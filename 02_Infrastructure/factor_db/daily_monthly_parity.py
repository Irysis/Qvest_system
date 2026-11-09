"""daily_monthly_parity.py — 일간 DB(fdb_daily) 와 월간 DB(factor_db) 가 같은 이름에 같은 값을 담는지 월말마다 대조한다.

왜(2026-11-09): 일간 접근자 load_daily_factors 는 월간 값으로 잰 IC 부호를 일간 값에 그대로 곱한다. 그런데 같은 이름의
일간 값이 월간 값의 부호 반대이거나(베타 · 변동성 · 크기 계열) 정의가 다른 팩터가 많았다(2026-11-09 실측 4달: 같음 86 ·
반대 56 · 다름 146 / 공통 288). 이 표가 그 사실을 기록하고, 접근자가 이 표로 부호를 바로잡거나 정렬을 거부한다.

사용: python -I daily_monthly_parity.py [--months YYYYMM ...] [--out PATH] [--dry-run]
  기본 달 = 두 DB 에 모두 있는 달 중 매년 6월 · 12월(2000~) + 가장 최근 두 달.
  비교 = 월간 파일의 신호일(Date) 과 같은 날(없으면 그 전 마지막 날) 의 일간 행 · 종목 맞춤 · 순위 상관(Spearman).
판정(팩터마다 · 값이 있는 달 전부):
  same      = 모든 달 ρ ≥ SAME_MIN
  negated   = 모든 달 ρ ≤ −SAME_MIN
  mismatch  = 그 밖(정의가 다르다 — 같은 이름 다른 값)
  constant  = 비교할 달마다 한쪽이 상수(국면 · 시장 공통 값 — 순위 상관 무의미 · 값 대조로 판정)
  monthly_only / daily_only = 한쪽에만 있다
SAME_MIN = 0.98 — 같은 양이면 일간 윈저라이즈(1/99 · phase10) 와 월간 미캡의 차이만 남는다(2026-07-25 M01 월말 대조
  pearson 0.9987 · spearman 0.9952 실측 — factor-db.md). 0.98 은 그 차이를 넉넉히 덮고, 창 길이 · 정의가 다른 팩터
  (실측 0.5~0.95)는 걸러 낸다. 검사 수치이지 연구 결정이 아니다.
읽기 전용 — 월간 Date · Ticker · Factor_Name · Raw_Value 와 일간 Date · Ticker · 팩터 열만 읽는다(빌드 산출물 검사).
"""
import json
import os
import re
import sys
import tempfile
from datetime import date

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot")
MDIR = os.path.join(ROOT, ".cache", "factor_db")
DDIR = os.path.join(ROOT, ".cache", "factor_db_daily")
OUT = os.path.join(ROOT, "06_Registry", "factor_daily_monthly_parity.json")
SAME_MIN = 0.98
MIN_N = 50


def _months(d, pat):
    return sorted(m.group(1) for m in (re.match(pat, x) for x in os.listdir(d)) if m)


def _default_months():
    mm = set(_months(MDIR, r"^factor_db_(\d{6})\.parquet$")) & set(_months(DDIR, r"^fdb_daily_(\d{6})\.parquet$"))
    mm = sorted(m for m in mm if m >= "200001")
    pick = {m for m in mm if m[4:] in ("06", "12")} | set(mm[-2:])
    return sorted(pick)


def _rank_corr(a, b):
    """Spearman = 평균 순위(동순위 평균)의 Pearson — 이진 · 동순위 많은 팩터도 바르게 잰다."""
    ra = pd.Series(a).rank(method="average").values
    rb = pd.Series(b).rank(method="average").values
    if ra.std() == 0 or rb.std() == 0:
        return None
    return float(np.corrcoef(ra, rb)[0, 1])


def compare_month(ym):
    mt = pq.read_table(os.path.join(MDIR, f"factor_db_{ym}.parquet"),
                       columns=["Date", "Ticker", "Factor_Name", "Raw_Value"]).to_pandas()
    sig = mt["Date"].iloc[0]
    dt = pq.read_table(os.path.join(DDIR, f"fdb_daily_{ym}.parquet")).to_pandas()
    dt["Date"] = dt["Date"].astype("datetime64[ns]")
    days = sorted(d for d in dt["Date"].unique() if d <= np.datetime64(sig, "ns"))
    if not days:
        return str(sig)[:10], None, {}
    day = days[-1]
    sub = dt[dt["Date"] == day].set_index("Ticker")
    res = {}
    for f, g in mt.groupby("Factor_Name"):
        if f not in sub.columns:
            continue
        x = g.set_index("Ticker")["Raw_Value"].astype(float)
        y = sub[f].astype(float)
        j = x.index.intersection(y.index)
        xv, yv = x.loc[j].values, y.loc[j].values
        ok = np.isfinite(xv) & np.isfinite(yv)
        xv, yv = xv[ok], yv[ok]
        if len(xv) < MIN_N:
            continue
        if np.unique(xv).size < 2 or np.unique(yv).size < 2:   # 횡단면 상수(국면 · 시장 공통 값) — 순위 상관 무의미
            res[f] = {"rho": None, "n": int(len(xv)), "const": True,
                      "max_abs_diff": float(np.max(np.abs(xv - yv))) if len(xv) else None}
            continue
        res[f] = {"rho": round(_rank_corr(xv, yv), 5), "n": int(len(xv))}
    mon_names = set(mt["Factor_Name"].unique())
    day_names = set(c for c in sub.columns if c not in ("Date",))
    return str(sig)[:10], str(day)[:10], {"pairs": res, "monthly": sorted(mon_names), "daily": sorted(day_names)}


def classify(per):
    rh = [v["rho"] for v in per.values() if v.get("rho") is not None]
    if not rh:
        if any(v.get("const") for v in per.values()):
            same_val = all((v.get("max_abs_diff") is not None and v["max_abs_diff"] < 1e-9) for v in per.values() if v.get("const"))
            return "constant_same" if same_val else "constant"
        return "no_overlap"
    if min(rh) >= SAME_MIN:
        return "same"
    if max(rh) <= -SAME_MIN:
        return "negated"
    return "mismatch"


def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    out = OUT
    if "--out" in args:
        out = args[args.index("--out") + 1]
    months = []
    if "--months" in args:
        i = args.index("--months") + 1
        while i < len(args) and re.fullmatch(r"\d{6}", args[i]):
            months.append(args[i]); i += 1
    months = months or _default_months()
    per_factor, seen_m, seen_d, checked = {}, set(), set(), []
    for ym in months:
        sig, day, r = compare_month(ym)
        if not r:
            continue
        checked.append({"ym": ym, "monthly_date": sig, "daily_date": day, "n_pairs": len(r["pairs"])})
        seen_m |= set(r["monthly"]); seen_d |= set(r["daily"])
        for f, v in r["pairs"].items():
            per_factor.setdefault(f, {})[ym] = v
        print(f"{ym} 월간 {sig} · 일간 {day} · 비교 {len(r['pairs'])}")
    factors = {}
    for f, per in sorted(per_factor.items()):
        rh = [v["rho"] for v in per.values() if v.get("rho") is not None]
        factors[f] = {"status": classify(per), "n_months": len(per),
                      "rho_min": min(rh) if rh else None, "rho_max": max(rh) if rh else None,
                      "rho_median": float(np.median(rh)) if rh else None,
                      "per_month": {k: v.get("rho") for k, v in sorted(per.items())}}
    for f in sorted(seen_m - seen_d):
        factors.setdefault(f, {"status": "monthly_only"})
    for f in sorted(seen_d - seen_m - {"Ticker"}):
        factors.setdefault(f, {"status": "daily_only"})
    counts = {}
    for v in factors.values():
        counts[v["status"]] = counts.get(v["status"], 0) + 1
    res = {"schema": "factor_daily_monthly_parity_v1", "generated": date.today().isoformat(),
           "same_min": SAME_MIN, "min_n": MIN_N, "months": checked, "counts": counts, "factors": factors,
           "_doc": "status = same(부호 · 정의 같음) | negated(부호만 반대) | mismatch(정의 다름) | constant(_same) | monthly_only | daily_only | no_overlap. "
                   "load_daily_factors 가 읽는다(정렬 시 negated = 부호 보정 · mismatch = 정렬 거부). 생성 = 02_Infrastructure/factor_db/daily_monthly_parity.py"}
    print("판정:", counts)
    if dry:
        return
    d = os.path.dirname(os.path.abspath(out))
    fd, tmp = tempfile.mkstemp(prefix=".parity_", suffix=".json", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(res, fh, ensure_ascii=False, indent=1)
        fh.write("\n")
    os.replace(tmp, out)
    print("JSON:", out)


if __name__ == "__main__":
    main()
