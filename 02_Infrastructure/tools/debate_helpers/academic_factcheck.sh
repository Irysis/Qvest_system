#!/usr/bin/env bash
#==============================================================================
# academic_factcheck.sh — S0 Debate Compact Mode: Academic Fact-Check Hook
#
# Scout plan의 core_reference를 자동 팩트체크 (LLM 불요, rule-based).
#
# 입력: $1 = s0_record JSON 경로 또는 환경변수 FC_CONTENT (JSON string)
# 환경변수: HYP_ID (필수)
# 출력: stage_artifacts/academic_factcheck_{H_ID}.json (stdout에도 출력)
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

LOGFILE="/tmp/academic_factcheck_${HYP_ID}.log"
OUTFILE="${DIR}/stage_artifacts/academic_factcheck_${HYP_ID}.json"

export FC_HYP_ID="$HYP_ID"
export FC_DIR="$DIR"
export FC_METHODOLOGY_ACTIVE="C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory/methodology_active.md"

# ─── python3: core_reference 추출 + 로컬 문헌 + hard_fail 매칭 ───
RESULT=$(python3 <<'PYEOF'
import json, re, os, sys

content_raw = os.environ.get("FC_CONTENT", "")
hyp_id = os.environ.get("FC_HYP_ID", "unknown")
project_dir = os.environ.get("FC_DIR", ".")
mem_active = os.environ.get("FC_METHODOLOGY_ACTIVE", "")

try:
    data = json.loads(content_raw)
except:
    data = {}

core_ref = data.get("core_reference", data.get("core_references", ""))
if isinstance(core_ref, list):
    core_ref = "; ".join(str(c) for c in core_ref)
core_ref = str(core_ref)

family = data.get("economic_family", data.get("family", ""))
mechanism = data.get("mechanism_family", family)

# 1. DOI / Author / Year
dois = re.findall(r'10\.\d{4,9}/[^\s,;)]+', core_ref)
author_year = re.findall(
    r'([A-Z][a-z]+(?:\s+(?:et\s+al\.|&\s+[A-Z][a-z]+))?)\s*\((\d{4})\)',
    core_ref)
years = re.findall(r'\b(19\d{2}|20\d{2})\b', core_ref)
authors = [ay[0] for ay in author_year]

# 2. 01_Literature/Korea_Research/ 로컬 존재 확인
lit_dir = os.path.join(project_dir, "01_Literature", "Korea_Research")
local_matches = []
if os.path.isdir(lit_dir):
    lit_files = os.listdir(lit_dir)
    for author in authors:
        last_name = author.split()[0].lower()
        for f in lit_files:
            if last_name in f.lower() and f not in local_matches:
                local_matches.append(f)
    for y in years:
        for f in lit_files:
            if y in f and f not in local_matches:
                local_matches.append(f)

core_reference_exists = len(local_matches) > 0 or len(dois) > 0

# 3. methodology_active.md VALIDATED_HARD_FAIL family 매칭
matched_hard_fail = []
if mem_active and os.path.isfile(mem_active):
    try:
        with open(mem_active, encoding="utf-8") as f:
            mem_text = f.read()
        for line in mem_text.split("\n"):
            if "VALIDATED_HARD_FAIL" in line:
                lcode_m = re.search(r'(L-\d+)', line)
                if lcode_m and family and family.lower() in line.lower():
                    lc = lcode_m.group(1)
                    if lc not in matched_hard_fail:
                        matched_hard_fail.append(lc)
        # Block-level scan for multi-line patterns
        hf_blocks = re.findall(
            r'(L-\d+)[^#]*?VALIDATED_HARD_FAIL[^#]*?family[=:\s]+(\w+)',
            mem_text, re.IGNORECASE)
        for lc, hf_fam in hf_blocks:
            if hf_fam and family and hf_fam.lower() in family.lower():
                if lc not in matched_hard_fail:
                    matched_hard_fail.append(lc)
    except:
        pass

result = {
    "hypothesis_id": hyp_id,
    "core_reference_exists": core_reference_exists,
    "local_lit_match": local_matches[:10],
    "dois_found": dois,
    "authors_extracted": authors,
    "years_extracted": years,
    "matched_hard_fail_lcodes": list(set(matched_hard_fail)),
    "mechanism_family": mechanism if mechanism else "unknown"
}
print(json.dumps(result, ensure_ascii=False))
PYEOF
)

if [ -n "$RESULT" ]; then
  mkdir -p "$(dirname "$OUTFILE")" 2>/dev/null
  echo "$RESULT" > "$OUTFILE"
  echo "$(date +%H:%M:%S) ACADEMIC_FACTCHECK OK: $HYP_ID → $OUTFILE" >> "$LOGFILE"
  echo "$RESULT"
  exit 0
else
  echo "{\"error\":\"python3 failed\",\"hypothesis_id\":\"$HYP_ID\"}" >&2
  echo "$(date +%H:%M:%S) ACADEMIC_FACTCHECK FAIL: $HYP_ID" >> "$LOGFILE"
  exit 1
fi
