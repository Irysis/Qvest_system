"""Describe recorded position runs (consecutive non-flat weekly holdings) — descriptive only, no returns."""
import sys, csv, collections
sys.stdout.reconfigure(encoding="utf-8")
path = sys.argv[1]
by_date = collections.defaultdict(list)
with open(path, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        by_date[row["date"]].append((row["ticker"], float(row["target_weight"])))
dates = sorted(by_date)
state = {}
mega = {}
for d in dates:
    rows = by_date[d]
    mx = max(abs(w) for _, w in rows)
    if len(rows) <= 2 and mx <= 1e-5:
        state[d] = "F"
    else:
        sam = dict(rows).get("A005930")
        state[d] = "L" if (sam is not None and sam < 0) else ("S" if sam is not None else "?")
        w = dict(rows)
        big_neg = sorted(((abs(v), t) for t, v in rows if (v < 0 if state[d] == "L" else v > 0)), reverse=True)[:3]
        mega[d] = (w.get("A005930"), w.get("A000660"), [(t, round(a, 4)) for a, t in big_neg])
runs = []
cur = None
for d in dates:
    s = state[d]
    if s != "F":
        if cur is None:
            cur = [d, d, [s]]
        else:
            cur[1] = d; cur[2].append(s)
    else:
        if cur is not None:
            runs.append(cur); cur = None
if cur is not None:
    runs.append(cur)
print(f"weeks total {len(dates)} · position weeks {sum(len(r[2]) for r in runs)} · runs {len(runs)}")
lens = collections.Counter(len(r[2]) for r in runs)
print("run length (weeks) histogram:", dict(sorted(lens.items())))
first2 = sum(min(2, len(r[2])) for r in runs)
print(f"position weeks that are the 1st or 2nd week of a run: {first2}")
flips = sum(sum(1 for a, b in zip(r[2], r[2][1:]) if a != b) for r in runs)
print(f"sign flips inside runs: {flips}")
for r in runs:
    print(r[0], "->", r[1], len(r[2]), "".join(r[2]))
print("\nmega-cap weights on selected position dates (A005930, A000660, top-3 big-leg |w|):")
for d in [x for x in dates if state[x] != "F" and x[:4] in ("2008", "2020", "2025", "2026")][:60]:
    print(d, state[d], mega[d])
