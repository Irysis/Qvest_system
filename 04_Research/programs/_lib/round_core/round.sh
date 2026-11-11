#!/usr/bin/env bash
# round_core 실행기 — 라운드별 measure.sh · measure_now*.sh · notify_done.sh · fingerprint.sh · eval_parallel 호출을 대체한다(1계층 속도 계획 WP1).
# 사용: bash 04_Research/programs/_lib/round_core/round.sh <round_dir(저장소 상대)> <단계> [인자]
#   check | precheck | plan | draft | reviewed <v> <점검 파일> <ok|revise> | register | report [--send] [--next ..] | close --note ..  → R 실행기
#   measure [--now] [--p=N]  배리어 → 핀 사전 점검 → 엔진별 기준 칸(reference) 먼저 단독 → 나머지 병렬 → 칸마다 시작 · 끝 데이터 지문 →
#                            인프라 실패 1회 재측정 → 엔진 묶음 지문 불일치면 배리어 뒤 묶음 1회 재측정 → evaluate 자동 연쇄
#                            ('--now' = 갱신 완료 줄 대기 생략 · 배리어 · 사전 점검 · 지문은 그대로)
#   fresh-check              데이터 신선도(v1/freshness.R · 가격 · 벤치가 직전 거래일 세션까지 · 0 신선 · 6 낡음/판독 불가) — measure · standing-measure · p4 측정이 같은 판정
#   evaluate [K]             칸 평가 샤딩(K = 여유 RAM ÷ 4GB · 최대 6) → 종합 판정 1회 · 센티널 .cache/round_core/state/<라운드>.evaluated
#   상설 판(standing: true · WP5 — v1/standing.R):
#     scan [--dry-run] [--max N] [--out f]   레인 산출 → 자격 큐(입구 규칙 · 사유 코드) — 등록 뒤 시드 + 새 엔진을 원장에 넣는다
#     standing-measure         배리어 → 대기 항목마다 R2 대조 · 지문 · 정본 셀 워커 → 판정(원장 · 보는 창 표)
#     standing-check · pending · measure-item <code> · judge · standing-report [--send] · standing-status · superfan-mark
#   P4 강화 사슬(v1/p4.R · <round_dir> = 사슬 디렉터리 · 아래 기본 분기가 driver.R 로 넘긴다):
#     p4-pool · p4-base-spec · p4-check · p4-register --p1 --t1 · p4-design · p4-step-open · p4-step-decide · p4-status · p4-close --p2 --t2 · p4-generator-review
#     p4-base-measure · p4-step-measure --k <n>  배리어 대기(기준 칸 = 걸음 전 필수)(상설 측정과 같다 · 2시간 뒤에도 잡히면 종료 4) → R 쪽이 배리어 재확인 · 칸 사양 md5 대조 · 정본 셀 워커 → 원장 step_measured
#   RC_ROOT_POSIX · RC_ROOT_WIN = 다른 작업 트리(worktree)에서 돌릴 때만(기본 = 저장소 · R 쪽은 R_ENVIRON_USER 로 QM_ROOT 를 맞춘다)
set -u
ROOT=${RC_ROOT_POSIX:-/c/Users/99922/OneDrive/Quant_Module_Moltbot}
export QM_ROOT=${RC_ROOT_WIN:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}
cd "$ROOT" || exit 2
RD="${1:?round_dir}"; ST="${2:?stage}"; shift 2
## 코어 판 라우팅(11-11 · 코어 v2 출시 — 판단 T1 C-20261111-002 대안 (a) · 판은 불변): 라운드 · 상설 판 · 사슬 사양의 core_version 으로 코어 판을 고른다.
##   사양(round_spec.json · chain_spec.json)에 core_version 이 없으면 v1(그 표식 전의 판) · 사양 없는 호출('-' · 사양을 만들기 전) = RC_CORE_DEFAULT,
##   없으면 RELEASES.json 의 마지막 출시 판(출시 때만 항목을 더한다). 고른 판 디렉터리에 driver.R 이 없으면 종료 2.
rc_core_of() {
  local f v=""
  if [ "$RD" != "-" ]; then
    for f in "$ROOT/$RD/round_spec.json" "$ROOT/$RD/chain_spec.json"; do
      [ -f "$f" ] || continue
      v=$(grep -oE '"core_version"[[:space:]]*:[[:space:]]*"v[0-9]+"' "$f" | head -n 1 | sed -E 's/.*"(v[0-9]+)"$/\1/'); v=${v:-v1}; break
    done
  fi
  if [ -z "$v" ]; then
    v=${RC_CORE_DEFAULT:-$(grep -oE '"version"[[:space:]]*:[[:space:]]*"v[0-9]+"' "$ROOT/04_Research/programs/_lib/round_core/RELEASES.json" 2>/dev/null | tail -n 1 | sed -E 's/.*"(v[0-9]+)"$/\1/')}
    v=${v:-v1}
  fi
  printf '%s\n' "$v"
}
CV=$(rc_core_of)
CORE=$ROOT/04_Research/programs/_lib/round_core/$CV
[ -f "$CORE/driver.R" ] || { echo "[round.sh] 코어 판 $CV 없음($CORE) — 사양 core_version · RC_CORE_DEFAULT 확인" >&2; exit 2; }
DRV="$CORE/driver.R"
STATE=$ROOT/.cache/round_core/state; mkdir -p "$STATE"
[ "$RD" != "-" ] && mkdir -p "$ROOT/$RD/results"            # '-'(사양 없는 호출)는 결과 폴더를 만들지 않는다(11-11 — 저장소 맨 위 '-/results' 잔재)
TAG=$(basename "$RD")
sentinel() { echo "status=$2 rc=$3 at=$(date +%F' '%T) ${4:-}" > "$STATE/$TAG.$1"; }
barrier() { bash $ROOT/02_Infrastructure/ops/refresh_barrier.sh wait 7200 60 | sed "s/^/[배리어] /"; return "${PIPESTATUS[0]}"; }

evaluate() {
  local K="${1:-auto}"
  if [ "$K" = "auto" ]; then
    local GB=${EVAL_GB_PER_PROC:-4} KMAX=${EVAL_K_MAX:-6} FREE
    FREE=$(powershell.exe -NoProfile -Command "[math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)" 2>/dev/null | tr -d '\r')
    [ -z "$FREE" ] && FREE=8
    K=$(( FREE / GB )); [ "$K" -lt 1 ] && K=1; [ "$K" -gt "$KMAX" ] && K=$KMAX
  fi
  echo "== $(date +%F' '%T) [$TAG] 칸 평가 샤딩 K=$K =="
  local pids=() i rc=0
  for i in $(seq 1 "$K"); do
    Rscript "$DRV" "$RD" evaluate --cells-only --shard=$i/$K > "$ROOT/$RD/results/evaluate_cells_${i}of${K}.log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || rc=1; done
  # 짝 판정 템플릿(P2 · P3) — 최종 판정의 짝 평가(공통 창 · β 짝 패킷 · 기록)를 같은 K 로 샤딩 → 병합 종합(P1 은 --pairs-only 가 즉시 끝난다)
  pids=(); rm -rf "$ROOT/$RD/results/.pairs"                                  # 옛 짝 결과가 병합에 섞이지 않게(워커가 죽으면 병합이 '샤드 결과 없음'으로 멈춘다)
  for i in $(seq 1 "$K"); do
    Rscript "$DRV" "$RD" evaluate --pairs-only --shard=$i/$K > "$ROOT/$RD/results/evaluate_pairs_${i}of${K}.log" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || rc=1; done
  Rscript "$DRV" "$RD" evaluate --merge > "$ROOT/$RD/results/evaluate.log" 2>&1; local frc=$?
  tail -3 "$ROOT/$RD/results/evaluate.log"
  sentinel evaluated "$([ "$frc" = "0" ] && echo evaluated || echo eval_failed)" "$frc" "shards_rc=$rc"
  return $frc
}

case "$ST" in
  measure)
    NOW=0; PAR=${RC_PAR:-2}
    for a in "$@"; do case "$a" in --now) NOW=1 ;; --p=[1-9]*) PAR="${a#--p=}" ;; esac; done
    if [ "$NOW" = "0" ]; then
      LOG=$ROOT/.cache/scheduler_logs/daily_refresh.log
      n0=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n0=${n0:-0}
      echo "== $(date +%F' '%T) [$TAG] 데이터 갱신 완료 대기(완료 줄 $n0 · 마감 06:00) =="
      while :; do
        n=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n=${n:-0}
        [ "$n" -gt "$n0" ] && break
        hh=$(date +%H); [ "$hh" -ge 6 ] && [ "$hh" -lt 12 ] && break
        sleep 120
      done
    fi
    barrier; [ "$?" = "10" ] && { echo "== [$TAG] 배리어 2시간 뒤에도 잡힘 — 측정하지 않는다 =="; sentinel measured barrier_held 10; exit 4; }
    Rscript "$DRV" "$RD" fresh-check || { echo "== [$TAG] 데이터 신선도 미달 — 측정하지 않는다(v1/freshness.R) =="; sentinel measured data_stale 6; exit 6; }
    Rscript "$DRV" "$RD" precheck || { sentinel measured precheck_fail 3; exit 3; }
    PLAN=$(Rscript "$DRV" "$RD" plan) || exit 3
    export ROOT RD CORE
    m() {
      local code="$1" res="$ROOT/$RD/results/$1"
      if [ -f "$res.json" ] && grep -q '"ok": *true' "$res.json"; then echo "[$code] 이미 있음(지문 보존)"; return 0; fi
      rm -rf "$res" "$res.json" "$res.fp_start" "$res.fp_end"
      bash "$CORE/fingerprint.sh" equality > "$res.fp_start"
      Rscript "$CORE/measure_cell.R" "$RD" "$code" 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$code] /"
      bash "$CORE/fingerprint.sh" equality > "$res.fp_end"
    }
    okc() { [ -f "$ROOT/$RD/results/$1.json" ] && grep -q '"ok": *true' "$ROOT/$RD/results/$1.json"; }
    mm() { m "$1"; okc "$1" || { echo "[$1] 인프라 실패(ok ≠ true) — 같은 사양 1회 재측정"; m "$1"; }; }
    export -f m okc mm
    same_fp() { local u; u=$(for c in "$@"; do for t in fp_start fp_end; do f="$ROOT/$RD/results/$c.$t"; [ -f "$f" ] && tr '\n' '|' < "$f" || echo MISSING; echo; done; done | sort -u | wc -l); [ "$u" = "1" ]; }
    group() {   # $1 = 엔진
      local refs others
      refs=$(echo "$PLAN" | awk -v e="$1" '$1==e && $3=="reference" {print $2}')
      others=$(echo "$PLAN" | awk -v e="$1" '$1==e && $3!="reference" {print $2}')
      echo "== $(date +%F' '%T) [$TAG] 엔진 $1 — 기준 칸 먼저 단독 → 나머지 병렬 $PAR =="
      for r in $refs; do bash -c "mm $r"; done
      [ -n "$others" ] && echo "$others" | xargs -P "$PAR" -I{} bash -c 'mm {}'
    }
    for eng in $(echo "$PLAN" | awk '{print $1}' | awk '!s[$0]++'); do
      cells=$(echo "$PLAN" | awk -v e="$eng" '$1==e {print $2}')
      group "$eng"
      if ! same_fp $cells; then
        echo "== $(date +%F' '%T) [$TAG] $eng 묶음 지문 불일치 — 배리어 뒤 묶음 1회 재측정 =="
        if barrier; then for c in $cells; do rm -f "$ROOT/$RD/results/$c.json"; done; group "$eng"
          same_fp $cells || echo "== [$TAG] $eng 묶음 지문 여전히 불일치 — 판정 전에 사람이 본다 =="
        fi
      fi
    done
    nok=0; nt=0; for c in $(echo "$PLAN" | awk '{print $2}'); do nt=$((nt+1)); okc "$c" && nok=$((nok+1)); done
    echo "== $(date +%F' '%T) [$TAG] 측정 끝 — ok $nok/$nt =="
    sentinel measured measured 0 "ok=$nok/$nt"
    barrier; [ "$?" = "10" ] && { sentinel evaluated eval_barrier_held 10; exit 5; }
    evaluate auto ;;
  evaluate) evaluate "${1:-auto}" ;;
  scan|standing-check|pending|measure-item|judge|standing-report|standing-status|superfan-mark)
    exec Rscript "$CORE/standing.R" "$RD" "$ST" "$@" ;;
  standing-measure)
    barrier; [ "$?" = "10" ] && { sentinel standing barrier_held 10; echo "== [$TAG] 배리어 2시간 뒤에도 잡힘 — 측정하지 않는다 =="; exit 4; }
    PEND=$(Rscript "$CORE/standing.R" "$RD" pending) || exit 3
    FRESH=ok; [ -n "$PEND" ] && { Rscript "$DRV" - fresh-check || { FRESH=stale; echo "== [$TAG] 데이터 신선도 미달 — 대기 항목 측정 건너뜀(판정은 진행 · 다음 틱 재개) =="; PEND=""; }; }
    for code in $PEND; do Rscript "$CORE/standing.R" "$RD" measure-item "$code" 2>&1 | grep -E "^\[상설\]|Error|에러" | sed "s/^/[$code] /"; done
    Rscript "$CORE/standing.R" "$RD" judge; jrc=$?
    sentinel standing "$([ "$jrc" = "0" ] && { [ "$FRESH" = "ok" ] && echo judged || echo judged_data_stale; } || echo judge_failed)" "$jrc" "pending=$(echo $PEND | wc -w)"
    exit $jrc ;;
  p4-base-measure|p4-step-measure)
    barrier; [ "$?" = "10" ] && { sentinel p4measure barrier_held 10; echo "== [$TAG] 배리어 2시간 뒤에도 잡힘 — 측정하지 않는다 =="; exit 4; }
    Rscript "$DRV" "$RD" "$ST" "$@"; mrc=$?
    sentinel p4measure "$(case $mrc in 0) echo measured ;; 4) echo barrier_held ;; 6) echo data_stale ;; 7) echo busy ;; *) echo measure_failed ;; esac)" "$mrc"
    exit $mrc ;;
  *) exec Rscript "$DRV" "$RD" "$ST" "$@" ;;
esac
