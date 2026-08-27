"""일일 시장 레포트 생성·발행 서비스.

이 모듈은 GitHub 예약 실행과 FastAPI 스케줄러에서 함께 호출됩니다.
외부 모델 호출이 실패해도 최신 시장 데이터 기반의 한국어 기본 브리핑을 발행해
피드가 장기간 비는 상황을 방지합니다.
"""

from __future__ import annotations

import json
import os
import re
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from supabase import Client, create_client

KST = ZoneInfo("Asia/Seoul")
DEFAULT_AUTHOR_ID = "8d8aed4f-97da-4cbb-b552-dd07215dbc62"
REPORT_CATEGORY = "레포트"

BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv(dotenv_path=os.path.join(BASE_DIR, ".env"))


def _supabase_client() -> Client:
    url = os.getenv("SUPABASE_URL")
    key = (
        os.getenv("SUPABASE_SECRET_KEY")
        or os.getenv("SUPABASE_ANON_KEY")
        or os.getenv("SUPABASE_KEY")
    )
    if not url or not key:
        raise RuntimeError("SUPABASE_URL 및 Supabase 서버 키가 필요합니다.")
    return create_client(url, key)


def _gemini_client() -> Any | None:
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        return None
    try:
        from google import genai

        return genai.Client(api_key=api_key)
    except Exception:
        return None


def _market_snapshot() -> list[dict[str, Any]]:
    """Yahoo Finance에서 최소한의 주요 지수 변동을 수집합니다."""
    try:
        import yfinance as yf
    except Exception:
        return []

    targets = [("코스피", "^KS11"), ("코스닥", "^KQ11"), ("S&P 500", "^GSPC"), ("나스닥", "^IXIC")]
    snapshot: list[dict[str, Any]] = []
    for name, ticker in targets:
        try:
            history = yf.Ticker(ticker).history(period="5d", auto_adjust=False)
            if history.empty or len(history) < 2:
                continue
            current = float(history["Close"].iloc[-1])
            previous = float(history["Close"].iloc[-2])
            if previous == 0:
                continue
            snapshot.append(
                {
                    "name": name,
                    "value": round(current, 2),
                    "change_pct": round(((current - previous) / previous) * 100, 2),
                }
            )
        except Exception:
            continue
    return snapshot


def _latest_report(client: Client) -> dict[str, Any] | None:
    try:
        response = (
            client.table("analysis_posts")
            .select("id,title,preview,content,created_at,published_at")
            .eq("is_published", True)
            .eq("category", REPORT_CATEGORY)
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
    except Exception:
        response = (
            client.table("analysis_posts")
            .select("id,title,preview,content,published_at")
            .eq("is_published", True)
            .eq("category", REPORT_CATEGORY)
            .order("published_at", desc=True)
            .limit(1)
            .execute()
        )
    return (response.data or [None])[0]


def _to_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed
    except (TypeError, ValueError):
        return None


def _clean_json(raw: str) -> dict[str, str] | None:
    raw = raw.strip().replace("```json", "").replace("```", "").strip()
    match = re.search(r"\{.*\}", raw, re.DOTALL)
    if not match:
        return None
    try:
        value = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    required = ("title", "preview", "content")
    if not isinstance(value, dict) or not all(str(value.get(key, "")).strip() for key in required):
        return None
    return {key: str(value[key]).strip() for key in required}


def _fallback_report(now: datetime, market: list[dict[str, Any]]) -> dict[str, str]:
    lines = [
        f"## 작성 시점\n{now.strftime('%Y년 %m월 %d일 %H:%M')} KST",
        "\n## 시장 현황\n자동 수집된 주요 지수의 직전 거래일 대비 변동입니다. 장중·휴장 상태에 따라 수치는 지연되거나 변동될 수 있습니다.",
    ]
    if market:
        for item in market:
            direction = "상승" if item["change_pct"] >= 0 else "하락"
            lines.append(
                f"- **{item['name']}**: {item['value']:,.2f} · {item['change_pct']:+.2f}% ({direction})"
            )
    else:
        lines.append("- 주요 지수 실시간 수집이 지연되고 있어 다음 자동 갱신에서 수치를 보완합니다.")
    lines.extend(
        [
            "\n## 오늘의 체크포인트",
            "- 글로벌 금리·물가 발표 일정과 주요국 정책 발언을 함께 확인하세요.",
            "- 단일 기사나 장중 등락만으로 투자 결정을 내리기보다 공시와 공식 자료를 교차 확인하세요.",
            "\n## 안내",
            "이 브리핑은 정보 제공 목적의 자동 요약이며 특정 종목의 매수·매도 또는 수익을 보장하지 않습니다.",
        ]
    )
    summary = " · ".join(f"{item['name']} {item['change_pct']:+.2f}%" for item in market[:3])
    return {
        "title": f"[일일 시장 브리핑] {now.strftime('%m월 %d일')} 자동 업데이트",
        "preview": summary or "주요 시장 지수와 오늘의 점검 항목을 정리한 자동 업데이트 브리핑입니다.",
        "content": "\n".join(lines),
    }


def _ai_report(
    previous: dict[str, Any] | None, now: datetime, market: list[dict[str, Any]]
) -> dict[str, str] | None:
    client = _gemini_client()
    if client is None:
        return None
    prior_summary = (previous or {}).get("preview") or "이전 레포트가 없습니다."
    market_text = ", ".join(
        f"{item['name']} {item['value']:,.2f} ({item['change_pct']:+.2f}%)" for item in market
    ) or "주요 지수 수집 지연"
    prompt = f"""
당신은 금융 정보 앱의 한국어 편집자입니다. 다음 자동 수집 시장 자료를 근거로,
과장·예측·매수·매도 권유 없이 독자가 확인할 핵심 맥락을 정리하세요.
작성 시점: {now.strftime('%Y-%m-%d %H:%M KST')}
주요 지수: {market_text}
이전 브리핑 요약: {prior_summary}

반드시 아래 키만 가진 유효한 JSON 한 개만 반환하세요.
{{"title":"40자 이내 한글 제목","preview":"160자 이내 한글 요약","content":"마크다운 본문"}}
본문은 '작성 시점', '시장 현황', '체크포인트', '안내'를 포함하고,
마지막 안내에는 정보 제공 목적이며 특정 종목 매수·매도·수익을 보장하지 않는다는 문장을 넣으세요.
"""
    try:
        response = client.models.generate_content(model="gemini-2.5-flash", contents=prompt)
        return _clean_json(response.text or "")
    except Exception:
        return None


def generate_and_upload_report(force: bool = False, min_interval_hours: int = 3) -> dict[str, Any]:
    """한국어 일일 레포트를 발행하고 결과를 반환합니다.

    최근 발행 후 `min_interval_hours` 이내이면 중복 발행하지 않습니다. `force=True`는
    운영자 수동 실행과 장애 복구에서만 사용합니다.
    """
    now = datetime.now(KST)
    try:
        client = _supabase_client()
        previous = _latest_report(client)
        previous_time = _to_datetime((previous or {}).get("created_at") or (previous or {}).get("published_at"))
        if not force and previous_time and now - previous_time.astimezone(KST) < timedelta(hours=min_interval_hours):
            return {
                "status": "skipped",
                "reason": "recent_report_exists",
                "latest_at": previous_time.isoformat(),
            }

        market = _market_snapshot()
        report = _ai_report(previous, now, market) or _fallback_report(now, market)
        data = {
            "title": report["title"],
            "preview": report["preview"],
            "content": report["content"],
            "category": REPORT_CATEGORY,
            "is_published": True,
            "access_type": "free",
            "author_id": os.getenv("SYSTEM_AUTHOR_ID", DEFAULT_AUTHOR_ID),
            "published_at": datetime.now(timezone.utc).isoformat(),
        }
        inserted = client.table("analysis_posts").insert(data).execute()
        created = (inserted.data or [data])[0]
        return {
            "status": "published",
            "id": created.get("id"),
            "title": data["title"],
            "market_items": len(market),
            "used_fallback": _gemini_client() is None,
        }
    except Exception as exc:
        return {"status": "failed", "error_type": type(exc).__name__}


if __name__ == "__main__":
    result = generate_and_upload_report(force=False)
    print(json.dumps(result, ensure_ascii=False))
    if result.get("status") == "failed":
        raise SystemExit(1)
