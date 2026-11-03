# Weather family models (clouds, ice, lightning, fog)
import math
from modelkit import Model, rot, WHITE, PUPIL

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


def cloud(m, cx, cy, cz, scale, color, mat="SmoothPlastic", tr=0, name="Cloud"):
    puffs = [(0, 0, 0, 1.3), (-0.7, -0.15, 0.05, 0.95), (0.7, -0.15, 0.05, 0.95), (-0.35, 0.35, 0.15, 0.9),
             (0.35, 0.4, 0.15, 0.85), (0, -0.25, -0.25, 1.0), (-1.15, -0.3, 0.1, 0.65), (1.15, -0.3, 0.1, 0.65)]
    for (x, y, z, d) in puffs:
        m.ball(name, d * scale, (cx + x * scale, cy + y * scale, cz + z * scale), color, mat=mat, tr=tr)


@model
def drizzle_sprite():
    m = Model("drizzle_sprite")
    c = (235, 240, 250)
    cloud(m, 0, 1.75, 0, 0.85, c)
    m.eyes(1.75, -0.95, 0.42, 0.3, lid=c)
    m.smile(1.5, -0.98, 0.22, open_=True)
    m.cheeks(1.58, -0.92, 0.8, 0.2)
    for (x, y, z) in [(-0.6, 0.95, -0.1), (-0.15, 0.6, 0.15), (0.3, 0.85, -0.2), (0.7, 0.45, 0.1), (-0.4, 0.25, -0.25), (0.1, 0.15, 0.2)]:
        m.ell("Drop", (0.16, 0.3, 0.16), (x, y, z), (90, 170, 255), mat="Glass", tr=0.2, refl=0.3)
    m.cyl("Puddle", 0.04, 1.4, (0, 0.02, 0), (90, 170, 255), mat="Glass", tr=0.3, refl=0.4)
    # little umbrella hat
    m.cyl("Pole", 0.5, 0.06, (0.1, 2.75, 0), (80, 80, 90))
    m.ell("Umbrella", (1.0, 0.35, 1.0), (0.1, 3.0, 0), (255, 220, 60))
    return m


@model
def grumpy_cloud():
    m = Model("grumpy_cloud")
    c = (120, 125, 140)
    cloud(m, 0, 2.0, 0, 1.05, c)
    m.eyes(2.05, -1.18, 0.55, 0.36, lid=c, angry=22, look=(0, -0.04))
    m.ell("Frown", (0.5, 0.15, 0.15), (0, 1.62, -1.25), (40, 40, 50), R=rot(z=0))
    m.ell("FrownL", (0.15, 0.15, 0.12), (-0.25, 1.56, -1.24), (40, 40, 50))
    m.ell("FrownR", (0.15, 0.15, 0.12), (0.25, 1.56, -1.24), (40, 40, 50))
    bolt = m.blk("Bolt", (0.25, 0.7, 0.12), (0.25, 1.05, -0.3), (255, 230, 60), mat="Neon", R=rot(z=-25))
    m.blk("Bolt", (0.25, 0.65, 0.12), (0.05, 0.55, -0.3), (255, 230, 60), mat="Neon", R=rot(z=25))
    m.wedge("BoltTip", (0.14, 0.35, 0.3), (0.2, 0.15, -0.3), (255, 230, 60), mat="Neon", R=rot(z=180, y=90))
    m.light(bolt, (255, 230, 120), 1.2, 6)
    for (x, y, z) in [(-0.7, 1.0, 0.2), (-0.4, 0.6, -0.1), (0.8, 0.8, 0.1)]:
        m.ell("Drop", (0.14, 0.26, 0.14), (x, y, z), (120, 170, 230), mat="Glass", tr=0.2)
    return m


@model
def hailstone_hopper():
    m = Model("hailstone_hopper")
    ice = (180, 225, 250)
    deep = (120, 180, 230)
    m.ell("Body", (1.8, 1.4, 1.9), (0, 1.15, 0.1), ice, mat="Ice", refl=0.2)
    m.ell("Head", (1.5, 1.1, 1.2), (0, 1.75, -0.55), ice, mat="Ice", refl=0.2)
    m.eyes(2.25, -0.95, 0.75, 0.48, lid=ice)
    m.ell("Mouth", (0.9, 0.12, 0.2), (0, 1.55, -1.12), (60, 100, 150))
    m.ell("Belly", (1.2, 0.9, 0.5), (0, 1.0, -0.6), (230, 245, 255), mat="Ice")
    # folded back legs and front feet
    for s in (-1, 1):
        m.ell("Thigh", (0.6, 0.8, 1.3), (s * 0.85, 0.75, 0.45), deep, mat="Ice", R=rot(x=-25))
        m.ell("BackFoot", (0.55, 0.2, 1.1), (s * 0.95, 0.12, -0.05), deep, mat="Ice")
        m.ell("FrontFoot", (0.4, 0.2, 0.55), (s * 0.45, 0.12, -0.85), deep, mat="Ice")
        m.rod("FrontLeg", (s * 0.45, 0.85, -0.6), (s * 0.45, 0.2, -0.85), 0.22, deep, mat="Ice")
    # ice crystals on the back
    for (x, y, z, a) in [(0, 2.05, 0.35, 0), (-0.45, 1.85, 0.6, -25), (0.45, 1.85, 0.6, 25), (0, 1.75, 0.9, 0)]:
        m.rod("Crystal", (x, y - 0.2, z), (x + math.sin(math.radians(a)) * 0.5, y + 0.45, z + 0.15), 0.22, (220, 245, 255), mat="Glass", tr=0.15, refl=0.4, shape="B")
    # hailstones
    for (x, z) in [(-1.3, -0.6), (1.4, 0.4), (1.2, -0.9)]:
        m.ball("Hail", 0.3, (x, 0.15, z), (240, 250, 255), mat="Ice")
    return m


@model
def fog_bank():
    m = Model("fog_bank")
    fog = (225, 230, 240)
    body = m.ell("Body", (1.9, 1.6, 2.4), (0, 1.25, 0), fog, tr=0.25)
    m.smoke(body, (235, 235, 245), 0.12, 0.3, 2.5)
    m.ell("Core", (1.3, 1.1, 1.7), (0, 1.25, 0), (200, 205, 220), tr=0.1)
    m.cyl("Snout", 0.3, 0.6, (0, 1.2, -1.25), (235, 200, 215), axis="z")
    for s in (-1, 1):
        m.ell("Nostril", (0.1, 0.16, 0.06), (s * 0.12, 1.2, -1.41), (120, 90, 110))
        m.ell("Ear", (0.4, 0.5, 0.15), (s * 0.5, 2.05, -0.55), (235, 200, 215), R=rot(x=-20, z=s * -25))
        for sz in (-1, 1):
            m.cyl("Leg", 0.55, 0.4, (s * 0.55, 0.3, sz * 0.7), fog, tr=0.2)
    m.eyes(1.62, -1.02, 0.65, 0.34, lid=fog, sleepy=True)
    m.blk("CoinSlot", (0.8, 0.06, 0.16), (0, 2.06, 0.1), (60, 60, 70))
    m.cyl("Coin", 0.08, 0.5, (0, 2.25, 0.1), (240, 200, 60), mat="Metal", axis="x")
    m.chain("Tail", [(0, 1.4, 1.2), (0.15, 1.6, 1.4), (-0.05, 1.75, 1.45), (0.1, 1.85, 1.35)], 0.1, (235, 200, 215), joints=False)
    # fog wisps
    for (x, y, z, d) in [(-1.2, 0.5, -0.5, 0.8), (1.2, 0.6, 0.3, 0.9), (0.9, 0.3, -1.0, 0.7), (-1.0, 0.35, 0.9, 0.75)]:
        m.ball("Wisp", d, (x, y, z), (240, 240, 248), tr=0.55)
    return m


@model
def lightning_llama():
    m = Model("lightning_llama")
    wool = (250, 245, 225)
    face = (230, 215, 185)
    m.ell("Body", (1.4, 1.3, 2.4), (0, 1.75, 0.25), wool, mat="Fabric")
    m.ell("Neck", (0.7, 1.6, 0.75), (0, 2.6, -0.75), wool, mat="Fabric", R=rot(x=12))
    m.ell("Head", (0.8, 0.75, 1.15), (0, 3.45, -1.05), face)
    m.ell("Muzzle", (0.6, 0.5, 0.5), (0, 3.3, -1.6), (240, 230, 210))
    m.ell("Nose", (0.25, 0.12, 0.08), (0, 3.38, -1.84), (80, 60, 60))
    m.eyes(3.6, -1.42, 0.55, 0.25, lid=face)
    for s in (-1, 1):
        m.ell("Ear", (0.18, 0.55, 0.22), (s * 0.3, 4.0, -0.95), face, R=rot(z=s * -15))
        for sz in (-1, 1):
            m.cyl("Leg", 1.2, 0.32, (s * 0.42, 0.6, 0.25 + sz * 0.75), face)
            m.ell("Hoof", (0.36, 0.2, 0.42), (s * 0.42, 0.1, 0.25 + sz * 0.75 - 0.05), (90, 80, 70))
    # fluffy wool tufts and a storm-cloud hairdo
    for (x, y, z) in [(0, 2.45, 0.6), (0.35, 2.35, 0.0), (-0.35, 2.35, 0.1), (0, 2.4, 1.15)]:
        m.ball("Tuft", 0.6, (x, y, z), wool, mat="Fabric")
    for (x, z, d) in [(0, -1.0, 0.55), (-0.25, -0.85, 0.42), (0.25, -0.85, 0.42)]:
        m.ball("Hair", d, (x, 3.9, z), (110, 115, 135))
    # lightning bolt mark on the side
    for s in (-1, 1):
        m.blk("Bolt", (0.06, 0.6, 0.18), (s * 0.71, 1.95, 0.05), (255, 220, 40), mat="Neon", R=rot(x=25))
        m.blk("Bolt", (0.06, 0.5, 0.18), (s * 0.71, 1.55, 0.3), (255, 220, 40), mat="Neon", R=rot(x=-25))
    tail = m.ball("Tail", 0.45, (0, 2.0, 1.5), wool, mat="Fabric")
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
            m.cyl("Swirl", 0.12, d + 0.06, (cx + off, y + 0.22, 0), (215, 222, 235))
        m.eyes(2.45, -0.88, 0.48, 0.32, lid=tint, x=cx + math.sin(4 * 0.9 + s) * 0.12, angry=(10 if s < 0 else 0))
        m.smile(2.12, -0.92, 0.28, x=cx + math.sin(3 * 0.9 + s) * 0.12, open_=(s > 0))
    # holding hands
    m.rod("Arm", (-0.45, 1.6, -0.2), (0.0, 1.35, -0.45), 0.14, (170, 180, 200))
    m.rod("Arm", (0.45, 1.6, -0.2), (0.0, 1.35, -0.45), 0.14, (170, 180, 200))
    # debris spinning around
    for (x, y, z, c) in [(-1.7, 2.6, 0.3, (90, 170, 70)), (1.75, 2.0, -0.4, (200, 150, 80)), (-1.5, 1.2, -0.6, (90, 170, 70)), (1.6, 3.0, 0.5, (220, 60, 60))]:
        m.blk("Debris", (0.28, 0.06, 0.18), (x, y, z), c, R=rot(30, 50, 20))
    m.cyl("Dust", 0.08, 2.8, (0, 0.04, 0), (200, 190, 170), tr=0.4)
    return m


@model
def stormlord_nimbus():
    m = Model("stormlord_nimbus")
    c = (90, 95, 120)
    cloud(m, 0, 3.0, 0.1, 1.55, c)
    cloud(m, 0, 2.2, 0.3, 1.0, (75, 80, 105))
    for s in (-1, 1):
        m.ell("Eye", (0.5, 0.32, 0.25), (s * 0.45, 3.15, -1.7), (220, 240, 255), mat="Neon", R=rot(z=s * -12))
        m.blk("Brow", (0.65, 0.16, 0.2), (s * 0.45, 3.42, -1.72), (40, 45, 60), R=rot(z=s * 20))
    m.ell("Mouth", (0.7, 0.18, 0.15), (0, 2.65, -1.8), (30, 30, 45))
    # rain beard
    for k in range(7):
        x = -0.75 + k * 0.25
        ln = 0.9 + (0.4 if k % 2 == 0 else 0) - abs(x) * 0.3
        m.blk("Beard", (0.1, ln, 0.1), (x, 2.2 - ln / 2, -1.45), (110, 170, 240), mat="Glass", tr=0.25)
    # lightning crown
    crown = None
    for k in range(5):
        x = -0.8 + k * 0.4
        h = 0.7 if k == 2 else 0.5
        p = m.blk("Crown", (0.16, h, 0.16), (x, 4.35 + h / 2 - 0.2, -0.2), (255, 230, 60), mat="Neon", R=rot(z=(k - 2) * -10))
        if k == 2:
            crown = p
    m.cyl("CrownBand", 0.18, 1.9, (0, 4.25, -0.1), (255, 210, 50), mat="Neon", R=rot(x=-8))
    m.light(crown, (200, 220, 255), 2, 10)
    m.sparkles(crown, (255, 240, 120))
    # cloud arms and a lightning scepter
    m.rod("Arm", (-1.5, 2.7, -0.2), (-2.0, 2.1, -0.8), 0.6, c, shape="E")
    m.rod("Arm", (1.5, 2.7, -0.2), (2.0, 2.3, -0.8), 0.6, c, shape="E")
    m.ball("Hand", 0.6, (2.05, 2.25, -0.85), c)
    m.ball("Hand", 0.6, (-2.05, 2.05, -0.85), c)
    m.blk("Scepter", (0.2, 0.9, 0.2), (2.15, 2.85, -0.9), (255, 230, 60), mat="Neon", R=rot(z=-20))
    m.blk("Scepter", (0.2, 0.8, 0.2), (2.15, 3.55, -0.9), (255, 230, 60), mat="Neon", R=rot(z=20))
    m.blk("Scepter", (0.2, 0.7, 0.2), (2.1, 1.95, -0.9), (255, 230, 60), mat="Neon", R=rot(z=15))
    # rain under the cloud
    for (x, z) in [(-1.0, 0.2), (-0.4, 0.6), (0.5, 0.4), (1.1, 0.0), (0.0, 0.9)]:
        m.ell("Rain", (0.1, 0.5, 0.1), (x, 0.9, z), (120, 170, 240), mat="Glass", tr=0.3)
    m.cyl("Puddle", 0.05, 2.6, (0, 0.03, 0.2), (100, 150, 220), mat="Glass", tr=0.35, refl=0.3)
    return m
