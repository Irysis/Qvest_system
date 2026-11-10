#!/usr/bin/env bash
#==============================================================================
# test_telegram_guard_forms.sh — 텔레그램 직접 호출 가드가 실제 호출 꼴을 보는가 (2026-11-10 전수점검)
#
# 지키는 것:
#   telegram_direct_call_guard.sh 는 tg_send · tg_send_rich · tg_send_photo 직접 호출을 막고 tg_agent_brief 단일 진입만 허용한다.
#   그런데 페이로드 추출이 'Rscript' 바로 뒤가 공백이고 -e 가 첫 인자인 꼴만 봐서, 전체 경로 Rscript.exe · 다른 플래그 ·
#   둘째 -e · R -e · 변수 실행기 · heredoc 은 전부 통과했다(아래 10형태 중 수리 전 차단 = D1 · D8 둘뿐).
#
# 축:
#   D  직접 호출 11형태 → deny (D11 = 따옴표가 안 닫힌 조각 · 2026-11-10 적대적 검토 1차 U8)
#   A  [음성] 정본 진입(tg_agent_brief) · R 이 아닌 도구의 -e(grep · sed · 따옴표 안 닫힌 grep) · 파일 만들기 · 문자열 리터럴 → allow
#   M  [위반 주입] 새 추출부를 끈 사본은 D2~D7 · D9 · D10 을 통과시킨다(= 수리 전 상태를 이 시험이 본다) ·
#      M3 토큰화 실패 조각의 fail-closed 줄을 뗀 사본은 D11 을 통과시킨다
#   (PowerShell 꼴 — here-string · 백틱 줄 이음 — 은 test_hook_powershell_coverage.sh 의 T · H 축이 본다)
#   L  [한계 기록] 파일에 쓴 뒤 Rscript 파일.R 로 돌리는 꼴은 이 훅이 볼 수 없다(allow 가 현재 사실 — 바뀌면 이 칸을 고친다)
#
# 격리: 훅은 판정 JSON 만 낸다. 발송 없음.
#==============================================================================
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
command -v cygpath >/dev/null 2>&1 && ROOT="$(cygpath -m "$ROOT")"
HOOK="$ROOT/02_Infrastructure/hooks/telegram_direct_call_guard.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS  $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL  $1 — $2"; }
finish() {
  echo "=== 결과: PASS=$PASS FAIL=$FAIL ==="
  printf '{"test":"telegram_guard_forms","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
  [ "$FAIL" = "0" ] || exit 1
  exit 0
}
[ -f "$HOOK" ] || { ng "0 훅 원본" "없음"; finish; }
QVEST_PARSE_TRAP=caller; QVEST_PARSE_RESOLVE_ONLY=1
# shellcheck source=/dev/null
source "$ROOT/02_Infrastructure/hooks/_shared_parse.sh" 2>/dev/null; unset QVEST_PARSE_RESOLVE_ONLY QVEST_PARSE_TRAP
PY="${QVEST_PY_BIN:-python}"
T="$(mktemp -d 2>/dev/null || echo "/tmp/tgforms_$$")"; mkdir -p "$T"
command -v cygpath >/dev/null 2>&1 && T="$(cygpath -m "$T")"
trap 'rm -rf "$T" 2>/dev/null' EXIT

# verdict <hook> <command-text> → deny | allow | ?
verdict() {
  local hook="$1" c="$2"
  TGF_CMD="$c" "$PY" -X utf8 -c 'import json,os,sys
sys.stdout.buffer.write(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["TGF_CMD"]},"hook_event_name":"PreToolUse"},ensure_ascii=False).encode("utf-8"))' \
    | bash "$hook" 2>/dev/null | "$PY" -X utf8 -c 'import json,sys
s=sys.stdin.buffer.read().decode("utf-8","replace").strip()
try: d=json.loads(s.splitlines()[-1]) if s else {}
except Exception: d={"_raw":1}
h=d.get("hookSpecificOutput") or {}
v=d.get("decision") or h.get("permissionDecision") or ("allow" if d=={} else "?")
print("deny" if v in ("block","deny") else v)'
}
expect() {  # expect <want> <label> <hook> <command>
  local want="$1" label="$2" hook="$3" c="$4" got
  got="$(verdict "$hook" "$c")"
  [ "$got" = "$want" ] && ok "$label → $got" || ng "$label" "기대 $want · 실제 $got"
}
NL=$'\n'
D1="Rscript -e \"tg_send('x')\""
D2="\"/c/Program Files/R/R-4.6.2/bin/Rscript.exe\" -e \"tg_send('x')\""
D3="Rscript --no-save -e \"tg_send('x')\""
D4="Rscript --vanilla --no-init-file -e 'tg_send_rich(\"x\")'"
D5="Rscript -e \"x <- 1\" -e \"tg_send('x')\""
D6="R --slave -e \"tg_send_photo('p.png')\""
D7="R=\"/c/Program Files/R/R-4.6.2/bin/Rscript.exe\"; \"\$R\" -e \"tg_send('x')\""
D8="cd /tmp && timeout 60 Rscript -e \"tg_send('x')\""
D9="Rscript - <<'EOF'${NL}source(\"02_Infrastructure/telegram/telegram_notify.R\")${NL}tg_send(\"x\")${NL}EOF"
D10="Rscript.exe -e \"tg_send('x')\""
# D11 (2026-11-10 적대적 검토 1차 U8) — 종전 정규식이 못 보는 꼴(--no-save) + 꼬리 주석의 홀수 작은따옴표 → shlex 실패로 그 조각을
#   건너뛰어 통과했다. 이제 토큰화 실패 조각은 공백 낱말로 R 실행기 · -e 를 보고 조각 원문 전체를 페이로드로 본다(fail-closed).
D11="Rscript --no-save -e \"tg_send('x')\" # it's"

echo "== D 직접 호출 10형태 =="
expect deny "D1 Rscript -e (기준선 — 수리 전에도 막던 꼴)"   "$HOOK" "$D1"
expect deny "D2 전체 경로 Rscript.exe(따옴표)"                "$HOOK" "$D2"
expect deny "D3 다른 플래그(--no-save) 뒤 -e"                 "$HOOK" "$D3"
expect deny "D4 플래그 둘 + 작은따옴표 페이로드"              "$HOOK" "$D4"
expect deny "D5 둘째 -e 에 든 호출"                           "$HOOK" "$D5"
expect deny "D6 R --slave -e"                                 "$HOOK" "$D6"
expect deny "D7 변수에 담긴 실행기 \"\$R\" -e"                "$HOOK" "$D7"
expect deny "D8 래퍼(timeout) 뒤 Rscript"                     "$HOOK" "$D8"
expect deny "D9 R 로 흘려 넣는 heredoc"                       "$HOOK" "$D9"
expect deny "D10 Rscript.exe -e"                              "$HOOK" "$D10"
expect deny "D11 따옴표가 안 닫힌 조각(꼬리 주석 it's)의 -e 호출" "$HOOK" "$D11"

echo "== A 음성 =="
expect allow "A1 정본 진입 tg_agent_brief"                    "$HOOK" "Rscript -e \"tg_agent_brief(agent='Q-Lead', title='t', sections=list())\""
expect allow "A2 변수 실행기 + 정본 진입(같은 페이로드에 tg_send 가 있어도 면제 — 종전 규칙)" "$HOOK" "\"\$R\" -e \"source('02_Infrastructure/telegram/telegram_notify.R'); tg_agent_brief('Q-Lead','t',list()); tg_send('x')\""
expect allow "A3 grep -e 로 코드 검색"                        "$HOOK" "grep -rn -e 'tg_send(' 02_Infrastructure"
expect allow "A4 grep -R -e (-R 플래그는 R 실행기가 아니다)"  "$HOOK" "grep -R -e \"tg_send(\" ."
expect allow "A5 sed -e"                                      "$HOOK" "sed -n -e '/tg_send(/p' 02_Infrastructure/telegram/telegram_notify.R"
expect allow "A6 파일 만들기 heredoc(호출 아님)"              "$HOOK" "cat > /tmp/x.R <<'EOF'${NL}tg_send(\"x\")${NL}EOF"
expect allow "A7 echo 리터럴 + 깨끗한 R 페이로드"             "$HOOK" "echo \"tg_send(\" ; Rscript -e 'cat(1)'"
expect allow "A8 tg_send 가 없는 R 호출"                      "$HOOK" "\"\$R\" --no-save -e \"cat(1)\" -e \"print(2)\""
expect allow "A9 따옴표가 안 닫힌 조각이라도 R 실행기가 아니면(grep -e) 허용" "$HOOK" "grep -rn -e \"tg_send(\" 02_Infrastructure # it's"

echo "== M 위반 주입 — 새 추출부를 끈 사본 =="
MUT="$T/telegram_direct_call_guard_mut.sh"
"$PY" -X utf8 -c 'import io,sys
s=io.open(sys.argv[1],encoding="utf-8",newline="").read()
a="    if not _toks or \"-e\" not in _toks or not _r_like(_toks): continue"
b="    if not _toks or not _r_like(_toks): continue"
n=s.count(a)+s.count(b)
io.open(sys.argv[2],"w",encoding="utf-8",newline="").write(s.replace(a,"    continue").replace(b,"    continue"))
sys.exit(0 if n==2 else 1)' "$HOOK" "$MUT" && ok "M0 돌연변이 대상 2줄 치환" || ng "M0 돌연변이 치환" "대상 줄 수가 2가 아님"
expect deny  "M1 돌연변이도 기준선 꼴(D1)은 막는다(종전 정규식 유지)"  "$MUT" "$D1"
expect deny  "M1 래퍼 꼴(D8)도 종전 정규식이 막는다('Rscript -e' 가 그대로 이어지는 꼴)" "$MUT" "$D8"
miss=0
for c in "$D2" "$D3" "$D4" "$D5" "$D6" "$D7" "$D9" "$D10"; do [ "$(verdict "$MUT" "$c")" = "allow" ] && miss=$((miss+1)); done
[ "$miss" = "8" ] && ok "M2 돌연변이는 D2~D7 · D9 · D10 8형태를 전부 통과시킨다 — D 축이 이것을 잡는다" || ng "M2 돌연변이 검출" "통과 $miss/8"
MUT3="$T/telegram_direct_call_guard_mut3.sh"
"$PY" -X utf8 -c 'import io,sys
s=io.open(sys.argv[1],encoding="utf-8",newline="").read()
a="        if \"-e\" in _loose and _r_like(_loose): payloads.append(_unhs(_seg))"
n=s.count(a)
io.open(sys.argv[2],"w",encoding="utf-8",newline="").write(s.replace(a,"        pass"))
sys.exit(0 if n==1 else 1)' "$HOOK" "$MUT3" && ok "M3a 돌연변이 대상(토큰화 실패 조각의 fail-closed 줄) 1줄 치환" || ng "M3a 돌연변이 치환" "대상 줄 수가 1이 아님"
expect allow "M3 토큰화 실패 조각을 건너뛰는(수리 전) 사본은 D11 을 통과시킨다 — D11 이 잡는다" "$MUT3" "$D11"

echo "== L 한계 기록 =="
expect allow "L 파일로 돌리는 꼴(Rscript 파일.R)은 볼 수 없다 — 현재 사실" "$HOOK" "Rscript /tmp/send_direct.R"

finish
