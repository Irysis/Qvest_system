# ==============================================================================
#  qw_fund_v2_update.ps1 - rolling update of the fundamentals_v2 DBs (last N quarters)
#  (ASCII-only for PowerShell 5.1 encoding safety)
# ==============================================================================
#  Why (2026-11-08, 04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/README.md):
#    the history DBs (FundV2_* 2000Q1~) are refreshed once. New quarters, late filers and restatements
#    arrive later, so each update DB (registry fundamentals_v2.dbs[] with window_quarters + target)
#    re-fetches only the last N quarters and the loader replaces that window in the parent parquet
#    (value changes -> .cache/qw_fund_v2/revisions.parquet).
#  Steps per update DB: build (-Force: the window moves every quarter and a fresh template keeps B1 at the
#    template stamp, so loader G1 proves the refresh happened) -> DATA_Key sync (new listings) ->
#    qw_peer_refresh.ps1 -> qw_fund_v2_ingest.py --db <name>.
#  Stops at the first failure. A kicked session (rc 4) is NOT re-logged here - re-login belongs to
#    qw_refresh.ps1 Ensure-Login (once per run; Dohoon 11-06 standing rule: no login war).
#  Usage: powershell -File qw_fund_v2_update.ps1 [-Only FundV2_BS_upd,...] [-WhatIf]
#  Exit: 0 all done | 3 precondition / busy / kicked | 1 failure
# ==============================================================================
param([string[]]$Only = @(), [switch]$WhatIf)
$ErrorActionPreference = "Stop"
$ROOT = if ($env:QM_ROOT) { $env:QM_ROOT } else { "C:\Users\99922\OneDrive\Quant_Module_Moltbot" }
$OPS = Join-Path $ROOT "02_Infrastructure\ops"
$PY = Join-Path $ROOT ".venv_qvest_ml\Scripts\python.exe"
$Only = @($Only | ForEach-Object { "$_" -split ',' } | Where-Object { $_ -ne '' })
$reg = Get-Content -LiteralPath (Join-Path $ROOT "02_Infrastructure\data\qw_updatefile_registry.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$fv = $reg.fundamentals_v2
$upd = @($fv.dbs | ForEach-Object { $_ } | Where-Object { $_.window_quarters -and $_.target })
if ($Only.Count -gt 0) { $upd = @($upd | Where-Object { $Only -contains "$($_.name)" }) }
if ($upd.Count -eq 0) { Write-Host "[fund-upd] no update DB selected"; exit 3 }
$t0 = Get-Date
Write-Host ("[fund-upd] start {0} | {1}" -f $t0.ToString('yyyy-MM-dd HH:mm:ss'), (($upd | ForEach-Object { $_.name }) -join ','))
foreach ($d in $upd) {
  $name = "$($d.name)"
  $book = Join-Path (Join-Path $ROOT ("$($fv.dir)" -replace '/', '\')) "$($d.file)"
  if ($WhatIf) { Write-Host "[fund-upd] $name -> build -Force, dk-sync, peer refresh, ingest (WhatIf)"; continue }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_fundamental_book.ps1") -Mode build -Db $name -Force
  if ($LASTEXITCODE -ne 0) { Write-Host "[fund-upd] $name build rc=$LASTEXITCODE - stop"; exit $(if ($LASTEXITCODE -eq 3) { 3 } else { 1 }) }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_datakey_sync.ps1") -Only $name
  if ($LASTEXITCODE -ne 0) { Write-Host "[fund-upd] $name dk-sync rc=$LASTEXITCODE - stop"; exit $(if ($LASTEXITCODE -eq 3) { 3 } else { 1 }) }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_peer_refresh.ps1") -Book $book
  $rc = $LASTEXITCODE
  if ($rc -ne 0) { Write-Host "[fund-upd] $name refresh rc=$rc - stop (4 = kicked: re-login via qw_refresh.ps1, then re-run)"; exit $(if ($rc -eq 3 -or $rc -eq 4) { 3 } else { 1 }) }
  & $PY -X utf8 (Join-Path $ROOT "02_Infrastructure\data\qw_fund_v2_ingest.py") --db $name
  $rc = $LASTEXITCODE
  if ($rc -ne 0 -and $rc -ne 2) { Write-Host "[fund-upd] $name ingest rc=$rc - stop"; exit $(if ($rc -eq 3) { 3 } else { 1 }) }
}
Write-Host ("[fund-upd] END {0} | {1:n0}s" -f (Get-Date -Format HH:mm:ss), ((Get-Date) - $t0).TotalSeconds)
exit 0
