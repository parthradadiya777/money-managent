from uuid import UUID
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, delete
from sqlalchemy.orm import Session
from .config import settings
from .database import Base, engine, get_db
from .models import Tenant, User, BusinessRecord, AuditLog
from .schemas import RegisterIn, LoginIn, RecordIn, RecordBatchIn
from .security import hash_password, verify_password, create_access_token, decode_access_token

Base.metadata.create_all(bind=engine)
app = FastAPI(title="Digitechified Business Manager API", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=[x.strip() for x in settings.cors_origins.split(",")], allow_credentials=False, allow_methods=["*"], allow_headers=["*"])


def current_user(authorization: str | None = Header(default=None), db: Session = Depends(get_db)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required")
    claims = decode_access_token(authorization[7:])
    if not claims:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    try:
        user_id, tenant_id = UUID(claims["sub"]), UUID(claims["tid"])
    except (KeyError, ValueError):
        raise HTTPException(status_code=401, detail="Invalid token")
    user = db.scalar(select(User).where(User.id == user_id, User.tenant_id == tenant_id))
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user


@app.get("/health")
def health():
    return {"status": "ok", "service": "digitechified-business-manager-api"}


@app.post("/api/auth/register")
def register(data: RegisterIn, db: Session = Depends(get_db)):
    if db.scalar(select(User).where(User.email == data.email.lower())):
        raise HTTPException(status_code=409, detail="Email already registered")
    tenant = Tenant(name=data.business_name.strip())
    db.add(tenant)
    db.flush()
    user = User(tenant_id=tenant.id, email=data.email.lower(), password_hash=hash_password(data.password), role="owner")
    db.add(user)
    db.commit()
    return {"access_token": create_access_token(str(user.id), str(tenant.id)), "token_type": "bearer", "business_name": tenant.name, "role": user.role}


@app.post("/api/auth/login")
def login(data: LoginIn, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == data.email.lower()))
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Email or password is incorrect")
    tenant = db.get(Tenant, user.tenant_id)
    return {"access_token": create_access_token(str(user.id), str(user.tenant_id)), "token_type": "bearer", "business_name": tenant.name if tenant else "", "role": user.role}


@app.get("/api/auth/me")
def me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    tenant = db.get(Tenant, user.tenant_id)
    return {"email": user.email, "role": user.role, "business_name": tenant.name if tenant else ""}


@app.get("/api/records")
def list_records(module: str | None = None, user: User = Depends(current_user), db: Session = Depends(get_db)):
    query = select(BusinessRecord).where(BusinessRecord.tenant_id == user.tenant_id)
    if module:
        query = query.where(BusinessRecord.module == module)
    items = db.scalars(query.order_by(BusinessRecord.updated_at.desc()).limit(10000)).all()
    return {"records": [{"record_id": x.record_id, "module": x.module, "payload": x.payload, "updated_at": x.updated_at.isoformat()} for x in items]}


@app.put("/api/records")
def upsert_record(data: RecordIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    item = db.scalar(select(BusinessRecord).where(BusinessRecord.tenant_id == user.tenant_id, BusinessRecord.record_id == data.record_id))
    action = "update" if item else "create"
    if item:
        item.module, item.payload = data.module, data.payload
    else:
        item = BusinessRecord(tenant_id=user.tenant_id, record_id=data.record_id, module=data.module, payload=data.payload)
        db.add(item)
    db.add(AuditLog(tenant_id=user.tenant_id, user_id=user.id, action=action, module=data.module, record_id=data.record_id))
    db.commit()
    return {"ok": True, "record_id": data.record_id}


@app.put("/api/records/batch")
def batch_upsert(data: RecordBatchIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    saved = 0
    for record in data.records:
        item = db.scalar(select(BusinessRecord).where(BusinessRecord.tenant_id == user.tenant_id, BusinessRecord.record_id == record.record_id))
        action = "update" if item else "create"
        if item:
            item.module, item.payload = record.module, record.payload
        else:
            db.add(BusinessRecord(tenant_id=user.tenant_id, record_id=record.record_id, module=record.module, payload=record.payload))
        db.add(AuditLog(tenant_id=user.tenant_id, user_id=user.id, action=action, module=record.module, record_id=record.record_id))
        saved += 1
    db.commit()
    return {"ok": True, "saved": saved}


@app.delete("/api/records/{record_id}")
def remove_record(record_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    item = db.scalar(select(BusinessRecord).where(BusinessRecord.tenant_id == user.tenant_id, BusinessRecord.record_id == record_id))
    if not item:
        raise HTTPException(status_code=404, detail="Record not found")
    db.add(AuditLog(tenant_id=user.tenant_id, user_id=user.id, action="delete", module=item.module, record_id=item.record_id))
    db.delete(item)
    db.commit()
    return {"ok": True}
