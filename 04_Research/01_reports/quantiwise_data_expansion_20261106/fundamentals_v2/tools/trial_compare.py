"""trial_compare.py — 팩터 DB 한 달 시범 산출 두 개(fdb_trial.R 출력)를 팩터별로 대조한다.

사용: python -I trial_compare.py <dir> <label_a> <label_b> <YYYYMMDD> [--fresh]
  <dir>/trial_<label>_<YYYYMMDD>.parquet 두 개를 (Ticker, Factor_Name) 로 맞춘다.
  --fresh = 지금 병합 표에서 그 해 직전 회계연도 DART 연간 자산총계가 있는 종목만(옛 표 값이 최신인 종목 · 2015~ 달).
출력: 팩터마다 값 있는 종목 수(a · b · 둘 다) · 순위 상관(Spearman) · 같은 값 비율 · 5% 안 비율 +
  전 종목 같은 값으로 굳은 팩터(죽은 배출) · 값이 같은 팩터 묶음. CSV = <dir>/cmp_<a>_<b>_<YYYYMMDD>[_fresh].csv
읽기 전용(운영 .cache 는 --fresh 때 fundamental_merged.parquet 만 읽는다).
"""
import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

pd.set_option("display.width", 250); pd.set_option("display.max_rows", 500)
args = [a for a in sys.argv[1:] if not a.startswith("--")]
FRESH = "--fresh" in sys.argv
d, la, lb, s = args[0], args[1], args[2], args[3]
root = os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot")


def load(lab):
    return pd.read_parquet(os.path.join(d, f"trial_{lab}_{s}.parquet"), columns=["Ticker", "Factor_Name", "Raw_Value", "Coverage"])


a, b = load(la), load(lb)
if FRESH:
    fy = int(s[:4]) - 1
    t = pq.read_table(os.path.join(root, ".cache", "fundamental_merged.parquet"), columns=["Ticker"],
                      filters=[("Source", "==", "DART"), ("Item", "==", "TotalAssets"), ("Period", "==", f"{fy}12")])
    fresh = set(t["Ticker"].to_pylist())
    a, b = a[a.Ticker.isin(fresh)], b[b.Ticker.isin(fresh)]
    print(f"--fresh: FY{fy} DART 자산총계가 있는 종목 {len(fresh)}")
for lab, x in ((la, a), (lb, b)):
    dead = [f for f, g in x.groupby("Factor_Name") if g.Raw_Value.dropna().nunique() <= 1]
    print(f"[{lab}] 행 {len(x):,} · 종목 {x.Ticker.nunique():,} · 팩터 {x.Factor_Name.nunique()} · 값 있음 {int(x.Coverage.sum()):,} · "
          f"굳은 팩터 {len(dead)}: {dead}")
m = a.merge(b, on=["Ticker", "Factor_Name"], how="outer", suffixes=("_a", "_b"))
rows = []
for f, g in m.groupby("Factor_Name"):
    na_, nb_ = int(g.Raw_Value_a.notna().sum()), int(g.Raw_Value_b.notna().sum())
    both = g.dropna(subset=["Raw_Value_a", "Raw_Value_b"])
    if len(both) >= 30:
        sp = both.Raw_Value_a.rank().corr(both.Raw_Value_b.rank())
        same = float(np.isclose(both.Raw_Value_a, both.Raw_Value_b, rtol=1e-6, atol=1e-12).mean())
        w5 = float((np.abs(both.Raw_Value_a - both.Raw_Value_b) <= 0.05 * np.maximum(np.abs(both.Raw_Value_a), 1e-12)).mean())
    else:
        sp = same = w5 = np.nan
    rows.append((f, na_, nb_, len(both), sp, same, w5))
r = pd.DataFrame(rows, columns=["factor", f"n_{la}", f"n_{lb}", "n_both", "spearman", "same", "within5pct"])
chg = r[~((r.same >= 0.999) & (r[f"n_{la}"] == r[f"n_{lb}"]))]
print(f"팩터 {len(r)} · 같음 {len(r) - len(chg)} · 다름 {len(chg)}")
print(chg.sort_values("spearman").to_string(index=False, float_format=lambda z: f"{z:.3f}"))
out = os.path.join(d, f"cmp_{la}_{lb}_{s}{'_fresh' if FRESH else ''}.csv")
r.to_csv(out, index=False)
print("CSV:", out)
