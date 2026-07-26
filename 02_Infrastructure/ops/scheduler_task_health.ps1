# scheduler_task_health.ps1 — Qvest_* 예약작업의 *바깥 경계* 실측 (2026-07-26 신설)
#
# 왜: 오늘까지 계측은 전부 스크립트 *안*에 있었다. 스크립트가 아예 실행되지 않거나
#     OS 가 중도에 죽여도(ExecutionTimeLimit 초과 / 종료 / 강제종료) 저장소 어디에도
#     흔적이 남지 않는다 — 07-26 실측: 작업 rc 를 읽는 코드 0건, 그 상태로
#     InsiderBackfill(02:00) 이 rc=0xC000013A 로 조용히 실패 중이었다.
#     stranded_repairs 도 12:00/20:00 런이 로그 한 줄 없이 사라졌다.
#
# 출력: 06_Registry/scheduler_task_health.json  (판정·경보는 .sh 가 담당)
# 읽기 전용 — 작업을 고치거나 재발화하지 않는다.

param([string]$OutFile = "")

$ErrorActionPreference = 'SilentlyContinue'

# rc 해독 — 숫자만 남기면 사람이 못 읽는다
function Decode-Rc([long]$rc) {
  switch ($rc) {
    0          { 'ok' }
    267009     { 'still_running' }
    267011     { 'never_run' }
    267014     { 'terminated_by_user_or_limit' }
    2147942401 { 'file_not_found' }
    2147942402 { 'path_not_found' }
    2147942405 { 'access_denied' }
    3221225786 { 'hard_terminated (Ctrl-C/종료/ExecTimeLimit)' }
    3221225794 { 'dll_init_failed' }
    default    { if ($rc -gt 2147483647 -or $rc -lt 0) { 'nt_status_0x{0:X8}' -f $rc } else { "exit_$rc" } }
  }
}

# 트리거 주기 → 허용 정체 일수. 주기를 모르면 staleness 판정을 하지 않는다(오탐 방지).
function Max-StaleDays($task) {
  $d = $null
  foreach ($tr in $task.Triggers) {
    $c = $tr.CimClass.CimClassName
    switch -Wildcard ($c) {
      '*DailyTrigger*'   { $d = [math]::Max([int]($d), 2) }
      '*WeeklyTrigger*'  { $d = [math]::Max([int]($d), 9) }
      '*MonthlyTrigger*' { $d = [math]::Max([int]($d), 35) }
      '*TimeTrigger*'    {
        # 반복 없는 1회성 = 주기 아님. 반복 간격이 있으면 일 단위로 환산.
        if ($tr.Repetition.Interval) { $d = [math]::Max([int]($d), 2) }
      }
    }
  }
  if ($d) { $d } else { $null }
}

$rows = @()
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'Qvest*' })) {
  $i = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
  if (-not $i) { continue }

  $rc      = [long]$i.LastTaskResult
  $last    = $i.LastRunTime
  $ageDays = if ($last -and $last.Year -gt 1980) { [math]::Round(((Get-Date) - $last).TotalDays, 2) } else { $null }
  $maxSt   = Max-StaleDays $t

  $trig = @()
  foreach ($tr in $t.Triggers) { if ($tr.StartBoundary) { $trig += ([datetime]$tr.StartBoundary).ToString('HH:mm') } }

  $rows += [pscustomobject]@{
    task            = $t.TaskName
    state           = "$($t.State)"
    rc              = $rc
    rc_label        = (Decode-Rc $rc)
    last_run        = if ($last -and $last.Year -gt 1980) { $last.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }
    age_days        = $ageDays
    max_stale_days  = $maxSt
    next_run        = if ($i.NextRunTime -and $i.NextRunTime.Year -gt 1980) { $i.NextRunTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }
    exec_time_limit = "$($t.Settings.ExecutionTimeLimit)"
    enabled         = [bool]$t.Settings.Enabled
    triggers        = ($trig -join ',')
  }
}

$out = [pscustomobject]@{
  schema_version = 1
  measured_at    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
  n_tasks        = $rows.Count
  tasks          = @($rows | Sort-Object task)
}

$json = $out | ConvertTo-Json -Depth 5
if ($OutFile) {
  $dir = Split-Path $OutFile -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  # UTF-8 명시 — Set-Content 기본은 ANSI 라 bash/python 이 깨진 값을 읽는다
  $json | Out-File -FilePath $OutFile -Encoding utf8
} else {
  Write-Output $json
}
