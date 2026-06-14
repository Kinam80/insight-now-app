from fastapi import APIRouter


router = APIRouter(prefix="/admin") # 여기서 /admin을 추가해야 합니다!

@router.get("/users") # main.py(/api) + router(/admin) + 여기(/users) = /api/admin/users
def get_users():
    return {"status": "success", "data": []}

@router.get("/stats")
def get_stats():
    # 여기에 대시보드 통계 로직
    return {"total_users": 0, "total_revenue": 0}

@router.get("/")
def read_admin():
    return {"message": "Admin area is working!"}