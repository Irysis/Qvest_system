#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""dpl_recompute_dsr.py — sweep_results.json의 best cell DSR을 수정된 공식으로 재계산.

running sweep가 (구) DSR 코드를 메모리에 적재했을 수 있어, 종료 후 본 스크립트로
best cell의 active series에서 DSR을 honest n_trials로 재산출 + 전 cell 요약표 갱신.
"""
import os
import json
import numpy as np
import pandas as pd
import sys

THIS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, THIS_DIR)
from dpl_gpu_sweep import deflated_sharpe_ratio  # 수정된 공식
PROJECT_ROOT = os.path.abspath(os.path.join(THIS_DIR, "..", ".."))
OUT = os.path.join(PROJECT_ROOT, "stage_artifacts", "WT_DPL_GPU_SWEEP")

sw = json.load(open(os.path.join(OUT, "sweep_results.json")))
n_trials = sw["n_trials"]
best = sw["best"]

bs = pd.read_parquet(os.path.join(OUT, "dpl_best_net_returns.parquet"))
active = (bs["ret_net"] - bs["BM_Ret"]).values
from scipy import stats as st
skew = float(st.skew(active)) if len(active) > 3 else 0.0
kurt = float(st.kurtosis(active, fisher=False)) if len(active) > 3 else 3.0
dsr = deflated_sharpe_ratio(best["net_active_sr"], len(active), n_trials, skew, kurt)
best["DSR_corrected"] = dsr
best["active_skew"] = skew
best["active_kurt"] = kurt

# 전 cell SR 분포
srs = [c["net_active_sr"] for c in sw["all_cells"] if np.isfinite(c.get("net_active_sr", np.nan))]
sw["sr_distribution"] = {
    "n_finite": len(srs), "max": float(np.max(srs)), "median": float(np.median(srs)),
    "min": float(np.min(srs)),
    "n_TO_le_11": int(sum(1 for c in sw["all_cells"] if c.get("turnover_ann", 99) <= 11)),
}
sw["best"] = best
json.dump(sw, open(os.path.join(OUT, "sweep_results.json"), "w"),
          indent=2, ensure_ascii=False, default=float)
print(f"[dsr] best cell={best['cell']} net_active_SR={best['net_active_sr']:.3f} "
      f"DSR_corrected={dsr:.3f} (n_trials={n_trials}, n_obs={len(active)}, "
      f"skew={skew:.2f}, kurt={kurt:.2f})")
print(f"[dsr] SR dist: max={sw['sr_distribution']['max']:.3f} "
      f"median={sw['sr_distribution']['median']:.3f}  "
      f"cells with TO<=11: {sw['sr_distribution']['n_TO_le_11']}/{n_trials}")
