# A nicer preview renderer for Roblox primitive parts: anti-aliasing, a key light with soft-edged
# shadows, a fill light, a sky/ground ambient and a rim light. Still only a preview: Roblox's own
# renderer looks different (materials, real shadows, bloom).
import math
import numpy as np
from PIL import Image, ImageDraw
from rt import _intersect, prims_from_model, CORNERS

EMISSIVE = {"Neon"}
SHINY = {"Metal": 0.45, "Foil": 0.65, "Glass": 0.6, "DiamondPlate": 0.35, "Marble": 0.25, "Ice": 0.45,
         "SmoothPlastic": 0.18, "Plastic": 0.08, "Glacier": 0.3}
ROUGH = {"Fabric", "Sand", "Salt", "Concrete", "Slate", "Cardboard", "Carpet", "Grass", "LeafyGrass", "Ground",
         "Rock", "Pebble", "Brick", "Cobblestone", "WoodPlanks", "Wood", "CorrodedMetal", "Leather", "Rubber", "Plaster",
         "Snow", "Mud", "Limestone", "Sandstone", "Basalt", "Granite", "RoofShingles", "ClayRoofTiles", "Pavement", "Asphalt"}


def _screen_rect(prim, campos, f, r, u, th, W, H):
    pts = prim["pos"][None, :] + (CORNERS * (prim["size"] / 2)[None, :]) @ prim["R"].T
    v = pts - campos[None, :]
    z = v @ f
    if (z < 0.05).any():
        return None if (z < 0.05).all() else (0, W, 0, H)
    sx = (v @ r) / z / (th * W / H)
    sy = (v @ u) / z / th
    x0 = max(0, int(math.floor((sx.min() + 1) / 2 * W)) - 2)
    x1 = min(W, int(math.ceil((sx.max() + 1) / 2 * W)) + 2)
    y0 = max(0, int(math.floor((1 - sy.max()) / 2 * H)) - 2)
    y1 = min(H, int(math.ceil((1 - sy.min()) / 2 * H)) + 2)
    return (x0, x1, y0, y1) if x0 < x1 and y0 < y1 else None


def _bbox(prim):
    pts = prim["pos"][None, :] + (CORNERS * (prim["size"] / 2)[None, :]) @ prim["R"].T
    return pts.min(0), pts.max(0)


def _shadow(prims, P, L, res=900, bias=0.02, tan=None):
    """Shadow map from the key light (orthographic): 1 lit, 0 in shadow, soft edges (3x3 PCF)."""
    if P.shape[0] == 0:
        return np.ones(0)
    L = L / np.linalg.norm(L)
    helper = np.array([0, 0, 1.0]) if abs(L[2]) < 0.9 else np.array([1.0, 0, 0])
    lr = np.cross(helper, L); lr /= np.linalg.norm(lr)
    lu = np.cross(L, lr)
    occ = [p for p in prims if p["tr"] < 0.5 and p["mat"] not in EMISSIVE]
    if not occ:
        return np.ones(P.shape[0])
    allc = np.concatenate([p["pos"][None, :] + (CORNERS * (p["size"] / 2)[None, :]) @ p["R"].T for p in occ] + [P])
    xs = allc @ lr; ys = allc @ lu; zs = allc @ L
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    pad = 0.05 * max(x1 - x0, y1 - y0) + 0.05
    x0 -= pad; x1 += pad; y0 -= pad; y1 += pad
    far = zs.max() + 1.0
    span = max(x1 - x0, y1 - y0)
    px = span / res
    nx = int(math.ceil((x1 - x0) / px)); ny = int(math.ceil((y1 - y0) / px))
    depth = np.full((ny, nx), np.inf)
    for p in occ:
        c = p["pos"][None, :] + (CORNERS * (p["size"] / 2)[None, :]) @ p["R"].T
        cx = c @ lr; cy = c @ lu
        i0 = max(0, int((cx.min() - x0) / px) - 1); i1 = min(nx, int((cx.max() - x0) / px) + 2)
        j0 = max(0, int((cy.min() - y0) / px) - 1); j1 = min(ny, int((cy.max() - y0) / px) + 2)
        if i0 >= i1 or j0 >= j1:
            continue
        gi, gj = np.meshgrid(np.arange(i0, i1), np.arange(j0, j1))
        X = x0 + (gi + 0.5) * px; Y = y0 + (gj + 0.5) * px
        O = X.reshape(-1, 1) * lr[None, :] + Y.reshape(-1, 1) * lu[None, :] + far * L[None, :]
        t = _intersect_many(p, O, -L).reshape(gj.shape)
        sub = depth[j0:j1, i0:i1]
        depth[j0:j1, i0:i1] = np.minimum(sub, t)
    qx = (P @ lr - x0) / px - 0.5; qy = (P @ lu - y0) / px - 0.5
    tP = far - P @ L
    if tan is not None:
        bias = bias + 3.0 * px * np.minimum(tan, 8.0)
    lit = np.zeros(P.shape[0])
    for dj in (-1.5, 0, 1.5):
        for di in (-1.5, 0, 1.5):
            ii = np.clip(np.round(qx + di).astype(int), 0, nx - 1)
            jj = np.clip(np.round(qy + dj).astype(int), 0, ny - 1)
            lit += depth[jj, ii] >= tP - bias
    return lit / 9.0


def _intersect_many(prim, O, d):
    """Rays with many origins O (N,3) and one direction d against one primitive."""
    R = prim["R"]; c = prim["pos"]; h = prim["size"] / 2
    lo = (O - c) @ R
    ld = d @ R
    shape = prim["shape"]
    N = O.shape[0]
    if shape in ("S", "E"):
        if shape == "S":
            h = np.full(3, h.min())
        so = lo / h; sd = ld / h
        a = (sd * sd).sum(); b = (so * sd).sum(1); cc = (so * so).sum(1) - 1
        disc = b * b - a * cc
        ok = disc > 0
        sq = np.sqrt(np.where(ok, disc, 0))
        t0 = (-b - sq) / a; t1 = (-b + sq) / a
        tt = np.where(t0 > 1e-4, t0, np.where(t1 > 1e-4, t1, np.inf))
        return np.where(ok, tt, np.inf)
    if shape == "C":
        r = min(h[1], h[2]); L = h[0]
        a = ld[1] ** 2 + ld[2] ** 2
        best = np.full(N, np.inf)
        if a > 1e-12:
            b = ld[1] * lo[:, 1] + ld[2] * lo[:, 2]
            cc = lo[:, 1] ** 2 + lo[:, 2] ** 2 - r * r
            disc = b * b - a * cc
            ok = disc > 0
            sq = np.sqrt(np.where(ok, disc, 0))
            for ts in ((-b - sq) / a, (-b + sq) / a):
                x = lo[:, 0] + ld[0] * ts
                good = ok & (ts > 1e-4) & (np.abs(x) <= L) & (ts < best)
                best = np.where(good, ts, best)
        if abs(ld[0]) > 1e-12:
            for sgn in (-1, 1):
                tc = (sgn * L - lo[:, 0]) / ld[0]
                p = lo + np.outer(tc, ld)
                good = (tc > 1e-4) & (p[:, 1] ** 2 + p[:, 2] ** 2 <= r * r) & (tc < best)
                best = np.where(good, tc, best)
        return best
    with np.errstate(divide="ignore", invalid="ignore"):
        t1 = (-h[None, :] - lo) / ld; t2 = (h[None, :] - lo) / ld
    tmin_axes = np.nan_to_num(np.minimum(t1, t2), nan=-np.inf)
    tmax_axes = np.nan_to_num(np.maximum(t1, t2), nan=np.inf)
    if shape == "W":
        pn = np.array([0, h[2], -h[1]])
        denom = float(ld @ pn); num = -(lo @ pn)
        if abs(denom) < 1e-12:
            tmin_p = np.where(num < 0, np.inf, -np.inf); tmax_p = np.full(N, np.inf)
        else:
            tp = num / denom
            tmin_p = tp if denom < 0 else np.full(N, -np.inf)
            tmax_p = np.full(N, np.inf) if denom < 0 else tp
        tmin_axes = np.column_stack([tmin_axes, tmin_p]); tmax_axes = np.column_stack([tmax_axes, tmax_p])
    tmin = tmin_axes.max(1); tmax = tmax_axes.min(1)
    ok = (tmax >= tmin) & (tmax > 1e-4)
    return np.where(ok, np.where(tmin > 1e-4, tmin, np.inf), np.inf)


def render(prims, campos, look, W=320, H=320, fov=38, bg=(0.17, 0.19, 0.24), label=None, floor=0.0, ss=2,
           key=(-0.55, 0.85, -0.45), shadows=True, floor_color=(0.30, 0.36, 0.30)):
    Wr, Hr = W * ss, H * ss
    campos = np.array(campos, float); look = np.array(look, float)
    f = look - campos; f /= np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r); u = np.cross(r, f)
    th = math.tan(math.radians(fov / 2))
    ys, xs = np.mgrid[0:Hr, 0:Wr]
    px = (2 * (xs + 0.5) / Wr - 1) * th * Wr / Hr
    py = (1 - 2 * (ys + 0.5) / Hr) * th
    D = f[None, None, :] + px[..., None] * r[None, None, :] + py[..., None] * u[None, None, :]
    D = D / np.linalg.norm(D, axis=-1, keepdims=True)
    L = np.array(key, float); L /= np.linalg.norm(L)
    # background: a soft vertical gradient
    grad = np.linspace(1.08, 0.82, Hr)[:, None, None]
    col = np.tile(np.array(bg, float), (Hr, Wr, 1)) * grad
    best = np.full((Hr, Wr), np.inf)
    nbuf = np.zeros((Hr, Wr, 3))
    cbuf = np.zeros((Hr, Wr, 3))
    kind = np.zeros((Hr, Wr), int)  # 0 bg, 1 floor, 2 part
    pid = np.full((Hr, Wr), -1)
    if floor is not None:
        with np.errstate(divide="ignore", invalid="ignore"):
            tf = (floor - campos[1]) / D[..., 1]
        m = np.isfinite(tf) & (tf > 0)
        best = np.where(m, tf, best)
        kind[m] = 1
    solid = [p for p in prims if p["tr"] < 0.3]
    trans = [p for p in prims if p["tr"] >= 0.3]
    for i, prim in enumerate(solid):
        b = _screen_rect(prim, campos, f, r, u, th, Wr, Hr)
        if b is None:
            continue
        x0, x1, y0, y1 = b
        d = D[y0:y1, x0:x1].reshape(-1, 3)
        t, nw = _intersect(prim, campos, d)
        bs = best[y0:y1, x0:x1].reshape(-1)
        m = t < bs
        if not m.any():
            continue
        bs[m] = t[m]
        best[y0:y1, x0:x1] = bs.reshape(y1 - y0, x1 - x0)
        nb = nbuf[y0:y1, x0:x1].reshape(-1, 3); nb[m] = nw[m]; nbuf[y0:y1, x0:x1] = nb.reshape(y1 - y0, x1 - x0, 3)
        cb = cbuf[y0:y1, x0:x1].reshape(-1, 3); cb[m] = prim["color"]; cbuf[y0:y1, x0:x1] = cb.reshape(y1 - y0, x1 - x0, 3)
        kk = kind[y0:y1, x0:x1].reshape(-1); kk[m] = 2; kind[y0:y1, x0:x1] = kk.reshape(y1 - y0, x1 - x0)
        pp = pid[y0:y1, x0:x1].reshape(-1); pp[m] = i; pid[y0:y1, x0:x1] = pp.reshape(y1 - y0, x1 - x0)
    hitmask = kind > 0
    P = campos[None, None, :] + D * np.where(np.isfinite(best), best, 0)[..., None]
    # shadows
    lit = np.ones((Hr, Wr))
    if shadows and solid:
        idx = np.nonzero(hitmask.reshape(-1))[0]
        Pf = P.reshape(-1, 3)[idx]
        nf = nbuf.reshape(-1, 3)[idx]
        kf = kind.reshape(-1)[idx]
        nf = np.where((kf == 1)[:, None], np.array([0, 1.0, 0]), nf)
        cosl = np.clip(nf @ L, 0.08, 1.0)
        tanl = np.sqrt(1 - cosl ** 2) / cosl
        s = _shadow(solid, Pf + nf * 0.02, L, tan=tanl)
        lit.reshape(-1)[idx] = s
    # shading
    out = col.copy()
    # floor
    fm = kind == 1
    if fm.any():
        dist = np.sqrt(P[..., 0] ** 2 + P[..., 2] ** 2)
        fade = np.clip(1.15 - dist / 9.0, 0.55, 1.0)
        base = np.array(floor_color)
        out[fm] = (base[None, :] * (0.55 + 0.45 * lit[fm][:, None]) * fade[fm][:, None])
    pm = kind == 2
    if pm.any():
        n = nbuf[pm]
        d = D[pm]
        n = np.where(((n * d).sum(1) > 0)[:, None], -n, n)
        c = cbuf[pm]
        mats = np.array([solid[i]["mat"] for i in pid[pm]])
        diff = np.clip(n @ L, 0, 1) * lit[pm]
        hemi = 0.5 + 0.5 * n[:, 1]  # sky above, ground below
        amb = 0.30 + 0.16 * hemi
        fillL = np.array([0.6, 0.35, -0.7]); fillL /= np.linalg.norm(fillL)
        fill = np.clip(n @ fillL, 0, 1) * 0.16
        rim = np.clip(1 - np.abs((n * d).sum(1)), 0, 1) ** 3 * 0.22
        shade = amb + 0.78 * diff + fill
        cc = c * shade[:, None] + rim[:, None] * np.array([0.85, 0.9, 1.0])
        hv = L[None, :] - d
        hv /= np.linalg.norm(hv, axis=1, keepdims=True)
        spec_k = np.array([SHINY.get(m, 0.04) for m in mats])
        spec = np.clip((n * hv).sum(1), 0, 1) ** 28 * lit[pm]
        cc = cc + (spec_k * spec)[:, None]
        emis = np.array([m in EMISSIVE for m in mats])
        cc[emis] = np.clip(c[emis] * 1.15, 0, 1)
        out[pm] = cc
    # transparent parts on top (painter's order)
    trans.sort(key=lambda p: -np.linalg.norm(p["pos"] - campos))
    for prim in trans:
        b = _screen_rect(prim, campos, f, r, u, th, Wr, Hr)
        if b is None:
            continue
        x0, x1, y0, y1 = b
        d = D[y0:y1, x0:x1].reshape(-1, 3)
        t, nw = _intersect(prim, campos, d)
        bs = best[y0:y1, x0:x1].reshape(-1)
        m = t < bs
        if not m.any():
            continue
        cs = out[y0:y1, x0:x1].reshape(-1, 3)
        n = nw[m]
        dd = d[m]
        n = np.where(((n * dd).sum(1) > 0)[:, None], -n, n)
        diff = np.clip(n @ L, 0, 1)
        c = prim["color"][None, :] * (0.45 + 0.6 * diff[:, None])
        if prim["mat"] in EMISSIVE:
            c = np.repeat(prim["color"][None, :], m.sum(), 0)
        a = 1 - prim["tr"]
        cs[m] = cs[m] * (1 - a) + c * a
        out[y0:y1, x0:x1] = cs.reshape(y1 - y0, x1 - x0, 3)
    img = (np.clip(out, 0, 1) * 255).astype(np.uint8)
    im = Image.fromarray(img).resize((W, H), Image.LANCZOS)
    if label:
        ImageDraw.Draw(im).text((6, 5), label, fill=(255, 235, 140))
    return im


def view(model, size=360, yaw=-32, pitch=0.42, dist_k=1.75, label=True, back=False, zoom=1.0, look_k=0.45, focus=None):
    lo, hi = model.bounds()
    h = hi[1]
    span = max(hi[0] - lo[0], hi[2] - lo[2], h)
    look = (0, h * look_k, 0)
    dist = (span * dist_k + 1.0) / zoom
    if focus is not None:
        # look at a named part (a head close-up)
        fp = [p for p in model.parts if p["name"] == focus]
        if not fp:
            fp = [p for p in model.parts if p["name"] == "Eye"]
        if fp:
            look = tuple(np.mean([np.array(p["pos"], float) for p in fp], axis=0))
    a = math.radians(160 if back else yaw)
    cam = (look[0] + math.sin(a) * dist, look[1] + dist * pitch, look[2] - math.cos(a) * dist)
    prims = prims_from_model(model.parts)
    return render(prims, cam, look, size, size, fov=36, label=(f"{model.id} ({len(model.parts)})" if label else None))


def sheet(models, out, size=300, cols=4, **kw):
    tiles = [view(m, size, **kw) for m in models]
    rows = max(1, math.ceil(len(tiles) / cols))
    img = Image.new("RGB", (cols * size, rows * size), (18, 18, 22))
    for i, t in enumerate(tiles):
        img.paste(t, ((i % cols) * size, (i // cols) * size))
    img.save(out)
    return out
