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


def create_access_token(user_id: str, tenant_id: str) -> str:
    expires = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_expire_minutes)
    return jwt.encode({"sub": user_id, "tid": tenant_id, "exp": expires}, settings.jwt_secret, algorithm=_ALGORITHM)


def decode_access_token(token: str):
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[_ALGORITHM])
    except JWTError:
        return None
