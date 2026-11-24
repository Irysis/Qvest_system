"""Shape text with HarfBuzz and emit SVG outline paths via fontTools (no font needed at view time)."""
import io

import uharfbuzz as hb
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont


class Face:
    def __init__(self, path):
        tt = TTFont(path)          # .woff/.woff2/.ttf
        tt.flavor = None
        buf = io.BytesIO()
        tt.save(buf)
        data = buf.getvalue()
        self.tt = TTFont(io.BytesIO(data))
        self.hbfont = hb.Font(hb.Face(hb.Blob(data)))
        self.upm = self.tt['head'].unitsPerEm
        self.gs = self.tt.getGlyphSet()
        self.cap_height = self.tt['OS/2'].sCapHeight

    def _run(self, text):
        b = hb.Buffer()
        b.add_str(text)
        b.guess_segment_properties()
        hb.shape(self.hbfont, b, {"kern": True, "liga": True, "calt": True})   # script joins need calt
        run, cx = [], 0
        for inf, pos in zip(b.glyph_infos, b.glyph_positions):
            run.append((self.tt.getGlyphName(inf.codepoint), cx + pos.x_offset, pos.y_offset))
            cx += pos.x_advance
        return run

    def glyph_count(self, text):
        return len(self._run(text))

    def outline(self, text, x, y, size, tracking=0.0):
        """size = em in px, (x, y) = baseline origin, tracking = extra px after each glyph.
        Returns (svg path d, ink bbox)."""
        s = size / self.upm
        pen, bp = SVGPathPen(self.gs), BoundsPen(self.gs)
        for i, (name, gx, gy) in enumerate(self._run(text)):
            tr = (s, 0, 0, -s, x + gx * s + i * tracking, y - gy * s)
            self.gs[name].draw(TransformPen(pen, tr))
            self.gs[name].draw(TransformPen(bp, tr))
        return pen.getCommands(), bp.bounds
