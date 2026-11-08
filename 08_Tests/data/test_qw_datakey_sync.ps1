# ==============================================================================
#  test_qw_datakey_sync.ps1 - synthetic-book tests for 02_Infrastructure/ops/qw_datakey_sync.ps1
#  (ASCII-only for PowerShell 5.1). Builds tiny workbooks with Excel COM in a temp folder,
#  never touches 03_Universe or .cache.
#  Cases:
#    T1 ts layout   : 3 codes in book, master 5 -> appends 2 at the end, row-8 axis aligned, saved,
#                     backup = untouched original, pending.from = min list_dd of appended codes
#    T2 idempotent  : second run -> nochange, file unchanged (sha256)
#    T3 mutation    : query sheet row-8 formula shifted by one row (TRANSPOSE(DATA_Key!A3:...))
#                     -> verify fails, file NOT saved (sha256 unchanged), exit 1
#    T4 peer layout : K/L list from row 4, item sheet A14.. = IF(DATA_Key!$K4="","n/a",...)
#                     -> appends, 'n/a' after the list, saved
#    T5 canary      : the script under test exists and -WhatIf on an empty master exits 3
#                     (a dead script must not look like a pass)
#  Output: last line JSON {"test":"qw_datakey_sync","pass":n,"fail":n,"total":n}
# ==============================================================================
$ErrorActionPreference = "Stop"
$ROOT = if ($env:QM_ROOT) { $env:QM_ROOT } else { "C:\Users\99922\OneDrive\Quant_Module_Moltbot" }
$SUT = Join-Path $ROOT "02_Infrastructure\ops\qw_datakey_sync.ps1"
$tmp = Join-Path $env:TEMP ("qvest_dksync_test_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$PASS = 0; $FAIL = 0
function ok($m) { $script:PASS++; Write-Host "  OK   $m" }
function ng($m) { $script:FAIL++; Write-Host "  FAIL $m" }
function Sha($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

function New-TsBook($path, [string[]]$codes, [switch]$Shift) {
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  try {
    $wb = $xl.Workbooks.Add()
    while ($wb.Worksheets.Count -lt 3) { $null = $wb.Worksheets.Add() }
    $q1 = $wb.Worksheets.Item(1); $q1.Name = "Open"; $q2 = $wb.Worksheets.Item(2); $q2.Name = "Close"; $dk = $wb.Worksheets.Item(3); $dk.Name = "DATA_Key"
    $dk.Range("A1").Value2 = "list"
    $dk.Range("A2:A40").Formula = '=IFERROR(IF(D2<>"",D2,NA()),"")'
    for ($i = 0; $i -lt $codes.Count; $i++) { $dk.Range("D$($i + 2)").Value2 = $codes[$i]; $dk.Range("E$($i + 2)").Value2 = "n$i" }
    foreach ($q in @($q1, $q2)) {
      $q.Range("A3").Value2 = "Time Series (Company)"; $q.Range("A5").Value2 = "Period(From)"; $q.Range("A6").Value2 = "Period(To)"
      $src = if ($Shift -and $q.Name -eq "Close") { 'DATA_Key!A3:A41' } else { 'DATA_Key!A2:A40' }
      $q.Range("B8:AN8").FormulaArray = "=TRANSPOSE($src)"
      # [double]: assigning a PowerShell Int32 to Range.Value2 raised 'Unable to cast Int32 to String' (11-08 run)
      for ($i = 0; $i -lt $codes.Count; $i++) { $q.Range("$([char](66 + $i))15").Value2 = [double](100 + $i) }
    }
    $wb.SaveAs($path, 51); $wb.Close($false)
  } finally { $xl.Quit(); [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null }
}
function New-PeerBook($path, [string[]]$codes) {
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  try {
    $wb = $xl.Workbooks.Add()
    while ($wb.Worksheets.Count -lt 2) { $null = $wb.Worksheets.Add() }
    $it = $wb.Worksheets.Item(1); $it.Name = "Revenue"; $dk = $wb.Worksheets.Item(2); $dk.Name = "DATA_Key"
    for ($i = 0; $i -lt $codes.Count; $i++) { $dk.Range("K$($i + 4)").Value2 = $codes[$i]; $dk.Range("L$($i + 4)").Value2 = "n$i" }
    $it.Range("A3").Value2 = "Peer Analysis (To Select)"
    $it.Range("A14:A60").Formula = '=IF(DATA_Key!$K4="","n/a",DATA_Key!$K4)'
    for ($i = 0; $i -lt $codes.Count; $i++) { $it.Range("D$($i + 14)").Value2 = [double](10 + $i) }
    $wb.SaveAs($path, 51); $wb.Close($false)
  } finally { $xl.Quit(); [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null }
}
function New-Master($path, $entries) {
  $o = [ordered]@{ schema = 'qw_datakey_master/v1'; last_krx_date = '20261106'; codes = @($entries) }
  ($o | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding UTF8
}
function Run-Sut($only, $bookDir, $univDir, $master, [switch]$WhatIf) {
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SUT, '-Only', $only, '-NoBusyCheck', '-BookDir', $bookDir, '-UnivDir', $univDir,
         '-BackupRoot', $tmp, '-Master', $master, '-StatePath', (Join-Path $tmp 'state.json'), '-PendingPath', (Join-Path $tmp 'pending.json'))
  if ($WhatIf) { $a += '-WhatIf' }
  $out = & powershell @a 2>&1 | Out-String
  return @{ rc = $LASTEXITCODE; out = $out }
}
function Read-Row8($path, $sheet, [int]$n) {
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  try { $wb = $xl.Workbooks.Open($path, 0, $true); $v = $wb.Worksheets.Item($sheet).Range("B8:$([char](65 + $n))8").Value2; $r = @(); for ($i = 1; $i -le $n; $i++) { $r += "$($v[1, $i])" }; $wb.Close($false); return ,$r }
  finally { $xl.Quit(); [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null }
}

try {
  # T5 canary first: the SUT must exist and refuse to run without a master
  if (-not (Test-Path -LiteralPath $SUT)) { throw "SUT missing: $SUT" }
  $r5 = Run-Sut 'OHLCVS' $tmp $tmp (Join-Path $tmp 'no_master.json') -WhatIf
  if ($r5.rc -eq 3 -and $r5.out -match 'master missing') { ok "T5 canary: missing master -> exit 3 (script alive)" } else { ng "T5 canary rc=$($r5.rc) $($r5.out)"; throw "canary failed - not publishing case results" }

  $bd = Join-Path $tmp 'books'; New-Item -ItemType Directory -Force -Path $bd | Out-Null
  $master = Join-Path $tmp 'master.json'
  New-Master $master @(
    @{ code = 'A000010'; name = 'a' }, @{ code = 'A000020'; name = 'b' }, @{ code = 'A000030'; name = 'c' },
    @{ code = 'A0001A0'; name = 'd'; list_dd = '20260305' }, @{ code = 'A495910'; name = 'e'; list_dd = '20261104' })
  # T1
  $p1 = Join-Path $bd 'OHLCVS_update.xlsx'; New-TsBook $p1 @('A000010', 'A000020', 'A000030')
  $h0 = Sha $p1
  $r1 = Run-Sut 'OHLCVS' $bd $tmp $master
  $row = Read-Row8 $p1 'Close' 6
  $pend = Get-Content (Join-Path $tmp 'pending.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $bk = Join-Path $tmp ("_backup_datakey_" + (Get-Date -Format yyyyMMdd) + "\OHLCVS_update.xlsx")
  if ($r1.rc -eq 0 -and ($row -join ',') -eq 'A000010,A000020,A000030,A0001A0,A495910,' -and "$($pend.OHLCVS.from)" -eq '20260305' -and (Test-Path $bk) -and (Sha $bk) -eq $h0 -and (Sha $p1) -ne $h0) {
    ok "T1 ts: appended 2 at the end, row 8 aligned, backup = original, pending.from=20260305"
  } else { ng "T1 rc=$($r1.rc) row8=$($row -join ',') from=$($pend.OHLCVS.from) out=$($r1.out)" }
  # T2
  $h1 = Sha $p1; $r2 = Run-Sut 'OHLCVS' $bd $tmp $master
  if ($r2.rc -eq 0 -and $r2.out -match 'missing vs master 0' -and (Sha $p1) -eq $h1) { ok "T2 idempotent: nochange, file untouched" } else { ng "T2 rc=$($r2.rc) $($r2.out)" }
  # T3 mutation: row-8 array of one sheet shifted -> must refuse to save
  $p3 = Join-Path $bd 'Consensus_update.xlsx'; New-TsBook $p3 @('A000010', 'A000020', 'A000030') -Shift
  $h3 = Sha $p3; $r3 = Run-Sut 'Consensus' $bd $tmp $master
  if ($r3.rc -eq 1 -and $r3.out -match 'VERIFY FAILED' -and (Sha $p3) -eq $h3) { ok "T3 mutation (shifted row-8 array): verify failed, not saved, exit 1" } else { ng "T3 rc=$($r3.rc) saved=$((Sha $p3) -ne $h3) $($r3.out)" }
  # T4 peer layout
  $p4 = Join-Path $tmp 'Fundamental.xlsx'; New-PeerBook $p4 @('A000010', 'A000020', 'A000030')
  $r4 = Run-Sut 'Fundamental' $bd $tmp $master
  $xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
  try { $wb = $xl.Workbooks.Open($p4, 0, $true); $v = $wb.Worksheets.Item('Revenue').Range("A14:A19").Value2; $a4 = @(); for ($i = 1; $i -le 6; $i++) { $a4 += "$($v[$i, 1])" }; $wb.Close($false) } finally { $xl.Quit(); [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null }
  if ($r4.rc -eq 0 -and ($a4 -join ',') -eq 'A000010,A000020,A000030,A0001A0,A495910,n/a') { ok "T4 peer: K/L appended, item-sheet column A aligned, 'n/a' after list" } else { ng "T4 rc=$($r4.rc) colA=$($a4 -join ',') $($r4.out)" }
} catch {
  ng "harness error (line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())): $($_.Exception.Message)"
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host ("total: pass {0} fail {1}" -f $PASS, $FAIL)
Write-Host ('{"test":"qw_datakey_sync","pass":' + $PASS + ',"fail":' + $FAIL + ',"total":' + ($PASS + $FAIL) + '}')
if ($FAIL -gt 0) { exit 1 } else { exit 0 }
