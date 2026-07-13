#==============================================================================
# WT-D20260713_002 R18 — Step 02: canonical dual-basis eval + placebo + Size-partial
#   + incrementality corr (F-A vs AC13ref, F-A vs F-B, vs Size). cap-w PORT_t authoritative.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_002")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))

pan <- readRDS(file.path(OUT,"panels.rds"))
returns_all<-pan$returns_all; bench_all<-pan$bench_all; size_all<-pan$size_all; liq_all<-pan$liq_all
IS_CUT <- as.Date("2019-01-01")

run_canon <- function(sc, tag, diag=TRUE){
  canonical_screen_bt(sc[, .(Date,Ticker,score)], returns_all, bench_all, top_n=25L,
    cost_bps_oneway=15, liq_dt=liq_all, liq_min=2e8, size_dt=size_all,
    diag_dual_basis=diag, run_id=paste0("r18_",tag), strategy_id=tag)
}
rank_ic <- function(sc){
  m <- merge(sc[,.(Date,Ticker,score)], returns_all, by=c("Date","Ticker"))
  ic <- m[, .(ic=suppressWarnings(cor(score, Ret_1m, method="spearman",use="complete.obs"))), by=Date][is.finite(ic)]
  list(mean_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), t=mean(ic$ic)/sd(ic$ic)*sqrt(nrow(ic)), n=nrow(ic))
}
placebo <- function(sc, tag, nsim=200L){
  base <- run_canon(sc, paste0(tag,"_base"), diag=FALSE)$portfolio_alpha_t_nw_lag3
  set.seed(18L); sims <- numeric(nsim)
  for(i in seq_len(nsim)){
    sh <- copy(sc); sh[, score := sample(score), by=Ticker]
    sims[i] <- tryCatch(run_canon(sh, paste0(tag,"_pb",i), diag=FALSE)$portfolio_alpha_t_nw_lag3, error=function(e) NA_real_)
  }
  sims<-sims[is.finite(sims)]
  list(base=base, p_value=mean(sims >= base), n=length(sims), sim_mean=mean(sims), sim_sd=sd(sims))
}
size_partial <- function(sc, tag){
  m <- merge(sc[,.(Date,Ticker,score)], size_all, by=c("Date","Ticker"))
  m[, sc_resid := { if(.N>=5 && is.finite(sd(Size)) && sd(Size)>0){ residuals(lm(score~Size)) } else score }, by=Date]
  run_canon(m[,.(Date,Ticker,score=sc_resid)], paste0(tag,"_szpartial"))
}
calmar_from_pr <- function(pr){
  if(is.null(pr)||nrow(pr)<12) return(NA_real_)
  r<-pr$ret_net; nav<-cumprod(1+r); dd<-nav/cummax(nav)-1; mdd<- -min(dd)
  cagr<-prod(1+r)^(12/length(r))-1; if(mdd<=0) return(NA_real_); cagr/mdd
}
# cross-sectional monthly corr between two score panels (mean spearman)
xcorr <- function(a, b){
  m <- merge(a[,.(Date,Ticker,sa=score)], b[,.(Date,Ticker,sb=score)], by=c("Date","Ticker"))
  cc <- m[, .(c=suppressWarnings(cor(sa,sb,method="spearman",use="complete.obs"))), by=Date][is.finite(c)]
  list(mean=mean(cc$c), sd=sd(cc$c), n=nrow(cc))
}

eval_one <- function(fname, tag){
  sc <- as.data.table(read_parquet(file.path(OUT,fname)))
  cf <- run_canon(sc, paste0(tag,"_full"))
  ci <- run_canon(sc[Date <  IS_CUT], paste0(tag,"_IS"))
  co <- run_canon(sc[Date >= IS_CUT], paste0(tag,"_OOS"))
  ric<- rank_ic(sc); szp<- size_partial(sc, tag); pb <- placebo(sc, tag, nsim=200L)
  dt <- cf$diag_cap_tier; ew <- cf$diag_ew_universe
  list(tag=tag, n_months=cf$n_months, port_t_full=cf$portfolio_alpha_t_nw_lag3, port_p=cf$portfolio_alpha_t_pvalue,
    ir=cf$information_ratio, net_sr=cf$net_sr, turnover=cf$turnover_annual, calmar=calmar_from_pr(cf$period_returns),
    port_t_IS=ci$portfolio_alpha_t_nw_lag3, port_t_OOS=co$portfolio_alpha_t_nw_lag3,
    ew_t=ew$portfolio_alpha_t_nw_lag3, ew_post2017_t=ew$post2017_t_nw_lag3, ew_oos_ret=ew$oos_retention_approx,
    mega_w=if(!is.null(dt$weight_share_avg)) dt$weight_share_avg$MEGA else NA,
    mid_w =if(!is.null(dt$weight_share_avg)) dt$weight_share_avg$MID else NA,
    other_w=if(!is.null(dt$weight_share_avg)) dt$weight_share_avg$OTHER else NA,
    rank_ic=ric$mean_ic, icir=ric$icir, ric_t=ric$t, ric_n=ric$n,
    szpartial_port_t=szp$portfolio_alpha_t_nw_lag3, szpartial_ew_t=szp$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    placebo_p=pb$p_value, placebo_base=pb$base, placebo_sim_mean=pb$sim_mean, placebo_n=pb$n)
}

FA<-as.data.table(read_parquet(file.path(OUT,"scores_FA.parquet")))
FB<-as.data.table(read_parquet(file.path(OUT,"scores_FB.parquet")))
AC<-as.data.table(read_parquet(file.path(OUT,"scores_AC13ref.parquet")))
size_sc <- size_all[, .(Date,Ticker,score=Size)]

res <- list(FA=eval_one("scores_FA.parquet","FA"), FB=eval_one("scores_FB.parquet","FB"))

# incrementality
inc <- list(
  FA_vs_AC13ref = xcorr(FA, AC),      # modified vs original Jones (redundancy)
  FA_vs_FB      = xcorr(FA, FB),
  FA_vs_Size    = xcorr(FA, size_sc),
  FB_vs_Size    = xcorr(FB, size_sc)
)
res$incrementality <- inc
saveRDS(res, file.path(OUT,"canon_results.rds"))

cat("\n===== R18 canonical dual-basis summary (cap-w authoritative) =====\n")
tab <- rbindlist(lapply(res[c("FA","FB")], function(r) as.data.table(r[c("tag","n_months","port_t_full","port_t_IS","port_t_OOS",
  "ew_t","ew_post2017_t","ew_oos_ret","mega_w","mid_w","other_w","rank_ic","ric_t","szpartial_port_t",
  "placebo_p","net_sr","calmar","turnover")])), fill=TRUE)
print(tab, digits=3)
cat("\n--- incrementality (cross-sectional monthly spearman, mean) ---\n")
for(nm in names(inc)) cat(sprintf("  %-16s mean=%.3f sd=%.3f n=%d\n", nm, inc[[nm]]$mean, inc[[nm]]$sd, inc[[nm]]$n))
# DSR sweep note (n_trials=2)
tvec<-c(res$FA$port_t_full,res$FB$port_t_full); best<-which.max(tvec)
e_max <- (1-0.5772)*qnorm(1-1/2) + 0.5772*qnorm(1-1/(2*exp(1)))
cat(sprintf("\nbest cap-w PORT_t: %s t=%.2f | DSR sweep n_trials=2 E[max_2 z]=%.3f\n",
    c("FA","FB")[best], tvec[best], e_max))
fwrite(tab, file.path(OUT,"canon_summary.csv"))
cat("[02] DONE\n")
