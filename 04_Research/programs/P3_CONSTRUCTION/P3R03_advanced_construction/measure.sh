#!/usr/bin/env bash
# P3R03 측정 → 셀 평가 → 판정(분리 실행 · 2026-10-16 · v2 = 격리 교차 점검 반영) — 오늘 밤 데이터 갱신이 끝난 뒤에만(같은 배치 · 갱신 중 RAWDATA 는 창 안에서 NA 를 만든다).
#   ① 대기: 띄운 뒤 새 'Daily Refresh v2 Done' 줄이 생길 때까지(마감 06:00 — 갱신이 안 돌면 그 시각에 현 배치로 진행) → 리프레시 배리어 해제 대기
#      (2시간 뒤에도 잡혀 있으면 측정하지 않고 종료 — 권고 2)
#   ② precheck(사양 · 운영 · 평가 md5 · 카탈로그 6종 · 패키지 · R 판) 통과 시에만
#   ③ 엔진 묶음(E2 → E3) — RX0 먼저 단독(권고 3) → 방법 5칸 3병렬. 칸마다 측정 전에 옛 칸 평가 캐시 results/<code>/ · 지문을 지운다(필수 2) ·
#      시작 · 종료 데이터 지문(fingerprint.sh equality · DNN 캐시는 record). 인프라 실패(ok ≠ true) 칸은 같은 사양 1회 기계 재측정(사전등록 규칙).
#      묶음 안 지문이 갈리면 배리어 대기 뒤 그 묶음 전체를 1회 재측정 — 그래도 갈리면 evaluate.R 이 판정하지 않는다(rules.vintage_group).
#      RX0 는 카탈로그 미등재(QVEST_RP_REGISTER=0)
#   ④ 셀 평가 샤딩 + 종합 판정(_lib/eval_parallel.sh) · 센티널 night_state/p3r03_{measured,evaluated}.done 에 상태 · 종료 코드(권고 11)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
RDR=04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction
PRE=stage_artifacts/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json
ST=$ROOT/04_Research/programs/_lib/night_state
LOG=$ROOT/.cache/scheduler_logs/daily_refresh.log
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
mkdir -p "$ST" "$ROOT/$RDR/results"
sentinel() { echo "status=$2 rc=$3 at=$(date +%F' '%T) ${4:-}" > "$ST/$1"; }
n0=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n0=${n0:-0}   # 일치 0건이면 grep -c 가 0 을 찍고 rc=1 — '|| echo 0' 은 0 두 줄을 만든다(v2 점검 권고 5)
echo "== $(date +%F' '%T) 데이터 갱신 완료 대기(현재 완료 줄 $n0 · 마감 06:00) =="
while :; do
  n=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n=${n:-0}
  [ "$n" -gt "$n0" ] && { echo "== $(date +%F' '%T) 갱신 완료 줄 확인($n0 → $n) =="; break; }
  hh=$(date +%H); [ "$hh" -ge 6 ] && [ "$hh" -lt 12 ] && { echo "== $(date +%F' '%T) 마감 06:00 — 현 배치로 진행 =="; break; }
  sleep 120
done
barrier() { bash $ROOT/02_Infrastructure/ops/refresh_barrier.sh wait 7200 60 | sed "s/^/[배리어] /"; return "${PIPESTATUS[0]}"; }
barrier; brc=$?
if [ "$brc" = "10" ]; then echo "== $(date +%F' '%T) 배리어 2시간 뒤에도 잡힘 — 측정하지 않는다 =="; sentinel p3r03_measured.done barrier_held 10; exit 4; fi
echo "== $(date +%F' '%T) precheck =="
Rscript $ROOT/$RDR/precheck.R || { echo "== $(date +%F' '%T) precheck 불일치 — 측정하지 않는다 =="; sentinel p3r03_measured.done precheck_fail 3; exit 3; }
FPS="bash $ROOT/$RDR/fingerprint.sh"
m() {
  local code="$1" res="$ROOT/$RDR/results/$1"
  if [ -f "$res.json" ] && grep -q '"ok": *true' "$res.json"; then echo "[$code] [측정] 이미 있음(지문 보존)"; return 0; fi
  rm -rf "$res" "$res.json" "$res.fp_start" "$res.fp_end" "$res.fpc_start" "$res.fpc_end"     # 옛 칸 평가 캐시 · 지문 · ok=false 잔재 제거(필수 2)
  if [[ "$code" == *_RX0 ]]; then export QVEST_RP_REGISTER=0; else unset QVEST_RP_REGISTER; fi
  $FPS equality > "$res.fp_start"; $FPS record > "$res.fpc_start"
  Rscript $ROOT/04_Research/programs/_lib/measure_round_cell.R "$RDR" "$PRE" "$code" 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$code] /"
  $FPS equality > "$res.fp_end"; $FPS record > "$res.fpc_end"
}
okc() { [ -f "$ROOT/$RDR/results/$1.json" ] && grep -q '"ok": *true' "$ROOT/$RDR/results/$1.json"; }
mm() { m "$1"; okc "$1" || { echo "[$1] 인프라 실패(ok ≠ true) — 같은 사양 1회 재측정(사전등록 규칙)"; m "$1"; }; }
export -f m okc mm; export ROOT RDR PRE FPS
VARS="HRP NCO MRE CVR ERC"
group() {   # $1 = 엔진
  echo "== $(date +%F' '%T) 엔진 묶음 $1 — RX0 먼저 단독 =="
  bash -c "mm P3R03_$1_RX0"
  for v in $VARS; do echo "P3R03_$1_$v"; done | xargs -P 3 -I{} bash -c 'mm {}'
}
same_fp() {   # $1 = 엔진 — 묶음 6칸 시작 · 종료 지문이 모두 같으면 0
  local f u
  u=$(for c in RX0 $VARS; do for t in fp_start fp_end; do f="$ROOT/$RDR/results/P3R03_$1_$c.$t"; [ -f "$f" ] && tr '\n' '|' < "$f" || echo MISSING; echo; done; done | sort -u | wc -l)
  [ "$u" = "1" ]
}
for eng in E2 E3; do
  group $eng
  if ! same_fp $eng; then
    echo "== $(date +%F' '%T) $eng 묶음 지문 불일치 — 배리어 대기 뒤 묶음 전체 1회 재측정 =="
    if barrier; then
      for c in RX0 $VARS; do rm -f "$ROOT/$RDR/results/P3R03_${eng}_$c.json"; done
      group $eng
      same_fp $eng || echo "== $(date +%F' '%T) $eng 묶음 지문 여전히 불일치 — 판정은 evaluate.R 이 거부한다(rules.vintage_group) =="
    else
      echo "== $(date +%F' '%T) 배리어 2시간 뒤에도 잡힘 — $eng 재측정 생략(판정은 evaluate.R 이 거부한다) =="
    fi
  fi
done
nok=0; for eng in E2 E3; do for c in RX0 $VARS; do okc "P3R03_${eng}_$c" && nok=$((nok+1)); done; done
echo "== $(date +%F' '%T) 측정 끝 — ok $nok/12 =="
sentinel p3r03_measured.done measured 0 "ok=$nok/12"
bash $ROOT/04_Research/programs/_lib/eval_parallel.sh $RDR/evaluate.R auto $RDR/evaluate; erc=$?
echo "== $(date +%F' '%T) 평가 · 판정 끝(rc=$erc) =="
sentinel p3r03_evaluated.done "$([ "$erc" = "0" ] && echo evaluated || echo eval_failed)" "$erc" "ok=$nok/12"
