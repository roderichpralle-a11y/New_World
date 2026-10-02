"""Ersetzt die Ziffern 0-9 in Pixelify Sans durch klare 5x7-Pixelziffern.

Die Originalziffern (2, 5, 6, 8, 9) sehen sich in kleinen Groessen zu aehnlich.
Liest die Originalschrift aus tools/fonts_src/ und schreibt assets/fonts/*.woff2.
Aufruf: python3 tools/gen_font_digits.py   (braucht fonttools und brotli)
"""
import os
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DIGITS = {
    "zero":  [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "one":   [".#.", "##.", ".#.", ".#.", ".#.", ".#.", "###"],
    "two":   [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    "three": [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],
    "four":  ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    "five":  ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
    "six":   ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
    "seven": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
    "eight": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
    "nine":  [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
}

# Schrift -> (links, unten, oben, Zusatzbreite fuer fette Striche)
FONTS = {
    "pixelify-sans-latin-400-normal": (60, -12, 631, 0),
    "pixelify-sans-latin-700-normal": (61, -11, 638, 34),
}


def rect(pen, x0, y0, x1, y1):
    pen.moveTo((x0, y0))
    pen.lineTo((x0, y1))
    pen.lineTo((x1, y1))
    pen.lineTo((x1, y0))
    pen.closePath()


def build(name, left, bottom, top, bold):
    src = os.path.join(ROOT, "tools", "fonts_src", name + ".woff2")
    font = TTFont(src)
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    for gname, rows in DIGITS.items():
        adv = hmtx[gname][0]
        cols = len(rows[0])
        # Ziffernbreite aus der Originalschrift (5 Spalten; die 1 hat 3)
        width = (465 if cols == 5 else 283) + (16 if bold else 0)
        cw = (width - bold) / cols
        ch = (top - bottom - bold) / 7.0
        pen = TTGlyphPen(None)
        for r, row in enumerate(rows):
            y0 = bottom + (6 - r) * ch
            c = 0
            while c < cols:
                if row[c] != "#":
                    c += 1
                    continue
                e = c
                while e + 1 < cols and row[e + 1] == "#":
                    e += 1
                rect(pen, round(left + c * cw), round(y0), round(left + (e + 1) * cw + bold), round(y0 + ch + bold))
                c = e + 1
        g = pen.glyph()
        g.recalcBounds(glyf)
        glyf[gname] = g
        hmtx[gname] = (adv, g.xMin)
    font.flavor = "woff2"
    font.save(os.path.join(ROOT, "assets", "fonts", name + ".woff2"))


if __name__ == "__main__":
    for n, args in FONTS.items():
        build(n, *args)
    print("Ziffern ersetzt.")
