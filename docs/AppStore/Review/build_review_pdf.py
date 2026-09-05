"""Render the review reference from its structured, secret-free source."""

import json
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path(__file__).with_name("supporting_information.json")
OUTPUT = Path(__file__).with_name("Attachments") / "BZOGAK-App-Review-Information.pdf"
DATA = json.loads(SOURCE.read_text(encoding="utf-8"))
FONT = ROOT / "Overline/Resources/Fonts/PretendardVariable.ttf"
pdfmetrics.registerFont(TTFont("Pretendard", str(FONT)))

INK = colors.HexColor("#303A3B")
MUTED = colors.HexColor("#637071")
ACCENT = colors.HexColor("#21686D")
LINE = colors.HexColor("#DDE4E4")
WIDTH, HEIGHT = A4
MARGIN = 44
CONTENT_WIDTH = WIDTH - MARGIN * 2

styles = {
    "title": ParagraphStyle(
        "Title", fontName="Pretendard", fontSize=23, leading=29,
        textColor=INK, spaceAfter=15,
    ),
    "heading": ParagraphStyle(
        "Heading", fontName="Pretendard", fontSize=12.2, leading=17,
        textColor=ACCENT, spaceBefore=11, spaceAfter=6, keepWithNext=True,
    ),
    "body": ParagraphStyle(
        "Body", fontName="Pretendard", fontSize=10.2, leading=14.3,
        textColor=INK, spaceAfter=7,
    ),
    "cell": ParagraphStyle(
        "Cell", fontName="Pretendard", fontSize=9.5, leading=12.7,
        textColor=INK,
    ),
    "label": ParagraphStyle(
        "Label", fontName="Pretendard", fontSize=9.5, leading=12.7,
        textColor=ACCENT,
    ),
    "sample": ParagraphStyle(
        "Sample", fontName="Pretendard", fontSize=13, leading=23,
        textColor=INK, spaceAfter=20, wordWrap="CJK",
    ),
}


def page_chrome(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(ACCENT)
    canvas.setFont("Pretendard", 9)
    canvas.drawString(MARGIN, HEIGHT - 31, "BZOGAK  /  APP REVIEW INFORMATION")
    canvas.setFillColor(MUTED)
    canvas.setFont("Pretendard", 8.2)
    canvas.drawString(MARGIN, 27, DATA["subtitle"])
    canvas.drawRightString(WIDTH - MARGIN, 27, str(doc.page))
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.5)
    canvas.line(MARGIN, HEIGHT - 43, WIDTH - MARGIN, HEIGHT - 43)
    canvas.restoreState()


story = []
for page_index, page in enumerate(DATA["pages"]):
    if page_index:
        story.append(PageBreak())
    story.append(Paragraph(page["title"], styles["title"]))
    for section in page["sections"]:
        if "heading" in section:
            story.append(Paragraph(section["heading"], styles["heading"]))
        for text in section.get("paragraphs", []):
            story.append(Paragraph(text, styles["body"]))
        if "rows" in section:
            rows = [
                [Paragraph(label, styles["label"]), Paragraph(body, styles["cell"])]
                for label, body in section["rows"]
            ]
            table = Table(rows, colWidths=[132, CONTENT_WIDTH - 132], hAlign="LEFT")
            table.setStyle(TableStyle([
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (0, -1), 0),
                ("LEFTPADDING", (1, 0), (1, -1), 11),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("LINEBELOW", (0, 0), (-1, -1), 0.4, LINE),
            ]))
            story.extend([table, Spacer(1, 6)])
        for text in section.get("sample", []):
            story.append(KeepTogether([
                Paragraph(text.replace("\n", "<br/>"), styles["sample"])
            ]))

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
document = SimpleDocTemplate(
    str(OUTPUT), pagesize=A4, leftMargin=MARGIN, rightMargin=MARGIN,
    topMargin=61, bottomMargin=48, title=DATA["title"],
    author=DATA["company"], subject="Guideline 2.1 supporting information",
    pageCompression=1,
)
document.build(story, onFirstPage=page_chrome, onLaterPages=page_chrome)
print(OUTPUT)
