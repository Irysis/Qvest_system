# ==============================================================================
#  test_qw_peer_refresh_close_guard.ps1 - the close guard of 02_Infrastructure/ops/qw_peer_refresh.ps1
#  (ASCII-only for PowerShell 5.1). Runs the REAL finally block (extracted from the file) on a real Excel
#  instance; needs Excel, not Quantiwise. Never touches 03_Universe or .cache.
#  Why (11-08 22:01): after Save() an Office dialog for a OneDrive-synced book (NUIDialog 'cannot merge your
#    changes with the latest changes') blocked Workbook.Close for 30 min and stalled the refresh chain.
#  Cases:
#    T1 normal : real workbook, guard 120 s -> no 'fired' line, Excel exits, no guard process left
#    T2 hang   : $wb stub whose Close() sleeps 6 s (stands in for the dialog), guard 2 s -> 'close guard fired',
#                Excel killed, no guard process left
#    T3 mutation: start-time match made impossible -> same hang shape gives NO 'fired' line
#                 (T2's line is the guard's kill, not a coincidence of Excel quitting on its own)
#    T0 canary : extraction found the Add-Type block and a finally block that contains the guard
#  Output: last line JSON {"test":"qw_peer_refresh_close_guard","pass":n,"fail":n,"total":n}
# ==============================================================================
$ErrorActionPreference = "Stop"
$ROOT = if ($env:QM_ROOT) { $env:QM_ROOT } else { "C:\Users\99922\OneDrive\Quant_Module_Moltbot" }
$SUT = Join-Path $ROOT "02_Infrastructure\ops\qw_peer_refresh.ps1"
$PASS = 0; $FAIL = 0
function ok($m) { $script:PASS++; Write-Host "  OK   $m" }
function ng($m) { $script:FAIL++; Write-Host "  FAIL $m" }

function Run-Case([string]$fin, [int]$sec, [switch]$Hang) {
  $CloseGuardSec = $sec
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  $real = $xl.Workbooks.Add()
  $p0 = 0; [void][QpWin]::GetWindowThreadProcessId([IntPtr]$xl.Hwnd, [ref]$p0)
  if ($Hang) {
    $real.Close($false)
    $wb = New-Object psobject; $wb | Add-Member -MemberType ScriptMethod -Name Close -Value { param($s) Start-Sleep 6 }
  } else { $wb = $real }
  $out = (Invoke-Expression $fin) 6>&1 | Out-String
  Start-Sleep 4
  $alive = [bool](Get-Process -Id $p0 -EA SilentlyContinue)
  if ($alive) { Stop-Process -Id $p0 -Force -EA SilentlyContinue }
  $left = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match "Get-Process -Id $p0 " })
  $left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
  return @{ fired = ($out -match 'close guard fired'); alive = $alive; left = $left.Count; out = $out.Trim() }
}

try {
  $src = Get-Content -LiteralPath $SUT -Raw
  $at = [regex]::Match($src, '(?s)Add-Type -TypeDefinition @"\r?\n.*?\r?\n"@').Value
  $fin = [regex]::Match($src, '(?s)\} finally \{\r?\n(.*?)\r?\n\}\r?\nWrite-Host "\[peer-refresh\] END').Groups[1].Value
  if ($at -and $fin -match 'close guard' -and $fin -match 'StartTime\.Ticks -eq \$xlTicks') { ok "T0 canary: Add-Type + finally block with the guard extracted" }
  else { ng "T0 extraction failed (Add-Type $($at.Length) chars, finally $($fin.Length) chars)"; throw "canary failed - not publishing case results" }
  Invoke-Expression $at
  $r1 = Run-Case $fin 120
  if (-not $r1.fired -and -not $r1.alive -and $r1.left -eq 0) { ok "T1 normal close: no 'fired', Excel gone, guard stopped" } else { ng "T1 $($r1 | ConvertTo-Json -Compress)" }
  $r2 = Run-Case $fin 2 -Hang
  if ($r2.fired -and -not $r2.alive -and $r2.left -eq 0) { ok "T2 hung close: guard fired, Excel killed, guard gone" } else { ng "T2 $($r2 | ConvertTo-Json -Compress)" }
  $mut = $fin.Replace('.StartTime.Ticks -eq $xlTicks', '.StartTime.Ticks -eq 1')
  if ($mut -eq $fin) { ng "T3 mutation did not apply" }
  else {
    $r3 = Run-Case $mut 2 -Hang
    if (-not $r3.fired) { ok "T3 mutation (start time never matches): no 'fired' - T2's line is the guard's kill" } else { ng "T3 $($r3 | ConvertTo-Json -Compress)" }
  }
} catch {
  ng "harness error (line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"
}
Write-Host ""
Write-Host ("total: pass {0} fail {1}" -f $PASS, $FAIL)
Write-Host ('{"test":"qw_peer_refresh_close_guard","pass":' + $PASS + ',"fail":' + $FAIL + ',"total":' + ($PASS + $FAIL) + '}')
if ($FAIL -gt 0) { exit 1 } else { exit 0 }
