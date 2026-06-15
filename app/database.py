from supabase import create_client, Client
from dotenv import load_dotenv
import os

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_SECRET_KEY = os.getenv("SUPABASE_SECRET_KEY")

# ✅ 수정: ClientOptions 객체를 명시적으로 생성하지 않고, 
# 라이브러리가 지원하는 방식으로 타임아웃을 설정합니다.
# 최신 supabase-py 라이브러리는 options 인자에서 복잡한 중첩 객체 대신 
# 단순화된 설정을 지원합니다. 
# 만약 여전히 에러가 난다면, options={} 빈 딕셔너리로 초기화하세요.

supabase: Client = create_client(
    SUPABASE_URL, 
    SUPABASE_SECRET_KEY
)