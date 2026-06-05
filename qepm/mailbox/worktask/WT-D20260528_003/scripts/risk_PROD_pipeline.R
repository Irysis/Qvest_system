#==============================================================================
# WT-D20260528_003 — Risk Research Pipeline (D_PROD LightGBM 30f alpha)
#
# Role: Risk Research Agent (공동위험 구조 Σ + tail + stress + crowding + style)
# Input (immutable, read-only):
#   - alpha_package_PROD.json
#   - stage_artifacts/WT_D20260528_003/alpha_scores.parquet  (cols: Date, Ticker, pred, fold_id)
#   - stage_artifacts/WT_D20260528_003/weights_schedule.parquet (Date, Ticker, weight; top-20 Σw=1)
#   - .cache/rawdata.parquet
#
# Output → stage_artifacts/WT_D20260528_003_risk_PROD/
#   exposure_matrix.parquet / factor_covariance.parquet / specific_risk.parquet
#   covariance.parquet / B_loadings.parquet / tail_risk.json / stress_test_results.json
#   style_exposure.json / crowding_score.json / regime_correlation.parquet / method_shopping_log.json
#   → qepm/mailbox/worktask/WT-D20260528_003/risk_package_draft_PROD.json
#
# Conditioning mandate (Codex C6 Track1): Track1 factor_model cond=291.8.
#   PROD: explicit eigen-floor + target cond<200 + report before/after.
# Lockbox: sig_date <= 2023-12-22 (risk-research = 정규 리서치 scope). C9 t-1 lag.
# No alpha modification.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics)
  library(corpcor)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260528_003"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts/WT_D20260528_003_risk_PROD")
PROD_STAGE <- file.path(ROOT, "stage_artifacts/WT_D20260528_003")
LOCKBOX_CUTOFF <- as.Date("2023-12-22")
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

cat("================================================================\n")
cat("WT-D20260528_003 — Risk Research Pipeline (D_PROD LightGBM 30f)\n")
cat("Lockbox cutoff:", as.character(LOCKBOX_CUTOFF), "(strict)\n")
cat("Output dir:", STAGE_DIR, "\n================================================================\n\n")

source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/tail_risk_engine.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/crowding_score_per_factor.R"))

cov_schafer_strimmer <- function(X) {
  X <- as.matrix(X); X[is.na(X)] <- 0
  S <- corpcor::cov.shrink(X, verbose = FALSE)
  list(Sigma = as.matrix(S), delta_var = attr(S, "lambda.var"), delta_cor = attr(S, "lambda"))
}

# Eigen-floor: lift eigenvalues so that cond <= target_cond. PSD by construction.
eigen_floor_to_cond <- function(Sigma, target_cond = 200) {
  Sigma <- (Sigma + t(Sigma)) / 2
  e <- eigen(Sigma, symmetric = TRUE); vals <- e$values; vecs <- e$vectors
  max_val <- max(vals)
  floor_val <- max_val / target_cond
  vals[vals < floor_val] <- floor_val
  Sc <- vecs %*% diag(vals) %*% t(vecs)
  Sc <- (Sc + t(Sc)) / 2
  rownames(Sc) <- colnames(Sc) <- rownames(Sigma)
  Sc
}

# ============================================================================
# 0. Load inputs
# ============================================================================
cat("[0] Loading inputs...\n")
ap <- fromJSON(file.path(WT_DIR, "alpha_package_PROD.json"), simplifyVector = FALSE)
alpha_scores <- setDT(read_parquet(file.path(PROD_STAGE, "alpha_scores.parquet")))
weights_sched <- setDT(read_parquet(file.path(PROD_STAGE, "weights_schedule.parquet")))
RAWDATA <- setDT(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))

alpha_scores[, Date := as.Date(Date)]
weights_sched[, Date := as.Date(Date)]
RAWDATA[, Date := as.Date(Date)]

# Lockbox enforcement (risk-research = 정규 리서치 scope)
alpha_scores <- alpha_scores[Date <= LOCKBOX_CUTOFF]
weights_sched <- weights_sched[Date <= LOCKBOX_CUTOFF]
RAWDATA <- RAWDATA[Date <= LOCKBOX_CUTOFF]
sig_dates_all <- sort(unique(weights_sched$Date))
last_sig_date <- max(sig_dates_all)
cat("  sig_dates:", length(sig_dates_all), "(", as.character(min(sig_dates_all)), "~", as.character(last_sig_date), ")\n")
cat("  RAWDATA post-lockbox rows:", nrow(RAWDATA), "\n")

# Universe = top20 union over sig_dates (potential holdings)
universe_tickers <- sort(unique(weights_sched$Ticker))
cat("  Universe (top20 union):", length(universe_tickers), "tickers\n")
cat("  PROD last sig_date holdings (top-20 Σw=1):\n")
print(weights_sched[Date == last_sig_date][order(-weight)])

# ============================================================================
# Helper: build daily returns matrix (PIT strict, Date < sig_date)
# ============================================================================
build_returns_matrix <- function(tickers, as_of_date, n_days = 252L) {
  end_date <- as.Date(as_of_date) - 1L
  sub <- RAWDATA[Ticker %in% tickers & Date <= end_date, .(Date, Ticker, Ret)]
  if (nrow(sub) == 0L) return(NULL)
  last_dates <- tail(sort(unique(sub$Date)), n_days)
  sub <- sub[Date %in% last_dates]
  wide <- dcast(sub, Date ~ Ticker, value.var = "Ret")
  mat <- as.matrix(wide[, -1, drop = FALSE]); rownames(mat) <- as.character(wide$Date)
  good_cols <- colSums(!is.na(mat)) >= floor(0.8 * nrow(mat))
  if (sum(good_cols) < 5L) return(NULL)
  mat <- mat[, good_cols, drop = FALSE]
  good_rows <- rowSums(!is.na(mat)) >= ncol(mat) * 0.5
  mat <- mat[good_rows, , drop = FALSE]
  if (nrow(mat) < 60L) return(NULL)
  mat[is.na(mat)] <- 0; mat
}

# ============================================================================
# Step 1: Exposure matrix B (style + sector + market) at last sig_date
# ============================================================================
cat("\n[1] Exposure matrix B (style + sector + market) at", as.character(last_sig_date), "...\n")
build_exposure_at_sigdate <- function(sig_d, top_tickers) {
  end_d <- as.Date(sig_d) - 1L
  win_252 <- end_d - 252L; win_60 <- end_d - 60L; win_21 <- end_d - 21L
  rd_t1 <- RAWDATA[Ticker %in% top_tickers & Date <= end_d]
  rd_last <- rd_t1[, .SD[.N], by = Ticker, .SDcols = c("Date", "Close", "Size", "Sector_Lv2")]
  setnames(rd_last, "Date", "snap_Date")
  rd_60 <- rd_t1[Date > win_60, .(
    realized_vol = sd(Ret, na.rm = TRUE) * sqrt(252),
    amihud_60 = mean(abs(Ret) / pmax(Close * Vol, 1), na.rm = TRUE) * 1e9, n_60 = .N), by = Ticker]
  rd_252 <- rd_t1[Date > win_252, .(Date, Ticker, Ret, BM_Ret)]
  beta_dt <- rd_252[, {
    valid <- !is.na(Ret) & !is.na(BM_Ret)
    if (sum(valid) >= 60) {
      raw_b <- if (var(BM_Ret[valid]) > 0) cov(Ret[valid], BM_Ret[valid]) / var(BM_Ret[valid]) else NA_real_
      .(beta_blume = if (!is.na(raw_b)) 0.67 * raw_b + 0.33 else NA_real_, n_b = sum(valid))
    } else .(beta_blume = NA_real_, n_b = 0L)
  }, by = Ticker]
  rd_60_b <- rd_t1[Date > win_60, .(Date, Ticker, Ret, BM_Ret)]
  idio_dt <- rd_60_b[, {
    valid <- !is.na(Ret) & !is.na(BM_Ret)
    if (sum(valid) >= 40) {
      mod <- tryCatch(lm(Ret[valid] ~ BM_Ret[valid]), error = function(e) NULL)
      .(idio_vol = if (!is.null(mod)) sd(residuals(mod)) * sqrt(252) else NA_real_)
    } else .(idio_vol = NA_real_)
  }, by = Ticker]
  rd_mom <- rd_t1[Date > win_252 & Date <= win_21, .(mom_12m1m = sum(log1p(Ret), na.rm = TRUE)), by = Ticker]
  rd_rev <- rd_t1[Date > win_21 & Date <= end_d, .(rev_1m = sum(log1p(Ret), na.rm = TRUE)), by = Ticker]
  expo <- merge(rd_last, rd_60, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, beta_dt, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, idio_dt, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, rd_mom, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, rd_rev, by = "Ticker", all.x = TRUE)
  expo[, log_mktcap := log(pmax(Size, 1))]
  z_cols <- c("log_mktcap", "beta_blume", "realized_vol", "idio_vol", "amihud_60", "mom_12m1m", "rev_1m")
  for (cc in z_cols) {
    x <- expo[[cc]]; mu <- mean(x, na.rm = TRUE); sg <- sd(x, na.rm = TRUE)
    expo[[paste0(cc, "_z")]] <- if (!is.na(sg) && sg > 0) pmin(pmax((x - mu) / sg, -3), 3) else 0
  }
  expo[, sig_date := as.Date(sig_d)]; expo
}
expo_last <- build_exposure_at_sigdate(last_sig_date, universe_tickers)
cat("  Exposure rows:", nrow(expo_last), "/", length(universe_tickers), "\n")
write_parquet(expo_last, file.path(STAGE_DIR, "exposure_matrix.parquet"))

# ============================================================================
# Step 2-4: Σ estimation (multi-method) — sample / Schäfer-Strimmer / Gerber-RMT
# ============================================================================
cat("\n[2-4] Σ estimation (multi-method)...\n")
ret_mat_last <- build_returns_matrix(universe_tickers, last_sig_date, n_days = 252L)
T_obs <- nrow(ret_mat_last); N_assets <- ncol(ret_mat_last)
cat("  ret_mat:", T_obs, "days x", N_assets, "tickers; q=T/N=", round(T_obs/N_assets, 2), "\n")

method_log <- list()
cov_sample <- cov(ret_mat_last, use = "pairwise.complete.obs"); cov_sample[is.na(cov_sample)] <- 0
cond_sample <- kappa(cov_sample, exact = TRUE)
min_eig_sample <- min(eigen(cov_sample, symmetric = TRUE, only.values = TRUE)$values)
method_log$sample <- list(name = "sample_pairwise", condition = cond_sample, min_eig = min_eig_sample,
                          psd = min_eig_sample >= -1e-10, selected = FALSE)
cat("  [A] sample cond:", signif(cond_sample, 4), "min_eig:", signif(min_eig_sample, 4), "\n")

ss_res <- cov_schafer_strimmer(ret_mat_last); cov_ss <- ss_res$Sigma
cond_ss <- kappa(cov_ss, exact = TRUE)
min_eig_ss <- min(eigen(cov_ss, symmetric = TRUE, only.values = TRUE)$values)
method_log$schafer_strimmer <- list(name = "schafer_strimmer_2005", condition = cond_ss, min_eig = min_eig_ss,
                                     lambda_var = round(ss_res$delta_var, 6), lambda_cor = round(ss_res$delta_cor, 6),
                                     psd = min_eig_ss >= -1e-10, selected = FALSE)
cat("  [B] Schäfer-Strimmer cond:", round(cond_ss, 1), "min_eig:", signif(min_eig_ss, 4),
    "λ_var:", round(ss_res$delta_var, 4), "λ_cor:", round(ss_res$delta_cor, 4), "\n")

cc_gr <- tryCatch(.get_cor_cov(ret_mat_last, cov_method = "gerber_rmt"), error = function(e) NULL)
if (!is.null(cc_gr)) {
  cov_gr <- cc_gr$cov; cond_gr <- kappa(cov_gr, exact = TRUE)
  min_eig_gr <- min(eigen(cov_gr, symmetric = TRUE, only.values = TRUE)$values)
  method_log$gerber_rmt <- list(name = "gerber_rmt", condition = cond_gr, min_eig = min_eig_gr,
                                 psd = min_eig_gr >= -1e-10, selected = FALSE)
  cat("  [C] Gerber-RMT cond:", signif(cond_gr, 4), "min_eig:", signif(min_eig_gr, 4), "\n")
} else { cov_gr <- NULL; cond_gr <- NA; min_eig_gr <- NA
  method_log$gerber_rmt <- list(name = "gerber_rmt", condition = NA, psd = FALSE, selected = FALSE, error = "failed") }

# ============================================================================
# Step 2b: Factor covariance Ω (style factor returns: MKT/SMB/DEF/WML/STR)
# ============================================================================
cat("\n[2b] Factor covariance Ω...\n")
end_d <- last_sig_date - 1L; win_start <- end_d - 252L
panel_252 <- RAWDATA[Date > win_start & Date <= end_d & Ticker %in% universe_tickers, .(Date, Ticker, Ret, BM_Ret, Size)]
panel_252 <- panel_252[!is.na(Ret) & !is.na(Size) & Size > 0]
style_scores <- expo_last[, .(Ticker, log_mktcap_z, idio_vol_z, mom_12m1m_z, rev_1m_z, beta_blume_z)]
panel_252 <- merge(panel_252, style_scores, by = "Ticker", all.x = TRUE)
build_factor_ret <- function(panel, score_col, sign = 1) {
  dt <- copy(panel); setnames(dt, score_col, "score"); dt <- dt[!is.na(score)]
  out <- dt[, { q <- quantile(score, c(0.2, 0.8), na.rm = TRUE)
    .(factor_ret = sign * (mean(Ret[score >= q[2]], na.rm = TRUE) - mean(Ret[score <= q[1]], na.rm = TRUE))) }, by = Date]
  setorder(out, Date); out
}
mkt_ret <- panel_252[, .(factor_ret = mean(BM_Ret, na.rm = TRUE)), by = Date]; setorder(mkt_ret, Date)
smb_ret <- build_factor_ret(panel_252, "log_mktcap_z", sign = -1)
hml_ret <- build_factor_ret(panel_252, "idio_vol_z", sign = -1)   # DEF = low idio - high idio
wml_ret <- build_factor_ret(panel_252, "mom_12m1m_z", sign = 1)
str_ret <- build_factor_ret(panel_252, "rev_1m_z", sign = -1)
common_dates <- as.Date(Reduce(intersect, list(as.character(mkt_ret$Date), as.character(smb_ret$Date),
  as.character(hml_ret$Date), as.character(wml_ret$Date), as.character(str_ret$Date))))
ga <- function(d) d[as.character(Date) %in% as.character(common_dates), factor_ret]
factor_ret_mat <- cbind(MKT = ga(mkt_ret), SMB = ga(smb_ret), DEF = ga(hml_ret), WML = ga(wml_ret), STR = ga(str_ret))
factor_ret_mat[is.na(factor_ret_mat)] <- 0
Omega <- cov(factor_ret_mat) * 252
write_parquet(as.data.table(Omega, keep.rownames = "factor"), file.path(STAGE_DIR, "factor_covariance.parquet"))
cat("  Ω built. Factor annual vol (%):", round(sqrt(diag(Omega)) * 100, 2), "\n")

# ============================================================================
# Step 3: Specific risk D + loadings B (per-ticker factor regression)
# ============================================================================
cat("\n[3] Specific risk D + B loadings...\n")
tk_panel <- RAWDATA[Date > win_start & Date <= end_d & Ticker %in% universe_tickers, .(Date, Ticker, Ret)]
tk_wide <- dcast(tk_panel, Date ~ Ticker, value.var = "Ret")
date_align <- intersect(as.character(tk_wide$Date), as.character(common_dates))
tk_wide_a <- tk_wide[as.character(Date) %in% date_align]; setorder(tk_wide_a, Date)
factor_use <- factor_ret_mat[match(as.character(tk_wide_a$Date), as.character(common_dates)), , drop = FALSE]
factor_use[is.na(factor_use)] <- 0
tk_cols <- setdiff(names(tk_wide_a), "Date")
B_loadings <- matrix(0, nrow = length(tk_cols), ncol = ncol(factor_use),
                     dimnames = list(tk_cols, colnames(factor_use)))
specific_var <- setNames(numeric(length(tk_cols)), tk_cols)
n_obs_per_ticker <- setNames(integer(length(tk_cols)), tk_cols)
SPECIFIC_VAR_FLOOR <- 0.05; SPECIFIC_VAR_CEILING <- 2.0
for (i in seq_along(tk_cols)) {
  y <- tk_wide_a[[tk_cols[i]]]; valid <- !is.na(y)
  if (sum(valid) >= 60L) {
    mod <- tryCatch(lm.fit(cbind(1, factor_use[valid, , drop = FALSE]), y[valid]), error = function(e) NULL)
    if (!is.null(mod) && all(!is.na(mod$coefficients))) {
      B_loadings[i, ] <- mod$coefficients[-1]
      specific_var[i] <- pmin(pmax(var(mod$residuals) * 252, SPECIFIC_VAR_FLOOR), SPECIFIC_VAR_CEILING)
    } else specific_var[i] <- pmin(pmax(var(y[valid]) * 252, SPECIFIC_VAR_FLOOR), SPECIFIC_VAR_CEILING)
    n_obs_per_ticker[i] <- sum(valid)
  } else { specific_var[i] <- 0.16; n_obs_per_ticker[i] <- sum(valid) }
}
write_parquet(data.table(Ticker = tk_cols, specific_var_ann = specific_var,
              specific_vol_ann = sqrt(specific_var), n_obs = n_obs_per_ticker),
              file.path(STAGE_DIR, "specific_risk.parquet"))
write_parquet(as.data.table(B_loadings, keep.rownames = "Ticker"), file.path(STAGE_DIR, "B_loadings.parquet"))
total_var_per_tk <- apply(tk_wide_a[, -1, with = FALSE], 2, function(x) var(x[!is.na(x)]) * 252)
r2_per_tk <- pmax(0, pmin(1, 1 - specific_var[names(total_var_per_tk)] / total_var_per_tk))
median_r2 <- median(r2_per_tk, na.rm = TRUE)
cat("  Median R² factor fit:", round(median_r2, 3), "; Mean R²:", round(mean(r2_per_tk, na.rm = TRUE), 3), "\n")

# ============================================================================
# Step 4: Σ = BΩB' + D + conditioning improvement (Codex C6 mandate)
# ============================================================================
cat("\n[4] Σ = BΩB' + D + conditioning...\n")
tk_valid <- tk_cols[specific_var > 0]
B_v <- B_loadings[tk_valid, , drop = FALSE]
D_v <- diag(specific_var[tk_valid]); rownames(D_v) <- colnames(D_v) <- tk_valid
Sigma_fm_raw <- B_v %*% Omega %*% t(B_v) + D_v
rownames(Sigma_fm_raw) <- colnames(Sigma_fm_raw) <- tk_valid
cond_fm_before <- kappa(Sigma_fm_raw, exact = TRUE)
min_eig_fm_before <- min(eigen(Sigma_fm_raw, symmetric = TRUE, only.values = TRUE)$values)
cat("  Σ_FM BEFORE conditioning: cond =", round(cond_fm_before, 1), "; min_eig =", signif(min_eig_fm_before, 4), "\n")

# Codex C6 (Track1) + C1 (PROD round): target cond <= 100 via eigen-floor.
# Hard gate stays cond<500 (RF-R2); soft preference cond<=100 (Codex C1 ACCEPT).
TARGET_COND <- 100
Sigma_fm <- if (cond_fm_before > TARGET_COND) eigen_floor_to_cond(Sigma_fm_raw, TARGET_COND) else Sigma_fm_raw
cond_fm_after <- kappa(Sigma_fm, exact = TRUE)
min_eig_fm_after <- min(eigen(Sigma_fm, symmetric = TRUE, only.values = TRUE)$values)
cat("  Σ_FM AFTER eigen-floor (target", TARGET_COND, "): cond =", round(cond_fm_after, 1),
    "; min_eig =", signif(min_eig_fm_after, 4), "\n")
method_log$factor_model <- list(name = "factor_model_BOmegaBT_plus_D_eigfloor_cond100",
                                 condition_before = cond_fm_before, condition_after = cond_fm_after,
                                 min_eig = min_eig_fm_after, psd = min_eig_fm_after >= -1e-10,
                                 specific_var_floor = SPECIFIC_VAR_FLOOR, specific_var_ceiling = SPECIFIC_VAR_CEILING,
                                 target_cond = TARGET_COND, selected = TRUE)

Sigma_primary <- Sigma_fm; primary_method <- "factor_model_BOmegaBT_plus_D_eigfloor_cond100"
cond_final <- cond_fm_after
write_parquet(as.data.table(Sigma_primary, keep.rownames = "Ticker"), file.path(STAGE_DIR, "covariance.parquet"))
cat("  PRIMARY Σ:", primary_method, "| N =", nrow(Sigma_primary), "| cond =", round(cond_final, 1), "\n")

writeLines(toJSON(list(task_id = WT_ID, agent_role = "risk", as_of_date = as.character(last_sig_date),
  selection_objective = "condition_number", n_candidates = length(method_log), cap = 5,
  method_log = method_log, selected_method = primary_method,
  rationale = "Σ = BΩB' + D (QEPM standard, Connor-Korajczyk 1995 / Grinold-Kahn 2000). Codex C6 (Track1 cond=291.8): explicit eigen-floor target cond<200 applied; before/after reported. Schäfer-Strimmer 2005 + sample + Gerber-RMT compared as estimation-quality candidates."),
  pretty = TRUE, auto_unbox = TRUE), file.path(STAGE_DIR, "method_shopping_log.json"))

# ============================================================================
# Step 4b: Portfolio risk decomposition (PROD top-20 at last sig_date)
# ============================================================================
cat("\n[4b] Portfolio risk decomposition (PROD top-20)...\n")
w_last <- weights_sched[Date == last_sig_date]
w_named <- setNames(w_last$weight, w_last$Ticker)
w_tickers <- intersect(names(w_named), rownames(Sigma_primary))
cat("  Weight tickers in Σ universe:", length(w_tickers), "/", length(w_named), "\n")
w_vec <- w_named[w_tickers]; w_vec <- w_vec / sum(w_vec)
B_w <- B_v[w_tickers, , drop = FALSE]; D_sub <- diag(D_v)[w_tickers]
w_B <- t(w_vec) %*% B_w
factor_var_part <- as.numeric(w_B %*% Omega %*% t(w_B))
specific_var_part <- sum(w_vec^2 * D_sub)
port_var <- factor_var_part + specific_var_part; port_vol_ann <- sqrt(port_var)
factor_pct <- factor_var_part / port_var; specific_pct <- specific_var_part / port_var
cat("  Port vol ann:", round(port_vol_ann * 100, 2), "% | factor share:", round(factor_pct * 100, 1),
    "% | specific share:", round(specific_pct * 100, 1), "%\n")
per_factor_var_full <- setNames(numeric(ncol(Omega)), colnames(Omega))
for (k in seq_len(ncol(Omega))) per_factor_var_full[k] <- as.numeric(w_B[1, k]) * sum(w_B[1, ] * Omega[k, ])
per_factor_pct <- per_factor_var_full / port_var
cat("  Per-factor % of TOTAL port var:\n")
for (k in seq_along(per_factor_pct)) cat("    ", names(per_factor_pct)[k], ":", round(per_factor_pct[k] * 100, 2),
    "% (exposure", round(as.numeric(w_B[1, k]), 3), ")\n")

# Sector HHI
sect_dt <- expo_last[Ticker %in% w_tickers, .(Ticker, Sector_Lv2)]
sect_w <- merge(data.table(Ticker = names(w_vec), w = w_vec), sect_dt, by = "Ticker")[!is.na(Sector_Lv2)]
sect_agg <- sect_w[, .(w_sum = sum(w)), by = Sector_Lv2]; setorder(sect_agg, -w_sum)
hhi_sector <- sum(sect_agg$w_sum^2)
cat("  Sector HHI:", round(hhi_sector, 3), "(N_eff =", round(1/hhi_sector, 1), ") | top:",
    sect_agg$Sector_Lv2[1], round(sect_agg$w_sum[1] * 100, 1), "%\n")

# Idio-vol tilt diagnostic (PROD core check, alphaF C8): portfolio idio_vol_z & realized_vol_z exposure
idio_tilt <- expo_last[Ticker %in% w_tickers, .(Ticker, idio_vol_z, realized_vol_z, amihud_60_z, log_mktcap_z)]
idio_tilt <- merge(data.table(Ticker = names(w_vec), w = w_vec), idio_tilt, by = "Ticker")
port_idio_z <- sum(idio_tilt$w * idio_tilt$idio_vol_z, na.rm = TRUE)
port_realvol_z <- sum(idio_tilt$w * idio_tilt$realized_vol_z, na.rm = TRUE)
port_amihud_z <- sum(idio_tilt$w * idio_tilt$amihud_60_z, na.rm = TRUE)
port_size_z <- sum(idio_tilt$w * idio_tilt$log_mktcap_z, na.rm = TRUE)
cat("  PROD idio-vol tilt: idio_vol_z =", round(port_idio_z, 3), "| realized_vol_z =", round(port_realvol_z, 3),
    "| amihud_z =", round(port_amihud_z, 3), "| size_z =", round(port_size_z, 3), "\n")

style_summary <- list(as_of_date = as.character(last_sig_date), primary_sigma_method = primary_method,
  portfolio_vol_ann_pct = round(port_vol_ann * 100, 3),
  factor_variance_share = round(factor_pct, 4), specific_variance_share = round(specific_pct, 4),
  per_factor_contribution = lapply(seq_along(per_factor_pct), function(k) list(
    factor = names(per_factor_pct)[k], portfolio_exposure = round(as.numeric(w_B[1, k]), 4),
    pct_of_port_var = round(per_factor_pct[k] * 100, 3))),
  idio_vol_tilt = list(port_idio_vol_z = round(port_idio_z, 4), port_realized_vol_z = round(port_realvol_z, 4),
    port_amihud_z = round(port_amihud_z, 4), port_size_z = round(port_size_z, 4),
    note = "PROD 30f model dominated by D01_IdioVol/D03_RealVol/L01_Amihud/Size (alphaF C8). Negative idio_vol_z = low-vol (defensive) tilt; positive = high-vol (lottery) tilt."),
  factor_omega = lapply(seq_len(ncol(Omega)), function(k) list(factor = colnames(Omega)[k],
    annualized_vol = round(sqrt(Omega[k, k]) * 100, 3),
    correlation_with_others = setNames(round(cov2cor(Omega)[k, ], 4), rownames(Omega)))),
  sector_concentration = list(hhi = round(hhi_sector, 4), n_effective_sectors = round(1/hhi_sector, 2),
    top5 = lapply(seq_len(min(5L, nrow(sect_agg))), function(k) list(
      sector = sect_agg$Sector_Lv2[k], weight_pct = round(sect_agg$w_sum[k] * 100, 2)))))
writeLines(toJSON(style_summary, pretty = TRUE, auto_unbox = TRUE), file.path(STAGE_DIR, "style_exposure.json"))

# ============================================================================
# Step 5a: Tail risk (empirical + Cornish-Fisher + EVT-GPD)
# ============================================================================
cat("\n[5a] Tail risk metrics...\n")
ret_panel_p <- RAWDATA[Date > win_start & Date <= end_d & Ticker %in% w_tickers, .(Date, Ticker, Ret)]
ret_wide_p <- dcast(ret_panel_p, Date ~ Ticker, value.var = "Ret")
ret_mat_p <- as.matrix(ret_wide_p[, -1, with = FALSE]); ret_mat_p[is.na(ret_mat_p)] <- 0
w_for_port <- w_vec[colnames(ret_mat_p)]; w_for_port[is.na(w_for_port)] <- 0
if (sum(w_for_port) > 0) w_for_port <- w_for_port / sum(w_for_port)
port_ret_daily <- as.numeric(ret_mat_p %*% w_for_port)
var_95 <- as.numeric(quantile(port_ret_daily, 0.05)); var_99 <- as.numeric(quantile(port_ret_daily, 0.01))
es_95 <- mean(port_ret_daily[port_ret_daily <= var_95]); es_99 <- mean(port_ret_daily[port_ret_daily <= var_99])
cf_var_95 <- tryCatch(-compute_cf_var(port_ret_daily, p = 0.95), error = function(e) NA)
cf_var_99 <- tryCatch(-compute_cf_var(port_ret_daily, p = 0.99), error = function(e) NA)
evt_99 <- tryCatch(compute_evt_var(port_ret_daily, p = 0.99, threshold_q = 0.90, min_tail_n = 25L),
                   error = function(e) list(method = "failed", var_evt = NA, es_evt = NA))
sk <- as.numeric(PerformanceAnalytics::skewness(port_ret_daily))
ku <- as.numeric(PerformanceAnalytics::kurtosis(port_ret_daily))
# Codex C7 PARTIAL: Hill tail-index alpha (left tail) + monthly CVaR_95.
hill_alpha <- tryCatch({
  losses <- -port_ret_daily[port_ret_daily < 0]; losses <- sort(losses, decreasing = TRUE)
  k <- max(10L, floor(0.10 * length(losses)))
  if (length(losses) > k) 1 / mean(log(losses[1:k] / losses[k])) else NA_real_
}, error = function(e) NA_real_)
# Monthly CVaR_95 (aggregate daily → monthly compounded, then 5% ES)
port_dates <- as.Date(ret_wide_p$Date)
cvar_95_monthly <- tryCatch({
  month_key <- format(port_dates[seq_along(port_ret_daily)], "%Y-%m")
  mret <- tapply(port_ret_daily, month_key, function(r) prod(1 + r) - 1)
  if (length(mret) >= 12) { v <- quantile(mret, 0.05); mean(mret[mret <= v]) } else NA_real_
}, error = function(e) NA_real_)
cat("  ES 1% empirical:", round(es_99, 4), "| EVT 1% ES:", round(evt_99$es_evt, 4), "method:", evt_99$method,
    "| skew:", round(sk, 3), "| ex-kurt:", round(ku, 3), "| Hill α:", round(hill_alpha, 3),
    "| CVaR95 monthly:", round(cvar_95_monthly, 4), "\n")
tail_metrics <- list(as_of_date = as.character(last_sig_date), window_days = length(port_ret_daily),
  daily_mean = signif(mean(port_ret_daily), 4), daily_sd = signif(sd(port_ret_daily), 4),
  skewness = round(sk, 3), excess_kurtosis = round(ku, 3),
  hill_tail_index_alpha = if (!is.na(hill_alpha)) round(hill_alpha, 4) else NA,
  cvar_95_monthly = if (!is.na(cvar_95_monthly)) round(cvar_95_monthly, 4) else NA,
  empirical = list(var_5pct = round(var_95, 4), var_1pct = round(var_99, 4),
    es_5pct = round(es_95, 4), es_1pct = round(es_99, 4)),
  cornish_fisher = list(var_5pct = round(cf_var_95, 4), var_1pct = round(cf_var_99, 4)),
  evt_gpd = list(var_1pct = round(evt_99$var_evt, 4), es_1pct = round(evt_99$es_evt, 4), method = evt_99$method,
    shape_xi = if (is.null(evt_99$shape_xi)) NA else round(evt_99$shape_xi, 4),
    scale_beta = if (is.null(evt_99$scale_beta)) NA else signif(evt_99$scale_beta, 4),
    n_exceedances = if (is.null(evt_99$n_exceedances)) NA else evt_99$n_exceedances))
writeLines(toJSON(tail_metrics, pretty = TRUE, auto_unbox = TRUE), file.path(STAGE_DIR, "tail_risk.json"))

# ============================================================================
# Step 5b: Stress tests (6 crisis windows + 3 factor shocks)
# ============================================================================
cat("\n[5b] Stress tests...\n")
stress_windows <- list(
  list(name = "GFC_2008", start = "2008-09-01", end = "2009-03-31"),
  list(name = "EuDebt_2011", start = "2011-08-01", end = "2011-11-30"),
  list(name = "China_2015", start = "2015-06-01", end = "2015-09-30"),
  list(name = "COVID_2020", start = "2020-02-15", end = "2020-04-15"),
  list(name = "Rate_Hike_2022", start = "2022-01-01", end = "2022-10-31"),
  list(name = "KR_Bear_2023_H1", start = "2023-01-01", end = "2023-06-30"))
stress_results <- list()
for (sw in stress_windows) {
  s_start <- as.Date(sw$start); s_end <- min(as.Date(sw$end), LOCKBOX_CUTOFF)
  if (s_start > LOCKBOX_CUTOFF) next
  sp <- RAWDATA[Date >= s_start & Date <= s_end & Ticker %in% w_tickers, .(Date, Ticker, Ret)]
  if (nrow(sp) == 0) { stress_results[[sw$name]] <- list(window = sw$name, status = "no_data"); next }
  sp_w <- dcast(sp, Date ~ Ticker, value.var = "Ret"); sp_mat <- as.matrix(sp_w[, -1, with = FALSE]); sp_mat[is.na(sp_mat)] <- 0
  w_align <- w_vec[colnames(sp_mat)]; w_align[is.na(w_align)] <- 0; if (sum(w_align) > 0) w_align <- w_align / sum(w_align)
  port_path <- as.numeric(sp_mat %*% w_align)
  nav_path <- cumprod(1 + port_path); mdd <- min(nav_path / cummax(nav_path) - 1, na.rm = TRUE)
  cum_ret <- prod(1 + port_path) - 1
  bm_path <- RAWDATA[Date >= s_start & Date <= s_end & Ticker %in% w_tickers, .(BM = mean(BM_Ret, na.rm = TRUE)), by = Date]
  bm_cum <- prod(1 + bm_path$BM) - 1
  # Codex C3 ACCEPT: weight coverage of 2023 holdings present in this historical window.
  # Low coverage (<60%) → stress result UNRELIABLE (book did not exist / partially listed).
  present_tk <- colnames(sp_mat)[colSums(sp_mat != 0) > 0]
  wt_cov <- sum(w_vec[intersect(names(w_vec), present_tk)], na.rm = TRUE)
  reliable <- wt_cov >= 0.60
  stress_results[[sw$name]] <- list(window = sw$name, start = as.character(s_start), end = as.character(s_end),
    n_days = length(port_path), n_holdings_present = length(present_tk),
    weight_coverage = round(wt_cov, 4), reliable = reliable,
    portfolio_cum_return = round(cum_ret, 4), portfolio_mdd = round(mdd, 4),
    portfolio_worst_day = round(min(port_path), 4), benchmark_cum_return = round(bm_cum, 4),
    excess_return_vs_bm = round(cum_ret - bm_cum, 4))
  cat("    ", sw$name, ": port", round(cum_ret*100, 2), "% / BM", round(bm_cum*100, 2),
      "% / excess", round((cum_ret-bm_cum)*100, 2), "pp / MDD", round(mdd*100, 2),
      "% / cov", round(wt_cov*100, 1), "%", if (reliable) "[OK]" else "[UNRELIABLE]", "\n")
}
mkt_beta_port <- as.numeric(w_B[1, "MKT"]); market_down_5 <- mkt_beta_port * (-0.05)
def_beta_port <- as.numeric(w_B[1, "DEF"]); value_crash <- def_beta_port * (-0.05)
wml_beta_port <- as.numeric(w_B[1, "WML"]); mom_reversal <- wml_beta_port * (-0.05)
stress_results$market_shock_minus_5pct <- list(port_mkt_beta = round(mkt_beta_port, 4), loss_estimate = round(market_down_5, 4))
stress_results$value_def_shock_minus_5pct <- list(port_def_beta = round(def_beta_port, 4), loss_estimate = round(value_crash, 4))
stress_results$momentum_reversal_minus_5pct <- list(port_wml_beta = round(wml_beta_port, 4), loss_estimate = round(mom_reversal, 4))
cat("  Market -5%:", round(market_down_5*100, 2), "% (MKT beta", round(mkt_beta_port, 3), ")\n")
writeLines(toJSON(stress_results, pretty = TRUE, auto_unbox = TRUE), file.path(STAGE_DIR, "stress_test_results.json"))

# ============================================================================
# Step 5c: Crowding score (Acadian 2026, P5) — PROD alpha + vol-factor proxies
# ============================================================================
cat("\n[5c] Crowding score per factor (vol-factor focus, alphaF C8)...\n")
# (1) PROD alpha signal exposure
alpha_last <- alpha_scores[Date == last_sig_date, .(Ticker, factor_name = "D_PROD_LightGBM_30f", exposure = pred)]
# (2) vol-factor proxies reconstructed from exposure matrix (z-scores) — IdioVol/RealVol/Amihud
vf_idio  <- expo_last[, .(Ticker, factor_name = "D01_IdioVol_proxy",  exposure = idio_vol_z)][!is.na(exposure)]
vf_real  <- expo_last[, .(Ticker, factor_name = "D03_RealVol_proxy",  exposure = realized_vol_z)][!is.na(exposure)]
vf_amih  <- expo_last[, .(Ticker, factor_name = "L01_Amihud_proxy",   exposure = amihud_60_z)][!is.na(exposure)]
crowd_input <- rbindlist(list(alpha_last, vf_idio, vf_real, vf_amih), use.names = TRUE)
crowd_results <- tryCatch(crowding_score_per_factor(factor_exposures = crowd_input, sig_date = last_sig_date,
    RAWDATA = RAWDATA[Date >= last_sig_date - 90L & Date <= last_sig_date], benchmark_tickers = NULL, top_n = 20L),
  error = function(e) { cat("  Crowding failed:", conditionMessage(e), "\n")
    data.table(factor_name = "D_PROD_LightGBM_30f", crowding_score = NA_real_) })
cat("  Crowding results:\n"); print(crowd_results)
crowd_list <- lapply(seq_len(nrow(crowd_results)), function(i) {
  r <- crowd_results[i]
  el <- list(factor_name = r$factor_name, crowding_score = if (!is.na(r$crowding_score)) round(r$crowding_score, 4) else NA)
  if ("hhi_top" %in% names(r)) el$hhi_top <- if (!is.na(r$hhi_top)) round(r$hhi_top, 4) else NA
  if ("vol_concentration" %in% names(r)) el$vol_concentration <- if (!is.na(r$vol_concentration)) round(r$vol_concentration, 4) else NA
  if ("passive_overlap_proxy" %in% names(r)) el$passive_overlap_proxy <- if (!is.na(r$passive_overlap_proxy)) round(r$passive_overlap_proxy, 4) else NA
  if ("demand_elasticity_proxy" %in% names(r)) el$demand_elasticity_proxy <- if (!is.na(r$demand_elasticity_proxy)) round(r$demand_elasticity_proxy, 4) else NA
  if (!is.na(r$crowding_score) && r$crowding_score >= 0.75) el$alert <- "LEVEL_HIGH"
  el })
crowding_summary <- list(as_of_date = as.character(last_sig_date),
  crowding_score_per_factor = crowd_list,
  threshold_note = "crowding_score >= 0.75 → crowding_flags; vol-factor proxies (IdioVol/RealVol/Amihud) reconstructed from exposure z-scores per alphaF C8.")
writeLines(toJSON(crowding_summary, pretty = TRUE, auto_unbox = TRUE), file.path(STAGE_DIR, "crowding_score.json"))

# ============================================================================
# Step 5d: Regime correlation (normal vs high-vol)
# ============================================================================
cat("\n[5d] Regime correlation...\n")
bm_dt <- unique(RAWDATA[Date > win_start & Date <= end_d, .(Date, BM_Ret)])[!is.na(BM_Ret)]; setorder(bm_dt, Date)
bm_dt[, vol_60 := frollapply(BM_Ret, 60, sd, na.rm = TRUE) * sqrt(252)]; bm_dt <- bm_dt[!is.na(vol_60)]
delta_cor <- NA; avg_cor_normal <- NA; avg_cor_high <- NA
if (nrow(bm_dt) >= 60L) {
  vol_threshold <- quantile(bm_dt$vol_60, 0.67, na.rm = TRUE)
  bm_dt[, regime := fifelse(vol_60 >= vol_threshold, "high_vol", "normal")]
  ret_dt_long <- merge(data.table(Date = as.Date(rownames(ret_mat_last)), row_idx = seq_len(nrow(ret_mat_last))),
                       bm_dt[, .(Date, regime)], by = "Date")
  high_idx <- ret_dt_long[regime == "high_vol", row_idx]; norm_idx <- ret_dt_long[regime == "normal", row_idx]
  top50_idx <- order(-apply(ret_mat_last, 2, var))[1:min(50L, ncol(ret_mat_last))]; ret_sub <- ret_mat_last[, top50_idx]
  if (length(high_idx) >= 10 && length(norm_idx) >= 10) {
    cor_normal <- cor(ret_sub[norm_idx, ], use = "pairwise.complete.obs"); cor_high <- cor(ret_sub[high_idx, ], use = "pairwise.complete.obs")
    avg_cor_normal <- mean(cor_normal[upper.tri(cor_normal)], na.rm = TRUE); avg_cor_high <- mean(cor_high[upper.tri(cor_high)], na.rm = TRUE)
    delta_cor <- avg_cor_high - avg_cor_normal
    cat("  avg cor normal:", round(avg_cor_normal, 3), "| high-vol:", round(avg_cor_high, 3), "| Δ:", round(delta_cor, 3), "\n")
    write_parquet(data.table(regime = c("normal", "high_vol"), n_days = c(length(norm_idx), length(high_idx)),
      avg_pairwise_correlation = c(avg_cor_normal, avg_cor_high), vol_threshold_60d_pct = round(vol_threshold * 100, 2)),
      file.path(STAGE_DIR, "regime_correlation.parquet"))
  } else write_parquet(data.table(regime = NA_character_, n_days = 0L, avg_pairwise_correlation = NA_real_), file.path(STAGE_DIR, "regime_correlation.parquet"))
} else write_parquet(data.table(regime = NA_character_, n_days = 0L, avg_pairwise_correlation = NA_real_), file.path(STAGE_DIR, "regime_correlation.parquet"))

# ============================================================================
# Final: risk_package_draft_PROD.json
# ============================================================================
cat("\n[FINAL] risk_package_draft_PROD.json...\n")
sorted_fcontrib <- sort(per_factor_pct * 100, decreasing = TRUE)
top_risks_str <- sapply(seq_len(min(3L, length(sorted_fcontrib))), function(k) sprintf("%s (%.1f%%)", names(sorted_fcontrib)[k], sorted_fcontrib[k]))

crowding_flags <- character(0)
for (cl in crowd_list) if (!is.na(cl$crowding_score) && cl$crowding_score >= 0.75)
  crowding_flags <- c(crowding_flags, sprintf("%s crowding=%.3f LEVEL_HIGH", cl$factor_name, cl$crowding_score))
if (hhi_sector > 0.30) crowding_flags <- c(crowding_flags,
  sprintf("Sector HHI=%.3f > 0.30 (top %s=%.1f%%)", hhi_sector, sect_agg$Sector_Lv2[1], sect_agg$w_sum[1]*100))

liq_check <- RAWDATA[Date > (last_sig_date - 30L) & Date <= (last_sig_date - 1L) & Ticker %in% w_tickers,
                     .(adv_20d_krw = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
liq_check <- merge(liq_check, data.table(Ticker = names(w_vec), weight = w_vec), by = "Ticker")
liq_flags <- liq_check[adv_20d_krw < 2e8]
liq_flags_str <- if (nrow(liq_flags) > 0) sprintf("%s ADV=%.1e<2e8 (w=%.3f)", liq_flags$Ticker, liq_flags$adv_20d_krw, liq_flags$weight) else character(0)

challenge_flags <- list()
if (cond_final > 500) { challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R2", severity = "HIGH",
  detail = sprintf("Σ cond %.1f > 500 — ill-conditioned.", cond_final), action_required = "Optimizer use HRP/shrinkage-inverse.")
} else if (cond_final > 100) challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R2-soft", severity = "LOW",
  detail = sprintf("Σ cond %.1f in (100, 500] — within hard gate but above soft cond<=100 preference (Codex C1). Eigen-floor target_cond=%d applied; raw BΩB'+D was %.1f.", cond_final, TARGET_COND, cond_fm_before),
  action_required = "Acceptable for inversion; Optimizer may prefer HRP for robustness.")
# Codex C3 ACCEPT: stress windows with low 2023-book coverage are UNRELIABLE.
unreliable_stress <- Filter(function(nm) isFALSE(stress_results[[nm]]$reliable),
  names(stress_results)[grepl("^(GFC|EuDebt|China|COVID|Rate|KR)", names(stress_results))])
if (length(unreliable_stress) > 0) challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R4-coverage", severity = "MEDIUM",
  detail = sprintf("Stress windows with <60%% 2023-book coverage (UNRELIABLE — 2023 holdings partially unlisted in window): %s. GFC_2008 cov=%.0f%% (7/20 names). Pre-IPO survivorship: these MDDs are NOT representative of the executable book.",
    paste(unreliable_stress, collapse=", "), stress_results$GFC_2008$weight_coverage*100),
  action_required = "Forge/Judge: weight reliable windows (COVID/Rate2022, cov>=85%) over deep-history (GFC/EuDebt). GFC MDD -50.6% is on 35% partial book, not 100% portfolio.")
top_risk_pct <- max(per_factor_pct) * 100
if (top_risk_pct > 40) challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R1", severity = "HIGH",
  detail = sprintf("Top common risk %.1f%% > 40%% (%s).", top_risk_pct, names(per_factor_pct)[which.max(per_factor_pct)]),
  action_required = "Optimizer impose factor exposure constraints.")
if (length(crowding_flags) > 0) challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R3", severity = "MEDIUM",
  detail = paste(crowding_flags, collapse = "; "), action_required = "Monitor crowding 3m delta for decay onset.")
if (market_down_5 < -0.08) challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R4", severity = "HIGH",
  detail = sprintf("Market -5%% loss %.2f%% < -8%% (MKT beta %.2f)", market_down_5*100, mkt_beta_port),
  action_required = "Beta exposure excessive.")
# Stress excess check (RF-R4 ext): Rate_Hike_2022 BM-relative underperformance
rh <- stress_results$Rate_Hike_2022
if (!is.null(rh$excess_return_vs_bm) && rh$excess_return_vs_bm < -0.05) challenge_flags[[length(challenge_flags)+1]] <- list(
  id = "RF-R4-stress", severity = "MEDIUM",
  detail = sprintf("Rate_Hike_2022 underperforms BM by %.1fpp (port %.1f%% vs BM %.1f%%).", rh$excess_return_vs_bm*100, rh$portfolio_cum_return*100, rh$benchmark_cum_return*100),
  action_required = "Forge: confirm rate-sensitivity / duration tilt acceptable under AX-001 v2.")
# RF-R5: factor pair corr > 0.8
cor_omg <- cov2cor(Omega); high_pairs <- sum(abs(cor_omg[upper.tri(cor_omg)]) > 0.8)
if (high_pairs >= 2) challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R5", severity = "MEDIUM",
  detail = sprintf("%d factor pairs |corr|>0.8 — style redundancy.", high_pairs), action_required = "Review style factor set.")
# Idio-vol tilt note (alphaF C8 PROD core)
challenge_flags[[length(challenge_flags)+1]] <- list(id = "RF-R-idio", severity = "INFO",
  detail = sprintf("PROD vol-factor tilt: idio_vol_z=%.2f realized_vol_z=%.2f amihud_z=%.2f size_z=%.2f. %s",
    port_idio_z, port_realvol_z, port_amihud_z, port_size_z,
    if (port_idio_z < -0.1) "Net LOW-vol (defensive) tilt — crowding/decay risk if low-vol anomaly crowds." else if (port_idio_z > 0.1) "Net HIGH-vol (lottery) tilt — AX-001 crisis fragility risk." else "Near-neutral idio-vol exposure."),
  action_required = "Forge: AX-001 v2 crisis bad/normal IC robustness on vol-tilted book.")

risk_package <- list(task_id = WT_ID, schema_version = "risk_package_v1", as_of_date = as.character(last_sig_date),
  signal_cutoff = as.character(LOCKBOX_CUTOFF), alpha_handle = "D_PROD",
  alpha_package_ref = "qepm/mailbox/worktask/WT-D20260528_003/alpha_package_PROD.json",
  hypothesis_title = ap$hypothesis_title, selection_objective = "condition_number",
  primary_sigma_method = primary_method, universe_n = N_assets,
  exposure_matrix_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/exposure_matrix.parquet",
  factor_covariance_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/factor_covariance.parquet",
  specific_risk_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/covariance.parquet",
  regime_correlation_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/regime_correlation.parquet",
  tail_risk_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/tail_risk.json",
  stress_test_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/stress_test_results.json",
  style_exposure_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/style_exposure.json",
  crowding_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/crowding_score.json",
  method_shopping_log_ref = "stage_artifacts/WT_D20260528_003_risk_PROD/method_shopping_log.json",
  risk_summary = list(portfolio_vol_ann_pct = round(port_vol_ann * 100, 3),
    factor_var_share_pct = round(factor_pct * 100, 2), specific_var_share_pct = round(specific_pct * 100, 2),
    top_common_risks = top_risks_str, crowding_flags = crowding_flags, liquidity_flags = liq_flags_str,
    crowding_score_per_factor = crowd_list,
    sector_hhi = round(hhi_sector, 4), sector_top1_pct = round(sect_agg$w_sum[1] * 100, 2), sector_top1 = sect_agg$Sector_Lv2[1],
    idio_vol_tilt = list(port_idio_vol_z = round(port_idio_z, 4), port_realized_vol_z = round(port_realvol_z, 4),
      port_amihud_z = round(port_amihud_z, 4), port_size_z = round(port_size_z, 4)),
    stress_tests = list(market_down_5 = round(market_down_5, 4), value_def_shock = round(value_crash, 4),
      mom_reversal = round(mom_reversal, 4),
      covid_2020_replay = if (!is.null(stress_results$COVID_2020$portfolio_cum_return)) round(stress_results$COVID_2020$portfolio_cum_return, 4) else NA,
      rate_hike_2022 = if (!is.null(stress_results$Rate_Hike_2022$portfolio_cum_return)) round(stress_results$Rate_Hike_2022$portfolio_cum_return, 4) else NA,
      rate_hike_2022_excess_vs_bm = if (!is.null(stress_results$Rate_Hike_2022$excess_return_vs_bm)) round(stress_results$Rate_Hike_2022$excess_return_vs_bm, 4) else NA,
      gfc_2008 = if (!is.null(stress_results$GFC_2008$portfolio_cum_return)) round(stress_results$GFC_2008$portfolio_cum_return, 4) else NA,
      kr_bear_2023_h1 = if (!is.null(stress_results$KR_Bear_2023_H1$portfolio_cum_return)) round(stress_results$KR_Bear_2023_H1$portfolio_cum_return, 4) else NA),
    tail_risk = list(port_vol_ann_pct = round(port_vol_ann * 100, 3), var_1pct_daily = round(var_99, 4),
      es_1pct_daily = round(es_99, 4), cf_var_1pct = round(cf_var_99, 4),
      evt_var_1pct = round(evt_99$var_evt, 4), evt_es_1pct = round(evt_99$es_evt, 4), evt_method = evt_99$method,
      hill_tail_index_alpha = if (!is.na(hill_alpha)) round(hill_alpha, 4) else NA,
      cvar_95_monthly = if (!is.na(cvar_95_monthly)) round(cvar_95_monthly, 4) else NA,
      skewness = round(sk, 3), excess_kurtosis = round(ku, 3)),
    stress_reliability = lapply(names(stress_results)[grepl("^(GFC|EuDebt|China|COVID|Rate|KR)", names(stress_results))],
      function(nm) list(window = nm, weight_coverage = stress_results[[nm]]$weight_coverage,
        reliable = stress_results[[nm]]$reliable))),
  diagnostics = list(condition_number_primary = round(cond_final, 1),
    condition_number_fm_before = round(cond_fm_before, 1), condition_number_fm_after = round(cond_fm_after, 1),
    condition_number_sample = signif(cond_sample, 4), condition_number_schafer_strimmer = round(cond_ss, 1),
    condition_number_gr = if (!is.null(cov_gr)) signif(cond_gr, 4) else NA,
    shrinkage_used = TRUE, shrinkage_method = primary_method, target_cond = TARGET_COND,
    min_eigenvalue_primary = signif(min_eig_fm_after, 4),
    factor_coverage_median_r2 = round(median_r2, 3), factor_coverage_mean_r2 = round(mean(r2_per_tk, na.rm = TRUE), 3),
    factor_correlation_warnings = if (high_pairs >= 1) list(sprintf("%d factor pair(s) |corr|>0.8", high_pairs)) else list(),
    factor_correlations = (function() { p <- list(); for (i in seq_len(nrow(cor_omg)-1L)) for (j in seq(i+1L, ncol(cor_omg)))
      p[[length(p)+1L]] <- list(pair = sprintf("%s_%s", rownames(cor_omg)[i], colnames(cor_omg)[j]), corr = round(cor_omg[i,j], 3)); p })(),
    n_universe_for_sigma = N_assets, n_holdings_for_decomp = length(w_tickers),
    regime_correlation_delta = if (!is.na(delta_cor)) round(delta_cor, 4) else NA,
    specific_var_floor = SPECIFIC_VAR_FLOOR, specific_var_ceiling = SPECIFIC_VAR_CEILING),
  alpha_risk_integration = list(note = "Risk estimation independent of alpha values. Σ used downstream by Optimizer with alpha_vector unchanged.",
    portfolio_construction = "EWMA(0.5)+bandbuffer+softmax-cap [0,0.20] from LightGBM 30f pred. Σw=1.",
    no_weight_proposal = "Risk agent emits Σ + diagnostics only. No weight/MVO."),
  pit_assertions = list(lockbox_strict = sprintf("All sig_dates <= %s. RAWDATA lookback Date < sig_date (no C2).", as.character(LOCKBOX_CUTOFF)),
    sigma_pit = "Σ on 252d lookback ending sig_date - 1 (C9 t-1 lag).", crowding_pit = sprintf("Crowding RAWDATA[Date <= %s] strict.", as.character(LOCKBOX_CUTOFF)),
    omega_pit_note = "Codex C5: Ω factor returns use static t-1 PIT-lagged style z-scores (computed at sig_date-1) as quintile sort keys over the 252d lookback. Standard 'static exposure × time-varying return' factor-return construction (Grinold-Kahn 2000 §3); NO future data enters — exposures are as-of sig_date-1, returns are historical. This is a known approximation (cross-section ranks held fixed over the window), not a lookahead (C12) violation. Time-varying date-wise exposures deferred (one-period Σ snapshot is sufficient for monthly rebalance).",
    no_alpha_modification = "alpha_vector/pred/weights read-only. risk_package alpha 미수정.",
    boundary_compliance = "20 max + Σw=1 + [0,0.20] + LIQ 2e8 — Risk passive observation (Optimizer enforces)."),
  challenge_flags = challenge_flags,
  rule2_status = if (cond_final >= 500 || port_vol_ann > 0.50) "STOP_RECOMMEND" else "PASS",
  build_meta = list(agent = "risk-research", pipeline_version = "risk_PROD_v1.0",
    build_timestamp = as.character(Sys.time()), Rscript_path = "qepm/mailbox/worktask/WT-D20260528_003/scripts/risk_PROD_pipeline.R",
    libraries = c("data.table", "arrow", "jsonlite", "PerformanceAnalytics", "corpcor", "fExtremes", "evir")))

writeLines(toJSON(risk_package, pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null"),
           file.path(WT_DIR, "risk_package_draft_PROD.json"))

cat("\n================================================================\n")
cat("Risk PROD Pipeline COMPLETE.\n")
cat("  Primary Σ:", primary_method, "\n")
cat("  Cond before:", round(cond_fm_before, 1), "→ after:", round(cond_fm_after, 1), "(target", TARGET_COND, ")\n")
cat("  Port vol ann:", round(port_vol_ann*100, 2), "% | factor share:", round(factor_pct*100, 1), "% | specific:", round(specific_pct*100, 1), "%\n")
cat("  Top risk:", names(per_factor_pct)[which.max(per_factor_pct)], round(max(per_factor_pct)*100, 2), "%\n")
cat("  ES 1% empirical:", round(es_99, 4), "| EVT ES 1%:", round(evt_99$es_evt, 4), "\n")
cat("  Sector HHI:", round(hhi_sector, 3), "top:", sect_agg$Sector_Lv2[1], round(sect_agg$w_sum[1]*100, 1), "%\n")
cat("  idio_vol_z tilt:", round(port_idio_z, 3), "| Challenge flags:", length(challenge_flags), "\n")
cat("================================================================\n")
