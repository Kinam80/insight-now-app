from __future__ import annotations

from typing import Any

import requests
import yfinance as yf

from app.database import supabase

YAHOO_ETF_SCREENER_URL = "https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved"
REQUEST_HEADERS = {
    "User-Agent": "InsightNow/1.0 (+https://insight-now-app.onrender.com)",
    "Accept": "application/json",
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


def update_etf_data_by_ticker(ticker_symbol: str) -> dict[str, Any]:
    """개별 ETF의 이름·현재가를 조회하여 etf_data에 upsert합니다."""
    try:
        ticker = yf.Ticker(_market_symbol(ticker_symbol))
        info = ticker.info or {}
        price = info.get("regularMarketPrice") or info.get("currentPrice")
        name = info.get("shortName") or info.get("longName") or ticker_symbol
        payload = {"ticker": ticker_symbol.upper(), "name": name, "price": price}
        response = supabase.table("etf_data").upsert(payload).execute()
        return {"status": "success", "ticker": ticker_symbol.upper(), "data": response.data}
    except Exception as exc:
        print(f"⚠️ ETF 개별 업데이트 실패 ({ticker_symbol}): {exc}")
        return {"status": "error", "ticker": ticker_symbol.upper(), "message": str(exc)}


def discover_top_etfs(limit: int = 100) -> list[dict[str, Any]]:
    """Yahoo Finance 공개 ETF 스크리너에서 유동성 높은 ETF 목록을 가져옵니다."""
    response = requests.get(
        YAHOO_ETF_SCREENER_URL,
        params={"formatted": "false", "scrIds": "top_etfs_us", "count": min(max(limit, 1), 250)},
        headers=REQUEST_HEADERS,
        timeout=25,
    )
    response.raise_for_status()
    payload = response.json()
    results = payload.get("finance", {}).get("result", [])
    if not results:
        return []

    quotes = results[0].get("quotes", [])
    return [
        quote
        for quote in quotes
        if quote.get("symbol") and (quote.get("quoteType") in (None, "ETF"))
    ]


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
            supabase.table("etf_registry").upsert(
                {"ticker": ticker, "weight": 0, "is_active": True}
            ).execute()
            registered += 1
            supabase.table("etf_data").upsert(
                {"ticker": ticker, "name": name, "price": price}
            ).execute()
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
        return [str(item["ticker"]).upper() for item in response.data if item.get("ticker")]
    except Exception as exc:
        print(f"⚠️ ETF 레지스트리 조회 실패: {exc}")
        return []


def add_to_registry(ticker: str, weight: float) -> dict[str, Any]:
    """관리자 수동 등록 종목도 자동 갱신 대상에 포함합니다."""
    try:
        normalized = ticker.strip().upper()
        response = supabase.table("etf_registry").upsert(
            {"ticker": normalized, "weight": weight, "is_active": True}
        ).execute()
        return {"status": "success", "data": response.data}
    except Exception as exc:
        print(f"⚠️ ETF 레지스트리 등록 실패: {exc}")
        return {"status": "error", "message": str(exc)}
