#!/usr/bin/env python3
"""Bücher und Zeitungen (josh 2026-10-20).

Wird aus gen_art.py aufgerufen:
  ICONS_READING  Symbole "buecher" (Bücherstapel) und "zeitungen" (gefaltete Zeitung)
  newspaper()    Zeitung in der Hand (tools.png, Index 13 "newspaper" in Data.TOOL_INDEX)
  printshop()    Druckerei (3x2): Fachwerkhaus mit Druckerpresse unter dem Vordach, Papierstapel,
                 Ladenschild mit Buch. Zelle 59 in buildings.png ("printshop", Data.BUILDING_CELLS)
"""
from gen_art import (new, put, add_outline, blob, WOOD, DARK, STONE, ROOF_RED, ground_line, door,
                     tile_roof, window)

PAPER = [(196, 190, 172), (226, 222, 206), (250, 248, 238)]
INK = (52, 46, 58)

ICONS_READING = {
    "buecher": (["................",
                 "................",
                 "...1111111111...",
                 "...1222222221...",
                 "...1333333331...",
                 "...1111111111...",
                 "..111111111111..",
                 "..144444444441..",
                 "..155555555551..",
                 "..111111111111..",
                 "...1111111111...",
                 "...1666666661...",
                 "...1777777771...",
                 "...1111111111...",
                 "................",
                 "................"],
                {"1": (60, 40, 40), "2": (170, 50, 46), "3": (240, 232, 214), "4": (60, 110, 170),
                 "5": (240, 232, 214), "6": (70, 130, 70), "7": (240, 232, 214)}),
    "zeitungen": (["................",
                   "..111111111111..",
                   "..122222222221..",
                   "..123333333321..",
                   "..122222222221..",
                   "..124442555521..",
                   "..124442222221..",
                   "..124442555521..",
                   "..122222222221..",
                   "..125552555521..",
                   "..122222222221..",
                   "..125552555521..",
                   "..122222222221..",
                   "..111111111111..",
                   "................",
                   "................"],
                  {"1": (90, 86, 80), "2": (242, 238, 226), "3": (52, 46, 58), "4": (150, 150, 160),
                   "5": (150, 146, 140)}),
}


def newspaper():
    """Aufgeschlagene Zeitung, beidhändig vor dem Körper (wird nicht geschwungen)."""
    img = new(16, 16)
    for y in range(3, 13):
        for x in range(1, 15):
            c = PAPER[2] if x < 8 else PAPER[1]
            if x in (7, 8):
                c = PAPER[0]
            put(img, x, y, c)
    for x in range(2, 7):
        put(img, x, 4, INK)
    for y in (6, 8, 10):
        for x in range(2, 7):
            if (x + y) % 5:
                put(img, x, y, (140, 136, 140))
        for x in range(9, 14):
            if (x * 3 + y) % 7:
                put(img, x, y, (140, 136, 140))
    for y in range(5, 8):
        for x in range(9, 12):
            put(img, x, y, (120, 140, 170))
    add_outline(img)
    return img


def printshop():
    img = new(64, 64)
    # Fachwerk: weiße Gefache, dunkle Balken
    for y in range(36, 60):
        for x in range(6, 58):
            c = (232, 224, 204)
            if x in (6, 19, 32, 45, 57) or y in (36, 47, 59):
                c = WOOD[0]
            elif (x - 6) % 13 == (y - 36) % 13 and y < 47:
                c = WOOD[1]
            put(img, x, y, c)
    tile_roof(img, 4, 18, 56, 19)
    door(img, 27, 48, 9, 12)
    window(img, 10, 39, 6, 6)
    window(img, 48, 39, 6, 6)
    window(img, 10, 50, 6, 6)
    # Ladenschild mit offenem Buch am Ausleger
    for x in range(36, 44):
        put(img, x, 38, WOOD[0])
    for y in range(39, 46):
        for x in range(38, 45):
            put(img, x, y, WOOD[2] if x in (38, 44) or y in (39, 45) else PAPER[2])
    put(img, 41, 41, INK)
    put(img, 41, 42, INK)
    put(img, 41, 43, INK)
    # Papierstapel vor dem Haus
    for i in range(4):
        for x in range(46, 55):
            put(img, x, 58 - i * 2, PAPER[1] if i % 2 else PAPER[2])
            put(img, x, 59 - i * 2, PAPER[0])
    ground_line(img, 4, 60)
    add_outline(img)
    return img
