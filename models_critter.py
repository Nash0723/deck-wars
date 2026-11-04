# Critter family models (cute fuzzy animals with big eyes and little outfits)
import math
from modelkit import Model, rot, Rx, Ry, Rz, WHITE, PUPIL, shade

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


@model
def pocket_mouse():
    m = Model("pocket_mouse")
    denim = (60, 95, 160)
    gray = (165, 165, 175)
    pink = (250, 170, 185)
    thread = (240, 190, 90)
    # jeans pocket with double stitching, rivets and a leather tag
    m.rbox("Pocket", (2.2, 1.4, 0.9), (0, 0.7, 0.1), denim, 0.12, mat="Fabric")
    m.blk("PocketLip", (2.25, 0.2, 0.95), (0, 1.38, 0.1), (75, 115, 185), mat="Fabric")
    for x in (-0.95, -0.88, 0.88, 0.95):
        m.blk("Stitch", (0.03, 1.15, 0.02), (x, 0.72, -0.36), thread)
    for y in (0.15, 0.22):
        m.blk("Stitch", (1.85, 0.03, 0.02), (0, y, -0.36), thread)
    m.blk("Stitch", (2.0, 0.03, 0.02), (0, 1.28, -0.39), thread)
    for x in (-0.95, 0.95):
        m.cyl("Rivet", 0.06, 0.18, (x, 1.3, -0.4), (200, 160, 70), axis="z", mat="Metal")
    m.rbox("Tag", (0.5, 0.28, 0.04), (0.55, 0.45, -0.37), (150, 95, 55), 0.05, mat="Leather", axis="z")
    m.cyl("Coin", 0.05, 0.3, (-0.7, 1.52, -0.05), (240, 200, 60), mat="Metal", axis="z", R=rot(x=-20))
    # mouse peeking out
    m.ell("Body", (1.0, 1.0, 0.8), (0, 1.55, 0.15), gray, mat="Fabric")
    m.ell("Belly", (0.6, 0.55, 0.3), (0, 1.55, -0.2), (230, 225, 230), mat="Fabric")
    m.ell("Head", (1.15, 1.0, 1.0), (0, 2.2, -0.05), gray, mat="Fabric")
    m.ell("Muzzle", (0.6, 0.42, 0.45), (0, 2.02, -0.4), (225, 220, 228), mat="Fabric")
    for s in (-1, 1):
        m.cyl("Ear", 0.12, 0.9, (s * 0.55, 2.78, 0.05), gray, axis="z", R=rot(y=s * 12))
        m.cyl("EarInner", 0.13, 0.62, (s * 0.55, 2.78, 0.0), pink, axis="z", R=rot(y=s * 12))
        # little paws gripping the pocket edge, with fingers
        m.ball("Paw", 0.3, (s * 0.35, 1.45, -0.32), pink)
        for k in (-1, 0, 1):
            m.ball("Finger", 0.11, (s * 0.35 + k * 0.08, 1.36, -0.45), pink)
        for k in (-1, 1):
            m.blk("Whisker", (0.6, 0.025, 0.025), (s * 0.48, 2.05 + k * 0.06, -0.55), (60, 60, 60), R=rot(z=s * k * 10, y=s * 12))
    m.eyes(2.32, -0.5, 0.42, 0.3, lid=gray, iris=(70, 50, 40), z_back=0.04)
    m.ball("Nose", 0.2, (0, 2.08, -0.62), (240, 120, 150))
    m.ball("NoseShine", 0.06, (0.04, 2.12, -0.71), WHITE)
    m.grin(1.9, -0.6, 0.22, curve=0.35, color=(90, 50, 60))
    m.blk("Tooth", (0.07, 0.1, 0.04), (-0.04, 1.83, -0.62), WHITE)
    m.blk("Tooth", (0.07, 0.1, 0.04), (0.04, 1.83, -0.62), WHITE)
    m.cheeks(2.05, -0.5, 0.75, 0.2)
    m.chain("Tail", [(0.9, 1.0, 0.3), (1.25, 1.3, 0.35), (1.3, 1.7, 0.25), (1.1, 1.95, 0.2), (0.95, 1.9, 0.15)], 0.08, pink, joints=False)
    # a cheese wedge snack with holes
    m.wedge("Cheese", (0.35, 0.32, 0.45), (-0.62, 1.55, -0.45), (255, 210, 70), R=rot(y=30))
    for (dx, dy) in [(-0.05, -0.05), (0.06, 0.05)]:
        m.ball("CheeseHole", 0.07, (-0.62 + dx - 0.1, 1.5 + dy, -0.6), (220, 170, 40))
    return m


@model
def moth_mailman():
    m = Model("moth_mailman")
    fuzz = (230, 215, 180)
    wing = (210, 190, 150)
    m.ell("Body", (0.9, 1.5, 0.9), (0, 1.55, 0.1), fuzz, mat="Fabric")
    for k in range(3):
        m.ring("BodyStripe", (0, 1.15 + k * 0.28, 0.1), 0.44 - abs(k - 1) * 0.05, 0.05, shade(fuzz, 0.85), normal="y", segments=10, mat="Fabric")
    m.ell("Head", (0.95, 0.85, 0.85), (0, 2.55, -0.1), fuzz, mat="Fabric")
    m.ell("Ruff", (1.25, 0.42, 1.12), (0, 2.15, 0.0), (250, 245, 235), mat="Fabric")
    m.scatter("Fluff", (0, 2.15, 0), (1.25, 0.42, 1.12), 8, [(255, 252, 245)], seed=5, d=0.2, shape="dot", ymin=-0.3, mat="Fabric")
    for s in (-1, 1):
        m.ell("Wing", (1.6, 1.5, 0.12), (s * 1.0, 2.0, 0.45), wing, R=rot(y=s * 25, z=s * -10))
        m.ell("WingLow", (1.0, 0.9, 0.1), (s * 0.75, 1.25, 0.5), wing, R=rot(y=s * 25, z=s * 20))
        # eye spots with rings, veins and a pale edge
        m.ell("WingSpot", (0.52, 0.52, 0.14), (s * 1.15, 2.1, 0.38), (240, 225, 190), R=rot(y=s * 25))
        m.ell("WingSpot", (0.38, 0.38, 0.15), (s * 1.15, 2.1, 0.37), (120, 90, 160), R=rot(y=s * 25))
        m.ell("WingSpot", (0.14, 0.14, 0.16), (s * 1.17, 2.13, 0.36), (40, 30, 50), R=rot(y=s * 25))
        m.ell("WingSpot", (0.25, 0.25, 0.12), (s * 0.78, 1.2, 0.44), (150, 120, 90), R=rot(y=s * 25))
        for k in range(3):
            a = math.radians(-25 + k * 30)
            m.rod("WingTip", (s * 0.35, 2.0, 0.55), (s * (0.35 + math.cos(a) * 1.15), 2.0 + math.sin(a) * 0.8, 0.55 + math.cos(a) * 0.48), 0.04, shade(wing, 0.8))
        # feathery antennae
        m.rod("Antenna", (s * 0.18, 2.9, -0.2), (s * 0.55, 3.45, -0.35), 0.06, (120, 100, 80))
        for k in range(3):
            t = 0.4 + k * 0.25
            m.ell("AntennaTip", (0.3, 0.08, 0.06), (s * (0.18 + 0.37 * t), 2.9 + 0.55 * t, -0.2 - 0.15 * t), (150, 125, 95), R=rot(z=s * -20))
        m.ell("AntennaTip", (0.25, 0.4, 0.12), (s * 0.58, 3.5, -0.37), (150, 125, 95), R=rot(z=s * 30))
    m.eyes(2.58, -0.45, 0.4, 0.34, lid=fuzz, pupil=(40, 30, 60), pupil_scale=0.7, iris=(90, 70, 150), z_back=0.04)
    m.grin(2.28, -0.48, 0.24, curve=0.3)
    m.cheeks(2.38, -0.44, 0.72, 0.16)
    # mail cap with a badge
    m.cyl("Cap", 0.38, 0.82, (0, 3.0, -0.05), (50, 80, 160))
    m.ell("Cap", (0.84, 0.2, 0.84), (0, 3.2, -0.05), (50, 80, 160))
    m.cyl("HatBand", 0.08, 0.84, (0, 2.87, -0.05), (240, 200, 60))
    m.blk("CapBill", (0.72, 0.08, 0.45), (0, 2.85, -0.5), (40, 65, 140))
    m.cyl("CapBadge", 0.05, 0.2, (0, 3.04, -0.44), (240, 200, 60), axis="z", mat="Metal")
    # leather mail bag with a flap, buckle and letters
    m.rod("Strap", (-0.45, 2.2, -0.35), (0.5, 1.2, -0.45), 0.08, (110, 70, 40), mat="Leather")
    m.rbox("Bag", (0.78, 0.62, 0.35), (0.55, 1.1, -0.5), (140, 95, 55), 0.08, mat="Leather", axis="z")
    m.blk("BagFlap", (0.8, 0.28, 0.37), (0.55, 1.32, -0.52), (120, 80, 45), mat="Leather")
    m.blk("Buckle", (0.12, 0.12, 0.04), (0.55, 1.2, -0.72), (230, 200, 90), mat="Metal")
    for k, (x, a) in enumerate([(0.42, 10), (0.62, -8)]):
        m.blk("Letter", (0.45, 0.32, 0.04), (x, 1.5 + k * 0.05, -0.52 + k * 0.05), (250, 250, 245), R=rot(z=a))
        m.blk("Stamp", (0.1, 0.1, 0.02), (x + 0.13, 1.56 + k * 0.05, -0.55 + k * 0.05), [(220, 60, 60), (60, 150, 220)][k], R=rot(z=a))
    m.wedge("Seal", (0.12, 0.1, 0.02), (0.42, 1.43, -0.55), (200, 40, 40), R=rot(z=190))
    # little legs, hovering pose
    for s in (-1, 1):
        m.rod("Leg", (s * 0.25, 0.9, 0.05), (s * 0.35, 0.3, -0.05), 0.12, (120, 100, 80))
        m.ball("Knee", 0.15, (s * 0.3, 0.6, 0.0), (110, 90, 70))
        m.ell("Foot", (0.25, 0.14, 0.35), (s * 0.36, 0.25, -0.12), (120, 100, 80))
    m.cyl("Stand", 0.06, 1.2, (0, 0.03, 0), (180, 170, 150), tr=0.5)
    return m


@model
def pillow_bunny():
    m = Model("pillow_bunny")
    pil = (215, 200, 245)
    edge = (190, 170, 225)
    m.ell("Body", (2.1, 1.9, 1.1), (0, 1.15, 0), pil, mat="Fabric")
    for (x, y) in [(-1.0, 0.25), (1.0, 0.25), (-1.0, 2.05), (1.0, 2.05)]:
        m.ell("Corner", (0.45, 0.45, 0.35), (x, y, 0), pil, mat="Fabric")
        m.ball("Tassel", 0.18, (x * 1.15, y + (0.12 if y > 1 else -0.12), 0), (255, 225, 120), mat="Fabric")
    m.blk("Seam", (2.0, 0.05, 1.12), (0, 1.15, 0), edge, mat="Fabric")
    m.ring("Piping", (0, 1.15, 0), 1.0, 0.07, edge, normal="z", segments=16, R=rot(x=0) @ rot(z=0))
    # embroidered stars and moons
    for (x, y, c) in [(-0.62, 0.6, (255, 230, 120)), (0.6, 1.75, (255, 230, 120)), (0.62, 0.78, (190, 220, 255))]:
        for k in range(3):
            m.blk("Star", (0.2, 0.05, 0.02), (x, y, -0.55), c, R=rot(z=k * 60))
    m.blk("Tag", (0.25, 0.35, 0.03), (0.75, 0.42, -0.52), (255, 255, 255))
    m.blk("TagLine", (0.15, 0.03, 0.02), (0.75, 0.45, -0.54), (200, 120, 160))
    for s in (-1, 1):
        m.ell("Ear", (0.47, 1.52, 0.3), (s * 0.45, 2.6, 0.05), pil, mat="Fabric", R=rot(z=s * -18, x=10))
        m.ell("EarInner", (0.28, 1.15, 0.1), (s * 0.43, 2.55, -0.08), (255, 185, 210), R=rot(z=s * -18, x=10))
    # a sleepy, snuggly face with a floating "Zz"
    m.eyes(1.5, -0.52, 0.65, 0.34, lid=pil, sleepy=True, iris=(140, 100, 200), lash=2)
    m.ell("Nose", (0.22, 0.16, 0.12), (0, 1.25, -0.56), (250, 140, 170))
    m.grin(1.06, -0.55, 0.32, curve=0.3, color=(150, 80, 120))
    m.cheeks(1.15, -0.52, 1.1, 0.3)
    for k, (x, y, sz) in enumerate([(0.95, 2.75, 0.3), (1.25, 3.15, 0.22)]):
        m.blk("Zz", (sz, sz * 0.18, 0.05), (x, y + sz * 0.4, -0.2), (200, 220, 255), mat="Neon")
        m.blk("Zz", (sz * 1.1, sz * 0.18, 0.05), (x, y, -0.2), (200, 220, 255), mat="Neon", R=rot(z=-45))
        m.blk("Zz", (sz, sz * 0.18, 0.05), (x, y - sz * 0.4, -0.2), (200, 220, 255), mat="Neon")
    # paws with pink toe beans
    for s in (-1, 1):
        m.ball("Paw", 0.45, (s * 0.85, 0.85, -0.45), (240, 230, 255), mat="Fabric")
        m.ell("Foot", (0.55, 0.3, 0.75), (s * 0.55, 0.15, -0.35), (240, 230, 255), mat="Fabric")
        m.ell("Toe", (0.22, 0.14, 0.06), (s * 0.55, 0.17, -0.72), (255, 170, 200))
        for k in (-1, 0, 1):
            m.ball("Toe", 0.09, (s * 0.55 + k * 0.12, 0.27, -0.7), (255, 170, 200))
    m.ball("Tail", 0.5, (0, 0.8, 0.6), (255, 255, 255), mat="Fabric")
    m.ball("Tail", 0.32, (0.1, 0.95, 0.75), (255, 255, 255), mat="Fabric")
    # floating feathers
    for (x, y, z, a) in [(-1.3, 2.3, -0.3, 30), (1.35, 1.9, 0.2, -40), (0.9, 2.9, -0.4, 60), (-1.1, 0.6, -0.6, -20)]:
        m.ell("Feather", (0.12, 0.45, 0.06), (x, y, z), (255, 255, 255), R=rot(z=a))
        m.rod("Feather", (x - math.sin(math.radians(-a)) * 0.25, y - math.cos(math.radians(a)) * 0.25, z), (x, y, z), 0.025, (220, 220, 230))
    return m


@model
def hamster_wheel_hero():
    m = Model("hamster_wheel_hero")
    fur = (235, 165, 90)
    # wheel standing on a base with wood shavings, wheel plane = YZ so the hamster runs toward -Z
    m.rbox("Base", (2.6, 0.2, 2.8), (0, 0.1, 0), (90, 130, 200), 0.2)
    m.scatter("Shaving", (0, 0.2, 0), (2.4, 0.05, 2.6), 14, [(240, 215, 160), (225, 195, 140)], seed=3, d=0.1, shape="sprinkle", length=2.0, ymin=0.5)
    for s in (-1, 1):
        m.rod("Stand", (s * 1.15, 0.2, -0.8), (s * 1.15, 1.6, 0), 0.14, (200, 200, 210), mat="Metal")
        m.rod("Stand", (s * 1.15, 0.2, 0.8), (s * 1.15, 1.6, 0), 0.14, (200, 200, 210), mat="Metal")
        m.ring("Wheel", (s * 0.95, 1.6, 0), 1.35, 0.13, (220, 60, 60), normal="x", segments=16, mat="Metal")
        m.cyl("WheelHub", 0.12, 0.4, (s * 0.95, 1.6, 0), (250, 210, 60), axis="x", mat="Metal")
        for k in range(4):
            a = k * math.pi / 4
            m.rod("Spoke", (s * 0.95, 1.6 + math.sin(a) * 1.3, math.cos(a) * 1.3), (s * 0.95, 1.6 - math.sin(a) * 1.3, -math.cos(a) * 1.3), 0.05, (230, 230, 235), mat="Metal")
    m.cyl("Axle", 2.4, 0.16, (0, 1.6, 0), (200, 200, 210), axis="x", mat="Metal")
    for k in range(14):
        a = k * 2 * math.pi / 14
        m.cyl("Rung", 1.9, 0.07, (0, 1.6 + math.sin(a) * 1.35, math.cos(a) * 1.35), (230, 230, 235), axis="x", mat="Metal")
    # hamster running inside
    m.ell("Body", (1.0, 0.95, 1.3), (0, 0.85, -0.05), fur, R=rot(x=-15), mat="Fabric")
    m.ell("Belly", (0.75, 0.6, 0.8), (0, 0.72, -0.25), (255, 240, 220), mat="Fabric")
    m.ell("Emblem", (0.32, 0.3, 0.06), (0, 0.85, -0.66), (250, 210, 60), R=rot(x=-15))
    m.blk("EmblemBolt", (0.06, 0.22, 0.03), (0, 0.85, -0.69), (220, 30, 40), R=rot(x=-15, z=20))
    m.ell("Head", (0.85, 0.8, 0.8), (0, 1.35, -0.6), fur, mat="Fabric")
    for s in (-1, 1):
        m.ell("Cheek", (0.36, 0.36, 0.36), (s * 0.35, 1.22, -0.75), (255, 235, 210), mat="Fabric")
        m.ell("Ear", (0.26, 0.32, 0.1), (s * 0.3, 1.75, -0.5), (240, 150, 140))
        m.ell("EarInner", (0.15, 0.2, 0.05), (s * 0.3, 1.74, -0.56), (255, 190, 190))
        m.rod("Leg", (s * 0.25, 0.6, 0.1), (s * 0.25, 0.32, 0.45 if s > 0 else -0.3), 0.14, (240, 150, 140))
        m.ell("Foot", (0.16, 0.08, 0.22), (s * 0.25, 0.3, 0.5 if s > 0 else -0.36), (240, 150, 140))
        m.blk("Whisker", (0.4, 0.02, 0.02), (s * 0.35, 1.26, -1.0), (90, 60, 40), R=rot(z=s * 8))
    # superhero mask with eye holes, determined face
    m.rbox("Mask", (0.88, 0.2, 0.1), (0, 1.47, -0.97), (30, 30, 40), 0.05, axis="z")
    for s in (-1, 1):
        m.wedge("MaskTail", (0.05, 0.12, 0.35), (s * 0.3, 1.5, -0.55), (30, 30, 40), R=rot(x=-20))
    m.eyes(1.47, -1.02, 0.36, 0.2, lid=None, iris=(90, 60, 30))
    m.ball("Nose", 0.12, (0, 1.28, -1.02), (240, 120, 130))
    m.grin(1.15, -0.98, 0.2, curve=0.3)
    m.blk("Tooth", (0.08, 0.08, 0.03), (0, 1.11, -1.0), WHITE)
    # tiny fists pumping and a cape flowing back
    for s in (-1, 1):
        m.rod("Arm", (s * 0.35, 1.0, -0.4), (s * 0.4, 1.05, -0.8), 0.11, fur)
        m.ball("Hand", 0.14, (s * 0.4, 1.05, -0.83), (240, 150, 140))
    m.blk("Cape", (0.9, 0.08, 1.4), (0, 1.25, 0.55), (220, 30, 40), mat="Fabric", R=rot(x=-20))
    for k in range(3):
        m.wedge("CapeHem", (0.3, 0.08, 0.2), (-0.3 + k * 0.3, 1.0, 1.25), (220, 30, 40), mat="Fabric", R=rot(x=-20) @ rot(x=90))
    m.blk("CapeTie", (0.8, 0.12, 0.12), (0, 1.12, -0.25), (250, 210, 60))
    # speed lines
    for (y, z, L) in [(0.7, 0.9, 0.5), (1.0, 1.1, 0.7), (1.3, 0.95, 0.4)]:
        m.blk("Speed", (0.04, 0.04, L), (0.6, y, z), (255, 255, 255), mat="Neon", tr=0.4)
    return m


def pigeon_body(m, x, z, scale=1.0, helmet=True, yaw=0.0):
    s = scale
    gray = (150, 155, 170)
    dgray = (120, 125, 145)
    cx, cz = x, z
    m.ell("Body", (0.85 * s, 0.85 * s, 1.2 * s), (cx, 0.75 * s, cz + 0.1 * s), gray, R=rot(x=-10, y=yaw))
    m.ell("Chest", (0.6 * s, 0.55 * s, 0.3 * s), (cx, 0.85 * s, cz - 0.4 * s), (170, 165, 185))
    # shimmering green and purple neck
    m.ell("Neck", (0.62 * s, 0.5 * s, 0.62 * s), (cx, 1.15 * s, cz - 0.2 * s), (110, 160, 140), refl=0.25)
    m.ell("Neck", (0.5 * s, 0.28 * s, 0.5 * s), (cx, 1.0 * s, cz - 0.28 * s), (150, 110, 170), refl=0.25)
    m.ball("Head", 0.6 * s, (cx, 1.5 * s, cz - 0.3 * s), gray)
    m.ell("Beak", (0.14 * s, 0.12 * s, 0.3 * s), (cx, 1.45 * s, cz - 0.65 * s), (240, 170, 60))
    m.ell("Snoot", (0.12 * s, 0.07 * s, 0.1 * s), (cx, 1.53 * s, cz - 0.58 * s), (240, 235, 230))
    for k in (-1, 1):
        # layered wings with darker bars and feather tips
        m.ell("Wing", (0.15 * s, 0.6 * s, 0.9 * s), (cx + k * 0.42 * s, 0.8 * s, cz + 0.15 * s), dgray, R=rot(x=-15))
        m.ell("Wing", (0.1 * s, 0.12 * s, 0.6 * s), (cx + k * 0.48 * s, 0.85 * s, cz + 0.2 * s), (70, 75, 90), R=rot(x=-15))
        m.ell("WingTip", (0.1 * s, 0.25 * s, 0.5 * s), (cx + k * 0.4 * s, 0.6 * s, cz + 0.55 * s), (90, 95, 110), R=rot(x=-30))
        m.cyl("Leg", 0.35 * s, 0.08 * s, (cx + k * 0.18 * s, 0.2 * s, cz), (240, 130, 140))
        for t in (-1, 0, 1):
            m.ell("Toe", (0.05 * s, 0.05 * s, 0.22 * s), (cx + k * 0.18 * s + t * 0.06 * s, 0.03 * s, cz - 0.12 * s), (240, 130, 140), R=rot(y=t * 25))
    m.ell("Tail", (0.5 * s, 0.12 * s, 0.6 * s), (cx, 0.75 * s, cz + 0.8 * s), dgray, R=rot(x=20))
    m.ell("Tail", (0.5 * s, 0.1 * s, 0.15 * s), (cx, 0.66 * s, cz + 1.05 * s), (70, 75, 90), R=rot(x=20))
    m.eyes(1.58 * s, cz - 0.55 * s, 0.32 * s, 0.17 * s, x=cx, lid=gray, pupil=PUPIL, pupil_scale=0.45, iris=(230, 110, 40), z_back=0.02 * s)
    if helmet:
        m.ell("Helmet", (0.78 * s, 0.42 * s, 0.78 * s), (cx, 1.75 * s, cz - 0.28 * s), (80, 110, 60))
        m.ring("HelmetRim", (cx, 1.66 * s, cz - 0.28 * s), 0.38 * s, 0.05 * s, (60, 85, 45), normal="y", segments=10)
        for (dx, dz) in [(-0.15, -0.1), (0.18, 0.05), (0.0, 0.2)]:
            m.ell("HelmetRivet", (0.14 * s, 0.06 * s, 0.1 * s), (cx + dx * s, 1.93 * s, cz - 0.28 * s + dz * s), (110, 130, 70))
        m.blk("HelmetStrap", (0.05 * s, 0.35 * s, 0.05 * s), (cx + 0.3 * s, 1.55 * s, cz - 0.42 * s), (60, 80, 45))


@model
def pigeon_squad():
    m = Model("pigeon_squad")
    pigeon_body(m, 0.0, -0.75, 1.15)
    pigeon_body(m, -1.05, 0.55, 1.0)
    pigeon_body(m, 1.05, 0.55, 1.0)
    # sergeant stripes on the leader, bread-crumb ammo belts and a tiny flag
    for k in range(2):
        m.blk("Stripe", (0.06, 0.06, 0.3), (0.5, 1.02 - k * 0.1, -0.6), (250, 210, 60), R=rot(x=20))
    for cx, cz in ((-1.05, 0.55), (1.05, 0.55)):
        m.rod("Belt", (cx - 0.35, 1.05, cz - 0.3), (cx + 0.35, 0.65, cz - 0.4), 0.08, (110, 80, 50), shape="B")
        for k in range(3):
            m.blk("Crumb", (0.09, 0.09, 0.07), (cx - 0.2 + k * 0.2, 0.97 - k * 0.11, cz - 0.42), (220, 180, 110))
    m.cyl("FlagPole", 1.6, 0.06, (1.6, 1.0, 0.6), (200, 200, 210), mat="Metal")
    m.ball("FlagTop", 0.12, (1.6, 1.82, 0.6), (240, 200, 60), mat="Metal")
    m.blk("Flag", (0.6, 0.4, 0.04), (1.92, 1.6, 0.6), (220, 60, 60), mat="Fabric")
    m.blk("FlagStripe", (0.6, 0.08, 0.05), (1.92, 1.6, 0.6), (250, 250, 250), mat="Fabric")
    return m


@model
def pigeon_token():
    m = Model("pigeon", kind="token")
    pigeon_body(m, 0.0, 0.0, 1.3)
    return m


@model
def sergeant_snail():
    m = Model("sergeant_snail")
    slime = (205, 215, 150)
    shell = (190, 120, 70)
    band = (150, 90, 50)
    # foot / body with a shiny slime trail
    m.ell("Foot", (1.3, 0.6, 3.0), (0, 0.3, 0), slime, refl=0.25)
    m.ell("Slime", (1.0, 0.06, 1.4), (0, 0.03, 1.4), (190, 230, 170), mat="Glass", tr=0.3, refl=0.4)
    m.ell("Neck", (0.9, 1.6, 0.9), (0, 1.1, -1.05), slime, refl=0.25, R=rot(x=-12))
    m.ell("Head", (1.0, 0.9, 0.95), (0, 1.95, -1.25), slime, refl=0.25)
    m.scatter("Freckle", (0, 1.1, -1.05), (0.92, 1.6, 0.92), 6, [shade(slime, 0.85)], seed=9, d=0.12, shape="dot", front_only=True)
    for s in (-1, 1):
        m.rod("Stalk", (s * 0.2, 2.25, -1.25), (s * 0.45, 3.05, -1.35), 0.14, slime)
        m.ball("Eyeball", 0.44, (s * 0.47, 3.12, -1.37), WHITE)
        m.ball("Iris", 0.26, (s * 0.47, 3.12, -1.5), (90, 140, 60))
        m.ball("Pupil", 0.15, (s * 0.47, 3.12, -1.6), PUPIL)
        m.ball("Glint", 0.06, (s * 0.47 + 0.05, 3.17, -1.66), WHITE)
        m.ball("Lid", 0.48, (s * 0.47, 3.12, -1.37), slime, tr=1)
        m.ell("Lidhalf", (0.48, 0.2, 0.48), (s * 0.47, 3.28, -1.39), shade(slime, 0.9), R=rot(z=s * 15))
    # grand drill-sergeant mustache and a whistle on a cord
    for s in (-1, 1):
        m.chain("Mustache", [(0, 1.75, -1.72), (s * 0.25, 1.72, -1.7), (s * 0.45, 1.78, -1.6), (s * 0.55, 1.9, -1.5)], 0.16, (90, 70, 50), mat="Fabric")
    m.grin(1.58, -1.7, 0.32, curve=-0.15, color=(80, 70, 50))
    m.rod("Cord", (-0.3, 1.5, -1.55), (0.1, 1.1, -1.55), 0.04, (220, 60, 60))
    m.cyl("Whistle", 0.25, 0.14, (0.15, 1.05, -1.6), (220, 220, 230), axis="x", mat="Metal")
    # drill sergeant hat with pinched crown
    m.cyl("HatBrim", 0.08, 1.4, (0, 2.42, -1.25), (120, 95, 60))
    m.cyl("HatCrown", 0.45, 0.75, (0, 2.65, -1.25), (130, 105, 65))
    m.ell("HatCrown", (0.75, 0.25, 0.75), (0, 2.87, -1.25), (130, 105, 65))
    for k in range(4):
        a = k * math.pi / 2
        m.ell("HatDent", (0.14, 0.25, 0.14), (math.cos(a) * 0.29, 2.85, -1.25 + math.sin(a) * 0.29), (110, 85, 55))
    m.cyl("HatBand", 0.1, 0.78, (0, 2.5, -1.25), (60, 45, 30))
    m.cyl("HatBadge", 0.05, 0.16, (0, 2.6, -1.64), (240, 200, 60), axis="z", mat="Metal")
    # spiral shell: a real spiral of shrinking coils with camo spots
    m.ball("Shell", 2.3, (0, 1.75, 0.45), shell)
    for side in (-1, 1):
        pts = []
        for k in range(16):
            t = k / 15
            a = t * 3.4 * math.pi
            r = 0.95 * (1 - t * 0.85)
            pts.append((side * (math.sqrt(max(1.15 ** 2 - r * r, 0.04)) + 0.03), 1.75 + math.sin(a) * r, 0.45 + math.cos(a) * r))
        m.chain("Spiral", pts, 0.2, band, joints=False)
        m.cyl("ShellCenter", 0.08, 0.3, (side * 1.15, 1.8, 0.4), band, axis="x")
    for (x, y, z) in [(0.3, 2.85, 0.7), (-0.4, 2.7, 0.0), (0.1, 2.5, 1.35), (-0.2, 2.9, 0.95)]:
        m.ell("Camo", (0.4, 0.15, 0.3), (x, y, z), (110, 130, 70), R=rot(x=-20))
    # medals with ribbons on the shell side
    for k, c in enumerate([(240, 200, 60), (200, 60, 60), (60, 120, 220)]):
        m.blk("Ribbon", (0.04, 0.25, 0.16), (-1.1, 1.62, -0.2 + k * 0.35), [(60, 80, 200), (240, 240, 240), (200, 50, 50)][k])
        m.cyl("Medal", 0.06, 0.28, (-1.1, 1.4, -0.2 + k * 0.35), c, axis="x", mat="Metal", refl=0.3)
        m.ell("MedalStar", (0.03, 0.12, 0.12), (-1.14, 1.4, -0.2 + k * 0.35), shade(c, 1.3))
    return m


@model
def big_momma_moose():
    m = Model("big_momma_moose")
    fur = (120, 80, 55)
    dark = (90, 60, 40)
    light = (150, 110, 80)
    antler = (215, 190, 145)
    m.ell("Body", (2.2, 2.0, 3.4), (0, 2.55, 0.35), fur, mat="Fabric")
    m.ell("Belly", (1.7, 1.0, 2.4), (0, 1.95, 0.35), light, mat="Fabric")
    m.ell("Hump", (1.6, 1.0, 1.4), (0, 3.4, -0.2), fur, mat="Fabric")
    m.scatter("Mane", (0, 3.4, -0.2), (1.6, 1.0, 1.4), 9, [dark], seed=4, d=0.35, shape="dot", ymin=0.3, mat="Fabric")
    for s in (-1, 1):
        for sz in (-1, 1):
            z = 0.35 + sz * 1.05
            m.cyl("Leg", 1.8, 0.48, (s * 0.65, 0.95, z), dark)
            m.ball("Knee", 0.55, (s * 0.65, 1.1, z), shade(dark, 1.1), mat="Fabric")
            m.ell("Hoof", (0.58, 0.27, 0.68), (s * 0.65, 0.12, z - 0.05), (50, 40, 35))
            m.blk("Hoof", (0.05, 0.25, 0.3), (s * 0.65, 0.12, z - 0.3), (30, 25, 22))
    # knitted shawl with a fringe around the shoulders
    m.ell("Shawl", (2.35, 0.9, 1.6), (0, 3.05, -0.55), (200, 80, 120), mat="Fabric")
    for k in range(9):
        a = math.radians(-80 + k * 20)
        m.blk("Fringe", (0.08, 0.35, 0.08), (math.sin(a) * 1.15, 2.55, -0.55 - math.cos(a) * 0.78), (255, 210, 120), mat="Fabric")
    for k in range(3):
        m.ring("ShawlStripe", (0, 2.75 + k * 0.22, -0.55), 1.12 - k * 0.12, 0.05, (255, 210, 120), normal="y", segments=14, mat="Fabric", R=rot(x=0))
    m.ell("Neck", (1.0, 1.3, 1.1), (0, 3.2, -1.2), fur, mat="Fabric", R=rot(x=-25))
    m.ell("Head", (1.1, 1.0, 1.8), (0, 3.6, -1.95), fur, mat="Fabric", R=rot(x=10))
    m.ell("Snout", (1.0, 0.85, 0.9), (0, 3.3, -2.65), (140, 100, 75), mat="Fabric")
    m.ell("Lip", (0.85, 0.3, 0.5), (0, 3.0, -2.75), (150, 110, 85), mat="Fabric")
    for s in (-1, 1):
        m.ell("Nostril", (0.15, 0.22, 0.08), (s * 0.22, 3.4, -3.08), (50, 35, 30))
    m.grin(3.08, -3.0, 0.5, curve=0.25, color=(70, 45, 35), bend=0.12)
    m.ell("Dewlap", (0.4, 0.6, 0.35), (0, 2.8, -2.0), fur, mat="Fabric")
    m.eyes(3.95, -2.25, 0.85, 0.32, lid=fur, iris=(110, 70, 40), lash=3, z_back=0.05)
    m.cheeks(3.62, -2.5, 0.95, 0.22)
    for s in (-1, 1):
        m.ell("Ear", (0.27, 0.58, 0.15), (s * 0.55, 4.15, -1.7), fur, R=rot(z=s * -50))
        m.ell("EarInner", (0.15, 0.38, 0.06), (s * 0.55, 4.15, -1.77), (180, 130, 110), R=rot(z=s * -50))
    # huge antlers: palm, base, tines with rounded tips
    for s in (-1, 1):
        m.ell("AntlerPalm", (1.6, 0.2, 0.95), (s * 1.3, 4.6, -1.6), antler, R=rot(z=s * 18))
        m.ell("AntlerPalm", (1.1, 0.12, 0.6), (s * 1.25, 4.7, -1.6), shade(antler, 1.1), R=rot(z=s * 18))
        m.rod("AntlerBase", (s * 0.35, 4.15, -1.65), (s * 0.75, 4.45, -1.6), 0.24, antler)
        m.ball("AntlerBase", 0.32, (s * 0.35, 4.15, -1.65), shade(antler, 0.85))
        for k in range(5):
            x = s * (0.72 + k * 0.34)
            tip = (x + s * 0.12, 5.05 + abs(x) * 0.15, -1.55 - (k % 2) * 0.25)
            m.rod("AntlerTine", (x, 4.55 + abs(x) * 0.1, -1.6), tip, 0.15, (225, 200, 155))
            m.ball("AntlerTine", 0.15, tip, (230, 210, 165))
    # flower crown with leaves
    for k in range(7):
        a = math.pi * (k / 6.0)
        c = [(255, 120, 160), (255, 220, 70), (160, 120, 255), (255, 255, 255)][k % 4]
        p = (math.cos(a) * 0.5, 4.35 + math.sin(a) * 0.08, -1.75 - math.sin(a) * 0.3)
        m.ball("Flower", 0.26, p, c)
        m.ball("Flower", 0.1, (p[0], p[1] + 0.08, p[2] - 0.08), (255, 230, 120))
        m.ell("Leaf", (0.18, 0.05, 0.1), (p[0] + 0.15, p[1] - 0.03, p[2] + 0.05), (90, 170, 80), R=rot(y=k * 25))
    # pearl necklace with a heart locket
    for k in range(11):
        a = math.pi * (0.15 + 0.7 * k / 10)
        m.ball("Pearl", 0.17, (math.cos(a) * 0.62, 2.85 - math.sin(a) * 0.25, -1.45 - math.sin(a) * 0.35), (250, 245, 240), refl=0.35)
    m.ell("Locket", (0.25, 0.25, 0.08), (0, 2.5, -1.85), (240, 200, 80), mat="Metal", refl=0.3)
    m.ell("Tail", (0.3, 0.35, 0.25), (0, 3.0, 2.0), fur)
    return m


@model
def captain_confetti():
    m = Model("captain_confetti")
    red = (230, 40, 50)
    blue = (40, 110, 230)
    green = (60, 200, 120)
    gold = (240, 200, 60)
    # parrot body with chest feathers
    m.ell("Body", (1.5, 2.1, 1.5), (0, 1.85, 0.1), red)
    m.ell("Belly", (1.0, 1.4, 0.5), (0, 1.7, -0.5), (255, 200, 60))
    for k in range(3):
        for j in range(3 - k % 2):
            m.ell("ChestFeather", (0.32, 0.22, 0.1), (-0.25 + j * 0.25 + (k % 2) * 0.12, 2.15 - k * 0.3, -0.72 + k * 0.03), (255, 220, 100))
    # captain's coat over the shoulders with gold buttons and braid
    m.ell("Coat", (1.6, 1.0, 1.55), (0, 2.45, 0.15), (40, 50, 110), mat="Fabric")
    m.ell("Collar", (1.3, 0.3, 1.2), (0, 2.75, 0.05), gold, mat="Fabric")
    for k in range(3):
        m.ball("Button", 0.1, (0.42, 2.35 - k * 0.2, -0.6), gold, mat="Metal")
        m.ball("Button", 0.1, (-0.42, 2.35 - k * 0.2, -0.6), gold, mat="Metal")
    m.ball("Head", 1.35, (0, 3.2, -0.15), red)
    m.ell("FacePatch", (0.9, 0.8, 0.4), (0, 3.2, -0.65), (255, 245, 235))
    for k in range(3):
        m.ell("Freckle", (0.08, 0.05, 0.03), (-0.2 + k * 0.1, 3.0 + (k % 2) * 0.05, -0.84), (220, 200, 200))
    # hooked beak, upper and lower
    m.ell("Beak", (0.45, 0.55, 0.55), (0, 2.95, -0.9), (60, 60, 70), R=rot(x=20))
    m.ell("BeakTip", (0.3, 0.3, 0.3), (0, 2.72, -0.95), (60, 60, 70))
    m.ell("Beak", (0.36, 0.2, 0.35), (0, 2.75, -0.78), (90, 90, 100))
    m.ell("Nostril", (0.06, 0.04, 0.03), (0.1, 3.15, -1.05), (30, 30, 35))
    m.eyes(3.35, -0.78, 0.5, 0.3, lid=(255, 245, 235), iris=(250, 200, 50), z_back=0.03)
    m.blk("EyePatchStrap", (1.4, 0.1, 0.1), (0, 3.55, -0.5), (20, 20, 25), R=rot(z=-20))
    m.cyl("EyePatch", 0.08, 0.36, (0.25, 3.36, -0.82), (20, 20, 25), axis="z")
    m.brow(-0.25, 3.62, -0.78, 0.28, (20, 20, 25), -1, tilt=-10)
    for s in (-1, 1):
        # layered wings: blue coverts, green flight feathers, red tips
        m.ell("Wing", (0.35, 1.6, 1.0), (s * 0.85, 1.85, 0.25), blue, R=rot(z=s * 10))
        for k in range(4):
            m.ell("Wing", (0.2, 0.55, 0.32), (s * 0.95, 1.95 - k * 0.22, -0.1 + k * 0.22), shade(blue, 1.15 if k % 2 else 0.9), R=rot(z=s * 10, x=-20))
        m.ell("WingTip", (0.3, 0.9, 0.7), (s * 0.95, 1.1, 0.5), green, R=rot(z=s * 10))
        m.ell("WingTip", (0.2, 0.35, 0.4), (s * 0.98, 0.72, 0.62), (255, 210, 60), R=rot(z=s * 10))
        m.cyl("Leg", 0.6, 0.18, (s * 0.35, 0.45, 0), (90, 90, 100))
        for t in (-1, 0, 1):
            m.ell("Toe", (0.1, 0.1, 0.3), (s * 0.35 + t * 0.1, 0.08, -0.2), (90, 90, 100), R=rot(y=t * 20))
    m.ell("Tail", (0.9, 0.2, 1.6), (0, 1.0, 1.0), blue, R=rot(x=40))
    m.ell("Tail2", (0.6, 0.2, 1.3), (0, 0.8, 1.2), green, R=rot(x=50))
    m.ell("Tail", (0.35, 0.18, 1.0), (0, 0.65, 1.45), red, R=rot(x=55))
    # captain's tricorn hat with gold trim, a star badge and a big plume
    m.cyl("Hat", 0.45, 1.4, (0, 3.95, -0.1), (30, 30, 40))
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        m.ell("HatCorner", (1.2, 0.32, 0.5), (math.cos(a) * 0.45, 3.85, -0.1 - math.sin(a) * 0.45), (30, 30, 40), R=rot(y=-math.degrees(a)))
        m.ell("HatTrim", (1.22, 0.08, 0.1), (math.cos(a) * 0.62, 3.97, -0.1 - math.sin(a) * 0.62), gold, R=rot(y=-math.degrees(a)), mat="Metal")
    m.cyl("HatTrim", 0.1, 1.45, (0, 3.75, -0.1), gold, mat="Metal")
    star = m.ell("HatStar", (0.35, 0.35, 0.1), (0, 4.0, -0.82), (255, 230, 80), mat="Neon")
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 2
        m.wedge("HatStar", (0.06, 0.16, 0.08), (math.cos(a) * 0.2, 4.0 + math.sin(a) * 0.2, -0.84), (255, 230, 80), mat="Neon", R=rot(z=math.degrees(a) - 90))
    feather = m.ell("Feather", (0.2, 1.0, 0.2), (0.45, 4.45, 0.1), (255, 90, 200), R=rot(z=-30))
    m.ell("HatFeather", (0.14, 0.7, 0.14), (0.62, 4.35, 0.2), (120, 220, 255), R=rot(z=-45))
    m.confetti(star)
    m.sparkles(feather, (255, 200, 255))
    # brass spyglass with bands
    m.rod("Spyglass", (0.85, 2.0, -0.4), (1.25, 2.6, -1.0), 0.22, (200, 160, 70), mat="Metal")
    m.rod("SpyglassBand", (1.0, 2.22, -0.62), (1.06, 2.32, -0.72), 0.26, (130, 90, 40), mat="Metal")
    m.rod("SpyglassBand", (1.18, 2.5, -0.9), (1.23, 2.57, -0.97), 0.28, (230, 200, 110), mat="Metal")
    m.cyl("SpyglassLens", 0.1, 0.3, (1.27, 2.63, -1.03), (150, 220, 255), mat="Glass", axis="z")
    return m
