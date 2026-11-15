# ==============================================================================
#  qw_follow_guard_client.ps1 - caller side of qw_follow_guard.ps1 (dot-source it; ASCII-only for PowerShell 5.1)
# ==============================================================================
#  One place for the protocol between an add-in refresh script and its guard process (2026-11-15, FUNDV2-TAXTS-FIX-20261115):
#    Initialize-FollowGuard <work dir>     events file <work>\follow_guard_events.jsonl (cleared) - $false if the guard is missing
#    Invoke-FollowGuardOnce                one pass before Excel starts (picker forms closed, update prompt declined) -> acts
#    Start-FollowGuard <pid> <ticks> <s>   the guard beside that Excel (stall limit s per Follow) - exits with the caller;
#                                          returns the process only after the guard's 'ready' event (<= 60 s), else $null
#    Set-FollowBeat '<label>' / ''         before / after each Follow (the guard measures the stall from it); throws when the
#                                          guard has exited (no unguarded Follow)
#    Get-FollowGuardActs <since>           guard actions since a unix second (lookup_closed, update_declined)
#    Get-FollowGuardKill                   the last excel_killed event (waits 2 s once - the event may land after the COM error)
#    Stop-FollowGuard                      stop file, 5 s, then kill
#  Users: ops/qw_fund_v2_tax_ts.ps1, ops/qw_peer_refresh.ps1. Test: 08_Tests/scenarios/test_scn_qw_follow_guard.sh.
# ==============================================================================
$script:FgScript = Join-Path $PSScriptRoot 'qw_follow_guard.ps1'
$script:FgEvents = ''; $script:FgBeat = ''; $script:FgStop = ''; $script:FgProc = $null
$script:FgQwPid = 0   # test hook only (the scenario test sets a fake 'terminal' pid so the real qwMain is never touched)
function FG-QwArgs { if ($script:FgQwPid -gt 0) { return @('-QwPid', $script:FgQwPid) }; return @() }
function FG-Now { return [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) }   # unix ms - same clock as the guard's events
function Initialize-FollowGuard([string]$WorkDir) {
  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  $script:FgEvents = Join-Path $WorkDir 'follow_guard_events.jsonl'
  $script:FgBeat = Join-Path $WorkDir 'follow_guard_beat.txt'
  $script:FgStop = Join-Path $WorkDir 'follow_guard.stop'
  Remove-Item -LiteralPath $script:FgEvents, $script:FgBeat, $script:FgStop -EA SilentlyContinue
  return (Test-Path -LiteralPath $script:FgScript)
}
function Get-FollowGuardEvents([int64]$Since = 0) {
  if (-not $script:FgEvents -or -not (Test-Path -LiteralPath $script:FgEvents)) { return @() }
  $lines = @()
  for ($i = 0; $i -lt 5; $i++) { try { $lines = @(Get-Content -LiteralPath $script:FgEvents -Encoding UTF8 -EA Stop); break } catch { Start-Sleep -Milliseconds 200 } }
  $out = @()
  foreach ($l in $lines) { if ("$l".Trim()) { try { $o = "$l" | ConvertFrom-Json; if ([int64]$o.t -ge $Since) { $out += $o } } catch {} } }
  return $out
}
function Get-FollowGuardActs([int64]$Since) { return @(Get-FollowGuardEvents $Since | Where-Object { $_.kind -eq 'lookup_closed' -or $_.kind -eq 'update_declined' }) }
function Format-FollowGuardActs($acts) { return ((@($acts) | ForEach-Object { "$($_.kind) '$($_.title)' ($($_.detail))" }) -join '; ') }
function Invoke-FollowGuardOnce {
  if (-not (Test-Path -LiteralPath $script:FgScript) -or -not $script:FgEvents) { return @() }
  $t = FG-Now
  $qa = @(FG-QwArgs)
  & powershell -NoProfile -ExecutionPolicy Bypass -File $script:FgScript -Events $script:FgEvents -Once @qa | Out-Null
  return @(Get-FollowGuardActs $t)
}
function Start-FollowGuard([int]$ExcelPid, [long]$ExcelTicks, [int]$StallSec) {
  if (-not (Test-Path -LiteralPath $script:FgScript) -or -not $script:FgEvents -or $ExcelPid -le 0) { return $null }
  Remove-Item -LiteralPath $script:FgBeat, $script:FgStop -EA SilentlyContinue
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($script:FgScript)`"", '-ExcelPid', $ExcelPid, '-ExcelTicks', $ExcelTicks,
         '-Events', "`"$($script:FgEvents)`"", '-Beat', "`"$($script:FgBeat)`"", '-StopFile', "`"$($script:FgStop)`"",
         '-StallSec', $StallSec, '-ParentPid', $PID) + @(FG-QwArgs)
  $t = FG-Now
  try { $p = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList $a; $null = $p.Handle } catch { return $null }   # .Handle keeps ExitCode readable (PS 5.1)
  # ready handshake: a guard that died at start (bad path, compile error) must not leave the caller refreshing unguarded
  for ($i = 0; $i -lt 300; $i++) {   # <= 60 s (a busy PC can take seconds to start PowerShell and compile Add-Type)
    if (@(Get-FollowGuardEvents $t | Where-Object { $_.kind -eq 'ready' }).Count -gt 0) { $script:FgProc = $p; return $p }
    if ($p.HasExited) { break }
    Start-Sleep -Milliseconds 200
  }
  try { if (-not $p.HasExited) { $p.Kill() } } catch {}
  return $null
}
function Set-FollowBeat([string]$Label) {
  if (-not $script:FgProc -or -not $script:FgBeat) { return }
  # a guard that exited mid-run (it only exits on its own when the Excel is gone) -> no unguarded Follow
  if ($Label -and $script:FgProc.HasExited) { throw "follow guard exited (code $($script:FgProc.ExitCode)) - not refreshing unguarded" }
  $v = ''; if ($Label) { $v = "$Label|$(FG-Now)" }
  try { [IO.File]::WriteAllText($script:FgBeat, $v) } catch {}
}
function Get-FollowGuardKill {
  $k = @(Get-FollowGuardEvents 0 | Where-Object { $_.kind -eq 'excel_killed' }) | Select-Object -Last 1
  if (-not $k -and $script:FgProc) { Start-Sleep 2; $k = @(Get-FollowGuardEvents 0 | Where-Object { $_.kind -eq 'excel_killed' }) | Select-Object -Last 1 }
  return $k
}
function Stop-FollowGuard {
  if (-not $script:FgProc) { return }
  try { New-Item -ItemType File -Force -Path $script:FgStop | Out-Null } catch {}
  try { if (-not $script:FgProc.WaitForExit(5000)) { $script:FgProc.Kill() } } catch {}
  $script:FgProc = $null
}
