from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Literal

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException
from pydantic import BaseModel, EmailStr, Field

from app.core.security import decode_access_token, hash_password
from app.database import supabase_admin as supabase
from app.routers.chat import _community_leaderboard, _community_snapshot, _live_history, admin_adjust_points

router = APIRouter(prefix="/admin", tags=["관리자 콘솔"])


class UserUpdateRequest(BaseModel):
    email: EmailStr | None = None
    role: Literal["free", "premium", "admin"] | None = None
    nickname: str | None = Field(default=None, min_length=2, max_length=18)


class PasswordResetRequest(BaseModel):
    new_password: str = Field(min_length=8, max_length=128)


class PointAdjustmentRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    delta: int = Field(ge=-5000, le=5000)
    reason: str = Field(min_length=2, max_length=80)


def require_admin(authorization: str | None = Header(default=None)) -> dict:
    """JWT와 현재 DB 역할을 함께 검증하는 관리자 권한 의존성입니다."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="관리자 로그인이 필요합니다.")
    payload = decode_access_token(authorization.split(" ", 1)[1].strip())
    if not payload or not payload.get("sub") or payload.get("role") != "admin":
        raise HTTPException(status_code=403, detail="관리자 권한이 없습니다.")
    try:
        result = (
            supabase.table("users")
            .select("id, email, role")
            .eq("id", payload["sub"])
            .limit(1)
            .execute()
        )
        account = (result.data or [None])[0]
    except Exception as exc:
        raise HTTPException(status_code=503, detail="관리자 권한을 확인할 수 없습니다.") from exc
    if not account or account.get("role") != "admin":
        raise HTTPException(status_code=403, detail="현재 관리자 권한이 없습니다.")
    return {**payload, "email": account.get("email")}


def _user_rows(limit: int = 200) -> list[dict]:
    try:
        result = (
            supabase.table("users")
            .select("id, email, nickname, role, created_at")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return list(result.data or [])
    except Exception as exc:
        raise HTTPException(status_code=503, detail="회원 정보를 불러올 수 없습니다.") from exc


@router.get("/stats")
def get_admin_stats(_: dict = Depends(require_admin)):
    users = _user_rows()
    try:
        published_posts = (
            supabase.table("analysis_posts")
            .select("id", count="exact")
            .eq("is_published", True)
            .limit(1)
            .execute()
        )
        post_count = int(published_posts.count or 0)
    except Exception:
        post_count = 0
    try:
        payment_rows = supabase.table("payments").select("amount, status").limit(500).execute().data or []
        completed = [row for row in payment_rows if str(row.get("status", "")).lower() in {"done", "paid", "success"}]
        revenue = sum(int(row.get("amount") or 0) for row in completed)
    except Exception:
        revenue = 0
    snapshot = _community_snapshot(60)
    live_messages = _live_history(80)
    return {
        "status": "success",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_users": len(users),
        "free_users": sum(1 for user in users if user.get("role") == "free"),
        "premium_users": sum(1 for user in users if user.get("role") == "premium"),
        "admin_users": sum(1 for user in users if user.get("role") == "admin"),
        "total_revenue": revenue,
        "total_posts": post_count,
        "community_posts": len(snapshot["posts"]),
        "recent_live_messages": len(live_messages),
    }


@router.get("/users")
def get_users(limit: int = 200, _: dict = Depends(require_admin)):
    return {"status": "success", "users": _user_rows(min(max(limit, 1), 500))}


@router.patch("/users/{user_id}")
def update_user(user_id: str, data: UserUpdateRequest, _: dict = Depends(require_admin)):
    changes = data.model_dump(exclude_none=True)
    if not changes:
        raise HTTPException(status_code=422, detail="변경할 회원 정보가 없습니다.")
    try:
        if "email" in changes:
            supabase.auth.admin.update_user_by_id(
                user_id, {"email": str(changes["email"]), "email_confirm": True}
            )
        result = supabase.table("users").update(changes).eq("id", user_id).execute()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="회원 정보를 변경하지 못했습니다.") from exc
    if not result.data:
        raise HTTPException(status_code=404, detail="회원을 찾을 수 없습니다.")
    return {"status": "updated", "user": result.data[0]}


@router.post("/users/{user_id}/reset-password")
def reset_user_password(user_id: str, data: PasswordResetRequest, _: dict = Depends(require_admin)):
    """관리자가 회원의 로그인 비밀번호를 재설정합니다. 비밀번호 원문은 저장·반환하지 않습니다."""
    try:
        supabase.auth.admin.update_user_by_id(user_id, {"password": data.new_password})
        result = (
            supabase.table("users")
            .update({"password_hash": hash_password(data.new_password)})
            .eq("id", user_id)
            .execute()
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail="비밀번호를 재설정하지 못했습니다.") from exc
    if not result.data:
        raise HTTPException(status_code=404, detail="회원을 찾을 수 없습니다.")
    return {"status": "updated", "message": "비밀번호가 재설정되었습니다."}


@router.delete("/users/{user_id}")
def delete_user_account(user_id: str, admin: dict = Depends(require_admin)):
    """회원 탈퇴를 수행합니다. 현재 로그인한 관리자는 자기 계정을 삭제할 수 없습니다."""
    if user_id == admin.get("sub"):
        raise HTTPException(status_code=409, detail="현재 로그인한 관리자 계정은 여기서 삭제할 수 없습니다.")
    try:
        existing = supabase.table("users").select("id").eq("id", user_id).limit(1).execute()
        if not existing.data:
            raise HTTPException(status_code=404, detail="회원을 찾을 수 없습니다.")
        supabase.auth.admin.delete_user(user_id)
        supabase.table("users").delete().eq("id", user_id).execute()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="회원 탈퇴를 처리하지 못했습니다.") from exc
    return {"status": "deleted", "message": "회원 계정이 삭제되었습니다."}


@router.get("/community/leaderboard")
def get_community_leaderboard(limit: int = 20, _: dict = Depends(require_admin)):
    return {
        "status": "success",
        "leaderboard": _community_leaderboard(limit),
        "notice": "머니 포인트는 현금화·양도·거래가 불가능한 명예·배지용 포인트입니다.",
    }


@router.post("/community/points")
def adjust_community_points(data: PointAdjustmentRequest, _: dict = Depends(require_admin)):
    profile = admin_adjust_points(data.nickname, data.delta, data.reason)
    return {"status": "updated", "profile": profile}


@router.get("/automation/status")
def get_automation_status(_: dict = Depends(require_admin)):
    from app.main import automation_status

    return {
        "status": "success",
        "jobs": automation_status,
        "gemini": {
            "configured": bool(os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")),
            "mode": "Gemini 전용 · 이전 레포트 연속성 분석",
            "notice": "API 키 원문은 서버 또는 화면에서 조회·표시되지 않습니다.",
        },
    }


@router.post("/automation/{job_name}/run")
async def run_automation_job(
    job_name: Literal["news", "daily_reports", "etfs", "government_reports"],
    background_tasks: BackgroundTasks,
    _: dict = Depends(require_admin),
):
    from app.main import (
        refresh_daily_reports_in_background,
        refresh_etfs_in_background,
        refresh_gov_reports_in_background,
        refresh_news_in_background,
    )

    task_map = {
        "news": refresh_news_in_background,
        "daily_reports": refresh_daily_reports_in_background,
        "etfs": refresh_etfs_in_background,
        "government_reports": refresh_gov_reports_in_background,
    }
    background_tasks.add_task(task_map[job_name])
    return {"status": "queued", "job": job_name, "message": "자동화 작업을 시작했습니다."}


@router.get("/")
def read_admin(_: dict = Depends(require_admin)):
    return {"status": "success", "message": "관리자 콘솔 권한이 확인되었습니다."}
