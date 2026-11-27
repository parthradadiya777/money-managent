from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from pwdlib import PasswordHash
from .config import settings

_ALGORITHM = "HS256"
_password_hash = PasswordHash.recommended()


def hash_password(password: str) -> str:
    return _password_hash.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return _password_hash.verify(password, password_hash)


def create_access_token(user_id: str, tenant_id: str, *, expires_minutes: int | None = None, impersonating: bool = False) -> str:
    duration = expires_minutes if expires_minutes is not None else settings.jwt_expire_minutes
    now = datetime.now(timezone.utc)
    expires = now + timedelta(minutes=duration)
    # Keep sub-second precision so a password reset invalidates older tokens
    # without also invalidating a new login created in the same second.
    claims = {"sub": user_id, "tid": tenant_id, "iat": now.timestamp(), "exp": expires}
    if impersonating:
        claims["imp"] = True
    return jwt.encode(claims, settings.jwt_secret, algorithm=_ALGORITHM)


def decode_access_token(token: str):
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[_ALGORITHM])
    except JWTError:
        return None
