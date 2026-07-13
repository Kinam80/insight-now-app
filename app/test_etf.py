import os
from dotenv import load_dotenv, find_dotenv

print(f"[DEBUG] 현재 작업 디렉토리: {os.getcwd()}")

# 1. 파일 자동 탐색 및 로드 시도
dotenv_path = find_dotenv()
print(f"[DEBUG] find_dotenv가 찾은 .env 경로: {dotenv_path}")

load_dotenv(dotenv_path=dotenv_path, override=True)

# 2. 결과 검증
keys_to_check = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "GEMINI_API_KEY"]
print("\n--- 환경 변수 확인 결과 ---")
for key in keys_to_check:
    val = os.environ.get(key)
    if val:
        print(f"[PASS] {key}: {val[:10]}... (로드 성공)")
    else:
        print(f"[FAIL] {key}: 찾을 수 없음 (None)")

# 3. 환경 변수 강제 주입 테스트 (로드가 안 될 경우를 대비)
if not os.environ.get("SUPABASE_ANON_KEY"):
    print("\n[알림] 로드 실패. 환경 변수를 직접 삽입합니다.")
    os.environ["SUPABASE_ANON_KEY"] = "TEST_KEY_123"
    print(f"강제 삽입 확인: {os.environ.get('SUPABASE_ANON_KEY')}")