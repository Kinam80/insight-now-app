import os
from dotenv import load_dotenv

load_dotenv()

# 환경변수 (Render 배포용)
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY")
JWT_SECRET = os.getenv("JWT_SECRET")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")
TOSS_CLIENT_KEY = os.getenv("TOSS_CLIENT_KEY")
TOSS_SECRET_KEY = os.getenv("TOSS_SECRET_KEY")

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, news, posts, payments, admin
from app.news_service import fetch_and_save_news
from apscheduler.schedulers.background import BackgroundScheduler
from fastapi.staticfiles import StaticFiles

app = FastAPI(title="Insight Now API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(news.router)
app.include_router(posts.router)
app.include_router(payments.router)
app.include_router(admin.router)
app.mount("/admin", StaticFiles(directory="app/static/admin", html=True), name="admin")

# 스케줄러 설정 (1시간마다 뉴스 수집)
scheduler = BackgroundScheduler()
scheduler.add_job(fetch_and_save_news, "interval", hours=1)
scheduler.start()

@app.on_event("startup")
async def startup_event():
    print("🚀 서버 시작 - 뉴스 첫 수집 시작!")
    fetch_and_save_news()

@app.get("/")
def root():
    return {"message": "Insight Now API 서버 정상 작동 중 🚀"}