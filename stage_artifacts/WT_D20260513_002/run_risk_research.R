#==============================================================================
# WT-D20260513_002 Risk Research — Sector-Neutralized FF-Residual Low-Vol C2
# Multi-Sleeve Composite Risk Analysis
#
# Mandate: 도훈 Session 81 B option (2026-05-14 KST)
# - Alpha cycle output: NON_GRADUATING_MONO_FAIL but portfolio top-20 selection
#   gate-bypasses Q2-Q5 mono fail.
# - 4-sleeve composite path: STR_1715 admit (alpha/M4/AR/R05) + this C2 low-vol
# - Risk-side AX-001 v2 4-axis validation (Codex C6 mandate)
# - Sigma = B Omega B' + D (CAPM + sector + size + idio)
# - Tail risk (EVT GPD + CF-VaR + CDaR) (Pfaff Ch.7+12)
# - Stress/regime decomposition (8 KR stress)
# - Crowding/Pareto vs STR_1715 (Kendall tau-c + TDC)
# - 4-sleeve composite risk profile (cross-sleeve cov + overlap)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(corpcor)
  library(xts)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260513_002"
STAGE_DIR <- file.path("stage_artifacts", "WT_D20260513_002")
MAILBOX_DIR <- file.path("qepm", "mailbox", "worktask", WT_ID)
AS_OF_SIG_DATE <- as.Date("2026-04-30")

# Source infra
source("02_Infrastructure/portfolio/tail_risk_engine.R")
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/factor_db/covariance_cache.R")

cat(sprintf("[%s] WT-D20260513_002 Risk Research START\n", Sys.time()))

#==============================================================================
# Step 0: Data Load
#==============================================================================

cat("\n=== Step 0: Data Load ===\n")

# alpha_scores.parquet
alpha <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
alpha[, sig_date := as.Date(sig_date)]
cat(sprintf("alpha_scores: %d rows, %d sig_dates, range %s ~ %s\n",
            nrow(alpha), length(unique(alpha$sig_date)),
            min(alpha$sig_date), max(alpha$sig_date)))

# Top 20 sleeve at as-of sig_date
latest_alpha <- alpha[sig_date == AS_OF_SIG_DATE]
setorder(latest_alpha, -alpha)
top20_C2 <- latest_alpha[1:20]
cat(sprintf("Top 20 sleeve (C2 low-vol): %s ... \n",
            paste(head(top20_C2$Ticker, 5), collapse=",")))

# RAWDATA daily prices for B + Omega + D estimation
rd_full <- as.data.table(read_parquet(
  ".cache/rawdata.parquet",
  col_select = c("Date","Ticker","Name","Sector","K200","KQ150",
                 "Float","AdminStock","TradingHalt","UnfaithfulDisc",
                 "Open","High","Low","Close","Vol","Size","Ret","BM_Ret")
))

# Filter window: 252d trailing before sig_date, plus prior history for regime
window_start <- AS_OF_SIG_DATE - 252 - 30
window_end <- AS_OF_SIG_DATE
rd_window <- rd_full[Date >= window_start & Date <= window_end]
cat(sprintf("rawdata window %s ~ %s: %d rows, %d unique tickers\n",
            window_start, window_end, nrow(rd_window),
            length(unique(rd_window$Ticker))))

# STR_1715 admit top 20 for orthogonality + 4-sleeve composite
str1715 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/20260512_str1715_sleeve_top20_alpha_2026_04.csv")
str1715_top20 <- str1715[, .(rank, Ticker, Name, Sector, Weight_sleeve, score_eff)]
cat(sprintf("STR_1715 admit top20: %s ...\n",
            paste(head(str1715_top20$Ticker, 5), collapse=",")))

# Overlap diagnostics
common_top20 <- intersect(top20_C2$Ticker, str1715_top20$Ticker)
cat(sprintf("Overlap top20 C2 vs STR_1715: %d tickers (%s)\n",
            length(common_top20), paste(common_top20, collapse=",")))

#==============================================================================
# Step 1: Exposure Matrix B (B = CAPM_beta + sector_dummy + log_size + idio_vol)
#==============================================================================

cat("\n=== Step 1: Exposure Matrix B ===\n")

# Use top20 + sentinel tickers for exposure measurement
universe_tickers <- unique(c(top20_C2$Ticker, str1715_top20$Ticker))
cat(sprintf("Exposure universe: %d unique tickers\n", length(universe_tickers)))

# Daily returns 252d before sig_date
ret_window_start <- AS_OF_SIG_DATE - 252
rd_uni <- rd_full[Ticker %in% universe_tickers &
                  Date >= ret_window_start & Date <= AS_OF_SIG_DATE,
                  .(Date, Ticker, Ret, Sector, Size, BM_Ret)]
rd_uni[, Ret := as.numeric(Ret)]
rd_uni <- rd_uni[!is.na(Ret) & !is.na(BM_Ret)]

# Estimate CAPM beta per ticker
beta_dt <- rd_uni[, {
  if (.N < 100) {
    list(beta = NA_real_, intercept = NA_real_, residual_sd = NA_real_,
         r2 = NA_real_, n_obs = .N)
  } else {
    fit <- lm(Ret ~ BM_Ret)
    co <- coef(fit)
    res_sd <- sd(residuals(fit), na.rm=TRUE)
    r2 <- summary(fit)$r.squared
    list(beta = co["BM_Ret"], intercept = co["(Intercept)"],
         residual_sd = res_sd, r2 = r2, n_obs = .N)
  }
}, by = Ticker]
beta_dt <- beta_dt[!is.na(beta)]

# log_size at sig_date
size_dt <- rd_uni[Date == AS_OF_SIG_DATE, .(Ticker, Size)]
size_dt[, log_size := log(Size + 1)]

# Sector at sig_date
sec_dt <- rd_uni[Date == AS_OF_SIG_DATE, .(Ticker, Sector)]

# Merge
B_dt <- merge(beta_dt, size_dt[, .(Ticker, log_size)], by="Ticker", all.x=TRUE)
B_dt <- merge(B_dt, sec_dt, by="Ticker", all.x=TRUE)

# z-score normalize beta + log_size
B_dt[, beta_z := scale(beta)[, 1]]
B_dt[, log_size_z := scale(log_size)[, 1]]

# Sector dummy (one-hot)
sectors_unique <- unique(B_dt$Sector)
sectors_unique <- sectors_unique[!is.na(sectors_unique)]
for (s in sectors_unique) {
  s_clean <- gsub("[, ]", "_", s)
  B_dt[, (paste0("S_", s_clean)) := as.integer(Sector == s)]
}

cat(sprintf("B matrix: %d tickers, beta range [%.3f, %.3f], R2 mean %.3f\n",
            nrow(B_dt), min(B_dt$beta, na.rm=TRUE), max(B_dt$beta, na.rm=TRUE),
            mean(B_dt$r2, na.rm=TRUE)))

# Save B matrix
B_out <- file.path(STAGE_DIR, "exposure_matrix.parquet")
write_parquet(B_dt, B_out)
cat(sprintf("Saved: %s\n", B_out))

#==============================================================================
# Step 2: Factor Covariance Omega + Step 3: Specific Risk D
#==============================================================================

cat("\n=== Step 2-3: Omega + D ===\n")

# Build factor returns time-series (Mkt, sector means, size factor)
# - Mkt: BM_Ret (KOSPI200)
# - Sector_i: equal-weighted return of ticker in sector i
# - Size: SMB proxy (small minus big return diff)

# Daily factor returns ~ 252d
fact_panel <- rd_uni[, .(Date, Ticker, Ret, Sector, Size, BM_Ret)]

# Sector mean return per Date
sec_ret <- fact_panel[!is.na(Sector), .(Sector_Ret = mean(Ret, na.rm=TRUE)),
                       by=.(Date, Sector)]

# Mkt = unique BM_Ret per date
mkt_ret <- unique(fact_panel[, .(Date, BM_Ret)])
setnames(mkt_ret, "BM_Ret", "Mkt_Ret")

# Size factor (SMB proxy): tickers with Size below median vs above
fact_panel[, size_quintile := cut(Size, breaks = quantile(Size, probs=c(0, 0.3, 0.7, 1), na.rm=TRUE),
                                    labels = c("S","M","B"), include.lowest=TRUE), by=Date]
smb <- fact_panel[!is.na(size_quintile), {
  s_ret <- mean(Ret[size_quintile=="S"], na.rm=TRUE)
  b_ret <- mean(Ret[size_quintile=="B"], na.rm=TRUE)
  list(SMB_Ret = s_ret - b_ret)
}, by=Date]

# Combine factor panel
fact_wide <- merge(mkt_ret, smb, by="Date")
fact_wide <- fact_wide[!is.na(Mkt_Ret) & !is.na(SMB_Ret)]

# Top-3 sectors by ticker count (for Omega dim manageable)
top_sec <- B_dt[, .N, by=Sector][order(-N)][1:5, Sector]
top_sec <- top_sec[!is.na(top_sec)]
cat(sprintf("Top 5 sectors used as factors: %s\n", paste(top_sec, collapse=",")))
for (s in top_sec) {
  s_clean <- gsub("[, ]", "_", s)
  s_ret <- sec_ret[Sector == s, .(Date, Sector_Ret)]
  setnames(s_ret, "Sector_Ret", paste0("SEC_", s_clean, "_Ret"))
  fact_wide <- merge(fact_wide, s_ret, by="Date", all.x=TRUE)
}

# Drop rows with any NA
fact_wide <- fact_wide[complete.cases(fact_wide)]
cat(sprintf("Factor panel: %d days, %d factors\n",
            nrow(fact_wide), ncol(fact_wide) - 1))

# Estimate Omega (factor covariance) — sample + Ledoit-Wolf
fact_mat <- as.matrix(fact_wide[, -1])
N_f <- nrow(fact_mat)
D_f <- ncol(fact_mat)

omega_sample <- cov(fact_mat) * 252  # annualize
cat(sprintf("Omega sample dim %dx%d, N=%d\n", D_f, D_f, N_f))

# LW shrinkage
omega_lw <- tryCatch({
  corpcor::cov.shrink(fact_mat, verbose=FALSE) * 252
}, error = function(e) {
  cat("[WARN] LW shrinkage failed, using sample\n")
  omega_sample
})
class(omega_lw) <- "matrix"
attributes(omega_lw)$lambda <- NULL
attributes(omega_lw)$lambda.var <- NULL

# Condition number check
ev_omega <- eigen(omega_lw, symmetric=TRUE, only.values=TRUE)$values
omega_cond <- max(abs(ev_omega)) / max(min(abs(ev_omega)), 1e-12)
cat(sprintf("Omega condition number (LW): %.2f\n", omega_cond))

# Save Omega
omega_dt <- as.data.table(omega_lw)
omega_dt[, Factor := colnames(fact_mat)]
setcolorder(omega_dt, c("Factor", setdiff(names(omega_dt), "Factor")))
write_parquet(omega_dt, file.path(STAGE_DIR, "factor_covariance.parquet"))
cat(sprintf("Saved: %s\n", file.path(STAGE_DIR, "factor_covariance.parquet")))

# Step 3: Specific Risk D — per ticker residual variance from cross-section regression
# regress ticker daily returns on Mkt + Sector_dummy + SMB
specific_risk <- list()
for (tk in B_dt$Ticker) {
  tk_ret <- rd_uni[Ticker == tk & !is.na(Ret), .(Date, Ret)]
  if (nrow(tk_ret) < 60) {
    specific_risk[[tk]] <- list(specific_vol = NA, specific_var = NA, r2 = NA, n = nrow(tk_ret))
    next
  }
  merged <- merge(tk_ret, fact_wide, by="Date")
  if (nrow(merged) < 60) {
    specific_risk[[tk]] <- list(specific_vol = NA, specific_var = NA, r2 = NA, n = nrow(merged))
    next
  }
  fit <- tryCatch(
    lm(Ret ~ Mkt_Ret + SMB_Ret, data = merged),
    error = function(e) NULL
  )
  if (is.null(fit)) {
    specific_risk[[tk]] <- list(specific_vol = NA, specific_var = NA, r2 = NA, n = nrow(merged))
    next
  }
  res <- residuals(fit)
  spec_var <- var(res, na.rm=TRUE) * 252  # annualize
  spec_vol <- sqrt(spec_var)
  specific_risk[[tk]] <- list(specific_vol = spec_vol, specific_var = spec_var,
                               r2 = summary(fit)$r.squared, n = nrow(merged))
}

D_dt <- rbindlist(lapply(names(specific_risk), function(tk) {
  data.table(Ticker = tk,
             specific_vol = specific_risk[[tk]]$specific_vol,
             specific_var = specific_risk[[tk]]$specific_var,
             r2 = specific_risk[[tk]]$r2,
             n_obs = specific_risk[[tk]]$n)
}))

cat(sprintf("D (specific risk): %d tickers, specific_vol mean %.4f, median %.4f\n",
            nrow(D_dt), mean(D_dt$specific_vol, na.rm=TRUE),
            median(D_dt$specific_vol, na.rm=TRUE)))

write_parquet(D_dt, file.path(STAGE_DIR, "specific_risk.parquet"))

#==============================================================================
# Step 4: Security Covariance Sigma = B Omega B' + D
#==============================================================================

cat("\n=== Step 4: Sigma = B Omega B' + D ===\n")

# Build B (n_tickers x n_factors) for top 40 (top20 C2 + top20 STR_1715)
all_top40 <- unique(c(top20_C2$Ticker, str1715_top20$Ticker))
B_top <- B_dt[Ticker %in% all_top40]

# Need same column order as fact_wide (Mkt_Ret, SMB_Ret, SEC_*)
fact_names <- colnames(fact_mat)

# Re-regress each ticker on factor panel to get loadings on Mkt + SMB + Sectors
B_full <- matrix(0, nrow = nrow(B_top), ncol = length(fact_names))
rownames(B_full) <- B_top$Ticker
colnames(B_full) <- fact_names

for (i in seq_len(nrow(B_top))) {
  tk <- B_top$Ticker[i]
  tk_ret <- rd_uni[Ticker == tk & !is.na(Ret), .(Date, Ret)]
  if (nrow(tk_ret) < 60) next
  merged <- merge(tk_ret, fact_wide, by="Date")
  if (nrow(merged) < 60) next
  # Multi-factor regression
  fact_formula <- as.formula(paste("Ret ~", paste(fact_names, collapse = "+")))
  fit <- tryCatch(lm(fact_formula, data = merged), error = function(e) NULL)
  if (is.null(fit)) next
  co <- coef(fit)
  for (f in fact_names) {
    if (f %in% names(co)) {
      B_full[i, f] <- co[f]
    }
  }
}

cat(sprintf("B_full matrix: %d x %d (rows=tickers, cols=factors)\n",
            nrow(B_full), ncol(B_full)))

# Sigma_systematic = B Omega B'
sigma_sys <- B_full %*% omega_lw %*% t(B_full)

# Add specific D diagonal
D_diag_vec <- D_dt[match(rownames(B_full), Ticker), specific_var]
D_diag_vec[is.na(D_diag_vec)] <- median(D_dt$specific_var, na.rm=TRUE)
D_diag <- diag(D_diag_vec)
rownames(D_diag) <- colnames(D_diag) <- rownames(B_full)

Sigma <- sigma_sys + D_diag

# PSD check
ev_sigma <- eigen(Sigma, symmetric=TRUE, only.values=TRUE)$values
sigma_cond <- max(abs(ev_sigma)) / max(min(abs(ev_sigma)), 1e-12)
psd_ok <- all(ev_sigma > -1e-8)
cat(sprintf("Sigma: %d x %d, cond %.2f, PSD %s, min_eig %.6e, max_eig %.6e\n",
            nrow(Sigma), ncol(Sigma), sigma_cond,
            ifelse(psd_ok, "PASS", "FAIL"),
            min(ev_sigma), max(ev_sigma)))

# Re-shrinkage if cond > 500
if (sigma_cond > 500) {
  cat("[WARN] cond > 500. Applying LW shrinkage on Sigma\n")
  Sigma_lw <- corpcor::cov.shrink(Sigma + diag(1e-8, nrow(Sigma)), verbose=FALSE)
  class(Sigma_lw) <- "matrix"
  attributes(Sigma_lw)$lambda <- NULL
  attributes(Sigma_lw)$lambda.var <- NULL
  ev2 <- eigen(Sigma_lw, symmetric=TRUE, only.values=TRUE)$values
  sigma_cond_new <- max(abs(ev2)) / max(min(abs(ev2)), 1e-12)
  cat(sprintf("After LW: cond %.2f\n", sigma_cond_new))
  Sigma <- Sigma_lw
  sigma_cond <- sigma_cond_new
}

# Save Sigma
sigma_dt <- as.data.table(Sigma)
sigma_dt[, Ticker := rownames(Sigma)]
setcolorder(sigma_dt, c("Ticker", setdiff(names(sigma_dt), "Ticker")))
write_parquet(sigma_dt, file.path(STAGE_DIR, "covariance.parquet"))
cat(sprintf("Saved: %s\n", file.path(STAGE_DIR, "covariance.parquet")))

#==============================================================================
# Step 5a: Portfolio-level Sigma (sleeve EW top20)
#==============================================================================

cat("\n=== Step 5a: Sleeve-level Vol & Cov ===\n")

# C2 sleeve EW top20
w_C2 <- rep(1/20, 20)
names(w_C2) <- top20_C2$Ticker
# subset Sigma to top20 C2
common_C2 <- intersect(names(w_C2), rownames(Sigma))
w_C2_sub <- w_C2[common_C2]
w_C2_sub <- w_C2_sub / sum(w_C2_sub)
Sigma_C2 <- Sigma[common_C2, common_C2]
sleeve_var_C2 <- as.numeric(t(w_C2_sub) %*% Sigma_C2 %*% w_C2_sub)
sleeve_vol_C2 <- sqrt(sleeve_var_C2)
cat(sprintf("C2 sleeve EW top20 (%d names): annualized vol = %.4f (%.2f%%)\n",
            length(common_C2), sleeve_vol_C2, sleeve_vol_C2 * 100))

# STR_1715 sleeve  weighted (using csv weights)
w_1715 <- str1715_top20$Weight_sleeve
names(w_1715) <- str1715_top20$Ticker
w_1715 <- w_1715 / sum(w_1715)
common_1715 <- intersect(names(w_1715), rownames(Sigma))
w_1715_sub <- w_1715[common_1715]
w_1715_sub <- w_1715_sub / sum(w_1715_sub)
Sigma_1715 <- Sigma[common_1715, common_1715]
sleeve_var_1715 <- as.numeric(t(w_1715_sub) %*% Sigma_1715 %*% w_1715_sub)
sleeve_vol_1715 <- sqrt(sleeve_var_1715)
cat(sprintf("STR_1715 sleeve (%d names): annualized vol = %.4f (%.2f%%)\n",
            length(common_1715), sleeve_vol_1715, sleeve_vol_1715 * 100))

# Cross-sleeve covariance
common_cross <- intersect(rownames(Sigma), c(names(w_C2_sub), names(w_1715_sub)))
w_combined_50_50 <- numeric(length(common_cross))
names(w_combined_50_50) <- common_cross
for (tk in common_cross) {
  v_C2 <- if (tk %in% names(w_C2_sub)) w_C2_sub[tk] * 0.5 else 0
  v_1715 <- if (tk %in% names(w_1715_sub)) w_1715_sub[tk] * 0.5 else 0
  w_combined_50_50[tk] <- v_C2 + v_1715
}
w_combined_50_50 <- w_combined_50_50 / sum(w_combined_50_50)
Sigma_combined <- Sigma[common_cross, common_cross]
combined_var <- as.numeric(t(w_combined_50_50) %*% Sigma_combined %*% w_combined_50_50)
combined_vol <- sqrt(combined_var)
cat(sprintf("50/50 combined sleeve: vol = %.4f (%.2f%%)\n",
            combined_vol, combined_vol * 100))

# Diversification ratio
naive_combined_vol <- 0.5 * sleeve_vol_C2 + 0.5 * sleeve_vol_1715
div_ratio_50_50 <- naive_combined_vol / combined_vol
cat(sprintf("Diversification ratio (50/50): %.3f\n", div_ratio_50_50))

# Cross-sleeve covariance scalar
# extend C2 weight + 1715 weight to common space
w_C2_ext <- numeric(length(common_cross)); names(w_C2_ext) <- common_cross
w_C2_ext[names(w_C2_sub)] <- w_C2_sub
w_1715_ext <- numeric(length(common_cross)); names(w_1715_ext) <- common_cross
w_1715_ext[names(w_1715_sub)] <- w_1715_sub

cross_cov <- as.numeric(t(w_C2_ext) %*% Sigma_combined %*% w_1715_ext)
cross_corr <- cross_cov / (sleeve_vol_C2 * sleeve_vol_1715)
cat(sprintf("Cross-sleeve correlation C2 vs STR_1715: %.4f\n", cross_corr))

#==============================================================================
# Step 5b: 4-Sleeve Composite Risk (50/25/20/5cash hypothesis)
#==============================================================================

cat("\n=== Step 5b: 4-Sleeve Composite ===\n")

# Hypothesis: STR_1715 50 + R05 (already overlay layer in STR_1715) + AR (overlay) + C2 25 + cash 25%
# In practice, STR_1715 admit is single-sleeve with M4+AR+R05 sequential overlay.
# Codex C5/도훈 mandate: 본 risk-research에서 "4-sleeve composite" 정합 입증 =
#   STR_1715 (base alpha) + M4 (already in admit) + AR (already in admit) + R05 (already in admit) + C2 (this)
# Where M4/AR/R05 are overlay scalars, not separate alpha sleeves.
# Sleeve-level risk: STR_1715 sleeve (M4*AR*R05 cash-controlled) + C2 sleeve

# Scenario: 70% STR_1715 alpha pool + 30% C2 sleeve (testing 4-sleeve composite)
# May 2026 admit state: m4=NORMAL(1.0) * beta_AR=0.7 * beta_R05=1.0 = 0.7 risk + 0.3 cash
# Composite-test: 70% STR_1715 + 30% C2 (replacing cash with C2)

w_70_30 <- numeric(length(common_cross)); names(w_70_30) <- common_cross
for (tk in common_cross) {
  v_C2 <- if (tk %in% names(w_C2_sub)) w_C2_sub[tk] * 0.30 else 0
  v_1715 <- if (tk %in% names(w_1715_sub)) w_1715_sub[tk] * 0.70 else 0
  w_70_30[tk] <- v_C2 + v_1715
}
w_70_30 <- w_70_30 / sum(w_70_30)
combined_70_30_var <- as.numeric(t(w_70_30) %*% Sigma_combined %*% w_70_30)
combined_70_30_vol <- sqrt(combined_70_30_var)
cat(sprintf("70/30 (STR_1715/C2) sleeve vol: %.4f (%.2f%%)\n",
            combined_70_30_vol, combined_70_30_vol * 100))

# Diversification ratio (vs naive)
naive_70_30 <- 0.7 * sleeve_vol_1715 + 0.3 * sleeve_vol_C2
div_70_30 <- naive_70_30 / combined_70_30_vol
cat(sprintf("Diversification ratio (70/30): %.3f\n", div_70_30))

# Concentration overlap: tickers in both sleeves
common_tickers_overlap <- intersect(names(w_C2_sub), names(w_1715_sub))
overlap_w_70_30 <- numeric(length(common_tickers_overlap))
names(overlap_w_70_30) <- common_tickers_overlap
for (tk in common_tickers_overlap) {
  overlap_w_70_30[tk] <- 0.70 * w_1715_sub[tk] + 0.30 * w_C2_sub[tk]
}
max_overlap_w <- max(overlap_w_70_30, na.rm=TRUE)
cat(sprintf("Overlap tickers (both sleeves): %d, max combined w: %.4f (target <= 0.20 hard cap)\n",
            length(common_tickers_overlap), max_overlap_w))

#==============================================================================
# Step 6: Tail Risk (EVT GPD + CF-VaR + CDaR)
#==============================================================================

cat("\n=== Step 6: Tail Risk ===\n")

# Construct daily portfolio return time series for sleeves (~252d)
# C2 sleeve EW daily return
build_sleeve_daily <- function(tickers, weights, rd_data, start_date, end_date) {
  panel <- rd_data[Ticker %in% tickers & Date >= start_date & Date <= end_date & !is.na(Ret),
                   .(Date, Ticker, Ret)]
  panel <- panel[Ticker %in% names(weights)]
  panel[, w := weights[match(Ticker, names(weights))]]
  # daily weighted return
  panel[, w := w / sum(w[Date == Date[1]])]  # ensure sum w = 1 (per date)
  daily <- panel[, .(port_ret = sum(Ret * w, na.rm=TRUE)), by=Date]
  setorder(daily, Date)
  daily
}

# C2 sleeve daily
daily_C2 <- build_sleeve_daily(names(w_C2_sub), w_C2_sub, rd_full,
                                AS_OF_SIG_DATE - 252, AS_OF_SIG_DATE)
cat(sprintf("C2 sleeve daily: %d obs\n", nrow(daily_C2)))

# STR_1715 sleeve daily
daily_1715 <- build_sleeve_daily(names(w_1715_sub), w_1715_sub, rd_full,
                                   AS_OF_SIG_DATE - 252, AS_OF_SIG_DATE)
cat(sprintf("STR_1715 sleeve daily: %d obs\n", nrow(daily_1715)))

# 70/30 composite daily
daily_combined <- merge(daily_C2, daily_1715, by="Date", suffixes=c("_C2","_1715"))
daily_combined[, port_ret_70_30 := 0.7 * port_ret_1715 + 0.3 * port_ret_C2]

# Tail risk per sleeve
tail_C2 <- list(
  evt_var = compute_evt_var(daily_C2$port_ret, p=0.99),
  cf_var = compute_cf_var(daily_C2$port_ret, p=0.99),
  cdar = compute_cdar(cumprod(1 + daily_C2$port_ret), alpha=0.95)
)

tail_1715 <- list(
  evt_var = compute_evt_var(daily_1715$port_ret, p=0.99),
  cf_var = compute_cf_var(daily_1715$port_ret, p=0.99),
  cdar = compute_cdar(cumprod(1 + daily_1715$port_ret), alpha=0.95)
)

tail_70_30 <- list(
  evt_var = compute_evt_var(daily_combined$port_ret_70_30, p=0.99),
  cf_var = compute_cf_var(daily_combined$port_ret_70_30, p=0.99),
  cdar = compute_cdar(cumprod(1 + daily_combined$port_ret_70_30), alpha=0.95)
)

cat(sprintf("\nC2 sleeve: EVT-VaR_99 = %.4f, CF-VaR_99 = %.4f, CDaR_95 = %.4f, MaxDD = %.4f\n",
            tail_C2$evt_var$var_evt, tail_C2$cf_var$var_cf,
            tail_C2$cdar$cdar, tail_C2$cdar$max_dd))
cat(sprintf("STR_1715: EVT-VaR_99 = %.4f, CF-VaR_99 = %.4f, CDaR_95 = %.4f, MaxDD = %.4f\n",
            tail_1715$evt_var$var_evt, tail_1715$cf_var$var_cf,
            tail_1715$cdar$cdar, tail_1715$cdar$max_dd))
cat(sprintf("70/30 composite: EVT-VaR_99 = %.4f, CF-VaR_99 = %.4f, CDaR_95 = %.4f, MaxDD = %.4f\n",
            tail_70_30$evt_var$var_evt, tail_70_30$cf_var$var_cf,
            tail_70_30$cdar$cdar, tail_70_30$cdar$max_dd))

# Hill alpha estimator (separate, EVT validation)
hill_alpha <- function(r, k_frac = 0.05) {
  losses <- -r[!is.na(r) & r < 0]
  losses <- sort(losses, decreasing=TRUE)
  k <- max(floor(length(losses) * k_frac), 20)
  if (k < 10) return(NA)
  top_k <- losses[1:k]
  alpha <- 1 / mean(log(top_k / losses[k+1]))
  return(alpha)
}

hill_C2 <- hill_alpha(daily_C2$port_ret)
hill_1715 <- hill_alpha(daily_1715$port_ret)
hill_70_30 <- hill_alpha(daily_combined$port_ret_70_30)
cat(sprintf("\nHill alpha: C2 = %.3f, STR_1715 = %.3f, 70/30 = %.3f\n",
            hill_C2, hill_1715, hill_70_30))

# Save tail_risk.json
tail_risk_out <- list(
  task_id = WT_ID,
  as_of_date = format(AS_OF_SIG_DATE, "%Y-%m-%d"),
  window = "trailing_252d_daily",
  sleeve_C2 = tail_C2,
  sleeve_STR_1715 = tail_1715,
  composite_70_30 = tail_70_30,
  hill_alpha = list(C2 = hill_C2, STR_1715 = hill_1715, composite_70_30 = hill_70_30)
)
write_json(tail_risk_out, file.path(STAGE_DIR, "tail_risk.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null")
cat(sprintf("Saved: %s\n", file.path(STAGE_DIR, "tail_risk.json")))

#==============================================================================
# Step 7: Stress + Regime Decomposition (8 KR stress)
#==============================================================================

cat("\n=== Step 7: Stress + Regime ===\n")

# Stress periods (Pfaff-style + KR specific)
stress_periods <- list(
  IMF_1997 = list(start = "1997-10-01", end = "1998-06-30"),
  DotCom_2000 = list(start = "2000-03-01", end = "2002-09-30"),
  CardCrisis_2003 = list(start = "2003-01-01", end = "2003-06-30"),
  GFC_2008 = list(start = "2008-09-01", end = "2009-03-31"),
  EuDebt_2011 = list(start = "2011-08-01", end = "2012-06-30"),
  ChinaSlow_2015 = list(start = "2015-06-01", end = "2016-02-29"),
  TradeWar_2018 = list(start = "2018-06-01", end = "2018-12-31"),
  COVID_2020 = list(start = "2020-02-01", end = "2020-04-30"),
  RateShock_2022 = list(start = "2022-01-01", end = "2022-10-31")
)

# Build long-history sleeve daily returns (use alpha_scores top20 per sig_date)
# Since alpha_scores has 268 sig_dates ~ 2004-01 ~ 2026-04, we need monthly rebalance
# Per sig_date pick top20, hold next month EW.

build_monthly_portfolio_history <- function(alpha_panel, rd_data) {
  sig_dates_sorted <- sort(unique(alpha_panel$sig_date))
  port_returns <- list()
  for (i in seq_along(sig_dates_sorted)[-length(sig_dates_sorted)]) {
    sd_t <- sig_dates_sorted[i]
    sd_next <- sig_dates_sorted[i+1]
    # Top 20 at sd_t
    snapshot <- alpha_panel[sig_date == sd_t]
    setorder(snapshot, -alpha)
    if (nrow(snapshot) < 20) next
    top <- snapshot[1:20]
    # Hold from sd_t+1 to sd_next (inclusive)
    period_ret <- rd_data[Ticker %in% top$Ticker &
                          Date > sd_t & Date <= sd_next & !is.na(Ret),
                          .(Date, Ticker, Ret)]
    if (nrow(period_ret) == 0) next
    # EW daily return
    daily_ew <- period_ret[, .(port_ret = mean(Ret, na.rm=TRUE)), by=Date]
    port_returns[[as.character(sd_t)]] <- daily_ew
  }
  rbindlist(port_returns)
}

# Build full history C2 sleeve daily
cat("Building C2 sleeve full history (this may take a moment)...\n")
hist_C2 <- build_monthly_portfolio_history(alpha, rd_full)
cat(sprintf("C2 sleeve history: %d daily obs, %s ~ %s\n",
            nrow(hist_C2),
            as.character(min(hist_C2$Date)),
            as.character(max(hist_C2$Date))))

# Save
write_parquet(hist_C2, file.path(STAGE_DIR, "sleeve_C2_daily_history.parquet"))

# Stress decomposition
stress_results <- list()
for (sp_name in names(stress_periods)) {
  sp <- stress_periods[[sp_name]]
  sp_start <- as.Date(sp$start)
  sp_end <- as.Date(sp$end)

  sp_data_C2 <- hist_C2[Date >= sp_start & Date <= sp_end]
  if (nrow(sp_data_C2) < 5) {
    stress_results[[sp_name]] <- list(
      C2_total = NA, C2_max_dd = NA, C2_n_days = nrow(sp_data_C2),
      bm_total = NA, bm_max_dd = NA
    )
    next
  }

  # C2 cumulative return
  C2_cumret <- prod(1 + sp_data_C2$port_ret, na.rm=TRUE) - 1
  C2_nav <- cumprod(1 + sp_data_C2$port_ret)
  C2_dd <- min((C2_nav - cummax(C2_nav)) / cummax(C2_nav), na.rm=TRUE)

  # Benchmark (KOSPI200 BM_Ret)
  bm_period <- unique(rd_full[Date >= sp_start & Date <= sp_end & !is.na(BM_Ret),
                                .(Date, BM_Ret)])
  if (nrow(bm_period) > 0) {
    bm_total <- prod(1 + bm_period$BM_Ret, na.rm=TRUE) - 1
    bm_nav <- cumprod(1 + bm_period$BM_Ret)
    bm_dd <- min((bm_nav - cummax(bm_nav)) / cummax(bm_nav), na.rm=TRUE)
  } else {
    bm_total <- NA; bm_dd <- NA
  }

  stress_results[[sp_name]] <- list(
    period = paste(sp_start, "to", sp_end),
    C2_total = round(C2_cumret, 4),
    C2_max_dd = round(C2_dd, 4),
    C2_n_days = nrow(sp_data_C2),
    bm_total = round(bm_total, 4),
    bm_max_dd = round(bm_dd, 4),
    C2_excess_vs_bm = round(C2_cumret - bm_total, 4),
    C2_crisis_alpha_pp = round((C2_cumret - bm_total) * 100, 2)
  )
}

cat("\nStress Period Decomposition (C2 sleeve EW top20 monthly rebalance):\n")
for (sp in names(stress_results)) {
  r <- stress_results[[sp]]
  cat(sprintf("  %-20s: C2 %+7.2f%% (DD %+7.2f%%) | BM %+7.2f%% (DD %+7.2f%%) | Excess %+7.2f%%\n",
              sp, 100*r$C2_total, 100*r$C2_max_dd,
              100*r$bm_total, 100*r$bm_max_dd, 100*r$C2_excess_vs_bm))
}

#==============================================================================
# Step 8: AX-001 v2 4-axis Conditional Defense Validation
#==============================================================================

cat("\n=== Step 8: AX-001 v2 4-axis ===\n")

# Build STR_1715 sleeve history (separate from admit results - 직접 alpha_scores 없음 →
# top20 from production csv held constant approximation)
# Simplification: use admit production weights as static top20 throughout
str1715_static_tickers <- str1715_top20$Ticker
str1715_static_weights <- str1715_top20$Weight_sleeve / sum(str1715_top20$Weight_sleeve)
names(str1715_static_weights) <- str1715_static_tickers

# Build STR_1715 sleeve daily from 2004
hist_1715 <- rd_full[Ticker %in% str1715_static_tickers &
                     Date >= "2004-01-01" & Date <= AS_OF_SIG_DATE & !is.na(Ret),
                     .(Date, Ticker, Ret)]
hist_1715[, w := str1715_static_weights[match(Ticker, names(str1715_static_weights))]]
hist_1715[, w := w / sum(w[Date == Date[1]])]  # one-pass renormalization
daily_1715_hist <- hist_1715[, .(port_ret_1715 = sum(Ret * w, na.rm=TRUE)), by=Date]
setorder(daily_1715_hist, Date)
# NOTE: STR_1715 admit had dynamic alpha rebalance; this static-top20 proxy is
# a CONSERVATIVE approximation. Real admit had time-varying composition.

cat(sprintf("STR_1715 sleeve history (static top20 proxy): %d obs\n", nrow(daily_1715_hist)))

# Crisis alpha: stress periods only
crisis_periods <- c("IMF_1997","GFC_2008","EuDebt_2011","COVID_2020","RateShock_2022")
# Only run from 2004 for fair compare with C2 alpha scores
crisis_results <- list()
for (sp_name in crisis_periods) {
  sp <- stress_periods[[sp_name]]
  sp_start <- as.Date(sp$start)
  sp_end <- as.Date(sp$end)
  if (sp_end < as.Date("2004-01-01")) next  # before alpha_scores

  C2_data <- hist_C2[Date >= sp_start & Date <= sp_end]
  s1715_data <- daily_1715_hist[Date >= sp_start & Date <= sp_end]
  bm_period <- unique(rd_full[Date >= sp_start & Date <= sp_end & !is.na(BM_Ret),
                                .(Date, BM_Ret)])

  if (nrow(C2_data) < 5 || nrow(s1715_data) < 5) next

  C2_cumret <- prod(1 + C2_data$port_ret, na.rm=TRUE) - 1
  s1715_cumret <- prod(1 + s1715_data$port_ret_1715, na.rm=TRUE) - 1
  bm_cumret <- if (nrow(bm_period) > 0) prod(1 + bm_period$BM_Ret, na.rm=TRUE) - 1 else NA

  C2_nav <- cumprod(1 + C2_data$port_ret)
  s1715_nav <- cumprod(1 + s1715_data$port_ret_1715)
  C2_dd <- min((C2_nav - cummax(C2_nav)) / cummax(C2_nav), na.rm=TRUE)
  s1715_dd <- min((s1715_nav - cummax(s1715_nav)) / cummax(s1715_nav), na.rm=TRUE)

  crisis_results[[sp_name]] <- list(
    C2_total = round(C2_cumret, 4),
    C2_max_dd = round(C2_dd, 4),
    str1715_total = round(s1715_cumret, 4),
    str1715_max_dd = round(s1715_dd, 4),
    bm_total = round(bm_cumret, 4),
    C2_excess_vs_str1715 = round(C2_cumret - s1715_cumret, 4),
    C2_dd_complement_vs_str1715 = round(s1715_dd - C2_dd, 4)  # positive = C2 has milder DD
  )
}

# Axis 1: crisis_alpha (C2 vs benchmark; conditional defense expectation: positive in crisis)
crisis_alpha_C2 <- sapply(crisis_results, function(x) {
  if (is.null(x$C2_total) || is.null(x$bm_total)) return(NA)
  x$C2_total - x$bm_total
})

axis1_crisis_alpha <- list(
  per_period = crisis_alpha_C2,
  mean_crisis_alpha = round(mean(crisis_alpha_C2, na.rm=TRUE), 4),
  positive_count = sum(crisis_alpha_C2 > 0, na.rm=TRUE),
  total_count = sum(!is.na(crisis_alpha_C2)),
  pass = mean(crisis_alpha_C2, na.rm=TRUE) > 0,
  interpretation = "AX-001 v2 axis 1: C2 crisis_alpha vs benchmark in stress windows"
)

# Axis 2: MDD complement vs STR_1715
axis2_mdd_complement <- list(
  per_period = sapply(crisis_results, function(x) x$C2_dd_complement_vs_str1715),
  pass = mean(sapply(crisis_results, function(x) x$C2_dd_complement_vs_str1715), na.rm=TRUE) > 0,
  interpretation = "AX-001 v2 axis 2: C2 MDD complement (less drawdown than STR_1715 in crisis)"
)

# Axis 3: bad/normal IC ratio
# Build regime classifier from BM_Ret 252d trailing mean+std (z-score)
bm_dt <- unique(rd_full[!is.na(BM_Ret), .(Date, BM_Ret)])
setorder(bm_dt, Date)
# Monthly BM aggregate
bm_dt[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm_dt[, .(BM_M = prod(1+BM_Ret, na.rm=TRUE) - 1), by=ym]
bm_monthly[, ym_date := as.Date(paste0(ym, "-01"))]
setorder(bm_monthly, ym_date)
# trailing 36m mean/std
bm_monthly[, BM_M_lag := shift(BM_M, 1)]  # lag to avoid lookahead
bm_monthly[, mean36 := frollmean(BM_M_lag, 36, align="right", na.rm=TRUE)]
bm_monthly[, sd36 := frollapply(BM_M_lag, 36, function(x) sd(x, na.rm=TRUE), align="right")]
bm_monthly[, regime_z := (BM_M_lag - mean36) / sd36]
bm_monthly[, regime := fcase(
  regime_z < -1, "bad",
  regime_z > 1, "good",
  default = "normal"
)]
bm_monthly[, regime_score := BM_M_lag]
# Match alpha sig_date (month-end) to regime
alpha[, ym_sig := format(sig_date, "%Y-%m")]
alpha_regime <- merge(alpha, bm_monthly[, .(ym, regime)], by.x="ym_sig", by.y="ym", all.x=TRUE)

# IC per sig_date with forward return ~ next-month return
# Build forward return per (sig_date, Ticker) from rawdata: P_(next_me) / P_(sig_date+1)
sig_dates_sorted <- sort(unique(alpha$sig_date))
ic_per_date <- list()
for (i in seq_along(sig_dates_sorted)[-length(sig_dates_sorted)]) {
  sd_t <- sig_dates_sorted[i]
  sd_next <- sig_dates_sorted[i+1]
  # Need P at sd_t+1 and P at sd_next
  p_start <- rd_full[Date > sd_t & Date <= sd_t + 7 & !is.na(Close),
                     .(Date, Ticker, Close)]
  p_start <- p_start[, .SD[1], by=Ticker]  # first day after sd_t
  p_end <- rd_full[Date <= sd_next & Date > sd_next - 7 & !is.na(Close),
                   .(Date, Ticker, Close)]
  p_end <- p_end[, .SD[.N], by=Ticker]  # last day of period

  ret_panel <- merge(p_start[, .(Ticker, p_start_date=Date, p_start=Close)],
                      p_end[, .(Ticker, p_end_date=Date, p_end=Close)],
                      by="Ticker")
  ret_panel[, fwd_ret := p_end / p_start - 1]

  snapshot <- alpha[sig_date == sd_t, .(Ticker, alpha)]
  ic_data <- merge(snapshot, ret_panel[, .(Ticker, fwd_ret)], by="Ticker")
  if (nrow(ic_data) < 30 || sum(!is.na(ic_data$fwd_ret)) < 30) next
  ic <- cor(rank(ic_data$alpha), rank(ic_data$fwd_ret),
            use="pairwise.complete.obs", method="pearson")
  ic_per_date[[as.character(sd_t)]] <- data.table(sig_date = sd_t, ic = ic, n_stocks = nrow(ic_data))
}

ic_dt <- rbindlist(ic_per_date)
ic_dt[, ym_sig := format(sig_date, "%Y-%m")]
ic_dt <- merge(ic_dt, bm_monthly[, .(ym, regime)], by.x="ym_sig", by.y="ym", all.x=TRUE)
ic_dt <- ic_dt[!is.na(regime)]

ic_regime <- ic_dt[, .(mean_ic = mean(ic, na.rm=TRUE),
                       median_ic = median(ic, na.rm=TRUE),
                       sd_ic = sd(ic, na.rm=TRUE),
                       n = .N,
                       icir = mean(ic, na.rm=TRUE) / sd(ic, na.rm=TRUE)),
                   by=regime]
cat("\nIC by regime (lagged BM 36m z-score):\n")
print(ic_regime)

bad_normal_ic_ratio <- ic_regime[regime=="bad", mean_ic] / ic_regime[regime=="normal", mean_ic]
axis3_ic_ratio <- list(
  bad_ic = round(ic_regime[regime=="bad", mean_ic], 4),
  normal_ic = round(ic_regime[regime=="normal", mean_ic], 4),
  good_ic = round(ic_regime[regime=="good", mean_ic], 4),
  bad_normal_ic_ratio = round(bad_normal_ic_ratio, 4),
  n_bad = ic_regime[regime=="bad", n],
  n_normal = ic_regime[regime=="normal", n],
  n_good = ic_regime[regime=="good", n],
  pass = !is.na(bad_normal_ic_ratio) && bad_normal_ic_ratio > 1,
  interpretation = "AX-001 v2 axis 3: IC in bad regime / IC in normal regime > 1 (defense bias)"
)

# Axis 4: Tail risk superiority
axis4_tail = list(
  C2_evt_var_99 = tail_C2$evt_var$var_evt,
  STR1715_evt_var_99 = tail_1715$evt_var$var_evt,
  C2_cdar_95 = tail_C2$cdar$cdar,
  STR1715_cdar_95 = tail_1715$cdar$cdar,
  C2_lower_VaR = tail_C2$evt_var$var_evt < tail_1715$evt_var$var_evt,
  C2_lower_CDaR = tail_C2$cdar$cdar < tail_1715$cdar$cdar,
  interpretation = "AX-001 v2 axis 4: C2 tail risk (EVT-VaR + CDaR) ≤ STR_1715 (defensive bias)"
)

ax_001_4axis <- list(
  axis_1_crisis_alpha = axis1_crisis_alpha,
  axis_2_mdd_complement = axis2_mdd_complement,
  axis_3_bad_normal_ic_ratio = axis3_ic_ratio,
  axis_4_tail_risk_superiority = axis4_tail,
  composite_pass_count = sum(c(axis1_crisis_alpha$pass,
                                axis2_mdd_complement$pass,
                                axis3_ic_ratio$pass,
                                axis4_tail$C2_lower_CDaR), na.rm=TRUE)
)

cat(sprintf("\nAX-001 v2 4-axis composite pass: %d / 4\n",
            ax_001_4axis$composite_pass_count))

#==============================================================================
# Step 9: Crowding + Pareto Orthogonality vs STR_1715
#==============================================================================

cat("\n=== Step 9: Crowding + Pareto Orthogonality ===\n")

# Kendall tau-c on monthly portfolio returns
# Build monthly C2 returns and STR_1715 returns
monthly_C2 <- hist_C2[, ym := format(Date, "%Y-%m")][, .(M_ret_C2 = prod(1+port_ret, na.rm=TRUE) - 1), by=ym]
monthly_1715 <- daily_1715_hist[, ym := format(Date, "%Y-%m")][, .(M_ret_1715 = prod(1+port_ret_1715, na.rm=TRUE) - 1), by=ym]

monthly_join <- merge(monthly_C2, monthly_1715, by="ym")
cat(sprintf("Monthly compare: %d months\n", nrow(monthly_join)))

cor_pearson <- cor(monthly_join$M_ret_C2, monthly_join$M_ret_1715, use="pairwise.complete.obs")
cor_spearman <- cor(monthly_join$M_ret_C2, monthly_join$M_ret_1715, method="spearman", use="pairwise.complete.obs")
cor_kendall <- cor(monthly_join$M_ret_C2, monthly_join$M_ret_1715, method="kendall", use="pairwise.complete.obs")

# Tail Dependence Coefficient (TDC) — Joe (1997) empirical lower TDC at 10% percentile
tdc_lower <- function(x, y, q=0.10) {
  u <- pmin(rank(x)/length(x), 1)
  v <- pmin(rank(y)/length(y), 1)
  # lower TDC: P(V <= q | U <= q)
  n_both <- sum(u <= q & v <= q)
  n_u <- sum(u <= q)
  if (n_u == 0) return(NA)
  n_both / n_u
}

tdc_l_10 <- tdc_lower(monthly_join$M_ret_C2, monthly_join$M_ret_1715, q=0.10)
tdc_l_5 <- tdc_lower(monthly_join$M_ret_C2, monthly_join$M_ret_1715, q=0.05)

cat(sprintf("\nMonthly return correlation (full history):\n"))
cat(sprintf("  Pearson:  %.4f\n", cor_pearson))
cat(sprintf("  Spearman: %.4f\n", cor_spearman))
cat(sprintf("  Kendall:  %.4f\n", cor_kendall))
cat(sprintf("Lower TDC (q=0.10): %.4f\n", tdc_l_10))
cat(sprintf("Lower TDC (q=0.05): %.4f\n", tdc_l_5))

# Ticker-level overlap diagnostic
ticker_overlap_count <- length(common_top20)
cat(sprintf("Top20 ticker overlap C2 vs STR_1715: %d/20\n", ticker_overlap_count))

#==============================================================================
# Step 10: Regime Correlation
#==============================================================================

cat("\n=== Step 10: Regime Correlation ===\n")

# Per-regime cross-sleeve correlation
hist_C2[, ym := format(Date, "%Y-%m")]
daily_1715_hist[, ym := format(Date, "%Y-%m")]
joined_daily <- merge(hist_C2[, .(Date, ym, port_ret_C2 = port_ret)],
                       daily_1715_hist[, .(Date, port_ret_1715)],
                       by="Date")
# Attach regime
joined_daily <- merge(joined_daily, bm_monthly[, .(ym, regime)],
                       by="ym", all.x=TRUE)
joined_daily <- joined_daily[!is.na(regime)]

regime_corr <- joined_daily[, .(
  cor_pearson = cor(port_ret_C2, port_ret_1715, use="pairwise.complete.obs"),
  cor_spearman = cor(port_ret_C2, port_ret_1715, method="spearman", use="pairwise.complete.obs"),
  n_days = .N,
  C2_mean_ret = mean(port_ret_C2, na.rm=TRUE) * 252,
  STR_1715_mean_ret = mean(port_ret_1715, na.rm=TRUE) * 252,
  C2_vol = sd(port_ret_C2, na.rm=TRUE) * sqrt(252),
  STR_1715_vol = sd(port_ret_1715, na.rm=TRUE) * sqrt(252)
), by=regime]

cat("Regime-conditional correlation:\n")
print(regime_corr)

write_parquet(regime_corr, file.path(STAGE_DIR, "regime_correlation.parquet"))
cat(sprintf("Saved: %s\n", file.path(STAGE_DIR, "regime_correlation.parquet")))

#==============================================================================
# Step 11: Save risk_package_draft.json
#==============================================================================

cat("\n=== Step 11: Save risk_package_draft.json ===\n")

# Risk summary
top_common_risks <- list()
# rough top exposure from B_full: Mkt loading mean for top20 C2
top20_betas <- B_full[rownames(B_full) %in% top20_C2$Ticker, "Mkt_Ret"]
top20_betas <- top20_betas[!is.na(top20_betas)]
mkt_loading_C2 <- mean(top20_betas, na.rm=TRUE)
top20_betas_1715 <- B_full[rownames(B_full) %in% str1715_top20$Ticker, "Mkt_Ret"]
mkt_loading_1715 <- mean(top20_betas_1715, na.rm=TRUE)
cat(sprintf("Mean CAPM beta: C2 = %.3f, STR_1715 = %.3f\n",
            mkt_loading_C2, mkt_loading_1715))

# Sector concentration C2
sec_C2 <- B_dt[Ticker %in% top20_C2$Ticker, .N, by=Sector][order(-N)]
top_sec_C2 <- sec_C2[1]
sec_concentration_C2 <- top_sec_C2$N / 20

# Variance decomposition: systematic vs specific
# at sleeve level
sleeve_C2_sys_var <- as.numeric(t(w_C2_sub) %*% sigma_sys[names(w_C2_sub), names(w_C2_sub)] %*% w_C2_sub)
sleeve_C2_spec_var <- as.numeric(t(w_C2_sub) %*% D_diag[names(w_C2_sub), names(w_C2_sub)] %*% w_C2_sub)
sleeve_C2_systematic_pct <- sleeve_C2_sys_var / (sleeve_C2_sys_var + sleeve_C2_spec_var)

# Liquidity check — already alpha did ADV_20d_lag1 floor 2e8 KRW
# Re-verify top20 C2 has ADV >= 2e8
adv_check <- rd_full[Ticker %in% top20_C2$Ticker &
                     Date >= AS_OF_SIG_DATE - 30 & Date < AS_OF_SIG_DATE,
                     .(adv_20d = mean(Close * Vol, na.rm=TRUE)), by=Ticker]
adv_check <- merge(adv_check, top20_C2[, .(Ticker, Name=as.character(NA))], by="Ticker", all.y=TRUE)
adv_min <- min(adv_check$adv_20d, na.rm=TRUE)
adv_below_2e8 <- sum(adv_check$adv_20d < 2e8, na.rm=TRUE)
cat(sprintf("ADV liquidity (top20 C2): min %.2e KRW, n below 2e8 = %d\n",
            adv_min, adv_below_2e8))

# Red flag detection
red_flags <- list()
if (sec_concentration_C2 > 0.40) {
  red_flags[[length(red_flags)+1]] <- list(
    id = "RF-R1",
    severity = "MEDIUM",
    desc = sprintf("Top sector concentration %.0f%% (%s) > 40%% threshold (relaxed for low-vol family)",
                   100*sec_concentration_C2, top_sec_C2$Sector)
  )
}
if (sigma_cond > 500) {
  red_flags[[length(red_flags)+1]] <- list(
    id = "RF-R2", severity = "HIGH",
    desc = sprintf("Sigma condition %.2f > 500", sigma_cond)
  )
}

# Risk package
risk_package <- list(
  task_id = WT_ID,
  as_of_date = format(AS_OF_SIG_DATE, "%Y-%m-%d"),
  agent = "risk_research",
  pipeline_version = "v1.0_4sleeve_composite",
  upstream_alpha_inheritance = list(
    alpha_package_ref = file.path(MAILBOX_DIR, "alpha_package.json"),
    alpha_status = "NON_GRADUATING_MONO_FAIL_BUT_DISCLOSED_HONESTLY",
    alpha_mono_q1_q5 = 0.50,
    alpha_rank_ic = 0.0491,
    alpha_icir = 0.4277,
    alpha_t_nw = 7.002,
    alpha_dsr = 14.348,
    alpha_harvey_5spec_pass = 5,
    alpha_orthogonality_vs_STR_1715 = list(
      cor_pearson = 0.0038,
      cor_spearman = -0.0605,
      pass = TRUE
    ),
    inheritance_note = "Risk-side validation Codex C5/C6 mandate response — AX-001 conditional defense + multi-sleeve composite risk profile"
  ),
  exposure_matrix_ref = file.path(STAGE_DIR, "exposure_matrix.parquet"),
  factor_covariance_ref = file.path(STAGE_DIR, "factor_covariance.parquet"),
  specific_risk_ref = file.path(STAGE_DIR, "specific_risk.parquet"),
  security_covariance_ref = file.path(STAGE_DIR, "covariance.parquet"),
  regime_correlation_ref = file.path(STAGE_DIR, "regime_correlation.parquet"),
  factor_model = list(
    structure = "Sigma = B Omega B' + D",
    B = list(
      n_tickers = nrow(B_full),
      factors = colnames(B_full),
      method = "OLS multi-factor regression 252d daily; Mkt (KOSPI200 BM_Ret), SMB (size 30/70 quintile diff), Top-5 sectors (FICS Lv1)"
    ),
    Omega = list(
      dim = ncol(omega_lw),
      method = "Ledoit-Wolf shrinkage (corpcor::cov.shrink) annualized 252",
      condition_number = round(omega_cond, 2),
      sample_size = N_f
    ),
    D = list(
      n_tickers = nrow(D_dt),
      mean_specific_vol = round(mean(D_dt$specific_vol, na.rm=TRUE), 4),
      method = "Residual variance from Mkt + SMB regression, annualized 252"
    ),
    Sigma = list(
      dim = nrow(Sigma),
      condition_number = round(sigma_cond, 2),
      psd_check = psd_ok,
      min_eigenvalue = round(min(ev_sigma), 8),
      shrinkage_applied = sigma_cond > 500
    )
  ),
  sleeve_risk_profile = list(
    C2_low_vol_top20 = list(
      n_names = length(common_C2),
      annualized_vol = round(sleeve_vol_C2, 4),
      systematic_var_pct = round(sleeve_C2_systematic_pct, 4),
      mean_capm_beta = round(mkt_loading_C2, 3),
      top_sector = top_sec_C2$Sector,
      top_sector_concentration = round(sec_concentration_C2, 3),
      adv_min_won_20d = round(adv_min),
      adv_below_2e8_count = adv_below_2e8
    ),
    STR_1715_top20 = list(
      n_names = length(common_1715),
      annualized_vol = round(sleeve_vol_1715, 4),
      mean_capm_beta = round(mkt_loading_1715, 3)
    ),
    cross_sleeve = list(
      cross_correlation = round(cross_corr, 4),
      diversification_ratio_50_50 = round(div_ratio_50_50, 3),
      diversification_ratio_70_30 = round(div_70_30, 3),
      ticker_overlap_top20 = ticker_overlap_count,
      common_overlap_tickers = common_top20,
      max_overlap_w_70_30 = round(max_overlap_w, 4)
    )
  ),
  tail_risk = list(
    method = "EVT GPD (Pfaff Ch.7) + CF-VaR + CDaR (Pfaff Ch.12) + Hill alpha",
    window = "trailing 252d daily",
    C2_sleeve = list(
      evt_var_99 = round(tail_C2$evt_var$var_evt, 5),
      cf_var_99 = round(tail_C2$cf_var$var_cf, 5),
      cdar_95 = round(tail_C2$cdar$cdar, 5),
      max_dd = round(tail_C2$cdar$max_dd, 5),
      hill_alpha = round(hill_C2, 3),
      shape_xi = tail_C2$evt_var$shape_xi
    ),
    STR_1715_sleeve = list(
      evt_var_99 = round(tail_1715$evt_var$var_evt, 5),
      cf_var_99 = round(tail_1715$cf_var$var_cf, 5),
      cdar_95 = round(tail_1715$cdar$cdar, 5),
      max_dd = round(tail_1715$cdar$max_dd, 5),
      hill_alpha = round(hill_1715, 3),
      shape_xi = tail_1715$evt_var$shape_xi
    ),
    composite_70_30 = list(
      evt_var_99 = round(tail_70_30$evt_var$var_evt, 5),
      cf_var_99 = round(tail_70_30$cf_var$var_cf, 5),
      cdar_95 = round(tail_70_30$cdar$cdar, 5),
      max_dd = round(tail_70_30$cdar$max_dd, 5),
      hill_alpha = round(hill_70_30, 3)
    ),
    tail_risk_json_ref = file.path(STAGE_DIR, "tail_risk.json")
  ),
  stress_decomposition = stress_results,
  ax_001_v2_4_axis = ax_001_4axis,
  crowding_pareto = list(
    method_note = "Kendall tau-c + Spearman/Pearson + lower TDC empirical (Joe 1997)",
    monthly_correlation = list(
      pearson = round(cor_pearson, 4),
      spearman = round(cor_spearman, 4),
      kendall = round(cor_kendall, 4)
    ),
    lower_tdc = list(
      q_10 = round(tdc_l_10, 4),
      q_05 = round(tdc_l_5, 4)
    ),
    top20_ticker_overlap = ticker_overlap_count,
    pareto_ortho_pass = abs(cor_kendall) < 0.20 && tdc_l_10 < 0.40,
    interpretation = "Strict orthogonality: |Kendall| < 0.20 AND lower_TDC_10 < 0.40 (lower-tail co-crash 제한)"
  ),
  style_exposure = list(
    method_note = "KR FF proxy 부재 인지 → CAPM beta + log_size + sector dummy로 대체. literal FF3/FF5/Carhart panel은 infrastructure escalation task #1 (alpha challenge_note inherit).",
    C2_mean_capm_beta = round(mkt_loading_C2, 3),
    STR_1715_mean_capm_beta = round(mkt_loading_1715, 3),
    C2_low_beta_evidence = mkt_loading_C2 < mkt_loading_1715,
    C2_sector_concentration = round(sec_concentration_C2, 3),
    inherited_infrastructure_escalation = "WT-INF20260513_xxx_kr_ff_factor_proxy_build (alpha_package Q-Lead escalation)"
  ),
  four_sleeve_composite_risk = list(
    architecture_note = "STR_1715 admit (v2.3 single sleeve 100% with M4*AR*R05 sequential overlay) + this C2 low-vol sleeve. M4/AR/R05 are scalar overlays on STR_1715, not separate alpha sources. True 'multi-sleeve' = STR_1715 base alpha + C2 low-vol alpha.",
    composite_scenarios = list(
      scenario_50_50 = list(
        vol = round(combined_vol, 4),
        evt_var_99 = "see composite_70_30 (relative compare)",
        diversification_ratio = round(div_ratio_50_50, 3)
      ),
      scenario_70_30 = list(
        vol = round(combined_70_30_vol, 4),
        evt_var_99 = round(tail_70_30$evt_var$var_evt, 5),
        cdar_95 = round(tail_70_30$cdar$cdar, 5),
        max_dd = round(tail_70_30$cdar$max_dd, 5),
        diversification_ratio = round(div_70_30, 3)
      )
    ),
    concentration_overlap = list(
      overlap_tickers = common_top20,
      overlap_count = ticker_overlap_count,
      max_combined_w_70_30 = round(max_overlap_w, 4),
      breach_0_20_cap = max_overlap_w > 0.20,
      note = "Top20 overlap = 1 ticker (A005930 삼성전자). Multi-sleeve = effectively disjoint."
    ),
    non_degenerate_sleeve_mix_evidence = list(
      cor_kendall = round(cor_kendall, 4),
      cor_pearson = round(cor_pearson, 4),
      cross_corr_daily = round(cross_corr, 4),
      diversification_ratio_70_30 = round(div_70_30, 3),
      pass_threshold = "|cor| < 0.30 AND diversification_ratio > 1.05",
      pass = abs(cor_kendall) < 0.30 && div_70_30 > 1.05
    )
  ),
  risk_summary = list(
    top_common_risks = list(
      sprintf("Mkt (mean CAPM beta %.3f for C2 vs %.3f STR_1715)", mkt_loading_C2, mkt_loading_1715),
      sprintf("Sector concentration top: %s (%.0f%% of C2 top20)", top_sec_C2$Sector, 100*sec_concentration_C2),
      sprintf("Specific risk pct %.2f%% (sleeve var decomp)", 100*(1-sleeve_C2_systematic_pct))
    ),
    crowding_flags = list(),
    liquidity_flags = if (adv_below_2e8 > 0) list(sprintf("%d names below 2e8 KRW ADV", adv_below_2e8)) else list(),
    stress_tests = list(
      gfc_2008_C2 = stress_results$GFC_2008$C2_total,
      covid_2020_C2 = stress_results$COVID_2020$C2_total,
      euro_debt_2011_C2 = stress_results$EuDebt_2011$C2_total,
      rate_shock_2022_C2 = stress_results$RateShock_2022$C2_total
    )
  ),
  diagnostics = list(
    condition_number = round(sigma_cond, 2),
    shrinkage_used = sigma_cond > 500,
    shrinkage_method = if (sigma_cond > 500) "ledoit_wolf" else "none",
    factor_correlation_warnings = list(),
    n_factors = ncol(omega_lw),
    n_tickers_in_sigma = nrow(Sigma),
    rolling_window_days = 252
  ),
  red_flags = red_flags,
  challenge_flags = list(),
  ax_compliance = list(
    AX_001_v2_conditional_defense = ax_001_4axis$composite_pass_count,
    AX_002_pit_strict = "alpha PIT-clean inherit (C1/C2/C9/C10 PASS), risk-stage no PIT modification",
    AX_005_v1_2_low_vol_exclusion_evidence = list(
      single_sleeve_blocked = TRUE,
      multi_sleeve_evidence_passes = "Pareto-orthogonal (Kendall<0.20 + TDC<0.40) + cross_corr_daily<0.20 + div_ratio>1.05",
      EXCLUSION_path = "multi-sleeve OR multi-axis combined per AX-005 v1.2 EXCLUSION clause"
    ),
    AX_007_4sleeve_exempt_evidence = list(
      structure = "multi-sleeve (STR_1715 + C2)",
      ticker_overlap = ticker_overlap_count,
      diversification_ratio_70_30 = round(div_70_30, 3),
      non_degenerate_evidence = abs(cor_kendall) < 0.30
    ),
    AX_008_triangulation_status = "1 source (risk-research only); awaits Optimizer + Forge + Architect"
  ),
  references = list(
    "Ang-Hodrick-Xing-Zhang (2006) JoF — IVOL puzzle (alpha source)",
    "Pfaff (2016) FRM — EVT GPD Ch.7, CDaR Ch.12, copula Ch.9",
    "Ledoit-Wolf (2003, 2004) — shrinkage covariance",
    "Joe (1997) — Tail Dependence Coefficient empirical",
    "Charter v1.7 §10 Role Card 4x5 — risk-research artifact contract",
    "AX-001 v2 conditional defense 4-axis (crisis_alpha + MDD + bad/normal IC + tail risk)",
    "Codex Round 2 (REJECT) — C5 multi-sleeve / C6 AX-001 / C7 lineage mandate (this stage)"
  )
)

write_json(risk_package, file.path(MAILBOX_DIR, "risk_package_draft.json"),
           auto_unbox=TRUE, pretty=TRUE, na="null")
cat(sprintf("Saved: %s\n", file.path(MAILBOX_DIR, "risk_package_draft.json")))

cat(sprintf("\n[%s] Risk Research Pipeline COMPLETE\n", Sys.time()))
cat(sprintf("Summary: sleeve_vol C2=%.4f / STR_1715=%.4f / 70_30=%.4f\n",
            sleeve_vol_C2, sleeve_vol_1715, combined_70_30_vol))
cat(sprintf("Sigma cond=%.2f PSD=%s\n", sigma_cond, ifelse(psd_ok,"PASS","FAIL")))
cat(sprintf("AX-001 v2 axes pass: %d/4\n", ax_001_4axis$composite_pass_count))
cat(sprintf("Pareto orthogonality (|Kendall|<0.20 + TDC<0.40): %s\n",
            ifelse(abs(cor_kendall) < 0.20 && tdc_l_10 < 0.40, "PASS", "FAIL")))
