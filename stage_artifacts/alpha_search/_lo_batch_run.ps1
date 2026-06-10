# Long-only screen batch runner — one fresh Rscript per factor (OOM-safe, sequential)
$env:CLAUDE_PROJECT_DIR='G:/Quant_Module_Moltbot'
$env:PYTHONUTF8='1'
$RS='C:/Program Files/R/R-4.5.2/bin/Rscript.exe'
$DRIVER='G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/driver_lo_screen.R'
$LOG='G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/lo_screen/_batch.log'
$factors = @(
  'CR02_Volume_Concentration','CR03_Herding_Dispersion','CR04_Ownership_Concentration',
  'CR05_Short_Pressure_Proxy','CR06_DTC_Proxy','CR07_Momentum_Crowding',
  'CR08_Volume_Price_Divergence','CR09_Money_Flow_Ratio','CR10_Convergence_Premium',
  'CR11_Idiosyncratic_Return',
  'V10_FCF_Yield','V15_NetDebt_Adj_EP','V17_Payout_Ratio','V19_Debt_to_Market','V21_Composite_Equity_Issuance',
  'AC09_NNI','AC13_Abnormal_Accruals','AC24_NOA_Growth',
  'IN01_CapEx_to_Assets','IN02_CapEx_to_Revenue','IN05_Net_Debt_Issuance',
  'XF_DU02_AssetTurnover','XF_LL01_DebtToCapital','XF_PR05_EBITDA_to_Assets',
  'C16_EPS_Acceleration','C19_Composite_Earnings'
)
"=== LO batch start $(Get-Date -Format o) | $($factors.Count) factors ===" | Out-File $LOG -Encoding utf8
$i = 0
foreach ($f in $factors) {
  $i++
  $env:FACTOR_NAME = $f
  $outjson = "G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/lo_screen/$f.json"
  "[$i/$($factors.Count)] $f start $(Get-Date -Format HH:mm:ss)" | Tee-Object -FilePath $LOG -Append
  $res = & $RS -e "source('$DRIVER')" 2>&1
  $done = $res | Select-String -Pattern 'LO-DONE'
  if ($done) { "$($done.Line.Trim())" | Tee-Object -FilePath $LOG -Append }
  if (-not (Test-Path $outjson)) {
    # retry once on non-deterministic death / no json
    "  [retry] $f (no json on 1st)" | Tee-Object -FilePath $LOG -Append
    $res2 = & $RS -e "source('$DRIVER')" 2>&1
    $done2 = $res2 | Select-String -Pattern 'LO-DONE'
    if ($done2) { "$($done2.Line.Trim())" | Tee-Object -FilePath $LOG -Append }
    if (-not (Test-Path $outjson)) {
      "  [FAIL] $f no json after retry. tail:" | Tee-Object -FilePath $LOG -Append
      ($res2 | Select-Object -Last 8) -join "`n" | Out-File $LOG -Append -Encoding utf8
    }
  }
}
"=== LO batch done $(Get-Date -Format o) ===" | Tee-Object -FilePath $LOG -Append
