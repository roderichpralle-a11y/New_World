#!/usr/bin/env python3
"""Schubkarre fuer Siedler, die mit Handkarren (Forschung "handkarren") Waren transportieren.

Aufruf:  python3 tools/gen_art_cart.py
Ausgabe: assets/sprites/cart.png (eigene Datei, die anderen Atlanten bleiben unveraendert)

Zellen 24x24, 4 Spalten = Rad-Bilder (Rad dreht sich), Zeilen wie die Siedler-Richtungen
(Settler.DIR_DOWN=0, DIR_UP=1, DIR_SIDE=2; seitlich schaut nach rechts, links = gespiegelt):
  Zeile 0-2: ganze Karre (unten, oben, seitlich)
  Zeile 3-5: nur die vordere Wannenwand (wird ueber die geladene Ware gelegt, damit die Ware
             in der Wanne liegt; gleiche Pixel wie die ganze Karre)
Jede Richtung ist um einen eigenen Ankerpunkt gezeichnet (die Fuesse des Siedlers), siehe
ANCHOR; die Bildmitte (12, 12) liegt also bei Fuessen + (12, 12) - ANCHOR (Data.CART_POS).
"""
import math
import os

from gen_art import OUT, WOOD, IRON, OUTLINE, new, put, add_outline

CELL = 24
FRAMES = 4
# Ankerpunkt (Fuesse des Siedlers, Mitte zwischen Pixel -1 und 0) je Richtung in Zellkoordinaten
ANCHOR = {0: (12, 12), 1: (12, 32), 2: (2, 20)}
# Ab dieser lokalen Zeile (Fuesse = 0) gehoert alles zur Vorderwand (Zeilen 3-5)
FRONT_ROW = {0: -1, 1: -22, 2: -12}
TIRE = IRON[0]
SPOKE = IRON[2]
HUB = IRON[3]
RIM = IRON[2]
RIM_HI = IRON[3]


class Canvas:
    """Zeichnen in Siedler-Koordinaten: (0, 0) = Fuesse, y nach unten."""

    def __init__(self, d):
        self.img = new(CELL, CELL)
        self.ax, self.ay = ANCHOR[d]

    def p(self, x, y, c):
        put(self.img, x + self.ax, y + self.ay, c)

    def hline(self, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            self.p(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            self.p(x, y, c)


def side_wheel(cv, cx, cy, frame):
    """Eisenrad von der Seite, Radius 3, vier Speichen um frame * 22,5 Grad gedreht (im Uhrzeigersinn
    = rollt nach rechts)."""
    for y in range(-3, 4):
        for x in range(-3, 4):
            d = math.hypot(x, y)
            if 2.2 < d <= 3.4:
                # Lauffläche: oben heller (Licht von oben)
                cv.p(cx + x, cy + y, IRON[1] if y < -1 else TIRE)
    a0 = math.radians(frame * 22.5)
    for k in range(4):
        a = a0 + k * math.pi / 2
        for t in (1.0, 1.9):
            cv.p(cx + round(math.cos(a) * t), cy + round(math.sin(a) * t), SPOKE)
    cv.p(cx, cy, HUB)


def draw_side(frame):
    cv = Canvas(2)
    # Holm: vom Griff (Hand des Siedlers bei x -1..0, y -7) schraeg hinunter zur Achse
    gx, gy, ax, ay = -1, -8, 16, -4
    for i in range(0, ax - gx + 1):
        x = gx + i
        y = gy + round(i * (ay - gy) / (ax - gx))
        cv.p(x, y, WOOD[2])
        cv.p(x, y + 1, WOOD[1])
    cv.p(-1, -8, WOOD[3])
    cv.p(0, -8, WOOD[3])
    # Stuetzbein hinten (beim Schieben in der Luft)
    cv.vline(6, -6, -2, WOOD[1])
    cv.p(6, -2, WOOD[0])
    # Wanne: Rueckwand fast senkrecht, Nase schraeg nach vorn ueber dem Rad
    for y in range(-11, -5):
        r = y + 11
        x0 = 3 + r // 2
        x1 = 18 - r
        for x in range(x0, x1 + 1):
            c = WOOD[2]
            if y == -11:
                c = WOOD[3]
            elif y == -8:
                c = WOOD[1]  # Fuge zwischen zwei Brettern
            elif y == -6:
                c = WOOD[1]
            if x == x0:
                c = IRON[1]  # Eisenband an der Rueckkante
            cv.p(x, y, c)
    # Eisenrand oben, vorn etwas ueberstehend
    cv.hline(3, 19, -12, RIM)
    for x in (5, 10, 15):
        cv.p(x, -12, RIM_HI)
    cv.p(19, -11, RIM)
    # Nieten
    cv.p(8, -10, IRON[3])
    cv.p(13, -10, IRON[3])
    # Rad vor der Holmspitze
    side_wheel(cv, 16, -4, frame)
    return cv


def front_wheel(cv, y0, h, frame, down=True):
    """Rad von vorn/hinten (Spalten -2..1, Mitte wie der Siedler zwischen -1 und 0), oben und unten
    abgerundet. Das Profil in der Mitte wandert mit dem Rollen (nach unten = auf uns zu)."""
    for y in range(h):
        end = y in (0, h - 1)
        for x in (-2, -1, 0, 1):
            side = x in (-2, 1)
            if side and end:
                continue
            if side:
                c = TIRE
            else:
                ph = (y - frame) % 4 if down else (y + frame) % 4
                c = IRON[3] if ph == 0 else (IRON[1] if ph == 2 else IRON[2] if ph == 1 else TIRE)
                if x == 0 and c == IRON[3]:
                    c = IRON[2]
            cv.p(x, y0 + y, c)


def draw_down(frame):
    """Karre vor dem Siedler, der nach unten (auf uns zu) geht: Rad vorn, Blick in die Wanne."""
    cv = Canvas(0)
    # Griffenden hinter der Wanne bei den Haenden
    for x in (-6, 5):
        cv.p(x, -8, WOOD[3])
        cv.p(x, -7, WOOD[2])
    # Rad unter der Wanne (oben von ihr verdeckt), Achsbolzen seitlich
    front_wheel(cv, 1, 8, frame, True)
    cv.p(-3, 5, IRON[2])
    cv.p(2, 5, IRON[2])
    # Hinterer Rand (fern)
    cv.hline(-6, 5, -6, RIM)
    cv.p(-3, -6, RIM_HI)
    cv.p(2, -6, RIM_HI)
    # Innenraum (dunkel), Seitenwaende innen etwas heller
    for y in range(-5, -1):
        cv.hline(-6, 5, y, WOOD[0])
        cv.p(-6, y, WOOD[1])
        cv.p(5, y, WOOD[1])
    # Vorderer Rand (nah, breiter)
    cv.hline(-7, 6, -1, RIM)
    for x in (-5, 0, 4):
        cv.p(x, -1, RIM_HI)
    # Vorderwand, nach unten schmaler
    rows = {0: (-7, 6), 1: (-6, 5), 2: (-5, 4)}
    for y, (x0, x1) in rows.items():
        for x in range(x0, x1 + 1):
            c = WOOD[2] if y != 1 else WOOD[1]
            if y == 0:
                c = WOOD[3]
            if x in (x0, x1):
                c = IRON[1]
            cv.p(x, y, c)
    return cv


def draw_up(frame):
    """Karre vor dem Siedler, der nach oben (von uns weg) geht: Wanne ueber dem Kopf, Holme an den
    Schultern vorbei zu den Haenden, das Rad schaut vorn (oben) ueber die Wanne."""
    cv = Canvas(1)
    front_wheel(cv, -31, 6, frame, False)
    # Ferner Rand (Nase), Innenraum, naher Rand
    cv.hline(-6, 5, -27, RIM)
    cv.p(-3, -27, RIM_HI)
    cv.p(2, -27, RIM_HI)
    for y in range(-26, -22):
        cv.hline(-6, 5, y, WOOD[0])
        cv.p(-6, y, WOOD[1])
        cv.p(5, y, WOOD[1])
    cv.hline(-7, 6, -22, RIM)
    for x in (-5, 0, 4):
        cv.p(x, -22, RIM_HI)
    # Rueckwand (zum Siedler), nach unten schmaler
    rows = {-21: (-7, 6), -20: (-6, 5), -19: (-5, 4)}
    for y, (x0, x1) in rows.items():
        for x in range(x0, x1 + 1):
            c = WOOD[2] if y != -20 else WOOD[1]
            if y == -21:
                c = WOOD[3]
            if x in (x0, x1):
                c = IRON[1]
            cv.p(x, y, c)
    # Holme unter der Wanne hervor hinunter zu den Haenden (seitlich am Kopf vorbei, an den
    # Schultern verdeckt)
    for x0, x1 in ((-5, -6), (4, 5)):
        cv.vline(x0, -18, -16, WOOD[2])
        cv.vline(x1, -15, -11, WOOD[2])
    return cv


# Schatten auf dem Boden (wie der Siedler-Schatten), nach der Kontur unter die Karre gelegt:
# Mitte x, y, Halbachsen; nach oben keiner (der Boden unter der Karre liegt hinter dem Siedler)
SHADOW = {0: (-0.5, 8.5, 6.5, 1.6), 2: (11.0, 0.5, 9.0, 1.6)}


def add_shadow(img, d):
    if d not in SHADOW:
        return img
    cx, cy, rx, ry = SHADOW[d]
    ax, ay = ANCHOR[d]
    out = new(CELL, CELL)
    for y in range(CELL):
        for x in range(CELL):
            dx = (x - ax + 0.5 - cx) / rx
            dy = (y - ay + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                out.putpixel((x, y), (20, 30, 40, 80))
    out.alpha_composite(img)
    return out


def front_part(img, d):
    """Vorderwand: alle Pixel ab FRONT_ROW (inklusive Kontur), damit sie nahtlos ueber der Ware liegt."""
    out = new(CELL, CELL)
    ay = ANCHOR[d][1]
    for y in range(max(0, FRONT_ROW[d] + ay), CELL):
        for x in range(CELL):
            px = img.getpixel((x, y))
            if px[3]:
                out.putpixel((x, y), px)
    return out


def gen_cart():
    sheet = new(CELL * FRAMES, CELL * 6)
    for d, fn in ((0, draw_down), (1, draw_up), (2, draw_side)):
        for f in range(FRAMES):
            img = add_outline(fn(f).img)
            sheet.paste(add_shadow(img, d), (f * CELL, d * CELL))
            sheet.paste(front_part(img, d), (f * CELL, (d + 3) * CELL))
    sheet.save(os.path.join(OUT, "cart.png"))
    return sheet


def preview(sheet, path):
    """Vergroesserte Vorschau zum Ansehen (nicht im Spiel benutzt)."""
    big = sheet.resize((sheet.width * 8, sheet.height * 8), 0)
    bg = new(big.width, big.height)
    bg.paste((120, 170, 90, 255), (0, 0, big.width, big.height))
    bg.alpha_composite(big)
    bg.save(path)


if __name__ == "__main__":
    import sys
    s = gen_cart()
    if len(sys.argv) > 1:
        preview(s, sys.argv[1])
    print("ok")
