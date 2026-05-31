from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import Optional
from app.database import supabase
from app.core.security import decode_access_token
import httpx
import os
import base64
from dotenv import load_dotenv

load_dotenv()

router = APIRouter(prefix="/payments", tags=["결제"])

TOSS_SECRET_KEY = os.getenv("TOSS_SECRET_KEY")
TOSS_API_URL = "https://api.tosspayments.com/v1/payments/confirm"

def get_current_user(authorization: str = None):
    if not authorization:
        return None
    try:
        auth_str = authorization.strip()
        if auth_str.lower().startswith("bearer "):
            token = auth_str[7:]
        else:
            token = auth_str
        return decode_access_token(token.strip())
    except:
        return None

class PaymentConfirm(BaseModel):
    payment_key: str
    order_id: str
    amount: int
    post_id: Optional[str] = None
    payment_type: str = "single_post"  # single_post or subscription

class SubscriptionCreate(BaseModel):
    plan: str  # monthly or yearly

@router.post("/confirm")
async def confirm_payment(
    body: PaymentConfirm,
    authorization: Optional[str] = Header(default=None)
):
    # 원래대로 정상적인 로그인 토큰 검증 로직으로 복구했습니다.
    user = get_current_user(authorization)
    if not user:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다.")

    # 토스페이먼츠 결제 승인 요청
    secret_key = TOSS_SECRET_KEY + ":"
    encoded_key = base64.b64encode(secret_key.encode()).decode()

    async with httpx.AsyncClient() as client:
        response = await client.post(
            TOSS_API_URL,
            headers={
                "Authorization": f"Basic {encoded_key}",
                "Content-Type": "application/json"
            },
            json={
                "paymentKey": body.payment_key,
                "orderId": body.order_id,
                "amount": body.amount
            }
        )

    if response.status_code != 200:
        raise HTTPException(status_code=400, detail=f"결제 승인 실패: {response.text}")

    toss_data = response.json()

    # 결제 이력 DB 저장
    payment_record = supabase.table("payments").insert({
        "user_id": user.get("sub"),
        "type": body.payment_type,
        "status": "success",
        "amount": body.amount,
        "currency": "KRW",
        "pg_provider": "toss",
        "pg_transaction_id": body.payment_key,
        "post_id": body.post_id
    }).execute()

    payment_id = payment_record.data[0]["id"]

    # 단건 구매인 경우 post_purchases 에 저장
    if body.payment_type == "single_post" and body.post_id:
        supabase.table("post_purchases").insert({
            "user_id": user.get("sub"),
            "post_id": body.post_id,
            "payment_id": payment_id
        }).execute()

    # 구독 결제인 경우 subscriptions 에 저장
    if body.payment_type == "subscription":
        from datetime import datetime, timedelta
        expires_at = datetime.utcnow() + timedelta(days=30)
        supabase.table("subscriptions").insert({
            "user_id": user.get("sub"),
            "plan": "monthly",
            "status": "active",
            "expires_at": expires_at.isoformat()
        }).execute()
        # 유저 role을 premium으로 업데이트
        supabase.table("users").update({"role": "premium"})\
            .eq("id", user.get("sub")).execute()

    return {
        "message": "결제 완료!",
        "payment_id": payment_id,
        "toss_data": toss_data
    }

@router.get("/my")
def get_my_payments(authorization: Optional[str] = Header(default=None)):
    # 원래대로 정상적인 로그인 토큰 검증 로직으로 복구했습니다.
    user = get_current_user(authorization)
    if not user:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다.")

    result = supabase.table("payments")\
        .select("*")\
        .eq("user_id", user.get("sub"))\
        .order("created_at", desc=True)\
        .execute()

    return {"payments": result.data}