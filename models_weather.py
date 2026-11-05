# Weather family models (soft puffy clouds, ice, lightning, fog)
import math
from modelkit import Model, rot, Rx, Ry, Rz, WHITE, PUPIL, shade, ell_front, cyl_front, front_of

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


def cloud(m, cx, cy, cz, scale, color, mat="SmoothPlastic", tr=0, name="Cloud", shaded=True):
    """A puffy cloud: big main puffs, lighter puffs on top and darker ones underneath for volume."""
    puffs = [(0, 0, 0, 1.3), (-0.7, -0.15, 0.05, 0.95), (0.7, -0.15, 0.05, 0.95), (-0.35, 0.35, 0.15, 0.9),
             (0.35, 0.4, 0.15, 0.85), (0, -0.25, -0.25, 1.0), (-1.15, -0.3, 0.1, 0.65), (1.15, -0.3, 0.1, 0.65)]
    for (x, y, z, d) in puffs:
        m.ball(name, d * scale, (cx + x * scale, cy + y * scale, cz + z * scale), color, mat=mat, tr=tr)
    if shaded:
        light = shade(color, 1.25)
        dark = shade(color, 0.8)
        for (x, y, z, d) in [(-0.15, 0.62, 0.1, 0.55), (0.5, 0.55, 0.3, 0.45), (-0.6, 0.3, 0.3, 0.45)]:
            m.ball(name, d * scale, (cx + x * scale, cy + y * scale, cz + z * scale), light, mat=mat, tr=tr)
        for (x, y, z, d) in [(-0.5, -0.45, 0.1, 0.7), (0.45, -0.45, 0.1, 0.7), (0, -0.5, 0.35, 0.75)]:
            m.ball(name, d * scale, (cx + x * scale, cy + y * scale, cz + z * scale), dark, mat=mat, tr=tr)


def bolt(m, name, top, h, w, color=(255, 230, 60), glow=None):
    """A zigzag lightning bolt hanging down from top (three blocks and a point)."""
    x, y, z = top
    a = m.blk(name, (w, h * 0.4, w * 0.5), (x, y - h * 0.18, z), color, mat="Neon", R=rot(z=-25))
    m.blk(name, (w, h * 0.38, w * 0.5), (x - h * 0.1, y - h * 0.5, z), color, mat="Neon", R=rot(z=25))
    m.wedge(name, (w * 0.5, h * 0.3, w * 1.1), (x - h * 0.02, y - h * 0.82, z), color, mat="Neon", R=rot(z=180, y=90))
    if glow:
        m.blk(name + "Glow", (w * 1.8, h * 0.42, w * 0.3), (x, y - h * 0.18, z + w * 0.3), glow, mat="Neon", R=rot(z=-25), tr=0.6)
    return a


def drop(m, name, pos, d, color=(90, 170, 255), tr=0.2):
    """A teardrop: a round bottom and a pointed top."""
    x, y, z = pos
    m.ball(name, d, (x, y, z), color, mat="Glass", tr=tr, refl=0.35)
    m.ell(name, (d * 0.55, d * 1.1, d * 0.55), (x, y + d * 0.45, z), color, mat="Glass", tr=tr, refl=0.35)


@model
def drizzle_sprite():
    m = Model("drizzle_sprite")
    c = (235, 240, 250)
    cloud(m, 0, 1.75, 0, 0.85, c)
    m.eyes(1.75, -0.95, 0.42, 0.3, lid=c, iris=(80, 150, 230), lash=2, z_back=0.03)
    m.grin(1.5, -0.98, 0.24, open_=True, curve=0.25)
    m.cheeks(1.58, -0.92, 0.8, 0.2)
    # a little rainbow arching behind
    for k, col in enumerate([(240, 80, 80), (250, 170, 60), (250, 230, 80), (110, 210, 110), (90, 160, 240)]):
        r = 1.15 - k * 0.09
        for j in range(7):
            a1, a2 = math.pi * j / 7, math.pi * (j + 1) / 7
            m.rod("Rainbow", (math.cos(a1) * r, 1.6 + math.sin(a1) * r, 0.6), (math.cos(a2) * r, 1.6 + math.sin(a2) * r, 0.6), 0.1, col, mat="Neon", tr=0.25)
    # teardrops falling into a rippling puddle
    for (x, y, z, d) in [(-0.6, 0.95, -0.1, 0.17), (-0.15, 0.6, 0.15, 0.15), (0.3, 0.85, -0.2, 0.17), (0.7, 0.45, 0.1, 0.14), (-0.4, 0.3, -0.25, 0.14), (0.1, 0.22, 0.2, 0.13)]:
        drop(m, "Drop", (x, y, z), d)
    m.cyl("Puddle", 0.04, 1.4, (0, 0.02, 0), (90, 170, 255), mat="Glass", tr=0.3, refl=0.4)
    m.ring("Ripple", (0.1, 0.05, 0.2), 0.3, 0.03, (190, 225, 255), normal="y", segments=10, tr=0.2)
    m.ring("Ripple", (-0.35, 0.05, -0.2), 0.2, 0.03, (190, 225, 255), normal="y", segments=8, tr=0.2)
    # little umbrella hat with panels, ribs, a tip and a curled handle
    m.cyl("Pole", 0.5, 0.06, (0.1, 2.75, 0), (80, 80, 90))
    m.ell("Umbrella", (1.05, 0.38, 1.05), (0.1, 3.0, 0), (255, 220, 60))
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        m.ell("UmbrellaPanel", (0.5, 0.39, 0.22), (0.1 + math.cos(a) * 0.22, 3.0, math.sin(a) * 0.22), (255, 140, 160), R=rot(y=-math.degrees(a)))
    for k in range(8):
        a = k * math.pi / 4
        m.ball("UmbrellaTip", 0.07, (0.1 + math.cos(a) * 0.52, 2.95, math.sin(a) * 0.52), (240, 240, 245))
    m.ball("UmbrellaTip", 0.1, (0.1, 3.2, 0), (240, 240, 245))
    return m


@model
def grumpy_cloud():
    m = Model("grumpy_cloud")
    c = (120, 125, 140)
    cloud(m, 0, 2.0, 0, 1.05, c)
    m.eyes(2.05, -1.18, 0.55, 0.36, lid=c, look=(0, -0.04), iris=(240, 200, 60), z_back=0.03)
    for s in (-1, 1):
        m.brow(s * 0.28, 2.34, -1.2, 0.42, (40, 40, 50), s, tilt=22, d=0.12, arch=0.0)
    m.grin(1.6, -1.25, 0.55, color=(40, 40, 50), curve=-0.25, bend=0.05)
    m.ell("PuffCheek", (0.4, 0.3, 0.25), (-0.62, 1.7, -1.05), shade(c, 1.1))
    m.ell("PuffCheek", (0.4, 0.3, 0.25), (0.62, 1.7, -1.05), shade(c, 1.1))
    # a little steam cloud huffing from the side
    for (x, y, d) in [(1.5, 2.6, 0.3), (1.75, 2.8, 0.22), (1.92, 3.0, 0.15)]:
        m.ball("Huff", d, (x, y, -0.3), (210, 215, 225), tr=0.3)
    b = bolt(m, "Bolt", (0.3, 1.35, -0.3), 1.2, 0.25, glow=(255, 250, 200))
    m.light(b, (255, 230, 120), 1.2, 6)
    for (x, y, z) in [(-1.0, 0.9, -0.2), (0.9, 1.1, 0.4), (-0.4, 0.2, 0.6)]:
        m.ball("Spark", 0.1, (x * 0.4 + 0.3, y * 0.6, -0.3 + z * 0.3), (255, 250, 180), mat="Neon")
    for (x, y, z) in [(-0.7, 1.0, 0.2), (-0.4, 0.6, -0.1), (0.8, 0.8, 0.1), (-0.95, 0.55, 0.4)]:
        drop(m, "Drop", (x, y, z), 0.15, (120, 170, 230))
    return m


@model
def hailstone_hopper():
    m = Model("hailstone_hopper")
    ice = (180, 225, 250)
    deep = (120, 180, 230)
    frost = (235, 248, 255)
    m.ell("Body", (1.8, 1.4, 1.9), (0, 1.15, 0.1), ice, mat="Ice", refl=0.25)
    m.ell("Head", (1.5, 1.1, 1.2), (0, 1.75, -0.55), ice, mat="Ice", refl=0.25)
    # frosty spots and faceted ice chips
    m.scatter("Frost", (0, 1.15, 0.1), (1.8, 1.4, 1.9), 10, [frost, deep], seed=6, d=0.22, shape="dot", ymin=0.0)
    m.scatter("Chip", (0, 1.15, 0.1), (1.8, 1.4, 1.9), 6, [(220, 245, 255)], seed=16, d=0.14, shape="cube", ymin=0.2, mat="Glass")
    # eye bumps on top of the head
    for s in (-1, 1):
        m.ball("EyeBump", 0.62, (s * 0.37, 2.2, -0.82), ice, mat="Ice", refl=0.25)
    m.eyes(2.27, -1.0, 0.75, 0.48, lid=ice, iris=(60, 120, 200), z_back=0.03)
    m.grin(1.58, -1.12, 0.95, color=(60, 100, 150), curve=0.12, bend=0.12, d=0.08)
    m.cheeks(1.7, -1.05, 1.0, 0.22, color=(200, 230, 255))
    m.ell("Belly", (1.2, 0.9, 0.5), (0, 1.0, -0.6), frost, mat="Ice")
    # icicles hanging under the chin
    for k, x in enumerate((-0.35, -0.1, 0.15, 0.38)):
        m.ell("Icicle", (0.1, 0.3 + 0.08 * (k % 2), 0.1), (x, 1.2, -1.0 + abs(x) * 0.3), (220, 245, 255), mat="Glass", tr=0.15)
    # folded back legs and front feet with toes
    for s in (-1, 1):
        m.ell("Thigh", (0.6, 0.8, 1.3), (s * 0.85, 0.75, 0.45), deep, mat="Ice", R=rot(x=-25))
        m.ell("BackFoot", (0.55, 0.2, 1.1), (s * 0.95, 0.12, -0.05), deep, mat="Ice")
        m.ell("FrontFoot", (0.4, 0.2, 0.55), (s * 0.45, 0.12, -0.85), deep, mat="Ice")
        m.rod("FrontLeg", (s * 0.45, 0.85, -0.6), (s * 0.45, 0.2, -0.85), 0.22, deep, mat="Ice")
        for k in (-1, 0, 1):
            m.ball("Toe", 0.16, (s * 0.45 + k * 0.14, 0.1, -1.1), frost, mat="Ice")
            m.ball("Toe", 0.18, (s * 0.95 + k * 0.17, 0.1, -0.6), frost, mat="Ice")
    # ice crystals on the back
    for (x, y, z, a) in [(0, 2.05, 0.35, 0), (-0.45, 1.85, 0.6, -25), (0.45, 1.85, 0.6, 25), (0, 1.75, 0.9, 0), (-0.25, 1.95, 0.0, -12), (0.25, 1.95, 0.0, 12)]:
        top = (x + math.sin(math.radians(a)) * 0.5, y + 0.45, z + 0.15)
        m.rod("Crystal", (x, y - 0.2, z), top, 0.22, (220, 245, 255), mat="Glass", tr=0.15, refl=0.4, shape="B")
        m.ell("Crystal", (0.14, 0.24, 0.14), top, (245, 252, 255), mat="Glass", tr=0.1)
    # hailstones bouncing around
    for (x, z) in [(-1.3, -0.6), (1.4, 0.4), (1.2, -0.9), (-1.2, 0.8)]:
        m.ball("Hail", 0.3, (x, 0.15, z), (240, 250, 255), mat="Ice")
        m.ball("HailShine", 0.1, (x - 0.06, 0.24, z - 0.08), WHITE)
    return m


@model
def fog_bank():
    m = Model("fog_bank")
    fog = (225, 230, 240)
    pink = (235, 200, 215)
    body = m.ell("Body", (1.9, 1.6, 2.4), (0, 1.25, 0), fog, tr=0.25)
    m.smoke(body, (235, 235, 245), 0.12, 0.3, 2.5)
    m.ell("Core", (1.3, 1.1, 1.7), (0, 1.25, 0), (200, 205, 220), tr=0.1)
    # swirls of mist inside
    for k in range(3):
        m.ring("Swirl", (0, 1.25 + (k - 1) * 0.25, 0.1), 0.6 - k * 0.1, 0.06, (245, 245, 252), normal="y", segments=10, tr=0.35, R=rot(x=10 * k, z=-8 * k))
    m.cyl("Snout", 0.3, 0.62, (0, 1.2, -1.25), pink, axis="z")
    m.ring("Snout", (0, 1.2, -1.41), 0.3, 0.05, shade(pink, 0.9), normal="z", segments=10)
    for s in (-1, 1):
        m.ell("Nostril", (0.1, 0.16, 0.06), (s * 0.12, 1.2, -1.42), (120, 90, 110))
        m.ell("Ear", (0.42, 0.52, 0.15), (s * 0.5, 2.05, -0.55), pink, R=rot(x=-20, z=s * -25))
        m.ell("EarInner", (0.25, 0.32, 0.08), (s * 0.5, 2.03, -0.63), (215, 160, 185), R=rot(x=-20, z=s * -25))
        for sz in (-1, 1):
            m.cyl("Leg", 0.55, 0.4, (s * 0.55, 0.3, sz * 0.7), fog, tr=0.2)
            m.cyl("Hoof", 0.14, 0.42, (s * 0.55, 0.07, sz * 0.7), pink)
    m.eyes(1.62, -1.02, 0.65, 0.34, lid=fog, sleepy=True, iris=(120, 140, 200))
    m.cheeks(1.32, -1.0, 1.15, 0.24)
    m.grin(0.8, -1.08, 0.3, curve=0.2, color=(130, 110, 130), surface=ell_front((0, 1.25, 0), (1.9, 1.6, 2.4)))
    # coin slot with a coin dropping in, and a cork stopper underneath
    m.rbox("CoinSlot", (0.85, 0.08, 0.2), (0, 2.06, 0.1), (60, 60, 70), 0.04)
    m.cyl("Coin", 0.08, 0.5, (0, 2.25, 0.1), (240, 200, 60), mat="Metal", axis="x", refl=0.3)
    m.cyl("CoinRim", 0.09, 0.4, (0, 2.25, 0.1), (255, 220, 100), mat="Metal", axis="x")
    m.cyl("Coin", 0.06, 0.32, (0.55, 0.1, -0.55), (240, 200, 60), mat="Metal")
    m.cyl("Cork", 0.2, 0.36, (0, 0.5, 0.2), (190, 150, 100))
    m.chain("Tail", [(0, 1.4, 1.2), (0.15, 1.6, 1.4), (-0.05, 1.75, 1.45), (0.1, 1.85, 1.35)], 0.1, pink, joints=False)
    # fog wisps
    for (x, y, z, d) in [(-1.2, 0.5, -0.5, 0.8), (1.2, 0.6, 0.3, 0.9), (0.9, 0.3, -1.0, 0.7), (-1.0, 0.35, 0.9, 0.75), (0.3, 0.25, 1.2, 0.6)]:
        m.ball("Wisp", d, (x, y, z), (240, 240, 248), tr=0.55)
    return m


@model
def lightning_llama():
    m = Model("lightning_llama")
    wool = (250, 245, 225)
    face = (230, 215, 185)
    m.ell("Body", (1.4, 1.3, 2.4), (0, 1.75, 0.25), wool, mat="Fabric")
    m.scatter("Fluff", (0, 1.75, 0.25), (1.4, 1.3, 2.4), 12, [wool, shade(wool, 0.95)], seed=21, d=0.35, shape="dot", ymin=-0.2, mat="Fabric")
    m.ell("Neck", (0.7, 1.6, 0.75), (0, 2.6, -0.75), wool, mat="Fabric", R=rot(x=12))
    for k in range(3):
        m.ball("Fluff", 0.4, (0, 2.2 + k * 0.4, -1.02 - k * 0.03), wool, mat="Fabric")
    m.ell("Head", (0.8, 0.75, 1.15), (0, 3.45, -1.05), face)
    m.ell("Muzzle", (0.6, 0.5, 0.5), (0, 3.3, -1.6), (240, 230, 210))
    m.ell("Nose", (0.25, 0.12, 0.08), (0, 3.38, -1.84), (80, 60, 60))
    m.grin(3.18, -1.82, 0.22, curve=0.3, color=(90, 60, 60))
    m.eyes(3.6, -1.42, 0.55, 0.25, lid=face, iris=(120, 80, 40), lash=3, z_back=0.04)
    for s in (-1, 1):
        # banana-shaped ears
        m.ell("Ear", (0.18, 0.58, 0.22), (s * 0.3, 4.02, -0.95), face, R=rot(z=s * -15))
        m.ell("EarInner", (0.08, 0.38, 0.1), (s * 0.3, 4.02, -1.04), (210, 170, 150), R=rot(z=s * -15))
        for sz in (-1, 1):
            z = 0.25 + sz * 0.75
            m.cyl("Leg", 1.2, 0.32, (s * 0.42, 0.6, z), face)
            m.ball("Knee", 0.36, (s * 0.42, 0.68, z), shade(face, 0.95))
            m.ell("Hoof", (0.38, 0.2, 0.42), (s * 0.42, 0.1, z - 0.05), (90, 80, 70))
            m.blk("Hoof", (0.04, 0.18, 0.2), (s * 0.42, 0.1, z - 0.2), (50, 45, 40))
    # woven saddle blanket with a zigzag and tassels
    m.ell("Blanket", (1.5, 0.6, 1.2), (0, 2.3, 0.3), (210, 60, 70), mat="Fabric")
    for s in (-1, 1):
        for k in range(4):
            m.blk("Zigzag", (0.04, 0.12, 0.24), (s * 0.73, 2.1, -0.15 + k * 0.3), (255, 210, 50), R=rot(x=40 if k % 2 else -40))
        for k in range(3):
            m.ball("Tassel", 0.14, (s * 0.72, 1.85, -0.1 + k * 0.4), (60, 120, 210), mat="Fabric")
    # fluffy wool tufts and a storm-cloud hairdo with a spark
    for (x, y, z) in [(0, 2.45, 1.0), (0.3, 2.35, 1.25)]:
        m.ball("Tuft", 0.55, (x, y, z), wool, mat="Fabric")
    for (x, z, d) in [(0, -1.0, 0.55), (-0.25, -0.85, 0.42), (0.25, -0.85, 0.42), (0, -0.7, 0.45)]:
        m.ball("Hair", d, (x, 3.9, z), (110, 115, 135))
    m.ball("Hair", 0.3, (0.0, 3.85, -1.35), (140, 145, 165))
    bolt(m, "Spark", (0.15, 3.75, -1.6), 0.45, 0.1)
    # lightning bolt marks on both sides
    for s in (-1, 1):
        m.blk("Bolt", (0.06, 0.6, 0.18), (s * 0.71, 1.95, 0.05), (255, 220, 40), mat="Neon", R=rot(x=25))
        m.blk("Bolt", (0.06, 0.5, 0.18), (s * 0.71, 1.55, 0.3), (255, 220, 40), mat="Neon", R=rot(x=-25))
    m.ball("Tail", 0.45, (0, 2.0, 1.5), wool, mat="Fabric")
    m.ball("TailTip", 0.3, (0, 1.82, 1.65), wool, mat="Fabric")
    sp = m.ball("Spark", 0.2, (0, 4.25, -0.95), (255, 240, 120), mat="Neon")
    m.sparkles(sp, (255, 240, 100))
    m.light(sp, (255, 240, 150), 1, 6)
    return m


@model
def tornado_twins():
    m = Model("tornado_twins")
    for s, tint in ((-1, (175, 185, 205)), (1, (160, 175, 200))):
        cx = s * 0.85
        for k in range(6):
            y = 0.3 + k * 0.55
            d = 0.4 + k * 0.27
            off = math.sin(k * 0.9 + s) * 0.12
            m.cyl("Funnel", 0.6, d, (cx + off, y, 0), tint, tr=0.15 if k > 0 else 0)
            # a slanted swirl band on every layer
            m.ring("Swirl", (cx + off, y + 0.22, 0), d / 2 + 0.02, 0.05, (225, 230, 242), normal="y", segments=8 + k, R=rot(x=10, z=6 * s))
        top = 0.3 + 5 * 0.55
        m.cyl("Funnel", 0.1, 1.75, (cx + math.sin(5 * 0.9 + s) * 0.12, top + 0.33, 0), shade(tint, 0.85))
        ex = cx + math.sin(4 * 0.9 + s) * 0.12
        m.eyes(2.45, -0.88, 0.48, 0.32, lid=tint, x=ex, iris=(90, 120, 200) if s > 0 else (200, 90, 90), z_back=0.03)
        if s < 0:
            m.brow(ex - 0.24, 2.73, -0.86, 0.26, (70, 80, 100), -1, tilt=18)
            m.brow(ex + 0.24, 2.73, -0.86, 0.26, (70, 80, 100), 1, tilt=18)
        mx = cx + math.sin(3 * 0.9 + s) * 0.12
        m.grin(2.12, -0.92, 0.3, x=mx, open_=(s > 0), curve=0.25 if s > 0 else -0.1, bend=0.04)
    # holding hands
    m.rod("Arm", (-0.45, 1.6, -0.2), (0.0, 1.35, -0.45), 0.14, (170, 180, 200))
    m.rod("Arm", (0.45, 1.6, -0.2), (0.0, 1.35, -0.45), 0.14, (170, 180, 200))
    m.ball("Hand", 0.22, (-0.05, 1.36, -0.46), (170, 180, 200))
    m.ball("Hand", 0.22, (0.05, 1.34, -0.44), (170, 180, 200))
    # debris spinning around: leaves, a plank, a sign and a tiny cow-spotted bucket
    for (x, y, z, c) in [(-1.7, 2.6, 0.3, (90, 170, 70)), (1.75, 2.0, -0.4, (200, 150, 80)), (-1.5, 1.2, -0.6, (90, 170, 70)), (1.6, 3.0, 0.5, (220, 60, 60))]:
        m.blk("Debris", (0.28, 0.06, 0.18), (x, y, z), c, R=rot(30, 50, 20))
    m.blk("Plank", (0.7, 0.1, 0.18), (-1.75, 3.2, -0.2), (150, 105, 60), mat="Wood", R=rot(10, 30, 35))
    m.cyl("Bucket", 0.3, 0.3, (1.85, 1.2, 0.3), (240, 240, 240), R=rot(z=40))
    m.ell("BucketSpot", (0.12, 0.1, 0.05), (1.82, 1.22, 0.15), (30, 30, 30))
    m.cyl("Dust", 0.08, 2.8, (0, 0.04, 0), (200, 190, 170), tr=0.4)
    m.ring("Dust", (0, 0.1, 0), 1.45, 0.12, (210, 200, 180), normal="y", segments=14, tr=0.5)
    return m


@model
def stormlord_nimbus():
    m = Model("stormlord_nimbus")
    c = (90, 95, 120)
    cloud(m, 0, 3.0, 0.1, 1.55, c)
    cloud(m, 0, 2.2, 0.3, 1.0, (75, 80, 105), shaded=False)
    # fierce glowing eyes with heavy brows
    for s in (-1, 1):
        e = m.ell("Eye", (0.52, 0.34, 0.25), (s * 0.45, 3.15, -1.7), (220, 240, 255), mat="Neon", R=rot(z=s * -12))
        m.ell("EyeGlow", (0.75, 0.5, 0.15), (s * 0.45, 3.15, -1.66), (160, 200, 255), mat="Neon", tr=0.65, R=rot(z=s * -12))
        m.brow(s * 0.45, 3.45, -1.72, 0.7, (40, 45, 60), s, tilt=22, d=0.18, arch=0.04)
    m.light(e, (190, 220, 255), 1.0, 6)
    m.grin(2.68, -1.8, 0.75, color=(30, 30, 45), curve=-0.12, d=0.12, bend=0.08, open_=True, teeth=4, tongue=(40, 40, 60))
    # rain beard: strands of different lengths ending in drops
    for k in range(9):
        x = -0.8 + k * 0.2
        ln = 0.8 + (0.45 if k % 2 == 0 else 0.1) - abs(x) * 0.3
        m.blk("Beard", (0.09, ln, 0.09), (x, 2.3 - ln / 2, -1.45 + abs(x) * 0.15), (110, 170, 240), mat="Glass", tr=0.25)
        drop(m, "Beard", (x, 2.3 - ln - 0.05, -1.45 + abs(x) * 0.15), 0.13, (130, 185, 250))
    # crown of zigzag lightning on a glowing band
    crown = None
    for k in range(5):
        x = -0.8 + k * 0.4
        h = 0.85 if k == 2 else 0.6
        p = m.blk("Crown", (0.16, h * 0.55, 0.16), (x, 4.3 + h * 0.2, -0.2), (255, 230, 60), mat="Neon", R=rot(z=(k - 2) * -10 - 18))
        m.blk("Crown", (0.16, h * 0.55, 0.16), (x + 0.06, 4.3 + h * 0.6, -0.2), (255, 230, 60), mat="Neon", R=rot(z=(k - 2) * -10 + 18))
        m.wedge("Crown", (0.12, 0.2, 0.16), (x + 0.02, 4.3 + h * 0.95, -0.2), (255, 245, 150), mat="Neon")
        if k == 2:
            crown = p
    m.cyl("CrownBand", 0.18, 1.9, (0, 4.25, -0.1), (255, 210, 50), mat="Neon", R=rot(x=-8))
    m.gem("CrownGem", (0, 4.25, -1.05), 0.26, (120, 200, 255), glow=True)
    m.light(crown, (200, 220, 255), 2, 10)
    m.sparkles(crown, (255, 240, 120))
    # cloud arms with puffy fists and a lightning scepter with a storm orb
    m.rod("Arm", (-1.5, 2.7, -0.2), (-2.0, 2.1, -0.8), 0.6, c, shape="E")
    m.rod("Arm", (1.5, 2.7, -0.2), (2.0, 2.3, -0.8), 0.6, c, shape="E")
    for s, y in ((1, 2.25), (-1, 2.05)):
        m.ball("Hand", 0.6, (s * 2.05, y, -0.85), c)
        m.ball("Knuckle", 0.25, (s * 1.95, y + 0.2, -1.1), shade(c, 1.15))
        m.ball("Knuckle", 0.25, (s * 2.15, y + 0.15, -1.1), shade(c, 1.15))
    m.blk("Scepter", (0.2, 0.9, 0.2), (2.15, 2.85, -0.9), (255, 230, 60), mat="Neon", R=rot(z=-20))
    m.blk("Scepter", (0.2, 0.8, 0.2), (2.15, 3.55, -0.9), (255, 230, 60), mat="Neon", R=rot(z=20))
    m.blk("Scepter", (0.2, 0.7, 0.2), (2.1, 1.95, -0.9), (255, 230, 60), mat="Neon", R=rot(z=15))
    orb = m.ball("Orb", 0.42, (2.05, 4.05, -0.9), (170, 200, 255), mat="Glass", tr=0.3, refl=0.3)
    m.ball("StaffGem", 0.2, (2.05, 4.05, -0.9), (255, 250, 200), mat="Neon")
    m.sparkles(orb, (200, 220, 255))
    # rain under the cloud and a rippling puddle
    for (x, z) in [(-1.0, 0.2), (-0.4, 0.6), (0.5, 0.4), (1.1, 0.0), (0.0, 0.9), (-0.7, -0.3), (0.8, 0.9)]:
        m.ell("Rain", (0.08, 0.5, 0.08), (x, 0.9, z), (120, 170, 240), mat="Glass", tr=0.3)
    m.cyl("Puddle", 0.05, 2.6, (0, 0.03, 0.2), (100, 150, 220), mat="Glass", tr=0.35, refl=0.3)
    for (x, z, r) in [(-0.4, 0.5, 0.3), (0.6, 0.1, 0.22), (0.1, 1.0, 0.18)]:
        m.ring("Ripple", (x, 0.07, z), r, 0.03, (180, 210, 255), normal="y", segments=8, tr=0.2)
    return m
