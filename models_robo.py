# Robo family models (shiny appliances and robots with screws, LEDs and panels)
import math
from modelkit import Model, rot, Rx, Ry, Rz, WHITE, PUPIL, shade, ell_front, cyl_front, front_of

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


def screws(m, pts, d=0.08, color=(110, 110, 120), normal="z"):
    for p in pts:
        m.cyl("Screw", d * 0.4, d, p, color, normal, "Metal")


@model
def bolt_bug():
    m = Model("bolt_bug")
    shell = (60, 120, 220)
    dark = (30, 70, 150)
    m.ell("Shell", (1.7, 1.1, 2.0), (0, 0.85, 0.1), shell, mat="Metal", refl=0.3)
    m.ell("Belly", (1.4, 0.4, 1.7), (0, 0.45, 0.1), (60, 65, 80), mat="Metal")
    m.blk("ShellLine", (0.06, 0.6, 1.9), (0, 1.15, 0.12), dark, mat="Metal")
    # rivet rows along the wing cases and a lightning decal
    for s in (-1, 1):
        for k in range(4):
            m.ball("Rivet", 0.08, (s * 0.25, 1.33 - abs(k - 1.5) * 0.05, -0.45 + k * 0.38), (200, 205, 215), mat="Metal")
        m.blk("Decal", (0.06, 0.32, 0.12), (s * 0.82, 0.92, 0.0), (255, 220, 60), mat="Neon", R=rot(x=25))
        m.blk("Decal", (0.06, 0.28, 0.12), (s * 0.82, 0.72, 0.18), (255, 220, 60), mat="Neon", R=rot(x=-25))
    # big bolt on the back with a hex head and a thread
    m.cyl("Bolt", 0.3, 0.6, (0, 1.45, 0.25), (190, 190, 200), mat="Metal")
    for k in range(3):
        m.ring("Bolt", (0, 1.36 + k * 0.08, 0.25), 0.3, 0.035, (160, 160, 170), normal="y", segments=8, mat="Metal")
    m.cyl("BoltHead", 0.14, 0.38, (0, 1.62, 0.25), (160, 160, 170), mat="Metal")
    m.ell("Head", (1.1, 0.75, 0.8), (0, 0.75, -0.95), (50, 55, 70), mat="Metal")
    m.ell("Visor", (0.9, 0.34, 0.2), (0, 0.85, -1.27), (20, 25, 35), mat="Glass", refl=0.3)
    for s in (-1, 1):
        e = m.ell("EyeLED", (0.32, 0.26, 0.12), (s * 0.24, 0.85, -1.33), (255, 230, 60), mat="Neon")
        m.ell("Pupil", (0.1, 0.12, 0.04), (s * 0.24, 0.85, -1.4), (120, 90, 10))
        m.rod("Antenna", (s * 0.2, 1.05, -1.1), (s * 0.5, 1.6, -1.45), 0.06, (180, 180, 190), mat="Metal")
        m.ball("AntennaTip", 0.16, (s * 0.52, 1.64, -1.47), (120, 230, 255), mat="Neon")
        # mandibles
        m.chain("Fang", [(s * 0.3, 0.55, -1.25), (s * 0.28, 0.45, -1.5), (s * 0.12, 0.42, -1.6)], 0.09, (180, 185, 195), mat="Metal")
        # two-part legs with joints and pointy feet
        for k in (-1, 0, 1):
            knee = (s * 0.95, 0.5, 0.05 + k * 0.65)
            m.rod("Leg", (s * 0.6, 0.55, 0.1 + k * 0.6), knee, 0.1, (70, 70, 80), mat="Metal")
            m.ball("Knee", 0.14, knee, (200, 205, 215), mat="Metal")
            m.rod("Leg", knee, (s * 1.08, 0.05, 0.0 + k * 0.7), 0.08, (70, 70, 80), mat="Metal")
    m.light(e, (255, 230, 120), 0.8, 5)
    # charge meter on the back
    for k in range(3):
        m.blk("Charge", (0.3, 0.1, 0.05), (0, 0.95 + k * 0.15, 1.1), (120, 255, 120) if k < 2 else (60, 90, 60), mat="Neon")
    m.rbox("ChargeFrame", (0.4, 0.55, 0.04), (0, 1.1, 1.08), (40, 40, 50), 0.05, axis="z")
    return m


@model
def roomba_rex():
    m = Model("roomba_rex")
    green = (90, 180, 80)
    dgreen = (60, 130, 60)
    m.cyl("Vacuum", 0.45, 2.6, (0, 0.28, 0), (55, 55, 65), mat="Metal")
    m.ring("Bumper", (0, 0.25, 0), 1.3, 0.16, (30, 30, 35), normal="y", segments=18, mat="Rubber")
    m.cyl("VacuumRing", 0.1, 2.65, (0, 0.5, 0), (180, 180, 190), mat="Metal")
    m.cyl("VacuumTop", 0.06, 2.2, (0, 0.53, 0), (75, 75, 85), mat="Metal")
    m.cyl("Button", 0.08, 0.5, (0, 0.55, 0.65), (80, 220, 120), mat="Neon")
    m.ring("Button", (0, 0.57, 0.65), 0.28, 0.04, (200, 200, 210), normal="y", segments=10, mat="Metal")
    m.blk("Sensor", (0.8, 0.12, 0.08), (0, 0.38, -1.27), (20, 20, 25), mat="Glass", refl=0.4)
    for s in (-1, 1):
        m.ball("Led", 0.08, (s * 0.5, 0.55, -0.9), (255, 80, 80) if s < 0 else (80, 220, 255), mat="Neon")
        m.cyl("Brush", 0.06, 0.2, (s * 0.9, 0.08, -0.9), (220, 200, 60))
        for k in range(4):
            a = k * math.pi / 4
            m.rod("Brush", (s * 0.9, 0.08, -0.9), (s * 0.9 + math.cos(a) * 0.4, 0.05, -0.9 + math.sin(a) * 0.4), 0.04, (230, 210, 80))
    # dust bin with crumbs
    m.blk("DustBin", (0.8, 0.2, 0.3), (0, 0.4, 1.25), (120, 200, 255), mat="Glass", tr=0.4)
    # dino on top with belly plates, spikes, teeth and tiny clawed arms
    m.ell("DinoBody", (1.1, 1.1, 1.4), (0, 1.1, 0.25), green)
    m.ell("Belly", (0.75, 0.8, 0.5), (0, 1.05, -0.22), (200, 220, 140))
    for k in range(3):
        m.blk("BellyPlate", (0.5 - k * 0.08, 0.04, 0.05), (0, 0.85 + k * 0.2, -0.46), (170, 190, 110))
    m.rbox("DinoHead", (0.9, 0.75, 1.2), (0, 1.85, -0.45), green, 0.15, axis="z")
    m.rbox("Jaw", (0.85, 0.25, 1.0), (0, 1.38, -0.55), (80, 160, 70), 0.1, R=rot(x=10), axis="z")
    m.blk("Mouth", (0.8, 0.12, 0.9), (0, 1.53, -0.6), (120, 40, 50))
    for k in range(5):
        m.wedge("Tooth", (0.09, 0.16, 0.1), (-0.32 + k * 0.16, 1.55, -1.03), WHITE, R=rot(x=180))
    for k in range(3):
        m.wedge("Tooth", (0.08, 0.12, 0.08), (-0.2 + k * 0.2, 1.52, -1.0), WHITE)
    m.eyes(2.05, -1.06, 0.45, 0.28, lid=green, iris=(240, 180, 40), z_back=0.0)
    m.brow(-0.22, 2.22, -1.06, 0.3, (40, 80, 40), -1, tilt=20, d=0.08)
    m.brow(0.22, 2.22, -1.06, 0.3, (40, 80, 40), 1, tilt=20, d=0.08)
    for s in (-1, 1):
        m.rod("TinyArm", (s * 0.45, 1.3, -0.25), (s * 0.55, 1.05, -0.6), 0.13, green)
        for k in (-1, 1):
            m.wedge("Claw", (0.05, 0.1, 0.08), (s * 0.55 + k * 0.05, 1.0, -0.66), WHITE, R=rot(x=180))
        m.ell("Nostril", (0.08, 0.06, 0.04), (s * 0.15, 2.0, -1.06), (40, 60, 40))
        m.ball("Spot", 0.18, (s * 0.45, 1.35, 0.45), dgreen)
    m.chain("Tail", [(0, 1.0, 0.9), (0, 0.85, 1.35), (0.1, 0.75, 1.7)], 0.3, green)
    m.ball("TailTip", 0.2, (0.12, 0.72, 1.82), green)
    for k in range(5):
        m.wedge("Spike", (0.08, 0.25, 0.25), (0, [2.32, 2.3, 1.81, 1.59, 1.37][k], -0.3 + k * 0.32), (250, 160, 60) if k % 2 else (60, 130, 60))
    return m


@model
def toaster_knight():
    m = Model("toaster_knight")
    chrome = (205, 210, 220)
    dark = (60, 60, 70)
    m.rbox("Body", (2.0, 1.5, 1.3), (0, 1.25, 0), chrome, 0.22, mat="Metal", refl=0.4)
    m.blk("BodyTrim", (2.05, 0.15, 1.35), (0, 0.55, 0), dark, mat="Metal")
    m.blk("CrumbTray", (1.4, 0.08, 0.2), (0, 0.6, -0.68), (40, 40, 45), mat="Metal")
    m.ell("Shine", (0.12, 1.0, 0.04), (-0.62, 1.35, -0.66), WHITE, tr=0.5)
    for s in (-1, 1):
        m.blk("Slot", (0.22, 0.06, 1.0), (s * 0.4, 2.01, 0), (30, 30, 35))
        m.rbox("Toast", (0.16, 0.85, 0.95), (s * 0.4, 2.2, 0), (225, 180, 110), 0.12, axis="x")
        m.ell("Crust", (0.18, 0.2, 0.97), (s * 0.4, 2.6, 0), (160, 100, 50))
        m.blk("ToastBrown", (0.17, 0.3, 0.6), (s * 0.4, 2.3, 0), (205, 150, 80))
    # knightly visor with glowing slits
    m.rbox("Visor", (1.5, 0.48, 0.1), (0, 1.45, -0.67), (40, 40, 50), 0.1, mat="Metal", axis="z")
    for s in (-1, 1):
        m.blk("EyeLED", (0.38, 0.12, 0.05), (s * 0.35, 1.47, -0.73), (255, 140, 40), mat="Neon", R=rot(z=s * 8))
    m.blk("VisorRidge", (0.08, 0.5, 0.06), (0, 1.45, -0.74), (90, 90, 100), mat="Metal")
    screws(m, [(-0.72, 1.62, -0.73), (0.72, 1.62, -0.73), (-0.72, 1.28, -0.73), (0.72, 1.28, -0.73)])
    m.blk("Lever", (0.2, 0.2, 0.5), (1.05, 1.4, 0.1), (40, 40, 45))
    m.blk("Lever", (0.06, 0.6, 0.06), (1.02, 1.4, 0.1), (20, 20, 22))
    for k, c in enumerate([(220, 60, 60), (60, 200, 90)]):
        m.cyl("Dial", 0.1, 0.28, (0.55 + k * 0.35, 0.85, -0.67), (40, 40, 45), axis="z")
        m.blk("DialMark", (0.04, 0.12, 0.02), (0.55 + k * 0.35, 0.9, -0.73), c, mat="Neon")
    # helmet plume between the toast slices
    m.cyl("Plume", 0.3, 0.16, (0, 2.1, 0.0), (240, 200, 60), mat="Metal")
    for k, c in enumerate([(220, 40, 40), (250, 240, 235), (220, 40, 40)]):
        m.ell("Plume", (0.2, 0.55, 0.65), (0, 2.75 + k * 0.04, 0.15 + k * 0.25), c, R=rot(x=10 + k * 22), mat="Fabric")
    # power cord tail with a plug
    m.chain("Tail", [(0.4, 0.8, 0.65), (0.6, 0.5, 1.0), (0.4, 0.2, 1.3), (0.75, 0.1, 1.55)], 0.07, (30, 30, 35), joints=False)
    m.rbox("TailTip", (0.22, 0.18, 0.28), (0.8, 0.12, 1.65), (240, 240, 245), 0.05, axis="z")
    # legs with greaves and armored boots
    for s in (-1, 1):
        m.cyl("Leg", 0.5, 0.3, (s * 0.5, 0.3, 0), (70, 70, 80), mat="Metal")
        m.cyl("Greave", 0.22, 0.36, (s * 0.5, 0.38, 0), chrome, mat="Metal")
        m.rbox("Foot", (0.45, 0.2, 0.7), (s * 0.5, 0.1, -0.12), (50, 50, 60), 0.08, mat="Metal")
        m.ell("Toe", (0.42, 0.2, 0.3), (s * 0.5, 0.12, -0.42), chrome, mat="Metal")
    # butter knife sword
    m.rod("Arm", (1.0, 1.25, 0), (1.35, 1.05, -0.4), 0.2, (80, 80, 90), mat="Metal")
    m.ball("Shoulder", 0.3, (1.0, 1.25, 0), chrome, mat="Metal")
    m.mitt((1.38, 1.03, -0.42), 0.3, (80, 80, 90), 1, mat="Metal")
    m.blk("KnifeHandle", (0.16, 0.5, 0.16), (1.4, 1.2, -0.44), (60, 40, 30))
    m.blk("KnifeGuard", (0.4, 0.08, 0.2), (1.4, 1.47, -0.44), (240, 200, 60), mat="Metal")
    m.blk("KnifeBlade", (0.08, 1.4, 0.3), (1.4, 2.2, -0.44), (225, 228, 235), mat="Metal", refl=0.35)
    m.wedge("KnifeEdge", (0.08, 0.25, 0.3), (1.4, 3.02, -0.44), (225, 228, 235), mat="Metal")
    m.blk("Butter", (0.12, 0.2, 0.32), (1.4, 2.55, -0.44), (255, 230, 120))
    # toast shield with jam and a butter pat
    m.rod("Arm", (-1.0, 1.25, 0), (-1.3, 1.1, -0.45), 0.2, (80, 80, 90), mat="Metal")
    m.ball("Shoulder", 0.3, (-1.0, 1.25, 0), chrome, mat="Metal")
    m.mitt((-1.3, 1.1, -0.47), 0.28, (80, 80, 90), -1, mat="Metal", thumb=False)
    m.rbox("ShieldCrust", (1.1, 1.2, 0.12), (-1.3, 1.2, -0.85), (165, 105, 50), 0.2, R=rot(y=20), axis="z")
    m.rbox("ToastShield", (0.95, 1.05, 0.14), (-1.31, 1.2, -0.89), (225, 180, 110), 0.15, R=rot(y=20), axis="z")
    m.ell("Jam", (0.5, 0.45, 0.1), (-1.33, 1.25, -0.97), (180, 30, 60), R=rot(y=20), refl=0.2)
    m.ell("Jam", (0.2, 0.25, 0.08), (-1.18, 0.98, -1.03), (180, 30, 60), R=rot(y=20), refl=0.2)
    m.blk("ShieldBoss", (0.25, 0.12, 0.2), (-1.45, 1.55, -0.98), (255, 230, 120), R=rot(y=20))
    return m


@model
def laundry_bot_3000():
    m = Model("laundry_bot_3000")
    white = (240, 242, 248)
    m.rbox("Body", (2.2, 2.2, 1.8), (0, 1.35, 0), white, 0.25, refl=0.1)
    m.blk("Panel", (2.2, 0.4, 0.1), (0, 2.25, -0.9), (190, 195, 210))
    for k, c in enumerate([(255, 80, 80), (80, 200, 255), (120, 230, 120)]):
        m.cyl("PanelButton", 0.06, 0.18, (-0.7 + k * 0.3, 2.25, -0.97), c, axis="z", mat="Neon")
    m.cyl("PanelDial", 0.12, 0.3, (0.65, 2.25, -0.97), (90, 90, 100), axis="z")
    m.blk("DialMark", (0.03, 0.1, 0.02), (0.65, 2.3, -1.04), (255, 80, 80))
    m.blk("Drawer", (0.5, 0.25, 0.06), (0.15, 2.25, -0.96), (220, 225, 235))
    # round door with a chrome ring, swirling water and socks
    m.ring("DoorRing", (0, 1.25, -0.92), 0.7, 0.16, (170, 175, 190), normal="z", segments=16, mat="Metal")
    m.cyl("Door", 0.1, 1.25, (0, 1.25, -0.97), (120, 190, 255), axis="z", mat="Glass", tr=0.35, refl=0.35)
    m.ell("Water", (1.1, 0.5, 0.2), (0, 1.0, -0.88), (60, 140, 230))
    m.ell("Foam", (1.0, 0.15, 0.22), (0, 1.22, -0.88), (230, 245, 255))
    m.ell("SockInside", (0.25, 0.45, 0.12), (-0.25, 1.35, -0.86), (240, 80, 120), R=rot(z=40))
    m.ell("Sock2", (0.25, 0.45, 0.12), (0.28, 1.2, -0.86), (90, 200, 120), R=rot(z=-30))
    m.blk("DoorHandle", (0.12, 0.35, 0.1), (0.72, 1.25, -1.0), (150, 155, 165), mat="Metal")
    # head with screen eyes and a little antenna
    m.rbox("Head", (1.6, 0.7, 1.2), (0, 2.8, -0.1), (225, 228, 238), 0.2)
    m.rbox("EyeBand", (1.4, 0.42, 0.05), (0, 2.8, -0.71), (30, 40, 60), 0.12, axis="z")
    for s in (-1, 1):
        m.rbox("Eye", (0.3, 0.24, 0.04), (s * 0.35, 2.82, -0.75), (80, 220, 255), 0.08, mat="Neon", axis="z")
        m.blk("Eye", (0.1, 0.1, 0.03), (s * 0.35 + 0.06, 2.86, -0.78), WHITE, mat="Neon")
    m.blk("ScreenMouth", (0.3, 0.05, 0.03), (0, 2.66, -0.75), (80, 220, 255), mat="Neon")
    m.rod("Antenna", (0.5, 3.15, 0.1), (0.62, 3.5, 0.15), 0.05, (170, 175, 185), mat="Metal")
    m.ball("AntennaTip", 0.14, (0.63, 3.53, 0.15), (120, 230, 120), mat="Neon")
    # arms with elbows and clothes-peg hands
    for s in (-1, 1):
        m.rod("Arm", (s * 1.1, 1.8, 0), (s * 1.5, 1.2, -0.4), 0.22, (170, 175, 185), mat="Metal")
        m.ball("Elbow", 0.32, (s * 1.1, 1.8, 0), (150, 155, 165), mat="Metal")
        m.ball("Hand", 0.24, (s * 1.52, 1.18, -0.42), (150, 155, 165), mat="Metal")
        m.blk("Peg", (0.08, 0.45, 0.14), (s * 1.5, 0.95, -0.45), (240, 200, 60), R=rot(z=s * 14))
        m.blk("Peg", (0.08, 0.45, 0.14), (s * 1.6, 0.95, -0.45), (240, 200, 60), R=rot(z=s * 4))
        m.ring("Peg", (s * 1.56, 1.02, -0.45), 0.06, 0.03, (200, 200, 210), normal="z", segments=6, mat="Metal")
    # treads with wheels
    for s in (-1, 1):
        m.rbox("Tread", (0.6, 0.38, 1.9), (s * 0.85, 0.19, 0), (40, 40, 45), 0.18, mat="Rubber", axis="x")
        for z in (-0.65, 0, 0.65):
            m.cyl("TreadHub", 0.62, 0.22, (s * 0.85, 0.19, z), (150, 150, 160), axis="x", mat="Metal")
    # a drain hose and bubbles
    m.chain("Hose", [(-0.8, 0.8, 0.9), (-0.9, 0.5, 1.15), (-0.7, 0.2, 1.3)], 0.12, (200, 200, 210), joints=False)
    for (x, y, z, d) in [(-0.6, 3.4, 0.0, 0.35), (0.2, 3.6, 0.3, 0.25), (0.7, 3.3, -0.2, 0.3), (-0.1, 3.85, -0.1, 0.2), (-0.9, 3.0, -0.3, 0.18)]:
        m.ball("Bubble", d, (x, y, z), (220, 240, 255), mat="Glass", tr=0.4, refl=0.4)
        m.ball("BubbleShine", d * 0.25, (x - d * 0.2, y + d * 0.2, z - d * 0.3), WHITE)
    # the back: a service panel with screws, a water inlet with a hose, a lint filter and a sticker
    m.rbox("ServicePanel", (1.6, 1.4, 0.05), (0, 1.4, 0.91), (225, 228, 235), 0.1, axis="z")
    for (x, y) in [(-0.7, 2.0), (0.7, 2.0), (-0.7, 0.8), (0.7, 0.8)]:
        m.ball("Screw", 0.07, (x, y, 0.94), (150, 155, 165), mat="Metal")
    for k in range(5):
        m.blk("LintSlot", (0.7, 0.06, 0.03), (0.2, 1.85 - k * 0.12, 0.94), (150, 155, 170))
    m.cyl("Inlet", 0.15, 0.22, (-0.45, 1.25, 0.98), (180, 180, 190), axis="z", mat="Metal")
    m.chain("InletHose", [(-0.45, 1.25, 1.05), (-0.55, 1.0, 1.25), (-0.3, 0.7, 1.4), (0.1, 0.65, 1.45)], 0.12, (90, 140, 220), joints=False)
    m.rbox("Sticker", (0.45, 0.3, 0.03), (0.35, 0.95, 0.94), (120, 200, 255), 0.05, axis="z")
    m.blk("StickerText", (0.3, 0.04, 0.02), (0.35, 0.98, 0.96), (255, 255, 255))
    m.blk("StickerText", (0.22, 0.04, 0.02), (0.35, 0.9, 0.96), (255, 255, 255))
    return m


@model
def microwave_mage():
    m = Model("microwave_mage")
    shell = (225, 228, 235)
    hat = (50, 60, 170)
    m.rbox("Body", (2.6, 1.7, 1.7), (0, 1.35, 0), shell, 0.2, refl=0.15)
    win = m.blk("Window", (1.6, 1.15, 0.06), (-0.35, 1.38, -0.86), (255, 170, 70), mat="Neon", tr=0.15)
    m.rbox("WindowFrame", (1.78, 1.32, 0.05), (-0.35, 1.38, -0.84), (40, 40, 45), 0.12, axis="z")
    m.light(win, (255, 170, 80), 1.8, 8)
    # glass grid and a turntable inside
    m.cyl("Turntable", 0.04, 1.0, (-0.35, 0.95, -0.55), (230, 230, 240), mat="Glass", tr=0.3)
    # face on the window: friendly wise eyes, brows and a smile
    for s in (-1, 1):
        m.ell("Eye", (0.3, 0.32, 0.05), (-0.35 + s * 0.35, 1.55, -0.9), (60, 30, 20))
        m.ell("Glint", (0.1, 0.1, 0.03), (-0.35 + s * 0.35 + 0.06, 1.6, -0.93), (255, 240, 220))
        m.brow(-0.35 + s * 0.35, 1.8, -0.9, 0.3, (60, 30, 20), s, tilt=-10, d=0.06)
    m.grin(1.2, -0.9, 0.5, curve=0.2, color=(60, 30, 20), d=0.06)
    # keypad, timer and a handle
    m.blk("Keypad", (0.6, 1.2, 0.06), (0.9, 1.38, -0.86), (60, 60, 70))
    for k in range(9):
        m.rbox("Key", (0.13, 0.11, 0.04), (0.76 + (k % 3) * 0.14, 1.65 - (k // 3) * 0.17, -0.9), (200, 200, 210), 0.03, axis="z")
    m.blk("Timer", (0.44, 0.18, 0.04), (0.9, 1.88, -0.9), (120, 255, 140), mat="Neon")
    m.rbox("StartButton", (0.4, 0.14, 0.04), (0.9, 1.0, -0.9), (80, 200, 100), 0.04, axis="z")
    m.blk("DoorHandle", (0.08, 0.9, 0.12), (0.5, 1.38, -0.92), (170, 175, 185), mat="Metal")
    # wizard hat with stars and a moon
    m.cyl("HatBrim", 0.1, 2.1, (0, 2.27, 0), hat)
    m.ring("HatBrim", (0, 2.28, 0), 1.04, 0.07, (255, 220, 80), normal="y", segments=16, mat="Metal")
    for k in range(4):
        m.cyl("HatCone", 0.45, 1.2 - k * 0.26, (0.1 * k, 2.55 + k * 0.42, 0.04 * k), hat, R=rot(z=-7 * k))
    m.cyl("HatBand", 0.12, 1.22, (0, 2.42, 0), (255, 220, 80))
    m.ball("HatTip", 0.2, (0.42, 4.15, 0.2), (255, 230, 80), mat="Neon")
    # stars stuck on the hat's surface (front and one on the back), facing outward
    for (x, y, side) in [(-0.4, 2.7, -1), (0.35, 3.1, -1), (0.0, 2.6, 1), (0.2, 3.5, -1)]:
        j = min(3, max(0, int(round((y - 2.55) / 0.42))))
        r, cx, cz = (1.2 - j * 0.26) / 2, 0.1 * j, 0.04 * j
        dx = max(-r * 0.9, min(r * 0.9, x - cx))
        z = cz + side * (math.sqrt(r * r - dx * dx) + 0.017)
        yaw = math.degrees(math.atan2(dx, -side * math.sqrt(r * r - dx * dx)))
        for k in range(3):
            m.blk("HatStar", (0.2, 0.05, 0.03), (cx + dx, y, z), (255, 230, 80), mat="Neon", R=rot(y=-yaw if side < 0 else yaw) @ rot(z=k * 60))
    m.ell("Moon", (0.3, 0.3, 0.05), (-0.3, 3.15, -0.38), (255, 240, 160), mat="Neon")
    m.ell("Moon", (0.26, 0.26, 0.06), (-0.22, 3.2, -0.4), hat)
    # a fluffy popcorn beard
    m.ell("Beard", (1.0, 0.8, 0.3), (-0.35, 0.55, -0.88), (245, 240, 230), mat="Fabric")
    m.scatter("Beard", (-0.35, 0.55, -0.88), (1.0, 0.8, 0.3), 10, [(255, 250, 235), (250, 230, 170)], seed=4, d=0.16, shape="dot", front_only=True, ymin=-1)
    # arms and a wand with a glowing star
    for s in (-1, 1):
        m.rod("Arm", (s * 1.3, 1.5, 0), (s * 1.7, 1.15, -0.45), 0.2, (150, 150, 160), mat="Metal")
        m.ball("Shoulder", 0.3, (s * 1.3, 1.5, 0), (130, 130, 140), mat="Metal")
        m.cyl("Cuff", 0.12, 0.3, (s * 1.62, 1.22, -0.36), hat, R=rot(y=s * 48) @ rot(z=s * 40))
        m.mitt((s * 1.72, 1.13, -0.47), 0.3, (150, 150, 160), s, mat="Metal")
    m.rod("Wand", (1.72, 1.0, -0.47), (1.95, 2.3, -0.7), 0.1, (90, 60, 40))
    m.rod("WandBand", (1.88, 1.9, -0.63), (1.9, 2.0, -0.65), 0.13, (255, 220, 80), mat="Metal")
    star = m.ell("WandStar", (0.4, 0.4, 0.1), (1.98, 2.45, -0.72), (255, 240, 120), mat="Neon")
    for k in range(5):
        a = k * 2 * math.pi / 5 + math.pi / 2
        m.wedge("WandGlow", (0.06, 0.18, 0.08), (1.98 + math.cos(a) * 0.22, 2.45 + math.sin(a) * 0.22, -0.72), (255, 240, 120), mat="Neon", R=rot(z=math.degrees(a) - 90))
    m.sparkles(star, (255, 240, 140))
    for s in (-1, 1):
        m.rbox("Foot", (0.5, 0.25, 0.5), (s * 0.85, 0.13, 0), (60, 60, 70), 0.1)
    # the back: a vent grille, a warning sticker, the cord and plug, and a star the mage drew on itself
    for k in range(6):
        m.blk("Vent", (1.1, 0.07, 0.05), (0.1, 1.85 - k * 0.14, 0.86), (60, 60, 68))
    m.rbox("WarnSticker", (0.5, 0.4, 0.03), (-0.75, 0.95, 0.86), (250, 210, 60), 0.05, axis="z")
    m.wedge("WarnMark", (0.03, 0.22, 0.2), (-0.75, 0.95, 0.88), (40, 40, 40), R=rot(y=90))
    m.chain("PowerCord", [(0.6, 0.85, 0.87), (0.75, 0.6, 1.05), (0.55, 0.3, 1.25), (0.15, 0.22, 1.35)], 0.08, (35, 35, 40), joints=False)
    m.rbox("Plug", (0.2, 0.14, 0.24), (0.02, 0.22, 1.36), (240, 240, 235), 0.04, axis="x")
    for k in range(5):
        a = math.radians(90 + k * 72)
        m.blk("BackStar", (0.07, 0.3, 0.02), (-0.85 + math.cos(a) * 0.12, 1.6 + math.sin(a) * 0.12, 0.865), (255, 220, 80), mat="Neon", R=rot(z=math.degrees(a) - 90))
    return m


@model
def mecha_fridge():
    m = Model("mecha_fridge")
    mint = (170, 230, 210)
    chrome = (200, 205, 215)
    steel = (140, 145, 155)
    m.rbox("Fridge", (2.2, 3.2, 1.7), (0, 2.6, 0), mint, 0.25, refl=0.15)
    m.blk("DoorGap", (2.22, 0.06, 1.72), (0, 3.35, 0), (110, 160, 145))
    for y in (2.5, 3.85):
        m.rbox("Handle", (0.15, 0.62, 0.15), (0.85, y, -0.95), chrome, 0.05, mat="Metal")
    m.rbox("Visor", (1.6, 0.38, 0.06), (0, 3.85, -0.87), (30, 40, 60), 0.12, axis="z")
    v = m.blk("VisorGlow", (1.4, 0.15, 0.04), (0, 3.85, -0.91), (120, 220, 255), mat="Neon")
    m.blk("VisorGlow", (0.3, 0.06, 0.03), (-0.45, 3.92, -0.93), WHITE, mat="Neon")
    m.light(v, (140, 220, 255), 1.2, 7)
    for (x, y, c) in [(-0.6, 2.7, (240, 80, 80)), (-0.2, 2.2, (250, 210, 60)), (0.3, 2.85, (90, 160, 250)), (-0.5, 1.75, (120, 220, 120))]:
        m.rbox("Magnet", (0.3, 0.3, 0.06), (x, y, -0.88), c, 0.08, R=rot(z=15), axis="z")
    m.blk("Note", (0.45, 0.55, 0.03), (0.2, 1.85, -0.87), (255, 250, 200), R=rot(z=-8))
    for k in range(3):
        m.blk("NoteLine", (0.32, 0.03, 0.02), (0.2, 2.0 - k * 0.12, -0.89), (120, 140, 200), R=rot(z=-8))
    m.blk("Drawing", (0.35, 0.3, 0.03), (-0.25, 1.45, -0.87), (255, 255, 255), R=rot(z=10))
    m.ball("Drawing", 0.12, (-0.25, 1.48, -0.89), (240, 200, 60))
    # frost on top and ice crystals
    m.rbox("Frost", (2.1, 0.08, 1.6), (0, 4.22, 0), (235, 250, 255), 0.25)
    for (x, z) in [(-0.6, -0.3), (0.5, 0.2), (0.0, 0.5)]:
        m.ell("Crystal", (0.15, 0.4, 0.15), (x, 4.4, z), (220, 245, 255), mat="Glass", tr=0.2)
    # shoulder pauldrons and arms with pistons
    for s in (-1, 1):
        m.ball("Shoulder", 0.85, (s * 1.35, 3.5, 0), (120, 125, 135), mat="Metal")
        m.ell("Pauldron", (0.9, 0.4, 1.0), (s * 1.4, 3.85, 0), mint, R=rot(z=s * -20))
        m.ball("PauldronRivet", 0.1, (s * 1.45, 3.98, -0.45), chrome, mat="Metal")
    m.rod("Arm", (-1.4, 3.4, 0), (-1.6, 2.4, -0.5), 0.5, steel, mat="Metal")
    m.rod("Piston", (-1.25, 3.2, -0.2), (-1.45, 2.4, -0.6), 0.12, chrome, mat="Metal")
    m.rbox("Fist", (0.78, 0.78, 0.78), (-1.62, 2.05, -0.65), (110, 115, 125), 0.15, mat="Metal")
    for k in range(4):
        m.ball("Knuckle", 0.2, (-1.62 + (k - 1.5) * 0.17, 2.3, -1.03), (150, 155, 165), mat="Metal")
    m.rod("Arm", (1.4, 3.4, 0), (1.65, 2.6, -0.6), 0.5, steel, mat="Metal")
    m.rod("Piston", (1.25, 3.2, -0.2), (1.5, 2.6, -0.7), 0.12, chrome, mat="Metal")
    # ice cannon with frosty rings
    m.cyl("Cannon", 1.2, 0.62, (1.7, 2.45, -1.0), (90, 95, 105), axis="z", mat="Metal")
    for k in range(3):
        m.cyl("CannonRing", 0.08, 0.7, (1.7, 2.45, -0.6 - k * 0.3), (200, 235, 255), axis="z", mat="Metal")
    m.cyl("CannonMouth", 0.1, 0.5, (1.7, 2.45, -1.6), (200, 240, 255), axis="z", mat="Neon")
    m.blk("IceCube", (0.35, 0.35, 0.35), (1.7, 2.45, -1.75), (200, 240, 255), mat="Glass", tr=0.25, R=rot(20, 30, 0))
    # mech legs with knee joints and clawed feet
    for s in (-1, 1):
        m.cyl("Hip", 0.5, 0.7, (s * 0.6, 0.95, 0), (120, 125, 135), axis="x", mat="Metal")
        m.cyl("Leg", 0.9, 0.5, (s * 0.6, 0.55, 0), steel, mat="Metal")
        m.cyl("Kneepad", 0.25, 0.58, (s * 0.6, 0.62, -0.05), mint)
        m.rbox("Foot", (0.8, 0.3, 1.2), (s * 0.6, 0.15, -0.2), (90, 95, 105), 0.12, mat="Metal")
        for k in (-1, 0, 1):
            m.ell("Toe", (0.22, 0.22, 0.3), (s * 0.6 + k * 0.25, 0.14, -0.8), (110, 115, 125), mat="Metal")
    base = m.ball("ColdAir", 0.3, (0, 0.4, -0.5), (220, 240, 255), tr=1)
    m.smoke(base, (230, 245, 255), 0.06, 0.2, 2)
    m.blk("Vent", (1.6, 0.25, 0.05), (0, 1.15, -0.87), (60, 70, 80))
    for k in range(4):
        m.blk("VentSlat", (1.5, 0.03, 0.03), (0, 1.07 + k * 0.055, -0.9), (40, 45, 55))
    # the back: the black condenser coils every fridge has, a compressor, a cord and a rating sticker
    m.rbox("CoilPanel", (1.7, 2.4, 0.05), (0, 2.55, 0.86), (40, 45, 50), 0.08, axis="z")
    for k in range(9):
        m.cyl("Coil", 1.5, 0.06, (0, 1.55 + k * 0.25, 0.9), (25, 25, 30), axis="x", mat="Metal")
    for x in (-0.6, 0.0, 0.6):
        m.blk("CoilWire", (0.03, 2.2, 0.03), (x, 2.55, 0.93), (90, 90, 95), mat="Metal")
    m.cyl("Compressor", 0.45, 0.55, (0.45, 1.25, 0.72), (30, 30, 35), axis="x", mat="Metal")
    m.rbox("RatingSticker", (0.5, 0.32, 0.03), (-0.55, 1.22, 0.87), (245, 245, 240), 0.05, axis="z")
    for (y, w) in [(1.3, 0.38), (1.22, 0.3), (1.14, 0.34)]:
        m.blk("StickerText", (w, 0.03, 0.02), (-0.55, y, 0.89), (60, 60, 70))
    m.chain("PowerCord", [(-0.3, 1.1, 0.88), (-0.35, 0.8, 1.05), (-0.1, 0.5, 1.15), (0.25, 0.42, 1.2)], 0.08, (30, 30, 35), joints=False)
    m.rbox("Plug", (0.2, 0.14, 0.24), (0.38, 0.42, 1.2), (240, 240, 235), 0.04, axis="x")
    return m


@model
def mega_blender_prime():
    m = Model("mega_blender_prime")
    steel = (150, 155, 165)
    m.rbox("Motor", (2.4, 1.3, 2.0), (0, 1.75, 0), (40, 40, 50), 0.25, mat="Metal", refl=0.2)
    m.blk("MotorTrim", (2.45, 0.15, 2.05), (0, 2.35, 0), (200, 205, 215), mat="Metal")
    for k, c in enumerate([(255, 70, 70), (255, 200, 60), (90, 220, 120), (90, 160, 255)]):
        m.cyl("Button", 0.08, 0.26, (-0.6 + k * 0.4, 1.6, -1.02), c, axis="z", mat="Neon")
        m.ring("Button", (-0.6 + k * 0.4, 1.6, -1.04), 0.15, 0.03, (200, 205, 215), normal="z", segments=8, mat="Metal")
    m.cyl("SpeedDial", 0.12, 0.45, (0, 1.95, -1.04), (200, 205, 215), axis="z", mat="Metal")
    m.blk("DialMark", (0.04, 0.16, 0.03), (0.08, 2.02, -1.1), (255, 70, 70), mat="Neon", R=rot(z=-30))
    # pitcher with measure marks, a smoothie with fruit chunks and spinning blades
    m.cyl("Pitcher", 2.6, 2.0, (0, 3.75, 0), (210, 235, 250), mat="Glass", tr=0.55, refl=0.35)
    for k in range(4):
        m.blk("Measure", (0.2 + (k % 2) * 0.15, 0.04, 0.03), (-0.6, 2.9 + k * 0.5, -0.98), WHITE)
    m.cyl("Smoothie", 1.6, 1.8, (0, 3.25, 0), (220, 80, 170))
    m.ell("SmoothieTop", (1.8, 0.4, 1.8), (0, 4.05, 0), (240, 120, 190))
    for (x, y, z, c) in [(-0.4, 3.0, -0.6, (250, 220, 60)), (0.5, 3.5, -0.5, (120, 200, 90)), (0.1, 2.8, -0.75, (250, 120, 60)), (-0.55, 3.7, -0.5, (200, 40, 70)), (0.6, 2.9, -0.4, (250, 220, 60))]:
        m.blk("Fruit", (0.35, 0.35, 0.35), (x, y, z), c, R=rot(30, 40, 10))
    for k in range(4):
        m.blk("Blade", (1.1, 0.06, 0.2), (0, 2.6, 0), (220, 225, 235), mat="Metal", R=rot(y=k * 45, x=10))
    m.cyl("BladeHub", 0.2, 0.3, (0, 2.6, 0), (180, 185, 195), mat="Metal")
    # straw and a fruit slice on the rim
    m.rod("Straw", (0.4, 3.6, 0.3), (0.65, 5.2, 0.45), 0.12, (90, 220, 255))
    m.cyl("Slice", 0.08, 0.6, (-0.85, 5.0, -0.4), (255, 220, 60), axis="z", R=rot(y=30))
    m.cyl("Slice", 0.09, 0.48, (-0.85, 5.0, -0.4), (255, 245, 170), axis="z", R=rot(y=30))
    m.cyl("Handle", 2.0, 0.35, (1.25, 3.8, 0), (40, 40, 50), mat="Metal")
    m.rod("HandleTop", (0.9, 4.75, 0), (1.25, 4.75, 0), 0.3, (40, 40, 50), mat="Metal")
    m.rod("HandleTop", (0.9, 2.85, 0), (1.25, 2.85, 0), 0.3, (40, 40, 50), mat="Metal")
    # lid head with angry glowing eyes
    m.cyl("JarLid", 0.5, 2.1, (0, 5.3, 0), (40, 40, 50), mat="Metal")
    m.ring("JarLidRing", (0, 5.06, 0), 1.05, 0.08, (200, 205, 215), normal="y", segments=16, mat="Metal")
    m.cyl("LidCap", 0.4, 0.8, (0, 5.7, 0), (60, 60, 70), mat="Metal")
    m.ball("LidCap", 0.3, (0, 5.95, 0), (255, 70, 70), mat="Neon")
    for s in (-1, 1):
        e = m.blk("EyeGlow", (0.5, 0.18, 0.06), (s * 0.4, 5.32, -1.06), (255, 50, 50), mat="Neon", R=rot(z=s * -15))
        m.blk("EyeGlow", (0.7, 0.3, 0.04), (s * 0.4, 5.32, -1.04), (255, 120, 120), mat="Neon", R=rot(z=s * -15), tr=0.7)
    m.grin(5.12, -1.06, 0.6, curve=-0.12, color=(255, 70, 70), d=0.06)
    m.light(e, (255, 60, 60), 1.5, 8)
    # mech arms with pistons and pincer claws, heavy legs
    for s in (-1, 1):
        m.ball("Shoulder", 0.8, (s * 1.45, 2.2, 0), (90, 95, 105), mat="Metal")
        m.rod("Arm", (s * 1.5, 2.1, 0), (s * 1.85, 1.2, -0.6), 0.45, steel, mat="Metal")
        m.rod("Piston", (s * 1.35, 2.0, -0.25), (s * 1.7, 1.25, -0.75), 0.12, (210, 215, 225), mat="Metal")
        m.rbox("Claw", (0.6, 0.6, 0.6), (s * 1.9, 0.95, -0.75), (90, 95, 105), 0.12, mat="Metal")
        for k in (-1, 1):
            m.rod("Pincer", (s * 1.9 + k * 0.18, 0.75, -0.95), (s * 1.9 + k * 0.12, 0.45, -1.2), 0.12, (200, 205, 215), mat="Metal")
        m.cyl("Leg", 1.1, 0.6, (s * 0.7, 0.6, 0), steel, mat="Metal")
        m.cyl("Kneepad", 0.2, 0.66, (s * 0.7, 0.75, 0), (255, 70, 70), mat="Metal")
        m.rbox("Foot", (0.9, 0.3, 1.3), (s * 0.7, 0.15, -0.2), (60, 60, 70), 0.12, mat="Metal")
    screws(m, [(-1.0, 1.25, -1.02), (1.0, 1.25, -1.02), (-1.0, 2.2, -1.02), (1.0, 2.2, -1.02)], 0.1)
    return m


@model
def omega_microwave():
    m = Model("omega_microwave")
    gold = (245, 200, 70)
    dgold = (180, 140, 50)
    purple = (190, 90, 255)
    m.rbox("Body", (3.2, 2.2, 2.2), (0, 2.1, 0), gold, 0.3, mat="Metal", refl=0.4)
    # ornate trim bands and corner gems
    for y in (1.05, 3.15):
        m.blk("Trim", (3.0, 0.12, 2.22), (0, y, 0), dgold, mat="Metal")
    for x in (-1.45, 1.45):
        for y in (1.15, 3.05):
            m.gem("Gem", (x, y, -1.12), 0.2, purple, glow=True)
    win = m.blk("Window", (2.0, 1.5, 0.06), (-0.4, 2.15, -1.11), purple, mat="Neon", tr=0.1)
    m.rbox("WindowFrame", (2.18, 1.68, 0.05), (-0.4, 2.15, -1.09), (60, 40, 20), 0.15, mat="Metal", axis="z")
    # swirling energy and the omega mark
    for k in range(2):
        m.ring("Swirl", (-0.4, 2.15, -1.15), 0.62 - k * 0.15, 0.05, (230, 180, 255), normal="z", segments=12, mat="Neon", R=rot(z=k * 20))
    m.ring("Omega", (-0.4, 2.25, -1.17), 0.42, 0.1, (255, 245, 200), normal="z", segments=12, mat="Neon")
    m.blk("OmegaFoot", (0.3, 0.1, 0.05), (-0.75, 1.8, -1.17), (255, 245, 200), mat="Neon")
    m.blk("OmegaFoot", (0.3, 0.1, 0.05), (-0.05, 1.8, -1.17), (255, 245, 200), mat="Neon")
    m.light(win, (190, 110, 255), 2.5, 12)
    # eyes glaring through the window
    for s in (-1, 1):
        m.ell("EyeGlow", (0.36, 0.18, 0.04), (-0.4 + s * 0.42, 2.6, -1.18), (255, 255, 255), mat="Neon", R=rot(z=s * -12))
    m.blk("Keypad", (0.7, 1.6, 0.06), (1.15, 2.15, -1.11), (70, 50, 25), mat="Metal")
    for k in range(9):
        m.rbox("Key", (0.16, 0.13, 0.04), (0.98 + (k % 3) * 0.17, 2.55 - (k // 3) * 0.22, -1.15), (255, 230, 150), 0.04, mat="Neon", axis="z")
    m.blk("Timer", (0.55, 0.2, 0.04), (1.15, 2.85, -1.15), (255, 80, 80), mat="Neon")
    # floating halo rings and a power core
    for k, y in enumerate((1.0, 3.5)):
        m.ring("HaloRing", (0, y, 0), 2.0 - k * 0.3, 0.1, (255, 220, 120), normal="y", segments=18, mat="Neon")
    crown = m.ball("Core", 0.55, (0, 3.85, 0), (255, 240, 180), mat="Neon")
    m.ring("Core", (0, 3.85, 0), 0.38, 0.06, gold, normal="x", segments=10, mat="Metal")
    m.ring("Core", (0, 3.85, 0), 0.38, 0.06, gold, normal="z", segments=10, mat="Metal")
    m.sparkles(crown, (255, 220, 120))
    # crown spikes on top
    for k in range(5):
        x = -1.0 + k * 0.5
        m.wedge("Crown", (0.3, 0.45 + 0.15 * (k == 2), 0.3), (x, 3.45 + 0.07 * (k == 2), 0.4), gold, mat="Metal")
    # heavy plated arms and legs
    for s in (-1, 1):
        m.cyl("Leg", 1.0, 0.72, (s * 0.9, 0.5, 0), dgold, mat="Metal")
        m.cyl("Kneepad", 0.25, 0.8, (s * 0.9, 0.6, 0), gold, mat="Metal")
        m.rbox("Foot", (1.0, 0.3, 1.4), (s * 0.9, 0.15, -0.2), (120, 90, 30), 0.15, mat="Metal")
        m.ball("Shoulder", 0.85, (s * 1.8, 2.7, 0), (200, 160, 60), mat="Metal")
        m.ell("Pauldron", (1.0, 0.45, 1.1), (s * 1.85, 3.05, 0), gold, mat="Metal", R=rot(z=s * -20))
        m.gem("PauldronGem", (s * 1.95, 3.15, -0.5), 0.16, purple, glow=True)
        m.rod("Arm", (s * 1.85, 2.6, 0), (s * 2.1, 1.7, -0.7), 0.5, (200, 160, 60), mat="Metal")
        m.cyl("Bracer", 0.3, 0.6, (s * 2.05, 1.88, -0.56), dgold, mat="Metal", R=rot(x=38, z=s * -16))
        m.ball("Fist", 0.78, (s * 2.12, 1.6, -0.78), (180, 140, 50), mat="Metal")
        for k in range(3):
            m.ball("Knuckle", 0.2, (s * 2.12 + (k - 1) * 0.2, 1.8, -1.1), gold, mat="Metal")
    m.cyl("Antenna", 0.8, 0.12, (1.2, 3.6, 0.5), (200, 160, 60), mat="Metal")
    m.ball("AntennaTip", 0.3, (1.2, 4.05, 0.5), purple, mat="Neon")
    return m
