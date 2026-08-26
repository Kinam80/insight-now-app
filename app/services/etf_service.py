from __future__ import annotations

from typing import Any

import requests
import yfinance as yf

from app.database import supabase_admin as supabase

YAHOO_ETF_SCREENER_URLS = (
    "https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved",
    "https://query2.finance.yahoo.com/v1/finance/screener/predefined/saved",
)
REQUEST_HEADERS = {
    # Yahoo의 공개 엔드포인트는 봇성 커스텀 UA를 간헐적으로 거부하므로 표준 브라우저 요청 형식을 사용합니다.
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
}


def _market_symbol(ticker_symbol: str) -> str:
    """숫자형 국내 종목만 KRX 접미사를 붙이고, 해외 ETF 심볼은 그대로 사용합니다."""
    ticker = ticker_symbol.strip().upper()
    if ticker.isdigit() and len(ticker) == 6:
        return f"{ticker}.KS"
    return ticker


def _quote_price(quote: dict[str, Any]) -> float | None:
    for field in ("regularMarketPrice", "postMarketPrice", "preMarketPrice", "price"):
        value = quote.get(field)
        if isinstance(value, (int, float)):
            return float(value)
    return None


def _korean_etf_description(ticker: str, name: str) -> str:
    """ETF 공식 명칭을 기반으로 앱 상세 화면에 표시할 한국어 안내문을 만듭니다."""
    normalized_name = name.lower()
    theme_map = [
        (("semiconductor", "chip"), "반도체·AI 인프라"),
        (("technology", "tech", "software", "cloud"), "기술·소프트웨어"),
        (("gold", "silver", "metal", "miners"), "귀금속·광산"),
        (("energy", "oil", "gas", "uranium"), "에너지·원자재"),
        (("treasury", "bond", "income"), "채권·인컴"),
        (("bank", "financial"), "금융"),
        (("health", "biotech", "medical"), "헬스케어·바이오"),
        (("real estate", "reit", "property"), "부동산"),
        (("china", "korea", "india", "japan", "emerging"), "국가·신흥시장"),
        (("dividend", "quality", "value"), "배당·가치"),
        (("bitcoin", "crypto", "blockchain"), "디지털자산·블록체인"),
    ]
    theme = next(
        (label for keywords, label in theme_map if any(keyword in normalized_name for keyword in keywords)),
        "글로벌 주식시장",
    )
    market_label = "국내 상장 ETF" if ticker.isdigit() and len(ticker) == 6 else "해외 상장 ETF"
    return f"""## {ticker} ETF 한눈에 보기

**{name}**은(는) {theme} 흐름에 투자하는 {market_label}입니다.

### 무엇을 확인해야 하나요?
- **추종 대상:** ETF가 어떤 지수·산업·자산을 따라가는지 확인하세요.
- **변동 요인:** 관련 업종 실적, 금리, 환율 및 원자재 가격이 수익률에 영향을 줄 수 있습니다.
- **투자 전 점검:** 총보수, 거래량, 편입 종목 비중과 분배 정책을 함께 비교하세요.

> 이 설명은 투자 권유가 아닌 기본 학습 정보입니다. 실제 투자 전에는 운용사의 최신 투자설명서와 구성 종목을 확인하세요.
"""


def _save_by_ticker(table_name: str, payload: dict[str, Any]) -> Any:
    """유니크 제약이 없는 레거시 테이블에서도 중복 없이 티커 행을 저장합니다."""
    ticker = str(payload["ticker"]).upper()
    existing = (
        supabase.table(table_name).select("id").eq("ticker", ticker).limit(1).execute()
    )
    if existing.data:
        return supabase.table(table_name).update(payload).eq("ticker", ticker).execute()
    return supabase.table(table_name).insert(payload).execute()


def update_etf_data_by_ticker(ticker_symbol: str) -> dict[str, Any]:
    """개별 ETF의 이름·현재가를 조회하여 etf_data에 upsert합니다."""
    try:
        ticker = yf.Ticker(_market_symbol(ticker_symbol))
        info = ticker.info or {}
        price = info.get("regularMarketPrice") or info.get("currentPrice")
        name = info.get("shortName") or info.get("longName") or ticker_symbol
        normalized_ticker = ticker_symbol.upper()
        payload = {
            "ticker": normalized_ticker,
            "name": name,
            "price": price,
            "description": _korean_etf_description(normalized_ticker, str(name)),
        }
        response = _save_by_ticker("etf_data", payload)
        return {"status": "success", "ticker": ticker_symbol.upper(), "data": response.data}
    except Exception as exc:
        print(f"⚠️ ETF 개별 업데이트 실패 ({ticker_symbol}): {exc}")
        return {"status": "error", "ticker": ticker_symbol.upper(), "message": str(exc)}


def discover_top_etfs(limit: int = 100) -> list[dict[str, Any]]:
    """Yahoo Finance 공개 ETF 스크리너에서 유동성 높은 ETF 목록을 가져옵니다."""
    request_params = {
        "formatted": "false",
        "scrIds": "top_etfs_us",
        "count": min(max(limit, 1), 250),
    }
    last_error: requests.RequestException | None = None

    for endpoint in YAHOO_ETF_SCREENER_URLS:
        try:
            response = requests.get(
                endpoint,
                params=request_params,
                headers=REQUEST_HEADERS,
                timeout=25,
            )
            response.raise_for_status()
            payload = response.json()
            results = payload.get("finance", {}).get("result", [])
            if not results:
                continue
            quotes = results[0].get("quotes", [])
            discovered = [
                quote
                for quote in quotes
                if quote.get("symbol") and (quote.get("quoteType") in (None, "ETF"))
            ]
            if discovered:
                return discovered
        except requests.RequestException as exc:
            last_error = exc
            continue

    if last_error:
        raise last_error
    return []


def refresh_etf_universe(limit: int = 100) -> dict[str, Any]:
    """상위 ETF를 자동 등록하고 시세를 갱신합니다. 기존 사용자 등록 종목은 유지합니다."""
    quotes = discover_top_etfs(limit)
    registered = 0
    updated = 0
    failures: list[str] = []

    for quote in quotes:
        ticker = str(quote["symbol"]).upper()
        name = str(quote.get("shortName") or quote.get("longName") or ticker)
        price = _quote_price(quote)
        try:
            _save_by_ticker(
                "etf_registry", {"ticker": ticker, "weight": 0, "is_active": True}
            )
            registered += 1
            _save_by_ticker(
                "etf_data",
                {
                    "ticker": ticker,
                    "name": name,
                    "price": price,
                    "description": _korean_etf_description(ticker, name),
                },
            )
            updated += 1
        except Exception as exc:
            failures.append(f"{ticker}: {exc}")

    # 자동 목록 밖의 기존 활성 ETF도 가격을 유지·갱신합니다.
    discovered_tickers = {str(item["symbol"]).upper() for item in quotes}
    for ticker in get_all_registered_tickers():
        if ticker not in discovered_tickers:
            result = update_etf_data_by_ticker(ticker)
            if result["status"] == "success":
                updated += 1
            else:
                failures.append(f"{ticker}: {result.get('message', '업데이트 실패')}")

    return {
        "discovered": len(quotes),
        "registered": registered,
        "updated": updated,
        "failures": failures[:10],
    }


def get_all_registered_tickers() -> list[str]:
    """etf_registry에서 활성 ETF 티커 목록을 반환합니다."""
    try:
        response = supabase.table("etf_registry").select("ticker").eq("is_active", True).execute()
        return list(
            dict.fromkeys(
                str(item["ticker"]).upper()
                for item in response.data
                if item.get("ticker")
            )
        )
    except Exception as exc:
        print(f"⚠️ ETF 레지스트리 조회 실패: {exc}")
        return []


def add_to_registry(ticker: str, weight: float) -> dict[str, Any]:
    """관리자 수동 등록 종목도 자동 갱신 대상에 포함합니다."""
    try:
        normalized = ticker.strip().upper()
        response = _save_by_ticker(
            "etf_registry", {"ticker": normalized, "weight": weight, "is_active": True}
        )
        return {"status": "success", "data": response.data}
    except Exception as exc:
        print(f"⚠️ ETF 레지스트리 등록 실패: {exc}")
        return {"status": "error", "message": str(exc)}
