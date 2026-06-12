from etf_service import update_etf_data_by_ticker, get_all_registered_tickers

def test_flow():
    print("--- 테스트 시작 ---")
    # 1. 관리 대상 티커 목록 가져오기 테스트
    tickers = get_all_registered_tickers()
    print(f"등록된 티커: {tickers}")
    
    # 2. 첫 번째 티커만 실제 수집/갱신 테스트
    if tickers:
        test_ticker = tickers[0]
        print(f"수집 테스트: {test_ticker}")
        result = update_etf_data_by_ticker(test_ticker)
        print(f"결과: {result}")

if __name__ == "__main__":
    test_flow()