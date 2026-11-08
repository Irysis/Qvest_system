#!/usr/bin/env bash
# build_venv_py315.sh — Python 3.15.2 로 새 venv 를 별도 폴더(.venv_qvest_ml_py315)에 만든다 · 2026-11-08
#   기존 .venv_qvest_ml 은 건드리지 않는다(전환 = 이름 바꾸기 · 별도 단계). 패키지 = 기존 venv 의 이름 목록 전부 최신 + torch 2.15.0+cu132.
#   프로젝트 폴더 안이라 Claude 도구 세션에서 돌려도 실제로 써진다(가상화는 %LOCALAPPDATA% 쪽 — pip 캐시만 해당).
# 사용: build_venv_py315.sh <names_file> <log>
set -u
NAMES_FILE="$1"; LOG="$2"
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PY315="C:/Users/99922/AppData/Local/Programs/Python/Python315/python.exe"
VENV="$ROOT/.venv_qvest_ml_py315"
V="$VENV/Scripts/python.exe"
export PYTHONUTF8=1
step() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
[ -x "$PY315" ] || { step "STOP Python 3.15 없음"; exit 2; }
[ -e "$VENV" ] && { step "STOP 이미 있음: $VENV"; exit 3; }
step "venv 생성"; "$PY315" -m venv "$VENV" >> "$LOG" 2>&1 || { step "FAIL venv"; exit 1; }
step "pip · setuptools · wheel"; "$V" -m pip install --upgrade pip setuptools wheel >> "$LOG" 2>&1 || { step "FAIL pip"; exit 1; }
step "torch 2.15.0+cu132"; "$V" -m pip install torch==2.15.0 --index-url https://download.pytorch.org/whl/cu132 >> "$LOG" 2>&1 || { step "FAIL torch"; exit 1; }
# shellcheck disable=SC2046
step "패키지 $(wc -w < "$NAMES_FILE")개 최신"; "$V" -m pip install --upgrade $(cat "$NAMES_FILE") >> "$LOG" 2>&1 || { step "FAIL packages"; exit 1; }
step "pip check"; "$V" -m pip check >> "$LOG" 2>&1; step "pip check rc=$?"
"$V" -m pip list --format=freeze > "$ROOT/.cache/installers/venv315_freeze.txt" 2>>"$LOG"
step "DONE $(wc -l < "$ROOT/.cache/installers/venv315_freeze.txt") packages"
