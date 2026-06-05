#!/usr/bin/env python3
"""159_53h_v5e_strict.py — Cycle 55A: 53H v5e strict-PIT fresh retrain.

Feature panel: feature_panel_v5e_q126_usmacro.parquet (74 feat — foreign breadth + US macro)
PatchTST: 53H baseline mirror (patch_size=4, d_model=64, nhead=4, nlayers=3)
PIT FIX: Bug #1 purged CV + Bug #2 y_valid_mask via 157 master template.

⭐ HEADLINE CANDIDATE — 53H strict-PIT fair baseline 측정.
Pre-fix leaky 53H seed=42 = 0.4012; expected post-fix mean5 ≥ 0.50.

5-seed [42, 123, 456, 789, 1024] | strict determinism | walk-forward 5-fold
Outputs: outputs/03_models/cycle55a_strict_PIT/predictions_53H_v5e_seed{S}_y_tail_q126.parquet
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
        "--cycle", "53H_v5e",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v5e_q126_usmacro.parquet"),
        "--n_features", "74",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle55a_strict_PIT"),
        "--gpu_fraction", "0.15",
    ]
    print("[159_53h] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
