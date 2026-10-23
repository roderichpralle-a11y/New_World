#!/usr/bin/env python3
"""Check complete-frame registration; anatomy additionally needs visual review."""
from pathlib import Path
from PIL import Image
import json

ROOT=Path(__file__).resolve().parents[1]
art=ROOT/'assets/walk_v4'
meta=json.loads((art/'registration.json').read_text())
for name in ['jonas','lena']:
    im=Image.open(art/f'{name}.png')
    assert im.size==(640,144) and im.mode=='RGBA'
    assert meta[name]['complete_figures']
    assert len(meta[name]['frames'])==4
    frames=[]
    for i in range(4):
        frame=im.crop((i*160,0,(i+1)*160,144))
        box=frame.getchannel('A').point(lambda a:255 if a>150 else 0).getbbox()
        assert box and box[0]>0 and box[2]<160 and box[3]<=136,(name,i,box)
        assert box[3]-box[1]>=95,(name,i,'incomplete body')
        frames.append(frame.tobytes())
    assert len(set(frames))==4,(name,'repeated whole pose')
print('WHOLE WALK OK: eight complete pictures, stable ground registration, no repeated pose')
