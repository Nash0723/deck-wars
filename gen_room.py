# Rebuilds the menu room's props in the chunky, rounded style of the remodelled cards:
# speakers, radio and side table, trophies, pennants and certificates, the shop (Pickles, the
# register, the counter, candy jars, booster boxes, display packs), binders and card boxes,
# balloons, the fireplace, candlesticks, the mantel clock and trophy, hanging lamps, potted
# plants, the front door and the painting's frame.
#
#     python3 gen_room.py [src/world/MenuRoom.rbxmx]      (rewrites the file in place)
#
# Safe to run again: every prop is first taken out of the room (all its parts, found by name
# near where it stands), then built again at the same spot.
#
# The parts keep the names the room's scripts look for (RoomLife's hover/click reactions,
# HubRoom's Park door and Campaign painting, ParkClient's door hinge), each prop stays where it
# was and keeps its size, and lights, fire and signs move over to the new parts. New detail
# parts get their own names (SpeakerTrim, RegisterBody, ...): RoomLife.luau lists them so they
# move with their prop.
import math
import sys
import xml.etree.ElementTree as ET

import numpy as np

from modelkit import Rx, Ry, Rz, I3, shade, frame_from_x, frame_normal
from stylekit import SModel, V, norm, INK, GOLD, WHITE

ROOM = "src/world/MenuRoom.rbxmx"

MATERIAL = {"Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528, "Marble": 784,
            "Slate": 800, "Concrete": 816, "Granite": 832, "Brick": 848, "Pebble": 864, "Cobblestone": 880, "Rock": 896,
            "Sandstone": 912, "CorrodedMetal": 1040, "DiamondPlate": 1056, "Foil": 1072, "Metal": 1088, "Grass": 1280,
            "Fabric": 1312, "Glass": 1568, "Cardboard": 2304, "Carpet": 2305, "CeramicTiles": 2306,
            "Leather": 2309, "Plaster": 2310, "Rubber": 2311, "Ice": 1536, "Marble ": 784}

BRASS = (226, 180, 82)
BRASS_DK = (176, 132, 60)
CHROME = (214, 218, 228)
WALNUT = (112, 70, 42)
WALNUT_DK = (82, 50, 30)
OAK = (168, 112, 66)


# ------------------------------------------------------------------------------------------------
# The room file
# ------------------------------------------------------------------------------------------------
def _name(item):
    p = item.find("Properties")
    for q in p:
        if q.get("name") == "Name":
            return q.text
    return None


def _cframe(item):
    for q in item.find("Properties"):
        if q.tag == "CoordinateFrame" and q.get("name") == "CFrame":
            v = {c.tag: float(c.text) for c in q}
            return V(v["X"], v["Y"], v["Z"]), np.array([[v["R00"], v["R01"], v["R02"]], [v["R10"], v["R11"], v["R12"]],
                                                        [v["R20"], v["R21"], v["R22"]]])
    return None, None


def _bool(item, name, default):
    for q in item.find("Properties"):
        if q.get("name") == name and q.tag == "bool":
            return q.text == "true"
    return default


PART_CLASSES = ("Part", "WedgePart", "Seat", "SpawnLocation")


def color_of(item):
    for q in item.find("Properties"):
        if q.get("name") == "Color3uint8":
            c = int(q.text) & 0xFFFFFF
            return ((c >> 16) & 255, (c >> 8) & 255, c & 255)
    return (160, 160, 160)


def nearest(taken, name, pos):
    """The taken part called `name` nearest to pos: (name, position, item)."""
    c = [t for t in taken if t[0] == name]
    return min(c, key=lambda t: np.linalg.norm(t[1] - V(*pos))) if c else None


class RoomFile:
    def __init__(self, path):
        self.path = path
        self.tree = ET.parse(path)
        self.root = self.tree.getroot()
        self.room = self.root.find("Item")
        assert _name(self.room) == "MenuRoom", "not the menu room"
        self.made = 0
        self.taken = []

    def container(self, path):
        node = self.room
        for step in path.split("/"):
            node = next(k for k in node.findall("Item") if _name(k) == step)
        return node

    def take(self, path, names, near=None, radius=1.0, box=None):
        """Take out the parts called one of `names` that are direct children of the container at
        `path` and stand within `radius` of a point in `near` (or inside box = (lo, hi)).
        Returns the removed parts as [(name, position, item)]."""
        cont = self.container(path)
        names = set(names)
        out = []
        for k in list(cont.findall("Item")):
            if k.get("class") not in PART_CLASSES or _name(k) not in names:
                continue
            pos, _ = _cframe(k)
            ok = False
            if near is not None:
                ok = any(np.linalg.norm(pos - V(*c)) <= radius for c in near)
            if box is not None:
                lo, hi = V(*box[0]), V(*box[1])
                ok = ok or bool(np.all(pos >= lo) and np.all(pos <= hi))
            if ok:
                cont.remove(k)
                out.append((_name(k), pos, k))
        self.taken += out
        return out

    def put(self, path, m, origin, yaw=0.0, taken=(), collide=None, after=None, carry=3.0, R=None, scale=1.0):
        """Add model m's parts to the container at `path`, scaled, turned by yaw (degrees, about y;
        or by the rotation R) and moved to origin. Lights, fire, sparkles and GUIs on the taken
        parts move to the new part of the same name nearest to where they were. A part can be
        bumped into if the old parts of its name could (or if its name is in `collide`)."""
        cont = self.container(path)
        Rw = Ry(yaw) if R is None else np.array(R, float)
        o = V(*origin)
        if collide is None:
            collide = {nm for (nm, _, old) in taken if _bool(old, "CanCollide", True)}
        new = []
        for p in m.parts:
            q = dict(p)
            if scale != 1.0:
                q["size"] = tuple(float(v) * scale for v in p["size"])
            Rp = Rw @ np.array(p["R"], float)
            pos = Rw @ (V(*p["pos"]) * scale) + o
            item = self._part_item(q, pos, Rp, p["name"] in collide)
            new.append((p["name"], pos, item))
        # carry the extras (lights, fire, guis) over from the old parts to the nearest new part
        # of the same name (within `carry` studs: the others wait for their own prop)
        for (nm, pos, old) in taken:
            extras = [c for c in old.findall("Item") if c.get("class") != "SpecialMesh"]
            if not extras:
                continue
            same = [(np.linalg.norm(npos - pos), item) for (nn, npos, item) in new if nn == nm]
            if not same or min(t[0] for t in same) > carry:
                continue
            target = min(same, key=lambda t: t[0])[1]
            for e in extras:
                old.remove(e)
                target.append(e)
        idx = len(list(cont)) if after is None else after
        for (_, _, item) in new:
            cont.insert(idx, item)
            idx += 1
        self.made += len(new)
        return new

    def _part_item(self, p, pos, R, collide):
        shape = p["shape"]
        cls = "WedgePart" if shape == "W" else "Part"
        item = ET.Element("Item", {"class": cls, "referent": "RBX0"})
        pr = ET.SubElement(item, "Properties")

        def add(tag, name, text=None):
            e = ET.SubElement(pr, tag, {"name": name})
            if text is not None:
                e.text = text
            return e

        def num(v):
            v = float(v)
            if abs(v) < 5e-7:
                v = 0.0
            s = f"{v:.6f}".rstrip("0").rstrip(".")
            return "0" if s in ("-0", "") else s

        add("string", "Name", p["name"])
        add("bool", "Anchored", "true")
        add("token", "BottomSurface", "0")
        cf = add("CoordinateFrame", "CFrame")
        for tag, v in (("X", pos[0]), ("Y", pos[1]), ("Z", pos[2])):
            ET.SubElement(cf, tag).text = num(v)
        for i in range(3):
            for j in range(3):
                ET.SubElement(cf, f"R{i}{j}").text = num(R[i, j])
        neon = p["mat"] == "Neon"
        clear = p["tr"] >= 0.3
        add("bool", "CanCollide", "true" if collide else "false")
        add("bool", "CanQuery", "true")
        add("bool", "CanTouch", "false")
        add("bool", "CastShadow", "false" if (neon or clear) else "true")
        r, g, b = (int(max(0, min(255, round(c)))) for c in p["color"])
        add("Color3uint8", "Color3uint8", str((r << 16) | (g << 8) | b))
        add("token", "Material", str(MATERIAL[p["mat"]]))
        add("float", "Reflectance", num(p["refl"]))
        add("token", "shape", {"S": "0", "C": "2"}.get(shape, "1"))
        sz = add("Vector3", "size")
        for tag, v in zip("XYZ", p["size"]):
            ET.SubElement(sz, tag).text = num(max(float(v), 0.02))
        add("token", "TopSurface", "0")
        add("float", "Transparency", num(p["tr"]))
        if shape == "E":
            mesh = ET.SubElement(item, "Item", {"class": "SpecialMesh", "referent": "RBX0"})
            mp = ET.SubElement(mesh, "Properties")
            ET.SubElement(mp, "string", {"name": "Name"}).text = "Mesh"
            ET.SubElement(mp, "token", {"name": "MeshType"}).text = "3"
        return item

    def save(self, path=None):
        left = [(nm, [c.get("class") for c in old.findall("Item") if c.get("class") != "SpecialMesh"])
                for (nm, _, old) in self.taken]
        left = [x for x in left if x[1]]
        if left:
            raise SystemExit(f"lights/guis left on removed parts: {left}")
        n = [0]

        def renumber(item):
            n[0] += 1
            item.set("referent", "RBX%08X" % n[0])
            for k in item.findall("Item"):
                renumber(k)

        renumber(self.room)
        ET.ElementTree(self.root).write(path or self.path, encoding="utf-8", xml_declaration=False)
        return n[0]


def rename(m, table, start=0):
    """Rename parts (from index start) by the table {old name: new name}; others keep theirs."""
    for p in m.parts[start:]:
        p["name"] = table.get(p["name"], p["name"])


def name_all(m, name, start=0):
    for p in m.parts[start:]:
        p["name"] = name


def disc(m, name, c, d, t, color, normal=(0, 0, -1), mat="SmoothPlastic", tr=0.0, refl=0.0):
    """A flat round disc (a cylinder d across and t thick) facing along normal."""
    return m.add("C", name, (t, d, d), c, color, mat, frame_from_x(norm(normal)), tr, refl)


def arc_rods(m, name, c, r, a0, a1, n, d, color, plane=I3, mat="SmoothPlastic", joints=True, refl=0.0):
    """A smooth bent tube along an arc (rods with round joints) in the plane's x-y."""
    P = np.asarray(plane, float)
    pts = [V(*c) + P @ V(math.cos(math.radians(a0 + (a1 - a0) * k / n)) * r,
                         math.sin(math.radians(a0 + (a1 - a0) * k / n)) * r, 0) for k in range(n + 1)]
    for i in range(n):
        m.rod(name, pts[i], pts[i + 1], d, color, mat, refl=refl)
        if joints and 0 < i:
            m.ball(name, d, pts[i], color, mat, refl=refl)
    return pts


def leaf(m, name, root, direction, length, width, color, thick=None, curl=0.0, mat="SmoothPlastic"):
    """A leaf as an ellipsoid whose own y axis runs from its root along `direction` (RoomLife
    sways leaves around the bottom end of that axis)."""
    d = norm(direction)
    side = np.cross(d, V(0, 1, 0)) if abs(d[1]) < 0.95 else V(1, 0, 0)
    side = norm(side)
    fwd = np.cross(side, d)
    R = np.column_stack([side, d, fwd]) @ Ry(curl)
    c = V(*root) + d * length / 2
    return m.add("E", name, (width, length, thick or width * 0.42), c, color, mat, R)


# ------------------------------------------------------------------------------------------------
# Pack Party: speakers and balloons
# ------------------------------------------------------------------------------------------------
def speaker():
    """A chunky party speaker: rounded cabinet, black baffle, chrome-ringed woofer and tweeter,
    a neon LED bar, chrome corner guards and rubber feet. Faces -z, stands on y = 0."""
    m = SModel("speaker", "room")
    body, baffle = (46, 40, 64), (24, 22, 30)
    W, H, D, y0 = 2.5, 4.28, 2.0, 0.12
    cy = y0 + H / 2
    m.rbox("Speaker", (W, H, D), (0, cy, 0), body, 0.22, axis="z", edge_name="SpeakerTrim")
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cyl("SpeakerTrim", 0.14, 0.34, (sx * 0.86, 0.07, sz * 0.62), (30, 30, 34), "y", "Rubber")
    zf = -D / 2
    m.blk("SpeakerTrim", (W - 0.36, H - 0.34, 0.08), (0, cy, zf - 0.03), baffle)
    # top strip: the brand plate and the LED bar
    m.blk("SpeakerTrim", (1.5, 0.09, 0.05), (0, y0 + H - 0.42, zf - 0.08), (255, 80, 200), "Neon")
    m.rbox("SpeakerTrim", (0.62, 0.2, 0.05), (0, y0 + 2.36, zf - 0.08), BRASS, 0.08, "Metal", axis="z")
    for (y, dd, cone, cap) in ((y0 + 1.32, 1.92, 1.42, 0.56), (y0 + 3.2, 1.16, 0.8, 0.46)):
        disc(m, "SpeakerTrim", (0, y, zf - 0.08), dd + 0.14, 0.06, CHROME, mat="Metal", refl=0.1)
        disc(m, "SpeakerCone", (0, y, zf - 0.12), dd, 0.06, (34, 34, 40), mat="Rubber")
        disc(m, "SpeakerCone", (0, y, zf - 0.155), cone, 0.04, (66, 66, 76))
        disc(m, "SpeakerCone", (0, y, zf - 0.175), cone * 0.62, 0.03, (52, 52, 60))
        m.ell("SpeakerDust", (cap, cap, cap * 0.55), (0, y, zf - 0.19), (20, 20, 26))
        m.ell("SpeakerDust", (cap * 0.3, cap * 0.22, cap * 0.12), (-cap * 0.13, y + cap * 0.17, zf - 0.33), (120, 120, 135))
    # bass port and corner guards
    m.rbox("SpeakerTrim", (1.3, 0.22, 0.05), (0, y0 + 0.26, zf - 0.06), (8, 8, 10), 0.1, axis="z")
    for sx in (-1, 1):
        for y in (y0 + 0.2, y0 + H - 0.2):
            m.ball("SpeakerTrim", 0.4, (sx * (W / 2 - 0.12), y, zf + 0.1), CHROME, "Metal", refl=0.1)
    return m


def balloon(color):
    """A shiny party balloon: a round body that narrows to the knot, a soft highlight, a curly
    ribbon. The body's middle is at y = 0 (the old balloon's centre)."""
    m = SModel("balloon", "room")
    m.ell("Balloon", (1.34, 1.5, 1.34), (0, 0.06, 0), color)
    m.ell("BalloonKnot", (0.92, 0.9, 0.92), (0, -0.42, 0), color)
    m.ell("BalloonKnot", (0.44, 0.5, 0.44), (0, -0.7, 0), color)
    m.ell("BalloonKnot", (0.26, 0.2, 0.26), (0, -0.88, 0), shade(color, 0.82))
    m.ell("BalloonKnot", (0.3, 0.42, 0.12), (-0.34, 0.36, -0.52), shade(color, 1.55), R=Rz(-28) @ Rx(-30))
    return m


def balloon_string(m, top, length):
    """A curly ribbon hanging from top (a few short bent rods)."""
    pts = []
    n = 7
    for k in range(n + 1):
        u = k / n
        pts.append(V(0.09 * math.sin(u * 9.0), top - u * length, 0.09 * math.cos(u * 9.0)))
    for i in range(n):
        m.rod("BalloonString", pts[i], pts[i + 1], 0.05, (245, 245, 250))


# ------------------------------------------------------------------------------------------------
# Radio corner: side table and radio
# ------------------------------------------------------------------------------------------------
def side_table():
    m = SModel("side_table", "room")
    top, dark = (128, 82, 50), (92, 58, 34)
    m.rbox("SideTable", (4.2, 0.36, 4.2), (0, 3.0, 0), top, 0.34)
    m.rbox("SideTable", (3.9, 0.22, 3.9), (0, 2.74, 0), dark, 0.3)
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * 1.62, sz * 1.62
            m.blk("SideTableLeg", (0.44, 0.5, 0.44), (x, 2.4, z), dark)
            m.seg("SideTableLeg", (x, 2.18, z), (x * 1.03, 0.36, z * 1.03), 0.21, dark, r2=0.21, bulge=0.32, ext=0.05)
            m.ball("SideTableLeg", 0.38, (x * 1.03, 0.2, z * 1.03), BRASS, "Metal")
    m.rbox("SideTableShelf", (3.5, 0.2, 3.5), (0, 1.0, 0), top, 0.3)
    return m


def radio():
    """A chunky cathedral radio: rounded wood body with a dome, cloth grille with ribs, a glowing
    dial with a red needle, brass-capped knobs, ball feet and a chrome antenna. Built on the table
    top (y = 0), facing -z."""
    m = SModel("radio", "room")
    wood, dark = (156, 88, 50), (104, 58, 32)
    m.rbox("RadioBox", (3.0, 1.84, 1.5), (0, 0.24 + 0.92, 0), wood, 0.26, "Wood", edge_name="RadioTop")
    m.ell("RadioTop", (3.0, 1.16, 1.5), (0, 2.04, 0), wood, "Wood")
    m.rbox("RadioTop", (3.12, 0.16, 1.6), (0, 0.32, 0), dark, 0.3)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.ball("RadioTop", 0.3, (sx * 1.2, 0.13, sz * 0.5), BRASS, "Metal")
    zf = -0.75
    # cloth grille with wooden ribs (left half from the front)
    m.rbox("RadioGrille", (1.5, 1.3, 0.06), (0.62, 1.28, zf - 0.02), (214, 186, 136), 0.16, "Fabric", axis="z")
    for k in range(4):
        x = 0.62 + (k - 1.5) * 0.34
        m.rod("RadioGrille", (x, 0.7, zf - 0.07), (x, 1.86, zf - 0.07), 0.1, dark, "Wood")
    m.rod("RadioGrille", (-0.13, 1.96, zf - 0.07), (1.37, 1.96, zf - 0.07), 0.12, dark, "Wood")
    # dial window (right half), needle and knobs
    m.rbox("RadioTop", (1.08, 0.6, 0.05), (-0.78, 1.62, zf - 0.03), BRASS, 0.1, "Metal", axis="z")
    m.blk("RadioDial", (0.92, 0.44, 0.05), (-0.78, 1.62, zf - 0.06), (255, 196, 96), "Neon")
    for k in range(5):
        m.blk("RadioTop", (0.03, 0.1, 0.02), (-1.12 + k * 0.17, 1.76, zf - 0.09), (120, 70, 30))
    m.blk("RadioNeedle", (0.05, 0.4, 0.03), (-0.88, 1.62, zf - 0.1), (210, 40, 40))
    for x in (-1.08, -0.48):
        disc(m, "RadioKnob", (x, 0.96, zf - 0.1), 0.46, 0.2, dark, mat="Wood")
        disc(m, "RadioKnob", (x, 0.96, zf - 0.21), 0.3, 0.06, BRASS, mat="Metal")
    m.rbox("RadioTop", (0.7, 0.18, 0.04), (0, 2.38, zf + 0.16), BRASS, 0.08, "Metal", axis="z")
    # antenna (from the back right corner of the top)
    a, b = V(-1.0, 2.5, 0.3), V(-1.58, 4.4, 0.52)
    m.rod("RadioAntenna", a, b, 0.09, CHROME, "Metal")
    m.ball("RadioAntennaTip", 0.22, b + norm(b - a) * 0.06, (230, 60, 60))
    # two floating music notes (they bob when you point at the radio)
    for (x, y, z, tilt) in ((0.8, 3.2, -1.1, -12), (1.42, 3.82, -0.6, 10)):
        R = Rz(tilt)
        with m.group(R=R, t=(x, y, z)):
            m.blk("MusicNote", (0.1, 0.56, 0.06), (0.1, 0.28, 0), (255, 222, 96), "Neon")
            m.blk("MusicNote", (0.26, 0.08, 0.06), (0.2, 0.52, 0), (255, 222, 96), "Neon", R=Rz(-28))
            m.ell("MusicNoteHead", (0.32, 0.24, 0.12), (-0.02, 0.0, 0), (255, 222, 96), "Neon", R=Rz(24))
    return m


# ------------------------------------------------------------------------------------------------
# Trophy Wall
# ------------------------------------------------------------------------------------------------
GOLD_M, SILVER_M, BRONZE_M = (240, 200, 60), (200, 205, 215), (205, 130, 70)


def trophy(metal, k=1.0, names=("TrophyCup", "TrophyRim", "TrophyStem", "TrophyHandle", "TrophyBase"), emblem=None):
    """A chunky trophy cup on a two-step wooden base with a gold plate: round-bottomed cup with a
    thick rim, two round handles, a stem with a knot. Stands on y = 0, faces -z. The first part
    is the cup's bowl (RoomLife's anchor)."""
    cup, rim, stem, handle, base = names
    m = SModel("trophy", "room")
    hi = shade(metal, 1.25)
    with m.group(scale=k):
        m.ell(cup, (1.12, 0.92, 1.12), (0, 1.44, 0), metal, "Metal", refl=0.15)
        m.cyl(rim, 0.5, 1.12, (0, 1.7, 0), metal, "y", "Metal", refl=0.15)
        m.cyl(rim, 0.12, 1.26, (0, 1.98, 0), hi, "y", "Metal", refl=0.15)
        m.cyl(rim, 0.04, 1.0, (0, 2.04, 0), shade(metal, 0.55), "y", "Metal")
        for s in (-1, 1):
            arc_rods(m, handle, (s * 0.56, 1.66, 0), 0.27, 90, -90, 4, 0.13, metal, plane=(I3 if s > 0 else Ry(180)), mat="Metal", refl=0.15)
        m.ell(stem, (0.5, 0.2, 0.5), (0, 1.0, 0), metal, "Metal", refl=0.15)
        m.cyl(stem, 0.42, 0.22, (0, 0.78, 0), metal, "y", "Metal", refl=0.15)
        m.ball(stem, 0.36, (0, 0.74, 0), hi, "Metal", refl=0.15)
        m.ell(stem, (0.62, 0.16, 0.62), (0, 0.56, 0), metal, "Metal", refl=0.15)
        m.cyl(base, 0.3, 1.3, (0, 0.15, 0), (66, 42, 30), "y", "Wood")
        m.cyl(base, 0.2, 1.0, (0, 0.4, 0), (84, 54, 36), "y", "Wood")
        m.blk(base, (0.56, 0.15, 0.03), (0, 0.15, -0.63), BRASS, "Metal")
        e = emblem or (GOLD_M if metal != GOLD_M else (230, 70, 70))
        disc(m, rim, (0, 1.62, -0.57), 0.36, 0.05, e, mat="Metal")
        disc(m, rim, (0, 1.62, -0.6), 0.2, 0.03, shade(e, 1.3), mat="Metal")
    return m


def pennant(color):
    """A felt pennant hanging point-down from its top edge (y = 0), facing -z: a sleeve, a white
    badge with a star, a contrasting trim."""
    from models_extra import tri, star
    m = SModel("pennant", "room")
    with m.group(R=Rz(180), t=(0, -0.06, 0)):
        tri(m, "Pennant", (0, 0, 0), 1.05, 1.5, 0.08, color, "Fabric")
    m.parts[1]["name"] = "PennantTrim"
    with m.group(R=Rz(180), t=(0, -0.1, -0.03)):
        tri(m, "PennantTrim", (0, 0, 0), 0.9, 1.28, 0.06, shade(color, 1.22), "Fabric")
    m.rod("PennantTrim", (-1.12, 0, 0), (1.12, 0, 0), 0.18, (250, 248, 240), "Fabric")
    disc(m, "PennantTrim", (0, -0.5, -0.09), 0.5, 0.04, (250, 248, 240), mat="Fabric")
    star(m, "PennantTrim", (0, -0.5, -0.12), (0, 0, -1), 0.34, 0.04, shade(color, 0.8))
    return m


def certificate():
    """A framed certificate (y = 0 its middle, facing -z): paper, lines of text, a gold frame and a
    red ribbon seal."""
    m = SModel("certificate", "room")
    m.blk("Certificate", (2.1, 1.5, 0.06), (0, 0, 0), (250, 245, 230))
    for (x0, x1, y) in ((-0.62, 0.62, 0.42), (-0.8, 0.8, 0.16), (-0.8, 0.5, -0.04), (-0.8, 0.2, -0.24)):
        m.blk("CertificateFrame", ((x1 - x0), 0.07 if y > 0.3 else 0.045, 0.02), ((x0 + x1) / 2, y, -0.04), (90, 70, 60))
    for (a, b) in (((-1.1, 0.8), (1.1, 0.8)), ((-1.1, -0.8), (1.1, -0.8)), ((-1.1, -0.8), (-1.1, 0.8)), ((1.1, -0.8), (1.1, 0.8))):
        m.rod("CertificateFrame", (a[0], a[1], -0.02), (b[0], b[1], -0.02), 0.16, BRASS, "Metal")
    for x in (-1.1, 1.1):
        for y in (-0.8, 0.8):
            m.ball("CertificateFrame", 0.2, (x, y, -0.02), BRASS, "Metal")
    disc(m, "Seal", (0.6, -0.42, -0.07), 0.46, 0.05, (220, 60, 60))
    disc(m, "Seal", (0.6, -0.42, -0.1), 0.28, 0.03, (245, 200, 80), mat="Metal")
    for s in (-1, 1):
        m.blk("Seal", (0.14, 0.42, 0.03), (0.6 + s * 0.1, -0.72, -0.05), (200, 50, 50), R=Rz(s * 16))
    return m


# ------------------------------------------------------------------------------------------------
# Shop
# ------------------------------------------------------------------------------------------------
def pickles():
    """Pickles the shopkeeper: a big friendly pickle in a straw boater, apron and bow tie, with a
    curly moustache, rosy cheeks and wide shiny eyes. Built on the floor under him, facing -z.
    Names match RoomLife's waving / blinking / eye-following parts."""
    from stylekit import on_ell_R
    m = SModel("pickles", "room")
    G, G_D, G_L = (112, 170, 62), (84, 136, 46), (150, 204, 92)
    c, size = V(0, 4.8, 0), (2.5, 4.3, 2.3)
    m.ell("Pickles", size, c, G)
    # warty bumps (none on the face)
    import random
    rnd = random.Random(7)
    k = 0
    while k < 14:
        a = rnd.uniform(-170, 170)
        el = rnd.uniform(-50, 62)
        if abs(a) < 48 and -10 < el < 45:
            continue
        d = Ry(a) @ Rx(el) @ V(0, 0, -1)
        p, n = on_ell_R(c, size, I3, d)
        m.ball("PickleBump", rnd.uniform(0.26, 0.38), p - n * 0.04, G_D if k % 3 else G_L)
        k += 1
    # face
    s0 = len(m.parts)
    m.eyes_on(c, size, I3, 17, 20, 0.74, 0.86, G, "cheerful", brow=(70, 46, 30), brow_k=1.1, look=(0, -0.05))
    rename(m, {"Eye": "PicklesEye", "Pupil": "PicklesPupil", "Glint": "PicklesPupil", "Brow": "PicklesBrow",
               "Lash": "PicklesBrow", "Lidhalf": "PicklesBrow"}, s0)
    for sx in (-1, 1):
        d = Ry(sx * 30) @ Rx(4) @ V(0, 0, -1)
        p, n = on_ell_R(c, size, I3, d)
        m.add("E", "PicklesCheek", (0.46, 0.26, 0.12), p + n * 0.02, (255, 140, 150), "SmoothPlastic", frame_normal(n))
    # moustache: a puffy middle and two curls
    pm, nm = on_ell_R(c, size, I3, Rx(-2) @ V(0, 0, -1))
    brown = (98, 64, 40)
    m.ell("PicklesMustache", (0.62, 0.3, 0.3), pm + V(0, 0.02, -0.08), brown)
    for sx in (-1, 1):
        m.seg("PicklesMustache", pm + V(sx * 0.12, 0.0, -0.08), pm + V(sx * 0.62, -0.04, 0.04), 0.15, brown, r2=0.15, bulge=0.4)
        m.ball("PicklesMustache", 0.2, pm + V(sx * 0.66, 0.1, 0.06), brown)
    ps, ns = on_ell_R(c, size, I3, Rx(-9) @ V(0, 0, -1))
    s0 = len(m.parts)
    m.mouth(ps, ns, 0.52, "cheerful", skin=G)
    name_all(m, "PicklesSmile", s0)
    # bow tie and apron
    pb, nb = on_ell_R(c, size, I3, Rx(-17) @ V(0, 0, -1))
    red = (214, 52, 60)
    m.ball("PicklesTrim", 0.2, pb + nb * 0.06, red)
    for sx in (-1, 1):
        m.add("E", "PicklesTrim", (0.4, 0.3, 0.14), pb + nb * 0.04 + V(sx * 0.22, 0, 0), red, "SmoothPlastic", frame_normal(nb) @ Rz(sx * 12))
    pa, na = on_ell_R(c, size, I3, Rx(-30) @ V(0, 0, -1))
    m.add("E", "PicklesApron", (2.1, 1.7, 0.42), pa + na * 0.02 + V(0, -0.1, 0.12), (248, 248, 250), "Fabric", frame_normal(na))
    m.add("B", "PicklesApron", (0.62, 0.36, 0.06), pa + na * 0.2 + V(0, -0.34, 0), (230, 232, 238), "Fabric", frame_normal(na))
    m.add("B", "PicklesApron", (0.62, 0.05, 0.065), pa + na * 0.205 + V(0, -0.17, 0), red, "Fabric", frame_normal(na))
    for sx in (-1, 1):
        a, _ = on_ell_R(c, size, I3, Ry(sx * 24) @ Rx(-12) @ V(0, 0, -1))
        b, _ = on_ell_R(c, size, I3, Ry(sx * 60) @ Rx(10) @ V(0, 0, -1))
        m.rod("PicklesApron", a, b, 0.14, (248, 248, 250), "Fabric")
    # straw boater, tipped a little
    with m.group(R=Rz(-7) @ Rx(-4), t=(0.05, 6.72, 0.08)):
        straw = (232, 204, 128)
        m.cyl("PicklesHat", 0.12, 2.3, (0, 0, 0), straw, "y", "Fabric")
        m.cyl("PicklesHat", 0.62, 1.48, (0, 0.34, 0), straw, "y", "Fabric")
        m.cyl("PicklesHat", 0.06, 1.38, (0, 0.66, 0), shade(straw, 1.1), "y", "Fabric")
        m.cyl("PicklesHatBand", 0.2, 1.52, (0, 0.14, 0), red, "y", "Fabric")
    # arms: one rod each, the hand ball last (RoomLife finds the shoulder from the arm and hand)
    for sx in (-1, 1):
        sh = V(sx * 1.08, 5.05, -0.5)
        hand = V(sx * 1.52, 4.68, -2.0)
        m.ell("PicklesHand", (0.28, 0.2, 0.36), hand + V(-sx * 0.3, 0.06, -0.05), G_L)
        m.ell("PicklesHand", (0.62, 0.44, 0.62), hand, G)
        m.rod("PicklesArm", sh, hand, 0.44, G)
    return m


def register():
    """A candy-coloured cash register (on the counter top, y = 0, facing -z): rounded mint body
    with gold trim, a sloped key deck with round keys, a pop-up price window, a drawer full of
    coins and a crank."""
    m = SModel("register", "room")
    mint, mint_d, cream = (92, 196, 176), (58, 150, 136), (252, 244, 222)
    m.rbox("Register", (2.0, 1.0, 1.4), (0, 1.0, 0.05), mint, 0.22, edge_name="RegisterBody")
    m.rbox("RegisterBody", (2.2, 0.5, 1.8), (0, 0.27, 0), mint_d, 0.2)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.ball("RegisterBody", 0.22, (sx * 0.95, 0.06, sz * 0.75), BRASS, "Metal")
    m.rod("RegisterBody", (-1.1, 0.53, -0.9), (1.1, 0.53, -0.9), 0.08, BRASS, "Metal")
    # the drawer: a front with a handle, and inside it a coin tray that shows when it pops out
    m.rbox("RegisterDrawer", (1.9, 0.36, 0.1), (0, 0.27, -0.92), cream, 0.12, axis="z")
    m.rod("RegisterDrawer", (-0.35, 0.27, -1.02), (0.35, 0.27, -1.02), 0.1, BRASS, "Metal")
    m.blk("RegisterDrawer", (1.76, 0.26, 1.2), (0, 0.27, -0.28), (110, 76, 50), "Wood")
    for (x, z) in ((-0.55, -0.62), (-0.2, -0.55), (0.25, -0.62), (0.6, -0.5)):
        disc(m, "RegisterDrawer", (x, 0.42, z), 0.3, 0.05, BRASS, normal=(0, 1, 0), mat="Metal")
    # key deck: a slope with two rows of round keys
    m.wedge("RegisterBody", (1.8, 0.42, 0.7), (0, 1.66, -0.32), mint)
    for row, (y, z) in enumerate(((1.6, -0.52), (1.76, -0.24))):
        for k in range(3):
            x = (k - 1) * 0.5
            disc(m, "RegisterKey", (x, y + 0.06, z), 0.3, 0.12, cream if (k + row) % 2 else (255, 214, 120),
                 normal=norm(V(0, 1, -0.6)))
    # price window
    m.rbox("RegisterScreen", (1.3, 0.62, 0.34), (0, 2.12, 0.42), mint_d, 0.14, axis="z")
    m.blk("RegisterDigits", (1.04, 0.32, 0.04), (0, 2.14, 0.24), (110, 255, 160), "Neon")
    m.rod("RegisterBody", (-0.66, 2.46, 0.42), (0.66, 2.46, 0.42), 0.1, BRASS, "Metal")
    # crank on the right side
    m.rod("RegisterBody", (1.1, 1.0, 0.1), (1.32, 1.0, 0.1), 0.14, BRASS, "Metal")
    m.rod("RegisterBody", (1.32, 1.0, 0.1), (1.32, 0.56, 0.1), 0.1, BRASS, "Metal")
    m.ball("RegisterBody", 0.24, (1.38, 0.56, 0.1), (220, 60, 60))
    return m


def counter():
    """The shop counter (on the floor, facing -z): a dark plinth, warm wood body with raised panels
    and gold-capped corner posts, a candy-stripe band, and a thick marble top with a rounded front."""
    m = SModel("counter", "room")
    wood, wood_d, wood_l = (190, 130, 85), (120, 78, 48), (206, 150, 102)
    m.rbox("CounterBase", (12.3, 0.4, 3.1), (0, 0.2, 0), (70, 46, 30), 0.16, "Wood")
    m.blk("Counter", (12.0, 3.4, 2.9), (0, 2.1, 0), wood, "WoodPlanks")
    for i in range(4):
        x = -4.4 + i * 2.95
        m.blk("CounterPanel", (2.5, 2.4, 0.1), (x, 2.0, -1.48), wood_d, "Wood")
        m.rbox("CounterPanel", (2.06, 1.96, 0.12), (x, 2.0, -1.5), wood_l, 0.16, "Wood", axis="z")
        m.add("B", "CounterPanel", (0.42, 0.42, 0.06), (x, 2.0, -1.58), GOLD_M, "Metal", Rz(45))
    for k in range(24):
        x = -5.75 + k * 0.5
        m.blk("CounterTrim", (0.5, 0.3, 0.06), (x, 3.62, -1.47), (226, 64, 70) if k % 2 == 0 else (252, 246, 236))
    for sx in (-1, 1):
        m.cyl("CounterTrim", 3.4, 0.56, (sx * 5.95, 2.1, -1.42), wood_d, "y", "Wood")
        m.ball("CounterTrim", 0.62, (sx * 5.95, 3.86, -1.42), GOLD_M, "Metal")
        m.cyl("CounterTrim", 0.3, 0.7, (sx * 5.95, 0.55, -1.42), wood_d, "y", "Wood")
    m.rbox("CounterTop", (12.6, 0.4, 3.4), (0, 4.2, 0), (242, 240, 236), 0.2, "Marble", axis="x")
    m.rod("CounterTrim", (-6.2, 3.96, -1.66), (6.2, 3.96, -1.66), 0.1, BRASS, "Metal")
    return m


def pack_display():
    m = SModel("pack_display", "room")
    m.rbox("PackDisplay", (3.0, 0.24, 1.4), (0, 0.12, 0), (240, 200, 90), 0.12, "Metal")
    m.rbox("PackDisplay", (2.7, 0.1, 1.1), (0, 0.29, 0), (255, 226, 140), 0.1, "Metal")
    return m


def display_pack(color):
    """A booster pack standing in the counter display (its middle at y = 0, facing -z)."""
    m = SModel("display_pack", "room")
    m.blk("DisplayPack", (0.8, 1.1, 0.12), (0, 0, 0), color)
    for y in (0.6, -0.6):
        m.blk("DisplayPackTrim", (0.84, 0.12, 0.08), (0, y, 0), (220, 224, 232), "Foil")
    disc(m, "DisplayPackTrim", (0, 0.08, -0.07), 0.44, 0.03, (255, 250, 236))
    m.add("B", "DisplayPackTrim", (0.18, 0.18, 0.03), (0, 0.08, -0.09), shade(color, 0.75), "SmoothPlastic", Rz(45))
    return m


def candy_jar(candy):
    """A glass candy jar (on the shelf, y = 0) full of round sweets, with a coloured lid and knob."""
    m = SModel("candy_jar", "room")
    m.cyl("Jar", 0.92, 0.84, (0, 0.5, 0), (214, 236, 255), "y", "Glass", tr=0.4, refl=0.1)
    m.cyl("JarLid", 0.08, 0.9, (0, 0.06, 0), (200, 226, 250), "y", "Glass", tr=0.3)
    import random
    rnd = random.Random(int(sum(candy)))
    cols = [candy, shade(candy, 1.35), (255, 255, 255), shade(candy, 0.75)]
    k = 0
    for layer, y in enumerate((0.26, 0.56)):
        for j in range(4 if layer < 1 else 3):
            a = math.radians(j * 90 + layer * 45 + rnd.uniform(-15, 15))
            r = 0.2 if layer < 2 else 0.14
            m.ball("JarCandy", 0.28, (math.cos(a) * r, y, math.sin(a) * r), cols[k % 4])
            k += 1
    m.cyl("JarLid", 0.16, 0.96, (0, 1.02, 0), shade(candy, 0.85), "y")
    m.cyl("JarLid", 0.06, 0.98, (0, 0.95, 0), (250, 246, 236), "y")
    m.ball("JarLid", 0.26, (0, 1.16, 0), shade(candy, 1.2))
    return m


def pack_box(color):
    """A booster box on the back shelf (y = 0 its bottom, facing -z): a lid band, a window with
    packs peeking out, a gold star sticker."""
    m = SModel("pack_box", "room")
    m.blk("PackBox", (0.9, 1.3, 0.9), (0, 0.65, 0), color, "Cardboard")
    m.blk("PackBoxTrim", (0.94, 0.24, 0.94), (0, 1.2, 0), shade(color, 0.72), "Cardboard")
    m.blk("PackBoxTrim", (0.62, 0.44, 0.04), (0, 0.72, -0.46), (40, 34, 52))
    for k, c in enumerate(((255, 226, 110), (130, 220, 255), (255, 140, 200))):
        m.blk("PackBoxTrim", (0.16, 0.36, 0.03), ((k - 1) * 0.19, 0.7, -0.48), c)
    disc(m, "PackBoxTrim", (0.27, 0.32, -0.465), 0.24, 0.03, GOLD_M, mat="Metal")
    return m


# ------------------------------------------------------------------------------------------------
# Deck Shelf
# ------------------------------------------------------------------------------------------------
def binder(color):
    """A ring binder standing on the shelf (y = 0 its bottom), spine facing -z: a thicker cover
    on the spine, a label with a stripe, a metal finger hole."""
    m = SModel("binder", "room")
    m.blk("Binder", (1.12, 2.24, 1.8), (0, 1.12, 0.04), color)
    m.blk("BinderLabel", (1.16, 2.3, 0.14), (0, 1.15, -0.86), shade(color, 0.86))
    m.blk("BinderLabel", (0.7, 0.86, 0.04), (0, 1.32, -0.95), (250, 246, 232))
    m.blk("BinderLabel", (0.56, 0.14, 0.02), (0, 1.5, -0.975), shade(color, 0.9))
    m.blk("BinderLabel", (0.46, 0.06, 0.02), (0, 1.28, -0.975), (120, 110, 100))
    m.blk("BinderLabel", (0.46, 0.06, 0.02), (0, 1.14, -0.975), (120, 110, 100))
    disc(m, "BinderRing", (0, 0.42, -0.94), 0.34, 0.04, (196, 200, 210), mat="Metal")
    disc(m, "BinderRing", (0, 0.42, -0.96), 0.2, 0.03, (40, 36, 44))
    return m


def card_box(color):
    """A cardboard box of cards (y = 0 its bottom, facing -z): a lid, a label, cards sticking out."""
    m = SModel("card_box", "room")
    m.blk("CardBox", (1.8, 1.0, 1.8), (0, 0.5, 0), color, "Cardboard")
    m.blk("CardBoxTrim", (1.88, 0.3, 1.88), (0, 1.05, 0), shade(color, 0.78), "Cardboard")
    m.blk("CardBoxTrim", (0.9, 0.44, 0.04), (0, 0.5, -0.91), (250, 244, 228))
    m.blk("CardBoxTrim", (0.6, 0.1, 0.02), (0, 0.58, -0.94), shade(color, 0.7))
    for k, (x, a) in enumerate(((-0.3, -8), (0.05, 6), (0.32, -4))):
        m.add("B", "CardBoxTrim", (0.6, 0.86, 0.04), (x, 1.32, 0.1 + k * 0.08), (255, 252, 244) if k != 1 else (255, 214, 110),
              "SmoothPlastic", Rz(a))
    return m


def shelf_frame():
    """Rounded edges and trim for the Deck Shelf (built in room coordinates)."""
    m = SModel("shelf_frame", "room")
    wood, dark = (120, 78, 48), (95, 62, 38)
    for y in (0.35, 3.35, 6.35, 9.35):
        m.rod("ShelfTrim", (-21.05, y, -6.9), (-21.05, y, 6.9), 0.34, (150, 100, 62), "Wood")
    for z in (-7.1, 7.1):
        m.rod("ShelfTrim", (-21.0, 0.0, z), (-21.0, 12.4, z), 0.5, wood, "Wood")
        m.rbox("ShelfTrim", (3.0, 0.5, 0.7), (-22.4, 0.25, z), dark, 0.16, "Wood")
    m.rod("ShelfTrim", (-20.62, 12.66, -7.8), (-20.62, 12.66, 7.8), 0.42, dark, "Wood")
    m.rod("ShelfTrim", (-20.5, 13.08, -7.82), (-20.5, 13.08, 7.82), 0.22, BRASS, "Metal")
    return m


# ------------------------------------------------------------------------------------------------
# Fireplace, mantel and lamps (room coordinates)
# ------------------------------------------------------------------------------------------------
def fireplace():
    """Stone-capped brick pillars, a lintel with a keystone, a hearth with a rounded front, chunky
    logs with pale cut ends on andirons, and a mantel with corbels."""
    m = SModel("fireplace", "room")
    brick, stone, stone_d = (165, 72, 55), (170, 164, 160), (128, 122, 120)
    m.blk("Hearth", (10.5, 0.4, 2.8), (0, 0.2, -22.6), (95, 90, 92), "Slate")
    m.rod("FireFloor", (-5.25, 0.2, -21.2), (5.25, 0.2, -21.2), 0.4, (110, 105, 108), "Slate")
    m.blk("FireFloor", (5.4, 0.2, 1.4), (0, 0.5, -23.1), (30, 22, 20), "Slate")
    m.blk("FireBack", (5.4, 5.4, 0.4), (0, 2.7, -23.8), (40, 28, 26), "Slate")
    for sx in (-1, 1):
        x = sx * 3.7
        m.blk("FirePillar", (2.0, 6.0, 1.6), (x, 3.6, -23.2), brick, "Brick")
        m.rbox("FirePillar", (2.4, 0.6, 1.9), (x, 0.7, -23.05), stone, 0.16, "Slate")
        m.rbox("FirePillar", (2.4, 0.4, 1.9), (x, 5.2, -23.05), stone, 0.16, "Slate")
        for k in range(3):
            m.blk("FirePillar", (2.04, 0.08, 1.64), (x, 1.9 + k * 1.1, -23.2), (196, 176, 160), "Slate")
    m.blk("FireLintel", (9.4, 1.6, 1.6), (0, 6.2, -23.2), brick, "Brick")
    m.rbox("FireLintel", (5.6, 0.36, 1.7), (0, 5.55, -23.15), stone, 0.14, "Slate")
    m.add("B", "FireLintel", (0.9, 1.1, 1.76), (0, 5.95, -23.12), stone_d, "Slate")
    m.wedge("FireLintel", (1.7, 0.7, 0.7), (-2.35, 5.03, -23.2), stone, "Slate", R=Ry(90) @ Rx(180))
    m.wedge("FireLintel", (1.7, 0.7, 0.7), (2.35, 5.03, -23.2), stone, "Slate", R=Ry(-90) @ Rx(180))
    # andirons
    for x in (-1.5, 1.5):
        m.blk("GrateBar", (0.14, 0.9, 0.14), (x, 1.05, -22.55), (44, 42, 48), "Metal")
        m.ball("GrateBar", 0.32, (x, 1.56, -22.55), BRASS, "Metal")
        m.rod("GrateBar", (x, 0.66, -22.55), (x, 0.66, -23.4), 0.14, (44, 42, 48), "Metal")
    m.rod("Grate", (-1.8, 0.75, -22.6), (1.8, 0.75, -22.6), 0.16, (44, 42, 48), "Metal")
    # logs: bark, pale cut ends, a stub
    bark = (98, 62, 38)
    for (a, b, d) in (((-1.7, 0.95, -23.1), (1.7, 0.95, -23.1), 0.68), ((-1.4, 1.5, -23.55), (1.6, 1.4, -22.95), 0.62),
                      ((-1.4, 1.35, -22.75), (1.2, 1.55, -23.45), 0.56)):
        a, b = V(*a), V(*b)
        m.rod("Log", a, b, d, bark, "Wood")
        for e, o in ((a, -1), (b, 1)):
            v = norm(b - a) * o
            disc(m, "Log", e + v * 0.02, d * 0.88, 0.05, (222, 186, 132), normal=v, mat="Wood")
            disc(m, "Log", e + v * 0.05, d * 0.4, 0.02, (196, 150, 98), normal=v, mat="Wood")
    m.rod("Log", (0.4, 1.12, -22.8), (0.62, 1.45, -22.6), 0.2, bark, "Wood")
    m.ell("Embers", (3.6, 0.4, 1.0), (0, 0.65, -23.1), (255, 110, 30), "Neon")
    # mantel: a thick shelf with a rounded front, a cove under it and two corbels
    m.blk("Mantle", (10.4, 0.55, 2.1), (0, 7.3, -22.95), (100, 64, 40), "Wood")
    m.rod("Mantle", (-5.2, 7.3, -21.9), (5.2, 7.3, -21.9), 0.55, (100, 64, 40), "Wood")
    m.blk("MantleTrim", (10.0, 0.3, 1.8), (0, 6.95, -23.05), (80, 50, 32), "Wood")
    m.rod("MantleTrim", (-5.0, 6.92, -22.15), (5.0, 6.92, -22.15), 0.3, (80, 50, 32), "Wood")
    for x in (-4.4, 4.4):
        m.ell("MantleTrim", (0.6, 1.1, 0.9), (x, 6.5, -22.45), (88, 56, 36), "Wood")
        m.ball("MantleTrim", 0.3, (x, 6.06, -22.3), BRASS, "Metal")
    return m


def candlestick():
    """A brass candlestick with a dripping candle (on the mantel, y = 0, facing -z)."""
    m = SModel("candlestick", "room")
    m.cyl("CandleHolder", 0.1, 0.78, (0, 0.05, 0), BRASS, "y", "Metal")
    m.ball("CandleHolder", 0.24, (0, 0.18, 0), BRASS, "Metal")
    m.cyl("CandleHolder", 0.26, 0.16, (0, 0.33, 0), BRASS, "y", "Metal")
    m.cyl("CandleHolder", 0.14, 0.46, (0, 0.48, 0), BRASS, "y", "Metal")
    arc_rods(m, "CandleHolder", (0.36, 0.3, 0), 0.14, 100, -100, 3, 0.07, BRASS, mat="Metal")
    m.cyl("Candle", 0.86, 0.34, (0, 0.98, 0), (250, 240, 222), "y")
    m.ell("CandleHolder", (0.4, 0.14, 0.4), (0, 1.4, 0), (252, 246, 232))
    for (a, L) in ((20, 0.34), (150, 0.22), (260, 0.28)):
        t = math.radians(a)
        m.ell("CandleHolder", (0.1, L, 0.1), (math.sin(t) * 0.17, 1.38 - L / 2, -math.cos(t) * 0.17), (252, 246, 232))
    m.cyl("CandleHolder", 0.1, 0.03, (0, 1.48, 0), (40, 30, 30), "y")
    m.ell("Flame", (0.22, 0.4, 0.22), (0, 1.66, 0), (255, 196, 84), "Neon")
    return m


def mantel_clock():
    """A small arched mantel clock facing +z... built facing -z on y = 0 (turned at placement)."""
    m = SModel("mantel_clock", "room")
    m.rbox("Clock", (1.3, 1.0, 0.7), (0, 0.62, 0), WALNUT, 0.14, "Wood", edge_name="ClockTrim")
    m.cyl("ClockTrim", 0.7, 1.3, (0, 1.12, 0), WALNUT, "z", "Wood")
    m.rbox("ClockTrim", (1.5, 0.14, 0.86), (0, 0.17, 0), WALNUT_DK, 0.1, "Wood")
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.ball("ClockTrim", 0.2, (sx * 0.6, 0.06, sz * 0.32), BRASS, "Metal")
    m.ball("ClockTrim", 0.24, (0, 1.82, 0), BRASS, "Metal")
    disc(m, "ClockTrim", (0, 0.98, -0.37), 1.08, 0.06, BRASS, mat="Metal")
    disc(m, "ClockFace", (0, 0.98, -0.41), 0.9, 0.04, (252, 244, 222))
    for k in range(12):
        a = math.radians(k * 30)
        L = 0.1 if k % 3 == 0 else 0.05
        m.add("B", "ClockTrim", (0.04 if k % 3 else 0.06, L, 0.02), (math.sin(a) * 0.36, 0.98 + math.cos(a) * 0.36, -0.44),
              (60, 44, 34), "SmoothPlastic", Rz(-k * 30))
    # hands: the short upright one points at 12, the long flat one at 3 (RoomLife turns them to your time)
    m.blk("ClockHand", (0.07, 0.3, 0.03), (0, 0.98 + 0.13, -0.45), (40, 30, 30))
    m.blk("ClockHand", (0.38, 0.05, 0.03), (-0.17, 0.98, -0.47), (40, 30, 30))
    m.ball("ClockTrim", 0.1, (0, 0.98, -0.47), BRASS, "Metal")
    return m


def pendant_lamp():
    """A hanging drum lamp (built around the bulb's height = 0): brass canopy and cap, cream drum
    shade with maroon trim and a little fringe, glowing bulb."""
    m = SModel("pendant_lamp", "room")
    shade_c, trim = (238, 212, 160), (150, 52, 52)
    m.cyl("LampCord", 2.6, 0.08, (0, 2.85, 0), (40, 36, 36), "y")
    m.cyl("LampCord", 0.12, 0.62, (0, 4.1, 0), BRASS, "y", "Metal")
    m.ell("LampShadeTop", (0.66, 0.36, 0.66), (0, 1.5, 0), BRASS, "Metal")
    m.cyl("LampShadeTop", 0.24, 0.26, (0, 1.66, 0), BRASS, "y", "Metal")
    m.cyl("LampShade", 1.2, 2.5, (0, 0.6, 0), shade_c, "y", "Fabric")
    m.cyl("LampShadeTop", 0.12, 2.58, (0, 1.2, 0), trim, "y", "Fabric")
    m.cyl("LampShadeTop", 0.12, 2.58, (0, 0.0, 0), trim, "y", "Fabric")
    m.cyl("LampShadeTop", 0.06, 1.7, (0, 1.28, 0), shade(shade_c, 0.9), "y", "Fabric")
    for k in range(12):
        a = math.radians(k * 30 + 15)
        m.ell("LampShadeTop", (0.2, 0.26, 0.2), (math.sin(a) * 1.22, -0.14, math.cos(a) * 1.22), trim, "Fabric")
    m.ball("LampBulb", 0.64, (0, 0.05, 0), (255, 225, 170), "Neon")
    return m


def plant(seed):
    """A potted plant (on the floor, y = 0): tapered terracotta pot with a painted band and a
    thick rim, dark soil with pebbles, a rosette of glossy leaves around a curled sprout."""
    import random
    rnd = random.Random(seed)
    m = SModel("plant", "room")
    terra, terra_d = (204, 110, 66), (170, 88, 52)
    m.cyl("Pot", 1.2, 1.5, (0, 0.72, 0), terra, "y")
    m.cyl("PotRim", 0.5, 1.72, (0, 1.38, 0), terra, "y")
    m.cyl("PotRim", 0.2, 1.32, (0, 0.1, 0), terra_d, "y")
    m.cyl("PotRim", 0.16, 1.54, (0, 0.96, 0), (246, 226, 190), "y")
    m.cyl("PotRim", 0.32, 2.04, (0, 1.72, 0), terra_d, "y")
    m.cyl("Soil", 0.06, 1.86, (0, 1.86, 0), (78, 54, 34), "y")
    for k in range(3):
        a = rnd.uniform(0, 6.28)
        m.ball("Soil", 0.16, (math.cos(a) * 0.62, 1.9, math.sin(a) * 0.62), (186, 180, 170))
    greens = [(62, 150, 76), (80, 172, 88), (54, 132, 70)]
    n = 7
    for k in range(n):
        a = math.radians(k * 360 / n + rnd.uniform(-12, 12))
        out = rnd.uniform(26, 44)
        d = Ry(math.degrees(a)) @ Rz(0) @ V(0, math.cos(math.radians(out)), 0) + V(math.sin(a), 0, math.cos(a)) * math.sin(math.radians(out))
        L = rnd.uniform(1.9, 2.5)
        leaf(m, "Leaf", (math.sin(a) * 0.18, 1.86, math.cos(a) * 0.18), d, L, rnd.uniform(0.8, 1.0), greens[k % 3], curl=rnd.uniform(-20, 20))
    leaf(m, "LeafTop", (0, 1.86, 0), (0.05, 1, 0.02), 1.5, 0.62, (110, 190, 98))
    return m


# ------------------------------------------------------------------------------------------------
# Front door and the painting (room coordinates)
# ------------------------------------------------------------------------------------------------
def door():
    """The front door (to the Park) facing -z: raised panels, a middle rail, a brass kick plate,
    knob and rose, hinges, and a chunky casing with corner blocks."""
    m = SModel("door", "room")
    wood, panel, panel_l, dark = (125, 80, 48), (110, 70, 42), (140, 92, 56), (90, 58, 36)
    m.blk("Door", (5.8, 11.2, 0.4), (-14.0, 5.6, 23.75), wood, "Wood")
    zf = 23.55
    for x in (-15.3, -12.7):
        for y in (8.3, 3.2):
            m.blk("DoorPanel", (2.1, 3.9, 0.08), (x, y, zf - 0.04), panel, "Wood")
            m.rbox("DoorPanel", (1.6, 3.4, 0.08), (x, y, zf - 0.09), panel_l, 0.18, "Wood", axis="z")
    m.blk("DoorPanel", (5.8, 0.5, 0.08), (-14.0, 5.75, zf - 0.04), dark, "Wood")
    m.blk("DoorKnobPlate", (5.2, 0.7, 0.05), (-14.0, 0.62, zf - 0.03), BRASS, "Metal")
    for y in (2.0, 9.2):
        m.blk("DoorKnobPlate", (0.5, 0.9, 0.08), (-16.75, y, zf - 0.04), (50, 46, 52), "Metal")
    m.rbox("DoorKnobPlate", (0.5, 1.3, 0.06), (-11.8, 5.25, zf - 0.03), BRASS, 0.2, "Metal", axis="z")
    m.ell("DoorKnobPlate", (0.1, 0.22, 0.03), (-11.8, 4.86, zf - 0.07), (40, 34, 30))
    m.cyl("DoorKnob", 0.24, 0.18, (-11.8, 5.45, zf - 0.15), BRASS, "z", "Metal")
    m.ball("DoorKnob", 0.56, (-11.8, 5.45, zf - 0.36), BRASS, "Metal")
    # casing
    m.blk("DoorFrameL", (0.6, 11.6, 0.8), (-17.2, 5.8, 23.7), dark, "Wood")
    m.blk("DoorFrameR", (0.6, 11.6, 0.8), (-10.8, 5.8, 23.7), dark, "Wood")
    m.blk("DoorFrameTop", (7.0, 0.7, 0.8), (-14.0, 11.6, 23.7), dark, "Wood")
    for x in (-17.2, -10.8):
        m.rod("DoorFrameTop", (x, 0.0, 23.3), (x, 11.3, 23.3), 0.3, shade(dark, 1.15), "Wood")
        m.rbox("DoorFrameTop", (0.9, 0.9, 0.3), (x, 11.6, 23.24), shade(dark, 1.1), 0.12, "Wood", axis="z")
        m.ell("DoorFrameTop", (0.5, 0.5, 0.12), (x, 11.6, 23.08), BRASS, "Metal")
        m.rbox("DoorFrameTop", (0.86, 0.7, 0.96), (x, 0.35, 23.66), shade(dark, 0.85), 0.12, "Wood")
    m.rod("DoorFrameTop", (-17.4, 12.06, 23.3), (-10.6, 12.06, 23.3), 0.36, shade(dark, 1.15), "Wood")
    # door mat: a round-cornered mat with a border
    m.rbox("DoorMat", (6.0, 0.1, 3.0), (-14.0, 0.06, 21.8), (150, 104, 64), 0.4, "Fabric")
    m.rbox("DoorMat", (5.2, 0.12, 2.2), (-14.0, 0.07, 21.8), (182, 136, 86), 0.3, "Fabric")
    return m


def painting_frame():
    """A chunky gilded frame round the Campaign painting (facing +z), plus clouds, a road, trees
    and castle details in the picture."""
    m = SModel("painting", "room")
    gold, gold_d = (222, 176, 76), (180, 136, 56)
    m.blk("PaintingFrame", (5.4, 3.8, 0.3), (0, 11.2, -22.75), (200, 160, 70), "Metal")
    z = -22.5
    for (a, b) in (((-2.55, 9.45), (2.55, 9.45)), ((-2.55, 12.95), (2.55, 12.95)), ((-2.55, 9.45), (-2.55, 12.95)), ((2.55, 9.45), (2.55, 12.95))):
        m.rod("PaintingTrim", (a[0], a[1], z), (b[0], b[1], z), 0.34, gold, "Metal")
    for x in (-2.55, 2.55):
        for y in (9.45, 12.95):
            m.ball("PaintingTrim", 0.52, (x, y, z), gold_d, "Metal")
            m.ball("PaintingTrim", 0.24, (x, y, z + 0.22), (230, 70, 80), "Metal")
    m.ell("PaintingTrim", (1.3, 0.62, 0.3), (0, 13.18, z + 0.02), gold, "Metal")
    m.ball("PaintingTrim", 0.34, (0, 13.3, z + 0.18), (90, 170, 255), "Metal")
    m.rbox("PaintingTrim", (1.3, 0.3, 0.06), (0, 9.42, z + 0.2), gold_d, 0.1, "Metal", axis="z")
    # picture details (on top of the old sky, hills, sun, castle and tower)
    for (x, y, w) in ((-1.6, 12.4, 1.1), (0.4, 12.55, 0.8)):
        m.ell("PaintingDetail", (w, w * 0.34, 0.04), (x, y, -22.56), (250, 250, 255))
        m.ell("PaintingDetail", (w * 0.6, w * 0.3, 0.04), (x + w * 0.3, y + 0.1, -22.555), (250, 250, 255))
    m.ell("PaintingDetail", (1.6, 0.24, 0.03), (0.3, 9.75, -22.53), (226, 200, 140), R=Rz(-12))
    for (x, y) in ((1.9, 10.2), (2.15, 10.05), (-2.0, 10.15)):
        m.ell("PaintingDetail", (0.3, 0.42, 0.03), (x, y, -22.53), (50, 110, 60))
    for k in range(3):
        m.blk("PaintingDetail", (0.12, 0.12, 0.04), (-1.32 + k * 0.22, 11.11, -22.5), (230, 230, 240))
    m.blk("PaintingDetail", (0.16, 0.24, 0.03), (-1.1, 10.5, -22.48), (90, 70, 80))
    m.wedge("PaintingDetail", (0.02, 0.18, 0.28), (-1.16, 11.55, -22.5), (230, 70, 80), R=Ry(90))
    m.blk("PaintingDetail", (0.03, 0.3, 0.03), (-1.3, 11.5, -22.5), (90, 70, 80))
    return m


# ------------------------------------------------------------------------------------------------
# Building the room
# ------------------------------------------------------------------------------------------------
def build(room):
    PP, SH, TW, DS, ST = "Stations/PackParty", "Stations/ShopCounter", "Stations/TrophyWall", "Stations/DeckShelf", "Structure"
    # Pack Party speakers and balloons
    spk = (((10.4, 0, -22.3), 180), ((22.3, 0, -10.4), 90))
    t = room.take(PP, ["Speaker", "SpeakerCone", "SpeakerDust", "SpeakerTrim"], near=[(p[0], 2.2, p[2]) for p, _ in spk], radius=3.0)
    for (pos, yaw) in spk:
        room.put(PP, speaker(), pos, yaw, t)
    balloons = [((10.8, 8.6, -21.8), (255, 80, 120), 3.9), ((11.8, 9.4, -22.6), (90, 170, 255), 4.7),
                ((22.4, 9.0, -11.6), (255, 220, 60), 4.3), ((21.6, 8.2, -10.6), (150, 230, 110), 3.5),
                ((12.6, 10.2, -23.0), (200, 120, 255), 5.5)]
    t = room.take(PP, ["Balloon", "BalloonKnot", "BalloonString"], box=((10, 2, -23.6), (23, 11.2, -10)))
    for (c, col, L) in balloons:
        m = balloon(col)
        balloon_string(m, -0.9, L * 0.98)
        room.put(PP, m, c, 0, t)

    # radio corner
    t = room.take("Stations/Radio", ["SideTable", "SideTableLeg", "SideTableShelf"], near=[(-17, 1.5, -18)], radius=4.0)
    room.put("Stations/Radio", side_table(), (-17, 0, -18), 180, t)
    t = room.take("Stations/Radio", ["RadioBox", "RadioTop", "RadioGrille", "RadioDial", "RadioNeedle", "RadioKnob", "RadioAntenna",
                                     "RadioAntennaTip", "MusicNote", "MusicNoteHead"], near=[(-17, 5.0, -18)], radius=4.5)
    room.put("Stations/Radio", radio(), (-17, 3.18, -18), 180, t)

    # Trophy Wall: trophies on the two shelves, pennants, certificates
    cups = [((22.5, 5.55, -4.2), GOLD_M), ((22.5, 5.55, 0.0), SILVER_M), ((22.5, 5.55, 4.2), BRONZE_M),
            ((22.5, 9.55, -3.2), SILVER_M), ((22.5, 9.55, 1.0), BRONZE_M), ((22.5, 9.55, 5.2), GOLD_M)]
    t = room.take(TW, ["TrophyCup", "TrophyRim", "TrophyStem", "TrophyHandle", "TrophyBase"], near=[(p[0], p[1] + 1.2, p[2]) for p, _ in cups], radius=1.9)
    for (pos, metal) in cups:
        room.put(TW, trophy(metal), pos, 90, t)
    flags = [(-5.6, (255, 90, 90)), (-2.8, (90, 170, 255)), (0.0, (255, 210, 60)), (2.8, (150, 230, 110)), (5.6, (200, 120, 255))]
    t = room.take(TW, ["Pennant", "PennantTrim"], near=[(23.25, 12.0, z) for z, _ in flags], radius=1.4)
    for (z, col) in flags:
        room.put(TW, pennant(col), (23.25, 12.72, z), 90, t)
    t = room.take(TW, ["Certificate", "Seal", "CertificateFrame"], near=[(23.28, 7.4, -5.5), (23.28, 7.4, 5.5)], radius=1.7)
    for z in (-5.5, 5.5):
        room.put(TW, certificate(), (23.27, 7.4, z), 90, t)

    # Shop: counter, display, Pickles, register, jars, booster boxes
    t = room.take(SH, ["Counter", "CounterPanel", "CounterTop", "CounterBase", "CounterTrim"], box=((8.4, -0.2, 12.8), (21.6, 4.5, 17.2)))
    room.put(SH, counter(), (15, 0, 15), 0, t)
    t = room.take(SH, ["PackDisplay"], box=((17.8, 4.3, 14.2), (21.2, 4.9, 15.8)))
    room.put(SH, pack_display(), (19.5, 4.4, 15.0), 0, t)
    packs = [((18.5, 14.98), -24, (255, 90, 90)), ((19.0, 14.88), -12, (90, 170, 255)), ((19.5, 14.8), 0, (255, 210, 60)),
             ((20.0, 14.72), 12, (150, 230, 110)), ((20.5, 14.62), 24, (200, 120, 255))]
    t = room.take(SH, ["DisplayPack", "DisplayPackTrim"], box=((17.6, 4.6, 14.2), (21.4, 6.2, 15.4)))
    for ((x, z), roll, col) in packs:
        R = Rz(roll)
        lift = 0.66 / math.cos(math.radians(roll)) + 0.4 * abs(math.sin(math.radians(roll))) * 0.6
        room.put(SH, display_pack(col), (x, 4.74 + lift, z), R=R, taken=t)
    t = room.take(SH, ["Pickles", "PickleBump", "PicklesApron", "PicklesHat", "PicklesHatBand", "PicklesMustache", "PicklesSmile", "PicklesEye",
                       "PicklesPupil", "PicklesArm", "PicklesHand", "PicklesBrow", "PicklesCheek", "PicklesTrim"], near=[(15, 5.2, 18.2)], radius=3.6)
    room.put(SH, pickles(), (15, 0, 18.4), 0, t)
    t = room.take(SH, ["Register", "RegisterScreen", "RegisterDigits", "RegisterKey", "RegisterDrawer", "RegisterBody"], near=[(10.5, 5.4, 15.0)], radius=2.3)
    room.put(SH, register(), (10.5, 4.4, 15.0), 0, t)
    jars = [(x, y) for y in (5.15, 8.15, 11.15) for x in (12.7, 16.15, 19.6)]
    candy = [(90, 170, 255), (200, 120, 255), (255, 120, 160), (120, 220, 140), (255, 200, 80), (255, 140, 90),
             (255, 110, 200), (110, 220, 240), (250, 90, 90)]
    t = room.take(SH, ["Jar", "JarCandy", "JarLid"], near=[(x, y + 0.5, 23.2) for x, y in jars], radius=0.9)
    for k, (x, y) in enumerate(jars):
        room.put(SH, candy_jar(candy[k]), (x, y, 23.2), 0, t)
    boxes = [(x, y) for y in (5.15, 8.15, 11.15) for x in (10.4, 11.55, 13.85, 15.0, 17.3, 18.45)]
    t = room.take(SH, ["PackBox", "PackBoxTrim"], near=[(x, y + 0.65, 23.2) for x, y in boxes], radius=0.8)
    for (x, y) in boxes:
        old = nearest(t, "PackBox", (x, y + 0.65, 23.2))
        room.put(SH, pack_box(color_of(old[2]) if old else (255, 150, 60)), (x, y, 23.2), 0, t)

    # Deck Shelf: binders, card boxes, rounded trim
    bpos = [(y, z) for y in (3.5, 6.5, 9.5) for z in (-5.75, -4.3, -2.7, -0.95, 0.5, 2.1, 3.85, 5.3)]
    t = room.take(DS, ["Binder", "BinderLabel", "BinderRing"], near=[(-22.35, y + 1.15, z) for y, z in bpos], radius=1.25)
    for (y, z) in bpos:
        old = nearest(t, "Binder", (-22.35, y + 1.15, z))
        room.put(DS, binder(color_of(old[2]) if old else (120, 200, 110)), (-22.35, y, z), -90, t)
    cpos = [((0.5, -5.0), False), ((1.7, -3.9), True), ((0.5, -0.6), False), ((1.7, 0.5), True), ((0.5, 3.8), True)]
    t = room.take(DS, ["CardBox", "CardBoxTrim"], near=[(-22.4, y + 0.6, z) for (y, z), _ in cpos], radius=1.1)
    for ((y, z), cards) in cpos:
        old = nearest(t, "CardBox", (-22.4, y + 0.6, z))
        m = card_box(color_of(old[2]) if old else (220, 80, 80))
        if not cards:
            m.parts = [p for p in m.parts if not (p["name"] == "CardBoxTrim" and p["pos"][1] > 1.2)]
        room.put(DS, m, (-22.4, y, z), -90, t)
    t = room.take(DS, ["ShelfTrim"], box=((-24, -1, -8.5), (-19.5, 14, 8.5)))
    room.put(DS, shelf_frame(), (0, 0, 0), 0, t)

    # fireplace and mantel
    t = room.take(ST, ["Hearth", "FireFloor", "FireBack", "FirePillar", "FireLintel", "GrateBar", "Grate", "Log", "Embers", "Mantle", "MantleTrim"],
                  box=((-6, -0.2, -24.3), (6, 7.8, -20.8)))
    room.put(ST, fireplace(), (0, 0, 0), 0, t)
    t = room.take(ST, ["Candle", "CandleHolder", "Flame"], near=[(-4.2, 8.2, -22.8), (4.2, 8.2, -22.8)], radius=1.3)
    for x in (-4.2, 4.2):
        room.put(ST, candlestick(), (x, 7.575, -22.7), 180, t)
    t = room.take(ST, ["Clock", "ClockFace", "ClockHand", "ClockTrim"], near=[(-2.2, 8.4, -22.8)], radius=1.6)
    room.put(ST, mantel_clock(), (-2.2, 7.575, -22.55), 180, t, scale=0.85)
    t = room.take(ST, ["TrophySmallCup", "TrophySmall", "TrophySmallBase"], near=[(2.3, 8.2, -22.8)], radius=1.2)
    room.put(ST, trophy(GOLD_M, 0.5, names=("TrophySmallCup", "TrophySmall", "TrophySmall", "TrophySmall", "TrophySmallBase")),
             (2.3, 7.575, -22.6), 180, t)

    # hanging lamps
    lamps = [(-12, -12), (12, 12), (-12, 12), (12, -12)]
    t = room.take(ST, ["LampShade", "LampShadeTop", "LampBulb", "LampCord"], near=[(x, 15.2, z) for x, z in lamps], radius=3.5)
    for (x, z) in lamps:
        room.put(ST, pendant_lamp(), (x, 13.85, z), 0, t)

    # potted plants (scale: the old pots were three sizes)
    pots = [((-21.5, 21.5), 1.1), ((21.8, 22.0), 1.0), ((-21.6, -21.4), 1.0), ((5.8, -22.2), 0.8), ((-5.8, -22.2), 0.8)]
    t = room.take(ST, ["Pot", "PotRim", "Soil", "Leaf", "LeafTop"], near=[(x, 1.5, z) for (x, z), _ in pots], radius=3.5)
    for k, ((x, z), s) in enumerate(pots):
        room.put(ST, plant(k + 3), (x, 0, z), k * 47, t, scale=s)

    # front door (HubRoom makes it the Park door) and the Campaign painting's frame
    t = room.take(ST, ["Door", "DoorPanel", "DoorKnob", "DoorKnobPlate", "DoorFrameL", "DoorFrameR", "DoorFrameTop", "DoorMat"],
                  box=((-18.2, -0.2, 20.0), (-9.8, 12.6, 24.4)))
    room.put(ST, door(), (0, 0, 0), 0, t)
    t = room.take(ST, ["PaintingFrame", "PaintingTrim", "PaintingDetail"], near=[(0, 11.2, -22.7)], radius=3.8)
    room.put(ST, painting_frame(), (0, 0, 0), 0, t)


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else ROOM
    out = sys.argv[2] if len(sys.argv) > 2 else path
    room = RoomFile(path)
    build(room)
    n = room.save(out)
    print(f"room: {room.made} new parts, {n} instances in all -> {out}")
