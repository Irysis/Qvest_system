# ==============================================================================
#  qw_fundamental_book.ps1 - shape Quantiwise "Peer Analysis (To Select)" fundamentals books
#  (ASCII-only for PowerShell 5.1 encoding safety)
# ==============================================================================
#  Why (2026-11-08, 04_Research/01_reports/quantiwise_data_expansion_20261106/BUILD_20261108.md s2):
#    03_Universe/Fundamental.xlsx stops at 201412 for 39 of its 41 item sheets (only ISSD/SBB were
#    extended to 202512 by hand), so every fundamentals factor after 2014 came from DART annual
#    rows only (504-714 tickers/year). It also lacks CAPEX, non-controlling interest, parent net
#    income/equity, preferred capital, bonds, report dates (QMJ needs them).
#
#  Measured layout (openpyxl 11-08): one item per sheet; A3 = 'Peer Analysis (To Select)';
#    row 9 = item code (D9 e.g. 'M121000.M', E9.. '=$D$9'); row 10 = periods (YYYYMM, D..);
#    row 11 = unit; row 13 = header (Code, Name, fiscal month, item name per period col);
#    rows 14..5000 col A = IF(DATA_Key!$K4="","n/a",DATA_Key!$K4); B/C = name, fiscal month
#    (filled by the add-in); data D14.. filled by the add-in on Refresh (A1 hyperlink).
#
#  Modes:
#    -Mode extend   : on every item sheet append period columns after the last one up to
#                     -TargetPeriod (row 9 '=$D$9', row 10 period, row 11/13 copied from the
#                     last column; data cells left blank for the refresh), then add new item
#                     sheets from -ItemsJson (copy of -TemplateSheet, D9 = code, data cleared).
#    -Mode testbook : build a small positive-control book from -Book: keep DATA_Key + item
#                     sheets from -ItemsJson only, with period columns = -Periods.
#    -Mode build    : same construction for a registry DB (02_Infrastructure/data/
#                     qw_updatefile_registry.json :: fundamentals_v2): -Db <name> picks dbs[].items
#                     from the item catalog; periods = period_from..period_to ('auto' = last
#                     quarter-end month <= today), or the last window_quarters of it (update DB);
#                     out = fundamentals_v2.dir/<file>. Refuses an existing file unless -Force.
#  testbook/build verify every new sheet before saving (A3 Peer Analysis, D9 = code, row 10 =
#  periods and nothing after, Quantiwise refresh link, A14 DATA_Key-driven, data area empty).
#  Writes -Out (never modifies -Book in place unless -Out equals -Book; then a backup is
#  taken first under 03_Universe/_backup_fundamental_<yyyyMMdd>/).
#  Exit: 0 ok | 1 failure (output not saved) | 3 busy/precondition
# ==============================================================================
param(
  [ValidateSet('extend', 'testbook', 'build')][string]$Mode = 'extend',
  [string]$Book = "",
  [string]$Out = "",
  [string]$TargetPeriod = "",           # YYYYMM, quarter end month (03/06/09/12)
  [string]$Periods = "",                # testbook: comma list of YYYYMM
  [string]$ItemsJson = "",              # [{ "sheet": "CAPEX", "code": "M132010.M" }, ...]
  [string]$TemplateSheet = "",          # default = first item sheet
  [string]$Registry = "",               # build: registry with a fundamentals_v2 section
  [string]$Db = "",                     # build: fundamentals_v2.dbs[].name
  [string]$Today = "",                  # build: YYYYMMDD for period_to = 'auto' (tests); default = today
  [switch]$Force,                       # build: overwrite an existing DB file (refreshed data is lost)
  [switch]$NoBusyCheck
)
$ErrorActionPreference = "Stop"
$ROOT = if ($env:QM_ROOT) { $env:QM_ROOT } else { "C:\Users\99922\OneDrive\Quant_Module_Moltbot" }
if (-not $Book) { $Book = Join-Path $ROOT "03_Universe\Fundamental.xlsx" }
if ($Mode -ne 'build' -and -not $Out)  { Write-Host "[fund-book] -Out required"; exit 3 }

function ColName([int]$n) { $s = ''; while ($n -gt 0) { $r = ($n - 1) % 26; $s = [char](65 + $r) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }; return $s }
function Next-Quarter([int]$p) { $y = [int][Math]::Floor($p / 100); $mo = $p % 100; $mo += 3; if ($mo -gt 12) { $mo -= 12; $y += 1 }; return ($y * 100 + $mo) }
function Get-Busy {
  $p = Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'qw_refresh[^ ]*\.ps1|qw_excel_refresh\.ps1|qw_datakey_sync\.ps1|qw_peer_refresh\.ps1') -or
    ($_.Name -eq 'bash.exe' -and $_.CommandLine -match 'qw_updatefile_unattended\.sh|daily_refresh\.sh') -or
    ($_.Name -eq 'python.exe' -and $_.CommandLine -match 'quantiwise_fetch\.py') -or
    ($_.Name -eq 'EXCEL.EXE' -and $_.CommandLine -match '/automation')
  }
  return @($p)
}
function Is-ItemSheet($ws) { return ("$($ws.Range('A3').Value2)" -like 'Peer Analysis*') }
function Last-PeriodCol($ws) {
  # last non-empty cell in row 10 from column D (4); periods are numbers or YYYYMM strings
  $c = 4; $last = 0; $lastP = 0
  while ($c -lt 400) {
    $v = "$($ws.Range("$(ColName $c)10").Value2)".Trim()
    if ($v -eq '') { break }
    if ($v -match '^\d{6}$') { $last = $c; $lastP = [int]$v } else { throw "sheet '$($ws.Name)' row 10 col $(ColName $c) not YYYYMM: '$v'" }
    $c++
  }
  return @($last, $lastP)
}
function Append-Periods($ws, [int[]]$plist) {
  $lp = Last-PeriodCol $ws; $c = $lp[0]
  if ($c -lt 4) { throw "sheet '$($ws.Name)' has no period columns" }
  $unit = $ws.Range("$(ColName $c)11").Value2; $hdr = $ws.Range("$(ColName $c)13").Value2
  foreach ($p in $plist) {
    $c++; $cl = ColName $c
    $ws.Range("$($cl)9").Formula = '=$D$9'
    $ws.Range("$($cl)10").Value2 = [double]$p
    $ws.Range("$($cl)11").Value2 = $unit
    $ws.Range("$($cl)13").Value2 = $hdr
  }
  return $c
}

if (-not $NoBusyCheck) {
  $busy = Get-Busy
  if ($busy.Count -gt 0) { Write-Host "[fund-book] BUSY - Quantiwise job / automation Excel running; abort"; $busy | ForEach-Object { Write-Host ("  pid {0} {1}" -f $_.ProcessId, $_.Name) }; exit 3 }
}
$items = @()
# PS 5.1: ConvertFrom-Json writes a top-level JSON array as ONE pipeline object, so @(... | ConvertFrom-Json)
# is a 1-element array holding the whole list ("$($it.sheet)" then joins every name -> invalid sheet name,
# 11-08). Re-enumerate through ForEach-Object.
if ($ItemsJson) { $rawItems = Get-Content -LiteralPath $ItemsJson -Raw -Encoding UTF8 | ConvertFrom-Json; $items = @($rawItems | ForEach-Object { $_ }) }
if ($Mode -eq 'build') {
  # fundamentals_v2 = { template, dir, period_from, period_to ('auto' = last quarter-end month <= today),
  #   items[] (catalog: sheet, code, ...), dbs[] = { name, file, items[] = catalog sheet names,
  #   window_quarters? (rolling update DB = last N quarters ending at period_to) } }
  if (-not $Registry) { $Registry = Join-Path $ROOT "02_Infrastructure\data\qw_updatefile_registry.json" }
  $reg = Get-Content -LiteralPath $Registry -Raw -Encoding UTF8 | ConvertFrom-Json
  $fv = $reg.fundamentals_v2
  if (-not $fv) { Write-Host "[fund-book] registry has no fundamentals_v2: $Registry"; exit 3 }
  $dbe = @($fv.dbs | ForEach-Object { $_ } | Where-Object { "$($_.name)" -eq $Db })
  if ($dbe.Count -ne 1) { Write-Host "[fund-book] -Db '$Db' not in fundamentals_v2.dbs ($(@($fv.dbs | ForEach-Object { $_.name }) -join ','))"; exit 3 }
  $dbe = $dbe[0]
  $cat = @{}; foreach ($c in @($fv.items | ForEach-Object { $_ })) { $cat["$($c.sheet)"] = $c }
  # update DB (window_quarters + target) may take its sheet list from the parent: items_from = <db name>
  $srcDb = $dbe
  if ($dbe.items_from) {
    $srcDb = @($fv.dbs | ForEach-Object { $_ } | Where-Object { "$($_.name)" -eq "$($dbe.items_from)" })
    if ($srcDb.Count -ne 1) { Write-Host "[fund-book] items_from '$($dbe.items_from)' not in fundamentals_v2.dbs"; exit 3 }
    $srcDb = $srcDb[0]
  }
  $items = @(foreach ($s in @($srcDb.items | ForEach-Object { $_ })) {
    if (-not $cat.ContainsKey("$s")) { Write-Host "[fund-book] db '$Db' lists '$s' - not in fundamentals_v2.items"; exit 3 }
    $cat["$s"]
  })
  if ($fv.template) { $Book = Join-Path $ROOT ("$($fv.template)" -replace '/', '\') }
  if (-not $Out) { $Out = Join-Path (Join-Path $ROOT ("$($fv.dir)" -replace '/', '\')) "$($dbe.file)" }
  $td = if ($Today) { [datetime]::ParseExact($Today, 'yyyyMMdd', $null) } else { Get-Date }
  $pto = "$($fv.period_to)"
  if ($pto -eq 'auto' -or -not $pto) {
    $qm = @(3, 6, 9, 12) | Where-Object { (New-Object datetime($td.Year, $_, 1)).AddMonths(1).AddDays(-1) -le $td.Date } | Select-Object -Last 1
    $pto = if ($qm) { "{0}{1:d2}" -f $td.Year, $qm } else { "{0}12" -f ($td.Year - 1) }
  }
  $p = [int]"$($fv.period_from)"; $plistB = @()
  if ($p % 100 -notin 3, 6, 9, 12) { Write-Host "[fund-book] period_from not a quarter end: $p"; exit 3 }
  while ($p -le [int]$pto) { $plistB += $p; $p = Next-Quarter $p }
  if ($dbe.window_quarters) { $w = [int]$dbe.window_quarters; if ($plistB.Count -gt $w) { $plistB = @($plistB[($plistB.Count - $w)..($plistB.Count - 1)]) } }
  $Periods = ($plistB -join ',')
  Write-Host ("[fund-book] build {0}: {1} items x {2} periods ({3}..{4}) -> {5}" -f $Db, $items.Count, $plistB.Count, $plistB[0], $plistB[-1], $Out)
  if ((Test-Path -LiteralPath $Out) -and -not $Force) { Write-Host "[fund-book] $Out exists - refreshed data would be lost; pass -Force to rebuild"; exit 3 }
  $odir = Split-Path -Parent $Out; if (-not (Test-Path -LiteralPath $odir)) { New-Item -ItemType Directory -Force -Path $odir | Out-Null }
}
foreach ($it in $items) {
  $nm = "$($it.sheet)"
  if ($nm.Length -lt 1 -or $nm.Length -gt 31 -or $nm -match '[:\\/\?\*\[\]]' -or -not "$($it.code)") { Write-Host "[fund-book] bad item entry: sheet='$nm' code='$($it.code)'"; exit 3 }
}
$dupe = @($items | Group-Object { "$($_.sheet)" } | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
if ($dupe.Count -gt 0) { Write-Host "[fund-book] duplicate sheet names: $($dupe -join ',')"; exit 3 }

$srcPath = $Book
if ((Resolve-Path -LiteralPath $Book).Path -eq [IO.Path]::GetFullPath($Out)) {
  $bdir = Join-Path $ROOT ("03_Universe\_backup_fundamental_" + (Get-Date -Format yyyyMMdd))
  New-Item -ItemType Directory -Force -Path $bdir | Out-Null
  $bp = Join-Path $bdir ([IO.Path]::GetFileName($Book))
  if (-not (Test-Path -LiteralPath $bp)) { Copy-Item -LiteralPath $Book -Destination $bp }
  Write-Host "[fund-book] in-place edit; backup = $bp"
} else {
  Copy-Item -LiteralPath $Book -Destination $Out -Force
  $srcPath = $Out
}

$xl = $null; $wb = $null; $rc = 1
try {
  $xl = New-Object -ComObject Excel.Application
  $xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.EnableEvents = $false; $xl.ScreenUpdating = $false; $xl.AskToUpdateLinks = $false
  $wb = $xl.Workbooks.Open($srcPath, 0, $false)
  $sheets = @(); foreach ($ws in $wb.Worksheets) { if (Is-ItemSheet $ws) { $sheets += $ws } }
  Write-Host ("[fund-book] {0}: {1} item sheets" -f $Mode, $sheets.Count)
  $tmplName = if ($TemplateSheet) { $TemplateSheet } else { $sheets[0].Name }
  $tmpl = $wb.Worksheets.Item($tmplName)

  if ($Mode -eq 'testbook' -or $Mode -eq 'build') {
    $plist = @($Periods -split ',' | Where-Object { $_ -match '^\d{6}$' } | ForEach-Object { [int]$_ })
    if ($plist.Count -eq 0) { throw "-Periods required for $Mode" }
    if ($items.Count -eq 0) { throw "items required for $Mode (-ItemsJson or registry db)" }
    # template: keep column D (E9.. refer to $D$9 - deleting D would turn them into #REF!), drop E..last,
    # make D the first requested period, then append the rest after it.
    $lp = Last-PeriodCol $tmpl
    if ($lp[0] -gt 4) { $tmpl.Range("E:$(ColName $lp[0])").Delete() | Out-Null }
    $tmpl.Range("D10").Value2 = [double]$plist[0]
    if ($plist.Count -gt 1) { $null = Append-Periods $tmpl @($plist[1..($plist.Count - 1)]) }
    $tmpl.Range("D14:$(ColName (3 + $plist.Count))5000").ClearContents() | Out-Null
    # new sheets get temporary names first: a requested name may equal an original sheet that is
    # deleted only below (e.g. 'ISSD' - Excel refuses the duplicate, 11-08).
    $made = @(); $k = 0
    foreach ($it in $items) {
      $k++
      $tmpl.Copy([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
      $ns = $wb.Worksheets.Item($wb.Worksheets.Count); $ns.Name = ("~new_{0:d3}" -f $k)
      $ns.Range("D9").Value2 = "$($it.code)"
      $ns.Range("D13:$(ColName (3 + $plist.Count))13").Value2 = "$($it.sheet)"
      $made += , @($ns, "$($it.sheet)")
    }
    # drop every original item sheet (the template included) -> only DATA_Key + new sheets remain
    $xl.DisplayAlerts = $false
    foreach ($ws in @($sheets)) { $ws.Delete() }
    foreach ($pair in $made) { $pair[0].Name = $pair[1] }
    # verify before saving (a bad DB is not saved): code, periods, add-in link, DATA_Key-driven rows, empty data
    $lastC = ColName (3 + $plist.Count); $bad = @()
    foreach ($pair in $made) {
      $ws = $pair[0]; $it = @($items | Where-Object { "$($_.sheet)" -eq $pair[1] })[0]
      if ("$($ws.Range('A3').Value2)" -notlike 'Peer Analysis*') { $bad += "$($ws.Name): A3" }
      if ("$($ws.Range('D9').Value2)" -ne "$($it.code)") { $bad += "$($ws.Name): D9 '$($ws.Range('D9').Value2)' <> '$($it.code)'" }
      for ($j = 0; $j -lt $plist.Count; $j++) { $v = "$($ws.Range("$(ColName (4 + $j))10").Value2)"; if ([int][double]$v -ne $plist[$j]) { $bad += "$($ws.Name): period col $(ColName (4 + $j)) '$v' <> $($plist[$j])"; break } }
      if ("$($ws.Range("$(ColName (4 + $plist.Count))10").Value2)" -ne '') { $bad += "$($ws.Name): extra period after $lastC" }
      $nl = 0; foreach ($h in $ws.Hyperlinks) { if ($h.ScreenTip -like 'Quantiwise*') { $nl++ } }; if ($nl -lt 1) { $bad += "$($ws.Name): no Quantiwise refresh link" }
      if ("$($ws.Range('A14').Formula)" -notmatch 'DATA_Key!\$K4') { $bad += "$($ws.Name): A14 not DATA_Key-driven" }
      if ($xl.WorksheetFunction.CountA($ws.Range("D14:$($lastC)5000")) -ne 0) { $bad += "$($ws.Name): data area not empty" }
    }
    if ($bad.Count -gt 0) { throw ("verify failed: " + ($bad -join ' | ')) }
    Write-Host ("[fund-book] verified {0} sheets x {1} periods ({2}..{3})" -f $made.Count, $plist.Count, $plist[0], $plist[-1])
  } else {
    if ($TargetPeriod -notmatch '^\d{6}$') { throw "-TargetPeriod YYYYMM required for extend" }
    $tp = [int]$TargetPeriod
    foreach ($ws in $sheets) {
      $lp = Last-PeriodCol $ws; $p = $lp[1]; $add = @()
      while ((Next-Quarter $p) -le $tp) { $p = Next-Quarter $p; $add += $p }
      if ($add.Count -gt 0) { $c = Append-Periods $ws $add; Write-Host ("  {0}: {1} -> {2} (+{3} cols, last {4})" -f $ws.Name, $lp[1], $p, $add.Count, (ColName $c)) }
    }
    $lastCol = (Last-PeriodCol $tmpl)[0]
    foreach ($it in $items) {
      $exists = $false; foreach ($ws in $wb.Worksheets) { if ($ws.Name -eq "$($it.sheet)") { $exists = $true } }
      if ($exists) { Write-Host "  item sheet '$($it.sheet)' exists - skip"; continue }
      $tmpl.Copy([Type]::Missing, $wb.Worksheets.Item($wb.Worksheets.Count))
      $ns = $wb.Worksheets.Item($wb.Worksheets.Count); $ns.Name = "$($it.sheet)"
      $ns.Range("D9").Value2 = "$($it.code)"
      $ns.Range("D13:$(ColName $lastCol)13").Value2 = "$($it.sheet)"
      $ns.Range("D14:$(ColName $lastCol)5000").ClearContents() | Out-Null
      Write-Host ("  + item sheet {0} = {1}" -f $it.sheet, $it.code)
    }
  }
  $wb.Save(); $rc = 0
  Write-Host "[fund-book] saved $srcPath"
} catch {
  $ln = $_.InvocationInfo.ScriptLineNumber
  Write-Host "[fund-book] ERROR (line $ln): $($_.Exception.Message)"; $rc = 1
} finally {
  if ($wb) { try { $wb.Close($false) } catch {} }
  if ($xl) { try { $xl.Quit() } catch {}; [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
exit $rc
