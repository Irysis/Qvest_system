import re
import sys
import zlib

src = sys.argv[1]
dst = sys.argv[2]
data = open(src, "rb").read()

# 1. collect all streams, inflate the FlateDecode ones
chunks = []
for m in re.finditer(rb"stream\r?\n", data):
    start = m.end()
    end = data.find(b"endstream", start)
    if end < 0:
        continue
    raw = data[start:end]
    head = data[max(0, m.start() - 400):m.start()]
    if b"FlateDecode" in head:
        try:
            raw = zlib.decompress(raw)
        except Exception:
            try:
                raw = zlib.decompressobj().decompress(raw)
            except Exception:
                continue
    if b"BT" in raw and (b"Tj" in raw or b"TJ" in raw):
        chunks.append(raw)

LIG = {11: "ff", 12: "fi", 13: "fl", 14: "ffi", 15: "ffl"}

def unescape(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == 0x5C and i + 1 < n:  # backslash
            d = s[i + 1]
            if d in b"nrtbf":
                out.append({0x6E: "\n", 0x72: "\r", 0x74: "\t", 0x62: "\b", 0x66: "\f"}[d])
                i += 2
                continue
            if d in b"()\\":
                out.append(chr(d))
                i += 2
                continue
            if 0x30 <= d <= 0x37:
                j = i + 1
                oct_digits = b""
                while j < n and j < i + 4 and 0x30 <= s[j] <= 0x37:
                    oct_digits += bytes([s[j]])
                    j += 1
                code = int(oct_digits, 8)
                out.append(LIG.get(code, chr(code) if 32 <= code < 127 else ""))
                i = j
                continue
            i += 2
            continue
        if c in LIG:
            out.append(LIG[c])
        elif 32 <= c < 127:
            out.append(chr(c))
        else:
            out.append("")
        i += 1
    return "".join(out)

def parse_content(buf):
    text = []
    i = 0
    n = len(buf)
    while i < n:
        c = buf[i]
        if c == 0x28:  # '(' literal string
            depth = 1
            j = i + 1
            while j < n and depth > 0:
                if buf[j] == 0x5C:
                    j += 2
                    continue
                if buf[j] == 0x28:
                    depth += 1
                elif buf[j] == 0x29:
                    depth -= 1
                j += 1
            text.append(("S", unescape(buf[i + 1:j - 1])))
            i = j
            continue
        if c == 0x5B:  # '[' TJ array
            text.append(("A", None))
            i += 1
            continue
        if c == 0x5D:
            text.append(("E", None))
            i += 1
            continue
        m = re.match(rb"-?\d+(\.\d+)?", buf[i:i + 24])
        if m and (i == 0 or buf[i - 1] in b" \n\r\t[]"):
            text.append(("N", float(m.group(0))))
            i += m.end()
            continue
        m = re.match(rb"[A-Za-z']+\*?", buf[i:i + 8])
        if m:
            op = m.group(0)
            if op in (b"TJ", b"Tj", b"T*", b"Td", b"TD", b"Tm", b"ET", b"BT", b"'"):
                text.append(("O", op.decode()))
            i += m.end()
            continue
        i += 1
    out = []
    in_arr = False
    for kind, val in text:
        if kind == "A":
            in_arr = True
        elif kind == "E":
            in_arr = False
        elif kind == "S":
            out.append(val)
        elif kind == "N" and in_arr:
            if val < -180:
                out.append(" ")
        elif kind == "O":
            if val in ("T*", "Td", "TD", "Tm", "'", "ET"):
                out.append(" ")
            if val == "ET":
                out.append("\n")
    return "".join(out)

pages = [parse_content(c) for c in chunks]
txt = "\n".join(pages)
txt = re.sub(r"[ \t]+", " ", txt)
open(dst, "w", encoding="utf-8").write(txt)
print("streams", len(chunks), "chars", len(txt))
