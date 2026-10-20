#!/usr/bin/env python3
"""Grafiken fuer Strassen, Deiche und den Foerster (josh 2026-10-11).

Aufruf:  python3 tools/gen_art_land.py   (auch aus gen_art.py)
Ausgabe: assets/sprites/objects3.png, Regionen in Data.OBJECT3_REGIONS:
  Zeile y=0:  road0..road15  Strassenkacheln 16x16, Maske N=1 O=2 S=4 W=8 (Nachbar ist auch Strasse)
  Zeile y=16: dike0..dike15  Deichkacheln 16x16, Maske wie oben (Nachbar ist Deich oder Land)
  Zeile y=32: plant_mark (Pflanzloch mit Pflock), clear_mark (rot-weisses Band: wird gerodet)
  Zeile y=48: fence0..fence15 Holzzaun 16x16, Maske wie oben (Nachbar ist auch Zaun; josh 2026-10-20)
Die Kachel liegt mittig auf der Zelle (Bodengebaeude, siehe Building.refresh).
"""
import os
import random

from gen_art import (OUT, OUTLINE, STONE, SOIL, GRASS, WOOD, LEAF, SAND, new, put, add_outline, blob)

N, E, S, W = 1, 2, 4, 8
COBBLE = [(96, 88, 92), (128, 120, 118), (156, 148, 140), (186, 178, 166), (212, 204, 190)]
GRIT = (118, 104, 86)


def _inside(mask, x, y, half):
    """Liegt (x,y) auf dem Band: Mitte plus Arme zu den Nachbarn mit gesetztem Bit."""
    lo, hi = 8 - half, 7 + half
    if lo <= x <= hi and lo <= y <= hi:
        return True
    if mask & N and lo <= x <= hi and y < lo:
        return True
    if mask & S and lo <= x <= hi and y > hi:
        return True
    if mask & W and lo <= y <= hi and x < lo:
        return True
    if mask & E and lo <= y <= hi and x > hi:
        return True
    return False


def road(mask):
    """Gepflasterter Weg: Kies als Bett, darauf runde Pflastersteine in versetzten Reihen."""
    img = new(16, 16)
    rnd = random.Random(400 + mask)
    half = 5
    for y in range(16):
        for x in range(16):
            if not _inside(mask, x, y, half):
                continue
            # Rand des Bandes: dunklerer Kies (Bordstein)
            edge = not (_inside(mask, x - 1, y, half) and _inside(mask, x + 1, y, half)
                        and _inside(mask, x, y - 1, half) and _inside(mask, x, y + 1, half))
            if edge:
                put(img, x, y, COBBLE[0] if (x + y) % 3 else GRIT)
                continue
            # Pflaster: Steine 3x2 mit Fugen, jede zweite Reihe versetzt
            row = y // 2
            off = 1 if row % 2 else 0
            fx = (x + off) % 3 == 0
            fy = y % 2 == 0
            if fx or fy:
                c = COBBLE[1]
            else:
                c = COBBLE[3] if (x + y + rnd.randint(0, 1)) % 4 else COBBLE[4]
                if rnd.random() < 0.12:
                    c = COBBLE[2]
            put(img, x, y, c)
    # Ohne Nachbarn: Ecken abrunden
    for (x, y) in [(3, 3), (12, 3), (3, 12), (12, 12)]:
        if img.getpixel((x, y))[3] and _corner_free(mask, x, y):
            put(img, x, y, (0, 0, 0, 0))
    return img


def _corner_free(mask, x, y):
    if x < 8 and y < 8:
        return not (mask & N) and not (mask & W)
    if x >= 8 and y < 8:
        return not (mask & N) and not (mask & E)
    if x < 8 and y >= 8:
        return not (mask & S) and not (mask & W)
    return not (mask & S) and not (mask & E)


def dike(mask):
    """Deich: begruente Krone in der Mitte, zu den Seiten Boeschung aus Erde und Steinpackung."""
    img = new(16, 16)
    rnd = random.Random(700 + mask)
    half = 7
    for y in range(16):
        for x in range(16):
            if not _inside(mask, x, y, half):
                continue
            # Abstand zum Rand des Bandes (Krone innen, Steinpackung aussen)
            d = 9
            for k in range(1, 5):
                if not (_inside(mask, x - k, y, half) and _inside(mask, x + k, y, half)
                        and _inside(mask, x, y - k, half) and _inside(mask, x, y + k, half)):
                    d = k
                    break
            if d <= 1:
                c = STONE[0] if (x * 3 + y) % 3 else STONE[1]
            elif d == 2:
                c = STONE[2] if (x + 2 * y + rnd.randint(0, 2)) % 3 else STONE[3]
            elif d == 3:
                c = SOIL[1] if (x + y) % 3 else SOIL[0]
            elif d == 4:
                c = SOIL[2] if (x * 5 + y) % 4 else GRASS[1]
            else:
                c = GRASS[2] if (x * 7 + y * 5 + rnd.randint(0, 3)) % 6 else GRASS[3]
            put(img, x, y, c)
    # Kronenweg: schmaler Trampelpfad in Laengsrichtung
    if mask & (N | S) and not mask & (E | W):
        for y in range(16):
            if img.getpixel((8, y))[3]:
                put(img, 8, y, SAND[0] if y % 3 else SOIL[2])
    elif mask & (E | W) and not mask & (N | S):
        for x in range(16):
            if img.getpixel((x, 8))[3]:
                put(img, x, 8, SAND[0] if x % 3 else SOIL[2])
    return img


def plant_mark():
    """Pflanzstelle: kleiner Erdring mit dunklem Loch, daneben ein Pflock mit gruenem Band."""
    img = new(16, 16)
    for y in range(9, 15):
        for x in range(1, 11):
            dx, dy = (x - 5.5) / 4.6, (y - 11.5) / 2.6
            r = dx * dx + dy * dy
            if r <= 1.0:
                put(img, x, y, SOIL[2] if r > 0.55 else (SOIL[0] if r > 0.2 else (60, 38, 28)))
    for y in range(2, 13):
        put(img, 13, y, WOOD[2])
        put(img, 14, y, WOOD[1])
    for x, y in [(11, 3), (12, 3), (11, 4), (12, 4), (10, 4)]:
        put(img, x, y, LEAF[3])
    add_outline(img)
    return img


def clear_mark():
    """Pflock mit rot-weissem Band: hier rodet der Foerster."""
    img = new(16, 16)
    for y in range(2, 15):
        put(img, 7, y, WOOD[1])
        put(img, 8, y, WOOD[2])
    for i, x in enumerate(range(9, 15)):
        for y in (3, 4, 5):
            put(img, x, y + (1 if i > 3 and y == 5 else 0), (220, 50, 40) if (x // 2) % 2 == 0 else (246, 240, 232))
    add_outline(img)
    return img


# Symbol fuer den Bau-Reiter "Land und Wege" (haengt hinten an icons.png an)
ICONS_LAND = {
    "weg": (["................",
             "..........1111..",
             ".........133231.",
             "........1323331.",
             ".......13332311.",
             "......1323331...",
             ".....13332311...",
             "....1323331.....",
             "...13332311.....",
             "..1323331.......",
             ".13332311.......",
             ".1323331....44..",
             ".1333311...4554.",
             "..11111....4554.",
             "............66..",
             "................"],
            {"1": (60, 50, 60), "2": (110, 104, 110), "3": (196, 188, 176), "4": (44, 104, 60),
             "5": (96, 172, 82), "6": (122, 78, 50)}),
}


def fence(mask):
    """Holzzaun: Pfosten in der Mitte, zwei Querlatten zu jedem Nachbarzaun, Halbpfosten an den Enden."""
    img = new(16, 16)
    post = [WOOD[0], WOOD[1], WOOD[2]]
    # Querlatten (oben y=7, unten y=10) zu den Seiten; nach N/S eine schmale Latte in der Mitte
    for y in (7, 10):
        if mask & W:
            for x in range(0, 8):
                put(img, x, y, WOOD[3] if y == 7 else WOOD[2])
                put(img, x, y + 1, WOOD[1])
        if mask & E:
            for x in range(8, 16):
                put(img, x, y, WOOD[3] if y == 7 else WOOD[2])
                put(img, x, y + 1, WOOD[1])
    if mask & N:
        for y in range(0, 6):
            put(img, 7, y, WOOD[3])
            put(img, 8, y, WOOD[1])
        put(img, 7, 2, WOOD[0])
    if mask & S:
        for y in range(13, 16):
            put(img, 7, y, WOOD[3])
            put(img, 8, y, WOOD[1])
    # Pfosten mit Spitze und Schatten am Boden
    for y in range(4, 14):
        put(img, 6, y, post[1])
        put(img, 7, y, post[2])
        put(img, 8, y, post[1])
        put(img, 9, y, post[0])
    put(img, 7, 3, post[2])
    put(img, 8, 3, post[1])
    for x in range(5, 11):
        put(img, x, 14, (60, 90, 50, 110))
    add_outline(img)
    return img


def gen_objects3():
    atlas = new(256, 64)
    for m in range(16):
        atlas.paste(road(m), (m * 16, 0))
        atlas.paste(dike(m), (m * 16, 16))
        atlas.paste(fence(m), (m * 16, 48))
    atlas.paste(plant_mark(), (0, 32))
    atlas.paste(clear_mark(), (16, 32))
    atlas.save(os.path.join(OUT, "objects3.png"))


if __name__ == "__main__":
    gen_objects3()
