"""Symbol für Stahl (josh 2026-11-16): ein blauer Doppel-T-Träger statt grauer Barren, die wie Eisen aussahen.
Zeichnet das Symbol in 34x34 Punkten und setzt es in alle vier Symbolbögen (16, 64, 68 und 136 Punkte je Feld).
Aufruf: python3 tools/art_v2/stahl_symbol.py [vorschau.png]"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = (28, 36, 54, 255)      # Umriss
DARK = (62, 84, 122, 255)    # Schattenseite
MID = (104, 134, 178, 255)   # Stirnseite
LIGHT = (160, 190, 226, 255) # Oberseiten
SHINE = (222, 238, 255, 255) # Glanz


def draw() -> Image.Image:
    im = Image.new("RGBA", (34, 34), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    dx, dy = 13, -9  # Tiefe nach rechts oben
    # Stirnseite des Trägers als "I": Punkte im Uhrzeigersinn
    f = [(2, 12), (18, 12), (18, 16), (12, 16), (12, 26), (18, 26), (18, 31), (2, 31), (2, 26), (8, 26), (8, 16), (2, 16)]
    def sh(p): return (p[0] + dx, p[1] + dy)
    # Oberseite des oberen Flansches
    d.polygon([f[0], f[1], sh(f[1]), sh(f[0])], fill=LIGHT, outline=OUT)
    # rechte Seite des oberen Flansches
    d.polygon([f[1], f[2], sh(f[2]), sh(f[1])], fill=DARK, outline=OUT)
    # Steg (rechte Seite, liegt im Schatten)
    d.polygon([f[3], f[4], sh(f[4]), sh(f[3])], fill=DARK, outline=OUT)
    # Oberseite des unteren Flansches
    d.polygon([f[4], f[5], sh(f[5]), sh(f[4])], fill=LIGHT, outline=OUT)
    # rechte Seite des unteren Flansches
    d.polygon([f[5], f[6], sh(f[6]), sh(f[5])], fill=DARK, outline=OUT)
    # Stirnseite
    d.polygon(f, fill=MID, outline=OUT)
    # Glanz
    d.line([(4, 13), (15, 13)], fill=SHINE)
    d.line([(4, 27), (15, 27)], fill=LIGHT)
    d.line([(9, 17), (9, 24)], fill=LIGHT)
    d.line([(6, 10), (17, 2)], fill=SHINE)
    d.line([(21, 24), (29, 18)], fill=SHINE)
    return im


def main() -> None:
    names = [l.strip() for l in open(os.path.join(ROOT, "assets", "sprites", "icons.txt")) if l.strip()]
    i = names.index("stahl")
    base = draw()
    if len(sys.argv) > 1:
        base.resize((272, 272), Image.NEAREST).save(sys.argv[1])
    for rel, cell, cols in (("assets/sprites/icons.png", 16, 10 ** 6), ("assets/sprites_hd/icons.png", 64, 16),
                            ("assets/sprites_hd/half/fine/icons.png", 68, 16), ("assets/sprites_hd/fine/icons.png", 136, 16)):
        p = os.path.join(ROOT, rel)
        sheet = Image.open(p).convert("RGBA")
        x, y = (i % cols) * cell, (i // cols) * cell
        t = base.resize((cell, cell), Image.NEAREST if cell % 34 == 0 else Image.LANCZOS)
        sheet.paste((0, 0, 0, 0), (x, y, x + cell, y + cell))
        sheet.alpha_composite(t, (x, y))
        sheet.save(p)
        print("gesetzt:", rel, (x, y), cell)


if __name__ == "__main__":
    main()
