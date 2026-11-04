# Tiny modeling kit for Deck Wars creatures, gadgets and heroes.
# Models are built from Roblox primitive parts. Units are studs.
# Convention: the model stands on y = 0, centered on x = 0, z = 0, and faces -Z (its front).
import math
import numpy as np

I3 = np.eye(3)


def Rx(d):
    a = math.radians(d); c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(d):
    a = math.radians(d); c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def Rz(d):
    a = math.radians(d); c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def rot(x=0, y=0, z=0):
    """Same order as Roblox CFrame.Angles(x, y, z): R = Rx * Ry * Rz."""
    return Rx(x) @ Ry(y) @ Rz(z)


def euler_xyz(R):
    """Inverse of rot(): degrees (x, y, z) with R = Rx(x) Ry(y) Rz(z)."""
    sb = max(-1.0, min(1.0, R[0, 2]))
    b = math.asin(sb)
    if abs(math.cos(b)) > 1e-6:
        a = math.atan2(-R[1, 2], R[2, 2])
        c = math.atan2(-R[0, 1], R[0, 0])
    else:
        a = math.atan2(R[2, 1], R[1, 1])
        c = 0.0
    return tuple(math.degrees(v) for v in (a, b, c))


def frame_from_x(direction):
    """Rotation whose local X axis points along `direction` (used for cylinders between two points)."""
    d = np.array(direction, float)
    d /= np.linalg.norm(d)
    helper = np.array([0, 1, 0]) if abs(d[1]) < 0.9 else np.array([1, 0, 0])
    y = helper - d * np.dot(helper, d)
    y /= np.linalg.norm(y)
    z = np.cross(d, y)
    return np.column_stack([d, y, z])


def frame_normal(n, spin=0.0):
    """Rotation whose local Z axis points along n (for flat details lying on a surface)."""
    z = np.array(n, float)
    z /= np.linalg.norm(z)
    helper = np.array([0, 1, 0]) if abs(z[1]) < 0.9 else np.array([1, 0, 0])
    x = np.cross(helper, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    R = np.column_stack([x, y, z])
    return R @ Rz(spin)


def on_ell(center, size, direction):
    """Point on the surface of an ellipsoid (center, full size) in a direction, and the surface normal there."""
    c = np.array(center, float)
    h = np.array(size, float) / 2
    d = np.array(direction, float)
    d /= np.linalg.norm(d)
    t = 1.0 / math.sqrt(float(((d / h) ** 2).sum()))
    p = c + d * t
    nrm = (d * t) / (h * h)
    return p, nrm / np.linalg.norm(nrm)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def shade(c, f):
    """Darker (f < 1) or lighter (f > 1) version of a color."""
    if f <= 1:
        return tuple(max(0, min(255, int(v * f))) for v in c)
    return tuple(max(0, min(255, int(v + (255 - v) * (f - 1)))) for v in c)


AXIS = {"x": I3, "y": Rz(90), "z": Ry(90)}

# Handy colors
WHITE = (255, 255, 255)
BLACK = (25, 22, 30)
PUPIL = (30, 25, 35)
PINK_CHEEK = (255, 140, 160)


class Model:
    def __init__(self, mid, kind="creature"):
        self.id = mid
        self.kind = kind
        self.parts = []
        self.effects = []

    # Core primitive. shape: B block, S ball, E ellipsoid (block + sphere mesh), C cylinder, W wedge
    def add(self, shape, name, size, pos, color, mat="SmoothPlastic", R=None, tr=0.0, refl=0.0):
        size = tuple(float(v) for v in size)
        if shape == "S":
            d = min(size)
            size = (d, d, d)
        if shape == "C":
            d = min(size[1], size[2])
            size = (size[0], d, d)
        self.parts.append(dict(shape=shape, name=name, size=size, pos=tuple(float(v) for v in pos),
                               color=tuple(int(round(c)) for c in color), mat=mat,
                               R=I3 if R is None else np.array(R, float), tr=float(tr), refl=float(refl)))
        return len(self.parts)  # 1-based index, used by effects

    def blk(self, name, size, pos, color, mat="SmoothPlastic", R=None, tr=0, refl=0):
        return self.add("B", name, size, pos, color, mat, R, tr, refl)

    def ball(self, name, d, pos, color, mat="SmoothPlastic", tr=0, refl=0):
        return self.add("S", name, (d, d, d), pos, color, mat, None, tr, refl)

    def ell(self, name, size, pos, color, mat="SmoothPlastic", R=None, tr=0, refl=0):
        return self.add("E", name, size, pos, color, mat, R, tr, refl)

    def cyl(self, name, length, d, pos, color, axis="y", mat="SmoothPlastic", R=None, tr=0, refl=0):
        Rf = (I3 if R is None else np.array(R, float)) @ AXIS[axis]
        return self.add("C", name, (length, d, d), pos, color, mat, Rf, tr, refl)

    def wedge(self, name, size, pos, color, mat="SmoothPlastic", R=None, tr=0, refl=0):
        return self.add("W", name, size, pos, color, mat, R, tr, refl)

    def rod(self, name, p1, p2, d, color, mat="SmoothPlastic", tr=0, refl=0, shape="C"):
        p1 = np.array(p1, float); p2 = np.array(p2, float)
        v = p2 - p1
        L = float(np.linalg.norm(v))
        mid = (p1 + p2) / 2
        Rf = frame_from_x(v)
        if shape == "C":
            return self.add("C", name, (L, d, d), mid, color, mat, Rf, tr, refl)
        if shape == "E":
            return self.add("E", name, (L, d, d), mid, color, mat, Rf, tr, refl)
        return self.add("B", name, (L, d, d), mid, color, mat, Rf, tr, refl)

    def chain(self, name, points, d, color, mat="SmoothPlastic", joints=True):
        """A bendy tube through several points (noodles, tails, necks)."""
        for i in range(len(points) - 1):
            self.rod(name, points[i], points[i + 1], d, color, mat)
            if joints and i > 0:
                self.ball(name, d, points[i], color, mat)

    def ring(self, name, center, radius, thickness, color, normal="z", segments=10, mat="SmoothPlastic", R=None, tr=0, refl=0):
        """A ring (torus-ish) made of short rods. normal is the ring's axis."""
        c = np.array(center, float)
        Rn = {"x": Ry(90), "y": Rx(90), "z": I3}[normal]
        if R is not None:
            Rn = np.array(R, float) @ Rn
        pts = []
        for k in range(segments):
            a = 2 * math.pi * k / segments
            pts.append(c + Rn @ np.array([math.cos(a) * radius, math.sin(a) * radius, 0]))
        for k in range(segments):
            p1, p2 = pts[k], pts[(k + 1) % segments]
            v = p2 - p1
            # stretch slightly so the segments overlap without gaps
            self.rod(name, p1 - v * 0.08, p2 + v * 0.08, thickness, color, mat, tr, refl)

    # Faces --------------------------------------------------------------
    def eyes(self, y, zf, sep, d, lid=None, x=0.0, look=(0.0, 0.0), pupil=PUPIL, white=WHITE, pupil_scale=0.55, tilt=0.0, angry=0.0, sleepy=False,
             iris=None, lash=0, lash_color=None, rim=None, bulge=0.55, z_back=0.0):
        """Two cartoon eyes on a surface whose front is at z = zf (facing -Z).
        lid: color of the hidden eyelids used for blinking (None = no blinking).
        iris: color ring around the pupil. lash: number of lashes per eye. rim: thin dark outline color.
        z_back: how far the outer eye sits further back (for eyes on round faces)."""
        for s in (-1, 1):
            ex = x + s * sep / 2
            ez = zf + z_back
            Rt = Rz(-s * tilt) @ Ry(s * z_back * 40)
            if rim is not None:
                self.ell("EyeRim", (d * 1.12, d * 1.24, d * bulge * 0.9), (ex, y, ez - d * 0.02), rim, R=Rt)
            self.ell("Eye", (d, d * 1.12, d * bulge), (ex, y, ez - d * 0.05), white, R=Rt)
            pd = d * pupil_scale
            px, py = ex + look[0], y + look[1] - (d * 0.08 if sleepy else 0)
            if iris is not None:
                self.ell("Iris", (pd * 1.45, pd * 1.55, d * 0.3), (px, py, ez - d * (bulge * 0.42)), iris, R=Rt)
                self.ell("Pupil", (pd * 0.82, pd * 0.9, d * 0.3), (px, py, ez - d * (bulge * 0.42 + 0.03)), pupil, R=Rt)
            else:
                self.ell("Pupil", (pd, pd * 1.1, d * 0.3), (px, py, ez - d * (bulge * 0.42 + 0.02)), pupil, R=Rt)
            gz = ez - d * (bulge * 0.42 + 0.1)
            self.ell("Glint", (max(pd * 0.4, 0.035), max(pd * 0.4, 0.035), max(d * 0.12, 0.025)), (px + pd * 0.22, py + pd * 0.28, gz), white)
            self.ell("Glint", (max(pd * 0.18, 0.025), max(pd * 0.18, 0.025), max(d * 0.08, 0.02)), (px - pd * 0.22, py - pd * 0.25, gz), white)
            if lid is not None:
                self.ell("Lid", (d * 1.18, d * 1.28, d * max(bulge, 0.55) * 1.7), (ex, y, ez - d * 0.06), lid, R=Rt, tr=1)
            if angry:
                # slanted brow
                self.blk("Brow", (d * 1.05, d * 0.2, d * 0.2), (ex, y + d * 0.68, ez - d * 0.2), pupil, R=Rz(s * angry))
            if sleepy:
                self.ell("Lidhalf", (d * 1.1, d * 0.62, d * 0.62), (ex, y + d * 0.3, ez - d * 0.08), lid or (200, 200, 200))
            lc = lash_color or pupil
            for k in range(lash):
                a = math.radians(55 + 28 * k)
                bx, by = ex + s * math.cos(a) * d * 0.5, y + math.sin(a) * d * 0.56
                self.rod("Lash", (bx, by, ez - d * 0.1), (bx + s * math.cos(a) * d * 0.32, by + math.sin(a) * d * 0.3, ez - d * 0.05), max(d * 0.07, 0.025), lc)

    def smile(self, y, zf, w, color=(60, 25, 35), x=0.0, open_=False, tongue=(240, 110, 130)):
        if open_:
            self.ell("Mouth", (w, w * 0.55, w * 0.25), (x, y, zf + w * 0.02), color)
            self.ell("Tongue", (w * 0.55, w * 0.25, w * 0.15), (x, y - w * 0.12, zf - w * 0.07), tongue)
        else:
            self.ell("Mouth", (w, w * 0.28, w * 0.2), (x, y, zf), color)

    def cheeks(self, y, zf, sep, d, color=PINK_CHEEK):
        for s in (-1, 1):
            self.ell("Cheek", (d, d * 0.6, d * 0.25), (s * sep / 2, y, zf), color, tr=0.25)

    def grin(self, y, zf, w, color=(60, 25, 35), x=0.0, curve=0.22, d=None, bend=0.0, teeth=0, open_=False, tongue=(240, 110, 130), tooth=WHITE, name="Mouth", segments=5):
        """A curved smile line (ends higher than the middle when curve > 0; frown when < 0).
        bend pushes the ends back into a round face. teeth: number of top teeth (open mouths)."""
        d = d or w * 0.13
        pts = []
        for k in range(segments):
            u = -1 + 2 * k / (segments - 1)
            pts.append((x + u * w / 2, y + curve * w * u * u, zf + bend * u * u))
        if open_:
            # open mouth: dark inside, tongue, teeth on top
            self.ell(name, (w * 0.9, w * 0.5, w * 0.22), (x, y + curve * w * 0.25 - w * 0.12, zf + bend * 0.2 + w * 0.02), color)
            self.ell("Tongue", (w * 0.5, w * 0.2, w * 0.14), (x, y + curve * w * 0.25 - w * 0.25, zf + bend * 0.2 - w * 0.06), tongue)
            for k in range(teeth):
                tx = x + (k - (teeth - 1) / 2) * w * 0.17
                u = (tx - x) / (w / 2)
                self.blk("Tooth", (w * 0.14, w * 0.13, w * 0.08), (tx, y + curve * w * u * u - w * 0.03, zf + bend * u * u - w * 0.08), tooth)
        self.chain(name, pts, d, color)
        # little dimples at the corners
        for e in (pts[0], pts[-1]):
            self.ball(name, d * 1.15, e, color)

    def brow(self, cx, y, zf, w, color, side, tilt=12, d=None, arch=0.08, name="Brow"):
        """A curved eyebrow over an eye at cx (side -1 left / 1 right)."""
        d = d or w * 0.2
        a = math.radians(side * tilt)
        pts = []
        for k in range(3):
            u = -1 + k
            px = cx + u * w / 2 * math.cos(a)
            py = y + u * w / 2 * math.sin(a) + arch * (1 - u * u)
            pts.append((px, py, zf))
        self.chain(name, pts, d, color)

    def mitt(self, pos, d, color, side, name="Hand", thumb=True, fingers=0, mat="SmoothPlastic", tname="Thumb"):
        """A round cartoon hand with a thumb (and optional finger bumps)."""
        x, y, z = pos
        self.ball(name, d, pos, color, mat)
        if thumb:
            self.ell(tname, (d * 0.42, d * 0.55, d * 0.42), (x - side * d * 0.3, y + d * 0.22, z - d * 0.28), color, mat, R=Rz(side * 30))
        for k in range(fingers):
            fx = x + side * d * 0.12 + (k - (fingers - 1) / 2) * d * 0.26
            self.ell("Finger", (d * 0.26, d * 0.3, d * 0.34), (fx, y - d * 0.3, z - d * 0.2), color, mat)

    def shoe(self, x, z, w, l, color, sole=(40, 35, 40), y=0.0, h=None, name="Foot", toe=None, lace=None, mat="SmoothPlastic"):
        """A cartoon shoe: rounded upper, a flat sole and an optional toe cap and laces."""
        h = h or w * 0.55
        self.ell(name, (w, h * 1.6, l), (x, y + h * 0.55, z), color, mat)
        self.blk("Sole", (w * 0.92, h * 0.28, l * 0.88), (x, y + h * 0.14, z), sole, "Rubber")
        if toe is not None:
            self.ell("Toe", (w * 0.8, h * 1.0, l * 0.42), (x, y + h * 0.5, z - l * 0.3), toe, mat)
        if lace is not None:
            for k in range(2):
                self.blk("Laces", (w * 0.5, h * 0.12, h * 0.12), (x, y + h * (1.1 - k * 0.1), z - l * (0.05 + k * 0.14)), lace)

    def rbox(self, name, size, pos, color, r, mat="SmoothPlastic", R=None, tr=0, refl=0, edge_name=None, axis="y"):
        """A box with rounded edges along one axis (2 blocks + 4 cylinders)."""
        sx, sy, sz = size
        R0 = I3 if R is None else np.array(R, float)
        en = edge_name or name
        c = np.array(pos, float)
        if axis == "y":
            first = self.blk(name, (sx - 2 * r, sy, sz), pos, color, mat, R0, tr, refl)
            self.blk(en, (sx, sy, sz - 2 * r), pos, color, mat, R0, tr, refl)
            for ix in (-1, 1):
                for iz in (-1, 1):
                    off = R0 @ np.array([ix * (sx / 2 - r), 0, iz * (sz / 2 - r)])
                    self.cyl(en, sy, 2 * r, c + off, color, "y", mat, R0, tr, refl)
        elif axis == "z":
            first = self.blk(name, (sx - 2 * r, sy, sz), pos, color, mat, R0, tr, refl)
            self.blk(en, (sx, sy - 2 * r, sz), pos, color, mat, R0, tr, refl)
            for ix in (-1, 1):
                for iy in (-1, 1):
                    off = R0 @ np.array([ix * (sx / 2 - r), iy * (sy / 2 - r), 0])
                    self.cyl(en, sz, 2 * r, c + off, color, "z", mat, R0, tr, refl)
        else:
            first = self.blk(name, (sx, sy - 2 * r, sz), pos, color, mat, R0, tr, refl)
            self.blk(en, (sx, sy, sz - 2 * r), pos, color, mat, R0, tr, refl)
            for iy in (-1, 1):
                for iz in (-1, 1):
                    off = R0 @ np.array([0, iy * (sy / 2 - r), iz * (sz / 2 - r)])
                    self.cyl(en, sx, 2 * r, c + off, color, "x", mat, R0, tr, refl)
        return first

    def rivets(self, name, pts, d, color, normal="z", mat="Metal"):
        for p in pts:
            self.cyl(name, d * 0.45, d, p, color, normal, mat)

    def scatter(self, name, center, size, n, colors, seed=1, d=0.12, ymin=0.0, shape="sprinkle", front_only=False, mat="SmoothPlastic", length=2.6, inset=0.0):
        """Scatters little details (sprinkles, seeds, salt, studs) over the upper surface of an ellipsoid."""
        import random
        rnd = random.Random(seed)
        c = np.array(center, float)
        h = np.array(size, float) / 2
        placed = 0
        tries = 0
        while placed < n and tries < n * 60:
            tries += 1
            v = np.array([rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)])
            if np.linalg.norm(v) < 1e-3:
                continue
            v /= np.linalg.norm(v)
            if v[1] < ymin:
                continue
            if front_only and v[2] > 0.2:
                continue
            p = c + v * h * (1 - inset)
            nrm = v / h
            nrm /= np.linalg.norm(nrm)
            col = colors[placed % len(colors)]
            Rn = frame_normal(nrm, rnd.uniform(0, 360))
            if shape == "sprinkle":
                self.ell(name, (d * length, d, d), p + nrm * d * 0.2, col, mat, R=Rn)
            elif shape == "dot":
                self.ell(name, (d, d, d * 0.5), p, col, mat, R=Rn)
            elif shape == "cube":
                self.blk(name, (d, d, d), p, col, mat, R=Rn @ rot(30, 20, 10))
            elif shape == "stud":
                self.cyl(name, d * 0.5, d, p, col, "z", mat, R=Rn)
            placed += 1

    def drip(self, name, top, length, d, color, mat="SmoothPlastic", refl=0.0):
        """A hanging drip: a stretched blob ending in a round drop."""
        x, y, z = top
        self.ell(name, (d * 0.8, length, d * 0.8), (x, y - length / 2, z), color, mat, refl=refl)
        self.ball(name, d, (x, y - length + d * 0.15, z), color, mat, refl=refl)

    def stitches(self, name, p1, p2, n, d, color, R=None):
        p1 = np.array(p1, float); p2 = np.array(p2, float)
        for k in range(n):
            t = (k + 0.5) / n
            p = p1 + (p2 - p1) * t
            self.blk(name, (d * 2.2, d * 0.7, d * 0.7), p, color, R=Rz(45 if k % 2 else -45) if R is None else R)

    def gem(self, name, pos, d, color, glow=False):
        """A faceted-looking gem: a ball with a bright highlight."""
        self.ball(name, d, pos, color, "Neon" if glow else "Glass", refl=0.3)
        x, y, z = pos
        self.ball(name + "Shine", d * 0.3, (x + d * 0.18, y + d * 0.18, z - d * 0.3), (255, 255, 255), "Neon")

    # Effects ------------------------------------------------------------
    def fire(self, idx, size=2, heat=6, color=(255, 120, 30), color2=(255, 220, 80)):
        self.effects.append(("Fire", idx, size, heat, color, color2))

    def sparkles(self, idx, color=(255, 240, 150)):
        self.effects.append(("Sparkles", idx, color))

    def smoke(self, idx, color=(230, 230, 240), opacity=0.08, rise=0.6, size=1.5):
        self.effects.append(("Smoke", idx, color, opacity, rise, size))

    def light(self, idx, color=(255, 220, 160), brightness=1.5, rng=8):
        self.effects.append(("PointLight", idx, color, brightness, rng))

    def confetti(self, idx):
        self.effects.append(("Confetti", idx))

    # Info ---------------------------------------------------------------
    def bounds(self):
        lo = np.array([1e9] * 3); hi = -lo
        for p in self.parts:
            if p["tr"] >= 1:
                continue
            h = np.array(p["size"]) / 2
            corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * h
            w = corners @ p["R"].T + np.array(p["pos"])
            lo = np.minimum(lo, w.min(0)); hi = np.maximum(hi, w.max(0))
        return lo, hi


def r3(v):
    return float(f"{v:.3f}")


def to_luau(models, header):
    out = [header, "return {"]
    for m in models:
        lo, hi = m.bounds()
        out.append(f"\t{m.id} = {{")
        out.append(f"\t\theight = {r3(hi[1])}, width = {r3(hi[0] - lo[0])}, depth = {r3(hi[2] - lo[2])},")
        out.append("\t\tparts = {")
        for p in m.parts:
            ex, ey, ez = euler_xyz(p["R"])
            vals = [f'"{p["shape"]}"', f'"{p["name"]}"'] + [str(r3(v)) for v in p["size"]] + [str(r3(v)) for v in p["pos"]] + \
                   [str(r3(v)) for v in (ex, ey, ez)] + [str(c) for c in p["color"]] + [f'"{p["mat"]}"', str(r3(p["tr"])), str(r3(p["refl"]))]
            out.append("\t\t\t{" + ", ".join(vals) + "},")
        out.append("\t\t},")
        if m.effects:
            out.append("\t\teffects = {")
            for e in m.effects:
                items = []
                for v in e:
                    if isinstance(v, str):
                        items.append(f'"{v}"')
                    elif isinstance(v, tuple):
                        items.extend(str(int(c)) for c in v)
                    else:
                        items.append(str(r3(v)) if isinstance(v, float) else str(v))
                out.append("\t\t\t{" + ", ".join(items) + "},")
            out.append("\t\t},")
        out.append("\t},")
    out.append("}")
    return "\n".join(out) + "\n"
