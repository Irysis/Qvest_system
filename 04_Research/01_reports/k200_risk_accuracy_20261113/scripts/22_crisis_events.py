"""22_crisis_events.py — LT 20/20 위기 구간 성적 · 위기 초입 적응 · 브리핑 경보 규칙의 적중/거짓 경보.

위기 = Lunde & Timmermann (2004) 20/20 첫 통과(behavior_card.R::bc_crises_lt 와 같은 알고리즘 · scoring.lt_crises).
  구간 = 고점 → 바닥 · 초입 = 고점 뒤 20거래일 · 사전 = 고점 앞 20거래일.
경보 규칙(운영 600_morning_brief.py 그대로):
  red    = σ > 2.8 ∨ λ < −0.3 ∨ P(−10%) > 1%
  yellow+= σ > 2.0 ∨ λ < −0.2 ∨ P(−10%) > 0.5%   (주의 이상)
  p5     = P(−5%) > 5%                             (알림 '🟡 P(-5%) 높음')
사건 = 다음 거래일 수익 ≤ −3% · ≤ −5%.
--max_outcome YYYY-MM-DD : 결과일 상한(설계 단계는 2022-12-31)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402

WIN = 20


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", type=str, default="P3,GJR,EWMA,HS500")
    ap.add_argument("--max_outcome", type=str, default="2022-12-31")
    ap.add_argument("--tag", type=str, default="design_IS")
    args = ap.parse_args()
    models = [m for m in args.models.split(",") if m]
    bm = pd.read_parquet(C.BM_PATH); bm["Date"] = pd.to_datetime(bm["Date"]); bm = bm.sort_values("Date").reset_index(drop=True)
    cr = S.lt_crises(bm["Date"], bm["BM_Ret"].fillna(0.0).values)
    nxt = pd.Series(bm["Date"].shift(-1).values, index=bm["Date"].values)
    lim = pd.Timestamp(args.max_outcome)
    data = {}
    for m in models:
        d = pd.read_parquet(C.OUT / f"sc_{m}.parquet"); d["Date"] = pd.to_datetime(d["Date"])
        d["y_date"] = pd.to_datetime(d["Date"].map(nxt))
        data[m] = d[d["y_date"] <= lim].reset_index(drop=True)
    common = set.intersection(*[set(v["Date"]) for v in data.values()])
    for m in models:
        data[m] = data[m][data[m]["Date"].isin(common)].reset_index(drop=True)
    d0 = data[models[0]]
    lo, hi = d0["Date"].min(), d0["Date"].max()
    cr = cr[(cr["trough"] >= lo) & (cr["peak"] <= hi)].reset_index(drop=True)
    out = {"crises": [], "alerts": {}, "max_outcome": args.max_outcome, "window": [str(lo.date()), str(hi.date())]}
    for _, c in cr.iterrows():
        row = {"peak": str(c.peak.date()), "confirm": str(c.confirm.date()), "trough": str(c.trough.date()),
               "depth": float(c.depth), "ongoing": bool(c.ongoing), "models": {}}
        for m in models:
            d = data[m]
            inw = d[(d["Date"] >= c.peak) & (d["Date"] < c.trough)]
            pk = d.index[d["Date"] >= c.peak]
            if len(inw) == 0 or len(pk) == 0:
                continue
            i0 = pk[0]
            on = d.iloc[i0:i0 + WIN]
            pre = d.iloc[max(0, i0 - WIN):i0]
            base = d.iloc[max(0, i0 - 250):max(0, i0 - WIN)]
            row["models"][m] = {
                "n": int(len(inw)), "ls": float(inw["ls"].mean()) if inw["ls"].notna().any() else None,
                "crps": float(inw["crps"].mean()), "twcrps": float(inw["twcrps"].mean()),
                "fz0": float(inw["fz0_050"].mean()), "hit5": float(inw["hit_050"].mean()), "hit1": float(inw["hit_010"].mean()),
                "sd_pred": float(inw["sd_pred"].mean()), "sd_real": float(inw["y"].std()),
                "onset_hits5": int(on["hit_050"].sum()), "onset_hits1": int(on["hit_010"].sum()),
                "onset_sd_ratio": float(on["sd_pred"].mean() / on["y"].std()) if on["y"].std() > 0 else None,
                "pre_p3_vs_base": float(pre["p_le_3"].mean() / base["p_le_3"].mean()) if len(base) and base["p_le_3"].mean() > 0 else None,
            }
        out["crises"].append(row)
    # 경보 규칙(P3 만 — 운영 규칙이 P3 모수를 읽는다)
    if "P3" in data:
        d_all = data["P3"]
        tau = pd.Timestamp("2022-12-31")
        subsets = {"ALL": d_all, "IS": d_all[d_all["y_date"] <= tau], "OOS": d_all[d_all["y_date"] > tau]}
        out["alerts_by_seg"] = {}
        for sname, d in subsets.items():
            if len(d) == 0:
                continue
            p10 = d["p_le_10"]; sg = d["sigma"]; lm = d["lam"]
            rules = {"red": (sg > 2.8) | (lm < -0.3) | (p10 > 0.01),
                     "yellow_plus": (sg > 2.0) | (lm < -0.2) | (p10 > 0.005),
                     "p5_gt_5pct": d["p_le_5"] > 0.05}
            blk = {}
            for thr in (-3.0, -5.0):
                ev = d["y"] <= thr
                blk[str(int(thr))] = {k: S.alert_metrics(v.values, ev.values) for k, v in rules.items()}
                blk[str(int(thr))]["lambda_auc"] = S.auc(-lm.values, ev.values.astype(int))
                blk[str(int(thr))]["sigma_auc"] = S.auc(sg.values, ev.values.astype(int))
                blk[str(int(thr))]["p_auc"] = S.auc(d[f"p_le_{int(-thr)}"].values, ev.values.astype(int))
            out["alerts_by_seg"][sname] = blk
        out["alerts"] = out["alerts_by_seg"]["ALL"]
    C.write_json(C.OUT / f"crisis_events_{args.tag}.json", out)
    for r in out["crises"]:
        print(f"\n위기 고점 {r['peak']} → 바닥 {r['trough']} 깊이 {r['depth']:.0%}")
        for m, v in r["models"].items():
            print(f"  {m:7s} n={v['n']:4d} LS={v['ls'] if v['ls'] is not None else float('nan'):.3f} CRPS={v['crps']:.3f} "
                  f"hit5={v['hit5']:.3f} hit1={v['hit1']:.3f} sdPred={v['sd_pred']:.2f} sdReal={v['sd_real']:.2f} "
                  f"초입20일 5%위반={v['onset_hits5']} 1%위반={v['onset_hits1']}")
    for thr, v in out["alerts"].items():
        print(f"\n경보 규칙 vs 다음날 ≤ {thr}%:")
        for k, a in v.items():
            if isinstance(a, dict):
                print(f"  {k:12s} 경보 {a['alerts']:4d}일 · 사건 {a['events']:3d} · 적중률 {a['hit_rate']:.2f} · 거짓경보비 {a['false_alarm_ratio']:.2f} · 정밀도 {a['precision']:.3f}")
            else:
                print(f"  {k}: {a:.3f}")


if __name__ == "__main__":
    main()
