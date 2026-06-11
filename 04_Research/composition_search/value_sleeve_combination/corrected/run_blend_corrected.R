# =============================================================================
# Value Sleeve Combination — Stage 1 CORRECTED re-measurement (Forge)
# =============================================================================
# Fixes the realized_ym label offset in the book series (period_returns_layer5).
# Production semantics (confirmed from STR_1715 run_all.R L1143 + run_layer5 L96):
#   book realized_ym = month-of(period_end); return earned over (start_d, period_end]
#   => book label m corresponds to CALENDAR month m-1.
#   value_ret + bench_ret are keyed to true calendar month (run_blend.R L84-86, L109-111).
# Correction: shift book forward by 1 label so book_true[m] = book_ret[m+1] (= calendar m),
#   paired with value_ret[m], bench_ret[m]. Loses last month (no book m+1).
#
# All else identical to run_blend.R: w_value grid {0.05,0.10,0.15,0.20,0.30},
#   Return.portfolio(rebalance_on="months") + sleeve-rebal 15bps one-way,
#   PerformanceAnalytics + contract build_benchmark_compare (NO hand synthesis).
# metric_type = "backtested".
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
setDTthreads(1)

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
VSDIR  <- file.path(PROJECT_ROOT, "04_Research/composition_search/value_sleeve_combination")
OUTDIR <- file.path(VSDIR, "corrected")
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

BLEND_REBAL_BPS <- 15
W_GRID <- c(0.05, 0.10, 0.15, 0.20, 0.30)

# ---- 1. Load aligned series (read-only product of run_blend.R) ----
M <- as.data.table(readRDS(file.path(VSDIR, "aligned_series.rds")))
setorder(M, realized_ym)
n <- nrow(M)
cat(sprintf("[1] aligned_series n=%d  %s..%s\n", n, M$realized_ym[1], M$realized_ym[n]))

# Sanity: reproduce misaligned cor (artifact) before correction
cor_artifact <- cor(M$value_ret, M$book_ret)
cat(sprintf("    cor(value, book) MISALIGNED (artifact) = %.4f  (Stage1 reported -0.0455)\n",
            cor_artifact))

# ---- 2. Corrected alignment: book label m+1 = calendar month m ----
C <- data.table(
  realized_ym = M$realized_ym[1:(n-1)],
  book_ret    = M$book_ret[2:n],        # shift book forward -> true calendar month
  value_ret   = M$value_ret[1:(n-1)],
  bench_ret   = M$bench_ret[1:(n-1)]
)
nc <- nrow(C)
cor_corrected <- cor(C$value_ret, C$book_ret)
cor_book_bench <- cor(C$book_ret, C$bench_ret)
cat(sprintf("[2] CORRECTED n=%d  %s..%s\n", nc, C$realized_ym[1], C$realized_ym[nc]))
cat(sprintf("    cor(value, book_corrected) = %.4f  (artifact was %.4f)\n",
            cor_corrected, cor_artifact))
cat(sprintf("    cor(book_corrected, bench) = %.4f  (artifact -0.0044, value-bench +0.566)\n",
            cor_book_bench))

dts <- as.Date(paste0(C$realized_ym, "-01"))
bdt <- data.table(date = dts, benchmark_ret = C$bench_ret, benchmark_id = "KOSPI200_KQ150_BM")

# ---- 3. metric helper (PerformanceAnalytics + contract) ----
metric_block <- function(ret_xts, tag) {
  sr   <- as.numeric(SharpeRatio.annualized(ret_xts, Rf = 0))
  ann  <- table.AnnualizedReturns(ret_xts, Rf = 0, scale = 12)
  cagr <- as.numeric(ann["Annualized Return", 1])
  mdd  <- as.numeric(maxDrawdown(ret_xts))
  calmar <- if (mdd > 0) cagr / mdd else NA_real_
  pr <- data.table(date = index(ret_xts), ret_net = as.numeric(ret_xts), frequency = "monthly")
  bc <- build_benchmark_compare(pr, bdt, run_id = tag, strategy_id = tag, annualization_factor = 12)
  getv <- function(nm) bc[metric_name == nm, active_value][1]
  list(tag = tag, n_months = nrow(pr), SR = sr, CAGR = cagr, MDD = mdd, Calmar = calmar,
       IR = getv("Information_Ratio"), TE = getv("Tracking_Error"),
       PORT_t = getv("Portfolio_Alpha_t_NW_lag3"),
       alpha_ann = getv("Alpha_Annualized"),
       beta = bc[metric_name == "Beta_to_Benchmark", strategy_value][1],
       cor_bm = bc[metric_name == "Correlation", strategy_value][1])
}

ret_mat <- xts(cbind(book = C$book_ret, value = C$value_ret), order.by = dts)

bk <- metric_block(ret_mat[, "book"], "book_only_corrected")
cat(sprintf("[3] book-only (corrected): SR=%.4f CAGR=%.4f MDD=%.4f Calmar=%.4f IR=%.4f TE=%.4f PORT_t=%.3f beta=%.4f cor_bm=%.4f\n",
            bk$SR, bk$CAGR, bk$MDD, bk$Calmar, bk$IR, bk$TE, bk$PORT_t, bk$beta, bk$cor_bm))

# ---- 4. Blend grid (Return.portfolio monthly) + sleeve-rebal 15bps ----
blend_one <- function(wv) {
  rp <- Return.portfolio(ret_mat, weights = c(book = 1 - wv, value = wv),
                         rebalance_on = "months", verbose = TRUE)
  gross <- rp$returns
  bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
  to <- rep(0, nrow(bop))
  for (i in 2:nrow(bop)) to[i] <- sum(abs(as.numeric(bop[i,]) - as.numeric(eop[i-1,])))
  net <- gross - xts(to * BLEND_REBAL_BPS / 1e4, order.by = index(gross))
  list(net = net, mean_blend_to_annual = mean(to) * 12)
}

results <- list()
for (wv in W_GRID) {
  bl <- blend_one(wv)
  mb <- metric_block(bl$net, sprintf("blend_w%02d_corrected", round(wv*100)))
  mb$w_value <- wv
  mb$blend_to_annual <- bl$mean_blend_to_annual
  results[[as.character(wv)]] <- mb
  cat(sprintf("   w=%.2f: SR=%.4f dSR=%+.4f CAGR=%.4f MDD=%.4f dMDD=%+.4f Calmar=%.4f dCalmar=%+.4f IR=%.4f dIR=%+.4f PORT_t=%.3f blendTO=%.1f%%\n",
              wv, mb$SR, mb$SR-bk$SR, mb$CAGR, mb$MDD, mb$MDD-bk$MDD, mb$Calmar, mb$Calmar-bk$Calmar,
              mb$IR, mb$IR-bk$IR, mb$PORT_t, mb$blend_to_annual*100))
}

# ---- 5. DSR (sweep n_trials=5) diagnostic ----
trial_srs <- sapply(results, function(x) x$SR)
sel_metric <- sapply(results, function(x) x$IR)
best_key <- names(which.max(sel_metric))
best <- results[[best_key]]
sr_var <- var(trial_srs); emc <- 0.5772156649
exp_max <- sqrt(sr_var) * ((1-emc)*qnorm(1 - 1/5) + emc*qnorm(1 - 1/(5*exp(1))))
best_net <- blend_one(best$w_value)$net
r <- as.numeric(best_net)
srm <- mean(r)/sd(r)
g3 <- mean(((r-mean(r))/sd(r))^3); g4 <- mean(((r-mean(r))/sd(r))^4)
dsr_z <- (srm - exp_max/sqrt(12)) * sqrt(length(r)-1) / sqrt(1 - g3*srm + (g4-1)/4*srm^2)
DSR <- pnorm(dsr_z)
cat(sprintf("[5] DSR sweep n=5: best_by_IR=%s (w=%.2f) E[maxSR]=%.4f DSR=%.4f skew=%.4f kurt=%.4f\n",
            best_key, best$w_value, exp_max, DSR, g3, g4))

# ---- 6. Write outputs ----
rows <- rbindlist(lapply(c(list(bk), results), function(x) {
  data.table(
    label = x$tag,
    w_value = if (is.null(x$w_value)) 0 else x$w_value,
    n_months = x$n_months,
    SR = round(x$SR,4), CAGR = round(x$CAGR,4), MDD = round(x$MDD,4), Calmar = round(x$Calmar,4),
    IR = round(x$IR,4), TE = round(x$TE,4), PORT_t = round(x$PORT_t,3),
    alpha_ann = round(x$alpha_ann,4), beta = round(x$beta,3), cor_bm = round(x$cor_bm,3),
    dSR = round(x$SR - bk$SR,4), dMDD = round(x$MDD - bk$MDD,4),
    dCalmar = round(x$Calmar - bk$Calmar,4), dIR = round(x$IR - bk$IR,4),
    blend_to_annual = if (is.null(x$blend_to_annual)) NA_real_ else round(x$blend_to_annual,4),
    metric_type = "backtested"
  )
}), fill = TRUE)
fwrite(rows, file.path(OUTDIR, "results_corrected.csv"))

out <- list(
  meta = list(
    task = "value_sleeve_combination_stage1_CORRECTED",
    as_of = format(Sys.Date()), agent = "forge",
    correction = "book realized_ym label offset +1 fixed (book label m = calendar m-1); book shifted forward 1 label",
    selection_type = "sweep", n_trials = 5L, grid = W_GRID,
    n_overlap_months_corrected = nc, n_overlap_months_artifact = n,
    cor_value_book_artifact = round(cor_artifact, 4),
    cor_value_book_corrected = round(cor_corrected, 4),
    cor_book_bench_corrected = round(cor_book_bench, 4),
    metric_type = "backtested"
  ),
  book_only = list(SR=round(bk$SR,4), CAGR=round(bk$CAGR,4), MDD=round(bk$MDD,4),
                   Calmar=round(bk$Calmar,4), IR=round(bk$IR,4), TE=round(bk$TE,4),
                   PORT_t=round(bk$PORT_t,3), beta=round(bk$beta,3), cor_bm=round(bk$cor_bm,3)),
  blends = lapply(results, function(x) list(
    w_value = x$w_value, SR=round(x$SR,4), CAGR=round(x$CAGR,4), MDD=round(x$MDD,4),
    Calmar=round(x$Calmar,4), IR=round(x$IR,4), PORT_t=round(x$PORT_t,3),
    dSR=round(x$SR-bk$SR,4), dMDD=round(x$MDD-bk$MDD,4), dCalmar=round(x$Calmar-bk$Calmar,4),
    dIR=round(x$IR-bk$IR,4), blend_to_annual=round(x$blend_to_annual,4))),
  selection = list(best_by_IR = best_key, best_w_value = best$w_value,
                   best_SR = round(best$SR,4), best_dIR = round(best$IR-bk$IR,4),
                   best_dSR = round(best$SR-bk$SR,4), best_dMDD = round(best$MDD-bk$MDD,4),
                   best_dCalmar = round(best$Calmar-bk$Calmar,4)),
  dsr = list(n_trials = 5L, exp_max_sr_null = round(exp_max,4), DSR = round(DSR,4),
             skew = round(g3,4), kurt = round(g4,4)),
  gate_reference = list(
    dIR_hurdle = 0.05, dIR_best = round(best$IR-bk$IR,4),
    cor_hurdle = 0.30, cor_actual = round(cor_corrected,4),
    dsr_hurdle = 0.5, dsr_actual = round(DSR,4),
    note = "two-sleeve top-20 union > 25 (admission max 25) — research-stage report only")
)
write_json(out, file.path(OUTDIR, "blend_result_corrected.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
saveRDS(C, file.path(OUTDIR, "aligned_series_corrected.rds"))

cat("\n========== DONE (corrected) ==========\n")
cat(sprintf("cor(v,b) artifact=%.4f -> corrected=%.4f\n", cor_artifact, cor_corrected))
cat(sprintf("book-only corrected: SR=%.4f Calmar=%.4f IR=%.4f\n", bk$SR, bk$Calmar, bk$IR))
cat(sprintf("best blend by IR: %s dIR=%+.4f dSR=%+.4f dCalmar=%+.4f DSR=%.4f\n",
            best_key, best$IR-bk$IR, best$SR-bk$SR, best$Calmar-bk$Calmar, DSR))
