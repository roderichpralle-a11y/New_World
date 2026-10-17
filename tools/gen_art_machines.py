#!/usr/bin/env python3
"""Maschinen aus joshs Verwalter-bis-KI-Fahrplan (2026-10-17).

Wird aus gen_art.py aufgerufen:
  automaton()      Rechenautomat (3x2), Zelle 56 in buildings.png ("automaton", Data.BUILDING_CELLS)
  droid_factory()  Droidenfabrik (3x2), Zelle 57 ("droid_factory")
"""
from gen_art import new, put, add_outline, STONE, IRON, DARK, GLOW, SLATE, ground_line, stone_wall, tile_roof

BRASS = [(140, 100, 40), (190, 146, 60), (226, 190, 96), (250, 226, 150)]
STEEL = [(54, 60, 74), (84, 92, 110), (122, 132, 152), (170, 180, 198), (214, 222, 234)]
LED = (90, 220, 250)


def _gear(img, cx, cy, r, cols):
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 1, cx + r + 2):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            tooth = (x - cx + y - cy) % 3 == 0
            if d <= r - 1:
                put(img, x, y, cols[1] if d > r * 0.45 else cols[0])
            elif d <= r + (1 if tooth else 0):
                put(img, x, y, cols[2])
    put(img, cx, cy, cols[3])


def automaton():
    """Rechenautomat: hoher Messingschrank mit Zahnraedern, Lochstreifen und Glaskuppel auf einem
    Steinsockel, daneben ein kleines Schreibpult (Renaissance, Uhrwerk)."""
    img = new(64, 64)
    stone_wall(img, 10, 48, 44, 12)
    # Schrank
    for y in range(22, 48):
        for x in range(18, 46):
            c = BRASS[1] if (x + y) % 7 else BRASS[0]
            if x in (18, 45) or y == 22:
                c = BRASS[0]
            put(img, x, y, c)
    for y in range(24, 46):
        put(img, 31, y, BRASS[0])
        put(img, 32, y, BRASS[2])
    _gear(img, 25, 30, 4, BRASS)
    _gear(img, 38, 33, 5, [STEEL[0], STEEL[2], STEEL[3], STEEL[4]])
    _gear(img, 26, 40, 3, [STEEL[0], STEEL[2], STEEL[3], STEEL[4]])
    # Zifferblatt
    for y in range(38, 45):
        for x in range(35, 43):
            d = (x - 38.5) ** 2 + (y - 41) ** 2
            if d <= 11:
                put(img, x, y, (246, 236, 210))
    put(img, 38, 41, DARK)
    put(img, 38, 40, DARK)
    put(img, 39, 41, DARK)
    # Glaskuppel oben
    for y in range(12, 22):
        for x in range(22, 42):
            d = ((x - 31.5) / 10) ** 2 + ((y - 22) / 10) ** 2
            if d <= 1.0:
                put(img, x, y, (180, 220, 236) if (x - y) % 5 else (230, 246, 252))
    _gear(img, 31, 18, 3, BRASS)
    # Lochstreifen, der aus dem Schrank laeuft
    for x in range(46, 56):
        for y in (44, 45, 46):
            put(img, x, y, (240, 230, 200) if not (y == 45 and x % 2) else DARK)
    # Schreibpult links
    for y in range(40, 48):
        put(img, 11, y, (122, 78, 50))
        put(img, 16, y, (122, 78, 50))
    for x in range(10, 18):
        put(img, x, 39, (160, 108, 66))
        put(img, x, 40, (122, 78, 50))
    ground_line(img, 10, 54)
    add_outline(img)
    return img


def droid_factory():
    """Droidenfabrik: flache Stahlhalle mit Schiebetor, Leuchtstreifen und Antenne, davor ein Droide."""
    img = new(64, 64)
    for y in range(28, 58):
        for x in range(6, 58):
            c = STEEL[2] if (x // 4 + y // 6) % 2 else STEEL[1]
            if y < 31:
                c = STEEL[3]
            put(img, x, y, c)
    # Tor
    for y in range(40, 58):
        for x in range(22, 42):
            put(img, x, y, STEEL[0] if (y % 3) else STEEL[1])
    # Leuchtstreifen
    for x in range(8, 56):
        if x < 22 or x > 41:
            put(img, x, 36, LED if x % 3 else STEEL[4])
    # Dach und Antenne
    for x in range(4, 60):
        put(img, x, 27, SLATE[0])
        put(img, x, 26, SLATE[1])
    for y in range(12, 26):
        put(img, 50, y, STEEL[3])
    put(img, 50, 11, (240, 70, 60))
    put(img, 49, 14, STEEL[3])
    put(img, 51, 14, STEEL[3])
    # kleiner Droide vor dem Tor
    for y in range(48, 57):
        for x in range(12, 18):
            put(img, x, y, STEEL[3] if y < 52 else STEEL[2])
    put(img, 13, 50, LED)
    put(img, 16, 50, LED)
    put(img, 15, 47, STEEL[4])
    ground_line(img, 6, 58)
    add_outline(img)
    return img
