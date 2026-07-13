import json
import time
import schedule
import google.generativeai as genai
from supabase import create_client, Client
import os

# 1. 설정 (환경변수 권장, 로컬 테스트 시에는 아래 값을 직접 넣어주셔도 됩니다)
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://ckzaqaxhzbqydiwrbkas.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "sb_publishable_zZgUzW8_1mjzz6_C7DoN-w_XtAy7Cfs")
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

genai.configure(api_key=os.environ.get("GEMINI_API_KEY", "AIzaSyDUEPVkUDFXL1vBQh27c0w61_huIu4W6L8"))

def generate_and_upload_report():
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 리포트 생성 시작...")
    try:
        model = genai.GenerativeModel('models/gemini-1.5-flash') # 안정적인 모델로 변경
        
        prompt = """
        너는 20년 차 월스트리트 전략가다. 야후 뉴스(https://www.yahoo.com/news/)를 분석하여 리포트를 작성하라.
        
        [핵심 지침]
        1. 시장의 판도를 바꿀 메가 이벤트(예: SK하이닉스 ADR 상장 등)는 반드시 1순위로 배치하라.
        2. 시장을 움직이는 핵심 테마 3가지를 분석하라.
        3. '병력 철수 시점(손절 및 익절)'을 명확하게 포함한 전략을 제시하라.
        
        [출력 포맷: 반드시 JSON으로만 응답할 것]
        {
            "title": "여기에 제목",
            "preview": "여기에 200자 내외 요약",
            "content": "여기에 마크다운 본문(## 📊, ### 등 포함)",
            "category": "레포트"
        }
        """
        
        response = model.generate_content(prompt)
        raw_text = response.text.replace('```json', '').replace('```', '')
        report_data = json.loads(raw_text)
        
        data = {
            "title": report_data["title"], 
            "preview": report_data["preview"],
            "content": report_data["content"],
            "category": report_data["category"],
            "is_published": True,
            "access_type": "free"
        }
        
        supabase.table("analysis_posts").insert(data).execute()
        print(f"성공: {data['title']} 배포 완료!")
        
    except Exception as e:
        print(f"오류 발생: {e}")

# 2. 스케줄 설정 (매일 08시, 12시, 15시에 실행)
schedule.every().day.at("08:00").do(generate_and_upload_report)
schedule.every().day.at("12:00").do(generate_and_upload_report)
schedule.every().day.at("15:00").do(generate_and_upload_report)

if __name__ == "__main__":
    print("자동 리포트 시스템이 시작되었습니다.")
    # 즉시 테스트하고 싶다면 아래 주석을 푸세요
    # generate_and_upload_report()
    
    while True:
        schedule.run_pending()
        time.sleep(60) # 1분마다 스케줄 확인