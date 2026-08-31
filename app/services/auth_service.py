import os

from fastapi import HTTPException
from supabase import create_client

from app.core.security import create_access_token, hash_password, verify_password
from app.database import (
    SUPABASE_ANON_KEY,
    SUPABASE_KEY,
    SUPABASE_URL,
    supabase,
    supabase_admin,
)


def register_user(email, password, nickname):
    """Supabase Auth와 public.users 프로필을 함께 생성합니다."""
    try:
        auth_response = supabase.auth.sign_up({"email": email, "password": password})
        if auth_response.user is None:
            raise HTTPException(status_code=400, detail="인증 계정 생성 실패")
        user_id = auth_response.user.id
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"가입 실패: {str(exc)}") from exc

    hashed = hash_password(password)
    result = supabase.table("users").insert({
        "id": user_id,
        "email": email,
        "password_hash": hashed,
        "nickname": nickname,
        "role": "free",
    }).execute()
    return result.data[0]


def request_password_reset(email: str) -> None:
    """계정 존재 여부를 노출하지 않고 Supabase의 비밀번호 재설정 메일을 요청합니다."""
    try:
        auth_client = create_client(SUPABASE_URL, SUPABASE_KEY)
        auth_client.auth.reset_password_for_email(email)
    except Exception:
        # 계정 존재 여부, 메일 전송 설정, 공급자 오류를 외부에 노출하지 않습니다.
        pass


ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "hancum2@gmail.com").strip().lower()


def _supabase_auth_user(email: str, password: str):
    """운영 환경에서 유효한 Supabase Auth 키로 비밀번호를 확인합니다."""
    for auth_key in dict.fromkeys(
        key for key in (SUPABASE_ANON_KEY, SUPABASE_KEY) if key
    ):
        try:
            auth_client = create_client(SUPABASE_URL, auth_key)
            response = auth_client.auth.sign_in_with_password(
                {"email": email, "password": password}
            )
            if response.user is not None:
                return response.user
        except Exception:
            continue
    return None


def authenticate_user(email, password):
    """프로필과 Supabase Auth를 함께 검증하고 지정 관리자 프로필을 자동 복구합니다."""
    normalized_email = str(email).strip().lower()
    try:
        result = (
            supabase_admin.table("users")
            .select("*")
            .eq("email", normalized_email)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail="인증 서버에 연결할 수 없습니다.") from exc

    user = (result.data or [None])[0]
    profile_password_valid = bool(
        user
        and user.get("password_hash")
        and verify_password(password, user["password_hash"])
    )
    auth_user = None if profile_password_valid else _supabase_auth_user(
        normalized_email, password
    )
    if not profile_password_valid and auth_user is None:
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    # 프로필이 삭제되었거나 이전 데이터에 role이 빠진 경우, Auth가 성공한
    # 지정 관리자 계정만 서버 전용 클라이언트로 안전하게 복구합니다.
    if user is None:
        if auth_user is None:
            raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")
        user = {
            "id": str(auth_user.id),
            "email": normalized_email,
            "nickname": normalized_email.split("@", 1)[0][:18],
            "password_hash": hash_password(password),
            "role": "admin" if normalized_email == ADMIN_EMAIL else "free",
        }
        try:
            inserted = supabase_admin.table("users").insert(user).execute()
            user = (inserted.data or [user])[0]
        except Exception as exc:
            raise HTTPException(status_code=503, detail="관리자 프로필을 복구하지 못했습니다.") from exc

    if normalized_email == ADMIN_EMAIL and user.get("role") != "admin":
        try:
            updated = (
                supabase_admin.table("users")
                .update({"role": "admin"})
                .eq("id", user["id"])
                .execute()
            )
            user = (updated.data or [{**user, "role": "admin"}])[0]
        except Exception as exc:
            raise HTTPException(status_code=503, detail="관리자 권한을 복구하지 못했습니다.") from exc

    token = create_access_token({"sub": user["id"], "role": user.get("role", "free")})
    return token, user
