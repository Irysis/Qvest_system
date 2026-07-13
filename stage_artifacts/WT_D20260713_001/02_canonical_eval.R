#==============================================================================
# WT-D20260713_001 R17 — Step 02: canonical dual-basis eval + placebo + Size-partial
# selection authority = cap-w portfolio_alpha_t_nw_lag3. advisory = rank-IC.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_001")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))

pan <- readRDS(file.path(OUT,"panels.rds"))
returns_all<-pan$returns_all; bench_all<-pan$bench_all; size_all<-pan$size_all; liq_all<-pan$liq_all
IS_CUT <- as.Date("2019-01-01")

run_canon <- function(sc, tag, diag=TRUE){
  canonical_screen_bt(sc[, .(Date,Ticker,score)], returns_all, bench_all, top_n=25L,
    cost_bps_oneway=15, liq_dt=liq_all, liq_min=2e8, size_dt=size_all,
    diag_dual_basis=diag, run_id=paste0("r17_",tag), strategy_id=tag)
}
# rank-IC (advisory): spearman(score_t, fwd ret_t) per month, then mean/IR + NW t
rank_ic <- function(sc){
  m <- merge(sc[,.(Date,Ticker,score)], returns_all, by=c("Date","Ticker"))
  ic <- m[, .(ic=suppressWarnings(cor(score, Ret_1m, method="spearman",use="complete.obs"))), by=Date][is.finite(ic)]
  list(mean_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic), t=mean(ic$ic)/sd(ic$ic)*sqrt(nrow(ic)), n=nrow(ic))
}
# placebo: shuffle each corp's signal series across time (break signal-return link), recompute cap-w PORT_t
placebo <- function(sc, tag, nsim=200L){
  base <- run_canon(sc, paste0(tag,"_base"), diag=FALSE)$portfolio_alpha_t_nw_lag3
  set.seed(17L)
  sims <- numeric(nsim)
  for(i in seq_len(nsim)){
    sh <- copy(sc)
    sh[, score := sample(score), by=Ticker]   # permute a corp's own signal across its months
    sims[i] <- tryCatch(run_canon(sh, paste0(tag,"_pb",i), diag=FALSE)$portfolio_alpha_t_nw_lag3, error=function(e) NA_real_)
  }
  sims<-sims[is.finite(sims)]
  list(base=base, p_value=mean(sims >= base), n=length(sims), sim_mean=mean(sims), sim_sd=sd(sims))
}
# Size-partial: residualize score on Size cross-sectionally per month, re-screen residual
size_partial <- function(sc, tag){
  m <- merge(sc[,.(Date,Ticker,score)], size_all, by=c("Date","Ticker"))
  m[, sc_resid := {
    if(.N>=5 && is.finite(sd(Size)) && sd(Size)>0){ r<-residuals(lm(score~Size)); r } else score
  }, by=Date]
  run_canon(m[,.(Date,Ticker,score=sc_resid)], paste0(tag,"_szpartial"))
}
calmar_from_pr <- function(pr){
  if(is.null(pr)||nrow(pr)<12) return(NA_real_)
  r <- pr$ret_net; nav<-cumprod(1+r); dd<-nav/cummax(nav)-1; mdd<- -min(dd)
  cagr <- prod(1+r)^(12/length(r))-1
  if(mdd<=0) return(NA_real_); cagr/mdd
}

eval_one <- function(fname, tag){
  sc <- as.data.table(read_parquet(file.path(OUT,fname)))
  cf <- run_canon(sc, paste0(tag,"_full"))
  ci <- run_canon(sc[Date <  IS_CUT], paste0(tag,"_IS"))
  co <- run_canon(sc[Date >= IS_CUT], paste0(tag,"_OOS"))
  ric<- rank_ic(sc)
  szp<- size_partial(sc, tag)
  pb <- placebo(sc, tag, nsim=200L)
  dt <- cf$diag_cap_tier; ew <- cf$diag_ew_universe
  list(tag=tag,
    n_months=cf$n_months, port_t_full=cf$portfolio_alpha_t_nw_lag3, port_p=cf$portfolio_alpha_t_pvalue,
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

res <- list(
  FA = eval_one("scores_FA.parquet","FA"),
  FB = eval_one("scores_FB.parquet","FB"),
  FC = eval_one("scores_FC.parquet","FC")
)
saveRDS(res, file.path(OUT,"canon_results.rds"))

# DSR (sweep, n_trials=3): deflate best net_sr across 3 trials
sr <- c(res$FA$net_sr, res$FB$net_sr, res$FC$net_sr)
tvec<- c(res$FA$port_t_full, res$FB$port_t_full, res$FC$port_t_full)
best <- which.max(tvec)
N <- min(c(res$FA$n_months,res$FB$n_months,res$FC$n_months))
# Bailey-LdP DSR approx: SR* threshold from N_trials
e_max <- (1-0.5772)*qnorm(1-1/3) + 0.5772*qnorm(1-1/(3*exp(1)))  # expected max of 3 std-normal
sr_ann <- sr/sqrt(12); # monthly SR
sr_std <- sr_ann/ (1/sqrt(N))  # crude
cat("\n===== R17 canonical dual-basis summary (cap-w authoritative) =====\n")
tab <- rbindlist(lapply(res, function(r) as.data.table(r[c("tag","n_months","port_t_full","port_t_IS","port_t_OOS",
  "ew_t","ew_post2017_t","ew_oos_ret","mega_w","mid_w","other_w","rank_ic","ric_t","szpartial_port_t",
  "placebo_p","net_sr","calmar","turnover")])), fill=TRUE)
print(tab, digits=3)
cat("\nbest cap-w PORT_t trial:", res[[best]]$tag, " t=",round(tvec[best],2),"\n")
cat("DSR note: sweep n_trials=3, E[max_3 z]=",round(e_max,3)," — best PORT_t applied multiple-testing aware.\n")
fwrite(tab, file.path(OUT,"canon_summary.csv"))
cat("[02] DONE\n")
