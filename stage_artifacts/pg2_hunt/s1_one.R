suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds")
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
inc <- bm_load_incumbent()
cat("incumbent rows:", nrow(inc), " range:", as.character(min(inc$date)), as.character(max(inc$date)), "\n")
f <- "M04_Mom_1"
S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
cat("panel rows:", nrow(S), " months:", uniqueN(S$Date), "\n")
r <- suppressWarnings(canonical_screen_bt(S, ret, as.data.table(M$bench), top_n = 25L,
      cost_bps_oneway = 15, liq_dt = as.data.table(M$liq), liq_min = 2e8,
      run_id = f, strategy_id = f, diag_dual_basis = FALSE,
      size_dt = as.data.table(M$size_dt)))
cat("r names:", paste(names(r), collapse=","), "\n")
PR <- as.data.table(r$period_returns)
cat("PR cols:", paste(names(PR), collapse=","), " rows:", nrow(PR), "\n")
print(head(PR,3)); print(tail(PR,2))
sw1 <- bm_delta_ir_sweep(PR[, .(date, ret_net)])
print(sw1)
o <- bm_delta_ir(PR[, .(date, ret_net)], weight=0.20, incumbent=inc)
cat("sleeve IR:", o$sleeve_standalone_ir, " cor:", o$correlation_with_incumbent, " n:", o$n_overlap, "\n")
Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]
X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by="date")
cat("parked merge rows:", nrow(X), "\n")
X[, sw := c(0L, abs(diff(as.integer(regime))))]
X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
sw2 <- bm_delta_ir_sweep(X[, .(date, ret_net = r2)], require_overlap = 60L)
print(sw2)
o2 <- bm_delta_ir(X[, .(date, ret_net=r2)], weight=0.20, incumbent=inc, require_overlap=60L)
cat("parked sleeve IR:", o2$sleeve_standalone_ir, " cor:", o2$correlation_with_incumbent, " n:", o2$n_overlap, "\n")
