"""P1R03 재측정 전후 — IS(≤ 2022-12-31) 일간 순수익이 같은가, OOS 에서 어디가 달라졌나(기술 통계 · 판정 아님).
실행: 저장소 루트에서 <venv python> 04_Research/01_reports/rawdata_seam_20260330_repair_20261113/tools/is_identity_check.py
출력: ../p1r03_is_identity.csv · 표준 출력 요약
"""
import csv
import json
import os

ROOT = os.environ.get("QM_ROOT", os.getcwd()).replace("\\", "/")
RD = f"{ROOT}/04_Research/programs/P1_RETURN/P1R03_factor_family_composites"
REP = f"{ROOT}/04_Research/01_reports/rawdata_seam_20260330_repair_20261113"
TAU = "2022-12-31"
CODES = ["FACCR", "FCONS", "FCROW", "FDEFE", "FGROW", "FINVE", "FLEVE", "FLIQU", "FMOME", "FQUAL", "FREGI", "FRISK", "FTECH", "FVALU", "TOTAL"]


def art(d, code):
    p = f"{d}/P1R03_{code}_C0.json"
    if not os.path.exists(p):
        return None
    j = json.load(open(p, encoding="utf-8"))
    return j.get("artifacts") if j.get("ok") else None


def rets(a):
    out = {}
    with open(f"{a}/03_period_returns.csv", encoding="utf-8-sig") as f:
        r = csv.DictReader(f)
        for x in r:
            out[x["date"]] = float(x["ret_net"]) if x["ret_net"] not in ("", "NA") else None
    return out


rows = []
for c in CODES:
    ao, an = art(f"{RD}/results", c), art(f"{RD}/remeasure_seam_20261113/results", c)
    if not ao or not an:
        rows.append({"code": c, "status": "missing"})
        continue
    o, n = rets(ao), rets(an)
    common = sorted(set(o) & set(n))
    is_d = [d for d in common if d <= TAU]
    oos_d = [d for d in common if d > TAU]
    def mx(ds):
        v = [abs(o[d] - n[d]) for d in ds if o[d] is not None and n[d] is not None]
        return max(v) if v else None
    diff_oos = [d for d in oos_d if o[d] is not None and n[d] is not None and abs(o[d] - n[d]) > 1e-12]
    rows.append({"code": c, "status": "ok", "n_is": len(is_d), "is_max_abs_diff": mx(is_d), "n_oos": len(oos_d),
                 "oos_days_changed": len(diff_oos), "oos_first_changed": diff_oos[0] if diff_oos else "",
                 "oos_last_changed": diff_oos[-1] if diff_oos else "", "only_old": len(set(o) - set(n)), "only_new": len(set(n) - set(o))})
keys = sorted({k for r in rows for k in r}, key=lambda k: ["code", "status", "n_is", "is_max_abs_diff", "n_oos", "oos_days_changed",
                                                         "oos_first_changed", "oos_last_changed", "only_old", "only_new"].index(k))
with open(f"{REP}/p1r03_is_identity.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=keys)
    w.writeheader()
    for r in rows:
        w.writerow(r)
for r in rows:
    print(r)
ok = [r for r in rows if r.get("status") == "ok"]
print("IS identical (max |diff| <= 1e-12):", sum(1 for r in ok if r["is_max_abs_diff"] is not None and r["is_max_abs_diff"] <= 1e-12), "/", len(ok))
