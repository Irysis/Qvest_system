#!/usr/bin/env bash
#==============================================================================
# test_hook_fire_coverage.sh — 발화0 감지 위반 주입 테스트 (2026-07-26 도훈 승인)
#
# 대상: 02_Infrastructure/ops/hook_fire_coverage.sh (events.jsonl 원장 소비면)
#   이 감시기의 존재 이유 = 이 저장소 실패부류의 지문이 "경고 0"이 아니라 **"발화 0"**이라는 것.
#   그러니 감시기 자신이 침묵하면 안 된다. 합성 원장을 주입해 각 판정 경로를 확인한다.
#
# 축:
#   T1 전 훅 발화 → OK
#   T2 일부 훅 발화 0 → WARN + 그 훅 이름이 출력에 등장
#   T3 ★관측창 가드 — 원장이 요구 기간보다 짧으면 WARN 아니라 **보류**
#      (초판이 2분 된 원장으로 "7일 발화 0"을 WARN 한 실측 오탐의 회귀 가드)
#   T4 원장 부재 → "미측정" 보고 (발화 0 으로 위장 금지)
#   T5 원장 0행 → 미측정
#   T6 회전 — 문턱 초과 시 최근 절반 유지 + .1 보존
#   T7 미커버 게이트 4종을 출력에 이름으로 노출(조용히 빼지 않음)
#
# 요약 규약: 마지막 줄 {"test":"hook_fire_coverage_guard","pass":N,"fail":N,"total":N}
#==============================================================================
set -u

_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK="$_SELF/../../02_Infrastructure/ops/hook_fire_coverage.sh"
[ -f "$CHK" ] || { echo "FATAL: checker 부재"; echo '{"test":"hook_fire_coverage_guard","pass":0,"fail":1,"total":1}'; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1  ($2)"; }

FX="$(mktemp -d)"
cleanup() { rm -rf "$FX"; }   # top-level on.exit 금지 규율의 bash 등가 — 명시 호출

# 합성 원장 생성: mk_ledger <파일> <최근발화offset일> <훅이름...>
#   ★관측창과 발화창은 **다른 축**이다. 초판 픽스처는 이벤트를 전부 10일 전에 두고 7일
#     창을 요구해, 관측창은 충족되는데 발화는 창 밖이라 T1 이 모순이었다(실측 FAIL).
#     현실 형태 = 원장은 오래 전부터 있고(anchor) 발화는 최근. 두 축을 분리해 만든다.
ANCHOR_DAYS=30
mk_ledger() {
  local f="$1" off="$2"; shift 2
  local a_ts r_ts
  a_ts="$(date -d "$ANCHOR_DAYS days ago" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null)"
  r_ts="$(date -d "$off days ago" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null)"
  # anchor: 관측창을 벌리는 오래된 1행 (기대 목록에 없는 훅명 — 발화 판정에 영향 없음)
  printf '{"timestamp":"%s","event_type":"hook_fired","hook_name":"_anchor.sh","decision":"fired","latency_ms":0}\n' \
    "$a_ts" > "$f"
  local h
  for h in "$@"; do
    printf '{"timestamp":"%s","event_type":"hook_fired","hook_name":"%s","decision":"fired","latency_ms":0}\n' \
      "$r_ts" "$h" >> "$f"
  done
}

run_chk() { # $1=ledger $2=days [$3=rotate_max]
  # ★env 경유 필수: `${3:+VAR=x} cmd` 는 확장 결과가 **할당 워드로 인식되지 않아**
  #   "VAR=x: command not found" 로 죽는다(bash 는 할당을 파싱 시점에 판별).
  #   이 세션 test_auto_commit_valve 에서 같은 함정을 이미 겪었는데 재발시켰다 —
  #   조건부 환경변수는 항상 env(1) 로 넘긴다.
  local -a envs=("QVEST_HFC_LEDGER=$1" "QVEST_HFC_DAYS=$2" "QVEST_HFC_EXPECTED=a.sh b.sh")
  [ -n "${3:-}" ] && envs+=("QVEST_HFC_ROTATE_MAX=$3")
  OUT=$(env "${envs[@]}" bash "$CHK" --boot 2>&1)
  return $?
}

echo "=== test_hook_fire_coverage (발화0 감지 위반 주입) ==="

# T1 전 훅 발화 (10일 전 원장 → 관측창 충족)
L="$FX/t1.jsonl"; mk_ledger "$L" 1 "a.sh" "b.sh"
if run_chk "$L" 7 && echo "$OUT" | grep -q "hook-fire: OK"; then ok "T1 전 훅 발화 → OK"
else bad "T1 전 훅 발화 → OK" "${OUT:0:140}"; fi

# T2 b.sh 만 발화 → a.sh 가 WARN 에 이름으로
L="$FX/t2.jsonl"; mk_ledger "$L" 1 "b.sh"
if ! run_chk "$L" 7 && echo "$OUT" | grep -q "발화 0회" && echo "$OUT" | grep -q "a.sh"; then
  ok "T2 일부 발화 0 → WARN + 훅 이름 노출"
else bad "T2 일부 발화 0 → WARN" "${OUT:0:140}"; fi

# T3 ★관측창 가드 — 원장이 오늘 것뿐이면 7일 판정 보류
L="$FX/t3.jsonl"
_t3ts="$(date +%Y-%m-%dT%H:%M:%S%z)"   # anchor 없음 = 관측창 0h (보류 경로 테스트)
printf '{"timestamp":"%s","event_type":"hook_fired","hook_name":"b.sh","decision":"fired","latency_ms":0}\n' "$_t3ts" > "$L"
if run_chk "$L" 7 && echo "$OUT" | grep -q "판정 보류"; then
  ok "T3 ★관측창 < 요구기간 → 보류(WARN 아님)"
else bad "T3 ★관측창 가드" "WARN 으로 오탐: ${OUT:0:140}"; fi

# T3b 같은 원장에 DAYS=0 이면 관측창 충족 → 실판정(WARN)로 전환돼야 함
if ! run_chk "$L" 0 && echo "$OUT" | grep -q "발화 0회"; then
  ok "T3b 관측창 충족 시 실판정으로 전환"
else bad "T3b 실판정 전환" "${OUT:0:140}"; fi

# T4 원장 부재 → 미측정
if ! run_chk "$FX/none.jsonl" 7 && echo "$OUT" | grep -q "미측정"; then
  ok "T4 원장 부재 → 미측정(발화 0 위장 금지)"
else bad "T4 원장 부재" "${OUT:0:140}"; fi

# T5 원장 0행 → 미측정
L="$FX/t5.jsonl"; : > "$L"
if ! run_chk "$L" 7 && echo "$OUT" | grep -q "미측정"; then ok "T5 원장 0행 → 미측정"
else bad "T5 원장 0행" "${OUT:0:140}"; fi

# T6 회전 — 30행/문턱 10 → 최근 5행 + .1 보존
L="$FX/t6.jsonl"; rm -f "$L.1"
: > "$L"
for i in $(seq 1 30); do
  printf '{"timestamp":"%s","event_type":"hook_fired","hook_name":"a.sh","decision":"fired","latency_ms":0}\n' \
    "$(date -d '10 days ago' +%Y-%m-%dT%H:%M:%S%z)" >> "$L"
done
run_chk "$L" 7 10 >/dev/null 2>&1 || true
N_AFTER=$(grep -c . "$L" 2>/dev/null || echo 0)
N_BAK=$(grep -c . "$L.1" 2>/dev/null || echo 0)
if [ "$N_AFTER" = "5" ] && [ "$N_BAK" = "30" ]; then ok "T6 회전 30→5행 + .1 보존 30행"
else bad "T6 회전" "after=$N_AFTER bak=$N_BAK (기대 5/30)"; fi

# T7 미커버 게이트 4종 이름 노출
L="$FX/t7.jsonl"; mk_ledger "$L" 1 "a.sh" "b.sh"
run_chk "$L" 7 >/dev/null 2>&1 || true
if echo "$OUT" | grep -q "discovery_graduation_gate.sh" && echo "$OUT" | grep -q "legacy_write_block.sh"; then
  ok "T7 미커버 게이트 이름 노출(조용히 빼지 않음)"
else bad "T7 미커버 게이트 노출" "${OUT:0:140}"; fi

# T8 ★writer parity — 외부 CLI(emit_event.sh)와 인라인(qvest_emit_event)이 **같은 스키마**를
#    내야 한다. 갈라지면 같은 원장에 두 모양이 섞여 소비자(hook_fire_coverage·qvest_observe·
#    wt_timeline)가 한쪽을 조용히 놓친다 — 이 세션이 반복 확인한 '필드명 불일치 = 조용한 빈 값'.
_SRC="$_SELF/../.."
_PA="$FX/pa"; _PB="$FX/pb"
mkdir -p "$_PA/qepm/observability" "$_PB/qepm/observability"
env CLAUDE_PROJECT_DIR="$_PA" bash "$_SRC/02_Infrastructure/observability/emit_event.sh" \
  "parity" "h.sh" "block" "WT-1" "alpha" "42" 'C:\a\b"c".json' "ctx" >/dev/null 2>&1
cat > "$FX/pb.sh" <<'PBEOF'
QVEST_PARSE_TRAP=caller QVEST_PARSE_RESOLVE_ONLY=1
source "$SRC/02_Infrastructure/hooks/_shared_parse.sh"
qvest_emit_event "parity" "h.sh" "block" "WT-1" "alpha" "42" 'C:\a\b"c".json' "ctx"
PBEOF
env SRC="$_SRC" CLAUDE_PROJECT_DIR="$_PB" bash "$FX/pb.sh" >/dev/null 2>&1
_LA=$(tail -1 "$_PA/qepm/observability/events.jsonl" 2>/dev/null | sed 's/"timestamp":"[^"]*"/"timestamp":"T"/')
_LB=$(tail -1 "$_PB/qepm/observability/events.jsonl" 2>/dev/null | sed 's/"timestamp":"[^"]*"/"timestamp":"T"/')
if [ -n "$_LA" ] && [ "$_LA" = "$_LB" ]; then ok "T8 ★writer parity (외부 CLI ↔ 인라인 동일 스키마)"
else bad "T8 ★writer parity" "A=${_LA:0:80} / B=${_LB:0:80}"; fi

cleanup
echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "{\"test\":\"hook_fire_coverage_guard\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ] || exit 1
