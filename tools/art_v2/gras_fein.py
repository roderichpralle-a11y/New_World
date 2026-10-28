import numpy as np, random, sys, math
from PIL import Image, ImageDraw
W = 512  # 8x8 Kacheln zu 64 HD-Pixeln, 1 HD-Pixel = Viertel-Spielpixel
BASE = (126, 176, 52)
rs = np.random.RandomState(57); rnd = random.Random(99)
fy = np.fft.fftfreq(W)[:, None]; fx = np.fft.fftfreq(W)[None, :]
r = np.sqrt(fx**2 + fy**2)
f = np.real(np.fft.ifft2(np.fft.fft2(rs.randn(W, W)) * np.exp(-(r/0.015)**2))); f /= f.std()
g = np.real(np.fft.ifft2(np.fft.fft2(rs.randn(W, W)) * np.exp(-(r/0.08)**2))); f += 0.35 * g / g.std()
# Dither (Bayer 4x4) für weiche Übergänge in Pixel-Art
bay = np.array([[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]) / 16.0 - 0.5
fd = f + 0.35 * np.tile(bay, (W//4, W//4))
tones = [(-1.5,(100,154,44)),(-0.8,(112,166,48)),(0.0,BASE),(0.75,(138,188,58)),(1.4,(152,198,66))]
a = np.zeros((W, W, 3), np.uint8); a[:] = BASE
for th,c in tones:
    if th < 0: a[fd < th] = c
for th,c in tones:
    if th > 0: a[fd > th] = c
img = Image.fromarray(a, "RGB").convert("RGBA")
px = img.load()
def put(x,y,c,al=255):
    x%=W; y%=W
    if al<255:
        o=px[x,y]; t=al/255; c=tuple(int(o[i]*(1-t)+c[i]*t) for i in range(3))
    px[x,y]=c+(255,)
SH = [(58,110,34),(78,134,40),(98,156,46),(124,182,56),(152,204,72),(184,222,98)]
def blade(x,y,ln,lean,light):
    for k in range(ln):
        t=k/max(1,ln-1)
        xx=x+int(round(lean*t*t*ln/6))
        i=min(5,int(t*(4 if not light else 5.2))+ (0 if light else 0))
        put(xx,y-k,SH[i])
def tuft(x,y,big=False):
    n=rnd.randint(5,9) if big else rnd.randint(3,6)
    light = f[y%W,x%W] > 0.2
    for b in range(n):
        bx=x+rnd.randint(-3,3); ln=rnd.randint(6,13) if big else rnd.randint(4,8)
        blade(bx,y+rnd.randint(-1,1),ln,rnd.uniform(-3,3),light or b%2==0)
# kleine Halme überall
for _ in range(W*W//200): tuft(rnd.randrange(W),rnd.randrange(W))
for _ in range(W*W//700): tuft(rnd.randrange(W),rnd.randrange(W),True)
# Blumen
PET=[((252,252,246),(214,214,206)),((252,218,70),(214,170,40)),((240,140,176),(196,96,136)),((150,174,244),(104,124,206)),((250,120,90),(200,80,60))]
def flower(x,y):
    p,ps=rnd.choice(PET)
    for k in range(2,9): put(x,y+k,SH[1+(k%2)])
    for (lx,ly) in ((x+1,y+6),(x+2,y+5),(x-1,y+7),(x-2,y+6)): put(lx,ly,SH[3])
    for dx,dy in ((0,-3),(3,-1),(2,2),(-2,2),(-3,-1)):
        for ex,ey in ((0,0),(1,0),(0,1),(1,1)):
            put(x+dx+ex-0,y+dy+ey-0,p if (ex,ey)!=(1,1) else ps)
    for ex,ey in ((0,0),(1,0),(0,1),(1,1)):
        put(x+ex,y+ey-1,(248,200,60) if (ex,ey)==(0,0) else (226,160,40))
for _ in range(W*W//5000): flower(rnd.randrange(W),rnd.randrange(W))
img.save(sys.argv[1])
