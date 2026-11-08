#!/usr/bin/env bash
# infra_currency_run.sh — 예약 작업 Qvest_InfraCurrency 본체(매일 05:40 · 기계마다 · machines.conf period local) · 2026-11-08
#   infra_currency.py(읽기만 — 판 대조 · 올릴 수 있는 패키지 수 · 열린 라운드 판 고정)를 돌려
#   .cache/machine/infra_currency_<HOST>.json 을 쓴다. 부팅(boot_lean.sh 'Infra:' 줄)이 이 파일을 읽는다.
#   해석기 = QVEST_PY(시스템 Python · 표준 라이브러리만 씀) → 없으면 venv. 로그 = .cache/scheduler_logs/infra_currency_<HOST>.log
set -u
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
export CLAUDE_PROJECT_DIR="$ROOT" QM_ROOT="$ROOT" PYTHONUTF8=1
PY="${QVEST_PY:-}"
[ -n "$PY" ] && [ -x "$PY" ] || PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
HOST="${COMPUTERNAME:-unknown}"
LOG="$ROOT/.cache/scheduler_logs/infra_currency_${HOST}.log"
mkdir -p "$ROOT/.cache/scheduler_logs"
{
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] start py=$PY"
  "$PY" "$ROOT/02_Infrastructure/ops/infra_currency.py" --root "$ROOT"
  rc=$?
  echo "[$(date '+%Y-%m-%dT%H:%M:%S')] SUMMARY rc=$rc"
} >> "$LOG" 2>&1
exit "${rc:-2}"
