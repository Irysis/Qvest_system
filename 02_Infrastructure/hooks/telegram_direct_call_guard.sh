#!/usr/bin/env bash
# (v8.2.1 HOOK-P0-1) bare python3 → $QVEST_PY_BIN (Windows Store 스텁 fail-open 방지)
if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi
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

export PYTHONUTF8=1  # (v8.1.2) 인코딩 사고 방지 — harness.md "Hook stdout JSON 규율"

INPUT=$(cat)

# ── 빠른 길 (WP4 2026-10-20 · 훅 지연 — 판정 불변) ─────────────────────────────────
# 증명: '{}' 가 아닌 출력은 deny 하나뿐이고, deny 는 Rscript -e 페이로드(해독된 COMMAND 의 부분 문자열)에
#   tg_send_rich( · tg_send_photo( · tg_send( 가 있어야 한다 → 셋 다 'tg_send' 를 담는다. JSON 해독에서
#   영숫자·_ 를 만드는 이스케이프는 \uXXXX 뿐이므로, 원문에 'tg_send' 도 '\u' 도 없으면 해독값에도 없다.
#   그 밖의 모든 가지(Bash 아님 · 페이로드 없음 · 파서 실패 · ERR)는 '{}' 다 → 출력 동일.
# 끄기: QVEST_HOOK_FASTPATH=0 (검사 08_Tests/hooks/test_hook_fastpath_equivalence.sh)
if [ "${QVEST_HOOK_FASTPATH:-1}" != "0" ]; then
  case "$INPUT" in
    *tg_send*|*'\u'*) : ;;
    *) echo '{}'; exit 0 ;;
  esac
fi

TOOL=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_name",""))' 2>/dev/null || echo "")
COMMAND=$(printf '%s' "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_input",{}).get("command",""))' 2>/dev/null || echo "")

# Only Bash tool
if [ "$TOOL" != "Bash" ]; then
  echo '{}'
  exit 0
fi

# Use env var to pass COMMAND (heredoc + pipe stdin collision fix)
DECISION=$(TG_GUARD_CMD="$COMMAND" "$QVEST_PY_BIN" <<'PYEOF'
import re, sys, json, os, shlex

cmd = os.environ.get("TG_GUARD_CMD", "")

# Extract all Rscript -e "..." or Rscript -e '...' payloads.
pattern_dq = re.compile(r'Rscript\s+(?:--vanilla\s+)?-e\s+"((?:\\.|[^"\\])*)"', re.DOTALL)
pattern_sq = re.compile(r"Rscript\s+(?:--vanilla\s+)?-e\s+'((?:\\.|[^'\\])*)'", re.DOTALL)

payloads = []
payloads.extend(pattern_dq.findall(cmd))
payloads.extend(pattern_sq.findall(cmd))

# (2026-11-10 전수점검) 위 두 정규식은 'Rscript' 바로 뒤가 공백이고 -e 가 첫 인자일 때만 본다 — 실제 호출 꼴 대부분이 통과했다
#   (전체 경로 Rscript.exe · --no-save 같은 다른 플래그 · 둘째 -e · R -e · 변수에 담긴 실행기 "$R" -e · timeout 같은 래퍼 · heredoc).
#   종전 정규식은 그대로 두고(막던 것은 계속 막는다), 명령을 따옴표를 지키며 단순 명령으로 가른 뒤 R 실행기로 보이는 명령의
#   -e 인자 전부와 R 로 흘려 넣는 heredoc 본문을 더한다. 빠른 길의 증명은 그대로다(차단에는 여전히 'tg_send' 가 필요하다).
#   남는 한계: 파일에 쓴 뒤 `Rscript 파일.R` 로 돌리는 꼴은 이 훅이 볼 수 없다. 검사: 08_Tests/hooks/test_telegram_guard_forms.sh
def _segments(s):
    out, cur, q, i, n = [], [], None, 0, len(s)
    while i < n:
        c = s[i]
        if q:
            cur.append(c)
            if c == "\\" and q == '"' and i + 1 < n:
                cur.append(s[i + 1]); i += 2; continue
            if c == q: q = None
        elif c in "\"'":
            q = c; cur.append(c)
        elif c == "\\" and i + 1 < n:
            cur.append(c); cur.append(s[i + 1]); i += 2; continue
        elif c in ";|&\n()":
            out.append("".join(cur)); cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return [x for x in out if x.strip()]

_R_NAME = re.compile(r"^(rscript|r)(\.exe)?$", re.I)
_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
def _r_like(tokens):
    for t in tokens:
        if t == "-e": break
        if _R_NAME.match(re.split(r"[\\/]", t)[-1]): return True
    # 실행기가 변수에 담긴 꼴("$R" -e …)은 풀 수 없다 — -e 를 받는 변수 실행기는 R 로 본다
    first = next((t for t in tokens if not _ASSIGN.match(t)), "")
    return first.startswith("$")

def _tokens(seg):          # 단순 명령 → 낱말(따옴표 해석). 따옴표가 안 닫혔으면 None(그 조각은 종전 정규식만 본다)
    try:
        lx = shlex.shlex(seg, posix=True); lx.whitespace_split = True; lx.commenters = ""
        return list(lx)
    except ValueError:
        return None

for _seg in _segments(cmd):
    _toks = _tokens(_seg)
    if not _toks or "-e" not in _toks or not _r_like(_toks): continue
    payloads.extend(_toks[_i + 1] for _i, _t in enumerate(_toks[:-1]) if _t == "-e")

# R 로 흘려 넣는 heredoc(Rscript - <<'EOF' … EOF) — 여는 줄에서 heredoc 을 받는 단순 명령(마지막 조각)이 R 실행기일 때만
#   (파일을 만드는 cat > x.R <<EOF 는 호출이 아니다). 실행기 판정은 위와 같은 _r_like 하나다.
_HEREDOC = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
_lines = cmd.split("\n")
for _k, _ln in enumerate(_lines):
    _m = _HEREDOC.search(_ln)
    _head = _segments(_ln[:_m.start()]) if _m else []
    _toks = _tokens(_head[-1]) if _head else None
    if not _toks or not _r_like(_toks): continue
    _body = []
    for _b in _lines[_k + 1:]:
        if _b.strip() == _m.group(1): break
        _body.append(_b)
    if _body: payloads.append("\n".join(_body))

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
        "반드시 tg_agent_brief(agent, title, sections) 단일 진입점 사용(1계층 v10.01 보고는 "
        "02_Infrastructure/programs/program_report.R::prep_send). 평상 보고는 mute=TRUE. "
        "차트는 이름 붙인 charts=c('무엇을 보는가'=경로). 참조: .claude/skills/qvest-telegram/SKILL.md §0(v10.01)."
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
