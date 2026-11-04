# Spooky family models (friendly ghosts, haunted stuff, purple and ghost-green glows)
import math
from modelkit import Model, rot, Rx, Ry, Rz, WHITE, PUPIL, shade

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


def sheet_ghost_body(m, scale=1.0, tr=0.08, color=(245, 245, 255), lift=0.35):
    s = scale
    y0 = lift
    fold = shade(color, 0.9)
    m.ell("Body", (1.6 * s, 2.3 * s, 1.5 * s), (0, y0 + 1.35 * s, 0), color, tr=tr)
    m.ell("Skirt", (1.95 * s, 0.9 * s, 1.85 * s), (0, y0 + 0.42 * s, 0), color, tr=tr)
    # wavy hem with alternating long and short lobes
    for k in range(10):
        a = k * 2 * math.pi / 10 + 0.2
        long_ = k % 2 == 0
        m.ell("Hem", (0.5 * s, (0.5 if long_ else 0.36) * s, 0.5 * s), (math.cos(a) * 0.8 * s, y0 + (0.02 if long_ else 0.12) * s, math.sin(a) * 0.77 * s), color, tr=tr)
    # soft cloth folds on the skirt
    for k, a in enumerate((-55, -20, 20, 55, 150, 210)):
        r = math.radians(a)
        m.ell("Fold", (0.18 * s, 0.5 * s, 0.14 * s), (math.sin(r) * 0.86 * s, y0 + 0.4 * s, -math.cos(r) * 0.82 * s), fold, tr=tr, R=rot(y=-a))
    # eye holes with a soft glow deep inside, and a little open mouth
    for k in (-1, 1):
        m.ell("Hole", (0.32 * s, 0.48 * s, 0.12 * s), (k * 0.3 * s, y0 + 1.85 * s, -0.66 * s), (30, 25, 40))
        m.ell("Pupil", (0.12 * s, 0.14 * s, 0.05 * s), (k * 0.3 * s + 0.03 * s, y0 + 1.8 * s, -0.71 * s), (200, 180, 255), mat="Neon")
        m.ell("Glint", (0.06 * s, 0.06 * s, 0.03 * s), (k * 0.3 * s + 0.08 * s, y0 + 1.96 * s, -0.71 * s), WHITE)
        m.ell("Arm", (0.38 * s, 0.75 * s, 0.38 * s), (k * 0.85 * s, y0 + 1.1 * s, -0.15 * s), color, tr=tr, R=rot(z=k * 40))
        m.ell("Hand", (0.3 * s, 0.22 * s, 0.3 * s), (k * 1.12 * s, y0 + 0.82 * s, -0.18 * s), color, tr=tr, R=rot(z=k * 40))
    m.ell("Mouth", (0.32 * s, 0.24 * s, 0.1 * s), (0, y0 + 1.42 * s, -0.7 * s), (30, 25, 40))
    m.ell("Tongue", (0.16 * s, 0.08 * s, 0.06 * s), (0, y0 + 1.35 * s, -0.73 * s), (240, 120, 160))
    m.cheeks(y0 + 1.55 * s, -0.66 * s, 1.0 * s, 0.24 * s)
    # a laundry tag and a patched corner
    m.blk("Tag", (0.18 * s, 0.24 * s, 0.03 * s), (0.62 * s, y0 + 0.62 * s, -0.66 * s), (250, 250, 250), R=rot(y=-30))
    m.blk("TagLine", (0.12 * s, 0.03 * s, max(0.02 * s, 0.02)), (0.62 * s, y0 + 0.66 * s, -0.68 * s), (120, 140, 220), R=rot(y=-30))


@model
def sheet_ghost():
    m = Model("sheet_ghost")
    sheet_ghost_body(m, 1.0)
    glow = m.ball("Glow", 0.2, (0, 2.0, 0), (200, 180, 255), tr=1)
    m.light(glow, (190, 170, 255), 1.0, 7)
    m.cyl("Shadow", 0.04, 1.4, (0, 0.02, 0), (40, 30, 60), tr=0.5)
    for (x, y, z, d) in [(-1.1, 2.6, 0.3, 0.25), (1.05, 2.3, 0.4, 0.2), (0.8, 3.0, -0.2, 0.15)]:
        m.ball("Wisp", d, (x, y, z), (220, 210, 255), tr=0.5)
    return m


@model
def ghost_token():
    m = Model("ghost", kind="token")
    sheet_ghost_body(m, 0.85, tr=0.35, color=(220, 230, 255), lift=0.5)
    glow = m.ball("Glow", 0.2, (0, 1.8, 0), (200, 220, 255), tr=1)
    m.light(glow, (170, 200, 255), 0.8, 6)
    return m


@model
def skeleton_mascot():
    m = Model("skeleton_mascot")
    bone = (240, 235, 220)
    shadow = (200, 192, 175)
    orange = (240, 120, 30)
    purple = (60, 40, 90)
    # skull with a dome, cheekbones and a big grin
    m.ball("Skull", 1.15, (0, 3.0, 0), bone)
    m.ell("Skull", (1.05, 0.5, 1.0), (0, 3.38, 0.05), shade(bone, 1.05))
    for s in (-1, 1):
        m.ell("Cheek", (0.3, 0.22, 0.25), (s * 0.36, 2.78, -0.4), shade(bone, 1.05))
        m.ell("Socket", (0.36, 0.4, 0.15), (s * 0.24, 3.05, -0.52), (40, 30, 50))
        m.ball("SocketGlow", 0.13, (s * 0.24, 3.05, -0.58), (190, 120, 255), mat="Neon")
        m.ball("Glint", 0.05, (s * 0.24 + 0.04, 3.1, -0.64), WHITE)
    m.ell("NoseHole", (0.13, 0.16, 0.08), (0, 2.82, -0.56), (40, 30, 50))
    m.ell("Jaw", (0.82, 0.36, 0.72), (0, 2.45, -0.1), bone)
    m.ell("Mouth", (0.62, 0.14, 0.1), (0, 2.6, -0.46), (40, 30, 50))
    for k in range(6):
        x = -0.25 + k * 0.1
        m.blk("Tooth", (0.08, 0.11, 0.06), (x, 2.65, -0.49 + abs(x) * 0.25), WHITE)
        m.blk("Tooth", (0.08, 0.09, 0.06), (x, 2.54, -0.48 + abs(x) * 0.25), WHITE)
    # cheer headband with a bow
    m.ring("Headband", (0, 3.25, 0), 0.56, 0.08, orange, normal="y", segments=14, R=rot(x=-15))
    for s in (-1, 1):
        m.ell("Bow", (0.3, 0.2, 0.08), (s * 0.18, 3.55, 0.45), orange, R=rot(x=-15, z=s * 20))
    # jersey torso with a big number, collar trim and pleated skirt
    m.rbox("Jersey", (1.2, 1.1, 0.7), (0, 1.85, 0), orange, 0.12, mat="Fabric")
    m.blk("JerseyStripe", (1.22, 0.16, 0.72), (0, 2.2, 0), purple, mat="Fabric")
    m.wedge("Collar", (0.5, 0.25, 0.04), (0, 2.27, -0.37), purple, R=rot(z=180))
    # number 13 made of blocks
    # (the model's -X side is the viewer's right)
    m.blk("Number", (0.08, 0.42, 0.03), (0.17, 1.75, -0.37), WHITE)
    for y in (1.94, 1.75, 1.56):
        m.blk("Number", (0.2, 0.07, 0.03), (-0.12, y, -0.37), WHITE)
    m.blk("Number", (0.07, 0.42, 0.03), (-0.2, 1.75, -0.37), WHITE)
    m.cyl("Spine", 0.5, 0.18, (0, 1.1, 0), bone)
    m.ell("Pelvis", (0.8, 0.35, 0.5), (0, 0.85, 0), bone)
    for k in range(10):
        a = k * 2 * math.pi / 10
        m.wedge("Skirt", (0.3, 0.38, 0.12), (math.sin(a) * 0.48, 1.1, -math.cos(a) * 0.36), purple if k % 2 else orange, mat="Fabric", R=rot(y=-math.degrees(a)) @ rot(x=-12))
    m.cyl("Skirt", 0.12, 0.95, (0, 1.28, 0), purple, mat="Fabric")
    for s in (-1, 1):
        # legs with knee joints and cheer sneakers
        m.rod("Leg", (s * 0.25, 0.8, 0), (s * 0.3, 0.25, -0.05), 0.14, bone)
        m.ball("Knee", 0.2, (s * 0.28, 0.5, -0.03), bone)
        m.cyl("Sock", 0.16, 0.2, (s * 0.3, 0.3, -0.05), WHITE, mat="Fabric")
        m.shoe(s * 0.3, -0.15, 0.36, 0.56, (245, 245, 250), sole=purple, toe=WHITE, lace=orange)
        # arms up with pom-poms, finger bones peeking out
        m.rod("Arm", (s * 0.65, 2.25, 0), (s * 1.0, 2.85, -0.2), 0.13, bone)
        m.ball("Elbow", 0.18, (s * 1.0, 2.85, -0.2), bone)
        m.rod("Arm", (s * 1.0, 2.85, -0.2), (s * 1.15, 3.45, -0.3), 0.12, bone)
        m.ball("Shoulder", 0.24, (s * 0.65, 2.25, 0), bone)
        col = (170, 80, 230) if s < 0 else (255, 140, 40)
        m.ball("PomPom", 0.75, (s * 1.18, 3.65, -0.32), col, mat="Foil")
        m.scatter("PomPom", (s * 1.18, 3.65, -0.32), (0.75, 0.75, 0.75), 10, [shade(col, 1.2), shade(col, 0.85)], seed=30 + s, d=0.09, shape="sprinkle", length=3.0, ymin=-0.8, mat="Foil")
        for k in (-1, 0, 1):
            m.rod("Finger", (s * 1.13 + k * 0.06, 3.38, -0.38), (s * 1.15 + k * 0.08, 3.28, -0.5), 0.05, bone)
    # ribs peeking from the collar
    for k in range(3):
        m.blk("Rib", (0.5 - k * 0.08, 0.06, 0.05), (0, 2.38 - k * 0.1, -0.36), bone)
    m.ell("Rib", (0.12, 0.12, 0.05), (0, 2.36, -0.38), shadow)
    return m


@model
def haunted_vending_machine():
    m = Model("haunted_vending_machine")
    body = (70, 40, 100)
    dark = (45, 25, 65)
    slime = (120, 255, 150)
    m.rbox("Cabinet", (2.4, 3.4, 1.6), (0, 1.75, 0), body, 0.15, refl=0.1)
    m.rbox("Top", (2.5, 0.28, 1.7), (0, 3.5, 0), (90, 55, 130), 0.12)
    # glowing header sign
    sign = m.rbox("Sign", (2.0, 0.32, 0.06), (0, 3.2, -0.82), (255, 110, 200), 0.1, mat="Neon", axis="z")
    m.light(sign, (255, 120, 210), 0.8, 6)
    m.rbox("Window", (1.5, 2.2, 0.08), (-0.3, 1.95, -0.8), (150, 200, 255), 0.08, mat="Glass", tr=0.55, refl=0.35, axis="z")
    m.blk("WindowShine", (0.12, 1.8, 0.02), (-0.82, 2.0, -0.86), WHITE, tr=0.5, R=rot(z=-8))
    # snacks inside on spiral coils
    colors = [(230, 70, 70), (250, 200, 60), (90, 200, 90), (80, 150, 240), (240, 130, 40)]
    for row in range(4):
        for col in range(3):
            c = colors[(row * 3 + col) % len(colors)]
            x, y = -0.75 + col * 0.45, 1.22 + row * 0.48
            m.rbox("Snack", (0.35, 0.38, 0.28), (x, y, -0.55), c, 0.06)
            m.blk("SnackLabel", (0.22, 0.1, 0.02), (x, y + 0.03, -0.7), shade(c, 1.4))
            m.ring("Coil", (x, y - 0.12, -0.45), 0.15, 0.03, (200, 200, 210), normal="z", segments=6, mat="Metal")
        m.blk("Shelf", (1.45, 0.05, 0.6), (-0.3, 1.0 + row * 0.48, -0.45), (200, 200, 210), mat="Metal")
    # glowing eyes in the glass, with angry brows
    for s in (-1, 1):
        e = m.ell("EyeGlow", (0.44, 0.32, 0.06), (-0.3 + s * 0.38, 2.75, -0.86), slime, mat="Neon")
        m.ell("Pupil", (0.12, 0.2, 0.04), (-0.3 + s * 0.38, 2.73, -0.9), (20, 60, 30))
        m.blk("Brow", (0.48, 0.08, 0.04), (-0.3 + s * 0.38, 2.97, -0.88), slime, mat="Neon", R=rot(z=s * 14))
    m.light(e, slime, 1.5, 8)
    # mouth slot with teeth and a slimy tongue
    m.rbox("MouthSlot", (1.45, 0.38, 0.1), (-0.3, 0.5, -0.79), (15, 10, 20), 0.08, axis="z")
    for k in range(7):
        m.wedge("MouthTeeth", (0.15, 0.14, 0.06), (-0.84 + k * 0.18, 0.62, -0.85), (240, 240, 230), R=rot(x=180))
    m.ell("Tongue", (0.55, 0.12, 0.5), (-0.3, 0.38, -0.98), slime, tr=0.15)
    # control panel with keys, coin slot and a flickering display
    m.blk("Panel", (0.5, 1.5, 0.08), (0.88, 2.2, -0.8), (40, 25, 60))
    for k in range(9):
        m.cyl("Key", 0.04, 0.11, (0.76 + (k % 3) * 0.12, 2.5 - (k // 3) * 0.18, -0.85), (220, 220, 230), axis="z")
    m.blk("CoinSlot", (0.06, 0.25, 0.04), (0.88, 1.75, -0.85), (240, 200, 60), mat="Metal")
    m.blk("CoinReturn", (0.28, 0.2, 0.06), (0.88, 1.45, -0.84), (30, 20, 40))
    m.blk("Display", (0.4, 0.18, 0.04), (0.88, 2.85, -0.85), (255, 80, 80), mat="Neon")
    # little arms and dripping slime
    for s in (-1, 1):
        m.rod("Arm", (s * 1.2, 2.0, -0.2), (s * 1.55, 1.4, -0.5), 0.2, (90, 55, 130))
        m.ball("Elbow", 0.24, (s * 1.36, 1.72, -0.34), dark)
        m.mitt((s * 1.57, 1.36, -0.52), 0.32, (90, 55, 130), s, fingers=3)
    m.ell("Slime", (0.55, 0.3, 0.2), (0.6, 3.38, -0.82), slime, tr=0.2)
    m.drip("SlimeDrip", (0.72, 3.3, -0.84), 0.5, 0.14, slime)
    m.drip("SlimeDrip", (0.45, 3.3, -0.84), 0.3, 0.1, slime)
    # cobweb in the corner and stubby feet
    for k in range(3):
        a = math.radians(-10 - k * 35)
        m.rod("Web", (-1.2, 3.35, -0.82), (-1.2 + math.cos(a) * 0.55, 3.35 + math.sin(a) * 0.55, -0.82), 0.02, (230, 230, 240))
    m.rod("Web", (-0.9, 3.33, -0.82), (-1.02, 3.03, -0.82), 0.02, (230, 230, 240))
    for s in (-1, 1):
        for z in (-0.5, 0.5):
            m.cyl("CabinetFoot", 0.12, 0.3, (s * 0.95, 0.03, z), (30, 20, 40))
    return m


@model
def mushroom_witch():
    m = Model("mushroom_witch")
    stem = (245, 235, 215)
    cap = (130, 60, 170)
    gill = (220, 200, 180)
    m.ell("Stem", (1.6, 2.2, 1.45), (0, 1.15, 0), stem)
    m.scatter("Freckle", (0, 1.15, 0), (1.6, 2.2, 1.45), 7, [(225, 205, 185)], seed=13, d=0.12, shape="dot", ymin=-0.5)
    m.eyes(1.4, -0.68, 0.56, 0.38, lid=stem, look=(0.03, 0), iris=(120, 200, 90), lash=2, z_back=0.04)
    m.brow(-0.28, 1.72, -0.66, 0.32, (110, 60, 140), -1, tilt=-14)
    m.brow(0.28, 1.72, -0.66, 0.32, (110, 60, 140), 1, tilt=-14)
    m.grin(0.95, -0.7, 0.4, curve=0.3, bend=0.05)
    m.wedge("Tooth", (0.08, 0.1, 0.04), (0.08, 0.92, -0.71), WHITE, R=rot(x=180))
    # warty nose
    m.ell("Nose", (0.22, 0.34, 0.24), (0, 1.18, -0.76), (240, 200, 180), R=rot(x=-20))
    m.ball("Wart", 0.07, (0.07, 1.25, -0.86), (200, 170, 150))
    # mushroom-cap witch hat with gills underneath
    m.cyl("Brim", 0.12, 2.4, (0, 2.22, 0), cap)
    for k in range(16):
        a = k * 2 * math.pi / 16
        m.blk("Gill", (0.5, 0.04, 0.04), (math.cos(a) * 0.9, 2.14, math.sin(a) * 0.9), gill, R=rot(y=-math.degrees(a)))
    m.ell("Cap", (1.7, 0.9, 1.7), (0, 2.55, 0), cap)
    for k in range(5):
        m.cyl("HatCone", 0.4, 1.1 - k * 0.2, (0.12 * k, 2.9 + k * 0.33, 0.05 * k), cap, R=rot(z=-8 * k))
    m.ell("HatTip", (0.2, 0.35, 0.2), (0.75, 4.55, 0.3), cap, R=rot(z=-60))
    m.ball("HatTip", 0.18, (0.98, 4.5, 0.3), (120, 255, 160), mat="Neon")
    for (x, y, z, d) in [(-0.6, 2.55, -0.55, 0.28), (0.55, 2.6, -0.5, 0.24), (0.0, 2.8, -0.65, 0.2), (-0.8, 2.35, 0.3, 0.26), (0.85, 2.4, 0.2, 0.22), (0.2, 3.3, -0.3, 0.16), (-0.25, 3.7, -0.15, 0.12)]:
        m.ell("Spot", (d, d, d * 0.5), (x, y, z), (255, 255, 255), R=rot(x=-30))
    m.cyl("HatBand", 0.16, 1.15, (0, 2.95, 0), (60, 200, 120))
    glow = m.rbox("Buckle", (0.28, 0.22, 0.06), (0, 2.95, -0.58), (120, 255, 160), 0.05, mat="Neon", axis="z")
    m.sparkles(glow, (140, 255, 170))
    # a potion bottle on a belt
    m.ring("Belt", (0, 0.7, 0), 0.76, 0.07, (110, 70, 140), normal="y", segments=14)
    m.ball("Potion", 0.3, (-0.55, 0.55, -0.48), (120, 255, 160), mat="Glass", tr=0.25)
    m.cyl("Potion", 0.14, 0.1, (-0.55, 0.75, -0.48), (150, 110, 70))
    # broom with straw strands and a binding
    m.rod("Arm", (0.6, 1.3, -0.1), (1.0, 1.0, -0.45), 0.2, stem)
    m.mitt((1.0, 1.0, -0.46), 0.26, stem, 1)
    m.rod("BroomStick", (1.05, 2.5, -0.5), (0.95, 0.2, -0.45), 0.14, (130, 90, 55))
    m.ell("Bristles", (0.6, 0.7, 0.6), (0.95, 0.35, -0.45), (210, 170, 90), mat="Fabric")
    m.cyl("BroomBand", 0.1, 0.34, (0.95, 0.68, -0.45), (110, 60, 140))
    for k in range(6):
        a = k * math.pi / 3
        m.rod("Bristles", (0.95 + math.cos(a) * 0.15, 0.6, -0.45 + math.sin(a) * 0.15), (0.95 + math.cos(a) * 0.35, 0.05, -0.45 + math.sin(a) * 0.35), 0.05, (190, 150, 70))
    m.rod("Arm", (-0.6, 1.3, -0.1), (-0.95, 0.95, -0.35), 0.2, stem)
    m.mitt((-0.97, 0.93, -0.37), 0.26, stem, -1)
    # tiny glowing mushrooms at her feet
    for (x, z, c) in [(-0.9, -0.6, (120, 255, 160)), (0.3, -0.9, (200, 120, 255)), (-0.4, 0.8, (120, 255, 160)), (0.85, 0.55, (200, 120, 255))]:
        m.cyl("Shroomlet", 0.25, 0.1, (x, 0.12, z), (240, 240, 230))
        m.ell("ShroomCap", (0.35, 0.18, 0.35), (x, 0.28, z), c, mat="Neon")
        m.ball("ShroomSpot", 0.06, (x + 0.06, 0.36, z - 0.06), WHITE)
    return m


@model
def mall_cop_phantom():
    m = Model("mall_cop_phantom")
    ghost = (190, 225, 255)
    navy = (50, 70, 140)
    gold = (240, 200, 60)
    # segway with lights, fenders and grippy handles
    m.rbox("Deck", (1.6, 0.2, 1.0), (0, 0.45, 0), (50, 50, 60), 0.1)
    m.blk("DeckGrip", (1.3, 0.03, 0.8), (0, 0.56, 0), (25, 25, 30), mat="Rubber")
    for s in (-1, 1):
        m.cyl("Wheel", 0.3, 0.8, (s * 0.95, 0.4, 0), (30, 30, 35), axis="x", mat="Rubber")
        m.cyl("Hubcap", 0.32, 0.35, (s * 0.95, 0.4, 0), (200, 200, 210), axis="x", mat="Metal")
        m.ell("Fender", (0.36, 0.3, 0.9), (s * 0.95, 0.72, 0), (60, 60, 70))
        m.ball("Headlight", 0.12, (s * 0.6, 0.47, -0.52), (255, 250, 200), mat="Neon")
    m.rod("Pole", (0, 0.55, -0.35), (0, 2.2, -0.55), 0.14, (60, 60, 70), mat="Metal")
    m.cyl("Handlebar", 1.2, 0.14, (0, 2.2, -0.55), (40, 40, 45), axis="x")
    for s in (-1, 1):
        m.cyl("Grip", 0.25, 0.18, (s * 0.52, 2.2, -0.55), (20, 20, 22), axis="x", mat="Rubber")
    # ghost body with a wispy tail
    m.ell("Body", (1.4, 1.9, 1.2), (0, 2.1, 0.15), ghost, tr=0.2)
    m.ell("Tail", (0.9, 0.9, 0.8), (0, 1.15, 0.25), ghost, tr=0.3)
    m.ell("Tail", (0.5, 0.5, 0.5), (0.15, 0.75, 0.45), ghost, tr=0.4)
    m.ell("Head", (1.2, 1.1, 1.1), (0, 3.25, 0.05), ghost, tr=0.15)
    m.eyes(3.3, -0.47, 0.42, 0.3, lid=ghost, angry=10, iris=(90, 120, 200), z_back=0.04)
    for s in (-1, 1):
        m.chain("Mustache", [(0, 3.03, -0.53), (s * 0.18, 3.0, -0.52), (s * 0.32, 3.05, -0.47), (s * 0.38, 3.13, -0.42)], 0.1, (90, 110, 140))
    m.grin(2.86, -0.5, 0.22, curve=-0.2, color=(80, 100, 140))
    # uniform: shirt with a pocket, star badge, belt with a radio and cuffs
    m.rbox("Shirt", (1.3, 0.9, 0.2), (0, 2.25, -0.38), navy, 0.06, tr=0.05)
    m.blk("Pocket", (0.3, 0.25, 0.04), (0.32, 2.4, -0.49), shade(navy, 0.85))
    badge = m.cyl("Badge", 0.06, 0.3, (-0.3, 2.45, -0.5), gold, axis="z", mat="Metal")
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 2
        m.wedge("Badge", (0.05, 0.1, 0.05), (-0.3 + math.cos(a) * 0.17, 2.45 + math.sin(a) * 0.17, -0.52), gold, mat="Metal", R=rot(z=math.degrees(a) - 90))
    m.blk("Belt", (1.32, 0.14, 0.24), (0, 1.82, -0.36), (30, 30, 35), mat="Leather")
    m.blk("Buckle", (0.16, 0.12, 0.04), (0, 1.82, -0.49), gold, mat="Metal")
    m.rbox("Radio", (0.2, 0.32, 0.12), (-0.5, 1.72, -0.48), (40, 40, 45), 0.04)
    m.rod("RadioAntenna", (-0.55, 1.85, -0.48), (-0.55, 2.1, -0.48), 0.03, (40, 40, 45))
    m.ring("Cuffs", (0.5, 1.68, -0.5), 0.1, 0.03, (200, 200, 210), normal="z", segments=8, mat="Metal")
    m.cyl("Cap", 0.35, 1.05, (0, 3.85, 0.05), (40, 55, 120))
    m.ell("Cap", (1.1, 0.2, 1.1), (0, 4.03, 0.05), (40, 55, 120))
    m.blk("CapBill", (0.9, 0.08, 0.4), (0, 3.7, -0.5), (25, 30, 60))
    m.cyl("CapBadge", 0.05, 0.22, (0, 3.9, -0.5), gold, axis="z", mat="Metal")
    # arms on the handlebar, flashlight with a soft beam in one hand
    for s in (-1, 1):
        m.rod("Arm", (s * 0.6, 2.6, -0.1), (s * 0.5, 2.25, -0.5), 0.24, ghost, tr=0.2)
        m.ball("Hand", 0.24, (s * 0.5, 2.25, -0.55), ghost, tr=0.15)
    fl = m.cyl("Flashlight", 0.6, 0.2, (0.75, 2.4, -0.75), (40, 40, 40), axis="z", mat="Metal")
    m.cyl("FlashBand", 0.1, 0.26, (0.75, 2.4, -0.98), (200, 200, 210), axis="z", mat="Metal")
    m.cyl("FlashLens", 0.06, 0.24, (0.75, 2.4, -1.07), (255, 250, 200), axis="z", mat="Neon")
    m.cyl("Beam", 0.9, 0.5, (0.75, 2.4, -1.55), (255, 250, 210), axis="z", mat="Neon", tr=0.88)
    m.light(fl, (255, 250, 210), 1.2, 7)
    m.smoke(badge, (200, 230, 255), 0.05, 0.2, 1.2)
    return m


@model
def escalator_wraith():
    m = Model("escalator_wraith")
    metal = (150, 150, 160)
    cloak = (60, 30, 90)
    cloak2 = (80, 45, 115)
    # escalator steps rising toward the back, with grooves and yellow edges
    for k in range(4):
        y, z = 0.2 + k * 0.4, -0.9 + k * 0.6
        m.blk("Step", (1.8, 0.4, 0.7), (0, y, z), metal, mat="DiamondPlate")
        m.blk("StepEdge", (1.8, 0.05, 0.08), (0, y + 0.2, z - 0.32), (240, 200, 40))
        m.blk("StepFace", (1.8, 0.4 + k * 0.4, 0.1), (0, 0.2 + k * 0.2, -1.25 + k * 0.6), (110, 110, 120), mat="Metal")
        for j in range(5):
            m.blk("Groove", (0.03, 0.02, 0.6), (-0.7 + j * 0.35, y + 0.21, z), (90, 90, 100))
    for s in (-1, 1):
        m.wedge("Side", (0.15, 1.8, 2.6), (s * 0.98, 0.9, 0.0), (90, 90, 100), mat="Metal")
        m.wedge("SideGlass", (0.06, 1.2, 2.2), (s * 0.98, 1.95, 0.2), (180, 220, 255), mat="Glass", tr=0.6)
        m.rod("Rail", (s * 1.0, 1.0, -1.4), (s * 1.0, 2.6, 1.0), 0.16, (20, 20, 25), mat="Rubber")
        m.ball("Rail", 0.2, (s * 1.0, 1.0, -1.4), (20, 20, 25), mat="Rubber")
    # hooded cloak floating on the steps, layered folds and a tattered hem
    m.cyl("Robe", 1.2, 1.5, (0, 1.6, 0.0), cloak, mat="Fabric")
    m.cyl("RobeTop", 1.0, 1.2, (0, 2.6, 0.0), cloak, mat="Fabric")
    for k in range(6):
        a = k * 2 * math.pi / 6 + 0.3
        m.ell("RobeFold", (0.2, 1.6, 0.18), (math.cos(a) * 0.7, 1.9, math.sin(a) * 0.7), cloak2, mat="Fabric", R=rot(y=-math.degrees(a)))
    m.ell("Hood", (1.4, 1.5, 1.4), (0, 3.4, 0.05), cloak, mat="Fabric")
    m.ell("HoodRim", (1.15, 1.2, 0.3), (0, 3.32, -0.52), cloak2, mat="Fabric")
    m.ell("HoodDark", (0.95, 1.0, 0.5), (0, 3.3, -0.5), (12, 8, 20))
    m.wedge("HoodTip", (0.3, 0.5, 0.4), (0, 4.15, 0.45), cloak, mat="Fabric", R=rot(x=-30))
    for s in (-1, 1):
        e = m.ell("EyeGlow", (0.22, 0.14, 0.06), (s * 0.2, 3.38, -0.75), (90, 240, 255), mat="Neon", R=rot(z=s * -12))
        m.ell("EyeGlow", (0.4, 0.28, 0.04), (s * 0.2, 3.38, -0.72), (90, 240, 255), mat="Neon", tr=0.7)
        m.rod("Sleeve", (s * 0.6, 2.7, 0), (s * 1.0, 2.2, -0.45), 0.42, cloak, shape="E")
        m.ell("Cuff", (0.42, 0.3, 0.42), (s * 1.0, 2.15, -0.47), cloak2, mat="Fabric")
        m.ell("Claw", (0.25, 0.3, 0.2), (s * 1.05, 2.0, -0.52), (200, 220, 230))
        for k in (-1, 0, 1):
            m.rod("Finger", (s * 1.05 + k * 0.07, 1.92, -0.55), (s * 1.08 + k * 0.1, 1.68, -0.68), 0.05, (200, 220, 230))
    m.light(e, (90, 240, 255), 1.5, 8)
    m.smoke(e, (140, 90, 200), 0.1, 0.4, 1.5)
    for k in range(8):
        a = k * 2 * math.pi / 8
        m.wedge("Tatter", (0.32, 0.5, 0.15), (math.cos(a) * 0.72, 0.9, math.sin(a) * 0.72), cloak if k % 2 else cloak2, mat="Fabric", R=rot(y=-math.degrees(a) - 90) @ rot(z=180))
    # chains of a lost soul and a glowing out-of-order sign
    m.chain("Chain", [(-0.6, 2.4, -0.55), (-0.3, 2.1, -0.65), (0.1, 2.2, -0.65), (0.5, 2.0, -0.6)], 0.07, (170, 170, 180), mat="Metal")
    m.rbox("Sign", (0.85, 0.38, 0.06), (0, 3.9, 0.9), (240, 220, 60), 0.08, mat="Neon", axis="z")
    m.blk("SignBar", (0.6, 0.06, 0.04), (0, 3.9, 0.86), (30, 30, 30), R=rot(z=-15))
    return m


@model
def the_mannequin_duke():
    m = Model("the_mannequin_duke")
    skin = (235, 225, 210)
    joint = (205, 190, 170)
    velvet = (100, 40, 140)
    velvet2 = (75, 25, 110)
    gold = (240, 195, 70)
    # stand with a weighted base
    m.cyl("StandBase", 0.15, 1.6, (0, 0.08, 0), (40, 40, 45), mat="Metal")
    m.ring("StandBase", (0, 0.15, 0), 0.78, 0.06, gold, normal="y", segments=16, mat="Metal")
    m.cyl("StandPole", 0.8, 0.18, (0, 0.5, 0), (180, 180, 190), mat="Metal")
    # legs with breeches and polished riding boots
    for s in (-1, 1):
        m.cyl("Leg", 1.2, 0.38, (s * 0.3, 1.2, 0), skin, refl=0.2)
        m.ball("Knee", 0.4, (s * 0.3, 1.35, 0), joint, refl=0.2)
        m.ell("Boot", (0.45, 0.6, 0.65), (s * 0.3, 0.75, -0.05), (30, 25, 25), refl=0.3)
        m.cyl("Boot", 0.1, 0.44, (s * 0.3, 1.02, 0), (80, 60, 40))
    m.rbox("Breeches", (1.0, 0.6, 0.6), (0, 1.95, 0), (240, 235, 220), 0.12, mat="Fabric")
    # velvet coat with tails, gold trim, medals and a sash
    m.rbox("Coat", (1.4, 1.6, 0.8), (0, 2.85, 0), velvet, 0.15, mat="Fabric")
    m.blk("CoatTail", (1.3, 1.0, 0.3), (0, 2.0, 0.35), velvet, mat="Fabric")
    m.wedge("CoatTail", (0.6, 0.4, 0.3), (-0.33, 1.3, 0.35), velvet2, mat="Fabric", R=rot(z=180))
    m.wedge("CoatTail", (0.6, 0.4, 0.3), (0.33, 1.3, 0.35), velvet2, mat="Fabric", R=rot(z=180))
    m.blk("TrimL", (0.12, 1.6, 0.05), (-0.18, 2.85, -0.42), gold, mat="Metal")
    m.blk("TrimR", (0.12, 1.6, 0.05), (0.18, 2.85, -0.42), gold, mat="Metal")
    m.blk("Trim", (1.42, 0.08, 0.82), (0, 2.08, 0), gold, mat="Metal")
    for k in range(3):
        m.ball("Button", 0.12, (0, 3.3 - k * 0.35, -0.43), gold, mat="Metal")
    m.cyl("Sash", 0.2, 1.45, (0, 2.6, 0), (200, 30, 50), mat="Fabric", R=rot(z=-25))
    for k, c in enumerate([(220, 50, 60), (60, 120, 220)]):
        m.blk("Ribbon", (0.14, 0.2, 0.03), (-0.45 + k * 0.2, 3.25, -0.42), c)
        m.cyl("Medal", 0.04, 0.16, (-0.45 + k * 0.2, 3.08, -0.43), gold, axis="z", mat="Metal")
    for s in (-1, 1):
        m.blk("Epaulette", (0.45, 0.12, 0.6), (s * 0.75, 3.66, 0), gold, mat="Metal")
        m.cyl("Fringe", 0.2, 0.5, (s * 0.85, 3.52, 0), gold, mat="Metal")
    # a tailor's measuring tape draped round the neck
    for s in (-1, 1):
        m.blk("Tape", (0.1, 0.9, 0.03), (s * 0.3, 3.25, -0.43), (250, 220, 80), R=rot(z=s * 6))
        for k in range(4):
            m.blk("TapeMark", (0.06, 0.022, 0.022), (s * 0.3 - 0.01, 2.95 + k * 0.18, -0.45), (40, 30, 30))
    # layered ruff collar and the blank mannequin head
    m.cyl("Ruff", 0.25, 1.15, (0, 3.75, 0), (250, 250, 250), mat="Fabric")
    for k in range(10):
        a = k * 2 * math.pi / 10
        m.ball("Ruff", 0.28, (math.cos(a) * 0.55, 3.75, math.sin(a) * 0.55), (245, 245, 250), mat="Fabric")
    m.cyl("Neck", 0.3, 0.35, (0, 3.95, 0), skin, refl=0.2)
    m.ell("Head", (0.8, 1.05, 0.85), (0, 4.5, 0), skin, refl=0.3)
    m.ell("Chin", (0.4, 0.25, 0.3), (0, 4.08, -0.28), skin, refl=0.3)
    m.ell("Nose", (0.12, 0.2, 0.12), (0, 4.45, -0.43), skin, refl=0.3)
    for s in (-1, 1):
        g = m.ball("EyeGlow", 0.15, (s * 0.17, 4.6, -0.38), (220, 140, 255), mat="Neon")
        m.chain("Mustache", [(0, 4.3, -0.42), (s * 0.15, 4.28, -0.4), (s * 0.27, 4.33, -0.35), (s * 0.3, 4.42, -0.32)], 0.06, (40, 30, 40))
    m.ring("Monocle", (0.17, 4.6, -0.43), 0.16, 0.04, gold, normal="z", segments=8, mat="Metal")
    m.cyl("Monocle", 0.02, 0.3, (0.17, 4.6, -0.44), (220, 230, 255), axis="z", mat="Glass", tr=0.6)
    m.rod("MonocleChain", (0.3, 4.5, -0.42), (0.45, 3.9, -0.35), 0.02, gold)
    # top hat with a band, a buckle and a plume
    m.cyl("HatBrim", 0.08, 1.2, (0, 4.98, 0), (20, 20, 25))
    m.cyl("Hat", 0.9, 0.8, (0, 5.45, 0), (20, 20, 25))
    m.cyl("HatBand", 0.18, 0.82, (0, 5.1, 0), velvet)
    m.blk("HatPin", (0.18, 0.14, 0.04), (0, 5.1, -0.41), gold, mat="Metal")
    m.ell("HatFeather", (0.12, 0.7, 0.12), (0.35, 5.5, 0.15), (230, 230, 240), R=rot(z=-25))
    m.light(g, (200, 130, 255), 1.5, 8)
    m.sparkles(g, (220, 160, 255))
    # arms with wooden joints, a pin cushion on one wrist and a gold-topped cane
    for s in (-1, 1):
        m.rod("Arm", (s * 0.75, 3.5, 0), (s * 0.95, 2.7, -0.2), 0.3, velvet, mat="Fabric")
        m.ball("Joint", 0.24, (s * 0.95, 2.7, -0.2), joint, refl=0.2)
        m.rod("Forearm", (s * 0.95, 2.7, -0.2), (s * 0.95, 2.2, -0.55), 0.22, skin, refl=0.2)
        m.cyl("Cuff", 0.12, 0.28, (s * 0.95, 2.66, -0.23), (250, 250, 250), mat="Fabric", R=rot(x=40))
        m.mitt((s * 0.95, 2.15, -0.58), 0.27, skin, s)
    m.ball("PinCushion", 0.24, (-0.95, 2.38, -0.45), (220, 60, 80), mat="Fabric")
    for k in range(3):
        m.ball("CushionPin", 0.05, (-0.95 + (k - 1) * 0.07, 2.52, -0.48 + k * 0.03), [(255, 230, 80), (90, 200, 255), WHITE][k])
    m.cyl("Cane", 2.1, 0.12, (0.95, 1.15, -0.62), (30, 25, 30))
    m.cyl("CaneBand", 0.08, 0.15, (0.95, 2.05, -0.62), gold, mat="Metal")
    m.ball("CaneTop", 0.28, (0.95, 2.3, -0.62), gold, mat="Metal", refl=0.3)
    return m
