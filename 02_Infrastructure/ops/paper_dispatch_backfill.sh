#!/usr/bin/env bash
# paper_dispatch_backfill.sh — 논문 라우터 큐의 **미소비 날짜**를 찾아 dispatcher 를 날짜별로 구동.
#
# 왜 (2026-08-13 실사고):
#   `paper_research_dispatch.R` 은 `mode_queue_<TODAY>.json` **하나만** 읽고 없으면 즉시 종료한다
#   (그 파일 :17,:19). 그런데 소비자가 생산자보다 **먼저** 돈다 — 08-13 실측 타임라인:
#     dispatch 06:47:07 → "no queue" / 라우터 06:53:20 시작 → 큐 07:02 기록 → 07:38 종료.
#   다음 날 dispatch 는 다음 날 큐를 읽으므로 그날 큐는 **영원히 회수되지 않는다.**
#   ★비대칭이 핵심: 라우터는 2026-07-10 v3 에서 7일 백로그 스캔을 받았는데(07-08 spend-limit 로
#     17편 좌초한 사건 대응) **그 소비자에는 같은 장치가 안 들어갔다.** 같은 실패를 반쪽만 고친 상태.
#   미소비 census 2026-08-13: 47편 — 06-19 25편 · 07-05 18편 · 08-13 4편.
#
# 설계 — dispatcher 본문(550줄)을 고치지 않는다:
#   그 스크립트는 이미 `QVEST_DISPATCH_TODAY` 를 지원하고, `today` 사용처가 6곳(큐 경로 · 로그 ·
#   출력 date 필드 · 출력 경로 · 텔레그램 lock_scope)뿐이라 **날짜별 재호출이 정확히 등가**다.
#   큰 파일을 루프로 리팩터링하는 것보다 검증 표면이 훨씬 작다.
#
# ★무음 절단 금지: 창(window) 밖이라 건너뛴 날짜는 **반드시 개수와 목록을 찍는다.**
#   조용히 자르면 "커버했다"로 읽힌다 — 이 저장소가 반복해 온 실패 형태.
#
# 사용:
#   bash 02_Infrastructure/ops/paper_dispatch_backfill.sh                 # 창(기본 7일) 내 미소비분
#   bash 02_Infrastructure/ops/paper_dispatch_backfill.sh --all           # 전 기간 드레인
#   bash 02_Infrastructure/ops/paper_dispatch_backfill.sh --dry-run       # 선정만 출력, 실행 없음
#   bash 02_Infrastructure/ops/paper_dispatch_backfill.sh --window=30
#
# env:
#   QVEST_DISPATCH_BACKLOG_DAYS  창 크기(기본 7)
#   QVEST_BACKFILL_TODAY         기준일 override (YYYYMMDD, 검사 결정성용)
#   QVEST_DISPATCH_RUNNER        dispatcher 실행 명령 override (검사용. 기본 Rscript ...)
set -uo pipefail

_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1090
source "$_SELF_DIR/resolve_project.sh" 2>/dev/null || true
BASE="${QM_ROOT:-${PROJECT:-${CLAUDE_PROJECT_DIR:-$(cd "$_SELF_DIR/../.." && pwd)}}}"
cd "$BASE" || { echo "[backfill] PROJECT 해석 실패: $BASE" >&2; exit 1; }

STAGE="stage_artifacts/paper_recharge"
WINDOW="${QVEST_DISPATCH_BACKLOG_DAYS:-7}"
TODAY="${QVEST_BACKFILL_TODAY:-$(date +%Y%m%d)}"
ALL=0; DRY=0
for a in "$@"; do
  case "$a" in
    --all)       ALL=1 ;;
    --dry-run)   DRY=1 ;;
    --window=*)  WINDOW="${a#*=}" ;;
  esac
done

RUNNER="${QVEST_DISPATCH_RUNNER:-}"
if [ -z "$RUNNER" ]; then
  # LC_ALL 고정 — cron 의 C 로케일에서 R 이 UTF-8 한글 리터럴을 **파싱 시점에** 망가뜨린다
  # (morning_run.sh:144 선례. 출력단 UTF-8 쓰기로는 못 고침).
  # ★로케일 문자열은 **공백 포함** 'English_United States.utf8' 이 정본이다(morning_run.sh:151).
  #   밑줄판은 R 이 "Setting LC_COLLATE=... failed" 경고만 내고 넘어가 — 조용히 C 로 폴백해
  #   한글 리터럴이 파싱 시점에 깨진다(구 사고: verdict "가중 레버 아님" → "j0").
  RUNNER="LC_ALL='English_United States.utf8' Rscript '$BASE/02_Infrastructure/ops/paper_research_dispatch.R'"
fi

_epoch() { date -d "$1" +%s 2>/dev/null || echo 0; }
T_EPOCH=$(_epoch "$TODAY")

PENDING=""; SKIPPED=""; N_PEND=0; N_SKIP=0; N_DONE=0
for q in "$STAGE"/mode_queue_*.json; do
  [ -e "$q" ] || continue
  D="$(basename "$q")"; D="${D#mode_queue_}"; D="${D%.json}"
  case "$D" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) continue ;; esac
  if [ -f "$STAGE/research_status_${D}.json" ]; then N_DONE=$((N_DONE + 1)); continue; fi
  d_ep=$(_epoch "$D"); age=-1
  [ "${d_ep:-0}" -gt 0 ] && [ "${T_EPOCH:-0}" -gt 0 ] && age=$(( (T_EPOCH - d_ep) / 86400 ))
  if [ "$ALL" -eq 0 ] && [ "${age:-0}" -gt "$WINDOW" ] 2>/dev/null; then
    N_SKIP=$((N_SKIP + 1)); SKIPPED="${SKIPPED:+$SKIPPED }${D}(${age}d)"; continue
  fi
  N_PEND=$((N_PEND + 1)); PENDING="${PENDING:+$PENDING }$D"
done

# 오래된 것 먼저 — 순서가 뒤집히면 최신 결과가 구판에 덮일 여지가 생긴다
PENDING="$(printf '%s\n' $PENDING | sort | tr '\n' ' ')"
PENDING="${PENDING% }"

echo "[backfill] 기준일 $TODAY · 창 ${WINDOW}일$([ "$ALL" -eq 1 ] && echo ' (--all: 창 무시)')"
echo "[backfill] 소비완료 $N_DONE · 대상 $N_PEND · 창밖 제외 $N_SKIP"
# ★제외분은 반드시 명시한다. 조용히 자르면 '전부 처리했다'로 읽힌다.
[ "$N_SKIP" -gt 0 ] && echo "[backfill] ★창밖 미처리(--all 로 포함): $SKIPPED"
[ "$N_PEND" -eq 0 ] && { echo "[backfill] 대상 없음"; exit 0; }
echo "[backfill] 대상 날짜: $PENDING"

if [ "$DRY" -eq 1 ]; then echo "[backfill] DRY-RUN — 실행 없음"; exit 0; fi

RC_ANY=0
for D in $PENDING; do
  echo "[backfill] ── $D 구동"
  QVEST_DISPATCH_TODAY="$D" QVEST_PAPER_DISPATCH_ENABLE=1 \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 ARROW_NUM_THREADS=1 R_DATATABLE_NUM_THREADS=1 \
    bash -c "$RUNNER"
  rc=$?
  if [ -f "$STAGE/research_status_${D}.json" ]; then
    echo "[backfill] ── $D 완료 (rc=$rc, 산출 있음)"
  else
    # ★rc=0 인데 산출이 없으면 '조용히 아무것도 안 한 것'이다 — 성공과 구분해 남긴다.
    echo "[backfill] ── ★$D rc=$rc 인데 research_status 미생성 — 미소비 잔존"
    RC_ANY=1
  fi
done
exit $RC_ANY
