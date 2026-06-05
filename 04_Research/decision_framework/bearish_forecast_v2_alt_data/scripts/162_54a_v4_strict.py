#!/usr/bin/env python3
"""162_54a_v4_strict.py — Cycle 55A: 54A v4 (d_model_32) strict-PIT fresh retrain.

Feature panel: feature_panel_v4a_combined.parquet (70 feat — 54A uses v4a)
PatchTST sweep variant: patch_size=4, stride=2, d_model=32, nhead=4, nlayers=3
PIT FIX: Bug #1 purged CV + Bug #2 y_valid_mask via 157 master template.

Purpose: architectural sweep winner candidate (d_model=32 vs 64). Strict-PIT 재평가.

5-seed [42, 123, 456, 789, 1024] | strict determinism | walk-forward 5-fold
Outputs: outputs/03_models/cycle55a_strict_PIT/predictions_54A_v4_dm32_seed{S}_y_tail_q126.parquet
"""
import subprocess, sys
from pathlib import Path

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
TEMPLATE = WS / "scripts/157_patchtst_strict_PIT_template.py"
VENV_PY = PROJECT_ROOT / ".venv_dpl/bin/python3"

if __name__ == "__main__":
    cmd = [
        str(VENV_PY), "-u", str(TEMPLATE),
        "--cycle", "54A_v4_dm32",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v4a_combined.parquet"),
        "--n_features", "70",
        "--patch_size", "4",
        "--d_model", "32",
        "--nhead", "4",
        "--nlayers", "3",
        "--stride", "2",
        "--output_dir", str(WS / "outputs/03_models/cycle55a_strict_PIT"),
        "--gpu_fraction", "0.15",
    ]
    print("[162_54a_v4] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
