#!/usr/bin/env bash
# run_full.sh — NLFF 전체 실행(2000-01 ~ END · 워커 4) — ★준비만 · 이 스크립트는 아직 실행하지 않았다(도훈 11-16 '권장안대로 진행').
#
# 순서 = FLAML → TPOT → auto-sklearn. 엔진 하나가 끝나면 다음 엔진. 한 엔진의 한 표적이 실패하면 그 엔진의 남은 표적만 멈추고
# 다음 엔진으로 간다(다른 엔진은 계속).
# 실행 단위 = 엔진 × 표적(nlff_run.py --engine E --targets T). 표적 목록 = nlff_config.json::engines.<E>.targets
#   (FLAML = earn · val · dist · ret · TPOT · auto-sklearn = earn · dist · ret).
# 재개: 단위마다 산출(.cache/nl_fundamental_factors/<E>/NLFF_<T>.parquet)과 메타(NLFF_meta_<t>.json)가 둘 다 있으면 건너뛴다.
#   단위 안에서는 재개하지 않는다(끊기면 그 엔진 × 표적을 처음부터).  다시 돌리려면 그 두 파일을 지운다.
# 로그 = 이 폴더 logs/full_<E>_<t>.log(표준 출력 · 오류) + 실행 기록 run_<E>_<t>_<START>_<END>_log.json.
# 선형 대조(linear/NLFF_<T>_LIN.parquet)는 FLAML 단위에서만 만든다(엔진 무관 · 외부 엔진은 --no-linear).
#
# 사용:  bash run_full.sh [END=2026-10] [WORKERS=4]
# 전제: 같은 PC 의 팩터 DB 전체 재빌드 · 무거운 레인이 끝난 뒤(CPU 4코어 · 메모리 — README §11). WSL Ubuntu(auto-sklearn).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
START=2000-01
END="${1:-2026-10}"
WORKERS="${2:-4}"
ROOT="$(cd ../../.. && pwd)"
OUT="$ROOT/.cache/nl_fundamental_factors"
PY_FLAML="$ROOT/.venv_qvest_ml/Scripts/python.exe"        # FLAML 판 = 공용 venv(코어 · 종전 판)
PY_DRV="$ROOT/.venv_nlff_automl/Scripts/python.exe"       # 외부 엔진 드라이버(작업기는 .venv_nlff_tpot · WSL 을 하위 프로세스로)
mkdir -p "$HERE/logs"

targets_of() {   # 설정의 엔진별 표적 목록
  "$PY_DRV" -c "import json;print(' '.join(json.load(open('nlff_config.json',encoding='utf-8'))['engines']['$1']['targets']))"
}

run_engine() {   # $1 = 엔진 · $2 = 드라이버 파이썬 · $3 = 추가 인자
  local E="$1" PY="$2" EXTRA="$3" T U
  for T in $(targets_of "$E"); do
    U=$(echo "$T" | tr '[:lower:]' '[:upper:]')
    if [ -f "$OUT/$E/NLFF_$U.parquet" ] && [ -f "$OUT/$E/NLFF_meta_$T.json" ]; then
      echo "[run_full] $E $T 건너뜀(산출 · 메타 있음)"; continue
    fi
    echo "[run_full] $(date '+%F %T') $E $T 시작"
    "$PY" -W ignore nlff_run.py --engine "$E" --targets "$T" --start "$START" --end "$END" --workers "$WORKERS" $EXTRA \
      > "$HERE/logs/full_${E}_${T}.log" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
      echo "[run_full] $(date '+%F %T') ★$E $T 실패 rc=$rc — $E 의 남은 표적은 멈추고 다음 엔진으로(로그 logs/full_${E}_${T}.log)"
      return $rc
    fi
    echo "[run_full] $(date '+%F %T') $E $T 끝"
  done
  return 0
}

run_engine flaml       "$PY_FLAML" ""            ; RC_FLAML=$?
run_engine tpot        "$PY_DRV"   "--no-linear" ; RC_TPOT=$?
run_engine autosklearn "$PY_DRV"   "--no-linear" ; RC_AS=$?
echo "[run_full] $(date '+%F %T') 끝 · rc flaml=$RC_FLAML tpot=$RC_TPOT autosklearn=$RC_AS"
[ $RC_FLAML -eq 0 ] && [ $RC_TPOT -eq 0 ] && [ $RC_AS -eq 0 ]
