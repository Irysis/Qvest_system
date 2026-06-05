#!/usr/bin/env python3
"""204_patchtst_v5h_q15_10seed_extension.py — Cycle 58F driver

v5h (91 features) baseline 5-seed retain (58C complete). 10 NEW seeds 추가 학습 →
15-seed total → 5-seed peak inflation 검증 (58B v5g 사례 따라).

Inherits 167b template. GPU dedicated (no parallel job).
gpu_fraction 0.4. Skip 5 existing seeds [42, 123, 456, 789, 1024].
"""
import subprocess
import sys
import os
import shutil
from pathlib import Path

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
TEMPLATE = WS / "scripts/167b_patchtst_strict_PIT_q15_template.py"
VENV_PY = PROJECT_ROOT / ".venv_dpl/bin/python3"

EXIST_DIR = WS / "outputs/03_models/cycle58c_v5h_5seed"
OUT_DIR = WS / "outputs/03_models/cycle58f_v5h_15seed"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# 1. Copy existing 5 seeds
print("Step 1: Copying existing 5 seeds from 58C...")
for seed in [42, 123, 456, 789, 1024]:
    src = EXIST_DIR / f"predictions_53I_v5h_interactions_seed{seed}_y_tail_q15.parquet"
    dst = OUT_DIR / src.name
    if src.exists() and not dst.exists():
        shutil.copy2(src, dst)
        print(f"  Copied seed{seed}")
    else:
        print(f"  Skip seed{seed} (already present or src missing)")

# 2. Train 10 NEW seeds (one at a time)
new_seeds = [2048, 3000, 5000, 7777, 9999, 10000, 20000, 30000, 40000, 50000]
print(f"\nStep 2: Training {len(new_seeds)} NEW seeds...")
for seed in new_seeds:
    out_file = (OUT_DIR /
                f"predictions_53I_v5h_interactions_seed{seed}_y_tail_q15.parquet")
    if out_file.exists():
        print(f"  seed{seed} already done, skipping")
        continue
    cmd = [
        str(VENV_PY), "-u", str(TEMPLATE),
        "--cycle", "53I_v5h_interactions",
        "--feature_panel", str(
            WS / "outputs/01_data/feature_panel_v5h_cross_market_interactions.parquet"
        ),
        "--n_features", "91",
        "--patch_size", "4",
        "--d_model", "64",
        "--nhead", "4",
        "--nlayers", "3",
        "--output_dir", str(OUT_DIR),
        "--gpu_fraction", "0.4",
        "--seeds", str(seed),  # single seed
    ]
    print(f"\n  [seed{seed}] CMD: " + " ".join(cmd[-6:]))
    ret = subprocess.run(cmd).returncode
    if ret != 0:
        print(f"  [seed{seed}] FAILED with code {ret}")
        sys.exit(ret)

print(f"\nAll 10 NEW seeds done. Total 15 seeds in {OUT_DIR}")
