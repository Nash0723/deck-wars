# Spell models: one small 3D object per spell. Cards show it turning slowly in their picture window
# (like the creatures), Pack Brawl stands it in front of the big spell card.
#
# Same look as the creatures and buildings: chunky rounded shapes, bold colours, faces with a mood
# on the spells that are "alive". The rarer the spell, the more shine and glow:
#   Common: plain paint. Rare: shiny gold, glass and foil. Epic: a little glow.
#   Mythic: glowing light and sparkles. Legendary: glow, gold and things orbiting it.
# Spells never stand on the board, so they keep their real size (kind "spell").
import math
import random
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal, frame_from_x
from stylekit import SModel, V, norm, INK, GOLD, SILVER, on_ell_R
from models_extra import plank, tri, disc, torus, star, grass

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


# ------------------------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------------------------
def cyl_pt(r, a, y, c=(0.0, 0.0)):
    """Point on an upright cylinder (axis through c = (x, z)) at angle a degrees from the front
    (-z; + turns towards +x), and the outward normal there."""
    t = math.radians(a)
    n = V(math.sin(t), 0, -math.cos(t))
    return V(c[0], y, c[1]) + n * r, n


def stroke(m, name, pts, r, depth, color, mat="SmoothPlastic", shape="tube", tr=0.0, r_end=None):
    """A smooth line through points (a motion line, a painted stroke): round tubes r thick, tapering
    to r_end. shape="E" makes flat ellipsoid strokes instead (depth = half their thickness; build
    them in the x-y plane)."""
    P = [np.asarray(p, float) for p in pts]
    n = len(P) - 1
    for i in range(n):
        rr = r if r_end is None else r + (r_end - r) * i / max(n - 1, 1)
        a, b = P[i], P[i + 1]
        if shape == "tube":
            v = (b - a) * (0.06 if tr > 0 else 0.0)
            m.rod(name, a - v, b + v, 2 * rr, color, mat, tr=tr)
            if tr == 0:
                m.ball(name, 2 * rr, b, color, mat)
                if i == 0:
                    m.ball(name, 2 * rr, a, color, mat)
        else:
            m.seg(name, a, b, rr, color, mat, r2=depth, ext=rr * 0.55, shape=shape, tr=tr)


def arc_pts(c, r, a0, a1, n, plane=I3):
    """n + 1 points on a circle of radius r around c from angle a0 to a1 (degrees) in the plane's
    x-y (plane = rotation; I3 is the x-y plane facing -z)."""
    P = np.asarray(plane, float)
    c = np.asarray(c, float)
    out = []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        out.append(c + P @ V(math.cos(a) * r, math.sin(a) * r, 0))
    return out


def stripes(m, name, pts, d, colors, step=0.14, mat="SmoothPlastic"):
    """A round tube through points, painted in bands of alternating colours (a straw, a pole)."""
    P = [np.asarray(p, float) for p in pts]
    k = 0
    for a, b in zip(P[:-1], P[1:]):
        L = float(np.linalg.norm(b - a))
        n = max(1, int(round(L / step)))
        for i in range(n):
            m.rod(name, a + (b - a) * i / n, a + (b - a) * (i + 1) / n, d, colors[k % len(colors)], mat)
            k += 1
    for p in P[1:-1]:
        m.ball(name, d, p, colors[0], mat)


def qmark(m, name, c, h, color, mat="SmoothPlastic", R=I3, r=None, segs=10):
    """A chunky rounded question mark (a smooth tube), h tall, built facing -z around its middle c
    and turned by R."""
    r = r or h * 0.085
    with m.group(R=R, t=c):
        cy, ar = h * 0.2, h * 0.2
        pts = arc_pts(V(0, cy, 0), ar, 165, -60, segs)
        pts.append(V(h * 0.012, cy - ar * 1.18, 0))
        pts.append(V(0, -h * 0.1, 0))
        m.chain(name, pts, 2 * r, color, mat)
        m.ball(name, 2 * r, pts[0], color, mat)
        m.ball(name, 2 * r, pts[-1], color, mat)
        m.ball(name, r * 2.5, V(0, -h * 0.36, 0), color, mat)


def loop_tube(m, name, c, R, r, normal, color, n=10, mat="SmoothPlastic"):
    """A smooth closed ring of tube (rods with round joints), R from the middle, tube radius r."""
    pts = arc_pts(c, R, 0, 360, n, plane=frame_normal(normal))[:-1]
    first = None
    for i in range(n):
        idx = m.rod(name, pts[i], pts[(i + 1) % n], 2 * r, color, mat)
        m.ball(name, 2 * r, pts[i], color, mat)
        first = first or idx
    return first


def glint(m, p, n, s, color=WHITE, mat="Neon"):
    """A four-pointed twinkle facing along n."""
    F = frame_normal(n)
    m.add("E", "Glint", (s, s * 0.17, 0.03), p, color, mat, F)
    m.add("E", "Glint", (s * 0.17, s, 0.03), p, color, mat, F)


def hex_prism(m, name, c, axis, d, L, color, mat="Metal"):
    """A six-sided prism (a bolt head, a nut) d across its corners and L long, along axis."""
    F = frame_from_x(norm(axis))
    for k in range(3):
        m.add("B", name, (L, d * 0.866, d * 0.5), c, color, mat, F @ Rx(60 * k))


def tile(m, name, c, R, top, side, size=0.66, h=0.36, top_mat="SmoothPlastic", top_tr=0.0):
    """A little block of land: earth underneath and a top layer (grass, sand, snow, water)."""
    with m.group(R=R, t=c):
        m.rbox(name, (size, h * 0.7, size), (0, -h * 0.15, 0), side, size * 0.1)
        m.rbox(name, (size + 0.02, h * 0.36, size + 0.02), (0, h * 0.32, 0), top, size * 0.11, top_mat, tr=top_tr)


def peak(m, name, base, hw, h, color, snow=None, snow_k=0.36, R=I3):
    """A low-poly mountain standing on base: two crossed triangular ridges, an optional snow cap."""
    with m.group(R=R, t=base):
        tri(m, name, V(0, 0, 0), hw, h, hw * 1.15, color, plane="xy")
        tri(m, name, V(0, 0, 0), hw, h, hw * 1.15, shade(color, 0.9), plane="zy")
        if snow is not None:
            s = snow_k
            for plane in ("xy", "zy"):
                tri(m, "Snow", V(0, h * (1 - s) - 0.01, 0), hw * s + 0.02, h * s + 0.03, hw * 1.15 * s + 0.04, snow, plane=plane)


def ground_on_zero(m):
    """Moves the model so its lowest point sits exactly on y = 0."""
    lo, hi = m.bounds()
    dy = -lo[1]
    for p in m.parts:
        p["pos"] = (p["pos"][0], p["pos"][1] + dy, p["pos"][2])


# ------------------------------------------------------------------------------------------------
# Common
# ------------------------------------------------------------------------------------------------
@model
def spare_battery():
    """A chunky battery with an eager grin, a copper top, a charge meter and sparks off its terminal."""
    m = SModel("spare_battery", "spell")
    BODY = (46, 132, 222)
    BODY_D = (22, 58, 124)
    TOP = (240, 156, 66)
    CH = (214, 220, 230)
    LIME = (130, 240, 90)
    YEL = (255, 214, 60)
    R = 0.7
    with m.group(R=Rz(-5) @ Ry(10), t=(0, 0.07, 0)):
        m.cyl("Body", 1.96, 2 * R, (0, 1.12, 0), BODY)
        m.cyl("Base", 0.16, 2 * R - 0.12, (0, 0.08, 0), CH, "y", "Metal")
        m.cyl("Rim", 0.12, 2 * R + 0.04, (0, 0.2, 0), BODY_D)
        m.cyl("Top", 0.52, 2 * R + 0.04, (0, 1.86, 0), TOP, "y", "Metal")
        m.cyl("Rim", 0.07, 2 * R + 0.07, (0, 2.1, 0), shade(TOP, 0.88), "y", "Metal")
        m.cyl("TopPlate", 0.08, 2 * R - 0.14, (0, 2.15, 0), shade(TOP, 0.86), "y", "Metal")
        m.cyl("Terminal", 0.22, 0.5, (0, 2.28, 0), CH, "y", "Metal")
        m.ell("Terminal", (0.5, 0.16, 0.5), (0, 2.39, 0), CH, "Metal")
        for y in (0.44, 1.56):
            m.cyl("Stripe", 0.07, 2 * R + 0.02, (0, y, 0), YEL, "y")
        # a + on the copper band
        p, n = cyl_pt(R + 0.03, 0, 1.86)
        m.blk("Plus", (0.26, 0.07, 0.04), p, WHITE)
        m.blk("Plus", (0.07, 0.26, 0.04), p, WHITE)
        # the face
        for s in (-1, 1):
            p, n = cyl_pt(R, s * 18, 1.18)
            m.eye(p, n, 0.32, 0.4, BODY, "eager", brow=BODY_D)
        p, n = cyl_pt(R, 0, 0.84)
        m.mouth(p, n, 0.46, "cheerful", d=0.07)
        for s in (-1, 1):
            p, n = cyl_pt(R + 0.005, s * 36, 0.95)
            m.ell("Cheek", (0.2, 0.1, 0.05), p, (255, 130, 170), R=Ry(-s * 36))
        # shine down one side
        p, n = cyl_pt(R + 0.012, 44, 1.02)
        m.blk("Shine", (0.09, 1.1, 0.03), p, WHITE, R=Ry(-44), tr=0.45)
        # a charge meter on the other side: three glowing bars
        p, n = cyl_pt(R + 0.012, -62, 0.86)
        m.rbox("Meter", (0.36, 0.88, 0.06), p, BODY_D, 0.08, R=Ry(62), axis="z")
        for y in (0.6, 0.86, 1.12):
            q, _ = cyl_pt(R + 0.05, -62, y)
            m.rbox("Charge", (0.26, 0.18, 0.05), q, LIME, 0.05, "Neon", R=Ry(62), axis="z")
        # a lightning bolt on the back
        m.bolt("Emblem", (0, 1.46, R + 0.025), 0.86, color=YEL, mat="SmoothPlastic", R=Ry(180))
        # sparks jumping off the terminal
        m.bolt("Zap", (0.44, 2.86, -0.04), 0.42, color=(255, 236, 90), R=Rz(-30))
        m.bolt("Zap", (-0.38, 2.76, 0.06), 0.34, color=(255, 236, 90), R=Rz(32))
        glint(m, V(0.05, 2.78, -0.2), (0, 0, -1), 0.26, (255, 246, 170))
    return m


@model
def wrong_turn():
    """A U-turn road sign caught mid-spin on its post, on a round chunk of road."""
    m = SModel("wrong_turn", "spell")
    ASPH = (84, 86, 98)
    ASPH_D = (58, 60, 70)
    CURB = (206, 202, 194)
    SIGN = (255, 202, 40)
    BLACK = (32, 30, 38)
    POLE = (176, 182, 194)
    # the road chunk
    m.cyl("Road", 0.22, 2.6, (0, 0.11, 0), ASPH)
    loop_tube(m, "Curb", V(0, 0.2, 0), 1.27, 0.11, (0, 1, 0), CURB, n=24)
    for x in (-0.78, 0.0, 0.78):
        m.blk("RoadLine", (0.46, 0.03, 0.13), (x, 0.235, -0.52), WHITE)
    for pts in (((-0.55, 0.62), (-0.32, 0.4), (-0.4, 0.12)), ((0.62, 0.1), (0.86, -0.02), (0.98, 0.18))):
        P = [V(x, 0.226, z) for (x, z) in pts]
        for a, b in zip(P[:-1], P[1:]):
            m.seg("Crack", a, b, 0.012, ASPH_D, r2=0.026, shape="B", ext=0.01)
    grass(m, [V(-0.62, 0.22, 0.72), V(0.86, 0.22, 0.34), V(0.25, 0.22, 0.95)], n=3, length=0.22, width=0.08)
    m.ell("Pebble", (0.16, 0.1, 0.13), (-0.85, 0.25, -0.2), (150, 146, 140))
    m.ell("Pebble", (0.12, 0.08, 0.1), (0.5, 0.25, -0.86), (150, 146, 140))
    # the post in a concrete footing
    PX, PZ = 0.08, 0.32
    m.cyl("Footing", 0.18, 0.56, (PX, 0.3, PZ), CURB, "y", "Concrete")
    m.ell("Footing", (0.56, 0.12, 0.56), (PX, 0.39, PZ), CURB)
    base, top = V(PX, 0.3, PZ), V(PX + 0.06, 2.62, PZ + 0.03)
    m.rod("Pole", base, top, 0.16, POLE, "Metal")
    m.ball("PoleCap", 0.2, top + V(0, 0.04, 0), POLE, "Metal")
    for (y, h, c) in ((0.76, 0.14, (236, 62, 62)), (0.92, 0.1, WHITE), (1.06, 0.14, (236, 62, 62))):
        q = base + (top - base) * ((y - base[1]) / (top[1] - base[1]))
        m.cyl("Reflector", h, 0.19, q, c, "y")
    # the sign: a yellow diamond with a thick U-turn arrow, turned on the post as if spinning
    sc = base + (top - base) * ((2.06 - base[1]) / (top[1] - base[1]))
    for y in (1.72, 2.4):
        q = base + (top - base) * ((y - base[1]) / (top[1] - base[1]))
        m.cyl("Clamp", 0.1, 0.22, q, (120, 124, 134), "y", "Metal")
    with m.group(R=Ry(26), t=sc):
        with m.group(R=Rz(45)):
            m.rbox("SignBack", (1.36, 1.36, 0.08), (0, 0, -0.05), (150, 154, 164), 0.13, "Metal", axis="z")
            m.rbox("Sign", (1.3, 1.3, 0.08), (0, 0, -0.12), SIGN, 0.13, axis="z")
            for (x, y, w, h) in ((0, 0.53, 1.1, 0.06), (0, -0.53, 1.1, 0.06), (0.53, 0, 0.06, 1.1), (-0.53, 0, 0.06, 1.1)):
                m.blk("SignBorder", (w, h, 0.02), (x, y, -0.168), BLACK)
        for y in (-0.62, 0.62):
            m.ball("SignBolt", 0.09, (0, y, -0.17), (190, 194, 204), "Metal")
        z = -0.17
        ox = -0.06
        m.seg("Arrow", V(ox - 0.2, -0.36, z), V(ox - 0.2, 0.06, z), 0.068, BLACK, r2=0.02, shape="B")
        pts = arc_pts(V(ox, 0.06, z), 0.2, 180, 0, 6)
        for a, b in zip(pts[:-1], pts[1:]):
            m.seg("Arrow", a, b, 0.068, BLACK, r2=0.02, shape="B", ext=0.02)
        m.seg("Arrow", V(ox + 0.2, 0.06, z), V(ox + 0.2, -0.12, z), 0.068, BLACK, r2=0.02, shape="B")
        with m.group(R=Rz(180), t=V(ox + 0.2, -0.1, z)):
            tri(m, "Arrow", V(0, 0, 0), 0.19, 0.28, 0.04, BLACK)
        # a sticker someone slapped on it
        m.ell("Sticker", (0.2, 0.2, 0.02), (0.36, -0.3, -0.17), (90, 200, 250))
        star(m, "Sticker", V(0.36, -0.3, -0.19), (0, 0, -1), 0.1, 0.026, WHITE)
    # spin trails sweeping round the sign
    # spin marks curving round both sides of the sign
    with m.group(R=Ry(26), t=sc):
        for (a0, a1) in ((150, 205), (-25, 30)):
            for k, rr in enumerate((1.08, 1.24)):
                pts = arc_pts(V(0, 0, 0.06), rr, a0 + k * 6, a1 - k * 6, 5)
                stroke(m, "Swoosh", pts, 0.045 - k * 0.012, 0.02, WHITE, tr=0.2)
    return m


@model
def water_balloon():
    """A heavy water balloon with a cheeky grin, sagging in its own puddle."""
    m = SModel("water_balloon", "spell")
    BL = (60, 152, 252)
    BL_D = (24, 70, 160)
    WATER = (120, 196, 255)
    m.ell("Puddle", (2.7, 0.05, 2.3), (0.1, 0.025, -0.1), WATER, "Glass", tr=0.3, refl=0.3)
    m.ell("Puddle", (1.2, 0.055, 0.9), (-0.95, 0.028, -0.8), WATER, "Glass", tr=0.3, refl=0.3)
    C, S = V(0, 0.84, 0), V(2.0, 1.68, 1.92)
    m.ell("Balloon", S, C, BL, refl=0.12)
    m.ell("Balloon", (0.98, 1.0, 0.96), (0, 1.6, 0.02), BL, refl=0.12)
    m.ell("Neck", (0.38, 0.4, 0.38), (0, 2.06, 0.04), shade(BL, 0.86))
    torus(m, "Knot", (0, 2.24, 0.04), 0.12, 0.07, shade(BL, 0.8), n=8, normal=(0, 1, 0))
    m.ball("Knot", 0.26, (0, 2.32, 0.04), shade(BL, 0.86))
    m.seg("KnotTail", (0.05, 2.33, 0.03), (0.32, 2.2, -0.02), 0.075, shade(BL, 0.86), bulge=0.3)
    m.seg("KnotTail", (-0.05, 2.34, 0.07), (-0.27, 2.25, 0.14), 0.07, shade(BL, 0.86), bulge=0.3)
    # a cheeky face
    cheeky = dict(open=1.0, lid=0, brow=16, lift=0.16, mouth="smirk", curve=0.32, look=(0.12, 0))
    m.eyes_on(C, S, I3, 19, 14, 0.36, 0.44, BL, cheeky, brow=BL_D)
    p, n = on_ell_R(C, S, I3, V(0.03, -0.16, -1))
    m.mouth(p, n, 0.56, cheeky, skin=BL, side_bias=1)
    for s in (-1, 1):
        p, n = on_ell_R(C, S, I3, V(s * 0.58, -0.08, -0.82))
        m.add("E", "Cheek", (0.24, 0.12, 0.05), p, (255, 140, 200), "SmoothPlastic", frame_normal(n))
    # shine
    p, n = on_ell_R(C, S, I3, V(0.55, 0.6, -0.58))
    m.add("E", "Shine", (0.3, 0.52, 0.05), p, WHITE, "SmoothPlastic", frame_normal(n, -32), 0.3)
    p, n = on_ell_R(C, S, I3, V(0.7, 0.32, -0.63))
    m.add("E", "Shine", (0.12, 0.14, 0.04), p, WHITE, "SmoothPlastic", frame_normal(n), 0.3)
    # splashes and a drip from the knot
    for (p, d) in (((-1.28, 0.3, -0.55), 0.18), ((1.32, 0.48, -0.32), 0.15), ((0.95, 0.16, -1.08), 0.13), ((-0.72, 0.6, -1.02), 0.12)):
        m.drop("Drop", p, d, WATER, "Glass", tr=0.15)
    m.drop("Drop", (0.2, 2.0, -0.16), 0.1, WATER, "Glass", tr=0.15)
    return m


@model
def snack_break():
    """A chocolate chip cookie leaning on a glass of milk with a bendy straw, on a checked napkin."""
    m = SModel("snack_break", "spell")
    DOUGH = (226, 162, 86)
    DOUGH_D = (186, 118, 58)
    CHOC = (92, 52, 34)
    MILK = (250, 250, 246)
    GL = (210, 236, 250)
    RED = (226, 64, 64)
    with m.group(R=Ry(14)):
        m.blk("Napkin", (2.3, 0.03, 2.3), (0, 0.015, 0), WHITE)
        for i in range(4):
            for j in range(4):
                if (i + j) % 2 == 0:
                    m.blk("NapkinCheck", (0.575, 0.024, 0.575), (-0.8625 + i * 0.575, 0.034, -0.8625 + j * 0.575), RED)
    # the glass of milk
    gx, gz = 0.5, 0.32
    m.cyl("GlassBase", 0.16, 1.0, (gx, 0.12, gz), GL, "y", "Glass", tr=0.25, refl=0.25)
    m.cyl("Milk", 1.2, 0.88, (gx, 0.8, gz), MILK)
    m.ell("Milk", (0.88, 0.08, 0.88), (gx, 1.4, gz), MILK)
    m.cyl("Glass", 1.58, 1.0, (gx, 0.84, gz), GL, "y", "Glass", tr=0.55, refl=0.2)
    torus(m, "GlassRim", (gx, 1.63, gz), 0.49, 0.045, GL, n=14, normal=(0, 1, 0), mat="Glass", tr=0.3, refl=0.3)
    p, n = cyl_pt(0.51, -36, 0.92, (gx, gz))
    m.blk("GlassShine", (0.08, 1.0, 0.02), p, WHITE, R=Ry(36), tr=0.35)
    a, _ = cyl_pt(0.515, 8, 1.6, (gx, gz))
    b, _ = cyl_pt(0.515, 8, 1.2, (gx, gz))
    m.seg("MilkDrip", a, b, 0.045, MILK, shape="C")
    m.ball("MilkDrip", 0.12, b, MILK)
    stripes(m, "Straw", [V(gx + 0.12, 1.0, gz + 0.1), V(gx + 0.2, 1.92, gz + 0.12), V(gx + 0.15, 2.1, gz + 0.12),
                         V(gx - 0.18, 2.26, gz + 0.1)], 0.1, [RED, WHITE], step=0.13)

    def cookie(R, t, d, thick, front, back, seed):
        rnd = random.Random(seed)
        with m.group(R=R, t=t):
            m.cyl("Cookie", thick, d, (0, 0, 0), DOUGH, "z")
            n = 14
            for k in range(n):
                a = 2 * math.pi * (k + 0.25 * (k % 2)) / n
                r = d / 2 - 0.05
                m.ell("CookieEdge", (0.34 * d / 1.6, 0.26 * d / 1.6, thick * 1.08), (math.cos(a) * r, math.sin(a) * r, 0),
                      DOUGH_D if k % 3 == 0 else shade(DOUGH, 0.92), R=Rz(math.degrees(a) + 90))
            for (side, cnt) in ((-1, front), (1, back)):
                placed = []
                tries = 0
                while len(placed) < cnt and tries < 300:
                    tries += 1
                    rr = math.sqrt(rnd.random()) * (d / 2 - 0.2)
                    a = rnd.random() * 2 * math.pi
                    q = (math.cos(a) * rr, math.sin(a) * rr)
                    if any((q[0] - p[0]) ** 2 + (q[1] - p[1]) ** 2 < (d * 0.19) ** 2 for p in placed):
                        continue
                    placed.append(q)
                    s = rnd.uniform(0.14, 0.2) * d / 1.6 + 0.04
                    m.ell("Chip", (s, s * 0.8, 0.12), (q[0], q[1], side * thick / 2), CHOC, R=Rz(rnd.uniform(0, 180)))
            for k in range(3):
                a = rnd.random() * 2 * math.pi
                rr = rnd.uniform(0.15, d / 2 - 0.25)
                m.ell("CookieBump", (0.3 * d / 1.6, 0.22 * d / 1.6, 0.05), (math.cos(a) * rr, math.sin(a) * rr, -thick / 2), shade(DOUGH, 1.08))

    cookie(Ry(26) @ Rx(12), V(-0.36, 0.96, -0.28), 1.6, 0.26, 8, 4, 7)
    cookie(Rx(-90) @ Rz(20), V(0.82, 0.16, -0.68), 1.0, 0.2, 0, 6, 11)
    rnd = random.Random(5)
    for k in range(7):
        x, z = rnd.uniform(-0.9, 0.95), rnd.uniform(-1.0, -0.35)
        s = rnd.uniform(0.07, 0.12)
        m.ell("Crumb", (s, s * 0.7, s * 0.9), (x, 0.06, z), DOUGH_D if k % 2 else DOUGH, R=Ry(rnd.uniform(0, 90)))
    return m


@model
def scrap():
    """A heap of junk: a big gear, a bolt and nuts, a spring, a tin can, a bent pipe and a wrench."""
    m = SModel("scrap", "spell")
    RUST = (178, 92, 48)
    RUST_D = (122, 60, 34)
    TIN = (170, 176, 182)
    TIN_D = (118, 124, 132)
    STEEL = (196, 200, 210)
    BRASS = (214, 170, 70)
    DARKJ = (76, 68, 64)
    YEL = (246, 196, 38)
    # the heap: two rounded mounds that sit flat on the ground
    m.ell("Heap", (2.5, 0.5, 2.0), (0, 0.25, 0.1), DARKJ)
    m.ell("Heap", (1.7, 0.6, 1.3), (-0.05, 0.42, 0.15), shade(DARKJ, 1.08))
    m.puffs("Heap", (0, 0.25, 0.1), (2.5, 0.5, 2.0), 14, 0.34, shade(DARKJ, 0.92), seed=5, ymin=0.15, shade_k=0.2)
    m.puffs("Heap", (-0.05, 0.42, 0.15), (1.7, 0.6, 1.3), 8, 0.3, DARKJ, seed=8, ymin=0.25, shade_k=0.2)

    def heap_y(x, z):
        a = 1 - (x / 1.25) ** 2 - ((z - 0.1) / 1.0) ** 2
        b = 1 - ((x + 0.05) / 0.85) ** 2 - ((z - 0.15) / 0.65) ** 2
        return max(0.25 + 0.25 * math.sqrt(max(a, 0)), 0.42 + 0.3 * math.sqrt(b) if b > 0 else 0.0)

    rnd = random.Random(3)
    for k in range(7):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.3, 0.85)
        x, z = math.cos(a) * r * 1.1, 0.1 + math.sin(a) * r * 0.8
        col = (RUST, TIN_D, RUST_D, TIN)[k % 4]
        m.blk("Junk", (rnd.uniform(0.3, 0.5), 0.07, rnd.uniform(0.22, 0.4)), (x, heap_y(x, z), z), col, "Metal",
              R=rot(rnd.uniform(-25, 25), rnd.uniform(0, 180), rnd.uniform(-25, 25)))
    # a big gear standing up at the back
    with m.group(R=Ry(24) @ Rx(-10), t=(-0.32, 1.28, 0.42)):
        rad, th = 0.62, 0.2
        m.cyl("Gear", th, 2 * rad, (0, 0, 0), TIN, "z", "Metal")
        for k in range(10):
            a = 2 * math.pi * k / 10
            d = V(math.cos(a), math.sin(a), 0)
            tg = V(-math.sin(a), math.cos(a), 0)
            m.add("B", "GearTooth", (0.22, 0.2, th), d * (rad + 0.07), TIN, "Metal", np.column_stack([tg, d, V(0, 0, 1)]))
        m.cyl("GearHub", th + 0.08, 0.34, (0, 0, 0), TIN_D, "z", "Metal")
        m.cyl("GearHole", th + 0.1, 0.16, (0, 0, 0), (36, 34, 38), "z")
        for k in range(4):
            a = 2 * math.pi * (k + 0.5) / 4
            m.cyl("GearHole", th + 0.02, 0.2, (math.cos(a) * 0.4, math.sin(a) * 0.4, 0), (52, 50, 54), "z")
        for (x, y, s) in ((0.28, 0.36, 0.2), (-0.36, -0.22, 0.16)):
            m.ell("Rust", (s, s * 0.7, 0.03), (x, y, -th / 2 - 0.005), RUST)
    # a little brass gear and washers lying on the heap
    with m.group(R=rot(-12, 30, 8), t=(-0.6, 0.5, -0.32)):
        m.cyl("Gear", 0.1, 0.5, (0, 0, 0), BRASS, "y", "Metal")
        for k in range(8):
            a = 2 * math.pi * k / 8
            m.blk("GearTooth", (0.11, 0.1, 0.1), (math.cos(a) * 0.28, 0, math.sin(a) * 0.28), BRASS, "Metal", R=Ry(-math.degrees(a)))
        m.cyl("GearHole", 0.12, 0.14, (0, 0, 0), (60, 50, 40), "y")
    for (c, nrm) in ((V(0.66, 0.44, 0.02), V(0.2, 1, -0.3)), (V(-0.2, 0.7, 0.62), V(-0.3, 1, 0.1))):
        torus(m, "Washer", c, 0.09, 0.04, STEEL, n=8, normal=nrm, mat="Metal")
    # a big bolt lying across the front, two nuts
    bh, bt = V(0.62, 0.5, -0.5), V(-0.34, 0.36, -0.78)
    ax = norm(bt - bh)
    hex_prism(m, "BoltHead", bh, ax, 0.46, 0.22, STEEL)
    m.rod("BoltShaft", bh, bt, 0.22, STEEL, "Metal")
    for k in range(6):
        q = bh + (bt - bh) * (0.35 + k * 0.11)
        m.rod("BoltThread", q - ax * 0.02, q + ax * 0.02, 0.26, shade(STEEL, 0.88), "Metal")
    for (c, axn, col) in ((V(-0.9, 0.44, -0.16), V(0.3, 1, -0.2), BRASS), (V(0.2, 0.74, -0.08), V(-0.2, 1, 0.4), STEEL)):
        hex_prism(m, "Nut", c, axn, 0.36, 0.15, col)
        m.rod("NutHole", c - norm(axn) * 0.085, c + norm(axn) * 0.085, 0.15, (40, 38, 42))
    # a spring
    sc = V(0.92, 0.38, 0.32)
    pts = []
    for k in range(25):
        a = 2 * math.pi * k / 8
        pts.append(sc + V(math.cos(a) * 0.17, k * 0.022, math.sin(a) * 0.17))
    for a, b in zip(pts[:-1], pts[1:]):
        m.rod("Spring", a, b, 0.06, STEEL, "Metal")
    # a tin can on its side
    with m.group(R=Ry(-28), t=(-1.0, 0.285, -0.72)):
        m.cyl("Can", 0.7, 0.52, (0, 0, 0), TIN, "x", "Metal")
        m.cyl("CanLabel", 0.4, 0.54, (0.02, 0, 0), (236, 112, 40), "x")
        m.cyl("CanLabel", 0.08, 0.545, (0.02, 0, 0), WHITE, "x")
        for x in (-0.33, 0.33):
            m.cyl("CanRim", 0.05, 0.55, (x, 0, 0), STEEL, "x", "Metal")
        m.cyl("CanInside", 0.02, 0.44, (-0.355, 0, 0), (54, 52, 58), "x")
        disc(m, "CanLid", V(-0.42, 0.2, 0.0), V(-0.6, 0.8, 0), 0.42, 0.025, STEEL, "Metal")
    # a bent pipe sticking out at the back
    p0, p1, p2 = V(0.86, 0.2, 0.66), V(1.04, 1.0, 0.56), V(1.46, 1.06, 0.38)
    m.rod("Pipe", p0, p1, 0.24, RUST, "Metal")
    m.ball("Pipe", 0.26, p1, RUST_D, "Metal")
    m.rod("Pipe", p1, p2, 0.24, RUST, "Metal")
    m.rod("PipeRim", p2 - norm(p2 - p1) * 0.04, p2 + norm(p2 - p1) * 0.04, 0.3, RUST_D, "Metal")
    # a wrench on the heap
    with m.group(R=Ry(-62) @ Rz(8), t=(0.35, 0.72, 0.02)):
        m.rbox("Wrench", (0.9, 0.05, 0.13), (0, 0, 0), STEEL, 0.05, "Metal", axis="y")
        for s in (-1, 1):
            m.blk("WrenchJaw", (0.2, 0.05, 0.08), (0.52, 0, s * 0.11), STEEL, "Metal")
        m.blk("WrenchJaw", (0.08, 0.05, 0.3), (0.42, 0, 0), STEEL, "Metal")
        torus(m, "WrenchRing", (-0.5, 0, 0), 0.11, 0.045, STEEL, n=8, normal=(0, 1, 0), mat="Metal")
    # a hazard plate sticking out of the back
    with m.group(R=rot(-24, 18, 8), t=(0.3, 0.76, 0.72)):
        m.rbox("Plate", (0.8, 0.52, 0.05), (0, 0, 0), YEL, 0.06, "Metal", axis="z")
        for k in range(3):
            m.blk("PlateStripe", (0.1, 0.62, 0.02), (-0.25 + k * 0.25, 0, -0.03), (40, 36, 40), R=Rz(35))
    return m


# ------------------------------------------------------------------------------------------------
# Rare
# ------------------------------------------------------------------------------------------------
@model
def coin_flip_fury():
    """A furious gold coin standing on a pile of coins, steaming, with flip trails behind it."""
    m = SModel("coin_flip_fury", "spell")
    G = (255, 196, 52)
    G_L = (255, 226, 120)
    G_D = (206, 140, 30)
    BROW = (120, 64, 18)

    def flat_coin(p, d=0.86, t=0.12, tilt=(0, 0, 0)):
        with m.group(R=rot(*tilt), t=p):
            m.cyl("Coin", t, d, (0, 0, 0), G, "y", refl=0.15)
            torus(m, "CoinRim", (0, 0, 0), d / 2 - 0.05, t * 0.55, G_L, n=12, normal=(0, 1, 0), mat="Foil")
            star(m, "CoinStar", V(0, t / 2 + 0.005, 0), (0, 1, 0), d * 0.22, 0.03, G_D)

    for (p, tl) in (((-0.1, 0.06, 0.08), (0, 0, 0)), ((-0.04, 0.18, 0.1), (0, 20, 0)), ((-0.12, 0.3, 0.06), (0, 40, 0)),
                    ((1.0, 0.06, 0.45), (0, 0, 0)), ((0.96, 0.18, 0.42), (0, 30, 0)),
                    ((-1.08, 0.2, -0.38), (10, 0, 14)), ((0.78, 0.13, -0.72), (0, 0, -8))):
        flat_coin(V(*p), tilt=tl)
    CR = 1.12
    with m.group(R=Ry(16) @ Rz(-7), t=(-0.1, 1.52, 0.05)):
        m.cyl("Coin", 0.3, 2 * CR, (0, 0, 0), G, "z", refl=0.18)
        torus(m, "CoinRim", (0, 0, 0), 0.98, 0.1, G_L, n=20, normal=(0, 0, -1), flat=1.9, mat="Foil")
        for k in range(24):
            a = 2 * math.pi * k / 24
            d = V(math.cos(a), math.sin(a), 0)
            tg = V(-math.sin(a), math.cos(a), 0)
            m.add("B", "CoinEdge", (0.07, 0.07, 0.32), d * (CR + 0.005), G_D, "SmoothPlastic", np.column_stack([tg, d, V(0, 0, 1)]))
        # the furious face
        furious = dict(open=1.0, lid=0, brow=30, lift=0.02, mouth="flat", curve=0.0)
        for s in (-1, 1):
            m.eye(V(s * 0.36, 0.2, -0.15), (0, 0, -1), 0.4, 0.44, G, furious, brow=BROW, brow_k=1.5)
        mc = V(0, -0.4, -0.155)
        m.ell("Mouth", (0.72, 0.34, 0.08), mc, (90, 30, 34))
        m.blk("Teeth", (0.56, 0.18, 0.05), mc + V(0, 0, -0.03), WHITE)
        m.blk("TeethLine", (0.56, 0.024, 0.03), mc + V(0, 0, -0.056), (160, 150, 150))
        for x in (-0.17, -0.06, 0.06, 0.17):
            m.blk("TeethLine", (0.024, 0.18, 0.03), mc + V(x, 0, -0.056), (160, 150, 150))
        vc = V(0.6, 0.62, -0.17)
        for (sx, sy) in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            m.seg("Anger", vc + V(sx * 0.05, sy * 0.16, 0), vc + V(sx * 0.16, sy * 0.05, 0), 0.035, (232, 40, 48), r2=0.025, ext=0.02)
        # tails side: a star
        star(m, "Emblem", V(0, 0, 0.16), (0, 0, 1), 0.52, 0.05, G_D)
        # steam
        for s in (-1, 1):
            for (x, y, d) in ((1.0, 1.0, 0.2), (1.2, 1.2, 0.34), (1.38, 1.3, 0.3), (1.3, 1.42, 0.28)):
                m.ball("Steam", d, (s * x, y, 0.02), (244, 244, 248), tr=0.3)
        # flip trails
        for (a0, a1) in ((26, 86), (206, 266)):
            pts = arc_pts(V(0, 0, 0.12), 1.46, a0, a1, 5)
            stroke(m, "Swoosh", pts, 0.06, 0.025, WHITE, tr=0.5, r_end=0.022)
        glint(m, V(0.72, 0.74, -0.24), (0, 0, -1), 0.4)
    glint(m, V(1.2, 0.36, 0.2), (-0.4, 0.3, -1), 0.26)
    return m


@model
def sneeze_storm():
    """A tissue box with a red nose, caught mid-sneeze: a stormy sneeze cloud bursts out of it."""
    m = SModel("sneeze_storm", "spell")
    BOX = (126, 206, 192)
    BOX_D = (70, 150, 140)
    BOX_L = (196, 238, 228)
    TISSUE = (250, 250, 255)
    SNEEZE = (222, 244, 214)
    INKC = (40, 52, 60)
    bx, bz = -0.35, 0.2
    W, H, D = 1.6, 1.16, 1.24
    m.rbox("Box", (W, H, D), (bx, H / 2, bz), BOX, 0.16, refl=0.06)
    m.rbox("BoxBand", (W + 0.02, 0.18, D + 0.02), (bx, 0.12, bz), BOX_D, 0.17)
    m.rbox("BoxTop", (W - 0.06, 0.06, D - 0.06), (bx, H + 0.02, bz), BOX_L, 0.13)
    m.ell("SlotRim", (0.96, 0.05, 0.44), (bx, H + 0.05, bz), BOX_D)
    m.ell("Slot", (0.84, 0.06, 0.32), (bx, H + 0.055, bz), (40, 60, 64))
    # polka dots on the sides and back
    for (x, y, z, nrm) in ((bx - W / 2, 0.72, bz - 0.25, (-1, 0, 0)), (bx - W / 2, 0.5, bz + 0.3, (-1, 0, 0)), (bx - W / 2, 0.88, bz + 0.2, (-1, 0, 0)),
                           (bx + W / 2, 0.72, bz + 0.2, (1, 0, 0)), (bx + W / 2, 0.5, bz - 0.3, (1, 0, 0)),
                           (bx - 0.4, 0.7, bz + D / 2, (0, 0, 1)), (bx + 0.35, 0.5, bz + D / 2, (0, 0, 1))):
        m.add("E", "Dot", (0.22, 0.22, 0.04), (x, y, z), BOX_L, "SmoothPlastic", frame_normal(nrm))
    # the tissue flopping out of the slot
    tp = [V(bx, H + 0.02, bz), V(bx + 0.06, H + 0.44, bz + 0.04), V(bx + 0.02, H + 0.76, bz + 0.22), V(bx - 0.08, H + 0.9, bz + 0.5)]
    for (p, q, w) in zip(tp[:-1], tp[1:], (0.66, 0.6, 0.44)):
        v = q - p
        plank(m, "Tissue", p - v * 0.15, q + v * 0.15, w, 0.16, TISSUE, shape="E")
    m.ell("Tissue", (0.3, 0.16, 0.24), tp[1] + V(0.22, 0.02, 0.0), TISSUE, R=Rz(-30))
    m.ell("Tissue", (0.26, 0.14, 0.22), tp[2] + V(-0.2, -0.04, 0.02), TISSUE, R=Rz(24))
    # the sneezing face: eyes squeezed shut > <, a red nose, a big open mouth
    fz = bz - D / 2
    for s in (-1, 1):
        ex, ey = bx + s * 0.36, 0.82
        inner = -s
        tip = V(ex + inner * 0.11, ey, fz - 0.02)
        for dy in (0.11, -0.11):
            m.seg("Eye", V(ex - inner * 0.13, ey + dy, fz - 0.02), tip, 0.045, INKC, r2=0.03, ext=0.03)
        m.seg("Brow", V(ex - inner * 0.17, ey + 0.2, fz - 0.02), V(ex + inner * 0.13, ey + 0.28, fz - 0.02), 0.05, BOX_D, r2=0.03, ext=0.03)
        m.ell("Cheek", (0.24, 0.12, 0.04), (bx + s * 0.6, 0.6, fz - 0.01), (250, 140, 160))
    m.ell("Nose", (0.22, 0.17, 0.16), (bx, 0.64, fz - 0.06), (240, 110, 110))
    m.ell("Nose", (0.07, 0.05, 0.03), (bx + 0.05, 0.69, fz - 0.14), WHITE)
    m.ell("Mouth", (0.52, 0.38, 0.1), (bx, 0.36, fz - 0.01), (70, 24, 40))
    m.ell("Tongue", (0.3, 0.12, 0.06), (bx, 0.27, fz - 0.04), (240, 110, 130))
    # the sneeze: puffs widening into a little storm cloud
    M = V(bx, 0.38, fz - 0.06)
    dr = norm(V(0.66, 0.2, -0.72))
    for (s, d) in ((0.26, 0.34), (0.56, 0.48), (0.92, 0.62)):
        m.ball("Sneeze", d, M + dr * s, SNEEZE, tr=0.1)
    cc = M + dr * 1.46 + V(0, 0.24, 0)
    m.ell("Sneeze", (1.2, 0.7, 0.9), cc, SNEEZE, tr=0.05)
    m.puffs("Sneeze", cc, (1.2, 0.7, 0.9), 11, 0.46, SNEEZE, seed=3, ymin=-0.25, shade_k=0.12)
    m.bolt("Zap", cc + V(0.06, -0.16, -0.12), 0.62, color=(255, 230, 80))
    for (x, z) in ((-0.32, 0.1), (0.3, -0.05), (0.0, 0.2)):
        m.drop("Rain", cc + V(x, -0.62, z), 0.12, (150, 210, 250), "Glass", tr=0.1)
    rnd = random.Random(9)
    side = norm(np.cross(dr, V(0, 1, 0)))
    for k in range(6):
        s = rnd.uniform(0.3, 1.1)
        o = side * rnd.uniform(-0.35, 0.35) + V(0, rnd.uniform(-0.25, 0.3), 0)
        m.ball("Spray", rnd.uniform(0.07, 0.11), M + dr * s + o * s, (170, 220, 250), "Glass", tr=0.1, refl=0.2)
    for k in range(3):
        o = side * (k - 1) * 0.3 + V(0, (k - 1) * 0.1, 0)
        m.seg("SprayLine", M + dr * 0.3 + o, M + dr * 0.75 + o * 1.6, 0.025, WHITE, tr=0.3)
    # used tissues on the floor
    for (c, k) in ((V(0.72, 0.2, 0.62), 0), (V(-1.32, 0.2, -0.36), 1)):
        for j in range(3):
            a = math.radians(j * 120 + k * 40)
            m.ell("UsedTissue", (0.28, 0.24, 0.26), c + V(math.cos(a) * 0.08, 0.02 * j, math.sin(a) * 0.08), TISSUE, R=rot(j * 30, j * 50, k * 20))
    return m


@model
def bubble_wrap():
    """A roll of bubble wrap with a sheet pulled out in front, a couple of bubbles already popped."""
    m = SModel("bubble_wrap", "spell")
    WR = (176, 222, 255)
    BUB = (214, 240, 255)
    CARD = (196, 152, 98)
    CARD_D = (120, 86, 52)
    rc = V(0.1, 0.77, 0.42)
    RR, RL = 0.66, 1.8
    m.cyl("Roll", RL, 2 * RR, rc, WR, "x", "Glass", tr=0.3, refl=0.2)
    m.cyl("Core", RL + 0.08, 0.46, rc, CARD, "x", "Cardboard")
    m.cyl("CoreHole", RL + 0.1, 0.32, rc, CARD_D, "x")
    for s in (-1, 1):
        for r in (0.52, 0.38):
            torus(m, "RollLayer", rc + V(s * (RL / 2 + 0.01), 0, 0), r, 0.025, shade(WR, 0.86), n=12, normal=(1, 0, 0), mat="Glass", tr=0.15)
    for i, x in enumerate((-0.72, -0.36, 0.0, 0.36, 0.72)):
        for k in range(10):
            a = math.radians(k * 36 + (18 if i % 2 else 0))
            d = V(0, math.cos(a), math.sin(a))
            m.ball("Bubble", 0.22, rc + V(x, 0, 0) + d * (RR - 0.02), BUB, "Glass", tr=0.15, refl=0.35)
    # the sheet pulled out in front
    z0, z1 = rc[2] - 0.1, -1.2
    m.blk("Sheet", (1.7, 0.04, z0 - z1), (rc[0], 0.02, (z0 + z1) / 2), WR, "Glass", tr=0.25, refl=0.2)
    m.cyl("SheetCurl", 1.7, 0.18, (rc[0], 0.09, z1), WR, "x", "Glass", tr=0.25, refl=0.2)
    popped = {(4, 3), (1, 1)}
    for i in range(5):
        for j in range(4):
            x, z = rc[0] - 0.68 + 0.34 * i, -0.18 - 0.28 * j
            if (i, j) in popped:
                m.ell("Popped", (0.28, 0.035, 0.28), (x, 0.045, z), shade(WR, 0.9), "Glass", tr=0.15)
                m.rod("Popped", (x - 0.08, 0.06, z - 0.06), (x + 0.08, 0.06, z + 0.06), 0.024, WHITE)
                m.rod("Popped", (x - 0.08, 0.06, z + 0.06), (x + 0.08, 0.06, z - 0.06), 0.024, WHITE)
            else:
                m.ell("Bubble", (0.26, 0.16, 0.26), (x, 0.1, z), BUB, "Glass", tr=0.15, refl=0.35)
    # a POP burst over the popped bubble at the front
    bc = V(rc[0] + 0.82, 0.62, -1.02)
    F = frame_normal(V(-0.35, 0.15, -1))
    for k in range(8):
        a = math.radians(k * 45 + 10)
        d = F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)
        L = 0.34 if k % 2 == 0 else 0.24
        Fr = np.column_stack([d, np.cross(F[:, 2], d), F[:, 2]])
        m.add("E", "Burst", (L, 0.12, 0.05), bc + d * L * 0.42, (255, 226, 80), "SmoothPlastic", Fr)
    m.add("E", "Burst", (0.26, 0.26, 0.06), bc, (255, 246, 170), "SmoothPlastic", F)
    for k in range(3):
        a = math.radians(-60 + k * 40)
        d = F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)
        m.seg("PopLine", bc + d * 0.36, bc + d * 0.56, 0.025, WHITE)
    # a strip of tape holding the loose end
    p = rc + V(0.3, RR * 0.72, -RR * 0.72)
    m.blk("Tape", (0.34, 0.03, 0.46), p, (250, 236, 180), R=Rx(45), tr=0.2)
    glint(m, rc + V(-0.5, RR * 0.6, -RR * 0.85), (0, 0.5, -1), 0.3)
    return m


# ------------------------------------------------------------------------------------------------
# Epic
# ------------------------------------------------------------------------------------------------
@model
def pep_talk():
    """A striped megaphone on a stand on a wooden soapbox, glowing sound rings booming out of it."""
    m = SModel("pep_talk", "spell")
    WOOD = (198, 142, 86)
    WOOD_D = (146, 96, 56)
    WOOD_L = (228, 184, 126)
    RED = (230, 52, 52)
    CREAM = (250, 240, 220)
    DARK = (52, 50, 60)
    GOLDC = (255, 204, 70)
    RING = (255, 236, 140)
    # the soapbox
    m.rbox("Crate", (1.56, 0.86, 1.24), (0, 0.43, 0.22), WOOD, 0.08)
    fz = 0.22 - 0.62
    for y in (0.29, 0.57):
        m.blk("CratePlank", (1.4, 0.03, 0.02), (0, y, fz - 0.005), WOOD_D)
        m.blk("CratePlank", (0.02, 0.03, 1.1), (-0.785, y, 0.22), WOOD_D)
    for (x, z) in ((-0.74, fz + 0.06), (0.74, fz + 0.06), (-0.74, 0.22 + 0.56), (0.74, 0.22 + 0.56)):
        m.blk("CratePost", (0.16, 0.9, 0.16), (x, 0.45, z), WOOD_D)
    m.rbox("CrateTop", (1.6, 0.06, 1.28), (0, 0.88, 0.22), WOOD_L, 0.08)
    m.rbox("Label", (0.86, 0.38, 0.04), (0, 0.44, fz - 0.03), CREAM, 0.06, axis="z")
    m.text("LabelText", "PEP", (0, 0.44, fz - 0.06), 0.22, RED, facing="front")
    star(m, "Sticker", V(-0.8, 0.5, 0.25), (-1, 0, 0), 0.24, 0.03, GOLDC)
    # the megaphone, built along local +x (mouthpiece at 0, bell at L) and pointed up and out
    L = 1.8
    dr = norm(V(0.62, 0.34, -0.7))
    up = norm(V(0, 1, 0) - dr * dr[1])
    Rm = np.column_stack([dr, up, np.cross(dr, up)])
    O = V(-0.56, 1.5, 0.6)
    with m.group(R=Rm, t=O):
        m.cyl("Mouthpiece", 0.3, 0.26, (0.06, 0, 0), DARK, "x")
        m.ball("Mouthpiece", 0.27, (-0.09, 0, 0), DARK)
        m.cyl("Mouthpiece", 0.06, 0.32, (0.2, 0, 0), GOLDC, "x", "Foil")
        n = 6
        for k in range(n):
            x0 = 0.22 + (L - 0.22) * k / n
            x1 = 0.22 + (L - 0.22) * (k + 1) / n
            t = (k + 0.5) / n
            r = 0.15 + 0.42 * t ** 1.35
            m.cyl("Cone", x1 - x0 + 0.01, 2 * r, ((x0 + x1) / 2, 0, 0), RED if k % 2 == 0 else WHITE, "x", refl=0.08)
        torus(m, "Bell", (L, 0, 0), 0.6, 0.075, GOLDC, n=16, normal=(1, 0, 0), mat="Foil")
        disc(m, "BellInside", V(L - 0.03, 0, 0), V(1, 0, 0), 1.1, 0.03, (40, 30, 50))
        torus(m, "Grille", (L - 0.01, 0, 0), 0.3, 0.03, (90, 88, 100), n=10, normal=(1, 0, 0))
        m.ell("Driver", (0.12, 0.26, 0.26), (L - 0.03, 0, 0), (90, 88, 100), "Metal")
        for s in (-1, 1):
            star(m, "ConeStar", V(1.1, 0, s * 0.43), (0, 0.15, s), 0.2, 0.03, GOLDC)
        m.seg("Grip", V(0.6, -0.12, 0), V(0.52, -0.62, 0), 0.1, DARK, r2=0.12, shape="E")
        m.blk("Trigger", (0.08, 0.16, 0.06), (0.66, -0.3, 0), RED)
        rings = []
        for (k, (dx, rr, trn)) in enumerate(((0.3, 0.6, 0.3), (0.62, 0.74, 0.5), (0.94, 0.88, 0.68))):
            rings.append(torus(m, "SoundRing", (L + dx, 0, 0), rr, 0.035, RING, n=18, normal=(1, 0, 0), mat="Neon", tr=trn))
    grip = O + Rm @ V(0.52, -0.66, 0)
    # a little stand holding the grip
    m.cyl("StandBase", 0.06, 0.5, (grip[0], 0.92, grip[2]), DARK, "y", "Metal")
    m.rod("Stand", V(grip[0], 0.92, grip[2]), grip, 0.08, (170, 174, 184), "Metal")
    m.ball("StandClamp", 0.16, grip, (170, 174, 184), "Metal")
    # pep sparks: exclamation marks and stars bursting out
    bell = O + Rm @ V(L + 0.6, 0, 0)
    for (o, h) in ((V(0.1, 0.95, 0.1), 0.5), (V(0.6, 0.7, 0.3), 0.36)):
        p = bell + o
        m.seg("Bang", p + V(0, h * 0.5, 0), p - V(0, h * 0.1, 0), h * 0.13, GOLDC, bulge=0.35)
        m.ball("Bang", h * 0.24, p - V(0, h * 0.4, 0), GOLDC)
    star(m, "Spark", bell + V(-0.6, 0.85, -0.1), (-0.3, 0.2, -1), 0.18, 0.04, GOLDC)
    star(m, "Spark", bell + V(0.75, -0.2, -0.2), (0.2, 0.1, -1), 0.14, 0.04, GOLDC)
    m.light(rings[0], (255, 230, 150), 1.2, 6)
    return m


@model
def terrain_shift():
    """A folded map with a pop-up landscape and a big red pin; blocks of land swap round above it."""
    m = SModel("terrain_shift", "spell")
    PAPER = (240, 226, 186)
    PAPER_D = (214, 196, 150)
    INKB = (150, 110, 70)
    GREEN = (110, 186, 80)
    GREEN_D = (80, 150, 60)
    WATER = (90, 170, 240)
    ROCK = (150, 142, 140)
    REDP = (226, 50, 56)
    CYAN = (90, 236, 255)
    Z = 0.1

    def panel(R, hinge, cx, prints):
        with m.group(R=R, t=hinge):
            m.blk("Map", (0.95, 0.05, 1.9), (cx, 0, Z), PAPER)
            for s in (-1, 1):
                m.blk("MapEdge", (0.95, 0.022, 0.05), (cx, 0.026, Z + s * 0.87), INKB)
            m.blk("MapCrease", (0.95, 0.022, 0.025), (cx, 0.026, Z), PAPER_D)
            prints(cx)

    def left_prints(cx):
        m.ell("Lake", (0.5, 0.024, 0.32), (cx + 0.05, 0.03, Z + 0.45), WATER)
        for (x, z) in ((-0.2, -0.3), (0.15, -0.45), (-0.05, -0.6)):
            m.ell("Forest", (0.24, 0.024, 0.2), (cx + x, 0.03, Z + z), GREEN)
        for k in range(4):
            m.ell("Path", (0.07, 0.024, 0.07), (cx + 0.3 - k * 0.12, 0.03, Z - 0.1 + k * 0.08), REDP)

    def right_prints(cx):
        for k in range(4):
            m.ell("Path", (0.07, 0.024, 0.07), (cx - 0.35 + k * 0.12, 0.03, Z - 0.05 - k * 0.1), REDP)
        for a in (45, -45):
            m.blk("MapX", (0.26, 0.024, 0.06), (cx + 0.18, 0.031, Z - 0.5), REDP, R=Ry(a))
        m.ell("Forest", (0.3, 0.024, 0.22), (cx + 0.1, 0.03, Z + 0.55), GREEN)
        m.cyl("Compass", 0.06, 0.42, (cx + 0.12, 0.05, Z + 0.1), (210, 170, 80), "y", "Metal")
        m.cyl("Compass", 0.02, 0.34, (cx + 0.12, 0.08, Z + 0.1), (250, 246, 236), "y")
        m.blk("CompassNeedle", (0.05, 0.03, 0.28), (cx + 0.12, 0.095, Z + 0.1), REDP, R=Ry(30))

    def mid_prints(cx):
        m.ell("Land", (0.9, 0.03, 1.4), (cx, 0.03, Z), (170, 210, 120))

    panel(Rz(-8), V(-0.475, 0.05, 0), -0.475, left_prints)
    panel(I3, V(0, 0.05, 0), 0.0, mid_prints)
    panel(Rz(6), V(0.475, 0.05, 0), 0.475, right_prints)
    # the pop-up landscape on the middle panel
    m.cyl("Hill", 0.14, 0.92, (0.12, 0.145, Z + 0.12), GREEN)
    m.ell("Hill", (0.92, 0.36, 0.92), (0.12, 0.215, Z + 0.12), GREEN)
    m.ell("Hill", (0.56, 0.34, 0.5), (0.22, 0.3, Z + 0.06), shade(GREEN, 1.1))
    peak(m, "Mountain", V(-0.2, 0.075, Z + 0.5), 0.52, 0.98, ROCK, snow=WHITE, snow_k=0.42, R=Ry(20))
    peak(m, "Mountain", V(-0.58, 0.06, Z + 0.22), 0.36, 0.68, shade(ROCK, 0.9), snow=WHITE, snow_k=0.42, R=Ry(50))
    m.rod("Trunk", V(0.36, 0.3, Z - 0.02), V(0.38, 0.6, Z - 0.02), 0.08, (130, 84, 50))
    m.ball("TreeTop", 0.36, (0.38, 0.66, Z - 0.02), GREEN_D)
    m.ball("TreeTop", 0.26, (0.4, 0.84, Z - 0.03), shade(GREEN_D, 1.12))
    rv = [V(-0.12, 0.1, Z + 0.3), V(-0.32, 0.09, Z - 0.05), V(-0.22, 0.085, Z - 0.42), V(0.05, 0.085, Z - 0.75)]
    for a, b in zip(rv[:-1], rv[1:]):
        m.seg("River", a, b, 0.02, WATER, r2=0.08, ext=0.04)
    # the map pin stuck in the hill
    p0 = V(0.02, 0.36, Z + 0.1)
    p1 = p0 + V(-0.14, 0.62, -0.18)
    m.rod("PinNeedle", p0, p1, 0.05, (200, 206, 216), "Metal")
    m.ball("PinHead", 0.38, p1 + norm(p1 - p0) * 0.12, REDP, refl=0.1)
    m.ball("PinHead", 0.1, p1 + norm(p1 - p0) * 0.12 + V(0.06, 0.1, -0.12), WHITE)
    # the magic: a glowing ring on the map and blocks of land swapping round above it
    torus(m, "ShiftRing", (0.0, 0.085, Z), 0.82, 0.025, CYAN, n=18, normal=(0, 1, 0), mat="Neon", tr=0.15)
    tiles = (((-0.85, 1.42, -0.2), rot(18, 30, -16), GREEN, (130, 90, 56), "SmoothPlastic", 0),
             ((0.82, 1.72, 0.2), rot(-22, -28, 20), (236, 206, 140), (196, 160, 100), "Sand", 0),
             ((-0.18, 2.14, 0.32), rot(26, 60, 12), (244, 248, 255), (150, 160, 180), "SmoothPlastic", 0),
             ((0.5, 2.5, -0.28), rot(-14, 18, -30), WATER, (130, 90, 56), "Glass", 0.1))
    for (c, R, top, side, mat, trn) in tiles:
        tile(m, "LandBlock", V(*c), R, top, side, size=0.5, h=0.3, top_mat=mat, top_tr=trn)
    pts = []
    for k in range(9):
        t = k / 8
        a = math.radians(-30 + t * 400)
        pts.append(V(math.cos(a) * (0.75 - t * 0.2), 0.3 + t * 2.2, Z + math.sin(a) * (0.6 - t * 0.15)))
    first = None
    for k, p in enumerate(pts):
        idx = m.ball("ShiftSpark", 0.09 - 0.004 * k, p, CYAN, "Neon")
        first = first or idx
    m.light(first, (120, 230, 255), 1.0, 6)
    m.sparkles(first, (150, 240, 255))
    return m


@model
def pothole():
    """A chunk of road propped on a heap of dirt, a dark bottomless pothole in it, and a traffic cone."""
    m = SModel("pothole", "spell")
    ASPH = (82, 84, 96)
    ASPH_D = (60, 62, 72)
    DIRT = (118, 84, 58)
    CURB = (206, 202, 194)
    OR = (255, 122, 30)
    YEL = (255, 206, 50)
    # a pile of rubble holding the slab up
    rnd = random.Random(4)
    for (p, sz, col) in (((-0.75, 0.36, 0.78), (0.8, 0.72, 0.7), (128, 116, 106)), ((0.62, 0.34, 0.8), (0.76, 0.68, 0.66), (146, 134, 122)),
                         ((-0.05, 0.46, 0.92), (0.9, 0.9, 0.7), DIRT), ((0.2, 0.26, 0.42), (0.6, 0.52, 0.5), (130, 120, 112)),
                         ((-0.45, 0.24, 0.4), (0.5, 0.46, 0.44), (150, 140, 130))):
        Rr = rot(rnd.uniform(-15, 15), rnd.uniform(0, 90), rnd.uniform(-15, 15))
        m.blk("Rubble", (sz[0] * 0.8, sz[1] * 0.8, sz[2] * 0.8), p, col, R=Rr)
        m.ell("Rubble", (sz[0] * 0.9, sz[1] * 0.85, sz[2] * 0.95), V(*p) + V(0.03, 0.03, 0), shade(col, 1.08), R=Rr @ Ry(30))
    for k in range(7):
        a = rnd.uniform(0.15, math.pi - 0.15)
        p = V(math.cos(a) * 1.25, 0.07, 0.6 + math.sin(a) * 0.55)
        m.ell("Gravel", (0.18, 0.12, 0.16), p, (150, 140, 130) if k % 2 else (120, 110, 104), R=Ry(rnd.uniform(0, 90)))
    with m.group(R=Rx(-32), t=(-0.1, 0.73, 0.24)):
        m.rbox("Road", (2.4, 0.3, 1.9), (0, 0, 0), ASPH, 0.08)
        m.rbox("RoadBase", (2.44, 0.12, 1.94), (0, -0.19, 0), (96, 80, 66), 0.08)
        m.rbox("Curb", (2.4, 0.42, 0.3), (0, 0.06, 0.82), CURB, 0.06)
        top = 0.15
        m.blk("RoadLine", (2.2, 0.02, 0.09), (0, top + 0.01, -0.8), WHITE)
        for x in (-0.8, 0.0, 0.8):
            m.blk("RoadLine", (0.44, 0.02, 0.09), (x, top + 0.01, 0.5), YEL)
        # the hole: dark rings getting darker towards a faint purple glow, broken asphalt all round
        hc = V(-0.1, top, -0.18)
        rx, rz = 0.72, 0.5
        m.ell("Hole", (2 * rx, 0.03, 2 * rz), hc + V(0, 0.006, 0), (40, 38, 46))
        m.ell("Hole", (2 * rx * 0.78, 0.032, 2 * rz * 0.78), hc + V(0, 0.012, 0), (22, 20, 30))
        m.ell("Hole", (2 * rx * 0.52, 0.034, 2 * rz * 0.52), hc + V(0, 0.018, 0), (10, 8, 18))
        m.ell("HoleGlow", (0.42, 0.036, 0.28), hc + V(0, 0.024, 0), (110, 40, 200), "Neon", tr=0.3)
        for k in range(14):
            a = 2 * math.pi * k / 14 + rnd.uniform(-0.1, 0.1)
            d = V(math.cos(a), 0, math.sin(a))
            p = hc + V(math.cos(a) * rx * 1.02, 0.02, math.sin(a) * rz * 1.02)
            tg = V(-math.sin(a), 0, math.cos(a))
            out = norm(V(math.cos(a) * rz, 0, math.sin(a) * rx))
            F = np.column_stack([tg, V(0, 1, 0), np.cross(tg, V(0, 1, 0))])
            Rt = F @ Rx(rnd.uniform(14, 26))
            m.add("B", "Chunk", (rnd.uniform(0.2, 0.3), 0.1, rnd.uniform(0.14, 0.2)), p, ASPH_D if k % 2 else shade(ASPH, 0.9), "SmoothPlastic", Rt)
        for (a, L) in ((200, 0.5), (330, 0.42), (60, 0.38), (120, 0.46)):
            ar = math.radians(a)
            p0 = hc + V(math.cos(ar) * rx * 1.12, 0.01, math.sin(ar) * rz * 1.12)
            d = V(math.cos(ar), 0, math.sin(ar))
            j = V(-d[2], 0, d[0]) * 0.07
            pts = [p0, p0 + d * L * 0.5 + j, p0 + d * L - j * 0.5]
            for q0, q1 in zip(pts[:-1], pts[1:]):
                m.seg("Crack", q0, q1, 0.012, (30, 30, 36), r2=0.026, shape="B", ext=0.01)
        # a little party hat sinking into the hole
        hp = hc + V(0.18, 0.05, 0.06)
        m.seg("Hat", hp, hp + V(-0.06, 0.26, -0.1), 0.1, (90, 200, 250), bulge=0.15)
        m.ball("HatPom", 0.08, hp + V(-0.06, 0.28, -0.1), (255, 230, 80))
    # the traffic cone
    with m.group(R=Rz(7), t=(1.5, 0.0, -0.5)):
        m.rbox("ConeBase", (0.74, 0.09, 0.74), (0, 0.045, 0), shade(OR, 0.8), 0.12)
        h, r0, n = 1.16, 0.3, 7
        cols = [OR, OR, WHITE, OR, WHITE, OR, OR]
        for k in range(n):
            y0 = 0.09 + (h - 0.09) * k / n
            y1 = 0.09 + (h - 0.09) * (k + 1) / n
            r = r0 * (1 - (k + 0.5) / n * 0.8)
            m.cyl("Cone", y1 - y0 + 0.01, 2 * r, (0, (y0 + y1) / 2, 0), cols[k], refl=0.12 if cols[k] == WHITE else 0)
        m.ball("Cone", 0.12, (0, h, 0), OR)
    # bits of asphalt that broke off
    for (p, s) in (((-1.25, 0.08, -0.62), 0.24), ((0.62, 0.07, -0.95), 0.2), ((-0.5, 0.06, -1.05), 0.16)):
        m.blk("Chunk", (s, s * 0.45, s * 0.8), p, ASPH_D, R=Ry(p[0] * 60))
    return m


# ------------------------------------------------------------------------------------------------
# Mythic
# ------------------------------------------------------------------------------------------------
@model
def mystery_box():
    """A purple gift box with a gold question mark. Its lid is open a crack: glowing eyes peek out."""
    m = SModel("mystery_box", "spell")
    PUR = (124, 60, 206)
    PUR_D = (88, 40, 156)
    PUR_L = (186, 140, 246)
    GOLDC = (255, 204, 70)
    GOLD_D = (200, 140, 36)
    DARK = (24, 10, 44)
    GLOW = (255, 226, 120)
    W, H = 1.6, 1.26
    m.rbox("Box", (W, H, W), (0, H / 2 + 0.06, 0), PUR, 0.12)
    m.rbox("BoxTrim", (W + 0.06, 0.12, W + 0.06), (0, 0.06, 0), GOLDC, 0.14, "Foil")
    qmark(m, "Mark", V(-0.035, 0.7, -W / 2 - 0.02), 0.88, GOLD_D)
    qmark(m, "Mark", V(0.0, 0.73, -W / 2 - 0.05), 0.88, GOLDC)
    for (yaw, x, z) in ((90, -W / 2 - 0.03, 0.0), (-90, W / 2 + 0.03, 0.0), (180, 0.0, W / 2 + 0.03)):
        qmark(m, "Mark", V(x, 0.72, z), 0.62, PUR_L, R=Ry(yaw), segs=7)
    for (p, nrm) in (((-W / 2 - 0.02, 1.08, -0.5), (-1, 0, 0)), ((-W / 2 - 0.02, 0.3, 0.52), (-1, 0, 0)), ((W / 2 + 0.02, 1.06, 0.5), (1, 0, 0)),
                     ((W / 2 + 0.02, 0.32, -0.5), (1, 0, 0)), ((0.55, 1.1, -W / 2 - 0.02), (0, 0, -1)), ((-0.56, 0.3, -W / 2 - 0.02), (0, 0, -1))):
        star(m, "BoxStar", V(*p), nrm, 0.13, 0.03, GOLDC)
    # the dark gap under the lid, two glowing eyes and light spilling out of the sides
    gap = 1.72 * math.sin(math.radians(16))
    m.wedge("Gap", (W - 0.12, gap, W - 0.12), (0, H + 0.06 + gap / 2, 0), DARK, R=Ry(180))
    for s in (-1, 1):
        e = V(s * 0.25, H + 0.06 + gap * 0.45, -W / 2 + 0.03)
        m.ell("Eye", (0.28, 0.15, 0.06), e, GLOW, "Neon", R=Rz(s * 12))
        m.ell("Pupil", (0.07, 0.11, 0.03), e + V(-s * 0.02, 0, -0.025), (60, 20, 60), R=Rz(s * 12))
    m.blk("GapGlow", (W - 0.14, 0.04, 0.05), (0, H + 0.08, -W / 2 + 0.06), GLOW, "Neon")
    for s in (-1, 1):
        m.blk("GapGlow", (0.05, 0.04, W - 0.3), (s * (W / 2 - 0.06), H + 0.08, -0.06), GLOW, "Neon")
    # the lid, open a crack, with a ribbon and a big bow
    with m.group(R=Rx(16), t=(0, H + 0.06, W / 2 + 0.04)):
        LW = W + 0.16
        lc = V(0, 0.13, -LW / 2 + 0.04)
        m.rbox("Lid", (LW, 0.34, LW), lc, PUR_D, 0.12)
        m.blk("Ribbon", (0.3, 0.36, LW + 0.02), lc, GOLDC, "Foil")
        m.blk("Ribbon", (LW + 0.02, 0.36, 0.3), lc, GOLDC, "Foil")
        bc = lc + V(0, 0.2, 0)
        for s in (-1, 1):
            loop_tube(m, "Bow", bc + V(s * 0.3, 0.24, 0), 0.21, 0.07, Rz(-s * 30) @ V(0, 0, -1), GOLDC, n=10, mat="Foil")
            m.seg("BowTail", bc + V(s * 0.08, 0.06, -0.1), bc + V(s * 0.34, -0.02, -0.7), 0.03, GOLDC, "Foil", r2=0.11)
        knot = m.ball("BowKnot", 0.28, bc + V(0, 0.14, -0.02), GOLDC, "Foil")
    m.sparkles(knot, (255, 236, 160))
    # little question marks floating round it
    qmark(m, "Mark", V(1.02, 2.3, -0.2), 0.42, PUR_L, R=Ry(-20) @ Rz(-16), segs=6)
    qmark(m, "Mark", V(-1.06, 2.0, 0.1), 0.34, GOLDC, R=Ry(30) @ Rz(18), segs=6)
    glint(m, V(0.86, 1.4, -0.86), (0.3, 0.2, -1), 0.3)
    m.light(knot, (255, 210, 140), 1.2, 7)
    return m


@model
def earthquake_dance():
    """A pair of shiny dancing shoes stomping on a cracked, glowing slab of rock; rocks fly up."""
    m = SModel("earthquake_dance", "spell")
    ROCK = (128, 112, 104)
    ROCK_D = (92, 80, 76)
    LAVA = (255, 120, 30)
    SHOE = (220, 38, 60)
    SOCK = (250, 250, 252)
    NOTE = (186, 90, 240)
    # the cracked slab: a dark base, a glowing layer and five broken tiles
    m.cyl("Slab", 0.22, 2.7, (0, 0.11, 0), ROCK_D)
    glow = m.cyl("Glow", 0.06, 2.5, (0, 0.24, 0), LAVA, "y", "Neon")
    rnd = random.Random(2)
    tops = []
    for k in range(5):
        a = math.radians(k * 72 + 12)
        u = V(math.cos(a), 0, math.sin(a))
        apo = 1.28 * math.cos(math.radians(36))
        hw = 1.28 * math.sin(math.radians(36)) - 0.05
        base = u * apo
        phi = math.degrees(math.atan2(-u[0], -u[2]))
        tg = V(-u[2], 0, u[0])
        lift = 0.3 + rnd.uniform(0, 0.08)
        tilt = rnd.uniform(-7, 7)
        with m.group(R=Ry(phi) @ Rx(tilt) @ Rx(90), t=base * 1.0 + V(0, lift, 0)):
            tri(m, "Tile", V(0, 0, 0), hw, apo - 0.1, 0.16, ROCK if k % 2 else shade(ROCK, 1.08))
        tops.append(lift)
    for k in range(6):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.4, 1.1)
        m.blk("Pebble", (0.14, 0.1, 0.12), (math.cos(a) * r, 0.42, math.sin(a) * r), ROCK_D, R=rot(rnd.uniform(0, 40), rnd.uniform(0, 90), 0))

    def shoe(at, yaw, pitch):
        with m.group(R=Ry(yaw) @ Rx(pitch), t=at):
            m.ell("Shoe", (0.56, 0.4, 1.0), (0, 0.26, -0.06), SHOE, refl=0.22)
            m.ell("ShoeToe", (0.52, 0.34, 0.5), (0, 0.22, -0.36), shade(SHOE, 1.08), refl=0.22)
            m.blk("Sole", (0.52, 0.08, 0.64), (0, 0.05, -0.28), (40, 34, 40), "Rubber")
            m.blk("Heel", (0.36, 0.2, 0.26), (0, 0.1, 0.32), (40, 34, 40), "Rubber")
            m.blk("Tap", (0.46, 0.025, 0.3), (0, 0.0, -0.38), (200, 204, 214), "Metal")
            m.blk("Tap", (0.32, 0.025, 0.2), (0, 0.0, 0.32), (200, 204, 214), "Metal")
            m.ell("ShoeOpen", (0.42, 0.06, 0.42), (0, 0.45, 0.14), (50, 20, 30))
            m.cyl("Sock", 0.36, 0.4, (0, 0.64, 0.15), SOCK)
            m.cyl("SockStripe", 0.07, 0.41, (0, 0.72, 0.15), (60, 140, 240))
            torus(m, "SockTop", (0, 0.82, 0.15), 0.19, 0.04, SOCK, n=10, normal=(0, 1, 0))
            m.ell("SockInside", (0.3, 0.02, 0.3), (0, 0.82, 0.15), (200, 200, 210))
            m.blk("Strap", (0.6, 0.06, 0.12), (0, 0.44, -0.12), (120, 20, 36))
            m.blk("Buckle", (0.06, 0.13, 0.16), (0.3, 0.42, -0.12), GOLD, "Foil")
            m.ell("ShoeShine", (0.12, 0.05, 0.22), (-0.12, 0.38, -0.4), WHITE, tr=0.35)

    shoe(V(0.42, 0.44, 0.1), -16, 0)
    shoe(V(-0.48, 0.62, 0.2), 18, -38)
    # motion lines and impact stars
    for k in range(3):
        c = V(-0.62, 0.95, 0.42)
        pts = arc_pts(c, 0.55 + k * 0.14, 150 - k * 6, 105, 4, plane=Ry(-72))
        stroke(m, "Swoosh", pts, 0.035, 0.02, WHITE, tr=0.3, r_end=0.02)
    for (p, n) in ((V(0.95, 0.62, -0.5), V(0.4, 0.3, -1)), (V(-0.1, 0.55, -0.85), V(0, 0.3, -1))):
        star(m, "Impact", p, n, 0.14, 0.04, (255, 230, 80))
    # rocks thrown up by the stomping
    for (p, s, r) in (((-1.1, 1.3, -0.3), 0.3, (20, 40, 10)), ((1.12, 1.55, 0.2), 0.26, (-30, 10, 25)), ((0.25, 2.05, 0.55), 0.22, (10, 70, -20)),
                      ((-0.4, 1.85, -0.75), 0.18, (40, 0, 30)), ((0.9, 0.95, -0.95), 0.2, (0, 30, -40))):
        m.blk("FlyingRock", (s, s * 0.8, s * 0.9), p, ROCK, R=rot(*r))
        m.blk("FlyingRock", (s * 0.8, s * 0.7, s * 0.8), V(*p) + V(0.03, 0.05, -0.02), shade(ROCK, 1.1), R=rot(*r) @ rot(30, 45, 20))
        m.ell("FlyingRock", (s * 0.9, s * 0.6, s * 0.85), V(*p) + V(-0.02, 0.06, 0), shade(ROCK, 1.05), R=rot(*r))
    # music notes
    for (p, h, tilt) in ((V(-1.0, 2.1, 0.3), 0.6, 12), (V(1.02, 2.3, -0.1), 0.5, -14)):
        with m.group(R=Rz(tilt), t=p):
            m.ell("Note", (0.26, 0.2, 0.12), (0, 0, 0), NOTE, R=Rz(-20))
            m.rod("Note", (0.11, 0.0, 0), (0.11, h, 0), 0.05, NOTE)
            m.seg("Note", V(0.11, h, 0), V(0.3, h - 0.22, 0), 0.05, NOTE, r2=0.03)
    for k in range(5):
        a = rnd.uniform(0, 2 * math.pi)
        m.ball("Dust", rnd.uniform(0.32, 0.44), (math.cos(a) * 1.3, 0.24, math.sin(a) * 1.3), (226, 210, 186), tr=0.45)
    m.light(glow, (255, 140, 60), 1.4, 7)
    m.sparkles(glow, (255, 190, 90))
    return m


# ------------------------------------------------------------------------------------------------
# Legendary
# ------------------------------------------------------------------------------------------------
@model
def total_chaos():
    """A swirling vortex orb over tumbling blocks of land, with dice, cards and rocks flying round it."""
    m = SModel("total_chaos", "spell")
    C0 = V(0, 1.9, 0)
    # blocks of land tumbling under it
    for (c, R, top, side, mat, trn) in (((-0.78, 0.36, -0.2), rot(14, 30, -18), (110, 186, 80), (130, 90, 56), "SmoothPlastic", 0),
                                        ((0.76, 0.5, 0.12), rot(-20, -25, 22), (236, 206, 140), (196, 160, 100), "Sand", 0),
                                        ((0.04, 0.42, 0.78), rot(25, 60, 10), (244, 248, 255), (150, 160, 180), "SmoothPlastic", 0),
                                        ((0.12, 0.62, -0.86), rot(-12, 15, -30), (90, 170, 240), (130, 90, 56), "Glass", 0.1)):
        tile(m, "LandBlock", V(*c), R, top, side, size=0.62, h=0.36, top_mat=mat, top_tr=trn)
    # the orb: a white-hot core, a magenta glow, a glass shell
    core = m.ball("Core", 0.52, C0, (255, 236, 255), "Neon")
    m.ball("CoreGlow", 0.86, C0, (236, 80, 220), "Neon", tr=0.4)
    m.ball("Orb", 1.36, C0, (96, 40, 170), "Glass", tr=0.55, refl=0.3)
    # three spiral arms
    P = rot(18, 0, -12)
    for k, col in enumerate(((244, 72, 200), (255, 156, 40), (64, 214, 255))):
        pts = []
        for i in range(8):
            t = i / 7
            a = math.radians(k * 120 + t * 220)
            r = 0.5 + t * 0.95
            pts.append(C0 + P @ V(math.cos(a) * r, (t - 0.5) * 0.2 * (1 if k % 2 else -1), math.sin(a) * r))
        for i in range(7):
            rr = 0.21 * (1 - i / 8.5)
            m.seg("Swirl", pts[i], pts[i + 1], rr * 0.55, col, "Neon" if i < 3 else "SmoothPlastic", r2=rr, ext=rr * 0.6)
    # orbit rings
    n1 = Rz(22) @ Rx(14) @ V(0, 1, 0)
    n2 = Rz(-30) @ Rx(-20) @ V(0, 1, 0)
    torus(m, "OrbitRing", C0, 1.3, 0.04, GOLD, n=22, normal=n1, mat="Foil")
    torus(m, "OrbitRing", C0, 1.12, 0.035, (120, 230, 255), n=20, normal=n2, mat="Neon", tr=0.2)

    def on_ring(nrm, r, a):
        F = frame_normal(nrm)
        a = math.radians(a)
        return C0 + (F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)) * r

    # a die
    with m.group(R=rot(25, 35, 15), t=on_ring(n1, 1.3, 200)):
        m.rbox("Die", (0.34, 0.34, 0.34), (0, 0, 0), WHITE, 0.06)
        m.ball("Pip", 0.08, (0, 0, -0.17), (200, 30, 50))
        for (x, z) in ((-0.08, -0.08), (0.08, 0.08)):
            m.ball("Pip", 0.07, (x, 0.17, z), (30, 30, 40))
        for d in (-0.09, 0, 0.09):
            m.ball("Pip", 0.07, (0.17, d, d), (30, 30, 40))
    # a playing card with a heart
    with m.group(R=rot(10, -30, 25), t=on_ring(n1, 1.3, 20)):
        m.rbox("PlayCard", (0.3, 0.42, 0.03), (0, 0, 0), WHITE, 0.04, axis="z")
        for s in (-1, 1):
            m.ball("Heart", 0.1, (s * 0.04, 0.03, -0.02), (220, 40, 60))
        m.blk("Heart", (0.08, 0.08, 0.025), (0, -0.015, -0.02), (220, 40, 60), R=Rz(45))
    # a rock, a star, a bolt and a party hat flying round
    rp = on_ring(n2, 1.12, 110)
    m.blk("FlyingRock", (0.26, 0.2, 0.22), rp, (128, 112, 104), R=rot(30, 20, 10))
    m.ell("FlyingRock", (0.28, 0.18, 0.24), rp + V(0.02, 0.03, 0), (150, 134, 124), R=rot(30, 20, 10))
    star(m, "FlyingStar", on_ring(n2, 1.12, 300), (0.3, 0.2, -1), 0.2, 0.06, GOLD, "Foil")
    m.bolt("FlyingBolt", on_ring(n1, 1.3, 110) + V(0, 0.2, 0), 0.4, color=(255, 236, 90), R=Rz(20))
    hp = on_ring(n2, 1.12, 20)
    m.seg("PartyHat", hp, hp + V(0.1, 0.3, -0.05), 0.11, (90, 200, 250), bulge=0.15)
    m.ball("PartyHat", 0.08, hp + V(0.1, 0.32, -0.05), (255, 230, 80))
    # a twisting tail of chaos down to the land
    prev = C0 - V(0, 0.55, 0)
    for k in range(1, 7):
        t = k / 6
        a = math.radians(t * 540)
        p = C0 + V(math.cos(a) * 0.3 * (1 - t * 0.5), -0.55 - t * 1.0, math.sin(a) * 0.3 * (1 - t * 0.5))
        r = 0.16 * (1 - t * 0.6)
        m.seg("Twister", prev, p, r, (200, 120, 255), "Neon", ext=r * 0.6, tr=0.45)
        prev = p
    m.sparkles(core, (255, 180, 255))
    m.light(core, (230, 120, 255), 2.0, 9)
    return m
