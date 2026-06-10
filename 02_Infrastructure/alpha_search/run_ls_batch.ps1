# run_ls_batch.ps1 — 9 직교후보 factor long-short 스크리닝 순차 batch (1 run씩, RAM 보호)
#   ★ SIMPLIFIED driver (value_bm 상관 제거) 사용. AC07은 smoke로 이미 완료(JSON 있으면 skip).
$env:CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
$env:PYTHONUTF8 = "1"
$RS = "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
$DRIVER = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/driver_ls_generic.R"
$LOGDIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search/ls_screen"
New-Item -ItemType Directory -Force -Path $LOGDIR | Out-Null

# (Factor_Name, Strat_Name) — 학술 이상현상 직교 후보
$factors = @(
  @("AC07_Operating_Accruals",  "LS_AC07_Accruals_Sloan1996"),
  @("AC05_NOA",                 "LS_AC05_NOA_Hirshleifer2004"),
  @("AC18_Accrual_Quality",     "LS_AC18_AccrualQuality_Francis2005"),
  @("IN04_Net_Equity_Issuance", "LS_IN04_NetIssuance"),
  @("IN06_Investment_to_Assets","LS_IN06_InvToAssets_FF_CMA"),
  @("GR03_Asset_Growth",        "LS_GR03_AssetGrowth_Cooper2008"),
  @("L01_Amihud",               "LS_L01_Amihud2002"),
  @("V11_Shareholder_Yield",    "LS_V11_ShareholderYield"),
  @("Q35_CashBased_OpProf",     "LS_Q35_CashOpProf_Ball2016")
)

foreach ($f in $factors) {
  $jsonPath = Join-Path $LOGDIR ($f[0] + ".json")
  if (Test-Path $jsonPath) {
    Write-Output ("[batch] SKIP  " + $f[0] + " (JSON exists)")
    continue
  }
  $env:FACTOR_NAME = $f[0]
  $env:STRAT_NAME  = $f[1]
  $log = Join-Path $LOGDIR ("run_" + $f[0] + ".log")
  Write-Output ("[batch] START " + $f[0] + " -> " + $log)
  & $RS -e "source('$DRIVER')" *> $log
  $tail = Get-Content $log -Tail 3 -Encoding Unicode
  Write-Output ("[batch] DONE  " + $f[0] + " exit=" + $LASTEXITCODE)
  $tail | ForEach-Object { Write-Output ("    " + $_) }
}
Write-Output "[batch] ALL DONE"
