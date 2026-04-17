#!/bin/bash
#==============================================================================
# Artifact Validator — PostToolUse[Write] Hook (3중 방어선 2선)
# 산출물 JSON 스키마 검증 + PIT 패턴 탐지 + L-code EXIT CONDITION.
#==============================================================================

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
    python3 -c "
import json, sys
try:
    with open('$FILE') as f:
        d = json.load(f)
    required = ['strategy_id', 'factor_id']
    missing = [r for r in required if r not in d]
    if missing:
        print(f'$(date +%H:%M:%S) SCHEMA_WARN: $FILE missing {missing}', file=sys.stderr)
except Exception as e:
    print(f'$(date +%H:%M:%S) PARSE_ERROR: $FILE — {e}', file=sys.stderr)
" 2>> "$LOG"
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
    ;;
esac
