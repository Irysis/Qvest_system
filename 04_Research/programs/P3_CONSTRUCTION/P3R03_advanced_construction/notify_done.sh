#!/usr/bin/env bash
# P3R03 분기점 알림 감시 — measure.sh 와 함께 분리 실행(detached_env.sh). 띄운 뒤 새로 생긴 센티널(night_state/p3r03_{measured,evaluated}.done)을 보고
#   notify.R 로 1통(푸시)만 보내고 끝난다: 평가 센티널 = 판정 · 평가 실패 / 측정 센티널이 precheck_fail · barrier_held = 측정 안 함 / 14시간 안에 없으면 지연 알림.
#   측정 · 판정 절차와 무관(사전등록 고정 대상 아님 — measure.sh 를 바꾸지 않으려고 따로 둔다).
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
RDR=04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction
ST=$ROOT/04_Research/programs/_lib/night_state
cd $ROOT || exit 2
t0=$(date +%s); dl=$((t0 + 14 * 3600))
fresh() { [ -f "$1" ] && [ "$(stat -c %Y "$1")" -ge "$t0" ]; }
echo "== $(date +%F' '%T) 알림 감시 시작(마감 $(date -d @$dl +%F' '%T)) =="
while :; do
  if fresh "$ST/p3r03_evaluated.done"; then echo "== $(date +%F' '%T) 평가 센티널: $(cat "$ST/p3r03_evaluated.done")"; Rscript $ROOT/$RDR/notify.R; exit $?; fi
  if fresh "$ST/p3r03_measured.done" && grep -qE "status=(precheck_fail|barrier_held)" "$ST/p3r03_measured.done"; then
    echo "== $(date +%F' '%T) 측정 센티널: $(cat "$ST/p3r03_measured.done")"; Rscript $ROOT/$RDR/notify.R; exit $?; fi
  if [ "$(date +%s)" -ge "$dl" ]; then echo "== $(date +%F' '%T) 마감 — 지연 알림"; Rscript $ROOT/$RDR/notify.R --timeout; exit $?; fi
  sleep 300
done
