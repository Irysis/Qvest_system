# test_qw_dead_terminal.ps1 — 죽은 퀀티 단말 감지 · 정리(qw_dead_terminal.ps1)의 실물 검사
#   실행 = 08_Tests/data/test_qw_dead_terminal.sh (배터리 편입 · 마지막 줄 JSON).
#   실제 메시지 창(#32770)을 자식 PowerShell 로 띄워 판정한다 — 창 열거 · 글자 읽기(WM_GETTEXT) · 버튼 ID 까지 진짜 경로.
#
# 계약 (한쪽만 재면 검사 사망과 정상이 겉보기 같다 — 양성 · 음성 · 뮤테이션을 함께 잰다):
#   L1 양성  '오류' · '예기치 않은 오류가 발생하였습니다. 종료합니다.' · 확인          → 감지 1 · 정리 뒤 프로세스 소멸
#   L2 양성  다른 기기 로그인 종료 알림(확인)                                       → 감지 1 · 정리 뒤 소멸
#   L3 음성  중복 로그인 경고 '…종료되지 않았습니다. 로그인 하시겠습니까?' · 예/아니오 → 감지 0
#   L4 음성  무관한 알림 'Refresh 완료' · 확인                                      → 감지 0
#   L5 음성  '종료합니다' 를 담았지만 예/아니오로 묻는 창                             → 감지 0 (예/아니오 분기 단독 확인)
#   L6 PID 재사용 방지 — 시작 시각이 다른 기록으로 정리를 부르면 살아 있는 프로세스를 건드리지 않는다
#   M1 뮤테이션 — 문구 정규식을 깨면 L1 을 놓친다(= L1 이 회귀를 잡는다)
#   M2 뮤테이션 — 예/아니오 제외를 지우면 L5 를 잡는다(= L5 가 회귀를 잡는다)
#   ★뮤테이션 사본은 소스 텍스트 치환 · 치환 성사 단정 · 별도 프로세스 단독 실행(메모리 규칙 10-15).
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$MOD = Join-Path $Root '02_Infrastructure\data\qw_dead_terminal.ps1'
. $MOD

$script:PASS = 0; $script:FAIL = 0; $script:SKIP = 0
function Ok($m) { Write-Output "  [PASS] $m"; $script:PASS++ }
function Ng($m) { Write-Output "  [FAIL] $m"; $script:FAIL++ }
function Sk($m) { Write-Output "  [SKIP] $m"; $script:SKIP++ }

function Spawn-Box([string]$Text, [string]$Title, [string]$Buttons) {
  $cmd = "Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show('$Text', '$Title', '$Buttons', 'Error')"
  $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
  return Start-Process powershell -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $b64 -PassThru -WindowStyle Minimized
}
function Wait-Box($Proc, [int]$Sec = 20) {
  $dl = (Get-Date).AddSeconds($Sec)
  while ((Get-Date) -lt $dl) {
    if ($Proc.HasExited) { return $false }
    if (@([QwDead.W]::Dialogs([uint32[]]@($Proc.Id))).Count -gt 0) { return $true }
    Start-Sleep -Milliseconds 300
  }
  return $false
}
function Run-Mutant([string]$Find, [string]$Repl, [int]$TargetPid) {
  # 반환: 뮤턴트가 대상 창에서 감지한 개수 · 치환 실패면 -1
  $src = [IO.File]::ReadAllText($MOD, [Text.Encoding]::UTF8)
  if (-not $src.Contains($Find)) { return -1 }
  $mut = Join-Path ([IO.Path]::GetTempPath()) ("qw_dead_mutant_{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
  [IO.File]::WriteAllText($mut, $src.Replace($Find, $Repl), (New-Object Text.UTF8Encoding $true))
  try {
    $code = ". '{0}'; Write-Output ('N=' + @(Get-QwDeadDialogs @({1})).Count)" -f ($mut -replace '\\', '/'), $TargetPid
    $out = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $code 2>&1
    $m = [regex]::Match(($out -join "`n"), 'N=(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -2 }
  } finally { Remove-Item -LiteralPath $mut -Force -ErrorAction SilentlyContinue }
}

$cases = [ordered]@{
  L1 = @{ text = '예기치 않은 오류가 발생하였습니다. 종료합니다.'; title = '오류'; buttons = 'OK'; want = 1 }
  L2 = @{ text = '[TESTPC(10.0.0.1)]에서 같은 아이디로 로그인하여 아이디 중복사용으로 프로그램을 종료합니다.'; title = 'Quantiwise7G'; buttons = 'OK'; want = 1 }
  L3 = @{ text = '[TESTPC(10.0.0.1)]에서 사용중이거나 정상적으로 종료되지 않았습니다. 로그인 하시겠습니까?'; title = 'Quantiwise7G'; buttons = 'YesNo'; want = 0 }
  L4 = @{ text = 'Refresh 완료'; title = 'Quantiwise7G'; buttons = 'OK'; want = 0 }
  L5 = @{ text = '프로그램을 종료합니다. 계속하시겠습니까?'; title = 'Quantiwise7G'; buttons = 'YesNo'; want = 0 }
}
$procs = @{}
try {
  foreach ($k in $cases.Keys) { $c = $cases[$k]; $procs[$k] = Spawn-Box $c.text $c.title $c.buttons }
  $up = @{}
  foreach ($k in $cases.Keys) { $up[$k] = Wait-Box $procs[$k] }
  if (@($up.Values | Where-Object { $_ }).Count -eq 0) {
    Sk "메시지 창이 하나도 뜨지 않았다(대화형 데스크톱 없음?) — 실물 검사 L1~L6 · M1~M2 건너뜀"
  } else {
    foreach ($k in $cases.Keys) {
      $c = $cases[$k]
      if (-not $up[$k]) { Ng "$k 메시지 창이 20초 안에 뜨지 않았다(다른 창은 떴다)"; continue }
      $n = @(Get-QwDeadDialogs @($procs[$k].Id)).Count
      if ($n -eq $c.want) { Ok "$k 감지 $n (기대 $($c.want)) — '$($c.text)' [$($c.buttons)]" }
      else { Ng "$k 감지 $n (기대 $($c.want)) — '$($c.text)' [$($c.buttons)]" }
    }
    # L1 의 읽은 글자가 원문 그대로인가(글자 읽기 경로 · 인코딩)
    if ($up['L1']) {
      $d = @(Get-QwDeadDialogs @($procs['L1'].Id))
      if ($d.Count -eq 1 -and $d[0].text -eq $cases['L1'].text -and $d[0].title -eq '오류') { Ok "L1 글자 · 제목 원문 일치(WM_GETTEXT · BOM 판독)" }
      else { Ng ("L1 글자 불일치: title=[{0}] text=[{1}]" -f ($d | ForEach-Object title), ($d | ForEach-Object text)) }
    }
    # M1 · M2 뮤테이션 (창이 떠 있는 동안 별도 프로세스로)
    if ($up['L1']) {
      $m1 = Run-Mutant "'종료합니다|종료됩니다|예기치 않은 오류'" "'ZZZZ_NEVER'" $procs['L1'].Id
      if ($m1 -eq -1) { Ng 'M1 치환 실패 — 정규식 원문이 바뀌었다(검사 갱신 필요)' }
      elseif ($m1 -eq 0) { Ok 'M1 문구 정규식을 깬 뮤턴트는 L1 을 놓친다(N=0) — L1 이 회귀를 잡는다' }
      else { Ng "M1 뮤턴트가 여전히 L1 을 잡았다(N=$m1) — L1 이 정규식을 재지 않는다" }
    }
    if ($up['L5']) {
      $m2 = Run-Mutant 'if ($d.HasYesNo) { continue }' '' $procs['L5'].Id
      if ($m2 -eq -1) { Ng 'M2 치환 실패 — 예/아니오 제외 원문이 바뀌었다(검사 갱신 필요)' }
      elseif ($m2 -eq 1) { Ok 'M2 예/아니오 제외를 지운 뮤턴트는 L5 를 잡는다(N=1) — L5 가 회귀를 잡는다' }
      else { Ng "M2 뮤턴트 결과 N=$m2 (기대 1)" }
    }
    # L6 PID 재사용 방지 — L4(음성 · 살아 있음)를 틀린 시작 시각으로 정리 요청
    if ($up['L4']) {
      $fake = @([pscustomobject]@{ pid = $procs['L4'].Id; start = (Get-Date '2000-01-01'); hwnd = 0; title = ''; text = '' })
      $r6 = Close-QwDeadTerminal $fake 2
      if ($r6 -eq 'closed' -and -not $procs['L4'].HasExited -and (Get-Process -Id $procs['L4'].Id -ErrorAction SilentlyContinue)) {
        Ok "L6 시작 시각이 다른 기록은 건드리지 않는다(결과=$r6 · 대상 생존)"
      } else { Ng "L6 PID 재사용 방지 실패(결과=$r6 · 대상 종료=$($procs['L4'].HasExited))" }
    }
    # L1 · L2 정리 — 확인으로 스스로 끝나거나 강제 종료되어 프로세스가 사라져야 한다
    foreach ($k in 'L1', 'L2') {
      if (-not $up[$k]) { continue }
      $d = @(Get-QwDeadDialogs @($procs[$k].Id))
      if ($d.Count -ne 1) { Ng "$k 정리 전 감지가 1이 아니다($($d.Count))"; continue }
      $r = Close-QwDeadTerminal $d 15
      $procs[$k].Refresh()
      if (($r -eq 'closed' -or $r -eq 'killed') -and $procs[$k].HasExited) { Ok "$k 정리 = $r · 프로세스 소멸" }
      else { Ng "$k 정리 = $r · 종료=$($procs[$k].HasExited)" }
    }
  }
} finally {
  foreach ($p in $procs.Values) { if ($p -and -not $p.HasExited) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {} } }
}
Write-Output ("결과: PASS={0} FAIL={1} SKIP={2}" -f $script:PASS, $script:FAIL, $script:SKIP)
Write-Output ('{{"test":"qw_dead_terminal_live","pass":{0},"fail":{1},"skipped":{2},"total":{3}}}' -f $script:PASS, $script:FAIL, $script:SKIP, ($script:PASS + $script:FAIL + $script:SKIP))
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
