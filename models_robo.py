# Robo family models (appliances and robots)
import math
from modelkit import Model, rot, WHITE, PUPIL

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


@model
def bolt_bug():
    m = Model("bolt_bug")
    shell = (60, 120, 220)
    m.ell("Shell", (1.7, 1.1, 2.0), (0, 0.85, 0.1), shell, mat="Metal", refl=0.25)
    m.blk("ShellLine", (0.06, 0.6, 1.9), (0, 1.15, 0.12), (30, 70, 150), mat="Metal")
    m.cyl("Bolt", 0.25, 0.6, (0, 1.45, 0.25), (190, 190, 200), mat="Metal")
    m.cyl("BoltHead", 0.12, 0.35, (0, 1.6, 0.25), (160, 160, 170), mat="Metal")
    m.ell("Head", (1.1, 0.75, 0.8), (0, 0.75, -0.95), (50, 55, 70), mat="Metal")
    for s in (-1, 1):
        e = m.ell("EyeLED", (0.32, 0.26, 0.12), (s * 0.24, 0.85, -1.33), (255, 230, 60), mat="Neon")
        m.rod("Antenna", (s * 0.2, 1.05, -1.1), (s * 0.5, 1.6, -1.45), 0.06, (180, 180, 190), mat="Metal")
        m.ball("AntennaTip", 0.16, (s * 0.52, 1.64, -1.47), (120, 230, 255), mat="Neon")
        for k in (-1, 0, 1):
            m.rod("Leg", (s * 0.6, 0.55, 0.1 + k * 0.6), (s * 1.0, 0.1, 0.0 + k * 0.7), 0.1, (70, 70, 80), mat="Metal")
    m.light(e, (255, 230, 120), 0.8, 5)
    # charge meter on the back
    for k in range(3):
        m.blk("Charge", (0.3, 0.1, 0.05), (0, 0.95 + k * 0.15, 1.1), (120, 255, 120), mat="Neon")
    return m


@model
def roomba_rex():
    m = Model("roomba_rex")
    m.cyl("Vacuum", 0.45, 2.6, (0, 0.28, 0), (55, 55, 65), mat="Metal")
    m.cyl("VacuumRing", 0.1, 2.65, (0, 0.5, 0), (180, 180, 190), mat="Metal")
    m.cyl("Button", 0.08, 0.5, (0, 0.53, 0.6), (80, 220, 120), mat="Neon")
    for s in (-1, 1):
        m.cyl("Brush", 0.06, 0.7, (s * 0.9, 0.08, -0.9), (220, 200, 60))
    # dino head and body on top
    green = (90, 180, 80)
    m.ell("DinoBody", (1.1, 1.1, 1.4), (0, 1.1, 0.25), green)
    m.blk("DinoHead", (0.9, 0.75, 1.2), (0, 1.85, -0.45), green)
    m.blk("Jaw", (0.85, 0.25, 1.0), (0, 1.38, -0.55), (80, 160, 70), R=rot(x=10))
    for k in range(4):
        m.wedge("Tooth", (0.1, 0.16, 0.1), (-0.3 + k * 0.2, 1.53, -1.0), WHITE, R=rot(x=180))
    m.eyes(2.05, -1.06, 0.45, 0.28, lid=green, angry=12)
    for s in (-1, 1):
        m.rod("TinyArm", (s * 0.45, 1.3, -0.25), (s * 0.55, 1.05, -0.6), 0.12, green)
        m.ell("Nostril", (0.08, 0.06, 0.04), (s * 0.15, 2.0, -1.06), (40, 60, 40))
    m.chain("Tail", [(0, 1.0, 0.9), (0, 0.85, 1.35), (0.1, 0.75, 1.7)], 0.3, green)
    for k in range(3):
        m.wedge("Spike", (0.08, 0.25, 0.25), (0, 1.75 - k * 0.15, 0.2 + k * 0.3), (60, 130, 60))
    return m


@model
def toaster_knight():
    m = Model("toaster_knight")
    chrome = (205, 210, 220)
    m.blk("Body", (2.0, 1.5, 1.3), (0, 1.25, 0), chrome, mat="Metal", refl=0.35)
    m.blk("BodyTrim", (2.05, 0.15, 1.35), (0, 0.55, 0), (60, 60, 70), mat="Metal")
    for s in (-1, 1):
        m.blk("Slot", (0.2, 0.06, 1.0), (s * 0.4, 2.01, 0), (30, 30, 35))
        m.blk("Toast", (0.16, 0.85, 0.95), (s * 0.4, 2.2, 0), (225, 180, 110))
        m.blk("Crust", (0.18, 0.12, 0.97), (s * 0.4, 2.62, 0), (160, 100, 50))
    m.blk("Visor", (1.5, 0.45, 0.1), (0, 1.45, -0.67), (40, 40, 50), mat="Metal")
    for s in (-1, 1):
        m.blk("EyeLED", (0.38, 0.12, 0.05), (s * 0.35, 1.45, -0.73), (255, 140, 40), mat="Neon")
    m.blk("Lever", (0.2, 0.2, 0.5), (1.05, 1.4, 0.1), (40, 40, 45))
    m.cyl("Dial", 0.1, 0.3, (0.65, 0.85, -0.67), (40, 40, 45), axis="z")
    # helmet plume
    m.ell("Plume", (0.2, 0.6, 0.9), (0, 2.85, 0.1), (220, 40, 40), R=rot(x=-10))
    # legs
    for s in (-1, 1):
        m.cyl("Leg", 0.5, 0.3, (s * 0.5, 0.3, 0), (70, 70, 80), mat="Metal")
        m.blk("Foot", (0.45, 0.2, 0.7), (s * 0.5, 0.1, -0.12), (50, 50, 60), mat="Metal")
    # butter knife sword
    m.rod("Arm", (1.0, 1.25, 0), (1.35, 1.05, -0.4), 0.2, (80, 80, 90), mat="Metal")
    m.ball("Hand", 0.28, (1.38, 1.03, -0.42), (80, 80, 90), mat="Metal")
    m.blk("KnifeHandle", (0.16, 0.5, 0.16), (1.4, 1.2, -0.44), (60, 40, 30))
    m.blk("KnifeBlade", (0.08, 1.4, 0.3), (1.4, 2.1, -0.44), (225, 228, 235), mat="Metal", refl=0.3)
    m.blk("Butter", (0.12, 0.2, 0.32), (1.4, 2.5, -0.44), (255, 230, 120))
    # toast shield
    m.rod("Arm", (-1.0, 1.25, 0), (-1.3, 1.1, -0.45), 0.2, (80, 80, 90), mat="Metal")
    m.blk("ShieldCrust", (1.1, 1.2, 0.12), (-1.3, 1.2, -0.85), (165, 105, 50), R=rot(y=20))
    m.blk("ToastShield", (0.95, 1.05, 0.14), (-1.31, 1.2, -0.89), (225, 180, 110), R=rot(y=20))
    m.ell("Jam", (0.45, 0.4, 0.1), (-1.33, 1.25, -0.97), (180, 30, 60), R=rot(y=20))
    return m


@model
def laundry_bot_3000():
    m = Model("laundry_bot_3000")
    white = (240, 242, 248)
    m.blk("Body", (2.2, 2.2, 1.8), (0, 1.35, 0), white, refl=0.1)
    m.blk("Panel", (2.2, 0.4, 0.1), (0, 2.25, -0.9), (190, 195, 210))
    for k, c in enumerate([(255, 80, 80), (80, 200, 255), (120, 230, 120)]):
        m.cyl("PanelButton", 0.06, 0.18, (-0.7 + k * 0.3, 2.25, -0.97), c, axis="z", mat="Neon")
    m.cyl("PanelDial", 0.12, 0.3, (0.65, 2.25, -0.97), (90, 90, 100), axis="z")
    # round door with water and socks
    m.cyl("DoorRing", 0.15, 1.5, (0, 1.25, -0.9), (170, 175, 190), axis="z", mat="Metal")
    m.cyl("Door", 0.1, 1.25, (0, 1.25, -0.97), (120, 190, 255), axis="z", mat="Glass", tr=0.35, refl=0.3)
    m.ell("Water", (1.1, 0.5, 0.2), (0, 1.0, -0.88), (60, 140, 230))
    m.ell("Sock", (0.25, 0.45, 0.12), (-0.25, 1.35, -0.86), (240, 80, 120), R=rot(z=40))
    m.ell("Sock2", (0.25, 0.45, 0.12), (0.28, 1.2, -0.86), (90, 200, 120), R=rot(z=-30))
    # eyes on the top panel
    for s in (-1, 1):
        m.ell("EyeScreen", (0.42, 0.3, 0.06), (s * 0.45, 2.75, -0.92), (60, 200, 255), mat="Neon")
    m.blk("Head", (1.6, 0.7, 1.2), (0, 2.8, -0.1), (225, 228, 238))
    m.blk("EyeBand", (1.4, 0.4, 0.05), (0, 2.8, -0.71), (30, 40, 60))
    for s in (-1, 1):
        m.blk("Eye", (0.3, 0.22, 0.04), (s * 0.35, 2.8, -0.75), (80, 220, 255), mat="Neon")
    # arms with clothes pegs
    for s in (-1, 1):
        m.rod("Arm", (s * 1.1, 1.8, 0), (s * 1.5, 1.2, -0.4), 0.22, (170, 175, 185), mat="Metal")
        m.ball("Elbow", 0.3, (s * 1.1, 1.8, 0), (150, 155, 165), mat="Metal")
        m.blk("Peg", (0.15, 0.45, 0.15), (s * 1.55, 0.95, -0.45), (240, 200, 60), R=rot(z=s * 10))
    # treads
    for s in (-1, 1):
        m.blk("Tread", (0.6, 0.35, 1.9), (s * 0.85, 0.18, 0), (40, 40, 45), mat="Rubber")
    # bubbles
    for (x, y, z, d) in [(-0.6, 3.4, 0.0, 0.35), (0.2, 3.6, 0.3, 0.25), (0.7, 3.3, -0.2, 0.3), (-0.1, 3.85, -0.1, 0.2)]:
        m.ball("Bubble", d, (x, y, z), (220, 240, 255), mat="Glass", tr=0.4, refl=0.4)
    return m


@model
def microwave_mage():
    m = Model("microwave_mage")
    shell = (225, 228, 235)
    m.blk("Body", (2.6, 1.7, 1.7), (0, 1.35, 0), shell, refl=0.1)
    win = m.blk("Window", (1.6, 1.15, 0.06), (-0.35, 1.38, -0.86), (255, 170, 70), mat="Neon", tr=0.15)
    m.blk("WindowFrame", (1.75, 1.3, 0.05), (-0.35, 1.38, -0.84), (40, 40, 45))
    m.light(win, (255, 170, 80), 1.8, 8)
    # face on the window
    for s in (-1, 1):
        m.ell("Eye", (0.28, 0.3, 0.05), (-0.35 + s * 0.35, 1.55, -0.9), (60, 30, 20))
    m.ell("Mouth", (0.5, 0.15, 0.05), (-0.35, 1.15, -0.9), (60, 30, 20))
    m.blk("Keypad", (0.6, 1.2, 0.06), (0.9, 1.38, -0.86), (60, 60, 70))
    for k in range(9):
        m.blk("Key", (0.12, 0.1, 0.04), (0.76 + (k % 3) * 0.14, 1.7 - (k // 3) * 0.17, -0.9), (200, 200, 210))
    m.blk("Timer", (0.4, 0.16, 0.04), (0.9, 1.88, -0.9), (120, 255, 140), mat="Neon")
    # wizard hat with stars
    hat = (50, 60, 170)
    m.cyl("HatBrim", 0.1, 2.1, (0, 2.27, 0), hat)
    for k in range(4):
        m.cyl("HatCone", 0.45, 1.2 - k * 0.26, (0.1 * k, 2.55 + k * 0.42, 0.04 * k), hat, R=rot(z=-7 * k))
    m.ball("HatTip", 0.2, (0.42, 4.15, 0.2), (255, 230, 80), mat="Neon")
    for (x, y, z) in [(-0.4, 2.7, -0.55), (0.35, 3.1, -0.4), (0.0, 2.6, 0.58)]:
        m.ell("Star", (0.2, 0.2, 0.05), (x, y, z), (255, 230, 80), mat="Neon")
    # beard of bread crumbs
    m.ell("Beard", (1.0, 0.8, 0.3), (-0.35, 0.55, -0.88), (245, 240, 230), mat="Fabric")
    # arms and a wand
    for s in (-1, 1):
        m.rod("Arm", (s * 1.3, 1.5, 0), (s * 1.7, 1.15, -0.45), 0.2, (150, 150, 160), mat="Metal")
        m.ball("Hand", 0.3, (s * 1.72, 1.13, -0.47), (150, 150, 160), mat="Metal")
    m.rod("Wand", (1.72, 1.0, -0.47), (1.95, 2.3, -0.7), 0.1, (90, 60, 40))
    star = m.ell("WandStar", (0.4, 0.4, 0.1), (1.98, 2.45, -0.72), (255, 240, 120), mat="Neon")
    m.sparkles(star, (255, 240, 140))
    for s in (-1, 1):
        m.blk("Foot", (0.5, 0.25, 0.5), (s * 0.85, 0.13, 0), (60, 60, 70))
    return m


@model
def mecha_fridge():
    m = Model("mecha_fridge")
    mint = (170, 230, 210)
    chrome = (200, 205, 215)
    m.blk("Fridge", (2.2, 3.2, 1.7), (0, 2.6, 0), mint, refl=0.15)
    m.blk("DoorGap", (2.22, 0.06, 1.72), (0, 3.35, 0), (110, 160, 145))
    for y in (2.5, 3.85):
        m.blk("Handle", (0.15, 0.6, 0.15), (0.85, y, -0.95), chrome, mat="Metal")
    m.blk("Visor", (1.6, 0.35, 0.06), (0, 3.85, -0.87), (30, 40, 60))
    v = m.blk("VisorGlow", (1.4, 0.15, 0.04), (0, 3.85, -0.91), (120, 220, 255), mat="Neon")
    m.light(v, (140, 220, 255), 1.2, 7)
    for (x, y, c) in [(-0.6, 2.7, (240, 80, 80)), (-0.2, 2.2, (250, 210, 60)), (0.3, 2.85, (90, 160, 250)), (-0.5, 1.75, (120, 220, 120))]:
        m.blk("Magnet", (0.3, 0.3, 0.06), (x, y, -0.88), c, R=rot(z=15))
    m.blk("Note", (0.45, 0.55, 0.03), (0.2, 1.85, -0.87), (255, 250, 200), R=rot(z=-8))
    # shoulders and arms
    for s in (-1, 1):
        m.ball("Shoulder", 0.85, (s * 1.35, 3.5, 0), (120, 125, 135), mat="Metal")
    m.rod("Arm", (-1.4, 3.4, 0), (-1.6, 2.4, -0.5), 0.5, (140, 145, 155), mat="Metal")
    m.blk("Fist", (0.75, 0.75, 0.75), (-1.62, 2.05, -0.65), (110, 115, 125), mat="Metal")
    m.rod("Arm", (1.4, 3.4, 0), (1.65, 2.6, -0.6), 0.5, (140, 145, 155), mat="Metal")
    m.cyl("Cannon", 1.2, 0.6, (1.7, 2.45, -1.0), (90, 95, 105), axis="z", mat="Metal")
    m.blk("IceCube", (0.35, 0.35, 0.35), (1.7, 2.45, -1.7), (200, 240, 255), mat="Glass", tr=0.25, R=rot(20, 30, 0))
    # mech legs
    for s in (-1, 1):
        m.cyl("Hip", 0.5, 0.7, (s * 0.6, 0.95, 0), (120, 125, 135), axis="x", mat="Metal")
        m.cyl("Leg", 0.9, 0.5, (s * 0.6, 0.55, 0), (140, 145, 155), mat="Metal")
        m.blk("Foot", (0.8, 0.3, 1.2), (s * 0.6, 0.15, -0.2), (90, 95, 105), mat="Metal")
    base = m.ball("ColdAir", 0.3, (0, 0.4, -0.5), (220, 240, 255), tr=1)
    m.smoke(base, (230, 245, 255), 0.06, 0.2, 2)
    m.blk("Vent", (1.6, 0.25, 0.05), (0, 1.15, -0.87), (60, 70, 80))
    return m


@model
def mega_blender_prime():
    m = Model("mega_blender_prime")
    m.blk("Motor", (2.4, 1.3, 2.0), (0, 1.75, 0), (40, 40, 50), mat="Metal", refl=0.2)
    m.blk("MotorTrim", (2.45, 0.15, 2.05), (0, 2.35, 0), (200, 205, 215), mat="Metal")
    for k, c in enumerate([(255, 70, 70), (255, 200, 60), (90, 220, 120), (90, 160, 255)]):
        m.cyl("Button", 0.08, 0.26, (-0.6 + k * 0.4, 1.6, -1.02), c, axis="z", mat="Neon")
    m.cyl("Pitcher", 2.6, 2.0, (0, 3.75, 0), (210, 235, 250), mat="Glass", tr=0.55, refl=0.3)
    m.cyl("Smoothie", 1.6, 1.8, (0, 3.25, 0), (220, 80, 170))
    m.ell("SmoothieTop", (1.8, 0.4, 1.8), (0, 4.05, 0), (240, 120, 190))
    for (x, y, z, c) in [(-0.4, 3.0, -0.6, (250, 220, 60)), (0.5, 3.5, -0.5, (120, 200, 90)), (0.1, 2.8, -0.75, (250, 120, 60))]:
        m.blk("Fruit", (0.35, 0.35, 0.35), (x, y, z), c, R=rot(30, 40, 10))
    for k in range(4):
        m.blk("Blade", (1.1, 0.06, 0.2), (0, 2.6, 0), (220, 225, 235), mat="Metal", R=rot(y=k * 45, x=10))
    m.cyl("Handle", 2.0, 0.35, (1.25, 3.8, 0), (40, 40, 50), mat="Metal")
    m.rod("HandleTop", (0.9, 4.75, 0), (1.25, 4.75, 0), 0.3, (40, 40, 50), mat="Metal")
    # lid head with angry eyes
    m.cyl("Lid", 0.5, 2.1, (0, 5.3, 0), (40, 40, 50), mat="Metal")
    m.cyl("LidCap", 0.4, 0.8, (0, 5.7, 0), (60, 60, 70), mat="Metal")
    for s in (-1, 1):
        e = m.blk("EyeGlow", (0.5, 0.18, 0.06), (s * 0.4, 5.32, -1.06), (255, 50, 50), mat="Neon", R=rot(z=s * -15))
    m.light(e, (255, 60, 60), 1.5, 8)
    # mech arms and legs
    for s in (-1, 1):
        m.ball("Shoulder", 0.8, (s * 1.45, 2.2, 0), (90, 95, 105), mat="Metal")
        m.rod("Arm", (s * 1.5, 2.1, 0), (s * 1.85, 1.2, -0.6), 0.45, (150, 155, 165), mat="Metal")
        m.blk("Claw", (0.6, 0.6, 0.6), (s * 1.9, 0.95, -0.75), (90, 95, 105), mat="Metal")
        m.cyl("Leg", 1.1, 0.6, (s * 0.7, 0.6, 0), (150, 155, 165), mat="Metal")
        m.blk("Foot", (0.9, 0.3, 1.3), (s * 0.7, 0.15, -0.2), (60, 60, 70), mat="Metal")
    return m


@model
def omega_microwave():
    m = Model("omega_microwave")
    gold = (245, 200, 70)
    m.blk("Body", (3.2, 2.2, 2.2), (0, 2.1, 0), gold, mat="Metal", refl=0.35)
    win = m.blk("Window", (2.0, 1.5, 0.06), (-0.4, 2.15, -1.11), (190, 90, 255), mat="Neon", tr=0.1)
    m.blk("WindowFrame", (2.15, 1.65, 0.05), (-0.4, 2.15, -1.09), (60, 40, 20), mat="Metal")
    # omega mark made of blocks
    m.ring("Omega", (-0.4, 2.25, -1.17), 0.42, 0.1, (255, 245, 200), normal="z", segments=10, mat="Neon")
    m.blk("OmegaFoot", (0.3, 0.1, 0.05), (-0.75, 1.8, -1.17), (255, 245, 200), mat="Neon")
    m.blk("OmegaFoot", (0.3, 0.1, 0.05), (-0.05, 1.8, -1.17), (255, 245, 200), mat="Neon")
    m.light(win, (190, 110, 255), 2.5, 12)
    m.blk("Keypad", (0.7, 1.6, 0.06), (1.15, 2.15, -1.11), (70, 50, 25), mat="Metal")
    for k in range(9):
        m.blk("Key", (0.15, 0.12, 0.04), (0.98 + (k % 3) * 0.17, 2.55 - (k // 3) * 0.22, -1.15), (255, 230, 150), mat="Neon")
    # floating rings
    for k, y in enumerate((1.0, 3.5)):
        m.ring("HaloRing", (0, y, 0), 2.0 - k * 0.3, 0.1, (255, 220, 120), normal="y", segments=16, mat="Neon")
    crown = m.ball("Core", 0.5, (0, 3.8, 0), (255, 240, 180), mat="Neon")
    m.sparkles(crown, (255, 220, 120))
    # heavy legs and arms
    for s in (-1, 1):
        m.cyl("Leg", 1.0, 0.7, (s * 0.9, 0.5, 0), (180, 140, 50), mat="Metal")
        m.blk("Foot", (1.0, 0.3, 1.4), (s * 0.9, 0.15, -0.2), (120, 90, 30), mat="Metal")
        m.ball("Shoulder", 0.8, (s * 1.8, 2.7, 0), (200, 160, 60), mat="Metal")
        m.rod("Arm", (s * 1.85, 2.6, 0), (s * 2.1, 1.7, -0.7), 0.5, (200, 160, 60), mat="Metal")
        m.ball("Fist", 0.75, (s * 2.12, 1.6, -0.78), (180, 140, 50), mat="Metal")
    m.cyl("Antenna", 0.8, 0.12, (1.2, 3.6, 0.5), (200, 160, 60), mat="Metal")
    m.ball("AntennaTip", 0.3, (1.2, 4.05, 0.5), (190, 90, 255), mat="Neon")
    return m
