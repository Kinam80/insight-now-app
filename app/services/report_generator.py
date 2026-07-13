import json
import google.generativeai as genai
from supabase import create_client, Client

# 1. 설정
SUPABASE_URL = "https://ckzaqaxhzbqydiwrbkas.supabase.co"
SUPABASE_KEY = "sb_publishable_zZgUzW8_1mjzz6_C7DoN-w_XtAy7Cfs"
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

genai.configure(api_key="AIzaSyDUEPVkUDFXL1vBQh27c0w61_huIu4W6L8")

def generate_and_upload_report():
    model = genai.GenerativeModel('models/gemini-3.5-flash')
    
    # 디테일하게 설정한 프롬프트 적용
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
    
    # AI 리포트 생성
    response = model.generate_content(prompt)
    
    # JSON 파싱 (마크다운 코드 블록 제거)
    raw_text = response.text.replace('```json', '').replace('```', '')
    report_data = json.loads(raw_text)
    
    # 2. Supabase Insert
    data = {
        "title": report_data["title"], 
        "preview": report_data["preview"],
        "content": report_data["content"],
        "category": report_data["category"],
        "is_published": True,
        "access_type": "free"
    }
    
    result = supabase.table("analysis_posts").insert(data).execute()
    print("Supabase 배포 완료! 제목:", data["title"])

if __name__ == "__main__":
    generate_and_upload_report()