#!/usr/bin/env bash
#==============================================================================
# quant_factcheck.sh — S0 Debate Compact Mode: Quant Fact-Check Hook
#
# Scout plan의 factors를 받아 ICIR/KR IC sign/hard_fail 자동 확인.
# Rscript는 hook_batch_runner.R의 hook_quant_factcheck()로 통합 호출.
#
# 입력: $1 = Scout plan JSON 경로 또는 환경변수 FC_CONTENT (JSON string)
# 환경변수: HYP_ID (필수)
# 출력: stage_artifacts/quant_factcheck_{H_ID}.json (stdout에도 출력)
#
# V6 Amendment APPROVED (2026-04-19). Block H.
# 제약: PIT C1~C15 / AX-000~005 / Stage Gate 순서 = 0% 변경
#==============================================================================

trap 'echo "{\"decision\":\"allow\"}"; exit 0' ERR

DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1 || echo "$PWD")

# ─── 입력 처리 ───
INPUT_PATH="${1:-}"
: "${HYP_ID:=unknown}"

if [ -n "$INPUT_PATH" ] && [ -f "$INPUT_PATH" ]; then
  export FC_CONTENT=$(cat "$INPUT_PATH")
  if [ "$HYP_ID" = "unknown" ]; then
    HYP_ID=$(basename "$INPUT_PATH" | python3 -c "
import sys, re
name = sys.stdin.read().strip().rsplit('.', 1)[0]
m = re.search(r'(H_\d+(?:_[A-Za-z0-9]+)*)\s*$', name)
print(m.group(1) if m else 'unknown')
" 2>/dev/null || echo "unknown")
    export HYP_ID
  fi
elif [ -z "${FC_CONTENT:-}" ]; then
  echo '{"error":"no input","hypothesis_id":"unknown"}' >&2
  exit 1
fi

LOGFILE="/tmp/quant_factcheck_${HYP_ID}.log"
OUTFILE="${DIR}/stage_artifacts/quant_factcheck_${HYP_ID}.json"

# ─── Step 1: factors 추출 (python3, 경량) ───
FACTORS_JSON=$(python3 -c "
import json, os, sys
raw = os.environ.get('FC_CONTENT', '')
try:
    d = json.loads(raw)
except:
    d = {}
factors = d.get('factors', d.get('factor_list', d.get('factor_codes', [])))
if isinstance(factors, str):
    factors = [f.strip() for f in factors.split(',') if f.strip()]
family = d.get('economic_family', d.get('family', ''))
print(json.dumps({'factors': factors, 'family': family}))
" 2>/dev/null)

if [ -z "$FACTORS_JSON" ]; then
  echo "{\"error\":\"factors extraction failed\",\"hypothesis_id\":\"$HYP_ID\"}" >&2
  exit 1
fi

FACTORS_ARRAY=$(echo "$FACTORS_JSON" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['factors']))" 2>/dev/null || echo "[]")
FAMILY=$(echo "$FACTORS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('family',''))" 2>/dev/null || echo "")

# ─── Step 2: Rscript — hook_batch_runner.R::hook_quant_factcheck() ───
R_RESULT=$(cd "$DIR" && Rscript --no-save -e "
  source('02_Infrastructure/R/hook_batch_runner.R')
  hook_quant_factcheck(
    factors_json = '${FACTORS_ARRAY}',
    hyp_id       = '${HYP_ID}',
    family       = '${FAMILY}'
  )
" 2>>"$LOGFILE")

R_EXIT=$?

# ─── Step 3: methodology_active.md VALIDATED_HARD_FAIL 매칭 (python3) ───
export FC_FAMILY="$FAMILY"
export FC_R_RESULT="${R_RESULT:-}"
export FC_HYP_ID="$HYP_ID"

FINAL_RESULT=$(python3 <<'PYEOF'
import json, re, os, sys

hyp_id = os.environ.get("FC_HYP_ID", "unknown")
family = os.environ.get("FC_FAMILY", "")
r_raw = os.environ.get("FC_R_RESULT", "")
mem_active = "C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory/methodology_active.md"

# Parse R result (JSON expected on last line)
r_data = {}
for line in r_raw.strip().split("\n"):
    line = line.strip()
    if line.startswith("{"):
        try:
            r_data = json.loads(line)
        except:
            pass

# VALIDATED_HARD_FAIL family matching
matched_hard_fail = []
kr_empirical_check = "no_data"
if family and os.path.isfile(mem_active):
    try:
        with open(mem_active, encoding="utf-8") as f:
            mem_text = f.read()
        for line_t in mem_text.split("\n"):
            if "VALIDATED_HARD_FAIL" in line_t:
                lcode_m = re.search(r'(L-\d+)', line_t)
                if lcode_m and family.lower() in line_t.lower():
                    lc = lcode_m.group(1)
                    if lc not in matched_hard_fail:
                        matched_hard_fail.append(lc)
        if matched_hard_fail:
            kr_empirical_check = "hard_fail_match"
        elif family.lower() in mem_text.lower():
            kr_empirical_check = "partial"
        else:
            kr_empirical_check = "no_data"
    except:
        pass

result = {
    "hypothesis_id": hyp_id,
    "factors": r_data.get("factors", []),
    "icir_10y": r_data.get("icir_10y", {}),
    "kr_ic_sign": r_data.get("kr_ic_sign", {}),
    "factor_db_exists": r_data.get("factor_db_exists", {}),
    "kr_empirical_check": kr_empirical_check,
    "hard_fail_match_lcodes": matched_hard_fail
}
print(json.dumps(result, ensure_ascii=False))
PYEOF
)

if [ -n "$FINAL_RESULT" ]; then
  mkdir -p "$(dirname "$OUTFILE")" 2>/dev/null
  echo "$FINAL_RESULT" > "$OUTFILE"
  echo "$(date +%H:%M:%S) QUANT_FACTCHECK OK: $HYP_ID → $OUTFILE" >> "$LOGFILE"
  echo "$FINAL_RESULT"
  exit 0
else
  echo "{\"error\":\"quant_factcheck failed\",\"hypothesis_id\":\"$HYP_ID\"}" >&2
  echo "$(date +%H:%M:%S) QUANT_FACTCHECK FAIL: $HYP_ID (R_EXIT=$R_EXIT)" >> "$LOGFILE"
  exit 1
fi
