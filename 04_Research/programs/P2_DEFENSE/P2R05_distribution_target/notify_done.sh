#!/usr/bin/env bash
# P2R05 분기점 알림 감시 — measure.sh 와 함께 분리 실행(_lib/detached_env.sh). 띄운 뒤 새로 생긴 센티널(night_state/p2r05_{measured,evaluated}.done)을 보고
#   notify.R 로 1통(푸시)만 보내고 끝난다: 평가 센티널 = 판정 · 평가 실패 / 측정 센티널이 precheck_fail · barrier_held · gpu_locked · warm_stale · warm_invalid · gpu_busy ·
#   cells_mismatch · sentinel_copy_failed = 측정 안 함 · 중단 / 14시간 안에 없으면 지연 알림. 측정 · 판정 절차와 무관(사전등록 고정 대상 아님 — P2R04 notify_done.sh 형식).
#   워밍 알림은 warm_cache.sh 가 끝에서 직접 낸다(notify.R --warm).
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
RDR=04_Research/programs/P2_DEFENSE/P2R05_distribution_target
ST=$ROOT/04_Research/programs/_lib/night_state
cd $ROOT || exit 2
t0=$(date +%s); dl=$((t0 + 14 * 3600))
fresh() { [ -f "$1" ] && [ "$(stat -c %Y "$1")" -ge "$t0" ]; }
echo "== $(date +%F' '%T) [P2R05] 알림 감시 시작(마감 $(date -d @$dl +%F' '%T)) =="
while :; do
  if fresh "$ST/p2r05_evaluated.done"; then echo "== $(date +%F' '%T) [P2R05] 평가 센티널: $(cat "$ST/p2r05_evaluated.done")"; Rscript $ROOT/$RDR/notify.R; exit $?; fi
  if fresh "$ST/p2r05_measured.done" && grep -qE "status=(precheck_fail|barrier_held|gpu_locked|warm_stale|warm_invalid|cells_mismatch|gpu_busy|sentinel_copy_failed)" "$ST/p2r05_measured.done"; then
    echo "== $(date +%F' '%T) [P2R05] 측정 센티널: $(cat "$ST/p2r05_measured.done")"; Rscript $ROOT/$RDR/notify.R; exit $?; fi
  if [ "$(date +%s)" -ge "$dl" ]; then echo "== $(date +%F' '%T) [P2R05] 마감 — 지연 알림"; Rscript $ROOT/$RDR/notify.R --timeout; exit $?; fi
  sleep 300
done
