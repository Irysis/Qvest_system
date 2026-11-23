#!/usr/bin/env bash
# test_scn_qw_kick_shape.sh — 퀀티 종료 알림(중복 로그인)의 판별 규칙(2026-11-23 · 도훈 '2번은 규칙보강' · ops/qw_kick_rule.ps1)
#
# 실사고 11-23 18:17: 다른 기기가 같은 아이디로 로그인해 단말이 종료 알림을 띄웠는데 본문이 기기 이름에서 끊겼다('[' + 한글 세 글자 ·
#   [확인] 하나 · 제목 'Quantiwise7G'). 구판 규칙(본문의 '(IP)]' · '중복')이 못 잡아 수집은 'unknown dialog' 로 멈추고, 세션 확인은
#   숨은 창 제목 때문에 끊긴 세션을 살아 있다고 봤다.
# 가짜 프로세스가 띄운 **진짜 창**(MessageBox = '#32770' · Static · Button)으로 잰다 — 실물 단말(qwMain) · 엑셀 · 운영 .cache 무접촉:
#   W1 온전한 알림(본문에 '(a.b.c.d)]')            → 잡는다(규칙 A · 그대로)
#   W2 끊긴 알림('[' 로 시작 · ']' 없음 · 단추 하나) → 잡는다(규칙 B · 수리의 발화)
#   W3 괄호를 닫은 공지('[notice] …')               → 안 잡는다(모르는 대화상자로 남는다)
#   W4 끊긴 본문이지만 단추 둘(예 · 아니요)          → 안 잡는다
#   W5 끊긴 본문이지만 제목이 다르다                 → 안 잡는다
#   W6 괄호 없는 본문                                → 안 잡는다
#   WM 돌연변이 = 구판 규칙(규칙 A 만)               → W2 를 못 잡는다(W2 는 수리의 발화다)
#   P  순수 함수 Test-QwKickShape: 한글 '중복' · 빈 본문 · 긴 본문(65자) · 본문 둘 · 단추 0
#   S  정적 배선: 드라이버 셋(qw_refresh · qw_fund_v2_tax_ts · qw_peer_refresh)이 규칙 파일을 읽고 Get-QwKickDialog 를 부른다 ·
#      규칙 파일이 없으면 멈춘다 · 구판(수리 직전)에는 그 호출이 없다(양성 대조) · 규칙 파일은 ASCII
#   A  QW-Alive(qw_refresh.ps1 의 함수 글 그대로 · 가짜 pid): 숨은 '[[Quantiwise7]]' 창 + 끊긴 알림 → 거짓 · 알림이 없으면 참
# 요약: 마지막 줄 {"test":"scn_qw_kick_shape","pass":N,"fail":N,"total":N}
set -uo pipefail
T=scn_qw_kick_shape
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
OPS="${QVEST_TEST_QWOPS_DIR:-$PROJ/02_Infrastructure/ops}"       # 스테이징 사본으로 잴 때만 폴더를 준다
RULE="$OPS/qw_kick_rule.ps1"
OLD_REV="${QVEST_TEST_QWKICK_OLD_REV:-6a89ad6d3}"                # 수리 직전 판(구판 규칙 · 돌연변이 · 양성 대조)
GITROOT="${QVEST_TEST_GITROOT:-$PROJ}"
[ -f "$RULE" ] || { echo "대상 없음: $RULE"; fin 0 1; }
TMP="$(mktemp -d)"; trap 'kill_fakes; rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
W() { cygpath -w "$1"; }
PS() { powershell.exe -NoProfile -ExecutionPolicy Bypass "$@" 2>&1 | tr -d '\r'; }
echo "== $T =="

# ── 가짜 프로세스(진짜 창) ──────────────────────────────────────────────────────
cat > "$TMP/fake_box.ps1" <<'PSH'
param([string]$PidFile, [string]$Title, [string]$Body, [string]$Buttons = 'OK', [switch]$HiddenForm)
Add-Type -AssemblyName System.Windows.Forms
if ($HiddenForm) {   # the terminal's hidden main forms: a window titled '[[Quantiwise7]]' that is never shown
  $f = New-Object System.Windows.Forms.Form; $f.Text = '[[Quantiwise7]]'; $null = $f.Handle
}
Set-Content -LiteralPath $PidFile -Value $PID
if ($Title) {
  $t = New-Object System.Windows.Forms.Timer; $t.Interval = 90000; $t.Add_Tick({ [Environment]::Exit(0) }); $t.Start()   # never outlive the test
  [void][System.Windows.Forms.MessageBox]::Show($Body, $Title, [System.Windows.Forms.MessageBoxButtons]::$Buttons)
} else { Start-Sleep 90 }
PSH
FAKES=()
kill_fakes() { local p; for p in "${FAKES[@]:-}"; do [ -n "$p" ] && PS -Command "Stop-Process -Id $p -Force -EA SilentlyContinue" >/dev/null; done; }
start_box() {  # $1 = 이름 · $2 = 제목 · $3 = 본문 · $4 = 단추(OK | YesNo) · $5 = -HiddenForm(선택) → pid
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(W "$TMP/fake_box.ps1")" -PidFile "$(W "$TMP/$1.pid")" -Title "$2" -Body "$3" -Buttons "${4:-OK}" ${5:-} >/dev/null 2>&1 &
  local n=75; while [ "$n" -gt 0 ] && [ ! -s "$TMP/$1.pid" ]; do sleep 0.2; n=$((n-1)); done
  [ -s "$TMP/$1.pid" ] || return 1
  local p; p="$(tr -d '\r' < "$TMP/$1.pid" | awk '{print $1}')"; FAKES+=("$p"); echo "$p"
}
cat > "$TMP/probe.ps1" <<'PSH'
param([string]$Rule, [int]$P, [int]$WaitMs = 6000)
. $Rule
$sw = [Diagnostics.Stopwatch]::StartNew(); $seen = 0
while ($sw.ElapsedMilliseconds -lt $WaitMs) { $seen = @([QwKick]::Dialogs($P)).Count; if ($seen -gt 0) { break }; Start-Sleep -Milliseconds 150 }   # 창이 뜰 때까지
"dialogs=$seen kick=$([bool](Get-QwKickDialog $P))"
PSH
probe() { PS -File "$(W "$TMP/probe.ps1")" -Rule "$(W "$1")" -P "$2" | tail -n 1; }

# 구판 규칙(규칙 A 만) — 수리 직전 판 qw_fund_v2_tax_ts.ps1 의 판별 식을 그대로 쓴 돌연변이 규칙 파일
sed -e 's/^  if (\$Title -ne .Quantiwise7G.) { return \$false }.*$/  return $false   # mutant: rule A only/' "$RULE" > "$TMP/rule_mut.ps1"
chk "M0 돌연변이 규칙 파일(규칙 B 를 뗀 것)" "1" "$(grep -c 'mutant: rule A only' "$TMP/rule_mut.ps1")"

p1="$(start_box w1 'Quantiwise7G' '[HOST01(10.1.2.3)] same id logged in - terminated (test)' OK)"
p2="$(start_box w2 'Quantiwise7G' '[abc' OK)"
p3="$(start_box w3 'Quantiwise7G' '[notice] server check (test)' OK)"
p4="$(start_box w4 'Quantiwise7G' '[abc' YesNo)"
p5="$(start_box w5 '-Quantiwise7G Update-' '[abc' OK)"
p6="$(start_box w6 'Quantiwise7G' 'plain message (test)' OK)"
if [ -n "$p1" ] && [ -n "$p2" ] && [ -n "$p3" ] && [ -n "$p4" ] && [ -n "$p5" ] && [ -n "$p6" ]; then
  chk "W1 온전한 알림(본문에 '(a.b.c.d)]') → 잡는다" "dialogs=1 kick=True" "$(probe "$RULE" "$p1")"
  chk "W2 끊긴 알림('[abc' · 단추 하나) → 잡는다(수리의 발화)" "dialogs=1 kick=True" "$(probe "$RULE" "$p2")"
  chk "W3 괄호를 닫은 공지 → 안 잡는다" "dialogs=1 kick=False" "$(probe "$RULE" "$p3")"
  chk "W4 끊긴 본문 · 단추 둘 → 안 잡는다" "dialogs=1 kick=False" "$(probe "$RULE" "$p4")"
  chk "W5 끊긴 본문 · 제목이 다르다 → 안 잡는다" "dialogs=1 kick=False" "$(probe "$RULE" "$p5")"
  chk "W6 괄호 없는 본문 → 안 잡는다" "dialogs=1 kick=False" "$(probe "$RULE" "$p6")"
  chk "WM 돌연변이(구판 규칙) → 끊긴 알림을 못 잡는다 — W2 는 수리의 발화다" "dialogs=1 kick=False" "$(probe "$TMP/rule_mut.ps1" "$p2")"
  chk "WM2 돌연변이도 온전한 알림은 잡는다(규칙 A 는 그대로)" "dialogs=1 kick=True" "$(probe "$TMP/rule_mut.ps1" "$p1")"
else chk "W0 가짜 창 프로세스 기동" YES NO; fi

# ── A QW-Alive(qw_refresh.ps1 의 함수 글 그대로 · 가짜 pid) ────────────────────────────────
DRV="$OPS/qw_refresh.ps1"
pa="$(start_box wa 'Quantiwise7G' '[abc' OK -HiddenForm)"     # 숨은 '[[Quantiwise7]]' 창 + 끊긴 알림
pb="$(start_box wb '' '' OK -HiddenForm)"                      # 숨은 창만(살아 있는 세션의 모양)
awk '/^function QW-Alive \{/{f=1} f{print} f&&/^\}$/{exit}' "$DRV" > "$TMP/qwalive.txt"
awk '/^function Kick-Dialog \{/{f=1} f{print} f&&/^\}$/{exit}' "$DRV" > "$TMP/kickdlg.txt"
{ printf '\xef\xbb\xbf'
  cat <<'PSH'
param([string]$Rule, [int]$FakePid, [int]$ExpectDialogs = 0)
. $Rule
Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class Win { public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static string Txt(IntPtr h){ var s=new StringBuilder(512); GetWindowText(h,s,512); return s.ToString(); }
  public static List<IntPtr> Wins(uint pid0){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{int p; GetWindowThreadProcessId(h,out p); if((uint)p==pid0) r.Add(h); return true;}, IntPtr.Zero); return r; } }
"@
function Get-Process { param($Name, $EA) [pscustomobject]@{ Id = $script:FakePid } }   # the fake pid instead of the real terminal (script scope: the drivers use a local $p)
PSH
  cat "$TMP/kickdlg.txt" "$TMP/qwalive.txt"
  cat <<'PSH'
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt 8000 -and @([QwKick]::Dialogs($FakePid)).Count -lt $ExpectDialogs) { Start-Sleep -Milliseconds 150 }
Start-Sleep -Milliseconds 300
"dialogs=$(@([QwKick]::Dialogs($FakePid)).Count) alive=$(QW-Alive)"
PSH
} > "$TMP/alive.ps1"
if [ -s "$TMP/qwalive.txt" ] && [ -s "$TMP/kickdlg.txt" ] && [ -n "$pa" ] && [ -n "$pb" ]; then
  chk "A1 숨은 창 + 끊긴 알림 → 살아 있지 않다" "dialogs=1 alive=False" "$(PS -File "$(W "$TMP/alive.ps1")" -Rule "$(W "$RULE")" -FakePid "$pa" -ExpectDialogs 1 | tail -n 1)"
  chk "A2 숨은 창만 → 살아 있다" "dialogs=0 alive=True" "$(PS -File "$(W "$TMP/alive.ps1")" -Rule "$(W "$RULE")" -FakePid "$pb" | tail -n 1)"
  chk "AM 돌연변이(구판 규칙) → 끊긴 알림이 떠 있어도 살아 있다고 본다(11-23 의 결함)" "dialogs=1 alive=True" "$(PS -File "$(W "$TMP/alive.ps1")" -Rule "$(W "$TMP/rule_mut.ps1")" -FakePid "$pa" -ExpectDialogs 1 | tail -n 1)"
else chk "A0 QW-Alive 추출 · 가짜 창" YES NO; fi
kill_fakes; FAKES=()

# ── P 순수 함수 ─────────────────────────────────────────────────────────────────
cat > "$TMP/pure.ps1" <<'PSH'
param([string]$Rule)
. $Rule
$dup = "$([char]0xC911)$([char]0xBCF5)"
$long = '[' + ('a' * 64)
$r = @(
  (Test-QwKickShape 'Quantiwise7G' @('Button', 'Static') @('OK', "[HOST] $dup")),
  (Test-QwKickShape 'Other Quantiwise' @('Button', 'Button', 'Static') @('Y', 'N', "x $dup")),
  (Test-QwKickShape 'Quantiwise7G' @('Button', 'Static', 'Static') @('OK', '', '[abc')),
  (Test-QwKickShape 'Quantiwise7G' @('Button', 'Static') @('OK', $long)),
  (Test-QwKickShape 'Quantiwise7G' @('Button', 'Static', 'Static') @('OK', '[abc', '[def')),
  (Test-QwKickShape 'Quantiwise7G' @('Static') @('[abc')),
  (Test-QwKickShape 'Quantiwise7G' @('Button', 'Static') @('OK', ''))
)
($r | ForEach-Object { if ($_) { 'T' } else { 'F' } }) -join ''
PSH
chk "P1 순수 함수 일곱 꼴(중복 · 중복(제목 무관) · 빈 글 건너뜀 · 65자 · 본문 둘 · 단추 0 · 빈 본문)" "TTTFFFF" "$(PS -File "$(W "$TMP/pure.ps1")" -Rule "$(W "$RULE")" | tail -n 1)"

# ── S 정적 배선 ─────────────────────────────────────────────────────────────────
for f in qw_refresh.ps1 qw_fund_v2_tax_ts.ps1 qw_peer_refresh.ps1; do
  src="$OPS/$f"
  chk "S $f — 규칙 파일을 읽는다 · 없으면 멈춘다 · Get-QwKickDialog 를 부른다" "1 1 1" \
    "$(grep -c "Join-Path \$PSScriptRoot 'qw_kick_rule.ps1'" "$src") $(grep -c "missing - not running without the kick rule\"; exit 1" "$src") $(grep -c 'Get-QwKickDialog (\[int\]\$p.Id)' "$src")"
  chk "S $f — 옛 판별 식이 드라이버에 남아 있지 않다(규칙은 한 곳)" "0" "$(grep -c '\$t.Contains(\$dup)' "$src")"
  old="$(git -C "$GITROOT" show "$OLD_REV:02_Infrastructure/ops/$f" 2>/dev/null)"
  if [ -n "$old" ]; then chk "S $f — 양성 대조: 구판($OLD_REV)에는 그 호출이 없다" "0" "$(printf '%s' "$old" | grep -c 'Get-QwKickDialog')"
  else chk "S $f — 구판 조회($OLD_REV)" YES NO; fi
done
chk "S 규칙 파일은 ASCII(PowerShell 5.1 이 BOM 없는 파일을 ANSI 로 읽는다)" "0" "$(LC_ALL=C grep -c '[^ -~	]' "$RULE" | tr -d '\r')"
fin "$PASS" "$FAIL"
