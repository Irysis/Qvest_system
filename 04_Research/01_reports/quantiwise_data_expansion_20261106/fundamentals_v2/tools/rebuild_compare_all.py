"""rebuild_compare_all.py — 11-10 전 기간 대조(README §8 '재빌드 · 재계산 결과'). 사용: python -I <이 파일> <out_json>
재빌드 전 사본(fund_v2_20261109_114145) 대 지금 팩터 DB — 전 기간 월 파일 대조(읽기만 · mmap 끔).

묻는 것
  ① 잃은 팩터: 옛 판에 값이 있던 (달, 팩터)가 새 판에서 값 0 이 됐나(회귀)
  ② 값 있는 종목 수: 재무 원천 팩터(등록부 data_source fundamental · fundamental_xlsx)가 줄었나
  ③ 부채 · EV 계열 0 덮어쓰기(2015~): Q16 등 '정확히 0' 비율이 해마다 어떻게 바뀌었나
  ④ 바뀐 몫: 팩터 × 시기(≤2014 · 2015~)별 값이 바뀐 행 비율 — 의도한 수리(부분 재계산 13팩터 · 재무 v2) 밖의 큰 변화가 있나
출력: JSON(인자 1) · 요약 출력
"""
import glob
import json
import os
import sys
import time

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

sys.stdout.reconfigure(encoding="utf-8")
R = os.environ.get("QM_ROOT", "G:/OneDrive/Quant_Module_Moltbot").replace(chr(92), "/")
OLD = R + "/.cache/factor_db_backup/fund_v2_20261109_114145/factor_db"
NEW = R + "/.cache/factor_db"
OUT = sys.argv[1]
SKIP = {"202611"}  # 이번 달 = 일일 체인이 따로 짓는다(사본 뒤 날짜가 다르다)
COLS = ["Ticker", "Factor_Name", "Raw_Value"]
DEBT_EV = ["Q15", "Q16", "D60", "R17", "V19", "XF_LL01", "V07", "V13", "V14", "V22"]

reg = json.load(open(R + "/02_Infrastructure/factor_db/factor_registry.json", encoding="utf-8"))
fund_src = {k for k, v in reg.items() if v.get("data_source") in ("fundamental", "fundamental_xlsx")}

# 부분 재계산 대상(작업자 기록 per_factor 키)
wrec = open(R + "/.cache/scheduler_logs/subset_worker_20261109_175958_r0_w0.jsonl", encoding="utf-8").read().strip().splitlines()[-1]
subset = sorted(json.loads(wrec)["per_factor"].keys())


def code_of(name):  # Q16_DebtRatio → Q16 · XF_LL01_x → XF_LL01
    parts = name.split("_")
    return "_".join(parts[:2]) if parts[0] == "XF" else parts[0]


def ym_of(p):
    return os.path.basename(p)[10:16]


old_m = {ym_of(p): p for p in glob.glob(OLD + "/factor_db_*.parquet")}
new_m = {ym_of(p): p for p in glob.glob(NEW + "/factor_db_*.parquet")}
months = sorted((set(old_m) & set(new_m)) - SKIP)
print(f"달: 옛 {len(old_m)} · 새 {len(new_m)} · 대조 {len(months)}({months[0]}~{months[-1]}) · 재무 원천 팩터(등록부) {len(fund_src)} · 부분 재계산 {len(subset)}")

per_fy = {}   # (factor, period) -> counters
lost, gained = [], []
debt_zero = {}  # (code, year) -> [old_nn, old_zero, new_nn, new_zero, months]
fund_cov = {}   # month -> (n_fund_factors, n_shrunk>5%, median ratio)
t0 = time.time()
for i, ym in enumerate(months):
    o = pq.read_table(old_m[ym], columns=COLS, memory_map=False).to_pandas()
    n = pq.read_table(new_m[ym], columns=COLS, memory_map=False).to_pandas()
    period = "le2014" if ym <= "201412" else "ge2015"
    year = ym[:4]
    so = o.groupby("Factor_Name")["Raw_Value"].agg(nn="count", z=lambda s: int((s == 0).sum()))
    sn = n.groupby("Factor_Name")["Raw_Value"].agg(nn="count", z=lambda s: int((s == 0).sum()))
    allf = so.index.union(sn.index)
    so = so.reindex(allf, fill_value=0)
    sn = sn.reindex(allf, fill_value=0)
    for f in allf:
        if so.at[f, "nn"] > 0 and sn.at[f, "nn"] == 0:
            lost.append([ym, f, int(so.at[f, "nn"])])
        elif so.at[f, "nn"] == 0 and sn.at[f, "nn"] > 0:
            gained.append([ym, f, int(sn.at[f, "nn"])])
    # ② 재무 원천 팩터 값 있는 종목 수
    ff = [f for f in allf if f in fund_src and so.at[f, "nn"] > 0]
    if ff:
        ratio = (sn.loc[ff, "nn"] / so.loc[ff, "nn"]).astype(float)
        fund_cov[ym] = {"n": len(ff), "shrunk_5pct": [f for f in ff if ratio[f] < 0.95], "median_ratio": float(ratio.median())}
    # ③ 부채 · EV 계열 정확히 0 비율
    for f in allf:
        c = code_of(f)
        if c in DEBT_EV:
            k = (f, year)
            a = debt_zero.setdefault(k, [0, 0, 0, 0, 0])
            a[0] += int(so.at[f, "nn"]); a[1] += int(so.at[f, "z"]); a[2] += int(sn.at[f, "nn"]); a[3] += int(sn.at[f, "z"]); a[4] += 1
    # ④ 바뀐 몫(같은 키 · 값 다름 또는 결측 여부 다름)
    m = o.merge(n, on=["Ticker", "Factor_Name"], how="outer", suffixes=("_o", "_n"), indicator=True)
    vo, vn = m["Raw_Value_o"].to_numpy(), m["Raw_Value_n"].to_numpy()
    both = ~np.isnan(vo) & ~np.isnan(vn)
    diff = np.zeros(len(m), dtype=bool)
    diff[both] = np.abs(vo[both] - vn[both]) > 1e-9 * np.maximum(1.0, np.abs(vo[both]))
    diff |= np.isnan(vo) != np.isnan(vn)
    m["_d"] = diff
    g = m.groupby("Factor_Name")["_d"].agg(["sum", "size"])
    for f, row in g.iterrows():
        k = (f, period)
        a = per_fy.setdefault(k, [0, 0, 0])
        a[0] += int(row["sum"]); a[1] += int(row["size"]); a[2] += 1 if row["sum"] > 0 else 0
    if (i + 1) % 40 == 0:
        print(f"  {i + 1}/{len(months)} {ym} · {time.time() - t0:.0f}s", flush=True)

# ---- 정리 ------------------------------------------------------------------------------------
chg = []
for (f, p), (d, s, mc) in per_fy.items():
    chg.append({"factor": f, "period": p, "changed_rows": d, "rows": s, "share": d / s if s else 0.0, "months_changed": mc,
                "subset": f in subset, "fund_src": f in fund_src})
chg_df = pd.DataFrame(chg)
dz = [{"factor": f, "year": y, "old_nn": a[0], "old_zero_share": a[1] / a[0] if a[0] else None,
       "new_nn": a[2], "new_zero_share": a[3] / a[2] if a[2] else None, "months": a[4]} for (f, y), a in sorted(debt_zero.items())]
shrunk = {ym: v for ym, v in fund_cov.items() if v["shrunk_5pct"]}
res = {"schema": "factor_db_rebuild_compare/v1", "old": OLD, "new": NEW, "months": len(months), "range": [months[0], months[-1]],
       "skip": sorted(SKIP), "subset_factors": subset, "n_fund_src": len(fund_src),
       "lost": lost, "gained_n": len(gained), "gained_sample": gained[:50],
       "fund_cov_shrunk_months": shrunk, "fund_cov_median_ratio_by_year": {},
       "debt_ev_zero": dz, "changed": chg, "seconds": round(time.time() - t0)}
by_year = {}
for ym, v in fund_cov.items():
    by_year.setdefault(ym[:4], []).append(v["median_ratio"])
res["fund_cov_median_ratio_by_year"] = {y: float(np.median(v)) for y, v in sorted(by_year.items())}
json.dump(res, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

print(f"\n끝 {time.time() - t0:.0f}s → {OUT}")
print(f"① 잃은 (달, 팩터) {len(lost)} · 새로 생긴 {len(gained)}")
for r_ in lost[:20]:
    print("   잃음", r_)
print(f"② 재무 원천 팩터 값 있는 종목 수가 5% 넘게 준 달 {len(shrunk)}")
for ym, v in list(shrunk.items())[:12]:
    print("   ", ym, v["shrunk_5pct"][:8])
print("   해마다 중앙 비율(새/옛):", {y: round(v, 3) for y, v in res["fund_cov_median_ratio_by_year"].items() if y >= "2000"})
print("③ 부채 · EV 계열 정확히 0 비율(옛 → 새) — 해마다")
dzd = pd.DataFrame(dz)
if len(dzd):
    for f in sorted(dzd["factor"].unique()):
        s = dzd[(dzd["factor"] == f) & (dzd["year"] >= "2012")]
        print("   ", f, " ".join(f"{r.year}:{(r.old_zero_share or 0):.2f}→{(r.new_zero_share or 0):.2f}" for r in s.itertuples()))
print("④ 바뀐 몫 — 부분 재계산 13팩터")
for p in ("le2014", "ge2015"):
    s = chg_df[(chg_df["period"] == p) & chg_df["subset"]].sort_values("factor")
    print("   ", p, " ".join(f"{r.factor}:{r.share:.2f}" for r in s.itertuples()))
for p in ("le2014", "ge2015"):
    s = chg_df[(chg_df["period"] == p) & ~chg_df["subset"]].sort_values("share", ascending=False)
    big = s[s["share"] > 0.05]
    print(f"④ {p} 부분 재계산 밖 팩터 {len(s)} 중 5% 넘게 바뀜 {len(big)} · 그중 재무 원천 {int(big['fund_src'].sum())}")
    print("    상위 25:", " ".join(f"{r.factor}:{r.share:.2f}" for r in big.head(25).itertuples()))
    nf = big[~big["fund_src"]]
    print(f"    재무 원천 아닌데 5% 넘게 바뀜 {len(nf)}:", " ".join(f"{r.factor}:{r.share:.2f}" for r in nf.head(30).itertuples()))
