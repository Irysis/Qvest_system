#!/bin/bash

trap 'echo "{}"; exit 0' ERR  # Phase C3 전수 강제
#==============================================================================
# Axiom Enforcement Hook — PreToolUse[Write|Edit] (v52 AX 배선)
# AX-code 위반 패턴을 탐지하고 차단한다.
# Level 0: AX-code > PIT C1-C15 > L-code > Signals
#
# (2026-07-04 AXM-03) 동적 enforcement 스키마 배선:
#   active AX-*.json의 enforcement_hook dict(우선) 또는 enforcement dict를 소비.
#   스키마: {mode: block|advisory|documented, regex: [AND 전부매치],
#            require: [OR — 하나라도 존재 시 예외], applies_to_files: [...], reason}
#   mode=block → decision block / advisory → additionalContext warn / documented → 스킵.
#   의미론 SOT (.claude/rules/axioms.md "Hook 강제" 절, 변경 없음):
#     AX-000 documented / AX-001 block / AX-002 advisory /
#     AX-003 AX-004 AX-005 advisory / AX-007 AX-008 documented
#   legacy 하드코딩 절(AX-001/AX-002)은 python 부재 시 fallback으로 유지.
#==============================================================================

INPUT=$(cat)
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_shared_parse.sh"

# Write/Edit만 검사
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
  echo '{}'
  exit 0
fi

DIR=$(ls -d /c/Users/99922/OneDrive/Quant_Module_Moltbot /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot /g/Quant_Module_Moltbot /mnt/g/Quant_Module_Moltbot /mnt/c/Users/*/OneDrive/바탕\ 화면/Quant_Module_Moltbot 2>/dev/null | head -1)
LOG="/tmp/axiom_enforcement.log"

# ─── v53 Sprint 4 AX-P2 + AXM-03: 동적 AX.enforcement 규칙 적용 (1순위) ─────
# 모든 active AX의 enforcement_hook dict를 regex 기반으로 적용.
_ACTIVE_DIR="$DIR/qepm/memory/axioms/active"
if [ -d "$_ACTIVE_DIR" ]; then
  # (v8.1.2) bytes 경유 UTF-8 명시 + axiom 파일 encoding 명시 — cp949 locale에서 한글 AX-*.json이
  # UnicodeDecodeError로 전부 silent skip 되던 결함 수리. skip은 로그로 가시화.
  # (AXM-03) file_path/active_dir는 env 경유 전달 — 백슬래시 경로를 python 소스에 직접
  # 박을 때의 unicodeescape SyntaxError·인용부호 주입 차단 (bootstrap v8.1.3와 동일 패턴).
  _VIOLATION=$(printf '%s' "$CONTENT" | AX_FILE_PATH="$FILE_PATH" AX_ACTIVE_DIR="$_ACTIVE_DIR" "$QVEST_PY_BIN" -c "
import sys, json, os, glob, re
content = sys.stdin.buffer.read().decode('utf-8', 'replace')
file_path = os.environ.get('AX_FILE_PATH', '')
active_dir = os.environ.get('AX_ACTIVE_DIR', '')
def _lst(v):
    if v is None: return []
    return [v] if isinstance(v, str) else [x for x in v if isinstance(x, str)]
for f in sorted(set(glob.glob(os.path.join(active_dir, '**', 'AX-*.json'), recursive=True)) | set(glob.glob(os.path.join(active_dir, 'AX-*.json')))):
    try:
        ax = json.load(open(f, encoding='utf-8'))
    except Exception as e:
        open('/tmp/axiom_enforcement_skip.log', 'a', encoding='utf-8').write(f'{f}: {type(e).__name__}\n')
        continue
    enforcement = ax.get('enforcement_hook') or ax.get('enforcement') or ''
    if not isinstance(enforcement, dict):
        continue
    ax_id = ax.get('axiom_id') or ax.get('id') or os.path.basename(f)
    mode = enforcement.get('mode') or ax.get('enforcement_mode') or 'documented'
    if mode not in ('block', 'advisory'):
        continue
    pats = _lst(enforcement.get('regex'))
    if not pats:
        continue
    applies = _lst(enforcement.get('applies_to_files')) or ['.*']
    if not any(re.search(a, file_path) for a in applies):
        continue
    if not all(re.search(p, content, re.IGNORECASE | re.MULTILINE) for p in pats):
        continue
    reqs = _lst(enforcement.get('require'))
    if reqs and any(re.search(q, content, re.IGNORECASE | re.MULTILINE) for q in reqs):
        continue
    reason = str(enforcement.get('reason') or pats[0]).replace('\"', ' ').replace('%', 'pct')
    print(f'VIOLATION|{mode}|{ax_id}|{reason}')
    sys.exit(0)
" 2>/dev/null)
  if [ -n "$_VIOLATION" ] && echo "$_VIOLATION" | grep -q "^VIOLATION|"; then
    AX_MODE=$(echo "$_VIOLATION" | cut -d'|' -f2)
    AX_ID=$(echo "$_VIOLATION" | cut -d'|' -f3)
    AX_REASON=$(echo "$_VIOLATION" | cut -d'|' -f4-)
    if [ "$AX_MODE" = "block" ]; then
      echo "$(date +%H:%M:%S) AX_ENFORCE_BLOCK(dynamic): $AX_ID $AX_REASON" >> "$LOG"
      printf '{"decision":"block","reason":"[%s Enforcement dynamic] %s. active axiom enforcement 규칙 위반."}' "$AX_ID" "$AX_REASON"
      exit 0
    else
      echo "$(date +%H:%M:%S) AX_ENFORCE_ADVISORY(dynamic): $AX_ID $AX_REASON" >> "$LOG"
      printf '{"additionalContext":"[%s 경고 dynamic] %s"}' "$AX_ID" "$AX_REASON"
      exit 0
    fi
  fi
fi

# ─── AX-001 (legacy fallback): Defense 전기간 SR 기준 금지 ───────────────────
# hurdle_result.json 또는 s6_judge에서 defense 전략을 전기간 SR만으로 Grade F 판정.
# 동적 경로(AX-001.json enforcement_hook)와 동일 의미론 — python 부재/실패 시 안전망.
if echo "$FILE_PATH" | grep -qE "(hurdle_result|s6_judge|s7_).*\.json"; then
  if echo "$CONTENT" | grep -qiE "defense|Defence"; then
    if echo "$CONTENT" | grep -qiE '"grade".*"F"' && ! echo "$CONTENT" | grep -qiE "crisis|stress|conditional|bad_normal|regime"; then
      echo "$(date +%H:%M:%S) AX-001_WARN: $FILE_PATH — Defense Grade F without conditional eval (legacy path)" >> "$LOG"
      printf '{"decision":"block","reason":"[AX-001] Defense 전략을 전기간 SR만으로 Grade F 판정 금지. 위기 구간 alpha + Core 대비 MDD + bad/normal IC ratio 조건부 평가 필수."}'
      exit 0
    fi
  fi
fi

# ─── AX-002 (legacy fallback): 프로세스 우회 탐지 (금지 합리화 표현) ──────────
# S1 결과를 보고 S0 가설을 사후 정당화하는 패턴
if echo "$FILE_PATH" | grep -qE "s0_record.*\.json"; then
  if echo "$CONTENT" | grep -qiE "S1.*결과.*확인.*후|백테스트.*결과.*바탕|성과.*보고.*수정"; then
    echo "$(date +%H:%M:%S) AX-002_WARN: $FILE_PATH — s0_record에 S1 결과 기반 사후 수정 의심 (legacy path)" >> "$LOG"
    # 경고만 (차단은 과도)
    echo "{\"additionalContext\":\"[AX-002 경고] s0_record에 S1 결과 기반 사후 수정 패턴 탐지. S0 가설은 S1 실행 전에 확정되어야 합니다.\"}"
    exit 0
  fi
fi

echo '{}'
exit 0
