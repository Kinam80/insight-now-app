from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.database import supabase_admin as supabase

router = APIRouter(prefix="/chat", tags=["투자 커뮤니티"])

MAX_POSTS = 240
REACTION_EMOJIS = {"🔥", "👏", "📌", "🚀"}
BLOCKED_TERMS = ("자살", "죽어", "죽여", "한강 가", "혐오")


class MessageRequest(BaseModel):
    email: str = Field(min_length=1, max_length=40)
    content: str = Field(min_length=1, max_length=700)


class CommunityPostRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    kind: Literal["proof", "lounge", "prediction"]
    body: str = Field(min_length=1, max_length=700)
    ticker: str | None = Field(default=None, max_length=16)
    performance: float | None = Field(default=None, ge=-100.0, le=10000.0)


class CommunityReactionRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    post_id: str = Field(min_length=1, max_length=64)
    reaction: str = Field(min_length=1, max_length=2)


class CommunityCommentRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    post_id: str = Field(min_length=1, max_length=64)
    body: str = Field(min_length=1, max_length=400)


def _clean_text(value: str, limit: int) -> str:
    clean = re.sub(r"[\x00-\x1f\x7f]", " ", value or "")
    clean = re.sub(r"\s+", " ", clean).strip()
    if not clean:
        raise HTTPException(status_code=422, detail="내용을 입력해 주세요.")
    if any(term in clean.lower() for term in BLOCKED_TERMS):
        raise HTTPException(
            status_code=422,
            detail="안전한 투자 커뮤니티를 위해 공격적·위험 표현은 게시할 수 없습니다.",
        )
    return clean[:limit]


def _read_rows(limit: int = MAX_POSTS) -> list[dict[str, Any]]:
    try:
        response = (
            supabase.table("chat_messages")
            .select("id,user_email,content,created_at")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return list(response.data or [])
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail="커뮤니티 저장소를 준비 중입니다. 잠시 후 다시 시도해 주세요.",
        ) from exc


def _decode_row(row: dict[str, Any]) -> dict[str, Any]:
    raw_content = str(row.get("content") or "")
    try:
        payload = json.loads(raw_content)
        if isinstance(payload, dict) and payload.get("source") == "insight_now_community":
            return {**payload, "id": str(row.get("id") or ""), "created_at": row.get("created_at")}
    except (TypeError, ValueError):
        pass

    # 예전 일반 채팅도 라운지 글로 표시해 기존 대화가 사라지지 않도록 합니다.
    return {
        "id": str(row.get("id") or ""),
        "type": "post",
        "kind": "lounge",
        "nickname": str(row.get("user_email") or "익명 개미"),
        "body": raw_content,
        "ticker": None,
        "performance": None,
        "created_at": row.get("created_at"),
    }


def _encode_payload(payload: dict[str, Any]) -> str:
    return json.dumps({"source": "insight_now_community", "v": 1, **payload}, ensure_ascii=False)


def _community_snapshot(limit: int = 40) -> dict[str, Any]:
    rows = [_decode_row(row) for row in _read_rows()]
    posts = [row for row in rows if row.get("type") == "post"]
    reactions = [row for row in rows if row.get("type") == "reaction"]
    comments = [row for row in rows if row.get("type") == "comment"]

    reaction_map: dict[str, dict[str, int]] = {}
    comment_count: dict[str, int] = {}
    for reaction in reactions:
        post_id = str(reaction.get("post_id") or "")
        emoji = str(reaction.get("reaction") or "")
        if not post_id or emoji not in REACTION_EMOJIS:
            continue
        bucket = reaction_map.setdefault(post_id, {item: 0 for item in REACTION_EMOJIS})
        bucket[emoji] = bucket.get(emoji, 0) + 1
    for comment in comments:
        post_id = str(comment.get("post_id") or "")
        if post_id:
            comment_count[post_id] = comment_count.get(post_id, 0) + 1

    now = datetime.now(timezone.utc)
    feed: list[dict[str, Any]] = []
    for post in posts:
        post_id = str(post.get("id") or "")
        created_at_raw = str(post.get("created_at") or "")
        try:
            created_at = datetime.fromisoformat(created_at_raw.replace("Z", "+00:00"))
        except ValueError:
            created_at = now
        counts = reaction_map.get(post_id, {item: 0 for item in REACTION_EMOJIS})
        reaction_total = sum(counts.values())
        age_hours = max((now - created_at).total_seconds() / 3600, 1)
        score = round((reaction_total * 3 + comment_count.get(post_id, 0) * 2 + 1) / (age_hours**0.35), 2)
        feed.append(
            {
                "id": post_id,
                "kind": post.get("kind", "lounge"),
                "nickname": post.get("nickname", "익명 개미"),
                "body": post.get("body", ""),
                "ticker": post.get("ticker"),
                "performance": post.get("performance"),
                "created_at": post.get("created_at"),
                "reactions": counts,
                "reaction_total": reaction_total,
                "comment_count": comment_count.get(post_id, 0),
                "trending_score": score,
            }
        )

    feed.sort(key=lambda item: str(item.get("created_at") or ""), reverse=True)
    hall_of_fame = sorted(
        feed,
        key=lambda item: (item["trending_score"], item["reaction_total"]),
        reverse=True,
    )[:3]
    return {"posts": feed[:limit], "hall_of_fame": hall_of_fame}


@router.post("/messages")
def send_message(data: MessageRequest):
    """이전 채팅 클라이언트와의 호환용 메시지 전송 API입니다."""
    return supabase.table("chat_messages").insert(
        {"user_email": _clean_text(data.email, 40), "content": _clean_text(data.content, 700)}
    ).execute().data


@router.get("/messages")
def get_messages():
    """이전 채팅 클라이언트와의 호환용 메시지 목록 API입니다."""
    return list(reversed(_read_rows(120)))


@router.get("/community/feed")
def get_community_feed(limit: int = 40):
    snapshot = _community_snapshot(min(max(limit, 1), 60))
    return {"status": "success", **snapshot, "updated_at": datetime.now(timezone.utc).isoformat()}


@router.post("/community/posts")
def create_community_post(data: CommunityPostRequest):
    nickname = _clean_text(data.nickname, 18)
    body = _clean_text(data.body, 700)
    ticker = re.sub(r"[^A-Za-z0-9.^=-]", "", data.ticker or "").upper()[:16] or None
    payload = {
        "type": "post",
        "kind": data.kind,
        "nickname": nickname,
        "body": body,
        "ticker": ticker,
        "performance": data.performance if data.kind == "proof" else None,
    }
    response = supabase.table("chat_messages").insert(
        {"user_email": nickname, "content": _encode_payload(payload)}
    ).execute()
    return {"status": "created", "post": _decode_row((response.data or [{}])[0])}


@router.post("/community/reactions")
def add_community_reaction(data: CommunityReactionRequest):
    if data.reaction not in REACTION_EMOJIS:
        raise HTTPException(status_code=422, detail="지원하지 않는 반응입니다.")
    nickname = _clean_text(data.nickname, 18)
    snapshot = _community_snapshot(60)
    if not any(post["id"] == data.post_id for post in snapshot["posts"]):
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")

    # 최근 저장분 안에서 같은 사람이 같은 글에 중복 반응하는 것을 막습니다.
    for row in [_decode_row(row) for row in _read_rows()]:
        if (
            row.get("type") == "reaction"
            and row.get("post_id") == data.post_id
            and row.get("nickname") == nickname
        ):
            return {"status": "already_reacted", "feed": _community_snapshot(40)}

    supabase.table("chat_messages").insert(
        {
            "user_email": nickname,
            "content": _encode_payload(
                {"type": "reaction", "post_id": data.post_id, "nickname": nickname, "reaction": data.reaction}
            ),
        }
    ).execute()
    return {"status": "created", "feed": _community_snapshot(40)}


@router.post("/community/comments")
def add_community_comment(data: CommunityCommentRequest):
    nickname = _clean_text(data.nickname, 18)
    body = _clean_text(data.body, 400)
    snapshot = _community_snapshot(60)
    if not any(post["id"] == data.post_id for post in snapshot["posts"]):
        raise HTTPException(status_code=404, detail="게시글을 찾을 수 없습니다.")
    supabase.table("chat_messages").insert(
        {
            "user_email": nickname,
            "content": _encode_payload(
                {"type": "comment", "post_id": data.post_id, "nickname": nickname, "body": body}
            ),
        }
    ).execute()
    return {"status": "created", "feed": _community_snapshot(40)}
