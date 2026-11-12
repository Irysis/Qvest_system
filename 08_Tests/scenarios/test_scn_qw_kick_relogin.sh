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
$script:KICKS = 0; $script:LOGIN_BLOCKED = ''
$sel = @(@{ name = 'A' }, @{ name = 'B' }); $state = @{}; $target = '20261112'
$script:plan = @{ A = @(($env:H_A -split ',') | Where-Object { $_ }); B = @(($env:H_B -split ',') | Where-Object { $_ }) }
$script:refreshes = 0; $script:logins = 0
function Is-Done($st, $n, $t) { return $st.ContainsKey($n) }
function Mark-Done($st, $n, $t) { $st[$n] = $t }
function Ensure-Login { $script:logins++; if ($env:H_LOGIN -eq 'fail') { return $false }; return $true }
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
  env H_MAXR=2 H_SKIP=0 H_STALL=30 H_A= H_B= H_ALWAYS= H_LOGIN= "$@" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$TMP/h.ps1")" 2>&1 | tr -d '\r' | grep '^RES ' | tail -n 1 | sed 's/^RES //'
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

fin "$PASS" "$FAIL"
