# Builds the park's part-made props in the chunky, rounded style of the remodelled cards and writes
# them to src/park/ParkPropData.luau:
#
#   shrine       the Enchanting Crystal on the island: a purple-pink faceted crystal with gold bands,
#                a crown of little crystals and two gold rings round it (all in the "Crystal" group,
#                which the client floats and turns), over a plum stone floor with a glowing magic
#                circle and crystal clusters growing out of the rim
#   altar        the Pull Altar: marble dais and steps with gold bands, a glowing ring with a gold star,
#                a reeded pedestal whose gold claws cradle the floating pack, crystal clusters
#   lantern      a little iron lantern: glass sides, a candle, a stepped cap and a ring on top
#   bollard, lanternpost   the iron posts the lanterns stand on
#   birdbath     a stone bird bath: a stepped foot, a baluster stem, a rimmed bowl, a robin on the rim
#   bin          a slatted green litter bin with iron hoops and a domed lid
#   topiary      a stone planter with a clipped box topiary (two leafy balls on a trunk)
#   cat          a ginger cat curled up asleep, its tail round its paws
#   logseat, firepit   the campfire's log benches, and its ring of stones and its log tepee
#   questhall    the Quest Hall on the north lawn: a timber-framed guild hall with a blue slate roof,
#                a porch, an arched door with a sunburst fanlight, banners, a cupola (the Beacon in
#                it), a chimney; inside Quill's counter, pigeonholes full of scrolls, a fireplace,
#                bookshelves, board frames, a chandelier; out front a forecourt with a compass rose,
#                an armillary sphere and a notice board
#   questowl     Quill, the owl who keeps the Quest Hall (his head turns, his eyes blink)
#
#     python3 gen_park.py
#
# ParkBuilder's propFrom(parent, id, cf, scale) builds a prop from this data; ParkBuilder adds the
# working pieces in code (the prompts, the lights, the crystal's PrimaryPart, the runes the client
# colours, the floating and fallen shards, the fire). Names the scripts look for stay: Base (the
# Enchant prompt), Core (in the Crystal group: the client colours it), Dais (the OpenPacks prompt),
# Crystal (the altar's lights), Lantern (the glass the client lights after dark), LogSeat, and in the
# Quest Hall Desk, Beacon, ChimneyTop, Firebox, ChandelierLight, DailyBoard, WeeklyBoard, JourneyBoard,
# NoticeBoard, Sign, Armillary (a group); in Quill: Head (a group), Neck, Lid.
import math
import sys
from contextlib import contextmanager

import numpy as np

from modelkit import Rx, Ry, Rz, I3, shade, frame_from_x, frame_normal, euler_xyz, r3
from stylekit import SModel, V, norm, INK, WHITE
from gen_room import arc_rods, rename

OUT = "src/park/ParkPropData.luau"
UP = V(0, 1, 0)
MATERIALS = {"SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Slate", "Metal", "Glass", "Grass", "Ground",
             "Fabric", "Concrete", "Pebble", "Rock"}


class PModel(SModel):
    """A park prop: parts can go in a group (a Model inside the prop) and be solid."""

    def __init__(self, mid):
        super().__init__(mid, "park")
        self.solid_names = set()

    @contextmanager
    def grouped(self, g):
        start = len(self.parts)
        yield
        for p in self.parts[start:]:
            p.setdefault("group", g)


def polar(a_deg, r, y=0.0):
    """Same as ParkBuilder's polar: angle from +z towards +x."""
    a = math.radians(a_deg)
    return V(math.sin(a) * r, y, math.cos(a) * r)


def tri(m, name, A, B, P, t, color, mat="SmoothPlastic", tr=0.0, refl=0.0, inside=(0, 0, 0)):
    """A flat triangle A-B-P, t thick, made of two wedges. Its outer face lies on the triangle's plane,
    on the side away from the point `inside`."""
    A, B, P = V(*A), V(*B), V(*P)
    u = norm(B - A)
    F = A + u * np.dot(P - A, u)  # the foot of P on A-B: both halves have their right angle there
    h = float(np.linalg.norm(P - F))
    yv = (P - F) / h
    n = np.cross(u, yv)
    if np.dot(n, (A + B + P) / 3 - V(*inside)) < 0:
        n = -n
    for E in (A, B):
        e = F - E
        L = float(np.linalg.norm(e))
        if L < 1e-4:
            continue
        zv = e / L  # a wedge is full height at +z: the right angle (F) is at the back
        xv = np.cross(yv, zv)
        R = np.column_stack([xv, yv, zv])
        m.add("W", name, (t, h, L), F + yv * h / 2 - zv * L / 2 - n * t / 2, color, mat, R, tr, refl)


def hex_crystal(m, c, R, body, top, bot, t, cols, tip_cols, bot_cols, mat="Glass", tr=0.3, tip_tr=0.22, refl=0.12,
                body_name="Shell", tip_name="Tip"):
    """A six-sided crystal with a point at both ends, out of thin glass facets round an empty middle
    (a glowing core inside shows through). c is the middle of the six-sided body."""
    c = V(*c)
    vert = [polar(60 * k, R) for k in range(6)]
    ap = R * math.cos(math.radians(30))
    top_p = c + V(0, body / 2 + top, 0)
    bot_p = c - V(0, body / 2 + bot, 0)
    hb = V(0, body / 2, 0)
    for k in range(6):
        a, b = vert[k], vert[(k + 1) % 6]
        n = norm((a + b) / 2)
        m.add("B", body_name, (R, body, t), c + n * (ap - t / 2), cols[k % len(cols)], mat, frame_normal(n), tr, refl)
        tri(m, tip_name, c + a + hb, c + b + hb, top_p, t, tip_cols[k % len(tip_cols)], mat, tip_tr, refl, inside=c)
        tri(m, tip_name, c + a - hb, c + b - hb, bot_p, t, bot_cols[k % len(bot_cols)], mat, tip_tr, refl, inside=c)
    return ap


# ------------------------------------------------------------------------------------------------
# The Enchanting Crystal
# ------------------------------------------------------------------------------------------------
PLUM = (104, 84, 140)
PLUM_DK = (66, 50, 94)
LILAC = (214, 200, 236)
SEAL = (54, 40, 80)
GOLD = (238, 194, 92)
MAGIC = (255, 136, 226)
PINK_GL = (255, 156, 226)
VIOLET_GL = (196, 144, 255)
LILAC_GL = (236, 200, 255)
CORE = (255, 150, 236)
GEM = (255, 84, 186)


def rim_cluster(m, base, a_deg, seed=0, k=1.0):
    """Three crystals growing out of a mound of plum stone, leaning out from the middle."""
    out = polar(a_deg, 1)
    side = np.cross(UP, out)
    m.ell("Mound", (1.4 * k, 0.5 * k, 1.1 * k), base + V(0, 0.05, 0), PLUM_DK, "Slate", R=Ry(a_deg))
    specs = ((out * 0.35 + UP, 2.3, 0.52, PINK_GL, 0.0), (out * 0.25 + side * 0.55 + UP, 1.5, 0.4, VIOLET_GL, 0.3),
             (out * 0.55 - side * 0.45 + UP, 1.1, 0.34, LILAC_GL, -0.3))
    for i, (d, L, w, col, s) in enumerate(specs):
        m.crystal("RimCrystal", base + side * s * k - V(0, 0.1, 0), norm(d), L * k, w * k, col, "Glass", tr=0.12, refl=0.2,
                  spin=15 * i + seed * 20)


def shrine():
    m = PModel("shrine")
    m.solid_names = {"Base", "Step"}
    with m.grouped(""):
        m.cyl("Skirt", 0.3, 16.8, (0, 0.15, 0), PLUM_DK, mat="Slate")
        m.cyl("Base", 0.8, 16, (0, 0.4, 0), PLUM, mat="Slate")
        m.cyl("BaseTrim", 0.16, 16.26, (0, 0.6, 0), GOLD, mat="Metal")
        # the floor: a lilac inlay round the edge, then the dark channel the runes glow in
        m.cyl("Inlay", 0.04, 15.9, (0, 0.82, 0), LILAC, mat="Marble")
        m.cyl("Floor", 0.05, 14.9, (0, 0.825, 0), PLUM, mat="Slate")
        m.cyl("Channel", 0.04, 13.4, (0, 0.84, 0), PLUM_DK, mat="Slate")
        m.cyl("Floor", 0.04, 10.9, (0, 0.85, 0), PLUM, mat="Slate")
        # the round step, and the seal on it
        m.cyl("Step", 0.5, 10.6, (0, 1.05, 0), LILAC, mat="Marble")
        m.cyl("StepTrim", 0.1, 10.84, (0, 1.18, 0), GOLD, mat="Metal")
        m.cyl("Seal", 0.06, 8.8, (0, 1.3, 0), SEAL, mat="Slate")
        # the magic circle: two glowing rings and a six-pointed star, gold studs on its points
        m.cyl("Magic", 0.04, 8.5, (0, 1.33, 0), MAGIC, mat="Neon")
        m.cyl("Seal", 0.04, 8.2, (0, 1.34, 0), SEAL, mat="Slate")
        m.cyl("Magic", 0.04, 5.7, (0, 1.35, 0), MAGIC, mat="Neon")
        m.cyl("Seal", 0.04, 5.4, (0, 1.36, 0), SEAL, mat="Slate")
        pts = [polar(30 + 60 * k, 4.12, 1.385) for k in range(6)]
        for corners in ((0, 2, 4), (1, 3, 5)):
            for i in range(3):
                a, b = pts[corners[i]], pts[corners[(i + 1) % 3]]
                m.add("B", "Magic", (float(np.linalg.norm(b - a)), 0.04, 0.09), (a + b) / 2, MAGIC, "Neon", frame_from_x(b - a))
        for p in pts:
            m.ball("Stud", 0.3, p + V(0, 0.02, 0), GOLD, "Metal")
        # the heart in the middle: a glowing dome in a gold setting
        m.cyl("HeartSetting", 0.16, 2.0, (0, 1.42, 0), GOLD, mat="Metal")
        m.ell("Heart", (1.5, 0.5, 1.5), (0, 1.5, 0), CORE, "Neon")
        # crystal clusters growing out of the rim (clear of the bridge and the stepping stones)
        for k in range(4):
            rim_cluster(m, polar(45 + 90 * k, 7.05, 0.8), 45 + 90 * k, seed=k, k=1.25)
    with m.grouped("Crystal"):
        c = V(0, 8.4, 0)
        m.ell("Core", (1.5, 5.4, 1.5), c, CORE, "Neon")
        R, body, top, bot = 1.7, 4.4, 2.8, 2.4
        ap = hex_crystal(m, c, R, body, top, bot, 0.14,
                         cols=[(244, 156, 255), (255, 170, 232)], tip_cols=[(255, 206, 244), (238, 198, 255)],
                         bot_cols=[(206, 120, 240), (236, 124, 214)], tr=0.3, tip_tr=0.22)
        # two gold bands round the body, a pink gem on every other side
        d = ap + 0.04
        edge = 2 * d * math.tan(math.radians(30))
        for j, y in enumerate((c[1] - body / 2 + 0.25, c[1] + body / 2 - 0.25)):
            for k in range(6):
                n = polar(60 * k + 30, 1)
                m.add("B", "Band", (edge, 0.3, 0.12), V(0, y, 0) + n * d, GOLD, "Metal", frame_normal(n))
                m.ball("Band", 0.3, V(0, y, 0) + polar(60 * k, d / math.cos(math.radians(30))), GOLD, "Metal")
                if (k + j) % 2 == 0:
                    m.ell("Gem", (0.34, 0.42, 0.18), V(0, y, 0) + n * (d + 0.11), GEM, "Glass", R=frame_normal(n), refl=0.25)
        # a crown of little crystals at the top, three more pointing down underneath
        for k in range(3):
            a = 120 * k
            m.crystal("Shell", V(0, c[1] + body / 2 - 0.35, 0) + polar(a, R * 0.92), norm(polar(a, 0.34) + UP), 1.8, 0.42,
                      LILAC_GL if k % 2 else PINK_GL, "Glass", tr=0.15, refl=0.2, spin=10)
            a2 = 60 + 120 * k
            m.crystal("Shell", V(0, c[1] - body / 2 + 0.35, 0) + polar(a2, R * 0.92), norm(polar(a2, 0.4) - UP), 1.35, 0.36,
                      VIOLET_GL, "Glass", tr=0.15, refl=0.2)
        # two thin gold rings crossing round it
        for tilt in (Rz(22), Ry(45) @ Rx(-22)):
            m.ring("Ring", c, 2.8, 0.1, GOLD, normal="y", segments=22, mat="Metal", R=tilt)
    return m


# ------------------------------------------------------------------------------------------------
# The Pull Altar
# ------------------------------------------------------------------------------------------------
MARBLE = (240, 232, 216)
MARBLE_2 = (224, 212, 194)
MARBLE_3 = (206, 194, 176)
LAV_GL = (206, 188, 244)


def altar():
    m = PModel("altar")
    m.solid_names = {"Dais", "Step", "Top", "Pedestal", "PedestalBase"}
    m.cyl("DaisFoot", 0.25, 18.5, (0, 0.125, 0), MARBLE_3, mat="Marble")
    m.cyl("Dais", 1.2, 18, (0, 0.6, 0), MARBLE, mat="Marble")
    m.cyl("DaisTrim", 0.18, 18.3, (0, 1.06, 0), GOLD, mat="Metal")
    m.cyl("StepFoot", 0.2, 13.4, (0, 1.3, 0), MARBLE_3, mat="Marble")
    m.cyl("Step", 1.2, 13, (0, 1.8, 0), MARBLE_2, mat="Marble")
    m.cyl("StepTrim", 0.16, 13.28, (0, 2.27, 0), GOLD, mat="Metal")
    m.cyl("Top", 0.8, 8, (0, 2.8, 0), MARBLE, mat="Marble")
    m.cyl("TopTrim", 0.12, 8.24, (0, 3.1, 0), GOLD, mat="Metal")
    # a glowing ring on the top, a gold star inside it
    m.cyl("Glow", 0.06, 6.4, (0, 3.22, 0), (255, 214, 130), mat="Neon")
    m.cyl("TopInlay", 0.06, 6.0, (0, 3.23, 0), MARBLE, mat="Marble")
    for k in range(8):
        r0 = 1.62 if k % 2 == 0 else 2.2
        a, b = polar(45 * k, r0, 3.28), polar(45 * k, 2.86, 3.28)
        m.add("B", "TopStar", (float(np.linalg.norm(b - a)), 0.06, 0.16 if k % 2 == 0 else 0.11), (a + b) / 2, GOLD, "Metal", frame_from_x(b - a))
    # the pedestal: a square plinth, a reeded marble column, a gold capital
    m.rbox("PedestalBase", (3.0, 0.4, 3.0), (0, 3.45, 0), MARBLE_2, 0.18, "Marble")
    m.cyl("PedestalRing", 0.28, 2.7, (0, 3.79, 0), MARBLE, mat="Marble")
    m.cyl("PedestalRing", 0.1, 2.5, (0, 3.97, 0), GOLD, mat="Metal")
    m.cyl("Pedestal", 1.62, 2.0, (0, 4.83, 0), MARBLE, mat="Marble")
    for k in range(12):
        m.cyl("Reed", 1.5, 0.3, polar(30 * k + 15, 0.98, 4.83), (248, 242, 230), mat="Marble")
    m.cyl("Capital", 0.22, 2.6, (0, 5.72, 0), GOLD, mat="Metal")
    m.rbox("Abacus", (2.8, 0.22, 2.8), (0, 5.92, 0), MARBLE, 0.16, "Marble")
    # four gold claws curling up round the floating pack (clear of it as it turns), a crystal on each
    for k in range(4):
        a = 45 + 90 * k
        pts = [polar(a, r, y) for r, y in ((0.95, 5.95), (1.9, 6.06), (2.45, 6.75), (2.5, 7.7), (2.24, 8.45))]
        ds = (0.36, 0.32, 0.28, 0.24)
        for i in range(4):
            m.rod("Claw", pts[i], pts[i + 1], ds[i], GOLD, "Metal")
            if i > 0:
                m.ball("Claw", ds[i - 1], pts[i], GOLD, "Metal")
        m.ball("Claw", 0.3, pts[-1], GOLD, "Metal")
        m.crystal("ClawGem", pts[-1] + V(0, 0.08, 0), norm(polar(a, -0.2) + UP), 0.8, 0.3, LAV_GL, "Glass", tr=0.1, refl=0.25)
    # crystal clusters in gold-rimmed sockets on the step (the big one in each holds a light)
    for k in range(4):
        a = 45 + 90 * k
        base = polar(a, 5.2, 2.4)
        out = polar(a, 1)
        side = np.cross(UP, out)
        m.cyl("CrystalSocket", 0.3, 1.7, base + V(0, 0.15, 0), MARBLE_2, mat="Marble")
        m.cyl("CrystalSocket", 0.1, 1.84, base + V(0, 0.3, 0), GOLD, mat="Metal")
        i0 = len(m.parts)
        m.crystal("Crystal", base + V(0, 0.2, 0), norm(out * 0.22 + UP), 3.1, 0.8, LAV_GL, "Glass", tr=0.3, refl=0.2, spin=20)
        rename(m, {"Crystal": "CrystalTip"}, i0 + 1)
        m.crystal("CrystalShard", base + side * 0.45 + V(0, 0.2, 0), norm(out * 0.3 + side * 0.5 + UP), 1.7, 0.5, (226, 206, 255),
                  "Glass", tr=0.25, refl=0.2)
        m.crystal("CrystalShard", base - side * 0.45 + V(0, 0.2, 0), norm(out * 0.4 - side * 0.45 + UP), 1.3, 0.42, (196, 176, 246),
                  "Glass", tr=0.25, refl=0.2)
    return m


# ------------------------------------------------------------------------------------------------
# Little lanterns and their posts
# ------------------------------------------------------------------------------------------------
IRON = (38, 40, 38)
IRON_L = (58, 60, 58)


def lantern():
    m = PModel("lantern")
    m.blk("LanternBase", (0.74, 0.1, 0.74), (0, 0.05, 0), IRON, "Metal")
    m.blk("LanternBase", (0.6, 0.08, 0.6), (0, 0.14, 0), IRON_L, "Metal")
    m.blk("Lantern", (0.5, 0.62, 0.5), (0, 0.49, 0), (255, 232, 186), "Glass", tr=0.25)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cyl("LanternFrame", 0.72, 0.09, (sx * 0.26, 0.5, sz * 0.26), IRON, mat="Metal")
    m.cyl("LanternCandle", 0.22, 0.16, (0, 0.29, 0), (250, 244, 230))
    m.ell("LanternFlame", (0.09, 0.17, 0.09), (0, 0.49, 0), (255, 196, 100), "Neon")
    m.blk("LanternCap", (0.72, 0.08, 0.72), (0, 0.84, 0), IRON, "Metal")
    m.blk("LanternCap", (0.52, 0.08, 0.52), (0, 0.92, 0), IRON_L, "Metal")
    m.blk("LanternCap", (0.32, 0.08, 0.32), (0, 1.0, 0), IRON, "Metal")
    m.ball("LanternCap", 0.16, (0, 1.1, 0), IRON_L, "Metal")
    arc_rods(m, "LanternRing", (0, 1.25, 0), 0.12, -40, 220, 4, 0.05, IRON, mat="Metal", joints=False)
    return m


def bollard():
    m = PModel("bollard")
    m.solid_names = {"Bollard"}
    m.cyl("BollardFoot", 0.22, 0.72, (0, 0.11, 0), IRON, mat="Metal")
    m.cyl("Bollard", 1.5, 0.5, (0, 0.95, 0), IRON, mat="Metal")
    for y in (0.42, 1.48):
        m.cyl("BollardRing", 0.1, 0.6, (0, y, 0), IRON_L, mat="Metal")
    m.cyl("BollardCap", 0.12, 0.66, (0, 1.74, 0), IRON_L, mat="Metal")
    return m


def lanternpost():
    m = PModel("lanternpost")
    m.solid_names = {"LanternPost"}
    m.cyl("PostFoot", 0.3, 0.58, (0, 0.15, 0), IRON, mat="Metal")
    m.ball("PostFoot", 0.4, (0, 0.42, 0), IRON_L, "Metal")
    m.cyl("LanternPost", 2.9, 0.25, (0, 1.65, 0), IRON, mat="Metal")
    m.cyl("PostCollar", 0.12, 0.38, (0, 2.5, 0), IRON_L, mat="Metal")
    m.cyl("PostCap", 0.1, 0.52, (0, 3.15, 0), IRON_L, mat="Metal")
    return m


# ------------------------------------------------------------------------------------------------
# The bird bath, the bins, the topiaries
# ------------------------------------------------------------------------------------------------
STONE = (176, 172, 160)
STONE_L = (198, 194, 182)
STONE_D = (148, 144, 134)
MOSS = (92, 132, 66)


def robin(m, at, yaw):
    brown, breast = (128, 94, 70), (232, 112, 60)
    with m.group(R=Ry(yaw), t=at):
        m.ell("Bird", (0.34, 0.3, 0.46), (0, 0.22, 0.02), brown)
        m.ell("Bird", (0.26, 0.22, 0.24), (0, 0.18, -0.12), breast)
        m.ball("Bird", 0.26, (0, 0.42, -0.14), brown)
        m.ell("Bird", (0.2, 0.14, 0.1), (0, 0.38, -0.24), breast)
        m.rod("BirdBeak", (0, 0.42, -0.25), (0, 0.4, -0.36), 0.05, (70, 56, 44))
        for s in (-1, 1):
            m.ball("BirdEye", 0.07, (s * 0.09, 0.45, -0.22), INK)
            m.ball("BirdEye", 0.028, (s * 0.105, 0.47, -0.245), WHITE)
            m.ell("BirdWing", (0.08, 0.2, 0.36), (s * 0.16, 0.25, 0.05), shade(brown, 0.8), R=Rx(-12))
            m.cyl("BirdLeg", 0.12, 0.03, (s * 0.06, 0.06, 0), (90, 70, 50))
        m.ell("BirdTail", (0.14, 0.05, 0.3), (0, 0.3, 0.32), shade(brown, 0.75), R=Rx(-25))


def birdbath():
    m = PModel("birdbath")
    m.solid_names = {"Foot", "Pillar", "Bowl"}
    m.cyl("Foot", 0.3, 2.3, (0, 0.15, 0), STONE_D, mat="Slate")
    m.cyl("Foot", 0.24, 1.9, (0, 0.42, 0), STONE, mat="Slate")
    m.cyl("FootRing", 0.16, 1.4, (0, 0.62, 0), STONE_L, mat="Slate")
    m.ell("PillarBulb", (1.0, 1.1, 1.0), (0, 1.2, 0), STONE, "Slate")
    m.cyl("Pillar", 1.7, 0.6, (0, 1.75, 0), STONE_L, mat="Slate")
    m.cyl("PillarCollar", 0.14, 0.86, (0, 2.42, 0), STONE, mat="Slate")
    m.ell("PillarFlare", (0.95, 0.6, 0.95), (0, 2.7, 0), STONE_L, "Slate")
    m.ell("BowlBelly", (2.7, 0.7, 2.7), (0, 2.98, 0), STONE, "Slate")
    m.cyl("Bowl", 0.32, 3.1, (0, 3.14, 0), STONE_L, mat="Slate")
    m.cyl("BathWater", 0.05, 2.8, (0, 3.315, 0), (96, 156, 176), refl=0.35)
    m.trim_ring("BowlRim", (0, 3.36, 0), 1.48, 0.2, STONE_L, "y", 16, "Slate")
    # moss round the foot
    for a, s in ((20, 1.0), (150, 0.8), (260, 0.9)):
        m.ell("Moss", (0.7 * s, 0.22 * s, 0.45 * s), polar(a, 1.02, 0.3), MOSS, "Grass", R=Ry(a + 90))
    # a robin on the rim, side on, looking out
    robin(m, polar(60, 1.48, 3.42), 60 + 90 + 20)
    return m


BIN = (44, 82, 58)
BIN_L = (60, 104, 74)
BIN_D = (28, 50, 38)


def litter_bin():
    m = PModel("bin")
    m.solid_names = {"Bin"}
    m.cyl("BinFoot", 0.14, 1.42, (0, 0.07, 0), IRON, mat="Metal")
    m.cyl("Bin", 2.08, 1.2, (0, 1.18, 0), BIN_D, mat="Metal")
    for k in range(12):
        a = 30 * k + 15
        m.add("B", "BinSlat", (0.24, 1.86, 0.1), polar(a, 0.62, 1.16), BIN_L, "SmoothPlastic", Ry(a))
    for y in (0.42, 1.9):
        m.cyl("BinHoop", 0.12, 1.46, (0, y, 0), IRON, mat="Metal")
    m.cyl("BinMouth", 0.14, 1.24, (0, 2.26, 0), (16, 20, 18))
    m.cyl("Lid", 0.14, 1.56, (0, 2.38, 0), BIN, mat="Metal")
    m.ell("Lid", (1.36, 0.5, 1.36), (0, 2.44, 0), BIN, "Metal")
    m.ball("LidKnob", 0.2, (0, 2.74, 0), (206, 176, 92), "Metal")
    return m


PLANTER = (200, 196, 184)
PLANTER_D = (170, 166, 154)
PLANTER_L = (218, 214, 202)
BOX_G = (62, 112, 56)


def topiary():
    m = PModel("topiary")
    m.solid_names = {"Planter"}
    m.blk("PlanterFoot", (2.1, 0.16, 2.1), (0, 0.08, 0), PLANTER_D, "Slate")
    m.rbox("Planter", (2.0, 1.2, 2.0), (0, 0.76, 0), PLANTER, 0.16, "Slate")
    for k in range(4):
        n = polar(90 * k, 1)
        m.add("B", "PlanterPanel", (1.2, 0.66, 0.06), n * 1.0 + V(0, 0.76, 0), PLANTER_L, "Slate", frame_normal(n))
    m.rbox("PlanterRim", (2.34, 0.22, 2.34), (0, 1.44, 0), PLANTER_L, 0.2, "Slate")
    m.cyl("Soil", 0.06, 1.9, (0, 1.56, 0), (84, 62, 44), mat="Ground")
    m.cyl("Trunk", 2.6, 0.24, (0, 2.8, 0), (92, 70, 52), mat="Wood")
    for i, (y, D) in enumerate(((2.68, 2.2), (4.68, 1.4))):
        m.ball("Box", D * 0.9, (0, y, 0), BOX_G, "Grass")
        m.puffs("Box", (0, y, 0), (D * 0.82,) * 3, 11 - i * 3, D * 0.44, BOX_G, seed=3 + i, mat="Grass", out=0.3, jitter=0.15,
                shade_k=0.18)
    return m


# ------------------------------------------------------------------------------------------------
# The sleeping cat
# ------------------------------------------------------------------------------------------------
FUR = (232, 150, 70)
FUR_D = (194, 108, 46)
CREAM = (250, 234, 212)
NOSE = (238, 128, 148)


def cat():
    """Curled up on a bench: the head (at -x) rests on its front paws, the tail wraps round to them.
    Faces -z like the old one (ParkBuilder turns it to look at the pond)."""
    m = PModel("cat")
    bc, bs = V(0.05, 0.31, 0.05), V(1.3, 0.62, 1.0)
    m.ell("Body", bs, bc, FUR)
    hc, hs = V(0.36, 0.32, 0.12), V(0.72, 0.56, 0.78)
    m.ell("Body", hs, hc, shade(FUR, 0.97))
    m.ell("Chest", (0.52, 0.34, 0.34), (-0.34, 0.2, -0.32), CREAM)
    # stripes wrapping over the back (slices a touch bigger than the body where they sit)
    for x, (c, s) in ((-0.16, (bc, bs)), (0.1, (bc, bs)), (0.5, (hc, hs))):
        k = math.sqrt(max(0.0, 1 - ((x - c[0]) / (s[0] / 2)) ** 2))
        m.ell("Stripe", (0.12, s[1] * k + 0.03, s[2] * k + 0.03), (x, c[1], c[2]), FUR_D)
    # the head, resting on the paws, turned a little towards the pond
    with m.group(R=Ry(18) @ Rx(6), t=(-0.5, 0.45, -0.3)):
        m.ell("Head", (0.66, 0.56, 0.6), (0, 0, 0), FUR)
        m.ell("Stripe", (0.1, 0.06, 0.3), (0, 0.27, -0.06), FUR_D)
        m.ell("Muzzle", (0.36, 0.2, 0.2), (0, -0.09, -0.24), CREAM)
        m.ell("Nose", (0.09, 0.06, 0.06), (0, -0.02, -0.33), NOSE)
        for s in (-1, 1):
            # closed eyes: two short strokes in a shallow curve
            eye = [V(s * 0.065, 0.065, -0.27), V(s * 0.11, 0.04, -0.274), V(s * 0.16, 0.04, -0.267), V(s * 0.205, 0.065, -0.248)]
            for i in range(3):
                m.rod("Eye", eye[i], eye[i + 1], 0.03, INK)
            # pointed ears: a flat triangle with a pink inner triangle in front of it
            A, B, P = V(s * 0.04, 0.22, 0.02), V(s * 0.27, 0.15, 0.04), V(s * 0.22, 0.47, 0.06)
            tri(m, "Ear", A, B, P, 0.1, FUR, inside=(0, 0.1, 0.4))
            mid = (A + B + P) / 3
            k = 0.62
            tri(m, "EarInner", mid + (A - mid) * k + V(0, 0, -0.045), mid + (B - mid) * k + V(0, 0, -0.045),
                mid + (P - mid) * k + V(0, 0, -0.045), 0.03, NOSE, inside=(0, 0.1, 0.4))
            for dy in (0.0, -0.05):
                m.rod("Whisker", (s * 0.15, -0.08 + dy, -0.3), (s * 0.42, -0.04 + dy * 2, -0.32), 0.022, (252, 248, 240))
    for x in (-0.5, -0.22):
        m.ell("Paw", (0.22, 0.15, 0.3), (x, 0.075, -0.52), CREAM)
    # the tail: from behind, round the right side to the front paws, ringed, a dark tip
    pts = [V(0.62, 0.14, 0.34), V(0.74, 0.12, -0.12), V(0.5, 0.1, -0.5), V(0.12, 0.1, -0.63), V(-0.12, 0.12, -0.66)]
    for i in range(4):
        col = (FUR, FUR_D, FUR, FUR_D)[i]
        m.seg("Tail", pts[i], pts[i + 1], 0.115 - i * 0.008, col, ext=0.06)
    return m


# ------------------------------------------------------------------------------------------------
# The campfire: log benches, the fire pit
# ------------------------------------------------------------------------------------------------
BARK = (120, 86, 58)
BARK_D = (92, 64, 42)
SAPWOOD = (206, 170, 120)
RING = (170, 130, 88)


def logseat():
    """A log bench along x (4.4 long), its middle 0.5 up, cut ends with growth rings, a branch stub,
    moss on top, two little mushrooms at its foot."""
    m = PModel("logseat")
    m.solid_names = {"LogSeat"}
    m.cyl("LogSeat", 4.4, 1.2, (0, 0.5, 0), BARK, axis="x", mat="Wood")
    for a in (35, 160, 250):
        m.add("C", "Bark", (4.0, 0.16, 0.16), (0, 0.5 + math.sin(math.radians(a)) * 0.56, math.cos(math.radians(a)) * 0.56), BARK_D, "Wood")
    for s in (-1, 1):
        m.cyl("LogEnd", 0.06, 1.06, (s * 2.2, 0.5, 0), SAPWOOD, axis="x", mat="Wood")
        m.cyl("LogRing", 0.07, 0.72, (s * 2.205, 0.5, 0), RING, axis="x", mat="Wood")
        m.cyl("LogEnd", 0.08, 0.4, (s * 2.21, 0.5, 0), SAPWOOD, axis="x", mat="Wood")
        m.cyl("LogRing", 0.09, 0.1, (s * 2.215, 0.5, 0), RING, axis="x", mat="Wood")
    stub_a, stub_b = V(1.1, 0.75, 0.45), V(1.45, 1.0, 0.85)
    m.rod("Branch", stub_a, stub_b, 0.3, BARK, "Wood")
    m.add("C", "LogEnd", (0.05, 0.27, 0.27), stub_b + norm(stub_b - stub_a) * 0.02, SAPWOOD, "Wood", frame_from_x(stub_b - stub_a))
    m.ell("Moss", (1.3, 0.16, 0.6), (-1.0, 1.06, 0.18), MOSS, "Grass", R=Rx(-14))
    for x, z, h, d in ((-1.6, 0.66, 0.24, 0.3), (-1.3, 0.72, 0.16, 0.22)):
        m.cyl("Mushroom", h, d * 0.4, (x, h / 2, z), (240, 232, 214))
        m.ell("Mushroom", (d, d * 0.5, d), (x, h, z), (176, 112, 70))
    return m


def firepit():
    """The ring of stones and the log tepee round the embers (the fire itself is made in code)."""
    import random
    rnd = random.Random(42)
    m = PModel("firepit")
    m.cyl("Ash", 0.08, 2.8, (0, 0.04, 0), (78, 72, 68), mat="Slate")
    for k in range(12):
        a = k * 30 + rnd.uniform(-6, 6)
        g = rnd.uniform(118, 150)
        s = rnd.uniform(0.85, 1.1)
        p = polar(a, 1.95, 0.24 * s)
        m.ell("FireStone", (0.95 * s, 0.62 * s, 0.82 * s), p, (g, g - 6, g - 12), "Slate", R=Ry(a + rnd.uniform(-20, 20)))
        if k % 3 == 0:
            m.ell("Moss", (0.6 * s, 0.14 * s, 0.5 * s), p + V(0, 0.27 * s, 0.05) + polar(a, 0.12), MOSS, "Grass", R=Ry(a))
    for k in range(5):
        a = 72 * k + 20
        foot, top = polar(a, 1.05, 0.12), polar(a + 25, 0.14, 1.35)
        m.rod("FireLog", foot, top, 0.3, BARK, "Wood")
        m.rod("FireLog", top - norm(top - foot) * 0.32, top + norm(top - foot) * 0.05, 0.31, (40, 32, 30), "Wood")
    for k in range(2):
        m.cyl("FireLog", 2.4, 0.4, (0, 0.2, 0), BARK_D, axis="x", mat="Wood", R=Ry(45 + 90 * k))
    return m


# ------------------------------------------------------------------------------------------------
# The Duel Table in the gazebo, the picnic basket
# ------------------------------------------------------------------------------------------------
WHITE_IRON = (238, 238, 232)
TABLE_WOOD = (110, 78, 54)
FELT = (46, 110, 70)
CARD_BACK = (96, 78, 132)


def dueltable():
    """The park's Duel Table (y = 0 is the gazebo floor): a wooden rim round green felt with two cards
    and a deck on it, gold studs on the corners, a white iron pedestal on four curled feet, and two
    stools with red cushions either side (x = -4.4 and 4.4)."""
    m = PModel("dueltable")
    m.solid_names = {"TableRim", "Leg", "Stool", "StoolLeg"}
    m.rbox("TableRim", (6.8, 0.4, 4.6), (0, 2.95, 0), TABLE_WOOD, 0.5, "Wood")
    m.rbox("Table", (6.2, 0.1, 4.0), (0, 3.17, 0), FELT, 0.35, "Fabric", edge_name="Felt")
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.ball("TableStud", 0.3, (sx * 3.05, 3.12, sz * 1.95), GOLD, "Metal")
    for x, z, yaw in ((-1.7, 0.5, 12), (1.6, -0.6, -8)):
        m.blk("Card", (0.98, 0.03, 1.36), (x, 3.235, z), GOLD, "Metal", R=Ry(yaw))
        m.blk("Card", (0.9, 0.04, 1.28), (x, 3.25, z), CARD_BACK, "SmoothPlastic", R=Ry(yaw))
    m.blk("Deck", (0.9, 0.3, 1.28), (0.3, 3.37, 1.1), CARD_BACK, "SmoothPlastic", R=Ry(4))
    m.blk("Deck", (0.96, 0.31, 1.34), (0.3, 3.365, 1.1), GOLD, "Metal", R=Ry(4))
    # the pedestal
    m.cyl("LegCollar", 0.25, 1.3, (0, 2.62, 0), WHITE_IRON, mat="Metal")
    m.cyl("Leg", 2.2, 0.9, (0, 1.6, 0), WHITE_IRON, mat="Metal")
    m.cyl("LegFoot", 0.3, 1.6, (0, 0.3, 0), WHITE_IRON, mat="Metal")
    for k in range(4):
        a = 45 + 90 * k
        p0, p1, p2 = polar(a, 0.6, 0.35), polar(a, 1.5, 0.25), polar(a, 1.9, 0.12)
        m.rod("LegFoot", p0, p1, 0.32, WHITE_IRON, "Metal")
        m.rod("LegFoot", p1, p2, 0.28, WHITE_IRON, "Metal")
        m.ball("LegFoot", 0.32, p1, WHITE_IRON, "Metal")
        m.ball("LegFoot", 0.3, p2, WHITE_IRON, "Metal")
    # the stools
    for x in (-4.4, 4.4):
        m.cyl("StoolFoot", 0.15, 1.1, (x, 0.075, 0), WHITE_IRON, mat="Metal")
        m.cyl("StoolLeg", 1.7, 0.4, (x, 0.85, 0), WHITE_IRON, mat="Metal")
        m.trim_ring("StoolRing", (x, 0.8, 0), 0.5, 0.08, WHITE_IRON, "y", 10, "Metal")
        m.cyl("Stool", 0.3, 1.8, (x, 1.85, 0), (150, 112, 78), mat="Wood")
        m.ell("StoolCushion", (1.62, 0.38, 1.62), (x, 2.04, 0), (178, 52, 52), "Fabric")
        m.ball("StoolButton", 0.14, (x, 2.22, 0), (140, 36, 40), "Fabric")
    return m


WICKER = (196, 152, 92)
WICKER_D = (160, 118, 66)


def basket():
    """A wicker picnic basket (1.6 x 0.9 x 1.1, standing on y = 0): woven bands, a lid propped a little
    open with a red check cloth peeking out, a bent handle over the top."""
    m = PModel("basket")
    m.solid_names = {"Basket"}
    m.blk("Basket", (1.6, 0.9, 1.1), (0, 0.45, 0), WICKER, "Fabric")
    for y in (0.24, 0.6):
        m.blk("BasketWeave", (1.64, 0.1, 1.14), (0, y, 0), WICKER_D, "Fabric")
    m.blk("BasketRim", (1.68, 0.1, 1.18), (0, 0.88, 0), WICKER_D, "Fabric")
    for i in range(3):
        m.blk("Cloth", (0.46, 0.16, 0.06), (-0.5 + i * 0.5, 0.96, -0.5), (200, 50, 50) if i % 2 == 0 else (246, 240, 232), "Fabric", R=Rx(-20))
    with m.group(R=Rx(-6), t=(0, 0.94, 0.56)):
        m.blk("BasketLid", (1.7, 0.1, 1.2), (0, 0.05, -0.6), WICKER, "Fabric")
        m.blk("BasketLid", (1.5, 0.05, 1.0), (0, 0.12, -0.6), WICKER_D, "Fabric")
    arc_rods(m, "Handle", (0, 0.95, 0), 0.62, 10, 170, 5, 0.1, (130, 94, 54), mat="Wood")
    return m


# ------------------------------------------------------------------------------------------------
# The Hall of Pulls and the leaderboards: green painted notice boards under shingled gable roofs
# (the Board parts the client draws on, and the lanterns, are made in ParkBuilder)
# ------------------------------------------------------------------------------------------------
BOARD_G = (56, 84, 60)
BOARD_G_D = (40, 62, 44)
BOARD_G_L = (72, 104, 76)
FRAME_W = (110, 74, 46)
SHINGLE = (122, 62, 52)
SHINGLE_2 = (138, 72, 58)
FASCIA = (236, 226, 204)
COPPER = (186, 120, 74)
BRASS_P = (226, 184, 84)


def gable_roof(m, width, z_front, z_back, y_eave, y_ridge, thick, rows=3, gable_color=BOARD_G,
               roof_color=(104, 56, 46), shingles=(SHINGLE, SHINGLE_2), ridge_color=COPPER, finial=BRASS_P,
               fascia=FASCIA, gable_mat="Wood", ends=(-1, 1)):
    """A gabled roof along x: two slabs from the eaves (at z_front and z_back) up to the ridge, rows of
    shingles, a copper ridge cap with finials, cream fascia boards and two gable ends. `ends` says
    which ends (-1 at -x, 1 at +x) get a gable and a finial (a porch roof against a wall has one)."""
    z_r = (z_front + z_back) / 2
    for z_e in (z_front, z_back):
        a = V(0, y_eave, z_e)
        b = V(0, y_ridge, z_r)
        v = b - a
        L = float(np.linalg.norm(v))
        up = norm(v)
        out = norm(np.cross(V(1, 0, 0), up) if z_e > z_r else np.cross(up, V(1, 0, 0)))
        if out[1] < 0:
            out = -out
        R = np.column_stack([V(1, 0, 0), up, np.cross(V(1, 0, 0), up)])
        mid = (a + b) / 2 + out * (thick / 2)
        m.blk("Roof", (width, L + 0.3, thick), mid, roof_color, "WoodPlanks", R=R)
        for k in range(rows):
            t = (k + 0.5) / rows
            p = a + v * t + out * (thick + 0.06)
            m.blk("Shingles", (width + 0.3, L / rows + 0.2, 0.16), p, shingles[k % 2], "Slate", R=R)
        m.cyl("Fascia", width + 0.4, 0.34, a + V(0, -0.05, 0), fascia, "x", "Wood")
    m.cyl("RoofRidge", width + 0.6, 0.56, (0, y_ridge + thick * 0.75, z_r), ridge_color, "x", "Metal")
    for sx in (-1, 1):
        if sx not in ends:
            continue
        m.ball("RoofRidge", 0.62, (sx * (width / 2 + 0.3), y_ridge + thick * 0.75, z_r), finial, "Metal")
        x = sx * (width / 2 - 0.4)
        tri(m, "Gable", (x, y_eave, z_front), (x, y_eave, z_back), (x, y_ridge, z_r), 0.3, gable_color, gable_mat,
            inside=(0, (y_eave + y_ridge) / 2, z_r))


def board_frame(m, w, h, cy, z, rail, frame_color=FRAME_W, rosette=BRASS_P):
    """A carved frame round a w x h board centred at height cy (its face at z): round rails, gold beads
    inside them and gold rosettes on the corners."""
    hw, hh = w / 2 + rail / 2, h / 2 + rail / 2
    m.cyl("Frame", w + rail * 2, rail, (0, cy + hh, z), frame_color, "x", "Wood")
    m.cyl("Frame", w + rail * 2, rail, (0, cy - hh, z), frame_color, "x", "Wood")
    m.cyl("Frame", h + rail * 2, rail, (-hw, cy, z), frame_color, "y", "Wood")
    m.cyl("Frame", h + rail * 2, rail, (hw, cy, z), frame_color, "y", "Wood")
    bead = rail * 0.24
    m.cyl("FrameBead", w, bead, (0, cy + h / 2 + bead / 2, z - rail * 0.18), rosette, "x", "Metal")
    m.cyl("FrameBead", w, bead, (0, cy - h / 2 - bead / 2, z - rail * 0.18), rosette, "x", "Metal")
    m.cyl("FrameBead", h, bead, (-w / 2 - bead / 2, cy, z - rail * 0.18), rosette, "y", "Metal")
    m.cyl("FrameBead", h, bead, (w / 2 + bead / 2, cy, z - rail * 0.18), rosette, "y", "Metal")
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = (sx * hw, cy + sy * hh, z - rail * 0.32)
            m.cyl("Rosette", rail * 0.3, rail * 1.35, c, rosette, "z", "Metal")
            m.ball("Rosette", rail * 0.62, (c[0], c[1], c[2] - rail * 0.14), rosette, "Metal")


def hall():
    """The Hall of Pulls (the client draws on its 24 x 14 Board, at y 4 to 18 just in front of z = 0):
    a stone platform with a step, two thick green pillars on stone bases with gold bands, a carved
    frame with gold beads and rosettes, a frieze with a gold pack medallion, a shingled gable roof
    with a copper ridge, and iron hooks for two lanterns under the eaves."""
    m = PModel("hall")
    m.solid_names = {"HallBase", "Pillar", "PillarBase"}
    m.rbox("HallBase", (32.0, 0.8, 7.0), (0, 0.4, 0.4), STONE, 0.7, "Slate")
    m.rbox("HallBase", (22.0, 0.4, 2.2), (0, 0.2, -3.9), STONE_L, 0.5, "Slate")
    m.blk("HallBase", (31.0, 0.08, 6.0), (0, 0.82, 0.4), STONE_L, "Slate")
    for sx in (-1, 1):
        x = sx * 14.2
        m.blk("PillarBase", (3.0, 1.2, 3.0), (x, 1.4, 0), STONE_D, "Slate")
        m.blk("PillarBase", (2.7, 0.3, 2.7), (x, 2.15, 0), STONE_L, "Slate")
        m.rbox("Pillar", (2.3, 18.4, 2.3), (x, 11.5, 0), BOARD_G, 0.45, "Wood")
        m.blk("Pillar", (1.3, 14.6, 0.1), (x, 11.2, -1.16), BOARD_G_L, "Wood")
        for y in (4.4, 17.4):
            m.blk("PillarBand", (2.5, 0.32, 2.5), (x, y, 0), BRASS_P, "Metal")
        m.blk("PillarBand", (2.7, 0.5, 2.7), (x, 20.45, 0), BOARD_G_D, "Wood")
    m.blk("Frame", (26.0, 16.0, 0.8), (0, 11.0, 0.1), BOARD_G, "Wood")
    board_frame(m, 24.0, 14.0, 11.0, -0.75, 0.9)
    # the frieze under the roof, with a gold medallion and a little pack in it
    m.blk("Frieze", (31.0, 1.7, 0.7), (0, 19.75, 0.0), BOARD_G_D, "Wood")
    m.cyl("Frieze", 30.6, 0.2, (0, 18.96, -0.38), BRASS_P, "x", "Metal")
    m.cyl("Medallion", 0.24, 2.2, (0, 19.75, -0.42), BRASS_P, "z", "Metal")
    m.blk("Medallion", (0.86, 1.2, 0.12), (0, 19.75, -0.58), (110, 70, 200), R=Rz(-8))
    m.ball("Medallion", 0.3, (0, 19.75, -0.66), (255, 236, 160), "Neon")
    gable_roof(m, 33.0, -3.6, 3.2, 20.7, 23.6, 0.5)
    # hooks for the lanterns, under the front eave
    for sx in (-1, 1):
        x = sx * 9.0
        m.rod("LanternHook", (x, 20.65, -3.4), (x, 19.8, -3.4), 0.12, IRON, "Metal")
        m.ring("LanternHook", (x, 19.7, -3.4), 0.16, 0.08, IRON, "x", 6, "Metal")
    return m


def leaderboard():
    """A leaderboard (the client draws on its 12 x 12 Board, at y 1 to 13 just in front of z = 0): two
    green posts on stone feet, a carved frame, a small shingled gable roof, and an iron bracket on
    the right post for the lantern."""
    m = PModel("leaderboard")
    m.solid_names = {"Post", "PostFoot"}
    for sx in (-1, 1):
        x = sx * 6.9
        m.blk("PostFoot", (1.9, 0.8, 1.9), (x, 0.4, 0), STONE_D, "Slate")
        m.blk("PostFoot", (1.6, 0.2, 1.6), (x, 0.9, 0), STONE_L, "Slate")
        m.rbox("Post", (1.2, 13.6, 1.2), (x, 7.6, 0), BOARD_G, 0.3, "Wood")
        m.blk("PostBand", (1.36, 0.24, 1.36), (x, 2.2, 0), BRASS_P, "Metal")
    m.blk("Frame", (13.2, 13.2, 0.6), (0, 7.0, 0.1), BOARD_G, "Wood")
    board_frame(m, 12.0, 12.0, 7.0, -0.7, 0.66)
    m.blk("Frieze", (15.0, 0.9, 0.5), (0, 14.1, 0.0), BOARD_G_D, "Wood")
    gable_roof(m, 16.4, -2.2, 1.9, 14.5, 16.4, 0.36, rows=2)
    # the lantern bracket: an arm out from the right post with a curl, and a hook
    m.rod("LanternHook", (7.5, 12.4, 0), (8.9, 12.4, 0), 0.14, IRON, "Metal")
    m.rod("LanternHook", (7.5, 11.5, 0), (8.3, 12.4, 0), 0.1, IRON, "Metal")
    arc_rods(m, "LanternHook", (8.9, 12.7, 0), 0.3, -90, 150, 5, 0.1, IRON, mat="Metal")
    m.rod("LanternHook", (8.9, 12.4, 0), (8.9, 11.85, 0), 0.08, IRON, "Metal")
    return m


# ------------------------------------------------------------------------------------------------
# The Top Collector's terrace: the round terrace and its reeded pedestal, the easels, the lectern
# and the sign's frame (the cards, the plaque, the sign, the avatar spot are made in ParkBuilder)
# ------------------------------------------------------------------------------------------------
PAVING = (219, 216, 207)
PAVING_D = (196, 192, 182)
MARBLE_W = (244, 238, 228)
MARBLE_D = (214, 206, 192)


def tcterrace():
    """The Top Collector's terrace (y = 0 is the lawn; the stand is at y 4.36): two round stone steps,
    the terrace with a rounded edge and a star mosaic round the pedestal, and a marble pedestal with
    gold-capped reeds, a gold band and a rimmed cap."""
    m = PModel("tcterrace")
    m.solid_names = {"Step", "Terrace", "PedestalBase", "Pedestal", "PedestalCap"}
    m.cyl("Step", 0.34, 29.6, (0, 0.17, 0), PAVING_D, mat="Slate")
    m.cyl("Step", 0.67, 28.2, (0, 0.335, 0), shade(PAVING, 0.98), mat="Slate")
    m.cyl("Terrace", 1.0, 26.8, (0, 0.5, 0), PAVING, mat="Slate")
    m.trim_ring("TerraceEdge", (0, 0.93, 0), 13.3, 0.36, PAVING_D, "y", 28, "Slate")
    m.cyl("Inlay", 0.04, 12.2, (0, 1.02, 0), (150, 140, 126), mat="Slate")
    m.cyl("Inlay", 0.06, 11.2, (0, 1.03, 0), shade(PAVING, 1.06), mat="Marble")
    m.trim_ring("Inlay", (0, 1.06, 0), 5.5, 0.12, GOLD, "y", 20, "Metal")
    for k in range(8):
        long = k % 2 == 0
        m.blk("InlayStar", (0.5, 0.06, 4.4 if long else 3.0), (0, 1.07, 0), GOLD if long else (176, 150, 110), "Marble", R=Ry(k * 22.5))
    # the pedestal
    m.cyl("PedestalBase", 0.5, 6.4, (0, 1.25, 0), MARBLE_D, mat="Marble")
    m.trim_ring("PedestalBase", (0, 1.55, 0), 2.85, 0.4, MARBLE_W, "y", 18, "Marble")
    m.cyl("Pedestal", 2.4, 4.4, (0, 2.8, 0), MARBLE_W, mat="Marble")
    for k in range(14):
        a = k * 360 / 14
        p = polar(a, 2.2, 2.75)
        m.cyl("PedestalReed", 2.1, 0.42, p, MARBLE_W, mat="Marble")
        m.ball("PedestalReed", 0.42, p + V(0, 1.05, 0), GOLD, "Metal")
    m.cyl("PedestalBand", 0.3, 5.0, (0, 1.85, 0), GOLD, mat="Metal")
    m.cyl("PedestalBand", 0.28, 4.95, (0, 3.6, 0), GOLD, mat="Metal")
    m.cyl("PedestalCap", 0.36, 5.6, (0, 4.18, 0), shade(MARBLE_W, 1.04), mat="Marble")
    m.trim_ring("PedestalCap", (0, 4.2, 0), 2.8, 0.2, GOLD, "y", 20, "Metal")
    return m


EASEL_WOOD = (176, 136, 70)
EASEL_WOOD_D = (140, 104, 52)


def easel():
    """An easel for a card (y = 0 at its feet; the card, 3.1 x 4.34, faces -z with its middle at
    (0, 3.85, 0.37), leaning back 10 degrees against the front legs): turned legs with brass feet
    leaning back at the same angle, a cross bar, a round-nosed ledge with brass ends the card
    stands on, and a gold frame behind the card with corner balls and a crest."""
    m = PModel("easel")
    legs = [((-1.3, 0, -0.1), (-0.6, 6.6, 1.05)), ((1.3, 0, -0.1), (0.6, 6.6, 1.05)), ((0, 0, 2.3), (0, 6.4, 1.2))]
    for a, b in legs:
        m.rod("Leg", a, b, 0.26, EASEL_WOOD, "Wood")
        m.ball("LegFoot", 0.34, a, GOLD, "Metal")
    m.ball("Leg", 0.46, (0, 6.62, 1.12), EASEL_WOOD_D, "Wood")
    m.ball("Leg", 0.26, (0, 6.95, 1.12), GOLD, "Metal")
    m.rod("Leg", (-1.12, 1.1, 0.13), (1.12, 1.1, 0.13), 0.16, EASEL_WOOD_D, "Wood")
    m.blk("Ledge", (3.9, 0.26, 0.6), (0, 1.6, 0.06), EASEL_WOOD, "Wood")
    m.cyl("Ledge", 3.9, 0.3, (0, 1.6, -0.24), EASEL_WOOD_D, "x", "Wood")
    for sx in (-1, 1):
        m.cyl("Ledge", 0.08, 0.36, (sx * 1.99, 1.6, -0.24), GOLD, "x", "Metal")
    with m.group(R=Rx(10), t=(0, 3.85, 0.37)):
        m.blk("Frame", (3.45, 4.75, 0.1), (0, 0, 0.1), GOLD, "Metal")
        for y in (2.32, -2.32):
            m.cyl("Frame", 3.5, 0.2, (0, y, 0.0), GOLD, "x", "Metal")
        for x in (1.69, -1.69):
            m.cyl("Frame", 4.84, 0.2, (x, 0, 0.0), GOLD, "y", "Metal")
            for y in (2.32, -2.32):
                m.ball("Frame", 0.34, (x, y, -0.02), GOLD, "Metal")
        m.ball("Frame", 0.44, (0, 2.62, 0.0), GOLD, "Metal")
    return m


def lectern():
    """The plaque's lectern (y = 0 at its foot, facing -z; the plaque, 5.5 x 2.6, sits at (0, 1.75,
    -0.2) tilted back 48 degrees): a marble plinth, a tapered body with a gold band, and a gold frame
    with rounded corners behind the plaque on a marble bracket."""
    m = PModel("lectern")
    m.solid_names = {"Lectern"}
    m.rbox("Lectern", (2.9, 0.3, 1.5), (0, 0.15, 0), MARBLE_D, 0.25, "Marble")
    m.blk("Lectern", (2.2, 1.1, 0.9), (0, 0.85, 0), MARBLE_W, "Marble")
    m.blk("Lectern", (2.5, 0.16, 1.1), (0, 0.35, 0), MARBLE_D, "Marble")
    m.blk("LecternBand", (2.28, 0.14, 0.98), (0, 1.25, 0), GOLD, "Metal")
    with m.group(R=Rx(48), t=(0, 1.75, -0.2)):
        m.rbox("PlaqueFrame", (5.9, 3.0, 0.2), (0, 0, 0.08), GOLD, 0.3, "Metal", axis="z")
        m.blk("PlaqueBack", (4.6, 2.2, 0.5), (0, 0, 0.4), MARBLE_W, "Marble")
        for sx in (-1, 1):
            m.ball("PlaqueFrame", 0.3, (sx * 2.9, 0, -0.02), GOLD, "Metal")
    return m


def tcsign():
    """The frame round the TOP COLLECTOR sign (the 9 x 1.8 sign board itself is made in ParkBuilder,
    its middle at y = 0, facing -z): gold trim with round ends, a crown on top and scroll brackets
    down to the arch."""
    m = PModel("tcsign")
    m.blk("SignTrim", (9.4, 2.2, 0.2), (0, 0, 0.12), GOLD, "Metal")
    for sx in (-1, 1):
        m.cyl("SignTrim", 0.2, 2.2, (sx * 4.5, 0, 0.12), GOLD, "z", "Metal")
        m.cyl("SignEnd", 0.3, 1.8, (sx * 4.5, 0, 0.0), (36, 64, 48), "z", "Wood")
    # a little gold crown on top
    m.cyl("Crown", 0.3, 1.5, (0, 1.25, 0), GOLD, "y", "Metal")
    for k in range(5):
        x = -0.6 + 0.3 * k
        m.blk("Crown", (0.2, 0.55 if k % 2 == 0 else 0.4, 0.2), (x, 1.6 + (0.07 if k % 2 == 0 else 0), 0), GOLD, "Metal", R=Rz(45 if k % 2 else 0))
    m.ball("Crown", 0.24, (0, 1.95, -0.05), (255, 90, 120), "Neon")
    # scroll brackets from the arch's top up to the sign
    for sx in (-1, 1):
        x = sx * 2.5
        m.rod("SignPost", (x, -2.6, 0), (x, -1.1, 0), 0.2, WHITE_IRON, "Metal")
        arc_rods(m, "SignPost", (x + sx * 0.38, -1.8, 0), 0.38, 0, 270, 6, 0.12, WHITE_IRON, mat="Metal")
    return m


# ------------------------------------------------------------------------------------------------
# The Trading Post's tables (inside it: the building itself is a Blender model)
# ------------------------------------------------------------------------------------------------
def tptable():
    """A round café table with two stools (y = 0 is the Trading Post's floor; the stools at z = -3.2
    and 3.2): a top with a rim and a check card mat, a turned pedestal on a cross foot, and stools
    on three splayed legs with a foot ring and a cushion."""
    m = PModel("tptable")
    m.solid_names = {"TableTop", "TableLeg", "Stool"}
    wood, dark = (150, 112, 78), (92, 68, 50)
    m.cyl("TableTop", 0.3, 4.2, (0, 2.75, 0), wood, mat="WoodPlanks")
    m.trim_ring("TableTop", (0, 2.66, 0), 2.08, 0.22, dark, "y", 16, "Wood")
    m.blk("TableMat", (2.2, 0.03, 1.6), (0, 2.915, 0), (40, 92, 70), "Fabric")
    m.blk("TableMat", (2.36, 0.025, 1.76), (0, 2.91, 0), (236, 214, 150), "Fabric")
    m.cyl("TableLeg", 2.2, 0.5, (0, 1.5, 0), dark, mat="Wood")
    m.ell("TableLeg", (0.9, 0.7, 0.9), (0, 1.15, 0), wood, "Wood")
    m.cyl("TableLeg", 0.2, 1.1, (0, 2.5, 0), dark, mat="Wood")
    for a in (0, 90):
        m.blk("TableFoot", (2.6, 0.24, 0.42), (0, 0.12, 0), dark, "Wood", R=Ry(a + 45))
    for z in (-3.2, 3.2):
        m.cyl("Stool", 0.3, 1.7, (0, 1.75, z), wood, mat="WoodPlanks")
        m.ell("StoolCushion", (1.5, 0.34, 1.5), (0, 1.98, z), (176, 64, 52), "Fabric")
        for k in range(3):
            a = 30 + 120 * k
            m.rod("StoolLeg", polar(a, 0.45, 1.62) + V(0, 0, z), polar(a, 0.75, 0.0) + V(0, 0, z), 0.18, dark, "Wood")
        m.trim_ring("StoolLeg", (0, 0.6, z), 0.62, 0.08, (60, 60, 58), "y", 9, "Metal")
    return m


# ------------------------------------------------------------------------------------------------
# The gate porches: marble columns and stone urns with spiral topiary
# ------------------------------------------------------------------------------------------------
PORCH_MARBLE = (238, 238, 232)
PORCH_FLUTE = (204, 204, 198)
PORCH_GOLD = (222, 178, 84)
LIMESTONE_P = (206, 198, 180)


def porchcolumn():
    """A porch column (y = 0 is the porch floor, the top at 14.7): a square plinth, two round mouldings,
    a shaft with eight flutes all the way round, a gold necking ring, a round echinus and a square
    abacus."""
    m = PModel("porchcolumn")
    m.solid_names = {"Column", "ColumnBase"}
    m.blk("ColumnBase", (2.0, 0.5, 2.0), (0, 0.25, 0), PORCH_MARBLE, "Marble")
    m.cyl("ColumnBase", 0.3, 1.82, (0, 0.65, 0), PORCH_MARBLE, mat="Marble")
    m.cyl("ColumnBase", 0.22, 1.56, (0, 0.91, 0), shade(PORCH_MARBLE, 0.97), mat="Marble")
    m.cyl("Column", 12.9, 1.3, (0, 7.45, 0), PORCH_MARBLE, mat="Marble")
    for k in range(8):
        p = polar(k * 45 + 22.5, 0.63, 7.4)
        m.blk("Flute", (0.1, 12.3, 0.1), p, PORCH_FLUTE, "Marble", R=Ry(k * 45 + 22.5))
    m.cyl("ColumnCap", 0.2, 1.5, (0, 13.9, 0), PORCH_GOLD, mat="Metal")
    m.cyl("ColumnCap", 0.3, 1.86, (0, 14.15, 0), PORCH_MARBLE, mat="Marble")
    m.blk("ColumnCap", (2.1, 0.4, 2.1), (0, 14.5, 0), PORCH_MARBLE, "Marble")
    m.blk("ColumnCap", (2.2, 0.08, 2.2), (0, 14.32, 0), PORCH_GOLD, "Metal")
    return m


def porchurn():
    """A stone urn with a clipped spiral topiary and a gold star (y = 0 is the ground): a square plinth,
    a turned foot, a round bowl with a gold lip, the topiary in five shrinking balls."""
    m = PModel("porchurn")
    m.solid_names = {"Plinth", "Urn"}
    m.blk("Plinth", (3.2, 0.7, 3.2), (0, 0.35, 0), LIMESTONE_P, "Slate")
    m.blk("Plinth", (2.9, 0.12, 2.9), (0, 0.76, 0), shade(LIMESTONE_P, 1.06), "Slate")
    m.cyl("UrnFoot", 0.5, 1.5, (0, 1.07, 0), shade(LIMESTONE_P, 1.08), mat="Marble")
    m.ell("UrnFoot", (1.9, 0.5, 1.9), (0, 1.35, 0), shade(LIMESTONE_P, 1.04), "Marble")
    m.ell("Urn", (3.0, 2.3, 3.0), (0, 2.45, 0), shade(LIMESTONE_P, 1.1), "Marble")
    m.cyl("UrnLip", 0.34, 2.9, (0, 3.45, 0), PORCH_GOLD, mat="Metal")
    m.cyl("Soil", 0.1, 2.5, (0, 3.6, 0), (70, 54, 40), mat="Ground")
    for k in range(5):
        d = 2.6 - k * 0.42
        m.ball("Leaves", d, (math.sin(k * 1.9) * 0.25, 4.4 + k * 1.25, math.cos(k * 1.9) * 0.25), shade((58, 108, 54), 1 + k * 0.06), "Grass")
    m.ball("TopiaryStar", 0.5, (0, 10.6, 0), PORCH_GOLD, "Neon")
    return m


# ------------------------------------------------------------------------------------------------
# The Quest Hall on the north lawn, and Quill, the owl who keeps it
# ------------------------------------------------------------------------------------------------
QH_STONE = (178, 172, 160)
QH_STONE_D = (146, 140, 130)
QH_STONE_L = (206, 200, 188)
QH_PLASTER = (242, 232, 210)
QH_TIMBER = (92, 64, 46)
QH_TIMBER_L = (124, 90, 62)
QH_FLOOR = (158, 114, 76)
QH_SLATE = (64, 86, 124)
QH_SLATE_2 = (78, 102, 142)
QH_UNDER = (98, 68, 48)
QH_NAVY = (38, 58, 100)
QH_VERDIGRIS = (98, 166, 146)
QH_GLASS = (255, 222, 150)
QH_GREEN = (46, 124, 82)
QH_BLUE = (46, 92, 168)
QH_PURPLE = (116, 70, 168)
QH_RUG = (138, 40, 50)
QH_PARCHMENT = (232, 216, 180)
SCROLL = (244, 232, 204)
WAX_SEAL = (182, 40, 46)
TERRACOTTA = (186, 98, 66)


class Wall:
    """A flat wall's own frame: u runs along it, y is up and d goes into it from its outer face
    (d = 0 is the face, d = the thickness is its back)."""

    def __init__(self, origin, along, inward):
        self.o = V(*origin)
        self.a = norm(V(*along))
        self.n = norm(V(*inward))
        self.R = np.column_stack([self.a, UP, np.cross(self.a, UP)])

    def p(self, u, y, d=0.0):
        return self.o + self.a * u + UP * y + self.n * d

    def box(self, m, name, u0, u1, y0, y1, d0, d1, color, mat="SmoothPlastic", tr=0.0, refl=0.0):
        m.blk(name, (abs(u1 - u0), abs(y1 - y0), abs(d1 - d0)), self.p((u0 + u1) / 2, (y0 + y1) / 2, (d0 + d1) / 2),
              color, mat, R=self.R, tr=tr, refl=refl)

    def turned(self, deg):
        """The wall's frame turned by deg in its own plane (for stones round an arch)."""
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        x = self.a * c + UP * s
        y = -self.a * s + UP * c
        return np.column_stack([x, y, np.cross(x, y)])


def holed_wall(m, name, w, u0, u1, y0, y1, t, color, holes=(), mat="SmoothPlastic"):
    """Wall w from u0 to u1 and from y0 up to y1, t thick, with rectangular holes (hu0, hu1, hy0, hy1):
    as few blocks as the holes allow."""
    cuts = sorted({u0, u1} | {h[0] for h in holes} | {h[1] for h in holes})
    cuts = [c for c in cuts if u0 - 1e-6 <= c <= u1 + 1e-6]
    for a, b in zip(cuts, cuts[1:]):
        if b - a < 1e-3:
            continue
        spans = [(y0, y1)]
        for h in holes:
            if h[0] <= a + 1e-6 and h[1] >= b - 1e-6:
                left = []
                for s0, s1 in spans:
                    if h[3] <= s0 or h[2] >= s1:
                        left.append((s0, s1))
                        continue
                    if h[2] > s0:
                        left.append((s0, h[2]))
                    if h[3] < s1:
                        left.append((h[3], s1))
                spans = left
        for s0, s1 in spans:
            if s1 - s0 > 1e-3:
                w.box(m, name, a, b, s0, s1, 0, t, color, mat)


def arch_fill(m, name, w, uc, R, spring, top, t, color, n=9, stone=None, stone2=None, key=None, band=0.6,
              mat="SmoothPlastic"):
    """Fills wall w over a round-topped opening (half a circle of radius R, its middle at u = uc and
    height `spring`) up to `top`, between uc - R and uc + R (a block and a wedge for each of the n
    straight pieces of the arch). With `stone`: voussoirs round the arch on both faces (a keystone
    in the middle) and a soffit along its underside. Returns the arch's points as (u, y)."""
    pts = [(uc + R * math.cos(math.pi * k / n), spring + R * math.sin(math.pi * k / n)) for k in range(n + 1)]
    back = w.p(uc, spring, t)
    for (ua, ya), (ub, yb) in zip(pts, pts[1:]):
        lo, hi = min(ya, yb), max(ya, yb)
        if top - hi > 1e-3:
            w.box(m, name, min(ua, ub), max(ua, ub), hi, top, 0, t, color, mat)
        ul, uh = (ua, ub) if ya < yb else (ub, ua)
        tri(m, name, w.p(ul, lo), w.p(ul, hi), w.p(uh, hi), t, color, mat, inside=back)
    if stone:
        half = math.pi / n / 2
        ri = R * math.cos(half)  # (the straight pieces are this far from the middle)
        for k in range(n):
            th = math.pi * (k + 0.5) / n
            Rk = w.turned(math.degrees(th) + 90)
            is_key = key is not None and k == n // 2
            bw = band * (1.35 if is_key else 1.0)
            length = 2 * (ri + bw) * math.tan(half) + 0.03
            c_u, c_y = uc + math.cos(th) * (ri + bw / 2), spring + math.sin(th) * (ri + bw / 2)
            col = key if is_key else (stone if k % 2 == 0 else (stone2 or stone))
            proud = 0.26 if is_key else (0.2 if k % 2 == 0 else 0.16)
            for d in (-proud / 2, t + proud / 2):
                m.blk("ArchStone", (length, bw, proud), w.p(c_u, c_y, d), col, "Slate", R=Rk)
            s_u, s_y = uc + math.cos(th) * ri, spring + math.sin(th) * ri
            m.blk("ArchStone", (2 * R * math.sin(half) + 0.02, 0.12, t + 0.04), w.p(s_u, s_y, t / 2), stone, "Slate", R=Rk)
    return pts


def fan_glass(m, w, uc, R, spring, d, n, glass, bar, tr=0.35):
    """A half-round fanlight in wall w at depth d: glass in n slices, gold bars like sun rays and a
    transom bar along the bottom."""
    pts = [(uc + R * math.cos(math.pi * k / n), spring + R * math.sin(math.pi * k / n)) for k in range(n + 1)]
    c = w.p(uc, spring, d)
    for k in range(n):
        tri(m, "Fanlight", w.p(*pts[k], d), w.p(*pts[k + 1], d), c, 0.08, glass, "Glass", tr=tr, refl=0.1,
            inside=w.p(uc, spring + R / 2, d + 1))
    for k in range(1, n):
        m.rod("FanlightBar", c, w.p(*pts[k], d + 0.04), 0.12, bar, "Metal")
    m.rod("FanlightBar", w.p(uc - R, spring, d + 0.04), w.p(uc + R, spring, d + 0.04), 0.22, bar, "Metal")


def frame_y(direction, toward=(0, 0, -1)):
    """A turn whose y axis runs along `direction` and whose -z faces `toward` as well as it can."""
    y = norm(V(*direction))
    f = V(*toward)
    z = -(f - y * np.dot(f, y))
    if np.linalg.norm(z) < 1e-6:
        z = V(1, 0, 0) - y * np.dot(V(1, 0, 0), y)
    z = norm(z)
    x = np.cross(y, z)
    return np.column_stack([x, y, z])


def sun_emblem(m, c, r, color, rays=8):
    """A little gold sun on a surface facing -z: a disc and its rays."""
    c = V(*c)
    m.cyl("Emblem", 0.12, r * 1.15, c, color, "z", "Metal")
    for k in range(rays):
        a = 360 * k / rays
        p = c + V(math.cos(math.radians(a)), math.sin(math.radians(a)), 0) * (r * 0.92)
        m.blk("Emblem", (r * 0.62, r * 0.2, 0.1), p + V(0, 0, 0.02), color, "Metal", R=Rz(a))


def moon_emblem(m, c, r, color, back):
    """A crescent moon and a little four-point star on a surface facing -z (back: the colour behind)."""
    c = V(*c)
    m.cyl("Emblem", 0.12, r * 1.2, c + V(-0.1 * r, 0, 0), color, "z", "Metal")
    m.cyl("Emblem", 0.14, r * 1.02, c + V(0.18 * r, 0.12 * r, -0.03), back, "z", "Fabric")
    s = c + V(0.62 * r, 0.42 * r, -0.04)
    for a in (0, 90):
        m.blk("Emblem", (r * 0.62, r * 0.13, 0.08), s, color, "Metal", R=Rz(a + 45))
    m.ball("Emblem", r * 0.16, s + V(0, 0, -0.02), color, "Metal")


def star_emblem(m, c, r, color, inner):
    """A compass star on a surface facing -z: four long points and four short ones."""
    c = V(*c)
    for k in range(4):
        a = math.radians(90 + 90 * k)
        tip = c + V(math.cos(a), math.sin(a), 0) * r
        side = V(math.cos(a + math.pi / 2), math.sin(a + math.pi / 2), 0) * (r * 0.2)
        tri(m, "Emblem", c + side, c - side, tip, 0.08, color, "Metal", inside=c + V(0, 0, 1))
        m.blk("Emblem", (r * 0.62, r * 0.2, 0.07), c + V(math.cos(a + math.pi / 4), math.sin(a + math.pi / 4), 0) * (r * 0.3) + V(0, 0, 0.01),
              inner, "Metal", R=Rz(math.degrees(a) + 45))
    m.ball("Emblem", r * 0.3, c + V(0, 0, -0.04), inner, "Metal")


def scroll(m, name, a, b, d, color=SCROLL, ribbon=WAX_SEAL):
    """A rolled-up scroll from a to b, d thick, with a ribbon round its middle."""
    a, b = V(*a), V(*b)
    m.rod(name, a, b, d, color)
    mid = (a + b) / 2
    m.rod(name, mid - norm(b - a) * 0.06, mid + norm(b - a) * 0.06, d * 1.12, ribbon)


def wall_board(m, R, t, w, h, cy, crest, emblem, back=QH_TIMBER):
    """A board frame on a wall (built facing -z, then turned by R and moved to t): a backing plate,
    a carved frame with gold beads, a coloured crest with a gold rim and an emblem on top. The board
    the client draws on is the part named by the caller (made in questhall, in front of the plate)."""
    with m.group(R=R, t=t):
        m.blk("BoardBack", (w + 1.0, h + 1.0, 0.24), (0, cy, -0.12), back, "Wood")
        board_frame(m, w, h, cy, -0.42, 0.42)
        top = cy + h / 2 + 0.42
        m.cyl("Crest", 0.2, 1.9, (0, top + 0.55, -0.5), crest, "z", "Wood")
        m.ring("Crest", (0, top + 0.55, -0.6), 0.95, 0.14, BRASS_P, "z", 9, "Metal")
        emblem(m, (0, top + 0.55, -0.66))


def questhall():
    """The Quest Hall (front -Z, y = 0 the lawn; the hall is 24 x 16 inside its stone plinth): a
    timber-framed guild hall with a blue slate roof, a porch under its own gable with the sign
    and an emblem, an arched doorway with a sunburst fanlight and its doors standing open, banners
    either side (green for the daily quests, blue for the weekly ones), a round window in the
    gable, a cupola with the Beacon in it (the client lights it when you have quests to claim) and
    a chimney (ChimneyTop: ParkBuilder's smoke). Inside: Quill's counter and his perch, pigeonholes
    full of scrolls, a fireplace, bookshelves, a rug, trusses, a chandelier and three board frames
    (the boards the client draws on: DailyBoard, WeeklyBoard, JourneyBoard). Out front: a paved
    forecourt with a compass rose, an armillary sphere (the "Armillary" group: the client turns
    it) and the notice board (NoticeBoard: when the quests change). Desk is the unseen spot the
    prompt hangs on and the server measures from."""
    m = PModel("questhall")
    m.solid_names = {"Plinth", "Porch", "Step", "Floor", "Wall", "WallBase", "Column", "ColumnBase", "Counter",
                     "Chimney", "Hearth", "Pigeonholes", "Bookshelf", "Pedestal", "Paving", "NoticePost"}
    HW, HD, T = 12.0, 8.0, 0.8  # the walls' outer half width and half depth, and how thick they are
    FLOOR = 1.0
    # ---- the plinth, the porch floor and its steps -------------------------------------------
    m.rbox("Plinth", (26.0, 0.9, 17.6), (0, 0.45, 0), QH_STONE_D, 0.5, "Slate")
    m.blk("Porch", (13.6, 0.9, 4.0), (0, 0.45, -10.6), QH_STONE_D, "Slate")
    m.blk("Porch", (13.0, 0.06, 3.7), (0, 0.92, -10.6), QH_STONE_L, "Slate")
    m.blk("Step", (10.4, 0.6, 0.9), (0, 0.3, -13.05), QH_STONE, "Slate")
    m.blk("Step", (11.2, 0.3, 0.9), (0, 0.15, -13.85), QH_STONE, "Slate")
    m.blk("Floor", (2 * (HW - T), 0.1, 2 * (HD - T)), (0, 0.95, 0), QH_FLOOR, "WoodPlanks")
    m.blk("Floor", (6.8, 0.1, T), (0, 0.95, -HD + T / 2), QH_STONE_L, "Slate")  # (the doorstep)
    # ---- the walls ----------------------------------------------------------------------------
    front = Wall((0, 0, -HD), (1, 0, 0), (0, 0, 1))
    back = Wall((0, 0, HD), (-1, 0, 0), (0, 0, -1))
    left = Wall((-HW, 0, 0), (0, 0, 1), (1, 0, 0))
    right = Wall((HW, 0, 0), (0, 0, 1), (-1, 0, 0))
    DOOR_R, DOOR_SPRING = 3.4, 6.8
    holed_wall(m, "Wall", front, -HW, HW, 0.9, 11.2, T, QH_PLASTER, [(-DOOR_R, DOOR_R, 0.9, DOOR_SPRING + DOOR_R)])
    arch_fill(m, "Wall", front, 0, DOOR_R, DOOR_SPRING, DOOR_SPRING + DOOR_R, T, QH_PLASTER, n=9, stone=QH_STONE_L,
              stone2=QH_STONE, key=(222, 214, 198), band=0.62)
    for sx in (-1, 1):  # the door's jambs below the arch, on both faces
        u = sx * (DOOR_R + 0.31)
        for d in (-0.1, T + 0.1):
            front.box(m, "ArchStone", u - 0.31, u + 0.31, 0.9, DOOR_SPRING, d - 0.1, d + 0.1, QH_STONE_L if d < 0 else QH_STONE, "Slate")
    m.ball("ArchStone", 0.5, front.p(0, DOOR_SPRING + DOOR_R + 0.42, -0.32), BRASS_P, "Metal")  # (a gold boss on the keystone)
    fan_glass(m, front, 0, DOOR_R, DOOR_SPRING, T / 2, 9, QH_GLASS, BRASS_P)
    holed_wall(m, "Wall", back, -HW, HW, 0.9, 11.2, T, QH_PLASTER)
    WIN = (-6.6, -4.2, 3.8, 8.0)  # the side windows (u is z along the side walls)
    for w in (left, right):
        holed_wall(m, "Wall", w, -HD + T, HD - T, 0.9, 11.7, T, QH_PLASTER, [WIN])
    # the doors, standing open on the porch: planks, iron straps and a ring
    for sx in (-1, 1):
        hinge = V(sx * 3.3, 0, -HD - 0.08)
        a = math.radians(20)
        direc = V(sx * math.sin(a), 0, -math.cos(a))
        R = Ry(70 if sx > 0 else 110)
        c = hinge + direc * 1.62 + V(0, FLOOR + 2.85, 0)
        m.blk("Door", (3.24, 5.7, 0.28), c, QH_TIMBER_L, "WoodPlanks", R=R)
        for y in (-1.9, 1.9):
            m.blk("DoorStrap", (3.0, 0.22, 0.36), c + V(0, y, 0), (44, 40, 38), "Metal", R=R)
        nrm = R @ V(0, 0, 1)
        m.ring("DoorRing", c + direc * 1.1 + V(0, -0.2, 0) - nrm * sx * 0.2, 0.22, 0.07, BRASS_P, "z", 6, "Metal", R=R)
    # ---- outside: the stone base course, the timbers, the windows ----------------------------
    for u0, u1 in ((-HW - 0.18, -DOOR_R - 0.62), (DOOR_R + 0.62, HW + 0.18)):
        front.box(m, "WallBase", u0, u1, 0.9, 2.4, -0.18, 0, QH_STONE, "Slate")
        front.box(m, "WallBase", u0 - 0.06 * (u0 < 0), u1 + 0.06 * (u1 > 0), 2.4, 2.62, -0.26, 0, QH_STONE_L, "Slate")
    back.box(m, "WallBase", -HW - 0.18, HW + 0.18, 0.9, 2.4, -0.18, 0, QH_STONE, "Slate")
    back.box(m, "WallBase", -HW - 0.24, HW + 0.24, 2.4, 2.62, -0.26, 0, QH_STONE_L, "Slate")
    for w in (left, right):
        w.box(m, "WallBase", -HD - 0.18, HD + 0.18, 0.9, 2.4, -0.18, 0, QH_STONE, "Slate")
        w.box(m, "WallBase", -HD - 0.24, HD + 0.24, 2.4, 2.62, -0.26, 0, QH_STONE_L, "Slate")
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.blk("Timber", (0.62, 8.6, 0.62), (sx * HW, 6.9, sz * HD), QH_TIMBER, "Wood")
    TB = 0.14  # (how far the timbers stand out of the plaster)
    for w in (left, right):
        for u in (-2.4, 2.6):
            w.box(m, "Timber", u - 0.22, u + 0.22, 2.62, 11.0, -TB, 0, QH_TIMBER, "Wood")
        w.box(m, "Timber", -2.4, HD - 0.3, 6.4, 6.8, -TB, 0, QH_TIMBER, "Wood")
        w.box(m, "Timber", -HD - 0.3, HD + 0.3, 11.0, 11.6, -TB, 0, QH_TIMBER, "Wood")
        w.box(m, "Timber", 4.95, 5.35, 2.62, 6.4, -TB, 0, QH_TIMBER, "Wood")
        for (u0, y0), (u1, y1) in (((-2.4, 6.8), (0.1, 11.0)), ((2.6, 6.8), (0.1, 11.0)),
                                   ((2.6, 6.8), (HD - 0.3, 11.0)), ((HD - 0.3, 6.8), (2.6, 11.0))):
            m.rod("Timber", w.p(u0, y0, -TB / 2), w.p(u1, y1, -TB / 2), 0.36, QH_TIMBER, "Wood", shape="B")
        # the window: a timber frame, a stone sill, glass with a cross of glazing bars, blue shutters
        # and a window box of flowers
        u0, u1, y0, y1 = WIN
        uc = (u0 + u1) / 2
        w.box(m, "WindowFrame", u0 - 0.3, u1 + 0.3, y1, y1 + 0.42, -0.16, 0, QH_TIMBER, "Wood")
        for u in (u0 - 0.15, u1 + 0.15):
            w.box(m, "WindowFrame", u - 0.15, u + 0.15, y0, y1, -0.12, 0, QH_TIMBER, "Wood")
        w.box(m, "WindowSill", u0 - 0.4, u1 + 0.4, y0 - 0.3, y0, -0.36, 0.1, QH_STONE_L, "Slate")
        w.box(m, "Window", u0, u1, y0, y1, T / 2 - 0.04, T / 2 + 0.04, QH_GLASS, "Glass", tr=0.3, refl=0.12)
        w.box(m, "WindowBar", uc - 0.07, uc + 0.07, y0, y1, T / 2 - 0.1, T / 2 + 0.1, QH_TIMBER, "Wood")
        w.box(m, "WindowBar", u0, u1, 6.55, 6.69, T / 2 - 0.1, T / 2 + 0.1, QH_TIMBER, "Wood")
        for su, us in ((-1, u0 - 0.3), (1, u1 + 0.3)):
            w.box(m, "Shutter", us + su * 1.2, us, y0 - 0.05, y1 + 0.05, -0.2, -0.06, QH_NAVY, "Wood")
            for yy in (y0 + 0.9, y1 - 0.9):
                w.box(m, "Shutter", us + su * 1.12, us + su * 0.08, yy - 0.08, yy + 0.08, -0.26, -0.18, shade(QH_NAVY, 1.25), "Wood")
        w.box(m, "WindowBox", u0 - 0.2, u1 + 0.2, y0 - 1.05, y0 - 0.35, -0.88, -0.2, QH_TIMBER_L, "Wood")
        for k in range(4):
            uu = u0 + 0.15 + k * (u1 - u0 - 0.3) / 3
            m.ball("Flowers", 0.62, w.p(uu, y0 - 0.25, -0.56), (64, 118, 58), "Grass")
            m.ball("Flowers", 0.3, w.p(uu + 0.12, y0 - 0.02, -0.68), ((236, 90, 110), (255, 206, 80), (188, 132, 236))[k % 3])
    for u in (-4.0, 4.0):  # the back wall's timbers
        back.box(m, "Timber", u - 0.22, u + 0.22, 2.62, 11.0, -TB, 0, QH_TIMBER, "Wood")
    back.box(m, "Timber", -HW + 0.3, HW - 0.3, 6.4, 6.8, -TB, 0, QH_TIMBER, "Wood")
    for su in (-1, 1):
        for (u0, y0), (u1, y1) in (((4.0, 6.8), (HW - 0.3, 11.0)), ((HW - 0.3, 6.8), (4.0, 11.0))):
            m.rod("Timber", back.p(su * u0, y0, -TB / 2), back.p(su * u1, y1, -TB / 2), 0.36, QH_TIMBER, "Wood", shape="B")
    # the front: a beam under the gable (either side of the arch), posts at the porch's edges
    for u0, u1 in ((-HW - 0.3, -2.1), (2.1, HW + 0.3)):
        front.box(m, "Timber", u0, u1, 10.5, 11.1, -0.16, 0, QH_TIMBER, "Wood")
    for u in (-6.95, 6.95):
        front.box(m, "Timber", u - 0.22, u + 0.22, 2.62, 10.5, -TB, 0, QH_TIMBER, "Wood")
    # the banners either side of the porch: green for the daily quests (a sun), blue for the
    # weekly ones (a moon); gold rods on iron brackets, gold edging, swallow tails
    for sx, col, emb in ((-1, QH_GREEN, "sun"), (1, QH_BLUE, "moon")):
        x = sx * 9.45
        z = -HD - 0.42
        m.rod("BannerRod", (x - 1.55, 10.12, z - 0.04), (x + 1.55, 10.12, z - 0.04), 0.18, BRASS_P, "Metal")
        for e in (-1, 1):
            m.ball("BannerRod", 0.3, (x + e * 1.6, 10.12, z - 0.04), BRASS_P, "Metal")
            m.rod("BannerBracket", (x + e * 1.3, 10.12, -HD), (x + e * 1.3, 10.12, z - 0.04), 0.1, IRON, "Metal")
        m.blk("Banner", (2.5, 4.3, 0.1), (x, 7.85, z), col, "Fabric")
        for e in (-1, 1):
            xe = x + e * 1.25
            tri(m, "Banner", (xe, 5.7, z - 0.05), (x, 5.7, z - 0.05), (xe, 4.55, z - 0.05), 0.1, col, "Fabric",
                inside=(x, 5.3, z + 1))
            m.rod("BannerTrim", (xe, 10.0, z - 0.07), (xe, 4.6, z - 0.07), 0.09, BRASS_P, "Metal")
        m.blk("BannerTrim", (2.56, 0.3, 0.12), (x, 9.82, z - 0.04), BRASS_P, "Metal")
        m.blk("BannerTrim", (2.56, 0.1, 0.12), (x, 5.75, z - 0.04), BRASS_P, "Metal")
        if emb == "sun":
            sun_emblem(m, (x, 7.9, z - 0.12), 0.62, BRASS_P)
        else:
            moon_emblem(m, (x, 7.9, z - 0.12), 0.68, BRASS_P, col)
        # a flower box on the plinth under each banner
        m.blk("FlowerBox", (2.8, 0.7, 0.62), (x, 1.25, -HD - 0.36), QH_TIMBER_L, "Wood")
        for k in range(5):
            xx = x - 1.1 + k * 0.55
            m.ball("Flowers", 0.66, (xx, 1.75, -HD - 0.38), (62, 116, 56), "Grass")
            m.ball("Flowers", 0.32, (xx + 0.1, 2.05, -HD - 0.5), ((246, 246, 236), (236, 90, 110), (188, 132, 236), (255, 206, 80))[k % 4])
    # ---- the roof: blue slate, a copper ridge, a cream gable with a round window ---------------
    with m.group(R=Ry(90)):
        gable_roof(m, 17.4, -13.0, 13.0, 11.0, 20.0, 0.6, rows=4, gable_color=QH_PLASTER, roof_color=QH_UNDER,
                   shingles=(QH_SLATE, QH_SLATE_2), gable_mat="SmoothPlastic")
    gz = -8.3  # the front gable's face
    for sx in (-1, 1):
        m.rod("Barge", (sx * 13.35, 10.78, gz - 0.2), (0, 20.28, gz - 0.2), 0.56, QH_TIMBER, "Wood", shape="B")
    m.blk("Barge", (0.42, 1.5, 0.42), (0, 19.55, gz - 0.3), QH_TIMBER, "Wood")
    m.ball("Barge", 0.5, (0, 18.65, gz - 0.3), BRASS_P, "Metal")
    m.blk("Timber", (19.2, 0.5, 0.16), (0, 13.05, gz - 0.08), QH_TIMBER, "Wood")
    for sx in (-1, 1):
        m.blk("Timber", (0.44, 3.5, 0.16), (sx * 4.2, 15.05, gz - 0.08), QH_TIMBER, "Wood")
        m.rod("Timber", (sx * 4.4, 13.3, gz - 0.08), (sx * 7.3, 14.55, gz - 0.08), 0.36, QH_TIMBER, "Wood", shape="B")
    oc = V(0, 16.6, gz)
    m.cyl("Oculus", 0.06, 3.3, oc + V(0, 0, -0.03), (44, 36, 40), "z")
    m.cyl("Oculus", 0.06, 3.2, oc + V(0, 0, -0.08), QH_GLASS, "z", "Glass", tr=0.3, refl=0.15)
    m.ring("OculusRim", oc + V(0, 0, -0.14), 1.68, 0.3, BRASS_P, "z", 12, "Metal")
    for a in (0, 90):
        m.blk("OculusBar", (3.2, 0.14, 0.1), oc + V(0, 0, -0.12), BRASS_P, "Metal", R=Rz(a))
    m.cyl("Oculus", 0.06, 3.2, V(0, 16.6, -HD + 0.04), QH_GLASS, "z", "Glass", tr=0.3, refl=0.15)  # (seen from inside)
    bz = 8.3  # the back gable's face
    for sx in (-1, 1):
        m.rod("Barge", (sx * 13.35, 10.78, bz + 0.2), (0, 20.28, bz + 0.2), 0.56, QH_TIMBER, "Wood", shape="B")
        m.blk("Timber", (0.44, 4.2, 0.16), (sx * 3.2, 15.2, bz + 0.08), QH_TIMBER, "Wood")
    m.blk("Timber", (19.2, 0.5, 0.16), (0, 13.05, bz + 0.08), QH_TIMBER, "Wood")
    m.cyl("Oculus", 0.06, 2.0, V(0, 16.2, bz + 0.03), (44, 36, 40), "z")
    m.cyl("Oculus", 0.06, 1.9, V(0, 16.2, bz + 0.08), QH_GLASS, "z", "Glass", tr=0.3, refl=0.15)
    m.ring("OculusRim", V(0, 16.2, bz + 0.14), 1.02, 0.22, QH_TIMBER, "z", 10, "Wood")
    # ---- the cupola on the ridge, the Beacon in it, a verdigris roof and a weathervane ----------
    m.blk("CupolaBase", (3.0, 2.8, 3.0), (0, 19.8, 0), QH_PLASTER)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.blk("CupolaBase", (0.3, 1.6, 0.3), (sx * 1.5, 20.4, sz * 1.5), QH_TIMBER, "Wood")
    m.blk("CupolaDeck", (3.5, 0.3, 3.5), (0, 21.35, 0), QH_TIMBER, "Wood")
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.blk("CupolaPost", (0.42, 2.6, 0.42), (sx * 1.38, 22.8, sz * 1.38), QH_PLASTER)
    m.blk("Beacon", (1.5, 1.8, 1.5), (0, 22.6, 0), QH_GLASS, "Glass", tr=0.25, refl=0.1)
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.cyl("BeaconFrame", 1.9, 0.12, (sx * 0.76, 22.6, sz * 0.76), BRASS_P, mat="Metal")
    for y in (21.65, 23.55):
        m.blk("BeaconFrame", (1.7, 0.12, 1.7), (0, y, 0), BRASS_P, "Metal")
    m.blk("CupolaCornice", (3.7, 0.32, 3.7), (0, 24.26, 0), QH_TIMBER, "Wood")
    apex = V(0, 26.5, 0)
    hb = 1.95
    corners = [V(-hb, 24.42, -hb), V(hb, 24.42, -hb), V(hb, 24.42, hb), V(-hb, 24.42, hb)]
    for k in range(4):
        tri(m, "CupolaRoof", corners[k], corners[(k + 1) % 4], apex, 0.18, QH_VERDIGRIS, "Metal", inside=(0, 24.8, 0))
    m.ball("Vane", 0.5, (0, 26.62, 0), BRASS_P, "Metal")
    m.rod("Vane", (0, 26.6, 0), (0, 28.3, 0), 0.12, BRASS_P, "Metal")
    for a in (0, 90):
        m.blk("Vane", (1.5, 0.08, 0.08), (0, 27.15, 0), IRON, "Metal", R=Ry(a))
    m.rod("Vane", (-1.0, 27.8, 0), (1.0, 27.8, 0), 0.1, BRASS_P, "Metal")
    tri(m, "Vane", (1.0, 27.55, 0), (1.0, 28.05, 0), (1.45, 27.8, 0), 0.06, BRASS_P, "Metal", inside=(1.1, 27.8, 1))
    m.ell("Vane", (0.75, 0.46, 0.06), (-1.0, 27.84, 0), BRASS_P, "Metal", R=Rz(-14))
    # ---- the chimney (out through the roof's right slope) and the fireplace under it ----------
    CX, CZ = 8.3, 6.4
    m.blk("Chimney", (2.1, 16.45, 1.5), (CX, 4.95 + 16.45 / 2, CZ), QH_STONE_D, "Slate")
    for y in (17.4, 20.1):
        m.blk("Chimney", (2.3, 0.3, 1.7), (CX, y, CZ), QH_STONE, "Slate")
    m.blk("Chimney", (2.6, 0.4, 2.0), (CX, 21.6, CZ), QH_STONE_L, "Slate")
    for dx in (-0.55, 0.55):
        m.cyl("ChimneyPot", 0.9, 0.62, (CX + dx, 22.25, CZ), TERRACOTTA, mat="Slate")
        m.cyl("ChimneyPot", 0.16, 0.74, (CX + dx, 22.72, CZ), shade(TERRACOTTA, 0.9), mat="Slate")
    m.blk("ChimneyTop", (0.6, 0.2, 0.6), (CX, 22.9, CZ), (60, 60, 60), tr=1)
    for x0, x1 in ((6.4, 7.1), (9.5, 10.2)):
        m.blk("Hearth", (x1 - x0, 3.6, 1.8), ((x0 + x1) / 2, FLOOR + 1.8, 6.3), QH_STONE, "Slate")
    m.blk("Hearth", (3.8, 1.2, 1.8), (CX, FLOOR + 3.0, 6.3), QH_STONE, "Slate")
    m.blk("Firebox", (2.4, 2.4, 0.3), (CX, FLOOR + 1.2, 7.05), (52, 44, 40), "Slate")
    m.blk("Hearth", (2.4, 0.1, 1.5), (CX, FLOOR + 0.05, 6.3), (60, 50, 44), "Slate")
    m.blk("HearthStone", (4.6, 0.16, 0.9), (CX, FLOOR + 0.08, 4.95), QH_STONE_L, "Slate")
    m.blk("Mantel", (4.6, 0.34, 2.4), (CX, FLOOR + 3.77, 6.0), QH_TIMBER, "Wood")
    m.cyl("Log", 1.9, 0.5, (CX, FLOOR + 0.35, 6.45), BARK, "x", "Wood", R=Ry(8))
    m.cyl("Log", 1.9, 0.5, (CX, FLOOR + 0.35, 6.0), BARK, "x", "Wood", R=Ry(-6))
    m.cyl("Log", 1.5, 0.46, (CX, FLOOR + 0.72, 6.25), BARK_D, "z", "Wood")
    for dx, h, col in ((-0.45, 1.1, (255, 140, 40)), (0.35, 0.9, (255, 170, 60)), (0.0, 1.35, (255, 206, 90))):
        m.ell("Flame", (0.5, h, 0.45), (CX + dx, FLOOR + 0.75 + h / 2, 6.55), col, "Neon")
    # on the mantel: a gold cup between two candlesticks
    m.cyl("Cup", 0.16, 0.7, (CX, FLOOR + 4.02, 5.15), BRASS_P, mat="Metal")
    m.cyl("Cup", 0.5, 0.14, (CX, FLOOR + 4.33, 5.15), BRASS_P, mat="Metal")
    m.ell("Cup", (0.82, 0.62, 0.82), (CX, FLOOR + 4.8, 5.15), BRASS_P, "Metal")
    for sx in (-1, 1):
        m.ell("Cup", (0.14, 0.42, 0.1), (CX + sx * 0.46, FLOOR + 4.86, 5.15), BRASS_P, "Metal", R=Rz(sx * 20))
    for dx in (-1.6, 1.6):
        m.cyl("Candlestick", 0.6, 0.18, (CX + dx, FLOOR + 4.24, 5.15), BRASS_P, mat="Metal")
        m.cyl("Candlestick", 0.08, 0.42, (CX + dx, FLOOR + 3.98, 5.15), BRASS_P, mat="Metal")
        m.cyl("Candle", 0.55, 0.2, (CX + dx, FLOOR + 4.8, 5.15), (250, 244, 230))
        m.ell("Flame", (0.12, 0.24, 0.12), (CX + dx, FLOOR + 5.2, 5.15), (255, 196, 100), "Neon")
    # ---- the porch: timber posts on stone feet, a frieze with the sign, its own gable roof ------
    for sx in (-1, 1):
        x = sx * 5.8
        m.blk("ColumnBase", (1.45, 0.6, 1.45), (x, 1.2, -11.6), QH_STONE, "Slate")
        m.blk("ColumnBase", (1.2, 0.14, 1.2), (x, 1.57, -11.6), QH_STONE_L, "Slate")
        m.rbox("Column", (0.92, 6.6, 0.92), (x, 4.9, -11.6), QH_TIMBER, 0.2, "Wood")
        m.blk("Column", (1.02, 0.2, 1.02), (x, 7.55, -11.6), BRASS_P, "Metal")
        m.blk("Column", (1.3, 0.4, 1.3), (x, 8.4, -11.6), QH_TIMBER_L, "Wood")
        m.rod("Brace", (x - sx * 0.42, 6.9, -11.6), (x - sx * 1.75, 8.62, -11.6), 0.34, QH_TIMBER, "Wood", shape="B")
        m.blk("PorchBeam", (0.62, 1.0, 3.3), (x, 9.1, -9.95), QH_TIMBER, "Wood")
    m.blk("PorchBeam", (13.8, 1.4, 0.8), (0, 9.3, -11.9), QH_TIMBER, "Wood")
    m.blk("PorchBeam", (14.0, 0.18, 0.9), (0, 10.0, -11.9), shade(QH_TIMBER, 1.2), "Wood")
    m.blk("Sign", (9.4, 1.06, 0.12), (0, 9.3, -12.36), QH_NAVY, "Wood")
    for y in (8.7, 9.9):
        m.cyl("SignTrim", 9.7, 0.12, (0, y, -12.4), BRASS_P, "x", "Metal")
    for sx in (-1, 1):
        m.cyl("SignTrim", 1.32, 0.12, (sx * 4.8, 9.3, -12.4), BRASS_P, "y", "Metal")
        m.ball("SignTrim", 0.3, (sx * 4.8, 9.3, -12.46), BRASS_P, "Metal")
    with m.group(R=Ry(90), t=(0, 0, -10.55)):
        gable_roof(m, 4.5, -7.0, 7.0, 10.0, 14.0, 0.45, rows=2, gable_color=QH_NAVY, roof_color=QH_UNDER,
                   shingles=(QH_SLATE, QH_SLATE_2), ends=(1,))
    pz = -12.4  # the porch gable's face
    for sx in (-1, 1):
        m.rod("Barge", (sx * 7.25, 9.85, pz - 0.18), (0, 14.24, pz - 0.18), 0.42, QH_TIMBER, "Wood", shape="B")
    # the hall's emblem in the porch gable: a purple roundel with a gold rim, a scroll and a quill
    ec = V(0, 11.75, pz)
    m.cyl("Emblem", 0.16, 2.5, ec + V(0, 0, -0.08), QH_PURPLE, "z", "Wood")
    m.ring("Emblem", ec + V(0, 0, -0.18), 1.26, 0.22, BRASS_P, "z", 11, "Metal")
    scroll(m, "Emblem", ec + V(-0.95, -0.25, -0.3), ec + V(0.95, -0.25, -0.3), 0.42, SCROLL, BRASS_P)
    m.add("E", "Emblem", (0.14, 1.75, 0.42), ec + V(0.15, 0.32, -0.42), (250, 250, 244), "SmoothPlastic", frame_y((0.55, 1, 0)))
    m.rod("Emblem", ec + V(-0.28, -0.42, -0.42), ec + V(-0.05, 0.0, -0.42), 0.08, BRASS_P, "Metal")
    # the chain for the porch's hanging lantern (ParkBuilder hangs the lantern on it)
    m.rod("LanternHook", (0, 13.9, -10.4), (0, 8.8, -10.4), 0.08, IRON, "Metal")
    m.ring("LanternHook", (0, 8.73, -10.4), 0.14, 0.06, IRON, "x", 6, "Metal")
    # iron brackets for the two lanterns either side of the door
    for sx in (-1, 1):
        x = sx * 4.95
        m.blk("LanternHook", (0.5, 0.7, 0.12), (x, 6.6, -HD - 0.06), IRON, "Metal")
        m.rod("LanternHook", (x, 6.85, -HD - 0.1), (x, 6.85, -HD - 0.95), 0.12, IRON, "Metal")
        m.rod("LanternHook", (x, 6.45, -HD - 0.1), (x, 6.85, -HD - 0.6), 0.08, IRON, "Metal")
        m.rod("LanternHook", (x, 6.85, -HD - 0.92), (x, 6.55, -HD - 0.92), 0.07, IRON, "Metal")
    # ---- inside: wainscot, the counter and the perch -----------------------------------------
    PAN = (106, 74, 52)
    for w, spans in ((left, ((-HD + T, HD - T),)), (right, ((-HD + T, HD - T),)),
                     (back, ((-HW + T, -4.1), (4.1, 6.3))), (front, ((-HW + T, -DOOR_R - 0.62), (DOOR_R + 0.62, HW - T)))):
        for u0, u1 in spans:
            w.box(m, "Wainscot", u0, u1, FLOOR, 2.7, T, T + 0.1, PAN, "Wood")
            w.box(m, "Wainscot", u0, u1, 2.7, 2.9, T, T + 0.16, QH_TIMBER, "Wood")
    TOP = (70, 46, 34)
    m.blk("Counter", (8.4, 3.2, 1.6), (0, FLOOR + 1.6, 2.8), QH_TIMBER_L, "Wood")
    m.blk("Counter", (8.6, 0.3, 1.7), (0, FLOOR + 0.15, 2.8), QH_TIMBER, "Wood")
    for x in (-2.75, 0, 2.75):
        m.blk("CounterPanel", (2.3, 2.1, 0.1), (x, FLOOR + 1.85, 1.97), QH_TIMBER, "Wood")
        m.blk("CounterPanel", (1.9, 1.7, 0.06), (x, FLOOR + 1.85, 1.9), shade(QH_TIMBER_L, 1.06), "Wood")
    sun_emblem(m, (0, FLOOR + 1.85, 1.84), 0.42, BRASS_P)
    m.blk("CounterTop", (9.0, 0.3, 2.0), (0, FLOOR + 3.35, 2.8), TOP, "Wood", refl=0.05)
    m.cyl("CounterTop", 9.0, 0.14, (0, FLOOR + 3.33, 1.78), BRASS_P, "x", "Metal")
    for sx in (-1, 1):  # the counter's two wings, turned back towards the wall
        with m.group(R=Ry(-35 * sx), t=(sx * 4.2, 0, 2.8)):
            m.blk("Counter", (2.4, 3.2, 1.6), (sx * 1.2, FLOOR + 1.6, 0), QH_TIMBER_L, "Wood")
            m.blk("Counter", (2.5, 0.3, 1.7), (sx * 1.2, FLOOR + 0.15, 0), QH_TIMBER, "Wood")
            m.blk("CounterPanel", (1.7, 2.1, 0.1), (sx * 1.25, FLOOR + 1.85, -0.83), QH_TIMBER, "Wood")
            m.blk("CounterTop", (2.6, 0.3, 2.0), (sx * 1.25, FLOOR + 3.35, 0), TOP, "Wood", refl=0.05)
        m.cyl("Counter", 3.2, 1.9, (sx * 4.2, FLOOR + 1.6, 2.8), QH_TIMBER_L, mat="Wood")
        m.cyl("CounterTop", 0.32, 2.2, (sx * 4.2, FLOOR + 3.36, 2.8), TOP, mat="Wood")
    ct = FLOOR + 3.5  # the counter top
    # on it: the big quest ledger, an ink pot and a quill, a brass bell, scrolls and a candle
    m.blk("Ledger", (1.9, 0.12, 1.3), (-1.7, ct + 0.06, 2.75), (120, 44, 40), "Fabric", R=Ry(8))
    for sx in (-1, 1):
        m.blk("Ledger", (0.86, 0.1, 1.16), (-1.7 + sx * 0.44, ct + 0.17, 2.75), (248, 240, 220), R=Ry(8) @ Rz(-sx * 5))
    m.blk("Ledger", (0.06, 0.02, 0.9), (-1.6, ct + 0.24, 2.6), WAX_SEAL, R=Ry(8))
    m.cyl("InkPot", 0.38, 0.46, (1.5, ct + 0.19, 2.45), (36, 40, 56), mat="Glass", refl=0.2)
    m.cyl("InkPot", 0.1, 0.24, (1.5, ct + 0.43, 2.45), (36, 40, 56))
    m.add("E", "QuillPen", (0.1, 1.5, 0.4), (1.62, ct + 0.98, 2.5), (250, 250, 244), "SmoothPlastic", frame_y((0.25, 1, 0.15)))
    m.cyl("Bell", 0.08, 0.6, (2.9, ct + 0.04, 2.25), (60, 50, 44), mat="Wood")
    m.ell("Bell", (0.56, 0.46, 0.56), (2.9, ct + 0.2, 2.25), BRASS_P, "Metal")
    m.ball("Bell", 0.14, (2.9, ct + 0.46, 2.25), BRASS_P, "Metal")
    for (a, b) in (((-3.95, 0.21, 2.6), (-2.95, 0.21, 2.6)), ((-3.95, 0.21, 3.05), (-2.95, 0.21, 3.05)), ((-3.9, 0.6, 2.82), (-3.0, 0.6, 2.82))):
        scroll(m, "Scroll", V(a[0], ct + a[1], a[2]), V(b[0], ct + b[1], b[2]), 0.42)
    m.cyl("Candlestick", 0.1, 0.5, (3.6, ct + 0.05, 3.25), BRASS_P, mat="Metal")
    m.cyl("Candle", 0.6, 0.2, (3.6, ct + 0.4, 3.25), (250, 244, 230))
    m.ell("Flame", (0.12, 0.24, 0.12), (3.6, ct + 0.82, 3.25), (255, 196, 100), "Neon")
    # Quill's perch behind the counter (ParkBuilder stands Quill on it: the top is at y 4.6)
    m.cyl("Perch", 0.24, 1.6, (0, FLOOR + 0.12, 4.8), QH_TIMBER, mat="Wood")
    m.cyl("Perch", 3.38, 0.42, (0, FLOOR + 1.85, 4.8), QH_TIMBER_L, mat="Wood")
    m.cyl("Perch", 2.6, 0.36, (0, 4.42, 4.8), QH_TIMBER_L, "x", "Wood")
    for sx in (-1, 1):
        m.ball("Perch", 0.42, (sx * 1.32, 4.42, 4.8), BRASS_P, "Metal")
    # ---- the pigeonholes behind Quill: a wall of scrolls --------------------------------------
    PX0, PX1, PY0, PY1 = -3.8, 3.8, FLOOR, 9.2
    m.blk("Pigeonholes", (PX1 - PX0, PY1 - PY0, 0.12), (0, (PY0 + PY1) / 2, 7.12), (70, 48, 36), "Wood")
    for x in (PX0, PX1):
        m.blk("Pigeonholes", (0.3, PY1 - PY0, 0.9), (x, (PY0 + PY1) / 2, 6.75), QH_TIMBER, "Wood")
    m.blk("Pigeonholes", (PX1 - PX0 + 0.5, 0.5, 1.0), (0, PY1 + 0.1, 6.7), QH_TIMBER, "Wood")
    m.blk("Pigeonholes", (PX1 - PX0 + 0.3, 1.1, 0.9), (0, PY0 + 0.55, 6.75), QH_TIMBER, "Wood")
    cols, rows = 6, 5
    ya, yb = PY0 + 1.1, PY1 - 0.15
    cw = (PX1 - PX0 - 0.3) / cols
    rh = (yb - ya) / rows
    for c in range(1, cols):
        x = PX0 + 0.15 + c * cw
        m.blk("Pigeonholes", (0.12, yb - ya, 0.82), (x, (ya + yb) / 2, 6.75), QH_TIMBER_L, "Wood")
    for r in range(1, rows):
        y = ya + r * rh
        m.blk("Pigeonholes", (PX1 - PX0 - 0.3, 0.12, 0.82), (0, y, 6.75), QH_TIMBER_L, "Wood")
    rng = np.random.default_rng(7)
    for c in range(cols):
        for r in range(rows):
            if rng.random() < 0.28:
                continue
            x = PX0 + 0.15 + (c + 0.5) * cw
            y = ya + r * rh + 0.26
            n = 1 + int(rng.random() < 0.3)
            for k in range(n):
                dx = (k - (n - 1) / 2) * 0.36
                seal = (WAX_SEAL, (54, 96, 170), (52, 130, 84), BRASS_P)[int(rng.integers(0, 4))]
                scroll(m, "Scroll", (x + dx, y + k * 0.05, 6.35), (x + dx, y + k * 0.05, 7.05), 0.34, SCROLL, seal)
    m.cyl("Plaque", 0.12, 1.9, (0, PY1 + 0.75, 6.12), QH_PURPLE, "z", "Wood")
    m.ring("Plaque", (0, PY1 + 0.75, 6.04), 0.95, 0.14, BRASS_P, "z", 9, "Metal")
    star_emblem(m, (0, PY1 + 0.75, 5.98), 0.66, BRASS_P, shade(QH_PURPLE, 1.3))
    # ---- the boards (the client draws your quests on them) and their frames -------------------
    BOARD_Y = 5.5
    wall_board(m, Ry(-90), (-HW + T, 0, 1.6), 7.6, 5.4, BOARD_Y, QH_GREEN, lambda mm, c: sun_emblem(mm, c, 0.44, BRASS_P))
    wall_board(m, Ry(90), (HW - T, 0, 1.6), 7.6, 5.4, BOARD_Y, QH_BLUE, lambda mm, c: moon_emblem(mm, c, 0.48, BRASS_P, QH_BLUE))
    wall_board(m, I3, (-8.0, 0, HD - T), 4.6, 4.6, BOARD_Y, QH_PURPLE, lambda mm, c: star_emblem(mm, c, 0.55, BRASS_P, QH_PURPLE))
    with m.group(R=Ry(-90), t=(-HW + T, 0, 1.6)):
        m.blk("DailyBoard", (7.6, 5.4, 0.12), (0, BOARD_Y, -0.3), QH_PARCHMENT)
    with m.group(R=Ry(90), t=(HW - T, 0, 1.6)):
        m.blk("WeeklyBoard", (7.6, 5.4, 0.12), (0, BOARD_Y, -0.3), QH_PARCHMENT)
    with m.group(t=(-8.0, 0, HD - T)):
        m.blk("JourneyBoard", (4.6, 4.6, 0.12), (0, BOARD_Y, -0.3), QH_PARCHMENT)
    # iron brackets for the lanterns by the windows (ParkBuilder hangs the lanterns)
    for sx in (-1, 1):
        x = sx * (HW - T)
        m.rod("LanternHook", (x, 7.9, -3.25), (x - sx * 0.9, 7.9, -3.25), 0.12, IRON, "Metal")
        m.rod("LanternHook", (x, 7.4, -3.25), (x - sx * 0.6, 7.9, -3.25), 0.08, IRON, "Metal")
        m.rod("LanternHook", (x - sx * 0.88, 7.9, -3.25), (x - sx * 0.88, 7.6, -3.25), 0.07, IRON, "Metal")
    # ---- bookshelves either side of the door ---------------------------------------------------
    BOOKS = ((140, 40, 46), (46, 86, 150), (52, 116, 76), (196, 150, 64), (106, 64, 132), (176, 92, 50), (60, 60, 72))
    for sx in (-1, 1):
        x0, x1 = sx * 5.0, sx * 8.8
        xa, xb = min(x0, x1), max(x0, x1)
        z0 = -HD + T + 0.18  # (in front of the wainscot)
        m.blk("Bookshelf", (xb - xa, 6.2, 0.1), ((xa + xb) / 2, FLOOR + 3.1, z0 + 0.05), (70, 48, 36), "Wood")
        for x in (xa, xb):
            m.blk("Bookshelf", (0.24, 6.4, 1.0), (x, FLOOR + 3.2, z0 + 0.5), QH_TIMBER, "Wood")
        m.blk("Bookshelf", (xb - xa + 0.4, 0.3, 1.1), ((xa + xb) / 2, FLOOR + 6.45, z0 + 0.52), QH_TIMBER, "Wood")
        for k in range(4):
            y = FLOOR + 0.25 + k * 1.55
            m.blk("Bookshelf", (xb - xa, 0.16, 0.96), ((xa + xb) / 2, y, z0 + 0.5), QH_TIMBER_L, "Wood")
            if k < 3:
                x = xa + 0.2
                j = 0
                while x < xb - 0.45:
                    wbook = 0.22 + 0.1 * ((j * 7 + k * 3 + (sx > 0)) % 3)
                    hbook = 0.95 + 0.12 * ((j * 5 + k) % 4)
                    lean = 0 if (j + k) % 6 else 12
                    m.blk("Book", (wbook, hbook, 0.72), (x + wbook / 2, y + 0.08 + hbook / 2, z0 + 0.52), BOOKS[(j * 3 + k * 2 + (sx > 0) * 4) % len(BOOKS)],
                          R=Rz(lean))
                    x += wbook + (0.05 if lean == 0 else 0.25)
                    j += 1
    # ---- the rug, the trusses and the chandelier --------------------------------------------
    m.blk("Rug", (8.0, 0.06, 6.4), (0, FLOOR + 0.03, -1.8), QH_RUG, "Fabric")
    m.blk("Rug", (7.4, 0.07, 5.8), (0, FLOOR + 0.035, -1.8), shade(QH_RUG, 0.8), "Fabric")
    m.blk("Rug", (6.9, 0.08, 5.3), (0, FLOOR + 0.04, -1.8), QH_RUG, "Fabric")
    m.blk("Rug", (2.6, 0.09, 2.6), (0, FLOOR + 0.045, -1.8), BRASS_P, "Fabric", R=Ry(45))
    m.blk("Rug", (2.6, 0.095, 2.6), (0, FLOOR + 0.048, -1.8), (236, 214, 160), "Fabric")
    m.blk("Rug", (1.3, 0.1, 1.3), (0, FLOOR + 0.05, -1.8), QH_NAVY, "Fabric", R=Ry(45))
    for z in (-4.6, 4.6):
        m.blk("Truss", (2 * HW - 0.4, 0.6, 0.6), (0, 11.3, z), QH_TIMBER, "Wood")
        m.blk("Truss", (0.5, 7.6, 0.5), (0, 15.4, z), QH_TIMBER, "Wood")
        for sx in (-1, 1):
            m.rod("Truss", (sx * 0.25, 11.9, z), (sx * 6.0, 15.4, z), 0.42, QH_TIMBER, "Wood", shape="B")
    m.blk("Truss", (0.7, 0.7, 2 * HD + 0.2), (0, 19.25, 0), QH_TIMBER, "Wood")
    for sx in (-1, 1):
        m.blk("Truss", (0.5, 0.5, 2 * HD), (sx * 6.4, 15.25, 0), QH_TIMBER, "Wood", R=Rz(-sx * 34.7))
    chc = V(0, 13.4, -1.8)  # the chandelier's middle
    m.ring("Chandelier", chc, 2.2, 0.2, IRON, "y", 12, "Metal")
    m.ring("Chandelier", chc + V(0, 0.5, 0), 1.0, 0.14, IRON, "y", 7, "Metal")
    for k in range(8):
        a = 2 * math.pi * k / 8
        p = chc + V(math.sin(a) * 2.2, 0, math.cos(a) * 2.2)
        m.cyl("Chandelier", 0.12, 0.42, p + V(0, 0.12, 0), BRASS_P, mat="Metal")
        m.cyl("Candle", 0.5, 0.2, p + V(0, 0.42, 0), (250, 244, 230))
        m.ell("Flame", (0.13, 0.26, 0.13), p + V(0, 0.82, 0), (255, 200, 110), "Neon")
        if k % 2 == 0:
            m.rod("Chandelier", p + V(0, 0.1, 0), chc + V(0, 2.2, 0), 0.07, IRON, "Metal")
    m.rod("Chandelier", chc + V(0, 2.2, 0), V(0, 18.9, -1.8), 0.1, IRON, "Metal")
    m.ball("Chandelier", 0.5, chc + V(0, 2.2, 0), BRASS_P, "Metal")
    m.ball("Chandelier", 0.42, chc + V(0, -0.35, 0), BRASS_P, "Metal")
    m.blk("ChandelierLight", (0.4, 0.4, 0.4), chc + V(0, 0.6, 0), (255, 220, 160), tr=1)
    # ---- the spot the prompt hangs on (unseen, over the middle of the counter) ----------------
    m.blk("Desk", (1.0, 1.0, 1.0), (0, FLOOR + 3.4, 1.6), (255, 255, 255), tr=1)
    m.blk("FireSpot", (1.0, 0.4, 0.6), (CX, FLOOR + 0.6, 6.35), (255, 140, 60), tr=1)
    # ---- out front: the forecourt, a compass rose, an armillary sphere, the notice board -------
    FC = V(0, 0, -21.0)  # the forecourt's middle
    FLAG, FLAG_D = (204, 196, 180), (170, 162, 148)
    m.cyl("Paving", 0.5, 20.4, FC + V(0, -0.13, 0), FLAG_D, mat="Slate")
    m.cyl("Paving", 0.5, 19.6, FC + V(0, -0.1, 0), FLAG, mat="Slate")
    m.blk("Paving", (19.6, 0.5, 7.4), (0, -0.1, -17.3), FLAG, "Slate")
    m.blk("Paving", (20.4, 0.44, 7.4), (0, -0.13, -17.3), FLAG_D, "Slate")
    m.cyl("Paving", 0.1, 13.4, FC + V(0, 0.14, 0), FLAG_D, mat="Slate")
    m.cyl("Paving", 0.1, 12.8, FC + V(0, 0.16, 0), shade(FLAG, 1.04), mat="Slate")
    m.cyl("Paving", 0.1, 9.2, FC + V(0, 0.18, 0), FLAG_D, mat="Slate")
    m.cyl("Paving", 0.1, 8.6, FC + V(0, 0.2, 0), MARBLE_W, mat="Marble")
    for k in range(8):
        a = math.radians(45 * k)
        L = 4.0 if k % 2 == 0 else 2.5
        tip = FC + V(math.sin(a) * L, 0.26, math.cos(a) * L)
        for half in (-1, 1):
            side = FC + V(math.sin(a + half * math.pi / 4) * 0.95, 0.26, math.cos(a + half * math.pi / 4) * 0.95)
            col = (QH_NAVY if half < 0 else shade(QH_NAVY, 1.6)) if k % 2 == 0 else (BRASS_P if half < 0 else shade(BRASS_P, 0.8))
            tri(m, "Compass", FC + V(0, 0.26, 0), tip, side, 0.06, col, "Slate", inside=FC + V(0, -1, 0))
    m.ring("Compass", FC + V(0, 0.27, 0), 3.0, 0.12, BRASS_P, "y", 16, "Metal")
    # the armillary sphere on its pedestal (the "Armillary" group turns slowly)
    m.blk("Pedestal", (2.0, 0.4, 2.0), FC + V(0, 0.45, 0), QH_STONE, "Slate")
    m.cyl("Pedestal", 0.5, 1.5, FC + V(0, 0.9, 0), QH_STONE_L, mat="Marble")
    m.ell("Pedestal", (1.2, 1.6, 1.2), FC + V(0, 1.85, 0), QH_STONE_L, "Marble")
    m.cyl("Pedestal", 0.9, 0.62, FC + V(0, 2.8, 0), QH_STONE_L, mat="Marble")
    m.cyl("Pedestal", 0.26, 1.3, FC + V(0, 3.32, 0), QH_STONE, mat="Marble")
    m.cyl("Pedestal", 0.12, 1.1, FC + V(0, 3.52, 0), BRASS_P, mat="Metal")
    sc = FC + V(0, 5.0, 0)
    with m.grouped("Armillary"):
        m.ball("Globe", 0.95, sc, (64, 120, 196), "SmoothPlastic")
        m.ell("Globe", (0.5, 0.36, 0.3), sc + V(0.2, 0.18, -0.34), (96, 170, 96))
        m.ell("Globe", (0.34, 0.42, 0.3), sc + V(-0.32, -0.12, -0.28), (96, 170, 96))
        m.ring("Ring", sc, 1.25, 0.12, BRASS_P, "z", 11, "Metal")
        m.ring("Ring", sc, 1.25, 0.12, BRASS_P, "y", 11, "Metal")
        m.ring("Ring", sc, 1.1, 0.1, BRASS_P, "y", 10, "Metal", R=Rx(23.5))
        m.rod("Ring", sc + Rz(-23.5) @ V(0, -1.7, 0), sc + Rz(-23.5) @ V(0, 1.7, 0), 0.08, BRASS_P, "Metal")
        for e in (-1, 1):
            m.ball("Ring", 0.2, sc + Rz(-23.5) @ V(0, 1.72 * e, 0), BRASS_P, "Metal")
    m.rod("Pedestal", FC + V(0, 3.6, 0), sc + V(0, -1.25, 0), 0.16, BRASS_P, "Metal")
    m.ell("Pedestal", (0.9, 0.24, 0.9), FC + V(0, 3.68, 0), BRASS_P, "Metal")
    # the notice board on the forecourt's left, turned towards the path
    with m.group(R=Ry(-40), t=(-8.4, 0, -25.6)):
        for sx in (-1, 1):
            m.blk("NoticePost", (0.5, 5.9, 0.5), (sx * 2.2, 2.95, 0), QH_TIMBER, "Wood")
            m.blk("NoticePost", (0.8, 0.5, 0.8), (sx * 2.2, 0.25, 0), QH_STONE, "Slate")
        m.blk("NoticeBack", (4.5, 3.0, 0.24), (0, 3.9, 0.05), QH_TIMBER_L, "Wood")
        m.blk("NoticeBoard", (4.1, 2.6, 0.1), (0, 3.9, -0.1), QH_PARCHMENT)
        for y in (2.38, 5.42):
            m.cyl("NoticeTrim", 4.7, 0.16, (0, y, -0.12), BRASS_P, "x", "Metal")
        gable_roof(m, 5.4, -0.8, 0.8, 5.9, 6.9, 0.22, rows=1, gable_color=QH_NAVY, roof_color=QH_UNDER,
                   shingles=(QH_SLATE, QH_SLATE_2))
    return m


OWL = (150, 104, 66)
OWL_D = (110, 74, 48)
OWL_L = (190, 146, 100)
OWL_FACE = (238, 214, 172)
OWL_RIM = (122, 82, 52)
OWL_BELLY = (244, 230, 200)
OWL_EYE = (255, 184, 48)
OWL_BEAK = (228, 152, 58)
OWL_FOOT = (236, 176, 70)
OWL_SCARF = (40, 66, 124)


def questowl():
    """Quill, the Quest Hall's keeper: a round brown owl standing on his perch (y = 0 is where his
    feet grip it), with a cream face, big amber eyes behind round gold spectacles, ear tufts, a
    quill pen tucked behind his right tuft and a navy scarf with a gold pin. The "Head" group turns
    (round its Neck part, unseen); the Lid parts (unseen) are his eyelids: the client shows them to
    blink."""
    m = PModel("questowl")
    # the body, the belly with its little chevrons, the wings and the tail
    m.ell("Body", (2.2, 2.3, 2.0), (0, 1.25, 0.05), OWL)
    m.ell("Belly", (1.6, 1.8, 0.8), (0, 1.12, -0.62), OWL_BELLY)
    for (x, y) in ((-0.3, 1.62), (0.3, 1.62), (-0.48, 1.18), (0.0, 1.22), (0.48, 1.18), (-0.28, 0.76), (0.28, 0.76)):
        q = 1 - (x / 0.8) ** 2 - ((y - 1.12) / 0.9) ** 2
        z = -0.62 - 0.4 * math.sqrt(max(q, 0.05)) + 0.015
        for s in (-1, 1):
            m.ell("Speckle", (0.17, 0.07, 0.05), (x + s * 0.065, y - 0.02, z), OWL_D, R=Rz(s * 28))
    for sx in (-1, 1):
        m.ell("Wing", (0.56, 1.9, 1.5), (sx * 1.0, 1.28, 0.14), OWL_D, R=Rz(-sx * 9))
        m.ell("Wing", (0.6, 0.95, 1.3), (sx * 1.03, 1.86, 0.05), OWL, R=Rz(-sx * 9))
        for k in range(3):
            m.ell("WingTip", (0.3, 0.72, 0.34), (sx * (1.02 + k * 0.03), 0.42 + k * 0.05, 0.42 + k * 0.26),
                  shade(OWL_D, 0.86), R=Rz(-sx * 12) @ Rx(18))
        for k in range(3):
            m.ell("Speckle", (0.08, 0.2, 0.22), (sx * 1.29, 1.55 - k * 0.42, 0.05 + k * 0.08), OWL_L, R=Rz(-sx * 9))
    m.ell("Tail", (0.9, 0.3, 0.95), (0, 0.32, 0.98), OWL_D, R=Rx(28))
    # feet gripping the perch
    for sx in (-1, 1):
        for k, dx in enumerate((-0.18, 0.0, 0.18)):
            base = V(sx * 0.42 + dx, 0.1, -0.42)
            m.ell("Toe", (0.16, 0.16, 0.44), base + V(0, -0.02, -0.12), OWL_FOOT, R=Rx(32))
            m.ell("Claw", (0.1, 0.14, 0.14), base + V(0, -0.2, -0.3), (64, 56, 52), R=Rx(70))
    # the scarf, its knot and two tails, and a gold pin
    m.ring("Scarf", (0, 2.2, -0.02), 0.8, 0.36, OWL_SCARF, "y", 12)
    m.ball("Scarf", 0.46, (0.26, 2.12, -0.86), OWL_SCARF)
    m.ell("Scarf", (0.3, 0.72, 0.14), (0.36, 1.72, -0.95), shade(OWL_SCARF, 1.12), R=Rz(14))
    m.ell("Scarf", (0.28, 0.62, 0.14), (0.12, 1.74, -0.97), OWL_SCARF, R=Rz(-10))
    m.ball("Pin", 0.2, (0.27, 2.14, -1.1), BRASS_P, "Metal")
    m.ell("Pin", (0.3, 0.3, 0.06), (0.27, 2.14, -1.08), (255, 236, 160), "Neon")
    # the head (it turns round the Neck)
    with m.grouped("Head"):
        hc = V(0, 2.88, -0.08)
        m.blk("Neck", (0.2, 0.2, 0.2), (0, 2.2, -0.05), (0, 0, 0), tr=1)
        m.ell("Head", (2.1, 1.76, 1.86), hc, OWL)
        for sx in (-1, 1):
            m.ell("FaceRim", (1.18, 1.3, 0.34), (sx * 0.42, 2.86, -0.78), OWL_RIM)
            m.ell("Face", (1.04, 1.16, 0.36), (sx * 0.4, 2.86, -0.86), OWL_FACE)
            e = V(sx * 0.4, 2.93, -1.0)
            m.ball("Eye", 0.62, e, OWL_EYE)
            m.ell("Pupil", (0.36, 0.36, 0.12), e + V(0, 0, -0.27), (24, 20, 22))
            m.ball("Glint", 0.11, e + V(0.08 * sx + 0.04, 0.09, -0.32), (255, 255, 255))
            m.ell("Lid", (0.7, 0.7, 0.42), e + V(0, 0, -0.14), OWL, tr=1)
            m.ell("Brow", (0.72, 0.3, 0.44), e + V(0.02 * sx, 0.27, -0.12), OWL_RIM, R=Rz(-sx * 9))
            m.ring("Specs", e + V(0, 0, -0.34), 0.37, 0.06, BRASS_P, "z", 10, "Metal")
            m.rod("Specs", e + V(sx * 0.37, 0.04, -0.34), e + V(sx * 0.62, 0.12, -0.05), 0.05, BRASS_P, "Metal")
            m.ell("Tuft", (0.36, 0.98, 0.32), (sx * 0.72, 3.72, -0.18), OWL_D, R=Rz(-sx * 28) @ Rx(-8))
            m.ell("Tuft", (0.2, 0.6, 0.2), (sx * 0.8, 3.95, -0.24), OWL, R=Rz(-sx * 28) @ Rx(-8))
        m.rod("Specs", V(-0.03, 2.97, -1.34), V(0.03, 2.97, -1.34), 0.06, BRASS_P, "Metal")
        m.ell("Beak", (0.3, 0.5, 0.36), (0, 2.6, -1.1), OWL_BEAK, R=Rx(-14))
        m.ell("Beak", (0.18, 0.22, 0.2), (0, 2.38, -1.18), shade(OWL_BEAK, 0.86), R=Rx(-30))
        for (x, y) in ((-0.38, 3.62), (0.0, 3.72), (0.38, 3.62), (-0.2, 3.45), (0.2, 3.45)):
            m.ell("Speckle", (0.16, 0.06, 0.16), (x, y, -0.2), OWL_L)
        # the quill pen tucked behind his right tuft
        d = norm(V(0.42, 1, 0.55))
        base = V(0.72, 3.0, 0.42)
        m.add("E", "Pen", (0.1, 1.6, 0.44), base + d * 0.8, (250, 250, 244), "SmoothPlastic", frame_y(d, (1, 0, 0)))
        m.rod("Pen", base - d * 0.2, base + d * 1.55, 0.05, (210, 200, 180))
        m.rod("Pen", base - d * 0.42, base - d * 0.18, 0.08, BRASS_P, "Metal")
    return m


PROPS = [shrine, altar, lantern, bollard, lanternpost, birdbath, litter_bin, topiary, cat, logseat, firepit, dueltable, basket, hall, leaderboard, tcterrace, easel, lectern, tcsign, tptable, porchcolumn, porchurn, questhall, questowl]


def emit(models):
    out = ["-- Generated by gen_park.py. Do not edit by hand.",
           "-- The park's part-made props. Each part: { group, shape, name, sizeX, sizeY, sizeZ, posX, posY, posZ,",
           "-- rotX, rotY, rotZ (degrees), R, G, B, material, transparency, reflectance, solid }",
           "-- shape: B block, S ball, C cylinder (along X), E ellipsoid (block with a sphere mesh), W wedge.",
           "-- group: the Model inside the prop the part goes in (\"\" for the prop's own Model).",
           "-- Props stand on y = 0 and face -Z. ParkBuilder's propFrom builds them.",
           "return {"]
    for m in models:
        out.append(f"\t{m.id} = {{")
        for p in m.parts:
            ex, ey, ez = euler_xyz(p["R"])
            solid = p["name"] in m.solid_names and p["shape"] != "E"
            vals = [f'"{p.get("group", "")}"', f'"{p["shape"]}"', f'"{p["name"]}"'] + [str(r3(v)) for v in p["size"]] + \
                   [str(r3(v)) for v in p["pos"]] + [str(r3(v)) for v in (ex, ey, ez)] + [str(c) for c in p["color"]] + \
                   [f'"{p["mat"]}"', str(r3(p["tr"])), str(r3(p["refl"])), "true" if solid else "false"]
            out.append("\t\t{" + ", ".join(vals) + "},")
        out.append("\t},")
    out.append("}")
    return "\n".join(out) + "\n"


def build():
    models = [fn() for fn in PROPS]
    for m in models:
        for p in m.parts:
            assert p["mat"] in MATERIALS, f"{m.id}: unknown material {p['mat']}"
            if min(p["size"]) < 0.02:
                print(f"WARN {m.id}: part {p['name']} is very thin {p['size']}")
    return models


if __name__ == "__main__":
    models = build()
    src = emit(models)
    open(sys.argv[1] if len(sys.argv) > 1 else OUT, "w").write(src)
    for m in models:
        lo, hi = m.bounds()
        print(f"{m.id:12s} {len(m.parts):4d} parts  {hi[0] - lo[0]:5.2f} x {hi[1] - lo[1]:5.2f} x {hi[2] - lo[2]:5.2f}")
    print(f"{sum(len(m.parts) for m in models)} parts, {len(src) // 1024} KB")
