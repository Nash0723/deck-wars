# Snack family models (warm, food colors)
import math
from modelkit import Model, rot, Rx, Ry, Rz, WHITE, BLACK, PUPIL

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


@model
def jelly_bean_scout():
    m = Model("jelly_bean_scout")
    body = (235, 60, 105)
    dark = (190, 40, 80)
    m.ell("Body", (1.5, 2.0, 1.3), (0, 1.3, 0), body, R=rot(z=-8), refl=0.15)
    m.ell("Belly", (1.0, 1.2, 0.5), (0.05, 1.1, -0.45), (255, 120, 150), refl=0.1)
    # legs and feet
    for s in (-1, 1):
        m.cyl("Leg", 0.55, 0.32, (s * 0.35, 0.38, 0), dark)
        m.ell("Foot", (0.42, 0.24, 0.62), (s * 0.36, 0.12, -0.1), (60, 50, 70))
    # arms: one waving
    m.rod("Arm", (-0.65, 1.35, 0), (-1.05, 0.85, -0.1), 0.24, dark)
    m.rod("Arm", (0.65, 1.4, 0), (1.05, 1.95, -0.1), 0.24, dark)
    m.ball("Hand", 0.3, (-1.07, 0.82, -0.1), dark)
    m.ball("Hand", 0.3, (1.07, 1.98, -0.1), dark)
    # scout hat
    m.cyl("HatBrim", 0.1, 1.45, (0, 2.27, 0), (185, 145, 85))
    m.cyl("HatCrown", 0.42, 0.85, (0, 2.5, 0), (195, 155, 95))
    m.cyl("HatBand", 0.12, 0.88, (0, 2.36, 0), (110, 70, 40))
    m.ell("HatDent", (0.5, 0.15, 0.6), (0, 2.72, 0), (170, 130, 75))
    # merit badges and a little backpack
    for (x, y, c) in [(-0.22, 1.0, (60, 140, 230)), (0.18, 0.92, (90, 200, 90))]:
        m.cyl("Badge", 0.08, 0.24, (x, y, -0.66), c, axis="z")
    m.blk("Backpack", (0.9, 0.9, 0.45), (0.0, 1.35, 0.7), (90, 130, 70), mat="Fabric")
    m.blk("BackpackFlap", (0.92, 0.3, 0.48), (0.0, 1.72, 0.7), (70, 105, 55), mat="Fabric")
    m.ell("Bedroll", (1.0, 0.32, 0.32), (0.0, 1.95, 0.72), (180, 60, 50))
    m.eyes(1.78, -0.5, 0.52, 0.4, lid=body)
    m.smile(1.5, -0.6, 0.32, open_=True)
    return m


@model
def pretzel_guard():
    m = Model("pretzel_guard")
    bread = (175, 105, 45)
    dark = (140, 80, 35)
    salt = (250, 250, 245)
    m.ell("Body", (2.0, 2.4, 1.7), (0, 1.35, 0), bread, refl=0.1)
    for (x, y, z) in [(-0.4, 2.2, -0.55), (0.3, 2.35, -0.45), (0.65, 1.8, -0.7), (-0.75, 1.5, -0.6), (0.1, 0.85, -0.85), (-0.2, 2.5, 0.1)]:
        m.blk("Salt", (0.14, 0.12, 0.14), (x, y, z), salt, R=rot(20, 35, 10))
    # helmet
    m.ell("Helmet", (1.6, 0.9, 1.5), (0, 2.45, 0.05), (190, 195, 205), mat="Metal", refl=0.2)
    m.blk("HelmetRim", (1.7, 0.16, 0.2), (0, 2.18, -0.68), (160, 165, 175), mat="Metal")
    m.cyl("Plume", 0.7, 0.22, (0, 3.05, 0.1), (220, 50, 50))
    m.ell("PlumeTop", (0.3, 0.5, 0.9), (0, 3.4, 0.25), (230, 60, 60), R=rot(x=20))
    m.eyes(1.82, -0.78, 0.6, 0.38, lid=bread, angry=12)
    m.smile(1.42, -0.82, 0.36)
    # legs
    for s in (-1, 1):
        m.cyl("Leg", 0.5, 0.42, (s * 0.45, 0.3, 0), dark)
        m.ell("Foot", (0.55, 0.3, 0.75), (s * 0.47, 0.12, -0.12), (90, 60, 40))
    # pretzel shield (two loops and a twist) held on the left
    sx, sy, sz = -1.0, 1.25, -0.95
    for k in (-1, 1):
        m.ring("Shield", (sx + k * 0.33, sy + 0.12, sz), 0.38, 0.2, dark, normal="z", segments=8)
    m.rod("Shield", (sx - 0.62, sy - 0.25, sz), (sx + 0.62, sy - 0.25, sz), 0.22, dark)
    m.rod("Shield", (sx - 0.35, sy - 0.5, sz), (sx + 0.3, sy + 0.2, sz), 0.2, dark)
    m.rod("Shield", (sx + 0.35, sy - 0.5, sz), (sx - 0.3, sy + 0.2, sz), 0.2, dark)
    for (x, y) in [(-0.2, 0.25), (0.25, -0.2), (0.0, 0.0)]:
        m.blk("Salt", (0.1, 0.1, 0.1), (sx + x, sy + y, sz - 0.12), salt, R=rot(30, 30, 0))
    m.rod("Arm", (-0.85, 1.55, -0.2), (-1.0, 1.25, -0.8), 0.3, bread)
    # breadstick spear on the right
    m.rod("Arm", (0.9, 1.5, -0.1), (1.2, 1.3, -0.45), 0.3, bread)
    m.cyl("Spear", 3.0, 0.2, (1.25, 1.6, -0.5), (215, 170, 100))
    m.ell("SpearTip", (0.32, 0.6, 0.32), (1.25, 3.25, -0.5), (200, 150, 80))
    m.ball("Hand", 0.32, (1.25, 1.3, -0.5), bread)
    return m


@model
def pancake_paladin():
    m = Model("pancake_paladin")
    cake = (225, 160, 75)
    edge = (190, 115, 45)
    for i, (y, dx) in enumerate([(0.75, 0.0), (1.25, 0.08), (1.75, -0.06)]):
        m.cyl("Pancake", 0.5, 2.5, (dx, y, 0), edge)
        m.cyl("PancakeFace", 0.52, 2.3, (dx, y, 0), cake)
    m.cyl("Syrup", 0.14, 2.3, (0, 2.05, 0), (160, 70, 20), refl=0.3)
    for (x, z, ln) in [(-1.05, -0.3, 0.6), (0.7, -0.85, 0.8), (1.1, 0.4, 0.5), (-0.4, -1.1, 0.45)]:
        m.ell("Drip", (0.28, ln, 0.28), (x, 2.0 - ln / 2, z), (165, 75, 25), refl=0.3)
    m.blk("Butter", (0.75, 0.42, 0.75), (0.1, 2.32, 0.1), (255, 230, 120), R=rot(y=20))
    # helmet made of a strawberry
    m.ell("Strawberry", (0.6, 0.7, 0.6), (-0.15, 2.85, 0.1), (230, 40, 50))
    m.cyl("Leaves", 0.12, 0.5, (-0.15, 3.18, 0.1), (60, 160, 60))
    m.eyes(1.33, -1.2, 0.7, 0.42, lid=cake)
    m.smile(0.83, -1.24, 0.42, open_=True)
    m.cheeks(0.95, -1.18, 1.25, 0.28)
    # stubby legs
    for s in (-1, 1):
        m.cyl("Leg", 0.55, 0.38, (s * 0.5, 0.3, 0), edge)
        m.ell("Foot", (0.5, 0.28, 0.7), (s * 0.5, 0.12, -0.15), (110, 70, 40))
    # fork sword in the right hand
    m.rod("Arm", (1.2, 1.3, 0), (1.55, 1.2, -0.45), 0.28, edge)
    m.ball("Hand", 0.34, (1.55, 1.2, -0.48), edge)
    m.cyl("ForkHandle", 1.2, 0.18, (1.55, 1.25, -0.5), (200, 200, 210), mat="Metal")
    m.blk("ForkNeck", (0.5, 0.25, 0.12), (1.55, 1.95, -0.5), (200, 200, 210), mat="Metal")
    for k in range(4):
        m.blk("ForkTine", (0.08, 0.9, 0.08), (1.37 + k * 0.12, 2.5, -0.5), (215, 215, 225), mat="Metal")
    # round waffle shield in the left hand
    m.rod("Arm", (-1.2, 1.3, 0), (-1.45, 1.15, -0.5), 0.28, edge)
    m.cyl("Shield", 0.18, 1.3, (-1.5, 1.2, -0.62), (215, 150, 70), axis="z")
    for k in (-1, 0, 1):
        m.blk("ShieldGrid", (1.0, 0.07, 0.06), (-1.5, 1.2 + k * 0.3, -0.73), (170, 105, 45))
        m.blk("ShieldGrid", (0.07, 1.0, 0.06), (-1.5 + k * 0.3, 1.2, -0.73), (170, 105, 45))
    # little blue cape on the back
    m.blk("Cape", (1.8, 1.6, 0.1), (0, 1.15, 1.3), (60, 90, 200), mat="Fabric", R=rot(x=-8))
    return m


@model
def hot_sauce_imp():
    m = Model("hot_sauce_imp")
    red = (210, 30, 25)
    m.cyl("Body", 1.5, 1.25, (0, 1.05, 0), red, refl=0.15)
    m.ell("Shoulder", (1.25, 0.6, 1.25), (0, 1.8, 0), red, refl=0.15)
    m.cyl("Neck", 0.5, 0.55, (0, 2.2, 0), red, refl=0.15)
    cap = m.cyl("Cap", 0.4, 0.66, (0, 2.6, 0), (40, 140, 60))
    m.fire(cap, size=1.4, heat=6)
    m.cyl("Label", 0.75, 1.3, (0, 1.05, 0), (250, 240, 215))
    m.blk("Chili", (0.5, 0.16, 0.08), (0, 0.78, -0.66), (220, 40, 30), R=rot(z=15))
    m.eyes(1.2, -0.62, 0.48, 0.36, lid=(250, 240, 215), angry=18, look=(0, -0.03))
    m.smile(0.93, -0.66, 0.3, color=(90, 20, 20))
    # horns
    for s in (-1, 1):
        m.rod("Horn", (s * 0.42, 1.95, -0.05), (s * 0.6, 2.32, -0.12), 0.2, (120, 15, 15), shape="E")
    # arms on hips, tail
    for s in (-1, 1):
        m.rod("Arm", (s * 0.6, 1.4, 0), (s * 0.95, 1.0, -0.05), 0.2, red)
        m.rod("Arm", (s * 0.95, 1.0, -0.05), (s * 0.65, 0.75, -0.2), 0.2, red)
    m.chain("Tail", [(0, 0.5, 0.6), (0.2, 0.4, 1.0), (0.45, 0.65, 1.25), (0.5, 1.0, 1.3)], 0.14, (150, 20, 20))
    m.wedge("TailTip", (0.12, 0.35, 0.35), (0.5, 1.2, 1.3), (150, 20, 20), R=rot(x=-90))
    for s in (-1, 1):
        m.ell("Foot", (0.4, 0.25, 0.6), (s * 0.3, 0.12, -0.15), (50, 30, 30))
    return m


@model
def spaghetti_hydra():
    m = Model("spaghetti_hydra")
    noodle = (240, 205, 120)
    sauce = (195, 40, 30)
    meat = (125, 65, 40)
    m.cyl("Plate", 0.18, 3.5, (0, 0.09, 0), (245, 245, 250), refl=0.1)
    m.cyl("PlateInner", 0.2, 2.8, (0, 0.1, 0), (225, 228, 235))
    m.ell("Pile", (2.7, 1.1, 2.5), (0, 0.6, 0.1), noodle)
    for k in range(7):
        a = k * 2 * math.pi / 7
        x, z = math.cos(a) * 1.05, math.sin(a) * 0.95
        m.rod("Noodle", (x, 0.35, z + 0.1), (x * 0.4, 1.0, z * 0.4 + 0.1), 0.12, (250, 215, 130))
    m.ell("Sauce", (1.8, 0.55, 1.7), (0, 1.05, 0.1), sauce, refl=0.2)
    m.ell("Basil", (0.5, 0.1, 0.3), (0.35, 1.32, 0.3), (60, 150, 60), R=rot(y=30))
    for k in range(5):
        m.blk("Cheese", (0.12, 0.06, 0.12), (-0.5 + k * 0.25, 1.32, 0.0 + (k % 2) * 0.2), (255, 250, 220))
    heads = [((-1.0, 2.55, -0.55), [(-0.5, 1.0, 0.0), (-0.9, 1.7, 0.1), (-0.85, 2.2, -0.3)]),
             ((0.0, 3.25, -0.45), [(0.0, 1.1, 0.2), (0.25, 2.0, 0.2), (0.0, 2.8, -0.2)]),
             ((1.0, 2.55, -0.55), [(0.5, 1.0, 0.0), (0.95, 1.7, 0.1), (0.9, 2.2, -0.3)])]
    for (hx, hy, hz), pts in heads:
        m.chain("Neck", pts + [(hx, hy - 0.3, hz + 0.1)], 0.28, noodle)
        m.ball("Head", 1.0, (hx, hy, hz), meat)
        m.ell("HeadSauce", (0.8, 0.35, 0.8), (hx, hy + 0.38, hz + 0.05), sauce, refl=0.2)
        m.eyes(hy + 0.05, hz - 0.45, 0.4, 0.3, lid=meat, x=hx, angry=10)
        m.smile(hy - 0.22, hz - 0.47, 0.3, color=(60, 20, 20), x=hx, open_=True)
    return m


@model
def burrito_bouncer():
    m = Model("burrito_bouncer")
    tort = (230, 195, 135)
    m.cyl("Body", 2.4, 1.9, (0, 1.6, 0), tort)
    m.ell("Top", (1.9, 0.7, 1.9), (0, 2.8, 0), tort)
    m.ell("Filling", (1.4, 0.45, 1.4), (0, 3.02, 0), (120, 70, 45))
    for (x, z, c) in [(-0.35, -0.2, (90, 180, 70)), (0.3, 0.1, (220, 60, 50)), (0.0, 0.35, (250, 250, 240)), (-0.2, 0.3, (90, 180, 70)), (0.35, -0.3, (250, 220, 90))]:
        m.ball("Topping", 0.32, (x, 3.18, z), c)
    m.cyl("Foil", 1.0, 1.98, (0, 0.55, 0), (210, 215, 225), mat="Foil", refl=0.3)
    m.blk("FoilEdge", (2.0, 0.16, 0.3), (0, 1.07, -0.9), (220, 225, 235), mat="Foil", R=rot(z=4))
    # fold line
    m.blk("Fold", (0.12, 1.5, 0.1), (0.35, 1.95, -0.95), (205, 165, 110))
    # sunglasses
    for s in (-1, 1):
        m.blk("Shades", (0.62, 0.38, 0.12), (s * 0.38, 2.3, -0.96), (20, 20, 25), refl=0.4)
    m.blk("ShadesBridge", (0.3, 0.1, 0.1), (0, 2.38, -0.97), (20, 20, 25))
    m.blk("Mouth", (0.5, 0.08, 0.08), (0, 1.88, -0.97), (90, 40, 30))
    m.cyl("Earpiece", 0.2, 0.2, (0.96, 2.2, -0.2), (30, 30, 30), axis="x")
    m.chain("EarWire", [(1.0, 2.1, -0.2), (1.05, 1.7, 0.0), (0.98, 1.3, 0.1)], 0.05, (30, 30, 30), joints=False)
    # big crossed arms
    m.rod("Arm", (-0.95, 1.95, -0.2), (0.55, 1.45, -1.15), 0.48, tort, shape="E")
    m.rod("Arm", (0.95, 1.95, -0.2), (-0.55, 1.45, -1.05), 0.48, tort, shape="E")
    m.ball("Fist", 0.5, (0.62, 1.47, -1.17), tort)
    m.ball("Fist", 0.5, (-0.62, 1.47, -1.07), tort)
    # gold chain
    m.ring("Chain", (0, 2.0, -0.05), 0.85, 0.08, (240, 200, 60), normal="y", segments=12, R=rot(x=-12), mat="Metal")
    for s in (-1, 1):
        m.ell("Foot", (0.6, 0.3, 0.8), (s * 0.5, 0.15, -0.3), (40, 40, 45))
    return m


@model
def queen_parfait():
    m = Model("queen_parfait")
    m.cyl("Base", 0.18, 1.8, (0, 0.09, 0), (220, 235, 245), mat="Glass", tr=0.35, refl=0.2)
    m.cyl("Stem", 0.9, 0.42, (0, 0.6, 0), (220, 235, 245), mat="Glass", tr=0.35, refl=0.2)
    m.cyl("Bowl", 2.5, 2.3, (0, 2.3, 0), (225, 240, 250), mat="Glass", tr=0.6, refl=0.25)
    layers = [(1.3, (220, 50, 70)), (1.85, (255, 245, 230)), (2.4, (90, 70, 190)), (2.95, (255, 180, 200))]
    for y, c in layers:
        m.cyl("Layer", 0.55, 2.1, (0, y, 0), c)
    for (x, y, z) in [(-0.7, 1.6, -0.8), (0.6, 2.1, -0.85), (-0.3, 2.65, -0.95), (0.8, 2.75, -0.6)]:
        m.ball("Berry", 0.32, (x, y, z), (70, 60, 170))
    m.ell("Cream", (2.4, 0.9, 2.4), (0, 3.65, 0), (255, 250, 245))
    m.ell("Cream2", (1.7, 0.75, 1.7), (0, 4.1, 0), (255, 250, 245))
    m.ell("Cream3", (1.0, 0.6, 1.0), (0, 4.5, 0), (255, 250, 245))
    m.eyes(3.75, -1.12, 0.62, 0.38, lid=(255, 250, 245))
    m.smile(3.4, -1.15, 0.32, open_=True)
    m.cheeks(3.5, -1.1, 1.2, 0.3)
    # crown
    m.cyl("Crown", 0.38, 1.0, (0, 4.9, 0), (245, 200, 60), mat="Metal", refl=0.2)
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 2
        m.ell("CrownPoint", (0.2, 0.42, 0.2), (math.cos(a) * 0.45, 5.18, -math.sin(a) * 0.45), (245, 200, 60), mat="Metal")
    gem = m.ball("Gem", 0.24, (0, 4.92, -0.52), (255, 60, 120), mat="Neon")
    m.ball("Cherry", 0.48, (0.0, 5.35, 0.0), (210, 20, 40), refl=0.3)
    m.rod("CherryStem", (0, 5.55, 0), (0.18, 5.9, 0.1), 0.06, (90, 140, 50))
    m.sparkles(gem, (255, 170, 220))
    m.light(gem, (255, 150, 200), 1.2, 8)
    # arms with a wafer scepter
    for s in (-1, 1):
        m.rod("Arm", (s * 1.12, 2.6, 0), (s * 1.6, 2.2, -0.35), 0.24, (255, 210, 225))
        m.ball("Hand", 0.3, (s * 1.62, 2.18, -0.38), (255, 210, 225))
    m.blk("Wafer", (0.26, 2.2, 0.26), (1.62, 2.6, -0.4), (220, 175, 100), R=rot(z=-8))
    m.ell("WaferTop", (0.55, 0.55, 0.55), (1.78, 3.7, -0.4), (225, 40, 60))
    # cape of whipped cream on the back
    # a raspberry cape hanging from the shoulders, wider at the bottom
    m.ell("Cape", (1.5, 1.5, 0.3), (0, 3.25, 1.2), (200, 60, 120), mat="Fabric", R=rot(x=-4))
    m.ell("Cape", (2.3, 1.9, 0.34), (0, 2.2, 1.3), (200, 60, 120), mat="Fabric", R=rot(x=-8))
    m.ell("CapeFold", (0.22, 1.7, 0.2), (-0.45, 2.3, 1.46), (170, 45, 100), mat="Fabric", R=rot(x=-8, z=6))
    m.ell("CapeFold", (0.22, 1.7, 0.2), (0.45, 2.3, 1.46), (170, 45, 100), mat="Fabric", R=rot(x=-8, z=-6))
    for k in range(5):
        m.ball("CapeTrim", 0.2, (-0.8 + k * 0.4, 1.33 + 0.05 * abs(k - 2), 1.42), (255, 215, 90), mat="Metal")
    return m
