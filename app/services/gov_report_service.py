from __future__ import annotations

import html
import os
import re
from datetime import datetime
from typing import Any

import requests
from bs4 import BeautifulSoup

from app.database import supabase_admin as supabase

KDI_MONTHLY_TRENDS_URL = "https://www.kdi.re.kr/eng/research/monTrends"
MYMEMORY_TRANSLATE_URL = "https://api.mymemory.translated.net/get"
GOOGLE_WEB_TRANSLATE_URL = "https://translate.google.com/m"
REQUEST_HEADERS = {
    "User-Agent": "InsightNow/1.0 (+https://insight-now-app.onrender.com)",
    "Accept-Language": "en-US,en;q=0.9",
}


def _has_korean(text: str) -> bool:
    return bool(re.search(r"[가-힣]", text or ""))


def _needs_korean_brief(content: str) -> bool:
    """한국어 헤더만 있고 본문은 영어인 기존 카드도 갱신 대상으로 판별합니다."""
    text = re.sub(r"https?://\S+", "", content or "")
    english_count = len(re.findall(r"[A-Za-z]", text))
    korean_count = len(re.findall(r"[가-힣]", text))
    return english_count > max(120, korean_count * 2)


def _translate_with_mymemory(text: str) -> str:
    """키가 없는 환경을 위한 짧은 문장 번역 보조 경로입니다."""
    try:
        response = requests.get(
            MYMEMORY_TRANSLATE_URL,
            params={"q": text, "langpair": "en|ko"},
            headers={"User-Agent": "InsightNow/1.0"},
            timeout=12,
        )
        payload = response.json()
        translated = html.unescape(
            str((payload.get("responseData") or {}).get("translatedText") or "")
        ).strip()
        return translated if response.status_code == 200 and _has_korean(translated) else ""
    except (requests.RequestException, ValueError, TypeError):
        return ""


def _translate_with_google_web(text: str) -> str:
    """MyMemory가 일시 제한될 경우 사용할 Google 모바일 번역 보조 경로입니다."""
    try:
        response = requests.get(
            GOOGLE_WEB_TRANSLATE_URL,
            params={"sl": "en", "tl": "ko", "q": text},
            headers={
                "User-Agent": "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36",
                "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.7",
            },
            timeout=12,
        )
        node = BeautifulSoup(response.text, "html.parser").select_one(
            "div.result-container"
        )
        translated = node.get_text(" ", strip=True) if node else ""
        return translated if response.status_code == 200 and _has_korean(translated) else ""
    except requests.RequestException:
        return ""


def _chunks(text: str, limit: int = 1400) -> list[str]:
    """무료 번역 보조 경로의 URL 길이를 넘지 않도록 문장 단위로 나눕니다."""
    normalized = re.sub(r"\s+", " ", text).strip()
    if len(normalized) <= limit:
        return [normalized] if normalized else []

    pieces = re.split(r"(?<=[.!?])\s+", normalized)
    result: list[str] = []
    current = ""
    for piece in pieces:
        if len(piece) > limit:
            if current:
                result.append(current)
                current = ""
            result.extend(piece[i : i + limit] for i in range(0, len(piece), limit))
        elif len(current) + len(piece) + 1 <= limit:
            current = f"{current} {piece}".strip()
        else:
            if current:
                result.append(current)
            current = piece
    if current:
        result.append(current)
    return result


def _korean_display_title(published_date: str) -> str:
    date_match = re.search(r"(\d{4})\.\s*(\d{1,2})", published_date)
    if date_match:
        return f"[KDI 경제 정밀분석] KDI 월간 경제동향 {date_match.group(1)}년 {int(date_match.group(2))}월"
    return "[KDI 경제 정밀분석] KDI 월간 경제동향"


def _fallback_korean_brief(title: str, published_date: str, summary: str) -> str:
    """LLM 키가 없어도 원문 범위 안에서 한국어 핵심 브리핑을 제공합니다."""
    translated_parts: list[str] = []
    for chunk in _chunks(summary)[:3]:
        translated = _translate_with_mymemory(chunk) or _translate_with_google_web(chunk)
        translated_parts.append(translated or chunk)

    translated_summary = "\n\n".join(translated_parts).strip()
    return f"""### 한 줄 핵심 진단
KDI 월간 경제동향의 최신 공식 진단을 한국어로 정리했습니다.

### 공식 보고서 핵심 내용
{translated_summary}

### 유의할 점
이 브리핑은 KDI 공식 보고서 발췌문을 번역·정리한 정보이며, 특정 투자 판단이나 매매를 권유하지 않습니다."""


def _gemini_korean_brief(title: str, published_date: str, summary: str) -> str:
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        return _fallback_korean_brief(title, published_date, summary)

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
        return text if _has_korean(text) else _fallback_korean_brief(
            title, published_date, summary
        )
    except Exception as exc:
        print(f"⚠️ 정부 보고서 Gemini 요약 실패: {type(exc).__name__}")
        return _fallback_korean_brief(title, published_date, summary)


def fetch_latest_kdi_report() -> dict[str, str]:
    """KDI 공식 월간 경제동향 페이지에서 최신 제목·발행일·요약을 추출합니다."""
    response = requests.get(KDI_MONTHLY_TRENDS_URL, headers=REQUEST_HEADERS, timeout=30)
    response.raise_for_status()
    soup = BeautifulSoup(response.text, "html.parser")
    text = soup.get_text("\n", strip=True)

    title_match = re.search(r"KDI Monthly Economic Trends\s+\d{4}\.\s*\d{1,2}", text)
    title = title_match.group(0) if title_match else "KDI Monthly Economic Trends"

    date_match = re.search(
        r"(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}",
        text,
    )
    published_date = date_match.group(0) if date_match else datetime.now().strftime("%Y-%m-%d")

    summary_match = re.search(r"Summary\s+open\s+(.*?)\s+Contents\s+open", text, flags=re.DOTALL)
    raw_summary = summary_match.group(1) if summary_match else text[:2500]
    summary = re.sub(r"\s+", " ", raw_summary).strip()[:3000]
    if not summary:
        raise ValueError("KDI 보고서 요약을 추출하지 못했습니다.")

    return {"title": title, "published_date": published_date, "summary": summary}


def _build_content(report: dict[str, str]) -> str:
    brief = _gemini_korean_brief(report["title"], report["published_date"], report["summary"])
    return f"""# KDI 월간 경제동향

**발행일:** {report['published_date']}

## 핵심 경제 브리핑

{brief}

---

원문: [KDI Monthly Economic Trends]({KDI_MONTHLY_TRENDS_URL})
"""


def refresh_government_reports() -> dict[str, Any]:
    """최신 KDI 월간 경제동향을 한국어 브리핑으로 중복 없이 저장·갱신합니다."""
    report = fetch_latest_kdi_report()
    display_title = _korean_display_title(report["title"])
    content = _build_content(report)

    existing = (
        supabase.table("gov_stats")
        .select("id,title,content")
        .ilike("title", "%KDI%")
        .limit(20)
        .execute()
    )
    same_report = next(
        (
            item
            for item in (existing.data or [])
            if report["title"].split()[-1].replace(" ", "")
            in str(item.get("title", "")).replace(" ", "")
        ),
        None,
    )
    if same_report:
        needs_update = _needs_korean_brief(str(same_report.get("content", "")))
        needs_title = same_report.get("title") != display_title
        if needs_update or needs_title:
            supabase.table("gov_stats").update(
                {"title": display_title, "content": content}
            ).eq("id", same_report["id"]).execute()
            return {"status": "translated", "title": display_title}
        return {"status": "up_to_date", "title": display_title}

    response = supabase.table("gov_stats").insert(
        {"title": display_title, "content": content}
    ).execute()
    return {"status": "created", "title": display_title, "data": response.data}


def refresh_existing_korean_gov_reports(limit: int = 10) -> int:
    """기존 영문 KDI 카드도 자동으로 최신 한국어 브리핑으로 교체합니다."""
    try:
        result = (
            supabase.table("gov_stats")
            .select("id,title,content")
            .order("id", desc=True)
            .limit(limit)
            .execute()
        )
        updated = 0
        for item in result.data or []:
            content = str(item.get("content", ""))
            title = str(item.get("title", ""))
            if "KDI" not in title or not _needs_korean_brief(content):
                continue
            english_body = re.sub(r"^#.*?\n", "", content, flags=re.DOTALL).strip()[:2800]
            report = {
                "title": title,
                "published_date": "공식 보고서 기준",
                "summary": english_body,
            }
            supabase.table("gov_stats").update(
                {
                    "title": re.sub(r"^\[KDI.*?\]", "[KDI 경제 정밀분석]", title)
                    if _has_korean(title)
                    else "[KDI 경제 정밀분석] KDI 월간 경제동향",
                    "content": _build_content(report),
                }
            ).eq("id", item["id"]).execute()
            updated += 1
        return updated
    except Exception as exc:
        print(f"⚠️ 기존 정부 보고서 한국어 갱신 실패: {type(exc).__name__}")
        return 0
