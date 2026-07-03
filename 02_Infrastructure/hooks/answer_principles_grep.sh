#!/usr/bin/env bash
#==============================================================================
# answer_principles_grep.sh — PostToolUse[Write/Edit] Hook (Level 2 soft)
#
# Qvest 답변 원칙 8원칙 + 5금지 enforcement (lawbook v1.0 2026-04-29)
# Reference: 00_Lawbook/Multi_Agent/qvest_answer_principles.md
#
# 검사 대상 (비단순 산출물 패턴):
#   - methodology_active.md / methodology_*.md
#   - l_code_*.json
#   - alpha_package.json / risk_package.json / optimization_package.json
#   - forge_package.json / judge_verdict.json / governor_admission.json
#   - pg0_gap_vector_*.json / book_state.json / governance_log.json
#   - 4way_summary.json / monthly_comparison_summary.json
#   - common_charter.md / lawbook (00_Lawbook/) / _shared_prefix.md
#   - *.py (python-policy.md §5 — 회피표현 + 자체합성 idiom soft alert)
#
# 회피 표현 grep (검증 증거 없이 사용 시 위반):
#   가정: 유사하므로/동일하므로/거의 같다/대략/근사
#   추정: 추정/예상/기대/아마/보통
#   보류: 추후 검증/다음 step/TBD/나중에
#   단순화: 이 정도면/충분/관행적/관례상
#   합리화: 영향 미미/보수적이면/이미 반영/상쇄
#
# 검증 증거 패턴:
#   - 파일 경로 (예: 02_Infrastructure/.../foo.R, qepm/mailbox/...)
#   - line 번호 (line N, :NNN)
#   - 측정 출처 (forge_realized_share_based / Return.portfolio / apply.monthly)
#
# 동작:
#   1. file_path 비단순 패턴 매칭 → 아니면 skip
#   2. content 회피 표현 카운트
#   3. content 검증 증거 카운트
#   4. 회피 ≥ 3 + 증거 = 0 → log alert (soft, exit 0 always)
#   5. soft alert는 telegram 전송 안 함 (noise 방지). log only.
#
# 우회: QVEST_SKIP_ANSWER_PRINCIPLES=1
# 로그: /tmp/answer_principles.log
#==============================================================================

trap 'echo "{}"; exit 0' ERR
set -u

INPUT=$(cat 2>/dev/null || echo '{}')
LOG="/tmp/answer_principles.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

if [ "${QVEST_SKIP_ANSWER_PRINCIPLES:-0}" = "1" ]; then
  echo '{}'; exit 0
fi

# Extract file_path from JSON input
FILE_PATH=$(echo "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

[ -z "$FILE_PATH" ] && { echo '{}'; exit 0; }
[ ! -f "$FILE_PATH" ] && { echo '{}'; exit 0; }

# 비단순 산출물 패턴 매칭 (.py = python-policy.md §5 커버리지)
NONSIMPLE_PATTERN='(methodology_.*\.md|l_code_.*\.json|alpha_package\.json|risk_package\.json|optimization_package\.json|forge_package\.json|judge_verdict\.json|governor_admission\.json|pg0_gap_vector.*\.json|book_state\.json|governance_log\.json|4way_summary\.json|monthly_comparison.*\.json|common_charter\.md|00_Lawbook/.*\.md|_shared_prefix\.md|MEMORY\.md|\.py$)'

if ! echo "$FILE_PATH" | grep -qE "$NONSIMPLE_PATTERN"; then
  echo '{}'; exit 0
fi

# .py 자체합성 idiom soft alert (python-policy.md §4 — R prod(1+r)/cumprod 동등)
# Level 2 soft 유지 — log only, block 없음 (block은 backtest_contract_audit.sh 담당)
if echo "$FILE_PATH" | grep -qE '\.py$'; then
  PY_SYNTH_PATTERN='np\.prod\( *1 *\+|\( *1 *\+ *[A-Za-z_][A-Za-z0-9_.]* *\)\.cumprod\(|\( *w *\* *r *\)\.sum\(|\.prod\( *\) *- *1|0\.[0-9]+ *\* *r[0-9]'
  if grep -qE "$PY_SYNTH_PATTERN" "$FILE_PATH" 2>/dev/null; then
    echo "[$TS] ⚠️  PY SELF-SYNTHESIS SUSPECTED (soft) — $FILE_PATH" >> "$LOG"
    echo "[$TS]    python-policy.md §4: np.prod(1+r)/(1+r).cumprod()/(w*r).sum()/.prod()-1 금지" >> "$LOG"
  fi
fi

# 회피 표현 grep (한국어 + 영어)
EVASION_PATTERNS='(유사하므로|동일하므로|거의 같다|대략|근사|추정한다|예상된다|아마|보통.*것|TBD|추후 검증|나중에|이 정도면|충분하다 판단|관행적|관례상|영향 미미|보수적이면|이미 반영|상쇄|similar to|approximately|roughly|essentially|estimated|likely|probably|expected|to be verified|good enough|conventional|negligible|conservative enough|already accounted)'

# 검증 증거 패턴 (파일 경로 + line + PerformanceAnalytics 표준 + 측정 출처)
EVIDENCE_PATTERNS='(\.R:[0-9]+|\.json::|\.csv::|\.parquet::|line [0-9]+|forge_realized_share_based|Return\.portfolio|apply\.monthly|Return\.cumulative|table\.AnnualizedReturns|maxDrawdown|verbose=TRUE|02_Infrastructure/|04_Research/|qepm/mailbox/|stage_artifacts/|sr_provenance_certificate|measurement_basis_primary|canonical_screen_bt|portfolio_alpha_t_nw_lag3|metric_type)'

# 명시 라벨 (회피 카운트에서 제외)
HONEST_LABELS='(검증 안 됨|미실행|honest 표시|task #[0-9]+ 처리 예정|task #[0-9]+ 후속)'

# grep -c (line count, single integer) + numeric-only 강제 (set -u 호환)
to_int() {
  local raw="$1"
  local n
  n=$(printf '%s' "$raw" | tr -dc '0-9' | head -c 10)
  if [ -z "$n" ]; then echo 0; else echo "$n"; fi
}

EVASION_RAW=$(grep -cE "$EVASION_PATTERNS" "$FILE_PATH" 2>/dev/null || echo 0)
EVIDENCE_RAW=$(grep -cE "$EVIDENCE_PATTERNS" "$FILE_PATH" 2>/dev/null || echo 0)
HONEST_RAW=$(grep -cE "$HONEST_LABELS" "$FILE_PATH" 2>/dev/null || echo 0)

EVASION_COUNT=$(to_int "$EVASION_RAW")
EVIDENCE_COUNT=$(to_int "$EVIDENCE_RAW")
HONEST_COUNT=$(to_int "$HONEST_RAW")

# Adjusted evasion (명시 라벨 차감) — 항상 정의 보장
ADJ_EVASION=$((EVASION_COUNT - HONEST_COUNT))
if [ "$ADJ_EVASION" -lt 0 ] 2>/dev/null; then
  ADJ_EVASION=0
fi

# Log all checks (audit trail)
echo "[$TS] file=$FILE_PATH evasion=$EVASION_COUNT honest=$HONEST_COUNT adj_evasion=$ADJ_EVASION evidence=$EVIDENCE_COUNT" >> "$LOG"

# Alert condition: adj_evasion >= 3 AND evidence == 0
if [ $ADJ_EVASION -ge 3 ] && [ $EVIDENCE_COUNT -eq 0 ]; then
  echo "[$TS] ⚠️  ANSWER PRINCIPLES VIOLATION SUSPECTED" >> "$LOG"
  echo "[$TS]    file: $FILE_PATH" >> "$LOG"
  echo "[$TS]    회피 표현 ${ADJ_EVASION}건, 검증 증거 0건" >> "$LOG"
  echo "[$TS]    lawbook: 00_Lawbook/Multi_Agent/qvest_answer_principles.md §6" >> "$LOG"
fi

# Soft alert — never block. Always allow.
echo '{}'
exit 0
