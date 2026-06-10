# =============================================================================
# run_lo_batch.ps1 — long-only top25 단일 factor 스크리닝 batch (캐시 기반, OOM-free)
# =============================================================================
# 전제: 02_Infrastructure/alpha_search/build_lo_factor_cache.R 선행 실행으로
#   stage_artifacts/alpha_search/lo_screen/_factor_cache.rds 생성됨(parquet read 0회).
# 각 factor = 독립 Rscript 프로세스(메모리 격리) + 캐시 슬라이스 → 매우 가벼움.
# arrow 안전(PowerShell 경유). -f 금지(PowerShell -e source).
# =============================================================================
$ErrorActionPreference = "Continue"
$env:CLAUDE_PROJECT_DIR = "C:\Users\99922\OneDrive\Quant_Module_Moltbot"
$env:PYTHONUTF8 = "1"
Set-Location "C:\Users\99922\OneDrive\Quant_Module_Moltbot"
$RS = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
$driver = "stage_artifacts/alpha_search/driver_lo_screen.R"
$logDir = "stage_artifacts\alpha_search\lo_screen"
$batchLog = Join-Path $logDir "_lo_batch_run.log"

# BATCH 2 (2026-06-06): D/R/M/Q 38종 — _verify_factors_batch2.R로 실재(0 missing) 확인.
# batch 1(CR/V/AC/IN/C 23종) 완주 → 제외.
$factors = @(
  "D01_IdioVol","D04_Downside_Beta","D05_MaxRet","D16_Coskewness","D17_Cokurtosis",
  "D25_Left_Tail_Beta","D43_Skewness","D44_Kurtosis","D45_Downside_Dev","D46_Sortino",
  "D50_MaxDrawdown","D51_Ulcer_Index",
  "R03_CVaR_95","R05_Tail_Risk","R07_Downside_Dev","R09_Coskewness","R10_Cokurtosis",
  "R13_NCSKEW","R14_DUVOL","R15_Sortino","R16_Calmar","R19_Composite_Risk",
  "M02_Mom_6_1","M03_Mom_3_1","M10_Intermediate_Mom","M13_VolAdj_Mom","M14_RiskAdj_Mom",
  "M16_Trend_Factor","M22_Max_Return","M23_Acceleration",
  "Q05_Accrual","Q09_CFOA","Q12_Asset_Turnover","Q17_ROIC","Q23_Sustainable_Growth",
  "Q28_Cash_Conversion","Q33_Earnings_Persistence","Q35_CashBased_OpProf"
)

"=== LO batch start $(Get-Date -Format o) | $($factors.Count) factors (cache-based) ===" | Out-File -FilePath $batchLog -Encoding utf8

$n = $factors.Count
for ($i = 0; $i -lt $n; $i++) {
  $f = $factors[$i]
  $tag = ($f -split '_')[0]
  $env:FACTOR_NAME = $f
  $env:STRAT_TAG = $tag
  $msg = "[$($i+1)/$n] $f start $(Get-Date -Format HH:mm:ss)"
  Write-Host $msg
  $msg | Out-File -FilePath $batchLog -Append -Encoding utf8
  $outFile = Join-Path $logDir "_run_$tag.out"
  & $RS -e "source('$driver')" *> $outFile
  $done = Get-Content $outFile | Select-String -Pattern "LO-DONE|cache HIT|Error|stop" | Select-Object -Last 3
  $done | ForEach-Object { $_.Line | Out-File -FilePath $batchLog -Append -Encoding utf8 }
  $done | ForEach-Object { Write-Host "    $($_.Line)" }
}
"=== LO batch DONE $(Get-Date -Format o) ===" | Out-File -FilePath $batchLog -Append -Encoding utf8
Write-Host "=== batch complete ==="
