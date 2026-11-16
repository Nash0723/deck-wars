# Buildings, hero figurines and the bot opponent (remodel: chunky, stylized, one look with the creatures)
#
# Buildings (kind "gadget") face -Z like everything else and stand on a base that fills their tile.
# They share one building kit: thick walls, roofs that overhang with shingle courses and a round
# ridge cap, framed windows with sills, chunky doors, signs with block letters, chimneys, grass.
# The match board shrinks a building to fit its slot; sizefit.py keeps each one as tall on the
# board as it was before the remodel.
import math
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal, frame_from_x
from stylekit import SModel, PAL, V, norm, INK, GOLD, SILVER

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


# ------------------------------------------------------------------------------------------------
# Shared colours
# ------------------------------------------------------------------------------------------------
WOOD = (198, 142, 86)
WOOD_D = (146, 96, 56)
WOOD_L = (228, 184, 126)
WOOD_X = (110, 70, 42)
STONE = (170, 166, 160)
STONE_D = (126, 122, 118)
STONE_L = (204, 200, 194)
GRASS = (116, 190, 84)
GRASS_D = (84, 152, 62)
GRASS_L = (152, 214, 104)
IRON = (78, 82, 92)
IRON_L = (156, 162, 174)
CHROME = (224, 230, 238)
GLASS_C = (92, 150, 210)
LIT = (255, 214, 130)
YELLOW = (255, 214, 60)
LEMON = (255, 226, 70)
RED = (226, 58, 58)
PINK = (250, 120, 172)
SKY = (96, 170, 246)
TEAL = (56, 168, 176)
PURPLE = (128, 70, 200)
DIRT = (110, 76, 52)


# ------------------------------------------------------------------------------------------------
# Building kit
# ------------------------------------------------------------------------------------------------
def plank(m, name, a, b, w, t, color, mat="SmoothPlastic", side=(1, 0, 0), shape="B", tr=0.0, refl=0.0):
    """A block (or ellipsoid / wedge) from a to b: w wide along `side`, t thick across."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    z = norm(b - a)
    s = np.asarray(side, float)
    x = norm(s - z * float(s @ z))
    y = np.cross(z, x)
    L = float(np.linalg.norm(b - a))
    return m.add(shape, name, (w, t, L), (a + b) / 2, color, mat, np.column_stack([x, y, z]), tr, refl)


def tri(m, name, c, hw, rise, t, color, mat="SmoothPlastic", plane="xy", tr=0.0):
    """A solid triangle (two wedges): base 2*hw wide, apex `rise` above the base middle c.
    plane "xy": faces -z (a gable on a front wall, a picket point); "zy": faces x (a side gable)."""
    c = np.asarray(c, float)
    if plane == "xy":
        for s in (-1, 1):
            # a wedge is full height at its local +z end: turn that end towards the apex
            R = Ry(-90) if s > 0 else Ry(90)
            m.wedge(name, (t, rise, hw), c + V(s * hw / 2, rise / 2, 0), color, mat, R=R, tr=tr)
    else:
        for s in (-1, 1):
            R = I3 if s < 0 else Ry(180)
            m.wedge(name, (t, rise, hw), c + V(0, rise / 2, s * hw / 2), color, mat, R=R, tr=tr)


def gable_roof(m, c, w, d, rise, color, t=0.18, over=0.24, side_over=0.2, rows=2, name="Roof", ridge=None,
               edge=None, mat="SmoothPlastic", axis="x", gables=None, gable_t=0.14, scallops=0, scallop_color=None):
    """A pitched roof over walls w wide and d deep: c = (x, eave height, z) at the middle. The ridge
    runs along x (axis "x") or z. Two thick slopes with shingle courses, a round ridge cap, a round
    edge along each eave and, with gables=colour, the triangles that close the ends."""
    Rg = I3 if axis == "x" else Ry(90)
    with m.group(R=Rg, t=c):
        hd = d / 2
        a = math.atan2(rise, hd)
        ca, sa = math.cos(a), math.sin(a)
        W = w + 2 * side_over
        top = V(0, rise, 0)
        dark = ridge or shade(color, 0.78)
        for sz in (-1, 1):
            eave = V(0, 0, sz * hd)
            u = norm(top - eave)
            n = V(0, ca, sz * sa)
            p0 = eave - u * over + n * (t / 2)
            p1 = top + n * (t / 2) + u * (t / 2 * math.tan(a))
            plank(m, name, p0, p1, W, t, color, mat)
            for k in range(rows):
                f = (k + 0.6) / (rows + 0.4)
                p = p0 + (p1 - p0) * f + n * (t * 0.42)
                plank(m, name, p - u * 0.09, p + u * 0.09, W + 0.02, t * 0.34, shade(color, 0.88), mat)
            m.cyl(name, W + 0.04, t * 1.15, p0 + n * 0.0 - u * 0.02, edge or dark, "x", mat)
            if scallops and sz < 0:
                for k in range(scallops):
                    x = -W / 2 + (k + 0.5) * W / scallops
                    m.ell(name, (W / scallops * 1.02, t * 1.5, t * 0.9), p0 + V(x, -t * 0.7, 0) - u * 0.04,
                          scallop_color or shade(color, 0.92), mat)
        m.cyl(name, W + 0.1, t * 1.7, top + V(0, t / ca * 0.62, 0), dark, "x", mat)
        if gables is not None:
            for s in (-1, 1):
                tri(m, name + "Gable", V(s * (w / 2 - gable_t / 2), 0, 0), hd, rise, gable_t, gables, plane="zy")


def window(m, c, w, h, frame, glass=GLASS_C, yaw=0, sill=True, cross=True, shutters=None, lit=False, fr=0.07,
           name="Window", round_top=False):
    """A framed window on a wall: built facing -z, then turned by yaw (degrees about y) and moved to
    c, the middle of the window on the wall surface."""
    with m.group(R=Ry(yaw), t=c):
        if lit:
            m.blk(name, (w, h, 0.04), (0, 0, -0.01), LIT if lit is True else lit, "Neon")
        else:
            m.blk(name, (w, h, 0.04), (0, 0, -0.01), glass, refl=0.25)
            m.blk("WindowShine", (w * 0.14, h * 0.7, 0.02), (-w * 0.18, h * 0.04, -0.035), WHITE, tr=0.35, R=Rz(-28))
        if round_top:
            m.cyl(name, 0.04, w, (0, h / 2, -0.01), LIT if lit else glass, "z", "Neon" if lit else "SmoothPlastic")
            m.ring("WindowFrame", (0, h / 2, -0.04), w / 2 + fr / 2, fr, frame, "z", 8, R=None)
        else:
            m.blk("WindowFrame", (w + 2 * fr, fr, 0.09), (0, h / 2 + fr / 2, -0.035), frame)
        m.blk("WindowFrame", (w + 2 * fr, fr, 0.09), (0, -h / 2 - fr / 2, -0.035), frame)
        for s in (-1, 1):
            m.blk("WindowFrame", (fr, h, 0.09), (s * (w / 2 + fr / 2), 0, -0.035), frame)
        if cross:
            m.blk("WindowFrame", (fr * 0.6, h, 0.06), (0, 0, -0.035), frame)
            m.blk("WindowFrame", (w, fr * 0.6, 0.06), (0, 0, -0.035), frame)
        if sill:
            m.blk("Sill", (w + 2 * fr + 0.12, fr * 1.3, 0.2), (0, -h / 2 - fr * 1.15, -0.08), shade(frame, 0.88))
        if shutters is not None:
            for s in (-1, 1):
                x = s * (w / 2 + fr + w * 0.27)
                m.blk("Shutter", (w * 0.5, h + 2 * fr, 0.05), (x, 0, -0.025), shutters)
                for k in (-1, 1):
                    m.blk("Shutter", (w * 0.42, 0.03, 0.03), (x, k * h * 0.22, -0.055), shade(shutters, 0.75))


def door(m, c, w, h, color, frame, yaw=0, knob=GOLD, planks=3, arch=True, step=None, name="Door", straps=IRON):
    """A chunky door standing on c (bottom middle, on the wall surface): planks, an arched top, a
    thick frame, iron straps and a knob. Built facing -z, turned by yaw."""
    with m.group(R=Ry(yaw), t=c):
        bh = h - (w / 2 if arch else 0)
        m.blk(name, (w, bh, 0.08), (0, bh / 2, -0.02), color)
        if arch:
            m.cyl(name, 0.08, w, (0, bh, -0.02), color, "z")
        for k in range(1, planks):
            x = -w / 2 + k * w / planks
            top = bh + (math.sqrt(max((w / 2) ** 2 - x * x, 0)) if arch else 0) - 0.04
            m.blk("DoorPlank", (0.025, top - 0.04, 0.02), (x, (top + 0.04) / 2, -0.065), shade(color, 0.72))
        fr = 0.09
        for s in (-1, 1):
            m.blk("DoorFrame", (fr, bh, 0.14), (s * (w / 2 + fr / 2), bh / 2, -0.04), frame)
        if arch:
            r = w / 2 + fr / 2
            prev = None
            for k in range(7):
                a = math.pi * k / 6
                p = V(math.cos(a) * r, bh + math.sin(a) * r, -0.04)
                if prev is not None:
                    v = p - prev
                    plank(m, "DoorFrame", prev - v * 0.1, p + v * 0.1, 0.14, fr, frame, side=(0, 0, 1))
                prev = p
        else:
            m.blk("DoorFrame", (w + 2 * fr, fr, 0.14), (0, bh + fr / 2, -0.04), frame)
        if straps is not None:
            for y in (bh * 0.25, bh * 0.75):
                m.blk("DoorStrap", (w * 0.62, 0.07, 0.03), (-w * 0.17, y, -0.075), straps, "Metal")
                m.ball("DoorStrap", 0.07, (-w * 0.44, y, -0.085), straps, "Metal")
        if knob is not None:
            m.ball("DoorKnob", 0.1, (w * 0.3, bh * 0.52, -0.1), knob, "Metal")
        if step is not None:
            m.blk("Step", (w + 0.3, 0.1, 0.3), (0, 0.05, -0.15), step)


def sign(m, c, w, h, color, text, text_color, border=None, yaw=0, t=0.1, name="Sign", letter_h=None, mat="SmoothPlastic"):
    """A signboard with block letters, built facing -z at c, turned by yaw."""
    with m.group(R=Ry(yaw), t=c):
        if border is not None:
            m.rbox(name, (w + 0.12, h + 0.12, t * 0.8), (0, 0, t * 0.15), border, min(w, h) * 0.2, axis="z")
        m.rbox(name, (w, h, t), (0, 0, 0), color, min(w, h) * 0.18, mat, axis="z")
        lh = letter_h or h * 0.56
        m.text("SignText", text, (0, 0, -t / 2 - lh * 0.04), lh, text_color, facing="front")


def chimney(m, c, w, h, color, cap, smoke=(230, 230, 236)):
    """A chunky chimney standing on c (its bottom middle) with a cap and a puff of smoke."""
    x, y, z = c
    m.blk("Chimney", (w, h, w), (x, y + h / 2, z), color, "Brick")
    m.blk("Chimney", (w + 0.1, 0.12, w + 0.1), (x, y + h - 0.02, z), cap)
    top = m.blk("Chimney", (w * 0.6, 0.08, w * 0.6), (x, y + h + 0.06, z), shade(cap, 0.5))
    if smoke is not None:
        m.smoke(top, smoke, 0.12, 0.8, 1.0)


def grass(m, pts, color=GRASS_D, n=3, length=0.2, width=0.07, name="Grass"):
    """Little tufts of grass at the given (x, y, z) points."""
    for i, p in enumerate(pts):
        m.tuft(name, p, (0, 1, 0), length, width, color if i % 2 == 0 else shade(color, 1.18), n=n, spread=30)


def flower(m, p, color, d=0.1, stem=0.12, name="Flower"):
    p = np.asarray(p, float)
    m.seg(name + "Stem", p, p + V(0, stem, 0), 0.016, GRASS_D, shape="C")
    c = p + V(0, stem + d * 0.25, 0)
    for k in range(4):
        a = math.radians(45 + k * 90)
        m.ell(name, (d * 0.7, d * 0.3, d * 0.7), c + V(math.cos(a) * d * 0.4, 0, math.sin(a) * d * 0.4), color)
    m.ball(name, d * 0.55, c + V(0, d * 0.08, 0), (255, 236, 120))


def star(m, name, c, n, r, t, color, mat="SmoothPlastic", spin=0.0):
    """A chunky five-pointed star facing along n: a round middle and five rounded points."""
    F = frame_normal(n, spin)
    m.add("E", name, (r * 1.0, r * 1.0, t), c, color, mat, F)
    for k in range(5):
        a = math.radians(90 + k * 72)
        d = F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)
        Fr = np.column_stack([d, np.cross(F[:, 2], d), F[:, 2]])
        m.add("E", name, (r * 1.04, r * 0.4, t * 0.9), np.asarray(c, float) + d * r * 0.5, color, mat, Fr)


def pennants(m, a, b, n, colors, size=0.24, sag=0.12, name="Pennant", rope=(240, 240, 240)):
    """A string of triangle flags hanging from a to b (both ends facing -z)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    pts = [a + (b - a) * (k / n) - V(0, sag * math.sin(math.pi * k / n), 0) for k in range(n + 1)]
    for k in range(n):
        m.rod(name + "Rope", pts[k], pts[k + 1], 0.025, rope)
    for k in range(n):
        p = (pts[k] + pts[k + 1]) / 2
        # a triangle hanging point-down: a wedge turned so its sharp end points at the ground
        m.wedge(name, (0.03, size, size * 0.42), p + V(size * 0.21, -size / 2, 0), colors[k % len(colors)], R=Ry(90) @ Rx(180))
        m.wedge(name, (0.03, size, size * 0.42), p + V(-size * 0.21, -size / 2, 0), colors[k % len(colors)], R=Ry(-90) @ Rx(180))


def disc(m, name, c, n, d, t, color, mat="SmoothPlastic", tr=0.0, refl=0.0):
    """A round disc d across and t thick, facing along n."""
    return m.add("C", name, (t, d, d), c, color, mat, frame_from_x(norm(n)), tr, refl)


def torus(m, name, c, R, r, color, n=10, normal=(0, 0, -1), mat="SmoothPlastic", refl=0.0, flat=1.0, tr=0.0):
    """A smooth ring of overlapping ellipsoids: R from the middle c to the tube's middle, tube radius r,
    the ring facing along normal (flat < 1 squashes the tube along the normal)."""
    F = frame_normal(normal)
    c = np.asarray(c, float)
    first = None
    for i in range(n):
        a = 2 * math.pi * i / n
        d = F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)
        t = np.cross(d, F[:, 2])
        L = 2 * math.pi * R / n * 1.5
        idx = m.add("E", name, (L, 2 * r, 2 * r * flat), c + d * R, color, mat, np.column_stack([t, d, F[:, 2]]), tr, refl)
        first = first or idx
    return first


# ------------------------------------------------------------------------------------------------
# Buildings
# ------------------------------------------------------------------------------------------------
@model
def spiked_fence():
    """Spiked Fence (Common): a stubborn little palisade. Thick rounded pickets with pointed tops and
    iron spikes, two heavy rails, a stone footing, a barbed wire strand and a warning sign."""
    m = SModel("spiked_fence", kind="gadget")
    # stone footing: a rounded curb with stone faces
    m.rbox("Base", (3.3, 0.3, 0.76), (0, 0.15, 0), STONE_D, 0.12, "Slate", axis="x")
    for k in range(6):
        x = -1.38 + k * 0.55
        for zs in (-1, 1):
            c = shade(STONE, 0.92 + 0.08 * ((k * 5 + (zs > 0)) % 3))
            m.ell("Stone", (0.5, 0.24, 0.14), (x + zs * 0.05, 0.17, zs * 0.37), c, "Slate")
    # the pickets: alternating heights, warm wood, grain, a point and an iron spike each
    tops = []
    for k in range(6):
        x = -1.375 + k * 0.55
        h = 1.08 if k % 2 == 0 else 1.22
        c = shade(WOOD, 0.94 + 0.06 * ((k * 7) % 3))
        y0 = 0.24
        m.rbox("Plank", (0.42, h, 0.2), (x, y0 + h / 2, 0), c, 0.07, "Wood", axis="z")
        tri(m, "PlankTip", (x, y0 + h, 0), 0.21, 0.22, 0.2, c, "Wood")
        m.blk("Grain", (0.03, h * 0.55, 0.02), (x - 0.09, y0 + h * 0.46, -0.105), shade(c, 0.78))
        m.blk("Grain", (0.03, h * 0.35, 0.02), (x + 0.1, y0 + h * 0.62, -0.105), shade(c, 0.78))
        if k % 2 == 1:
            m.ell("Knot", (0.09, 0.12, 0.03), (x + 0.06, y0 + 0.32, -0.105), shade(c, 0.66))
        ty = y0 + h + 0.12
        m.cyl("SpikeBand", 0.08, 0.17, (x, ty + 0.02, 0), IRON, "y", "Metal")
        m.spike("Spike", V(x, ty, 0), (0, 1, 0), 0.4, 0.075, IRON_L, "Metal")
        tops.append((x, ty))
    # two heavy rails behind the pickets, held on with fat nails
    for y in (0.62, 1.1):
        m.rbox("Rail", (3.3, 0.2, 0.14), (0, y, 0.16), WOOD_D, 0.06, "Wood", axis="x")
        for k in range(6):
            m.ball("Nail", 0.09, (-1.375 + k * 0.55, y, -0.1), IRON, "Metal")
    # barbed wire strung across the spike bands
    pts = [V(x, ty - 0.06, -0.13) for (x, ty) in tops]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        mid = (a + b) / 2 - V(0, 0.07, 0)
        m.rod("Wire", a, mid, 0.03, IRON_L, "Metal")
        m.rod("Wire", mid, b, 0.03, IRON_L, "Metal")
        for r in (0, 90):
            m.blk("Barb", (0.13, 0.025, 0.025), mid + V(0, 0, -0.005), IRON_L, "Metal", R=Rz(45 + r))
    # a warning sign hanging from a nail
    sc = V(0.55, 0.88, -0.17)
    m.blk("Sign", (0.52, 0.52, 0.05), sc + V(0, 0, 0.012), (40, 34, 30), R=Rz(45))
    m.blk("Sign", (0.44, 0.44, 0.06), sc, YELLOW, R=Rz(45))
    m.text("SignMark", "!", sc + V(0, 0.0, -0.04), 0.3, INK, facing="front")
    m.ball("Nail", 0.08, sc + V(0, 0.46, 0.04), IRON, "Metal")
    for s in (-1, 1):
        m.rod("SignString", sc + V(0, 0.46, -0.0), sc + V(s * 0.17, 0.17, -0.0), 0.02, (90, 70, 50))
    # grass and a couple of flowers along the footing
    grass(m, [V(-1.62, 0.12, -0.32), V(-1.0, 0.28, -0.4), V(0.2, 0.28, -0.42), V(1.6, 0.12, -0.3), V(1.2, 0.28, 0.4), V(-0.5, 0.28, 0.42)])
    flower(m, V(-0.75, 0.26, -0.44), (255, 120, 150))
    flower(m, V(1.05, 0.26, -0.44), (255, 220, 80))
    return m


@model
def bouncy_castle():
    """Bouncy Castle (Common): a fat inflatable castle with a grin. Puffy vinyl walls with seams, two
    round towers with pointed caps, puffy battlements, an arched entrance, bunting and a blower."""
    m = SModel("bouncy_castle", kind="gadget")
    BLUE = (88, 158, 244)
    BLUE_L = (132, 190, 255)
    PNK = (252, 122, 176)
    PNK_D = (222, 92, 148)
    YEL = (255, 214, 78)
    YEL_D = (232, 182, 50)
    v = 0.06  # vinyl shine
    # the bouncy floor with a fat bumper all round
    m.rbox("Floor", (3.2, 0.32, 1.9), (0, 0.16, 0), BLUE, 0.3, refl=v)
    for z in (-0.8, 0.8):
        m.cyl("Bumper", 2.6, 0.34, (0, 0.34, z), BLUE_L, "x", refl=v)
    for x in (-1.45, 1.45):
        m.cyl("Bumper", 1.3, 0.34, (x, 0.34, 0), BLUE_L, "z", refl=v)
    for x in (-1.3, 1.3):
        for z in (-0.8, 0.8):
            m.ball("Bumper", 0.34, (x, 0.34, z) if abs(x) < 1.4 else (x, 0.34, z), BLUE_L, refl=v)
    # the back wall with inflated seams and puffy battlements
    m.rbox("Wall", (2.0, 1.72, 0.62), (0, 1.16, 0.36), PNK, 0.28, axis="z", refl=v)
    m.cyl("Seam", 1.5, 0.15, (0, 1.86, 0.05), PNK_D, "x", refl=v)
    for k in range(5):
        m.ball("Crenel", 0.42, (-0.8 + k * 0.4, 2.08, 0.36), PNK if k % 2 == 0 else YEL, refl=v)
    # the arched entrance with a puffy yellow trim
    m.ell("Entrance", (0.72, 0.84, 0.12), (0, 0.7, 0.03), (52, 72, 160))
    m.blk("Entrance", (0.72, 0.38, 0.12), (0, 0.5, 0.03), (52, 72, 160))
    for k in range(9):
        a = math.radians(-8 + k * 24.5)
        m.ball("ArchTrim", 0.2, (math.cos(a) * 0.44, 0.7 + math.sin(a) * 0.46, 0.0), YEL, refl=v)
    for s in (-1, 1):
        m.cyl("ArchTrim", 0.36, 0.2, (s * 0.44, 0.5, 0.0), YEL, "y", refl=v)
    # its grin above the door
    for s in (-1, 1):
        m.eye(V(s * 0.24, 1.52, 0.04), V(0, 0, -1), 0.26, 0.3, PNK, "eager", side=s, iris=(60, 110, 220), brow=PNK_D)
    m.mouth(V(0, 1.31, 0.03), V(0, 0, -1), 0.3, "cheerful", curve=0.32)
    for s in (-1, 1):
        m.ell("Cheek", (0.14, 0.08, 0.04), (s * 0.46, 1.34, 0.04), (255, 160, 200))
    # two round towers with puffy rings, pointed caps and a ball on top
    for s in (-1, 1):
        x = s * 1.18
        m.cyl("Tower", 1.95, 0.86, (x, 1.3, 0.18), YEL, "y", refl=v)
        for y in (0.7, 1.3, 1.9):
            m.ell("TowerRing", (0.98, 0.16, 0.98), (x, y, 0.18), YEL_D, refl=v)
        m.ell("TowerWindow", (0.26, 0.36, 0.08), (x, 1.6, -0.24), (52, 72, 160))
        m.ell("TowerTop", (1.04, 0.24, 1.04), (x, 2.28, 0.18), PNK_D, refl=v)
        m.seg("TowerTop", (x, 2.26, 0.18), (x, 2.98, 0.18), 0.48, PNK, bulge=0.1, refl=v)
        m.ball("TowerBall", 0.24, (x, 3.0, 0.18), BLUE_L, refl=v)
    # bunting between the towers
    pennants(m, V(-1.12, 2.26, -0.26), V(1.12, 2.26, -0.26), 5,
             [(255, 90, 90), (90, 210, 120), (255, 214, 78), (88, 158, 244), (190, 120, 250)], size=0.22, sag=0.16)
    # the blower humming at the back with its fat hose
    m.rbox("Blower", (0.5, 0.4, 0.4), (1.25, 0.2, 1.12), (60, 64, 76), 0.08, axis="z")
    m.cyl("Blower", 0.06, 0.32, (1.25, 0.22, 0.91), (36, 38, 44), "z")
    m.flow("Hose", [V(1.25, 0.24, 0.9), V(1.0, 0.34, 0.86), V(0.7, 0.62, 0.72)], [0.1, 0.1, 0.1], (70, 72, 82))
    # a beach ball left on the floor
    m.ball("BeachBall", 0.36, (-0.82, 0.5, -0.5), WHITE, refl=v)
    m.ell("BeachBall", (0.37, 0.37, 0.13), (-0.82, 0.5, -0.5), (255, 90, 90), R=Ry(30))
    m.ell("BeachBall", (0.13, 0.37, 0.37), (-0.82, 0.5, -0.5), (88, 158, 244), R=Ry(30))
    return m


@model
def lemonade_stand():
    """Lemonade Stand (Rare): a sturdy wooden stand. Plank counter with a hand-painted LEMONADE sign,
    a striped scalloped awning on corner posts, a lemon-slice sign on top, a pitcher, cups, a basket
    of lemons, a tip jar and a crate of lemons on the deck."""
    m = SModel("lemonade_stand", kind="gadget")
    # the deck it stands on
    m.rbox("Base", (3.36, 0.14, 1.6), (0, 0.07, 0.02), WOOD_D, 0.1, "WoodPlanks", axis="y")
    # the counter: a plank box with darker corner posts
    m.blk("Counter", (2.6, 1.0, 1.0), (0, 0.64, 0.12), WOOD, "WoodPlanks")
    for k in range(1, 7):
        m.blk("CounterSeam", (0.025, 0.92, 0.02), (-1.3 + k * 2.6 / 7, 0.64, -0.39), shade(WOOD, 0.74))
    # the counter top: a thick slab with a rounded front edge
    m.blk("CounterTop", (2.94, 0.12, 1.2), (0, 1.2, 0.1), WOOD_L, "Wood")
    m.cyl("CounterTop", 2.94, 0.14, (0, 1.2, -0.5), WOOD_L, "x", "Wood")
    # the hand-painted sign on the front
    sign(m, V(0, 0.72, -0.43), 2.2, 0.5, (255, 236, 120), "LEMONADE", (200, 90, 30), border=(240, 170, 40), t=0.08, letter_h=0.26)
    for s in (-1, 1):
        m.ell("SignLemon", (0.24, 0.18, 0.08), (s * 0.93, 0.72, -0.5), LEMON)
        m.ell("SignLemon", (0.09, 0.05, 0.04), (s * 0.93 + 0.07, 0.83, -0.53), (90, 170, 70), R=Rz(-30))
    # posts and the striped awning, sloping down to the front, with a scalloped edge
    for s in (-1, 1):
        m.blk("Post", (0.16, 1.24, 0.16), (s * 1.32, 1.82, -0.42), WOOD_D, "Wood")
        m.blk("Post", (0.16, 1.5, 0.16), (s * 1.32, 1.95, 0.56), WOOD_D, "Wood")
    for k in range(6):
        c = WHITE if k % 2 else (255, 208, 50)
        x = -1.25 + k * 0.5
        plank(m, "Awning", V(x, 2.38, -0.66), V(x, 2.76, 0.72), 0.5, 0.1, c, "Fabric")
        m.ell("Awning", (0.5, 0.26, 0.1), (x, 2.3, -0.68), c, "Fabric")
    m.cyl("Awning", 3.06, 0.16, (0, 2.78, 0.72), (240, 180, 40), "x", "Fabric")
    m.cyl("Awning", 3.06, 0.1, (0, 2.4, -0.67), (240, 180, 40), "x", "Fabric")
    # a lemon-slice medallion hanging in the middle of the awning's edge
    lc = V(0, 2.16, -0.76)
    m.cyl("LemonSign", 0.08, 0.56, lc, (255, 246, 200), "z")
    m.cyl("LemonSign", 0.09, 0.48, lc + V(0, 0, -0.005), LEMON, "z")
    for k in range(3):
        m.blk("LemonSign", (0.025, 0.44, 0.1), lc + V(0, 0, -0.01), (255, 246, 200), R=Rz(k * 60))
    m.cyl("LemonSign", 0.11, 0.08, lc + V(0, 0, -0.01), (255, 246, 200), "z")
    # on the counter: a glass pitcher of lemonade, cups, a basket of lemons and a tip jar
    pc = V(-0.72, 1.26, 0.02)
    m.cyl("Pitcher", 0.56, 0.42, pc + V(0, 0.28, 0), (230, 244, 250), "y", "Glass", tr=0.45)
    m.cyl("Lemonade", 0.42, 0.36, pc + V(0, 0.22, 0), (255, 224, 70))
    m.cyl("LemonSlice", 0.04, 0.2, pc + V(-0.04, 0.48, -0.08), (255, 240, 120), "z", R=Rx(20))
    m.seg("PitcherHandle", pc + V(0.2, 0.46, 0), pc + V(0.32, 0.26, 0), 0.04, (230, 244, 250), "Glass", tr=0.3)
    for (x, z) in ((-0.05, -0.12), (-0.05, 0.25)):
        m.blk("Ice", (0.08, 0.08, 0.08), pc + V(x, 0.42, z * 0.3), (236, 248, 255), "Glass", tr=0.25, R=rot(20, 30, 0))
    for k in range(3):
        cc = V(-0.12 + k * 0.3, 1.26, -0.2)
        m.cyl("Cup", 0.28, 0.2, cc + V(0, 0.14, 0), WHITE)
        m.cyl("Cup", 0.06, 0.21, cc + V(0, 0.16, 0), (255, 196, 40))
        if k == 1:
            m.cyl("Lemonade", 0.02, 0.17, cc + V(0, 0.28, 0), (255, 224, 70))
            m.rod("Straw", cc + V(0.02, 0.2, 0), cc + V(0.08, 0.44, 0.02), 0.03, (240, 80, 90))
    bc = V(0.92, 1.26, 0.18)
    m.cyl("Basket", 0.26, 0.6, bc + V(0, 0.13, 0), (196, 150, 90), "y", "Fabric")
    m.cyl("Basket", 0.06, 0.64, bc + V(0, 0.25, 0), (160, 116, 64), "y", "Fabric")
    for (x, z) in ((-0.12, -0.08), (0.12, -0.05), (0.0, 0.12), (0.02, -0.02)):
        m.ell("Lemon", (0.2, 0.17, 0.17), bc + V(x, 0.32 + (0.06 if (x, z) == (0.02, -0.02) else 0), z), LEMON)
    m.cyl("TipJar", 0.3, 0.24, (0.62, 1.41, 0.42), (220, 240, 255), "y", "Glass", tr=0.4)
    m.cyl("Coins", 0.1, 0.2, (0.62, 1.31, 0.42), GOLD, "y", "Metal")
    # a crate of lemons on the deck
    m.blk("Crate", (0.46, 0.34, 0.4), (1.4, 0.31, -0.6), WOOD_D, "WoodPlanks")
    m.blk("Crate", (0.48, 0.06, 0.42), (1.4, 0.42, -0.6), WOOD_X, "Wood")
    for (x, z) in ((-0.1, -0.08), (0.1, 0.06), (0.0, -0.02)):
        m.ell("Lemon", (0.2, 0.17, 0.17), (1.4 + x, 0.52, -0.6 + z), LEMON)
    return m


@model
def disco_cactus():
    """Disco Cactus (Epic): a cactus with moves. A chunky saguaro in a light-up terracotta pot on a
    little dance floor, star sunglasses, a big grin, one arm raised to the sky, a flower, and a
    glittering disco ball floating over its head."""
    m = SModel("disco_cactus", kind="gadget")
    G = (84, 178, 92)
    G_D = (60, 140, 72)
    G_L = (132, 210, 120)
    TERRA = (214, 112, 66)
    TERRA_D = (176, 86, 50)
    # a small dance floor: a 3 x 3 grid of tiles
    cols = [(255, 120, 200), (110, 220, 255), (255, 220, 90), (180, 120, 255)]
    for i in range(3):
        for j in range(3):
            c = cols[(i + j * 2) % 4]
            m.blk("DanceFloor", (0.54, 0.1, 0.54), ((i - 1) * 0.56, 0.05, (j - 1) * 0.56), c, refl=0.15)
    m.blk("DanceFloor", (1.72, 0.06, 1.72), (0, 0.03, 0), (40, 34, 52))
    # the pot: a tapered terracotta pot with a glowing band and painted dots
    m.cyl("Pot", 0.46, 0.92, (0, 0.33, 0), TERRA_D)
    m.cyl("Pot", 0.5, 1.06, (0, 0.78, 0), TERRA)
    m.cyl("PotRim", 0.22, 1.24, (0, 1.12, 0), TERRA)
    m.cyl("PotRim", 0.06, 1.26, (0, 1.02, 0), TERRA_D)
    band = m.cyl("PotGlow", 0.08, 1.08, (0, 0.62, 0), (255, 110, 210), "y", "Neon")
    for k in range(5):
        a = math.radians(225 + k * 22.5)
        m.ball("PotDot", 0.12, (math.cos(a) * 0.53, 0.84, math.sin(a) * 0.53), cols[k % 4])
    m.cyl("Soil", 0.06, 1.08, (0, 1.22, 0), DIRT)
    for (x, z) in ((0.34, -0.22), (-0.3, -0.3)):
        m.ball("Pebble", 0.12, (x, 1.26, z), (220, 210, 196))
    # the cactus: a capsule body with ribs and spines
    m.cyl("Cactus", 1.2, 0.86, (0, 1.82, 0), G)
    m.ball("Cactus", 0.86, (0, 2.42, 0), G)
    m.ball("Cactus", 0.86, (0, 1.26, 0), G)
    for k in range(6):
        a = math.radians(30 + k * 60)
        if abs(math.degrees(a) - 270) < 40:
            continue
        x, z = math.cos(a) * 0.38, math.sin(a) * 0.38
        m.ell("Rib", (0.14, 1.5, 0.14), (x, 1.88, z), G_D)
        for y in (1.55, 2.0, 2.4):
            m.blk("Spine", (0.03, 0.03, 0.16), (x * 1.3, y, z * 1.3), (250, 248, 226), R=Ry(-math.degrees(a)))
    # the arms: one raised to the sky, one on the hip
    m.seg("CactusArm", (0.32, 1.95, 0.04), (0.78, 2.0, 0.04), 0.18, G, bulge=0.5, shape="C")
    m.ball("CactusArm", 0.36, (0.78, 2.0, 0.04), G)
    m.seg("CactusArm", (0.78, 2.0, 0.04), (0.88, 2.78, -0.04), 0.18, G, shape="C")
    m.ball("CactusArm", 0.36, (0.88, 2.78, -0.04), G)
    m.seg("CactusArm", (-0.32, 1.72, 0.0), (-0.74, 1.66, -0.04), 0.16, G, shape="C")
    m.ball("CactusArm", 0.32, (-0.74, 1.66, -0.04), G)
    m.seg("CactusArm", (-0.74, 1.66, -0.04), (-0.76, 1.38, -0.12), 0.16, G, shape="C")
    m.ball("CactusArm", 0.32, (-0.76, 1.38, -0.12), G)
    for p in ((0.84, 2.4, -0.18), (0.62, 2.1, -0.16), (-0.6, 1.8, -0.16)):
        m.blk("Spine", (0.03, 0.03, 0.14), p, (250, 248, 226))
    # the face: star sunglasses over the eyes, cheeks and a big open grin
    def zs(x):
        return -math.sqrt(max(0.43 ** 2 - x * x, 0.0))
    for s in (-1, 1):
        x = s * 0.19
        nrm = V(x, 0.0, zs(x))
        star(m, "Shades", V(x, 2.2, zs(x) - 0.04), nrm, 0.26, 0.06, (255, 70, 200), "Neon", spin=s * 8)
        m.ell("Glint", (0.07, 0.05, 0.02), V(x - 0.05, 2.25, zs(x) - 0.08), WHITE, "Neon")
        m.ell("Brow", (0.2, 0.06, 0.06), V(x, 2.42, zs(x) - 0.02), G_D, R=Ry(-s * 22) @ Rz(-s * 12))
    m.blk("Shades", (0.12, 0.04, 0.04), (0, 2.24, zs(0) - 0.05), (255, 70, 200), "Neon")
    m.mouth(V(0, 1.88, zs(0) + 0.01), V(0, -0.15, -1), 0.32, "eager", skin=G)
    for s in (-1, 1):
        m.ell("Cheek", (0.12, 0.07, 0.04), (s * 0.3, 1.98, zs(0.3) - 0.01), (255, 150, 170))
    # a flower tucked behind its ear
    fc = V(-0.3, 2.66, 0.0)
    for k in range(5):
        a = math.radians(90 + k * 72)
        m.ell("Flower", (0.2, 0.12, 0.08), fc + V(math.cos(a) * 0.12, math.sin(a) * 0.12, -0.06), (255, 90, 160), R=Rz(math.degrees(a)) @ Rx(-20))
    m.ball("Flower", 0.1, fc + V(0, 0, -0.1), (255, 230, 90))
    # the disco ball floating overhead on a thin rod
    m.cyl("BallRod", 0.36, 0.05, (0, 3.02, 0), (200, 204, 214), "y", "Metal")
    bc = V(0, 3.42, 0)
    ball = m.ball("DiscoBall", 0.66, bc, (226, 228, 242), "Foil", refl=0.5)
    for y in (-0.16, 0.0, 0.16):
        r = math.sqrt(max(0.33 ** 2 - y * y, 0.01)) * 2 + 0.01
        m.ell("DiscoTile", (r, 0.035, r), bc + V(0, y, 0), (170, 172, 200), "Foil")
    for a in (0, 60, 120):
        m.ell("DiscoTile", (0.67, 0.67, 0.035), bc, (170, 172, 200), "Foil", R=Ry(a))
    m.sparkles(ball, (255, 150, 230))
    m.light(ball, (255, 140, 230), 1.5, 7)
    m.light(band, (255, 110, 210), 0.8, 4)
    # music notes bouncing out
    for (p, c) in ((V(-0.62, 3.1, -0.1), (255, 110, 210)), (V(0.6, 3.5, -0.08), (110, 220, 255))):
        m.ball("Note", 0.15, p, c, "Neon")
        m.blk("Note", (0.035, 0.32, 0.035), p + V(0.065, 0.15, 0), c, "Neon")
        m.blk("Note", (0.14, 0.05, 0.035), p + V(0.12, 0.3, 0), c, "Neon", R=Rz(-20))
    return m


@model
def haunted_arcade():
    """Haunted Arcade (Mythic): a possessed arcade cabinet. A chunky purple cabinet with glowing pink
    edge trim, a BOO marquee ringed with bulbs, a screen with a pixel ghost, a joystick and buttons,
    a coin door, ghost side art, a ghost floating out of it, a cobweb and creeping mist."""
    m = SModel("haunted_arcade", kind="gadget")
    BODY = (88, 52, 140)
    BODY_D = (60, 36, 100)
    TRIM = (255, 84, 214)
    SCR = (110, 255, 170)
    GH = (228, 236, 255)
    m.rbox("Base", (2.0, 0.14, 1.76), (0, 0.07, 0.06), (46, 36, 62), 0.12)
    # the cabinet: a lower body, a set-back upper body and a top
    m.blk("Cabinet", (1.44, 1.0, 1.0), (0, 0.64, 0.12), BODY)
    m.blk("Cabinet", (1.44, 1.32, 0.9), (0, 1.8, 0.22), BODY)
    m.blk("CabinetTop", (1.68, 0.12, 1.3), (0, 2.52, 0.12), BODY_D)
    for s in (-1, 1):
        x = s * 0.77
        m.blk("SidePanel", (0.1, 1.0, 1.14), (x, 0.64, 0.12), BODY_D)
        m.blk("SidePanel", (0.1, 0.92, 1.02), (x, 1.6, 0.21), BODY_D)
        m.blk("SidePanel", (0.1, 0.46, 1.24), (x, 2.29, 0.1), BODY_D)
        # glowing T-molding along the front edges
        m.blk("Trim", (0.12, 1.0, 0.05), (x, 0.64, -0.46), TRIM, "Neon")
        m.blk("Trim", (0.12, 0.92, 0.05), (x, 1.6, -0.31), TRIM, "Neon")
        m.blk("Trim", (0.12, 0.46, 0.05), (x, 2.29, -0.53), TRIM, "Neon")
        # a ghost painted on each side
        gc = V(s * 0.83, 1.58, 0.24)
        m.ell("SideArt", (0.03, 0.6, 0.48), gc, GH)
        for k in range(3):
            m.ell("SideArt", (0.03, 0.17, 0.17), gc + V(0, -0.29, -0.16 + k * 0.16), GH)
        for k in (-1, 1):
            m.ell("SideEye", (0.03, 0.13, 0.08), gc + V(s * 0.006, 0.06, k * 0.1), (40, 30, 70))
    # the control panel: a joystick and six glowing buttons
    cp = V(0, 1.2, -0.52)
    m.blk("Controls", (1.44, 0.16, 0.58), cp, (112, 72, 176), R=Rx(-10))
    m.blk("ControlTrim", (1.46, 0.06, 0.06), cp + V(0, -0.07, -0.29), TRIM, "Neon")
    with m.group(R=Rx(-10), t=cp):
        m.cyl("JoyBase", 0.04, 0.2, (-0.36, 0.1, 0.0), (24, 20, 30))
        m.cyl("Joystick", 0.26, 0.05, (-0.36, 0.22, 0.0), (40, 40, 44))
        m.ball("JoyBall", 0.18, (-0.36, 0.36, 0.0), (240, 50, 70))
        m.ball("JoyShine", 0.05, (-0.4, 0.41, -0.05), (255, 220, 230), "Neon")
        for k in range(6):
            col = [(255, 220, 60), (60, 180, 255), (255, 80, 110)][k % 3]
            m.cyl("Button", 0.05, 0.12, (0.02 + (k % 3) * 0.19, 0.09, -0.08 + (k // 3) * 0.17), col, "y", "Neon")
    # the screen, tilted back, with a pixel ghost on it
    sc = V(0, 1.68, -0.27)
    with m.group(R=Rx(10), t=sc):
        m.rbox("ScreenBezel", (1.26, 0.86, 0.08), (0, 0, 0), (22, 18, 30), 0.08, axis="z")
        scr = m.blk("Screen", (1.08, 0.68, 0.04), (0, 0, -0.05), (14, 40, 34))
        P = [".XXX.", "XXXXX", "X.X.X", "XXXXX", "X.X.X"]
        px = 0.085
        for r, row in enumerate(P):
            for ci, ch in enumerate(row):
                if ch == "X":
                    m.blk("ScreenPixel", (px * 0.94, px * 0.94, 0.02), ((ci - 2) * px, (2 - r) * px + 0.02, -0.075), SCR, "Neon")
        for ci in (1, 3):
            m.blk("ScreenPixel", (px * 0.5, px * 0.6, 0.02), ((ci - 2) * px, 0.02, -0.075), (60, 120, 255), "Neon")
        m.blk("ScreenPixel", (0.3, 0.04, 0.02), (-0.3, 0.27, -0.075), (255, 230, 120), "Neon")
        for k in range(3):
            m.blk("ScreenPixel", (0.05, 0.05, 0.02), (0.28 + k * 0.08, 0.27, -0.075), (255, 120, 200), "Neon")
    # the marquee with BOO in big letters and a row of bulbs
    mc = V(0, 2.29, -0.38)
    marq = m.rbox("Marquee", (1.44, 0.42, 0.28), mc, (255, 128, 222), 0.06, "Neon", axis="z")
    m.text("MarqueeLetter", "BOO", mc + V(0, 0, -0.15), 0.26, (54, 18, 78), facing="front")
    for k in range(7):
        m.ball("MarqueeBulb", 0.08, mc + V(-0.6 + k * 0.2, 0.24, -0.12), (255, 244, 170), "Neon")
    # the coin door and kick plate
    m.rbox("CoinDoor", (0.66, 0.56, 0.05), (0, 0.66, -0.4), (36, 28, 48), 0.05, axis="z")
    for s in (-1, 1):
        m.blk("CoinSlot", (0.05, 0.16, 0.03), (s * 0.14, 0.76, -0.435), (255, 200, 60), "Neon")
        m.blk("CoinLight", (0.14, 0.08, 0.03), (s * 0.14, 0.52, -0.435), (255, 70, 90), "Neon")
    m.blk("KickPlate", (1.44, 0.16, 0.04), (0, 0.24, -0.4), (24, 20, 30))
    # a ghost drifting out of the side of the cabinet, waving
    gc = V(1.06, 1.86, -0.1)
    ghost = m.ell("Ghost", (0.56, 0.62, 0.48), gc, GH, tr=0.1)
    m.ell("Ghost", (0.5, 0.34, 0.44), gc + V(0.0, -0.26, 0.02), GH, tr=0.1)
    for k in range(3):
        m.ball("GhostTail", 0.18 - k * 0.03, gc + V(0.04 - k * 0.12, -0.44 - k * 0.07, 0.04 + k * 0.05), GH, tr=0.1)
    m.seg("GhostArm", gc + V(0.22, 0.02, -0.06), gc + V(0.4, 0.26, -0.14), 0.08, GH, tr=0.1)
    m.seg("GhostArm", gc + V(-0.22, -0.02, -0.08), gc + V(-0.32, -0.12, -0.24), 0.08, GH, tr=0.1)
    for s in (-1, 1):
        m.ell("GhostEye", (0.1, 0.15, 0.05), gc + V(s * 0.11, 0.06, -0.225), (36, 28, 52))
        m.ball("GhostGlint", 0.035, gc + V(s * 0.11 - 0.025, 0.1, -0.25), WHITE)
        m.ell("GhostBlush", (0.08, 0.04, 0.02), gc + V(s * 0.19, -0.04, -0.21), (255, 170, 210))
    m.ell("GhostMouth", (0.08, 0.09, 0.04), gc + V(0, -0.08, -0.235), (36, 28, 52))
    m.sparkles(ghost, (190, 255, 220))
    # a cobweb in the top corner and a spider on its thread
    hub = V(-0.72, 2.5, -0.53)
    ends = []
    for k in range(4):
        a = math.radians(-90 + k * 30)
        ends.append(hub + V(math.cos(a) * 0.42, math.sin(a) * 0.42, 0))
        m.rod("Web", hub, ends[-1], 0.024, (236, 236, 246))
    for f in (0.45, 0.8):
        for k in range(3):
            m.rod("Web", hub + (ends[k] - hub) * f, hub + (ends[k + 1] - hub) * f, 0.022, (236, 236, 246))
    m.rod("SpiderThread", V(-0.48, 2.46, -0.6), V(-0.48, 2.08, -0.6), 0.022, (236, 236, 246))
    m.ball("Spider", 0.12, (-0.48, 2.02, -0.6), (30, 24, 36))
    for s in (-1, 1):
        for k in range(2):
            m.seg("Spider", V(-0.48 + s * 0.04, 2.02, -0.6), V(-0.48 + s * 0.14, 1.98 - k * 0.06, -0.6 + (k - 0.5) * 0.06), 0.012, (30, 24, 36))
    # the back: a service door with a lock, vents and the power cord
    m.blk("BackDoor", (1.0, 1.4, 0.04), (0, 1.3, 0.68), BODY_D)
    m.blk("BackLock", (0.1, 0.14, 0.04), (0.38, 1.3, 0.71), (200, 190, 120), "Metal")
    for k in range(4):
        m.blk("Vent", (0.6, 0.05, 0.03), (0, 2.1 + k * 0.08, 0.68), (34, 22, 54))
    m.flow("PowerCord", [V(-0.4, 0.5, 0.64), V(-0.45, 0.24, 0.8), V(-0.6, 0.16, 0.86)], [0.05, 0.05, 0.05], (26, 24, 30))
    mist = m.blk("Mist", (0.1, 0.1, 0.1), (0, 0.2, -0.7), (200, 200, 220), tr=1)
    m.smoke(mist, (190, 170, 240), 0.07, 0.3, 1.0)
    m.light(scr, (90, 255, 160), 1.4, 7)
    m.light(marq, (255, 120, 220), 1.0, 5)
    return m


@model
def rocket_lunchbox():
    """Rocket Lunchbox (Legendary): a retro tin lunchbox turned rocket. A red domed lunch pail with a
    chrome latch band and handle, a cream nose cone, swept fins, twin thrusters roaring, glowing
    portholes, stickers, gold trim, a sandwich peeking out, all clamped onto a launch pad."""
    m = SModel("rocket_lunchbox", kind="gadget")
    RD = (232, 64, 60)
    RD_D = (176, 36, 40)
    CREAM = (252, 242, 222)
    # the launch pad with hazard stripes round its rim
    m.cyl("Pad", 0.16, 2.2, (0, 0.08, 0.1), (84, 88, 100), "y", "DiamondPlate")
    for k in range(12):
        a = k * 30
        p = V(math.cos(math.radians(a)) * 1.0, 0.165, math.sin(math.radians(a)) * 1.0 + 0.1)
        m.blk("Hazard", (0.42, 0.02, 0.12), p, YELLOW if k % 2 == 0 else (32, 32, 36), R=Ry(-a - 90))
    for (x, z) in ((-0.5, -0.45), (0.5, -0.45), (-0.5, 0.65), (0.5, 0.65)):
        m.blk("Clamp", (0.12, 0.44, 0.16), (x, 0.38, z), (150, 156, 168), "Metal")
        m.blk("Clamp", (0.2, 0.08, 0.2), (x, 0.6, z), (110, 114, 124), "Metal")
    # the lunchbox body and its domed lid
    BY = 1.0
    m.rbox("Box", (1.3, 0.86, 1.7), (0, BY, 0.1), RD, 0.16, "Metal", axis="z", refl=0.2)
    m.cyl("Lid", 1.7, 1.3, (0, BY + 0.1, 0.1), RD, "z", "Metal", refl=0.2)
    m.blk("LidBand", (1.34, 0.07, 1.74), (0, BY + 0.3, 0.1), CHROME, "Metal", refl=0.3)
    m.blk("GoldTrim", (1.34, 0.07, 1.74), (0, BY - 0.36, 0.1), GOLD, "Foil", refl=0.2)
    for s in (-1, 1):
        m.blk("Latch", (0.06, 0.26, 0.2), (s * 0.68, BY + 0.24, -0.3), CHROME, "Metal")
        m.ball("Latch", 0.08, (s * 0.71, BY + 0.14, -0.3), CHROME, "Metal")
    # the carry handle on top
    for z in (-0.32, 0.52):
        m.cyl("HandleMount", 0.12, 0.16, (0, BY + 0.8, z), CHROME, "y", "Metal")
    hp = [V(0, BY + 0.84, -0.32), V(0, BY + 1.0, -0.2), V(0, BY + 1.04, 0.1), V(0, BY + 1.0, 0.4), V(0, BY + 0.84, 0.52)]
    for i in range(4):
        m.rod("Handle", hp[i], hp[i + 1], 0.1, (36, 36, 40))
    # the nose cone pointing at the enemy
    m.cyl("NoseRing", 0.1, 1.0, (0, BY + 0.05, -0.8), CHROME, "z", "Metal")
    m.seg("NoseCone", V(0, BY + 0.05, -0.82), V(0, BY + 0.05, -1.52), 0.47, CREAM, bulge=0.12)
    m.ell("NoseStripe", (0.93, 0.93, 0.07), (0, BY + 0.05, -1.04), RD)
    m.ball("NoseTip", 0.2, (0, BY + 0.05, -1.5), RD_D)
    # twin thrusters at the back, roaring
    for s in (-1, 1):
        nz = V(s * 0.32, BY - 0.1, 1.04)
        m.cyl("Thruster", 0.2, 0.44, nz, (150, 156, 168), "z", "Metal")
        m.ell("Thruster", (0.56, 0.56, 0.14), nz + V(0, 0, 0.12), (110, 114, 124), "Metal")
        burn = m.cyl("ThrusterGlow", 0.04, 0.36, nz + V(0, 0, 0.18), (255, 160, 60), "z", "Neon")
        m.fire(burn, size=1.2, heat=7)
    # swept fins: two at the sides, one on top
    for s in (-1, 1):
        m.ell("Fin", (0.09, 0.7, 0.78), (s * 0.76, BY - 0.3, 0.74), YELLOW, R=Rz(-s * 28) @ Rx(-18))
        m.ell("FinTip", (0.1, 0.24, 0.42), (s * 0.9, BY - 0.56, 0.86), RD_D, R=Rz(-s * 28) @ Rx(-18))
    m.ell("Fin", (0.09, 0.6, 0.74), (0, BY + 0.98, 0.8), YELLOW, R=Rx(-18))
    m.ell("FinTip", (0.1, 0.22, 0.4), (0, BY + 1.2, 0.9), RD_D, R=Rx(-18))
    # glowing portholes and stickers on the sides
    for s in (-1, 1):
        pc = V(s * 0.66, BY + 0.04, -0.28)
        disc(m, "Porthole", pc, V(s, 0, 0), 0.46, 0.06, CHROME, "Metal")
        win = disc(m, "PortholeGlass", pc + V(s * 0.02, 0, 0), V(s, 0, 0), 0.34, 0.05, (120, 220, 255), "Neon")
        m.light(win, (120, 220, 255), 0.8, 4)
        if s > 0:
            star(m, "Sticker", V(0.66, BY + 0.02, 0.38), V(1, 0, 0), 0.3, 0.03, YELLOW)
        else:
            disc(m, "Sticker", V(-0.66, BY + 0.02, 0.38), V(-1, 0, 0), 0.32, 0.03, (120, 200, 255))
            m.ball("Sticker", 0.18, (-0.67, BY + 0.02, 0.38), (240, 120, 200))
            m.ell("Sticker", (0.04, 0.06, 0.34), (-0.68, BY + 0.02, 0.38), WHITE, R=Rx(25))
    # a sandwich peeking out of the lid at the front
    m.blk("Sandwich", (0.46, 0.08, 0.26), (0.32, BY + 0.34, -0.8), (240, 204, 134))
    m.ell("Lettuce", (0.52, 0.05, 0.3), (0.32, BY + 0.29, -0.8), (110, 200, 80))
    m.blk("Cheese", (0.2, 0.04, 0.2), (0.44, BY + 0.31, -0.86), (255, 214, 70), R=Ry(45))
    m.sparkles(win, (255, 230, 140))
    return m


@model
def snack_bar():
    """Snack Bar (Common): a candy-striped snack kiosk that heals. A pink counter with cream stripes,
    candy-cane posts, a puffy canopy with a scalloped edge and string lights, a menu board, treats on
    the counter and a giant sprinkled donut on the roof with a glowing heart in its hole."""
    m = SModel("snack_bar", kind="gadget")
    S = PAL["Snack"]
    PK = S["pink"]
    PK_D = (214, 82, 124)
    CREAM = S["second"]
    MINT = S["mint"]
    CHOC = S["choc"]
    DOUGH = (232, 168, 84)
    # the tiled floor
    m.rbox("Base", (3.0, 0.14, 2.24), (0, 0.07, 0.06), CREAM, 0.12)
    for k in range(6):
        m.blk("Tile", (0.36, 0.02, 0.36), (-1.1 + k * 0.44, 0.145, -0.84), PK)
    # the counter
    m.rbox("Counter", (2.6, 1.0, 1.5), (0, 0.64, 0.15), PK, 0.14)
    for k in range(6):
        m.blk("Stripe", (0.18, 0.96, 0.02), (-1.1 + k * 0.44, 0.64, -0.61), CREAM)
    m.rbox("CounterTop", (2.86, 0.14, 1.72), (0, 1.21, 0.12), CREAM, 0.12)
    m.cyl("CounterTop", 2.86, 0.16, (0, 1.2, -0.72), MINT, "x")
    # the back wall with a chalk menu board
    m.blk("BackWall", (2.6, 1.22, 0.14), (0, 1.89, 0.86), PK)
    m.blk("Menu", (1.5, 0.72, 0.05), (0, 1.9, 0.78), (46, 64, 56))
    m.blk("MenuFrame", (1.6, 0.82, 0.03), (0, 1.9, 0.8), (150, 96, 60))
    for k in range(3):
        m.blk("MenuLine", (0.7, 0.04, 0.02), (0.18, 2.1 - k * 0.2, 0.75), (236, 236, 226))
        col = [(255, 140, 190), (255, 214, 90), (140, 230, 200)][k]
        m.ball("MenuIcon", 0.12, (-0.45, 2.1 - k * 0.2, 0.75), col)
    # candy-cane posts
    for x in (-1.3, 1.3):
        for z in (-0.66, 0.84):
            m.cyl("Post", 1.2, 0.14, (x, 1.88, z), WHITE, "y")
            for k in range(3):
                m.ell("PostStripe", (0.16, 0.06, 0.16), (x, 1.5 + k * 0.32, z), (230, 45, 70), R=Rz(24))
    # the puffy canopy with a scalloped edge and string lights
    m.rbox("Canopy", (3.0, 0.2, 2.24), (0, 2.56, 0.1), PK, 0.12)
    m.blk("Canopy", (3.04, 0.06, 2.28), (0, 2.67, 0.1), MINT)
    for k in range(7):
        x = -1.29 + k * 0.43
        m.ell("Scallop", (0.44, 0.3, 0.1), (x, 2.44, -1.0), PK if k % 2 == 0 else CREAM)
    for sx in (-1, 1):
        for k in range(5):
            z = -0.75 + k * 0.42
            m.ell("Scallop", (0.1, 0.3, 0.42), (sx * 1.5, 2.44, z), PK if k % 2 else CREAM)
    for k in range(6):
        x = -1.12 + k * 0.45
        y = 2.3 - 0.05 * math.sin(math.pi * k / 5)
        m.ball("Bulb", 0.1, (x, y, -0.96), [(255, 236, 140), (255, 150, 190), (150, 240, 210)][k % 3], "Neon")
    m.rod("LightWire", V(-1.3, 2.36, -0.97), V(1.3, 2.36, -0.97), 0.02, (60, 50, 50))
    # a sign on the roof edge and the giant donut behind it, with a glowing heart in its hole
    sign(m, V(0, 2.92, -0.78), 1.44, 0.36, CREAM, "SNACKS", PK_D, border=PK_D, t=0.08, letter_h=0.2)
    dc = V(0, 3.12, 0.12)
    torus(m, "Donut", dc, 0.34, 0.18, DOUGH, n=10)
    torus(m, "Icing", dc + V(0, 0.0, -0.07), 0.34, 0.15, PK, n=10, flat=0.9)
    for k in range(8):
        a = math.radians(k * 45 + 20)
        p = dc + V(math.cos(a) * 0.34, math.sin(a) * 0.34, -0.2)
        m.blk("Sprinkle", (0.1, 0.03, 0.03), p, [(255, 240, 120), (120, 210, 255), (255, 255, 255), (140, 230, 160)][k % 4], R=Rz(k * 67))
    heart = m.ball("Heart", 0.16, dc + V(-0.055, 0.03, -0.02), (255, 60, 100), "Neon")
    m.ball("Heart", 0.16, dc + V(0.055, 0.03, -0.02), (255, 60, 100), "Neon")
    m.blk("Heart", (0.14, 0.14, 0.12), dc + V(0, -0.04, -0.02), (255, 60, 100), "Neon", R=Rz(45))
    m.light(heart, (255, 120, 150), 1.0, 6)
    # treats on the counter: a burger, a soda, an ice cream cone and a cupcake
    top = 1.28
    bc = V(-0.82, top, -0.25)
    m.cyl("Burger", 0.12, 0.48, bc + V(0, 0.06, 0), DOUGH)
    m.cyl("Burger", 0.1, 0.52, bc + V(0, 0.16, 0), CHOC)
    m.blk("Burger", (0.4, 0.03, 0.4), bc + V(0, 0.22, 0), (255, 210, 60), R=Ry(45))
    m.cyl("Burger", 0.04, 0.56, bc + V(0, 0.24, 0), (110, 200, 80))
    m.ell("Burger", (0.5, 0.3, 0.5), bc + V(0, 0.3, 0), DOUGH)
    for (x, z) in ((-0.08, -0.12), (0.1, -0.08), (0.0, -0.18)):
        m.ell("Sesame", (0.05, 0.03, 0.04), bc + V(x, 0.42, z), (255, 246, 214))
    cc = V(-0.12, top, -0.3)
    m.cyl("Soda", 0.42, 0.3, cc + V(0, 0.21, 0), (230, 45, 70))
    m.cyl("Soda", 0.1, 0.31, cc + V(0, 0.24, 0), WHITE)
    m.cyl("Soda", 0.05, 0.33, cc + V(0, 0.44, 0), WHITE)
    m.rod("Straw", cc + V(0.03, 0.42, 0), cc + V(0.1, 0.72, 0.03), 0.04, (255, 220, 80))
    ic = V(0.5, top, -0.28)
    m.seg("Cone", ic + V(0, 0.42, 0), ic + V(0, 0.0, 0), 0.13, (220, 172, 104), bulge=0.18)
    m.ball("Scoop", 0.28, ic + V(0, 0.48, 0), (255, 196, 220))
    m.ball("Scoop", 0.24, ic + V(0.0, 0.68, 0), (150, 236, 200))
    m.ball("Cherry", 0.1, ic + V(0, 0.84, 0), (220, 30, 50))
    # the back: a back door, a round window and snack crates
    door(m, V(0.62, 0.14, 0.9), 0.5, 1.0, CREAM, MINT, yaw=180, knob=GOLD, planks=2, straps=None)
    disc(m, "BackWindow", V(-0.5, 1.9, 0.94), V(0, 0, 1), 0.46, 0.05, MINT)
    disc(m, "BackWindow", V(-0.5, 1.9, 0.96), V(0, 0, 1), 0.36, 0.04, (140, 200, 240), refl=0.2)
    for (x, y, w) in ((-0.62, 0.32, 0.44), (-0.6, 0.66, 0.36)):
        m.blk("Crate", (w, 0.34, 0.32), (x, y, 1.12), (214, 170, 110), "WoodPlanks")
        m.blk("Crate", (w * 0.6, 0.12, 0.02), (x, y + 0.02, 1.29), PK)
    kc = V(0.95, top, 0.2)
    m.cyl("Cupcake", 0.2, 0.3, kc + V(0, 0.1, 0), (120, 200, 255))
    m.ell("Frosting", (0.34, 0.16, 0.34), kc + V(0, 0.24, 0), (255, 246, 236))
    m.ell("Frosting", (0.22, 0.14, 0.22), kc + V(0, 0.34, 0), (255, 246, 236))
    m.ball("Cherry", 0.1, kc + V(0, 0.43, 0), (220, 30, 50))
    return m


@model
def bunny_burrow():
    """Bunny Burrow (Rare): a cosy hill home. A grassy mound with a round wooden door in a ring of
    stones, round lit windows, a stone chimney puffing smoke, a bunny popping out of a hole, a
    carrot patch, a mailbox, a signpost, flowers and mushrooms."""
    m = SModel("bunny_burrow", kind="gadget")
    from modelkit import on_ell
    m.cyl("Base", 0.12, 2.8, (0, 0.06, 0.05), GRASS_D, "y", "Grass")
    mc, ms = V(0, 0.05, 0.15), V(2.6, 2.0, 2.3)
    m.ell("Mound", ms, mc, GRASS, "Grass")
    m.ell("Mound", (1.6, 1.0, 1.4), (0.25, 0.62, 0.42), GRASS_L, "Grass")

    def surf(x, z, out=0.0):
        """The point on the mound above (x, z) and its normal."""
        q = 1 - (x / 1.3) ** 2 - ((z - 0.15) / 1.15) ** 2
        y = 0.05 + 1.0 * math.sqrt(max(q, 0.0))
        nrm = norm(V(x / 1.3 ** 2, (y - 0.05) / 1.0, (z - 0.15) / 1.15 ** 2))
        return V(x, y, z) + nrm * out, nrm

    # the round door in a ring of stones
    p, n = surf(0, -0.84)
    p = p + V(0, -0.06, 0)
    disc(m, "Door", p + n * 0.02, n, 0.7, 0.08, (178, 110, 62), "Wood")
    F = frame_normal(n)
    for k in range(3):
        m.add("B", "DoorPlank", (0.025, 0.6, 0.02), p + n * 0.065 + F[:, 0] * (k - 1) * 0.17, shade((178, 110, 62), 0.7), "SmoothPlastic", F)
    m.add("B", "DoorStrap", (0.56, 0.06, 0.03), p + n * 0.075 + F[:, 1] * 0.12, IRON, "Metal", F)
    m.add("B", "DoorStrap", (0.56, 0.06, 0.03), p + n * 0.075 - F[:, 1] * 0.14, IRON, "Metal", F)
    m.ball("DoorKnob", 0.1, p + n * 0.1 + F[:, 0] * 0.18, GOLD, "Metal")
    for k in range(10):
        a = math.radians(k * 36 + 10)
        q = p + n * 0.03 + (F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)) * 0.42
        m.add("E", "DoorStone", (0.2, 0.15, 0.12), q, shade(STONE, 0.9 + 0.08 * (k % 3)), "Slate", F @ Rz(math.degrees(a) + 90))
    m.blk("Step", (0.6, 0.08, 0.3), (0, 0.16, -1.08), STONE, "Slate")
    # round lit windows either side
    for sx in (-1, 1):
        q, nn = surf(sx * 0.74, -0.62)
        q = q + V(0, -0.02, 0)
        disc(m, "WindowFrame", q + nn * 0.02, nn, 0.36, 0.06, WOOD_D, "Wood")
        disc(m, "Window", q + nn * 0.05, nn, 0.26, 0.04, LIT, "Neon")
        Fw = frame_normal(nn)
        m.add("B", "WindowFrame", (0.03, 0.26, 0.03), q + nn * 0.075, WOOD_D, "SmoothPlastic", Fw)
        m.add("B", "WindowFrame", (0.26, 0.03, 0.03), q + nn * 0.075, WOOD_D, "SmoothPlastic", Fw)
        m.add("E", "FlowerBox", (0.36, 0.08, 0.1), q + nn * 0.08 - Fw[:, 1] * 0.2, (230, 120, 150), "SmoothPlastic", Fw)
    # a stone chimney poking out of the hill
    c, _ = surf(0.62, 0.62)
    chimney(m, c + V(0, -0.12, 0), 0.26, 0.5, (170, 120, 96), STONE_D)
    # the bunny popping out of its hole
    hp, hn = surf(-0.78, -0.36)
    Fh = frame_normal(hn)
    m.add("E", "Hole", (0.5, 0.46, 0.08), hp + hn * 0.0, (44, 30, 24), "SmoothPlastic", Fh)
    for k in range(8):
        a = math.radians(k * 45)
        m.add("E", "HoleRim", (0.16, 0.12, 0.1), hp + (Fh[:, 0] * math.cos(a) * 0.26 + Fh[:, 1] * math.sin(a) * 0.24) + hn * 0.02,
              (140, 98, 66), "SmoothPlastic", Fh @ Rz(k * 45 + 90))
    W_ = (250, 246, 240)
    hc = hp + hn * 0.12 + V(0, 0.12, 0)
    m.ell("BunnyHead", (0.5, 0.44, 0.44), hc, W_)
    m.ell("Snout", (0.26, 0.17, 0.14), hc + V(0, -0.08, -0.19), W_)
    for s in (-1, 1):
        m.ear(hc + V(s * 0.12, 0.16, 0.02), hc + V(s * 0.24, 0.62, 0.06), 0.17, W_, inner=(255, 176, 196), curve=(s * 0.04, 0, 0.02))
        m.eye(hc + V(s * 0.12, 0.05, -0.18), V(s * 0.45, 0.1, -1), 0.13, 0.16, W_, "eager", side=s, iris=(110, 76, 60))
        m.ell("Cheek", (0.08, 0.05, 0.03), hc + V(s * 0.17, -0.06, -0.18), (255, 170, 190))
        m.blk("Whisker", (0.2, 0.02, 0.02), hc + V(s * 0.2, -0.07, -0.2), (170, 170, 176), R=Rz(s * 10))
        m.ell("BunnyPaw", (0.14, 0.1, 0.16), hp + hn * 0.06 + V(s * 0.16, -0.02, -0.18), W_)
    m.ell("Nose", (0.08, 0.06, 0.05), hc + V(0, -0.03, -0.26), (255, 140, 170))
    m.ell("Tooth", (0.07, 0.06, 0.03), hc + V(0, -0.15, -0.245), WHITE)
    # the carrot patch
    m.ell("Patch", (0.7, 0.06, 0.46), (0.95, 0.12, -0.86), DIRT)
    for (x, z, a) in ((0.76, -0.86, 10), (0.96, -0.98, -8), (1.14, -0.8, 14)):
        m.seg("Carrot", (x, 0.1, z), (x, 0.3, z), 0.08, (250, 140, 40), bulge=0.65)
        for k in (-1, 0, 1):
            m.seg("CarrotTop", (x, 0.28, z), (x + k * 0.07, 0.48, z + 0.02 * k), 0.035, (80, 170, 70), bulge=0.3)
    # a little mailbox with its flag up
    mbx = V(-1.06, 0.12, -0.8)
    m.cyl("MailPost", 0.46, 0.07, mbx + V(0, 0.23, 0), WOOD_D, "y", "Wood")
    m.rbox("Mailbox", (0.24, 0.2, 0.34), mbx + V(0, 0.55, 0), (220, 64, 64), 0.08, axis="z")
    m.blk("MailFlag", (0.03, 0.14, 0.1), mbx + V(0.135, 0.66, 0.06), (250, 140, 40))
    m.blk("MailLetter", (0.16, 0.1, 0.02), mbx + V(0, 0.55, -0.18), (250, 246, 230), R=Rx(-10) @ Rz(8))
    # a signpost with a carrot arrow
    m.cyl("SignPost", 0.8, 0.08, (1.12, 0.5, 0.42), WOOD_D, "y", "Wood")
    m.rbox("SignBoard", (0.56, 0.24, 0.06), (1.12, 0.78, 0.38), WOOD_L, 0.06, "Wood", R=Rz(-5), axis="z")
    m.ell("SignCarrot", (0.32, 0.08, 0.03), (1.12, 0.78, 0.34), (250, 140, 40), R=Rz(-5))
    # flowers, mushrooms and grass
    flower(m, V(-0.5, 0.12, -1.1), (255, 140, 200))
    flower(m, V(0.42, 0.12, -1.12), (255, 220, 90))
    flower(m, V(-1.25, 0.12, 0.3), (160, 200, 255))
    for (x, z, d) in ((-0.95, 0.75, 0.22), (1.18, -0.1, 0.18)):
        m.cyl("Mushroom", 0.12, d * 0.4, (x, 0.18, z), (250, 240, 226))
        m.ell("Mushroom", (d, d * 0.55, d), (x, 0.26, z), (230, 70, 60))
        m.ball("MushroomDot", d * 0.22, (x + d * 0.2, 0.3, z - d * 0.2), WHITE)
    grass(m, [V(-0.3, 0.1, -1.2), V(0.62, 0.1, -1.2), V(1.3, 0.1, 0.0), V(-1.3, 0.1, -0.2), V(-0.6, 1.0, 0.4), V(0.3, 1.12, 0.1)])
    return m


@model
def wind_turbine():
    """Wind Turbine (Rare): a sky-blue and white turbine on a round cottage. A stone base, the cottage
    with a door, round windows and a cone roof, a tapering tower with blue bands, a nacelle with a
    warning light, a hub and three big blades with orange tips, and puffy clouds with a gust."""
    m = SModel("wind_turbine", kind="gadget")
    W = PAL["Weather"]
    SK = W["main"]
    WH = W["second"]
    SL = W["slate"]
    m.cyl("Base", 0.2, 2.1, (0, 0.1, 0.1), STONE_D, "y", "Slate")
    m.cyl("Base", 0.08, 2.16, (0, 0.22, 0.1), STONE, "y", "Slate")
    # the round cottage at the foot of the tower
    m.cyl("House", 0.86, 1.3, (0, 0.65, 0.1), WH)
    m.cyl("House", 0.12, 1.36, (0, 0.32, 0.1), SK)
    m.ell("HouseRoof", (1.62, 0.3, 1.62), (0, 1.08, 0.1), SL)
    m.seg("HouseRoof", V(0, 1.08, 0.1), V(0, 1.62, 0.1), 0.72, SK, bulge=0.06)
    door(m, V(0, 0.26, -0.53), 0.36, 0.54, (90, 140, 210), (220, 228, 240), knob=GOLD, planks=2, straps=None)
    for a in (-48, 48):
        r = math.radians(a)
        c = V(math.sin(r) * 0.66, 0.66, 0.1 - math.cos(r) * 0.66)
        disc(m, "WindowFrame", c, V(math.sin(r), 0, -math.cos(r)), 0.26, 0.05, SL)
        disc(m, "Window", c + V(math.sin(r), 0, -math.cos(r)) * 0.02, V(math.sin(r), 0, -math.cos(r)), 0.18, 0.04, LIT, "Neon")
    # the tower: three tapering sections with blue bands, round windows and a ladder
    m.cyl("Tower", 0.9, 0.58, (0, 1.95, 0.1), WH)
    m.cyl("Tower", 0.8, 0.5, (0, 2.8, 0.1), WH)
    m.cyl("Tower", 0.6, 0.42, (0, 3.5, 0.1), WH)
    for (y, d) in ((1.52, 0.64), (2.4, 0.56), (3.2, 0.48), (3.78, 0.44)):
        m.cyl("TowerBand", 0.1, d, (0, y, 0.1), SK)
    for y in (2.0, 2.85):
        disc(m, "Window", V(0, y, 0.1 - 0.27 + (0.02 if y > 2.5 else 0)), V(0, 0, -1), 0.14, 0.05, (150, 210, 255))
    # the nacelle with a stripe, a warning light and a tail vane
    nc = V(0, 4.0, 0.2)
    m.rbox("Nacelle", (0.6, 0.52, 1.0), nc, WH, 0.18, axis="z")
    m.blk("Nacelle", (0.62, 0.08, 1.02), nc + V(0, 0.08, 0), SK)
    warn = m.ball("Warning", 0.14, nc + V(0, 0.34, 0.24), (255, 70, 70), "Neon")
    m.light(warn, (255, 90, 90), 0.6, 3)
    plank(m, "Vane", nc + V(0, 0.1, 0.48), nc + V(0, 0.2, 0.86), 0.03, 0.04, (160, 170, 186), "Metal", side=(0, 1, 0))
    m.ell("VaneFin", (0.04, 0.3, 0.3), nc + V(0, 0.24, 0.88), W["accent"])
    # the hub, the spinner and three big blades
    hub = V(0, 4.0, -0.36)
    m.ell("Hub", (0.46, 0.46, 0.3), hub, SK)
    m.seg("Spinner", hub + V(0, 0, -0.04), hub + V(0, 0, -0.42), 0.18, WH, bulge=0.2)
    m.ball("SpinnerTip", 0.1, hub + V(0, 0, -0.42), (255, 140, 80))
    for k in range(3):
        a = math.radians(105 + k * 120)
        d = V(math.cos(a), math.sin(a), 0)
        # each blade is pitched 30 degrees about its own length, like a real rotor
        side = V(-math.sin(a), math.cos(a), 0) * math.cos(math.radians(30)) + V(0, 0, 1) * math.sin(math.radians(30))
        root = hub + V(0, 0, -0.06)
        m.seg("BladeRoot", root + d * 0.14, root + d * 0.46, 0.11, (226, 232, 242))
        Rb = np.column_stack([side, np.cross(d, side), d])
        plank(m, "Blade", root + d * 0.36 + side * 0.05, root + d * 0.92 + side * 0.05, 0.44, 0.08, WH, side=side)
        m.ell("Blade", (0.44, 0.08, 0.36), root + d * 0.36 + side * 0.05, WH, R=Rb)
        plank(m, "Blade", root + d * 0.88 + side * 0.03, root + d * 1.3 + side * 0.03, 0.34, 0.075, WH, side=side)
        plank(m, "BladeTip", root + d * 1.28 + side * 0.03, root + d * 1.48 + side * 0.03, 0.3, 0.08, (255, 140, 80), side=side)
        m.ell("BladeTip", (0.3, 0.08, 0.22), root + d * 1.48 + side * 0.03, (255, 140, 80), R=Rb)
        plank(m, "BladeStripe", root + d * 1.08 + side * 0.03, root + d * 1.15 + side * 0.03, 0.35, 0.085, SK, side=side)
    # puffy clouds round the base, one of them dozing, and a gust of wind
    for (x, y, z, sx) in ((-0.95, 0.42, 0.62, 0.8), (0.95, 0.4, -0.5, 0.7), (0.92, 0.42, 0.72, 0.6)):
        m.ell("Cloud", (sx, sx * 0.56, sx * 0.72), (x, y, z), (232, 238, 250))
        m.ell("Cloud", (sx * 0.62, sx * 0.52, sx * 0.52), (x + sx * 0.3, y + sx * 0.2, z - 0.04), (248, 250, 255))
        m.ell("Cloud", (sx * 0.52, sx * 0.44, sx * 0.46), (x - sx * 0.3, y + sx * 0.14, z - 0.06), (244, 247, 255))
    cf = V(0.95, 0.44, -0.78)
    for s in (-1, 1):
        m.eye(cf + V(s * 0.1, 0.02, 0.0), V(s * 0.2, 0.1, -1), 0.1, 0.1, (232, 238, 250), "sleepy", side=s)
    m.ell("Cheek", (0.08, 0.04, 0.03), cf + V(0.2, -0.06, 0.02), (255, 180, 200))
    for (c, L, sgn) in ((V(-0.72, 3.0, -0.5), 0.5, 1), (V(0.78, 2.2, -0.6), 0.42, -1)):
        pts = [c + V(-sgn * L, -0.06, 0), c + V(-sgn * L * 0.2, 0.04, 0), c + V(sgn * L * 0.45, 0.02, 0),
               c + V(sgn * L * 0.7, 0.16, 0), c + V(sgn * L * 0.5, 0.3, 0)]
        for i in range(4):
            m.seg("Gust", pts[i], pts[i + 1], 0.05 - i * 0.008, (214, 232, 255), tr=0.25, ext=0.03)
    swirl = m.blk("WindSwirl", (0.1, 0.1, 0.1), (0, 1.8, -0.6), WH, tr=1)
    m.smoke(swirl, (220, 235, 255), 0.06, 1.2, 0.6)
    return m


@model
def spooky_crypt():
    """Spooky Crypt (Rare): a stone mausoleum. A stepped base, thick block walls, a columned porch
    under an overhanging slate roof with a skull on the pediment, an iron door with purple light
    leaking round it, candles, tombstones, ivy, a cobweb, a bat on the ridge and creeping mist."""
    m = SModel("spooky_crypt", kind="gadget")
    SP = PAL["Spooky"]
    ST = (150, 144, 162)
    ST_D = (112, 106, 126)
    ST_L = (186, 180, 198)
    ROOF = (78, 62, 108)
    GLOW = (170, 90, 255)
    GR = SP["accent"]
    BONE = SP["bone"]
    # the stepped base and front steps
    m.blk("Base", (2.7, 0.18, 2.5), (0, 0.09, 0.1), ST_D, "Slate")
    m.blk("Base", (2.4, 0.14, 2.2), (0, 0.25, 0.14), ST, "Slate")
    m.blk("Step", (1.1, 0.16, 0.3), (0, 0.08, -1.3), ST, "Slate")
    # thick stone walls with block seams
    m.blk("Walls", (2.0, 1.7, 1.8), (0, 1.17, 0.24), ST, "Slate")
    for k in range(4):
        m.blk("Seam", (2.02, 0.03, 1.82), (0, 0.66 + k * 0.38, 0.24), ST_D)
    for row in range(5):
        for j in range(2):
            x = (-0.62 if row % 2 else -0.36) + j * (1.24 if row % 2 else 0.72)
            if abs(x) < 0.45:
                continue
            m.blk("Seam", (0.03, 0.34, 0.02), (x, 0.51 + row * 0.38, -0.665), ST_D)
    # the porch: columns, a beam and the roof with its pediment
    for s in (-1, 1):
        x = s * 0.8
        m.blk("PillarBase", (0.42, 0.14, 0.42), (x, 0.39, -0.95), ST_L, "Marble")
        m.cyl("Pillar", 1.5, 0.3, (x, 1.21, -0.95), ST_L, "y", "Marble")
        for k in (-1, 1):
            m.blk("Pillar", (0.025, 1.4, 0.02), (x + k * 0.07, 1.21, -1.1), shade(ST_L, 0.84))
        m.blk("PillarCap", (0.44, 0.14, 0.44), (x, 2.02, -0.95), ST_L, "Marble")
    m.blk("Beam", (2.2, 0.22, 0.5), (0, 2.2, -0.9), ST_L, "Marble")
    gable_roof(m, V(0, 2.31, -0.05), 2.4, 2.2, 0.82, ROOF, t=0.17, over=0.22, side_over=0.16, rows=2, axis="z",
               gables=ST_L, mat="Slate")
    # a grinning skull on the pediment
    sk = V(0, 2.62, -1.2)
    m.ball("Skull", 0.36, sk, BONE)
    m.blk("SkullJaw", (0.22, 0.12, 0.16), sk + V(0, -0.17, -0.04), BONE)
    for s in (-1, 1):
        m.ell("SkullEye", (0.1, 0.11, 0.06), sk + V(s * 0.08, 0.02, -0.15), GLOW, "Neon")
    m.ell("SkullNose", (0.05, 0.06, 0.04), sk + V(0, -0.07, -0.17), (40, 30, 50))
    for k in range(3):
        m.blk("SkullTooth", (0.045, 0.05, 0.02), sk + V(-0.05 + k * 0.05, -0.17, -0.125), WHITE)
    # the iron door with purple light seeping round its edges
    glow = m.blk("DoorGlow", (0.78, 0.86, 0.04), (0, 0.75, -0.67), GLOW, "Neon")
    m.cyl("DoorGlow", 0.04, 0.78, (0, 1.18, -0.67), GLOW, "z", "Neon")
    door(m, V(0, 0.32, -0.69), 0.66, 1.22, (66, 60, 78), ST_L, knob=None, planks=3, straps=(40, 38, 48))
    m.ball("Keyhole", 0.08, (0, 0.88, -0.79), GR, "Neon")
    m.blk("Keyhole", (0.04, 0.1, 0.03), (0, 0.82, -0.785), GR, "Neon")
    m.ring("Knocker", (0, 1.06, -0.8), 0.08, 0.025, (40, 38, 48), "z", 8, "Metal")
    m.light(glow, GLOW, 1.6, 7)
    # candles on the steps and the base
    for (x, y, z, h) in ((-1.0, 0.32, -0.95, 0.32), (1.0, 0.32, -0.95, 0.24), (0.42, 0.16, -1.3, 0.2)):
        m.cyl("Candle", h, 0.14, (x, y + h / 2, z), (246, 240, 222))
        m.drip("Wax", (x + 0.06, y + h - 0.02, z - 0.05), 0.1, 0.05, (246, 240, 222))
        f = m.ell("Flame", (0.1, 0.18, 0.1), (x, y + h + 0.1, z), (255, 176, 70), "Neon")
    # tombstones beside the crypt
    for (x, z, a) in ((-1.12, 0.62, -8), (1.14, 0.3, 6)):
        m.rbox("Tombstone", (0.34, 0.5, 0.12), (x, 0.57, z), (160, 154, 172), 0.12, "Slate", R=Rz(a), axis="z")
        m.blk("TombCross", (0.04, 0.2, 0.02), (x, 0.62, z - 0.07), (110, 104, 122), R=Rz(a))
        m.blk("TombCross", (0.13, 0.04, 0.02), (x, 0.66, z - 0.07), (110, 104, 122), R=Rz(a))
    # ivy climbing the left column
    for (y, z, k) in ((0.6, -1.08, 0), (0.95, -1.1, 1), (1.3, -1.08, 2), (1.62, -1.06, 3)):
        m.ell("Ivy", (0.2, 0.14, 0.08), (-0.8 + 0.08 * (k % 2 * 2 - 1), y, z), (88, 150, 80) if k % 2 else (70, 128, 66), R=Rz(30 * (k % 2 * 2 - 1)))
    m.rod("Vine", V(-0.84, 0.46, -1.09), V(-0.76, 1.7, -1.08), 0.03, (70, 110, 60))
    # a bat clinging to the ridge
    bt = V(0.3, 3.26, 0.4)
    m.ball("Bat", 0.2, bt, (40, 32, 52))
    for s in (-1, 1):
        m.ell("BatWing", (0.34, 0.04, 0.2), bt + V(s * 0.2, 0.02, 0), (54, 42, 70), R=Rz(-s * 20))
        m.wedge("BatEar", (0.03, 0.08, 0.05), bt + V(s * 0.05, 0.12, 0), (40, 32, 52))
        m.ball("BatEye", 0.04, bt + V(s * 0.04, 0.02, -0.09), (255, 80, 80), "Neon")
    # a crack, a cobweb in the porch corner, and mist
    m.blk("Crack", (0.04, 0.4, 0.02), (0.62, 1.3, -0.665), (90, 84, 104), R=Rz(24))
    m.blk("Crack", (0.04, 0.24, 0.02), (0.66, 1.06, -0.665), (90, 84, 104), R=Rz(-18))
    hub = V(0.62, 2.05, -1.16)
    ends = [hub + V(math.cos(math.radians(a)) * 0.34, math.sin(math.radians(a)) * 0.34, 0) for a in (180, 220, 260)]
    for e in ends:
        m.rod("Web", hub, e, 0.024, (236, 236, 246))
    for f in (0.5, 0.85):
        for k in range(2):
            m.rod("Web", hub + (ends[k] - hub) * f, hub + (ends[k + 1] - hub) * f, 0.024, (236, 236, 246))
    # the back: a round barred window glowing purple, and ivy
    wb = V(0, 1.45, 1.15)
    disc(m, "BackWindow", wb, V(0, 0, 1), 0.66, 0.06, ST_L, "Marble")
    disc(m, "BackWindow", wb + V(0, 0, 0.02), V(0, 0, 1), 0.48, 0.05, GLOW, "Neon")
    for k in range(3):
        m.blk("Bars", (0.035, 0.48, 0.04), wb + V(-0.12 + k * 0.12, 0, 0.05), (40, 38, 48), "Metal")
    for (x, y, k) in ((-0.62, 0.7, 0), (-0.7, 1.05, 1), (-0.58, 1.4, 0), (0.66, 0.66, 1), (0.6, 0.98, 0)):
        m.ell("Ivy", (0.22, 0.14, 0.08), (x, y, 1.16), (88, 150, 80) if k else (70, 128, 66), R=Rz(28 if k else -28))
    mist = m.blk("Mist", (0.1, 0.1, 0.1), (0, 0.4, -1.0), (200, 200, 220), tr=1)
    m.smoke(mist, (190, 170, 230), 0.07, 0.3, 1.0)
    return m


@model
def charging_station():
    """Charging Station (Epic): a friendly charging pillar. A diamond-plate base with hazard stripes,
    a rounded teal pillar with a steel face plate, a screen with a happy LED face, a battery gauge, a
    glowing bolt, a cap with a light ring and an antenna, and two cables looping into plug holsters."""
    m = SModel("charging_station", kind="gadget")
    P = PAL["Robo"]
    ST_ = P["main"]
    TL = P["second"]
    OR = P["accent"]
    DK = P["dark"]
    LT = P["light"]
    CY = (70, 226, 255)
    m.rbox("Base", (2.2, 0.22, 1.7), (0, 0.11, 0.05), (72, 76, 86), 0.14, "DiamondPlate")
    for k in range(7):
        m.blk("Hazard", (0.26, 0.04, 0.16), (-0.84 + k * 0.28, 0.235, -0.66), YELLOW if k % 2 == 0 else (30, 30, 34))
    for s in (-1, 1):
        m.cyl("Bumper", 0.3, 0.16, (s * 0.98, 0.3, -0.66), (36, 38, 44), "y", "Rubber")
    # the pillar and its face plate
    m.rbox("Pillar", (1.0, 2.2, 0.8), (0, 1.32, 0.15), TL, 0.24, axis="z", refl=0.1)
    m.rbox("Panel", (0.84, 1.96, 0.06), (0, 1.3, -0.26), ST_, 0.18, "Metal", axis="z")
    for (x, y) in ((-0.34, 2.18), (0.34, 2.18), (-0.34, 0.42), (0.34, 0.42)):
        m.ball("Rivet", 0.07, (x, y, -0.3), LT, "Metal")
    # the cap with a light ring and an antenna
    m.ell("Cap", (1.18, 0.5, 0.98), (0, 2.46, 0.15), LT, refl=0.15)
    ring = m.ell("CapGlow", (1.08, 0.1, 0.88), (0, 2.34, 0.15), CY, "Neon")
    m.rod("Antenna", V(0.28, 2.6, 0.3), V(0.36, 3.08, 0.34), 0.05, (200, 204, 214), "Metal")
    m.ball("AntennaTip", 0.14, (0.36, 3.12, 0.34), OR, "Neon")
    # the screen with a happy LED face
    sc = V(0, 1.86, -0.3)
    m.rbox("ScreenFrame", (0.74, 0.56, 0.05), sc, DK, 0.1, axis="z")
    scr = m.blk("Screen", (0.62, 0.44, 0.04), sc + V(0, 0, -0.03), (22, 36, 52))
    for s in (-1, 1):
        m.ell("ScreenEye", (0.12, 0.16, 0.02), sc + V(s * 0.14, 0.06, -0.055), CY, "Neon")
        m.ell("ScreenCheek", (0.08, 0.04, 0.02), sc + V(s * 0.22, -0.06, -0.055), (255, 140, 180), "Neon")
    pts = [sc + V(-0.12, -0.07, -0.055), sc + V(-0.06, -0.12, -0.055), sc + V(0.06, -0.12, -0.055), sc + V(0.12, -0.07, -0.055)]
    for i in range(3):
        m.rod("ScreenMouth", pts[i], pts[i + 1], 0.035, CY, "Neon", shape="B")
    # the battery gauge and a big glowing bolt
    bc = V(0, 1.3, -0.3)
    m.rbox("Battery", (0.5, 0.26, 0.04), bc, DK, 0.05, axis="z")
    m.blk("Battery", (0.06, 0.12, 0.04), bc + V(0.28, 0, 0), DK)
    for k in range(3):
        m.blk("BatteryBar", (0.11, 0.18, 0.03), bc + V(-0.15 + k * 0.14, 0, -0.03), (90, 255, 120), "Neon")
    m.bolt("Bolt", V(0.02, 1.05, -0.32), 0.52, color=(255, 214, 50))
    # vents on the sides and a warning sticker
    for s in (-1, 1):
        for k in range(3):
            m.blk("Vent", (0.03, 0.05, 0.4), (s * 0.505, 0.9 + k * 0.12, 0.15), DK)
    m.blk("Sticker", (0.2, 0.2, 0.02), (0.24, 0.62, -0.3), YELLOW, R=Rz(45))
    m.text("Sticker", "!", V(0.24, 0.62, -0.32), 0.14, INK, facing="front")
    # two cables looping down and back up into holsters on the sides
    for s in (-1, 1):
        pts = [V(s * 0.46, 0.62, 0.3), V(s * 0.78, 0.34, 0.12), V(s * 0.92, 0.5, -0.12), V(s * 0.8, 0.96, -0.02), V(s * 0.66, 1.1, 0.1)]
        m.flow("Cable", pts, [0.07] * 5, (34, 36, 42))
        m.blk("Holster", (0.1, 0.36, 0.34), (s * 0.55, 1.36, 0.12), DK, "Metal")
        pc = V(s * 0.66, 1.3, 0.12)
        m.rbox("Plug", (0.24, 0.34, 0.24), pc, OR, 0.07, axis="y")
        m.blk("Plug", (0.26, 0.08, 0.26), pc + V(0, -0.14, 0), (40, 42, 48), "Rubber")
        for k in (-1, 1):
            m.blk("PlugPin", (0.04, 0.14, 0.04), pc + V(k * 0.05, 0.22, 0), CHROME, "Metal")
    # the back: a bolted service hatch, a vent grille and the power line going into the ground
    m.rbox("Hatch", (0.64, 0.9, 0.05), (0, 1.5, 0.56), ST_, 0.1, "Metal", axis="z")
    for (x, y) in ((-0.25, 1.88), (0.25, 1.88), (-0.25, 1.12), (0.25, 1.12)):
        m.ball("Rivet", 0.06, (x, y, 0.59), LT, "Metal")
    for k in range(4):
        m.blk("Vent", (0.44, 0.04, 0.03), (0, 1.32 + k * 0.1, 0.595), DK)
    m.blk("Sticker", (0.3, 0.14, 0.02), (0, 1.74, 0.595), OR)
    m.flow("PowerLine", [V(0, 0.6, 0.5), V(0, 0.36, 0.7), V(0, 0.26, 0.82)], [0.09, 0.09, 0.09], (34, 36, 42))
    m.cyl("PowerLine", 0.06, 0.3, (0, 0.24, 0.84), DK, "y", "Metal")
    m.light(scr, CY, 1.2, 6)
    m.sparkles(ring, (120, 230, 255))
    return m


@model
def scrap_catapult():
    """Scrap Catapult (Epic): a junkyard catapult on four mismatched wheels (a cart wheel, a tyre, a
    cog and a hubcap). Rails and an A-frame patched with tin, a pillow on the crossbar, a throwing
    arm with a paint bucket full of junk, a winch with a crank and rope, and a pennant."""
    m = SModel("scrap_catapult", kind="gadget")
    J = PAL["Junk"]
    RU = J["main"]
    TJ = J["second"]
    YJ = J["accent"]
    TIN = J["tin"]
    DJ = J["dark"]
    RB = J["rubber"]
    m.ell("Base", (2.5, 0.12, 2.9), (0, 0.0, 0.05), DIRT)
    # the chassis: two rails and two cross beams
    for s in (-1, 1):
        m.rbox("Rail", (0.24, 0.24, 2.3), (s * 0.68, 0.52, 0.05), WOOD, 0.06, "Wood", axis="z")
    for z in (-0.95, 1.0):
        m.rbox("CrossBeam", (1.6, 0.2, 0.22), (0, 0.52, z), WOOD_D, 0.06, "Wood", axis="x")
    m.plate("Patch", V(0.68, 0.52, -0.5), (0.32, 0.22, 0.03), TIN, normal=(1, 0, 0), rivets=IRON)
    m.plate("Patch", V(-0.68, 0.54, 0.6), (0.34, 0.22, 0.03), (150, 96, 64), normal=(-1, 0, 0), rivets=IRON)
    # four mismatched wheels
    for (x, z) in ((-0.9, -0.78), (0.9, -0.78), (-0.9, 0.84), (0.9, 0.84)):
        m.cyl("Axle", 0.3, 0.1, (x * 0.88, 0.42, z), TIN, "x", "Metal")
    cw = V(-0.92, 0.42, -0.78)
    disc(m, "Wheel", cw, V(1, 0, 0), 0.82, 0.1, (90, 64, 44), "Wood")
    disc(m, "Wheel", cw + V(-0.02, 0, 0), V(1, 0, 0), 0.66, 0.11, WOOD, "Wood")
    for k in range(4):
        m.blk("WheelSpoke", (0.13, 0.62, 0.08), cw + V(-0.04, 0, 0), WOOD_D, R=Rx(k * 45))
    m.cyl("WheelHub", 0.16, 0.2, cw + V(-0.06, 0, 0), IRON, "x", "Metal")
    tw = V(0.92, 0.42, -0.78)
    disc(m, "Tire", tw, V(1, 0, 0), 0.84, 0.22, RB, "Rubber")
    disc(m, "Tire", tw + V(0.06, 0, 0), V(1, 0, 0), 0.46, 0.14, TIN, "Metal")
    for k in range(5):
        a = math.radians(k * 72)
        m.ball("LugNut", 0.06, tw + V(0.13, math.cos(a) * 0.12, math.sin(a) * 0.12), DJ, "Metal")
    gw = V(-0.92, 0.42, 0.84)
    disc(m, "Cog", gw, V(1, 0, 0), 0.72, 0.12, TIN, "Metal")
    for k in range(10):
        a = math.radians(k * 36)
        m.blk("CogTooth", (0.11, 0.12, 0.13), gw + V(0, math.cos(a) * 0.4, math.sin(a) * 0.4), TIN, "Metal", R=Rx(-k * 36))
    disc(m, "Cog", gw + V(-0.03, 0, 0), V(1, 0, 0), 0.2, 0.12, DJ, "Metal")
    hw = V(0.92, 0.42, 0.84)
    disc(m, "Hubcap", hw, V(1, 0, 0), 0.8, 0.12, TJ)
    disc(m, "Hubcap", hw + V(0.04, 0, 0), V(1, 0, 0), 0.52, 0.08, CHROME, "Metal", refl=0.3)
    star(m, "Hubcap", hw + V(0.09, 0, 0), V(1, 0, 0), 0.28, 0.03, YJ)
    # the A-frame with a pillow on the crossbar
    for s in (-1, 1):
        plank(m, "Upright", V(s * 0.68, 0.6, 0.3), V(s * 0.6, 1.62, -0.2), 0.2, 0.2, WOOD, "Wood")
        plank(m, "Upright", V(s * 0.68, 0.6, -0.72), V(s * 0.6, 1.62, -0.2), 0.2, 0.2, WOOD, "Wood")
    m.rbox("CrossBar", (1.46, 0.22, 0.26), (0, 1.64, -0.2), WOOD_D, 0.06, "Wood", axis="x")
    m.ell("Pillow", (0.8, 0.22, 0.4), (0, 1.8, -0.2), TJ, "Fabric")
    m.ell("Pillow", (0.2, 0.04, 0.16), (0.18, 1.91, -0.24), YJ, "Fabric")
    m.plate("Patch", V(0.0, 1.64, -0.34), (0.34, 0.22, 0.03), TIN, normal=(0, 0, -1), rivets=IRON)
    # the pivot and the long throwing arm, cocked back with the bucket held high
    m.cyl("Pivot", 1.3, 0.16, (0, 0.66, 0.28), TIN, "x", "Metal")
    a0, a1 = V(0, 0.66, 0.28), V(0, 1.98, 1.04)
    plank(m, "ThrowArm", a0 + (a0 - a1) * 0.12, a1, 0.2, 0.2, WOOD_L, "Wood")
    for f in (0.35, 0.7):
        p = a0 + (a1 - a0) * f
        m.add("C", "ArmBand", (0.07, 0.26, 0.26), p, IRON, "Metal", frame_from_x(a1 - a0))
    # the bucket of junk at the end of the arm
    bc = a1 + V(0, 0.12, 0.06)
    m.cyl("Bucket", 0.4, 0.6, bc, (196, 70, 56))
    m.cyl("Bucket", 0.06, 0.64, bc + V(0, 0.18, 0), TIN, "y", "Metal")
    m.rod("BucketHandle", bc + V(-0.3, 0.16, 0), bc + V(0.0, 0.4, -0.1), 0.03, TIN, "Metal")
    m.rod("BucketHandle", bc + V(0.0, 0.4, -0.1), bc + V(0.3, 0.16, 0), 0.03, TIN, "Metal")
    m.cyl("Junk", 0.28, 0.18, bc + V(-0.12, 0.3, 0.06), TJ, "y", "Metal", R=Rz(18))
    m.cyl("Junk", 0.06, 0.3, bc + V(0.12, 0.26, -0.04), YJ, "y", "Metal", R=Rx(60) @ Rz(-20))
    for k in range(3):
        m.cyl("Junk", 0.03, 0.14, bc + V(0.08, 0.22 + k * 0.05, 0.14), TIN, "y", "Metal", R=Rz(15))
    m.ell("Junk", (0.16, 0.14, 0.3), bc + V(-0.02, 0.26, -0.12), (110, 70, 44), R=Ry(30))
    # the winch with its crank, and the rope holding the arm down
    m.cyl("Winch", 1.1, 0.26, (0, 0.72, 1.0), WOOD_D, "x", "Wood")
    for k in range(4):
        m.cyl("Rope", 0.06, 0.3, (-0.2 + k * 0.08, 0.72, 1.0), (214, 192, 140), "x", "Fabric")
    m.rod("Crank", V(0.62, 0.72, 1.0), V(0.62, 0.98, 1.06), 0.06, IRON, "Metal")
    m.rod("Crank", V(0.62, 0.98, 1.06), V(0.8, 0.98, 1.06), 0.06, IRON, "Metal")
    m.ball("Crank", 0.1, (0.84, 0.98, 1.06), (196, 70, 56))
    m.rod("Rope", V(0, 0.84, 0.98), V(0, 1.5, 0.82), 0.04, (214, 192, 140), "Fabric")
    # a pennant on the front upright and scattered bolts
    m.cyl("FlagPole", 0.6, 0.05, (-0.6, 1.98, -0.2), TIN, "y", "Metal")
    m.wedge("Flag", (0.03, 0.26, 0.4), (-0.6, 2.12, -0.41), TJ, R=Ry(180))
    for (x, z) in ((0.4, -1.2), (-0.3, -1.25), (1.12, 0.2)):
        m.cyl("Bolt", 0.05, 0.1, (x, 0.07, z), TIN, "y", "Metal")
    return m


# ------------------------------------------------------------------------------------------------
# Hero figurines (they stand on pedestals beside each player's lanes)
# ------------------------------------------------------------------------------------------------
def front_z(ells, x, y):
    """The front surface (smallest z) at (x, y) of a body made of axis-aligned ellipsoids
    [(center, size), ...]; None if (x, y) is outside all of them."""
    best = None
    for c, sz in ells:
        q = 1 - ((x - c[0]) / (sz[0] / 2)) ** 2 - ((y - c[1]) / (sz[1] / 2)) ** 2
        if q > 0:
            z = c[2] - sz[2] / 2 * math.sqrt(q)
            best = z if best is None else min(best, z)
    return best


@model
def hero_bonk():
    """Bonk (hero): a cheeky frog wizard. A wide frog head with bulging eyes (one brow cocked), a
    smirk and a little white beard, a floppy purple wizard hat, a flared starry robe with a gold hem
    and rope belt, bell sleeves, a gnarled staff with a glowing orb in its curl, and webbed feet."""
    m = SModel("hero_bonk", kind="hero")
    FROG = (112, 196, 84)
    FROG_D = (80, 150, 62)
    ROBE = (114, 64, 188)
    ROBE_D = (84, 44, 144)
    GD = GOLD
    # webbed feet poking out under the robe
    for s in (-1, 1):
        fc = V(s * 0.34, 0.08, -0.56)
        m.ell("Foot", (0.44, 0.16, 0.5), fc, FROG)
        for k in (-1, 0, 1):
            m.ball("Toe", 0.15, fc + V(k * 0.15 + s * 0.02, 0.0, -0.25), FROG)
    # the robe: a gold hem, a flared bell, a chest
    robe = [(V(0, 0.52, 0.02), V(1.5, 0.94, 1.28)), (V(0, 1.35, 0.02), V(1.2, 1.32, 1.06)), (V(0, 1.86, 0.02), V(1.1, 0.8, 0.92))]
    m.cyl("RobeHem", 0.26, 1.52, (0, 0.13, 0.02), GD, "y", "Fabric")
    m.cyl("RobeHem", 0.12, 1.5, (0, 0.3, 0.02), ROBE_D, "y", "Fabric")
    for c, sz in robe:
        m.ell("Robe", sz, c, ROBE, "Fabric")
    # a gold band down the front with star buttons
    ys = [1.95, 1.6, 1.25, 0.9, 0.55, 0.3]
    pts = [V(0, y, front_z(robe, 0, y) - 0.01) for y in ys]
    for i in range(len(pts) - 1):
        m.seg("RobeBand", pts[i], pts[i + 1], 0.07, GD, "Fabric", ext=0.03, r2=0.04)
    for y in (1.62, 1.12):
        star(m, "RobeStar", V(0, y, front_z(robe, 0, y) - 0.05), V(0, 0.1, -1), 0.16, 0.05, (255, 236, 140))
    # stars and a moon on the skirt
    for (x, y, r) in ((-0.42, 0.78, 0.2), (0.4, 0.5, 0.16), (0.46, 1.08, 0.14)):
        z = front_z(robe, x, y)
        star(m, "RobeStar", V(x, y, z - 0.01), V(x * 0.9, 0.1, z), r, 0.04, GD)
    zm = front_z(robe, -0.36, 1.3)
    m.ell("Moon", (0.2, 0.2, 0.04), V(-0.36, 1.3, zm - 0.01), (255, 240, 170), R=frame_normal(V(-0.4, 0, zm)))
    m.ell("Moon", (0.16, 0.16, 0.05), V(-0.31, 1.33, zm - 0.02), ROBE, R=frame_normal(V(-0.4, 0, zm)))
    # a rope belt with a knot and a pouch
    for k in range(14):
        a = 2 * math.pi * k / 14
        p = V(math.sin(a) * 0.6, 1.5, 0.02 - math.cos(a) * 0.52)
        m.ell("Belt", (0.24, 0.1, 0.1), p, (236, 196, 90), "Fabric", R=Ry(-math.degrees(a)))
    m.ball("BeltKnot", 0.16, (0.2, 1.48, -0.52), (236, 196, 90), "Fabric")
    m.seg("BeltKnot", V(0.2, 1.44, -0.53), V(0.26, 1.18, -0.57), 0.04, (236, 196, 90), "Fabric")
    m.ell("Pouch", (0.26, 0.3, 0.16), (-0.42, 1.3, -0.44), (150, 98, 60), "Leather")
    m.ell("PouchVial", (0.1, 0.12, 0.1), (-0.44, 1.5, -0.44), (120, 240, 200), "Neon")
    # the head: wide and froggy, with eye bumps, spots, nostrils, cheeks and a cheeky smirk
    hc, hs = V(0, 2.55, -0.04), V(1.5, 0.98, 1.26)
    m.ell("Head", hs, hc, FROG)
    m.ell("Chin", (1.1, 0.4, 0.9), hc + V(0, -0.3, -0.08), (206, 236, 160))
    cheeky_l = dict(open=1.0, lid=0, brow=-22, lift=0.42, mouth="smirk", curve=0.26, look=(0.1, 0.0))
    cheeky_r = dict(open=0.62, lid=8, brow=12, lift=0.08, mouth="smirk", curve=0.26, look=(0.1, 0.0))
    for s in (-1, 1):
        bc = V(s * 0.4, 2.98, -0.16)
        m.ball("EyeBump", 0.62, bc, FROG)
        m.eye(bc + V(s * 0.06, 0.0, -0.27), V(s * 0.22, 0.08, -1), 0.42, 0.44, FROG, cheeky_l if s > 0 else cheeky_r,
              side=s, iris=(232, 176, 40), brow=FROG_D, brow_k=0.9)
        m.ell("Cheek", (0.2, 0.1, 0.06), (s * 0.5, 2.42, -0.6), (255, 150, 160))
        m.ell("Nostril", (0.05, 0.04, 0.03), (s * 0.08, 2.66, -0.66), (50, 90, 40))
    for (x, y, z, d) in ((-0.55, 2.86, 0.3, 0.16), (0.6, 2.7, 0.4, 0.14), (0.2, 2.98, 0.42, 0.12), (-0.66, 2.5, -0.1, 0.12)):
        m.ell("Spot", (d, d * 0.5, d), (x, y, z), FROG_D)
    m.mouth(V(0.02, 2.38, -0.64), V(0, -0.1, -1), 0.8, "smug", color=(60, 100, 44), d=0.06, side_bias=1)
    # a little white beard under the chin
    BW = (244, 244, 248)
    m.ell("Beard", (0.76, 0.3, 0.32), V(0, 2.14, -0.52), BW, "Fabric")
    for s in (-1, 1):
        m.ell("Beard", (0.3, 0.3, 0.26), V(s * 0.24, 2.02, -0.55), BW, "Fabric")
    m.ell("Beard", (0.42, 0.32, 0.26), V(0, 1.94, -0.6), BW, "Fabric")
    m.seg("Beard", V(0, 1.9, -0.62), V(0.08, 1.66, -0.66), 0.11, BW, "Fabric", bulge=0.3)
    m.ball("Beard", 0.1, (0.1, 1.64, -0.66), BW, "Fabric")
    # the floppy wizard hat sitting behind the eye bumps
    hb = V(0, 3.04, 0.2)
    m.ell("HatBrim", (0.92, 0.1, 0.86), hb, ROBE)
    m.cyl("HatBand", 0.14, 0.62, hb + V(0, 0.08, 0), GD)
    star(m, "HatStar", hb + V(0, 0.1, -0.32), V(0, 0.1, -1), 0.16, 0.04, (255, 236, 140))
    m.seg("Hat", hb + V(0, 0.04, 0), hb + V(0.03, 0.62, 0.02), 0.3, ROBE, bulge=0.12)
    m.seg("Hat", hb + V(0.02, 0.48, 0.02), hb + V(0.16, 0.92, 0.06), 0.16, ROBE, bulge=0.2)
    m.seg("Hat", hb + V(0.13, 0.86, 0.06), hb + V(0.42, 1.0, 0.08), 0.08, ROBE, bulge=0.25)
    m.ball("HatTip", 0.14, hb + V(0.44, 1.0, 0.08), GD, "Neon")
    # bell sleeves with gold cuffs and froggy hands
    for s in (-1, 1):
        sh = V(s * 0.6, 1.98, 0.02)
        if s > 0:
            el, wr = V(0.92, 1.62, -0.14), V(0.96, 1.52, -0.44)
        else:
            el, wr = V(-0.94, 1.64, -0.18), V(-0.9, 1.94, -0.48)
        m.ball("Shoulder", 0.36, sh, ROBE, "Fabric")
        m.seg("UpperArm", sh, el, 0.17, ROBE, "Fabric", bulge=0.45)
        m.ball("Elbow", 0.32, el, ROBE, "Fabric")
        d = norm(wr - el)
        m.seg("Sleeve", el, wr, 0.2, ROBE, "Fabric", bulge=0.75)
        m.seg("Cuff", wr - d * 0.06, wr + d * 0.04, 0.22, GD, "Fabric", shape="C")
        hcn = wr + d * 0.16
        m.glove(hcn, 0.13, FROG, s, fist=(s > 0), fingers=3, forward=(d[0], 0, d[2]) if s > 0 else (0, 0, -1))
        if s < 0:
            for k in (-1, 0, 1):
                m.ball("Finger", 0.09, hcn + V(k * 0.07, 0.14, -0.04), FROG)
    # a tiny spell spark over the raised hand
    spark = m.ball("Spark", 0.1, (-0.88, 2.3, -0.56), (255, 236, 140), "Neon")
    star(m, "Spark", V(-0.88, 2.3, -0.56), V(0, 0, -1), 0.14, 0.03, (255, 236, 140), "Neon")
    m.sparkles(spark, (255, 236, 160))
    # the gnarled staff with a curl holding a glowing orb
    sp = [V(0.98, 0.06, -0.5), V(1.0, 0.9, -0.52), V(0.97, 1.8, -0.5), V(1.0, 2.7, -0.52), V(1.02, 3.1, -0.5)]
    for i in range(len(sp) - 1):
        m.seg("Staff", sp[i], sp[i + 1], 0.06, (126, 84, 48), "Wood", ext=0.03)
    m.ell("StaffKnot", (0.16, 0.12, 0.16), sp[1], (106, 68, 38), "Wood")
    m.horn("Staff", sp[-1], sp[-1] + V(-0.24, 0.3, 0.0), 0.06, (126, 84, 48), curve=(-0.04, 0.08, 0), n=2)
    m.horn("Staff", sp[-1], sp[-1] + V(0.22, 0.32, 0.0), 0.06, (126, 84, 48), curve=(0.06, 0.06, 0), n=2)
    orb = m.ball("Orb", 0.34, sp[-1] + V(0.0, 0.3, 0.0), (120, 226, 255), "Neon")
    m.sparkles(orb, (170, 236, 255))
    m.light(orb, (120, 220, 255), 1.2, 7)
    return m


@model
def hero_granny_bolt():
    """Granny Bolt (hero): a fearless granny athlete. Silver hair in a big bun with a pencil through
    it, a red sweatband, big round gold glasses over determined eyes, a confident smirk, pearl
    earrings, a blue tracksuit with lightning bolts and white stripes, chunky sneakers and a purple
    bowling ball held ready, crackling."""
    m = SModel("hero_granny_bolt", kind="hero")
    SKIN = (246, 208, 178)
    SUIT = (62, 104, 222)
    SUIT_D = (44, 78, 178)
    BY_ = (255, 214, 60)
    HAIR = (232, 232, 242)
    RD = (236, 70, 70)
    # chunky sneakers and tracksuit legs with white stripes
    for s in (-1, 1):
        hip, knee, ank = V(s * 0.24, 1.3, 0.04), V(s * 0.26, 0.8, -0.04), V(s * 0.27, 0.36, 0.02)
        m.leg(hip, knee, ank, 0.21, 0.17, 0.16, SUIT, knee_color=SUIT)
        m.seg("Stripe", hip + V(s * 0.19, -0.04, 0), knee + V(s * 0.16, 0, 0), 0.035, WHITE, bulge=0.5)
        m.seg("Stripe", knee + V(s * 0.16, 0, 0), ank + V(s * 0.14, 0.04, 0), 0.03, WHITE, bulge=0.5)
        m.boot((ank[0], ank[2]), 0.44, 0.7, WHITE, sole=RD, toe=(250, 250, 250), name="Shoe")
        for k in range(2):
            m.blk("Laces", (0.2, 0.03, 0.05), (ank[0], 0.36 - k * 0.06, ank[2] - 0.2 - k * 0.08), RD, R=Rx(-30))
    # the tracksuit jacket: a white hem band, a zip, lightning bolts and a rolled collar
    body = [(V(0, 1.5, 0.0), V(1.0, 0.74, 0.82)), (V(0, 1.92, 0.0), V(1.08, 1.06, 0.86))]
    for c, sz in body:
        m.ell("Body", sz, c, SUIT, "Fabric")
    m.ell("Body", (1.02, 0.14, 0.84), (0, 1.3, 0.0), WHITE, "Fabric")
    pts = [V(0, y, front_z(body, 0, y) - 0.01) for y in (2.36, 2.0, 1.66, 1.36)]
    for i in range(3):
        m.seg("Zip", pts[i], pts[i + 1], 0.03, (200, 206, 216), "Metal", ext=0.02)
    for s in (-1, 1):
        z = front_z(body, s * 0.28, 1.92)
        m.bolt("BoltLogo", V(s * 0.28, 2.18, z - 0.02), 0.5, color=BY_, R=Ry(-s * 18) @ Rz(-s * 8))
    m.ell("Collar", (0.66, 0.2, 0.6), (0, 2.42, 0.0), WHITE, "Fabric")
    # arms holding the bowling ball out front, red sweatbands
    hands = m.arms2(2.22, 0.5, SUIT, 0.15, 0.13, 0.13, 0.14, SKIN,
                    {1: (V(0.6, 1.86, -0.24), V(0.46, 1.78, -0.6), False),
                     -1: (V(-0.6, 1.86, -0.24), V(-0.46, 1.78, -0.6), False)}, cuff=RD)
    bc = V(0, 1.78, -0.86)
    m.ball("BowlingBall", 0.78, bc, (96, 38, 150), refl=0.3)
    m.ell("BallSwirl", (0.5, 0.08, 0.04), bc + V(-0.08, 0.16, -0.38), (150, 90, 210), R=Rz(-24))
    m.ell("BallSwirl", (0.3, 0.06, 0.04), bc + V(0.12, -0.14, -0.37), (150, 90, 210), R=Rz(18))
    for (x, y) in ((-0.1, 0.2), (0.1, 0.2), (0.0, 0.02)):
        p, n = (bc + norm(V(x, y + 0.12, -0.39)) * 0.39), norm(V(x, y + 0.12, -0.39))
        disc(m, "FingerHole", p, n, 0.09, 0.03, (24, 12, 36))
    spark = m.bolt("Spark", V(0.42, 2.26, -1.0), 0.32, color=(255, 236, 120), R=Rz(-20))
    m.sparkles(spark, (255, 230, 120))
    # the head: round, rosy, determined
    hc, hs = V(0, 2.82, -0.02), V(0.98, 0.94, 0.9)
    m.ell("Head", hs, hc, SKIN)
    fierce = dict(open=0.8, lid=12, brow=20, lift=0.1, mouth="smirk", curve=0.22, look=(0, 0.02))
    m.eyes_on(hc, hs, I3, 22, 4, 0.2, 0.22, SKIN, fierce, iris=(80, 130, 220), brow=(200, 200, 212), brow_k=1.1)
    for s in (-1, 1):
        # big round gold glasses
        gc = V(s * 0.19, 2.85, -0.47)
        torus(m, "Glasses", gc, 0.14, 0.025, (214, 170, 60), n=8, normal=(s * 0.15, 0, -1))
        disc(m, "GlassesLens", gc + V(0, 0, -0.005), V(s * 0.15, 0, -1), 0.26, 0.02, (210, 236, 255), "Glass", tr=0.7)
        m.ear(hc + V(s * 0.46, -0.02, 0.02), hc + V(s * 0.56, 0.06, 0.06), 0.14, SKIN)
        m.ball("Earring", 0.08, hc + V(s * 0.5, -0.16, -0.0), (250, 248, 240), refl=0.2)
        m.ell("Cheek", (0.14, 0.08, 0.04), hc + V(s * 0.26, -0.12, -0.38), (250, 150, 150))
        m.seg("Glasses", gc + V(s * 0.14, 0.02, 0.0), gc + V(s * 0.3, 0.04, 0.32), 0.015, (214, 170, 60))
    m.seg("Glasses", V(-0.06, 2.87, -0.48), V(0.06, 2.87, -0.48), 0.02, (214, 170, 60))
    m.ball("Nose", 0.13, (0, 2.74, -0.47), shade(SKIN, 0.94))
    m.mouth(V(0.02, 2.58, -0.42), V(0, -0.15, -1), 0.24, fierce, color=(150, 60, 60), d=0.035, side_bias=1)
    # silver hair, side curls, a big bun with a pencil, and a red sweatband
    m.ell("Hair", (1.04, 0.6, 0.94), (0, 3.06, 0.08), HAIR)
    for s in (-1, 1):
        m.ball("Hair", 0.3, (s * 0.44, 2.86, 0.12), HAIR)
        m.ball("Hair", 0.24, (s * 0.38, 3.08, -0.18), HAIR)
    m.ball("Bun", 0.6, (0, 3.34, 0.22), HAIR)
    torus(m, "Bun", V(0, 3.16, 0.22), 0.27, 0.06, (206, 206, 220), n=10, normal=(0, 1, 0))
    m.ell("Bun", (0.2, 0.12, 0.06), (-0.12, 3.46, -0.06), (250, 250, 255))
    m.seg("BunPin", V(-0.38, 3.24, 0.3), V(0.36, 3.5, 0.12), 0.035, BY_)
    m.ball("BunPin", 0.07, (-0.39, 3.23, 0.3), (250, 150, 170))
    m.ell("Headband", (1.0, 0.12, 0.9), (0, 3.04, -0.02), RD, "Fabric", R=Rx(-14))
    return m


# ------------------------------------------------------------------------------------------------
# The bot opponent: sits in the far chair (seat top at y = 2, hips at 2.45), facing -Z like
# everything else; the server turns it to face the player and leans it about its hips.
# ------------------------------------------------------------------------------------------------
@model
def bot_bonkers():
    """Bot Bonkers (bot opponent): a big playful-menace robot. Glossy white shell with orange plates,
    a dark screen face with glowing eyes, mischievous LED brows and a jagged grin, ear discs, an
    orange crest and an antenna light, a glowing chest core, big shoulders, chunky arms resting
    on the table and thick legs folded on the chair."""
    m = SModel("bot_bonkers", kind="avatar")
    SH = (240, 243, 248)
    SH_D = (206, 212, 224)
    OR = (255, 142, 52)
    OR_D = (222, 104, 32)
    DK = (64, 68, 82)
    DK2 = (34, 36, 46)
    CY = (96, 232, 255)
    # hips on the seat
    m.rbox("Hips", (2.2, 0.82, 1.8), (0, 2.43, 0.25), DK, 0.3, "Metal", axis="x")
    # legs folded over the seat edge: thighs, knees, shins with an orange band, big feet
    for s in (-1, 1):
        x = s * 0.64
        m.ball("Hip", 0.8, (x, 2.42, -0.3), OR)
        m.seg("Thigh", (x, 2.42, -0.3), (x, 2.38, -1.42), 0.38, SH, bulge=0.45, ext=0.1, refl=0.1)
        m.ball("Knee", 0.7, (x, 2.36, -1.46), OR)
        m.seg("Shin", (x, 2.36, -1.46), (x, 0.54, -1.58), 0.32, SH, bulge=0.4, refl=0.1)
        m.ell("ShinBand", (0.7, 0.16, 0.7), (x, 1.62, -1.5), OR)
        m.ball("Ankle", 0.46, (x, 0.52, -1.58), DK, "Metal")
        m.rbox("Foot", (0.8, 0.4, 1.14), (x, 0.2, -1.74), DK, 0.15, "Metal", axis="x")
        m.ell("Toe", (0.76, 0.36, 0.52), (x, 0.24, -2.2), OR)
    # the torso: a glossy shell, a dark waist, an orange chest plate with a glowing core
    TC = V(0, 4.18, 0.3)
    m.ell("Torso", (2.9, 2.72, 2.1), TC, SH, refl=0.12)
    m.ell("Waist", (2.3, 0.62, 1.72), (0, 3.0, 0.3), DK, "Metal")
    m.ell("Seam", (2.92, 0.04, 2.12), TC + V(0, -0.56, 0), SH_D)
    m.ell("ChestPlate", (1.76, 1.36, 0.6), TC + V(0, 0.12, -0.78), OR, refl=0.1)
    cc = TC + V(0, 0.14, -1.08)
    disc(m, "Core", cc + V(0, 0, 0.02), V(0, 0, -1), 0.66, 0.1, SH_D, "Metal")
    core = disc(m, "Core", cc, V(0, 0, -1), 0.46, 0.1, CY, "Neon")
    m.light(core, CY, 1.2, 8)
    for s in (-1, 1):
        for k in range(3):
            m.blk("Vent", (0.06, 0.08, 0.5), (s * 1.42, 4.0 + k * 0.16, 0.3), DK)
    # shoulders, chunky arms and big mitten hands resting on the table
    for s in (-1, 1):
        sh = V(s * 1.5, 4.88, 0.3)
        m.ball("Shoulder", 1.0, sh, OR)
        m.ell("Pauldron", (1.04, 0.46, 1.06), sh + V(s * 0.06, 0.3, 0), OR_D)
        el = V(s * 1.82, 3.92, -0.8)
        wr = V(s * 1.1, 4.0, -2.08)
        m.seg("UpperArm", sh, el, 0.3, SH, bulge=0.45, refl=0.1)
        m.ball("Elbow", 0.58, el, DK, "Metal")
        m.seg("Forearm", el, wr, 0.32, SH, bulge=0.62, refl=0.1)
        d = norm(wr - el)
        m.seg("Cuff", wr - d * 0.2, wr + d * 0.02, 0.38, OR, shape="C")
        m.glove(wr + d * 0.3, 0.34, OR, s, fingers=3, forward=(d[0], 0, d[2]))
    # the neck: a dark accordion
    for k in range(3):
        m.cyl("Neck", 0.14, 0.7 - k * 0.04, (0, 5.5 + k * 0.14, 0.3), DK, "y", "Metal")
    # the head: a glossy shell, a bezel and a dark screen face
    HC = V(0, 6.72, 0.3)
    m.ell("Head", (2.5, 1.96, 2.06), HC, SH, refl=0.12)
    m.ell("Bezel", (2.0, 1.36, 0.42), HC + V(0, -0.02, -0.74), SH_D)
    scr_c, scr_s = HC + V(0, -0.02, -0.78), V(1.86, 1.22, 0.5)
    m.ell("Screen", scr_s, scr_c, DK2)

    def on_screen(x, y, out=0.01):
        q = max(1 - ((x - scr_c[0]) / (scr_s[0] / 2)) ** 2 - ((y - scr_c[1]) / (scr_s[1] / 2)) ** 2, 0.0)
        return V(x, y, scr_c[2] - scr_s[2] / 2 * math.sqrt(q) - out)
    # glowing eyes with glints, mischievous brows and a jagged grin
    for s in (-1, 1):
        ec = on_screen(s * 0.4, 6.82)
        eye = m.ell("Eye", (0.36, 0.42, 0.06), ec, CY, "Neon")
        m.ell("Pupil", (0.14, 0.18, 0.03), ec + V(-s * 0.05 + 0.03, -0.03, -0.03), (20, 60, 90), "Neon")
        m.ell("Glint", (0.08, 0.08, 0.02), ec + V(-0.08, 0.1, -0.04), WHITE, "Neon")
        b0, b1 = on_screen(s * 0.18, 7.04, 0.02), on_screen(s * 0.62, 7.18, 0.02)
        m.seg("Brow", b0, b1, 0.05, CY, "Neon", shape="B", ext=0.03)
    gp = [on_screen(x, y, 0.02) for (x, y) in ((-0.5, 6.5), (-0.34, 6.36), (-0.18, 6.46), (0.0, 6.32), (0.18, 6.46), (0.34, 6.36), (0.5, 6.5))]
    for i in range(len(gp) - 1):
        m.seg("Mouth", gp[i], gp[i + 1], 0.04, CY, "Neon", shape="B", ext=0.03)
    for s in (-1, 1):
        m.ell("Cheek", (0.16, 0.08, 0.03), on_screen(s * 0.66, 6.5, 0.02), (255, 120, 170), "Neon")
    # ear discs, an orange crest and an antenna with a light
    for s in (-1, 1):
        m.cyl("Ear", 0.3, 0.8, (s * 1.24, 6.72, 0.3), OR, "x")
        m.cyl("Ear", 0.32, 0.46, (s * 1.26, 6.72, 0.3), DK, "x", "Metal")
        m.ball("EarNub", 0.2, (s * 1.44, 6.72, 0.3), OR)
    for (z, h, d) in ((-0.3, 0.42, 0.5), (0.18, 0.5, 0.56), (0.66, 0.38, 0.48)):
        m.ell("Crest", (0.16, h, d), (0, 7.62 + h * 0.18, 0.3 + z), OR)
    m.rod("Antenna", V(0.6, 7.5, 0.4), V(0.82, 8.24, 0.46), 0.08, (184, 188, 198), "Metal")
    tip = m.ball("AntennaTip", 0.32, (0.84, 8.38, 0.46), (255, 80, 80), "Neon")
    m.light(tip, (255, 120, 120), 0.8, 5)
    return m
