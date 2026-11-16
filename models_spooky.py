# Spooky family: friendly-creepy haunts with a sense of humour.
# Palette: ghost lilac (main), midnight purple (secondary), ecto green glow (accent), with bone and a
# little pumpkin orange. Materials: fabric sheets and robes, slate and marble, glass, a few glows.
import math
import random
import numpy as np
from modelkit import rot, Rx, Ry, Rz, shade, I3, WHITE, frame_normal, frame_from_x, on_ell
from stylekit import SModel, PAL, V, norm, on_ell_R, INK, GOLD, SILVER

MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


P = PAL["Spooky"]
LILAC = P["main"]
MIDNIGHT = P["second"]
ECTO = P["accent"]
SHADOWP = P["shadow"]
BONE = P["bone"]
PUMPKIN = P["orange"]
SHEET = (242, 238, 255)
PURPLE = (124, 76, 196)
PURPLE_L = (170, 124, 236)
PURPLE_D = (56, 34, 92)
ECTO_D = (44, 176, 112)
ECTO_F = (96, 214, 140)  # fabric green for trims
BONE_D = (204, 192, 170)
INKP = (42, 26, 58)
BLUSH_S = (255, 170, 208)
GHOST = (206, 222, 255)  # see-through phantom blue-lilac
STEEL = (170, 176, 188)
CANDY_PINK = (246, 120, 170)

# moods only this family uses
HUNGRY = dict(open=0.62, lid=12, brow=16, lift=0.08, mouth="teeth", curve=0.3, look=(0.18, -0.05))
WITCHY = dict(open=0.58, lid=8, brow=14, lift=0.14, mouth="smirk", curve=0.26, look=(-0.16, 0.02))
SUSPICIOUS = dict(open=0.78, lid=10, brow=18, lift=0.04, mouth="frown", curve=-0.1, look=(0.16, 0))
SINISTER = dict(open=0.48, lid=-6, brow=-12, lift=0.32, mouth="smirk", curve=0.2, look=(0.06, 0))
SHY_OPEN = dict(open=1.0, lid=0, brow=-14, lift=0.28, mouth="small", curve=0.22, look=(0.04, -0.24))


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


def ell_front_at(c, size, X, Y, R=I3):
    """Surface point (and normal) on the front (-z) of an ellipsoid at local offsets X, Y."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    u, v = X / hx, Y / hy
    w = -math.sqrt(max(1 - u * u - v * v, 0.02))
    return on_ell_R(c, size, R, np.array(R, float) @ V(X, Y, hz * w))


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


def ball_cluster(m, name, c, r, n, d, colors, mat="Fabric", seed=0):
    """Balls spread evenly over a sphere (pom-poms, puffs): a golden spiral, colours taking turns."""
    for k in range(n):
        y = 1 - 2 * (k + 0.5) / n
        rr = math.sqrt(max(0.0, 1 - y * y))
        th = math.pi * (3 - math.sqrt(5)) * (k + seed)
        v = V(math.cos(th) * rr, y, math.sin(th) * rr)
        m.ball(name, d, c + v * r, colors[k % len(colors)], mat)


def flap(m, name, a, b, w, t, color, side, mat="SmoothPlastic", bulge=0.5, tr=0.0):
    """A flat ellipsoid from a to b (a rag, a tatter, a collar point): w wide along `side`, t thick.
    bulge < 0.5 puts the widest part near a and tapers it to a point at b."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    v = b - a
    L = float(np.linalg.norm(v))
    d = v / L
    sd = np.asarray(side, float)
    sd = sd - d * float(sd @ d)
    sd = sd / np.linalg.norm(sd)
    F = np.column_stack([d, sd, np.cross(d, sd)])
    half = max(bulge, 1 - bulge) * L
    return m.add("E", name, (2 * half, w, t), a + v * bulge, color, mat, F, tr)


# ------------------------------------------------------------------------------------------------
def sheet_body(m, s=1.0, color=SHEET, tr=0.0, lift=0.35, detail=True, iris=PURPLE_L):
    """A bedsheet ghost: a round top, a flared skirt with a rippled hem of long and short lobes,
    soft folds, little arms under the sheet (hands held shyly together), big shy eyes, rosy cheeks
    and a twisted curl of sheet on top. Built at size 1, then scaled by s and lifted off the floor."""
    fold = shade(color, 0.88)
    bc, bs = V(0, 1.45, 0), (1.7, 2.4, 1.58)
    sc, ss = V(0, 0.6, 0.04), (2.04, 1.1, 1.92)
    with m.group(t=(0, lift, 0), scale=s):
        m.ell("Body", bs, bc, color, tr=tr)
        m.ell("Skirt", ss, sc, color, tr=tr)
        # the dark hollow under the sheet, seen between the hem lobes
        m.ell("Under", (1.66, 0.1, 1.56), V(0, 0.1, 0.04), PURPLE_D)
        for k in range(12):
            a = k * 30 + 15
            lg = k % 2 == 0
            t = math.radians(a)
            p = V(math.cos(t) * 0.92, 0.2 if lg else 0.3, 0.04 + math.sin(t) * 0.87)
            m.ell("Hem", (0.6, 0.66, 0.24) if lg else (0.52, 0.5, 0.22), p, color if lg else shade(color, 0.94), R=tframe(a) @ Rx(15), tr=tr)
        for a in (180, 210, 240, 270, 300, 330, 0):
            t = math.radians(a)
            p, n = on_ell(sc, ss, (math.cos(t), -0.2, math.sin(t)))
            m.ell("Fold", (0.09, 0.5, 0.07), p, fold, R=frame_normal(n), tr=tr)
        # little arms under the sheet, hands held together in front (shy)
        for sd in (-1, 1):
            sh = V(sd * 0.6, 1.36, -0.34)
            wr = V(sd * 0.3, 1.08, -0.82)
            m.seg("Arm", sh, wr, 0.21, color, bulge=0.45, tr=tr)
            m.ell("Hand", (0.34, 0.3, 0.3), V(sd * 0.21, 1.06, -0.9), color, tr=tr)
        # the face
        for p in m.eyes_on(bc, bs, I3, 21, 30, 0.36, 0.48, color, SHY_OPEN, iris=iris, lid_color=color, pupil_k=0.62):
            q, n = on_ell_R(bc, bs, I3, p - bc)
            m.ell("EyeRim", (0.42, 0.54, 0.12), q - n * 0.005, shade(SHADOWP, 0.82), R=frame_normal(n))
        for sd in (-1, 1):
            p, n = on_ell_R(bc, bs, I3, Ry(sd * 36) @ Rx(15) @ V(0, 0, -1))
            m.ell("Cheek", (0.26, 0.15, 0.06), p + n * 0.012, BLUSH_S, R=frame_normal(n))
        p, n = on_ell_R(bc, bs, I3, Rx(9) @ V(0, 0, -1))
        m.mouth(p + n * 0.01, n, 0.34, "shy", color=INKP)
        # a twisted curl of sheet on top
        top = V(0, 2.6, 0.02)
        m.seg("Curl", top, top + V(0.03, 0.22, 0.08), 0.1, color, bulge=0.4, tr=tr)
        m.seg("Curl", top + V(0.03, 0.2, 0.08), top + V(-0.02, 0.24, 0.28), 0.07, color, bulge=0.5, tr=tr)
        m.ball("Curl", 0.11, top + V(-0.03, 0.18, 0.32), color, tr=tr)
        if detail:
            # the back: a laundry care tag and a sewn-on patch
            p, n = on_ell(bc, bs, (0, 0.5, 1))
            F = frame_normal(n)
            m.blk("CareTag", (0.34, 0.26, 0.03), p + n * 0.015, WHITE, R=F)
            for k in range(3):
                m.blk("CareText", (0.22 - k * 0.04, 0.03, 0.02), p + n * 0.035 + F[:, 1] * (0.07 - k * 0.07), (110, 130, 214), R=F)
            p, n = on_ell(bc, bs, (0.55, -0.35, 1))
            F = frame_normal(n, 16)
            m.ell("Patch", (0.46, 0.42, 0.05), p, (198, 214, 255), "Fabric", R=F)
            for k in range(4):
                a = math.radians(k * 90 + 45)
                q = p + n * 0.025 + F[:, 0] * math.cos(a) * 0.17 + F[:, 1] * math.sin(a) * 0.15
                m.blk("Stitch", (0.08, 0.025, 0.02), q, (120, 130, 210), R=F @ Rz(k * 90 + 135))


@model
def sheet_ghost():
    """Common. A bedsheet ghost with a rippled hem, little arms under the sheet held shyly
    together, big lilac eyes looking down, rosy cheeks, a curl of sheet on top, and on the back a
    care tag and a sewn-on patch. Green ecto wisps. Mood: shy."""
    m = SModel("sheet_ghost")
    sheet_body(m)
    g = m.ball("Glow", 0.2, V(0, 1.85, 0), (200, 180, 255), tr=1)
    m.light(g, (190, 170, 255), 1.0, 7)
    m.cyl("Shadow", 0.04, 1.7, V(0, 0.02, 0.04), (40, 28, 64), "y", tr=0.55)
    for (x, y, z, d, c) in ((-1.1, 2.0, 0.42, 0.2, ECTO), (-0.95, 2.42, 0.62, 0.12, ECTO), (1.08, 1.38, 0.56, 0.17, LILAC),
                            (0.92, 2.62, 0.36, 0.11, ECTO), (0.1, 0.62, 1.18, 0.15, LILAC)):
        m.ball("Wisp", d, V(x, y, z), c, "Neon", tr=0.45)
    return m


@model
def ghost_token():
    """Token. A smaller, see-through blue sheet ghost floating higher."""
    m = SModel("ghost", kind="token")
    sheet_body(m, 0.85, color=GHOST, tr=0.18, lift=0.5, detail=False, iris=(120, 170, 255))
    g = m.ball("Glow", 0.2, V(0, 1.75, 0), (200, 220, 255), tr=1)
    m.light(g, (170, 200, 255), 0.8, 6)
    for (x, y, z, d) in ((-0.95, 1.9, 0.4, 0.16), (0.9, 1.3, 0.5, 0.14), (0.2, 0.7, 1.0, 0.13)):
        m.ball("Wisp", d, V(x, y, z), ECTO, "Neon", tr=0.5)
    return m


# ------------------------------------------------------------------------------------------------
@model
def skeleton_mascot():
    """Common. A goofy skeleton cheering for the Spooky team: a big round mascot skull with a green
    sweatband, a crack, cross-eyed eyes in dark sockets, a toothy grin with the tongue out; a purple
    jersey with a white 13 and green trim, baggy shorts, knobbly bone limbs, striped socks, chunky
    high-tops and a purple-and-green pom-pom in each bony hand (one waving high). Mood: goofy."""
    m = SModel("skeleton_mascot")
    jersey = PURPLE
    jersey_d = shade(PURPLE, 0.78)
    trim = ECTO_F
    # legs: bones with knobbly knees, striped socks and chunky high-tops
    for s in (-1, 1):
        hip, knee, ankle = V(s * 0.3, 1.5, 0.02), V(s * 0.33, 0.98, -0.08), V(s * 0.33, 0.5, 0.0)
        m.seg("Thigh", hip, knee, 0.085, BONE, bulge=0.5, ext=0.04)
        for dx in (-0.05, 0.05):
            m.ball("Knee", 0.19, knee + V(dx, 0.02, 0.0), BONE)
        m.ball("Knee", 0.14, knee + V(0, 0.0, -0.08), BONE_D)
        m.seg("Shin", knee, ankle, 0.072, BONE, bulge=0.5)
        m.cyl("Sock", 0.36, 0.27, V(s * 0.33, 0.62, 0.0), WHITE, "y", "Fabric")
        for y in (0.68, 0.75):
            m.cyl("Sock", 0.04, 0.28, V(s * 0.33, y, 0.0), jersey, "y", "Fabric")
        # a chunky high-top: rounded white sole, purple upper, white toe cap, green laces and stripe
        fx, fz = s * 0.34, -0.12
        m.rbox("Sole", (0.66, 0.14, 1.0), V(fx, 0.07, fz), (244, 244, 248), 0.22, mat="Rubber", axis="y")
        uc, us = V(fx, 0.34, fz + 0.04), (0.6, 0.52, 0.9)
        m.ell("Shoe", us, uc, jersey)
        m.ell("Toe", (0.54, 0.34, 0.42), V(fx, 0.24, fz - 0.26), (244, 244, 248))
        m.ell("Shoe", (0.08, 0.16, 0.5), V(fx + s * 0.29, 0.3, fz + 0.06), trim, R=rot(x=12))
        for k, Y in enumerate((0.1, 0.0)):
            p, n = ell_front_at(uc, us, 0.0, Y + 0.12)
            m.blk("Laces", (0.28, 0.035, 0.07), p + n * 0.01, trim, R=frame_normal(n))
    # baggy shorts with a green side stripe
    m.ell("Shorts", (1.2, 0.46, 0.76), V(0, 1.78, 0.02), jersey_d, "Fabric")
    for s in (-1, 1):
        m.ell("Shorts", (0.62, 0.56, 0.66), V(s * 0.29, 1.56, 0.02), jersey_d, "Fabric", R=rot(z=s * 6))
        m.ell("Stripe", (0.05, 0.5, 0.22), V(s * 0.6, 1.6, 0.02), trim, "Fabric", R=rot(z=s * 6))
    # the jersey: a roomy top, green hem, V-neck and sleeve trim, a white 13 outlined in green
    tc, ts = V(0, 2.42, 0.0), (1.44, 1.2, 0.82)
    m.ell("Torso", ts, tc, jersey, "Fabric")
    m.ell("Torso", (1.26, 0.62, 0.76), V(0, 1.98, 0.01), jersey, "Fabric")
    m.ell("JerseyHem", (1.3, 0.12, 0.8), V(0, 1.72, 0.01), trim, "Fabric")
    m.ell("NeckHole", (0.48, 0.08, 0.36), V(0, 3.0, -0.02), INKP)
    for sd in (-1, 1):
        a, na = ell_front_at(tc, ts, sd * 0.3, 0.54)
        b, nb = ell_front_at(tc, ts, 0.0, 0.36)
        m.seg("Collar", a + na * 0.02, b + nb * 0.02, 0.045, trim, bulge=0.5, ext=0.03)

    def digit_block(X, Y, w, h, rz=0.0, color=WHITE, lift=0.014, grow=0.0):
        p, n = ell_front_at(tc, ts, X, Y)
        m.blk("Number", (w + grow, h + grow, 0.04), p + n * lift, color, "Fabric", R=frame_normal(n) @ Rz(rz))

    # (the viewer's left is +x: the "1" sits at +x, the "3" at -x)
    strokes = [(0.15, -0.06, 0.08, 0.44, 0), (0.2, 0.1, 0.13, 0.07, 45),
               (-0.13, 0.13, 0.22, 0.07, 0), (-0.15, -0.06, 0.16, 0.07, 0), (-0.13, -0.25, 0.22, 0.07, 0), (-0.205, -0.06, 0.07, 0.44, 0)]
    for (X, Y, w, h, rz) in strokes:
        digit_block(X, Y, w, h, rz, trim, lift=0.004, grow=0.05)
        digit_block(X, Y, w, h, rz)
    # the neck
    m.seg("Neck", V(0, 2.88, 0.0), V(0, 3.12, 0.0), 0.09, BONE_D, bulge=0.5)
    # the big mascot skull
    hc, hs = V(0, 3.52, 0.02), (1.46, 1.24, 1.36)
    fc, fs = V(0, 3.24, -0.12), (1.22, 0.86, 1.1)
    m.ell("Skull", hs, hc, BONE)
    m.ell("Skull", fs, fc, BONE)
    m.ell("Jaw", (0.96, 0.34, 0.84), V(0, 2.9, -0.16), BONE)
    for sd in (-1, 1):
        p, n = on_ell_R(fc, fs, I3, Ry(sd * 52) @ Rx(-6) @ V(0, 0, -1))
        m.ell("Cheek", (0.36, 0.24, 0.12), p, BONE)
    # eyes in dark sockets, crossed
    for sd in (-1, 1):
        p, n = on_ell_R(hc, hs, I3, Ry(sd * 22) @ Rx(-2) @ V(0, 0, -1))
        m.ell("Socket", (0.5, 0.56, 0.2), p - n * 0.03, INKP, R=frame_normal(n))
        m.eye(p + n * 0.02, n, 0.38, 0.42, BONE, "goofy", side=sd, iris=ECTO_D, brow=BONE_D, brow_k=1.25, lid_color=BONE, pupil_k=0.5)
    # nose hole: an upside-down heart
    p, n = on_ell_R(fc, fs, I3, Rx(12) @ V(0, 0, -1))
    for sd in (-1, 1):
        m.ell("NoseHole", (0.1, 0.17, 0.06), p + V(sd * 0.05, 0, 0), INKP, R=frame_normal(n) @ Rz(sd * 22))
    # a big toothy grin, and the tongue hanging out of one corner
    p, n = on_ell_R(fc, fs, I3, Rx(-26) @ V(0, 0, -1))
    m.ell("Mouth", (0.86, 0.26, 0.16), p - n * 0.02, INKP, R=frame_normal(n))
    for k in range(6):
        yaw = (k - 2.5) * 13
        q, nq = on_ell_R(fc, fs, I3, Ry(yaw) @ Rx(-24 + abs(k - 2.5) * 2.4) @ V(0, 0, -1))
        m.blk("Teeth", (0.11, 0.16, 0.07), q + nq * 0.01, WHITE, R=frame_normal(nq))
    q, nq = on_ell_R(fc, fs, I3, Ry(-20) @ Rx(-36) @ V(0, 0, -1))
    m.ell("Tongue", (0.2, 0.08, 0.32), q + nq * 0.05 + V(0, -0.06, 0), CANDY_PINK, R=frame_normal(nq) @ Rx(-55))
    # a sweatband and a crack
    eband(m, "Headband", hc + V(0, 0.46, 0), 0.5, 0.47, 0.07, trim, n=12, h=0.15)
    p, n = on_ell_R(hc, hs, I3, Ry(-40) @ Rx(38) @ V(0, 0, -1))
    m.seg("Crack", p, p + V(0.1, -0.16, -0.02), 0.022, BONE_D, bulge=0.5)
    m.seg("Crack", p + V(0.1, -0.16, -0.02), p + V(0.06, -0.3, -0.05), 0.018, BONE_D, bulge=0.5)
    # bony arms: one pom-pom waving high, one down at the hip
    poses = {1: (V(1.04, 3.12, -0.1), V(1.16, 3.56, -0.16)), -1: (V(-0.98, 2.26, -0.12), V(-1.08, 1.82, -0.2))}
    for s, (el, wr) in poses.items():
        sh = V(s * 0.72, 2.72, 0.0)
        up = norm(el - sh)
        m.ell("Sleeve", (0.52, 0.5, 0.56), V(s * 0.7, 2.7, 0.0), jersey, "Fabric")
        m.seg("Cuff", sh + up * 0.17, sh + up * 0.25, 0.17, trim, "Fabric", shape="C")
        m.seg("UpperArm", sh, el, 0.075, BONE, bulge=0.5, ext=0.03)
        m.ball("Elbow", 0.18, el, BONE)
        d = norm(wr - el)
        side = norm(np.cross(d, V(0, 0, 1)))
        for o in (-0.035, 0.035):
            m.seg("Forearm", el + side * o, wr + side * o, 0.042, BONE, bulge=0.5)
        hp = wr + d * 0.1
        m.ell("Hand", (0.22, 0.2, 0.16), hp, BONE, R=frame_from_x(d))
        for k in range(3):
            m.ball("Finger", 0.085, hp + d * 0.1 + side * (k - 1) * 0.06 + V(0, 0, -0.08), BONE)
        m.ball("Thumb", 0.08, hp + d * 0.06 + V(0, 0, 0.09), BONE)
        pc = wr + d * 0.42
        m.ball("PomPom", 0.4, pc, jersey, "Fabric")
        cols = (jersey, trim, PURPLE_L)
        for k in range(11):
            y = 1 - 2 * (k + 0.5) / 11
            rr = math.sqrt(max(0.0, 1 - y * y))
            th = math.pi * (3 - math.sqrt(5)) * (k + s + 2)
            v = V(math.cos(th) * rr, y, math.sin(th) * rr)
            m.seg("PomPom", pc + v * 0.08, pc + v * 0.31, 0.085, cols[k % 3], "Fabric", bulge=0.5)
    return m


# ------------------------------------------------------------------------------------------------
@model
def haunted_vending_machine():
    """Rare. A midnight-purple vending machine with a hungry, sly face on its LED header, a
    green-lit window of snacks on three shelves, a keypad and coin slot, a pickup slot grinning with
    fangs and a candy-pink tongue, see-through ghost arms reaching out of its sides (one clutching a
    candy bar) and green slime drips. Mood: hungry and sly."""
    m = SModel("haunted_vending_machine")
    body = MIDNIGHT
    edge = shade(MIDNIGHT, 1.28)
    W, H, D = 2.1, 3.16, 1.3
    yb = 0.22
    cc = V(0, yb + H / 2, 0.05)
    zf = cc[2] - D / 2
    m.rbox("Cabinet", (W, H, D), cc, body, 0.18, axis="z")
    m.rbox("Cabinet", (W + 0.08, 0.16, D + 0.08), V(0, yb + H - 0.04, 0.05), edge, 0.06, axis="z")
    for x in (-0.78, 0.78):
        for z in (-0.38, 0.46):
            m.cyl("Pad", 0.24, 0.3, V(x, 0.12, z), INKP, "y")
    for s in (-1, 1):
        m.blk("Stripe", (0.03, 0.16, D - 0.2), V(s * (W / 2 + 0.005), 1.2, 0.05), PUMPKIN)
        m.blk("Stripe", (0.03, 0.06, D - 0.2), V(s * (W / 2 + 0.005), 1.36, 0.05), ECTO_F)
    # the LED header: a sly, hungry face
    sy = 3.0
    m.blk("Bezel", (1.86, 0.66, 0.05), V(0, sy, zf - 0.015), edge)
    m.blk("Screen", (1.74, 0.56, 0.05), V(0, sy, zf - 0.04), (20, 14, 30), "Glass", refl=0.2)
    for s in (-1, 1):
        ex = s * 0.4
        m.ell("ScreenEye", (0.46, 0.28, 0.03), V(ex, sy - 0.02, zf - 0.07), ECTO, "Neon")
        # a dark lid slanting down to the middle makes the glowing eyes sly
        m.blk("ScreenEye", (0.56, 0.16, 0.035), V(ex + s * 0.02, sy + 0.09, zf - 0.08), (20, 14, 30), R=rot(z=-s * 14))
        m.ell("ScreenEye", (0.12, 0.12, 0.03), V(ex + 0.1, sy - 0.06, zf - 0.085), (16, 60, 36))
        m.blk("ScreenBrow", (0.34, 0.05, 0.03), V(ex + s * 0.02, sy + 0.22, zf - 0.075), ECTO, "Neon", R=rot(z=-s * 16))
    # the window of snacks (viewer's left), with a green light inside
    gx, gy, gw, gh = 0.24, 1.84, 1.3, 1.52
    zi = zf - 0.005
    m.blk("Inside", (gw, gh, 0.04), V(gx, gy, zi), (22, 48, 40))
    for k, y in enumerate((gy - 0.6, gy - 0.08, gy + 0.44)):
        m.blk("Shelf", (gw - 0.04, 0.04, 0.24), V(gx, y, zf - 0.12), STEEL, "Metal")
    cans = ((255, 140, 40), (110, 220, 140), (230, 60, 70), (170, 124, 236))
    for k in range(4):
        m.cyl("Snack", 0.26, 0.17, V(gx - 0.45 + k * 0.3, gy - 0.6 + 0.15, zf - 0.13), cans[k], "y", "Metal", refl=0.15)
    for k, c in enumerate(((246, 204, 60), (255, 130, 50), (230, 70, 80))):
        m.ell("Snack", (0.32, 0.38, 0.12), V(gx - 0.4 + k * 0.4, gy - 0.08 + 0.2, zf - 0.13), c, "Foil", R=rot(z=(k - 1) * 6))
    for k, c in enumerate(((110, 64, 40), (170, 124, 236), (246, 120, 170), (110, 64, 40))):
        m.blk("Snack", (0.14, 0.34, 0.08), V(gx - 0.45 + k * 0.3, gy + 0.44 + 0.18, zf - 0.13), c, R=rot(z=(k % 2) * 8 - 4))
    m.blk("Glass", (gw, gh, 0.04), V(gx, gy, zf - 0.24), (160, 255, 210), "Glass", tr=0.6, refl=0.35)
    for (sx, sy_, px, py) in ((gw + 0.12, 0.08, 0, gh / 2 + 0.02), (gw + 0.12, 0.08, 0, -gh / 2 - 0.02),
                              (0.08, gh, gw / 2 + 0.02, 0), (0.08, gh, -gw / 2 - 0.02, 0)):
        m.blk("WindowFrame", (sx, sy_, 0.26), V(gx + px, gy + py, zf - 0.12), edge)
    g = m.ball("Glow", 0.2, V(gx, gy + 0.2, zf - 0.1), ECTO, tr=1)
    m.light(g, (120, 255, 170), 1.2, 7)
    # controls (viewer's right): a little display, buttons and a coin slot
    px = -0.76
    m.rbox("Panel", (0.42, 1.52, 0.08), V(px, 1.86, zf - 0.03), (120, 106, 150), 0.06, axis="z")
    m.blk("Display", (0.3, 0.13, 0.03), V(px, 2.42, zf - 0.08), ECTO, "Neon")
    for i in range(3):
        for j in range(2):
            m.cyl("Button", 0.04, 0.09, V(px - 0.07 + j * 0.14, 2.16 - i * 0.15, zf - 0.08), WHITE if (i + j) % 2 else PUMPKIN, "z")
    m.blk("CoinSlot", (0.2, 0.26, 0.04), V(px, 1.52, zf - 0.08), PUMPKIN, "Metal")
    m.blk("CoinSlot", (0.04, 0.16, 0.03), V(px, 1.52, zf - 0.1), INKP)
    # the pickup slot is a grinning mouth: fangs, a green glow and a lolling candy-pink tongue
    my = 0.66
    R = rot(z=4)
    m.blk("Mouth", (1.52, 0.36, 0.06), V(0, my, zf - 0.01), INKP, R=R)
    m.blk("MouthGlow", (1.3, 0.1, 0.04), V(0, my - 0.11, zf - 0.03), ECTO, "Neon", R=R)
    for (sx, sy_, px_, py) in ((1.66, 0.08, 0, 0.22), (1.66, 0.08, 0, -0.22), (0.08, 0.52, 0.8, 0), (0.08, 0.52, -0.8, 0)):
        m.blk("Lip", (sx, sy_, 0.08), V(0, my, zf - 0.03) + R @ V(px_, py, 0), edge, R=R)
    for k, (x, L) in enumerate(((-0.58, 0.2), (-0.2, 0.12), (0.2, 0.12), (0.58, 0.2))):
        top = V(0, my, zf - 0.05) + R @ V(x, 0.17, 0)
        m.seg("Fang", top, top + V(0, -L * 1.3, -0.01), 0.06 if L > 0.15 else 0.05, WHITE, bulge=0.25)
    m.ell("Tongue", (0.34, 0.52, 0.1), V(-0.36, my - 0.36, zf - 0.09), CANDY_PINK, R=rot(z=8))
    m.ell("Tongue", (0.03, 0.34, 0.03), V(-0.35, my - 0.36, zf - 0.14), shade(CANDY_PINK, 0.8), R=rot(z=8))
    # slime drips under the screen and the mouth
    for (x, y, L) in ((0.62, sy - 0.33, 0.3), (-0.3, sy - 0.33, 0.2), (0.5, my - 0.22, 0.24)):
        m.drip("Slime", (x, y, zf - 0.03), L, 0.1, ECTO_D, refl=0.3)
    # see-through ghost arms reaching out of the sides
    for s in (-1, 1):
        a = V(s * (W / 2 - 0.1), 2.12, 0.15)
        b = V(s * 1.32, 2.0, -0.12)
        c = V(s * 1.44, 1.66, -0.52)
        m.seg("Shoulder", V(s * (W / 2 - 0.01), 2.12, 0.12), V(s * (W / 2 + 0.03), 2.12, 0.12), 0.24, ECTO, "Neon", shape="C", tr=0.2)
        m.seg("Arm", a, b, 0.17, GHOST, bulge=0.5, tr=0.25)
        m.seg("Arm", b, c, 0.15, GHOST, bulge=0.6, tr=0.25)
        hcn = c + V(0, -0.06, -0.12)
        m.ell("Hand", (0.32, 0.26, 0.32), hcn, GHOST, tr=0.2)
        for k in range(3):
            base = hcn + V((k - 1) * 0.09, -0.04, -0.12)
            m.spike("Claw", base, V((k - 1) * 0.3, -0.5, -1), 0.16, 0.04, ECTO_D)
    # the back: a vent and a power cord trailing to the floor with its plug
    zb = cc[2] + D / 2
    for k in range(3):
        m.blk("Vent", (1.1, 0.06, 0.03), V(0, 2.7 - k * 0.14, zb + 0.01), INKP)
    cord = [V(0.5, 0.9, zb + 0.01), V(0.56, 0.5, zb + 0.22), V(0.4, 0.1, zb + 0.5), V(0.0, 0.05, zb + 0.66)]
    m.chain("Cord", cord, 0.07, (30, 26, 36))
    m.blk("Plug", (0.16, 0.12, 0.22), cord[-1] + V(-0.1, 0.03, 0.02), (40, 36, 46), R=rot(y=-30))
    for s in (-1, 1):
        m.blk("Plug", (0.03, 0.03, 0.12), cord[-1] + V(-0.22 + s * 0.03, 0.03, 0.08), STEEL, "Metal", R=rot(y=-30))
    # the right hand (+x) clutches a candy bar
    cb = V(1.44, 1.5, -0.74)
    m.blk("Candy", (0.18, 0.5, 0.12), cb, PUMPKIN, R=rot(z=-12))
    for s in (-1, 1):
        m.ell("Candy", (0.16, 0.14, 0.1), cb + rot(z=-12) @ V(0, s * 0.3, 0), PUMPKIN, R=rot(z=-12))
    return m


# ------------------------------------------------------------------------------------------------
@model
def mushroom_witch():
    """Rare. A mushroom witch: a cream stem for a face (long crooked nose with a wart, sly green
    eyes, a smirk with one tooth) under a spotted purple mushroom cap that grows into a bent witch's
    cone with a green band and a pumpkin buckle; a ragged midnight robe with a rope belt, a patch and
    a jack-o'-lantern pouch, a high pointed collar, bell sleeves, a crooked broom in one hand and a
    glowing green potion held up in the other. Mood: sly."""
    m = SModel("mushroom_witch")
    robe = (66, 40, 100)
    robe_d = (46, 28, 72)
    stem = (240, 228, 210)
    stem_d = (214, 196, 172)
    cap = (150, 70, 190)
    cap_d = shade(cap, 0.78)
    gill = (220, 184, 230)
    spot = (238, 222, 255)
    rope = (176, 132, 82)
    wood = (130, 86, 52)
    straw = (226, 182, 92)
    # the robe, flaring to a ragged hem
    rc, rs = V(0, 1.28, 0.02), (1.46, 2.34, 1.36)
    m.ell("Robe", rs, rc, robe, "Fabric")
    m.ell("RobeHem", (1.84, 0.8, 1.72), V(0, 0.44, 0.02), robe, "Fabric")
    for k in range(9):
        a = k * 40 + 15
        L = 0.4 + (k % 3) * 0.05
        top = cpt(0.8, a, 0.52, cz=0.02)
        flap(m, "Rag", top, cpt(0.96, a, max(0.52 - L, 0.03), cz=0.02), 0.38, 0.08, robe_d, tang(a), "Fabric", bulge=0.35)
    p, n = ell_front_at(rc, rs, -0.32, -0.46)
    m.ell("Patch", (0.3, 0.3, 0.05), p + n * 0.01, ECTO_F, "Fabric", R=frame_normal(n, 10))
    for k in range(2):
        for sd in (-1, 1):
            m.blk("Stitch", (0.1, 0.022, 0.02), p + n * 0.035 + V(0, 0.08 - k * 0.16, 0), INKP, R=frame_normal(n) @ Rz(sd * 40))
    # a rope belt with a knot, and a little jack-o'-lantern pouch
    by = 1.62
    f = math.sqrt(1 - ((by - rc[1]) / (rs[1] / 2)) ** 2)
    eband(m, "Belt", V(0, by, 0.02), rs[0] / 2 * f + 0.02, rs[2] / 2 * f + 0.02, 0.07, rope, n=10, h=0.1, mat="Fabric")
    kp, kn = ell_front_at(rc, rs, 0.2, by - rc[1])
    m.ball("Belt", 0.15, kp + kn * 0.05, rope, "Fabric")
    for dx in (-0.04, 0.06):
        m.seg("Belt", kp + kn * 0.05, kp + kn * 0.07 + V(dx, -0.36, 0), 0.035, rope, "Fabric", bulge=0.5)
        m.ball("Belt", 0.07, kp + kn * 0.07 + V(dx, -0.38, 0), shade(rope, 0.8), "Fabric")
    pp, pn = ell_front_at(rc, rs, -0.56, -0.02)
    pc = pp + pn * 0.16 + V(0, -0.1, 0)
    m.ell("Pumpkin", (0.36, 0.3, 0.32), pc, PUMPKIN)
    m.ell("Pumpkin", (0.12, 0.29, 0.3), pc, shade(PUMPKIN, 0.85))
    m.cyl("Pumpkin", 0.1, 0.05, pc + V(0, 0.17, 0), (90, 140, 60), "y")
    for sd in (-1, 1):
        m.wedge("Pumpkin", (0.02, 0.06, 0.07), pc + V(sd * 0.07, 0.03, -0.16), INK, R=rot(y=90))
    m.blk("Pumpkin", (0.14, 0.03, 0.02), pc + V(0, -0.06, -0.16), INK)
    # the stem is the head
    hc, hs = V(0, 2.92, -0.02), (1.02, 1.3, 0.98)
    m.ell("Head", hs, hc, stem)
    # a high pointed collar standing up behind the head
    for a in (20, 55, 90, 125, 160):
        flap(m, "Collar", cpt(0.42, a, 2.3), cpt(0.74, a, 2.86), 0.36, 0.05, robe_d, tang(a), "Fabric", bulge=0.4)
    # the face: sly eyes, a long crooked nose with a wart, a smirk with one tooth
    m.eyes_on(hc, hs, I3, 25, 14, 0.3, 0.33, stem, WITCHY, iris=ECTO_D, lid_color=stem_d, brow=PURPLE_D, brow_k=1.1, lash=2)
    p, n = on_ell_R(hc, hs, I3, Rx(0) @ V(0, 0, -1))
    tip = p + n * 0.48 + V(0.05, -0.2, 0)
    m.horn("Nose", p - n * 0.06, tip, 0.12, stem_d, curve=V(0.02, 0.07, -0.03), n=3)
    m.ball("Nose", 0.09, tip, stem_d)
    m.ball("Bump", 0.07, lerp(p, tip, 0.5) + V(-0.06, 0.05, -0.02), (160, 176, 120))
    q, qn = on_ell_R(hc, hs, I3, Ry(-34) @ Rx(-8) @ V(0, 0, -1))
    m.ball("Bump", 0.06, q + qn * 0.01, (160, 176, 120))
    q, qn = on_ell_R(hc, hs, I3, Rx(-22) @ V(0, 0, -1))
    m.mouth(q + qn * 0.01, qn, 0.42, WITCHY, color=INKP, side_bias=1)
    m.blk("Tooth", (0.06, 0.07, 0.03), q + qn * 0.03 + V(-0.09, -0.03, 0), WHITE, R=frame_normal(qn))
    # the cap: a spotted mushroom brim with gills underneath, growing into a bent witch's cone
    Rb = rot(x=-5, z=6)
    with m.group(R=Rb, t=(0, 3.5, 0.04)):
        m.ell("HatBrim", (2.44, 0.22, 2.32), V(0, 0, 0), cap)
        m.ell("HatBrim", (2.24, 0.1, 2.12), V(0, -0.09, 0), gill)
        for k in range(8):
            t = math.radians(k * 45 + 22.5)
            m.seg("HatBrim", V(math.cos(t) * 0.5, -0.14, math.sin(t) * 0.48), V(math.cos(t) * 1.02, -0.12, math.sin(t) * 0.97), 0.022, cap_d, shape="C")
        dc, ds = V(0, 0.2, 0), (1.5, 0.72, 1.44)
        m.ell("Hat", ds, dc, cap)
        # the witch's cone: a long taper from the dome, then a bent, drooping tip
        pts = [V(0, 0.3, 0.02), V(-0.03, 1.16, 0.12), V(-0.36, 1.4, 0.38)]
        m.seg("Hat", pts[0], pts[1], 0.46, cap, bulge=0.16)
        m.seg("Hat", V(-0.02, 0.98, 0.1), pts[2], 0.15, cap, bulge=0.22)
        m.ball("HatTip", 0.1, pts[2] + V(-0.02, -0.03, 0.0), cap_d)
        eband(m, "HatBand", V(0, 0.52, 0.03), 0.46, 0.45, 0.07, ECTO_F, n=10, h=0.14, mat="Fabric")
        m.blk("HatBand", (0.22, 0.2, 0.05), V(0, 0.52, -0.47), PUMPKIN, "Metal")
        m.blk("HatBand", (0.1, 0.1, 0.03), V(0, 0.52, -0.5), cap_d)
        spots = [((0.6, 0.6, -0.55), 0.24), ((-0.7, 0.5, -0.3), 0.2), ((0.3, 0.75, 0.75), 0.22), ((-0.55, 0.45, 0.7), 0.2)]
        for dirn, sz in spots:
            q, qn = on_ell(dc, ds, dirn)
            m.ell("HatTrim", (sz, sz * 0.9, 0.04), q + qn * 0.005, spot, R=frame_normal(qn))
        for dirn, sz in (((0.9, 0.25, -0.42), 0.26), ((-0.88, 0.25, -0.48), 0.22), ((0.15, 0.25, -1), 0.2), ((0.66, 0.25, 0.78), 0.24), ((-0.5, 0.25, 0.9), 0.22)):
            q, qn = on_ell(V(0, 0, 0), (2.44, 0.22, 2.32), dirn)
            m.ell("HatTrim", (sz, sz * 0.9, 0.04), q + qn * 0.004, spot, R=frame_normal(qn))
        q = V(0.17, 0.7, -0.22)
        m.ell("HatTrim", (0.16, 0.14, 0.04), q, spot, R=frame_normal(V(0.55, 0.3, -0.78)))
    # bell sleeves; a fist round the broom (right) and the potion held up (left)
    poses = {1: (V(0.9, 1.78, -0.16), V(0.98, 1.52, -0.46)), -1: (V(-0.92, 1.86, -0.12), V(-0.98, 2.1, -0.48))}
    hands = {}
    for s, (el, wr) in poses.items():
        sh = V(s * 0.6, 2.18, 0.02)
        m.ball("Shoulder", 0.36, sh, robe, "Fabric")
        m.seg("Sleeve", sh, el, 0.17, robe, "Fabric", bulge=0.5)
        d = norm(wr - el)
        m.seg("Sleeve", el - d * 0.05, wr + d * 0.06, 0.24, robe, "Fabric", bulge=0.78)
        m.seg("Cuff", wr + d * 0.02, wr + d * 0.1, 0.25, ECTO_F, "Fabric", shape="C")
        hc_ = wr + d * 0.2
        m.glove(hc_, 0.12, stem, s, fist=True, fingers=3, forward=(d[0], 0, d[2]))
        hands[s] = hc_
    # the crooked broom
    bx, bz = hands[1][0] + 0.02, hands[1][2] - 0.04
    stick = [V(bx - 0.02, 0.62, bz - 0.02), V(bx + 0.03, 1.9, bz + 0.02), V(bx - 0.04, 3.0, bz + 0.06)]
    m.seg("BroomStick", stick[0], stick[1], 0.05, wood, "Wood", shape="C", ext=0.03)
    m.seg("BroomStick", stick[1], stick[2], 0.045, wood, "Wood", shape="C", ext=0.02)
    m.ball("BroomStick", 0.11, stick[1], shade(wood, 0.8), "Wood")
    m.ball("BroomStick", 0.1, stick[2], shade(wood, 0.8), "Wood")
    bt, bo = V(bx - 0.02, 0.7, bz - 0.02), V(bx - 0.02, 0.03, bz - 0.02)
    m.seg("Bristles", bt, bo, 0.2, straw, "Fabric", bulge=0.78)
    for k in range(7):
        t = math.radians(k * 51 + 10)
        q0 = bt + V(math.cos(t) * 0.07, -0.12, math.sin(t) * 0.07)
        q1 = bo + V(math.cos(t) * 0.17, 0.04, math.sin(t) * 0.17)
        m.seg("Bristles", q0, q1, 0.03, shade(straw, 0.82), "Fabric", bulge=0.6)
    m.cyl("BroomBand", 0.08, 0.26, V(bx - 0.02, 0.64, bz - 0.02), PURPLE, "y", "Fabric")
    # the glowing potion
    pc = hands[-1] + V(0, 0.3, -0.02)
    m.ball("Potion", 0.38, pc, (150, 255, 190), "Glass", tr=0.35, refl=0.3)
    liquid = m.ball("Potion", 0.3, pc + V(0, -0.03, 0), ECTO, "Neon")
    m.cyl("Potion", 0.16, 0.13, pc + V(0, 0.24, 0), (150, 255, 190), "y", "Glass", tr=0.35)
    m.cyl("Potion", 0.1, 0.12, pc + V(0, 0.36, 0), (150, 100, 60), "y", "Wood")
    m.ball("Potion", 0.07, pc + V(0.06, 0.1, -0.1), (220, 255, 230), "Neon")
    m.light(liquid, (120, 255, 170), 1.0, 6)
    return m


# ------------------------------------------------------------------------------------------------
@model
def mall_cop_phantom():
    """Epic. A ghost mall cop on a two-wheeled scooter: blue uniform shirt with a gold badge, navy
    tie, pockets and a pen, a belt with a radio and a pink donut, "SECURITY" across the back, a
    police cap with a gold badge, a big grey mustache and one eye squinting with suspicion. A
    flashlight throws a green beam ahead; the other hand steers. Below the belt the ghost thins into
    a wispy tail resting on the deck. Mood: suspicious."""
    m = SModel("mall_cop_phantom")
    shirt = (96, 124, 190)
    shirt_d = shade(shirt, 0.8)
    navy = (36, 42, 78)
    ghost = GHOST
    rubber = (34, 32, 40)
    chrome = (214, 218, 226)
    gray = (118, 112, 132)
    # the scooter
    for s in (-1, 1):
        wx = s * 0.62
        m.cyl("Wheel", 0.26, 0.92, V(wx, 0.46, 0.06), rubber, "x", "Rubber")
        m.cyl("Hubcap", 0.06, 0.52, V(wx + s * 0.13, 0.46, 0.06), chrome, "x", "Metal", refl=0.3)
        m.cyl("WheelHub", 0.04, 0.2, V(wx + s * 0.165, 0.46, 0.06), ECTO, "x", "Neon")
        m.ell("Fender", (0.34, 0.52, 1.04), V(wx, 0.72, 0.06), navy)
        m.ell("Fender", (0.36, 0.06, 0.62), V(wx, 0.975, 0.06), PUMPKIN)
    m.rbox("Deck", (0.96, 0.14, 0.72), V(0, 0.44, 0.06), navy, 0.12, axis="y")
    m.blk("DeckGrip", (0.86, 0.03, 0.6), V(0, 0.525, 0.06), rubber, "Rubber")
    m.blk("DeckGlow", (0.9, 0.03, 0.62), V(0, 0.36, 0.06), ECTO, "Neon")
    pa, pb = V(0, 0.5, -0.18), V(0, 2.14, -0.5)
    m.ell("Pole", (0.3, 0.26, 0.32), V(0, 0.58, -0.2), navy)
    m.seg("Pole", pa, pb, 0.055, chrome, "Metal", shape="C")
    m.cyl("Handlebar", 0.86, 0.08, V(0, 2.16, -0.52), chrome, "x", "Metal")
    for s in (-1, 1):
        m.cyl("Grip", 0.18, 0.12, V(s * 0.38, 2.16, -0.52), rubber, "x", "Rubber")
    hl = lerp(pa, pb, 0.43)
    m.cyl("Headlight", 0.08, 0.2, hl + V(0, 0, -0.06), navy, "z")
    m.cyl("Headlight", 0.03, 0.15, hl + V(0, 0, -0.11), (255, 244, 190), "z", "Neon")
    m.cyl("Beacon", 0.06, 0.16, V(0, 2.23, -0.52), navy, "y")
    bcn = m.ball("Beacon", 0.17, V(0, 2.3, -0.52), PUMPKIN, "Neon", tr=0.1)
    m.light(bcn, (255, 150, 60), 0.8, 5)
    # the ghost: a wispy tail curling onto the deck
    m.seg("Tail", V(0, 2.0, 0.1), V(0.05, 0.96, 0.2), 0.4, ghost, bulge=0.22, tr=0.12)
    m.seg("Tail", V(0.04, 1.18, 0.2), V(0.24, 0.66, -0.02), 0.2, ghost, bulge=0.3, tr=0.12)
    m.seg("TailTip", V(0.2, 0.7, 0.01), V(0.4, 0.62, -0.16), 0.1, ghost, bulge=0.35, tr=0.12)
    for (x, y, z, d) in ((-0.36, 1.2, 0.34, 0.12), (0.4, 1.0, 0.42, 0.1), (-0.2, 0.8, 0.5, 0.08)):
        m.ball("Wisp", d, V(x, y, z), ECTO, "Neon", tr=0.5)
    # the uniform: shirt with a little belly, belt, badge, pockets, pen, tie and collar
    tc, ts = V(0, 2.36, 0.12), (1.16, 1.3, 0.88)
    m.ell("Torso", ts, tc, shirt, "Fabric")
    bc_, bs_ = V(0, 2.06, 0.0), (0.96, 0.78, 0.72)
    m.ell("Belly", bs_, bc_, shirt, "Fabric")
    eband(m, "Belt", V(0, 1.86, 0.06), 0.43, 0.36, 0.08, (30, 28, 36), n=12, h=0.13)
    m.blk("Buckle", (0.18, 0.14, 0.05), V(0, 1.86, -0.31), GOLD, "Metal")
    m.blk("Radio", (0.16, 0.28, 0.12), V(0.4, 1.86, -0.12), (30, 30, 36), R=rot(y=-40))
    m.seg("RadioAntenna", V(0.42, 1.98, -0.1), V(0.44, 2.24, -0.08), 0.02, (30, 30, 36), shape="C")
    m.ball("RadioLight", 0.05, V(0.44, 1.96, -0.2), ECTO, "Neon")
    dn = V(-0.44, 1.78, -0.1)
    Rd = rot(y=50)
    m.cyl("Donut", 0.12, 0.3, dn, (214, 160, 100), "z", R=Rd)
    m.cyl("Donut", 0.04, 0.27, dn + Rd @ V(0, 0, -0.06), CANDY_PINK, "z", R=Rd)
    m.cyl("Donut", 0.13, 0.09, dn + Rd @ V(0, 0, -0.02), (60, 40, 44), "z", R=Rd)
    for k in range(3):
        t = math.radians(k * 120 + 20)
        m.blk("Donut", (0.05, 0.02, 0.02), dn + Rd @ V(math.cos(t) * 0.09, math.sin(t) * 0.09, -0.085), (110, 220, 255) if k % 2 else WHITE, R=Rd @ Rz(k * 50))
    p, n = ell_front_at(tc, ts, -0.26, 0.22)
    m.ell("Badge", (0.2, 0.24, 0.05), p + n * 0.02, GOLD, "Foil", R=frame_normal(n))
    m.ell("Badge", (0.07, 0.07, 0.03), p + n * 0.045, ECTO, "Neon", R=frame_normal(n))
    for sd in (-1, 1):
        p, n = ell_front_at(tc, ts, sd * 0.27, 0.02)
        m.blk("ShirtPocket", (0.24, 0.07, 0.04), p + n * 0.02, shirt_d, "Fabric", R=frame_normal(n))
    p, n = ell_front_at(tc, ts, 0.27, 0.06)
    m.seg("Pen", p + n * 0.03, p + n * 0.03 + V(0.02, 0.14, 0), 0.025, (30, 30, 36), shape="C")
    p, n = ell_front_at(tc, ts, 0.0, 0.5)
    m.ball("Tie", 0.12, p + n * 0.03, navy, "Fabric")
    q, qn = ell_front_at(bc_, bs_, 0.0, 0.08)
    m.seg("Tie", p + n * 0.03, q + qn * 0.03, 0.08, navy, "Fabric", r2=0.025, bulge=0.6)
    for sd in (-1, 1):
        flap(m, "Collar", p + V(sd * 0.04, 0.06, 0.0), p + V(sd * 0.22, -0.08, -0.02), 0.14, 0.04, shade(shirt, 1.12), V(0, 1, 0), "Fabric", bulge=0.4)
    zb = lambda x: tc[2] + ts[2] / 2 * math.sqrt(max(1 - (x / (ts[0] / 2)) ** 2 - ((2.5 - tc[1]) / (ts[1] / 2)) ** 2, 0.0)) + 0.02
    m.text("Text", "SECURITY", (0, 2.5, zb(0)), 0.13, (250, 222, 70), facing="back", wrap=zb)
    # the head: a ghost with a police cap, a big mustache and one suspicious squint
    hc, hs = V(0, 3.28, 0.1), (0.96, 1.06, 0.92)
    m.ell("Head", hs, hc, ghost)
    m.cyl("HatBand", 0.18, 0.96, V(0, 3.62, 0.1), (24, 24, 30), "y")
    m.cyl("Cap", 0.12, 1.14, V(0, 3.76, 0.1), navy, "y")
    m.ell("Cap", (1.14, 0.12, 1.1), V(0, 3.83, 0.1), navy)
    m.ell("CapBill", (0.84, 0.06, 0.46), V(0, 3.56, -0.38), (20, 20, 26), R=rot(x=12), refl=0.25)
    m.ell("CapBadge", (0.18, 0.2, 0.05), V(0, 3.72, -0.47), GOLD, "Foil")
    for sd, md in ((1, dict(SUSPICIOUS, open=0.92, brow=-8, lift=0.22)), (-1, dict(SUSPICIOUS, open=0.4, brow=24, lift=0.0))):
        p, n = on_ell_R(hc, hs, I3, Ry(-sd * 23) @ Rx(2) @ V(0, 0, -1))
        m.eye(p, n, 0.26, 0.3, ghost, md, side=sd, iris=ECTO_D, brow=gray, brow_k=1.25, lid_color=shade(ghost, 0.88))
    p, n = on_ell_R(hc, hs, I3, Rx(-10) @ V(0, 0, -1))
    m.ball("Nose", 0.16, p + n * 0.04, shade(ghost, 0.92))
    p, n = on_ell_R(hc, hs, I3, Rx(-20) @ V(0, 0, -1))
    F = frame_normal(n)
    m.ell("Mustache", (0.18, 0.14, 0.12), p + n * 0.05, gray, R=F)
    for sd in (-1, 1):
        m.ell("Mustache", (0.36, 0.17, 0.14), p + n * 0.04 + V(sd * 0.16, -0.02, 0.02), gray, R=F @ Rz(-sd * 14))
        m.ball("Mustache", 0.1, p + n * 0.0 + V(sd * 0.33, 0.04, 0.07), gray)
    p, n = on_ell_R(hc, hs, I3, Rx(-31) @ V(0, 0, -1))
    m.mouth(p + n * 0.01, n, 0.24, "grumpy", color=INKP, kind="frown")
    # arms: short uniform sleeves, ghostly arms. Right: the flashlight. Left: on the handlebar.
    poses = {1: (V(0.86, 2.36, 0.0), V(0.74, 2.14, -0.42)), -1: (V(-0.82, 2.4, -0.06), V(-0.48, 2.2, -0.46))}
    hands = {}
    for s, (el, wr) in poses.items():
        sh = V(s * 0.58, 2.74, 0.12)
        m.ball("Shoulder", 0.42, sh, shirt, "Fabric")
        m.seg("Sleeve", sh, lerp(sh, el, 0.72), 0.18, shirt, "Fabric", bulge=0.5)
        m.seg("Cuff", lerp(sh, el, 0.62), lerp(sh, el, 0.76), 0.19, shirt_d, "Fabric", shape="C")
        m.ell("Epaulette", (0.32, 0.06, 0.26), sh + V(0, 0.2, 0), navy)
        m.seg("UpperArm", lerp(sh, el, 0.6), el, 0.12, ghost)
        m.ball("Elbow", 0.22, el, ghost)
        m.seg("Forearm", el, wr, 0.11, ghost, bulge=0.6)
        d = norm(wr - el)
        hands[s] = wr + d * 0.12
        m.glove(hands[s], 0.13, ghost, s, fist=True, forward=(d[0], 0, d[2]))
    hp = hands[1]
    fd = norm(V(0.05, -0.3, -1))
    m.seg("Flashlight", hp - fd * 0.12, hp + fd * 0.3, 0.065, (30, 30, 36), shape="C")
    m.seg("FlashBand", hp - fd * 0.13, hp - fd * 0.07, 0.072, (250, 210, 60), shape="C")
    m.seg("FlashLens", hp + fd * 0.28, hp + fd * 0.4, 0.1, (250, 210, 60), shape="C")
    lens = m.seg("FlashLens", hp + fd * 0.39, hp + fd * 0.42, 0.08, ECTO, "Neon", shape="C")
    Fb = frame_from_x(fd)
    m.add("E", "FlashBeam", (1.0, 0.3, 0.3), hp + fd * 0.9, ECTO, "Neon", Fb, 0.72)
    m.add("E", "FlashBeam", (0.8, 0.5, 0.5), hp + fd * 1.18, ECTO, "Neon", Fb, 0.84)
    m.light(lens, (120, 255, 170), 1.2, 8)
    return m


# ------------------------------------------------------------------------------------------------
@model
def escalator_wraith():
    """Mythic. A hooded wraith rising from a stretch of mall escalator: steel diamond-plate steps
    lit green along their edges, glass balustrades with black handrails. A tattered midnight robe
    and mantle, a deep hood with only two slanted green eyes glowing inside, chains wrapped round
    the robe with a padlock, glowing runes on the hem, bony claws hanging a chain and shackle from
    one hand and a green ghost lantern from the other, lost souls drifting round it. Mood: ominous."""
    m = SModel("escalator_wraith")
    robe = (52, 34, 84)
    robe_l = (82, 58, 122)
    steel = (150, 154, 166)
    metal_d = (66, 68, 80)
    iron = (58, 58, 68)
    bone = (214, 206, 190)
    # the escalator: four steps climbing away from the viewer
    sw = 1.36
    tops = []
    for k in range(4):
        y = 0.18 + k * 0.24
        z = -0.92 + k * 0.42
        m.blk("Housing", (sw, y, 0.42), V(0, y / 2, z), metal_d, "Metal")
        m.blk("Step", (sw, 0.07, 0.42), V(0, y + 0.015, z), steel, "DiamondPlate")
        m.blk("StepEdge", (sw, 0.035, 0.05), V(0, y + 0.04, z - 0.19), ECTO, "Neon")
        for x in (-0.34, 0.34):
            m.blk("StepGroove", (0.03, 0.02, 0.36), V(x, y + 0.055, z + 0.02), metal_d)
        tops.append((z, y + 0.05))
    ly = tops[-1][1]
    m.blk("Landing", (sw, ly, 0.56), V(0, ly / 2, 0.83), metal_d, "Metal")
    m.blk("Step", (sw, 0.06, 0.56), V(0, ly + 0.0, 0.83), steel, "DiamondPlate")
    m.blk("Comb", (sw, 0.04, 0.08), V(0, ly + 0.03, 0.56), (210, 214, 222), "Metal")
    # glass balustrades with black handrails and a green running light along the skirt
    u = norm(V(0, 0.24, 0.42))
    w = V(0, u[2], -u[1])
    Rp = np.column_stack([V(1, 0, 0), w, u])
    for s in (-1, 1):
        pc = V(s * 0.74, 0.9, -0.08)
        m.blk("Balustrade", (0.05, 0.6, 2.2), pc, (190, 255, 220), "Glass", R=Rp, tr=0.55, refl=0.3)
        m.blk("Skirt", (0.1, 0.34, 2.24), pc - w * 0.46, metal_d, "Metal", R=Rp)
        m.blk("SkirtLight", (0.02, 0.04, 2.1), pc - w * 0.4 + V(s * 0.06, 0, 0), ECTO, "Neon", R=Rp)
        ra, rb = pc + w * 0.33 - u * 1.1, pc + w * 0.33 + u * 1.1
        m.seg("Rail", ra, rb, 0.065, (24, 22, 28), "Rubber", shape="C")
        m.ball("Rail", 0.13, ra, (24, 22, 28), "Rubber")
        m.seg("Rail", ra, ra - w * 0.36 - u * 0.06, 0.06, (24, 22, 28), "Rubber", shape="C")
    # the robe, rising from the steps in tatters
    # a cloak that widens like a bell down to a ragged hem floating over the steps
    rc, rs = V(0, 2.42, 0.18), (1.5, 2.3, 1.28)
    m.ell("Robe", rs, rc, robe, "Fabric")
    lc_, ls_ = V(0, 1.5, 0.18), (1.84, 0.9, 1.56)
    m.ell("RobeLow", ls_, lc_, robe, "Fabric")
    for k in range(12):
        a = k * 30 + 5
        top = cpt(0.8, a, 1.5, cz=0.18)
        L = 0.42 + (k % 3) * 0.1
        bot = cpt(1.0, a, 1.5 - L, cz=0.18)
        # stop above the step or landing below it
        zf = bot[2]
        floor = max([t[1] for t in tops if abs(t[0] - zf) < 0.25] + [ly if zf > 0.55 else 0.0])
        bot[1] = max(bot[1], floor + 0.06)
        flap(m, "Tatter", top, bot, 0.34, 0.06, robe if k % 2 else robe_l, tang(a), "Fabric", bulge=0.3)
    for (x, y, z, d) in ((-0.3, 1.0, -0.25, 0.2), (0.32, 1.06, 0.1, 0.16), (0.0, 0.98, 0.5, 0.18)):
        m.ball("Wisp", d, V(x, y, z), ECTO, "Neon", tr=0.55)
    # glowing runes on the robe's front
    for k, (X, Y) in enumerate(((-0.34, 0.06), (0.0, 0.0), (0.34, 0.06))):
        p, n = ell_front_at(lc_, ls_, X, Y)
        F = frame_normal(n)
        m.blk("Rune", (0.04, 0.2, 0.02), p + n * 0.01, ECTO, "Neon", R=F @ Rz(k * 30 - 30))
        if k != 1:
            m.blk("Rune", (0.14, 0.035, 0.02), p + n * 0.012 + F[:, 1] * 0.04, ECTO, "Neon", R=F @ Rz(k * 30 - 30))
    # a chain wrapped across the robe with a padlock
    for i in range(8):
        t = i / 7
        X, Y = lerp(0.46, -0.4, t), lerp(0.62, -0.34, t)
        p, n = ell_front_at(rc, rs, X, Y)
        F = frame_normal(n) @ Rz(-48 + (90 if i % 2 else 0))
        m.ell("ChainLink", (0.2, 0.1, 0.06 if i % 2 == 0 else 0.05), p + n * 0.03, iron, "Metal", R=F)
    p, n = ell_front_at(rc, rs, -0.44, -0.46)
    F = frame_normal(n)
    m.blk("Padlock", (0.2, 0.18, 0.08), p + n * 0.06, GOLD, "Metal", R=F)
    m.seg("Padlock", p + n * 0.06 + F[:, 1] * 0.08 - F[:, 0] * 0.06, p + n * 0.06 + F[:, 1] * 0.08 + F[:, 0] * 0.06, 0.03, iron, "Metal", shape="C")
    m.blk("Padlock", (0.03, 0.06, 0.02), p + n * 0.1 - F[:, 1] * 0.01, INK, R=F)
    # a tattered mantle over the shoulders
    # a ragged capelet round the hood
    m.ell("Mantle", (1.3, 0.44, 1.12), V(0, 3.4, 0.16), robe_l, "Fabric")
    for k in range(10):
        a = k * 36 + 18
        L = 0.5 if k % 2 else 0.74
        flap(m, "Tatter", cpt(0.5, a, 3.44, cz=0.16), cpt(0.84, a, 3.44 - L, cz=0.16), 0.3, 0.05, robe_l if k % 2 else shade(robe_l, 0.85), tang(a), "Fabric", bulge=0.2)
    # the deep hood: a pointed back, a rim round the face and only two green eyes inside
    hc, hs = V(0, 3.88, 0.12), (1.06, 1.18, 1.12)
    m.ell("Hood", hs, hc, robe, "Fabric")
    m.seg("Hood", hc + V(0, 0.3, 0.24), hc + V(0, 0.36, 0.9), 0.2, robe, "Fabric", bulge=0.18)
    p0 = hc + V(0, -0.04, -0.56)
    m.ell("HoodDark", (0.76, 0.88, 0.3), p0 + V(0, 0, 0.07), (10, 6, 16))
    for k in range(10):
        t0, t1 = 2 * math.pi * k / 10, 2 * math.pi * (k + 1) / 10
        a_ = p0 + V(math.cos(t0) * 0.41, math.sin(t0) * 0.47, 0.0)
        b_ = p0 + V(math.cos(t1) * 0.41, math.sin(t1) * 0.47, 0.0)
        m.seg("HoodDark", a_, b_, 0.07, robe_l, "Fabric", shape="C", ext=0.03)
    for sd in (-1, 1):
        e = p0 + V(sd * 0.16, 0.06, -0.06)
        m.ell("EyeGlow", (0.26, 0.09, 0.05), e, ECTO, "Neon", R=rot(z=sd * 16))
        m.ell("EyeGlow", (0.4, 0.2, 0.04), e + V(0, 0, 0.02), ECTO, "Neon", R=rot(z=sd * 16), tr=0.75)
    g = m.ball("Glow", 0.2, p0 + V(0, 0, 0.2), ECTO, tr=1)
    m.light(g, (120, 255, 170), 1.4, 6)
    # wide ragged sleeves with bony claws
    poses = {1: (V(0.98, 2.7, -0.12), V(0.82, 2.42, -0.6)), -1: (V(-0.96, 2.76, -0.1), V(-0.84, 2.56, -0.62))}
    hands = {}
    for s, (el, wr) in poses.items():
        sh = V(s * 0.66, 3.14, 0.16)
        m.seg("Sleeve", sh, el, 0.2, robe, "Fabric", bulge=0.5)
        d = norm(wr - el)
        m.seg("Sleeve", el - d * 0.06, wr + d * 0.04, 0.27, robe, "Fabric", bulge=0.8)
        side = norm(np.cross(d, V(0, 1, 0)))
        for t in (-1, 1):
            flap(m, "Sleeve", wr + side * t * 0.14, wr + side * t * 0.2 + V(0, -0.36, 0) + d * 0.05, 0.16, 0.04, robe_l, side, "Fabric", bulge=0.3)
        hp = wr + d * 0.16
        m.ell("Hand", (0.22, 0.12, 0.2), hp, bone, R=frame_from_x(d))
        for f_ in range(4):
            base = hp + d * 0.08 + side * (f_ - 1.5) * 0.06
            m.seg("Finger", base, base + d * 0.16 + V(0, -0.16, 0), 0.026, bone, bulge=0.5)
        hands[s] = hp
    # right claw: a chain hanging to an open shackle
    hp = hands[1]
    for i in range(7):
        c = hp + V(0, -0.1 - i * 0.16, -0.02 * i)
        m.ell("Shackle", (0.07, 0.2, 0.14) if i % 2 == 0 else (0.14, 0.2, 0.07), c, iron, "Metal")
    sc = hp + V(0, -1.32, -0.16)
    m.ring("Shackle", sc, 0.13, 0.05, iron, "z", 7, "Metal")
    # left claw: a ghost lantern with a green flame
    lc = hands[-1] + V(0, -0.5, 0)
    m.seg("Lantern", hands[-1] + V(0, -0.04, 0), lc + V(0, 0.24, 0), 0.025, iron, "Metal", shape="C")
    m.cyl("Lantern", 0.07, 0.32, lc + V(0, 0.21, 0), iron, "y", "Metal")
    m.ball("Lantern", 0.16, lc + V(0, 0.26, 0), iron, "Metal")
    m.cyl("Lantern", 0.07, 0.32, lc + V(0, -0.2, 0), iron, "y", "Metal")
    for (x, z) in ((-0.11, -0.11), (0.11, -0.11), (-0.11, 0.11), (0.11, 0.11)):
        m.cyl("Lantern", 0.36, 0.04, lc + V(x, 0, z), iron, "y", "Metal")
    m.cyl("Lantern", 0.34, 0.22, lc, (170, 255, 210), "y", "Glass", tr=0.5)
    fl = m.ell("Lantern", (0.12, 0.22, 0.12), lc + V(0, -0.02, 0), ECTO, "Neon")
    m.light(fl, (120, 255, 170), 1.2, 6)
    # lost souls drifting round it
    for (x, y, z, d) in ((1.05, 3.7, 0.3, 0.14), (-1.1, 3.3, 0.5, 0.12), (0.7, 4.3, -0.2, 0.1), (-0.8, 1.8, -0.5, 0.12)):
        m.ball("Wisp", d, V(x, y, z), ECTO if d > 0.11 else LILAC, "Neon", tr=0.45)
    return m


# ------------------------------------------------------------------------------------------------
@model
def the_mannequin_duke():
    """Legendary. An aristocratic shop-window mannequin on a marble plinth: glossy cream with darker
    ball joints, an egg head with half-lidded violet eyes, a thin curled mustache and a sinister
    little smile, a gold monocle on a chain, a black top hat with a purple band and a glowing green
    gem. A purple velvet tailcoat with gold epaulettes and fringe, gold buttons, a white cravat with a
    green pin, a green sash with a medal, a rose and a pocket square; white breeches, glossy black
    riding boots with tan tops and gold buckles. One hand rests on the hip, the other on a black
    cane topped with a gold orb and a green gem. Mood: aristocratic, sinister smile."""
    m = SModel("the_mannequin_duke")
    skin = (246, 236, 222)
    skin_d = (206, 190, 172)
    velvet = (96, 36, 128)
    velvet_d = (64, 22, 90)
    cream = (246, 242, 232)
    boot = (26, 22, 30)
    tan = (150, 98, 58)
    black = (24, 20, 30)
    marble = (232, 228, 238)
    # the display plinth
    m.cyl("StandBase", 0.22, 1.94, V(0, 0.11, 0), marble, "y", "Marble")
    m.cyl("StandRing", 0.06, 1.98, V(0, 0.23, 0), GOLD, "y", "Foil")
    m.cyl("StandTop", 0.12, 1.72, V(0, 0.32, 0), velvet_d, "y", "Fabric")
    m.blk("Plaque", (0.52, 0.14, 0.03), V(0, 0.11, -0.97), (214, 170, 80), "Metal")
    for k in range(2):
        m.blk("Plaque", (0.36 - k * 0.1, 0.02, 0.02), V(0, 0.14 - k * 0.05, -0.985), (120, 86, 40))
    yb = 0.38
    # legs: white breeches, ball-joint knees, glossy riding boots
    for s in (-1, 1):
        hip = V(s * 0.25, 2.66, 0.04)
        knee = V(s * 0.27, 1.66, -0.02)
        ank = V(s * 0.27, yb + 0.28, 0.02)
        m.ball("Hip", 0.36, hip, skin_d, refl=0.15)
        m.seg("Thigh", hip, knee, 0.2, cream, "Fabric", bulge=0.4, ext=0.04)
        m.ball("Knee", 0.26, knee + V(0, 0.02, -0.02), skin_d, refl=0.15)
        m.seg("Boot", knee + V(0, -0.1, 0), ank, 0.165, boot, bulge=0.45, refl=0.2)
        m.seg("Spat", knee + V(0, -0.08, 0), knee + V(0, -0.24, 0), 0.185, tan, shape="C")
        m.ell("Boot", (0.32, 0.3, 0.64), V(s * 0.27, yb + 0.15, -0.14), boot, refl=0.2)
        m.blk("Sole", (0.3, 0.06, 0.62), V(s * 0.27, yb + 0.03, -0.14), (60, 40, 30))
        m.blk("Heel", (0.24, 0.12, 0.16), V(s * 0.27, yb + 0.06, 0.12), (60, 40, 30))
        m.cyl("Spat", 0.05, 0.35, V(s * 0.27, yb + 0.34, 0.02), tan, "y")
        m.blk("Spat", (0.12, 0.1, 0.04), V(s * 0.27, yb + 0.34, -0.16), GOLD, "Metal")
    # the tailcoat: squared shoulders, open front over a white shirt, tails at the back
    cc, cs = V(0, 3.5, 0.02), (1.12, 1.64, 0.76)
    pc_, ps_ = V(0, 4.08, 0.02), (1.3, 0.4, 0.66)
    m.ell("Coat", cs, cc, velvet, "Fabric")
    m.ell("Coat", ps_, pc_, velvet, "Fabric")

    def surf(x, y):
        best = 9.0
        for (c, sz) in ((cc, cs), (pc_, ps_)):
            u = (x - c[0]) / (sz[0] / 2)
            v = (y - c[1]) / (sz[1] / 2)
            if u * u + v * v < 1:
                best = min(best, c[2] - sz[2] / 2 * math.sqrt(1 - u * u - v * v))
        return best

    p, n = ell_front_at(cc, cs, 0, 0.3)
    m.ell("Shirt", (0.34, 0.9, 0.1), p + n * 0.01, cream, "Fabric", R=frame_normal(n))
    for sd in (-1, 1):
        a_, na = ell_front_at(cc, cs, sd * 0.12, 0.68)
        b_, nb = ell_front_at(cc, cs, sd * 0.25, -0.12)
        flap(m, "Lapel", a_ + na * 0.03, b_ + nb * 0.03, 0.2, 0.05, velvet_d, V(1, 0, 0), "Fabric", bulge=0.45)
    for k, (y, d_) in enumerate(((4.3, 0.2), (4.16, 0.22), (4.02, 0.17))):
        m.ell("Cravat", (d_, d_ * 0.8, d_ * 0.6), V(0, y, surf(0, y) - 0.06), cream, "Fabric")
    m.ball("CravatPin", 0.07, V(0, 4.16, surf(0, 4.16) - 0.17), ECTO, "Neon")
    m.band("Sash", [(0.48, 4.02), (0.26, 3.64), (0.0, 3.26), (-0.3, 2.94)], 0.18, 0.04, ECTO_F, surface=surf, lift=0.03, mat="Fabric")
    m.ell("Medal", (0.18, 0.18, 0.05), V(0.2, 3.56, surf(0.2, 3.56) - 0.07), GOLD, "Foil")
    m.ball("Medal", 0.08, V(0.2, 3.56, surf(0.2, 3.56) - 0.1), ECTO, "Neon")
    for sd in (-1, 1):
        for y in (3.0, 3.24, 3.48):
            m.ball("Button", 0.08, V(sd * 0.27, y, surf(sd * 0.27, y) - 0.02), GOLD, "Metal")
    m.wedge("PocketSquare", (0.14, 0.1, 0.04), V(-0.34, 3.9, surf(-0.34, 3.9) - 0.03), ECTO_F, "Fabric")
    m.ball("Rose", 0.13, V(0.2, 3.94, surf(0.2, 3.94) - 0.08), (180, 60, 150), "Fabric")
    m.ell("Rose", (0.1, 0.05, 0.03), V(0.27, 3.88, surf(0.27, 3.88) - 0.05), (80, 150, 70), R=rot(z=-30))
    for sd in (-1, 1):
        a_, na = ell_front_at(cc, cs, sd * 0.2, 0.7)
        b_, nb = ell_front_at(cc, cs, sd * 0.36, -0.14)
        m.seg("Trim", a_ + na * 0.045 + V(sd * 0.1, 0, 0), b_ + nb * 0.045 + V(sd * 0.11, 0, 0), 0.02, GOLD, "Foil", shape="C")
        m.ell("CoatTail", (0.34, 1.34, 0.12), V(sd * 0.17, 2.48, 0.4), velvet, "Fabric", R=rot(x=8))
        m.seg("Trim", V(sd * 0.17, 1.86, 0.33), V(sd * 0.33, 1.98, 0.35), 0.022, GOLD, "Foil", shape="C")
        m.ball("Button", 0.08, V(sd * 0.17, 3.08, 0.43), GOLD, "Metal")
    # a pocket-watch chain across the waist, with the watch
    wpts = [V(0.3, 2.98, surf(0.3, 2.98) - 0.03), V(0.12, 2.9, surf(0.12, 2.9) - 0.04), V(-0.08, 2.92, surf(-0.08, 2.92) - 0.04), V(-0.22, 3.0, surf(-0.22, 3.0) - 0.03)]
    m.chain("WatchChain", wpts, 0.025, GOLD, "Metal")
    m.cyl("Watch", 0.04, 0.16, wpts[1] + V(0.0, -0.12, -0.02), GOLD, "z", "Metal")
    m.cyl("Watch", 0.02, 0.12, wpts[1] + V(0.0, -0.12, -0.045), cream, "z")
    # gold epaulettes with fringe
    for s in (-1, 1):
        ep = V(s * 0.58, 4.27, 0.02)
        m.ell("Epaulette", (0.42, 0.1, 0.38), ep, GOLD, "Foil")
        for k in range(5):
            t = math.radians(-60 + k * 30)
            q = ep + V(s * math.cos(t) * 0.2, -0.1, math.sin(t) * 0.18)
            m.cyl("Fringe", 0.16, 0.05, q, GOLD, "y", "Foil")
    # arms: velvet sleeves, lace cuffs, mannequin wrist joints and glossy hands
    poses = {1: (V(0.8, 3.46, -0.04), V(0.88, 2.86, -0.2)), -1: (V(-0.9, 3.38, 0.08), V(-0.6, 2.98, -0.12))}
    hands = {}
    for s, (el, wr) in poses.items():
        sh = V(s * 0.6, 4.08, 0.02)
        m.ball("Shoulder", 0.36, sh, velvet, "Fabric")
        m.seg("UpperArm", sh, el, 0.15, velvet, "Fabric", bulge=0.5)
        m.ball("Elbow", 0.27, el, velvet, "Fabric")
        d = norm(wr - el)
        m.seg("Forearm", el, wr, 0.14, velvet, "Fabric", bulge=0.55)
        m.seg("Cuff", wr - d * 0.1, wr - d * 0.02, 0.16, GOLD, "Foil", shape="C")
        m.add("E", "Cuff", (0.08, 0.3, 0.3), wr + d * 0.04, cream, "Fabric", frame_from_x(d))
        m.ball("Joint", 0.13, wr + d * 0.12, skin_d, refl=0.15)
        side_ = norm(np.cross(d, V(0, 0, 1)))
        for o in (-0.05, 0.05):
            m.ball("Cuff", 0.05, wr - d * 0.06 + side_ * o + V(0, 0, -0.15), GOLD, "Metal")
        hands[s] = wr + d * 0.26
        m.glove(hands[s], 0.11, skin, s, fist=(s == 1), fingers=3, forward=(d[0], 0, d[2]))
    # the cane, gold-topped with a glowing green gem
    cb, ct = V(0.7, yb, -0.42), V(0.9, 2.82, -0.24)
    m.seg("Cane", cb, ct, 0.04, black, shape="C", refl=0.2)
    m.seg("Cane", cb, cb + norm(ct - cb) * 0.1, 0.045, SILVER, "Metal", shape="C")
    for t in (0.86, 0.12):
        q = lerp(cb, ct, t)
        m.seg("CaneBand", q - norm(ct - cb) * 0.03, q + norm(ct - cb) * 0.03, 0.055, GOLD, "Metal", shape="C")
    m.ball("CaneTop", 0.2, ct + V(0, 0.04, 0), GOLD, "Metal", refl=0.2)
    gem = m.ball("CaneGem", 0.11, ct + V(0, 0.16, 0), ECTO, "Neon")
    m.sparkles(gem, (170, 255, 200))
    # neck and the egg head
    m.seg("Neck", V(0, 4.2, 0.0), V(0, 4.6, 0.0), 0.12, skin, refl=0.15)
    hc, hs = V(0, 4.98, 0.0), (0.7, 0.94, 0.76)
    m.ell("Head", hs, hc, skin, refl=0.15)
    eyes = m.eyes_on(hc, hs, I3, 25, 8, 0.19, 0.17, skin, SINISTER, iris=(140, 84, 210), lid_color=skin_d, brow=INK, brow_k=0.9, lash=2)
    p, n = on_ell_R(hc, hs, I3, Rx(-4) @ V(0, 0, -1))
    m.seg("Nose", p - n * 0.02, p + n * 0.1 + V(0, -0.07, 0), 0.05, skin, bulge=0.6, refl=0.15)
    p, n = on_ell_R(hc, hs, I3, Rx(-15) @ V(0, 0, -1))
    for sd in (-1, 1):
        pts = [p + n * 0.02 + V(sd * 0.02, 0, 0), p + n * 0.01 + V(sd * 0.13, -0.02, 0.03), p + V(sd * 0.21, 0.04, 0.07)]
        m.chain("Mustache", pts, 0.035, black)
        m.ball("Mustache", 0.05, pts[-1] + V(sd * 0.01, 0.03, 0), black)
    p, n = on_ell_R(hc, hs, I3, Rx(-26) @ V(0, 0, -1))
    m.mouth(p + n * 0.01, n, 0.22, SINISTER, color=(120, 36, 60), side_bias=1)
    # the monocle over the right eye, on a chain to the lapel
    e = eyes[0]
    q, qn = on_ell_R(hc, hs, I3, e - hc)
    mc = q + qn * 0.06
    Fm = frame_normal(qn)
    m.ring("Monocle", mc, 0.14, 0.03, GOLD, "z", 10, "Metal", R=Fm)
    m.add("E", "Monocle", (0.26, 0.26, 0.02), mc, (220, 240, 255), "Glass", Fm, 0.6, 0.3)
    m.chain("MonocleChain", [mc + V(0.1, -0.1, 0.0), V(0.36, 4.62, -0.24), V(0.4, 4.32, -0.26), V(0.28, 4.04, surf(0.28, 4.04) - 0.03)], 0.025, GOLD, "Metal")
    # the top hat
    with m.group(R=rot(z=-7, x=-4), t=(0.02, 5.36, 0.0)):
        m.cyl("HatBrim", 0.05, 1.0, V(0, 0, 0), black, "y")
        for sd in (-1, 1):
            m.ell("HatBrim", (0.22, 0.1, 0.84), V(sd * 0.44, 0.04, 0), black, R=rot(z=sd * 24))
        m.cyl("Hat", 0.72, 0.66, V(0, 0.38, 0), black, "y", refl=0.1)
        m.cyl("HatBand", 0.15, 0.68, V(0, 0.12, 0), velvet, "y", "Fabric")
        hg = m.ell("HatGem", (0.14, 0.16, 0.06), V(0, 0.12, -0.345), ECTO, "Neon")
    m.light(hg, (120, 255, 170), 0.8, 5)
    return m
