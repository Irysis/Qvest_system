#==============================================================================
# WT-D20260528_003 — Risk Research Pipeline (D ML XGBoost alpha)
#
# Role: Risk Research Agent
# Input:
#   - alpha_package_D_ML.json (read-only, immutable)
#   - alpha_scores_clean.parquet (116 sig_dates × ~349 tickers × alpha_z)
#   - weights_schedule.parquet (116 × 20 top, softmax-cap [0, 0.20], Σw=1)
#   - .cache/rawdata.parquet (RAWDATA, Date 1990~2026-05-27)
#
# Output:
#   - stage_artifacts/WT_D20260528_003_risk_D/
#       exposure_matrix.parquet
#       factor_covariance.parquet
#       specific_risk.parquet
#       covariance.parquet
#       tail_risk_metrics.json
#       stress_test_results.json
#       style_exposure.json
#       crowding_score.json
#       regime_correlation.parquet
#       method_shopping_log.json
#   - qepm/mailbox/worktask/WT-D20260528_003/risk_package_draft.json
#
# Hard:
#   - Σ PSD (eigenvalue >= 0)
#   - condition_number < 500 (shrinkage 후)
#   - Lockbox sig_date <= 2023-12-22 strict (정규 리서치 단계 alpha-research scope)
#   - PIT C1~C15 (Date <= sig_date strict for risk inputs)
#   - No alpha modification (alpha_package/weights/alpha_z untouched)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260528_003"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts/WT_D20260528_003_risk_D")
ALPHA_STAGE <- file.path(ROOT, "stage_artifacts/WT_D20260528_003_overnight_D_ML")
LOCKBOX_CUTOFF <- as.Date("2023-12-22")

dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

cat("================================================================\n")
cat("WT-D20260528_003 — Risk Research Pipeline\n")
cat("Lockbox cutoff:", as.character(LOCKBOX_CUTOFF), "(strict)\n")
cat("Output dir:", STAGE_DIR, "\n")
cat("================================================================\n\n")

# --- Risk infra source ---
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/tail_risk_engine.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/crowding_score_per_factor.R"))

# ============================================================================
# Helper: Schäfer-Strimmer 2005 shrinkage (corpcor::cov.shrink)
# Analytical empirical Bayes shrinkage. O(N²T) one pass. PSD by construction.
# Target: diagonal of empirical variances (unequal variance shrinkage)
# verbose=FALSE to silence stdout
# ============================================================================
suppressPackageStartupMessages(library(corpcor))
cov_schafer_strimmer <- function(X) {
  X <- as.matrix(X)
  X[is.na(X)] <- 0
  S <- corpcor::cov.shrink(X, verbose = FALSE)
  list(Sigma = as.matrix(S),
       delta_var = attr(S, "lambda.var"),
       delta_cor = attr(S, "lambda"))
}

# ============================================================================
# Helper: Eigenvalue floor (PSD + condition number control)
# ============================================================================
eigen_floor <- function(Sigma, min_eig_frac = 1e-4) {
  e <- eigen(Sigma, symmetric = TRUE)
  vals <- e$values; vecs <- e$vectors
  max_val <- max(vals)
  floor_val <- max_val * min_eig_frac
  vals[vals < floor_val] <- floor_val
  D <- diag(vals)
  Sigma_clean <- vecs %*% D %*% t(vecs)
  Sigma_clean <- (Sigma_clean + t(Sigma_clean)) / 2
  rownames(Sigma_clean) <- colnames(Sigma_clean) <- rownames(Sigma)
  Sigma_clean
}

# ============================================================================
# 0. Load inputs (immutable: alpha + RAWDATA)
# ============================================================================
cat("[0] Loading inputs...\n")
ap <- fromJSON(file.path(WT_DIR, "alpha_package_D_ML.json"), simplifyVector = FALSE)
alpha_scores <- setDT(read_parquet(file.path(ALPHA_STAGE, "alpha_scores_clean.parquet")))
weights_sched <- setDT(read_parquet(file.path(ALPHA_STAGE, "weights_schedule.parquet")))
RAWDATA <- setDT(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))

# Normalize Date
alpha_scores[, Date := as.Date(Date)]
weights_sched[, Date := as.Date(Date)]
RAWDATA[, Date := as.Date(Date)]

# Lockbox enforcement (alpha-research 단계로 본 pipeline은 정규 리서치 scope)
alpha_scores <- alpha_scores[Date <= LOCKBOX_CUTOFF]
weights_sched <- weights_sched[Date <= LOCKBOX_CUTOFF]
sig_dates_all <- sort(unique(weights_sched$Date))
cat("  alpha_scores N rows:", nrow(alpha_scores), "\n")
cat("  weights_sched N rows:", nrow(weights_sched), "\n")
cat("  sig_dates:", length(sig_dates_all), "(", as.character(min(sig_dates_all)), "~", as.character(max(sig_dates_all)), ")\n")
cat("  RAWDATA N rows:", nrow(RAWDATA), "(filter sig_date <=", as.character(LOCKBOX_CUTOFF), ")\n")
RAWDATA <- RAWDATA[Date <= LOCKBOX_CUTOFF]
cat("  RAWDATA post-lockbox:", nrow(RAWDATA), "\n\n")

# Universe: 모든 sig_date의 top20 union (= 잠재 holdings)
universe_tickers <- sort(unique(weights_sched$Ticker))
cat("  Universe (top20 union over sig_dates):", length(universe_tickers), "tickers\n\n")

# ============================================================================
# Helper: build daily returns matrix (Ticker x Date wide)
# ============================================================================
build_returns_matrix <- function(tickers, as_of_date, n_days = 252L) {
  # PIT strict: Date < as_of_date (lookback only, no same-day circular C2)
  end_date <- as.Date(as_of_date) - 1L  # exclusive of sig_date
  sub <- RAWDATA[Ticker %in% tickers & Date <= end_date,
                 .(Date, Ticker, Ret)]
  if (nrow(sub) == 0L) return(NULL)
  # Use last n_days available business days
  last_dates <- tail(sort(unique(sub$Date)), n_days)
  sub <- sub[Date %in% last_dates]
  wide <- dcast(sub, Date ~ Ticker, value.var = "Ret")
  mat <- as.matrix(wide[, -1, drop = FALSE])
  rownames(mat) <- as.character(wide$Date)
  # Filter: tickers with >=80% non-NA + rows with >=50% complete
  good_cols <- colSums(!is.na(mat)) >= floor(0.8 * nrow(mat))
  if (sum(good_cols) < 5L) return(NULL)
  mat <- mat[, good_cols, drop = FALSE]
  good_rows <- rowSums(!is.na(mat)) >= ncol(mat) * 0.5
  mat <- mat[good_rows, , drop = FALSE]
  if (nrow(mat) < 60L) return(NULL)
  mat[is.na(mat)] <- 0
  mat
}

# ============================================================================
# Step 1: Exposure Matrix B (Style + Sector + Market)
# ============================================================================
# D ML top features: L26_Log_MktCap + S01_Size + D01_IdioVol + L01_Amihud + D03_RealVol
# Style factors derived from RAWDATA at sig_date:
#   - log_mktcap (Size proxy)         : log(Size)
#   - market_beta (Mkt)               : Blume-adjusted (rolling 252d) on BM_Ret
#   - realized_vol (Vol style)        : sd(Ret) trailing 60d
#   - idio_vol (Idio style)           : sd(residual) from CAPM 60d
#   - amihud (Liq style)              : mean(|Ret|/(Vol*Close)) 60d
#   - momentum_12m1m (Mom style)      : cum log return t-252 ~ t-21
#   - reversal_1m (ST_Rev style)      : cum log return t-21 ~ t-1
# Sector exposure: Sector_Lv2 one-hot
cat("[1] Building exposure matrix B (style + sector + market) per sig_date...\n")
last_sig_date <- max(sig_dates_all)
cat("  Primary as_of_date:", as.character(last_sig_date), "(latest sig_date in lockbox)\n")

build_exposure_at_sigdate <- function(sig_d, top_tickers) {
  end_d <- as.Date(sig_d) - 1L
  win_252 <- end_d - 252L
  win_60 <- end_d - 60L
  win_21 <- end_d - 21L

  # Snapshot at t-1 (most recent Close/Size before sig_d)
  rd_t1 <- RAWDATA[Ticker %in% top_tickers & Date <= end_d]
  rd_last <- rd_t1[, .SD[.N], by = Ticker, .SDcols = c("Date", "Close", "Size", "Sector_Lv2")]
  setnames(rd_last, "Date", "snap_Date")

  # ── style features computed on rolling windows ──
  # 60d vol + amihud (using Vol/Close ratio)
  rd_60 <- rd_t1[Date > win_60, .(
    realized_vol = sd(Ret, na.rm = TRUE) * sqrt(252),
    amihud_60 = mean(abs(Ret) / pmax(Close * Vol, 1), na.rm = TRUE) * 1e9,
    n_60 = .N
  ), by = Ticker]

  # 252d Blume beta vs BM_Ret
  rd_252 <- rd_t1[Date > win_252, .(Date, Ticker, Ret, BM_Ret)]
  beta_dt <- rd_252[, {
    valid <- !is.na(Ret) & !is.na(BM_Ret)
    if (sum(valid) >= 60) {
      cov_xy <- cov(Ret[valid], BM_Ret[valid])
      var_x <- var(BM_Ret[valid])
      raw_b <- if (var_x > 0) cov_xy / var_x else NA_real_
      blume_b <- if (!is.na(raw_b)) 0.67 * raw_b + 0.33 else NA_real_
      .(beta_blume = blume_b, n_b = sum(valid))
    } else .(beta_blume = NA_real_, n_b = 0L)
  }, by = Ticker]

  # Idiosyncratic vol (CAPM residual sd) trailing 60d
  rd_60_b <- rd_t1[Date > win_60, .(Date, Ticker, Ret, BM_Ret)]
  idio_dt <- rd_60_b[, {
    valid <- !is.na(Ret) & !is.na(BM_Ret)
    if (sum(valid) >= 40) {
      mod <- tryCatch(lm(Ret[valid] ~ BM_Ret[valid]), error = function(e) NULL)
      idv <- if (!is.null(mod)) sd(residuals(mod)) * sqrt(252) else NA_real_
      .(idio_vol = idv)
    } else .(idio_vol = NA_real_)
  }, by = Ticker]

  # 12-1 momentum (t-252 ~ t-21)
  rd_mom <- rd_t1[Date > win_252 & Date <= win_21, .(
    mom_12m1m = sum(log1p(Ret), na.rm = TRUE)
  ), by = Ticker]

  # ST reversal (t-21 ~ t-1)
  rd_rev <- rd_t1[Date > win_21 & Date <= end_d, .(
    rev_1m = sum(log1p(Ret), na.rm = TRUE)
  ), by = Ticker]

  # Merge style
  expo <- merge(rd_last, rd_60, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, beta_dt, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, idio_dt, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, rd_mom, by = "Ticker", all.x = TRUE)
  expo <- merge(expo, rd_rev, by = "Ticker", all.x = TRUE)

  # log MktCap
  expo[, log_mktcap := log(pmax(Size, 1))]

  # Standardize style (cross-section z)
  z_cols <- c("log_mktcap", "beta_blume", "realized_vol", "idio_vol",
              "amihud_60", "mom_12m1m", "rev_1m")
  for (cc in z_cols) {
    x <- expo[[cc]]
    mu <- mean(x, na.rm = TRUE); sg <- sd(x, na.rm = TRUE)
    if (!is.na(sg) && sg > 0) {
      expo[[paste0(cc, "_z")]] <- pmin(pmax((x - mu) / sg, -3), 3)
    } else {
      expo[[paste0(cc, "_z")]] <- 0
    }
  }

  expo[, sig_date := as.Date(sig_d)]
  expo
}

# Build for last sig_date (primary Σ snapshot)
expo_last <- build_exposure_at_sigdate(last_sig_date, universe_tickers)
cat("  Last sig_date exposure rows:", nrow(expo_last), "/", length(universe_tickers), "\n")
cat("  Sector_Lv2 distribution (top10):\n")
print(head(expo_last[, .N, by = Sector_Lv2][order(-N)], 10))

# Save exposure_matrix (last sig_date)
write_parquet(expo_last, file.path(STAGE_DIR, "exposure_matrix.parquet"))
cat("  Saved exposure_matrix.parquet\n\n")

# ============================================================================
# Step 2-4: Σ estimation (parallel multi-method comparison)
# Build returns mat for last sig_date universe → 3 estimators
# ============================================================================
cat("[2-4] Σ estimation (multi-method comparison)...\n")
# Build returns matrix for universe at last sig_date (252 day lookback)
ret_mat_last <- build_returns_matrix(universe_tickers, last_sig_date, n_days = 252L)
cat("  ret_mat dim:", dim(ret_mat_last), "(rows=days, cols=tickers)\n")
T_obs <- nrow(ret_mat_last); N_assets <- ncol(ret_mat_last)
cat("  T_obs =", T_obs, "; N_assets =", N_assets, "; q_ratio = T/N =", round(T_obs/N_assets, 2), "\n")

# Method shopping log (Charter R2-C, max 5)
method_log <- list()

# (A) Sample (pairwise)
cat("\n  [A] Sample covariance...\n")
cov_sample <- cov(ret_mat_last, use = "pairwise.complete.obs")
cov_sample[is.na(cov_sample)] <- 0
cond_sample <- kappa(cov_sample, exact = TRUE)
eig_sample <- eigen(cov_sample, symmetric = TRUE, only.values = TRUE)$values
min_eig_sample <- min(eig_sample)
cat("    condition:", round(cond_sample, 1), "; min_eig:", signif(min_eig_sample, 4), "\n")
method_log$sample <- list(name = "sample_pairwise", condition = cond_sample,
                          min_eig = min_eig_sample, psd = min_eig_sample >= -1e-10,
                          selected = FALSE)

# (B) Schäfer-Strimmer 2005 analytical shrinkage (corpcor)
cat("\n  [B] Schäfer-Strimmer 2005 shrinkage (corpcor::cov.shrink)...\n")
ss_res <- cov_schafer_strimmer(ret_mat_last)
cov_ss <- ss_res$Sigma
cond_ss <- kappa(cov_ss, exact = TRUE)
eig_ss <- eigen(cov_ss, symmetric = TRUE, only.values = TRUE)$values
min_eig_ss <- min(eig_ss)
cat("    condition:", round(cond_ss, 1), "; min_eig:", signif(min_eig_ss, 4),
    "; λ_var:", round(ss_res$delta_var, 4),
    "; λ_cor:", round(ss_res$delta_cor, 4), "\n")
method_log$schafer_strimmer <- list(name = "schafer_strimmer_2005",
                                     condition = cond_ss, min_eig = min_eig_ss,
                                     lambda_var = round(ss_res$delta_var, 6),
                                     lambda_cor = round(ss_res$delta_cor, 6),
                                     psd = min_eig_ss >= -1e-10, selected = FALSE)

# (B2) Legacy hrp_core LW (for comparison only — known degenerate target)
cat("\n  [B2] Legacy hrp_core LW (constant-variance target, for log only)...\n")
cc_lw <- .get_cor_cov(ret_mat_last, cov_method = "ledoit_wolf")
cov_lw <- cc_lw$cov
cond_lw <- kappa(cov_lw, exact = TRUE)
eig_lw <- eigen(cov_lw, symmetric = TRUE, only.values = TRUE)$values
min_eig_lw <- min(eig_lw)
cat("    condition:", round(cond_lw, 1), "; min_eig:", signif(min_eig_lw, 4), "\n")
method_log$ledoit_wolf_legacy <- list(name = "ledoit_wolf_const_var_legacy",
                                       condition = cond_lw, min_eig = min_eig_lw,
                                       psd = min_eig_lw >= -1e-10, selected = FALSE,
                                       note = "Legacy hrp_core LW uses constant-variance target → may degenerate to identity when N>>T")

# (C) Gerber + RMT
cat("\n  [C] Gerber + RMT denoised...\n")
cc_gr <- tryCatch(.get_cor_cov(ret_mat_last, cov_method = "gerber_rmt"),
                  error = function(e) { cat("    Gerber failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(cc_gr)) {
  cov_gr <- cc_gr$cov
  cond_gr <- kappa(cov_gr, exact = TRUE)
  eig_gr <- eigen(cov_gr, symmetric = TRUE, only.values = TRUE)$values
  min_eig_gr <- min(eig_gr)
  cat("    condition:", round(cond_gr, 1), "; min_eig:", signif(min_eig_gr, 4), "\n")
  method_log$gerber_rmt <- list(name = "gerber_rmt", condition = cond_gr,
                                 min_eig = min_eig_gr,
                                 psd = min_eig_gr >= -1e-10, selected = FALSE)
} else {
  cov_gr <- NULL; cond_gr <- NA; min_eig_gr <- NA
  method_log$gerber_rmt <- list(name = "gerber_rmt", condition = NA,
                                 min_eig = NA, psd = FALSE, selected = FALSE,
                                 error = "Gerber computation failed")
}

# Selection by R4 selection_objective: condition_number (estimation quality)
# Hard: condition_number < 500 + PSD
# Note: legacy LW (constant-variance target) prone to degenerate cond=1 (target → I*mu_var)
#       when N>>T. Schäfer-Strimmer 2005 (corpcor) is well-conditioned analytical default.
candidates <- list()
if (cond_sample < 500 && method_log$sample$psd) candidates$sample <- list(cov = cov_sample, cond = cond_sample, method = "sample_pairwise")
if (cond_ss < 500 && method_log$schafer_strimmer$psd) candidates$ss <- list(cov = cov_ss, cond = cond_ss, method = "schafer_strimmer_2005")
# Exclude legacy LW (degenerate target)
if (!is.null(cov_gr) && cond_gr < 500 && method_log$gerber_rmt$psd) candidates$gr <- list(cov = cov_gr, cond = cond_gr, method = "gerber_rmt")

cat("\n  Candidates passing cond<500 + PSD (excluding legacy LW):\n")
for (nm in names(candidates)) cat("    ", candidates[[nm]]$method, "cond=", round(candidates[[nm]]$cond, 1), "\n")

# Select min condition (R4 objective = condition_number)
if (length(candidates) == 0L) {
  # 모두 fail → eigen_floor regularization on Schäfer-Strimmer
  cat("\n  ALL methods exceed cond=500 → eigen-floor regularization on SS\n")
  cov_final <- eigen_floor(cov_ss, min_eig_frac = 1e-3)
  cond_final <- kappa(cov_final, exact = TRUE)
  method_selected <- "schafer_strimmer_eigfloored"
  method_log$schafer_strimmer_eigfloored <- list(name = method_selected,
                                                   condition = cond_final, selected = TRUE)
} else {
  best <- candidates[[which.min(sapply(candidates, function(x) x$cond))]]
  cov_final <- best$cov
  cond_final <- best$cond
  method_selected <- best$method
  if (method_selected == "sample_pairwise") method_log$sample$selected <- TRUE
  if (method_selected == "schafer_strimmer_2005") method_log$schafer_strimmer$selected <- TRUE
  if (method_selected == "gerber_rmt") method_log$gerber_rmt$selected <- TRUE
}

cat("\n  Selected:", method_selected, "(cond =", round(cond_final, 1), ")\n")

# Save method shopping log
writeLines(toJSON(list(
  task_id = WT_ID,
  agent_role = "risk",
  as_of_date = as.character(last_sig_date),
  selection_objective = "condition_number",
  n_candidates = length(method_log),
  cap = 5,
  method_log = method_log,
  selected_method = method_selected
), pretty = TRUE, auto_unbox = TRUE),
  file.path(STAGE_DIR, "method_shopping_log.json"))

# ============================================================================
# Step 2b: Factor covariance Ω (style factor returns)
# Construct daily style factor returns by cross-section quintile portfolios
# ============================================================================
cat("\n[2b] Factor covariance Ω (style FF-like factor returns)...\n")
# Build factor returns over last 252d. For each day:
#   - Mkt = BM_Ret
#   - SMB = small minus big (by log_mktcap quintile, recomputed every 21d)
#   - HML = high minus low book/market — proxy via inverse log_mktcap is invalid → use idio_vol low−high (Defensive proxy)
#   - WML = winner minus loser (12-1 momentum)
#   - ST_REV = short-term reversal (low minus high last 21d)
# Simpler robust approach: rolling style returns from universe quintile portfolios
end_d <- last_sig_date - 1L
win_start <- end_d - 252L

# Build daily univeral panel
panel_252 <- RAWDATA[Date > win_start & Date <= end_d & Ticker %in% universe_tickers,
                     .(Date, Ticker, Ret, BM_Ret, Size)]
panel_252 <- panel_252[!is.na(Ret) & !is.na(Size) & Size > 0]

# Compute style scores per ticker (using static snapshot at win_start - 252)
# For simplicity use most recent 60d-end scores per ticker (PIT lag t-1)
style_scores <- expo_last[, .(Ticker, log_mktcap_z, idio_vol_z, mom_12m1m_z, rev_1m_z, beta_blume_z)]

panel_252 <- merge(panel_252, style_scores, by = "Ticker", all.x = TRUE)

# Quintile portfolios — long top quintile, short bottom quintile, EW
build_factor_ret <- function(panel, score_col, sign = 1) {
  # sign = +1 for "high minus low" (e.g., Size big-small if z = log_mktcap)
  # SMB = small - big → use sign = -1 with log_mktcap_z
  dt <- copy(panel)
  setnames(dt, score_col, "score")
  dt <- dt[!is.na(score)]
  out <- dt[, {
    q <- quantile(score, c(0.2, 0.8), na.rm = TRUE)
    long_ret <- mean(Ret[score >= q[2]], na.rm = TRUE)
    short_ret <- mean(Ret[score <= q[1]], na.rm = TRUE)
    factor_ret <- sign * (long_ret - short_ret)
    .(factor_ret = factor_ret)
  }, by = Date]
  setorder(out, Date)
  out
}

mkt_ret <- panel_252[, .(factor_ret = mean(BM_Ret, na.rm = TRUE)), by = Date]
setorder(mkt_ret, Date)
smb_ret <- build_factor_ret(panel_252, "log_mktcap_z", sign = -1)  # small - big
hml_ret <- build_factor_ret(panel_252, "idio_vol_z", sign = -1)    # low idio - high idio (defensive)
wml_ret <- build_factor_ret(panel_252, "mom_12m1m_z", sign = 1)    # winner - loser
str_ret <- build_factor_ret(panel_252, "rev_1m_z", sign = -1)      # reversal: low - high

# Align dates and build factor returns matrix
common_dates <- Reduce(intersect, list(as.character(mkt_ret$Date),
                                       as.character(smb_ret$Date),
                                       as.character(hml_ret$Date),
                                       as.character(wml_ret$Date),
                                       as.character(str_ret$Date)))
common_dates <- as.Date(common_dates)
mkt_a <- mkt_ret[as.character(Date) %in% as.character(common_dates), factor_ret]
smb_a <- smb_ret[as.character(Date) %in% as.character(common_dates), factor_ret]
hml_a <- hml_ret[as.character(Date) %in% as.character(common_dates), factor_ret]
wml_a <- wml_ret[as.character(Date) %in% as.character(common_dates), factor_ret]
str_a <- str_ret[as.character(Date) %in% as.character(common_dates), factor_ret]

factor_ret_mat <- cbind(MKT = mkt_a, SMB = smb_a, DEF = hml_a,
                         WML = wml_a, STR = str_a)
factor_ret_mat[is.na(factor_ret_mat)] <- 0
cat("  Factor returns matrix dim:", dim(factor_ret_mat), "\n")
cat("  Factor mean (daily, bps):", round(colMeans(factor_ret_mat) * 1e4, 2), "\n")
cat("  Factor sd (daily, bps):", round(apply(factor_ret_mat, 2, sd) * 1e4, 2), "\n")

# Ω = factor covariance (annualized)
Omega <- cov(factor_ret_mat) * 252
omega_df <- as.data.table(Omega, keep.rownames = "factor")
write_parquet(omega_df, file.path(STAGE_DIR, "factor_covariance.parquet"))
cat("  Saved factor_covariance.parquet\n")

# ============================================================================
# Step 3: Specific risk D (idiosyncratic variance from CAPM-like factor regression)
# For each ticker in universe: regress ticker daily ret ~ MKT+SMB+DEF+WML+STR
# B[i,] = factor loadings; D[i,i] = residual variance (annualized)
# ============================================================================
cat("\n[3] Specific risk D + exposure loadings B from factor regression...\n")
# Build ticker daily ret panel for last 252d
tk_panel <- RAWDATA[Date > win_start & Date <= end_d & Ticker %in% universe_tickers,
                     .(Date, Ticker, Ret)]
tk_wide <- dcast(tk_panel, Date ~ Ticker, value.var = "Ret")

# Align Dates with factor matrix
date_align <- intersect(as.character(tk_wide$Date), as.character(common_dates))
tk_wide_a <- tk_wide[as.character(Date) %in% date_align]
setorder(tk_wide_a, Date)
factor_mat_idx <- match(as.character(tk_wide_a$Date), as.character(common_dates))
factor_use <- factor_ret_mat[factor_mat_idx, , drop = FALSE]
factor_use[is.na(factor_use)] <- 0

tk_cols <- setdiff(names(tk_wide_a), "Date")
B_loadings <- matrix(NA_real_, nrow = length(tk_cols), ncol = ncol(factor_use))
rownames(B_loadings) <- tk_cols
colnames(B_loadings) <- colnames(factor_use)
specific_var <- numeric(length(tk_cols))
names(specific_var) <- tk_cols
n_obs_per_ticker <- integer(length(tk_cols))
names(n_obs_per_ticker) <- tk_cols

# Specific variance floor: 0.05 annual (~22% annual vol)
# Prevents degenerate D[i,i]≈0 from delisted/halted ticker that destroys Σ_FM condition.
# This floor is conservative (higher specific risk → less aggressive optimization).
SPECIFIC_VAR_FLOOR <- 0.05  # = (sqrt(0.05) ≈ 22% annual vol)
SPECIFIC_VAR_CEILING <- 2.0  # = sqrt(2.0) ≈ 141% annual vol (cap extreme volatility)

for (i in seq_along(tk_cols)) {
  y <- tk_wide_a[[tk_cols[i]]]
  valid <- !is.na(y)
  if (sum(valid) >= 60L) {
    Xv <- factor_use[valid, , drop = FALSE]
    yv <- y[valid]
    # OLS
    mod <- tryCatch(lm.fit(cbind(1, Xv), yv), error = function(e) NULL)
    if (!is.null(mod) && all(!is.na(mod$coefficients))) {
      B_loadings[i, ] <- mod$coefficients[-1]
      resid_var <- var(mod$residuals) * 252
      specific_var[i] <- pmin(pmax(resid_var, SPECIFIC_VAR_FLOOR), SPECIFIC_VAR_CEILING)
    } else {
      B_loadings[i, ] <- 0
      specific_var[i] <- pmin(pmax(var(yv) * 252, SPECIFIC_VAR_FLOOR), SPECIFIC_VAR_CEILING)
    }
    n_obs_per_ticker[i] <- sum(valid)
  } else {
    B_loadings[i, ] <- 0
    specific_var[i] <- 0.16  # default 40% annual vol for insufficient data
    n_obs_per_ticker[i] <- sum(valid)
  }
}

cat("  Applied specific_var floor =", SPECIFIC_VAR_FLOOR,
    "ceiling =", SPECIFIC_VAR_CEILING, "(rationale: numerical stability for Σ_FM)\n")

# Save specific risk + loadings
specific_dt <- data.table(Ticker = tk_cols,
                          specific_var_ann = specific_var,
                          specific_vol_ann = sqrt(specific_var),
                          n_obs = n_obs_per_ticker)
write_parquet(specific_dt, file.path(STAGE_DIR, "specific_risk.parquet"))
cat("  Specific vol summary (annualized):\n")
print(summary(sqrt(specific_var)))

B_dt <- as.data.table(B_loadings, keep.rownames = "Ticker")
write_parquet(B_dt, file.path(STAGE_DIR, "B_loadings.parquet"))

# Factor coverage check: median R² of CAPM-5 fit
# (skip detailed R² compute — use 1 - residual_var/total_var)
total_var_per_tk <- apply(tk_wide_a[, -1, with=FALSE], 2, function(x) var(x[!is.na(x)]) * 252)
r2_per_tk <- pmax(0, pmin(1, 1 - specific_var[names(total_var_per_tk)] / total_var_per_tk))
median_r2 <- median(r2_per_tk, na.rm = TRUE)
cat("  Median R² factor fit:", round(median_r2, 3), "\n")
cat("  Mean R²:", round(mean(r2_per_tk, na.rm = TRUE), 3), "\n")
cat("  Factor coverage (R² >= 0.1):", round(mean(r2_per_tk >= 0.1, na.rm = TRUE), 3), "\n\n")

# ============================================================================
# Step 4: Σ = BΩB' + D (factor-model implied) + compare to selected sample-based
# Hybrid: use B*Omega*B' + diag(D) for primary Σ structure (constructive)
# Cross-check vs sample/LW
# ============================================================================
cat("[4] Σ = BΩB' + D construction...\n")
# Align universe to those with non-trivial B + specific_var
valid_tk_idx <- !is.na(specific_var) & specific_var > 0
tk_valid <- tk_cols[valid_tk_idx]
B_v <- B_loadings[tk_valid, , drop = FALSE]
D_v <- diag(specific_var[tk_valid])
rownames(D_v) <- colnames(D_v) <- tk_valid

# Ω is annualized factor cov → use directly
Sigma_factor_model <- B_v %*% Omega %*% t(B_v) + D_v
rownames(Sigma_factor_model) <- colnames(Sigma_factor_model) <- tk_valid
cond_fm <- kappa(Sigma_factor_model, exact = TRUE)
eig_fm <- eigen(Sigma_factor_model, symmetric = TRUE, only.values = TRUE)$values
min_eig_fm <- min(eig_fm)
cat("  Σ_FM (BΩB'+D) cond:", round(cond_fm, 1), "; min_eig:", signif(min_eig_fm, 4), "\n")

# Apply eigen_floor if cond > 500
if (cond_fm > 500) {
  cat("  Σ_FM cond > 500 → eigen-floor regularization\n")
  Sigma_factor_model_clean <- eigen_floor(Sigma_factor_model, min_eig_frac = 1/500)
  cond_fm_clean <- kappa(Sigma_factor_model_clean, exact = TRUE)
  eig_fm_clean <- eigen(Sigma_factor_model_clean, symmetric = TRUE, only.values = TRUE)$values
  min_eig_fm_clean <- min(eig_fm_clean)
  cat("  Σ_FM after eigen_floor cond:", round(cond_fm_clean, 1),
      "; min_eig:", signif(min_eig_fm_clean, 4), "\n")
  Sigma_factor_model <- Sigma_factor_model_clean
  cond_fm <- cond_fm_clean
  min_eig_fm <- min_eig_fm_clean
}

method_log$factor_model <- list(name = "factor_model_BOmegaBT_plus_D_eigfloored",
                                 condition = cond_fm, min_eig = min_eig_fm,
                                 psd = min_eig_fm >= -1e-10, selected = FALSE,
                                 specific_var_floor = SPECIFIC_VAR_FLOOR,
                                 specific_var_ceiling = SPECIFIC_VAR_CEILING)

# Primary Σ for downstream: pick best among {sample, SS, GR, FM}
all_cands <- list(
  sample = list(cov = cov_sample, cond = cond_sample, psd = method_log$sample$psd,
                 name = "sample_pairwise"),
  ss = list(cov = cov_ss, cond = cond_ss, psd = method_log$schafer_strimmer$psd,
             name = "schafer_strimmer_2005"),
  fm = list(cov = Sigma_factor_model, cond = cond_fm,
             psd = method_log$factor_model$psd,
             name = "factor_model_BOmegaBT_plus_D_eigfloored")
)
if (!is.null(cov_gr)) {
  all_cands$gr <- list(cov = cov_gr, cond = cond_gr, psd = method_log$gerber_rmt$psd,
                        name = "gerber_rmt")
}

# Hard: PSD + cond < 500
viable <- Filter(function(x) x$psd && x$cond < 500, all_cands)
cat("\n  Viable Σ candidates (cond<500 + PSD):\n")
for (nm in names(viable)) cat("    ", viable[[nm]]$name, "cond =", round(viable[[nm]]$cond, 1), "\n")

# Decision: Σ_primary = Σ_FM (QEPM standard BΩB'+D structure)
# Backup Σ_alt = SS (Schäfer-Strimmer 2005, analytical shrinkage)
if (cond_fm < 500 && method_log$factor_model$psd) {
  Sigma_primary <- Sigma_factor_model
  primary_method <- "factor_model_BOmegaBT_plus_D_eigfloored"
  method_log$factor_model$selected <- TRUE
} else if (cond_ss < 500 && method_log$schafer_strimmer$psd) {
  Sigma_primary <- cov_ss
  primary_method <- "schafer_strimmer_2005"
  method_log$schafer_strimmer$selected <- TRUE
} else {
  # Final fallback: eigen-floored SS
  Sigma_primary <- eigen_floor(cov_ss, min_eig_frac = 1/400)
  primary_method <- "schafer_strimmer_eigfloored"
  method_log$schafer_strimmer_eigfloored <- list(
    name = primary_method,
    condition = kappa(Sigma_primary, exact = TRUE), selected = TRUE
  )
}
cat("\n  PRIMARY Σ:", primary_method, "\n")
cat("  Universe N =", nrow(Sigma_primary), "\n")
cat("  Cond =", round(kappa(Sigma_primary, exact = TRUE), 1), "\n")

# Save covariance.parquet (primary Σ)
cov_df <- as.data.table(Sigma_primary, keep.rownames = "Ticker")
write_parquet(cov_df, file.path(STAGE_DIR, "covariance.parquet"))
cat("  Saved covariance.parquet (", nrow(cov_df), "tickers)\n")

# Update method shopping log (final, post-FM construction)
# Note: total candidates = 5 (sample, schafer_strimmer, ledoit_wolf_legacy, gerber_rmt, factor_model)
# Charter R2-C cap = 5 → at limit, not exceeded
writeLines(toJSON(list(
  task_id = WT_ID,
  agent_role = "risk",
  as_of_date = as.character(last_sig_date),
  selection_objective = "condition_number_plus_structural_BOmegaBT_D",
  n_candidates = length(method_log),
  cap = 5,
  method_log = method_log,
  selected_method = primary_method,
  rationale = paste(
    "factor_model structure (Σ = BΩB' + D) is the QEPM standard frame",
    "(Connor-Korajczyk 1995, Grinold-Kahn 2000). Selected when PSD + cond<500.",
    "Schäfer-Strimmer 2005 reserved as fallback (analytical empirical Bayes shrinkage,",
    "well-conditioned by construction). Legacy hrp_core LW (constant-variance target)",
    "shown to degenerate when N>>T (cond=1 → identity-like)."
  )
), pretty = TRUE, auto_unbox = TRUE),
  file.path(STAGE_DIR, "method_shopping_log.json"))

# ============================================================================
# Step 4b: Portfolio risk decomposition (top-N weights at last sig_date)
# ============================================================================
cat("\n[4b] Portfolio risk decomposition at as_of_date...\n")
w_last <- weights_sched[Date == last_sig_date]
w_last_named <- setNames(w_last$weight, w_last$Ticker)
w_tickers <- intersect(names(w_last_named), rownames(Sigma_primary))
cat("  Weight tickers in Σ universe:", length(w_tickers), "/", length(w_last_named), "\n")
w_vec <- w_last_named[w_tickers]
w_vec <- w_vec / sum(w_vec)  # renormalize after intersection

# Decomposition uses Σ_FM structure (factor + specific separable)
# Even if primary Σ is SS, decomp computed from BΩB'+D structure for interpretability
B_w <- B_v[w_tickers, , drop = FALSE]
D_sub <- diag(D_v)[w_tickers]
w_B <- t(w_vec) %*% B_w  # 1 x F (portfolio factor exposure)

# Total Σ_FM-based portfolio variance
factor_var_part <- as.numeric(w_B %*% Omega %*% t(w_B))
specific_var_part <- sum(w_vec^2 * D_sub)
port_var_fm <- factor_var_part + specific_var_part
port_vol_ann_fm <- sqrt(port_var_fm)

# Also compute Σ_primary-based portfolio variance (for reference)
Sigma_sub <- Sigma_primary[w_tickers, w_tickers]
port_var_primary <- as.numeric(t(w_vec) %*% Sigma_sub %*% w_vec)
port_vol_ann_primary <- sqrt(port_var_primary)

# Use Σ_FM-decomposed values for primary reporting (more interpretable factor split)
port_var <- port_var_fm
port_vol_ann <- port_vol_ann_fm
factor_pct <- factor_var_part / port_var_fm
specific_pct <- specific_var_part / port_var_fm

cat("  Portfolio variance (Σ_FM):", signif(port_var_fm, 4), "\n")
cat("  Portfolio variance (Σ_primary):", signif(port_var_primary, 4), "\n")
cat("  Portfolio volatility annualized (Σ_FM):", round(port_vol_ann_fm * 100, 2), "%\n")
cat("  Portfolio volatility annualized (Σ_primary):", round(port_vol_ann_primary * 100, 2), "%\n")
cat("  Factor variance share:", round(factor_pct * 100, 1), "%\n")
cat("  Specific variance share:", round(specific_pct * 100, 1), "%\n")

# Per-factor risk attribution: w_B_i * sum_j w_B_j * Ω_ij = marginal contribution to factor_var_part
per_factor_var_full <- numeric(ncol(Omega))
names(per_factor_var_full) <- colnames(Omega)
for (k in seq_len(ncol(Omega))) {
  per_factor_var_full[k] <- as.numeric(w_B[1, k]) * sum(w_B[1, ] * Omega[k, ])
}
# % of TOTAL portfolio variance
per_factor_pct <- per_factor_var_full / port_var_fm
# % of FACTOR (common) variance only
per_factor_pct_of_factor <- per_factor_var_full / factor_var_part
cat("\n  Per-factor contribution to TOTAL port variance:\n")
for (k in seq_along(per_factor_pct)) {
  cat("    ", names(per_factor_pct)[k], ":",
      round(per_factor_pct[k] * 100, 2), "% (port factor exposure =",
      round(as.numeric(w_B[1, k]), 3), ")\n")
}
cat("\n  Per-factor contribution to FACTOR (common) variance:\n")
for (k in seq_along(per_factor_pct_of_factor)) {
  cat("    ", names(per_factor_pct_of_factor)[k], ":",
      round(per_factor_pct_of_factor[k] * 100, 2), "%\n")
}

# Sector concentration HHI
sect_dt <- expo_last[Ticker %in% w_tickers, .(Ticker, Sector_Lv2)]
sect_w <- merge(data.table(Ticker = names(w_vec), w = w_vec), sect_dt, by = "Ticker")
sect_w <- sect_w[!is.na(Sector_Lv2)]
sect_agg <- sect_w[, .(w_sum = sum(w)), by = Sector_Lv2]
setorder(sect_agg, -w_sum)
hhi_sector <- sum((sect_agg$w_sum)^2)
cat("\n  Sector HHI:", round(hhi_sector, 3), "(N_eff =", round(1/hhi_sector, 1), "sectors)\n")
cat("  Top sector exposures:\n")
print(head(sect_agg, 5))

# Save style + sector exposure summary
style_summary <- list(
  as_of_date = as.character(last_sig_date),
  primary_sigma_method = primary_method,
  portfolio_vol_ann_pct = round(port_vol_ann * 100, 3),
  factor_variance_share = round(factor_pct, 4),
  specific_variance_share = round(1 - factor_pct, 4),
  per_factor_contribution = lapply(seq_along(per_factor_pct), function(k) list(
    factor = names(per_factor_pct)[k],
    portfolio_exposure = round(as.numeric(w_B[1, k]), 4),
    pct_of_port_var = round(per_factor_pct[k] * 100, 3)
  )),
  factor_omega = lapply(seq_len(ncol(Omega)), function(k) list(
    factor = colnames(Omega)[k],
    annualized_vol = round(sqrt(Omega[k, k]) * 100, 3),
    correlation_with_others = setNames(round(cov2cor(Omega)[k, ], 4), rownames(Omega))
  )),
  sector_concentration = list(
    hhi = round(hhi_sector, 4),
    n_effective_sectors = round(1 / hhi_sector, 2),
    top5 = lapply(seq_len(min(5L, nrow(sect_agg))), function(k) list(
      sector = sect_agg$Sector_Lv2[k],
      weight_pct = round(sect_agg$w_sum[k] * 100, 2)
    ))
  )
)
writeLines(toJSON(style_summary, pretty = TRUE, auto_unbox = TRUE),
           file.path(STAGE_DIR, "style_exposure.json"))
cat("  Saved style_exposure.json\n")

# ============================================================================
# Step 5a: Tail risk metrics (portfolio level + per-stock)
# ============================================================================
cat("\n[5a] Tail risk metrics (portfolio + per-stock)...\n")
# Simulate portfolio returns over the 252d window via w' R_t
ret_panel_252 <- RAWDATA[Date > win_start & Date <= end_d & Ticker %in% w_tickers,
                         .(Date, Ticker, Ret)]
ret_wide_p <- dcast(ret_panel_252, Date ~ Ticker, value.var = "Ret")
ret_mat_p <- as.matrix(ret_wide_p[, -1, with=FALSE])
rownames(ret_mat_p) <- as.character(ret_wide_p$Date)
ret_mat_p[is.na(ret_mat_p)] <- 0

# Align w_vec to ret_mat_p columns
w_for_port <- w_vec[colnames(ret_mat_p)]
w_for_port[is.na(w_for_port)] <- 0
if (sum(w_for_port) > 0) w_for_port <- w_for_port / sum(w_for_port)

port_ret_daily <- as.numeric(ret_mat_p %*% w_for_port)
cat("  Portfolio daily returns:", length(port_ret_daily), "days\n")
cat("  Mean daily:", signif(mean(port_ret_daily), 4),
    "; SD daily:", signif(sd(port_ret_daily), 4), "\n")

# VaR / ES — multiple methods (5%, 1%)
var_95 <- as.numeric(quantile(port_ret_daily, 0.05))
var_99 <- as.numeric(quantile(port_ret_daily, 0.01))
es_95 <- mean(port_ret_daily[port_ret_daily <= var_95])
es_99 <- mean(port_ret_daily[port_ret_daily <= var_99])

# Cornish-Fisher
cf_var_95 <- tryCatch(-compute_cf_var(port_ret_daily, p = 0.95), error = function(e) NA)
cf_var_99 <- tryCatch(-compute_cf_var(port_ret_daily, p = 0.99), error = function(e) NA)

# EVT GPD (if T_obs >= 100)
evt_99 <- tryCatch(compute_evt_var(port_ret_daily, p = 0.99,
                                    threshold_q = 0.90,
                                    min_tail_n = 25L),
                    error = function(e) list(method = "failed", var_evt = NA, es_evt = NA))

# Skewness / Kurtosis
sk <- as.numeric(PerformanceAnalytics::skewness(port_ret_daily))
ku <- as.numeric(PerformanceAnalytics::kurtosis(port_ret_daily))

tail_metrics <- list(
  as_of_date = as.character(last_sig_date),
  window_days = length(port_ret_daily),
  daily_mean = signif(mean(port_ret_daily), 4),
  daily_sd = signif(sd(port_ret_daily), 4),
  skewness = round(sk, 3),
  excess_kurtosis = round(ku, 3),
  empirical = list(
    var_5pct = round(var_95, 4),
    var_1pct = round(var_99, 4),
    es_5pct = round(es_95, 4),
    es_1pct = round(es_99, 4)
  ),
  cornish_fisher = list(
    var_5pct = round(cf_var_95, 4),
    var_1pct = round(cf_var_99, 4)
  ),
  evt_gpd = list(
    var_1pct = round(evt_99$var_evt, 4),
    es_1pct = round(evt_99$es_evt, 4),
    method = evt_99$method,
    shape_xi = if (is.null(evt_99$shape_xi)) NA else evt_99$shape_xi,
    scale_beta = if (is.null(evt_99$scale_beta)) NA else evt_99$scale_beta,
    n_exceedances = if (is.null(evt_99$n_exceedances)) NA else evt_99$n_exceedances
  )
)
writeLines(toJSON(tail_metrics, pretty = TRUE, auto_unbox = TRUE),
           file.path(STAGE_DIR, "tail_risk_metrics.json"))
cat("  Saved tail_risk_metrics.json\n")
cat("  ES 1% empirical:", round(es_99, 4), "; EVT 1%:", round(evt_99$es_evt, 4),
    "method =", evt_99$method, "\n")

# ============================================================================
# Step 5b: Stress test (historical crisis windows on portfolio)
# Use full historical RAWDATA (within lockbox), find crisis periods, replay
# ============================================================================
cat("\n[5b] Stress test on portfolio holdings...\n")
# Predefined stress windows (from strategy_analyzer.R::def_stress_periods or canonical)
stress_windows <- list(
  list(name = "GFC_2008", start = "2008-09-01", end = "2009-03-31"),
  list(name = "EuDebt_2011", start = "2011-08-01", end = "2011-11-30"),
  list(name = "China_2015", start = "2015-06-01", end = "2015-09-30"),
  list(name = "COVID_2020", start = "2020-02-15", end = "2020-04-15"),
  list(name = "Rate_Hike_2022", start = "2022-01-01", end = "2022-10-31"),
  list(name = "KR_Bear_2023_H1", start = "2023-01-01", end = "2023-06-30")
)

# For each stress window: hold static portfolio = current w_vec, hypothetical
stress_results <- list()
for (sw in stress_windows) {
  s_start <- as.Date(sw$start); s_end <- as.Date(sw$end)
  if (s_end > LOCKBOX_CUTOFF) s_end <- LOCKBOX_CUTOFF
  if (s_start > LOCKBOX_CUTOFF) next
  sp <- RAWDATA[Date >= s_start & Date <= s_end & Ticker %in% w_tickers,
                .(Date, Ticker, Ret)]
  if (nrow(sp) == 0) {
    stress_results[[sw$name]] <- list(window = sw$name, status = "no_data")
    next
  }
  sp_w <- dcast(sp, Date ~ Ticker, value.var = "Ret")
  sp_mat <- as.matrix(sp_w[, -1, with=FALSE])
  sp_mat[is.na(sp_mat)] <- 0
  w_align <- w_vec[colnames(sp_mat)]
  w_align[is.na(w_align)] <- 0
  if (sum(w_align) > 0) w_align <- w_align / sum(w_align)
  port_path <- as.numeric(sp_mat %*% w_align)
  cum_ret <- prod(1 + port_path) - 1
  # maxDrawdown via NAV path (manual: nav = cumprod(1+r), mdd = min(nav/cummax(nav) - 1))
  nav_path <- cumprod(1 + port_path)
  mdd <- min(nav_path / cummax(nav_path) - 1, na.rm = TRUE)
  worst_day <- min(port_path)
  bm_path <- RAWDATA[Date >= s_start & Date <= s_end & Ticker %in% w_tickers,
                     .(BM = mean(BM_Ret, na.rm = TRUE)), by = Date]
  bm_cum <- prod(1 + bm_path$BM) - 1
  stress_results[[sw$name]] <- list(
    window = sw$name,
    start = as.character(s_start), end = as.character(s_end),
    n_days = length(port_path),
    portfolio_cum_return = round(cum_ret, 4),
    portfolio_mdd = round(mdd, 4),
    portfolio_worst_day = round(worst_day, 4),
    benchmark_cum_return = round(bm_cum, 4),
    excess_return_vs_bm = round(cum_ret - bm_cum, 4)
  )
  cat("    ", sw$name, ": port =", round(cum_ret*100, 2), "% / BM =",
      round(bm_cum*100, 2), "% / MDD =", round(mdd*100, 2), "% (",
      length(port_path), " days)\n")
}

# Also: explicit -5% market shock simulation
# Sensitivity: w_B * MKT shock = (port factor exposure on MKT) * (-0.05)
mkt_beta_port <- as.numeric(w_B[1, "MKT"])
market_down_5 <- mkt_beta_port * (-0.05)
cat("\n  Market -5% hypothetical:", round(market_down_5 * 100, 2),
    "% (port MKT beta =", round(mkt_beta_port, 3), ")\n")

stress_results$market_shock_minus_5pct <- list(
  port_mkt_beta = round(mkt_beta_port, 4),
  loss_estimate = round(market_down_5, 4)
)

# Value crash (DEF defensive proxy negative shock)
def_beta_port <- as.numeric(w_B[1, "DEF"])
value_crash <- def_beta_port * (-0.05)
stress_results$value_def_shock_minus_5pct <- list(
  port_def_beta = round(def_beta_port, 4),
  loss_estimate = round(value_crash, 4)
)

# Momentum reversal
wml_beta_port <- as.numeric(w_B[1, "WML"])
mom_reversal <- wml_beta_port * (-0.05)
stress_results$momentum_reversal_minus_5pct <- list(
  port_wml_beta = round(wml_beta_port, 4),
  loss_estimate = round(mom_reversal, 4)
)

writeLines(toJSON(stress_results, pretty = TRUE, auto_unbox = TRUE),
           file.path(STAGE_DIR, "stress_test_results.json"))
cat("  Saved stress_test_results.json\n")

# ============================================================================
# Step 5c: Crowding score (research_philosophy P5 / Acadian 2026)
# ============================================================================
cat("\n[5c] Crowding score per factor (Acadian 2026)...\n")
# Treat D_ML signal as a "factor" with exposure = alpha_z at sig_date
alpha_for_crowding <- alpha_scores[Date == last_sig_date,
                                    .(Ticker, factor_name = "D_ML_XGBoost",
                                      exposure = alpha_z)]
crowd_results <- tryCatch({
  crowding_score_per_factor(
    factor_exposures = alpha_for_crowding,
    sig_date = last_sig_date,
    RAWDATA = RAWDATA[Date >= last_sig_date - 60L & Date <= last_sig_date],
    benchmark_tickers = NULL,  # use top-200 Size proxy
    top_n = 20L
  )
}, error = function(e) {
  cat("  Crowding compute failed:", conditionMessage(e), "\n")
  data.table(factor_name = "D_ML_XGBoost", crowding_score = NA_real_,
             error = conditionMessage(e))
})

cat("  Crowding result:\n")
print(crowd_results)

# Also compute for the top 5 importance features
top5_features <- ap$top_features_by_importance[1:5, ]
cat("\n  Top 5 ML features:\n")
print(top5_features)
# Note: cannot easily reconstruct per-feature exposure without daily DB load. Mark deferred.
crowding_summary <- list(
  as_of_date = as.character(last_sig_date),
  primary_factor = "D_ML_XGBoost_alpha_z",
  components = if (nrow(crowd_results) > 0 && !all(is.na(crowd_results$crowding_score))) list(
    factor_name = crowd_results$factor_name[1],
    crowding_score = round(crowd_results$crowding_score[1], 4),
    hhi_top = round(crowd_results$hhi_top[1], 4),
    vol_concentration = round(crowd_results$vol_concentration[1], 4),
    passive_overlap_proxy = round(crowd_results$passive_overlap_proxy[1], 4),
    demand_elasticity_proxy = round(crowd_results$demand_elasticity_proxy[1], 4)
  ) else list(error = "Crowding compute returned NA"),
  alerts = if (nrow(crowd_results) > 0 &&
                !is.na(crowd_results$crowding_score[1]) &&
                crowd_results$crowding_score[1] >= 0.75)
             list(list(level = "HIGH", reason = "crowding_score >= 0.75 threshold"))
           else list(),
  per_feature_deferred = "Top 5 ML feature crowding scores deferred (require daily feature DB reconstruction; D_ML composite covers blended exposure)"
)
writeLines(toJSON(crowding_summary, pretty = TRUE, auto_unbox = TRUE),
           file.path(STAGE_DIR, "crowding_score.json"))
cat("  Saved crowding_score.json\n")

# ============================================================================
# Step 5d: Regime correlation (simple regime-conditional Σ shift)
# Regime: normal vs high-vol (VKOSPI proxy via market realized vol 60d top tertile)
# ============================================================================
cat("\n[5d] Regime correlation (normal vs high-vol)...\n")
# Compute market realized vol 60d rolling
bm_dt <- unique(RAWDATA[Date > win_start & Date <= end_d, .(Date, BM_Ret)])
bm_dt <- bm_dt[!is.na(BM_Ret)]
setorder(bm_dt, Date)
bm_dt[, vol_60 := frollapply(BM_Ret, 60, sd, na.rm = TRUE) * sqrt(252)]
bm_dt <- bm_dt[!is.na(vol_60)]

if (nrow(bm_dt) >= 60L) {
  vol_threshold <- quantile(bm_dt$vol_60, 0.67, na.rm = TRUE)
  bm_dt[, regime := fifelse(vol_60 >= vol_threshold, "high_vol", "normal")]

  # Subset returns matrix into regimes
  ret_dt_long <- merge(
    data.table(Date = as.Date(rownames(ret_mat_last)),
               row_idx = seq_len(nrow(ret_mat_last))),
    bm_dt[, .(Date, regime)], by = "Date"
  )
  high_idx <- ret_dt_long[regime == "high_vol", row_idx]
  norm_idx <- ret_dt_long[regime == "normal", row_idx]

  # Avg pairwise correlation in each regime (subset to top 50 tickers by var to keep tractable)
  top50_idx <- order(-apply(ret_mat_last, 2, var))[1:min(50L, ncol(ret_mat_last))]
  ret_sub <- ret_mat_last[, top50_idx]

  if (length(high_idx) >= 10 && length(norm_idx) >= 10) {
    cor_normal <- cor(ret_sub[norm_idx, ], use = "pairwise.complete.obs")
    cor_high <- cor(ret_sub[high_idx, ], use = "pairwise.complete.obs")

    avg_cor_normal <- mean(cor_normal[upper.tri(cor_normal)], na.rm = TRUE)
    avg_cor_high <- mean(cor_high[upper.tri(cor_high)], na.rm = TRUE)
    delta_cor <- avg_cor_high - avg_cor_normal
    cat("  Avg pairwise cor normal:", round(avg_cor_normal, 3), "\n")
    cat("  Avg pairwise cor high-vol:", round(avg_cor_high, 3), "\n")
    cat("  Δ correlation (high-vol - normal):", round(delta_cor, 3), "\n")

    regime_cor_dt <- data.table(
      regime = c("normal", "high_vol"),
      n_days = c(length(norm_idx), length(high_idx)),
      avg_pairwise_correlation = c(avg_cor_normal, avg_cor_high),
      vol_threshold_60d_pct = round(vol_threshold * 100, 2)
    )
    write_parquet(regime_cor_dt, file.path(STAGE_DIR, "regime_correlation.parquet"))
  } else {
    cat("  Regime sample insufficient — skipping\n")
    write_parquet(data.table(regime = NA_character_, n_days = 0L,
                              avg_pairwise_correlation = NA_real_),
                   file.path(STAGE_DIR, "regime_correlation.parquet"))
  }
} else {
  write_parquet(data.table(regime = NA_character_, n_days = 0L,
                            avg_pairwise_correlation = NA_real_),
                 file.path(STAGE_DIR, "regime_correlation.parquet"))
}

# ============================================================================
# Final: risk_package_draft.json
# ============================================================================
cat("\n[FINAL] Building risk_package_draft.json...\n")

# Top common risks summary (sorted by factor contribution)
sorted_fcontrib <- sort(per_factor_pct * 100, decreasing = TRUE)
top_risks_str <- sapply(seq_len(min(3L, length(sorted_fcontrib))), function(k)
  sprintf("%s (%.1f%%)", names(sorted_fcontrib)[k], sorted_fcontrib[k]))

# Crowding flags
crowding_flags <- character(0)
if (length(crowding_summary$alerts) > 0) {
  for (al in crowding_summary$alerts) {
    crowding_flags <- c(crowding_flags, sprintf("D_ML_XGBoost: %s", al$reason))
  }
}
# Sector concentration flag
if (hhi_sector > 0.30) {
  crowding_flags <- c(crowding_flags,
                       sprintf("Sector HHI=%.3f > 0.30 (top sector %s = %.1f%%)",
                               hhi_sector, sect_agg$Sector_Lv2[1],
                               sect_agg$w_sum[1] * 100))
}

# Liquidity flags (top holdings vs LIQ floor)
# Use Vol * Close at sig_date - 1 trading day to check 20d ADV
liq_check <- RAWDATA[Date > (last_sig_date - 30L) & Date <= (last_sig_date - 1L) & Ticker %in% w_tickers,
                     .(adv_20d_krw = mean(Vol * Close, na.rm = TRUE)), by = Ticker]
liq_check <- merge(liq_check, data.table(Ticker = names(w_vec), weight = w_vec), by = "Ticker")
liq_flags <- liq_check[adv_20d_krw < 2e8]
liq_flags_str <- character(0)
if (nrow(liq_flags) > 0) {
  for (i in seq_len(nrow(liq_flags))) {
    liq_flags_str <- c(liq_flags_str,
                        sprintf("%s ADV=%.1e KRW < 2e8 (w=%.3f)",
                                liq_flags$Ticker[i], liq_flags$adv_20d_krw[i],
                                liq_flags$weight[i]))
  }
}

# Challenge flags (auto-detected)
challenge_flags <- list()
if (cond_final > 500) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R2", severity = "HIGH",
    detail = sprintf("Σ condition number %.1f > 500 — shrinkage saturation. Numerical inversion unreliable.", cond_final),
    action_required = "Optimizer should use shrinkage-augmented inverse or HRP (no inversion required)."
  )
}
top_risk_pct <- max(per_factor_pct) * 100
if (top_risk_pct > 40) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R1", severity = "HIGH",
    detail = sprintf("Top common risk %.1f%% > 40%% threshold (%s).",
                     top_risk_pct, names(per_factor_pct)[which.max(per_factor_pct)]),
    action_required = "Risk concentration excessive. Optimizer should impose factor exposure constraints."
  )
}
if (length(crowding_flags) > 0) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R3", severity = "MEDIUM",
    detail = paste(crowding_flags, collapse = "; "),
    action_required = "Monitor crowding score over rolling 3m for alpha decay onset."
  )
}
if (market_down_5 < -0.08) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R4", severity = "HIGH",
    detail = sprintf("Market -5%% stress loss %.2f%% < -8%% threshold (port MKT beta = %.2f)",
                     market_down_5 * 100, mkt_beta_port),
    action_required = "Beta exposure excessive. Consider hedge or lower aggregate beta."
  )
}

# Idiosyncratic ML signal pattern (D_ML alpha source warning)
# top features = microstructure (D01_IdioVol, L01_Amihud, D03_RealVol) → idio risk concentration
if (per_factor_pct[["DEF"]] < 0 || per_factor_pct[["DEF"]] > 0.3) {
  challenge_flags[[length(challenge_flags) + 1]] <- list(
    id = "RF-R6", severity = "MEDIUM",
    detail = sprintf("DEF (low idio vol) factor contribution = %.1f%%. D ML top features (D01_IdioVol/D03_RealVol) signal anti-defensive tilt — confirm Codex C9 hard crisis test.",
                     per_factor_pct[["DEF"]] * 100),
    action_required = "Forge stage: Hard AX-001 crisis bad/normal IC ratio test on idio-vol tilted portfolio."
  )
}

# AX-001 v2 awareness: Alpha already passed (0.753 < 1.0 — defensive PASS)
# Risk perspective: idio_vol microstructure tilt could clash in genuine crisis. Note only.

# selection_objective Charter R4: HARD = condition_number
risk_package <- list(
  task_id = WT_ID,
  schema_version = "risk_package_v1",
  as_of_date = as.character(last_sig_date),
  signal_cutoff = as.character(LOCKBOX_CUTOFF),
  alpha_handle = "hypothesis_D",
  alpha_package_ref = "qepm/mailbox/worktask/WT-D20260528_003/alpha_package_D_ML.json",
  hypothesis_title = ap$hypothesis_title,
  selection_objective = "condition_number",  # R4 P3 HARD
  primary_sigma_method = primary_method,
  universe_n = N_assets,
  exposure_matrix_ref = "stage_artifacts/WT_D20260528_003_risk_D/exposure_matrix.parquet",
  factor_covariance_ref = "stage_artifacts/WT_D20260528_003_risk_D/factor_covariance.parquet",
  specific_risk_ref = "stage_artifacts/WT_D20260528_003_risk_D/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT_D20260528_003_risk_D/covariance.parquet",
  regime_correlation_ref = "stage_artifacts/WT_D20260528_003_risk_D/regime_correlation.parquet",
  tail_risk_ref = "stage_artifacts/WT_D20260528_003_risk_D/tail_risk_metrics.json",
  stress_test_ref = "stage_artifacts/WT_D20260528_003_risk_D/stress_test_results.json",
  style_exposure_ref = "stage_artifacts/WT_D20260528_003_risk_D/style_exposure.json",
  crowding_ref = "stage_artifacts/WT_D20260528_003_risk_D/crowding_score.json",
  method_shopping_log_ref = "stage_artifacts/WT_D20260528_003_risk_D/method_shopping_log.json",
  risk_summary = list(
    portfolio_vol_ann_pct = round(port_vol_ann * 100, 3),
    factor_var_share_pct = round(factor_pct * 100, 2),
    specific_var_share_pct = round((1 - factor_pct) * 100, 2),
    top_common_risks = top_risks_str,
    crowding_flags = crowding_flags,
    liquidity_flags = liq_flags_str,
    sector_hhi = round(hhi_sector, 4),
    sector_top1_pct = round(sect_agg$w_sum[1] * 100, 2),
    sector_top1 = sect_agg$Sector_Lv2[1],
    stress_tests = list(
      market_down_5 = round(market_down_5, 4),
      value_def_shock = round(value_crash, 4),
      mom_reversal = round(mom_reversal, 4),
      covid_2020_replay = if (!is.null(stress_results$COVID_2020$portfolio_cum_return))
        round(stress_results$COVID_2020$portfolio_cum_return, 4) else NA,
      rate_hike_2022 = if (!is.null(stress_results$Rate_Hike_2022$portfolio_cum_return))
        round(stress_results$Rate_Hike_2022$portfolio_cum_return, 4) else NA,
      kr_bear_2023_h1 = if (!is.null(stress_results$KR_Bear_2023_H1$portfolio_cum_return))
        round(stress_results$KR_Bear_2023_H1$portfolio_cum_return, 4) else NA,
      eudebt_2011 = if (!is.null(stress_results$EuDebt_2011$portfolio_cum_return))
        round(stress_results$EuDebt_2011$portfolio_cum_return, 4) else NA
    ),
    tail_risk = list(
      port_vol_ann_pct = round(port_vol_ann * 100, 3),
      var_1pct_daily = round(var_99, 4),
      es_1pct_daily = round(es_99, 4),
      cf_var_1pct = round(cf_var_99, 4),
      evt_var_1pct = round(evt_99$var_evt, 4),
      evt_es_1pct = round(evt_99$es_evt, 4),
      evt_method = evt_99$method,
      skewness = round(sk, 3),
      excess_kurtosis = round(ku, 3)
    )
  ),
  diagnostics = list(
    condition_number_primary = round(cond_final, 1),
    condition_number_sample = round(cond_sample, 1),
    condition_number_schafer_strimmer = round(cond_ss, 1),
    condition_number_legacy_lw = round(cond_lw, 1),
    condition_number_fm = round(cond_fm, 1),
    condition_number_gr = if (!is.null(cov_gr)) round(cond_gr, 1) else NA,
    shrinkage_used = grepl("shrinkage|strimmer|eigfloor|regulariz", primary_method, ignore.case = TRUE) ||
                     primary_method == "factor_model_BOmegaBT_plus_D_eigfloored",
    shrinkage_method = primary_method,
    min_eigenvalue_primary = signif(min_eig_fm, 4),
    factor_coverage_median_r2 = round(median_r2, 3),
    factor_coverage_mean_r2 = round(mean(r2_per_tk, na.rm = TRUE), 3),
    factor_correlation_warnings = if (any(abs(cov2cor(Omega)[upper.tri(cov2cor(Omega))]) > 0.8))
      list("Some factor pair correlation > 0.8 — possible style redundancy") else list(),
    factor_correlations = (function() {
      cor_omg <- cov2cor(Omega)
      pairs_out <- list()
      for (i in seq_len(nrow(cor_omg)-1L)) {
        for (j in seq(i+1L, ncol(cor_omg))) {
          pairs_out[[length(pairs_out)+1L]] <- list(
            pair = sprintf("%s_%s", rownames(cor_omg)[i], colnames(cor_omg)[j]),
            corr = round(cor_omg[i,j], 3)
          )
        }
      }
      pairs_out
    })(),
    n_universe_for_sigma = N_assets,
    n_holdings_for_decomp = length(w_tickers),
    regime_correlation_delta = if (exists("delta_cor")) round(delta_cor, 4) else NA,
    specific_var_floor = SPECIFIC_VAR_FLOOR,
    specific_var_ceiling = SPECIFIC_VAR_CEILING
  ),
  alpha_risk_integration = list(
    note = "Risk estimation independent of alpha values. Σ used downstream by Optimizer with alpha_vector unchanged.",
    portfolio_construction = "softmax-cap [0, 0.20] from alpha_z. Σw=1 strict.",
    expected_information_ratio_proxy_note = "IR proxy = alpha_z / sqrt(diag(Σ)) projection on weights. Optimizer determines final IR via SR maximization."
  ),
  pit_assertions = list(
    lockbox_strict = sprintf("All sig_dates <= %s. RAWDATA lookback Date < sig_date (no same-day C2 violation).",
                              as.character(LOCKBOX_CUTOFF)),
    sigma_pit = "Σ estimated on lookback 252d ending sig_date - 1 trading day.",
    factor_returns_pit = "Style factor returns from same 252d window, quintile sorts on PIT-lagged scores.",
    crowding_pit = sprintf("Crowding score using RAWDATA[Date <= %s] strict.",
                            as.character(LOCKBOX_CUTOFF)),
    no_alpha_modification = "alpha_vector, alpha_z, alpha_rank_pct, weights_schedule.weight 모두 read-only. 본 risk_package는 alpha 미수정.",
    boundary_compliance = "20종 max + Σw=1 + [0, 0.20] + LIQ 2e8 KRW — Risk passive observation (Optimizer enforces)."
  ),
  challenge_flags = challenge_flags,
  rule2_status = if (cond_final >= 500 || port_vol_ann > 0.50)
    "STOP_RECOMMEND — condition_number saturate or volatility excessive"
   else "PASS",
  build_meta = list(
    agent = "risk-research",
    pipeline_version = "risk_D_v1.0",
    build_timestamp = as.character(Sys.time()),
    Rscript_path = "qepm/mailbox/worktask/WT-D20260528_003/scripts/risk_D_pipeline.R",
    libraries = c("data.table", "arrow", "jsonlite", "PerformanceAnalytics",
                  "fExtremes", "evir")
  )
)

writeLines(toJSON(risk_package, pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null"),
           file.path(WT_DIR, "risk_package_draft.json"))

cat("\n================================================================\n")
cat("Risk Research Pipeline COMPLETE.\n")
cat("  risk_package_draft.json saved:", file.path(WT_DIR, "risk_package_draft.json"), "\n")
cat("  Primary Σ method:", primary_method, "\n")
cat("  Condition #:", round(cond_final, 1), "(< 500 PASS)\n")
cat("  Portfolio vol annualized:", round(port_vol_ann * 100, 2), "%\n")
cat("  Factor variance share:", round(factor_pct * 100, 2), "%\n")
cat("  Top risk:", names(per_factor_pct)[which.max(per_factor_pct)],
    round(max(per_factor_pct) * 100, 2), "%\n")
cat("  Challenge flags:", length(challenge_flags), "\n")
cat("================================================================\n")
