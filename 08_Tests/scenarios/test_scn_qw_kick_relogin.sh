#!/usr/bin/env bash
# test_scn_qw_kick_relogin.sh — 퀀티 드라이버 재로그인 규칙(2026-11-13 · 도훈 결정 QW-NIGHT-SESSION-ENSURE-20261113
#   "재로그인 횟수에 제한두지마. 회사컴 로그인 발생하면 항상 바로 재로그인해")
#
# 실제 ops/qw_refresh.ps1 의 라운드 루프 텍스트를 잘라 스텁(Ensure-Login · Refresh-One · 상태)으로 돌린다 — 단말 · 엑셀 · 운영 .cache 무접촉:
#   K  끊김 3번 뒤 완료(책 A) · MaxRounds 2 → 끝까지 받는다(끊긴 라운드는 예산을 쓰지 않는다 · 재로그인 4회 · 마지막 라운드 = 전부 끝 확인)
#   G  늘 끊김 · KickStall 5 → 5라운드에서 폭주 방지로 멈춘다(무한 반복 없음)
#   P  끊김 사이사이 책이 끝나면 연속 횟수를 0 으로 되돌린다 — A 끊김 2 · B 끊김 2(KickStall 3): A 가 끝난 라운드에서 0 으로 · 멈추지 않는다
#   S  -SkipLogin(재로그인 없음 · 구 동작) · 늘 끊김 · MaxRounds 2 → 2라운드에서 끝(끊긴 라운드도 예산을 쓴다)
#   F  로그인 실패(살아나지 않음) · MaxRounds 2 → 2라운드 · 수급 0(계정 잠금 경로는 예산으로 묶인다)
#   M  돌연변이 = 구판 루프(git 이전 판 · '두 번째 종료 = 멈춤') → K 가 끝까지 못 받는다(K 는 수리의 발화다)
#   T  정적: Ensure-Login · LoginOnly 에 '끊김 횟수로 멈춤' 분기가 없다 · 구판엔 있었다(양성 대조)
#   R  FundV2 TS 수집 Resolve-Kick(시트별 재로그인 · 횟수 제한 없음 · 로그인 실패 rc 3 · 폭주 방지 rc 4) + 돌연변이 RM
#   O  FundV2 실행기 Invoke-QwStep(끊긴 단계 재로그인 뒤 재실행 · 같은 규칙) + 돌연변이 OM · C1 정적(-NoRelogin 제거 · 피어 갱신 경유)
# 요약: 마지막 줄 {"test":"scn_qw_kick_relogin","pass":N,"fail":N,"total":N}
set -uo pipefail
T=scn_qw_kick_relogin
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; PROJ="$(cd "$_SELF_DIR/../.." && pwd)"
fin() { echo "{\"test\":\"$T\",\"pass\":$1,\"fail\":$2,\"total\":$(( $1 + $2 ))}"; [ "$2" -eq 0 ]; exit $?; }
DRV="${QVEST_TEST_QWREFRESH_SRC:-$PROJ/02_Infrastructure/ops/qw_refresh.ps1}"
OLD_REV="${QVEST_TEST_QWREFRESH_OLD_REV:-91fc50f4a}"   # 수리 직전 판(구판 루프 · 돌연변이 대조)
GITROOT="${QVEST_TEST_GITROOT:-$PROJ}"                 # 스테이징 사본으로 잴 때만 저장소 경로를 준다
[ -f "$DRV" ] || { echo "대상 없음: $DRV"; fin 0 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
chk() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1 — 기대 '$2' / 실제 '$3'"; fi; }
echo "== $T =="
loop_of() { awk '/^\$round = 0/{f=1} f{print} f&&/^\}$/{exit}'; }
loop_of < "$DRV" > "$TMP/loop_new.ps1"
chk "S0 라운드 루프 추출(새 판)" YES "$(grep -q 'while (\$spent -lt \$MaxRounds)' "$TMP/loop_new.ps1" && echo YES || echo NO)"
mk() {  # $1 = 루프 파일 → 하네스(.ps1)
  { printf '\xef\xbb\xbf'
    cat <<'PSH'
$ErrorActionPreference = 'Stop'
$MaxRounds = [int]$env:H_MAXR; $SkipLogin = ($env:H_SKIP -eq '1'); $KickStall = [int]$env:H_STALL
$script:KICKS = 0; $script:LOGIN_BLOCKED = ''; $script:NO_SAVED_PW = ($env:H_NOPW -eq '1')
$sel = @(@{ name = 'A' }, @{ name = 'B' }); $state = @{}; $target = '20261112'
$script:plan = @{ A = @(($env:H_A -split ',') | Where-Object { $_ }); B = @(($env:H_B -split ',') | Where-Object { $_ }) }
$script:refreshes = 0; $script:logins = 0
function Is-Done($st, $n, $t) { return $st.ContainsKey($n) }
function Mark-Done($st, $n, $t) { $st[$n] = $t }
function Ensure-Login { $script:logins++; if ($env:H_LOGIN -eq 'nopw') { $script:NO_SAVED_PW = $true; $script:SkipLogin = $true; return $false }; if ($env:H_LOGIN -eq 'fail') { return $false }; return $true }
function Refresh-One($f, $t) {
  $script:refreshes++; if ($script:refreshes -gt 300) { throw 'runaway in harness' }
  if ($env:H_ALWAYS -eq $f.name) { return 'kicked' }
  $q = @($script:plan[$f.name]); if ($q.Count -eq 0) { return 'ok' }
  $script:plan[$f.name] = @($q | Select-Object -Skip 1); return $q[0]
}
function Start-Sleep { }
PSH
    cat "$1"
    printf '\n"RES rounds=$round refreshes=$($script:refreshes) logins=$($script:logins) done=$(@($sel | Where-Object { Is-Done $state $_.name $target }).Count)"\n'
  } > "$TMP/h.ps1"
}
run() {  # $1 = 루프 파일 · 나머지 = 환경 대입 → RES 줄
  local lp="$1"; shift; mk "$lp"
  env H_MAXR=2 H_SKIP=0 H_STALL=30 H_A= H_B= H_ALWAYS= H_LOGIN= H_NOPW= "$@" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TMP/h.ps1")" 2>&1 | tr -d '\r' | grep '^RES ' | tail -n 1 | sed 's/^RES //'
}
chk "K 끊김 3번 뒤 완료 · MaxRounds 2 → 끝까지(재로그인 4 · 라운드 5 = 끝 확인 포함)" "rounds=5 refreshes=5 logins=4 done=2" "$(run "$TMP/loop_new.ps1" H_A=kicked,kicked,kicked)"
chk "G 늘 끊김 · KickStall 5 → 5라운드에서 멈춤(무한 반복 없음 · 완료 0)" "rounds=5 refreshes=5 logins=5 done=0" "$(run "$TMP/loop_new.ps1" H_ALWAYS=A H_STALL=5)"
chk "P 끊김 사이 책이 끝나면 연속 0 — A 끊김 2 · B 끊김 2 · KickStall 3 → 멈추지 않는다(끊김 4번 · 완료 2)" "rounds=6 refreshes=6 logins=5 done=2" "$(run "$TMP/loop_new.ps1" H_A=kicked,kicked H_B=kicked,kicked H_STALL=3)"
chk "P2 진행 없는 연속 끊김 3번 → KickStall 3 에서 멈춤(같은 조건 · 리셋 없는 경우)" "rounds=3 refreshes=3 logins=3 done=0" "$(run "$TMP/loop_new.ps1" H_ALWAYS=A H_STALL=3)"
chk "S -SkipLogin(구 동작) · 늘 끊김 · MaxRounds 2 → 2라운드(끊긴 라운드도 예산)" "rounds=2 refreshes=2 logins=0 done=0" "$(run "$TMP/loop_new.ps1" H_ALWAYS=A H_SKIP=1)"
chk "F 로그인 실패 · MaxRounds 2 → 2라운드 · 수급 0(잠금 경로는 예산으로 묶인다)" "rounds=2 refreshes=0 logins=2 done=0" "$(run "$TMP/loop_new.ps1" H_LOGIN=fail)"
if git -C "$GITROOT" show "$OLD_REV:02_Infrastructure/ops/qw_refresh.ps1" 2>/dev/null | loop_of > "$TMP/loop_old.ps1" && [ -s "$TMP/loop_old.ps1" ]; then
  chk "M0 구판 루프 추출(돌연변이 = 수리 전 판 $OLD_REV)" YES "$(grep -q 'while (\$round -lt \$MaxRounds)' "$TMP/loop_old.ps1" && echo YES || echo NO)"
  r=$(run "$TMP/loop_old.ps1" H_A=kicked,kicked,kicked)
  chk "M 돌연변이(구판 루프) → K 가 끝까지 못 받는다(완료 0) — K 는 수리의 발화다" "done=0" "$(printf '%s' "$r" | grep -o 'done=[0-9]*')"
else
  chk "M0 구판 루프 추출(돌연변이)" YES NO
fi
# T 정적 — 끊김 횟수로 멈추는 분기
el_new=$(awk '/^function Ensure-Login \{/{f=1} f{print} f&&/^\}$/{exit}' "$DRV")
lo_new=$(awk '/^if \(\$LoginOnly\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$DRV")
chk "T1 Ensure-Login · LoginOnly 에 'KICKS -gt 1' 멈춤 분기 없음(새 판)" "0 0" "$(printf '%s' "$el_new" | grep -c 'KICKS -gt 1') $(printf '%s' "$lo_new" | grep -c 'KICKS -gt 1')"
old_src="$(git -C "$GITROOT" show "$OLD_REV:02_Infrastructure/ops/qw_refresh.ps1" 2>/dev/null)"
chk "T2 양성 대조 — 구판에는 그 분기가 있었다(검사기가 볼 수 있는 것)" YES "$(printf '%s' "$old_src" | grep -q 'not competing (stop)' && echo YES || echo NO)"
chk "T3 KickStall 매개변수 · 기본 30" YES "$(grep -qE '^\s*\[int\]\$KickStall = 30,' "$DRV" && echo YES || echo NO)"
# ── FundV2 경로(같은 결정) — 시트별 재로그인 Resolve-Kick(qw_fund_v2_tax_ts.ps1) · 단계 재실행 Invoke-QwStep(qw_fund_v2_update.ps1) ──
TAXTS="${QVEST_TEST_TAXTS_SRC:-$PROJ/02_Infrastructure/ops/qw_fund_v2_tax_ts.ps1}"
FUPD="${QVEST_TEST_FUNDUPD_SRC:-$PROJ/02_Infrastructure/ops/qw_fund_v2_update.ps1}"
fn_of() { awk -v n="$1" '$0 ~ "^function "n"[ (]" {f=1} f{print} f&&/^\}$/{exit}'; }
fn_of Resolve-Kick < "$TAXTS" > "$TMP/rk.ps1"; fn_of Invoke-QwStep < "$FUPD" > "$TMP/qs.ps1"
chk "R0 · O0 함수 추출(Resolve-Kick · Invoke-QwStep)" "YES YES" "$([ -s "$TMP/rk.ps1" ] && echo YES || echo NO) $([ -s "$TMP/qs.ps1" ] && echo YES || echo NO)"
rk_run() {  # $1 = 함수 파일 · 나머지 = 환경 → RES
  local fp="$1"; shift
  { printf '\xef\xbb\xbf'
    cat <<'PSH'
$ErrorActionPreference = 'Stop'
$KickStall = [int]$env:H_STALL
$script:alive = @(($env:H_ALIVE -split ',') | Where-Object { $_ }); $script:ends = @(($env:H_ENDS -split ',') | Where-Object { $_ })
function Say([string]$m) { }
function QW-Alive { $v = '1'; if ($script:alive.Count) { $v = $script:alive[0]; $script:alive = @($script:alive | Select-Object -Skip 1) }; return ($v -eq '1') }
$script:loginCalls = 0
$script:LoginOnlyCmd = { $script:loginCalls++; $n = '1'; if ($script:ends.Count) { $n = $script:ends[0]; $script:ends = @($script:ends | Select-Object -Skip 1) }; "===== LOGIN-ONLY END 00:00:00 / alive=x / kicks=1 / logins_ok=$n =====" }
$script:Kicks = 0; $script:rc = 1
PSH
    cat "$fp"
    printf '\ntry { Resolve-Kick "S1"; $res = "returned" } catch { $res = "threw rc=$($script:rc)" }\n"RES $res kicks=$($script:Kicks) logins=$($script:loginCalls)"\n'
  } > "$TMP/rkh.ps1"
  env H_STALL=30 H_ALIVE= H_ENDS= "$@" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TMP/rkh.ps1")" 2>&1 | tr -d '\r' | grep '^RES ' | tail -n 1 | sed 's/^RES //'
}
chk "R1 재로그인 뒤 살아남 → 그 시트 다시(끊김 1)" "returned kicks=1 logins=1" "$(rk_run "$TMP/rk.ps1" H_ALIVE=1)"
chk "R2 재로그인은 됐는데 또 밀림(logins_ok 1) → 다시 재로그인 → 살아남(끊김 2)" "returned kicks=2 logins=2" "$(rk_run "$TMP/rk.ps1" H_ALIVE=0,1 H_ENDS=1,1)"
chk "R3 로그인 자체 실패(logins_ok 0) → rc 3(계정 잠금 방지)" "threw rc=3 kicks=1 logins=1" "$(rk_run "$TMP/rk.ps1" H_ALIVE=0 H_ENDS=0)"
chk "R4 계속 밀림 · KickStall 3 → rc 4(폭주 방지)" "threw rc=4 kicks=3 logins=2" "$(rk_run "$TMP/rk.ps1" H_ALIVE=0,0,0,0 H_ENDS=1,1,1,1 H_STALL=3)"
sed "s/if (-not (\"\$end\" -match 'logins_ok=\[1-9\]'))/if (\$true)/" "$TMP/rk.ps1" > "$TMP/rk_mut.ps1"
if ! cmp -s "$TMP/rk.ps1" "$TMP/rk_mut.ps1"; then
  chk "RM 돌연변이(재로그인 뒤 밀림 = 실패로 접음 · 구판 '1회 뒤 멈춤') → R2 가 rc 3 으로 멈춘다 — R2 는 수리의 발화다" "threw rc=3 kicks=1 logins=1" "$(rk_run "$TMP/rk_mut.ps1" H_ALIVE=0,1 H_ENDS=1,1)"
else chk "RM 돌연변이 치환" YES NO; fi
qs_run() {  # $1 = 함수 파일 · 나머지 = 환경 → RES
  local fp="$1"; shift
  { printf '\xef\xbb\xbf'
    cat <<'PSH'
$ErrorActionPreference = 'Stop'
$KICK_STALL = [int]$env:H_STALL
$script:steps = @(($env:H_RCS -split ',') | Where-Object { $_ } | ForEach-Object { [int]$_ }); $script:si = 0; $script:stepCalls = 0
$script:rel = @(($env:H_REL -split ',') | Where-Object { $_ }); $script:relogins = 0
function Invoke-Relogin { $script:relogins++; $x = 'alive'; if ($script:rel.Count) { $x = $script:rel[0]; $script:rel = @($script:rel | Select-Object -Skip 1) }
  switch ($x) { 'kick' { [pscustomobject]@{ alive = $false; logins_ok = 1 } } 'fail' { [pscustomobject]@{ alive = $false; logins_ok = 0 } } default { [pscustomobject]@{ alive = $true; logins_ok = 1 } } } }
$step = { $script:stepCalls++; $c = $script:steps[[Math]::Min($script:si, $script:steps.Count - 1)]; $script:si++; Write-Output "child output line"; cmd /c "exit $c" }
PSH
    cat "$fp"
    printf '\n$r = Invoke-QwStep $step "DB" "refresh"\n"RES rc=$r steps=$($script:stepCalls) relogins=$($script:relogins)"\n'
  } > "$TMP/qsh.ps1"
  env H_STALL=30 H_RCS=0 H_REL= "$@" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TMP/qsh.ps1")" 2>&1 | tr -d '\r' | grep '^RES ' | tail -n 1 | sed 's/^RES //'
}
chk "O1 끊김 2번 뒤 성공 → 재로그인 2 · 단계 3번 · rc 0(자식 출력은 반환값에 안 섞인다)" "rc=0 steps=3 relogins=2" "$(qs_run "$TMP/qs.ps1" H_RCS=4,4,0)"
chk "O2 재로그인 자체 실패 → rc 3(그 실행 멈춤)" "rc=3 steps=1 relogins=1" "$(qs_run "$TMP/qs.ps1" H_RCS=4 H_REL=fail)"
chk "O3 계속 끊김 · KICK_STALL 5 → rc 4(폭주 방지)" "rc=4 steps=5 relogins=4" "$(qs_run "$TMP/qs.ps1" H_RCS=4 H_STALL=5)"
chk "O4 끊김이 아닌 실패(rc 1) → 재로그인 없이 그대로" "rc=1 steps=1 relogins=0" "$(qs_run "$TMP/qs.ps1" H_RCS=1)"
chk "O5 재로그인 뒤 또 밀림 → 다시 재로그인 → 성공" "rc=0 steps=2 relogins=2" "$(qs_run "$TMP/qs.ps1" H_RCS=4,0 H_REL=kick,alive)"
sed 's/    if (\$src -ne 4) { return \$src }/    return $src/' "$TMP/qs.ps1" > "$TMP/qs_mut.ps1"
if ! cmp -s "$TMP/qs.ps1" "$TMP/qs_mut.ps1"; then
  chk "OM 돌연변이(끊김에도 재시도 없음 · 구판 '끊기면 실행 멈춤') → O1 이 rc 4 · 단계 1번 — O1 은 수리의 발화다" "rc=4 steps=1 relogins=0" "$(qs_run "$TMP/qs_mut.ps1" H_RCS=4,4,0)"
else chk "OM 돌연변이 치환" YES NO; fi
chk "C1 주간 TS 수집은 -NoRelogin 없이 부른다 · 피어 갱신은 Invoke-QwStep 경유" "0 1" "$(sed 's/#.*$//' "$FUPD" | grep -c 'qw_fund_v2_tax_ts.ps1.*-NoRelogin') $(grep -c 'Invoke-QwStep { & powershell .*qw_peer_refresh.ps1' "$FUPD")"

# ── 비밀번호 저장 꺼짐(2026-11-14 · refresh-root-fix) — 살아 있는 세션은 쓰고 로그인만 끈다 ────────────────────────────────────
#   실사고 11-14: 00:11 재로그인 직후 단말이 maincfg SAVEUSERPW=0 으로 다시 썼고, 구판 드라이버 · 벤치 드라이버는 세션이 살아 있는데도
#   시작 전에 끊어(exit 3) 밤 수급 0 · 자가 복구 5회 · 벤치 · 질의서가 다 멈췄다.
#   N  라운드 루프: no_saved_pw(= SkipLogin) 첫 끊김에서 곧바로 멈춤 · 끊김 없으면 끝까지 · NM 돌연변이(멈춤 줄 삭제) → 예산까지 돈다
#      N3 로그인이 꺼짐을 알리며 거짓이면 그 라운드에서 멈춤(죽은 세션에 수급하지 않음) · NM3 돌연변이
#   W  판정 함수 · 로그인 뒤 재확인(실물 함수 · 모래상자 maincfg) · 배선(시작 점검 · Ensure-Login 마지막 방어선 · LoginOnly) · 구판 양성 대조
#      W8 · W9 Ensure-Login 실물(단말 조회 · 종료 · 기동은 가림) — 로그인 직전 재확인 · W8M 돌연변이
#   B  벤치 · 질의서 드라이버(data/qw_excel_refresh.ps1) — 로그인이 필요할 때만 rc 3 · 구판 양성 대조
chk "N1 no_saved_pw · 늘 끊김 → 1라운드에서 멈춤(로그인 0)" "rounds=1 refreshes=1 logins=0 done=0" "$(run "$TMP/loop_new.ps1" H_ALWAYS=A H_SKIP=1 H_NOPW=1)"
chk "N2 no_saved_pw · 끊김 없음 → 끝까지(로그인 0 · 완료 2)" "rounds=2 refreshes=2 logins=0 done=2" "$(run "$TMP/loop_new.ps1" H_SKIP=1 H_NOPW=1)"
grep -v 'kicked and no saved password' "$TMP/loop_new.ps1" > "$TMP/loop_nm.ps1"
if ! cmp -s "$TMP/loop_new.ps1" "$TMP/loop_nm.ps1"; then
  chk "NM 돌연변이(멈춤 줄 삭제) → N1 이 예산(MaxRounds 2)까지 돈다 — N1 은 멈춤 줄의 발화다" "rounds=2 refreshes=2 logins=0 done=0" "$(run "$TMP/loop_nm.ps1" H_ALWAYS=A H_SKIP=1 H_NOPW=1)"
else chk "NM 돌연변이 치환" YES NO; fi
chk "N3 로그인 직전 꺼짐 발견(Ensure-Login 이 no_saved_pw 로 거짓) · 세션 없음 → 1라운드에서 멈춤(수급 0)" "rounds=1 refreshes=0 logins=1 done=0" "$(run "$TMP/loop_new.ps1" H_ALWAYS=A H_LOGIN=nopw)"
grep -v 'no session and no saved password' "$TMP/loop_new.ps1" > "$TMP/loop_nm3.ps1"
if ! cmp -s "$TMP/loop_new.ps1" "$TMP/loop_nm3.ps1"; then
  chk "NM3 돌연변이(그 멈춤 줄 삭제) → 'retry' 로 한 라운드 더 돌아 죽은 세션에 수급한다 — N3 은 그 줄의 발화다" "rounds=2 refreshes=1 logins=1 done=0" "$(run "$TMP/loop_nm3.ps1" H_ALWAYS=A H_LOGIN=nopw)"
else chk "NM3 돌연변이 치환" YES NO; fi
fn_of Resolve-SavedPwMode < "$DRV" > "$TMP/rs.ps1"
chk "W0 판정 함수 추출(Resolve-SavedPwMode)" YES "$([ -s "$TMP/rs.ps1" ] && echo YES || echo NO)"
{ printf '\xef\xbb\xbf'; cat "$TMP/rs.ps1"
  cat <<'PSH'
$cases = @('1:1', '1:0', ':0', '0:1', '0:0', ' 0 :1')
"RES " + (($cases | ForEach-Object { $p = $_.Split(':'); Resolve-SavedPwMode $p[0] ($p[1] -eq '1') }) -join ',')
PSH
} > "$TMP/rsh.ps1"
chk "W1 판정표 — 1·살아있음=ok · 1·없음=ok · 모름=ok · 0·살아있음=no_saved_pw · 0·없음=abort · 공백 0=no_saved_pw" "ok,ok,ok,no_saved_pw,abort,no_saved_pw" "$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TMP/rsh.ps1")" 2>&1 | tr -d '\r' | grep '^RES ' | sed 's/^RES //')"
for f in Read-SavePw Enter-NoSavedPw Test-SavePwAfterLogin; do fn_of "$f" < "$DRV"; done > "$TMP/sp.ps1"
sp_run() {  # $1 = 모래상자 maincfg 의 SAVEUSERPW 값 → RES(로그인 뒤 재확인의 결과)
  printf '[LOGIN]\r\nSAVEID=1\r\nSAVEUSERPW=%s\r\nLOGINCOMPLETE=1\r\n' "$1" > "$TMP/maincfg.ini"
  { printf '\xef\xbb\xbf'
    printf '$MAINCFG = %s\n' "'$(cygpath -w "$TMP/maincfg.ini")'"
    cat <<'PSH'
$script:NO_SAVED_PW = $false; $script:SkipLogin = $false; $script:out = @()
function Start-Sleep { }
function Write-Host { param([Parameter(ValueFromRemainingArguments = $true)] $o) $script:out += (@($o) -join ' ') }
PSH
    cat "$TMP/sp.ps1"
    cat <<'PSH'
Test-SavePwAfterLogin ((Get-Date).AddMinutes(-1))
$w = @($script:out | Where-Object { $_ -match '^WARN \[autologin\] SAVEUSERPW=0' }).Count
"RES nopw=$($script:NO_SAVED_PW) skip=$([bool]$script:SkipLogin) warn=$w"
PSH
  } > "$TMP/sph.ps1"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TMP/sph.ps1")" 2>&1 | tr -d '\r' | grep '^RES ' | sed 's/^RES //'
}
chk "W2 로그인 뒤 단말이 0 으로 씀 → 남은 로그인 끔(no_saved_pw · SkipLogin) + WARN 1줄" "nopw=True skip=True warn=1" "$(sp_run 0)"
chk "W3 로그인 뒤 1 유지 → 그대로(끄지 않음 · WARN 0)" "nopw=False skip=False warn=0" "$(sp_run 1)"
chk "W4 Ensure-Login — 로그인 끔 분기가 단말 종료(Stop-Process)보다 먼저 · 로그인 뒤 재확인 2곳(살아남 · 실패)" "YES 2" "$(printf '%s\n' "$el_new" | awk '/NO_SAVED_PW/ && !a {a=NR} /Stop-Process/ && !b {b=NR} END {print ((a && b && a < b) ? "YES" : "NO")}') $(printf '%s\n' "$el_new" | grep -c 'Test-SavePwAfterLogin \$submitAt')"
chk "W5 LoginOnly — no_saved_pw 면 로그인 없이 alive=True · exit 0 · 재시도 고리는 NO_SAVED_PW 에서 끊김" "YES YES" "$(printf '%s\n' "$lo_new" | grep -q 'no_saved_pw =====' && printf '%s\n' "$lo_new" | grep -q 'exit 0' && echo YES || echo NO) $(printf '%s\n' "$lo_new" | grep -qF 'LOGIN_BLOCKED -or $script:NO_SAVED_PW' && echo YES || echo NO)"
st_new=$(awk '/^if \(-not \$SkipLogin\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$DRV")
chk "W6 시작 점검 — 판정 함수 경유 · 중단(exit 3)은 abort 일 때만" "YES YES" "$(printf '%s\n' "$st_new" | grep -qF 'Resolve-SavedPwMode $savepw (QW-Alive)' && echo YES || echo NO) $(printf '%s\n' "$st_new" | awk '/mode -eq .abort./{f=1} f&&/exit 3/{print "YES"; exit}')"
for f in Ensure-Login Read-SavePw Enter-NoSavedPw Test-SavePwAfterLogin; do fn_of "$f" < "$DRV"; done > "$TMP/el.ps1"
el_run() {  # $1 = 모래상자 maincfg 의 SAVEUSERPW · $2 = 함수 파일 → RES(돌려준 값 · 단말 기동 횟수 · 꺼짐 표식 · WARN 수)
  printf '[LOGIN]\r\nSAVEID=1\r\nSAVEUSERPW=%s\r\nLOGINCOMPLETE=1\r\n' "$1" > "$TMP/maincfg.ini"
  { printf '\xef\xbb\xbf'
    printf '$MAINCFG = %s\n' "'$(cygpath -w "$TMP/maincfg.ini")'"
    cat <<'PSH'
$script:NO_SAVED_PW = $false; $script:SkipLogin = $false; $script:LOGIN_BLOCKED = ''; $script:KICKS = 0; $script:LOGINS_OK = 0
$script:out = @(); $script:launch = 0
## 단말 무접촉 — 프로세스 조회 · 종료 · 기동을 모두 가린다(실물 qwMain 을 건드리지 않는다)
function Get-Process { }
function Stop-Process { }
function Start-Process { $script:launch++ }
function Start-Sleep { }
function QW-Alive { $false }
function Kick-Dialog { $false }
function Write-Host { param([Parameter(ValueFromRemainingArguments = $true)] $o) $script:out += (@($o) -join ' ') }
PSH
    cat "$2"
    cat <<'PSH'
$r = Ensure-Login
$w = @($script:out | Where-Object { $_ -match '^WARN \[autologin\] SAVEUSERPW=0' }).Count
"RES ret=$r launch=$($script:launch) nopw=$($script:NO_SAVED_PW) warn=$w"
PSH
  } > "$TMP/elh.ps1"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TMP/elh.ps1")" 2>&1 | tr -d '\r' | grep '^RES ' | sed 's/^RES //'
}
chk "W8 Ensure-Login · 시작 점검 뒤 꺼짐(표식 없음 · maincfg 0) → 단말을 띄우지 않고 거짓 · 꺼짐 표식 + WARN 1줄(빈 비밀번호 제출 0)" "ret=False launch=0 nopw=True warn=1" "$(el_run 0 "$TMP/el.ps1")"
chk "W9 Ensure-Login · 저장 켜짐(1) → 종전대로 단말을 띄워 로그인(실패해도 꺼짐 표식 없음)" "ret=False launch=1 nopw=False warn=0" "$(el_run 1 "$TMP/el.ps1")"
grep -vF 'found off right before a login' "$TMP/el.ps1" > "$TMP/el_m.ps1"
if ! cmp -s "$TMP/el.ps1" "$TMP/el_m.ps1"; then
  chk "W8M 돌연변이(로그인 직전 재확인 삭제) → W8 조건에서 단말을 띄운다(빈 비밀번호 제출 경로) — W8 은 그 줄의 발화다" "launch=1" "$(el_run 0 "$TMP/el_m.ps1" | grep -o 'launch=[0-9]*')"
else chk "W8M 돌연변이 치환" YES NO; fi
OLD_SP_REV="${QVEST_TEST_QWREFRESH_SP_REV:-70397a128}"   # 비밀번호 저장 꺼짐 수리 직전 판
old_sp="$(git -C "$GITROOT" show "$OLD_SP_REV:02_Infrastructure/ops/qw_refresh.ps1" 2>/dev/null)"
chk "W7 양성 대조 — 수리 전 판($OLD_SP_REV)은 꺼짐이면 세션과 무관하게 중단했다(판정 함수 없음 · 꺼짐 분기 안 exit 3)" "YES 0" "$(printf '%s\n' "$old_sp" | awk '/if \(\$savepw -eq .0.\)/{f=1} f&&/exit 3/{print "YES"; exit}') $(printf '%s\n' "$old_sp" | grep -c 'Resolve-SavedPwMode')"
XLR="${QVEST_TEST_XLREFRESH_SRC:-$PROJ/02_Infrastructure/data/qw_excel_refresh.ps1}"
OLD_XL_REV="${QVEST_TEST_XLREFRESH_OLD_REV:-23d965420e}"   # 벤치 드라이버 수리 직전 판
OLDPAT="if (\$saveId -ne '1' -or \$savePw -ne '1'"; NEWPAT="if (-not \$autoOk) { Finish 3 'no_autologin' \$NO_AUTO_MSG }"
chk "B1 벤치 · 질의서 드라이버 — 자격 꺼짐으로 곧바로 끊는 줄 없음 · rc 3 은 두 곳(새로 띄움 · 로그인 창)뿐 · WARN 줄" "0 2 1" "$(grep -cF "$OLDPAT" "$XLR") $(grep -cF "$NEWPAT" "$XLR") $(grep -c 'WARN \[autologin\]' "$XLR")"
chk "B2 rc 3 자리 — 단말 기동(Start-Process) 앞 · 클릭 도우미(Invoke-QwClicker \$clicker) 앞" "YES YES" "$(awk -v p="$NEWPAT" 'index($0, p) && !a {a=NR} /Start-Process -FilePath \$QW_EXE/ && !b {b=NR} END {print ((a && b && a < b) ? "YES" : "NO")}' "$XLR") $(awk -v p="$NEWPAT" '/^if \(LoginWindowOpen\)/ {f=1} f && index($0, p) && !a {a=NR} f && /lrc = Invoke-QwClicker \$clicker/ && !b {b=NR} END {print ((a && b && a < b) ? "YES" : "NO")}' "$XLR")"
chk "B3 양성 대조 — 수리 전 판($OLD_XL_REV)은 자격 꺼짐이면 단말 상태와 무관하게 끊었다" "1" "$(git -C "$GITROOT" show "$OLD_XL_REV:02_Infrastructure/data/qw_excel_refresh.ps1" 2>/dev/null | grep -cF "$OLDPAT")"

fin "$PASS" "$FAIL"
