from fastapi import HTTPException

from app.core.security import create_access_token, hash_password, verify_password
from app.database import supabase, supabase_admin


def register_user(email, password, nickname):
    """Supabase Auth와 사용자 프로필 테이블을 함께 생성합니다."""
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
    result = supabase_admin.table("users").insert({
        "id": user_id,
        "email": email,
        "password_hash": hashed,
        "nickname": nickname,
        "role": "free",
    }).execute()
    return result.data[0]


def authenticate_user(email, password):
    """Supabase Auth와 기존 프로필 해시를 모두 호환해 로그인합니다."""
    result = supabase_admin.table("users").select("*").eq("email", email).limit(1).execute()
    user = result.data[0] if result.data else None

    legacy_password_valid = bool(
        user
        and user.get("password_hash")
        and verify_password(password, user["password_hash"])
    )

    auth_password_valid = False
    auth_user_id = None
    try:
        auth_response = supabase.auth.sign_in_with_password({"email": email, "password": password})
        if auth_response.user is not None:
            auth_password_valid = True
            auth_user_id = auth_response.user.id
    except Exception:
        # 기존 앱에서 관리하던 해시가 유효하면 이전 로그인 방식도 계속 지원합니다.
        pass

    if not legacy_password_valid and not auth_password_valid:
        raise HTTPException(status_code=401, detail="이메일 또는 비밀번호가 틀렸습니다.")

    if user is None:
        if auth_user_id is None:
            raise HTTPException(status_code=401, detail="사용자 프로필을 찾을 수 없습니다.")
        created = supabase_admin.table("users").insert({
            "id": auth_user_id,
            "email": email,
            "password_hash": hash_password(password),
            "nickname": email.split("@")[0],
            "role": "free",
        }).execute()
        user = created.data[0]
    elif auth_password_valid and not legacy_password_valid:
        # Supabase Auth의 비밀번호가 맞는 경우 프로필 해시를 동기화하여
        # 다음 로그인부터 두 저장소의 상태가 일치하도록 합니다.
        updated = supabase_admin.table("users").update({
            "password_hash": hash_password(password),
        }).eq("id", user["id"]).execute()
        if updated.data:
            user = updated.data[0]

    token = create_access_token({"sub": user["id"], "role": user.get("role", "free")})
    return token, user
