# diag_deeper.R — deeper diagnostics: signal distribution, clean decile (nonzero), split-adj impact,
#                  large-cap where signal is ACTIVE (nonzero issuance), robustness of small-cap concentration.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
PAN <- file.path(ROOT, "stage_artifacts/WT-D20260706_009/panel")
sc   <- as.data.table(read_parquet(file.path(PAN, "nsi_scores_monthly.parquet")))
rets <- as.data.table(read_parquet(file.path(PAN, "returns_monthly.parquet")))
bm_cw<- as.data.table(read_parquet(file.path(PAN, "benchmark_capw.parquet")))
bm_ew<- as.data.table(read_parquet(file.path(PAN, "benchmark_ew.parquet")))
univ <- as.data.table(read_parquet(file.path(PAN, "universe_flags.parquet")))
START<- as.Date("2005-01-01")
sc<-sc[Date>=START]; rets<-rets[Date>=START]; bm_cw<-bm_cw[Date>=START]; bm_ew<-bm_ew[Date>=START]; univ<-univ[Date>=START]
liq <- univ[, .(Date, Ticker, adv=adv20)]

# ---- 1. signal distribution: how much is exactly zero? ----
cat("=== nsi_shares distribution (split-adjusted -Δlog shares) ===\n")
x <- sc$nsi_shares[is.finite(sc$nsi_shares)]
cat(sprintf("n=%d  exactly 0: %.1f%%  |x|<0.001: %.1f%%\n", length(x), 100*mean(x==0), 100*mean(abs(x)<0.001)))
print(quantile(x, c(.01,.05,.10,.25,.5,.75,.90,.95,.99), na.rm=TRUE))
cat(sprintf("frac RETIREMENT (x>0.001, shares shrinking): %.1f%%   frac ISSUANCE (x<-0.001): %.1f%%\n",
    100*mean(x>0.001), 100*mean(x < -0.001)))

# ---- 2. CLEAN long-short style: long names with real retirement vs real issuance ----
# monthly quintile of NON-ZERO signal only
cat("\n=== forward-return by ACTIVE issuance bucket (nonzero signal only) ===\n")
d <- merge(sc[is.finite(nsi_shares), .(Date,Ticker,s=nsi_shares,size_pctile)], rets, by=c("Date","Ticker"))
d[, bucket := fifelse(s>0.005,"RETIRE(long)", fifelse(s< -0.005,"ISSUE(avoid)","FLAT"))]
prof <- d[, .(mean_fwd=mean(Ret_1m,na.rm=TRUE), n=.N), by=bucket][order(bucket)]
print(prof)

# large-cap only version
cat("\n=== SAME but LARGE-CAP only (size_pctile>=0.60) ===\n")
prof_lc <- d[size_pctile>=0.60, .(mean_fwd=mean(Ret_1m,na.rm=TRUE), n=.N), by=bucket][order(bucket)]
print(prof_lc)

# ---- 3. Does RETIRE-only long (drop flat/issue) beat? top-25 among retirers, cap-w vs ew ----
sc[, retire_score := fifelse(nsi_shares>0.002, nsi_shares, NA_real_)]  # only real retirers eligible
run1 <- function(scoredt, scol, months, bench, label, top_n=25L, restrict_large=FALSE){
  s <- scoredt[Date %in% months & is.finite(get(scol))]
  if (restrict_large) s <- s[size_pctile>=0.60]
  s <- s[, .(Date,Ticker,score=get(scol))]
  r<-rets[Date%in%months]; b<-bench[Date%in%months]; l<-liq[Date%in%months]
  if(uniqueN(s$Date)<6) return(data.table(label=label,n_months=uniqueN(s$Date),port_t=NA,ir=NA,net_sr=NA))
  res<-canonical_screen_bt(s,r,b,top_n=top_n,cost_bps_oneway=15,liq_dt=l,liq_min=2e8,periods_per_year=12L,
                           run_id=label,strategy_id=label)
  data.table(label=label,n_months=res$n_months,port_t=round(res$portfolio_alpha_t_nw_lag3,3),
             ir=round(res$information_ratio,3),net_sr=round(res$net_sr,3),alpha_ann=round(res$alpha_annualized,4))
}
all_m<-sort(unique(sc$Date)); post17<-all_m[all_m>=as.Date("2017-01-01")]; valup<-all_m[all_m>=as.Date("2024-01-01")]
cat("\n=== RETIRERS-ONLY long top-25 (retire_score), both benches ===\n")
print(rbindlist(list(
  run1(sc,"retire_score",all_m, bm_cw,"RETIRE_FULL_capw"),
  run1(sc,"retire_score",all_m, bm_ew,"RETIRE_FULL_ew"),
  run1(sc,"retire_score",post17,bm_cw,"RETIRE_POST17_capw"),
  run1(sc,"retire_score",post17,bm_ew,"RETIRE_POST17_ew"),
  run1(sc,"retire_score",valup, bm_cw,"RETIRE_VALUP_capw"),
  run1(sc,"retire_score",valup, bm_ew,"RETIRE_VALUP_ew")
),fill=TRUE))

cat("\n=== RETIRERS-ONLY LARGE-CAP top-25, both benches ===\n")
print(rbindlist(list(
  run1(sc,"retire_score",all_m, bm_cw,"RET_LC_FULL_capw",restrict_large=TRUE),
  run1(sc,"retire_score",all_m, bm_ew,"RET_LC_FULL_ew",restrict_large=TRUE),
  run1(sc,"retire_score",post17,bm_cw,"RET_LC_POST17_capw",restrict_large=TRUE),
  run1(sc,"retire_score",post17,bm_ew,"RET_LC_POST17_ew",restrict_large=TRUE),
  run1(sc,"retire_score",valup, bm_cw,"RET_LC_VALUP_capw",restrict_large=TRUE)
),fill=TRUE))

# ---- 4. split-adjustment sanity: how many top-25 picks would be splits without adj? ----
cat("\n=== split-adjustment sanity: raw vs adjusted top-25 overlap ===\n")
sc[, r_adj := frank(-nsi_shares,ties.method="first"), by=Date]
sc[, r_raw := frank(-nsi_shares_raw,ties.method="first"), by=Date]
top_adj <- sc[r_adj<=25, .(Date,Ticker)]; top_raw <- sc[r_raw<=25, .(Date,Ticker)]
ov <- merge(top_adj, top_raw, by=c("Date","Ticker"))
cat(sprintf("top-25 overlap adj vs raw: %.1f%% (%d/%d)\n", 100*nrow(ov)/nrow(top_adj), nrow(ov), nrow(top_adj)))

cat("\n[diag] DONE\n")
