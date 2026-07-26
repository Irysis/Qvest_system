#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
collision_scan.py — substring 충돌을 474사 원문 전수로 실측 (가드 없는 raw 매칭 기준).

성능: 키워드별 전체 스캔은 O(corpus x keywords)로 비현실적 → 키워드를 하나의
      alternation으로 합쳐 **코퍼스 1회 통과**로 처리. 매치마다 이를 포함하는
      최대 토큰의 prefix/suffix를 수집한다.
판정: 토큰 != 키워드면 합성어(정상: 열연→열연강판) 또는 충돌(비정상: 시너→시너지).
      사람이 실제 문자열 근거로 판정한다(추측 금지).
출력: collision_report.json
"""
import os, re, json, glob, unicodedata, time
from collections import Counter, defaultdict

FQ = os.path.dirname(os.path.abspath(__file__))
HS = json.load(open(os.path.join(FQ, "hs_lexicon.json"), encoding="utf-8"))
NT = json.load(open(os.path.join(FQ, "nontrade_lexicon.json"), encoding="utf-8"))
TOC = re.compile(r"-{3,}")
W = r"[가-힣A-Za-z0-9]"


def clean(rec):
    parts = []
    for f in ("text_sales", "text_overview"):
        for seg in (rec.get(f) or "").split(" ||| "):
            if len(TOC.findall(seg)) >= 3:
                continue
            parts.append(seg)
    return unicodedata.normalize("NFKC", " ".join(parts))


texts = [clean(json.load(open(fp, encoding="utf-8")))
         for fp in glob.glob(os.path.join(FQ, "dart_products", "*.json"))]
corpus = "\n".join(texts)
print("[scan] corpus=%d chars over %d firms" % (len(corpus), len(texts)), flush=True)

kws = []            # (tag, code, kw)
for lex, tag in ((HS, "HS"), (NT, "NT")):
    for code, v in lex.items():
        if code.startswith("_"):
            continue
        for kw in v["kw"]:
            kws.append((tag, code, kw))
print("[scan] keywords=%d" % len(kws), flush=True)

pre = defaultdict(Counter); post = defaultdict(Counter); tot = Counter()
BATCH = 120
t0 = time.time()
for i in range(0, len(kws), BATCH):
    chunk = kws[i:i + BATCH]
    alts = []
    for j, (tag, code, kw) in enumerate(chunk):
        try:
            re.compile(kw)
        except re.error:
            continue
        alts.append("(?P<g%d>%s)" % (j, kw))
    if not alts:
        continue
    rx = re.compile("(?P<pre>%s*)(?:%s)(?P<post>%s*)" % (W, "|".join(alts), W), re.I)
    for m in rx.finditer(corpus):
        gd = m.groupdict()
        gi = None
        for name, val in gd.items():
            if val is not None and name.startswith("g"):
                gi = int(name[1:]); break
        if gi is None:
            continue
        tag, code, kw = chunk[gi]
        key = "%s|%s|%s" % (tag, code, kw)
        tot[key] += 1
        if gd["pre"]:
            pre[key][gd["pre"]] += 1
        if gd["post"]:
            post[key][gd["post"]] += 1
    print("  batch %d/%d  %.0fs" % (i // BATCH + 1, (len(kws) + BATCH - 1) // BATCH, time.time() - t0), flush=True)

report = {}
for key, n in tot.items():
    ext = sum(pre[key].values()) + sum(post[key].values())
    report[key] = {"total": n, "ext_ratio": round(ext / n, 3),
                   "prefix": pre[key].most_common(5), "suffix": post[key].most_common(5)}
rank = sorted(report.items(), key=lambda kv: -(kv[1]["ext_ratio"] * kv[1]["total"]))
json.dump({"n_keywords_hit": len(report), "ranked": dict(rank)},
          open(os.path.join(FQ, "collision_report.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)

print("\n[scan] 충돌 후보 상위 60 (ext_ratio x total)")
for k, v in rank[:60]:
    print("  %-32s tot=%-5d ext=%.2f | pre=%s | suf=%s" % (
        k[:32], v["total"], v["ext_ratio"],
        ",".join("%s(%d)" % t for t in v["prefix"][:3]),
        ",".join("%s(%d)" % t for t in v["suffix"][:3])))
