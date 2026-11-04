# Junk family models (rusty metal, old furniture, tape, patches and glitter)
import math
from modelkit import Model, rot, Rx, Ry, Rz, WHITE, PUPIL, shade

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


def tape(m, pos, size, R=None, color=(200, 190, 160)):
    """A strip of old tape stuck on a surface."""
    m.blk("Tape", size, pos, color, mat="Fabric", R=R)


@model
def tin_can_tom():
    m = Model("tin_can_tom")
    tin = (185, 190, 200)
    twig = (120, 90, 60)
    m.cyl("Body", 1.5, 1.2, (0, 1.15, 0), tin, mat="Metal", refl=0.3, R=rot(z=4))
    # ribbed sides above and below the label
    for y in (0.6, 0.72, 1.56, 1.68):
        m.ring("Groove", (0.04 * (y - 1.15), y, 0), 0.61, 0.04, (150, 155, 165), normal="y", segments=14, mat="Metal", R=rot(z=4))
    m.cyl("Label", 0.68, 1.24, (0.03, 1.12, 0), (200, 60, 50), R=rot(z=4))
    m.cyl("LabelStripe", 0.12, 1.26, (0.03, 0.88, 0), (250, 220, 90), R=rot(z=4))
    # tomato on the label
    m.ball("LabelTomato", 0.3, (0.38, 1.25, -0.5), (240, 90, 60))
    m.ell("LabelLeaf", (0.18, 0.06, 0.04), (0.38, 1.4, -0.6), (70, 170, 70))
    for y in (0.4, 1.9):
        m.ring("Rim", (0.04 * (y - 1.15), y, 0), 0.62, 0.09, (160, 165, 175), normal="y", segments=14, mat="Metal", R=rot(z=4))
    # lid peeled open like a hat, with a jagged edge and a pull ring
    m.cyl("CanLid", 0.06, 1.15, (-0.1, 2.12, 0.25), (200, 205, 215), mat="Metal", refl=0.35, R=rot(x=35, z=4))
    for k in range(5):
        a = math.radians(-60 + k * 30)
        m.wedge("Jag", (0.1, 0.12, 0.06), (-0.1 + math.sin(a) * 0.55, 2.0 + math.cos(a) * 0.05, -0.15 + math.cos(a) * 0.12), (175, 180, 190), mat="Metal", R=rot(x=35, y=-math.degrees(a)))
    m.ring("PullTab", (-0.1, 2.32, -0.02), 0.1, 0.035, (170, 175, 185), normal="y", segments=8, mat="Metal", R=rot(x=35))
    # dents, rust and a tape patch
    m.ell("Dent", (0.4, 0.3, 0.2), (0.45, 1.6, -0.5), (150, 155, 165), mat="Metal")
    m.ell("Rust", (0.3, 0.2, 0.06), (-0.4, 0.55, -0.48), (150, 85, 45), mat="CorrodedMetal", R=rot(y=-35))
    tape(m, (-0.46, 1.62, -0.42), (0.36, 0.1, 0.03), R=rot(y=-40, z=25))
    tape(m, (-0.46, 1.62, -0.42), (0.36, 0.1, 0.03), R=rot(y=-40, z=-25))
    # mismatched eyes and a gap-tooth grin
    m.eyes(1.28, -0.6, 0.46, 0.36, lid=(200, 60, 50), iris=(90, 150, 220), z_back=0.04)
    m.ell("EyeRim", (0.5, 0.55, 0.2), (-0.23, 1.28, -0.57), (40, 35, 40))
    m.grin(0.92, -0.62, 0.36, open_=True, teeth=2, bend=0.06)
    m.brow(-0.23, 1.55, -0.62, 0.26, (60, 50, 50), -1, tilt=-12)
    m.brow(0.23, 1.52, -0.62, 0.26, (60, 50, 50), 1, tilt=10)
    # twig limbs with twig fingers and bottle-cap shoes
    for s in (-1, 1):
        hand = (s * 1.0, 0.9 + (0.5 if s > 0 else 0), -0.1)
        m.rod("Arm", (s * 0.6, 1.25, 0), hand, 0.11, twig)
        m.ball("Knuckle", 0.13, (s * 0.8, 1.08 + (0.25 if s > 0 else 0), -0.05), shade(twig, 0.85))
        m.ball("Hand", 0.18, hand, twig)
        for k in (-1, 0, 1):
            tip = (hand[0] + s * 0.16, hand[1] + k * 0.12 + 0.05, hand[2] - 0.05)
            m.rod("Finger", hand, tip, 0.05, twig)
        m.rod("Leg", (s * 0.28, 0.45, 0), (s * 0.35, 0.1, -0.05), 0.12, twig)
        m.cyl("Foot", 0.14, 0.46, (s * 0.36, 0.07, -0.1), (210, 50, 50), mat="Metal")
        for k in range(8):
            a = k * math.pi / 4
            m.blk("Toe", (0.06, 0.12, 0.05), (s * 0.36 + math.cos(a) * 0.23, 0.07, -0.1 + math.sin(a) * 0.23), (190, 40, 40), mat="Metal", R=rot(y=-math.degrees(a)))
    return m


@model
def couch_golem():
    m = Model("couch_golem")
    fab = (80, 140, 130)
    dark = (60, 110, 100)
    pipe = (215, 190, 120)
    wood = (110, 75, 45)
    # base with a fringe skirt and piping
    m.rbox("Base", (3.2, 0.9, 1.7), (0, 0.85, 0), dark, 0.15, mat="Fabric")
    m.cyl("Piping", 3.2, 0.08, (0, 1.29, -0.85), pipe, axis="x", mat="Fabric")
    for k in range(15):
        m.blk("Fringe", (0.16, 0.22, 0.04), (-1.4 + k * 0.2, 0.42, -0.86), pipe, mat="Fabric")
    # seat cushions with rounded corners and a crease
    for s in (-1, 1):
        m.rbox("Cushion", (1.45, 0.45, 1.5), (s * 0.75, 1.5, -0.08), fab, 0.18, mat="Fabric")
        m.cyl("Piping", 1.1, 0.06, (s * 0.75, 1.73, -0.83), pipe, axis="x", mat="Fabric")
    # backrest is the face, tufted with buttons
    m.rbox("Back", (3.2, 1.9, 0.6), (0, 2.1, 0.62), dark, 0.2, mat="Fabric", axis="z")
    m.rbox("BackPad", (2.8, 1.4, 0.3), (0, 2.25, 0.25), fab, 0.25, mat="Fabric", axis="z")
    for x in (-1.0, -0.33, 0.33, 1.0):
        m.cyl("Button", 0.05, 0.14, (x, 2.8, 0.09), (40, 70, 65), axis="z")
    for x in (-0.66, 0.66):
        m.cyl("Button", 0.05, 0.14, (x, 1.75, 0.09), (40, 70, 65), axis="z")
    # a patch, a tear with stuffing poking out
    m.blk("Patch", (0.5, 0.45, 0.04), (1.0, 2.15, 0.09), (200, 120, 80), mat="Fabric", R=rot(z=12))
    m.stitches("Stitch", (0.75, 1.95, 0.07), (1.2, 2.45, 0.07), 4, 0.04, (250, 240, 220))
    for (x, y, d) in [(-1.05, 2.0, 0.22), (-0.95, 2.1, 0.18), (-1.12, 2.12, 0.15)]:
        m.ball("Stuffing", d, (x, y, 0.08), (250, 248, 240), mat="Fabric")
    # sleepy, grumpy face
    m.eyes(2.32, 0.08, 0.95, 0.5, lid=fab, iris=(200, 160, 60), sleepy=True, bulge=0.5)
    m.brow(-0.48, 2.72, 0.06, 0.55, (40, 70, 65), -1, tilt=-6, d=0.13)
    m.brow(0.48, 2.72, 0.06, 0.55, (40, 70, 65), 1, tilt=-6, d=0.13)
    m.grin(1.82, 0.08, 0.9, curve=-0.1, color=(40, 60, 55), d=0.11)
    # armrests as arms with fists
    for s in (-1, 1):
        m.rbox("Armrest", (0.5, 1.0, 1.9), (s * 1.65, 1.35, -0.05), dark, 0.12, mat="Fabric")
        m.ell("ArmRoll", (0.62, 0.62, 1.95), (s * 1.65, 1.85, -0.05), fab, mat="Fabric")
        m.cyl("Piping", 0.07, 0.62, (s * 1.65, 1.85, -1.02), pipe, axis="z", mat="Fabric")
        m.ball("Fist", 0.72, (s * 1.7, 1.55, -1.15), fab, mat="Fabric")
        for k in range(3):
            m.ball("Knuckle", 0.2, (s * 1.7 + (k - 1) * 0.17, 1.78, -1.38), dark, mat="Fabric")
    # turned wooden legs with ball feet
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cyl("Leg", 0.4, 0.26, (sx * 1.35, 0.24, sz * 0.6), wood)
            m.ball("Foot", 0.3, (sx * 1.35, 0.1, sz * 0.6), shade(wood, 0.8))
    # a spring poking out, a lost coin, a remote and popcorn
    m.chain("Spring", [(0.7, 1.72, -0.45), (0.85, 1.92, -0.5), (0.65, 2.0, -0.55), (0.82, 2.15, -0.6), (0.68, 2.25, -0.62)], 0.07, (170, 170, 180), mat="Metal", joints=False)
    m.cyl("Coin", 0.05, 0.3, (-0.6, 1.74, -0.6), (240, 200, 60), mat="Metal")
    m.rbox("Remote", (0.2, 0.08, 0.6), (-0.05, 1.68, -0.4), (40, 40, 45), 0.06, R=rot(y=25))
    m.ball("RemoteButton", 0.07, (-0.08, 1.73, -0.55), (220, 50, 50))
    for (x, z) in [(-0.9, -0.5), (-1.1, -0.3), (0.3, -0.75)]:
        m.ball("Popcorn", 0.13, (x, 1.76, z), (255, 245, 200))
    # the back of the couch: a lighter panel with tufting, piping, a price tag and lost things
    m.rbox("BackPanel", (2.9, 1.6, 0.06), (0, 2.1, 0.93), fab, 0.15, mat="Fabric", axis="z")
    m.cyl("Piping", 3.2, 0.08, (0, 3.03, 0.9), pipe, axis="x", mat="Fabric")
    for x in (-0.97, 0.0, 0.97):
        m.blk("Seam", (0.04, 1.5, 0.03), (x, 2.1, 0.965), dark, mat="Fabric")
    for (x, y) in [(-0.48, 2.5), (0.48, 2.5), (-0.48, 1.7), (0.48, 1.7)]:
        m.cyl("Button", 0.05, 0.14, (x, y, 0.97), (40, 70, 65), axis="z")
    m.chain("TagString", [(1.2, 3.05, 0.95), (1.25, 2.85, 1.0), (1.28, 2.6, 0.99)], 0.025, (240, 235, 220), joints=False)
    m.rbox("PriceTag", (0.42, 0.3, 0.03), (1.28, 2.45, 1.0), (250, 220, 90), 0.06, axis="z", R=rot(z=-10))
    m.blk("PriceText", (0.26, 0.05, 0.02), (1.29, 2.48, 1.02), (200, 40, 40), R=rot(z=-10))
    m.blk("PriceText", (0.18, 0.04, 0.02), (1.27, 2.39, 1.02), (60, 50, 40), R=rot(z=-10))
    m.rbox("LostSock", (0.22, 0.5, 0.1), (-1.15, 1.52, 0.98), (250, 250, 250), 0.08, axis="z", mat="Fabric", R=rot(z=25))
    m.blk("LostSockStripe", (0.23, 0.06, 0.11), (-1.17, 1.62, 0.98), (220, 60, 60), mat="Fabric", R=rot(z=25))
    m.blk("Patch", (0.45, 0.4, 0.04), (-0.4, 2.55, 0.96), (230, 180, 80), mat="Fabric", R=rot(z=-8))
    m.stitches("Stitch", (-0.6, 2.38, 0.985), (-0.2, 2.72, 0.985), 4, 0.035, (250, 240, 220))
    return m


@model
def rusty_shopping_cart():
    m = Model("rusty_shopping_cart")
    rust = (150, 95, 60)
    wire = (175, 115, 72)
    metal = "CorrodedMetal"
    # basket panels (see-through wire look) with real wires
    m.blk("Floor", (2.0, 0.1, 2.6), (0, 1.0, 0), rust, mat=metal)
    for s in (-1, 1):
        m.blk("Side", (0.06, 1.2, 2.6), (s * 1.0, 1.6, 0), rust, mat=metal, tr=0.55)
        for k in range(5):
            m.blk("Wire", (0.05, 1.2, 0.05), (s * 1.02, 1.6, -1.04 + k * 0.52), wire, mat=metal)
        m.cyl("Wire", 2.6, 0.05, (s * 1.02, 1.6, 0), wire, axis="z", mat=metal)
    m.blk("Front", (2.0, 1.2, 0.06), (0, 1.6, -1.3), rust, mat=metal, tr=0.35)
    m.blk("BackGate", (2.0, 1.2, 0.06), (0, 1.6, 1.3), rust, mat=metal, tr=0.55)
    for (x, z, L, axis) in [(-1.0, 0, 2.7, "z"), (1.0, 0, 2.7, "z"), (0, -1.3, 2.1, "x"), (0, 1.3, 2.1, "x")]:
        m.cyl("Rim", L, 0.11, (x, 2.2, z), (170, 110, 70), axis=axis, mat=metal)
    for x in (-0.75, 0.75):
        m.blk("Wire", (0.05, 1.2, 0.05), (x, 1.6, -1.34), wire, mat=metal)
    m.cyl("Wire", 2.0, 0.05, (0, 1.05, -1.34), wire, axis="x", mat=metal)
    # rust patches
    for (x, y, z, ax) in [(-0.6, 2.2, -1.32, "x"), (1.0, 1.9, 0.6, "z"), (0.3, 2.2, 1.3, "x")]:
        m.ell("Rust", (0.35, 0.18, 0.18), (x, y, z), (110, 60, 35), mat=metal)
    # handle with a red grip and a child seat with leg holes
    m.cyl("Handle", 2.2, 0.18, (0, 2.45, 1.55), (210, 40, 40), axis="x")
    for x in (-0.95, 0.95):
        m.cyl("HandleCap", 0.12, 0.22, (x * 1.18, 2.45, 1.55), (60, 60, 65), axis="x")
    for s in (-1, 1):
        m.rod("HandleBar", (s * 1.0, 2.2, 1.3), (s * 1.0, 2.45, 1.55), 0.1, (170, 110, 70), mat=metal)
    m.blk("SeatFlap", (1.6, 0.08, 0.7), (0, 2.2, 0.9), (210, 40, 40), R=rot(x=20))
    for s in (-1, 1):
        m.ell("SeatHole", (0.3, 0.1, 0.2), (s * 0.4, 2.22, 0.95), (40, 30, 30), R=rot(x=20))
    # frame and caster wheels
    m.blk("Frame", (1.6, 0.12, 2.4), (0, 0.55, 0), (120, 80, 55), mat=metal)
    for sx in (-1, 1):
        m.rod("FrameLeg", (sx * 0.75, 0.55, -1.0), (sx * 0.9, 1.0, -1.2), 0.1, (120, 80, 55), mat=metal)
        m.rod("FrameLeg", (sx * 0.75, 0.55, 1.0), (sx * 0.9, 1.0, 1.2), 0.1, (120, 80, 55), mat=metal)
        for sz in (-1, 1):
            m.blk("Fork", (0.32, 0.3, 0.08), (sx * 0.7, 0.42, sz * 1.0), (90, 90, 95), mat="Metal")
            m.cyl("Wheel", 0.2, 0.5, (sx * 0.7, 0.25, sz * 1.0), (30, 30, 35), axis="x", mat="Rubber")
            m.cyl("WheelHub", 0.22, 0.2, (sx * 0.7, 0.25, sz * 1.0), (190, 190, 195), axis="x", mat="Metal")
    # junk inside: a can, a box, a sock, a rubber duck and a traffic cone
    m.cyl("CanInside", 0.6, 0.4, (-0.45, 1.4, 0.4), (60, 160, 220), mat="Metal")
    m.cyl("CanInside", 0.14, 0.42, (-0.45, 1.62, 0.4), (240, 240, 245), mat="Metal")
    m.blk("BoxInside", (0.7, 0.6, 0.6), (0.4, 1.35, 0.6), (220, 180, 90), mat="Cardboard", R=rot(y=20))
    tape(m, (0.4, 1.66, 0.6), (0.72, 0.03, 0.12), R=rot(y=20))
    m.ell("Sock", (0.3, 0.7, 0.3), (0.1, 1.55, -0.2), (240, 240, 240), mat="Fabric", R=rot(z=40))
    m.cyl("SockStripe", 0.08, 0.31, (0.3, 1.75, -0.2), (220, 60, 60), R=rot(z=40))
    m.ell("Duck", (0.4, 0.34, 0.5), (-0.5, 2.3, -0.6), (255, 220, 40))
    m.ball("Duck", 0.3, (-0.5, 2.55, -0.78), (255, 220, 40))
    m.ell("DuckBeak", (0.14, 0.06, 0.12), (-0.5, 2.52, -0.95), (255, 140, 30))
    m.cyl("Cone", 0.9, 0.5, (0.55, 1.5, -0.65), (255, 120, 30), R=rot(z=-25))
    m.cyl("ConeStripe", 0.16, 0.42, (0.62, 1.65, -0.65), (250, 250, 250), R=rot(z=-25))
    m.ball("ConeTip", 0.22, (0.72, 1.92, -0.65), (255, 120, 30))
    # the face is on the front of the basket
    m.eyes(1.9, -1.36, 0.8, 0.5, lid=None, look=(0.03, -0.04), iris=(200, 120, 60))
    m.blk("Bandage", (0.5, 0.14, 0.04), (0.42, 2.18, -1.42), (240, 190, 160), R=rot(z=-30))
    m.grin(1.38, -1.36, 0.66, open_=True, teeth=3, curve=0.18)
    return m


@model
def dumpster_diver():
    m = Model("dumpster_diver")
    green = (60, 120, 70)
    dgreen = (45, 92, 55)
    m.rbox("Bin", (2.8, 1.6, 2.0), (0, 1.05, 0), green, 0.12, mat="Metal", refl=0.1)
    m.blk("BinRim", (2.95, 0.15, 2.15), (0, 1.85, 0), (50, 100, 60), mat="Metal")
    for x in (-0.9, 0, 0.9):
        m.blk("Rib", (0.12, 1.5, 0.08), (x, 1.05, -1.02), dgreen, mat="Metal")
    m.blk("Stencil", (0.7, 0.18, 0.03), (-0.45, 1.5, -1.02), (240, 240, 230))
    m.blk("Stencil", (0.5, 0.18, 0.03), (0.45, 1.5, -1.02), (240, 240, 230))
    m.ell("Dent", (0.5, 0.4, 0.12), (0.5, 0.8, -1.0), dgreen, mat="Metal")
    for s in (-1, 1):
        m.cyl("SideHandle", 0.9, 0.1, (s * 1.45, 1.4, 0), (150, 150, 155), axis="z", mat="Metal")
    # lid propped open on hinges
    m.blk("BinLid", (2.9, 0.12, 2.0), (0, 2.6, 1.55), (45, 90, 55), mat="Metal", R=rot(x=-70))
    for x in (-0.9, 0.9):
        m.cyl("Hinge", 0.3, 0.14, (x, 1.88, 1.08), (120, 120, 125), axis="x", mat="Metal")
    for s in (-1, 1):
        for z in (-0.7, 0.7):
            m.cyl("Wheel", 0.2, 0.45, (s * 1.05, 0.22, z), (25, 25, 30), axis="x", mat="Rubber")
            m.cyl("WheelHub", 0.22, 0.18, (s * 1.05, 0.22, z), (170, 170, 175), axis="x", mat="Metal")
    # trash bags and garbage spilling over the rim
    for (x, z, d) in [(-1.0, 0.2, 0.75), (0.95, 0.35, 0.7), (-0.6, 0.65, 0.6)]:
        m.ell("TrashBag", (d, d * 0.8, d), (x, 2.0, z), (30, 30, 35), refl=0.25)
        m.ell("BagTie", (0.12, 0.14, 0.12), (x, 2.0 + d * 0.42, z), (240, 200, 50))
    m.ell("Peel", (0.4, 0.12, 0.25), (1.1, 1.95, -0.85), (250, 220, 70), R=rot(z=-20))
    # raccoon diver popping out
    fur = (130, 130, 140)
    m.ell("Head", (1.4, 1.2, 1.2), (0, 2.45, -0.1), fur)
    m.ell("Cheek", (0.5, 0.4, 0.4), (-0.5, 2.25, -0.5), (200, 200, 205))
    m.ell("Cheek", (0.5, 0.4, 0.4), (0.5, 2.25, -0.5), (200, 200, 205))
    for s in (-1, 1):
        m.ell("Ear", (0.42, 0.47, 0.2), (s * 0.5, 3.05, 0.0), fur, R=rot(z=s * -20))
        m.ell("EarInner", (0.24, 0.3, 0.1), (s * 0.5, 3.03, -0.09), (60, 60, 65), R=rot(z=s * -20))
        m.ell("Tuft", (0.14, 0.2, 0.1), (s * 0.12, 3.06, -0.2), (90, 90, 100), R=rot(z=s * -25))
    m.rbox("Mask", (1.25, 0.55, 0.15), (0, 2.6, -0.68), (40, 160, 220), 0.12, mat="Glass", tr=0.3, refl=0.35, axis="z")
    m.rbox("MaskFrame", (1.38, 0.68, 0.12), (0, 2.6, -0.62), (240, 200, 50), 0.16, axis="z")
    m.ring("MaskFrame", (0, 2.62, -0.1), 0.66, 0.08, (30, 30, 30), normal="y", segments=12)
    m.ell("Bandit", (1.2, 0.35, 0.3), (0, 2.6, -0.55), (40, 40, 45))
    m.eyes(2.62, -0.62, 0.48, 0.3, lid=None, iris=(140, 90, 40))
    m.ell("Snout", (0.5, 0.35, 0.4), (0, 2.2, -0.68), (220, 220, 225))
    m.ball("Nose", 0.18, (0, 2.27, -0.88), (30, 30, 30))
    m.ball("NoseShine", 0.06, (0.04, 2.31, -0.96), (200, 200, 210))
    m.grin(2.06, -0.86, 0.24, color=(60, 40, 45), curve=0.3)
    for s in (-1, 1):
        for k in (-1, 1):
            m.blk("Whisker", (0.5, 0.025, 0.025), (s * 0.45, 2.18 + k * 0.05, -0.78), (60, 60, 60), R=rot(z=s * k * 10, y=s * 15))
    # striped snorkel
    m.cyl("Snorkel", 1.2, 0.17, (0.72, 3.0, -0.35), (255, 130, 30))
    for k in range(3):
        m.cyl("Snorkel", 0.08, 0.19, (0.72, 2.75 + k * 0.25, -0.35), (250, 250, 250))
    m.rod("SnorkelMouth", (0.72, 2.4, -0.35), (0.3, 2.15, -0.75), 0.16, (255, 130, 30))
    # ringed tail hanging over the back
    pts = [(0.6, 1.9, 0.9), (0.9, 1.6, 1.15), (1.0, 1.2, 1.2), (0.95, 0.85, 1.15)]
    for i in range(len(pts) - 1):
        m.rod("Tail", pts[i], pts[i + 1], 0.32, (60, 60, 65) if i % 2 else fur, shape="E")
    m.ball("TailTip", 0.3, pts[-1], (60, 60, 65))
    # paws holding treasures: a fish skeleton and a banana
    m.rod("Arm", (-0.6, 1.9, -0.6), (-1.05, 2.5, -1.0), 0.26, fur)
    m.ball("Paw", 0.32, (-1.07, 2.55, -1.02), (60, 60, 65))
    for k in (-1, 0, 1):
        m.ball("Claw", 0.1, (-1.07 + k * 0.1, 2.7, -1.12), (230, 230, 220))
    m.ell("FishBone", (0.12, 0.75, 0.12), (-1.1, 3.0, -1.05), (240, 240, 230))
    for k in range(4):
        m.blk("FishRib", (0.42 - k * 0.07, 0.05, 0.05), (-1.1, 2.78 + k * 0.14, -1.05), (240, 240, 230))
    m.ell("FishHead", (0.3, 0.32, 0.14), (-1.1, 3.42, -1.05), (240, 240, 230))
    m.wedge("FishTail", (0.08, 0.25, 0.3), (-1.1, 2.6, -1.05), (240, 240, 230), R=rot(y=90))
    m.rod("Arm", (0.6, 1.9, -0.6), (1.1, 2.1, -1.0), 0.26, fur)
    m.ball("Paw", 0.32, (1.12, 2.12, -1.02), (60, 60, 65))
    m.ell("Banana", (0.25, 0.7, 0.25), (1.2, 2.3, -1.05), (250, 220, 70), R=rot(z=-35))
    m.ell("BananaTip", (0.1, 0.12, 0.1), (1.42, 2.6, -1.05), (90, 70, 40), R=rot(z=-35))
    for k in range(3):
        m.ball("BananaSpot", 0.07, (1.12 + k * 0.08, 2.2 + k * 0.12, -1.18), (170, 140, 60))
    # the outside of the open lid: ribs, warning stripes, a sticker and a doodle; ribs on the bin's back
    c, sn = math.cos(math.radians(-70)), math.sin(math.radians(-70))
    def on_lid(lx, ly, lz):
        return (lx, 2.6 + c * ly - sn * lz, 1.55 + sn * ly + c * lz)
    for lx in (-0.95, 0.0, 0.95):
        m.blk("LidRib", (0.12, 0.06, 1.85), on_lid(lx, -0.09, 0), dgreen, mat="Metal", R=rot(x=-70))
    for k in range(6):
        m.blk("HazardStripe", (0.24, 0.03, 0.22), on_lid(-1.25 + k * 0.5, -0.075, -0.82), (240, 200, 40) if k % 2 == 0 else (30, 30, 30), R=rot(x=-70))
    m.rbox("Sticker", (0.6, 0.4, 0.03), on_lid(0.48, -0.08, 0.35), (240, 240, 230), 0.06, axis="z", R=rot(x=-70) @ rot(x=-90))
    m.blk("StickerText", (0.4, 0.06, 0.02), on_lid(0.48, -0.1, 0.42), (200, 40, 40), R=rot(x=-70))
    m.blk("StickerText", (0.3, 0.05, 0.02), on_lid(0.48, -0.1, 0.28), (60, 60, 60), R=rot(x=-70))
    m.ring("Doodle", on_lid(-0.5, -0.08, 0.3), 0.2, 0.04, (240, 120, 200), normal="y", segments=8, R=rot(x=-70))
    m.ball("DoodleEye", 0.06, on_lid(-0.57, -0.09, 0.36), (240, 120, 200))
    m.ball("DoodleEye", 0.06, on_lid(-0.43, -0.09, 0.36), (240, 120, 200))
    for x in (-0.9, 0, 0.9):
        m.blk("Rib", (0.12, 1.5, 0.08), (x, 1.05, 1.02), dgreen, mat="Metal")
    m.ell("Dent", (0.45, 0.35, 0.12), (-0.5, 0.7, 1.0), dgreen, mat="Metal")
    m.blk("Stencil", (0.9, 0.16, 0.03), (0.0, 0.55, 1.02), (240, 240, 230))
    return m


@model
def glitter_gremlin():
    m = Model("glitter_gremlin")
    pink = (230, 80, 185)
    deep = (150, 50, 130)
    body = m.ell("Body", (1.7, 1.6, 1.5), (0, 1.15, 0), pink, mat="Foil", refl=0.25)
    m.sparkles(body, (255, 230, 120))
    m.ell("Belly", (1.0, 0.9, 0.5), (0, 0.95, -0.55), (255, 170, 225), mat="Foil")
    # fluffy foil fur tufts and glitter specks all over
    m.scatter("Fur", (0, 1.15, 0), (1.7, 1.6, 1.5), 10, [shade(pink, 0.85), shade(pink, 1.15)], seed=8, d=0.22, shape="dot", ymin=-0.2, mat="Foil")
    m.scatter("Glitter", (0, 1.15, 0), (1.72, 1.62, 1.52), 14, [(255, 240, 120), (120, 220, 255), (255, 255, 255), (180, 255, 160)], seed=12, d=0.07, shape="cube", mat="Neon")
    for s in (-1, 1):
        m.ell("Ear", (1.15, 0.52, 0.15), (s * 1.05, 1.9, 0.0), pink, mat="Foil", R=rot(z=s * 25, y=s * -15))
        m.ell("EarInner", (0.82, 0.3, 0.1), (s * 1.02, 1.9, -0.08), (120, 40, 110), R=rot(z=s * 25, y=s * -15))
        m.ball("EarTip", 0.14, (s * 1.6, 2.15, 0.1), (255, 230, 80), mat="Neon")
    # big glowing eyes
    m.eyes(1.45, -0.62, 0.62, 0.48, lid=pink, pupil=(40, 20, 50), pupil_scale=0.45, iris=(255, 210, 40), z_back=0.03)
    for s in (-1, 1):
        m.ell("EyeGlow", (0.56, 0.58, 0.22), (s * 0.31, 1.45, -0.6), (255, 230, 60), tr=0.6)
    m.brow(-0.32, 1.82, -0.58, 0.36, deep, -1, tilt=18, d=0.1)
    m.brow(0.32, 1.82, -0.58, 0.36, deep, 1, tilt=18, d=0.1)
    # toothy grin, wide and wicked
    m.grin(1.02, -0.72, 0.84, color=(70, 20, 60), curve=0.25, open_=True, teeth=0, bend=0.1)
    for k in range(5):
        x = -0.32 + k * 0.16
        m.wedge("Tooth", (0.11, 0.16, 0.06), (x, 1.04 + 0.12 * (x / 0.42) ** 2, -0.8 + 0.08 * (x / 0.42) ** 2), WHITE, R=rot(x=180))
    # spiky hair tufts and little horns
    for k, x in enumerate((-0.35, -0.12, 0.12, 0.35)):
        m.rod("Tuft", (x, 1.85, 0.1), (x * 1.6, 2.5 - abs(x) * 0.5, 0.2 + 0.1 * (k % 2)), 0.15, (255, 220, 60), mat="Foil")
    for s in (-1, 1):
        m.ell("Horn", (0.14, 0.32, 0.14), (s * 0.45, 1.98, -0.25), (255, 240, 200), R=rot(z=-s * 25))
    # arms with claws and a glue bottle with a label and a dripping nozzle
    m.rod("Arm", (-0.75, 1.15, -0.1), (-1.15, 0.8, -0.35), 0.22, pink, mat="Foil")
    m.ball("Hand", 0.28, (-1.17, 0.78, -0.37), pink, mat="Foil")
    for k in (-1, 0, 1):
        m.ell("Claw", (0.07, 0.16, 0.07), (-1.2 + k * 0.08, 0.62, -0.45), (255, 240, 220), R=rot(z=k * 15))
    m.rod("Arm", (0.75, 1.15, -0.1), (1.1, 1.4, -0.4), 0.22, pink, mat="Foil")
    m.ball("Hand", 0.28, (1.12, 1.42, -0.42), pink, mat="Foil")
    m.cyl("Glue", 0.6, 0.35, (1.15, 1.65, -0.45), (245, 245, 250))
    m.cyl("GlueLabel", 0.3, 0.37, (1.15, 1.65, -0.45), (255, 120, 30))
    m.cyl("GlueCap", 0.22, 0.2, (1.15, 2.05, -0.45), (255, 120, 30))
    m.ell("GlueCap", (0.08, 0.2, 0.08), (1.15, 2.22, -0.45), (255, 120, 30))
    m.drip("Glue", (1.2, 2.0, -0.55), 0.28, 0.08, (250, 250, 255), refl=0.3)
    # stubby clawed feet and a pom-pom tail
    for s in (-1, 1):
        m.ell("Foot", (0.52, 0.26, 0.72), (s * 0.42, 0.13, -0.15), deep)
        for k in (-1, 0, 1):
            m.ball("Toe", 0.14, (s * 0.42 + k * 0.14, 0.12, -0.5), (255, 240, 220))
    m.chain("Tail", [(0, 0.7, 0.7), (0.2, 0.55, 1.0), (0.35, 0.75, 1.2)], 0.1, pink)
    m.ball("TailTip", 0.3, (0.38, 0.85, 1.25), (255, 230, 80), mat="Foil")
    # glitter bits floating around
    for (x, y, z, c) in [(-0.9, 2.3, -0.3, (120, 220, 255)), (0.9, 2.5, 0.2, (255, 240, 120)), (-1.2, 1.5, 0.4, (255, 120, 220)), (0.4, 2.7, -0.4, (255, 255, 255)), (-0.4, 2.6, 0.3, (180, 255, 160))]:
        m.blk("Glitter", (0.12, 0.12, 0.02), (x, y, z), c, mat="Neon", R=rot(30, 40, 20))
    return m


@model
def scrapheap_titan():
    m = Model("scrapheap_titan")
    rust = (175, 95, 45)
    m.cyl("Barrel", 2.1, 1.9, (0, 2.3, 0), rust, mat="CorrodedMetal")
    for y in (1.55, 2.3, 3.05):
        m.ring("BarrelRing", (0, y, 0), 0.97, 0.1, (120, 70, 40), normal="y", segments=16, mat="CorrodedMetal")
    # hazard sign, bolted scrap plates and rivets
    m.blk("Hazard", (0.8, 0.8, 0.05), (0, 2.3, -0.98), (240, 200, 40), R=rot(z=45))
    m.blk("HazardMark", (0.12, 0.35, 0.03), (0, 2.36, -1.01), (30, 30, 30))
    m.blk("HazardMark", (0.12, 0.12, 0.03), (0, 2.08, -1.01), (30, 30, 30))
    m.blk("ScrapPlate", (0.7, 0.6, 0.08), (0.55, 1.75, -0.98), (130, 140, 150), mat="DiamondPlate", R=rot(z=-12))
    m.blk("ScrapPlate", (0.55, 0.5, 0.08), (-0.6, 2.75, -0.88), (150, 120, 90), mat="CorrodedMetal", R=rot(y=-30, z=8))
    for (x, y, z) in [(0.3, 2.0, -1.03), (0.8, 1.95, -1.0), (0.3, 1.52, -1.03), (0.8, 1.48, -1.0), (-0.78, 2.92, -0.82), (-0.42, 2.6, -0.98)]:
        m.ball("Rivet", 0.09, (x, y, z), (200, 200, 205), mat="Metal")
    # exhaust pipe on the back, puffing smoke
    m.cyl("Exhaust", 1.4, 0.3, (0.5, 3.4, 0.95), (90, 90, 95), mat="Metal")
    pipe_top = m.cyl("ExhaustTop", 0.2, 0.38, (0.5, 4.1, 0.95), (60, 60, 65), mat="Metal")
    m.smoke(pipe_top, (110, 110, 115), 0.1, 1.0, 0.8)
    # tire shoulders
    for s in (-1, 1):
        m.cyl("Tire", 0.55, 1.15, (s * 1.25, 3.2, 0), (35, 35, 40), axis="x", mat="Rubber")
        m.cyl("Hub", 0.58, 0.45, (s * 1.25, 3.2, 0), (160, 160, 170), axis="x", mat="Metal")
        for k in range(6):
            a = k * math.pi / 3
            m.blk("TireTread", (0.57, 0.1, 0.1), (s * 1.25, 3.2 + math.sin(a) * 0.57, math.cos(a) * 0.57), (25, 25, 28), R=rot(x=math.degrees(a)))
    # old TV head with dials, a speaker grille and rabbit-ear antennas
    m.rbox("TV", (1.6, 1.2, 1.2), (0, 3.95, 0), (110, 85, 60), 0.12, mat="Wood", axis="z")
    m.rbox("Screen", (1.15, 0.85, 0.08), (-0.12, 3.95, -0.6), (30, 60, 40), 0.15, axis="z")
    m.blk("ScreenGlass", (1.05, 0.75, 0.03), (-0.12, 3.95, -0.65), (60, 120, 80), mat="Glass", tr=0.6, refl=0.3)
    for s in (-1, 1):
        m.blk("ScreenEye", (0.24, 0.3, 0.04), (-0.12 + s * 0.24, 4.04, -0.66), (90, 255, 140), mat="Neon")
    m.blk("ScreenBrow", (0.3, 0.06, 0.04), (-0.36, 4.27, -0.66), (90, 255, 140), mat="Neon", R=rot(z=-15))
    m.blk("ScreenBrow", (0.3, 0.06, 0.04), (0.12, 4.27, -0.66), (90, 255, 140), mat="Neon", R=rot(z=15))
    m.blk("ScreenMouth", (0.5, 0.07, 0.04), (-0.12, 3.74, -0.66), (90, 255, 140), mat="Neon")
    for k in range(2):
        m.cyl("Knob", 0.1, 0.16, (0.62, 4.15 - k * 0.3, -0.62), (200, 200, 200), axis="z")
    for k in range(3):
        m.blk("Grille", (0.2, 0.03, 0.03), (0.62, 3.65 - k * 0.07, -0.61), (60, 45, 30))
    for s in (-1, 1):
        m.rod("Antenna", (s * 0.2, 4.55, 0.2), (s * 0.7, 5.25, 0.3), 0.06, (180, 180, 190), mat="Metal")
        m.ball("AntennaTip", 0.12, (s * 0.72, 5.28, 0.3), (200, 200, 210), mat="Foil")
    m.ell("AntennaBase", (0.4, 0.2, 0.3), (0, 4.58, 0.2), (40, 40, 45))
    # left arm: hose pipe with a wrench hand
    m.rod("ArmPipe", (-1.6, 3.15, 0), (-1.9, 2.0, -0.4), 0.4, (150, 150, 160), mat="Metal")
    m.ball("Elbow", 0.48, (-1.9, 2.0, -0.4), (110, 110, 120), mat="Metal")
    m.rod("ArmPipe", (-1.9, 2.0, -0.4), (-1.75, 1.2, -0.9), 0.36, (150, 150, 160), mat="Metal")
    for t in (0.3, 0.6):
        m.cyl("ArmBand", 0.08, 0.44, (-1.6 - 0.3 * t, 3.15 - 1.15 * t, -0.4 * t), (90, 90, 95), mat="Metal", R=rot(x=-19, z=-15))
    m.blk("Wrench", (0.25, 1.2, 0.12), (-1.72, 0.65, -1.05), (190, 190, 200), mat="Metal", R=rot(x=-20))
    m.blk("WrenchJaw", (0.6, 0.25, 0.14), (-1.72, 0.1, -1.25), (190, 190, 200), mat="Metal", R=rot(x=-20))
    m.cyl("WrenchBolt", 0.16, 0.16, (-1.72, 0.35, -1.15), (150, 150, 160), axis="z", mat="Metal")
    # right arm: crane claw with a hydraulic piston
    m.rod("ArmCrane", (1.6, 3.15, 0), (2.0, 2.3, -0.5), 0.45, (240, 190, 40), mat="Metal")
    m.ball("Elbow", 0.5, (2.0, 2.3, -0.5), (60, 60, 65), mat="Metal")
    m.rod("ArmCrane", (2.0, 2.3, -0.5), (2.0, 1.5, -0.9), 0.4, (240, 190, 40), mat="Metal")
    m.rod("Piston", (1.75, 3.0, -0.25), (2.15, 1.8, -0.75), 0.12, (210, 210, 215), mat="Metal")
    for k in range(3):
        m.blk("ArmPlate", (0.42, 0.06, 0.42), (1.6 + 0.4 * (k + 0.5) / 3, 3.15 - 0.85 * (k + 0.5) / 3, -0.5 * (k + 0.5) / 3), (30, 30, 30) if k % 2 else (240, 190, 40), R=rot(z=25))
    for s in (-1, 1):
        m.rod("Claw", (2.0, 1.4, -0.9), (2.0 + s * 0.35, 0.95, -1.05), 0.16, (110, 110, 120), mat="Metal")
        m.rod("Claw", (2.0 + s * 0.35, 0.95, -1.05), (2.0 + s * 0.15, 0.7, -1.15), 0.14, (110, 110, 120), mat="Metal")
    m.cyl("Claw", 0.3, 0.35, (2.0, 1.45, -0.9), (60, 60, 65), mat="Metal")
    # legs: paint cans with drips and laced boots
    for s, c in ((-1, (90, 120, 200)), (1, (220, 80, 60))):
        m.cyl("LegCan", 1.0, 0.8, (s * 0.55, 0.9, 0), c, mat="Metal")
        m.ring("LegCan", (s * 0.55, 1.4, 0), 0.4, 0.06, (170, 170, 175), normal="y", segments=12, mat="Metal")
        for k in range(3):
            a = math.radians(-40 + k * 40)
            m.drip("LegCan", (s * 0.55 + math.sin(a) * 0.41, 1.42, -math.cos(a) * 0.41), 0.25 + 0.12 * k, 0.1, shade(c, 1.15))
        m.shoe(s * 0.55, -0.15, 0.85, 1.2, (60, 45, 35), sole=(30, 25, 20), toe=(80, 60, 45), lace=(200, 180, 140), h=0.4)
    return m


@model
def the_junk_king():
    m = Model("the_junk_king")
    metal = (165, 170, 180)
    # trash can body with ribs and dents
    m.cyl("Can", 3.0, 2.4, (0, 1.95, 0), metal, mat="Metal", refl=0.2)
    for k in range(10):
        a = k * 2 * math.pi / 10
        m.blk("CanRib", (0.12, 2.8, 0.12), (math.cos(a) * 1.2, 1.95, math.sin(a) * 1.2), (140, 145, 155), mat="Metal", R=rot(y=-math.degrees(a)))
    m.ring("CanBand", (0, 0.6, 0), 1.22, 0.14, (140, 145, 155), normal="y", segments=16, mat="Metal")
    m.ring("CanBand", (0, 3.32, 0), 1.22, 0.14, (140, 145, 155), normal="y", segments=16, mat="Metal")
    m.ell("Dent", (0.5, 0.4, 0.15), (-0.55, 1.4, -1.08), (140, 145, 155), mat="Metal", R=rot(y=25))
    m.ell("Rust", (0.4, 0.22, 0.08), (0.65, 0.9, -1.02), (150, 90, 50), mat="CorrodedMetal", R=rot(y=-32))
    # dark gap with glowing eyes under the lid
    m.cyl("Gap", 0.55, 2.3, (0, 3.6, 0), (20, 20, 25))
    for s in (-1, 1):
        eye = m.ell("Eye", (0.44, 0.32, 0.2), (s * 0.4, 3.62, -1.1), (255, 230, 80), mat="Neon")
        m.ell("Pupil", (0.12, 0.2, 0.06), (s * 0.4, 3.62, -1.2), (90, 60, 10))
        m.blk("Brow", (0.5, 0.1, 0.1), (s * 0.4, 3.83, -1.12), (20, 20, 25), R=rot(z=s * 14))
    m.light(eye, (255, 220, 120), 0.8, 5)
    # grand curly mustache
    for s in (-1, 1):
        m.chain("Mustache", [(0, 3.28, -1.22), (s * 0.35, 3.22, -1.2), (s * 0.7, 3.3, -1.1), (s * 0.85, 3.5, -0.98), (s * 0.75, 3.62, -0.98)], 0.2, (90, 70, 50), mat="Fabric")
    # lid with a crown made of bottle caps and spoons
    m.cyl("TrashLid", 0.25, 2.6, (0, 4.0, 0), metal, mat="Metal", refl=0.25)
    m.ring("TrashLidRim", (0, 4.0, 0), 1.3, 0.1, (140, 145, 155), normal="y", segments=16, mat="Metal")
    m.cyl("LidHandle", 0.2, 0.9, (0, 4.2, 0), (150, 150, 160), mat="Metal")
    crown = m.cyl("Crown", 0.5, 1.5, (0, 4.55, 0), (245, 200, 60), mat="Metal", refl=0.3)
    m.ring("CrownBand", (0, 4.35, 0), 0.76, 0.08, (255, 225, 120), normal="y", segments=14, mat="Metal")
    for k in range(6):
        a = k * 2 * math.pi / 6
        m.ell("CrownPoint", (0.28, 0.6, 0.28), (math.cos(a) * 0.68, 4.95, math.sin(a) * 0.68), (245, 200, 60), mat="Metal")
        m.ball("CrownPoint", 0.14, (math.cos(a) * 0.7, 5.3, math.sin(a) * 0.7), (255, 245, 200), mat="Metal", refl=0.3)
        cap = [(220, 40, 40), (40, 120, 220), (60, 180, 80)][k % 3]
        m.cyl("BottleCap", 0.08, 0.28, (math.cos(a) * 0.77, 4.55, math.sin(a) * 0.77), cap, axis="z", R=rot(y=-math.degrees(a) - 90))
        m.ring("BottleCap", (math.cos(a) * 0.79, 4.55, math.sin(a) * 0.79), 0.14, 0.03, shade(cap, 0.8), normal="z", segments=8, R=rot(y=-math.degrees(a) - 90))
    for s in (-1, 1):
        m.ell("Spoon", (0.16, 0.5, 0.06), (s * 0.45, 5.15, -0.55), (210, 215, 225), mat="Metal", R=rot(z=s * 20))
    m.sparkles(crown, (255, 220, 100))
    # cape (old red blanket with patches, a fur collar and a ragged hem)
    # the cape wraps round the can in three panels, with folds, gold trim and a trash-can crest
    cape = (180, 30, 40)
    gold = (240, 195, 70)
    for (x, z, w, yaw) in [(0, 1.38, 1.15, 0), (-1.0, 1.15, 1.0, -30), (1.0, 1.15, 1.0, 30)]:
        m.blk("Cape", (w, 3.4, 0.15), (x, 2.1, z), cape, mat="Fabric", R=rot(x=-6, y=yaw))
        m.blk("CapeTrim", (w, 0.12, 0.17), (x, 0.42, z + 0.17), gold, mat="Fabric", R=rot(x=-6, y=yaw))
        for f in (-0.25, 0.25):
            fx = x + f * math.cos(math.radians(yaw))
            fz = z + 0.06 - f * math.sin(math.radians(yaw))
            m.ell("CapeFold", (0.12, 3.0, 0.1), (fx, 1.95, fz + 0.05), shade(cape, 0.8), mat="Fabric", R=rot(x=-6, y=yaw))
    for k in range(7):
        x = -1.2 + k * 0.4
        z = 1.55 if abs(x) < 0.55 else 1.55 - (abs(x) - 0.55) * 0.58
        m.wedge("CapeHem", (0.38, 0.3, 0.15), (x, 0.3, z), cape, mat="Fabric", R=rot(x=-6, y=(30 if x > 0.55 else -30 if x < -0.55 else 0)) @ rot(z=180))
    m.ring("Crest", (0, 2.35, 1.55), 0.42, 0.08, gold, normal="z", segments=14, mat="Metal", R=rot(x=-6))
    m.cyl("CrestBack", 0.03, 0.8, (0, 2.35, 1.53), (130, 20, 30), axis="z", R=rot(x=-6))
    m.blk("CrestCan", (0.34, 0.4, 0.04), (0, 2.27, 1.57), gold, mat="Metal", R=rot(x=-6))
    m.blk("CrestLid", (0.44, 0.07, 0.04), (0, 2.52, 1.59), gold, mat="Metal", R=rot(x=-6, z=-12))
    for x in (-0.09, 0.0, 0.09):
        m.blk("CrestRib", (0.03, 0.3, 0.02), (x, 2.26, 1.6), (180, 130, 40), R=rot(x=-6))
    m.blk("Patch", (0.5, 0.45, 0.04), (0.98, 2.3, 1.27), (60, 90, 170), mat="Fabric", R=rot(x=-6, y=30, z=10))
    m.stitches("Stitch", (0.8, 2.08, 1.39), (1.15, 2.5, 1.19), 4, 0.04, (250, 240, 200))
    m.blk("Patch", (0.45, 0.4, 0.04), (-0.95, 1.3, 1.37), (220, 180, 60), mat="Fabric", R=rot(x=-6, y=-30, z=-12))
    m.stitches("Stitch", (-1.12, 1.12, 1.47), (-0.78, 1.48, 1.28), 3, 0.04, (250, 240, 200))
    m.blk("CapeCollar", (2.9, 0.4, 0.5), (0, 3.4, 1.15), (240, 240, 240), mat="Fabric")
    for k in range(6):
        m.ell("CollarSpot", (0.1, 0.16, 0.05), (-1.2 + k * 0.48, 3.4, 0.88), (30, 30, 30))
    # can-lid medal on a ribbon
    m.wedge("Ribbon", (0.3, 0.4, 0.05), (-0.5, 2.85, -1.18), (60, 110, 210), R=rot(z=180))
    m.cyl("Medal", 0.06, 0.4, (-0.5, 2.55, -1.21), (215, 220, 230), axis="z", mat="Metal", refl=0.3)
    m.ring("Medal", (-0.5, 2.55, -1.24), 0.15, 0.03, (170, 175, 185), normal="z", segments=8, mat="Metal")
    # arms in dish gloves and a plunger scepter
    m.rod("Arm", (-1.25, 2.9, 0), (-1.7, 2.2, -0.6), 0.45, metal, mat="Metal")
    m.cyl("Cuff", 0.25, 0.6, (-1.62, 2.32, -0.5), (255, 225, 60), R=rot(x=50, z=-30), mat="Rubber")
    m.mitt((-1.72, 2.15, -0.65), 0.56, (255, 225, 60), -1, mat="Rubber")
    m.rod("Arm", (1.25, 2.9, 0), (1.75, 2.3, -0.6), 0.45, metal, mat="Metal")
    m.cyl("Cuff", 0.25, 0.6, (1.68, 2.42, -0.5), (255, 225, 60), R=rot(x=50, z=30), mat="Rubber")
    m.mitt((1.77, 2.25, -0.65), 0.56, (255, 225, 60), 1, mat="Rubber")
    m.cyl("PlungerStick", 3.2, 0.2, (1.8, 2.6, -0.7), (150, 100, 60), mat="Wood")
    for k in range(3):
        m.cyl("PlungerBand", 0.08, 0.23, (1.8, 1.5 + k * 0.9, -0.7), (245, 200, 60), mat="Metal")
    m.ell("PlungerCup", (0.92, 0.62, 0.92), (1.8, 4.3, -0.7), (200, 40, 50), mat="Rubber")
    m.ring("PlungerBand", (1.8, 4.02, -0.7), 0.45, 0.08, (160, 30, 40), normal="y", segments=12, mat="Rubber")
    m.ball("ScepterTop", 0.25, (1.8, 4.65, -0.7), (245, 200, 60), mat="Metal")
    # banana peel epaulette and a rubber boot pair
    m.ell("Peel", (0.5, 0.2, 0.4), (-0.85, 3.4, -0.55), (250, 220, 70), R=rot(z=20))
    for k in (-1, 1):
        m.ell("Peel", (0.14, 0.4, 0.1), (-0.85 + k * 0.2, 3.22, -0.75), (250, 220, 70), R=rot(z=k * 25, x=15))
    for s in (-1, 1):
        m.shoe(s * 0.7, -0.4, 0.9, 1.2, (60, 60, 70), sole=(30, 30, 35), toe=(75, 75, 85), mat="Rubber", h=0.42)

    return m
