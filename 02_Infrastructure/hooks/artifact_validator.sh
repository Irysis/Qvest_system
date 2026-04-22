#!/bin/bash
#==============================================================================
# Artifact Validator — PostToolUse[Write] Hook (3중 방어선 2선)
# 산출물 JSON 스키마 검증 + PIT 패턴 탐지 + L-code EXIT CONDITION.
#==============================================================================

# ERR trap (Phase C3 전수 강제) — hook 실패 시 도구 차단 방지
trap 'echo "{}"; exit 0' ERR

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
LOG="/tmp/artifact_validation.log"

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null)

[ -z "$FILE" ] && exit 0

case "$FILE" in
  # v53 Fix #4 + S2.4: s6_validation grade 누락 + v53 schema hash 검증 (monitoring)
  # 우선 매치 — stage_artifacts 하위 경로여도 먼저 처리, ;;&로 stage_artifacts 케이스 폴스루.
  *s6_validation*.json)
    python3 -c "
import json, hashlib, os, glob, sys, re
try:
    with open('$FILE') as f: d = json.load(f)
except Exception as e:
    print(f'$(date +%H:%M:%S) PARSE_ERROR: $FILE {e}', file=sys.stderr)
    sys.exit(0)

fn = os.path.basename('$FILE')

# Fix #4: grade 필드 누락 경고
if 'grade' not in d and 'verdict' not in d:
    print(f'$(date +%H:%M:%S) WARN: s6_validation without grade: {fn}', file=sys.stderr)

# S2.4: v53 schema 시 hash 검증 (monitoring — 경고만, 차단 없음)
if d.get('schema_version') == 'v53':
    claimed = d.get('hurdle_artifact_hash', '')
    m = re.search(r'STR_[A-Za-z0-9_]+', fn)
    if claimed and m:
        strategy = m.group(0)
        candidates = glob.glob(f'$PROJECT_ROOT/04_Research/strategies/*{strategy}*/output*/hurdle_result.json')
        if candidates:
            with open(candidates[0], 'rb') as f: actual = hashlib.sha256(f.read()).hexdigest()
            if actual != claimed:
                print(f'$(date +%H:%M:%S) WARN: v53 hash mismatch: {fn} claimed={claimed[:16]} actual={actual[:16]}', file=sys.stderr)
    # grade_source == judge_override 시 reason 길이 확인
    if d.get('grade_source') == 'judge_override':
        reason = d.get('grade_override_reason', '')
        if len(str(reason)) < 500:
            print(f'$(date +%H:%M:%S) WARN: v53 override reason too short ({len(str(reason))} < 500): {fn}', file=sys.stderr)
" 2>> "$LOG"
    ;;&

  # 산출물 JSON 스키마 검증 (s6_validation은 ;;& 로 이미 처리 후 여기로 폴스루)
  *stage_artifacts/*.json)
    P2B_RESULT=$(python3 -c "
import json, sys
try:
    with open('$FILE') as f:
        raw = f.read()
        d = json.loads(raw)
    required = ['strategy_id', 'factor_id']
    missing = [r for r in required if r not in d]
    if missing:
        print(f'SCHEMA_WARN|$FILE missing {missing}', file=sys.stderr)

    # v53 Sprint 3 P2-B: 금지 합리화 표현 전 stage_artifacts 스캔
    BANNED = [
        '영향 미미', '관행적 허용', '보수적이면 괜찮다',
        '대부분 결과 동일', '이미 반영되어 있었을 것',
        '백테스트 기간이 충분히 길어서 상쇄',
        '실무적으로 유의미', '이 정도면 괜찮다',
        '대체로 동일', '무시할 수 있는', '무시 가능한 수준',
    ]
    hits = [phr for phr in BANNED if phr in raw]
    if hits:
        print('RATIONALIZATION|' + '; '.join(hits))
except Exception as e:
    print(f'PARSE_ERROR|$FILE — {e}', file=sys.stderr)
" 2>> "$LOG")

    # 금지 표현 탐지 시 파일을 .p2b_violation 접미사로 격리 + block
    if echo "$P2B_RESULT" | grep -q "^RATIONALIZATION|"; then
      PHRASES=$(echo "$P2B_RESULT" | grep "^RATIONALIZATION|" | cut -d'|' -f2)
      mv "$FILE" "${FILE}.p2b_violation" 2>/dev/null
      echo "$(date +%H:%M:%S) P2-B_BLOCK: $FILE — $PHRASES" >> "$LOG"
      printf '{"decision":"block","reason":"[P2-B Rationalization Guard] 금지 합리화 표현 탐지: [%s]. qepm rules의 PIT-합리화 표현 위반. 파일을 %s.p2b_violation 으로 격리했습니다. 증거 기반으로 재작성 후 재저장하세요."}' "$PHRASES" "$FILE"
      exit 0
    fi
    ;;

  # PIT 금지 표현 탐지
  *run_all.R|*factor_engine.R)
    hits=$(grep -n "normalizePath\|영향 미미\|관행적 허용\|보수적이면 괜찮다\|대부분 결과 동일" "$FILE" 2>/dev/null)
    if [ -n "$hits" ]; then
      echo "$(date +%H:%M:%S) PIT_VIOLATION: $FILE" >> "$LOG"
      echo "$hits" >> "$LOG"
    fi
    # ── 최적화 패턴 2차 검사 (PreToolUse에서 놓친 경우) ──
    opt_loop=$(grep -n "for.*load_month_factors\|for.*read_parquet" "$FILE" 2>/dev/null)
    if [ -n "$opt_loop" ]; then
      echo "$(date +%H:%M:%S) OPT_VIOLATION(L-534): $FILE — loop parquet reload" >> "$LOG"
      echo "$opt_loop" >> "$LOG"
    fi
    if grep -q "load_rawdata" "$FILE" && ! grep -q "use_cache.*TRUE" "$FILE"; then
      echo "$(date +%H:%M:%S) OPT_VIOLATION: $FILE — missing use_cache=TRUE" >> "$LOG"
    fi
    if grep -qE "merge\(|data\.table" "$FILE" && ! grep -q "setkey(" "$FILE"; then
      echo "$(date +%H:%M:%S) OPT_WARN: $FILE — missing setkey()" >> "$LOG"
    fi
    ;;

  # L-code EXIT CONDITION: DONE_S6 생성 시 l_code 존재 체크
  *DONE_S6_*)
    strategy=$(basename "$FILE" | sed 's/DONE_S6_//' | sed 's/.json//')
    lcode=$(find "$PROJECT_ROOT/04_Research/strategies/" -path "*${strategy}*" -name "l_code_*.json" 2>/dev/null | head -1)
    if [ -z "$lcode" ]; then
      echo "$(date +%H:%M:%S) L-CODE MISSING: $strategy — DONE_S6 차단" >> "$LOG"
      # DONE을 되돌림
      todo_name=$(echo "$FILE" | sed 's/DONE_S6/TODO_S6_LCODE_MISSING/')
      mv "$FILE" "$todo_name" 2>/dev/null
    fi
    ;;

  # v53 Fix #3: Judge 포인터 — DONE_S5 감지 시 다음 처리 전략 단일 파일에 기록
  *DONE_S5_*)
    strategy=$(basename "$FILE" | sed 's/DONE_S5_//' | sed 's/.json//')
    mkdir -p "$PROJECT_ROOT/stage_artifacts" 2>/dev/null
    echo "$strategy" > "$PROJECT_ROOT/stage_artifacts/_judge_next_strategy.txt"
    echo "$(date +%H:%M:%S) JUDGE_POINTER: $strategy" >> "$LOG"
    ;;&

  # v53 S2.7: S5 mutation/slate artifact 작성 시 mutation_tracker.json 자동 갱신
  *stage_artifacts/s5_mutation_*.json|*stage_artifacts/s5_research_slate_*.json|*stage_artifacts/s5_synthesis_slate_*.json)
    QVEST_PROJECT_DIR="$PROJECT_ROOT" python3 "$PROJECT_ROOT/02_Infrastructure/validation/mutation_tracker.py" >> "$LOG" 2>&1 || true
    ;;&

  # v53 S2.11: s6_judge 작성 시 Role Honesty Audit 자동 호출 (background)
  *stage_artifacts/s6_judge_*.json|*stage_artifacts/s6_validation_*.json)
    # 이미 audit artifact 있으면 skip (중복 방지)
    _sid=$(basename "$FILE" | grep -oP 'STR_[0-9A-Za-z_]+' | head -1)
    if [ -n "$_sid" ] && [ ! -f "$PROJECT_ROOT/stage_artifacts/role_honesty_${_sid}.json" ]; then
      (
        QVEST_PROJECT_DIR="$PROJECT_ROOT" \
        Rscript "$PROJECT_ROOT/02_Infrastructure/validation/role_honesty_runner.R" "$FILE" \
          >> "$LOG" 2>&1
      ) &
    fi
    ;;&

  # v53 S2.15: hurdle_result.json 또는 s6_judge 작성 시 grade_a_catalog 자동 갱신
  */hurdle_result.json|*stage_artifacts/s6_judge_*.json|*stage_artifacts/s6_validation_*.json)
    (
      QVEST_PROJECT_DIR="$PROJECT_ROOT" \
      python3 "$PROJECT_ROOT/02_Infrastructure/validation/grade_a_catalog_builder.py" \
        >> "$LOG" 2>&1
    ) &
    ;;&

  # v53 Sprint 4 AX-P0: l_code_*.json 작성 시 harvester + cluster_extractor 자동 실행
  *stage_artifacts/l_code_*.json)
    (
      QVEST_PROJECT_DIR="$PROJECT_ROOT" \
      python3 "$PROJECT_ROOT/02_Infrastructure/axiom/lcode_harvester.py" \
        >> "$LOG" 2>&1 && \
      QVEST_PROJECT_DIR="$PROJECT_ROOT" \
      python3 "$PROJECT_ROOT/02_Infrastructure/axiom/cluster_extractor.py" \
        >> "$LOG" 2>&1
    ) &
    ;;&

  # v55 s0_record 신규 스키마 검증 (expected_role 6종 / trail 3종 / gap_targeting_axes / cash_component)
  *stage_artifacts/s0_record_*.json)
    V55_CHECK=$(python3 <<PYEOF
import json, sys

VALID_ROLES = {'core_alpha','diversifier','defense','cash_allocation','regime_adaptive','ml_predictive'}
VALID_TRAILS = {'standard','ml_empirical_first','kr_statistical'}
VALID_GAP_AXES = {'SR','MDD_regime','KR_structural','cash_efficiency'}

try:
    with open('$FILE') as f:
        d = json.load(f)
except Exception as e:
    print(f'PARSE_ERROR|{e}')
    sys.exit(0)

errors = []
warnings = []

# expected_role 6종 검증 (필수)
role = d.get('expected_role', '')
if not role:
    errors.append('expected_role 누락 (6종 필수: ' + ', '.join(sorted(VALID_ROLES)) + ')')
elif role not in VALID_ROLES:
    errors.append(f"expected_role='{role}' 무효 (허용: {', '.join(sorted(VALID_ROLES))})")

# trail 3종 검증 (필수)
trail = d.get('trail', '')
if not trail:
    warnings.append('trail 누락 — 기본값 standard 적용 권장 (ml_empirical_first/kr_statistical 명시 권장)')
elif trail not in VALID_TRAILS:
    errors.append(f"trail='{trail}' 무효 (허용: {', '.join(sorted(VALID_TRAILS))})")

# gap_targeting_axes 배열 검증 (필수)
gap_axes = d.get('gap_targeting_axes', [])
if not gap_axes:
    errors.append('gap_targeting_axes 누락 (배열 1+ 필수: ' + ', '.join(sorted(VALID_GAP_AXES)) + ')')
elif not isinstance(gap_axes, list):
    errors.append('gap_targeting_axes는 배열이어야 함')
else:
    invalid_axes = [a for a in gap_axes if a not in VALID_GAP_AXES]
    if invalid_axes:
        errors.append(f'gap_targeting_axes 무효 값: {invalid_axes}')

# expected_role_rationale 검증 (50자+, 권장)
rationale = d.get('expected_role_rationale', '')
if len(rationale) < 50:
    warnings.append(f'expected_role_rationale 짧음 ({len(rationale)}자 < 50자 권장)')

# cash_component 검증 (cash_allocation role이면 필수, 아니면 optional)
if role == 'cash_allocation':
    cc = d.get('cash_component', {})
    if not cc:
        errors.append('role=cash_allocation인데 cash_component 누락 (uses_cash, max_cash_weight 필수)')
    elif not isinstance(cc, dict):
        errors.append('cash_component는 object')
    elif 'max_cash_weight' not in cc:
        errors.append('cash_component.max_cash_weight 누락')

# 결과 출력
if errors:
    print('BLOCK|' + '; '.join(errors))
elif warnings:
    print('WARN|' + '; '.join(warnings))
else:
    print('PASS|' + f"role={role} trail={trail or 'standard'} axes={len(gap_axes)}")
PYEOF
)
    V55_STATUS=$(echo "$V55_CHECK" | cut -d'|' -f1)
    V55_MSG=$(echo "$V55_CHECK" | cut -d'|' -f2-)

    if [ "$V55_STATUS" = "BLOCK" ]; then
      mv "$FILE" "${FILE}.missing_v55_fields" 2>/dev/null
      echo "$(date +%H:%M:%S) V55_BLOCK: $FILE — $V55_MSG" >> "$LOG"
      CTX_ESC=$(printf '%s' "[v55 s0_record 스키마 위반] ${V55_MSG}. 파일을 ${FILE}.missing_v55_fields로 격리. 재작성 필수 필드: expected_role(6종), trail(3종), gap_targeting_axes(4축 배열), expected_role_rationale(50자+). role=cash_allocation이면 cash_component.max_cash_weight 필수." | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
      echo "{\"decision\":\"block\",\"reason\":${CTX_ESC}}"
      exit 0
    fi

    if [ "$V55_STATUS" = "WARN" ]; then
      echo "$(date +%H:%M:%S) V55_WARN: $FILE — $V55_MSG" >> "$LOG"
    fi

    echo "$(date +%H:%M:%S) V55_PASS: $FILE — $V55_MSG" >> "$LOG"

    # v53 Sprint 3 P3-B: s0_record 작성 시 backlog bucket 모니터 갱신 (경고만, block X)
    (
      QVEST_PROJECT_DIR="$PROJECT_ROOT" \
      python3 "$PROJECT_ROOT/02_Infrastructure/validation/backlog_bucket_monitor.py" \
        >> "$LOG" 2>&1
    ) &
    # 기존 backlog_buckets.json 경고 존재 시 additionalContext로 주입 (sync 버전 재실행 방지)
    BL_CACHE="$PROJECT_ROOT/.cache/backlog_buckets.json"
    if [ -f "$BL_CACHE" ]; then
      BL_WARN=$(python3 -c "
import json
try:
    d = json.load(open('$BL_CACHE'))
    w = d.get('imbalance_warnings', [])
    if w: print(' / '.join(w))
except: pass
" 2>/dev/null)
      if [ -n "$BL_WARN" ]; then
        CTX_ESC=$(printf '%s' "[P3-B Backlog] 4-bucket 분포 편향 (경고): $BL_WARN. qepm §1 Exploit 50%/Stabilize 20%/Explore 20%/Diagnose 10% 기준." | python3 -c "import sys,json;print(json.dumps(sys.stdin.read()))")
        echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":$CTX_ESC}}"
        exit 0
      fi
    fi
    ;;
esac
