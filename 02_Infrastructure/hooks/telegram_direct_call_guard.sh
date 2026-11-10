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
# (v10.2 · 2026-11-10 도훈 결정 HOOK-POWERSHELL-COVERAGE-20261110) PowerShell 도구의 명령도 본다 — 전에는 Bash 도구만 검사해
#   PowerShell 로 내린 직접 호출(Rscript -e "tg_send(...)" 등)이 그대로 통과했다. 판정식은 같다(명령 원문 검사).
if [ "$TOOL" != "Bash" ] && [ "$TOOL" != "PowerShell" ]; then
  echo '{}'
  exit 0
fi

# Use env var to pass COMMAND (heredoc + pipe stdin collision fix)
DECISION=$(TG_GUARD_CMD="$COMMAND" TG_GUARD_TOOL="$TOOL" "$QVEST_PY_BIN" <<'PYEOF'
import re, sys, json, os, shlex

cmd = os.environ.get("TG_GUARD_CMD", "")
tool = os.environ.get("TG_GUARD_TOOL", "")

# Extract all Rscript -e "..." or Rscript -e '...' payloads.
pattern_dq = re.compile(r'Rscript\s+(?:--vanilla\s+)?-e\s+"((?:\\.|[^"\\])*)"', re.DOTALL)
pattern_sq = re.compile(r"Rscript\s+(?:--vanilla\s+)?-e\s+'((?:\\.|[^'\\])*)'", re.DOTALL)

payloads = []
payloads.extend(pattern_dq.findall(cmd))
payloads.extend(pattern_sq.findall(cmd))

def _deny_json(detected):
    reason = (
        f"[telegram_direct_call_guard v3] 직접 호출 차단: {detected} — "
        "반드시 tg_agent_brief(agent, title, sections) 단일 진입점 사용(1계층 v10.01 보고는 "
        "02_Infrastructure/programs/program_report.R::prep_send). 평상 보고는 mute=TRUE. "
        "차트는 이름 붙인 charts=c('무엇을 보는가'=경로). 참조: .claude/skills/qvest-telegram/SKILL.md §0(v10.01)."
    )
    return json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason
        }
    })

# (2026-11-10 재수리) 아래 확장 추출이 예외로 죽으면 셸의 `|| DECISION='{}'` 가 허용으로 바꾼다(fail-open — 자리표 글자 주입으로
#   실제로 났다). 예외는 여기서 받아 fail-closed 로 판정한다: 명령 원문 전체를 페이로드로 보고 직접 호출 + 정본 진입 없음이면 차단.
#   종료 코드 0 으로 끝내야 셸이 판정을 덮지 않는다(os._exit(0)).
def _fail_closed(et, ev, tb):
    import traceback
    try:
        sys.stderr.write("[telegram_direct_call_guard] 확장 추출 예외 — 원문 전체로 fail-closed 판정\n")
        traceback.print_exception(et, ev, tb, file=sys.stderr)
        if re.search(r'\btg_send(?:_rich|_photo)?\(', cmd) and not re.search(r'\btg_agent_brief\(', cmd):
            sys.stdout.write(_deny_json("tg_send*() (추출 예외 · 원문 판정)") + "\n")
        else:
            sys.stdout.write("{}\n")
        sys.stdout.flush()
    finally:
        os._exit(0)
sys.excepthook = _fail_closed

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

def _tokens(seg):          # 단순 명령 → 낱말(따옴표 해석). 따옴표가 안 닫혔으면 None(아래 fail-closed 대체 경로로 간다)
    try:
        lx = shlex.shlex(seg, posix=True); lx.whitespace_split = True; lx.commenters = ""
        return list(lx)
    except ValueError:
        return None

# (2026-11-10 적대적 검토 1차 U8) PowerShell 만의 두 꼴 — 판정 전에 풀어 둔다(Bash 명령은 scan == cmd 로 종전 그대로).
#   ① here-string(@'<개행>…<개행>'@ · @"…"@)은 여러 줄 인자를 넘기는 PowerShell 정식 꼴이다(@'…'@ | Rscript - · Rscript -e @'…'@).
#      본문을 자리표(__qvest_hs_N__)로 바꿔 따옴표가 조각 가르기를 흐리지 않게 하고, 명령 안에 R 실행기가 있으면 본문 전부를 페이로드로 본다
#      (변수에 담았다가 넘기는 $s | Rscript - 도 같은 명령 안이면 잡는다 — 본문을 R 에 넘긴 경로를 추적하지 않는 fail-closed 쪽).
#      ★자리표 치환은 백틱 줄 이음보다 먼저다 — 본문 줄 끝의 백틱은 글자 그대로이고, 먼저 이으면 닫는 '@ 가 줄머리에서 밀려 본문을 놓친다.
#   ② 백틱+개행 = 줄 이음(문법상 한 명령 · 공백 하나로 읽힌다) → 공백으로 잇는다(글자를 지우지 않으니 'tg_send' 를 새로 만들지 않는다 —
#      빠른 길의 증명 불변).
#   (줄끝: 위 COMMAND 는 Windows 파이썬 print 가 LF 를 CRLF 로 바꿔 넘긴다 — 원문 CRLF 는 CR CR LF 로 온다. 그래서 \r* 로 받는다.)
_HERESTR = re.compile(r"@(['\"])[ \t]*\r*\n(.*?)\r*\n\1@", re.DOTALL)
#   (2026-11-10 재수리) 자리표에는 명령 원문에 없는 임의 nonce 를 넣는다 — 고정 글자(__qvest_hs_7__)를 명령에 적으면 _unhs 가
#   없는 번호를 읽다 IndexError 로 죽어 허용이 됐다(fail-open). 범위 밖 번호는 글자 그대로 둔다(이중 방어).
import secrets
_HS_NONCE = secrets.token_hex(8)
while _HS_NONCE in cmd:
    _HS_NONCE = secrets.token_hex(8)
_HS_TOK = re.compile(r"__qvest_hs_" + _HS_NONCE + r"_(\d+)__")
hs_bodies = []
scan = cmd
if tool == "PowerShell":
    def _hs(m):
        hs_bodies.append(m.group(2))
        return " __qvest_hs_%s_%d__ " % (_HS_NONCE, len(hs_bodies) - 1)
    scan = _HERESTR.sub(_hs, scan)
    scan = re.sub(r"`(\r*\n|\r+)", " ", scan)

def _unhs(t):
    def _put(m):
        i = int(m.group(1))
        return hs_bodies[i] if i < len(hs_bodies) else m.group(0)
    return _HS_TOK.sub(_put, t) if hs_bodies else t

def _r_exec(toks):         # here-string 본문을 받을 수 있는 R 실행 — R 이름 낱말 · 또는 변수 실행기($R -e · $R - · $R --vanilla - …)
    if any(_R_NAME.match(re.split(r"[\\/]", t)[-1]) for t in toks): return True
    rest = [t for t in toks if not _ASSIGN.match(t)]
    # (2026-11-10 재수리) 종전은 '-'/'-e' 가 실행기 바로 뒤일 때만 봤다 — `& $R --vanilla -` 가 빠졌다. Bash 갈래의 _r_like 처럼
    #   변수 실행기 뒤 어느 자리든 '-' 또는 '-e' 낱말이 있으면 R 실행으로 본다(fail-closed 쪽).
    return bool(rest) and rest[0].startswith("$") and "=" not in rest[0] and any(t in ("-e", "-") for t in rest[1:])

r_exec_seen = False
for _seg in _segments(scan):
    _toks = _tokens(_seg)
    if _toks is None:
        # 따옴표가 안 닫힌 조각(예: 페이로드 주석 안의 don't) — 건너뛰지 않는다(fail-closed): 따옴표를 뗀 공백 낱말로 R 실행기 · -e 를
        #   보고, 그렇다면 조각 원문 전체를 페이로드로 본다.
        _loose = [t.strip("\"'") for t in _seg.split()]
        if _r_exec(_loose): r_exec_seen = True
        if "-e" in _loose and _r_like(_loose): payloads.append(_unhs(_seg))
        continue
    if _toks and _r_exec(_toks): r_exec_seen = True
    if not _toks or "-e" not in _toks or not _r_like(_toks): continue
    payloads.extend(_unhs(_toks[_i + 1]) for _i, _t in enumerate(_toks[:-1]) if _t == "-e")

if hs_bodies and r_exec_seen:
    payloads.extend(hs_bodies)

# R 로 흘려 넣는 heredoc(Rscript - <<'EOF' … EOF) — 여는 줄에서 heredoc 을 받는 단순 명령(마지막 조각)이 R 실행기일 때만
#   (파일을 만드는 cat > x.R <<EOF 는 호출이 아니다). 실행기 판정은 위와 같은 _r_like 하나다.
_HEREDOC = re.compile(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")
_lines = scan.split("\n")
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
    print(_deny_json(", ".join(direct_calls)))
else:
    print(json.dumps({}))
PYEOF
) || DECISION='{}'

echo "$DECISION"
