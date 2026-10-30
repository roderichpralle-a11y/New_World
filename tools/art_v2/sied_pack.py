"""Siedler-Bögen ohne leeren Rand (josh 2026-10-30, Arbeitsspeicher): jedes Kästchen der Bögen in
assets/sprites_hd/sied (60 je Kästchen) und sied_hd (120) wird auf seinen Inhalt zugeschnitten und dicht in
assets/sprites_hd/sied_pack/<sied|sied_hd>/<name>.png gelegt; <ordner>/index.json nennt je Bogen
"cell" (Kästchengröße in Bildpunkten) und je Kästchen [x, y, w, h, links, oben] (Stelle im gepackten Bild und
Lage im Kästchen) oder null für leere Kästchen. Settler.sied_cells baut daraus AtlasTextures mit Rand
(margin), die genau so groß sind wie das Kästchen: das Bild bleibt Punkt für Punkt gleich.
Ausschnitte liegen auf einem Raster von ALIGN Punkten und haben ALIGN Punkte Luft um den Inhalt, damit auch
die verkleinerten Stufen (Mipmaps, World zeichnet mit LINEAR_WITH_MIPMAPS) bis 1/ALIGN gleich bleiben.
Nach jedem Neubau der Bögen (build.py gen_settler_sheets) erneut laufen lassen."""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
HD = os.path.join(HERE, "..", "..", "assets", "sprites_hd")
ROWS_PER_SHEET = 8  # Bilder je Zeile
SETS = {"sied": (2, 1024), "sied_hd": (4, 2048)}  # Ordner -> (ALIGN, Breite des gepackten Bildes)


def pack_sheet(img, align, width):
    cw = img.width // ROWS_PER_SHEET
    ch = cw
    rows = img.height // ch
    a = img.getchannel("A")
    boxes = []
    for r in range(rows):
        for c in range(ROWS_PER_SHEET):
            bb = a.crop((c * cw, r * ch, c * cw + cw, r * ch + ch)).getbbox()
            if bb is None:
                boxes.append(None)
                continue
            l = max(0, (bb[0] - align) // align * align)
            t = max(0, (bb[1] - align) // align * align)
            rr = min(cw, -(-(bb[2] + align) // align) * align)
            b = min(ch, -(-(bb[3] + align) // align) * align)
            boxes.append((c * cw, r * ch, l, t, rr - l, b - t))
    # Regalpacken: höchste zuerst, Zeile für Zeile; die erste Zeile bleibt für den leeren Platzhalter frei
    order = sorted((i for i, bx in enumerate(boxes) if bx), key=lambda i: -boxes[i][5])
    x, y, shelf = 0, align, 0
    place = {}
    for i in order:
        w, h = boxes[i][4], boxes[i][5]
        if x + w > width:
            x, y, shelf = 0, y + shelf, 0
        place[i] = (x, y)
        x += w
        shelf = max(shelf, h)
    out = Image.new("RGBA", (width, -(-(y + shelf) // align) * align), (0, 0, 0, 0))
    regions = []
    for i, bx in enumerate(boxes):
        if bx is None:
            regions.append(None)
            continue
        ox, oy, l, t, w, h = bx
        px, py = place[i]
        out.paste(img.crop((ox + l, oy + t, ox + l + w, oy + t + h)), (px, py))
        regions.append([px, py, w, h, l, t])
    return out, {"cell": [cw, ch], "rows": rows, "r": regions}


def main():
    for folder, (align, width) in SETS.items():
        src = os.path.join(HD, folder)
        dst = os.path.join(HD, "sied_pack", folder)
        os.makedirs(dst, exist_ok=True)
        index = {}
        before = after = 0
        for f in sorted(os.listdir(src)):
            if not f.endswith(".png"):
                continue
            img = Image.open(os.path.join(src, f)).convert("RGBA")
            out, meta = pack_sheet(img, align, width)
            out.save(os.path.join(dst, f), optimize=True)
            index[f[:-4]] = meta
            before += img.width * img.height * 4
            after += out.width * out.height * 4
        json.dump(index, open(os.path.join(dst, "index.json"), "w"), separators=(",", ":"))
        print("%s: %d Bögen, Speicher %.0f MB -> %.0f MB" % (folder, len(index), before / 1e6, after / 1e6))


if __name__ == "__main__":
    main()
