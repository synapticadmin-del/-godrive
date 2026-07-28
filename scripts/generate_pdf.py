#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Generate bilingual (Arabic + English) PDF: مشروع منصة شاملة لنقل الركاب
"""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm, cm
from reportlab.lib.colors import HexColor, white, black
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT, TA_JUSTIFY
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    PageBreak, Image, KeepTogether, Flowable
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas as canvaslib
import arabic_reshaper
from bidi.algorithm import get_display

# ============================================================
# Font Registration
# ============================================================
FONT_DIR = r"C:\Windows\Fonts"
pdfmetrics.registerFont(TTFont("Arabic", os.path.join(FONT_DIR, "tahoma.ttf")))
pdfmetrics.registerFont(TTFont("Arabic-Bold", os.path.join(FONT_DIR, "tahomabd.ttf")))
pdfmetrics.registerFont(TTFont("Arial", os.path.join(FONT_DIR, "arial.ttf")))
pdfmetrics.registerFont(TTFont("Arial-Bold", os.path.join(FONT_DIR, "arialbd.ttf")))

# ============================================================
# Colors
# ============================================================
PRIMARY = HexColor("#1a56db")
DARK_BG = HexColor("#0f172a")
CARD_BG = HexColor("#f8fafc")
TEXT_DARK = HexColor("#1e293b")
TEXT_MUTED = HexColor("#64748b")
ACCENT = HexColor("#0891b2")
SUCCESS = HexColor("#16a34a")
WARNING = HexColor("#d97706")
WHITE = HexColor("#ffffff")
LIGHT_BG = HexColor("#f1f5f9")
TABLE_HEADER = HexColor("#1e40af")
TABLE_ROW_ALT = HexColor("#f8fafc")
BORDER_COLOR = HexColor("#cbd5e1")

# ============================================================
# Arabic Helper
# ============================================================
def ar(text):
    """Reshape and apply bidi for Arabic text."""
    reshaped = arabic_reshaper.reshape(text)
    return get_display(reshaped)

# ============================================================
# Styles
# ============================================================
styles = getSampleStyleSheet()

style_cover_title = ParagraphStyle(
    "CoverTitle", parent=styles["Title"],
    fontName="Arabic-Bold", fontSize=32, leading=40,
    alignment=TA_CENTER, textColor=PRIMARY, spaceAfter=10,
)
style_cover_sub = ParagraphStyle(
    "CoverSub", parent=styles["Normal"],
    fontName="Arabic", fontSize=16, leading=22,
    alignment=TA_CENTER, textColor=TEXT_MUTED, spaceAfter=6,
)
style_h1_ar = ParagraphStyle(
    "H1Ar", parent=styles["Heading1"],
    fontName="Arabic-Bold", fontSize=20, leading=26,
    alignment=TA_RIGHT, textColor=PRIMARY, spaceBefore=20, spaceAfter=12,
)
style_h2_ar = ParagraphStyle(
    "H2Ar", parent=styles["Heading2"],
    fontName="Arabic-Bold", fontSize=15, leading=20,
    alignment=TA_RIGHT, textColor=TEXT_DARK, spaceBefore=14, spaceAfter=8,
)
style_body_ar = ParagraphStyle(
    "BodyAr", parent=styles["Normal"],
    fontName="Arabic", fontSize=11, leading=18,
    alignment=TA_RIGHT, textColor=TEXT_DARK, spaceAfter=6,
)
style_bullet_ar = ParagraphStyle(
    "BulletAr", parent=style_body_ar,
    leftIndent=20, rightIndent=20, bulletIndent=10, spaceAfter=3,
)
style_note_ar = ParagraphStyle(
    "NoteAr", parent=style_body_ar,
    fontSize=10, textColor=TEXT_MUTED, alignment=TA_RIGHT,
)

# English styles
style_h1_en = ParagraphStyle(
    "H1En", parent=styles["Heading1"],
    fontName="Arial-Bold", fontSize=20, leading=26,
    alignment=TA_LEFT, textColor=PRIMARY, spaceBefore=20, spaceAfter=12,
)
style_h2_en = ParagraphStyle(
    "H2En", parent=styles["Heading2"],
    fontName="Arial-Bold", fontSize=15, leading=20,
    alignment=TA_LEFT, textColor=TEXT_DARK, spaceBefore=14, spaceAfter=8,
)
style_body_en = ParagraphStyle(
    "BodyEn", parent=styles["Normal"],
    fontName="Arial", fontSize=11, leading=18,
    alignment=TA_LEFT, textColor=TEXT_DARK, spaceAfter=6,
)
style_bullet_en = ParagraphStyle(
    "BulletEn", parent=style_body_en,
    leftIndent=20, spaceAfter=3,
)
style_note_en = ParagraphStyle(
    "NoteEn", parent=style_body_en,
    fontSize=10, textColor=TEXT_MUTED, alignment=TA_LEFT,
)

# ============================================================
# Custom Flowables
# ============================================================
class HorizontalLine(Flowable):
    def __init__(self, width, color=PRIMARY, thickness=1.5):
        Flowable.__init__(self)
        self.width = width
        self.color = color
        self.thickness = thickness

    def draw(self):
        self.canv.setLineWidth(self.thickness)
        self.canv.setStrokeColor(self.color)
        self.canv.line(0, 0, self.width, 0)

class SectionDivider(Flowable):
    def __init__(self, width, label="", lang="ar"):
        Flowable.__init__(self)
        self.width = width
        self.label = label
        self.lang = lang
        self.height = 30

    def draw(self):
        self.canv.setLineWidth(0.5)
        self.canv.setStrokeColor(BORDER_COLOR)
        self.canv.line(0, 15, self.width, 15)

class ColoredBox(Flowable):
    """A colored rounded box with centered text."""
    def __init__(self, width, height, text, bg_color, text_color, font="Arabic-Bold", font_size=12):
        Flowable.__init__(self)
        self.width = width
        self.height = height
        self.text = text
        self.bg_color = bg_color
        self.text_color = text_color
        self.font = font
        self.font_size = font_size

    def draw(self):
        self.canv.setFillColor(self.bg_color)
        self.canv.roundRect(0, 0, self.width, self.height, 8, fill=1, stroke=0)
        self.canv.setFillColor(self.text_color)
        self.canv.setFont(self.font, self.font_size)
        text_width = self.canv.stringWidth(self.text, self.font, self.font_size)
        x = (self.width - text_width) / 2
        y = (self.height - self.font_size) / 2 + 2
        self.canv.drawString(x, y, self.text)

# ============================================================
# Page Templates (header/footer)
# ============================================================
def page_footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Arial", 8)
    canvas.setFillColor(TEXT_MUTED)
    page_num = canvas.getPageNumber()
    canvas.drawRightString(A4[0] - 20*mm, 12*mm, f"{page_num}")
    # Bottom line
    canvas.setStrokeColor(BORDER_COLOR)
    canvas.setLineWidth(0.3)
    canvas.line(20*mm, 15*mm, A4[0] - 20*mm, 15*mm)
    canvas.drawString(20*mm, 12*mm, "Synaptic Go")
    canvas.restoreState()

# ============================================================
# Cover Page Drawing
# ============================================================
def draw_cover(canvas, doc):
    c = canvas
    width, height = A4

    # Background gradient simulation (dark top)
    c.setFillColor(DARK_BG)
    c.rect(0, height - 220*mm, width, 220*mm, fill=1, stroke=0)

    # Blue accent bar
    c.setFillColor(PRIMARY)
    c.rect(0, height - 225*mm, width, 5*mm, fill=1, stroke=0)

    # Logo box
    c.setFillColor(white)
    c.roundRect(width/2 - 35*mm, height - 80*mm, 70*mm, 35*mm, 10, fill=1, stroke=0)
    c.setFillColor(PRIMARY)
    c.setFont("Arial-Bold", 28)
    c.drawCentredString(width/2, height - 68*mm, "SG")
    c.setFont("Arial", 10)
    c.setFillColor(TEXT_MUTED)
    c.drawCentredString(width/2, height - 78*mm, "Synaptic Go")

    # Title (Arabic - shaped)
    c.setFillColor(white)
    c.setFont("Arabic-Bold", 28)
    title = ar("مشروع منصة شاملة لنقل الركاب")
    c.drawCentredString(width/2, height - 120*mm, title)

    c.setFont("Arabic", 14)
    c.setFillColor(HexColor("#93c5fd"))
    subtitle = ar("دراسة شاملة: الميزات، التسعير، الجدوى الاقتصادية")
    c.drawCentredString(width/2, height - 135*mm, subtitle)

    # Date
    c.setFont("Arial", 11)
    c.setFillColor(HexColor("#94a3b8"))
    c.drawCentredString(width/2, height - 155*mm, "2026")

    # Bottom section
    c.setFillColor(HexColor("#f8fafc"))
    c.rect(0, 0, width, 60*mm, fill=1, stroke=0)

    c.setFillColor(PRIMARY)
    c.roundRect(width/2 - 45*mm, 30*mm, 90*mm, 12*mm, 6, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont("Arial-Bold", 10)
    c.drawCentredString(width/2, 33*mm, "CONFIDENTIAL DOCUMENT")

    c.setFillColor(TEXT_MUTED)
    c.setFont("Arial", 8)
    c.drawCentredString(width/2, 15*mm, "Synaptic Studio - All Rights Reserved")

    # Decorative lines
    c.setStrokeColor(PRIMARY)
    c.setLineWidth(2)
    c.line(40*mm, height - 100*mm, width - 40*mm, height - 100*mm)

# ============================================================
# Content Builders
# ============================================================
PAGE_WIDTH = A4[0] - 40*mm  # content width

def build_arabic_section(story):
    """Build all Arabic content pages."""
    # ==========================
    # Page: Features - Admin
    # ==========================
    story.append(Paragraph(ar("الميزات الكاملة"), style_h1_ar))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 15))

    story.append(Paragraph(ar("أولاً: لوحة تحكم الإدارة"), style_h2_ar))

    admin_features = [
        "نظام تسجيل دخول آمن (OTP + JWT) مع حماية كاملة",
        "لوحة تحكم رئيسية تعرض المؤشرات الحية والأرقام الفورية",
        "خريطة تفاعلية لمراقبة الرحلات والكباتن في الوقت الفعلي",
        "إدارة كاملة للكباتن: موافقة، إيقاف، بحث، فلترة بالحالة",
        "إدارة الرحلات: جدول شامل مع فلترة حسب الحالة والمدينة",
        "إدارة المستخدمين (الركاب والكباتن)",
        "نظام تسعير مرن قابل للتعديل حسب المدينة",
        "تحليلات متقدمة: الإيرادات، معدل الإكمال، أفضل الكباتن، رسوم بيانية",
        "سجل تدقيق كامل لكل الإجراءات الإدارية",
        "إدارة أكواد الخصم والترويج",
        "مراجعة وموافقة على مستندات الكباتن",
    ]
    for feat in admin_features:
        story.append(Paragraph(f"• {ar(feat)}", style_bullet_ar))

    story.append(Spacer(1, 15))
    story.append(Paragraph(ar("ثانياً: تطبيق المستخدم"), style_h2_ar))

    rider_features = [
        "تسجيل ودخول آمن عبر رمز التحقق (OTP)",
        "تحديد موقع المستخدم تلقائياً عبر GPS",
        "اختيار نقطة الانطلاق والوصول على الخريطة",
        "تقدير السعر المتوقع قبل طلب الرحلة",
        "طلب رحلة بضغطة واحدة",
        "تتبع الكابتن مباشرة على الخريطة (Live)",
        "إلغاء الرحلة مع تحديد السبب",
        "تقييم الكابتن بعد انتهاء الرحلة",
        "سجل كامل للرحلات السابقة",
        "حفظ الأماكن المفضلة (المنزل، العمل)",
        "اختيار نوع الرحلة (اقتصادي، كومفورت، XL)",
        "دعم أكواد الخصم عند الطلب",
    ]
    for feat in rider_features:
        story.append(Paragraph(f"• {ar(feat)}", style_bullet_ar))

    story.append(Spacer(1, 15))
    story.append(Paragraph(ar("ثالثاً: تطبيق الكابتن"), style_h2_ar))

    captain_features = [
        "تسجيل ودخول آمن عبر رمز التحقق",
        "إدخال بيانات السيارة ورفع المستندات المطلوبة",
        "التحكم في حالة التوفر (متصل / غير متصل)",
        "استقبال طلبات الرحلات فورياً عبر إشعارات لحظية",
        "قبول أو رفض الطلبات بسرعة",
        "بث الموقع المباشر أثناء الرحلة",
        "إدارة حالات الرحلة (في الطريق → وصل → بدأ → انتهى)",
        "تقارير الأرباح اليومية والأسبوعية والشهرية",
        "تقييم الراكب بعد كل رحلة",
        "التنقل عبر خرائط الملاحة للوصول لنقطة الالتقاط",
    ]
    for feat in captain_features:
        story.append(Paragraph(f"• {ar(feat)}", style_bullet_ar))

    # ==========================
    # Page: Development Costs
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph(ar("التكلفة الإجمالية للتطوير والتصميم"), style_h1_ar))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))
    story.append(Paragraph(ar("تكلفة لمرة واحدة (استثمار أولي)"), style_h2_ar))

    dev_data = [
        [ar("البند"), ar("التكلفة (ج.م)")],
        [ar("تطوير تطبيق المستخدم"), "15,000"],
        [ar("تطوير تطبيق الكابتن"), "15,000"],
        [ar("تطوير لوحة التحكم الإدارية"), "10,000"],
        [ar("تطوير واجهة البرمجة (API)"), "10,000"],
        [ar("التصميم وتجربة المستخدم (UX/UI)"), "10,000"],
        [ar("الإجمالي"), "60,000"],
    ]
    dev_table = Table(dev_data, colWidths=[120*mm, 50*mm])
    dev_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arabic-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("FONTNAME", (0, 1), (-1, -1), "Arabic"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [white, TABLE_ROW_ALT]),
        ("BACKGROUND", (0, -1), (-1, -1), HexColor("#dbeafe")),
        ("FONTNAME", (0, -1), (-1, -1), "Arabic-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(dev_table)
    story.append(Spacer(1, 10))
    story.append(Paragraph(ar("ملاحظة: هذه التكلفة تشمل التطوير الكامل لجميع المكونات الثلاثة (تطبيقين + لوحة تحكم) جاهزة للنشر."), style_note_ar))

    # ==========================
    # Page: Annual Fixed Costs
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph(ar("التكاليف السنوية الثابتة"), style_h1_ar))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))

    story.append(Paragraph(ar("1) الدومين وتحسين محركات البحث (SEO)"), style_h2_ar))
    story.append(Paragraph(ar("التكلفة: 5,000 ج.م سنوياً"), style_body_ar))
    story.append(Spacer(1, 5))
    story.append(Paragraph(ar("يشمل هذا البند ما يلي:"), style_body_ar))

    seo_items = [
        "تسجيل اسم النطاق (Domain) وتجديده سنوياً",
        "إدارة نظام أسماء الخوادم (DNS) لضمان استقرار الوصول",
        "تحسين عناوين الصفحات والوصف (Meta Tags) لظهور أفضل في البحث",
        "تحسين سرعة تحميل الصفحات لتحقيق تجربة مستخدم سلسة",
        "إضافة بيانات منظمة (Structured Data) لتوضيح محتوى الموقع لمحركات البحث",
        "إنشاء وتحديث خريطة الموقع (Sitemap) وتقديمها لمحركات البحث",
        "تحليل الكلمات المفتاحية وتحسين المحتوى بناءً عليها",
        "متابعة أداء الظهور في نتائج البحث وتحسينه بشكل مستمر",
    ]
    for item in seo_items:
        story.append(Paragraph(f"• {ar(item)}", style_bullet_ar))

    story.append(Spacer(1, 15))
    story.append(Paragraph(ar("2) الرسوم التشغيلية الثابتة"), style_h2_ar))
    story.append(Paragraph(ar("التكلفة: 1,000 ج.م شهرياً (12,000 ج.م سنوياً)"), style_body_ar))
    story.append(Paragraph(ar("تشمل المصاريف الإدارية الثابتة (مرافق، صيانة، تحديثات دورية، دعم فني أساسي)."), style_body_ar))

    story.append(Spacer(1, 15))

    # Summary table
    annual_data = [
        [ar("البند"), ar("التكلفة السنوية (ج.م)")],
        [ar("الدومين + SEO"), "5,000"],
        [ar("الرسوم التشغيلية الثابتة (1,000 × 12)"), "12,000"],
        [ar("الإجمالي السنوي الثابت"), "17,000"],
    ]
    annual_table = Table(annual_data, colWidths=[120*mm, 50*mm])
    annual_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arabic-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("FONTNAME", (0, 1), (-1, -1), "Arabic"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [white, TABLE_ROW_ALT]),
        ("BACKGROUND", (0, -1), (-1, -1), HexColor("#dbeafe")),
        ("FONTNAME", (0, -1), (-1, -1), "Arabic-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(annual_table)

    # ==========================
    # Page: Monthly Operating Costs
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph(ar("التكاليف التشغيلية الشهرية (المتغيرة)"), style_h1_ar))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))
    story.append(Paragraph(ar("تتغير التكاليف الشهرية حسب حجم الاستخدام وعدد الرحلات اليومية."), style_body_ar))
    story.append(Spacer(1, 10))

    monthly_data = [
        [ar("المرحلة"), ar("رحلات/يوم"), ar("البنية السحابية"), ar("الرسوم الثابتة"), ar("الإجمالي الشهري")],
        [ar("التجربة"), "< 50", "250 - 1,000", "1,000", "1,250 - 2,000"],
        [ar("الإطلاق"), "100 - 250", "1,500 - 3,500", "1,000", "2,500 - 4,500"],
        [ar("النمو"), "500 - 1,000", "5,000 - 10,000", "1,000", "6,000 - 11,000"],
        [ar("التوسع"), "2,000+", "15,000 - 40,000", "1,000", "16,000 - 41,000"],
    ]
    monthly_table = Table(monthly_data, colWidths=[30*mm, 28*mm, 40*mm, 32*mm, 40*mm])
    monthly_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arabic-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("FONTNAME", (0, 1), (-1, -1), "Arabic"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [white, TABLE_ROW_ALT]),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(monthly_table)
    story.append(Spacer(1, 10))
    story.append(Paragraph(ar("جميع المبالغ بالجنيه المصري. تشمل البنية السحابية: الخوادم، قواعد البيانات، التخزين، الخرائط، والإشعارات."), style_note_ar))

    # ==========================
    # Page: Feasibility Study
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph(ar("دراسة الجدوى الاقتصادية"), style_h1_ar))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))

    story.append(Paragraph(ar("الاستثمار الأولي"), style_h2_ar))
    story.append(Paragraph(ar("65,000 ج.م (60,000 تطوير + 5,000 دومين و SEO)"), style_body_ar))

    story.append(Spacer(1, 15))
    story.append(Paragraph(ar("الإيرادات المتوقعة (عمولة المنصة 20%)"), style_h2_ar))

    feasibility_data = [
        [ar("الفترة"), ar("رحلات/يوم"), ar("متوسط الأجرة"), ar("القيمة الشهرية"), ar("العمولة 20%"), ar("التكاليف"), ar("الصافي")],
        [ar("شهر 1-3"), "50", "30", "45,000", "9,000", "2,000", "7,000"],
        [ar("شهر 4-6"), "200", "30", "180,000", "36,000", "4,500", "31,500"],
        [ar("شهر 7-12"), "500", "35", "525,000", "105,000", "11,000", "94,000"],
        [ar("شهر 12+"), "1,000+", "35", "1,050,000+", "210,000+", "21,000", "189,000+"],
    ]
    feasibility_table = Table(feasibility_data, colWidths=[22*mm, 22*mm, 22*mm, 28*mm, 25*mm, 22*mm, 25*mm])
    feasibility_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arabic-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("FONTNAME", (0, 1), (-1, -1), "Arabic"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [white, TABLE_ROW_ALT]),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    story.append(feasibility_table)

    story.append(Spacer(1, 15))
    story.append(Paragraph(ar("نقطة التعادل"), style_h2_ar))
    story.append(Paragraph(ar("نقطة التعادل المتوقعة: الشهر الخامس تقريباً، عند الوصول إلى 200 رحلة يومية. بعد هذا الحد، تغطي الإيرادات التكاليف التشغيلية وتحقق ربحاً صافياً متنامياً."), style_body_ar))

    # ==========================
    # Page: Timeline
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph(ar("الجدول الزمني للتنفيذ"), style_h1_ar))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))

    timeline_data = [
        [ar("المرحلة"), ar("المدة"), ar("المحتوى")],
        [ar("1. الأساس"), ar("أسبوعان"), ar("تطوير الواجهة البرمجية + المصادقة + قاعدة البيانات")],
        [ar("2. التتبع اللحظي"), ar("أسبوعان"), ar("نظام التتبع المباشر + المطابقة الذكية")],
        [ar("3. تطبيقات الجوال"), ar("ثلاثة أسابيع"), ar("تطوير تطبيق المستخدم وتطبيق الكابتن")],
        [ar("4. لوحة التحكم"), ar("أسبوعان"), ar("تطوير لوحة التحكم الإدارية الكاملة")],
        [ar("5. التكامل والاختبار"), ar("أسبوعان"), ar("اختبار شامل + إصلاحات + تحسينات")],
        [ar("6. الإطلاق"), ar("أسبوع"), ar("النشر + متاجر التطبيقات")],
        [ar("الإجمالي"), ar("~12 أسبوع"), ar("مشروع كامل جاهز للتشغيل")],
    ]
    timeline_table = Table(timeline_data, colWidths=[35*mm, 30*mm, 105*mm])
    timeline_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arabic-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("FONTNAME", (0, 1), (-1, -1), "Arabic"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [white, TABLE_ROW_ALT]),
        ("BACKGROUND", (0, -1), (-1, -1), HexColor("#dbeafe")),
        ("FONTNAME", (0, -1), (-1, -1), "Arabic-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(timeline_table)

    # ==========================
    # Page: Domain & SEO Details
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph(ar("شرح الدومين وتحسين محركات البحث (SEO)"), style_h1_ar))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 15))

    story.append(Paragraph(ar("الدومين (Domain)"), style_h2_ar))
    story.append(Paragraph(ar("الدومين هو عنوان الموقع الإلكتروني الذي يكتبه المستخدمون للوصول إلى المنصة. يشمل تسجيل الاسم السنوي وإدارة نظام أسماء الخوادم (DNS) لضمان وصول مستقر وسريع للمستخدمين."), style_body_ar))

    story.append(Spacer(1, 15))
    story.append(Paragraph(ar("تحسين محركات البحث (SEO)"), style_h2_ar))
    story.append(Paragraph(ar("تهدف عملية تحسين محركات البحث إلى رفع ظهور المنصة في نتائج البحث على Google وغيرها، مما يزيد من عدد الزيارات العضوية (المجانية) ويقلل من تكلفة التسويق المدفوع."), style_body_ar))
    story.append(Spacer(1, 10))

    seo_details = [
        "تحسين العناوين والأوصاف (Meta Tags): كتابة عناوين جذابة تصف الخدمة بوضوح لمحركات البحث",
        "تحسين سرعة التحميل: الصفحات السريعة تحصل على ترتيب أفضل وتجربة مستخدم أفضل",
        "البيانات المنظمة (Structured Data): إضافة أكواد توضح لمحركات البحث نوع المحتوى والخدمات",
        "خريطة الموقع (Sitemap): إنشاء وتحديث خريطة تساعد محركات البحث على فهرسة كل الصفحات",
        "تحليل الكلمات المفتاحية: تحديد الكلمات التي يبحث عنها العملاء وتحسين المحتوى لها",
        "متابعة الأداء: تحليل ترتيب الموقع في نتائج البحث وتحسينه بشكل دوري ومستمر",
    ]
    for item in seo_details:
        story.append(Paragraph(f"• {ar(item)}", style_bullet_ar))

    story.append(Spacer(1, 15))
    story.append(Paragraph(ar("التكلفة الإجمالية للدومين و SEO: 5,000 ج.م سنوياً"), style_h2_ar))


def build_english_section(story):
    """Build all English content pages."""
    # ==========================
    # Features
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph("Complete Features", style_h1_en))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 15))

    story.append(Paragraph("1. Admin Dashboard", style_h2_en))
    admin_features_en = [
        "Secure authentication system (OTP + JWT) with full protection",
        "Main dashboard displaying live KPIs and instant metrics",
        "Interactive map for real-time monitoring of trips and captains",
        "Full captain management: approval, suspension, search, status filtering",
        "Trip management: comprehensive table with filtering by status and city",
        "User management (riders and captains)",
        "Flexible pricing system editable per city",
        "Advanced analytics: revenue, completion rate, top captains, charts",
        "Complete audit log for all administrative actions",
        "Promo and discount code management",
        "Document review and approval for captain verification",
    ]
    for feat in admin_features_en:
        story.append(Paragraph(f"• {feat}", style_bullet_en))

    story.append(Spacer(1, 15))
    story.append(Paragraph("2. Rider App", style_h2_en))
    rider_features_en = [
        "Secure registration and login via OTP verification",
        "Automatic location detection via GPS",
        "Select pickup and dropoff points on the map",
        "Fare estimation before requesting a ride",
        "One-tap ride request",
        "Live captain tracking on the map (real-time)",
        "Trip cancellation with reason selection",
        "Captain rating after trip completion",
        "Complete history of past trips",
        "Saved favorite places (Home, Work)",
        "Ride type selection (Economy, Comfort, XL)",
        "Discount and promo code support",
    ]
    for feat in rider_features_en:
        story.append(Paragraph(f"• {feat}", style_bullet_en))

    story.append(Spacer(1, 15))
    story.append(Paragraph("3. Captain App", style_h2_en))
    captain_features_en = [
        "Secure registration and login via OTP",
        "Vehicle details entry and document upload",
        "Availability toggle (Online / Offline)",
        "Instant ride request notifications (real-time push)",
        "Quick accept or reject requests",
        "Live location streaming during trips",
        "Trip status management (En route → Arrived → Started → Completed)",
        "Daily, weekly, and monthly earnings reports",
        "Rider rating after each trip",
        "Navigation via map apps to pickup point",
    ]
    for feat in captain_features_en:
        story.append(Paragraph(f"• {feat}", style_bullet_en))

    # ==========================
    # Development Costs
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph("Total Development & Design Cost", style_h1_en))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))
    story.append(Paragraph("One-time cost (initial investment)", style_h2_en))

    dev_data_en = [
        ["Item", "Cost (EGP)"],
        ["Rider App Development", "15,000"],
        ["Captain App Development", "15,000"],
        ["Admin Dashboard Development", "10,000"],
        ["API / Backend Development", "10,000"],
        ["Design & UX/UI", "10,000"],
        ["Total", "60,000"],
    ]
    dev_table_en = Table(dev_data_en, colWidths=[120*mm, 50*mm])
    dev_table_en.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arial-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("FONTNAME", (0, 1), (-1, -1), "Arial"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [white, TABLE_ROW_ALT]),
        ("BACKGROUND", (0, -1), (-1, -1), HexColor("#dbeafe")),
        ("FONTNAME", (0, -1), (-1, -1), "Arial-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(dev_table_en)
    story.append(Spacer(1, 10))
    story.append(Paragraph("Note: This cost includes full development of all three components (two apps + dashboard) ready for deployment.", style_note_en))

    # ==========================
    # Annual Fixed Costs
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph("Annual Fixed Costs", style_h1_en))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))

    story.append(Paragraph("1) Domain & Search Engine Optimization (SEO)", style_h2_en))
    story.append(Paragraph("Cost: 5,000 EGP annually", style_body_en))
    story.append(Spacer(1, 5))
    story.append(Paragraph("This item includes the following:", style_body_en))

    seo_items_en = [
        "Domain name registration and annual renewal",
        "DNS management to ensure stable and fast access",
        "Meta tags optimization for better search visibility",
        "Page load speed optimization for smooth user experience",
        "Structured data implementation for search engine clarity",
        "Sitemap creation and submission to search engines",
        "Keyword analysis and content optimization",
        "Continuous search ranking monitoring and improvement",
    ]
    for item in seo_items_en:
        story.append(Paragraph(f"• {item}", style_bullet_en))

    story.append(Spacer(1, 15))
    story.append(Paragraph("2) Fixed Operating Fees", style_h2_en))
    story.append(Paragraph("Cost: 1,000 EGP monthly (12,000 EGP annually)", style_body_en))
    story.append(Paragraph("Includes fixed administrative expenses (utilities, maintenance, periodic updates, basic technical support).", style_body_en))

    story.append(Spacer(1, 15))

    annual_data_en = [
        ["Item", "Annual Cost (EGP)"],
        ["Domain + SEO", "5,000"],
        ["Fixed Operating Fees (1,000 x 12)", "12,000"],
        ["Total Annual Fixed", "17,000"],
    ]
    annual_table_en = Table(annual_data_en, colWidths=[120*mm, 50*mm])
    annual_table_en.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arial-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 11),
        ("FONTNAME", (0, 1), (-1, -1), "Arial"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [white, TABLE_ROW_ALT]),
        ("BACKGROUND", (0, -1), (-1, -1), HexColor("#dbeafe")),
        ("FONTNAME", (0, -1), (-1, -1), "Arial-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(annual_table_en)

    # ==========================
    # Monthly Operating Costs
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph("Monthly Operating Costs (Variable)", style_h1_en))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))
    story.append(Paragraph("Monthly costs vary based on usage volume and daily trips.", style_body_en))
    story.append(Spacer(1, 10))

    monthly_data_en = [
        ["Stage", "Trips/Day", "Cloud Infra", "Fixed Fees", "Monthly Total"],
        ["Trial", "< 50", "250 - 1,000", "1,000", "1,250 - 2,000"],
        ["Launch", "100 - 250", "1,500 - 3,500", "1,000", "2,500 - 4,500"],
        ["Growth", "500 - 1,000", "5,000 - 10,000", "1,000", "6,000 - 11,000"],
        ["Scale", "2,000+", "15,000 - 40,000", "1,000", "16,000 - 41,000"],
    ]
    monthly_table_en = Table(monthly_data_en, colWidths=[30*mm, 28*mm, 40*mm, 32*mm, 40*mm])
    monthly_table_en.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arial-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("FONTNAME", (0, 1), (-1, -1), "Arial"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [white, TABLE_ROW_ALT]),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(monthly_table_en)
    story.append(Spacer(1, 10))
    story.append(Paragraph("All amounts in Egyptian Pounds (EGP). Cloud infrastructure includes: servers, databases, storage, maps, and notifications.", style_note_en))

    # ==========================
    # Feasibility Study
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph("Feasibility Study", style_h1_en))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))

    story.append(Paragraph("Initial Investment", style_h2_en))
    story.append(Paragraph("65,000 EGP (60,000 development + 5,000 domain & SEO)", style_body_en))

    story.append(Spacer(1, 15))
    story.append(Paragraph("Projected Revenue (20% Platform Commission)", style_h2_en))

    feasibility_data_en = [
        ["Period", "Trips/Day", "Avg Fare", "Monthly Value", "Commission 20%", "Costs", "Net Profit"],
        ["Month 1-3", "50", "30", "45,000", "9,000", "2,000", "7,000"],
        ["Month 4-6", "200", "30", "180,000", "36,000", "4,500", "31,500"],
        ["Month 7-12", "500", "35", "525,000", "105,000", "11,000", "94,000"],
        ["Month 12+", "1,000+", "35", "1,050,000+", "210,000+", "21,000", "189,000+"],
    ]
    feasibility_table_en = Table(feasibility_data_en, colWidths=[22*mm, 22*mm, 22*mm, 28*mm, 25*mm, 22*mm, 25*mm])
    feasibility_table_en.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arial-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("FONTNAME", (0, 1), (-1, -1), "Arial"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [white, TABLE_ROW_ALT]),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 7),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
    ]))
    story.append(feasibility_table_en)

    story.append(Spacer(1, 15))
    story.append(Paragraph("Break-even Point", style_h2_en))
    story.append(Paragraph("Expected break-even: approximately month 5, upon reaching 200 daily trips. Beyond this point, revenue covers operating costs and generates growing net profit.", style_body_en))

    # ==========================
    # Timeline
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph("Project Timeline", style_h1_en))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 10))

    timeline_data_en = [
        ["Phase", "Duration", "Content"],
        ["1. Foundation", "2 weeks", "API development + Authentication + Database"],
        ["2. Realtime", "2 weeks", "Live tracking system + Smart matching"],
        ["3. Mobile Apps", "3 weeks", "Rider app + Captain app development"],
        ["4. Dashboard", "2 weeks", "Full admin dashboard development"],
        ["5. Integration & Testing", "2 weeks", "Comprehensive testing + fixes + optimization"],
        ["6. Launch", "1 week", "Deployment + App stores"],
        ["Total", "~12 weeks", "Complete project ready for operation"],
    ]
    timeline_table_en = Table(timeline_data_en, colWidths=[35*mm, 30*mm, 105*mm])
    timeline_table_en.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), TABLE_HEADER),
        ("TEXTCOLOR", (0, 0), (-1, 0), white),
        ("FONTNAME", (0, 0), (-1, 0), "Arial-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("FONTNAME", (0, 1), (-1, -1), "Arial"),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -2), [white, TABLE_ROW_ALT]),
        ("BACKGROUND", (0, -1), (-1, -1), HexColor("#dbeafe")),
        ("FONTNAME", (0, -1), (-1, -1), "Arial-Bold"),
        ("GRID", (0, 0), (-1, -1), 0.5, BORDER_COLOR),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(timeline_table_en)

    # ==========================
    # Domain & SEO
    # ==========================
    story.append(PageBreak())
    story.append(Paragraph("Domain & SEO Explanation", style_h1_en))
    story.append(HorizontalLine(PAGE_WIDTH, PRIMARY, 2))
    story.append(Spacer(1, 15))

    story.append(Paragraph("Domain", style_h2_en))
    story.append(Paragraph("The domain is the web address that users type to access the platform. It includes annual name registration and DNS management to ensure stable and fast access for users.", style_body_en))

    story.append(Spacer(1, 15))
    story.append(Paragraph("Search Engine Optimization (SEO)", style_h2_en))
    story.append(Paragraph("SEO aims to increase the platform's visibility in search results on Google and other engines, increasing organic (free) traffic and reducing paid marketing costs.", style_body_en))
    story.append(Spacer(1, 10))

    seo_details_en = [
        "Meta tags optimization: writing compelling titles that clearly describe the service for search engines",
        "Load speed optimization: faster pages achieve better ranking and improved user experience",
        "Structured data: adding code that clarifies content type and services to search engines",
        "Sitemap: creating and updating a map that helps search engines index all pages",
        "Keyword analysis: identifying terms customers search for and optimizing content accordingly",
        "Performance monitoring: analyzing search ranking and improving it on an ongoing basis",
    ]
    for item in seo_details_en:
        story.append(Paragraph(f"• {item}", style_bullet_en))

    story.append(Spacer(1, 15))
    story.append(Paragraph("Total Domain & SEO Cost: 5,000 EGP annually", style_h2_en))


# ============================================================
# Build PDF
# ============================================================
def build_pdf(output_path):
    doc = SimpleDocTemplate(
        output_path,
        pagesize=A4,
        leftMargin=20*mm,
        rightMargin=20*mm,
        topMargin=20*mm,
        bottomMargin=20*mm,
        title="مشروع منصة شاملة لنقل الركاب",
        author="Synaptic Studio",
        subject="Comprehensive Ride-Hailing Platform Project",
        creator="Synaptic Go",
    )

    story = []

    # Cover page will be drawn by onFirstPage callback
    story.append(PageBreak())

    # Arabic section
    build_arabic_section(story)

    # English section
    build_english_section(story)

    doc.build(story, onFirstPage=draw_cover, onLaterPages=page_footer)
    print(f"PDF generated: {output_path}")
    print(f"File size: {os.path.getsize(output_path) / 1024:.1f} KB")


if __name__ == "__main__":
    output = os.path.join(os.path.expanduser("~"), "Desktop", "مشروع منصة شاملة لنقل الركاب.pdf")
    build_pdf(output)
