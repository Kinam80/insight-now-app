from supabase import create_client, Client, ClientOptions
from dotenv import load_dotenv
import os
import httpx

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY")

# 타임아웃 설정 (연결 대기 10초, 전체 응답 대기 30초)
timeout = httpx.Timeout(30.0, connect=10.0)

# ✅ 수정된 부분: ClientOptions 객체를 사용하여 설정을 전달합니다.
supabase: Client = create_client(
    SUPABASE_URL, 
    SUPABASE_SECRET_KEY,
    options=ClientOptions(http_options={"timeout": timeout})
)