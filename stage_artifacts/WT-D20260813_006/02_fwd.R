## WT-D20260813_006 / FQ-234 Lane B — forward return + benchmark + liquidity 패널 구축
## 실측-only: build_monthly_forward_returns (FQ-232 주입 경로 = 헌법 자 adv20_t1)
suppressMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")

cat("[fwd] load RAWDATA daily\n")
RAW <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet"),
        col_select = c("Date","Ticker","K200","KQ150","Close","Vol","Size")))
RAW[, Date := as.Date(Date)]
RAW <- RAW[Date >= as.Date("2000-01-01")]
RAW[, K200 := !is.na(K200) & K200 > 0]
RAW[, KQ150 := !is.na(KQ150) & KQ150 > 0]
RAW <- RAW[K200 | KQ150]
cat("[fwd] universe daily rows:", nrow(RAW), "\n")

## 신호일 = 각 캘린더월 시장 월말 거래일 (absorb 패널과 동일 축)
P <- as.data.table(read_parquet(file.path(OUT, "absorb_panel.parquet")))
P[, Date := as.Date(Date)]
ME <- sort(unique(P$Date))
cat("[fwd] sig dates:", length(ME), range(as.character(ME)), "\n")

ADV20 <- build_adv20_t1(RAW[, .(Date, Ticker, Vol, Close)], at_dates = ME)
RAWME <- RAW[Date %in% ME]
rm(RAW); invisible(gc())

fwd <- build_monthly_forward_returns(RAWME, ME, liq_daily = ADV20)
cat("[fwd] liq_ruler =", fwd$liq_ruler, "/ source =", fwd$liq_ruler_source, "\n")
cat("[fwd] returns rows:", nrow(fwd$returns_dt), " months:", uniqueN(fwd$returns_dt$Date), "\n")
cat("[fwd] bench rows:", nrow(fwd$bench_dt), "\n")
saveRDS(fwd, file.path(OUT, "fwd.rds"))
cat("[fwd] saved\n")
