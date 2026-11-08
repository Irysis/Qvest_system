# ==============================================================================
#  qw_book_build.ps1 - build a Quantiwise Time Series query book from the registry
#  (02_Infrastructure/data/qw_updatefile_registry.json) by copying the lean template
#  (ASCII-only for PowerShell 5.1 encoding safety)
# ==============================================================================
#  Why (2026-11-08, BUILD_20261108.md s2 / PLAN s3.2): glossary item codes -> one query sheet per
#    item, same layout the add-in + qw_refresh.ps1 + loaders already understand. No hand-made books.
#  Template = 03_Universe/Update_File/OHLCVS_update.xlsx (lean 18 MB; DATA_Key = canonical list
#    after qw_datakey_sync.ps1). Measured layout 11-08: A1 'Refresh' hyperlink (ScreenTip
#    'Quantiwise7G'), A3 'Time Series (Company)', B4 freq, D4 non-business fill, A5/B5 Period(From),
#    A6/B6 Period(To) 'CPD-1TD', row 8 {=TRANSPOSE(DATA_Key!A2:A10002)} over B8:NTP8, row 9 names,
#    B10 item code (one item per sheet), row 11 units, row 14 item names, data from row 15.
#  Steps: copy template -> per registry sheet copy the first query sheet (keeps hyperlink + row-8
#    array) -> rename = sheet id, B10 = item code, B4/D4 = registry freq/fill, B5 = -From,
#    B6 = 'CPD-1TD', clear B9/B11/B14 (the add-in fills them), DELETE rows 15.. (not clear - no
#    bloat) -> delete the template's own query sheets -> verify -> save.
#  Verify (before save): every new sheet has a 'Quantiwise*' ScreenTip hyperlink, A5/A6 labels,
#    B10 = registry code, row-8 array intact (B8 HasArray, B8 = first DATA_Key code), no data rows.
#  Usage: powershell -File qw_book_build.ps1 -Book ShortLending -From 20261102 [-Out <xlsx>] [-Force]
#  Exit: 0 built | 1 failure (nothing written at -Out) | 3 precondition
# ==============================================================================
param(
  [Parameter(Mandatory = $true)][string]$Book,
  [Parameter(Mandatory = $true)][string]$From,          # YYYYMMDD written to B5 of every sheet
  [string]$Registry = "",
  [string]$Out = "",
  [string]$Template = "",
  [switch]$Force,
  [switch]$NoBusyCheck
)
$ErrorActionPreference = "Stop"
$ROOT = if ($env:QM_ROOT) { $env:QM_ROOT } else { "C:\Users\99922\OneDrive\Quant_Module_Moltbot" }
if (-not $Registry) { $Registry = Join-Path $ROOT "02_Infrastructure\data\qw_updatefile_registry.json" }
if ($From -notmatch '^\d{8}$') { Write-Host "[book-build] -From YYYYMMDD required"; exit 3 }
$reg = Get-Content -LiteralPath $Registry -Raw -Encoding UTF8 | ConvertFrom-Json
$bk = @($reg.books | Where-Object { $_.name -eq $Book })
if ($bk.Count -ne 1) { Write-Host "[book-build] book '$Book' not in registry"; exit 3 }
$bk = $bk[0]
if ($bk.layout -ne 'ts' -or $bk.group -eq 'core') { Write-Host "[book-build] '$Book' is not an ext Time Series book (layout=$($bk.layout) group=$($bk.group))"; exit 3 }
if (-not $Out) { $Out = Join-Path $ROOT ($bk.path -replace '/', '\') }
if (-not $Template) { $Template = Join-Path $ROOT ($reg.template_ts -replace '/', '\') }
if ((Test-Path -LiteralPath $Out) -and -not $Force) { Write-Host "[book-build] $Out exists (use -Force to rebuild - existing data would be lost)"; exit 3 }
if (-not $NoBusyCheck) {
  $busy = @(Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'qw_refresh[^ ]*\.ps1|qw_excel_refresh\.ps1|qw_datakey_sync\.ps1|qw_peer_refresh\.ps1') -or
    ($_.Name -eq 'EXCEL.EXE' -and $_.CommandLine -match '/automation') })
  if ($busy.Count -gt 0) { Write-Host "[book-build] BUSY (Quantiwise job / automation Excel)"; $busy | ForEach-Object { Write-Host ("  pid {0} {1}" -f $_.ProcessId, $_.Name) }; exit 3 }
}
function ColName([int]$n) { $s = ''; while ($n -gt 0) { $r = ($n - 1) % 26; $s = [char](65 + $r) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }; return $s }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Out) | Out-Null
$tmpOut = [IO.Path]::Combine((Split-Path -Parent $Out), ("~build_" + [IO.Path]::GetFileName($Out)))
Copy-Item -LiteralPath $Template -Destination $tmpOut -Force
$xl = $null; $wb = $null; $rc = 1
try {
  $xl = New-Object -ComObject Excel.Application
  $xl.Visible = $false; $xl.DisplayAlerts = $false; $xl.EnableEvents = $false; $xl.ScreenUpdating = $false; $xl.AskToUpdateLinks = $false
  $wb = $xl.Workbooks.Open($tmpOut, 0, $false)
  $dk = $wb.Worksheets.Item("DATA_Key")
  $orig = @(); foreach ($ws in $wb.Worksheets) { if ("$($ws.Range('A6').Value2)" -like 'Period*To*') { $orig += $ws } }
  if ($orig.Count -eq 0) { throw "template has no query sheet" }
  $base = $orig[0]
  $lastCol = ColName 10000
  $new = @()
  foreach ($s in $bk.sheets) {
    $base.Copy($dk)                                    # insert before DATA_Key -> keeps hyperlink + row-8 array
    $ws = $wb.Worksheets.Item($dk.Index - 1)
    $ws.Name = "$($s.sheet)"
    $ws.Range("B10").Value2 = "$($s.item_code)"
    $ws.Range("B4").Value2 = "$($bk.freq)"
    $ws.Range("D4").Value2 = [double]$bk.fill_nonbiz
    $ws.Range("B5").Value2 = [double]$From
    $ws.Range("B6").Value2 = "CPD-1TD"
    foreach ($r in 9, 11, 14) { $ws.Range("B$($r):$($lastCol)$($r)").ClearContents() | Out-Null }
    $ur = $ws.UsedRange; $lastRow = $ur.Row + $ur.Rows.Count - 1
    if ($lastRow -ge 15) { $ws.Range("15:$lastRow").EntireRow.Delete() | Out-Null }
    $new += $ws
    Write-Host ("  + {0} = {1} ({2})" -f $s.sheet, $s.item_code, $s.unit)
  }
  foreach ($ws in $orig) { $ws.Delete() }
  $xl.Calculate()
  # ---- verify ----
  $errs = @()
  $firstCode = "$($dk.Range('A2').Value2)"
  foreach ($ws in $new) {
    $hl = 0; foreach ($h in $ws.Hyperlinks) { if ($h.ScreenTip -like 'Quantiwise*') { $hl++ } }
    if ($hl -lt 1) { $errs += "$($ws.Name): no Quantiwise hyperlink" }
    if ("$($ws.Range('A5').Value2)" -notlike 'Period*From*' -or "$($ws.Range('A6').Value2)" -notlike 'Period*To*') { $errs += "$($ws.Name): A5/A6 labels" }
    $want = "$((@($bk.sheets | Where-Object { $_.sheet -eq $ws.Name }))[0].item_code)"
    if ("$($ws.Range('B10').Value2)" -ne $want) { $errs += "$($ws.Name): B10 '$($ws.Range('B10').Value2)' != $want" }
    if (-not $ws.Range("B8").HasArray -or "$($ws.Range('B8').Value2)" -ne $firstCode) { $errs += "$($ws.Name): row-8 array broken (B8='$($ws.Range('B8').Value2)' vs DATA_Key A2 '$firstCode')" }
    $ur = $ws.UsedRange; if (($ur.Row + $ur.Rows.Count - 1) -gt 14) { $errs += "$($ws.Name): data rows remain" }
  }
  if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host "  VERIFY: $_" }; throw "verify failed ($($errs.Count))" }
  $wb.Save(); $wb.Close($false); $wb = $null
  Move-Item -LiteralPath $tmpOut -Destination $Out -Force
  Write-Host ("[book-build] {0}: {1} sheets, B5={2} -> {3}" -f $Book, $new.Count, $From, $Out)
  $rc = 0
} catch {
  $ln = $_.InvocationInfo.ScriptLineNumber
  Write-Host "[book-build] ERROR (line $ln): $($_.Exception.Message)"
  if ($wb) { try { $wb.Close($false) } catch {} ; $wb = $null }
  Remove-Item -LiteralPath $tmpOut -Force -ErrorAction SilentlyContinue
  $rc = 1
} finally {
  if ($xl) { try { $xl.Quit() } catch {}; [Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null }
  [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}
exit $rc
