from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import UUID, uuid4
from fastapi import Depends, FastAPI, Header, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select
from sqlalchemy.orm import Session
from .config import settings
from .database import Base, engine, get_db
from .models import Tenant, User, Partner, BusinessRecord, AuditLog, AdminAccessLog, UserSecurity, PartnerBackupDelivery
from .partner_backup import start_backup_scheduler, stop_backup_scheduler
from .schemas import RegisterIn, LoginIn, PartnerCreateIn, PartnerUpdateIn, PasswordResetIn, PasswordChangeIn, RecordIn, RecordBatchIn
from .security import hash_password, verify_password, create_access_token, decode_access_token

Base.metadata.create_all(bind=engine)
app = FastAPI(title="Digitechified Business Manager API", version="0.2.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[x.strip() for x in settings.cors_origins.split(",")],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@dataclass
class Principal:
    """Authenticated actor plus the tenant whose data this request may access."""
    id: UUID
    tenant_id: UUID
    role: str
    email: str
    impersonating: bool = False


def _partner_for_tenant(db: Session, tenant_id: UUID):
    return db.scalar(select(Partner).where(Partner.tenant_id == tenant_id))


def _write_admin_log(db: Session, admin_id: UUID, tenant_id: UUID, action: str, details: str = ""):
    db.add(AdminAccessLog(admin_user_id=admin_id, tenant_id=tenant_id, action=action, details=details[:2000]))


@app.on_event("startup")
def start_monthly_backup_scheduler():
    start_backup_scheduler()


@app.on_event("shutdown")
def stop_monthly_backup_scheduler():
    stop_backup_scheduler()


@app.on_event("startup")
def initialize_partner_workspace():
    """Provision metadata for legacy tenants and optionally bootstrap the owner admin."""
    db = next(get_db())
    try:
        tenants = db.scalars(select(Tenant)).all()
        admin_tenant_ids = set(db.scalars(select(User.tenant_id).where(User.role == "super_admin")).all())
        for tenant in tenants:
            if tenant.id in admin_tenant_ids or _partner_for_tenant(db, tenant.id):
                continue
            db.add(Partner(
                tenant_id=tenant.id,
                code=f"P-{tenant.id.hex[:10].upper()}",
                status="active",
            ))
        if settings.superadmin_email and settings.superadmin_password:
            email = settings.superadmin_email.strip().lower()
            admin = db.scalar(select(User).where(User.email == email))
            if admin is None:
                master = Tenant(name="Digitechified Admin")
                db.add(master)
                db.flush()
                admin = User(
                    tenant_id=master.id,
                    email=email,
                    password_hash=hash_password(settings.superadmin_password),
                    role="super_admin",
                )
                db.add(admin)
            elif settings.superadmin_force_password_reset and admin.role == "super_admin":
                # Explicit, temporary recovery switch. Disable it in Render after login is restored.
                admin.password_hash = hash_password(settings.superadmin_password)
                reset_at = datetime.now(timezone.utc)
                security_state = db.get(UserSecurity, admin.id)
                if security_state:
                    security_state.tokens_valid_after = reset_at
                else:
                    db.add(UserSecurity(user_id=admin.id, tokens_valid_after=reset_at))
                db.add(AdminAccessLog(
                    admin_user_id=admin.id,
                    tenant_id=admin.tenant_id,
                    action="admin_password_recovered",
                    details="Super Admin password synchronized from Render environment",
                ))
        db.commit()
    finally:
        db.close()


def current_user(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> Principal:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required")
    claims = decode_access_token(authorization[7:])
    if not claims:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    try:
        user_id, requested_tenant_id = UUID(claims["sub"]), UUID(claims["tid"])
    except (KeyError, ValueError, TypeError):
        raise HTTPException(status_code=401, detail="Invalid token")

    actor = db.get(User, user_id)
    if not actor:
        raise HTTPException(status_code=401, detail="User not found")
    security_state = db.get(UserSecurity, user_id)
    if security_state:
        issued_at = claims.get("iat")
        if issued_at is None or float(issued_at) < security_state.tokens_valid_after.timestamp():
            raise HTTPException(status_code=401, detail="Session expired after a password change. Please log in again.")

    is_admin = actor.role == "super_admin"
    impersonating = bool(claims.get("imp"))
    if is_admin:
        if requested_tenant_id != actor.tenant_id:
            if not impersonating:
                raise HTTPException(status_code=403, detail="Invalid admin workspace token")
            partner = _partner_for_tenant(db, requested_tenant_id)
            if not partner or partner.status != "active":
                raise HTTPException(status_code=403, detail="Partner workspace is unavailable")
        effective_tenant_id = requested_tenant_id
    else:
        if requested_tenant_id != actor.tenant_id:
            raise HTTPException(status_code=403, detail="Partner data access denied")
        partner = _partner_for_tenant(db, actor.tenant_id)
        if not partner:
            raise HTTPException(status_code=403, detail="Partner workspace is not provisioned")
        if partner.status != "active":
            raise HTTPException(status_code=403, detail="Partner account is disabled")
        effective_tenant_id = actor.tenant_id

    return Principal(
        id=actor.id,
        tenant_id=effective_tenant_id,
        role=actor.role,
        email=actor.email,
        impersonating=impersonating,
    )


def require_admin(user: Principal = Depends(current_user)) -> Principal:
    if user.role != "super_admin" or user.impersonating:
        raise HTTPException(status_code=403, detail="Digitechified admin access required")
    return user


@app.get("/health")
def health():
    return {"status": "ok", "service": "digitechified-business-manager-api"}


@app.post("/api/auth/register")
def register_test_partner(data: RegisterIn, db: Session = Depends(get_db)):
    # Synthetic-only self-registration is retained for the isolated CI test service.
    if settings.app_env.lower() != "test":
        raise HTTPException(status_code=403, detail="Public registration is disabled. Contact Digitechified Admin.")
    if db.scalar(select(User).where(User.email == data.email.lower())):
        raise HTTPException(status_code=409, detail="Email already registered")
    tenant = Tenant(name=data.business_name.strip())
    db.add(tenant)
    db.flush()
    user = User(tenant_id=tenant.id, email=data.email.lower(), password_hash=hash_password(data.password), role="partner")
    partner = Partner(tenant_id=tenant.id, code=f"P-{uuid4().hex[:10].upper()}", status="active")
    db.add_all([user, partner])
    db.commit()
    return {"access_token": create_access_token(str(user.id), str(tenant.id)), "token_type": "bearer", "business_name": tenant.name, "role": user.role, "tenant_id": str(tenant.id)}

@app.post("/api/auth/login")
def login(data: LoginIn, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == data.email.lower()))
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Login ID or password is incorrect")
    tenant = db.get(Tenant, user.tenant_id)
    if user.role != "super_admin":
        partner = _partner_for_tenant(db, user.tenant_id)
        if not partner or partner.status != "active":
            raise HTTPException(status_code=403, detail="Partner account is disabled or not provisioned. Contact Digitechified Admin.")
    return {
        "access_token": create_access_token(str(user.id), str(user.tenant_id)),
        "token_type": "bearer",
        "business_name": tenant.name if tenant else "",
        "role": user.role,
        "login_id": user.email,
        "tenant_id": str(user.tenant_id),
    }


@app.post("/api/auth/change-password")
def change_own_password(
    data: PasswordChangeIn,
    admin: Principal = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Allow the authenticated Super Admin to rotate their own password."""
    user = db.get(User, admin.id)
    if not user or not verify_password(data.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")
    if data.current_password == data.new_password:
        raise HTTPException(status_code=400, detail="New password must be different")
    user.password_hash = hash_password(data.new_password)
    security_state = db.get(UserSecurity, user.id)
    reset_at = datetime.now(timezone.utc)
    if security_state:
        security_state.tokens_valid_after = reset_at
    else:
        db.add(UserSecurity(user_id=user.id, tokens_valid_after=reset_at))
    _write_admin_log(db, admin.id, admin.tenant_id, "admin_password_changed", "Super Admin changed own password")
    db.commit()
    return {"ok": True, "message": "Password updated. Please log in again."}


@app.get("/api/auth/me")
def me(user: Principal = Depends(current_user), db: Session = Depends(get_db)):
    tenant = db.get(Tenant, user.tenant_id)
    return {
        "login_id": user.email,
        "email": user.email,
        "role": user.role,
        "business_name": tenant.name if tenant else "",
        "impersonating": user.impersonating,
        "tenant_id": str(user.tenant_id),
    }


@app.get("/api/admin/partners")
def list_partners(admin: Principal = Depends(require_admin), db: Session = Depends(get_db)):
    rows = db.execute(
        select(Partner, Tenant, User)
        .join(Tenant, Tenant.id == Partner.tenant_id)
        .join(User, User.tenant_id == Tenant.id)
        .where(User.role != "super_admin")
        .order_by(Partner.created_at.desc())
    ).all()
    return {"partners": [{
        "partner_id": str(partner.id),
        "tenant_id": str(tenant.id),
        "partner_code": partner.code,
        "name": tenant.name,
        "login_id": user.email,
        "status": partner.status,
        "created_at": partner.created_at.isoformat(),
    } for partner, tenant, user in rows]}


@app.post("/api/admin/partners", status_code=201)
def create_partner(data: PartnerCreateIn, admin: Principal = Depends(require_admin), db: Session = Depends(get_db)):
    login_id = data.login_id.lower()
    if db.scalar(select(User).where(User.email == login_id)):
        raise HTTPException(status_code=409, detail="This login ID is already in use")
    tenant = Tenant(name=data.name.strip())
    db.add(tenant)
    db.flush()
    user = User(
        tenant_id=tenant.id,
        email=login_id,
        password_hash=hash_password(data.password),
        role="partner",
    )
    partner = Partner(
        tenant_id=tenant.id,
        code=f"P-{uuid4().hex[:10].upper()}",
        status="active",
        created_by=admin.id,
    )
    db.add_all([user, partner])
    _write_admin_log(db, admin.id, tenant.id, "partner_created", f"Created {login_id}")
    db.commit()
    return {
        "partner_id": str(partner.id),
        "tenant_id": str(tenant.id),
        "partner_code": partner.code,
        "name": tenant.name,
        "login_id": user.email,
        "status": partner.status,
    }


@app.patch("/api/admin/partners/{tenant_id}")
def update_partner(tenant_id: UUID, data: PartnerUpdateIn, admin: Principal = Depends(require_admin), db: Session = Depends(get_db)):
    tenant = db.get(Tenant, tenant_id)
    partner = _partner_for_tenant(db, tenant_id)
    user = db.scalar(select(User).where(User.tenant_id == tenant_id, User.role != "super_admin"))
    if not tenant or not partner or not user:
        raise HTTPException(status_code=404, detail="Partner not found")
    changes = []
    if data.name is not None:
        tenant.name = data.name.strip()
        changes.append("name")
    if data.login_id is not None:
        login_id = data.login_id.lower()
        duplicate = db.scalar(select(User).where(User.email == login_id, User.id != user.id))
        if duplicate:
            raise HTTPException(status_code=409, detail="This login ID is already in use")
        user.email = login_id
        changes.append("login_id")
    if data.status is not None:
        partner.status = data.status
        changes.append("status")
    if changes:
        _write_admin_log(db, admin.id, tenant_id, "partner_updated", ",".join(changes))
        db.commit()
    return {"ok": True, "tenant_id": str(tenant_id), "name": tenant.name, "login_id": user.email, "status": partner.status}


@app.post("/api/admin/partners/{tenant_id}/reset-password")
def reset_partner_password(tenant_id: UUID, data: PasswordResetIn, admin: Principal = Depends(require_admin), db: Session = Depends(get_db)):
    partner = _partner_for_tenant(db, tenant_id)
    user = db.scalar(select(User).where(User.tenant_id == tenant_id, User.role != "super_admin"))
    if not partner or not user:
        raise HTTPException(status_code=404, detail="Partner not found")
    user.password_hash = hash_password(data.new_password)
    security_state = db.get(UserSecurity, user.id)
    reset_at = datetime.now(timezone.utc)
    if security_state:
        security_state.tokens_valid_after = reset_at
    else:
        db.add(UserSecurity(user_id=user.id, tokens_valid_after=reset_at))
    _write_admin_log(db, admin.id, tenant_id, "password_reset", f"Password reset for {user.email}")
    db.commit()
    return {"ok": True, "message": "Partner password updated"}


@app.post("/api/admin/partners/{tenant_id}/access")
def access_partner(tenant_id: UUID, admin: Principal = Depends(require_admin), db: Session = Depends(get_db)):
    partner = _partner_for_tenant(db, tenant_id)
    tenant = db.get(Tenant, tenant_id)
    if not partner or not tenant or partner.status != "active":
        raise HTTPException(status_code=404, detail="Active partner not found")
    _write_admin_log(db, admin.id, tenant_id, "admin_access_started", f"Admin opened partner workspace: {tenant.name}")
    db.commit()
    # The token retains the admin as its subject; only the effective tenant changes.
    token = create_access_token(str(admin.id), str(tenant_id), expires_minutes=30, impersonating=True)
    return {"access_token": token, "token_type": "bearer", "tenant_id": str(tenant_id), "partner_name": tenant.name, "role": "super_admin", "expires_in": 1800}


@app.get("/api/admin/audit-logs")
def admin_audit_logs(limit: int = 100, admin: Principal = Depends(require_admin), db: Session = Depends(get_db)):
    safe_limit = max(1, min(limit, 500))
    rows = db.scalars(select(AdminAccessLog).order_by(AdminAccessLog.created_at.desc()).limit(safe_limit)).all()
    return {"logs": [{
        "admin_user_id": str(row.admin_user_id),
        "tenant_id": str(row.tenant_id),
        "action": row.action,
        "details": row.details,
        "created_at": row.created_at.isoformat(),
    } for row in rows]}


@app.get("/api/records")
def list_records(module: str | None = None, limit: int = 1000, offset: int = 0, user: Principal = Depends(current_user), db: Session = Depends(get_db)):
    safe_limit = max(1, min(limit, 5000))
    safe_offset = max(0, offset)
    query = select(BusinessRecord).where(BusinessRecord.tenant_id == user.tenant_id)
    if module:
        query = query.where(BusinessRecord.module == module)
    items = db.scalars(query.order_by(BusinessRecord.updated_at.desc()).offset(safe_offset).limit(safe_limit)).all()
    return {"records": [{"record_id": x.record_id, "module": x.module, "payload": x.payload, "updated_at": x.updated_at.isoformat()} for x in items], "limit": safe_limit, "offset": safe_offset}


@app.put("/api/records")
def upsert_record(data: RecordIn, user: Principal = Depends(current_user), db: Session = Depends(get_db)):
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
def batch_upsert(data: RecordBatchIn, user: Principal = Depends(current_user), db: Session = Depends(get_db)):
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


@app.post("/api/orders/parse-label-pdf")
async def parse_label_pdf(
    file: UploadFile = File(...),
    platform: str = Form(...),
    firm: str = Form(""),
    user: Principal = Depends(current_user),
):
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Please upload a PDF file")
    raw = await file.read(20 * 1024 * 1024 + 1)
    if len(raw) > 20 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="PDF must be 20 MB or smaller")
    try:
        from pypdf import PdfReader
        import io, re
        reader = PdfReader(io.BytesIO(raw))
    except Exception:
        raise HTTPException(status_code=400, detail="Could not read this PDF")
    records = []
    skipped = 0
    for page_no, page in enumerate(reader.pages, start=1):
        text = page.extract_text() or ""
        # Only inspect the shipping-label portion; never use invoice data.
        label = re.split(r"TAX\s+INVOICE", text, flags=re.I)[0]
        match = re.search(r"SKU\s+Size\s+Qty\s+Color\s+Order\s+No\.?\s*(.*)", label, flags=re.I|re.S)
        if not match:
            # Some Myntra label layouts use a compact item row.
            match = re.search(r"Product\s+Details\s*(.*)", label, flags=re.I|re.S)
        if not match:
            skipped += 1
            continue
        section = match.group(1)
        lines = [re.sub(r"\s+", " ", x).strip() for x in section.splitlines() if x.strip()]
        parsed = 0
        for line in lines:
            if re.search(r"^(SKU|Size|Qty|Color|Order No)", line, re.I):
                continue
            # Common Meesho label row: SKU, size, quantity, color, marketplace order id.
            row = re.match(r"^(\S+)\s+(.+?)\s+(\d+)\s+([A-Za-z][A-Za-z -]*?)\s+(\d{12,}(?:_\d+)?)$", line)
            if not row:
                continue
            sku, size, qty, color, order_id = row.groups()
            head = label[:match.start()]
            courier_match = re.search(r"\b(Delhivery|Shadowfax|Ecom Express|Blue Dart|Xpressbees|Ekart)\b", head, re.I)
            awb_match = re.search(r"(?<!\d)(?:SF)?[A-Z0-9]{10,22}(?!\w)", head)
            customer_match = re.search(r"Customer Address\s+(.+?)(?:\s+If undelivered|\s+COD:)", head, re.I|re.S)
            customer = re.sub(r"\s+", " ", customer_match.group(1)).strip() if customer_match else ""
            pin_match = re.search(r"\b(\d{6})\b", customer)
            records.append({
                "Date": datetime.now(timezone.utc).date().isoformat(),
                "Platform": platform.strip(),
                "Firm / Account": firm.strip(),
                "Order ID": order_id,
                "SKU / Product": sku,
                "Size": size.strip(),
                "Color": color.strip(),
                "Orders Qty": int(qty),
                "Courier": courier_match.group(1) if courier_match else "",
                "AWB / Tracking No.": awb_match.group(0) if awb_match else "",
                "Customer": customer,
                "Pincode": pin_match.group(1) if pin_match else "",
                "Source PDF": file.filename,
                "PDF Page": page_no,
                "Import Type": "Shipping Label",
            })
            parsed += 1
        if parsed == 0:
            skipped += 1
    return {"records": records, "pages": len(reader.pages), "skipped_pages": skipped, "parsed_lines": len(records)}


@app.delete("/api/records/{record_id}")
def remove_record(record_id: str, user: Principal = Depends(current_user), db: Session = Depends(get_db)):
    item = db.scalar(select(BusinessRecord).where(BusinessRecord.tenant_id == user.tenant_id, BusinessRecord.record_id == record_id))
    if not item:
        raise HTTPException(status_code=404, detail="Record not found")
    db.add(AuditLog(tenant_id=user.tenant_id, user_id=user.id, action="delete", module=item.module, record_id=item.record_id))
    db.delete(item)
    db.commit()
    return {"ok": True}
