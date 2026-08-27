from datetime import datetime

from dateutil import parser
from fastapi import APIRouter, HTTPException, Query

from app.database import supabase_admin as supabase

router = APIRouter(prefix="/news", tags=["뉴스"])

CATEGORY_LABELS = {
    "us_market": "🇺🇸 글로벌 매크로·뉴욕증시",
    "kr_market": "🇰🇷 국내 핵심 마켓 흐름",
    "fx_rate": "💱 외환·매크로 동향",
    "bond_rate": "📊 채권·금리 시장 인사이트",
}
# 과거 Yahoo 검색 결과에 섞인 생활·홍보성 기사도 새 수집 품질 기준이 누적될 때까지 공개 화면에서 제외합니다.
NON_MARKET_TITLE_TERMS = (
    "월식",
    "블러드문",
    "팔레스타인",
    "표창",
    "양식 8.",
    "양식-8.",
    "form 8.",
    "form-8.",
    "지역 사회",
    "community impact",
    "congratulates",
)


def _is_displayable_market_news(item: dict) -> bool:
    title = str(item.get("title") or "").lower()
    return bool(title) and not any(term.lower() in title for term in NON_MARKET_TITLE_TERMS)


def format_time_ago(iso_string: str) -> str:
    """Supabase 날짜를 사용자 화면의 상대 시각으로 변환합니다."""
    if not iso_string:
        return "실시간 브리핑"
    try:
        dt = parser.parse(iso_string)
        if dt.tzinfo is not None:
            dt = dt.replace(tzinfo=None)
        diff = datetime.now() - dt
        if diff.days > 0:
            return f"{diff.days}일 전"
        hours = diff.seconds // 3600
        if hours > 0:
            return f"{hours}시간 전"
        minutes = (diff.seconds % 3600) // 60
        if minutes > 0:
            return f"{minutes}분 전"
        return "방금 전"
    except Exception:
        return "방금 전"


def enhance_news_data(item: dict) -> dict:
    """원본 출처가 확인되는 한국어 금융 뉴스를 화면용 형태로 정리합니다."""
    category = item.get("category", "")
    title = str(item.get("title") or "")
    if "]" in title:
        title = title.split("]", 1)[-1].strip()
    source_name = str(item.get("source_name") or "Yahoo Finance").strip()
    category_display = CATEGORY_LABELS.get(category, "🎯 금융 시장 인사이트")
    category_short = category_display.split(" ")[-1]

    return {
        "id": item.get("id"),
        "category_raw": category,
        "category_display": category_display,
        "title": f"[{category_short}] {title}",
        "summary": item.get("summary", "한국어 요약을 준비하고 있습니다."),
        "content": item.get("content", ""),
        "published_at": item.get("created_at"),
        "time_ago": format_time_ago(item.get("created_at", "")),
        "source_url": item.get("source_url"),
        "premium_metrics": {
            "badge": source_name[:40],
            "insight_score": "원문 제공",
        },
    }


@router.get("/")
def get_news(
    category: str | None = Query(default=None, description="카테고리 필터"),
    limit: int = Query(default=20, ge=1, le=50, description="가져올 뉴스 수"),
    page: int = Query(default=1, ge=1, description="페이지 번호"),
):
    try:
        offset = (page - 1) * limit
        query = supabase.table("ai_news").select("*").order("created_at", desc=True)
        if category:
            query = query.eq("category", category)
        # 품질 제외어가 포함된 기존 행을 건너뛰기 위해 넉넉히 읽고 공개 개수만 반환합니다.
        result = query.range(offset, offset + (limit * 4) - 1).execute()
        visible_items = [
            item for item in (result.data or []) if _is_displayable_market_news(item)
        ]
        enhanced_list = [enhance_news_data(item) for item in visible_items[:limit]]
        return {
            "status": "success",
            "page": page,
            "limit": limit,
            "count": len(enhanced_list),
            "news": enhanced_list,
        }
    except Exception as exc:
        print(f"뉴스 조회 오류: {type(exc).__name__}")
        raise HTTPException(status_code=500, detail="뉴스 데이터를 불러오지 못했습니다.") from exc


@router.get("/latest")
def get_latest_news():
    try:
        categories = ["us_market", "kr_market", "fx_rate", "bond_rate"]
        result = {}
        for category in categories:
            data = (
                supabase.table("ai_news")
                .select("*")
                .eq("category", category)
                .order("created_at", desc=True)
                .limit(12)
                .execute()
            )
            result[category] = [
                enhance_news_data(item)
                for item in (data.data or [])
                if _is_displayable_market_news(item)
            ][:3]
        return result
    except Exception as exc:
        print(f"최신 뉴스 조회 오류: {type(exc).__name__}")
        raise HTTPException(status_code=500, detail="최신 뉴스 정보를 불러오지 못했습니다.") from exc


@router.get("/{news_id}")
def get_news_detail(news_id: str):
    try:
        result = supabase.table("ai_news").select("*").eq("id", news_id).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="해당 뉴스를 찾을 수 없습니다.")
        item = result.data[0]
        if not _is_displayable_market_news(item):
            raise HTTPException(status_code=404, detail="현재 표시하지 않는 뉴스입니다.")
        return enhance_news_data(item)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail="뉴스 상세 정보를 불러오지 못했습니다.") from exc
