#!/usr/bin/env python3
"""Validate actual production images and regressions, not just the design inventory."""
from pathlib import Path
import json,re
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/sprites_fine'
layout=json.loads((ROOT/'art/source/atlas-layout-original.json').read_text())
manifest=json.loads((ART/'manifest.json').read_text())
for path in ART.glob('*.png'):
    with Image.open(path) as im:im.verify()
    with Image.open(path) as im:
        assert im.mode=='RGBA',path
        assert im.getbbox() is not None or path.name=='settler_glasses.png',path
for p in (ROOT/'scripts').rglob('*.gd'):
    assert 'res://assets/sprites/' not in p.read_text(),p
atlas=Image.open(ART/'buildings.png')
def building(name,frame=0):
    i=layout['buildings']['entries'][name][0]+frame
    return atlas.crop((i%8*64,i//8*64,i%8*64+64,i//8*64+64))
for name,(i,n) in layout['buildings']['entries'].items():
    for frame in range(n):assert building(name,frame).getbbox(),(name,frame)
for frame in range(1,4):
    assert building('hologram',frame).crop((0,55,64,64)).tobytes()==building('hologram').crop((0,55,64,64)).tobytes(),'Hologram foundation changed'
for name,entry in manifest['objects'].items():
    assert entry['kind'] in ['design-board','geometry'],name
assert manifest['objects']['mill']['orthogonal_arms']
assert manifest['objects']['fish_anim']['splash'] is False
objects=np.array(Image.open(ART/'objects.png'))
fish=objects[112:128,64:128]
assert not np.any((fish[:,:,1]>fish[:,:,2]+15)&(fish[:,:,3]>0)),'Fish ground contains grass'
props=np.array(Image.open(ART/'work_props.png'))
assert not np.array_equal(props[:32,32:64],props[:32,64:96]),'No split log from phase three'
assert not np.array_equal(props[32:64,:32],props[32:64,96:128]),'No building progress'
for name in ['pants','shirt','skin','hair_0','hair_1','hair_2','fixed','fixed_bun','apron','cap','chefhat','hunthat','saw','rifle','droid']:
    im=Image.open(ART/f'settler_{name}.png')
    assert im.size==(192,3024),(name,im.size)
    assert im.getbbox(),name
# Check headgear overlaps the crown of the matching head/hair mask in every walk phase.
hair=np.array(Image.open(ART/'settler_hair_0.png'))[:,:,3]>0
for name in ['cap','chefhat','hunthat']:
    mask=np.array(Image.open(ART/f'settler_{name}.png'))[:,:,3]>0
    for row in range(3):
        for f in range(4):
            r=np.s_[row*72:(row+1)*72,f*48:(f+1)*48]
            assert np.any(mask[r]&hair[r]),('floating hat',name,row,f)
assert (ART/'icons.txt').read_text().split()==layout['icons']['order']
assert Image.open(ART/'icons.png').width==93*16
for family,row in [('road',0),('dike',16),('fence',48),('gravel',64),('bricks',80),('hedge',96)]:
    im=Image.open(ART/'objects3.png')
    for m in range(16):assert im.crop((m*16,row,m*16+16,row+16)).getbbox(),(family,m)
print('FEIN ART OK: atlas regions, hats, 93 icons, 96 connections, sea-only fish, fixed foundations and work phases')
