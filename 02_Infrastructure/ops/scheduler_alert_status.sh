#!/bin/bash
# scheduler_alert_status.sh — 무인 러너 경보 마커의 **읽는 쪽** (2026-08-22 신설)
#
# 왜 있나 (실측 2026-08-22):
#   무인 러너들(paper_router · alpha_queue · factor_recheck · mode_queue)은 실패 시
#   `.cache/scheduler_alerts/<comp>_<reason>_<date>.alert` 마커를 남긴다. 텔레그램이
#   죽어도 사실은 남기려는 fail-soft 설계다. **그런데 그 디렉터리를 읽는 소비자가 없었다** —
#   `bootstrap.sh` 의 scheduler_alerts 참조 0건, 마커를 만지는 8개 파일이 전부 writer
#   (또는 morning_run 의 재시도 판정용 내부 조회)였다.
#   실측 결과 미해소 16건이 쌓여 있었고, 그중 하나가 **그날 무인 레인 전체를 세운**
#   `paper_router | auth_expired`(헤드리스 OAuth 401)였다. 아무 화면에도 안 떴다.
#
# ★같은 계통의 반복이다: 측정/기록은 되는데 **소비면이 닫혀 있어** 다음 사람에게 도달하지 않는다
#   (method_registry 환류 단절 · knowledge_index 지연과 동형).
#
# 사용:
#   bash scheduler_alert_status.sh --status-line   # 부트 1줄
#   bash scheduler_alert_status.sh                 # 상세 목록
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh" 2>/dev/null || true
BASE="${BASE:-${PROJECT:-$PWD}}"
# ★테스트 이음매: resolve_project.sh:89 이 BASE 를 무조건 덮어써(BASE="$PROJECT")
#   env 로 루트를 갈아끼우는 격리가 **구조적으로 불가능**하다. 그래서 대상 디렉터리만
#   명시 인자로 연다(편입 검사기의 QVEST_SEC_* 선례와 동일). 미지정 시 동작 불변.
ADIR="${QVEST_ALERT_DIR:-$BASE/.cache/scheduler_alerts}"

# 자동복구 여부 판정은 분류기 정본에 위임한다 — 여기에 표를 다시 적지 않는다
# (같은 표를 소비자마다 재구현한 것이 2026-08-02 3연발 결함의 기전이었다).
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true

MODE="${1:-detail}"

if [ ! -d "$ADIR" ]; then
  [ "$MODE" = "--status-line" ] && echo "SchedAlerts: 디렉터리 없음 (무인 러너 미가동)"
  exit 0
fi

shopt -s nullglob
FILES=("$ADIR"/*.alert)
N=${#FILES[@]}

if [ "$N" -eq 0 ]; then
  [ "$MODE" = "--status-line" ] && echo "SchedAlerts: 미해소 0건"
  exit 0
fi

# 사람 조치가 필요한(자동복구 안 되는) 건을 따로 센다 — 이 축이 없으면 경보가
# '학습된 무시'가 된다(전부 같은 무게로 보이면 아무것도 안 보인다).
HUMAN=0; HUMAN_LIST=""; OLDEST_D=""; DETAIL=""
# 2026-08-22: unknown/partial 을 따로 센다 — 구판은 `no` 만 세고 나머지를 전부
#   "자동복구 대상" 으로 접었다. 실측 18건 중 yes 는 **0건**이었는데도 그렇게 표시됐다.
UNK=0; UNK_LIST=""; PART=0; AUTO_YES=0
NOW=$(date +%s)
for f in "${FILES[@]}"; do
  comp=$(grep -m1 '^component=' "$f" 2>/dev/null | cut -d= -f2)
  reason=$(grep -m1 '^reason=' "$f" 2>/dev/null | cut -d= -f2-)
  ts=$(stat -c %Y "$f" 2>/dev/null || echo "$NOW")
  age=$(( (NOW - ts) / 86400 ))
  auto="unknown"
  command -v sched_failure_autorecovers >/dev/null 2>&1 && \
    auto=$(sched_failure_autorecovers "$reason" 2>/dev/null || echo unknown)
  case "$auto" in
    no)
      HUMAN=$((HUMAN+1))
      case "$HUMAN_LIST" in *"${comp}/${reason}"*) : ;; *) HUMAN_LIST="${HUMAN_LIST:+$HUMAN_LIST · }${comp}/${reason}" ;; esac
      ;;
    yes)     AUTO_YES=$((AUTO_YES+1)) ;;
    partial) PART=$((PART+1)) ;;
    *)
      # ★unknown = "자동복구된다" 가 아니라 **모른다**. 접지 않는다.
      UNK=$((UNK+1))
      case "$UNK_LIST" in *"${comp}/${reason}"*) : ;; *) UNK_LIST="${UNK_LIST:+$UNK_LIST · }${comp}/${reason}" ;; esac
      ;;
  esac
  [ -z "$OLDEST_D" ] && OLDEST_D=$age
  [ "$age" -gt "$OLDEST_D" ] && OLDEST_D=$age
  DETAIL="${DETAIL}  ${comp} | ${reason} | ${age}d | 자동복구=${auto} | $(basename "$f")"$'\n'
done

if [ "$MODE" = "--status-line" ]; then
  # ★분류를 접지 않는다 — 각각 세어 각각 적는다.
  #   "전부 자동복구 대상" 은 **정말 전부 yes 일 때만** 쓴다(2026-08-22 실사고).
  SEG=""
  [ "$HUMAN" -gt 0 ] && SEG="${SEG:+$SEG · }★사람 조치 ${HUMAN}건(${HUMAN_LIST})"
  [ "$UNK"   -gt 0 ] && SEG="${SEG:+$SEG · }판정불가 ${UNK}건(${UNK_LIST})"
  [ "$PART"  -gt 0 ] && SEG="${SEG:+$SEG · }부분복구 ${PART}건"
  [ "$AUTO_YES" -gt 0 ] && SEG="${SEG:+$SEG · }자동복구 ${AUTO_YES}건"
  if [ -z "$SEG" ]; then
    echo "SchedAlerts: 미해소 ${N}건 · 최고령 ${OLDEST_D}d"
  elif [ "$AUTO_YES" -eq "$N" ]; then
    echo "SchedAlerts: 미해소 ${N}건 (전부 자동복구 대상) · 최고령 ${OLDEST_D}d"
  else
    echo "SchedAlerts: ★미해소 ${N}건 — ${SEG} · 최고령 ${OLDEST_D}d"
  fi
  exit 0
fi

echo "미해소 경보 ${N}건 (사람조치 ${HUMAN} · 판정불가 ${UNK} · 부분복구 ${PART} · 자동복구 ${AUTO_YES}) — $ADIR"
printf '%s' "$DETAIL"
echo "해소: 해당 러너가 성공하면 sched_mark_resolved 가 _resolved/ 로 옮깁니다(삭제 아님)."
