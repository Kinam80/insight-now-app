import yfinance as yf
# 형님의 database.py 파일에서 생성한 supabase 클라이언트를 가져옵니다.
from database import supabase 

def update_etf_data_by_ticker(ticker_symbol: str):
    """특정 티커의 정보를 수집하여 Supabase etf_data 테이블에 저장/갱신합니다."""
    try:
        ticker = yf.Ticker(ticker_symbol)
        info = ticker.info
        
        data_to_save = {
            "ticker": ticker_symbol,
            "price": info.get("regularMarketPrice"),
            "description": info.get("longBusinessSummary"),
        }
        
        # upsert 사용 시 ticker 컬럼이 etf_data 테이블의 유니크 키여야 합니다.
        response = supabase.table("etf_data").upsert(data_to_save).execute()
        return {"status": "success", "data": response.data}
    
    except Exception as e:
        print(f"Error updating {ticker_symbol}: {e}")
        return {"status": "error", "message": str(e)}

def get_all_registered_tickers():
    """etf_registry 테이블에서 사용 중(is_active=True)인 티커 목록만 가져옵니다."""
    response = supabase.table("etf_registry").select("ticker").eq("is_active", True).execute()
    return [item['ticker'] for item in response.data]