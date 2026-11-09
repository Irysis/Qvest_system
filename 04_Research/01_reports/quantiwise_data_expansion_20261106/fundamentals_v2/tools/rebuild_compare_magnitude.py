"""rebuild_compare_magnitude.py — 11-10 전 기간 대조(README §8 '재빌드 · 재계산 결과'). 사용: python -I <이 파일> <rebuild_compare_20261110.json> <out_json>
2차 대조 — 1차(rebuild_compare_20261110.json)에서 5% 넘게 바뀐 팩터의 변화 크기를 잰다(읽기만 · mmap 끔).
  표본 달 = 해마다 6 · 12월(2000~2026) + 잃은 (달, 팩터) 15개의 앞뒤 달
  팩터마다: 같은 종목 순위 상관(Spearman) 중앙값 · 상대 차 중앙값 · 값 있는 종목 수 비(새/옛)
  분류: 수치 잡음(순위 ≥ 0.9999 · 상대 차 < 1e-6) · 단조 변환(순위 ≥ 0.999) · 실질 변화
  또 Q16 정확히 0 비율을 2025~2026 달마다(2026 이 2016~2025 보다 높은 까닭)
"""
import json
import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

sys.stdout.reconfigure(encoding="utf-8")
R = os.environ.get("QM_ROOT", "G:/OneDrive/Quant_Module_Moltbot").replace(chr(92), "/")
OLD = R + "/.cache/factor_db_backup/fund_v2_20261109_114145/factor_db"
NEW = R + "/.cache/factor_db"
J1, OUT = sys.argv[1], sys.argv[2]
c1 = json.load(open(J1, encoding="utf-8"))
chg = pd.DataFrame(c1["changed"])
big = sorted(set(chg.loc[chg["share"] > 0.05, "factor"]))
lost = c1["lost"]
months = [f"{y}{m:02d}" for y in range(2000, 2027) for m in (6, 12) if f"{y}{m:02d}" <= "202610"]
cols = ["Ticker", "Factor_Name", "Raw_Value"]


def load(d, ym, factors=None):
    t = pq.read_table(f"{d}/factor_db_{ym}.parquet", columns=cols, memory_map=False,
                      filters=[("Factor_Name", "in", factors)] if factors else None)
    return t.to_pandas()


acc = {f: {"rho": [], "rel": [], "cov": []} for f in big}
for ym in months:
    o = load(OLD, ym, big); n = load(NEW, ym, big)
    m = o.merge(n, on=["Ticker", "Factor_Name"], suffixes=("_o", "_n"))
    m = m[np.isfinite(m["Raw_Value_o"]) & np.isfinite(m["Raw_Value_n"])]
    for f, g in m.groupby("Factor_Name"):
        if len(g) < 30:
            continue
        a, b = g["Raw_Value_o"], g["Raw_Value_n"]
        if a.nunique() < 3 or b.nunique() < 3:   # 시장 공통값(국면 팩터) — 종목 순위가 뜻이 없다
            rho = np.nan
        else:
            rho = a.rank().corr(b.rank())
        rel = float(np.median(np.abs(b - a) / np.maximum(1e-12, np.abs(a))))
        acc[f]["rho"].append(rho); acc[f]["rel"].append(rel)
    co = o.groupby("Factor_Name")["Raw_Value"].count(); cn = n.groupby("Factor_Name")["Raw_Value"].count()
    for f in big:
        if co.get(f, 0) > 0:
            acc[f]["cov"].append(cn.get(f, 0) / co.get(f, 0))
    print(" ", ym, flush=True) if ym.endswith("12") and int(ym[:4]) % 5 == 0 else None

rows = []
fund_src = set(chg.loc[chg["fund_src"], "factor"])
subset = set(c1["subset_factors"])
for f in big:
    r = np.array(acc[f]["rho"], dtype=float); rel = np.array(acc[f]["rel"], dtype=float)
    rho_med = float(np.nanmedian(r)) if np.isfinite(r).any() else None
    rel_med = float(np.nanmedian(rel)) if len(rel) else None
    kind = ("잡음" if (rho_med is None or rho_med >= 0.9999) and (rel_med or 0) < 1e-6 else
            "단조 변환" if rho_med is not None and rho_med >= 0.999 else "실질 변화")
    rows.append({"factor": f, "fund_src": f in fund_src, "subset": f in subset, "rho_median": rho_med,
                 "rho_min": float(np.nanmin(r)) if np.isfinite(r).any() else None, "rel_median": rel_med,
                 "cov_ratio_median": float(np.median(acc[f]["cov"])) if acc[f]["cov"] else None, "kind": kind,
                 "share_le2014": float(chg[(chg.factor == f) & (chg.period == "le2014")]["share"].sum()),
                 "share_ge2015": float(chg[(chg.factor == f) & (chg.period == "ge2015")]["share"].sum())})
df = pd.DataFrame(rows)

# 잃은 (달, 팩터) — 앞뒤 달 값 있는 종목 수(옛 · 새)
lost_ctx = []
allm = sorted(p[-14:-8] for p in __import__("glob").glob(NEW + "/factor_db_*.parquet"))
for ym, f, nold in lost:
    i = allm.index(ym)
    ctx = {}
    for k in allm[max(0, i - 2): i + 3]:
        o = load(OLD, k, [f]); n = load(NEW, k, [f])
        ctx[k] = [int(o["Raw_Value"].notna().sum()), int(n["Raw_Value"].notna().sum())]
    lost_ctx.append({"ym": ym, "factor": f, "old_n": nold, "context_old_new": ctx})

# Q16 정확히 0 비율 — 2025~2026 달마다
q16 = {}
for k in [m_ for m_ in allm if "202501" <= m_ <= "202610"]:
    o = load(OLD, k, ["Q16_Debt_to_Assets"]); n = load(NEW, k, ["Q16_Debt_to_Assets"])
    q16[k] = [round(float((o.Raw_Value == 0).mean()), 3), round(float((n.Raw_Value == 0).mean()), 3), int(n.Raw_Value.notna().sum())]

json.dump({"schema": "factor_db_rebuild_compare2/v1", "sample_months": months, "factors": rows, "lost_context": lost_ctx, "q16_zero_monthly": q16},
          open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
pd.set_option("display.width", 250); pd.set_option("display.max_rows", 400)
for grp, s in df.groupby(["fund_src", "kind"]):
    print(f"\n== 재무 원천={grp[0]} · {grp[1]} · {len(s)}개")
    s = s.sort_values("rho_median")
    print(s[["factor", "rho_median", "rho_min", "rel_median", "cov_ratio_median", "share_le2014", "share_ge2015"]].head(60).to_string(index=False))
print("\n== 잃은 (달, 팩터) 앞뒤 달 [옛, 새]")
for x in lost_ctx:
    print(" ", x["ym"], x["factor"], x["context_old_new"])
print("\n== Q16 정확히 0 비율 [옛, 새, 새 값 수]")
print(" ", q16)
