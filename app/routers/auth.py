from fastapi import APIRouter
from pydantic import BaseModel, EmailStr
from app.services import auth_service # 서비스 레이어 호출

router = APIRouter(prefix="/auth", tags=["인증"])

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    nickname: str

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

@router.post("/register")
def register(req: RegisterRequest):
    user_data = auth_service.register_user(req.email, req.password, req.nickname)
    return {"message": "회원가입 성공!", "user_id": user_data["id"]}

@router.post("/login")
def login(req: LoginRequest):
    token, user = auth_service.authenticate_user(req.email, req.password)
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": user["id"],
            "email": user["email"],
            "nickname": user["nickname"],
            "role": user["role"]
        }
    }