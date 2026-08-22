import os

from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
# 기존 배포 설정과의 호환성을 위해 두 이름을 모두 지원합니다.
SUPABASE_KEY = (
    os.getenv("SUPABASE_KEY")
    or os.getenv("SUPABASE_ANON_KEY")
    or os.getenv("SUPABASE_SECRET_KEY")
)

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError(
        "Supabase 환경변수가 없습니다. SUPABASE_URL과 "
        "SUPABASE_SECRET_KEY 또는 SUPABASE_ANON_KEY를 설정하세요."
    )

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# 뉴스 수집·관리 작업처럼 쓰기 권한이 필요한 서버 작업용 클라이언트입니다.
# Secret key가 없으면 anon key를 사용하되, Supabase RLS에 따라 쓰기가 거부될 수 있습니다.
SUPABASE_ADMIN_KEY = os.getenv("SUPABASE_SECRET_KEY") or SUPABASE_KEY
supabase_admin: Client = create_client(SUPABASE_URL, SUPABASE_ADMIN_KEY)
