# scheduler_task_health.ps1 - collector for Qvest_* scheduled-task outer boundary (2026-07-26)
#
# ASCII-ONLY BY CONTRACT. Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, so any
# non-ASCII byte here corrupts the parse (measured 07-26: Korean comments produced
# "Unexpected token '}'" at a line that had no brace). Korean commentary lives in the
# sibling scheduler_task_health.sh instead. Same trap the .bat files were made ASCII for.
#
# Why this exists: until 07-26 nothing in the repo read scheduled-task exit codes, so a task
# that never ran, or that the OS killed, left no trace anywhere. All the instrumentation added
# that day lives *inside* the scripts and cannot observe a run that did not happen.
#
# Emits 06_Registry/scheduler_task_health.json. Read-only: never repairs or re-triggers a task.

param([string]$OutFile = "")

$ErrorActionPreference = 'SilentlyContinue'

function Decode-Rc([long]$rc) {
  switch ($rc) {
    0          { 'ok' }
    267009     { 'still_running' }
    267011     { 'never_run' }
    267014     { 'terminated_by_user_or_limit' }
    2147942401 { 'file_not_found' }
    2147942402 { 'path_not_found' }
    2147942405 { 'access_denied' }
    3221225786 { 'hard_terminated_ctrlc_or_exectimelimit' }
    3221225794 { 'dll_init_failed' }
    default    { if ($rc -gt 2147483647 -or $rc -lt 0) { 'nt_status_0x{0:X8}' -f $rc } else { "exit_$rc" } }
  }
}

# Trigger cadence -> tolerated staleness in days. Unknown cadence => no staleness verdict
# (a false "stalled" alert trains the reader to ignore the channel).
function Get-MaxStaleDays($task) {
  $d = 0
  foreach ($tr in $task.Triggers) {
    $c = "$($tr.CimClass.CimClassName)"
    if ($c -like '*DailyTrigger*')   { if ($d -lt 2)  { $d = 2 } }
    if ($c -like '*WeeklyTrigger*')  { if ($d -lt 9)  { $d = 9 } }
    if ($c -like '*MonthlyTrigger*') { if ($d -lt 35) { $d = 35 } }
    if ($c -like '*TimeTrigger*' -and $tr.Repetition.Interval) { if ($d -lt 2) { $d = 2 } }
  }
  if ($d -gt 0) { $d } else { $null }
}

$rows = @()
foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'Qvest*' })) {
  $i = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue
  if (-not $i) { continue }

  $rc   = [long]$i.LastTaskResult
  $last = $i.LastRunTime
  $hasLast = ($last -ne $null -and $last.Year -gt 1980)
  $ageDays = $null
  if ($hasLast) { $ageDays = [math]::Round(((Get-Date) - $last).TotalDays, 2) }

  $trig = @()
  foreach ($tr in $t.Triggers) {
    if ($tr.StartBoundary) { $trig += ([datetime]$tr.StartBoundary).ToString('HH:mm') }
  }

  $rows += [pscustomobject]@{
    task            = "$($t.TaskName)"
    state           = "$($t.State)"
    rc              = $rc
    rc_label        = (Decode-Rc $rc)
    last_run        = $(if ($hasLast) { $last.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null })
    age_days        = $ageDays
    max_stale_days  = (Get-MaxStaleDays $t)
    next_run        = $(if ($i.NextRunTime -ne $null -and $i.NextRunTime.Year -gt 1980) { $i.NextRunTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null })
    exec_time_limit = "$($t.Settings.ExecutionTimeLimit)"
    enabled         = [bool]$t.Settings.Enabled
    triggers        = ($trig -join ',')
    # 2026-08-02: recorded so a co-termination verdict can RULE OUT hypotheses from the
    # record instead of requiring a live query. Interactive = session-scoped lifetime
    # (logoff/session teardown kills it -> 0xC000013A). stop_on_battery falsifies the
    # battery-policy hypothesis. start_when_available explains catch-up bursts on resume.
    logon_type           = "$($t.Principal.LogonType)"
    stop_on_battery      = [bool]$t.Settings.StopIfGoingOnBatteries
    start_when_available = [bool]$t.Settings.StartWhenAvailable
  }
}

# Most recent resume-from-sleep and last boot. A burst of tasks all starting within minutes
# AFTER a resume is the catch-up signature (StartWhenAvailable replaying missed triggers),
# not N independent failures. Recording it lets the verdict be evidence-based rather than
# inferred from how long ago the burst happened - elapsed time says nothing about cause.
$lastResume = $null
$ev = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Power-Troubleshooter'; Id=1} -MaxEvents 1 -ErrorAction SilentlyContinue
if ($ev) { $lastResume = $ev.TimeCreated.ToString('yyyy-MM-ddTHH:mm:ss') }
$lastBoot = $null
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($os -and $os.LastBootUpTime) { $lastBoot = ([datetime]$os.LastBootUpTime).ToString('yyyy-MM-ddTHH:mm:ss') }

# Whether the Task Scheduler operational log is on. When it is off, the terminating agent
# of a hard-kill is NOT recoverable after the fact - the verdict must say "unidentified"
# rather than guess. (Measured 08-02: disabled, which is why the 07-26 investigation could
# not name the killer.) Enabling it is a system setting change - operator decision, not ours.
$opLogEnabled = $null
$ol = Get-WinEvent -ListLog 'Microsoft-Windows-TaskScheduler/Operational' -ErrorAction SilentlyContinue
if ($ol) { $opLogEnabled = [bool]$ol.IsEnabled }

$out = [pscustomobject]@{
  schema_version         = 2
  measured_at            = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
  n_tasks                = $rows.Count
  last_resume            = $lastResume
  last_boot              = $lastBoot
  tasksched_oplog_enabled = $opLogEnabled
  tasks                  = @($rows | Sort-Object task)
}

$json = $out | ConvertTo-Json -Depth 5
if ($OutFile) {
  $dir = Split-Path $OutFile -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  # Explicit utf8: Set-Content/Out-File default to ANSI here, which bash and python then misread.
  $json | Out-File -FilePath $OutFile -Encoding utf8
} else {
  Write-Output $json
}
