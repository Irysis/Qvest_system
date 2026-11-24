"""Geometric constructions (shapely) for the Qvest wordmark and the flat symbol.

Letter space: cap height H = 100, y grows downward (0 = cap line, 100 = baseline).
Letter widths and stroke are measured from the reference wordmark (x cap height):
Q 1.65 · V 1.38 · E 1.16 · S 1.19 · T 1.29 · stroke 0.17.
"""
import math

from shapely import affinity
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, box
from shapely.ops import unary_union

QS = 24  # arc segments per quarter circle
STROKE = 17.0
LETTER_W = dict(Q=165, V=138, E=116, S=119, T=129)
GAPS = (13, 19, 21, 17)  # Q-V, V-E, E-S, S-T (optical, at the closest points)


def rrect(x0, y0, x1, y1, r):
    if r <= 0:
        return box(x0, y0, x1, y1)
    return box(x0 + r, y0 + r, x1 - r, y1 - r).buffer(r, quad_segs=QS)


def ring_rect(x0, y0, x1, y1, r, t):
    """Rounded-rectangle ring with concentric corners (uniform stroke t)."""
    return rrect(x0, y0, x1, y1, r).difference(rrect(x0 + t, y0 + t, x1 - t, y1 - t, r - t))


def slab(x_top, y_top, y_bot, wh, ang_deg=45.0):
    """Parallelogram with horizontal ends, leaning down-right at ang_deg (same language as the symbol tail)."""
    dx = (y_bot - y_top) / math.tan(math.radians(ang_deg))
    return Polygon([(x_top, y_top), (x_top + wh, y_top), (x_top + wh + dx, y_bot), (x_top + dx, y_bot)])


def _arc(cx, cy, r, a0, a1, n=QS):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


# ---- letters -----------------------------------------------------------------------
def letter_Q(t, w=LETTER_W['Q'], r=42, gap=5.5):
    """Wide rounded bowl; 45-degree tail cuts through the lower-right with a knockout gap."""
    bowl = ring_rect(0, 0, w, 100, r, t)
    tail = slab(w * 0.535, 47, 112, t / math.sin(math.radians(45)))
    return unary_union([bowl.difference(tail.buffer(gap, join_style=2)), tail])


def letter_V(t, w=LETTER_W['V']):
    tip = (w / 2, 104.0)                 # outer edges meet just under the baseline -> small flat at y=100

    def arm(x0):
        dx, dy = tip[0] - x0, tip[1]
        n = math.hypot(dx, dy)
        nx, ny = dy / n, -dx / n
        if x0 > tip[0]:
            nx, ny = -nx, -ny
        p0, p1 = (x0 - dx, -dy), (tip[0] + dx, tip[1] + dy)
        return Polygon([p0, p1, (p1[0] + nx * t, p1[1] + ny * t), (p0[0] + nx * t, p0[1] + ny * t)])

    tri = Polygon([(0, 0), (w, 0), tip])
    return unary_union([arm(0), arm(w)]).intersection(tri).intersection(box(0, 0, w, 100))


def letter_E(t, w=LETTER_W['E'], mid=0.92):
    return unary_union([box(0, 0, t, 100), box(0, 0, w, t), box(0, 50 - t / 2, w * mid, 50 + t / 2),
                        box(0, 100 - t, w, 100)])


def letter_S(t, w=LETTER_W['S'], rc=16.5):
    """Squared S as a buffered centre line: flat terminals, concentric rounded corners."""
    h = t / 2
    pts = [(w, h)]
    pts += _arc(h + rc, h + rc, rc, 270, 180)            # top-left
    pts += _arc(h + rc, 50 - rc, rc, 180, 90)            # mid-left
    pts += _arc(w - h - rc, 50 + rc, rc, 270, 360)       # mid-right
    pts += _arc(w - h - rc, 100 - h - rc, rc, 0, 90)     # bottom-right
    pts += [(0, 100 - h)]
    return LineString(pts).buffer(h, cap_style=2, join_style=1, quad_segs=QS)


def letter_T(t, w=LETTER_W['T']):
    return unary_union([box(0, 0, w, t), box(w / 2 - t / 2, 0, w / 2 + t / 2, 100)])


def wordmark_geom(t=STROKE, gaps=GAPS):
    """QVEST laid out on nominal letter widths (the Q tail may overhang). Returns (geometry, bounds)."""
    letters = [('Q', letter_Q), ('V', letter_V), ('E', letter_E), ('S', letter_S), ('T', letter_T)]
    out, x = [], 0.0
    for i, (ch, fn) in enumerate(letters):
        out.append(affinity.translate(fn(t), x, 0))
        x += LETTER_W[ch] + (gaps[i] if i < len(gaps) else 0)
    u = unary_union(out)
    return u, u.bounds


# ---- flat symbol (true knockouts) -------------------------------------------------
def star_poly(lx, ly, w):
    return Polygon([(-lx, 0), (-w, -w), (0, -ly), (w, -w), (lx, 0), (w, w), (0, ly), (-w, w)])


def flat_symbol(R, band_in, ring_in, tail_pts, gap):
    """Band and inner ring with the tail knocked out (transparent gap), origin at the ring centre."""
    cut = Polygon(tail_pts).buffer(gap, join_style=2)
    band = Point(0, 0).buffer(R, quad_segs=64).difference(Point(0, 0).buffer(R * band_in, quad_segs=64))
    ring = Point(0, 0).buffer(R * (ring_in + 0.0175), quad_segs=64).difference(
        Point(0, 0).buffer(R * (ring_in - 0.0175), quad_segs=64))
    return band.difference(cut), ring.difference(cut), Polygon(tail_pts)


# ---- path output -------------------------------------------------------------------
def to_path(g, sx=1.0, sy=1.0, dx=0.0, dy=0.0):
    polys = list(g.geoms) if isinstance(g, MultiPolygon) else [g]
    out = []
    for p in polys:
        for ring in [p.exterior, *p.interiors]:
            cs = list(ring.coords)[:-1]
            out.append('M' + 'L'.join(f'{x * sx + dx:.2f} {y * sy + dy:.2f}' for x, y in cs) + 'Z')
    return ''.join(out)
