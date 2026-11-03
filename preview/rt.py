# Small numpy ray caster for previewing Roblox primitive parts (block, ball, cylinder, ellipsoid, wedge).
# It is only a rough preview: no textures, simple shading, approximate transparency.
import math
import numpy as np
from PIL import Image, ImageDraw

EMISSIVE = {"Neon"}
SHINY = {"Metal": 0.5, "Foil": 0.7, "Glass": 0.6, "DiamondPlate": 0.4, "Marble": 0.3, "Ice": 0.5, "SmoothPlastic": 0.15}


def _intersect(prim, O, D):
    """Return (t, normal_world) for rays O (3,) / D (N,3) against one primitive. t = inf for misses."""
    R = prim["R"]; c = prim["pos"]; h = prim["size"] / 2
    lo = (O - c) @ R          # ray origin in local space (same for all rays)
    ld = D @ R                # ray directions in local space
    N = D.shape[0]
    shape = prim["shape"]
    t = np.full(N, np.inf)
    n_local = np.zeros((N, 3))
    if shape in ("S", "E"):
        if shape == "S":
            h = np.full(3, h.min())
        so = lo / h; sd = ld / h
        a = (sd * sd).sum(1); b = (sd * so).sum(1); cc = (so * so).sum() - 1
        disc = b * b - a * cc
        ok = disc > 0
        sq = np.sqrt(np.where(ok, disc, 0))
        t0 = (-b - sq) / a; t1 = (-b + sq) / a
        tt = np.where(t0 > 1e-4, t0, np.where(t1 > 1e-4, t1, np.inf))
        t = np.where(ok, tt, np.inf)
        p = lo + ld * np.where(np.isfinite(t), t, 0)[:, None]
        n_local = p / (h * h)
    elif shape == "C":
        r = min(h[1], h[2]); L = h[0]
        # side
        a = ld[:, 1] ** 2 + ld[:, 2] ** 2
        b = ld[:, 1] * lo[1] + ld[:, 2] * lo[2]
        cc = lo[1] ** 2 + lo[2] ** 2 - r * r
        disc = b * b - a * cc
        ok = (disc > 0) & (a > 1e-12)
        sq = np.sqrt(np.where(ok, disc, 0))
        with np.errstate(divide="ignore", invalid="ignore"):
            ts0 = (-b - sq) / a; ts1 = (-b + sq) / a
        best = np.full(N, np.inf); nl = np.zeros((N, 3))
        for ts in (ts0, ts1):
            x = lo[0] + ld[:, 0] * ts
            good = ok & (ts > 1e-4) & (np.abs(x) <= L) & (ts < best)
            best = np.where(good, ts, best)
            p = lo + ld * np.where(good, ts, 0)[:, None]
            nl = np.where(good[:, None], np.stack([np.zeros(N), p[:, 1], p[:, 2]], 1), nl)
        # caps
        for sgn in (-1, 1):
            with np.errstate(divide="ignore", invalid="ignore"):
                tc = (sgn * L - lo[0]) / ld[:, 0]
            p = lo + ld * np.where(np.isfinite(tc), tc, 0)[:, None]
            good = np.isfinite(tc) & (tc > 1e-4) & (p[:, 1] ** 2 + p[:, 2] ** 2 <= r * r) & (tc < best)
            best = np.where(good, tc, best)
            nl = np.where(good[:, None], np.array([sgn, 0, 0])[None, :], nl)
        t = best; n_local = nl
    else:  # B or W: slab test, wedge adds the slope plane
        with np.errstate(divide="ignore", invalid="ignore"):
            t1 = (-h - lo) / ld; t2 = (h - lo) / ld
        tmin_axes = np.minimum(t1, t2); tmax_axes = np.maximum(t1, t2)
        tmin_axes = np.nan_to_num(tmin_axes, nan=-np.inf)
        tmax_axes = np.nan_to_num(tmax_axes, nan=np.inf)
        if shape == "W":
            # inside if n.p <= 0 with plane through (y=-h, z=-h) and (y=h, z=h): n = (0, h_z, -h_y)
            pn = np.array([0, h[2], -h[1]])
            denom = ld @ pn; num = -(lo @ pn)
            with np.errstate(divide="ignore", invalid="ignore"):
                tp = num / denom
            enter = denom < 0  # ray entering the half-space
            tmin_p = np.where(enter, tp, -np.inf)
            tmax_p = np.where(~enter, tp, np.inf)
            inside_parallel = (np.abs(denom) < 1e-12) & ((lo @ pn) > 0)
            tmin_axes = np.column_stack([tmin_axes, tmin_p])
            tmax_axes = np.column_stack([tmax_axes, tmax_p])
            tmin_axes[inside_parallel, -1] = np.inf
        tmin = tmin_axes.max(1); tmax = tmax_axes.min(1)
        ok = (tmax >= tmin) & (tmax > 1e-4)
        t = np.where(ok, np.where(tmin > 1e-4, tmin, np.inf), np.inf)
        k = np.argmax(tmin_axes, 1)
        nl = np.zeros((N, 3))
        p = lo + ld * np.where(np.isfinite(t), t, 0)[:, None]
        for ax in range(3):
            m = k == ax
            nl[m, ax] = np.sign(p[m, ax])
        if shape == "W":
            m = k == 3
            nl[m] = np.array([0, h[2], -h[1]]) / np.linalg.norm([h[2], h[1]])
        n_local = nl
    nw = n_local @ R.T
    nrm = np.linalg.norm(nw, axis=1, keepdims=True)
    nw = nw / np.where(nrm > 0, nrm, 1)
    return t, nw


def prims_from_model(model_parts, offset=(0, 0, 0), yaw=0.0):
    """Convert modelkit parts (dicts) to renderer prims, optionally moved / turned around Y."""
    a = math.radians(yaw)
    Ry = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
    out = []
    for p in model_parts:
        if p["tr"] >= 0.98:
            continue
        out.append(dict(shape=p["shape"], size=np.array(p["size"], float), pos=Ry @ np.array(p["pos"], float) + np.array(offset, float),
                        R=Ry @ np.array(p["R"], float), color=np.array(p["color"], float) / 255, mat=p["mat"], tr=p["tr"]))
    return out


def render(prims, campos, look, W=320, H=320, fov=40, bg=(0.16, 0.15, 0.2), light_dir=(-0.4, 0.9, -0.6), label=None, floor=None):
    campos = np.array(campos, float); look = np.array(look, float)
    f = look - campos; f /= np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r); u = np.cross(r, f)
    th = math.tan(math.radians(fov / 2))
    ys, xs = np.mgrid[0:H, 0:W]
    px = (2 * (xs + 0.5) / W - 1) * th * W / H
    py = (1 - 2 * (ys + 0.5) / H) * th
    D = f[None, None, :] + px[..., None] * r[None, None, :] + py[..., None] * u[None, None, :]
    D = (D / np.linalg.norm(D, axis=-1, keepdims=True)).reshape(-1, 3)
    N = D.shape[0]
    L = np.array(light_dir, float); L /= np.linalg.norm(L)
    best = np.full(N, np.inf); col = np.tile(np.array(bg, float), (N, 1))
    if floor is not None:  # simple ground plane at y = floor
        with np.errstate(divide="ignore", invalid="ignore"):
            tf = (floor - campos[1]) / D[:, 1]
        m = np.isfinite(tf) & (tf > 0)
        best = np.where(m, tf, best)
        col[m] = np.array([0.22, 0.34, 0.26])
    trans = []
    for prim in prims:
        if prim["tr"] >= 0.3:
            trans.append(prim)
            continue
        t, nw = _intersect(prim, campos, D)
        m = t < best
        if not m.any():
            continue
        best[m] = t[m]
        col[m] = _shade(prim, nw[m], D[m], L)
    # transparent parts: painter's order, far to near
    trans.sort(key=lambda p: -np.linalg.norm(p["pos"] - campos))
    for prim in trans:
        t, nw = _intersect(prim, campos, D)
        m = t < best
        if not m.any():
            continue
        c = _shade(prim, nw[m], D[m], L)
        col[m] = col[m] * prim["tr"] + c * (1 - prim["tr"])
    img = (np.clip(col, 0, 1) * 255).astype(np.uint8).reshape(H, W, 3)
    im = Image.fromarray(img)
    if label:
        ImageDraw.Draw(im).text((5, 4), label, fill=(255, 235, 120))
    return im


def _shade(prim, n, d, L):
    base = prim["color"][None, :]
    if prim["mat"] in EMISSIVE:
        return np.repeat(base, n.shape[0], 0)
    # flip normals facing away (inside views)
    n = np.where(((n * d).sum(1) > 0)[:, None], -n, n)
    diff = np.clip(n @ L, 0, 1)
    c = base * (0.42 + 0.62 * diff[:, None])
    k = SHINY.get(prim["mat"], 0.05)
    if k:
        hvec = L[None, :] - d
        hvec /= np.linalg.norm(hvec, axis=1, keepdims=True)
        spec = np.clip((n * hvec).sum(1), 0, 1) ** 24
        c = c + k * spec[:, None]
    return c
