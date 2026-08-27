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


class PasswordResetEmailRequest(BaseModel):
    email: EmailStr



@router.post("/register")
def register(req: RegisterRequest):
    user_data = auth_service.register_user(req.email, req.password, req.nickname)
    return {"message": "회원가입 성공!", "user_id": user_data["id"]}

@router.post("/request-password-reset")
def request_password_reset(req: PasswordResetEmailRequest):
    """계정 존재 여부를 노출하지 않는 비밀번호 재설정 메일 요청입니다."""
    auth_service.request_password_reset(req.email)
    return {
        "message": "등록된 계정이라면 비밀번호 재설정 안내를 이메일로 보냈습니다. 메일함과 스팸함을 확인해 주세요."
    }


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