import os
import time
import math
import asyncio
from dotenv import load_dotenv
import yfinance as yf
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from apscheduler.schedulers.background import BackgroundScheduler

# --- 내부 모듈 임포트 ---
from app.routers import auth, news, posts, payments, admin, chat
from app.news_service import fetch_and_save_news

load_dotenv()

app = FastAPI(title="Insight Now API", version="1.0.0")

# --- CORS 설정 ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 라우터 등록 ---
app.include_router(auth.router)
app.include_router(news.router)
app.include_router(posts.router)
app.include_router(payments.router)
app.include_router(admin.router)
app.include_router(chat.router)

# --- 정적 파일 마운트 ---
if os.path.exists("app/static/admin"):
    app.mount("/admin", StaticFiles(directory="app/static/admin", html=True), name="admin")

# --- 시장 데이터 캐시 ---
market_data_cache = {"data": [], "last_updated": 0}

def fetch_market_data():
    """데이터 무결성(NaN 체크)이 강화된 시장 데이터 수집"""
    tickers = {
        "코스피": "^KS11", "코스닥": "^KQ11", "나스닥": "^IXIC",
        "S&P 500": "^GSPC", "공포지수(VIX)": "^VIX", "미 10년물 국채": "^TNX"
    }
    results = []
    
    for name, symbol in tickers.items():
        try:
            ticker = yf.Ticker(symbol)
            data = ticker.history(period="5d")
            
            # 1. 데이터 존재 여부 및 NaN 체크
            if data.empty or len(data) < 2: continue
            current = float(data['Close'].iloc[-1])
            prev = float(data['Close'].iloc[-2])
            
            if math.isnan(current) or math.isnan(prev): continue
            
            change_pct = ((current - prev) / prev) * 100
            
            results.append({
                "name": name,
                "value": f"{current:,.2f}",
                "change": f"{change_pct:+.2f}%",
                "isUp": change_pct >= 0,
                "nation": "🇰🇷" if "코스" in name else ("🇺🇸" if name in ["나스닥", "S&P 500"] else "📊")
            })
        except Exception: continue
            
    # 환율 추가
    try:
        fx = yf.Ticker("KRW=X")
        fx_data = fx.history(period="2d")
        if not fx_data.empty and not math.isnan(fx_data['Close'].iloc[-1]):
            results.append({
                "name": "원·달러 환율", "value": f"{float(fx_data['Close'].iloc[-1]):,.2f}",
                "change": "실시간", "isUp": True, "nation": "💱"
            })
    except: pass
        
    return results

@app.get("/market/indices")
async def get_market_indices():
    # 60초 캐시 로직
    if time.time() - market_data_cache["last_updated"] > 60 or not market_data_cache["data"]:
        market_data_cache["data"] = fetch_market_data()
        market_data_cache["last_updated"] = time.time()
    return market_data_cache["data"]

@app.get("/")
def root():
    return {"message": "Insight Now API 서버 정상 작동 중 🚀"}

# --- 스케줄러 & 시작 이벤트 ---
scheduler = BackgroundScheduler()
scheduler.add_job(fetch_and_save_news, "interval", hours=1)
scheduler.start()

@app.on_event("startup")
async def startup_event():
    print("🚀 서버 초기화 시작...")
    # 비동기 태스크로 분리하여 서버 시작 시 타임아웃 방지
    asyncio.create_task(background_init())

async def background_init():
    try:
        # 뉴스 및 지표 수집을 루프 안에서 분리
        await asyncio.to_thread(fetch_and_save_news)
        data = await asyncio.to_thread(fetch_market_data)
        if data:
            market_data_cache["data"] = data
            market_data_cache["last_updated"] = time.time()
        print("✅ 초기 데이터 로드 완료")
    except Exception as e:
        print(f"⚠️ 초기화 중 경고: {e}")