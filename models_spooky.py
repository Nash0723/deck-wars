# Spooky family models (friendly ghosts, haunted stuff)
import math
from modelkit import Model, rot, WHITE, PUPIL

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


def sheet_ghost_body(m, scale=1.0, tr=0.08, color=(245, 245, 255), lift=0.35):
    s = scale
    y0 = lift
    m.ell("Body", (1.6 * s, 2.3 * s, 1.5 * s), (0, y0 + 1.35 * s, 0), color, tr=tr)
    m.ell("Skirt", (1.95 * s, 0.9 * s, 1.85 * s), (0, y0 + 0.42 * s, 0), color, tr=tr)
    for k in range(8):
        a = k * 2 * math.pi / 8 + 0.2
        m.ell("Hem", (0.55 * s, 0.42 * s, 0.55 * s), (math.cos(a) * 0.78 * s, y0 + 0.1 * s, math.sin(a) * 0.75 * s), color, tr=tr)
    for k in (-1, 1):
        m.ell("Hole", (0.3 * s, 0.46 * s, 0.12 * s), (k * 0.3 * s, y0 + 1.85 * s, -0.66 * s), (30, 25, 40))
        m.ell("Arm", (0.38 * s, 0.75 * s, 0.38 * s), (k * 0.85 * s, y0 + 1.1 * s, -0.15 * s), color, tr=tr, R=rot(z=k * 40))
    m.ell("Mouth", (0.32 * s, 0.22 * s, 0.1 * s), (0, y0 + 1.42 * s, -0.7 * s), (30, 25, 40))
    m.cheeks(y0 + 1.55 * s, -0.66 * s, 1.0 * s, 0.24 * s)


@model
def sheet_ghost():
    m = Model("sheet_ghost")
    sheet_ghost_body(m, 1.0)
    glow = m.ball("Glow", 0.2, (0, 2.0, 0), (200, 180, 255), tr=1)
    m.light(glow, (190, 170, 255), 1.0, 7)
    m.cyl("Shadow", 0.04, 1.4, (0, 0.02, 0), (40, 30, 60), tr=0.5)
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
    m.ball("Skull", 1.15, (0, 3.0, 0), bone)
    m.ell("Jaw", (0.8, 0.35, 0.7), (0, 2.45, -0.1), bone)
    for s in (-1, 1):
        m.ell("Socket", (0.34, 0.38, 0.15), (s * 0.24, 3.05, -0.52), (40, 30, 50))
        m.ball("SocketGlow", 0.12, (s * 0.24, 3.05, -0.58), (190, 120, 255), mat="Neon")
    m.ell("NoseHole", (0.12, 0.15, 0.08), (0, 2.82, -0.56), (40, 30, 50))
    for k in range(5):
        m.blk("Tooth", (0.1, 0.12, 0.06), (-0.22 + k * 0.11, 2.6, -0.48), WHITE)
    # jersey torso
    m.blk("Jersey", (1.2, 1.1, 0.7), (0, 1.85, 0), (240, 120, 30), mat="Fabric")
    m.blk("JerseyStripe", (1.22, 0.16, 0.72), (0, 2.2, 0), (60, 40, 90), mat="Fabric")
    m.blk("Number", (0.16, 0.5, 0.03), (0, 1.75, -0.37), (255, 255, 255))
    m.cyl("Spine", 0.5, 0.18, (0, 1.1, 0), bone)
    m.ell("Pelvis", (0.8, 0.35, 0.5), (0, 0.85, 0), bone)
    m.blk("Skirt", (1.0, 0.35, 0.65), (0, 1.1, 0), (60, 40, 90), mat="Fabric")
    for s in (-1, 1):
        # legs
        m.rod("Leg", (s * 0.25, 0.8, 0), (s * 0.3, 0.15, -0.05), 0.14, bone)
        m.ball("Knee", 0.2, (s * 0.28, 0.48, -0.03), bone)
        m.ell("Shoe", (0.35, 0.2, 0.55), (s * 0.3, 0.1, -0.15), (240, 240, 245))
        # arms up with pom-poms
        m.rod("Arm", (s * 0.65, 2.25, 0), (s * 1.0, 2.85, -0.2), 0.13, bone)
        m.ball("Elbow", 0.18, (s * 1.0, 2.85, -0.2), bone)
        m.rod("Arm", (s * 1.0, 2.85, -0.2), (s * 1.15, 3.45, -0.3), 0.12, bone)
        pom = m.ball("PomPom", 0.75, (s * 1.18, 3.65, -0.32), (170, 80, 230) if s < 0 else (255, 140, 40), mat="Foil")
    # ribs peeking from the collar
    for k in range(3):
        m.blk("Rib", (0.5 - k * 0.08, 0.06, 0.05), (0, 2.38 - k * 0.1, -0.36), bone)
    return m


@model
def haunted_vending_machine():
    m = Model("haunted_vending_machine")
    body = (70, 40, 100)
    m.blk("Cabinet", (2.4, 3.4, 1.6), (0, 1.75, 0), body, refl=0.1)
    m.blk("Top", (2.5, 0.25, 1.7), (0, 3.5, 0), (90, 55, 130))
    m.blk("Window", (1.5, 2.2, 0.08), (-0.3, 2.05, -0.8), (150, 200, 255), mat="Glass", tr=0.55, refl=0.3)
    # snacks inside
    colors = [(230, 70, 70), (250, 200, 60), (90, 200, 90), (80, 150, 240), (240, 130, 40)]
    for row in range(4):
        for col in range(3):
            c = colors[(row * 3 + col) % len(colors)]
            m.blk("Snack", (0.35, 0.4, 0.3), (-0.75 + col * 0.45, 1.3 + row * 0.5, -0.55), c)
        m.blk("Shelf", (1.45, 0.05, 0.6), (-0.3, 1.08 + row * 0.5, -0.45), (200, 200, 210), mat="Metal")
    # glowing eyes in the glass
    for s in (-1, 1):
        e = m.ell("EyeGlow", (0.42, 0.3, 0.06), (-0.3 + s * 0.38, 2.75, -0.86), (120, 255, 150), mat="Neon")
    m.light(e, (120, 255, 150), 1.5, 8)
    m.blk("MouthSlot", (1.4, 0.35, 0.1), (-0.3, 0.55, -0.79), (15, 10, 20))
    m.blk("MouthTeeth", (1.3, 0.08, 0.06), (-0.3, 0.68, -0.85), (240, 240, 230))
    # control panel
    m.blk("Panel", (0.5, 1.5, 0.08), (0.88, 2.3, -0.8), (40, 25, 60))
    for k in range(6):
        m.cyl("Key", 0.04, 0.12, (0.78 + (k % 2) * 0.2, 2.6 - (k // 2) * 0.22, -0.85), (220, 220, 230), axis="z")
    m.blk("CoinSlot", (0.06, 0.25, 0.04), (0.88, 1.85, -0.85), (240, 200, 60), mat="Metal")
    m.blk("Display", (0.4, 0.18, 0.04), (0.88, 2.95, -0.85), (255, 80, 80), mat="Neon")
    # little arms and a dripping slime
    for s in (-1, 1):
        m.rod("Arm", (s * 1.2, 2.0, -0.2), (s * 1.55, 1.4, -0.5), 0.2, (90, 55, 130))
        m.ball("Hand", 0.3, (s * 1.57, 1.36, -0.52), (90, 55, 130))
    m.ell("Slime", (0.5, 0.3, 0.2), (0.6, 3.3, -0.82), (120, 255, 150), tr=0.2)
    m.ell("SlimeDrip", (0.14, 0.45, 0.12), (0.7, 3.0, -0.84), (120, 255, 150), tr=0.2)
    return m


@model
def mushroom_witch():
    m = Model("mushroom_witch")
    stem = (245, 235, 215)
    cap = (130, 60, 170)
    m.ell("Stem", (1.6, 2.2, 1.45), (0, 1.15, 0), stem)
    m.eyes(1.4, -0.68, 0.56, 0.38, lid=stem, look=(0.03, 0))
    m.smile(0.95, -0.7, 0.34)
    m.ell("Nose", (0.2, 0.32, 0.22), (0, 1.18, -0.76), (240, 200, 180), R=rot(x=-20))
    # mushroom-cap witch hat
    m.cyl("Brim", 0.12, 2.4, (0, 2.22, 0), cap)
    m.ell("Cap", (1.7, 0.9, 1.7), (0, 2.55, 0), cap)
    for k in range(4):
        m.cyl("HatCone", 0.42, 1.1 - k * 0.24, (0.12 * k, 2.9 + k * 0.38, 0.05 * k), cap, R=rot(z=-8 * k))
    m.ell("HatTip", (0.2, 0.35, 0.2), (0.6, 4.4, 0.25), cap)
    for (x, y, z) in [(-0.6, 2.55, -0.55), (0.55, 2.6, -0.5), (0.0, 2.8, -0.65), (-0.8, 2.35, 0.3), (0.85, 2.4, 0.2)]:
        m.ball("Spot", 0.26, (x, y, z), (255, 255, 255))
    m.cyl("HatBand", 0.16, 1.15, (0, 2.95, 0), (60, 200, 120))
    glow = m.ball("Buckle", 0.22, (0, 2.95, -0.58), (120, 255, 160), mat="Neon")
    m.sparkles(glow, (140, 255, 170))
    # broom
    m.rod("Arm", (0.6, 1.3, -0.1), (1.0, 1.0, -0.45), 0.2, stem)
    m.rod("BroomStick", (1.05, 2.5, -0.5), (0.95, 0.2, -0.45), 0.14, (130, 90, 55))
    m.ell("Bristles", (0.6, 0.7, 0.6), (0.95, 0.35, -0.45), (210, 170, 90), mat="Fabric")
    m.rod("Arm", (-0.6, 1.3, -0.1), (-0.95, 0.95, -0.35), 0.2, stem)
    # tiny glowing mushrooms at her feet
    for (x, z, c) in [(-0.9, -0.6, (120, 255, 160)), (0.3, -0.9, (200, 120, 255)), (-0.4, 0.8, (120, 255, 160))]:
        m.cyl("Shroomlet", 0.25, 0.1, (x, 0.12, z), (240, 240, 230))
        m.ell("ShroomCap", (0.35, 0.18, 0.35), (x, 0.28, z), c, mat="Neon")
    return m


@model
def mall_cop_phantom():
    m = Model("mall_cop_phantom")
    ghost = (190, 225, 255)
    # segway
    m.blk("Deck", (1.6, 0.2, 1.0), (0, 0.45, 0), (50, 50, 60))
    for s in (-1, 1):
        m.cyl("Wheel", 0.3, 0.8, (s * 0.95, 0.4, 0), (30, 30, 35), axis="x")
        m.cyl("Hubcap", 0.32, 0.35, (s * 0.95, 0.4, 0), (200, 200, 210), axis="x", mat="Metal")
    m.rod("Pole", (0, 0.55, -0.35), (0, 2.2, -0.55), 0.14, (60, 60, 70), mat="Metal")
    m.cyl("Handlebar", 1.2, 0.14, (0, 2.2, -0.55), (40, 40, 45), axis="x")
    # ghost body
    m.ell("Body", (1.4, 1.9, 1.2), (0, 2.1, 0.15), ghost, tr=0.2)
    m.ell("Tail", (0.9, 0.9, 0.8), (0, 1.15, 0.25), ghost, tr=0.3)
    m.ell("Head", (1.2, 1.1, 1.1), (0, 3.25, 0.05), ghost, tr=0.15)
    m.eyes(3.3, -0.47, 0.42, 0.3, lid=ghost, angry=10)
    m.ell("Mustache", (0.6, 0.15, 0.15), (0, 3.02, -0.52), (90, 110, 140))
    # uniform bits
    m.blk("Shirt", (1.3, 0.9, 0.2), (0, 2.25, -0.38), (50, 70, 140), tr=0.05)
    badge = m.cyl("Badge", 0.06, 0.3, (-0.3, 2.45, -0.5), (240, 200, 60), axis="z", mat="Metal")
    m.cyl("Cap", 0.35, 1.05, (0, 3.85, 0.05), (40, 55, 120))
    m.blk("CapBill", (0.9, 0.08, 0.4), (0, 3.7, -0.5), (25, 30, 60))
    m.cyl("CapBadge", 0.05, 0.22, (0, 3.9, -0.5), (240, 200, 60), axis="z", mat="Metal")
    # arms on the handlebar, flashlight in one hand
    for s in (-1, 1):
        m.rod("Arm", (s * 0.6, 2.6, -0.1), (s * 0.5, 2.25, -0.5), 0.24, ghost, tr=0.2)
    fl = m.cyl("Flashlight", 0.6, 0.2, (0.75, 2.4, -0.75), (40, 40, 40), axis="z", mat="Metal")
    m.cyl("FlashLens", 0.06, 0.24, (0.75, 2.4, -1.07), (255, 250, 200), axis="z", mat="Neon")
    m.light(fl, (255, 250, 210), 1.2, 7)
    m.smoke(badge, (200, 230, 255), 0.05, 0.2, 1.2)
    return m


@model
def escalator_wraith():
    m = Model("escalator_wraith")
    metal = (150, 150, 160)
    # escalator steps rising toward the back
    for k in range(4):
        m.blk("Step", (1.8, 0.4, 0.7), (0, 0.2 + k * 0.4, -0.9 + k * 0.6), metal, mat="DiamondPlate")
        m.blk("StepFace", (1.8, 0.4 + k * 0.4, 0.1), (0, 0.2 + k * 0.2, -1.25 + k * 0.6), (110, 110, 120), mat="Metal")
    for s in (-1, 1):
        m.wedge("Side", (0.15, 1.8, 2.6), (s * 0.98, 0.9, 0.0), (90, 90, 100), mat="Metal")
        m.rod("Rail", (s * 1.0, 1.0, -1.4), (s * 1.0, 2.6, 1.0), 0.16, (20, 20, 25), mat="Rubber")
    # hooded cloak floating on the steps
    cloak = (60, 30, 90)
    m.cyl("Robe", 1.2, 1.5, (0, 1.6, 0.0), cloak, mat="Fabric")
    m.cyl("RobeTop", 1.0, 1.2, (0, 2.6, 0.0), cloak, mat="Fabric")
    m.ell("Hood", (1.4, 1.5, 1.4), (0, 3.4, 0.05), cloak, mat="Fabric")
    m.ell("HoodDark", (0.95, 1.0, 0.5), (0, 3.3, -0.5), (12, 8, 20))
    for s in (-1, 1):
        e = m.ell("EyeGlow", (0.22, 0.14, 0.06), (s * 0.2, 3.38, -0.75), (90, 240, 255), mat="Neon")
        m.rod("Sleeve", (s * 0.6, 2.7, 0), (s * 1.0, 2.2, -0.45), 0.4, cloak, shape="E")
        m.ell("Claw", (0.25, 0.35, 0.2), (s * 1.05, 2.0, -0.52), (200, 220, 230))
    m.light(e, (90, 240, 255), 1.5, 8)
    m.smoke(e, (140, 90, 200), 0.1, 0.4, 1.5)
    for k in range(5):
        a = k * 2 * math.pi / 5
        m.ell("Tatter", (0.4, 0.6, 0.25), (math.cos(a) * 0.68, 0.9, math.sin(a) * 0.68), cloak, mat="Fabric")
    m.blk("Sign", (0.8, 0.35, 0.06), (0, 3.9, 0.9), (240, 220, 60), mat="Neon")
    return m


@model
def the_mannequin_duke():
    m = Model("the_mannequin_duke")
    skin = (235, 225, 210)
    velvet = (100, 40, 140)
    gold = (240, 195, 70)
    # stand
    m.cyl("StandBase", 0.15, 1.6, (0, 0.08, 0), (40, 40, 45), mat="Metal")
    m.cyl("StandPole", 0.8, 0.18, (0, 0.5, 0), (180, 180, 190), mat="Metal")
    # legs with breeches
    for s in (-1, 1):
        m.cyl("Leg", 1.2, 0.38, (s * 0.3, 1.2, 0), skin, refl=0.2)
        m.ell("Boot", (0.45, 0.6, 0.65), (s * 0.3, 0.75, -0.05), (30, 25, 25), refl=0.2)
    m.blk("Breeches", (1.0, 0.6, 0.6), (0, 1.95, 0), (240, 235, 220), mat="Fabric")
    # velvet coat with gold trim
    m.blk("Coat", (1.4, 1.6, 0.8), (0, 2.85, 0), velvet, mat="Fabric")
    m.blk("CoatTail", (1.3, 1.0, 0.3), (0, 2.0, 0.35), velvet, mat="Fabric")
    m.blk("TrimL", (0.12, 1.6, 0.05), (-0.18, 2.85, -0.42), gold, mat="Metal")
    m.blk("TrimR", (0.12, 1.6, 0.05), (0.18, 2.85, -0.42), gold, mat="Metal")
    for k in range(3):
        m.ball("Button", 0.12, (0, 3.3 - k * 0.35, -0.43), gold)
    m.cyl("Sash", 0.2, 1.45, (0, 2.6, 0), (200, 30, 50), mat="Fabric", R=rot(z=-25))
    for s in (-1, 1):
        m.blk("Epaulette", (0.45, 0.12, 0.6), (s * 0.75, 3.66, 0), gold, mat="Metal")
        m.cyl("Fringe", 0.2, 0.5, (s * 0.85, 3.52, 0), gold, mat="Metal")
    # ruff collar and head
    m.cyl("Ruff", 0.25, 1.15, (0, 3.75, 0), (250, 250, 250), mat="Fabric")
    m.cyl("Neck", 0.3, 0.35, (0, 3.95, 0), skin, refl=0.2)
    m.ell("Head", (0.8, 1.05, 0.85), (0, 4.5, 0), skin, refl=0.25)
    for s in (-1, 1):
        g = m.ball("EyeGlow", 0.15, (s * 0.17, 4.55, -0.4), (220, 140, 255), mat="Neon")
    m.ring("Monocle", (0.17, 4.55, -0.44), 0.16, 0.04, gold, normal="z", segments=8, mat="Metal")
    m.rod("MonocleChain", (0.3, 4.45, -0.42), (0.45, 3.9, -0.35), 0.02, gold)
    # top hat
    m.cyl("HatBrim", 0.08, 1.2, (0, 4.98, 0), (20, 20, 25))
    m.cyl("Hat", 0.9, 0.8, (0, 5.45, 0), (20, 20, 25))
    m.cyl("HatBand", 0.18, 0.82, (0, 5.1, 0), velvet)
    m.light(g, (200, 130, 255), 1.5, 8)
    m.sparkles(g, (220, 160, 255))
    # arms with cane
    for s in (-1, 1):
        m.rod("Arm", (s * 0.75, 3.5, 0), (s * 0.95, 2.7, -0.2), 0.3, velvet, mat="Fabric")
        m.ball("Joint", 0.24, (s * 0.95, 2.7, -0.2), skin, refl=0.2)
        m.rod("Forearm", (s * 0.95, 2.7, -0.2), (s * 0.95, 2.2, -0.55), 0.22, skin, refl=0.2)
        m.ball("Hand", 0.26, (s * 0.95, 2.15, -0.58), skin, refl=0.2)
    m.cyl("Cane", 2.1, 0.12, (0.95, 1.15, -0.62), (30, 25, 30))
    m.ball("CaneTop", 0.28, (0.95, 2.3, -0.62), gold, mat="Metal")
    return m
