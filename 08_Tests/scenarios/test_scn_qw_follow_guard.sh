#!/usr/bin/env bash
# test_scn_qw_follow_guard.sh — 퀀티 애드인 새로고침 감시기(ops/qw_follow_guard.ps1)와 FundV2 TS 수집 배선(2026-11-15 · refresh-root-fix
#   · 도훈 11-15 "고쳐" FUNDV2-TAXTS-FIX-20261115)
# 실사고 11-14 13:38: qw_fund_v2_tax_ts.ps1 2번째 시트(B101400_M) 새로고침 중 단말이 'Item Lookup'(사람용 선택 창)을 띄웠고,
#   엑셀은 그 OLE 호출을 끝없이 기다렸다 — Follow() 가 돌아오지 않아 정기 작업이 2시간 넘게 멈췄다(시간 상한 없음).
# 실제 단말 · 엑셀 무접촉: 가짜 '단말'(WinForms 창 · MessageBox) · 가짜 '엑셀'(잠자는 powershell)만 쓴다 — 감시기에는 늘 -QwPid 를 준다
#   (주지 않으면 실행 중인 qwMain 을 본다).
#   G1 선택 창 'Item Lookup' — 유예(grace) 전엔 그대로 · 유예 뒤 WM_CLOSE · 사건 lookup_closed(심박 표지 S1#1) · 돌연변이 GM1(닫기 줄 삭제)
#   G2 업데이트 확인 창 '-Quantiwise7G Update-' → '아니요'(id 7) · 사건 update_declined (-Once)
#   G3 정체 — 심박 나이 > StallSec → 그 엑셀(pid + 시작 시각) 종료 · 사건 excel_killed · 종료 코드 9 · 돌연변이 GM3(종료 줄 삭제)
#   G4 pid 재사용 보호 — 시작 시각이 다르면 죽이지 않는다 · 돌연변이 GM4(시작 시각 대조 삭제 → 죽인다)
#   G5 심박 비어 있음(새로고침 밖) → 죽이지 않는다
#   G6 부모 프로세스가 끝나면 감시기도 끝난다
#   C7 · C8 밤 드라이버용 규약(Start-FollowGuardForExcel · Get-FollowGuardKill -Since)
#   D  대화상자 감시기(qw_refresh.ps1 Start-DialogWatcher) — 업데이트 확인 창 = 아니요 · 승계 창 = 예 · 구판 = 예(양성 대조) · 가짜 창 pid 만 본다
#   U  Update_File 드라이버(qw_refresh.ps1) 배선 · X 벤치 · 질의서 드라이버(data/qw_excel_refresh.ps1) 배선
#   S  정적 배선(qw_fund_v2_tax_ts.ps1): 시작 전 1회(-Once) · 엑셀 뒤 상주(-ExcelPid/-ExcelTicks/-Beat/-StallSec/-ParentPid) ·
#      Follow 앞뒤 심박 · 손댄 시트 재수집(상한 LookupRetries 뒤 rc 1) · finally 에서 멈춤 · 구판(HEAD~) 양성 대조
# 요약: 마지막 줄 {"test":"scn_qw_follow_guard","pass":N,"fail":N,"total":N}
set -uo pipefail
T=scn_qw_follow_guard
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
GUARD="${QVEST_TEST_GUARD_SRC:-$PROJ/02_Infrastructure/ops/qw_follow_guard.ps1}"
TAXTS="${QVEST_TEST_TAXTS_SRC:-$PROJ/02_Infrastructure/ops/qw_fund_v2_tax_ts.ps1}"
OLD_REV="${QVEST_TEST_TAXTS_OLD_REV:-f89084e5e}"     # 수리 직전 판(감시기 없음 · 양성 대조)
GITROOT="${QVEST_TEST_GITROOT:-$PROJ}"
[ -f "$GUARD" ] || { echo "대상 없음: $GUARD"; fin 0 1; }
[ -f "$TAXTS" ] || { echo "대상 없음: $TAXTS"; fin 0 1; }
TMP="$(mktemp -d)"; trap 'kill_fakes; rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
W() { cygpath -w "$1"; }
PS() { powershell.exe -NoProfile -ExecutionPolicy Bypass "$@" 2>&1 | tr -d '\r'; }
echo "== $T =="

# ── 가짜 프로세스 ───────────────────────────────────────────────────────────────
cat > "$TMP/fake_picker.ps1" <<'PSH'
param([string]$Out, [string]$PidFile)
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
Set-Content -LiteralPath $PidFile -Value $PID
$f = New-Object System.Windows.Forms.Form
$f.Text = 'Item Lookup'; $f.ShowInTaskbar = $false; $f.StartPosition = 'Manual'
$f.Location = New-Object System.Drawing.Point(-3000, -3000); $f.Size = New-Object System.Drawing.Size(220, 120)
$f.Add_Shown({ Set-Content -LiteralPath $Out -Value 'open' })
$f.Add_FormClosed({ Set-Content -LiteralPath $Out -Value 'closed' })
$t = New-Object System.Windows.Forms.Timer; $t.Interval = 60000; $t.Add_Tick({ $f.Close() }); $t.Start()   # never outlive the test
[System.Windows.Forms.Application]::Run($f)
PSH
cat > "$TMP/fake_update.ps1" <<'PSH'
param([string]$Out, [string]$PidFile)
Add-Type -AssemblyName System.Windows.Forms
Set-Content -LiteralPath $PidFile -Value $PID
$r = [System.Windows.Forms.MessageBox]::Show('update test (scn_qw_follow_guard)', '-Quantiwise7G Update-', [System.Windows.Forms.MessageBoxButtons]::YesNo)
Set-Content -LiteralPath $Out -Value "$r"
PSH
cat > "$TMP/fake_excel.ps1" <<'PSH'
param([string]$PidFile, [int]$Sec = 120)
Set-Content -LiteralPath $PidFile -Value ("{0} {1}" -f $PID, (Get-Process -Id $PID).StartTime.Ticks)
Start-Sleep $Sec
PSH
cat > "$TMP/alive.ps1" <<'PSH'
param([int]$P, [long]$Ticks = 0)
$proc = Get-Process -Id $P -EA SilentlyContinue
if ($proc -and ($Ticks -eq 0 -or $proc.StartTime.Ticks -eq $Ticks)) { 'True' } else { 'False' }
PSH
FAKES=()
kill_fakes() { local p; for p in "${FAKES[@]:-}"; do [ -n "$p" ] && PS -Command "Stop-Process -Id $p -Force -EA SilentlyContinue" >/dev/null; done; }
wait_file() { local f="$1" n="${2:-50}"; while [ "$n" -gt 0 ] && [ ! -s "$f" ]; do sleep 0.2; n=$((n-1)); done; [ -s "$f" ]; }
start_fake() {  # $1 = 스크립트 · $2 = 이름 → pid 파일 $TMP/$2.pid (첫 칸 = Windows pid)
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(W "$TMP/$1")" -Out "$(W "$TMP/$2.out")" -PidFile "$(W "$TMP/$2.pid")" >/dev/null 2>&1 &
  wait_file "$TMP/$2.pid" 75 || return 1
  local p; p="$(tr -d '\r' < "$TMP/$2.pid" | awk '{print $1}')"; FAKES+=("$p"); echo "$p"
}
start_excel() {  # $1 = 이름 → "pid ticks"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(W "$TMP/fake_excel.ps1")" -PidFile "$(W "$TMP/$1.pid")" -Sec 120 >/dev/null 2>&1 &
  wait_file "$TMP/$1.pid" 75 || return 1
  local v; v="$(tr -d '\r' < "$TMP/$1.pid")"; FAKES+=("${v%% *}"); echo "$v"
}
ev_count() { local n=0; [ -f "$1" ] && n="$(grep -c "\"kind\":\"$2\"" "$1")"; echo "${n:-0}"; }   # grep -c 가 0 을 내며 1 로 끝나도 한 줄만
ev_label() { [ -f "$1" ] && grep "\"kind\":\"$2\"" "$1" | head -n 1 | sed -n 's/.*"label":"\([^"]*\)".*/\1/p'; }
now() { date +%s; }

# ── G1 선택 창 닫기(상주 모드 · 유예) ────────────────────────────────────────────────
g1() {  # $1 = 감시기 파일 → "early=… final=… ev=… label=…"
  local gs="$1" qp; rm -f "$TMP"/g1.*
  qp="$(start_fake fake_picker.ps1 g1)" || { echo "fake-failed"; return; }
  wait_file "$TMP/g1.out" 75
  printf 'S1#1|%s' "$(( $(now) * 1000 ))" > "$TMP/g1.beat"   # 심박 = unix ms
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(W "$gs")" -QwPid "$qp" -Events "$(W "$TMP/g1.ev")" -Beat "$(W "$TMP/g1.beat")" \
    -StopFile "$(W "$TMP/g1.stop")" -LookupGraceSec 4 -PollMs 300 -StallSec 3600 >/dev/null 2>&1 &
  sleep 2.5; local early; early="$(tr -d '\r' < "$TMP/g1.out")"
  local n=50; while [ "$n" -gt 0 ] && [ "$(tr -d '\r' < "$TMP/g1.out")" != "closed" ]; do sleep 0.2; n=$((n-1)); done
  local final; final="$(tr -d '\r' < "$TMP/g1.out")"
  : > "$TMP/g1.stop"; sleep 1.5
  echo "early=$early final=$final ev=$(ev_count "$TMP/g1.ev" lookup_closed) label=$(ev_label "$TMP/g1.ev" lookup_closed)"
}
chk "G1 'Item Lookup' — 유예 4초 전엔 그대로 · 뒤엔 닫힘 · 사건 lookup_closed 1건 · 표지 = 심박(S1#1)" "early=open final=closed ev=1 label=S1#1" "$(g1 "$GUARD")"
grep -vF 'PostMessage($h, 0x0010' "$GUARD" | grep -vF 'SendMessageTimeout($h, 0x0010' > "$TMP/gm1.ps1"
if ! cmp -s "$GUARD" "$TMP/gm1.ps1"; then
  chk "GM1 돌연변이(WM_CLOSE 줄 삭제) → 창이 남는다 — G1 은 그 줄의 발화다" "final=open" "$(g1 "$TMP/gm1.ps1" | grep -o 'final=[a-z]*')"
else chk "GM1 돌연변이 치환" YES NO; fi

# ── G2 업데이트 확인 창 → 아니요(-Once) ───────────────────────────────────────────────
g2() {
  local qp; rm -f "$TMP"/g2.*
  qp="$(start_fake fake_update.ps1 g2)" || { echo "fake-failed"; return; }
  sleep 1.5
  PS -File "$(W "$GUARD")" -QwPid "$qp" -Events "$(W "$TMP/g2.ev")" -Once >/dev/null
  wait_file "$TMP/g2.out" 50
  echo "result=$(tr -d '\r' < "$TMP/g2.out" 2>/dev/null) ev=$(ev_count "$TMP/g2.ev" update_declined)"
}
chk "G2 '-Quantiwise7G Update-' → '아니요'(id 7) · 사건 update_declined 1건(-Once)" "result=No ev=1" "$(g2)"

# ── G3 · G4 · G5 정체 종료 · pid 재사용 보호 · 심박 없음 ───────────────────────────────
g_stall() {  # $1 = 감시기 · $2 = 심박 내용(T=지금-100 치환) · $3 = 시작 시각 보정(0 = 그대로) → "exit=… alive=… ev=… label=…"
  local gs="$1" beat="$2" off="$3" v p tk rc; rm -f "$TMP"/gx.*
  v="$(start_excel gx)" || { echo "fake-failed"; return; }; p="${v%% *}"; tk="${v##* }"
  printf '%s' "${beat//T/$(( ( $(now) - 100 ) * 1000 ))}" > "$TMP/gx.beat"   # 100초 전(ms)
  ( sleep 6; : > "$TMP/gx.stop" ) &
  PS -File "$(W "$gs")" -ExcelPid "$p" -ExcelTicks "$(( tk + off ))" -QwPid "$p" -Events "$(W "$TMP/gx.ev")" -Beat "$(W "$TMP/gx.beat")" \
    -StopFile "$(W "$TMP/gx.stop")" -StallSec 5 -PollMs 300 >/dev/null; rc=$?
  wait
  echo "exit=$rc alive=$(PS -File "$(W "$TMP/alive.ps1")" -P "$p" -Ticks "$tk") ev=$(ev_count "$TMP/gx.ev" excel_killed) label=$(ev_label "$TMP/gx.ev" excel_killed)"
}
chk "G3 정체(심박 100초 > StallSec 5) → 그 엑셀 종료 · 종료 코드 9 · 사건 excel_killed(표지 S2#1)" "exit=9 alive=False ev=1 label=S2#1" "$(g_stall "$GUARD" 'S2#1|T' 0)"
grep -vF 'if ($age -gt $StallSec)' "$GUARD" > "$TMP/gm3.ps1"
if ! cmp -s "$GUARD" "$TMP/gm3.ps1"; then
  chk "GM3 돌연변이(정체 종료 줄 삭제) → 엑셀이 산다 — G3 은 그 줄의 발화다" "exit=0 alive=True ev=0 label=" "$(g_stall "$TMP/gm3.ps1" 'S2#1|T' 0)"
else chk "GM3 돌연변이 치환" YES NO; fi
chk "G4 시작 시각 불일치(재사용된 pid) → 죽이지 않는다(사건 0)" "exit=0 alive=True ev=0 label=" "$(g_stall "$GUARD" 'S2#1|T' 1)"
sed 's/ -and \$p\.StartTime\.Ticks -eq \$ExcelTicks//' "$GUARD" > "$TMP/gm4.ps1"
if ! cmp -s "$GUARD" "$TMP/gm4.ps1"; then
  chk "GM4 돌연변이(시작 시각 대조 삭제) → 재사용 pid 를 죽인다 — G4 는 그 대조의 발화다" "alive=False" "$(g_stall "$TMP/gm4.ps1" 'S2#1|T' 1 | grep -o 'alive=[A-Za-z]*')"
else chk "GM4 돌연변이 치환" YES NO; fi
chk "G5 심박 비어 있음(새로고침 밖) → 죽이지 않는다" "exit=0 alive=True ev=0 label=" "$(g_stall "$GUARD" '' 0)"

# ── G6 부모가 끝나면 감시기도 끝난다 ────────────────────────────────────────────────────
g6() {
  local v pp t0 t1; rm -f "$TMP"/g6.*
  v="$(start_excel g6)" || { echo "fake-failed"; return; }; pp="${v%% *}"
  ( sleep 2; PS -Command "Stop-Process -Id $pp -Force -EA SilentlyContinue" >/dev/null ) &
  t0=$(now); PS -File "$(W "$GUARD")" -ParentPid "$pp" -QwPid "$pp" -Events "$(W "$TMP/g6.ev")" -PollMs 300 -MaxSec 30 >/dev/null; t1=$(now); wait
  [ $(( t1 - t0 )) -lt 20 ] && echo "exited=True" || echo "exited=False($(( t1 - t0 ))s)"
}
chk "G6 부모 프로세스 종료 → 감시기 종료(MaxSec 30 전)" "exited=True" "$(g6)"


# ── C 호출 측 규약(ops/qw_follow_guard_client.ps1) — 실물 감시기 · 가짜 단말 · 가짜 엑셀 ──────────────────────────
CLIENT="${QVEST_TEST_GUARD_CLIENT_SRC:-$(dirname "$GUARD")/qw_follow_guard_client.ps1}"
printf 'exit 0\n' > "$TMP/dummy_guard.ps1"   # 시작하자마자 끝나는 '감시기'(준비 신호 없음)
c_run() {  # $1 = 모드(kill | acts | once | dead | gone) · $2 = 가짜 단말 pid(없으면 가짜 엑셀 pid) → RES 한 줄
  local mode="$1" qp="$2" v p tk gs="$GUARD"; v="$(start_excel "c_$mode")" || { echo "fake-failed"; return; }; p="${v%% *}"; tk="${v##* }"
  [ -n "$qp" ] || qp="$p"
  [ "$mode" = dead ] && gs="$TMP/dummy_guard.ps1"
  { printf '\xef\xbb\xbf'
    printf '. "%s"\n' "$(W "$CLIENT")"
    printf '$script:FgScript = "%s"\n' "$(W "$gs")"
    printf '$script:FgQwPid = %s\n' "$qp"
    printf '$mode = "%s"; $xp = %s; $tk = %s\n' "$mode" "$p" "$tk"
    printf '$ok = Initialize-FollowGuard "%s"\n' "$(W "$TMP/c_$mode.work")"
    cat <<'PSH'
if ($mode -eq 'once') { $a = @(Invoke-FollowGuardOnce); "RES init=$ok acts=$($a.Count) kind=$($a[0].kind)"; exit }
if ($mode -eq 'dead') { $t0 = Get-Date; $g = Start-FollowGuard $xp $tk 60; "RES started=$([bool]$g) proc=$([bool]$script:FgProc) fast=$(((Get-Date) - $t0).TotalSeconds -lt 16)"; exit }
if ($mode -eq 'gone') {
  $g = Start-FollowGuard $xp $tk 60; Stop-Process -Id $g.Id -Force; Start-Sleep 1
  try { Set-FollowBeat 'C#2'; $r = 'no-throw' } catch { $r = 'threw' }
  "RES started=$([bool]$g) beat=$r"; exit
}
$stall = 60; if ($mode -eq 'kill') { $stall = 3 }
$g = Start-FollowGuard $xp $tk $stall
$ta = FG-Now; Set-FollowBeat "C#1"
$beat = [IO.File]::ReadAllText($script:FgBeat)
if ($mode -eq 'kill') {
  for ($i = 0; $i -lt 40 -and (Get-Process -Id $xp -EA SilentlyContinue); $i++) { Start-Sleep -Milliseconds 250 }
  $k = Get-FollowGuardKill; Stop-FollowGuard
  "RES init=$ok started=$([bool]$g) beat=$($beat -match '^C#1\|\d+$') killed=$([bool]$k) label=$($k.label) alive=$([bool](Get-Process -Id $xp -EA SilentlyContinue)) proc=$([bool]$script:FgProc)"
} else {
  Start-Sleep 9; Set-FollowBeat ''
  $a = @(Get-FollowGuardActs $ta); $f = Format-FollowGuardActs $a; Stop-FollowGuard
  "RES init=$ok acts=$($a.Count) label=$($a[0].label) fmt=$($f -like "lookup_closed 'Item Lookup'*") cleared=$([IO.File]::ReadAllText($script:FgBeat) -eq '')"
}
PSH
  } > "$TMP/c_$mode.ps1"
  PS -File "$(W "$TMP/c_$mode.ps1")" | grep '^RES ' | tail -n 1 | sed 's/^RES //'
}
[ -f "$CLIENT" ] || { chk "C0 호출 측 규약 파일" YES NO; }
chk "C1 Start-FollowGuard → Set-FollowBeat 'C#1|초' → 정체 3초 넘김 → 감시기가 그 엑셀 종료 · Get-FollowGuardKill 표지 C#1 · Stop 뒤 비움" \
  "init=True started=True beat=True killed=True label=C#1 alive=False proc=False" "$(c_run kill '')"
rm -f "$TMP"/g1.*; qp="$(start_fake fake_picker.ps1 g1)"; wait_file "$TMP/g1.out" 75
chk "C2 선택 창 → Get-FollowGuardActs(그 새로고침 시각 이후) 1건 · 표지 C#1 · 사람이 읽을 서식 · 심박 비움" \
  "init=True acts=1 label=C#1 fmt=True cleared=True" "$(c_run acts "$qp")"
rm -f "$TMP"/g2.*; qp="$(start_fake fake_update.ps1 g2)"; sleep 1.5
chk "C3 Invoke-FollowGuardOnce(엑셀 전 1회) → 업데이트 확인 창 '아니요' · 행동 1건 update_declined" "init=True acts=1 kind=update_declined" "$(c_run once "$qp")"
chk "C4 C3 의 가짜 창 결과 = No" "No" "$(wait_file "$TMP/g2.out" 50; tr -d '\r' < "$TMP/g2.out" 2>/dev/null)"
chk "C5 감시기가 시작하자마자 죽음(준비 신호 없음) → Start-FollowGuard 는 \$null(호출 측은 돌리지 않는다)" "started=False proc=False fast=True" "$(c_run dead '')"
chk "C6 실행 중 감시기가 사라짐 → 다음 Set-FollowBeat 가 throw(감시 없는 Follow 없음)" "started=True beat=threw" "$(c_run gone '')"

# ── S 정적 배선(qw_fund_v2_tax_ts.ps1) ─────────────────────────────────────────────────
src="$(sed 's/#.*$//' "$TAXTS")"
has() { printf '%s\n' "$1" | grep -qF -- "$2" && echo YES || echo NO; }
order() { awk -v a="$2" -v b="$3" 'index($0,a){if(!x)x=NR} index($0,b){if(!y)y=NR} END{print (x>0 && y>x) ? "YES" : "NO"}' "$1"; }
chk "S1 시작 전 1회(Invoke-FollowGuardOnce)가 끊김 · 모르는 대화상자 점검보다 먼저" "YES YES" "$(order "$TAXTS" 'Invoke-FollowGuardOnce' 'if (Kick-Dialog) { Say "duplicate-login dialog at start') $(order "$TAXTS" 'Invoke-FollowGuardOnce' 'if (Other-Dialog) { Say "unknown Quantiwise dialog at start')"
chk "S2 엑셀 pid · 시작 시각을 잡은 뒤 상주 감시기(Start-FollowGuard \$xp \$tk \$StallSec) → 그다음 책 열기" "YES YES" "$(order "$TAXTS" '$tk = (Get-Process -Id $xp).StartTime.Ticks' 'Start-FollowGuard $xp $tk $StallSec') $(order "$TAXTS" 'Start-FollowGuard $xp $tk $StallSec' '$wb = $xl.Workbooks.Open($local)')"
chk "S3 Follow 앞에 심박 · 뒤에 비움(원문 — 심박 표지의 '#' 은 주석이 아니다)" "YES YES" "$(order "$TAXTS" 'Set-FollowBeat "$($r.sheet)#$attempt"' '$h.Follow()') $(order "$TAXTS" '$h.Follow()' "Set-FollowBeat ''")"
chk "S4 손댄 시트는 다시(continue) · 상한 LookupRetries 뒤 rc 1 로 끝(무한 반복 없음)" "YES YES" "$(has "$src" 'if ($script:Prompts -le $LookupRetries)') $(printf '%s\n' "$src" | grep -A2 -F 'if ($script:Prompts -le $LookupRetries)' | grep -qF '$rc = 1; throw' && echo YES || echo NO)"
chk "S5 finally 첫 줄에서 감시기 멈춤 · catch 는 감시기 종료를 이름 붙인다" "YES YES" "$(printf '%s\n' "$src" | grep -A1 -E '^finally \{' | grep -qF 'Stop-FollowGuard' && echo YES || echo NO) $(has "$src" '$kill = Get-FollowGuardKill')"
chk "S6 StallSec 기본 1800 · LookupRetries 기본 2" "YES YES" "$(grep -qE '^\s*\[int\]\$StallSec = 1800,' "$TAXTS" && echo YES || echo NO) $(grep -qE '^\s*\[int\]\$LookupRetries = 2,' "$TAXTS" && echo YES || echo NO)"
chk "S7 감시기 없음 = 돌리지 않음(규약 파일 없음 · 감시기 없음 → exit 1 · 기동 실패 → throw)" "3" "$(printf '%s\n' "$src" | grep -c 'not running unguarded')"
old_src="$(git -C "$GITROOT" show "$OLD_REV:02_Infrastructure/ops/qw_fund_v2_tax_ts.ps1" 2>/dev/null)"
chk "S8 양성 대조 — 구판($OLD_REV)에는 감시기 · 심박이 없다(검사기가 없는 것을 없다고 본다)" "0 0" "$(printf '%s' "$old_src" | grep -c 'FollowGuard') $(printf '%s' "$old_src" | grep -c 'Set-FollowBeat')"

# ── P 정적 배선(qw_peer_refresh.ps1 — 같은 FundV2 실행의 앞 단계) ─────────────────────────────
PEER="${QVEST_TEST_PEER_SRC:-$(dirname "$TAXTS")/qw_peer_refresh.ps1}"
if [ -f "$PEER" ]; then
  psrc="$(sed 's/#.*$//' "$PEER")"
  chk "P1 엑셀 전 1회 → 엑셀 뒤 상주 → 책 열기 순서" "YES YES" "$(order "$PEER" 'Invoke-FollowGuardOnce' '$xl = New-Object -ComObject Excel.Application') $(order "$PEER" 'Start-FollowGuard $fgPid' '$wb = $xl.Workbooks.Open($Book)')"
  chk "P2 Follow 자리 3곳(본 · 부분 전송 재시도 · 프롬프트 재시도) 모두 심박 3 · 비움 3" "3 3" "$(printf '%s\n' "$psrc" | grep -c 'Set-FollowBeat "') $(printf '%s\n' "$psrc" | grep -c "Set-FollowBeat ''")"
  chk "P3 감시기가 손댄 시트 = 한 번 더 · 또 손대면 NOT REFRESHED(무한 반복 없음)" "YES YES" "$(has "$psrc" '$acts = @(Get-FollowGuardActs $tsU)') $(printf '%s\n' "$psrc" | grep -F 'Get-FollowGuardActs $tsR' -A1 | grep -qF '$changed = $false' && echo YES || echo NO)"
  chk "P4 finally 첫 줄 Stop-FollowGuard · 감시기 없음 = 돌리지 않음 3곳" "YES 3" "$(printf '%s\n' "$psrc" | grep -A1 -F '} finally {' | grep -qF 'Stop-FollowGuard' && echo YES || echo NO) $(printf '%s\n' "$psrc" | grep -c 'not running unguarded')"
  old_peer="$(git -C "$GITROOT" show "$OLD_REV:02_Infrastructure/ops/qw_peer_refresh.ps1" 2>/dev/null)"
  chk "P5 양성 대조 — 구판($OLD_REV) 피어 갱신에는 감시기가 없다" "0" "$(printf '%s' "$old_peer" | grep -c 'FollowGuard')"
else chk "P0 피어 갱신 파일" YES NO; fi
# ── C7 · C8 호출 측 규약 추가분(밤 드라이버용) ──────────────────────────────────────────
c_xl() {  # $1 = 가짜 창 pid(그 프로세스의 창 핸들을 '엑셀 Hwnd' 로 쓴다 · 0 이면 Hwnd 0) → RES
  local qp="$1"
  { printf '\xef\xbb\xbf'
    printf '. "%s"\n' "$(W "$CLIENT")"
    printf '$script:FgScript = "%s"\n' "$(W "$GUARD")"
    printf '$script:FgQwPid = %s; $fake = %s\n' "${qp:-0}" "${qp:-0}"
    printf '$ok = Initialize-FollowGuard "%s"\n' "$(W "$TMP/c_xl.work")"
    cat <<'PSH'
$h = [IntPtr]::Zero
if ($fake -gt 0) {   # the fake's first visible top-level window (MainWindowHandle is 0 for a no-taskbar form)
  Add-Type -TypeDefinition 'using System; using System.Collections.Generic; using System.Runtime.InteropServices; public static class FWin { public delegate bool P(IntPtr h, IntPtr l); [DllImport("user32.dll")] static extern bool EnumWindows(P f, IntPtr l); [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid); [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h); public static IntPtr Of(int pid0) { IntPtr r = IntPtr.Zero; EnumWindows((h, l) => { int q; GetWindowThreadProcessId(h, out q); if (q == pid0 && IsWindowVisible(h)) { r = h; return false; } return true; }, IntPtr.Zero); return r; } }'
  $h = [FWin]::Of($fake)
}
$xl = [pscustomobject]@{ Hwnd = [int64]$h }
$g = Start-FollowGuardForExcel $xl 60
$okp = $false; if ($g) { $okp = ((Get-FollowGuardEvents 0 | Where-Object { $_.kind -eq 'ready' } | Select-Object -First 1).detail -match "excel=$fake ") }
Stop-FollowGuard
"RES hwnd=$([bool]($h -ne [IntPtr]::Zero)) started=$([bool]$g) pid_ok=$okp"
PSH
  } > "$TMP/c_xl.ps1"
  PS -File "$(W "$TMP/c_xl.ps1")" | grep '^RES ' | tail -n 1 | sed 's/^RES //'
}
rm -f "$TMP"/g1.*; qp="$(start_fake fake_picker.ps1 g1)"; wait_file "$TMP/g1.out" 75
chk "C7 Start-FollowGuardForExcel — 엑셀 객체의 Hwnd 로 pid · 시작 시각을 찾아 감시기 기동(준비 신호의 excel= 이 그 pid)" "hwnd=True started=True pid_ok=True" "$(c_xl "$qp")"
chk "C7b Hwnd 0(엑셀 창을 못 찾음) → \$null(호출 측은 받지 않는다)" "hwnd=False started=False pid_ok=False" "$(c_xl 0)"
c_since() {
  { printf '\xef\xbb\xbf'; printf '. "%s"\n' "$(W "$CLIENT")"; printf '$ok = Initialize-FollowGuard "%s"\n' "$(W "$TMP/c_since.work")"
    cat <<'PSH'
Add-Content -LiteralPath $script:FgEvents -Value '{"t":1000,"kind":"excel_killed","label":"OLD#1","title":"","detail":"old"}' -Encoding UTF8
Add-Content -LiteralPath $script:FgEvents -Value '{"t":3000,"kind":"excel_killed","label":"NEW#1","title":"","detail":"new"}' -Encoding UTF8
$a = Get-FollowGuardKill 0; $b = Get-FollowGuardKill 2000; $c = Get-FollowGuardKill 4000
"RES all=$($a.label) since=$($b.label) none=$([bool]$c)"
PSH
  } > "$TMP/c_since.ps1"
  PS -File "$(W "$TMP/c_since.ps1")" | grep '^RES ' | tail -n 1 | sed 's/^RES //'
}
chk "C8 Get-FollowGuardKill -Since — 책마다 엑셀을 새로 띄우는 드라이버는 앞 책의 종료 사건을 이 책 것으로 읽지 않는다" "all=NEW#1 since=NEW#1 none=False" "$(c_since)"

# ── D 대화상자 감시기(ops/qw_refresh.ps1 Start-DialogWatcher) — 업데이트 확인 창 = '아니요' · 승계 창 = '예'(그대로) ──────────
#   감시기 본문을 그대로 꺼내 ① 가짜 창 pid 만 보게 거르는 줄을 넣고(실제 단말 무접촉 — 넣지 못하면 돌리지 않는다) ② 무한 고리를 30바퀴로 묶는다.
DRV_U="${QVEST_TEST_QWREFRESH_SRC:-$(dirname "$TAXTS")/qw_refresh.ps1}"
watcher_body() { awk '/Start-Job -Name QWDlg -ScriptBlock \{/{f=1; next} f&&/^  \} \| Out-Null$/{exit} f{print}'; }
d_prep() {  # $1 = 원문 파일 · $2 = 출력 → 출력에 걸러진 본문(성공 YES)
  watcher_body < "$1" > "$TMP/wb_raw.ps1"
  local inj='$__p = 0; [void][DWX]::GetWindowThreadProcessId($h, [ref]$__p); if ($__p -ne [int]$env:H_FAKEPID) { return $true }'
  awk -v inj="$inj" '{ if ($0 ~ /\[WD\]::EnumWindows\(\{ param\(\$h,\$l\)/) { print; print "        " inj; n++ } else print } END { if (n != 1) exit 3 }' "$TMP/wb_raw.ps1" \
    | sed 's/^    while (\$true) {$/    for ($__n = 0; $__n -lt 30; $__n++) {/' > "$2.body" || { echo NO; return; }
  if ! grep -qF '$__p -ne [int]$env:H_FAKEPID' "$2.body" || ! grep -qF 'for ($__n = 0; $__n -lt 30; $__n++) {' "$2.body"; then echo NO; return; fi
  { printf '\xef\xbb\xbf'
    printf 'Add-Type -TypeDefinition %s\n' "'using System; using System.Runtime.InteropServices; public static class DWX { [DllImport(\"user32.dll\")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid); }'"
    cat "$2.body"; } > "$2"
  echo YES
}
d_run() {  # $1 = 걸러진 감시기 · $2 = 가짜 창 제목 → 그 창의 결과(Yes/No/없음)
  local wf="$1" title="$2" qp; rm -f "$TMP"/dw.*
  cat > "$TMP/dw_fake.ps1" <<PSH
param([string]\$Out, [string]\$PidFile)
Add-Type -AssemblyName System.Windows.Forms
Set-Content -LiteralPath \$PidFile -Value \$PID
\$r = [System.Windows.Forms.MessageBox]::Show('watcher test (scn_qw_follow_guard)', '$title', [System.Windows.Forms.MessageBoxButtons]::YesNo)
Set-Content -LiteralPath \$Out -Value "\$r"
PSH
  qp="$(start_fake dw_fake.ps1 dw)" || { echo "fake-failed"; return; }
  sleep 1.5
  H_FAKEPID="$qp" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(W "$wf")" >/dev/null 2>&1
  wait_file "$TMP/dw.out" 25; local v; v="$(tr -d '\r' < "$TMP/dw.out" 2>/dev/null)"; echo "${v:-none}"
}
if [ -f "$DRV_U" ]; then
  chk "D0 감시기 본문 추출 · 가짜 창 pid 걸름 주입 · 고리 묶음(새 판)" "YES" "$(d_prep "$DRV_U" "$TMP/dw_new.ps1")"
  if [ -s "$TMP/dw_new.ps1" ]; then
    chk "D1 새 판 — '-Quantiwise7G Update-' 확인 창에 '아니요'(단말 갱신 금지 · 11-14 비밀번호 저장 꺼짐 가설의 경로)" "No" "$(d_run "$TMP/dw_new.ps1" '-Quantiwise7G Update-')"
    chk "D2 새 판 — 승계 확인 창('Quantiwise7G' 예/아니요)은 종전대로 '예'(재로그인 경로 불변)" "Yes" "$(d_run "$TMP/dw_new.ps1" 'Quantiwise7G')"
  fi
  git -C "$GITROOT" show "$OLD_REV:02_Infrastructure/ops/qw_refresh.ps1" > "$TMP/qw_refresh_old.ps1" 2>/dev/null
  if [ -s "$TMP/qw_refresh_old.ps1" ] && [ "$(d_prep "$TMP/qw_refresh_old.ps1" "$TMP/dw_old.ps1")" = YES ]; then
    chk "D3 양성 대조 — 구판($OLD_REV)은 업데이트 확인 창에 '예'를 눌렀다(검사기가 그 차이를 본다)" "Yes" "$(d_run "$TMP/dw_old.ps1" '-Quantiwise7G Update-')"
  else chk "D3 구판 감시기 추출" YES NO; fi
else chk "D0 qw_refresh.ps1" YES NO; fi

# ── U Update_File 드라이버(ops/qw_refresh.ps1) 배선 ─────────────────────────────────────────
if [ -f "$DRV_U" ]; then
  usrc="$(sed 's/#.*$//' "$DRV_U")"
  ro="$(awk '/^function Refresh-One\(/{f=1} f{print} f&&/^\}$/{exit}' "$DRV_U")"
  lo="$(awk '/^if \(\$LoginOnly\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$DRV_U")"
  chk "U1 감시기 준비 = -LoginOnly 블록 뒤 · 책 고르기 전(로그인만 하는 길은 감시기와 무관)" "YES YES 0" "$(order "$DRV_U" 'if ($LoginOnly) {' 'Initialize-FollowGuard') $(order "$DRV_U" 'Initialize-FollowGuard' '$sel = @(') $(printf '%s\n' "$lo" | grep -c 'FollowGuard')"
  chk "U2 Refresh-One — 엑셀을 띄운 뒤 · 책을 열기 전 감시기(Start-FollowGuardForExcel \$xl \$StallSec)" "YES YES" "$(printf '%s\n' "$ro" > "$TMP/ro.ps1"; order "$TMP/ro.ps1" 'New-Object -ComObject Excel.Application' 'Start-FollowGuardForExcel $xl $StallSec') $(order "$TMP/ro.ps1" 'Start-FollowGuardForExcel $xl $StallSec' '$wb = $xl.Workbooks.Open($f.path)')"
  chk "U3 Refresh-One — 시트마다 Follow 앞 심박 · 뒤 비움" "YES YES" "$(order "$TMP/ro.ps1" 'Set-FollowBeat "$($f.name)/$($ws.Name)"' '$h.Follow()') $(order "$TMP/ro.ps1" '$h.Follow()' "Set-FollowBeat ''")"
  chk "U4 감시기가 손댄 책 = 저장 안 함(Close(\$keepBook)) · 2라운드면 그 실행에선 포기 · 종료 사건은 그 책 시각부터" "YES YES YES" "$(has "$ro" '$wb.Close($keepBook)') $(has "$ro" '[int]$script:FG_ACTS[$f.name] -ge 2') $(has "$ro" 'Get-FollowGuardKill $tb')"
  chk "U5 Refresh-One finally 첫 줄 Stop-FollowGuard · 감시기 없음 = 받지 않음(exit 1 두 곳 · throw 한 곳)" "YES 3" "$(printf '%s\n' "$ro" | grep -A1 -F '} finally {' | grep -qF 'Stop-FollowGuard' && echo YES || echo NO) $(printf '%s\n' "$usrc" | grep -c 'not refreshing unguarded')"
  chk "U6 StallSec 기본 5400" "YES" "$(grep -qE '^\s*\[int\]\$StallSec = 5400$' "$DRV_U" && echo YES || echo NO)"
  chk "U7 대화상자 감시기 — 업데이트 확인 창 분기가 '*Quantiwise7*' 일반 분기보다 먼저" "YES" "$(order "$DRV_U" "if (\$t -eq '-Quantiwise7G Update-')" 'elseif ($t -like "*Quantiwise7*")')"
  chk "U8 양성 대조 — 구판($OLD_REV) Update_File 드라이버에는 감시기가 없다" "0" "$(grep -c 'FollowGuard' "$TMP/qw_refresh_old.ps1")"
else chk "U0 qw_refresh.ps1" YES NO; fi

# ── X 벤치 · 질의서 드라이버(data/qw_excel_refresh.ps1) 배선 ─────────────────────────────────
DRV_X="${QVEST_TEST_XLREFRESH_SRC:-$PROJ/02_Infrastructure/data/qw_excel_refresh.ps1}"
if [ -f "$DRV_X" ]; then
  xsrc="$(sed 's/#.*$//' "$DRV_X")"
  chk "X1 엑셀 전 1회(Invoke-FollowGuardOnce) → 엑셀 뒤 감시기 → 책 열기" "YES YES YES" "$(order "$DRV_X" 'Invoke-FollowGuardOnce' '$xl = New-Object -ComObject Excel.Application') $(order "$DRV_X" '$xl = New-Object -ComObject Excel.Application' 'Start-FollowGuardForExcel $xl $StallSec') $(order "$DRV_X" 'Start-FollowGuardForExcel $xl $StallSec' '$wb = $xl.Workbooks.Open($work')"
  chk "X2 시트 Follow · 폴백 QBroker.Run 앞뒤 심박" "YES YES YES YES" "$(order "$DRV_X" 'Set-FollowBeat "$($b.name)"' '$sh.Hyperlinks.Item(1).Follow()') $(order "$DRV_X" '$sh.Hyperlinks.Item(1).Follow()' "Set-FollowBeat ''") $(order "$DRV_X" 'Set-FollowBeat "QBroker.Run($mid)"' '$broker.Run([int16]$mid') $(grep -A1 -F '$broker.Run([int16]$mid' "$DRV_X" | grep -qF "Set-FollowBeat ''" && echo YES || echo NO)"
  chk "X3 손댄 시트 = 한 번 더 · 또 손대면 저장 없이 rc 1 guard_prompt(폴백 포함 2곳)" "YES 2" "$(printf '%s\n' "$xsrc" | grep -A3 -F 'if ($r1.guard) {' | grep -qF '$r1 = RefreshSheet $sh $TimeoutSec' && echo YES || echo NO) $(printf '%s\n' "$xsrc" | grep -c "Finish 1 'guard_prompt'")"
  chk "X4 finally 첫 줄 Stop-FollowGuard · catch 는 감시기 종료를 이름 붙인다 · 감시기 없음 = rc 1 no_guard 3곳" "YES YES 3" "$(printf '%s\n' "$xsrc" | grep -A1 -E '^finally \{' | grep -qF 'Stop-FollowGuard' && echo YES || echo NO) $(has "$xsrc" '$kill = Get-FollowGuardKill') $(printf '%s\n' "$xsrc" | grep -c "Finish 1 'no_guard'")"
  chk "X5 StallSec 기본 3600 · 규약 파일 = ..\\ops 정규화 경로" "YES YES" "$(grep -qE '^\s*\[int\]\$StallSec = 3600$' "$DRV_X" && echo YES || echo NO) $(has "$xsrc" "[System.IO.Path]::GetFullPath((Join-Path \$PSScriptRoot '..\\ops\\qw_follow_guard_client.ps1'))")"
  old_x="$(git -C "$GITROOT" show "$OLD_REV:02_Infrastructure/data/qw_excel_refresh.ps1" 2>/dev/null)"
  chk "X6 양성 대조 — 구판($OLD_REV) 벤치 드라이버에는 감시기가 없다" "0" "$(printf '%s' "$old_x" | grep -c 'FollowGuard')"
else chk "X0 qw_excel_refresh.ps1" YES NO; fi
kill_fakes
fin "$PASS" "$FAIL"
