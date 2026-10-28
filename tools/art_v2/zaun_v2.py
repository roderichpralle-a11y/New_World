"""Zaun für Version 2 (josh 2026-10-28 „Zeichne den Zaun neu“): Pfosten und zwei Querlatten im Maßstab der
neuen Figuren (Zaun etwa hüfthoch, 11 von 21 Spielpixeln). 16 Kacheln nach Nachbarmaske N=1, O=2, S=4, W=8,
gezeichnet in halben Spielpixeln (32 x 32 je Kachel), 4-fach (HD) ausgegeben.
Aufruf: python3 zaun_v2.py <ausgabe.png>  (Streifen 16 Kacheln breit)"""
from PIL import Image, ImageDraw
import sys

H = 32
OUT_ = (58, 36, 22, 255)
DARK = (104, 66, 38, 255)
MID = (146, 98, 56, 255)
LIGHT = (180, 128, 76, 255)
HI = (210, 162, 102, 255)
SHADOW = (0, 0, 0, 56)
CX = 16          # Pfostenmitte
FOOT = 27        # Fußpunkt des Pfostens
TOP = 9          # Oberkante des Pfostens
RAILS = (13, 20)  # Oberkante der beiden Latten


def rail_h(d, x0, x1, y):
    d.rectangle((x0, y - 1, x1, y + 3), fill=OUT_)
    d.rectangle((x0, y, x1, y + 2), fill=MID)
    d.line((x0, y, x1, y), fill=LIGHT)
    for x in range(x0 + 3, x1, 7):
        d.point((x, y + 1), fill=DARK)


def tile(m):
    img = Image.new("RGBA", (H, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Schatten am Boden
    if m & 2:
        d.rectangle((CX, FOOT - 1, H - 1, FOOT + 1), fill=SHADOW)
    if m & 8:
        d.rectangle((0, FOOT - 1, CX, FOOT + 1), fill=SHADOW)
    d.ellipse((CX - 5, FOOT - 2, CX + 5, FOOT + 2), fill=SHADOW)
    # Latten nach Norden und Süden: von oben gesehen ein schmaler Balken über dem Boden
    for bit, y0, y1 in ((1, -2, TOP + 2), (4, FOOT - 4, H + 12)):
        if m & bit:
            for ry in RAILS[:1]:
                pass
            d.rectangle((CX - 2, y0, CX + 2, y1), fill=OUT_)
            d.rectangle((CX - 1, y0, CX + 1, y1), fill=MID)
            d.line((CX - 1, y0, CX - 1, y1), fill=LIGHT)
    # Latten nach Osten und Westen hinter dem Pfosten
    for ry in RAILS:
        if m & 8:
            rail_h(d, 0, CX, ry)
        if m & 2:
            rail_h(d, CX, H - 1, ry)
    # Pfosten
    d.rectangle((CX - 3, TOP, CX + 3, FOOT), fill=OUT_)
    d.rectangle((CX - 2, TOP + 1, CX + 2, FOOT - 1), fill=MID)
    d.line((CX - 2, TOP + 1, CX - 2, FOOT - 1), fill=LIGHT)
    d.line((CX + 2, TOP + 1, CX + 2, FOOT - 1), fill=DARK)
    d.rectangle((CX - 2, TOP, CX + 2, TOP + 1), fill=HI)  # Hirnholz oben
    d.point((CX, TOP + 1), fill=LIGHT)
    for y in (TOP + 6, TOP + 12):
        d.point((CX, y), fill=DARK)
    return img


def strip():
    out = Image.new("RGBA", (16 * H * 2, H * 2), (0, 0, 0, 0))
    for m in range(16):
        out.paste(tile(m).resize((H * 2, H * 2), Image.NEAREST), (m * H * 2, 0))
    return out


if __name__ == "__main__":
    strip().save(sys.argv[1])
