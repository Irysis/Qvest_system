#!/usr/bin/env python3
"""182b_53H_v5e_q15_FIXED2.py — Cycle 57B Phase 4 driver: 53H v5e FIXED2 q15.

Mandate (BBVA indirect ICSA fix on top of 57A direct US FRED fix):
  Substitute Cycle 57A 53H_v5e_FIXED q15 result with BBVA-indirect ALSO fixed retrain.
  v5e = v4a (BBVA inherit) + 4 US macro (direct FRED).
  57A only fixed direct US FRED (us_cfnai/us_initial_claims).
  57B now ALSO fixes BBVA-inherited Init_Claims (35 BBVA features rebuilt).

Feature panel: feature_panel_v5e_FIXED2.parquet (74 feat — BBVA fixed via FIXED FRED + 4 US macro direct fixed)

PatchTST: 53H baseline (patch_size=4, d_model=64, nhead=4, nlayers=3, stride=2)
TARGET: y_tail_q15 | PIT FIX via 167b template

5-seed [42, 123, 456, 789, 1024] | strict determinism
Outputs: outputs/03_models/cycle57b_q15_BBVA_fixed/predictions_53H_v5e_FIXED2_seed{S}_y_tail_q15.parquet
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
        "--cycle", "53H_v5e_FIXED2",
        "--feature_panel", str(WS / "outputs/01_data/feature_panel_v5e_FIXED2.parquet"),
        "--n_features", "74",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(WS / "outputs/03_models/cycle57b_q15_BBVA_fixed"),
        "--gpu_fraction", "0.15",
    ]
    print("[182b_53H_v5e_FIXED2_q15] CMD: " + " ".join(cmd))
    sys.exit(subprocess.run(cmd).returncode)
