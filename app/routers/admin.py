from fastapi import APIRouter, Header, HTTPException, Depends
from typing import Optional

router = APIRouter(prefix="/admin") # 여기서 prefix는 이미 /admin

def verify_token(authorization: Optional[str] = Header(None)):
    print(f"DEBUG: 서버가 실제로 읽은 헤더값: {authorization}")
    if not authorization:
        raise HTTPException(status_code=401, detail="인증 헤더가 누락되었습니다.")
    return authorization

@router.get("/users")
def get_users(token: str = Depends(verify_token)):
    return {"status": "success", "data": []}

@router.get("/stats")
async def get_admin_stats(token: str = Depends(verify_token)):
    return {"total_users": 100, "total_revenue": 50000, "total_posts": 10}

@router.get("/")
def read_admin(token: str = Depends(verify_token)):
    return {"message": "Admin area is working!"}