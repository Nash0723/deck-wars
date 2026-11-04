# Buildings, hero figurines and the bot opponent
import math
from modelkit import ell_top, top_of, Model, rot, Rx, Ry, Rz, WHITE, PUPIL, shade, ell_front, cyl_front, front_of

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


# Buildings (kind "gadget") are built about 3 studs wide; the client shrinks them to fit one tile.

@model
def spiked_fence():
    m = Model("spiked_fence", kind="gadget")
    wood = (150, 105, 60)
    for k in range(5):
        x = -1.3 + k * 0.65
        c = shade(wood, 1.0 + 0.06 * ((k * 7) % 3 - 1))
        h = 1.1 - 0.06 * (k % 2)
        m.blk("Plank", (0.45, h, 0.16), (x, h / 2, 0), c, mat="WoodPlanks", R=rot(z=(k - 2) * 1.5))
        m.blk("PlankTip", (0.32, 0.32, 0.16), (x, h, 0), c, mat="WoodPlanks", R=rot(z=45))
        m.blk("Grain", (0.03, h * 0.7, 0.02), (x - 0.1, h * 0.45, -0.09), shade(c, 0.8))
        m.ell("Knot", (0.09, 0.12, 0.02), (x + 0.08, 0.35 + 0.1 * (k % 3), -0.09), shade(c, 0.7))
        m.cyl("Spike", 0.5, 0.12, (x, 1.45, 0), (190, 195, 205), mat="Metal")
        m.ring("SpikeBand", (x, 1.22, 0), 0.08, 0.04, (110, 110, 120), normal="y", segments=6, mat="Metal")
        m.ell("SpikeTip", (0.12, 0.28, 0.12), (x, 1.76, 0), (215, 220, 230), mat="Metal", refl=0.3)
    for y in (0.3, 0.85):
        m.blk("Rail", (3.1, 0.18, 0.12), (0, y, 0.14), (120, 80, 45), mat="Wood")
    for x in (-1.3, -0.65, 0, 0.65, 1.3):
        for y in (0.3, 0.85):
            m.cyl("Nail", 0.05, 0.07, (x, y, -0.1), (90, 90, 100), axis="z", mat="Metal")
    # warning sign hanging off a nail, and some barbed wire
    m.rbox("Sign", (0.72, 0.42, 0.06), (0.55, 0.65, -0.12), (250, 230, 120), 0.06, R=rot(z=-6), axis="z")
    m.blk("SignMark", (0.08, 0.22, 0.03), (0.55, 0.69, -0.16), (200, 40, 40))
    m.blk("SignMark", (0.08, 0.07, 0.03), (0.56, 0.52, -0.16), (200, 40, 40))
    m.chain("Wire", [(-1.5, 1.2, -0.1), (-0.9, 1.1, -0.12), (-0.3, 1.2, -0.1), (0.3, 1.1, -0.12), (0.9, 1.2, -0.1), (1.5, 1.1, -0.12)], 0.03, (120, 120, 130), mat="Metal", joints=False)
    for x in (-1.2, -0.6, 0.0, 0.6, 1.2):
        m.blk("Barb", (0.12, 0.03, 0.03), (x, 1.15, -0.12), (120, 120, 130), mat="Metal", R=rot(z=45))
    m.ell("Grass", (0.5, 0.2, 0.3), (-1.1, 0.05, -0.2), (90, 150, 70), mat="Grass")
    m.ell("Grass", (0.4, 0.18, 0.3), (1.0, 0.05, -0.2), (90, 150, 70), mat="Grass")
    return m


@model
def bouncy_castle():
    m = Model("bouncy_castle", kind="gadget")
    pink = (250, 120, 170)
    yellow = (255, 220, 80)
    blue = (90, 160, 240)
    m.rbox("Floor", (3.0, 0.35, 1.7), (0, 0.18, 0), blue, 0.17, mat="Rubber")
    m.ell("FloorPuff", (2.7, 0.2, 1.4), (0, 0.36, 0), shade(blue, 1.15), mat="Rubber")
    m.rbox("Wall", (2.4, 0.9, 1.2), (0, 0.75, 0.1), pink, 0.2, mat="Rubber")
    # inflated seams on the wall
    for x in (-0.6, 0.0, 0.6):
        m.cyl("Seam", 0.9, 0.08, (x, 0.75, -0.5), shade(pink, 0.85), mat="Rubber")
    for s in (-1, 1):
        m.cyl("Tower", 1.6, 0.75, (s * 1.25, 0.95, 0.2), yellow, mat="Rubber")
        for y in (0.55, 1.05, 1.5):
            m.ring("TowerRing", (s * 1.25, y, 0.2), 0.385, 0.07, shade(yellow, 0.88), normal="y", segments=10, mat="Rubber", outer=True)
        m.ell("TowerTop", (0.88, 0.62, 0.88), (s * 1.25, 1.95, 0.2), pink, mat="Rubber")
        m.ball("Bump", 0.3, (s * 1.25, 2.3, 0.2), blue, mat="Rubber")
        m.ell("Window", (0.22, 0.3, 0.05), (s * 1.25, 1.25, -0.18), (60, 90, 190))
    for k in range(4):
        m.ell("Crenel", (0.45, 0.45, 0.45), (-0.75 + k * 0.5, 1.3, 0.1), (250, 140, 185), mat="Rubber")
    m.ell("Door", (0.8, 0.6, 0.1), (0, 0.65, -0.52), (60, 90, 190))
    m.ring("DoorTrim", (0, 0.68, -0.55), 0.38, 0.06, yellow, normal="z", segments=10, mat="Rubber")
    # a happy face on the front wall, pennants and a blower hose
    m.eyes(1.02, -0.53, 0.5, 0.16, lid=None, iris=(60, 90, 190))
    m.cheeks(0.92, -0.53, 0.9, 0.14)
    for k in range(5):
        x = -1.0 + k * 0.5
        m.wedge("Pennant", (0.04, 0.2, 0.22), (x, 1.62, -0.35), [(255, 90, 90), (90, 220, 120), (255, 220, 80), (90, 160, 240), (200, 120, 255)][k], R=rot(y=90, z=180))
    m.rod("Bunting", (-1.25, 1.75, -0.35), (1.25, 1.75, -0.35), 0.03, (240, 240, 240))
    m.cyl("Flag", 0.6, 0.05, (1.25, 2.65, 0.2), (200, 200, 210), mat="Metal")
    m.wedge("FlagCloth", (0.03, 0.25, 0.45), (1.46, 2.82, 0.2), (90, 220, 120), mat="Fabric", R=rot(y=90))
    m.chain("Hose", [(1.2, 0.3, 0.8), (1.45, 0.15, 1.0), (1.6, 0.12, 0.6)], 0.16, (60, 60, 70), joints=False)
    return m


@model
def lemonade_stand():
    m = Model("lemonade_stand", kind="gadget")
    wood = (200, 150, 90)
    dark = (170, 120, 70)
    m.blk("Counter", (2.8, 1.0, 1.1), (0, 0.5, 0.1), wood, mat="WoodPlanks")
    for x in (-0.9, 0.0, 0.9):
        m.blk("Board", (0.03, 0.95, 0.02), (x, 0.5, -0.46), shade(wood, 0.8))
    m.blk("CounterTop", (3.0, 0.12, 1.25), (0, 1.06, 0.1), dark, mat="Wood")
    m.rbox("Banner", (2.4, 0.45, 0.06), (0, 0.6, -0.47), (255, 240, 120), 0.08, axis="z")
    for k in range(5):
        m.ball("Lemon", 0.22, (-0.8 + k * 0.4, 0.6, -0.52), (255, 220, 50))
        m.ell("LemonLeaf", (0.1, 0.05, 0.04), (-0.74 + k * 0.4, 0.72, -0.55), (80, 170, 70), R=rot(z=-30))
    for s in (-1, 1):
        m.blk("Post", (0.12, 1.4, 0.12), (s * 1.35, 1.75, 0.55), dark, mat="Wood")
        m.blk("Post", (0.12, 1.15, 0.12), (s * 1.35, 1.65, -0.35), dark, mat="Wood")
    for k in range(6):
        c = (255, 255, 255) if k % 2 == 0 else (240, 200, 40)
        m.blk("Awning", (0.48, 0.08, 1.1), (-1.2 + k * 0.48, 2.45, 0.2), c, mat="Fabric", R=rot(x=-14))
        m.ell("AwningScallop", (0.44, 0.2, 0.06), (-1.2 + k * 0.48, 2.25, -0.35), c, mat="Fabric")
    # pitcher with ice and lemon slices, cups, a price sign and a tip jar
    m.cyl("Pitcher", 0.6, 0.45, (-0.6, 1.42, 0.1), (255, 245, 150), mat="Glass", tr=0.3)
    m.cyl("PitcherLemonade", 0.45, 0.4, (-0.6, 1.36, 0.1), (255, 230, 80))
    m.cyl("LemonSlice", 0.03, 0.22, (-0.6, 1.62, -0.05), (255, 240, 120), axis="z")
    for (dx, dz) in [(-0.07, 0.05), (0.08, 0.12)]:
        m.blk("Ice", (0.08, 0.08, 0.08), (-0.6 + dx, 1.6, 0.1 + dz), (230, 245, 255), mat="Glass", tr=0.2, R=rot(20, 30, 0))
    m.rod("PitcherHandle", (-0.35, 1.6, 0.1), (-0.32, 1.3, 0.1), 0.06, (255, 245, 150), mat="Glass")
    for k in range(3):
        m.cyl("Cup", 0.35, 0.22, (0.2 + k * 0.35, 1.3, -0.05), (250, 250, 250))
        m.cyl("CupStripe", 0.06, 0.23, (0.2 + k * 0.35, 1.32, -0.05), (240, 200, 40))
    m.rbox("PriceSign", (0.5, 0.35, 0.04), (0.2, 1.45, -0.3), (255, 255, 255), 0.05, axis="z", R=rot(x=-15))
    m.ball("PriceDot", 0.12, (0.2, 1.45, -0.33), (230, 60, 60))
    m.blk("Jar", (0.4, 0.4, 0.4), (1.0, 1.32, 0.3), (190, 230, 255), mat="Glass", tr=0.3)
    m.cyl("Coins", 0.12, 0.28, (1.0, 1.2, 0.3), (240, 200, 60), mat="Metal")
    m.cyl("JarLid", 0.06, 0.42, (1.0, 1.54, 0.3), (220, 60, 60))
    return m


@model
def disco_cactus():
    m = Model("disco_cactus", kind="gadget")
    m.cyl("Pot", 0.8, 1.0, (0, 0.4, 0), (210, 110, 60))
    m.cyl("PotRim", 0.2, 1.15, (0, 0.82, 0), (190, 95, 50))
    for k in range(3):
        m.ball("PotDot", 0.14, (-0.25 + k * 0.25, 0.4, -0.5), [(255, 220, 80), (90, 200, 255), (255, 120, 200)][k])
    m.cyl("Soil", 0.06, 0.95, (0, 0.9, 0), (90, 60, 40))
    green = (70, 170, 80)
    ridge = (55, 140, 65)
    m.ell("Cactus", (0.7, 1.8, 0.7), (0, 1.75, 0), green)
    # ridges running up the cactus
    for k in range(6):
        a = k * math.pi / 3 + math.pi / 6
        if math.sin(a) > -0.9:  # no ridge down the middle of the face
            m.ell("Ridge", (0.12, 1.7, 0.12), (math.cos(a) * 0.3, 1.75, math.sin(a) * 0.3), ridge)
    for s in (-1, 1):
        m.rod("ArmOut", (s * 0.3, 1.65, 0), (s * 0.7, 1.75, 0), 0.32, green)
        m.ell("ArmUp", (0.32, 0.8, 0.32), (s * 0.72, 2.1, 0), green)
    for (x, y, z) in [(-0.2, 2.2, -0.34), (0.2, 1.6, -0.34), (0.15, 2.45, -0.3), (-0.25, 1.4, -0.32), (0.3, 1.25, -0.25), (-0.32, 1.85, -0.22), (0.75, 2.3, -0.15), (-0.7, 2.0, -0.15)]:
        m.blk("ArmSpine" if abs(x) > 0.6 else "Spine", (0.03, 0.03, 0.16), (x, y, z), (250, 250, 230))
    m.eyes(1.95, -0.33, 0.3, 0.2, lid=green, iris=(150, 90, 40), z_back=0.02)
    m.grin(1.72, -0.34, 0.2, open_=True, curve=0.3)
    # star-shaped party shades, a flower and a disco ball on a stem
    for s in (-1, 1):
        m.rbox("Shades", (0.24, 0.16, 0.05), (s * 0.15, 2.02, -0.42), (255, 60, 200), 0.05, mat="Neon", axis="z")
    m.blk("Shades", (0.12, 0.04, 0.04), (0, 2.05, -0.42), (255, 60, 200), mat="Neon")
    m.cyl("Stem", 0.3, 0.06, (0, 2.68, 0), (180, 180, 190), mat="Metal")
    ball = m.ball("DiscoBall", 0.6, (0, 2.95, 0), (225, 225, 240), mat="Foil", refl=0.6)
    for k in range(4):
        m.ring("DiscoTile", (0, 2.95 + (k - 1.5) * 0.13, 0), math.sqrt(max(0.09 - ((k - 1.5) * 0.13) ** 2, 0.01)) + 0.005, 0.04, (190, 190, 215), normal="y", segments=10, mat="Foil")
    m.sparkles(ball, (255, 120, 220))
    m.light(ball, (255, 140, 230), 1.5, 7)
    for k in range(5):
        a = k * 2 * math.pi / 5
        m.ell("Flower", (0.12, 0.06, 0.12), (0.72 + math.cos(a) * 0.1, 2.52, math.sin(a) * 0.1), (255, 90, 160))
    m.ball("Flower", 0.08, (0.72, 2.54, 0), (255, 230, 80))
    # little music notes floating up
    for (x, y) in [(-0.6, 2.9), (0.65, 3.15)]:
        m.ball("Note", 0.14, (x, y, -0.1), (255, 120, 220), mat="Neon")
        m.blk("Note", (0.03, 0.3, 0.03), (x + 0.06, y + 0.15, -0.1), (255, 120, 220), mat="Neon")
    return m


@model
def haunted_arcade():
    m = Model("haunted_arcade", kind="gadget")
    body = (70, 40, 110)
    trim = (240, 80, 200)
    m.rbox("Cabinet", (1.5, 2.3, 1.2), (0, 1.15, 0.15), body, 0.1)
    m.blk("KickPlate", (1.4, 0.18, 0.05), (0, 0.12, -0.47), (30, 20, 40))
    for s in (-1, 1):
        # glowing T-molding along the front edges and pixel ghost side art
        m.blk("Trim", (0.05, 2.1, 0.05), (s * 0.74, 1.12, -0.45), trim, mat="Neon")
        m.blk("SideArt", (0.03, 1.6, 0.9), (s * 0.76, 1.3, 0.15), trim, mat="Neon", tr=0.5)
        m.blk("SideArt", (0.04, 1.4, 0.7), (s * 0.76, 1.3, 0.15), body)
        for (gy, gz) in [(0, 0), (0, 1), (0, 2), (1, -1), (1, 0), (1, 1), (1, 2), (1, 3), (2, -1), (2, 1), (2, 3), (3, -1), (3, 0), (3, 1), (3, 2), (3, 3), (4, -1), (4, 1), (4, 3)]:
            m.blk("SidePixel", (0.03, 0.09, 0.09), (s * 0.79, 1.75 - gy * 0.1, -0.05 + gz * 0.1), (200, 230, 255), mat="Neon")
        m.blk("SideEye", (0.035, 0.09, 0.09), (s * 0.795, 1.65, 0.05), (40, 30, 60))
        m.blk("SideEye", (0.035, 0.09, 0.09), (s * 0.795, 1.65, 0.25), (40, 30, 60))
        m.blk("Foot", (0.25, 0.1, 0.3), (s * 0.55, 0.05, -0.3), (25, 20, 30))
    m.rbox("Marquee", (1.55, 0.4, 0.3), (0, 2.25, -0.32), trim, 0.08, mat="Neon")
    # "BOO" spelled in chunky letters on the marquee
    def letter_o(cx):
        for (dx, dy, w, h) in [(0, 0.1, 0.18, 0.05), (0, -0.1, 0.18, 0.05), (-0.07, 0, 0.05, 0.22), (0.07, 0, 0.05, 0.22)]:
            m.blk("MarqueeLetter", (w, h, 0.03), (cx + dx, 2.25 + dy, -0.485), (40, 15, 60))
    for (dx, dy, w, h) in [(0.07, 0, 0.05, 0.25), (0, 0.1, 0.14, 0.05), (0, 0, 0.14, 0.05), (0, -0.1, 0.14, 0.05), (-0.06, 0.05, 0.05, 0.08), (-0.06, -0.05, 0.05, 0.08)]:
        m.blk("MarqueeLetter", (w, h, 0.03), (0.3 + dx, 2.25 + dy, -0.485), (40, 15, 60))
    letter_o(0.0)
    letter_o(-0.28)
    for k in range(6):
        m.ball("MarqueeBulb", 0.07, (-0.68 + k * 0.272, 2.47, -0.47), (255, 240, 150), mat="Neon")
    m.blk("ScreenBezel", (1.3, 0.9, 0.1), (0, 1.6, -0.47), (20, 15, 30), R=rot(x=-10))
    scr = m.blk("Screen", (1.1, 0.72, 0.06), (0, 1.6, -0.52), (60, 220, 120), mat="Neon", R=rot(x=-10))
    # the screen shows a spooky pixel face with pixel teeth and scanlines
    # (everything sits on the tilted glass: the screen leans forward 10 degrees at the top)
    def on_screen(y, depth, out=0.0):
        ly = (y - 1.6) / 0.985
        return -0.52 - 0.174 * ly - 0.03 * 0.985 - depth * 0.5 * 0.985 + 0.006 - out
    for s in (-1, 1):
        m.blk("ScreenEye", (0.18, 0.22, 0.04), (s * 0.22, 1.7, on_screen(1.7, 0.04)), (20, 40, 25), R=rot(x=-10))
        m.blk("ScreenGlint", (0.06, 0.06, 0.03), (s * 0.22 - 0.04, 1.75, on_screen(1.75, 0.03, 0.02)), (200, 255, 210), mat="Neon", R=rot(x=-10))
        m.blk("ScreenBrow", (0.2, 0.05, 0.03), (s * 0.22, 1.85, on_screen(1.85, 0.03)), (20, 40, 25), R=rot(x=-10, z=-s * 15))
    for k in range(5):
        y = 1.42 - 0.02 * (k % 2)
        m.blk("ScreenTooth", (0.08, 0.08 + 0.04 * (k % 2), 0.03), (-0.2 + k * 0.1, y, on_screen(y, 0.03)), (20, 40, 25), R=rot(x=-10))
    for k in range(4):
        y = 1.33 + k * 0.17
        m.blk("Scanline", (1.08, 0.022, 0.02), (0, y, on_screen(y, 0.02, 0.015)), (30, 120, 60), tr=0.55, R=rot(x=-10))
    m.blk("Score", (0.3, 0.06, 0.02), (0.32, 1.9, on_screen(1.9, 0.02)), (255, 255, 150), mat="Neon", R=rot(x=-10))
    m.blk("Controls", (1.5, 0.2, 0.6), (0, 1.0, -0.6), (90, 55, 140), R=rot(x=15))
    m.blk("ControlTrim", (1.52, 0.05, 0.05), (0, 0.98, -0.9), trim, mat="Neon")
    m.cyl("JoyBase", 0.05, 0.2, (-0.35, 1.12, -0.63), (20, 20, 25))
    m.cyl("Joystick", 0.3, 0.06, (-0.35, 1.25, -0.65), (30, 30, 30))
    m.ball("JoyBall", 0.18, (-0.35, 1.42, -0.65), (230, 40, 40))
    m.ball("JoyShine", 0.05, (-0.38, 1.47, -0.72), (255, 220, 220), mat="Neon")
    for k in range(6):
        col = [(255, 220, 60), (60, 160, 255), (255, 80, 80)][k % 3]
        bz = -0.62 - (k // 3) * 0.12
        top = 1.0966 - 0.259 * (bz + 0.5741) / 0.966
        m.cyl("Button", 0.06, 0.13, (0.05 + (k % 3) * 0.2, top + 0.012, bz), col, mat="Neon", R=rot(x=15))
    m.blk("CoinDoor", (0.6, 0.45, 0.05), (0, 0.5, -0.47), (30, 20, 40))
    for s in (-1, 1):
        m.blk("CoinSlot", (0.06, 0.16, 0.03), (s * 0.13, 0.55, -0.5), (255, 200, 60), mat="Neon")
        m.blk("CoinLight", (0.12, 0.08, 0.03), (s * 0.13, 0.38, -0.5), (255, 60, 60), mat="Neon")
    m.light(scr, (90, 255, 140), 1.4, 7)
    # a little ghost peeking out from behind, waving, with a cobweb on the other corner
    ghost = m.ell("Ghost", (0.5, 0.6, 0.4), (0.9, 2.3, 0.0), (220, 230, 255), tr=0.3)
    for k in range(3):
        m.ell("GhostTail", (0.18, 0.18, 0.18), (0.75 + k * 0.15, 2.02 - 0.03 * (k % 2), 0.0), (220, 230, 255), tr=0.3)
    m.ell("GhostArm", (0.14, 0.22, 0.12), (0.62, 2.35, -0.12), (220, 230, 255), tr=0.3, R=rot(z=40))
    m.ell("GhostArm", (0.14, 0.22, 0.12), (1.15, 2.45, -0.05), (220, 230, 255), tr=0.3, R=rot(z=-50))
    for s in (-1, 1):
        m.ell("GhostEye", (0.07, 0.1, 0.03), (0.9 + s * 0.1, 2.38, -0.2), (30, 25, 40))
        m.ball("GhostGlint", 0.025, (0.9 + s * 0.1 - 0.02, 2.41, -0.215), (255, 255, 255))
        m.ell("GhostBlush", (0.07, 0.04, 0.02), (0.9 + s * 0.17, 2.29, -0.19), (255, 170, 200))
    m.ell("GhostMouth", (0.08, 0.06, 0.03), (0.9, 2.24, -0.2), (30, 25, 40))
    m.smoke(ghost, (200, 220, 255), 0.05, 0.3, 0.8)
    hub = (-0.75, 2.45, -0.48)
    ends = []
    for k in range(4):
        a = math.radians(185 + k * 28)
        ends.append((-0.75 + math.cos(a) * -0.45, 2.45 + math.sin(a) * 0.45, -0.48))
        m.rod("Web", hub, ends[-1], 0.022, (230, 230, 240))
    for f in (0.45, 0.8):
        for k in range(3):
            p1 = tuple(hub[i] + (ends[k][i] - hub[i]) * f for i in range(3))
            p2 = tuple(hub[i] + (ends[k + 1][i] - hub[i]) * f for i in range(3))
            m.rod("Web", p1, p2, 0.02, (230, 230, 240))
    m.ball("Spider", 0.1, (-0.5, 2.1, -0.5), (30, 25, 35))
    m.rod("SpiderThread", (-0.5, 2.45, -0.5), (-0.5, 2.15, -0.5), 0.02, (230, 230, 240))
    return m


@model
def rocket_lunchbox():
    m = Model("rocket_lunchbox", kind="gadget")
    red = (220, 50, 50)
    m.rbox("Box", (2.2, 1.2, 1.2), (0, 1.0, 0), red, 0.15, mat="Metal", refl=0.25)
    m.rbox("BoxLid", (2.25, 0.3, 1.25), (0, 1.75, 0), (200, 40, 40), 0.12, mat="Metal", refl=0.25)
    m.blk("Latch", (0.3, 0.3, 0.08), (0, 1.55, -0.64), (220, 220, 230), mat="Metal")
    m.rod("Handle", (-0.5, 1.95, 0), (0.5, 1.95, 0), 0.12, (40, 40, 45))
    for x in (-0.5, 0.5):
        m.cyl("HandleMount", 0.1, 0.16, (x, 1.92, 0), (200, 200, 210), mat="Metal")
    # stickers: a star, a planet and a lightning bolt
    m.rbox("Sticker", (0.5, 0.4, 0.03), (-0.75, 1.05, -0.62), (255, 230, 80), 0.08, R=rot(z=-8), axis="z")
    for k in range(3):
        m.blk("StickerStar", (0.25, 0.05, 0.02), (-0.75, 1.05, -0.64), (240, 120, 40), R=rot(z=k * 60))
    m.rbox("Sticker2", (0.45, 0.38, 0.03), (0.75, 0.95, -0.62), (90, 200, 255), 0.08, R=rot(z=10), axis="z")
    m.ball("Planet", 0.2, (0.75, 0.95, -0.64), (240, 120, 200))
    m.ring("PlanetRing", (0.75, 0.95, -0.65), 0.16, 0.025, (255, 255, 255), normal="z", segments=8, R=rot(z=20))
    # rocket parts: nose cone pointing at the enemy (-Z), nozzle at the back
    nozzle = m.cyl("Nozzle", 0.5, 0.6, (0, 1.0, 0.82), (90, 90, 100), axis="z", mat="Metal")
    m.ring("NozzleRim", (0, 1.0, 1.07), 0.3, 0.06, (60, 60, 65), normal="z", segments=10, mat="Metal")
    m.fire(nozzle, size=1.6, heat=8)
    m.ell("NoseCone", (0.95, 0.9, 0.8), (0, 1.0, -0.75), (230, 230, 240), mat="Metal")
    m.ell("NoseTip", (0.3, 0.3, 0.25), (0, 1.0, -1.12), red, mat="Metal")
    m.cyl("Porthole", 0.05, 0.3, (0, 1.25, -0.9), (120, 200, 255), axis="z", mat="Glass", R=rot(x=-25))
    for s in (-1, 1):
        m.wedge("Fin", (0.1, 0.7, 0.7), (s * 1.15, 0.75, 0.35), (240, 200, 60))
        m.blk("FinStripe", (0.11, 0.12, 0.5), (s * 1.15, 0.7, 0.4), red)
    m.wedge("Fin", (0.7, 0.1, 0.7), (0, 1.62, 0.6), (240, 200, 60), R=rot(z=90))
    m.rbox("Stand", (1.6, 0.4, 0.6), (0, 0.2, 0), (80, 80, 90), 0.1, mat="Metal")
    for s in (-1, 1):
        m.blk("Strut", (0.1, 0.5, 0.1), (s * 0.7, 0.45, -0.3), (150, 150, 160), mat="Metal")
    # a sandwich peeking out under the lid
    m.blk("Sandwich", (0.6, 0.1, 0.4), (0.4, 1.62, -0.55), (240, 200, 130))
    m.blk("Lettuce", (0.62, 0.04, 0.42), (0.4, 1.56, -0.55), (110, 200, 80))
    return m


# Buildings added with the tile board. Like the others they face -Z (toward the enemy)
# and are shrunk by the client to fit on one tile.

@model
def snack_bar():
    m = Model("snack_bar", kind="gadget")
    wood = (230, 170, 110)
    m.rbox("Base", (2.6, 1.1, 1.8), (0, 0.55, 0.1), (240, 120, 130), 0.12)
    m.blk("CounterTop", (2.8, 0.14, 2.0), (0, 1.17, 0.05), (250, 245, 235))
    m.blk("Stripe", (2.62, 0.18, 0.04), (0, 0.8, -0.81), (255, 255, 255))
    m.blk("Stripe2", (2.62, 0.08, 0.04), (0, 0.45, -0.81), (255, 200, 90))
    for k in range(5):
        m.ball("Sprinkle", 0.08, (-1.0 + k * 0.5, 0.62, -0.82), [(90, 200, 255), (255, 220, 80), (120, 220, 120)][k % 3])
    for s in (-1, 1):
        m.blk("Post", (0.14, 1.5, 0.14), (s * 1.25, 1.95, 0.85), wood, mat="Wood")
        m.blk("PostFront", (0.14, 1.25, 0.14), (s * 1.25, 1.82, -0.8), wood, mat="Wood")
        m.chain("Lights", [(s * 1.25, 2.4, -0.85), (s * 0.6, 2.25, -0.95), (0, 2.3, -0.98)], 0.03, (60, 60, 60), joints=False)
    for k in range(6):
        c = (255, 90, 120) if k % 2 == 0 else (255, 250, 240)
        m.blk("Awning", (0.47, 0.1, 2.0), (-1.18 + k * 0.47, 2.55, 0.05), c, mat="Fabric", R=rot(x=-10))
    for k in range(6):
        c = (255, 90, 120) if k % 2 == 0 else (255, 250, 240)
        m.ell("AwningScallop", (0.42, 0.22, 0.08), (-1.18 + k * 0.47, 2.3, -0.98), c, mat="Fabric")
    for k in range(5):
        m.ball("Bulb", 0.09, (-1.0 + k * 0.5, 2.22 - 0.04 * (k % 2), -0.96), [(255, 230, 120), (255, 150, 180)][k % 2], mat="Neon")
    # treats on the counter: a sprinkled donut, a burger, a soda and an ice cream cone
    m.cyl("Donut", 0.16, 0.5, (-0.8, 1.32, -0.35), (230, 160, 90))
    m.cyl("DonutIcing", 0.07, 0.52, (-0.8, 1.42, -0.35), (255, 130, 200))
    m.cyl("DonutHole", 0.08, 0.16, (-0.8, 1.44, -0.35), (250, 245, 235))
    for k in range(5):
        a = k * 2 * math.pi / 5
        m.blk("Sprinkle", (0.08, 0.025, 0.025), (-0.8 + math.cos(a) * 0.17, 1.47, -0.35 + math.sin(a) * 0.17), [(90, 200, 255), (255, 240, 120), (255, 255, 255)][k % 3], R=rot(y=k * 50))
    m.cyl("BurgerBun", 0.16, 0.55, (0, 1.32, -0.4), (220, 150, 70))
    m.cyl("BurgerPatty", 0.1, 0.6, (0, 1.45, -0.4), (110, 60, 40))
    m.cyl("BurgerLettuce", 0.04, 0.64, (0, 1.5, -0.4), (110, 200, 80))
    m.cyl("BurgerCheese", 0.04, 0.62, (0, 1.53, -0.4), (255, 210, 60))
    m.ell("BurgerTop", (0.56, 0.32, 0.56), (0, 1.62, -0.4), (225, 155, 75))
    m.scatter("Sesame", (0, 1.62, -0.4), (0.56, 0.32, 0.56), 6, [(255, 245, 210)], seed=2, d=0.04, ymin=0.3)
    m.cyl("Cup", 0.5, 0.32, (0.75, 1.48, -0.35), (250, 250, 250))
    m.cyl("CupBand", 0.12, 0.34, (0.75, 1.5, -0.35), (255, 90, 120))
    m.cyl("CupLid", 0.06, 0.36, (0.75, 1.75, -0.35), (255, 90, 120))
    m.rod("Straw", (0.78, 1.75, -0.35), (0.9, 2.1, -0.3), 0.05, (255, 230, 80))
    m.cyl("Cone", 0.4, 0.2, (0.45, 1.42, 0.2), (220, 170, 100), R=rot(x=180))
    m.ball("Scoop", 0.28, (0.45, 1.7, 0.2), (255, 200, 220))
    m.ball("Cherry", 0.1, (0.45, 1.86, 0.2), (220, 30, 50))
    # glowing heart on the roof: it heals
    heart = m.ell("HeartL", (0.42, 0.42, 0.12), (-0.14, 3.0, 0.1), (255, 70, 100), mat="Neon")
    m.ell("HeartR", (0.42, 0.42, 0.12), (0.14, 3.0, 0.1), (255, 70, 100), mat="Neon")
    m.blk("HeartTip", (0.32, 0.32, 0.12), (0, 2.83, 0.1), (255, 70, 100), mat="Neon", R=rot(z=45))
    m.ell("HeartShine", (0.1, 0.06, 0.04), (-0.2, 3.1, 0.03), WHITE, mat="Neon")
    m.light(heart, (255, 120, 140), 1.0, 6)
    return m


@model
def bunny_burrow():
    m = Model("bunny_burrow", kind="gadget")
    grass = (110, 180, 80)
    m.ell("Mound", (2.8, 1.4, 2.5), (0, 0.4, 0.15), grass, mat="Grass")
    m.ell("MoundTop", (1.8, 1.2, 1.6), (0.25, 0.85, 0.35), (125, 195, 90), mat="Grass")
    # grass tufts and pebbles on the mound
    m.scatter("Tuft", (0, 0.4, 0.15), (2.8, 1.4, 2.5), 10, [(90, 160, 60), (140, 205, 100)], seed=7, d=0.1, shape="sprinkle", length=3.0, ymin=0.15)
    m.ell("Hole", (1.0, 0.85, 0.3), (0, 0.55, -0.98), (40, 28, 22))
    m.ring("HoleRim", (0, 0.55, -1.0), 0.55, 0.14, (140, 100, 60), normal="z", segments=12, mat="Wood")
    for k in range(5):
        a = math.radians(200 + k * 35)
        m.ball("Pebble", 0.14, (math.cos(a) * 0.7, 0.55 + math.sin(a) * 0.5, -1.05), (170, 160, 150), mat="Slate")
    # a bunny peeks out
    white = (250, 245, 240)
    m.ell("BunnyHead", (0.62, 0.5, 0.45), (0, 0.6, -1.0), white)
    for s in (-1, 1):
        m.ell("Ear", (0.16, 0.55, 0.1), (s * 0.15, 1.05, -0.98), white, R=rot(z=-s * 12))
        m.ell("EarInside", (0.08, 0.36, 0.04), (s * 0.15, 1.05, -1.04), (255, 170, 190), R=rot(z=-s * 12))
        m.ball("BunnyPaw", 0.14, (s * 0.2, 0.35, -1.18), white)
        m.blk("Whisker", (0.25, 0.025, 0.025), (s * 0.2, 0.53, -1.22), (150, 150, 150), R=rot(z=s * 10))
    m.eyes(0.66, -1.2, 0.21, 0.17, lid=white, iris=(90, 60, 50))
    m.ball("Nose", 0.09, (0, 0.55, -1.23), (255, 140, 170))
    m.cheeks(0.55, -1.2, 0.36, 0.1)
    # carrots and flowers around the mound
    # (carrots are planted in the mound with their tops showing, flowers sit on the grass)
    ground = top_of(ell_top((0, 0.4, 0.15), (2.8, 1.4, 2.5)), ell_top((0.25, 0.85, 0.35), (1.8, 1.2, 1.6)))
    for (x, z, a) in [(1.05, -0.55, 25), (-1.1, -0.45, -30), (0.95, 0.85, 10)]:
        g = ground(x, z)
        cy = g + 0.02
        sa = math.sin(math.radians(a))
        m.ell("Carrot", (0.16, 0.5, 0.16), (x, cy, z), (250, 140, 40), R=rot(z=a))
        for k in range(2):
            ly = 0.02 + k * 0.1
            m.blk("CarrotLine", (0.13, 0.02, 0.02), (x - sa * ly, cy + ly, z - 0.075 * math.sqrt(1 - (ly / 0.25) ** 2) - 0.005), (220, 110, 30), R=rot(z=a))
        for k in (-1, 0, 1):
            m.ell("CarrotTop", (0.08, 0.26, 0.06), (x - sa * 0.3 + k * 0.05, cy + 0.33, z), (80, 170, 70), R=rot(z=a + k * 25))
    for (x, z, c) in [(-0.7, 0.9, (255, 220, 80)), (0.5, -0.7, (255, 140, 200)), (-0.95, 0.2, (160, 200, 255))]:
        g = ground(x, z)
        m.cyl("FlowerStem", 0.14, 0.04, (x, g + 0.05, z), (80, 150, 60))
        for k in range(5):
            aa = k * 2 * math.pi / 5
            m.ball("Flower", 0.11, (x + math.cos(aa) * 0.07, g + 0.13, z + math.sin(aa) * 0.07), c)
        m.ball("Flower", 0.07, (x, g + 0.15, z), (255, 240, 200))
    m.blk("SignPost", (0.1, 0.9, 0.1), (1.05, 0.75, 0.25), (140, 100, 60), mat="Wood")
    m.blk("SignBoard", (0.6, 0.32, 0.06), (1.05, 1.15, 0.21), (200, 160, 110), mat="Wood", R=rot(z=-5))
    m.ell("SignCarrot", (0.3, 0.08, 0.03), (1.05, 1.15, 0.17), (250, 140, 40), R=rot(z=-5))
    return m


@model
def wind_turbine():
    m = Model("wind_turbine", kind="gadget")
    white = (240, 245, 250)
    blue = (120, 190, 255)
    m.cyl("Base", 0.3, 1.5, (0, 0.15, 0.1), (150, 160, 175), mat="Concrete")
    m.cyl("BaseRim", 0.1, 1.6, (0, 0.33, 0.1), (130, 140, 155), mat="Concrete")
    m.cyl("BaseStripe", 0.06, 1.52, (0, 0.24, 0.1), (255, 210, 60))
    # a tapered tower in three sections with blue bands, a door, a window and rungs
    m.cyl("Tower", 1.0, 0.56, (0, 0.85, 0.1), white)
    m.cyl("Tower", 1.0, 0.48, (0, 1.85, 0.1), white)
    m.cyl("TowerTop", 0.8, 0.4, (0, 2.7, 0.1), white)
    for (y, d) in [(0.6, 0.6), (1.37, 0.52), (2.32, 0.44)]:
        m.cyl("TowerBand", 0.1, d, (0, y, 0.1), blue)
    m.rbox("Door", (0.24, 0.42, 0.05), (0, 0.6, -0.19), (80, 120, 180), 0.06, axis="z")
    m.ball("DoorKnob", 0.05, (0.07, 0.58, -0.22), (255, 210, 60))
    m.cyl("Window", 0.04, 0.16, (0, 1.75, -0.14), (150, 220, 255), axis="z", mat="Glass", refl=0.3)
    m.ring("WindowRim", (0, 1.75, -0.145), 0.09, 0.03, (90, 140, 200), normal="z", segments=8)
    for k in range(5):
        m.blk("Rung", (0.14, 0.025, 0.03), (0.2, 0.95 + k * 0.28, -0.12), (150, 160, 175), mat="Metal", R=rot(y=-30))
    m.rbox("Nacelle", (0.5, 0.5, 0.95), (0, 2.95, 0.15), (230, 235, 245), 0.14, axis="z")
    for k in range(3):
        m.blk("Vent", (0.03, 0.2, 0.05), (0.26, 2.95, 0.3 + k * 0.12), (150, 160, 175))
    m.blk("NacelleStripe", (0.52, 0.06, 0.96), (0, 3.08, 0.15), blue)
    m.cyl("WarningBase", 0.06, 0.12, (0, 3.22, 0.45), (60, 60, 70))
    warn = m.ball("Warning", 0.12, (0, 3.3, 0.45), (255, 60, 60), mat="Neon")
    m.light(warn, (255, 80, 80), 0.6, 3)
    m.cyl("Vane", 0.3, 0.03, (0, 3.35, 0.6), (150, 160, 175), mat="Metal")
    m.wedge("VaneFin", (0.02, 0.18, 0.22), (0, 3.45, 0.7), (255, 120, 80))
    m.ell("Hub", (0.4, 0.4, 0.4), (0, 2.95, -0.35), blue)
    m.ell("Spinner", (0.26, 0.26, 0.3), (0, 2.95, -0.52), white)
    m.ball("SpinnerTip", 0.08, (0, 2.95, -0.66), (255, 120, 80))
    for k in range(3):
        a = math.radians(90 + k * 120)
        tilt = math.degrees(a) - 90
        def at(r):
            return (math.cos(a) * r, 2.95 + math.sin(a) * r, -0.45)
        # each blade: wide root, long tapered body, orange safety tip
        m.ell("BladeRoot", (0.22, 0.32, 0.12), at(0.3), (220, 225, 235), R=rot(z=tilt))
        m.blk("Blade", (0.34, 0.9, 0.06), at(0.75), (250, 250, 255), R=rot(z=tilt))
        m.blk("BladeEdge", (0.06, 0.9, 0.07), tuple(at(0.75)[i] + (math.cos(a + math.pi / 2) * 0.16 if i == 0 else math.sin(a + math.pi / 2) * 0.16 if i == 1 else 0) for i in range(3)), (210, 220, 235), R=rot(z=tilt))
        m.blk("BladeTip", (0.28, 0.32, 0.07), at(1.35), (255, 120, 80), R=rot(z=tilt))
        m.blk("BladeStripe", (0.3, 0.05, 0.075), at(1.17), (255, 255, 255), R=rot(z=tilt))
    m.blk("Bolt", (0.14, 0.5, 0.05), (0, 1.15, -0.27), (255, 220, 60), mat="Neon", R=rot(z=20))
    m.blk("Bolt", (0.14, 0.38, 0.05), (-0.05, 0.8, -0.27), (255, 220, 60), mat="Neon", R=rot(z=-20))
    # puffy shaded clouds around the base, a solar panel, a cable and wind streaks
    for (x, y, z, sx) in [(-0.95, 0.45, 0.55, 0.9), (0.9, 0.4, -0.4, 0.75), (0.75, 0.42, 0.75, 0.6)]:
        m.ell("Cloud", (sx, sx * 0.55, sx * 0.7), (x, y, z), (225, 232, 245))
        m.ell("Cloud", (sx * 0.6, sx * 0.5, sx * 0.5), (x + sx * 0.3, y + sx * 0.18, z - 0.05), (245, 248, 255))
        m.ell("Cloud", (sx * 0.5, sx * 0.42, sx * 0.45), (x - sx * 0.3, y + sx * 0.12, z - 0.08), (240, 245, 255))
    m.rbox("Solar", (0.6, 0.04, 0.4), (-0.8, 0.5, -0.6), (40, 60, 120), 0.03, mat="Glass", refl=0.3, R=rot(x=-25))
    for k in range(3):
        m.blk("SolarLine", (0.02, 0.045, 0.38), (-0.95 + k * 0.15, 0.51, -0.6), (150, 180, 230), R=rot(x=-25))
    m.blk("SolarLeg", (0.05, 0.4, 0.05), (-0.8, 0.25, -0.55), (150, 150, 160), mat="Metal")
    m.chain("Cable", [(-0.6, 0.3, -0.5), (-0.4, 0.33, -0.3), (-0.28, 0.35, -0.1)], 0.04, (40, 40, 50), joints=False)
    for (y, z, L) in [(3.6, -0.6, 0.9), (2.2, -0.75, 0.7)]:
        m.chain("Gust", [(-L, y, z), (0, y + 0.1, z - 0.05), (L * 0.6, y - 0.05, z)], 0.04, (210, 230, 255), joints=False)
    swirl = m.blk("WindSwirl", (0.1, 0.1, 0.1), (0, 1.8, -0.6), white, tr=1)
    m.smoke(swirl, (220, 235, 255), 0.06, 1.2, 0.6)
    return m


@model
def spooky_crypt():
    m = Model("spooky_crypt", kind="gadget")
    stone = (130, 125, 140)
    m.blk("Step", (2.6, 0.25, 2.3), (0, 0.125, 0.05), (100, 95, 110), mat="Slate")
    m.blk("Step", (1.2, 0.12, 0.4), (0, 0.3, -0.95), (115, 110, 125), mat="Slate")
    m.blk("Walls", (2.0, 1.7, 1.7), (0, 1.1, 0.15), stone, mat="Slate")
    # stone blocks pattern
    for row in range(3):
        for col in range(2):
            x = -0.7 + col * 1.4
            m.blk("Brick", (0.5, 0.03, 0.02), (x, 0.6 + row * 0.5, -0.71), (100, 95, 110))
    # (the roof starts just behind the front wall, so it no longer hides the top of the door)
    m.blk("Roof", (1.55, 1.55, 1.75), (0, 1.95, 0.24), (85, 70, 105), mat="Slate", R=rot(z=45))
    m.blk("RoofRidge", (0.15, 0.15, 1.85), (0, 3.05, 0.24), (70, 55, 90), mat="Slate")
    m.wedge("Gable", (1.9, 0.6, 0.1), (0, 2.25, -0.7), (110, 100, 125), mat="Slate")
    for s in (-1, 1):
        m.blk("Pillar", (0.3, 1.8, 0.3), (s * 0.85, 1.15, -0.8), (155, 150, 165), mat="Marble")
        m.blk("PillarCap", (0.42, 0.14, 0.42), (s * 0.85, 2.1, -0.8), (175, 170, 185), mat="Marble")
        m.blk("PillarBase", (0.42, 0.14, 0.42), (s * 0.85, 0.32, -0.8), (175, 170, 185), mat="Marble")
        m.ell("Ivy", (0.2, 0.7, 0.12), (s * 0.85, 1.2, -0.97), (90, 140, 80), mat="Grass", R=rot(z=s * 10))
    door = m.blk("Door", (0.75, 1.15, 0.06), (0, 0.85, -0.72), (150, 60, 220), mat="Neon")
    m.ell("DoorArch", (0.75, 0.5, 0.06), (0, 1.42, -0.72), (150, 60, 220), mat="Neon")
    m.ring("DoorFrame", (0, 1.42, -0.74), 0.38, 0.06, (175, 170, 185), normal="z", segments=10, mat="Marble")
    for k in range(3):
        m.blk("Bars", (0.04, 1.2, 0.04), (-0.2 + k * 0.2, 0.88, -0.76), (40, 30, 50), mat="Metal")
    m.light(door, (170, 90, 255), 1.6, 7)
    # a grinning skull over the door and bats on the roof
    m.ball("Skull", 0.34, (0, 1.97, -0.85), (235, 230, 215))
    for s in (-1, 1):
        m.ball("SkullEye", 0.09, (s * 0.07, 2.0, -1.0), (150, 60, 220), mat="Neon")
        m.wedge("BatWing", (0.04, 0.12, 0.25), (0.5 + s * 0.16, 2.75, -0.2), (30, 25, 35), R=rot(y=90, x=s * 20))
    for k in range(3):
        m.blk("SkullTooth", (0.04, 0.05, 0.02), (-0.05 + k * 0.05, 1.86, -1.0), WHITE)
    m.ball("Bat", 0.14, (0.5, 2.75, -0.2), (30, 25, 35))
    for (x, z) in [(-1.1, -0.95), (1.1, -0.95)]:
        m.cyl("Candle", 0.32, 0.14, (x, 0.41, z), (245, 240, 220))
        m.drip("Wax", (x + 0.06, 0.55, z - 0.05), 0.12, 0.05, (245, 240, 220))
        m.ell("Flame", (0.1, 0.18, 0.1), (x, 0.66, z), (255, 170, 60), mat="Neon")
    m.blk("Crack", (0.04, 0.6, 0.03), (0.6, 1.2, -0.71), (70, 65, 80), R=rot(z=25))
    m.blk("Crack", (0.04, 0.3, 0.03), (0.68, 0.9, -0.71), (70, 65, 80), R=rot(z=-20))
    m.ell("Moss", (0.6, 0.18, 0.5), (-0.7, 2.0, 0.6), (90, 130, 80), mat="Grass")
    m.rbox("Tombstone", (0.35, 0.5, 0.12), (-1.05, 0.5, 0.6), (150, 145, 160), 0.12, mat="Slate", axis="z")
    mist = m.blk("Mist", (0.1, 0.1, 0.1), (0, 0.4, -0.9), (200, 200, 220), tr=1)
    m.smoke(mist, (190, 170, 230), 0.07, 0.3, 1.0)
    return m


@model
def charging_station():
    m = Model("charging_station", kind="gadget")
    metal = (180, 185, 195)
    m.rbox("Base", (2.2, 0.3, 1.7), (0, 0.15, 0.05), (70, 75, 85), 0.15, mat="DiamondPlate")
    for k in range(5):
        m.blk("Hazard", (0.2, 0.31, 0.05), (-0.8 + k * 0.4, 0.15, -0.79), (240, 200, 40) if k % 2 == 0 else (30, 30, 30))
    m.rbox("Pillar", (1.0, 2.2, 0.8), (0, 1.4, 0.15), metal, 0.15, mat="Metal", refl=0.15)
    m.blk("PillarStripe", (1.02, 0.12, 0.82), (0, 2.3, 0.15), (60, 200, 255), mat="Neon")
    cap = m.rbox("Cap", (1.15, 0.2, 0.95), (0, 2.6, 0.15), (60, 200, 255), 0.1, mat="Neon")
    m.rbox("ScreenFrame", (0.8, 0.6, 0.04), (0, 1.95, -0.25), (40, 45, 55), 0.06, axis="z")
    scr = m.blk("Screen", (0.7, 0.5, 0.05), (0, 1.95, -0.27), (40, 220, 255), mat="Neon")
    m.rbox("BatteryIcon", (0.4, 0.22, 0.02), (0, 1.95, -0.3), (20, 60, 80), 0.04, axis="z")
    m.blk("BatteryFill", (0.24, 0.14, 0.02), (-0.04, 1.95, -0.31), (90, 255, 120), mat="Neon")
    m.blk("Bolt", (0.14, 0.42, 0.04), (0, 1.3, -0.27), (255, 220, 50), mat="Neon", R=rot(z=22))
    for k in range(3):
        m.blk("Bar", (0.16, 0.24, 0.04), (-0.22 + k * 0.22, 0.78, -0.27), (90, 255, 120), mat="Neon")
    for s in (-1, 1):
        m.chain("Cable", [(s * 0.5, 1.25, 0.1), (s * 0.85, 0.9, -0.15), (s * 0.95, 0.42, -0.35)], 0.1, (30, 30, 35))
        m.rbox("Plug", (0.26, 0.3, 0.26), (s * 0.98, 0.45, -0.4), (240, 200, 40), 0.06)
        m.blk("PlugPin", (0.05, 0.05, 0.12), (s * 0.98 - 0.05, 0.45, -0.58), (220, 220, 230), mat="Metal")
        m.blk("PlugPin2", (0.05, 0.05, 0.12), (s * 0.98 + 0.05, 0.45, -0.58), (220, 220, 230), mat="Metal")
        m.cyl("Holster", 0.2, 0.3, (s * 0.52, 1.25, 0.1), (60, 60, 70), axis="x", mat="Metal")
    m.cyl("Antenna", 0.6, 0.06, (0.35, 3.0, 0.3), (200, 200, 210), mat="Metal")
    m.ball("AntennaTip", 0.14, (0.35, 3.32, 0.3), (255, 80, 80), mat="Neon")
    m.light(scr, (80, 220, 255), 1.4, 7)
    m.sparkles(cap, (120, 220, 255))
    return m


@model
def scrap_catapult():
    m = Model("scrap_catapult", kind="gadget")
    wood = (150, 105, 60)
    for s in (-1, 1):
        m.blk("Rail", (0.25, 0.25, 2.3), (s * 0.75, 0.38, 0), wood, mat="WoodPlanks")
        for z in (-0.75, 0.75):
            m.cyl("Wheel", 0.16, 0.7, (s * 0.95, 0.35, z), (80, 80, 85), axis="x", mat="Metal")
            m.ring("Wheel", (s * 0.95, 0.35, z), 0.33, 0.06, (60, 60, 65), normal="x", segments=10, mat="Metal")
            m.cyl("WheelHub", 0.18, 0.2, (s * 0.97, 0.35, z), (200, 170, 70), axis="x", mat="Metal")
        m.blk("Upright", (0.22, 1.4, 0.22), (s * 0.75, 1.15, -0.2), wood, mat="WoodPlanks")
        m.rod("Brace", (s * 0.75, 0.5, 0.6), (s * 0.75, 1.5, -0.15), 0.12, shade(wood, 0.85), mat="Wood")
        for z in (-0.6, 0.0, 0.6):
            m.cyl("Bolt", 0.06, 0.08, (s * 0.88, 0.38, z), (90, 90, 100), axis="x", mat="Metal")
    m.blk("CrossBeam", (1.75, 0.22, 0.24), (0, 1.8, -0.2), wood, mat="WoodPlanks")
    m.blk("CrossPad", (0.5, 0.14, 0.3), (0, 1.95, -0.2), (90, 60, 40), mat="Fabric")
    m.cyl("Axle", 1.5, 0.16, (0, 0.62, 0.25), (110, 110, 115), axis="x", mat="Metal")
    m.rod("Arm", (0, 0.62, 0.25), (0, 1.65, 1.05), 0.2, wood, mat="WoodPlanks")
    for t in (0.3, 0.7):
        m.cyl("ArmBand", 0.06, 0.26, (0, 0.62 + 1.03 * t, 0.25 + 0.8 * t), (90, 90, 100), mat="Metal", R=rot(x=-52))
    m.cyl("Bucket", 0.4, 0.62, (0, 1.75, 1.12), (120, 115, 105), mat="Metal")
    m.ring("Bucket", (0, 1.95, 1.12), 0.31, 0.05, (90, 85, 80), normal="y", segments=10, mat="Metal")
    m.blk("ScrapCan", (0.2, 0.28, 0.2), (-0.12, 2.02, 1.1), (190, 195, 200), mat="Metal", R=rot(z=20))
    m.ring("ScrapGear", (0.12, 2.02, 1.15), 0.14, 0.06, (200, 150, 60), normal="z", segments=8, mat="Metal")
    m.blk("ScrapBolt", (0.08, 0.2, 0.08), (0.02, 2.06, 1.25), (150, 150, 160), mat="Metal", R=rot(x=30))
    m.ell("ScrapSpring", (0.12, 0.2, 0.12), (0.05, 2.1, 0.98), (170, 170, 180), mat="Metal")
    m.ring("Tire", (0, 0.55, 0.95), 0.32, 0.16, (40, 40, 45), normal="x", segments=10, mat="Rubber")
    m.chain("Rope", [(0.3, 0.55, 0.85), (0.35, 0.9, 0.45), (0.2, 1.25, 0.6)], 0.05, (210, 190, 140), mat="Fabric", joints=False)
    m.blk("Pennant", (0.04, 0.25, 0.35), (0.75, 2.05, -0.2), (200, 60, 60), mat="Fabric")
    m.cyl("PennantPole", 0.5, 0.04, (0.75, 1.95, -0.02), (200, 200, 210), mat="Metal")
    return m


# Hero figurines stand on pedestals next to each player's lanes.

@model
def hero_bonk():
    m = Model("hero_bonk", kind="hero")
    frog = (110, 190, 80)
    robe = (110, 60, 180)
    gold = (255, 225, 80)
    m.ell("Robe", (1.5, 1.7, 1.3), (0, 0.85, 0), robe, mat="Fabric")
    m.cyl("RobeHem", 0.2, 1.6, (0, 0.1, 0), (90, 45, 150), mat="Fabric")
    m.ring("RobeTrim", (0, 0.2, 0), 0.79, 0.06, gold, normal="y", segments=14, mat="Fabric")
    for k in range(5):
        m.ell("RobeStar", (0.18, 0.18, 0.05), (-0.45 + k * 0.23, 0.55 + (k % 2) * 0.4, -0.64), gold, mat="Neon")
    m.ell("Moon", (0.2, 0.2, 0.05), (0.45, 1.25, -0.55), (255, 240, 160), mat="Neon")
    m.ell("Head", (1.5, 1.0, 1.25), (0, 2.05, -0.05), frog)
    m.ell("Belly", (0.9, 0.5, 0.4), (0, 1.75, -0.5), (220, 240, 170))
    m.scatter("Spot", (0, 2.05, -0.05), (1.5, 1.0, 1.25), 6, [shade(frog, 0.82)], seed=3, d=0.16, shape="dot", ymin=0.0)
    for s in (-1, 1):
        m.ball("EyeBump", 0.6, (s * 0.42, 2.55, -0.25), frog)
    m.eyes(2.58, -0.5, 0.84, 0.42, lid=frog, iris=(200, 150, 40), z_back=0.03)
    m.grin(1.88, -0.62, 0.95, color=(60, 100, 40), curve=0.15, bend=0.1, d=0.08)
    m.cheeks(2.0, -0.6, 1.1, 0.25)
    # a curly wizard beard
    m.ell("Beard", (0.6, 0.45, 0.25), (0, 1.62, -0.6), (240, 240, 245), mat="Fabric")
    m.ell("Beard", (0.3, 0.35, 0.2), (0, 1.35, -0.62), (240, 240, 245), mat="Fabric")
    # wizard hat sitting between the eyes
    m.cyl("HatBrim", 0.08, 1.2, (0, 2.85, 0.15), robe)
    m.ring("HatBand", (0, 2.95, 0.15), 0.36, 0.06, gold, normal="y", segments=10)
    for k in range(4):
        m.cyl("HatCone", 0.32, 0.75 - k * 0.16, (0.06 * k, 3.05 + k * 0.28, 0.15 + 0.03 * k), robe, R=rot(z=-8 * k))
    m.ball("HatTip", 0.16, (0.26, 4.05, 0.28), gold, mat="Neon")
    m.ell("HatStar", (0.14, 0.14, 0.04), (0.0, 3.25, -0.15), gold, mat="Neon")
    # arms and a staff with a glowing orb held in a claw
    for s in (-1, 1):
        m.rod("Sleeve", (s * 0.6, 1.45, 0), (s * 0.95, 1.05, -0.35), 0.35, robe, mat="Fabric", shape="E")
        m.ell("Cuff", (0.38, 0.2, 0.38), (s * 0.95, 1.05, -0.36), gold, mat="Fabric")
        m.ball("Hand", 0.3, (s * 1.0, 1.0, -0.4), frog)
    m.cyl("Staff", 2.6, 0.12, (1.0, 1.4, -0.42), (120, 80, 45))
    for k in range(3):
        m.rod("StaffBand", (1.0 + 0.12 * math.cos(k * 2.1), 2.6, -0.42 + 0.12 * math.sin(k * 2.1)), (1.0 + 0.15 * math.cos(k * 2.1), 2.95, -0.42 + 0.15 * math.sin(k * 2.1)), 0.05, (120, 80, 45))
    orb = m.ball("Orb", 0.42, (1.0, 2.8, -0.42), (120, 220, 255), mat="Neon")
    m.sparkles(orb, (160, 230, 255))
    m.light(orb, (120, 220, 255), 1.3, 7)
    return m


@model
def hero_granny_bolt():
    m = Model("hero_granny_bolt", kind="hero")
    skin = (245, 205, 175)
    suit = (70, 110, 220)
    m.cyl("Legs", 0.9, 0.9, (0, 0.5, 0), suit, mat="Fabric")
    for s in (-1, 1):
        m.shoe(s * 0.22, -0.15, 0.4, 0.6, (240, 240, 245), sole=(255, 80, 80), toe=WHITE, lace=(255, 80, 80))
    m.ell("Body", (1.3, 1.4, 1.0), (0, 1.55, 0), suit, mat="Fabric")
    m.blk("Stripe", (0.12, 1.2, 0.05), (-0.35, 1.55, -0.5), (255, 220, 60), R=rot(z=12))
    m.blk("Stripe", (0.12, 1.2, 0.05), (0.35, 1.55, -0.5), (255, 220, 60), R=rot(z=-12))
    m.blk("BoltLogo", (0.12, 0.45, 0.04), (0, 1.65, -0.52), (255, 220, 60), mat="Neon", R=rot(z=20))
    m.ell("Collar", (0.7, 0.2, 0.5), (0, 2.15, -0.1), (255, 255, 255), mat="Fabric")
    m.ball("Head", 1.0, (0, 2.6, 0), skin)
    m.ball("Bun", 0.6, (0, 3.2, 0.15), (220, 220, 230))
    m.cyl("BunPin", 0.7, 0.04, (0, 3.2, 0.15), (240, 200, 60), axis="x", mat="Metal", R=rot(z=20))
    m.ell("Hair", (1.05, 0.55, 1.0), (0, 2.9, 0.05), (220, 220, 230))
    m.cyl("Headband", 0.12, 1.02, (0, 2.85, 0), (255, 80, 80), mat="Fabric")
    m.eyes(2.62, -0.45, 0.38, 0.22, lid=skin, iris=(90, 140, 210), z_back=0.03)
    for s in (-1, 1):
        m.ring("Glasses", (s * 0.19, 2.62, -0.5), 0.14, 0.035, (60, 40, 30), normal="z", segments=8)
        m.brow(s * 0.19, 2.82, -0.47, 0.18, (200, 200, 210), s, tilt=-10, d=0.05)
    m.blk("Glasses", (0.12, 0.03, 0.03), (0, 2.64, -0.51), (60, 40, 30))
    m.ell("Nose", (0.12, 0.12, 0.1), (0, 2.5, -0.5), shade(skin, 0.92))
    m.grin(2.36, -0.46, 0.24, curve=0.3)
    m.cheeks(2.5, -0.44, 0.7, 0.18)
    # arms in sweatbands holding a bowling ball
    for s in (-1, 1):
        m.rod("Arm", (s * 0.55, 1.95, 0), (s * 0.45, 1.4, -0.55), 0.24, suit, mat="Fabric")
        m.cyl("Wristband", 0.12, 0.28, (s * 0.46, 1.45, -0.5), (255, 80, 80), mat="Fabric", R=rot(x=45))
        m.ball("Hand", 0.24, (s * 0.42, 1.36, -0.62), skin)
    m.ball("BowlingBall", 0.85, (0, 1.3, -0.75), (80, 30, 120), refl=0.4)
    m.ball("BallShine", 0.18, (-0.2, 1.5, -1.08), (180, 140, 220), tr=0.3)
    for (x, y) in [(-0.12, 1.45), (0.12, 1.45), (0, 1.25)]:
        m.cyl("FingerHole", 0.05, 0.1, (x, y, -1.17), (20, 10, 30), axis="z")
    spark = m.ball("Spark", 0.2, (0.35, 1.6, -1.0), (255, 230, 80), mat="Neon")
    m.sparkles(spark, (255, 230, 100))
    return m


# The bot opponent sits in the far chair (seat top at y = 2, facing -Z like everything else;
# the server turns it around to face the player).

@model
def bot_bonkers():
    m = Model("bot_bonkers", kind="avatar")
    shell = (235, 240, 245)
    accent = (255, 150, 60)
    joint = (120, 125, 140)
    m.rbox("Hips", (2.4, 0.9, 2.0), (0, 2.45, 0.2), (90, 95, 110), 0.25, mat="Metal")
    for s in (-1, 1):
        m.rod("Thigh", (s * 0.6, 2.4, -0.2), (s * 0.6, 2.4, -1.4), 0.6, joint, mat="Metal")
        m.ball("Knee", 0.7, (s * 0.6, 2.4, -1.4), accent)
        m.rod("Shin", (s * 0.6, 2.4, -1.4), (s * 0.6, 0.4, -1.5), 0.5, joint, mat="Metal")
        m.rbox("Foot", (0.7, 0.35, 1.0), (s * 0.6, 0.18, -1.7), (70, 75, 90), 0.12, mat="Metal")
    m.ell("Torso", (2.8, 2.6, 2.0), (0, 4.1, 0.3), shell, refl=0.2)
    m.ell("Chest", (1.6, 1.2, 0.4), (0, 4.1, -0.62), accent)
    m.cyl("ChestLight", 0.1, 0.5, (0, 4.15, -0.84), (120, 255, 160), axis="z", mat="Neon")
    m.ring("ChestLight", (0, 4.15, -0.86), 0.3, 0.06, (200, 205, 215), normal="z", segments=12, mat="Metal")
    for k in range(3):
        m.blk("Vent", (0.6, 0.06, 0.05), (0, 3.6 - k * 0.12, -0.85), (60, 65, 80))
    for s in (-1, 1):
        m.ball("Shoulder", 0.9, (s * 1.5, 4.8, 0.3), joint, mat="Metal")
        m.rod("UpperArm", (s * 1.6, 4.7, 0.3), (s * 1.75, 3.9, -0.9), 0.5, shell)
        m.ball("Elbow", 0.55, (s * 1.75, 3.9, -0.9), joint, mat="Metal")
        m.rod("Forearm", (s * 1.75, 3.9, -0.9), (s * 1.0, 4.0, -2.2), 0.45, shell)
        m.ball("Hand", 0.6, (s * 0.95, 4.0, -2.3), accent)
        for k in range(3):
            m.ball("Finger", 0.22, (s * 0.95 + (k - 1) * 0.16, 3.82, -2.55), accent)
    m.cyl("Neck", 0.5, 0.6, (0, 5.5, 0.3), joint, mat="Metal")
    m.ell("Head", (2.4, 1.9, 2.0), (0, 6.6, 0.3), shell, refl=0.2)
    m.rbox("Face", (1.8, 1.1, 0.12), (0, 6.6, -0.68), (25, 30, 45), 0.25, axis="z")
    for s in (-1, 1):
        m.ell("Eye", (0.45, 0.55, 0.06), (s * 0.42, 6.75, -0.76), (120, 230, 255), mat="Neon")
        m.ell("Glint", (0.12, 0.14, 0.03), (s * 0.42 + 0.1, 6.88, -0.8), WHITE, mat="Neon")
        m.cyl("Ear", 0.3, 0.7, (s * 1.25, 6.6, 0.3), accent, axis="x")
        m.ring("Ear", (s * 1.42, 6.6, 0.3), 0.25, 0.05, joint, normal="x", segments=10, mat="Metal")
    m.grin(6.32, -0.77, 0.6, curve=0.2, color=(120, 230, 255), d=0.08)
    m.rod("Antenna", (0, 7.5, 0.3), (0.2, 8.3, 0.4), 0.1, (180, 180, 190), mat="Metal")
    tip = m.ball("AntennaTip", 0.35, (0.2, 8.4, 0.4), (255, 80, 80), mat="Neon")
    m.light(tip, (255, 120, 120), 0.8, 5)
    return m
