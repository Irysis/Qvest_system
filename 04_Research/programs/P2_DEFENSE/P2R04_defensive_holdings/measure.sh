#!/usr/bin/env bash
# P2R04 측정 → 셀 평가 → 판정(분리 실행 · 2026-10-18 · P2R03 measure.sh 를 이어받음) — 데이터 갱신이 끝난 뒤에만(같은 배치).
#   ① 대기: 띄운 뒤 새 'Daily Refresh v2 Done' 줄이 생길 때까지(마감 06:00 — 갱신이 안 돌면 그 시각에 현 배치로 진행) → 리프레시 배리어 해제 대기
#      (2시간 뒤에도 잡혀 있으면 측정하지 않고 종료). '--now' = 완료 줄 대기만 생략(배리어 · precheck · 칸별 지문은 그대로).
#   ② precheck(사양 23 · 운영 경로(팩터 DB 커넥터 · 등급 계약 v3.2 포함) · 팩터 레지스트리 엔트리 · 비중 카탈로그 lean:entropy · 패키지 · R 판 ·
#      평가 경로 md5 · 행동 카드 설정 사본 · 등록부 사전등록 md5) 통과 시에만. 오버레이 없음 → 오버레이 arm 핀 없음.
#   ③ 엔진 묶음(E2 → E3) — RX0 먼저 단독 → 나머지 칸 PAR 병렬(기본 2 · '--p=N' 으로 바꾼다(3 허용) — 결과 무관).
#        E2 묶음 14칸 = RX0 + 장치 H1~H4 + 진단 9(결측 짝 C1~C4 · 용량 짝 W1~W4 · 희석 짝 N0 — 철학 P1 R-20261018-003 · 판정 표 밖 · 시행 수 무가산)
#        E3 묶음  9칸 = RX0 + 장치 H1~H4(v3 방어 몫 50% · 장치 팩터 6회 나열) + 진단 4(도구 상자 용량 짝 W1~W4 · 12.5% — 판단 T1 C-027)
#      lag-1 진단 칸 없음(시점 신호 = 오버레이가 없다 · 팩터 값 시점은 load_month_factors 가 지킨다). 칸마다 측정 전에 옛 칸 평가 캐시
#      results/<code>/ · 지문을 지운다 · 시작 · 종료 데이터 지문(fingerprint.sh equality · DNN 캐시는 record). 인프라 실패(ok ≠ true) 칸은
#      같은 사양 1회 기계 재측정(사전등록 규칙 rules.remeasure). 묶음 칸 × 시작/끝 지문이 갈리면 배리어 대기 뒤 그 묶음 전체를 1회 재측정 —
#      그래도 갈리면 evaluate.R 이 판정하지 않는다(rules.vintage_group). 2계층 모듈 풀 등재는 장치 칸(H*)만 — RX0 · 진단 칸은 QVEST_RP_REGISTER=0.
#   ④ 평가 전 배리어 → 셀 평가 샤딩(evaluate.R --cells-only --shard=i/K) + 종합 판정 1회(_lib/eval_parallel.sh) ·
#      센티널 night_state/p2r04_{measured,evaluated}.done 에 상태 · 종료 코드(notify_done.sh 가 읽는다)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
TAG=P2R04
RDR=04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings
PRE=stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json
ST=$ROOT/04_Research/programs/_lib/night_state
LOG=$ROOT/.cache/scheduler_logs/daily_refresh.log
ENGINES="E2 E3"
VARS_E2="H1 H2 H3 H4 C1 C2 C3 C4 W1 W2 W3 W4 N0"                # 장치 먼저(판정 칸) → 진단
VARS_E3="H1 H2 H3 H4 W1 W2 W3 W4"
vars_of() { case "$1" in E2) echo "$VARS_E2" ;; E3) echo "$VARS_E3" ;; *) echo "" ;; esac; }
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
mkdir -p "$ST" "$ROOT/$RDR/results"
sentinel() { echo "status=$2 rc=$3 at=$(date +%F' '%T) ${4:-}" > "$ST/$1"; }
NOW=0; PAR=2
for a in "$@"; do case "$a" in --now) NOW=1 ;; --p=[1-9]) PAR="${a#--p=}" ;; esac; done
NT=0; for e in $ENGINES; do for c in RX0 $(vars_of $e); do NT=$((NT + 1)); done; done   # 측정 칸 수(14 + 9 = 23)
if [ "$NOW" = "1" ]; then
  echo "== $(date +%F' '%T) [$TAG] 즉시 측정(--now) — 갱신 완료 대기 생략 · 현 배치 · 칸 $NT · 병렬 $PAR =="
else
  n0=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n0=${n0:-0}
  echo "== $(date +%F' '%T) [$TAG] 데이터 갱신 완료 대기(현재 완료 줄 $n0 · 마감 06:00 · 칸 $NT · 병렬 $PAR) =="
  while :; do
    n=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n=${n:-0}
    [ "$n" -gt "$n0" ] && { echo "== $(date +%F' '%T) [$TAG] 갱신 완료 줄 확인($n0 → $n) =="; break; }
    hh=$(date +%H); [ "$hh" -ge 6 ] && [ "$hh" -lt 12 ] && { echo "== $(date +%F' '%T) [$TAG] 마감 06:00 — 현 배치로 진행 =="; break; }
    sleep 120
  done
fi
barrier() { bash $ROOT/02_Infrastructure/ops/refresh_barrier.sh wait 7200 60 | sed "s/^/[배리어] /"; return "${PIPESTATUS[0]}"; }
barrier; brc=$?
if [ "$brc" = "10" ]; then echo "== $(date +%F' '%T) [$TAG] 배리어 2시간 뒤에도 잡힘 — 측정하지 않는다 =="; sentinel p2r04_measured.done barrier_held 10; exit 4; fi
echo "== $(date +%F' '%T) [$TAG] precheck =="
Rscript $ROOT/$RDR/precheck.R || { echo "== $(date +%F' '%T) [$TAG] precheck 불일치 — 측정하지 않는다 =="; sentinel p2r04_measured.done precheck_fail 3; exit 3; }
FPS="bash $ROOT/$RDR/fingerprint.sh"
m() {
  local code="$1" res="$ROOT/$RDR/results/$1"
  if [ -f "$res.json" ] && grep -q '"ok": *true' "$res.json"; then echo "[$code] [측정] 이미 있음(지문 보존)"; return 0; fi
  rm -rf "$res" "$res.json" "$res.fp_start" "$res.fp_end" "$res.fpc_start" "$res.fpc_end"     # 옛 칸 평가 캐시 · 지문 · ok=false 잔재 제거
  case "$code" in *_H[0-9]) unset QVEST_RP_REGISTER ;; *) export QVEST_RP_REGISTER=0 ;; esac  # 장치 칸만 2계층 모듈 풀 등재(RX0 · 진단 = 미등재)
  $FPS equality > "$res.fp_start"; $FPS record > "$res.fpc_start"
  Rscript $ROOT/04_Research/programs/_lib/measure_round_cell.R "$RDR" "$PRE" "$code" 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$code] /"
  $FPS equality > "$res.fp_end"; $FPS record > "$res.fpc_end"
}
okc() { [ -f "$ROOT/$RDR/results/$1.json" ] && grep -q '"ok": *true' "$ROOT/$RDR/results/$1.json"; }
mm() { m "$1"; okc "$1" || { echo "[$1] 인프라 실패(ok ≠ true) — 같은 사양 1회 재측정(사전등록 규칙)"; m "$1"; }; }
export -f m okc mm; export ROOT RDR PRE FPS
group() {   # $1 = 엔진
  local vs; vs=$(vars_of "$1"); local nv=0; for v in $vs; do nv=$((nv + 1)); done
  echo "== $(date +%F' '%T) [$TAG] 엔진 묶음 $1 — RX0 먼저 단독 → 나머지 ${nv}칸 병렬 $PAR =="
  bash -c "mm ${TAG}_$1_RX0"
  for v in $vs; do echo "${TAG}_$1_$v"; done | xargs -P "$PAR" -I{} bash -c 'mm {}'
}
same_fp() {   # $1 = 엔진 — 묶음 칸(RX0 + 나머지) 시작 · 종료 지문이 모두 같으면 0(파일 없음 = 불일치)
  local f u
  u=$(for c in RX0 $(vars_of "$1"); do for t in fp_start fp_end; do f="$ROOT/$RDR/results/${TAG}_$1_$c.$t"; [ -f "$f" ] && tr '\n' '|' < "$f" || echo MISSING; echo; done; done | sort -u | wc -l)
  [ "$u" = "1" ]
}
for eng in $ENGINES; do
  group $eng
  if ! same_fp $eng; then
    echo "== $(date +%F' '%T) [$TAG] $eng 묶음 지문 불일치 — 배리어 대기 뒤 묶음 전체 1회 재측정 =="
    if barrier; then
      for c in RX0 $(vars_of $eng); do rm -f "$ROOT/$RDR/results/${TAG}_${eng}_$c.json"; done
      group $eng
      same_fp $eng || echo "== $(date +%F' '%T) [$TAG] $eng 묶음 지문 여전히 불일치 — 판정은 evaluate.R 이 거부한다(rules.vintage_group) =="
    else
      echo "== $(date +%F' '%T) [$TAG] 배리어 2시간 뒤에도 잡힘 — $eng 재측정 생략(판정은 evaluate.R 이 거부한다) =="
    fi
  fi
done
nok=0; for eng in $ENGINES; do for c in RX0 $(vars_of $eng); do okc "${TAG}_${eng}_$c" && nok=$((nok+1)); done; done
echo "== $(date +%F' '%T) [$TAG] 측정 끝 — ok $nok/$NT =="
sentinel p2r04_measured.done measured 0 "ok=$nok/$NT"
# 평가 전 배리어 — 셀 평가는 원천 RAWDATA 를 읽는다(크기 · 멤버십). 갱신이 돌고 있으면 끝날 때까지 기다리고, 2시간 넘게 잡히면 평가하지 않는다
barrier; ebrc=$?
if [ "$ebrc" = "10" ]; then echo "== $(date +%F' '%T) [$TAG] 평가 전 배리어 2시간 뒤에도 잡힘 — 평가하지 않는다 =="; sentinel p2r04_evaluated.done eval_barrier_held 10 "ok=$nok/$NT"; exit 5; fi
bash $ROOT/04_Research/programs/_lib/eval_parallel.sh $RDR/evaluate.R auto $RDR/evaluate; erc=$?
echo "== $(date +%F' '%T) [$TAG] 평가 · 판정 끝(rc=$erc) =="
sentinel p2r04_evaluated.done "$([ "$erc" = "0" ] && echo evaluated || echo eval_failed)" "$erc" "ok=$nok/$NT"
