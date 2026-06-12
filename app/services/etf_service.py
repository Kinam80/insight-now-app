import yfinance as yf
# 형님의 database.py 파일에서 생성한 supabase 클라이언트를 가져옵니다.
from app.database import supabase 

def update_etf_data_by_ticker(ticker_symbol: str):
    """특정 티커의 정보를 수집하여 Supabase etf_data 테이블에 저장/갱신합니다."""
    # [수정] 한국 주식 티커 처리: .KS나 .KQ가 없으면 .KS를 자동으로 붙임
    search_ticker = ticker_symbol
    if not any(x in search_ticker for x in [".KS", ".KQ"]):
        search_ticker = f"{search_ticker}.KS"
        
    try:
        ticker = yf.Ticker(search_ticker)
        info = ticker.info
        
        # 'regularMarketPrice'가 없으면 'currentPrice'로 시도 (데이터 안정성 향상)
        price = info.get("regularMarketPrice") or info.get("currentPrice")
        
        data_to_save = {
            "ticker": ticker_symbol, # DB에는 원본 ticker 번호 저장
            "price": price,
            "description": info.get("longBusinessSummary"),
        }
        
        response = supabase.table("etf_data").upsert(data_to_save).execute()
        return {"status": "success", "data": response.data}
    
    except Exception as e:
        print(f"Error updating {ticker_symbol}: {e}")
        return {"status": "error", "message": str(e)}

def get_all_registered_tickers():
    """etf_registry 테이블에서 사용 중(is_active=True)인 티커 목록만 가져옵니다."""
    response = supabase.table("etf_registry").select("ticker").eq("is_active", True).execute()
    return [item['ticker'] for item in response.data]

def add_to_registry(ticker: str, weight: float):
    """etf_registry 테이블에 티커와 비중을 등록하거나 업데이트합니다."""
    try:
        data = {
            "ticker": ticker,
            "weight": weight,
            "is_active": True
        }
        # etf_registry 테이블에 upsert (중복 시 업데이트)
        response = supabase.table("etf_registry").upsert(data).execute()
        return {"status": "success", "data": response.data}
    except Exception as e:
        print(f"Error adding to registry: {e}")
        return {"status": "error", "message": str(e)}