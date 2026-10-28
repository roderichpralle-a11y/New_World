from PIL import Image, ImageDraw
import random, sys
random.seed(4)
U=4  # ein Kunstpixel = 4 Bildpixel (wie josh's Bögen)
W,H=60,62
im=Image.new("RGBA",(W,H),(0,0,0,0)); px=im.load()
def put(x,y,c):
    if 0<=x<W and 0<=y<H: px[x,y]=c+(255,) if len(c)==3 else c
def rect(x0,y0,x1,y1,c):
    for y in range(y0,y1+1):
        for x in range(x0,x1+1): put(x,y,c)
OUT=(46,30,20)
# Boden: Grasfleck mit Weg
for y in range(50,62):
    for x in range(1,59):
        dx=(x-29.5)/29.0; dy=(y-55.5)/6.2
        if dx*dx+dy*dy<=1.0:
            c=(98,168,52) if (x*7+y*3)%11 else (120,186,64)
            if dy>0.55: c=(196,160,96) if dx*dx+dy*dy>0.85 else c
            put(x,y,c)
for y in range(52,62):
    w=6+(y-52)//2
    for x in range(26-w//2,26+w//2+1):
        if px[x,y][3]: put(x,y,(206,172,110) if (x+y)%5 else (190,154,96))
# Wände: liegende Bohlen
X0,X1,Y0,Y1=8,51,26,53
for y in range(Y0,Y1+1):
    for x in range(X0,X1+1):
        band=(y-Y0)%4
        c=(150,98,56) if band in (0,1) else (132,84,46)
        if band==3: c=(96,60,34)
        if (x*13+y*7)%17==0: c=(112,72,40)
        put(x,y,c)
for y in range(Y0,Y1+1):
    put(X0,y,OUT); put(X1,y,OUT)
    for x in (X0+1,X0+2,X1-2,X1-1): put(x,y,(104,64,36))
rect(X0,Y1,X1,Y1,OUT)
# Tor (zweiflügelig, höher als ein Siedler)
D0,D1,DT=20,33,29
rect(D0-1,DT-1,D1+1,Y1,OUT)
for y in range(DT,Y1):
    for x in range(D0,D1+1):
        c=(118,74,40) if (x-D0)%3 else (96,58,32)
        put(x,y,c)
for x in range(D0,D1+1): put(x,DT+4,(70,44,26)); put(x,Y1-5,(70,44,26))
for y in range(DT,Y1): put((D0+D1)//2,y,OUT)
for i in range(D1-D0):  # Querstrebe
    put(D0+i, Y1-5-int(i*(Y1-DT-9)/(D1-D0)), (84,52,30))
put((D0+D1)//2-1,DT+12,(220,190,90)); put((D0+D1)//2+1,DT+12,(220,190,90))
# Fenster
for wx in (11,40):
    rect(wx-1,32,wx+6,38,OUT)
    rect(wx,33,wx+5,37,(255,206,92))
    rect(wx,33,wx+5,33,(255,232,150))
    for y in range(33,38): put(wx+2,y,(120,80,40)); put(wx+3,y,(120,80,40))
    for x in range(wx,wx+6): put(x,35,(120,80,40))
# Schornstein
rect(42,4,47,14,(128,128,134)); 
for y in range(4,15):
    put(42,y,(70,70,78)); put(47,y,(70,70,78))
    if y%3==0:
        for x in range(43,47): put(x,y,(100,100,108))
rect(41,3,48,4,(90,90,98))
# Dach aus grünem Stroh: Walm von vorn, Reihen mit Fransen
G=[(40,78,30),(62,112,40),(88,146,52),(118,176,66),(156,202,90)]
RT,RB=7,27   # Firstzeile, Traufe
for y in range(RT,RB+1):
    t=(y-RT)/(RB-RT)
    l=int(round(18-t*14)); r=int(round(41+t*14))
    for x in range(l,r+1):
        row=(y-RT)//4
        k=(y-RT)%4
        c=G[2]
        if k==0: c=G[3]
        if k==3: c=G[1]
        if (x*5+row*3)%7==0 and k>=2: c=G[1]
        if (x*3+y)%9==0 and k==1: c=G[4]
        put(x,y,c)
    put(l,y,G[0]); put(r,y,G[0])
    if y==RT:
        for x in range(l,r+1): put(x,y,G[0])
# Fransen an der Traufe
for x in range(4,56):
    n=1+((x*7)%3)
    for d in range(n):
        put(x,RB+1+d,G[1] if d==0 else G[0])
# First-Bündel
for x in range(18,42):
    put(x,RT-1,G[0]);
    if x%3==0: put(x,RT-2,G[0])
# Schornstein vor dem Dach wieder zeichnen (steht auf dem Dach)
rect(42,4,47,10,(128,128,134))
for y in range(4,11): put(42,y,(70,70,78)); put(47,y,(70,70,78))
rect(41,3,48,4,(90,90,98))
# Kisten, Fass, Sack
def crate(x,y,w,h):
    rect(x,y,x+w,y+h,OUT); rect(x+1,y+1,x+w-1,y+h-1,(160,110,62))
    for i in range(1,w): put(x+i,y+1+int((i-1)*(h-2)/max(1,w-2)),(110,70,38))
    rect(x+1,y+1,x+w-1,y+1,(186,136,82))
crate(3,44,8,8); crate(5,38,6,6)
def barrel(x,y):
    rect(x,y,x+6,y+9,OUT); rect(x+1,y+1,x+5,y+8,(150,92,50))
    for yy in (y+2,y+7): rect(x+1,yy,x+5,yy,(90,90,96))
    rect(x+2,y+1,x+2,y+8,(176,116,66))
barrel(46,44)
# Sack
for y in range(46,53):
    for x in range(37,44):
        dx=(x-40)/3.6; dy=(y-49.5)/3.6
        if dx*dx+dy*dy<1.0: put(x,y,(214,196,150) if dx<0.2 else (186,166,120))
put(40,45,(150,130,90))
big=im.resize((W*U,H*U),Image.NEAREST)
big.save(sys.argv[1])
