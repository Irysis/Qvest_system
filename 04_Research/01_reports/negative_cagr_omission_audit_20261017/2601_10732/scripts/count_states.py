"""Count recorded weekly position states from 04_holdings.csv (descriptive only — no returns computed).

state per holdings date:
  flat  = only the ±1e-6 token pair (2 rows, |w| <= 1e-5)
  long  = long-SMB  (A005930, always Big, carries a negative weight)
  short = short-SMB (A005930 carries a positive weight above token size)
  other = position present but A005930 absent (sign by small/big unknown) -> fallback on gross sign of the largest-|w| names is not attempted
"""
import sys, csv, collections
sys.stdout.reconfigure(encoding="utf-8")

def run(path):
    by_date = collections.defaultdict(list)
    with open(path, encoding="utf-8") as f:
        r = csv.DictReader(f)
        for row in r:
            by_date[row["date"]].append((row["ticker"], float(row["target_weight"])))
    per_year = collections.defaultdict(collections.Counter)
    gross = {}
    for d, rows in sorted(by_date.items()):
        y = d[:4]
        mx = max(abs(w) for _, w in rows)
        if len(rows) <= 2 and mx <= 1e-5:
            st = "flat"
        else:
            sam = [w for t, w in rows if t == "A005930"]
            if sam and sam[0] < -1e-5:
                st = "long_SMB"
            elif sam and sam[0] > 1e-5:
                st = "short_SMB"
            else:
                st = "pos_unknown"
            gl = sum(w for _, w in rows if w > 0)
            gs = -sum(w for _, w in rows if w < 0)
            gross[d] = (round(gl, 4), round(gs, 4), len(rows))
        per_year[y][st] += 1
    tot = collections.Counter()
    print("year  flat  long_SMB  short_SMB  pos_unknown")
    for y in sorted(per_year):
        c = per_year[y]
        tot.update(c)
        print(f"{y}  {c['flat']:4d}  {c['long_SMB']:8d}  {c['short_SMB']:9d}  {c['pos_unknown']:11d}")
    print("total", dict(tot))
    if gross:
        gls = [v[0] for v in gross.values()]; gss = [v[1] for v in gross.values()]; ns = [v[2] for v in gross.values()]
        print(f"position dates {len(gross)} · long gross {min(gls)}~{max(gls)} · short gross {min(gss)}~{max(gss)} · names {min(ns)}~{max(ns)}")

for p in sys.argv[1:]:
    print("==", p)
    run(p)
