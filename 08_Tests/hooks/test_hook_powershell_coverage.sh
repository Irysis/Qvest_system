#!/usr/bin/env bash
#==============================================================================
# test_hook_powershell_coverage.sh — 차단 훅이 PowerShell 도구의 명령도 보는가 (2026-11-10 · 도훈 결정 HOOK-POWERSHELL-COVERAGE-20261110)
#
# 지키는 것:
#   safety_guard.sh(생산 폴더 쓰기 · 경로 정규화 함수) 와 telegram_direct_call_guard.sh(텔레그램 직접 호출)는 전에는 Bash 도구의
#   명령만 검사했다 — PowerShell 도구로 내린 같은 명령은 그대로 통과했다. 등록(.claude/settings.json 의 PowerShell 대응)과
#   두 훅의 도구 분기를 함께 고쳤다. 이 시험은 그 셋(등록 · 안전 가드 · 텔레그램 가드)을 본다.
#
# ★입력 모양(2026-11-10 적대적 검토 1차 U8 수리): 훅 입력은 Claude Code 가 실제로 내는 압축 JSON 한 줄이다(구분자 "," ":" ·
#   session_id · transcript_path · cwd · permission_mode · tool_use_id 포함). 구판은 json.dumps 기본 구분자(": ")로 만들어 빠른 길의
#   '"tool_name":"' 정규식이 늘 빗나가 — 모든 사례가 느린 길에서만 판정됐다(빠른 길의 판정 차이를 원리상 볼 수 없었다).
#   이제 사례마다 빠른 길 켬(QVEST_HOOK_FASTPATH=1 · 운영 기본값) · 끔(=0) 두 판정을 모두 단언하고, F 축이 빠른 길을 실제로 탔음을
#   스파이 해석기(파이썬 호출 수)로 단정한다.
#
# 축:
#   R  등록 — settings.json 의 PreToolUse 에 PowerShell 대응이 있고 Bash 대응과 같은 두 가드를 태운다
#   F  빠른 길 실재 — 무해한 PowerShell 압축 입력: 켬 = 파이썬 0회 · 끔 = 1회 이상(입력 모양이 운영과 같다는 실증)
#   S  안전 가드 × PowerShell — 생산 폴더 쓰기(cmdlet · 별칭 · 리디렉션 · 소문자/혼합 표기 경로 · 백틱 줄 이음) = 차단 ·
#      읽기(Get-Content · Select-String · Format-Hex · 낱말 안의 rm) = 허용 · 경로 정규화 함수 = 차단 · 무관한 명령 = 허용
#   T  텔레그램 가드 × PowerShell — 직접 호출(백틱 줄 이음 포함) = 차단 · 정본 진입(tg_agent_brief) = 허용
#   H  텔레그램 가드 × PowerShell here-string — @'…'@ | Rscript - · Rscript -e @'…'@(본문 홀수 작은따옴표) · @"…"@ · CRLF ·
#      본문 줄 끝 백틱 = 차단 · 정본 진입 · 커밋 메시지 · 파일 쓰기 = 허용
#   B  [대조] 같은 명령의 Bash 판정은 그대로다(생산 폴더 쓰기 = 차단 · 읽기 = 허용)
#   L  [한계 기록] Bash 갈래 · Write/Edit 는 대소문자를 구분한다(소문자 경로 = 허용이 현재 사실 — 범위 밖 · 바뀌면 이 칸을 고친다)
#   M  [위반 주입] 수리를 하나씩 되돌린 사본은 그 수리를 재는 사례를 뒤집는다(치환 성사 단정 · 소스 텍스트 치환)
#      M1 · M2 PowerShell 분기 떼기 · M3 별칭 낱말 경계 떼기(Bash 판 정규식) → S10 · M4 빠른 길 소문자 재검사 떼기 → S13 켬 ·
#      M5 백틱 줄 이음 떼기 → S16 · M6 here-string 추출 떼기 → H1 · M7 텔레그램 백틱 줄 이음 떼기 → T5 ·
#      (재수리) M8 · M9 추출 예외 갈무리(fail-closed) → H6 · M10 변수 실행기 플래그 뒤 '-' → H8 · M11 고정 자리표(수리 전 꼴) → H7
#
# 격리: 훅은 판정 JSON 만 낸다. 임시 루트(CLAUDE_PROJECT_DIR · QM_ROOT = 임시 폴더 · QVEST_EVENT_LEDGER=0)에서 돌려 운영 원장에
#   쓰지 않는다. 파일 쓰기 · 발송 없음.
#==============================================================================
set -u
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
command -v cygpath >/dev/null 2>&1 && ROOT="$(cygpath -m "$ROOT")"
SG="$ROOT/02_Infrastructure/hooks/safety_guard.sh"
TG="$ROOT/02_Infrastructure/hooks/telegram_direct_call_guard.sh"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  PASS  $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL  $1 — $2"; }
finish() {
  echo "=== 결과: PASS=$PASS FAIL=$FAIL ==="
  printf '{"test":"hook_powershell_coverage","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
  [ "$FAIL" = "0" ] || exit 1
  exit 0
}
[ -f "$SG" ] && [ -f "$TG" ] || { ng "0 훅 원본" "없음"; finish; }
QVEST_PARSE_TRAP=caller; QVEST_PARSE_RESOLVE_ONLY=1
# shellcheck source=/dev/null
source "$ROOT/02_Infrastructure/hooks/_shared_parse.sh" 2>/dev/null; unset QVEST_PARSE_RESOLVE_ONLY QVEST_PARSE_TRAP
PY="${QVEST_PY_BIN:-python}"
T="$(mktemp -d 2>/dev/null || echo "/tmp/pscov_$$")"; mkdir -p "$T"
command -v cygpath >/dev/null 2>&1 && T="$(cygpath -m "$T")"
trap 'rm -rf "$T" 2>/dev/null' EXIT
unset QVEST_UNATTENDED_LANE QVEST_CLEAN_LANE
mkdir -p "$T/proj"
# 스파이 해석기 — 호출 1회 = 줄 1개(빠른 길을 탔는지 = 파이썬 0회)
SPY="$T/spy_python.sh"
printf '#!/usr/bin/env bash\necho call >> "${PSC_SPY_LOG:-/dev/null}"\nexec "%s" "$@"\n' "$PY" > "$SPY"
chmod +x "$SPY"

# run1 <hook> <tool> <command-text> <fast 0|1> → "<deny|allow|?> <파이썬 호출 수>"
run1() {
  local hook="$1" tool="$2" c="$3" fast="$4" lg="$T/spy.log" dec n
  rm -f "$lg"
  PSC_TOOL="$tool" PSC_CMD="$c" "$PY" -X utf8 -c 'import json,os,sys
d={"session_id":"pscov-test","transcript_path":"C:\\x\\t.jsonl","cwd":"C:\\x","permission_mode":"acceptEdits",
   "hook_event_name":"PreToolUse","tool_name":os.environ["PSC_TOOL"],
   "tool_input":{"command":os.environ["PSC_CMD"],"description":"d"},"tool_use_id":"toolu_pscov"}
sys.stdout.buffer.write(json.dumps(d,ensure_ascii=False,separators=(",",":")).encode("utf-8"))' > "$T/in.json"
  ( cd "$T/proj" && env -u QVEST_UNATTENDED_LANE -u QVEST_CLEAN_LANE CLAUDE_PROJECT_DIR="$T/proj" QM_ROOT="$T/proj" \
      QVEST_EVENT_LEDGER=0 QVEST_HOOK_FASTPATH="$fast" QVEST_PY_BIN="$SPY" QVEST_PY="$SPY" PSC_SPY_LOG="$lg" \
      bash "$hook" < "$T/in.json" 2>/dev/null ) > "$T/out.txt"
  dec="$("$PY" -X utf8 -c 'import json,sys
t=open(sys.argv[1],"rb").read().decode("utf-8","replace").strip()
try:
    d=json.loads(t.splitlines()[-1]) if t else {}
except Exception:
    print("?"); sys.exit(0)
dec=str(d.get("decision","")) or str((d.get("hookSpecificOutput") or {}).get("permissionDecision",""))
print("deny" if dec in ("block","deny") else ("allow" if d=={} or dec in ("","allow") else "?"))' "$T/out.txt")"
  n=0; [ -f "$lg" ] && n="$(wc -l < "$lg" | tr -d ' ')"
  printf '%s %s' "$dec" "$n"
}
verdict() { local r; r="$(run1 "$1" "$2" "$3" "${4:-1}")"; printf '%s' "${r%% *}"; }
# expect <이름> <기대> <hook> <tool> <명령> — 빠른 길 켬(운영 기본값) · 끔 두 판정이 모두 기대와 같아야 한다
expect() {
  local on off
  on="$(verdict "$3" "$4" "$5" 1)"; off="$(verdict "$3" "$4" "$5" 0)"
  if [ "$on" = "$2" ] && [ "$off" = "$2" ]; then ok "$1"; else ng "$1" "기대 $2 · 켬 $on · 끔 $off"; fi
}
P="05_""Production"; NP="normalize""Path"   # 이 파일의 원문에 보호 낱말을 통째로 두지 않는다(이 시험을 돌리는 명령이 가드에 걸리지 않게)
PL="05_""production"; PU="05_""PRODUCTION"
NL=$'\n'; CRLF=$'\r\n'; BT='`'

echo "=== R. 등록 ==="
REG="$("$PY" -X utf8 -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8-sig"))
pre=d["hooks"]["PreToolUse"]
g=lambda m:[h["command"].split("/")[-1].rstrip("\"") for e in pre if e.get("matcher")==m for h in e.get("hooks",[])]
b,p=g("Bash"),g("PowerShell")
print("ok" if p and b==p and any("safety_guard.sh" in x for x in p) and any("telegram_direct_call_guard.sh" in x for x in p) else "bad:%s|%s"%(b,p))' "$ROOT/.claude/settings.json" 2>/dev/null)"
[ "$REG" = "ok" ] && ok "R1 settings.json — PowerShell 대응이 Bash 대응과 같은 두 가드를 태운다" || ng "R1 등록" "$REG"

echo "=== F. 빠른 길 실재(운영 입력 모양) ==="
for pair in "SG|Get-ScheduledTask -TaskName 'Qvest_*' | Format-Table" "TG|Get-Process | Select-Object -First 3"; do
  k="${pair%%|*}"; c="${pair#*|}"; h="$SG"; [ "$k" = "TG" ] && h="$TG"
  r_on="$(run1 "$h" PowerShell "$c" 1)"; r_off="$(run1 "$h" PowerShell "$c" 0)"
  if [ "$r_on" = "allow 0" ] && [ "${r_off%% *}" = "allow" ] && [ "${r_off##* }" -ge 1 ] 2>/dev/null; then
    ok "F[$k] 압축 JSON PowerShell 입력이 빠른 길을 탄다 — 켬 파이썬 0회 · 끔 ${r_off##* }회"
  else ng "F[$k] 빠른 길 실재" "켬=($r_on) 끔=($r_off) — 켬 'allow 0' · 끔 파이썬 ≥1 이어야"; fi
done

echo "=== S. 안전 가드 × PowerShell ==="
expect "S1 Copy-Item → 생산 폴더 = 차단" deny "$SG" PowerShell "Copy-Item .\\x.R -Destination .\\$P\\x.R"
expect "S2 Set-Content 생산 폴더 = 차단" deny "$SG" PowerShell "Set-Content -Path \"$P/a.txt\" -Value 1"
expect "S3 Remove-Item 생산 폴더 = 차단" deny "$SG" PowerShell "Remove-Item -Recurse -Force $P\\old"
expect "S4 별칭 rm = 차단" deny "$SG" PowerShell "rm $P\\x.R"
expect "S5 리디렉션 > = 차단" deny "$SG" PowerShell "'x' > $P\\x.txt"
expect "S6 Out-File = 차단" deny "$SG" PowerShell "Get-Date | Out-File -FilePath $P\\stamp.txt"
expect "S7 소문자 cmdlet(대소문자 무시) = 차단" deny "$SG" PowerShell "move-item a.txt $P\\a.txt"
expect "S8 읽기 Get-Content = 허용" allow "$SG" PowerShell "Get-Content $P\\model.R -TotalCount 5"
expect "S9 읽기 Select-String = 허용" allow "$SG" PowerShell "Select-String -Path $P\\*.R -Pattern 'alpha'"
# S10 — 별칭 낱말(rm)이 경로 *앞* 낱말 안에 있어야 낱말 경계를 잰다(Format-Hex 의 'rm' · term_list 의 'rm'). 경계 없는 Bash 판
#   정규식 (>|mv|cp|rm).*경로 는 이것을 차단한다(M3 이 그 차이를 실증한다).
S10C="Format-Hex -Path .\\term_list.txt, $P\\x.R -Count 16"
expect "S10 읽기 Format-Hex(경로 앞 낱말 안의 rm 에 걸리지 않는다) = 허용" allow "$SG" PowerShell "$S10C"
expect "S11 경로 정규화 함수 = 차단" deny "$SG" PowerShell "Rscript -e \"$NP('x')\""
expect "S12 무관한 명령 = 허용" allow "$SG" PowerShell "Get-ScheduledTask -TaskName 'Qvest_*' | Format-Table"
S13C="Remove-Item $PL\\x.R"
expect "S13 소문자 경로 Remove-Item(Windows 는 경로 대소문자 무시) = 차단" deny "$SG" PowerShell "$S13C"
expect "S14 대문자 경로 Copy-Item = 차단" deny "$SG" PowerShell "Copy-Item a.R .\\$PU\\a.R"
expect "S15 소문자 경로 읽기 Get-Content = 허용(오탐 없음)" allow "$SG" PowerShell "Get-Content $PL\\x.R -TotalCount 3"
S16C="Copy-Item a.R ${BT}${NL}  -Destination .\\$P\\a.R"
expect "S16 백틱 줄 이음(LF)으로 동사와 경로를 가른 쓰기 = 차단" deny "$SG" PowerShell "$S16C"
expect "S17 백틱 줄 이음(CRLF) = 차단" deny "$SG" PowerShell "Move-Item a.R ${BT}${CRLF}  $P\\a.R"
expect "S18 개행(줄 이음 아님)으로 갈린 두 명령(쓰기 · 생산 폴더 읽기) = 허용(명령 경계 유지)" allow "$SG" PowerShell "Copy-Item a.R b.R${NL}Get-Content $P\\x.R"
expect "S19 백틱 줄 이음 읽기 = 허용" allow "$SG" PowerShell "Get-ChildItem ${BT}${NL}  $P -Filter *.R"
expect "S20 소문자 경로 + 백틱 줄 이음 쓰기 = 차단" deny "$SG" PowerShell "Set-Content ${BT}${NL}  -Path $PL\\a.txt -Value 1"

echo "=== T. 텔레그램 가드 × PowerShell ==="
expect "T1 Rscript -e 직접 호출 = 차단" deny "$TG" PowerShell "Rscript -e \"source('02_Infrastructure/telegram/telegram_notify.R'); tg_send('x')\""
expect "T2 tg_send_photo 직접 호출 = 차단" deny "$TG" PowerShell "& Rscript.exe -e \"tg_send_photo('a.png')\""
expect "T3 정본 진입 tg_agent_brief = 허용" allow "$TG" PowerShell "Rscript -e \"tg_agent_brief(agent = 'Q-Lead', title = 't', sections = list())\""
expect "T4 무관한 명령 = 허용" allow "$TG" PowerShell "Get-Process | Select-Object -First 3"
T5C="Rscript ${BT}${NL}  -e \"tg_send('x')\""
expect "T5 백틱 줄 이음으로 Rscript 와 -e 를 가른 직접 호출 = 차단" deny "$TG" PowerShell "$T5C"

echo "=== H. 텔레그램 가드 × PowerShell here-string ==="
H1C="@'${NL}source(\"a.R\"); tg_send(\"x\")${NL}'@ | Rscript -"
expect "H1 @'…'@ | Rscript - = 차단" deny "$TG" PowerShell "$H1C"
expect "H2 Rscript -e @'…'@(본문 주석에 홀수 작은따옴표 don't) = 차단" deny "$TG" PowerShell "Rscript -e @'${NL}source('a.R') # don't${NL}tg_send(\"x\")${NL}'@"
expect "H3 @\"…\"@ 를 변수에 담아 | Rscript - = 차단" deny "$TG" PowerShell "\$code = @\"${NL}tg_send_photo('p.png')${NL}\"@${NL}\$code | Rscript -"
expect "H4 CRLF here-string | & Rscript.exe - = 차단" deny "$TG" PowerShell "@'${CRLF}tg_send(\"x\")${CRLF}'@ | & \"C:\\Program Files\\R\\R-4.6.2\\bin\\Rscript.exe\" -"
expect "H5 본문 줄 끝 백틱(글자 그대로) here-string = 차단" deny "$TG" PowerShell "@'${NL}tg_send(\"x\") #${BT}${NL}'@ | Rscript -"
expect "H6 변수 실행기 \$R -e @'…'@ = 차단" deny "$TG" PowerShell "\$R -e @'${NL}tg_send_rich(\"x\")${NL}'@"
H7C="@'${NL}x${NL}'@ | Out-Null; Rscript -e \"tg_send('x') __qvest_hs_7__\""
expect "H7 자리표 글자(__qvest_hs_7__)를 명령에 적은 직접 호출 = 차단(재수리 — 전엔 IndexError 로 허용)" deny "$TG" PowerShell "$H7C"
H8C="@'${NL}tg_send(\"x\")${NL}'@ | & \$R --vanilla -"
expect "H8 변수 실행기 + 플래그 뒤 '-'(@'…'@ | & \$R --vanilla -) = 차단(재수리 — Bash 의 \"\$R\" --vanilla - <<EOF 와 같게)" deny "$TG" PowerShell "$H8C"
expect "H9 [대조] 같은 꼴 Bash heredoc \"\$R\" --vanilla - = 차단" deny "$TG" Bash "\"\$R\" --vanilla - <<'EOF'${NL}tg_send(\"x\")${NL}EOF"
expect "HA4 here-string 커밋 메시지 + 변수 -replace(R 실행 아님) = 허용(변수 실행기 확장의 오탐 없음)" allow "$TG" PowerShell "git commit -m @'${NL}fix: tg_send( 막기${NL}'@; \$p = 'a'; \$p -replace 'a','b'"
expect "HA1 here-string 정본 진입 tg_agent_brief = 허용" allow "$TG" PowerShell "@'${NL}tg_agent_brief('Q-Lead','t',list())${NL}'@ | Rscript -"
expect "HA2 커밋 메시지 here-string 의 tg_send( 글자 = 허용(R 실행 없음)" allow "$TG" PowerShell "git commit -m @'${NL}fix: tg_send( 직접 호출 막기${NL}'@"
expect "HA3 here-string 을 파일로 쓰기 = 허용(호출 아님 — Bash 의 cat > x.R <<EOF 와 같다)" allow "$TG" PowerShell "@'${NL}tg_send(\"x\")${NL}'@ | Set-Content x.R"

echo "=== B. [대조] Bash 판정은 그대로 ==="
expect "B1 Bash cp → 생산 폴더 = 차단" deny "$SG" Bash "cp x.R $P/x.R"
expect "B2 Bash 읽기 = 허용" allow "$SG" Bash "ls 02_Infrastructure | head -3"
expect "B3 Bash 텔레그램 직접 호출 = 차단" deny "$TG" Bash "Rscript -e \"tg_send('x')\""

echo "=== L. [한계 기록] 대소문자 구분 갈래 ==="
expect "L1 Bash 소문자 경로 cp = 허용(Bash 갈래는 대소문자 구분 — 현재 사실 · 범위 밖)" allow "$SG" Bash "cp x.R $PL/x.R"

echo "=== M. [위반 주입] 수리를 하나씩 되돌린 사본 ==="
# mut <id> <원본 훅 파일> <찾을 원문> <바꿀 글> → 사본 경로(stdout) · 치환 수는 $T/mut_<id>.n
mut() {
  local id="$1" src="$2" d="$T/mut_$1"
  mkdir -p "$d"; cp "$ROOT/02_Infrastructure/hooks/"*.sh "$d/" 2>/dev/null
  MUT_A="$3" MUT_B="$4" "$PY" -X utf8 -c 'import io,os,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8",newline="").read()
a,b=os.environ["MUT_A"],os.environ["MUT_B"]
print(s.count(a)); s=s.replace(a,b)
io.open(p,"w",encoding="utf-8",newline="").write(s)' "$d/$(basename "$src")" > "$T/mut_$id.n" 2>/dev/null
  printf '%s' "$d/$(basename "$src")"
}
mn() { tr -d '\r\n' < "$T/mut_$1.n"; }
M="$(mut m1 "$SG" 'if [ "$TOOL_NAME" = "Bash" ] || [ "$TOOL_NAME" = "PowerShell" ]; then' 'if [ "$TOOL_NAME" = "Bash" ]; then')"
r="$(verdict "$M" PowerShell "Copy-Item .\\x.R -Destination .\\$P\\x.R")"
[ "$(mn m1)" = "1" ] && [ "$r" = "allow" ] && ok "M1 안전 가드의 PowerShell 분기를 떼면 생산 폴더 쓰기가 통과한다(치환 1곳 성사) — S1 이 그 차이를 본다" || ng "M1" "치환 $(mn m1) · 판정 $r"
M="$(mut m2 "$TG" 'if [ "$TOOL" != "Bash" ] && [ "$TOOL" != "PowerShell" ]; then' 'if [ "$TOOL" != "Bash" ]; then')"
r="$(verdict "$M" PowerShell "Rscript -e \"tg_send('x')\"")"
[ "$(mn m2)" = "1" ] && [ "$r" = "allow" ] && ok "M2 텔레그램 가드의 PowerShell 분기를 떼면 직접 호출이 통과한다(치환 1곳 성사) — T1 이 그 차이를 본다" || ng "M2" "치환 $(mn m2) · 판정 $r"
M="$(mut m3 "$SG" '(^|[^A-Za-z-])(mv|cp|rm|del|ren|move|copy|ni|sc|ac|rd|rmdir|md|mkdir)([^A-Za-z-]|$)' '(mv|cp|rm|del|ren|move|copy|ni|sc|ac|rd|rmdir|md|mkdir)')"
r1="$(verdict "$M" PowerShell "$S10C" 1)"; r0="$(verdict "$M" PowerShell "$S10C" 0)"
[ "$(mn m3)" = "1" ] && [ "$r1" = "deny" ] && [ "$r0" = "deny" ] && ok "M3 별칭 낱말 경계를 뗀(Bash 판) 사본은 S10 을 차단한다(치환 1곳) — S10 이 경계를 잰다" || ng "M3" "치환 $(mn m3) · 켬 $r1 · 끔 $r0"
M="$(mut m4 "$SG" 'if _qsg_fast_fields && _qsg_fast_ps_clear; then' 'if _qsg_fast_fields; then')"
r1="$(verdict "$M" PowerShell "$S13C" 1)"; r0="$(verdict "$M" PowerShell "$S13C" 0)"
[ "$(mn m4)" = "1" ] && [ "$r1" = "allow" ] && [ "$r0" = "deny" ] && ok "M4 빠른 길 소문자 재검사를 뗀 사본은 S13 을 켬에서만 허용한다(켬 allow · 끔 deny · 치환 1곳) — S13 의 켬/끔 단언이 잡는다" || ng "M4" "치환 $(mn m4) · 켬 $r1 · 끔 $r0"
M="$(mut m5 "$SG" '    _qsg_psjoin            # (U8)' '    :            # (U8)')"
r1="$(verdict "$M" PowerShell "$S16C" 1)"; r0="$(verdict "$M" PowerShell "$S16C" 0)"
[ "$(mn m5)" = "1" ] && [ "$r1" = "allow" ] && [ "$r0" = "allow" ] && ok "M5 백틱 줄 이음을 뗀 사본은 S16 을 통과시킨다(치환 1곳) — S16 이 잡는다" || ng "M5" "치환 $(mn m5) · 켬 $r1 · 끔 $r0"
M="$(mut m6 "$TG" '    scan = _HERESTR.sub(_hs, scan)' '    pass')"
r="$(verdict "$M" PowerShell "$H1C")"
[ "$(mn m6)" = "1" ] && [ "$r" = "allow" ] && ok "M6 here-string 추출을 뗀 사본은 H1 을 통과시킨다(치환 1곳) — H1 이 잡는다" || ng "M6" "치환 $(mn m6) · 판정 $r"
M="$(mut m7 "$TG" '    scan = re.sub(r"`(\r*\n|\r+)", " ", scan)' '    pass')"
r="$(verdict "$M" PowerShell "$T5C")"
[ "$(mn m7)" = "1" ] && [ "$r" = "allow" ] && ok "M7 텔레그램 가드의 백틱 줄 이음을 뗀 사본은 T5 를 통과시킨다(치환 1곳) — T5 가 잡는다" || ng "M7" "치환 $(mn m7) · 판정 $r"
# M8 · M9 — 확장 추출 예외의 fail-closed(재수리): 자리표 복원에 예외를 주입한 사본은 차단을 지키고(예외 갈무리) · 깨끗한 명령은 허용한다.
#   갈무리까지 뗀 사본은 같은 입력을 허용으로 떨어뜨린다(셸의 || DECISION='{}') — 갈무리가 그 차이를 만든다는 실증.
H6C="\$R -e @'${NL}tg_send_rich(\"x\")${NL}'@"
M="$(mut m8 "$TG" '    return _HS_TOK.sub(_put, t) if hs_bodies else t' '    raise RuntimeError("m8 injected")')"
r="$(verdict "$M" PowerShell "$H6C")"; rc="$(verdict "$M" PowerShell "\$R -e @'${NL}cat(1)${NL}'@")"
[ "$(mn m8)" = "1" ] && [ "$r" = "deny" ] && [ "$rc" = "allow" ] && ok "M8 추출 예외를 주입한 사본도 H6 을 차단하고 깨끗한 R 호출은 허용한다(치환 1곳 · fail-closed 갈무리)" || ng "M8" "치환 $(mn m8) · H6 $r · 깨끗 $rc"
M8F="$M"
M9A="$(MUT_A='sys.excepthook = _fail_closed' MUT_B='pass' "$PY" -X utf8 -c 'import io,os,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8",newline="").read(); a,b=os.environ["MUT_A"],os.environ["MUT_B"]
print(s.count(a)); io.open(p,"w",encoding="utf-8",newline="").write(s.replace(a,b))' "$M8F" 2>/dev/null | tr -d '\r\n')"
r="$(verdict "$M8F" PowerShell "$H6C")"
[ "$M9A" = "1" ] && [ "$r" = "allow" ] && ok "M9 갈무리(excepthook)까지 뗀 사본은 같은 예외에서 H6 을 허용한다(치환 1곳) — M8 의 차단은 갈무리가 만든다" || ng "M9" "치환 $M9A · 판정 $r"
M="$(mut m10 "$TG" 'any(t in ("-e", "-") for t in rest[1:])' 'len(rest) > 1 and rest[1] in ("-e", "-")')"
r="$(verdict "$M" PowerShell "$H8C")"
[ "$(mn m10)" = "1" ] && [ "$r" = "allow" ] && ok "M10 변수 실행기 판정을 종전(바로 뒤 낱말만)으로 되돌린 사본은 H8 을 통과시킨다(치환 1곳) — H8 이 잡는다" || ng "M10" "치환 $(mn m10) · 판정 $r"
M="$(mut m11 "$TG" '        return hs_bodies[i] if i < len(hs_bodies) else m.group(0)' '        return hs_bodies[i]')"
M11B="$(MUT_A='_HS_NONCE + r"_(\d+)__"' MUT_B='r"(\d+)__"' "$PY" -X utf8 -c 'import io,os,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8",newline="").read(); a,b=os.environ["MUT_A"],os.environ["MUT_B"]
s2=s.replace(a,b).replace("return \" __qvest_hs_%s_%d__ \" % (_HS_NONCE, len(hs_bodies) - 1)","return \" __qvest_hs_%d__ \" % (len(hs_bodies) - 1)")
print(s.count(a) + (s2.count("__qvest_hs_%d__") if s2!=s else 0)); io.open(p,"w",encoding="utf-8",newline="").write(s2)' "$M" 2>/dev/null | tr -d '\r\n')"
M11C="$(MUT_A='sys.excepthook = _fail_closed' MUT_B='pass' "$PY" -X utf8 -c 'import io,os,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8",newline="").read(); a,b=os.environ["MUT_A"],os.environ["MUT_B"]
print(s.count(a)); io.open(p,"w",encoding="utf-8",newline="").write(s.replace(a,b))' "$M" 2>/dev/null | tr -d '\r\n')"
r="$(verdict "$M" PowerShell "$H7C")"
[ "$(mn m11)" = "1" ] && [ "$M11B" = "2" ] && [ "$M11C" = "1" ] && [ "$r" = "allow" ] && ok "M11 고정 자리표 · 범위 검사 없음 · 갈무리 없음(수리 전 꼴) 사본은 H7 을 허용한다(치환 1+2+1곳) — H7 이 그 fail-open 을 잡는다" || ng "M11" "치환 $(mn m11)/$M11B/$M11C · 판정 $r"
finish
