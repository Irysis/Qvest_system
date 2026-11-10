#!/usr/bin/env bash
#==============================================================================
# test_axiom_inject_tau_d.sh — 주입 훅의 정보 경계(τ_D) 대상 스폰 처리 (2026-11-10 전수점검)
#
# 지키는 것:
#   Superfan(판단 · 철학 · 구성요소)은 2022-12-31 뒤 성과 수치를 읽지 않는 에이전트인데, 에이전트 스폰 훅
#   axiom_context_inject.sh 가 스폰마다 전 기간 성과 줄(최고 전략의 PORT_t · SR · CAGR · MDD · OOS 와 최근 교훈의
#   등급 · SR)을 넣고 있었다. 수리 뒤에는 그 스폰에 변동부(성과 · 교훈 · dead)를 넣지 않는다.
#
# 축:
#   A [양성 대조] 일반 스폰에는 성과 줄이 들어간다(검사가 '빠졌다'와 '원래 없다'를 구분할 수 있어야 한다)
#   B Superfan 3종 — 성과 줄 0 · 정보 경계 표식 줄 있음 · 고정부(공리 · 고정 축)는 그대로
#   C 범용 에이전트를 Superfan 으로 띄우는 경우(프롬프트 앞부분에 이름) — 같은 처리
#   D 청정 레인 표식이 함께 있으면 청정 레인 줄이 우선
#   E 계측 파일에 tau_d_agent 가 남는다
#   F [위반 주입] 판정 줄을 무력화한 사본은 B 를 통과하지 못한다
#
# 격리: 훅 사본 + 고정물(픽스처)만 든 임시 루트에서 돈다. 운영 캐시 · 계측 파일을 건드리지 않는다.
#==============================================================================
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
HOOK="$ROOT/02_Infrastructure/hooks/axiom_context_inject.sh"
PARSE="$ROOT/02_Infrastructure/hooks/_shared_parse.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS  $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL  $1 — $2"; }
finish() {
  echo "=== 결과: PASS=$PASS FAIL=$FAIL ==="
  printf '{"test":"axiom_inject_tau_d","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
  [ "$FAIL" = "0" ] || exit 1
  exit 0
}
[ -f "$HOOK" ] && [ -f "$PARSE" ] || { ng "0 훅 원본" "없음: $HOOK"; finish; }

# 해석기(훅과 같은 규칙)
QVEST_PARSE_TRAP=caller; QVEST_PARSE_RESOLVE_ONLY=1
# shellcheck source=/dev/null
source "$PARSE"; unset QVEST_PARSE_RESOLVE_ONLY QVEST_PARSE_TRAP
PY="${QVEST_PY_BIN:-python}"

T="$(mktemp -d 2>/dev/null || echo "/tmp/axinj_$$")"; mkdir -p "$T"
command -v cygpath >/dev/null 2>&1 && T="$(cygpath -m "$T")"
trap 'rm -rf "$T" 2>/dev/null' EXIT
SB="$T/sb"; H="$T/h"
mkdir -p "$SB/qepm/memory/axioms/active" "$SB/.cache" "$H"
cp "$HOOK" "$PARSE" "$H/"
# 고정물: 공리 1건 + 성과 문맥(식별 가능한 가짜 수치) + 헌법 사본
cat > "$SB/qepm/memory/axioms/active/AX-900.json" <<'JSON'
{"axiom_id":"AX-900","grade":"IMMUTABLE","statement":"고정물 공리 문장 — 주입 고정부 확인용"}
JSON
cat > "$SB/.cache/positive_context.json" <<'JSON'
{"generated_at":"2026-11-10T00:00:00+00:00","positive_block":"- STR_FIXTURE_1 B s50.0 PORT_t 9.99 SR 8.88 CAGR 77% MDD 66% OOS 0.55 | 고정물 전략",
 "dist_block":"","recent_block":"- L-FIX-1 F | 고정물 충실구현: 등급 F. 논문기준 SR 7.77 vs 15bps SR -6.66",
 "dead_line":"[dead configs 3 — 고정물]","n_dead":3,"n_fired":0}
JSON
[ -f "$ROOT/CLAUDE.md" ] && cp "$ROOT/CLAUDE.md" "$SB/CLAUDE.md"

# render <hook> <payload-json> [env…] → additionalContext 를 표준출력으로
render() {
  local hook="$1" payload="$2"; shift 2
  printf '%s' "$payload" | env CLAUDE_PROJECT_DIR="$SB" QM_ROOT="$SB" "$@" bash "$hook" 2>/dev/null \
    | "$PY" -X utf8 -c 'import sys,json
try:
    d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace"))
    sys.stdout.buffer.write((d.get("hookSpecificOutput",{}).get("additionalContext","") or "").encode("utf-8"))
except Exception as e:
    sys.stdout.write("RENDER_ERR "+type(e).__name__)'
}
has()   { printf '%s' "$1" | grep -qF -- "$2"; }
PERF1="PORT_t 9.99"; PERF2="SR 7.77"; MARK="정보 경계 대상 스폰"; FIXED="AX-900"

echo "== A 양성 대조: 일반 스폰 =="
OUT_A="$(render "$H/axiom_context_inject.sh" '{"tool_input":{"subagent_type":"general-purpose","prompt":"코드 위치 조사"}}')"
has "$OUT_A" "$PERF1" && ok "A1 일반 스폰에는 최고 전략 성과 줄이 있다" || ng "A1 일반 스폰 성과 줄" "없음(검사가 구분력을 잃음): ${OUT_A:0:120}"
has "$OUT_A" "$PERF2" && ok "A2 일반 스폰에는 최근 교훈 줄이 있다" || ng "A2 일반 스폰 교훈 줄" "없음"
has "$OUT_A" "$FIXED" && ok "A3 고정부(공리)가 있다" || ng "A3 고정부" "없음"

echo "== B Superfan 3종 =="
for ag in superfan superfan-philosophy superfan-component; do
  OUT="$(render "$H/axiom_context_inject.sh" "{\"tool_input\":{\"subagent_type\":\"$ag\",\"prompt\":\"트리거 T1\"}}")"
  if has "$OUT" "$PERF1" || has "$OUT" "$PERF2"; then ng "B $ag 성과 줄 제외" "성과 수치가 들어갔다"; else ok "B $ag — 성과 · 교훈 수치 0"; fi
  has "$OUT" "$MARK" && ok "B $ag — 정보 경계 표식 줄" || ng "B $ag 표식 줄" "없음: ${OUT:0:120}"
  has "$OUT" "$FIXED" && ok "B $ag — 고정부 유지" || ng "B $ag 고정부" "사라짐"
done

echo "== C 범용 에이전트를 Superfan 으로 =="
OUT_C="$(render "$H/axiom_context_inject.sh" '{"tool_input":{"subagent_type":"general-purpose","description":"철학 리뷰","prompt":".claude/agents/superfan-philosophy.md 정의 파일을 먼저 읽고 따르라. 트리거 P1"}}')"
if has "$OUT_C" "$PERF1" || has "$OUT_C" "$PERF2"; then ng "C 프롬프트로 띄운 Superfan" "성과 수치가 들어갔다"; else ok "C 프롬프트 앞부분의 이름으로도 잡는다"; fi

echo "== D 청정 레인 우선 =="
OUT_D="$(render "$H/axiom_context_inject.sh" '{"tool_input":{"subagent_type":"superfan","prompt":"x"}}' QVEST_CLEAN_LANE=1)"
has "$OUT_D" "청정 레인" && ! has "$OUT_D" "$PERF1" && ok "D 청정 레인 줄이 우선 · 성과 0" || ng "D 청정 레인 우선" "${OUT_D:0:120}"

echo "== E 계측 =="
render "$H/axiom_context_inject.sh" '{"tool_input":{"subagent_type":"superfan-philosophy","prompt":"P2"}}' >/dev/null
"$PY" -X utf8 -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); sys.exit(0 if (d.get("tau_d_agent") is True and d.get("pc_status")=="tau_d_agent_excluded") else 1)' "$SB/.cache/axiom_inject_last.json" \
  && ok "E 계측 파일에 tau_d_agent=true · pc_status=tau_d_agent_excluded" || ng "E 계측" "표식 없음"

echo "== F 위반 주입 =="
MUT="$H/axiom_context_inject_mut.sh"
"$PY" -X utf8 -c 'import sys,io
s=io.open(sys.argv[1],encoding="utf-8",newline="").read()
old="TAUD = os.environ.get(\x27QVEST_INJECT_TAUD\x27, \x27\x27) == \x27tau_d\x27"
n=s.count(old)
io.open(sys.argv[2],"w",encoding="utf-8",newline="").write(s.replace(old,"TAUD = False"))
sys.exit(0 if n==1 else 1)' "$H/axiom_context_inject.sh" "$MUT" && ok "F0 돌연변이 대상 줄이 정확히 한 곳 · 치환됨" || ng "F0 돌연변이 치환" "대상 줄 수가 1이 아님"
OUT_F="$(render "$MUT" '{"tool_input":{"subagent_type":"superfan-philosophy","prompt":"P1"}}')"
has "$OUT_F" "$PERF1" && ok "F1 판정 줄이 없으면 Superfan 에 성과 줄이 들어간다 — B 가 이것을 잡는다" || ng "F1 돌연변이 검출" "돌연변이에서도 성과 줄이 없다(검사가 병을 못 본다)"

finish
