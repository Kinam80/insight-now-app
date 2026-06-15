from supabase import create_client, Client
from dotenv import load_dotenv
import os
import httpx

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY")

# 타임아웃 설정
timeout = httpx.Timeout(30.0, connect=10.0)

# ✅ 수정된 부분: options 매개변수를 추가하여 timeout을 전달합니다.
supabase: Client = create_client(
    SUPABASE_URL, 
    SUPABASE_SECRET_KEY,
    options={"http_options": {"timeout": timeout}}
)