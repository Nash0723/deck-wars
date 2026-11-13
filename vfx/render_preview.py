#!/usr/bin/env python3
"""Renders what LayerFx does with the sheets, without Roblox.

    luaurun -D FX_DUMP=1 mock_roblox/fxharness.luau mock_roblox | grep ^FRAME > frames.txt
    python3 vfx/render_preview.py frames.txt vfx/

Writes effects_strip.png (every effect, frame by frame) and effects.gif (all of them playing).
The frames are the real ones the game code computes (sizes, turns, fades, colours).
"""
import os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
Q = 512
BG = (22, 28, 44)
sheets = {}


def quad(sheet, ox, oy):
    key = (sheet, ox, oy)
    if key not in sheets:
        im = Image.open(os.path.join(HERE, "sheets", sheet + ".png")).convert("RGBA")
        sheets[key] = im.crop((ox, oy, ox + Q, oy + Q))
    return sheets[key]


def draw_frame(sprites, size):
    canvas = Image.new("RGBA", (size, size), BG + (255,))
    box = size / 1.7          # the holder is this big; the rest is room for overshoot
    off = (size - box) / 2
    for sp in sorted(sprites, key=lambda s: s["z"]):
        w, h = sp["sx"] * box, sp["sy"] * box
        if w < 1 or h < 1:
            continue
        q = quad(sp["sheet"], sp["ox"], sp["oy"]).resize((max(1, int(w)), max(1, int(h))), Image.BILINEAR)
        a = np.asarray(q, np.float32) / 255
        a[..., 0] *= sp["r"] / 255; a[..., 1] *= sp["g"] / 255; a[..., 2] *= sp["b"] / 255
        a[..., 3] *= (1 - sp["tr"])
        q = Image.fromarray((a * 255).astype(np.uint8), "RGBA")
        # where its middle is (Roblox turns a picture around its middle, wherever its anchor is)
        cx = off + sp["px"] * box + (0.5 - sp["ax"]) * w
        cy = off + sp["py"] * box + (0.5 - sp["ay"]) * h
        if abs(sp["rot"]) > 0.01:
            q = q.rotate(-sp["rot"], Image.BILINEAR, expand=True)
        canvas.alpha_composite(q, (int(cx - q.width / 2), int(cy - q.height / 2))) if (0 <= int(cx - q.width / 2) and 0 <= int(cy - q.height / 2) and int(cx - q.width / 2) + q.width <= size and int(cy - q.height / 2) + q.height <= size) else paste_clipped(canvas, q, int(cx - q.width / 2), int(cy - q.height / 2))
    return canvas.convert("RGB")


def paste_clipped(canvas, q, x, y):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(q, (x, y))
    canvas.alpha_composite(layer)


def main():
    src, out = sys.argv[1], sys.argv[2]
    fx = {}
    for line in open(src):
        parts = line.rstrip("\n").split(" ", 3)
        name, f = parts[1], int(parts[2])
        sprites = []
        if len(parts) > 3 and parts[3]:
            for s in parts[3].split(";"):
                v = s.split(",")
                sprites.append(dict(sheet=v[0][:-1], ox=int(v[1]), oy=int(v[2]), px=float(v[3]), py=float(v[4]), sx=float(v[5]), sy=float(v[6]),
                                    rot=float(v[7]), tr=float(v[8]), r=int(v[9]), g=int(v[10]), b=int(v[11]), z=int(v[12]), ax=float(v[13]), ay=float(v[14])))
        fx.setdefault(name, {})[f] = sprites
    names = list(fx.keys())
    # the strip: 8 moments of each effect
    cell, cols = 200, 8
    strip = Image.new("RGB", (cell * cols, cell * len(names)), BG)
    for r, n in enumerate(names):
        frames = sorted(fx[n].keys())
        live = [f for f in frames if fx[n][f]]
        for c in range(cols):
            f = live[min(len(live) - 1, int(c * (len(live) - 1) / (cols - 1) * 0.92))]
            strip.paste(draw_frame(fx[n][f], cell), (c * cell, r * cell))
    strip.save(os.path.join(out, "effects_strip.png"))
    # the gif: all of them looping on one board
    cell, per_row = 220, 5
    rows = (len(names) + per_row - 1) // per_row
    longest = max(len(v) for v in fx.values()) + 8
    gif = []
    for f in range(1, longest + 1):
        im = Image.new("RGB", (cell * per_row, cell * rows), BG)
        for i, n in enumerate(names):
            im.paste(draw_frame(fx[n].get(f, []), cell), ((i % per_row) * cell, (i // per_row) * cell))
        gif.append(im)
    gif[0].save(os.path.join(out, "effects.gif"), save_all=True, append_images=gif[1:], duration=50, loop=0, optimize=True)
    print("wrote", len(names), "effects,", longest, "frames")


if __name__ == "__main__":
    main()
