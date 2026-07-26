#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
collision_quick.py — 짧은 한글 키워드(<=3음절)의 substring 충돌만 빠르게 실측.

성능: alternation 1회 통과(가변길이 W* 래핑 없음) + 사전 토큰화 + bisect로
      '매치를 포함하는 최대 토큰'을 O(log n)에 복원. 전수 스캔의 30초판.
"""
import os, re, json, glob, unicodedata, bisect, time
from collections import Counter, defaultdict

FQ = os.path.dirname(os.path.abspath(__file__))
HS = json.load(open(os.path.join(FQ, "hs_lexicon.json"), encoding="utf-8"))
NT = json.load(open(os.path.join(FQ, "nontrade_lexicon.json"), encoding="utf-8"))
TOC = re.compile(r"-{3,}")


def clean(rec):
    parts = []
    for f in ("text_sales", "text_overview"):
        for seg in (rec.get(f) or "").split(" ||| "):
            if len(TOC.findall(seg)) >= 3:
                continue
            parts.append(seg)
    return unicodedata.normalize("NFKC", " ".join(parts))


corpus = "\n".join(clean(json.load(open(fp, encoding="utf-8")))
                   for fp in glob.glob(os.path.join(FQ, "dart_products", "*.json")))
print("[quick] corpus=%d" % len(corpus), flush=True)

# 토큰 경계 사전 계산
spans = [(m.start(), m.end()) for m in re.finditer(r"[가-힣A-Za-z0-9]+", corpus)]
starts = [s for s, _ in spans]
print("[quick] tokens=%d" % len(spans), flush=True)

# 위험 대상: 한글 음절 <=3, \b 미사용
targets = []
for lex, tag in ((HS, "HS"), (NT, "NT")):
    for code, v in lex.items():
        if code.startswith("_"):
            continue
        for kw in v["kw"]:
            kor = re.findall(r"[가-힣]", kw)
            if kor and len(kor) <= 3 and "\\b" not in kw:
                targets.append((tag, code, kw))
print("[quick] risky keywords=%d" % len(targets), flush=True)

tot = Counter(); enc = defaultdict(Counter)
B = 150
t0 = time.time()
for i in range(0, len(targets), B):
    ch = targets[i:i + B]
    alts = []
    for j, (_t, _c, kw) in enumerate(ch):
        try:
            re.compile(kw)
            alts.append("(?P<g%d>%s)" % (j, kw))
        except re.error:
            pass
    rx = re.compile("|".join(alts), re.I)
    for m in rx.finditer(corpus):
        gi = next((int(n[1:]) for n, v in m.groupdict().items() if v is not None), None)
        if gi is None:
            continue
        tag, code, kw = ch[gi]
        key = "%s|%s|%s" % (tag, code, kw)
        tot[key] += 1
        k = bisect.bisect_right(starts, m.start()) - 1
        if 0 <= k < len(spans) and spans[k][0] <= m.start() < spans[k][1]:
            enc[key][corpus[spans[k][0]:spans[k][1]][:24]] += 1
    print("  batch %d/%d %.0fs" % (i // B + 1, (len(targets) + B - 1) // B, time.time() - t0), flush=True)

rows = []
for key, n in tot.items():
    bare = re.sub(r"\\s\*|\\b|\\", "", key.split("|")[2])
    ext = sum(v for t, v in enc[key].items() if t != bare)
    rows.append((key, n, round(ext / n, 3), enc[key].most_common(6)))
rows.sort(key=lambda r: -(r[2] * r[1]))
json.dump([{"key": k, "total": n, "ext_ratio": e, "tokens": t} for k, n, e, t in rows],
          open(os.path.join(FQ, "collision_quick.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
print("\n[quick] 충돌 후보 상위 60")
for k, n, e, t in rows[:60]:
    print("  %-30s tot=%-5d ext=%.2f | %s" % (k[:30], n, e, ", ".join("%s(%d)" % x for x in t[:4])))
