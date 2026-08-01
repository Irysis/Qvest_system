#!/usr/bin/env bash
#==============================================================================
# test_ast_spec_gate.sh — AST v1.1 스펙 기계 게이트 위반 주입 테스트
#------------------------------------------------------------------------------
# 신설 2026-08-02. 대상 = 02_Infrastructure/hooks/ast_spec_gate.sh (SOT §7 ①~⑤)
#
# ★왜 필요한가: 이 게이트는 2026-07-25 등재 후 부팅 hook-fire 발화 목록에 한 번도
#   오르지 않았다. 조건부 훅이라 "트리거 미도달"일 수도, "차단 실효 사망"일 수도
#   있는데 겉보기가 같다. 게이트 전용 위반 주입 테스트가 부재해 판별 수단이 없었다.
#   → 일부러 틀린 입력을 주입해 실제로 block 을 발행하는지 실증한다.
#   양성 대조(정상 스펙은 통과)도 함께 시험해 오탐 게이트가 아님을 보인다.
#
# 실행: bash 08_Tests/hooks/test_ast_spec_gate.sh
#==============================================================================
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)}}"
ROOT="${ROOT//\\//}"
HOOK="$ROOT/02_Infrastructure/hooks/ast_spec_gate.sh"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }

[ -x "$HOOK" ] || { echo "훅 부재/비실행: $HOOK"; exit 1; }

# payload 조립: Write 툴 PreToolUse 입력. content 는 JSON 문자열로 삽입.
mk_payload() {
  local spec_json="$1"
  "${QVEST_PY:-python}" - "$spec_json" <<'PY'
import json, sys
spec = sys.argv[1]
payload = {
    "session_id": "test_ast_spec_gate",
    "tool_name": "Write",
    "tool_input": {
        "file_path": "qepm/mailbox/worktask/WT-D20260802_999/alpha_package.json",
        "content": spec,
    },
}
sys.stdout.write(json.dumps(payload, ensure_ascii=False))
PY
}

run_hook() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }
is_block() { printf '%s' "$1" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; }

# ── 정상 v1.1 스펙 (양성 대조 기준선) ────────────────────────────────────────
# ★ falsification 은 자유 서술이 아니라 **field_dictionary 내 필드 지목**이어야 한다
#   (SOT par.1: "field_dictionary 내 필드로 확인 가능한 부수 관측만, 성과 동어반복 금지").
#   초안에서 자연어 문장을 넣었더니 게이트가 정확히 반려했다 — 게이트가 살아있다는 실증이자
#   본 게이트의 존재 이유(느슨한 반증 조건의 기계적 차단) 그 자체다.
#   2단계 반려: falsification 을 고치자 이번엔 pit.sig_date 부재로 fail-closed 됐다.
#   PIT 기준시점 없이는 정적검증(리프 avail_ts 상향 전파)이 성립하지 않으므로 옳은 차단이다.
GOOD='{"spec_version":"ast_v1.1","strategy_id":"TEST_AST_GATE",
 "pit":{"sig_date":"2026-06-30","decision_ts":"2026-07-01"},
 "hypothesis":{"mechanism":{"agent":"국내 기관투자자","friction":"분기 재무 공시 지연에 따른 정보 반영 시차","path":"수출 실적 선공표 -> 실적 서프라이즈 사전 반영"},
 "falsification":[{"field":"V02_EP","expectation":"밸류 축 통제 후에도 잔존 신호가 있어야 한다"}],
 "regime_scope":{"holds_in":["NORMAL"],"weakens_or_reverses_in":["CRISIS"]}},
 "factor_definition":{"ast":{"op":"CS_RANK","args":[{"op":"TS_DELTA","args":[{"leaf":"FIELD","name":"V01_BM"},{"const":3}]}]}},
 "combination_rule":"Z_Score_Aligned"}'

echo "=== test_ast_spec_gate (위반 주입 + 양성 대조) ==="
echo "--- A. 양성 대조: 정상 스펙은 통과해야 한다 ---"
out=$(run_hook "$(mk_payload "$GOOD")")
if is_block "$out"; then bad "A1 정상 v1.1 스펙 통과" "block 발행됨: $out"; else ok "A1 정상 v1.1 스펙 통과"; fi

echo "--- B. 위반 주입: 게이트가 실제로 block 을 발행하나 ---"

# B1: mechanism.agent 공백 (SOT §7 ①)
B1=${GOOD/\"agent\":\"국내 기관투자자\"/\"agent\":\"\"}
out=$(run_hook "$(mk_payload "$B1")")
if is_block "$out"; then ok "B1 mechanism.agent 공백 -> block"; else bad "B1 mechanism.agent 공백 -> block" "통과됨: $out"; fi

# B2: mechanism.friction 키 자체 제거
B2=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); d["hypothesis"]["mechanism"].pop("friction",None)
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$B2")")
if is_block "$out"; then ok "B2 mechanism.friction 누락 -> block"; else bad "B2 mechanism.friction 누락 -> block" "통과됨: $out"; fi

# B3: regime_scope.weakens_or_reverses_in 빈 배열 (SOT §1 명문 금지)
B3=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); d["hypothesis"]["regime_scope"]["weakens_or_reverses_in"]=[]
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$B3")")
if is_block "$out"; then ok "B3 regime_scope 빈 배열 -> block"; else bad "B3 regime_scope 빈 배열 -> block" "통과됨: $out"; fi

# B4: falsification 빈 배열
B4=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); d["hypothesis"]["falsification"]=[]
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$B4")")
if is_block "$out"; then ok "B4 falsification 빈 배열 -> block"; else bad "B4 falsification 빈 배열 -> block" "통과됨: $out"; fi

# B5: 𝒪 밖 연산자 (LEAD = 표현공간에서 의도적으로 제거된 미래참조 연산자)
B5=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
d["factor_definition"]["ast"]={"op":"LEAD","args":[{"leaf":"FIELD","name":"V01_PER"},{"const":1}]}
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$B5")")
if is_block "$out"; then ok "B5 ★LEAD(𝒪 밖·미래참조) -> block"; else bad "B5 ★LEAD(𝒪 밖·미래참조) -> block" "통과됨: $out"; fi

echo "--- C. 조기-exit / 구식 호환 (오탐 아님을 실증) ---"

# C1: alpha_package 무관 payload → python 스폰 0, 빈 응답
out=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/unrelated.txt","content":"hello"}}' | bash "$HOOK" 2>/dev/null)
if is_block "$out"; then bad "C1 무관 payload 조기-exit" "block 발행됨"; else ok "C1 무관 payload 조기-exit(무해)"; fi

# C2: 구식 패키지(spec_version 부재) → 통과 (SOT §7 ④ advisory)
C2=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); d.pop("spec_version",None); d.pop("hypothesis",None); d.pop("factor_definition",None)
d["factor_specs"]=[{"name":"legacy_factor"}]
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$C2")")
if is_block "$out"; then bad "C2 구식 패키지 하위호환 통과" "block 발행됨: $out"; else ok "C2 구식 패키지 하위호환 통과(advisory)"; fi

echo "--- D. schema 정본 표현이 게이트를 통과하는가 (ALB-005/006 수리) ---"
# D1: schema 정본 위치 factors[].ast 만 (top-level ast 없음)
D1=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
ast=d.pop("factor_definition")["ast"]
d["factors"]=[{"name":"F1","ast":ast}]
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$D1")")
if is_block "$out"; then bad "D1 factors[].ast (schema 정본 위치) 통과" "block: $out"; else ok "D1 ★factors[].ast (schema 정본 위치) 통과 — ALB-006"; fi

# D2: 다중 팩터 중 뒤쪽에 𝒪 밖 연산자 → 전 팩터 검사되어야 block
D2=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
ast=d.pop("factor_definition")["ast"]
bad_ast={"op":"LEAD","args":[{"leaf":"FIELD","name":"V01_BM"},{"const":1}]}
d["factors"]=[{"name":"F1","ast":ast},{"name":"F2","ast":bad_ast}]
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$D2")")
if is_block "$out"; then ok "D2 ★다중 팩터 중 2번째의 𝒪 밖 연산자 검거 — 첫 팩터만 보고 통과시키지 않음"; else bad "D2 다중 팩터 전량 검사" "통과됨: $out"; fi

# D3: 구 schema 형(falsification 문자열) → 정본 타입 확정으로 block 유지
D3=$("${QVEST_PY:-python}" - "$GOOD" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
d["hypothesis"]["falsification"]="수출비중 하위 그룹에서 신호가 소멸"
sys.stdout.write(json.dumps(d,ensure_ascii=False))
PY
)
out=$(run_hook "$(mk_payload "$D3")")
if is_block "$out"; then ok "D3 자유 서술 문자열 falsification → block (정본=객체배열)"; else bad "D3 문자열 falsification 반려" "통과됨: $out"; fi

# D4: schema 파일 자체가 정본 타입으로 개정됐는지 (문서-구현 동기)
SCHEMA_T=$("${QVEST_PY:-python}" -c "
import json,io,sys
d=json.load(io.open(r'$ROOT/02_Infrastructure/worktask/schema.json',encoding='utf-8'))
print(d['definitions']['ast_hypothesis']['properties']['falsification']['type'])
" 2>/dev/null)
if [ "$SCHEMA_T" = "array" ]; then ok "D4 schema.json falsification = array (게이트와 동일 정본)"; else bad "D4 schema-게이트 타입 동기" "schema=$SCHEMA_T"; fi
SCHEMA_PIT=$("${QVEST_PY:-python}" -c "
import json,io
d=json.load(io.open(r'$ROOT/02_Infrastructure/worktask/schema.json',encoding='utf-8'))
s=json.dumps(d,ensure_ascii=False)
print('yes' if '\"pit\"' in s and 'sig_date' in s else 'no')
" 2>/dev/null)
if [ "$SCHEMA_PIT" = "yes" ]; then ok "D5 schema.json 에 pit.sig_date 정의 존재 (게이트 요구와 일치)"; else bad "D5 schema pit 정의" "got $SCHEMA_PIT"; fi

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
printf '{"test":"ast_spec_gate","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
