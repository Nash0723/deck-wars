# Generates src/world/MenuRoom.model.json: the cozy game room with all stations and the duel table.
# Props are built with modelkit (same kit as the creatures) and converted to Rojo model JSON.
# Names the scripts rely on: Stations/<DuelTable|DeckShelf|PackParty|ShopCounter|TrophyWall|Radio>,
# DuelTable/Seat_Near, Seat_Far, Board/Tile_<column 1-4>_<row 1-6> (row 1 nearest Seat_Near), building slots
# Board/Tile_<column>_0 (near) and Tile_<column>_7 (far), Hero_<side>,
# HeroGlow_<side>, Energy_<side>_<1-8>, Deck_<side>, Discard_<side>, TableLamp,
# Structure/FireLight, PackParty/PackShelf/ShelfPack_<pack id> (PackBody, ...), MascotSpot_<pack id>, MarqueeBulb,
# DiscoBall, DiscoTile, PartyLight*, StringLight, and "Sign" billboards.
import json, math
import numpy as np
from modelkit import Model, rot, Rx, Ry, Rz, I3
from modelkit import shade as kshade

W = 48; H = 18; HALF = W / 2


def c3(c):
    return [round(c[0] / 255, 4), round(c[1] / 255, 4), round(c[2] / 255, 4)]


def r4(v):
    return round(float(v), 4)


def emit(m, collide=False, offset=(0, 0, 0), yaw=0.0, children=None, props=None, names=None):
    """Convert a modelkit Model to a list of Rojo part nodes, moved by offset and turned by yaw (degrees)."""
    Rw = Ry(yaw)
    out = []
    children = children or {}
    props = props or {}
    for i, p in enumerate(m.parts, start=1):
        R = Rw @ p["R"]
        pos = Rw @ np.array(p["pos"]) + np.array(offset, float)
        cls = "WedgePart" if p["shape"] == "W" else "Part"
        pr = {
            "Anchored": True,
            "Size": [r4(v) for v in p["size"]],
            "CFrame": {"CFrame": {"position": [r4(v) for v in pos], "orientation": [[r4(v) for v in row] for row in R]}},
            "Color": c3(p["color"]),
            "Material": p["mat"],
            "TopSurface": "Smooth",
            "BottomSurface": "Smooth",
            "CanCollide": collide,
        }
        if p["shape"] == "S":
            pr["Shape"] = "Ball"
        elif p["shape"] == "C":
            pr["Shape"] = "Cylinder"
        if p["tr"]:
            pr["Transparency"] = p["tr"]
        if p["refl"]:
            pr["Reflectance"] = p["refl"]
        if not collide:
            pr["CanTouch"] = False
        pr.update(props.get(i, {}))
        kids = []
        if p["shape"] == "E":
            kids.append({"Name": "Mesh", "ClassName": "SpecialMesh", "Properties": {"MeshType": "Sphere"}})
        kids.extend(children.get(i, []))
        node = {"Name": p["name"], "ClassName": cls, "Properties": pr}
        if kids:
            node["Children"] = kids
        out.append(node)
    return out


def light(cls, color, brightness, rng, shadows=False, extra=None):
    p = {"Color": c3(color), "Brightness": brightness, "Range": rng, "Shadows": shadows}
    if extra:
        p.update(extra)
    return {"Name": cls, "ClassName": cls, "Properties": p}


def fire(size, heat, color, color2):
    return {"Name": "Fire", "ClassName": "Fire", "Properties": {"Size": size, "Heat": heat, "Color": c3(color), "SecondaryColor": c3(color2)}}


def sparkles(color):
    return {"Name": "Sparkles", "ClassName": "Sparkles", "Properties": {"SparkleColor": c3(color)}}


def sign(text, size=(10, 2.2), color=(255, 255, 255)):
    return {"Name": "Sign", "ClassName": "BillboardGui",
            "Properties": {"Size": {"UDim2": [[size[0], 0], [size[1], 0]]}, "AlwaysOnTop": False, "MaxDistance": 120, "LightInfluence": 0},
            "Children": [{"Name": "Label", "ClassName": "TextLabel", "Properties": {
                "Text": text, "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundTransparency": 1, "TextScaled": True,
                "Font": "FredokaOne", "TextColor3": c3(color), "TextStrokeTransparency": 0.2}}]}


def surface_text(face, lines, color=(255, 240, 200), font="FredokaOne", ppsd=40, bg=None, name="Gui"):
    kids = []
    n = len(lines)
    for k, (text, weight) in enumerate(lines):
        kids.append({"Name": "Line%d" % (k + 1), "ClassName": "TextLabel", "Properties": {
            "Text": text, "Size": {"UDim2": [[0.92, 0], [weight, 0]]},
            "Position": {"UDim2": [[0.04, 0], [sum(w for _, w in lines[:k]), 0]]},
            "BackgroundTransparency": 1, "TextScaled": True, "Font": font, "TextColor3": c3(color), "TextStrokeTransparency": 0.6}})
    props = {"Face": face, "SizingMode": "PixelsPerStud", "PixelsPerStud": ppsd, "LightInfluence": 0.4}
    return {"Name": name, "ClassName": "SurfaceGui", "Properties": props, "Children": kids}


def folder(name, children):
    return {"Name": name, "ClassName": "Folder", "Children": children}


def model(name, children):
    return {"Name": name, "ClassName": "Model", "Children": children}


def label_part(name, pos, text, size=(10, 2.2), color=(255, 255, 255)):
    m = Model(name)
    m.blk(name, (1, 1, 1), pos, (0, 0, 0), tr=1)
    return emit(m, children={1: [sign(text, size, color)]}, props={1: {"CanQuery": False, "CastShadow": False}})


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
WALNUT = (92, 58, 36)
WALNUT_DARK = (70, 43, 27)
OAK = (150, 105, 65)
BRASS = (215, 175, 80)
PLASTER = (226, 200, 165)
WAINSCOT = (112, 74, 46)
FELT = (34, 92, 60)
CREAM = (245, 235, 215)

# ---------------------------------------------------------------------------
# Room structure
# ---------------------------------------------------------------------------
structure = []
s = Model("Structure")
s.blk("Floor", (W, 1, W), (0, -0.5, 0), (130, 88, 58), mat="WoodPlanks")
s.blk("Ceiling", (W, 1, W), (0, H + 0.5, 0), (238, 228, 210), mat="Plaster")
s.blk("WallNorth", (W, H, 1), (0, H / 2, -HALF - 0.5), PLASTER, mat="Plaster")
s.blk("WallSouth", (W, H, 1), (0, H / 2, HALF + 0.5), PLASTER, mat="Plaster")
s.blk("WallWest", (1, H, W), (-HALF - 0.5, H / 2, 0), PLASTER, mat="Plaster")
s.blk("WallEast", (1, H, W), (HALF + 0.5, H / 2, 0), PLASTER, mat="Plaster")
structure += emit(s, collide=True)

d = Model("Decor")
# rug under the duel table
d.blk("RugBorder", (33, 0.08, 36), (0, 0.04, 0), (140, 35, 45), mat="Fabric")
d.blk("RugGold", (31.4, 0.09, 34.4), (0, 0.045, 0), (205, 160, 80), mat="Fabric")
d.blk("Rug", (30.6, 0.1, 33.6), (0, 0.05, 0), (40, 45, 85), mat="Carpet")
d.blk("RugPattern", (3.2, 0.11, 3.2), (0, 0.055, 0), (150, 40, 55), mat="Fabric", R=rot(y=45))
for (x, z) in [(-14, -15.5), (14, -15.5), (-14, 15.5), (14, 15.5)]:
    d.blk("RugCorner", (1.6, 0.11, 1.6), (x, 0.055, z), (205, 160, 80), mat="Fabric", R=rot(y=45))
# ceiling beams
for z in (-12, 0, 12):
    d.blk("Beam", (W, 1.0, 1.2), (0, H - 0.5, z), (100, 66, 40), mat="Wood")
for x in (-12, 12):
    d.blk("Beam", (1.0, 0.8, W), (x, H - 0.4, 0), (95, 62, 38), mat="Wood")


def wall_trim(m, axis, fixed, start, end, inward):
    """Wainscot, chair rail, baseboard and crown molding along one wall segment."""
    length = end - start
    mid = (start + end) / 2
    if axis == "x":
        def P(y, depth):
            return (mid, y, fixed + inward * depth / 2)
        def S(h, depth):
            return (length, h, depth)
    else:
        def P(y, depth):
            return (fixed + inward * depth / 2, y, mid)
        def S(h, depth):
            return (depth, h, length)
    m.blk("Wainscot", S(5.0, 0.3), P(2.5, 0.3), WAINSCOT, mat="WoodPlanks")
    m.blk("ChairRail", S(0.4, 0.5), P(5.1, 0.5), (90, 58, 36), mat="Wood")
    m.blk("Baseboard", S(0.8, 0.45), P(0.4, 0.45), (80, 52, 32), mat="Wood")
    m.blk("Crown", S(0.6, 0.6), P(H - 0.3, 0.6), (240, 230, 212), mat="Plaster")


wall_trim(d, "x", -HALF, -HALF, HALF, 1)          # north
wall_trim(d, "x", HALF, -HALF, -17.4, -1)          # south, left of the door
wall_trim(d, "x", HALF, -10.6, HALF, -1)           # south, right of the door
wall_trim(d, "z", -HALF, -HALF, HALF, 1)           # west
wall_trim(d, "z", HALF, -HALF, HALF, -1)           # east

# door (south wall, x = -14)
d.blk("DoorFrameL", (0.6, 11.6, 0.8), (-17.2, 5.8, HALF - 0.3), (90, 58, 36), mat="Wood")
d.blk("DoorFrameR", (0.6, 11.6, 0.8), (-10.8, 5.8, HALF - 0.3), (90, 58, 36), mat="Wood")
d.blk("DoorFrameTop", (7.0, 0.7, 0.8), (-14, 11.6, HALF - 0.3), (90, 58, 36), mat="Wood")
d.blk("Door", (5.8, 11.2, 0.4), (-14, 5.6, HALF - 0.25), (125, 80, 48), mat="Wood")
for (x, y) in [(-15.3, 8.2), (-12.7, 8.2), (-15.3, 3.2), (-12.7, 3.2)]:
    d.blk("DoorPanel", (2.0, 3.8, 0.12), (x, y, HALF - 0.48), (110, 70, 42), mat="Wood")
d.ball("DoorKnob", 0.55, (-11.8, 5.4, HALF - 0.6), BRASS, mat="Metal", refl=0.2)
d.cyl("DoorKnobPlate", 0.08, 0.7, (-11.8, 5.4, HALF - 0.47), BRASS, axis="z", mat="Metal")
d.blk("DoorMat", (6, 0.12, 3), (-14, 0.06, HALF - 2.2), (120, 90, 60), mat="Fabric")


def window(m, center_x, center_z, facing, glow_moon=False):
    """Night window on a wall. facing = direction into the room as (dx, dz)."""
    yaw = {(0, 1): 0, (1, 0): 90, (-1, 0): -90, (0, -1): 180}[facing]
    w = Model("Window")
    w.blk("NightSky", (5.0, 6.0, 0.05), (0, 9, 0.05), (18, 26, 62))
    for (x, y, dd) in [(-1.6, 11.2, 0.12), (1.1, 10.4, 0.1), (-0.4, 8.0, 0.08), (1.8, 7.0, 0.1), (-1.9, 6.6, 0.09), (0.5, 11.6, 0.08), (-0.9, 9.6, 0.1)]:
        w.ball("Star", dd, (x, y, 0.1), (255, 250, 220), mat="Neon")
    if glow_moon:
        w.ball("Moon", 1.1, (1.2, 11.0, 0.12), (250, 240, 200), mat="Neon")
        w.ball("MoonShade", 1.0, (1.5, 11.15, 0.18), (18, 26, 62))
    w.blk("Glass", (5.0, 6.0, 0.08), (0, 9, 0.2), (150, 180, 230), mat="Glass", tr=0.75, refl=0.15)
    for (sx, sy, x, y) in [(5.6, 0.4, 0, 12.2), (5.6, 0.4, 0, 5.8), (0.4, 6.8, -2.7, 9), (0.4, 6.8, 2.7, 9), (0.2, 6.0, 0, 9), (5.0, 0.2, 0, 9)]:
        w.blk("Frame", (sx, sy, 0.35), (x, y, 0.25), (235, 228, 215), mat="Wood")
    w.blk("Sill", (6.4, 0.3, 0.9), (0, 5.55, 0.45), (235, 228, 215), mat="Wood")
    w.cyl("CurtainRod", 8.6, 0.18, (0, 13.3, 0.6), BRASS, axis="x", mat="Metal")
    for sx in (-1, 1):
        w.ball("RodEnd", 0.4, (sx * 4.35, 13.3, 0.6), BRASS, mat="Metal")
        w.blk("Curtain", (1.6, 8.6, 0.3), (sx * 3.45, 8.9, 0.75), (150, 32, 48), mat="Fabric")
        for k in range(3):
            w.blk("CurtainFold", (0.25, 8.6, 0.38), (sx * 3.45 - 0.55 + k * 0.55, 8.9, 0.8), (130, 26, 40), mat="Fabric")
        w.cyl("Tieback", 0.3, 0.12, (sx * 3.45, 7.3, 0.95), BRASS, axis="x", mat="Metal")
    w.blk("Valance", (7.2, 1.0, 0.5), (0, 13.0, 0.9), (130, 26, 40), mat="Fabric")
    Rw = Ry(yaw)
    for p in w.parts:
        p["pos"] = tuple(Rw @ np.array(p["pos"]) + np.array([center_x, 0, center_z]))
        p["R"] = Rw @ p["R"]
        m.parts.append(p)


window(d, -8.5, -HALF, (0, 1))
window(d, 8.5, -HALF, (0, 1), glow_moon=True)
window(d, -HALF, 14, (1, 0))

# fireplace on the north wall (behind the bot)
fz = -HALF
d.blk("Hearth", (10.5, 0.4, 2.8), (0, 0.2, fz + 1.4), (95, 90, 92), mat="Slate")
for sx in (-1, 1):
    d.blk("FirePillar", (2.0, 7.0, 1.6), (sx * 3.7, 3.5, fz + 0.8), (165, 72, 55), mat="Brick")
d.blk("FireLintel", (9.4, 1.6, 1.6), (0, 6.2, fz + 0.8), (165, 72, 55), mat="Brick")
d.blk("FireBack", (5.4, 5.4, 0.4), (0, 2.7, fz + 0.2), (40, 28, 26), mat="Slate")
d.blk("FireFloor", (5.4, 0.2, 1.4), (0, 0.5, fz + 0.9), (30, 22, 20), mat="Slate")
d.blk("Grate", (3.6, 0.15, 0.15), (0, 0.75, fz + 1.4), (40, 40, 45), mat="Metal")
for k in range(5):
    d.blk("GrateBar", (0.12, 0.6, 0.12), (-1.6 + k * 0.8, 0.95, fz + 1.4), (40, 40, 45), mat="Metal")
d.cyl("Log", 3.4, 0.65, (0, 0.95, fz + 0.9), (105, 68, 42), axis="x", mat="Wood")
d.cyl("Log", 3.0, 0.6, (0.1, 1.45, fz + 0.75), (95, 62, 38), axis="x", mat="Wood", R=rot(y=12))
d.cyl("Log", 2.6, 0.55, (-0.2, 1.4, fz + 1.05), (110, 72, 45), axis="x", mat="Wood", R=rot(y=-15, z=8))
embers = d.ell("Embers", (3.6, 0.4, 1.0), (0, 0.65, fz + 0.9), (255, 110, 30), mat="Neon")
firepart = d.blk("FireLight", (2.5, 0.5, 0.8), (0, 1.6, fz + 0.9), (0, 0, 0), tr=1)
d.blk("Mantle", (10.4, 0.55, 2.1), (0, 7.3, fz + 1.05), (100, 64, 40), mat="Wood")
d.blk("MantleTrim", (10.0, 0.3, 1.8), (0, 6.95, fz + 0.95), (80, 50, 32), mat="Wood")
d.blk("Chimney", (8.2, 10.4, 1.2), (0, 12.8, fz + 0.6), (160, 70, 54), mat="Brick")
# mantle decorations
for sx in (-1, 1):
    d.cyl("CandleHolder", 0.15, 0.7, (sx * 4.2, 7.65, fz + 1.2), BRASS, mat="Metal")
    d.cyl("Candle", 1.0, 0.32, (sx * 4.2, 8.2, fz + 1.2), CREAM)
    d.ell("Flame", (0.18, 0.35, 0.18), (sx * 4.2, 8.85, fz + 1.2), (255, 200, 90), mat="Neon")
d.blk("Clock", (1.4, 1.6, 0.8), (-2.2, 8.4, fz + 1.2), (120, 78, 48), mat="Wood")
d.cyl("ClockFace", 0.1, 1.0, (-2.2, 8.5, fz + 0.75), CREAM, axis="z")
d.blk("ClockHand", (0.06, 0.4, 0.04), (-2.2, 8.62, fz + 0.69), (30, 30, 30))
d.blk("ClockHand", (0.3, 0.06, 0.04), (-2.07, 8.5, fz + 0.69), (30, 30, 30))
d.cyl("TrophySmall", 0.7, 0.5, (2.3, 8.0, fz + 1.2), BRASS, mat="Metal")
d.blk("TrophySmallBase", (0.6, 0.3, 0.6), (2.3, 7.7, fz + 1.2), (60, 40, 30))
d.ell("TrophySmallCup", (0.8, 0.6, 0.8), (2.3, 8.5, fz + 1.2), BRASS, mat="Metal")
# painting above the mantle: a little landscape
pz = fz + 1.25
d.blk("PaintingFrame", (5.4, 3.8, 0.3), (0, 11.2, pz), (200, 160, 70), mat="Metal")
d.blk("PaintingSky", (4.8, 3.2, 0.1), (0, 11.2, pz + 0.12), (120, 170, 220))
d.ell("PaintingHill", (3.6, 1.6, 0.1), (-1.0, 10.0, pz + 0.17), (90, 160, 80))
d.ell("PaintingHill", (3.4, 1.3, 0.1), (1.3, 9.9, pz + 0.19), (70, 140, 70))
d.ball("PaintingSun", 0.7, (1.5, 12.0, pz + 0.18), (255, 220, 90))
d.blk("PaintingCastle", (0.6, 0.7, 0.05), (-1.1, 10.7, pz + 0.24), (230, 230, 240))
d.blk("PaintingTower", (0.25, 0.5, 0.05), (-1.3, 11.15, pz + 0.24), (230, 230, 240))

# pendant lamps in the room corners
for (x, z) in [(-12, -12), (12, 12), (-12, 12), (12, -12)]:
    d.cyl("LampCord", 3.2, 0.08, (x, H - 1.6, z), (40, 40, 40))
    d.cyl("LampShade", 1.1, 2.4, (x, H - 3.6, z), (235, 205, 150), mat="Fabric")
    d.cyl("LampShadeTop", 0.4, 1.6, (x, H - 2.9, z), (235, 205, 150), mat="Fabric")
d_lamp_bulbs = []
for (x, z) in [(-12, -12), (12, 12), (-12, 12), (12, -12)]:
    d_lamp_bulbs.append(d.ball("LampBulb", 0.7, (x, H - 4.15, z), (255, 225, 170), mat="Neon"))

# potted plants
def plant(m, x, z, scale=1.0):
    k = scale
    m.cyl("Pot", 1.6 * k, 1.8 * k, (x, 0.8 * k, z), (190, 100, 60))
    m.cyl("PotRim", 0.3 * k, 2.0 * k, (x, 1.6 * k, z), (170, 88, 52))
    m.cyl("Soil", 0.1 * k, 1.7 * k, (x, 1.7 * k, z), (80, 55, 35))
    leaves = [(0, 3.2, 0, 0, 0), (0.6, 2.8, 0.3, 30, -25), (-0.6, 2.9, -0.2, -20, 30), (0.2, 2.6, -0.7, -40, 0), (-0.3, 2.5, 0.7, 40, 0), (0.0, 3.9, 0.1, 5, 10)]
    for (dx, y, dz, ax, az) in leaves:
        m.ell("Leaf", (0.9 * k, 2.2 * k, 0.5 * k), (x + dx * k, y * k, z + dz * k), (60, 140, 70), R=rot(x=ax, z=az))
    m.ell("LeafTop", (1.4 * k, 1.0 * k, 1.4 * k), (x, 3.5 * k, z), (70, 155, 80))


plant(d, -21.5, 21.5, 1.1)
plant(d, 21.8, 22.0, 1.0)
plant(d, -21.6, -21.4, 1.0)
plant(d, 5.8, -22.2, 0.8)
plant(d, -5.8, -22.2, 0.8)

# posters
d.blk("PosterFrame", (5.6, 7.2, 0.25), (-4, 9.5, HALF - 0.15), (60, 40, 30), mat="Wood")
poster = d.blk("Poster", (5.0, 6.6, 0.1), (-4, 9.5, HALF - 0.3), (40, 30, 70))
d.blk("PosterFrame", (5.0, 4.0, 0.25), (-HALF + 0.15, 9.5, -12), (60, 40, 30), mat="Wood", R=rot(y=-90))
poster2 = d.blk("Poster2", (4.4, 3.4, 0.1), (-HALF + 0.3, 9.5, -12), (240, 220, 160), R=rot(y=-90))

structure += emit(d, children={
    firepart: [fire(7, 9, (255, 110, 30), (255, 200, 70)), light("PointLight", (255, 150, 70), 1.7, 20, shadows=True)],
    embers: [light("PointLight", (255, 120, 50), 0.6, 7)],
    poster: [surface_text("Front", [("DECK WARS", 0.32), ("Lane Brawl Champions", 0.14), ("Every Friday", 0.12), ("bring your best deck!", 0.12)], color=(255, 220, 90))],
    poster2: [surface_text("Front", [("WANTED", 0.35), ("Granny Bolt", 0.25), ("for bowling too fast", 0.18)], color=(90, 50, 30))],
    **{b: [light("PointLight", (255, 205, 150), 0.6, 22)] for b in d_lamp_bulbs},
}, props={firepart: {"CanQuery": False, "CastShadow": False}, embers: {"CastShadow": False}})

structure.append({"Name": "SpawnLocation", "ClassName": "SpawnLocation", "Properties": {
    "Anchored": True, "Size": [6, 1, 6], "CFrame": {"CFrame": {"position": [-14, 0.1, 18], "orientation": I3.tolist()}},
    "Transparency": 1, "CanCollide": False, "Neutral": True, "Duration": 0}})

# ---------------------------------------------------------------------------
# Duel table (center): 4 lanes x 6 rows of tiles, and a row of building slots behind each side
# ---------------------------------------------------------------------------
# Tiles are numbered from the near chair: Tile_<column>_<row>, column 1 on the left,
# row 1 nearest the near chair. Row 0 is the near building row, row 7 the far one.
# The client turns the board around for whoever sits far.
# The tiles sit edge to edge with only a hairline seam, so a lane of the same terrain reads as
# one continuous strip of ground (the seam is the subtle tile outline).
COLS, ROWS = 4, 6
PITCH_X = 2.6        # distance between lane centers
PITCH = 2.4          # distance between row centers
SEAM = 0.07          # the hairline between tiles
TILE_W, TILE_D = PITCH_X - SEAM, PITCH - SEAM
SLOT_GAP = 0.42      # gap between a Backline and its building row
SLOT_D = 1.95        # depth of a building slot
TOP = 4.0            # table top surface
FELT_TOP = 4.1
TW, TD = 25.0, 22.0  # table top size (x, z)
HX, HZ = -8.75, 3.9  # hero pedestals (x, distance from the middle line)
CHAIR_Z = 13.7
BW, BD = COLS * PITCH_X, ROWS * PITCH  # 10.4 x 14.4 (tiles only)
SLOT_Z = BD / 2 + SLOT_GAP + SLOT_D / 2   # distance of the building rows from the middle line
BD_ALL = 2 * (SLOT_Z + SLOT_D / 2)        # depth with the building rows
TILE_Y = FELT_TOP + 0.22  # tile center height (tile top at FELT_TOP + 0.32)


def tile_xz(wc, wr):
    x = (wc - (COLS + 1) / 2) * PITCH_X
    if wr == 0:
        return (x, SLOT_Z)
    if wr == ROWS + 1:
        return (x, -SLOT_Z)
    return (x, ((ROWS + 1) / 2 - wr) * PITCH)


t = Model("DuelTable")
t.blk("TableTop", (TW, 1.2, TD), (0, TOP - 0.6, 0), WALNUT, mat="Wood", refl=0.05)
t.blk("Apron", (TW - 1.4, 1.0, TD - 1.4), (0, TOP - 1.7, 0), WALNUT_DARK, mat="Wood")
lx, lz = TW / 2 - 1.4, TD / 2 - 1.3
for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1), (-1, 0), (1, 0)]:
    x, z = sx * lx, sz * lz
    t.cyl("Leg", 1.6, 1.3, (x, 2.0, z), WALNUT_DARK, mat="Wood")
    t.ball("LegKnob", 1.6, (x, 1.1, z), WALNUT, mat="Wood")
    t.cyl("Leg", 0.9, 0.9, (x, 0.45, z), WALNUT_DARK, mat="Wood")
    t.cyl("LegFoot", 0.15, 1.3, (x, 0.08, z), BRASS, mat="Metal")
t.blk("Stretcher", (TW - 4, 0.5, 0.6), (0, 0.9, 0), WALNUT_DARK, mat="Wood")
for sx in (-1, 1):
    t.blk("Stretcher", (0.6, 0.5, TD - 4), (sx * lx, 0.9, 0), WALNUT_DARK, mat="Wood")
# raised rim around the playmat
rx, rz = TW / 2 - 0.45, TD / 2 - 0.45
for (sx, sy, sz, x, z) in [(TW + 0.4, 0.5, 0.9, 0, rz), (TW + 0.4, 0.5, 0.9, 0, -rz), (0.9, 0.5, TD + 0.4, rx, 0), (0.9, 0.5, TD + 0.4, -rx, 0)]:
    t.blk("Rim", (sx, sy, sz), (x, TOP + 0.2, z), WALNUT_DARK, mat="Wood", refl=0.05)
for (x, z) in [(-rx, -rz), (rx, -rz), (-rx, rz), (rx, rz)]:
    t.blk("RimCorner", (1.05, 0.6, 1.05), (x, TOP + 0.25, z), BRASS, mat="Metal", refl=0.15)
t.blk("Felt", (TW - 1.6, 0.1, TD - 1.6), (0, TOP + 0.05, 0), FELT, mat="Fabric")
ix, iz = TW / 2 - 1.25, TD / 2 - 1.25
for (sx, sz, x, z) in [(2 * ix, 0.12, 0, iz), (2 * ix, 0.12, 0, -iz), (0.12, 2 * iz, ix, 0), (0.12, 2 * iz, -ix, 0)]:
    t.blk("Inlay", (sx, 0.02, sz), (x, FELT_TOP + 0.01, z), BRASS, mat="Metal")

# the board: a dark bed for the grooves, a wooden frame, and a brass line across the middle
t.blk("BoardBed", (BW + 0.3, 0.12, BD_ALL + 0.3), (0, FELT_TOP + 0.06, 0), (34, 28, 26), mat="Wood")
fz, fx = BD_ALL / 2 + 0.38, BW / 2 + 0.38
for (sx, sz, x, z) in [(BW + 1.5, 0.46, 0, fz), (BW + 1.5, 0.46, 0, -fz), (0.46, BD_ALL + 0.3, fx, 0), (0.46, BD_ALL + 0.3, -fx, 0)]:
    t.blk("BoardFrame", (sx, 0.4, sz), (x, FELT_TOP + 0.2, z), OAK, mat="Wood", refl=0.04)
for (x, z) in [(-fx, -fz), (fx, -fz), (-fx, fz), (fx, fz)]:
    t.cyl("FrameCap", 0.16, 0.62, (x, FELT_TOP + 0.44, z), BRASS, mat="Metal", refl=0.15)
t.blk("HalfwayLine", (BW + 0.2, 0.04, 0.12), (0, FELT_TOP + 0.14, 0), BRASS, mat="Metal", refl=0.2)
for sx in (-1, 1):
    t.blk("HalfwayMark", (0.5, 0.06, 0.5), (sx * fx, FELT_TOP + 0.42, 0), BRASS, mat="Metal", R=rot(y=45), refl=0.2)
# a thin brass rail between each side's tiles and its building row, and small lane studs on the frame
for sz in (-1, 1):
    t.blk("BuildRail", (BW + 0.2, 0.05, 0.08), (0, FELT_TOP + 0.15, sz * (BD / 2 + SLOT_GAP / 2)), BRASS, mat="Metal", refl=0.2)
for wc in range(1, COLS + 1):
    x = (wc - (COLS + 1) / 2) * PITCH_X
    for sz in (-1, 1):
        t.cyl("LaneStud", 0.06, 0.22, (x, FELT_TOP + 0.43, sz * fz), BRASS, mat="Metal", refl=0.2)

# chairs
def chair(m, z, facing):
    """facing: -1 = seat faces -Z (near chair), +1 = faces +Z (far chair)."""
    back = z - facing * 2.0
    m.blk("ChairBase", (4.4, 0.45, 4.4), (0, 0.78, z), WALNUT, mat="Wood")
    for (sx, sz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
        m.cyl("ChairLeg", 0.6, 0.45, (sx * 1.9, 0.3, z + sz * 1.9), WALNUT_DARK, mat="Wood")
    for sx in (-1, 1):
        m.blk("ChairPost", (0.5, 5.4, 0.5), (sx * 1.95, 3.5, back), WALNUT, mat="Wood")
        m.ball("ChairFinial", 0.6, (sx * 1.95, 6.35, back), WALNUT_DARK, mat="Wood")
        m.blk("Armrest", (0.45, 0.35, 3.7), (sx * 2.2, 3.0, z - facing * 0.15), WALNUT, mat="Wood")
        m.blk("ArmPost", (0.35, 1.2, 0.35), (sx * 2.2, 2.4, z + facing * 1.4), WALNUT_DARK, mat="Wood")
    m.blk("ChairTopRail", (4.4, 0.7, 0.55), (0, 6.0, back), WALNUT, mat="Wood")
    for k in (-1, 0, 1):
        m.blk("ChairSlat", (0.55, 3.4, 0.25), (k * 1.1, 4.05, back), WALNUT_DARK, mat="Wood")
    m.blk("BackCushion", (3.2, 2.6, 0.35), (0, 4.0, back + facing * 0.35), (150, 35, 48), mat="Fabric")


chair(t, CHAIR_Z, -1)
chair(t, -CHAIR_Z, 1)

# two lamps hang over the table, one over each half
lamp_bulbs = []
for lz2 in (-4.6, 4.6):
    # hung high, so they stay above the player's view of the board
    t.cyl("TableLampCord", 1.6, 0.08, (0, H - 0.8, lz2), (40, 40, 40))
    t.cyl("TableLampShade", 0.9, 4.0, (0, H - 2.15, lz2), (40, 90, 60), refl=0.1)
    t.cyl("TableLampTop", 0.6, 2.4, (0, H - 1.5, lz2), (40, 90, 60), refl=0.1)
    t.cyl("TableLampRim", 0.15, 4.1, (0, H - 2.6, lz2), BRASS, mat="Metal")
    lamp_bulbs.append(t.ball("TableLamp", 0.9, (0, H - 2.65, lz2), (255, 235, 190), mat="Neon"))

table_children = {}
for k, bulb in enumerate(lamp_bulbs):
    # a warm pool of light on the board with the room falling into shadow around it
    # (crisp shadows under the pieces make them feel heavy)
    table_children[bulb] = [light("SpotLight", (255, 214, 168), 1.3, 22, shadows=True, extra={"Angle": 76, "Face": "Bottom"}),
                            light("PointLight", (255, 205, 150), 0.07, 9)]
table_nodes = emit(t, children=table_children, props={bulb: {"CastShadow": False} for bulb in lamp_bulbs})


def seat(name, z, yaw, color):
    m = Model(name)
    m.blk(name, (4, 1, 4), (0, 1.5, 0), color, mat="Fabric")
    node = emit(m, collide=True, offset=(0, 0, z), yaw=yaw)[0]
    node["ClassName"] = "Seat"
    return node


table_nodes.append(seat("Seat_Near", CHAIR_Z, 0, (150, 35, 48)))
table_nodes.append(seat("Seat_Far", -CHAIR_Z, 180, (150, 35, 48)))

# Board folder: tiles, hero pedestals, energy crystals, card piles (the scripts look these up by name)
b = Model("Board")
named = {}
plinths = []
for wr in range(1, ROWS + 1):
    for wc in range(1, COLS + 1):
        x, z = tile_xz(wc, wr)
        # one even surface: the client paints each tile with its lane's terrain
        named[f"Tile_{wc}_{wr}"] = b.blk(f"Tile_{wc}_{wr}", (TILE_W, 0.2, TILE_D), (x, TILE_Y, z), (128, 120, 108), mat="Slate")
for wr in (0, ROWS + 1):
    for wc in range(1, COLS + 1):
        x, z = tile_xz(wc, wr)
        # a building slot: a low dark stone pad with a brass edge, a little lower than the tiles
        plinths.append(b.blk("SlotTrim", (TILE_W - 0.1, 0.14, SLOT_D), (x, FELT_TOP + 0.13, z), (150, 118, 60), mat="Metal"))
        named[f"Tile_{wc}_{wr}"] = b.blk(f"Tile_{wc}_{wr}", (TILE_W - 0.3, 0.16, SLOT_D - 0.2), (x, FELT_TOP + 0.17, z), (58, 52, 50), mat="Slate")
for side, sz in (("Near", 1), ("Far", -1)):
    # hero pedestal on the left of each half
    hz = sz * HZ
    b.cyl("PedestalBase", 0.3, 2.9, (HX, FELT_TOP + 0.15, hz), (60, 55, 60), mat="Marble")
    b.cyl("PedestalColumn", 0.4, 2.3, (HX, FELT_TOP + 0.5, hz), (230, 225, 215), mat="Marble")
    named[f"HeroGlow_{side}"] = b.cyl(f"HeroGlow_{side}", 0.12, 2.75, (HX, FELT_TOP + 0.72, hz), (255, 210, 90), mat="Neon", tr=0.35)
    named[f"Hero_{side}"] = b.cyl(f"Hero_{side}", 0.16, 2.5, (HX, FELT_TOP + 0.78, hz), (240, 235, 225), mat="Marble")
    # energy crystals: two rows of four on the right
    for k in range(8):
        col, row = k // 4, k % 4
        ex = 8.3 + col * 0.95
        ez = sz * (2.3 + row * 0.9)
        b.cyl("CrystalSocket", 0.18, 0.75, (ex, FELT_TOP + 0.09, ez), BRASS, mat="Metal")
        named[f"Energy_{side}_{k + 1}"] = b.blk(f"Energy_{side}_{k + 1}", (0.42, 0.8, 0.42), (ex, FELT_TOP + 0.58, ez), (70, 90, 120), mat="Glass", R=rot(y=45), tr=0.1)
    # deck (right corner) and discard pile (left corner)
    b.blk("DeckTray", (2.0, 0.12, 2.6), (9.65, FELT_TOP + 0.06, sz * 8.55), WALNUT_DARK, mat="Wood")
    named[f"Deck_{side}"] = b.blk(f"Deck_{side}", (1.6, 0.6, 2.2), (9.65, FELT_TOP + 0.42, sz * 8.55), (40, 50, 120), mat="SmoothPlastic")
    b.blk("DiscardTray", (2.0, 0.12, 2.6), (-9.65, FELT_TOP + 0.06, sz * 8.55), WALNUT_DARK, mat="Wood")
    named[f"Discard_{side}"] = b.blk(f"Discard_{side}", (1.6, 0.05, 2.2), (-9.65, FELT_TOP + 0.145, sz * 8.55), (235, 225, 200), mat="SmoothPlastic")

board_props = {}
for name, idx in named.items():
    board_props[idx] = {"CanQuery": True}
for idx in plinths:
    # clicks go through the plinths to the tiles
    board_props[idx] = {"CanQuery": False}
board_nodes = emit(b, props=board_props)
table_nodes.append(folder("Board", board_nodes))
table_nodes += label_part("TableLabel", (0, 10.5, 0), "DUEL TABLE")

# ---------------------------------------------------------------------------
# Deck shelf (west wall)
# ---------------------------------------------------------------------------
sh = Model("DeckShelf")
sx0 = -HALF
sh.blk("ShelfBack", (0.4, 12, 14), (sx0 + 0.25, 6, 0), (95, 62, 38), mat="Wood")
for z in (-7.1, 7.1):
    sh.blk("ShelfSide", (2.8, 12.4, 0.45), (sx0 + 1.6, 6.2, z), (120, 78, 48), mat="Wood")
sh.blk("ShelfTop", (3.2, 0.5, 15.2), (sx0 + 1.65, 12.45, 0), (120, 78, 48), mat="Wood")
sh.blk("ShelfCrown", (3.5, 0.4, 15.6), (sx0 + 1.7, 12.85, 0), (95, 62, 38), mat="Wood")
book_colors = [(220, 80, 80), (80, 150, 230), (250, 200, 60), (120, 200, 110), (170, 110, 220), (240, 140, 60), (60, 190, 190)]
for row, y in enumerate((0.35, 3.35, 6.35, 9.35)):
    sh.blk("ShelfPlank", (2.7, 0.3, 13.8), (sx0 + 1.6, y, 0), (135, 90, 56), mat="Wood")
    if row == 0:
        continue
    for k in range(8):
        c = book_colors[(row * 3 + k) % len(book_colors)]
        z = -5.9 + k * 1.6 + (0.15 if k % 3 == 0 else 0)
        tilt = 8 if k == 7 else 0
        sh.blk("Binder", (1.9, 2.3, 1.15), (sx0 + 1.65, y + 1.3, z), c, R=rot(x=tilt))
        sh.blk("BinderLabel", (0.04, 0.9, 0.7), (sx0 + 2.62, y + 1.45, z), (250, 245, 230))
        sh.blk("BinderRing", (0.05, 0.12, 0.9), (sx0 + 2.62, y + 0.5, z), (200, 200, 210), mat="Metal")
# card boxes on the bottom shelf
for k in range(5):
    c = book_colors[k % len(book_colors)]
    sh.blk("CardBox", (1.8, 1.2, 1.8), (sx0 + 1.6, 1.1 + (k % 2) * 1.2, -5 + k * 2.2 - (k % 2) * 1.1), c, mat="Cardboard")
# reading lamp on top
sh.cyl("ShelfLampBase", 0.2, 1.0, (sx0 + 1.6, 12.9, 4.5), BRASS, mat="Metal")
sh.cyl("ShelfLampPole", 1.6, 0.12, (sx0 + 1.6, 13.7, 4.5), BRASS, mat="Metal")
shelf_lamp = sh.cyl("ShelfLampShade", 0.9, 1.3, (sx0 + 1.6, 14.6, 4.5), (60, 110, 80))
shelf_nodes = emit(sh, children={shelf_lamp: [light("PointLight", (255, 214, 150), 0.5, 9)]})
shelf_nodes += label_part("ShelfLabel", (-20, 14.6, 0), "DECK SHELF")

# ---------------------------------------------------------------------------
# The Pack Shelf (in the Pack Party corner): a lit display stand with one pack per family and
# the classic Brawl Pack on top. Pack names and colors come from src/packbrawl/Packs.luau.
# Built in its own frame (x across, y up, +z toward the room) and turned to face the room.
# ---------------------------------------------------------------------------
import re


def read_packs():
    src = open("src/packbrawl/Packs.luau").read()
    body = src[src.index("Packs.List = {"):]
    body = body[:body.index("\n}\n")]
    packs = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("{ id ="):
            continue
        d = {k: v for k, v in re.findall(r'(\w+) = "([^"]*)"', line)}
        for key in ("color", "dark", "accent"):
            nums = re.search(key + r" = \{ (\d+), (\d+), (\d+) \}", line)
            d[key] = tuple(int(v) for v in nums.groups())
        packs.append(d)
    return packs


PACKS = read_packs()
SHELF_AT = (18.0, 0.0, -18.0)
SHELF_YAW = -45  # local +z (the shelf's front) faces the middle of the room
LACQUER = (30, 22, 48)
LACQUER_LIGHT = (44, 34, 70)
GOLD = (255, 206, 72)
BULB = (255, 238, 196)
# Where each pack stands: (x, floor y, z, scale) in the shelf's frame.
SHELF_SLOTS = {
    "brawl": (0.0, 7.625, -0.45, 1.15),
    "snack": (-3.2, 4.225, 0.15, 1.0), "junk": (0.0, 4.225, 0.15, 1.0), "weather": (3.2, 4.225, 0.15, 1.0),
    "critter": (-3.2, 1.0, 1.15, 1.0), "spooky": (0.0, 1.0, 1.15, 1.0), "robo": (3.2, 1.0, 1.15, 1.0),
}
PACK_TILT = Rx(-8)  # leaning back a little against its stand


def pack_face_gui(d):
    """The printed front of a pack: DECK WARS, the pack's name, its family."""
    words = d["name"].upper().replace(" PACK", "").split(" ")
    title = "\n".join(words)
    sub = (d["family"].upper() + " PACK") if d.get("family") else "ALL FAMILIES"
    def lbl(name, text, y, h, color, font="GothamBlack", stroke=0.5):
        return {"Name": name, "ClassName": "TextLabel", "Properties": {
            "Text": text, "Size": {"UDim2": [[0.9, 0], [h, 0]]}, "Position": {"UDim2": [[0.05, 0], [y, 0]]},
            "BackgroundTransparency": 1, "TextScaled": True, "Font": font, "TextColor3": c3(color),
            "TextStrokeTransparency": stroke, "TextStrokeColor3": c3(d["dark"])}}
    bg = {"Name": "Bg", "ClassName": "Frame", "Properties": {
        "Size": {"UDim2": [[1, 0], [1, 0]]}, "BackgroundColor3": c3((255, 255, 255)), "BorderSizePixel": 0, "ZIndex": 0},
        "Children": [{"Name": "Foil", "ClassName": "UIGradient", "Properties": {
            "Rotation": 70,
            "Color": {"ColorSequence": {"keypoints": [{"time": 0, "color": c3(d["color"])}, {"time": 0.55, "color": c3(kshade(d["color"], 0.7))}, {"time": 1, "color": c3(d["dark"])}]}}}}]}
    kids = [
        bg,
        lbl("Brand", "DECK WARS", 0.04, 0.11, d["accent"], "GothamBold", 1),
        lbl("Title", title, 0.2, 0.52, (255, 255, 255)),
        lbl("Family", sub, 0.78, 0.1, d["accent"], "GothamBold", 1),
    ]
    return {"Name": "PackArt", "ClassName": "SurfaceGui", "Properties": {
        "Face": "Back", "SizingMode": "PixelsPerStud", "PixelsPerStud": 90, "LightInfluence": 0.15}, "Children": kids}


def build_pack(d, slot):
    """One pack on its riser. Returns (riser nodes, pack Model node, mascot spot node)."""
    sx, fy, sz, k = slot
    base = np.array([sx, fy, sz], float)
    riser = Model("Riser")
    riser.blk("PackRiser", (2.1 * k, 0.3, 1.1 * k), (sx, fy + 0.15, sz), (205, 225, 255), mat="Glass", tr=0.35, refl=0.1)
    glow = riser.blk("RiserGlow", (2.0 * k, 0.07, 0.07), (sx, fy + 0.05, sz + 0.56 * k), d["color"], mat="Neon")
    riser.blk("PackPlate", (1.5 * k, 0.22, 0.06), (sx, fy + 0.17, sz + 0.57 * k), LACQUER, mat="Metal", R=Rx(-15))
    # a soft backlight in the pack's color on the back wall of its niche
    riser.blk("PackBacklight", (2.6 * k, 2.6 * k, 0.05), (sx, fy + 1.55 * k, -1.37), d["color"], mat="Neon", tr=0.72)
    riser_nodes = emit(riser, offset=SHELF_AT, yaw=SHELF_YAW,
                       children={glow: [light("PointLight", d["color"], 1.6, 4.0 * k)]},
                       props={i: {"CanQuery": False, "CastShadow": False} for i in range(1, 5)})
    # the pack itself, in its own frame (center of the pack at the origin), then tilted and placed
    pk = Model("Pack")
    pk.blk("PackBody", (1.7, 2.1, 0.2), (0, 0, 0), d["color"], mat="Foil", refl=0.12)
    pk.blk("PackTop", (1.78, 0.32, 0.24), (0, 1.2, 0), d["accent"], mat="SmoothPlastic", refl=0.05)
    for j in range(7):
        pk.wedge("PackCrimp", (0.2, 0.1, 0.24), (-0.76 + j * 0.253, 1.41, 0), d["accent"])
    pk.blk("PackBottom", (1.78, 0.2, 0.24), (0, -1.14, 0), d["accent"])
    face = pk.blk("PackFace", (1.46, 1.72, 0.02), (0, 0.0, 0.11), kshade(d["color"], 0.7))
    for sxx in (-1, 1):
        pk.blk("PackEdge", (0.06, 2.0, 0.06), (sxx * 0.86, 0, 0.1), d["accent"], mat="Neon")
    pk.blk("PackTear", (1.6, 0.03, 0.03), (0, 1.02, 0.115), d["accent"], mat="Neon")
    center = base + np.array([0, 0.3 + 1.32 * k, 0])
    for p in pk.parts:
        p["pos"] = tuple(center + PACK_TILT @ (np.array(p["pos"]) * k))
        p["size"] = tuple(v * k for v in p["size"])
        p["R"] = PACK_TILT @ p["R"]
    pack_nodes = emit(pk, offset=SHELF_AT, yaw=SHELF_YAW, children={face: [pack_face_gui(d)]},
                      props={i: {"CastShadow": False} for i in range(1, len(pk.parts) + 1)})
    pack_model = model("ShelfPack_" + d["id"], pack_nodes)
    # the mascot figurine (built by the client) stands to the right of the pack, a little behind
    spot = None
    if d.get("mascot"):
        ms = Model("Spot")
        ms.blk("MascotSpot_" + d["id"], (0.2, 0.2, 0.2), (sx + 1.3, fy, sz - 0.3), (0, 0, 0), tr=1, R=Ry(180))
        spot = emit(ms, offset=SHELF_AT, yaw=SHELF_YAW, props={1: {"CanQuery": False, "CastShadow": False}})[0]
        spot["Properties"]["CFrame"]["CFrame"]["position"][1] = r4(fy)
    return riser_nodes, pack_model, spot


def build_pack_shelf():
    sh = Model("PackShelf")
    # plinth with a brass edge and an LED strip in the six family colors
    sh.blk("Plinth", (10.6, 1.0, 3.8), (0, 0.5, 0.15), LACQUER, refl=0.06)
    sh.blk("PlinthTop", (10.1, 0.06, 3.5), (0, 1.0, 0.15), LACQUER_LIGHT, mat="Fabric")
    sh.blk("PlinthTrim", (10.7, 0.12, 0.12), (0, 1.0, 2.06), GOLD, mat="Metal", refl=0.15)
    fam = [d for d in PACKS if d.get("family")]
    for j, d in enumerate(fam):
        sh.blk("PlinthGlow", (10.4 / 6, 0.12, 0.08), (-5.2 + 10.4 / 12 + j * 10.4 / 6, 0.16, 2.06), d["color"], mat="Neon")
    # back and sides
    sh.blk("ShelfBack", (10.6, 11.0, 0.4), (0, 6.0, -1.65), LACQUER)
    sh.blk("ShelfBackInset", (9.8, 10.2, 0.08), (0, 6.1, -1.43), LACQUER_LIGHT, mat="Fabric")
    for sx in (-1, 1):
        sh.blk("ShelfSide", (0.5, 11.6, 3.8), (sx * 5.3, 5.8, 0.15), LACQUER, refl=0.06)
        sh.blk("ShelfSideGlow", (0.08, 11.0, 0.08), (sx * 5.3, 5.8, 2.07), GOLD, mat="Neon")
        sh.blk("ShelfSideCap", (0.7, 0.18, 4.0), (sx * 5.3, 11.68, 0.15), GOLD, mat="Metal", refl=0.15)
    # middle step and the top niche
    sh.blk("ShelfStep", (10.1, 0.35, 2.6), (0, 4.05, -0.2), LACQUER, refl=0.06)
    sh.blk("ShelfStepLip", (10.1, 0.12, 0.1), (0, 4.17, 1.13), GOLD, mat="Metal", refl=0.15)
    sh.blk("ShelfTop", (4.6, 0.35, 1.9), (0, 7.45, -0.55), LACQUER, refl=0.06)
    sh.blk("ShelfTopLip", (4.6, 0.12, 0.1), (0, 7.57, 0.42), GOLD, mat="Metal", refl=0.15)
    halo = sh.blk("HaloBack", (3.2, 3.2, 0.05), (0, 9.3, -1.36), (60, 44, 110), mat="Neon", tr=0.55)
    sh.ring("Halo", (0, 9.3, -1.3), 1.75, 0.14, GOLD, normal="z", segments=18, mat="Neon")
    # glass jars of mini packs on brackets beside the top niche
    for sx in (-1, 1):
        x = sx * 3.65
        sh.blk("JarBracket", (1.5, 0.2, 1.5), (x, 7.3, -0.4), LACQUER, refl=0.06)
        sh.cyl("PackJar", 1.6, 1.25, (x, 8.2, -0.4), (220, 235, 255), mat="Glass", tr=0.55, refl=0.1)
        sh.cyl("PackJarLid", 0.2, 1.32, (x, 9.05, -0.4), GOLD, mat="Metal", refl=0.15)
        for j in range(6):
            d = fam[(j + (0 if sx < 0 else 3)) % 6]
            sh.blk("MiniPack", (0.36, 0.5, 0.06), (x - 0.3 + (j % 3) * 0.3, 7.7 + (j // 3) * 0.48, -0.4 + ((j * 37) % 5 - 2) * 0.08), d["color"],
                   R=rot(x=0, y=(j * 47) % 90 - 45, z=(j * 29) % 30 - 15))
    # the marquee sign with its bulbs
    marquee = sh.blk("Marquee", (10.8, 1.7, 0.6), (0, 12.25, -1.2), LACQUER, refl=0.06)
    sh.blk("MarqueeTrim", (11.0, 0.12, 0.7), (0, 13.12, -1.2), GOLD, mat="Metal", refl=0.15)
    sh.blk("MarqueeTrim", (11.0, 0.12, 0.7), (0, 11.38, -1.2), GOLD, mat="Metal", refl=0.15)
    for j in range(15):
        x = -5.0 + j * (10.0 / 14)
        for y in (13.0, 11.5):
            sh.ball("MarqueeBulb", 0.22, (x, y, -0.86), BULB, mat="Neon")
    lamp = sh.blk("ShelfLamp", (9.0, 0.15, 0.4), (0, 11.2, -0.9), (60, 50, 80), mat="Metal")
    lamp_light = light("SpotLight", (255, 240, 220), 2.2, 16, extra={"Angle": 80, "Face": "Bottom"})
    marquee_gui = {"Name": "MarqueeGui", "ClassName": "SurfaceGui", "Properties": {
        "Face": "Back", "SizingMode": "PixelsPerStud", "PixelsPerStud": 40, "LightInfluence": 0},
        "Children": [{"Name": "Title", "ClassName": "TextLabel", "Properties": {
            "Text": "PACK SHELF", "Size": {"UDim2": [[0.9, 0], [0.62, 0]]}, "Position": {"UDim2": [[0.05, 0], [0.19, 0]]},
            "BackgroundTransparency": 1, "TextScaled": True, "Font": "GothamBlack", "TextColor3": c3(GOLD),
            "TextStrokeTransparency": 0.4, "TextStrokeColor3": c3((90, 40, 10))}}]}
    nodes = emit(sh, offset=SHELF_AT, yaw=SHELF_YAW,
                 children={marquee: [marquee_gui], lamp: [lamp_light]},
                 props={halo: {"CanQuery": False, "CastShadow": False}})
    for d in PACKS:
        riser_nodes, pack_model, spot = build_pack(d, SHELF_SLOTS[d["id"]])
        nodes += riser_nodes
        nodes.append(pack_model)
        if spot:
            nodes.append(spot)
    return model("PackShelf", nodes)


# ---------------------------------------------------------------------------
# Pack Party corner (north-east)
# ---------------------------------------------------------------------------
pp = Model("PackParty")
pack_colors = [(255, 90, 90), (90, 170, 255), (255, 210, 60), (150, 230, 110), (200, 120, 255), (255, 150, 60)]
for i in range(6):
    for j in range(6):
        pp.blk("DiscoTile", (1.95, 0.12, 1.95), (11 + i * 2, 0.07, -21 + j * 2), (60, 40, 90), mat="Neon", tr=0.45)
# speakers
for (x, z, yaw) in [(10.4, -22.3, 0), (22.3, -10.4, -90)]:
    spk = Model("Speaker")
    spk.blk("Speaker", (2.4, 4.4, 2.0), (0, 2.2, 0), (35, 35, 40))
    for (y, dd) in [(3.2, 1.4), (1.3, 1.8)]:
        spk.cyl("SpeakerCone", 0.12, dd, (0, y, 1.02), (60, 60, 65), axis="z", mat="Rubber")
        spk.cyl("SpeakerDust", 0.14, dd * 0.3, (0, y, 1.05), (25, 25, 30), axis="z")
    Rw = Ry(yaw)
    for p in spk.parts:
        p["pos"] = tuple(Rw @ np.array(p["pos"]) + np.array([x, 0, z]))
        p["R"] = Rw @ p["R"]
        pp.parts.append(p)
# balloons
for (x, y, z, c) in [(10.8, 8.6, -21.8, (255, 80, 120)), (11.8, 9.4, -22.6, (90, 170, 255)), (22.4, 9.0, -11.6, (255, 220, 60)), (21.6, 8.2, -10.6, (150, 230, 110)), (12.6, 10.2, -23.0, (200, 120, 255))]:
    pp.ell("Balloon", (1.3, 1.6, 1.3), (x, y, z), c, refl=0.2)
    pp.ell("BalloonKnot", (0.25, 0.2, 0.25), (x, y - 0.85, z), c)
    pp.cyl("BalloonString", y - 4.7, 0.04, (x, (y - 0.9 + 3.8) / 2, z), (240, 240, 240))
# string lights along the corner walls
string_lights = []
for k in range(12):
    x = 9 + k * 1.25
    string_lights.append(pp.ball("StringLight", 0.32, (x, 14.6 - 0.35 * math.sin(k * math.pi / 3) ** 2, -HALF + 0.5), pack_colors[k % 6], mat="Neon"))
for k in range(12):
    z = -9 - k * 1.25
    string_lights.append(pp.ball("StringLight", 0.32, (HALF - 0.5, 14.6 - 0.35 * math.sin(k * math.pi / 3) ** 2, z), pack_colors[(k + 3) % 6], mat="Neon"))
pp.cyl("LightWire", 15, 0.04, (16.5, 14.8, -HALF + 0.5), (30, 30, 30), axis="x")
pp.cyl("LightWire", 15, 0.04, (HALF - 0.5, 14.8, -16.5), (30, 30, 30), axis="z")
disco = pp.ball("DiscoBall", 2.6, (14, H - 3.2, -14), (225, 225, 240), mat="Foil", refl=0.6)
pp.cyl("DiscoString", 1.9, 0.08, (14, H - 1.0, -14), (200, 200, 200))
party_lights = []
for i, (c, x, z) in enumerate([((255, 60, 140), 10, -22), ((60, 200, 255), 22, -10), ((255, 220, 60), 22, -22)]):
    party_lights.append(pp.blk("PartyLight%d" % (i + 1), (1.2, 0.8, 1.2), (x, H - 1.2, z), c, mat="Neon"))
pp_children = {disco: [sparkles((255, 255, 255))]}
for i, idx in enumerate(party_lights):
    c = [(255, 60, 140), (60, 200, 255), (255, 220, 60)][i]
    pp_children[idx] = [light("SpotLight", c, 2.4, 26, extra={"Angle": 60, "Face": "Bottom"})]
pp_nodes = emit(pp, children=pp_children)
pp_nodes.append(build_pack_shelf())
pp_nodes += label_part("PartyLabel", (14.5, 14.6, -14.5), "PACK PARTY", color=(255, 230, 120))

# ---------------------------------------------------------------------------
# Shop counter (south-east) with Pickles the shopkeeper
# ---------------------------------------------------------------------------
sp = Model("ShopCounter")
sp.blk("Counter", (12, 4, 3), (15, 2, 15), (190, 130, 85), mat="WoodPlanks")
for k in range(4):
    sp.blk("CounterPanel", (2.4, 2.6, 0.12), (10.6 + k * 2.95, 2.0, 13.45), (170, 112, 72), mat="Wood")
sp.blk("CounterTop", (12.6, 0.4, 3.4), (15, 4.2, 15), (240, 240, 240), mat="Marble")
sp.blk("Register", (2.0, 1.4, 1.6), (10.5, 5.1, 15), (70, 70, 80), mat="Metal")
sp.blk("RegisterScreen", (1.2, 0.6, 0.1), (10.5, 6.2, 14.6), (40, 40, 50), R=rot(x=-20))
sp.blk("RegisterDigits", (1.0, 0.35, 0.05), (10.5, 6.22, 14.53), (110, 255, 140), mat="Neon", R=rot(x=-20))
for k in range(6):
    sp.blk("RegisterKey", (0.3, 0.1, 0.3), (10.0 + (k % 3) * 0.5, 5.85, 14.6 + (k // 3) * 0.4), (230, 230, 230))
sp.blk("RegisterDrawer", (1.9, 0.4, 1.7), (10.5, 4.6, 14.9), (90, 90, 100), mat="Metal")
sp.blk("PackDisplay", (3.0, 0.3, 1.4), (19.5, 4.55, 15), (240, 200, 90))
for k in range(5):
    sp.blk("DisplayPack", (0.8, 1.2, 0.12), (18.5 + k * 0.5, 5.3, 15 - 0.1 * k), pack_colors[k], R=rot(z=(k - 2) * 12))
# awning over the counter
for sxp in (9.3, 20.7):
    sp.cyl("AwningPost", 6.0, 0.3, (sxp, 7.4, 14.0), (230, 230, 235), mat="Metal")
for k in range(8):
    c = (220, 60, 60) if k % 2 == 0 else (250, 250, 245)
    sp.blk("Awning", (1.5, 0.12, 3.6), (9.75 + k * 1.5, 10.6, 15.4), c, mat="Fabric", R=rot(x=18))
for k in range(8):
    c = (220, 60, 60) if k % 2 == 0 else (250, 250, 245)
    sp.ell("AwningScallop", (1.5, 0.7, 0.12), (9.75 + k * 1.5, 9.9, 13.65), c, mat="Fabric")
# back shelves
for y in (5.0, 8.0, 11.0):
    sp.blk("BackShelf", (11, 0.3, 1.6), (15, y, HALF - 0.8), (135, 90, 56), mat="Wood")
    for k in range(9):
        c = pack_colors[(k + int(y)) % 6]
        if k % 3 == 2:
            sp.cyl("Jar", 1.0, 0.8, (10.4 + k * 1.15, y + 0.65, HALF - 0.8), (200, 230, 255), mat="Glass", tr=0.3)
            sp.cyl("JarCandy", 0.6, 0.65, (10.4 + k * 1.15, y + 0.5, HALF - 0.8), c)
        else:
            sp.blk("PackBox", (0.9, 1.3, 0.9), (10.4 + k * 1.15, y + 0.8, HALF - 0.8), c, mat="Cardboard")
sp.blk("PriceBoard", (7.4, 3.2, 0.3), (15, 14.4, HALF - 0.2), (60, 45, 35), mat="Wood")
price = sp.blk("PriceBoardFace", (7.0, 2.8, 0.05), (15, 14.4, HALF - 0.38), (30, 45, 35))
# Pickles the pickle shopkeeper
pk = (110, 165, 60)
sp.ell("Pickles", (2.6, 4.4, 2.4), (15, 4.8, 18.4), pk)
for (x, y, z) in [(14.0, 5.6, 17.4), (15.9, 4.4, 17.3), (14.6, 3.7, 17.3), (16.0, 6.1, 17.6), (14.3, 6.6, 17.9)]:
    sp.ball("PickleBump", 0.35, (x, y, z), (95, 145, 50))
for sxp in (-1, 1):
    sp.ell("PicklesEye", (0.62, 0.7, 0.35), (15 + sxp * 0.42, 6.0, 17.25), (255, 255, 255))
    sp.ell("PicklesPupil", (0.3, 0.34, 0.2), (15 + sxp * 0.42, 5.95, 17.08), (30, 25, 35))
sp.ell("PicklesMustache", (1.2, 0.3, 0.3), (15, 5.35, 17.15), (90, 60, 40), mat="Fabric")
sp.ell("PicklesSmile", (0.6, 0.15, 0.15), (15, 5.0, 17.2), (60, 30, 30))
sp.blk("PicklesApron", (2.0, 1.6, 0.15), (15, 4.3, 17.25), (245, 245, 250), mat="Fabric")
sp.cyl("PicklesHat", 0.7, 1.4, (15, 7.2, 18.4), (250, 250, 250))
sp.blk("PicklesHatBand", (1.45, 0.2, 1.45), (15, 6.95, 18.4), (220, 60, 60))
for sxp in (-1, 1):
    sp.rod("PicklesArm", (15 + sxp * 1.15, 5.0, 18.0), (15 + sxp * 1.5, 4.55, 16.4), 0.4, pk)
    sp.ball("PicklesHand", 0.55, (15 + sxp * 1.5, 4.6, 16.3), pk)
shop_nodes = emit(sp, children={price: [surface_text("Front", [("PICKLES' PACKS", 0.36), ("Snack Pack ..... 100 coins", 0.2), ("Gems & cosmetics: soon!", 0.2)], color=(250, 240, 200), ppsd=40)]})
shop_nodes += label_part("ShopLabel", (15, 13.0, 15), "SHOP", (8, 2.2), (255, 240, 150))

# ---------------------------------------------------------------------------
# Trophy wall (east wall)
# ---------------------------------------------------------------------------
tw = Model("TrophyWall")
ex0 = HALF
tw.blk("Plaque", (0.6, 9.5, 14.4), (ex0 - 0.35, 8, 0), (100, 65, 40), mat="Wood")
tw.blk("PlaqueTrim", (0.4, 9.9, 14.8), (ex0 - 0.2, 8, 0), (80, 52, 32), mat="Wood")
metals = [(240, 200, 60), (200, 205, 215), (205, 130, 70)]
for row, y in enumerate((5.4, 9.4)):
    tw.blk("TrophyShelf", (1.8, 0.3, 13.2), (ex0 - 1.5, y, 0), (130, 85, 52), mat="Wood")
    for k in range(3):
        z = -4.2 + k * 4.2 + row * 1.0
        mcol = metals[(k + row) % 3]
        tw.blk("TrophyBase", (1.1, 0.5, 1.1), (ex0 - 1.5, y + 0.4, z), (60, 40, 30), mat="Wood")
        tw.cyl("TrophyStem", 0.6, 0.3, (ex0 - 1.5, y + 0.95, z), mcol, mat="Metal", refl=0.2)
        tw.ell("TrophyCup", (1.1, 1.0, 1.1), (ex0 - 1.5, y + 1.6, z), mcol, mat="Metal", refl=0.25)
        tw.cyl("TrophyRim", 0.12, 1.15, (ex0 - 1.5, y + 2.05, z), mcol, mat="Metal")
        for sz2 in (-1, 1):
            tw.ring("TrophyHandle", (ex0 - 1.5, y + 1.6, z + sz2 * 0.62), 0.3, 0.08, mcol, normal="x", segments=8, mat="Metal")
for k in range(5):
    z = -5.6 + k * 2.8
    c = pack_colors[k]
    tw.wedge("Pennant", (0.1, 1.4, 2.2), (ex0 - 0.75, 12.0, z), c, mat="Fabric", R=rot(x=180))
tw.cyl("PennantString", 14, 0.04, (ex0 - 0.72, 12.75, 0), (240, 240, 240), axis="z")
for z in (-5.5, 5.5):
    tw.blk("Certificate", (0.1, 1.6, 2.2), (ex0 - 0.72, 7.4, z), (250, 245, 230))
    tw.cyl("Seal", 0.06, 0.5, (ex0 - 0.8, 7.0, z + 0.6), (220, 60, 60), axis="x")
trophy_nodes = emit(tw)
trophy_nodes += label_part("TrophyLabel", (21, 14.6, 0), "TROPHY WALL")

# ---------------------------------------------------------------------------
# Radio (settings) in the north-west corner
# ---------------------------------------------------------------------------
rd = Model("Radio")
rx, rz = -17, -18
rd.blk("SideTable", (4.2, 0.35, 4.2), (rx, 3.0, rz), (120, 78, 48), mat="Wood")
for (sx2, sz2) in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
    rd.cyl("SideTableLeg", 2.85, 0.35, (rx + sx2 * 1.7, 1.42, rz + sz2 * 1.7), (95, 62, 38), mat="Wood")
rd.blk("SideTableShelf", (3.6, 0.2, 3.6), (rx, 1.0, rz), (110, 72, 44), mat="Wood")
rd.blk("RadioBox", (3.2, 2.0, 1.6), (rx, 4.2, rz), (150, 85, 50), mat="Wood", refl=0.05)
rd.cyl("RadioTop", 3.2, 1.6, (rx, 5.2, rz), (150, 85, 50), axis="x", mat="Wood")
rd.blk("RadioGrille", (1.5, 1.4, 0.1), (rx - 0.6, 4.4, rz + 0.82), (200, 175, 130), mat="Fabric")
rd.blk("RadioDial", (1.0, 0.45, 0.08), (rx + 0.85, 4.75, rz + 0.84), (255, 190, 90), mat="Neon")
rd.blk("RadioNeedle", (0.04, 0.4, 0.04), (rx + 0.75, 4.75, rz + 0.9), (200, 40, 40))
for k in range(2):
    rd.cyl("RadioKnob", 0.25, 0.4, (rx + 0.6 + k * 0.55, 3.95, rz + 0.9), (60, 40, 30), axis="z")
rd.rod("RadioAntenna", (rx + 1.1, 5.9, rz), (rx + 1.9, 8.2, rz - 0.4), 0.08, (200, 200, 210), mat="Metal")
rd.ball("RadioAntennaTip", 0.2, (rx + 1.92, 8.25, rz - 0.42), (200, 200, 210), mat="Metal")
for k, (y, dz) in enumerate([(6.4, 0.2), (7.0, -0.3)]):
    rd.blk("MusicNote", (0.12, 0.5, 0.05), (rx - 0.8 - k * 0.6, y, rz + 0.9 + dz), (255, 220, 90), mat="Neon")
    rd.ball("MusicNoteHead", 0.25, (rx - 0.88 - k * 0.6, y - 0.25, rz + 0.9 + dz), (255, 220, 90), mat="Neon")
radio_nodes = emit(rd)
radio_nodes += label_part("RadioLabel", (-17, 9.2, -18), "SETTINGS", (7, 1.8))

room = model("MenuRoom", [
    folder("Structure", structure),
    folder("Stations", [model("DuelTable", table_nodes), model("DeckShelf", shelf_nodes), model("PackParty", pp_nodes),
                        model("ShopCounter", shop_nodes), model("TrophyWall", trophy_nodes), model("Radio", radio_nodes)]),
])
json.dump(room, open("src/world/MenuRoom.model.json", "w"), indent=None, separators=(",", ":"))
txt = json.dumps(room)
print("parts:", txt.count('"ClassName": "Part"') + txt.count('"ClassName": "WedgePart"') + txt.count('"ClassName": "Seat"'), "size KB:", len(txt) // 1024)
