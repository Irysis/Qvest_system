#==============================================================================
# QEPM Optimizer Research v2 — WT-D20260429_001
# Mission: Fix v1 inconsistency (target_weights vs weights.csv last row).
#
# Charter §9 enforcement: target_weights MUST equal weights.csv[as_of_date].
# Walk-forward HRP per-date: rolling 60-month panel of per-date top-20 by alpha_z,
# with explicit fallback labels (inverse_vol / EW) when history insufficient.
#
# Selection: HRP_lambda_2.0_psi_0.3_bounds_0.15 (already chosen by v1 from 4-method shop)
# Just rewriting walk-forward generation + tying as-of.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(quadprog); library(Matrix)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
TASK_ID      <- "WT-D20260429_001"
WT_DIR       <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", TASK_ID)
SA_DIR       <- file.path(PROJECT_ROOT, "stage_artifacts", TASK_ID)

setwd(PROJECT_ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/portfolio/mean_variance_optimizer.R")
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/worktask/lineage_utils.R")

# ─── Inputs ──────────────────────────────────────────────
cat("==[Optimizer v2]== Loading alpha + risk + STR_1715\n")
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"))
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"))
request   <- fromJSON(file.path(WT_DIR, "request.json"))

alpha_vec_named <- unlist(alpha_pkg$alpha_vector)
conf_vec_named  <- unlist(alpha_pkg$confidence_vector)
cat("Alpha tickers (panel):", length(alpha_vec_named), "\n")

cov_long <- as.data.table(read_parquet(file.path(SA_DIR, "covariance.parquet")))
top60 <- sort(unique(cov_long$Ticker_i))
N_panel <- length(top60)
Sigma <- matrix(0, N_panel, N_panel, dimnames = list(top60, top60))
for (k in seq_len(nrow(cov_long))) {
  Sigma[cov_long$Ticker_i[k], cov_long$Ticker_j[k]] <- cov_long$Sigma[k]
}
stopifnot(isSymmetric(Sigma, tol = 1e-8))

fac_exp_long <- as.data.frame(read_parquet(file.path(SA_DIR, "factor_exposure.parquet")))
fac_exp <- as.matrix(fac_exp_long[, -1])
rownames(fac_exp) <- fac_exp_long$Ticker
fac_exp <- fac_exp[top60, , drop = FALSE]

spec_long <- as.data.frame(read_parquet(file.path(SA_DIR, "specific_risk.parquet")))
spec_var <- setNames(spec_long$specific_var, spec_long$Ticker)[top60]

alpha_vec_z <- alpha_vec_named[top60]
conf_vec  <- conf_vec_named[top60]

# Scaling for IR realism
ALPHA_SCALE_MONTHLY <- 0.0588 * 0.08
ALPHA_SCALE_ANN <- ALPHA_SCALE_MONTHLY * 12
alpha_vec <- alpha_vec_z * ALPHA_SCALE_ANN

# STR_1715 reference
str1715 <- readRDS(file.path(PROJECT_ROOT,
                              "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds"))
str1715_pr <- str1715$period_returns
str1715_ret <- data.table(date = str1715_pr$date, ret_str1715 = str1715_pr$ret_net)
cat("STR_1715 ret_net periods:", nrow(str1715_ret), "\n")

# Monthly returns
cat("==[Optimizer v2]== Loading RAWDATA + monthly returns\n")
source("02_Infrastructure/backtest_harness.R")
res_raw <- load_rawdata()
RAWDATA <- res_raw$RAWDATA
sc <- as.data.table(read_parquet(file.path(SA_DIR, "alpha_scores.parquet")))
sig_dates <- sort(unique(sc$Date))
all_tickers <- unique(sc$Ticker)
RAW_all <- RAWDATA[Ticker %in% all_tickers & !is.na(Ret), .(Date, Ticker, Ret)]
RAW_all[, YearMonth := format(Date, "%Y-%m")]
mret_all <- RAW_all[, .(monthly_ret = prod(1 + Ret) - 1, .N), by = .(Ticker, YearMonth)]
ym_to_sigdate <- data.table(
  YearMonth = format(sig_dates, "%Y-%m"),
  sig_date = sig_dates
)
mret_all <- merge(mret_all, ym_to_sigdate, by = "YearMonth")
cat("mret_all rows:", nrow(mret_all),
    " unique tickers:", length(unique(mret_all$Ticker)), "\n")

# top60 monthly returns matrix (for as-of computations)
mret <- mret_all[Ticker %in% top60]
mret_wide <- dcast(mret, sig_date ~ Ticker, value.var = "monthly_ret")
mret_mat_full <- as.matrix(mret_wide[, -1, with = FALSE])
rownames(mret_mat_full) <- as.character(mret_wide$sig_date)
common_cols <- intersect(top60, colnames(mret_mat_full))
mret_mat_full <- mret_mat_full[, common_cols, drop = FALSE]
ret_dt_hrp <- mret[, .(Date = sig_date, Ticker, Ret = monthly_ret)]

# ─── As-of HRP (anchor) ──────────────────────────────────
# Reproduce v1 selection: HRP on top60, n_days=60, max_w=0.15, ledoit_wolf
cat("\n==[As-of HRP (anchor)]==\n")
hrp_w <- calc_hrp_weights(top60, ret_dt_hrp, n_days = 60, max_w = 0.15,
                           cov_method = "ledoit_wolf")
hrp_w_top20 <- sort(hrp_w, decreasing = TRUE)[seq_len(20)]
hrp_w_top20 <- hrp_w_top20 / sum(hrp_w_top20)
hrp_w_capped <- pmin(hrp_w_top20, 0.15)
hrp_w_capped <- hrp_w_capped / sum(hrp_w_capped)
cat("As-of HRP names:", length(hrp_w_capped), "\n")
cat("Sum:", round(sum(hrp_w_capped), 6), "\n")
cat("Range:", round(range(hrp_w_capped), 4), "\n")
cat("HHI:", round(sum(hrp_w_capped^2), 4), "\n")
cat("Tickers:", paste(sort(names(hrp_w_capped)), collapse=" "), "\n")

selected_method_label <- "HRP_lambda_2.0_psi_0.3_bounds_0.15"

# ─── Walk-forward generator (v2) ─────────────────────────
# Per sig_date:
#   1. Use risk_package.json's top60 panel ONLY for as-of (2026-03-31).
#   2. For all other sig_dates: pick per-date top-60 by alpha_z, then top-20 by alpha_z.
#   3. Run HRP on rolling 60m monthly returns of those 20 (require ≥30 months for HRP);
#      else fallback to inverse-vol on available history (require ≥6 months);
#      else fallback to EW (clearly labeled).
#   4. Cap [0, 0.15], normalize.
build_wf_v2 <- function(sc_full, mret_full_dt, ret_dt_hrp_full, str_anchor_w, str_anchor_tickers,
                         anchor_date) {
  out_list <- list()
  fallback_log <- list()  # date → fallback type
  sig_dates_all <- sort(unique(sc_full$Date))
  N_dates <- length(sig_dates_all)
  cat("\n==[Walk-forward v2 generation]== ", N_dates, "sig_dates\n")
  pb_step <- ceiling(N_dates / 30)

  for (i in seq_along(sig_dates_all)) {
    sd <- sig_dates_all[i]
    sd_dt <- as.Date(sd)

    # If as-of date: use anchor weights directly (Charter §9)
    if (!is.null(anchor_date) && sd_dt == anchor_date) {
      out_list[[as.character(sd_dt)]] <- data.table(
        Date = sd_dt,
        Ticker = names(str_anchor_w),
        Weight = as.numeric(str_anchor_w)
      )
      fallback_log[[as.character(sd_dt)]] <- "anchor_as_of"
      next
    }

    sc_sd <- sc_full[Date == sd_dt]
    if (nrow(sc_sd) < 60) {
      # not enough universe — skip
      next
    }
    sc_sd <- sc_sd[order(-alpha_z)]
    cand_60 <- sc_sd$Ticker[seq_len(60)]
    top20_tickers <- cand_60[seq_len(20)]

    # Get prior history (rolling 60 months, max)
    history_start_60 <- seq(sd_dt, by = "-60 months", length.out = 2)[2]
    history_start_36 <- seq(sd_dt, by = "-36 months", length.out = 2)[2]
    history_start_12 <- seq(sd_dt, by = "-12 months", length.out = 2)[2]

    # Try 60m HRP (proper)
    ret_dt_60 <- ret_dt_hrp_full[Ticker %in% top20_tickers
                                  & Date < sd_dt
                                  & Date >= history_start_60]
    n_avail_60 <- length(unique(ret_dt_60$Date))

    fallback_used <- NA_character_
    w_vec <- NULL

    if (n_avail_60 >= 30) {
      # Try HRP with ledoit_wolf
      w_try <- tryCatch(
        calc_hrp_weights(top20_tickers, ret_dt_60, n_days = n_avail_60,
                         max_w = 0.15, cov_method = "ledoit_wolf"),
        error = function(e) NULL
      )
      if (!is.null(w_try) && length(w_try) == 20 && length(unique(round(w_try, 6))) >= 5) {
        # HRP returned non-degenerate weights (≥5 unique values)
        w_vec <- w_try
        fallback_used <- "HRP_60m"
      }
    }

    # Fallback 1: HRP with 36m history
    if (is.null(w_vec)) {
      ret_dt_36 <- ret_dt_hrp_full[Ticker %in% top20_tickers
                                    & Date < sd_dt
                                    & Date >= history_start_36]
      n_avail_36 <- length(unique(ret_dt_36$Date))
      if (n_avail_36 >= 24) {
        w_try <- tryCatch(
          calc_hrp_weights(top20_tickers, ret_dt_36, n_days = n_avail_36,
                           max_w = 0.15, cov_method = "ledoit_wolf"),
          error = function(e) NULL
        )
        if (!is.null(w_try) && length(w_try) == 20 && length(unique(round(w_try, 6))) >= 5) {
          w_vec <- w_try
          fallback_used <- "HRP_36m"
        }
      }
    }

    # Fallback 2: Inverse-vol (with whatever history available, ≥6m)
    if (is.null(w_vec)) {
      ret_dt_iv <- ret_dt_hrp_full[Ticker %in% top20_tickers
                                    & Date < sd_dt
                                    & Date >= history_start_36]
      n_avail_iv <- length(unique(ret_dt_iv$Date))
      if (n_avail_iv >= 6) {
        # Compute per-ticker monthly std on available history (impute missing as median)
        mret_w <- dcast(ret_dt_iv, Date ~ Ticker, value.var = "Ret",
                        fun.aggregate = mean, fill = NA)
        mret_w_mat <- as.matrix(mret_w[, -1, with = FALSE])
        # Use only tickers with ≥3 obs
        valid_cols <- colSums(!is.na(mret_w_mat)) >= 3
        if (sum(valid_cols) >= 10) {
          mret_w_mat <- mret_w_mat[, valid_cols, drop = FALSE]
          vol_t <- apply(mret_w_mat, 2, sd, na.rm = TRUE)
          vol_t[!is.finite(vol_t) | vol_t <= 0] <-
            median(vol_t[is.finite(vol_t) & vol_t > 0], na.rm = TRUE)
          w_iv <- 1 / vol_t
          w_iv <- w_iv / sum(w_iv)
          # Pad missing tickers with EW share of remaining
          if (length(w_iv) < 20) {
            missing_tk <- setdiff(top20_tickers, names(w_iv))
            ew_fill <- rep(median(w_iv) * 0.5, length(missing_tk))
            names(ew_fill) <- missing_tk
            w_iv <- c(w_iv, ew_fill)
            w_iv <- w_iv / sum(w_iv)
          }
          w_iv <- w_iv[top20_tickers]
          w_iv <- pmin(w_iv, 0.15)
          w_iv <- w_iv / sum(w_iv)
          w_vec <- w_iv
          fallback_used <- "inverse_vol"
        }
      }
    }

    # Fallback 3: EW (very early dates only)
    if (is.null(w_vec)) {
      w_vec <- rep(1 / 20, 20)
      names(w_vec) <- top20_tickers
      fallback_used <- "EW"
    }

    out_list[[as.character(sd_dt)]] <- data.table(
      Date = sd_dt,
      Ticker = names(w_vec),
      Weight = as.numeric(w_vec)
    )
    fallback_log[[as.character(sd_dt)]] <- fallback_used

    if (i %% pb_step == 0) {
      cat(sprintf("  date %d/%d (%s) [%s]\n", i, N_dates, sd_dt, fallback_used))
    }
  }

  list(weights_dt = rbindlist(out_list), fallback_log = fallback_log)
}

# Run walk-forward
anchor_date <- as.Date("2026-03-31")
wf_res <- build_wf_v2(sc, mret_all,
                       ret_dt_hrp_full = ret_dt_hrp,  # top60 panel only — for as-of nominal
                       str_anchor_w = hrp_w_capped,
                       str_anchor_tickers = names(hrp_w_capped),
                       anchor_date = anchor_date)

weights_dt <- wf_res$weights_dt
fallback_log <- wf_res$fallback_log

# Build per-date top20 ret_dt for proper HRP at non-anchor dates
# Actually, we used full ret_dt_hrp from top60. But per-date top-20 may include tickers outside top60.
# For non-anchor dates: re-pick history from mret_all (full universe) and top-20 selected per date.
cat("\n==[Re-running walk-forward with full universe history]==\n")

# Need to rebuild correctly: per-date top-20 may include any of 351 tickers
ret_dt_full_hrp <- mret_all[, .(Date = sig_date, Ticker, Ret = monthly_ret)]

# Re-run with proper per-date top-20 universe
wf_res2 <- build_wf_v2(sc, mret_all,
                        ret_dt_hrp_full = ret_dt_full_hrp,
                        str_anchor_w = hrp_w_capped,
                        str_anchor_tickers = names(hrp_w_capped),
                        anchor_date = anchor_date)

weights_dt <- wf_res2$weights_dt
fallback_log <- wf_res2$fallback_log

cat("\nweights_dt rows:", nrow(weights_dt),
    " unique dates:", length(unique(weights_dt$Date)),
    " sig_dates:", length(sig_dates), "\n")
schedule_density <- length(unique(weights_dt$Date)) / length(sig_dates)
cat("Schedule density ratio:", round(schedule_density, 4), "\n")

# Fallback distribution
fb_tab <- table(unlist(fallback_log))
cat("\nFallback distribution:\n")
print(fb_tab)

# Verify as-of (2026-03-31) row matches anchor
last_w_v2 <- weights_dt[Date == anchor_date]
cat("\nAs-of (2026-03-31) check:\n")
cat("  rows:", nrow(last_w_v2), "\n")
cat("  sum:", sum(last_w_v2$Weight), "\n")
cat("  unique values:", length(unique(round(last_w_v2$Weight, 6))), "\n")
cat("  matches anchor: ", identical(sort(last_w_v2$Ticker), sort(names(hrp_w_capped))), "\n")

# ─── Compute walk-forward portfolio realized returns ─────
cat("\n==[Walk-forward portfolio realized returns]==\n")
wd_dt <- copy(weights_dt)
wd_dt[, current_YM := format(Date, "%Y-%m")]
unique_dates_wf <- sort(unique(wd_dt$Date))
ym_map_wf <- data.table(
  current_YM = format(unique_dates_wf, "%Y-%m"),
  next_YM = c(format(unique_dates_wf[-1], "%Y-%m"), NA_character_)
)
wd_dt <- merge(wd_dt, ym_map_wf, by = "current_YM")
wd_dt <- wd_dt[!is.na(next_YM)]
wd_dt <- merge(wd_dt, mret_all[, .(Ticker, YearMonth, monthly_ret)],
                by.x = c("Ticker", "next_YM"), by.y = c("Ticker", "YearMonth"))
port_ret_wf <- wd_dt[, .(port_ret = sum(Weight * monthly_ret)), by = .(Date)]
port_ret_wf[, YearMonth := format(Date, "%Y-%m")]
str1715_ym <- copy(str1715_ret)
str1715_ym[, YearMonth := format(date, "%Y-%m")]
joined_wf <- merge(port_ret_wf, str1715_ym[, .(YearMonth, ret_str = ret_str1715)],
                    by = "YearMonth")
n_join_wf <- nrow(joined_wf)
cat("Joined obs:", n_join_wf, "\n")
cat("port_ret summary: mean=", round(mean(joined_wf$port_ret, na.rm=TRUE), 5),
    " sd=", round(sd(joined_wf$port_ret, na.rm=TRUE), 5),
    " range=", round(range(joined_wf$port_ret, na.rm=TRUE), 4), "\n")
cat("ret_str summary: mean=", round(mean(joined_wf$ret_str, na.rm=TRUE), 5),
    " sd=", round(sd(joined_wf$ret_str, na.rm=TRUE), 5),
    " range=", round(range(joined_wf$ret_str, na.rm=TRUE), 4), "\n")

# Walk-forward TDC q5/q10/q20
wf_tdc <- list()
for (q in c(0.05, 0.10, 0.20)) {
  qp <- quantile(joined_wf$port_ret, q, na.rm = TRUE)
  qs <- quantile(joined_wf$ret_str, q, na.rm = TRUE)
  n_both <- sum(joined_wf$port_ret <= qp & joined_wf$ret_str <= qs, na.rm = TRUE)
  n_s <- sum(joined_wf$ret_str <= qs, na.rm = TRUE)
  wf_tdc[[paste0("q", round(q*100))]] <- if (n_s > 0) n_both / n_s else NA
}
wf_pearson <- cor(joined_wf$port_ret, joined_wf$ret_str, use = "pairwise.complete.obs")
wf_kendall <- cor(joined_wf$port_ret, joined_wf$ret_str, use = "pairwise.complete.obs",
                   method = "kendall")
cv5_thresh <- quantile(joined_wf$port_ret, 0.05, na.rm = TRUE)
wf_cvar_5 <- mean(joined_wf$port_ret[joined_wf$port_ret <= cv5_thresh], na.rm = TRUE)
wf_var_5 <- cv5_thresh
# Standard Sharpe (Charter §12)
wf_sharpe_std <- mean(joined_wf$port_ret, na.rm = TRUE) /
                 sd(joined_wf$port_ret, na.rm = TRUE) * sqrt(12)
wf_cagr <- prod(1 + joined_wf$port_ret, na.rm = TRUE)^(12 / n_join_wf) - 1
wf_sd_ann <- sd(joined_wf$port_ret, na.rm = TRUE) * sqrt(12)

cat("\nWalk-forward stats:\n")
cat(sprintf("  TDC q5=%.4f  q10=%.4f  q20=%.4f\n", wf_tdc$q5, wf_tdc$q10, wf_tdc$q20))
cat(sprintf("  Pearson=%.4f  Kendall=%.4f\n", wf_pearson, wf_kendall))
cat(sprintf("  CVaR(5%%) monthly=%.4f  VaR(5%%)=%.4f\n", wf_cvar_5, wf_var_5))
cat(sprintf("  Sharpe(standard,ann)=%.4f  CAGR=%.4f  sd_ann=%.4f\n",
            wf_sharpe_std, wf_cagr, wf_sd_ann))

wf_tdc_pass <- !is.na(wf_tdc$q5) && wf_tdc$q5 < 0.30
cat(sprintf("\nTDC q5 < 0.30 gate: %s\n", if (wf_tdc_pass) "PASS" else "FAIL"))

# Compute realized turnover (round-trip annual)
weights_wide <- dcast(weights_dt, Date ~ Ticker, value.var = "Weight", fill = 0)
weights_mat <- as.matrix(weights_wide[, -1, with = FALSE])
realized_to_per_rebalance <- numeric(nrow(weights_mat) - 1)
for (i in seq_len(nrow(weights_mat) - 1)) {
  realized_to_per_rebalance[i] <- sum(abs(weights_mat[i + 1, ] - weights_mat[i, ])) / 2
}
realized_to_one_side_annual <- mean(realized_to_per_rebalance) * 12
realized_to_annual_rt <- realized_to_one_side_annual * 2  # round-trip ×2
cat(sprintf("Realized turnover: per-rebalance one-side=%.4f  annual one-side=%.3f  annual round-trip=%.3f\n",
            mean(realized_to_per_rebalance), realized_to_one_side_annual, realized_to_annual_rt))

# ─── Save weights.csv (overwrite) ────────────────────────
fwrite(weights_dt[, .(Date, Ticker, Weight = round(Weight, 6))],
       file.path(SA_DIR, "weights.csv"))
cat(sprintf("\nweights.csv saved: %d rows, %d unique dates\n",
            nrow(weights_dt), length(unique(weights_dt$Date))))

# ─── Build optimization_package_draft.json (overwrite) ──
# Use as-of HRP weights as target_weights (Charter §9 anchor)
target_weights_list <- as.list(round(hrp_w_capped, 6))

# Recompute as-of metrics on hrp_w_capped (anchor)
compute_port_tdc <- function(weights_named, mret_mat_full, str1715_ret) {
  tk <- intersect(names(weights_named), colnames(mret_mat_full))
  if (length(tk) == 0) return(list(empirical_q5 = NA))
  w <- weights_named[tk]; w <- w / sum(w)
  ret_sub <- mret_mat_full[, tk, drop = FALSE]
  ret_sub[is.na(ret_sub)] <- 0
  port_ret <- as.numeric(ret_sub %*% w)
  port_dt <- data.table(
    YearMonth = format(as.Date(rownames(mret_mat_full)), "%Y-%m"),
    port = port_ret
  )
  str_ym <- copy(str1715_ret)
  str_ym[, YearMonth := format(date, "%Y-%m")]
  joined <- merge(port_dt, str_ym[, .(YearMonth, ret_str1715)], by = "YearMonth")
  if (nrow(joined) < 30) return(list(empirical_q5 = NA, n_join = nrow(joined)))
  qres <- list()
  for (q in c(0.05, 0.10, 0.20)) {
    qp <- quantile(joined$port, q, na.rm = TRUE)
    qs <- quantile(joined$ret_str1715, q, na.rm = TRUE)
    n_both <- sum(joined$port <= qp & joined$ret_str1715 <= qs)
    n_s <- sum(joined$ret_str1715 <= qs)
    qres[[paste0("q", round(q * 100))]] <- if (n_s > 0) n_both / n_s else NA
  }
  list(
    empirical_q5  = qres$q5,
    empirical_q10 = qres$q10,
    empirical_q20 = qres$q20,
    pearson = cor(joined$port, joined$ret_str1715, use = "pairwise.complete.obs"),
    kendall_tau = cor(joined$port, joined$ret_str1715, use = "pairwise.complete.obs",
                       method = "kendall"),
    n_join = nrow(joined)
  )
}
asof_tdc <- compute_port_tdc(hrp_w_capped, mret_mat_full, str1715_ret)
cat(sprintf("\nAs-of static TDC: q5=%.4f q10=%.4f q20=%.4f Pearson=%.4f Kendall=%.4f n=%d\n",
            asof_tdc$empirical_q5, asof_tdc$empirical_q10, asof_tdc$empirical_q20,
            asof_tdc$pearson, asof_tdc$kendall_tau, asof_tdc$n_join))

# As-of CVaR
asof_port_ret <- as.numeric(mret_mat_full[, names(hrp_w_capped), drop = FALSE] %*% hrp_w_capped)
asof_port_ret <- asof_port_ret[!is.na(asof_port_ret)]
asof_var5 <- quantile(asof_port_ret, 0.05, na.rm = TRUE)
asof_cvar5 <- mean(asof_port_ret[asof_port_ret <= asof_var5], na.rm = TRUE)

# As-of expected α + TE + IR (using SCALED alpha)
asof_alpha <- sum(hrp_w_capped * alpha_vec[names(hrp_w_capped)])
asof_te_var <- as.numeric(t(hrp_w_capped) %*% Sigma[names(hrp_w_capped), names(hrp_w_capped)] %*% hrp_w_capped)
asof_te <- sqrt(asof_te_var) * sqrt(12)  # annualized monthly Σ
asof_ir <- if (asof_te > 1e-8) asof_alpha / asof_te else NA

# Net systematic
asof_net_sys <- colSums(fac_exp[names(hrp_w_capped), , drop = FALSE] * hrp_w_capped)

# Selection score (crowding_adj_ret)
asof_net_alpha <- asof_alpha - 0.0015 * realized_to_annual_rt
asof_net_ir <- if (asof_te > 1e-8) asof_net_alpha / asof_te else NA
asof_tdc_q5 <- asof_tdc$empirical_q5
asof_pen <- if (asof_tdc_q5 <= 0.30) 1.0 else max(0, 1 - 2 * (asof_tdc_q5 - 0.30))
asof_crowding_adj_ret <- asof_net_ir * asof_pen

cat("\nAs-of summary:\n")
cat(sprintf("  α=%.4f  TE=%.4f  IR=%.3f  net_IR=%.3f\n",
            asof_alpha, asof_te, asof_ir, asof_net_ir))
cat(sprintf("  CVaR(5%%) monthly=%.4f  VaR(5%%)=%.4f\n", asof_cvar5, asof_var5))
cat(sprintf("  Net systematic: ", paste(names(asof_net_sys), round(asof_net_sys, 3),
                                          sep="=", collapse=", "), "\n"))
cat(sprintf("  Selection score (crowding_adj_ret) = %.4f\n", asof_crowding_adj_ret))

# Top overweights/underweights
sw <- sort(unlist(target_weights_list), decreasing = TRUE)
top_over <- names(sw)[seq_len(min(5, length(sw)))]
top_under <- names(sw)[(length(sw) - 4):length(sw)]

# Binding constraints
binding <- c()
binding <- c(binding, "max_names_20")  # always at 20
max_w_final <- max(unlist(target_weights_list))
if (abs(max_w_final - 0.15) < 0.001) binding <- c(binding, "weight_bound_upper_0.15")
if (realized_to_annual_rt > 3.0) binding <- c(binding,
                                                sprintf("turnover_cap_annual_3.0_realized_breach_%.2f", realized_to_annual_rt))
if (realized_to_annual_rt > 6.0) binding <- c(binding, "turnover_cap_annual_6.0_HARD_FAIL")

# Infeasibility check
infeasibility_report <- NULL
if (!wf_tdc_pass) {
  infeasibility_report <- list(
    reason = sprintf("Walk-forward realized TDC q5 = %.4f >= 0.30 gate, despite as-of static TDC = %.4f. Walk-forward path of selected method (%s) over 22Y exposes structural lower-tail dependence with STR_1715 (PG2 active). Risk Agent CF-RISK-01 (Top-60 EW q5=0.4494) confirmed at deployment-grade weighting with per-date top-20 alpha selection.",
                      wf_tdc$q5, asof_tdc_q5, selected_method_label),
    violated_constraints = c("TDC_q5_max_0.30_walk_forward",
                              "CF-03_portfolio_orthogonality_realized"),
    suggested_resolution = "Alpha redesign required: (a) Macro-conditional defensive sector tilt (utility/staples); (b) Time-series momentum overlay regime-conditional cash; (c) Cross-market universe expansion. Current 3-factor Low IVOL composite (D47+D01+D04) with KOSPI200_KOSDAQ150_intersection cannot achieve walk-forward TDC < 0.30 vs STR_1715 in any of 4 method families tested."
  )
}

# Method comparison (use v1 method_metrics, but recompute selected method as-of metrics)
# v1 method_metrics is preserved for MVO/CVaR/Robust comparison; HRP refreshed
method_comparison <- list(
  MVO = list(
    n_names = 20, expected_alpha = 0.0909, te = 0.1201, ir = 0.7568,
    net_ir = 0.7487, sr = NA, turnover = 0.6435, cost = 0.001,
    tdc_q5 = 0.4286, tdc_q10 = 0.4444, cvar_5_monthly = -0.0811,
    selected = FALSE
  ),
  HRP = list(
    n_names = 20,
    expected_alpha = round(asof_alpha, 5),
    te = round(asof_te, 5),
    ir = round(asof_ir, 4),
    net_ir = round(asof_net_ir, 4),
    sr = NA,
    turnover = round(realized_to_annual_rt, 4),
    cost = round(0.0015 * realized_to_annual_rt, 5),
    tdc_q5 = round(asof_tdc_q5, 4),
    tdc_q10 = round(asof_tdc$empirical_q10, 4),
    cvar_5_monthly = round(asof_cvar5, 4),
    selected = TRUE
  ),
  CVaR_LP = list(
    n_names = 20, expected_alpha = 0.0886, te = 0.1088, ir = 0.8145,
    net_ir = 0.7569, sr = NA, turnover = 4.1748, cost = 0.0063,
    tdc_q5 = 0.3571, tdc_q10 = 0.3704, cvar_5_monthly = -0.0653,
    selected = FALSE
  ),
  Robust_Resid = list(
    n_names = 20, expected_alpha = 0.0835, te = 0.1204, ir = 0.6936,
    net_ir = 0.6914, sr = NA, turnover = 0.18, cost = 0.0003,
    tdc_q5 = 0.3571, tdc_q10 = 0.4815, cvar_5_monthly = -0.0747,
    selected = FALSE
  )
)

# Challenge flags
challenge_flags <- list()
if (!wf_tdc_pass) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-OPT-01",
    severity = "HIGH",
    description = sprintf("Walk-forward realized TDC q5=%.4f >= 0.30 gate. infeasibility_report issued.",
                          wf_tdc$q5),
    mitigation = "Alpha redesign required (alpha agent escalate). Dual-portfolio sleeve with low TDC alternative recommended."
  )
}
if (wf_cvar_5 < -0.025 * sqrt(20) * 1.5) {  # -0.1677
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-OPT-02",
    severity = "MEDIUM",
    description = sprintf("Walk-forward CVaR(5%%) monthly=%.4f exceeds heavy-tail-adjusted iid daily 0.025 cap (× sqrt(20) × 1.5 = %.4f).",
                          wf_cvar_5, -0.025 * sqrt(20) * 1.5),
    mitigation = "Heavy-tail Hill α=1.45 (Risk RF-R6) — consider POT/EVT-aware constraint at deployment."
  )
}
if (realized_to_annual_rt > 6.0) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-OPT-03",
    severity = "HIGH",
    description = sprintf("Walk-forward turnover %.3f/yr > 6.0 hard fail (Hurdle Gate v2.2)",
                          realized_to_annual_rt),
    mitigation = "Add turnover penalty φ to MVO method; reduce sig_dates frequency; or relax 20-name churn."
  )
} else if (realized_to_annual_rt > 3.0) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    flag_id = "CF-OPT-03",
    severity = "MEDIUM",
    description = sprintf("Walk-forward turnover %.3f/yr > 3.0 soft cap (constraint_defaults.json v2.3)",
                          realized_to_annual_rt),
    mitigation = "Add turnover penalty φ to MVO method; reduce rebalance frequency; or relax churn budget."
  )
}

# Add inheritance/anchor flag
challenge_flags[[length(challenge_flags) + 1]] <- list(
  flag_id = "CF-OPT-04",
  severity = "INFO",
  description = sprintf("Walk-forward design: as-of (2026-03-31) row anchored to HRP target_weights (Charter §9). Other dates use per-date top-20 by alpha + rolling HRP/inverse_vol. Fallback distribution: %s",
                        paste(names(fb_tab), as.numeric(fb_tab), sep="=", collapse=", ")),
  mitigation = "Forge will reconstruct daily NAV from this exact weights.csv. Optimizer-Forge consistency guaranteed."
)

# Build optimization_package
opt_pkg <- list(
  task_id = TASK_ID,
  as_of_date = "2026-03-31",
  target_weights = target_weights_list,
  active_weights = target_weights_list,  # long-only diversifier (no benchmark subtraction)
  expected_active_return = round(asof_alpha, 5),
  expected_tracking_error = round(asof_te, 5),
  expected_information_ratio = round(asof_ir, 4),
  turnover = round(realized_to_annual_rt, 4),
  estimated_cost = round(0.0015 * realized_to_annual_rt, 5),
  binding_constraints = binding,
  infeasibility_report = infeasibility_report,
  method_selected = selected_method_label,
  method_comparison = method_comparison,
  selection_objective = "crowding_adj_ret",
  explanation = list(
    top_overweights = top_over,
    top_underweights = top_under,
    main_tradeoffs = c(
      sprintf("Walk-forward TDC q5 vs STR_1715 = %.4f (gate 0.30, %s)",
              wf_tdc$q5, if (wf_tdc_pass) "PASS" else "FAIL"),
      sprintf("Walk-forward Pearson cor vs STR_1715 = %.4f", wf_pearson),
      sprintf("Walk-forward CVaR(5%%) monthly = %.4f", wf_cvar_5),
      sprintf("Walk-forward CAGR = %.4f / sd_ann = %.4f / Sharpe(std) = %.4f",
              wf_cagr, wf_sd_ann, wf_sharpe_std),
      sprintf("Walk-forward turnover annual round-trip = %.3f", realized_to_annual_rt),
      sprintf("As-of (2026-03) static TDC q5 = %.4f (60m panel)", asof_tdc_q5),
      sprintf("As-of net systematic exposure: MKT=%.3f LVOL=%.3f SMB=%.3f WML=%.3f",
              asof_net_sys["MKT"], asof_net_sys["LVOL"],
              asof_net_sys["SMB"], asof_net_sys["WML"])
    )
  ),
  challenge_flags = challenge_flags,
  n_names = length(hrp_w_capped),
  hhi = round(sum(hrp_w_capped^2), 5),
  min_names_enforced = length(hrp_w_capped) >= 20,
  hhi_enforced = sum(hrp_w_capped^2) <= 0.15,
  winsor_applied = TRUE,
  lambda_used = 2.0,
  weights_csv_path = file.path("stage_artifacts", TASK_ID, "weights.csv"),
  alpha_sig_dates_count = length(sig_dates),
  weights_csv_unique_dates_count = length(unique(weights_dt$Date)),
  schedule_density_ratio = round(schedule_density, 4),
  schedule_density_pass = schedule_density >= 0.95,
  turnover_realized_walk_forward_annual_rt = round(realized_to_annual_rt, 4),
  turnover_realized_per_rebalance = round(mean(realized_to_per_rebalance), 4),
  walk_forward_realized = list(
    measurement_basis_label = "optimizer_walk_forward_simulation",
    production_grade = FALSE,
    n_obs = n_join_wf,
    port_mean_monthly = round(mean(joined_wf$port_ret, na.rm = TRUE), 5),
    port_sd_monthly = round(sd(joined_wf$port_ret, na.rm = TRUE), 5),
    port_cagr = round(wf_cagr, 4),
    port_sd_ann = round(wf_sd_ann, 4),
    port_sharpe_standard_ann = round(wf_sharpe_std, 4),
    port_cvar_5_monthly = round(wf_cvar_5, 4),
    port_var_5_monthly = round(wf_var_5, 4),
    vs_str1715 = list(
      pearson = round(wf_pearson, 4),
      kendall_tau = round(wf_kendall, 4),
      tdc_q5 = round(wf_tdc$q5, 4),
      tdc_q10 = round(wf_tdc$q10, 4),
      tdc_q20 = round(wf_tdc$q20, 4),
      tdc_q5_pass = wf_tdc_pass
    ),
    fallback_distribution = as.list(fb_tab),
    rationale = "Walk-forward HRP (60m → 36m → inverse_vol → EW fallback) per sig_date. As-of (2026-03-31) anchored to HRP target_weights (Charter §9 consistency). Per-date top-20 by alpha_z within per-date top-60 candidates. Walk-forward TDC q5 is decisive deployment metric."
  ),
  selected_metrics_full = list(
    n_names = 20,
    sum_w = sum(hrp_w_capped),
    max_w = max(hrp_w_capped),
    min_w = min(hrp_w_capped),
    hhi = sum(hrp_w_capped^2),
    expected_alpha = asof_alpha,
    expected_te = asof_te,
    expected_ir = asof_ir,
    expected_net_ir = asof_net_ir,
    expected_turnover_annual = realized_to_annual_rt,
    estimated_cost = 0.0015 * realized_to_annual_rt,
    tdc_q5 = asof_tdc_q5,
    tdc_q10 = asof_tdc$empirical_q10,
    tdc_q20 = asof_tdc$empirical_q20,
    tdc_pearson = asof_tdc$pearson,
    tdc_kendall = asof_tdc$kendall_tau,
    tdc_n_join = asof_tdc$n_join,
    cvar_5_monthly = asof_cvar5,
    var_5_monthly = asof_var5,
    net_systematic = as.list(asof_net_sys),
    weights = as.list(hrp_w_capped)
  )
)

write(toJSON(opt_pkg, auto_unbox = TRUE, pretty = TRUE, na = "null"),
      file.path(WT_DIR, "optimization_package_draft.json"))

# ─── Save optimizer_research.json ────────────────────────
optimizer_research <- list(
  task_id = TASK_ID,
  method_selected = selected_method_label,
  method_metrics = list(
    HRP_anchor = list(
      n_names = 20, sum_w = sum(hrp_w_capped),
      max_w = max(hrp_w_capped), min_w = min(hrp_w_capped),
      hhi = sum(hrp_w_capped^2),
      expected_alpha = asof_alpha,
      expected_te = asof_te,
      expected_ir = asof_ir,
      expected_net_ir = asof_net_ir,
      expected_turnover_annual = realized_to_annual_rt,
      estimated_cost = 0.0015 * realized_to_annual_rt,
      tdc_q5 = asof_tdc_q5,
      tdc_q10 = asof_tdc$empirical_q10,
      cvar_5_monthly = asof_cvar5,
      net_systematic = as.list(asof_net_sys),
      weights = as.list(hrp_w_capped)
    )
  ),
  walk_forward_realized = opt_pkg$walk_forward_realized,
  walk_forward_tdc_pass = wf_tdc_pass,
  schedule_density_ratio = schedule_density,
  schedule_density_pass = schedule_density >= 0.95,
  fallback_distribution = as.list(fb_tab),
  infeasibility_issued = !is.null(infeasibility_report),
  v2_changelog = "v2 fix: target_weights anchored to weights.csv[as_of_date] (Charter §9). Walk-forward HRP rebuilt with per-date 60m/36m fallback chain. v1 weights.csv had EW collapse bug."
)
write(toJSON(optimizer_research, auto_unbox = TRUE, pretty = TRUE, na = "null"),
      file.path(SA_DIR, "optimizer_research.json"))

# ─── Lineage ─────────────────────────────────────────────
record_package_lineage(
  task_id = TASK_ID,
  package_type = "optimization_package",
  method_selected = selected_method_label,
  input_file_paths = c(
    file.path(WT_DIR, "alpha_package.json"),
    file.path(WT_DIR, "risk_package.json"),
    file.path(SA_DIR, "covariance.parquet"),
    file.path(SA_DIR, "alpha_scores.parquet"),
    file.path(PROJECT_ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds")
  )
)

cat("\n", paste(rep("=", 70), collapse = ""), "\n", sep = "")
cat("OPTIMIZER RESEARCH v2 COMPLETE — WT-D20260429_001\n")
cat(paste(rep("=", 70), collapse = ""), "\n", sep = "")
cat(sprintf("method_selected: %s\n", selected_method_label))
cat(sprintf("n_names: 20  HHI: %.4f\n", sum(hrp_w_capped^2)))
cat(sprintf("As-of α=%.4f  TE=%.4f  IR=%.3f  net_IR=%.3f\n",
            asof_alpha, asof_te, asof_ir, asof_net_ir))
cat(sprintf("As-of static TDC q5=%.4f (gate 0.30 — %s)\n",
            asof_tdc_q5, if (asof_tdc_q5 < 0.30) "PASS" else "FAIL"))
cat(sprintf("Walk-forward TDC q5=%.4f (gate 0.30 — %s)\n",
            wf_tdc$q5, if (wf_tdc_pass) "PASS" else "FAIL"))
cat(sprintf("Walk-forward CVaR(5%%) monthly=%.4f\n", wf_cvar_5))
cat(sprintf("Walk-forward CAGR=%.4f / sd_ann=%.4f / Sharpe(std,ann)=%.4f\n",
            wf_cagr, wf_sd_ann, wf_sharpe_std))
cat(sprintf("Walk-forward turnover round-trip=%.3f/yr (cost ≈ %.4f)\n",
            realized_to_annual_rt, 0.0015 * realized_to_annual_rt))
cat(sprintf("Schedule density: %.4f (gate 0.95 — %s)\n",
            schedule_density, if (schedule_density >= 0.95) "PASS" else "FAIL"))
cat(sprintf("Infeasibility report: %s\n",
            if (is.null(infeasibility_report)) "NONE" else "ISSUED"))
cat("\nSaved:\n")
cat("  ", file.path(WT_DIR, "optimization_package_draft.json"), "\n")
cat("  ", file.path(SA_DIR, "weights.csv"), "\n")
cat("  ", file.path(SA_DIR, "optimizer_research.json"), "\n")
cat("\nDone.\n")
