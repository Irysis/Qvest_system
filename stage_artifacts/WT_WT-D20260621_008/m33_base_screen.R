suppressMessages({library(arrow); library(data.table)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
E <- readRDS("/tmp/m33_env.rds")
dt<-E$dt; sig_dates<-E$sig_dates; returns_dt<-E$returns_dt; bench_dt<-E$bench_dt; build_scores<-E$build_scores
environment(build_scores) <- environment()  # bind globals

# ---- BASE config: L=126, skip=21, lambda=0.5, top_n=20 ----
cat("=== Building BASE scores (L=126, skip=21, lambda=0.5) ===\n")
S_base <- build_scores(L=126L, skip=21L, lambda=0.5)
liq_dt <- S_base[, .(Date, Ticker, adv)]
scores_dt <- S_base[, .(Date, Ticker, score)]
cat("scores rows:", nrow(scores_dt), "avg names/month:", round(nrow(scores_dt)/length(unique(scores_dt$Date)),1),"\n")

res_base <- canonical_screen_bt(scores_dt, returns_dt, bench_dt, top_n=20L,
                                cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8,
                                run_id="M33_base", strategy_id="M33_OvernightMom_base")
cat("\n=== BASE (L126 skip21 lambda0.5 top20) ===\n")
cat("n_months:", res_base$n_months,"\n")
cat("PORT_t (NW lag3):", round(res_base$portfolio_alpha_t_nw_lag3,3),"\n")
cat("IR:", round(res_base$information_ratio,3),"\n")
cat("net_SR:", round(res_base$net_sr,3),"\n")
cat("alpha_annualized:", round(res_base$alpha_annualized,4),"\n")
cat("turnover_annual:", round(res_base$turnover_annual,2),"\n")
cat("mean_active_net (monthly):", round(res_base$mean_active_net,5),"\n")

saveRDS(list(res_base=res_base, S_base=S_base, scores_dt=scores_dt, liq_dt=liq_dt),
        "/tmp/m33_base.rds")

# ---- rank-IC / ICIR (ADVISORY) ----
ic_dt <- merge(scores_dt, returns_dt, by=c("Date","Ticker"))
ic_by_month <- ic_dt[, .(ic = cor(score, Ret_1m, method="spearman")), by=Date]
rank_ic <- mean(ic_by_month$ic, na.rm=TRUE)
icir <- rank_ic / sd(ic_by_month$ic, na.rm=TRUE)
# Harvey t (NW would be ideal; use simple t * harvey adj proxy = mean/se)
n_ic <- sum(!is.na(ic_by_month$ic))
ic_t <- rank_ic / (sd(ic_by_month$ic,na.rm=TRUE)/sqrt(n_ic))
cat("\n=== rank-IC diagnostics (ADVISORY) ===\n")
cat("rank_IC:", round(rank_ic,4)," ICIR:", round(icir,3)," IC_t:", round(ic_t,2)," n_months:", n_ic,"\n")
saveRDS(ic_by_month, "/tmp/m33_ic.rds")
