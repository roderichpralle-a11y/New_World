#!/usr/bin/env python3
"""Register COMPLETE walking pictures, without extracting or painting limbs.

Input: a checked 2-by-2 sheet of COMPLETE figures per founder. One uniform
scale for the whole sheet and shared head/ground anchors preserve proportions.
"""
from pathlib import Path
from PIL import Image
import numpy as np
import json
from import_home_art import components

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'assets/walk_v4'
OUT.mkdir(exist_ok=True)


def bounds(im):
    return im.getchannel('A').point(lambda a: 255 if a>150 else 0).getbbox()


def head_center(im, box):
    x,y,r,b=box
    top=im.crop((x,y,r,round(y+(b-y)*.43)))
    a=np.asarray(top.getchannel('A'))>150
    ys,xs=np.where(a)
    assert len(xs)
    return x+float(np.mean(xs))


def register(name):
    reference=Image.open(ROOT/f'art/walk-v4/reference-{name}.png').convert('RGBA')
    ref=bounds(reference)
    ref_head=head_center(reference,ref)
    source=ROOT/f'art/walk-v4/{name}-walk-source.png'
    im=Image.open(source).convert('RGBA')
    boxes=components(im)
    assert len(boxes)==4,(name,'expected four complete figures',len(boxes))
    ratio=(ref[3]-ref[1])/float(np.median([b-y for x,y,r,b in boxes]))
    atlas=Image.new('RGBA',(640,144))
    records={}
    for box in boxes:
        x,y,r,b=box
        col=min(1,int((x+r)/2/(im.width/2)))
        row=min(1,int((y+b)/2/(im.height/2)))
        index=row*2+col
        assert index not in records
        rect=(max(0,x-2),max(0,y-2),min(im.width,r+2),min(im.height,b+2))
        part=im.crop(rect)
        part=part.resize((round(part.width*ratio),round(part.height*ratio)),Image.Resampling.LANCZOS)
        px=round(ref_head+(rect[0]-head_center(im,box))*ratio)
        py=136-part.height
        assert px>0 and py>0 and px+part.width<160, (name,index,px,py,part.size)
        atlas.alpha_composite(part,(index*160+px,py))
        records[index]={'source':str(source.relative_to(ROOT)),'source_rect':list(rect),'placement':[px,py],'uniform_scale':ratio}
    atlas.save(OUT/f'{name}.png')
    return {'frame':[160,144],'columns':4,'rows':1,'ground_anchor':[80,136],
        'complete_figures':True,'frames':[records[i] for i in range(4)]}


if __name__=='__main__':
    data={name:register(name) for name in ['jonas','lena']}
    (OUT/'registration.json').write_text(json.dumps(data,indent=2)+'\n')
    print('Eight complete walking pictures registered without limb layers')
