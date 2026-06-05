#!/usr/bin/env python3
"""182_53B_v5b_q15_FIXED2.py — Cycle 57B Phase 4 driver: 53B v5b FIXED2 q15.

Mandate (BBVA indirect ICSA fix):
  Substitute Cycle 56A 53B_v5b q15 result with BBVA-indirect-ICSA-contamination fixed retrain.
  53B_v5b uses v4a_combined panel (70 feat) — was BBVA contaminated via Init_Claims indirect.

Feature panel: feature_panel_v4a_FIXED2.parquet (70 feat — BBVA rebuilt with FIXED FRED)
  - All 35 BBVA-derived features now use Init_Claims +5d Sat→Thu publication-lag fix
  - Plus 12 other monthly indicators (Copper/CPI/UMich/etc) publication-lag fixed
  - No direct US FRED features (53B is pre-cycle 53H US macro addition)

PatchTST: 53B baseline mirror (patch_size=4, d_model=64, nhead=4, nlayers=3, stride=2)
TARGET: y_tail_q15 (21-day forward bear tail event)
PIT FIX (inherited 55A): Bug #1 purged CV + Bug #2 y_valid_mask + M6 phantom-0 guard via 167b template.

5-seed [42, 123, 456, 789, 1024] | strict determinism | walk-forward 5-fold (NO fold skip for q15)
Outputs: outputs/03_models/cycle57b_q15_BBVA_fixed/predictions_53B_v5b_FIXED2_seed{S}_y_tail_q15.parquet
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
        "--cycle", "53B_v5b_FIXED2",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v4a_FIXED2.parquet"),
        "--n_features", "70",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle57b_q15_BBVA_fixed"),
        "--gpu_fraction", "0.15",
    ]
    print("[182_53B_v5b_FIXED2_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
