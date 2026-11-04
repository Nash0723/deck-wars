# Renders the tile board the way the new client lays it out.
# python3 preview/tiles.py [--w=640] [--out=preview/tiles.png] [--cams=seat,top]
import sys, os, json, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lb"))
sys.path.insert(0, os.path.dirname(__file__))
import rt
import models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo, models_extra

room = json.load(open("src/world/MenuRoom.model.json"))
TERRAIN = {"Snack": (80, 150, 142), "Junk": (118, 113, 104), "Weather": (196, 210, 226), "Critter": (222, 176, 194), "Spooky": (138, 116, 174), "Robo": (60, 50, 50)}
SLOT = (70, 64, 60)
def terrain_of(wc, wr):
    # each side's lanes: near side Snack Snack Critter Critter, far side Robo Robo Junk Junk
    if wr in (0, 7): return None
    if wr <= 3: return "Snack" if wc <= 2 else "Critter"
    return "Robo" if wc >= 3 else "Junk"
prims = []
tiles = {}
heroes_at = {}
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
                fam = terrain_of(wc, wr)
                base = np.array(TERRAIN[fam] if fam else SLOT, float) / 255
                color = base * (1.0 if (wc + wr) % 2 == 0 else 0.9)
            prims.append(dict(shape=shape, size=np.array(p["Size"], float), pos=np.array(cf["position"], float),
                              R=np.array(cf["orientation"], float), color=color, mat=p.get("Material", "Plastic"), tr=tr))
    for c in n.get("Children", []):
        walk(c)
walk(room)

allm = {}
for mod in [models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo, models_extra]:
    for fn in mod.MODELS:
        m = fn(); allm[m.id] = m

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

def place(id, wc, wr, yaw):
    m = allm[id]
    pos, size = tiles[(wc, wr)]
    top = pos[1] + size[1] / 2
    tile = min(size[0], size[2])
    if m.kind == "gadget":
        s = min(0.56, tile * 0.96 / footprint(m))
    else:
        s = min(0.52, tile * 1.06 / footprint(m))
    return scaled(m, (pos[0], top, pos[2]), yaw, s)

extra = []
mine = [("pretzel_guard", 1, 2), ("snack_bar", 3, 0), ("queen_parfait", 3, 1), ("pancake_paladin", 2, 3), ("hot_sauce_imp", 4, 4), ("bouncy_castle", 1, 0)]
theirs = [("roomba_rex", 2, 5), ("microwave_mage", 3, 6), ("charging_station", 4, 7), ("toaster_knight", 3, 4), ("mecha_fridge", 4, 5)]
for id, c, r in mine: extra += place(id, c, r, 0)
for id, c, r in theirs: extra += place(id, c, r, 180)
def hero_spot(name):
    pos, size = heroes_at[name]
    return (pos[0], pos[1] + size[0] / 2, pos[2])  # cylinder: X is its height
extra += scaled(allm["hero_bonk"], hero_spot("Hero_Near"), -20, 0.9)
extra += scaled(allm["hero_granny_bolt"], hero_spot("Hero_Far"), 200, 0.9)
extra += rt.prims_from_model(allm["bot_bonkers"].parts, (0, 0, -13.7), 180)

Wd = 640
out = "preview/tiles.png"
which = "seat,top"
for a in sys.argv[1:]:
    if a.startswith("--w="): Wd = int(a[4:])
    if a.startswith("--out="): out = a[6:]
    if a.startswith("--cams="): which = a[7:]
Hd = Wd * 9 // 16
CAMS = {
    "seat": ("Seat (match camera)", (0, 14.4, 12.6), (0, 3.6, 0.3), 60),
    "you": ("SeatYou", (0, 16, 16), (0, 4.2, 3.4), 46),
    "opp": ("SeatOpp", (0, 16, 16.5), (0, 4.0, 2.2), 50),
    "oldseat": ("Old seat camera", (0, 16.2, 14.5), (0, 3.4, 0.2), 60),
    "top": ("Table from the room", (0, 17, 24), (0, 4, 0), 70),
    "far": ("Far side", (0, 19.5, -15.0), (0, 3.6, -0.8), 58),
}
cams = [CAMS[k] for k in which.split(",")]
ims = [rt.render(prims + extra, cp, lk, Wd, Hd, fov=fov, label=name, bg=(0.1, 0.1, 0.12), light_dir=(0.3, 1.0, 0.45)) for name, cp, lk, fov in cams]
sheet = Image.new("RGB", (Wd, Hd * len(ims)))
for i, im in enumerate(ims):
    sheet.paste(im, (0, i * Hd))
sheet.save(out)
print("saved", out)
