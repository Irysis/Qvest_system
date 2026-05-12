#==============================================================================
# WT-D20260508_010 Forge Step 1
#  (a) cov_eigen drift audit (Codex C1: file binary κ vs Risk supplement κ=202.62)
#  (b) R14_DUVOL alpha-sleeve net monthly returns (60 sig_dates 2021-05~2026-04)
#      using weights.csv × stock forward returns × 15bps cost
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

WT_ID <- "WT-D20260508_010"
PKG_DIR <- file.path("qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path("stage_artifacts", WT_ID)
OUT_DIR <- file.path(SA_DIR, "forge")
COST_BPS <- 15  # one-way

cat("================================================================\n")
cat("[FORGE STEP 1] cov_eigen drift + R14_DUVOL sleeve returns\n")
cat("================================================================\n")

# ----------------------------------------------------------------------
# (a) cov_eigen drift audit
# ----------------------------------------------------------------------
cov_path <- file.path(SA_DIR, "covariance.parquet")
cat("\n[1a] cov_eigen drift audit\n")
cat("    Reading", cov_path, "\n")
cov_dt <- as.data.table(read_parquet(cov_path))
cat("    cov_dt nrow x ncol =", nrow(cov_dt), "x", ncol(cov_dt), "\n")
cat("    First 3 col names:", head(names(cov_dt), 3), "\n")

# Reconstruct symmetric matrix
if ("Ticker" %in% names(cov_dt) || "ticker" %in% names(cov_dt)) {
  rn_col <- if ("Ticker" %in% names(cov_dt)) "Ticker" else "ticker"
  rn <- cov_dt[[rn_col]]
  cov_mat <- as.matrix(cov_dt[, !rn_col, with = FALSE])
} else {
  # Square matrix without explicit ticker col (348x348)
  rn <- names(cov_dt)
  cov_mat <- as.matrix(cov_dt)
}
rownames(cov_mat) <- rn
colnames(cov_mat) <- rn

cat("    cov_mat dim:", dim(cov_mat), "\n")
cat("    Symmetric:", isSymmetric(cov_mat, tol = 1e-8), "\n")

eig <- eigen(cov_mat, symmetric = TRUE, only.values = TRUE)
ev <- eig$values
ev_min <- min(ev); ev_max <- max(ev); cond_num <- ev_max / ev_min
cat(sprintf("    lambda_min = %.6e\n", ev_min))
cat(sprintf("    lambda_max = %.6e\n", ev_max))
cat(sprintf("    cond_exact = lambda_max/lambda_min = %.4f\n", cond_num))

risk_kappa_supp <- 202.62  # from Risk supplement
codex_alleged_cond <- 2165.76  # from Codex C1
drift_vs_supp <- cond_num - risk_kappa_supp
drift_vs_codex <- cond_num - codex_alleged_cond

drift_diagnosis <- if (abs(drift_vs_supp) < 50) {
  "NEGLIGIBLE_drift_with_risk_supplement"
} else if (abs(drift_vs_codex) < 50) {
  "DRIFT_CONFIRMED_codex_C1_correct"
} else {
  "DRIFT_DETECTED_third_value"
}
cat(sprintf("    drift vs Risk κ=%.2f: %.2f\n", risk_kappa_supp, drift_vs_supp))
cat(sprintf("    drift vs Codex alleged %.2f: %.2f\n", codex_alleged_cond, drift_vs_codex))
cat(sprintf("    diagnosis: %s\n", drift_diagnosis))

cov_drift_log <- list(
  cov_path = cov_path,
  n_assets = nrow(cov_mat),
  is_symmetric = isSymmetric(cov_mat, tol = 1e-8),
  lambda_min = ev_min,
  lambda_max = ev_max,
  cond_exact_forge_recompute = round(cond_num, 4),
  risk_supplement_kappa = risk_kappa_supp,
  codex_C1_alleged_cond = codex_alleged_cond,
  drift_pp_vs_risk_supplement = round(drift_vs_supp, 4),
  drift_pp_vs_codex_alleged = round(drift_vs_codex, 4),
  diagnosis = drift_diagnosis,
  decision = "covariance.parquet binary used as single source of truth (Codex C1 acknowledged via independent recompute)"
)
write_json(cov_drift_log, file.path(SA_DIR, "forge", "cov_eigen_recompute.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("    [saved] forge/cov_eigen_recompute.json\n")

# ----------------------------------------------------------------------
# (b) R14_DUVOL alpha-sleeve net monthly returns
# ----------------------------------------------------------------------
cat("\n[1b] R14_DUVOL alpha-sleeve returns (60 sig_dates 2021-05~2026-04)\n")
weights <- fread(file.path(SA_DIR, "weights.csv"))
weights[, sig_date := as.Date(sig_date)]
weights[, as_of_date := as.Date(as_of_date)]
sig_dates <- sort(unique(weights$sig_date))
cat("    weights.csv: n_rows =", nrow(weights), "/ unique sig_dates =", length(sig_dates), "\n")
cat("    range:", as.character(min(sig_dates)), "~", as.character(max(sig_dates)), "\n")

# Load rawdata for stock prices
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)

# For each sig_date pair (k -> k+1), compute portfolio return = sum(w_k * (P_{k+1}/P_k - 1))
# Last sig_date 2026-04-30 has no forward (the as-of forecast period); we exclude it from realized PnL
sleeve_rets <- numeric(length(sig_dates) - 1L)
sleeve_dates <- as.Date(rep(NA, length(sig_dates) - 1L))
sleeve_turnovers <- numeric(length(sig_dates) - 1L)
n_holdings_per <- integer(length(sig_dates) - 1L)

prev_w <- NULL
for (k in seq_len(length(sig_dates) - 1L)) {
  d_now <- sig_dates[k]
  d_next <- sig_dates[k + 1]
  w_k <- weights[sig_date == d_now, .(Ticker, weight)]

  # Stock returns from d_now to d_next
  p_now <- rd[Date == d_now, .(Ticker, Close_now = Close)]
  p_next <- rd[Date == d_next, .(Ticker, Close_next = Close)]
  px <- merge(p_now, p_next, by = "Ticker")
  px[, ret := Close_next / Close_now - 1]
  port <- merge(w_k, px[, .(Ticker, ret)], by = "Ticker", all.x = TRUE)
  if (any(is.na(port$ret))) {
    n_drop <- sum(is.na(port$ret))
    cat(sprintf("    [warn] sig_date %s -> %s: %d/%d names missing ret (delisted?)\n",
                d_now, d_next, n_drop, nrow(port)))
    # Renormalize remaining weights
    port <- port[!is.na(ret)]
    port[, weight := weight / sum(weight)]
  }
  ret_gross <- sum(port$weight * port$ret, na.rm = TRUE)

  # Turnover (one-way) — at d_now: if k==1, full deploy 1.0 turnover; else half-half-diff vs prev_w
  if (is.null(prev_w)) {
    to_oneway <- 1.0  # initial deploy
  } else {
    # union of names
    all_names <- union(prev_w$Ticker, w_k$Ticker)
    p_old <- merge(data.table(Ticker = all_names),
                   prev_w[, .(Ticker, w_old = weight)], by = "Ticker", all.x = TRUE)
    p_old[is.na(w_old), w_old := 0]
    p_new <- merge(p_old, w_k[, .(Ticker, w_new = weight)], by = "Ticker", all.x = TRUE)
    p_new[is.na(w_new), w_new := 0]
    to_oneway <- 0.5 * sum(abs(p_new$w_new - p_new$w_old))
  }

  # Net return: gross - 2*turnover_oneway*15bps (round-trip)
  cost <- 2 * to_oneway * (COST_BPS / 1e4)
  ret_net <- ret_gross - cost

  sleeve_rets[k] <- ret_net
  sleeve_dates[k] <- d_next  # measured at end-of-period
  sleeve_turnovers[k] <- to_oneway
  n_holdings_per[k] <- nrow(w_k)
  prev_w <- w_k
}

sleeve_dt <- data.table(
  date = sleeve_dates,
  ret_gross = sleeve_rets + 2 * sleeve_turnovers * (COST_BPS / 1e4),
  ret_net = sleeve_rets,
  turnover = sleeve_turnovers,
  cost_ret = -2 * sleeve_turnovers * (COST_BPS / 1e4),
  n_holdings = n_holdings_per
)
fwrite(sleeve_dt, file.path(SA_DIR, "forge", "r14_duvol_sleeve_returns.csv"))
cat(sprintf("    sleeve n_periods = %d\n", nrow(sleeve_dt)))
cat(sprintf("    sleeve mean ret_net (m) = %.6f\n", mean(sleeve_dt$ret_net)))
cat(sprintf("    sleeve sd ret_net (m) = %.6f\n", sd(sleeve_dt$ret_net)))
cat(sprintf("    sleeve mean turnover (one-way) = %.4f\n", mean(sleeve_dt$turnover)))
cat(sprintf("    sleeve mean cost (m) = %.4f bps\n",
            mean(sleeve_dt$cost_ret) * 1e4))

# Annualized figures
mu_ann <- mean(sleeve_dt$ret_net) * 12
sd_ann <- sd(sleeve_dt$ret_net) * sqrt(12)
sr_ann <- mu_ann / sd_ann
cat(sprintf("    sleeve SR_annualized (mu/sigma * sqrt12) = %.4f\n", sr_ann))
cat(sprintf("    sleeve mu_ann = %.4f / sd_ann = %.4f\n", mu_ann, sd_ann))

cat("\n[FORGE STEP 1] DONE\n")
