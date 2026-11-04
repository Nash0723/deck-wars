# Snack family models (warm, food colors, glossy and a little sticky)
import math
from modelkit import Model, rot, Rx, Ry, Rz, WHITE, BLACK, PUPIL, shade

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


@model
def jelly_bean_scout():
    m = Model("jelly_bean_scout")
    body = (235, 60, 105)
    dark = (190, 40, 80)
    m.ell("Body", (1.5, 2.0, 1.3), (0, 1.3, 0), body, R=rot(z=-8), refl=0.2)
    m.ell("Belly", (1.0, 1.2, 0.5), (0.05, 1.1, -0.45), (255, 120, 150), refl=0.1)
    # jelly shine and speckles
    m.ell("Shine", (0.22, 0.75, 0.12), (-0.48, 1.75, -0.42), (255, 215, 230), R=rot(z=-14, y=-30), tr=0.25)
    m.ell("Shine", (0.12, 0.25, 0.08), (-0.38, 2.2, -0.36), (255, 235, 240), R=rot(z=-20, y=-30), tr=0.2)
    m.scatter("Speckle", (0, 1.3, 0), (1.5, 2.0, 1.3), 14, [(200, 35, 80), (255, 150, 180)], seed=4, d=0.09, shape="dot", ymin=-0.7)
    # hiking boots
    for s in (-1, 1):
        m.cyl("Leg", 0.55, 0.32, (s * 0.35, 0.42, 0), dark)
        m.cyl("Sock", 0.14, 0.36, (s * 0.35, 0.33, 0), (245, 240, 230), mat="Fabric")
        m.shoe(s * 0.36, -0.1, 0.46, 0.68, (120, 75, 45), sole=(55, 40, 35), toe=(140, 90, 55), lace=(240, 220, 150))
    # arms: one waving, one holding the backpack strap
    m.rod("Arm", (-0.65, 1.35, 0), (-1.05, 0.88, -0.1), 0.24, dark)
    m.rod("Arm", (0.65, 1.4, 0), (1.05, 1.95, -0.1), 0.24, dark)
    m.cyl("Cuff", 0.12, 0.3, (-0.98, 0.96, -0.09), (90, 130, 70), mat="Fabric", R=rot(z=-40))
    m.cyl("Cuff", 0.12, 0.3, (0.99, 1.87, -0.1), (90, 130, 70), mat="Fabric", R=rot(z=40))
    m.mitt((-1.08, 0.82, -0.1), 0.32, dark, -1)
    m.mitt((1.08, 2.0, -0.1), 0.32, dark, 1, fingers=3)
    # scout neckerchief with a woggle
    m.wedge("Scarf", (0.55, 0.36, 0.08), (0.02, 1.12, -0.66), (250, 200, 50), R=rot(z=180) @ rot(x=14))
    m.cyl("Woggle", 0.1, 0.16, (0.02, 1.27, -0.67), (160, 100, 50), axis="z")
    # merit badge sash
    m.rod("Sash", (-0.7, 1.3, -0.35), (0.45, 0.62, -0.5), 0.26, (70, 120, 60), mat="Fabric", shape="B")
    for k, c in enumerate([(60, 140, 230), (250, 180, 40), (230, 70, 70)]):
        t = 0.3 + k * 0.22
        m.cyl("Badge", 0.06, 0.18, (-0.7 + 1.15 * t, 1.3 - 0.68 * t, -0.53 - 0.06 * t), c, axis="z")
        m.cyl("Badge", 0.065, 0.08, (-0.7 + 1.15 * t, 1.3 - 0.68 * t, -0.56 - 0.06 * t), (255, 250, 230), axis="z")
    # campaign hat with the four pinches and a feather
    hat = (195, 155, 95)
    m.cyl("HatBrim", 0.1, 1.5, (0, 2.27, 0), (185, 145, 85))
    m.ring("HatBrim", (0, 2.28, 0), 0.74, 0.08, (165, 125, 70), normal="y", segments=14)
    m.cyl("HatBand", 0.13, 0.9, (0, 2.38, 0), (110, 70, 40))
    m.cyl("HatCrown", 0.42, 0.8, (0, 2.58, 0), hat)
    m.ell("HatCrown", (0.8, 0.3, 0.8), (0, 2.79, 0), hat)
    for k in range(4):
        a = k * math.pi / 2
        m.ell("HatDent", (0.18, 0.3, 0.18), (math.cos(a) * 0.3, 2.78, math.sin(a) * 0.3), (165, 125, 70))
    m.ell("HatDent", (0.12, 0.12, 0.45), (0, 2.92, 0), (165, 125, 70))
    m.ell("HatFeather", (0.12, 0.55, 0.06), (0.45, 2.6, 0.05), (240, 90, 60), R=rot(z=-30))
    # backpack with a bedroll, a pocket and a canteen
    m.rbox("Backpack", (0.9, 0.95, 0.45), (0.0, 1.35, 0.72), (90, 130, 70), 0.12, mat="Fabric")
    m.blk("BackpackFlap", (0.92, 0.32, 0.5), (0.0, 1.74, 0.72), (70, 105, 55), mat="Fabric")
    m.blk("Pocket", (0.6, 0.35, 0.12), (0, 1.12, 0.98), (70, 105, 55), mat="Fabric")
    m.cyl("Buckle", 0.04, 0.12, (0, 1.6, 0.98), (230, 200, 90), axis="z", mat="Metal")
    m.ell("Bedroll", (1.05, 0.34, 0.34), (0.0, 1.97, 0.74), (180, 60, 50), mat="Fabric")
    for x in (-0.3, 0.3):
        m.cyl("BedrollTie", 0.06, 0.36, (x, 1.97, 0.74), (110, 70, 40), axis="x")
    for s in (-1, 1):
        m.rod("Strap", (s * 0.36, 2.0, 0.45), (s * 0.5, 1.0, 0.45), 0.1, (70, 105, 55), mat="Fabric", shape="B")
    m.cyl("Canteen", 0.18, 0.4, (0.62, 1.0, 0.55), (150, 160, 170), axis="x", mat="Metal")
    # face
    m.eyes(1.78, -0.5, 0.52, 0.4, lid=body, iris=(110, 60, 40), z_back=0.02)
    m.brow(-0.26, 2.08, -0.48, 0.28, dark, -1, tilt=-8)
    m.brow(0.26, 2.08, -0.48, 0.28, dark, 1, tilt=-8)
    m.grin(1.5, -0.6, 0.36, curve=0.25, open_=True, teeth=2, bend=0.04)
    m.cheeks(1.55, -0.56, 0.95, 0.22)
    return m


@model
def pretzel_guard():
    m = Model("pretzel_guard")
    bread = (175, 105, 45)
    dark = (140, 80, 35)
    salt = (250, 250, 245)
    steel = (190, 195, 205)
    m.ell("Body", (2.0, 2.4, 1.7), (0, 1.35, 0), bread, refl=0.15)
    # the pretzel twist pressed into the belly
    m.ring("Twist", (-0.32, 1.05, -0.62), 0.32, 0.14, dark, normal="z", segments=10, R=rot(x=12))
    m.ring("Twist", (0.32, 1.05, -0.62), 0.32, 0.14, dark, normal="z", segments=10, R=rot(x=12))
    m.rod("Twist", (-0.55, 0.62, -0.62), (0.4, 1.3, -0.72), 0.14, dark)
    m.rod("Twist", (0.55, 0.62, -0.62), (-0.4, 1.3, -0.72), 0.14, dark)
    m.scatter("Salt", (0, 1.35, 0), (2.0, 2.4, 1.7), 16, [salt], seed=7, d=0.075, shape="cube", ymin=-0.3)
    # belt with a buckle
    m.cyl("Belt", 0.2, 1.88, (0, 0.72, 0), (90, 55, 30), mat="Leather")
    m.rbox("Buckle", (0.32, 0.24, 0.08), (0, 0.72, -0.8), (230, 190, 80), 0.05, mat="Metal", axis="z")
    # knight helmet: ridge, rivets, nose guard, cheek guards, a big plume
    m.ell("Helmet", (1.6, 0.95, 1.5), (0, 2.45, 0.05), steel, mat="Metal", refl=0.25)
    m.blk("HelmetRim", (1.72, 0.16, 0.2), (0, 2.18, -0.68), (160, 165, 175), mat="Metal")
    m.ring("HelmetRim", (0, 2.18, 0.05), 0.8, 0.1, (160, 165, 175), normal="y", segments=14, mat="Metal")
    m.rod("HelmetRidge", (0, 2.92, -0.4), (0, 2.88, 0.6), 0.14, (160, 165, 175), mat="Metal")
    m.blk("NoseGuard", (0.14, 0.5, 0.1), (0, 2.02, -0.82), (160, 165, 175), mat="Metal")
    for s in (-1, 1):
        for k in range(3):
            m.ball("HelmetRivet", 0.08, (s * (0.35 + k * 0.17), 2.2, -0.75 + k * 0.04), (230, 200, 90), mat="Metal")
    m.cyl("Plume", 0.55, 0.24, (0, 3.08, 0.1), (230, 190, 80), mat="Metal")
    for k, c in enumerate([(220, 50, 50), (250, 240, 235), (220, 50, 50)]):
        m.ell("PlumeTop", (0.26, 0.5, 0.85), (0, 3.35 + k * 0.05, 0.18 + k * 0.3), c, R=rot(x=20 + k * 25), mat="Fabric")
    # face: stern eyes and a pretzel-dough mustache
    m.eyes(1.82, -0.78, 0.6, 0.38, lid=bread, angry=12, iris=(70, 130, 60))
    for s in (-1, 1):
        m.chain("Mustache", [(0, 1.56, -0.86), (s * 0.25, 1.52, -0.84), (s * 0.42, 1.6, -0.78), (s * 0.5, 1.72, -0.72)], 0.13, dark)
    m.grin(1.38, -0.84, 0.3, curve=-0.12, color=(80, 35, 20))
    # legs with steel greaves
    for s in (-1, 1):
        m.cyl("Leg", 0.5, 0.42, (s * 0.45, 0.3, 0), dark)
        m.cyl("Greave", 0.3, 0.46, (s * 0.45, 0.4, 0), steel, mat="Metal")
        m.shoe(s * 0.47, -0.12, 0.55, 0.78, (90, 60, 40), sole=(50, 35, 25), toe=(160, 165, 175))
    # pretzel shield (two loops and a twist, salted) held on the left
    sx, sy, sz = -1.0, 1.25, -0.95
    m.cyl("ShieldBoss", 0.14, 1.45, (sx, sy, sz + 0.1), (120, 70, 30), axis="z")
    for k in (-1, 1):
        m.ring("Shield", (sx + k * 0.33, sy + 0.12, sz), 0.38, 0.22, dark, normal="z", segments=12)
    m.rod("Shield", (sx - 0.62, sy - 0.25, sz), (sx + 0.62, sy - 0.25, sz), 0.22, dark)
    m.rod("Shield", (sx - 0.35, sy - 0.5, sz), (sx + 0.3, sy + 0.2, sz), 0.22, dark)
    m.rod("Shield", (sx + 0.35, sy - 0.5, sz), (sx - 0.3, sy + 0.2, sz), 0.22, dark)
    for (x, y) in [(-0.45, 0.35), (-0.2, 0.25), (0.25, -0.2), (0.0, 0.0), (0.5, 0.3), (0.3, 0.45), (-0.5, -0.25), (0.45, -0.25)]:
        m.blk("ShieldSalt", (0.07, 0.07, 0.07), (sx + x, sy + y, sz - 0.13), salt, R=rot(30, 30, 0))
    m.rod("Arm", (-0.85, 1.55, -0.2), (-1.0, 1.25, -0.8), 0.3, bread)
    m.cyl("Gauntlet", 0.2, 0.34, (-0.98, 1.3, -0.72), steel, mat="Metal", R=rot(x=60))
    # salted breadstick spear with a pennant on the right
    m.rod("Arm", (0.9, 1.5, -0.1), (1.2, 1.3, -0.45), 0.3, bread)
    m.cyl("Gauntlet", 0.2, 0.34, (1.15, 1.34, -0.4), steel, mat="Metal", R=rot(x=50))
    m.cyl("Spear", 3.0, 0.2, (1.25, 1.6, -0.5), (215, 170, 100))
    for k in range(4):
        m.cyl("SpearBand", 0.08, 0.23, (1.25, 0.5 + k * 0.85, -0.5), (180, 130, 65))
    m.ell("SpearTip", (0.34, 0.66, 0.34), (1.25, 3.27, -0.5), (200, 150, 80))
    for k in range(3):
        m.blk("SpearSeed", (0.08, 0.08, 0.08), (1.25 + 0.1 * (k - 1), 3.2 + k * 0.1, -0.66), salt, R=rot(30, 30, 0))
    m.wedge("SpearFlag", (0.06, 0.4, 0.6), (1.25, 2.75, -0.2), (60, 110, 200), R=rot(x=90))
    m.mitt((1.25, 1.3, -0.52), 0.34, bread, 1)
    m.mitt((-1.02, 1.2, -0.86), 0.32, bread, -1, thumb=False)
    return m


@model
def pancake_paladin():
    m = Model("pancake_paladin")
    cake = (225, 160, 75)
    edge = (190, 115, 45)
    toast = (165, 95, 35)
    for i, (y, dx) in enumerate([(0.75, 0.0), (1.25, 0.08), (1.75, -0.06)]):
        m.cyl("Pancake", 0.5, 2.5, (dx, y, 0), edge)
        m.cyl("PancakeFace", 0.52, 2.3, (dx, y, 0), cake)
        # golden-brown cooked rim lines above and below
        m.ring("PancakeRim", (dx, y + 0.22, 0), 1.2, 0.08, toast, normal="y", segments=16)
    m.cyl("Syrup", 0.16, 2.35, (0, 2.06, 0), (160, 70, 20), refl=0.35)
    m.ell("SyrupPool", (2.2, 0.22, 2.2), (0, 2.12, 0), (175, 80, 25), refl=0.4)
    for (x, z, ln) in [(-1.12, -0.3, 0.7), (0.72, -0.9, 0.9), (1.13, 0.4, 0.55), (-0.45, -1.08, 0.5), (0.0, 1.17, 0.8), (-0.85, 0.8, 0.45)]:
        m.drip("Drip", (x, 2.08, z), ln, 0.26, (165, 75, 25), refl=0.35)
    # melting butter pat
    m.rbox("Butter", (0.75, 0.38, 0.75), (0.1, 2.34, 0.1), (255, 230, 120), 0.08, R=rot(y=20))
    m.ell("ButterMelt", (1.0, 0.1, 0.95), (0.12, 2.18, 0.12), (255, 225, 110), R=rot(y=20), refl=0.2)
    # strawberry helmet with seeds and a leafy crown
    m.ell("Strawberry", (0.7, 0.8, 0.7), (-0.15, 2.92, 0.1), (230, 40, 50), refl=0.15)
    m.scatter("Seed", (-0.15, 2.92, 0.1), (0.7, 0.8, 0.7), 12, [(255, 230, 120)], seed=3, d=0.06, shape="dot", ymin=-0.6)
    for k in range(5):
        a = k * 2 * math.pi / 5
        m.ell("Leaves", (0.32, 0.06, 0.14), (-0.15 + math.cos(a) * 0.16, 3.3, 0.1 + math.sin(a) * 0.16), (60, 160, 60), R=rot(y=-math.degrees(a), z=-20))
    m.cyl("Leaves", 0.18, 0.06, (-0.15, 3.42, 0.1), (60, 130, 50))
    # face on the middle pancake
    m.eyes(1.33, -1.2, 0.7, 0.42, lid=cake, iris=(90, 140, 220), bulge=0.5)
    m.brow(-0.35, 1.67, -1.22, 0.32, toast, -1, tilt=-10)
    m.brow(0.35, 1.67, -1.22, 0.32, toast, 1, tilt=-10)
    m.grin(0.85, -1.26, 0.46, curve=0.22, open_=True, teeth=2)
    m.cheeks(0.95, -1.18, 1.25, 0.28)
    # stubby legs in boots
    for s in (-1, 1):
        m.cyl("Leg", 0.55, 0.38, (s * 0.5, 0.3, 0), edge)
        m.shoe(s * 0.5, -0.15, 0.52, 0.72, (110, 70, 40), sole=(60, 40, 25), toe=(200, 205, 215))
    # fork sword in the right hand
    m.rod("Arm", (1.2, 1.3, 0), (1.55, 1.2, -0.45), 0.28, edge)
    m.cyl("Bracer", 0.16, 0.32, (1.48, 1.22, -0.36), (200, 205, 215), mat="Metal", R=rot(y=-50) @ rot(z=90))
    m.mitt((1.55, 1.2, -0.5), 0.36, edge, 1)
    m.cyl("ForkGrip", 0.7, 0.24, (1.55, 1.05, -0.5), (70, 110, 200), mat="Fabric")
    m.ball("ForkPommel", 0.24, (1.55, 0.66, -0.5), (240, 200, 80), mat="Metal")
    m.cyl("ForkHandle", 1.2, 0.18, (1.55, 1.55, -0.5), (200, 200, 210), mat="Metal", refl=0.2)
    m.blk("ForkNeck", (0.55, 0.25, 0.12), (1.55, 2.2, -0.5), (200, 200, 210), mat="Metal")
    m.blk("ForkGrip", (0.75, 0.1, 0.16), (1.55, 2.08, -0.5), (240, 200, 80), mat="Metal")
    for k in range(4):
        m.blk("ForkTine", (0.08, 0.95, 0.08), (1.37 + k * 0.12, 2.78, -0.5), (215, 215, 225), mat="Metal", refl=0.2)
        m.wedge("ForkTine", (0.08, 0.12, 0.08), (1.37 + k * 0.12, 3.31, -0.5), (215, 215, 225), mat="Metal")
    # round waffle shield in the left hand
    m.rod("Arm", (-1.2, 1.3, 0), (-1.45, 1.15, -0.5), 0.28, edge)
    m.mitt((-1.45, 1.15, -0.5), 0.34, edge, -1, thumb=False)
    m.cyl("ShieldRim", 0.2, 1.42, (-1.5, 1.2, -0.62), (185, 120, 50), axis="z")
    m.cyl("Shield", 0.22, 1.25, (-1.5, 1.2, -0.64), (225, 165, 75), axis="z")
    for i in range(4):
        for j in range(4):
            x, y = -1.5 + (i - 1.5) * 0.24, 1.2 + (j - 1.5) * 0.24
            if (x + 1.5) ** 2 + (y - 1.2) ** 2 < 0.42:
                m.blk("ShieldGrid", (0.15, 0.15, 0.06), (x, y, -0.77), (190, 120, 45))
    m.drip("ShieldRim", (-1.25, 1.55, -0.77), 0.3, 0.12, (165, 75, 25), refl=0.35)
    # blue cape with a golden clasp and a butter emblem
    m.ell("Cape", (1.9, 1.7, 0.16), (0, 1.15, 1.3), (60, 90, 200), mat="Fabric", R=rot(x=-8))
    m.ell("CapeFold", (0.2, 1.5, 0.18), (-0.4, 1.15, 1.38), (45, 70, 170), mat="Fabric", R=rot(x=-8))
    m.ell("CapeFold", (0.2, 1.5, 0.18), (0.4, 1.15, 1.38), (45, 70, 170), mat="Fabric", R=rot(x=-8))
    m.rbox("CapeBadge", (0.4, 0.3, 0.06), (0, 1.25, 1.42), (255, 230, 120), 0.06, axis="z", R=rot(x=-8))
    for s in (-1, 1):
        m.ball("Clasp", 0.2, (s * 0.85, 1.95, 1.05), (240, 200, 80), mat="Metal")
    return m


@model
def hot_sauce_imp():
    m = Model("hot_sauce_imp")
    red = (210, 30, 25)
    deep = (150, 20, 20)
    m.cyl("Body", 1.5, 1.25, (0, 1.05, 0), red, refl=0.2)
    m.ell("Shoulder", (1.25, 0.6, 1.25), (0, 1.8, 0), red, refl=0.2)
    m.cyl("Neck", 0.5, 0.55, (0, 2.2, 0), red, refl=0.2)
    m.ring("NeckRing", (0, 2.02, 0), 0.3, 0.08, deep, normal="y", segments=10)
    # glass shine
    m.ell("Shine", (0.1, 0.5, 0.06), (-0.5, 1.72, -0.4), (255, 170, 160), R=rot(y=-50), tr=0.4)
    m.ell("Shine", (0.08, 0.3, 0.08), (-0.18, 1.9, -0.5), (255, 190, 180), R=rot(x=-30, y=-30), tr=0.2)
    # ridged cap on fire, with a little drip of sauce
    cap = m.cyl("Cap", 0.42, 0.68, (0, 2.62, 0), (40, 140, 60))
    for k in range(3):
        m.ring("CapRidge", (0, 2.48 + k * 0.13, 0), 0.34, 0.05, (30, 110, 45), normal="y", segments=10)
    m.fire(cap, size=1.4, heat=6)
    m.drip("Drip", (0.25, 2.42, -0.2), 0.35, 0.1, red, refl=0.3)
    # label: cream paper with a chili and flame stripes
    m.cyl("Label", 0.8, 1.3, (0, 1.05, 0), (250, 240, 215))
    m.ring("LabelEdge", (0, 1.45, 0), 0.65, 0.06, (230, 170, 40), normal="y", segments=14)
    m.ring("LabelEdge", (0, 0.65, 0), 0.65, 0.06, (230, 170, 40), normal="y", segments=14)
    for k in range(5):
        a = math.radians(-50 + k * 25)
        x, z = math.sin(a) * 0.66, -math.cos(a) * 0.66
        m.wedge("Flame", (0.16, 0.26, 0.04), (x, 0.8, z), (255, 140, 30) if k % 2 else (255, 200, 60), R=rot(y=-math.degrees(a)))
    m.ell("Chili", (0.48, 0.18, 0.1), (0.05, 0.98, -0.66), (220, 40, 30), R=rot(z=18))
    m.rod("ChiliStem", (-0.17, 0.92, -0.67), (-0.25, 1.0, -0.66), 0.05, (60, 150, 60))
    for k in range(3):
        x = 0.25 + k * 0.1
        for d in (-1, 1):
            m.blk("Hot", (0.03, 0.12, 0.02), (x, 1.22, -0.655), (180, 30, 30), R=rot(z=d * 35))
    # face: mischievous
    m.eyes(1.2, -0.62, 0.48, 0.36, lid=(250, 240, 215), angry=18, look=(0, -0.03), iris=(255, 180, 40), z_back=0.03)
    m.grin(0.92, -0.66, 0.34, curve=0.3, color=(90, 20, 20), bend=0.03)
    for s in (-1, 1):
        m.wedge("Fang", (0.06, 0.1, 0.04), (s * 0.08, 0.9, -0.67), WHITE, R=rot(x=180))
    # curved horns
    for s in (-1, 1):
        m.chain("Horn", [(s * 0.42, 1.92, -0.05), (s * 0.6, 2.08, -0.1), (s * 0.66, 2.26, -0.04)], 0.18, (120, 15, 15))
        m.ell("Horn", (0.1, 0.2, 0.1), (s * 0.67, 2.36, -0.02), (90, 10, 10))
    # arms on hips, pointy tail
    for s in (-1, 1):
        m.rod("Arm", (s * 0.6, 1.4, 0), (s * 0.95, 1.0, -0.05), 0.2, red)
        m.rod("Arm", (s * 0.95, 1.0, -0.05), (s * 0.65, 0.75, -0.2), 0.2, red)
        m.ball("Elbow", 0.22, (s * 0.95, 1.0, -0.05), red)
        m.mitt((s * 0.63, 0.74, -0.2), 0.24, deep, s, thumb=False)
    m.chain("Tail", [(0, 0.5, 0.6), (0.2, 0.4, 1.0), (0.45, 0.65, 1.25), (0.5, 1.0, 1.3)], 0.14, deep)
    m.wedge("TailTip", (0.12, 0.35, 0.35), (0.5, 1.2, 1.3), deep, R=rot(x=-90))
    m.wedge("TailTip", (0.12, 0.35, 0.35), (0.5, 1.2, 1.3), deep, R=rot(x=90))
    # pointy little shoes
    for s in (-1, 1):
        m.cyl("Leg", 0.3, 0.3, (s * 0.3, 0.3, 0), deep)
        m.shoe(s * 0.3, -0.15, 0.4, 0.6, (50, 30, 30), sole=(30, 20, 20))
        m.ell("Toe", (0.18, 0.18, 0.3), (s * 0.3, 0.2, -0.5), (50, 30, 30), R=rot(x=25))
    return m


@model
def spaghetti_hydra():
    m = Model("spaghetti_hydra")
    noodle = (240, 205, 120)
    noodle2 = (250, 220, 140)
    sauce = (195, 40, 30)
    meat = (125, 65, 40)
    meat2 = (100, 50, 30)
    # plate with a blue rim pattern
    m.cyl("Plate", 0.18, 3.6, (0, 0.09, 0), (245, 245, 250), refl=0.15)
    m.ring("PlateRim", (0, 0.19, 0), 1.65, 0.07, (70, 110, 200), normal="y", segments=16)
    m.ring("PlateRim", (0, 0.19, 0), 1.5, 0.035, (70, 110, 200), normal="y", segments=16)
    m.cyl("PlateInner", 0.2, 2.8, (0, 0.1, 0), (225, 228, 235))
    m.ell("Pile", (2.7, 1.1, 2.5), (0, 0.6, 0.1), noodle)
    # noodle loops wrapped around the pile
    for k in range(3):
        m.ring("Noodle", (0, 0.48 + k * 0.2, 0.1), 1.25 - k * 0.24, 0.1, noodle2 if k % 2 else noodle, normal="y", segments=12, R=rot(x=4 * (k - 1), z=5 * (k % 2)))
    for k in range(7):
        a = k * 2 * math.pi / 7
        x, z = math.cos(a) * 1.15, math.sin(a) * 1.0
        m.chain("Noodle", [(x, 0.22, z + 0.1), (x * 0.8, 0.6, z * 0.8 + 0.1), (x * 0.4, 1.0, z * 0.4 + 0.1)], 0.1, noodle2)
    # a stray noodle hanging over the plate edge
    m.chain("Noodle", [(1.2, 0.4, -0.6), (1.55, 0.25, -0.7), (1.75, 0.12, -0.85)], 0.1, noodle2)
    m.ell("Sauce", (1.8, 0.55, 1.7), (0, 1.05, 0.1), sauce, refl=0.25)
    for (x, z) in [(-0.6, -0.55), (0.7, -0.4), (0.2, 0.75), (-0.7, 0.5)]:
        m.drip("Sauce", (x, 1.0, z), 0.3, 0.2, sauce, refl=0.25)
    for (x, z, c) in [(-0.3, -0.2, (225, 70, 50)), (0.35, 0.2, (225, 70, 50)), (0.1, -0.45, (240, 90, 60))]:
        m.blk("Tomato", (0.18, 0.14, 0.18), (x, 1.3, z), c, R=rot(10, 40, 15))
    for (x, z, a) in [(0.35, 0.3, 30), (-0.45, 0.1, -40), (0.05, 0.55, 100)]:
        m.ell("Basil", (0.5, 0.08, 0.28), (x, 1.33, z), (60, 150, 60), R=rot(y=a, z=8))
    m.scatter("Cheese", (0, 1.05, 0.1), (1.8, 0.55, 1.7), 8, [(255, 250, 220), (250, 240, 200)], seed=5, d=0.09, shape="cube", ymin=0.4)
    # a fork stuck in the pile
    m.rod("Fork", (-1.0, 0.85, 0.7), (-1.5, 2.0, 1.05), 0.12, (205, 205, 215), mat="Metal")
    for k in range(3):
        m.rod("Fork", (-0.95 + k * 0.06, 0.85, 0.7), (-0.9 + k * 0.06, 0.5, 0.55), 0.05, (205, 205, 215), mat="Metal")
    heads = [((-1.0, 2.55, -0.55), [(-0.5, 1.0, 0.0), (-0.9, 1.7, 0.1), (-0.85, 2.2, -0.3)], -1),
             ((0.0, 3.25, -0.45), [(0.0, 1.1, 0.2), (0.25, 2.0, 0.2), (0.0, 2.8, -0.2)], 0),
             ((1.0, 2.55, -0.55), [(0.5, 1.0, 0.0), (0.95, 1.7, 0.1), (0.9, 2.2, -0.3)], 1)]
    for (hx, hy, hz), pts, s in heads:
        # each neck is a twist of three noodles
        for k, off in enumerate([(-0.06, 0, 0.02), (0.06, 0, -0.02)]):
            p = [(x + off[0] * (1 + 0.5 * math.sin(i + k)), y, z + off[2]) for i, (x, y, z) in enumerate(pts)]
            m.chain("Neck", p + [(hx + off[0], hy - 0.3, hz + 0.1 + off[2])], 0.17, noodle if k == 0 else noodle2)
        m.ball("Head", 1.0, (hx, hy, hz), meat)
        m.scatter("Bump", (hx, hy, hz), (1.0, 1.0, 1.0), 8, [meat2, (140, 75, 45)], seed=11 + s, d=0.13, shape="dot", ymin=-0.5)
        m.ell("HeadSauce", (0.82, 0.36, 0.82), (hx, hy + 0.38, hz + 0.05), sauce, refl=0.25)
        m.drip("HeadSauce", (hx + 0.25, hy + 0.3, hz - 0.3), 0.22, 0.12, sauce, refl=0.25)
        m.ell("Basil", (0.32, 0.06, 0.18), (hx - 0.1, hy + 0.58, hz + 0.05), (60, 150, 60), R=rot(y=30 + s * 40, z=10))
        m.eyes(hy + 0.05, hz - 0.45, 0.4, 0.3, lid=meat, x=hx, angry=10, iris=(230, 170, 40), z_back=0.03)
        m.grin(hy - 0.22, hz - 0.47, 0.34, color=(60, 20, 20), x=hx, open_=True, teeth=0, bend=0.05)
        for t in (-1, 1):
            m.wedge("Fang", (0.07, 0.12, 0.05), (hx + t * 0.1, hy - 0.2, hz - 0.5), WHITE, R=rot(x=180))
    return m


@model
def burrito_bouncer():
    m = Model("burrito_bouncer")
    tort = (230, 195, 135)
    grill = (175, 125, 70)
    m.cyl("Body", 2.4, 1.9, (0, 1.6, 0), tort)
    m.ell("Top", (1.9, 0.7, 1.9), (0, 2.8, 0), tort)
    # grill marks and toasty spots
    for k in range(4):
        m.rod("Grill", (-0.85, 1.55 + k * 0.35, -0.42), (-0.35, 1.75 + k * 0.35, -0.86), 0.06, grill, shape="B")
        m.rod("Grill", (0.85, 1.55 + k * 0.35, -0.42), (0.6, 1.65 + k * 0.35, -0.75), 0.06, grill, shape="B")
    m.scatter("Toast", (0, 1.6, 0), (1.95, 2.4, 1.95), 10, [(205, 160, 100)], seed=9, d=0.18, shape="dot", ymin=-0.6)
    # filling bursting out of the top
    m.ell("Filling", (1.45, 0.48, 1.45), (0, 3.02, 0), (120, 70, 45))
    m.ell("Rice", (1.1, 0.3, 1.1), (0.1, 3.12, 0.1), (250, 248, 235))
    for (x, z, c) in [(-0.35, -0.2, (90, 180, 70)), (0.3, 0.1, (220, 60, 50)), (0.0, 0.35, (250, 250, 240)), (-0.2, 0.3, (90, 180, 70)), (0.35, -0.3, (250, 220, 90)), (-0.45, 0.1, (220, 60, 50)), (0.15, -0.45, (90, 180, 70))]:
        m.ball("Topping", 0.3, (x, 3.2, z), c)
    for (x, z, a) in [(-0.55, -0.4, 20), (0.5, -0.45, -30)]:
        m.ell("Lettuce", (0.5, 0.1, 0.35), (x, 3.05, z), (110, 200, 80), R=rot(x=-25, y=a))
    # foil wrapper with crinkles
    m.cyl("Foil", 1.0, 1.98, (0, 0.55, 0), (210, 215, 225), mat="Foil", refl=0.35)
    m.blk("FoilEdge", (2.0, 0.16, 0.3), (0, 1.07, -0.9), (220, 225, 235), mat="Foil", R=rot(z=4))
    for k in range(7):
        a = math.radians(-70 + k * 23)
        m.blk("Crinkle", (0.06, 0.7, 0.05), (math.sin(a) * 1.0, 0.55, -math.cos(a) * 1.0), (185, 190, 205), mat="Foil", R=rot(y=-math.degrees(a), z=12 * (1 if k % 2 else -1)))
    # tortilla fold seam
    m.blk("Fold", (0.12, 1.5, 0.1), (0.35, 1.95, -0.95), (205, 165, 110))
    m.blk("Fold", (0.9, 0.1, 0.1), (0.55, 2.68, -0.75), (205, 165, 110), R=rot(z=-8))
    # mirror shades with a frame, a stern mouth and a furrowed brow
    for s in (-1, 1):
        m.rbox("Shades", (0.62, 0.4, 0.12), (s * 0.38, 2.3, -0.96), (20, 20, 25), 0.1, axis="z", refl=0.5)
        m.ell("ShadesShine", (0.2, 0.08, 0.04), (s * 0.38 - 0.12, 2.4, -1.03), (150, 170, 220), R=rot(z=20), mat="Neon", tr=0.3)
        m.brow(s * 0.36, 2.6, -0.86, 0.36, (150, 105, 60), s, tilt=14, d=0.1)
    m.blk("ShadesBridge", (0.3, 0.1, 0.1), (0, 2.38, -0.97), (20, 20, 25))
    m.grin(1.88, -0.97, 0.5, curve=-0.08, color=(90, 40, 30))
    m.ell("Chin", (0.4, 0.12, 0.1), (0, 1.72, -0.95), (210, 170, 115))
    m.cyl("Earpiece", 0.2, 0.2, (0.96, 2.2, -0.2), (30, 30, 30), axis="x")
    m.chain("EarWire", [(1.0, 2.1, -0.2), (1.05, 1.7, 0.0), (0.98, 1.3, 0.1)], 0.05, (30, 30, 30), joints=False)
    # big crossed arms with bicep bulges and knuckles
    m.rod("Arm", (-0.95, 1.95, -0.2), (0.55, 1.45, -1.15), 0.5, tort, shape="E")
    m.rod("Arm", (0.95, 1.95, -0.2), (-0.55, 1.45, -1.05), 0.5, tort, shape="E")
    m.ell("Bicep", (0.62, 0.55, 0.62), (-0.85, 1.85, -0.35), tort)
    m.ell("Bicep", (0.62, 0.55, 0.62), (0.85, 1.85, -0.35), tort)
    m.ball("Fist", 0.52, (0.62, 1.47, -1.17), tort)
    m.ball("Fist", 0.52, (-0.62, 1.47, -1.07), tort)
    for k in range(3):
        m.ball("Knuckle", 0.13, (0.62 + (k - 1) * 0.13, 1.66, -1.3), grill)
        m.ball("Knuckle", 0.13, (-0.62 + (k - 1) * 0.13, 1.66, -1.2), grill)
    # gold chain with a hot pepper medallion
    m.ring("Chain", (0, 2.0, -0.05), 0.85, 0.08, (240, 200, 60), normal="y", segments=14, R=rot(x=-12), mat="Metal")
    m.cyl("Medal", 0.06, 0.3, (0.0, 1.88, -0.98), (250, 210, 70), axis="z", mat="Metal", refl=0.3)
    # sneakers
    for s in (-1, 1):
        m.shoe(s * 0.5, -0.3, 0.62, 0.85, (245, 245, 250), sole=(200, 40, 40), toe=(225, 225, 235), lace=(40, 40, 45))
    return m


@model
def queen_parfait():
    m = Model("queen_parfait")
    glass = (220, 235, 245)
    m.cyl("Base", 0.18, 1.8, (0, 0.09, 0), glass, mat="Glass", tr=0.35, refl=0.25)
    m.ring("BaseRim", (0, 0.18, 0), 0.88, 0.06, (250, 210, 90), normal="y", segments=14, mat="Metal")
    m.cyl("Stem", 0.9, 0.42, (0, 0.6, 0), glass, mat="Glass", tr=0.35, refl=0.25)
    m.ball("StemKnob", 0.55, (0, 0.62, 0), glass, mat="Glass", tr=0.35, refl=0.25)
    m.cyl("Bowl", 2.5, 2.3, (0, 2.3, 0), (225, 240, 250), mat="Glass", tr=0.6, refl=0.3)
    m.ring("BowlRim", (0, 3.55, 0), 1.15, 0.1, (250, 210, 90), normal="y", segments=18, mat="Metal")
    layers = [(1.3, (220, 50, 70)), (1.85, (255, 245, 230)), (2.4, (90, 70, 190)), (2.95, (255, 180, 200))]
    for i, (y, c) in enumerate(layers):
        m.cyl("Layer", 0.55, 2.1, (0, y, 0), c)
        # granola crumbs between the layers
        if i < 3:
            for k in range(8):
                a = k * 2 * math.pi / 8 + i
                m.blk("Granola", (0.14, 0.1, 0.12), (math.cos(a) * 1.02, y + 0.27, math.sin(a) * 1.02), (200, 150, 80), R=rot(20, k * 30, 10))
    for (x, y, z) in [(-0.7, 1.6, -0.8), (0.6, 2.1, -0.85), (-0.3, 2.65, -0.95), (0.8, 2.75, -0.6), (0.85, 1.4, -0.5), (-0.9, 2.3, -0.5)]:
        m.ball("Berry", 0.34, (x, y, z), (70, 60, 170), refl=0.2)
    # whipped cream swirl
    for k, (w, y) in enumerate([(2.45, 3.65), (2.0, 3.92), (1.7, 4.12), (1.3, 4.35), (0.9, 4.55)]):
        m.ell("Cream", (w, 0.55, w), (0.04 * (k % 2), y, 0.03 * k), (255, 250, 245))
    m.scatter("Sprinkle", (0, 4.0, 0), (2.0, 1.2, 2.0), 16, [(255, 90, 130), (90, 200, 255), (255, 220, 60), (150, 230, 120)], seed=2, d=0.06, ymin=0.3)
    # face
    m.eyes(3.75, -1.12, 0.62, 0.38, lid=(255, 250, 245), iris=(180, 60, 150), lash=3, z_back=0.03)
    m.grin(3.42, -1.15, 0.36, curve=0.28, open_=True, teeth=0, color=(200, 50, 90), bend=0.03)
    m.cheeks(3.5, -1.1, 1.2, 0.3)
    # crown with gems
    m.cyl("Crown", 0.38, 1.0, (0, 4.9, 0), (245, 200, 60), mat="Metal", refl=0.25)
    m.ring("CrownBand", (0, 4.75, 0), 0.5, 0.07, (255, 230, 120), normal="y", segments=12, mat="Metal")
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 2
        m.ell("CrownPoint", (0.2, 0.42, 0.2), (math.cos(a) * 0.45, 5.18, -math.sin(a) * 0.45), (245, 200, 60), mat="Metal")
        m.ball("CrownPoint", 0.1, (math.cos(a) * 0.45, 5.42, -math.sin(a) * 0.45), (255, 245, 200), mat="Neon")
    gem = m.ball("CrownGem", 0.24, (0, 4.92, -0.52), (255, 60, 120), mat="Neon")
    for s in (-1, 1):
        m.ball("CrownGem", 0.14, (s * 0.32, 4.92, -0.4), (90, 200, 255), mat="Glass", refl=0.3)
    m.ball("Cherry", 0.5, (0.0, 5.35, 0.0), (210, 20, 40), refl=0.35)
    m.ball("CherryShine", 0.14, (-0.12, 5.48, -0.18), (255, 200, 200), tr=0.2)
    m.rod("CherryStem", (0, 5.55, 0), (0.18, 5.9, 0.1), 0.06, (90, 140, 50))
    m.sparkles(gem, (255, 170, 220))
    m.light(gem, (255, 150, 200), 1.2, 8)
    # a wafer stick and a mint leaf in the cream
    m.blk("WaferStick", (0.18, 0.9, 0.3), (-0.65, 4.2, 0.35), (220, 175, 100), R=rot(z=20))
    m.ell("Mint", (0.4, 0.08, 0.22), (0.55, 4.45, 0.3), (80, 190, 110), R=rot(z=-25, y=30))
    # arms and a wafer scepter topped with a strawberry
    for s in (-1, 1):
        m.rod("Arm", (s * 1.12, 2.6, 0), (s * 1.6, 2.2, -0.35), 0.24, (255, 210, 225))
        m.cyl("Cuff", 0.1, 0.3, (s * 1.5, 2.28, -0.28), (255, 250, 245), R=rot(y=s * 35) @ rot(z=s * 40))
        m.mitt((s * 1.62, 2.18, -0.38), 0.3, (255, 210, 225), s)
    m.blk("Wafer", (0.26, 2.2, 0.26), (1.62, 2.6, -0.4), (220, 175, 100), R=rot(z=-8))
    for k in range(5):
        m.blk("WaferStripe", (0.28, 0.05, 0.28), (1.62 + 0.03 * (k - 2), 1.75 + k * 0.38, -0.4), (180, 130, 70), R=rot(z=-8))
    m.ell("ScepterTop", (0.58, 0.62, 0.58), (1.78, 3.72, -0.4), (225, 40, 60), refl=0.15)
    m.ring("ScepterBand", (1.76, 3.45, -0.4), 0.18, 0.06, (250, 210, 90), normal="y", segments=8, mat="Metal")
    # a raspberry cape hanging from the shoulders with an ermine-style trim
    m.ell("Cape", (1.5, 1.5, 0.3), (0, 3.25, 1.2), (200, 60, 120), mat="Fabric", R=rot(x=-4))
    m.ell("Cape", (2.3, 1.9, 0.34), (0, 2.2, 1.3), (200, 60, 120), mat="Fabric", R=rot(x=-8))
    m.ell("CapeFold", (0.22, 1.7, 0.2), (-0.45, 2.3, 1.46), (170, 45, 100), mat="Fabric", R=rot(x=-8, z=6))
    m.ell("CapeFold", (0.22, 1.7, 0.2), (0.45, 2.3, 1.46), (170, 45, 100), mat="Fabric", R=rot(x=-8, z=-6))
    for k in range(6):
        x = -0.95 + k * 0.38
        m.ell("CapeTrim", (0.4, 0.26, 0.3), (x, 1.32 + 0.04 * abs(k - 2.5), 1.43), (255, 250, 245), mat="Fabric")
        m.ell("CapeTrim", (0.07, 0.11, 0.05), (x, 1.32 + 0.04 * abs(k - 2.5), 1.6), (40, 30, 40))
    m.ell("Collar", (1.6, 0.35, 0.6), (0, 3.62, 0.85), (255, 250, 245), mat="Fabric")
    return m
