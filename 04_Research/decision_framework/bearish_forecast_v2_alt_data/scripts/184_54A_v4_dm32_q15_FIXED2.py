#!/usr/bin/env python3
"""184_54A_v4_dm32_q15_FIXED2.py — Cycle 57B Phase 4 driver: 54A v4 d_model=32 FIXED2 q15.

Mandate (BBVA indirect ICSA fix):
  Substitute Cycle 56A 54A_v4_dm32 q15 result with BBVA-indirect-ICSA fixed retrain.

Feature panel: feature_panel_v4a_FIXED2.parquet (70 feat)

PatchTST: 54A v4 (patch_size=4, d_model=32, nhead=4, nlayers=3, stride=2)
TARGET: y_tail_q15 | PIT FIX via 167b template

5-seed [42, 123, 456, 789, 1024] | strict determinism
Outputs: outputs/03_models/cycle57b_q15_BBVA_fixed/predictions_54A_v4_dm32_FIXED2_seed{S}_y_tail_q15.parquet
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
        "--cycle", "54A_v4_dm32_FIXED2",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v4a_FIXED2.parquet"),
        "--n_features", "70",
        "--patch_size", "4",
        "--d_model", "32",
        "--nhead", "4",
        "--nlayers", "3",
        "--stride", "2",
        "--output_dir", str(WS / "outputs/03_models/cycle57b_q15_BBVA_fixed"),
        "--gpu_fraction", "0.15",
    ]
    print("[184_54A_v4_dm32_FIXED2_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
