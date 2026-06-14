import os
import time
import math
import asyncio
from dotenv import load_dotenv
import yfinance as yf
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from apscheduler.schedulers.background import BackgroundScheduler
from pydantic import BaseModel
# 기존 import문들 아래에 추가
from app.database import supabase

# 서비스 함수 임포트
from app.services.etf_service import update_etf_data_by_ticker, get_all_registered_tickers, add_to_registry

# 내부 모듈 임포트
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

# --- 종목 등록용 데이터 모델 ---
class EtfRegistration(BaseModel):
    ticker: str
    weight: float

# --- 시장 데이터 캐시 ---
market_data_cache = {"data": [], "last_updated": 0}

def fetch_market_data():
    tickers = {
        "코스피": "^KS11", "코스닥": "^KQ11", "나스닥": "^IXIC",
        "S&P 500": "^GSPC", "공포지수(VIX)": "^VIX", "미 10년물 국채": "^TNX"
    }
    results = []
    for name, symbol in tickers.items():
        try:
            ticker = yf.Ticker(symbol)
            data = ticker.history(period="5d")
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
    if time.time() - market_data_cache["last_updated"] > 60 or not market_data_cache["data"]:
        market_data_cache["data"] = fetch_market_data()
        market_data_cache["last_updated"] = time.time()
    return market_data_cache["data"]

# --- ETF 관리 API (등록 및 업데이트) ---

@app.post("/etf/register")
async def register_etf(data: EtfRegistration):
    """새 종목번호를 등록하고 즉시 데이터를 갱신합니다."""
    try:
        add_to_registry(data.ticker, data.weight)
        update_res = update_etf_data_by_ticker(data.ticker)
        return {"message": "등록 및 업데이트 완료", "ticker": data.ticker, "result": update_res}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
@app.get("/etf/list")
async def get_etf_list():
    """등록된 모든 ETF 목록을 가져옵니다."""
    try:
        # Supabase에서 데이터 조회
        response = supabase.table("etf_registry").select("*").eq("is_active", True).execute()
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/etfs/{ticker}")
async def get_etf_detail(ticker: str):
    """특정 ETF의 상세 정보를 조회합니다."""
    try:
        # Supabase에서 해당 ticker 정보 조회
        response = supabase.table("etf_registry").select("*").eq("ticker", ticker).single().execute()
        if not response.data:
            raise HTTPException(status_code=404, detail="ETF를 찾을 수 없습니다.")
        return response.data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/admin/update-etf")
async def trigger_etf_update():
    """모든 등록된 종목번호를 한 번에 업데이트합니다."""
    tickers = get_all_registered_tickers()
    results = []
    for ticker in tickers:
        res = update_etf_data_by_ticker(ticker)
        results.append({"ticker": ticker, "result": res})
    return {"message": "업데이트 완료", "details": results}
# main.py 또는 admin.py에 추가
@app.get("/admin/stats")
async def get_admin_stats():
    # 여기서 DB(Supabase)에서 유저 수, 수익 등을 조회하는 로직 필요
    return {
        "total_users": 100, 
        "total_revenue": 50000, 
        "total_posts": 10,
        "total_transactions": 5,
        "avg_price": 5000
    }
# 삭제 기능을 위한 엔드포인트 추가
@app.delete("/etf/unregister/{ticker}")
async def unregister_etf(ticker: str):
    """지정된 종목번호를 레지스트리에서 삭제합니다."""
    try:
        # Supabase에서 해당 ticker를 삭제하는 로직
        response = supabase.table("etf_registry").delete().eq("ticker", ticker).execute()
        return {"message": f"{ticker} 삭제 완료", "data": response.data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
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
    asyncio.create_task(background_init())

async def background_init():
    try:
        await asyncio.to_thread(fetch_and_save_news)
        data = await asyncio.to_thread(fetch_market_data)
        if data:
            market_data_cache["data"] = data
            market_data_cache["last_updated"] = time.time()
        print("✅ 초기 데이터 로드 완료")
    except Exception as e:
        print(f"⚠️ 초기화 중 경고: {e}")