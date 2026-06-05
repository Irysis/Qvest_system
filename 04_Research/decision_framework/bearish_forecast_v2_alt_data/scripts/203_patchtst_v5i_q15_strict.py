#!/usr/bin/env python3
"""203_patchtst_v5i_q15_strict.py — Cycle 58E v5i driver

Strict-PIT PatchTST q15 5-seed on v5i panel (96 features = v5g 86 + 10 interactions:
5 from 58C v5h + 5 new from 58E expanded).

Inherits 167b_patchtst_strict_PIT_q15_template.py.
GPU dedicated (no parallel job), gpu_fraction 0.4.
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
        "--cycle", "53I_v5i_expanded_interactions",
        "--feature_panel", str(
            WS / "outputs/01_data/feature_panel_v5i_expanded_interactions.parquet"
        ),
        "--n_features", "96",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle58e_v5i_5seed"),
        "--gpu_fraction", "0.4",
    ]
    print("[203_53I_v5i_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
