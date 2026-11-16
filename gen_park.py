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
#
#     python3 gen_park.py
#
# ParkBuilder's propFrom(parent, id, cf, scale) builds a prop from this data; ParkBuilder adds the
# working pieces in code (the prompts, the lights, the crystal's PrimaryPart, the runes the client
# colours, the floating and fallen shards, the fire). Names the scripts look for stay: Base (the
# Enchant prompt), Core (in the Crystal group: the client colours it), Dais (the OpenPacks prompt),
# Crystal (the altar's lights), Lantern (the glass the client lights after dark), LogSeat.
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


PROPS = [shrine, altar, lantern, bollard, lanternpost, birdbath, litter_bin, topiary, cat, logseat, firepit, dueltable, basket]


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
