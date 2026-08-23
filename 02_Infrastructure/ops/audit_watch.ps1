# =============================================================================
# audit_watch.ps1 - venv tree deletion audit watcher (2026-08-16)
#
# WHY:
#   2026-08-16 16:02:11 .venv_qvest_ml was emptied. File System auditing was OFF,
#   so 4660/4663 were never written - the culprit is permanently unknowable.
#   Auditing + a folder SACL were then enabled and PROVEN to record (positive
#   control at 17:09:56 produced 4660+4663).
#   Remaining gap: the Security log needs admin to read, but the boot check runs
#   as a normal user. This script runs elevated on a schedule and distills the
#   answer into a plain JSON file the boot check can read without privilege.
#
# WHAT IT WATCHES (three things, not one):
#   1. Did anything delete inside the watched tree?      -> events
#   2. Is the audit policy still enabled?                -> audit_policy
#   3. Is the SACL still attached?                       -> sacl
#   (2) and (3) matter because an attacker or a cleanup tool can silently turn
#   the watch off; without them "no events" is indistinguishable from "blind".
#
# FAIL-CLOSED: anything we cannot determine becomes verdict=DEGRADED/ALERT,
#   never OK. Silence must never read as safety.
#
# OUTPUT: <repo>/.cache/audit_watch_status.json   (.cache is gitignored - this
#   file carries process image paths and account names, which must not be pushed)
#
# USAGE: powershell -ExecutionPolicy Bypass -File audit_watch.ps1 [-WindowHours 26]
# =============================================================================
[CmdletBinding()]
param(
    [string]$WatchPath = "",
    [int]$WindowHours = 26,
    [string]$OutFile = ""
)

$ErrorActionPreference = 'Continue'

# ---- resolve repo root from script location (no hardcoded path) -------------
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $repo 'CLAUDE.md'))) {
    if ($env:QM_ROOT -and (Test-Path (Join-Path $env:QM_ROOT 'CLAUDE.md'))) { $repo = $env:QM_ROOT }
}
if ($WatchPath -eq "") { $WatchPath = Join-Path $repo '.venv_qvest_ml' }
if ($OutFile   -eq "") { $OutFile   = Join-Path $repo '.cache\audit_watch_status.json' }

$notes = New-Object System.Collections.ArrayList
$verdict = 'OK'
function Set-Verdict([string]$v) {
    # ALERT > DEGRADED > OK  (never downgrade)
    $rank = @{ 'OK' = 0; 'DEGRADED' = 1; 'ALERT' = 2 }
    if ($rank[$v] -gt $rank[$script:verdict]) { $script:verdict = $v }
}

# ---- 0. elevation ----------------------------------------------------------
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    $isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { $null = $notes.Add("elevation check threw: $($_.Exception.Message)") }
if (-not $isAdmin) {
    $null = $notes.Add("NOT ELEVATED - Security log and SACL are unreadable. Register the scheduled task with 'Run with highest privileges'.")
    Set-Verdict 'DEGRADED'
}

# ---- 1. audit policy state (File System subcategory) -----------------------
# Locale-independent-ish: treat "No Auditing"/"감사 없음" as disabled; a parse
# failure is UNKNOWN, never assumed enabled.
$auditEnabled = $null
$auditSetting = ''
if ($isAdmin) {
    try {
        $raw = & auditpol /get /subcategory:"{0CCE921D-69AE-11D9-BED3-505054503030}"
        $line = ($raw | Where-Object { $_ -match 'File System|파일 시스템' } | Select-Object -First 1)
        if ($line) {
            $auditSetting = ($line -replace '.*(파일 시스템|File System)\s+', '').Trim()
            if ($auditSetting -match '감사 없음|No Auditing') { $auditEnabled = $false }
            elseif ($auditSetting.Length -gt 0)              { $auditEnabled = $true }
        }
    } catch { $null = $notes.Add("auditpol threw: $($_.Exception.Message)") }

    if ($auditEnabled -eq $false) {
        $null = $notes.Add("AUDIT POLICY OFF - deletions are no longer recorded. Re-enable: auditpol /set /subcategory:`"{0CCE921D-69AE-11D9-BED3-505054503030}`" /success:enable")
        Set-Verdict 'ALERT'
    } elseif ($null -eq $auditEnabled) {
        $null = $notes.Add("audit policy state UNPARSEABLE (auditpol output changed?) - treating as not-verified")
        Set-Verdict 'DEGRADED'
    }
}

# ---- 2. SACL still attached to the watched tree ----------------------------
$saclCount = $null
if ($isAdmin) {
    if (Test-Path $WatchPath) {
        try {
            $acl = Get-Acl -Path $WatchPath -Audit
            $saclCount = @($acl.Audit).Count
            if ($saclCount -eq 0) {
                $null = $notes.Add("SACL MISSING on $WatchPath - the folder is no longer watched even though the policy is on.")
                Set-Verdict 'ALERT'
            }
        } catch {
            $null = $notes.Add("Get-Acl -Audit threw: $($_.Exception.Message)")
            Set-Verdict 'DEGRADED'
        }
    } else {
        $null = $notes.Add("WATCHED PATH ABSENT: $WatchPath - the whole directory is gone, not just its contents.")
        Set-Verdict 'ALERT'
    }
}

# ---- 3. deletion events inside the watched tree ----------------------------
$items = New-Object System.Collections.ArrayList
if ($isAdmin) {
    try {
        $start = (Get-Date).AddHours(-1 * $WindowHours)
        $evts = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4660, 4663; StartTime = $start } -ErrorAction SilentlyContinue
        foreach ($e in $evts) {
            $obj = ''; $proc = ''; $acct = ''; $acc = ''
            try {
                $x = [xml]$e.ToXml()
                foreach ($d in $x.Event.EventData.Data) {
                    switch ($d.Name) {
                        'ObjectName'      { $obj  = [string]$d.'#text' }
                        'ProcessName'     { $proc = [string]$d.'#text' }
                        'SubjectUserName' { $acct = [string]$d.'#text' }
                        'AccessList'      { $acc  = [string]$d.'#text' }
                    }
                }
            } catch { }
            # 4660 carries no ObjectName; keep it when its process/time pairs with the window
            if ($obj -and ($obj -notlike "$WatchPath*")) { continue }
            $null = $items.Add([pscustomobject]@{
                time    = $e.TimeCreated.ToString('s')
                id      = $e.Id
                object  = $obj
                process = $proc
                account = $acct
                access  = ($acc -replace '\s+', ' ').Trim()
            })
        }
    } catch { $null = $notes.Add("Get-WinEvent threw: $($_.Exception.Message)") }

    if ($items.Count -gt 0) {
        $procs = ($items | Where-Object { $_.process } | Select-Object -ExpandProperty process -Unique) -join ', '
        $null = $notes.Add("DELETION ACTIVITY in watched tree: $($items.Count) event(s). Processes: $procs")
        Set-Verdict 'ALERT'
    }
}

# ---- 3b. is the SCHEDULE itself still armed? -------------------------------
# The freshness axis in C11 can only notice a dead task after the digest goes
# stale (30h). That window is long enough to read as safety. Worse, any manual
# run refreshes the digest and hides a mis-armed schedule for another 30h -
# which is exactly what happened on 2026-08-23. So the watch reports on its own
# trigger conditions: a laptop task registered without -Settings inherits
# DisallowStartIfOnBatteries=True and is REFUSED (0x800710E0) on every battery
# run while still reading State=Ready. Flat booleans, grep-readable (see part 4).
$schedBatterySafe = 'UNKNOWN'
$schedStartWhenAvailable = 'UNKNOWN'
$schedLastResult = 'UNKNOWN'
try {
    $selfTask = Get-ScheduledTask -TaskName 'Qvest_AuditWatch' -ErrorAction Stop
    $schedBatterySafe = (-not $selfTask.Settings.DisallowStartIfOnBatteries -and
                         -not $selfTask.Settings.StopIfGoingOnBatteries).ToString().ToLower()
    $schedStartWhenAvailable = ([bool]$selfTask.Settings.StartWhenAvailable).ToString().ToLower()
    $schedLastResult = '0x{0:X}' -f (Get-ScheduledTaskInfo -TaskName 'Qvest_AuditWatch').LastTaskResult
    if ($schedBatterySafe -eq 'false') {
        $null = $notes.Add("SCHEDULE NOT ARMED: DisallowStartIfOnBatteries/StopIfGoingOnBatteries is set, so battery-time runs are refused (0x800710E0) while the task still reads Ready. Repair in an ELEVATED shell: `$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew ; Set-ScheduledTask -TaskName 'Qvest_AuditWatch' -Settings `$s")
    }
} catch {
    $null = $notes.Add("SCHEDULE SELF-CHECK FAILED: could not read own task registration - $($_.Exception.Message)")
}


# ---- 4. write digest -------------------------------------------------------
# Top level is deliberately FLAT: the consumer (boot_currency_check.sh C11) is a
# grep-based shell check with no JSON parser. Nested fields would force it to
# parse structure, and a fragile parser that silently misreads is worse than no
# check at all. Detail stays under event_items for humans.
$payload = [pscustomobject]@{
    generated_at   = (Get-Date).ToString('s')
    generated_epoch = [int][double]::Parse((Get-Date -UFormat %s))
    watch_path     = $WatchPath
    window_hours   = $WindowHours
    schedule_battery_safe = $schedBatterySafe
    schedule_start_when_available = $schedStartWhenAvailable
    schedule_last_result = $schedLastResult
    elevated       = $isAdmin
    audit_enabled  = $auditEnabled
    audit_setting  = $auditSetting
    sacl_present   = ($null -ne $saclCount -and $saclCount -gt 0)
    sacl_rules     = $saclCount
    event_count    = $items.Count
    verdict        = $verdict
    notes          = @($notes)
    event_items    = @($items | Select-Object -First 50)
}

$dir = Split-Path -Parent $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$json = $payload | ConvertTo-Json -Depth 6
# UTF-8 without BOM - bash/python readers choke on a BOM
[System.IO.File]::WriteAllText($OutFile, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "[audit_watch] verdict=$verdict events=$($items.Count) elevated=$isAdmin -> $OutFile"
if ($verdict -eq 'ALERT') { exit 2 } elseif ($verdict -eq 'DEGRADED') { exit 1 } else { exit 0 }
