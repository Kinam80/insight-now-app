import yfinance as yf
import json

def test_fetch():
    # SOL AI반도체 소부장 ETF 티커
    ticker = yf.Ticker("294870.KS")
    info = ticker.info
    
    # 우리가 필요한 핵심 데이터만 쏙 뽑아봅니다.
    data = {
        "종목명": info.get("shortName"),
        "현재가": info.get("regularMarketPrice"),
        "설명": info.get("longBusinessSummary"),
        "통화": info.get("currency"),
        "전체 데이터 샘플": info # 이걸 보면 다른 어떤 정보가 있는지 다 알 수 있습니다.
    }
    
    # 보기 좋게 출력
    print(json.dumps(data, indent=4, ensure_ascii=False))

if __name__ == "__main__":
    test_fetch()