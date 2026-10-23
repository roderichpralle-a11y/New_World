#!/usr/bin/env python3
"""Production asset registration checks for the first home-island revision."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/home_v2'
meta = json.loads((ART / 'registration.json').read_text())
assert len(meta['objects']) == 9
for name, entry in meta['objects'].items():
    im = Image.open(ART / f'{name}.png')
    assert im.mode == 'RGBA' and list(im.size) == entry['size'], name
    assert im.getpixel((0, 0))[3] == 0, ('opaque background', name)
    box = im.getchannel('A').point(lambda a: 255 if a > 150 else 0).getbbox()
    assert box and box[3] <= entry['anchor'][1] + 1, ('ground anchor', name)
for name in ['lena', 'jonas']:
    im = Image.open(ART / f'{name}.png')
    assert im.size == (640, 864) and im.mode == 'RGBA', name
    assert len(meta['characters'][name]['frames']) == 24
    for row in range(6):
        phases = []
        for col in range(4):
            frame = im.crop((col*160, row*144, (col+1)*160, (row+1)*144))
            box = frame.getchannel('A').point(lambda a: 255 if a > 150 else 0).getbbox()
            assert box and box[0] > 0 and box[2] < 160 and box[3] <= 136, (name, row, col, box)
            phases.append(frame.tobytes())
        assert len(set(phases)) >= 2, ('static animation', name, row)
props = Image.open(ART / 'chop_props.png')
assert props.size == (640, 128)
assert props.crop((160, 0, 320, 128)).tobytes() != props.crop((320, 0, 480, 128)).tobytes(), 'split wood missing'
meadow = Image.open(ART / 'meadow.png')
assert min(meadow.size) >= 1024 and len(meadow.getcolors(meadow.width * meadow.height)) > 200
print('HOME ART OK: transparent objects, 48 complete registered frames, split wood and detailed meadow')
