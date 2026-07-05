# _wt_eval.R — WT-D20260705_001 XATTN formalization: contract-grade eval + seed-ensemble
# CRITICAL FIX vs ad-hoc: kns_master_bench.parquet is shifted 1 month early (clean[t]==master[t+1]).
# We rebuild benchmark from .cache/benchmark.parquet (clean IKS200 KOSPI200), aligned so that a
# signal-month-t portfolio (score Date=t month-end, F1 realized in t+1) is compared to clean[t+1].
suppressMessages({ library(data.table); library(arrow) })
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(file.path(R,"04_Research/factor_rotation/fof_first_slice"))
source(file.path(R,"02_Infrastructure/contracts/canonical_screen_bt.R"))

args <- commandArgs(trailingOnly=TRUE)
MODE   <- ifelse(length(args)>=1, args[1], "canonical")
TOPN   <- ifelse(length(args)>=2, as.integer(args[2]), 25L)
LIQMIN <- ifelse(length(args)>=3, as.numeric(args[3]), 2e8)
COST   <- ifelse(length(args)>=4, as.numeric(args[4]), 15)
cat(sprintf("[eval] MODE=%s TOPN=%d LIQMIN=%.0e COST=%g\n", MODE, TOPN, LIQMIN, COST))

# --- panel: F1 (forward 1M realized in t+1), adv (t-1 liquidity), universe mask ---
M <- as.data.table(read_parquet("kns_master_panel.parquet",
       col_select=c("ym","Ticker","F1","adv","K200f","KQ150f","bad","nret")))
# signal month t -> Date = month-end(t). F1 realized t+1.
me <- function(ym) { d <- as.Date(paste0(ym,"-01")); as.Date(format(d + 32, "%Y-%m-01")) - 1 }
M[, Date := me(ym)]

# --- clean benchmark: compound daily -> monthly, align to REALIZATION month, then map to signal month ---
cb <- as.data.table(read_parquet(file.path(R,".cache/benchmark.parquet")))
cb[, ym := format(as.Date(Date), "%Y-%m")]
bm_real <- cb[, .(BM_real = prod(1+BM_Ret)-1), by=ym]  # realized return of month ym
setorder(bm_real, ym)
# signal month t's forward benchmark = realized benchmark of month (t+1)
bm_real[, ym_signal := format(as.Date(paste0(ym,"-01")) - 1, "%Y-%m")]  # ym is realization; signal = ym-1
bm_sig <- bm_real[, .(ym = ym_signal, BM_Ret = BM_real)]  # BM_Ret keyed by SIGNAL month
bm_sig[, Date := me(ym)]
bench_dt <- bm_sig[, .(Date, BM_Ret)]

# returns_dt: Ret_1m = F1 (forward realized), keyed by signal-month Date
returns_dt <- M[!is.na(F1), .(Date, Ticker, Ret_1m = F1)]
# liq_dt: adv at signal month (t-1 20d avg already in panel)
liq_dt <- M[, .(Date, Ticker, adv)]

eval_scores <- function(scores_file, tag) {
  if (!file.exists(scores_file)) { cat(sprintf("  [skip] %s missing\n", tag)); return(NULL) }
  S <- as.data.table(read_parquet(scores_file))
  setnames(S, old=intersect(names(S),"score"), new="score")
  S[, Date := as.Date(Date)]
  res <- canonical_screen_bt(
    scores_dt = S[, .(Date, Ticker, score)],
    returns_dt = returns_dt, bench_dt = bench_dt,
    top_n = TOPN, cost_bps_oneway = COST,
    liq_dt = if (LIQMIN>0) liq_dt else NULL, liq_min = LIQMIN,
    run_id=tag, strategy_id=tag)
  pr <- as.data.table(res$period_returns)  # date, ret_net, benchmark_ret
  pr[, active := ret_net - benchmark_ret]
  pr[, ym := format(date,"%Y-%m")]
  # subperiod active-t (NW not needed for split diagnostic; use simple t)
  sp_t <- function(d) if (nrow(d)>2 && sd(d$active)>0) mean(d$active)/sd(d$active)*sqrt(nrow(d)) else NA_real_
  t_2022 <- sp_t(pr[ym>="2022-01"])
  t_pre18 <- sp_t(pr[ym<"2018-01"]); t_post18 <- sp_t(pr[ym>="2018-01"])
  # oos_retention: anchored 3-split {55,65,75}% median of SR_oos/SR_is
  splits <- c(0.55,0.65,0.75); n <- nrow(pr); rets <- pr$active
  oos_vals <- sapply(splits, function(f){
    k <- floor(n*f); is_sr <- mean(rets[1:k])/(sd(rets[1:k])+1e-9); oos_sr <- mean(rets[(k+1):n])/(sd(rets[(k+1):n])+1e-9)
    if (abs(is_sr)<1e-6) NA_real_ else oos_sr/is_sr })
  oos_ret <- median(oos_vals, na.rm=TRUE)
  cagr <- prod(1+pr$ret_net)^(12/n)-1
  # MDD on net NAV
  nav <- cumprod(1+pr$ret_net); mdd <- max(1 - nav/cummax(nav))
  calmar <- cagr/ifelse(mdd>0,mdd,NA)
  list(tag=tag, n=n, port_t=res$portfolio_alpha_t_nw_lag3, IR=res$information_ratio,
       net_sr=res$net_sr, alpha_ann=res$alpha_annualized, turnover=res$turnover_annual,
       t_2022=t_2022, t_pre18=t_pre18, t_post18=t_post18, oos_ret=oos_ret,
       cagr=cagr, mdd=mdd, calmar=calmar, period_returns=pr)
}

# --- build seed-ensemble score (mean of per-seed scores by Date,Ticker) ---
build_ensemble <- function(files, out) {
  L <- lapply(files, function(f) if (file.exists(f)) as.data.table(read_parquet(f)) else NULL)
  L <- Filter(Negate(is.null), L); if (length(L)==0) return(NULL)
  A <- rbindlist(lapply(L, function(d){ d[, Date:=as.Date(Date)]; d[,.(Date,Ticker,score)] }))
  E <- A[, .(score = mean(score)), by=.(Date,Ticker)]
  write_parquet(E, out); out
}

pr_report <- function(r) if(!is.null(r)) cat(sprintf(
  "  %-18s n=%d port_t=%+.2f IR=%+.2f netSR=%+.2f turn=%.0f%% | pre18=%+.2f post18=%+.2f 2022+=%+.2f | oos=%+.2f calmar=%.2f MDD=%.1f%% CAGR=%.1f%%\n",
  r$tag, r$n, r$port_t, r$IR, r$net_sr, 100*r$turnover, r$t_pre18, r$t_post18, r$t_2022, r$oos_ret, r$calmar, 100*r$mdd, 100*r$cagr))

# discover seed files for MODE
seed_files <- c(sprintf("scores_XATTN_%s.parquet", MODE),
                Sys.glob(sprintf("scores_XATTN_%s_s*.parquet", MODE)))
seed_files <- unique(seed_files[file.exists(seed_files)])
cat(sprintf("[eval] %s seed files: %d\n", MODE, length(seed_files)))

results <- list()
for (sf in seed_files) {
  tag <- gsub(".parquet","",gsub("scores_XATTN_","",basename(sf)))
  results[[tag]] <- eval_scores(sf, tag)
  pr_report(results[[tag]])
}
# ensemble
ens_out <- sprintf("scores_XATTN_%s_ENS.parquet", MODE)
if (length(seed_files)>=2) {
  build_ensemble(seed_files, ens_out)
  results[["ENSEMBLE"]] <- eval_scores(ens_out, sprintf("%s_ENSEMBLE", MODE))
  pr_report(results[["ENSEMBLE"]])
}
saveRDS(results, sprintf("_wt_eval_%s.rds", MODE))
cat(sprintf("[eval] DONE %s -> _wt_eval_%s.rds\n", MODE, MODE))
