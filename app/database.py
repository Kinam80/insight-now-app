import os

from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
# 기존 배포 설정과의 호환성을 위해 두 이름을 모두 지원합니다.
SUPABASE_KEY = os.getenv("SUPABASE_SECRET_KEY") or os.getenv("SUPABASE_ANON_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError(
        "Supabase 환경변수가 없습니다. SUPABASE_URL과 "
        "SUPABASE_SECRET_KEY 또는 SUPABASE_ANON_KEY를 설정하세요."
    )

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
