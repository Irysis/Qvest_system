#!/usr/bin/env bash
#==============================================================================
# telegram_direct_call_guard.sh — L3 hard block (v3 — env var fix)
#
# 이벤트: PreToolUse[Bash]
# 목적: tg_send() / tg_send_rich() / tg_send_photo() 직접 호출 차단.
#       Single-Dispatch 강제 — agent는 반드시 tg_agent_brief() 단일 진입점만 사용.
#
# v3 변경 (2026-04-25):
#   - heredoc + pipe stdin 충돌 fix: COMMAND를 환경변수로 python3에 전달
#   - Rscript -e 페이로드를 python regex로 정확히 추출 후 내부만 스캔
#     (false positive 방지: echo/cat 내 string literal "tg_send(" 등)
#   - 함수명-괄호 사이 공백 비허용: \btg_send_rich\( (strict)
#
# 차단 조건 (모두 만족):
#   1. Tool == Bash
#   2. Command에 Rscript -e "..." 페이로드 존재
#   3. 페이로드 내 \btg_send_rich\( / \btg_send_photo\( / \btg_send\(  발견
#   4. 동일 페이로드 내 \btg_agent_brief\(  미존재 (tg_agent_brief 호출 시 면제)
#
# SOT: .claude/skills/qvest-telegram/SKILL.md (v6, 2026-05-07 통합)
# 본 hook 정규식은 함수 이름만 검사 — v6 신규 인자(decode_jargon/decode_mode/smart_break)에 영향 없음.
#==============================================================================

set -euo pipefail
trap 'echo "{}"; exit 0' ERR

INPUT=$(cat)

TOOL=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null || echo "")
COMMAND=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")

# Only Bash tool
if [ "$TOOL" != "Bash" ]; then
  echo '{}'
  exit 0
fi

# Use env var to pass COMMAND (heredoc + pipe stdin collision fix)
DECISION=$(TG_GUARD_CMD="$COMMAND" python3 <<'PYEOF'
import re, sys, json, os

cmd = os.environ.get("TG_GUARD_CMD", "")

# Extract all Rscript -e "..." or Rscript -e '...' payloads.
pattern_dq = re.compile(r'Rscript\s+(?:--vanilla\s+)?-e\s+"((?:\\.|[^"\\])*)"', re.DOTALL)
pattern_sq = re.compile(r"Rscript\s+(?:--vanilla\s+)?-e\s+'((?:\\.|[^'\\])*)'", re.DOTALL)

payloads = []
payloads.extend(pattern_dq.findall(cmd))
payloads.extend(pattern_sq.findall(cmd))

if not payloads:
    print(json.dumps({}))
    sys.exit(0)

combined = "\n".join(payloads)

# Strict: function name immediately followed by `(` (no space allowed)
direct_calls = []
if re.search(r'\btg_send_rich\(', combined):
    direct_calls.append("tg_send_rich()")
if re.search(r'\btg_send_photo\(', combined):
    direct_calls.append("tg_send_photo()")
# tg_send( standalone (not part of tg_send_rich/photo) — \b ensures boundary
# Use negative lookahead to avoid matching tg_send_rich( or tg_send_photo(
if re.search(r'\btg_send\((?!.)', combined) or re.search(r'\btg_send\([^)]*\)', combined):
    # Confirm it's not tg_send_rich/photo by checking surrounding chars
    # Just check: \btg_send\b followed by \( (not _rich or _photo before \( )
    if re.search(r'\btg_send(?!_rich|_photo)\(', combined):
        if "tg_send()" not in direct_calls:
            direct_calls.append("tg_send()")

has_brief = bool(re.search(r'\btg_agent_brief\(', combined))

if direct_calls and not has_brief:
    detected = ", ".join(direct_calls)
    reason = (
        f"[telegram_direct_call_guard v3] 직접 호출 차단: {detected} — "
        "반드시 tg_agent_brief(agent, title, sections) 단일 진입점 사용. "
        "표 nrow≥2 ncol≥2 + emoji 5+ + sections 4+ + bytes ≥1200 자동 강제. "
        "차트는 charts=c(...) 인자만. 참조: .claude/skills/telegram-protocol/SKILL.md (v4 ENFORCE)."
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason
        }
    }))
else:
    print(json.dumps({}))
PYEOF
) || DECISION='{}'

echo "$DECISION"
