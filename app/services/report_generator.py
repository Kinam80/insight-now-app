"""이전 분석의 연속성을 유지하는 한국어 일일 레포트 발행 서비스.

GitHub 예약 실행과 FastAPI 서버 스케줄러가 공통으로 호출합니다. Gemini가
정교한 분석을 정상 생성·검증한 경우에만 공개 발행하며, 모델 또는 입력 데이터에
문제가 생기면 공개 피드에는 임시 문구를 올리지 않고 운영 상태를 `deferred`로 남깁니다.
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
PLACEHOLDER_TITLE_PREFIX = "[일일 시장 브리핑]"

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
    """Yahoo Finance에서 레포트의 검증 가능한 주요 지수 변동을 수집합니다."""
    try:
        import yfinance as yf
    except Exception:
        return []

    targets = [
        ("코스피", "^KS11"),
        ("코스닥", "^KQ11"),
        ("S&P 500", "^GSPC"),
        ("나스닥", "^IXIC"),
        ("미 10년물 국채", "^TNX"),
    ]
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


def _report_candidates(client: Client) -> list[dict[str, Any]]:
    fields = "id,title,preview,content,created_at,published_at"
    try:
        response = (
            client.table("analysis_posts")
            .select(fields)
            .eq("is_published", True)
            .eq("category", REPORT_CATEGORY)
            .order("created_at", desc=True)
            .limit(8)
            .execute()
        )
    except Exception:
        response = (
            client.table("analysis_posts")
            .select("id,title,preview,content,published_at")
            .eq("is_published", True)
            .eq("category", REPORT_CATEGORY)
            .order("published_at", desc=True)
            .limit(8)
            .execute()
        )
    return response.data or []


def _latest_quality_report(client: Client) -> dict[str, Any] | None:
    """공개 테스트성 자동 브리핑을 제외한 가장 최근의 분석 레포트를 가져옵니다."""
    for report in _report_candidates(client):
        if not str(report.get("title", "")).startswith(PLACEHOLDER_TITLE_PREFIX):
            return report
    return None


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


def _recent_korean_news(client: Client, limit: int = 8) -> list[dict[str, str]]:
    """이미 한국어화된 앱 뉴스만 레포트의 사실 입력으로 사용합니다."""
    try:
        response = (
            client.table("ai_news")
            .select("title,summary,created_at,source_url")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
    except Exception:
        return []

    items: list[dict[str, str]] = []
    for raw in response.data or []:
        title = str(raw.get("title") or "").strip()
        summary = str(raw.get("summary") or "").strip()
        if title:
            items.append(
                {
                    "title": title[:240],
                    "summary": summary[:520],
                    "created_at": str(raw.get("created_at") or ""),
                }
            )
    return items


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
    title = str(value["title"]).strip()[:120]
    preview = str(value["preview"]).strip()[:600]
    content = str(value["content"]).strip()
    if len(content) < 300:
        return None
    return {"title": title, "preview": preview, "content": content}


def _ai_report(
    previous: dict[str, Any] | None,
    now: datetime,
    market: list[dict[str, Any]],
    recent_news: list[dict[str, str]],
) -> dict[str, str] | None:
    """기존 레포트 흐름을 이어받는 정교한 Gemini 분석을 생성합니다."""
    client = _gemini_client()
    if client is None:
        return None

    previous_content = str((previous or {}).get("content") or "이전 분석 레포트가 없습니다.")
    previous_title = str((previous or {}).get("title") or "이전 레포트 없음")
    # 전후 맥락은 유지하되 API 입력을 지나치게 키우지 않습니다.
    previous_context = previous_content[-9000:]
    market_text = "\n".join(
        f"- {item['name']}: {item['value']:,.2f} ({item['change_pct']:+.2f}% · 직전 거래일 대비)"
        for item in market
    ) or "- 주요 지수 수집 지연: 수치가 없는 항목은 단정하지 말 것"
    news_text = "\n".join(
        f"- [{index + 1}] {item['title']}\n  요약: {item['summary']}\n  수집시각: {item['created_at']}"
        for index, item in enumerate(recent_news)
    ) or "- 최신 뉴스 입력이 부족하므로 확인되지 않은 사건·수치·발언을 만들지 말 것"
    time_slot_instruction = (
        "이번 회차는 오후장 레포트입니다. 오늘 오전 레포트 및 직전 레포트와 비교해 흐름의 변화를 구체적으로 설명하세요."
        if now.hour >= 15
        else "직전 레포트와 비교해 시장 추세가 지속인지 반전인지 근거와 함께 설명하세요."
    )

    prompt = f"""
너는 Insight Now의 20년 경력 글로벌 시장 전략가이자 한국어 금융 편집자다.
오늘 작성 시간은 {now.strftime('%Y-%m-%d %H:%M')} (KST)이다.

[이전 분석 레포트]
제목: {previous_title}
본문:
{previous_context}

[검증된 주요 시장 수치]
{market_text}

[앱이 수집·한국어화한 최신 금융 뉴스]
{news_text}

[필수 편집 원칙]
1. 반드시 JSON 한 개만 반환한다. 마크다운 표는 금지하고 본문은 제목·문단·불릿만 사용한다.
2. 이전 분석과 비교하여 추세가 **지속**인지 **반전**인지 명확히 판정하되, 근거가 부족하면 관찰 단계라고 표현한다.
3. {time_slot_instruction}
4. 제공된 뉴스와 시장 수치에 없는 사건, 정책 발언, 실적 수치, 장중 움직임은 사실처럼 작성하지 않는다.
5. 독자가 확인할 시장 맥락과 리스크 요인을 설명하되 특정 종목의 매수·매도·손절·익절·목표가를 지시하거나 수익을 보장하지 않는다.
6. 모든 문장은 자연스러운 한국어로 작성하고 불필요한 영어 제목을 사용하지 않는다.

[반환 형식]
{{
  "title": "한글 제목",
  "preview": "핵심 요약 2~3문장",
  "content": "마크다운 본문"
}}

[본문 필수 구조]
1. ## 작성 시점 및 시장 컨디션: 작성 시각과 전반적 온도
2. ## 오늘의 메가 이벤트: 제공된 뉴스에서 확인되는 핵심 이슈와 파급 경로
3. ## 연결성 분석: 이전 레포트 대비 지속·반전 판단과 근거
4. ## 핵심 테마 TOP 3: 각 테마의 관찰 포인트와 리스크
5. ## 주요 섹터·자산군 브리핑: 제공된 입력에서 확인되는 범위로만 정리
6. ## 다음 확인 항목: 후속 뉴스·지표·공시에서 확인할 조건
7. ## 안내: 정보 제공 목적이며 특정 종목의 매수·매도·수익을 보장하지 않는다는 문장
"""
    try:
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
            config={"response_mime_type": "application/json"},
        )
        return _clean_json(response.text or "")
    except Exception:
        return None


def _hide_legacy_placeholder_reports(client: Client) -> int:
    """정교한 레포트가 생성된 뒤에만 과거 테스트성 공개 항목을 피드에서 숨깁니다."""
    try:
        result = (
            client.table("analysis_posts")
            .select("id,title")
            .eq("is_published", True)
            .ilike("title", f"{PLACEHOLDER_TITLE_PREFIX}%")
            .limit(20)
            .execute()
        )
        hidden = 0
        for item in result.data or []:
            client.table("analysis_posts").update({"is_published": False}).eq(
                "id", item["id"]
            ).execute()
            hidden += 1
        return hidden
    except Exception:
        return 0


def generate_and_upload_report(force: bool = False, min_interval_hours: int = 3) -> dict[str, Any]:
    """Gemini 연속성 레포트를 생성·검증한 뒤 공개 발행합니다.

    `force=True`는 정해진 3회 발행이나 장애 복구에서 중복 시간 제한을 넘겨
    현재 회차를 생성할 때 사용합니다. 모델 실패는 공개 임시 콘텐츠가 아닌
    `deferred` 상태로 반환됩니다.
    """
    now = datetime.now(KST)
    try:
        client = _supabase_client()
        previous = _latest_quality_report(client)
        previous_time = _to_datetime(
            (previous or {}).get("created_at") or (previous or {}).get("published_at")
        )
        if (
            not force
            and previous_time
            and now - previous_time.astimezone(KST) < timedelta(hours=min_interval_hours)
        ):
            return {
                "status": "skipped",
                "reason": "recent_quality_report_exists",
                "latest_at": previous_time.isoformat(),
            }

        market = _market_snapshot()
        recent_news = _recent_korean_news(client)
        report = _ai_report(previous, now, market, recent_news)
        if report is None:
            return {
                "status": "deferred",
                "reason": "gemini_unavailable_or_invalid_response",
                "market_items": len(market),
                "news_items": len(recent_news),
            }

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
        hidden_placeholders = _hide_legacy_placeholder_reports(client)
        return {
            "status": "published",
            "id": created.get("id"),
            "title": data["title"],
            "quality": "gemini_continuity",
            "market_items": len(market),
            "news_items": len(recent_news),
            "hidden_placeholder_reports": hidden_placeholders,
        }
    except Exception as exc:
        return {"status": "failed", "error_type": type(exc).__name__}


if __name__ == "__main__":
    force_from_env = os.getenv("FORCE_REPORT", "").strip().lower() in {"1", "true", "yes"}
    result = generate_and_upload_report(force=force_from_env)
    print(json.dumps(result, ensure_ascii=False))
    if result.get("status") in {"failed", "deferred"}:
        raise SystemExit(1)
