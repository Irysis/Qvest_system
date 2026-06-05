#!/usr/bin/env python3
"""167_53h_v5e_q15_strict.py — Cycle 56A: 53H v5e q15 strict-PIT fresh retrain.

Feature panel: feature_panel_v5e_q126_usmacro.parquet (74 feat — foreign breadth + US macro)
PatchTST: 53H baseline mirror (patch_size=4, d_model=64, nhead=4, nlayers=3)
TARGET: y_tail_q15 (21-day forward bear tail event, q15 naming = 15% quantile threshold)
PIT FIX (inherited 55A): Bug #1 purged CV + Bug #2 y_valid_mask + M6 phantom-0 guard via 167b template.

Mandate (도훈 2026-05-21): 원래 +21d 약세 확률값 mandate 회복.
Cycle 48A 이후 q126 drift 자체 결정 (Q-Lead 미허가) → q15 진정 baseline 회복.

5-seed [42, 123, 456, 789, 1024] | strict determinism | walk-forward 5-fold (NO fold skip)
Outputs: outputs/03_models/cycle56a_q15_strict_PIT/predictions_53H_v5e_seed{S}_y_tail_q15.parquet
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
        "--cycle", "53H_v5e",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v5e_q126_usmacro.parquet"),
        "--n_features", "74",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle56a_q15_strict_PIT"),
        "--gpu_fraction", "0.15",
    ]
    print("[167_53h_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
