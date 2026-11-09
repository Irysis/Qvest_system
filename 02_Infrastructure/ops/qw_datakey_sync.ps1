# ==============================================================================
#  qw_datakey_sync.ps1 - append missing tickers to the END of each Quantiwise
#  book's DATA_Key ticker list, verify every query sheet still points each stored
#  column/row at the same ticker, then save. (ASCII-only for PowerShell 5.1)
# ==============================================================================
#  Why (2026-11-08, 04_Research/01_reports/quantiwise_data_expansion_20261106/BUILD_20261108.md s1):
#    DATA_Key lists were maintained by hand. Measured 11-06: OHLCVS 3,717 vs the other
#    three books 3,668 (53 missing -> hygiene flags NA in RAWDATA, PLAN F7), and 46 listed
#    stocks (IPOs since 2026-03-05) missing from every book.
#    Canonical list = 06_Registry/qw_datakey_master.json (writer: data/qw_datakey_master.py).
#
#  Two book layouts (measured 11-08):
#    ts   = Time Series (Company) books in 03_Universe/Update_File: DATA_Key D:E from row 2;
#           every query sheet (A6 like Period*To*) has row 8 = {=TRANSPOSE(DATA_Key!A2:A10002)}
#           over B8:NTP8 -> DATA_Key row r <-> row-8 column r (rows 2..10000).
#    peer = Peer Analysis books (03_Universe/Fundamental.xlsx): DATA_Key K:L from row 4; every
#           item sheet (A3 like Peer Analysis*) has A14:A5000 = IF(DATA_Key!$K4="","n/a",...)
#           -> DATA_Key row r <-> item-sheet row r+10 (rows 4..4990).
#
#  Rules (PLAN s5.2 step 7, F7 report s2.3-2.4):
#    - END-APPEND only. Never insert, sort, delete, or edit formulas: a mid-list insert saved
#      before a refresh attaches every stored value to the neighbouring ticker.
#    - Verify before save: the old part of the alignment axis is unchanged on every query
#      sheet, the new part equals the appended codes, the next slot is blank ('' or 'n/a'),
#      FilterMode False. Any failure -> close WITHOUT saving (exit 1).
#    - Backup the untouched file first (Copy-Item keeps LastWriteTime), outside Update_File.
#    - Records appended codes + the backfill start each book now needs
#      (.cache/qw_backfill_pending.json; consumed by the refresh step).
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File qw_datakey_sync.ps1 -WhatIf
#    powershell -ExecutionPolicy Bypass -File qw_datakey_sync.ps1 -Only OHLCVS
#  Exit: 0 ok (appended or nothing to do) | 1 verify/IO failure (book left unsaved) | 3 busy/precondition
# ==============================================================================
param(
  [string[]]$Only = @(),
  [switch]$WhatIf,
  [string]$Master = "",
  [string]$BookDir = "",
  [string]$UnivDir = "",
  [string]$BackupRoot = "",
  [string]$StatePath = "",
  [string]$PendingPath = "",
  [switch]$NoBusyCheck,         # synthetic tests only
  [switch]$InChain              # called by daily_refresh.sh [1pre-dk]: the chain itself (and its lock) is not 'busy'
)
$ErrorActionPreference = "Stop"
$ROOT = if ($env:QM_ROOT) { $env:QM_ROOT } else { "C:\Users\99922\OneDrive\Quant_Module_Moltbot" }
if (-not $Master)      { $Master      = Join-Path $ROOT "06_Registry\qw_datakey_master.json" }
if (-not $UnivDir)     { $UnivDir     = Join-Path $ROOT "03_Universe" }
if (-not $BookDir)     { $BookDir     = Join-Path $UnivDir "Update_File" }
if (-not $BackupRoot)  { $BackupRoot  = $UnivDir }
if (-not $StatePath)   { $StatePath   = Join-Path $ROOT ".cache\qw_datakey_sync_state.json" }
if (-not $PendingPath) { $PendingPath = Join-Path $ROOT ".cache\qw_backfill_pending.json" }
$Only = @($Only | ForEach-Object { "$_" -split ',' } | Where-Object { $_ -ne '' })

$LAYOUT = @{
  ts   = @{ code = 'D'; name = 'E'; r0 = 2; rmax = 10000; tag = 'A6'; like = 'Period*To*';     axis = 'row8'; blank = '' }
  peer = @{ code = 'K'; name = 'L'; r0 = 4; rmax = 4990;  tag = 'A3'; like = 'Peer Analysis*'; axis = 'colA'; off = 10; blank = 'n/a' }
}
# Core Update_File books = qw_refresh.ps1 $FILES minus Benchmark (no ticker list) + the fundamentals base book.
$BOOKS = [ordered]@{
  "OHLCVS"           = @{ path = (Join-Path $BookDir "OHLCVS_update.xlsx");           layout = 'ts' }
  "Universe_Support" = @{ path = (Join-Path $BookDir "Universe_Support_update.xlsx"); layout = 'ts' }
  "Investor_Act"     = @{ path = (Join-Path $BookDir "Investor_Act_update.xlsx");     layout = 'ts' }
  "Consensus"        = @{ path = (Join-Path $BookDir "Consensus_update.xlsx");        layout = 'ts' }
  "Fundamental"      = @{ path = (Join-Path $UnivDir "Fundamental.xlsx");             layout = 'peer' }
}
# ext books (02_Infrastructure/data/qw_updatefile_registry.json group=ext, layout=ts) built from the same template:
# new listings must reach them too. A book not built yet is skipped (optional), not an error.
$regPath = Join-Path $ROOT "02_Infrastructure\data\qw_updatefile_registry.json"
if (Test-Path -LiteralPath $regPath) {
  try {
    $reg = Get-Content -LiteralPath $regPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($b in @($reg.books | Where-Object { $_.group -eq 'ext' -and $_.layout -eq 'ts' })) {
      $p = if ($BookDir -ne (Join-Path $UnivDir "Update_File")) { Join-Path $BookDir ([IO.Path]::GetFileName("$($b.path)")) } else { Join-Path $ROOT ("$($b.path)" -replace '/', '\') }
      if (-not $BOOKS.Contains("$($b.name)")) { $BOOKS["$($b.name)"] = @{ path = $p; layout = 'ts'; optional = $true } }
    }
    # fundamentals_v2 DBs (Peer Analysis, built by qw_fundamental_book.ps1 -Mode build) - 2026-11-08
    if ($reg.fundamentals_v2) {
      $fvDir = "$($reg.fundamentals_v2.dir)"
      foreach ($d in @($reg.fundamentals_v2.dbs | ForEach-Object { $_ })) {
        $p = if ($UnivDir -ne (Join-Path $ROOT "03_Universe")) { Join-Path (Join-Path $UnivDir "Fundamental_v2") "$($d.file)" } else { Join-Path (Join-Path $ROOT ($fvDir -replace '/', '\')) "$($d.file)" }
        if (-not $BOOKS.Contains("$($d.name)")) { $BOOKS["$($d.name)"] = @{ path = $p; layout = 'peer'; optional = $true } }
      }
      # fundamentals_v2 time-series DBs (FundV2_TAX - Time Series (Company) layout, ops/qw_fund_v2_tax_ts.ps1) - 2026-11-09.
      #   Guarded: '$null | ForEach-Object' runs once with $null, which would register an empty book name.
      if ($reg.fundamentals_v2.ts_dbs) {
        foreach ($d in @($reg.fundamentals_v2.ts_dbs | ForEach-Object { $_ })) {
          $p = if ($UnivDir -ne (Join-Path $ROOT "03_Universe")) { Join-Path (Join-Path $UnivDir "Fundamental_v2") "$($d.file)" } else { Join-Path (Join-Path $ROOT ($fvDir -replace '/', '\')) "$($d.file)" }
          if ("$($d.name)" -and -not $BOOKS.Contains("$($d.name)")) { $BOOKS["$($d.name)"] = @{ path = $p; layout = 'ts'; optional = $true } }
        }
      }
    }
  } catch { Write-Host "[dk-sync] WARN registry unreadable ($regPath): $($_.Exception.Message)" }
}
$sel = @(if ($Only.Count -gt 0) { @($BOOKS.Keys) | Where-Object { $Only -contains $_ } } else { @($BOOKS.Keys) })
if ($Only.Count -gt 0 -and $sel.Count -ne $Only.Count) { Write-Host "[dk-sync] unknown book in -Only: $($Only -join ',')"; exit 3 }

function Get-Busy {
  $bashPat = if ($InChain) { 'qw_updatefile_unattended\.sh' } else { 'qw_updatefile_unattended\.sh|daily_refresh\.sh' }
  $p = Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'qw_refresh[^ ]*\.ps1|qw_excel_refresh\.ps1|qw_peer_refresh\.ps1|qw_fundamental_book\.ps1') -or
    ($_.Name -eq 'bash.exe' -and $_.CommandLine -match $bashPat) -or
    ($_.Name -eq 'python.exe' -and $_.CommandLine -match 'quantiwise_fetch\.py') -or
    ($_.Name -eq 'EXCEL.EXE' -and $_.CommandLine -match '/automation')
  }
  return @($p)
}
function Test-Exclusive($path) {
  try { $fs = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None'); $fs.Close(); return $true } catch { return $false }
}
function Norm($c) { $s = "$c".Trim(); if ($s -eq '') { return '' }; if ($s.StartsWith('A')) { return $s } else { return "A$s" } }
# Column index -> letters. String addresses only: PS 5.1 COM marshaling of $ws.Range($ws.Cells(..),$ws.Cells(..))
# was suspected first; the real culprits were the two array issues noted at Get-Axis and the write loop.
function ColName([int]$n) { $s = ''; while ($n -gt 0) { $r = ($n - 1) % 26; $s = [char](65 + $r) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }; return $s }
# Values along the alignment axis for DATA_Key rows r1..r2, as a flat 0-based object[].
#   Returned with a leading comma: unrolled through the pipeline, a 1-based object[,] from Excel raised
#   "Insufficient memory to continue the execution of the program" (measured 2026-11-08).
function Get-Axis($ws, $L, [int]$r1, [int]$r2) {
  $n = $r2 - $r1 + 1
  if ($L.axis -eq 'row8') { $v = $ws.Range("$(ColName $r1)8:$(ColName $r2)8").Value2 }
  else { $v = $ws.Range("A$($r1 + $L.off):A$($r2 + $L.off)").Value2 }
  $out = New-Object object[] $n
  if ($n -eq 1) { $out[0] = $v; return ,$out }
  for ($i = 1; $i -le $n; $i++) { if ($L.axis -eq 'row8') { $out[$i - 1] = $v[1, $i] } else { $out[$i - 1] = $v[$i, 1] } }
  return ,$out
}
function Save-JsonAtomic($obj, $path) {
  $tmp = "$path.tmp"
  ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $path -Force
}
function Load-JsonOrEmpty($path) {
  if (Test-Path -LiteralPath $path) { try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { } }
  return $null
}

if (-not $NoBusyCheck) {
  $busy = Get-Busy
  if ($busy.Count -gt 0) {
    Write-Host "[dk-sync] BUSY - Quantiwise job / daily refresh / automation Excel running; abort:"
    $busy | ForEach-Object { Write-Host ("  pid {0} {1}" -f $_.ProcessId, $_.Name) }
    exit 3
  }
  $lock = Join-Path $env:TEMP 'qm_daily_refresh.lock'
  if (-not $InChain -and (Test-Path -LiteralPath $lock)) { Write-Host "[dk-sync] daily refresh lock present ($lock); abort"; exit 3 }
}

if (-not (Test-Path -LiteralPath $Master)) { Write-Host "[dk-sync] master missing: $Master (run data/qw_datakey_master.py --seed)"; exit 3 }
$m = Get-Content -LiteralPath $Master -Raw -Encoding UTF8 | ConvertFrom-Json
$mCodes = @(); $mName = @{}; $mList = @{}
foreach ($e in $m.codes) { $c = Norm $e.code; $mCodes += $c; $mName[$c] = "$($e.name)"; if ($e.list_dd) { $mList[$c] = "$($e.list_dd)" } }
Write-Host ("[dk-sync] master {0} codes (last_krx_date {1})" -f $mCodes.Count, $m.last_krx_date)

$state = Load-JsonOrEmpty $StatePath
if (-not $state) { $state = [pscustomobject]@{ schema = 'qw_datakey_sync_state/v1'; runs = @() } }
$pending = Load-JsonOrEmpty $PendingPath
$pend = @{}
if ($pending) { foreach ($p in $pending.PSObject.Properties) { $pend[$p.Name] = $p.Value } }

$rcAll = 0
$runRec = [ordered]@{ at = (Get-Date -Format s); whatif = [bool]$WhatIf; books = [ordered]@{} }

foreach ($name in $sel) {
  $path = $BOOKS[$name].path; $L = $LAYOUT[$BOOKS[$name].layout]
  if (-not (Test-Path -LiteralPath $path)) {
    if ($BOOKS[$name].optional) { Write-Host "[$name] not built yet ($path) - skip"; continue }
    Write-Host "[$name] missing book $path"; $rcAll = 1; continue
  }
  if (-not (Test-Exclusive $path)) { Write-Host "[$name] book is open elsewhere (no exclusive access); skip"; $rcAll = 3; continue }
  $xl = $null; $wb = $null; $rec = [ordered]@{ path = $path; layout = $BOOKS[$name].layout; result = 'err' }
  try {
    $xl = New-Object -ComObject Excel.Application
    $xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.EnableEvents = $false
    $xl.ScreenUpdating = $false; $xl.AskToUpdateLinks = $false
    $t0 = Get-Date
    $wb = $xl.Workbooks.Open($path, 0, $false)
    Write-Host ("[{0}] opened in {1:n0}s ({2})" -f $name, ((Get-Date) - $t0).TotalSeconds, $BOOKS[$name].layout)
    $dk = $wb.Worksheets.Item("DATA_Key")
    $nSlots = $L.rmax - $L.r0 + 1
    $vals = $dk.Range("$($L.code)$($L.r0):$($L.code)$($L.rmax)").Value2
    $have = @{}; $nLast = $L.r0 - 1
    for ($i = 1; $i -le $nSlots; $i++) {
      $c = Norm $vals[$i, 1]
      if ($c -ne '') {
        if ($have.ContainsKey($c)) { throw "duplicate code in DATA_Key: $c (row $($L.r0 + $i - 1))" }
        $have[$c] = $L.r0 + $i - 1; $nLast = $L.r0 + $i - 1
      }
    }
    # the code column must be contiguous: a hole is a hand-edit symptom (and breaks 'last row' logic)
    if ($have.Count -ne ($nLast - $L.r0 + 1)) { throw "DATA_Key $($L.code)$($L.r0):$($L.code)$nLast not contiguous (codes $($have.Count))" }
    $missing = @($mCodes | Where-Object { -not $have.ContainsKey($_) })
    $extra = @($have.Keys | Where-Object { -not $mName.ContainsKey($_) })
    $k = $missing.Count
    $rec.n_before = $have.Count; $rec.n_missing = $k; $rec.not_in_master = $extra.Count
    Write-Host ("[{0}] DATA_Key {1} codes (rows {2}..{3}) | missing vs master {4} | book-only {5}" -f $name, $have.Count, $L.r0, $nLast, $k, $extra.Count)
    if ($extra.Count -gt 0) { Write-Host ("[{0}] WARN book-only codes (not in master): {1}" -f $name, (($extra | Select-Object -First 10) -join ',')) }
    if ($k -eq 0) { $rec.result = 'nochange'; $wb.Close($false); $wb = $null; $runRec.books[$name] = $rec; continue }
    if ($nLast + $k -gt $L.rmax) { throw "capacity: rows $nLast + $k > $($L.rmax)" }
    $first = $nLast + 1; $last = $nLast + $k
    Write-Host ("[{0}] append {1} codes -> {2}{3}:{4}{5}: {6}{7}" -f $name, $k, $L.code, $first, $L.name, $last, (($missing | Select-Object -First 8) -join ','), $(if ($k -gt 8) { ',...' } else { '' }))
    if ($WhatIf) { $rec.result = 'whatif'; $rec.would_append = $missing; $wb.Close($false); $wb = $null; $runRec.books[$name] = $rec; continue }

    $qs = @(); foreach ($ws in $wb.Worksheets) { if ("$($ws.Range($L.tag).Value2)" -like $L.like) { $qs += $ws } }
    if ($qs.Count -eq 0) { throw "no query sheet ($($L.tag) like $($L.like)) found" }
    $pre = @{}
    foreach ($ws in $qs) {
      if ($ws.FilterMode) { throw "sheet '$($ws.Name)' FilterMode=True" }
      $pre[$ws.Name] = Get-Axis $ws $L $L.r0 $nLast
    }
    # cell-by-cell writes: assigning a PowerShell object[,] to Range.Value2 raised "Insufficient memory"
    # under PS 5.1 (measured 2026-11-08); k is tens of rows, so 2k COM calls are cheap.
    for ($j = 0; $j -lt $k; $j++) {
      $r = $first + $j
      $dk.Range("$($L.code)$r").Value2 = [string]$missing[$j]
      $dk.Range("$($L.name)$r").Value2 = [string]$mName[$missing[$j]]
    }
    $xl.Calculate()

    # ---- verify on every query sheet ----
    $errs = @()
    foreach ($ws in $qs) {
      $now = Get-Axis $ws $L $L.r0 $nLast
      $old = $pre[$ws.Name]
      for ($i = 0; $i -lt $old.Count; $i++) { if ("$($now[$i])" -ne "$($old[$i])") { $errs += "sheet '$($ws.Name)' slot of DATA_Key row $($L.r0 + $i) changed '$($old[$i])'->'$($now[$i])'"; break } }
      $nw = Get-Axis $ws $L $first ($last + 1)
      for ($j = 0; $j -lt $k; $j++) { if ("$($nw[$j])" -ne $missing[$j]) { $errs += "sheet '$($ws.Name)' slot of DATA_Key row $($first + $j) = '$($nw[$j])' != $($missing[$j])"; break } }
      $nx = "$($nw[$k])"; if (-not ($nx -eq '' -or $nx -eq $L.blank)) { $errs += "sheet '$($ws.Name)' slot after the list not blank: '$nx'" }
      if ($ws.FilterMode) { $errs += "sheet '$($ws.Name)' FilterMode=True after write" }
    }
    if ($errs.Count -gt 0) {
      Write-Host "[$name] VERIFY FAILED -> close without saving:"; $errs | Select-Object -First 10 | ForEach-Object { Write-Host "   $_" }
      $rec.result = 'verify_failed'; $rec.errors = $errs; $wb.Close($false); $wb = $null; $rcAll = 1; $runRec.books[$name] = $rec; continue
    }
    Write-Host ("[{0}] verify OK ({1} query sheets) -> backup + save" -f $name, $qs.Count)
    $bdir = Join-Path $BackupRoot ("_backup_datakey_" + (Get-Date -Format yyyyMMdd))
    New-Item -ItemType Directory -Force -Path $bdir | Out-Null
    $bpath = Join-Path $bdir ([IO.Path]::GetFileName($path))
    if (-not (Test-Path -LiteralPath $bpath)) { Copy-Item -LiteralPath $path -Destination $bpath }   # untouched file on disk
    $t1 = Get-Date
    $wb.Save(); $wb.Close($false); $wb = $null
    Write-Host ("[{0}] saved in {1:n0}s" -f $name, ((Get-Date) - $t1).TotalSeconds)
    $rec.result = 'appended'; $rec.appended = $missing; $rec.n_after = $have.Count + $k; $rec.backup = $bpath
    $rec.sha256_after = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    # backfill start = earliest listing date among appended codes (unknown list_dd -> listed for the caller)
    $lds = @($missing | Where-Object { $mList.ContainsKey($_) } | ForEach-Object { $mList[$_] } | Sort-Object)
    $unknown = @($missing | Where-Object { -not $mList.ContainsKey($_) })
    $prev = $pend[$name]
    $from = if ($lds.Count -gt 0) { $lds[0] } else { $null }
    if ($prev -and $prev.from -and $from -and ("$($prev.from)" -lt $from)) { $from = "$($prev.from)" }
    $codesAll = @(@($missing) + @(if ($prev -and $prev.codes) { $prev.codes } else { @() }) | Select-Object -Unique)
    $pend[$name] = [ordered]@{ from = $from; codes = $codesAll; unknown_list_dd = $unknown; layout = $BOOKS[$name].layout; at = (Get-Date -Format s) }
    $rec.backfill_from = $from; $rec.unknown_list_dd = $unknown.Count
  } catch {
    $ln = $_.InvocationInfo.ScriptLineNumber; $lt = "$($_.InvocationInfo.Line)".Trim()
    Write-Host "[$name] ERROR (line $ln): $($_.Exception.Message)`n   at: $lt"; $rec.result = 'err'; $rec.error = "line $($ln): $($_.Exception.Message)"; $rcAll = 1
    if ($wb) { try { $wb.Close($false) } catch {}; $wb = $null }
  } finally {
    if ($xl) { try { $xl.Quit() } catch {}; [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
  }
  $runRec.books[$name] = $rec
}

if (-not $WhatIf) {
  $state.runs = @(@($state.runs) | Select-Object -Last 49) + @([pscustomobject]$runRec)
  Save-JsonAtomic $state $StatePath
  Save-JsonAtomic ([pscustomobject]$pend) $PendingPath
}
Write-Host "[dk-sync] END rc=$rcAll"
exit $rcAll
