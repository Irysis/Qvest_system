suppressMessages({library(data.table);library(arrow);library(PerformanceAnalytics);library(xts)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
if(!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260813_006"
fwd <- readRDS(file.path(OUT,"fwd.rds")); A <- readRDS(file.path(OUT,"alpha_variants.rds"))$primary
RET <- fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]; BEN <- fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]
LIQ <- fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
vs <- sort(unique(RET$Date)); vs <- vs[vs < as.Date("2026-06-01")]
RET <- RET[Date %in% vs]; BEN <- BEN[Date %in% vs]; LIQ <- LIQ[Date %in% vs]
cs <- suppressWarnings(canonical_screen_bt(A[Date %in% vs], RET, BEN, top_n=25L, cost_bps_oneway=15,
                                           liq_dt=LIQ, liq_min=2e8, diag_dual_basis=FALSE))
pr <- as.data.table(cs$period_returns); x <- xts(pr$ret_net, order.by=as.Date(pr$date))
dd <- Drawdowns(x); i <- which.min(as.numeric(dd))
cat("MDD full window   :", as.numeric(maxDrawdown(x)), " trough:", as.character(index(x)[i]), "\n")
x2 <- x[index(x) >= as.Date("2015-07-01")]
cat("MDD clean subwindow:", as.numeric(maxDrawdown(x2)), " n:", length(x2), "\n")
o <- order(as.numeric(x))[1:5]
cat("worst 5 months:\n"); print(data.frame(date=as.character(index(x)[o]), ret=round(as.numeric(x)[o],4)))
