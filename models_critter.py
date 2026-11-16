# Critter family: cute fuzzy animals in little outfits, with a job and an attitude.
# Palette: hazel fur (main), cream belly (secondary), postbox red (accent) with leaf green.
# Materials: fabric clothes, leather bags and straps, wood.
import math
import random
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal, frame_from_x
from stylekit import SModel, PAL, V, norm, on_ell_R, INK, GOLD, SILVER

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


P = PAL["Critter"]
HAZEL = P["main"]
CREAM = P["second"]
RED = P["accent"]
LEAF = P["leaf"]
DARKF = P["dark"]
PINK = P["pink"]
LEATHER = (150, 96, 56)
LEATHER_D = (108, 66, 38)
WOOD = (178, 124, 72)
WOOD_D = (126, 82, 46)
NAVY = (44, 56, 112)
BLUSH = (255, 160, 170)
ORANGE = (244, 140, 50)

CURIOUS = dict(open=1.0, lid=0, brow=-16, lift=0.34, mouth="small", curve=0.22, look=(0.08, 0.14))
DILIGENT = dict(open=0.84, lid=4, brow=6, lift=0.2, mouth="smile", curve=0.14)
DUTIFUL = dict(open=0.82, lid=8, brow=10, lift=0.12, mouth="flat", curve=0.0)
STRICT = dict(open=0.62, lid=14, brow=24, lift=0.0, mouth="frown", curve=-0.24)
WARM = dict(open=0.72, lid=-6, brow=-10, lift=0.28, mouth="smile", curve=0.24)
FLAMBOYANT = dict(open=0.6, lid=-8, brow=-14, lift=0.34, mouth="smirk", curve=0.22)


def lerp(a, b, t):
    return a + (b - a) * t


def cheeks(m, c, s_, R, sep, y, d, color=BLUSH):
    for s in (-1, 1):
        p, n = on_ell_R(c, s_, R, np.array(R, float) @ V(s * sep, y, -1))
        m.ell("Cheek", (d, d * 0.6, d * 0.3), p + n * 0.01, color, R=frame_normal(n))


def scale_all(m, k):
    """Shrink a finished model about its feet (keeps it standing on y = 0)."""
    for p in m.parts:
        p["pos"] = tuple(float(v) * k for v in p["pos"])
        p["size"] = tuple(float(v) * k for v in p["size"])


def flower(m, name, p, n, d, petal, center=(255, 214, 70)):
    """A little flower lying on a surface: a petal disc and a round middle."""
    m.ell(name, (d, d, d * 0.3), p, petal, "Fabric", R=frame_normal(n))
    m.ball(name, d * 0.42, p + norm(n) * d * 0.12, center)


# ------------------------------------------------------------------------------------------------
@model
def pocket_mouse():
    """Common. A curious mouse peeking out of a stitched leather pocket: big round ears with pink
    insides, a pink nose, whiskers, buck teeth, little paws hugging a holey cheese wedge, red stitching
    and a pink tail curling out over the rim. Mood: curious."""
    m = SModel("pocket_mouse")
    fur = (176, 130, 92)
    # the pocket: a rounded leather pouch with a rolled rim, red stitching and brass rivets
    m.rbox("Pocket", (1.84, 1.2, 1.22), V(0, 0.82, 0.08), LEATHER, 0.42, "Leather")
    m.ell("Pocket", (1.84, 0.44, 1.22), V(0, 0.24, 0.08), LEATHER, "Leather")
    m.rbox("PocketRim", (1.92, 0.14, 1.3), V(0, 1.44, 0.08), LEATHER_D, 0.46, "Leather")
    m.rbox("PocketRim", (1.56, 0.15, 0.96), V(0, 1.45, 0.08), (44, 30, 22), 0.32)
    for k in range(6):
        x = -0.72 + k * 0.288
        m.blk("Stitch", (0.16, 0.04, 0.04), V(x, 1.24, -0.53), RED)
    for k in range(3):
        m.blk("Stitch", (0.04, 0.16, 0.04), V(-0.92, 1.02 - k * 0.26, -0.33 - k * 0.0), RED, R=rot(y=-38))
        m.blk("Stitch", (0.04, 0.16, 0.04), V(0.92, 1.02 - k * 0.26, -0.33 - k * 0.0), RED, R=rot(y=38))
    for s in (-1, 1):
        m.cyl("Rivet", 0.06, 0.14, V(s * 0.74, 1.3, -0.54), (226, 180, 80), "z", "Metal")
    m.blk("Tag", (0.34, 0.24, 0.04), V(0.42, 0.72, -0.54), LEAF, "Fabric", R=rot(z=-8))
    m.ell("Tag", (0.12, 0.1, 0.05), V(0.42, 0.72, -0.56), RED, R=rot(z=-8))
    # the mouse: chest, belly, a big tilted head
    m.ell("Fur", (1.0, 0.98, 0.84), V(0, 1.62, 0.02), fur)
    m.ell("Belly", (0.66, 0.64, 0.3), V(0, 1.56, -0.34), CREAM)
    Rh = Rz(9)
    hc, hs = V(0, 2.36, -0.08), (1.14, 1.02, 1.0)
    m.ell("Head", hs, hc, fur, R=Rh)
    mz = hc + Rh @ V(0, -0.2, -0.44)
    m.ell("Muzzle", (0.54, 0.4, 0.52), mz, CREAM, R=Rh)
    m.ball("Nose", 0.2, mz + Rh @ V(0, 0.08, -0.27), (244, 130, 150))
    m.ball("Glint", 0.06, mz + Rh @ V(-0.04, 0.13, -0.35), WHITE)
    for s in (-1, 1):
        m.blk("Tooth", (0.08, 0.1, 0.04), mz + Rh @ V(s * 0.045, -0.14, -0.24), WHITE)
        for dy in (0.04, -0.04):
            a0 = mz + Rh @ V(s * 0.2, dy, -0.16)
            m.seg("Whisker", a0, a0 + Rh @ V(s * 0.46, dy * 1.4, 0.04), 0.012, (90, 64, 50))
    p, n = on_ell_R(mz, (0.54, 0.4, 0.52), Rh, Rh @ V(0, -0.35, -1))
    m.mouth(p + n * 0.01, n, 0.22, CURIOUS, color=(110, 60, 60), d=0.03)
    m.eyes_on(hc, hs, Rh, 27, 12, 0.34, 0.4, fur, CURIOUS, iris=(120, 76, 44), brow=DARKF, brow_k=0.8, lash=2)
    for s in (-1, 1):
        ec = hc + Rh @ V(s * 0.5, 0.5, 0.12)
        Re = Rh @ rot(y=-s * 18, z=-s * 16)
        m.ell("Ear", (0.84, 0.84, 0.16), ec, fur, R=Re)
        m.ell("EarInner", (0.6, 0.6, 0.1), ec + Re @ V(0, 0, -0.05), (250, 176, 186), R=Re)
    # little paws hugging a cheese wedge
    hands = m.arms2(1.86, 0.42, fur, 0.14, 0.12, 0.12, 0.15, (244, 170, 170),
                    {1: (V(0.58, 1.6, -0.36), V(0.32, 1.68, -0.66), False),
                     -1: (V(-0.58, 1.6, -0.36), V(-0.32, 1.68, -0.66), False)})
    ch = V(0, 1.66, -0.84)
    m.wedge("Cheese", (0.34, 0.62, 0.56), ch, (255, 206, 70), R=rot(z=90, y=180))
    for (dx, dy, dz, d) in ((0.12, 0.18, -0.12, 0.1), (-0.1, 0.18, 0.06, 0.08), (0.05, -0.02, -0.29, 0.09)):
        m.ell("CheeseHole", (d, d * 0.5, d), ch + V(dx, dy, dz), (226, 170, 50))
    # a pink tail curling out over the rim and onto the ground
    tp = [V(0.36, 1.46, 0.56), V(0.7, 1.6, 0.74), V(0.98, 1.0, 0.82), V(1.12, 0.3, 0.6), V(1.06, 0.07, 0.16), V(0.82, 0.07, -0.04)]
    for k in range(len(tp) - 1):
        m.seg("Tail" if k < 4 else "TailTip", tp[k], tp[k + 1], 0.07 - k * 0.006, (240, 170, 176), ext=0.03)
    return m


# ------------------------------------------------------------------------------------------------
@model
def moth_mailman():
    """Common. A fuzzy moth postie: a cream fluffy body with hazel bands, a fluffy collar, feathery
    antennae poking through a red postman cap, big patterned wings with eye spots, a red satchel of
    letters, white gloves holding out a letter and sturdy boots. Mood: diligent."""
    m = SModel("moth_mailman")
    fuzz, fuzz_d = CREAM, (224, 200, 166)
    wing, wing_d = (200, 150, 98), (142, 96, 60)
    shin = (96, 70, 56)
    # legs: fuzzy thighs, dark shins, postman boots
    for s in (-1, 1):
        hip, knee, ank = V(s * 0.3, 1.18, 0.12), V(s * 0.33, 0.72, 0.04), V(s * 0.35, 0.3, 0.12)
        m.seg("Thigh", hip, knee, 0.2, fuzz, bulge=0.4)
        m.ball("Knee", 0.32, knee, fuzz_d)
        m.seg("Shin", knee, ank, 0.12, shin, bulge=0.45)
        m.boot((ank[0], ank[2]), 0.48, 0.72, (70, 48, 36), sole=(30, 24, 22), cuff=RED)
    # fuzzy abdomen with hazel bands, thorax and a fluffy collar
    m.ell("Body", (1.08, 1.16, 1.06), V(0, 1.5, 0.2), fuzz)
    for y, d in ((1.34, 1.0), (1.66, 1.02)):
        m.ell("Body", (d + 0.06, 0.12, d + 0.04), V(0, y, 0.2), wing_d)
    m.ell("Chest", (1.12, 1.0, 0.96), V(0, 2.16, -0.02), fuzz)
    for k in range(8):
        a = math.radians(k * 45 + 22)
        m.ball("Fluff", 0.38, V(math.sin(a) * 0.48, 2.44, 0.02 - math.cos(a) * 0.4), WHITE, "Fabric")
    # head, big diligent eyes, a small smile
    hc, hs = V(0, 3.0, -0.14), (1.02, 0.94, 0.92)
    m.ell("Head", hs, hc, fuzz)
    m.eyes_on(hc, hs, I3, 28, -6, 0.36, 0.38, fuzz, DILIGENT, iris=(70, 50, 110), brow=wing_d, brow_k=0.85)
    p, n = on_ell_R(hc, hs, I3, Rx(-24) @ V(0, 0, -1))
    m.mouth(p, n, 0.22, DILIGENT, color=(110, 60, 60), d=0.03)
    cheeks(m, hc, hs, I3, 0.62, -0.26, 0.2)
    # red postman cap with a black bill and a gold envelope badge
    cc = hc + V(0, 0.48, 0.04)
    m.ell("Cap", (0.98, 0.34, 0.96), cc, RED, "Fabric")
    m.cyl("Cap", 0.22, 0.98, cc + V(0, -0.1, 0), RED, "y", "Fabric")
    m.cyl("HatBand", 0.08, 1.0, cc + V(0, -0.2, 0), INK, "y", "Fabric")
    m.ell("CapBill", (0.74, 0.07, 0.46), cc + V(0, -0.22, -0.46), INK, R=rot(x=-10))
    m.blk("CapBadge", (0.22, 0.15, 0.04), cc + V(0, -0.02, -0.5), GOLD, "Metal")
    m.wedge("CapBadge", (0.04, 0.07, 0.2), cc + V(0, 0.01, -0.52), shade(GOLD, 0.8), "Metal", R=rot(z=90))
    # feathery antennae curving up out of the cap
    for s in (-1, 1):
        a0 = cc + V(s * 0.16, 0.1, -0.2)
        a1 = a0 + V(s * 0.24, 0.42, -0.1)
        a2 = a1 + V(s * 0.34, 0.24, 0.06)
        m.seg("Antenna", a0, a1, 0.05, fuzz_d)
        m.seg("Antenna", a1, a2, 0.045, fuzz_d)
        d = norm(a2 - a0)
        F = frame_from_x(d)
        m.ell("Antenna", (0.86, 0.34, 0.05), lerp(a0, a2, 0.62), wing, R=F @ Rx(70))
        for o in (-1, 1):
            m.ell("Antenna", (0.62, 0.05, 0.06), lerp(a0, a2, 0.62) + F @ Rx(70) @ V(0, o * 0.09, 0.0), wing_d, R=F @ Rx(70))
        m.ball("AntennaTip", 0.14, a2, wing)
    # big patterned wings with eye spots (two pairs)
    for s in (-1, 1):
        for (c, sz, ang, spot) in ((V(s * 1.18, 2.64, 0.42), (1.8, 1.36, 0.1), 24, 0.44), (V(s * 0.9, 1.7, 0.46), (1.2, 0.96, 0.1), -18, 0.3)):
            R = rot(y=s * 28) @ rot(z=s * ang)
            m.ell("Wing", sz, c, wing, R=R)
            m.ell("WingTip", (sz[0] * 0.5, sz[1] * 0.5, 0.11), c + R @ V(s * sz[0] * 0.28, sz[1] * 0.12, 0), wing_d, R=R)
            m.ell("WingStripe", (sz[0] * 0.9, 0.08, 0.12), c + R @ V(0, -sz[1] * 0.22, 0), wing_d, R=R)
            q = c + R @ V(s * sz[0] * 0.04, sz[1] * 0.04, -0.06)
            m.ell("WingSpot", (spot, spot, 0.04), q, CREAM, R=R)
            m.ell("WingSpot", (spot * 0.62, spot * 0.62, 0.05), q + R @ V(0, 0, -0.01), DARKF, R=R)
            m.ell("WingSpot", (spot * 0.24, spot * 0.24, 0.06), q + R @ V(-s * spot * 0.08, spot * 0.08, -0.02), RED, R=R)
    # a red satchel full of letters on a strap
    sc = V(0.64, 1.42, -0.34)
    m.rbox("Satchel", (0.7, 0.56, 0.3), sc, RED, 0.12, "Leather", R=rot(y=-24), axis="z")
    m.rbox("Satchel", (0.72, 0.28, 0.32), sc + V(0, 0.17, -0.02), shade(RED, 0.78), 0.1, "Leather", R=rot(y=-24), axis="z")
    m.cyl("Satchel", 0.05, 0.12, sc + V(-0.04, 0.06, -0.19), GOLD, "z", "Metal", R=rot(y=-24))
    for k, (dx, dy) in enumerate(((-0.14, 0.34), (0.1, 0.38))):
        m.blk("SatchelLetter", (0.3, 0.2, 0.03), sc + V(dx, dy, 0.02), (252, 250, 244), R=rot(y=-24, z=(k - 0.5) * 20))
    for a_, b_ in ((sc + V(-0.2, 0.2, -0.04), V(0.2, 2.36, -0.5)), (V(0.2, 2.36, -0.5), V(-0.48, 2.5, -0.02))):
        m.seg("Strap", a_, b_, 0.06, LEATHER_D, "Leather", r2=0.03, ext=0.04)
    # arms in white gloves: one holding out a letter
    hands = m.arms2(2.34, 0.56, fuzz, 0.15, 0.13, 0.12, 0.17, WHITE,
                    {-1: (V(-0.84, 2.0, -0.3), V(-0.74, 2.12, -0.74), False),
                     1: (V(0.82, 1.92, -0.12), V(0.72, 1.66, -0.44), True)})
    lt = hands[-1] + V(0.06, 0.12, -0.12)
    m.blk("Letter", (0.46, 0.3, 0.03), lt, (252, 250, 244), R=rot(x=-10, z=-10))
    m.blk("Stamp", (0.1, 0.12, 0.035), lt + V(0.14, 0.06, -0.005), RED, R=rot(x=-10, z=-10))
    m.wedge("Letter", (0.032, 0.14, 0.44), lt + V(0, 0.07, -0.01), (232, 228, 220), R=rot(x=-10, z=-10) @ rot(z=90, x=90))
    return m


# ------------------------------------------------------------------------------------------------
@model
def pillow_bunny():
    """Rare. A plump pillow bunny: a soft square cushion body with puffy middle, corner tufts and piped
    seams, long floppy ears, a red-and-cream striped nightcap with a pompom, sleepy eyes, buck teeth,
    big bunny feet, a pompom tail and a carrot plush hugged to its tummy. Mood: sleepy."""
    m = SModel("pillow_bunny")
    pil, pil_d = (250, 238, 220), (222, 200, 172)
    feet = HAZEL
    # big soft feet on stubby legs
    for s in (-1, 1):
        m.seg("Leg", V(s * 0.5, 0.7, 0.06), V(s * 0.55, 0.26, 0.02), 0.22, pil, bulge=0.4)
        m.ell("Foot", (0.56, 0.34, 0.98), V(s * 0.56, 0.17, -0.18), feet)
        for k in (-1, 0, 1):
            m.ball("Toe", 0.16, V(s * 0.56 + k * 0.14, 0.12, -0.64), shade(feet, 1.12))
        m.ell("Sole", (0.3, 0.06, 0.34), V(s * 0.56, 0.05, -0.32), BLUSH)
    # the pillow: a rounded square slab with a puffy middle, corner tufts and piped seams
    bc = V(0, 1.58, 0.05)
    m.rbox("Body", (2.16, 1.94, 0.6), bc, pil, 0.52, "Fabric", axis="z")
    m.ell("Body", (1.98, 1.78, 1.02), bc, pil, "Fabric")
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = bc + V(sx * 0.86, sy * 0.76, 0)
            m.seg("Tuft", c, c + V(sx * 0.34, sy * 0.3, 0), 0.13, pil, bulge=0.25)
    for a_, b_ in ((V(-0.54, 0.97, 0), V(0.54, 0.97, 0)), (V(-0.54, 0.97, 0) * V(1, -1, 1), V(0.54, 0.97, 0) * V(1, -1, 1)),
                   (V(-1.08, 0.46, 0), V(-1.08, -0.46, 0)), (V(1.08, 0.46, 0), V(1.08, -0.46, 0))):
        m.seg("Seam", bc + a_, bc + b_, 0.05, pil_d, shape="C", ext=0.04)
    # sleepy face: drowsy lids, pink nose, buck teeth, a little smile, rosy cheeks
    fc, fs = bc, (1.98, 1.78, 1.02)
    for X in (-0.42, 0.42):
        p, n = on_ell_R(fc, fs, I3, V(X, 0.34, -0.42))
        m.eye(p, n, 0.44, 0.38, pil, "sleepy", lash=2, brow=pil_d, brow_k=0.9, iris=(110, 80, 150))
    p, n = on_ell_R(fc, fs, I3, V(0, 0.08, -0.5))
    m.ell("Nose", (0.2, 0.14, 0.1), p, (244, 130, 150), R=frame_normal(n))
    m.mouth(p + V(0, -0.14, 0), n, 0.24, "sleepy", color=(150, 90, 90), d=0.03)
    for s in (-1, 1):
        m.blk("Tooth", (0.08, 0.1, 0.03), p + V(s * 0.045, -0.22, -0.01), WHITE)
    for X in (-0.7, 0.7):
        q, nq = on_ell_R(fc, fs, I3, V(X, -0.04, -0.44))
        m.ell("Cheek", (0.3, 0.18, 0.06), q, BLUSH, R=frame_normal(nq))
    # long floppy ears
    for s in (-1, 1):
        b0 = bc + V(s * 0.46, 0.92, 0.0)
        b1 = b0 + V(s * 0.22, 0.6, 0.02)
        b2 = b1 + V(s * 0.66, -0.2, -0.04)
        b3 = b2 + V(s * 0.24, -0.62, -0.06)
        for k, (a_, c_) in enumerate(((b0, b1), (b1, b2), (b2, b3))):
            m.seg("Ear", a_, c_, 0.25 - k * 0.02, pil, r2=0.12, ext=0.1, bulge=0.5)
            m.seg("EarInner", a_ + V(0, 0, -0.06), c_ + V(0, 0, -0.06), 0.15 - k * 0.015, BLUSH, r2=0.06, bulge=0.5)
    # striped nightcap flopping over with a pompom
    hb = bc + V(0.04, 1.02, 0.04)
    m.cyl("HatTrim", 0.16, 0.86, hb, CREAM, "y", "Fabric")
    pts = [hb + V(0, 0.04, 0), hb + V(0.06, 0.56, 0.0), hb + V(0.34, 0.86, 0.02), hb + V(0.7, 0.8, 0.04), hb + V(0.9, 0.46, 0.06)]
    for k, rr in enumerate((0.42, 0.3, 0.2, 0.13)):
        m.seg("Hat", pts[k], pts[k + 1], rr, RED, "Fabric", r2=rr, ext=0.08, bulge=0.4)
        q = lerp(pts[k], pts[k + 1], 0.5)
        m.seg("HatTrim", q - norm(pts[k + 1] - pts[k]) * 0.04, q + norm(pts[k + 1] - pts[k]) * 0.04, rr * 0.98 + 0.02, CREAM, "Fabric", shape="C")
    m.ball("HatTip", 0.34, pts[-1] + V(0.02, -0.12, 0), WHITE, "Fabric")
    # stubby arms hugging a carrot plush
    hands = m.arms2(1.44, 1.0, pil, 0.17, 0.15, 0.15, 0.17, pil,
                    {1: (V(1.06, 1.12, -0.44), V(0.56, 1.06, -0.72), False),
                     -1: (V(-1.06, 1.12, -0.44), V(-0.56, 1.06, -0.72), False)})
    ca, cb = V(-0.5, 0.86, -0.7), V(0.46, 1.28, -0.72)
    m.seg("Carrot", ca, cb, 0.2, ORANGE, "Fabric", bulge=0.72, ext=0.04)
    for t in (0.3, 0.55):
        q = lerp(ca, cb, t + 0.12)
        m.blk("Carrot", (0.04, 0.2, 0.04), q + V(0, 0, -0.19), shade(ORANGE, 0.78), R=rot(z=-24))
    for k in (-1, 0, 1):
        m.seg("Carrot", cb, cb + V(0.24 + k * 0.04, 0.12 + k * 0.12, -0.02), 0.07, LEAF, bulge=0.4)
    for s in (-1, 1):
        m.ball("Carrot", 0.06, lerp(ca, cb, 0.7) + V(s * 0.04, 0.08 + s * 0.02, -0.2), INK)
    m.ball("Tail", 0.46, bc + V(0, -0.5, 0.56), WHITE, "Fabric")
    return m


# ------------------------------------------------------------------------------------------------
@model
def hamster_wheel_hero():
    """Rare. A golden hamster superhero sprinting in a wooden wheel on a stand: puffy cheek pouches, a
    navy domino mask, determined brows, a chest emblem, a red cape streaming back, pumping fists,
    pink paws, wood shavings and speed lines. Mood: determined."""
    m = SModel("hamster_wheel_hero")
    fur, paw = (224, 158, 88), (246, 170, 162)
    # wooden base with shavings, A-frame stands, wheel with rungs and red hubs
    m.rbox("Base", (2.7, 0.22, 2.9), V(0, 0.11, 0), WOOD_D, 0.24, "Wood")
    m.scatter("Shaving", V(0, 0.22, 0), (2.5, 0.06, 2.7), 12, [(242, 218, 164), (226, 196, 142)], seed=3, d=0.1, ymin=0.5, length=2.0)
    wc, wr = V(0, 1.64, 0), 1.36
    for s in (-1, 1):
        for sz in (-1, 1):
            m.seg("Stand", V(s * 1.2, 0.2, sz * 0.86), V(s * 1.2, wc[1], 0), 0.08, WOOD, "Wood", shape="C", ext=0.06)
        m.ring("Wheel", V(s * 0.96, wc[1], 0), wr, 0.15, WOOD, normal="x", segments=14, mat="Wood")
        m.cyl("WheelHub", 0.14, 0.42, V(s * 1.02, wc[1], 0), RED, "x", "SmoothPlastic")
        for k in range(3):
            a = k * math.pi / 3 + 0.3
            m.seg("Spoke", V(s * 0.96, wc[1] + math.sin(a) * wr, math.cos(a) * wr), V(s * 0.96, wc[1] - math.sin(a) * wr, -math.cos(a) * wr), 0.04, WOOD_D, "Wood", shape="C")
    m.cyl("Axle", 2.44, 0.14, wc, (200, 200, 210), "x", "Metal")
    for k in range(12):
        a = k * 2 * math.pi / 12 + math.pi / 12
        if math.cos(a) < -0.6:
            continue
        m.cyl("Rung", 1.92, 0.08, V(0, wc[1] + math.sin(a) * (wr - 0.04), math.cos(a) * (wr - 0.04)), (236, 210, 160), "x", "Wood")
    # the hamster: leaning into the run
    m.ell("Body", (1.06, 1.0, 1.24), V(0, 0.98, 0.02), fur, R=rot(x=-16))
    m.ell("Belly", (0.76, 0.68, 0.44), V(0, 0.9, -0.42), CREAM, R=rot(x=-16))
    m.cyl("Emblem", 0.06, 0.38, V(0, 1.0, -0.62), (255, 214, 60), "z", R=rot(x=-16))
    m.blk("Emblem", (0.07, 0.24, 0.04), V(0, 1.0, -0.66), RED, R=rot(x=-16, z=24))
    hc, hs = V(0, 1.64, -0.5), (1.02, 0.94, 0.94)
    m.ell("Head", hs, hc, fur)
    for s in (-1, 1):
        m.ball("Cheek", 0.56, hc + V(s * 0.38, -0.26, -0.18), CREAM)
        ec = hc + V(s * 0.36, 0.44, 0.06)
        m.ell("Ear", (0.34, 0.34, 0.12), ec, fur, R=rot(y=-s * 20, z=-s * 18))
        m.ell("EarInner", (0.22, 0.22, 0.08), ec + V(0, 0, -0.04), paw, R=rot(y=-s * 20, z=-s * 18))
    for s in (-1, 1):
        p, n = on_ell_R(hc, hs, I3, Ry(s * 24) @ Rx(14) @ V(0, 0, -1))
        m.ell("Mask", (0.56, 0.38, 0.22), p + n * 0.0, NAVY, R=frame_normal(n, s * 14))
        t0 = hc + V(s * 0.46, 0.14, 0.12)
        m.seg("Mask", t0, t0 + V(s * 0.2, -0.08, 0.5), 0.06, NAVY, r2=0.02)
    p, n = on_ell_R(hc, hs, I3, Rx(16) @ V(0, 0, -1))
    m.ell("Mask", (0.3, 0.2, 0.16), p, NAVY, R=frame_normal(n))
    m.eyes_on(hc, hs, I3, 24, 14, 0.3, 0.3, NAVY, "determined", iris=(110, 70, 36), lid_color=NAVY, sink=0.3)
    p, n = on_ell_R(hc, hs, I3, Rx(-12) @ V(0, 0, -1))
    m.ball("Nose", 0.14, p + n * 0.02, (240, 120, 130))
    m.mouth(p + V(0, -0.14, 0), n, 0.22, "determined", color=(110, 56, 50), d=0.03)
    m.blk("Tooth", (0.1, 0.1, 0.03), p + V(0, -0.22, -0.03), WHITE)
    for s in (-1, 1):
        for dy in (0.02, -0.06):
            a0 = p + V(s * 0.16, dy, 0.02)
            m.seg("Whisker", a0, a0 + V(s * 0.4, dy, 0.08), 0.012, (110, 76, 50))
    # cape streaming back with a gold clasp
    m.ell("Cape", (1.16, 0.12, 1.6), V(0, 1.42, 0.62), RED, "Fabric", R=rot(x=-24))
    for k in range(3):
        m.ell("Cape", (0.4, 0.12, 0.34), V(-0.36 + k * 0.36, 1.06 + (k % 2) * 0.06, 1.36), RED, "Fabric", R=rot(x=-30))
    m.seg("CapeTie", V(-0.36, 1.32, -0.22), V(0.36, 1.32, -0.22), 0.07, (255, 214, 60), "Metal")
    # pumping arms and sprinting legs
    m.arms2(1.2, 0.46, fur, 0.14, 0.13, 0.13, 0.16, paw,
            {1: (V(0.58, 1.02, -0.5), V(0.5, 1.28, -0.84), True), -1: (V(-0.6, 1.0, 0.26), V(-0.56, 1.2, 0.56), True)})
    for (s, knee, ank) in ((1, V(0.34, 0.54, 0.42), V(0.34, 0.42, 0.66)), (-1, V(-0.34, 0.62, -0.42), V(-0.34, 0.34, -0.52))):
        hip = V(s * 0.3, 0.76, 0.06)
        m.leg(hip, knee, ank, 0.16, 0.13, 0.12, fur)
        m.ell("Foot", (0.26, 0.14, 0.42), ank + V(0, -0.06, -0.12), paw)
    m.ball("Tail", 0.16, V(0, 0.82, 0.62), fur)
    # speed lines
    for (y, z, L) in ((0.74, 1.0, 0.5), (1.04, 1.18, 0.7), (1.34, 1.04, 0.4)):
        m.blk("Speed", (0.04, 0.04, L), V(0.66, y, z), WHITE, "Neon", tr=0.4)
    return m


# ------------------------------------------------------------------------------------------------
def pigeon_body(m, x, z, s=1.0, yaw=0.0, lead=False):
    """One plump pigeon in a leaf-green army helmet: an iridescent neck, orange feet, folded barred
    wings, a fanned tail and a dutiful face."""
    gray, gray_d, gray_l = (150, 156, 174), (110, 116, 138), (182, 186, 200)
    neck_g, neck_p = (86, 176, 132), (156, 100, 186)
    feet = (244, 128, 96)
    R = Ry(yaw)
    o = V(x, 0, z)

    def Pt(px, py, pz):
        return o + R @ V(px * s, py * s, pz * s)

    for k in (-1, 1):
        hip, ank = Pt(k * 0.2, 0.62, 0.06), Pt(k * 0.22, 0.12, -0.02)
        m.seg("Leg", hip, ank, 0.08 * s, feet, bulge=0.5)
        for t in (-1, 0, 1):
            m.seg("Toe", ank, Pt(k * 0.22 + t * 0.12, 0.05, -0.28), 0.045 * s, feet, bulge=0.4)
        m.seg("Toe", ank, Pt(k * 0.22, 0.05, 0.16), 0.04 * s, feet)
    m.ell("Body", (1.0 * s, 0.96 * s, 1.32 * s), Pt(0, 0.86, 0.12), gray, R=R @ rot(x=-10))
    m.ell("Chest", (0.78 * s, 0.7 * s, 0.5 * s), Pt(0, 0.98, -0.36), gray_l, R=R)
    m.ell("Neck", (0.72 * s, 0.56 * s, 0.7 * s), Pt(0, 1.32, -0.22), neck_g, R=R, refl=0.25)
    m.ell("Neck", (0.62 * s, 0.3 * s, 0.62 * s), Pt(0, 1.16, -0.28), neck_p, R=R, refl=0.25)
    hc, hs = Pt(0, 1.68, -0.36), (0.66 * s, 0.62 * s, 0.66 * s)
    m.ell("Head", hs, hc, gray, R=R)
    m.ell("Beak", (0.14 * s, 0.12 * s, 0.32 * s), hc + R @ V(0, -0.06 * s, -0.4 * s), (70, 66, 74), R=R)
    m.ell("Snoot", (0.13 * s, 0.08 * s, 0.12 * s), hc + R @ V(0, 0.03 * s, -0.3 * s), (240, 236, 230), R=R)
    m.eyes_on(hc, hs, R, 34, 10, 0.27 * s, 0.28 * s, gray, DUTIFUL, iris=(240, 120, 40), pupil_k=0.48, lidline=False)
    for k in (-1, 1):
        wc = Pt(k * 0.46, 0.9, 0.18)
        Rw = R @ rot(x=-14)
        m.ell("Wing", (0.18 * s, 0.66 * s, 0.98 * s), wc, gray_d, R=Rw)
        for j in (0, 1):
            m.ell("WingStripe", (0.06 * s, 0.1 * s, 0.5 * s), wc + R @ V(k * 0.08 * s, (0.04 - j * 0.16) * s, (0.1 + j * 0.06) * s), (58, 62, 78), R=Rw)
        m.ell("WingTip", (0.14 * s, 0.3 * s, 0.56 * s), Pt(k * 0.4, 0.66, 0.66), (84, 90, 108), R=R @ rot(x=-30))
    m.ell("Tail", (0.54 * s, 0.12 * s, 0.66 * s), Pt(0, 0.78, 0.86), gray_d, R=R @ rot(x=20))
    m.ell("Tail", (0.54 * s, 0.1 * s, 0.16 * s), Pt(0, 0.68, 1.12), (58, 62, 78), R=R @ rot(x=20))
    # leaf-green army helmet with a rim, rivets, camo spots and a chin strap
    hel = (90, 122, 64)
    hp = hc + R @ V(0, 0.22 * s, 0.02 * s)
    m.ell("Helmet", (0.84 * s, 0.5 * s, 0.84 * s), hp, hel, R=R)
    m.ell("HelmetRim", (0.96 * s, 0.08 * s, 0.96 * s), hp + V(0, -0.1 * s, 0), shade(hel, 0.8), R=R)
    for (dx, dz, c) in ((-0.18, -0.12, (66, 90, 46)), (0.2, 0.06, (120, 150, 80))):
        m.ell("Helmet", (0.26 * s, 0.08 * s, 0.2 * s), hp + R @ V(dx * s, 0.2 * s, dz * s), c, R=R @ rot(x=dz * 60, z=-dx * 60))
    m.seg("HelmetStrap", hp + R @ V(0.33 * s, -0.1 * s, -0.06 * s), hc + R @ V(0.22 * s, -0.24 * s, -0.12 * s), 0.025 * s, (60, 80, 44))
    if lead:
        m.ell("HelmetRivet", (0.18 * s, 0.18 * s, 0.05 * s), hp + R @ V(0, 0.08 * s, -0.42 * s), GOLD, "Metal", R=R @ rot(x=-24))


@model
def pigeon_squad():
    """Epic. Three plump pigeons in leaf-green army helmets marching in formation: the sergeant out
    front with gold stripes and a helmet star, the two privates with bread-crumb ammo belts, and a
    little squad flag. Mood: dutiful."""
    m = SModel("pigeon_squad")
    pigeon_body(m, 0.0, -0.78, 1.16, lead=True)
    pigeon_body(m, -1.08, 0.56, 1.0, yaw=8)
    pigeon_body(m, 1.08, 0.56, 1.0, yaw=-8)
    for k in range(2):
        for s in (-1, 1):
            m.blk("WingStripe", (0.06, 0.07, 0.3), V(s * 0.6, 1.14 - k * 0.12, -0.6), (250, 210, 60), R=rot(x=20))
    for (cx, cz, yaw) in ((-1.08, 0.56, 8), (1.08, 0.56, -8)):
        R = Ry(yaw)
        pts = [V(cx, 0, cz) + R @ V(-0.3 + t * 0.6, 1.16 - t * 0.36, -0.52 + abs(t - 0.5) * 0.12) for t in (0.0, 0.5, 1.0)]
        m.chain("Belt", pts, 0.08, LEATHER_D, joints=False)
        for t in (0.25, 0.5, 0.75):
            q = V(cx, 0, cz) + R @ V(-0.3 + t * 0.6, 1.16 - t * 0.36, -0.58 + abs(t - 0.5) * 0.12)
            m.blk("Crumb", (0.11, 0.1, 0.08), q, (226, 184, 112), R=rot(x=10, z=40 * t))
    fp = V(1.62, 0, 0.66)
    m.cyl("FlagStaff", 1.7, 0.07, fp + V(0, 0.85, 0), (204, 204, 214), "y", "Metal")
    m.ball("FlagTop", 0.14, fp + V(0, 1.74, 0), GOLD, "Metal")
    m.blk("Flag", (0.66, 0.44, 0.04), fp + V(0.34, 1.46, 0), RED, "Fabric", R=rot(y=-8))
    m.blk("Flag", (0.66, 0.1, 0.05), fp + V(0.34, 1.46, 0), WHITE, "Fabric", R=rot(y=-8))
    return m


@model
def pigeon_token():
    """Token. One plump helmeted pigeon. Mood: dutiful."""
    m = SModel("pigeon", kind="token")
    pigeon_body(m, 0.0, 0.0, 1.3)
    return m


# ------------------------------------------------------------------------------------------------
@model
def sergeant_snail():
    """Mythic. A drill-sergeant snail: a big hazel spiral shell armoured with riveted steel bands and
    gold sergeant chevrons, a campaign hat with a glowing star, eyes on stalks under bristling brows,
    a bushy mustache, medals and a whistle on a lanyard, on a glossy slimy foot. Mood: strict."""
    m = SModel("sergeant_snail")
    slime, slime_l = (172, 200, 124), (204, 226, 160)
    shell, shell_d = (184, 116, 66), (128, 76, 42)
    steel = (176, 182, 192)
    # the foot and a slime trail
    m.ell("Foot", (1.4, 0.64, 3.2), V(0, 0.32, 0.12), slime, refl=0.2)
    m.ell("Foot", (1.52, 0.2, 3.3), V(0, 0.12, 0.12), slime_l, refl=0.2)
    m.ell("Slime", (0.9, 0.05, 0.9), V(0, 0.03, 1.4), (196, 236, 176), "Glass", tr=0.35, refl=0.4)
    # neck and head
    m.seg("Neck", V(0, 0.4, -1.2), V(0, 1.86, -1.34), 0.58, slime, bulge=0.5, refl=0.15)
    hc, hs = V(0, 2.2, -1.4), (1.36, 1.18, 1.22)
    m.ell("Head", hs, hc, slime, refl=0.15)
    # eyes on stalks under heavy brows
    for s in (-1, 1):
        a0 = hc + V(s * 0.26, 0.34, -0.38)
        tip = a0 + V(s * 0.32, 0.64, -0.34)
        m.seg("Stalk", a0, tip, 0.12, slime, bulge=0.45, refl=0.15)
        m.ball("Eyeball", 0.5, tip, slime)
        n = norm(V(s * 0.25, 0.1, -1))
        m.eye(tip + n * 0.18, n, 0.42, 0.46, slime, STRICT, iris=(90, 120, 60), brow=(80, 60, 40), brow_k=1.25, sink=0.3)
    # bushy mustache, a frown and a nose bump
    p, n = on_ell_R(hc, hs, I3, Rx(-6) @ V(0, 0, -1))
    m.ball("Nose", 0.22, p, shade(slime, 0.92))
    for s in (-1, 1):
        a_ = p + V(s * 0.06, -0.12, -0.04)
        b_ = a_ + V(s * 0.38, -0.08, 0.1)
        m.seg("Mustache", a_, b_, 0.13, (96, 66, 44), bulge=0.4, ext=0.06)
        m.seg("Mustache", b_, b_ + V(s * 0.16, -0.16, 0.06), 0.08, (96, 66, 44), bulge=0.5)
    q, nq = on_ell_R(hc, hs, I3, Rx(-30) @ V(0, 0, -1))
    m.mouth(q, nq, 0.3, STRICT, color=(70, 44, 40), d=0.045)
    # campaign hat with a glowing gold star
    hat = (126, 140, 78)
    hp = hc + V(0, 0.58, 0.22)
    m.ell("HatBrim", (1.5, 0.08, 1.5), hp, hat, "Fabric")
    m.ell("HatCrown", (0.86, 0.6, 0.86), hp + V(0, 0.28, 0), hat, "Fabric")
    m.cyl("HatBand", 0.12, 0.88, hp + V(0, 0.08, 0), LEATHER_D, "y", "Leather")
    for a in (0, 90, 180, 270):
        t = math.radians(a)
        m.ell("HatDent", (0.2, 0.2, 0.14), hp + V(math.cos(t) * 0.34, 0.5, math.sin(t) * 0.34), shade(hat, 0.82), R=frame_normal(V(math.cos(t), 0.5, math.sin(t))))
    st = m.ell("HatPin", (0.2, 0.2, 0.06), hp + V(0, 0.16, -0.43), GOLD, "Neon")
    m.light(st, (255, 214, 120), 0.5, 4)
    # the shell: a big spiral, riveted steel bands and sergeant chevrons
    sc, sr = V(0, 1.82, 0.54), 1.22
    m.ball("Shell", 2 * sr, sc, shell)
    for s in (-1, 1):
        pts = []
        for k in range(15):
            t = k / 14
            ang = t * 1.8 * 2 * math.pi
            rho = 0.95 * (1 - t * 0.9)
            yy, zz = math.sin(ang) * rho, math.cos(ang) * rho
            xx = math.sqrt(max(sr * sr - yy * yy - zz * zz, 0.01))
            pts.append(sc + V(s * xx, yy, zz))
        m.chain("ShellSpiral", pts, 0.1, shell_d, joints=False)
        m.ball("ShellCenter", 0.3, pts[-1], shell_d)
    for x in (-0.46, 0.46):
        rr = math.sqrt(sr * sr - x * x)
        m.cyl("ShellBand", 0.22, 2 * rr + 0.08, sc + V(x, 0, 0), steel, "x", "Metal", refl=0.2)
        for k in range(5):
            a = math.radians(-70 + k * 45)
            m.ball("ShellRivet", 0.12, sc + V(x * 1.04, math.sin(a) * (rr + 0.05), -math.cos(a) * (rr + 0.05) + 0.0), shade(steel, 0.8), "Metal")
    for k in range(3):
        for o in (-1, 1):
            c = sc + V(sr * 0.94, 0.32 - k * 0.24, 0.36 + o * 0.17)
            m.blk("Chevron", (0.06, 0.1, 0.44), c, GOLD, "Fabric", R=rot(x=-o * 32))
    # medals and a whistle on a red lanyard
    for k, (dx, col) in enumerate(((-0.24, RED), (0.0, (60, 110, 200)), (0.24, LEAF))):
        p = V(dx, 1.1 - abs(dx) * 0.2, -1.86)
        m.blk("Medal", (0.12, 0.22, 0.04), p + V(0, 0.14, 0.01), col)
        m.cyl("Medal", 0.05, 0.2, p, GOLD, "z", "Metal")
    ln = [V(-0.5, 1.56, -1.5), V(-0.24, 1.4, -1.84), V(0.12, 1.4, -1.86), V(0.48, 1.56, -1.52)]
    m.chain("Lanyard", ln, 0.04, RED, joints=False)
    m.seg("Whistle", V(0.16, 1.36, -1.9), V(0.3, 1.26, -2.0), 0.08, steel, "Metal", shape="C")
    return m


# ------------------------------------------------------------------------------------------------
@model
def big_momma_moose():
    """Legendary. A massive warm-hearted moose: a deep chest and shoulder hump, a long gentle face with a
    big droopy nose, huge palmate antlers hung with flowers and bead strings, a flower garland round
    her neck, a dewlap, thick legs with knee tufts and big dark hooves, and fireflies. Mood: warm but
    mighty."""
    m = SModel("big_momma_moose")
    fur, fur_d, fur_l = (138, 92, 58), (96, 62, 40), (192, 152, 108)
    antler = (228, 206, 164)
    hoof = (58, 46, 40)
    # legs: thick thighs into knee tufts, slimmer pale shins, big hooves
    for s in (-1, 1):
        x = s * 0.64
        for (zh, zk, za, front) in ((-1.12, -1.2, -1.14, True), (1.32, 1.42, 1.3, False)):
            hip, knee, ank = V(x, 2.7, zh), V(x * 1.02, 1.52, zk - (0.06 if front else -0.08)), V(x * 1.03, 0.58, za)
            m.seg("Thigh", hip, knee, 0.44, fur, bulge=0.36, ext=0.1)
            m.ball("Knee", 0.5, knee, fur)
            m.seg("Shin", knee, ank, 0.22, fur_l, bulge=0.45, ext=0.05)
            m.tuft("Knee", knee + V(0, -0.02, 0.06), V(0, -0.4, 0.2 if front else -0.2), 0.36, 0.22, fur_d, n=2, spread=34)
            m.hoof((ank[0], ank[2] - 0.04), 0.36, hoof)
    # body: deep chest, barrel, rump, belly and the big shoulder hump with a mane
    m.ell("Chest", (2.06, 2.1, 1.9), V(0, 3.12, -1.0), fur)
    m.ell("Body", (1.9, 1.84, 2.7), V(0, 3.0, 0.3), fur)
    m.ell("Rump", (1.76, 1.72, 1.5), V(0, 2.96, 1.32), fur)
    m.ell("Belly", (1.5, 0.8, 2.6), V(0, 2.36, 0.1), fur_l)
    m.ell("Hump", (1.5, 1.2, 1.5), V(0, 4.0, -0.82), fur_d)
    for k in range(4):
        m.tuft("Mane", V(0, 4.5 - k * 0.12, -1.2 + k * 0.32), V(0, 1, 0.4), 0.42, 0.24, fur_d, n=2, spread=30)
    m.ball("Tail", 0.4, V(0, 3.3, 2.08), fur_d)
    # neck, dewlap and the long gentle head
    m.seg("Neck", V(0, 3.62, -1.4), V(0, 4.0, -2.22), 0.62, fur, bulge=0.5)
    Rh = rot(x=14)
    hc, hs = V(0, 4.1, -2.46), (1.12, 1.06, 1.46)
    m.ell("Head", hs, hc, fur, R=Rh)
    sn = hc + Rh @ V(0, -0.24, -0.84)
    m.ell("Snout", (0.96, 0.72, 0.92), sn, fur_l, R=Rh)
    for s in (-1, 1):
        m.ell("Nostril", (0.14, 0.1, 0.08), sn + Rh @ V(s * 0.2, -0.06, -0.44), (60, 40, 32), R=Rh)
    m.seg("Beard", hc + Rh @ V(0, -0.5, -0.1), hc + V(0, -1.1, -0.16), 0.16, fur_d, bulge=0.6)
    m.ball("Beard", 0.26, hc + V(0, -1.12, -0.16), fur_d)
    p, n = on_ell_R(sn, (0.96, 0.72, 0.92), Rh, Rh @ V(0, -0.6, -1))
    m.mouth(p + n * 0.01, n, 0.42, WARM, color=(70, 40, 34), d=0.05)
    m.eyes_on(hc, hs, Rh, 40, 34, 0.36, 0.38, fur, WARM, iris=(120, 76, 44), lash=3, brow=fur_d, brow_k=0.9)
    for s in (-1, 1):
        m.ear(hc + V(s * 0.4, 0.4, 0.28), hc + V(s * 1.0, 0.7, 0.4), 0.42, fur, inner=fur_l, facing=(s * 0.2, 0.3, -1))
    # huge palmate antlers with tines, flowers and bead strings
    rnd = random.Random(4)
    beads = [(80, 200, 210), RED, GOLD, (250, 250, 250)]
    petals = [(255, 140, 180), (255, 255, 255), (255, 200, 60), (230, 90, 120)]
    for s in (-1, 1):
        b0 = hc + V(s * 0.3, 0.5, 0.2)
        b1 = b0 + V(s * 0.62, 0.32, 0.08)
        m.seg("AntlerBase", b0, b1, 0.18, antler, bulge=0.4, ext=0.06)
        m.ball("AntlerBase", 0.34, b0, shade(antler, 0.85))
        pc = b1 + V(s * 0.9, 0.5, 0.1)
        Rp = rot(z=s * 26, y=-s * 10)
        m.ell("AntlerPalm", (2.36, 0.26, 1.36), pc, antler, R=Rp)
        m.ell("AntlerPalm", (1.76, 0.18, 0.92), pc + V(0, 0.07, 0), shade(antler, 1.06), R=Rp)
        for k in range(6):
            u = -0.9 + k * 0.36
            base = pc + Rp @ V(s * u * 0.6 + s * 0.24, 0.06, -0.52 + abs(u) * 0.14)
            tip = base + V(s * (0.14 + u * 0.18), 0.62 - abs(u) * 0.1, -0.14)
            m.seg("AntlerTine", base, tip, 0.12, antler, bulge=0.35, ext=0.04)
        for k, (u, w) in enumerate(((-0.3, -0.2), (0.25, 0.18), (0.62, -0.1))):
            fp = pc + Rp @ V(s * u, 0.14, w)
            flower(m, "Flower", fp, Rp @ V(0, 1, -0.4), 0.42, petals[(k + (s > 0)) % 4])
        for j, u in enumerate((0.1, 0.62)):
            top = pc + Rp @ V(s * u, -0.1, -0.3)
            for k in range(3):
                m.ball("Bead", 0.12, top + V(0, -0.16 - k * 0.16, -0.02 * k), beads[(j + k) % 4], "Glass" if k == 2 else "SmoothPlastic", refl=0.2)
    # a flower garland round her neck
    for k in range(10):
        a = math.radians(-160 + k * 34)
        gp = V(0, 3.62, -1.38) + V(math.sin(a) * 0.86, -abs(math.cos(a)) * 0.05 - 0.04, -math.cos(a) * 0.7)
        if k % 3 == 2:
            m.ell("Garland", (0.36, 0.14, 0.2), gp, LEAF, "Fabric", R=rot(y=-math.degrees(a)))
        else:
            flower(m, "Garland", gp, V(math.sin(a), 0.4, -math.cos(a)), 0.46, petals[k % 4])
    # fireflies
    for (fx, fy, fz) in ((1.6, 5.6, -1.8), (-1.9, 5.2, -2.4), (0.4, 5.8, -2.8)):
        fi = m.ball("Firefly", 0.12, V(fx, fy, fz), (230, 255, 120), "Neon")
    m.light(fi, (220, 255, 140), 0.5, 5)
    scale_all(m, 0.84)   # the antlers are huge: keep her inside one board tile
    return m


# ------------------------------------------------------------------------------------------------
@model
def captain_confetti():
    """Secret. A flamboyant macaw pirate captain: scarlet feathers with rainbow wings and a long rainbow
    tail, a navy coat with gold-foil trim, fringed gold epaulettes and buttons, a big tricorn with a
    glowing party star and a rainbow plume, a gold-foil confetti cannon blasting confetti, a peg leg,
    and long-lashed smug eyes. Mood: flamboyant."""
    m = SModel("captain_confetti")
    red, red_d = (232, 42, 52), (180, 28, 40)
    blue, green, yellow = (40, 112, 232), (60, 200, 120), (255, 210, 60)
    gold = (255, 206, 80)
    navy = (36, 46, 104)
    claw = (90, 90, 100)
    # legs: one scaly foot with parrot toes, one wooden peg leg with a gold band
    m.seg("Leg", V(-0.36, 1.1, 0.06), V(-0.38, 0.32, 0.0), 0.17, claw, bulge=0.45)
    for t in (-1, 1):
        m.seg("Toe", V(-0.38, 0.16, -0.04), V(-0.38 + t * 0.16, 0.08, -0.42), 0.07, claw, bulge=0.4)
        m.seg("Toe", V(-0.38, 0.16, 0.04), V(-0.38 + t * 0.12, 0.08, 0.32), 0.06, claw, bulge=0.4)
    m.ball("Foot", 0.3, V(-0.38, 0.18, 0.0), claw)
    m.seg("Leg", V(0.36, 1.1, 0.06), V(0.38, 0.62, 0.02), 0.17, claw, bulge=0.45)
    m.seg("Leg", V(0.38, 0.66, 0.02), V(0.4, 0.04, 0.0), 0.12, WOOD, "Wood", r2=0.12, shape="C")
    m.cyl("Leg", 0.1, 0.3, V(0.39, 0.6, 0.02), gold, "y", "Foil")
    m.cyl("Leg", 0.08, 0.2, V(0.4, 0.04, 0.0), WOOD_D, "y", "Wood")
    # body with layered chest feathers
    m.ell("Body", (1.54, 2.06, 1.46), V(0, 1.88, 0.12), red)
    rnd = random.Random(2)
    for k in range(3):
        for j in range(3 - k % 2):
            fx, fy = -0.26 + j * 0.26 + (k % 2) * 0.13, 1.96 - k * 0.3
            p, n = on_ell_R(V(0, 1.88, 0.12), (1.54, 2.06, 1.46), I3, V(fx, fy - 1.88, -0.72))
            m.ell("ChestFeather", (0.32, 0.24, 0.1), p + n * 0.01, (255, 120, 90) if (j + k) % 2 else red, R=frame_normal(n))
    # navy captain's coat, open at the front, gold-foil trim, buttons, epaulettes and coat tails
    for s in (-1, 1):
        R = rot(y=s * 32, z=-s * 4)
        m.ell("Coat", (0.9, 1.5, 1.4), V(s * 0.42, 2.04, 0.22), navy, "Fabric", R=R)
        m.ell("CoatTrim", (0.12, 1.42, 0.14), V(s * 0.46, 2.02, -0.5), gold, "Foil", R=rot(z=-s * 8))
        for k in range(3):
            m.ball("Button", 0.12, V(s * 0.56, 2.34 - k * 0.26, -0.48 + k * 0.02), gold, "Foil")
        m.ell("Coat", (0.5, 1.5, 0.16), V(s * 0.32, 1.06, 0.84), navy, "Fabric", R=rot(x=18, z=s * 6))
        m.ell("CoatTrim", (0.52, 0.1, 0.18), V(s * 0.32, 0.36, 1.06), gold, "Foil", R=rot(x=18))
        ep = V(s * 0.72, 2.76, 0.06)
        m.ell("CoatEpaulet", (0.62, 0.2, 0.62), ep, gold, "Foil", R=rot(z=-s * 14))
        for k in range(5):
            a = math.radians(k * 36 - 72 + (90 if s > 0 else -90))
            q = ep + V(math.sin(a) * 0.26 + s * 0.04, -0.14, math.cos(a) * 0.26 * -1)
            m.seg("CoatEpaulet", q, q + V(s * 0.02, -0.22, 0), 0.035, shade(gold, 0.9), "Foil")
    m.ell("Belt", (1.52, 0.18, 1.38), V(0, 1.4, 0.12), (60, 40, 30), "Leather")
    m.blk("Belt", (0.3, 0.24, 0.06), V(0, 1.4, -0.58), gold, "Foil")
    for k, x in enumerate((-0.34, -0.5, 0.42)):
        m.cyl("Coin", 0.05, 0.2, V(x, 1.22 - k * 0.04, -0.52 + abs(x) * 0.18), gold, "z", "Foil", R=rot(y=x * 40))
    # a rainbow sash with a gold medallion across the chest
    bc_, bs_ = V(0, 1.88, 0.12), (1.54, 2.06, 1.46)
    for j, col in enumerate(((255, 120, 200), (255, 220, 70), (120, 230, 130), (90, 200, 255), (180, 120, 255))):
        o = (j - 2) * 0.07
        pts = []
        for t in (0.0, 0.5, 1.0):
            X, Y = 0.5 - t * 0.96 + o * 0.5, 0.66 - t * 0.9 + o
            pp, nn = on_ell_R(bc_, bs_, I3, V(X, Y, -0.72))
            pts.append(pp + nn * 0.03)
        m.chain("Sash", pts, 0.08, col, "Fabric", joints=False)
    pp, nn = on_ell_R(bc_, bs_, I3, V(0.02, 0.2, -0.72))
    m.cyl("Sash", 0.06, 0.3, pp + nn * 0.06, gold, "x", "Foil", R=frame_from_x(nn))
    m.ball("Sash", 0.14, pp + nn * 0.1, (255, 90, 160), "Glass", refl=0.3)
    # head with the white face patch, hooked beak and smug long-lashed eyes
    hc, hs = V(0, 3.24, -0.14), (1.32, 1.3, 1.28)
    m.ell("Head", hs, hc, red)
    p, n = on_ell_R(hc, hs, I3, V(0, -0.05, -1))
    m.ell("FacePatch", (0.96, 0.82, 0.36), p + n * -0.08, (255, 246, 238), R=frame_normal(n))
    for s in (-1, 1):
        for k in range(3):
            m.ell("Freckle", (0.08, 0.04, 0.03), p + V(s * (0.2 + k * 0.08), -0.16 + (k % 2) * 0.06, 0.04), (226, 170, 170), R=frame_normal(n))
    m.eyes_on(hc, hs, I3, 30, 10, 0.4, 0.42, (255, 246, 238), FLAMBOYANT, iris=(250, 200, 50), lash=3, brow=INK, brow_k=0.9)
    horn = (234, 224, 204)
    b0, b1, b2 = hc + V(0, -0.02, -0.56), hc + V(0, -0.2, -0.96), hc + V(0, -0.6, -0.9)
    m.seg("Beak", b0, b1, 0.25, horn, bulge=0.38, ext=0.06)
    m.seg("Beak", b1 + V(0, 0.06, 0.02), b2 + V(0, 0.12, -0.02), 0.17, horn, bulge=0.3)
    m.seg("BeakTip", lerp(b1, b2, 0.55), b2, 0.1, INK, bulge=0.35)
    m.ell("Beak", (0.36, 0.26, 0.34), hc + V(0, -0.44, -0.62), (50, 50, 58))
    m.ell("Nostril", (0.06, 0.04, 0.03), b0 + V(0.08, 0.08, -0.16), (120, 110, 100))
    # red crest feathers fanning out behind the hat, and a gold earring
    for k in (-1, 0, 1):
        q = hc + V(k * 0.18, 0.24, 0.5)
        m.seg("Feather", q, q + V(k * 0.22, 0.4, 0.42), 0.12, (255, 96, 70) if k else red, bulge=0.35)
    er = hc + V(0.66, -0.2, 0.06)
    m.cyl("Feather", 0.05, 0.26, er, gold, "x", "Foil")
    m.cyl("Feather", 0.06, 0.14, er, red_d, "x")
    # tricorn with gold-foil trim, a glowing party star and a rainbow plume
    hat = (30, 30, 42)
    hp = hc + V(0, 0.66, 0.02)
    m.cyl("Hat", 0.44, 1.36, hp, hat, "y", "Fabric")
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        c = hp + V(math.cos(a) * 0.46, -0.1, -math.sin(a) * 0.46)
        m.ell("HatCorner", (1.3, 0.36, 0.5), c, hat, "Fabric", R=rot(y=-math.degrees(a)))
        m.ell("HatTrim", (1.32, 0.08, 0.1), c + V(math.cos(a) * 0.18, 0.12, -math.sin(a) * 0.18), gold, "Foil", R=rot(y=-math.degrees(a)))
    m.cyl("HatTrim", 0.1, 1.42, hp + V(0, -0.2, 0), gold, "y", "Foil")
    star = m.ell("HatStar", (0.36, 0.36, 0.1), hp + V(0, 0.06, -0.74), (255, 232, 90), "Neon")
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 2
        m.wedge("HatStar", (0.06, 0.16, 0.08), hp + V(math.cos(a) * 0.2, 0.06 + math.sin(a) * 0.2, -0.76), (255, 232, 90), "Neon", R=rot(z=math.degrees(a) - 90))
    for k, col in enumerate(((255, 90, 200), (120, 220, 255), (255, 220, 70), (140, 240, 140), (200, 130, 255))):
        b = hp + V(0.36, 0.16, 0.12)
        m.seg("HatFeather", b, b + V(0.24 + k * 0.12, 0.96 - k * 0.12, 0.16 + k * 0.08), 0.12 - k * 0.012, col, bulge=0.45)
    # wings: the left folded and rainbow-layered, the right swinging the confetti cannon
    for s in (-1, 1):
        wc = V(s * 0.86, 1.92, 0.24)
        R = rot(z=s * 10)
        m.ell("Wing", (0.36, 1.62, 1.02), wc, blue, R=R)
        for k in range(4):
            m.ell("Wing", (0.2, 0.56, 0.34), wc + V(s * 0.1, 0.06 - k * 0.22, -0.34 + k * 0.22), shade(blue, 1.15 if k % 2 else 0.9), R=R @ rot(x=-20))
        m.ell("WingTip", (0.3, 0.92, 0.7), V(s * 0.96, 1.12, 0.52), green, R=R)
        m.ell("WingStripe", (0.22, 0.36, 0.42), V(s * 0.99, 0.74, 0.64), yellow, R=R)
        m.ell("WingStripe", (0.14, 0.2, 0.3), V(s * 1.0, 0.5, 0.72), red, R=R)
        m.ell("WingStripe", (0.4, 0.12, 0.9), wc + V(s * 0.04, 0.66, 0.0), gold, "Foil", R=R)
    cb, cm = V(1.06, 2.12, -0.4), V(1.32, 2.7, -1.2)
    m.seg("Cannon", cb, cm, 0.26, gold, "Foil", shape="C", ext=0.06)
    m.ball("Cannon", 0.5, cb, gold, "Foil")
    for t in (0.3, 0.65):
        q = lerp(cb, cm, t)
        m.seg("CannonRing", q - norm(cm - cb) * 0.04, q + norm(cm - cb) * 0.04, 0.3, (255, 130, 200), "Foil", shape="C")
    mouth = m.seg("CannonMouth", cm - norm(cm - cb) * 0.06, cm + norm(cm - cb) * 0.14, 0.34, gold, "Foil", shape="C")
    m.seg("CannonMouth", cm + norm(cm - cb) * 0.1, cm + norm(cm - cb) * 0.16, 0.26, INK, shape="C")
    cols = [(255, 80, 120), (80, 200, 255), (255, 230, 70), (120, 230, 120), (200, 120, 255), (255, 150, 60)]
    rnd = random.Random(9)
    d = norm(cm - cb)
    for k in range(24):
        t = 0.22 + k * 0.035
        q = cm + d * t + V(rnd.uniform(-0.42, 0.42) * t, rnd.uniform(-0.1, 0.4) * t, rnd.uniform(-0.12, 0.12) * t)
        m.blk("Confetti", (0.12, 0.06, 0.02), q, cols[k % 6], "Neon" if k % 4 == 0 else "SmoothPlastic", R=rot(rnd.uniform(0, 180), rnd.uniform(0, 180), rnd.uniform(0, 180)))
    for j in range(3):
        a = j * 2.1
        pts = [cm + d * (0.25 + t * 0.28) + V(math.cos(a + t * 3) * 0.1 * t, 0.1 * t + math.sin(a + t * 3) * 0.1 * t, 0) for t in (0, 1, 2, 3)]
        m.chain("Confetti", pts, 0.05, cols[(j * 2) % 6], joints=False)
    m.confetti(star)
    m.confetti(mouth)
    # the long rainbow tail
    for k, (col, nm, L) in enumerate(((red, "Tail", 1.7), (blue, "Tail", 1.9), (yellow, "Tail2", 1.6), (green, "TailTip", 1.4), ((180, 120, 255), "Tail2", 1.3), (255, 120, 200) and ((255, 140, 60), "TailTip", 1.2))):
        a = -0.5 + k * 0.2
        L *= 0.88
        m.ell(nm, (0.32, 0.12, L), V(a * 0.9, 0.86 - k * 0.04, 1.06 + L * 0.2), col, R=rot(x=52, y=a * 30))
    m.sparkles(star, (255, 220, 255))
    return m
