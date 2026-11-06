<#
install_task.ps1 - Qvest_StressDaily 예약 작업을 이 기계에 설치(노트북 · 메인 PC 공통 · 한 줄).
  1) make_task_xml.ps1 로 이 기계 경로의 원본 XML 을 만든다(%OneDrive%\Qvest_sync\stress_daily_task_<컴퓨터 이름>)
  2) qvest_tasks.ps1 -Mode Apply -Name Qvest_StressDaily 로 '메인 우선 게이트' 실행기에 감싸 등록(다른 Qvest 예약 작업과 같은 방식)
  3) 등록 상태 · 다음 실행 시각을 보여 준다
  사용: powershell -ExecutionPolicy Bypass -File <이 파일> [-Time 04:00] [-WhatIf] [-RunNow]
  -RunNow = 등록 직후 한 번 돌려 본다(데이터 준비를 기다린 뒤 체인 · 약 2분).
  되돌리기: Unregister-ScheduledTask Qvest_StressDaily -Confirm:$false
#>
param([string]$Time = '04:00', [switch]$WhatIf, [switch]$RunNow)
$ErrorActionPreference = 'Stop'
$ops = $PSScriptRoot
$root = [IO.Path]::GetFullPath((Join-Path $ops '..\..\..\..'))
if ($env:QM_ROOT -and (Test-Path -LiteralPath $env:QM_ROOT)) { $root = $env:QM_ROOT }
$od = $env:OneDrive; if (-not $od) { $od = Join-Path $env:USERPROFILE 'OneDrive' }
$out = Join-Path $od ("Qvest_sync\stress_daily_task_" + $env:COMPUTERNAME)
Write-Host "[install] host=$env:COMPUTERNAME root=$root out=$out time=$Time"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ops 'make_task_xml.ps1') -Out $out -Time $Time -Root $root
if ($LASTEXITCODE -ne 0) { throw "make_task_xml 실패 rc=$LASTEXITCODE" }
$qt = Join-Path $root '02_Infrastructure\ops\machine\qvest_tasks.ps1'
$args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $qt, '-Mode', 'Apply', '-From', $out, '-Name', 'Qvest_StressDaily', '-Root', $root)
if ($WhatIf) { $args2 += '-WhatIf' }
& powershell @args2
if ($LASTEXITCODE -ne 0) { throw "qvest_tasks Apply 실패 rc=$LASTEXITCODE" }
if ($WhatIf) { Write-Host '[install] -WhatIf - 등록하지 않음'; exit 0 }
$t = Get-ScheduledTask -TaskName 'Qvest_StressDaily' -ErrorAction Stop
$i = $t | Get-ScheduledTaskInfo
Write-Host ("[install] 등록됨 state={0} next={1} action={2} {3}" -f $t.State, $i.NextRunTime, $t.Actions[0].Execute, $t.Actions[0].Arguments)
$runner = Join-Path $env:LOCALAPPDATA 'Qvest\jobs\Qvest_StressDaily.cmd'
if (-not (Test-Path -LiteralPath $runner)) { Write-Warning "실행기 파일이 보이지 않음: $runner (도구 세션의 가상화된 쓰기일 수 있다 - 사람이 연 PowerShell 에서 다시 실행)" }
if ($RunNow) { Start-ScheduledTask -TaskName 'Qvest_StressDaily'; Write-Host '[install] 지금 한 번 실행 시작 - 로그: %LOCALAPPDATA%\Qvest\logs\Qvest_StressDaily.log' }
