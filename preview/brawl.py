# Renders Pack Brawl snapshots printed by mock_roblox/pullharness.luau (run it with -D SNAP=1).
# Rough preview only (primitive parts, simple shading): it checks framing and staging,
# not the real Roblox look. Usage: python3 preview/brawl.py <harness log> <out dir>
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
import rt


def parse(path):
    snaps, cur = [], None
    for line in open(path):
        line = line.rstrip("\n")
        if line.startswith("SNAP|"):
            cur = {"name": line[5:], "parts": [], "over": []}
        elif cur is None:
            continue
        elif line.startswith("PART|"):
            f = line.split("|")
            shape = f[1]
            v = list(map(float, f[2:17]))
            pos = np.array(v[0:3]); R = np.array(v[3:12]).reshape(3, 3); size = np.array(v[12:15])
            col = np.array(list(map(int, f[17:20]))) / 255.0
            cur["parts"].append(dict(shape=shape, pos=pos, R=R, size=size, color=col, tr=float(f[20]), mat=f[21]))
        elif line.startswith("CAM|"):
            f = line.split("|")
            v = list(map(float, f[1:13]))
            cur["cam"] = (np.array(v[0:3]), np.array(v[3:12]).reshape(3, 3), float(f[13]))
        elif line.startswith("OVER|"):
            f = line.split("|")
            cur["over"].append((np.array(list(map(int, f[1:4]))) / 255.0, float(f[4])))
        elif line == "END":
            snaps.append(cur); cur = None
    return snaps


def render(snap, W=480, H=270):
    pos, R, fov = snap["cam"]
    right, up, back = R[:, 0], R[:, 1], R[:, 2]
    fwd = -back
    th = math.tan(math.radians(fov / 2))
    ys, xs = np.mgrid[0:H, 0:W]
    px = (2 * (xs + 0.5) / W - 1) * th * W / H
    py = (1 - 2 * (ys + 0.5) / H) * th
    D = fwd[None, None, :] + px[..., None] * right[None, None, :] + py[..., None] * up[None, None, :]
    D = (D / np.linalg.norm(D, axis=-1, keepdims=True)).reshape(-1, 3)
    L = np.array([0.2, 1.0, 0.4]); L /= np.linalg.norm(L)
    best = np.full(D.shape[0], np.inf)
    col = np.tile(np.array([0.05, 0.04, 0.08]), (D.shape[0], 1))
    # only parts in front of the camera and not too far away (skip the far specks for speed)
    prims = [p for p in snap["parts"] if np.dot(p["pos"] - pos, fwd) > -5 and np.linalg.norm(p["pos"] - pos) < 120]
    trans = []
    for p in prims:
        if p["tr"] >= 0.3:
            trans.append(p); continue
        t, nw = rt._intersect(p, pos, D)
        m = t < best
        if m.any():
            best[m] = t[m]; col[m] = rt._shade(p, nw[m], D[m], L)
    trans.sort(key=lambda p: -np.linalg.norm(p["pos"] - pos))
    for p in trans:
        t, nw = rt._intersect(p, pos, D)
        m = t < best
        if m.any():
            col[m] = col[m] * p["tr"] + rt._shade(p, nw[m], D[m], L) * (1 - p["tr"])
    for c, a in snap["over"]:
        col = col * (1 - a) + c[None, :] * a
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8).reshape(H, W, 3))
    ImageDraw.Draw(img).text((6, 5), snap["name"], fill=(255, 235, 120))
    return img


if __name__ == "__main__":
    snaps = parse(sys.argv[1])
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    imgs = []
    for s in snaps:
        im = render(s)
        im.save(os.path.join(out, s["name"] + ".png"))
        imgs.append(im)
    # contact sheet, 4 per row
    if imgs:
        cols = 4
        rows = (len(imgs) + cols - 1) // cols
        w, h = imgs[0].size
        sheet = Image.new("RGB", (cols * w, rows * h), (0, 0, 0))
        for i, im in enumerate(imgs):
            sheet.paste(im, ((i % cols) * w, (i // cols) * h))
        sheet.save(os.path.join(out, "sheet.png"))
    print(len(snaps), "snapshots")
