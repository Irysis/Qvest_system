#!/usr/bin/env bash
# resurrection_verify.sh — Resurrection Protocol 자동 검증
# 사용: bash 02_Infrastructure/ops/resurrection_verify.sh
#
# V1 Token / V2 Latency / V3 S0 state machine unit test / V6 Axiom block /
# V7 pipeline transition 1건 / structural syntax / settings.json ↔ files

set -uo pipefail
# ERR trap 제거 (개별 명령의 non-zero는 if/||로 처리, 전역 trap은 false-positive 양산)

ROOT=$(ls -d /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")
cd "$ROOT" || exit 1

PASS=0; FAIL=0
SMOKE_DIR=$(mktemp -d)
trap 'rm -rf "$SMOKE_DIR"' EXIT

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
hdr()  { echo; echo "━━ $1 ━━"; }

# ─── V1. Token 측정 ────────────────────────────────────────
hdr "V1 Token Savings"
CUR_TOTAL=$(bash 02_Infrastructure/ops/count_prompt_tokens.sh --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['total_tokens_approx'])")
BASE=48906
SAVE=$((BASE - CUR_TOTAL))
PCT=$(python3 -c "print(f'{($SAVE/$BASE)*100:.1f}')")
echo "  baseline=$BASE  current=$CUR_TOTAL  saved=$SAVE (-${PCT}%)"
[ "$CUR_TOTAL" -lt 42000 ] && ok "TOTAL < 42,000 tokens" || bad "TOTAL >= 42,000 tokens"

# agent init 6종 개별 합
INIT_TOTAL=$(bash 02_Infrastructure/ops/count_prompt_tokens.sh --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
names = ['qlead_init','scout_init','forge_init','judge_init','governor_init','risk_manager_init']
total = sum(int(f['tokens_approx']) for f in d['files'] if any(n in f['path'] for n in names))
print(total)")
echo "  agent init 6종 합: $INIT_TOTAL (baseline 19,410)"
[ "$INIT_TOTAL" -lt 10000 ] && ok "agent init < 10,000" || bad "agent init >= 10,000"

# ─── V2. Hook Latency ─────────────────────────────────────
hdr "V2 Hook Latency Profile"
dummy='{"tool_name":"Write","tool_input":{"file_path":"/tmp/dummy.txt","content":"x"}}'
bash_dummy='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
measure() {
  local name="$1" hook="$2" input="$3"
  local t0 t1 ms
  t0=$(date +%s%3N)
  echo "$input" | timeout 10 bash "$hook" > /dev/null 2>&1
  t1=$(date +%s%3N)
  ms=$((t1 - t0))
  echo "  $name: ${ms}ms"
  [ "$ms" -lt 2000 ] && ok "$name < 2000ms" || bad "$name >= 2000ms"
}
measure "safety_guard"              "02_Infrastructure/hooks/safety_guard.sh" "$dummy"
measure "axiom_enforcement_hook"    "02_Infrastructure/hooks/axiom_enforcement_hook.sh" "$dummy"
measure "forge_code_guard (Bash)"   "02_Infrastructure/hooks/forge_code_guard.sh" "$bash_dummy"
measure "pipeline_trigger"          "02_Infrastructure/hooks/pipeline_trigger.sh" "$dummy"
measure "s0_debate_enforcer (passthrough)" "02_Infrastructure/hooks/s0_debate_enforcer.sh" "$dummy"
measure "artifact_validator"        "02_Infrastructure/hooks/artifact_validator.sh" "$dummy"

# ─── V3. S0 State Machine 단위 테스트 ──────────────────────
hdr "V3 S0 Debate State Machine — unit tests"

run_sm() {
  local dtype="$1" hyp="$2" content="$3"
  local payload
  payload=$(python3 -c "import json; print(json.dumps({'tool_input': {'file_path': '$SMOKE_DIR/s0_debate_r1_role_$hyp.json', 'content': '''$content'''}}))")
  echo "$payload" | python3 02_Infrastructure/hooks/s0_enforcer/state_machine.py "$dtype" "$hyp" 2>/dev/null
}

# 3.1 R1 valid
rm -f /tmp/s0_debate_state_VSM_A.json
R=$(run_sm R1 VSM_A '{"role":"risk_manager","stance":"APPROVE","veto_flag":null,"supporting_arguments":["ok"],"critical_concerns":[]}')
echo "$R" | grep -q '"hook_decision": {}' && ok "R1 valid → passthrough" || bad "R1 valid 실패 ($R)"
STATE=$(python3 -c "import json; print(json.load(open('/tmp/s0_debate_state_VSM_A.json')).get('state',''))")
[ "$STATE" = "R1_IN_PROGRESS" ] && ok "state=R1_IN_PROGRESS" || bad "state=$STATE (expected R1_IN_PROGRESS)"

# 3.2 R1 bad schema (missing stance)
rm -f /tmp/s0_debate_state_VSM_B.json
R=$(run_sm R1 VSM_B '{"role":"governor","stance":"","veto_flag":null}')
echo "$R" | grep -q '"decision": "block"' && ok "R1 bad schema → block" || bad "R1 bad schema block 실패"

# 3.3 R1 wrong-state (VERDICT before R2 completes)
rm -f /tmp/s0_debate_state_VSM_C.json
# 강제 IDLE 상태에서 VERDICT 시도
R=$(run_sm VERDICT VSM_C '{"verdict":"APPROVE"}')
echo "$R" | grep -q '"decision": "block"' && ok "VERDICT from IDLE → block" || bad "VERDICT IDLE block 실패"

# 3.4 R2 before R1_COMPLETE → block
R=$(run_sm R2 VSM_D '{"role":"risk_manager","r1_stance":"APPROVE","stance_change":"UNCHANGED","new_stance":"APPROVE","veto_flag":null,"unresolved":[{"with":"quant","point":"x"}]}')
echo "$R" | grep -q '"decision": "block"' && ok "R2 pre-R1_COMPLETE → block" || bad "R2 pre-R1_COMPLETE block 실패"

# ─── V4. pipeline_trigger transition 1건 ──────────────────
hdr "V4 Pipeline transition (DONE_S0 → TODO_S1)"

MB="$SMOKE_DIR/qepm/mailbox"
mkdir -p "$MB/scout/inbox" "$MB/scout/processed" "$MB/forge/inbox" "$MB/forge/processed"
DONE="$MB/scout/inbox/DONE_S0_STR_VERIFY.json"
echo '{"strategy_id":"STR_VERIFY","hypothesis_id":"H_V"}' > "$DONE"

ACTUAL_MB="$ROOT/qepm/mailbox"
if [ -d "$ACTUAL_MB/scout/inbox" ]; then
  ACTUAL_DONE="$ACTUAL_MB/scout/inbox/DONE_S0_STR_RESVERIFY.json"
  ACTUAL_TODO="$ACTUAL_MB/forge/inbox/TODO_S1_STR_RESVERIFY.json"
  ACTUAL_PROC="$ACTUAL_MB/scout/processed/DONE_S0_STR_RESVERIFY.json"

  echo '{"strategy_id":"STR_RESVERIFY"}' > "$ACTUAL_DONE"
  payload=$(python3 -c "import json; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':'$ACTUAL_DONE','content':'x'}}))")
  echo "$payload" | bash 02_Infrastructure/hooks/pipeline_trigger.sh > /dev/null 2>&1

  if [ -f "$ACTUAL_TODO" ]; then
    ok "DONE_S0 → TODO_S1 copy 생성"
    rm -f "$ACTUAL_TODO"
  else
    bad "TODO_S1 생성 실패"
  fi
  if [ -f "$ACTUAL_PROC" ]; then
    ok "DONE archive (inbox → processed)"
    rm -f "$ACTUAL_PROC"
  else
    bad "DONE archive 실패"
    rm -f "$ACTUAL_DONE"
  fi
else
  echo "  [SKIP] $ACTUAL_MB 구조 없음"
fi

# ─── V6. Axiom / Safety 회귀 ──────────────────────────────
hdr "V6 Safety Block — 05_Production write attempt"
prod_attempt='{"tool_name":"Write","tool_input":{"file_path":"05_Production/test_write.R","content":"x"}}'
R=$(echo "$prod_attempt" | bash 02_Infrastructure/hooks/safety_guard.sh 2>/dev/null)
echo "$R" | grep -qE 'block|Production' && ok "05_Production write → block" || bad "05_Production block 실패 ($R)"

# ─── V7. ERR trap coverage ────────────────────────────────
hdr "V7 ERR trap coverage"
MISSING=0
for f in 02_Infrastructure/hooks/*.sh; do
  [ "$(basename $f)" = "resolve_project.sh" ] && continue
  has=$(grep -c "trap.*ERR" "$f" 2>/dev/null)
  [ "$has" = "0" ] && { MISSING=$((MISSING+1)); echo "  missing: $(basename $f)"; }
done
[ "$MISSING" -eq 0 ] && ok "ERR trap 100% coverage (19/19)" || bad "ERR trap missing: $MISSING"

# ─── V8. Structural syntax (모든 hook + python) ───────────
hdr "V8 Syntax — all hooks + python"
SYNTAX_FAIL=0
for f in 02_Infrastructure/hooks/*.sh 02_Infrastructure/hooks/s0_enforcer/*.sh; do
  bash -n "$f" 2>/dev/null || { SYNTAX_FAIL=$((SYNTAX_FAIL+1)); echo "  bash fail: $f"; }
done
for f in 02_Infrastructure/hooks/pipeline/*.py 02_Infrastructure/hooks/s0_enforcer/*.py; do
  python3 -c "import ast; ast.parse(open('$f').read())" 2>/dev/null || { SYNTAX_FAIL=$((SYNTAX_FAIL+1)); echo "  python fail: $f"; }
done
[ "$SYNTAX_FAIL" -eq 0 ] && ok "Syntax all PASS" || bad "Syntax failures: $SYNTAX_FAIL"

# ─── V9. settings.json JSON valid + hooks ↔ files ────────
hdr "V9 settings.json integrity"
python3 -c "import json; json.load(open('.claude/settings.json'))" 2>/dev/null \
  && ok "settings.json valid JSON" || bad "settings.json 파싱 실패"

MISS_HOOK=0
python3 -c "
import json, os
s = json.load(open('.claude/settings.json'))['hooks']
ROOT = '${ROOT}'
for ev, entries in s.items():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            # bash \"\$DIR/02_Infrastructure/hooks/xyz.sh\" 패턴에서 파일명만
            import re
            m = re.search(r'hooks/([A-Za-z0-9_/]+\.sh)', cmd)
            if m:
                path = os.path.join(ROOT, '02_Infrastructure/hooks/', m.group(1))
                if not os.path.exists(path):
                    print('  missing: ' + path)
" | tee /tmp/resurrection_missing_hooks.txt
if [ ! -s /tmp/resurrection_missing_hooks.txt ]; then
  ok "모든 등록 hook 파일 존재"
else
  bad "$(wc -l < /tmp/resurrection_missing_hooks.txt) 파일 누락"
fi

# ─── V10. SSOT 중복 재발생 확인 ───────────────────────────
hdr "V10 SSOT regression — AXIOM_INJECT block 없음"
INJECT=$(grep -l "AXIOM_INJECT_START" 02_Infrastructure/prompts/*.md 2>/dev/null | wc -l)
[ "$INJECT" -eq 0 ] && ok "AXIOM_INJECT 블록 0건" || bad "AXIOM_INJECT 블록 $INJECT건 (SSOT 파괴)"

# ─── 요약 ─────────────────────────────────────────────────
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PASS: $PASS     FAIL: $FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
