# Robo family: shiny appliances and robots with a lot of heart.
# Palette: brushed steel (main), enamel teal (secondary), signal orange LEDs (accent), with dark
# graphite, chrome and glass. Materials: metal, foil, glass screens and a little neon.
import math
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal, frame_from_x, on_ell
from stylekit import SModel, PAL, V, norm, on_ell_R, INK, GOLD, SILVER

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


P = PAL["Robo"]
STEEL = P["main"]
TEAL = P["second"]
ORANGE = P["accent"]
DARK = P["dark"]
LIGHT = P["light"]
GLASS = P["glass"]
CHROME = (224, 230, 238)
STEEL_D = (138, 144, 156)
LIGHT_D = (208, 214, 222)
TEAL_D = (32, 116, 124)
TEAL_L = (124, 212, 216)
ORANGE_D = (206, 90, 22)
ORANGE_L = (255, 184, 104)
GRAPHITE = (44, 48, 56)
RUBBER = (34, 36, 42)
SCREEN = (22, 32, 48)
LED = (96, 240, 250)
ICE = (168, 228, 255)
ICE_D = (70, 170, 230)
MOUTH_D = (52, 26, 36)
CABLE = (238, 238, 242)
TOAST = (232, 186, 112)
CRUST = (168, 104, 50)
BUTTER = (255, 226, 120)
JAM = (196, 28, 62)

# moods only this family uses
CURIOUS = dict(open=1.0, lid=0, brow=-16, lift=0.36, mouth="open", curve=0.2, look=(0.12, 0.16))
FIERCE_SMALL = dict(open=0.84, lid=16, brow=24, lift=0.02, mouth="teeth", curve=0.05, look=(0, -0.04))
VALIANT = dict(open=0.86, lid=8, brow=16, lift=0.08, mouth="smile", curve=0.24, look=(0, 0.02))
EAGER_BOT = dict(open=1.0, lid=0, brow=-16, lift=0.3, mouth="open", curve=0.28, look=(0, 0.04))
WISE = dict(open=0.56, lid=-8, brow=-10, lift=0.3, mouth="smile", curve=0.2, look=(0.0, -0.06))
STOIC = dict(open=0.6, lid=4, brow=8, lift=0.04, mouth="flat", curve=0.0, look=(0, -0.02))
ALMIGHTY = dict(open=0.62, lid=-4, brow=-8, lift=0.32, mouth="smirk", curve=0.2, look=(0, 0))


def lerp(a, b, t):
    return a + (b - a) * t


def cpt(r, a, y, cx=0.0, cz=0.0, out=0.0):
    """Point on an upright cylinder of radius r around (cx, cz); a = 270 is the front (-z)."""
    t = math.radians(a)
    return V(cx + math.cos(t) * (r + out), y, cz + math.sin(t) * (r + out))


def cn(a):
    t = math.radians(a)
    return V(math.cos(t), 0, math.sin(t))


def tang(a):
    t = math.radians(a)
    return V(-math.sin(t), 0, math.cos(t))


def tframe(a):
    """Frame at angle a round an upright ring: x along the ring, y up, z inwards."""
    t = tang(a)
    return np.column_stack([t, V(0, 1, 0), np.cross(t, V(0, 1, 0))])


def up_frame(n):
    """Frame whose y axis points along n (for things standing on a slanted surface)."""
    n = norm(n)
    x = norm(np.cross(n, V(0, 0, 1.0)))
    return np.column_stack([x, n, np.cross(x, n)])


def ell_front_at(c, size, X, Y, R=I3):
    """Surface point (and normal) on the front (-z) of an ellipsoid at local offsets X, Y."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    u, v = X / hx, Y / hy
    w = -math.sqrt(max(1 - u * u - v * v, 0.02))
    return on_ell_R(c, size, R, np.array(R, float) @ V(X, Y, hz * w))


def top_pt(c, size, x, z):
    """Point on the top of an upright ellipsoid above (x, z), and the normal there."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    q = max(1 - ((x - c[0]) / hx) ** 2 - ((z - c[2]) / hz) ** 2, 0.0)
    y = c[1] + hy * math.sqrt(q)
    n = norm(V((x - c[0]) / hx ** 2, (y - c[1]) / hy ** 2, (z - c[2]) / hz ** 2))
    return V(x, y, z), n


def seg_ell(a, b, r, bulge=0.5, ext=0.0, r2=None):
    """The ellipsoid that SModel.seg makes from a to b: (center, size, rotation)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    v = b - a
    L = float(np.linalg.norm(v))
    c = a + v * bulge
    half = max(bulge, 1 - bulge) * L + ext
    return c, (2 * half, 2 * r, 2 * (r if r2 is None else r2)), frame_from_x(v)


def eband(m, name, c, ax, az, thick, color, n=12, h=None, mat="SmoothPlastic"):
    """A flat band round an upright ellipse (half widths ax, az) centred on c."""
    pts = [c + V(math.cos(2 * math.pi * k / n) * ax, 0, math.sin(2 * math.pi * k / n) * az) for k in range(n)]
    for k in range(n):
        p, q = pts[k], pts[(k + 1) % n]
        v = q - p
        L = float(np.linalg.norm(v))
        xa = v / L
        ya = V(0, 1, 0)
        m.blk(name, (L * 1.1, h or thick, thick), (p + q) / 2, color, mat, R=np.column_stack([xa, ya, np.cross(xa, ya)]))


def disc(m, name, c, n, d, t, color, mat="SmoothPlastic", tr=0.0, refl=0.0):
    """A flat round disc (a short cylinder) at c, facing along n."""
    return m.add("C", name, (t, d, d), c, color, mat, frame_from_x(norm(n)), tr, refl)


def lens_eye(m, at, n, w, skin, mood, iris, side, h=None, brow=None, rim=CHROME, rim_k=1.3, **kw):
    """A camera-lens eye: a cartoon eye (white, iris, pupil, glints, a metal lid for the mood) in a
    round chrome bezel. The bezel is named EyeRim, so it always follows the eye."""
    h = h or w
    n = norm(n)
    m.eye(at, n, w, h, skin, mood, side=side, iris=iris, brow=brow, **kw)
    dz = min(w, h) * 0.55
    disc(m, "EyeRim", np.asarray(at, float) - n * dz * 0.08, n, max(w, h) * rim_k, dz * 0.9, rim, "Metal")


def hexnut(m, name, c, axis, r, t, color, mat="Metal"):
    """A hex nut: three crossed blocks make a six-sided prism along `axis`."""
    F = frame_from_x(axis)
    for k in range(3):
        m.blk(name, (t, r * 1.732, r), c, color, mat, R=F @ Rx(k * 60))


def piston(m, a, b, r, housing=STEEL_D, rod=CHROME, name="Piston"):
    """A hydraulic piston from a to b: a thick housing and a thinner chrome rod."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    mid = a + (b - a) * 0.55
    m.seg(name, a, mid, r, housing, "Metal", shape="C", ext=r * 0.3)
    m.seg(name, mid, b, r * 0.55, rod, "Metal", shape="C", ext=r * 0.2)


def ribbed(m, name, a, b, r, color, rib, n=2, rib_color=None):
    """A flexible ribbed hose from a to b (duct arms): a tube with n raised ribs."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    m.seg(name, a, b, r, color, "SmoothPlastic", shape="C", ext=r * 0.2)
    v = b - a
    for k in range(n):
        t = (k + 0.5) / n
        disc(m, name, a + v * t, v, r * 2.5, rib, rib_color or shade(color, 0.86))


def star6(m, name, p, n, s, color, mat="Neon", spin=0.0):
    """A twinkle star lying on a surface: three crossed bars."""
    for k in range(3):
        m.blk(name, (s, s * 0.24, s * 0.14), p, color, mat, R=frame_normal(n, spin + k * 60))


def star5(m, name, c, n, r, t, color, mat="Neon", ray=None):
    """A chunky five-pointed star facing along n: a round middle and five rounded points."""
    F = frame_normal(n)
    m.add("E", name, (r * 1.0, r * 1.0, t), c, color, mat, F)
    for k in range(5):
        a = math.radians(90 + k * 72)
        d = F[:, 0] * math.cos(a) + F[:, 1] * math.sin(a)
        Fr = np.column_stack([d, np.cross(F[:, 2], d), F[:, 2]])
        m.add("E", ray or name, (r * 1.04, r * 0.4, t * 0.9), c + d * r * 0.5, color, mat, Fr)


# ------------------------------------------------------------------------------------------------
@model
def bolt_bug():
    """Bolt Bug (Common): a beetle robot. A teal enamel dome split into two wing cases with orange
    lightning decals, a big hex bolt on its back, six thick jointed legs on rubber feet, two antenna
    lights and big curious lamp eyes in chrome bezels."""
    m = SModel("bolt_bug")
    sc, ss = V(0, 1.0, 0.22), (1.86, 1.2, 2.16)
    m.ell("Belly", (1.62, 0.56, 1.96), V(0, 0.66, 0.2), GRAPHITE, "Metal")
    m.ell("Shell", ss, sc, TEAL, refl=0.2)
    # the seam between the two wing cases, a chrome rim round the bottom and rivets along the seam
    m.ell("ShellSeam", (0.08, ss[1] + 0.03, ss[2] + 0.03), sc, TEAL_D)
    eband(m, "ShellRim", V(0, 0.68, 0.22), 0.8, 0.93, 0.1, CHROME, n=12, h=0.12, mat="Metal")
    for s in (-1, 1):
        for z in (-0.3, 0.2, 0.7):
            p, n = top_pt(sc, ss, s * 0.15, z)
            disc(m, "Rivet", p, n, 0.11, 0.06, CHROME, "Metal")
        # a lightning bolt decal on each wing case
        p, n = on_ell(sc, ss, (s * 0.9, 0.25, -0.05))
        F = frame_normal(n)
        m.bolt("Decal", p - n * 0.015 + F[:, 1] * 0.26, 0.52, w=0.13, t=0.05, color=ORANGE, mat="SmoothPlastic", R=F)
    # enamel shine
    for (d, sz) in (((-0.42, 0.85, -0.3), (0.42, 0.18)), ((-0.62, 0.6, 0.12), (0.16, 0.1))):
        p, n = on_ell(sc, ss, d)
        m.ell("ShellShine", (sz[0], sz[1], 0.04), p, WHITE, R=frame_normal(n, 35), tr=0.35)
    # the big bolt on its back
    bp, bn = top_pt(sc, ss, 0, 0.5)
    with m.group(R=up_frame(bn), t=bp):
        m.cyl("Washer", 0.08, 0.8, (0, 0.0, 0), STEEL_D, "y", "Metal")
        hexnut(m, "Bolt", V(0, 0.14, 0), (0, 1, 0), 0.3, 0.22, CHROME)
        m.blk("BoltSlot", (0.44, 0.04, 0.07), (0, 0.26, 0), GRAPHITE)
        m.blk("BoltSlot", (0.07, 0.04, 0.44), (0, 0.26, 0), GRAPHITE)
    # a charge meter on its tail end
    bk, bkn = on_ell(sc, ss, (0, -0.1, 1))
    F = frame_normal(bkn)
    m.ell("ChargeFrame", (0.56, 0.3, 0.06), bk, GRAPHITE, R=F)
    for k in range(3):
        m.ell("Charge", (0.12, 0.17, 0.05), bk + F[:, 0] * (k - 1) * 0.15 + bkn * 0.03, LED if k < 2 else shade(LED, 0.4),
              "Neon" if k < 2 else "SmoothPlastic", R=F)

    # head: big lamp eyes (one brow up, curious), chrome mandibles, a little "o" mouth
    hc, hs = V(0, 0.9, -0.96), (1.26, 0.94, 1.02)
    m.ell("Head", hs, hc, STEEL, "Metal", refl=0.1)
    for s in (-1, 1):
        md = dict(CURIOUS)
        if s > 0:
            md.update(brow=-26, lift=0.48)
        d = norm(Ry(s * 27) @ Rx(12) @ V(0, 0, -1))
        p, n = on_ell_R(hc, hs, I3, d)
        lens_eye(m, p, n, 0.44, STEEL, md, TEAL, s, brow=ORANGE, brow_k=0.9)
        m.horn("Fang", hc + V(s * 0.3, -0.26, -0.3), hc + V(s * 0.1, -0.42, -0.7), 0.075, CHROME, curve=(s * 0.08, 0, -0.04), mat="Metal", n=2)
        p, n = on_ell_R(hc, hs, I3, (s, 0.05, -0.15))
        disc(m, "Knob", p, n, 0.2, 0.08, CHROME, "Metal")
        disc(m, "Knob", p + n * 0.04, n, 0.09, 0.06, ORANGE, "Neon")
        # antennae with glowing tips
        b0 = hc + V(s * 0.24, 0.4, 0.06)
        b1 = V(s * 0.4, 1.5, -1.12)
        b2 = V(s * 0.6, 1.62, -1.44)
        m.cyl("Antenna", 0.1, 0.16, b0, GRAPHITE, "y", "Metal")
        m.seg("Antenna", b0, b1, 0.045, STEEL_D, "Metal", shape="C", ext=0.02)
        m.seg("Antenna", b1, b2, 0.04, STEEL_D, "Metal", shape="C", ext=0.02)
        tip = m.ball("AntennaTip", 0.2, b2 + norm(b2 - b1) * 0.06, ORANGE, "Neon")
        if s > 0:
            m.light(tip, ORANGE_L, 0.8, 4)
    mp, mn = ell_front_at(hc, hs, 0, -0.2)
    m.mouth(mp, mn, 0.22, CURIOUS, kind="open")

    # six thick jointed legs on rubber feet
    for (z0, dz) in ((-0.36, -0.42), (0.22, 0.0), (0.8, 0.42)):
        for s in (-1, 1):
            hip = V(s * 0.7, 0.62, z0)
            knee = V(s * 1.04, 0.96, z0 + dz * 0.4)
            ank = V(s * 1.12, 0.2, z0 + dz)
            m.ball("Hip", 0.3, hip, GRAPHITE, "Metal")
            m.seg("Thigh", hip, knee, 0.12, STEEL, "Metal", bulge=0.45, ext=0.04)
            m.ball("Knee", 0.25, knee, ORANGE)
            m.seg("Shin", knee, ank, 0.1, STEEL, "Metal", bulge=0.4, ext=0.03)
            m.ell("Foot", (0.3, 0.18, 0.38), V(s * 1.14, 0.09, z0 + dz * 1.1), RUBBER, "Rubber")
    return m


@model
def roomba_rex():
    """Roomba Rex (Common): a chunky teal robot T-rex riding a robot vacuum like a seat. A big head
    with lens eyes and a fierce frown, a wide open jaw of steel teeth, tiny arms with orange claws,
    orange back plates and a tail that ends in a plug."""
    m = SModel("roomba_rex")
    vz = 0.1
    # the robot vacuum
    m.cyl("Vacuum", 0.44, 2.5, (0, 0.28, vz), GRAPHITE, "y", "Metal")
    m.cyl("Bumper", 0.22, 2.62, (0, 0.24, vz), RUBBER, "y", "Rubber")
    m.cyl("VacuumRing", 0.06, 2.48, (0, 0.5, vz), CHROME, "y", "Metal")
    m.cyl("VacuumTop", 0.07, 2.28, (0, 0.53, vz), STEEL, "y", "Metal")
    m.ell("Sensor", (1.1, 0.12, 0.32), (0, 0.38, vz - 1.15), SCREEN, "Glass", refl=0.4)
    for k in range(3):
        m.ball("Led", 0.1, (-0.16 + k * 0.16, 0.57, vz - 0.92), (LED, ORANGE, LED)[k], "Neon")
    for s in (-1, 1):
        bc = V(s * 0.86, 0.06, vz - 0.86)
        m.cyl("Brush", 0.06, 0.2, bc, ORANGE, "y")
        for k in range(3):
            a = math.radians(k * 120 + s * 20)
            m.seg("Brush", bc, bc + V(math.cos(a) * 0.42, -0.02, math.sin(a) * 0.42), 0.035, ORANGE_L, bulge=0.6)
    m.blk("DustBin", (0.72, 0.2, 0.42), (0, 0.64, vz + 0.9), GLASS, "Glass", tr=0.45, refl=0.3)
    m.ball("DustBunny", 0.16, (0.12, 0.62, vz + 0.9), (150, 150, 158), "Fabric")

    # the dino: a body leaning forward, a deep chest with a steel belly, haunches on the seat
    m.ell("DinoBody", (1.24, 1.16, 1.6), (0, 1.12, 0.3), TEAL, R=rot(x=24), refl=0.12)
    cc, cs = V(0, 1.48, -0.18), (1.02, 1.0, 0.92)
    m.ell("Chest", cs, cc, TEAL, refl=0.12)
    m.seg("Neck", V(0, 1.6, -0.24), V(0, 1.98, -0.52), 0.36, TEAL)
    bc_, bs_ = V(0, 1.4, -0.46), (0.72, 0.86, 0.44)
    m.ell("Belly", bs_, bc_, LIGHT, "Metal")
    for k in range(3):
        p, n = ell_front_at(bc_, bs_, 0, -0.24 + k * 0.2)
        m.ell("BellyPlate", (0.52 - abs(k - 1) * 0.1, 0.05, 0.06), p, STEEL_D, R=frame_normal(n))
    for s in (-1, 1):
        m.ell("Haunch", (0.46, 0.74, 0.96), V(s * 0.5, 0.88, 0.42), TEAL, R=rot(x=-8), refl=0.12)
        for k in (-1, 1):
            m.horn("FootClaw", V(s * 0.5 + k * 0.1, 0.62, -0.02), V(s * 0.52 + k * 0.12, 0.6, -0.2), 0.06, ORANGE, n=1)
    for (y, z, L) in ((1.92, -0.08, 0.3), (1.78, 0.3, 0.34), (1.58, 0.64, 0.3), (1.32, 0.94, 0.24)):
        m.seg("BackPlate", V(0, y - 0.1, z), V(0, y + L, z + 0.06), 0.035, ORANGE, r2=0.15, bulge=0.32)

    # head: a big rounded skull, snout and open jaw
    hc, hs, HR = V(0, 2.14, -0.66), (1.1, 0.86, 1.2), rot(x=-6)
    m.ell("DinoHead", hs, hc, TEAL, R=HR, refl=0.12)
    nc, ns, NR = V(0, 2.02, -1.12), (0.94, 0.52, 0.8), rot(x=-4)
    m.ell("Snout", ns, nc, TEAL, R=NR, refl=0.12)
    m.ell("Jaw", (0.9, 0.32, 1.02), V(0, 1.62, -0.94), TEAL_D, R=rot(x=-22))
    m.ell("Mouth", (0.8, 0.4, 0.92), V(0, 1.82, -1.0), MOUTH_D)
    m.ell("Tongue", (0.42, 0.12, 0.5), V(0, 1.7, -1.08), (240, 110, 130), R=rot(x=-14))
    for k in range(6):
        a = math.radians(-55 + k * 22)
        top = V(0.36 * math.sin(a), 1.82, -1.12 - 0.34 * math.cos(a))
        m.seg("Tooth", top, top + V(0, -0.15, 0), 0.045, LIGHT, "Metal", bulge=0.3)
    for k in range(4):
        a = math.radians(-42 + k * 28)
        base = V(0.3 * math.sin(a), 1.5, -1.0 - 0.38 * math.cos(a))
        m.seg("Tooth", base, base + V(0, 0.13, 0), 0.04, LIGHT, "Metal", bulge=0.3)
    for s in (-1, 1):
        d = norm(HR @ (Ry(s * 34) @ Rx(26) @ V(0, 0, -1)))
        p, n = on_ell_R(hc, hs, HR, d)
        lens_eye(m, p, n, 0.34, TEAL, FIERCE_SMALL, ORANGE, s, h=0.36, brow=TEAL_D, brow_k=1.25, rim_k=1.28)
        p, n = on_ell_R(nc, ns, NR, (s * 0.3, 0.55, -0.78))
        m.ell("Nostril", (0.1, 0.06, 0.05), p, MOUTH_D, R=frame_normal(n))
    for k, (y, z) in enumerate(((2.58, -0.72), (2.5, -0.4))):
        m.seg("Spike", V(0, y - 0.06, z), V(0, y + 0.22 - k * 0.04, z + 0.08), 0.035, ORANGE, r2=0.13, bulge=0.32)

    # tiny arms with orange claws
    for s in (-1, 1):
        sh = V(s * 0.46, 1.44, -0.44)
        el = V(s * 0.62, 1.26, -0.64)
        wr = V(s * 0.54, 1.2, -0.86)
        m.arm(sh, el, wr, 0.11, 0.1, 0.09, TEAL)
        m.ball("Hand", 0.18, wr + V(0, -0.02, -0.06), TEAL)
        for k in (-1, 1):
            m.horn("Claw", wr + V(k * 0.06, -0.04, -0.1), wr + V(k * 0.07, -0.16, -0.2), 0.035, ORANGE, n=1)

    # the tail sweeps back and ends in a power plug
    tp = [V(0, 1.0, 0.86), V(0.05, 1.0, 1.22), V(0.18, 1.06, 1.56), V(0.38, 1.18, 1.82), V(0.58, 1.32, 1.98)]
    rr = [0.36, 0.3, 0.23, 0.16, 0.1]
    m.flow("Tail", tp, rr, TEAL, refl=0.12)
    for (i, t) in ((0, 0.6), (1, 0.6), (2, 0.6)):
        p = tp[i] + (tp[i + 1] - tp[i]) * t + V(0, (rr[i] + rr[i + 1]) * 0.42, 0)
        m.seg("Tail", p - V(0, 0.06, 0), p + V(0, 0.2 - i * 0.04, 0.05), 0.03, ORANGE, r2=0.12 - i * 0.02, bulge=0.32)
    d = norm(tp[-1] - tp[-2])
    m.seg("TailTip", tp[-1] - d * 0.04, tp[-1] + d * 0.2, 0.11, ORANGE, shape="B")
    side = norm(np.cross(d, V(0, 1, 0)))
    for k in (-1, 1):
        m.seg("TailTip", tp[-1] + d * 0.18 + side * k * 0.05, tp[-1] + d * 0.34 + side * k * 0.05, 0.02, CHROME, "Metal", shape="B")
    return m


@model
def toaster_knight():
    """Toaster Knight (Rare): a chrome toaster knight. A helm slot with determined eyes and a nose
    guard, toast in the slots and a plume, toast-slice pauldrons, a butter-knife sword raised high,
    a toast shield with a jam heart, armoured legs and a power-cord tail."""
    m = SModel("toaster_knight")
    BY = 1.75
    CH = (214, 220, 230)
    m.rbox("Body", (2.0, 1.6, 1.3), (0, BY, 0), CH, 0.36, "Metal", refl=0.3, axis="z")
    m.blk("BodyTrim", (2.04, 0.22, 1.34), (0, BY - 0.8, 0), TEAL)
    m.ell("Shine", (0.1, 0.9, 0.03), (-0.8, BY + 0.1, -0.66), WHITE, tr=0.4)
    zf = -0.65
    # the helm: a dark eye slot with the eyes, a nose guard, breathing holes and a brave smile
    m.ell("Visor", (1.5, 0.58, 0.1), (0, BY + 0.2, zf - 0.01), GRAPHITE)
    for s in (-1, 1):
        m.eye(V(s * 0.34, BY + 0.2, zf - 0.04), V(0, 0, -1), 0.34, 0.38, CH, VALIANT, side=s, iris=TEAL, brow=GRAPHITE, brow_k=1.1)
        for k in range(3):
            m.ell("Vent", (0.07, 0.07, 0.04), V(s * (0.58 + k * 0.09), BY - 0.16 - k * 0.07, zf - 0.005), GRAPHITE)
    m.ell("NoseGuard", (0.13, 0.66, 0.1), V(0, BY + 0.12, zf - 0.06), CH, "Metal")
    m.mouth(V(0, BY - 0.32, zf - 0.01), V(0, 0, -1), 0.46, VALIANT, color=MOUTH_D)
    # browning dial, shade dots and the crumb tray
    disc(m, "Dial", V(0.66, BY - 0.5, zf - 0.03), V(0, 0, -1), 0.26, 0.08, CH, "Metal")
    m.blk("DialMark", (0.04, 0.1, 0.03), V(0.66, BY - 0.46, zf - 0.08), ORANGE, "Neon")
    for k, c in enumerate(((246, 214, 160), (222, 166, 92), (150, 92, 44))):
        m.ball("Shade", 0.08, V(-0.78 + k * 0.12, BY - 0.52, zf - 0.01), c)
    m.blk("CrumbTray", (1.0, 0.06, 0.04), (0, BY - 0.68, zf - 0.01), GRAPHITE)
    # the lever on its side
    m.blk("LeverSlot", (0.04, 0.7, 0.12), (1.0, BY - 0.05, 0.36), GRAPHITE)
    m.blk("Lever", (0.22, 0.1, 0.12), (1.1, BY + 0.1, 0.36), GRAPHITE)
    m.ball("Lever", 0.18, (1.2, BY + 0.1, 0.36), ORANGE)

    # two slices of toast in the slots (the helmet's crest) and a plume between them
    top = BY + 0.8
    for s in (-1, 1):
        x = s * 0.42
        m.blk("Slot", (0.28, 0.04, 1.02), (x, top + 0.01, 0), GRAPHITE)
        m.blk("Toast", (0.16, 0.6, 0.9), (x, top + 0.24, 0), CRUST)
        for z in (-0.2, 0.2):
            m.cyl("Toast", 0.16, 0.5, (x, top + 0.56, z), CRUST, "x")
        m.blk("Crumb", (0.18, 0.5, 0.76), (x, top + 0.26, 0), TOAST)
        for z in (-0.19, 0.19):
            m.cyl("Crumb", 0.18, 0.38, (x, top + 0.55, z), TOAST, "x")
    m.cyl("Plume", 0.16, 0.2, (0, top + 0.08, 0.12), GOLD, "y", "Metal")
    m.seg("Plume", V(0, top + 0.12, 0.1), V(0, top + 0.78, 0.38), 0.14, (222, 46, 46), "Fabric", r2=0.1, bulge=0.55)
    m.seg("Plume", V(0, top + 0.14, 0.16), V(0, top + 0.62, 0.72), 0.13, (250, 246, 240), "Fabric", r2=0.09, bulge=0.55)
    m.seg("Plume", V(0, top + 0.12, 0.2), V(0, top + 0.42, 0.88), 0.11, (222, 46, 46), "Fabric", r2=0.08, bulge=0.55)

    # toast-slice pauldrons
    for s in (-1, 1):
        m.ball("Shoulder", 0.5, V(s * 1.08, BY + 0.3, 0), CH, "Metal")
        with m.group(R=Rz(-s * 30), t=V(s * 1.02, BY + 0.62, 0)):
            m.blk("Pauldron", (0.62, 0.12, 0.62), V(-s * 0.04, 0, 0), CRUST)
            for z in (-0.17, 0.17):
                m.cyl("Pauldron", 0.12, 0.42, V(s * 0.27, 0, z), CRUST, "y")
            m.blk("Pauldron", (0.52, 0.14, 0.5), V(-s * 0.04, 0.005, 0), TOAST)
            for z in (-0.15, 0.15):
                m.cyl("Pauldron", 0.14, 0.32, V(s * 0.25, 0.005, z), TOAST, "y")

    # right arm (+x): the butter-knife sword raised high
    sh, el, wr = V(1.08, BY + 0.3, 0.0), V(1.44, BY - 0.06, -0.3), V(1.38, BY + 0.24, -0.7)
    m.arm(sh, el, wr, 0.15, 0.14, 0.13, STEEL, mat="Metal", cuff=CH)
    hcen = wr + norm(wr - el) * 0.14
    m.glove(hcen, 0.19, GRAPHITE, 1, fist=True, forward=(0, 0, -1))
    kd = norm(V(0.0, 1.0, -0.2))
    m.seg("KnifeHandle", hcen - kd * 0.26, hcen + kd * 0.26, 0.075, (120, 74, 44), shape="C")
    m.add("B", "KnifeGuard", (0.08, 0.44, 0.16), hcen + kd * 0.3, GOLD, "Metal", frame_from_x(kd))
    b0, b1 = hcen + kd * 0.32, hcen + kd * 1.5
    m.seg("KnifeBlade", b0, b1, 0.13, (226, 230, 238), "Metal", r2=0.025, shape="B", refl=0.35)
    m.seg("KnifeEdge", b1 - kd * 0.12, b1 + kd * 0.12, 0.13, (226, 230, 238), "Metal", r2=0.025)
    m.add("E", "Butter", (0.3, 0.2, 0.08), hcen + kd * 1.1 + V(0, 0, -0.03), BUTTER, "SmoothPlastic", frame_from_x(kd))

    # left arm (-x): the toast shield held in front
    sh2, el2, wr2 = V(-1.08, BY + 0.3, 0.0), V(-1.42, BY - 0.14, -0.22), V(-1.32, BY - 0.06, -0.64)
    m.arm(sh2, el2, wr2, 0.15, 0.14, 0.13, STEEL, mat="Metal", cuff=CH)
    m.glove(wr2 + norm(wr2 - el2) * 0.14, 0.19, GRAPHITE, -1, fist=True, forward=(0, 0, -1))
    with m.group(R=Ry(17), t=V(-1.36, BY + 0.0, -0.98)):
        m.blk("ShieldCrust", (1.0, 0.86, 0.14), V(0, -0.14, 0), CRUST)
        for x in (-0.24, 0.24):
            m.cyl("ShieldCrust", 0.14, 0.56, V(x, 0.28, 0), CRUST, "z")
        m.blk("ToastShield", (0.86, 0.74, 0.16), V(0, -0.14, -0.01), TOAST)
        for x in (-0.23, 0.23):
            m.cyl("ToastShield", 0.16, 0.42, V(x, 0.27, -0.01), TOAST, "z")
        for x in (-0.1, 0.1):
            m.ell("Jam", (0.28, 0.28, 0.06), V(x, 0.0, -0.1), JAM, refl=0.2)
        m.blk("Jam", (0.24, 0.24, 0.06), V(0, -0.13, -0.1), JAM, R=Rz(45), refl=0.2)
        m.ell("Jam", (0.07, 0.07, 0.04), V(-0.12, 0.06, -0.135), (255, 150, 170))
        m.blk("ShieldBoss", (0.24, 0.16, 0.08), V(0.24, 0.3, -0.1), BUTTER, R=Rz(-12))

    # armoured legs: steel thighs, orange knees, chrome greaves, dark sabatons with chrome toes
    m.legs2(BY - 0.78, 0.5, STEEL, 0.2, 0.19, 0.17, 0.52, 0.74, GRAPHITE, toe=CH, knee_color=ORANGE, sole=RUBBER, mat="Metal")
    for s in (-1, 1):
        m.ell("Greave", (0.4, 0.3, 0.42), V(s * 0.53, 0.5, -0.05), CH, "Metal")

    # the power cord tail with a plug
    cp = [V(0.46, BY - 0.62, 0.6), V(0.66, 0.66, 1.0), V(0.5, 0.3, 1.32), V(0.82, 0.13, 1.56)]
    for i in range(3):
        m.seg("Tail", cp[i], cp[i + 1], 0.055, RUBBER, "Rubber", shape="C", ext=0.03)
    d = norm(cp[3] - cp[2])
    m.seg("TailTip", cp[3], cp[3] + d * 0.26, 0.11, LIGHT, shape="B")
    side = norm(np.cross(d, V(0, 1, 0)))
    for k in (-1, 1):
        m.seg("TailTip", cp[3] + d * 0.24 + side * k * 0.05, cp[3] + d * 0.38 + side * k * 0.05, 0.02, CHROME, "Metal", shape="B")
    return m


@model
def laundry_bot_3000():
    """Laundry Bot 3000 (Rare): a cheerful front-loader robot. A porthole belly of suds with a sock
    tumbling inside, a screen face with a big grin, ribbed duct arms with orange rubber gloves (one
    waving, one flying a striped sock flag), stubby legs on washer feet and soap bubbles."""
    m = SModel("laundry_bot_3000")
    BY = 1.95
    WASHER = (236, 240, 246)
    m.rbox("Body", (2.1, 2.2, 1.8), (0, BY, 0), WASHER, 0.3, axis="z", refl=0.08)
    m.blk("Plinth", (1.96, 0.2, 1.66), (0, BY - 1.08, 0), GRAPHITE)
    zf = -0.9
    # control panel: detergent drawer, buttons, the cycle dial
    m.rbox("Panel", (1.94, 0.46, 0.08), (0, BY + 0.78, zf - 0.02), TEAL, 0.12, axis="z")
    m.blk("Drawer", (0.5, 0.26, 0.06), (-0.6, BY + 0.78, zf - 0.07), WASHER)
    m.blk("DrawerHandle", (0.3, 0.05, 0.04), (-0.6, BY + 0.72, zf - 0.11), STEEL_D)
    for k, c in enumerate((ORANGE, LED, WHITE)):
        disc(m, "PanelButton", V(-0.12 + k * 0.17, BY + 0.78, zf - 0.08), V(0, 0, -1), 0.11, 0.05, c, "Neon")
    disc(m, "PanelDial", V(0.66, BY + 0.78, zf - 0.08), V(0, 0, -1), 0.32, 0.08, CHROME, "Metal")
    m.blk("DialMark", (0.04, 0.12, 0.03), V(0.66, BY + 0.84, zf - 0.13), ORANGE, "Neon")
    # the porthole: chrome ring, dark drum, soapy water, suds, a sock and a domed glass door
    pc = V(0, BY - 0.22, zf)
    disc(m, "DoorRing", pc + V(0, 0, -0.06), V(0, 0, -1), 1.56, 0.16, CHROME, "Metal", refl=0.3)
    disc(m, "Drum", pc + V(0, 0, -0.16), V(0, 0, -1), 1.22, 0.04, (70, 78, 92), "Metal")
    m.ell("Water", (1.04, 0.5, 0.06), pc + V(0, -0.27, -0.18), (70, 150, 236))
    for (x, y, d) in ((-0.36, -0.05, 0.2), (-0.14, -0.02, 0.22), (0.1, -0.04, 0.2), (0.33, -0.06, 0.17), (-0.02, 0.13, 0.15), (0.22, 0.11, 0.12)):
        m.ball("Suds", d, pc + V(x, y, -0.19), WHITE)
    m.ell("SockInside", (0.2, 0.42, 0.06), pc + V(-0.2, 0.3, -0.19), (246, 110, 150), R=Rz(50))
    m.ell("SockInside", (0.18, 0.2, 0.06), pc + V(-0.34, 0.44, -0.19), (246, 110, 150))
    m.ell("Door", (1.24, 1.24, 0.3), pc + V(0, 0, -0.16), GLASS, "Glass", tr=0.5, refl=0.35)
    m.blk("DoorHandle", (0.14, 0.44, 0.14), pc + V(0.86, 0, -0.12), CHROME, "Metal")

    # head: a little washer with a screen face and a big happy grin
    m.cyl("Neck", 0.22, 0.56, (0, BY + 1.16, 0), STEEL_D, "y", "Metal")
    hc = V(0, BY + 1.72, -0.04)
    m.rbox("Head", (1.5, 1.0, 1.1), hc, WASHER, 0.26, axis="z", refl=0.08)
    sz = hc[2] - 0.55
    m.ell("Screen", (1.2, 0.78, 0.1), V(0, hc[1], sz - 0.01), SCREEN, refl=0.2)
    for s in (-1, 1):
        m.eye(V(s * 0.27, hc[1] + 0.08, sz - 0.05), V(0, 0, -1), 0.28, 0.3, SCREEN, EAGER_BOT, side=s, iris=TEAL, brow=LED, brow_k=0.9)
        m.ell("Cheek", (0.14, 0.07, 0.04), V(s * 0.47, hc[1] - 0.14, sz - 0.06), (255, 130, 170), "Neon")
        disc(m, "Earpiece", V(s * 0.76, hc[1], hc[2]), V(1, 0, 0), 0.4, 0.12, CHROME, "Metal")
        disc(m, "Earpiece", V(s * 0.83, hc[1], hc[2]), V(1, 0, 0), 0.18, 0.06, ORANGE, "Neon")
    m.mouth(V(0, hc[1] - 0.2, sz - 0.05), V(0, 0, -1), 0.34, EAGER_BOT, color=MOUTH_D, skin=SCREEN)
    a0, a1 = V(0.4, hc[1] + 0.46, hc[2] + 0.1), V(0.56, hc[1] + 0.88, hc[2] + 0.16)
    m.seg("Antenna", a0, a1, 0.028, STEEL_D, "Metal", shape="C")
    t = m.ball("AntennaTip", 0.17, a1, ORANGE, "Neon")
    m.light(t, ORANGE_L, 0.8, 4)

    # ribbed duct arms with orange rubber gloves
    for s in (-1, 1):
        m.ball("Shoulder", 0.46, V(s * 1.08, BY + 0.5, 0), CHROME, "Metal")
    sh, el, wr = V(1.12, BY + 0.5, 0), V(1.56, BY + 0.62, -0.14), V(1.52, BY + 1.18, -0.28)
    ribbed(m, "UpperArm", sh, el, 0.13, LIGHT_D, 0.07, n=2, rib_color=STEEL)
    m.ball("Elbow", 0.3, el, CHROME, "Metal")
    ribbed(m, "Forearm", el, wr, 0.13, LIGHT_D, 0.07, n=2, rib_color=STEEL)
    d = norm(wr - el)
    disc(m, "Cuff", wr, d, 0.38, 0.14, ORANGE)
    hp = wr + d * 0.24
    m.ell("Hand", (0.38, 0.38, 0.2), hp, ORANGE)
    for k in range(4):
        x = (k - 1.5) * 0.09
        m.seg("Finger", hp + V(x, 0.1, 0), hp + V(x * 1.25, 0.36 - abs(k - 1.5) * 0.04, -0.02), 0.052, ORANGE, bulge=0.5, ext=0.03)
    m.seg("Thumb", hp + V(-0.12, -0.02, -0.02), hp + V(-0.3, 0.12, -0.04), 0.06, ORANGE, bulge=0.45, ext=0.03)
    sh2, el2, wr2 = V(-1.12, BY + 0.5, 0), V(-1.52, BY + 0.08, -0.2), V(-1.44, BY - 0.02, -0.62)
    ribbed(m, "UpperArm", sh2, el2, 0.13, LIGHT_D, 0.07, n=2, rib_color=STEEL)
    m.ball("Elbow", 0.3, el2, CHROME, "Metal")
    ribbed(m, "Forearm", el2, wr2, 0.13, LIGHT_D, 0.07, n=2, rib_color=STEEL)
    d2 = norm(wr2 - el2)
    disc(m, "Cuff", wr2, d2, 0.38, 0.14, ORANGE)
    fist = wr2 + d2 * 0.18
    m.glove(fist, 0.18, ORANGE, -1, fist=True, forward=(0, 0, -1))
    # the flag: a chrome pole with a striped sock flying from the top
    p0, p1 = fist + V(0, -0.36, -0.02), fist + V(0.06, 2.8, -0.12)
    m.seg("FlagPole", p0, p1, 0.045, CHROME, "Metal", shape="C")
    m.ball("FlagTip", 0.15, p1 + V(0, 0.05, 0), ORANGE)
    with m.group(R=Rz(-6), t=p1 + V(0.02, -0.24, 0)):
        m.ell("SockFlag", (0.12, 0.38, 0.1), V(0.04, 0, 0), TEAL_D, "Fabric")
        m.ell("SockFlag", (0.74, 0.34, 0.08), V(0.38, 0, 0), WHITE, "Fabric")
        m.ell("SockFlag", (0.08, 0.3, 0.09), V(0.2, 0, 0), TEAL, "Fabric")
        m.ell("SockFlag", (0.08, 0.33, 0.09), V(0.42, 0, 0), TEAL, "Fabric")
        m.seg("SockFlag", V(0.66, 0.02, 0), V(0.86, -0.2, 0), 0.17, WHITE, "Fabric", r2=0.045)
        m.ell("SockFlag", (0.26, 0.26, 0.1), V(0.84, -0.2, 0), ORANGE, "Fabric")
        m.ell("SockFlag", (0.22, 0.2, 0.1), V(0.7, 0.04, 0), ORANGE, "Fabric")

    # stubby legs on round rubber washer feet
    ank = m.legs2(BY - 1.02, 0.6, STEEL, 0.21, 0.2, 0.18, 0.6, 0.6, None, foot="none", ankle_y=0.4, knee_color=TEAL, mat="Metal")
    for a in ank:
        m.cyl("Foot", 0.22, 0.8, (a[0], 0.11, a[2] - 0.02), RUBBER, "y", "Rubber")
        m.ell("Foot", (0.66, 0.24, 0.66), (a[0], 0.26, a[2] - 0.02), CHROME, "Metal")

    # the back: a service panel, lint filter, water inlet hose and a sticker
    zb = 0.9
    m.blk("ServicePanel", (1.5, 1.4, 0.04), (0, BY + 0.05, zb + 0.01), LIGHT_D)
    for (x, y) in ((-0.64, 0.6), (0.64, 0.6), (-0.64, -0.55), (0.64, -0.55)):
        disc(m, "Screw", V(x, BY + 0.05 + y, zb + 0.04), V(0, 0, 1), 0.1, 0.04, STEEL_D, "Metal")
    for k in range(4):
        m.blk("Lint", (0.7, 0.06, 0.03), (0.22, BY + 0.5 - k * 0.13, zb + 0.04), STEEL_D)
    disc(m, "Inlet", V(-0.42, BY - 0.15, zb + 0.06), V(0, 0, 1), 0.24, 0.16, CHROME, "Metal")
    hose = [V(-0.42, BY - 0.15, zb + 0.14), V(-0.52, BY - 0.62, zb + 0.34), V(-0.26, BY - 1.1, zb + 0.46), V(0.18, 0.12, zb + 0.52)]
    for i in range(3):
        m.seg("InletHose", hose[i], hose[i + 1], 0.07, (110, 150, 230), "Rubber", shape="C", ext=0.04)
    m.blk("Sticker", (0.46, 0.3, 0.03), (0.3, BY - 0.42, zb + 0.03), (90, 170, 240))
    for (y, w) in ((0.04, 0.32), (-0.05, 0.24)):
        m.blk("Sticker", (w, 0.04, 0.02), (0.3, BY - 0.42 + y, zb + 0.05), WHITE)
    # soap bubbles drifting up
    for (x, y, z, d) in ((0.98, 3.94, 0.22, 0.24), (0.92, 4.46, 0.02, 0.28), (0.12, 4.42, 0.32, 0.18), (-1.02, 3.42, -0.32, 0.18)):
        m.ball("Bubble", d, (x, y, z), (226, 244, 255), "Glass", tr=0.45, refl=0.4)
        m.ball("Bubble", d * 0.26, (x - d * 0.18, y + d * 0.18, z - d * 0.32), WHITE, "Neon")
    return m


@model
def microwave_mage():
    """Microwave Mage (Epic): a wise old microwave wizard. A teal wizard hat with orange stars and a
    moon, a wise face on the glowing window with gold spectacles and bushy brows, a mustache and a
    long beard of white cables ending in plugs, bell sleeves, a star wand, a floating orb and curly
    wizard shoes."""
    m = SModel("microwave_mage")
    BY = 1.95
    SHELL = (222, 226, 232)
    AMBER = (255, 172, 78)
    LIDC = (226, 140, 60)
    GLOVE_W = (246, 246, 250)
    m.rbox("Body", (2.5, 1.6, 1.6), (0, BY, 0), SHELL, 0.22, "Metal", axis="z", refl=0.15)
    zf = -0.8
    wx = -0.3
    m.rbox("WindowFrame", (1.56, 1.26, 0.06), (wx, BY, zf - 0.02), GRAPHITE, 0.14, axis="z")
    win = m.blk("Window", (1.38, 1.06, 0.04), (wx, BY, zf - 0.05), AMBER, "Neon", tr=0.05)
    m.light(win, (255, 180, 90), 1.6, 8)
    # the glowing turntable plate inside, seen behind the face like a halo
    disc(m, "Plate", V(wx, BY + 0.14, zf - 0.075), V(0, 0, -1), 0.96, 0.02, (255, 226, 160), "Neon")
    # the face: wise half-closed eyes behind round gold spectacles, bushy white brows
    ey = BY + 0.16
    for s in (-1, 1):
        ex = wx + s * 0.3
        disc(m, "Glasses", V(ex, ey - 0.01, zf - 0.09), V(0, 0, -1), 0.44, 0.03, GOLD, "Metal")
        m.eye(V(ex, ey, zf - 0.1), V(0, 0, -1), 0.3, 0.32, LIDC, WISE, side=s, iris=TEAL, brow=(246, 246, 250), brow_k=1.35)
    m.seg("Glasses", V(wx - 0.1, ey + 0.02, zf - 0.1), V(wx + 0.1, ey + 0.02, zf - 0.1), 0.02, GOLD, "Metal", shape="C")
    # a curly cable mustache and a smile
    my = BY - 0.12
    for s in (-1, 1):
        a = V(wx + s * 0.03, my, zf - 0.12)
        b = V(wx + s * 0.26, my - 0.08, zf - 0.13)
        c = V(wx + s * 0.4, my + 0.02, zf - 0.13)
        m.seg("Mustache", a, b, 0.07, CABLE, bulge=0.45, ext=0.03)
        m.seg("Mustache", b, c, 0.055, CABLE, bulge=0.5, ext=0.02)
        m.ball("Mustache", 0.1, c + V(s * 0.01, 0.04, 0), ORANGE)
    m.mouth(V(wx, my - 0.17, zf - 0.1), V(0, 0, -1), 0.26, WISE, color=MOUTH_D)
    # the long beard: white cables over a soft grey bed, each ending in a plug
    bc, bs = V(wx, BY - 0.62, zf - 0.08), (1.16, 0.96, 0.3)
    m.ell("Beard", bs, bc, (214, 216, 222), "Fabric")

    def beard_z(x, y):
        hx, hy, hz = bs[0] / 2, bs[1] / 2, bs[2] / 2
        q = 1 - ((x - bc[0]) / hx) ** 2 - ((y - bc[1]) / hy) ** 2
        return bc[2] - hz * math.sqrt(max(q, 0.0)) - 0.03

    for k in range(7):
        u = (k - 3) / 3.0
        x0 = bc[0] + u * 0.44
        y0 = bc[1] + 0.34 - abs(u) * 0.1
        y2 = bc[1] - 0.62 + abs(u) * 0.34 - (0.06 if k % 2 else 0)
        y1 = (y0 + y2) / 2
        x1 = x0 + 0.05 * (1 if k % 2 else -1)
        x2 = bc[0] + u * 0.34
        P0, P1, P2 = V(x0, y0, beard_z(x0, y0)), V(x1, y1, beard_z(x1, y1)), V(x2, y2, beard_z(x2, y2))
        m.seg("Beard", P0, P1, 0.075, CABLE, ext=0.03)
        m.seg("Beard", P1, P2, 0.07, CABLE, ext=0.03)
        m.blk("BeardPlug", (0.13, 0.12, 0.1), P2 + V(0, -0.06, 0), ORANGE if k % 2 else TEAL)
    # keypad, timer, start button and the door handle
    kx = 0.84
    m.blk("Keypad", (0.56, 1.26, 0.05), (kx, BY, zf - 0.02), GRAPHITE)
    m.blk("Timer", (0.44, 0.17, 0.03), (kx, BY + 0.44, zf - 0.05), LED, "Neon")
    for r in range(3):
        for c in range(2):
            m.blk("Key", (0.18, 0.13, 0.04), (kx - 0.1 + c * 0.2, BY + 0.16 - r * 0.18, zf - 0.05), (214, 218, 226))
    m.blk("StartButton", (0.4, 0.14, 0.04), (kx, BY - 0.44, zf - 0.05), ORANGE, "Neon")
    m.blk("DoorHandle", (0.06, 0.92, 0.1), (0.52, BY, zf - 0.07), CHROME, "Metal")

    # the wizard hat: wide brim with an orange edge, a tall cone with a bent tip, stars and a moon
    HB = BY + 0.82
    m.cyl("HatTrim", 0.06, 2.36, (0, HB, 0), ORANGE, "y")
    m.cyl("HatBrim", 0.1, 2.28, (0, HB + 0.06, 0), TEAL, "y")
    m.cyl("HatBand", 0.2, 1.5, (0, HB + 0.2, 0), ORANGE, "y")
    ca, cb = V(0, HB + 0.08, 0), V(0.03, HB + 0.92, 0.04)
    m.seg("Hat", ca, cb, 0.72, TEAL, bulge=0.12)
    m.seg("Hat", V(0.02, HB + 0.62, 0.03), V(0.12, HB + 1.3, 0.12), 0.38, TEAL, bulge=0.2)
    m.seg("Hat", V(0.1, HB + 1.12, 0.1), V(0.5, HB + 1.5, 0.38), 0.17, TEAL, bulge=0.22)
    m.ball("HatTip", 0.24, V(0.56, HB + 1.53, 0.42), ORANGE, "Neon")
    cc, cs, cR = seg_ell(ca, cb, 0.72, bulge=0.12)
    for (dvec, sz) in (((-0.55, 0.35, -0.75), 0.24), ((0.45, 0.62, -0.62), 0.2)):
        p, n = on_ell_R(cc, cs, cR, V(*dvec))
        star6(m, "HatStar", p + n * 0.01, n, sz, ORANGE_L, "Neon")
    c2, s2, R2 = seg_ell(V(0.02, HB + 0.62, 0.03), V(0.12, HB + 1.3, 0.12), 0.38, bulge=0.2)
    p, n = on_ell_R(c2, s2, R2, V(-0.3, 0.5, -0.8))
    star6(m, "HatStar", p + n * 0.01, n, 0.16, ORANGE_L, "Neon")
    p, n = on_ell_R(cc, cs, cR, V(0.7, 0.2, -0.4))
    F = frame_normal(n)
    m.ell("HatStar", (0.3, 0.3, 0.04), p + n * 0.01, (255, 230, 150), "Neon", R=F)
    m.ell("HatStar", (0.27, 0.27, 0.05), p + n * 0.02 + F[:, 0] * 0.08 + F[:, 1] * 0.05, TEAL, R=F)

    # arms in teal bell sleeves with orange cuffs and white gloves
    def sleeve_arm(s, el, wr):
        sh = V(s * 1.28, BY + 0.3, 0)
        m.ball("Shoulder", 0.44, sh, STEEL_D, "Metal")
        m.seg("UpperArm", sh, el, 0.13, STEEL, "Metal", bulge=0.45, ext=0.04)
        m.ball("Elbow", 0.28, el, STEEL_D, "Metal")
        d = norm(wr - el)
        m.seg("Sleeve", el - d * 0.05, wr - d * 0.2, 0.17, TEAL, shape="C")
        m.seg("Sleeve", wr - d * 0.22, wr, 0.25, TEAL, shape="C")
        m.seg("Cuff", wr - d * 0.03, wr + d * 0.03, 0.27, ORANGE, shape="C")
        m.seg("Sleeve", wr + d * 0.015, wr + d * 0.045, 0.19, (24, 40, 44), shape="C")
        return d

    el, wr = V(1.66, BY + 0.06, -0.3), V(1.72, BY + 0.52, -0.66)
    d = sleeve_arm(1, el, wr)
    hc = wr + d * 0.22
    m.glove(hc, 0.19, GLOVE_W, 1, fist=True, forward=(0, 0, -1))
    wd = norm(V(0.22, 1.0, -0.32))
    m.seg("Wand", hc - wd * 0.22, hc + wd * 1.05, 0.05, (110, 70, 44), shape="C")
    m.seg("WandBand", hc + wd * 0.82, hc + wd * 0.9, 0.065, GOLD, "Metal", shape="C")
    sc_ = hc + wd * 1.21
    star5(m, "WandStar", sc_, V(0, 0, -1), 0.28, 0.1, (255, 214, 90), "Neon", ray="WandGlow")
    m.sparkles(len(m.parts), (255, 236, 150))
    el2, wr2 = V(-1.66, BY - 0.06, -0.24), V(-1.6, BY + 0.06, -0.7)
    d2 = sleeve_arm(-1, el2, wr2)
    hc2 = wr2 + d2 * 0.22
    m.glove(hc2, 0.19, GLOVE_W, -1, fist=False, fingers=3, forward=(0, 0.4, -1))
    oc = hc2 + V(0, 0.5, -0.06)
    orb = m.ball("Orb", 0.36, oc, (150, 236, 255), "Neon")
    for (o, dd) in ((V(0.26, 0.1, -0.06), 0.08), (V(-0.22, -0.12, 0.08), 0.06)):
        m.ball("Orb", dd, oc + o, (210, 250, 255), "Neon")
    m.light(orb, (150, 236, 255), 1.2, 6)
    m.sparkles(orb, (190, 245, 255))

    # short legs and curly wizard shoes with glowing toe tips
    ank = m.legs2(BY - 0.74, 0.66, STEEL, 0.19, 0.18, 0.16, 0.56, 0.9, None, foot="none", ankle_y=0.36, knee_color=GRAPHITE, mat="Metal")
    for a in ank:
        x, z = a[0], a[2]
        m.ell("Shoe", (0.56, 0.42, 0.9), V(x, 0.22, z - 0.12), TEAL)
        m.blk("Sole", (0.5, 0.08, 0.8), V(x, 0.04, z - 0.1), GRAPHITE, "Rubber")
        m.seg("Toe", V(x, 0.2, z - 0.48), V(x, 0.44, z - 0.74), 0.1, TEAL, bulge=0.3)
        m.ball("Toe", 0.15, V(x, 0.46, z - 0.72), ORANGE, "Neon")

    # the back: vents, a warning sticker, the power cord and plug
    zb = 0.8
    for k in range(5):
        m.blk("Vent", (1.1, 0.07, 0.04), (0.2, BY + 0.5 - k * 0.15, zb + 0.01), GRAPHITE)
    m.blk("WarnSticker", (0.46, 0.4, 0.03), (-0.75, BY - 0.35, zb + 0.01), (250, 210, 60))
    m.text("WarnMark", "!", (-0.75, BY - 0.35, zb + 0.04), 0.28, INK, facing="back")
    cord = [V(0.6, BY - 0.5, zb), V(0.8, BY - 0.85, zb + 0.22), V(0.56, 0.5, zb + 0.44), V(0.2, 0.16, zb + 0.56)]
    for i in range(3):
        m.seg("PowerCord", cord[i], cord[i + 1], 0.05, GRAPHITE, "Rubber", shape="C", ext=0.03)
    m.blk("Plug", (0.24, 0.16, 0.26), cord[3] + V(-0.06, 0, 0.06), LIGHT)
    return m


@model
def mecha_fridge():
    """Mecha Fridge (Mythic): a stoic fridge mech. A teal enamel double-door torso with chrome
    handles, an ice dispenser and fridge magnets, a frosty freezer head with a visor, big pauldrons,
    a piston fist, an ice cannon arm and heavy mech legs."""
    m = SModel("mecha_fridge")
    FY = 2.45
    m.rbox("Fridge", (2.1, 2.3, 1.6), (0, FY, 0), TEAL, 0.24, axis="z", refl=0.15)
    zf = -0.8
    m.blk("DoorGap", (0.05, 2.04, 0.03), (0, FY - 0.04, zf - 0.005), TEAL_D)
    for s in (-1, 1):
        x = s * 0.15
        m.blk("Handle", (0.1, 0.9, 0.1), (x, FY + 0.28, zf - 0.13), CHROME, "Metal")
        for y in (FY - 0.12, FY + 0.68):
            m.blk("Handle", (0.08, 0.08, 0.1), (x, y, zf - 0.06), CHROME, "Metal")
    # the ice dispenser on the left door
    dx = -0.56
    m.rbox("Dispenser", (0.66, 0.86, 0.06), (dx, FY + 0.12, zf - 0.02), GRAPHITE, 0.1, axis="z")
    m.blk("DispenserGlow", (0.5, 0.06, 0.03), (dx, FY + 0.48, zf - 0.06), ICE, "Neon")
    m.blk("Chute", (0.22, 0.2, 0.06), (dx, FY + 0.3, zf - 0.06), (24, 26, 32))
    m.blk("DispenserLever", (0.3, 0.36, 0.04), (dx, FY + 0.0, zf - 0.07), STEEL_D, "Metal")
    m.blk("Tray", (0.56, 0.06, 0.16), (dx, FY - 0.26, zf - 0.1), CHROME, "Metal")
    ice = m.blk("Ice", (0.14, 0.14, 0.14), (dx - 0.05, FY + 0.16, zf - 0.12), (220, 244, 255), "Ice", R=rot(20, 30, 10), tr=0.15)
    m.blk("Ice", (0.12, 0.12, 0.12), (dx + 0.08, FY - 0.17, zf - 0.14), (220, 244, 255), "Ice", R=rot(-10, 45, 20), tr=0.15)
    m.smoke(ice, (230, 245, 255), 0.06, 0.25, 0.8)
    # fridge magnets, a note and a child's drawing on the right door
    m.blk("Note", (0.42, 0.5, 0.02), (0.52, FY + 0.48, zf - 0.01), (255, 250, 210), R=Rz(-6))
    for k in range(3):
        m.blk("NoteLine", (0.3, 0.03, 0.02), (0.53 - k * 0.01, FY + 0.5 - k * 0.11, zf - 0.025), (120, 140, 200), R=Rz(-6))
    disc(m, "Magnet", V(0.5, FY + 0.72, zf - 0.03), V(0, 0, -1), 0.16, 0.06, (236, 70, 70))
    m.blk("Drawing", (0.4, 0.34, 0.02), (0.6, FY - 0.26, zf - 0.01), WHITE, R=Rz(8))
    m.ball("Drawing", 0.12, (0.5, FY - 0.18, zf - 0.03), (250, 206, 50))
    m.blk("Drawing", (0.34, 0.05, 0.02), (0.61, FY - 0.38, zf - 0.025), (90, 190, 90), R=Rz(8))
    disc(m, "Magnet", V(0.44, FY - 0.08, zf - 0.03), V(0, 0, -1), 0.14, 0.06, (90, 150, 245))
    m.blk("Magnet", (0.16, 0.16, 0.06), (0.84, FY + 0.18, zf - 0.03), ORANGE, R=Rz(12))
    star6(m, "Magnet", V(0.26, FY + 0.12, zf - 0.03), V(0, 0, -1), 0.18, (250, 206, 50), "SmoothPlastic")
    m.ell("Badge", (0.5, 0.14, 0.04), (0, FY + 1.0, zf - 0.02), CHROME, "Metal")
    m.blk("Grille", (1.7, 0.24, 0.04), (0, FY - 1.0, zf - 0.01), GRAPHITE)
    for k in range(4):
        m.blk("Grille", (1.6, 0.03, 0.03), (0, FY - 1.09 + k * 0.06, zf - 0.03), CHROME, "Metal")

    # the freezer head: a frosty top with icicles, a handle, a dark visor with stoic eyes
    m.cyl("Neck", 0.2, 0.9, (0, FY + 1.2, 0), CHROME, "y", "Metal")
    hc = V(0, FY + 1.76, 0.02)
    m.rbox("Head", (1.72, 1.06, 1.4), hc, TEAL, 0.2, axis="z", refl=0.15)
    hz = hc[2] - 0.7
    m.blk("HeadHandle", (0.9, 0.08, 0.1), (0, hc[1] + 0.42, hz - 0.1), CHROME, "Metal")
    for x in (-0.4, 0.4):
        m.blk("HeadHandle", (0.08, 0.08, 0.1), (x, hc[1] + 0.42, hz - 0.03), CHROME, "Metal")
    m.ell("Visor", (1.48, 0.64, 0.1), V(0, hc[1] + 0.07, hz - 0.02), GRAPHITE)
    for s in (-1, 1):
        m.eye(V(s * 0.33, hc[1] + 0.06, hz - 0.05), V(0, 0, -1), 0.34, 0.32, GRAPHITE, STOIC, side=s, iris=ICE_D, brow=CHROME, brow_k=1.1)
    for k in range(3):
        m.blk("Mouth", (0.46 - k * 0.06, 0.045, 0.05), V(0, hc[1] - 0.28 - k * 0.07, hz - 0.03), CHROME, "Metal")
    vg = m.blk("VisorGlow", (0.06, 0.06, 0.03), (0.62, hc[1] - 0.24, hz - 0.02), ICE, "Neon")
    m.light(vg, ICE, 0.8, 5)
    m.ell("Frost", (1.7, 0.2, 1.38), V(0, hc[1] + 0.53, hc[2]), (232, 246, 255))
    for x in (-0.78, -0.62, 0.62, 0.78):
        top = V(x, hc[1] + 0.52, hz - 0.01)
        m.seg("Icicle", top, top + V(0, -0.24 - abs(x) * 0.08, -0.01), 0.05, ICE, "Ice", bulge=0.25, tr=0.1)
    m.crystal("Frost", V(0.42, hc[1] + 0.56, 0.24), (0.25, 1, 0.1), 0.44, 0.16, ICE, "Ice", tr=0.1)
    m.crystal("Frost", V(0.62, hc[1] + 0.55, -0.1), (0.6, 1, -0.2), 0.3, 0.12, ICE, "Ice", tr=0.1)

    # shoulders with big pauldrons
    for s in (-1, 1):
        m.ball("Shoulder", 0.96, V(s * 1.46, FY + 0.82, 0), CHROME, "Metal")
        with m.group(R=Rz(-s * 22), t=V(s * 1.6, FY + 1.14, 0)):
            m.ell("Pauldron", (1.16, 0.56, 1.22), V(0, 0, 0), TEAL, refl=0.15)
            m.ell("Pauldron", (1.22, 0.34, 1.28), V(0, -0.11, 0), CHROME, "Metal")
            for z in (-0.32, 0.32):
                m.ball("PauldronRivet", 0.1, V(s * 0.3, 0.16, z), CHROME, "Metal")

    # left arm (-x): a heavy piston fist
    sh, el, wr = V(-1.46, FY + 0.82, 0), V(-1.78, FY + 0.06, -0.14), V(-1.74, FY - 0.62, -0.42)
    m.seg("UpperArm", sh, el, 0.24, STEEL, "Metal", bulge=0.45, ext=0.05)
    piston(m, sh + V(0, -0.12, -0.24), el + V(0.06, 0.14, -0.24), 0.07)
    m.ball("Elbow", 0.44, el, CHROME, "Metal")
    m.seg("Forearm", el, wr, 0.27, TEAL, bulge=0.6, ext=0.04, refl=0.15)
    d = norm(wr - el)
    disc(m, "ArmPlate", wr - d * 0.04, d, 0.62, 0.1, CHROME, "Metal")
    fc = wr + d * 0.3
    m.ell("Fist", (0.66, 0.62, 0.62), fc, STEEL_D, "Metal")
    for k in range(4):
        m.ball("Knuckle", 0.2, fc + V((k - 1.5) * 0.15, 0.1, -0.28), CHROME, "Metal")
    m.seg("Thumb", fc + V(0.22, 0.0, -0.1), fc + V(0.3, 0.14, -0.28), 0.09, STEEL_D, "Metal", bulge=0.4)

    # right arm (+x): the ice cannon
    sh2, el2 = V(1.46, FY + 0.82, 0), V(1.78, FY + 0.08, -0.08)
    m.seg("UpperArm", sh2, el2, 0.24, STEEL, "Metal", bulge=0.45, ext=0.05)
    piston(m, sh2 + V(0, -0.12, -0.24), el2 + V(-0.06, 0.14, -0.24), 0.07)
    m.ball("Elbow", 0.44, el2, CHROME, "Metal")
    cx, cy = 1.8, el2[1] - 0.02
    m.ell("Cannon", (0.96, 0.96, 0.72), V(cx, cy, -0.12), TEAL, refl=0.15)
    m.seg("Cannon", V(cx, cy, -0.2), V(cx, cy, -1.5), 0.4, GRAPHITE, "Metal", shape="C")
    for z in (-0.55, -0.85, -1.15):
        disc(m, "CannonRing", V(cx, cy, z), V(0, 0, -1), 0.9, 0.1, ICE, "Ice")
    disc(m, "CannonRing", V(cx, cy, -1.46), V(0, 0, -1), 0.96, 0.16, CHROME, "Metal")
    mouth = disc(m, "CannonMouth", V(cx, cy, -1.55), V(0, 0, -1), 0.56, 0.04, ICE, "Neon")
    m.light(mouth, ICE, 1.2, 6)
    m.blk("IceCube", (0.3, 0.3, 0.3), V(cx, cy, -1.62), (220, 244, 255), "Ice", R=rot(20, 30, 0), tr=0.2)
    m.blk("Cannon", (0.4, 0.24, 0.5), V(cx, cy + 0.44, -0.6), TEAL)
    for k in range(3):
        m.blk("IceCube", (0.13, 0.13, 0.13), V(cx - 0.1 + k * 0.1, cy + 0.6, -0.62 + (k % 2) * 0.1), (220, 244, 255), "Ice", R=rot(10, 20 * k, 15), tr=0.15)

    # heavy mech legs
    for s in (-1, 1):
        hip = V(s * 0.62, 1.36, 0.0)
        knee = V(s * 0.68, 0.84, -0.14)
        ank = V(s * 0.68, 0.38, 0.0)
        m.cyl("Hip", 0.5, 0.58, hip, CHROME, "x", "Metal")
        m.seg("Thigh", hip, knee, 0.26, STEEL, "Metal", bulge=0.45, ext=0.05)
        m.ball("Knee", 0.44, knee, CHROME, "Metal")
        m.ell("Kneepad", (0.44, 0.46, 0.26), knee + V(0, 0.02, -0.2), TEAL, refl=0.15)
        m.seg("Shin", knee, ank, 0.25, TEAL, bulge=0.55, ext=0.04, refl=0.15)
        piston(m, knee + V(0, -0.04, 0.24), ank + V(0, 0.08, 0.26), 0.06, name="Greave")
        m.ball("Ankle", 0.36, ank, CHROME, "Metal")
        m.ell("Foot", (0.86, 0.38, 1.26), V(s * 0.68, 0.19, -0.18), GRAPHITE, "Metal")
        m.blk("Sole", (0.8, 0.1, 1.16), V(s * 0.68, 0.05, -0.18), RUBBER, "Rubber")
        for k in (-1, 1):
            m.ell("Toe", (0.3, 0.26, 0.34), V(s * 0.68 + k * 0.2, 0.15, -0.76), CHROME, "Metal")
        m.blk("Heel", (0.4, 0.26, 0.24), V(s * 0.68, 0.16, 0.42), STEEL_D, "Metal")

    # the back: condenser coils, the compressor, the power cord and plug
    zb = 0.8
    m.blk("CoilPanel", (1.7, 1.9, 0.04), (0, FY - 0.05, zb + 0.01), (34, 38, 44))
    for k in range(6):
        m.cyl("Coil", 1.5, 0.07, (0, FY - 0.8 + k * 0.3, zb + 0.07), (22, 22, 26), "x", "Metal")
    for x in (-0.5, 0.5):
        m.blk("CoilWire", (0.03, 1.7, 0.03), (x, FY - 0.05, zb + 0.1), (100, 100, 108), "Metal")
    m.cyl("Compressor", 0.5, 0.56, (0.42, 1.62, zb - 0.06), (30, 30, 36), "x", "Metal")
    cord = [V(-0.3, 1.5, zb + 0.02), V(-0.4, 1.0, zb + 0.24), V(-0.12, 0.5, zb + 0.4), V(0.24, 0.14, zb + 0.5)]
    for i in range(3):
        m.seg("PowerCord", cord[i], cord[i + 1], 0.05, GRAPHITE, "Rubber", shape="C", ext=0.03)
    m.blk("Plug", (0.24, 0.16, 0.26), cord[3] + V(0.06, 0, 0.06), LIGHT)
    return m


@model
def mega_blender_prime():
    """Mega Blender Prime (Legendary): a towering blender mech. A glass jar head full of smoothie
    with a dark mask of glowing angry eyes and a toothy molten grin, a siren lid, a heavy motor body
    with a glowing core, spiked pauldrons, piston arms with pincer claws and piston legs."""
    m = SModel("mega_blender_prime")
    MY = 2.4
    SMOOTHIE = (226, 70, 150)
    SMOOTHIE_L = (250, 150, 200)
    m.rbox("Motor", (2.3, 1.46, 1.9), (0, MY, 0), GRAPHITE, 0.34, "Metal", refl=0.15)
    m.ell("MotorSkirt", (2.5, 0.56, 2.06), (0, MY - 0.66, 0), (34, 36, 42), "Metal")
    m.rbox("MotorTrim", (2.34, 0.12, 1.94), (0, MY + 0.7, 0), CHROME, 0.35, "Metal")
    zf = -0.95
    # the glowing core, buttons, the speed dial, rivets and hazard stripes
    cc = V(0, MY + 0.05, zf)
    disc(m, "CoreRing", cc + V(0, 0, -0.03), V(0, 0, -1), 0.9, 0.1, CHROME, "Metal")
    core = disc(m, "Core", cc + V(0, 0, -0.06), V(0, 0, -1), 0.68, 0.1, ORANGE, "Neon")
    for a in (90, 210, 330):
        m.blk("CoreGrille", (0.3, 0.1, 0.04), cc + Rz(a) @ V(0.16, 0, 0) + V(0, 0, -0.12), GRAPHITE, R=Rz(a + 14))
    disc(m, "CoreGrille", cc + V(0, 0, -0.13), V(0, 0, -1), 0.16, 0.04, CHROME, "Metal")
    m.light(core, ORANGE_L, 1.6, 8)
    for k, c in enumerate((ORANGE, LED, WHITE, (236, 60, 60))):
        disc(m, "Button", V(-0.48 + k * 0.32, MY - 0.5, zf - 0.04), V(0, 0, -1), 0.17, 0.08, c, "Neon")
    disc(m, "SpeedDial", V(0.74, MY + 0.38, zf - 0.04), V(0, 0, -1), 0.32, 0.1, CHROME, "Metal")
    m.blk("DialMark", (0.04, 0.12, 0.03), V(0.78, MY + 0.44, zf - 0.1), ORANGE, "Neon", R=Rz(-30))
    for x in (-0.8, 0.8):
        for y in (MY - 0.5, MY + 0.5):
            if x > 0 and y > MY:
                continue
            disc(m, "Rivet", V(x, y, zf - 0.02), V(0, 0, -1), 0.12, 0.05, CHROME, "Metal")
    ks, kc = (2.5, 0.56, 2.06), V(0, MY - 0.66, 0)
    for k in range(5):
        x = -0.72 + k * 0.36
        p, n = ell_front_at(kc, ks, x, 0.0)
        m.blk("Hazard", (0.12, 0.34, 0.05), p, ORANGE, R=frame_normal(n, -30))

    # the jar head: a chrome collar, glass jar, smoothie with swirls and fruit, measure marks
    m.cyl("JarBase", 0.16, 1.98, (0, MY + 0.8, 0), GRAPHITE, "y", "Metal")
    m.cyl("JarBase", 0.3, 1.86, (0, MY + 0.98, 0), CHROME, "y", "Metal")
    hc = V(0, MY + 2.22, 0)
    m.cyl("Head", 2.2, 1.84, hc, (214, 238, 250), "y", "Glass", tr=0.55, refl=0.3)
    m.cyl("Smoothie", 1.7, 1.72, (0, hc[1] - 0.24, 0), SMOOTHIE, "y")
    for k, y in enumerate((hc[1] - 0.95, hc[1] - 0.7, hc[1] - 0.45)):
        a = 262 + k * 9
        m.ell("Swirl", (0.5, 0.09, 0.04), cpt(0.87, a, y), SMOOTHIE_L, R=tframe(a) @ Rz(20))
    for (a, y, kind) in ((240, hc[1] - 0.82, 0), (300, hc[1] - 0.62, 1), (276, hc[1] - 0.3, 2), (318, hc[1] - 0.98, 3), (226, hc[1] - 0.42, 3)):
        p = cpt(0.87, a, y)
        if kind == 0:
            m.ell("Fruit", (0.22, 0.26, 0.12), p, (230, 40, 60), R=tframe(a))
            m.ell("Fruit", (0.14, 0.06, 0.08), p + V(0, 0.13, 0), (90, 190, 80), R=tframe(a))
        elif kind == 1:
            m.add("C", "Fruit", (0.05, 0.24, 0.24), p, (255, 240, 180), "SmoothPlastic", tframe(a) @ Ry(90))
        elif kind == 2:
            m.add("C", "Fruit", (0.05, 0.22, 0.22), p, (130, 200, 70), "SmoothPlastic", tframe(a) @ Ry(90))
        else:
            m.ball("Fruit", 0.13, p, (60, 70, 170))
    for k in range(3):
        m.blk("Measure", (0.2 + (k % 2) * 0.12, 0.035, 0.03), cpt(0.925, 205, hc[1] - 0.8 + k * 0.32), WHITE, R=tframe(205))
    for y in (hc[1] + 0.62, hc[1] - 0.62):
        m.blk("JarHandle", (0.18, 0.16, 0.44), (0, y, 1.08), GRAPHITE, "Metal")
    m.blk("JarHandle", (0.2, 1.4, 0.2), (0, hc[1], 1.26), GRAPHITE, "Metal")

    # the mask: a dark band round the jar with glowing angry eyes and a molten toothy grin
    my_ = hc[1] + 0.28
    m.cyl("Mask", 0.14, 1.9, (0, my_ + 0.12, 0), GRAPHITE, "y", "Metal")
    for k in range(5):
        a = 270 + (k - 2) * 26
        m.blk("Mask", (0.48, 0.9, 0.08), cpt(0.96, a, my_), GRAPHITE, "Metal", R=tframe(a))
        for y in (my_ + 0.45, my_ - 0.45):
            m.blk("Mask", (0.5, 0.06, 0.11), cpt(0.965, a, y), CHROME, "Metal", R=tframe(a))
    R0 = 1.0
    for s in (-1, 1):
        a = 270 + s * 22
        e = m.eye(cpt(R0, a, my_ + 0.12), cn(a), 0.4, 0.34, GRAPHITE, "menacing", side=s, iris=(255, 90, 30), glow=True, brow=CHROME, brow_k=1.3)
    m.light(len(m.parts), (255, 90, 60), 1.0, 6)
    gy = my_ - 0.24
    for k in range(5):
        a = 270 + (k - 2) * 11
        m.blk("Mouth", (0.2, 0.16, 0.05), cpt(R0 + 0.005, a, gy), (255, 110, 30), "Neon", R=tframe(a))
    for k in range(6):
        a = 270 + (k - 2.5) * 9
        p = cpt(R0 + 0.03, a, gy + 0.05)
        m.seg("Tooth", p + V(0, 0.04, 0), p + V(0, -0.1, 0), 0.05, CHROME, "Metal", r2=0.025, bulge=0.25)
    for k in range(5):
        a = 270 + (k - 2) * 9
        p = cpt(R0 + 0.03, a, gy - 0.06)
        m.seg("Tooth", p + V(0, -0.04, 0), p + V(0, 0.09, 0), 0.045, CHROME, "Metal", r2=0.025, bulge=0.25)
    # the lid with a red siren light
    ly = hc[1] + 1.25
    m.cyl("JarLid", 0.3, 1.98, (0, ly, 0), GRAPHITE, "y", "Metal")
    m.cyl("JarLid", 0.06, 2.02, (0, ly - 0.14, 0), CHROME, "y", "Metal")
    m.cyl("LidCap", 0.24, 0.7, (0, ly + 0.25, 0), STEEL_D, "y", "Metal")
    siren = m.ball("LidCap", 0.46, (0, ly + 0.36, 0), (255, 70, 40), "Neon")
    m.light(siren, (255, 90, 50), 1.2, 7)

    # arms: spiked pauldrons, pistons, heavy forearms and three-pincer claws
    for s in (-1, 1):
        sh = V(s * 1.42, MY + 0.48, 0)
        el = V(s * 1.94, MY - 0.12, -0.34)
        wr = V(s * 1.86, MY - 0.42, -0.98)
        m.ball("Shoulder", 0.9, sh, CHROME, "Metal")
        with m.group(R=Rz(-s * 24), t=sh + V(s * 0.1, 0.38, 0)):
            m.ell("Pauldron", (0.96, 0.5, 1.04), V(0, 0, 0), GRAPHITE, "Metal")
            m.ell("Pauldron", (1.0, 0.2, 1.08), V(0, -0.12, 0), ORANGE)
            for z in (-0.26, 0.26):
                m.seg("Pauldron", V(s * 0.1, 0.12, z), V(s * 0.3, 0.52, z), 0.09, CHROME, "Metal", bulge=0.3)
        m.seg("UpperArm", sh, el, 0.22, STEEL, "Metal", bulge=0.45, ext=0.05)
        piston(m, sh + V(0, -0.2, -0.3), el + V(-s * 0.04, 0.16, -0.24), 0.07)
        m.ball("Elbow", 0.44, el, CHROME, "Metal")
        m.seg("Forearm", el, wr, 0.28, GRAPHITE, "Metal", bulge=0.6, ext=0.04)
        piston(m, el + V(s * 0.2, -0.14, 0.0), wr + V(s * 0.26, 0.0, 0.18), 0.06)
        d = norm(wr - el)
        cl = wr + d * 0.22
        m.ell("Claw", (0.56, 0.48, 0.5), cl, STEEL_D, "Metal")
        for (ox, oy) in ((-0.14, 0.12), (0.14, 0.12), (0.0, -0.16)):
            b0 = cl + V(ox, oy, 0) + d * 0.18
            b1 = b0 + d * 0.3 + V(ox * 0.6, oy * 1.4, 0)
            b2 = b1 + d * 0.22 + V(0, -oy * 0.9, 0)
            m.seg("Pincer", b0, b1, 0.07, CHROME, "Metal", bulge=0.45, ext=0.03)
            m.seg("Pincer", b1, b2, 0.055, ORANGE, bulge=0.35, ext=0.02)

    # piston legs on big clawed feet
    for s in (-1, 1):
        hip = V(s * 0.74, 1.66, 0.04)
        knee = V(s * 0.82, 1.0, -0.16)
        ank = V(s * 0.82, 0.42, 0.02)
        m.cyl("Hip", 0.56, 0.62, hip, CHROME, "x", "Metal")
        m.seg("Thigh", hip, knee, 0.28, STEEL, "Metal", bulge=0.45, ext=0.05)
        m.seg("Greave", hip + V(s * 0.3, -0.06, -0.06), knee + V(s * 0.3, 0.1, -0.02), 0.06, CHROME, "Metal", shape="C")
        m.ball("Knee", 0.46, knee, CHROME, "Metal")
        m.ell("Kneepad", (0.46, 0.5, 0.26), knee + V(0, 0.02, -0.22), ORANGE)
        m.seg("Shin", knee, ank, 0.27, GRAPHITE, "Metal", bulge=0.55, ext=0.04)
        m.ball("Ankle", 0.4, ank, CHROME, "Metal")
        m.ell("Foot", (0.96, 0.4, 1.38), V(s * 0.82, 0.2, -0.22), GRAPHITE, "Metal")
        m.blk("Sole", (0.9, 0.1, 1.28), V(s * 0.82, 0.05, -0.22), RUBBER, "Rubber")
        for k in (-1, 0, 1):
            m.seg("Toe", V(s * 0.82 + k * 0.26, 0.2, -0.7), V(s * 0.82 + k * 0.3, 0.08, -1.02), 0.09, CHROME, "Metal", bulge=0.35)
        m.blk("Heel", (0.36, 0.3, 0.3), V(s * 0.82, 0.18, 0.46), STEEL_D, "Metal")

    # the back: vents, exhaust stacks with smoke, the power cord and plug
    zb = 0.95
    for k in range(3):
        m.blk("Vent", (1.3, 0.08, 0.04), (0, MY + 0.3 - k * 0.2, zb + 0.01), (24, 26, 30))
    for s in (-1, 1):
        ex = m.cyl("Exhaust", 0.6, 0.22, (s * 0.7, MY + 0.86, 0.72), STEEL_D, "y", "Metal")
        m.cyl("Exhaust", 0.08, 0.28, (s * 0.7, MY + 1.18, 0.72), CHROME, "y", "Metal")
        m.smoke(ex, (180, 180, 190), 0.08, 0.5, 0.8)
    cord = [V(0.4, MY - 0.4, zb), V(0.6, 1.2, zb + 0.3), V(0.3, 0.5, zb + 0.5), V(-0.1, 0.14, zb + 0.6)]
    for i in range(3):
        m.seg("PowerCord", cord[i], cord[i + 1], 0.06, GRAPHITE, "Rubber", shape="C", ext=0.03)
    m.blk("Plug", (0.26, 0.18, 0.3), cord[3] + V(-0.08, 0, 0.04), LIGHT)
    return m


@model
def omega_microwave():
    """Omega Microwave (Secret): an all-powerful gold-foil microwave. A cosmic portal window with a
    swirling galaxy and a glowing regal face, a jewelled crown, a satellite dish, two orbit rings,
    gold armour with gems, a cosmic orb in one raised hand and a royal purple cape with an omega."""
    m = SModel("omega_microwave")
    BY = 2.35
    OG = (246, 196, 72)
    OG_D = (184, 138, 48)
    OG_L = (255, 226, 140)
    PURP = (150, 70, 236)
    PURP_L = (204, 140, 255)
    PURP_D = (84, 34, 140)
    SPACE = (26, 12, 54)
    m.rbox("Body", (3.0, 2.0, 2.0), (0, BY, 0), OG, 0.32, "Foil", axis="z", refl=0.25)
    zf = -1.0
    for y in (BY - 0.72, BY + 0.72):
        m.blk("Trim", (2.4, 0.12, 2.04), (0, y, 0), OG_D, "Metal")
    for x in (-1.24, 1.24):
        for y in (BY - 0.8, BY + 0.8):
            disc(m, "Gem", V(x, y, zf - 0.02), V(0, 0, -1), 0.3, 0.06, OG_D, "Metal")
            m.ell("Gem", (0.2, 0.2, 0.12), V(x, y, zf - 0.07), PURP, "Neon")
    # the cosmic portal window: an ornate gold frame, deep space, a galaxy swirl and stars
    wc = V(-0.36, BY + 0.02, zf)
    disc(m, "WindowFrame", wc + V(0, 0, -0.04), V(0, 0, -1), 1.8, 0.1, OG_D, "Metal", refl=0.2)
    for k in range(8):
        a = math.radians(k * 45 + 22.5)
        m.ball("WindowFrame", 0.12, wc + V(math.cos(a) * 0.83, math.sin(a) * 0.83, -0.1), OG_L, "Metal")
    win = disc(m, "Window", wc + V(0, 0, -0.09), V(0, 0, -1), 1.5, 0.04, SPACE)
    m.light(win, PURP_L, 2.0, 10)
    # a small spiral galaxy tucked in the lower left and a ringed planet in the lower right,
    # kept clear of the face so they read as scenery, not features
    gc = wc + V(-0.45, -0.3, -0.115)
    for k, c in enumerate(((150, 80, 220), (196, 92, 196), (96, 120, 220))):
        a = k * 120 + 15
        m.ell("Swirl", (0.2, 0.05, 0.02), gc + Rz(a) @ V(0.08, 0, 0), c, R=Rz(a + 55))
    m.ball("Swirl", 0.06, gc + V(0, 0, -0.005), PURP_L, "Neon")
    pc = wc + V(0.47, -0.3, -0.12)
    m.ball("Planet", 0.09, pc, (255, 150, 110))
    m.ell("Planet", (0.3, 0.04, 0.02), pc + V(0, 0, -0.01), OG_L, R=Rz(-18))
    for (x, y) in ((-0.58, 0.3), (0.6, 0.3), (0.0, 0.6), (0.64, -0.02), (-0.66, -0.04), (0.18, -0.6), (-0.2, -0.62)):
        m.ball("Star", 0.04, wc + V(x, y, -0.12), WHITE, "Neon")
    # the face in the portal: glowing regal eyes and a knowing smirk
    for s in (-1, 1):
        m.eye(wc + V(s * 0.3, 0.24, -0.14), V(0, 0, -1), 0.32, 0.26, SPACE, ALMIGHTY, side=s, iris=PURP, glow=True, brow=OG, brow_k=1.1)
    m.mouth(wc + V(0, -0.34, -0.13), V(0, 0, -1), 0.4, ALMIGHTY, color=(250, 220, 255))
    # the keypad
    kx = 1.04
    m.blk("Keypad", (0.66, 1.2, 0.06), (kx, BY, zf - 0.02), OG_D, "Metal")
    m.blk("Timer", (0.5, 0.2, 0.04), (kx, BY + 0.42, zf - 0.06), (255, 70, 90), "Neon")
    for r in range(3):
        for c in range(3):
            m.blk("Key", (0.14, 0.12, 0.04), (kx - 0.18 + c * 0.18, BY + 0.14 - r * 0.17, zf - 0.06), OG_L, "Neon")
    m.blk("StartButton", (0.46, 0.12, 0.04), (kx, BY - 0.44, zf - 0.06), PURP, "Neon")
    # gold filigree scrolls on the sides and vents on the back
    for s in (-1, 1):
        disc(m, "Trim", V(s * 1.5, BY, 0.0), V(1, 0, 0), 0.7, 0.06, OG_D, "Metal")
        m.ell("Trim", (0.08, 0.3, 0.3), V(s * 1.53, BY, 0.0), PURP, "Neon")
    for k in range(4):
        m.blk("Vent", (1.4, 0.07, 0.04), (0, BY + 0.45 - k * 0.15, -zf + 0.01), OG_D, "Metal")

    # the crown on the top front edge
    top = BY + 1.0
    m.blk("CrownBand", (2.3, 0.2, 0.14), (0, top + 0.08, zf + 0.12), OG_D, "Metal")
    for k in range(5):
        x = -0.9 + k * 0.45
        hgt = 0.46 if k == 2 else (0.36 if k % 2 == 0 else 0.26)
        m.seg("Crown", V(x, top + 0.12, zf + 0.12), V(x, top + 0.12 + hgt, zf + 0.12), 0.11, OG, "Foil", r2=0.06, bulge=0.3)
        m.ball("CrownGem", 0.16 if k == 2 else 0.11, V(x, top + 0.1, zf + 0.04), (255, 90, 160) if k == 2 else PURP, "Neon")
    # the satellite dish
    dp = V(0.62, top, 0.36)
    m.seg("DishPole", dp - V(0, 0.05, 0), dp + V(0, 0.46, 0), 0.07, CHROME, "Metal", shape="C")
    with m.group(R=Ry(-25) @ Rx(-35), t=dp + V(0, 0.6, 0)):
        m.ell("Dish", (1.3, 0.26, 1.3), V(0, 0, 0), OG_L, "Metal", refl=0.2)
        m.ell("Dish", (1.12, 0.12, 1.12), V(0, 0.08, 0), (250, 246, 236), "Metal")
        for k in range(3):
            a = math.radians(k * 120 + 90)
            m.seg("DishArm", V(math.cos(a) * 0.52, 0.12, math.sin(a) * 0.52), V(0, 0.62, 0), 0.025, CHROME, "Metal", shape="C")
        feed = m.ball("DishFeed", 0.18, V(0, 0.66, 0), PURP, "Neon")
    m.light(feed, PURP_L, 1.0, 6)
    # two floating orbit rings
    m.ring("HaloRing", (0, BY - 0.45, 0), 2.62, 0.1, OG_L, normal="y", segments=20, mat="Neon", R=rot(x=-12, z=6))
    m.ring("HaloRing", (0, BY - 0.6, 0), 2.3, 0.08, PURP_L, normal="y", segments=18, mat="Neon", R=rot(x=-8, z=-12))

    # gold arms: gem pauldrons, bracers; a cosmic orb raised in one hand, the other a fist
    for s in (-1, 1):
        sh = V(s * 1.56, BY + 0.5, 0)
        m.ball("Shoulder", 0.84, sh, OG_D, "Metal")
        with m.group(R=Rz(-s * 22), t=sh + V(s * 0.1, 0.36, 0)):
            m.ell("Pauldron", (1.0, 0.5, 1.1), V(0, 0, 0), OG, "Foil", refl=0.25)
            m.ell("Pauldron", (1.06, 0.22, 1.16), V(0, -0.12, 0), OG_D, "Metal")
            m.ell("PauldronGem", (0.24, 0.12, 0.24), V(s * 0.06, 0.24, 0), PURP, "Neon")

    def gold_arm(s, el, wr):
        sh = V(s * 1.56, BY + 0.5, 0)
        m.seg("UpperArm", sh, el, 0.24, OG_D, "Metal", bulge=0.45, ext=0.05)
        m.ball("Elbow", 0.44, el, OG, "Foil")
        m.seg("Forearm", el, wr, 0.27, OG, "Foil", bulge=0.6, ext=0.04)
        d = norm(wr - el)
        bp = el + (wr - el) * 0.55
        disc(m, "Bracer", bp, d, 0.64, 0.16, OG_D, "Metal")
        side = norm(np.cross(d, V(0, 1, 0)))
        m.ell("Bracer", (0.16, 0.16, 0.1), bp - V(0, 0, 0.3) + side * 0.0, PURP, "Neon")
        return d

    el, wr = V(1.98, BY + 0.1, -0.22), V(1.98, BY + 0.72, -0.62)
    d = gold_arm(1, el, wr)
    hc = wr + d * 0.2
    m.glove(hc, 0.24, OG_D, 1, fist=False, fingers=3, mat="Metal", forward=(0, 0.3, -1))
    oc = hc + V(0, 0.58, -0.1)
    orb = m.ball("Orb", 0.52, oc, (210, 150, 255), "Neon")
    m.ring("Orb", oc, 0.42, 0.05, OG_L, normal="y", segments=8, mat="Neon", R=rot(x=20, z=15))
    m.light(orb, PURP_L, 1.6, 8)
    m.sparkles(orb, (230, 200, 255))
    el2, wr2 = V(-1.98, BY - 0.1, -0.16), V(-1.92, BY - 0.56, -0.6)
    d2 = gold_arm(-1, el2, wr2)
    m.glove(wr2 + d2 * 0.2, 0.25, OG_D, -1, fist=True, mat="Metal", forward=(0, 0, -1))

    # gold legs, knee guards with gems, big boots with purple spats
    m.legs2(BY - 0.98, 0.86, OG_D, 0.3, 0.28, 0.26, 0.8, 1.12, OG, sole=(60, 40, 20), toe=OG_L, cuff=PURP, knee_color=OG, mat="Metal")
    for s in (-1, 1):
        kn = V(s * 0.89, (BY - 0.98 + 0.8 * 0.62) / 2 + 0.03, -0.07)
        m.ell("Kneepad", (0.5, 0.52, 0.28), kn + V(0, 0.02, -0.26), OG, "Foil", refl=0.25)
        m.ell("Kneepad", (0.14, 0.14, 0.08), kn + V(0, 0.04, -0.4), PURP, "Neon")

    # the royal cape with a gold hem, clasps and an omega on the back
    cz, cy = 1.12, BY - 0.25
    CR = rot(x=-7)
    cs = (2.7, 2.7, 0.16)
    m.ell("Cape", cs, V(0, cy, cz), PURP_D, "Fabric", R=CR)

    def cape_back(x, y):
        """A point on the cape's back surface at (x, y), lifted a little off it."""
        dy = y - cy
        q = max(1 - (x / 1.35) ** 2 - (dy / 1.35) ** 2, 0.0)
        # the cape leans back (rot x -7): its back face sits further back the lower it goes
        return V(x, y, cz + 0.08 * math.sqrt(q) - 0.122 * dy + 0.02)

    for x in (-0.62, 0.0, 0.62):
        p = cape_back(x, cy - 0.2)
        m.ell("CapeFold", (0.16, 1.7, 0.06), p, shade(PURP_D, 0.75), "Fabric", R=CR)
    for k in range(5):
        a = math.radians(-58 + k * 29)
        p = V(math.sin(a) * 1.18, cy - math.cos(a) * 1.18, 0)
        p = cape_back(p[0], p[1])
        m.blk("CapeTrim", (0.52, 0.12, 0.06), p, OG, "Foil", R=CR @ Rz(math.degrees(a)))
    for s in (-1, 1):
        m.cyl("Clasp", 0.08, 0.3, (s * 1.0, BY + 0.86, 1.06), OG, "z", "Metal")
    oc_ = V(0, cy + 0.42, 0)
    pts = []
    # the omega: an arc open at the bottom (measured from the top), with a foot turning out at each end
    for k in range(7):
        a = math.radians(-140 + k * (280 / 6))
        x, y = math.sin(a) * 0.3, oc_[1] + math.cos(a) * 0.3
        pts.append(cape_back(x, y))
    for i in range(6):
        m.seg("Omega", pts[i], pts[i + 1], 0.045, OG, "Foil", shape="C", ext=0.03)
    for (p, sgn) in ((pts[0], -1), (pts[-1], 1)):
        m.seg("Omega", p, cape_back(p[0] + sgn * 0.15, p[1] - 0.02), 0.045, OG, "Foil", shape="C", ext=0.03)
    return m
