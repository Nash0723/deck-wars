#!/usr/bin/env python3
"""Draws the layered effect pictures for LayerFx.

Every effect is four pictures that sit on top of each other:
    glow   - a soft bloom behind everything
    rim    - the full silhouette (tinted with the dark, saturated colour in game)
    middle - a smaller shape inside it (the bright colour)
    core   - the hottest, smallest part (near white)
The four are packed into the quadrants of one 1024x1024 sheet (glow top-left, rim top-right,
middle bottom-left, core bottom-right), white with brush streaks in the brightness, so the game
can tint each layer and one drawing serves every card family.

    python3 vfx/draw_layers.py            # writes vfx/sheets/*.png and vfx/preview.png
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

Q = 512          # one quadrant on the sheet
SS = 2           # supersampling while drawing
W = Q * SS
PAD = 10 * SS    # kept clear at the quadrant edges so layers never bleed into each other
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sheets")


def rng_for(name):
    return np.random.default_rng(abs(hash_str(name)) % (2 ** 32))


def hash_str(s):
    h = 2166136261
    for ch in s.encode():
        h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
    return h


# ---------------------------------------------------------------------------------- noise
def value_noise(rng, gx, gy, octaves=3):
    out = np.zeros((W, W), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        g = rng.random((max(2, gy * 2 ** o), max(2, gx * 2 ** o))).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC)
        out += amp * np.asarray(im, np.float32) / 255.0
        tot += amp
        amp *= 0.5
    return out / tot


def grid():
    y, x = np.mgrid[0:W, 0:W].astype(np.float32)
    return (x - W / 2) / (W / 2), (y - W / 2) / (W / 2)


def streaks(rng, kind):
    """Brush streaks: brightness that runs along the way the brush moved."""
    x, y = grid()
    if kind == "radial":
        ang = (np.arctan2(y, x) + math.pi) / (2 * math.pi)
        line = smooth1d(rng, 2048, 90)
        s = line[(ang * 2047).astype(np.int32)]
    elif kind == "ring":
        r = np.clip(np.hypot(x, y), 0, 1.5) / 1.5
        line = smooth1d(rng, 2048, 70)
        s = line[(r * 2047).astype(np.int32)]
    elif kind == "horizontal":
        s = value_noise(rng, 3, 60, 2)
    elif kind == "vertical":
        s = value_noise(rng, 60, 3, 2)
    else:
        s = value_noise(rng, 8, 8, 3)
    s = (s - s.min()) / max(1e-6, s.max() - s.min())
    return s


def smooth1d(rng, n, cells):
    g = rng.random(cells + 1).astype(np.float32)
    xs = np.linspace(0, cells, n)
    i = np.floor(xs).astype(np.int32).clip(0, cells - 1)
    f = xs - i
    f = f * f * (3 - 2 * f)
    return g[i] * (1 - f) + g[i + 1] * f


# ---------------------------------------------------------------------------------- drawing
class Mask:
    def __init__(self):
        self.im = Image.new("L", (W, W), 0)
        self.d = ImageDraw.Draw(self.im)

    def px(self, p):
        return (W / 2 + p[0] * W / 2, W / 2 + p[1] * W / 2)

    def poly(self, pts, v=255):
        self.d.polygon([self.px(p) for p in pts], fill=v)

    def disc(self, c, r, v=255):
        cx, cy = self.px(c)
        rr = r * W / 2
        self.d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=v)

    def ellipse(self, c, rx, ry, v=255):
        cx, cy = self.px(c)
        self.d.ellipse([cx - rx * W / 2, cy - ry * W / 2, cx + rx * W / 2, cy + ry * W / 2], fill=v)

    def stroke(self, p0, p1, p2, width, profile="blade", v=255, n=28):
        """A brush stroke: a bent ribbon from p0 to p2 (p1 pulls the bend)."""
        left, right = [], []
        for i in range(n + 1):
            t = i / n
            a = (1 - t) ** 2
            b = 2 * (1 - t) * t
            c = t * t
            x = a * p0[0] + b * p1[0] + c * p2[0]
            y = a * p0[1] + b * p1[1] + c * p2[1]
            dx = 2 * (1 - t) * (p1[0] - p0[0]) + 2 * t * (p2[0] - p1[0])
            dy = 2 * (1 - t) * (p1[1] - p0[1]) + 2 * t * (p2[1] - p1[1])
            L = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / L, dx / L
            if profile == "blade":       # fat at the root, a long point at the tip
                w = width * (1 - t) ** 0.85 * min(1.0, t * 9 + 0.35)
            elif profile == "leaf":      # points at both ends
                w = width * math.sin(math.pi * t) ** 0.7
            elif profile == "comet":     # round head at the end, thin tail at the start
                w = width * t ** 1.5 if t < 0.93 else width * math.sqrt(max(0.0, 1 - ((t - 0.93) / 0.07) ** 2)) * 0.93 ** 1.5
            else:
                w = width
            left.append((x + nx * w, y + ny * w))
            right.append((x - nx * w, y - ny * w))
        self.poly(left + right[::-1], v)

    def arr(self):
        return np.asarray(self.im, np.float32) / 255.0


def blur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r * SS)), np.float32) / 255.0


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def roughen(a, rng, amount=0.5, r=3.0, cells=40):
    """Ragged, dry-brush edges instead of a clean vector outline."""
    soft = blur(a, r)
    n = value_noise(rng, cells, cells, 3)
    return smoothstep(0.38, 0.6, soft + (n - 0.5) * amount) * smoothstep(0.02, 0.2, soft)


def shrink(a, r, level=0.8):
    return (blur(a, r) > level).astype(np.float32)


def shift(a, dx, dy):
    return np.roll(np.roll(a, int(dy * W / 2), 0), int(dx * W / 2), 1)


def edge_fade(a):
    x, y = grid()
    m = np.maximum(np.abs(x), np.abs(y))
    return a * (1 - smoothstep(1 - 2.2 * PAD / W * 2, 1 - PAD / W * 2 * 0.6, m))


def finish(alpha, lum):
    """-> RGBA quadrant (white with streaky brightness, alpha = the shape)."""
    alpha = edge_fade(np.clip(alpha, 0, 1))
    lum = np.clip(lum, 0, 1)
    rgba = np.dstack([lum, lum, lum, alpha])
    im = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
    return im.resize((Q, Q), Image.LANCZOS)


def pack(name, glow, rim, middle, core, streak_kind, rng, glow_r=26, glow_gain=0.9):
    s = streaks(rng, streak_kind)
    fine = value_noise(rng, 90, 90, 2)
    lum_rim = 0.62 + 0.38 * s
    lum_mid = 0.74 + 0.26 * (0.7 * s + 0.3 * fine)
    lum_core = 0.9 + 0.1 * s
    if glow is None:
        glow = np.clip(blur(rim, glow_r) * 1.25 + blur(rim, glow_r * 2.4) * 0.8, 0, 1) * glow_gain
    sheet = Image.new("RGBA", (Q * 2, Q * 2), (255, 255, 255, 0))
    sheet.paste(finish(glow, np.ones_like(glow)), (0, 0))
    sheet.paste(finish(rim, lum_rim), (Q, 0))
    sheet.paste(finish(middle, lum_mid), (0, Q))
    sheet.paste(finish(core, lum_core), (Q, Q))
    os.makedirs(OUT, exist_ok=True)
    sheet.save(os.path.join(OUT, name + ".png"), optimize=True)
    return sheet


def pol(r, a):
    return (r * math.cos(a), r * math.sin(a))


# ---------------------------------------------------------------------------------- effects
def radial_strokes(rng, count, rmin, rmax, width, bend=0.25, jitter=0.5, bias=None):
    """Spikes thrown out from the middle. Returns a list the three layers scale down."""
    out = []
    for i in range(count):
        a = (i + rng.uniform(-jitter, jitter)) / count * 2 * math.pi
        r = rng.uniform(rmin, rmax)
        if bias is not None:      # longer on one side: the hit has a direction
            r *= 1 + 0.45 * max(0.0, math.cos(a - bias))
        out.append((a, r, width * rng.uniform(0.6, 1.25), rng.uniform(-bend, bend)))
    return out


def draw_radial(strokes, scale, wscale, blob, root=0.0, cap=0.86):
    m = Mask()
    for a, r, w, b in strokes:
        r = min(r * scale, cap)
        p0 = pol(root, a)
        p2 = pol(r, a + b * 0.35)
        p1 = pol(r * 0.55, a - b)
        m.stroke(p0, p1, p2, w * wscale)
    if blob > 0:
        m.disc((0, 0), blob)
    return m.arr()


def fx_burst(rng):
    st = radial_strokes(rng, 15, 0.45, 0.86, 0.105, bias=-0.6)
    thin = radial_strokes(rng, 11, 0.5, 0.9, 0.028, bend=0.4)
    rim = np.maximum(draw_radial(st, 1.0, 1.0, 0.27), draw_radial(thin, 1.0, 1.0, 0))
    mid = draw_radial(st, 0.8, 0.66, 0.2)
    core = draw_radial(st, 0.52, 0.42, 0.135)
    return (None, roughen(rim, rng, 0.42), roughen(shift(mid, 0.012, -0.012), rng, 0.38), roughen(core, rng, 0.25, 2.2)), "radial"


def fx_shard(rng):
    """Crystal spikes: straight, hard facets (frost, glass, steel)."""
    def layer(scale, wscale, blob):
        m = Mask()
        r2 = np.random.default_rng(7)
        for i in range(9):
            a = (i + r2.uniform(-0.3, 0.3)) / 9 * 2 * math.pi
            r = min(r2.uniform(0.5, 0.88) * scale, 0.87)
            w = r2.uniform(0.07, 0.13) * wscale
            base = r * 0.32
            m.poly([pol(0.02, a + math.pi), pol(base, a + w / base * 1.0), pol(r, a), pol(base, a - w / base * 1.0)])
        for i in range(7):
            a = (i + 0.5 + r2.uniform(-0.3, 0.3)) / 7 * 2 * math.pi
            r = min(r2.uniform(0.3, 0.55) * scale, 0.87)
            m.poly([pol(0.02, a + math.pi), pol(r * 0.4, a + 0.16 * wscale), pol(r, a), pol(r * 0.4, a - 0.16 * wscale)])
        if blob:
            m.disc((0, 0), blob)
        return m.arr()
    rim = layer(1, 1, 0.16)
    mid = layer(0.82, 0.62, 0.11)
    core = layer(0.5, 0.4, 0.07)
    return (None, roughen(rim, rng, 0.14, 1.6), roughen(shift(mid, 0.01, -0.012), rng, 0.12, 1.6), roughen(core, rng, 0.1, 1.4)), "radial"


def crescent(m, r_out, thick, a0, a1, tail=1.0, off=(0, 0), n=60):
    """A sword-swipe moon: thick in the middle, needle points at both ends."""
    outer, inner = [], []
    for i in range(n + 1):
        t = i / n
        a = a0 + (a1 - a0) * t
        w = thick * math.sin(math.pi * t) ** (0.75 * tail)
        w *= 0.55 + 0.45 * t          # heavier toward the leading end
        outer.append((off[0] + r_out * math.cos(a), off[1] + r_out * math.sin(a)))
        inner.append((off[0] + (r_out - w) * math.cos(a), off[1] + (r_out - w) * math.sin(a)))
    m.poly(outer + inner[::-1])


def fx_slash(rng):
    c = (-0.1, 0.34)
    a0, a1 = math.radians(-168), math.radians(-6)
    m = Mask(); crescent(m, 0.86, 0.34, a0, a1, off=c)
    for k in range(6):                       # loose hairs of paint that trail the swipe
        rr = 0.86 - rng.uniform(0.02, 0.36)
        s = a0 + rng.uniform(-0.12, 0.5)
        e = s + rng.uniform(0.5, 1.3)
        crescent(m, rr, rng.uniform(0.012, 0.03), s, min(e, a1 + 0.1), off=c)
    rim = m.arr()
    m = Mask(); crescent(m, 0.835, 0.22, a0 + 0.2, a1 - 0.04, off=c)
    mid = m.arr()
    m = Mask(); crescent(m, 0.815, 0.1, a0 + 0.55, a1 - 0.1, off=c)
    core = m.arr()
    return (None, roughen(rim, rng, 0.45), roughen(mid, rng, 0.36), roughen(core, rng, 0.22, 2.0)), "ring"


def ring_band(r, w):
    x, y = grid()
    d = np.hypot(x, y)
    return ((d > r - w) & (d < r + w)).astype(np.float32)


def fx_ring(rng):
    """Shock ring for slams: a broken ring with paint thrown outward."""
    x, y = grid()
    ang = np.arctan2(y, x)
    d = np.hypot(x, y)
    line = smooth1d(rng, 2048, 26)
    wob = line[((ang + math.pi) / (2 * math.pi) * 2047).astype(np.int32)]
    def band(r, w, gap):
        b = (np.abs(d - (r + (wob - 0.5) * 0.05)) < w * (0.45 + 1.1 * wob)).astype(np.float32)
        return b * (wob > gap)
    spikes = radial_strokes(rng, 26, 0.72, 0.9, 0.04, bend=0.12)
    rim = np.maximum(band(0.62, 0.085, 0.16), draw_radial(spikes, 1.0, 1.0, 0, root=0.58, cap=0.9))
    mid = np.maximum(band(0.615, 0.052, 0.24), draw_radial(spikes, 0.92, 0.55, 0, root=0.58))
    core = band(0.61, 0.024, 0.34)
    return (None, roughen(rim, rng, 0.4), roughen(mid, rng, 0.34), roughen(core, rng, 0.25, 2.0)), "radial"


def fx_circle(rng):
    """Spell circle: two rings, tick marks, a six-point star and small moons."""
    def ring(m, r, w, v=255):
        m.disc((0, 0), r + w, v); m.disc((0, 0), r - w, 0)
    def star(m, r, w, turn=0.0):
        for tri in range(2):
            pts = [pol(r, turn + tri * math.pi / 3 + k * 2 * math.pi / 3 - math.pi / 2) for k in range(3)]
            for k in range(3):
                a, b = pts[k], pts[(k + 1) % 3]
                dx, dy = b[0] - a[0], b[1] - a[1]
                L = math.hypot(dx, dy); nx, ny = -dy / L * w, dx / L * w
                m.poly([(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny), (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)])
    # rim: the heavy outer rings with a band of tick marks between them
    m = Mask()
    ring(m, 0.84, 0.03)
    ring(m, 0.66, 0.018)
    for k in range(36):
        a = k / 36 * 2 * math.pi
        long = k % 3 == 0
        r0, r1 = (0.69, 0.81) if long else (0.73, 0.79)
        w = 0.022 if long else 0.012
        m.poly([pol(r0, a - w), pol(r1, a - w * 0.8), pol(r1, a + w * 0.8), pol(r0, a + w)])
    star(m, 0.64, 0.02)
    rim = m.arr()
    # middle: thinner copies inside the heavy lines plus the inner ring and moons
    m = Mask()
    ring(m, 0.84, 0.012)
    star(m, 0.64, 0.009)
    ring(m, 0.36, 0.014)
    for k in range(6):
        c = pol(0.5, k / 6 * 2 * math.pi)
        m.disc(c, 0.055); m.disc((c[0] * 1.07, c[1] * 1.07), 0.046, 0)
    for k in range(12):
        a = (k + 0.5) / 12 * 2 * math.pi
        m.disc(pol(0.75, a), 0.014)
    mid = m.arr()
    # core: the bright heart
    m = Mask()
    ring(m, 0.36, 0.006)
    star(m, 0.3, 0.01, math.pi / 6)
    m.disc((0, 0), 0.06)
    for k in range(6):
        m.disc(pol(0.64, k / 6 * 2 * math.pi - math.pi / 2), 0.022)
    core = m.arr()
    both = np.maximum(rim, mid)
    glow = np.clip(blur(both, 14) * 1.5 + blur(both, 40) * 1.0, 0, 1) * 0.85
    return (glow, roughen(rim, rng, 0.2, 1.6, 70), roughen(mid, rng, 0.16, 1.3, 70), roughen(core, rng, 0.1, 1.2, 70)), "radial"


def fx_pillar(rng):
    """A column of light: wide flare at the foot, streaks racing up."""
    def col(width, top, foot, n_wisps, seed):
        r2 = np.random.default_rng(seed)
        m = Mask()
        m.stroke((0, 0.86), (0, 0.1), (0, top), width, "blade")
        m.stroke((0, 0.86), (0, 0.4), (0, top * 0.6), width * 1.1, "leaf")
        m.ellipse((0, 0.84), foot, foot * 0.24)
        for k in range(n_wisps):
            sx = r2.uniform(-1, 1) * foot * 0.9
            m.stroke((sx, 0.84), (sx * 1.25, r2.uniform(0.2, 0.5)), (sx * 0.5 + r2.uniform(-0.08, 0.08), r2.uniform(-0.6, 0.1)),
                     r2.uniform(0.018, 0.045) * (width / 0.2 + 0.4), "blade")
        return m.arr()
    rim = col(0.2, -0.9, 0.5, 9, 3)
    mid = col(0.125, -0.84, 0.36, 5, 3)
    core = col(0.06, -0.78, 0.2, 0, 3)
    return (None, roughen(rim, rng, 0.42), roughen(mid, rng, 0.34), roughen(core, rng, 0.22, 2.0)), "vertical"


def fx_bolt(rng):
    """A thrown bolt: bright head on the right, torn tail to the left."""
    def comet(w, x0, x1, hairs, seed):
        r2 = np.random.default_rng(seed)
        m = Mask()
        m.stroke((x0, 0.0), ((x0 + x1) / 2, 0.02), (x1, 0), w, "comet")
        for k in range(hairs):
            y = r2.uniform(-1, 1) * w * 1.5
            s = r2.uniform(x0, 0.0)
            m.stroke((s, y), ((s + x1) / 2, y * 0.8), (x1 - 0.1, y * 0.3), r2.uniform(0.012, 0.03), "leaf")
        return m.arr()
    rim = comet(0.2, -0.88, 0.84, 8, 5)
    mid = comet(0.135, -0.5, 0.82, 3, 5)
    core = comet(0.08, -0.12, 0.8, 0, 5)
    return (None, roughen(rim, rng, 0.42), roughen(mid, rng, 0.32), roughen(core, rng, 0.2, 2.0)), "horizontal"


def fx_puff(rng):
    """A fat cloud for things that pop."""
    r2 = np.random.default_rng(11)
    blobs = [(0, 0.02, 0.4)]
    for k in range(9):
        a = k / 9 * 2 * math.pi + r2.uniform(-0.2, 0.2)
        d = r2.uniform(0.3, 0.46)
        blobs.append((d * math.cos(a), d * math.sin(a) * 0.85, r2.uniform(0.2, 0.31)))
    def cloud(k, dx=0.0, dy=0.0):
        m = Mask()
        for bx, by, br in blobs:
            m.disc((bx * (0.55 + 0.45 * k) + dx, by * (0.55 + 0.45 * k) + dy), br * k)
        return m.arr()
    rim = cloud(1.0)
    mid = cloud(0.74, -0.03, -0.05)
    core = cloud(0.42, -0.07, -0.1)
    return (None, roughen(rim, rng, 0.3, 4.0, 16), roughen(mid, rng, 0.3, 4.0, 16), roughen(core, rng, 0.3, 4.0, 16)), "blotch"


def fx_bloom(rng):
    """A rising fan of leaves of light (heals, buffs, blessings)."""
    def fan(scale, wscale, heart):
        r2 = np.random.default_rng(21)
        m = Mask()
        for k in range(11):
            t = (k + r2.uniform(-0.25, 0.25)) / 10
            a = math.radians(-170 + 160 * t)
            r = r2.uniform(0.6, 0.95) * scale * (0.75 + 0.35 * math.sin(math.pi * t))
            curl = (t - 0.5) * 0.9
            root = (0, 0.55)
            tip = (root[0] + r * math.cos(a), root[1] + r * math.sin(a))
            midp = (root[0] + r * 0.5 * math.cos(a - curl), root[1] + r * 0.5 * math.sin(a - curl))
            m.stroke(root, midp, tip, r2.uniform(0.06, 0.1) * wscale, "leaf")
        m.ellipse((0, 0.52), heart, heart * 0.6)
        return m.arr()
    rim = fan(1.0, 1.0, 0.22)
    mid = fan(0.86, 0.6, 0.16)
    core = fan(0.6, 0.34, 0.1)
    return (None, roughen(rim, rng, 0.36), roughen(mid, rng, 0.3), roughen(core, rng, 0.2, 2.0)), "radial"


def fx_shield(rng):
    """A ward: a kite shield outline with a cross brace and a shine."""
    def kite(m, s, v=255):
        pts = [(-0.62, -0.62), (0, -0.8), (0.62, -0.62), (0.6, 0.0), (0.34, 0.5), (0, 0.84), (-0.34, 0.5), (-0.6, 0.0)]
        m.poly([(x * s, y * s) for x, y in pts], v)
    m = Mask(); kite(m, 1.0); kite(m, 0.84, 0)
    rim = m.arr()
    m = Mask(); kite(m, 0.93); kite(m, 0.89, 0)
    m.poly([(-0.03, -0.62), (0.03, -0.62), (0.03, 0.62), (-0.03, 0.62)])
    m.poly([(-0.46, -0.2), (0.46, -0.2), (0.46, -0.14), (-0.46, -0.14)])
    mid = m.arr()
    m = Mask()
    m.stroke((-0.4, -0.46), (-0.1, -0.56), (0.3, -0.5), 0.05, "leaf")
    m.stroke((-0.44, -0.3), (-0.46, -0.1), (-0.4, 0.14), 0.035, "leaf")
    m.disc((0, -0.17), 0.085)
    core = m.arr()
    m = Mask(); kite(m, 0.95)
    fill = m.arr()
    glow = np.clip(fill * 0.35 + blur(rim, 16) * 1.3 + blur(fill, 40) * 0.55, 0, 1) * 0.85
    return (glow, roughen(rim, rng, 0.3, 2.4), roughen(mid, rng, 0.24, 1.8), roughen(core, rng, 0.2, 1.8)), "vertical"


def fx_flame(rng):
    """Licks of flame, or a spirit wisp when it's tinted cold."""
    def fire(k, dy, tongues):
        r2 = np.random.default_rng(31)
        m = Mask()
        m.ellipse((0, 0.42 + dy), 0.4 * k, 0.4 * k)
        specs = [(-0.02, -0.9, 0.3, 0.3), (-0.3, -0.45, 0.2, -0.35), (0.3, -0.58, 0.2, 0.4), (-0.46, -0.05, 0.13, -0.3), (0.47, -0.16, 0.13, 0.3)]
        for i, (tx, ty, w, bend) in enumerate(specs[:tongues]):
            root = (tx * 0.5 * k, 0.6 + dy)
            tip = (tx * k, 0.42 + dy + (ty - 0.42) * k)
            midp = ((root[0] + tip[0]) / 2 + bend * 0.3 * k, (root[1] + tip[1]) / 2)
            m.stroke(root, midp, tip, w * k * 1.25, "blade")
        return m.arr()
    rim = fire(1.0, 0.0, 5)
    mid = fire(0.72, 0.1, 3)
    core = fire(0.42, 0.2, 1)
    return (None, roughen(rim, rng, 0.4, 3.2, 26), roughen(mid, rng, 0.34, 3.0, 26), roughen(core, rng, 0.24, 2.4, 26)), "vertical"


def fx_spark(rng):
    """A four-point glint."""
    def glint(long, short, w):
        m = Mask()
        for k in range(4):
            a = k * math.pi / 2 - math.pi / 2
            L = long if k % 2 == 0 else short
            m.poly([pol(w, a - math.pi / 2), pol(L, a), pol(w, a + math.pi / 2)])
        m.disc((0, 0), w * 1.25)
        return m.arr()
    rim = glint(0.88, 0.6, 0.12)
    mid = glint(0.74, 0.46, 0.075)
    core = glint(0.5, 0.3, 0.045)
    return (None, roughen(rim, rng, 0.12, 1.4), roughen(mid, rng, 0.1, 1.3), roughen(core, rng, 0.08, 1.2)), "radial"


def fx_bits(rng):
    """Loose bits the effects throw around. Not layers: four separate small pictures."""
    m = Mask(); m.stroke((-0.8, 0.05), (0, -0.08), (0.8, 0.0), 0.12, "leaf")
    dash = roughen(m.arr(), rng, 0.4)
    x, y = grid()
    dot = np.clip(1 - np.hypot(x, y) / 0.8, 0, 1) ** 2.2
    m = Mask(); m.poly([(-0.5, 0.6), (0.1, -0.8), (0.55, 0.45)]); m.poly([(-0.2, 0.2), (0.05, -0.3), (0.2, 0.15)], 0)
    chip = roughen(m.arr(), rng, 0.2, 1.6)
    m = Mask()
    m.stroke((-0.7, 0.5), (-0.5, -0.5), (0.5, -0.6), 0.09, "leaf")
    m.stroke((-0.3, 0.7), (0.4, 0.4), (0.7, -0.2), 0.07, "leaf")
    curl = roughen(m.arr(), rng, 0.4)
    return (dot * 0.95, dash, chip, curl), "horizontal"


EFFECTS = [
    ("burst", fx_burst), ("slash", fx_slash), ("ring", fx_ring), ("circle", fx_circle),
    ("pillar", fx_pillar), ("bolt", fx_bolt), ("puff", fx_puff), ("bloom", fx_bloom),
    ("shield", fx_shield), ("shard", fx_shard), ("flame", fx_flame), ("spark", fx_spark),
    ("bits", fx_bits),
]

PALETTES = {  # glow, rim, middle, core  (the same numbers LayerFx uses in game)
    "ember": ((255, 150, 40), (196, 84, 12), (255, 184, 62), (255, 250, 226)),
    "frost": ((90, 190, 255), (30, 96, 190), (120, 214, 255), (240, 252, 255)),
    "arcane": ((176, 110, 255), (92, 40, 176), (196, 150, 255), (250, 240, 255)),
    "verdant": ((110, 240, 140), (26, 132, 70), (150, 250, 150), (244, 255, 232)),
    "smoke": ((120, 120, 140), (52, 50, 66), (128, 126, 146), (214, 214, 226)),
}


def composite(sheet, pal, size=256, bg=(16, 24, 38)):
    out = np.zeros((size, size, 3), np.float32) + np.array(bg, np.float32) / 255
    quads = [(0, 0), (Q, 0), (0, Q), (Q, Q)]
    for i, (qx, qy) in enumerate(quads):
        q = sheet.crop((qx, qy, qx + Q, qy + Q)).resize((size, size), Image.LANCZOS)
        a = np.asarray(q, np.float32) / 255
        col = np.array(pal[i], np.float32) / 255
        alpha = a[..., 3:4] * (0.55 if i == 0 else 1.0)
        out = out * (1 - alpha) + a[..., :3] * col * alpha
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main():
    only = sys.argv[1:] or None
    sheets = {}
    for name, fn in EFFECTS:
        if only and name not in only:
            continue
        rng = rng_for(name)
        layers, kind = fn(rng)
        sheets[name] = pack(name, layers[0], layers[1], layers[2], layers[3], kind, rng)
        print("drew", name)
    # contact sheet: the four layers on their own, then put together in a few colours
    names = [n for n, _ in EFFECTS if n in sheets]
    cell = 200
    pals = ["ember", "frost", "arcane", "verdant"]
    prev = Image.new("RGB", (cell * (4 + len(pals)), cell * len(names)), (16, 24, 38))
    for r, n in enumerate(names):
        sh = sheets[n]
        for i, (qx, qy) in enumerate([(0, 0), (Q, 0), (0, Q), (Q, Q)]):
            q = sh.crop((qx, qy, qx + Q, qy + Q)).resize((cell, cell), Image.LANCZOS)
            back = Image.new("RGB", (cell, cell), (30, 40, 58))
            back.paste(q, (0, 0), q)
            prev.paste(back, (i * cell, r * cell))
        if n != "bits":
            for j, p in enumerate(pals):
                pal = PALETTES["smoke"] if (n == "puff" and j == 0) else PALETTES[p]
                prev.paste(composite(sh, pal, cell), ((4 + j) * cell, r * cell))
    prev.save(os.path.join(os.path.dirname(OUT), "preview.png"))


if __name__ == "__main__":
    main()
