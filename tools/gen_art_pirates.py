#!/usr/bin/env python3
"""Grafiken fuer den Kampf gegen Piraten (josh 2026-10-12).

Wird aus gen_art.py aufgerufen:
  armory()          Waffenschmiede, Zelle 53 in buildings.png ("armory", Data.BUILDING_CELLS)
  weapon_tools()    Saebel, Mistgabel, Knueppel, angehaengt an tools.png (Data.TOOL_INDEX 10-12)
  ICONS_PIRATES     Symbol "waffen" (Ware Waffen)
"""
from gen_art import (new, put, add_outline, WOOD, STONE, IRON, GLOW, SHINGLE,
                     stone_wall, tile_roof, chimney, ground_line)

BRASS = (214, 170, 60)


def armory():
    """Waffenschmiede (3x2): Esse und Amboss wie die Schmiede, dazu ein Waffenstaender mit Speeren
    und Saebeln, ein Schild an der Wand und ein rotes Banner."""
    img = new(64, 64)
    stone_wall(img, 8, 32, 48, 28)
    # Esse
    for y in range(40, 52):
        for x in range(12, 26):
            put(img, x, y, STONE[1])
    for y in range(46, 52):
        for x in range(14, 24):
            put(img, x, y, GLOW[1] if (x + y) % 3 else GLOW[2])
    chimney(img, 14, 16, 18)
    tile_roof(img, 6, 20, 52, 14, SHINGLE, overhang=2)
    for x in (8, 54):
        for y in range(34, 60):
            put(img, x, y, WOOD[1])
            put(img, x + 1, y, WOOD[2])
    # Schild an der Wand (rund, Eisenbeschlag)
    for y in range(36, 46):
        for x in range(28, 38):
            d = (x - 32.5) ** 2 + (y - 40.5) ** 2
            if d <= 20:
                put(img, x, y, IRON[1] if d > 13 else ((170, 40, 36) if (x + y) % 2 else (150, 32, 30)))
    put(img, 32, 40, BRASS)
    put(img, 33, 41, BRASS)
    # Waffenstaender: zwei Speere, zwei Saebel
    for y in range(44, 58):
        put(img, 40, y, WOOD[1])
        put(img, 50, y, WOOD[1])
    for x in range(40, 51):
        put(img, x, 50, WOOD[2])
    for x0 in (42, 45):
        for y in range(34, 57):
            put(img, x0, y, WOOD[2])
        put(img, x0, 33, IRON[3])
        put(img, x0, 32, IRON[2])
        put(img, x0 - 1, 34, IRON[2])
        put(img, x0 + 1, 34, IRON[2])
    for x0 in (47, 49):
        for y in range(40, 52):
            put(img, x0, y, IRON[3] if y < 49 else IRON[2])
        put(img, x0 - 1, 49, BRASS)
        put(img, x0 + 1, 49, BRASS)
        put(img, x0, 52, (90, 60, 40))
    # Banner unter dem Dachrand
    for y in range(33, 41):
        for x in range(52, 57):
            if y < 39 or (x - 52) % 2 == (y - 39):
                put(img, x, y, (190, 40, 36) if x != 54 else (220, 180, 70))
    ground_line(img, 8, 56)
    add_outline(img)
    return img


def saber():
    img = new(16, 16)
    for i in range(3):
        put(img, 3 + i, 13 - i, (90, 60, 40))  # Griff
    put(img, 5, 12, BRASS)
    put(img, 6, 11, BRASS)
    put(img, 7, 12, BRASS)
    pts = [(7, 10), (8, 9), (9, 8), (10, 7), (11, 5), (12, 4), (13, 3), (13, 2)]
    for x, y in pts:
        put(img, x, y, IRON[3])
        put(img, x - 1, y, IRON[2])
    add_outline(img)
    return img


def pitchfork():
    img = new(16, 16)
    for i in range(9):
        put(img, 2 + i, 14 - i, WOOD[2])
    # Querstueck und drei Zinken schraeg nach oben rechts
    for x, y in [(9, 7), (10, 6), (11, 5), (10, 8), (11, 7), (12, 6)]:
        put(img, x, y, IRON[2])
    for (x, y) in [(10, 5), (11, 4), (12, 3)]:
        put(img, x, y, IRON[3])
    for (x, y) in [(12, 5), (13, 4), (14, 3)]:
        put(img, x, y, IRON[3])
    for (x, y) in [(11, 6), (12, 5)]:
        put(img, x + 1, y + 1, IRON[3])
    add_outline(img)
    return img


def club():
    img = new(16, 16)
    for i in range(6):
        put(img, 3 + i, 13 - i, WOOD[1])
    for y in range(2, 9):
        for x in range(8, 15):
            d = (x - 11) ** 2 + (y - 5) ** 2
            if d <= 9:
                put(img, x, y, WOOD[2] if d > 3 else WOOD[3])
    put(img, 10, 4, WOOD[0])
    put(img, 12, 6, WOOD[0])
    add_outline(img)
    return img


def weapon_tools():
    return [saber(), pitchfork(), club()]


ICONS_PIRATES = {
    "waffen": (["................",
                ".1...........1..",
                ".31.........13..",
                "..31.......13...",
                "...32.....23....",
                "....32...23.....",
                ".....32.23......",
                "......323.......",
                "......232.......",
                ".....24.42......",
                "....44...44.....",
                "...55.....55....",
                "..55.......55...",
                ".55.........55..",
                "................",
                "................"],
               {"1": IRON[3], "2": IRON[1], "3": IRON[2], "4": BRASS, "5": WOOD[1]}),
}
