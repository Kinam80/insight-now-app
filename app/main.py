import os
import time
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
# 디렉토리가 존재하지 않을 경우를 대비하여 존재 여부 확인 후 마운트하는 것이 안전합니다.
if os.path.exists("app/static/admin"):
    app.mount("/admin", StaticFiles(directory="app/static/admin", html=True), name="admin")

# --- 시장 데이터 캐시 저장소 ---
market_data_cache = {"data": [], "last_updated": 0}

def fetch_market_data():
    """데이터가 없는 경우를 완벽히 걸러내는 안전한 데이터 수집 함수"""
    tickers = {
        "코스피": "^KS11",
        "코스닥": "^KQ11",
        "나스닥": "^IXIC",
        "S&P 500": "^GSPC",
        "공포지수(VIX)": "^VIX",
        "미 10년물 국채": "^TNX"
    }
    results = []
    
    for name, symbol in tickers.items():
        try:
            ticker = yf.Ticker(symbol)
            data = ticker.history(period="5d") # 기간을 5일로 늘려 데이터 확보 확률 높임
            
            # 데이터가 비어있거나 부족하면 패스
            if data.empty or len(data) < 2:
                print(f"⚠️ {name} 데이터 부족, 건너뜀")
                continue
            
            current = float(data['Close'].iloc[-1])
            prev = float(data['Close'].iloc[-2])
            change_pct = float(((current - prev) / prev) * 100)
            
            # 국가 구분
            nation = "🇰🇷" if "코스" in name else ("🇺🇸" if name in ["나스닥", "S&P 500"] else "📊")
            
            results.append({
                "name": name,
                "value": f"{current:,.2f}",
                "change": f"{change_pct:+.2f}%",
                "isUp": bool(change_pct >= 0),
                "nation": nation
            })
        except Exception as e:
            print(f"❌ {name} 수집 실패: {e}")
            continue
            
    # 환율 추가
    try:
        fx = yf.Ticker("KRW=X")
        fx_data = fx.history(period="2d")
        if not fx_data.empty:
            fx_val = float(fx_data['Close'].iloc[-1])
            results.append({
                "name": "원·달러 환율",
                "value": f"{fx_val:,.2f}",
                "change": "실시간",
                "isUp": True,
                "nation": "💱"
            })
    except: pass
        
    return results

@app.get("/market/indices")
async def get_market_indices():
    """캐싱된 시장 데이터를 반환"""
    # 60초가 지났거나 데이터가 없을 때만 실시간 업데이트
    if time.time() - market_data_cache["last_updated"] > 60 or not market_data_cache["data"]:
        market_data_cache["data"] = fetch_market_data()
        market_data_cache["last_updated"] = time.time()
    return market_data_cache["data"]

@app.get("/")
def root():
    return {"message": "Insight Now API 서버 정상 작동 중 🚀"}

# --- 스케줄러 설정 ---
scheduler = BackgroundScheduler()
scheduler.add_job(fetch_and_save_news, "interval", hours=1)
scheduler.start()

# 서버 시작 시 이벤트
@app.on_event("startup")
async def startup_event():
    print("🚀 서버 시작 - 뉴스 및 실시간 시장 데이터 연동 완료!")
    # 비동기적으로 수행하기 위해 시도
    try:
        fetch_and_save_news()
        market_data_cache["data"] = fetch_market_data()
        market_data_cache["last_updated"] = time.time()
    except Exception as e:
        print(f"⚠️ 초기 데이터 수집 실패: {e}")