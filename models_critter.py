# Critter family models (cute animals)
import math
from modelkit import Model, rot, WHITE, PUPIL

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


@model
def pocket_mouse():
    m = Model("pocket_mouse")
    denim = (60, 95, 160)
    gray = (165, 165, 175)
    # jeans pocket
    m.blk("Pocket", (2.2, 1.4, 0.9), (0, 0.7, 0.1), denim, mat="Fabric")
    m.blk("PocketLip", (2.25, 0.18, 0.95), (0, 1.38, 0.1), (75, 115, 185), mat="Fabric")
    for x in (-0.95, 0.95):
        m.blk("Stitch", (0.05, 1.2, 0.02), (x, 0.7, -0.36), (240, 190, 90))
        m.cyl("Rivet", 0.06, 0.16, (x, 1.3, -0.38), (200, 160, 70), axis="z", mat="Metal")
    m.blk("Stitch", (1.95, 0.05, 0.02), (0, 0.15, -0.36), (240, 190, 90))
    # mouse peeking out
    m.ell("Body", (1.0, 1.0, 0.8), (0, 1.55, 0.15), gray)
    m.ell("Head", (1.15, 1.0, 1.0), (0, 2.2, -0.05), gray)
    for s in (-1, 1):
        m.cyl("Ear", 0.12, 0.85, (s * 0.55, 2.75, 0.05), gray, axis="z")
        m.cyl("EarInner", 0.13, 0.6, (s * 0.55, 2.75, 0.0), (250, 170, 185), axis="z")
        m.ball("Paw", 0.3, (s * 0.35, 1.45, -0.32), (240, 175, 190))
        for k in (-1, 1):
            m.blk("Whisker", (0.6, 0.03, 0.03), (s * 0.45, 2.05 + k * 0.06, -0.5), (60, 60, 60), R=rot(z=s * k * 10))
    m.eyes(2.32, -0.48, 0.42, 0.3, lid=gray)
    m.ball("Nose", 0.2, (0, 2.05, -0.58), (240, 120, 150))
    m.ell("Mouth", (0.18, 0.08, 0.05), (0, 1.88, -0.52), (90, 50, 60))
    m.chain("Tail", [(0.9, 1.0, 0.3), (1.25, 1.3, 0.35), (1.3, 1.7, 0.25), (1.1, 1.95, 0.2)], 0.08, (240, 175, 190), joints=False)
    # a crumb snack
    m.blk("Cheese", (0.35, 0.3, 0.3), (-0.6, 1.5, -0.45), (255, 210, 70), R=rot(y=30))
    return m


@model
def moth_mailman():
    m = Model("moth_mailman")
    fuzz = (230, 215, 180)
    wing = (210, 190, 150)
    m.ell("Body", (0.9, 1.5, 0.9), (0, 1.55, 0.1), fuzz, mat="Fabric")
    m.ell("Head", (0.95, 0.85, 0.85), (0, 2.55, -0.1), fuzz, mat="Fabric")
    m.ell("Ruff", (1.2, 0.4, 1.1), (0, 2.15, 0.0), (250, 245, 235), mat="Fabric")
    for s in (-1, 1):
        m.ell("Wing", (1.6, 1.5, 0.12), (s * 1.0, 2.0, 0.45), wing, R=rot(y=s * 25, z=s * -10))
        m.ell("WingLow", (1.0, 0.9, 0.1), (s * 0.75, 1.25, 0.5), wing, R=rot(y=s * 25, z=s * 20))
        m.ell("WingSpot", (0.45, 0.45, 0.14), (s * 1.15, 2.1, 0.38), (120, 90, 160), R=rot(y=s * 25))
        m.rod("Antenna", (s * 0.18, 2.9, -0.2), (s * 0.55, 3.45, -0.35), 0.06, (120, 100, 80))
        m.ell("AntennaTip", (0.25, 0.4, 0.12), (s * 0.58, 3.5, -0.37), (150, 125, 95), R=rot(z=s * 30))
    m.eyes(2.58, -0.45, 0.4, 0.34, lid=fuzz, pupil=(40, 30, 60), pupil_scale=0.7)
    m.smile(2.3, -0.5, 0.2)
    # mail cap
    m.cyl("Cap", 0.35, 0.8, (0, 3.0, -0.05), (50, 80, 160))
    m.blk("CapBill", (0.7, 0.08, 0.45), (0, 2.85, -0.5), (40, 65, 140))
    m.cyl("CapBadge", 0.05, 0.18, (0, 3.02, -0.42), (240, 200, 60), axis="z", mat="Metal")
    # mail bag with letters
    m.rod("Strap", (-0.45, 2.2, -0.35), (0.5, 1.2, -0.45), 0.08, (110, 70, 40))
    m.blk("Bag", (0.75, 0.6, 0.35), (0.55, 1.1, -0.5), (140, 95, 55), mat="Leather")
    m.blk("Letter", (0.5, 0.35, 0.04), (0.5, 1.45, -0.55), (250, 250, 245), R=rot(z=10))
    m.blk("Stamp", (0.12, 0.12, 0.02), (0.65, 1.5, -0.58), (220, 60, 60))
    # little legs, hovering pose
    for s in (-1, 1):
        m.rod("Leg", (s * 0.25, 0.9, 0.05), (s * 0.35, 0.3, -0.05), 0.12, (120, 100, 80))
        m.ell("Foot", (0.25, 0.14, 0.35), (s * 0.36, 0.25, -0.12), (120, 100, 80))
    m.cyl("Stand", 0.06, 1.2, (0, 0.03, 0), (180, 170, 150), tr=0.5)
    return m


@model
def pillow_bunny():
    m = Model("pillow_bunny")
    pil = (215, 200, 245)
    m.ell("Body", (2.1, 1.9, 1.1), (0, 1.15, 0), pil, mat="Fabric")
    for (x, y) in [(-1.0, 0.25), (1.0, 0.25), (-1.0, 2.05), (1.0, 2.05)]:
        m.ell("Corner", (0.45, 0.45, 0.35), (x, y, 0), pil, mat="Fabric")
    m.blk("Seam", (2.0, 0.05, 1.12), (0, 1.15, 0), (190, 170, 225), mat="Fabric")
    m.blk("Tag", (0.25, 0.35, 0.03), (0.75, 0.55, -0.52), (255, 255, 255))
    for s in (-1, 1):
        m.ell("Ear", (0.45, 1.5, 0.3), (s * 0.45, 2.6, 0.05), pil, mat="Fabric", R=rot(z=s * -18, x=10))
        m.ell("EarInner", (0.28, 1.15, 0.1), (s * 0.43, 2.55, -0.08), (255, 185, 210), R=rot(z=s * -18, x=10))
    m.eyes(1.5, -0.52, 0.65, 0.34, lid=pil, sleepy=True)
    m.ell("Nose", (0.22, 0.16, 0.12), (0, 1.25, -0.56), (250, 140, 170))
    m.smile(1.05, -0.55, 0.3)
    m.cheeks(1.15, -0.52, 1.1, 0.3)
    for s in (-1, 1):
        m.ball("Paw", 0.45, (s * 0.85, 0.85, -0.45), (240, 230, 255), mat="Fabric")
        m.ell("Foot", (0.55, 0.3, 0.75), (s * 0.55, 0.15, -0.35), (240, 230, 255), mat="Fabric")
    m.ball("Tail", 0.5, (0, 0.8, 0.6), (255, 255, 255), mat="Fabric")
    # floating feathers
    for (x, y, z, a) in [(-1.3, 2.3, -0.3, 30), (1.35, 1.9, 0.2, -40), (0.9, 2.9, -0.4, 60)]:
        m.ell("Feather", (0.12, 0.45, 0.06), (x, y, z), (255, 255, 255), R=rot(z=a))
    return m


@model
def hamster_wheel_hero():
    m = Model("hamster_wheel_hero")
    fur = (235, 165, 90)
    # wheel standing on a base, wheel plane = YZ so the hamster runs toward -Z
    m.blk("Base", (2.6, 0.2, 2.8), (0, 0.1, 0), (90, 130, 200))
    for s in (-1, 1):
        m.rod("Stand", (s * 1.15, 0.2, -0.8), (s * 1.15, 1.6, 0), 0.14, (200, 200, 210), mat="Metal")
        m.rod("Stand", (s * 1.15, 0.2, 0.8), (s * 1.15, 1.6, 0), 0.14, (200, 200, 210), mat="Metal")
        m.ring("Wheel", (s * 0.95, 1.6, 0), 1.35, 0.12, (220, 60, 60), normal="x", segments=14, mat="Metal")
    m.cyl("Axle", 2.4, 0.16, (0, 1.6, 0), (200, 200, 210), axis="x", mat="Metal")
    for k in range(12):
        a = k * 2 * math.pi / 12
        m.cyl("Rung", 1.9, 0.08, (0, 1.6 + math.sin(a) * 1.35, math.cos(a) * 1.35), (230, 230, 235), axis="x", mat="Metal")
    # hamster running inside
    m.ell("Body", (1.0, 0.95, 1.3), (0, 0.85, -0.05), fur, R=rot(x=-15))
    m.ell("Belly", (0.75, 0.6, 0.8), (0, 0.72, -0.25), (255, 240, 220))
    m.ell("Head", (0.85, 0.8, 0.8), (0, 1.35, -0.6), fur)
    for s in (-1, 1):
        m.ell("Cheek", (0.35, 0.35, 0.35), (s * 0.35, 1.22, -0.75), (255, 235, 210))
        m.ell("Ear", (0.25, 0.3, 0.1), (s * 0.3, 1.75, -0.5), (240, 150, 140))
        m.rod("Leg", (s * 0.25, 0.6, 0.1), (s * 0.25, 0.32, 0.45 if s > 0 else -0.3), 0.14, (240, 150, 140))
    m.blk("Mask", (0.86, 0.18, 0.1), (0, 1.47, -0.97), (30, 30, 40))
    m.eyes(1.47, -1.0, 0.36, 0.2, lid=None)
    m.ball("Nose", 0.12, (0, 1.28, -1.02), (240, 120, 130))
    # cape flowing back
    m.blk("Cape", (0.9, 0.08, 1.4), (0, 1.25, 0.55), (220, 30, 40), mat="Fabric", R=rot(x=-20))
    m.blk("CapeTie", (0.8, 0.12, 0.12), (0, 1.12, -0.25), (250, 210, 60))
    return m


def pigeon_body(m, x, z, scale=1.0, helmet=True, yaw=0.0):
    s = scale
    gray = (150, 155, 170)
    cx, cz = x, z
    R = rot(y=yaw)
    m.ell("Body", (0.85 * s, 0.85 * s, 1.2 * s), (cx, 0.75 * s, cz + 0.1 * s), gray, R=rot(x=-10, y=yaw))
    m.ell("Neck", (0.6 * s, 0.5 * s, 0.6 * s), (cx, 1.15 * s, cz - 0.2 * s), (110, 160, 140), refl=0.2)
    m.ball("Head", 0.6 * s, (cx, 1.5 * s, cz - 0.3 * s), gray)
    m.ell("Beak", (0.14 * s, 0.12 * s, 0.3 * s), (cx, 1.45 * s, cz - 0.65 * s), (240, 170, 60))
    for k in (-1, 1):
        m.ell("Wing", (0.15 * s, 0.6 * s, 0.9 * s), (cx + k * 0.42 * s, 0.8 * s, cz + 0.15 * s), (120, 125, 145), R=rot(x=-15))
        m.cyl("Leg", 0.35 * s, 0.08 * s, (cx + k * 0.18 * s, 0.2 * s, cz), (240, 130, 140))
        m.ell("Foot", (0.22 * s, 0.06 * s, 0.3 * s), (cx + k * 0.18 * s, 0.04 * s, cz - 0.1 * s), (240, 130, 140))
    m.ell("Tail", (0.5 * s, 0.12 * s, 0.6 * s), (cx, 0.75 * s, cz + 0.8 * s), (110, 115, 135), R=rot(x=20))
    m.eyes(1.58 * s, cz - 0.55 * s, 0.32 * s, 0.17 * s, x=cx, lid=gray, pupil=(200, 80, 40), pupil_scale=0.45)
    if helmet:
        m.ell("Helmet", (0.75 * s, 0.4 * s, 0.75 * s), (cx, 1.75 * s, cz - 0.28 * s), (80, 110, 60))
        m.blk("HelmetStrap", (0.05 * s, 0.35 * s, 0.05 * s), (cx + 0.3 * s, 1.55 * s, cz - 0.42 * s), (60, 80, 45))


@model
def pigeon_squad():
    m = Model("pigeon_squad")
    pigeon_body(m, 0.0, -0.75, 1.15)
    pigeon_body(m, -1.05, 0.55, 1.0)
    pigeon_body(m, 1.05, 0.55, 1.0)
    # sergeant stripes on the leader and a tiny flag
    m.blk("Stripe", (0.06, 0.2, 0.3), (0.5, 1.0, -0.6), (250, 210, 60))
    m.cyl("FlagPole", 1.6, 0.06, (1.6, 1.0, 0.6), (200, 200, 210), mat="Metal")
    m.blk("Flag", (0.6, 0.4, 0.04), (1.92, 1.6, 0.6), (220, 60, 60), mat="Fabric")
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
    # foot / body
    m.ell("Foot", (1.3, 0.6, 3.0), (0, 0.3, 0), slime, refl=0.2)
    m.ell("Neck", (0.9, 1.6, 0.9), (0, 1.1, -1.05), slime, refl=0.2, R=rot(x=-12))
    m.ell("Head", (1.0, 0.9, 0.95), (0, 1.95, -1.25), slime, refl=0.2)
    for s in (-1, 1):
        m.rod("Stalk", (s * 0.2, 2.25, -1.25), (s * 0.45, 3.05, -1.35), 0.14, slime)
        m.ball("Eyeball", 0.42, (s * 0.47, 3.12, -1.37), WHITE)
        m.ball("Pupil", 0.2, (s * 0.47, 3.12, -1.56), PUPIL)
        m.ball("Lid", 0.46, (s * 0.47, 3.12, -1.37), slime, tr=1)
    m.ell("Mustache", (0.9, 0.18, 0.25), (0, 1.75, -1.7), (90, 70, 50), mat="Fabric")
    m.ell("Mouth", (0.35, 0.08, 0.1), (0, 1.6, -1.7), (80, 70, 50))
    # drill sergeant hat
    m.cyl("HatBrim", 0.08, 1.35, (0, 2.42, -1.25), (120, 95, 60))
    m.cyl("HatCrown", 0.45, 0.75, (0, 2.65, -1.25), (130, 105, 65))
    m.cyl("HatBand", 0.1, 0.78, (0, 2.5, -1.25), (60, 45, 30))
    # spiral shell
    m.ball("Shell", 2.3, (0, 1.75, 0.45), shell)
    m.ring("Spiral", (0, 1.75, 0.45), 0.85, 0.22, (150, 90, 50), normal="x", segments=12)
    m.ring("Spiral", (0, 1.8, 0.4), 0.45, 0.2, (150, 90, 50), normal="x", segments=10)
    for s in (-1, 1):
        m.cyl("ShellCenter", 0.08, 0.3, (s * 1.15, 1.8, 0.4), (150, 90, 50), axis="x")
    # medals
    for k, c in enumerate([(240, 200, 60), (200, 60, 60), (60, 120, 220)]):
        m.cyl("Medal", 0.06, 0.28, (-1.08, 1.4 - k * 0.0, -0.2 + k * 0.35), c, axis="x", mat="Metal")
        m.blk("Ribbon", (0.04, 0.25, 0.14), (-1.1, 1.62, -0.2 + k * 0.35), (60, 80, 200))
    return m


@model
def big_momma_moose():
    m = Model("big_momma_moose")
    fur = (120, 80, 55)
    dark = (90, 60, 40)
    m.ell("Body", (2.2, 2.0, 3.4), (0, 2.55, 0.35), fur, mat="Fabric")
    m.ell("Hump", (1.6, 1.0, 1.4), (0, 3.4, -0.2), fur, mat="Fabric")
    for s in (-1, 1):
        for sz in (-1, 1):
            m.cyl("Leg", 1.8, 0.48, (s * 0.65, 0.95, 0.35 + sz * 1.05), dark)
            m.ell("Hoof", (0.55, 0.25, 0.65), (s * 0.65, 0.12, 0.3 + sz * 1.05), (50, 40, 35))
    m.ell("Neck", (1.0, 1.3, 1.1), (0, 3.2, -1.2), fur, mat="Fabric", R=rot(x=-25))
    m.ell("Head", (1.1, 1.0, 1.8), (0, 3.6, -1.95), fur, mat="Fabric", R=rot(x=10))
    m.ell("Snout", (1.0, 0.85, 0.9), (0, 3.3, -2.65), (140, 100, 75), mat="Fabric")
    for s in (-1, 1):
        m.ell("Nostril", (0.14, 0.2, 0.08), (s * 0.22, 3.4, -3.08), (50, 35, 30))
    m.ell("Dewlap", (0.4, 0.6, 0.35), (0, 2.8, -2.0), fur, mat="Fabric")
    m.eyes(3.95, -2.25, 0.85, 0.32, lid=fur)
    for s in (-1, 1):
        m.ell("Lash", (0.06, 0.15, 0.04), (s * 0.58, 4.12, -2.38), PUPIL, R=rot(z=s * -30))
        m.ell("Ear", (0.25, 0.55, 0.15), (s * 0.55, 4.15, -1.7), fur, R=rot(z=s * -50))
    # huge antlers
    for s in (-1, 1):
        m.ell("AntlerPalm", (1.6, 0.18, 0.9), (s * 1.3, 4.6, -1.6), (210, 185, 140), R=rot(z=s * 18))
        m.rod("AntlerBase", (s * 0.35, 4.15, -1.65), (s * 0.75, 4.45, -1.6), 0.22, (210, 185, 140))
        for k in range(4):
            x = s * (0.75 + k * 0.42)
            m.rod("AntlerTine", (x, 4.55 + abs(x) * 0.1, -1.6), (x + s * 0.12, 5.05 + abs(x) * 0.15, -1.55 - (k % 2) * 0.25), 0.14, (220, 195, 150))
    # flower crown
    for k in range(7):
        a = math.pi * (k / 6.0)
        c = [(255, 120, 160), (255, 220, 70), (160, 120, 255), (255, 255, 255)][k % 4]
        m.ball("Flower", 0.26, (math.cos(a) * 0.5, 4.35 + math.sin(a) * 0.08, -1.75 - math.sin(a) * 0.3), c)
    # pearl necklace
    for k in range(9):
        a = math.pi * (0.15 + 0.7 * k / 8)
        m.ball("Pearl", 0.18, (math.cos(a) * 0.62, 2.85 - math.sin(a) * 0.25, -1.45 - math.sin(a) * 0.35), (250, 245, 240), refl=0.3)
    m.ell("Tail", (0.3, 0.35, 0.25), (0, 3.0, 2.0), fur)
    return m


@model
def captain_confetti():
    m = Model("captain_confetti")
    red = (230, 40, 50)
    # parrot body
    m.ell("Body", (1.5, 2.1, 1.5), (0, 1.85, 0.1), red)
    m.ell("Belly", (1.0, 1.4, 0.5), (0, 1.7, -0.5), (255, 200, 60))
    m.ball("Head", 1.35, (0, 3.2, -0.15), red)
    m.ell("FacePatch", (0.9, 0.8, 0.4), (0, 3.2, -0.65), (255, 245, 235))
    m.ell("Beak", (0.45, 0.55, 0.55), (0, 2.95, -0.9), (60, 60, 70), R=rot(x=20))
    m.ell("BeakTip", (0.3, 0.3, 0.3), (0, 2.72, -0.95), (60, 60, 70))
    m.eyes(3.35, -0.78, 0.5, 0.3, lid=(255, 245, 235))
    m.blk("EyePatchStrap", (1.4, 0.1, 0.1), (0, 3.55, -0.5), (20, 20, 25), R=rot(z=-20))
    m.cyl("EyePatch", 0.08, 0.36, (0.25, 3.36, -0.82), (20, 20, 25), axis="z")
    for s in (-1, 1):
        m.ell("Wing", (0.35, 1.6, 1.0), (s * 0.85, 1.85, 0.25), (40, 110, 230), R=rot(z=s * 10))
        m.ell("WingTip", (0.3, 0.9, 0.7), (s * 0.95, 1.1, 0.5), (60, 200, 120), R=rot(z=s * 10))
        m.cyl("Leg", 0.6, 0.18, (s * 0.35, 0.45, 0), (90, 90, 100))
        m.ell("Foot", (0.35, 0.15, 0.55), (s * 0.35, 0.1, -0.15), (90, 90, 100))
    m.ell("Tail", (0.9, 0.2, 1.6), (0, 1.0, 1.0), (40, 110, 230), R=rot(x=40))
    m.ell("Tail2", (0.6, 0.2, 1.3), (0, 0.8, 1.2), (60, 200, 120), R=rot(x=50))
    # captain's tricorn hat
    m.cyl("Hat", 0.45, 1.4, (0, 3.95, -0.1), (30, 30, 40))
    for k in range(3):
        a = k * 2 * math.pi / 3 + math.pi / 2
        m.ell("HatCorner", (1.2, 0.32, 0.5), (math.cos(a) * 0.45, 3.85, -0.1 - math.sin(a) * 0.45), (30, 30, 40), R=rot(y=-math.degrees(a)))
    m.cyl("HatTrim", 0.1, 1.45, (0, 3.75, -0.1), (240, 200, 60), mat="Metal")
    star = m.ell("HatStar", (0.35, 0.35, 0.1), (0, 4.0, -0.82), (255, 230, 80), mat="Neon")
    feather = m.ell("Feather", (0.18, 1.0, 0.18), (0.45, 4.45, 0.1), (255, 90, 200), R=rot(z=-30))
    m.confetti(star)
    m.sparkles(feather, (255, 200, 255))
    # spyglass
    m.rod("Spyglass", (0.85, 2.0, -0.4), (1.25, 2.6, -1.0), 0.22, (200, 160, 70), mat="Metal")
    m.cyl("SpyglassLens", 0.1, 0.3, (1.27, 2.63, -1.03), (150, 220, 255), mat="Glass", axis="z")
    return m
