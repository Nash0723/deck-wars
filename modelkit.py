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
    def eyes(self, y, zf, sep, d, lid=None, x=0.0, look=(0.0, 0.0), pupil=PUPIL, white=WHITE, pupil_scale=0.55, tilt=0.0, angry=0.0, sleepy=False):
        """Two cartoon eyes on a surface whose front is at z = zf (facing -Z).
        lid: color of the hidden eyelids used for blinking (None = no blinking)."""
        for s in (-1, 1):
            ex = x + s * sep / 2
            Rt = Rz(-s * tilt)
            self.ell("Eye", (d, d * 1.12, d * 0.55), (ex, y, zf - d * 0.05), white, R=Rt)
            pd = d * pupil_scale
            self.ell("Pupil", (pd, pd * 1.1, d * 0.3), (ex + look[0], y + look[1] - (d * 0.08 if sleepy else 0), zf - d * 0.24), pupil, R=Rt)
            self.ell("Glint", (pd * 0.36, pd * 0.36, d * 0.12), (ex + look[0] + pd * 0.2, y + look[1] + pd * 0.25, zf - d * 0.36), white)
            if lid is not None:
                self.ell("Lid", (d * 1.18, d * 1.28, d * 0.95), (ex, y, zf - d * 0.06), lid, R=Rt, tr=1)
            if angry:
                # slanted brow
                self.blk("Brow", (d * 1.05, d * 0.2, d * 0.2), (ex, y + d * 0.68, zf - d * 0.2), pupil, R=Rz(s * angry))
            if sleepy:
                self.ell("Lidhalf", (d * 1.1, d * 0.62, d * 0.62), (ex, y + d * 0.3, zf - d * 0.08), lid or (200, 200, 200))

    def smile(self, y, zf, w, color=(60, 25, 35), x=0.0, open_=False, tongue=(240, 110, 130)):
        if open_:
            self.ell("Mouth", (w, w * 0.55, w * 0.25), (x, y, zf + w * 0.02), color)
            self.ell("Tongue", (w * 0.55, w * 0.25, w * 0.15), (x, y - w * 0.12, zf - w * 0.07), tongue)
        else:
            self.ell("Mouth", (w, w * 0.28, w * 0.2), (x, y, zf), color)

    def cheeks(self, y, zf, sep, d, color=PINK_CHEEK):
        for s in (-1, 1):
            self.ell("Cheek", (d, d * 0.6, d * 0.25), (s * sep / 2, y, zf), color, tr=0.25)

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
