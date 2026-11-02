<#
qvest_tasks.ps1 — Qvest 예약 작업을 '메인 우선 게이트' 실행기로 감싸 등록 · 되돌림 · 내보내기 (2026-11-01 두 대 운용)

  -Mode Export    -Out <폴더>               이 기계의 Qvest 예약 작업 원본 XML 을 내보낸다(감싼 작업은 jobs\orig 원본으로).
                                            대상 = 이름 Qvest* 또는 동작이 Quant_Module_Moltbot 을 부르는 작업(\Microsoft\ 제외).
  -Mode Apply     -From <폴더> [-Name ..]   원본 XML 을 이 기계 계정으로 고치고 감싸서 등록한다(같은 이름은 덮어씀).
                  [-Out <폴더>]              실행기 · 감싼 XML 미리보기를 그 폴더에도 쓴다(-WhatIf 와 함께 쓰면 계획만).
  -Mode Restore   [-Name ..]                감싸기 전 원본(jobs\orig)으로 되돌린다.
  -Mode Heartbeat [-Remove]                 메인 생존 신호 작업(Qvest_MachineHeartbeat · 5분 + 로그온)을 등록 · 해제 — main 만.
  -Mode Status                              역할 · 생존 신호 · 감싼 작업 목록.
  공통: -WhatIf(쓰기 없이 계획만) · -Root <프로젝트>(기본 QM_ROOT → 이 스크립트 위치) · -Period <주기>(전 작업 덮어쓰기 — 검사용)
        -Visible(창 없는 실행 대신 보이는 cmd 창 — 원래 작업과 같은 모습)

감싸기: 작업 동작을 pythonw.exe %LOCALAPPDATA%\Qvest\hidden_launch.pyw %LOCALAPPDATA%\Qvest\jobs\<작업>.cmd 로 바꾼다
  (창 없이 cmd /c 실행기 · 종료 코드 그대로 → LastTaskResult(scheduler_task_health.ps1 이 읽는다) · 출력은
  %LOCALAPPDATA%\Qvest\logs\<작업>.log). pythonw 가 없거나 -Visible 이면 cmd.exe /d /c <실행기>(창 보임).
  conhost --headless 는 쓰지 않는다 — 자식 종료 코드를 버리고(항상 0) 작업 스케줄러 아래선 실행기가 돌지 않았다(2026-11-01 실측).
  실행기는
  ① bash qvest_machine.sh gate <작업> <주기> — 10 이면 건너뜀(종료 0) · bash 나 게이트가 없으면 그냥 실행(fail-open)
  ② 원래 동작 그대로(.bat/.cmd 는 별도 cmd, 그 밖은 직접 · 작업 폴더 유지)  ③ done <작업> <주기> <rc> 기록.
  주기 추정: 반복 간격 <1h = none · ≥1h = hour · 시각 트리거 2개 이상 = hour · 주간 요일 1개 = week · 여럿 = day ·
    월간 날짜 1개 = month · 여럿 = day · 그 외(로그온 · 1회 등) = day. machines.conf 의 period 줄이 실행 때 덮어쓴다.
  꺼진 작업의 실행기는 jobs\off\ — 생존 신호의 jobs 목록(메인이 맡는 작업)에서 빠진다. 켜고 끄기를 바꾸면 Apply 를 다시.
  계정: UserId = 이 기계 사용자 SID · LogonType Password/S4U → InteractiveToken(암호를 저장하지 않는다 —
    로그인해 있을 때만 돈다. OneDrive 파일은 사용자 세션이 있어야 내려온다).
  ExecutionTimeLimit 이 24h 미만이면 +12분(게이트 대기 최대 10분).
규칙 · 상태 파일 = qvest_machine.sh 머리말. 검사 = 08_Tests/ops/test_qvest_machine.sh(게이트) · README.md(실측 절차).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Export', 'Apply', 'Restore', 'Heartbeat', 'Status')]
  [string]$Mode,
  [string]$From,
  [string]$Out,
  [string[]]$Name,
  [string]$Root,
  [ValidateSet('', 'day', 'week', 'month', 'hour', 'none', 'local')]
  [string]$Period = '',
  [switch]$Visible,
  [switch]$Remove,
  [switch]$Force,
  [string]$Base                                  # 실행기 · 원본 · 로그 폴더(기본 %LOCALAPPDATA%\Qvest — 검사는 다른 곳)
)
$ErrorActionPreference = 'Stop'
$script:Rc = 0

if (-not $Root) { $Root = $env:QM_ROOT }
if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')) }
$Root = ($Root -replace '/', '\').TrimEnd('\')
$GateW = Join-Path $Root '02_Infrastructure\ops\machine\qvest_machine.sh'
$GateU = $GateW -replace '\\', '/'          # bash 의 dirname 은 역슬래시를 나누지 못한다
if (-not $Base) { $Base = Join-Path $env:LOCALAPPDATA 'Qvest' }
$Jobs = Join-Path $Base 'jobs'
$OffDir = Join-Path $Jobs 'off'
$OrigDir = Join-Path $Jobs 'orig'
$Sys32 = Join-Path $env:SystemRoot 'System32'
$TaskNS = 'http://schemas.microsoft.com/windows/2004/02/mit/task'
$HbName = 'Qvest_MachineHeartbeat'

function Find-GitBash {
  $c = @()
  if ($env:ProgramFiles) { $c += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
  $g = Get-Command git.exe -ErrorAction SilentlyContinue
  if ($null -ne $g) { $c += (Join-Path (Split-Path (Split-Path $g.Source -Parent) -Parent) 'bin\bash.exe') }
  foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }   # System32\bash.exe(WSL)는 쓰지 않는다
  return $null
}
$Bash = Find-GitBash

# 창 없는 실행용 pythonw — OneDrive 밖 기본 설치(내려받기 대기 없음) 우선, WindowsApps 스텁 제외
function Find-PythonW {
  $c = @()
  if ($env:LOCALAPPDATA) { $c += @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python3*\pythonw.exe') -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | ForEach-Object { $_.FullName }) }
  $g = Get-Command pythonw.exe -ErrorAction SilentlyContinue
  if ($null -ne $g -and $g.Source -notmatch '\\WindowsApps\\') { $c += $g.Source }
  foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }
  return $null
}
$PyW = $(if ($Visible) { $null } else { Find-PythonW })
$Launcher = Join-Path $Base 'hidden_launch.pyw'
$LauncherText = @'
# hidden_launch.pyw - Qvest gated-runner launcher without a console window. Written by qvest_tasks.ps1 (do not edit).
# usage: pythonw.exe hidden_launch.pyw <runner.cmd>   exit code = the runner's (Task Scheduler LastTaskResult)
# output -> logs\<runner>.log (rotated at 2 MB). stdio must not be left as pythonw's dummy pipes: a chatty job would block.
import datetime, os, subprocess, sys

NO_WINDOW = 0x08000000
runner = sys.argv[1]
cmd = [os.environ.get('ComSpec') or r'C:\Windows\System32\cmd.exe', '/d', '/c', runner]
try:
    logdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'logs')
    os.makedirs(logdir, exist_ok=True)
    log = os.path.join(logdir, os.path.splitext(os.path.basename(runner))[0] + '.log')
    if os.path.exists(log) and os.path.getsize(log) > 2000000:
        os.replace(log, log + '.1')
    out = open(log, 'ab')
    out.write(('--- %s %s\r\n' % (datetime.datetime.now().isoformat(timespec='seconds'), runner)).encode())
    out.flush()
except OSError:
    out = subprocess.DEVNULL
rc = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT, creationflags=NO_WINDOW).returncode
if out is not subprocess.DEVNULL:
    out.write(('--- rc=%d\r\n' % rc).encode())
    out.close()
sys.exit(rc)
'@

function Install-Launcher {
  if (-not $PyW) { return }
  [void](New-Item -ItemType Directory -Force -Path $Base)
  [IO.File]::WriteAllText($Launcher, $LauncherText, (New-Object Text.UTF8Encoding($false)))
}

function Read-TaskXml([string]$path) {
  $b = [IO.File]::ReadAllBytes($path)
  $encs = @([Text.Encoding]::Unicode, [Text.Encoding]::UTF8)
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $encs = @([Text.Encoding]::UTF8) }
  elseif ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { $encs = @([Text.Encoding]::Unicode) }
  foreach ($e in $encs) {
    try {
      $x = New-Object Xml.XmlDocument
      $x.LoadXml($e.GetString($b).TrimStart([char]0xFEFF))
      return , $x                                            # XmlDocument 는 열거형 — 쉼표 없으면 자식 노드로 풀린다
    } catch { }
  }
  throw "XML 을 읽지 못함(인코딩 · 형식): $path"
}

function New-Ns($x) { $n = New-Object Xml.XmlNamespaceManager($x.NameTable); $n.AddNamespace('t', $TaskNS); return , $n }

function Get-NodeText($node, [string]$xp, $ns) {
  $s = $node.SelectSingleNode($xp, $ns)
  if ($null -eq $s) { return '' }
  return [string]$s.InnerText
}

function Get-SafeName([string]$n) { return ($n -replace '[^A-Za-z0-9_.-]', '_') }

function Get-TaskId($x, $ns, [string]$file) {
  $u = Get-NodeText $x '/t:Task/t:RegistrationInfo/t:URI' $ns
  if ($u) {
    $i = $u.LastIndexOf('\')
    $p = $u.Substring(0, $i + 1); if (-not $p) { $p = '\' }
    return [pscustomobject]@{ Name = $u.Substring($i + 1); Path = $p }
  }
  return [pscustomobject]@{ Name = [IO.Path]::GetFileNameWithoutExtension($file); Path = '\' }
}

function Get-ExecActions($x, $ns) {
  $r = @()
  foreach ($e in @($x.SelectNodes('/t:Task/t:Actions/t:Exec', $ns))) {
    $r += [pscustomobject]@{
      Command          = (Get-NodeText $e 't:Command' $ns).Trim()
      Arguments        = (Get-NodeText $e 't:Arguments' $ns)
      WorkingDirectory = (Get-NodeText $e 't:WorkingDirectory' $ns).Trim().Trim('"')
    }
  }
  return , $r
}

function Get-Period($x, $ns) {
  $trs = @($x.SelectNodes('/t:Task/t:Triggers/*', $ns))
  if ($trs.Count -eq 0) { return 'day' }
  $hour = $false
  foreach ($t in $trs) {
    $iv = Get-NodeText $t 't:Repetition/t:Interval' $ns
    if ($iv) {
      if ([Xml.XmlConvert]::ToTimeSpan($iv).TotalMinutes -lt 60) { return 'none' }
      $hour = $true
    }
  }
  if ($hour) { return 'hour' }
  $timed = @($trs | Where-Object { $_.LocalName -eq 'TimeTrigger' -or $_.LocalName -eq 'CalendarTrigger' })
  if ($timed.Count -gt 1) { return 'hour' }
  if ($timed.Count -eq 1) {
    $t = $timed[0]
    $w = $t.SelectSingleNode('t:ScheduleByWeek', $ns)
    if ($null -ne $w) { if (@($w.SelectNodes('t:DaysOfWeek/*', $ns)).Count -le 1) { return 'week' } else { return 'day' } }
    $m = $t.SelectSingleNode('t:ScheduleByMonth', $ns)
    if ($null -ne $m) { if (@($m.SelectNodes('t:DaysOfMonth/t:Day', $ns)).Count -gt 1) { return 'day' } else { return 'month' } }
    if ($null -ne $t.SelectSingleNode('t:ScheduleByMonthDayOfWeek', $ns)) { return 'month' }
  }
  return 'day'
}

function Get-TaskEnabled($x, $ns) { return ((Get-NodeText $x '/t:Task/t:Settings/t:Enabled' $ns).Trim() -ne 'false') }

function Set-TaskEnabled($x, $ns, [bool]$on) {
  $s = $x.SelectSingleNode('/t:Task/t:Settings', $ns)
  if ($null -eq $s) { return }
  $e = $s.SelectSingleNode('t:Enabled', $ns)
  if ($null -eq $e) { $e = $x.CreateElement('Enabled', $TaskNS); [void]$s.AppendChild($e) }
  $e.InnerText = $(if ($on) { 'true' } else { 'false' })
}

# 다른 기계에서 온 XML 을 이 기계 사용자로 — SID · 계정 이름 · 로그온 방식(암호 저장 없음)
function Set-ThisMachineAccount($x, $ns) {
  $me = [Security.Principal.WindowsIdentity]::GetCurrent()
  foreach ($p in @($x.SelectNodes('/t:Task/t:Principals/t:Principal', $ns))) {
    $u = $p.SelectSingleNode('t:UserId', $ns)
    if ($null -eq $u) { continue }
    if ($u.InnerText -match '^S-1-5-(18|19|20)$' -or $u.InnerText -match '^(NT AUTHORITY\\|SYSTEM$|LOCAL SERVICE$|NETWORK SERVICE$)') { continue }
    $u.InnerText = $me.User.Value
    $lt = $p.SelectSingleNode('t:LogonType', $ns)
    if ($null -ne $lt -and @('Password', 'S4U', 'InteractiveTokenOrPassword') -contains $lt.InnerText) { $lt.InnerText = 'InteractiveToken' }
  }
  foreach ($u in @($x.SelectNodes('/t:Task/t:Triggers/*/t:UserId', $ns))) { $u.InnerText = $me.Name }
  $a = $x.SelectSingleNode('/t:Task/t:RegistrationInfo/t:Author', $ns)
  if ($null -ne $a) { $a.InnerText = $me.Name }
}

function Add-GateTime($x, $ns) {
  $e = $x.SelectSingleNode('/t:Task/t:Settings/t:ExecutionTimeLimit', $ns)
  if ($null -eq $e -or -not $e.InnerText) { return }
  $ts = [Xml.XmlConvert]::ToTimeSpan($e.InnerText)
  if ($ts -gt [TimeSpan]::Zero -and $ts -lt [TimeSpan]::FromHours(24)) { $e.InnerText = [Xml.XmlConvert]::ToString($ts.Add([TimeSpan]::FromMinutes(12))) }
}

# 작업 스케줄러가 넘기던 문자열을 .cmd 한 줄로 — %NAME%(정의된 변수)는 그대로(스케줄러도 펼친다) · 그 밖의 % 는 %% ·
#   -EscapeOps 면 따옴표 밖 ^ & | < > 를 ^ 로(스케줄러는 연산자로 읽지 않았다)
function ConvertTo-CmdText([string]$s, [switch]$EscapeOps) {
  $sb = New-Object Text.StringBuilder
  $q = $false; $i = 0
  while ($i -lt $s.Length) {
    $c = $s[$i]
    if ($c -eq '"') { $q = -not $q; [void]$sb.Append($c); $i++; continue }
    if ($c -eq '%') {
      $j = $s.IndexOf('%', $i + 1)
      if ($j -gt $i + 1) {
        $n = $s.Substring($i + 1, $j - $i - 1)
        if ($n -match '^[A-Za-z_][A-Za-z0-9_()]*$' -and $null -ne [Environment]::GetEnvironmentVariable($n)) {
          [void]$sb.Append($s.Substring($i, $j - $i + 1)); $i = $j + 1; continue
        }
      }
      [void]$sb.Append('%%'); $i++; continue
    }
    if ($EscapeOps -and -not $q -and '^&|<>'.IndexOf($c) -ge 0) { [void]$sb.Append('^') }
    [void]$sb.Append($c); $i++
  }
  return $sb.ToString()
}

function New-RunnerText([string]$job, [string]$per, $acts, [string]$src) {
  $L = New-Object Collections.Generic.List[string]
  $L.Add('@echo off')
  $L.Add("rem Qvest gated runner - generated by qvest_tasks.ps1 $(Get-Date -Format s). Do not edit: re-run qvest_tasks.ps1 -Mode Apply.")
  $L.Add("rem job=$job period=$per source=$src")
  $L.Add('setlocal')
  $L.Add("title Qvest $job")
  $L.Add("echo [Qvest] %DATE% %TIME% $job period=$per - main-priority gate (may wait a few minutes)")
  $L.Add("set `"QV_BASH=$Bash`"")
  $L.Add("set `"QV_GATEW=$GateW`"")
  $L.Add("set `"QV_GATE=$GateU`"")
  $L.Add('if not exist "%QV_BASH%" goto :qv_run')
  $L.Add('if not exist "%QV_GATEW%" goto :qv_run')
  $L.Add("`"%QV_BASH%`" `"%QV_GATE%`" gate $job $per")
  $L.Add('if "%ERRORLEVEL%"=="10" exit /b 0')
  $L.Add(':qv_run')
  foreach ($a in $acts) {
    if ($a.WorkingDirectory) { $L.Add('cd /d "' + (ConvertTo-CmdText $a.WorkingDirectory) + '"') }
    $cmd = $a.Command.Trim('"')
    if ($cmd -match '\.(bat|cmd)$') {
      $inner = '"' + (ConvertTo-CmdText $cmd) + '"'
      if ($a.Arguments) { $inner += ' ' + (ConvertTo-CmdText $a.Arguments) }
      $L.Add('cmd /s /c "' + $inner + '"')                   # exit(/b 없음)가 실행기를 끊지 않게 별도 cmd
    } else {
      $line = '"' + (ConvertTo-CmdText $cmd) + '"'
      if ($a.Arguments) { $line += ' ' + (ConvertTo-CmdText $a.Arguments -EscapeOps) }
      $L.Add($line)
    }
  }
  $L.Add('set "QV_RC=%ERRORLEVEL%"')
  $L.Add("if exist `"%QV_BASH%`" if exist `"%QV_GATEW%`" `"%QV_BASH%`" `"%QV_GATE%`" done $job $per %QV_RC%")
  $L.Add('exit /b %QV_RC%')
  return (($L -join "`r`n") + "`r`n")
}

function Get-RunnerArg([string]$runner) {
  $q = { param($p) if ($p -match '\s') { '"' + $p + '"' } else { $p } }
  if ($PyW) { return @($PyW, ((& $q $Launcher) + ' ' + (& $q $runner))) }
  return @((Join-Path $Sys32 'cmd.exe'), ('/d /c ' + (& $q $runner)))
}

function Set-WrappedAction($x, $ns, [string]$runner, [string]$wd) {
  $acts = $x.SelectSingleNode('/t:Task/t:Actions', $ns)
  foreach ($n in @($acts.SelectNodes('t:Exec', $ns))) { [void]$acts.RemoveChild($n) }
  $ca = Get-RunnerArg $runner
  $e = $x.CreateElement('Exec', $TaskNS)
  $c = $x.CreateElement('Command', $TaskNS); $c.InnerText = $ca[0]; [void]$e.AppendChild($c)
  $g = $x.CreateElement('Arguments', $TaskNS); $g.InnerText = $ca[1]; [void]$e.AppendChild($g)
  if ($wd) { $w = $x.CreateElement('WorkingDirectory', $TaskNS); $w.InnerText = $wd; [void]$e.AppendChild($w) }
  [void]$acts.AppendChild($e)
}

function Read-ConfPeriods {
  $h = @{}
  $c = Join-Path $PSScriptRoot 'machines.conf'
  if (Test-Path -LiteralPath $c) {
    foreach ($l in [IO.File]::ReadAllLines($c, [Text.Encoding]::UTF8)) {
      $w = (($l -replace '#.*$', '').Trim()) -split '\s+'
      if ($w.Count -ge 3 -and $w[0] -eq 'period') { $h[$w[1]] = $w[2] }
    }
  }
  return $h
}

function Get-Role {
  if (-not $Bash -or -not (Test-Path -LiteralPath $GateW)) { return 'unknown' }
  $r = & $Bash $GateU role 2>$null | Select-Object -First 1
  return [string]$r
}

function Invoke-Apply {
  if (-not $From -or -not (Test-Path -LiteralPath $From)) { throw '-From <원본 XML 폴더> 가 필요합니다' }
  if (-not $Bash) { Write-Warning 'Git Bash 를 찾지 못함 — 실행기는 게이트 없이 원래 동작만 돈다(fail-open).' }
  if (-not (Test-Path -LiteralPath $GateW)) { Write-Warning "게이트 없음: $GateW — 실행기는 게이트 없이 돈다(fail-open)." }
  Write-Host "root=$Root role=$(Get-Role) jobs=$Jobs launcher=$(if ($PyW) { "hidden ($PyW)" } else { 'visible cmd' })"
  if (-not $PyW -and -not $Visible) { Write-Warning 'pythonw.exe 를 찾지 못함 — 보이는 cmd 창으로 등록한다.' }
  if ($PSCmdlet.ShouldProcess($Launcher, '창 없는 실행기 쓰기')) { Install-Launcher }
  $conf = Read-ConfPeriods
  foreach ($f in @(Get-ChildItem -LiteralPath $From -Filter *.xml -File | Sort-Object Name)) {
    try {
      $x = Read-TaskXml $f.FullName
      $ns = New-Ns $x
      $id = Get-TaskId $x $ns $f.FullName
      if ($Name -and ($Name -notcontains $id.Name)) { continue }
      if ($id.Name -eq $HbName) { continue }
      $other = @($x.SelectNodes('/t:Task/t:Actions/*', $ns) | Where-Object { $_.LocalName -ne 'Exec' })
      if ($other.Count -gt 0) { Write-Host "SKIP    $($id.Name) - Exec 아닌 동작($($other[0].LocalName))은 감싸지 않음"; continue }
      $acts = Get-ExecActions $x $ns
      if ($acts.Count -eq 0) { Write-Host "SKIP    $($id.Name) - 동작 없음"; continue }
      if (@($acts | Where-Object { "$($_.Command) $($_.Arguments)" -match '\\Qvest\\jobs\\' }).Count -gt 0) {
        Write-Host "SKIP    $($id.Name) - 이미 감싼 XML(원본이 아님)"; continue
      }
      $safe = Get-SafeName $id.Name
      $per = $(if ($Period) { $Period } else { Get-Period $x $ns })
      $eff = $(if ($conf.ContainsKey($safe)) { "$per->$($conf[$safe])(conf)" } else { $per })
      $on = Get-TaskEnabled $x $ns
      $runner = Join-Path $(if ($on) { $Jobs } else { $OffDir }) "$safe.cmd"
      $runText = New-RunnerText $safe $per $acts $f.Name
      Set-ThisMachineAccount $x $ns
      Add-GateTime $x $ns
      Set-WrappedAction $x $ns $runner $acts[0].WorkingDirectory
      $xmlText = $x.OuterXml
      if ($Out) {
        [void](New-Item -ItemType Directory -Force -Path $Out -WhatIf:$false)
        [IO.File]::WriteAllText((Join-Path $Out "$safe.cmd"), $runText, [Text.Encoding]::Default)
        [IO.File]::WriteAllText((Join-Path $Out "$safe.wrapped.xml"), $xmlText, [Text.Encoding]::Unicode)
      }
      if ($PSCmdlet.ShouldProcess("$($id.Path)$($id.Name)", "감싸서 등록 (period=$eff)")) {
        [void](New-Item -ItemType Directory -Force -Path $Jobs, $OffDir, $OrigDir)
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $OrigDir "$safe.xml") -Force
        foreach ($old in @((Join-Path $Jobs "$safe.cmd"), (Join-Path $OffDir "$safe.cmd"))) { if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force } }
        [IO.File]::WriteAllText($runner, $runText, [Text.Encoding]::Default)
        [void](Register-ScheduledTask -Xml $xmlText -TaskName $id.Name -TaskPath $id.Path -Force)
      }
      Write-Host ('APPLY   {0,-36} period={1,-18} enabled={2,-5} runner={3}' -f $id.Name, $eff, $on, $runner)
    } catch {
      Write-Host "FAIL    $($f.Name): $($_.Exception.Message)"; $script:Rc = 1
    }
  }
}

function Invoke-Restore {
  if (-not (Test-Path -LiteralPath $OrigDir)) { Write-Host "되돌릴 원본 없음: $OrigDir"; return }
  foreach ($f in @(Get-ChildItem -LiteralPath $OrigDir -Filter *.xml -File | Sort-Object Name)) {
    try {
      $x = Read-TaskXml $f.FullName
      $ns = New-Ns $x
      $id = Get-TaskId $x $ns $f.FullName
      if ($Name -and ($Name -notcontains $id.Name)) { continue }
      $safe = Get-SafeName $id.Name
      $live = Get-ScheduledTask -TaskName $id.Name -TaskPath $id.Path -ErrorAction SilentlyContinue
      if ($null -ne $live) { Set-TaskEnabled $x $ns ($live.State -ne 'Disabled') }
      Set-ThisMachineAccount $x $ns
      if ($PSCmdlet.ShouldProcess("$($id.Path)$($id.Name)", '원본으로 되돌림')) {
        [void](Register-ScheduledTask -Xml $x.OuterXml -TaskName $id.Name -TaskPath $id.Path -Force)
        foreach ($old in @((Join-Path $Jobs "$safe.cmd"), (Join-Path $OffDir "$safe.cmd"), $f.FullName)) { if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force } }
      }
      Write-Host "RESTORE $($id.Name)"
    } catch {
      Write-Host "FAIL    $($f.Name): $($_.Exception.Message)"; $script:Rc = 1
    }
  }
}

function Invoke-Export {
  if (-not $Out) { throw '-Out <폴더> 가 필요합니다' }
  [void](New-Item -ItemType Directory -Force -Path $Out)
  $idx = New-Object Collections.Generic.List[string]
  $idx.Add("name`tpath`tstate`tperiod`tlast_run`tlast_result`tnext_run`tsource`tactions")
  foreach ($t in @(Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.TaskName -ne $HbName })) {
    try {
      $at = (@($t.Actions) | ForEach-Object { "$($_.Execute) $($_.Arguments) [$($_.WorkingDirectory)]" }) -join ' | '
      $wrapped = $at -match '\\Qvest\\jobs\\'
      if ($Name) { if ($Name -notcontains $t.TaskName) { continue } }
      elseif (-not ($t.TaskName -like 'Qvest*' -or $at -match 'Quant_Module_Moltbot' -or $wrapped)) { continue }
      $safe = Get-SafeName $t.TaskName
      $orig = Join-Path $OrigDir "$safe.xml"
      if ($wrapped) {
        if (-not (Test-Path -LiteralPath $orig)) { Write-Warning "$($t.TaskName): 감싼 작업인데 원본(jobs\orig)이 없어 건너뜀"; continue }
        $x = Read-TaskXml $orig; $ns = New-Ns $x
        Set-TaskEnabled $x $ns ($t.State -ne 'Disabled')
        $text = $x.OuterXml; $src = 'orig'
      } else {
        $text = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath
        $x = New-Object Xml.XmlDocument; $x.LoadXml($text); $ns = New-Ns $x; $src = 'live'
      }
      $per = Get-Period $x $ns
      $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
      if ($PSCmdlet.ShouldProcess((Join-Path $Out "$safe.xml"), 'XML 내보내기')) {
        [IO.File]::WriteAllText((Join-Path $Out "$safe.xml"), $text, [Text.Encoding]::Unicode)
      }
      $lr = $(if ($null -ne $info) { '{0:yyyy-MM-ddTHH:mm}' -f $info.LastRunTime } else { '' })
      $nr = $(if ($null -ne $info) { '{0:yyyy-MM-ddTHH:mm}' -f $info.NextRunTime } else { '' })
      $rc = $(if ($null -ne $info) { $info.LastTaskResult } else { '' })
      $idx.Add(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}" -f $t.TaskName, $t.TaskPath, $t.State, $per, $lr, $rc, $nr, $src, ($at -replace "`t", ' ')))
      Write-Host ('EXPORT  {0,-36} state={1,-8} period={2,-5} src={3}' -f $t.TaskName, $t.State, $per, $src)
    } catch {
      Write-Host "FAIL    $($t.TaskName): $($_.Exception.Message)"; $script:Rc = 1
    }
  }
  if ($PSCmdlet.ShouldProcess((Join-Path $Out 'tasks_index.tsv'), '목록 쓰기')) {
    [IO.File]::WriteAllLines((Join-Path $Out 'tasks_index.tsv'), $idx, (New-Object Text.UTF8Encoding($true)))
  }
}

function Invoke-Heartbeat {
  $hb = Join-Path $Base 'heartbeat.cmd'
  if ($Remove) {
    if ($PSCmdlet.ShouldProcess($HbName, '등록 해제')) {
      Unregister-ScheduledTask -TaskName $HbName -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue
      if (Test-Path -LiteralPath $hb) { Remove-Item -LiteralPath $hb -Force }
    }
    Write-Host "REMOVED $HbName"; return
  }
  if (-not $Bash) { throw 'Git Bash 없음 — 생존 신호를 쓸 수 없다' }
  $role = Get-Role
  if ($role -ne 'main' -and -not $Force) { Write-Host "SKIP    $HbName - 이 기계 역할 = $role (main 전용 · machines.conf)"; return }
  $me = [Security.Principal.WindowsIdentity]::GetCurrent()
  $ca = Get-RunnerArg $hb
  $start = (Get-Date).AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ss')
  $hbText = "@echo off`r`nrem Qvest main heartbeat - generated by qvest_tasks.ps1 -Mode Heartbeat $(Get-Date -Format s)`r`n" +
    "set `"QVEST_JOBS_DIR=$($Jobs -replace '\\', '/')`"`r`n`"$Bash`" `"$GateU`" heartbeat`r`n"
  $xmlText = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="$TaskNS">
  <RegistrationInfo>
    <Author>$([Security.SecurityElement]::Escape($me.Name))</Author>
    <Description>Qvest main heartbeat every 5 min + logon (qvest_machine.sh heartbeat). Two-machine setup 2026-11-01: the laptop defers to a live main.</Description>
    <URI>\$HbName</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$($me.User.Value)</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$start</StartBoundary>
      <Repetition>
        <Interval>PT5M</Interval>
      </Repetition>
    </TimeTrigger>
    <LogonTrigger>
      <UserId>$([Security.SecurityElement]::Escape($me.Name))</UserId>
    </LogonTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>$($ca[0])</Command>
      <Arguments>$([Security.SecurityElement]::Escape($ca[1]))</Arguments>
    </Exec>
  </Actions>
</Task>
"@
  if (-not $PyW) { Write-Warning 'pythonw.exe 없음 — 생존 신호가 5분마다 cmd 창을 띄운다(-Visible 이 아니면 Python 3 설치 권장).' }
  if ($PSCmdlet.ShouldProcess($HbName, '생존 신호 작업 등록(5분)')) {
    Install-Launcher
    [void](New-Item -ItemType Directory -Force -Path $Base)
    [IO.File]::WriteAllText($hb, $hbText, [Text.Encoding]::Default)
    [void](Register-ScheduledTask -Xml $xmlText -TaskName $HbName -TaskPath '\' -Force)
    Start-ScheduledTask -TaskName $HbName -TaskPath '\'
  }
  Write-Host "HEARTBEAT $HbName registered (5 min + logon) -> $hb"
}

function Invoke-Status {
  if ($Bash -and (Test-Path -LiteralPath $GateW)) { & $Bash $GateU status }
  Write-Host '--- gated tasks'
  foreach ($t in @(Get-ScheduledTask | Where-Object { ((@($_.Actions) | ForEach-Object { "$($_.Arguments)" }) -join ' ') -match '\\Qvest\\' })) {
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
    $a = ((@($t.Actions) | ForEach-Object { "$($_.Arguments)" }) -join ' ')
    $r = [regex]::Match($a, '([A-Za-z]:\\\S+\.cmd)').Groups[1].Value
    $per = ''
    if ($r -and (Test-Path -LiteralPath $r)) { $m = Select-String -LiteralPath $r -Pattern 'period=(\S+)' | Select-Object -First 1; if ($null -ne $m) { $per = $m.Matches[0].Groups[1].Value } }
    Write-Host ('{0,-36} {1,-9} period={2,-5} last={3:yyyy-MM-dd HH:mm} rc={4}' -f $t.TaskName, $t.State, $per, $info.LastRunTime, $info.LastTaskResult)
  }
}

switch ($Mode) {
  'Export'    { Invoke-Export }
  'Apply'     { Invoke-Apply }
  'Restore'   { Invoke-Restore }
  'Heartbeat' { Invoke-Heartbeat }
  'Status'    { Invoke-Status }
}
exit $script:Rc
