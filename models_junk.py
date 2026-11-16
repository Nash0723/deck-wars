# Junk family: rusty, dented, patched-together junk with a lot of heart.
# Palette: rust orange (main), patina teal (secondary), hazard yellow (accent).
# Materials: corroded metal, diamond plate, rubber, worn fabric.
import math
import random
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal, frame_from_x
from stylekit import SModel, PAL, V, norm, on_ell_R, INK, GOLD, SILVER

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


P = PAL["Junk"]
RUST = P["main"]
TEAL = P["second"]
HAZ = P["accent"]
TIN = P["tin"]
DARK = P["dark"]
RUBBER = P["rubber"]
RUST_D = (128, 62, 34)
RUST_L = (214, 130, 72)
TEAL_L = (116, 170, 158)
TEAL_D = (50, 90, 84)
CHROME = (208, 214, 222)
WOOD = (156, 96, 54)
WOOD_D = (112, 66, 38)
COPPER = (206, 126, 74)
BRASS = (222, 176, 80)
CONCRETE = (156, 154, 148)

# moods only this family uses
PLUCKY = dict(open=1.0, lid=0, brow=8, lift=0.2, mouth="open", curve=0.25)
POMPOUS = dict(open=0.5, lid=-8, brow=-14, lift=0.36, mouth="smirk", curve=0.18)
STOIC = dict(open=0.62, lid=6, brow=10, lift=0.06, mouth="flat", curve=0.0)


def cpt(r, a, y, cx=0.0, cz=0.0, out=0.0):
    """Point on an upright cylinder of radius r around (cx, cz); a = 270 is the front (-z)."""
    t = math.radians(a)
    return V(cx + math.cos(t) * (r + out), y, cz + math.sin(t) * (r + out))


def cn(a):
    t = math.radians(a)
    return V(math.cos(t), 0, math.sin(t))


def tang(a):
    t = math.radians(a)
    return V(-math.sin(t), 0, math.cos(t))


def eyes_cyl(m, r, y, da, w, h, skin, mood, cx=0.0, cz=0.0, **kw):
    pts = []
    for s in (-1, 1):
        a = 270 + s * da
        p = cpt(r, a, y, cx, cz)
        m.eye(p, cn(a), w, h, skin, mood, side=s, **kw)
        pts.append(p)
    return pts


def ell_front_at(c, size, X, Y, R=I3):
    """Surface point (and normal) on the front (-z) of an ellipsoid at local offsets X, Y."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    u, v = X / hx, Y / hy
    w = -math.sqrt(max(1 - u * u - v * v, 0.02))
    return on_ell_R(c, size, R, np.array(R, float) @ V(X, Y, hz * w))


def patch(m, name, p, n, size, color, spin=0.0, mat="SmoothPlastic"):
    """A flat patch lying on a surface (rust, dents, stickers, tears)."""
    m.ell(name, size, p, color, mat, R=frame_normal(n, spin))


def hexnut(m, name, c, axis, r, t, color, mat="Metal"):
    """A hex nut: three crossed blocks make a six-sided prism along `axis`."""
    F = frame_from_x(axis)
    for k in range(3):
        m.blk(name, (t, r * 1.732, r), c, color, mat, R=F @ Rx(k * 60))


def wire(m, a, b, r, color, name="Wire", mat="Metal"):
    m.seg(name, a, b, r, color, mat, shape="C", ext=r * 0.9)


def lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------------------------------------
@model
def tin_can_tom():
    """Common. A dented tin can with its peeled-open lid worn as a jaunty hat, a half-torn teal label
    with a yellow stripe, short can legs in rust boots and threaded-bolt arms with hex-nut elbows and
    yellow work gloves. Mood: plucky."""
    m = SModel("tin_can_tom")
    tin = (186, 192, 200)
    tin_d = shade(tin, 0.8)
    r, yb, yt = 0.68, 0.8, 2.32
    yc = (yb + yt) / 2
    m.cyl("Body", yt - yb, 2 * r, V(0, yc, 0), tin, "y", "Metal", refl=0.25)
    for y, d in ((yt - 0.03, 2 * r + 0.1), (yb + 0.04, 2 * r + 0.1), (yb + 0.22, 2 * r + 0.035)):
        m.cyl("Rim", 0.07, d, V(0, y, 0), shade(tin, 0.86), "y", "Metal", refl=0.2)
    # the open top and the peeled lid worn like a jaunty hat, with a pull tab and jagged teeth
    m.cyl("Inside", 0.03, 2 * r - 0.1, V(0, yt + 0.005, 0), (76, 80, 90), "y", "Metal")
    Rl = Rz(-15) @ Rx(-8)
    lc = V(0.1, yt + 0.2, 0.06)
    m.cyl("Hat", 0.05, 2 * r - 0.06, lc, shade(tin, 1.06), "y", "Metal", R=Rl, refl=0.3)
    m.cyl("HatTrim", 0.07, 2 * r - 0.3, lc + Rl @ V(0, 0.01, 0), shade(tin, 0.9), "y", "Metal", R=Rl)
    tab = lc + Rl @ V(0, 0.05, -0.22)
    m.ell("Tab", (0.32, 0.05, 0.22), tab, tin_d, "Metal", R=Rl)
    m.ell("Tab", (0.16, 0.06, 0.1), tab + Rl @ V(0, 0.005, -0.03), (70, 74, 84), R=Rl)
    for a in (205, 240, 300, 335):
        t = math.radians(a)
        q = lc + Rl @ V(math.cos(t) * (r - 0.04), 0, math.sin(t) * (r - 0.04))
        m.blk("HatTrim", (0.1, 0.035, 0.1), q, shade(tin, 1.06), "Metal", R=Rl @ Ry(45 - a))
    # the label: teal with a yellow stripe and a fish logo, torn away on one side
    m.cyl("Label", 0.56, 2 * r + 0.03, V(0, 1.16, 0), TEAL, "y")
    m.cyl("Label", 0.1, 2 * r + 0.04, V(0, 1.32, 0), HAZ, "y")
    lg = cpt(r, 244, 1.08, out=0.025)
    patch(m, "Logo", lg, cn(244), (0.34, 0.18, 0.04), RUST)
    m.blk("Logo", (0.13, 0.13, 0.03), lg + tang(244) * 0.2, RUST, R=frame_normal(cn(244), 45))
    m.ball("Logo", 0.05, lg - tang(244) * 0.09 + V(0, 0.03, 0) + cn(244) * 0.015, WHITE)
    patch(m, "Tear", cpt(r, 306, 1.12, out=0.03), cn(306), (0.46, 0.4, 0.04), tin, spin=10)
    patch(m, "Tear", cpt(r, 318, 1.0, out=0.03), cn(318), (0.3, 0.28, 0.04), tin, spin=-20)
    fq = cpt(r, 332, 1.16, out=0.08)
    fn_ = norm(cn(332) * 0.45 + tang(332) * 0.9)
    m.ell("Flap", (0.3, 0.3, 0.03), fq, (238, 232, 214), R=frame_normal(fn_, 12))
    m.ell("Flap", (0.29, 0.29, 0.025), fq + fn_ * 0.02, TEAL, R=frame_normal(fn_, 12))
    # face: big eager eyes, determined brows, an open grin
    eyes_cyl(m, r, 1.86, 21, 0.4, 0.44, tin, PLUCKY, brow=(62, 64, 74), brow_k=1.0)
    m.mouth(cpt(r, 270, 1.58), V(0, 0, -1), 0.46, PLUCKY, color=(70, 34, 42), skin=tin, kind="open")
    # dents and rust
    patch(m, "Dent", cpt(r, 228, 1.78, out=-0.01), cn(228), (0.32, 0.26, 0.05), shade(tin, 0.78))
    patch(m, "Dent", cpt(r, 230, 1.86, out=0.0), cn(230), (0.24, 0.07, 0.05), shade(tin, 1.12), spin=-8)
    patch(m, "Dent", cpt(r, 60, 1.6, out=-0.01), cn(60), (0.36, 0.26, 0.05), shade(tin, 0.78))
    for (a, y, sz, col) in ((212, 0.92, 0.3, RUST), (250, 2.2, 0.22, RUST_D), (334, 0.9, 0.26, RUST),
                            (100, 1.86, 0.34, RUST), (150, 0.96, 0.28, RUST_D), (20, 2.18, 0.2, RUST)):
        patch(m, "Rust", cpt(r, a, y, out=0.01), cn(a), (sz, sz * 0.62, 0.04), col, spin=a)
    # threaded-bolt arms with hex-nut shoulders and elbows, yellow work gloves
    poses = {1: (V(1.16, 1.56, -0.06), V(1.2, 2.18, -0.18), True),
             -1: (V(-1.14, 1.46, 0.14), V(-0.88, 1.1, -0.16), False)}
    for s in (-1, 1):
        sh = V(s * (r + 0.07), 1.72, 0.02)
        el, wr, fist = poses[s]
        hexnut(m, "Shoulder", sh, V(1, 0, 0), 0.2, 0.14, tin_d)
        m.ball("Shoulder", 0.17, sh + V(s * 0.08, 0, 0), shade(tin, 0.95), "Metal")
        for a_, b_, nm in ((sh, el, "UpperArm"), (el, wr, "Forearm")):
            m.seg(nm, a_, b_, 0.115, shade(tin, 0.94), "Metal", shape="C")
            d = norm(b_ - a_)
            for t in (0.36, 0.64):
                q = lerp(a_, b_, t)
                m.seg("ArmBand", q - d * 0.025, q + d * 0.025, 0.14, tin_d, "Metal", shape="C")
        ax = np.cross(el - sh, wr - el)
        ax = norm(ax) if np.linalg.norm(ax) > 1e-3 else V(0, 0, 1)
        hexnut(m, "Elbow", el, ax, 0.21, 0.17, tin_d)
        d = norm(wr - el)
        m.seg("Cuff", wr - d * 0.06, wr + d * 0.12, 0.17, HAZ, bulge=0.5)
        m.glove(wr + d * 0.28, 0.25, HAZ, s, fist=fist, fingers=3, forward=(d[0], 0, d[2]) if abs(d[1]) < 0.95 else (0, 0, -1))
    # short can legs on a rubber knee, chunky rust boots
    for s in (-1, 1):
        x = s * 0.32
        hip, knee, ank = V(x, 0.86, 0.0), V(x + s * 0.02, 0.56, -0.04), V(x + s * 0.03, 0.26, 0.0)
        m.seg("LegCan", hip, knee, 0.21, tin, "Metal", shape="C", ext=0.02)
        m.seg("LegCan", lerp(hip, knee, 0.15) + V(0, 0, 0), lerp(hip, knee, 0.25), 0.225, tin_d, "Metal", shape="C")
        m.ball("Knee", 0.32, knee, RUBBER, "Rubber")
        m.seg("Shin", knee, ank, 0.18, tin, "Metal", shape="C", ext=0.03)
        m.boot((ank[0], ank[2]), 0.52, 0.74, RUST, sole=RUBBER, toe=RUST_L)
    return m


# ------------------------------------------------------------------------------------------------
@model
def couch_golem():
    """Common. An armchair golem: a plump teal seat cushion belly with button tufting, a tall backrest
    face, rolled armrests that end in big knuckle-walking fists, stubby turned wooden legs, a spring
    popping out of a tear, a lace doily and a lost TV remote. Mood: sleepy gentle giant."""
    m = SModel("couch_golem")
    fab, fab_l, fab_d = TEAL, TEAL_L, TEAL_D
    # stubby turned wooden legs with brass cups
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * 1.08, sz * 0.74 + 0.08
            m.seg("Leg", V(x, 0.66, z), V(x * 1.02, 0.14, z), 0.18, WOOD, "Wood", bulge=0.32)
            m.ell("Leg", (0.4, 0.12, 0.4), V(x, 0.5, z), WOOD_D, "Wood")
            m.ell("Foot", (0.32, 0.16, 0.32), V(x * 1.02, 0.08, z), BRASS, "Metal", refl=0.2)
    # the upholstered base with a wooden front rail and yellow stitching
    m.rbox("Body", (2.92, 0.76, 2.12), V(0, 1.0, 0.08), fab, 0.34, "Fabric")
    m.rbox("Trim", (2.5, 0.16, 0.14), V(0, 0.68, -0.97), WOOD, 0.06, "Wood", axis="x")
    for k in range(7):
        m.blk("Stitch", (0.18, 0.04, 0.04), V(-1.14 + k * 0.38, 1.3, -0.985), HAZ)
    # the seat cushion belly with button tufting
    cc, cs = V(0, 1.46, -0.22), (2.32, 0.58, 1.78)
    m.ell("Cushion", cs, cc, fab_l, "Fabric")
    for X in (-0.62, 0, 0.62):
        p, n = ell_front_at(cc, cs, X, 0.1)
        m.ell("Button", (0.15, 0.15, 0.08), p, HAZ, R=frame_normal(n))
        for sp in (40, -40):
            m.seg("Crease", p + V(-0.2, -0.06, 0.02) if sp > 0 else p + V(0.2, -0.06, 0.02), p, 0.025, fab_d, ext=0.0)
    # the backrest: a tall pillow with a rolled top: the golem's face
    bc, bs = V(0, 2.14, 0.66), (2.62, 2.1, 0.96)
    m.ell("Back", bs, bc, fab, "Fabric")
    m.ell("Back", (2.76, 0.66, 0.96), V(0, 3.02, 0.66), fab_l, "Fabric")
    for X, Y in ((-0.44, 0.38), (0.44, 0.38)):
        p, n = ell_front_at(bc, bs, X, Y)
        m.eye(p, n, 0.52, 0.5, fab, "sleepy", brow=fab_d, brow_k=1.2, lid_color=fab, lash_color=(30, 56, 52))
    p, n = ell_front_at(bc, bs, 0, 0.08)
    m.ell("Nose", (0.32, 0.26, 0.18), p, fab_d, R=frame_normal(n))
    for sp in (45, -45):
        m.blk("Nose", (0.13, 0.03, 0.03), p + n * 0.085, HAZ, R=frame_normal(n, sp))
    p, n = ell_front_at(bc, bs, 0, -0.18)
    m.mouth(p, n, 0.44, "sleepy", color=(32, 58, 54), d=0.05)
    # a sewn-on patch on the backrest corner
    p, n = ell_front_at(bc, bs, 0.95, -0.3)
    m.blk("Patch", (0.36, 0.32, 0.05), p, RUST, "Fabric", R=frame_normal(n, 8))
    for sp in (45, -45):
        m.blk("Stitch", (0.1, 0.03, 0.03), p + n * 0.03 + V(0.11, 0.1, 0), HAZ, R=frame_normal(n, sp))
    # rolled armrests ending in big fists
    for s in (-1, 1):
        sh, el = V(s * 1.32, 1.82, 0.74), V(s * 1.38, 1.66, -0.86)
        fist = V(s * 1.52, 0.5, -1.4)
        m.ball("Shoulder", 0.84, sh, fab, "Fabric")
        m.seg("UpperArm", sh, el, 0.42, fab, "Fabric", r2=0.38, bulge=0.5, ext=0.12)
        m.cyl("ArmPlate", 0.14, 0.78, el + V(0, 0.02, -0.12), fab_l, "z", "Fabric")
        m.cyl("ArmBand", 0.1, 0.86, el + V(0, 0.02, -0.08), HAZ, "z", "Fabric")
        m.ball("Elbow", 0.62, el + V(s * 0.02, -0.12, -0.08), fab, "Fabric")
        m.seg("Forearm", el + V(0, -0.1, -0.08), fist + V(0, 0.22, 0.12), 0.3, fab, "Fabric", bulge=0.62)
        m.glove(fist, 0.42, fab_l, s, fist=True, fingers=3, name="Fist", forward=(0, -0.35, -1))
        m.blk("Stitch", (0.2, 0.04, 0.04), fist + V(0, 0.38, 0.18), HAZ, R=rot(x=-30))
    # a spring popping out of a tear in the seat, with stuffing
    tc = V(0.7, 1.72, -0.5)
    m.ell("Tear", (0.46, 0.06, 0.32), tc, (26, 44, 42), R=rot(x=4, z=-4))
    for k, (dx, dz, d) in enumerate(((-0.2, 0.06, 0.2), (0.18, -0.08, 0.18), (0.08, 0.14, 0.16))):
        m.ball("Fluff", d, tc + V(dx, 0.04, dz), (246, 244, 236), "Fabric")
    pts = []
    for k in range(10):
        t = math.radians(k * 120)
        pts.append(tc + V(math.cos(t) * 0.12 + k * 0.012, 0.02 + k * 0.065, math.sin(t) * 0.12))
    m.chain("Spring", pts, 0.05, CHROME, "Metal", joints=False)
    # a lace doily on the backrest and a lost TV remote
    dc = V(0.34, 3.36, 0.56)
    m.ell("Doily", (1.06, 0.06, 0.82), dc, (250, 248, 240), "Fabric", R=rot(z=7, x=-4))
    for k in range(5):
        a = math.radians(200 + k * 35)
        m.ball("Doily", 0.14, dc + V(math.cos(a) * 0.5, -0.04 - abs(math.cos(a)) * 0.06, math.sin(a) * 0.38), (250, 248, 240), "Fabric")
    rc = V(-1.0, 1.72, -0.66)
    m.blk("Remote", (0.18, 0.1, 0.5), rc, (36, 36, 42), R=rot(x=24, y=-14))
    m.ball("Remote", 0.07, rc + V(0.0, 0.06, -0.14), (230, 60, 50))
    m.ball("Remote", 0.06, rc + V(0.0, 0.03, 0.02), HAZ)
    return m


# ------------------------------------------------------------------------------------------------
@model
def rusty_shopping_cart():
    """Rare. A runaway shopping cart creature: a thick rusty wire basket, a tin face plate with two
    big headlight eyes and a grille grin, the teal handle bent up as goofy eyebrows, squeaky casters,
    a rubber duck riding on a box of junk and a safety flag. Mood: goofy."""
    m = SModel("rusty_shopping_cart")
    wire_c = (170, 150, 136)
    TLf, TRf = V(-0.84, 2.06, -1.1), V(0.84, 2.06, -1.1)
    TLb, TRb = V(-0.64, 1.96, 1.16), V(0.64, 1.96, 1.16)
    BLf, BRf = V(-0.78, 1.1, -1.06), V(0.78, 1.1, -1.06)
    BLb, BRb = V(-0.58, 1.34, 1.12), V(0.58, 1.34, 1.12)
    # the frame (rust) and the wire grid (rusty tin)
    for a, b in ((TLf, TLb), (TRf, TRb), (TLb, TRb), (TLf, TRf), (BLf, BLb), (BRf, BRb), (BLf, BRf), (BLb, BRb),
                 (TLf, BLf), (TRf, BRf), (TLb, BLb), (TRb, BRb)):
        wire(m, a, b, 0.07, RUST)
    for (T0, T1, B0, B1) in ((TLf, TLb, BLf, BLb), (TRf, TRb, BRf, BRb)):
        for t in (0.25, 0.5, 0.75):
            wire(m, lerp(T0, T1, t), lerp(B0, B1, t), 0.04, wire_c)
        wire(m, lerp(T0, B0, 0.5), lerp(T1, B1, 0.5), 0.04, wire_c)
    for t in (0.25, 0.5, 0.75):
        wire(m, lerp(TLb, TRb, t), lerp(BLb, BRb, t), 0.04, wire_c)
    wire(m, lerp(TLb, BLb, 0.5), lerp(TRb, BRb, 0.5), 0.04, wire_c)
    for t in (0.33, 0.67):
        wire(m, lerp(BLf, BRf, t), lerp(BLb, BRb, t), 0.04, wire_c)
    # the face plate with headlight eyes and a grille grin
    plate = (194, 198, 204)
    m.rbox("Plate", (1.56, 0.92, 0.08), V(0, 1.6, -1.13), plate, 0.16, "Metal", axis="z", refl=0.15)
    for (x, y, sz, col) in ((-0.62, 1.26, 0.26, RUST), (0.66, 1.92, 0.2, RUST_D), (0.5, 1.22, 0.18, RUST)):
        patch(m, "Rust", V(x, y, -1.175), V(0, 0, -1), (sz, sz * 0.66, 0.03), col, spin=x * 40)
    for s in (-1, 1):
        p = V(s * 0.4, 1.76, -1.19)
        m.cyl("EyeRim", 0.12, 0.62, p + V(0, 0, 0.02), CHROME, "z", "Metal", refl=0.35)
        m.eye(p + V(0, 0, -0.03), V(0, 0, -1), 0.5, 0.5, plate, "goofy", sink=0.0)
    m.mouth(V(0, 1.38, -1.18), V(0, 0, -1), 0.78, "goofy", color=(46, 30, 34), kind="teeth")
    # the handle: bent up in the middle like raised eyebrows
    hl, hm, hr = V(-0.92, 2.3, -1.24), V(0, 2.46, -1.28), V(0.92, 2.3, -1.24)
    m.seg("Handle", hl, hm, 0.085, TEAL, ext=0.06)
    m.seg("Handle", hm, hr, 0.085, TEAL, ext=0.06)
    for p in (hl, hr):
        m.ball("Handle", 0.2, p, TEAL_D)
    wire(m, TLf, hl, 0.05, RUST)
    wire(m, TRf, hr, 0.05, RUST)
    # chassis and casters
    for s in (-1, 1):
        wire(m, V(s * 0.52, 0.5, -0.98), V(s * 0.46, 0.5, 1.04), 0.055, RUST)
        wire(m, V(s * 0.74, 1.1, -1.0), V(s * 0.54, 0.5, -0.96), 0.045, RUST)
        wire(m, V(s * 0.56, 1.34, 1.08), V(s * 0.46, 0.5, 1.02), 0.045, RUST)
    wire(m, V(-0.52, 0.5, -0.98), V(0.52, 0.5, -0.98), 0.045, RUST)
    for (x, z) in ((-0.54, -0.9), (0.54, -0.9), (-0.46, 0.96), (0.46, 0.96)):
        m.cyl("Fork", 0.08, 0.2, V(x, 0.47, z), DARK, "y", "Metal")
        for s in (-1, 1):
            m.blk("Fork", (0.03, 0.3, 0.12), V(x + s * 0.09, 0.3, z), DARK, "Metal")
        m.cyl("Wheel", 0.14, 0.38, V(x, 0.19, z), RUBBER, "x", "Rubber")
        m.cyl("Hubcap", 0.17, 0.18, V(x, 0.19, z), CHROME, "x", "Metal")
    # a rubber duck riding on a box of junk, a bottle and a sock
    m.blk("Box", (0.72, 0.6, 0.66), V(-0.18, 1.62, 0.42), (196, 156, 104), "SmoothPlastic", R=rot(y=12))
    m.blk("Box", (0.74, 0.04, 0.3), V(-0.18, 1.93, 0.42), (176, 136, 88), R=rot(y=12))
    dk = V(-0.16, 2.12, 0.36)
    m.ell("Duck", (0.62, 0.48, 0.74), dk, HAZ)
    m.ell("Duck", (0.26, 0.3, 0.2), dk + V(0, 0.14, 0.34), HAZ, R=rot(x=-30))
    m.ell("Duck", (0.16, 0.26, 0.4), dk + V(0.3, 0.02, 0.04), shade(HAZ, 0.9))
    m.ell("Duck", (0.16, 0.26, 0.4), dk + V(-0.3, 0.02, 0.04), shade(HAZ, 0.9))
    hd = dk + V(0, 0.4, -0.22)
    m.ball("Duck", 0.44, hd, HAZ)
    m.ell("DuckBeak", (0.26, 0.1, 0.22), hd + V(0, -0.04, -0.24), (244, 132, 40))
    for s in (-1, 1):
        m.eye(hd + V(s * 0.11, 0.06, -0.17), norm(V(s * 0.45, 0.1, -1)), 0.2, 0.22, HAZ, "cheerful", sink=0.0)
    m.seg("Bottle", V(0.36, 1.5, 0.66), V(0.46, 2.2, 0.8), 0.13, TEAL_L, "Glass", tr=0.25, refl=0.3)
    m.seg("Bottle", V(0.46, 2.2, 0.8), V(0.5, 2.44, 0.84), 0.05, TEAL_L, "Glass", tr=0.25)
    m.seg("Sock", V(0.2, 1.98, 1.18), V(0.22, 1.6, 1.3), 0.1, (240, 236, 226), "Fabric")
    m.ell("Sock", (0.22, 0.16, 0.32), V(0.22, 1.56, 1.22), RUST, "Fabric")
    # a safety flag on a whip pole
    m.seg("Flag", TRb + V(0, 0, 0), TRb + V(0.12, 1.2, 0.1), 0.025, (238, 238, 240), shape="C")
    ft = TRb + V(0.12, 1.2, 0.1)
    m.blk("Flag", (0.04, 0.34, 0.52), ft + V(0.0, -0.18, 0.26), HAZ, R=rot(x=-8))
    m.blk("Flag", (0.045, 0.1, 0.52), ft + V(0.0, -0.18, 0.26), RUST, R=rot(x=-8))
    # rust blooms on the frame joints
    for p in (TLf, TRb, BLf, BRb, lerp(TLf, TLb, 0.5)):
        m.ball("Rust", 0.18, p, RUST_D, "Metal")
    return m


# ------------------------------------------------------------------------------------------------
@model
def dumpster_diver():
    """Rare. A raccoon popping out of a dented teal dumpster with both lids thrown open: a black bandit
    mask, white muzzle and brows, ringed tail hanging over the front, a fish skeleton held up like a
    prize, a hazard sticker, rust streaks and trash on the rim. Mood: sly."""
    m = SModel("dumpster_diver")
    fur, fur_l, fur_d = (128, 128, 138), (214, 214, 222), (54, 52, 60)
    lidc = (48, 52, 58)
    # the dumpster
    m.rbox("Bin", (2.56, 1.56, 1.8), V(0, 1.14, 0.25), TEAL, 0.18, "Metal")
    for s in (-1, 1):
        m.blk("BinBase", (0.24, 0.16, 1.7), V(s * 0.9, 0.34, 0.25), TEAL_D, "Metal")
        m.blk("BinPocket", (0.12, 0.34, 1.5), V(s * 1.3, 1.2, 0.25), TEAL_D, "Metal")
    for x in (-0.8, 0.0, 0.8):
        m.blk("BinRib", (0.16, 1.28, 0.08), V(x, 1.1, -0.66), TEAL_D, "Metal")
    yr = 1.96
    for a, b in ((V(-1.32, yr, -0.68), V(1.32, yr, -0.68)), (V(-1.32, yr, 1.18), V(1.32, yr, 1.18)),
                 (V(-1.32, yr, -0.68), V(-1.32, yr, 1.18)), (V(1.32, yr, -0.68), V(1.32, yr, 1.18))):
        m.seg("BinRim", a, b, 0.1, TEAL_D, "Metal", shape="C", ext=0.1)
    m.blk("BinDark", (2.4, 0.04, 1.66), V(0, 1.9, 0.25), (24, 30, 30))
    for (x, z, k) in ((-0.64, 1.18, 106), (0.64, 1.18, 78)):
        t = math.radians(k)
        c = V(x, yr + 0.06, z) + V(0, math.sin(t) * 0.92, -math.cos(t) * 0.92)
        R = Rx(k)
        m.blk("BinLid", (1.24, 0.1, 1.84), c, lidc, R=R)
        for dx in (-0.3, 0.3):
            m.blk("BinLid", (0.12, 0.06, 1.6), c + R @ V(dx, -0.07, 0), shade(lidc, 1.25), R=R)
    for p, sz in ((V(0.92, 1.42, -0.69), (0.42, 0.34, 0.05)), (V(1.29, 0.92, 0.6), (0.3, 0.4, 0.05))):
        n = V(0, 0, -1) if p[2] < 0 else V(1, 0, 0)
        patch(m, "Dent", p, n, sz, TEAL_D)
    for (x, ln) in ((-1.05, 0.5), (0.38, 0.36), (1.1, 0.62)):
        m.ell("Rust", (0.1, ln, 0.04), V(x, 1.86 - ln / 2, -0.68), RUST)
    for (x, sz) in ((-0.5, 0.5), (0.6, 0.36)):
        patch(m, "Rust", V(x, 0.46, -0.665), V(0, 0, -1), (sz, 0.2, 0.04), RUST_D)
    sc = V(-0.4, 1.24, -0.71)
    m.blk("Sticker", (0.48, 0.48, 0.02), sc + V(0, 0, 0.005), WHITE, R=rot(z=45))
    m.blk("Sticker", (0.4, 0.4, 0.025), sc, HAZ, R=rot(z=45))
    m.blk("Sticker", (0.07, 0.2, 0.03), sc + V(0, 0.04, -0.01), INK)
    m.ball("Sticker", 0.08, sc + V(0, -0.12, -0.01), INK)
    for (x, z) in ((-0.95, -0.4), (0.95, -0.4), (-0.95, 0.9), (0.95, 0.9)):
        m.blk("Fork", (0.16, 0.12, 0.16), V(x, 0.32, z), DARK, "Metal")
        m.cyl("Wheel", 0.13, 0.3, V(x, 0.15, z), RUBBER, "x", "Rubber")
        m.cyl("Hubcap", 0.15, 0.13, V(x, 0.15, z), CHROME, "x", "Metal")
    # the raccoon: chest and belly fur rising out of the bin
    m.ell("Fur", (1.3, 1.16, 1.0), V(0, 2.28, 0.1), fur)
    m.ell("Fur", (0.84, 0.72, 0.36), V(0, 2.24, -0.34), fur_l)
    hc, hs = V(0, 3.04, -0.02), (1.32, 1.08, 1.12)
    m.ell("Head", hs, hc, fur)
    for s in (-1, 1):
        m.tuft("Cheek", hc + V(s * 0.5, -0.24, -0.12), V(s * 1, -0.5, -0.2), 0.42, 0.28, fur, n=2, spread=34)
    mz = hc + V(0, -0.26, -0.48)
    m.ell("Muzzle", (0.64, 0.42, 0.56), mz, fur_l)
    m.ell("Nose", (0.26, 0.17, 0.18), mz + V(0, 0.12, -0.26), INK)
    m.ball("Glint", 0.06, mz + V(-0.05, 0.17, -0.33), WHITE)
    # bandit mask, white brow patches and a dark forehead stripe
    for s in (-1, 1):
        p, n = on_ell_R(hc, hs, I3, Ry(s * 26) @ Rx(6) @ V(0, 0, -1))
        m.ell("Mask", (0.56, 0.4, 0.16), p + n * 0.0 + V(s * 0.02, -0.03, 0), fur_d, R=frame_normal(n, s * 14))
        q, nq = on_ell_R(hc, hs, I3, Ry(s * 26) @ Rx(26) @ V(0, 0, -1))
        m.ell("FacePatch", (0.44, 0.18, 0.12), q, fur_l, R=frame_normal(nq, -s * 10))
    p, n = on_ell_R(hc, hs, I3, Rx(22) @ V(0, 0, -1))
    m.ell("FacePatch", (0.14, 0.4, 0.1), p, fur_d, R=frame_normal(n))
    m.eyes_on(hc, hs, I3, 26, 6, 0.3, 0.32, fur_d, "sly", iris=(170, 120, 60), lid_color=fur_d, sink=0.18)
    p, n = on_ell_R(mz, (0.64, 0.42, 0.56), I3, V(0, -0.5, -1))
    m.mouth(p, n, 0.26, "sly", color=INK, side_bias=1, d=0.035)
    for s in (-1, 1):
        for dy in (0.02, -0.06):
            a0 = mz + V(s * 0.24, dy, -0.12)
            m.seg("Whisker", a0, a0 + V(s * 0.42, dy * 1.5, 0.02), 0.012, (240, 240, 244))
        m.ear(hc + V(s * 0.36, 0.38, 0.06), hc + V(s * 0.58, 0.84, 0.1), 0.38, fur_l, inner=fur_d,
              curve=(s * 0.04, 0, -0.02), facing=(s * 0.3, 0, -1))
    # arms: one leaning on the rim, one holding up a fish skeleton
    bone = (242, 236, 218)
    hands = m.arms2(2.42, 0.62, fur, 0.18, 0.16, 0.16, 0.2, fur_d,
                    {1: (V(0.96, 2.62, -0.3), V(1.0, 3.06, -0.46), True),
                     -1: (V(-0.98, 2.1, -0.5), V(-0.78, 1.98, -0.8), False)}, z=-0.06)
    h = hands[1]
    m.seg("FishBone", h + V(0, -0.08, 0), h + V(0.2, 0.86, -0.06), 0.045, bone)
    for k in range(4):
        q = h + V(0.05 + k * 0.04, 0.22 + k * 0.17, -0.02)
        for s in (-1, 1):
            m.seg("FishRib", q, q + V(s * 0.17, -0.07, 0), 0.022, bone, bulge=0.4)
    sk = h + V(0.22, 0.98, -0.07)
    m.ell("FishBone", (0.22, 0.3, 0.14), sk, bone, R=rot(z=-12))
    m.ball("FishEye", 0.08, sk + V(0.04, 0.04, -0.06), INK)
    for s in (-1, 1):
        m.seg("FishTail", h + V(0, -0.06, 0), h + V(s * 0.16, -0.3, -0.02), 0.05, bone, bulge=0.6)
    # the ringed tail hanging over the front of the bin
    tp = [V(0.78, 1.92, -0.3), V(0.98, 2.08, -0.66), V(1.04, 1.78, -0.84), V(1.0, 1.42, -0.86), V(0.94, 1.08, -0.84)]
    for k in range(4):
        m.seg("Tail" if k < 3 else "TailTip", tp[k], tp[k + 1], 0.2 - k * 0.012, fur if k % 2 == 0 else fur_d, ext=0.06)
    m.ball("TailTip", 0.3, tp[-1], fur_d)
    # trash on the rim: a banana peel and an apple core
    pc = V(-1.0, 2.1, 0.5)
    for k in range(3):
        a = math.radians(70 + k * 110)
        m.seg("Peel", pc, pc + V(math.cos(a) * 0.36, -0.2, math.sin(a) * 0.3), 0.08, HAZ, bulge=0.35)
    m.ball("Peel", 0.14, pc + V(0, 0.04, 0), (110, 90, 40))
    ac = V(1.14, 2.14, 0.6)
    m.ell("Core", (0.14, 0.3, 0.14), ac, (246, 236, 200))
    for dy in (0.14, -0.14):
        m.ell("Core", (0.24, 0.1, 0.24), ac + V(0, dy, 0), (210, 50, 50))
    m.seg("Core", ac + V(0, 0.18, 0), ac + V(0.04, 0.32, 0), 0.02, (90, 60, 30))
    return m


# ------------------------------------------------------------------------------------------------
@model
def glitter_gremlin():
    """Epic. A round teal gremlin with huge ribbed bat ears, a shock of scrap-wire hair, glitter flecks
    in its fur, a manic toothy grin, clawed paws, a bottle-cap necklace with a glass gem and a glue
    bottle squirting. Mood: manic grin."""
    m = SModel("glitter_gremlin")
    fur, fur_l, fur_d = TEAL, TEAL_L, TEAL_D
    claw = (244, 238, 220)
    # short thick legs on big clawed paws
    ank = m.legs2(0.82, 0.44, fur, 0.25, 0.21, 0.19, 0.66, 0.8, fur_d, foot="paw", toes=3, ankle_y=0.3)
    for a in ank:
        for k in (-1, 0, 1):
            b = V(a[0] + k * 0.2, 0.12, a[2] - 0.5)
            m.seg("Claws", b, b + V(k * 0.03, -0.04, -0.14), 0.045, claw, bulge=0.3)
    # round body and belly
    m.ell("Body", (1.62, 1.48, 1.42), V(0, 1.38, 0.06), fur)
    m.ell("Belly", (1.02, 0.96, 0.42), V(0, 1.28, -0.54), fur_l)
    for s in (-1, 1):
        m.tuft("Tuft", V(s * 0.74, 1.5, 0.1), V(s, 0.2, 0.2), 0.36, 0.22, fur, n=3, spread=26)
    # head
    hc, hs = V(0, 2.2, -0.14), (1.48, 1.22, 1.26)
    m.ell("Head", hs, hc, fur)
    m.eyes_on(hc, hs, I3, 25, 12, 0.46, 0.52, fur, "manic", iris=HAZ, pupil_k=0.5, brow=fur_d, brow_k=1.0)
    p, n = on_ell_R(hc, hs, I3, Rx(-4) @ V(0, 0, -1))
    m.ell("Nose", (0.24, 0.15, 0.16), p, fur_d, R=frame_normal(n))
    p, n = on_ell_R(hc, hs, I3, Rx(-26) @ V(0, 0, -1))
    m.mouth(p, n, 0.82, "manic", color=(76, 22, 46), skin=fur, kind="teeth", fangs=True, tongue=(250, 120, 160))
    # huge ribbed bat ears with rust insides and a washer earring
    for s in (-1, 1):
        base, tip = hc + V(s * 0.5, 0.3, 0.06), hc + V(s * 1.5, 1.32, 0.2)
        m.ear(base, tip, 0.86, fur, inner=RUST, curve=(s * 0.08, -0.06, 0.04), facing=(s * 0.35, 0.05, -1))
        m.spike("Ear", lerp(base, tip, 0.86), norm(tip - base), 0.42, 0.12, fur)
        for t in (0.3, 0.62):
            q = lerp(base, tip, t) + V(0, 0, -0.14)
            ax = norm(np.cross(tip - base, V(0, 0, 1)))
            m.seg("Ear", q + ax * 0.34 * (1.1 - t), q - ax * 0.3 * (1.1 - t), 0.035, fur_d)
        # scalloped lower edge: two little points
        for t in (0.42, 0.7):
            q = lerp(base, tip, t) + V(0, -0.26 * (1.1 - t), 0.02)
            m.spike("Ear", q, V(s * 0.3, -1, 0.1), 0.2, 0.08, fur)
    m.cyl("Ear", 0.06, 0.24, hc + V(-0.96, 0.4, 0.02), CHROME, "z", "Metal")
    # scrap-wire hair: copper, tin and teal wires bent every which way
    rnd = random.Random(7)
    for k in range(6):
        a = math.radians(-70 + k * 28)
        b0 = hc + V(math.sin(a) * 0.36, 0.5, 0.06 + rnd.uniform(-0.1, 0.1))
        b1 = b0 + V(math.sin(a) * 0.3, 0.42, rnd.uniform(-0.12, 0.12))
        b2 = b1 + V(rnd.uniform(-0.24, 0.24), 0.22, rnd.uniform(-0.1, 0.1))
        col = (COPPER, CHROME, (60, 150, 140), COPPER, HAZ, CHROME)[k]
        m.chain("Hair", [b0, b1, b2], 0.07, col, "Metal", joints=False)
    sp = [hc + V(0.06 + math.cos(math.radians(t * 140)) * 0.09, 0.6 + t * 0.07, 0.2 + math.sin(math.radians(t * 140)) * 0.09) for t in range(7)]
    m.chain("Hair", sp, 0.04, CHROME, "Metal", joints=False)
    # glitter in the fur
    rnd = random.Random(3)
    for k in range(16):
        on_head = k < 6
        c, sz = (hc, hs) if on_head else (V(0, 1.38, 0.06), (1.62, 1.48, 1.42))
        v = norm(V(rnd.uniform(-1, 1), rnd.uniform(-0.2 if on_head else -0.6, 1), rnd.uniform(-1, 0.2)))
        p, n = on_ell_R(c, sz, I3, v)
        col = (HAZ, (255, 236, 140), (255, 150, 210), HAZ)[k % 4]
        m.blk("Glitter", (0.07, 0.07, 0.02), p + n * 0.01, col, "Foil", R=frame_normal(n, 45))
    # arms: one flung up with claws spread, one holding a glue bottle
    hands = m.arms2(1.74, 0.72, fur, 0.2, 0.17, 0.17, 0.24, fur_d,
                    {1: (V(1.12, 1.48, -0.36), V(1.06, 1.86, -0.78), True),
                     -1: (V(-1.18, 1.92, -0.12), V(-1.36, 2.36, -0.36), False)}, z=-0.04)
    for k in (-1, 0, 1):
        q = hands[-1] + V(-0.06 + k * 0.14, 0.26, -0.04)
        m.seg("Claw", q, q + V(k * 0.06 - 0.04, 0.16, -0.04), 0.04, claw, bulge=0.3)
    g = hands[1] + V(0.0, 0.22, -0.12)
    m.cyl("Glue", 0.5, 0.38, g, (250, 250, 246), "y")
    m.ell("Glue", (0.38, 0.2, 0.38), g + V(0, 0.25, 0), (250, 250, 246))
    m.cyl("GlueLabel", 0.26, 0.4, g + V(0, -0.02, 0), TEAL_L, "y")
    m.ball("GlueLabel", 0.14, g + V(0, -0.02, -0.19), RUST)
    m.seg("GlueCap", g + V(0, 0.3, 0), g + V(0.02, 0.52, -0.02), 0.1, (240, 120, 40), bulge=0.3)
    m.seg("GlueCap", g + V(0.02, 0.5, -0.02), g + V(0.04, 0.66, -0.04), 0.035, (240, 120, 40))
    m.drip("Glue", tuple(g + V(0.06, 0.66, -0.07)), 0.3, 0.1, (252, 252, 248))
    # thin tail with a wire-bristle tip
    tp = [V(0, 1.0, 0.7), V(0.2, 0.8, 1.06), V(0.46, 0.92, 1.3), V(0.62, 1.22, 1.4)]
    for k in range(3):
        m.seg("Tail", tp[k], tp[k + 1], 0.1 - k * 0.015, fur, ext=0.04)
    m.tuft("TailTip", tp[-1], V(0.3, 1, 0.2), 0.3, 0.12, COPPER, n=3, spread=30)
    # bottle-cap necklace with a glass gem
    nk = [V(-0.62, 1.86, -0.32), V(-0.3, 1.66, -0.62), V(0, 1.6, -0.7), V(0.3, 1.66, -0.62), V(0.62, 1.86, -0.32)]
    m.chain("Necklace", nk, 0.04, DARK, joints=False)
    for p, col in ((nk[1], (220, 50, 50)), (nk[3], HAZ), (lerp(nk[0], nk[1], 0.5), CHROME), (lerp(nk[3], nk[4], 0.5), (220, 50, 50))):
        m.cyl("BottleCap", 0.07, 0.2, p + V(0, 0, -0.04), col, "z", "Metal")
    m.cyl("Gem", 0.06, 0.24, nk[2] + V(0, -0.02, -0.04), GOLD, "z", "Metal")
    m.crystal("Gem", nk[2] + V(0, -0.04, -0.08), V(0, -1, -0.1), 0.34, 0.2, (255, 110, 210), tr=0.1, refl=0.3)
    return m


# ------------------------------------------------------------------------------------------------
@model
def scrapheap_titan():
    """Mythic. A towering junk golem: a rust oil-drum chest with a hazard band, tyre pauldrons, a yellow
    crane-boom arm with a three-prong claw, a car-part arm (shock absorber, brake disc, exhaust pipe)
    ending in a huge fist, a CRT TV head with a stoic face on its screen, rebar spikes, a chain and a
    hazard beacon. Mood: stoic brute."""
    m = SModel("scrapheap_titan")
    steel = (120, 126, 134)
    # legs: rusty pipe thighs, hubcap knees, teal paint-can shins, concrete boots
    for s in (-1, 1):
        x = s * 0.66
        hip, knee, ank = V(x, 2.02, 0.06), V(x + s * 0.04, 1.38, -0.14), V(x + s * 0.06, 0.56, 0.02)
        m.seg("Thigh", hip, knee, 0.42, RUST, "Metal", bulge=0.42, ext=0.08)
        m.seg("Thigh", lerp(hip, knee, 0.42) + V(0, 0.04, 0), lerp(hip, knee, 0.5), 0.44, steel, "Metal", shape="C")
        m.ball("Knee", 0.62, knee, DARK, "Metal")
        m.cyl("Kneepad", 0.1, 0.56, knee + V(0, 0.02, -0.3), CHROME, "z", "Metal", refl=0.3)
        m.cyl("Kneepad", 0.12, 0.2, knee + V(0, 0.02, -0.34), DARK, "z", "Metal")
        m.seg("Shin", knee + V(0, -0.12, 0.02), ank + V(0, 0.08, 0), 0.36, TEAL, "Metal", shape="C")
        m.seg("Shin", knee + V(0, -0.14, 0.02), knee + V(0, -0.22, 0.02), 0.385, TEAL_D, "Metal", shape="C")
        m.drip("Shin", tuple(knee + V(s * 0.18, -0.18, -0.32)), 0.4, 0.12, HAZ)
        m.boot((ank[0], ank[2]), 0.96, 1.24, CONCRETE, sole=RUBBER, toe=steel, mat="Concrete")
    # tyre belt with a license plate buckle
    m.ell("Belt", (2.04, 0.52, 1.62), V(0, 2.14, 0.06), RUBBER, "Rubber")
    m.blk("Plate", (0.64, 0.34, 0.06), V(0, 2.12, -0.82), HAZ, "Metal")
    m.blk("Plate", (0.56, 0.26, 0.065), V(0, 2.12, -0.82), shade(HAZ, 1.08), "Metal")
    for k in range(3):
        m.blk("Plate", (0.1, 0.12, 0.07), V(-0.16 + k * 0.16, 2.12, -0.84), INK)
    # oil-drum chest
    dc = V(0, 3.1, 0.06)
    R0 = 1.0
    m.cyl("Barrel", 1.78, 2 * R0, dc, RUST, "y", "Metal", refl=0.08)
    for y in (2.64, 3.56):
        m.cyl("Hoop", 0.1, 2 * R0 + 0.07, V(0, y, 0.06), RUST_D, "y", "Metal")
    m.cyl("Hoop", 0.28, 2 * R0 + 0.035, V(0, 3.12, 0.06), HAZ, "y", "Metal")
    for k in range(4):
        a = 238 + k * 21
        m.blk("Hoop", (0.11, 0.36, 0.04), cpt(R0 + 0.02, a, 3.12, cz=0.06), INK, R=frame_normal(cn(a), 40))
    m.cyl("Hoop", 0.06, 2 * R0 - 0.1, V(0, 4.0, 0.06), DARK, "y", "Metal")
    m.cyl("Hoop", 0.12, 0.26, V(0.5, 4.04, 0.36), RUST_D, "y", "Metal")
    m.plate("ChestPlate", cpt(R0 + 0.03, 248, 2.84, cz=0.06), (0.56, 0.42, 0.06), steel, normal=cn(248), rivets=DARK)
    patch(m, "Splash", cpt(R0, 300, 2.86, cz=0.06, out=0.02), cn(300), (0.52, 0.36, 0.04), TEAL, spin=20)
    patch(m, "Splash", cpt(R0, 306, 2.68, cz=0.06, out=0.02), cn(306), (0.16, 0.3, 0.04), TEAL)
    patch(m, "Dent", cpt(R0, 290, 3.42, cz=0.06, out=-0.01), cn(290), (0.42, 0.3, 0.05), RUST_D)
    # tyre pauldrons, a hazard beacon on one
    for s in (-1, 1):
        pc = V(s * 1.16, 3.98, 0.06)
        R = Rz(-s * 22)
        m.ell("Pauldron", (1.2, 0.5, 1.2), pc, RUBBER, "Rubber", R=R)
        m.ell("Pauldron", (0.62, 0.52, 0.62), pc + R @ V(0, 0.02, 0), CHROME, "Metal", R=R, refl=0.2)
        m.ell("Pauldron", (0.26, 0.56, 0.26), pc + R @ V(0, 0.04, 0), DARK, "Metal", R=R)
    bc = V(-1.22, 4.3, 0.1)
    m.cyl("Beacon", 0.12, 0.3, bc, DARK, "y", "Metal")
    bi = m.ell("Beacon", (0.26, 0.3, 0.26), bc + V(0, 0.18, 0), (255, 140, 40), "Neon")
    m.light(bi, (255, 150, 60), 0.8, 6)
    # neck and CRT TV head with a stoic face on the screen
    m.cyl("Neck", 0.34, 0.5, V(0, 4.12, 0.06), DARK, "y", "Metal")
    tc = V(0, 4.72, 0.0)
    m.rbox("TV", (1.5, 1.02, 1.02), tc, TEAL, 0.14, "SmoothPlastic", axis="z")
    m.blk("Screen", (1.0, 0.8, 0.06), tc + V(-0.16, 0, -0.5), (26, 30, 34))
    m.ell("Screen", (0.9, 0.7, 0.1), tc + V(-0.16, 0, -0.52), (124, 232, 196), "Neon")
    px = (18, 70, 54)
    for s in (-1, 1):
        m.blk("ScreenEye", (0.18, 0.09, 0.04), tc + V(-0.16 + s * 0.2, 0.08, -0.575), px)
        m.blk("ScreenEye", (0.22, 0.05, 0.04), tc + V(-0.16 + s * 0.2, 0.2, -0.575), px, R=rot(z=s * 8))
    m.blk("ScreenMouth", (0.36, 0.05, 0.04), tc + V(-0.16, -0.18, -0.575), px)
    for k in range(2):
        m.cyl("Knob", 0.08, 0.17, tc + V(0.55, 0.22 - k * 0.24, -0.52), DARK, "z")
    for k in range(3):
        m.blk("Grille", (0.2, 0.025, 0.02), tc + V(0.55, -0.16 - k * 0.07, -0.515), DARK)
    for s in (-1, 1):
        a0 = tc + V(s * 0.06, 0.5, 0.1)
        tip = a0 + V(s * 0.46, 0.66, 0.08)
        m.seg("Antenna", a0, tip, 0.03, CHROME, "Metal", shape="C")
        m.ball("AntennaTip", 0.11, tip, HAZ if s > 0 else CHROME, "Metal")
    m.ell("Antenna", (0.3, 0.12, 0.24), tc + V(0, 0.52, 0.1), DARK)
    # crane arm (creature's right): hydraulic piston, nut elbow, lattice boom and a three-prong claw
    sh, el, wr = V(1.18, 3.52, 0.06), V(1.74, 2.86, -0.22), V(1.96, 1.9, -0.66)
    m.ball("Shoulder", 0.62, sh, DARK, "Metal")
    m.seg("Piston", sh, lerp(sh, el, 0.62), 0.22, HAZ, "Metal", shape="C")
    m.seg("Piston", lerp(sh, el, 0.55), el, 0.12, CHROME, "Metal", shape="C")
    m.ball("Elbow", 0.5, el, DARK, "Metal")
    hexnut(m, "Elbow", el + V(0.24, 0, 0), V(1, 0, 0), 0.16, 0.08, steel)
    d = norm(wr - el)
    side = norm(np.cross(d, V(1, 0, 0)))
    for o in (-1, 1):
        m.seg("ArmCrane", el + side * o * 0.14, wr + side * o * 0.1, 0.07, HAZ, "Metal", shape="C", ext=0.05)
    for t in (0.25, 0.5, 0.75):
        a_ = lerp(el, wr, t)
        m.seg("ArmCrane", a_ + side * 0.14 + d * 0.1, a_ - side * 0.14 - d * 0.1, 0.035, DARK, "Metal", shape="C")
    m.ball("Claw", 0.42, wr, DARK, "Metal")
    for k in range(3):
        a = math.radians(k * 120 + 30)
        out = V(math.cos(a), 0, math.sin(a)) * 0.24
        p1 = wr + out + V(0, -0.1, 0)
        p2 = wr + out * 1.7 + V(0, -0.42, 0)
        p3 = wr + out * 0.9 + V(0, -0.66, 0)
        m.seg("Claw", wr, p1, 0.08, steel, "Metal")
        m.seg("Claw", p1, p2, 0.07, steel, "Metal", ext=0.04)
        m.seg("Claw", p2, p3, 0.055, DARK, "Metal", bulge=0.3)
    # car-part arm (creature's left): shock absorber, brake disc elbow, exhaust forearm, hubcap fist
    sh, el, wr = V(-1.18, 3.52, 0.06), V(-1.72, 2.78, -0.08), V(-1.86, 1.86, -0.44)
    m.ball("Shoulder", 0.62, sh, DARK, "Metal")
    m.seg("UpperArm", sh, el, 0.13, CHROME, "Metal", shape="C")
    d = norm(el - sh)
    for t in (0.3, 0.5, 0.7):
        q = lerp(sh, el, t)
        m.seg("Bicep", q - d * 0.03, q + d * 0.03, 0.26, (200, 60, 50), "Metal", shape="C")
    m.cyl("Elbow", 0.12, 0.66, el, CHROME, "x", "Metal", refl=0.3)
    m.blk("Elbow", (0.18, 0.26, 0.2), el + V(0.02, 0.16, -0.22), HAZ, "Metal")
    m.seg("Forearm", el, wr, 0.24, (168, 170, 176), "Metal", shape="C", ext=0.05)
    m.seg("Cuff", lerp(el, wr, 0.82), wr + norm(wr - el) * 0.06, 0.29, DARK, "Metal", shape="C")
    fc = wr + norm(wr - el) * 0.42
    m.glove(fc, 0.46, RUST, -1, fist=True, fingers=4, name="Fist", forward=(0, -0.2, -1))
    m.cyl("ArmPlate", 0.08, 0.62, fc + V(-0.44, 0.06, 0.04), CHROME, "x", "Metal", refl=0.3)
    m.cyl("ArmPlate", 0.1, 0.2, fc + V(-0.47, 0.06, 0.04), DARK, "x", "Metal")
    for k in range(4):
        m.cyl("Knuckle", 0.08, 0.13, fc + V(-0.21 + k * 0.14, 0.2, -0.5), steel, "z", "Metal")
    # rebar spikes out of the back and a chain across the chest
    for (x, y, dx, dy, dz) in ((-0.5, 3.8, -0.3, 0.9, 0.6), (0.3, 3.86, 0.22, 1.0, 0.56), (0.7, 3.4, 0.6, 0.7, 0.7), (-0.8, 3.3, -0.7, 0.5, 0.6)):
        a_ = V(x, y, 0.6)
        b_ = a_ + V(dx, dy, dz) * 0.8
        m.seg("Rebar", a_, b_, 0.05, RUST_D, "Metal", shape="C")
        m.seg("Rebar", lerp(a_, b_, 0.7), lerp(a_, b_, 0.76), 0.07, RUST, "Metal", shape="C")
    pts = [cpt(R0 + 0.06, 300, 3.8, cz=0.06)] + [cpt(R0 + 0.08, 300 - k * 13, 3.6 - k * 0.24, cz=0.06) for k in range(1, 6)]
    for k in range(len(pts) - 1):
        m.seg("Chain", pts[k], pts[k + 1], 0.06, steel, "Metal", r2=0.03, spin=90 * (k % 2), ext=0.02)
    return m


# ------------------------------------------------------------------------------------------------
@model
def the_junk_king():
    """Legendary. A pompous galvanized trash-can king: a crown of bent forks and bottle caps on his lid,
    a doorknob nose, a scrub-brush mustache, a bottle-bottom monocle, bottle-cap medals, a mop-head
    ermine collar, an old rug cape with fringe, duct-hose arms in yellow rubber gloves, a plunger
    sceptre and mismatched sneakers. Flies buzz round the crown. Mood: pompous."""
    m = SModel("the_junk_king")
    galv = (182, 188, 194)
    rug, rug_d = (168, 54, 44), (120, 34, 30)
    # duct-hose legs and mismatched sneakers
    for s in (-1, 1):
        x = s * 0.5
        hip, knee, ank = V(x, 1.32, 0.06), V(x + s * 0.04, 0.82, -0.08), V(x + s * 0.06, 0.38, 0.0)
        m.leg(hip, knee, ank, 0.27, 0.24, 0.22, (196, 200, 206), mat="Metal")
        for a_, b_, nm in ((hip, knee, "Thigh"), (knee, ank, "Shin")):
            for t in (0.35, 0.68):
                q = lerp(a_, b_, t)
                m.seg(nm, q - V(0, 0.025, 0), q + V(0, 0.025, 0), 0.29 if nm == "Thigh" else 0.25, shade(galv, 0.84), "Metal", shape="C")
        col = TEAL if s < 0 else RUST
        m.boot((ank[0], ank[2]), 0.74, 1.04, col, sole=(244, 244, 240), toe=(244, 244, 240))
        for k in range(2):
            m.blk("Laces", (0.3, 0.04, 0.06), V(ank[0], 0.5 - k * 0.0, ank[2] - 0.2 - k * 0.14), HAZ)
    # the can body
    R0 = 1.02
    m.cyl("Can", 2.2, 2 * R0, V(0, 2.4, 0.06), galv, "y", "Metal", refl=0.22)
    for y in (1.5, 1.95, 3.44):
        m.cyl("CanRib", 0.1, 2 * R0 + 0.06, V(0, y, 0.06), shade(galv, 0.84), "y", "Metal", refl=0.15)
    for s in (-1, 1):
        a_, b_ = V(s * (R0 + 0.02), 3.22, -0.26), V(s * (R0 + 0.02), 3.22, 0.38)
        m.seg("CanHandle", a_, a_ + V(s * 0.2, 0, 0.02), 0.04, shade(galv, 0.7), "Metal", shape="C")
        m.seg("CanHandle", b_, b_ + V(s * 0.2, 0, -0.02), 0.04, shade(galv, 0.7), "Metal", shape="C")
        m.seg("CanHandle", a_ + V(s * 0.2, 0, 0), b_ + V(s * 0.2, 0, 0), 0.05, shade(galv, 0.7), "Metal", shape="C")
    # lid tilted on top, crown of bent forks and bottle caps
    m.ell("CanLid", (2.2, 0.38, 2.2), V(0, 3.62, 0.06), shade(galv, 1.04), "Metal", R=rot(z=-5), refl=0.25)
    m.seg("CanLid", V(-0.22, 3.86, 0.06), V(0.22, 3.84, 0.06), 0.05, shade(galv, 0.7), "Metal", shape="C")
    cc = V(0.06, 4.0, 0.06)
    m.cyl("CrownBand", 0.36, 1.42, cc, GOLD, "y", "Metal", refl=0.25)
    m.cyl("CrownBand", 0.07, 1.48, cc + V(0, -0.17, 0), shade(GOLD, 0.85), "y", "Metal")
    m.cyl("CrownBand", 0.07, 1.48, cc + V(0, 0.17, 0), shade(GOLD, 0.85), "y", "Metal")
    fork = (214, 220, 228)
    for k, a in enumerate((270, 215, 325, 160, 20)):
        n = cn(a)
        b0 = cpt(0.68, a, 4.06, cx=0.06, cz=0.06)
        bend = (k % 3) - 1
        up = norm(V(0, 1, 0) + n * 0.22)
        b1 = b0 + up * 0.46
        m.seg("CrownPoint", b0 + V(0, -0.1, 0), b1, 0.07, fork, "Metal", r2=0.035, spin=a)
        m.blk("CrownPoint", (0.28, 0.1, 0.05), b1 + up * 0.04, fork, "Metal", R=frame_normal(n, 0))
        for t in (-1, 0, 1):
            q = b1 + up * 0.07 + tang(a) * t * 0.1
            tip = q + norm(up + tang(a) * t * 0.14 + n * (0.5 if t == bend else 0)) * 0.4
            m.seg("CrownPoint", q, tip, 0.03, fork, "Metal", shape="C")
    for a, col in ((242, (220, 50, 50)), (298, HAZ), (188, TEAL_L), (352, (220, 50, 50))):
        m.cyl("CrownGem", 0.08, 0.26, cpt(0.72, a, 4.0, cx=0.06, cz=0.06), col, "x", "Metal", R=frame_from_x(cn(a)))
    gi = m.ball("CrownGem", 0.32, cpt(0.74, 270, 3.98, cx=0.06, cz=0.06), (90, 230, 140), "Glass", refl=0.3)
    m.light(gi, (120, 255, 170), 0.6, 5)
    # pompous face: smug lids, high brows, doorknob nose, scrub-brush mustache, bottle-bottom monocle
    eyes = eyes_cyl(m, R0, 2.98, 22, 0.42, 0.44, galv, POMPOUS, cz=0.06, iris=TEAL, brow=(70, 56, 48), brow_k=1.1)
    nz = cpt(R0, 270, 2.66, cz=0.06)
    m.seg("Nose", nz, nz + V(0, 0.04, -0.16), 0.07, BRASS, "Metal", shape="C")
    m.ball("Nose", 0.34, nz + V(0, 0.08, -0.26), BRASS, "Metal", refl=0.3)
    for s in (-1, 1):
        m0 = nz + V(s * 0.08, -0.14, -0.12)
        m1 = m0 + V(s * 0.34, -0.04, 0.06)
        m2 = m1 + V(s * 0.16, 0.16, 0.06)
        m.seg("Mustache", m0, m1, 0.11, (92, 62, 40), bulge=0.4, ext=0.04)
        m.seg("Mustache", m1, m2, 0.07, (92, 62, 40), bulge=0.5)
        m.ball("Mustache", 0.1, m2, (92, 62, 40))
    m.mouth(cpt(R0, 270, 2.36, cz=0.06), V(0, 0, -1), 0.34, POMPOUS, color=(60, 34, 34), side_bias=1, d=0.045)
    mo = eyes[1] + V(0, 0, -0.08)
    m.cyl("Monocle", 0.05, 0.56, mo, RUST_D, "z", "Metal")
    m.cyl("Monocle", 0.03, 0.48, mo + V(0, 0, -0.02), (120, 200, 140), "z", "Glass", tr=0.45, refl=0.4)
    mc = [mo + V(0.24, -0.16, 0), mo + V(0.3, -0.5, -0.06), mo + V(0.22, -0.82, -0.08)]
    m.chain("MonocleChain", mc, 0.03, GOLD, "Metal", joints=False)
    # bottle-cap medals with ribbons
    for k, (a, y, col) in enumerate(((236, 2.2, (220, 50, 50)), (250, 2.06, HAZ), (222, 2.0, TEAL_L))):
        p = cpt(R0 + 0.02, a, y, cz=0.06)
        m.blk("Medal", (0.12, 0.22, 0.03), p + V(0, 0.18, 0), TEAL if k % 2 else (220, 50, 50), R=frame_normal(cn(a)))
        m.cyl("Medal", 0.06, 0.24, p, col, "x", "Metal", R=frame_from_x(cn(a)))
        m.ball("Medal", 0.08, p + cn(a) * 0.04, GOLD, "Metal")
    # mop-head ermine collar
    for k in range(14):
        a = k * (360 / 14) + 6
        if abs(a - 270) < 40:
            continue   # keep the face clear
        p = cpt(R0 + 0.1, a, 3.3, cz=0.06)
        m.ball("Collar", 0.46, p, (248, 246, 240), "Fabric")
        if k % 3 == 1:
            m.ell("Collar", (0.1, 0.18, 0.06), p + cn(a) * 0.22 + V(0, -0.04, 0), INK, "Fabric", R=frame_normal(cn(a)))
    # the old rug cape: rust-red with teal borders, yellow diamonds and a fringe
    for k, a in enumerate((2, 30, 60, 90, 120, 150, 178)):
        n = cn(a)
        c = cpt(1.2, a, 1.84, cz=0.1)
        R = frame_normal(n) @ Rx(-8)
        m.ell("Cape", (1.12, 3.34, 0.14), c, rug, "Fabric", R=R)
        m.ell("Cape", (1.08, 0.24, 0.16), c + R @ V(0, -1.34, 0.01), TEAL, "Fabric", R=R)
        m.ell("Cape", (1.04, 0.08, 0.17), c + R @ V(0, -1.12, 0.01), HAZ, "Fabric", R=R)
        for t in (-0.3, 0.3):
            q = c + R @ V(t, -1.6, 0)
            m.seg("Tassel", q, q + V(0, -0.24, 0), 0.04, (240, 228, 196), "Fabric")
    bk = cpt(1.32, 90, 2.1, cz=0.08)
    for dy, col in ((0.0, HAZ), (0.6, TEAL)):
        m.blk("Cape", (0.42, 0.42, 0.05), bk + V(0, dy - 0.3, 0.04), col, "Fabric", R=frame_normal(cn(90), 45))
    for s in (-1, 1):
        m.cyl("Cape", 0.08, 0.3, cpt(R0 + 0.08, 270 + s * 62, 3.3, cz=0.06), GOLD, "x", "Metal", R=frame_from_x(cn(270 + s * 62)))
    # duct-hose arms, yellow rubber gloves, a plunger sceptre
    hands = m.arms2(3.04, R0 + 0.06, (196, 200, 206), 0.2, 0.19, 0.19, 0.27, HAZ,
                    {1: (V(1.5, 2.56, -0.24), V(1.58, 2.78, -0.72), True),
                     -1: (V(-1.52, 2.88, -0.1), V(-1.8, 3.34, -0.36), False)}, z=0.06, cuff=HAZ, mat="Metal")
    hp = hands[1]
    m.seg("PlungerStick", hp + V(0, -1.3, 0), hp + V(0, 1.5, 0), 0.07, WOOD, "Wood", shape="C")
    m.cyl("PlungerBand", 0.1, 0.18, hp + V(0, 1.32, 0), GOLD, "y", "Metal")
    m.ell("PlungerCup", (0.62, 0.44, 0.62), hp + V(0, 1.66, 0), (196, 48, 40), "Rubber")
    m.ball("ScepterTop", 0.22, hp + V(0, -1.36, 0), GOLD, "Metal")
    # flies buzzing round the crown and a couple of sparkles
    for (fx, fy, fz) in ((0.86, 4.5, -0.3), (-0.72, 4.8, 0.2)):
        f = V(fx, fy, fz)
        m.ball("Fly", 0.12, f, INK)
        for s in (-1, 1):
            m.ell("Fly", (0.16, 0.03, 0.1), f + V(s * 0.08, 0.06, 0.02), (220, 236, 250), "Glass", R=rot(z=s * 20), tr=0.3)
    for (x, y, z) in ((0.7, 4.3, -0.2), (-0.5, 4.5, -0.3)):
        m.blk("Sparkle", (0.1, 0.1, 0.02), V(x, y, z), (255, 240, 160), "Neon", R=rot(z=45))
    return m
