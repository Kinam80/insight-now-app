import yfinance as yf
from app.database import supabase 

def update_etf_data_by_ticker(ticker_symbol: str):
    """특정 티커의 정보를 수집하여 Supabase etf_data 테이블에 저장/갱신합니다."""
    
    # 1. 한국 주식 티커 처리 (.KS / .KQ 자동 추가)
    search_ticker = ticker_symbol
    if not any(x in search_ticker for x in [".KS", ".KQ"]):
        search_ticker = f"{search_ticker}.KS"
        
    try:
        # 2. 데이터 수집
        ticker = yf.Ticker(search_ticker)
        info = ticker.info
        
        # 3. 데이터 추출 (가격 및 이름)
        price = info.get("regularMarketPrice") or info.get("currentPrice")
        name = info.get("shortName") or info.get("longName")
        
        # 4. 저장할 데이터 구성
        # description은 자동 수집이 불가능하므로, 기존 값이 있다면 유지하거나 None으로 저장
        # (관리자 페이지에서 수동으로 업데이트하는 구조를 위한 준비)
        data_to_save = {
            "ticker": ticker_symbol, 
            "name": name,
            "price": price,
        }
        
        # 5. Supabase 업데이트
        response = supabase.table("etf_data").upsert(data_to_save).execute()
        return {"status": "success", "data": response.data}
    
    except Exception as e:
        print(f"Error updating {ticker_symbol}: {e}")
        return {"status": "error", "message": str(e)}

def get_all_registered_tickers():
    """etf_registry 테이블에서 사용 중(is_active=True)인 티커 목록만 가져옵니다."""
    try:
        response = supabase.table("etf_registry").select("ticker").eq("is_active", True).execute()
        return [item['ticker'] for item in response.data]
    except Exception as e:
        print(f"Error fetching tickers: {e}")
        return []

def add_to_registry(ticker: str, weight: float):
    """etf_registry 테이블에 티커와 비중을 등록하거나 업데이트합니다."""
    try:
        data = {
            "ticker": ticker,
            "weight": weight,
            "is_active": True
        }
        response = supabase.table("etf_registry").upsert(data).execute()
        return {"status": "success", "data": response.data}
    except Exception as e:
        print(f"Error adding to registry: {e}")
        return {"status": "error", "message": str(e)}