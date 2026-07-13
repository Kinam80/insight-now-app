import json
import time
import schedule
from google import genai
from supabase import create_client, Client
import os
from dotenv import load_dotenv

# 경로 설정
base_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
dotenv_path = os.path.join(base_dir, '.env')
load_dotenv(dotenv_path=dotenv_path)

# 환경 변수 확인
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_ANON_KEY")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

# 클라이언트 초기화
client = genai.Client(api_key=GEMINI_API_KEY)
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

def generate_and_upload_report():
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] 리포트 생성 시작...")
    
    # 모델명은 요청하신 대로 gemini-3.5-flash로 고정합니다.
    model_name = "gemini-3.5-flash"
    
    # 프롬프트: 표 사용 금지 및 리스트 형식 강제
    prompt = """
    너는 20년 차 월스트리트 전략가다. 야후 뉴스를 분석하여 리포트를 작성하라.
    [필수 제약 사항]
    1. 반드시 JSON 형식으로만 응답할 것.
    2. 표(Table)는 절대 사용하지 말고, 리스트(bullet points)로만 작성할 것.
    3. 문장은 짧고 간결하게 작성할 것.
    
    [출력 포맷: 반드시 아래 형식을 지킬 것]
    {"title": "제목", "preview": "요약", "content": "마크다운본문", "category": "레포트"}
    
    [마크다운 본문 구성]
    1. 🚨 오늘의 메가 이벤트: (이슈명 및 시장 파급력)
    2. 핵심 테마 TOP 3: (분석)
    3. 주요 섹터/종목 브리핑: (섹터별 요약)
    4. 베테랑의 전략 (Strategy):
       - 손절/익절: 병력 철수 시점 및 기술적 제언
       - 투자 지침: 구체적 대응 방향
    """
    
    try:
        response = client.models.generate_content(
            model=model_name, 
            contents=prompt
        )
        
        # JSON 파싱을 위한 전처리
        raw_text = response.text.replace('```json', '').replace('```', '').strip()
        report_data = json.loads(raw_text)
        
        data = {
            "title": report_data["title"], 
            "preview": report_data["preview"],
            "content": report_data["content"],
            "category": report_data["category"],
            "is_published": True,
            "access_type": "free",
            "author_id": "8d8aed4f-97da-4cbb-b552-dd07215dbc62"
        }
        
        supabase.table("analysis_posts").insert(data).execute()
        print(f"성공: {data['title']} 배포 완료!")
        
    except Exception as e:
        print(f"[ERROR] 리포트 생성 중 오류 발생: {e}")

# 스케줄 설정: 08:00, 12:00, 15:00
#schedule.every().day.at("08:00").do(generate_and_upload_report)
#schedule.every().day.at("12:00").do(generate_and_upload_report)
#schedule.every().day.at("15:00").do(generate_and_upload_report)

#if __name__ == "__main__":
    #print("자동 리포트 시스템이 시작되었습니다.")
    #while True:
        #schedule.run_pending()
        #time.sleep(60)
if __name__ == "__main__":
    # 예약된 스케줄러가 아니라, 호출 즉시 실행되도록 변경
    generate_and_upload_report()