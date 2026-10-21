#!/usr/bin/env python3
"""Jagdhuette am Wildgehege (josh 2026-10-20).

Wird aus gen_art.py aufgerufen:
  lodge()  Jagdhuette (2x2): Blockhuette aus Rundstaemmen mit Schindeldach, Geweih ueber der Tuer,
           Schiessluke zum Gehege, Fellgestell daneben. Zelle 58 in buildings.png ("lodge", Data.BUILDING_CELLS)
"""
from gen_art import (new, put, add_outline, blob, WOOD, SOIL, DARK, SHINGLE, STONE, ground_line, door)

LOG = [(92, 58, 38), (128, 84, 52), (164, 116, 70), (196, 150, 98)]
BONE = [(176, 160, 132), (214, 200, 170), (240, 230, 206)]
HIDE = [(110, 70, 44), (146, 98, 60), (178, 128, 82)]


def lodge():
    img = new(64, 64)
    x0, x1 = 15, 49
    # Waende aus Rundstaemmen: je Stamm 3 Pixel hoch, heller Rand oben, dunkle Fuge unten,
    # Stammenden ragen an den Ecken heraus
    for y in range(38, 60):
        k = (y - 38) % 3
        for x in range(x0 - 2, x1 + 2):
            if x < x0 or x >= x1:
                if k == 1:
                    put(img, x, y, LOG[3] if x in (x0 - 2, x1 + 1) else LOG[2])  # Stammende (hell)
                elif k == 0:
                    put(img, x, y, LOG[1])
                continue
            c = LOG[2] if k == 0 else LOG[1] if k == 1 else LOG[0]
            if k == 1 and (x * 7 + y) % 13 == 0:
                c = LOG[0]  # Astloch
            put(img, x, y, c)
    # Satteldach aus Holzschindeln, Giebel nach vorn
    for y in range(22, 40):
        half = (y - 22) * 1.15 + 3
        for x in range(int(32 - half) - 1, int(32 + half) + 1):
            if x < x0 - 4 or x > x1 + 3:
                continue
            row = (y - 22) // 3
            c = SHINGLE[2] if (y - 22) % 3 else SHINGLE[0]
            if (x + row * 2) % 5 == 0:
                c = SHINGLE[1]
            if abs(x - 32) <= 1 and y < 26:
                c = SHINGLE[3]
            put(img, x, y, c)
    for x in range(x0 - 4, x1 + 4):
        put(img, x, 39, SHINGLE[0])
    # Kamin aus Feldsteinen
    for y in range(18, 30):
        for x in range(41, 46):
            put(img, x, y, STONE[2] if (x + y // 2) % 3 else STONE[1])
    for x in range(40, 47):
        put(img, x, 17, STONE[3])
    # Tuer und Geweih darueber
    door(img, 28, 48, 8, 12)
    for x, y in [(29, 44), (28, 43), (27, 42), (27, 41), (26, 40), (28, 41),
                 (34, 44), (35, 43), (36, 42), (36, 41), (37, 40), (35, 41), (30, 45), (31, 45), (32, 45), (33, 45)]:
        put(img, x, y, BONE[1] if y > 41 else BONE[2])
    put(img, 31, 46, BONE[0])
    put(img, 32, 46, BONE[0])
    # Schiessluke rechts mit Klappe, links ein kleines Fenster
    for y in range(45, 48):
        for x in range(40, 46):
            put(img, x, y, DARK)
    for x in range(40, 46):
        put(img, x, 44, LOG[3])
    for y in range(46, 51):
        for x in range(19, 24):
            put(img, x, y, (60, 52, 50) if (x, y) != (21, 48) else (230, 190, 110))
    # Fellgestell links: zwei Pfosten, Querstange, gespanntes Fell
    for y in range(44, 61):
        put(img, 5, y, WOOD[1])
        put(img, 12, y, WOOD[1])
    for x in range(4, 14):
        put(img, x, 44, WOOD[2])
    blob(img, 8.5, 50, 3, 4.5, HIDE, noise_seed=41, jag=0.2)
    for y in range(45, 47):
        put(img, 7, y, (200, 190, 170))
        put(img, 10, y, (200, 190, 170))
    # Hackklotz mit Beil und Brennholz rechts
    for y in range(55, 60):
        for x in range(52, 58):
            put(img, x, y, WOOD[2] if y > 55 else WOOD[3])
    for i in range(5):
        put(img, 55 + i // 2, 54 - i, WOOD[1])
    put(img, 57, 50, STONE[3])
    put(img, 58, 50, STONE[2])
    put(img, 58, 51, STONE[2])
    ground_line(img, 3, 60)
    add_outline(img)
    return img
