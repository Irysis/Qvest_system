<#
make_task_xml.ps1 - Qvest_StressDaily 작업 원본 XML 을 '이 기계' 경로로 써 낸다(qvest_tasks.ps1 -Mode Apply -From <Out> 의 입력).
  기계마다 사용자 폴더 · QM_ROOT 가 달라(노트북 C:\Users\99922 · 메인 C:\Users\User / G:) XML 을 저장소에 고정해 두지 않고 등록 직전에 만든다.
  사용: powershell -ExecutionPolicy Bypass -File make_task_xml.ps1 [-Out <폴더>] [-Time 04:00] [-Root <프로젝트>]
  기본 Out = %OneDrive%\Qvest_sync\stress_daily_task_20261106 (작업 트리 밖 · 두 기계가 같은 폴더로 Apply).
#>
param(
  [string]$Out,
  [string]$Time = '04:00',
  [string]$Root
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = $env:QM_ROOT }
if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..')) }
$Root = ($Root -replace '/', '\').TrimEnd('\')
if (-not $Out) {
  $od = $env:OneDrive
  if (-not $od) { $od = Join-Path $env:USERPROFILE 'OneDrive' }
  $Out = Join-Path $od 'Qvest_sync\stress_daily_task_20261106'
}
$bat = Join-Path $Root '04_Research\01_reports\kr_market_stress_index_20261106\ops\Qvest_StressDaily.bat'
if (-not (Test-Path -LiteralPath $bat)) { throw "진입점이 없습니다: $bat" }
if ($Time -notmatch '^\d{2}:\d{2}$') { throw "-Time 은 HH:mm 꼴이어야 합니다: $Time" }
$start = (Get-Date).ToString('yyyy-MM-dd') + 'T' + $Time + ':00'
$sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
$esc = [Security.SecurityElement]::Escape($bat)
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>KR capital-market stress daily report (PDF + xlsx). Runs after the nightly data refresh: waits for /tmp/qm_daily_refresh.lock release and for bench data >= previous KRX session (cap 480 min, then skips the day). Dohoon 2026-11-06: separate scheduled task. Entry = 04_Research/01_reports/kr_market_stress_index_20261106/ops.</Description>
    <URI>\Qvest_StressDaily</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <Enabled>true</Enabled>
    <ExecutionTimeLimit>PT9H</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <IdleSettings>
      <Duration>PT10M</Duration>
      <WaitTimeout>PT1H</WaitTimeout>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>$esc</Command>
    </Exec>
  </Actions>
</Task>
"@
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$path = Join-Path $Out 'Qvest_StressDaily.xml'
[IO.File]::WriteAllText($path, $xml, [Text.Encoding]::Unicode)
Write-Host "[stress-task] XML -> $path"
Write-Host "[stress-task] root=$Root  entry=$bat  trigger=daily $Time  user=$sid"
