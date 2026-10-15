#!/usr/bin/env bash
# 라운드 셀 평가 샤딩 병렬 실행(2026-10-15) — evaluate.R --cells-only --shard=i/K 를 K 개 동시에 띄우고 모두 기다린 뒤 종합 판정 1회.
#   셀 평가는 셀마다 results/<code>/eval.json 에만 쓰고 이미 있으면 건너뛰므로 샤드끼리 경합하지 않고, 종합 판정은 캐시를 읽기만 한다.
#   K 를 안 주면 여유 메모리로 정한다(프로세스당 ≈ EVAL_GB_PER_PROC GB · 기본 4 · 최소 1 · 최대 EVAL_K_MAX 기본 6).
#   ★측정(재현 하네스)과 동시에 돌리면 메모리를 나눠 쓴다 — 파이프라인이 순서를 정한다.
# 사용: bash eval_parallel.sh <evaluate.R(저장소 상대 경로)> [K] [로그 접두(저장소 상대)] [--no-final]
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
EV="${1:?evaluate.R 경로}"; K="${2:-}"; LP="${3:-$(dirname "$EV")/evaluate}"; FINAL=1
for a in "$@"; do [ "$a" = "--no-final" ] && FINAL=0; done
if [ -z "$K" ] || [ "$K" = "auto" ]; then
  GB=${EVAL_GB_PER_PROC:-4}; KMAX=${EVAL_K_MAX:-6}
  FREE_GB=$(powershell.exe -NoProfile -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r')
  [ -z "$FREE_GB" ] && FREE_GB=8
  K=$(( FREE_GB / GB )); [ "$K" -lt 1 ] && K=1; [ "$K" -gt "$KMAX" ] && K=$KMAX
fi
echo "== $(date +%F' '%T) 셀 평가 샤딩 K=$K · $EV =="
pids=()
for i in $(seq 1 "$K"); do
  Rscript "$EV" --cells-only --shard=$i/$K > "${LP}_cells_${i}of${K}.log" 2>&1 &
  pids+=($!)
done
rc=0; for p in "${pids[@]}"; do wait "$p" || rc=1; done
echo "== $(date +%F' '%T) 샤드 $K 개 끝 rc=$rc =="
if [ "$FINAL" = "1" ]; then
  Rscript "$EV" > "${LP}.log" 2>&1; frc=$?; echo "rc=$frc" >> "${LP}.log"
  echo "== $(date +%F' '%T) 종합 판정 rc=$frc =="
  exit $frc
fi
exit $rc
