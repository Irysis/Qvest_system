# kill_own_r.ps1 - BOOK runner kills only its OWN R processes (2026-11-06, Dohoon: "remove every part of the
#   BOOK rebalance that interferes with other work"). ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
#
# Old kill_stray = "taskkill /F /IM Rscript.exe" -> killed EVERY R process on the machine (L1 replication lane,
#   P2R05 measurement, other sessions). Callers: run_nolayer4_monthly.sh kill_stray(), and ops/shims/taskkill
#   (PATH interceptor for the frozen 05_Production forward script, whose file is never modified).
#
# Kills (image Rscript.exe / R.exe / Rterm.exe only):
#   (1) live descendants of -RootPid (the runner bash's Windows pid)
#   (2) orphan R processes (parent no longer alive) whose command line contains a BOOK pipeline fragment
#       (timeout leftovers of this or an earlier run - no other job runs these scripts), plus their R descendants
# Never touches anything else. One line per kill + a summary. -DryRun lists without killing (used by the tests).
# Exit 0 (best effort) - exit 2 only for an invalid -RootPid.
param(
  [Parameter(Mandatory = $true)][int]$RootPid,
  [string[]]$OwnFragments = @(
    'WT_D20260425_010', 'WT-D20260430_001', 'forward_weights_', 'm4_append_only.R',
    'normalize_terminal_anchor.R', 'run_layer5_rerun_extended.R', 'extend_nolayer4_series.R',
    'monitor_nolayer4_paper.R', 'mark_nolayer4_daily.R'),
  [switch]$DryRun
)
if ($RootPid -le 0) { Write-Output "kill_own_r: invalid RootPid $RootPid - nothing killed"; exit 2 }
$rNames = @('rscript.exe', 'r.exe', 'rterm.exe')
$procs = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CommandLine)
$alive = @{}; $kids = @{}
foreach ($p in $procs) {
  $id = [int]$p.ProcessId; $pp = [int]$p.ParentProcessId
  $alive[$id] = $true
  if (-not $kids.ContainsKey($pp)) { $kids[$pp] = New-Object System.Collections.Generic.List[int] }
  if ($pp -ne $id) { $kids[$pp].Add($id) }
}
function Get-Subtree([int]$top) {
  $seen = @{}; $q = New-Object System.Collections.Generic.Queue[int]; $q.Enqueue($top)
  while ($q.Count -gt 0) {
    $cur = $q.Dequeue()
    if ($kids.ContainsKey($cur)) { foreach ($c in $kids[$cur]) { if (-not $seen.ContainsKey($c) -and $c -ne $top) { $seen[$c] = $true; $q.Enqueue($c) } } }
  }
  return $seen
}
$isR = @{}
foreach ($p in $procs) { if ($rNames -contains ([string]$p.Name).ToLower()) { $isR[[int]$p.ProcessId] = $p } }
$why = @{}
$desc = Get-Subtree $RootPid
foreach ($id in $desc.Keys) { if ($isR.ContainsKey($id)) { $why[$id] = 'descendant' } }
foreach ($id in @($isR.Keys)) {
  if ($why.ContainsKey($id)) { continue }
  $p = $isR[$id]
  if ($alive.ContainsKey([int]$p.ParentProcessId)) { continue }
  $cl = [string]$p.CommandLine
  $hit = $null
  foreach ($f in $OwnFragments) { if ($cl -and $cl.Contains($f)) { $hit = $f; break } }
  if (-not $hit) { continue }
  $why[$id] = "orphan:$hit"
  $sub = Get-Subtree $id
  foreach ($c in $sub.Keys) { if ($isR.ContainsKey($c) -and -not $why.ContainsKey($c)) { $why[$c] = "orphan-child:$hit" } }
}
$n = 0
foreach ($id in ($why.Keys | Sort-Object)) {
  $nm = $isR[$id].Name
  if ($DryRun) { Write-Output ("kill_own_r: would kill {0} {1} ({2})" -f $id, $nm, $why[$id]); $n++; continue }
  try { Stop-Process -Id $id -Force -ErrorAction Stop; Write-Output ("kill_own_r: killed {0} {1} ({2})" -f $id, $nm, $why[$id]); $n++ }
  catch { Write-Output ("kill_own_r: could not kill {0} {1} ({2}): {3}" -f $id, $nm, $why[$id], $_.Exception.Message) }
}
Write-Output ("kill_own_r: root={0} {1}={2} other_R_untouched={3}" -f $RootPid, $(if ($DryRun) { 'would_kill' } else { 'killed' }), $n, ($isR.Count - $why.Count))
exit 0
