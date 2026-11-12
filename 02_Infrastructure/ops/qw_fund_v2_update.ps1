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
#  Time-series DB (2026-11-09, Dohoon 'beobinse B code pateu-do jeonggi gaengsin-e neocha'): registry
#    fundamentals_v2.ts_dbs[] with update.window_quarters (FundV2_TAX, tax B codes) -> DATA_Key sync of the full book ->
#    qw_fund_v2_tax_ts.ps1 -WindowQuarters N (full book as template -> update book; re-logs in itself on kicks) ->
#    qw_fund_v2_tax_ingest.py --window (same window_merge / revisions as the Peer DBs). Selected as -Only <update.db>.
#  Failure policy (2026-11-09): one DB's failure does not block the other DBs. A session / busy / precondition stop
#    (step rc 3) ends the run - every later DB needs the same session.
#  Kicks (2026-11-13 Dohoon decision QW-NIGHT-SESSION-ENSURE-20261113 'no limit on re-logins; always re-login at once when the office PC
#    logs in'; replaces the 11-06 'no login war' rule): a peer refresh that ends kicked (rc 4) -> qw_refresh.ps1 -LoginOnly -> re-run that
#    refresh, no limit. Stops only on a login that never comes alive (logins_ok 0 -> rc 3, account-lock guard) or the runaway guard
#    QVEST_QW_KICK_STALL (default 30 kicks in one step; 0 = off). The tax time-series step re-logs in per sheet itself (no -NoRelogin).
#  Usage: powershell -File qw_fund_v2_update.ps1 [-Only FundV2_BS_upd,FundV2_TAX_upd,...] [-WhatIf]
#  Exit: 0 all done | 1 any DB failed | 3 precondition / busy / kicked / loader gate refused (nothing else failed)
# ==============================================================================
param([string[]]$Only = @(), [switch]$WhatIf)
$ErrorActionPreference = "Stop"
$ROOT = if ($env:QM_ROOT) { $env:QM_ROOT } else { "C:\Users\99922\OneDrive\Quant_Module_Moltbot" }
$OPS = Join-Path $ROOT "02_Infrastructure\ops"
$PY = Join-Path $ROOT ".venv_qvest_ml\Scripts\python.exe"
$Only = @($Only | ForEach-Object { "$_" -split ',' } | Where-Object { $_ -ne '' })
$reg = Get-Content -LiteralPath (Join-Path $ROOT "02_Infrastructure\data\qw_updatefile_registry.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$fv = $reg.fundamentals_v2
$fvDir = Join-Path $ROOT ("$($fv.dir)" -replace '/', '\')
$upd = @($fv.dbs | ForEach-Object { $_ } | Where-Object { $_.window_quarters -and $_.target })
if ($Only.Count -gt 0) { $upd = @($upd | Where-Object { $Only -contains "$($_.name)" }) }
$tsu = @()
if ($fv.ts_dbs) { $tsu = @($fv.ts_dbs | ForEach-Object { $_ } | Where-Object { $_.update -and $_.update.window_quarters -and $_.update.db }) }
if ($Only.Count -gt 0) { $tsu = @($tsu | Where-Object { $Only -contains "$($_.update.db)" }) }
if ($upd.Count -eq 0 -and $tsu.Count -eq 0) { Write-Host "[fund-upd] no update DB selected"; exit 3 }
$t0 = Get-Date
Write-Host ("[fund-upd] start {0} | {1}" -f $t0.ToString('yyyy-MM-dd HH:mm:ss'), ((@($upd | ForEach-Object { $_.name }) + @($tsu | ForEach-Object { $_.update.db })) -join ','))
$script:failed = @(); $script:refused = @(); $script:stopped = $false
# rc 3 / 4 from a Quantiwise step = session / busy / precondition -> stop the whole run
# 2026-11-10 (audit lane A, P7): the stop line names the cause of THIS rc only. The 11-09 log printed
#   'rc=1 - stop (4 = kicked: re-login ...)' for a CompInfo empty-sheet failure, which pointed the reader at the session.
function Step-Why([int]$rc) { switch ($rc) { 3 { 'precondition / busy / no live session' } 4 { 'session kicked by another login - re-login via qw_refresh.ps1, then re-run' } default { "rc $rc" } } }
function Step-Stop([string]$name, [string]$step, [int]$rc) { Write-Host "[fund-upd] $name $step rc=$rc - stop the run ($(Step-Why $rc))"; $script:stopped = $true }
function Step-Fail([string]$name, [string]$step, [int]$rc) { Write-Host "[fund-upd] $name $step rc=$rc - this DB failed; continue with the others"; $script:failed += $name }
# 2026-11-13: re-login on kicks, no limit (see header). Invoke-Relogin parses the -LoginOnly END line (alive / logins_ok).
$KICK_STALL = if ($env:QVEST_QW_KICK_STALL) { [int]$env:QVEST_QW_KICK_STALL } else { 30 }
function Invoke-Relogin {
  $out = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_refresh.ps1") -LoginOnly 2>&1 | ForEach-Object { "$_" })
  $end = @($out | Where-Object { $_ -match 'LOGIN-ONLY END' }) | Select-Object -Last 1
  Write-Host "[fund-upd] re-login: $end"
  $lok = 0; if ("$end" -match 'logins_ok=(\d+)') { $lok = [int]$Matches[1] }
  return [pscustomobject]@{ alive = ("$end" -match 'alive=True'); logins_ok = $lok }
}
function Invoke-QwStep([scriptblock]$Step, [string]$name, [string]$label) {
  $kicks = 0
  while ($true) {
    & $Step | Out-Host; $src = $LASTEXITCODE   # child output -> host (else it becomes part of the return value)
    if ($src -ne 4) { return $src }
    do {
      $kicks++
      if ($KICK_STALL -gt 0 -and $kicks -ge $KICK_STALL) { Write-Host "[fund-upd] $name $label kicked $kicks times - runaway guard (QVEST_QW_KICK_STALL=$KICK_STALL)"; return 4 }
      Write-Host "[fund-upd] $name $label kicked (#$kicks) -> re-login and re-run (no limit - Dohoon 11-13)"
      $r = Invoke-Relogin
      if (-not $r.alive -and $r.logins_ok -eq 0) { Write-Host "[fund-upd] $name re-login failed (no successful login) - stop"; return 3 }
    } while (-not $r.alive)
  }
}

foreach ($d in $upd) {
  if ($script:stopped) { break }
  $name = "$($d.name)"
  $book = Join-Path $fvDir "$($d.file)"
  if ($WhatIf) { Write-Host "[fund-upd] $name -> build -Force, dk-sync, peer refresh, ingest (WhatIf)"; continue }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_fundamental_book.ps1") -Mode build -Db $name -Force
  $rc = $LASTEXITCODE
  if ($rc -eq 3) { Step-Stop $name 'build' $rc; break } elseif ($rc -ne 0) { Step-Fail $name 'build' $rc; continue }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_datakey_sync.ps1") -Only $name
  $rc = $LASTEXITCODE
  if ($rc -eq 3) { Step-Stop $name 'dk-sync' $rc; break } elseif ($rc -ne 0) { Step-Fail $name 'dk-sync' $rc; continue }
  $rc = Invoke-QwStep { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_peer_refresh.ps1") -Book $book } $name 'refresh'
  if ($rc -eq 3 -or $rc -eq 4) { Step-Stop $name 'refresh' $rc; break } elseif ($rc -ne 0) { Step-Fail $name 'refresh' $rc; continue }
  & $PY -X utf8 (Join-Path $ROOT "02_Infrastructure\data\qw_fund_v2_ingest.py") --db $name
  $rc = $LASTEXITCODE
  if ($rc -eq 3) { Write-Host "[fund-upd] $name ingest refused (gate) - this DB not loaded; continue"; $script:refused += $name }
  elseif ($rc -ne 0 -and $rc -ne 2) { Step-Fail $name 'ingest' $rc }
}

foreach ($t in $tsu) {
  if ($script:stopped) { break }
  $name = "$($t.update.db)"
  $full = Join-Path $fvDir "$($t.file)"
  $ubook = Join-Path $fvDir "$($t.update.file)"
  $wq = [int]$t.update.window_quarters
  if ($WhatIf) { Write-Host "[fund-upd] $name -> dk-sync $($t.name), qw_fund_v2_tax_ts.ps1 -WindowQuarters $wq -> $ubook, tax ingest --window (WhatIf)"; continue }
  if (-not (Test-Path -LiteralPath $full)) { Step-Fail $name 'template' 1; Write-Host "  full book missing: $full (run the full collection first)"; continue }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_datakey_sync.ps1") -Only "$($t.name)"
  $rc = $LASTEXITCODE
  if ($rc -eq 3) { Step-Stop $name 'dk-sync' $rc; break } elseif ($rc -ne 0) { Step-Fail $name 'dk-sync' $rc; continue }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $OPS "qw_fund_v2_tax_ts.ps1") -Template $full -Out $ubook -WindowQuarters $wq
  $rc = $LASTEXITCODE
  if ($rc -eq 3 -or $rc -eq 4) { Step-Stop $name 'collect' $rc; break } elseif ($rc -ne 0) { Step-Fail $name 'collect' $rc; continue }
  & $PY -X utf8 (Join-Path $ROOT "02_Infrastructure\data\qw_fund_v2_tax_ingest.py") --root $ROOT --window --book $ubook
  $rc = $LASTEXITCODE
  if ($rc -eq 3) { Write-Host "[fund-upd] $name ingest refused (gate) - not loaded"; $script:refused += $name }
  elseif ($rc -ne 0) { Step-Fail $name 'ingest' $rc }
}

$code = if ($script:failed.Count -gt 0) { 1 } elseif ($script:stopped -or $script:refused.Count -gt 0) { 3 } else { 0 }
Write-Host ("[fund-upd] END {0} | {1:n0}s | failed [{2}] refused [{3}] stopped {4} -> rc {5}" -f (Get-Date -Format HH:mm:ss), ((Get-Date) - $t0).TotalSeconds, ($script:failed -join ','), ($script:refused -join ','), $script:stopped, $code)
exit $code
