suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
A <- readRDS(file.path(OUT,"factor_long.rds")); M <- readRDS(file.path(OUT,"mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]
S <- A[Factor_Name=="D60_Leverage", .(Date, Ticker, score=z)]
cat("D60 패널: 행", nrow(S), "· 개월", uniqueN(S$Date), "·", as.character(min(S$Date)), "~", as.character(max(S$Date)), "\n")
r <- suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n=25L,
      cost_bps_oneway=15, liq_dt=as.data.table(M$liq), liq_min=2e8, run_id="d60",
      strategy_id="d60", diag_dual_basis=FALSE, size_dt=as.data.table(M$size_dt)))
PR <- as.data.table(r$period_returns)
cat("PR 개월", nrow(PR), "·", as.character(min(PR$date)), "~", as.character(max(PR$date)), "\n")
cat("PR 2019+ 개월:", nrow(PR[date>=as.Date("2019-11-01")]), "\n")
X <- merge(PR[,.(date,ret_net,benchmark_ret)], Mru[,.(date,regime)], by="date")
cat("regime merge 행:", nrow(X), "\n")
cat("regime dates 중 PR 에 없는 것:", sum(!Mru$date %in% PR$date), "\n")
print(head(sort(setdiff(as.character(Mru$date), as.character(PR$date))), 20))
cat("D60 패널 월별 종목수 (2019+ 일부):\n")
print(S[Date>=as.Date("2019-01-01"), .N, by=Date][order(Date)][1:15])
