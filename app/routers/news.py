from fastapi import APIRouter, Query, HTTPException
from app.database import supabase_admin as supabase

from datetime import datetime, timedelta
from dateutil import parser

router = APIRouter(prefix="/news", tags=["뉴스"])

# 💎 영문 코드를 고급스러운 프리미엄 브랜드 라벨로 치환하는 마스터 맵
CATEGORY_LABELS = {
    "us_market": "🇺🇸 글로벌 매크로·뉴욕증시",
    "kr_market": "🇰🇷 국내 핵심 마켓 센티먼트",
    "fx_rate": "💱 외환·매크로 외환 동향",
    "bond_rate": "📊 채권·금리 시황 인사이틀"
}

def format_time_ago(iso_string: str) -> str:
    """Supabase의 날짜 데이터를 분석하여 실시간 타임스탬프로 변환"""
    if not iso_string: return "실시간 브리핑"
    try:
        dt = parser.parse(iso_string)
        if dt.tzinfo is not None: dt = dt.replace(tzinfo=None)
        
        now = datetime.now()
        diff = now - dt
        
        if diff.days > 0: return f"{diff.days}일 전"
        hours = diff.seconds // 3600
        if hours > 0: return f"{hours}시간 전"
        minutes = (diff.seconds % 3600) // 60
        if minutes > 0: return f"{minutes}분 전"
        return "방금 전"
    except Exception as e:
        print(f"❌ [시간 파싱 오류]: {e}")
        return "방금 전"

def enhance_news_data(item: dict) -> dict:
    """일반 마켓 뉴스를 최고급 유료 멤버십 투자 인텔리전스 데이터로 가공"""
    cat_raw = item.get("category", "")
    title = item.get("title", "")
    if "]" in title:
        title = title.split("]", 1)[-1].strip()
        
    title_hash = len(title)
    importance_stars = (title_hash % 3) + 3
    insight_score = 85 + (title_hash % 15)
    
    return {
        "id": item.get("id"),
        "category_raw": cat_raw,
        "category_display": CATEGORY_LABELS.get(cat_raw, "🎯 프리미엄 인사이틀"),
        "title": f"[{CATEGORY_LABELS.get(cat_raw, '이슈').split(' ')[-1]}] {title}",
        "summary": item.get("summary", "AI 심층 본문 분석을 진행하고 있습니다."),
        "content": item.get("content", ""),
        "published_at": item.get("created_at"),
        "time_ago": format_time_ago(item.get("created_at", "")),
        "source_url": item.get("source_url"),
        "premium_metrics": {
            "importance": "🔥" * importance_stars,
            "insight_score": f"{insight_score}%",
            "badge": "PREMIUM" if insight_score > 92 else "HOT"
        }
    }

@router.get("/")
def get_news(
    category: str = Query(default=None, description="카테고리 필터"),
    limit: int = Query(default=20, description="가져올 뉴스 수"),
    page: int = Query(default=1, description="페이지 번호")
):
    try:
        offset = (page - 1) * limit
        query = supabase.table("ai_news").select("*").order("created_at", desc=True)
        if category: query = query.eq("category", category)
        result = query.range(offset, offset + limit - 1).execute()
        enhanced_list = [enhance_news_data(item) for item in result.data]
        return {
            "status": "success",
            "page": page,
            "limit": limit,
            "count": len(enhanced_list),
            "news": enhanced_list
        }
    except Exception as e:
        print(f"❌ 뉴스 조회 오류: {e}")
        raise HTTPException(status_code=500, detail="데이터베이스 연결 중 오류가 발생했습니다.")

@router.get("/latest")
def get_latest_news():
    try:
        categories = ["us_market", "kr_market", "fx_rate", "bond_rate"]
        result = {}
        for cat in categories:
            data = supabase.table("ai_news").select("*").eq("category", cat).order("created_at", desc=True).limit(3).execute()
            result[cat] = [enhance_news_data(item) for item in data.data]
        return result
    except Exception as e:
        print(f"❌ 최신 뉴스 조회 오류: {e}")
        raise HTTPException(status_code=500, detail="최신 뉴스 정보를 불러오는 데 실패했습니다.")

@router.get("/{news_id}")
def get_news_detail(news_id: str):
    try:
        result = supabase.table("ai_news").select("*").eq("id", news_id).execute()
        if not result.data:
            raise HTTPException(status_code=404, detail="해당 보고서를 찾을 수 없습니다.")
        return enhance_news_data(result.data[0])
    except Exception as e:
        if isinstance(e, HTTPException): raise e
        raise HTTPException(status_code=500, detail="상세 정보 조회 오류")