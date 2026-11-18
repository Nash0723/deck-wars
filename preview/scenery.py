# Renders the biome scenery on a 1v1 Duel Table (rough preview: no textures, lamps or shadows).
# 1) luaurun -D FAR=... -D NEAR=... preview/scenery_dump.luau mock_roblox > parts.jsonl
# 2) python3 preview/scenery.py parts.jsonl --out=scenery.png [--w=1280] [--shot=seat|far|close:<lane>]
import sys, os, json, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import rt

args = dict(a[2:].split("=", 1) for a in sys.argv[2:] if a.startswith("--") and "=" in a)
W = int(args.get("w", 1280)); H = W * 9 // 16
shot = args.get("shot", "seat")
near = args.get("near", "Spooky,Robo,Snack,Junk").split(",")
far = args.get("far", "Snack,Junk,Weather,Critter").split(",")

FAM = {"Snack": (255, 150, 90), "Junk": (140, 130, 110), "Weather": (120, 190, 255), "Critter": (150, 220, 110), "Spooky": (170, 110, 220), "Robo": (200, 200, 215)}
SHADE = {"Snack": 0.12, "Junk": 0.3, "Weather": 0.05, "Critter": 0.25, "Spooky": 0.3, "Robo": 0.25}
MAT = {"Snack": "Sand", "Junk": "CorrodedMetal", "Weather": "Snow", "Critter": "Grass", "Spooky": "Slate", "Robo": "DiamondPlate"}
ACCENT = {"Snack": (255, 170, 70), "Junk": (255, 120, 220), "Weather": (150, 220, 255), "Critter": (255, 200, 225), "Spooky": (190, 120, 255), "Robo": (255, 120, 40)}


def ground(f):
    c = np.array(FAM[f], float); d = np.array((30, 26, 32), float)
    return (c + (d - c) * SHADE[f]) / 255


I3 = np.eye(3)
FLAT = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], float)  # cylinder axis (x) turned to point up


def box(size, pos, color, mat="SmoothPlastic", shape="B", R=I3, tr=0.0):
    return dict(shape=shape, size=np.array(size, float), pos=np.array(pos, float), R=np.array(R, float),
                color=np.array(color, float) / (255 if max(color) > 1.0001 else 1), mat=mat, tr=tr)


prims = []
# the table and its felt
prims.append(box((25, 1.2, 22), (0, 3.4, 0), (92, 58, 36), "Wood"))
prims.append(box((23.4, 0.1, 20.4), (0, 4.05, 0), (34, 92, 60), "Fabric"))
for sx, sz, x, z in [(25.4, 0.9, 0, 10.55), (25.4, 0.9, 0, -10.55), (0.9, 22.4, 12.05, 0), (0.9, 22.4, -12.05, 0)]:
    prims.append(box((sx, 0.5, sz), (x, 4.2, z), (70, 43, 27), "Wood"))
pitch, width, half, frame, base = 3.075, 4, 7.35, 0.36, 4.1
gtop = base + 0.26
Wd = pitch * width / 2
prims.append(box((2 * (Wd + frame), 0.12, 2 * (half + frame)), (0, base + 0.06, 0), (46, 36, 32), "Wood"))
fh = gtop + 0.16 - base
for sx in (-1, 1):
    prims.append(box((frame, fh, 2 * (half + frame)), (sx * (Wd + frame / 2), base + fh / 2, 0), (150, 105, 65), "Wood"))
    prims.append(box((2 * Wd, fh, frame), (0, base + fh / 2, sx * (half + frame / 2)), (150, 105, 65), "Wood"))
prims.append(box((2 * Wd, 0.03, 0.08), (0, gtop + 0.01, 0), (215, 175, 80), "SmoothPlastic", tr=0.2))


def lane_x(l):
    return (l - (width + 1) / 2) * pitch


spot = min(pitch * 0.82, 2.1)
for s, lands in ((1, near), (-1, far)):
    for l, f in enumerate(lands, 1):
        x = lane_x(l)
        g = ground(f)
        gb = base + 0.12
        prims.append(box((pitch, gtop - gb, half), (x, gb + (gtop - gb) / 2, s * half / 2), g, MAT[f]))
        for z, k in ((1.95, 0.3), (4.2, 0.12)):
            prims.append(box((0.02, spot, spot), (x, gtop + 0.006, s * z), np.array(ACCENT[f]) / 255, "SmoothPlastic", "C", FLAT, tr=0.6))
            pad = g + (1 - g) * k
            prims.append(box((0.02, spot - 0.16, spot - 0.16), (x, gtop + 0.012, s * z), pad, "SmoothPlastic", "C", FLAT, tr=0.35))
        prims.append(box((pitch * 0.58 + 0.14, 0.02, 1.64), (x, gtop + 0.008, s * 6.25), (28, 22, 24), tr=0.15))
        prims.append(box((pitch * 0.58, 0.03, 1.5), (x, gtop + 0.016, s * 6.25), g * 0.6 + np.array((20, 16, 18)) / 255 * 0.4, "Cobblestone"))
    for l in range(1, width):
        prims.append(box((0.05, 0.03, half - 0.12), ((lane_x(l) + lane_x(l + 1)) / 2, gtop + 0.005, s * (half / 2 + 0.06)), (22, 18, 20), tr=0.4))

# Stand-ins for what is on the board in a match: a card under each unit, a creature or a building
# on it (so you can judge what the scenery might cover).
def creature(x, z, col):
    prims.append(box((1.5, 0.04, 2.05), (x, gtop + 0.04, z), (240, 232, 215)))
    prims.append(box((0.9, 1.0, 0.7), (x, gtop + 0.55, z), col, "SmoothPlastic", "E"))
    prims.append(box((0.6, 0.6, 0.6), (x, gtop + 1.25, z), col, "SmoothPlastic", "S"))


def building(x, z, col):
    prims.append(box((1.5, 0.04, 2.05), (x, gtop + 0.04, z), (240, 232, 215)))
    prims.append(box((1.3, 1.1, 1.0), (x, gtop + 0.6, z), col, "WoodPlanks"))
    prims.append(box((1.0, 0.5, 0.8), (x, gtop + 1.4, z), (170, 60, 50)))


for l, z, c in [(1, 1.95, (230, 120, 90)), (2, 4.2, (120, 160, 230)), (3, 1.95, (150, 210, 120)), (4, 1.95, (220, 200, 120))]:
    creature(lane_x(l), z, c)
for l, z, c in [(1, -1.95, (180, 120, 230)), (2, -1.95, (230, 150, 200)), (3, -4.2, (110, 200, 200)), (4, -1.95, (200, 200, 210))]:
    creature(lane_x(l), z, c)
building(lane_x(2), 6.25, (150, 110, 70))
building(lane_x(3), -6.25, (120, 120, 140))
building(lane_x(1), -6.25, (140, 100, 80))
# heroes on their pedestals
for z in (3.9, -3.9):
    prims.append(box((0.5, 2.2, 2.2), (-8.75, base + 0.25, z), (60, 50, 60), "SmoothPlastic", "C", FLAT))
    prims.append(box((0.9, 1.5, 0.8), (-8.75, base + 1.3, z), (210, 170, 120), "SmoothPlastic", "E"))

# the scenery itself
for line in open(sys.argv[1]):
    if not line.startswith("{"):
        continue
    p = json.loads(line)
    prims.append(dict(shape=p["shape"], size=np.array(p["size"], float), pos=np.array(p["pos"], float), R=np.array(p["R"], float),
                      color=np.array(p["color"], float), mat=p["mat"], tr=p["tr"]))

if shot == "seat":
    cam, look, fov = (0, 15.8, 12.8), (0, 4.1, 0.2), 50
elif shot == "far":
    cam, look, fov = (0, 11, 2.5), (0, 4.8, -7.5), 55
elif shot.startswith("close:"):
    l = int(shot.split(":")[1])
    x = lane_x(l)
    cam, look, fov = (x * 0.9, 7.6, -3.2), (x, 5.2, -8.6), 50
elif shot.startswith("lane:"):
    l = int(shot.split(":")[1])
    x = lane_x(l)
    cam, look, fov = (x + 1.2, 8.5, 6), (x, 4.4, 1.5), 50
im = rt.render(prims, cam, look, W=W, H=H, fov=fov, bg=(0.12, 0.1, 0.13), light_dir=(-0.35, 0.9, 0.45))
im.save(args.get("out", "scenery.png"))
print("saved", args.get("out", "scenery.png"), len(prims), "prims")
