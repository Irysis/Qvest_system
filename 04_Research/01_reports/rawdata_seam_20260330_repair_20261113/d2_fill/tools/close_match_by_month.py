"""퀀티 Close vs 거래소 종가(네이버 모바일 closePrice) — 월별 일치율. 어느 날부터 어긋났나.
입력: argv[1] = scratchpad · argv[2] = RAWDATA 표본 csv(Date,Ticker,Close,Vol,source)
"""
import csv, json, sys, time, urllib.request
from collections import defaultdict

SP, SAMPLE = sys.argv[1], sys.argv[2]
UA = {"User-Agent": "Mozilla/5.0"}
rows = list(csv.DictReader(open(SAMPLE, encoding="utf-8")))
qw = defaultdict(dict)
for r in rows:
    qw[r["Ticker"]][r["Date"]] = (float(r["Close"]), float(r["Vol"]) if r["Vol"] not in ("", "NA") else None, r["source"])


def fetch(code, oldest):
    out = {}
    for p in range(1, 40):
        u = f"https://m.stock.naver.com/api/stock/{code}/price?pageSize=60&page={p}"
        try:
            with urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=20) as r:
                d = json.loads(r.read().decode("utf-8"))
        except Exception:
            d = []
        time.sleep(0.12)
        if not d:
            break
        for x in d:
            out[x["localTradedAt"]] = (float(str(x["closePrice"]).replace(",", "")), x.get("accumulatedTradingVolume"))
        if d[-1]["localTradedAt"] < oldest:
            break
    return out


stat = defaultdict(lambda: [0, 0, 0])   # month -> [n, close_same, vol_same]
src_by_month = defaultdict(set)
ex = []
for t, dd in qw.items():
    api = fetch(t[1:], min(dd))
    for d, (c, v, s) in dd.items():
        if d not in api:
            continue
        oc, ov = api[d]
        m = d[:7]
        stat[m][0] += 1
        same = abs(c - oc) < 0.5
        stat[m][1] += same
        stat[m][2] += (v is not None and ov is not None and abs(v - float(ov)) < 0.5)
        src_by_month[m].add(s)
        if not same and len(ex) < 12 and d >= "2026-03-25" and d <= "2026-04-03":
            ex.append((d, t, c, oc, v, ov, s))
for m in sorted(stat):
    n, cs, vs = stat[m]
    print(f"{m}  n={n:4d}  종가 일치 {cs:4d} ({100*cs/n:5.1f}%)  거래량 일치 {vs:4d} ({100*vs/n:5.1f}%)  원천 {','.join(sorted(src_by_month[m]))}")
print("이음매 근처 불일치 예:")
for e in ex:
    print("  ", e)
