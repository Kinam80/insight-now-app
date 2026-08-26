import json
import os
from datetime import datetime
from typing import Any

import requests
from dotenv import load_dotenv

from app.database import supabase_admin as supabase

try:
    from google import genai
except ImportError:  # 배포 환경이 새 의존성을 설치하기 전에도 API 기동을 유지합니다.
    genai = None

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


def _fallback_summary(title: str, publisher: str, tickers: list[str]) -> dict[str, Any]:
    ticker_text = f" 관련 종목: {', '.join(tickers[:4])}." if tickers else ""
    return {
        "headline": title,
        "summary": f"{publisher}가 전한 금융 뉴스입니다. {title}{ticker_text}",
        "importance": 3,
    }


def summarize_news(title: str, publisher: str, tickers: list[str]) -> dict[str, Any]:
    """Yahoo Finance 기사 메타데이터를 근거로 Gemini가 한국어 브리핑을 생성합니다."""
    fallback = _fallback_summary(title, publisher, tickers)
    client = _get_gemini_client()
    if client is None:
        print("⚠️ GEMINI_API_KEY가 없어 원문 제목 기반 요약으로 저장합니다.")
        return fallback

    related_tickers = ", ".join(tickers[:6]) if tickers else "없음"
    prompt = f"""
당신은 금융 뉴스 편집자입니다. 아래 Yahoo Finance 뉴스 메타데이터만 근거로 한국어 금융 브리핑을 작성하세요.
기사에 없는 사실, 숫자, 전망은 절대 만들지 마세요. 투자 매수·매도 권유도 금지합니다.

제목: {title}
매체: {publisher}
관련 티커: {related_tickers}

다음 JSON만 반환하세요.
{{
  "headline": "원문 의미를 유지한 45자 이내의 자연스러운 한국어 금융 헤드라인",
  "summary": "한국어 2문장 이내의 읽기 쉬운 요약. 제목의 핵심과 시장에서 주목할 맥락을 사실 범위에서 설명",
  "importance": 1에서 5 사이의 정수
}}
""".strip()

    try:
        response = client.models.generate_content(
            model=os.getenv("GEMINI_NEWS_MODEL", "gemini-2.5-flash"),
            contents=prompt,
            config={
                "response_mime_type": "application/json",
                "temperature": 0.2,
                "max_output_tokens": 240,
            },
        )
        raw_text = (response.text or "").strip().replace("```json", "").replace("```", "").strip()
        data = json.loads(raw_text)
        headline = str(data.get("headline", "")).strip()
        summary = str(data.get("summary", "")).strip()
        importance = int(data.get("importance", 3))
        if not headline or not summary:
            return fallback
        return {
            "headline": headline[:120],
            "summary": summary[:600],
            "importance": max(1, min(5, importance),),
        }
    except Exception as exc:
        print(f"⚠️ Gemini 뉴스 요약 실패: {exc}")
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


def fetch_and_save_news() -> int:
    """Yahoo Finance 최신 금융 뉴스를 수집하고 Gemini 한국어 요약을 저장합니다."""
    print(f"\n🔍 Yahoo Finance 뉴스 수집 시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    saved_count = 0

    for source in YAHOO_QUERIES:
        try:
            entries = _fetch_yahoo_news(source["query"])
            print(f"📡 Yahoo Finance {source['category']}: {len(entries)}개 항목 확인")
        except Exception as exc:
            print(f"⚠️ Yahoo Finance 수집 실패 ({source['category']}): {exc}")
            continue

        for entry in entries:
            title = str(entry.get("title", "")).strip()
            source_url = str(entry.get("link", "")).strip()
            publisher = str(entry.get("publisher", "Yahoo Finance")).strip() or "Yahoo Finance"
            tickers = [str(ticker) for ticker in entry.get("relatedTickers", []) if ticker]

            if not title or _is_duplicate(source_url):
                continue

            summary_data = summarize_news(title, publisher, tickers)
            try:
                supabase.table("ai_news").insert({
                    "title": summary_data["headline"],
                    "summary": summary_data["summary"],
                    "content": f"원문 제목: {title}",
                    "source_url": source_url,
                    "source_name": publisher,
                    "category": source["category"],
                    "importance": summary_data["importance"],
                }).execute()
                saved_count += 1
                print(f"✅ 저장: {title[:60]}...")
            except Exception as exc:
                print(f"⚠️ 뉴스 저장 실패: {exc}")

    print(f"📰 Yahoo Finance 뉴스 총 {saved_count}개 저장 완료")
    return saved_count


if __name__ == "__main__":
    fetch_and_save_news()
