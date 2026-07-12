# -*- coding: utf-8 -*-
"""census_raw → 최종 census JSON 집계 + 콘솔 표 출력 (MD 작성 재료)."""
import json, sys

OUT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/dart_census"
raw = json.load(open(OUT + "/census_raw_20260713.json", encoding="utf-8"))
st = json.load(open(OUT + "/census_state_20260713.json", encoding="utf-8"))

fin = {"meta": dict(raw["meta"], calls_used=st["calls"], aborted=st["aborted"],
                    abort_reason=st.get("abort_reason"), n_status013=st.get("n_status013"),
                    started=st.get("started"), finished=st.get("finished"))}

# --- A. market grid pivot ---
grid = {}
for g in raw.get("p1_grid", []):
    key = "%s_%s" % (g["detail_ty"], g["last_reprt_at"])
    grid.setdefault(key, {})[g["year"]] = g["total_count"]
years = sorted({g["year"] for g in raw.get("p1_grid", [])})
tblA = []
for y in years:
    d = grid.get("D001_N", {}).get(y)
    f1n = grid.get("F001_N", {}).get(y)
    f1y = grid.get("F001_Y", {}).get(y)
    f2n = grid.get("F002_N", {}).get(y)
    tblA.append(dict(year=y, D001=d, F001_all=f1n, F001_final=f1y,
                     F001_superseded=(None if (f1n is None or f1y is None) else f1n - f1y),
                     F002_all=f2n))
fin["A_market_grid"] = tblA
pat = {}
for g in raw.get("p1_grid", []):
    k = g["detail_ty"]
    p = g.get("page1x4_patterns", {})
    a = pat.setdefault(k, {kk: 0 for kk in p})
    for kk, v in p.items():
        a[kk] += v
fin["A_page1_patterns_by_type"] = pat

# --- B. universe pledge (majorstock) ---
p3 = raw.get("p3_majorstock", {})
fin["B_universe_majorstock_by_year"] = p3.get("by_year", {})
corps = p3.get("corps", [])
fin["B_summary"] = dict(
    n_corps=len(corps),
    n_corps_with_reports=sum(1 for c in corps if c["n"] > 0),
    n_corps_with_ctr_pos=sum(1 for c in corps if c["n_ctr_pos"] > 0),
    n_corps_with_resn_pledge=sum(1 for c in corps if c.get("n_resn_pledge", 0) > 0),
    total_reports=sum(c["n"] for c in corps),
    total_ctr_pos=sum(c["n_ctr_pos"] for c in corps),
    total_resn_pledge=sum(c.get("n_resn_pledge", 0) for c in corps),
    yr_min_dist={},
)
ymd = {}
for c in corps:
    if c["yr_min"] is not None:
        ymd[str(c["yr_min"])] = ymd.get(str(c["yr_min"]), 0) + 1
fin["B_summary"]["yr_min_dist"] = dict(sorted(ymd.items()))
fin["B_report_tp_dist"] = p3.get("report_tp_dist", {})
fin["B_resn_top"] = p3.get("resn_top", {})

# --- C. universe audit (per-corp F group) ---
p4 = raw.get("p4_audit", {})
fin["C_universe_audit_by_year"] = p4.get("by_year", {})
ac = p4.get("corps", [])
fin["C_summary"] = dict(
    n_corps=len(ac),
    n_truncated_gt2pages=p4.get("n_truncated", 0),
    total_f_rows=sum(c["n_rows"] for c in ac),
    total_corr=sum(c["n_corr"] for c in ac),
    n_corps_with_corr=sum(1 for c in ac if c["n_corr"] > 0),
    yr_min_dist={},
)
ymd2 = {}
for c in ac:
    if c.get("yr_min") is not None:
        ymd2[str(c["yr_min"])] = ymd2.get(str(c["yr_min"]), 0) + 1
fin["C_summary"]["yr_min_dist"] = dict(sorted(ymd2.items()))

# --- probes ---
fin["D_probes"] = raw.get("p2_probe", {})

with open(OUT + "/census_pledge_audit_20260713.json.tmp", "w", encoding="utf-8") as f:
    json.dump(fin, f, ensure_ascii=False, indent=1)
import os
os.replace(OUT + "/census_pledge_audit_20260713.json.tmp", OUT + "/census_pledge_audit_20260713.json")

# console tables (ascii-safe)
print("== A. market grid ==")
print("year  D001   F001_all F001_fin  superseded  F002_all")
for r in tblA:
    print("%d %6s %8s %8s %10s %9s" % (r["year"], r["D001"], r["F001_all"], r["F001_final"],
                                       r["F001_superseded"], r["F002_all"]))
print("patterns(page1x4):", json.dumps(pat, ensure_ascii=True))
print("== B. universe majorstock by_year ==")
for y, v in sorted(fin["B_universe_majorstock_by_year"].items()):
    print(y, v)
print("B_summary:", json.dumps(fin["B_summary"], ensure_ascii=True))
print("report_tp:", json.dumps(fin["B_report_tp_dist"], ensure_ascii=True))
print("== C. universe audit by_year ==")
for y, v in sorted(fin["C_universe_audit_by_year"].items()):
    print(y, v)
print("C_summary:", json.dumps(fin["C_summary"], ensure_ascii=True))
print("== meta ==", json.dumps(fin["meta"], ensure_ascii=True))
