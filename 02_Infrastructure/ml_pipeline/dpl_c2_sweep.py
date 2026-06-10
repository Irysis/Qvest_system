#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_c2_sweep.py — Qvest DPL cycle2: refined sweep (TO<=11 + OOS-robust selection).

dpl_gpu_sweep.py 핵심기계(analytic capped-simplex projection / DPLNet / train_dpl /
walk_forward / net_return_series / DSR)를 *그대로 import* (검증된 코드 재사용, 자체합성 없음).
C2가 바꾸는 것은 두 가지뿐:

  (1) HP grid — task가 지목한 진짜 레버:
        gamma(turnover penalty): 90f 스윕 max 1.5 → TO 15+. C2는 {1.5, 4, 8, 16} 로 ↑↑ (TO<=11 압박).
        temp(softmax 집중도): 높을수록 EW화 → 회전↓. {1.0, 2.0} ↑.
        regularization: l2 {1e-3, 5e-3}, dropout {0.1, 0.3} ↑ (OOS over-fit 대응).
      lam/lookback/depth/width는 90f 최적 근방 소수로 고정(grid 폭발 방지, n_trials 정직 유지).

  (2) Selection rule — IS-best 금지, OOS-robust:
        90f 스윕은 full-window active SR로 best 선정 → sub_min 0.09(천장의 15%)인 cell 채택.
        C2는 worst-third Sharpe(sr_min_subperiod)가 가장 높은 cell을 best로(단, TO<=11 우선,
        TO<=11 없으면 전체 중 worst-third 최고). oos_retention = worst3/full 도 리포트.
        → "OOS robust point(IS best 아닌 OOS best)" task 요구 직접 반영.

산출: stage_artifacts/WT_DPL_C2/{dpl_best_net_returns.parquet, dpl_best_weights.parquet,
      sweep_results.json}. portfolio_alpha_t/total Sharpe는 R contract 단일경로(자체합성 금지).
실행: $env:DPL_OUT_DIR="...WT_DPL_C2"; .venv_qvest_ml python dpl_c2_sweep.py
      DPL_SMOKE=1 = 1 cell 빠른 점검.
"""
import os
import json
import itertools
import numpy as np
import pandas as pd
import torch

# C2 출력 디렉토리를 sweep 모듈이 읽도록 import 전에 설정
os.environ.setdefault(
    "DPL_OUT_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                 "stage_artifacts", "WT_DPL_C2"))

import dpl_gpu_sweep as S   # noqa: E402  (검증된 핵심기계 재사용)

OUT_DIR = S.OUT_DIR
ANNUALIZE = S.ANNUALIZE


def oos_robust_split(series):
    """OOS 윈도우를 early/late 2분할 → retention(late/early active SR)도 산출."""
    s = series.sort_values("ym").reset_index(drop=True)
    half = len(s) // 2
    early, late = s.iloc[:half], s.iloc[half:]
    sr_e = S.sharpe_of(early)
    sr_l = S.sharpe_of(late)
    return sr_e, sr_l


def main():
    print(f"[c2-sweep] device={S.DEVICE}  OUT_DIR={OUT_DIR}")
    panel, bm, feat_cols = S.load_panel()
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    months = sorted(panel["ym"].unique())
    lock = S.LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]
    print(f"[c2-sweep] feats={len(feat_cols)} months={len(months)} [{months[0]}..{months[-1]}]")
    print("[c2-sweep] building per-month GPU tensor cache ...")
    cache = S.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)

    # ── refined HP grid ──────────────────────────────────────────────
    grid = {
        "lam":      [0.0, 0.3],
        "gamma":    [1.5, 4.0, 8.0, 16.0],   # ↑↑ turnover penalty (TO<=11 압박)
        "lookback": [72, 120],
        "depth":    [2, 3],
        "width":    [32],                    # 64 제거(폭발 방지; 90f서 32가 best)
        "l2":       [1e-3, 5e-3],            # 강한 정규화 추가
        "dropout":  [0.1, 0.3],              # 강한 dropout 추가
        "temp":     [1.0, 2.0],              # 집중도 완화(EW화) → 회전↓
        "lr":       [5e-3],
        "epochs":   [40],
        "min_train": [60],
    }
    if os.environ.get("DPL_SMOKE") == "1":
        grid = {k: [v[0]] for k, v in grid.items()}
        grid["epochs"] = [5]
        print("[c2-sweep] SMOKE — 1 cell, 5 epochs")
    keys = list(grid.keys())
    combos = list(itertools.product(*[grid[k] for k in keys]))
    n_trials = len(combos)
    print(f"[c2-sweep] grid cells (n_trials) = {n_trials}")

    results = []
    all_series = {}
    for ci, vals in enumerate(combos):
        cfg = dict(zip(keys, vals))
        torch.manual_seed(7)
        np.random.seed(7)
        wdf = S.walk_forward(cache, n_feat, cfg, months)
        if wdf.empty:
            continue
        s = S.net_return_series(wdf, rets, bm)
        sr = S.sharpe_of(s)
        to_ann = float(s["traded"].mean() * 12)
        s_sorted = s.sort_values("ym").reset_index(drop=True)
        thirds = np.array_split(s_sorted, 3)
        sub_srs = [S.sharpe_of(t) for t in thirds if len(t) >= 6]
        sr_min_sub = float(np.nanmin(sub_srs)) if sub_srs else np.nan
        sr_e, sr_l = oos_robust_split(s)
        # retention: worst-third / full (음수 full은 0 retention)
        retention = float(sr_min_sub / sr) if (sr and sr > 1e-9) else np.nan
        rec = {"cell": ci, **cfg, "net_active_sr": sr, "turnover_ann": to_ann,
               "n_oos_months": int(s["ym"].nunique()), "sr_min_subperiod": sr_min_sub,
               "sub_period_srs": [round(x, 3) for x in sub_srs],
               "sr_early_half": sr_e, "sr_late_half": sr_l,
               "oos_retention_worst3_over_full": retention,
               "to_ok": bool(to_ann <= 11.0)}
        results.append(rec)
        all_series[ci] = s.copy()
        print(f"[c2-sweep] cell {ci+1}/{n_trials} SR={sr:.3f} TO={to_ann:.2f} "
              f"sub_min={sr_min_sub:.3f} ret={retention if retention==retention else float('nan'):.2f} "
              f"g={cfg['gamma']} temp={cfg['temp']} l2={cfg['l2']} drop={cfg['dropout']}")

    if not results:
        print("[c2-sweep] no results"); return

    # ── OOS-robust selection: TO<=11 우선, 그 안에서 worst-third SR 최대 ──
    def robust_key(r):
        sm = r["sr_min_subperiod"]
        return sm if sm == sm else -9.0
    to_ok = [r for r in results if r["to_ok"]]
    pool = to_ok if to_ok else results
    best = max(pool, key=robust_key)
    # 참고용 IS-best(full SR 최대) — 90f 방식과 대조
    best_fullsr = max(results, key=lambda r: r["net_active_sr"] if r["net_active_sr"] == r["net_active_sr"] else -9)
    print(f"\n[c2-sweep] BEST(OOS-robust, TO<=11 pool n={len(pool)}): cell={best['cell']} "
          f"worst3_SR={best['sr_min_subperiod']:.3f} full_SR={best['net_active_sr']:.3f} "
          f"TO={best['turnover_ann']:.2f} retention={best['oos_retention_worst3_over_full']:.2f}")
    print(f"[c2-sweep] (cf. full-SR-best cell={best_fullsr['cell']} "
          f"full_SR={best_fullsr['net_active_sr']:.3f} TO={best_fullsr['turnover_ann']:.2f} "
          f"worst3={best_fullsr['sr_min_subperiod']:.3f})")

    # DSR on best (honest n_trials)
    best_series = all_series[best["cell"]]
    active = (best_series["ret_net"] - best_series["BM_Ret_1m"]).values
    from scipy import stats as st
    skew = float(st.skew(active)) if len(active) > 3 else 0.0
    kurt = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0
    dsr = S.deflated_sharpe_ratio(best["net_active_sr"], len(active), n_trials, skew, kurt)
    best["DSR_active"] = dsr
    print(f"[c2-sweep] BEST DSR(active SR, n_trials={n_trials}) = {dsr:.4f}")

    # export best series + weights for R contract
    be = best_series[["ym", "ret_net", "BM_Ret_1m", "traded"]].copy()
    be["date"] = pd.PeriodIndex(be["ym"], freq="M").to_timestamp("M")
    be["method"] = "DPL_C2_best"
    be.rename(columns={"BM_Ret_1m": "BM_Ret"}, inplace=True)
    out_series = os.path.join(OUT_DIR, "dpl_best_net_returns.parquet")
    be[["method", "date", "ret_net", "BM_Ret", "traded"]].to_parquet(out_series, index=False)
    # best weights
    wb = S.walk_forward(cache, n_feat, dict(zip(keys, combos[best["cell"]])), months)
    wb.assign(date=lambda d: pd.PeriodIndex(d["ym"], freq="M").to_timestamp("M")).to_parquet(
        os.path.join(OUT_DIR, "dpl_best_weights.parquet"), index=False)

    sweep_out = {
        "n_trials": n_trials, "n_feature_cols": len(feat_cols), "device": S.DEVICE,
        "convex_layer": "analytic capped-simplex Euclidean projection (GPU-native, autograd-diff)",
        "lockbox": str(S.LOCKBOX.date()),
        "selection_rule": "OOS-robust: TO<=11 우선 pool, 그 안에서 worst-third(=sr_min_subperiod) SR 최대",
        "best": best, "best_full_sr_ref": best_fullsr,
        "all_cells": sorted(results, key=lambda r: -robust_key(r)),
        "out_best_net_returns": out_series,
        "self_synth_note": "월별 net return series만. total/portfolio-alpha-t는 R contract 단일경로.",
    }
    with open(os.path.join(OUT_DIR, "sweep_results.json"), "w", encoding="utf-8") as f:
        json.dump(sweep_out, f, indent=2, ensure_ascii=False, default=float)
    print(f"[c2-sweep] results -> {os.path.join(OUT_DIR, 'sweep_results.json')}")
    print(f"[c2-sweep] best series -> {out_series}")


if __name__ == "__main__":
    main()
