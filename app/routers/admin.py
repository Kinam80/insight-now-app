from fastapi import APIRouter

router = APIRouter()

# main.py에서 prefix="/api"를 붙였으므로, 
# 실제 호출 주소는 /api/admin/users 가 됩니다.
@router.get("/users") 
def get_users():
    # 여기에 사용자 목록 로직
    return {"users": []}

@router.get("/stats")
def get_stats():
    # 여기에 대시보드 통계 로직
    return {"total_users": 0, "total_revenue": 0}

@router.get("/")
def read_admin():
    return {"message": "Admin area is working!"}