"""Boden und Wege von josh (2026-10-30), fein: 136 Bildpunkte je Feld wie die feinen Siedler-Bögen.
Quelle tools/art_v2/src/boden_fein: grund_<jahreszeit>.png und grund_sand.png (544 x 544 = 4 x 4 Felder,
nahtlos), <weg>_<maske>.png (136 x 136, Maske N=1 O=2 S=4 W=8). Ziel assets/sprites_hd/fine:
dieselben Bodenbilder und wege.png (16 Masken nebeneinander, Zeilen Steinstraße = road, Erdweg = gravel,
Pflaster = bricks). Jeder Weg bekommt einen dünnen dunklen Rand zum Gras (josh: „setze das um“)."""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src", "boden_fein")
OUT = os.path.join(HERE, "..", "..", "assets", "sprites_hd", "fine")
T = 136
ROWS = [("strasse", "road"), ("weg", "gravel"), ("pflaster", "bricks")]  # josh 2026-10-30: Straße = Steinstraße, Kiesweg = Erdweg
GROUNDS = ["fruehling", "sommer", "herbst", "winter", "sand"]


def outline(img, m):
    """Dunkler Rand 3 Punkte breit an offenen Kanten (Übergang zu durchsichtig); an verbundenen Seiten nicht."""
    a = np.asarray(img).astype(np.float32).copy()
    op = a[:, :, 3] > 127
    pad = np.pad(op, 3, mode="edge")
    # über die Kachelkante hinaus: verbundene Seiten gelten als belegt, offene als leer
    if not (m & 1):
        pad[:3, :] = False
    if not (m & 2):
        pad[:, -3:] = False
    if not (m & 4):
        pad[-3:, :] = False
    if not (m & 8):
        pad[:, :3] = False
    near = np.zeros_like(op)
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            if dx * dx + dy * dy <= 9:
                near |= ~pad[3 + dy:3 + dy + T, 3 + dx:3 + dx + T]
    edge = op & near
    a[edge, :3] *= 0.62
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def main():
    os.makedirs(OUT, exist_ok=True)
    for g in GROUNDS:
        Image.open(os.path.join(SRC, "grund_%s.png" % g)).convert("RGBA").save(os.path.join(OUT, "grund_%s.png" % g), optimize=True)
    sheet = Image.new("RGBA", (16 * T, len(ROWS) * T), (0, 0, 0, 0))
    for r, (src, _kind) in enumerate(ROWS):
        for m in range(16):
            img = Image.open(os.path.join(SRC, "%s_%02d.png" % (src, m))).convert("RGBA")
            sheet.alpha_composite(outline(img, m), (m * T, r * T))
    sheet.save(os.path.join(OUT, "wege.png"), optimize=True)
    print("   fein: Boden", len(GROUNDS), "Wege", len(ROWS))


if __name__ == "__main__":
    main()
