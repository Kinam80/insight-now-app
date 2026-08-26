from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import Optional
from app.database import supabase
from app.core.security import decode_access_token
from datetime import datetime

router = APIRouter(prefix="/posts", tags=["유료 분석 글"])

class PostCreate(BaseModel):
    title: str
    preview: str
    content: str
    category: str  # 👈 여기를 추가하세요!
    access_type: str = "premium_only"
    single_price: Optional[int] = None
    tags: Optional[list] = []
    thumbnail_url: Optional[str] = None

def get_current_user(authorization: str = Header(default=None)):
    print(f"DEBUG: 들어온 헤더값: {authorization}") # 로그에서 이 값을 확인!
    if not authorization:
        return None
    
    # "Bearer " 가 포함된 경우를 명확하게 처리
    token = authorization.replace("Bearer ", "").strip()
    
    try:
        payload = decode_access_token(token)
        print(f"✅ 토큰 디코딩 성공 결과: {payload}")
        return payload
    except Exception as e:
        print(f"❌ 토큰 디코딩 실패: {e}")
        return None

@router.get("/")
def get_posts(authorization: Optional[str] = Header(default=None)):
    user = get_current_user(authorization)

    # 신규/레거시 데이터 모두 최신순으로 보이도록 생성일 우선 정렬합니다.
    # 오래된 테이블에 created_at이 없는 경우에는 기존 published_at 정렬로 안전하게 폴백합니다.
    base_fields = "id, title, preview, category, access_type, single_price, tags, thumbnail_url, view_count, published_at"
    try:
        result = supabase.table("analysis_posts")\
            .select(f"{base_fields}, created_at")\
            .eq("is_published", True)\
            .order("created_at", desc=True)\
            .execute()
    except Exception:
        result = supabase.table("analysis_posts")\
            .select(base_fields)\
            .eq("is_published", True)\
            .order("published_at", desc=True)\
            .execute()

    posts = result.data or []

    for post in posts:
        post["is_purchased"] = False
        if user:
            if user.get("role") == "premium" and post["access_type"] == "premium_only":
                post["is_purchased"] = True
            elif post["access_type"] == "free":
                post["is_purchased"] = True
            elif post["access_type"] == "paid_single":
                purchase = supabase.table("post_purchases")\
                    .select("id")\
                    .eq("user_id", user.get("sub"))\
                    .eq("post_id", post["id"])\
                    .execute()
                post["is_purchased"] = bool(purchase.data)

        return {"posts": posts}


@router.get("/feed/latest")
def get_latest_report_feed():
    """모바일 홈 전용의 가벼운 공개 일일 레포트 피드입니다."""
    fields = "id, title, preview, category, published_at"
    try:
        result = (
            supabase.table("analysis_posts")
            .select(f"{fields}, created_at")
            .eq("is_published", True)
            .order("created_at", desc=True)
            .limit(60)
            .execute()
        )
    except Exception:
        result = (
            supabase.table("analysis_posts")
            .select(fields)
            .eq("is_published", True)
            .order("published_at", desc=True)
            .limit(60)
            .execute()
        )
    return {"reports": result.data or []}


@router.get("/{post_id}")

def get_post_detail(post_id: str, authorization: Optional[str] = Header(default=None)):
    user = get_current_user(authorization)

    result = supabase.table("analysis_posts")\
        .select("*")\
        .eq("id", post_id)\
        .eq("is_published", True)\
        .execute()

    if not result.data:
        raise HTTPException(status_code=404, detail="글을 찾을 수 없습니다.")

    post = result.data[0]

    supabase.table("analysis_posts")\
        .update({"view_count": post["view_count"] + 1})\
        .eq("id", post_id)\
        .execute()

    if post["access_type"] == "free":
        return post

    if not user:
        return {
            "id": post["id"],
            "title": post["title"],
            "preview": post["preview"],
            "access_type": post["access_type"],
            "single_price": post["single_price"],
            "is_locked": True
        }

    if post["access_type"] == "premium_only":
        if user.get("role") in ["premium", "admin"]:
            return post
        return {
            "id": post["id"],
            "title": post["title"],
            "preview": post["preview"],
            "access_type": post["access_type"],
            "is_locked": True,
            "message": "구독자 전용 콘텐츠입니다."
        }

    if post["access_type"] == "paid_single":
        if user.get("role") == "admin":
            return post
        purchase = supabase.table("post_purchases")\
            .select("id")\
            .eq("user_id", user.get("sub"))\
            .eq("post_id", post_id)\
            .execute()
        if purchase.data:
            return post
        return {
            "id": post["id"],
            "title": post["title"],
            "preview": post["preview"],
            "access_type": post["access_type"],
            "single_price": post["single_price"],
            "is_locked": True,
            "message": "단건 결제가 필요한 콘텐츠입니다."
        }

@router.post("/admin/create")
def create_post(post: PostCreate, authorization: Optional[str] = Header(default=None)):
    user = get_current_user(authorization)
    print(f"👤 현재 유저: {user}")

    if not user or user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="관리자만 글을 작성할 수 있습니다.")

    result = supabase.table("analysis_posts").insert({
        "author_id": user.get("sub"),
        "title": post.title,
        "preview": post.preview,
        "content": post.content,
        "category": post.category,  # 👈 여기를 추가하세요! (쉼표 잊지 마세요)
        "access_type": post.access_type,
        "single_price": post.single_price,
        "tags": post.tags,
        "thumbnail_url": post.thumbnail_url,
        "is_published": True,
        "published_at": datetime.utcnow().isoformat()
    }).execute()

    return {"message": "글 발행 완료!", "post": result.data[0]}

@router.delete("/{post_id}")
def delete_post(post_id: str, authorization: Optional[str] = Header(default=None)):
    user = get_current_user(authorization)
    
    # 관리자 권한 확인
    if not user or user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="삭제 권한이 없습니다.")

    # Supabase에서 데이터 삭제
    result = supabase.table("analysis_posts")\
        .delete()\
        .eq("id", post_id)\
        .execute()
    
    # 결과 확인
    if not result.data:
        raise HTTPException(status_code=404, detail="삭제할 글을 찾을 수 없습니다.")
        
    return {"message": "글이 성공적으로 삭제되었습니다."}