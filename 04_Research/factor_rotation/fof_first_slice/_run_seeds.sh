#!/usr/bin/env bash
# Seed-ensemble generation for XATTN formalization (WT-D20260705_001)
cd "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/factor_rotation/fof_first_slice"
PY="C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
export QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
MODE="$1"
shift
for s in "$@"; do
  echo ">>> $MODE seed $s $(date +%H:%M:%S)"
  "$PY" xattn_score.py "$MODE" "$s" 2>&1 | tail -3
done
echo "SEEDS_DONE_${MODE}"
