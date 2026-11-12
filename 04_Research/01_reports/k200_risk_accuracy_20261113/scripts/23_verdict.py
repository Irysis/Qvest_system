"""23_verdict.py — 사전등록 판정 규칙(PROTOCOL_v1 §4) 그대로 적용. 규칙 수치는 prereg_v1.json 에서 읽는다.

주 지표: OOS ΔLS = LS(도전) − LS(P3) · DM(HAC Bartlett · lag = ⌊4(T/100)^{2/9}⌋) 단측 · Holm(k)
관문 A: OOS ΔFZ0₅ ≤ 0 이거나 양측 p ≥ 0.05
관문 B: α ∈ {0.01, 0.05}: Kupiec p ≥ 0.01 또는 |hit−α| ≤ |hit_P3−α|
관문 C: IS ΔLS > 0
산출: output/verdict_v1.json
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats as sp_stats

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402


def nw_lag(n):
    return int(math.floor(4 * (n / 100.0) ** (2.0 / 9.0)))


def dm(la, lb):
    d = np.asarray(la, float) - np.asarray(lb, float)
    n = len(d); L = nw_lag(n)
    se = math.sqrt(S.nw_lrv(d, L) / n)
    t = d.mean() / se
    return {"n": n, "lag": L, "mean": float(d.mean()), "se": float(se), "t": float(t),
            "p_one_better": float(1 - sp_stats.norm.cdf(t)),   # 여기서 d = 이득(클수록 도전 우위)
            "p_two": float(2 * (1 - sp_stats.norm.cdf(abs(t))))}


def main():
    reg = json.loads((C.STUDY / "prereg" / "prereg_v1.json").read_text(encoding="utf-8"))
    base = reg["baseline"]["name"]
    chs = [c["name"] for c in reg["challengers"]]
    fam_alpha = reg["decision"]["family_alpha"]
    bm = pd.read_parquet(C.BM_PATH, columns=["Date"]); dd = pd.to_datetime(bm["Date"]).sort_values().reset_index(drop=True)
    nxt = pd.Series(dd.shift(-1).values, index=dd.values)
    def load(m):
        d = pd.read_parquet(C.OUT / f"sc_{m}.parquet"); d["Date"] = pd.to_datetime(d["Date"])
        d["seg"] = np.where(pd.to_datetime(d["Date"].map(nxt)) <= pd.Timestamp(reg["segments"]["tau"]), "IS", "OOS")
        return d
    D = {m: load(m) for m in [base] + chs}
    common = set.intersection(*[set(v["Date"]) for v in D.values()])
    for m in D:
        D[m] = D[m][D[m]["Date"].isin(common)].sort_values("Date").reset_index(drop=True)
    out = {"registered": reg["id"], "base": base, "k": len(chs), "family_alpha": fam_alpha, "n_common": len(common),
           "challengers": {}}
    pvals = {}
    for m in chs:
        r = {}
        for sg in ("IS", "OOS"):
            a = D[m][D[m]["seg"] == sg]; b = D[base][D[base]["seg"] == sg]
            r[sg] = {"ls": dm(a["ls"].values, b["ls"].values),                       # 이득 = LS 차
                     "fz0_gain": dm(-a["fz0_050"].values, -b["fz0_050"].values),     # 이득 = −FZ0 차
                     "crps_gain": dm(-a["crps"].values, -b["crps"].values),
                     "twcrps_gain": dm(-a["twcrps"].values, -b["twcrps"].values),
                     "hits": {str(al): {"c": float(a[f"hit_{int(al*1000):03d}"].mean()), "base": float(b[f"hit_{int(al*1000):03d}"].mean()),
                                        "kupiec_p_c": S.kupiec(a[f"hit_{int(al*1000):03d}"].values, al)["p"],
                                        "kupiec_p_base": S.kupiec(b[f"hit_{int(al*1000):03d}"].values, al)["p"]}
                              for al in (0.01, 0.05)}}
        pvals[m] = r["OOS"]["ls"]["p_one_better"]
        # 관문
        g = {}
        fz = r["OOS"]["fz0_gain"]
        g["A_fz0_not_worse"] = bool(fz["mean"] >= 0 or fz["p_two"] >= 0.05)
        okB = True
        for al, h in r["OOS"]["hits"].items():
            a_ = float(al)
            okB &= bool(h["kupiec_p_c"] >= 0.01 or abs(h["c"] - a_) <= abs(h["base"] - a_))
        g["B_var_calibration"] = okB
        g["C_is_consistency"] = bool(r["IS"]["ls"]["mean"] > 0)
        r["gates"] = g
        out["challengers"][m] = r
    # Holm 단계 보정
    order = sorted(pvals, key=lambda k: pvals[k])
    k = len(order); stop = False
    for i, m in enumerate(order):
        thr = fam_alpha / (k - i)
        rej = (not stop) and pvals[m] <= thr
        if not rej:
            stop = True
        out["challengers"][m]["holm"] = {"rank": i + 1, "threshold": thr, "p": pvals[m], "reject_null": bool(rej)}
    passed = []
    for m in chs:
        r = out["challengers"][m]
        r["pass"] = bool(r["holm"]["reject_null"] and all(r["gates"].values()))
        if r["pass"]:
            passed.append((r["OOS"]["ls"]["mean"], m))
    out["recommend"] = max(passed)[1] if passed else None
    C.write_json(C.OUT / "verdict_v1.json", out)
    for m in chs:
        r = out["challengers"][m]
        print(f"{m:12s} OOS ΔLS={r['OOS']['ls']['mean']:+.4f} t={r['OOS']['ls']['t']:+.2f} p1={r['holm']['p']:.4g} "
              f"Holm thr={r['holm']['threshold']:.4f} rej={r['holm']['reject_null']} gates={r['gates']} PASS={r['pass']} | "
              f"IS ΔLS={r['IS']['ls']['mean']:+.4f} t={r['IS']['ls']['t']:+.2f}")
    print("recommend:", out["recommend"])


if __name__ == "__main__":
    main()
