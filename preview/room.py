# Renders the room from each menu camera, with sample creatures on the table for the match view.
# python3 preview/room.py [--match-only] [--w=480]
import sys, os, json, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lb"))
sys.path.insert(0, os.path.dirname(__file__))
import rt

room = json.load(open("src/world/MenuRoom.model.json"))
prims = []


def walk(n):
    p = n.get("Properties", {})
    cls = n["ClassName"]
    if cls in ("Part", "Seat", "WedgePart", "SpawnLocation"):
        tr = p.get("Transparency", 0)
        if tr < 0.95:
            cf = p["CFrame"]["CFrame"]
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
print("prims", len(prims))

# sample creatures for the match view
import models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo, models_extra
allm = {}
for mod in [models_snack, models_junk, models_weather, models_critter, models_spooky, models_robo, models_extra]:
    for fn in mod.MODELS:
        m = fn()
        allm[m.id] = m
board_y = 4.24
sample = [("toaster_knight", -6, 3.2, 180), ("queen_parfait", 0, 3.2, 180), ("couch_golem", 6, 3.2, 180),
          ("haunted_vending_machine", -6, -3.2, 0), ("lightning_llama", 0, -3.2, 0), ("big_momma_moose", 6, -3.2, 0)]
extra = []
for (mid, x, z, yaw) in sample:
    extra += rt.prims_from_model(allm[mid].parts, (x, board_y, z), yaw)
extra += rt.prims_from_model(allm["hero_bonk"].parts, (-10.0, 4.96, 3.2), 180)
extra += rt.prims_from_model(allm["hero_granny_bolt"].parts, (-10.0, 4.96, -3.2), 0)
extra += rt.prims_from_model(allm["lemonade_stand"].parts, (0, 4.15, 6.75), 180)
extra += rt.prims_from_model(allm["haunted_arcade"].parts, (6, 4.15, -6.75), 0)
extra += rt.prims_from_model(allm["bot_bonkers"].parts, (0, 0, -11), 180)

CAMS = {
    "Overview": ((0, 15, 22), (0, 3, -6)),
    "Seat (match view)": ((0, 16, 17), (0, 3, -1)),
    "DuelTable": ((0, 14, 19), (0, 4, 0)),
    "DeckShelf": ((-9, 8, 0), (-22, 6, 0)),
    "PackParty": ((5, 9, -5), (17, 5, -17)),
    "ShopCounter": ((6, 8, 5), (15, 5, 17)),
    "TrophyWall": ((11, 9, 0), (23.5, 8, 0)),
    "Radio": ((-9, 7, -9), (-17, 4, -18)),
}
for a in sys.argv[1:]:
    if a.startswith("--cam="):
        name, vals = a[6:].split(":")
        v = [float(x) for x in vals.split(",")]
        CAMS = {name: ((v[0], v[1], v[2]), (v[3], v[4], v[5]))}
Wd = 480
for a in sys.argv[1:]:
    if a.startswith("--w="):
        Wd = int(a[4:])
Hd = Wd * 9 // 16
match_only = "--match-only" in sys.argv
ims = []
for name, (cp, lk) in CAMS.items():
    if match_only and not name.startswith("Seat"):
        continue
    ps = prims + (extra if name.startswith(("Seat", "DuelTable", "Overview")) else [])
    ims.append(rt.render(ps, cp, lk, Wd, Hd, fov=70, label=name, bg=(0.1, 0.1, 0.12), light_dir=(0.3, 1.0, 0.45)))
cols = 2 if len(ims) > 1 else 1
rows = math.ceil(len(ims) / cols)
sheet = Image.new("RGB", (Wd * cols, Hd * rows))
for i, im in enumerate(ims):
    sheet.paste(im, ((i % cols) * Wd, (i // cols) * Hd))
out = "preview/room.png" if not match_only else "preview/match.png"
for a in sys.argv[1:]:
    if a.startswith("--out="):
        out = a[6:]
sheet.save(out)
print("saved", out)
