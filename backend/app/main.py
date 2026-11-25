from uuid import UUID
from fastapi import Depends, FastAPI, Header, HTTPException, UploadFile, File, Form
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




@app.post("/api/orders/parse-label-pdf")
async def parse_label_pdf(
    file: UploadFile = File(...),
    platform: str = Form(...),
    firm: str = Form(""),
    user: User = Depends(current_user),
):
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Please upload a PDF file")
    raw = await file.read()
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
                "Date": __import__("datetime").date.today().isoformat(),
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
def remove_record(record_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    item = db.scalar(select(BusinessRecord).where(BusinessRecord.tenant_id == user.tenant_id, BusinessRecord.record_id == record_id))
    if not item:
        raise HTTPException(status_code=404, detail="Record not found")
    db.add(AuditLog(tenant_id=user.tenant_id, user_id=user.id, action="delete", module=item.module, record_id=item.record_id))
    db.delete(item)
    db.commit()
    return {"ok": True}
