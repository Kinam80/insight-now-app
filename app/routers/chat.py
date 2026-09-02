from __future__ import annotations

import asyncio
import json
import re
import time
import random
from datetime import datetime, timedelta, timezone
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from app.database import supabase_admin as supabase

router = APIRouter(prefix="/chat", tags=["투자 커뮤니티"])

MAX_POSTS = 240
REACTION_EMOJIS = {"🔥", "👏", "📌", "🚀"}
BLOCKED_TERMS = ("자살", "죽어", "죽여", "한강 가", "혐오")
LIVE_MESSAGE_COOLDOWN_SECONDS = 12
DAILY_POINT_CAP = 60
GAME_MAX_WAGER = 20
GAME_DAILY_WAGER_CAP = 100
SLOT_MAX_WAGER = GAME_MAX_WAGER
SLOT_DAILY_WAGER_CAP = GAME_DAILY_WAGER_CAP
SLOT_SYMBOLS = ("🍒", "🔔", "⭐", "💎", "7️⃣")
SLOT_MULTIPLIERS = {"🍒": 3, "🔔": 5, "⭐": 8, "💎": 12, "7️⃣": 20}
GAME_RULES = {
    "slot777": {
        "name": "9칸 일확천금 777",
        "max_wager": GAME_MAX_WAGER,
        "daily_wager_cap": GAME_DAILY_WAGER_CAP,
        "notice": "일반 보드 88% · 당첨 보드 12%, 당첨 보드 배율은 5·10·20배입니다.",
        "probabilities": {"일반 보드": 88, "당첨 보드": 12},
    },
    "dropball": {
        "name": "드랍볼 곱하기 파이낸스",
        "max_wager": GAME_MAX_WAGER,
        "daily_wager_cap": GAME_DAILY_WAGER_CAP,
        "notice": "꽝·1배 구간이 넓고 고배율 구간은 좁은 공개 확률표를 사용합니다.",
        "probabilities": {"꽝": 40, "1배": 35, "2배": 12, "3배": 8, "5배": 4, "10배": 1},
    },
    "runner": {
        "name": "동물 상자 러닝 배틀",
        "max_wager": GAME_MAX_WAGER,
        "daily_wager_cap": GAME_DAILY_WAGER_CAP,
        "notice": "각 상자 폭탄 확률 45% · 안전 구간에서 0·1·2·4배 보상이 공개됩니다.",
        "probabilities": {"폭탄": 45, "안전": 55, "안전 보상 0배": 35, "안전 보상 1배": 48, "안전 보상 2배": 14, "안전 보상 4배": 3},
    },
}
POINT_RULES = {
    "community_post": (20, "투자 기록 작성"),
    "community_comment": (5, "건설적 대화 참여"),
    "live_message": (2, "실시간 라운지 참여"),
}
LEVELS: tuple[tuple[int, str, str], ...] = (
    (0, "새싹 개미", "🌱"),
    (60, "시장 관찰자", "🔎"),
    (180, "인사이트 메이커", "💡"),
    (420, "수익 인증러", "📈"),
    (900, "머니톡 마스터", "🏆"),
)
_recent_live_messages: dict[str, float] = {}


class LiveConnectionManager:
    """단일 웹 인스턴스의 실시간 라운지 연결을 관리합니다.

    메시지는 Supabase에도 즉시 저장하므로 연결이 끊겨도 HTTP 기록 피드로 복구됩니다.
    """

    def __init__(self) -> None:
        self._connections: set[WebSocket] = set()

    @property
    def online_count(self) -> int:
        return len(self._connections)

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self._connections.add(websocket)

    def disconnect(self, websocket: WebSocket) -> None:
        self._connections.discard(websocket)

    async def broadcast(self, payload: dict[str, Any]) -> None:
        stale: list[WebSocket] = []
        for connection in tuple(self._connections):
            try:
                await connection.send_json(payload)
            except Exception:
                stale.append(connection)
        for connection in stale:
            self.disconnect(connection)


live_connections = LiveConnectionManager()


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


class LiveMessageRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    body: str = Field(min_length=1, max_length=300)


class SlotSpinRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    wager: int = Field(ge=1, le=GAME_MAX_WAGER)


class DropballRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    wager: int = Field(ge=1, le=GAME_MAX_WAGER)


class RunnerRequest(BaseModel):
    nickname: str = Field(min_length=2, max_length=18)
    wager: int = Field(ge=1, le=GAME_MAX_WAGER)
    animal: Literal["고양이", "강아지", "여우", "토끼"] = "고양이"


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


def _level_for(points: int) -> dict[str, Any]:
    level_index = 0
    for index, (minimum, _, _) in enumerate(LEVELS):
        if points >= minimum:
            level_index = index
    minimum, title, badge = LEVELS[level_index]
    next_minimum = LEVELS[level_index + 1][0] if level_index + 1 < len(LEVELS) else None
    return {
        "level": level_index + 1,
        "title": title,
        "badge": badge,
        "points": points,
        "current_level_min": minimum,
        "next_level_points": next_minimum,
    }


def _reward_profile(nickname: str) -> dict[str, Any]:
    safe_nickname = _clean_text(nickname, 18)
    rewards = [
        row
        for row in (_decode_row(item) for item in _read_rows(MAX_POSTS))
        if row.get("type") == "reward" and row.get("nickname") == safe_nickname
    ]
    total = sum(int(row.get("points") or 0) for row in rewards)
    return {"nickname": safe_nickname, **_level_for(total)}


def _award_points(nickname: str, action: str) -> dict[str, Any]:
    """동일 일자에 과도한 반복 활동으로 포인트가 쌓이지 않도록 상한을 적용합니다."""
    safe_nickname = _clean_text(nickname, 18)
    requested, reason = POINT_RULES[action]
    today = datetime.now(timezone.utc).date()
    today_earned = 0
    for row in (_decode_row(item) for item in _read_rows(MAX_POSTS)):
        if row.get("type") != "reward" or row.get("nickname") != safe_nickname:
            continue
        try:
            created = datetime.fromisoformat(str(row.get("created_at")).replace("Z", "+00:00"))
        except ValueError:
            continue
        if created.date() == today:
            today_earned += max(0, int(row.get("points") or 0))
    awarded = max(0, min(requested, DAILY_POINT_CAP - today_earned))
    if awarded:
        supabase.table("chat_messages").insert(
            {
                "user_email": safe_nickname,
                "content": _encode_payload(
                    {
                        "type": "reward",
                        "nickname": safe_nickname,
                        "points": awarded,
                        "reason": reason,
                        "action": action,
                    }
                ),
            }
        ).execute()
    profile = _reward_profile(safe_nickname)
    return {**profile, "awarded": awarded, "reason": reason}


def _community_leaderboard(limit: int = 20) -> list[dict[str, Any]]:
    """최근 활동 기준의 명예 포인트 순위를 제공합니다.

    현행 레거시 저장 구조는 chat_messages를 사용하므로, 대규모 공개 런칭 전에는
    별도 reward ledger 테이블과 인증 사용자 ID로 이전해야 합니다.
    """
    totals: dict[str, int] = {}
    for row in (_decode_row(item) for item in _read_rows(MAX_POSTS)):
        if row.get("type") != "reward":
            continue
        nickname = str(row.get("nickname") or "").strip()
        if nickname:
            totals[nickname] = totals.get(nickname, 0) + int(row.get("points") or 0)
    leaderboard = [
        {"nickname": nickname, **_level_for(max(0, points))}
        for nickname, points in totals.items()
    ]
    leaderboard.sort(key=lambda profile: int(profile["points"]), reverse=True)
    return leaderboard[: min(max(limit, 1), 50)]


def admin_adjust_points(nickname: str, delta: int, reason: str) -> dict[str, Any]:
    """관리자 전용의 비현금성 명예 포인트 수동 조정입니다."""
    safe_nickname = _clean_text(nickname, 18)
    safe_reason = _clean_text(reason, 80)
    if not delta:
        raise HTTPException(status_code=422, detail="조정할 포인트를 입력해 주세요.")
    current = max(0, int(_reward_profile(safe_nickname)["points"]))
    # 차감은 현재 잔액을 넘지 않도록 음수 방향으로 제한합니다.
    applied_delta = max(-current, delta) if delta < 0 else delta
    if not applied_delta:
        raise HTTPException(status_code=422, detail="현재 포인트보다 더 많이 차감할 수 없습니다.")
    supabase.table("chat_messages").insert(
        {
            "user_email": safe_nickname,
            "content": _encode_payload(
                {
                    "type": "reward",
                    "nickname": safe_nickname,
                    "points": applied_delta,
                    "reason": f"관리자 조정: {safe_reason}",
                    "action": "admin_adjustment",
                }
            ),
        }
    ).execute()
    return {
        "nickname": safe_nickname,
        "adjusted": applied_delta,
        "reason": safe_reason,
        **_reward_profile(safe_nickname),
    }


def _live_message_from_payload(payload: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": str(payload.get("id") or ""),
        "nickname": str(payload.get("nickname") or "익명 개미"),
        "body": str(payload.get("body") or ""),
        "created_at": payload.get("created_at"),
        "profile": payload.get("profile") or _level_for(0),
    }


def _create_live_message(nickname: str, body: str) -> dict[str, Any]:
    safe_nickname = _clean_text(nickname, 18)
    safe_body = _clean_text(body, 300)
    now_monotonic = time.monotonic()
    last_sent = _recent_live_messages.get(safe_nickname, 0.0)
    if now_monotonic - last_sent < LIVE_MESSAGE_COOLDOWN_SECONDS:
        raise HTTPException(
            status_code=429,
            detail=f"라운지 메시지는 {LIVE_MESSAGE_COOLDOWN_SECONDS}초 간격으로 보낼 수 있습니다.",
        )
    _recent_live_messages[safe_nickname] = now_monotonic
    reward = _award_points(safe_nickname, "live_message")
    response = supabase.table("chat_messages").insert(
        {
            "user_email": safe_nickname,
            "content": _encode_payload(
                {
                    "type": "live_chat",
                    "nickname": safe_nickname,
                    "body": safe_body,
                    "profile": _level_for(int(reward["points"])),
                }
            ),
        }
    ).execute()
    message = _live_message_from_payload(_decode_row((response.data or [{}])[0]))
    message["reward"] = reward
    return message


def _live_history(limit: int = 50) -> list[dict[str, Any]]:
    messages = [
        _live_message_from_payload(row)
        for row in (_decode_row(item) for item in _read_rows(MAX_POSTS))
        if row.get("type") == "live_chat"
    ]
    messages.sort(key=lambda item: str(item.get("created_at") or ""))
    return messages[-min(max(limit, 1), 80) :]


def _community_snapshot(limit: int = 40) -> dict[str, Any]:
    rows = [_decode_row(row) for row in _read_rows()]
    posts = [row for row in rows if row.get("type") == "post"]
    reactions = [row for row in rows if row.get("type") == "reaction"]
    comments = [row for row in rows if row.get("type") == "comment"]

    reaction_map: dict[str, dict[str, int]] = {}
    comment_count: dict[str, int] = {}
    comment_map: dict[str, list[dict[str, Any]]] = {}
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
            comment_map.setdefault(post_id, []).append(
                {
                    "id": str(comment.get("id") or ""),
                    "nickname": str(comment.get("nickname") or "익명 개미"),
                    "body": str(comment.get("body") or ""),
                    "created_at": comment.get("created_at"),
                }
            )

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
                "comments": list(reversed(comment_map.get(post_id, [])))[:30],
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


@router.get("/community/profile/{nickname}")
def get_community_profile(nickname: str):
    return {"status": "success", "profile": _reward_profile(nickname)}


def _game_wager_used_today(nickname: str) -> int:
    today = datetime.now(timezone.utc).date()
    used = 0
    for row in (_decode_row(item) for item in _read_rows(MAX_POSTS)):
        if row.get("type") != "reward" or row.get("action") not in {"slot_spin", "dropball", "runner"}:
            continue
        if row.get("nickname") != nickname:
            continue
        try:
            created = datetime.fromisoformat(str(row.get("created_at")).replace("Z", "+00:00"))
        except ValueError:
            continue
        if created.date() == today:
            used += max(0, int(row.get("wager") or 0))
    return used


# 이전 이름을 유지해 기존 테스트·클라이언트와 호환합니다.
def _slot_wager_used_today(nickname: str) -> int:
    return _game_wager_used_today(nickname)


def _validate_game_wager(nickname: str, wager: int) -> tuple[str, dict[str, Any], int]:
    safe_nickname = _clean_text(nickname, 18)
    if wager < 1 or wager > GAME_MAX_WAGER:
        raise HTTPException(status_code=422, detail=f"한 번에 {GAME_MAX_WAGER}P까지 사용할 수 있습니다.")
    profile = _reward_profile(safe_nickname)
    balance = max(0, int(profile["points"]))
    if balance < wager:
        raise HTTPException(status_code=422, detail=f"포인트가 부족합니다. 현재 잔액은 {balance}P입니다.")
    used_today = _game_wager_used_today(safe_nickname)
    if used_today + wager > GAME_DAILY_WAGER_CAP:
        raise HTTPException(status_code=429, detail=f"게임은 하루 {GAME_DAILY_WAGER_CAP}P까지 이용할 수 있습니다.")
    return safe_nickname, profile, used_today


def _record_game(nickname: str, game: str, wager: int, net: int, payload: dict[str, Any]) -> dict[str, Any]:
    supabase.table("chat_messages").insert(
        {
            "user_email": nickname,
            "content": _encode_payload(
                {
                    "type": "reward",
                    "nickname": nickname,
                    "points": net,
                    "reason": payload.get("reason", GAME_RULES[game]["name"]),
                    "action": game if game != "slot777" else "slot_spin",
                    "game": game,
                    "wager": wager,
                    "payout": max(0, int(payload.get("payout") or 0)),
                    **payload,
                }
            ),
        }
    ).execute()
    used_today = _game_wager_used_today(nickname)
    return {**payload, "wager": wager, "net": net, "daily_wager_used": used_today, "daily_wager_cap": GAME_DAILY_WAGER_CAP, "profile": _reward_profile(nickname)}


def _slot777_board() -> tuple[list[str], list[int], int]:
    rng = random.SystemRandom()
    board = [rng.choice(SLOT_SYMBOLS) for _ in range(9)]
    # 당첨 여부를 먼저 공개 규칙에 맞춰 결정합니다. 기본 보드는 모든 줄을 깨뜨립니다.
    if rng.random() >= 0.12:
        for line in ((0, 1, 2), (3, 4, 5), (6, 7, 8), (0, 3, 6), (1, 4, 7), (2, 5, 8), (0, 4, 8), (2, 4, 6)):
            if board[line[0]] == board[line[1]] == board[line[2]]:
                board[line[2]] = next(symbol for symbol in SLOT_SYMBOLS if symbol != board[line[0]])
        return board, [], 0
    symbol = rng.choice(SLOT_SYMBOLS)
    line = rng.choice(((0, 1, 2), (3, 4, 5), (6, 7, 8), (0, 3, 6), (1, 4, 7), (2, 5, 8), (0, 4, 8), (2, 4, 6)))
    for index in line:
        board[index] = symbol
    return board, list(line), {"🍒": 5, "🔔": 5, "⭐": 10, "💎": 10, "7️⃣": 20}[symbol]


def play_slot777(nickname: str, wager: int) -> dict[str, Any]:
    safe_nickname, _, used_today = _validate_game_wager(nickname, wager)
    board, winning_line, multiplier = _slot777_board()
    payout = wager * multiplier
    return _record_game(safe_nickname, "slot777", wager, payout - wager, {"board": board, "winning_line": winning_line, "multiplier": multiplier, "payout": payout, "reason": f"9칸 777 · {multiplier}배", "rules": GAME_RULES["slot777"], "daily_wager_used_before": used_today})


def play_dropball(nickname: str, wager: int) -> dict[str, Any]:
    safe_nickname, _, used_today = _validate_game_wager(nickname, wager)
    rng = random.SystemRandom()
    buckets = [("꽝", 0, 0.22), ("꽝", 0, 0.18), ("1배", 1, 0.20), ("1배", 1, 0.15), ("2배", 2, 0.12), ("3배", 3, 0.08), ("5배", 5, 0.04), ("10배", 10, 0.01)]
    label, multiplier, _ = rng.choices(buckets, weights=[item[2] for item in buckets], k=1)[0]
    bucket_index = rng.randrange(8)
    path = [{"x": 50, "y": 0}]
    x = 50.0
    for step in range(1, 13):
        x = max(8.0, min(92.0, x + rng.uniform(-11.0, 11.0)))
        path.append({"x": round(x, 2), "y": round(step / 12 * 100, 2)})
    payout = wager * multiplier
    return _record_game(safe_nickname, "dropball", wager, payout - wager, {"path": path, "bucket_index": bucket_index, "bucket_label": label, "multiplier": multiplier, "payout": payout, "reason": f"드랍볼 · {label}", "rules": GAME_RULES["dropball"], "daily_wager_used_before": used_today})


def play_runner(nickname: str, wager: int, animal: str) -> dict[str, Any]:
    safe_nickname, _, used_today = _validate_game_wager(nickname, wager)
    rng = random.SystemRandom()
    events: list[dict[str, Any]] = []
    bomb = False
    multiplier = 0
    for step in range(1, 7):
        if rng.random() < 0.45:
            events.append({"step": step, "kind": "bomb", "label": "폭탄 상자"})
            bomb = True
            break
        step_multiplier = rng.choices([0, 1, 2, 4], weights=[0.35, 0.48, 0.14, 0.03], k=1)[0]
        multiplier = max(multiplier, step_multiplier)
        events.append({"step": step, "kind": "safe", "label": "보상 상자", "multiplier": step_multiplier})
    payout = 0 if bomb else wager * multiplier
    return _record_game(safe_nickname, "runner", wager, payout - wager, {"animal": animal, "events": events, "game_over": bomb, "multiplier": 0 if bomb else multiplier, "payout": payout, "reason": "러닝 배틀 · 폭탄 상자" if bomb else f"러닝 배틀 · {multiplier}배", "rules": GAME_RULES["runner"], "daily_wager_used_before": used_today})


@router.get("/community/game/profile/{nickname}")
def get_game_profile(nickname: str):
    return {"status": "success", "profile": _reward_profile(nickname), "rules": list(GAME_RULES.values())}


@router.get("/community/game/rules")
def get_game_rules():
    return {"status": "success", "games": GAME_RULES, "notice": "현금화·환전·양도 불가 포인트 전용 게임이며 확률표는 운영 정책에 공개됩니다."}


@router.post("/community/game/slot")
def spin_money_slot(data: SlotSpinRequest):
    # 기존 3칸 API 경로는 새 9칸 게임으로 연결합니다.
    return {"status": "created", "game": play_slot777(data.nickname, data.wager)}


@router.post("/community/game/slot777")
def spin_slot777(data: SlotSpinRequest):
    return {"status": "created", "game": play_slot777(data.nickname, data.wager)}


@router.post("/community/game/dropball")
def spin_dropball(data: DropballRequest):
    return {"status": "created", "game": play_dropball(data.nickname, data.wager)}


@router.post("/community/game/runner")
def run_runner(data: RunnerRequest):
    return {"status": "created", "game": play_runner(data.nickname, data.wager, data.animal)}


@router.get("/community/live/messages")
def get_live_messages(limit: int = 50):
    return {
        "status": "success",
        "messages": _live_history(limit),
        "online_count": live_connections.online_count,
    }


@router.post("/community/live/messages")
async def send_live_message(data: LiveMessageRequest):
    message = await asyncio.to_thread(_create_live_message, data.nickname, data.body)
    await live_connections.broadcast(
        {"type": "live_message", "message": message, "online_count": live_connections.online_count}
    )
    return {"status": "created", "message": message}


@router.websocket("/community/live")
async def live_lounge_socket(websocket: WebSocket):
    await live_connections.connect(websocket)
    try:
        history = await asyncio.to_thread(_live_history, 50)
        await websocket.send_json(
            {
                "type": "connected",
                "messages": history,
                "online_count": live_connections.online_count,
                "heartbeat_seconds": 25,
            }
        )
        await live_connections.broadcast(
            {"type": "presence", "online_count": live_connections.online_count}
        )
        while True:
            incoming = await websocket.receive_json()
            event_type = str(incoming.get("type") or "")
            if event_type == "ping":
                await websocket.send_json({"type": "pong"})
                continue
            if event_type != "send":
                await websocket.send_json({"type": "error", "message": "지원하지 않는 라운지 요청입니다."})
                continue
            try:
                message = await asyncio.to_thread(
                    _create_live_message,
                    str(incoming.get("nickname") or ""),
                    str(incoming.get("body") or ""),
                )
                await live_connections.broadcast(
                    {"type": "live_message", "message": message, "online_count": live_connections.online_count}
                )
            except HTTPException as exc:
                await websocket.send_json({"type": "error", "message": str(exc.detail)})
    except WebSocketDisconnect:
        pass
    finally:
        live_connections.disconnect(websocket)
        await live_connections.broadcast(
            {"type": "presence", "online_count": live_connections.online_count}
        )


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
    reward = _award_points(nickname, "community_post")
    return {
        "status": "created",
        "post": _decode_row((response.data or [{}])[0]),
        "reward": reward,
    }


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
    reward = _award_points(nickname, "community_comment")
    return {"status": "created", "feed": _community_snapshot(40), "reward": reward}
