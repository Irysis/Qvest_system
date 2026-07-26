#!/usr/bin/env bash
#==============================================================================
# hook_fire_coverage.sh — 게이트급 훅의 "발화 0회" 감지 (2026-07-26 도훈 승인)
#
# 왜 필요한가: 이 저장소가 2026-07-26 에 확정한 실패부류의 지문은 **"경고 0"이 아니라
#   "발화 0"** 이다. 실사례 —
#     · harness_health 가 settings.json 훅 등록 0건을 INFO 로 통과(블록을 비워도 부팅 동일)
#     · CBA-02: coherence 크래시 시 7c 백필 게이트가 영영 미발화
#     · selection_contamination_detector 가 구조적 상시-allow (07-03 감사)
#     · agent_role_guard 가 marker writer 부재로 발화 불가 (07-03 문서화)
#   전부 "그 훅이 실제로 돌았는가"를 사후 확인할 수 없어 오래 살아남았다.
#   events.jsonl(v7.0 Sprint 6) 이 정확히 그 목적이었으나 writer 가 죽어 49일 STALE 이었고,
#   07-26 에 _shared_parse.sh 자동 emit 으로 배관을 살렸다. 이 스크립트가 그 소비면이다.
#
# 판정: 기대 훅 목록 대비 최근 N일 발화 0회 = WARN. 원장 자체가 비었거나 낡으면 그것을 먼저 보고
#   (원장 부재를 "발화 0"으로 읽으면 같은 위장이 된다 — 미측정과 0 을 구분한다).
#
# 출력: --boot → [boot] 1~N줄 (WARN-only) / 기본 → 상세 + 마지막 줄 JSON 요약
# 테스트 오버라이드: QVEST_HFC_LEDGER / QVEST_HFC_DAYS / QVEST_HFC_EXPECTED(공백구분)
#==============================================================================
set -u

_MARKER="02_Infrastructure/ops/hook_fire_coverage.sh"
PROJECT=""
for c in "${CLAUDE_PROJECT_DIR:-}" "${QM_ROOT:-}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)"; do
  if [ -n "$c" ] && [ -f "$c/$_MARKER" ]; then PROJECT="$c"; break; fi
done
if [ -z "$PROJECT" ]; then
  echo "[hook-fire] FATAL: PROJECT 해석 실패"
  echo '{"test":"hook_fire_coverage","pass":0,"fail":1,"total":1}'; exit 1
fi

LEDGER="${QVEST_HFC_LEDGER:-$PROJECT/qepm/observability/events.jsonl}"
DAYS="${QVEST_HFC_DAYS:-7}"
MODE="${1:-detail}"

# 기대 목록 = _shared_parse.sh 를 source 하는 게이트급 훅 (자동 emit 경로 커버 대상).
#   ★여기에 없는 게이트급 4종(discovery_graduation_gate / backtest_contract_audit /
#     legacy_write_block / worktask_constraint_enforcer)은 source 를 안 하므로 이 경로로
#     기록되지 않는다 — 커버리지 밖임을 아래에서 **이름으로** 보고한다(조용히 빼지 않는다).
EXPECTED_DEFAULT="safety_guard.sh axiom_enforcement_hook.sh ast_spec_gate.sh artifact_placement_guard.sh cache_registry_enforce.sh worktask_sequence_enforcer.sh"
UNCOVERED="discovery_graduation_gate.sh backtest_contract_audit.sh legacy_write_block.sh worktask_constraint_enforcer.sh"
read -r -a EXPECTED <<< "${QVEST_HFC_EXPECTED:-$EXPECTED_DEFAULT}"

emit_line() { if [ "$MODE" = "--boot" ]; then echo "[boot] $1"; else echo "$1"; fi; }

#──────────────────────────────────────────────────────────────────────────────
# 원장 회전 (2026-07-26) — CHANGELOG:140 이 "events.jsonl rotation 90+ days = v7.2 이연"
#   으로 남겨둔 항목. 07-26 자동 emit 배선으로 **실적재가 시작**되므로 지금 필요해졌다.
#   훅 발화가 세션당 수십~수백 행이라 방치하면 무한 성장하고, 이 스크립트의 라인별 grep
#   파싱도 함께 느려진다. ROTATE_MAX 행 초과 시 뒤쪽(최근) 절반만 남기고 .1 로 보존.
#   ★판정 전에 회전한다 — 회전이 관측창을 줄이면 위 window 가드가 자동으로 보류로 돌린다.
#──────────────────────────────────────────────────────────────────────────────
ROTATE_MAX="${QVEST_HFC_ROTATE_MAX:-20000}"
# ★grep -c 는 대상이 여러 개거나 실패하면 여러 줄/비정수를 낸다 — 정수 비교가 깨진다
#   (실측 에러: integer expected). 숫자만 남기고 기본값을 준다.
_n_now=$(grep -c . "$LEDGER" 2>/dev/null | head -1 | tr -dc '0-9')
_n_now=${_n_now:-0}
if [ "${_n_now:-0}" -gt "$ROTATE_MAX" ]; then
  _keep=$(( ROTATE_MAX / 2 ))
  if tail -n "$_keep" "$LEDGER" > "$LEDGER.rot.tmp" 2>/dev/null; then
    cat "$LEDGER" >> "$LEDGER.1" 2>/dev/null || true
    mv -f "$LEDGER.rot.tmp" "$LEDGER" 2>/dev/null \
      && emit_line "hook-fire: 원장 회전 ${_n_now}행 → 최근 ${_keep}행 유지 (이전분 events.jsonl.1 누적)"
  else
    rm -f "$LEDGER.rot.tmp" 2>/dev/null || true
    emit_line "WARN: 원장 회전 실패 (${_n_now}행) — 무한 성장 중"
  fi
fi

# ── 원장 상태 먼저 (미측정 ≠ 0) ───────────────────────────────────────────────
if [ ! -f "$LEDGER" ]; then
  emit_line "WARN: hook-fire 원장 부재 ($LEDGER) — 발화 0 이 아니라 **미측정**. _shared_parse.sh 자동 emit 배선 확인"
  echo '{"test":"hook_fire_coverage","pass":0,"fail":1,"total":1}'; exit 1
fi
N_ROWS=$(grep -c . "$LEDGER" 2>/dev/null | head -1 | tr -dc '0-9')
N_ROWS=${N_ROWS:-0}
LED_AGE_D=$(( ( $(date +%s) - $(stat -c %Y "$LEDGER" 2>/dev/null || echo 0) ) / 86400 ))
if [ "$N_ROWS" -eq 0 ]; then
  emit_line "WARN: hook-fire 원장 0행 — 미측정(자동 emit 미발화 의심)"
  echo '{"test":"hook_fire_coverage","pass":0,"fail":1,"total":1}'; exit 1
fi

# ── 최근 DAYS 일 내 발화한 hook_name 집합 ────────────────────────────────────
CUT=$(date -d "$DAYS days ago" +%Y-%m-%d 2>/dev/null || echo "0000-00-00")
# ★수동 오프셋 산술 금지 (2026-07-26 실측: RSTART+14/RLENGTH-15 가 한 칸 어긋나 원장 49행에
#   대해 발화 0 을 보고했다 — 이 세션이 반복해 겪은 '검사가 잘못된 것을 잼' 과 같은 부류).
#   값 추출은 grep -o 로, 자리수 계산 없이.
FIRED=$(grep '"event_type":"hook_fired"' "$LEDGER" 2>/dev/null \
        | while IFS= read -r _ln; do
            _ts=$(printf '%s' "$_ln" | grep -oE '"timestamp":"[^"]+"' | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
            _hn=$(printf '%s' "$_ln" | grep -oE '"hook_name":"[^"]+"' | head -1 | sed 's/.*:"//;s/"$//')
            [ -n "$_ts" ] && [ -n "$_hn" ] && [ "$_ts" \> "$CUT" -o "$_ts" = "$CUT" ] && printf '%s\n' "$_hn"
          done | sort -u)

#──────────────────────────────────────────────────────────────────────────────
# ★원장 관측창 검사 (2026-07-26 오탐 수리)
#   초판은 "7일 내 발화 0회"를 원장 나이와 무관하게 판정했다 — 원장이 2분 전에 시작됐는데
#   조건부 훅 4종을 "발화 0회 = 계측 사망"으로 WARN 했다(실측 오탐).
#   그건 이 스크립트 자신이 위에서 선언한 "미측정 ≠ 0" 을 이 축에 적용하지 않은 것이다.
#   관측창이 요구 기간보다 짧으면 판정을 **보류**한다(WARN 아님, 사실 보고).
#──────────────────────────────────────────────────────────────────────────────
OLDEST=$(grep '"event_type":"hook_fired"' "$LEDGER" 2>/dev/null \
         | grep -oE '"timestamp":"[^"]+"' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}' \
         | sort | head -1)
WINDOW_H=0
if [ -n "$OLDEST" ]; then
  _o=$(date -d "${OLDEST/T/ }" +%s 2>/dev/null || echo 0)
  [ "$_o" -gt 0 ] && WINDOW_H=$(( ( $(date +%s) - _o ) / 3600 ))
fi
REQUIRED_H=$(( DAYS * 24 ))
if [ "$WINDOW_H" -lt "$REQUIRED_H" ]; then
  emit_line "hook-fire: 판정 보류 — 원장 관측창 ${WINDOW_H}h < 요구 ${REQUIRED_H}h (${DAYS}일). 조건부 훅은 아직 트리거를 못 만났을 수 있어 '발화 0'을 계측 사망으로 읽지 않는다"
  emit_line "   현재까지 발화 확인: $(printf '%s' "$FIRED" | tr '\n' ' ')"
  if [ "$MODE" != "--boot" ]; then
    echo ""
    echo "{\"test\":\"hook_fire_coverage\",\"pass\":0,\"fail\":0,\"total\":0,\"status\":\"window_too_short\"}"
  fi
  exit 0
fi

MISSING=""; PRESENT=0
for h in "${EXPECTED[@]}"; do
  if printf '%s\n' "$FIRED" | grep -qx -- "$h"; then PRESENT=$((PRESENT+1)); else MISSING="$MISSING$h "; fi
done

if [ -n "$MISSING" ]; then
  emit_line "WARN: 게이트급 훅 ${DAYS}일 내 발화 0회 — ${MISSING}(계측 사망 또는 등록 해제. events.jsonl ${N_ROWS}행·원장 ${LED_AGE_D}일)"
  emit_line "   확인: bash 02_Infrastructure/ops/hook_fire_coverage.sh  ·  원장 미커버 게이트: ${UNCOVERED}"
else
  emit_line "hook-fire: OK — 게이트급 ${PRESENT}/${#EXPECTED[@]} 훅 ${DAYS}일 내 발화 확인 (원장 ${N_ROWS}행). 미커버 게이트 4종은 별 경로: ${UNCOVERED}"
fi

if [ "$MODE" != "--boot" ]; then
  echo ""
  echo "발화 확인된 hook_name (${DAYS}일):"
  printf '%s\n' "$FIRED" | sed 's/^/  /'
  N_MISS=$(printf '%s' "$MISSING" | wc -w | tr -d ' ')
  echo ""
  echo "{\"test\":\"hook_fire_coverage\",\"pass\":$PRESENT,\"fail\":$N_MISS,\"total\":${#EXPECTED[@]}}"
fi
[ -z "$MISSING" ] || exit 1
