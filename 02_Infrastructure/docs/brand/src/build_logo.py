"""Qvest brand mark generator — writes the SVG logo variants (all text converted to outlines).

usage: python build_logo.py <fonts_dir> <out_dir>
  fonts_dir must contain allison-latin-400-normal.woff (npm @fontsource/allison — SIL OFL 1.1).
  The QVEST wordmark is a geometric construction (geom.py), not a font.
  deps: fonttools · uharfbuzz · shapely

Symbol geometry is measured from the reference concept image (1254 px): ring centre (627, 470),
outer radius 307 px. All symbol dimensions below are in units of that outer radius R.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shapely.geometry import box  # noqa: E402

from geom import flat_symbol, star_poly, to_path, wordmark_geom  # noqa: E402
from textpath import Face  # noqa: E402

# ---- measured symbol geometry (units of R) ----------------------------------------
BAND_IN = 0.723          # inner edge of the glass band (222/307)
RING_IN = 0.619          # thin inner ring (190/307)
TAIL = [(-0.287, 0.107), (0.221, 0.107), (1.154, 1.040), (0.646, 1.040)]   # slab: 45 deg, horizontal ends
RAY_DEG = -28.5          # light ray from the core through the flare (measured -26..-29 deg)

PAL = dict(
    bg0='#0b2c8c', bg1='#071c63', bg2='#04103d', bg3='#020823',
    ice='#eaf7ff', rim='#c8ecff', cyan='#7fd2ff', blue='#2f86ff', deep='#0f4fd0',
    navy='#0a1f5c', brand='#1f6fff',
)


def f(v):
    s = f"{v:.2f}"
    return s.rstrip('0').rstrip('.') if '.' in s else s


class Canvas:
    """One SVG document; ids are prefixed so several logos can be inlined in one page."""

    def __init__(self, w, h, pfx):
        self.w, self.h, self.p = w, h, pfx
        self.defs, self.body = [], []

    def id(self, name):
        return f"{self.p}-{name}"

    def ref(self, name):
        return f"url(#{self.p}-{name})"

    def add(self, s):
        self.body.append(s)

    def svg(self, title):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" '
                f'width="{self.w}" height="{self.h}" role="img" aria-label="{title}">'
                f'<title>{title}</title><defs>{"".join(self.defs)}</defs>{"".join(self.body)}</svg>')

    def glow(self, name, s1, s2, k=1.0):
        """Two-radius bloom; user-space region so thin lines are not clipped."""
        self.defs.append(
            f'<filter id="{self.id(name)}" filterUnits="userSpaceOnUse" x="0" y="0" width="{self.w}" '
            f'height="{self.h}" color-interpolation-filters="sRGB">'
            f'<feGaussianBlur in="SourceGraphic" stdDeviation="{f(s2)}" result="b2"/>'
            f'<feGaussianBlur in="SourceGraphic" stdDeviation="{f(s1)}" result="b1"/>'
            f'<feComponentTransfer in="b2" result="b2k"><feFuncA type="linear" slope="{f(k)}"/></feComponentTransfer>'
            f'<feMerge><feMergeNode in="b2k"/><feMergeNode in="b1"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')

    def blur(self, name, s):
        self.defs.append(
            f'<filter id="{self.id(name)}" filterUnits="userSpaceOnUse" x="0" y="0" width="{self.w}" '
            f'height="{self.h}"><feGaussianBlur stdDeviation="{f(s)}"/></filter>')

    def radial(self, name, cx, cy, r, stops):
        st = ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        self.defs.append(f'<radialGradient id="{self.id(name)}" gradientUnits="userSpaceOnUse" '
                         f'cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}">{st}</radialGradient>')

    def linear(self, name, x1, y1, x2, y2, stops):
        st = ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        self.defs.append(f'<linearGradient id="{self.id(name)}" gradientUnits="userSpaceOnUse" '
                         f'x1="{f(x1)}" y1="{f(y1)}" x2="{f(x2)}" y2="{f(y2)}">{st}</linearGradient>')


# ---- background ------------------------------------------------------------------
def background(c, cx, cy, seed, stars=160):
    c.radial('bg', cx, cy, max(c.w, c.h) * 0.78,
             [(0, PAL['bg0'], 1), (0.32, PAL['bg1'], 1), (0.66, PAL['bg2'], 1), (1, PAL['bg3'], 1)])
    c.add(f'<rect width="{c.w}" height="{c.h}" fill="{c.ref("bg")}"/>')
    rnd = random.Random(seed)
    dots = []
    for _ in range(stars):
        x, y = rnd.uniform(0, c.w), rnd.uniform(0, c.h)
        r = rnd.choice([0.5, 0.6, 0.8, 1.0, 1.3])
        a = rnd.uniform(0.12, 0.5)
        dots.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="#bfe3ff" opacity="{f(a)}"/>')
    c.add(f'<g>{"".join(dots)}</g>')


# ---- small parts -------------------------------------------------------------------
def star_path(x, y, lx, ly, w):
    """4-point star: horizontal half-length lx, vertical ly, waist half-width w."""
    return (f'M{f(x - lx)} {f(y)}L{f(x - w)} {f(y - w)}L{f(x)} {f(y - ly)}L{f(x + w)} {f(y - w)}'
            f'L{f(x + lx)} {f(y)}L{f(x + w)} {f(y + w)}L{f(x)} {f(y + ly)}L{f(x - w)} {f(y + w)}Z')


def sparkle(c, x, y, s, name):
    c.radial(name, x, y, s * 1.7, [(0, '#ffffff', 1), (0.12, '#ffffff', 0.95), (0.3, PAL['cyan'], 0.55),
                                   (0.6, PAL['blue'], 0.18), (1, PAL['blue'], 0)])
    c.add(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(s * 1.7)}" fill="{c.ref(name)}"/>')
    c.add(f'<path d="{star_path(x, y, s * 1.6, s * 1.15, s * 0.07)}" fill="#ffffff" opacity="0.95"/>')
    d = s * 0.42
    c.add(f'<path d="M{f(x - d)} {f(y - d)}L{f(x + d)} {f(y + d)}M{f(x - d)} {f(y + d)}L{f(x + d)} {f(y - d)}" '
          f'stroke="#ffffff" stroke-width="{f(s * 0.035)}" stroke-linecap="round" opacity="0.7"/>')


def tail_pts(cx, cy, R):
    return [(cx + x * R, cy + y * R) for x, y in TAIL]


def poly(pts):
    return 'M' + 'L'.join(f'{f(x)} {f(y)}' for x, y in pts) + 'Z'


# ---- the Q symbol (glow) -----------------------------------------------------------
def symbol_glow(c, cx, cy, R, seed=7, ray=1.75):
    rnd = random.Random(seed)
    c.glow('gl', R * 0.010, R * 0.045, 0.9)
    c.glow('gls', R * 0.006, R * 0.02, 0.8)
    c.blur('soft', R * 0.03)

    # atmosphere behind the ring
    c.radial('halo', cx, cy, R * 1.45, [(0, PAL['blue'], 0.32), (0.55, PAL['deep'], 0.22),
                                        (0.75, PAL['deep'], 0.10), (1, PAL['deep'], 0)])
    c.add(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * 1.45)}" fill="{c.ref("halo")}"/>')

    # energy disc
    c.radial('disc', cx, cy, R * RING_IN, [(0, '#3a8dff', 0.55), (0.35, '#1556d6', 0.45),
                                           (0.8, '#0a2f97', 0.35), (1, '#071f6b', 0.25)])
    c.add(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * RING_IN)}" fill="{c.ref("disc")}"/>')

    # glass band (annulus) + network texture
    rm = R * (1 + BAND_IN) / 2
    bw = R * (1 - BAND_IN)
    c.linear('band', cx - R, cy - R, cx + R, cy + R,
             [(0, '#2d7dff', 0.42), (0.5, '#1149c4', 0.34), (1, '#0a2f8f', 0.42)])
    c.add(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(rm)}" fill="none" stroke="{c.ref("band")}" '
          f'stroke-width="{f(bw)}"/>')
    c.defs.append(f'<clipPath id="{c.id("bandclip")}"><path fill-rule="evenodd" d="'
                  f'M{f(cx + R)} {f(cy)}A{f(R)} {f(R)} 0 1 0 {f(cx - R)} {f(cy)}A{f(R)} {f(R)} 0 1 0 {f(cx + R)} {f(cy)}Z'
                  f'M{f(cx + R * BAND_IN)} {f(cy)}A{f(R * BAND_IN)} {f(R * BAND_IN)} 0 1 0 {f(cx - R * BAND_IN)} {f(cy)}'
                  f'A{f(R * BAND_IN)} {f(R * BAND_IN)} 0 1 0 {f(cx + R * BAND_IN)} {f(cy)}Z"/></clipPath>')
    pts = []
    for _ in range(110):
        rr = math.sqrt(rnd.uniform((BAND_IN + 0.02) ** 2, 0.985 ** 2)) * R
        a = rnd.uniform(0, 2 * math.pi)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    seg = []
    for i, (x, y) in enumerate(pts):
        near = sorted(((x - u) ** 2 + (y - v) ** 2, j) for j, (u, v) in enumerate(pts) if j != i)[:2]
        for d2, j in near:
            if j > i and d2 < (0.16 * R) ** 2:
                seg.append(f'M{f(x)} {f(y)}L{f(pts[j][0])} {f(pts[j][1])}')
    net = (f'<path d="{"".join(seg)}" stroke="{PAL["cyan"]}" stroke-width="{f(R * 0.0035)}" opacity="0.35"/>' +
           ''.join(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(R * rnd.uniform(0.004, 0.009))}" fill="#d6f1ff" '
                   f'opacity="{f(rnd.uniform(0.35, 0.85))}"/>' for x, y in pts))
    c.add(f'<g clip-path="{c.ref("bandclip")}">{net}</g>')

    # specular sweep on the band's upper-left
    a0, a1 = math.radians(195), math.radians(285)
    r_s = R * 0.93
    c.add(f'<path d="M{f(cx + r_s * math.cos(a0))} {f(cy + r_s * math.sin(a0))}A{f(r_s)} {f(r_s)} 0 0 1 '
          f'{f(cx + r_s * math.cos(a1))} {f(cy + r_s * math.sin(a1))}" fill="none" stroke="#ffffff" '
          f'stroke-width="{f(R * 0.03)}" stroke-linecap="round" opacity="0.22" filter="{c.ref("soft")}"/>')

    # rims and inner ring (glowing)
    c.add(f'<g filter="{c.ref("gl")}" fill="none">'
          f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R)}" stroke="{PAL["rim"]}" stroke-width="{f(R * 0.016)}"/>'
          f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * 0.968)}" stroke="{PAL["cyan"]}" stroke-width="{f(R * 0.005)}" opacity="0.7"/>'
          f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * BAND_IN)}" stroke="{PAL["rim"]}" stroke-width="{f(R * 0.012)}"/>'
          f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * RING_IN)}" stroke="{PAL["cyan"]}" stroke-width="{f(R * 0.014)}"/>'
          f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * (RING_IN - 0.022))}" stroke="{PAL["blue"]}" stroke-width="{f(R * 0.004)}" opacity="0.8"/>'
          f'</g>')

    # filaments (seeded random-walk lightning) + particles inside the disc
    c.defs.append(f'<clipPath id="{c.id("discclip")}"><circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * (RING_IN - 0.03))}"/></clipPath>')
    fil = []

    def walk(x, y, ang, length, width, depth):
        d = f'M{f(x)} {f(y)}'
        n = int(length / (0.032 * R))
        a_ref = ang
        for _ in range(n):
            ang = a_ref + 0.75 * (ang - a_ref) + rnd.uniform(-0.6, 0.6)   # jagged but keeps heading outward
            x += 0.032 * R * math.cos(ang)
            y += 0.032 * R * math.sin(ang)
            d += f'L{f(x)} {f(y)}'
            if depth < 2 and rnd.random() < 0.16:
                walk(x, y, ang + rnd.choice([-1, 1]) * rnd.uniform(0.5, 1.0), length * 0.45, width * 0.6, depth + 1)
        fil.append(f'<path d="{d}" stroke-width="{f(width)}" opacity="{f(rnd.uniform(0.35, 0.8))}"/>')

    for k in range(24):
        a = 2 * math.pi * k / 24 + rnd.uniform(-0.12, 0.12)
        walk(cx + 0.03 * R * math.cos(a), cy + 0.03 * R * math.sin(a), a, rnd.uniform(0.22, 0.6) * R,
             R * rnd.uniform(0.004, 0.007), 0)
    parts = ''.join(
        f'<circle cx="{f(cx + rr * math.cos(a))}" cy="{f(cy + rr * math.sin(a))}" r="{f(R * rnd.uniform(0.003, 0.008))}" '
        f'fill="#e6f6ff" opacity="{f(rnd.uniform(0.3, 0.95))}"/>'
        for rr, a in ((R * (RING_IN - 0.04) * rnd.random() ** 0.8, rnd.uniform(0, 2 * math.pi)) for _ in range(150)))
    c.add(f'<g clip-path="{c.ref("discclip")}"><g fill="none" stroke="{PAL["cyan"]}" stroke-linecap="round" '
          f'stroke-linejoin="round" filter="{c.ref("gls")}">{"".join(fil)}</g>{parts}</g>')

    # tail slab: knockout gap, body, lit face, circuit traces, inner bevel, rim
    tp = tail_pts(cx, cy, R)
    c.add(f'<path d="{poly(tp)}" fill="none" stroke="{c.ref("bg")}" stroke-width="{f(R * 0.045)}" stroke-linejoin="miter"/>')
    (x0, y0), (x1, _), (x2, y2), (x3, _) = tp
    c.linear('tail', (x0 + x1) / 2, y0, (x2 + x3) / 2, y2,
             [(0, '#d2efff', 0.97), (0.16, '#7cc4ff', 0.93), (0.55, '#2d78f0', 0.9), (1, '#1a4fc4', 0.93)])
    c.add(f'<path d="{poly(tp)}" fill="{c.ref("tail")}"/>')
    # across the slab (perpendicular to its 45-degree axis): lit upper-right face, shaded lower-left
    mx, my = (x1 + x2) / 2, (y0 + y2) / 2
    hw = (TAIL[1][0] - TAIL[0][0]) * R * 0.5 * math.sqrt(0.5)
    c.linear('tailx', mx + hw * 0.7, my - hw * 0.7, mx - hw * 2.1, my + hw * 2.1,
             [(0, '#ffffff', 0.30), (0.35, '#ffffff', 0.06), (0.75, '#000a40', 0.0), (1, '#000a40', 0.28)])
    c.add(f'<path d="{poly(tp)}" fill="{c.ref("tailx")}"/>')
    c.defs.append(f'<clipPath id="{c.id("tailclip")}"><path d="{poly(tp)}"/></clipPath>')
    th = math.radians(45)
    T = ((tp[0][0] + tp[1][0]) / 2, tp[0][1])
    L = math.hypot((tp[2][0] + tp[3][0]) / 2 - T[0], tp[2][1] - T[1])
    half = (TAIL[1][0] - TAIL[0][0]) * math.sin(th) / 2 * R
    lanes = [-0.62, -0.3, 0.02, 0.34, 0.64]
    tr = []
    for i, ln in enumerate(lanes):
        u = rnd.uniform(0.12, 0.35) * L
        v = ln * half
        d = f'M{f(u)} {f(v)}'
        dots = [(u, v)]
        while u < L * 1.05:
            u += rnd.uniform(0.07, 0.17) * L
            d += f'L{f(u)} {f(v)}'
            if rnd.random() < 0.45 and u < L * 0.9:
                nv = lanes[min(len(lanes) - 1, max(0, i + rnd.choice([-1, 1])))] * half
                u += abs(nv - v)
                v = nv
                d += f'L{f(u)} {f(v)}'
            if rnd.random() < 0.3:
                dots.append((u, v))
        tr.append(f'<path d="{d}" fill="none"/>')
        tr += [f'<circle cx="{f(a)}" cy="{f(b)}" r="{f(R * 0.009)}"/>' for a, b in dots]
    c.add(f'<g clip-path="{c.ref("tailclip")}">'
          f'<g transform="translate({f(T[0])} {f(T[1])}) rotate(45)" stroke="#e2f5ff" stroke-width="{f(R * 0.0045)}" '
          f'fill="#e2f5ff" opacity="0.55">{"".join(tr)}</g>'
          f'<path d="{poly(tp)}" fill="none" stroke="#cdeeff" stroke-width="{f(R * 0.06)}" opacity="0.28"/>'
          f'<path d="{poly(tp)}" fill="none" stroke="#e8f7ff" stroke-width="{f(R * 0.022)}" opacity="0.35"/></g>')
    c.add(f'<path d="{poly(tp)}" fill="none" stroke="{PAL["ice"]}" stroke-width="{f(R * 0.011)}" '
          f'stroke-linejoin="miter" filter="{c.ref("gls")}"/>')
    sparkle(c, tp[2][0] - R * 0.01, tp[2][1] - R * 0.006, 0.05 * R, 'sptip')

    # core burst (drawn over the slab's head)
    c.radial('core', cx, cy, R * 0.42, [(0, '#ffffff', 1), (0.06, '#ffffff', 0.95), (0.16, '#a6e1ff', 0.75),
                                        (0.4, '#3f93ff', 0.35), (1, '#1f6fff', 0)])
    c.add(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * 0.42)}" fill="{c.ref("core")}"/>')
    c.radial('rays', cx, cy, R * 0.55, [(0, '#ffffff', 1), (0.35, '#cdeeff', 0.7), (1, '#7fd2ff', 0)])
    c.add(f'<g fill="{c.ref("rays")}">'
          f'<path d="{star_path(cx, cy, R * 0.55, R * 0.42, R * 0.018)}"/>'
          f'<path d="{star_path(cx, cy, R * 0.2, R * 0.2, R * 0.012)}" transform="rotate(45 {f(cx)} {f(cy)})"/></g>')
    c.add(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(R * 0.022)}" fill="#ffffff"/>')

    # light ray through the flare + sparkles
    if ray:
        a = math.radians(RAY_DEG)
        p0 = (cx + 0.42 * R * math.cos(a), cy + 0.42 * R * math.sin(a))
        p1 = (cx + ray * R * math.cos(a), cy + ray * R * math.sin(a))
        c.linear('ray', *p0, *p1, [(0, '#ffffff', 0), (0.2, '#cdeeff', 0.55), (0.42, '#ffffff', 0.95),
                                   (0.7, '#9fdcff', 0.45), (1, '#9fdcff', 0)])
        c.add(f'<path d="M{f(p0[0])} {f(p0[1])}L{f(p1[0])} {f(p1[1])}" stroke="{c.ref("ray")}" '
              f'stroke-width="{f(R * 0.012)}" stroke-linecap="round" filter="{c.ref("gls")}"/>')
        for rr, s, nm in ((BAND_IN, 0.045, 'sp1'), (0.968, 0.085, 'sp2')):
            sparkle(c, cx + rr * R * math.cos(a), cy + rr * R * math.sin(a), s * R, nm)
    sparkle(c, cx + 0.02 * R, cy - 0.985 * R, 0.04 * R, 'sp3')
    sparkle(c, cx - 0.70 * R, cy + 0.72 * R, 0.025 * R, 'sp4')


# ---- the Q symbol (flat) -----------------------------------------------------------
def symbol_flat(c, cx, cy, R, ink, accent):
    """Flat mark: geometric knockouts (gaps are truly transparent); the slab starts just under the spark."""
    band, ring, tail = flat_symbol(R, BAND_IN, RING_IN, [(x * R, y * R) for x, y in TAIL], R * 0.045)
    ly = R * 0.27
    star = star_poly(R * 0.36, ly, R * 0.05)
    tail = tail.intersection(box(-4 * R, ly + R * 0.05, 4 * R, 4 * R))   # horizontal cut keeps the parallelogram
    c.add(f'<path fill-rule="evenodd" d="{to_path(band, dx=cx, dy=cy)}" fill="{ink}"/>')
    c.add(f'<path fill-rule="evenodd" d="{to_path(ring, dx=cx, dy=cy)}" fill="{accent}"/>')
    c.add(f'<path d="{to_path(star, dx=cx, dy=cy)}" fill="{accent}"/>')
    c.add(f'<path fill-rule="evenodd" d="{to_path(tail, dx=cx, dy=cy)}" fill="{accent}"/>')


# ---- wordmark, underline, tagline ---------------------------------------------------
def wordmark(c, xc, base, cap, style):
    """Geometric QVEST (geom.py, cap height 100 units) scaled to `cap` px, centred on xc."""
    g, (gx0, _, gx1, _) = wordmark_geom()
    k = cap / 100.0
    dx, dy = xc - (gx0 + gx1) / 2 * k, base - 100 * k
    d = to_path(g, k, k, dx, dy)
    if style == 'glow':
        c.linear('wm', 0, base - cap, 0, base,
                 [(0, '#f4fbff', 1), (0.42, '#bfe5ff', 0.97), (0.52, '#86c4ff', 0.95), (1, '#3d82f2', 0.95)])
        c.defs.append(f'<clipPath id="{c.id("wmclip")}"><path fill-rule="evenodd" d="{d}"/></clipPath>')
        c.add(f'<g filter="{c.ref("gltext")}"><path fill-rule="evenodd" d="{d}" fill="{c.ref("wm")}" '
              f'stroke="#e9f7ff" stroke-width="{f(cap * 0.02)}" stroke-linejoin="miter"/></g>')
        c.add(f'<path fill-rule="evenodd" d="{d}" fill="none" stroke="#ffffff" stroke-width="{f(cap * 0.07)}" '
              f'opacity="0.22" clip-path="{c.ref("wmclip")}"/>')
    else:
        c.add(f'<path fill-rule="evenodd" d="{d}" fill="{style}"/>')
    return gx0 * k + dx, gx1 * k + dx


def underline(c, x0, x1, y, style, s=1.0):
    xm = (x0 + x1) / 2
    if style == 'glow':
        c.linear('ul', x0, y, x1, y, [(0, PAL['blue'], 0), (0.25, PAL['cyan'], 0.55), (0.5, '#ffffff', 1),
                                      (0.75, PAL['cyan'], 0.55), (1, PAL['blue'], 0)])
        c.add(f'<path d="M{f(x0)} {f(y)}L{f(x1)} {f(y)}" stroke="{c.ref("ul")}" stroke-width="{f(3.2 * s)}" '
              f'stroke-linecap="round" filter="{c.ref("gltext")}"/>')
        sparkle(c, xm, y, 12 * s, 'ulsp')
    else:
        c.linear('ul', x0, y, x1, y, [(0, style, 0), (0.5, style, 1), (1, style, 0)])
        c.add(f'<path d="M{f(x0)} {f(y)}L{f(x1)} {f(y)}" stroke="{c.ref("ul")}" stroke-width="{f(2.4 * s)}"/>')


def tagline(c, face, xc, base, width, fill, glow=True):
    text = 'The Quant Research System'
    size = face.fit(text, box_w=width)
    _, (b0, _, b1, _) = face.outline(text, 0, base, size)
    # bake the offset into the outline: a transform on a filtered element would shift the filter region
    d, _ = face.outline(text, xc - (b0 + b1) / 2, base, size)
    flt = f' filter="{c.ref("gltext")}"' if glow else ''
    c.add(f'<g{flt}><path d="{d}" fill="{fill}"/></g>')


# ---- variants ----------------------------------------------------------------------
def build(fonts, out):
    scr = Face(os.path.join(fonts, 'allison-latin-400-normal.woff'))
    files = {}

    # 1) primary square lockup (reference composition, 1024 grid)
    c = Canvas(1024, 1024, 'qp')
    background(c, 512, 420, seed=11)
    c.glow('gltext', 2.2, 9, 0.85)
    symbol_glow(c, 512, 384, 250)
    x0, x1 = wordmark(c, 512, 784, 95, 'glow')
    underline(c, x0 - 6, x1 + 6, 813, 'glow')
    tagline(c, scr, 512, 884, 610, '#b3e0ff')
    files['qvest_logo.svg'] = c.svg('Qvest — The Quant Research System')

    # 2) app / avatar icon: symbol only, bbox-centred (ring [-R, R] + slab to 1.154R),
    #    farthest point 1.51R = 468 px stays inside the 512 px circle of a round avatar crop
    c = Canvas(1024, 1024, 'qi')
    R = 310
    background(c, 512, 512, seed=5, stars=90)
    symbol_glow(c, 512 - 0.077 * R, 512 - 0.02 * R, R, ray=1.4)
    files['qvest_icon.svg'] = c.svg('Qvest')

    # 3) wide banner (GitHub social preview 1280x640)
    c = Canvas(1280, 640, 'qb')
    background(c, 420, 300, seed=3, stars=140)
    c.glow('gltext', 2, 8, 0.85)
    symbol_glow(c, 300, 300, 195)
    x0, x1 = wordmark(c, 890, 330, 80, 'glow')
    underline(c, x0 - 5, x1 + 5, 356, 'glow', 0.9)
    tagline(c, scr, 890, 414, 520, '#b3e0ff')
    files['qvest_banner.svg'] = c.svg('Qvest — The Quant Research System')

    # 4) flat lockup for light backgrounds (transparent)
    c = Canvas(1400, 532, 'ql')
    symbol_flat(c, 270, 262, 200, PAL['navy'], PAL['brand'])
    x0, x1 = wordmark(c, 950, 272, 92, PAL['navy'])
    underline(c, x0, x1, 305, PAL['brand'], 1.2)
    tagline(c, scr, 950, 374, 560, PAL['brand'], glow=False)
    files['qvest_logo_light.svg'] = c.svg('Qvest — The Quant Research System')

    # 5) flat symbol alone (favicons, small sizes; transparent)
    c = Canvas(512, 512, 'qs')
    R = 200
    symbol_flat(c, 256 - 0.077 * R, 256 - 0.02 * R, R, PAL['navy'], PAL['brand'])
    files['qvest_symbol_flat.svg'] = c.svg('Qvest')

    os.makedirs(out, exist_ok=True)
    for k, v in files.items():
        with open(os.path.join(out, k), 'w', encoding='utf-8') as fh:
            fh.write(v)
        print(k, len(v) // 1024, 'KB')


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2])
