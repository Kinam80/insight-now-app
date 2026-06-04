import os
import yfinance as yf
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.background import BackgroundScheduler
from fastapi.staticfiles import StaticFiles

# 내부 모듈 임포트
from app.routers import auth, news, posts, payments, admin
from app.news_service import fetch_and_save_news

load_dotenv()

app = FastAPI(title="Insight Now API", version="1.0.0")

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 라우터 등록
app.include_router(auth.router)
app.include_router(news.router)
app.include_router(posts.router)
app.include_router(payments.router)
app.include_router(admin.router)
app.mount("/admin", StaticFiles(directory="app/static/admin", html=True), name="admin")

# --- [핵심 수정] 실시간 금융 데이터 수집 함수 ---
def get_live_market_data():
    # 주요 지수 티커: 코스피(^KS11), 코스닥(^KQ11), 나스닥(^IXIC), S&P500(^GSPC)
    tickers = {
        "코스피 (KOSPI)": "^KS11",
        "코스닥 (KOSDAQ)": "^KQ11",
        "나스닥 종합 (NASDAQ)": "^IXIC",
        "S&P 500": "^GSPC"
    }
    
    results = []
    for name, symbol in tickers.items():
        ticker = yf.Ticker(symbol)
        data = ticker.history(period="2d")
        if len(data) < 2: continue
        
        current = data['Close'].iloc[-1]
        prev = data['Close'].iloc[-2]
        change_pct = ((current - prev) / prev) * 100
        
        results.append({
            "name": name,
            "value": f"{current:,.2f}",
            "change": f"{change_pct:+.2f}%",
            "isUp": change_pct >= 0,
            "nation": "🇰🇷" if "KOS" in name else "🇺🇸"
        })
    
    # 환율 추가 (USD/KRW)
    fx = yf.Ticker("KRW=X")
    fx_data = fx.history(period="1d")
    fx_val = fx_data['Close'].iloc[-1]
    results.append({
        "name": "원·달러 환율 (USD/KRW)",
        "value": f"{fx_val:,.2f}",
        "change": "실시간",
        "isUp": True,
        "nation": "💱"
    })
    return results

# API 엔드포인트
@app.get("/market/indices")
async def get_market_indices():
    return get_live_market_data()

@app.get("/")
def root():
    return {"message": "Insight Now API 서버 정상 작동 중 🚀"}

# 스케줄러 설정
scheduler = BackgroundScheduler()
scheduler.add_job(fetch_and_save_news, "interval", hours=1)
scheduler.start()

@app.on_event("startup")
async def startup_event():
    print("🚀 서버 시작 - 뉴스 및 실시간 시장 데이터 연동 완료!")
    fetch_and_save_news()