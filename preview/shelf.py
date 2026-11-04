# Renders the Pack Party corner from the station camera, with the mascot figurines the client
# puts on the shelf, and the station panel's spot outlined on the right (so the shelf isn't hidden).
# python3 preview/shelf.py [--w=960] [--cam=x,y,z,lx,ly,lz] [--out=preview/shelf.png]
import sys, os, json, math
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import rt
import models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo

MASCOT_HEIGHT = 2.2  # same as PackShelf.MascotHeight
room = json.load(open("src/world/MenuRoom.model.json"))
prims, spots = [], {}


def walk(n):
    p = n.get("Properties", {})
    cls = n["ClassName"]
    if cls in ("Part", "Seat", "WedgePart"):
        cf = p["CFrame"]["CFrame"]
        if n["Name"].startswith("MascotSpot_"):
            spots[n["Name"][11:]] = (np.array(cf["position"], float), np.array(cf["orientation"], float))
        tr = p.get("Transparency", 0)
        if tr < 0.95:
            shape = "B"
            if cls == "WedgePart":
                shape = "W"
            elif p.get("Shape") == "Ball":
                shape = "S"
            elif p.get("Shape") == "Cylinder":
                shape = "C"
            for c in n.get("Children", []):
                if c["ClassName"] == "SpecialMesh":
                    shape = "E"
            prims.append(dict(shape=shape, size=np.array(p["Size"], float), pos=np.array(cf["position"], float),
                              R=np.array(cf["orientation"], float), color=np.array(p.get("Color", [0.6, 0.6, 0.6]), float),
                              mat=p.get("Material", "Plastic"), tr=tr))
    for c in n.get("Children", []):
        walk(c)


walk(room)
allm = {}
for mod in [models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo]:
    for fn in mod.MODELS:
        m = fn()
        allm[m.id] = m
mascots = {}
for line in open("src/packbrawl/Packs.luau"):
    if line.strip().startswith("{ id ="):
        pid = line.split('id = "')[1].split('"')[0]
        if 'mascot = "' in line:
            mascots[pid] = line.split('mascot = "')[1].split('"')[0]
for pid, (pos, R) in spots.items():
    m = allm[mascots[pid]]
    h = max(p["pos"][1] + p["size"][1] / 2 for p in m.parts)
    s = MASCOT_HEIGHT / h
    for p in m.parts:
        if p["tr"] >= 0.98:
            continue
        prims.append(dict(shape=p["shape"], size=np.array(p["size"], float) * s, pos=R @ (np.array(p["pos"], float) * s) + pos,
                          R=R @ np.array(p["R"], float), color=np.array(p["color"], float) / 255, mat=p["mat"], tr=p["tr"]))

cam = ((12.1, 9.0, -6.9), (19.6, 5.6, -14.9))
W = 960
out = "preview/shelf.png"
for a in sys.argv[1:]:
    if a.startswith("--cam="):
        v = [float(x) for x in a[6:].split(",")]
        cam = (tuple(v[:3]), tuple(v[3:]))
    elif a.startswith("--w="):
        W = int(a[4:])
    elif a.startswith("--out="):
        out = a[6:]
H = W * 9 // 16
im = rt.render(prims, cam[0], cam[1], W, H, fov=70, bg=(0.1, 0.1, 0.12), light_dir=(0.3, 1.0, 0.45), label="Pack Party")
# the station panel: 390 x 480 px at the right edge of a 1280 x 720 screen, 24 px in
k = W / 1280
d = ImageDraw.Draw(im)
d.rectangle([W - (24 + 390) * k, H / 2 - 260 * k, W - 24 * k, H / 2 + 220 * k], outline=(255, 220, 90), width=2)
im.save(out)
print("saved", out)
