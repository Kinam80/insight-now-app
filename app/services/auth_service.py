from app.database import supabase
from app.core.security import hash_password, verify_password, create_access_token
from fastapi import HTTPException

def register_user(email, password, nickname):
    # 1. Supabase Auth에 사용자 생성 (인증 시스템 등록)
    try:
        auth_response = supabase.auth.sign_up({"email": email, "password": password})
        if auth_response.user is None:
            raise HTTPException(status_code=400, detail="인증 계정 생성 실패")
        
        user_id = auth_response.user.id # 여기서 생성된 UID를 가져옵니다.
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"가입 실패: {str(e)}")

    # 2. DB 테이블에 상세 정보 저장 (이제 uid를 연결합니다)
    hashed = hash_password(password)
    result = supabase.table("users").insert({
        "id": user_id,           # Auth에서 받은 UID와 DB를 연결!
        "email": email,
        "password_hash": hashed,
        "nickname": nickname,
        "role": "free"
    }).execute()
    
    return result.data[0]

def authenticate_user(email, password):
    # 유저 조회
    result = supabase.table("users").select("*").eq("email", email).execute()
    if not result.data:
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    user = result.data[0]

    # 비밀번호 확인
    if not verify_password(password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    # JWT 토큰 발급
    token = create_access_token({"sub": user["id"], "role": user["role"]})
    return token, user