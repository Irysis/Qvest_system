#!/usr/bin/env bash
#==============================================================================
# test_hook_powershell_coverage.sh — 차단 훅이 PowerShell 도구의 명령도 보는가 (2026-11-10 · 도훈 결정 HOOK-POWERSHELL-COVERAGE-20261110)
#
# 지키는 것:
#   safety_guard.sh(생산 폴더 쓰기 · 경로 정규화 함수) 와 telegram_direct_call_guard.sh(텔레그램 직접 호출)는 전에는 Bash 도구의
#   명령만 검사했다 — PowerShell 도구로 내린 같은 명령은 그대로 통과했다. 등록(.claude/settings.json 의 PowerShell 대응)과
#   두 훅의 도구 분기를 함께 고쳤다. 이 시험은 그 셋(등록 · 안전 가드 · 텔레그램 가드)을 본다.
#
# 축:
#   R  등록 — settings.json 의 PreToolUse 에 PowerShell 대응이 있고 Bash 대응과 같은 두 가드를 태운다
#   S  안전 가드 × PowerShell — 생산 폴더 쓰기(cmdlet · 별칭 · 리디렉션) = 차단 · 읽기(Get-Content · Select-String · Format-Table) = 허용 ·
#      경로 정규화 함수 = 차단 · 무관한 명령 = 허용
#   T  텔레그램 가드 × PowerShell — 직접 호출 = 차단 · 정본 진입(tg_agent_brief) = 허용
#   B  [대조] 같은 명령의 Bash 판정은 그대로다(생산 폴더 쓰기 = 차단 · 읽기 = 허용)
#   M  [위반 주입] PowerShell 분기를 뗀 사본은 S · T 의 차단을 통과시킨다(= 수리 전 상태를 이 시험이 본다)
#
# 격리: 훅은 판정 JSON 만 낸다. 파일 쓰기 · 발송 없음.
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

# verdict <hook> <tool> <command-text> → deny | allow | ?
verdict() {
  local hook="$1" tool="$2" c="$3"
  PSC_TOOL="$tool" PSC_CMD="$c" "$PY" -X utf8 -c 'import json,os,sys
sys.stdout.buffer.write(json.dumps({"tool_name":os.environ["PSC_TOOL"],"tool_input":{"command":os.environ["PSC_CMD"]},"hook_event_name":"PreToolUse"},ensure_ascii=False).encode("utf-8"))' \
    | bash "$hook" 2>/dev/null | "$PY" -X utf8 -c 'import json,sys
t=sys.stdin.buffer.read().decode("utf-8","replace").strip()
try:
    d=json.loads(t) if t else {}
except Exception:
    print("?"); sys.exit(0)
dec=str(d.get("decision","")) or str((d.get("hookSpecificOutput") or {}).get("permissionDecision",""))
print("deny" if dec in ("block","deny") else "allow")'
}
expect() { # <이름> <기대> <hook> <tool> <명령>
  local got; got="$(verdict "$3" "$4" "$5")"
  if [ "$got" = "$2" ]; then ok "$1"; else ng "$1" "기대 $2 · 실제 $got"; fi
}
P="05_""Production"; NP="normalize""Path"   # 이 파일의 원문에 보호 낱말을 통째로 두지 않는다(이 시험을 돌리는 명령이 가드에 걸리지 않게)

echo "=== R. 등록 ==="
REG="$("$PY" -X utf8 -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8-sig"))
pre=d["hooks"]["PreToolUse"]
g=lambda m:[h["command"].split("/")[-1].rstrip("\"") for e in pre if e.get("matcher")==m for h in e.get("hooks",[])]
b,p=g("Bash"),g("PowerShell")
print("ok" if p and b==p and any("safety_guard.sh" in x for x in p) and any("telegram_direct_call_guard.sh" in x for x in p) else "bad:%s|%s"%(b,p))' "$ROOT/.claude/settings.json" 2>/dev/null)"
[ "$REG" = "ok" ] && ok "R1 settings.json — PowerShell 대응이 Bash 대응과 같은 두 가드를 태운다" || ng "R1 등록" "$REG"

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
expect "S10 읽기 + Format-Table(낱말 안의 rm 에 걸리지 않는다) = 허용" allow "$SG" PowerShell "Get-ChildItem $P | Format-Table Name, Length"
expect "S11 경로 정규화 함수 = 차단" deny "$SG" PowerShell "Rscript -e \"$NP('x')\""
expect "S12 무관한 명령 = 허용" allow "$SG" PowerShell "Get-ScheduledTask -TaskName 'Qvest_*' | Format-Table"

echo "=== T. 텔레그램 가드 × PowerShell ==="
expect "T1 Rscript -e 직접 호출 = 차단" deny "$TG" PowerShell "Rscript -e \"source('02_Infrastructure/telegram/telegram_notify.R'); tg_send('x')\""
expect "T2 tg_send_photo 직접 호출 = 차단" deny "$TG" PowerShell "& Rscript.exe -e \"tg_send_photo('a.png')\""
expect "T3 정본 진입 tg_agent_brief = 허용" allow "$TG" PowerShell "Rscript -e \"tg_agent_brief(agent = 'Q-Lead', title = 't', sections = list())\""
expect "T4 무관한 명령 = 허용" allow "$TG" PowerShell "Get-Process | Select-Object -First 3"

echo "=== B. [대조] Bash 판정은 그대로 ==="
expect "B1 Bash cp → 생산 폴더 = 차단" deny "$SG" Bash "cp x.R $P/x.R"
expect "B2 Bash 읽기 = 허용" allow "$SG" Bash "ls 02_Infrastructure | head -3"
expect "B3 Bash 텔레그램 직접 호출 = 차단" deny "$TG" Bash "Rscript -e \"tg_send('x')\""

echo "=== M. [위반 주입] PowerShell 분기를 뗀 사본 ==="
SGM="$T/hooks_sg"; TGM="$T/hooks_tg"; mkdir -p "$SGM" "$TGM"
cp "$ROOT/02_Infrastructure/hooks/"*.sh "$SGM/" 2>/dev/null; cp "$ROOT/02_Infrastructure/hooks/"*.sh "$TGM/" 2>/dev/null
"$PY" -X utf8 -c 'import io,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8",newline="").read()
a="if [ \"$TOOL_NAME\" = \"Bash\" ] || [ \"$TOOL_NAME\" = \"PowerShell\" ]; then"
print(s.count(a)); s=s.replace(a,"if [ \"$TOOL_NAME\" = \"Bash\" ]; then")
io.open(p,"w",encoding="utf-8",newline="").write(s)' "$SGM/safety_guard.sh" > "$T/m1.n" 2>/dev/null
"$PY" -X utf8 -c 'import io,sys
p=sys.argv[1]; s=io.open(p,encoding="utf-8",newline="").read()
a="if [ \"$TOOL\" != \"Bash\" ] && [ \"$TOOL\" != \"PowerShell\" ]; then"
print(s.count(a)); s=s.replace(a,"if [ \"$TOOL\" != \"Bash\" ]; then")
io.open(p,"w",encoding="utf-8",newline="").write(s)' "$TGM/telegram_direct_call_guard.sh" > "$T/m2.n" 2>/dev/null
N1="$(tr -d '\r\n' < "$T/m1.n")"; N2="$(tr -d '\r\n' < "$T/m2.n")"
M1="$(verdict "$SGM/safety_guard.sh" PowerShell "Copy-Item .\\x.R -Destination .\\$P\\x.R")"
M2="$(verdict "$TGM/telegram_direct_call_guard.sh" PowerShell "Rscript -e \"tg_send('x')\"")"
[ "$N1" = "1" ] && [ "$M1" = "allow" ] && ok "M1 안전 가드의 PowerShell 분기를 떼면 생산 폴더 쓰기가 통과한다(치환 1곳 성사) — S1 이 그 차이를 본다" || ng "M1" "치환 $N1 · 판정 $M1"
[ "$N2" = "1" ] && [ "$M2" = "allow" ] && ok "M2 텔레그램 가드의 PowerShell 분기를 떼면 직접 호출이 통과한다(치환 1곳 성사) — T1 이 그 차이를 본다" || ng "M2" "치환 $N2 · 판정 $M2"
finish
