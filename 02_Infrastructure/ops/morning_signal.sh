#!/bin/bash
# Morning Signal Generator — 새벽 실행용
# MRS 최신화 + STR_1631 3월 시그널 생성

source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT"

echo "=== Morning Signal $(date) ==="

# Step 1: FRED 데이터 갱신 (MRS용)
echo "[1/3] FRED MRS 갱신..."
Rscript --no-save -e '
source("02_Infrastructure/config.R")
source("02_Infrastructure/regime_engine_daily.R")
library(data.table); library(arrow)
BM_DT <- as.data.table(read_parquet(".cache/benchmark.parquet"))
REGIME <- build_daily_regime(BM_DT$Date)
write_parquet(REGIME, ".cache/regime_daily_v2.parquet")
lr <- REGIME[Date == max(Date)]
cat(sprintf("MRS (%s): %.2f → %s\n", lr$Date, lr$MRS,
    ifelse(lr$MRS < 30, "NORMAL", ifelse(lr$MRS < 60, "CAUTION", "CRISIS"))))
'

# Step 2: STR_1631 3월 시그널 생성
echo "[2/3] STR_1631 시그널 생성..."
Rscript --no-save -e '
PROJECT_ROOT <- getwd()
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
SCRIPT_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631_v5")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
if (!"Name" %in% names(RAWDATA)) RAWDATA[, Name := NA_character_]
if (!"Sector" %in% names(RAWDATA)) RAWDATA[, Sector := NA_character_]
source(file.path(SCRIPT_DIR, "factor_engine.R"))
latest <- FACTORS[Date == max(Date)]
setorder(latest, -Score)

# Regime
REGIME <- as.data.table(read_parquet(".cache/regime_daily_v2.parquet"))
lr <- REGIME[Date == max(Date)]
mrs <- lr$MRS

cat(sprintf("\n=== STR_1631 투자 시그널 (%s) ===\n", max(FACTORS$Date)))
cat(sprintf("Regime: MRS=%.2f → %s\n\n", mrs,
    ifelse(mrs < 30, "NORMAL (100%% 팩터)", 
    ifelse(mrs < 60, sprintf("CAUTION (팩터 %.0f%% + 현금 %.0f%%)", 
           (1-0.5*(mrs-30)/30)*100, (0.5*(mrs-30)/30)*100), 
           "CRISIS (팩터 50%% + 인버스 20%% + 현금 30%%)"))))

for (i in 1:nrow(latest)) {
  w <- 5.0
  if (mrs >= 30 && mrs < 60) w <- w * (1 - 0.5*(mrs-30)/30)
  if (mrs >= 60) w <- 2.5
  cat(sprintf("  %2d. %s  Score: %.2f  비중: %.1f%%\n", i, latest$Ticker[i], latest$Score[i], w))
}

if (mrs >= 60) {
  cat(sprintf("\n  인버스 ETF (114800): 20%%\n"))
  cat(sprintf("  현금: 30%%\n"))
} else if (mrs >= 30) {
  cash_pct <- 0.5*(mrs-30)/30 * 100
  cat(sprintf("\n  현금: %.0f%%\n", cash_pct))
}
'

# Step 3: 텔레그램 발송
echo "[3/3] 텔레그램 발송..."
Rscript --no-save -e '
source("02_Infrastructure/telegram/telegram_notify.R")
tg_send("Morning Signal 생성 완료. 위 종목 확인 후 매수 진행.", parse_mode = "")
'

echo "=== Done ==="
