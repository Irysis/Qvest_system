#!/usr/bin/env bash
#==============================================================================
# test_token_reduction.sh — Block A~H 토큰 절감 검증
#
# 실행 조건: .cache/token_reduction_test_pending.flag 존재 시 qvest.md가 호출
# 완료 후: 플래그를 .cache/token_reduction_test_done_{TIMESTAMP}.log로 rename
#
# 사용자 요청 (2026-04-19 Session 68 Day 2 종료 시): 다음 세션 첫 /qvest에서
# 자동으로 토큰 절감 인프라 검증 실행.
#==============================================================================

set -u
DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
if [ -z "$DIR" ]; then echo "ERROR: project dir not found"; exit 1; fi
cd "$DIR"

TS=$(date +%Y%m%d_%H%M%S)
LOG="/tmp/token_reduction_test_${TS}.log"
PASS=0
FAIL=0
WARN=0

pass() { echo "✅ PASS | $1" | tee -a "$LOG"; PASS=$((PASS+1)); }
fail() { echo "❌ FAIL | $1" | tee -a "$LOG"; FAIL=$((FAIL+1)); }
warn() { echo "⚠️  WARN | $1" | tee -a "$LOG"; WARN=$((WARN+1)); }

echo "==============================================================================" | tee "$LOG"
echo "Block A~H 토큰 절감 검증 — $(date)" | tee -a "$LOG"
echo "==============================================================================" | tee -a "$LOG"

# ─── Block A: 모델 라우팅 ───────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Block A] 모델 라우팅 검증" | tee -a "$LOG"
for f in .claude/commands/scout.md .claude/commands/forge.md .claude/commands/governor.md; do
  if grep -q "^model: sonnet" "$f" 2>/dev/null; then
    pass "$f frontmatter model: sonnet"
  else
    fail "$f frontmatter에 'model: sonnet' 없음"
  fi
done
if grep -q 'model="sonnet"\|model: "sonnet"' .claude/commands/launch-team.md; then
  pass "launch-team.md Agent() 호출에 model parameter 명시"
else
  fail "launch-team.md Agent() 호출에 model 미명시"
fi
if grep -q 'model: "sonnet"\|model: "opus"' .claude/skills/s0-debate/SKILL.md; then
  pass "s0-debate/SKILL.md Agent 스폰에 model parameter 명시"
else
  fail "s0-debate/SKILL.md Agent 스폰에 model 미명시"
fi

# ─── Block B: 컨텍스트 분할 ─────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Block B] 컨텍스트 분할 검증" | tee -a "$LOG"
MEM_DIR="/home/quant/.claude/projects/-mnt-c-Users-99922-OneDrive-------Quant-Module-Moltbot/memory"
[ -f "$MEM_DIR/methodology_active.md" ] && pass "methodology_active.md 존재" || fail "methodology_active.md 없음"
[ -f "$MEM_DIR/methodology_archive.md" ] && pass "methodology_archive.md 존재" || fail "methodology_archive.md 없음"
[ -f "$MEM_DIR/feedback_INDEX.md" ] && pass "feedback_INDEX.md 존재" || fail "feedback_INDEX.md 없음"
# MEMORY.md 인덱스에 active 항목 포함 여부
if grep -q "methodology_active.md" "$MEM_DIR/MEMORY.md"; then
  pass "MEMORY.md 인덱스에 methodology_active.md 반영"
else
  fail "MEMORY.md 인덱스 재구성 미반영"
fi
# 사이즈 확인 (active는 methodology_memory.md보다 작아야 함)
if [ -f "$MEM_DIR/methodology_active.md" ] && [ -f "$MEM_DIR/methodology_memory.md" ]; then
  ASZ=$(stat -c%s "$MEM_DIR/methodology_active.md")
  MSZ=$(stat -c%s "$MEM_DIR/methodology_memory.md")
  if [ "$ASZ" -lt "$MSZ" ]; then
    pass "methodology_active.md($((ASZ/1024))K) < methodology_memory.md($((MSZ/1024))K)"
  else
    warn "active($((ASZ/1024))K) ≥ memory($((MSZ/1024))K) — 분할 확인 필요"
  fi
fi

# ─── Block C: Hook 최적화 + Codex 축소 ──────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Block C] Hook 최적화 + Codex 축소 검증" | tee -a "$LOG"
[ -f "02_Infrastructure/hooks/_shared_parse.sh" ] && pass "_shared_parse.sh 신설됨" || fail "_shared_parse.sh 없음"
[ -f "02_Infrastructure/R/hook_batch_runner.R" ] && pass "hook_batch_runner.R 신설됨" || fail "hook_batch_runner.R 없음"
# _shared_parse.sh source 적용 확인
for h in safety_guard.sh axiom_enforcement_hook.sh unified_agent_guard.sh forge_code_guard.sh; do
  if grep -q "_shared_parse.sh" "02_Infrastructure/hooks/$h" 2>/dev/null; then
    pass "$h _shared_parse.sh source 적용"
  else
    fail "$h _shared_parse.sh 미적용"
  fi
done
# Codex 결과 jq 축약 확인
if grep -q "jq -c" 02_Infrastructure/tools/debate_helpers/run_codex_critic.sh; then
  pass "run_codex_critic.sh jq 요약 적용"
else
  fail "run_codex_critic.sh jq 요약 미적용"
fi
if grep -q "jq -c" 02_Infrastructure/tools/debate_helpers/run_codex_critic_r2.sh; then
  pass "run_codex_critic_r2.sh jq 요약 적용"
else
  fail "run_codex_critic_r2.sh jq 요약 미적용"
fi
# axiom 캐시 경로 확인
if grep -q "axiom_inject_body.md" 02_Infrastructure/hooks/unified_agent_guard.sh; then
  pass "unified_agent_guard.sh axiom mtime 캐싱 적용"
else
  fail "unified_agent_guard.sh axiom 캐싱 미적용"
fi
# pipeline_trigger 비동기화 확인
if grep -q "nohup" 02_Infrastructure/hooks/pipeline_trigger.sh; then
  pass "pipeline_trigger.sh nohup 비동기화 적용"
else
  fail "pipeline_trigger.sh nohup 미적용"
fi
# Codex 캐시 디렉토리 확인
if grep -q "codex_verdicts" 02_Infrastructure/tools/debate_helpers/run_codex_critic.sh; then
  pass "run_codex_critic.sh verdict 캐시 로직 적용 (Block F)"
else
  fail "run_codex_critic.sh 캐시 로직 미적용"
fi

# ─── Block D: Caching Discipline ────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Block D] Caching Discipline 검증" | tee -a "$LOG"
if grep -q "## Caching Discipline" CLAUDE.md; then
  pass "CLAUDE.md Caching Discipline 절 추가됨"
else
  fail "CLAUDE.md Caching Discipline 미추가"
fi

# ─── Block E: R1→R2 요약본 ──────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Block E] R1→R2 요약본 검증" | tee -a "$LOG"
if grep -q "s0_debate_r1_summary" 02_Infrastructure/hooks/s0_debate_enforcer.sh; then
  pass "s0_debate_enforcer R1 요약본 생성 로직 적용"
else
  fail "s0_debate_enforcer R1 요약본 미적용"
fi

# ─── Block F: v55 Compact Mode Lawbook ──────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Block F/G] Lawbook + Amendment 검증" | tee -a "$LOG"
if [ -f "00_Lawbook/v6_amendment_debate_compact.md" ]; then
  if grep -q "Status.*APPROVED" 00_Lawbook/v6_amendment_debate_compact.md; then
    pass "v6 Amendment APPROVED 상태"
  else
    warn "v6 Amendment 존재하나 APPROVED 상태 아님"
  fi
else
  fail "v6 Amendment 파일 없음"
fi
if grep -q "§1.6 Compact Mode\|Compact Mode" 00_Lawbook/v55_consensus_addendum.md; then
  pass "v55 §1.6 Compact Mode 조항 추가됨"
else
  fail "v55 Compact Mode 조항 미추가"
fi

# ─── Block H: Compact Mode Hook 구현 ────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Block H] Compact Mode Hook 구현 검증" | tee -a "$LOG"
[ -f "02_Infrastructure/tools/debate_helpers/academic_factcheck.sh" ] && pass "academic_factcheck.sh 신설됨" || fail "academic_factcheck.sh 없음"
[ -f "02_Infrastructure/tools/debate_helpers/quant_factcheck.sh" ] && pass "quant_factcheck.sh 신설됨" || fail "quant_factcheck.sh 없음"
if grep -q "QVEST_DEBATE_MODE" 02_Infrastructure/hooks/s0_debate_guard.sh; then
  pass "s0_debate_guard.sh Compact/Full 모드 분기"
else
  fail "s0_debate_guard.sh 모드 분기 미적용"
fi
if grep -q "QVEST_DEBATE_MODE\|compact" 02_Infrastructure/hooks/s0_debate_enforcer.sh; then
  pass "s0_debate_enforcer.sh Compact 모드 대응"
else
  fail "s0_debate_enforcer.sh Compact 대응 미적용"
fi
if grep -q "debaters.*3\|3인\|compact" 02_Infrastructure/hooks/s0_verdict_router.sh; then
  pass "s0_verdict_router.sh 3인 router 규칙 추가"
else
  fail "s0_verdict_router.sh 3인 규칙 미추가"
fi

# ─── Hook 동작 smoke test (불변 보증) ────────────────────────────────────
echo "" | tee -a "$LOG"
echo "[Smoke] Hook 불변 보증 smoke test" | tee -a "$LOG"
# safety_guard.sh: 05_Production write 차단 확인
TEST_IN='{"tool_name":"Write","tool_input":{"file_path":"05_Production/dummy.R","content":"x"}}'
OUT=$(echo "$TEST_IN" | bash 02_Infrastructure/hooks/safety_guard.sh 2>/dev/null)
if echo "$OUT" | grep -q "block.*05_Production"; then
  pass "safety_guard 05_Production block 동작 유지"
else
  fail "safety_guard 05_Production block 동작 실패 — 출력: $OUT"
fi

# ─── 결과 요약 ──────────────────────────────────────────────────────────
echo "" | tee -a "$LOG"
echo "==============================================================================" | tee -a "$LOG"
echo "결과: ✅ PASS $PASS / ❌ FAIL $FAIL / ⚠️  WARN $WARN" | tee -a "$LOG"
echo "로그: $LOG" | tee -a "$LOG"
echo "==============================================================================" | tee -a "$LOG"

# 플래그 처리
FLAG_DIR="$DIR/.cache"
PENDING_FLAG="$FLAG_DIR/token_reduction_test_pending.flag"
DONE_FLAG="$FLAG_DIR/token_reduction_test_done_${TS}.log"
if [ -f "$PENDING_FLAG" ]; then
  mv "$PENDING_FLAG" "$DONE_FLAG"
  cat "$LOG" >> "$DONE_FLAG"
  echo "플래그 이동: $PENDING_FLAG → $DONE_FLAG" | tee -a "$LOG"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "🎉 모든 핵심 검증 통과. Block A~H 정상 배포 확인." | tee -a "$LOG"
  exit 0
else
  echo "⛔ $FAIL 건 FAIL. 로그 확인 후 조치 필요." | tee -a "$LOG"
  exit 1
fi
