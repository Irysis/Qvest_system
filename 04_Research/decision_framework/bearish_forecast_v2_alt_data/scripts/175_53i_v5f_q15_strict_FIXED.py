#!/usr/bin/env python3
"""175_53i_v5f_q15_strict_FIXED.py — Cycle 57A Phase 3 driver: 53I v5f FIXED q15.

Mandate: substitute Cycle 56A 53I_v5f q15 result with FRED publication-lag fixed retrain.

Feature panel: feature_panel_v5f_ecos_kr_FIXED.parquet (79 feat)
  - v5e_FIXED (74) + ECOS (5, no change)
  - FRED us_cfnai_lag1 / us_initial_claims_4w_avg_lag1 publication-lag corrected

PatchTST: 53H baseline mirror (patch_size=4, d_model=64, nhead=4, nlayers=3)
TARGET: y_tail_q15 (21-day forward bear tail event)
PIT FIX (inherited 55A): Bug #1 purged CV + Bug #2 y_valid_mask + M6 phantom-0 guard via 167b template.

5-seed [42, 123, 456, 789, 1024] | strict determinism | walk-forward 5-fold (NO fold skip for q15)
Outputs: outputs/03_models/cycle57a_q15_FRED_fixed/predictions_53I_v5f_FIXED_seed{S}_y_tail_q15.parquet
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
        "--cycle", "53I_v5f_FIXED",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v5f_ecos_kr_FIXED.parquet"),
        "--n_features", "79",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle57a_q15_FRED_fixed"),
        "--gpu_fraction", "0.15",
    ]
    print("[175_53i_v5f_FIXED_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
