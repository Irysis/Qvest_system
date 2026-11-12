"""20_evaluate.py — 모형별 일별 점수 파일(output/sc_*.parquet)을 구간별로 채점해 표를 낸다.

구간(결과일 기준): IS = 결과일 ≤ 2022-12-31 · OOS = 결과일 ≥ 2023-01-01 (정보 경계 τ_D = 2022-12-31 과 같음)
  --segments IS            설계 단계(사전등록 전) — OOS 는 계산도 출력도 하지 않는다
  --segments IS,OOS,ALL    사전등록 커밋 뒤
산출: output/eval_<tag>.json (+ 콘솔 요약)
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

TAU_D = pd.Timestamp("2022-12-31")


def outcome_dates():
    bm = pd.read_parquet(C.BM_PATH, columns=["Date"])
    d = pd.to_datetime(bm["Date"]).sort_values().reset_index(drop=True)
    return pd.Series(d.shift(-1).values, index=d.values)


def load_scores(name):
    d = pd.read_parquet(C.OUT / f"sc_{name}.parquet")
    d["Date"] = pd.to_datetime(d["Date"])
    return d.sort_values("Date").reset_index(drop=True)


def seg_mask(d, seg, nxt):
    yd = pd.to_datetime(d["Date"].map(nxt))
    if seg == "IS":
        return (yd <= TAU_D).values
    if seg == "OOS":
        return (yd > TAU_D).values
    if seg == "ALL":
        return np.ones(len(d), bool)
    raise ValueError(seg)


def summarize(d, clim):
    out = {"n": int(len(d)), "first": str(d["Date"].min().date()), "last": str(d["Date"].max().date())}
    for c in ("ls", "crps", "twcrps", "qs_010", "qs_050", "fz0_050"):
        v = d[c].values.astype(float)
        out[c] = float(np.nanmean(v)) if np.isfinite(v).any() else None
    out["sd_pred_mean"] = float(d["sd_pred"].mean())
    out["abs_y_mean"] = float(d["y"].abs().mean())
    out["realized_sd"] = float(d["y"].std())
    pit = d["pit"].values
    out["pit_mean"] = float(np.mean(pit))
    out["pit_chi2_20"] = S.pit_chi2(pit, 20)
    out["berkowitz"] = S.berkowitz_ar1(pit)
    out["coverage"] = {str(a): float(np.mean(pit <= a)) for a in S.COVER_LEVELS}
    var = {}
    for a in S.LEVELS_VAR:
        h = d[f"hit_{int(a*1000):03d}"].values
        v = d[f"var_{int(a*1000):03d}"].values
        var[str(a)] = {"kupiec": S.kupiec(h, a), "cc": S.christoffersen_cc(h, a), "dq": S.dq_test(h, v, a)}
    out["var_backtest"] = var
    ev = {}
    for thr in (-3.0, -5.0):
        e = (d["y"].values <= thr).astype(int)
        ev[str(int(thr))] = S.event_metrics(d[f"p_le_{int(-thr)}"].values, e, clim[str(int(thr))])
    out["events"] = ev
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", type=str, default="P3,GJR,EWMA,HS500")
    ap.add_argument("--segments", type=str, default="IS")
    ap.add_argument("--base", type=str, default="P3")
    ap.add_argument("--tag", type=str, default="design_IS")
    ap.add_argument("--dm_lag", type=int, default=10)
    args = ap.parse_args()
    models = [m.strip() for m in args.models.split(",") if m.strip()]
    segs = [s.strip() for s in args.segments.split(",")]
    nxt = outcome_dates()
    data = {m: load_scores(m) for m in models}
    # 공통 날짜(모든 모형 예측이 있는 날)
    common = set(data[models[0]]["Date"])
    for m in models[1:]:
        common &= set(data[m]["Date"])
    for m in models:
        data[m] = data[m][data[m]["Date"].isin(common)].sort_values("Date").reset_index(drop=True)
    # 확장 기후값(2001-01 이후 실현 사건 빈도 · 예측일 이전만)
    bm = pd.read_parquet(C.BM_PATH); bm["Date"] = pd.to_datetime(bm["Date"]); bm = bm.sort_values("Date")
    bm["r"] = np.log(bm["BM_Close"]).diff() * 100
    bm["y"] = bm["r"].shift(-1)
    bm = bm[bm["Date"] >= "2001-01-03"].dropna(subset=["y"])
    res = {"segments": {}, "models": models, "base": args.base, "dm_lag": args.dm_lag,
           "data_vintage": C.data_vintage(), "n_common": len(common)}
    for seg in segs:
        sres = {}
        for m in models:
            d = data[m]
            mk = seg_mask(d, seg, nxt)
            dd = d[mk].reset_index(drop=True)
            clim = {str(int(t)): S.expanding_climatology(bm["Date"].values, bm["y"].values, dd["Date"].values, t)
                    for t in (-3.0, -5.0)}
            sres[m] = summarize(dd, clim)
        # 기준 대비 DM(손실 기준: −LS · CRPS · twCRPS · QS · FZ0)
        dm = {}
        b = data[args.base][seg_mask(data[args.base], seg, nxt)].reset_index(drop=True)
        for m in models:
            if m == args.base:
                continue
            d = data[m][seg_mask(data[m], seg, nxt)].reset_index(drop=True)
            dm[m] = {}
            for c, sign in (("ls", -1), ("crps", 1), ("twcrps", 1), ("qs_010", 1), ("qs_050", 1), ("fz0_050", 1)):
                la = sign * d[c].values.astype(float); lb = sign * b[c].values.astype(float)
                if not (np.isfinite(la).any() and np.isfinite(lb).any()):
                    continue
                dm[m][c] = S.dm_test(la, lb, args.dm_lag)
        sres["_dm_vs_base"] = dm
        # 연도별 ΔLS(결과일 연도 · 일관성 확인 — 판정에 쓰지 않음)
        by = {}
        yd = pd.to_datetime(b["Date"].map(nxt)).dt.year.values
        for m in models:
            if m == args.base:
                continue
            d = data[m][seg_mask(data[m], seg, nxt)].reset_index(drop=True)
            diff = d["ls"].values.astype(float) - b["ls"].values.astype(float)
            by[m] = {str(int(yy)): {"n": int((yd == yy).sum()), "dls": float(np.nanmean(diff[yd == yy]))}
                     for yy in np.unique(yd) if np.isfinite(diff[yd == yy]).any()}
        sres["_by_year_dls"] = by
        res["segments"][seg] = sres
    C.write_json(C.OUT / f"eval_{args.tag}.json", res)
    # 콘솔 요약
    for seg in segs:
        print(f"\n=== {seg} ===")
        hdr = f"{'model':8s} {'n':>5s} {'LS':>8s} {'CRPS':>7s} {'twCRPS':>7s} {'QS1%':>7s} {'QS5%':>7s} {'FZ0':>7s} {'hit5%':>6s} {'hit1%':>6s} {'PITchi2p':>8s} {'Berk p':>7s} {'sdPred':>6s} {'sdReal':>6s}"
        print(hdr)
        for m in models:
            s = res["segments"][seg][m]
            vb = s["var_backtest"]
            print(f"{m:8s} {s['n']:5d} {s['ls'] if s['ls'] is not None else float('nan'):8.4f} {s['crps']:7.4f} {s['twcrps']:7.4f} "
                  f"{s['qs_010']:7.4f} {s['qs_050']:7.4f} {s['fz0_050']:7.4f} {vb['0.05']['kupiec']['rate']:6.3f} "
                  f"{vb['0.01']['kupiec']['rate']:6.3f} {s['pit_chi2_20']['p']:8.4f} {s['berkowitz']['p']:7.4f} "
                  f"{s['sd_pred_mean']:6.2f} {s['realized_sd']:6.2f}")
        for m, v in res["segments"][seg]["_dm_vs_base"].items():
            print(f"  DM {m} vs {args.base}: " + " · ".join(f"{c} d={x['mean_d']:+.4f} t={x['t']:+.2f}" for c, x in v.items()))


if __name__ == "__main__":
    main()
