# Style kit for the Deck Wars remodel: the shared building blocks every model is made of, so the
# whole set looks like one game. Built on modelkit (Roblox primitive parts).
#
# - Group transforms: build a head, a leg or a whole pigeon in its own frame, then turn and move it.
# - Flowing bodies: overlapping ellipsoids along a path (neck into chest into belly).
# - Thick tapered limbs in segments (thigh, knee, shin, foot) and arms (upper arm, elbow, forearm, hand).
# - Big feet: hooves, paws, boots; mitten hands and gloves.
# - Faces with a mood: eye whites, pupils, highlights, half-lids, chunky brows, mouths, muzzles, ears.
# - Details that sit on top of the big shapes: tufts, horns, spikes, plates, gems, trims, straps.
#
# Part names matter: the Pack Brawl rig (src/packbrawl/Rig.luau) finds arms, legs, heads, tails
# and wings by name. Leg pieces use Thigh / Knee / Shin / Ankle / Hoof / Foot / Toe / Sock,
# arm pieces UpperArm / Elbow / Forearm / Cuff / Hand / Thumb / Finger, faces Eye / Pupil / Glint /
# Lid / Lidhalf / Brow / Mouth / Muzzle / Nose / Nostril / Ear / EarInner ...
import math
from contextlib import contextmanager
import numpy as np
from modelkit import Model, rot, Rx, Ry, Rz, frame_from_x, frame_normal, on_ell, shade, lerp, I3, WHITE, PUPIL

V = lambda *a: np.array(a, float)

# ---------------------------------------------------------------------------------------------
# Family palettes: main, second, accent (+ a few helpers), and the family's materials.
# ---------------------------------------------------------------------------------------------
PAL = {
    "Snack": dict(main=(232, 160, 70), second=(255, 238, 214), accent=(230, 45, 70), pink=(244, 110, 150),
                  mint=(120, 220, 190), choc=(110, 62, 40), gold=(255, 200, 70), glaze=0.12),
    "Junk": dict(main=(178, 92, 48), second=(78, 128, 120), accent=(246, 196, 38), tin=(170, 176, 182),
                 dark=(62, 58, 56), rubber=(40, 38, 40)),
    "Weather": dict(main=(110, 180, 250), second=(238, 244, 252), accent=(255, 220, 50), slate=(84, 96, 128),
                    storm=(120, 132, 160), ice=(190, 230, 255)),
    "Critter": dict(main=(170, 112, 70), second=(250, 230, 200), accent=(205, 50, 45), leaf=(110, 180, 80),
                    dark=(92, 58, 38), pink=(240, 150, 160)),
    "Spooky": dict(main=(226, 220, 250), second=(74, 46, 120), accent=(110, 255, 160), shadow=(150, 130, 200),
                   bone=(240, 232, 214), orange=(255, 140, 40)),
    "Robo": dict(main=(188, 194, 204), second=(56, 168, 176), accent=(255, 128, 40), dark=(58, 62, 72),
                 light=(232, 236, 242), glass=(140, 220, 240)),
}
GOLD = (255, 196, 60)
SILVER = (205, 210, 220)
INK = (34, 26, 38)


def norm(v):
    v = np.array(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


class SModel(Model):
    """Model with group transforms and the style helpers."""

    # -- groups --------------------------------------------------------------------------------
    @contextmanager
    def group(self, R=None, t=(0, 0, 0), scale=1.0):
        """Parts added inside are built in a local frame, then scaled, turned by R and moved by t."""
        start = len(self.parts)
        e0 = len(self.effects)
        yield
        R = I3 if R is None else np.array(R, float)
        t = np.array(t, float)
        for p in self.parts[start:]:
            pos = np.array(p["pos"], float) * scale
            p["pos"] = tuple(R @ pos + t)
            p["R"] = R @ p["R"]
            if scale != 1.0:
                p["size"] = tuple(float(v) * scale for v in p["size"])

    def mirror_x(self, start):
        """Mirror parts from index `start` across x = 0 (adds the copies)."""
        M = np.diag([-1.0, 1, 1])
        for p in list(self.parts[start:]):
            q = dict(p)
            q["pos"] = (-p["pos"][0], p["pos"][1], p["pos"][2])
            # reflect the orientation: R' = M R M (keeps a proper rotation)
            q["R"] = M @ p["R"] @ M
            self.parts.append(q)

    # -- shapes ---------------------------------------------------------------------------------
    def seg(self, name, a, b, r, color, mat="SmoothPlastic", r2=None, ext=0.0, bulge=0.5, shape="E", tr=0, refl=0, spin=0.0):
        """An ellipsoid (or cylinder / block) from a to b with radius r (r2 across the other way).
        bulge < 0.5 puts the widest point nearer a (tapering towards b); the far end stays at b."""
        a = np.array(a, float); b = np.array(b, float)
        v = b - a
        L = float(np.linalg.norm(v))
        if L < 1e-6:
            return self.ball(name, 2 * r, a, color, mat, tr, refl)
        c = a + v * bulge
        half = max(bulge, 1 - bulge) * L + ext
        Rf = frame_from_x(v) @ Rx(spin)
        r2 = r if r2 is None else r2
        if shape == "C":
            return self.add("C", name, (2 * half, 2 * r, 2 * r), c, color, mat, Rf, tr, refl)
        return self.add(shape, name, (2 * half, 2 * r, 2 * r2), c, color, mat, Rf, tr, refl)

    def flow(self, name, pts, radii, color, mat="SmoothPlastic", refl=0.0, between=True):
        """A flowing body along a path: an ellipsoid at every point (radii (rx, ry, rz) or r) turned
        along the path, plus a joining piece between points so there are no waists or seams."""
        P = [np.array(p, float) for p in pts]
        n = len(P)
        RR = []
        for i in range(n):
            if n == 1:
                d = np.array([0, 0, -1.0])
            elif i == 0:
                d = P[1] - P[0]
            elif i == n - 1:
                d = P[-1] - P[-2]
            else:
                d = P[i + 1] - P[i - 1]
            RR.append(radii[i] if isinstance(radii[i], (tuple, list)) else (radii[i], radii[i], radii[i]))
            rx, ry, rz = RR[-1]
            # local x along the path, y up-ish
            F = frame_from_x(d)
            # keep the "up" axis as close to world up as possible
            up = np.array([0, 1.0, 0])
            xa = norm(d)
            ya = up - xa * (up @ xa)
            if np.linalg.norm(ya) < 1e-3:
                ya = np.array([0, 0, 1.0]) - xa * xa[2]
            ya = norm(ya)
            za = np.cross(xa, ya)
            F = np.column_stack([xa, ya, za])
            self.add("E", name, (2 * rz, 2 * ry, 2 * rx), P[i], color, mat, F @ Ry(90), 0, refl)
        if between:
            for i in range(n - 1):
                a, b = P[i], P[i + 1]
                r0 = np.mean(RR[i][:2]); r1 = np.mean(RR[i + 1][:2])
                rr = (r0 + r1) / 2 * 0.92
                self.seg(name, a, b, rr, color, mat, r2=(RR[i][0] + RR[i + 1][0]) / 2 * 0.92, refl=refl)

    def puffs(self, name, center, size, n, d, color, seed=1, ymin=-1.0, zmax=1.0, mat="SmoothPlastic", out=0.18, jitter=0.25, R=None, refl=0.0, keep=None, shade_k=None):
        """Fluffy balls on the surface of an ellipsoid (wool, cloud, fur clumps)."""
        import random
        rnd = random.Random(seed)
        c = np.array(center, float)
        h = np.array(size, float) / 2
        R = I3 if R is None else np.array(R, float)
        # golden-spiral points for an even spread
        placed = 0
        k = 0
        total = n * 6
        while placed < n and k < total:
            k += 1
            i = rnd.random() * total
            y = 1 - 2 * (i + 0.5) / total
            rr = math.sqrt(max(0, 1 - y * y))
            th = math.pi * (3 - math.sqrt(5)) * i
            v = np.array([math.cos(th) * rr, y, math.sin(th) * rr])
            if v[1] < ymin or v[2] > zmax or (keep is not None and not keep(v)):
                continue
            p = c + R @ (v * h)
            nn = norm(R @ (v / (h * h)))
            dd = d * (1 + rnd.uniform(-jitter, jitter))
            col = color
            if shade_k:
                # puffs higher up catch more light: a little lighter on top, darker underneath
                col = shade(color, 1 + shade_k * v[1])
            self.ball(name, dd, p + nn * dd * (out - 0.5) * 0.5, col, mat, refl=refl)
            placed += 1

    def tuft(self, name, base, direction, length, width, color, n=3, spread=28, mat="SmoothPlastic", seed=0):
        """A tuft of fur / hair / feathers: n pointed blobs fanning out from base."""
        d = norm(direction)
        side = norm(np.cross(d, [0, 0, 1.0]) if abs(d[2]) < 0.9 else np.cross(d, [1.0, 0, 0]))
        for k in range(n):
            a = math.radians((k - (n - 1) / 2) * spread)
            dk = norm(d * math.cos(a) + side * math.sin(a))
            L = length * (1.0 - 0.18 * abs(k - (n - 1) / 2))
            self.seg(name, base, np.array(base, float) + dk * L, width * 0.5, color, mat, bulge=0.3)

    def horn(self, name, base, tip, r, color, curve=(0, 0, 0), mat="SmoothPlastic", n=3):
        """A tapered, slightly curved horn from base to tip (r at the base)."""
        a = np.array(base, float); b = np.array(tip, float); cv = np.array(curve, float)
        pts = [a + (b - a) * t + cv * math.sin(math.pi * t) for t in np.linspace(0, 1, n + 1)]
        for i in range(n):
            rr = r * (1 - i / (n + 0.4))
            self.seg(name, pts[i], pts[i + 1], rr, color, mat, bulge=0.35, ext=rr * 0.3)

    def spike(self, name, base, direction, length, r, color, mat="SmoothPlastic"):
        """A pointed spike: a fat base and a thin point."""
        a = np.array(base, float)
        b = a + norm(direction) * length
        self.seg(name, a, a + (b - a) * 0.55, r, color, mat, bulge=0.3)
        self.seg(name, a + (b - a) * 0.35, b, r * 0.5, color, mat, bulge=0.25)

    def crystal(self, name, base, direction, length, w, color, mat="Glass", tr=0.0, refl=0.2, spin=0.0):
        """A faceted crystal: a turned square prism with a pyramid point (two wedges)."""
        a = np.array(base, float)
        d = norm(direction)
        body = length * 0.72
        F = frame_from_x(d) @ Rx(45 + spin)
        c = a + d * body / 2
        self.add("B", name, (body, w, w), c, color, mat, F, tr, refl)
        # the point: two wedges meeting at a ridge
        tipL = length - body
        tc = a + d * (body + tipL / 2)
        Fw = np.column_stack([F[:, 1], d, F[:, 2]])  # wedge's y along the crystal
        for s in (1, -1):
            Rw = Fw @ Ry(90 if s > 0 else -90)
            self.add("W", name, (w, tipL, w / 2), tc + F[:, 2] * (s * w / 4), color, mat, Rw, tr, refl)

    # -- limbs ----------------------------------------------------------------------------------
    def leg(self, hip, knee, ankle, r_top, r_knee, r_low, color, names=("Thigh", "Knee", "Shin", "Ankle"), mat="SmoothPlastic", knee_color=None, refl=0.0):
        """A thick tapered leg: a bulging thigh, a knee, a slimmer shin, an ankle."""
        self.seg(names[0], hip, knee, r_top, color, mat, bulge=0.38, ext=r_top * 0.15, refl=refl)
        self.ball(names[1], r_knee * 2, knee, knee_color or color, mat, refl=refl)
        self.seg(names[2], knee, ankle, r_low, color, mat, bulge=0.42, ext=r_low * 0.2, refl=refl)
        self.ball(names[3], r_low * 1.7, ankle, color, mat, refl=refl)

    def arm(self, shoulder, elbow, wrist, r_top, r_elbow, r_low, color, names=("UpperArm", "Elbow", "Forearm", "Cuff"), mat="SmoothPlastic", refl=0.0, cuff=None):
        """A chunky arm: a round shoulder, upper arm, elbow, a forearm that widens to the wrist."""
        self.ball("Shoulder", r_top * 2.1, shoulder, color, mat, refl=refl)
        self.seg(names[0], shoulder, elbow, r_top, color, mat, bulge=0.45, refl=refl)
        self.ball(names[1], r_elbow * 2, elbow, color, mat, refl=refl)
        # forearms get a little thicker towards the hand (cartoon "popeye" taper)
        self.seg(names[2], elbow, wrist, r_low, color, mat, bulge=0.62, refl=refl)
        if cuff:
            self.seg(names[3], np.array(wrist, float) + (np.array(elbow, float) - np.array(wrist, float)) * 0.18, wrist, r_low * 1.25, cuff, mat, bulge=0.5)

    def hoof(self, at, r, color, sock=None, notch=True, mat="SmoothPlastic"):
        """A big hoof standing on the ground at `at` (x, z): wider than the shin, rounded top."""
        x, z = at[0], at[-1]
        h = r * 1.0
        self.cyl("Hoof", h, r * 2.1, (x, h / 2, z), color, "y", mat)
        self.ell("Hoof", (r * 2.04, r * 1.0, r * 2.04), (x, h, z), color, mat)
        if notch:
            self.blk("Hoof", (r * 0.12, h * 0.8, r * 0.5), (x, h * 0.42, z - r * 0.85), shade(color, 0.55), mat)
        if sock is not None:
            self.ell("Sock", (r * 2.0, r * 1.0, r * 2.0), (x, h + r * 0.35, z), sock, mat)

    def paw(self, at, r, color, toe_color=None, toes=3, y=0.0, mat="SmoothPlastic", name="Foot", forward=(0, 0, -1)):
        """A big round paw on the ground with toe bumps at the front."""
        x, z = at[0], at[-1]
        f = norm(forward)
        self.ell(name, (r * 2.2, r * 1.15, r * 2.5), (x + f[0] * r * 0.2, y + r * 0.55, z + f[2] * r * 0.25), color, mat)
        tc = toe_color or color
        side = np.array([-f[2], 0, f[0]])
        for k in range(toes):
            o = (k - (toes - 1) / 2) * r * 0.62
            p = np.array([x, y + r * 0.42, z]) + f * r * 1.15 + side * o
            self.ball("Toe", r * 0.62, p, tc, mat)

    def boot(self, at, w, l, color, sole=(45, 38, 42), cuff=None, toe=None, y=0.0, mat="SmoothPlastic", name="Boot"):
        """A chunky cartoon boot: a fat rounded upper, a thick sole, an optional cuff and toe cap."""
        x, z = at[0], at[-1]
        h = w * 0.62
        self.ell(name, (w, h * 1.5, l), (x, y + h * 0.62, z - l * 0.06), color, mat)
        self.blk("Sole", (w * 0.96, h * 0.3, l * 0.9), (x, y + h * 0.15, z - l * 0.04), sole, "Rubber")
        if toe is not None:
            self.ell("Toe", (w * 0.86, h * 1.0, l * 0.5), (x, y + h * 0.55, z - l * 0.28), toe, mat)
        if cuff is not None:
            # "Spat", not "Cuff": the rig reads "Cuff" as part of an arm
            self.cyl("Spat", h * 0.45, w * 0.82, (x, y + h * 1.25, z + l * 0.06), cuff, "y", mat)

    def glove(self, at, r, color, side, fist=False, fingers=3, thumb=True, mat="SmoothPlastic", name="Hand", forward=(0, 0, -1)):
        """A big mitten hand: a round palm, finger bumps and a thumb pointing forward/in."""
        p = np.array(at, float)
        f = norm(forward)
        self.ell(name, (r * 2.0, r * 2.1, r * 1.9), p, color, mat)
        inward = np.array([-side, 0, 0.0])
        if thumb:
            self.seg("Thumb", p + inward * r * 0.4 + f * r * 0.3, p + inward * r * 0.95 + f * r * 0.55 + np.array([0, r * 0.35, 0]), r * 0.38, color, mat, bulge=0.4)
        if fingers and not fist:
            for k in range(fingers):
                o = (k - (fingers - 1) / 2) * r * 0.55
                q = p + np.array([o * side * 0.2 + o * 0.8, -r * 0.75, 0]) + f * r * 0.35
                self.ball("Finger", r * 0.62, q, color, mat)
        elif fist:
            for k in range(fingers):
                o = (k - (fingers - 1) / 2) * r * 0.55
                q = p + np.array([o, -r * 0.05, 0]) + f * r * 0.8
                self.ball("Knuckle", r * 0.6, q, color, mat)

    # -- faces ----------------------------------------------------------------------------------
    MOODS = {
        # open: how much of the eye shows under the upper lid (1 = wide open)
        # lid: tilt of the lid line, brow: tilt of the brows (+ = inner ends lower: cross, angry;
        # - = inner ends higher: happy, worried), lift: brow height (fractions of the eye height)
        # mouth: shape, curve: smile (+) / frown (-), look: pupils (x to the creature's left, y up)
        "cheerful": dict(open=1.0, lid=0, brow=-10, lift=0.22, mouth="smile", curve=0.28),
        "eager": dict(open=1.0, lid=0, brow=-14, lift=0.32, mouth="open", curve=0.25),
        "proud": dict(open=0.64, lid=4, brow=-10, lift=0.3, mouth="smirk", curve=0.2),
        "grumpy": dict(open=0.58, lid=16, brow=24, lift=0.02, mouth="frown", curve=-0.22),
        "stern": dict(open=0.72, lid=8, brow=16, lift=0.08, mouth="flat", curve=0.0),
        "sly": dict(open=0.55, lid=4, brow=10, lift=0.18, mouth="smirk", curve=0.24, look=(0.18, 0)),
        "goofy": dict(open=1.0, lid=0, brow=-18, lift=0.35, mouth="open", curve=0.3, cross=True),
        "fierce": dict(open=0.8, lid=14, brow=26, lift=0.0, mouth="teeth", curve=0.05),
        "sleepy": dict(open=0.38, lid=-4, brow=-6, lift=0.2, mouth="small", curve=0.15),
        "shy": dict(open=0.9, lid=-6, brow=-14, lift=0.28, mouth="small", curve=0.22, look=(0, -0.2)),
        "determined": dict(open=0.82, lid=10, brow=18, lift=0.06, mouth="flat", curve=0.06),
        "smug": dict(open=0.52, lid=-6, brow=-6, lift=0.3, mouth="smirk", curve=0.26),
        "manic": dict(open=1.0, lid=0, brow=20, lift=0.1, mouth="teeth", curve=0.3, cross=True),
        "regal": dict(open=0.7, lid=-4, brow=-8, lift=0.32, mouth="smile", curve=0.14),
        "menacing": dict(open=0.66, lid=12, brow=22, lift=0.0, mouth="teeth", curve=-0.05),
        "worried": dict(open=0.95, lid=-6, brow=-22, lift=0.3, mouth="frown", curve=-0.12),
    }

    def eye(self, at, normal, w, h, skin, mood="cheerful", side=1, iris=None, pupil=PUPIL, white=WHITE, look=(0, 0),
            lash=0, lash_color=None, depth=None, pupil_k=0.56, blink=False, brow=None, brow_k=1.0, lid_color=None, glow=False,
            inward=0.08, lidline=True, sink=0.12, open_=None):
        """One cartoon eye on a surface point `at` with outward `normal`."""
        md = self.MOODS[mood] if isinstance(mood, str) else mood
        n = norm(normal)
        up = np.array([0, 1.0, 0]) - n * n[1]
        up = norm(up) if np.linalg.norm(up) > 1e-3 else np.array([0, 0, 1.0])
        xa = np.cross(up, n)
        F = np.column_stack([xa, up, n])  # x: across (to the viewer's right), y: up, z: out of the face
        # which side of the face (world x) the eye is on: tilts mirror between the two eyes
        sx = float(np.sign(at[0])) if abs(at[0]) > 1e-4 else float(side)
        dz = depth or min(w, h) * 0.55
        c = np.array(at, float) + n * dz * sink
        ex, ey, ez = F[:, 0], F[:, 1], F[:, 2]
        self.add("E", "Eye", (w, h, dz), c, white, "Neon" if glow else "SmoothPlastic", F)
        lk = md.get("look", (0, 0))
        lx, ly = look[0] + lk[0], look[1] + lk[1]
        lx -= sx * (inward + (0.16 if md.get("cross") else 0.0))
        wx = np.array([1.0, 0, 0]) - n * n[0]
        wx = norm(wx) if np.linalg.norm(wx) > 1e-3 else -ex
        pw, ph = w * pupil_k, h * pupil_k * 1.05
        pc = c + ez * dz * 0.36 + wx * lx * w + ey * ly * h
        if iris is not None:
            self.add("E", "Iris", (pw * 1.35, ph * 1.35, dz * 0.42), pc - ez * dz * 0.02, iris, "SmoothPlastic", F)
            self.add("E", "Pupil", (pw * 0.75, ph * 0.75, dz * 0.42), pc + ez * dz * 0.02, pupil, "SmoothPlastic", F)
        else:
            self.add("E", "Pupil", (pw, ph, dz * 0.42), pc, pupil, "SmoothPlastic", F)
        g = max(min(pw, ph) * 0.42, 0.03)
        g2 = max(g * 0.5, 0.024)
        self.add("E", "Glint", (g, g, max(g * 0.6, 0.024)), pc + ez * dz * 0.12 - ex * pw * 0.22 + ey * ph * 0.26, WHITE, "SmoothPlastic", F)
        self.add("E", "Glint", (g2, g2, max(g * 0.4, 0.024)), pc + ez * dz * 0.12 + ex * pw * 0.2 - ey * ph * 0.22, WHITE, "SmoothPlastic", F)
        lidc = lid_color or skin
        o = md.get("open", 1.0) if open_ is None else open_
        # lid tilt: + lowers the inner corner. The inner corner of the eye on the creature's
        # left (+x) is towards the viewer's right (+ex), so it turns the other way round there
        tilt = -sx * md.get("lid", 0)
        Rl = F @ Rz(tilt)
        yl = (o - 0.5) * h
        if o < 0.97:
            # the upper lid: a skin cap barely deeper than the eye, slid up so the two surfaces
            # cross right at the lid line (o = how much of the eye still shows)
            bk = 1.04
            k = 1 - (1 / bk) ** 2 * (1 - (yl / (0.5 * h)) ** 2)
            yc = yl + 0.53 * h * math.sqrt(max(k, 0.0))
            self.add("E", "Lidhalf", (w * 1.06, h * 1.06, dz * bk), c + Rl[:, 1] * yc, lidc, "SmoothPlastic", Rl)
            if lidline:
                # a dark line along the lid's edge so the half-closed eye reads clearly
                q = math.sqrt(max(1 - (yl / (0.5 * h)) ** 2, 0.05))
                xe = 0.5 * w * q * 0.98
                zm = 0.5 * dz * q
                lc_ = lash_color or shade(lidc, 0.45)
                pL = c + Rl @ np.array([-xe, yl, zm * 0.25])
                pM = c + Rl @ np.array([0, yl, zm * 1.02])
                pR = c + Rl @ np.array([xe, yl, zm * 0.25])
                th = max(h * 0.07, 0.02)
                self.seg("Lash", pL, pM, th, lc_, bulge=0.5, ext=th * 0.4)
                self.seg("Lash", pM, pR, th, lc_, bulge=0.5, ext=th * 0.4)
        if blink:
            self.add("E", "Lid", (w * 1.14, h * 1.12, dz * 1.3), c + ez * dz * 0.1, lidc, "SmoothPlastic", F, 1)
        # lashes flick out from the outer corner (at the lid line when the eye is half closed)
        outer = -sx  # outer corner of the eye on +x is towards -ex
        top = min(yl, 0.5 * h * 0.8) if o < 0.97 else 0.5 * h * 0.55
        for k in range(lash):
            a = math.radians(14 + 30 * k)
            q = math.sqrt(max(1 - (top / (0.5 * h)) ** 2, 0.1))
            b0 = c + Rl @ np.array([outer * 0.5 * w * q * 0.92, top, 0.5 * dz * q * 0.3])
            b1 = b0 + Rl @ np.array([outer * math.cos(a) * w * 0.3, math.sin(a) * h * 0.3, dz * 0.08])
            self.seg("Lash", b0, b1, max(w * 0.06, 0.02), lash_color or INK, bulge=0.3)
        if brow is not None:
            bt = -sx * md.get("brow", 0)
            lift = md.get("lift", 0.2)
            bw = w * 1.08 * brow_k
            bc = c + ey * (h * 0.62 + lift * h) + ez * dz * 0.05
            Rb = F @ Rz(bt)
            self.add("E", "Brow", (bw, h * 0.2 * brow_k, dz * 0.5), bc, brow, "SmoothPlastic", Rb)

    def eyes_on(self, center, size, R, yaw, pitch, w, h, skin, mood="cheerful", **kw):
        """A pair of eyes on an ellipsoid head (center, full size, rotation R), yaw degrees out from
        the middle and pitch degrees up. Returns the two surface points."""
        pts = []
        for s in (-1, 1):
            d = norm(R @ (Ry(s * yaw) @ Rx(pitch) @ np.array([0, 0, -1.0])))
            p, nn = on_ell_R(center, size, R, d)
            self.eye(p, nn, w, h, skin, mood, side=s, **kw)
            pts.append(p)
        return pts

    def mouth(self, center, normal, w, mood="cheerful", color=(70, 28, 40), tongue=(240, 110, 130), teeth=WHITE, d=None, R_face=None, curve=None, side_bias=0.0, fangs=False, skin=None, kind=None):
        """A mouth on a surface point with outward normal. Shapes: smile, smirk, frown, flat, small,
        open (with tongue), teeth (open with teeth)."""
        md = self.MOODS[mood] if isinstance(mood, str) else mood
        kind = kind or md.get("mouth", "smile")
        cv = md.get("curve", 0.2) if curve is None else curve
        n = norm(normal)
        up = np.array([0, 1.0, 0]) - n * n[1]
        up = norm(up) if np.linalg.norm(up) > 1e-3 else np.array([0, 0, 1.0])
        xa = np.cross(up, n)
        c = np.array(center, float)
        d = d or w * 0.14
        if kind in ("open", "teeth"):
            Fm = np.column_stack([xa, up, n])
            self.add("E", "Mouth", (w * 0.85, w * 0.56, w * 0.3), c - up * w * 0.08, color, "SmoothPlastic", Fm)
            self.add("E", "Tongue", (w * 0.5, w * 0.24, w * 0.2), c - up * w * 0.24 + n * w * 0.05, tongue, "SmoothPlastic", Fm)
            if skin is not None:
                # an upper lip in the skin colour flattens the top: a D-shaped grin
                self.add("E", "Lip", (w * 1.0, w * 0.44, w * 0.32), c + up * w * 0.17 + n * w * 0.015, skin, "SmoothPlastic", Fm)
            if kind == "teeth":
                for k in range(4):
                    tx = (k - 1.5) * w * 0.17
                    self.add("B", "Tooth", (w * 0.14, w * 0.13, w * 0.08), c + xa * tx + up * w * 0.1 + n * w * 0.08, teeth, "SmoothPlastic", np.column_stack([xa, up, n]))
            if fangs:
                for s in (-1, 1):
                    self.seg("Fang", c + xa * s * w * 0.28 + up * w * 0.12 + n * w * 0.1, c + xa * s * w * 0.26 - up * w * 0.08 + n * w * 0.1, w * 0.06, teeth, bulge=0.3)
            return
        if kind == "small":
            w = w * 0.55
        pts = []
        for k in range(5):
            u = -1 + k / 2
            yy = cv * w * u * u
            if kind == "smirk":
                yy = cv * w * (0.5 * u * u + 0.35 * u * (1 if side_bias >= 0 else -1))
            if kind == "flat":
                yy = 0
            pts.append(c + xa * u * w / 2 + up * yy)
        self.chain("Mouth", pts, d, color)
        for e in (pts[0], pts[-1]):
            self.ball("Mouth", d * 1.2, e, color)
        if fangs:
            for s in (-1, 1):
                self.seg("Fang", c + xa * s * w * 0.22, c + xa * s * w * 0.22 - up * w * 0.2 + n * w * 0.03, w * 0.07, teeth, bulge=0.3)

    def ear(self, base, tip, w, color, inner=None, depth=None, curve=(0, 0, 0), mat="SmoothPlastic", name="Ear", facing=(0, 0, -1)):
        """A leaf-shaped ear from base to tip, flat side facing `facing`, with an inner ear."""
        a = np.array(base, float); b = np.array(tip, float)
        mid = (a + b) / 2 + np.array(curve, float)
        dz = depth or w * 0.35
        f = norm(facing)
        for (p, q, k) in ((a, mid, 1.0), (mid, b, 0.78)):
            v = q - p
            xa = norm(v)
            za = f - xa * (f @ xa)
            za = norm(za) if np.linalg.norm(za) > 1e-3 else np.array([0, 0, -1.0])
            ya = np.cross(za, xa)
            F = np.column_stack([xa, ya, za])
            L = np.linalg.norm(v)
            self.add("E", name, (L * 1.35, w * k, dz), (p + q) / 2, color, mat, F)
            if inner is not None:
                self.add("E", "EarInner", (L * 1.05, w * k * 0.6, dz * 0.6), (p + q) / 2 + za * dz * 0.28, inner, mat, F)

    def legs2(self, hip_y, sep, color, r_top, r_knee, r_low, foot_w, foot_l, foot_color, z=0.0, sole=(45, 38, 42),
              cuff=None, toe=None, knee_color=None, spread=0.03, mat="SmoothPlastic", foot="boot", ankle_y=None,
              knee_fwd=0.07, toes=3, refl=0.0):
        """Two thick legs standing on the ground (thigh, knee, shin, ankle) with big boots or paws.
        Returns the two ankle points."""
        out = []
        for s in (-1, 1):
            x = s * sep
            ay = ankle_y if ankle_y is not None else foot_w * 0.62
            hip = V(x, hip_y, z)
            knee = V(x + s * spread, (hip_y + ay) / 2 + 0.03, z - knee_fwd)
            ankle = V(x + s * spread * 1.5, ay, z)
            self.leg(hip, knee, ankle, r_top, r_knee, r_low, color, mat=mat, knee_color=knee_color, refl=refl)
            if foot == "boot":
                self.boot((ankle[0], ankle[2]), foot_w, foot_l, foot_color, sole=sole, cuff=cuff, toe=toe)
            elif foot == "paw":
                self.paw((ankle[0], ankle[2] - foot_l * 0.12), foot_w * 0.5, foot_color, toes=toes)
            elif foot == "hoof":
                self.hoof((ankle[0], ankle[2]), foot_w * 0.5, foot_color, sock=cuff)
            out.append(ankle)
        return out

    def arms2(self, sh_y, sep, color, r_top, r_elbow, r_low, hand_r, hand_color, poses, z=0.0, cuff=None, mat="SmoothPlastic",
              refl=0.0, fingers=3):
        """Two chunky arms from shoulders at (+-sep, sh_y, z). poses: {side: (elbow, wrist, fist)} in
        world coordinates. Returns the hand centers by side."""
        hands = {}
        for s in (-1, 1):
            el, wr, fist = poses[s]
            el, wr = V(*el), V(*wr)
            sh = V(s * sep, sh_y, z)
            self.arm(sh, el, wr, r_top, r_elbow, r_low, color, mat=mat, refl=refl, cuff=cuff)
            d = norm(wr - el)
            hc = wr + d * hand_r * 0.75
            self.glove(hc, hand_r, hand_color, s, fist=fist, fingers=fingers, forward=(d[0], 0, d[2]) if abs(d[1]) < 0.95 else (0, 0, -1))
            hands[s] = hc
        return hands

    # -- weather bits ----------------------------------------------------------------------------
    def bolt(self, name, top, h, w=None, t=None, color=(255, 220, 50), mat="Neon", R=None, tr=0.0):
        """A zigzag lightning bolt hanging from `top`, h long: two slanted slabs, a jog and a sharp
        tip. Built flat in the x-y plane (facing -z), turned by R."""
        w = w or h * 0.2
        t = t or w * 0.45
        R = I3 if R is None else np.array(R, float)
        o = np.array(top, float)
        P0, P1, P2, P3 = (np.array([0.16, 0.0]) * h, np.array([-0.1, -0.47]) * h,
                          np.array([0.14, -0.43]) * h, np.array([-0.14, -1.0]) * h)

        def slab(a, b, width, nm):
            v = b - a
            L = float(np.linalg.norm(v))
            ux = np.array([v[0], v[1], 0.0]) / L
            uy = np.array([-ux[1], ux[0], 0.0])
            F = np.column_stack([ux, uy, [0, 0, 1.0]])
            mid = np.array([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0])
            return self.add("B", nm, (L + width * 0.35, width, t), o + R @ mid, color, mat, R @ F, tr)

        first = slab(P0, P1, w, name)
        slab(P1 + np.array([-0.02 * h, 0]), P2 + np.array([0.04 * h, 0]), w * 0.85, name)
        # the tip: a wedge whose sharp corner is at P3 and whose wide end sits at P2
        u3 = np.array([P2[0] - P3[0], P2[1] - P3[1], 0.0])
        L3 = float(np.linalg.norm(u3)); u3 /= L3
        v3 = np.array([u3[1], -u3[0], 0.0])  # across, towards the bolt's left
        Fw = np.column_stack([[0, 0, 1.0], v3, u3])
        cw = np.array([P3[0], P3[1], 0.0]) + v3 * (w * 1.1 / 2) + u3 * (L3 / 2)
        self.add("W", name, (t, w * 1.1, L3), o + R @ cw, color, mat, R @ Fw, tr)
        return first

    def drop(self, name, pos, d, color=(110, 180, 250), mat="Glass", tr=0.15, refl=0.3):
        """A teardrop: a round bottom and a pointed top."""
        p = np.array(pos, float)
        self.ball(name, d, p, color, mat, tr, refl)
        self.seg(name, p + np.array([0, d * 0.05, 0]), p + np.array([0, d * 1.05, 0]), d * 0.36, color, mat, bulge=0.2, tr=tr, refl=refl)

    # -- details ---------------------------------------------------------------------------------
    def plate(self, name, center, size, color, normal=(0, 0, -1), r=None, mat="Metal", rivets=None, spin=0.0):
        """An armour plate lying on a surface: a rounded slab, optional rivets at the corners."""
        F = frame_normal(normal, spin)
        sx, sy, sz = size
        self.add("E", name, (sx * 1.04, sy * 1.04, sz), center, color, "SmoothPlastic", F)
        self.add("B", name, (sx * 0.86, sy * 0.86, sz * 0.7), np.array(center, float) + F[:, 2] * sz * 0.12, color, mat, F)
        if rivets:
            for ix in (-1, 1):
                for iy in (-1, 1):
                    p = np.array(center, float) + F[:, 0] * ix * sx * 0.34 + F[:, 1] * iy * sy * 0.34 + F[:, 2] * sz * 0.42
                    self.ball(name + "Rivet", min(sx, sy) * 0.12, p, rivets, "Metal")

    def trim_ring(self, name, center, radius, thick, color, normal="y", segments=12, mat="SmoothPlastic", R=None):
        self.ring(name, center, radius, thick, color, normal, segments, mat, R, outer=True)


def on_ell_R(center, size, R, direction):
    """Point on a turned ellipsoid's surface in a world direction from its middle, and the normal there."""
    R = np.array(R, float)
    dl = R.T @ norm(direction)
    p, nn = on_ell((0, 0, 0), size, dl)
    return np.array(center, float) + R @ p, norm(R @ nn)


def model(fn):
    fn.is_model = True
    return fn
