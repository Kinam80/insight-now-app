from __future__ import annotations

import os
import re
from datetime import datetime
from typing import Any

import requests
from bs4 import BeautifulSoup

from app.database import supabase_admin as supabase

KDI_MONTHLY_TRENDS_URL = "https://www.kdi.re.kr/eng/research/monTrends"
REQUEST_HEADERS = {
    "User-Agent": "InsightNow/1.0 (+https://insight-now-app.onrender.com)",
    "Accept-Language": "en-US,en;q=0.9",
}


def _gemini_korean_brief(title: str, published_date: str, summary: str) -> str:
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        return summary

    try:
        from google import genai

        client = genai.Client(api_key=api_key)
        prompt = f"""
다음은 한국개발연구원(KDI)의 공식 월간 경제동향 보고서 발췌문입니다.
발췌문 밖의 사실을 추가하지 말고, 한국어로 읽기 쉬운 경제 정밀분석 브리핑을 작성하세요.
투자 권유는 하지 마세요.

보고서: {title}
발행일: {published_date}
발췌문: {summary}

마크다운 형식으로 다음만 작성하세요.
- 한 줄 핵심 진단
- 주요 실물경제·수출·소비·물가·금융 포인트 3~5개
- 불확실성 또는 유의할 위험 요인
""".strip()
        response = client.models.generate_content(
            model=os.getenv("GEMINI_GOV_MODEL", "gemini-2.5-flash"),
            contents=prompt,
            config={"temperature": 0.2, "max_output_tokens": 700},
        )
        text = (response.text or "").strip()
        return text or summary
    except Exception as exc:
        print(f"⚠️ 정부 보고서 Gemini 요약 실패: {exc}")
        return summary


def fetch_latest_kdi_report() -> dict[str, str]:
    """KDI 공식 월간 경제동향 페이지에서 최신 제목·발행일·요약을 추출합니다."""
    response = requests.get(KDI_MONTHLY_TRENDS_URL, headers=REQUEST_HEADERS, timeout=30)
    response.raise_for_status()
    soup = BeautifulSoup(response.text, "html.parser")
    text = soup.get_text("\n", strip=True)

    title_match = re.search(r"KDI Monthly Economic Trends\s+\d{4}\.\s*\d{1,2}", text)
    title = title_match.group(0) if title_match else "KDI Monthly Economic Trends"

    date_match = re.search(r"(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}", text)
    published_date = date_match.group(0) if date_match else datetime.now().strftime("%Y-%m-%d")

    summary_match = re.search(r"Summary\s+open\s+(.*?)\s+Contents\s+open", text, flags=re.DOTALL)
    raw_summary = summary_match.group(1) if summary_match else text[:2500]
    summary = re.sub(r"\s+", " ", raw_summary).strip()[:3000]
    if not summary:
        raise ValueError("KDI 보고서 요약을 추출하지 못했습니다.")

    return {"title": title, "published_date": published_date, "summary": summary}


def refresh_government_reports() -> dict[str, Any]:
    """최신 KDI 월간 경제동향을 중복 없이 gov_stats에 저장합니다."""
    report = fetch_latest_kdi_report()
    display_title = f"[KDI 경제 정밀분석] {report['title']}"
    existing = supabase.table("gov_stats").select("id").eq("title", display_title).limit(1).execute()
    if existing.data:
        return {"status": "up_to_date", "title": display_title}

    korean_brief = _gemini_korean_brief(
        report["title"], report["published_date"], report["summary"]
    )
    content = f"""# {report['title']}

**발행일:** {report['published_date']}

## 핵심 경제 브리핑

{korean_brief}

---

원문: [KDI Monthly Economic Trends]({KDI_MONTHLY_TRENDS_URL})
"""
    response = supabase.table("gov_stats").insert(
        {"title": display_title, "content": content}
    ).execute()
    return {"status": "created", "title": display_title, "data": response.data}
