"""Monthly, tenant-isolated partner data backups delivered by email.

Runs inside the existing API process (no extra Render service). The daily
scheduler only sends during days 1-7, so a short API outage on the 1st can
be recovered automatically. A DB marker prevents repeat sends per partner.
"""
import io
import json
import logging
import os
import smtplib
import zipfile
from datetime import datetime
from email.message import EmailMessage
from zoneinfo import ZoneInfo

from apscheduler.schedulers.background import BackgroundScheduler
from sqlalchemy import select

from .database import SessionLocal
from .models import (
    Tenant, User, Partner, BusinessRecord, AuditLog, PartnerBackupDelivery,
)

logger = logging.getLogger(__name__)
IST = ZoneInfo("Asia/Kolkata")
MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024
_scheduler = None


def _json_default(value):
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def _send_partner_backup(db, partner, tenant, user, backup_month, smtp):
    existing = db.scalar(select(PartnerBackupDelivery).where(
        PartnerBackupDelivery.tenant_id == tenant.id,
        PartnerBackupDelivery.backup_month == backup_month,
    ))
    if existing:
        return "already_sent"

    records = db.scalars(select(BusinessRecord).where(
        BusinessRecord.tenant_id == tenant.id
    ).order_by(BusinessRecord.module, BusinessRecord.record_id)).all()
    audit_logs = db.scalars(select(AuditLog).where(
        AuditLog.tenant_id == tenant.id
    ).order_by(AuditLog.created_at)).all()

    export = {
        "backup_type": "Digitechified Business Manager Partner Backup",
        "backup_month": backup_month,
        "generated_at": datetime.now(IST).isoformat(),
        "partner": {
            "business_name": tenant.name,
            "partner_code": partner.code,
            "registered_email": user.email,
            "status": partner.status,
            "tenant_id": str(tenant.id),
        },
        "records": [
            {
                "record_id": row.record_id,
                "module": row.module,
                "payload": row.payload,
                "updated_at": row.updated_at.isoformat() if row.updated_at else None,
            } for row in records
        ],
        "activity_logs": [
            {
                "action": row.action,
                "module": row.module,
                "record_id": row.record_id,
                "created_at": row.created_at.isoformat() if row.created_at else None,
            } for row in audit_logs
        ],
    }

    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            f"partner_backup_{backup_month}.json",
            json.dumps(export, ensure_ascii=False, default=_json_default, indent=2),
        )
        archive.writestr(
            "README.txt",
            "This archive contains only the business records and activity logs "
            "for the partner named in partner_backup JSON. It does not contain "
            "login passwords, password hashes, tokens, or other partners' data.\n",
        )
    attachment = buffer.getvalue()
    if len(attachment) > MAX_ATTACHMENT_BYTES:
        logger.error(
            "Partner backup too large for email; partner=%s month=%s bytes=%s",
            tenant.id, backup_month, len(attachment),
        )
        return "too_large"

    sender = os.environ["BACKUP_SMTP_USERNAME"].strip()
    message = EmailMessage()
    message["Subject"] = f"Your monthly business data backup - {backup_month}"
    message["From"] = sender
    message["To"] = user.email
    message.set_content(
        f"Hello {tenant.name},\n\n"
        f"Attached is your Digitechified Business Manager data backup for {backup_month}.\n"
        "This ZIP contains only your business workspace data. Please keep it in a safe place.\n\n"
        "Regards,\nDigitechified"
    )
    message.add_attachment(
        attachment,
        maintype="application",
        subtype="zip",
        filename=f"Digitechified_Backup_{backup_month}.zip",
    )
    smtp.send_message(message)

    db.add(PartnerBackupDelivery(
        tenant_id=tenant.id,
        backup_month=backup_month,
        records_count=len(records),
    ))
    db.commit()
    return "sent"


def run_monthly_partner_backups():
    now = datetime.now(IST)
    # Daily checks from the 1st through 7th provide a small outage-recovery window.
    if now.day > 7:
        return
    backup_month = now.strftime("%Y-%m")

    smtp_username = os.getenv("BACKUP_SMTP_USERNAME", "").strip()
    smtp_password = os.getenv("BACKUP_SMTP_APP_PASSWORD", "").strip()
    if not smtp_username or not smtp_password:
        logger.warning("Monthly partner backups are not configured: Gmail SMTP credentials missing")
        return

    db = SessionLocal()
    try:
        partners = db.execute(
            select(Partner, Tenant, User)
            .join(Tenant, Tenant.id == Partner.tenant_id)
            .join(User, User.tenant_id == Tenant.id)
            .where(Partner.status == "active", User.role == "partner")
            .order_by(Tenant.name)
        ).all()
        if not partners:
            logger.info("Monthly partner backup: no active partners found")
            return

        summary_rows = []
        with smtplib.SMTP("smtp.gmail.com", 587, timeout=30) as smtp:
            smtp.ehlo()
            smtp.starttls()
            smtp.ehlo()
            smtp.login(smtp_username, smtp_password)
            for partner, tenant, user in partners:
                try:
                    result = _send_partner_backup(
                        db, partner, tenant, user, backup_month, smtp
                    )
                    # Count all records for the admin summary without including their contents.
                    records_total = len(db.scalars(select(BusinessRecord.record_id).where(
                        BusinessRecord.tenant_id == tenant.id
                    )).all())
                    summary_rows.append(
                        f"- {tenant.name} | {user.email} | records: {records_total} | status: {result}"
                    )
                    logger.info(
                        "Partner backup result=%s tenant=%s month=%s",
                        result, tenant.id, backup_month,
                    )
                except Exception as exc:
                    db.rollback()
                    summary_rows.append(
                        f"- {tenant.name} | {user.email} | status: FAILED ({type(exc).__name__})"
                    )
                    logger.exception(
                        "Partner backup failed tenant=%s month=%s",
                        tenant.id, backup_month,
                    )

            admin_message = EmailMessage()
            admin_message["Subject"] = f"Digitechified monthly backup summary - {backup_month}"
            admin_message["From"] = smtp_username
            admin_message["To"] = smtp_username
            admin_message.set_content(
                "Monthly partner backup summary\\n"
                f"Month: {backup_month}\\n"
                f"Active partners: {len(partners)}\\n"
                f"Sent: {sum('status: sent' in row for row in summary_rows)}\\n"
                f"Already sent: {sum('status: already_sent' in row for row in summary_rows)}\\n"
                f"Failed/other: {sum(('status: FAILED' in row) or ('status: too_large' in row) for row in summary_rows)}\\n\\n"
                "Per-partner status (metadata and counts only; no partner records attached):\\n"
                + ("\\n".join(summary_rows) if summary_rows else "No partner details.")
            )
            smtp.send_message(admin_message)
            logger.info("Monthly partner backup summary emailed to Super Admin %s for %s", smtp_username, backup_month)
    except Exception:
        db.rollback()
        logger.exception("Monthly partner backup scheduler failed")
    finally:
        db.close()


def start_backup_scheduler():
    global _scheduler
    if _scheduler and _scheduler.running:
        return
    _scheduler = BackgroundScheduler(timezone=IST)
    _scheduler.add_job(
        run_monthly_partner_backups,
        trigger="cron",
        hour=9,
        minute=5,
        id="monthly_partner_email_backups",
        replace_existing=True,
        coalesce=True,
        max_instances=1,
        misfire_grace_time=60 * 60 * 24 * 7,
    )
    _scheduler.start()
    logger.info("Monthly partner email backup scheduler started (09:05 Asia/Kolkata)")


def stop_backup_scheduler():
    global _scheduler
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=False)


def send_partner_backup_test(db, partner, tenant, user):
    """Send a one-off test ZIP to one partner without writing monthly delivery markers."""
    smtp_username = os.getenv("BACKUP_SMTP_USERNAME", "").strip()
    smtp_password = os.getenv("BACKUP_SMTP_APP_PASSWORD", "").strip()
    if not smtp_username or not smtp_password:
        raise RuntimeError("Gmail SMTP credentials are not configured")

    records = db.scalars(select(BusinessRecord).where(
        BusinessRecord.tenant_id == tenant.id
    ).order_by(BusinessRecord.module, BusinessRecord.record_id)).all()
    audit_logs = db.scalars(select(AuditLog).where(
        AuditLog.tenant_id == tenant.id
    ).order_by(AuditLog.created_at)).all()
    now = datetime.now(IST)
    export = {
        "backup_type": "Digitechified Business Manager TEST Backup",
        "backup_month": now.strftime("%Y-%m"),
        "generated_at": now.isoformat(),
        "partner": {
            "business_name": tenant.name,
            "partner_code": partner.code,
            "registered_email": user.email,
            "status": partner.status,
            "tenant_id": str(tenant.id),
        },
        "records": [{
            "record_id": row.record_id,
            "module": row.module,
            "payload": row.payload,
            "updated_at": row.updated_at.isoformat() if row.updated_at else None,
        } for row in records],
        "activity_logs": [{
            "action": row.action,
            "module": row.module,
            "record_id": row.record_id,
            "created_at": row.created_at.isoformat() if row.created_at else None,
        } for row in audit_logs],
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            f"TEST_partner_backup_{now.strftime('%Y-%m')}.json",
            json.dumps(export, ensure_ascii=False, default=_json_default, indent=2),
        )
        archive.writestr(
            "README.txt",
            "TEST BACKUP. Contains only the business records and activity logs "
            "for the named partner. No passwords, hashes, tokens, or other partners' data.\\n",
        )
    attachment = buffer.getvalue()
    if len(attachment) > MAX_ATTACHMENT_BYTES:
        raise ValueError("Partner backup is larger than the 20 MB email attachment limit")

    message = EmailMessage()
    message["Subject"] = f"[TEST] Your business data backup - {now.strftime('%Y-%m')}"
    message["From"] = smtp_username
    message["To"] = user.email
    message.set_content(
        f"Hello {tenant.name},\\n\\n"
        "This is a TEST backup email from Digitechified Business Manager.\\n"
        "The attached ZIP contains only this partner workspace's data.\\n\\n"
        "Regards,\\nDigitechified"
    )
    message.add_attachment(
        attachment, maintype="application", subtype="zip",
        filename=f"Digitechified_TEST_Backup_{now.strftime('%Y-%m')}.zip",
    )
    with smtplib.SMTP("smtp.gmail.com", 587, timeout=30) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.ehlo()
        smtp.login(smtp_username, smtp_password)
        smtp.send_message(message)
    logger.info("Partner TEST backup email sent tenant=%s recipient=%s records=%s", tenant.id, user.email, len(records))
    return {"recipient": user.email, "records_count": len(records), "attachment_bytes": len(attachment)}
