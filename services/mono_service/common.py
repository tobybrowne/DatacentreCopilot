import asyncio
import os

from fastapi import Header, HTTPException
from supabase import Client, ClientOptions, create_client


def get_supabase() -> Client:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_KEY")
    if not url or not key:
        raise HTTPException(500, "SUPABASE_URL and SUPABASE_KEY must be set")
    return create_client(url, key, options=ClientOptions(storage_client_timeout=120))


async def verify_token(token: str) -> bool:
    if not token:
        return False
    try:
        sb = get_supabase()
        loop = asyncio.get_event_loop()
        response = await loop.run_in_executor(None, sb.auth.get_user, token)
        return response.user is not None
    except Exception:
        return False


async def require_auth(authorization: str = Header(default="")) -> None:
    token = authorization.removeprefix("Bearer ").strip()
    if not await verify_token(token):
        raise HTTPException(401, "Unauthorized")


def require_webhook_auth(authorization: str = Header(default="")) -> None:
    secret = os.environ.get("WEBHOOK_SECRET")
    if not secret:
        raise HTTPException(500, "WEBHOOK_SECRET not configured")
    token = authorization.removeprefix("Bearer ").strip()
    if token != secret:
        raise HTTPException(401, "Unauthorized")
