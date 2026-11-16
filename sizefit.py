# Keeps every remodeled model at the size it showed before the remodel.
#
# The match board fits each unit into its spot (MatchScreen F.unitScale):
#   creatures and tokens: scale = min(0.6, spot * 0.98 / widest, 2.6 / height), spot about 2.1 studs
#   buildings:            scale = min(0.5, pitch * 0.62 / widest, 1.6 / height), pitch 3.075
# Heroes and the bot opponent are shown at a fixed scale, so for them the real height counts.
#
# fit(m) scales a finished model evenly about its feet (the pivot stays at the origin) so that it
# stands as tall on the board as the old model did. A model whose new shape is much wider than its
# height allows cannot reach the old height by scaling alone (the board shrinks it to fit its spot);
# fit() reports that so the model can be made narrower instead.
from model_sizes_old import OLD_SIZES

SPOT = 2.1 * 0.98
PITCH = 3.075


def _limits(kind):
    if kind == "gadget":
        return 0.5, PITCH * 0.62, 1.6
    return 0.6, SPOT, 2.6


def shown_height(w, h, d, kind):
    """How tall a model of this size stands on the board (studs)."""
    if kind in ("hero", "avatar"):
        return h
    cap, wide_k, tall_k = _limits(kind)
    widest = max(w, d, 0.5)
    return min(cap, wide_k / widest, tall_k / max(h, 0.5)) * h


def size_of(m):
    lo, hi = m.bounds()
    return hi[0] - lo[0], hi[1], hi[2] - lo[2]


MIN_SIZE = 0.02  # thin details (glints, stitches, grooves) never get thinner than this when scaled


def scale_model(m, k):
    for p in m.parts:
        p["pos"] = tuple(float(v) * k for v in p["pos"])
        p["size"] = tuple(max(float(v) * k, MIN_SIZE) if float(v) >= MIN_SIZE else float(v) * k for v in p["size"])


TOL = 0.04  # how far the height on the board may drift from the old one


def fit(m):
    """Scale m so it stands as tall on the board as before (within TOL), keeping its real size as
    close to the old one as that allows (Pack Brawl shows models at their real size).
    Returns (k, note); note is '' when it fits."""
    old = OLD_SIZES.get(m.id)
    if old is None:
        return 1.0, ""
    ow, oh, od, _ = old
    w, h, d = size_of(m)
    ka = oh / h  # the scale that keeps the real height
    if m.kind in ("hero", "avatar"):
        scale_model(m, ka)
        return ka, ""
    target = shown_height(ow, oh, od, m.kind)
    cap, wide_k, tall_k = _limits(m.kind)
    widest = max(w, d, 0.5)
    best = min(wide_k * h / widest, tall_k)  # the tallest it can stand on the board, at any scale
    # on the board it stands cap * k * h tall until it reaches `best`, then stays there
    if (1 - TOL) * target > best:
        k = max(ka, best / (cap * h))
        scale_model(m, k)
        return k, "stands %.2f tall on the board instead of %.2f: too wide for its height (%.2f wide, %.2f tall)" % (
            best, target, widest, h)
    k_lo = (1 - TOL) * target / (cap * h)
    k_hi = float("inf") if (1 + TOL) * target >= best else (1 + TOL) * target / (cap * h)
    k = min(max(ka, k_lo), k_hi)
    scale_model(m, k)
    return k, ""
