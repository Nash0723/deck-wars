# Before/after preview of the calm + weight pass: old vs new terrain colors, tile plinths,
# creature bases, and a rough "pool of light" (the ray tracer has no lamps or shadows, so the
# darkness is only an approximation of what Studio will show).
# python3 preview/calm.py --w=560 --out=preview/calm.png
import sys, os, json, math
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lb"))
sys.path.insert(0, os.path.dirname(__file__))
import rt
import models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo, models_extra

OLD = {"Snack": (80, 150, 142), "Junk": (118, 113, 104), "Weather": (196, 210, 226), "Critter": (222, 176, 194), "Spooky": (138, 116, 174), "Robo": (70, 55, 55)}
NEW = {"Snack": (150, 84, 50), "Junk": (104, 94, 80), "Weather": (78, 112, 150), "Critter": (84, 120, 64), "Spooky": (96, 70, 128), "Robo": (118, 124, 142)}
middle = ["Spooky", "Weather", "Junk", "Critter", "Snack"]
def terrain_of(wc, wr):
    if wr <= 2: return "Snack"
    if wr >= 5: return "Robo"
    return middle[wc - 1]

allm = {}
for mod in [models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo, models_extra]:
    for fn in mod.MODELS:
        m = fn(); allm[m.id] = m

def load(room_path, colors):
    room = json.load(open(room_path))
    prims, tiles, heroes_at = [], {}, {}
    def walk(n):
        p = n.get("Properties", {})
        cls = n["ClassName"]
        if cls in ("Part", "Seat", "WedgePart", "SpawnLocation"):
            tr = p.get("Transparency", 0)
            if tr < 0.95:
                cf = p["CFrame"]["CFrame"]
                shape = "B"
                if cls == "WedgePart": shape = "W"
                elif p.get("Shape") == "Ball": shape = "S"
                elif p.get("Shape") == "Cylinder": shape = "C"
                for c in n.get("Children", []):
                    if c["ClassName"] == "SpecialMesh": shape = "E"
                color = np.array(p.get("Color", [0.6, 0.6, 0.6]), float)
                name = n.get("Name", "")
                if name in ("Hero_Near", "Hero_Far"):
                    heroes_at[name] = (cf["position"], p["Size"])
                if name.startswith("Tile_"):
                    wc, wr = int(name.split("_")[1]), int(name.split("_")[2])
                    tiles[(wc, wr)] = (cf["position"], p["Size"])
                    base = np.array(colors[terrain_of(wc, wr)], float) / 255
                    color = base * (1.0 if (wc + wr) % 2 == 0 else 0.88)
                prims.append(dict(shape=shape, size=np.array(p["Size"], float), pos=np.array(cf["position"], float),
                                  R=np.array(cf["orientation"], float), color=color, mat=p.get("Material", "Plastic"), tr=tr))
        for c in n.get("Children", []):
            walk(c)
    walk(room)
    return prims, tiles, heroes_at

def scaled(m, offset, yaw, s):
    parts = []
    for p in m.parts:
        q = dict(p)
        q["size"] = [v * s for v in p["size"]]
        q["pos"] = [v * s for v in p["pos"]]
        parts.append(q)
    return rt.prims_from_model(parts, offset, yaw)

def footprint(m):
    lo, hi = m.bounds()
    return max(hi[0] - lo[0], hi[2] - lo[2])

def disc(pos, d, h, color, mat="Slate"):
    R = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], float)  # cylinder axis (X) turned to point up
    return dict(shape="C", size=np.array([h, d, d], float), pos=np.array(pos, float), R=R, color=np.array(color, float) / 255, mat=mat, tr=0)

def board(tiles, heroes_at, bases):
    extra = []
    mine = [("pretzel_guard", 1, 2), ("snack_bar", 3, 2), ("queen_parfait", 3, 1), ("pancake_paladin", 2, 3), ("hot_sauce_imp", 4, 4), ("bouncy_castle", 5, 1)]
    theirs = [("roomba_rex", 2, 5), ("microwave_mage", 3, 6), ("charging_station", 4, 6), ("toaster_knight", 3, 4), ("mecha_fridge", 5, 5)]
    for side, lst, yaw in (("mine", mine, 0), ("theirs", theirs, 180)):
        for id, c, r in lst:
            m = allm[id]
            pos, size = tiles[(c, r)]
            top = pos[1] + size[1] / 2
            tile = size[0]
            gadget = m.kind == "gadget"
            s = min(0.56, tile * 0.96 / footprint(m)) if gadget else min(0.52, tile * 1.06 / footprint(m))
            extra += scaled(m, (pos[0], top, pos[2]), yaw, s)
            if bases and not gadget:
                you = side == "mine"
                extra.append(disc((pos[0], top + 0.05, pos[2]), 1.6, 0.1, (38, 44, 58) if you else (58, 38, 38)))
                extra.append(disc((pos[0], top + 0.0175, pos[2]), 1.7, 0.035, (80, 140, 215) if you else (205, 85, 85), "SmoothPlastic"))
    def hero_spot(name):
        pos, size = heroes_at[name]
        return (pos[0], pos[1] + size[0] / 2, pos[2])
    extra += scaled(allm["hero_bonk"], hero_spot("Hero_Near"), -20, 0.9)
    extra += scaled(allm["hero_granny_bolt"], hero_spot("Hero_Far"), 200, 0.9)
    extra += rt.prims_from_model(allm["bot_bonkers"].parts, (0, 0, -13.7), 180)
    return extra

def render_pool(prims, campos, look, W, H, fov, exposure, pool, label):
    # rt.render, then darken by distance from the middle of the board (a stand-in for the lamp's pool of light)
    im = rt.render(prims, campos, look, W, H, fov=fov, bg=(0.05, 0.05, 0.06), light_dir=(0.3, 1.0, 0.45))
    a = np.asarray(im).astype(float) / 255
    if pool:
        campos = np.array(campos, float); look = np.array(look, float)
        f = look - campos; f /= np.linalg.norm(f)
        r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r); u = np.cross(r, f)
        th = math.tan(math.radians(fov / 2))
        ys, xs = np.mgrid[0:H, 0:W]
        px = (2 * (xs + 0.5) / W - 1) * th * W / H
        py = (1 - 2 * (ys + 0.5) / H) * th
        D = f + px[..., None] * r + py[..., None] * u
        D /= np.linalg.norm(D, axis=-1, keepdims=True)
        # where each ray meets the table top plane (y = 4.4), roughly
        t = (4.4 - campos[1]) / np.where(np.abs(D[..., 1]) < 1e-6, -1e-6, D[..., 1])
        P = campos + t[..., None] * D
        dist = np.sqrt(P[..., 0] ** 2 + (P[..., 2] * 0.8) ** 2)
        k = np.clip(1.0 - (dist - 7.0) / 9.0, 0.32, 1.0)
        k = np.where(t > 0, k, 0.32)
        a = a * k[..., None]
    a = np.clip(a * exposure, 0, 1)
    out = Image.fromarray((a * 255).astype(np.uint8))
    ImageDraw.Draw(out).text((6, 5), label, fill=(255, 235, 120))
    return out

Wd = 560
out = "preview/calm.png"
for a in sys.argv[1:]:
    if a.startswith("--w="): Wd = int(a[4:])
    if a.startswith("--out="): out = a[6:]
Hd = Wd * 9 // 16
cam = ((0, 16, 12), (0, 4.2, 1.25), 48)
old_room = sys.argv[sys.argv.index("--old") + 1] if "--old" in sys.argv else "src/world/MenuRoom.model.json"
p0, t0, h0 = load(old_room, OLD)
p1, t1, h1 = load("src/world/MenuRoom.model.json", NEW)
im0 = render_pool(p0 + board(t0, h0, False), cam[0], cam[1], Wd, Hd, cam[2], 1.08, False, "Before (last update)")
im1 = render_pool(p1 + board(t1, h1, True), cam[0], cam[1], Wd, Hd, cam[2], 0.95, True, "After: deep family colors, plinths, creature bases, darker room (rough preview)")
sheet = Image.new("RGB", (Wd, Hd * 2))
sheet.paste(im0, (0, 0))
sheet.paste(im1, (0, Hd))
sheet.save(out)
print("saved", out)
