from app.database import supabase
from datetime import datetime, timezone, timedelta

# 한국 시간대(KST) 설정
KST = timezone(timedelta(hours=9))

class NewsService:
    @staticmethod
    def save_news(category: str, title: str, summary: str, content: str = ""):
        """
        뉴스 데이터를 데이터베이스(ai_news 테이블)에 저장합니다.
        created_at은 한국 시간(KST) 기준으로 저장됩니다.
        """
        try:
            data = {
                "category": category,
                "title": title,
                "summary": summary,
                "content": content,
                # UTC 대신 한국 시간(KST)으로 저장하여 시간 오차 해결
                "created_at": datetime.now(KST).isoformat()
            }
            response = supabase.table("ai_news").insert(data).execute()
            return response.data
        except Exception as e:
            print(f"❌ 뉴스 저장 실패: {e}")
            return None

    @staticmethod
    def fetch_and_process_news():
        """
        뉴스 수집 로직(크롤링 또는 API 호출)입니다.
        """
        print("🚀 뉴스 수집 및 정제 작업 시작...")
        # 여기에 추후 뉴스 수집 로직을 구현하고 save_news를 호출하세요.
        pass