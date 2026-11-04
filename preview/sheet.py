# Renders a contact sheet of models: python3 preview/sheet.py <module> [<module> ...] [--out=file.png] [--back] [--only=id,id] [--size=260] [--cols=5]
import sys, os, math, importlib
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.dirname(__file__))
from PIL import Image
import rt

args = [a for a in sys.argv[1:] if not a.startswith("--")]
out = "preview/models.png"
back = "--back" in sys.argv
for a in sys.argv[1:]:
    if a.startswith("--out="):
        out = a[6:]
only = None
for a in sys.argv[1:]:
    if a.startswith("--only="):
        only = set(a[7:].split(","))

models = []
for modname in args:
    mod = importlib.import_module(modname)
    for fn in mod.MODELS:
        m = fn()
        if only and m.id not in only:
            continue
        models.append(m)

tiles = []
S = 260
cols = 5
for a in sys.argv[1:]:
    if a.startswith("--size="):
        S = int(a[7:])
    if a.startswith("--cols="):
        cols = int(a[7:])
for m in models:
    lo, hi = m.bounds()
    h = hi[1]
    size = max(hi[0] - lo[0], hi[2] - lo[2], h)
    look = (0, h * 0.45, 0)
    dist = size * 1.75 + 1.2
    yaw = math.radians(160 if back else -30)
    cam = (math.sin(yaw) * dist, h * 0.5 + dist * 0.45, -math.cos(yaw) * dist)
    prims = rt.prims_from_model(m.parts)
    im = rt.render(prims, cam, look, S, S, fov=38, label=f"{m.id} ({len(m.parts)})", floor=0)
    tiles.append(im)

rows = max(1, math.ceil(len(tiles) / cols))
sheet = Image.new("RGB", (cols * S, rows * S), (20, 20, 25))
for i, im in enumerate(tiles):
    sheet.paste(im, ((i % cols) * S, (i // cols) * S))
sheet.save(out)
print("saved", out, len(tiles), "models")
