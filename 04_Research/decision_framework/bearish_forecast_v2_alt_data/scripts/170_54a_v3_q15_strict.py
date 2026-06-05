#!/usr/bin/env python3
"""170_54a_v3_q15_strict.py — Cycle 56A: 54A v3 (patch_size_7) q15 strict-PIT fresh retrain.

Feature panel: feature_panel_v4a_combined.parquet (70 feat — 54A uses v4a)
PatchTST sweep variant: patch_size=7, stride=2, d_model=64, nhead=4, nlayers=3
TARGET: y_tail_q15 (21-day forward bear tail event)
PIT FIX (inherited 55A): Bug #1 purged CV + Bug #2 y_valid_mask + M6 phantom-0 guard via 167b template.

Purpose: architectural sweep variant (patch_size=7 vs 4) re-evaluated under strict-PIT q15.

5-seed [42, 123, 456, 789, 1024] | strict determinism | walk-forward 5-fold (NO fold skip for q15)
Outputs: outputs/03_models/cycle56a_q15_strict_PIT/predictions_54A_v3_patch7_seed{S}_y_tail_q15.parquet
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
        "--cycle", "54A_v3_patch7",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v4a_combined.parquet"),
        "--n_features", "70",
        "--patch_size", "7",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--stride", "2",
        "--output_dir", str(WS / "outputs/03_models/cycle56a_q15_strict_PIT"),
        "--gpu_fraction", "0.15",
    ]
    print("[170_54a_v3_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
