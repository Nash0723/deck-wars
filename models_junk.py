# Junk family models (rusty metal, old furniture, glitter)
import math
from modelkit import Model, rot, WHITE, PUPIL

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


@model
def tin_can_tom():
    m = Model("tin_can_tom")
    tin = (185, 190, 200)
    m.cyl("Body", 1.5, 1.2, (0, 1.15, 0), tin, mat="Metal", refl=0.25, R=rot(z=4))
    m.cyl("Label", 0.8, 1.24, (0.03, 1.1, 0), (200, 60, 50), R=rot(z=4))
    m.cyl("LabelStripe", 0.16, 1.26, (0.03, 1.1, 0), (250, 220, 90), R=rot(z=4))
    for y in (0.5, 1.82):
        m.cyl("Rim", 0.08, 1.28, (0.04 * (y - 1.15), y, 0), (160, 165, 175), mat="Metal", R=rot(z=4))
    # lid peeled open like a hat
    m.cyl("Lid", 0.06, 1.15, (-0.1, 2.1, 0.25), (200, 205, 215), mat="Metal", refl=0.3, R=rot(x=35, z=4))
    m.blk("PullTab", (0.3, 0.04, 0.16), (-0.1, 2.3, 0.0), (170, 175, 185), mat="Metal", R=rot(x=35))
    # dent
    m.ell("Dent", (0.4, 0.3, 0.2), (0.45, 1.5, -0.5), (150, 155, 165), mat="Metal")
    m.eyes(1.25, -0.6, 0.46, 0.38, lid=(200, 60, 50))
    m.smile(0.9, -0.64, 0.3, open_=True)
    # stick limbs
    for s in (-1, 1):
        m.rod("Arm", (s * 0.6, 1.25, 0), (s * 1.0, 0.9 + (0.5 if s > 0 else 0), -0.1), 0.1, (120, 90, 60))
        m.rod("Leg", (s * 0.28, 0.45, 0), (s * 0.35, 0.05, -0.05), 0.12, (120, 90, 60))
        m.ell("Shoe", (0.35, 0.18, 0.5), (s * 0.36, 0.08, -0.12), (60, 60, 70))
    m.ball("Hand", 0.18, (1.0, 1.42, -0.1), (120, 90, 60))
    m.ball("Hand", 0.18, (-1.0, 0.9, -0.1), (120, 90, 60))
    return m


@model
def couch_golem():
    m = Model("couch_golem")
    fab = (80, 140, 130)
    dark = (60, 110, 100)
    wood = (110, 75, 45)
    # base and seat cushions
    m.blk("Base", (3.2, 0.9, 1.7), (0, 0.85, 0), dark, mat="Fabric")
    for s in (-1, 1):
        m.blk("Cushion", (1.45, 0.45, 1.5), (s * 0.75, 1.5, -0.08), fab, mat="Fabric")
    # backrest is the head
    m.blk("Back", (3.2, 1.9, 0.6), (0, 2.1, 0.62), dark, mat="Fabric")
    m.blk("BackPad", (2.8, 1.4, 0.3), (0, 2.25, 0.25), fab, mat="Fabric")
    for x in (-0.9, 0, 0.9):
        m.cyl("Button", 0.05, 0.14, (x, 2.75, 0.09), (40, 70, 65), axis="z")
    m.eyes(2.28, 0.08, 0.95, 0.5, lid=fab)
    m.blk("Mouth", (0.9, 0.12, 0.08), (0, 1.85, 0.08), (40, 60, 55))
    # armrests as arms with fists
    for s in (-1, 1):
        m.blk("Armrest", (0.5, 1.0, 1.9), (s * 1.65, 1.35, -0.05), dark, mat="Fabric")
        m.ell("ArmRoll", (0.6, 0.6, 1.95), (s * 1.65, 1.85, -0.05), fab, mat="Fabric")
        m.ball("Fist", 0.7, (s * 1.7, 1.55, -1.15), fab, mat="Fabric")
    # wooden legs
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cyl("Leg", 0.4, 0.28, (sx * 1.35, 0.2, sz * 0.6), wood)
    # a spring poking out and a lost coin
    m.chain("Spring", [(0.7, 1.72, -0.45), (0.85, 1.92, -0.5), (0.65, 2.0, -0.55), (0.82, 2.15, -0.6)], 0.07, (170, 170, 180), mat="Metal", joints=False)
    m.cyl("Coin", 0.05, 0.3, (-0.6, 1.74, -0.6), (240, 200, 60), mat="Metal")
    return m


@model
def rusty_shopping_cart():
    m = Model("rusty_shopping_cart")
    rust = (150, 95, 60)
    metal = "CorrodedMetal"
    # basket panels (see-through wire look)
    m.blk("Floor", (2.0, 0.1, 2.6), (0, 1.0, 0), rust, mat=metal)
    for s in (-1, 1):
        m.blk("Side", (0.08, 1.2, 2.6), (s * 1.0, 1.6, 0), rust, mat=metal, tr=0.35)
    m.blk("Front", (2.0, 1.2, 0.08), (0, 1.6, -1.3), rust, mat=metal, tr=0.25)
    m.blk("BackGate", (2.0, 1.2, 0.08), (0, 1.6, 1.3), rust, mat=metal, tr=0.35)
    for (x, z, L, axis) in [(-1.0, 0, 2.7, "z"), (1.0, 0, 2.7, "z"), (0, -1.3, 2.1, "x"), (0, 1.3, 2.1, "x")]:
        m.cyl("Rim", L, 0.1, (x, 2.2, z), (170, 110, 70), axis=axis, mat=metal)
    for x in (-0.5, 0, 0.5):
        m.blk("Wire", (0.05, 1.2, 0.05), (x, 1.6, -1.33), (170, 110, 70), mat=metal)
    # handle and child seat
    m.cyl("Handle", 2.2, 0.16, (0, 2.45, 1.55), (210, 40, 40), axis="x")
    for s in (-1, 1):
        m.rod("HandleBar", (s * 1.0, 2.2, 1.3), (s * 1.0, 2.45, 1.55), 0.1, (170, 110, 70), mat=metal)
    m.blk("SeatFlap", (1.6, 0.08, 0.7), (0, 2.2, 0.9), (210, 40, 40), R=rot(x=20))
    # frame and wheels
    m.blk("Frame", (1.6, 0.12, 2.4), (0, 0.55, 0), (120, 80, 55), mat=metal)
    for sx in (-1, 1):
        m.rod("FrameLeg", (sx * 0.75, 0.55, -1.0), (sx * 0.9, 1.0, -1.2), 0.1, (120, 80, 55), mat=metal)
        m.rod("FrameLeg", (sx * 0.75, 0.55, 1.0), (sx * 0.9, 1.0, 1.2), 0.1, (120, 80, 55), mat=metal)
        for sz in (-1, 1):
            m.cyl("Wheel", 0.2, 0.5, (sx * 0.7, 0.25, sz * 1.0), (30, 30, 35), axis="x")
    # junk inside
    m.cyl("CanInside", 0.6, 0.4, (-0.45, 1.4, 0.4), (60, 160, 220), mat="Metal")
    m.blk("BoxInside", (0.7, 0.6, 0.6), (0.4, 1.35, 0.6), (220, 180, 90), mat="Cardboard", R=rot(y=20))
    m.ell("Sock", (0.3, 0.7, 0.3), (0.1, 1.55, -0.2), (240, 240, 240), mat="Fabric", R=rot(z=40))
    # the face is on the front of the basket
    m.eyes(1.9, -1.36, 0.8, 0.5, lid=None, look=(0.03, -0.04))
    m.smile(1.35, -1.36, 0.6, open_=True)
    return m


@model
def dumpster_diver():
    m = Model("dumpster_diver")
    green = (60, 120, 70)
    m.blk("Bin", (2.8, 1.6, 2.0), (0, 1.05, 0), green, mat="Metal", refl=0.1)
    m.blk("BinRim", (2.95, 0.15, 2.15), (0, 1.85, 0), (50, 100, 60), mat="Metal")
    for x in (-0.9, 0, 0.9):
        m.blk("Rib", (0.12, 1.5, 0.08), (x, 1.05, -1.02), (50, 100, 60), mat="Metal")
    m.blk("Lid", (2.9, 0.12, 2.0), (0, 2.6, 1.55), (45, 90, 55), mat="Metal", R=rot(x=-70))
    for s in (-1, 1):
        m.cyl("Wheel", 0.2, 0.45, (s * 1.05, 0.22, -0.7), (25, 25, 30), axis="x")
        m.cyl("Wheel", 0.2, 0.45, (s * 1.05, 0.22, 0.7), (25, 25, 30), axis="x")
    # raccoon diver popping out
    fur = (130, 130, 140)
    m.ell("Head", (1.4, 1.2, 1.2), (0, 2.45, -0.1), fur)
    for s in (-1, 1):
        m.ell("Ear", (0.4, 0.45, 0.2), (s * 0.5, 3.05, 0.0), fur, R=rot(z=s * -20))
    m.blk("Mask", (1.25, 0.55, 0.15), (0, 2.6, -0.68), (40, 160, 220), mat="Glass", tr=0.3, refl=0.3)
    m.blk("MaskFrame", (1.35, 0.65, 0.12), (0, 2.6, -0.62), (240, 200, 50))
    m.ell("Bandit", (1.2, 0.35, 0.3), (0, 2.6, -0.55), (40, 40, 45))
    m.eyes(2.62, -0.62, 0.48, 0.3, lid=None)
    m.ell("Snout", (0.5, 0.35, 0.4), (0, 2.2, -0.68), (220, 220, 225))
    m.ball("Nose", 0.18, (0, 2.27, -0.88), (30, 30, 30))
    # snorkel
    m.cyl("Snorkel", 1.2, 0.16, (0.72, 3.0, -0.35), (255, 130, 30))
    m.rod("SnorkelMouth", (0.72, 2.4, -0.35), (0.3, 2.15, -0.75), 0.16, (255, 130, 30))
    # paws holding treasures
    m.rod("Arm", (-0.6, 1.9, -0.6), (-1.05, 2.5, -1.0), 0.25, fur)
    m.ball("Paw", 0.3, (-1.07, 2.55, -1.02), (60, 60, 65))
    m.ell("FishBone", (0.12, 0.7, 0.12), (-1.1, 3.0, -1.05), (240, 240, 230))
    for k in range(3):
        m.blk("FishRib", (0.4 - k * 0.08, 0.05, 0.05), (-1.1, 2.85 + k * 0.15, -1.05), (240, 240, 230))
    m.rod("Arm", (0.6, 1.9, -0.6), (1.1, 2.1, -1.0), 0.25, fur)
    m.ell("Banana", (0.25, 0.7, 0.25), (1.2, 2.3, -1.05), (250, 220, 70), R=rot(z=-35))
    return m


@model
def glitter_gremlin():
    m = Model("glitter_gremlin")
    pink = (230, 80, 185)
    body = m.ell("Body", (1.7, 1.6, 1.5), (0, 1.15, 0), pink, mat="Foil", refl=0.2)
    m.sparkles(body, (255, 230, 120))
    m.ell("Belly", (1.0, 0.9, 0.5), (0, 0.95, -0.55), (255, 170, 225), mat="Foil")
    for s in (-1, 1):
        m.ell("Ear", (1.1, 0.5, 0.15), (s * 1.05, 1.9, 0.0), pink, mat="Foil", R=rot(z=s * 25, y=s * -15))
        m.ell("EarInner", (0.8, 0.3, 0.1), (s * 1.02, 1.9, -0.08), (120, 40, 110), R=rot(z=s * 25, y=s * -15))
    m.eyes(1.45, -0.62, 0.62, 0.48, lid=pink, pupil=(40, 20, 50), pupil_scale=0.4)
    for s in (-1, 1):
        m.ell("EyeGlow", (0.5, 0.52, 0.22), (s * 0.31, 1.45, -0.61), (255, 230, 60), tr=0.5)
    # toothy grin
    m.ell("Mouth", (0.8, 0.28, 0.2), (0, 0.98, -0.72), (70, 20, 60))
    for k in range(4):
        m.wedge("Tooth", (0.12, 0.16, 0.06), (-0.27 + k * 0.18, 1.05, -0.8), WHITE, R=rot(x=180))
    # spiky hair tufts
    for k, x in enumerate((-0.3, 0.0, 0.3)):
        m.rod("Tuft", (x, 1.85, 0.1), (x * 1.6, 2.45 - abs(x) * 0.4, 0.2), 0.16, (255, 220, 60), mat="Foil")
    # arms and a glue bottle
    m.rod("Arm", (-0.75, 1.15, -0.1), (-1.15, 0.8, -0.35), 0.22, pink, mat="Foil")
    m.rod("Arm", (0.75, 1.15, -0.1), (1.1, 1.4, -0.4), 0.22, pink, mat="Foil")
    m.cyl("Glue", 0.6, 0.35, (1.15, 1.6, -0.45), (245, 245, 250))
    m.cyl("GlueCap", 0.25, 0.18, (1.15, 2.0, -0.45), (255, 120, 30))
    for s in (-1, 1):
        m.ell("Foot", (0.5, 0.25, 0.7), (s * 0.42, 0.12, -0.15), (150, 50, 130))
    # glitter bits around
    for (x, y, z, c) in [(-0.9, 2.3, -0.3, (120, 220, 255)), (0.9, 2.5, 0.2, (255, 240, 120)), (-1.2, 1.5, 0.4, (255, 120, 220))]:
        m.blk("Glitter", (0.12, 0.12, 0.02), (x, y, z), c, mat="Neon", R=rot(30, 40, 20))
    return m


@model
def scrapheap_titan():
    m = Model("scrapheap_titan")
    rust = (175, 95, 45)
    m.cyl("Barrel", 2.1, 1.9, (0, 2.3, 0), rust, mat="CorrodedMetal")
    for y in (1.55, 2.3, 3.05):
        m.cyl("BarrelRing", 0.12, 1.98, (0, y, 0), (120, 70, 40), mat="CorrodedMetal")
    m.blk("Hazard", (0.8, 0.8, 0.05), (0, 2.3, -0.98), (240, 200, 40), R=rot(z=45))
    # tire shoulders and hips
    for s in (-1, 1):
        m.cyl("Tire", 0.55, 1.15, (s * 1.25, 3.2, 0), (35, 35, 40), axis="x")
        m.cyl("Hub", 0.58, 0.45, (s * 1.25, 3.2, 0), (160, 160, 170), axis="x", mat="Metal")
    # TV head
    m.blk("TV", (1.6, 1.2, 1.2), (0, 3.95, 0), (110, 85, 60), mat="Wood")
    m.blk("Screen", (1.2, 0.85, 0.08), (0, 3.95, -0.6), (30, 60, 40))
    for s in (-1, 1):
        m.blk("ScreenEye", (0.28, 0.32, 0.04), (s * 0.28, 4.02, -0.65), (90, 255, 140), mat="Neon")
    m.blk("ScreenMouth", (0.6, 0.08, 0.04), (0, 3.72, -0.65), (90, 255, 140), mat="Neon")
    for s in (-1, 1):
        m.rod("Antenna", (s * 0.2, 4.55, 0.2), (s * 0.7, 5.25, 0.3), 0.06, (180, 180, 190), mat="Metal")
    m.cyl("Knob", 0.1, 0.18, (0.65, 3.55, -0.62), (200, 200, 200), axis="z")
    # left arm: pipe with a wrench hand
    m.rod("ArmPipe", (-1.6, 3.15, 0), (-1.9, 2.0, -0.4), 0.4, (150, 150, 160), mat="Metal")
    m.rod("ArmPipe", (-1.9, 2.0, -0.4), (-1.75, 1.2, -0.9), 0.36, (150, 150, 160), mat="Metal")
    m.blk("Wrench", (0.25, 1.2, 0.12), (-1.72, 0.65, -1.05), (190, 190, 200), mat="Metal", R=rot(x=-20))
    m.blk("WrenchJaw", (0.6, 0.25, 0.14), (-1.72, 0.1, -1.25), (190, 190, 200), mat="Metal", R=rot(x=-20))
    # right arm: crane claw
    m.rod("ArmCrane", (1.6, 3.15, 0), (2.0, 2.3, -0.5), 0.45, (240, 190, 40), mat="Metal")
    m.rod("ArmCrane", (2.0, 2.3, -0.5), (2.0, 1.5, -0.9), 0.4, (240, 190, 40), mat="Metal")
    for s in (-1, 1):
        m.rod("Claw", (2.0, 1.4, -0.9), (2.0 + s * 0.35, 0.95, -1.05), 0.16, (110, 110, 120), mat="Metal")
        m.rod("Claw", (2.0 + s * 0.35, 0.95, -1.05), (2.0 + s * 0.15, 0.7, -1.15), 0.14, (110, 110, 120), mat="Metal")
    # legs: paint cans and boots
    for s in (-1, 1):
        m.cyl("LegCan", 1.0, 0.8, (s * 0.55, 0.9, 0), (90, 120, 200), mat="Metal")
        m.blk("Boot", (0.85, 0.45, 1.2), (s * 0.55, 0.23, -0.15), (60, 45, 35))
    m.blk("ScrapPlate", (0.7, 0.6, 0.08), (0.55, 1.75, -0.98), (130, 140, 150), mat="DiamondPlate", R=rot(z=-12))
    return m


@model
def the_junk_king():
    m = Model("the_junk_king")
    metal = (165, 170, 180)
    # trash can body
    m.cyl("Can", 3.0, 2.4, (0, 1.95, 0), metal, mat="Metal", refl=0.15)
    for k in range(8):
        a = k * 2 * math.pi / 8
        m.blk("CanRib", (0.12, 2.8, 0.12), (math.cos(a) * 1.2, 1.95, math.sin(a) * 1.2), (140, 145, 155), mat="Metal")
    m.cyl("CanBand", 0.2, 2.5, (0, 0.6, 0), (140, 145, 155), mat="Metal")
    # dark gap with glowing eyes under the lid
    m.cyl("Gap", 0.55, 2.3, (0, 3.6, 0), (20, 20, 25))
    for s in (-1, 1):
        m.ell("Eye", (0.42, 0.3, 0.2), (s * 0.4, 3.62, -1.1), (255, 230, 80), mat="Neon")
    m.ell("Mustache", (1.5, 0.35, 0.4), (0, 3.25, -1.2), (90, 70, 50), mat="Fabric")
    # lid crown
    m.cyl("Lid", 0.25, 2.6, (0, 4.0, 0), metal, mat="Metal", refl=0.2)
    m.cyl("LidHandle", 0.2, 0.9, (0, 4.2, 0), (150, 150, 160), mat="Metal")
    crown = m.cyl("Crown", 0.5, 1.5, (0, 4.55, 0), (245, 200, 60), mat="Metal", refl=0.25)
    for k in range(6):
        a = k * 2 * math.pi / 6
        m.ell("CrownPoint", (0.28, 0.6, 0.28), (math.cos(a) * 0.68, 4.95, math.sin(a) * 0.68), (245, 200, 60), mat="Metal")
        m.cyl("BottleCap", 0.08, 0.26, (math.cos(a) * 0.76, 4.55, math.sin(a) * 0.76), [(220, 40, 40), (40, 120, 220), (60, 180, 80)][k % 3],
              axis="z", R=rot(y=-math.degrees(a) - 90))
    m.sparkles(crown, (255, 220, 100))
    # cape (old red blanket)
    m.blk("Cape", (2.8, 3.4, 0.15), (0, 2.1, 1.35), (180, 30, 40), mat="Fabric", R=rot(x=-6))
    m.blk("CapeCollar", (2.9, 0.4, 0.5), (0, 3.4, 1.15), (240, 240, 240), mat="Fabric")
    # arms and plunger scepter
    m.rod("Arm", (-1.25, 2.9, 0), (-1.7, 2.2, -0.6), 0.45, metal, mat="Metal")
    m.ball("Glove", 0.55, (-1.72, 2.15, -0.65), (240, 240, 240))
    m.rod("Arm", (1.25, 2.9, 0), (1.75, 2.3, -0.6), 0.45, metal, mat="Metal")
    m.ball("Glove", 0.55, (1.77, 2.25, -0.65), (240, 240, 240))
    m.cyl("PlungerStick", 3.2, 0.2, (1.8, 2.6, -0.7), (150, 100, 60), mat="Wood")
    m.ell("PlungerCup", (0.9, 0.6, 0.9), (1.8, 4.3, -0.7), (200, 40, 50), mat="Rubber")
    # banana peel on the shoulder for style
    m.ell("Peel", (0.5, 0.2, 0.4), (-0.8, 3.95, -0.6), (250, 220, 70), R=rot(z=20))
    for s in (-1, 1):
        m.ell("Foot", (0.9, 0.4, 1.2), (s * 0.7, 0.2, -0.4), (60, 60, 70), mat="Rubber")
    return m
