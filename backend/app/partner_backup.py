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


def _build_summary_pdf(export):
    """Create a compact, professional PDF containing counts only (no order rows)."""
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
    from collections import Counter

    partner_data = export.get("partner", {})
    records = export.get("records", [])
    logs = export.get("activity_logs", [])
    module_counts = Counter(str(row.get("module") or "Uncategorized") for row in records)
    daily_order_count = sum(
        count for module, count in module_counts.items()
        if "daily" in module.lower() and "order" in module.lower()
    )

    buffer = io.BytesIO()
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(
        name="DBMTitle", parent=styles["Title"], fontName="Helvetica-Bold",
        fontSize=20, leading=24, alignment=TA_CENTER,
        textColor=colors.HexColor("#183153"), spaceAfter=3,
    ))
    styles.add(ParagraphStyle(
        name="DBMSub", parent=styles["Normal"], fontSize=9, leading=12,
        alignment=TA_CENTER, textColor=colors.HexColor("#667085"), spaceAfter=15,
    ))
    styles.add(ParagraphStyle(
        name="DBMSection", parent=styles["Heading2"], fontSize=11, leading=14,
        textColor=colors.HexColor("#A87912"), spaceBefore=12, spaceAfter=7,
    ))
    styles.add(ParagraphStyle(name="DBMCell", parent=styles["BodyText"], fontSize=8, leading=10))
    styles.add(ParagraphStyle(
        name="DBMKpiLabel", parent=styles["BodyText"], fontSize=7, leading=9,
        alignment=TA_CENTER, textColor=colors.HexColor("#667085"),
    ))
    styles.add(ParagraphStyle(
        name="DBMKpiValue", parent=styles["BodyText"], fontName="Helvetica-Bold",
        fontSize=18, leading=22, alignment=TA_CENTER, textColor=colors.HexColor("#183153"),
    ))
    styles.add(ParagraphStyle(
        name="DBMNote", parent=styles["BodyText"], fontSize=8, leading=11,
        textColor=colors.HexColor("#667085"),
    ))

    doc = SimpleDocTemplate(
        buffer, pagesize=A4, rightMargin=17*mm, leftMargin=17*mm,
        topMargin=16*mm, bottomMargin=18*mm,
    )
    story = [
        Paragraph("DIGITECHIFIED", styles["DBMTitle"]),
        Paragraph(f"PARTNER BACKUP SUMMARY  |  {export.get('backup_month', '')}", styles["DBMSub"]),
    ]
    info = [
        [Paragraph("<b>Partner</b>", styles["DBMCell"]), Paragraph(str(partner_data.get("business_name", "—")), styles["DBMCell"])],
        [Paragraph("<b>Registered Email</b>", styles["DBMCell"]), Paragraph(str(partner_data.get("registered_email", "—")), styles["DBMCell"])],
        [Paragraph("<b>Partner Code</b>", styles["DBMCell"]), Paragraph(str(partner_data.get("partner_code", "—")), styles["DBMCell"])],
        [Paragraph("<b>Account Status</b>", styles["DBMCell"]), Paragraph(str(partner_data.get("status", "—")).title(), styles["DBMCell"])],
        [Paragraph("<b>Generated</b>", styles["DBMCell"]), Paragraph(str(export.get("generated_at", "—")), styles["DBMCell"])],
    ]
    info_table = Table(info, colWidths=[42*mm, 130*mm])
    info_table.setStyle(TableStyle([
        ("BACKGROUND",(0,0),(0,-1),colors.HexColor("#F4F0E7")),
        ("BACKGROUND",(1,0),(1,-1),colors.HexColor("#FBFAF7")),
        ("BOX",(0,0),(-1,-1),0.6,colors.HexColor("#E3DED2")),
        ("INNERGRID",(0,0),(-1,-1),0.35,colors.HexColor("#E3DED2")),
        ("VALIGN",(0,0),(-1,-1),"MIDDLE"),
        ("LEFTPADDING",(0,0),(-1,-1),9),("RIGHTPADDING",(0,0),(-1,-1),9),
        ("TOPPADDING",(0,0),(-1,-1),7),("BOTTOMPADDING",(0,0),(-1,-1),7),
    ]))
    story += [info_table, Paragraph("BACKUP AT A GLANCE", styles["DBMSection"])]
    kpi = Table([
        [Paragraph("TOTAL BUSINESS RECORDS", styles["DBMKpiLabel"]),
         Paragraph("DAILY ORDER RECORDS", styles["DBMKpiLabel"]),
         Paragraph("ACTIVITY LOG COUNT", styles["DBMKpiLabel"])],
        [Paragraph(str(len(records)), styles["DBMKpiValue"]),
         Paragraph(str(daily_order_count), styles["DBMKpiValue"]),
         Paragraph(str(len(logs)), styles["DBMKpiValue"])],
    ], colWidths=[57.3*mm]*3, rowHeights=[10*mm, 15*mm])
    kpi.setStyle(TableStyle([
        ("BACKGROUND",(0,0),(-1,-1),colors.HexColor("#F7F8FA")),
        ("BOX",(0,0),(-1,-1),0.6,colors.HexColor("#E3E7ED")),
        ("INNERGRID",(0,0),(-1,-1),0.6,colors.HexColor("#E3E7ED")),
        ("VALIGN",(0,0),(-1,-1),"MIDDLE"),
        ("LEFTPADDING",(0,0),(-1,-1),5),("RIGHTPADDING",(0,0),(-1,-1),5),
    ]))
    story += [kpi, Paragraph("RECORDS BY MODULE", styles["DBMSection"])]
    if module_counts:
        rows = [[Paragraph("<b>Module</b>", styles["DBMCell"]), Paragraph("<b>Record Count</b>", styles["DBMCell"])]]
        rows.extend([
            [Paragraph(module, styles["DBMCell"]), Paragraph(str(count), styles["DBMCell"])]
            for module, count in sorted(module_counts.items())
        ])
        rows.append([Paragraph("<b>Total</b>", styles["DBMCell"]), Paragraph(f"<b>{len(records)}</b>", styles["DBMCell"])])
        table = Table(rows, colWidths=[125*mm, 47*mm], repeatRows=1)
        table.setStyle(TableStyle([
            ("BACKGROUND",(0,0),(-1,0),colors.HexColor("#183153")),
            ("TEXTCOLOR",(0,0),(-1,0),colors.white),
            ("FONTNAME",(0,0),(-1,0),"Helvetica-Bold"),
            ("BACKGROUND",(0,-1),(-1,-1),colors.HexColor("#F4F0E7")),
            ("GRID",(0,0),(-1,-1),0.4,colors.HexColor("#E1E5EA")),
            ("ALIGN",(1,1),(1,-1),"RIGHT"),("VALIGN",(0,0),(-1,-1),"MIDDLE"),
            ("LEFTPADDING",(0,0),(-1,-1),9),("RIGHTPADDING",(0,0),(-1,-1),9),
            ("TOPPADDING",(0,0),(-1,-1),7),("BOTTOMPADDING",(0,0),(-1,-1),7),
        ]))
        story.append(table)
    story += [
        Paragraph("PRIVACY &amp; SCOPE", styles["DBMSection"]),
        Paragraph(
            "This PDF contains summary counts only. Individual order entries and individual activity-log entries are not printed. "
            "This PDF contains the partner backup summary and module-wise record counts.",
            styles["DBMNote"],
        ),
        Spacer(1, 16),
        Paragraph("CONFIDENTIAL  •  PARTNER-SPECIFIC BACKUP  •  DIGITECHIFIED BUSINESS MANAGER", styles["DBMSub"]),
    ]

    def footer(canvas, doc):
        canvas.saveState()
        width, _ = A4
        canvas.setStrokeColor(colors.HexColor("#E3E7ED"))
        canvas.line(17*mm, 12*mm, width-17*mm, 12*mm)
        canvas.setFont("Helvetica", 7)
        canvas.setFillColor(colors.HexColor("#7A8493"))
        canvas.drawString(17*mm, 7*mm, "DIGITECHIFIED  |  CONFIDENTIAL")
        canvas.drawRightString(width-17*mm, 7*mm, f"Page {doc.page}")
        canvas.restoreState()

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()


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

    pdf_attachment = _build_summary_pdf(export)
    if len(pdf_attachment) > MAX_ATTACHMENT_BYTES:
        logger.error("Partner backup PDF too large for email; partner=%s month=%s", tenant.id, backup_month)
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
        pdf_attachment,
        maintype="application",
        subtype="pdf",
        filename=f"Digitechified_Backup_Summary_{backup_month}.pdf",
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
    pdf_attachment = _build_summary_pdf(export)
    if len(pdf_attachment) > MAX_ATTACHMENT_BYTES:
        raise ValueError("Partner backup PDF is larger than the 20 MB email attachment limit")

    message = EmailMessage()
    message["Subject"] = f"[TEST] Your business data backup - {now.strftime('%Y-%m')}"
    message["From"] = smtp_username
    message["To"] = user.email
    message.set_content(
        f"Hello {tenant.name},\\n\\n"
        "This is a TEST backup email from Digitechified Business Manager.\\n"
        "Attached is the partner-specific PDF backup summary with record counts and module-wise details.\\n\\n"
        "Regards,\\nDigitechified"
    )
    message.add_attachment(
        pdf_attachment, maintype="application", subtype="pdf",
        filename=f"Digitechified_TEST_Backup_Summary_{now.strftime('%Y-%m')}.pdf",
    )
    with smtplib.SMTP("smtp.gmail.com", 587, timeout=30) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.ehlo()
        smtp.login(smtp_username, smtp_password)
        smtp.send_message(message)
    logger.info("Partner TEST backup email sent tenant=%s recipient=%s records=%s", tenant.id, user.email, len(records))
    return {"recipient": user.email, "records_count": len(records), "pdf_bytes": len(pdf_attachment)}
