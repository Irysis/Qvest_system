# run_ls_batch.ps1 — per-factor foreground LS screening (fresh R process each, OOM-safe)
#   각 factor를 별도 fresh Rscript 프로세스로 1run씩(누적 메모리 회피).
#   기존 ls_screen/<F>.json 있으면 skip. 비결정 죽음(exit!=0 & JSON 미생성) 1회 재시도.
#   호출: powershell -File run_ls_batch.ps1 FAC1 FAC2 ...
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Factors)
$ErrorActionPreference = "Continue"
$PROJ = "G:/Quant_Module_Moltbot"
$RS   = "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
$DRV  = "$PROJ/02_Infrastructure/alpha_search/driver_ls_generic.R"
$OUT  = "$PROJ/stage_artifacts/alpha_search/ls_screen"
$env:CLAUDE_PROJECT_DIR = $PROJ
$env:PYTHONUTF8 = "1"
Set-Location $PROJ
New-Item -ItemType Directory -Force -Path $OUT | Out-Null

foreach ($f in $Factors) {
  $json = Join-Path $OUT "$f.json"
  if (Test-Path $json) { Write-Host "[batch] SKIP $f (JSON exists)"; continue }
  $env:FACTOR_NAME = $f
  $env:STRAT_NAME  = "LS_$f"
  $log = Join-Path $OUT "run_$f.log"
  $attempt = 0; $ok = $false
  while ($attempt -lt 2 -and -not $ok) {
    $attempt++
    Write-Host "[batch] START $f (attempt $attempt)"
    & $RS -e "source('$DRV')" *> $log
    if (Test-Path $json) {
      $ok = $true
      $r = Get-Content $json -Raw | ConvertFrom-Json
      Write-Host ("[batch] DONE  {0} | LS_SR={1} OOS_ret={2} C4_t={3} ortho={4}" -f `
        $f, $r.ls_sharpe, $r.oos_retention, $r.carhart4_alpha_t, $r.ortho_candidate_1st)
    } else {
      Write-Host "[batch] FAIL  $f (attempt $attempt, no JSON) — see $log tail:"
      Get-Content $log -Tail 6 -ErrorAction SilentlyContinue
    }
  }
  if (-not $ok) { Write-Host "[batch] GIVEUP $f after 2 attempts" }
}
Write-Host "[batch] === DONE ==="
