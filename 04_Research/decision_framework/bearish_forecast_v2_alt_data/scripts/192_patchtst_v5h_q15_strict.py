#!/usr/bin/env python3
"""192_patchtst_v5h_q15_strict.py — Cycle 58C Phase 3 driver

Strict-PIT PatchTST q15 5-seed retrain on v5h panel (91 features = v5g 86 + 5 interactions).

Inherits 167b_patchtst_strict_PIT_q15_template.py — identical CLI to 188 (cycle 58B).
"""
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
TEMPLATE = WS / "scripts/167b_patchtst_strict_PIT_q15_template.py"
VENV_PY = PROJECT_ROOT / ".venv_dpl/bin/python3"

if __name__ == "__main__":
    cmd = [
        str(VENV_PY), "-u", str(TEMPLATE),
        "--cycle", "53I_v5h_interactions",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v5h_cross_market_interactions.parquet"),
        "--n_features", "91",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle58c_v5h_5seed"),
        "--gpu_fraction", "0.15",
    ]
    print("[192_53I_v5h_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
