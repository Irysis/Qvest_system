# debug_three_screen.R — isolate why canonical_screen_bt returns error/n_months=0
suppressMessages({ library(data.table); library(arrow) })
source("02_Infrastructure/ramp/pure_factor_extraction.R")
source("02_Infrastructure/ramp/factor_validation.R")

rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet"))
sig_dates <- as.Date(c("2018-01-31","2018-02-28","2018-03-31","2018-04-30","2018-05-31","2018-06-30"))
pf <- extract_pure_factor(c("M01_Mom_12_1"), sig_dates, rawdata, verbose = FALSE)
fwd <- build_monthly_forward_returns(rawdata, sig_dates)

sc <- pf$scores[, .(Date=as.Date(signal_date), Ticker=security_id, score=neutralized_z)][!is.na(score)]
ret <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
bench <- fwd$bench_dt[, .(Date=as.Date(Date), BM_Ret)]
liq <- fwd$liq_dt[, .(Date=as.Date(Date), Ticker, adv)]

cat("sc dates:", paste(as.character(sort(unique(sc$Date))), collapse=","), "\n")
cat("ret dates:", paste(as.character(sort(unique(ret$Date))), collapse=","), "\n")
cat("bench dates:", paste(as.character(sort(unique(bench$Date))), collapse=","), "\n")
cat("date overlap sc∩ret:", length(intersect(sc$Date, ret$Date)), "\n")
cat("sc rows:", nrow(sc), " ret rows:", nrow(ret), " bench rows:", nrow(bench), "\n")
cat("sample sc:\n"); print(head(sc,3))
cat("sample ret:\n"); print(head(ret,3))
cat("sample bench:\n"); print(head(bench,3))

cat("\n=== direct canonical_screen_bt call (with tryCatch off) ===\n")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
res <- tryCatch(
  canonical_screen_bt(sc, ret, bench, top_n=20L, cost_bps_oneway=15, liq_dt=liq, liq_min=2e8),
  error=function(e){ cat("ERROR:", conditionMessage(e), "\n"); NULL})
if(!is.null(res)){ cat("metric_type:", res$metric_type, " n_months:", res$n_months, "\n"); str(res, max.level=1) }
