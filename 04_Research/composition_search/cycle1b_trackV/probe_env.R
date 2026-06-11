# probe_env.R - Track V pre-measurement environment probe (diagnostic only)
# 1) PerformanceAnalytics Return.portfolio weight-timing semantics (empirical)
# 2) b1 panel / lo_screen caches readability + factor coverage
# 3) contract build_benchmark_compare standalone source
suppressMessages({library(data.table); library(xts); library(PerformanceAnalytics); library(arrow)})
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
cat("=== 1) Return.portfolio alignment test ===\n")
# Case A (interleaved, b1-style): weights at month-end t, returns at month-end t+1
d_w <- as.Date(c("2020-01-31","2020-02-29","2020-03-31"))
d_r <- as.Date(c("2020-02-29","2020-03-31","2020-04-30"))
# asset A returns 10% only in Feb; asset B returns 5% only in Mar
R <- xts(matrix(c(0.10,0,0, 0,0.05,0), ncol=2, dimnames=list(NULL,c("A","B"))), order.by=d_r)
W <- xts(matrix(c(1,0,0, 0,1,0), ncol=2, dimnames=list(NULL,c("A","B"))), order.by=d_w)
pA <- Return.portfolio(R, weights=W)
cat("Case A (interleaved) port returns:\n"); print(data.table(date=index(pA), ret=as.numeric(pA)))
# expect: Feb=0.10 (w@Jan31 -> A), Mar=0.05 (w@Feb29 -> B) if weights apply to NEXT period
# Case B (same-grid, driver-style): weights and returns on identical dates
W2 <- xts(matrix(c(1,0,0, 0,1,0), ncol=2, dimnames=list(NULL,c("A","B"))), order.by=d_r)
pB <- tryCatch(Return.portfolio(R, weights=W2), error=function(e) e$message)
cat("Case B (same-grid) port returns:\n")
if (is.character(pB)) cat("ERROR:", pB, "\n") else print(data.table(date=index(pB), ret=as.numeric(pB)))

cat("\n=== 2) b1 panel ===\n")
pan <- as.data.table(read_parquet(file.path(PROJ,"04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
cat("rows:", nrow(pan), "| cols:", paste(names(pan), collapse=","), "\n")
pan[, Date := as.Date(Date)]
cat("dates:", as.character(min(pan$Date)), "~", as.character(max(pan$Date)), "| n_dates:", uniqueN(pan$Date), "\n")
cat("rows/date median:", median(pan[, .N, by=Date]$N), "| score_eff non-NA:", round(pan[, mean(!is.na(score_eff))],3), "\n")

cat("\n=== 3) lo_screen caches ===\n")
LO <- file.path(PROJ,"stage_artifacts/alpha_search/lo_screen")
FC <- readRDS(file.path(LO,"_factor_cache.rds"))
cat("factor cache rows:", nrow(FC), "| factors:", paste(sort(unique(FC$Factor_Name)), collapse=","), "\n")
cat("dates:", as.character(min(FC$Date)), "~", as.character(max(FC$Date)), "\n")
mep <- readRDS(file.path(LO,"_me_panel_cache.rds"))
cat("me_panel rows:", nrow(mep), "| cols:", paste(names(mep),collapse=","), "| dates:", as.character(min(mep$Date)), "~", as.character(max(mep$Date)), "\n")
mem <- readRDS(file.path(LO,"_universe_cache.rds"))
cat("universe rows:", nrow(mem), "| dates:", uniqueN(mem$Date), "\n")
bmc <- readRDS(file.path(LO,"_bm_cache.rds"))
cat("bm rows:", nrow(bmc), "| dates:", as.character(min(bmc$Date)), "~", as.character(max(bmc$Date)), "\n")

cat("\n=== 4) contract standalone source ===\n")
source(file.path(PROJ,"02_Infrastructure/contracts/backtest_result_contract.R"))
cat("build_benchmark_compare exists:", exists("build_benchmark_compare"), "\n")
cat("\n=== 5) RAWDATA cache file ===\n")
rc <- file.path(PROJ,".cache","RAWDATA.parquet")
cat("RAWDATA.parquet exists:", file.exists(rc), "| size MB:", round(file.size(rc)/1e6,1), "\n")
cat("PROBE DONE\n")
