from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, EmailStr
from app.database import supabase
from app.core.security import hash_password, verify_password, create_access_token

router = APIRouter(prefix="/auth", tags=["인증"])

# 요청 데이터 형식 정의
class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    nickname: str

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

# 회원가입
@router.post("/register")
def register(req: RegisterRequest):
    # 이메일 중복 확인
    existing = supabase.table("users").select("id").eq("email", req.email).execute()
    if existing.data:
        raise HTTPException(status_code=400, detail="이미 사용 중인 이메일입니다.")

    # 비밀번호 해시화 후 저장
    hashed = hash_password(req.password)
    result = supabase.table("users").insert({
        "email": req.email,
        "password_hash": hashed,
        "nickname": req.nickname,
        "role": "free"
    }).execute()

    return {"message": "회원가입 성공!", "user_id": result.data[0]["id"]}

# 로그인
@router.post("/login")
def login(req: LoginRequest):
    # 유저 조회
    result = supabase.table("users").select("*").eq("email", req.email).execute()
    if not result.data:
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    user = result.data[0]

    # 비밀번호 확인
    if not verify_password(req.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    # JWT 토큰 발급
    token = create_access_token({"sub": user["id"], "role": user["role"]})

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