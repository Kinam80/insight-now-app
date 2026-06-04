from app.database import supabase
from datetime import datetime

class NewsService:
    @staticmethod
    def save_news(category: str, title: str, summary: str, content: str = ""):
        """
        뉴스 데이터를 데이터베이스(ai_news 테이블)에 저장합니다.
        """
        try:
            data = {
                "category": category,
                "title": title,
                "summary": summary,
                "content": content,
                "created_at": datetime.utcnow().isoformat()
            }
            response = supabase.table("ai_news").insert(data).execute()
            return response.data
        except Exception as e:
            print(f"❌ 뉴스 저장 실패: {e}")
            return None

    @staticmethod
    def fetch_and_process_news():
        """
        실제 뉴스 수집 로직(크롤링 또는 API 호출)이 들어갈 곳입니다.
        향후 여기에서 외부 뉴스 API를 호출하거나 크롤러를 실행합니다.
        """
        # 예시: 여기서 크롤링 로직을 호출하거나 API를 호출한 뒤,
        # 위 save_news를 통해 DB에 밀어 넣습니다.
        print("🚀 뉴스 수집 및 정제 작업 시작...")
        pass