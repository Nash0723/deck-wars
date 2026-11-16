# Snack family: glossy sweets and comfort food with a lot of attitude.
# Palette: caramel gold (main), frosting cream (secondary), cherry red (accent).
# Materials: glossy glaze (a little reflectance), sugar and salt (sand), foil wrappers.
import math
import random
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal
from stylekit import SModel, PAL, V, norm, on_ell_R, INK, GOLD, SILVER

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


P = PAL["Snack"]
CARAMEL = P["main"]
CREAM = P["second"]
CHERRY = P["accent"]
PINK = P["pink"]
MINT = P["mint"]
CHOC = P["choc"]
GLAZE = P["glaze"]
BLUSH = (255, 150, 170)
LEATHER = (150, 96, 56)
STEEL = (200, 206, 216)


def cheeks(m, c, s_, R, sep, y, d, color=BLUSH):
    for s in (-1, 1):
        p, n = on_ell_R(c, s_, R, R @ V(s * sep, y, -1))
        m.ell("Cheek", (d, d * 0.58, d * 0.3), p + n * 0.01, color, R=frame_normal(n))


def sprinkles(m, c, size, n, seed, colors=None, ymin=0.15, d=0.07):
    m.scatter("Sprinkle", c, size, n, colors or [(255, 90, 120), (90, 200, 255), (255, 230, 90), (140, 230, 140), WHITE],
              seed=seed, d=d, ymin=ymin, shape="sprinkle", length=2.8)


# ------------------------------------------------------------------------------------------------
@model
def jelly_bean_scout():
    """Common. A glossy kidney-bean scout leaning eagerly forward: saluting under a campaign hat, a
    cherry neckerchief, a badge sash, a canteen and a little backpack, stubby legs in hiking boots.
    Mood: eager."""
    m = SModel("jelly_bean_scout")
    bean = PINK
    m.ell("Body", (1.56, 1.42, 1.28), (0, 1.36, 0.06), bean, refl=GLAZE)
    hc, hs, HR = V(0, 2.08, -0.1), (1.46, 1.36, 1.22), rot(x=-12)
    m.ell("Head", hs, hc, bean, R=HR, refl=GLAZE)
    # face
    m.eyes_on(hc, hs, HR, 22, 10, 0.4, 0.46, bean, "eager", iris=CHOC, brow=CHOC, brow_k=0.8)
    p, n = on_ell_R(hc, hs, HR, HR @ V(0, -0.34, -1))
    m.mouth(p, n, 0.36, "eager", skin=bean)
    cheeks(m, hc, hs, HR, 0.62, -0.22, 0.24)
    # campaign hat with a cherry band and a gold badge
    hat = hc + HR @ V(0, 0.66, 0.02)
    m.ell("HatBrim", (1.66, 0.08, 1.56), hat, (204, 164, 104), R=HR)
    m.ell("Hat", (0.84, 0.56, 0.8), hat + HR @ V(0, 0.26, 0), (214, 176, 116), R=HR)
    m.ell("HatDent", (0.12, 0.2, 0.56), hat + HR @ V(0, 0.5, 0), (186, 146, 92), R=HR)
    m.cyl("HatBand", 0.12, 0.86, hat + HR @ V(0, 0.08, 0), CHERRY, "y", R=HR)
    m.cyl("CapBadge", 0.05, 0.2, hat + HR @ V(0, 0.1, -0.43), GOLD, "z", "Metal", R=HR)
    # cherry neckerchief: a knot under the chin and a flap down the chest
    for k in range(5):
        a1, a2 = math.radians(205 + k * 26), math.radians(231 + k * 26)
        p1 = V(math.cos(a1) * 0.7, 1.72, 0.05 + math.sin(a1) * 0.56)
        p2 = V(math.cos(a2) * 0.7, 1.72, 0.05 + math.sin(a2) * 0.56)
        m.seg("Scarf", p1, p2, 0.11, CHERRY, "Fabric", ext=0.05)
    m.ell("Scarf", (0.44, 0.52, 0.1), V(0, 1.44, -0.64), CHERRY, "Fabric", R=rot(x=-16))
    m.cyl("Scarf", 0.12, 0.17, V(0, 1.66, -0.56), GOLD, "y", "Metal")
    # mint sash with merit badges
    bc_, bs_ = V(0, 1.36, 0.06), (1.56, 1.42, 1.28)
    pts = [on_ell_R(bc_, bs_, I3, V(x, y, -1)) for (x, y) in [(0.75, 0.42), (0.3, 0.1), (-0.2, -0.25), (-0.7, -0.5)]]
    for (a, na), (b, nb) in zip(pts, pts[1:]):
        m.seg("Sash", a + na * 0.03, b + nb * 0.03, 0.1, MINT, "Fabric", r2=0.04, ext=0.06)
    for k, col in enumerate([GOLD, (90, 170, 250), CHERRY]):
        q, nq = pts[1][0] + (pts[2][0] - pts[1][0]) * (0.1 + k * 0.42), pts[1][1]
        m.cyl("Badge", 0.05, 0.17, q + nq * 0.07, col, "z", R=frame_normal(nq) @ Ry(90) @ Ry(-90))
    # arms: the right one salutes at the brim, the left holds the canteen strap
    m.arms2(1.74, 0.7, bean, 0.16, 0.14, 0.15, 0.18, CREAM,
            {1: ((1.08, 2.12, -0.22), (0.7, 2.56, -0.66), False), -1: ((-0.98, 1.3, 0.02), (-0.84, 1.04, -0.36), True)},
            z=-0.05, refl=GLAZE)
    # canteen at the hip
    m.cyl("Canteen", 0.18, 0.46, V(-0.86, 0.98, 0.28), (176, 184, 192), "x", "Metal")
    m.cyl("Canteen", 0.2, 0.3, V(-0.86, 0.98, 0.28), MINT, "x", "Fabric")
    m.cyl("Canteen", 0.1, 0.1, V(-0.86, 1.24, 0.28), (70, 70, 80), "y")
    # a little backpack with a rolled mat
    m.ell("Backpack", (0.96, 0.9, 0.44), V(0, 1.55, 0.7), (110, 150, 90), "Fabric")
    m.cyl("Backpack", 0.98, 0.28, V(0, 2.06, 0.74), (200, 120, 80), "x", "Fabric")
    # stubby legs in hiking boots with cream socks
    m.legs2(0.95, 0.3, bean, 0.17, 0.14, 0.14, 0.44, 0.64, LEATHER, sole=(70, 50, 40), cuff=CREAM, refl=GLAZE)
    return m


# ------------------------------------------------------------------------------------------------
@model
def pretzel_guard():
    """Common. A soft-pretzel guard: a pretzel knot on his dough chest, a bun head with a mustache, a
    round steel helmet with a cherry plume, a pretzel-stick spear and a cracker shield. Mood: stern."""
    m = SModel("pretzel_guard")
    dough = (204, 132, 64)
    crust = (170, 96, 42)
    salt = (250, 246, 236)
    bc, bs = V(0, 1.62, 0.05), (1.4, 1.42, 1.08)
    # a cherry-red guard's tunic with a gold trim; the pretzel knot is the emblem on the chest
    m.ell("Body", bs, bc, CHERRY, "Fabric")
    m.ell("Tunic", (1.46, 0.16, 1.14), bc + V(0, -0.5, 0), GOLD, "Fabric")
    m.ell("Tunic", (0.92, 0.2, 0.74), bc + V(0, 0.64, 0), GOLD, "Fabric")
    # the pretzel knot on the chest: a heart-shaped loop with a twist inside
    heart = [(0, -0.5), (-0.36, -0.36), (-0.52, -0.04), (-0.42, 0.28), (-0.18, 0.36), (0, 0.2),
             (0.18, 0.36), (0.42, 0.28), (0.52, -0.04), (0.36, -0.36), (0, -0.5)]
    twist = [[(0, 0.2), (-0.08, 0.0), (0.28, -0.3)], [(0, 0.2), (0.08, 0.0), (-0.28, -0.3)]]

    def on_chest(x, y):
        p, n = on_ell_R(bc, bs, I3, V(x * 1.45, y * 1.35 + 0.05, -1))
        return p + n * 0.1

    for a, b in zip(heart, heart[1:]):
        m.seg("Pretzel", on_chest(*a), on_chest(*b), 0.15, crust, ext=0.06, refl=GLAZE)
    for strand in twist:
        for a, b in zip(strand, strand[1:]):
            m.seg("Pretzel", on_chest(*a) + V(0, 0, -0.04), on_chest(*b) + V(0, 0, -0.04), 0.14, crust, ext=0.05, refl=GLAZE)
    rnd = random.Random(3)
    for k in range(12):
        a = heart[rnd.randrange(len(heart) - 1)]
        q = on_chest(a[0] + rnd.uniform(-0.04, 0.04), a[1] + rnd.uniform(-0.04, 0.04)) + V(0, 0.08, -0.1)
        m.blk("Salt", (0.08, 0.08, 0.08), q, salt, "Sand", R=rot(rnd.uniform(0, 90), rnd.uniform(0, 90), 0))
    # belt
    m.cyl("Belt", 0.16, 1.34, V(0, 1.1, 0.05), (70, 44, 30), "y", "Leather")
    m.blk("Buckle", (0.24, 0.2, 0.06), V(0, 1.12, -0.64), GOLD, "Metal")
    # bun head with scored crust and salt
    hc, hs = V(0, 2.7, -0.04), (1.02, 0.92, 0.96)
    m.ell("Head", hs, hc, dough, refl=GLAZE)
    m.eyes_on(hc, hs, I3, 22, 4, 0.3, 0.34, dough, "stern", iris=(70, 130, 60), brow=CHOC, brow_k=1.0)
    p, n = on_ell_R(hc, hs, I3, V(0, -0.36, -1))
    m.mouth(p, n, 0.24, "stern", color=(70, 36, 24), d=0.04)
    for s in (-1, 1):
        q, nq = on_ell_R(hc, hs, I3, V(s * 0.12, -0.22, -1))
        m.seg("Mustache", q + nq * 0.06, q + nq * 0.03 + V(s * 0.3, -0.06, 0.06), 0.08, CHOC, bulge=0.3)
    m.ell("Nose", (0.2, 0.18, 0.16), on_ell_R(hc, hs, I3, V(0, -0.1, -1))[0] + V(0, 0, -0.04), shade(dough, 1.08))
    # helmet: a round steel kettle hat with a brim, a crest ridge and a cherry plume
    hm = hc + V(0, 0.36, 0.02)
    m.ell("Helmet", (1.1, 0.66, 1.06), hm, STEEL, "Metal", refl=0.1)
    m.ell("HelmetRim", (1.42, 0.09, 1.36), hm + V(0, -0.12, 0), shade(STEEL, 0.9), "Metal")
    m.seg("HelmetRidge", hm + V(0, 0.3, -0.42), hm + V(0, 0.33, 0.42), 0.05, shade(STEEL, 1.1), "Metal")
    for k, (dz, dy, L) in enumerate([(-0.05, 0.0, 0.5), (0.1, -0.04, 0.45), (0.24, -0.1, 0.4)]):
        base = hm + V(0, 0.32, dz)
        m.seg("Plume", base, base + V(0, 0.3 + dy, 0.28 + k * 0.08), 0.1 - k * 0.012, shade(CHERRY, 1 + k * 0.08), "Fabric", bulge=0.35)
    # arms: a pretzel-stick spear in the right hand, a cracker shield on the left
    hands = m.arms2(1.98, 0.66, dough, 0.16, 0.14, 0.15, 0.17, CREAM,
                    {1: ((0.98, 1.55, -0.12), (0.92, 1.28, -0.5), True), -1: ((-0.95, 1.6, -0.12), (-0.78, 1.38, -0.58), True)},
                    z=0.0, refl=GLAZE)
    sp = hands[1]
    m.seg("Spear", sp + V(0, -1.2, 0.05), sp + V(0, 1.85, -0.05), 0.06, (196, 120, 56), shape="C")
    for k in range(6):
        m.ball("SpearSeed", 0.05, sp + V(0.05 * (1 if k % 2 else -1), -0.9 + k * 0.48, -0.03), salt, "Sand")
    m.crystal("SpearTip", sp + V(0, 1.84, -0.05), V(0, 1, 0), 0.42, 0.14, STEEL, mat="Metal", tr=0, refl=0.2)
    m.cyl("SpearBand", 0.1, 0.16, sp + V(0, 1.8, -0.05), GOLD, "y", "Metal")
    sh = hands[-1] + V(-0.12, 0.05, -0.18)
    m.blk("Shield", (0.08, 0.92, 0.92), sh, (232, 194, 124), R=rot(y=-18))
    for iy in (-1, 1):
        for iz in (-1, 1):
            m.ell("ShieldRim", (0.1, 0.22, 0.22), sh + rot(y=-18) @ V(0, iy * 0.36, iz * 0.36), (240, 206, 140), R=rot(y=-18))
    for (yy, zz) in [(-0.2, -0.2), (-0.2, 0.2), (0.2, -0.2), (0.2, 0.2), (0, 0)]:
        m.ell("ShieldGrid", (0.06, 0.07, 0.07), sh + rot(y=-18) @ V(-0.05, yy, zz), (176, 130, 70), R=rot(y=-18))
    # legs in leather boots with steel shin plates
    ank = m.legs2(1.0, 0.3, dough, 0.17, 0.15, 0.15, 0.44, 0.62, (92, 58, 36), sole=(52, 40, 34), refl=GLAZE)
    for a in ank:
        m.ell("ShinPlate", (0.26, 0.3, 0.1), a + V(0, 0.25, -0.13), STEEL, "Metal")
    return m


# ------------------------------------------------------------------------------------------------
@model
def pancake_paladin():
    """Rare. A knight made of three fat pancakes with syrup running down, a butter-pat helmet with a
    strawberry plume, steel pauldrons, gauntlets and greaves, a fork lance, a waffle shield and a
    cherry cape. Mood: noble."""
    m = SModel("pancake_paladin")
    cake = (228, 162, 76)
    edge = (186, 116, 48)
    top = (242, 196, 118)
    syrup = (176, 82, 24)
    stack = [(0.98, 1.76, "Pancake"), (1.42, 1.86, "Pancake"), (1.88, 1.72, "Head")]
    for (y, d, nm) in stack:
        m.ell(nm, (d * 1.04, 0.46, d * 1.04), V(0, y, 0), edge, refl=GLAZE)
        m.cyl(nm if nm != "Head" else "Pancake", 0.4, d, V(0, y + 0.02, 0), cake, "y", refl=GLAZE)
        m.cyl("Pancake", 0.04, d * 0.94, V(0, y + 0.22, 0), top, "y")
    # syrup pooled on top and running down
    m.ell("Syrup", (1.5, 0.12, 1.42), V(0, 2.12, 0), syrup, "Glass", tr=0.1, refl=0.35)
    for k, (a, L) in enumerate([(200, 0.55), (250, 0.9), (290, 0.4), (330, 0.75), (20, 0.5), (120, 0.8), (160, 0.45)]):
        r = 0.86
        x, z = math.cos(math.radians(a)) * r, math.sin(math.radians(a)) * r
        m.drip("Syrup", (x, 2.1, z), L, 0.13, syrup, "Glass", refl=0.35)
    # noble face on the top pancake's rim
    fy = 1.86
    for s in (-1, 1):
        d = norm(V(s * 0.38, 0.0, -1))
        pe = V(d[0] * 0.86, fy + 0.02, d[2] * 0.86)
        m.eye(pe, d, 0.28, 0.34, edge, "regal", iris=(70, 120, 200))
    m.mouth(V(0, 1.68, -0.87), V(0, 0, -1), 0.3, "regal", color=(110, 50, 30), d=0.045)
    for s in (-1, 1):
        m.ell("Cheek", (0.2, 0.11, 0.06), V(s * 0.52, 1.72, -0.72), BLUSH, R=frame_normal(V(s * 0.6, 0, -0.8)))
    # butter-pat helmet with a visor line and a strawberry plume
    m.rbox("Helmet", (0.92, 0.34, 0.92), (0, 2.34, 0), (255, 232, 150), 0.12, refl=0.15)
    m.blk("Visor", (0.94, 0.05, 0.05), (0, 2.3, -0.47), (230, 200, 110))
    sb = V(0, 2.82, 0.02)
    m.ell("Plume", (0.5, 0.62, 0.5), sb, (226, 40, 54), refl=0.15)
    for k in range(8):
        a = k * 2.4
        q, nq = on_ell_R(sb, (0.5, 0.62, 0.5), I3, V(math.cos(a), (k % 3 - 1) * 0.5, math.sin(a)))
        m.ell("Plume", (0.04, 0.06, 0.03), q, (255, 230, 120), R=frame_normal(nq))
    for k in range(4):
        a = math.radians(45 + k * 90)
        m.ell("PlumeTop", (0.36, 0.06, 0.16), sb + V(math.cos(a) * 0.15, 0.3, math.sin(a) * 0.15), (90, 170, 70), R=rot(y=-math.degrees(a), z=18))
    # arms in steel pauldrons and gauntlets: a fork lance and a waffle shield
    hands = m.arms2(1.5, 0.92, cake, 0.16, 0.14, 0.15, 0.18, STEEL,
                    {1: ((1.3, 1.15, -0.1), (1.18, 0.98, -0.52), True), -1: ((-1.28, 1.2, -0.12), (-1.08, 1.12, -0.6), True)},
                    refl=GLAZE, cuff=STEEL)
    for s in (-1, 1):
        m.ell("Pauldron", (0.6, 0.36, 0.62), V(s * 0.98, 1.66, 0), STEEL, "Metal", R=rot(z=s * -24))
        m.ball("PauldronRivet", 0.08, V(s * 1.12, 1.75, -0.24), GOLD, "Metal")
    fk = hands[1]
    m.seg("ForkHandle", fk + V(0, -0.85, 0.08), fk + V(0, 1.2, -0.06), 0.07, SILVER, "Metal", shape="C")
    m.ball("ForkPommel", 0.17, fk + V(0, -0.88, 0.08), GOLD, "Metal")
    m.ell("ForkNeck", (0.42, 0.26, 0.1), fk + V(0, 1.3, -0.07), SILVER, "Metal")
    for k in range(4):
        x = -0.15 + k * 0.1
        m.seg("ForkTine", fk + V(x, 1.36, -0.07), fk + V(x * 1.1, 1.95, -0.08), 0.03, SILVER, "Metal", shape="C")
    ws = hands[-1] + V(-0.16, 0.06, -0.16)
    Rw = rot(y=-20) @ rot(z=90)
    m.cyl("Shield", 0.14, 1.06, ws, (232, 176, 84), "x", R=rot(y=-20))
    m.cyl("ShieldRim", 0.1, 1.14, ws + rot(y=-20) @ V(0.02, 0, 0), (196, 132, 56), "x", R=rot(y=-20))
    for k in (-2, -1, 0, 1, 2):
        L = 0.95 * math.sqrt(max(0.0, 1 - (k * 0.19 / 0.5) ** 2))
        m.blk("ShieldGrid", (0.06, 0.06, L), ws + rot(y=-20) @ V(-0.07, k * 0.19, 0), (206, 146, 64), R=rot(y=-20))
        m.blk("ShieldGrid", (0.06, L, 0.06), ws + rot(y=-20) @ V(-0.07, 0, k * 0.19), (206, 146, 64), R=rot(y=-20))
    # a cherry cape behind the stack
    m.ell("Cape", (1.7, 1.6, 0.18), V(0, 1.26, 0.88), CHERRY, "Fabric", R=rot(x=8))
    m.seg("Cape", V(-0.8, 1.96, 0.72), V(0.8, 1.96, 0.72), 0.08, GOLD, "Metal")
    # blueberries on the stack
    for (a, y) in [(220, 1.42), (300, 0.98), (40, 1.44), (140, 1.0)]:
        x, z = math.cos(math.radians(a)) * 0.92, math.sin(math.radians(a)) * 0.92
        m.ball("Blueberry", 0.2, (x, y, z), (70, 70, 150), refl=0.1)
    # armoured legs: steel knee pads, greaves and sabatons
    ank = m.legs2(0.78, 0.36, cake, 0.18, 0.15, 0.15, 0.46, 0.66, STEEL, sole=(90, 94, 104), toe=shade(STEEL, 1.08),
                  knee_color=STEEL, refl=GLAZE)
    for a in ank:
        m.ell("Greave", (0.3, 0.32, 0.3), a + V(0, 0.2, -0.02), STEEL, "Metal")
    return m


# ------------------------------------------------------------------------------------------------
@model
def hot_sauce_imp():
    """Rare. A curvy hot-sauce bottle imp: a cream label with a chili, a screw cap worn like a hat with
    a flame on top, little horns, a pointed tail, clawed hands and a fanged grin. Mood: mischievous."""
    m = SModel("hot_sauce_imp")
    red = (214, 40, 46)
    dark = (140, 24, 34)
    # a curvy bottle: a round belly, sloping shoulders (the head), a long neck and a screw cap
    m.ell("Body", (1.26, 1.22, 1.14), V(0, 0.96, 0), red, refl=0.18)
    hc, hs = V(0, 1.66, -0.02), (1.06, 0.92, 0.98)
    m.ell("Head", hs, hc, red, refl=0.18)
    m.seg("Neck", V(0, 1.86, 0), V(0, 2.42, 0), 0.22, red, bulge=0.25, refl=0.18)
    m.ell("Sheen", (0.1, 0.5, 0.05), V(-0.42, 1.0, -0.42), (255, 150, 150), R=rot(y=45), tr=0.25)
    # label with a chili pepper and flame stripes
    m.ell("Label", (1.3, 0.52, 1.18), V(0, 0.92, 0), CREAM)
    for y in (0.66, 1.18):
        m.ell("Label", (1.22, 0.07, 1.1), V(0, y, 0), (255, 150, 40))
    m.seg("Chili", V(-0.18, 1.0, -0.6), V(0.16, 0.84, -0.62), 0.09, red, bulge=0.35)
    m.seg("Chili", V(-0.2, 1.0, -0.6), V(-0.3, 1.08, -0.56), 0.03, (80, 160, 60))
    # cap worn like a hat, with a three-tongued flame on top
    cap = V(0.04, 2.56, 0)
    m.cyl("Hat", 0.36, 0.54, cap, (40, 112, 64), "y", R=rot(z=-12))
    for k in range(6):
        a_ = 2 * math.pi * k / 6
        m.blk("HatTrim", (0.05, 0.32, 0.05), cap + rot(z=-12) @ V(math.cos(a_) * 0.27, 0, math.sin(a_) * 0.27), (30, 90, 50), R=rot(z=-12))
    fl = cap + V(-0.05, 0.22, 0)
    f = m.seg("Flame", fl, fl + V(-0.08, 0.6, 0.0), 0.17, (255, 110, 30), bulge=0.28)
    m.seg("Flame", fl + V(-0.08, 0.0, 0.02), fl + V(-0.3, 0.36, 0.02), 0.1, (255, 140, 40), bulge=0.3)
    m.seg("Flame", fl + V(0.07, 0.0, 0.02), fl + V(0.24, 0.32, 0.02), 0.09, (255, 140, 40), bulge=0.3)
    m.seg("Flame", fl + V(-0.02, 0.0, -0.06), fl + V(-0.05, 0.36, -0.08), 0.1, (255, 216, 80), bulge=0.3)
    m.fire(f, size=1, heat=3)
    # mischievous face: half-lidded yellow eyes, raised brows, a fanged grin
    m.eyes_on(hc, hs, I3, 23, 14, 0.32, 0.38, red, "sly", iris=(255, 200, 40), brow=dark, brow_k=0.9)
    p, n = on_ell_R(hc, hs, I3, V(0, -0.34, -1))
    m.mouth(p, n, 0.42, "sly", color=(80, 14, 24), fangs=True, side_bias=1)
    cheeks(m, hc, hs, I3, 0.62, -0.2, 0.22, color=(255, 120, 120))
    for s in (-1, 1):
        m.horn("Horn", hc + V(s * 0.34, 0.36, 0.05), hc + V(s * 0.58, 0.82, 0.12), 0.12, CREAM, curve=(s * 0.06, 0, -0.05))
    # little arms: one hand on the hip, one claw raised to scheme
    m.arms2(1.32, 0.62, red, 0.14, 0.12, 0.13, 0.16, dark,
            {1: ((0.92, 1.6, -0.25), (0.66, 1.88, -0.55), False), -1: ((-0.94, 0.98, 0.0), (-0.62, 0.86, -0.34), True)},
            refl=0.18)
    # short legs with cloven hooves
    for s in (-1, 1):
        hip, knee, ankle = V(s * 0.32, 0.55, 0.0), V(s * 0.36, 0.36, -0.05), V(s * 0.38, 0.22, 0.0)
        m.leg(hip, knee, ankle, 0.17, 0.14, 0.14, red, refl=0.18)
        m.hoof((s * 0.38, -0.02), 0.2, (60, 18, 26), notch=True)
    # pointed devil tail
    pts = [V(0, 0.8, 0.5), V(0.1, 0.62, 0.9), V(0.32, 0.72, 1.2), V(0.42, 1.05, 1.32)]
    for k, (a, b) in enumerate(zip(pts, pts[1:])):
        m.seg("Tail", a, b, 0.07 - k * 0.012, red, ext=0.03)
    tip = pts[-1]
    m.ell("TailTip", (0.08, 0.34, 0.26), tip + V(0.03, 0.14, 0.02), dark, R=rot(x=-20, z=-18))
    return m


# ------------------------------------------------------------------------------------------------
@model
def spaghetti_hydra():
    """Epic. A plate heaped with spaghetti and sauce, three meatball heads on thick braided noodle
    necks (grumpy, goofy and fierce), cheese flakes, basil and a fork stuck in. Mood: three of them."""
    m = SModel("spaghetti_hydra")
    noodle = (250, 220, 140)
    noodle_d = (232, 196, 112)
    sauce = (200, 40, 32)
    meat = (128, 70, 44)
    # the plate
    m.cyl("Base", 0.14, 3.2, V(0, 0.07, 0), WHITE, "y")
    m.cyl("Base", 0.1, 3.24, V(0, 0.1, 0), (90, 140, 220), "y")
    m.cyl("Base", 0.06, 2.66, V(0, 0.17, 0), WHITE, "y")
    # noodle heap
    hc, hs = V(0, 0.62, 0.05), (2.7, 1.0, 2.5)
    m.ell("Body", hs, hc, noodle)
    rnd = random.Random(8)
    for k in range(14):
        a0 = rnd.uniform(0, 2 * math.pi)
        y0 = rnd.uniform(-0.1, 0.55)
        pts = []
        for j in range(4):
            a = a0 + j * 0.45
            v = V(math.cos(a), y0 + math.sin(j * 1.3 + k) * 0.18, math.sin(a))
            p, n = on_ell_R(hc, hs, I3, v)
            pts.append(p + n * 0.04)
        col = noodle if k % 2 else noodle_d
        for a_, b_ in zip(pts, pts[1:]):
            m.seg("Noodle", a_, b_, 0.055, col, ext=0.03)
    # sauce on top with drips
    m.ell("Sauce", (1.7, 0.3, 1.5), hc + V(0.05, 0.42, 0.0), sauce, refl=0.2)
    for (a, L) in [(30, 0.35), (130, 0.45), (220, 0.32), (300, 0.42)]:
        q = hc + V(math.cos(math.radians(a)) * 0.78, 0.42, math.sin(math.radians(a)) * 0.7)
        m.drip("Sauce", q, L, 0.14, sauce, refl=0.2)
    # three braided noodle necks and meatball heads
    heads = [(-0.92, 2.1, -0.2, "grumpy", 0.92), (0.05, 2.85, 0.15, "goofy", 1.0), (0.96, 2.2, -0.25, "fierce", 0.94)]
    for (x, y, z, mood, d) in heads:
        base = V(x * 0.55, 0.95, z * 0.4)
        top = V(x, y - d * 0.4, z)
        mid = (base + top) / 2 + V(x * 0.2, 0, -0.15)
        for k in range(3):
            o = V(math.cos(k * 2.1) * 0.09, 0, math.sin(k * 2.1) * 0.09)
            o2 = V(math.cos(k * 2.1 + 1.5) * 0.09, 0, math.sin(k * 2.1 + 1.5) * 0.09)
            m.seg("Noodle", base + o * 1.2, mid + o2 * 1.2, 0.1, noodle if k != 1 else noodle_d, ext=0.05)
            m.seg("Noodle", mid + o2 * 1.2, top + o * 1.2, 0.1, noodle if k != 1 else noodle_d, ext=0.05)
        hc2, hs2 = V(x, y, z), (d, d * 0.94, d)
        m.ell("Head", hs2, hc2, meat)
        for j in range(5):
            q, nq = on_ell_R(hc2, hs2, I3, V(math.cos(j * 2.4), 0.6 - j * 0.3, math.sin(j * 2.4) + 0.3))
            m.ball("Bump", d * 0.18, q - nq * 0.02, shade(meat, 0.85))
        iris = {"grumpy": (240, 200, 60), "goofy": (90, 160, 240), "fierce": (230, 80, 60)}[mood]
        m.eyes_on(hc2, hs2, I3, 24, 10, d * 0.38, d * 0.44, meat, mood, iris=iris, brow=(60, 30, 20), brow_k=0.95)
        p, n = on_ell_R(hc2, hs2, I3, V(0, -0.42, -1))
        m.mouth(p, n, d * 0.48, mood, color=(70, 20, 20), skin=meat if mood != "grumpy" else None, d=d * 0.06)
        # a sauce cap with a drip and a basil leaf
        m.ell("HeadSauce", (d * 0.8, d * 0.3, d * 0.8), hc2 + V(0, d * 0.36, 0.03), sauce, refl=0.2)
        m.drip("HeadSauce", hc2 + V(d * 0.2, d * 0.3, -d * 0.3), d * 0.3, d * 0.12, sauce, refl=0.2)
        m.ell("Basil", (d * 0.36, 0.04, d * 0.2), hc2 + V(-d * 0.1, d * 0.52, 0.04), (70, 160, 70), R=rot(z=12, y=30))
    # cheese flakes and basil on the heap, a fork stuck in
    for k in range(7):
        a = k * 0.9 + 0.3
        q, nq = on_ell_R(hc, hs, I3, V(math.cos(a), 0.55, math.sin(a)))
        m.blk("Cheese", (0.12, 0.04, 0.08), q + nq * 0.05, (255, 240, 170), R=frame_normal(nq, k * 40))
    for (x, z) in [(-0.55, 0.6), (0.6, 0.45)]:
        m.ell("Basil", (0.3, 0.04, 0.16), V(x, 1.14, z), (70, 160, 70), R=rot(z=10, y=x * 60))
    fork = V(1.0, 1.0, 0.75)
    m.seg("ForkHandle", fork, fork + V(0.45, 1.25, 0.25), 0.07, SILVER, "Metal", shape="C")
    for k in range(4):
        m.seg("ForkTine", fork + V(-0.1 + k * 0.07, 0, 0), fork + V(-0.16 + k * 0.08, -0.35, -0.06), 0.025, SILVER, "Metal", shape="C")
    return m


# ------------------------------------------------------------------------------------------------
@model
def burrito_bouncer():
    """Mythic. A huge burrito bouncer: a toasted tortilla wrapped round with a fold across the front,
    a crinkly foil skirt, filling spilling out of the open top, wraparound shades, a toothpick, a
    security earpiece, a gold chain and big folded arms. Mood: tough and unimpressed."""
    m = SModel("burrito_bouncer")
    tort = (238, 204, 146)
    tort_l = (246, 222, 176)
    toast = (196, 140, 76)
    foil = (206, 212, 222)
    R0 = 0.92
    m.cyl("Body", 1.95, 2 * R0, V(0, 1.72, 0.02), tort, "y")
    m.ell("Body", (2 * R0, 0.6, 2 * R0), V(0, 0.78, 0.02), tort)
    # toasted spots
    rnd = random.Random(5)
    for k in range(12):
        a = rnd.uniform(0, 2 * math.pi)
        y = rnd.uniform(1.35, 2.55)
        if abs(math.degrees(a) % 360 - 270) < 40 and y > 1.75:
            continue   # keep the face clear
        m.ell("Toast", (0.28, 0.17, 0.05), V(math.cos(a) * R0, y, 0.02 + math.sin(a) * R0), toast, R=frame_normal(V(math.cos(a), 0, math.sin(a)), rnd.uniform(0, 180)))

    def on_wrap(a_deg, y, out=0.0):
        a = math.radians(a_deg)
        return V(math.cos(a) * (R0 + out), y, 0.02 + math.sin(a) * (R0 + out))

    # the tortilla's wrapped edge sweeping across the front, with a toasted shadow under it
    pts = [on_wrap(a, 2.5 - k * 0.24, 0.05) for k, a in enumerate(range(130, 420, 48))]
    for a_, b_ in zip(pts, pts[1:]):
        m.seg("Fold", a_ + V(0, -0.11, 0), b_ + V(0, -0.11, 0), 0.07, toast, r2=0.06, ext=0.06)
        m.seg("Fold", a_, b_, 0.12, tort_l, r2=0.1, ext=0.1)
    # the open top: a rolled tortilla rim with floppy flaps and the filling heaped inside
    m.ell("Rim", (2 * R0 + 0.04, 0.24, 2 * R0 + 0.04), V(0, 2.7, 0.02), tort_l)
    for k, a in enumerate((20, 95, 160, 215, 330)):
        n = V(math.cos(math.radians(a)), 0, math.sin(math.radians(a)))
        p = on_wrap(a, 2.92, -0.08)
        R = frame_normal(n) @ Rx(-28)
        m.ell("Rim", (0.92, 0.62, 0.14), p, tort_l if k % 2 else tort, R=R)
        m.ell("Toast", (0.22, 0.14, 0.05), p + n * 0.08 + V(0, 0.12, 0), toast, R=R)
    m.ell("Filling", (1.62, 0.66, 1.58), V(0, 2.9, 0.02), (150, 84, 48))
    rnd = random.Random(11)
    for k in range(18):
        a = k * 0.62 + 0.3
        r = (0.2, 0.42, 0.6)[k % 3]
        q = V(math.cos(a) * r, 3.1 + rnd.uniform(-0.03, 0.08) - r * 0.18, 0.02 + math.sin(a) * r)
        kind = k % 6
        if kind in (0, 3):
            m.ell("Lettuce", (0.5, 0.1, 0.34), q + V(0, 0.08, 0), (110, 196, 70) if kind == 0 else (150, 214, 90),
                  R=rot(z=26 * math.cos(a), y=math.degrees(a), x=24))
        elif kind == 1:
            m.blk("Tomato", (0.2, 0.17, 0.2), q + V(0, 0.04, 0), (226, 58, 48), R=rot(20, k * 30, 10))
        elif kind == 2:
            m.ball("Bean", 0.17, q, (96, 52, 34))
        elif kind == 4:
            m.ball("Rice", 0.15, q + V(0, 0.03, 0), (252, 250, 240))
        else:
            m.ball("Corn", 0.13, q + V(0, 0.05, 0), (255, 214, 70))
    m.ell("Guac", (0.62, 0.3, 0.56), V(0.2, 3.26, 0.12), (130, 184, 70))
    m.ell("SourCream", (0.46, 0.3, 0.44), V(-0.22, 3.3, -0.02), (252, 250, 244))
    m.ell("SourCream", (0.24, 0.22, 0.24), V(-0.2, 3.46, -0.02), (252, 250, 244))
    # melted cheese drips over the rim at the sides and back, away from the face
    for a in (140, 175, 10, 40, 95):
        n = V(math.cos(math.radians(a)), 0, math.sin(math.radians(a)))
        ln = 0.3 + (a % 4) * 0.07
        p = on_wrap(a, 2.68 - ln / 2, 0.0)
        m.ell("Cheese", (0.24, ln + 0.1, 0.12), p, (255, 200, 60), R=frame_normal(n))
        m.ell("Cheese", (0.22, 0.2, 0.16), on_wrap(a, 2.68 - ln, 0.02), (255, 200, 60), R=frame_normal(n))
    # face: wraparound shades, heavy brows, a flat mouth with a toothpick, an earpiece
    # two big wraparound lenses with a bridge and arms running back to the earpiece
    for sd in (-1, 1):
        a = 270 + sd * 21
        n = V(math.cos(math.radians(a)), 0, math.sin(math.radians(a)))
        m.ell("Glasses", (0.6, 0.42, 0.12), on_wrap(a, 2.24, 0.05), (22, 22, 28), R=frame_normal(n) @ Rz(sd * 6), refl=0.4)
        m.ell("Glint", (0.22, 0.07, 0.02), on_wrap(a - sd * 6, 2.32, 0.12), (210, 222, 240), R=frame_normal(n) @ Rz(-20))
        arm = [on_wrap(270 + sd * k, 2.3, 0.06) for k in (40, 62, 84)]
        m.chain("Glasses", arm, 0.035, (30, 30, 36), joints=False)
        b = on_wrap(270 + sd * 24, 2.58, 0.05)
        m.ell("Brow", (0.52, 0.14, 0.1), b, (110, 66, 34), R=frame_normal(V(math.cos(math.radians(270 + sd * 24)), 0, math.sin(math.radians(270 + sd * 24)))) @ Rz(-sd * 14))
    m.seg("Glasses", on_wrap(266, 2.28, 0.06), on_wrap(274, 2.28, 0.06), 0.05, (30, 30, 36))
    pm = on_wrap(270, 1.92, 0.02)
    m.mouth(pm, V(0, 0, -1), 0.46, "stern", color=(110, 60, 40), d=0.06, curve=-0.07, kind="smile")
    m.seg("Toothpick", pm + V(0.18, 0, -0.03), pm + V(0.46, 0.08, -0.22), 0.026, (220, 190, 130))
    qe = on_wrap(0, 2.3, 0.04)
    m.ell("Earpiece", (0.1, 0.2, 0.16), qe, (30, 30, 36))
    m.ball("EyeLED", 0.06, qe + V(0.05, 0.07, 0), (255, 60, 60), "Neon")
    m.chain("EarWire", [qe + V(0.03, -0.08, 0.02), qe + V(0.05, -0.4, 0.14), qe + V(0.02, -0.72, 0.24)], 0.025, (40, 40, 46), joints=False)
    # a gold chain with a chili medallion
    for k in range(8):
        a1, a2 = 205 + k * 16.5, 205 + (k + 1) * 16.5
        y1 = 1.98 - math.sin(math.radians((a1 - 205) * 180 / 132)) * 0.3
        y2 = 1.98 - math.sin(math.radians((a2 - 205) * 180 / 132)) * 0.3
        m.seg("Chain", on_wrap(a1, y1, 0.07), on_wrap(a2, y2, 0.07), 0.075, GOLD, "Metal", ext=0.02)
    med = on_wrap(270, 1.5, 0.1)
    m.cyl("Medal", 0.08, 0.38, med, GOLD, "z", "Metal", refl=0.2)
    m.seg("Medal", med + V(-0.09, 0.07, -0.05), med + V(0.09, -0.07, -0.05), 0.075, CHERRY)
    # a crinkly foil skirt
    m.cyl("Foil", 0.74, 2 * R0 + 0.1, V(0, 0.92, 0.02), foil, "y", "Foil", refl=0.2)
    for k in range(14):
        a = 2 * math.pi * k / 14
        m.blk("Foil", (0.06, 0.7, 0.16), V(math.cos(a) * (R0 + 0.05), 0.92, 0.02 + math.sin(a) * (R0 + 0.05)), shade(foil, 1.07), "Foil", R=rot(y=-math.degrees(a)))
    m.cyl("Foil", 0.1, 2 * R0 + 0.16, V(0, 1.28, 0.02), shade(foil, 1.1), "y", "Foil")
    # big arms folded across the belly (each hand tucked on its own side)
    for s in (-1, 1):
        sh, el, wr = V(s * 1.0, 2.05, 0.0), V(s * 1.2, 1.42, -0.45), V(s * 0.3, 1.36 + s * 0.12, -1.05)
        m.ball("Shoulder", 0.68, sh, tort)
        m.seg("UpperArm", sh, el, 0.29, tort, bulge=0.5)
        m.ball("Elbow", 0.48, el, tort)
        m.seg("Forearm", el, wr, 0.28, tort, bulge=0.62)
        m.ball("Fist", 0.48, wr + V(-s * 0.05, 0, -0.04), shade(tort, 0.96))
        m.ell("Wristband", (0.52, 0.2, 0.52), el + (wr - el) * 0.62, (36, 36, 42), R=frame_normal(norm(wr - el)) @ Rx(90))
    # short legs in black boots
    m.legs2(0.62, 0.42, tort, 0.24, 0.2, 0.2, 0.52, 0.72, (36, 36, 42), sole=(20, 20, 24), cuff=(60, 60, 68), ankle_y=0.32)
    return m


# ------------------------------------------------------------------------------------------------
@model
def queen_parfait():
    """Legendary. A parfait queen: a gown that is a tall layered parfait glass on a stem, a whipped-cream
    bodice and beehive hair swirl, a gold-foil crown with a cherry, puffed cream sleeves, a wafer
    sceptre, a glossy syrup cape and sprinkles. Mood: regal."""
    m = SModel("queen_parfait")
    glass = (226, 236, 248)
    skin = (255, 230, 228)
    # the glass: a foot, a stem and a tulip bowl of layers
    m.cyl("Base", 0.12, 1.5, V(0, 0.06, 0), glass, "y", "Glass", tr=0.25, refl=0.3)
    m.seg("Stem", V(0, 0.1, 0), V(0, 0.8, 0), 0.14, glass, "Glass", shape="C", tr=0.2, refl=0.3)
    m.ball("Stem", 0.36, V(0, 0.55, 0), glass, "Glass", tr=0.2, refl=0.3)
    layers = [(1.0, 1.0, (255, 140, 170)), (1.38, 1.36, CREAM), (1.76, 1.64, (150, 110, 200)), (2.14, 1.84, (230, 176, 90)),
              (2.5, 1.96, (255, 150, 180))]
    for k, (y, d, col) in enumerate(layers):
        m.ell("Robe", (d, 0.5, d), V(0, y, 0), col)
        if col == (230, 176, 90):
            for j in range(7):
                a = j * 0.9
                m.ball("Crumb", 0.12, V(math.cos(a) * d * 0.48, y + 0.06, math.sin(a) * d * 0.48), (200, 140, 60))
        if col == (150, 110, 200):
            for j in range(6):
                a = j * 1.05 + 0.4
                m.ball("Berry", 0.18, V(math.cos(a) * d * 0.47, y + 0.08, math.sin(a) * d * 0.47), (90, 70, 170), refl=0.1)
    m.ell("Robe", (2.12, 2.2, 2.12), V(0, 1.78, 0), glass, "Glass", tr=0.82, refl=0.35)
    m.ell("Robe", (2.18, 0.14, 2.18), V(0, 2.8, 0), glass, "Glass", tr=0.3, refl=0.35)
    # whipped-cream bodice swirling up out of the glass
    for k, (y, d) in enumerate([(2.98, 1.7), (3.3, 1.3), (3.58, 0.94)]):
        m.ell("Body" if k == 1 else "Cream", (d, 0.46, d), V(0, y, 0), CREAM)
    sprinkles(m, V(0, 3.1, 0), (1.5, 0.8, 1.5), 12, seed=4, ymin=0.1)
    # head and regal face
    hc, hs = V(0, 4.22, -0.02), (0.98, 0.96, 0.92)
    m.ell("Head", hs, hc, skin)
    m.eyes_on(hc, hs, I3, 24, 8, 0.3, 0.36, skin, "regal", iris=(200, 70, 120), lash=3, brow=(170, 90, 110), brow_k=0.8)
    p, n = on_ell_R(hc, hs, I3, V(0, -0.38, -1))
    m.mouth(p, n, 0.26, "regal", color=(200, 50, 90), d=0.045)
    cheeks(m, hc, hs, I3, 0.62, -0.22, 0.22)
    # beehive hair: a whipped-cream swirl
    for k, (y, d) in enumerate([(0.32, 1.04), (0.6, 0.86), (0.85, 0.64), (1.06, 0.42)]):
        m.ell("Hair", (d, 0.34, d * 0.96), hc + V(0, y, 0.08), CREAM)
    m.seg("Hair", hc + V(0, 1.12, 0.08), hc + V(0.06, 1.34, 0.06), 0.1, CREAM, bulge=0.3)
    # gold-foil crown with points, gems and a cherry
    cr = hc + V(0, 0.52, -0.02)
    m.cyl("Crown", 0.26, 1.02, cr, GOLD, "y", "Foil", refl=0.2)
    for k in range(6):
        a = math.radians(-90 + (k - 2.5) * 30)
        m.seg("CrownPoint", cr + V(math.cos(a) * 0.5, 0.1, math.sin(a) * 0.5), cr + V(math.cos(a) * 0.54, 0.42, math.sin(a) * 0.54), 0.08, GOLD, "Foil", bulge=0.25)
    for k in (-1, 0, 1):
        a = math.radians(-90 + k * 32)
        m.gem("CrownGem", cr + V(math.cos(a) * 0.52, 0.0, math.sin(a) * 0.52), 0.14, (255, 80, 130) if k == 0 else (110, 200, 255))
    ch = hc + V(0.02, 1.52, 0.06)
    m.ball("Cherry", 0.36, ch, (210, 20, 50), refl=0.3)
    m.seg("Cherry", ch + V(0, 0.15, 0), ch + V(0.15, 0.45, 0.05), 0.025, (90, 140, 60))
    # puffed cream sleeves and gloved arms; a wafer sceptre in the right hand
    hands = m.arms2(3.42, 0.72, skin, 0.13, 0.11, 0.12, 0.15, WHITE,
                    {1: ((1.05, 3.0, -0.2), (1.0, 2.62, -0.58), True), -1: ((-1.05, 3.55, -0.15), (-1.1, 4.0, -0.45), False)})
    for s in (-1, 1):
        m.ball("Sleeve", 0.56, V(s * 0.74, 3.44, 0.0), CREAM)
        m.ball("Sleeve", 0.36, V(s * 0.9, 3.62, 0.02), WHITE)
    w = hands[1]
    m.seg("Wafer", w + V(0, -1.0, 0.05), w + V(0, 0.95, -0.05), 0.08, (230, 180, 100), shape="B")
    for k in range(5):
        m.blk("WaferStripe", (0.17, 0.035, 0.17), w + V(0, -0.8 + k * 0.38, 0), (200, 140, 70))
    m.ell("WaferTop", (0.42, 0.42, 0.42), w + V(0, 1.12, -0.05), (255, 150, 180))
    m.gem("WaferTop", w + V(0, 1.42, -0.05), 0.2, (255, 60, 110))
    # a glossy syrup cape with drips
    syrup = (180, 40, 60)
    m.ell("Cape", (1.9, 2.6, 0.24), V(0, 2.4, 0.92), syrup, "Glass", R=rot(x=10), tr=0.1, refl=0.3)
    m.seg("Cape", V(-0.72, 3.5, 0.62), V(0.72, 3.5, 0.62), 0.1, GOLD, "Foil")
    for k in range(6):
        x = -0.75 + k * 0.3
        m.drip("Cape", (x, 1.3 + abs(x) * 0.3, 1.14), 0.3 + (k % 3) * 0.12, 0.16, syrup, "Glass", refl=0.3)
    sp = m.ball("Sparkle", 0.1, hc + V(0, 1.8, 0), (255, 255, 220), "Neon")
    m.sparkles(sp, (255, 210, 230))
    return m
