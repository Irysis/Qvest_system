#!/usr/bin/env bash
# P2R05 측정 → 셀 평가 → 판정(분리 실행 · 2026-10-18 · P2R04 measure.sh 를 이어받음) — 데이터 갱신이 끝난 뒤에만(같은 배치) · 워밍 센티널 선행 단정.
#   ① 대기: 띄운 뒤 새 'Daily Refresh v2 Done' 줄이 생길 때까지(마감 06:00 — 갱신이 안 돌면 그 시각에 현 배치로 진행) → 리프레시 배리어 해제 대기
#      (2시간 뒤에도 잡혀 있으면 측정하지 않고 종료). '--now' = 완료 줄 대기만 생략(배리어 · precheck · 워밍 단정 · 칸별 지문은 그대로).
#   ② precheck(사양 16 · 운영 경로(DT 엔진 파일 · 팩터 DB 커넥터 · 등급 계약 v3.2 포함) · DT 엔진(템플릿 차분 · 매니페스트 · 정적 PIT · 상수 · 리허설 요약 · 시험 증거 md5) ·
#      팩터 레지스트리 엔트리 · 비중 카탈로그 lean:entropy · 패키지 · R 판 · 파이썬 판 · 평가 경로 md5 · 행동 카드 설정 사본 · 등록부 사전등록 md5 · 사전등록 커밋) 통과 시에만 ·
#      이 스크립트의 칸 목록 = 사전등록 cells(집합 대조 — 다르면 측정하지 않는다)
#   ③ GPU 잠금(night_state/p2r05_gpu.lock.d — warm_cache.sh 와 같은 잠금 · 워밍과 측정이 같은 GPU 에 겹치지 않게) → 워밍 센티널 단정(precheck.R --warm-check:
#      유효 ∧ 신선(워밍 끝 dnn_input 지문 = 현재) — 판본이 바뀌었으면 측정하지 않는다 · '--rewarm' = warm_cache.sh 를 잠금 쥔 채 다시(바뀐 달만 재학습) 뒤 재단정) ·
#      센티널 사본 results/warm_sentinel.json(이 측정에 묶인 워밍 기록 · 구성 증거 ⑩(a) 입력)
#   ④ 엔진 묶음(E2 11칸 → E3 5칸) — RX0 → RX0S(재시드 짝) 차례로 단독 → 둘 중 하나의 DNN 완료 줄이 '(trained 0, …)'(셀 경로 = 워밍 경로 · 캐시 적중의 증거)이면 나머지 칸 PAR 병렬,
#      아니면(기저 캐시 적중으로 엔진이 안 돌았거나 재학습이 있었으면) 분위 엔진 첫 칸(V1)을 단독으로 먼저 잰 뒤 나머지 병렬 — 같은 GPU 에 분위 학습 둘이 겹치지 않게
#      (DESIGN §7.3 · P2R03 10-18 04시 VRAM 사건). 그 폴백(분위 재학습 가능) 앞에 GPU 게이트(precheck.R --gpu-gate — nvidia-smi 표의 다른 연산(Type C) 0 까지 대기 ·
#      어떤 프로세스도 끄지 않는다 · 최대 GPU_WAIT_S = 배리어 최대 대기와 같은 2시간) — 마감 · 조회 실패 = 측정 중단(gpu_busy · rc 9 · 이미 ok 인 칸은 다음 실행이 건너뛴다)
#      (격리 점검 v1 권고 4 — 워밍 센티널이 쓰이면 레인이 자동 재개된다 · lane_hold_wait.sh). 병렬 기본 2 · '--p=N'(3 허용 — 결과 무관).
#        E2 묶음 11칸 = RX0 + 재시드 RX0S + 변형 V1 · V2 + 진단 Q50 · N1 · N2 · S1 · S2 · W2 + 비교 기준 LV(판단 T2 C-20261018-038 · T1 R-20261018-007)
#        E3 묶음  5칸 = RX0 + 재시드 RX0S + 변형 V1 · V2 + 비교 기준 LV
#      lag-1 진단 칸 없음(시점 신호 없음). 칸마다 측정 전에 옛 칸 평가 캐시 results/<code>/ · 지문을 지운다 · 시작 · 종료 데이터 지문(fingerprint.sh equality · 예측 캐시는 record) ·
#      칸별 DNN 완료 줄을 측정 로그에 남긴다. 인프라 실패(ok ≠ true) 칸은 같은 사양 1회 기계 재측정(rules.remeasure). 묶음 칸 × 시작/끝 지문이 갈리면 배리어 대기 →
#      워밍 신선도 재단정(낡았으면 --rewarm 일 때만 다시 워밍) → 그 묶음 전체를 1회 재측정 — 그래도 갈리면 evaluate.R 이 판정하지 않는다(rules.vintage_group).
#      2계층 모듈 풀 등재는 변형 칸(V*)만 — RX0 · 진단 · 비교 기준 칸은 QVEST_RP_REGISTER=0.
#   ⑤ 평가 전 배리어 → 셀 평가 샤딩(evaluate.R --cells-only --shard=i/K) + 종합 판정 1회(_lib/eval_parallel.sh) ·
#      센티널 night_state/p2r05_{measured,evaluated}.done 에 상태 · 종료 코드(notify_done.sh 가 읽는다)
# 종료 코드: 0 = 평가 끝 · 2 = 환경 · 3 = precheck · 4 = 측정 전 배리어 · 5 = 평가 전 배리어 · 6 = 워밍 센티널 없음 · 무효 · 낡음 · 7 = GPU 잠금 · 8 = 칸 목록 ≠ 사전등록 ·
#            9 = 폴백 GPU 게이트 마감 · 조회 실패(분위 엔진 첫 칸 단독 전 — 다른 연산이 GPU 를 쓰고 있었다) ·
#            11 = 워밍 센티널 사본(results/warm_sentinel.json) 쓰기 실패(측정 시작 · 묶음 재측정 전 — 사본 없이는 평가가 측정과 다른 night_state 판으로 묶일 수 있다 · 격리 점검 v2 권고 5)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
TAG=P2R05
RDR=04_Research/programs/P2_DEFENSE/P2R05_distribution_target
PRE=stage_artifacts/programs/P2_DEFENSE/P2R05_distribution_target/prereg.json
ST=$ROOT/04_Research/programs/_lib/night_state
LOG=$ROOT/.cache/scheduler_logs/daily_refresh.log
LOCKD=$ST/p2r05_gpu.lock.d
ENGINES="E2 E3"
VARS_E2="V1 V2 Q50 N1 N2 S1 S2 W2 LV"     # 변형 먼저(판정 칸) → 진단 → 비교 기준(사전등록 cells 순서 · 조정자 10-18)
VARS_E3="V1 V2 LV"
SEQ="RX0 RX0S"                            # 묶음마다 차례로 단독(기준 → 재시드 짝 · 판단 T1 R-20261018-007 · 조정자 10-18)
DT_FIRST=V1                               # 분위 엔진 첫 칸 — RX0 · RX0S 셀 로그가 캐시 적중(trained 0)을 보이지 못하면 이 칸을 단독으로 먼저
GPU_WAIT_S=7200                           # 폴백 GPU 게이트 최대 대기(초) = 아래 배리어 최대 대기(refresh_barrier wait 7200)와 같은 운영 상한 · 판정 무관
vars_of() { case "$1" in E2) echo "$VARS_E2" ;; E3) echo "$VARS_E3" ;; *) echo "" ;; esac; }
cells_of() { echo "$SEQ $(vars_of "$1")"; }   # 묶음의 전 칸(지문 · 재측정 · 셈)
[ -f "$ROOT/02_Infrastructure/hooks/qvest_hook_router.py" ] || { echo "[$TAG] 프로젝트 루트 표지 없음: $ROOT"; exit 2; }
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot
mkdir -p "$ST" "$ROOT/$RDR/results"
sentinel() { echo "status=$2 rc=$3 at=$(date +%F' '%T) ${4:-}" > "$ST/$1"; }
NOW=0; PAR=2; REWARM=0; LANE_OK=""
for a in "$@"; do case "$a" in --now) NOW=1 ;; --p=[1-9]) PAR="${a#--p=}" ;; --rewarm) REWARM=1 ;; --allow-lane-on) LANE_OK="--allow-lane-on" ;; esac; done
NT=0; for e in $ENGINES; do for c in $(cells_of $e); do NT=$((NT + 1)); done; done   # 측정 칸 수(11 + 5 = 16)
if [ "$NOW" = "1" ]; then
  echo "== $(date +%F' '%T) [$TAG] 즉시 측정(--now) — 갱신 완료 대기 생략 · 현 배치 · 칸 $NT · 병렬 $PAR · 다시 워밍 $REWARM =="
else
  n0=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n0=${n0:-0}
  echo "== $(date +%F' '%T) [$TAG] 데이터 갱신 완료 대기(현재 완료 줄 $n0 · 마감 06:00 · 칸 $NT · 병렬 $PAR · 다시 워밍 $REWARM) =="
  while :; do
    n=$(grep -c "=== Daily Refresh v2 Done" "$LOG" 2>/dev/null || true); n=${n:-0}
    [ "$n" -gt "$n0" ] && { echo "== $(date +%F' '%T) [$TAG] 갱신 완료 줄 확인($n0 → $n) =="; break; }
    hh=$(date +%H); [ "$hh" -ge 6 ] && [ "$hh" -lt 12 ] && { echo "== $(date +%F' '%T) [$TAG] 마감 06:00 — 현 배치로 진행 =="; break; }
    sleep 120
  done
fi
barrier() { bash $ROOT/02_Infrastructure/ops/refresh_barrier.sh wait 7200 60 | sed "s/^/[배리어] /"; return "${PIPESTATUS[0]}"; }
barrier; brc=$?
if [ "$brc" = "10" ]; then echo "== $(date +%F' '%T) [$TAG] 배리어 2시간 뒤에도 잡힘 — 측정하지 않는다 =="; sentinel p2r05_measured.done barrier_held 10; exit 4; fi
echo "== $(date +%F' '%T) [$TAG] precheck =="
Rscript $ROOT/$RDR/precheck.R || { echo "== $(date +%F' '%T) [$TAG] precheck 불일치 — 측정하지 않는다 =="; sentinel p2r05_measured.done precheck_fail 3; exit 3; }
# 칸 목록 = 사전등록 cells(같은 bash sort 로 양쪽을 정렬해 집합 대조)
LISTED=$(for e in $ENGINES; do for c in $(cells_of $e); do echo "${TAG}_${e}_$c"; done; done | sort | tr '\n' ' ')
PREREG=$(Rscript -e 'p <- jsonlite::fromJSON(commandArgs(TRUE)[1], simplifyVector = FALSE); cat(vapply(p$cells, function(z) z$code, ""), sep = "\n")' "$ROOT/$PRE" 2>/dev/null | tr -d '\r' | sort | tr '\n' ' ')
if [ "$LISTED" != "$PREREG" ]; then
  echo "== $(date +%F' '%T) [$TAG] 이 스크립트의 칸 목록 ≠ 사전등록 cells — 측정하지 않는다"; echo "  스크립트: $LISTED"; echo "  사전등록: $PREREG"
  sentinel p2r05_measured.done cells_mismatch 8; exit 8
fi
# GPU 잠금(워밍 · 다른 측정과 겹치지 않게) — mkdir 원자성 · 죽은 주인 = refresh_barrier.sh 와 같은 판정
LOCK_MINE=0
lock_take() {
  if mkdir "$LOCKD" 2>/dev/null; then echo "pid=$$ who=measure at=$(date +%F' '%T)" > "$LOCKD/owner"; LOCK_MINE=1; return 0; fi
  local op; op=$(sed -n 's/^pid=\([0-9]*\).*/\1/p' "$LOCKD/owner" 2>/dev/null)
  if [ -n "$op" ] && { ! kill -0 "$op" 2>/dev/null || [ ! -d "/proc/$op" ]; }; then
    echo "== $(date +%F' '%T) [$TAG] 주인 없는 GPU 잠금(pid $op 종료) — 회수"; rm -rf "$LOCKD"
    if mkdir "$LOCKD" 2>/dev/null; then echo "pid=$$ who=measure at=$(date +%F' '%T)" > "$LOCKD/owner"; LOCK_MINE=1; return 0; fi
  fi
  return 1
}
lock_drop() { [ "$LOCK_MINE" = "1" ] && rm -rf "$LOCKD"; LOCK_MINE=0; }
trap lock_drop EXIT
if ! lock_take; then
  echo "== $(date +%F' '%T) [$TAG] GPU 잠금을 다른 프로세스가 쥐고 있다($(cat "$LOCKD/owner" 2>/dev/null || echo '주인 기록 없음')) — 측정하지 않는다 =="
  sentinel p2r05_measured.done gpu_locked 7; exit 7
fi
# 워밍 센티널 선행 단정(precheck.R --warm-check: 0 = 유효 · 신선 · 10 = 유효하나 낡음 · 1 = 없음 · 무효)
warm_check() { Rscript $ROOT/$RDR/precheck.R --warm-check; }
rewarm() { echo "== $(date +%F' '%T) [$TAG] --rewarm: warm_cache.sh 다시(잠금 유지 · 바뀐 달만 재학습) =="; P2R05_GPU_LOCK_HELD=1 bash $ROOT/$RDR/warm_cache.sh --no-notify $LANE_OK; }
warm_check; wrc=$?
if [ "$wrc" = "10" ] && [ "$REWARM" = "1" ]; then rewarm; warm_check; wrc=$?; fi
if [ "$wrc" != "0" ]; then
  wst=$([ "$wrc" = "10" ] && echo warm_stale || echo warm_invalid)
  echo "== $(date +%F' '%T) [$TAG] 워밍 센티널 단정 실패($wst · rc $wrc) — 측정하지 않는다(warm_cache.sh 먼저 · 낡음 = '--rewarm') =="
  sentinel p2r05_measured.done "$wst" 6; exit 6
fi
cp "$ST/p2r05_warm.done" "$ROOT/$RDR/results/warm_sentinel.json" || {       # 측정에 묶인 워밍 기록 — 실패 = 측정 중단(격리 점검 v2 권고 5 · 실패 의미 고정)
  echo "== $(date +%F' '%T) [$TAG] 워밍 센티널 사본(results/warm_sentinel.json) 쓰기 실패 — 측정하지 않는다(사본 없이는 평가가 측정과 다른 판으로 묶일 수 있다) =="
  sentinel p2r05_measured.done sentinel_copy_failed 11 "stage=start"; exit 11; }
FPS="bash $ROOT/$RDR/fingerprint.sh"
m() {
  local code="$1" res="$ROOT/$RDR/results/$1"
  if [ -f "$res.json" ] && grep -q '"ok": *true' "$res.json"; then echo "[$code] [측정] 이미 있음(지문 보존)"; return 0; fi
  rm -rf "$res" "$res.json" "$res.fp_start" "$res.fp_end" "$res.fpc_start" "$res.fpc_end"     # 옛 칸 평가 캐시 · 지문 · ok=false 잔재 제거
  case "$code" in *_V[0-9]) unset QVEST_RP_REGISTER ;; *) export QVEST_RP_REGISTER=0 ;; esac  # 변형 칸만 2계층 모듈 풀 등재(RX0 · 진단 · 비교 기준 = 미등재)
  $FPS equality > "$res.fp_start"; $FPS record > "$res.fpc_start"
  Rscript $ROOT/04_Research/programs/_lib/measure_round_cell.R "$RDR" "$PRE" "$code" 2>&1 | grep -E "^\[측정\]|Error|에러" | sed "s/^/[$code] /"
  $FPS equality > "$res.fp_end"; $FPS record > "$res.fpc_end"
}
okc() { [ -f "$ROOT/$RDR/results/$1.json" ] && grep -q '"ok": *true' "$ROOT/$RDR/results/$1.json"; }
mm() { m "$1"; okc "$1" || { echo "[$1] 인프라 실패(ok ≠ true) — 같은 사양 1회 재측정(사전등록 규칙)"; m "$1"; }; }
dnn_line() { grep -aoE "\(trained [0-9]+, cache [0-9]+\)" "$ROOT/$RDR/results/$1.log" 2>/dev/null | tail -1; }   # 셀 로그의 DNN 완료 줄(마지막 엔진 실행)
gpu_gate() {   # $1 = 기록 이름 — precheck.R --gpu-gate(다른 Type C 0 까지 대기 · 끄지 않는다 · 마감 = 지금 + GPU_WAIT_S) · rc 0 = 열림 · 7 = 마감 · 8 = 조회 실패
  local dl; dl=$(date -d "+${GPU_WAIT_S} seconds" +%Y-%m-%dT%H:%M)
  Rscript $ROOT/$RDR/precheck.R --gpu-gate --gpu-deadline="$dl" --gpu-out="$ROOT/$RDR/results/gpu_gate_$1.json"
}
export -f m okc mm; export ROOT RDR PRE FPS
group() {   # $1 = 엔진 — SEQ(RX0 → RX0S) 차례로 단독 → 증거 확인 → 나머지 병렬
  local e="$1" vs rest dl ev=0 c; vs=$(vars_of "$e")
  for c in $SEQ; do
    echo "== $(date +%F' '%T) [$TAG] 엔진 묶음 $e — $c 단독 =="
    bash -c "mm ${TAG}_${e}_$c"
    dl=$(dnn_line "${TAG}_${e}_$c"); echo "[${TAG}_${e}_$c] DNN 완료 줄: ${dl:-없음(기저 캐시 적중 · 엔진 미실행 또는 실패)}"
    echo "$dl" | grep -qE "^\(trained 0, " && ev=1                           # 셀 경로가 워밍 캐시를 그대로 찾았다(패널 동일)의 증거
  done
  if [ "$ev" = "1" ]; then
    rest="$vs"
  else
    echo "== $(date +%F' '%T) [$TAG] RX0 · RX0S 셀 로그가 DNN 캐시 적중(trained 0)을 보이지 않는다 — 분위 엔진 첫 칸 ${DT_FIRST} 단독(같은 GPU 에 분위 학습 둘이 겹치지 않게) · 그 앞 GPU 게이트(최대 $((GPU_WAIT_S / 60))분 · 끄지 않는다) =="
    local grc; gpu_gate "fallback_${e}"; grc=$?
    if [ "$grc" != "0" ]; then
      echo "== $(date +%F' '%T) [$TAG] 측정 중단 — 분위 재학습이 필요할 수 있는데 GPU 가 비지 않았다(게이트 rc $grc · 다른 연산 프로세스를 끄지 않는다 · 기록 results/gpu_gate_fallback_${e}.json) · GPU 가 빈 뒤 같은 명령으로 다시(ok 칸은 건너뛴다 · 워밍이 낡았으면 --rewarm · 레인 GPU 배분 = 도훈 확인 사항) =="
      sentinel p2r05_measured.done gpu_busy 9 "group=$e gate_rc=$grc"; exit 9
    fi
    bash -c "mm ${TAG}_${e}_${DT_FIRST}"
    dl=$(dnn_line "${TAG}_${e}_${DT_FIRST}"); echo "[${TAG}_${e}_${DT_FIRST}] DNN 완료 줄: ${dl:-없음}"
    echo "$dl" | grep -qE "^\(trained [1-9]" && echo "== $(date +%F' '%T) [$TAG] 주의 — ${DT_FIRST} 가 셀 경로에서 분위 모형을 다시 학습했다(워밍 캐시 미적중) · 워밍 예측표(센티널 qpred)와 셀 예측이 다를 수 있다 — 평가가 칸 셀 로그의 예측표 경로를 묶인 판(워밍 센티널 qpred)과 대조해 다르면 멈춘다(멈추면 원인 확인 뒤 다시 워밍)"
    rest=$(for v in $vs; do [ "$v" != "$DT_FIRST" ] && echo "$v"; done | tr '\n' ' ')
  fi
  local nr=0; for v in $rest; do nr=$((nr + 1)); done
  echo "== $(date +%F' '%T) [$TAG] 엔진 묶음 $e — 나머지 ${nr}칸 병렬 $PAR =="
  for v in $rest; do echo "${TAG}_${e}_$v"; done | xargs -P "$PAR" -I{} bash -c 'mm {}'
  for c in $(cells_of "$e"); do echo "[${TAG}_${e}_$c] DNN 완료 줄: $(dnn_line "${TAG}_${e}_$c")"; done
}
same_fp() {   # $1 = 엔진 — 묶음 칸 시작 · 종료 지문이 모두 같으면 0(파일 없음 = 불일치)
  local f u
  u=$(for c in $(cells_of "$1"); do for t in fp_start fp_end; do f="$ROOT/$RDR/results/${TAG}_$1_$c.$t"; [ -f "$f" ] && tr '\n' '|' < "$f" || echo MISSING; echo; done; done | sort -u | wc -l)
  [ "$u" = "1" ]
}
for eng in $ENGINES; do
  group $eng
  if ! same_fp $eng; then
    echo "== $(date +%F' '%T) [$TAG] $eng 묶음 지문 불일치 — 배리어 대기 · 워밍 신선도 재단정 뒤 묶음 전체 1회 재측정 =="
    if barrier; then
      warm_check; wrc=$?
      if [ "$wrc" = "10" ] && [ "$REWARM" = "1" ]; then rewarm; warm_check; wrc=$?; fi
      if [ "$wrc" = "0" ]; then
        cp "$ST/p2r05_warm.done" "$ROOT/$RDR/results/warm_sentinel.json" || {   # 다시 워밍한 판을 이 측정에 묶는다 — 실패 = 측정 중단(격리 점검 v2 권고 5)
          echo "== $(date +%F' '%T) [$TAG] $eng 재측정 전 워밍 센티널 사본 쓰기 실패 — 측정 중단(이미 잰 칸은 남는다 · 원인 확인 뒤 같은 명령으로 다시) =="
          sentinel p2r05_measured.done sentinel_copy_failed 11 "stage=regroup group=$eng"; exit 11; }
        for c in $(cells_of $eng); do rm -f "$ROOT/$RDR/results/${TAG}_${eng}_$c.json"; done
        group $eng
        same_fp $eng || echo "== $(date +%F' '%T) [$TAG] $eng 묶음 지문 여전히 불일치 — 판정은 evaluate.R 이 거부한다(rules.vintage_group) =="
      else
        echo "== $(date +%F' '%T) [$TAG] 워밍 센티널이 새 판본과 맞지 않는다(rc $wrc) — $eng 재측정 생략(판정은 evaluate.R 이 거부한다 · 다시 워밍 뒤 측정) =="
      fi
    else
      echo "== $(date +%F' '%T) [$TAG] 배리어 2시간 뒤에도 잡힘 — $eng 재측정 생략(판정은 evaluate.R 이 거부한다) =="
    fi
  fi
done
nok=0; for eng in $ENGINES; do for c in $(cells_of $eng); do okc "${TAG}_${eng}_$c" && nok=$((nok+1)); done; done
echo "== $(date +%F' '%T) [$TAG] 측정 끝 — ok $nok/$NT =="
sentinel p2r05_measured.done measured 0 "ok=$nok/$NT"
lock_drop                                                                       # 평가는 GPU 를 쓰지 않는다 — 잠금을 먼저 푼다
# 평가 전 배리어 — 셀 평가는 원천 RAWDATA 를 읽는다(크기 · 멤버십 · ⑮ 표본 밖 라벨). 갱신이 돌고 있으면 끝날 때까지 기다리고, 2시간 넘게 잡히면 평가하지 않는다
barrier; ebrc=$?
if [ "$ebrc" = "10" ]; then echo "== $(date +%F' '%T) [$TAG] 평가 전 배리어 2시간 뒤에도 잡힘 — 평가하지 않는다 =="; sentinel p2r05_evaluated.done eval_barrier_held 10 "ok=$nok/$NT"; exit 5; fi
bash $ROOT/04_Research/programs/_lib/eval_parallel.sh $RDR/evaluate.R auto $RDR/evaluate; erc=$?
echo "== $(date +%F' '%T) [$TAG] 평가 · 판정 끝(rc=$erc) =="
sentinel p2r05_evaluated.done "$([ "$erc" = "0" ] && echo evaluated || echo eval_failed)" "$erc" "ok=$nok/$NT"
