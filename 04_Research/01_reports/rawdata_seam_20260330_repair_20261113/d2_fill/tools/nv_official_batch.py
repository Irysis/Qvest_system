"""D2 재검 ⑤ — 거래소 공식 등락률(네이버 모바일 일별 시세 fluctuationsRatio = (종가 − 기준가)/기준가)로 단절 행 전부를 대조.
입력: d2_changed_rows.csv(원천 내부 87 + A250030) + 제한폭 밖 14행 — 종목별로 필요한 쪽만 받는다(이분 탐색 → 쪽 범위).
출력: d2_official.csv — Date, Ticker, found, close, chg, pct, base(= close − chg), api_prev_date, api_prev_close
"""
import csv, json, sys, time, urllib.request
from collections import defaultdict

SP = sys.argv[1]
UA = {"User-Agent": "Mozilla/5.0"}
PS = 60
cache = {}


def page(code, p):
    if (code, p) in cache:
        return cache[(code, p)]
    u = f"https://m.stock.naver.com/api/stock/{code}/price?pageSize={PS}&page={p}"
    out = None
    for _ in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=20) as r:
                d = json.loads(r.read().decode("utf-8"))
            out = d if isinstance(d, list) else []
            break
        except Exception:
            time.sleep(1.0)
    time.sleep(0.12)
    cache[(code, p)] = out
    return out


def page_of(code, date):
    """date 를 담은(또는 그보다 이른 첫) 쪽 번호 — 없으면 None"""
    lo, hi = 1, 1
    while True:
        rows = page(code, hi)
        if not rows:
            break
        if rows[-1]["localTradedAt"] <= date:
            break
        lo, hi = hi, hi * 2
        if hi > 8192:
            return None
    while hi - lo > 1:
        mid = (lo + hi) // 2
        rows = page(code, mid)
        if not rows or rows[-1]["localTradedAt"] <= date:
            hi = mid
        else:
            lo = mid
    return hi


def num(s):
    try:
        return float(str(s).replace(",", ""))
    except Exception:
        return None


need = defaultdict(set)
with open(f"{SP}/d2_changed_rows.csv", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        if r["Date"] < "2026-01-01" or r["Ticker"] == "A250030":
            need[r["Ticker"][1:]].add(r["Date"])
extra = [("1991-01-03", "A003580"), ("1992-01-03", "A013520"), ("1996-11-19", "A016560"), ("1997-08-27", "A014440"),
         ("1997-10-28", "A024890"), ("1997-11-25", "A027840"), ("1998-07-13", "A012470"), ("1999-11-26", "A007120"),
         ("2012-01-12", "A008080"), ("2012-11-30", "A008080"), ("2015-11-19", "A127160"), ("2015-11-20", "A180400"),
         ("2016-12-09", "A204990"), ("2018-06-07", "A037030")]
for d, t in extra:
    need[t[1:]].add(d)

res = []
for code, dates in sorted(need.items()):
    ds = sorted(dates)
    p_new = page_of(code, ds[-1])
    p_old = page_of(code, ds[0])
    rows = []
    if p_new and p_old:
        for p in range(max(1, p_new - 1), p_old + 2):
            rows.extend(page(code, p) or [])
    by = {}
    for r in rows:
        by[r["localTradedAt"]] = r
    keys = sorted(by)
    first = keys[0] if keys else None
    for d in ds:
        r = by.get(d)
        if r is None:
            res.append({"Date": d, "Ticker": "A" + code, "found": 0, "close": "", "chg": "", "pct": "", "base": "",
                        "api_prev_date": "", "api_prev_close": "", "api_first_seen": first or ""})
            continue
        i = keys.index(d)
        pr = by[keys[i - 1]] if i > 0 else None
        c, ch = num(r["closePrice"]), num(r["compareToPreviousClosePrice"])
        sign = r.get("compareToPreviousPrice", {}).get("code")
        if ch is not None and sign in ("4", "5"):   # 하한 · 하락 — 전일비는 절댓값으로 온다
            ch = -abs(ch)
        res.append({"Date": d, "Ticker": "A" + code, "found": 1, "close": c, "chg": ch, "pct": num(r["fluctuationsRatio"]),
                    "base": (c - ch) if (c is not None and ch is not None) else "",
                    "api_prev_date": pr["localTradedAt"] if pr else "", "api_prev_close": num(pr["closePrice"]) if pr else "",
                    "api_first_seen": first or ""})
    print(f"{code}: {len(ds)}일 · 쪽 {p_new}~{p_old} · 찾음 {sum(1 for x in res if x['Ticker'] == 'A' + code and x['found'])}", flush=True)

with open(f"{SP}/d2_official.csv", "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(res[0].keys()))
    w.writeheader()
    w.writerows(res)
print("rows", len(res))
