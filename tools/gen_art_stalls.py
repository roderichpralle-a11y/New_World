#!/usr/bin/env python3
"""Schweinestall und Kuhstall (josh 2026-10-12).

Wird aus gen_art.py aufgerufen:
  pigsty()     Schweinestall (Bruchstein, Pultdach, Suhle), Zelle 54 in buildings.png ("pigsty", Data.BUILDING_CELLS)
  cowshed()    Kuhstall, Zelle 55 ("cowshed")
  ICONS_STALLS Symbol "milch" (Ware Milch)
"""
from gen_art import (new, put, add_outline, blob, WOOD, SOIL, THATCH, ROOF_RED, DARK, WHEAT, STONE, SHINGLE,
                     plank_wall, thatch_roof, tile_roof, stone_wall, ground_line)

PIG = [(196, 120, 120), (232, 160, 156), (248, 196, 190)]
COW_W = (246, 242, 234)
COW_B = (52, 40, 40)
HAY = [(176, 140, 60), (214, 180, 84), (240, 214, 120)]
BARN = [(120, 44, 36), (156, 60, 46), (184, 80, 60)]


def _fence(img, x0, x1, y0, y1):
    for x in range(x0, x1):
        put(img, x, y0, WOOD[2])
        put(img, x, y0 + 5, WOOD[2])
    for x in range(x0, x1, 5):
        for y in range(y0 - 2, y1):
            put(img, x, y, WOOD[1])


def _pig(img, x, y, flip=False, lying=False):
    """Grosses Schwein von der Seite, 12x7 Pixel (liegend 12x5, halb im Matsch)."""
    s = -1 if flip else 1
    h = 3 if lying else 5
    for dy in range(0, h):
        for dx in range(0, 10):
            if dx in (0, 9) and dy in (0, h - 1):
                continue
            c = PIG[2] if dy == 0 else PIG[1] if dy < h - 1 else PIG[0]
            put(img, x + s * dx, y + dy, c)
    # Kopf mit Ruessel und Schlappohr
    for dy in range(0, 3):
        put(img, x + s * 10, y + dy, PIG[1])
    put(img, x + s * 11, y + 1, PIG[2])
    put(img, x + s * 11, y + 2, (210, 120, 120))
    put(img, x + s * 12, y + 1, (190, 100, 104))
    put(img, x + s * 12, y + 2, (190, 100, 104))
    put(img, x + s * 9, y - 1, PIG[0])
    put(img, x + s * 10, y - 1, PIG[0])
    put(img, x + s * 10, y + 1, DARK)
    # Ringelschwanz
    put(img, x - s, y, PIG[0])
    put(img, x - s * 2, y - 1, PIG[0])
    put(img, x - s, y - 2, PIG[0])
    if not lying:
        for dx in (1, 2, 7, 8):
            put(img, x + s * dx, y + 5, PIG[0])
            put(img, x + s * dx, y + 6, (110, 70, 64))


def pigsty():
    """Schweinestall (3x2): langer, niedriger Bruchsteinstall mit Pultdach aus Holzschindeln und
    zwei Koben mit halb offenen Stalltueren; davor ein Pferch mit Bruchsteinmauer, grosser
    Suhle, Steintrog und vier dicken Schweinen. Bewusst anders als der Huehnerhof (kein
    Strohdach, kein Holzlattenzaun)."""
    img = new(64, 64)
    # Rueckwand: niedriger Bruchsteinstall ueber die ganze Breite
    stone_wall(img, 3, 30, 58, 16)
    # Pultdach: hinten hoch, vorn tief, Schindeln in Reihen
    for y in range(20, 32):
        for x in range(1, 63):
            row = (y - 20) // 3
            c = SHINGLE[1] if (x + row * 2) % 6 == 0 else SHINGLE[2] if (y - 20) % 3 else SHINGLE[0]
            if y == 31:
                c = SHINGLE[0]
            if y == 20:
                c = SHINGLE[3]
            put(img, x, y, c)
    # Balkenkopf-Reihe unter der Traufe
    for x in range(4, 61, 7):
        put(img, x, 32, WOOD[1])
        put(img, x + 1, 32, WOOD[2])
    # Zwei Koben mit zweiteiliger Stalltuer (obere Haelfte offen, untere zu)
    for x0 in (10, 38):
        for y in range(35, 46):
            for x in range(x0, x0 + 12):
                if y < 40:
                    c = DARK if x not in (x0, x0 + 11) else WOOD[0]
                else:
                    c = WOOD[1] if (x - x0) % 3 else WOOD[0]
                put(img, x, y, c)
        for x in range(x0, x0 + 12):
            put(img, x, 34, WOOD[0])
            put(img, x, 40, WOOD[2])
        # Schweinekopf schaut aus dem Koben
        for dy in range(0, 3):
            for dx in range(0, 4):
                put(img, x0 + 4 + dx, 37 + dy, PIG[1] if dy < 2 else PIG[0])
        put(img, x0 + 5, 38, DARK)
        put(img, x0 + 4, 39, (190, 100, 104))
        put(img, x0 + 4, 36, PIG[0])
        put(img, x0 + 7, 36, PIG[0])
    # Strohhaufen zwischen den Koben
    blob(img, 30, 44, 4, 2, [THATCH[1], THATCH[2], THATCH[3]], noise_seed=33, jag=0.3)
    # Pferch: Boden aus festgetretener Erde, grosse Suhle in der Mitte
    for y in range(46, 61):
        for x in range(3, 61):
            put(img, x, y, SOIL[1] if (x * 7 + y * 3) % 11 else SOIL[2])
    blob(img, 30, 55, 13, 4, [(58, 38, 30), (76, 50, 38), (92, 62, 46)], noise_seed=34, jag=0.15)
    for (x, y) in [(21, 53), (22, 53), (33, 56), (34, 56), (29, 58)]:
        put(img, x, y, (150, 128, 116))  # nasse Glanzlichter
    # Steintrog links
    for y in range(48, 52):
        for x in range(3, 15):
            put(img, x, y, STONE[2] if y == 49 else STONE[1])
    for x in range(4, 14):
        put(img, x, 49, WHEAT[1] if x % 2 else WHEAT[2])
    # Vier dicke Schweine: am Trog, in der Suhle liegend, zwei laufend
    _pig(img, 4, 52)
    _pig(img, 24, 55, lying=True)
    _pig(img, 58, 46, flip=True)
    _pig(img, 50, 52, flip=True)
    # Niedrige Bruchsteinmauer vorn (nur 3 Pixel hoch, damit man die Schweine sieht)
    for x in range(2, 62):
        for y in range(58, 62):
            c = STONE[2] if y == 58 else STONE[1] if (x // 3 + y) % 2 else STONE[0]
            put(img, x, y, c)
    for x in range(3, 61, 6):
        put(img, x, 59, STONE[3])
    # Gattertor rechts in der Mauer
    for x in range(53, 60):
        for y in range(56, 61):
            put(img, x, y, WOOD[2] if y in (56, 59) or x in (53, 59) or x - 53 == y - 56 else SOIL[1])
    ground_line(img, 2, 62)
    add_outline(img)
    return img


def _cow(img, x, y):
    """Kuh von der Seite (Blick nach links), 14x9 Pixel, schwarz-weiss gefleckt."""
    spots = {(3, 1), (4, 1), (4, 2), (8, 2), (9, 2), (9, 3), (10, 1), (6, 4)}
    for dy in range(0, 6):
        for dx in range(2, 13):
            if (dx in (2, 12) and dy in (0, 5)):
                continue
            put(img, x + dx, y + dy, COW_B if (dx, dy) in spots else COW_W)
    # Kopf
    for dy in range(-1, 4):
        for dx in range(-1, 2):
            put(img, x + dx, y + dy, COW_W if dy < 2 else (230, 170, 160))
    put(img, x, y, DARK)            # Auge
    put(img, x - 1, y - 2, (220, 210, 190))  # Horn
    put(img, x + 1, y - 2, (220, 210, 190))
    put(img, x + 2, y - 1, COW_B)   # Ohr
    # Euter, Beine, Schwanz
    put(img, x + 8, y + 6, (240, 170, 170))
    put(img, x + 9, y + 6, (240, 170, 170))
    for dx in (3, 4, 10, 11):
        for dy in (6, 7, 8):
            put(img, x + dx, y + dy, COW_W if dy < 8 else COW_B)
    for dy in range(0, 5):
        put(img, x + 13, y + dy, COW_B)


def cowshed():
    """Kuhstall (3x2): rote Scheune mit Schiebetor, Heuboden, Heuballen und einer Kuh vor dem Tor."""
    img = new(64, 64)
    # Scheunenwand aus roten Brettern
    for y in range(32, 60):
        for x in range(8, 56):
            c = BARN[1] if (x // 3) % 2 else BARN[2]
            if y in (32, 59):
                c = BARN[0]
            put(img, x, y, c)
    # Tor mit weissem X
    for y in range(42, 60):
        for x in range(24, 40):
            put(img, x, y, BARN[0] if x in (24, 31, 32, 39) or y == 42 else BARN[1])
    for i in range(16):
        put(img, 24 + i, 43 + i * 16 // 16 if i < 16 else 58, (236, 228, 214))
        put(img, 39 - i, 43 + i * 16 // 16 if i < 16 else 58, (236, 228, 214))
    # Heuboden-Luke mit Heu
    for y in range(26, 34):
        for x in range(28, 36):
            put(img, x, y, DARK if y < 30 else HAY[1])
    tile_roof(img, 6, 12, 52, 20, [(70, 46, 40), (98, 64, 50), (128, 86, 62), (156, 112, 78)], overhang=2)
    # Heuballen links
    for y in range(52, 60):
        for x in range(2, 10):
            put(img, x, y, HAY[0] if (x + y) % 3 == 0 else HAY[2] if y < 54 else HAY[1])
    _cow(img, 44, 51)  # Hufe auf dem Boden (y 59), nicht schwebend (josh)
    # Milchkanne
    for y in range(54, 60):
        for x in range(18, 21):
            put(img, x, y, (190, 194, 204) if x < 20 else (150, 154, 168))
    put(img, 19, 53, (150, 154, 168))
    ground_line(img, 2, 62)
    add_outline(img)
    return img


ICONS_STALLS = {
    "milch": (["................",
               "......1111......",
               "......1221......",
               ".....112211.....",
               "....12222221....",
               "....13333331....",
               "....13333331....",
               "....13333331....",
               "....13344331....",
               "....13344331....",
               "....13333331....",
               "....13333331....",
               "....13333331....",
               "....11111111....",
               "................",
               "................"],
              {"1": (110, 112, 128), "2": (190, 194, 206), "3": (250, 250, 246), "4": (120, 170, 220)}),
}
