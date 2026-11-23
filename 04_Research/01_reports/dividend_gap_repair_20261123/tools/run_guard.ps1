# run_guard.ps1 - run one command; track its process tree's working set; kill the tree if the system's
#   available memory drops below -MinAvailGB (the machine must not be starved). ASCII only.
#   prints: rc=<code|n/a> killed=<bool> secs=<n> tree_peak_gb=<x> min_avail_gb=<y>
param([string]$Exe, [string[]]$ArgList, [string]$Cwd, [string]$Out, [double]$MinAvailGB = 3.5)
$t0 = Get-Date
$p = Start-Process -FilePath $Exe -ArgumentList $ArgList -WorkingDirectory $Cwd -RedirectStandardOutput $Out -RedirectStandardError ($Out + '.err') -PassThru -NoNewWindow
$null = $p.Handle   # keep the handle so ExitCode is readable after exit
$peak = 0.0; $minAvail = 1e9; $killed = $false
while (-not $p.HasExited) {
  Start-Sleep -Milliseconds 2000
  try {
    $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, WorkingSetSize)
    $kids = New-Object 'System.Collections.Generic.HashSet[int]'
    [void]$kids.Add([int]$p.Id)
    $grew = $true
    while ($grew) {
      $grew = $false
      foreach ($q in $all) {
        if ($kids.Contains([int]$q.ParentProcessId) -and -not $kids.Contains([int]$q.ProcessId)) { [void]$kids.Add([int]$q.ProcessId); $grew = $true }
      }
    }
    $ws = 0.0
    foreach ($q in $all) { if ($kids.Contains([int]$q.ProcessId)) { $ws += [double]$q.WorkingSetSize } }
    $ws = $ws / 1GB
    if ($ws -gt $peak) { $peak = $ws }
    $avail = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
    if ($avail -lt $minAvail) { $minAvail = $avail }
    if ($avail -lt $MinAvailGB) { & taskkill.exe /PID $p.Id /T /F | Out-Null; $killed = $true; break }
  } catch {}
}
if (-not $killed) { $p.WaitForExit() }
$rc = 'n/a'
if (-not $killed) { $rc = $p.ExitCode }
"rc={0} killed={1} secs={2:N0} tree_peak_gb={3:N2} min_avail_gb={4:N1}" -f $rc, $killed, ((Get-Date) - $t0).TotalSeconds, $peak, $minAvail
