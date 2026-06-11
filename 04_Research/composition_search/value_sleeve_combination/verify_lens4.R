# =============================================================================
# Lens 4 adversarial verification — provenance / PIT / statistical claims
# Read-only on all sources. PerformanceAnalytics standard functions only.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
setDTthreads(1)

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/value_sleeve_combination")
BOOK_CSV <- file.path(PROJECT_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

cat("==== [A] aligned_series.rds structure ====\n")
M <- readRDS(file.path(OUTDIR, "aligned_series.rds"))
M <- as.data.table(M)
cat(sprintf("cols: %s\n", paste(names(M), collapse=",")))
cat(sprintf("n=%d  range %s..%s  NA: book=%d value=%d bench=%d\n",
  nrow(M), M$realized_ym[1], M$realized_ym[nrow(M)],
  sum(is.na(M$book_ret)), sum(is.na(M$value_ret)), sum(is.na(M$bench_ret))))
# contiguity check: every calendar month present exactly once?
yms <- M$realized_ym
d1 <- as.Date(paste0(yms, "-01"))
gaps <- diff(as.integer(format(d1,"%Y"))*12L + as.integer(format(d1,"%m")))
cat(sprintf("monotone+contiguous months: %s (gaps != 1: %d)\n",
  all(gaps == 1L), sum(gaps != 1L)))

cat("\n==== [B] book provenance: ret_L5_V2 full-sample SR vs metrics CSV ====\n")
book <- fread(BOOK_CSV)
bv <- book[!is.na(ret_L5_V2), .(realized_ym, anchor_date, ret_L5_V2)]
bx <- xts(bv$ret_L5_V2, order.by = as.Date(paste0(bv$realized_ym,"-01")))
sr_267 <- as.numeric(SharpeRatio.annualized(bx, Rf = 0))
ann <- table.AnnualizedReturns(bx, Rf = 0, scale = 12)
mdd_267 <- as.numeric(maxDrawdown(bx))
cat(sprintf("book full: n=%d  SR=%.4f (claim 1.8861)  CAGR=%.4f (claim 0.4037)  MDD=%.4f (claim 0.2481)\n",
  nrow(bv), sr_267, as.numeric(ann["Annualized Return",1]), mdd_267))
# cross-check vs metrics_layer5_variants.csv
mv <- fread(file.path(dirname(BOOK_CSV), "metrics_layer5_variants.csv"))
cat("metrics CSV L5_V2 rows:\n")
print(mv[variant == "L5_V2_aggressive_regime", .(panel, CAGR, Sharpe, MDD, n_months)])
# does aligned book series match CSV column on common months?
chk <- merge(M[, .(realized_ym, book_ret)], bv[, .(realized_ym, ret_L5_V2)], by="realized_ym")
cat(sprintf("aligned book == CSV ret_L5_V2 on %d months: max|diff|=%.3e\n",
  nrow(chk), max(abs(chk$book_ret - chk$ret_L5_V2))))

cat("\n==== [C] book-only metrics on 248m window (claims 1.9175/0.2481/1.6343/0.8539) ====\n")
dts <- as.Date(paste0(M$realized_ym,"-01"))
bk_x <- xts(M$book_ret, order.by = dts)
bench_x <- xts(M$bench_ret, order.by = dts)
sr_bk <- as.numeric(SharpeRatio.annualized(bk_x, Rf=0))
ann_bk <- table.AnnualizedReturns(bk_x, Rf=0, scale=12)
cagr_bk <- as.numeric(ann_bk["Annualized Return",1])
mdd_bk <- as.numeric(maxDrawdown(bk_x))
calmar_bk <- cagr_bk / mdd_bk
pr_bk <- data.table(date = index(bk_x), ret_net = as.numeric(bk_x), frequency="monthly")
bdt <- data.table(date = index(bench_x), benchmark_ret = as.numeric(bench_x),
                  benchmark_id = "KOSPI200_KQ150_BM")
bc_bk <- build_benchmark_compare(pr_bk, bdt, run_id="v", strategy_id="book_only",
                                 annualization_factor = 12)
ir_bk <- bc_bk[metric_name=="Information_Ratio", active_value][1]
te_bk <- bc_bk[metric_name=="Tracking_Error", active_value][1]
pt_bk <- bc_bk[metric_name=="Portfolio_Alpha_t_NW_lag3", active_value][1]
beta_bk <- bc_bk[metric_name=="Beta_to_Benchmark", strategy_value][1]
cor_bk <- bc_bk[metric_name=="Correlation", strategy_value][1]
cat(sprintf("book-only: SR=%.4f CAGR=%.4f MDD=%.4f Calmar=%.4f IR=%.4f TE=%.4f PORT_t=%.3f beta=%.4f cor_bm=%.4f\n",
  sr_bk, cagr_bk, mdd_bk, calmar_bk, ir_bk, te_bk, pt_bk, beta_bk, cor_bk))

cat("\n==== [D] off-by-one lag scan: cor with benchmark at lags -2..+2 ====\n")
lagcor <- function(a, b, k) {
  n <- length(a)
  if (k >= 0) cor(a[(1+k):n], b[1:(n-k)]) else cor(a[1:(n+k)], b[(1-k):n])
}
for (k in -2:2) {
  cat(sprintf("lag %+d: cor(book_t, bench_{t-%+d})=%.4f   cor(value_t, bench_{t-%+d})=%.4f   cor(value_t, book_{t-%+d})=%.4f\n",
    k, k, lagcor(M$book_ret, M$bench_ret, k),
    k, lagcor(M$value_ret, M$bench_ret, k),
    k, lagcor(M$value_ret, M$book_ret, k)))
}
cat(sprintf("cor(value, book) lag0 = %.4f (claim -0.0455)\n", cor(M$value_ret, M$book_ret)))
# replicate original anchor -0.042245 vs ret_orig
co <- merge(M[, .(realized_ym, value_ret)], book[, .(realized_ym, ret_orig)], by="realized_ym")
co <- co[!is.na(ret_orig)]
cat(sprintf("cor(value, ret_orig) = %.6f on n=%d (alpha_validation claim -0.042245 n=248)\n",
  cor(co$value_ret, co$ret_orig), nrow(co)))

cat("\n==== [E] value sleeve fidelity: IR (canonical net_sr analog) + abs SR ====\n")
vx <- xts(M$value_ret, order.by = dts)
sr_v_abs <- as.numeric(SharpeRatio.annualized(vx, Rf=0))
act_v <- M$value_ret - M$bench_ret
ir_v <- mean(act_v)/sd(act_v)*sqrt(12)   # = canonical_screen_bt net_sr definition
cat(sprintf("value abs SR (PerfA geometric)=%.4f (json standalone_sr_perfa 0.4804)\n", sr_v_abs))
cat(sprintf("value IR=mean(active)/sd(active)*sqrt(12)=%.4f (alpha_validation net_sr 0.375339, 249m)\n", ir_v))

cat("\n==== [F] blend w=0.20 recompute (claims SR 2.0695 MDD 0.2054 Calmar 1.7763 IR 0.8789) ====\n")
ret_mat <- xts(cbind(book = M$book_ret, value = M$value_ret), order.by = dts)
blend_one <- function(wv) {
  rp <- Return.portfolio(ret_mat, weights = c(book = 1-wv, value = wv),
                         rebalance_on = "months", verbose = TRUE)
  gross <- rp$returns
  bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
  to <- rep(0, nrow(bop))
  for (i in 2:nrow(bop)) to[i] <- sum(abs(as.numeric(bop[i,]) - as.numeric(eop[i-1,])))
  net <- gross - xts(to * 15/1e4, order.by = index(gross))
  list(net = net, to_ann = mean(to)*12)
}
res <- list()
for (wv in c(0.05,0.10,0.15,0.20,0.30)) {
  bl <- blend_one(wv)
  nx <- bl$net
  sr <- as.numeric(SharpeRatio.annualized(nx, Rf=0))
  a2 <- table.AnnualizedReturns(nx, Rf=0, scale=12)
  cg <- as.numeric(a2["Annualized Return",1])
  md <- as.numeric(maxDrawdown(nx))
  prx <- data.table(date = index(nx), ret_net = as.numeric(nx), frequency="monthly")
  bcx <- build_benchmark_compare(prx, bdt, run_id="v", strategy_id=sprintf("w%02d",wv*100),
                                 annualization_factor = 12)
  irx <- bcx[metric_name=="Information_Ratio", active_value][1]
  ptx <- bcx[metric_name=="Portfolio_Alpha_t_NW_lag3", active_value][1]
  res[[as.character(wv)]] <- c(SR=sr, CAGR=cg, MDD=md, Calmar=cg/md, IR=irx, PORT_t=ptx, TOann=bl$to_ann)
  cat(sprintf("w=%.2f: SR=%.4f CAGR=%.4f MDD=%.4f Calmar=%.4f IR=%.4f dIR=%+.4f PORT_t=%.3f blendTO=%.4f\n",
    wv, sr, cg, md, cg/md, irx, irx-ir_bk, ptx, bl$to_ann))
}

cat("\n==== [G] DSR arithmetic (claim exp_max 0.0447, DSR 1.0000, n_trials=5) ====\n")
trial_srs <- sapply(res, function(x) x["SR.Annualized Sharpe Ratio (Rf=0%)"])
if (any(is.na(trial_srs))) trial_srs <- sapply(res, function(x) x[1])
cat(sprintf("trial SRs: %s\n", paste(sprintf("%.4f", trial_srs), collapse=", ")))
sr_var <- var(trial_srs); emc <- 0.5772156649
exp_max <- sqrt(sr_var) * ((1-emc)*qnorm(1-1/5) + emc*qnorm(1-1/(5*exp(1))))
cat(sprintf("sd(trialSR)=%.4f  E[maxSR null]=%.4f (claim 0.0447)\n", sqrt(sr_var), exp_max))
best_net <- blend_one(0.20)$net
r <- as.numeric(best_net)
srm <- mean(r)/sd(r)
g3 <- mean(((r-mean(r))/sd(r))^3); g4 <- mean(((r-mean(r))/sd(r))^4)
dsr_z <- (srm - exp_max/sqrt(12)) * sqrt(length(r)-1) / sqrt(1 - g3*srm + (g4-1)/4*srm^2)
cat(sprintf("monthly SR=%.4f skew=%.4f kurt=%.4f DSR=%.6f (claim 1.0000, skew 0.5581 kurt 4.8368)\n",
  srm, g3, g4, pnorm(dsr_z)))

cat("\n==== [H] date convention: book anchor vs realized; value sig->realized ====\n")
print(head(book[, .(anchor_date, realized_ym)], 3))
print(tail(book[!is.na(ret_L5_V2), .(anchor_date, realized_ym)], 3))
cat("DONE\n")
