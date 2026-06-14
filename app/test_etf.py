import sys
import os
import yfinance as yf

# 프로젝트 경로 설정
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services.etf_service import get_all_registered_tickers

def test_flow():
    print("--- 테스트 시작: 종목 정보 키 확인 ---")
    tickers = get_all_registered_tickers()
    
    if not tickers:
        print("등록된 티커가 없습니다.")
        return

    # 첫 번째 티커 사용 (232080 -> 232080.KS)
    test_ticker = f"{tickers[0]}.KS"
    print(f"[대상 티커]: {test_ticker}")
    
    ticker_obj = yf.Ticker(test_ticker)
    info = ticker_obj.info
    
    # 1. 이름 확인
    name = info.get('shortName') or info.get('longName')
    # 2. 가격 확인
    price = info.get('regularMarketPrice') or info.get('currentPrice')
    # 3. 설명 확인
    desc = info.get('longBusinessSummary')
    
    print(f"\n--- 수집된 정보 ---")
    print(f"이름(shortName/longName): {name}")
    print(f"가격(regularMarketPrice/currentPrice): {price}")
    print(f"설명(longBusinessSummary): {str(desc)[:100]}...")
    
    print(f"\n--- 사용 가능한 전체 키 목록 ---")
    print(list(info.keys()))

if __name__ == "__main__":
    test_flow()