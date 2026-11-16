# Weather family: puffy clouds, ice, fog and lightning.
# Palette: sky blue (main), cloud white and storm slate (secondary), bolt yellow (accent).
# Soft smooth plastic, ice and glass; neon only inside bolts and the Stormlord's eyes.
import math
import random
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal
from stylekit import SModel, PAL, V, norm, on_ell_R, INK, GOLD

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


P = PAL["Weather"]
SKY = P["main"]
CLOUD = P["second"]
BOLT = P["accent"]
SLATE = P["slate"]
RAIN = (110, 180, 250)
BLUSH = (255, 160, 182)


def cloud(m, c, size, color, seed=1, name="Cloud", core="Body", under=None, light=None, front=True, mat="SmoothPlastic"):
    """A puffy cartoon cloud: a core, big puffs (the biggest on top in the middle), lighter
    highlight puffs and a flatter, darker underside. Returns the core's (center, size), the
    surface the face goes on."""
    c = V(*c)
    W, H, D = size
    cs = (W * 0.82, H * 0.8, D * 0.84)
    m.ell(core, cs, c, color, mat)
    lt = light or shade(color, 1.18)
    dk = under or shade(color, 0.82)
    rnd = random.Random(seed)
    puffs = [(0, 0.38, 0.08, 1.0), (-0.47, 0.22, 0.1, 0.84), (0.48, 0.2, 0.05, 0.82),
             (-0.8, -0.12, 0.05, 0.66), (0.81, -0.1, 0.08, 0.64), (0.0, 0.1, 0.56, 0.86)]
    if front:
        puffs += [(-0.62, -0.3, -0.42, 0.56), (0.63, -0.32, -0.4, 0.54)]
    for (x, y, z, d) in puffs:
        j = 1 + rnd.uniform(-0.06, 0.06)
        m.ball(name, d * H * j, c + V(x * W / 2, y * H / 2, z * D / 2), color, mat)
    for (x, y, z, d) in [(-0.16, 0.72, -0.1, 0.5), (0.32, 0.64, 0.12, 0.42), (-0.56, 0.46, 0.05, 0.4)]:
        m.ball(name, d * H, c + V(x * W / 2, y * H / 2, z * D / 2), lt, mat)
    m.ell(name, (W * 0.94, H * 0.38, D * 0.88), c + V(0, -H * 0.3, 0), dk, mat)
    return c, cs


def face_cheeks(m, c, cs, sep, y, d, color=BLUSH):
    for s in (-1, 1):
        p, n = on_ell_R(c, cs, I3, V(s * sep, y, -1))
        m.ell("Cheek", (d, d * 0.58, d * 0.3), p + n * 0.01, color, R=frame_normal(n))


# ------------------------------------------------------------------------------------------------
@model
def drizzle_sprite():
    """Common. A plump little rain cloud under a rainbow, holding up a tiny yellow umbrella, with rain
    falling into a puddle. Mood: cheerful."""
    m = SModel("drizzle_sprite")
    c, cs = cloud(m, (0, 1.72, 0), (2.0, 1.36, 1.4), CLOUD, seed=2, under=(198, 220, 246))
    # face: big happy eyes, an open grin, rosy cheeks
    m.eyes_on(c, cs, I3, 21, 12, 0.38, 0.46, CLOUD, "cheerful", iris=SKY, lash=2)
    p, n = on_ell_R(c, cs, I3, V(0, -0.3, -1))
    m.mouth(p, n, 0.4, "eager", skin=CLOUD)
    face_cheeks(m, c, cs, 0.62, -0.18, 0.26)
    # stubby puff arms: one waves, one holds the umbrella up
    for s in (-1, 1):
        sh = c + V(s * 0.9, -0.12, -0.1)
        hand = c + V(s * 1.18, 0.16 if s > 0 else 0.36, -0.42)
        m.seg("Arm", sh, hand, 0.16, CLOUD, bulge=0.4)
        m.ball("Hand", 0.3, hand, CLOUD)
    # the tiny umbrella: a domed yellow canopy with white tips and ribs, a pole and a hooked handle
    hand = c + V(1.18, 0.16, -0.42)
    top = V(1.0, 3.05, -0.45)
    u = norm(top - hand)
    ax = norm(np.cross(u, [0, 0, 1.0]))
    Fu = np.column_stack([ax, u, np.cross(ax, u)])
    m.seg("UmbrellaPole", hand - u * 0.16, top, 0.045, (90, 92, 110), shape="C")
    m.ell("Umbrella", (1.18, 0.66, 1.18), top - u * 0.14, BOLT, R=Fu)
    m.ell("Umbrella", (1.1, 0.36, 1.1), top - u * 0.3, shade(BOLT, 0.8), R=Fu)
    for k in range(6):
        a = 2 * math.pi * k / 6
        rim = top - u * 0.36 + Fu[:, 0] * math.cos(a) * 0.56 + Fu[:, 2] * math.sin(a) * 0.56
        m.ball("UmbrellaTip", 0.09, rim, WHITE)
        if k % 2 == 0:
            m.seg("UmbrellaRib", top + u * 0.19, rim + u * 0.08, 0.032, WHITE, bulge=0.5)
    m.ball("UmbrellaTip", 0.12, top + u * 0.21, WHITE)
    hook0 = hand - u * 0.16
    m.seg("UmbrellaHook", hook0, hook0 - u * 0.12 + V(0.12, -0.05, 0), 0.05, (90, 92, 110), bulge=0.5)
    # the rainbow arching behind it
    for k, col in enumerate([(244, 92, 92), (255, 168, 64), BOLT, (110, 206, 120), SKY]):
        r = 1.24 - k * 0.11
        cc = V(0, 1.86, 0.5)
        for j in range(5):
            a1, a2 = math.radians(8 + 164 * j / 5), math.radians(8 + 164 * (j + 1) / 5)
            m.seg("Rainbow", cc + V(math.cos(a1) * r, math.sin(a1) * r, 0), cc + V(math.cos(a2) * r, math.sin(a2) * r, 0), 0.062, col, ext=0.03)
    # raindrops into a puddle
    for (x, y, z, d) in [(-0.62, 0.84, -0.1, 0.17), (-0.12, 0.55, 0.18, 0.15), (0.34, 0.86, -0.22, 0.17),
                         (0.72, 0.42, 0.1, 0.14), (-0.42, 0.3, -0.28, 0.14)]:
        m.drop("Drop", (x, y, z), d, RAIN)
    m.cyl("Puddle", 0.05, 1.7, (0, 0.025, 0), RAIN, mat="Glass", tr=0.25, refl=0.4)
    m.cyl("Puddle", 0.06, 0.6, (0.25, 0.03, -0.2), (200, 228, 255), mat="Glass", tr=0.2, refl=0.4)
    return m


# ------------------------------------------------------------------------------------------------
@model
def grumpy_cloud():
    """Common. A storm cloud with one heavy unibrow, a deep frown, folded arms, a small bolt and rain.
    Mood: grumpy."""
    m = SModel("grumpy_cloud")
    dark = (124, 136, 170)
    c, cs = cloud(m, (0, 2.0, 0), (2.85, 1.7, 1.8), dark, seed=7, under=(84, 94, 126), light=(162, 174, 202), front=False)
    ink = (30, 32, 46)
    eyes = m.eyes_on(c, cs, I3, 19, 10, 0.5, 0.48, dark, "grumpy", iris=BOLT, inward=0.05, lash_color=ink)
    # one heavy unibrow across both eyes, dipping in the middle
    mid = (eyes[0] + eyes[1]) / 2 + V(0, 0.27, 0)
    for e in eyes:
        sd = 1 if e[0] > 0 else -1
        end = e + V(sd * 0.3, 0.42, 0)
        pm, nm_ = on_ell_R(c, cs, I3, mid - c)
        pe, ne = on_ell_R(c, cs, I3, end - c)
        m.seg("Brow", pm + nm_ * 0.1, pe + ne * 0.1, 0.13, ink, r2=0.09, ext=0.12)
    p, n = on_ell_R(c, cs, I3, V(0, -0.3, -1))
    m.mouth(p + n * 0.02, n, 0.56, "grumpy", color=ink, d=0.08)
    # arms folded under the frown (each hand stays on its own side)
    for s in (-1, 1):
        sh = c + V(s * 1.18, -0.3, -0.15)
        el = c + V(s * 1.05, -0.78, -0.7)
        hand = c + V(s * 0.32, -0.72, -0.98)
        m.seg("UpperArm", sh, el, 0.21, dark, bulge=0.45)
        m.seg("Forearm", el, hand, 0.19, dark, bulge=0.5)
        m.ball("Hand", 0.34, hand, shade(dark, 1.06))
    # a little bolt zapping down and rain
    b = m.bolt("Bolt", (0.75, 1.26, -0.25), 0.95, w=0.2, color=BOLT)
    m.light(b, (255, 232, 130), 1.2, 6)
    for (x, y, z) in [(-0.7, 0.95, -0.1), (-0.3, 0.55, 0.25), (0.0, 1.0, 0.35), (-0.95, 0.45, 0.2)]:
        m.drop("Drop", (x, y, z), 0.15, RAIN)
    # an angry huff of steam
    for (x, y, d) in [(1.5, 2.85, 0.34), (1.78, 3.08, 0.26), (1.96, 3.3, 0.18)]:
        m.ball("Huff", d, (x, y, -0.25), (220, 226, 236), tr=0.3)
    return m


# ------------------------------------------------------------------------------------------------
@model
def hailstone_hopper():
    """Rare. An ice frog: a squat icy body with big crystal spikes down its back, thick folded legs
    with wide webbed feet, a knitted scarf and hailstones bouncing around. Mood: excited."""
    m = SModel("hailstone_hopper")
    ice = (150, 206, 245)
    deep = (96, 156, 222)
    frost = (232, 246, 255)
    m.ell("Body", (1.95, 1.35, 1.95), (0, 1.02, 0.28), ice, "Ice", refl=0.15)
    m.ell("Belly", (1.5, 1.05, 0.95), (0, 0.9, -0.35), frost, "Ice")
    hc, hs = V(0, 1.58, -0.38), (2.05, 1.05, 1.45)
    m.ell("Head", hs, hc, ice, "Ice", refl=0.15)
    m.ell("Chin", (1.7, 0.5, 1.1), hc + V(0, -0.3, -0.12), frost, "Ice")
    # big eyes on top bumps
    for s in (-1, 1):
        bc = V(s * 0.5, 2.02, -0.62)
        m.ball("EyeBump", 0.8, bc, ice, "Ice")
        d = norm(V(s * 0.38, 0.3, -1))
        m.eye(bc + d * 0.36, d, 0.5, 0.54, ice, "eager", iris=(40, 110, 210))
    # a wide frog grin with the tongue poking out of one corner
    p, n = on_ell_R(hc, hs, I3, V(0, -0.12, -1))
    m.mouth(p + n * 0.02, n, 1.2, "cheerful", color=(36, 70, 128), curve=0.16, d=0.075, kind="smile")
    m.seg("Tongue", p + V(0.36, -0.1, -0.02), p + V(0.5, -0.32, -0.12), 0.09, (244, 130, 160), bulge=0.7)
    for s in (-1, 1):
        q, nq = on_ell_R(hc, hs, I3, V(s * 0.12, 0.18, -1))
        m.ell("Nostril", (0.07, 0.05, 0.05), q + nq * 0.01, deep, R=frame_normal(nq))
        q, nq = on_ell_R(hc, hs, I3, V(s * 0.74, -0.05, -1))
        m.ell("Cheek", (0.32, 0.18, 0.08), q + nq * 0.01, (196, 222, 255), R=frame_normal(nq))
    # frost freckles
    for (x, y, z, d) in [(0.4, 1.95, 0.25, 0.2), (-0.5, 1.88, 0.45, 0.16), (0.72, 1.4, 0.8, 0.18), (-0.78, 1.32, 0.75, 0.15)]:
        m.ell("Freckle", (d, d * 0.6, d), (x, y, z), frost)
    # folded back legs: thigh forward, shin back, wide webbed foot forward
    for s in (-1, 1):
        hip, knee, ankle = V(s * 0.78, 1.0, 0.7), V(s * 1.22, 0.78, 0.0), V(s * 1.05, 0.32, 0.78)
        m.seg("Thigh", hip, knee, 0.38, ice, "Ice", bulge=0.45, ext=0.06)
        m.ball("Knee", 0.5, knee, ice, "Ice")
        m.seg("Shin", knee, ankle, 0.24, ice, "Ice", bulge=0.5)
        m.ball("Ankle", 0.36, ankle, deep, "Ice")
        m.ell("Foot", (0.62, 0.2, 1.05), (s * 1.12, 0.1, 0.28), deep, "Ice")
        for k in (-1, 0, 1):
            m.ball("Toe", 0.24, (s * 1.12 + k * 0.2, 0.11, -0.22 - abs(k) * 0.04), frost, "Ice")
        # front legs
        sh, wr = V(s * 0.62, 1.0, -0.55), V(s * 0.78, 0.26, -0.92)
        m.seg("FrontLeg", sh, wr, 0.2, ice, "Ice", bulge=0.42)
        m.ell("FrontFoot", (0.46, 0.18, 0.5), (s * 0.8, 0.1, -1.0), deep, "Ice")
        for k in (-1, 0, 1):
            m.ball("Toe", 0.18, (s * 0.8 + k * 0.15, 0.09, -1.25), frost, "Ice")
    # big crystal spikes along the head and back: the frog's silhouette
    for (x, y, z, L, w, ax, az) in [(0, 2.0, -0.05, 0.95, 0.32, 0, -12), (-0.38, 1.9, 0.2, 0.72, 0.26, -26, -6),
                                    (0.38, 1.9, 0.22, 0.75, 0.26, 26, -4), (0, 1.88, 0.5, 0.85, 0.3, 0, 10),
                                    (-0.42, 1.62, 0.78, 0.6, 0.22, -30, 22), (0.42, 1.62, 0.8, 0.6, 0.22, 30, 24),
                                    (0, 1.5, 1.02, 0.55, 0.22, 0, 40)]:
        dirv = V(math.sin(math.radians(ax)), 1.0, math.sin(math.radians(az)))
        m.crystal("Crystal", V(x, y, z), dirv, L, w, (214, 242, 255), mat="Glass", tr=0.08, refl=0.35, spin=ax)
    # a knitted scarf (sky blue with a yellow stripe), its end blowing back
    for k in range(5):
        a1, a2 = math.radians(-150 + k * 30), math.radians(-120 + k * 30)
        p1 = V(math.cos(a1) * 0.84, 1.16, math.sin(a1) * 0.64 + 0.1)
        p2 = V(math.cos(a2) * 0.84, 1.16, math.sin(a2) * 0.64 + 0.1)
        m.seg("Scarf", p1, p2, 0.15, SKY if k != 2 else BOLT, "Fabric", ext=0.05)
    m.seg("Scarf", V(0.62, 1.2, -0.25), V(1.05, 1.0, 0.3), 0.13, SKY, "Fabric", r2=0.06)
    m.seg("Scarf", V(1.05, 1.0, 0.3), V(1.15, 0.92, 0.62), 0.12, BOLT, "Fabric", r2=0.06)
    # hailstones bouncing around
    for (x, z, d) in [(-1.35, -0.75, 0.32), (1.45, -0.85, 0.28), (-1.45, 0.95, 0.26), (0.0, -1.35, 0.24)]:
        m.ball("Hail", d, (x, d / 2, z), (236, 248, 255), "Ice")
        m.ball("Hail", d * 0.35, (x - d * 0.18, d * 0.78, z - d * 0.18), WHITE)
    return m


# ------------------------------------------------------------------------------------------------
@model
def fog_bank():
    """Rare. A piggy bank made of fog: a round cloud pig with swirls of mist, a snout, floppy ears, a
    bowler hat, a coin slot with a gold coin, stubby legs, a curly tail and ground fog. Mood: smug."""
    m = SModel("fog_bank")
    fog = (214, 222, 240)
    deep = (178, 188, 214)
    snout = (234, 206, 224)
    bc, bs = V(0, 1.32, 0.12), (2.3, 1.95, 2.6)
    m.ell("Body", bs, bc, fog)
    # a cloudy fringe of fog puffs round the back and sides, a darker belly
    for (x, y, z, d) in [(-0.66, 1.92, 0.62, 0.86), (0.64, 1.95, 0.66, 0.82), (0.0, 2.06, 0.98, 0.86),
                         (-0.95, 1.45, 0.9, 0.74), (0.96, 1.42, 0.92, 0.74), (-1.05, 1.15, 0.1, 0.62), (1.06, 1.12, 0.14, 0.62)]:
        m.ball("Fog", d, (x, y, z), shade(fog, 1.06))
    m.ell("Belly", (1.9, 0.7, 2.2), (0, 0.72, 0.12), deep)
    # swirls of mist on the sides
    for s in (-1, 1):
        for k, (y, z, L) in enumerate([(1.55, 0.05, 1.0), (1.18, 0.35, 0.8)]):
            p, n = on_ell_R(bc, bs, I3, V(s, (y - bc[1]) / 1.0, (z - bc[2]) / 1.3))
            m.ell("Swirl", (L, 0.13, 0.06), p + n * 0.01, (244, 248, 255), R=frame_normal(n) @ Rz(-14 * s))
    # snout and face
    sc = V(0, 1.22, -1.12)
    m.cyl("Snout", 0.42, 0.78, sc, snout, axis="z")
    m.ell("Snout", (0.78, 0.78, 0.2), sc + V(0, 0, -0.2), shade(snout, 1.05))
    for s in (-1, 1):
        m.ell("Nostril", (0.13, 0.2, 0.08), sc + V(s * 0.16, 0, -0.29), (120, 84, 110))
    m.eyes_on(bc, bs, I3, 25, 17, 0.38, 0.44, fog, "smug", iris=SKY, lash=2, brow=(120, 128, 160), brow_k=0.8)
    p, n = on_ell_R(bc, bs, I3, V(0.1, -0.2, -1))
    m.mouth(p + V(0, -0.06, -0.02), n, 0.4, "smug", color=(96, 80, 110), side_bias=1)
    for s in (-1, 1):
        p, n = on_ell_R(bc, bs, I3, V(s * 0.66, -0.1, -1))
        m.ell("Cheek", (0.3, 0.17, 0.08), p + n * 0.01, (240, 182, 206), R=frame_normal(n))
        # pointy pig ears with the tips folding forward
        m.ear(V(s * 0.6, 2.02, -0.48), V(s * 0.92, 2.5, -0.82), 0.5, fog, inner=snout, depth=0.16,
              curve=(s * 0.02, 0.04, -0.08), facing=(s * 0.35, 0.35, -1))
    # a little bowler hat with a sky-blue band
    hc = V(0, 2.32, -0.18)
    m.ell("HatBrim", (1.0, 0.1, 0.9), hc, (52, 54, 70), R=rot(x=-8))
    m.ell("Hat", (0.7, 0.62, 0.64), hc + V(0, 0.2, 0.02), (60, 62, 80), R=rot(x=-8))
    m.cyl("HatBand", 0.12, 0.72, hc + V(0, 0.1, 0.01), SKY, axis="y", R=rot(x=-8))
    # coin slot with a gold coin dropping in
    m.blk("Slot", (0.6, 0.07, 0.13), (0, 2.27, 0.58), (52, 54, 70), R=rot(x=14))
    m.cyl("Coin", 0.09, 0.64, (0, 2.5, 0.56), GOLD, axis="x", mat="Metal", refl=0.15)
    m.cyl("Coin", 0.11, 0.42, (0, 2.5, 0.56), shade(GOLD, 1.12), axis="x", mat="Metal", refl=0.15)
    # four stubby piggy-bank legs with hooves
    for s in (-1, 1):
        for z in (-0.55, 0.82):
            m.seg("Leg", V(s * 0.68, 0.92, z), V(s * 0.7, 0.26, z - 0.03), 0.27, fog, bulge=0.4)
            m.hoof((s * 0.7, z - 0.03), 0.22, (94, 102, 132), notch=True)
    # curly tail
    pts = [V(0, 1.55, 1.4), V(0.1, 1.72, 1.58), V(0.28, 1.68, 1.66), V(0.32, 1.5, 1.6), V(0.18, 1.42, 1.62)]
    for k in range(4):
        m.seg("Tail", pts[k], pts[k + 1], 0.08 - k * 0.008, snout, ext=0.03)
    # ground fog curling round the feet, coins on the ground
    for (x, z, w, d) in [(-1.1, -0.4, 1.2, 0.8), (1.15, 0.25, 1.1, 0.9), (-0.8, 1.1, 1.0, 0.7), (0.9, -1.0, 0.9, 0.6)]:
        m.ell("Wisp", (w, 0.34, d), (x, 0.17, z), (236, 242, 252), tr=0.5)
    for (x, z) in [(-0.45, -1.35), (0.55, -1.3)]:
        m.cyl("Coin", 0.06, 0.36, (x, 0.03, z), GOLD, axis="y", mat="Metal", refl=0.15)
    return m


# ------------------------------------------------------------------------------------------------
@model
def lightning_llama():
    """Epic. A storm-wool llama: a woolly neck and deep chest, a body of big wool clumps, thick legs
    with woolly thighs, slate shins and big hooves, tall ears, a storm-cloud hairdo with a spark, a bolt
    on its pom tail and a sky-blue saddle blanket with a yellow zigzag. Mood: proud, half-lidded."""
    m = SModel("lightning_llama")
    wool = (240, 244, 252)
    wool_d = (212, 220, 240)
    skin = (118, 130, 176)
    skin_l = (172, 182, 216)
    hoofc = (54, 58, 84)
    blanket = SKY
    bolt = BOLT

    # body: chest, barrel and rump flow into each other, big wool clumps
    m.ell("Body", (1.52, 1.36, 1.75), (0, 1.98, 0.22), wool, "Fabric")
    m.ell("Chest", (1.42, 1.4, 1.2), (0, 2.02, -0.48), wool, "Fabric")
    m.ell("Rump", (1.44, 1.36, 1.18), (0, 2.02, 0.88), wool, "Fabric")
    m.ell("Belly", (1.24, 0.72, 1.9), (0, 1.5, 0.2), wool_d, "Fabric")
    m.puffs("Wool", (0, 2.02, -0.48), (1.42, 1.4, 1.2), 5, 0.66, wool, seed=3, ymin=-0.3,
            keep=lambda v: v[2] < -0.3, mat="Fabric", shade_k=0.05)
    m.puffs("Wool", (0, 2.02, 0.88), (1.44, 1.36, 1.18), 5, 0.64, wool, seed=5, ymin=-0.25,
            keep=lambda v: v[2] > 0.3, mat="Fabric", shade_k=0.05)

    # saddle blanket: five cloth slats bent over the back, rolled hems, a zigzag stripe, tassels
    arc = []
    for k in range(5):
        a = math.radians(-76 + k * 38)
        arc.append((math.sin(a) * 0.8, 2.0 + math.cos(a) * 0.72))
    hem = shade(blanket, 0.8)
    zf, zb = -0.36, 0.8
    for k in range(5):
        a = math.radians(-76 + k * 38)
        x, y = arc[k]
        m.blk("Blanket", (0.56, 0.08, zb - zf), (x, y, (zf + zb) / 2), blanket, "Fabric", R=rot(z=-math.degrees(a)))
    for z in (zf, zb):
        for k in range(5):
            a = math.radians(-76 + k * 38)
            x, y = arc[k]
            d = V(math.cos(a), -math.sin(a), 0) * 0.29
            p = V(x, y, z)
            m.seg("Hem", p - d, p + d, 0.06, hem, "Fabric", shape="C")
    for s in (-1, 1):
        x, y = arc[0 if s < 0 else 4]
        a = math.radians(-76 if s < 0 else 76)
        low = V(x, y, 0) - V(math.cos(a), -math.sin(a), 0) * 0.28
        m.seg("Hem", V(low[0], low[1], zf), V(low[0], low[1], zb), 0.065, hem, "Fabric", shape="C")
        nrm = V(math.sin(a), math.cos(a), 0)
        pts = [V(low[0], low[1], 0) + V(math.cos(a), -math.sin(a), 0) * (0.16 if k % 2 else 0.06) + nrm * 0.045
               + V(0, 0, zf + 0.12 + k * 0.165) for k in range(8)]
        m.chain("Zigzag", pts, 0.055, bolt, joints=False)
        for z in (zf, zb):
            m.ball("Tassel", 0.13, (low[0], low[1] - 0.04, z), bolt, "Fabric")
            m.seg("Tassel", (low[0], low[1] - 0.06, z), (low[0] * 1.02, low[1] - 0.3, z), 0.06, bolt, "Fabric", bulge=0.7)

    # neck: thick and woolly, leaning forward, with a fluffy bib and collar
    m.seg("Neck", V(0, 2.2, -0.62), V(0, 3.62, -1.26), 0.44, wool, "Fabric", bulge=0.36, r2=0.42)
    for (y, z, d) in [(2.42, -1.18, 0.66), (2.86, -1.3, 0.54), (3.22, -1.4, 0.44)]:
        m.ball("Wool", d, (0, y, z), wool, "Fabric")
    for s in (-1, 1):
        m.ball("Wool", 0.56, (s * 0.34, 2.48, -1.0), wool, "Fabric")

    # head
    hc = V(0, 3.72, -1.4)
    hs = (0.94, 0.84, 0.92)
    m.ell("Head", hs, hc, skin)
    mc = V(0, 3.4, -1.88)
    ms = (0.6, 0.5, 0.62)
    m.ell("Muzzle", ms, mc, skin_l)
    m.ell("Nose", (0.34, 0.13, 0.17), mc + V(0, 0.19, -0.27), shade(skin, 0.62))
    for s in (-1, 1):
        m.ell("Nostril", (0.08, 0.05, 0.06), mc + V(s * 0.11, 0.16, -0.31), INK)
    p, n = on_ell_R(mc, ms, I3, V(0, -0.5, -1))
    m.mouth(p + V(0, 0.03, 0), n, 0.26, "smug", color=(48, 40, 70), side_bias=1, d=0.032)
    m.seg("Mouth", mc + V(0, 0.1, -0.31), mc + V(0, -0.02, -0.31), 0.02, (48, 40, 70))
    m.eyes_on(hc, hs, I3, 26, 16, 0.32, 0.38, skin, "proud", iris=(96, 170, 245), lash=3,
              brow=(52, 58, 86), brow_k=0.8)
    for s in (-1, 1):
        m.ear(hc + V(s * 0.26, 0.3, 0.1), hc + V(s * 0.5, 0.98, 0.2), 0.28, skin, inner=(210, 194, 240),
              curve=(s * 0.1, 0, -0.04), facing=(s * 0.3, 0, -1))
    # storm-cloud hairdo with a little lightning spark
    hair = (176, 186, 214)
    for (x, y, z, d) in [(0, 0.5, 0.0, 0.46), (-0.2, 0.44, 0.1, 0.38), (0.2, 0.46, 0.12, 0.38),
                         (0, 0.56, 0.22, 0.36), (0.0, 0.42, -0.22, 0.32)]:
        m.ball("Hair", d, hc + V(x, y, z), hair, "Fabric")
    m.ball("Hair", 0.26, hc + V(0.04, 0.68, 0.06), shade(hair, 1.2), "Fabric")
    sp = m.bolt("Spark", hc + V(0.1, 1.02, -0.06), 0.42, w=0.1, color=bolt, R=rot(z=-12))
    m.light(sp, (255, 236, 140), 1.0, 6)

    # legs: woolly thighs, slate shins, big hooves
    for s in (-1, 1):
        x = s * 0.42
        for (zh, zk, za) in ((-0.55, -0.6, -0.55), (0.98, 1.08, 0.96)):
            hip, knee, ankle = V(x, 1.72, zh), V(x * 1.02, 0.98, zk), V(x * 1.02, 0.4, za)
            m.seg("Thigh", hip, knee, 0.34, wool, "Fabric", bulge=0.36, ext=0.08)
            m.ball("Knee", 0.4, knee + V(0, 0.02, -0.03), wool, "Fabric")
            m.seg("Shin", knee, ankle, 0.18, skin, bulge=0.45, ext=0.05)
            m.hoof((ankle[0], ankle[2] - 0.03), 0.24, hoofc, sock=None)

    # tail: a fluffy pom with a lightning bolt sticking out
    m.ball("Tail", 0.6, (0, 2.38, 1.5), wool, "Fabric")
    m.ball("TailTip", 0.44, (0, 2.64, 1.72), wool, "Fabric")
    m.bolt("Tail", (0, 3.25, 1.86), 0.5, w=0.12, color=bolt, mat="SmoothPlastic", R=rot(y=90))
    return m


# ------------------------------------------------------------------------------------------------
@model
def tornado_twins():
    """Mythic. Two twisting funnels on one dust base, each with its own giggling face, holding hands,
    with streaks of wind, a road sign, a plank, a tin can and leaves caught in the spin and a spark
    crackling between them. Mood: chaotic giggle."""
    m = SModel("tornado_twins")
    low, high = (110, 126, 166), (204, 216, 238)
    swirl = (240, 245, 253)

    def mix(t):
        return tuple(int(low[i] + (high[i] - low[i]) * t) for i in range(3))

    faces = {}
    for s, phase in ((-1, 0.0), (1, 2.4)):
        cx = s * 0.98

        def at(k):
            return cx + math.sin(k * 0.8 + phase) * 0.13, math.cos(k * 0.8 + phase) * 0.07

        n = 9
        for k in range(n):
            t = k / (n - 1)
            y = 0.36 + k * 0.34
            r = 0.2 + t ** 1.1 * 0.92
            ox, oz = at(k)
            m.ell("Funnel", (2 * r, 0.62, 2 * r), (ox, y, oz), mix(t))
        # a puffy, cloudy top
        ox, oz = at(n)
        top = V(ox, 3.2, oz)
        m.ell("Funnel", (2.25, 0.62, 2.0), top, high)
        for k in range(5):
            a = 2 * math.pi * k / 5 + phase
            m.ball("Funnel", 0.6, top + V(math.cos(a) * 0.82, 0.08, math.sin(a) * 0.72), shade(high, 1.04))
        m.ell("Swirl", (1.0, 0.12, 0.9), top + V(0, 0.3, 0), swirl, tr=0.1)
        # a smooth face piece on the upper funnel
        ox, oz = at(6)
        fc, fs = V(ox, 2.36, oz - 0.18), (1.72, 1.36, 1.86)
        m.ell("Funnel", fs, fc, mix(0.72))
        faces[s] = (fc, fs)
        # streaks of wind wrapping round the funnel below the face
        for k, (y, r) in enumerate([(0.95, 0.5), (1.45, 0.66)]):
            ox, oz = at(2 + k * 2)
            for j in range(3):
                a1, a2 = math.radians(200 + j * 40 + phase * 30), math.radians(240 + j * 40 + phase * 30)
                p1 = V(ox + math.cos(a1) * r, y + j * 0.07, oz + math.sin(a1) * r)
                p2 = V(ox + math.cos(a2) * r, y + (j + 1) * 0.07, oz + math.sin(a2) * r)
                m.seg("Swirl", p1, p2, 0.05, swirl, tr=0.1, ext=0.03)
    # faces: one goofy (crossed eyes, tongue out), one wide-eyed and giggling
    for s, mood, iris in ((-1, "goofy", (90, 130, 220)), (1, "eager", (222, 104, 120))):
        fc, fs = faces[s]
        m.eyes_on(fc, fs, I3, 23, 14, 0.42, 0.5, mix(0.72), mood, iris=iris, brow=(66, 76, 108), brow_k=0.8)
        p, n = on_ell_R(fc, fs, I3, V(0, -0.34, -1))
        m.mouth(p, n, 0.46, mood, skin=mix(0.72))
        face_cheeks(m, fc, fs, 0.62, -0.2, 0.22)
    # wind-wisp arms: the inner ones hold hands in the middle, the outer ones wave
    wisp = (184, 198, 226)
    for s in (-1, 1):
        sh, hand = V(s * 0.5, 1.82, -0.25), V(s * 0.16, 1.5, -0.66)
        m.seg("Arm", sh, hand, 0.13, wisp, bulge=0.45)
        m.ball("Hand", 0.24, hand, wisp)
        sh2, hand2 = V(s * 1.72, 2.2, 0.0), V(s * 2.02, 2.86, -0.32)
        m.seg("Arm", sh2, hand2, 0.13, wisp, bulge=0.45)
        m.ball("Hand", 0.24, hand2, wisp)
    # the dust base they spin on
    m.ell("Base", (3.3, 0.24, 1.9), (0, 0.12, 0), (176, 160, 138))
    m.ell("Base", (2.6, 0.12, 1.5), (0, 0.22, 0), (196, 182, 160))
    for (x, z, d) in [(-1.5, -0.4, 0.5), (1.55, 0.3, 0.46), (-0.2, 0.7, 0.42), (0.45, -0.75, 0.4), (-1.0, 0.75, 0.36)]:
        m.ball("Dust", d, (x, d * 0.4, z), (200, 186, 164), tr=0.25)
    # debris caught in the wind: a road sign, a plank, a tin can, leaves
    sg = V(1.72, 3.62, 0.35)
    m.seg("SignPole", sg + V(-0.35, -0.55, 0), sg, 0.05, (140, 144, 152), shape="C")
    for k, (sz, col) in enumerate([(0.52, BOLT), (0.38, (40, 40, 46)), (0.3, BOLT)]):
        m.blk("Sign", (sz, sz, 0.05 + k * 0.01), sg + V(0.02, 0.05, -0.006 * k), col, R=rot(y=20, z=45))
    m.blk("Plank", (0.8, 0.12, 0.22), (-1.98, 3.2, -0.25), (156, 110, 66), "WoodPlanks", R=rot(10, 30, 35))
    m.blk("Plank", (0.06, 0.13, 0.06), (-1.75, 3.27, -0.2), (90, 92, 100), "Metal", R=rot(10, 30, 35))
    m.cyl("Can", 0.42, 0.28, (2.12, 1.25, -0.45), (200, 70, 60), "y", "Metal", R=rot(x=30, z=50))
    m.cyl("Can", 0.06, 0.3, (2.12, 1.25, -0.45) + V(0.16, 0.12, 0.08), (200, 205, 212), "y", "Metal", R=rot(x=30, z=50))
    for (x, y, z, a) in [(-1.75, 1.3, -0.65, 30), (1.85, 1.75, -0.5, -40), (-2.05, 2.45, 0.45, 60), (2.05, 1.05, 0.55, 15),
                         (0.0, 3.25, -0.65, -20), (-0.6, 3.6, 0.3, 45)]:
        m.ell("Leaf", (0.32, 0.05, 0.18), (x, y, z), (104, 178, 82), R=rot(a, a * 1.3, a * 0.6))
        m.seg("Leaf", V(x, y, z) + V(-0.1, 0, 0), V(x, y, z) + V(0.12, 0.01, 0), 0.015, (70, 130, 60))
    # a little spark crackling between the twins
    b = m.bolt("Spark", (0.08, 3.1, -0.1), 0.62, w=0.14, color=BOLT)
    m.light(b, (255, 236, 140), 1.0, 6)
    return m


# ------------------------------------------------------------------------------------------------
@model
def stormlord_nimbus():
    """Legendary. A huge thundercloud lord: glowing eyes under heavy brows, a cloud beard, a gold crown
    of lightning bolts on a velvet cap, a royal mantle with a gold trim, big cloud arms with a bolt
    sceptre and a crackling orb, a gold medallion, bolts striking down and a curtain of rain.
    Mood: imperious."""
    m = SModel("stormlord_nimbus")
    body = (86, 96, 132)
    c, cs = cloud(m, (0, 3.08, 0.1), (3.9, 2.3, 2.6), body, seed=11, under=(56, 62, 90), light=(128, 140, 176))
    imperious = dict(open=0.8, lid=16, brow=22, lift=0.05, mouth="flat", curve=0.0)
    # face: glowing eyes under heavy brows, a puff nose, a cloud mustache and beard
    m.eyes_on(c, cs, I3, 18, 14, 0.52, 0.42, body, imperious, glow=True, white=(255, 240, 150), pupil=(70, 50, 30),
              pupil_k=0.38, brow=(34, 38, 56), brow_k=1.4, inward=0.04)
    p, n = on_ell_R(c, cs, I3, V(0, -0.02, -1))
    m.ball("Nose", 0.44, p + n * 0.06, shade(body, 1.12))
    beard = (206, 214, 232)
    for s in (-1, 1):
        p0, n0 = on_ell_R(c, cs, I3, V(s * 0.08, -0.16, -1))
        m.seg("Mustache", p0 + n0 * 0.14, p0 + n0 * 0.1 + V(s * 0.64, -0.1, 0.12), 0.17, beard, bulge=0.35)
        m.ball("Mustache", 0.24, p0 + n0 * 0.08 + V(s * 0.68, 0.0, 0.14), beard)
    p, n = on_ell_R(c, cs, I3, V(0, -0.3, -1))
    m.mouth(p + n * 0.02, n, 0.34, imperious, color=(36, 36, 52), d=0.06)
    for (x, y, z, d) in [(0, -0.62, -0.84, 0.64), (-0.44, -0.5, -0.78, 0.52), (0.44, -0.5, -0.78, 0.52),
                         (-0.22, -0.96, -0.74, 0.46), (0.22, -0.96, -0.74, 0.46), (0, -1.28, -0.68, 0.38)]:
        m.ball("Beard", d, c + V(x, y, z), beard)
    # crown: a velvet cap inside a gold band with lightning-bolt points and sky-blue gems
    crc = c + V(0, 1.2, 0.0)
    m.ell("Crown", (1.5, 0.75, 1.5), crc + V(0, 0.16, 0), (120, 40, 70), "Fabric")
    m.cyl("CrownBand", 0.36, 1.64, crc, GOLD, "y", "Metal", refl=0.2)
    m.cyl("CrownBand", 0.09, 1.72, crc + V(0, -0.16, 0), shade(GOLD, 0.8), "y", "Metal")
    m.cyl("CrownBand", 0.07, 1.7, crc + V(0, 0.16, 0), shade(GOLD, 1.1), "y", "Metal")
    for k in range(5):
        a = math.radians(-90 + (k - 2) * 38)
        q = crc + V(math.cos(a) * 0.8, 0.12, math.sin(a) * 0.8)
        m.bolt("CrownPoint", q + V(0, 0.66, 0), 0.66, w=0.16, color=BOLT, R=Ry(-math.degrees(a) - 90))
    for k in (-1, 0, 1):
        a = math.radians(-90 + k * 38)
        m.gem("CrownGem", crc + V(math.cos(a) * 0.83, 0.0, math.sin(a) * 0.83), 0.2 if k else 0.26, SKY)
    m.ball("Crown", 0.24, crc + V(0, 0.62, 0), GOLD, "Metal")
    # a royal mantle round the back: deep blue with a gold trim and an ermine collar
    mantle = (44, 56, 120)
    m.ell("Mantle", (4.1, 2.2, 0.5), c + V(0, -0.35, 1.25), mantle, "Fabric", R=rot(x=-10))
    m.ell("Mantle", (4.2, 0.24, 0.56), c + V(0, -1.42, 1.43), GOLD, "Fabric", R=rot(x=-10))
    for k in range(7):
        x = -1.65 + k * 0.55
        m.ball("Ermine", 0.5, c + V(x, 0.68 - abs(x) * 0.18, 0.95 + abs(x) * 0.06), (246, 246, 250), "Fabric")
        if k % 2:
            m.ell("Ermine", (0.07, 0.14, 0.05), c + V(x, 0.68 - abs(x) * 0.18, 0.69 + abs(x) * 0.06), (30, 30, 36))
    # big cloud arms: a bolt sceptre in the right hand, a crackling orb above the left
    for s in (-1, 1):
        sh, el, wr = c + V(s * 1.62, -0.2, 0.0), c + V(s * 1.96, -0.8, -0.4), c + V(s * 1.82, -0.9, -1.0)
        m.ball("Shoulder", 0.92, sh, body)
        m.seg("UpperArm", sh, el, 0.36, body, bulge=0.45)
        m.ball("Elbow", 0.68, el, body)
        m.seg("Forearm", el, wr, 0.34, body, bulge=0.6)
        m.ball("Cuff", 0.58, wr + V(0, 0.02, 0.12), GOLD, "Metal")
        m.glove(wr + V(0, 0.02, -0.1), 0.3, shade(body, 1.08), s, fist=(s > 0), fingers=3)
    sx = c + V(1.82, -0.9, -1.12)
    m.seg("Scepter", sx + V(0, -1.3, 0), sx + V(0, 1.2, 0), 0.08, GOLD, "Metal", shape="C")
    for y in (1.15, 0.45, -1.25):
        m.cyl("ScepterBand", 0.12, 0.24, sx + V(0, y, 0), shade(GOLD, 0.85), "y", "Metal")
    st = m.bolt("ScepterTop", sx + V(0.05, 2.08, 0), 0.98, w=0.25, color=BOLT)
    m.sparkles(st, (255, 240, 120))
    orb = c + V(-1.82, -0.5, -1.15)
    o = m.ball("Orb", 0.44, orb, (210, 236, 255), "Neon", tr=0.2)
    m.bolt("Orb", orb + V(0.05, 0.17, -0.02), 0.34, w=0.07, color=BOLT)
    m.light(o, (200, 230, 255), 1.4, 8)
    # a gold medallion on a chain
    for s_ in (-1, 1):
        a0, _ = on_ell_R(c, cs, I3, V(s_ * 0.78, -0.4, -1))
        b0, _ = on_ell_R(c, cs, I3, V(s_ * 0.12, -0.74, -1))
        m.seg("MedalChain", a0 + V(0, 0, -0.05), b0 + V(0, 0, -0.08), 0.045, GOLD, "Metal", shape="C")
    p, n = on_ell_R(c, cs, I3, V(0, -0.78, -1))
    med = p + n * 0.1 + V(0, -0.06, 0)
    m.cyl("Medal", 0.1, 0.62, med, GOLD, "z", "Metal", refl=0.2)
    m.cyl("Medal", 0.12, 0.42, med + V(0, 0, -0.01), SKY, "z")
    m.bolt("Medal", med + V(0.02, 0.15, -0.08), 0.3, w=0.08, t=0.04, color=BOLT, mat="SmoothPlastic")
    # bolts striking down and a curtain of rain
    m.bolt("Strike", c + V(-0.95, -1.15, -0.2), 1.1, w=0.18, color=BOLT)
    m.bolt("Strike", c + V(0.9, -1.2, 0.35), 0.9, w=0.15, color=BOLT, R=Ry(180))
    rnd = random.Random(4)
    for k in range(14):
        x = -1.65 + k * 0.255 + rnd.uniform(-0.05, 0.05)
        z = -0.45 + rnd.uniform(-0.35, 0.7)
        y0 = 1.8 - rnd.uniform(0, 0.25)
        m.seg("Rain", V(x, y0, z), V(x - 0.08, y0 - 0.95 - rnd.uniform(0, 0.45), z), 0.04, RAIN, "Glass", tr=0.25, refl=0.3)
    m.cyl("Puddle", 0.05, 3.2, (0, 0.025, -0.05), RAIN, mat="Glass", tr=0.3, refl=0.4)
    for (x, z, r) in [(-0.9, -0.3, 0.32), (0.7, 0.2, 0.26)]:
        m.cyl("Puddle", 0.06, r * 2, (x, 0.03, z), (200, 228, 255), mat="Glass", tr=0.2)
    m.light(1, (190, 210, 255), 0.8, 10)
    return m

