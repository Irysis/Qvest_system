## _r6_bench_parity.R — R6 Step1 벤치: 2팩터 canonical_screen_bt 타이밍 + z==Z_Score_Aligned provenance parity
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
if (!exists("load_month_factors")) source("02_Infrastructure/factor_db/factor_db_connector.R")

OUT <- "outputs/ramp"
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
approved <- af[status=="approved", factor_id]
cat("approved[1:8]:", paste(head(approved,8), collapse=", "), "\n")
## pick 2 approved factors that exist in pure_factor_scores with cross-sectional variation
test_fids <- head(approved, 2)
cat("test factors:", paste(test_fids, collapse=", "), "\n")

## rawdata slim (R4 패턴)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]

## sig_dates from factor_group_scores
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet"), col_select=c("signal_date")))
sig_dates <- sort(unique(as.Date(g$signal_date))); n_sig <- length(sig_dates)
cat("n_sig:", n_sig, " range:", as.character(sig_dates[1]), "~", as.character(sig_dates[n_sig]), "\n")

## slim rawdata to month-end trading days (R4 pattern)
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
  if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
t0 <- Sys.time()
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
cat(sprintf("build_monthly_forward_returns: %.1fs | returns_dt rows=%d bench rows=%d\n",
    as.numeric(Sys.time()-t0,units="secs"), nrow(fwd$returns_dt), nrow(fwd$bench_dt)))

## load pure_factor_scores z for test factors
t1 <- Sys.time()
sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"),
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% test_fids]
cat(sprintf("pure z load+filter (2 fac): %.1fs rows=%d\n", as.numeric(Sys.time()-t1,units="secs"), nrow(sc)))

## per-factor canonical_screen_bt timing
for(fid in test_fids){
  s <- sc[factor_id==fid, .(Date=as.Date(signal_date), Ticker=security_id, score=z)][!is.na(score)]
  tt <- Sys.time()
  cs <- canonical_screen_bt(s, fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],
        fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)], top_n=25L, cost_bps_oneway=15,
        liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)], liq_min=2e8,
        run_id="r6bench", strategy_id=fid, diag_dual_basis=FALSE)
  el <- as.numeric(Sys.time()-tt, units="secs")
  pr <- as.data.table(cs$period_returns)
  cat(sprintf("  [%s] %.2fs n_months=%d PORT_t_capw=%.3f net_sr=%.3f TO=%.2f\n",
      fid, el, cs$n_months, cs$portfolio_alpha_t_nw_lag3, cs$net_sr, cs$turnover_annual))
}

## provenance parity: pure z vs load_month_factors Z_Score_Aligned (1 factor, 3 months)
cat("\n=== provenance parity: pure_factor_scores z vs load_month_factors Z_Score_Aligned ===\n")
fid <- test_fids[1]
chk_dates <- sig_dates[c(50, 150, 250)]
for(cd in as.character(chk_dates)){
  lm <- tryCatch(load_month_factors(as.Date(cd), factor_names=fid), error=function(e) NULL)
  if(is.null(lm)||nrow(lm)==0){ cat(sprintf("  %s: load_month_factors empty\n", cd)); next }
  lm <- as.data.table(lm)[Factor_Name==fid, .(security_id=Ticker, zdb=Z_Score_Aligned)]
  pz <- sc[factor_id==fid & signal_date==as.Date(cd), .(security_id, zp=z)]
  m <- merge(lm, pz, by="security_id")
  if(nrow(m)==0){ cat(sprintf("  %s: no overlap\n", cd)); next }
  mad <- max(abs(m$zdb - m$zp), na.rm=TRUE); cc <- cor(m$zdb, m$zp, use="complete.obs")
  cat(sprintf("  %s: n=%d max|Δ|=%.2e cor=%.4f\n", cd, nrow(m), mad, cc))
}
cat("\nBENCH_DONE\n")
