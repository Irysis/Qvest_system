#!/usr/bin/env bash
# P2R05 분위 모델 캐시 워밍(DESIGN §7.3 순서 1~6) — 등록 → 커밋 → ★워밍 → 측정. 사전등록 평가 경로 핀 대상(결과 전에 고정).
#   ★Q 가 레인 GPU 배분(도훈 확인 — 열린 질문 6)을 정한 뒤에 띄운다. 이 스크립트는 레인을 멈추지 않고 어떤 프로세스도 끄지 않는다.
#   ① 정적 검사 · 등록 · 커밋 · 핀 — Rscript precheck.R --warm(템플릿 차분 rc 0 · 생성 엔진 7 md5 = 매니페스트 = 사전등록 핀 · 정적 PIT(lookahead_detector) ·
#      CODE_VERSION · 규칙 상수 · 운영 경로 · 러너 축 · 사전등록 두 사본 커밋 · 파이썬 판) — 비싼 실행 뒤 주석 오탐으로 전량 버린 10-17 교훈 때문에 맨 앞
#   ② 양성 대조 · 뮤테이션 리허설 결과 확인 — 같은 검사 안(positive_control_rehearsal.json · pass ∧ 뮤테이션 전부 잡힘 ∧ 현 템플릿 판 ∧ md5 = 핀)
#   ③ GPU 게이트 — Rscript precheck.R --gpu-gate(nvidia-smi 표의 다른 Type C 0 까지 폴링 대기 · 끄지 않는다 · memory.used 기록) · CUDA 가용 · 레인 스위치 확인
#      (레인 켜짐 = 워밍 중 레인이 GPU 작업을 시작할 수 있다 → --allow-lane-on 없이는 시작하지 않는다 · 정지 여부 = 도훈 확인 사항)
#   ④ engine_Q50.R 단독 실행(셀 엔진 밖 · 엔진만 · warm_engine.R run — 셀 경로와 같은 RAWDATA) · PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2(P2R03 10-18 04시 사건 처치) ·
#      다른 칸 동시 실행 금지 = GPU 잠금(night_state/p2r05_gpu.lock.d — measure.sh 와 같은 잠금) · 감시 = 진행 줄의 월당 학습 초 > 실행 중앙값 × 3(DESIGN §7.3 운영 감시 문턱) ·
#      진행 줄 정체 · CPU 학습이면 경고 줄(끄지 않는다 — 완료 달은 캐시에 남는다 · 워커를 줄인 재기동 판단 = Q)
#   ⑤ 단정 — 학습 달 전부 cuda(diag device · 혼합 장치 캐시 금지) · 분위 캐시 전 달 · 양성 대조 · 예측표(warm/q50.json)
#   ⑤' 재시드 워밍(판단 T1 R-20261018-007 · DESIGN §0b 14) — engine_RX0S.R(원본 RX0 와 .SEED_BASE 한 줄만 다름 · 경로 = 매니페스트) 단독 전 달(새 시드 → 전 달 새 학습 · GPU) ·
#      cuda 단정(warm/rx0s.json) — 분위 워밍과 겹치지 않게 차례로(계획 GPU ≈ 8시간 = 분위 + 재시드)
#   ⑥ RX0 평균 캐시 확인 — RP_AUTO_2002_06975/engine.R 단독(적중이면 GPU 미사용 · 데이터 판본이 바뀐 달만 재학습 · warm/rx0.json)
#   → 센티널 04_Research/programs/_lib/night_state/p2r05_warm.done(JSON · warm_engine.R finalize — 분위 캐시 a/b · 재시드 캐시 a/b · 양성 대조 · CODE_VERSION · 예측표 ·
#     memory.used 시작/끝 · dnn_input 지문 시작/끝 · 엔진 md5(규칙 7 · 재시드)) · 분기점 알림 1통(notify.R --warm · --no-notify 로 끔)
#   실패는 센티널을 덮지 않는다(warm/last_failure.txt · 알림) — 완료된 시도만 센티널을 쓴다(실패 상태 포함). 측정 직전 precheck.R --warm-check 가 센티널 신선도를 단정한다.
# 사용: bash warm_cache.sh [--allow-lane-on] [--gpu-deadline=YYYY-mm-ddTHH:MM] [--no-notify]
#       분리 실행 권장: bash 04_Research/programs/_lib/detached_env.sh <이 파일> <로그>   (measure.sh --rewarm 이 잠금을 쥔 채 부를 때 = P2R05_GPU_LOCK_HELD=1)
# 종료 코드: 0 = 센티널 ok · 1 = 센티널 failed(완료된 시도) · 2 = 환경 · 3 = precheck --warm 불일치 · 4 = 배리어 2시간 · 5 = GPU 잠금(다른 워밍 · 측정) ·
#            6 = GPU 게이트 마감 · 바쁨 · 7 = CUDA 불가 · 8 = nvidia-smi 조회 불가 · 9 = 레인 켜짐(--allow-lane-on 없음) · 11 = 분위 워밍 실패 · 12 = RX0 확인 실패 ·
#            13 = 재시드 워밍 실패(엔진 경로 · 실행)
set -u
ROOT=/c/Users/99922/OneDrive/Quant_Module_Moltbot
RDR=04_Research/programs/P2_DEFENSE/P2R05_distribution_target
DT=04_Research/strategies/DT_2002_06975
RX0_ENGINE=04_Research/strategies/RP_AUTO_2002_06975/engine.R
ST=$ROOT/04_Research/programs/_lib/night_state
WD=$ROOT/$RDR/warm
LOCKD=$ST/p2r05_gpu.lock.d
MON_MULT=3            # DESIGN §7.3 '월당 초가 실행 중앙값의 3배를 넘으면 폴백 의심'(운영 감시 문턱 · 사건 배율 10~20배보다 충분히 낮다)
MON_EVERY=20          # 감시 간격 = 30초 폴링 × 20 = 10분 — 진행 줄 간격(12개월 ≈ 월당 549초 × 12 ÷ 워커 8 ≈ 14분 · DESIGN §2.2 실측) 안에서 한 번은 본다
[ -f "$ROOT/02_Infrastructure/hooks/qvest_hook_router.py" ] || { echo "[warm] 프로젝트 루트 표지 없음: $ROOT"; exit 2; }
cd $ROOT || exit 2
export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot
export PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2
mkdir -p "$ST" "$WD"
LANE_OK=0; NOTIFY=1; DEADLINE=""
for a in "$@"; do case "$a" in --allow-lane-on) LANE_OK=1 ;; --no-notify) NOTIFY=0 ;; --gpu-deadline=*) DEADLINE="$a" ;; esac; done
[ "${P2R05_GPU_LOCK_HELD:-0}" = "1" ] && NOTIFY=0      # measure.sh --rewarm 이 부름 — 알림은 measure 쪽이 낸다
say() { echo "== $(date +%F' '%T) [P2R05 워밍] $*"; }
notify() { [ "$NOTIFY" = "1" ] && Rscript $ROOT/$RDR/notify.R --warm; return 0; }
fail() { echo "status=$1 rc=$2 at=$(date +%F' '%T) ${3:-}" > "$WD/last_failure.txt"; say "중단 — $1(rc $2) ${3:-}"; notify; exit "$2"; }
## GPU 잠금 — mkdir 원자성 · 주인 pid(MSYS)가 죽었으면 회수(refresh_barrier.sh 와 같은 판정: kill -0 실패 ∨ /proc/<pid> 없음 — MSYS 표의 죽은 항목 대비) ·
##   주인 기록이 없으면 확인 불가(손으로 지운다 — 안전 쪽)
LOCK_MINE=0
lock_take() {
  [ "${P2R05_GPU_LOCK_HELD:-0}" = "1" ] && return 0
  if mkdir "$LOCKD" 2>/dev/null; then echo "pid=$$ who=warm at=$(date +%F' '%T)" > "$LOCKD/owner"; LOCK_MINE=1; return 0; fi
  local op; op=$(sed -n 's/^pid=\([0-9]*\).*/\1/p' "$LOCKD/owner" 2>/dev/null)
  if [ -n "$op" ] && { ! kill -0 "$op" 2>/dev/null || [ ! -d "/proc/$op" ]; }; then
    say "주인 없는 GPU 잠금(pid $op 종료) — 회수"; rm -rf "$LOCKD"
    if mkdir "$LOCKD" 2>/dev/null; then echo "pid=$$ who=warm at=$(date +%F' '%T)" > "$LOCKD/owner"; LOCK_MINE=1; return 0; fi
  fi
  return 1
}
lock_drop() { [ "$LOCK_MINE" = "1" ] && rm -rf "$LOCKD"; LOCK_MINE=0; }
trap lock_drop EXIT
lock_take || fail gpu_locked 5 "잠금 $(cat "$LOCKD/owner" 2>/dev/null || echo '주인 기록 없음 — 확인 뒤 손으로 지운다')"
say "시작(pid $$ · 잠금 $([ "$LOCK_MINE" = "1" ] && echo '획득' || echo '호출자 보유') · PYTORCH_CUDA_ALLOC_CONF=$PYTORCH_CUDA_ALLOC_CONF)"
# 0. 리프레시 배리어 — 갱신 중이면 끝날 때까지(같은 배치에서 워밍 · 측정) · 2시간 넘게 잡히면 중단
bash $ROOT/02_Infrastructure/ops/refresh_barrier.sh wait 7200 60 | sed "s/^/[배리어] /"; [ "${PIPESTATUS[0]}" = "10" ] && fail barrier_held 4
# ① · ② 정적 검사 · 등록 · 커밋 · 핀 · 양성 대조 리허설
Rscript $ROOT/$RDR/precheck.R --warm || fail precheck_fail 3 "warm/precheck_warm.json"
# ③ GPU 게이트 · CUDA · 레인
LANE=$(Rscript -e 'cat(isTRUE(jsonlite::fromJSON("06_Registry/reinforce_auto_config.json")$replication_lane$enabled))' 2>/dev/null)
say "충실구현 레인 replication_lane.enabled = ${LANE:-판독 실패}"
if [ "$LANE" != "FALSE" ] && [ "$LANE_OK" != "1" ]; then fail lane_on 9 "레인이 켜져 있다(또는 판독 실패) — 도훈 확인(정지 또는 허용) 뒤 --allow-lane-on"; fi
Rscript $ROOT/$RDR/precheck.R --gpu-gate $DEADLINE --gpu-out="$WD/gpu_gate.json"; grc=$?
[ "$grc" = "8" ] && fail smi_fail 8 "nvidia-smi 조회 불가 — 다른 연산 0 을 확인할 수 없다"
[ "$grc" != "0" ] && fail gpu_busy 6 "다른 연산(Type C) 프로세스가 남아 있다(마감) — 끄지 않는다"
PY=$ROOT/.venv_qvest_ml/Scripts/python.exe; [ -f "$PY" ] || PY="${QVEST_PY:-}"
"$PY" -c "import torch, sys; sys.exit(0 if torch.cuda.is_available() else 1)" || fail cuda_unavailable 7 "venv torch 가 CUDA 를 못 본다 — CPU 학습(혼합 장치 캐시)을 만들지 않는다"
mem() { nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' \r'; }
MEM0=$(mem); bash $ROOT/$RDR/fingerprint.sh dnn_input > "$WD/fp_start.txt"
say "GPU memory.used 시작 ${MEM0:-?} MiB · dnn_input 지문 기록"
: > "$WD/monitor.log"
# ④ · ⑤ 엔진 단독 실행 + 감시
run_engine() {   # $1 = 엔진(저장소 상대) · $2 = 꼬리표
  local eng="$1" tag="$2" wpid rc n=0
  say "엔진 단독 실행 $tag — $eng(로그 warm/warm_$tag.log)"
  P2R05_WARM_FROM_SCRIPT=1 Rscript $ROOT/$RDR/warm_engine.R run "$eng" "$tag" > "$WD/warm_$tag.log" 2>&1 &
  wpid=$!
  while kill -0 "$wpid" 2>/dev/null; do
    sleep 30; n=$((n + 1))
    if [ $((n % MON_EVERY)) = "0" ] && kill -0 "$wpid" 2>/dev/null; then
      Rscript $ROOT/$RDR/warm_engine.R monitor "$WD/warm_$tag.log" "$MON_MULT" 2>&1 | sed "s/^/[감시 $tag] /" | tee -a "$WD/monitor.log"
    fi
  done
  wait "$wpid"; rc=$?
  tail -3 "$WD/warm_$tag.log" | sed "s/^/[$tag] /"
  return $rc
}
run_engine "$DT/engine_Q50.R" q50 || fail q50_failed 11 "warm/q50.json · warm/warm_q50.log"
# ⑤' 재시드 워밍(판단 T1 R-20261018-007 · DESIGN §0b 14) — engine_RX0S.R 단독(새 시드 → 전 달 새 학습 · 같은 할당 설정 · 분위 워밍 뒤 · 한 번에 엔진 하나)
RX0S_ENGINE=$(Rscript -e 'source("04_Research/programs/P2_DEFENSE/P2R05_distribution_target/engine_checks.R"); cat(P2R05_DTC$rx0s_rel("C:/Users/99922/OneDrive/Quant_Module_Moltbot"))' 2>/dev/null | tr -d '\r')
[ -n "$RX0S_ENGINE" ] && [ -f "$ROOT/$RX0S_ENGINE" ] || fail rx0s_missing 13 "재시드 엔진 경로 해석 실패 또는 파일 없음(${RX0S_ENGINE:-?})"
run_engine "$RX0S_ENGINE" rx0s || fail rx0s_failed 13 "warm/rx0s.json · warm/warm_rx0s.log"
# ⑥ RX0 평균 캐시 확인(적중이면 GPU 미사용)
run_engine "$RX0_ENGINE" rx0 || fail rx0_failed 12 "warm/rx0.json · warm/warm_rx0.log"
MEM1=$(mem); bash $ROOT/$RDR/fingerprint.sh dnn_input > "$WD/fp_end.txt"
Rscript $ROOT/$RDR/warm_engine.R finalize --fp-start="$WD/fp_start.txt" --fp-end="$WD/fp_end.txt" --mem-start="${MEM0:-NA}" --mem-end="${MEM1:-NA}" \
  --gate="$WD/gpu_gate.json" --lane="${LANE:-NA}$([ "$LANE_OK" = "1" ] && echo '(allow-lane-on)')" --monitor-log="$WD/monitor.log"; frc=$?
rm -f "$WD/last_failure.txt"
say "센티널 $([ "$frc" = "0" ] && echo ok || echo failed)(rc $frc) — $ST/p2r05_warm.done"
notify
exit $frc
