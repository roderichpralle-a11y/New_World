"""Freistellen und Zerschneiden der Bildbögen von josh (Version 2.0.0).

Jeder Bogen in tools/art_v2/src hat einen hellen Papier-Hintergrund. cut() trennt ihn ab
(Flutfüllung vom Rand aus, damit helle Stellen innerhalb der Figuren bleiben) und findet die
einzelnen Bilder als zusammenhängende Flächen. Beschriftungen fallen über ihre geringe Höhe
heraus. Aufruf zur Kontrolle: python3 tools/art_v2/cut.py <bogen> schreibt eine Übersicht
mit Nummern nach tools/preview/v2/.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
PREVIEW = os.path.join(HERE, "..", "preview", "v2")


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGB")


def bg_color(a):
    corners = np.concatenate([a[:8, :8].reshape(-1, 3), a[:8, -8:].reshape(-1, 3),
                              a[-8:, :8].reshape(-1, 3), a[-8:, -8:].reshape(-1, 3)])
    return np.median(corners, axis=0)


def paper_mask(a, tol=34.0, with_lines=False):
    """True, wo Papier (Hintergrund) ist: Farbe nah am Papier und vom Rand aus erreichbar."""
    bg = bg_color(a)
    d = np.sqrt(((a.astype(np.float32) - bg) ** 2).sum(axis=2))
    # Papier ist hell und kaum gesättigt; auch leichte Schatten unter Figuren zählen dazu
    mx = a.max(axis=2).astype(np.float32)
    mn = a.min(axis=2).astype(np.float32)
    light = (d < tol) | ((mn > 200) & (mx - mn < 40) & (d < 60))
    if with_lines:
        light |= lines(a, d)
    lab, _ = ndimage.label(light)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    paper = np.isin(lab, list(edge))
    return paper


def lines(a, d, length=400):
    """Lange, dünne Trennlinien und Rahmen der Bögen (nicht Teil der Bilder)."""
    fg = d > 12
    h = ndimage.binary_opening(fg, structure=np.ones((1, length)))
    v = ndimage.binary_opening(fg, structure=np.ones((length, 1)))
    # nur dünne Linien: dicke Flächen (Wasser, Gras) bleiben
    thin_h = h & ~ndimage.binary_opening(fg, structure=np.ones((5, length)))
    thin_v = v & ~ndimage.binary_opening(fg, structure=np.ones((length, 5)))
    return ndimage.binary_dilation(thin_h | thin_v, iterations=2)


def components(a, paper=None, min_h=34, min_area=500, merge=6, with_lines=False):
    """Bounding-Boxen (x0, y0, x1, y1) der Bilder, oben links nach unten rechts sortiert."""
    if paper is None:
        paper = paper_mask(a, with_lines=with_lines)
    fg = ~paper
    grown = ndimage.binary_dilation(fg, iterations=merge)
    lab, n = ndimage.label(grown)
    boxes = []
    for sl in ndimage.find_objects(lab):
        y0, y1 = sl[0].start, sl[0].stop
        x0, x1 = sl[1].start, sl[1].stop
        sub = fg[y0:y1, x0:x1]
        if y1 - y0 < min_h or sub.sum() < min_area:
            continue
        boxes.append((x0 + merge, y0 + merge, x1 - merge, y1 - merge))
    return sort_boxes(boxes)


def sort_boxes(boxes, row_tol=60):
    boxes = sorted(boxes, key=lambda b: (b[1] + b[3]) / 2)
    rows = []
    for b in boxes:
        cy = (b[1] + b[3]) / 2
        if rows and abs(rows[-1][0] - cy) < row_tol:
            rows[-1][1].append(b)
        else:
            rows.append([cy, [b]])
    out = []
    for _, r in rows:
        out += sorted(r, key=lambda b: b[0])
    return out


def cutout(img, box, paper=None, pad=2):
    """RGBA-Ausschnitt mit durchsichtigem Papier."""
    a = np.asarray(img)
    if paper is None:
        paper = paper_mask(a)
    x0, y0, x1, y1 = box
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(a.shape[1], x1 + pad), min(a.shape[0], y1 + pad)
    rgb = a[y0:y1, x0:x1]
    alpha = np.where(paper[y0:y1, x0:x1], 0, 255).astype(np.uint8)
    # einzelne Papierpixel am Rand weg, Löcher in der Figur schließen
    solid = ndimage.binary_opening(alpha > 0, iterations=1)
    solid = ndimage.binary_fill_holes(solid) & (alpha > 0) | ndimage.binary_fill_holes(solid) & ~_reachable_paper(paper[y0:y1, x0:x1])
    alpha = np.where(solid, 255, 0).astype(np.uint8)
    out = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
    bb = out.getbbox()
    return out.crop(bb) if bb else out


def _reachable_paper(p):
    lab, _ = ndimage.label(p)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    return np.isin(lab, list(edge))


def keep_largest(rgba, min_frac=0.02):
    """Entfernt kleine abgetrennte Reste (Beschriftungen) aus einem Ausschnitt."""
    a = np.asarray(rgba).copy()
    m = a[:, :, 3] > 0
    lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=3))
    if n <= 1:
        return rgba
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * min_frac]
    a[:, :, 3] = np.where(np.isin(lab, keep) & m, 255, 0)
    out = Image.fromarray(a, "RGBA")
    return out.crop(out.getbbox())


def preview(name, **kw):
    img = load(name)
    a = np.asarray(img)
    boxes = components(a, **kw)
    dbg = img.copy()
    d = ImageDraw.Draw(dbg)
    for i, b in enumerate(boxes):
        d.rectangle(b, outline=(255, 0, 0), width=2)
        d.text((b[0] + 3, b[1] + 3), str(i), fill=(255, 0, 255))
    os.makedirs(PREVIEW, exist_ok=True)
    dbg.save(os.path.join(PREVIEW, "boxes_" + name + ".png"))
    for i, b in enumerate(boxes):
        print(i, b, b[2] - b[0], b[3] - b[1])
    return boxes


if __name__ == "__main__":
    for n in sys.argv[1:]:
        print("==", n)
        preview(n)
