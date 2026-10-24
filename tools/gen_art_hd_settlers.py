"""Detailreichere Siedler (josh 2026-10-23): Figuren in dreifacher Auflösung mit Gelenk-Gerüst.

Eine Figur ist ein kleines 3D-Gerüst (Hüfte, Rumpf, Kopf, Arme, Beine), das je Bild in eine Pose
gestellt und von vorn, hinten oder der Seite gezeichnet wird. Jede Fläche bekommt eine Schattierung
(Licht von oben links) und eine eigene dunkle Kontur. Ergebnis je Pixel: Ebene (Haut, Haar, Hemd,
Hose, fest, Werkzeug) und Helligkeitsstufe; so lässt sich jede Ebene später einfärben.

Koordinaten in Einheiten (1 Einheit = 1 alter Pixel, Figur 24 Einheiten hoch), x = linke Seite der
Figur, y = oben, z = vorn. Ansichten: "down" (zur Kamera), "up" (von hinten), "side" (nach rechts).
"""
import math

from PIL import Image

S = 3  # Pixel je Einheit
FW, FH = 64, 84  # Bildgröße
OX, OY = 32, 80  # Fußpunkt im Bild

# Helligkeitsstufen: 0 Kontur, 1 tiefer Schatten, 2 Schatten, 3 Grundton, 4 Licht
LIGHT = (-0.45, 0.5, 0.74)  # Lichtrichtung auf dem Bildschirm (x, y nach oben, z zur Kamera)


def _norm(v):
    l = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / l for c in v)


LIGHT = _norm(LIGHT)


def rot_x(p, a):
    """Dreht um die x-Achse (vorbeugen: +a kippt y nach +z)."""
    x, y, z = p
    c, s = math.cos(a), math.sin(a)
    return (x, y * c - z * s, y * s + z * c)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def limb_dir(fwd, abd, side):
    """Richtung eines Glieds: fwd = Schwung nach vorn (rad), abd = seitlich abgespreizt."""
    ca = math.cos(abd)
    return (math.sin(abd) * side, -math.cos(fwd) * ca, math.sin(fwd) * ca)


class Canvas:
    """Zeichenfläche: je Pixel (Tiefe, Ebene, Stufe, Gruppe)."""

    def __init__(self, view):
        self.view = view
        self.px = {}

    def proj(self, p):
        x, y, z = p
        if self.view == "down":
            sx, d = x, z
        elif self.view == "up":
            sx, d = -x, -z
        else:
            sx, d = z, -x
        return OX + sx * S, OY - y * S, d

    def put(self, x, y, depth, layer, shade, group, force=False):
        if not (0 <= x < FW and 0 <= y < FH):
            return
        old = self.px.get((x, y))
        if old is None or depth >= old[0] or force:
            self.px[(x, y)] = (depth, layer, shade, group)

    # --- Grundformen -------------------------------------------------------------------------
    def capsule(self, a, b, r, layer, group, dbias=0.0, shade_fn=None, r2=None):
        """Glied von a nach b (3D), Radius r (am Ende r2). Schattierung wie ein Zylinder."""
        ax, ay, ad = self.proj(a)
        bx, by, bd = self.proj(b)
        r2 = r if r2 is None else r2
        rp, rp2 = r * S, r2 * S
        x0 = int(min(ax, bx) - max(rp, rp2) - 1)
        x1 = int(max(ax, bx) + max(rp, rp2) + 2)
        y0 = int(min(ay, by) - max(rp, rp2) - 1)
        y1 = int(max(ay, by) + max(rp, rp2) + 2)
        dx, dy = bx - ax, by - ay
        ll = dx * dx + dy * dy
        for y in range(y0, y1):
            for x in range(x0, x1):
                cx, cy = x + 0.5, y + 0.5
                t = 0.0 if ll < 1e-6 else max(0.0, min(1.0, ((cx - ax) * dx + (cy - ay) * dy) / ll))
                qx, qy = ax + dx * t, ay + dy * t
                rr = rp + (rp2 - rp) * t
                ox, oy = cx - qx, cy - qy
                dist = math.hypot(ox, oy)
                if dist > rr:
                    continue
                # Normale: quer zum Glied, nach außen gewölbt
                nz = math.sqrt(max(0.0, 1.0 - (dist / rr) ** 2))
                nx, ny = (ox / rr, -oy / rr)
                lum = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
                sh = shade_fn(lum, t) if shade_fn else lum_to_shade(lum)
                self.put(x, y, ad + (bd - ad) * t + dbias, layer, sh, group)

    def ellipse(self, c, rx, ry, layer, group, dbias=0.0, clip=None, flat=False, bias=0.0, rz=0.0):
        cx, cy, d = self.proj(c)
        rxp, ryp = rx * S, ry * S
        for y in range(int(cy - ryp - 1), int(cy + ryp + 2)):
            for x in range(int(cx - rxp - 1), int(cx + rxp + 2)):
                u, v = (x + 0.5 - cx) / rxp, (y + 0.5 - cy) / ryp
                q = u * u + v * v
                if q > 1.0:
                    continue
                if clip and not clip(u, v):
                    continue
                nz = math.sqrt(max(0.0, 1.0 - q))
                lum = 0.5 if flat else u * LIGHT[0] - v * LIGHT[1] + nz * LIGHT[2] + bias
                self.put(x, y, d + dbias + nz * rz, layer, lum_to_shade(lum), group)

    def poly(self, pts3, layer, group, dbias=0.0, shade=3):
        pts = [self.proj(p) for p in pts3]
        d = sum(p[2] for p in pts) / len(pts)
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)) - 1, int(max(ys)) + 2):
            for x in range(int(min(xs)) - 1, int(max(xs)) + 2):
                if _inside(x + 0.5, y + 0.5, pts):
                    self.put(x, y, d + dbias, layer, shade, group)

    def line(self, a, b, layer, shade, group, dbias=0.0):
        ax, ay, ad = self.proj(a)
        bx, by, bd = self.proj(b)
        n = int(max(abs(bx - ax), abs(by - ay))) + 1
        for i in range(n + 1):
            t = i / max(1, n)
            self.put(int(ax + (bx - ax) * t), int(ay + (by - ay) * t), ad + (bd - ad) * t + dbias, layer, shade, group)

    def dot(self, p, layer, shade, group, dbias=0.0, dx=0, dy=0):
        x, y, d = self.proj(p)
        self.put(int(x) + dx, int(y) + dy, d + dbias, layer, shade, group, force=True)


def _inside(x, y, pts):
    ins = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i][0], pts[i][1]
        xj, yj = pts[j][0], pts[j][1]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
            ins = not ins
        j = i
    return ins


def lum_to_shade(lum):
    if lum > 0.9:
        return 4
    if lum > 0.42:
        return 3
    if lum > 0.05:
        return 2
    return 1


# ------------------------------------------------------------------------------------- Pose
class Pose:
    def __init__(self, **kw):
        self.lean = 0.0  # Oberkörper nach vorn (Grad)
        self.twist = 0.0
        self.bob = 0.0
        self.head_nod = 0.0  # Kopf nach vorn/unten (Grad)
        self.arm = {1: [0.0, 8.0, 10.0], -1: [0.0, 8.0, 10.0]}  # vorn, seitlich, Ellenbogen (Grad)
        self.leg = {1: [0.0, 0.0], -1: [0.0, 0.0]}  # Hüfte vorn, Knie (Grad)
        self.tool = None  # (Name, Hand 1/-1, Winkel absolut in Grad: 0 = nach unten, 90 = nach vorn)
        self.item = None  # (Name, Hand)
        self.eyes = "open"
        self.ground = True
        self.extra = []  # Zusatzteile: ("line", ...) usw.
        for k, v in kw.items():
            setattr(self, k, v)


# Maße (Einheiten)
HIP_Y = 6.9
THIGH, SHIN = 3.45, 3.25
UPPER, FORE = 3.0, 2.8
SHOULDER_Y = 12.3  # über der Hüfte gemessen absolut im Stand
NECK_Y = 13.0
HEAD_C = 17.3
HEAD_RX, HEAD_RY = 5.0, 4.7
HEAD_RZ = 3.0


class Figure:
    """Aussehen: Geschlecht, Haarstil, Kind."""

    def __init__(self, hair=0, sex="m", child=False, beard=False, dress=None):
        self.hair = hair
        self.sex = sex
        self.child = child
        self.beard = beard
        self.dress = (sex == "f") if dress is None else dress


def build(fig, pose, view):
    cv = Canvas(view)
    k = 0.78 if fig.child else 1.0  # Kinder: kürzere Glieder, großer Kopf
    hip_y = HIP_Y * k
    thigh, shin, upper, fore = THIGH * k, SHIN * k, UPPER * k, FORE * k
    # --- Beine (von der Hüfte nach unten) und Bodenausgleich
    legs = {}
    for side in (1, -1):
        a, kn = [math.radians(v) for v in pose.leg[side]]
        hip = (1.45 * side * (0.9 if fig.child else 1.0), hip_y, 0.0)
        knee = add(hip, mul(limb_dir(a, 0.0, side), thigh))
        ank = add(knee, mul(limb_dir(a - kn, 0.0, side), shin))
        legs[side] = [hip, knee, ank]
    lowest = min(legs[1][2][1], legs[-1][2][1])
    dy = (0.55 - lowest) if pose.ground else 0.0
    dy += pose.bob
    for side in legs:
        legs[side] = [add(p, (0, dy, 0)) for p in legs[side]]
    hip_c = (0.0, hip_y + dy, 0.0)
    lean = math.radians(pose.lean)

    def up(p):  # Oberkörperpunkt (relativ zur Hüfte im Stand) vorbeugen und setzen
        rel = (p[0], p[1] - hip_y, p[2])
        return add(rot_x(rel, lean), hip_c)

    sh_y = hip_y + (SHOULDER_Y - HIP_Y) * (0.82 if fig.child else 1.0)
    neck_y = hip_y + (NECK_Y - HIP_Y) * (0.82 if fig.child else 1.0)
    head_c_rel = (0.0, neck_y + (HEAD_C - NECK_Y) * (0.95 if fig.child else 1.0), 0.0)
    shoulders = {s: up((3.05 * s * (0.85 if fig.child else 1.0), sh_y, 0.0)) for s in (1, -1)}
    neck = up((0.0, neck_y, 0.0))
    nod = math.radians(pose.head_nod)
    head_c = add(neck, rot_x((0.0, head_c_rel[1] - neck_y, 0.0), lean + nod))
    # --- Arme
    arms = {}
    for side in (1, -1):
        f, ab, el = [math.radians(v) for v in pose.arm[side]]
        sh = shoulders[side]
        d1 = rot_x(limb_dir(f, ab, side), lean)
        elbow = add(sh, mul(d1, upper))
        d2 = rot_x(limb_dir(f + el, ab * 0.6, side), lean)
        hand = add(elbow, mul(d2, fore))
        arms[side] = [sh, elbow, hand, d2]
    body = dict(legs=legs, arms=arms, hip=hip_c, neck=neck, head=head_c, lean=lean + nod, up=up,
                shoulders=shoulders, k=k)
    draw_figure(cv, fig, pose, body, view)
    return cv


def draw_figure(cv, fig, pose, b, view):
    """Stil nach josh' Vorlage (Handyansicht.png, 2026-10-24): Hemd, lange Hose, Stiefel, kräftige Farben."""
    k = b["k"]
    legs, arms = b["legs"], b["arms"]
    up = b["up"]
    # Beine: lange Hose, Stiefel
    for side in (1, -1):
        hip, knee, ank = legs[side]
        g = "leg%d" % side
        cv.capsule(hip, knee, 1.32 * k, "pants", g, r2=1.18 * k)
        cv.capsule(knee, ank, 1.15 * k, "pants", g, r2=1.05 * k)
        boot0 = add(ank, mul(sub(knee, ank), 0.3))
        cv.capsule(boot0, ank, 1.12 * k, "fixed:boot", g, dbias=0.01)
        toe = add(ank, (0.0, -0.2, 1.5 * k))
        cv.capsule(add(ank, (0, -0.25, -0.3)), toe, 0.95 * k, "fixed:boot", g, dbias=0.02)
    # Rumpf: Hemd bis über die Hüfte
    torso_group = "torso"
    hw_sh, hw_hip = 3.0 * k, 2.8 * k
    depth_half = 2.6 * k
    top = (SHOULDER_Y - HIP_Y) * (0.82 if fig.child else 1.0) * 1.02
    hem = -0.9 if not fig.dress else -2.6
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        y = HIP_Y * k + hem + t * (top - hem)
        p = up((0.0, y, 0.0))
        tt = (y - HIP_Y * k) / top
        hw = hw_hip + (hw_sh - hw_hip) * max(0.0, min(1.0, tt * 1.4))
        if tt > 0.86:
            hw *= 1.0 - (tt - 0.86) * 1.6
        if tt < 0:
            hw *= 1.0 - tt * 0.18
        hd = depth_half * (1.0 + 0.1 * math.sin(max(0.0, tt) * math.pi))
        _torso_slice(cv, p, hw, hd, view, torso_group)
    # Gürtel aus Leder mit Schnalle
    belt_y = HIP_Y * k + (0.25 if not fig.dress else 0.6)
    _ring(cv, up, belt_y, hw_hip * 1.03, depth_half * 1.08, "fixed:belt", torso_group, view)
    if view == "down":
        bk = up((0.0, belt_y, depth_half * 1.1))
        for dx in (-1, 0, 1):
            cv.dot(bk, "fixed:buckle", 3 if dx else 4, torso_group, 0.5, dx=dx)
            cv.dot(bk, "fixed:buckle", 2, torso_group, 0.5, dx=dx, dy=1)
    # Kragen
    if view == "down":
        sh_top = up((0.0, HIP_Y * k + top - 0.25, 0.0))
        vneck = [add(sh_top, (-1.05 * k, 0.5, depth_half + 0.1)), add(sh_top, (1.05 * k, 0.5, depth_half + 0.1)),
                 add(sh_top, (0.0, -1.1 * k, depth_half + 0.25))]
        cv.poly(vneck, "skin", torso_group, dbias=0.2, shade=2)
    # Arme: kurze Ärmel, Unterarm Haut, Hand
    for side in (1, -1):
        sh, el, hand, d2 = arms[side]
        g = "arm%d" % side
        sleeve_end = add(sh, mul(sub(el, sh), 0.7))
        cv.capsule(add(sh, (0, -0.2, 0)), sleeve_end, 1.28 * k, "shirt", g, dbias=0.15, r2=1.15 * k)
        cv.capsule(sleeve_end, el, 0.95 * k, "skin", g, dbias=0.12)
        cv.capsule(el, hand, 0.9 * k, "skin", g, dbias=0.12, r2=0.84 * k)
        cv.ellipse(add(hand, mul(d2, 0.35)), 1.0 * k, 1.0 * k, "skin", g, dbias=0.13)
    if pose.tool:
        draw_tool(cv, pose.tool, arms, view, k)
    if pose.item:
        draw_item(cv, pose.item, arms, b, view, k)
    for ex in pose.extra:
        ex(cv, b, view)
    draw_head(cv, fig, pose, b, view)


def _torso_slice(cv, p, hw, hd, view, group, hem=False):
    """Querschnitt des Rumpfes: in der Ansicht eine waagerechte Linie mit Schattierung."""
    if view == "side":
        a = add(p, (0, 0, -hd))
        bb = add(p, (0, 0, hd))
    else:
        a = add(p, (-hw, 0, 0))
        bb = add(p, (hw, 0, 0))
    ax, ay, ad = cv.proj(a)
    bx, by, bd = cv.proj(bb)
    x0, x1 = (ax, bx) if ax < bx else (bx, ax)
    for yy in (int(ay) - 1, int(ay), int(ay) + 1):
        for x in range(int(round(x0)), int(round(x1))):
            u = ((x + 0.5) - x0) / max(1.0, (x1 - x0)) * 2.0 - 1.0  # -1 links .. 1 rechts
            nz = math.sqrt(max(0.0, 1.0 - u * u))
            lum = u * LIGHT[0] + nz * LIGHT[2] + 0.15
            d = (ad + bd) * 0.5 + (hd if view != "side" else hw) * nz * 0.6
            cv.put(x, yy, d, "shirt", lum_to_shade(lum), group)


def _ring(cv, up, y, hw, hd, layer, group, view):
    for i in range(160):
        a = i / 160 * 2 * math.pi
        p = up((math.cos(a) * hw, y, math.sin(a) * hd))
        x, yy, d = cv.proj(p)
        front = (d > cv.proj(up((0, y, 0)))[2] - 0.01)
        if front:
            cv.put(int(x), int(yy), d + 0.4, layer, 3, group)
            cv.put(int(x), int(yy) + 1, d + 0.4, layer, 2, group)


def _fringe(cv, up, y, hw, hd, view, group):
    """Fransen am Saum: abwechselnd längere und kürzere Zacken."""
    for i in range(48):
        a = i / 48 * 2 * math.pi
        p = up((math.cos(a) * hw, y, math.sin(a) * hd))
        x, yy, d = cv.proj(p)
        length = 2 if i % 3 == 0 else (1 if i % 3 == 1 else 0)
        for j in range(length + 1):
            cv.put(int(x), int(yy) + j, d, "shirt", 2 if j else 3, group)


def draw_head(cv, fig, pose, b, view):
    c = b["head"]
    k = 1.0
    rx, ry = HEAD_RX * (0.96 if fig.child else 1.0), HEAD_RY * (0.96 if fig.child else 1.0)
    g = "head"
    # Hals
    cv.capsule(add(b["neck"], (0, -0.6, 0)), add(c, (0, -2.6, 0)), 1.05, "skin", "neck", dbias=-0.3)
    nod = b["lean"]
    long_hair = fig.hair == 1
    # langes Haar hinter dem Kopf (von vorn) bzw. über dem Rücken
    if long_hair:
        back = -1 if view != "up" else 1
        if view == "side":
            cv.ellipse(add(c, (0, -2.6, -2.6)), 2.4, 3.6, "hair", "hairback", dbias=-1.5)
        else:
            depth = -1.5 if view == "down" else 1.5
            cv.ellipse(add(c, (0, -2.8, -2.4 if view == "down" else -2.4)), rx * 0.98, 3.8, "hair", "hairback",
                       dbias=-2.5 if view == "down" else 0.5)
    # Ohren
    if view in ("down", "up"):
        for s in (1, -1):
            cv.ellipse(add(c, (s * rx * 0.97, -0.7, -0.3)), 1.15, 1.45, "skin", "ear%d" % s, dbias=-0.8)
    # Kopf
    cv.ellipse(c, rx, ry, "skin", g, dbias=0.0, bias=0.28, rz=HEAD_RZ)
    fd = cv.proj(c)[2] + HEAD_RZ + 0.05
    if view == "side":
        # Nase und Kinn
        cv.ellipse(add(c, (0.0, -1.0, rx * 0.97)), 0.5, 0.6, "skin", g, dbias=HEAD_RZ, flat=True)
        cv.ellipse(add(c, (-0.3, -0.7, -0.6)), 0.85, 1.2, "skin", "ear", dbias=HEAD_RZ)
        cv.dot(add(c, (-0.3, -0.7, -0.6)), "skin", 2, "ear", HEAD_RZ + 0.1)
    # Haare
    draw_hair(cv, fig, c, rx, ry, view)
    # Gesicht
    if view == "down":
        ex = 1.75
        for s in (1, -1):
            e = add(c, (s * ex, -0.55, ry))
            x, y, d = cv.proj(e)
            x, y = int(x), int(y)
            if pose.eyes == "closed":
                for dx in (-1, 0, 1):
                    cv.put(x + dx, y + 1, fd, "fixed:eye", 0, g)
            else:
                for dx in (-1, 0):
                    for dyy in (-1, 0, 1):
                        cv.put(x + dx, y + dyy, fd, "fixed:eye", 0, g)
                cv.put(x - 1, y - 1, fd, "fixed:eyewhite", 4, g)
            # Augenbraue in Haarfarbe
            for dx in (-2, -1, 0, 1):
                cv.put(x + dx, y - 3 + (1 if dx == (1 if s > 0 else -2) else 0), fd, "hair", 1, g)
            # Wangenröte
            cv.put(x + (1 if s > 0 else -2), y + 3, fd, "fixed:blush", 3, g)
            cv.put(x + (2 if s > 0 else -3), y + 3, fd, "fixed:blush", 3, g)
        n = add(c, (0, -1.7, ry))
        nx, ny, _ = cv.proj(n)
        cv.put(int(nx), int(ny), fd, "skin", 2, g)
        cv.put(int(nx) - 1, int(ny) + 1, fd, "skin", 2, g)
        m = add(c, (0, -2.8, ry))
        mx, my, _ = cv.proj(m)
        for dx in (-1, 0, 1):
            cv.put(int(mx) + dx, int(my), fd, "fixed:mouth", 1 if dx == 0 else 2, g)
        if fig.beard:
            _beard(cv, c, rx, ry, view)
    elif view == "side":
        e = add(c, (0, -0.55, rx * 0.62))
        x, y, d = cv.proj(e)
        x, y = int(x), int(y)
        if pose.eyes == "closed":
            for dx in (-1, 0):
                cv.put(x + dx, y + 1, fd, "fixed:eye", 0, g)
        else:
            for dyy in (-1, 0, 1):
                cv.put(x, y + dyy, fd, "fixed:eye", 0, g)
                cv.put(x - 1, y + dyy, fd, "fixed:eye", 0, g)
            cv.put(x - 1, y - 1, fd, "fixed:eyewhite", 4, g)
        for dx in (-2, -1, 0, 1):
            cv.put(x + dx, y - 3, fd, "hair", 1, g)
        cv.put(x - 1, y + 3, fd, "fixed:blush", 3, g)
        cv.put(x - 2, y + 3, fd, "fixed:blush", 3, g)
        m = add(c, (0, -2.8, rx * 0.86))
        mx, my, _ = cv.proj(m)
        cv.put(int(mx), int(my), fd, "fixed:mouth", 1, g)
        cv.put(int(mx) - 1, int(my), fd, "fixed:mouth", 2, g)
        if fig.beard:
            _beard(cv, c, rx, ry, view)


def _beard(cv, c, rx, ry, view):
    if view == "down":
        def clip(u, v):
            return v > 0.25 and not (abs(u) < 0.32 and 0.38 < v < 0.62)
        cv.ellipse(add(c, (0, -0.9, 0.6)), rx * 0.86, ry * 0.95, "hair", "beard", dbias=HEAD_RZ + 0.02, clip=clip)
    else:
        def clip(u, v):
            return v > 0.3 and u > -0.1
        cv.ellipse(add(c, (0, -1.2, 1.6)), rx * 0.62, ry * 0.85, "hair", "beard", dbias=HEAD_RZ + 0.02, clip=clip)


def draw_hair(cv, fig, c, rx, ry, view):
    st = fig.hair
    g = "hair"
    hx, hy, hd = cv.proj(c)
    rxp, ryp = (rx + 0.35) * S, (ry + 0.45) * S
    for y in range(int(hy - ryp - 2), int(hy + ryp + 2)):
        for x in range(int(hx - rxp - 1), int(hx + rxp + 2)):
            u, v = (x + 0.5 - hx) / rxp, (y + 0.5 - hy) / ryp
            q = u * u + v * v
            if q > 1.0:
                continue
            take = False
            if view == "down":
                # Pony mit Zacken, Seiten bis Ohrhöhe
                edge = -0.28 + 0.1 * math.sin(u * 9.0) - (0.12 if abs(u) > 0.7 else 0.0)
                if st == 2:
                    edge = -0.38 + 0.06 * abs(u) * 3 - 0.08 * (abs(u) < 0.15)
                take = v < edge or (abs(u) > 0.84 and v < 0.25 + (0.5 if st == 1 else 0.0))
            elif view == "up":
                take = v < 0.55 + (0.45 if st == 1 else 0.0)
            else:
                # Seite: oben und hinten
                edge = -0.3 + 0.08 * math.sin(u * 10.0)
                take = v < edge or (u < -0.15 and v < 0.55 + (0.45 if st == 1 else 0.0)) or (u < -0.55)
                if u > 0.55 and v > -0.45:
                    take = False
            if not take:
                continue
            nz = math.sqrt(max(0.0, 1.0 - q))
            lum = u * LIGHT[0] - v * LIGHT[1] + nz * LIGHT[2]
            sh = lum_to_shade(lum)
            # Strähnen: feine dunkle Linien
            if sh >= 3 and int((u * 7.0 + v * 2.0) * 3) % 3 == 0:
                sh -= 1
            if sh == 4 and int((u + 1) * 20) % 4 != 0:
                sh = 3
            cv.put(x, y, hd + nz * HEAD_RZ + 0.04, "hair", sh, g)
    if st == 2:  # Dutt oben am Hinterkopf
        if view == "side":
            p = add(c, (0, ry * 0.75, -rx * 0.6))
        elif view == "up":
            p = add(c, (0, ry * 0.45, -rx * 0.9))
        else:
            p = add(c, (0, ry * 1.02, -rx * 0.4))
        cv.ellipse(p, 1.9, 1.7, "hair", "bun", dbias=(3.0 if view == "up" else -1.0 if view == "down" else 2.8))
        # Knochennadel
        a = add(p, (-2.2, 0.3, 0.0)) if view != "side" else add(p, (0, 0.4, -2.2))
        bb = add(p, (2.2, -0.2, 0.0)) if view != "side" else add(p, (0, -0.1, 2.2))
        cv.line(a, bb, "fixed:bone", 3, "bun", dbias=4.0 if view != "down" else -0.9)
    if st == 1 and view == "down":  # Strähnen vorn über die Schultern
        for s in (1, -1):
            cv.capsule(add(c, (s * rx * 0.9, -1.0, 0.4)), add(c, (s * rx * 0.8, -5.2, 0.9)), 0.95, "hair", "lock%d" % s,
                       dbias=1.0, r2=0.7)


# ------------------------------------------------------------------------------- Werkzeuge
TOOL_COL = {
    "wood": [(52, 32, 26), (96, 62, 40), (136, 92, 56), (170, 122, 74), (204, 160, 104)],
    "stone": [(40, 40, 50), (84, 86, 98), (122, 124, 136), (160, 162, 170), (206, 208, 212)],
    "flint": [(36, 30, 40), (70, 62, 80), (104, 94, 114), (140, 128, 148), (186, 176, 190)],
    "rope": [(60, 44, 28), (120, 96, 60), (164, 136, 88), (196, 170, 116), (226, 204, 150)],
    "basket": [(64, 40, 22), (120, 80, 40), (166, 118, 60), (204, 156, 86), (230, 196, 122)],
    "clay": [(60, 32, 24), (118, 62, 40), (162, 92, 58), (196, 124, 80), (226, 164, 116)],
    "berry": [(40, 14, 40), (110, 30, 70), (170, 50, 90), (210, 80, 120), (240, 150, 170)],
    "leaf": [(20, 44, 30), (40, 92, 50), (66, 132, 64), (104, 168, 80), (150, 200, 110)],
    "line": [(200, 200, 190)] * 5,
    "water": [(40, 70, 110), (60, 110, 160), (90, 150, 200), (140, 190, 230), (200, 230, 250)],
}


def draw_tool(cv, tool, arms, view, k):
    name, side, ang = tool[0], tool[1], tool[2]
    hand = arms[side][2]
    a = math.radians(ang)
    ax = limb_dir(a, 0.0, side)  # Richtung des Stiels
    perp = limb_dir(a + math.pi / 2, 0.0, side)  # quer dazu (nach vorn gedreht)
    g = "tool"
    db = 0.25
    if name in ("axe", "pick", "hammer"):
        back = add(hand, mul(ax, -1.0))
        tip = add(hand, mul(ax, 5.0))
        cv.capsule(back, tip, 0.42, "tool:wood", g, dbias=db)
        if name == "axe":
            head = add(tip, mul(ax, -0.6))
            pts = [add(head, mul(perp, 0.3)), add(add(head, mul(perp, 2.6)), mul(ax, 1.1)),
                   add(add(head, mul(perp, 2.9)), mul(ax, -0.4)), add(add(head, mul(perp, 2.4)), mul(ax, -1.6)),
                   add(head, mul(ax, -0.8))]
            cv.poly(pts, "tool:stone", g, dbias=db + 0.1, shade=3)
            cv.line(add(add(head, mul(perp, 2.7)), mul(ax, 0.8)), add(add(head, mul(perp, 2.7)), mul(ax, -1.2)),
                    "tool:stone", 4, g, dbias=db + 0.12)
            for t in (-0.5, 0.0, 0.5):
                p = add(head, mul(ax, t))
                cv.line(add(p, mul(perp, -0.45)), add(p, mul(perp, 0.55)), "tool:rope", 3, g, dbias=db + 0.2)
        elif name == "pick":
            head = add(tip, mul(ax, -0.4))
            cv.capsule(add(head, mul(perp, -2.2)), add(add(head, mul(perp, 2.8)), mul(ax, -1.4)), 0.55, "tool:stone",
                       g, dbias=db + 0.1, r2=0.25)
            cv.capsule(head, add(head, mul(perp, -2.4)), 0.5, "tool:stone", g, dbias=db + 0.1, r2=0.3)
            cv.line(add(head, mul(ax, -0.4)), add(head, mul(ax, 0.4)), "tool:rope", 3, g, dbias=db + 0.2)
        else:  # Steinhammer
            tip = add(hand, mul(ax, 3.6))
            cv.capsule(back, tip, 0.4, "tool:wood", g, dbias=db)
            cv.ellipse(add(tip, mul(perp, 0.4)), 1.35, 1.05, "tool:stone", g, dbias=db + 0.1)
            cv.line(add(tip, mul(ax, -0.5)), add(tip, mul(ax, 0.5)), "tool:rope", 3, g, dbias=db + 0.2)
    elif name == "sickle":
        tip = add(hand, mul(ax, 1.6))
        cv.capsule(add(hand, mul(ax, -0.7)), tip, 0.42, "tool:wood", g, dbias=db)
        prev = tip
        for i in range(1, 8):
            t = i / 7
            p = add(add(tip, mul(ax, 2.4 * math.sin(t * 2.0))), mul(perp, -2.6 * (1 - math.cos(t * 2.3))))
            cv.capsule(prev, p, 0.55 * (1.1 - t * 0.6), "tool:stone", g, dbias=db + 0.1)
            prev = p
    elif name == "shovel":  # Grabstock mit Steinblatt
        top = add(hand, mul(ax, -2.4))
        bot = add(hand, mul(ax, 6.0))
        cv.capsule(top, bot, 0.42, "tool:wood", g, dbias=db)
        cv.capsule(add(bot, mul(ax, -0.4)), add(bot, mul(ax, 1.4)), 1.2, "tool:stone", g, dbias=db + 0.1, r2=0.7)
    elif name == "rod":
        tip = add(hand, mul(ax, 7.5))
        cv.capsule(add(hand, mul(ax, -1.2)), tip, 0.38, "tool:wood", g, dbias=db, r2=0.18)
        line_end = tool[3] if len(tool) > 3 and tool[3] else add(tip, (0, -5.0, 0))
        cv.line(tip, line_end, "tool:line", 3, g, dbias=db)
        cv.ellipse(line_end, 0.55, 0.55, "tool:berry", g, dbias=db + 0.1)
    elif name == "spoon":
        tip = add(hand, mul(ax, 4.4))
        cv.capsule(add(hand, mul(ax, -0.8)), tip, 0.32, "tool:wood", g, dbias=db)
        cv.ellipse(tip, 0.7, 0.6, "tool:wood", g, dbias=db)
    elif name == "stylus":
        tip = add(hand, mul(ax, 1.8))
        cv.capsule(add(hand, mul(ax, -0.8)), tip, 0.28, "tool:wood", g, dbias=db + 0.4, r2=0.15)
    elif name == "spear":
        cv.capsule(add(hand, mul(ax, -4.0)), add(hand, mul(ax, 6.0)), 0.38, "tool:wood", g, dbias=db)
        tip = add(hand, mul(ax, 6.0))
        pts = [add(tip, mul(perp, 0.9)), add(tip, mul(ax, 2.4)), add(tip, mul(perp, -0.9)), add(tip, mul(ax, -0.3))]
        cv.poly(pts, "tool:flint", g, dbias=db + 0.1, shade=3)


def draw_item(cv, item, arms, b, view, k):
    name, where = item[0], item[1]
    g = "item"
    if name == "basket":
        if where == "hip":  # Korb am Boden neben dem Sammler
            p = (2.6 if view != "side" else 0.0, 1.4, 2.8 if view == "side" else 1.0)
            if view == "side":
                p = (-1.0, 1.4, -2.6)
            _basket(cv, p, 2.2, 1.6, view, g, 0.0 if view != "up" else -3.0)
        else:
            hand = arms[where][2]
            _basket(cv, add(hand, (0, -1.4, 0.0)), 1.9, 1.4, view, g, 0.6)
    elif name == "bundle":  # Bündel Holz vor der Brust, mit beiden Armen gehalten
        hand = mul(add(arms[1][2], arms[-1][2]), 0.5)
        c = add(hand, (0, 0.5, -0.2))
        for dy_, dz in ((0.0, 0.0), (1.2, -0.3), (-1.1, -0.2)):
            q = add(c, (0, dy_, dz))
            if view == "side":
                a_, b_ = add(q, (0, 0.4, -1.4)), add(q, (0, -0.2, 2.2))
            else:
                a_, b_ = add(q, (-2.6, 0, 0)), add(q, (2.6, 0, 0))
            cv.capsule(a_, b_, 0.75, "tool:wood", g, dbias=0.05)
            cv.ellipse(b_ if view != "up" else a_, 0.6, 0.7, "tool:wood", g, dbias=0.1, flat=True)
        cv.line(add(c, (0, 1.9, 0.9)), add(c, (0, -1.9, 0.9)), "tool:rope", 3, g, dbias=0.2)
    elif name == "tablet":  # Tontafel in der linken Hand
        hand = arms[-where][2]
        c = add(hand, (0, 0.6, 0.6))
        if view == "side":
            pts = [add(c, (0, 1.6, -1.2)), add(c, (0, 1.9, 1.6)), add(c, (0, -0.4, 1.9)), add(c, (0, -0.7, -0.9))]
        else:
            pts = [add(c, (-1.8, 1.4, 0.5)), add(c, (1.8, 1.4, 0.5)), add(c, (1.8, -1.0, 0.5)), add(c, (-1.8, -1.0, 0.5))]
        cv.poly(pts, "tool:clay", g, dbias=0.6, shade=3)
        for i in range(3):
            q = add(c, (0, 1.0 - i * 0.7, 0.1)) if view == "side" else add(c, (-1.0, 0.9 - i * 0.7, 0.6))
            r = add(q, (0, 0, 1.6)) if view == "side" else add(q, (2.0, 0, 0))
            cv.line(q, r, "tool:clay", 1, g, dbias=0.7)
    elif name == "pot":  # Tontopf über dem Feuer vor dem Koch
        p = (0.0, 2.0, 5.4)
        cv.ellipse(add(p, (0, 0, 0)), 2.6, 2.1, "tool:clay", g, dbias=1.0 if view != "up" else -6.0)
        cv.ellipse(add(p, (0, 1.6, 0.2)), 2.0, 0.55, "tool:wood", g, dbias=1.1 if view != "up" else -5.9, flat=True)
        for dx in (-1.6, 0.0, 1.6):  # Flammen
            q = add(p, (dx, -1.7, 0.4)) if view != "side" else add(p, (0, -1.7, dx + 0.4))
            cv.ellipse(q, 0.6, 0.9, "tool:fire", g, dbias=1.2 if view != "up" else -5.8)
    elif name == "berry":  # Beere in der Hand
        hand = arms[where][2]
        cv.ellipse(add(hand, (0, 0.2, 0.3)), 0.6, 0.6, "tool:berry", g, dbias=0.5)
    elif name == "sapling":  # Setzling am Boden
        p = (0.0, 0.6, 4.2)
        cv.line(p, add(p, (0, 3.0, 0)), "tool:wood", 2, g, dbias=0.0)
        cv.ellipse(add(p, (-0.8, 2.6, 0)) if view != "side" else add(p, (0, 2.6, -0.8)), 1.0, 0.6, "tool:leaf", g)
        cv.ellipse(add(p, (0.8, 3.2, 0)) if view != "side" else add(p, (0, 3.2, 0.8)), 1.0, 0.6, "tool:leaf", g)


def _basket(cv, p, rx, ry, view, g, db):
    cv.ellipse(p, rx, ry, "tool:basket", g, dbias=db)
    cx, cy, d = cv.proj(p)
    # Flechtmuster
    for y in range(int(cy - ry * S), int(cy + ry * S) + 1):
        for x in range(int(cx - rx * S), int(cx + rx * S) + 1):
            u, v = (x + 0.5 - cx) / (rx * S), (y + 0.5 - cy) / (ry * S)
            if u * u + v * v > 0.8 or v < -0.45:
                continue
            if (x + (y // 2) * 2) % 4 == 0 or y % 3 == 0:
                cv.put(x, y, d + db + 0.05, "tool:basket", 2, g)
    # Rand mit Beeren
    top_y = int(cy - ry * S * 0.55)
    for x in range(int(cx - rx * S * 0.8), int(cx + rx * S * 0.8)):
        cv.put(x, top_y, d + db + 0.1, "tool:basket", 4, g)
    for i, dx in enumerate((-3, -1, 1, 3, 0, -2, 2)):
        cv.put(int(cx) + dx, top_y - 1 - (i // 4), d + db + 0.2, "tool:berry", 3 if i % 2 else 4, g)


# --------------------------------------------------------------------------- Kontur & Bild
def finish(cv):
    """Konturen: Rand zur Leere und zu Teilen anderer Gruppen dahinter."""
    out = {}
    for (x, y), (d, layer, sh, grp) in cv.px.items():
        edge = False
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            o = cv.px.get((nx, ny))
            if o is None:
                edge = True
                break
            if o[3] != grp and o[0] < d - 0.35 and not layer.startswith("fixed:eye") and _sep(grp, o[3]):
                edge = True
                break
        if edge and not layer.startswith("fixed:eye") and layer != "fixed:mouth" and layer != "fixed:blush":
            sh = 0
        out[(x, y)] = (layer, sh)
    return out


def _sep(a, b):
    """Keine Kontur zwischen eng verbundenen Teilen."""
    pairs = {frozenset(("neck", "head")), frozenset(("neck", "torso")), frozenset(("hair", "head")),
             frozenset(("bun", "hair")), frozenset(("beard", "head")), frozenset(("beard", "hair"))}
    return frozenset((a, b)) not in pairs


# Farbrampen für die Vorschau (später im Spiel aus der Farbe des Siedlers gerechnet)
def ramp(base, hue_shadow=(-18, -10, 22), hue_light=(22, 16, -6)):
    r, g, b = base
    def c(t, sh):
        return tuple(max(0, min(255, int(v * t + s))) for v, s in zip((r, g, b), sh))
    return [c(0.38, (8, 0, 18)), c(0.62, (0, -2, 12)), c(0.8, (-2, -2, 8)), c(1.0, (0, 0, 0)),
            c(1.12, (14, 12, 4))]


FIXED = {
    "boot": ramp((92, 58, 38)),
    "belt": ramp((70, 46, 32)),
    "buckle": ramp((200, 176, 110)),
    "wrap": ramp((140, 96, 62)),
    "rope": ramp((196, 168, 112)),
    "bone": ramp((236, 226, 200)),
    "eye": [(34, 22, 34)] * 5,
    "eyewhite": [(250, 250, 250)] * 5,
    "mouth": [(120, 50, 50), (150, 64, 60), (172, 84, 76), (190, 100, 90), (210, 120, 110)],
    "blush": [(236, 150, 128)] * 5,
}
TOOLS = dict(TOOL_COL)
TOOLS["fire"] = [(120, 30, 10), (200, 70, 20), (240, 130, 30), (255, 190, 60), (255, 240, 150)]


def to_image(px, look):
    im = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
    for (x, y), (layer, sh) in px.items():
        if layer.startswith("fixed:"):
            col = FIXED[layer[6:]][sh]
        elif layer.startswith("tool:"):
            col = TOOLS[layer[5:]][sh]
        else:
            col = look[layer][sh]
        if sh == 0:  # Kontur: dunkles Braun wie in der Vorlage, leicht in der Farbe der Fläche
            col = tuple((c + o) // 2 for c, o in zip(col, (52, 32, 30)))
        im.putpixel((x, y), tuple(col) + (255,))
    return im


def to_layers(px):
    """Graustufen-Ebenen für das Spiel: Stufe 0..4 als Grauwert, Farbe kommt aus dem Shader."""
    layers = {}
    for (x, y), (layer, sh) in px.items():
        key = layer
        if layer.startswith("fixed:") or layer.startswith("tool:"):
            key = "fixed"
        if key not in layers:
            layers[key] = {}
        layers[key][(x, y)] = (layer, sh)
    return layers


def render(fig, pose, view, look):
    cv = build(fig, pose, view)
    return to_image(finish(cv), look)


# ----------------------------------------------------------------------------- Bewegungen
def _walk_legs(p, amp=28.0):
    sp, cp = math.sin(p), math.cos(p)
    return {1: [amp * sp, 8 + 48 * max(0.0, cp) ** 1.3], -1: [-amp * sp, 8 + 48 * max(0.0, -cp) ** 1.3]}


def anim_walk(n=8):
    out = []
    for f in range(n):
        p = 2 * math.pi * f / n
        sp = math.sin(p)
        out.append(Pose(lean=4, leg=_walk_legs(p), head_nod=-2,
                        arm={-1: [-24 * sp, 7, 18 + 12 * max(0, -sp)], 1: [24 * sp, 7, 18 + 12 * max(0, sp)]}))
    return out


def anim_idle(n=4):
    out = []
    for f in range(n):
        b = 0.18 * math.sin(2 * math.pi * f / n)
        out.append(Pose(bob=b, arm={-1: [2, 8 + b * 6, 12], 1: [2, 8 + b * 6, 12]},
                        eyes="closed" if f == 3 else "open"))
    return out


def anim_carry(n=8):
    out = []
    for f in range(n):
        p = 2 * math.pi * f / n
        out.append(Pose(lean=-3, leg=_walk_legs(p, 22.0), item=("bundle", 0), bob=0.1 * math.cos(2 * p),
                        arm={-1: [22, 20, 62], 1: [22, 20, 62]}))
    return out


def _swing(frames, tool, impact_lean, item=None, legs=None):
    out = []
    for arm_f, el, lean, tang in frames:
        out.append(Pose(lean=lean, tool=(tool, -1, tang), item=item,
                        leg=legs or {1: [14, 8], -1: [-10, 4]},
                        arm={-1: [arm_f, 6, el], 1: [arm_f - 6, 14, el + 6]}))
    return out


def anim_chop():
    # Ausholen über den Kopf, Schlag nach vorn, kurz halten
    fr = [(100, 30, 6, 170), (160, 25, 0, 225), (190, 15, -3, 250), (130, 10, 12, 150), (60, 8, 24, 65),
          (52, 10, 26, 55)]
    return _swing(fr, "axe", 24, legs={1: [34, 30], -1: [-26, 12]})


def anim_mine():
    fr = [(100, 30, 4, 170), (160, 20, -4, 230), (190, 12, -6, 255), (130, 10, 10, 150), (65, 8, 22, 80),
          (60, 10, 24, 75)]
    return _swing(fr, "pick", 22)


def anim_hammer():
    fr = [(70, 50, 22, 130), (120, 40, 18, 190), (85, 30, 22, 120), (55, 25, 26, 80)]
    out = _swing(fr, "hammer", 22, legs={1: [40, 70], -1: [-20, 40]})
    for p in out:
        p.arm[1] = [55, 10, 20]
    return out


def anim_gather():
    """Wie in der Vorlage: Korb in der vorderen Hand, die andere pflückt vorn am Strauch."""
    out = []
    reach = [(60, 20), (75, 10), (80, 8), (70, 30), (45, 55), (40, 60)]
    for i, (af, el) in enumerate(reach):
        out.append(Pose(lean=12, head_nod=4, leg={1: [24, 22], -1: [-14, 10]}, item=("basket", -1),
                        arm={1: [af, 8, el], -1: [18, 12, 70]}))
        if i in (2, 3):
            out[-1].extra = [lambda cv, b, v: cv.ellipse(add(b["arms"][1][2], (0, 0.1, 0.4)), 0.6, 0.6, "tool:berry",
                                                          "item", dbias=0.6)]
    return out

def anim_fish():
    out = []
    seq = [(-30, 70, 215), (30, 70, 170), (75, 40, 120), (60, 40, 128), (58, 40, 131), (62, 40, 126)]
    for i, (af, el, tang) in enumerate(seq):
        end = (0.0, 0.6 + (0.25 if i % 2 else 0.0), 9.6)
        out.append(Pose(lean=2, tool=("rod", -1, tang, end if i >= 2 else None),
                        arm={-1: [af, 6, el], 1: [af - 4, 12, el + 4]}))
    return out


def anim_sickle():
    out = []
    seq = [(0, 20, 50), (20, 18, 75), (42, 12, 105), (58, 10, 125), (30, 16, 90), (8, 20, 60)]
    for af, el, tang in seq:
        out.append(Pose(lean=34, head_nod=4, tool=("sickle", -1, tang), leg={1: [34, 42], -1: [-6, 20]},
                        arm={-1: [af, 14, el], 1: [-10, 8, 40]}))
    return out


def anim_cook():
    out = []
    for f in range(4):
        a = 2 * math.pi * f / 4
        out.append(Pose(lean=18, item=("pot", 0), tool=("spoon", -1, 25 + 10 * math.sin(a)),
                        leg={1: [80, 125], -1: [20, 120]},
                        arm={-1: [38 + 8 * math.sin(a), 10 + 6 * math.cos(a), 28], 1: [30, 14, 60]}))
    return out


def anim_research():
    out = []
    for f in range(4):
        d = (0, 4, -2, 3)[f]
        out.append(Pose(lean=6, head_nod=14, item=("tablet", -1), tool=("stylus", -1, 150 + d * 3),
                        arm={-1: [60 + d, 18, 70], 1: [55, 14, 70]}, eyes="open"))
    return out


def anim_dig():
    out = []
    seq = [(30, 30, 14, 22), (22, 25, 20, 14), (15, 25, 26, 8), (30, 35, 18, 30), (42, 30, 10, 38),
           (36, 30, 12, 28)]
    for af, el, lean, tang in seq:
        out.append(Pose(lean=lean, tool=("shovel", -1, tang), item=("sapling", 0), leg={1: [24, 18], -1: [-12, 6]},
                        arm={-1: [af, 10, el], 1: [af + 25, 14, el + 10]}))
    return out


def anim_eat():
    out = []
    for f in range(4):
        up_ = f in (1, 2)
        out.append(Pose(ground=False, bob=-3.4, lean=-6, leg={1: [88, 75], -1: [82, 85]},
                        item=("berry", -1) if up_ else None, head_nod=4 if up_ else 0,
                        arm={-1: [55 if up_ else 35, 12, 120 if up_ else 50], 1: [35, 16, 50]}))
    return out


def anim_sleep():
    return [Pose(eyes="closed", arm={-1: [0, 6, 20], 1: [0, 6, 20]}),
            Pose(eyes="closed", bob=0.15, arm={-1: [0, 7, 22], 1: [0, 7, 22]})]


ANIMS = [
    ("walk", "Gehen", anim_walk),
    ("idle", "Stehen", anim_idle),
    ("carry", "Tragen", anim_carry),
    ("chop", "Holz hacken", anim_chop),
    ("mine", "Stein schlagen", anim_mine),
    ("gather", "Beeren sammeln", anim_gather),
    ("fish", "Angeln", anim_fish),
    ("sickle", "Ernten", anim_sickle),
    ("hammer", "Bauen und Handwerk", anim_hammer),
    ("cook", "Kochen", anim_cook),
    ("research", "Forschen", anim_research),
    ("dig", "Pflanzen (Förster)", anim_dig),
    ("eat", "Sitzen und Essen", anim_eat),
    ("sleep", "Schlafen", anim_sleep),
]
