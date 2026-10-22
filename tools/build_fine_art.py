#!/usr/bin/env python3
"""Build the isolated fine edition. AI design boards are input, never runtime atlases.

Requires Pillow and numpy. Reproducible inputs are in art/source. Atlas coordinates
remain logical pixels; characters use 3x native resolution with registered layers.
"""
from pathlib import Path
import json, re, math, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'art/source'
OUT = ROOT / 'assets/sprites_fine'
OUT.mkdir(parents=True, exist_ok=True)
MANIFEST = {'edition': 'fein', 'version': '1.1.0', 'character_scale': 3, 'objects': {}, 'files': {}}

def blank(w, h):
    return Image.new('RGBA', (w, h))

def board_crop(name, box, size, ground=False):
    """Isolate one reference drawing; captions remain outside its crop.

    Remove the connected cream background, not bright pixels inside the drawing.
    Only the largest connected art component is retained, so detached text is gone.
    """
    im = Image.open(SRC / (name + '.png')).convert('RGBA')
    w, h = im.size
    im = im.crop(tuple(round(v * (w if i % 2 == 0 else h)) for i, v in enumerate(box)))
    a = np.array(im)
    pale = (a[:, :, 0] > 215) & (a[:, :, 1] > 208) & (a[:, :, 2] > 170)
    # Flood only background reachable from the crop boundary.
    from collections import deque
    hh, ww = pale.shape
    seen = np.zeros((hh, ww), dtype=bool)
    q = deque()
    for x in range(ww):
        if pale[0, x]: q.append((x, 0)); seen[0, x] = True
        if pale[-1, x]: q.append((x, hh-1)); seen[-1, x] = True
    for y in range(hh):
        if pale[y, 0]: q.append((0, y)); seen[y, 0] = True
        if pale[y, -1]: q.append((ww-1, y)); seen[y, -1] = True
    while q:
        x, y = q.popleft()
        for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if 0 <= nx < ww and 0 <= ny < hh and pale[ny,nx] and not seen[ny,nx]:
                seen[ny,nx] = True; q.append((nx,ny))
    a[seen, 3] = 0
    # Remove detached lettering and tiny background fragments, retaining art.
    opaque = a[:,:,3] > 0
    visited = np.zeros((hh,ww), dtype=bool); components = []
    for sy in range(hh):
        for sx in range(ww):
            if not opaque[sy,sx] or visited[sy,sx]: continue
            pts=[]; q=deque([(sx,sy)]); visited[sy,sx]=True
            while q:
                x,y=q.popleft(); pts.append((x,y))
                for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                    if 0<=nx<ww and 0<=ny<hh and opaque[ny,nx] and not visited[ny,nx]:
                        visited[ny,nx]=True; q.append((nx,ny))
            components.append(pts)
    if not components: raise ValueError('Empty reference: '+name+str(box))
    largest=max(components,key=len); keep=np.zeros((hh,ww),dtype=bool)
    for x,y in largest: keep[y,x]=True
    # Ships/objects may have legitimate disconnected small parts close to main art.
    xs,ys=zip(*largest); bounds=(min(xs),min(ys),max(xs),max(ys))
    for pts in components:
        if len(pts)>30 and all(bounds[0]<=x<=bounds[2] and bounds[1]<=y<=bounds[3] for x,y in pts):
            for x,y in pts: keep[y,x]=True
    a[~keep,3]=0
    im=Image.fromarray(a); im=im.crop(im.getbbox())
    # The material base on a design board is not a rectangular terrain decal.
    # Production footprint is fixed by the game, not perspective in the drawing.
    target=blank(*size); maxw,maxh=size[0]-4,size[1]-5
    factor=min(maxw/im.width,maxh/im.height)
    im=im.resize((max(1,round(im.width*factor)),max(1,round(im.height*factor))),Image.Resampling.LANCZOS)
    pix=np.array(im); pix[:,:,3]=np.where(pix[:,:,3]>140,255,0)
    im=Image.fromarray(pix)
    target.alpha_composite(im,((size[0]-im.width)//2,size[1]-4-im.height))
    return target

def base_atlases():
    # Rebuild small supporting sprites with micro-shading, not a missing-art fallback.
    # Large scene objects and all UI icons are subsequently replaced from design boards.
    for path in (ROOT/'assets/sprites').glob('*.png'):
        if path.name.startswith('settler_'): continue
        im=Image.open(path).convert('RGBA')
        a=np.array(im)
        yy,xx=np.indices(a.shape[:2]); opaque=a[:,:,3]>0
        # Palette-wide, deterministic material variation within existing alpha masks.
        v=((xx*13+yy*7)%7-3)
        for c in range(3):
            a[:,:,c]=np.where(opaque,np.clip(a[:,:,c].astype(int)+v,0,255),a[:,:,c])
        Image.fromarray(a).save(OUT/path.name)

def patch(atlas, region, im):
    x,y,w,h=region[:4]
    if im.size!=(w,h): raise ValueError((region,im.size))
    atlas.paste((0,0,0,0),(x,y,x+w,y+h));atlas.alpha_composite(im,(x,y))

def buildings():
    layout=json.loads((SRC/'atlas-layout-original.json').read_text())
    data=json.loads((ROOT/'data/buildings.json').read_text())
    atlas=Image.open(OUT/'buildings.png').convert('RGBA')
    specs={
      'gebaeude_wohnen_1': [(i/3,.06+(j*.45),(i+1)/3,.44+j*.45) for j in range(2) for i in range(3)],
      'gebaeude_nahrung_1': [(i/4,.05+j*.305,(i+1)/4,.33+j*.305) for j in range(2) for i in range(4)]+[(i/3,.665,(i+1)/3,.94) for i in range(3)],
      'gebaeude_handwerk_1': [(i/4,.115+j*.30,(i+1)/4,.35+j*.30) for j in range(3) for i in range(4)],
      'gebaeude_handwerk_2': [(i/3,.035+j*.36,(i+1)/3,.345+j*.36) for j in range(2) for i in range(3)]+[(.25,.735,.75,.99)],
      'gebaeude_wissen_1': [(i/4,.06+j*.31,(i+1)/4,.31+j*.31) for j in range(3) for i in range(4)],
      'gebaeude_wissen_2': [(0,.16,.5,.83),(.5,.16,1,.83)],
      'gebaeude_see_1': [(i/4,.07+j*.30,(i+1)/4,.33+j*.30) for j in range(3) for i in range(4)],
      'gebaeude_lager_1': [(0,.47,.22,.82),(.22,.24,.55,.82),(.55,.14,1,.82)],
      'gebaeude_schmuck_1': [(i/4,.07+j*.305,(i+1)/4,.32+j*.305) for j in range(3) for i in range(4)],
      'gebaeude_schmuck_2': [(i/4,.075+j*.30,(i+1)/4,.32+j*.30) for j in range(2) for i in range(4)]+[(.08,.67,.38,.94),(.38,.67,.65,.94),(.65,.67,.95,.94)],
    }
    inv=json.loads((SRC/'inventar.json').read_text())
    seen=set()
    objects=Image.open(OUT/'objects.png').convert('RGBA')
    for board,boxes in specs.items():
        items=next(p['items'] for p in inv['plan'] if p['id']==board)
        assert len(items)==len(boxes),(board,len(items),len(boxes))
        for item,box in zip(items,boxes):
            name=item['sprite']
            if name in seen: continue
            if name in layout['buildings']['entries']:
                cell,frames=layout['buildings']['entries'][name]
                im=board_crop(board,box,(64,64))
                for f in range(frames):
                    index=cell+f;patch(atlas,(index%8*64,index//8*64,64,64),im)
                MANIFEST['objects'][name]={'source':board,'frames':frames,'kind':'design-board'}
            elif name in ('hut','storehouse','campfire'):
                r=layout['objects'][name]
                if name!='campfire':patch(objects,r,board_crop(board,box,(r[2],r[3])))
                MANIFEST['objects'][name]={'source':board,'kind':'design-board'}
            seen.add(name)
    objects.save(OUT/'objects.png');atlas.save(OUT/'buildings.png')

def objects_and_icons():
    layout=json.loads((SRC/'atlas-layout-original.json').read_text())
    a=Image.open(OUT/'objects.png').convert('RGBA');b=Image.open(OUT/'objects2.png').convert('RGBA')
    # Individually registered nature references, with full-height depleted palm.
    crops={
      'tree0':(.005,.13,.125,.34),'tree1':(.125,.13,.235,.34),'tree2':(.235,.13,.345,.34),
      'stump':(.44,.225,.56,.34),'sapling':(.36,.18,.445,.34),
      'rock_big':(.55,.15,.665,.34),'rock_small':(.66,.22,.745,.34),
      'bush_full':(.74,.17,.87,.34),'bush_empty':(.87,.17,1,.34),
      'palm0':(.22,.41,.335,.65),'palm1':(.335,.41,.44,.65),'palm_empty':(.44,.41,.55,.65),
      'mushrooms':(.56,.47,.67,.65),'spice_full':(.69,.43,.85,.65),'spice_empty':(.85,.43,1,.65),
      'ore_rock':(.005,.75,.12,.92),'gold_rock':(.17,.75,.29,.92),'den':(.33,.75,.48,.92),
      'wallow':(.49,.77,.65,.92),'cave':(.66,.73,.83,.92),'carcass':(.83,.77,1,.92)}
    for name,box in crops.items():
        rs=layout['objects'] if name in layout['objects'] else layout['objects2']
        r=rs[name];im=board_crop('landschaft_rohstoffe',box,(r[2],r[3]));patch(a if name in layout['objects'] else b,r,im)
        MANIFEST['objects'][name]={'source':'landschaft_rohstoffe','kind':'design-board'}
    # No raft: rowboat is always a hull with seats and oars.
    for j,name in enumerate(['boat','ship_kogge','ship_fast','ship_galleon']):
        r=layout['objects2'][name]
        for f in range(2):
            im=board_crop('schiffe',(.25+f*.27,.015+j*.245,.52+f*.27,.225+j*.245),(r[2],r[3]))
            patch(b,(r[0]+r[2]*f,r[1],r[2],r[3]),im)
        MANIFEST['objects'][name]={'source':'schiffe','frames':2,'kind':'design-board'}
    a.save(OUT/'objects.png');b.save(OUT/'objects2.png')
    icons=blank(len(layout['icons']['order'])*16,16)
    for i,name in enumerate(layout['icons']['order']):
        board='symbole_'+str(i//24+1);k=i%24;col=k%6;row=k//6
        # Sheets 3 and 4 have no title strip; sheets 1 and 2 do.
        top=.07 if i//24<2 else .005;step=(.99-top)/4
        im=board_crop(board,(col/6,top+row*step,(col+1)/6,top+(row+.80)*step),(16,16))
        icons.alpha_composite(im,(i*16,0))
    icons.save(OUT/'icons.png')
    # Each tool gets an isolated grip-ready production sprite.
    tools=blank(14*16,16)
    for i,name in enumerate(layout['tools']['order']):
        im=board_crop('werkzeuge_transport',(i/15,.055,(i+1)/15,.175),(16,16))
        tools.alpha_composite(im,(i*16,0))
    tools.save(OUT/'tools.png')
    # Five frames per animal, no extra enemies from the design board's captions.
    animals=blank(5*24,4*24)
    for j,row in enumerate([0,1,2,6]):
        for f in range(5):
            im=board_crop('tiere_piraten',(.14+f*.17,.045+row*.133,.31+f*.17,.17+row*.133),(24,24))
            animals.alpha_composite(im,(f*24,j*24))
    animals.save(OUT/'animals.png')

def special_animations():
    """Mathematical geometry prevents flickering foundations and broken windmills."""
    layout=json.loads((SRC/'atlas-layout-original.json').read_text())
    atlas=Image.open(OUT/'buildings.png').convert('RGBA');objects=Image.open(OUT/'objects.png').convert('RGBA')
    for f in range(4):
        im=blank(64,64);d=ImageDraw.Draw(im)
        # Fixed mill tower and four exactly perpendicular blades at every phase.
        d.polygon([(19,59),(22,24),(42,24),(46,59)],fill='#ead7ae',outline='#563f32')
        d.polygon([(19,26),(32,13),(45,26)],fill='#a44d32',outline='#563325')
        d.rectangle((29,46,36,59),fill='#58402e');d.rectangle((25,31,29,37),fill='#b8d6d9')
        hub=(32,28);ang=f*math.pi/8
        for arm in range(4):
            theta=ang+arm*math.pi/2
            def pt(u,v):return (hub[0]+u*math.cos(theta)-v*math.sin(theta),hub[1]+u*math.sin(theta)+v*math.cos(theta))
            d.polygon([pt(5,-2),pt(25,-2),pt(25,3),pt(5,3)],fill='#f4dfb0',outline='#76513a')
            for u in range(8,25,4):d.line([pt(u,-2),pt(u,3)],fill='#a17a50')
        d.ellipse((29,25,35,31),fill='#8b633f',outline='#46382b')
        cell=3+f;patch(atlas,(cell%8*64,cell//8*64,64,64),im)
        # Hologram: identical plain pedestal; only figure opacity/sparkle changes.
        im=blank(64,64);d=ImageDraw.Draw(im)
        d.rectangle((24,55,40,59),fill='#596579',outline='#283343');d.line((25,55,39,55),fill='#7ecbdf')
        c=['#58cce4','#82dfef','#40a4cf','#91e8f3'][f]
        d.ellipse((29,17,36,25),fill=c);d.rectangle((28,26,37,42),fill=c)
        d.line((30,41,29,53),fill=c,width=3);d.line((35,41,37,53),fill=c,width=3)
        d.line((28,28,23,38),fill=c,width=2);d.line((37,28,42,34),fill=c,width=2)
        cell=86+f;patch(atlas,(cell%8*64,cell//8*64,64,64),im)
        # Fish ground is a transparent sea overlay: fish and low ripples only.
        im=blank(16,16);d=ImageDraw.Draw(im);x=4+f;y=7+(f%2)
        d.arc((1,4,14,13),10,130,fill='#8bcad9');d.ellipse((x,y,x+5,y+2),fill='#608ba8')
        d.polygon([(x,y+1),(x-2,y-1),(x-2,y+3)],fill='#658fa5')
        patch(objects,(64+f*16,112,16,16),im)
    # Fixed clear access to lighthouse doorway in BOTH frames.
    for f in range(2):
        cell=22+f;x=cell%8*64;y=cell//8*64
        d=ImageDraw.Draw(atlas);d.polygon([(x+29,y+51),(x+36,y+51),(x+40,y+59),(x+25,y+59)],fill='#c8b28b')
    # Work props: split wood visible from the third chopping phase, construction grows.
    props=blank(4*32,2*32)
    for f in range(4):
        d=ImageDraw.Draw(props);x=f*32
        if f<2:d.rectangle((x+11,18,x+20,27),fill='#ab7447',outline='#503627')
        else:
            for dx in (7,19):d.polygon([(x+dx,27),(x+dx+2,17),(x+dx+7,20),(x+dx+6,28)],fill='#d4a86b',outline='#745133')
        d.rectangle((x+5,58,x+27,60),fill='#77543c')
        for k in range(f+1):d.rectangle((x+7+k*5,44,x+9+k*5,58),fill='#bd8d58')
        if f>=2:d.rectangle((x+6,43,x+27,46),fill='#d0a16b')
    props.save(OUT/'work_props.png');atlas.save(OUT/'buildings.png');objects.save(OUT/'objects.png')
    MANIFEST['objects']['mill']={'frames':4,'kind':'geometry','blade_angle_step_degrees':22.5,'orthogonal_arms':True}
    MANIFEST['objects']['hologram']={'frames':4,'kind':'geometry','fixed_pedestal':True}
    MANIFEST['objects']['fish_anim']={'frames':4,'kind':'geometry','sea_only':True,'splash':False}

def characters():
    """48x72 registered tint masks: shared geometry also anchors hats in every frame."""
    acts=['walk','axe','pick','sickle','hammer','basket','rod','spoon','book','shovel','spear','sleep','eat','carry']
    names=['pants','shirt','skin','hair_0','hair_1','hair_2','fixed','fixed_bun','apron','cap','chefhat','hunthat','saw','rifle','glasses','droid']
    sheets={n:blank(48*4,72*3*len(acts)) for n in names}
    for ai,act in enumerate(acts):
      for direction in range(3):
       for frame in range(4):
        layers={n:blank(48,72) for n in names};ds={n:ImageDraw.Draw(im) for n,im in layers.items()}
        bob=1 if act=='walk' and frame%2 else 0
        hx,hy=24,20+bob
        # Hair/face assembly, front/back/side with the SAME crown anchor for hats.
        ds['skin'].rounded_rectangle((13,hy-7,35,hy+13),radius=7,fill='#fff7ed')
        ds['skin'].rectangle((20,hy+11,28,hy+18),fill='#ddd5c8')
        for style in range(3):
            d=ds['hair_'+str(style)]
            d.rounded_rectangle((10,hy-14,36,hy+2),radius=7,fill='#dbc8ad')
            d.polygon([(10,hy-3),(15,hy-12),(34,hy-14),(27,hy-5),(18,hy-1),(12,hy+6)],fill='#eee0ca')
            d.rectangle((10,hy-1,13,hy+10),fill='#ab9479')
            if direction==1:d.rounded_rectangle((11,hy-10,36,hy+12),radius=7,fill='#cbb69a')
            if style==1:d.rectangle((9,hy,14,hy+20),fill='#bca388');d.rectangle((33,hy+1,37,hy+20),fill='#cbb69a')
            if style==2:d.ellipse((20,hy-20,31,hy-10),fill='#d8c3a6')
        if direction!=1:
            for ex in ([19,29] if direction==0 else [29]):ds['fixed'].rectangle((ex,hy+2,ex+2,hy+5),fill='#32282a')
            ds['fixed'].line((23,hy+9,27,hy+9),fill='#9d6660')
        ds['shirt'].polygon([(15,hy+15),(32,hy+15),(36,hy+30),(12,hy+30)],fill='#ebeff4',outline='#87919b')
        ds['shirt'].polygon([(19,hy+14),(24,hy+20),(28,hy+14)],fill='#b3bbc4')
        ds['shirt'].line((25,hy+21,25,hy+28),fill='#c4ccd4')
        stride=[-3,0,3,0][frame] if act=='walk' else 0
        for lx,off in [(15,stride),(25,-stride)]:
            ds['pants'].polygon([(lx,hy+30),(lx+8,hy+30),(lx+8+off,hy+43),(lx+off,hy+43)],fill='#d1c1b0',outline='#8d7c6c')
            ds['fixed'].rounded_rectangle((lx+off-1,hy+42,lx+off+9,hy+47),radius=2,fill='#564236',outline='#332c2a')
        ds['fixed'].rectangle((14,hy+29,33,hy+32),fill='#70503b');ds['fixed'].rectangle((23,hy+29,26,hy+32),fill='#dcb366')
        # Hands follow action geometry, rather than hovering tool sprites.
        left=(11,hy+27);right=(36,hy+27)
        if act in ('axe','pick','hammer','sickle','shovel','spear'):
            lift=[-11,-16,4,7][frame]
            left=(31,hy+18+lift);right=(37,hy+21+lift)
        elif act in ('basket','book','carry','eat','spoon','rod'):
            left=(19,hy+25-(frame%2));right=(35,hy+23-(frame%2))
        for start,end in [((15,hy+18),left),((31,hy+18),right)]:
            ds['shirt'].line((start,end),fill='#d1d9e1',width=6)
            ds['skin'].rounded_rectangle((end[0]-2,end[1]-2,end[0]+2,end[1]+3),radius=1,fill='#fff1df')
        # Equipment uses the common crown and shoulder coordinates, never free offsets.
        ds['cap'].pieslice((9,hy-17,38,hy+2),180,360,fill='#c89536',outline='#674e2c');ds['cap'].rectangle((8,hy-7,39,hy-4),fill='#e1b957')
        ds['chefhat'].rounded_rectangle((13,hy-20,35,hy-6),radius=5,fill='#fff8e8',outline='#b7b0a4');ds['chefhat'].rectangle((13,hy-9,35,hy-4),fill='#e9e5db')
        ds['hunthat'].polygon([(7,hy-5),(14,hy-17),(31,hy-17),(39,hy-5)],fill='#577346',outline='#35432e');ds['hunthat'].line((30,hy-13,35,hy-23),fill='#b16e46',width=3)
        ds['apron'].rectangle((16,hy+20,32,hy+38),fill='#8f969e',outline='#505965');ds['apron'].line((19,hy+15,18,hy+23),fill='#c3c8ca',width=2)
        ds['rifle'].line((10,hy+35,35,hy+3),fill='#4e4b49',width=3);ds['rifle'].line((9,hy+36,19,hy+23),fill='#90653e',width=4)
        ds['saw'].rounded_rectangle((27,hy+25,38,hy+34),radius=2,fill='#cc7f36',outline='#473f39');ds['saw'].rounded_rectangle((36,hy+27,46,hy+31),radius=2,fill='#c2c7cc',outline='#555f68')
        ds['droid'].rounded_rectangle((11,hy-13,37,hy+11),radius=5,fill='#b9bdc5',outline='#505865');ds['droid'].rectangle((16,hy-4,33,hy+4),fill='#344c62')
        ds['droid'].rectangle((19,hy-1,22,hy+2),fill='#89dded');ds['droid'].rectangle((28,hy-1,30,hy+2),fill='#89dded')
        ds['droid'].rounded_rectangle((14,hy+14,34,hy+34),radius=3,fill='#b7a278',outline='#585c65')
        for x in [13,31]:ds['droid'].rectangle((x,hy+34,x+5,hy+46),fill='#636d78')
        if act=='sleep':
            # Ground sleeping only; indoor sleepers are hidden by the game.
            for n,im in layers.items():
                box=im.getbbox()
                if box:
                    rot=im.crop(box).rotate(90,expand=True);out=blank(48,72);rot.thumbnail((45,25));out.alpha_composite(rot,((48-rot.width)//2,65-rot.height));layers[n]=out
        layers['fixed_bun'] = layers['fixed'].copy()
        for n,im in layers.items():sheets[n].alpha_composite(im,(frame*48,(ai*3+direction)*72))
    for n,im in sheets.items():im.save(OUT/('settler_'+n+'.png'))
    (OUT/'character_actions.json').write_text(json.dumps({'actions':acts,'frame':[48,72],'columns':4,'rows':len(acts)*3,'scale':3},indent=2))

def interface_and_terrain():
    # Nine-slice UI geometry is deliberately authored, never cut from a labelled card.
    ui=blank(96,24);d=ImageDraw.Draw(ui)
    for i in range(4):
        x=i*24;paper=i==0
        d.rounded_rectangle((x,0,x+23,23),radius=3,fill='#51382b',outline='#33282a')
        d.rectangle((x+2,2,x+21,21),fill=('#d8b77b' if paper else ['#aa743b','#c99049','#85572e'][i-1]))
        d.line((x+3,3,x+20,3),fill='#efd19b');d.line((x+3,20,x+20,20),fill='#775039')
        if paper:d.rectangle((x+6,6,x+17,17),fill='#f1dfb0')
        else:
            for y in (7,13,18):d.line((x+5,y,x+18,y),fill='#b88144' if i!=3 else '#916335')
    ui.save(OUT/'ui.png')
    bars=blank(128,128);d=ImageDraw.Draw(bars)
    def bar(box,pressed=False,track=False):
        d.rounded_rectangle(box,radius=3,fill='#3f2c27',outline='#201d22')
        x,y,r,b=box
        d.rectangle((x+3,y+3,r-3,b-3),fill='#614632' if track else '#b88648' if not pressed else '#8c6036')
        if not track:
            d.line((x+5,y+4,r-4,y+4),fill='#efd09a')
            if b-y>r-x:
                cy=(y+b)//2
                for dy in (-5,0,5):d.line((x+6,cy+dy,r-6,cy+dy),fill='#e2bd7e',width=2)
            else:
                cx=(x+r)//2
                for dx in (-5,0,5):d.line((cx+dx,y+6,cx+dx,b-6),fill='#e2bd7e',width=2)
    bar((0,0,23,63),track=True);bar((24,0,47,47));bar((48,0,71,47),pressed=True)
    bar((0,96,63,119),track=True);bar((0,72,47,95));bar((64,72,111,95),pressed=True)
    bars.save(OUT/'scrollbars.png')
    icons=Image.open(OUT/'icons.png');order=(ROOT/'assets/sprites/icons.txt').read_text().split()
    menu=blank(120,20)
    for i,n in enumerate(['haus','wissen','person','kompass','menu','maschinen']):
        j=order.index(n);menu.alpha_composite(icons.crop((j*16,0,j*16+16,16)).resize((20,20),Image.Resampling.NEAREST),(i*20,0))
    menu.save(OUT/'menu_icons.png')
    # All cart directions share a registered canvas and ground baseline.
    cart=blank(96,144)
    for row in range(6):
        direction=row%3;front=row>=3
        for f in range(4):
            im=blank(24,24);q=ImageDraw.Draw(im)
            if direction==2:
                if not front:
                    q.rectangle((6,8,22,16),fill='#9b713f',outline='#4c382a');q.line((0,11,7,11),fill='#6b4c30',width=2)
                    q.ellipse((12,14,20,22),fill='#5f452f',outline='#362b25')
                    angle=f*math.pi/8
                    for k in range(4):
                        a=angle+k*math.pi/2;q.line((16,18,16+int(3*math.cos(a)),18+int(3*math.sin(a))),fill='#c29860')
                else:q.rectangle((7,13,22,15),fill='#b58549',outline='#57402d')
            else:
                if not front:
                    q.rectangle((5,5,18,16),fill='#b08348',outline='#58402d')
                    q.line((3,2,3,21),fill='#805c34',width=2);q.line((20,2,20,21),fill='#805c34',width=2)
                    for y in (8,12):q.line((6,y,17,y),fill='#775136')
                else:q.rectangle((5,13,18,16),fill='#c69656',outline='#58402d')
            cart.alpha_composite(im,(f*24,row*24))
    cart.save(OUT/'cart.png')

def construction_frames():
    layout=json.loads((SRC/'atlas-layout-original.json').read_text())
    atlas=Image.open(OUT/'buildings.png').convert('RGBA')
    out=blank(5*4*64,16*64)
    index={}
    for row,(name,(cell,frames)) in enumerate(layout['buildings']['entries'].items()):
        im=atlas.crop((cell%8*64,cell//8*64,cell%8*64+64,cell//8*64+64))
        for stage in range(4):
            dst=blank(64,64);height=[10,23,39,56][stage]
            dst.alpha_composite(im.crop((0,64-height,64,64)),(0,64-height))
            d=ImageDraw.Draw(dst)
            for x in (10,51):d.line((x,60-height,x,60),fill='#8d663f',width=2)
            d.line((8,61-height,53,61-height),fill='#c39a61',width=2)
            out.alpha_composite(dst,((row//16)*256+stage*64,(row%16)*64))
        index[name]=row
    out.save(OUT/'construction.png');(OUT/'construction_index.json').write_text(json.dumps(index))

def main():
    base_atlases();buildings();objects_and_icons();special_animations();characters();interface_and_terrain();construction_frames()
    (OUT/"icons.txt").write_text((ROOT/"assets/sprites/icons.txt").read_text())
    for p in sorted(OUT.glob('*.png')):
        im=Image.open(p);im.verify()
        MANIFEST['files'][p.name]={'size':Image.open(p).size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
    (OUT/'manifest.json').write_text(json.dumps(MANIFEST,indent=2))
    print('Fine production assets:',len(MANIFEST['files']))

if __name__=='__main__':main()
