import feedparser
from groq import Groq
from dotenv import load_dotenv
import os
from app.database import supabase_admin as supabase
from datetime import datetime

load_dotenv()

client = Groq(api_key=os.getenv("GROQ_API_KEY"))

RSS_FEEDS = [
    {
        "url": "https://news.google.com/rss/search?q=미국+증시+나스닥&hl=ko&gl=KR&ceid=KR:ko",
        "category": "us_market"
    },
    {
        "url": "https://news.google.com/rss/search?q=코스피+코스닥+한국증시&hl=ko&gl=KR&ceid=KR:ko",
        "category": "kr_market"
    },
    {
        "url": "https://news.google.com/rss/search?q=환율+달러+원화&hl=ko&gl=KR&ceid=KR:ko",
        "category": "fx_rate"
    },
    {
        "url": "https://news.google.com/rss/search?q=국채+금리+연준&hl=ko&gl=KR&ceid=KR:ko",
        "category": "bond_rate"
    },
]

def summarize_news(title: str, description: str) -> dict:
    prompt = f"""다음 뉴스를 분석해줘.

제목: {title}
내용: {description}

아래 형식으로 정확히 답해줘:
요약: (핵심 내용을 3줄 이내로 요약)
중요도: (1~5 숫자만)
"""
    try:
        response = client.chat.completions.create(
            model="llama-3.1-8b-instant",
            messages=[{"role": "user", "content": prompt}],
            max_tokens=300,
        )
        text = response.choices[0].message.content.strip()

        summary = ""
        importance = 3

        for line in text.split("\n"):
            if line.startswith("요약:"):
                summary = line.replace("요약:", "").strip()
            elif line.startswith("중요도:"):
                try:
                    importance = int(line.replace("중요도:", "").strip()[0])
                except:
                    importance = 3

        if not summary:
            summary = text[:200]

        return {"summary": summary, "importance": importance}
    except Exception as e:
        print(f"AI 요약 실패: {e}")
        return {"summary": title, "importance": 3}

def fetch_and_save_news():
    print(f"\n🔍 뉴스 수집 시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    saved_count = 0

    for feed_info in RSS_FEEDS:
        feed = feedparser.parse(feed_info["url"])

        for entry in feed.entries[:5]:
            title = entry.get("title", "")
            description = entry.get("summary", title)
            source_url = entry.get("link", "")
            source_name = entry.get("source", {}).get("title", "Google News")

            existing = supabase.table("ai_news").select("id").eq("source_url", source_url).execute()
            if existing.data:
                continue

            result = summarize_news(title, description)

            supabase.table("ai_news").insert({
                "title": title,
                "summary": result["summary"],
                "source_url": source_url,
                "source_name": source_name,
                "category": feed_info["category"],
                "importance": result["importance"],
            }).execute()

            saved_count += 1
            print(f"✅ 저장: {title[:40]}...")

    print(f"📰 총 {saved_count}개 뉴스 저장 완료!")
    return saved_count

if __name__ == "__main__":
    fetch_and_save_news()