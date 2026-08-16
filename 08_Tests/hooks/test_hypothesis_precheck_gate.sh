#!/usr/bin/env bash
# test_hypothesis_precheck_gate — 착수 전 조회절 게이트 위반 주입 검사 (2026-08-16 신설)
#
# ★양방향: 차단해야 할 것을 차단하는가(A) ∧ 통과시켜야 할 것을 통과시키는가(B).
#   B 축이 없으면 "전부 block" 이라는 무용 게이트도 A 를 통과한다.
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-${QM_ROOT:-$PWD}}"
HOOK="$ROOT/02_Infrastructure/hooks/hypothesis_precheck_gate.sh"
PY="${QVEST_PY:-python}"
PASS=0; FAIL=0
note(){ printf '  %-56s %s\n' "$1" "$2"; }
ok(){ PASS=$((PASS+1)); note "$1" "OK"; }
bad(){ FAIL=$((FAIL+1)); note "$1" "★FAIL — $2"; }

# $1=라벨 $2=기대(block|pass) $3=file_path $4=content(JSON 문자열)
run(){
  local label="$1" expect="$2" fp="$3" body="$4"
  local payload
  payload=$(FP="$fp" BODY="$body" "$PY" -c '
import json,os
print(json.dumps({"tool_name":"Write","tool_input":{"file_path":os.environ["FP"],"content":os.environ["BODY"]}}))
')
  local outp got
  outp=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)
  got=$(printf '%s' "$outp" | "$PY" -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print("BADJSON"); raise SystemExit
print("block" if d.get("decision")=="block" else "pass")
')
  [ "$got" = "$expect" ] && ok "$label" || bad "$label" "기대 $expect 실제 $got"
}

echo "=== test_hypothesis_precheck_gate ==="
[ -f "$HOOK" ] && ok "훅 파일 존재" || { bad "훅 파일 존재" "$HOOK 부재"; echo "=== 0 PASS / 1 FAIL ==="; exit 1; }
bash -n "$HOOK" && ok "bash 문법" || bad "bash 문법" "구문 오류"

WT="qepm/mailbox/worktask/WT-TEST_001/alpha_hypothesis.json"

# ── A축: 차단해야 할 것 ──────────────────────────────────────────────────────
run "A1 prechecks 절 자체가 없음"            block "$WT" '{"wt_id":"X","verdict":"designed"}'
run "A2 hypothesis_index_hits 부재"          block "$WT" '{"prechecks":{"note":"봤음"}}'
run "A3 hits 가 배열이 아님"                 block "$WT" '{"prechecks":{"hypothesis_index_hits":"봤음"}}'
run "A4 hits 빈 배열 + empty_reason 없음"    block "$WT" '{"prechecks":{"hypothesis_index_hits":[]}}'
run "A5 hits 원소가 빈 dict"                  block "$WT" '{"prechecks":{"hypothesis_index_hits":[{}]}}'
run "A6 hits 원소가 빈 문자열"                block "$WT" '{"prechecks":{"hypothesis_index_hits":["  "]}}'

# ── B축: 통과시켜야 할 것 (★이 축이 없으면 '전부 block' 무용 게이트도 A 를 통과한다) ──
run "B1 정상 조회절(ref 형)"                  pass "$WT" '{"prechecks":{"hypothesis_index_hits":[{"ref":"L-AR-1","verdict":"FAIL","bearing":"x"}]}}'
# ★형상 다양성 — 실측 분포(id 22 · 비-dict 20 · ref 7)를 그대로 축으로 세운다.
#   초판이 ref 를 박제해 아래 두 형태를 오차단했다(실산출물 12/13).
run "B1b 조회절(id 형 — 실측 최빈)"           pass "$WT" '{"prechecks":{"hypothesis_index_hits":[{"id":"DIST-QPM-003","verdict":"DISTILLED_NEG"}]}}'
run "B1c 조회절(순수 문자열 형)"              pass "$WT" '{"prechecks":{"hypothesis_index_hits":["L-AR-20260808_120900"]}}'
run "B2 조회 0건 + empty_reason 선언"         pass "$WT" '{"prechecks":{"hypothesis_index_hits":[],"empty_reason":"신규 family — 인덱스 선례 없음"}}'
run "B3 무관 파일(alpha_package)"             pass "qepm/mailbox/worktask/WT-TEST_001/alpha_package.json" '{"alpha_hypothesis":"ref only"}'
run "B4 JSON 아닌 content"                    pass "$WT" '# alpha_hypothesis 초안 메모'

# B5: Edit 경로(content 없음) — 판정 불가라 통과 + advisory
EDIT_PAYLOAD=$(FP="$WT" "$PY" -c '
import json,os
print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":os.environ["FP"],"old_string":"a","new_string":"b"}}))
')
GOT5=$(printf '%s' "$EDIT_PAYLOAD" | bash "$HOOK" 2>/dev/null | "$PY" -c '
import json,sys
d=json.load(sys.stdin)
print("block" if d.get("decision")=="block" else "pass")
')
[ "$GOT5" = "pass" ] && ok "B5 Edit 경로는 통과(+advisory)" || bad "B5 Edit 경로는 통과" "실제 $GOT5"

# ── C축: 조기-exit (무관 payload 에 python 스폰 0) ──────────────────────────
GOT6=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"README.md","content":"hello"}}' \
        | bash "$HOOK" 2>/dev/null)
[ "$GOT6" = "{}" ] && ok "C1 무관 payload 조기-exit ({} 반환)" || bad "C1 무관 payload 조기-exit" "실제 $GOT6"

echo
echo "=== $PASS PASS / $FAIL FAIL ==="
[ "$FAIL" -eq 0 ]
