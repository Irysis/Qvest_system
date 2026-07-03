suppressMessages({library(arrow); library(data.table)})
setDTthreads(1L)
B <- readRDS("/tmp/m33_base.rds")
E <- readRDS("/tmp/m33_env.rds")
returns_dt <- E$returns_dt; bench_dt <- E$bench_dt
scores_dt <- B$scores_dt

# decile analysis: per Date, decile by score, EW return, vs BM
dd <- merge(scores_dt, returns_dt, by=c("Date","Ticker"))
dd <- merge(dd, bench_dt, by="Date")
dd[, dec := cut(frank(score)/.N, breaks=seq(0,1,.1), labels=1:10, include.lowest=TRUE), by=Date]
# mean active return per decile per month, then average
dec_perf <- dd[, .(ew_ret=mean(Ret_1m), bm=mean(BM_Ret), .N), by=.(Date,dec)]
dec_perf[, active := ew_ret - bm]
dec_summary <- dec_perf[, .(mean_active=mean(active), sd_active=sd(active), n_m=.N), by=dec][order(dec)]
dec_summary[, t_active := mean_active/(sd_active/sqrt(n_m))]
cat("=== DECILE ANALYSIS (active return = EW decile - BM, monthly) ===\n")
print(dec_summary)

# spread D10-D1 and D10-D9
d10 <- dec_summary[dec==10, mean_active]; d1<-dec_summary[dec==1,mean_active]; d9<-dec_summary[dec==9,mean_active]
cat("\nD10-D1 spread (monthly):", round(d10-d1,5), "\n")
cat("D10-D9 gap (monthly):", round(d10-d9,5), "\n")
cat("Top-decile (D10) active t-stat:", round(dec_summary[dec==10,t_active],3), "\n")
cat("Bottom-decile (D1) active t-stat:", round(dec_summary[dec==1,t_active],3), "\n")

# long-short D10-D1 spread t-stat (per-month spread)
ls <- merge(dec_perf[dec==10,.(Date,a10=active)], dec_perf[dec==1,.(Date,a1=active)], by="Date")
ls[, spread:=a10-a1]
cat("L/S D10-D1 spread mean:", round(mean(ls$spread),5)," t:", round(mean(ls$spread)/(sd(ls$spread)/sqrt(nrow(ls))),3),"\n")
cat("(NOTE: L/S not tradeable - KR long-only; diagnostic only)\n")
