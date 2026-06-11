from datetime import datetime, timedelta
from jose import JWTError, jwt
import bcrypt
import os

# 환경변수 로드 (Render 환경변수 우선 적용)
JWT_SECRET = os.getenv("JWT_SECRET")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

# 방어적 체크: 서버에 SECRET이 설정 안 되어 있으면 경고 출력
if not JWT_SECRET:
    print("❌ 경고: 환경변수 JWT_SECRET이 설정되지 않았습니다!")

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))

def create_access_token(data: dict) -> str:
    if not JWT_SECRET:
        raise ValueError("JWT_SECRET이 설정되지 않았습니다.")
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, JWT_SECRET, algorithm=ALGORITHM)

def decode_access_token(token: str) -> dict:
    if not JWT_SECRET:
        print("❌ 에러: JWT_SECRET이 없습니다.")
        return None
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
        return payload
    except JWTError as e:
        print(f"❌ 토큰 디코딩 상세 에러: {e}")
        return None