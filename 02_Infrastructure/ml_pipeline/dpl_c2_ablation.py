#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dpl_c2_ablation.py — Marginal feature ablation for DPL cycle 2 (optimizer-research).

Codex "what_missing" 의무: base90 vs +PIOTROSKI vs +MOHANRAM vs +NETISSUE vs +all3.
신규 quality/issuance feature가 DPL 천장(1.74)을 *올리는가*를 정량 입증.

설계: dpl_gpu_sweep.py 검증된 핵심기계(walk_forward/train_dpl/net_return_series/
sharpe_of/deflated_sharpe_ratio/build_month_cache)를 그대로 import (자체합성 없음).
panel column 만 DPL_FEAT_KEEP_ADDED 로 필터(load_panel 내장) → 5 변형.

각 panel 변형마다 reduced-but-real HP grid(gamma 1.5/4/8/16 × temp 1/2 × depth 2/3,
나머지 c2 best 근방 고정) walk-forward sweep. per-(panel,cell):
  net_active_sr / turnover_ann / sr_min_subperiod / oos_retention / DSR(n_trials=grid).
selection: OOS-robust(TO<=11 우선 pool, worst-third SR 최대) — c2_sweep 동일 rule.

산출(DPL_OUT_DIR=stage_artifacts/WT_D20260606_002/ablation):
  ablation_results.json (5 panel × all cells + per-panel best)
  ablation_<panel>_best_net_returns.parquet (R contract eval 용)
실행: PYTHONIOENCODING=utf-8 DPL_OUT_DIR=... .venv_qvest_ml python dpl_c2_ablation.py
"""
import os
import json
import itertools
import numpy as np
import pandas as pd
import torch

# 패널/벤치는 93f run 디렉토리(98f panel 보유)에서 읽되, 결과는 ablation 디렉토리로.
PANEL_DIR = os.environ["DPL_PANEL_DIR"]            # 98f panel 보유 디렉토리
ABL_DIR = os.environ["DPL_OUT_DIR"]                # 결과 출력
os.makedirs(ABL_DIR, exist_ok=True)
# sweep 모듈은 import 시 OUT_DIR/PANEL/BENCH를 PANEL_DIR 기준으로 잡도록 설정
os.environ["DPL_OUT_DIR"] = PANEL_DIR

import dpl_gpu_sweep as S   # noqa: E402

# panel 변형: KEEP_ADDED 리스트 (빈 = base90)
VARIANTS = {
    "base90":      [],
    "p_piotroski": ["PIOTROSKI__lvl"],
    "p_mohanram":  ["MOHANRAM__lvl"],
    "p_netissue":  ["NETISSUE__lvl"],
    "p_all3":      ["PIOTROSKI__lvl", "MOHANRAM__lvl", "NETISSUE__lvl"],
}

# reduced-but-real grid (TO<=11 압박 gamma 포함; c2 best 근방 고정으로 폭발 방지)
GRID = {
    "lam":      [0.0],
    "gamma":    [1.5, 4.0, 8.0, 16.0],
    "lookback": [120],
    "depth":    [2, 3],
    "width":    [32],
    "l2":       [1e-3],
    "dropout":  [0.3],          # c2 관찰상 dropout0.3이 sub_min 개선
    "temp":     [1.0, 2.0],
    "lr":       [5e-3],
    "epochs":   [40],
    "min_train": [60],
}


def load_panel_variant(keep_added):
    """98f panel 로드 후 added 8f 중 keep_added 만 남기고 base90 로 환원."""
    added = ["RESIDMOM__lvl", "RESIDMOM__slp", "PIOTROSKI__lvl", "PIOTROSKI__slp",
             "MOHANRAM__lvl", "MOHANRAM__slp", "NETISSUE__lvl", "NETISSUE__slp"]
    panel = pd.read_parquet(os.path.join(PANEL_DIR, "dpl_feature_panel.parquet"))
    bm = pd.read_parquet(os.path.join(PANEL_DIR, "benchmark_monthly.parquet"))
    panel["ym"] = panel["ym"].astype(str)
    bm["ym"] = bm["ym"].astype(str)
    feat = [c for c in panel.columns if c.endswith(("__lvl", "__slp", "__vol"))]
    keep = set(keep_added)
    feat = [c for c in feat if (c not in added) or (c in keep)]
    return panel, bm, feat


def sweep_variant(name, keep_added):
    panel, bm, feat_cols = load_panel_variant(keep_added)
    rets = panel[["ym", "Ticker", "Ret_1m"]].drop_duplicates()
    months = sorted(panel["ym"].unique())
    lock = S.LOCKBOX.to_period("M")
    months = [m for m in months if pd.Period(m, "M") <= lock]
    cache = S.build_month_cache(panel[panel["ym"].isin(months)], feat_cols)
    n_feat = len(feat_cols)
    keys = list(GRID.keys())
    combos = list(itertools.product(*[GRID[k] for k in keys]))
    n_trials = len(combos)
    print(f"\n[abl:{name}] feats={n_feat} months={len(months)} cells={n_trials}")
    results = []
    series_map = {}
    for ci, vals in enumerate(combos):
        cfg = dict(zip(keys, vals))
        torch.manual_seed(7); np.random.seed(7)
        wdf = S.walk_forward(cache, n_feat, cfg, months)
        if wdf.empty:
            continue
        s = S.net_return_series(wdf, rets, bm)
        sr = S.sharpe_of(s)
        to_ann = float(s["traded"].mean() * 12)
        s_sorted = s.sort_values("ym").reset_index(drop=True)
        thirds = np.array_split(s_sorted, 3)
        sub = [S.sharpe_of(t) for t in thirds if len(t) >= 6]
        sub_min = float(np.nanmin(sub)) if sub else np.nan
        ret = float(sub_min / sr) if (sr and sr > 1e-9) else np.nan
        rec = {"cell": ci, **cfg, "net_active_sr": sr, "turnover_ann": to_ann,
               "sr_min_subperiod": sub_min, "oos_retention": ret,
               "n_oos_months": int(s["ym"].nunique()), "to_ok": bool(to_ann <= 11.0)}
        results.append(rec)
        series_map[ci] = s.copy()
        print(f"[abl:{name}] cell {ci+1}/{n_trials} SR={sr:.3f} TO={to_ann:.2f} "
              f"sub_min={sub_min:.3f} ret={ret if ret==ret else float('nan'):.2f} "
              f"g={cfg['gamma']} temp={cfg['temp']} d={cfg['depth']}")
    if not results:
        return None
    # OOS-robust select: TO<=11 pool 우선, worst-third SR 최대
    def rk(r):
        sm = r["sr_min_subperiod"]; return sm if sm == sm else -9.0
    to_ok = [r for r in results if r["to_ok"]]
    pool = to_ok if to_ok else results
    best = max(pool, key=rk)
    best_fullsr = max(results, key=lambda r: r["net_active_sr"] if r["net_active_sr"] == r["net_active_sr"] else -9)
    # DSR on best
    bs = series_map[best["cell"]]
    active = (bs["ret_net"] - bs["BM_Ret_1m"]).values
    from scipy import stats as st
    sk = float(st.skew(active)) if len(active) > 3 else 0.0
    ku = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0
    best["DSR_active"] = S.deflated_sharpe_ratio(best["net_active_sr"], len(active), n_trials, sk, ku)
    # export best series (R contract)
    be = bs[["ym", "ret_net", "BM_Ret_1m", "traded"]].copy()
    be["date"] = pd.PeriodIndex(be["ym"], freq="M").to_timestamp("M")
    be["method"] = f"ABL_{name}"
    be.rename(columns={"BM_Ret_1m": "BM_Ret"}, inplace=True)
    out_p = os.path.join(ABL_DIR, f"ablation_{name}_best_net_returns.parquet")
    be[["method", "date", "ret_net", "BM_Ret", "traded"]].to_parquet(out_p, index=False)
    print(f"[abl:{name}] BEST(TO<=11 pool n={len(pool)}): SR={best['net_active_sr']:.3f} "
          f"TO={best['turnover_ann']:.2f} sub_min={best['sr_min_subperiod']:.3f} "
          f"ret={best['oos_retention']:.2f} DSR={best['DSR_active']:.3f} "
          f"| full-SR-best SR={best_fullsr['net_active_sr']:.3f} TO={best_fullsr['turnover_ann']:.2f}")
    return {"n_feat": n_feat, "n_trials": n_trials, "best": best,
            "best_full_sr": best_fullsr,
            "all_cells": sorted(results, key=lambda r: -rk(r)),
            "best_series_parquet": out_p}


def main():
    print(f"[ablation] device={S.DEVICE} PANEL_DIR={PANEL_DIR} OUT={ABL_DIR}")
    out = {"variants": {}, "grid": GRID,
           "note": "marginal ablation base90 vs +each new __lvl vs +all3; verified machinery reuse; "
                   "portfolio-alpha-t는 R contract 단일경로(여기선 net-active-SR/TO/DSR/subperiod만)."}
    for name, ka in VARIANTS.items():
        r = sweep_variant(name, ka)
        if r:
            out["variants"][name] = r
    with open(os.path.join(ABL_DIR, "ablation_results.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False, default=float)
    print(f"\n[ablation] -> {os.path.join(ABL_DIR, 'ablation_results.json')}")
    # 요약표
    print("\n===== ABLATION SUMMARY (per-panel best, OOS-robust TO<=11) =====")
    print(f"{'panel':<13}{'nfeat':>6}{'SR':>8}{'TO':>7}{'sub_min':>9}{'ret':>7}{'DSR':>7}")
    for name, v in out["variants"].items():
        b = v["best"]
        print(f"{name:<13}{v['n_feat']:>6}{b['net_active_sr']:>8.3f}{b['turnover_ann']:>7.2f}"
              f"{b['sr_min_subperiod']:>9.3f}{b['oos_retention']:>7.2f}{b['DSR_active']:>7.3f}")


if __name__ == "__main__":
    main()
