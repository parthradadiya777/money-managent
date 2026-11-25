from pydantic import BaseModel, EmailStr, Field
from typing import Any


class RegisterIn(BaseModel):
    business_name: str = Field(min_length=2, max_length=180)
    email: EmailStr
    password: str = Field(min_length=12, max_length=128)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class RecordIn(BaseModel):
    record_id: str = Field(min_length=1, max_length=160)
    module: str = Field(min_length=1, max_length=80)
    payload: dict[str, Any]


class RecordBatchIn(BaseModel):
    records: list[RecordIn] = Field(max_length=1000)
