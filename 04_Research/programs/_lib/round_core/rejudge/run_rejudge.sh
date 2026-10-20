#!/usr/bin/env bash
# 끝난 라운드 재판정 실행기(결과 동일 실증 · 무거운 작업) — 공용 무거운 작업 자리(qm_heavy_slot.lock)를 잡고, 여유 RAM 으로 샤드 수를 정해
#   코어 재판정(짝 평가 샤딩 → 병합) → 저장본 대조를 라운드마다 돌린다. 끝나면(실패해도) 자리를 반드시 놓는다.
# 사용: bash run_rejudge.sh <출력 디렉터리> <라운드...>   (환경: RC_CORE_ROOT = 코어 저장소 · RC_REPRO_<라운드> = 재현 루트 · RC_RES_<라운드> = 저장 칸 산출 ·
#   속도 조치 기본값 = 코어 사양 라운드와 같음: RC_MINIMAL=1 · RC_MEMO=1 · RC_MC8=1 — 결과 동일 실증이 채택 상태 그대로를 재게)
#   자리 잡기 = mkdir(원자적) · 실패하면 10분 간격 최대 3시간 대기 · 자리 안에 owner 파일(WP1-b · 시각 · 목적)
set -u
OUT="${1:?출력 디렉터리}"; shift
LOCK=/c/Users/99922/AppData/Local/Temp/qm_heavy_slot.lock
CORE="${RC_CORE_ROOT:?RC_CORE_ROOT}"
RJ="$CORE/04_Research/programs/_lib/round_core/rejudge"
EMPTY_ENV="${RC_EMPTY_RENVIRON:-}"
mkdir -p "$OUT"
log() { echo "== $(date +%F' '%T) $*" | tee -a "$OUT/run.log"; }
got=0
if [ "${RC_SLOT_HELD:-0}" = "1" ]; then
  grep -q "WP1-b" "$LOCK/owner" 2>/dev/null || { log "RC_SLOT_HELD=1 인데 자리 주인이 WP1-b 가 아니다 — 실행하지 않는다"; exit 9; }
  got=1; log "호출자가 이미 자리를 잡았다(RC_SLOT_HELD) — 놓기는 호출자 몫"
else
  for i in $(seq 0 18); do
    if mkdir "$LOCK" 2>/dev/null; then
      echo "owner=WP1-b (round_core p2/p3 rejudge · worktree agent-ae9afd1f89396eda6) at=$(date +%F' '%T) purpose=rejudge $*" > "$LOCK/owner"; got=1; break
    fi
    log "무거운 작업 자리 대기($(cat "$LOCK/owner" 2>/dev/null | head -1)) — 10분 뒤 다시"
    sleep 600
  done
  [ "$got" = "1" ] || { log "3시간 동안 자리를 못 잡았다 — 실행하지 않는다"; exit 9; }
  release() { rm -rf "$LOCK"; log "무거운 작업 자리 놓음"; }
  trap release EXIT
fi
FREE=$(powershell.exe -NoProfile -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r')
[ -z "$FREE" ] && FREE=0
log "자리 잡음 · 여유 RAM ${FREE}GB"
if [ "$FREE" -lt 6 ]; then log "여유 RAM < 6GB — 실행하지 않는다"; exit 8; fi
K=$(( (FREE - 3) / 4 )); [ "$K" -lt 1 ] && K=1; [ -n "${RC_K:-}" ] && [ "$RC_K" -lt "$K" ] && K=$RC_K
log "샤드 K=$K"
for R in "$@"; do
  ROOTV="RC_REPRO_$R"; RESV="RC_RES_$R"; ROOT="${!ROOTV}"; RES="${!RESV}"; O="$OUT/$R"
  rm -rf "$O"; mkdir -p "$O"
  log "[$R] 짝 평가 샤딩 K=$K 시작 · 루트 $ROOT"
  t0=$(date +%s); pids=()
  for s in $(seq 1 "$K"); do
    R_ENVIRON_USER="$EMPTY_ENV" Rscript "$RJ/rejudge.R" "$R" --root "$ROOT" --res "$RES" --out "$O" --shard=$s/$K --minimal "${RC_MINIMAL:-1}" --memo "${RC_MEMO:-1}" --mc8 "${RC_MC8:-1}" --perf "$OUT/perf.jsonl" \
      > "$O/shard_${s}of${K}.log" 2>&1 &
    pids+=($!)
  done
  rc=0; for p in "${pids[@]}"; do wait "$p" || rc=1; done
  t1=$(date +%s)
  R_ENVIRON_USER="$EMPTY_ENV" Rscript "$RJ/rejudge.R" "$R" --root "$ROOT" --res "$RES" --out "$O" --merge --minimal "${RC_MINIMAL:-1}" --memo "${RC_MEMO:-1}" --mc8 "${RC_MC8:-1}" --perf "$OUT/perf.jsonl" > "$O/merge.log" 2>&1
  mrc=$?; t2=$(date +%s)
  log "[$R] 샤드 rc=$rc $((t1 - t0))초 · 병합 rc=$mrc $((t2 - t1))초 · 합 $((t2 - t0))초"
  echo "{\"round\":\"$R\",\"K\":$K,\"shards_seconds\":$((t1 - t0)),\"merge_seconds\":$((t2 - t1)),\"total_seconds\":$((t2 - t0)),\"shards_rc\":$rc,\"merge_rc\":$mrc}" >> "$OUT/timing.jsonl"
  for f in evaluation_visible.json evaluation_full.json evaluation.json; do
    if [ -f "$O/$f" ] && [ -f "$RES/$f" ]; then
      R_ENVIRON_USER="$EMPTY_ENV" Rscript "$RJ/compare.R" "$RES/$f" "$O/$f" --json "$O/compare_${f%.json}.json" >> "$OUT/compare.log" 2>&1
    fi
  done
  tail -6 "$OUT/compare.log" | tee -a "$OUT/run.log"
done
log "끝"
