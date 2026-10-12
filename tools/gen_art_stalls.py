#!/usr/bin/env python3
"""Schweinestall und Kuhstall (josh 2026-10-12).

Wird aus gen_art.py aufgerufen:
  pigsty()     Schweinestall, Zelle 54 in buildings.png ("pigsty", Data.BUILDING_CELLS)
  cowshed()    Kuhstall, Zelle 55 ("cowshed")
  ICONS_STALLS Symbol "milch" (Ware Milch)
"""
from gen_art import (new, put, add_outline, blob, WOOD, SOIL, THATCH, ROOF_RED, DARK, WHEAT,
                     plank_wall, thatch_roof, tile_roof, ground_line)

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


def _pig(img, x, y, flip=False):
    """Schwein von der Seite, 9x6 Pixel."""
    s = -1 if flip else 1
    for dy in range(0, 4):
        for dx in range(0, 7):
            if (dx in (0, 6) and dy in (0, 3)):
                continue
            put(img, x + s * dx, y + dy, PIG[1] if dy < 2 else PIG[0])
    # Kopf und Ruessel
    for dy in range(0, 3):
        put(img, x + s * 7, y + dy, PIG[1])
    put(img, x + s * 8, y + 1, PIG[2])
    put(img, x + s * 8, y + 2, PIG[0])
    put(img, x + s * 7, y - 1, PIG[0])  # Ohr
    put(img, x + s * 7, y + 1, DARK)    # Auge
    # Beine und Ringelschwanz
    for dx in (1, 5):
        put(img, x + s * dx, y + 4, PIG[0])
    put(img, x - s, y, PIG[0])
    put(img, x - s, y - 1, PIG[1])


def pigsty():
    """Schweinestall (3x2): kleiner Bretterstall mit Strohdach, davor ein Matschgehege mit
    Trog und drei Schweinen."""
    img = new(64, 64)
    plank_wall(img, 4, 38, 24, 22)
    for y in range(48, 60):
        for x in range(12, 20):
            put(img, x, y, DARK)
    thatch_roof(img, 2, 24, 28, 16)
    # Zaun hinten (die Schweine stehen davor)
    _fence(img, 30, 62, 40, 47)
    # Matsch im Gehege
    blob(img, 45, 54, 15, 5, [SOIL[0], SOIL[1], SOIL[2]], noise_seed=31, jag=0.2)
    blob(img, 50, 56, 5, 2, [(80, 54, 40), (96, 64, 46), (110, 74, 52)], noise_seed=32)
    # Trog
    for x in range(36, 46):
        put(img, x, 50, WOOD[0])
        put(img, x, 51, WOOD[1])
    for x in range(37, 45):
        put(img, x, 49, HAY[1] if x % 2 else HAY[0])
    _pig(img, 34, 54)
    _pig(img, 52, 51, flip=True)
    _pig(img, 47, 56)
    # Zaun vorn nur als niedrige Latte mit Pfosten
    for x in range(30, 62):
        put(img, x, 60, WOOD[2])
    for x in range(30, 62, 8):
        put(img, x, 59, WOOD[1])
        put(img, x, 58, WOOD[1])
    ground_line(img, 4, 60)
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
    _cow(img, 44, 48)
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
