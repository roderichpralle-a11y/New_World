#!/usr/bin/env python3
"""Berufskleidung der Siedler (josh 2026-10-20).

Aufruf aus gen_art.py (oder allein). Erzeugt Überlagerungen im Raster der Siedler-Bögen
(16x24 je Bild, Spalten = 4 Lauf-Bilder, Zeilen = unten, oben, seitlich), in festen Farben:
  settler_cap.png       gelbe Schirmmütze (Bauer, josh 2026-10-21)
  settler_chefhat.png   weiße Kochmütze (Koch)
  settler_hunthat.png   grüner Hut mit Feder (Jäger)
  settler_glasses.png   Brille (nicht mehr benutzt; Forscher tragen seit 2026-10-21 ein weißes Hemd)
  settler_apron.png     graue Schürze (Steinmetz)
  settler_rifle.png     Gewehr auf dem Rücken (Jäger)
  settler_saw.png       Motorsäge in der Hand (Förster)
Overall (Handwerker), braune Hose (Bauer) und weiße Hose (Koch) färbt das Spiel über Hemd und Hose
ein (Settler.OUTFIT). In den Bildern 1 und 3 wippt der Oberkörper 1 Pixel nach oben wie in walk_variant.
"""
import os
from gen_art import new, put, OUT, OUTLINE

BROWN = [(86, 56, 34), (120, 82, 50), (150, 108, 68)]
YELLOW = [(184, 140, 30), (228, 190, 52), (248, 222, 104)]
WHITE = [(176, 172, 168), (222, 220, 214), (250, 249, 244)]
GREEN = [(48, 78, 40), (70, 108, 54), (96, 138, 72)]
GREY = [(96, 96, 104), (128, 128, 136), (156, 156, 164)]
GLASS = (54, 46, 60)
WOODS = [(92, 58, 38), (128, 84, 52)]
STEEL = [(84, 88, 96), (150, 154, 162)]
ORANGE = [(196, 92, 30), (236, 134, 48)]
FEATHER = (196, 62, 48)


def cap(d):
    px = {}
    if d == "up":
        for x in range(5, 11):
            px[(x, 2)] = OUTLINE
        for y in (3, 4, 5):
            px[(4, y)] = OUTLINE
            px[(11, y)] = OUTLINE
            for x in range(5, 11):
                px[(x, y)] = YELLOW[1] if y < 5 else YELLOW[0]
        return px
    x0, x1 = (4, 11) if d == "down" else (4, 10)
    for x in range(x0 + 1, x1):
        px[(x, 2)] = OUTLINE
    for y in (3, 4, 5):
        px[(x0, y)] = OUTLINE
        px[(x1, y)] = OUTLINE
        for x in range(x0 + 1, x1):
            px[(x, y)] = YELLOW[2] if y == 3 and x < x0 + 3 else YELLOW[1]
    px[(x0 + 3, 4)] = YELLOW[0]  # Knopf/Naht
    if d == "down":
        for x in range(4, 12):
            px[(x, 6)] = YELLOW[0]  # Schirm nach vorn
        px[(3, 6)] = OUTLINE
        px[(12, 6)] = OUTLINE
    else:
        for x in range(10, 14):
            px[(x, 6)] = YELLOW[0]
        px[(14, 6)] = OUTLINE
    return px


def chefhat(d):
    px = {}
    x0, x1 = (4, 11)
    if d == "side":
        x0, x1 = (4, 10)
    # Puffige Krone
    for x in range(x0 + 1, x1):
        px[(x, 0)] = OUTLINE
    for y in range(1, 5):
        px[(x0, y)] = OUTLINE
        px[(x1, y)] = OUTLINE
        for x in range(x0 + 1, x1):
            px[(x, y)] = WHITE[2] if (x + y) % 3 else WHITE[1]
    px[(x0 + 2, 2)] = WHITE[1]
    # Band
    for x in range(x0, x1 + 1):
        px[(x, 5)] = WHITE[1] if x0 < x < x1 else OUTLINE
    for x in range(x0 + 1, x1):
        px[(x, 4)] = WHITE[2]
    return px


def hunthat(d):
    px = {}
    for x in range(6, 10):
        px[(x, 1)] = OUTLINE
    for y in (2, 3, 4):
        px[(5, y)] = OUTLINE
        px[(10, y)] = OUTLINE
        for x in range(6, 10):
            px[(x, y)] = GREEN[2] if y == 2 else GREEN[1]
    for x in range(6, 10):
        px[(x, 4)] = GREEN[0]  # Hutband
    for x in range(3, 13):
        px[(x, 5)] = GREEN[1]  # Krempe
    px[(2, 5)] = OUTLINE
    px[(13, 5)] = OUTLINE
    if d != "up":
        px[(10, 1)] = FEATHER
        px[(11, 0)] = FEATHER
    return px


def glasses(d):
    """Runde Brille: Rand oben und an den Seiten der Augen, Steg dazwischen; Augen bleiben frei."""
    px = {}
    if d == "down":
        for x in (5, 6, 7, 8, 9, 10):
            px[(x, 8)] = GLASS
        for x in (5, 7, 8, 10):
            px[(x, 9)] = GLASS
    elif d == "side":
        for x in (9, 10, 11):
            px[(x, 8)] = GLASS
        for x in (6, 7, 8, 9, 11):
            px[(x, 9)] = GLASS  # Bügel zum Ohr
    else:
        px[(4, 9)] = GLASS
        px[(11, 9)] = GLASS
    return px


def apron(d):
    px = {}
    if d == "down":
        px[(6, 12)] = GREY[0]
        px[(9, 12)] = GREY[0]
        for y in range(13, 20):
            for x in range(5, 11):
                px[(x, y)] = GREY[2] if x == 5 else GREY[1]
            px[(5, y)] = GREY[0] if y > 16 else GREY[1]
        for x in range(5, 11):
            px[(x, 16)] = GREY[0]  # Schnur
        px[(7, 18)] = GREY[0]
    elif d == "side":
        for y in range(13, 19):
            px[(10, y)] = GREY[1]
            px[(11, y)] = GREY[0] if y > 15 else GREY[1]
        px[(9, 12)] = GREY[0]
    else:
        px[(7, 15)] = GREY[0]
        px[(8, 15)] = GREY[0]
        px[(4, 15)] = GREY[1]
        px[(11, 15)] = GREY[1]
    return px


def rifle(d):
    """Gewehr auf dem Rücken: Lauf ragt über die Schulter, Kolben unten an der Hüfte."""
    px = {}
    if d == "down":
        for y in range(4, 9):
            px[(2, y)] = STEEL[1]
            px[(1, y)] = OUTLINE
        px[(2, 3)] = OUTLINE
        px[(3, 9)] = STEEL[0]
        for (x, y) in [(12, 16), (13, 17), (13, 18)]:
            px[(x, y)] = WOODS[1]
        px[(14, 18)] = OUTLINE
        px[(14, 17)] = OUTLINE
    elif d == "up":
        # Quer über den Rücken
        pts = [(2, 6), (3, 7), (3, 8), (4, 9), (5, 10), (6, 11), (7, 12), (8, 13), (9, 14), (10, 15), (11, 16), (12, 17)]
        for i, (x, y) in enumerate(pts):
            px[(x, y)] = STEEL[1] if i < 6 else WOODS[1] if i < 10 else WOODS[0]
        px[(11, 17)] = WOODS[0]
        px[(1, 6)] = OUTLINE
    else:
        for y in range(4, 10):
            px[(3, y)] = STEEL[1]
            px[(2, y)] = OUTLINE
        px[(3, 3)] = OUTLINE
        for y in range(10, 17):
            px[(3, y)] = WOODS[1] if y < 15 else WOODS[0]
            px[(2, y)] = OUTLINE
        px[(3, 17)] = OUTLINE
    return px


def saw(d):
    px = {}
    if d == "down":
        bx, by = 12, 14
    elif d == "side":
        bx, by = 9, 14
    else:
        return px  # von hinten verdeckt
    for y in range(by, by + 3):
        for x in range(bx, bx + 3):
            px[(x, y)] = ORANGE[1] if y == by else ORANGE[0]
    px[(bx + 1, by - 1)] = OUTLINE  # Griff
    if d == "down":
        for y in range(by + 3, by + 7):
            px[(bx + 1, y)] = STEEL[1]
            px[(bx + 2, y)] = STEEL[0]
    else:
        for x in range(bx + 3, bx + 7):
            px[(x, by + 1)] = STEEL[1]
            px[(x, by + 2)] = STEEL[0]
    return px


OUTFITS = {"cap": cap, "chefhat": chefhat, "hunthat": hunthat, "glasses": glasses,
           "apron": apron, "rifle": rifle, "saw": saw}


def gen_outfits():
    for name, fn in OUTFITS.items():
        sheet = new(64, 72)
        for di, d in enumerate(("down", "up", "side")):
            px = fn(d)
            for f in range(4):
                bob = 1 if f in (1, 3) else 0
                for (x, y), c in px.items():
                    yy = y - bob if y < 18 else y
                    if 0 <= x < 16 and 0 <= yy < 24:
                        c4 = c if len(c) == 4 else (c[0], c[1], c[2], 255)
                        sheet.putpixel((f * 16 + x, di * 24 + yy), c4)
        sheet.save(os.path.join(OUT, f"settler_{name}.png"))


if __name__ == "__main__":
    gen_outfits()
