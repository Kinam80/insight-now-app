from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import requests
import yfinance as yf

from app.database import supabase_admin as supabase

YAHOO_ETF_SCREENER_URLS = (
    "https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved",
    "https://query2.finance.yahoo.com/v1/finance/screener/predefined/saved",
)
NAVER_ETF_LIST_URL = "https://finance.naver.com/api/sise/etfItemList.nhn"
KRX_CATEGORY_BY_TAB = {
    1: "국내 주식형",
    2: "국내 섹터·테마형",
    3: "레버리지·인버스형",
    4: "해외 주식형",
    5: "원자재·귀금속형",
    6: "채권·금리형",
    7: "혼합·머니마켓형",
}
REQUEST_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "en-US,en;q=0.9",
}
DESCRIPTION_MARKER = "## 상품 핵심 정보"

CATEGORY_KO = {
    "large blend": "미국 대형주 혼합형",
    "large growth": "미국 대형 성장주형",
    "large value": "미국 대형 가치주형",
    "mid-cap blend": "미국 중형주 혼합형",
    "mid-cap growth": "미국 중형 성장주형",
    "mid-cap value": "미국 중형 가치주형",
    "small blend": "미국 소형주 혼합형",
    "small growth": "미국 소형 성장주형",
    "small value": "미국 소형 가치주형",
    "technology": "정보기술 섹터형",
    "health": "헬스케어 섹터형",
    "financial": "금융 섹터형",
    "energy limited partnership": "에너지 인프라형",
    "natural resources": "천연자원·원자재형",
    "real estate": "부동산 리츠형",
    "consumer cyclical": "경기소비재 섹터형",
    "consumer defensive": "필수소비재 섹터형",
    "industrials": "산업재 섹터형",
    "utilities": "유틸리티 섹터형",
    "communications": "커뮤니케이션 섹터형",
    "world stock": "글로벌 주식형",
    "foreign large blend": "해외 대형주형",
    "foreign large growth": "해외 성장주형",
    "foreign small/mid blend": "해외 중소형주형",
    "emerging markets": "신흥국 주식형",
    "japan stock": "일본 주식형",
    "europe stock": "유럽 주식형",
    "india equity": "인도 주식형",
    "china region": "중국 주식형",
    "latin america stock": "중남미 주식형",
    "commodities focused": "원자재형",
    "precious metals": "귀금속형",
    "digital assets": "디지털자산 관련주형",
    "intermediate core bond": "중기 채권형",
    "short government": "단기 국채형",
    "ultrashort bond": "초단기 채권형",
    "high yield bond": "하이일드 채권형",
}


def _market_symbol(ticker_symbol: str) -> str:
    """국내 ETF 코드는 KRX 접미사를 붙이고 해외 ETF 심볼은 그대로 사용합니다."""
    ticker = ticker_symbol.strip().upper()
    if len(ticker) == 6 and ticker.isalnum() and ticker[0].isdigit():
        return f"{ticker}.KS"
    return ticker


def _is_krx_ticker(ticker: str) -> bool:
    # 2025년 이후 KRX ETF에는 0167A0처럼 영문·숫자가 섞인 6자리 코드도 있습니다.
    return len(ticker) == 6 and ticker.isalnum() and ticker[0].isdigit()


def _as_float(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).replace(",", ""))
    except (TypeError, ValueError):
        return None


def _first_number(*values: Any) -> float | None:
    for value in values:
        number = _as_float(value)
        if number is not None and number > 0:
            return number
    return None


def _quote_price(quote: dict[str, Any]) -> float | None:
    return _first_number(
        quote.get("regularMarketPrice"),
        quote.get("postMarketPrice"),
        quote.get("preMarketPrice"),
        quote.get("price"),
    )


def _percent(value: Any) -> float | None:
    number = _as_float(value)
    if number is None:
        return None
    # Yahoo 응답은 필드별로 0.0101 또는 1.01 형식을 사용하므로 화면용 %로 통일합니다.
    return round(number * 100 if abs(number) <= 1 else number, 3)


def _format_number(value: Any, suffix: str = "") -> str | None:
    number = _as_float(value)
    if number is None:
        return None
    if abs(number) >= 1_000_000_000_000:
        return f"{number / 1_000_000_000_000:.2f}조{suffix}"
    if abs(number) >= 1_000_000_000:
        return f"{number / 1_000_000_000:.2f}십억{suffix}"
    if abs(number) >= 1_000_000:
        return f"{number / 1_000_000:.2f}백만{suffix}"
    return f"{number:,.2f}{suffix}"


def _as_of_iso(value: Any) -> str | None:
    number = _as_float(value)
    if number is None:
        return None
    try:
        return datetime.fromtimestamp(number, tz=timezone.utc).isoformat()
    except (OverflowError, OSError, ValueError):
        return None


def _provider_from_korean_name(name: str) -> str | None:
    prefixes = {
        "KODEX": "삼성자산운용",
        "TIGER": "미래에셋자산운용",
        "ACE": "한국투자신탁운용",
        "RISE": "KB자산운용",
        "PLUS": "한화자산운용",
        "SOL": "신한자산운용",
        "HANARO": "NH-Amundi자산운용",
        "TIME": "타임폴리오자산운용",
        "1Q": "키움투자자산운용",
    }
    upper = name.strip().upper()
    return next((provider for prefix, provider in prefixes.items() if upper.startswith(prefix)), None)


def _category_label(category: str | None, name: str) -> str:
    normalized = (category or "").strip().lower()
    if normalized in CATEGORY_KO:
        return CATEGORY_KO[normalized]
    for source, translated in CATEGORY_KO.items():
        if source in normalized:
            return translated

    name_lower = name.lower()
    theme_map = [
        (("semiconductor", "chip"), "반도체·AI 인프라형"),
        (("technology", "tech", "software", "cloud"), "정보기술·소프트웨어형"),
        (("gold", "silver", "metal", "miners"), "귀금속·광산형"),
        (("energy", "oil", "gas", "uranium", "mlp"), "에너지·인프라형"),
        (("treasury", "bond", "income", "fixed"), "채권·인컴형"),
        (("bank", "financial"), "금융 섹터형"),
        (("health", "biotech", "medical", "life sci"), "헬스케어·바이오형"),
        (("real estate", "reit", "property"), "부동산·리츠형"),
        (("china", "korea", "india", "japan", "emerging"), "국가·신흥시장형"),
        (("dividend", "quality", "value"), "배당·퀄리티·가치형"),
        (("bitcoin", "crypto", "blockchain"), "디지털자산 관련주형"),
    ]
    return next((label for words, label in theme_map if any(word in name_lower for word in words)), "주식시장 분산투자형")


def _strategy_sentence(raw_summary: str | None, category: str, name: str) -> str:
    """영문 원문을 노출하지 않고 실제 상품명·분류·공개 설명의 핵심 패턴만 한국어로 안내합니다."""
    text = (raw_summary or "").lower()
    if "weight" in text and "index" in text:
        return "공개 설명상 기초지수 편입 자산을 지수 비중에 가깝게 보유하도록 설계된 상품입니다."
    if "index" in text and ("track" in text or "seek" in text or "replicate" in text):
        return "공개 설명상 특정 기초지수 또는 시장 구간의 성과를 따르도록 설계된 상품입니다."
    if "income" in text or "dividend" in text:
        return "공개 설명상 분배·인컴 특성을 함께 고려하는 자산군에 투자하는 상품입니다."
    if "bond" in text or "treasury" in text:
        return "공개 설명상 채권 또는 금리 민감 자산에 분산 투자하는 상품입니다."
    return f"공식 상품명과 분류 기준으로 {category}에 분산 투자하도록 구성된 ETF입니다."


def _metadata_from_sources(
    ticker: str,
    name: str,
    info: dict[str, Any],
    quote: dict[str, Any] | None,
    price: float | None,
) -> dict[str, Any]:
    quote = quote or {}
    expense_ratio = _percent(
        info.get("annualReportExpenseRatio")
        or info.get("netExpenseRatio")
        or quote.get("netExpenseRatio")
    )
    dividend_yield = _percent(
        info.get("yield")
        or info.get("trailingAnnualDividendYield")
        or quote.get("yieldTTM")
        or quote.get("dividendYield")
    )
    category_raw = str(info.get("category") or quote.get("category") or "").strip()
    is_krx = quote.get("_market") == "KRX" or _is_krx_ticker(ticker)
    category_ko = str(quote.get("_category_ko") or _category_label(category_raw, name))
    return {
        "version": 2,
        "source": quote.get("_source") or "Yahoo Finance 공개 상품 메타데이터",
        "source_updated_at": _as_of_iso(info.get("regularMarketTime") or quote.get("regularMarketTime")),
        "synced_at": datetime.now(timezone.utc).isoformat(),
        "official_name": name,
        "ticker": ticker,
        "market": "KRX" if is_krx else "해외 거래소",
        "currency": info.get("currency") or quote.get("currency") or ("KRW" if _is_krx_ticker(ticker) else "USD"),
        "exchange": info.get("fullExchangeName") or quote.get("fullExchangeName") or info.get("exchange") or quote.get("exchange"),
        "provider": info.get("fundFamily") or quote.get("fundFamily") or _provider_from_korean_name(name),
        "category_raw": category_raw,
        "category_ko": category_ko,
        "underlying_index": info.get("underlyingIndex") or info.get("indexName"),
        "product_summary_raw": str(info.get("longBusinessSummary") or "").strip(),
        "price": price,
        "expense_ratio_percent": expense_ratio,
        "dividend_yield_percent": dividend_yield,
        "net_assets": _first_number(info.get("totalAssets"), info.get("netAssets"), quote.get("netAssets")),
        "ytd_return_percent": _percent(info.get("ytdReturn") or quote.get("ytdReturn")),
        "three_year_return_percent": _percent(info.get("threeYearAverageReturn") or quote.get("annualReturnNavY3")),
        "five_year_return_percent": _percent(info.get("fiveYearAverageReturn") or quote.get("annualReturnNavY5")),
        "week_52_low": _first_number(info.get("fiftyTwoWeekLow"), quote.get("fiftyTwoWeekLow")),
        "week_52_high": _first_number(info.get("fiftyTwoWeekHigh"), quote.get("fiftyTwoWeekHigh")),
        "nav": _as_float(quote.get("nav")),
        "daily_change_percent": _percent(quote.get("changeRate")),
        "three_month_return_percent": _percent(quote.get("threeMonthEarnRate")),
        # 네이버 ETF 목록의 시가총액 단위는 억 원입니다.
        "market_cap": (_as_float(quote.get("marketSum")) or 0) * 100_000_000 if quote.get("marketSum") is not None else None,
    }


def _korean_etf_description(ticker: str, name: str, metadata: dict[str, Any]) -> str:
    """실제 운용사·분류·비용·자산·시장 데이터를 문서형 한국어 상품 설명으로 구성합니다."""
    category = str(metadata.get("category_ko") or "분산투자형")
    raw_summary = str(metadata.get("product_summary_raw") or "")
    rows: list[tuple[str, str]] = [("상품 분류", category)]
    if metadata.get("provider"):
        rows.append(("운용사", str(metadata["provider"])))
    if metadata.get("underlying_index"):
        rows.append(("추종지수·기초자산", str(metadata["underlying_index"])))
    if metadata.get("exchange"):
        rows.append(("거래소", str(metadata["exchange"])))
    if metadata.get("currency"):
        rows.append(("거래 통화", str(metadata["currency"])))
    assets = _format_number(metadata.get("net_assets"))
    if assets:
        rows.append(("순자산", assets))
    market_cap = _format_number(metadata.get("market_cap"), "원")
    if market_cap:
        rows.append(("시가총액", market_cap))
    nav = _format_number(metadata.get("nav"))
    if nav:
        rows.append(("NAV", nav))
    if metadata.get("daily_change_percent") is not None:
        rows.append(("당일 등락률", f"{metadata['daily_change_percent']:.3f}%"))
    if metadata.get("three_month_return_percent") is not None:
        rows.append(("3개월 수익률", f"{metadata['three_month_return_percent']:.3f}%"))
    if metadata.get("expense_ratio_percent") is not None:
        rows.append(("총보수", f"{metadata['expense_ratio_percent']:.3f}%"))
    if metadata.get("dividend_yield_percent") is not None:
        rows.append(("최근 분배수익률", f"{metadata['dividend_yield_percent']:.3f}%"))
    if metadata.get("ytd_return_percent") is not None:
        rows.append(("연초 이후 수익률", f"{metadata['ytd_return_percent']:.3f}%"))
    if metadata.get("week_52_low") is not None and metadata.get("week_52_high") is not None:
        rows.append(("52주 가격 범위", f"{metadata['week_52_low']:,.2f} ~ {metadata['week_52_high']:,.2f}"))

    table = "\n".join(f"| {label} | {value} |" for label, value in rows)
    source_time = metadata.get("source_updated_at") or metadata.get("synced_at")
    source_display = str(source_time).replace("T", " ")[:19] if source_time else "최근 동기화"
    return f"""## {ticker} 상품 핵심 정보

**공식 상품명:** {name}

**한줄 설명:** {name}은(는) {category}에 속하는 ETF입니다. {_strategy_sentence(raw_summary, category, name)}

### 이 ETF는 어떤 상품인가요?
이 상품은 위의 운용사·분류·거래소·비용 데이터를 기준으로 자동 정리되었습니다. 추종지수가 공개된 경우에는 해당 지수의 구성 종목과 비중을, 공개되지 않은 경우에는 운용사의 최신 투자설명서를 함께 확인해야 합니다.

| 확인 항목 | 자동 수집 데이터 |
| --- | --- |
{table}

### 투자 전 확인할 점
- 같은 테마 ETF라도 추종지수, 보수, 환헤지 여부, 분배 정책과 편입 비중이 다를 수 있습니다.
- 가격은 시장 개장·마감 및 데이터 제공 지연에 따라 변동할 수 있으며, **최근 수신 시각은 {source_display} UTC**입니다.
- 이 화면은 상품 이해를 위한 정보이며, 특정 종목의 매수·매도 또는 수익을 보장하지 않습니다.
"""


def _description_is_verified(value: Any) -> bool:
    return DESCRIPTION_MARKER in str(value or "")


def _latest_data_row(ticker: str) -> dict[str, Any] | None:
    try:
        response = (
            supabase.table("etf_data")
            .select("*")
            .eq("ticker", ticker.upper())
            .order("updated_at", desc=True)
            .limit(1)
            .execute()
        )
        return (response.data or [None])[0]
    except Exception:
        return None


def _save_by_ticker(table_name: str, payload: dict[str, Any]) -> Any:
    """기존 중복 행은 최신 행만 갱신해 최신 데이터가 목록과 상세에 일관되게 선택되도록 합니다."""
    ticker = str(payload["ticker"]).upper()
    existing = (
        supabase.table(table_name)
        # etf_registry에는 updated_at 열이 없는 기존 환경도 있어 두 테이블 공통인 created_at을 기준으로 선택합니다.
        .select("id")
        .eq("ticker", ticker)
        .order("created_at", desc=True)
        .limit(1)
        .execute()
    )
    if existing.data:
        return supabase.table(table_name).update(payload).eq("id", existing.data[0]["id"]).execute()
    return supabase.table(table_name).insert(payload).execute()


def update_etf_data_by_ticker(ticker_symbol: str, quote: dict[str, Any] | None = None) -> dict[str, Any]:
    """개별 ETF의 실시간 가격과 상품 메타데이터를 갱신합니다. 조회 실패 시 기존 검증값을 덮어쓰지 않습니다."""
    normalized_ticker = ticker_symbol.strip().upper()
    try:
        quote = quote or {}
        info: dict[str, Any] = {}
        fast_info: Any = {}
        # 현재 가격·정식 명칭이 원본 목록에 있는 ETF는 대량 동기화 때 개별 조회를 생략합니다.
        # 이 방식은 원본 API 제한으로 가격이 비어 버리는 현상을 막습니다.
        if not (quote.get("symbol") and _quote_price(quote) is not None):
            ticker = yf.Ticker(_market_symbol(normalized_ticker))
            try:
                info = ticker.get_info() or {}
            except Exception:
                info = {}
            try:
                fast_info = ticker.fast_info
            except Exception:
                fast_info = {}
        name = str(
            info.get("longName")
            or info.get("shortName")
            or quote.get("longName")
            or quote.get("shortName")
            or normalized_ticker
        ).strip()
        price = _first_number(
            info.get("regularMarketPrice"),
            info.get("currentPrice"),
            fast_info.get("lastPrice") if hasattr(fast_info, "get") else None,
            _quote_price(quote),
        )
        if price is None:
            return {"status": "error", "ticker": normalized_ticker, "message": "가격 원본을 찾지 못했습니다."}

        metadata = _metadata_from_sources(normalized_ticker, name, info, quote, price)
        existing = _latest_data_row(normalized_ticker)
        # 현재 가격·보수·NAV·갱신 시각이 설명에 반영되도록 동기화 때마다 설명을 재생성합니다.
        description = _korean_etf_description(normalized_ticker, name, metadata)
        payload = {
            "ticker": normalized_ticker,
            "name": name,
            "price": price,
            "description": description,
            "holdings_json": metadata,
        }
        response = _save_by_ticker("etf_data", payload)
        return {
            "status": "success",
            "ticker": normalized_ticker,
            "price": price,
            "description_enriched": not _description_is_verified(existing.get("description") if existing else None),
            "data": response.data,
        }
    except Exception as exc:
        print(f"ETF 개별 업데이트 실패 ({normalized_ticker}): {type(exc).__name__}")
        return {"status": "error", "ticker": normalized_ticker, "message": type(exc).__name__}


def discover_top_etfs(limit: int = 100) -> list[dict[str, Any]]:
    """Yahoo Finance 공개 ETF 스크리너에서 가격·보수·수익률 메타데이터가 포함된 상위 ETF를 가져옵니다."""
    request_params = {
        "formatted": "false",
        "scrIds": "top_etfs_us",
        "count": min(max(limit, 1), 250),
    }
    last_error: requests.RequestException | None = None
    for endpoint in YAHOO_ETF_SCREENER_URLS:
        try:
            response = requests.get(endpoint, params=request_params, headers=REQUEST_HEADERS, timeout=25)
            response.raise_for_status()
            payload = response.json()
            results = payload.get("finance", {}).get("result", [])
            quotes = results[0].get("quotes", []) if results else []
            discovered = [
                quote for quote in quotes
                if quote.get("symbol") and quote.get("quoteType") in (None, "ETF") and _quote_price(quote) is not None
            ]
            if discovered:
                return discovered
        except requests.RequestException as exc:
            last_error = exc
    if last_error:
        raise last_error
    return []


def discover_krx_etfs(limit: int = 100) -> list[dict[str, Any]]:
    """국내 상장 ETF 공개 목록에서 시가총액 기준 상위 종목의 한글 상품명·현재가·NAV를 가져옵니다."""
    response = requests.get(NAVER_ETF_LIST_URL, headers=REQUEST_HEADERS, timeout=25)
    response.raise_for_status()
    payload = response.json()
    items = payload.get("result", {}).get("etfItemList", [])
    quotes: list[dict[str, Any]] = []
    for item in items:
        ticker = str(item.get("itemcode") or "").upper().strip()
        name = str(item.get("itemname") or "").strip()
        price = _as_float(item.get("nowVal"))
        if not ticker or not name or price is None or price <= 0:
            continue
        tab_code = int(item.get("etfTabCode") or 0)
        quotes.append(
            {
                "symbol": ticker,
                "quoteType": "ETF",
                "longName": name,
                "shortName": name,
                "regularMarketPrice": price,
                "currency": "KRW",
                "fullExchangeName": "한국거래소",
                "exchange": "KRX",
                "nav": item.get("nav"),
                "changeRate": item.get("changeRate"),
                "threeMonthEarnRate": item.get("threeMonthEarnRate"),
                "marketSum": item.get("marketSum"),
                "_market": "KRX",
                "_category_ko": KRX_CATEGORY_BY_TAB.get(tab_code, "국내 상장 ETF"),
                "_source": "네이버 금융 공개 ETF 목록",
            }
        )
    quotes.sort(key=lambda quote: _as_float(quote.get("marketSum")) or 0, reverse=True)
    return quotes[: min(max(limit, 1), 250)]


def get_all_registered_tickers() -> list[str]:
    """활성화된 ETF 레지스트리의 티커를 중복 없이 반환합니다."""
    try:
        response = supabase.table("etf_registry").select("ticker").eq("is_active", True).execute()
        return list(dict.fromkeys(str(item["ticker"]).upper() for item in response.data or [] if item.get("ticker")))
    except Exception as exc:
        print(f"ETF 레지스트리 조회 실패: {type(exc).__name__}")
        return []


def batch_latest_prices(tickers: list[str]) -> dict[str, float]:
    """등록 ETF의 종가를 최대 75개씩 묶어 가져와 개별 Yahoo 요청의 지연·제한을 피합니다."""
    normalized = list(dict.fromkeys(ticker.strip().upper() for ticker in tickers if ticker))
    prices: dict[str, float] = {}
    for start in range(0, len(normalized), 75):
        batch = normalized[start : start + 75]
        market_symbols = [_market_symbol(ticker) for ticker in batch]
        try:
            frame = yf.download(
                tickers=market_symbols,
                period="5d",
                interval="1d",
                group_by="ticker",
                auto_adjust=False,
                threads=True,
                progress=False,
                timeout=15,
            )
        except Exception:
            continue
        for ticker, market_symbol in zip(batch, market_symbols):
            try:
                if len(market_symbols) == 1:
                    close = frame["Close"].dropna()
                else:
                    close = frame[market_symbol]["Close"].dropna()
                if not close.empty:
                    value = _as_float(close.iloc[-1])
                    if value is not None and value > 0:
                        prices[ticker] = value
            except Exception:
                continue
    return prices


def refresh_etf_universe(limit: int = 100) -> dict[str, Any]:
    """국내·해외 유동성 ETF 발견, 가격·상품 설명 갱신, 기존 등록 종목 보강을 하나의 작업으로 수행합니다."""
    source_errors: list[str] = []
    try:
        us_quotes = discover_top_etfs(limit)
    except Exception as exc:
        us_quotes = []
        source_errors.append(f"해외 ETF 원본: {type(exc).__name__}")
    try:
        krx_quotes = discover_krx_etfs(limit)
    except Exception as exc:
        krx_quotes = []
        source_errors.append(f"국내 ETF 원본: {type(exc).__name__}")

    quote_by_ticker = {
        str(item["symbol"]).upper(): item
        for item in [*us_quotes, *krx_quotes]
        if item.get("symbol")
    }
    if not quote_by_ticker:
        raise RuntimeError("국내·해외 ETF 원본을 모두 불러오지 못했습니다.")

    registered = 0
    registry_failures = 0

    for ticker in quote_by_ticker:
        try:
            _save_by_ticker("etf_registry", {"ticker": ticker, "weight": 0, "is_active": True})
            registered += 1
        except Exception:
            registry_failures += 1

    registered_tickers = get_all_registered_tickers()
    active_tickers = list(dict.fromkeys([*quote_by_ticker.keys(), *registered_tickers]))
    legacy_tickers = [ticker for ticker in registered_tickers if ticker not in quote_by_ticker]
    legacy_prices = batch_latest_prices(legacy_tickers)
    for ticker, price in legacy_prices.items():
        existing = _latest_data_row(ticker) or {}
        metadata = existing.get("holdings_json") if isinstance(existing.get("holdings_json"), dict) else {}
        quote_by_ticker[ticker] = {
            "symbol": ticker,
            "quoteType": "ETF",
            "longName": existing.get("name") or metadata.get("official_name") or ticker,
            "regularMarketPrice": price,
            "currency": metadata.get("currency"),
            "fullExchangeName": metadata.get("exchange"),
            "_market": metadata.get("market"),
            "_source": "Yahoo Finance 일괄 시세 갱신",
        }

    price_updated = 0
    description_enriched = 0
    failures: list[str] = []
    for ticker in active_tickers:
        result = update_etf_data_by_ticker(ticker, quote_by_ticker.get(ticker))
        if result["status"] == "success":
            price_updated += 1
            description_enriched += int(bool(result.get("description_enriched")))
        else:
            failures.append(f"{ticker}: {result.get('message', '데이터 조회 실패')}")

    return {
        "discovered": len(quote_by_ticker),
        "discovered_us": len(us_quotes),
        "discovered_krx": len(krx_quotes),
        "registered": registered,
        "active_tickers": len(active_tickers),
        "price_updated": price_updated,
        "description_enriched": description_enriched,
        "registry_failure_count": registry_failures,
        "legacy_price_updated": len(legacy_prices),
        "failure_count": len(failures),
        "failures": failures[:10],
        "source_failure_count": len(source_errors),
        "source_errors": source_errors,
        "source": "Yahoo Finance 공개 ETF 메타데이터 + 네이버 금융 공개 ETF 목록",
        "completed_at": datetime.now(timezone.utc).isoformat(),
    }


def add_to_registry(ticker: str, weight: float) -> dict[str, Any]:
    """관리자 수동 등록 ETF도 다음 자동 동기화부터 전수 갱신 대상에 포함합니다."""
    try:
        normalized = ticker.strip().upper()
        response = _save_by_ticker("etf_registry", {"ticker": normalized, "weight": weight, "is_active": True})
        return {"status": "success", "data": response.data}
    except Exception as exc:
        print(f"ETF 레지스트리 등록 실패: {type(exc).__name__}")
        return {"status": "error", "message": type(exc).__name__}
