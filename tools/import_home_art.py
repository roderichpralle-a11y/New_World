#!/usr/bin/env python3
"""Register generated home-island art without redrawing the approved pixels.

Only alpha-aware extraction, uniform scaling, baseline registration and atlas
packing happen here. Full-resolution generated sources remain in art/home-v2.
"""
from pathlib import Path
from collections import deque
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'art/home-v2'
OUT = ROOT / 'assets/home_v2'
OUT.mkdir(exist_ok=True)
meta = {'revision': 2, 'scale': .25, 'objects': {}, 'characters': {}}


def components(im, minimum=600):
    mask = np.asarray(im)[:, :, 3] > 150
    seen = np.zeros(mask.shape, bool)
    h, w = mask.shape
    result = []
    for yy, xx in zip(*np.where(mask)):
        if seen[yy, xx]:
            continue
        q = deque([(int(xx), int(yy))]); seen[yy, xx] = True
        lo_x = hi_x = int(xx); lo_y = hi_y = int(yy); count = 0
        while q:
            x, y = q.popleft(); count += 1
            lo_x = min(lo_x, x); hi_x = max(hi_x, x)
            lo_y = min(lo_y, y); hi_y = max(hi_y, y)
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((nx, ny))
        if count >= minimum:
            result.append((lo_x, lo_y, hi_x + 1, hi_y + 1))
    return result


def opaque_bounds(im):
    return im.getchannel('A').point(lambda a: 255 if a > 150 else 0).getbbox()


def pack_character(name):
    im = Image.open(SRC / f'{name}-source.png').convert('RGBA')
    boxes = components(im)
    assert len(boxes) == 24, (name, len(boxes), boxes)
    atlas = Image.new('RGBA', (640, 864))
    registered = {}
    for box in boxes:
        x, y, right, bottom = box
        col = min(3, int((x + right) / 2 / (im.width / 4)))
        row = min(5, int((y + bottom) / 2 / (im.height / 6)))
        assert (col, row) not in registered, (name, col, row)
        # Include antialiased outline; keep the cell's shared body X anchor.
        rect = (max(0, x-2), max(0, y-2), min(im.width, right+2), min(im.height, bottom+2))
        part = im.crop(rect)
        part = part.resize((round(part.width / 2), round(part.height / 2)), Image.Resampling.LANCZOS)
        px = round(80 + (rect[0] - (col * 256 + 128)) / 2)
        py = 136 - part.height
        assert px >= 0 and px + part.width <= 160 and py >= 0, (name, col, row, px, py, part.size)
        atlas.alpha_composite(part, (col * 160 + px, row * 144 + py))
        registered[col, row] = {'source': list(rect), 'baseline': 136}
    atlas.save(OUT / f'{name}.png')
    meta['characters'][name] = {'frame': [160, 144], 'rows': 6, 'columns': 4,
        'anchor': [80, 136], 'source': f'{name}-source.png', 'frames': [registered[c, r] for r in range(6) for c in range(4)]}


def pack_objects():
    im = Image.open(SRC / 'nature-hut-source.png').convert('RGBA')
    # The delivered composition has unequal row heights; never pretend it is a grid.
    specs = [
        ('tree0', (0, 0, 424, 510), (256, 288), (164, 212)),
        ('tree1', (430, 0, 834, 510), (256, 288), (164, 212)),
        ('tree2', (840, 0, 1254, 510), (256, 288), (164, 212)),
        ('stump', (0, 520, 420, 838), (128, 104), (116, 88)),
        ('sapling', (440, 520, 820, 838), (128, 176), (112, 152)),
        ('bush_full', (830, 520, 1254, 838), (144, 128), (132, 100)),
        ('bush_empty', (0, 850, 402, 1254), (144, 128), (132, 100)),
        ('hut', (408, 838, 834, 1254), (320, 256), (300, 232)),
        ('hut_construction', (836, 838, 1254, 1254), (320, 256), (300, 232)),
    ]
    for name, rect, canvas, fit in specs:
        part = im.crop(rect)
        bounds = opaque_bounds(part)
        assert bounds, name
        part = part.crop(bounds)
        ratio = min(fit[0] / part.width, fit[1] / part.height)
        part = part.resize((round(part.width * ratio), round(part.height * ratio)), Image.Resampling.LANCZOS)
        target = Image.new('RGBA', canvas)
        anchor = [canvas[0] // 2, canvas[1] - 12]
        target.alpha_composite(part, (anchor[0] - part.width // 2, anchor[1] - part.height))
        target.save(OUT / f'{name}.png')
        meta['objects'][name] = {'size': list(canvas), 'anchor': anchor, 'source_rect': list(rect)}


def pack_props():
    im = Image.open(SRC / 'chop-props-source.png').convert('RGBA')
    atlas = Image.new('RGBA', (640, 128))
    for col in range(4):
        rect = (round(col * im.width / 4), 0, round((col + 1) * im.width / 4), im.height)
        part = im.crop(rect); part = part.crop(opaque_bounds(part))
        ratio = min(148 / part.width, 112 / part.height)
        part = part.resize((round(part.width * ratio), round(part.height * ratio)), Image.Resampling.LANCZOS)
        atlas.alpha_composite(part, (col * 160 + (160 - part.width) // 2, 120 - part.height))
    atlas.save(OUT / 'chop_props.png')


if __name__ == '__main__':
    for n in ['jonas', 'lena']:
        pack_character(n)
    pack_objects(); pack_props()
    Image.open(SRC / 'meadow-source.png').save(OUT / 'meadow.png')
    (OUT / 'registration.json').write_text(json.dumps(meta, indent=2))
    print('HOME ART OK:', len(meta['objects']), 'objects and 48 registered character frames')
