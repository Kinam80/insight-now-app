import os
import time
import math
import asyncio
import secrets
from datetime import datetime, timezone
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from dotenv import load_dotenv
import yfinance as yf
from fastapi import Depends, FastAPI, Header, HTTPException

from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from pydantic import BaseModel
# 기존 import문들 아래에 추가
from app.database import supabase
from pathlib import Path

# 서비스 함수 임포트
from app.services.etf_service import (
    add_to_registry,
    get_all_registered_tickers,
    refresh_etf_universe,
    update_etf_data_by_ticker,
)
from app.services.gov_report_service import refresh_government_reports

# 내부 모듈 임포트
from app.routers import auth, news, posts, payments, admin, chat
from app.news_service import fetch_and_save_news

load_dotenv()

app = FastAPI(title="Insight Now API", version="1.0.0")


@app.get("/health", include_in_schema=False)
async def health_check():
    """Render health check 및 외부 모니터링용 경량 엔드포인트입니다."""
    return {
        "status": "ok",
        "service": "insight-now-api",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


# --- CORS 설정 ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 기존 코드 순서 ---
app.include_router(auth.router, prefix="/api")
app.include_router(news.router, prefix="/api")
app.include_router(posts.router, prefix="/api")
app.include_router(payments.router, prefix="/api")
app.include_router(admin.router, prefix="/api") 
app.include_router(chat.router, prefix="/api")

# 현재 main.py가 위치한 폴더의 경로를 기준으로 설정
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static", "admin")

# 수정된 부분: 정확한 절대 경로를 전달합니다.
app.mount("/admin", StaticFiles(directory=STATIC_DIR, html=True), name="admin")
# --- 종목 등록용 데이터 모델 ---
class EtfRegistration(BaseModel):
    ticker: str
    weight: float

# --- 시장 데이터 캐시 ---
market_data_cache = {"data": [], "last_updated": 0}
automation_scheduler = AsyncIOScheduler(timezone="Asia/Seoul")


def require_admin_refresh_key(
    x_admin_refresh_key: str | None = Header(default=None),
) -> None:
    """수동 데이터 갱신 API를 운영 비밀키로 보호합니다.

    주기 스케줄러는 이 키와 무관하게 서버 내부에서 실행됩니다.
    """
    expected_key = os.getenv("ADMIN_REFRESH_KEY")
    if not expected_key:
        raise HTTPException(
            status_code=503,
            detail="ADMIN_REFRESH_KEY is not configured for manual refresh APIs.",
        )
    if not x_admin_refresh_key or not secrets.compare_digest(
        x_admin_refresh_key, expected_key
    ):
        raise HTTPException(status_code=403, detail="Invalid admin refresh key.")


async def refresh_news_in_background():
    """Yahoo Finance 뉴스와 Gemini 요약을 웹 요청과 분리해 갱신합니다."""
    try:
        saved_count = await asyncio.to_thread(fetch_and_save_news)
        print(f"📰 뉴스 수집 작업 완료: {saved_count}개 저장")
    except Exception as exc:
        print(f"⚠️ 뉴스 수집 작업 실패: {exc}")


async def refresh_etfs_in_background():
    """Yahoo Finance 상위 ETF와 기존 수동 등록 ETF의 시세를 자동 동기화합니다."""
    try:
        result = await asyncio.to_thread(refresh_etf_universe, 100)
        print(f"📈 ETF 자동 갱신 완료: {result}")
    except Exception as exc:
        print(f"⚠️ ETF 자동 갱신 실패: {exc}")


async def refresh_gov_reports_in_background():
    """KDI 공식 월간 경제동향을 중복 없이 정부 보고서 탭에 저장합니다."""
    try:
        result = await asyncio.to_thread(refresh_government_reports)
        print(f"🏛️ 정부 경제보고서 갱신 완료: {result}")
    except Exception as exc:
        print(f"⚠️ 정부 경제보고서 갱신 실패: {exc}")


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

@app.get("/api/market/indices")
async def get_market_indices():
    if time.time() - market_data_cache["last_updated"] > 60 or not market_data_cache["data"]:
        market_data_cache["data"] = fetch_market_data()
        market_data_cache["last_updated"] = time.time()
    return market_data_cache["data"]

# --- ETF 관리 API (등록 및 업데이트) ---

@app.post("/api/etf/register")
async def register_etf(data: EtfRegistration):
    """새 종목번호를 등록하고 즉시 데이터를 갱신합니다."""
    try:
        add_to_registry(data.ticker, data.weight)
        update_res = update_etf_data_by_ticker(data.ticker)
        return {"message": "등록 및 업데이트 완료", "ticker": data.ticker, "result": update_res}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/etf/list")
async def get_etf_list():
    try:
        # 1. registry 목록을 가져옵니다.
        registry_res = supabase.table("etf_registry").select("*").eq("is_active", True).execute()
        
        # 2. etf_data 전체를 가져옵니다.
        data_res = supabase.table("etf_data").select("*").execute()
        
        # 3. 파이썬 로직으로 두 리스트를 합칩니다.
        combined_list = []
        for reg in registry_res.data:
            # 티커(ticker)가 같은 데이터를 찾아서 합칩니다.
            ticker = reg['ticker']
            # etf_data 리스트에서 현재 티커와 일치하는 것을 찾습니다.
            match = next((item for item in data_res.data if item['ticker'] == ticker), {})
            
            # 레지스트리(reg) + 데이터(match)를 합쳐서 새로운 객체 생성
            # 이렇게 하면 앱은 etf['name'], etf['price'] 등을 바로 쓸 수 있습니다.
            combined_item = {**reg, **match}
            combined_list.append(combined_item)
            
        return combined_list
    except Exception as e:
        print(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/etfs/{ticker}")
async def get_etf_detail(ticker: str):
    try:
        # 데이터가 여러 개여도 가장 최신 것 하나만 가져오도록 명시
        response = supabase.table("etf_registry")\
                            .select("*")\
                            .eq("ticker", ticker)\
                            .order("created_at", desc=True)\
                            .limit(1)\
                            .execute()
        
        # 데이터가 아예 없는 경우 404 처리
        if not response.data or len(response.data) == 0:
            raise HTTPException(status_code=404, detail="ETF를 찾을 수 없습니다.")
        
        return response.data[0]
    except Exception as e:
        # 에러 내용을 로그로 찍어서 확인
        print(f"Error in get_etf_detail: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/admin/update-etf")
async def trigger_etf_update(_: None = Depends(require_admin_refresh_key)):
    """전체 ETF 유니버스를 즉시 동기화합니다."""
    result = await asyncio.to_thread(refresh_etf_universe, 100)
    return {"message": "ETF 자동 동기화 완료", "details": result}

# 삭제 기능을 위한 엔드포인트 추가
@app.delete("/api/etf/unregister/{ticker}")
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

# --- 시작 이벤트 ---
# 뉴스 수집은 웹 요청 프로세스의 시작을 늦추지 않도록 별도 작업으로 운영합니다.

@app.on_event("startup")
async def startup_event():
    print("🚀 서버 초기화 시작...")
    
    # 1. 초기 데이터 로드
    asyncio.create_task(background_init())

    # 2. 뉴스·ETF·정부 경제보고서는 API 요청과 분리해 주기적으로 갱신합니다.
    if not automation_scheduler.running:
        automation_scheduler.add_job(
            refresh_news_in_background,
            trigger="interval",
            hours=2,
            id="refresh_news",
            replace_existing=True,
            max_instances=1,
            coalesce=True,
        )
        automation_scheduler.add_job(
            refresh_etfs_in_background,
            trigger="interval",
            hours=6,
            id="refresh_etfs",
            replace_existing=True,
            max_instances=1,
            coalesce=True,
        )
        automation_scheduler.add_job(
            refresh_gov_reports_in_background,
            trigger="interval",
            hours=24,
            id="refresh_government_reports",
            replace_existing=True,
            max_instances=1,
            coalesce=True,
        )
        automation_scheduler.start()
    asyncio.create_task(refresh_news_in_background())
    asyncio.create_task(refresh_etfs_in_background())
    asyncio.create_task(refresh_gov_reports_in_background())
    
    # 3. 경로 출력
    print("--- 📋 현재 등록된 API 경로 목록 ---")
    for route in app.routes:
        if hasattr(route, "methods"):
            print(f"{list(route.methods)} : {route.path}")
    print("----------------------------------")

@app.on_event("shutdown")
async def shutdown_event():
    if automation_scheduler.running:
        automation_scheduler.shutdown(wait=False)


async def background_init():
    try:
        # 외부 RSS/LLM 호출은 서버 시작 시 실행하지 않고, 실제 요청과 분리합니다.
        data = await asyncio.to_thread(fetch_market_data)
        if data:
            market_data_cache["data"] = data
            market_data_cache["last_updated"] = time.time()
        print("✅ 초기 데이터 로드 완료")
    except Exception as e:
        print(f"⚠️ 초기화 중 경고: {e}")
# --- [통로: ETF 설명 업데이트 API] ---
class EtfDescriptionUpdate(BaseModel):
    ticker: str
    description: str

@app.post("/api/etf/update-description")
async def update_etf_description(data: EtfDescriptionUpdate):
    try:
        # 이 통로를 통해 받은 데이터를 etf_data 테이블에 저장합니다.
        response = supabase.table("etf_data")\
                           .update({"description": data.description})\
                           .eq("ticker", data.ticker)\
                           .execute()
        return {"message": "설명 업데이트 성공", "data": response.data}
    except Exception as e:
        # 통로에서 에러가 발생하면 서버가 이유를 알려줍니다.
        raise HTTPException(status_code=500, detail=str(e))
# main.py 맨 아래에 추가
# --- [신규 추가: 경제 보고서 발행 API] ---
class GovStatsUpdate(BaseModel):
    title: str
    content: str

@app.post("/api/admin/gov-stats")
async def create_gov_stats(data: GovStatsUpdate):
    try:
        response = supabase.table("gov_stats").insert({
            "title": data.title,
            "content": data.content
        }).execute()
        return {"message": "보고서 저장 성공", "data": response.data}
    except Exception as e:
        print(f"Error saving report: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/gov-stats")
async def get_gov_stats(limit: int = 20):
    """정부 경제 정밀분석 보고서를 최신순으로 반환합니다."""
    try:
        response = supabase.table("gov_stats").select("*").order(
            "created_at", desc=True
        ).limit(min(max(limit, 1), 50)).execute()
        return {"status": "success", "reports": response.data}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/api/admin/refresh-gov-stats")
async def trigger_gov_stats_refresh(_: None = Depends(require_admin_refresh_key)):
    """KDI 최신 월간 경제동향을 즉시 동기화합니다."""
    result = await asyncio.to_thread(refresh_government_reports)
    return {"message": "정부 경제보고서 자동 동기화 완료", "details": result}



@app.get("/api/admin/stats")
async def get_admin_stats_direct():
    return {"total_users": 100, "total_revenue": 50000, "total_posts": 10}

@app.get("/api/admin/users")
async def get_admin_users_direct():
    return {"status": "success", "users": []}