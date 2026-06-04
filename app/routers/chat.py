from fastapi import APIRouter
from app.database import supabase

router = APIRouter(prefix="/chat", tags=["Chat"])

# 메시지 저장
@router.post("/messages")
def send_message(data: dict):
    return supabase.table("chat_messages").insert({
        "user_email": data.get("email"),
        "content": data.get("content")
    }).execute()

# 메시지 불러오기 (화면 이동해도 유지됨)
@router.get("/messages")
def get_messages():
    # 생성 시간 순으로 데이터 가져오기
    return supabase.table("chat_messages").select("*").order("created_at", asc=True).execute().data