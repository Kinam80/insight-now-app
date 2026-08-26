from fastapi import HTTPException
from supabase import create_client

from app.core.security import create_access_token, hash_password, verify_password
from app.database import SUPABASE_KEY, SUPABASE_URL, supabase


def register_user(email, password, nickname):
    """Supabase Auth와 public.users 프로필을 함께 생성합니다."""
    try:
        auth_response = supabase.auth.sign_up({"email": email, "password": password})
        if auth_response.user is None:
            raise HTTPException(status_code=400, detail="인증 계정 생성 실패")
        user_id = auth_response.user.id
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"가입 실패: {str(exc)}") from exc

    hashed = hash_password(password)
    result = supabase.table("users").insert({
        "id": user_id,
        "email": email,
        "password_hash": hashed,
        "nickname": nickname,
        "role": "free",
    }).execute()
    return result.data[0]


def authenticate_user(email, password):
    """기존 프로필 로그인과 Supabase Auth를 모두 지원합니다."""
    result = supabase.table("users").select("*").eq("email", email).execute()
    if not result.data:
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    user = result.data[0]
    profile_password_valid = bool(
        user.get("password_hash") and verify_password(password, user["password_hash"])
    )

    if not profile_password_valid:
        # 과거 데이터처럼 public.users 해시와 Auth 비밀번호가 분리된 경우에도
        # 실제 Supabase Auth 비밀번호가 유효하면 같은 프로필·권한으로 로그인합니다.
        try:
            auth_client = create_client(SUPABASE_URL, SUPABASE_KEY)
            auth_response = auth_client.auth.sign_in_with_password({
                "email": email,
                "password": password,
            })
            auth_password_valid = auth_response.user is not None
        except Exception:
            auth_password_valid = False

        if not auth_password_valid:
            raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    token = create_access_token({"sub": user["id"], "role": user.get("role", "free")})
    return token, user
