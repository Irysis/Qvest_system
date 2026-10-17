"""2604.16773 생략 점검 — 보유 기록 기술통계(성과 계산 아님 · 수익/NAV 를 만들지 않는다).

입력: <art>/04_holdings.csv(target_weight · 리밸 집행일별 목표 비중) · <art>/03_period_returns.csv(turnover 열 · 하네스 기록값)
출력: 표준출력만. 파일 쓰기 없음.
실행: "$QVEST_PY" -I holdings_stats.py C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/replication/20261016_202515_25636
"""
import sys, csv, math, statistics
from collections import defaultdict

sys.stdout.reconfigure(encoding="utf-8")  # 한글 표기 — 콘솔 코드페이지와 무관하게 UTF-8 로 낸다
art = sys.argv[1]
book = defaultdict(dict)  # date -> {ticker: target_weight}
with open(art + "/04_holdings.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        book[row["date"]][row["ticker"]] = float(row["target_weight"])
dates = sorted(book)


def q(v, p):
    v = sorted(v); k = (len(v) - 1) * p; lo = math.floor(k); hi = math.ceil(k)
    return v[lo] + (v[hi] - v[lo]) * (k - lo)


def summ(name, v):
    print(f"{name}: min {min(v):.4f} | p10 {q(v,.1):.4f} | median {q(v,.5):.4f} | mean {statistics.mean(v):.4f} | p90 {q(v,.9):.4f} | max {max(v):.4f}")


rows = []
for d in dates:
    w = book[d]
    gl = sum(x for x in w.values() if x > 0)
    gs = -sum(x for x in w.values() if x < 0)
    g = gl + gs
    a = sorted(((abs(x), t, x) for t, x in w.items()), reverse=True)
    c, n50, n90 = 0.0, None, None
    for k, x in enumerate(a, 1):
        c += x[0] / g
        if n50 is None and c >= 0.5:
            n50 = k
        if n90 is None and c >= 0.9:
            n90 = k
            break
    rows.append(dict(d=d, n=len(w), nl=sum(1 for x in w.values() if x > 0), ns=sum(1 for x in w.values() if x < 0),
                     r12=a[0][0] / a[1][0], r1_25=a[0][0] / sum(x[0] for x in a[1:5]),
                     gl=gl, gs=gs, net=gl - gs, g=g, top1=a[0][0] / g, top10=sum(x[0] for x in a[:10]) / g,
                     top25=sum(x[0] for x in a[:25]) / g, effn=1.0 / sum((x[0] / g) ** 2 for x in a),
                     n50=n50, n90=n90, top_long=a[0][2] > 0, top_t=a[0][1]))

print(f"리밸 장부 수: {len(rows)} ({rows[0]['d']} ~ {rows[-1]['d']})")
for name, key in [("보유 종목수", "n"), ("롱 종목수", "nl"), ("숏 종목수", "ns"), ("GL(롱 총노출)", "gl"),
                  ("GS(숏 총노출)", "gs"), ("순노출 GL-GS", "net"), ("총노출", "g"), ("top-1 비중/총노출", "top1"),
                  ("top-10 비중/총노출", "top10"), ("top-25 비중/총노출", "top25"), ("유효 종목수 1/HHI", "effn"),
                  ("총노출 50% 도달 종목수", "n50"), ("총노출 90% 도달 종목수", "n90"),
                  ("|w|1위 / |w|2위", "r12"), ("|w|1위 / (2~5위 합)", "r1_25")]:
    summ(name, [r[key] for r in rows])
print(f"|w|1위 >= 2 x |w|2위 인 장부: {sum(r['r12'] >= 2 for r in rows)}/{len(rows)} · 1위 >= 2~5위 합: {sum(r['r1_25'] >= 1 for r in rows)}/{len(rows)}")
print(f"순노출<0: {sum(r['net'] < 0 for r in rows)}/{len(rows)} · <-0.1: {sum(r['net'] < -0.1 for r in rows)} · >+0.1: {sum(r['net'] > 0.1 for r in rows)}")
print(f"top-1 이 롱인 장부: {sum(r['top_long'] for r in rows)}/{len(rows)} · top-1 부호 = 순노출 부호: {sum(r['top_long'] == (r['net'] > 0) for r in rows)}/{len(rows)}")
same = sum(1 for i in range(1, len(rows)) if rows[i]['top_t'] == rows[i - 1]['top_t'])
flip = sum(1 for i in range(1, len(rows)) if (rows[i]['net'] > 0) != (rows[i - 1]['net'] > 0))
print(f"top-1 종목이 직전 장부와 같음: {same}/{len(rows)-1} · 서로 다른 top-1 종목 수: {len(set(r['top_t'] for r in rows))} · 순노출 부호 반전: {flip}/{len(rows)-1}")
for lo, hi in [("2000", "2004"), ("2005", "2009"), ("2010", "2014"), ("2015", "2019"), ("2020", "2022"), ("2023", "2026")]:
    s = [r for r in rows if lo <= r["d"][:4] <= hi]
    print(f"  {lo}-{hi}: 장부 {len(s)} · 종목수 중앙 {q([r['n'] for r in s],.5):.0f} · top-1 중앙 {q([r['top1'] for r in s],.5):.3f} · "
          f"유효N 중앙 {q([r['effn'] for r in s],.5):.1f} · 순노출 평균 {statistics.mean([r['net'] for r in s]):+.3f}")

# 목표 장부 사이 Σ|Δw| 와 그 중 top 종목 몫(하네스 비용 산식 Σ|Δw_target| 와 같은 정의)
l1s, sh1, sh10 = [], [], []
for i in range(1, len(dates)):
    w, pw = book[dates[i]], book[dates[i - 1]]
    allt = set(w) | set(pw)
    l1 = sum(abs(w.get(t, 0.0) - pw.get(t, 0.0)) for t in allt)
    t1 = {max(w, key=lambda t: abs(w[t])), max(pw, key=lambda t: abs(pw[t]))}
    t10 = set(sorted(w, key=lambda t: -abs(w[t]))[:10]) | set(sorted(pw, key=lambda t: -abs(pw[t]))[:10])
    l1s.append(l1)
    sh1.append(sum(abs(w.get(t, 0.0) - pw.get(t, 0.0)) for t in t1) / l1)
    sh10.append(sum(abs(w.get(t, 0.0) - pw.get(t, 0.0)) for t in t10) / l1)
summ("Σ|Δw| (목표 장부 간)", l1s)
summ("  그중 직전·현재 top-1 몫", sh1)
summ("  그중 직전·현재 top-10 합집합 몫", sh10)

tv = []
with open(art + "/03_period_returns.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        if row["turnover"] not in ("", "NA"):
            tv.append(float(row["turnover"]))
summ(f"기록 turnover(03_period_returns · L1/2 · {len(tv)}행)", tv)
print(f"  turnover >= 0.9 인 리밸 비율: {sum(x >= 0.9 for x in tv)/len(tv):.3f}")

# 연말 기록 NAV 병치(02_nav.csv nav_net · 05_benchmark_returns.csv benchmark_nav — 기록값 그대로 · 수익 재계산 없음)
nav, bnav = {}, {}
with open(art + "/02_nav.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        nav[row["date"]] = float(row["nav_net"])
with open(art + "/05_benchmark_returns.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        bnav[row["date"]] = float(row["benchmark_nav"])
ye = {}
for d in sorted(nav):
    ye[d[:4]] = d  # 그해 마지막 기록일
print("연도 · 연말 기록일 · nav_net(기록) · KOSPI200 benchmark_nav(기록) · 그해 장부 순노출 평균 · top-1 중앙")
for y in sorted(ye):
    s = [r for r in rows if r["d"][:4] == y]
    d = ye[y]
    print(f"  {y} · {d} · {nav[d]:.4f} · {bnav.get(d, float('nan')):.4f} · "
          f"{statistics.mean([r['net'] for r in s]):+.3f} · {q([r['top1'] for r in s],.5):.3f}")
