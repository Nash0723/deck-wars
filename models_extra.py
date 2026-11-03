# Buildings, hero figurines and the bot opponent
import math
from modelkit import Model, rot, WHITE, PUPIL

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
        m.blk("Plank", (0.45, 1.1, 0.16), (x, 0.55, 0), wood, mat="WoodPlanks")
        m.blk("PlankTip", (0.32, 0.32, 0.16), (x, 1.1, 0), wood, mat="WoodPlanks", R=rot(z=45))
        m.cyl("Spike", 0.5, 0.12, (x, 1.45, 0), (190, 195, 205), mat="Metal")
        m.ell("SpikeTip", (0.12, 0.25, 0.12), (x, 1.75, 0), (210, 215, 225), mat="Metal")
    for y in (0.3, 0.85):
        m.blk("Rail", (3.1, 0.18, 0.12), (0, y, 0.14), (120, 80, 45), mat="Wood")
    for x in (-1.0, 0.3, 1.1):
        m.cyl("Nail", 0.05, 0.06, (x, 0.85, -0.1), (90, 90, 100), axis="z", mat="Metal")
    m.blk("Sign", (0.7, 0.4, 0.06), (0.55, 0.65, -0.12), (250, 230, 120), R=rot(z=-6))
    m.blk("SignMark", (0.08, 0.25, 0.03), (0.55, 0.67, -0.16), (200, 40, 40))
    return m


@model
def bouncy_castle():
    m = Model("bouncy_castle", kind="gadget")
    m.blk("Floor", (3.0, 0.35, 1.7), (0, 0.18, 0), (90, 160, 240), mat="Rubber")
    m.blk("Wall", (2.4, 0.9, 1.2), (0, 0.75, 0.1), (250, 120, 170), mat="Rubber")
    for s in (-1, 1):
        m.cyl("Tower", 1.6, 0.75, (s * 1.25, 0.95, 0.2), (255, 220, 80), mat="Rubber")
        m.ell("TowerTop", (0.85, 0.6, 0.85), (s * 1.25, 1.95, 0.2), (250, 120, 170), mat="Rubber")
        m.ball("Bump", 0.3, (s * 1.25, 2.3, 0.2), (90, 160, 240), mat="Rubber")
    for k in range(4):
        m.ell("Crenel", (0.45, 0.45, 0.45), (-0.75 + k * 0.5, 1.3, 0.1), (250, 140, 185), mat="Rubber")
    m.ell("Door", (0.8, 0.6, 0.1), (0, 0.65, -0.52), (60, 90, 190))
    m.cyl("Flag", 0.6, 0.05, (1.25, 2.65, 0.2), (200, 200, 210), mat="Metal")
    m.blk("FlagCloth", (0.4, 0.25, 0.03), (1.46, 2.82, 0.2), (90, 220, 120), mat="Fabric")
    return m


@model
def lemonade_stand():
    m = Model("lemonade_stand", kind="gadget")
    wood = (200, 150, 90)
    m.blk("Counter", (2.8, 1.0, 1.1), (0, 0.5, 0.1), wood, mat="WoodPlanks")
    m.blk("CounterTop", (3.0, 0.12, 1.25), (0, 1.06, 0.1), (170, 120, 70), mat="Wood")
    m.blk("Banner", (2.4, 0.45, 0.06), (0, 0.6, -0.47), (255, 240, 120))
    for k in range(5):
        m.ball("Lemon", 0.22, (-0.8 + k * 0.4, 0.6, -0.52), (255, 220, 50))
    for s in (-1, 1):
        m.blk("Post", (0.12, 1.4, 0.12), (s * 1.35, 1.75, 0.55), (170, 120, 70), mat="Wood")
    for k in range(6):
        c = (255, 255, 255) if k % 2 == 0 else (240, 200, 40)
        m.blk("Awning", (0.48, 0.08, 1.1), (-1.2 + k * 0.48, 2.45, 0.2), c, mat="Fabric", R=rot(x=-14))
    m.cyl("Pitcher", 0.6, 0.45, (-0.6, 1.42, 0.1), (255, 245, 150), mat="Glass", tr=0.3)
    m.cyl("PitcherLemonade", 0.45, 0.4, (-0.6, 1.36, 0.1), (255, 230, 80))
    for k in range(3):
        m.cyl("Cup", 0.35, 0.22, (0.2 + k * 0.35, 1.3, -0.05), (250, 250, 250))
    m.blk("Jar", (0.4, 0.4, 0.4), (1.0, 1.32, 0.3), (190, 230, 255), mat="Glass", tr=0.3)
    m.cyl("Coins", 0.12, 0.28, (1.0, 1.2, 0.3), (240, 200, 60), mat="Metal")
    return m


@model
def disco_cactus():
    m = Model("disco_cactus", kind="gadget")
    m.cyl("Pot", 0.8, 1.0, (0, 0.4, 0), (210, 110, 60))
    m.cyl("PotRim", 0.2, 1.15, (0, 0.82, 0), (190, 95, 50))
    m.cyl("Soil", 0.06, 0.95, (0, 0.9, 0), (90, 60, 40))
    green = (70, 170, 80)
    m.ell("Cactus", (0.7, 1.8, 0.7), (0, 1.75, 0), green)
    for s in (-1, 1):
        m.rod("ArmOut", (s * 0.3, 1.65, 0), (s * 0.7, 1.75, 0), 0.32, green)
        m.ell("ArmUp", (0.32, 0.8, 0.32), (s * 0.72, 2.1, 0), green)
    for (x, y) in [(-0.2, 2.2), (0.2, 1.6), (0.15, 2.45), (-0.25, 1.4)]:
        m.blk("Spine", (0.04, 0.04, 0.18), (x, y, -0.34), (250, 250, 230))
    m.eyes(1.95, -0.33, 0.3, 0.2, lid=green)
    m.smile(1.72, -0.34, 0.16, open_=True)
    m.blk("Shades", (0.55, 0.12, 0.06), (0, 2.02, -0.42), (255, 60, 200), mat="Neon")
    ball = m.ball("DiscoBall", 0.6, (0, 2.95, 0), (225, 225, 240), mat="Foil", refl=0.6)
    m.sparkles(ball, (255, 120, 220))
    m.light(ball, (255, 140, 230), 1.5, 7)
    m.blk("Flower", (0.2, 0.2, 0.2), (0.72, 2.55, 0), (255, 90, 160))
    return m


@model
def haunted_arcade():
    m = Model("haunted_arcade", kind="gadget")
    body = (70, 40, 110)
    m.blk("Cabinet", (1.5, 2.3, 1.2), (0, 1.15, 0.15), body)
    m.blk("Marquee", (1.55, 0.4, 0.3), (0, 2.25, -0.32), (240, 80, 200), mat="Neon")
    m.blk("ScreenBezel", (1.3, 0.9, 0.1), (0, 1.6, -0.47), (20, 15, 30), R=rot(x=-10))
    scr = m.blk("Screen", (1.1, 0.72, 0.06), (0, 1.6, -0.52), (60, 220, 120), mat="Neon", R=rot(x=-10))
    for s in (-1, 1):
        m.ell("ScreenEye", (0.18, 0.24, 0.04), (s * 0.2, 1.65, -0.56), (20, 40, 25), R=rot(x=-10))
    m.blk("Controls", (1.5, 0.2, 0.6), (0, 1.0, -0.6), (90, 55, 140), R=rot(x=15))
    m.cyl("Joystick", 0.3, 0.06, (-0.35, 1.25, -0.65), (30, 30, 30))
    m.ball("JoyBall", 0.18, (-0.35, 1.42, -0.65), (230, 40, 40))
    for k in range(2):
        m.cyl("Button", 0.06, 0.16, (0.15 + k * 0.28, 1.15, -0.68), [(255, 220, 60), (60, 160, 255)][k], mat="Neon")
    m.blk("CoinDoor", (0.5, 0.35, 0.05), (0, 0.5, -0.47), (30, 20, 40))
    m.blk("CoinSlot", (0.06, 0.18, 0.03), (0, 0.52, -0.5), (255, 200, 60), mat="Neon")
    m.light(scr, (90, 255, 140), 1.4, 7)
    ghost = m.ell("Ghost", (0.5, 0.6, 0.4), (0.9, 2.3, 0.0), (220, 230, 255), tr=0.35)
    m.smoke(ghost, (200, 220, 255), 0.05, 0.3, 0.8)
    return m


@model
def rocket_lunchbox():
    m = Model("rocket_lunchbox", kind="gadget")
    red = (220, 50, 50)
    m.blk("Box", (2.2, 1.2, 1.2), (0, 1.0, 0), red, mat="Metal", refl=0.2)
    m.blk("Lid", (2.25, 0.3, 1.25), (0, 1.75, 0), (200, 40, 40), mat="Metal", refl=0.2)
    m.blk("Latch", (0.3, 0.3, 0.08), (0, 1.55, -0.64), (220, 220, 230), mat="Metal")
    m.rod("Handle", (-0.5, 1.9, 0), (0.5, 1.9, 0), 0.12, (40, 40, 45))
    m.blk("Sticker", (0.5, 0.4, 0.03), (-0.75, 1.05, -0.62), (255, 230, 80), R=rot(z=-8))
    m.blk("Sticker2", (0.45, 0.38, 0.03), (0.75, 0.95, -0.62), (90, 200, 255), R=rot(z=10))
    # rocket parts: nose cone pointing at the enemy (-Z), nozzle at the back
    nozzle = m.cyl("Nozzle", 0.5, 0.6, (0, 1.0, 0.82), (90, 90, 100), axis="z", mat="Metal")
    m.fire(nozzle, size=1.6, heat=8)
    m.ell("NoseCone", (0.95, 0.9, 0.8), (0, 1.0, -0.75), (230, 230, 240), mat="Metal")
    for s in (-1, 1):
        m.wedge("Fin", (0.1, 0.7, 0.7), (s * 1.15, 0.75, 0.35), (240, 200, 60))
    m.blk("Stand", (1.6, 0.4, 0.6), (0, 0.2, 0), (80, 80, 90), mat="Metal")

    return m


# Buildings added with the tile board. Like the others they face -Z (toward the enemy)
# and are shrunk by the client to fit on one tile.

@model
def snack_bar():
    m = Model("snack_bar", kind="gadget")
    wood = (230, 170, 110)
    m.blk("Base", (2.6, 1.1, 1.8), (0, 0.55, 0.1), (240, 120, 130))
    m.blk("CounterTop", (2.8, 0.14, 2.0), (0, 1.17, 0.05), (250, 245, 235))
    m.blk("Stripe", (2.62, 0.18, 0.04), (0, 0.8, -0.81), (255, 255, 255))
    m.blk("Stripe2", (2.62, 0.08, 0.04), (0, 0.45, -0.81), (255, 200, 90))
    for s in (-1, 1):
        m.blk("Post", (0.14, 1.5, 0.14), (s * 1.25, 1.95, 0.85), wood, mat="Wood")
        m.blk("PostFront", (0.14, 1.25, 0.14), (s * 1.25, 1.82, -0.8), wood, mat="Wood")
    for k in range(6):
        c = (255, 90, 120) if k % 2 == 0 else (255, 250, 240)
        m.blk("Awning", (0.47, 0.1, 2.0), (-1.18 + k * 0.47, 2.55, 0.05), c, mat="Fabric", R=rot(x=-10))
    for k in range(6):
        c = (255, 90, 120) if k % 2 == 0 else (255, 250, 240)
        m.ell("AwningScallop", (0.42, 0.22, 0.08), (-1.18 + k * 0.47, 2.3, -0.98), c, mat="Fabric")
    # treats on the counter
    m.cyl("Donut", 0.16, 0.5, (-0.8, 1.32, -0.35), (230, 160, 90))
    m.cyl("DonutIcing", 0.07, 0.52, (-0.8, 1.42, -0.35), (255, 130, 200))
    m.cyl("DonutHole", 0.08, 0.16, (-0.8, 1.44, -0.35), (250, 245, 235))
    m.cyl("BurgerBun", 0.16, 0.55, (0, 1.32, -0.4), (220, 150, 70))
    m.cyl("BurgerPatty", 0.1, 0.6, (0, 1.45, -0.4), (110, 60, 40))
    m.cyl("BurgerCheese", 0.04, 0.62, (0, 1.52, -0.4), (255, 210, 60))
    m.ell("BurgerTop", (0.56, 0.32, 0.56), (0, 1.62, -0.4), (225, 155, 75))
    m.cyl("Cup", 0.5, 0.32, (0.75, 1.48, -0.35), (250, 250, 250))
    m.cyl("CupBand", 0.12, 0.34, (0.75, 1.5, -0.35), (255, 90, 120))
    m.cyl("CupLid", 0.06, 0.36, (0.75, 1.75, -0.35), (255, 90, 120))
    m.rod("Straw", (0.78, 1.75, -0.35), (0.9, 2.1, -0.3), 0.05, (255, 230, 80))
    # glowing heart on the roof: it heals
    heart = m.ell("HeartL", (0.42, 0.42, 0.12), (-0.14, 3.0, 0.1), (255, 70, 100), mat="Neon")
    m.ell("HeartR", (0.42, 0.42, 0.12), (0.14, 3.0, 0.1), (255, 70, 100), mat="Neon")
    m.blk("HeartTip", (0.32, 0.32, 0.12), (0, 2.83, 0.1), (255, 70, 100), mat="Neon", R=rot(z=45))
    m.light(heart, (255, 120, 140), 1.0, 6)
    return m


@model
def bunny_burrow():
    m = Model("bunny_burrow", kind="gadget")
    grass = (110, 180, 80)
    m.ell("Mound", (2.8, 1.4, 2.5), (0, 0.4, 0.15), grass, mat="Grass")
    m.ell("MoundTop", (1.8, 1.2, 1.6), (0.25, 0.85, 0.35), (125, 195, 90), mat="Grass")
    m.ell("Hole", (1.0, 0.85, 0.3), (0, 0.55, -0.98), (40, 28, 22))
    m.ring("HoleRim", (0, 0.55, -1.0), 0.55, 0.14, (140, 100, 60), normal="z", segments=10, mat="Wood")
    # a bunny peeks out
    white = (250, 245, 240)
    m.ell("BunnyHead", (0.62, 0.5, 0.45), (0, 0.6, -1.0), white)
    for s in (-1, 1):
        m.ell("Ear", (0.16, 0.55, 0.1), (s * 0.15, 1.05, -0.98), white, R=rot(z=-s * 12))
        m.ell("EarInside", (0.08, 0.36, 0.04), (s * 0.15, 1.05, -1.04), (255, 170, 190), R=rot(z=-s * 12))
    m.eyes(0.66, -1.2, 0.21, 0.17, lid=white)
    m.ball("Nose", 0.09, (0, 0.55, -1.23), (255, 140, 170))
    # carrots and flowers around the mound
    for (x, z, a) in [(1.05, -0.55, 25), (-1.1, -0.45, -30), (0.95, 0.85, 10)]:
        m.ell("Carrot", (0.16, 0.5, 0.16), (x, 0.3, z), (250, 140, 40), R=rot(z=a))
        m.ell("CarrotTop", (0.22, 0.22, 0.1), (x - math.sin(math.radians(a)) * 0.3, 0.58, z), (80, 170, 70))
    for (x, z, c) in [(-0.7, 0.9, (255, 220, 80)), (0.5, -0.7, (255, 140, 200)), (-0.95, 0.2, (160, 200, 255))]:
        m.ball("Flower", 0.18, (x, 0.75, z), c)
    m.blk("SignPost", (0.1, 0.9, 0.1), (1.05, 0.75, 0.25), (140, 100, 60), mat="Wood")
    m.blk("SignBoard", (0.6, 0.32, 0.06), (1.05, 1.15, 0.21), (200, 160, 110), mat="Wood", R=rot(z=-5))
    return m


@model
def wind_turbine():
    m = Model("wind_turbine", kind="gadget")
    white = (240, 245, 250)
    m.cyl("Base", 0.3, 1.5, (0, 0.15, 0.1), (150, 160, 175), mat="Concrete")
    m.cyl("Tower", 2.5, 0.42, (0, 1.5, 0.1), white)
    m.cyl("TowerBand", 0.25, 0.46, (0, 0.6, 0.1), (120, 190, 255))
    m.blk("Nacelle", (0.45, 0.45, 0.9), (0, 2.95, 0.15), (230, 235, 245))
    m.ell("Hub", (0.38, 0.38, 0.4), (0, 2.95, -0.35), (120, 190, 255))
    for k in range(3):
        a = math.radians(90 + k * 120)
        cx, cy = math.cos(a) * 0.78, 2.95 + math.sin(a) * 0.78
        m.blk("Blade", (0.24, 1.35, 0.06), (cx, cy, -0.45), (250, 250, 255), R=rot(z=math.degrees(a) - 90))
    m.blk("Bolt", (0.12, 0.45, 0.05), (0, 1.55, -0.12), (255, 220, 60), mat="Neon", R=rot(z=20))
    for (x, y, z, sx) in [(-0.95, 0.45, 0.55, 0.9), (0.9, 0.4, -0.4, 0.75), (0.75, 0.42, 0.75, 0.6)]:
        m.ell("Cloud", (sx, sx * 0.55, sx * 0.7), (x, y, z), (235, 240, 250))
    swirl = m.blk("WindSwirl", (0.1, 0.1, 0.1), (0, 1.8, -0.6), white, tr=1)
    m.smoke(swirl, (220, 235, 255), 0.06, 1.2, 0.6)
    return m


@model
def spooky_crypt():
    m = Model("spooky_crypt", kind="gadget")
    stone = (130, 125, 140)
    m.blk("Step", (2.6, 0.25, 2.3), (0, 0.125, 0.05), (100, 95, 110), mat="Slate")
    m.blk("Walls", (2.0, 1.7, 1.7), (0, 1.1, 0.15), stone, mat="Slate")
    m.blk("Roof", (1.55, 1.55, 1.9), (0, 1.95, 0.15), (85, 70, 105), mat="Slate", R=rot(z=45))
    for s in (-1, 1):
        m.blk("Pillar", (0.3, 1.8, 0.3), (s * 0.85, 1.15, -0.8), (155, 150, 165), mat="Marble")
        m.blk("PillarCap", (0.42, 0.14, 0.42), (s * 0.85, 2.1, -0.8), (175, 170, 185), mat="Marble")
    door = m.blk("Door", (0.75, 1.15, 0.06), (0, 0.85, -0.72), (150, 60, 220), mat="Neon")
    m.ell("DoorArch", (0.75, 0.5, 0.06), (0, 1.42, -0.72), (150, 60, 220), mat="Neon")
    m.light(door, (170, 90, 255), 1.6, 7)
    m.ball("Skull", 0.32, (0, 1.95, -0.85), (235, 230, 215))
    for s in (-1, 1):
        m.ball("SkullEye", 0.09, (s * 0.07, 1.98, -1.0), (30, 20, 40))
    for (x, z) in [(-1.1, -0.95), (1.1, -0.95)]:
        m.cyl("Candle", 0.32, 0.14, (x, 0.41, z), (245, 240, 220))
        flame = m.ell("Flame", (0.1, 0.18, 0.1), (x, 0.66, z), (255, 170, 60), mat="Neon")
    m.blk("Crack", (0.04, 0.6, 0.03), (0.6, 1.2, -0.71), (70, 65, 80), R=rot(z=25))
    m.ell("Moss", (0.6, 0.18, 0.5), (-0.7, 2.0, 0.6), (90, 130, 80), mat="Grass")
    mist = m.blk("Mist", (0.1, 0.1, 0.1), (0, 0.4, -0.9), (200, 200, 220), tr=1)
    m.smoke(mist, (190, 170, 230), 0.07, 0.3, 1.0)
    return m


@model
def charging_station():
    m = Model("charging_station", kind="gadget")
    metal = (180, 185, 195)
    m.blk("Base", (2.2, 0.3, 1.7), (0, 0.15, 0.05), (70, 75, 85), mat="DiamondPlate")
    m.blk("Pillar", (1.0, 2.2, 0.8), (0, 1.4, 0.15), metal, mat="Metal", refl=0.1)
    cap = m.blk("Cap", (1.15, 0.2, 0.95), (0, 2.6, 0.15), (60, 200, 255), mat="Neon")
    scr = m.blk("Screen", (0.7, 0.5, 0.05), (0, 1.95, -0.27), (40, 220, 255), mat="Neon")
    m.blk("Bolt", (0.14, 0.42, 0.04), (0, 1.3, -0.27), (255, 220, 50), mat="Neon", R=rot(z=22))
    for k in range(3):
        m.blk("Bar", (0.16, 0.24, 0.04), (-0.22 + k * 0.22, 0.78, -0.27), (90, 255, 120), mat="Neon")
    for s in (-1, 1):
        m.rod("Cable", (s * 0.5, 1.25, 0.1), (s * 0.95, 0.42, -0.35), 0.1, (30, 30, 35))
        m.blk("Plug", (0.26, 0.3, 0.26), (s * 0.98, 0.45, -0.4), (240, 200, 40))
        m.blk("PlugPin", (0.05, 0.05, 0.12), (s * 0.98 - 0.05, 0.45, -0.58), (220, 220, 230), mat="Metal")
        m.blk("PlugPin2", (0.05, 0.05, 0.12), (s * 0.98 + 0.05, 0.45, -0.58), (220, 220, 230), mat="Metal")
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
            m.cyl("WheelHub", 0.18, 0.2, (s * 0.97, 0.35, z), (200, 170, 70), axis="x", mat="Metal")
        m.blk("Upright", (0.22, 1.4, 0.22), (s * 0.75, 1.15, -0.2), wood, mat="WoodPlanks")
    m.blk("CrossBeam", (1.75, 0.22, 0.24), (0, 1.8, -0.2), wood, mat="WoodPlanks")
    m.blk("CrossPad", (0.5, 0.14, 0.3), (0, 1.95, -0.2), (90, 60, 40), mat="Fabric")
    m.cyl("Axle", 1.5, 0.16, (0, 0.62, 0.25), (110, 110, 115), axis="x", mat="Metal")
    m.rod("Arm", (0, 0.62, 0.25), (0, 1.65, 1.05), 0.2, wood, mat="WoodPlanks")
    m.cyl("Bucket", 0.4, 0.62, (0, 1.75, 1.12), (120, 115, 105), mat="Metal")
    m.blk("ScrapCan", (0.2, 0.28, 0.2), (-0.12, 2.02, 1.1), (190, 195, 200), mat="Metal", R=rot(z=20))
    m.ring("ScrapGear", (0.12, 2.02, 1.15), 0.14, 0.06, (200, 150, 60), normal="z", segments=8, mat="Metal")
    m.blk("ScrapBolt", (0.08, 0.2, 0.08), (0.02, 2.06, 1.25), (150, 150, 160), mat="Metal", R=rot(x=30))
    m.ring("Tire", (0, 0.55, 0.95), 0.32, 0.16, (40, 40, 45), normal="x", segments=10, mat="Rubber")
    m.blk("Rope", (0.06, 0.06, 0.9), (0.3, 0.8, 0.55), (210, 190, 140), mat="Fabric", R=rot(x=-35))
    return m


# Hero figurines stand on pedestals next to each player's lanes.

@model
def hero_bonk():
    m = Model("hero_bonk", kind="hero")
    frog = (110, 190, 80)
    robe = (110, 60, 180)
    m.ell("Robe", (1.5, 1.7, 1.3), (0, 0.85, 0), robe, mat="Fabric")
    m.cyl("RobeHem", 0.2, 1.6, (0, 0.1, 0), (90, 45, 150), mat="Fabric")
    for k in range(4):
        m.ell("RobeStar", (0.18, 0.18, 0.05), (-0.4 + k * 0.28, 0.6 + (k % 2) * 0.4, -0.64), (255, 225, 80), mat="Neon")
    m.ell("Head", (1.5, 1.0, 1.25), (0, 2.05, -0.05), frog)
    m.ell("Belly", (0.9, 0.5, 0.4), (0, 1.75, -0.5), (220, 240, 170))
    for s in (-1, 1):
        m.ball("EyeBump", 0.6, (s * 0.42, 2.55, -0.25), frog)
    m.eyes(2.58, -0.5, 0.84, 0.42, lid=frog)
    m.ell("Mouth", (1.0, 0.1, 0.2), (0, 1.88, -0.62), (60, 100, 40))
    m.cheeks(2.0, -0.6, 1.1, 0.25)
    # wizard hat sitting between the eyes
    m.cyl("HatBrim", 0.08, 1.2, (0, 2.85, 0.15), robe)
    for k in range(4):
        m.cyl("HatCone", 0.32, 0.75 - k * 0.16, (0.06 * k, 3.05 + k * 0.28, 0.15 + 0.03 * k), robe, R=rot(z=-8 * k))
    m.ball("HatTip", 0.16, (0.26, 4.05, 0.28), (255, 225, 80), mat="Neon")
    # arms and a staff with a glowing orb
    for s in (-1, 1):
        m.rod("Sleeve", (s * 0.6, 1.45, 0), (s * 0.95, 1.05, -0.35), 0.35, robe, mat="Fabric", shape="E")
        m.ball("Hand", 0.3, (s * 1.0, 1.0, -0.4), frog)
    m.cyl("Staff", 2.6, 0.12, (1.0, 1.4, -0.42), (120, 80, 45))
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
        m.ell("Shoe", (0.4, 0.25, 0.6), (s * 0.22, 0.12, -0.15), (240, 240, 245))
    m.ell("Body", (1.3, 1.4, 1.0), (0, 1.55, 0), suit, mat="Fabric")
    m.blk("Stripe", (0.12, 1.2, 0.05), (-0.35, 1.55, -0.5), (255, 220, 60), R=rot(z=12))
    m.blk("Stripe", (0.12, 1.2, 0.05), (0.35, 1.55, -0.5), (255, 220, 60), R=rot(z=-12))
    m.blk("BoltLogo", (0.12, 0.45, 0.04), (0, 1.65, -0.52), (255, 220, 60), mat="Neon", R=rot(z=20))
    m.ball("Head", 1.0, (0, 2.6, 0), skin)
    m.ball("Bun", 0.6, (0, 3.2, 0.15), (220, 220, 230))
    m.ell("Hair", (1.05, 0.55, 1.0), (0, 2.9, 0.05), (220, 220, 230))
    m.cyl("Headband", 0.12, 1.02, (0, 2.85, 0), (255, 80, 80), mat="Fabric")
    m.eyes(2.62, -0.45, 0.38, 0.22, lid=skin)
    for s in (-1, 1):
        m.ring("Glasses", (s * 0.19, 2.62, -0.5), 0.14, 0.035, (60, 40, 30), normal="z", segments=8)
    m.smile(2.38, -0.46, 0.22)
    m.cheeks(2.5, -0.44, 0.7, 0.18)
    # arms holding a bowling ball
    for s in (-1, 1):
        m.rod("Arm", (s * 0.55, 1.95, 0), (s * 0.45, 1.4, -0.55), 0.24, suit, mat="Fabric")
    m.ball("BowlingBall", 0.85, (0, 1.3, -0.75), (80, 30, 120), refl=0.35)
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
    m.blk("Hips", (2.4, 0.9, 2.0), (0, 2.45, 0.2), (90, 95, 110), mat="Metal")
    for s in (-1, 1):
        m.rod("Thigh", (s * 0.6, 2.4, -0.2), (s * 0.6, 2.4, -1.4), 0.6, (120, 125, 140), mat="Metal")
        m.rod("Shin", (s * 0.6, 2.4, -1.4), (s * 0.6, 0.4, -1.5), 0.5, (120, 125, 140), mat="Metal")
        m.blk("Foot", (0.7, 0.35, 1.0), (s * 0.6, 0.18, -1.7), (70, 75, 90), mat="Metal")
    m.ell("Torso", (2.8, 2.6, 2.0), (0, 4.1, 0.3), shell, refl=0.15)
    m.ell("Chest", (1.6, 1.2, 0.4), (0, 4.1, -0.62), accent)
    m.cyl("ChestLight", 0.1, 0.5, (0, 4.15, -0.84), (120, 255, 160), axis="z", mat="Neon")
    for s in (-1, 1):
        m.ball("Shoulder", 0.9, (s * 1.5, 4.8, 0.3), (120, 125, 140), mat="Metal")
        m.rod("UpperArm", (s * 1.6, 4.7, 0.3), (s * 1.75, 3.9, -0.9), 0.5, shell)
        m.rod("Forearm", (s * 1.75, 3.9, -0.9), (s * 1.0, 4.0, -2.2), 0.45, shell)
        m.ball("Hand", 0.6, (s * 0.95, 4.0, -2.3), accent)
    m.cyl("Neck", 0.5, 0.6, (0, 5.5, 0.3), (120, 125, 140), mat="Metal")
    m.ell("Head", (2.4, 1.9, 2.0), (0, 6.6, 0.3), shell, refl=0.15)
    m.blk("Face", (1.8, 1.1, 0.12), (0, 6.6, -0.68), (25, 30, 45), R=rot(x=0))
    for s in (-1, 1):
        m.ell("Eye", (0.45, 0.55, 0.06), (s * 0.42, 6.75, -0.76), (120, 230, 255), mat="Neon")
        m.cyl("Ear", 0.3, 0.7, (s * 1.25, 6.6, 0.3), accent, axis="x")
    m.ell("Mouth", (0.6, 0.14, 0.05), (0, 6.3, -0.76), (120, 230, 255), mat="Neon")
    m.rod("Antenna", (0, 7.5, 0.3), (0.2, 8.3, 0.4), 0.1, (180, 180, 190), mat="Metal")
    tip = m.ball("AntennaTip", 0.35, (0.2, 8.4, 0.4), (255, 80, 80), mat="Neon")
    m.light(tip, (255, 120, 120), 0.8, 5)
    return m
