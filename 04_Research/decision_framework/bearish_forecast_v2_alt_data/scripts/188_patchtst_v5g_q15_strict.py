#!/usr/bin/env python3
"""188_patchtst_v5g_q15_strict.py — Cycle 58B Phase 3 driver

Strict-PIT PatchTST q15 5-seed retrain on v5g_cross_market panel (86 features).
v5g = v5f_FIXED2 (79) + 7 cross-market lag1 features.

Inherits 167b_patchtst_strict_PIT_q15_template.py:
  - Purged k-fold CV (busday_offset H=21)
  - y_valid_mask (ret_q15.notna())
  - 5-seed [42, 123, 456, 789, 1024]
  - Strict determinism (CUBLAS_WORKSPACE_CONFIG=:4096:8)
  - PatchTST 53I hparams (patch=4, d=64, nhead=4, nlayer=3, stride=2)
  - PostHoc target file = targets_long_horizon_observable.parquet (M6 phantom-0 clean)

Output: outputs/03_models/cycle58b_v5g_q15/predictions_53I_v5g_cross_market_seed{S}_y_tail_q15.parquet
"""
import subprocess, sys
from pathlib import Path

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
TEMPLATE = WS / "scripts/167b_patchtst_strict_PIT_q15_template.py"
VENV_PY = PROJECT_ROOT / ".venv_dpl/bin/python3"

if __name__ == "__main__":
    cmd = [
        str(VENV_PY), "-u", str(TEMPLATE),
        "--cycle", "53I_v5g_cross_market",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v5g_cross_market.parquet"),
        "--n_features", "86",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle58b_v5g_q15"),
        "--gpu_fraction", "0.15",
    ]
    print("[188_53I_v5g_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
