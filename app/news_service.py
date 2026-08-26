import json
import os
import re
from datetime import datetime
from typing import Any

import requests
from dotenv import load_dotenv

from app.database import supabase_admin as supabase

try:
    from google import genai
except ImportError:  # 배포 환경이 새 의존성을 설치하기 전에도 API 기동을 유지합니다.
    genai = None

try:
    from groq import Groq
except ImportError:
    Groq = None

load_dotenv()

YAHOO_SEARCH_URLS = (
    "https://query1.finance.yahoo.com/v1/finance/search",
    "https://query2.finance.yahoo.com/v1/finance/search",
)
YAHOO_QUERIES = [
    {"query": "stock market", "category": "us_market"},
    {"query": "Federal Reserve interest rates", "category": "bond_rate"},
    {"query": "US dollar currency market", "category": "fx_rate"},
    {"query": "Korea stock market", "category": "kr_market"},
]
MAX_ITEMS_PER_QUERY = 5
REQUEST_HEADERS = {
    # Yahoo의 공개 검색 API는 서버성 커스텀 UA를 간헐적으로 차단하므로 표준 브라우저 형식을 사용합니다.
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
}


def _get_gemini_client():
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if genai is None or not api_key:
        return None
    return genai.Client(api_key=api_key)


def _get_groq_client():
    api_key = os.getenv("GROQ_API_KEY")
    if Groq is None or not api_key:
        return None
    return Groq(api_key=api_key)


def _fallback_summary(title: str, publisher: str, tickers: list[str]) -> dict[str, Any]:
    ticker_text = f" 관련 종목: {', '.join(tickers[:4])}." if tickers else ""
    return {
        "headline": title,
        "summary": f"{publisher}가 전한 금융 뉴스입니다. {title}{ticker_text}",
        "importance": 3,
    }


def _parse_korean_brief(raw_text: str, fallback: dict[str, Any]) -> dict[str, Any]:
    try:
        data = json.loads(raw_text.strip().replace("```json", "").replace("```", "").strip())
        headline = str(data.get("headline", "")).strip()
        summary = str(data.get("summary", "")).strip()
        importance = int(data.get("importance", 3))
        if not headline or not summary:
            return fallback
        return {
            "headline": headline[:120],
            "summary": summary[:600],
            "importance": max(1, min(5, importance)),
        }
    except (TypeError, ValueError, json.JSONDecodeError):
        return fallback


def summarize_news(title: str, publisher: str, tickers: list[str]) -> dict[str, Any]:
    """Yahoo 메타데이터를 Gemini 우선, Groq 보조 순서로 한국어 브리핑합니다."""
    fallback = _fallback_summary(title, publisher, tickers)
    related_tickers = ", ".join(tickers[:6]) if tickers else "없음"
    prompt = f"""
당신은 한국어 금융 뉴스 편집자입니다. 아래 Yahoo Finance 뉴스 메타데이터만 근거로
한국 독자가 읽기 쉬운 금융 헤드라인과 요약을 작성하세요.
기사에 없는 사실, 숫자, 전망을 만들지 말고 투자 매수·매도 권유도 하지 마세요.

원문 제목: {title}
매체: {publisher}
관련 티커: {related_tickers}

다음 JSON만 반환하세요.
{{
  "headline": "원문 의미를 유지한 45자 이내의 자연스러운 한국어 금융 헤드라인",
  "summary": "한국어 2문장 이내의 읽기 쉬운 요약. 제목의 핵심과 시장에서 주목할 맥락을 사실 범위에서 설명",
  "importance": 1에서 5 사이의 정수
}}
""".strip()

    gemini_client = _get_gemini_client()
    if gemini_client is not None:
        try:
            response = gemini_client.models.generate_content(
                model=os.getenv("GEMINI_NEWS_MODEL", "gemini-2.5-flash"),
                contents=prompt,
                config={
                    "response_mime_type": "application/json",
                    "temperature": 0.2,
                    "max_output_tokens": 240,
                },
            )
            result = _parse_korean_brief(response.text or "", fallback)
            if result != fallback:
                return result
        except Exception as exc:
            print(f"⚠️ Gemini 뉴스 요약 실패: {type(exc).__name__}")

    groq_client = _get_groq_client()
    if groq_client is not None:
        try:
            response = groq_client.chat.completions.create(
                model=os.getenv("GROQ_NEWS_MODEL", "llama-3.1-8b-instant"),
                messages=[
                    {"role": "system", "content": "You output valid JSON only."},
                    {"role": "user", "content": prompt},
                ],
                response_format={"type": "json_object"},
                temperature=0.2,
                max_tokens=280,
            )
            return _parse_korean_brief(response.choices[0].message.content or "", fallback)
        except Exception as exc:
            print(f"⚠️ Groq 뉴스 요약 실패: {type(exc).__name__}")

    print("⚠️ Gemini와 Groq 키가 없어 원문 제목 기반 요약으로 저장합니다.")
    return fallback


def _fetch_yahoo_news(query: str) -> list[dict[str, Any]]:
    request_params = {
        "q": query,
        "newsCount": MAX_ITEMS_PER_QUERY,
        "region": "US",
        "lang": "en-US",
    }
    last_error: requests.RequestException | None = None

    for endpoint in YAHOO_SEARCH_URLS:
        try:
            response = requests.get(
                endpoint,
                params=request_params,
                headers=REQUEST_HEADERS,
                timeout=20,
            )
            response.raise_for_status()
            payload = response.json()
            news_items = payload.get("news", []) if isinstance(payload, dict) else []
            if news_items:
                return news_items
        except requests.RequestException as exc:
            last_error = exc
            continue

    if last_error:
        raise last_error
    return []


def _is_duplicate(source_url: str) -> bool:
    if not source_url:
        return True
    result = supabase.table("ai_news").select("id").eq("source_url", source_url).limit(1).execute()
    return bool(result.data)


def _needs_korean_refresh(title: str) -> bool:
    """카테고리 접두사를 제외한 실제 제목에 한글이 없으면 재번역 대상으로 판단합니다."""
    clean_title = re.sub(r"^\[[^\]]+\]\s*", "", title).strip()
    return bool(clean_title) and not bool(re.search(r"[가-힣]", clean_title))


def _refresh_existing_korean_news(limit: int = 50) -> int:
    """기존 영문 제목의 최근 뉴스도 한국어 편집본으로 안전하게 갱신합니다."""
    try:
        response = (
            supabase.table("ai_news")
            .select("id,title,source_name")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
    except Exception as exc:
        print(f"⚠️ 기존 뉴스 번역 대상 조회 실패: {type(exc).__name__}")
        return 0

    updated_count = 0
    for item in response.data or []:
        original_title = str(item.get("title", "")).strip()
        if not _needs_korean_refresh(original_title):
            continue
        source_title = re.sub(r"^\[[^\]]+\]\s*", "", original_title).strip()
        summary_data = summarize_news(
            source_title,
            str(item.get("source_name") or "Yahoo Finance"),
            [],
        )
        if summary_data["headline"] == source_title:
            continue
        try:
            (
                supabase.table("ai_news")
                .update(
                    {
                        "title": summary_data["headline"],
                        "summary": summary_data["summary"],
                        "importance": summary_data["importance"],
                    }
                )
                .eq("id", item["id"])
                .execute()
            )
            updated_count += 1
        except Exception as exc:
            print(f"⚠️ 기존 뉴스 한국어 갱신 실패: {type(exc).__name__}")
    return updated_count


def fetch_and_save_news() -> dict[str, int]:
    """Yahoo Finance 최신 금융 뉴스를 수집하고 Gemini 한국어 요약을 저장합니다.

    중복 확인과 저장을 배치화하여 서버 시작 직후의 일시적인 DB 연결 오류가
    개별 기사마다 증폭되지 않도록 합니다.
    """
    print(f"\n🔍 Yahoo Finance 뉴스 수집 시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    translated_count = _refresh_existing_korean_news()
    raw_candidates: list[dict[str, Any]] = []
    seen_urls: set[str] = set()
    fetch_failure_count = 0

    for source in YAHOO_QUERIES:
        try:
            entries = _fetch_yahoo_news(source["query"])
            print(f"📡 Yahoo Finance {source['category']}: {len(entries)}개 항목 확인")
        except Exception as exc:
            fetch_failure_count += 1
            print(f"⚠️ Yahoo Finance 수집 실패 ({source['category']}): {exc}")
            continue

        for entry in entries:
            title = str(entry.get("title", "")).strip()
            source_url = str(entry.get("link", "")).strip()
            if not title or not source_url or source_url in seen_urls:
                continue
            seen_urls.add(source_url)
            raw_candidates.append({"entry": entry, "category": source["category"]})

    if not raw_candidates:
        return {
            "saved_count": 0,
            "candidate_count": 0,
            "fetch_failure_count": fetch_failure_count,
            "save_failure_count": 0,
            "translated_count": translated_count,
        }

    candidate_urls = [item["entry"]["link"] for item in raw_candidates]
    try:
        existing_result = (
            supabase.table("ai_news")
            .select("source_url")
            .in_("source_url", candidate_urls)
            .execute()
        )
        existing_urls = {
            str(item.get("source_url"))
            for item in (existing_result.data or [])
            if item.get("source_url")
        }
    except Exception as exc:
        # 배포 직후 연결이 재설정되는 경우에도 신규 기사를 놓치지 않도록 저장을 시도합니다.
        existing_urls = set()
        print(f"⚠️ 뉴스 중복 조회 실패, 신규 저장을 계속 시도합니다: {type(exc).__name__}")

    records: list[dict[str, Any]] = []
    for candidate in raw_candidates:
        entry = candidate["entry"]
        source_url = str(entry["link"])
        if source_url in existing_urls:
            continue
        title = str(entry["title"]).strip()
        publisher = str(entry.get("publisher", "Yahoo Finance")).strip() or "Yahoo Finance"
        tickers = [str(ticker) for ticker in entry.get("relatedTickers", []) if ticker]
        summary_data = summarize_news(title, publisher, tickers)
        records.append({
            "title": summary_data["headline"],
            "summary": summary_data["summary"],
            "source_url": source_url,
            "source_name": publisher,
            "category": candidate["category"],
            "importance": summary_data["importance"],
        })

    if not records:
        return {
            "saved_count": 0,
            "candidate_count": len(raw_candidates),
            "fetch_failure_count": fetch_failure_count,
            "save_failure_count": 0,
            "translated_count": translated_count,
        }

    saved_count = 0
    save_failure_count = 0
    try:
        supabase.table("ai_news").insert(records).execute()
        saved_count = len(records)
    except Exception as exc:
        print(f"⚠️ 뉴스 일괄 저장 실패, 개별 저장으로 재시도합니다: {type(exc).__name__}")
        for record in records:
            try:
                supabase.table("ai_news").insert(record).execute()
                saved_count += 1
            except Exception as item_exc:
                save_failure_count += 1
                print(f"⚠️ 뉴스 저장 실패: {type(item_exc).__name__}")

    print(f"📰 Yahoo Finance 뉴스 총 {saved_count}개 저장 완료")
    return {
        "saved_count": saved_count,
        "candidate_count": len(raw_candidates),
        "fetch_failure_count": fetch_failure_count,
        "save_failure_count": save_failure_count,
        "translated_count": translated_count,
    }


if __name__ == "__main__":
    fetch_and_save_news()
