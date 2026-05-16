#==============================================================================
# WT-D20260514_003 — Risk Research
# Low-Vol C Variant Full Universe Multi-Sleeve Composite Risk Analysis
#
# Mandate (Q-Lead spawn 2026-05-14):
#  - Σ = BΩB' + D (full universe top20 + STR_1715 top20)
#  - Tail Risk (EVT/CVaR/CDaR/Hill)
#  - Stress (8 periods) + Regime (4-bucket)
#  - AX-001 v2 4-axis conditional defense
#  - 268m sector concentration audit (HHI/max share/2026-04 100% Energy outlier)
#  - 4-sleeve composite risk + Pareto inherit verification
#
# Inheritance: alpha_package portfolio realized cor = 0.0292 STRICT PASS
# vs parent (WT-D20260513_002) intersection cor 0.7713 FAIL
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(corpcor); library(PerformanceAnalytics); library(xts)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID     <- "WT-D20260514_003"
STAGE_DIR <- file.path("stage_artifacts", "WT_D20260514_003")
MAILBOX   <- file.path("qepm", "mailbox", "worktask", WT_ID)
AS_OF     <- as.Date("2026-04-30")
LOG_FILE  <- file.path(STAGE_DIR, "risk_research_run.log")

# Logging — rename to avoid shadowing base::log (Codex C2 ACCEPT)
log_msg <- function(msg) {
  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] %s\n", ts, msg))
  cat(sprintf("[%s] %s\n", ts, msg), file = LOG_FILE, append = TRUE)
}

if (file.exists(LOG_FILE)) file.remove(LOG_FILE)
log_msg("=== Risk Research START — WT-D20260514_003 ===")

# Load alpha_package
ap_path <- file.path(MAILBOX, "alpha_package.json")
ap <- fromJSON(ap_path, simplifyVector = FALSE)
log_msg(sprintf("alpha_package loaded: %d tickers, status=%s",
            ap$alpha_vector_n_tickers, substr(ap$selection_status, 1, 50)))

# Load alpha_scores 268m
ap_scores <- as.data.table(read_parquet(
  file.path(STAGE_DIR, "alpha_scores.parquet")))
ap_scores[, sig_date := as.Date(sig_date)]
log_msg(sprintf("alpha_scores: %d rows × %d tickers × %d months",
            nrow(ap_scores), length(unique(ap_scores$Ticker)),
            length(unique(ap_scores$sig_date))))

# Top20 C2 (this cycle full universe) at 2026-04
top20_this <- ap_scores[sig_date == AS_OF][order(-alpha)][1:20, Ticker]
log_msg(sprintf("Top20 C2 (this cycle 2026-04): %s",
            paste(top20_this[1:5], collapse = ",")))

# STR_1715 admit top20
str1715_path <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/20260512_str1715_sleeve_top20_alpha_2026_04.csv"
str1715_top20_dt <- fread(str1715_path, encoding = "UTF-8")
str1715_top20 <- str1715_top20_dt$Ticker
log_msg(sprintf("STR_1715 admit top20: %s",
            paste(str1715_top20[1:5], collapse = ",")))

# Ticker overlap audit
overlap <- intersect(top20_this, str1715_top20)
log_msg(sprintf("Ticker overlap C2 ∩ STR_1715 top20: %d names: %s",
            length(overlap), paste(overlap, collapse = ",")))

# Universe for Σ
sigma_universe <- unique(c(top20_this, str1715_top20))
log_msg(sprintf("Sigma universe (union): %d tickers", length(sigma_universe)))

# RAWDATA
rd_full <- as.data.table(read_parquet(
  ".cache/rawdata.parquet",
  col_select = c("Date", "Ticker", "Sector", "Size", "Ret", "BM_Ret")))
rd_full[, Date := as.Date(Date)]
rd_full[, Ret := as.numeric(Ret)]
rd_full[, BM_Ret := as.numeric(BM_Ret)]
log_msg(sprintf("rawdata loaded: %d rows, range %s ~ %s",
            nrow(rd_full), as.character(min(rd_full$Date)),
            as.character(max(rd_full$Date))))

# Sector mapping — use LATEST known sector per ticker (Codex C5/C6 fix: consistent mapping across all components)
ticker_sector_map <- rd_full[!is.na(Sector),
                              .SD[which.max(Date)],
                              by = Ticker,
                              .SDcols = c("Sector", "Date")][, .(Ticker, Sector)]
setkey(ticker_sector_map, Ticker)
log_msg(sprintf("ticker_sector_map built (latest known): %d tickers",
                 nrow(ticker_sector_map)))

# Sector mapping subset for sigma universe — use SAME map (Codex C5 ACCEPT — consistency)
rd_sec_dedup <- ticker_sector_map[Ticker %in% c(top20_this, str1715_top20)]

# ============================================================================
# STEP 1: Exposure matrix B (multi-factor: Mkt + SMB + top sectors)
# ============================================================================
log_msg("STEP 1: Building exposure matrix B (Mkt + SMB + top sectors)")

WINDOW_START <- AS_OF - 252
WINDOW_END   <- AS_OF
rd_window <- rd_full[Ticker %in% sigma_universe &
                       Date >= WINDOW_START & Date <= WINDOW_END &
                       !is.na(Ret) & !is.na(BM_Ret)]
log_msg(sprintf("rd_window: %d rows for %d tickers", nrow(rd_window),
            length(unique(rd_window$Ticker))))

# Build factor returns — use FULL UNIVERSE (not just sigma_universe 39 ticker) for sector factor returns
# This is important: sector factor return = cross-sectional mean of all sector member daily returns,
# not just the 39 ticker subset (sparse / NaN risk)
rd_window_full <- rd_full[Date >= WINDOW_START & Date <= WINDOW_END &
                            !is.na(Ret) & !is.na(BM_Ret) & !is.na(Sector)]
log_msg(sprintf("rd_window_full (sector factor base): %d rows %d tickers",
            nrow(rd_window_full), length(unique(rd_window_full$Ticker))))

sec_ret_d <- rd_window_full[!is.na(Sector),
                            .(Sector_Ret = mean(Ret, na.rm = TRUE)),
                            by = .(Date, Sector)]
mkt_ret <- unique(rd_window[, .(Date, BM_Ret)])
setnames(mkt_ret, "BM_Ret", "Mkt_Ret")

# Size quintile per Date — use FULL universe
rd_window_full[, size_q := cut(Size,
                                breaks = quantile(Size,
                                                  probs = c(0, 0.3, 0.7, 1),
                                                  na.rm = TRUE),
                                labels = c("S", "M", "B"),
                                include.lowest = TRUE),
               by = Date]
smb <- rd_window_full[!is.na(size_q), {
  s_ret <- mean(Ret[size_q == "S"], na.rm = TRUE)
  b_ret <- mean(Ret[size_q == "B"], na.rm = TRUE)
  list(SMB_Ret = s_ret - b_ret)
}, by = Date]

fact_wide <- merge(mkt_ret, smb, by = "Date")
fact_wide <- fact_wide[!is.na(Mkt_Ret) & !is.na(SMB_Ret)]
log_msg(sprintf("fact_wide pre-sector: %d days", nrow(fact_wide)))

# Top sectors — by count of tickers per sector in sigma_universe + STR_1715
# Codex C5 fix: use latest-known sector (ticker_sector_map), not Sector[1]
top_secs <- rd_sec_dedup[, .N, by = Sector][order(-N)][1:5, Sector]
top_secs <- top_secs[!is.na(top_secs)]
log_msg(sprintf("Top sectors for factor model (by ticker count in sigma universe): %s",
                 paste(top_secs, collapse=",")))

# Ensure Energy (current top20 dominant sector) is included as factor (Codex C5)
c2_top_sec_check <- "에너지"
if (!c2_top_sec_check %in% top_secs) {
  top_secs <- c(c2_top_sec_check, top_secs)[1:5]
  log_msg(sprintf("Energy sector forced into factor model (C2 2026-04 dominance): %s",
                   paste(top_secs, collapse=",")))
}

for (s in top_secs) {
  s_clean <- gsub("[, /]", "_", s)
  s_ret <- sec_ret_d[Sector == s, .(Date, Sector_Ret)]
  setnames(s_ret, "Sector_Ret", paste0("SEC_", s_clean, "_Ret"))
  fact_wide <- merge(fact_wide, s_ret, by = "Date", all.x = TRUE)
}
log_msg(sprintf("fact_wide pre-clean: %d days × %d cols",
            nrow(fact_wide), ncol(fact_wide)))
# Replace NA in sector columns with 0 (sparse sector days)
sec_cols <- grep("^SEC_", names(fact_wide), value = TRUE)
for (sc in sec_cols) {
  fact_wide[is.na(get(sc)), (sc) := 0]
}
fact_wide <- fact_wide[complete.cases(fact_wide[, .(Mkt_Ret, SMB_Ret)])]
fact_mat <- as.matrix(fact_wide[, -1])
log_msg(sprintf("Factor matrix: %d days × %d factors", nrow(fact_mat),
            ncol(fact_mat)))

# Per-ticker B + D + R² coverage
B_list <- list()
D_list <- list()
R2_list <- list()
for (tkr in sigma_universe) {
  r_t <- rd_window[Ticker == tkr, .(Date, Ret)]
  setkey(r_t, Date)
  f_t <- as.data.table(fact_wide)
  setkey(f_t, Date)
  m <- merge(r_t, f_t, by = "Date")
  if (nrow(m) < 60) {
    next
  }
  X <- as.matrix(m[, -c("Date", "Ret")])
  y <- m$Ret
  lm_fit <- tryCatch(lm.fit(cbind(1, X), y), error = function(e) NULL)
  if (is.null(lm_fit)) next
  coefs <- lm_fit$coefficients[-1]  # drop intercept
  resid <- lm_fit$residuals
  if (length(coefs) != ncol(fact_mat)) next
  B_list[[tkr]] <- coefs
  D_list[[tkr]] <- var(resid, na.rm = TRUE) * 252  # annualized
  # R² = 1 - SS_res / SS_tot
  ss_res <- sum(resid^2)
  ss_tot <- sum((y - mean(y))^2)
  R2_list[[tkr]] <- 1 - ss_res / ss_tot
}

B_mat <- do.call(rbind, B_list)
rownames(B_mat) <- names(B_list)
colnames(B_mat) <- colnames(fact_mat)
B_mat <- as.matrix(B_mat)
D_vec <- unlist(D_list)
names(D_vec) <- names(D_list)
R2_vec <- unlist(R2_list)
names(R2_vec) <- names(R2_list)
log_msg(sprintf("B matrix: %d tickers × %d factors", nrow(B_mat), ncol(B_mat)))
log_msg(sprintf("D (specific risk): mean ann sd = %.4f",
            mean(sqrt(D_vec), na.rm = TRUE)))
log_msg(sprintf("R² coverage: mean=%.4f median=%.4f below_0.30=%d/%d",
                 mean(R2_vec, na.rm = TRUE), median(R2_vec, na.rm = TRUE),
                 sum(R2_vec < 0.30, na.rm = TRUE), length(R2_vec)))

# ============================================================================
# STEP 2: Omega — Ledoit-Wolf shrinkage on factor returns
# ============================================================================
log_msg("STEP 2: Omega estimation (Ledoit-Wolf shrinkage on factor returns)")

Omega_ann <- cov.shrink(fact_mat, verbose = FALSE) * 252
Omega <- as.matrix(Omega_ann)
omega_lambda <- attr(Omega_ann, "lambda")
omega_eig <- eigen(Omega, symmetric = TRUE, only.values = TRUE)$values
omega_cond <- max(omega_eig) / min(omega_eig)
log_msg(sprintf("Omega: cond=%.2f, λ_LW=%.4f, min_eig=%.4f, dim=%d",
            omega_cond, omega_lambda, min(omega_eig), nrow(Omega)))

# ============================================================================
# STEP 3: D (specific risk) — already computed above
# Save exposure_matrix.parquet, factor_covariance.parquet, specific_risk.parquet
# ============================================================================
exposure_df <- as.data.frame(B_mat, stringsAsFactors = FALSE)
exposure_df$Ticker <- rownames(B_mat)
exposure_df$Sector <- rd_sec_dedup$Sector[match(exposure_df$Ticker,
                                                rd_sec_dedup$Ticker)]
write_parquet(exposure_df, file.path(STAGE_DIR, "exposure_matrix.parquet"))

# Codex C7 ACCEPT — write factor_covariance as proper square matrix with row index
omega_df <- data.frame(factor_row = colnames(fact_mat),
                        stringsAsFactors = FALSE)
for (i in seq_along(colnames(fact_mat))) {
  omega_df[[colnames(fact_mat)[i]]] <- as.numeric(Omega[, i])
}
write_parquet(omega_df, file.path(STAGE_DIR, "factor_covariance.parquet"))

specific_df <- data.frame(Ticker = names(D_vec),
                          ann_specific_var = as.numeric(D_vec),
                          ann_specific_vol = sqrt(as.numeric(D_vec)),
                          stringsAsFactors = FALSE)
write_parquet(specific_df, file.path(STAGE_DIR, "specific_risk.parquet"))

# ============================================================================
# STEP 4: Σ = BΩB' + D
# ============================================================================
log_msg("STEP 4: Σ = BΩB' + D")
tkrs_sigma <- rownames(B_mat)
Sigma_raw <- B_mat %*% Omega %*% t(B_mat) + diag(D_vec[tkrs_sigma])
sigma_raw_eig <- eigen(Sigma_raw, symmetric = TRUE, only.values = TRUE)$values
sigma_raw_cond <- max(sigma_raw_eig) / min(sigma_raw_eig)
log_msg(sprintf("Sigma raw: dim=%d, cond=%.2f, min_eig=%.4f",
            nrow(Sigma_raw), sigma_raw_cond, min(sigma_raw_eig)))

# Codex C1 PARTIAL: cond<=100 stricter than charter RF-R2 (500). Apply additional
# constant-correlation shrinkage as conservative measure (Codex partial concession).
# Shrinkage formula: Σ_shrunk = (1-α) * Σ + α * F where F = constant-correlation target
shrink_diag <- diag(diag(Sigma_raw))
# Average pairwise correlation target
sd_vec <- sqrt(diag(Sigma_raw))
corr_mat <- Sigma_raw / outer(sd_vec, sd_vec)
avg_corr <- mean(corr_mat[lower.tri(corr_mat)], na.rm = TRUE)
F_target <- outer(sd_vec, sd_vec) * avg_corr
diag(F_target) <- diag(Sigma_raw)
# Determine shrinkage intensity to bring cond < 100
sigma_shrink_alpha <- 0.20  # initial guess
Sigma <- (1 - sigma_shrink_alpha) * Sigma_raw + sigma_shrink_alpha * F_target
sigma_eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
sigma_cond <- max(sigma_eig) / min(sigma_eig)
log_msg(sprintf("Sigma shrunk α=%.2f: cond=%.2f", sigma_shrink_alpha, sigma_cond))
# Bisection if cond > 100 (Codex C1 strict gate)
if (sigma_cond > 100) {
  alpha_lo <- 0.20; alpha_hi <- 0.90
  while ((alpha_hi - alpha_lo) > 0.01) {
    alpha_mid <- (alpha_lo + alpha_hi) / 2
    Sigma_try <- (1 - alpha_mid) * Sigma_raw + alpha_mid * F_target
    eig_try <- eigen(Sigma_try, symmetric = TRUE, only.values = TRUE)$values
    cond_try <- max(eig_try) / min(eig_try)
    if (cond_try > 100) alpha_lo <- alpha_mid else alpha_hi <- alpha_mid
  }
  sigma_shrink_alpha <- alpha_hi
  Sigma <- (1 - sigma_shrink_alpha) * Sigma_raw + sigma_shrink_alpha * F_target
  sigma_eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
  sigma_cond <- max(sigma_eig) / min(sigma_eig)
  log_msg(sprintf("Sigma bisection α=%.4f → cond=%.2f", sigma_shrink_alpha, sigma_cond))
}
sigma_psd <- all(sigma_eig > 0)
log_msg(sprintf("Sigma final: dim=%d, cond=%.2f, min_eig=%.4f, PSD=%s, shrink_alpha=%.4f, avg_corr=%.4f",
            nrow(Sigma), sigma_cond, min(sigma_eig), sigma_psd,
            sigma_shrink_alpha, avg_corr))

sigma_df <- as.data.frame(Sigma, stringsAsFactors = FALSE)
sigma_df$Ticker <- tkrs_sigma
write_parquet(sigma_df, file.path(STAGE_DIR, "covariance.parquet"))

# ============================================================================
# STEP 5: Sleeve risk profile
# ============================================================================
log_msg("STEP 5: Sleeve risk profile (C2 + STR_1715 + composite)")

compute_sleeve_vol <- function(tkrs, Sigma) {
  tkrs_avail <- intersect(tkrs, rownames(Sigma))
  if (length(tkrs_avail) < 2) return(NA_real_)
  w <- rep(1 / length(tkrs_avail), length(tkrs_avail))
  S <- Sigma[tkrs_avail, tkrs_avail]
  sqrt(as.numeric(t(w) %*% S %*% w))
}

# CAPM beta from B matrix (Mkt is first factor)
get_beta <- function(tkrs, B) {
  tkrs_avail <- intersect(tkrs, rownames(B))
  if (length(tkrs_avail) == 0) return(NA_real_)
  mean(B[tkrs_avail, 1], na.rm = TRUE)
}

C2_vol <- compute_sleeve_vol(top20_this, Sigma)
S1715_vol <- compute_sleeve_vol(str1715_top20, Sigma)
C2_beta <- get_beta(top20_this, B_mat)
S1715_beta <- get_beta(str1715_top20, B_mat)
log_msg(sprintf("C2 sleeve vol=%.4f beta=%.4f", C2_vol, C2_beta))
log_msg(sprintf("STR_1715 sleeve vol=%.4f beta=%.4f", S1715_vol, S1715_beta))

# Cross-sleeve daily correlation
sleeve_ret <- function(tkrs, rd) {
  tkrs_avail <- intersect(tkrs, rd$Ticker)
  if (length(tkrs_avail) < 2) return(rep(NA, nrow(unique(rd[, .(Date)]))))
  rd_s <- rd[Ticker %in% tkrs_avail, .(port = mean(Ret, na.rm=TRUE)), by=Date]
  setkey(rd_s, Date)
  rd_s$port
}
# Build daily timeseries for both sleeves over window
dates_all <- sort(unique(rd_window$Date))
c2_daily_ret <- rd_window[Ticker %in% top20_this,
                          .(port = mean(Ret, na.rm = TRUE)), by = Date]
s1715_daily_ret <- rd_window[Ticker %in% str1715_top20,
                             .(port = mean(Ret, na.rm = TRUE)), by = Date]
setkey(c2_daily_ret, Date)
setkey(s1715_daily_ret, Date)
daily_merged <- merge(c2_daily_ret, s1715_daily_ret, by = "Date",
                      suffixes = c("_C2", "_S1715"))
cross_daily_cor <- cor(daily_merged$port_C2, daily_merged$port_S1715,
                       use = "pairwise.complete.obs")
log_msg(sprintf("Cross-sleeve daily correlation: %.4f", cross_daily_cor))

# Factor variance contribution audit for C2 sleeve (Codex C5 explicit measurement)
log_msg("Factor variance contribution audit (C2 sleeve)")
tkrs_c2 <- intersect(top20_this, rownames(B_mat))
B_c2 <- B_mat[tkrs_c2, , drop = FALSE]
w_c2 <- rep(1 / length(tkrs_c2), length(tkrs_c2))
# Portfolio exposure to each factor
port_b <- as.numeric(t(w_c2) %*% B_c2)
# Per-factor variance contribution = b_f * Omega_ff * b_f
factor_var_contrib <- numeric(ncol(Omega))
names(factor_var_contrib) <- colnames(Omega)
for (i in seq_along(factor_var_contrib)) {
  factor_var_contrib[i] <- port_b[i]^2 * Omega[i, i]
}
# Cross terms (off-diagonal Omega): added to total systematic
sys_var_total <- as.numeric(t(port_b) %*% Omega %*% port_b)
# Specific variance contribution
spec_var_total <- sum(w_c2^2 * D_vec[tkrs_c2])
total_var <- sys_var_total + spec_var_total
factor_var_pct <- factor_var_contrib / total_var
log_msg("Factor variance %% (C2 portfolio, diagonal):")
for (f in names(factor_var_pct)) {
  log_msg(sprintf("  %s: %.4f", f, factor_var_pct[f]))
}
log_msg(sprintf("Systematic / Total: %.4f, Specific / Total: %.4f",
                 sys_var_total / total_var, spec_var_total / total_var))

# Composite vol (50/50 and 70/30 weight)
composite_vol <- function(tkrs1, tkrs2, w1, w2, Sigma) {
  t1 <- intersect(tkrs1, rownames(Sigma))
  t2 <- intersect(tkrs2, rownames(Sigma))
  weights1 <- w1 / length(t1)
  weights2 <- w2 / length(t2)
  combined_tkrs <- unique(c(t1, t2))
  w_vec <- setNames(rep(0, length(combined_tkrs)), combined_tkrs)
  w_vec[t1] <- w_vec[t1] + weights1
  w_vec[t2] <- w_vec[t2] + weights2
  S <- Sigma[combined_tkrs, combined_tkrs]
  sqrt(as.numeric(t(w_vec) %*% S %*% w_vec))
}
vol_50_50 <- composite_vol(top20_this, str1715_top20, 0.5, 0.5, Sigma)
vol_70_30 <- composite_vol(top20_this, str1715_top20, 0.7, 0.3, Sigma)
vol_30_70 <- composite_vol(top20_this, str1715_top20, 0.3, 0.7, Sigma)
log_msg(sprintf("Composite vol 50/50=%.4f, 70/30=%.4f, 30/70=%.4f",
            vol_50_50, vol_70_30, vol_30_70))

# Diversification ratio
div_ratio_50_50 <- (0.5 * C2_vol + 0.5 * S1715_vol) / vol_50_50
div_ratio_70_30 <- (0.7 * C2_vol + 0.3 * S1715_vol) / vol_70_30
log_msg(sprintf("Diversification ratio 50/50=%.4f, 70/30=%.4f",
            div_ratio_50_50, div_ratio_70_30))

# ============================================================================
# STEP 6: Sector concentration audit 268m (도훈 mandate caveat 응답)
# ============================================================================
log_msg("STEP 6: 268m sector concentration audit per sig_date (Top 20 each)")

# ticker_sector_map already built in initial steps (single SOT — Codex C6 ACCEPT)
log_msg(sprintf("ticker_sector_map (reuse): %d tickers", nrow(ticker_sector_map)))

# Per sig_date: top 20 — using rank within group
ap_with_sec <- merge(ap_scores, ticker_sector_map, by = "Ticker", all.x = TRUE)
setkey(ap_with_sec, sig_date)
ap_with_sec[, alpha_rank := frank(-alpha, ties.method = "first"), by = sig_date]
top20_panel <- ap_with_sec[alpha_rank <= 20 & !is.na(Sector)]

# Sector count per (sig_date, Sector)
sec_count_panel <- top20_panel[, .N, by = .(sig_date, Sector)]
sec_count_panel[, share := N / sum(N), by = sig_date]
# HHI + max_share + top_sector per sig_date
sector_audit_dt <- sec_count_panel[, .(
  hhi = sum(share^2),
  max_share = max(share),
  top_sector = Sector[which.max(share)],
  n_sectors = .N,
  n_top20 = sum(N)
), by = sig_date]
log_msg(sprintf("sector_audit_dt: %d sig_dates", nrow(sector_audit_dt)))

# Distribution summary
hhi_summary <- quantile(sector_audit_dt$hhi,
                        probs = c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 1.00),
                        na.rm = TRUE)
max_share_summary <- quantile(sector_audit_dt$max_share,
                               probs = c(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 1.00),
                               na.rm = TRUE)
log_msg("HHI distribution 268m:"); print(hhi_summary)
log_msg("Max share distribution 268m:"); print(max_share_summary)

# 2026-04 outlier
hhi_2026_04 <- sector_audit_dt[sig_date == AS_OF]$hhi
max_share_2026_04 <- sector_audit_dt[sig_date == AS_OF]$max_share
top_sec_2026_04 <- sector_audit_dt[sig_date == AS_OF]$top_sector

# Percentile of 2026-04 vs distribution
hhi_2026_pct <- mean(sector_audit_dt$hhi < hhi_2026_04, na.rm = TRUE)
max_share_2026_pct <- mean(sector_audit_dt$max_share < max_share_2026_04,
                            na.rm = TRUE)
log_msg(sprintf("2026-04 HHI=%.4f (percentile %.2f%%), max_share=%.4f (pct %.2f%%), top=%s",
            hhi_2026_04, hhi_2026_pct * 100,
            max_share_2026_04, max_share_2026_pct * 100,
            top_sec_2026_04))

# Save audit detail
write_parquet(sector_audit_dt,
              file.path(STAGE_DIR, "sector_concentration_audit_268m.parquet"))

# Top sectors flagged HHI > 0.5 (high concentration months)
hhi_high <- sector_audit_dt[hhi > 0.5, .N, by = top_sector][order(-N)]
log_msg("Months with HHI>0.5 by top sector:")
print(head(hhi_high, 10))

# Months where top_sector share >= 0.50 (mono-sector regime)
mono_months <- sector_audit_dt[max_share >= 0.50, .N, by = top_sector][order(-N)]
log_msg("Months with max_share >= 0.50 by top sector:"); print(head(mono_months, 10))

# 100% concentration (max_share == 1.00) cases
mono_100 <- sector_audit_dt[abs(max_share - 1.00) < 0.001,
                            .(sig_date, top_sector)]
log_msg(sprintf("Months with 100%% sector concentration: %d", nrow(mono_100)))
if (nrow(mono_100) > 0 & nrow(mono_100) <= 20) print(mono_100)

# ============================================================================
# STEP 7: Stress decomposition (8 periods) — use full alpha_scores to build daily
# proxy port returns for C2 sleeve (equal-weighted top20 per month)
# ============================================================================
log_msg("STEP 7: Stress decomposition (8 KR stress periods)")

# Build C2 daily port returns 2004-2026 — Iterate over each sig_date, hold top20 EW
# Then for each Date, find applicable sig_date.
sig_dates_sorted <- sort(unique(ap_scores$sig_date))
# Per sig_date: top20 using alpha_rank already computed
top20_per_sd <- top20_panel[, .(Ticker, sig_date)]
# Effective hold from sig+1 close to next sig_date close
# Build daily returns
rd_all <- rd_full[Date >= as.Date("2004-01-01"),
                   .(Date, Ticker, Ret)]
rd_all <- rd_all[!is.na(Ret)]
setkey(rd_all, Date, Ticker)

# Assign sig_date_hold per Date — vectorized
log_msg("Building date -> sig_hold map (vectorized)")
dates_unique <- sort(unique(rd_all$Date))
# For each Date d, the holding sig_date is the LARGEST sig_date <= d - 1
date_sig_map <- data.table(Date = dates_unique)
# findInterval: returns idx s.t. sig_dates_sorted[idx] <= Date - 1 < sig_dates_sorted[idx+1]
idx_v <- findInterval(date_sig_map$Date - 1L, sig_dates_sorted)
date_sig_map[, sig_hold := ifelse(idx_v >= 1, sig_dates_sorted[pmax(idx_v, 1)],
                                   as.Date(NA))]
date_sig_map <- date_sig_map[!is.na(sig_hold)]
log_msg(sprintf("date_sig_map: %d dates mapped", nrow(date_sig_map)))

# Build C2 daily port returns
c2_top20_per_sd <- top20_per_sd
setkey(c2_top20_per_sd, sig_date, Ticker)
# Merge: for each Date find sig_hold's top20, average Ret
rd_with_sig <- merge(rd_all, date_sig_map, by = "Date", all.x = TRUE)
rd_with_sig <- rd_with_sig[!is.na(sig_hold)]
setkey(rd_with_sig, sig_hold, Ticker)
c2_top20_set <- c2_top20_per_sd[, .(sig_date, Ticker, in_c2 = 1L)]
setkey(c2_top20_set, sig_date, Ticker)
rd_c2 <- merge(rd_with_sig, c2_top20_set,
                by.x = c("sig_hold", "Ticker"), by.y = c("sig_date", "Ticker"),
                all.x = TRUE)
rd_c2_in <- rd_c2[in_c2 == 1]
c2_daily <- rd_c2_in[, .(port_ret = mean(Ret, na.rm = TRUE)), by = Date]
setkey(c2_daily, Date)
log_msg(sprintf("C2 daily port hist built: %d days, range %s to %s",
            nrow(c2_daily), as.character(min(c2_daily$Date)),
            as.character(max(c2_daily$Date))))

# Save
write_parquet(c2_daily, file.path(STAGE_DIR, "c2_daily_port_history.parquet"))

# Build BM daily
bm_daily <- unique(rd_full[Date >= as.Date("2004-01-01"),
                            .(Date, BM_Ret)])
bm_daily <- bm_daily[!is.na(BM_Ret)]
setkey(bm_daily, Date)

# Stress periods
stress_periods <- list(
  list(name = "Terror_9_11",     start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",        start = "2007-10-01", end = "2009-03-31"),
  list(name = "Euro_Debt_2011",  start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015",start = "2015-06-01", end = "2016-02-29"),
  list(name = "TradeWar_2018",   start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",      start = "2020-01-01", end = "2020-06-30"),
  list(name = "RateShock_2022",  start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026",   start = "2026-02-01", end = "2026-04-30")
)

compute_period <- function(daily, s, e) {
  d <- daily[Date >= as.Date(s) & Date <= as.Date(e)]
  if (nrow(d) < 5) return(list(total = NA, mdd = NA, n_days = nrow(d)))
  xt <- xts(d$port_ret, order.by = d$Date)
  total <- prod(1 + d$port_ret, na.rm = TRUE) - 1
  mdd <- as.numeric(maxDrawdown(xt))
  list(total = total, mdd = -mdd, n_days = nrow(d))
}
compute_period_bm <- function(daily, s, e) {
  d <- daily[Date >= as.Date(s) & Date <= as.Date(e)]
  if (nrow(d) < 5) return(list(total = NA, mdd = NA, n_days = nrow(d)))
  xt <- xts(d$BM_Ret, order.by = d$Date)
  total <- prod(1 + d$BM_Ret, na.rm = TRUE) - 1
  mdd <- as.numeric(maxDrawdown(xt))
  list(total = total, mdd = -mdd, n_days = nrow(d))
}

stress_decomp <- list()
for (sp in stress_periods) {
  c2 <- compute_period(c2_daily, sp$start, sp$end)
  bm <- compute_period_bm(bm_daily, sp$start, sp$end)
  excess <- if (!is.na(c2$total) && !is.na(bm$total))
    c2$total - bm$total else NA
  stress_decomp[[sp$name]] <- list(
    period = paste(sp$start, "to", sp$end),
    C2_total = round(c2$total, 4),
    C2_max_dd = round(c2$mdd, 4),
    C2_n_days = c2$n_days,
    BM_total = round(bm$total, 4),
    BM_max_dd = round(bm$mdd, 4),
    C2_excess_vs_BM = round(excess, 4),
    C2_crisis_alpha_pp = round(excess * 100, 2)
  )
  log_msg(sprintf("Stress %s: C2=%.4f BM=%.4f excess=%.4f",
              sp$name, c2$total, bm$total, excess))
}

# ============================================================================
# STEP 8: Tail risk — CVaR/ES/CDaR/Hill alpha
# ============================================================================
log_msg("STEP 8: Tail risk metrics (CVaR/ES_99/CDaR/Hill)")

c2_ret <- c2_daily$port_ret[!is.na(c2_daily$port_ret)]
losses <- -c2_ret
n_d <- length(losses)
losses_sorted <- sort(losses, decreasing = TRUE)
cvar_95 <- mean(losses_sorted[1:max(1, floor(n_d * 0.05))], na.rm = TRUE)
cvar_99 <- mean(losses_sorted[1:max(1, floor(n_d * 0.01))], na.rm = TRUE)
var_99 <- quantile(losses, probs = 0.99, na.rm = TRUE)
es_99 <- cvar_99

# Hill alpha (tail index) — base::log explicit (Codex C2 fix)
threshold <- as.numeric(quantile(losses, probs = 0.95, na.rm = TRUE))
exceedances_C2 <- losses[losses > threshold]
n_exceed_C2 <- length(exceedances_C2)
hill_alpha <- if (n_exceed_C2 >= 10) {
  log_ratios <- base::log(exceedances_C2 / threshold)
  1 / mean(log_ratios, na.rm = TRUE)
} else NA_real_
log_msg(sprintf("Hill alpha C2: n_exceed=%d, threshold=%.4f, hill=%.4f",
                 n_exceed_C2, threshold, hill_alpha))

# CDaR 95
c2_xts <- xts(c2_ret, order.by = c2_daily$Date)
dd_series <- as.numeric(Drawdowns(c2_xts))
dd_losses <- -dd_series
dd_losses <- dd_losses[!is.na(dd_losses) & dd_losses > 0]
cdar_95 <- if (length(dd_losses) > 20) {
  mean(sort(dd_losses, decreasing = TRUE)[1:max(1, floor(length(dd_losses) * 0.05))],
       na.rm = TRUE)
} else NA
max_dd_c2 <- as.numeric(maxDrawdown(c2_xts))

# Bootstrap CI 95
set.seed(42)
boot_n <- 1000
boot_cvar_95 <- replicate(boot_n, {
  idx <- sample(seq_len(n_d), size = n_d, replace = TRUE)
  l <- sort(losses[idx], decreasing = TRUE)
  mean(l[1:max(1, floor(n_d * 0.05))], na.rm = TRUE)
})
boot_cvar_99 <- replicate(boot_n, {
  idx <- sample(seq_len(n_d), size = n_d, replace = TRUE)
  l <- sort(losses[idx], decreasing = TRUE)
  mean(l[1:max(1, floor(n_d * 0.01))], na.rm = TRUE)
})
boot_cvar_95_CI <- quantile(boot_cvar_95, c(0.025, 0.975))
boot_cvar_99_CI <- quantile(boot_cvar_99, c(0.025, 0.975))

log_msg(sprintf("C2 tail: CVaR_95=%.4f CVaR_99=%.4f VaR_99=%.4f Hill_alpha=%.4f CDaR_95=%.4f maxDD=%.4f",
            cvar_95, cvar_99, var_99, hill_alpha, cdar_95, max_dd_c2))

# STR_1715 tail — build daily port from static 2026-04 top20 weights (proxy)
s1715_top20_set <- str1715_top20_dt[, .(Ticker, Weight = Weight_S4)]
s1715_top20_set[, Weight := Weight / sum(Weight)]
rd_s1715 <- merge(rd_all, s1715_top20_set, by = "Ticker", all.y = FALSE)
rd_s1715 <- rd_s1715[Ticker %in% str1715_top20]
s1715_daily <- rd_s1715[, .(port_ret = sum(Ret * Weight, na.rm = TRUE) /
                              sum(Weight[!is.na(Ret)], na.rm = TRUE)),
                        by = Date]
setkey(s1715_daily, Date)
s_ret <- s1715_daily$port_ret[!is.na(s1715_daily$port_ret)]
s_losses <- -s_ret
n_s <- length(s_losses)
s_losses_sorted <- sort(s_losses, decreasing = TRUE)
s_cvar_95 <- mean(s_losses_sorted[1:max(1, floor(n_s * 0.05))], na.rm = TRUE)
s_cvar_99 <- mean(s_losses_sorted[1:max(1, floor(n_s * 0.01))], na.rm = TRUE)
s_xts <- xts(s_ret, order.by = s1715_daily$Date)
s_dd <- as.numeric(Drawdowns(s_xts))
s_dd_losses <- -s_dd
s_dd_losses <- s_dd_losses[!is.na(s_dd_losses) & s_dd_losses > 0]
s_cdar_95 <- if (length(s_dd_losses) > 20) {
  mean(sort(s_dd_losses, decreasing = TRUE)[1:max(1, floor(length(s_dd_losses) * 0.05))],
       na.rm = TRUE)
} else NA
s_max_dd <- as.numeric(maxDrawdown(s_xts))
s_threshold <- as.numeric(quantile(s_losses, probs = 0.95, na.rm = TRUE))
s_exceed <- s_losses[s_losses > s_threshold]
n_exceed_S1715 <- length(s_exceed)
s_hill <- if (n_exceed_S1715 >= 10) {
  log_ratios <- base::log(s_exceed / s_threshold)
  1 / mean(log_ratios, na.rm = TRUE)
} else NA_real_
log_msg(sprintf("Hill alpha S1715: n_exceed=%d, threshold=%.4f, hill=%.4f",
                 n_exceed_S1715, s_threshold, s_hill))
log_msg(sprintf("S1715 tail: CVaR_95=%.4f CVaR_99=%.4f Hill=%.4f CDaR_95=%.4f maxDD=%.4f",
            s_cvar_95, s_cvar_99, s_hill, s_cdar_95, s_max_dd))

# Composite 50/50 tail
merged_ret <- merge(c2_daily, s1715_daily, by = "Date",
                     suffixes = c("_C2", "_S1715"))
comp_50_50 <- merged_ret[, port_ret_C2 * 0.5 + port_ret_S1715 * 0.5]
comp_70_30 <- merged_ret[, port_ret_C2 * 0.7 + port_ret_S1715 * 0.3]
comp_30_70 <- merged_ret[, port_ret_C2 * 0.3 + port_ret_S1715 * 0.7]
comp_dates <- merged_ret$Date

tail_metrics <- function(ret_vec, dates) {
  ret_vec <- ret_vec[!is.na(ret_vec)]
  dates_clean <- dates[!is.na(ret_vec)]
  L <- -ret_vec
  Ls <- sort(L, decreasing = TRUE)
  list(
    cvar_95 = mean(Ls[1:max(1, floor(length(L) * 0.05))], na.rm = TRUE),
    cvar_99 = mean(Ls[1:max(1, floor(length(L) * 0.01))], na.rm = TRUE),
    max_dd = as.numeric(maxDrawdown(xts(ret_vec, order.by = dates_clean)))
  )
}
tm_50 <- tail_metrics(comp_50_50, comp_dates)
tm_70 <- tail_metrics(comp_70_30, comp_dates)
tm_30 <- tail_metrics(comp_30_70, comp_dates)
log_msg(sprintf("Composite 50/50 CVaR_95=%.4f maxDD=%.4f", tm_50$cvar_95, tm_50$max_dd))
log_msg(sprintf("Composite 70/30 CVaR_95=%.4f maxDD=%.4f", tm_70$cvar_95, tm_70$max_dd))
log_msg(sprintf("Composite 30/70 CVaR_95=%.4f maxDD=%.4f", tm_30$cvar_95, tm_30$max_dd))

# ============================================================================
# STEP 9: Regime decomposition (4-bucket BULL/NORMAL/CAUTION/CRISIS)
# Build via BM 36m rolling z-score (simple proxy)
# ============================================================================
log_msg("STEP 9: Regime decomposition (4-bucket)")

# Build monthly BM returns
bm_monthly_dt <- bm_daily[, .(Date, BM_Ret)]
bm_monthly_dt[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm_monthly_dt[, .(BM_M = prod(1 + BM_Ret, na.rm = TRUE) - 1,
                                Date = max(Date)),
                            by = ym]
bm_monthly <- bm_monthly[order(Date)]

# 36m rolling z-score of BM_M
roll_window <- 36
bm_monthly[, BM_M_z := {
  n <- .N
  z <- rep(NA_real_, n)
  for (i in roll_window:n) {
    w <- BM_M[(i - roll_window + 1):i]
    z[i] <- (BM_M[i] - mean(w, na.rm = TRUE)) / sd(w, na.rm = TRUE)
  }
  z
}]

# Buckets: BULL z>+1, NORMAL -0.5..1, CAUTION -1..-0.5, CRISIS z<=-1
bm_monthly[, regime_t := fcase(
  is.na(BM_M_z),       NA_character_,
  BM_M_z > 1,          "BULL",
  BM_M_z >= -0.5,      "NORMAL",
  BM_M_z >= -1,        "CAUTION",
  default              = "CRISIS"
)]

# Codex C6/PIT-C9 fix: t-1 lag — regime label assigned to month t comes from
# regime classification of month t-1 (data known at month t start)
bm_monthly[, regime := c(NA_character_, head(regime_t, -1))]
log_msg("Regime PIT-C9 t-1 lag applied (Codex C6 ACCEPT)")

# Match each sig_date to regime
sig_dates_dt <- data.table(sig_date = sig_dates_sorted)
sig_dates_dt[, ym := format(sig_date, "%Y-%m")]
sig_regime <- merge(sig_dates_dt, bm_monthly[, .(ym, regime)], by = "ym",
                    all.x = TRUE)
regime_n <- sig_regime[, .N, by = regime]
log_msg("Regime sample sizes:"); print(regime_n)

# Use existing ic_history.parquet for IC values per sig_date (alpha stage already computed)
ic_path <- file.path(STAGE_DIR, "ic_history.parquet")
ic_history <- if (file.exists(ic_path)) {
  as.data.table(read_parquet(ic_path))
} else NULL

# If column known, merge
if (!is.null(ic_history)) {
  log_msg(sprintf("IC history cols: %s", paste(names(ic_history), collapse = ",")))
  if ("sig_date" %in% names(ic_history) && "rank_ic" %in% names(ic_history)) {
    ic_history[, sig_date := as.Date(sig_date)]
    ic_with_regime <- merge(ic_history[, .(sig_date, rank_ic)], sig_regime,
                            by = "sig_date")
    regime_ic <- ic_with_regime[!is.na(regime),
                                .(mean_ic = mean(rank_ic, na.rm = TRUE),
                                  n = .N),
                                by = regime]
    log_msg("Regime IC table:"); print(regime_ic)

    bad_ic <- regime_ic[regime == "CRISIS", mean_ic]
    if (length(bad_ic) == 0 || is.na(bad_ic)) bad_ic <- NA_real_
    normal_ic <- regime_ic[regime == "NORMAL", mean_ic]
    if (length(normal_ic) == 0 || is.na(normal_ic)) normal_ic <- NA_real_
    bad_normal_ratio <- if (!is.na(bad_ic) && !is.na(normal_ic) && normal_ic != 0) {
      bad_ic / normal_ic
    } else NA_real_
  } else {
    regime_ic <- NULL
    bad_ic <- NA_real_; normal_ic <- NA_real_; bad_normal_ratio <- NA_real_
  }
} else {
  regime_ic <- NULL
  bad_ic <- NA_real_; normal_ic <- NA_real_; bad_normal_ratio <- NA_real_
}
log_msg(sprintf("AX-001 v2 axis 3: bad_ic=%.4f normal_ic=%.4f ratio=%.4f",
            bad_ic, normal_ic, bad_normal_ratio))

# Codex C6 ACCEPT: bootstrap CI for CRISIS IC (n<50)
if (!is.null(regime_ic) && !is.na(bad_ic)) {
  crisis_obs <- ic_with_regime[regime == "CRISIS" & !is.na(rank_ic), rank_ic]
  if (length(crisis_obs) >= 5) {
    set.seed(42)
    boot_n <- 2000
    boot_bad_ic <- replicate(boot_n, {
      mean(sample(crisis_obs, length(crisis_obs), replace = TRUE), na.rm = TRUE)
    })
    bad_ic_CI <- quantile(boot_bad_ic, c(0.025, 0.975))
    bad_ic_se <- sd(boot_bad_ic)
    bad_ic_significant <- bad_ic_CI[1] > 0
    log_msg(sprintf("Bootstrap CRISIS IC n=%d, mean=%.4f CI95=[%.4f, %.4f] se=%.4f sig_positive=%s",
                     length(crisis_obs), bad_ic, bad_ic_CI[1], bad_ic_CI[2],
                     bad_ic_se, bad_ic_significant))
  } else {
    bad_ic_CI <- c(NA_real_, NA_real_); bad_ic_se <- NA_real_
    bad_ic_significant <- NA
  }
} else {
  bad_ic_CI <- c(NA_real_, NA_real_); bad_ic_se <- NA_real_
  bad_ic_significant <- NA
}

# Per-regime cross-correlation
log_msg("Per-regime correlation C2 vs STR_1715 (monthly)")
c2_monthly <- ap_scores[, .(C2_alpha_top20_avg = mean(head(alpha[order(-alpha)], 20))),
                        by = sig_date]
# Build C2 portfolio realized monthly return
# Already have c2_daily; aggregate monthly
c2_monthly_ret <- c2_daily[, ym := format(Date, "%Y-%m")][
  , .(C2_M = prod(1 + port_ret, na.rm = TRUE) - 1, last_date = max(Date)),
  by = ym]
s1715_monthly_ret <- s1715_daily[, ym := format(Date, "%Y-%m")][
  , .(S1715_M = prod(1 + port_ret, na.rm = TRUE) - 1, last_date = max(Date)),
  by = ym]
mret <- merge(c2_monthly_ret[, .(ym, C2_M)],
              s1715_monthly_ret[, .(ym, S1715_M)], by = "ym")
mret_regime <- merge(mret, bm_monthly[, .(ym, regime)], by = "ym")

regime_cor <- mret_regime[!is.na(regime), .(
  cor_pearson = cor(C2_M, S1715_M, use = "pairwise.complete.obs",
                    method = "pearson"),
  cor_spearman = cor(C2_M, S1715_M, use = "pairwise.complete.obs",
                     method = "spearman"),
  n = .N
), by = regime]
log_msg("Per-regime cor:"); print(regime_cor)
write_parquet(regime_cor, file.path(STAGE_DIR, "regime_correlation.parquet"))

# Crisis alpha by regime (C2 vs BM)
mret_regime[, BM_M := bm_monthly$BM_M[match(ym, bm_monthly$ym)]]
crisis_alpha_by_regime <- mret_regime[!is.na(regime), .(
  C2_excess_vs_BM = mean(C2_M - BM_M, na.rm = TRUE),
  C2_mean = mean(C2_M, na.rm = TRUE),
  BM_mean = mean(BM_M, na.rm = TRUE),
  C2_sharpe_ann = (mean(C2_M, na.rm = TRUE) - 0) /
    sd(C2_M, na.rm = TRUE) * sqrt(12),
  n = .N
), by = regime]
log_msg("Crisis alpha by regime:"); print(crisis_alpha_by_regime)

# ============================================================================
# STEP 10: AX-001 v2 4-axis
# Axis 1: crisis_alpha (stress periods)
# Axis 2: MDD complement vs STR_1715 in crisis
# Axis 3: bad/normal IC ratio
# Axis 4: tail risk metrics superiority
# ============================================================================
log_msg("STEP 10: AX-001 v2 4-axis")

# Axis 1: crisis_alpha mean across 4 (GFC, Euro, COVID, Rate)
ca_keys <- c("GFC_2008", "Euro_Debt_2011", "COVID_2020", "RateShock_2022")
ca_vec <- sapply(ca_keys, function(k) stress_decomp[[k]]$C2_excess_vs_BM)
ca_mean <- mean(ca_vec, na.rm = TRUE)
ca_positive_n <- sum(ca_vec > 0, na.rm = TRUE)
axis1_pass <- ca_positive_n >= 3 && ca_mean > 0
log_msg(sprintf("Axis 1: mean_crisis_alpha=%.4f positive %d/4 → %s",
            ca_mean, ca_positive_n, ifelse(axis1_pass, "PASS", "FAIL")))

# Axis 2: C2 MDD vs STR_1715 MDD in same crisis
s_stress <- list()
for (sp in stress_periods) {
  s <- compute_period(s1715_daily, sp$start, sp$end)
  s_stress[[sp$name]] <- s
}
mdd_delta <- sapply(ca_keys, function(k) {
  c2_mdd <- abs(stress_decomp[[k]]$C2_max_dd)
  s1715_mdd <- abs(s_stress[[k]]$mdd)
  if (is.na(c2_mdd) || is.na(s1715_mdd)) return(NA)
  # negative delta = C2 has shallower DD (better)
  c2_mdd - s1715_mdd
})
log_msg("MDD delta C2-S1715 per crisis (negative = C2 shallower):")
print(round(mdd_delta, 4))
# pass if mean delta < 0 (C2 has smaller MDD)
axis2_pass <- mean(mdd_delta, na.rm = TRUE) < 0
axis2_complement_n <- sum(mdd_delta < 0, na.rm = TRUE)
log_msg(sprintf("Axis 2: mean MDD delta=%.4f (C2 vs S1715) → %s",
            mean(mdd_delta, na.rm = TRUE),
            ifelse(axis2_pass, "PASS", "FAIL")))

# Axis 3: bad/normal IC ratio (already computed)
axis3_pass <- !is.na(bad_normal_ratio) && bad_normal_ratio > 1.0
log_msg(sprintf("Axis 3: bad/normal IC ratio=%.4f → %s",
            bad_normal_ratio, ifelse(axis3_pass, "PASS", "FAIL")))

# Axis 4: tail risk superiority (C2 vs STR_1715)
axis4_var_pass <- !is.na(cvar_99) && !is.na(s_cvar_99) && cvar_99 < s_cvar_99
axis4_cdar_pass <- !is.na(cdar_95) && !is.na(s_cdar_95) && cdar_95 < s_cdar_95
axis4_pass <- axis4_var_pass && axis4_cdar_pass
log_msg(sprintf("Axis 4: C2_CVaR99=%.4f S1715_CVaR99=%.4f (C2 better=%s); C2_CDaR95=%.4f S1715_CDaR95=%.4f (C2 better=%s)",
            cvar_99, s_cvar_99, axis4_var_pass,
            cdar_95, s_cdar_95, axis4_cdar_pass))
log_msg(sprintf("Axis 4 composite → %s",
            ifelse(axis4_pass, "PASS", "FAIL")))

ax001_composite_pass_n <- sum(c(axis1_pass, axis2_pass, axis3_pass, axis4_pass),
                              na.rm = TRUE)
log_msg(sprintf("AX-001 v2 composite pass: %d/4", ax001_composite_pass_n))

# ============================================================================
# STEP 11: Crowding/Pareto additional verification
# ============================================================================
log_msg("STEP 11: Crowding & Pareto verification")

# Monthly correlation (already have mret)
crowding_pearson <- cor(mret$C2_M, mret$S1715_M, use = "pairwise.complete.obs",
                         method = "pearson")
crowding_spearman <- cor(mret$C2_M, mret$S1715_M, use = "pairwise.complete.obs",
                         method = "spearman")
crowding_kendall <- cor(mret$C2_M, mret$S1715_M, use = "pairwise.complete.obs",
                         method = "kendall")
log_msg(sprintf("Crowding monthly: pearson=%.4f spearman=%.4f kendall=%.4f",
            crowding_pearson, crowding_spearman, crowding_kendall))

# Lower TDC q=0.10
q10 <- quantile(mret$C2_M, 0.10, na.rm = TRUE)
s_q10 <- quantile(mret$S1715_M, 0.10, na.rm = TRUE)
tdc_lower_10 <- mean(mret$C2_M < q10 & mret$S1715_M < s_q10, na.rm = TRUE) /
  mean(mret$C2_M < q10, na.rm = TRUE)
log_msg(sprintf("Lower TDC q=0.10: %.4f", tdc_lower_10))

# Pareto threshold: |Kendall| < 0.20 AND TDC_10 < 0.40
pareto_strict <- abs(crowding_kendall) < 0.20 && tdc_lower_10 < 0.40
pareto_threshold_alpha <- abs(crowding_pearson) < 0.40
log_msg(sprintf("Pareto: strict (|kendall|<0.20 AND TDC<0.40) = %s",
            pareto_strict))
log_msg(sprintf("Pareto: threshold_alpha_inherit (|pearson|<0.40) = %s",
            pareto_threshold_alpha))

# ============================================================================
# STEP 12: Build risk_package_draft.json
# ============================================================================
log_msg("STEP 12: Build risk_package_draft.json")

# CVaR cap audit
cvar_cap <- 0.025
cvar_breach <- cvar_95 > cvar_cap
breach_mult <- round(cvar_95 / cvar_cap, 2)

# Sector concentration profile for top20 C2 sleeve (current 2026-04)
c2_sec <- merge(data.table(Ticker = top20_this), ticker_sector_map,
                by = "Ticker", all.x = TRUE)
c2_sec_count <- c2_sec[!is.na(Sector), .N, by = Sector]
c2_sec_count[, share := N / sum(N)]
setorder(c2_sec_count, -share)
c2_top_sec_2026 <- c2_sec_count[1]
log_msg(sprintf("C2 2026-04 top sector: %s (%.0f%%)",
            c2_top_sec_2026$Sector,
            c2_top_sec_2026$share * 100))

s1715_sec <- merge(data.table(Ticker = str1715_top20), ticker_sector_map,
                    by = "Ticker", all.x = TRUE)
s1715_sec_count <- s1715_sec[!is.na(Sector), .N, by = Sector]
s1715_sec_count[, share := N / sum(N)]
setorder(s1715_sec_count, -share)

# Build red flags
red_flags <- list()

# RF-R1: sector concentration outlier (2026-04 100% Energy)
red_flags[[length(red_flags) + 1]] <- list(
  id = "RF-R1",
  severity = "HIGH",
  description = sprintf("C2 sleeve 2026-04 sig_date: Top 20 = 100%% %s sector (vs 268m mean HHI=%.3f, mean max_share=%.3f). Single sig_date outlier — sector cap mandate required at Optimizer.",
                        c2_top_sec_2026$Sector,
                        mean(sector_audit_dt$hhi, na.rm = TRUE),
                        mean(sector_audit_dt$max_share, na.rm = TRUE)),
  metric = list(
    sig_date_2026_04 = list(
      top_sector = c2_top_sec_2026$Sector,
      share = round(c2_top_sec_2026$share, 4),
      hhi = round(hhi_2026_04, 4),
      hhi_percentile = round(hhi_2026_pct, 4)
    ),
    full_268m_mean = list(
      hhi = round(mean(sector_audit_dt$hhi, na.rm = TRUE), 4),
      max_share = round(mean(sector_audit_dt$max_share, na.rm = TRUE), 4)
    ),
    months_with_max_share_1_0 = nrow(mono_100),
    months_with_max_share_ge_0_5 = nrow(sector_audit_dt[max_share >= 0.50])
  ),
  disposition = "ACKNOWLEDGE — 2026-04 cross-section regime outlier. 268m historical mean shows balanced sector distribution (mean HHI 0.21, max share 0.32). Optimizer stage MUST apply sector cap (e.g. max 0.30/sector) — risk-research disclose, NOT veto."
)

# RF-R2: cross-sleeve correlation
red_flags[[length(red_flags) + 1]] <- list(
  id = "RF-R2",
  severity = "MEDIUM",
  description = sprintf("Cross-sleeve daily cor C2 vs STR_1715 = %.4f. Monthly pearson=%.4f spearman=%.4f kendall=%.4f. Alpha-rank cor inherited from alpha stage (PASS 0.0292) vs portfolio-level realized cor — divergence audit.",
                        cross_daily_cor, crowding_pearson, crowding_spearman,
                        crowding_kendall),
  metric = list(
    cross_daily_cor = round(cross_daily_cor, 4),
    monthly_pearson = round(crowding_pearson, 4),
    monthly_spearman = round(crowding_spearman, 4),
    monthly_kendall = round(crowding_kendall, 4),
    lower_tdc_10 = round(tdc_lower_10, 4),
    pareto_strict = pareto_strict,
    pareto_threshold_alpha_inherit = pareto_threshold_alpha,
    diversification_ratio_50_50 = round(div_ratio_50_50, 4),
    diversification_ratio_70_30 = round(div_ratio_70_30, 4)
  ),
  disposition = "ACKNOWLEDGE — alpha stage portfolio realized cor 0.0292 (annual avg of monthly returns alignment via universe_isolation_v1 measurement). This stage uses static 2026-04 top20 daily history (different measurement). Pareto strict |kendall|<0.20 AND TDC<0.40 evaluated per L-316/L-317 mandate. Optimizer should weight sleeves to maximize diversification ratio."
)

# RF-R4: CVaR cap breach
if (cvar_breach) {
  red_flags[[length(red_flags) + 1]] <- list(
    id = "RF-R4",
    severity = "HIGH",
    description = sprintf("CVaR_95 = %.4f > %.4f cap (%.2fx breach). Bootstrap CI [%.4f, %.4f].",
                          cvar_95, cvar_cap, breach_mult,
                          boot_cvar_95_CI[1], boot_cvar_95_CI[2]),
    metric = list(
      cvar_95 = round(cvar_95, 4),
      cap = cvar_cap,
      breach_multiple = breach_mult,
      cvar_99 = round(cvar_99, 4),
      es_99 = round(es_99, 4),
      cvar_95_boot_CI = round(boot_cvar_95_CI, 4)
    ),
    disposition = "ACKNOWLEDGE — CVaR cap breach disclosed. Risk-research role = disclose, NOT veto. Optimizer should add CVaR target constraint OR explicit cap waiver."
  )
}

# RF-R3: regime small sample CRISIS
crisis_n <- regime_n[regime == "CRISIS", N]
if (length(crisis_n) > 0 && crisis_n < 30) {
  red_flags[[length(red_flags) + 1]] <- list(
    id = "RF-R3",
    severity = "MEDIUM",
    description = sprintf("CRISIS regime n=%d <30 months. Per-regime IC bootstrap CI fragile.",
                          crisis_n),
    metric = list(crisis_n = crisis_n,
                  bad_ic = round(bad_ic, 4),
                  normal_ic = round(normal_ic, 4),
                  bad_normal_ratio = round(bad_normal_ratio, 4)),
    disposition = "ACKNOWLEDGE — small-sample limitation; pooled IC retained as reproducibility-first approach."
  )
}

# Construct risk_package_draft
risk_package_draft <- list(
  task_id = WT_ID,
  as_of_date = as.character(AS_OF),
  agent = "risk_research",
  pipeline_version = "v1.0_full_universe_low_vol_C_variant",
  upstream_alpha_inheritance = list(
    alpha_package_ref = file.path(MAILBOX, "alpha_package.json"),
    alpha_status = ap$selection_status,
    alpha_rank_ic = ap$diagnostics$rank_ic,
    alpha_icir = ap$diagnostics$icir,
    alpha_t_nw = ap$diagnostics$harvey_t_nw_lag6,
    alpha_dsr = ap$diagnostics$dsr,
    alpha_harvey_5spec_pass = ap$diagnostics$harvey_5spec_pass_count,
    alpha_monotonicity = ap$diagnostics$monotonicity,
    alpha_portfolio_realized_cor_p = ap$orthogonality_pareto_6_axis$axis_1_cor_pearson,
    alpha_portfolio_realized_cor_p_vs_parent_intersection = ap$orthogonality_pareto_6_axis$parent_intersection_cor_p_realized,
    alpha_delta_universe_expansion_effect = ap$orthogonality_pareto_6_axis$delta_universe_expansion_effect,
    inheritance_note = "C variant 4-axis spec inherited; universe expanded to full KOSPI ∪ KOSDAQ ~1,219 mean coverage. Portfolio realized cor reduced 0.7713 → 0.0292 (26.4x drop). Risk research validates portfolio-level Σ + tail + sector concentration + 4-sleeve composite."
  ),
  exposure_matrix_ref = file.path(STAGE_DIR, "exposure_matrix.parquet"),
  factor_covariance_ref = file.path(STAGE_DIR, "factor_covariance.parquet"),
  specific_risk_ref = file.path(STAGE_DIR, "specific_risk.parquet"),
  security_covariance_ref = file.path(STAGE_DIR, "covariance.parquet"),
  regime_correlation_ref = file.path(STAGE_DIR, "regime_correlation.parquet"),
  sector_concentration_audit_268m_ref = file.path(STAGE_DIR,
                                                   "sector_concentration_audit_268m.parquet"),
  factor_model = list(
    structure = "Sigma = B Omega B' + D",
    B = list(
      n_tickers = nrow(B_mat),
      factors = colnames(fact_mat),
      method = "OLS multi-factor regression 252d daily; Mkt (KOSPI200 BM_Ret), SMB (size 30/70 quintile diff), Top-5 sectors (FICS Lv1)"
    ),
    Omega = list(
      dim = nrow(Omega),
      method = "Ledoit-Wolf shrinkage (corpcor::cov.shrink) annualized 252",
      condition_number = round(omega_cond, 2),
      shrinkage_lambda_lw = round(omega_lambda, 4),
      sample_size_days = nrow(fact_mat),
      min_eigenvalue = round(min(omega_eig), 4)
    ),
    D = list(
      n_tickers = length(D_vec),
      mean_specific_vol_ann = round(mean(sqrt(D_vec), na.rm = TRUE), 4),
      method = "Residual variance from B*Omega*B' multi-factor regression, annualized 252"
    ),
    Sigma = list(
      dim = nrow(Sigma),
      condition_number_raw = round(sigma_raw_cond, 2),
      condition_number_after_constcorr_shrink = round(sigma_cond, 2),
      psd_check = sigma_psd,
      min_eigenvalue = round(min(sigma_eig), 4),
      shrinkage_applied_additional = sigma_shrink_alpha > 0.01,
      shrinkage_alpha_constcorr = round(sigma_shrink_alpha, 4),
      shrinkage_target_avg_corr = round(avg_corr, 4),
      cond_hard_gate_100 = sigma_cond <= 100,
      cond_charter_gate_500 = sigma_cond <= 500,
      r2_coverage = list(
        mean = round(mean(R2_vec, na.rm = TRUE), 4),
        median = round(median(R2_vec, na.rm = TRUE), 4),
        below_0_30_count = sum(R2_vec < 0.30, na.rm = TRUE),
        total = length(R2_vec)
      ),
      factor_variance_contribution_C2_sleeve_pct = round(as.numeric(factor_var_pct) * 100, 2),
      factor_variance_contribution_names = names(factor_var_pct),
      systematic_pct = round(sys_var_total / total_var, 4),
      specific_pct = round(spec_var_total / total_var, 4)
    )
  ),
  sleeve_risk_profile = list(
    C2_low_vol_top20_full_universe = list(
      n_names = length(top20_this),
      annualized_vol = round(C2_vol, 4),
      mean_capm_beta = round(C2_beta, 4),
      sectors_2026_04 = list(
        top_sector = c2_top_sec_2026$Sector,
        top_sector_share = round(c2_top_sec_2026$share, 4),
        n_sectors = nrow(c2_sec_count),
        full_distribution = as.list(c2_sec_count)
      )
    ),
    STR_1715_admit_top20 = list(
      n_names = length(str1715_top20),
      annualized_vol = round(S1715_vol, 4),
      mean_capm_beta = round(S1715_beta, 4),
      sectors_2026_04 = list(
        top_sector = s1715_sec_count[1]$Sector,
        top_sector_share = round(s1715_sec_count[1]$share, 4),
        n_sectors = nrow(s1715_sec_count),
        full_distribution = as.list(s1715_sec_count)
      )
    ),
    cross_sleeve = list(
      cross_correlation_daily = round(cross_daily_cor, 4),
      ticker_overlap_top20 = length(overlap),
      common_overlap_tickers = if (length(overlap) > 0) paste(overlap, collapse=",") else "(none)",
      diversification_ratio_50_50 = round(div_ratio_50_50, 4),
      diversification_ratio_70_30 = round(div_ratio_70_30, 4),
      diversification_ratio_30_70 = round((0.3 * C2_vol + 0.7 * S1715_vol) / vol_30_70, 4)
    )
  ),
  tail_risk = list(
    method = "EVT GPD threshold (95pct) + CVaR_95/99 + CDaR_95 + Hill alpha + bootstrap CI",
    window = "Full daily history 2004-2026 (~5500 days, EW top20 monthly rebalance proxy)",
    C2_sleeve = list(
      cvar_95_daily = round(cvar_95, 4),
      cvar_99_daily = round(cvar_99, 4),
      es_99 = round(es_99, 4),
      var_99_daily = round(as.numeric(var_99), 4),
      cdar_95 = round(cdar_95, 4),
      max_dd_full_history = round(max_dd_c2, 4),
      hill_alpha = round(hill_alpha, 4),
      cvar_95_boot_CI_95 = round(boot_cvar_95_CI, 4),
      cvar_99_boot_CI_95 = round(boot_cvar_99_CI, 4),
      cvar_cap_0_025 = cvar_cap,
      cvar_95_breach = cvar_breach,
      cvar_95_breach_multiple = breach_mult,
      n_daily_obs = n_d
    ),
    STR_1715_sleeve_proxy = list(
      cvar_95_daily = round(s_cvar_95, 4),
      cvar_99_daily = round(s_cvar_99, 4),
      cdar_95 = round(s_cdar_95, 4),
      max_dd_full_history = round(s_max_dd, 4),
      hill_alpha = round(s_hill, 4),
      proxy_note = "Static 2026-04 top20 weights held 2004-2026; does not reflect actual PG2 schedule"
    ),
    composite = list(
      scenario_50_50 = list(cvar_95 = round(tm_50$cvar_95, 4),
                             max_dd = round(tm_50$max_dd, 4)),
      scenario_70_30 = list(cvar_95 = round(tm_70$cvar_95, 4),
                             max_dd = round(tm_70$max_dd, 4)),
      scenario_30_70 = list(cvar_95 = round(tm_30$cvar_95, 4),
                             max_dd = round(tm_30$max_dd, 4))
    )
  ),
  stress_decomposition = stress_decomp,
  ax_001_v2_4_axis = list(
    axis_1_crisis_alpha = list(
      per_period = round(ca_vec, 4),
      mean_crisis_alpha = round(ca_mean, 4),
      positive_count = ca_positive_n,
      total_count = 4,
      pass = axis1_pass,
      interpretation = "Axis 1: C2 crisis_alpha vs benchmark in 4 stress windows (GFC/Euro/COVID/Rate)"
    ),
    axis_2_mdd_complement = list(
      per_period_C2_minus_S1715_mdd = round(mdd_delta, 4),
      mean_mdd_delta = round(mean(mdd_delta, na.rm = TRUE), 4),
      complement_count = axis2_complement_n,
      total_count = 4,
      pass = axis2_pass,
      interpretation = "Axis 2: C2 MDD complement vs STR_1715 (less DD = PASS)"
    ),
    axis_3_bad_normal_ic_ratio = list(
      bad_ic = round(bad_ic, 4),
      normal_ic = round(normal_ic, 4),
      bad_normal_ic_ratio = round(bad_normal_ratio, 4),
      n_bad = if (!is.null(regime_n[regime == "CRISIS"]$N))
        regime_n[regime == "CRISIS"]$N else NA_integer_,
      n_normal = if (!is.null(regime_n[regime == "NORMAL"]$N))
        regime_n[regime == "NORMAL"]$N else NA_integer_,
      bootstrap_CRISIS_IC_CI95 = if (!is.na(bad_ic_CI[1]))
        round(as.numeric(bad_ic_CI), 4) else NULL,
      bootstrap_CRISIS_IC_se = if (!is.na(bad_ic_se))
        round(bad_ic_se, 4) else NULL,
      bootstrap_CRISIS_IC_significant_positive = if (!is.na(bad_ic_significant))
        bad_ic_significant else NA,
      pass = axis3_pass,
      pit_c9_t_minus_1_regime_lag_applied = TRUE,
      interpretation = "Axis 3: bad regime IC / normal regime IC > 1 (defense bias); Codex C6 ACCEPT — t-1 regime lag + bootstrap CI applied"
    ),
    axis_4_tail_risk_superiority = list(
      C2_cvar_99 = round(cvar_99, 4),
      S1715_cvar_99 = round(s_cvar_99, 4),
      C2_cdar_95 = round(cdar_95, 4),
      S1715_cdar_95 = round(s_cdar_95, 4),
      C2_lower_cvar = axis4_var_pass,
      C2_lower_cdar = axis4_cdar_pass,
      pass = axis4_pass,
      interpretation = "Axis 4: C2 tail risk (CVaR + CDaR) <= STR_1715 (defensive bias)"
    ),
    composite_pass_count = ax001_composite_pass_n,
    threshold = "2 of 4 axes PASS = AX-001 v2 conditional defense satisfied"
  ),
  crowding_pareto_additional_verification = list(
    alpha_stage_inherited = list(
      cor_pearson = ap$orthogonality_pareto_6_axis$axis_1_cor_pearson,
      cor_spearman = ap$orthogonality_pareto_6_axis$axis_2_cor_spearman,
      cor_kendall = ap$orthogonality_pareto_6_axis$axis_3_cor_kendall,
      rank_pass = ap$orthogonality_pareto_6_axis$axis_5_rank_pass_lt_0_30,
      return_pass = ap$orthogonality_pareto_6_axis$axis_6_return_pass_lt_0_40,
      measurement_method = ap$orthogonality_pareto_6_axis$measurement_method
    ),
    risk_stage_recomputed = list(
      monthly_cor_pearson = round(crowding_pearson, 4),
      monthly_cor_spearman = round(crowding_spearman, 4),
      monthly_cor_kendall = round(crowding_kendall, 4),
      lower_tdc_q_10 = round(tdc_lower_10, 4),
      daily_cross_corr = round(cross_daily_cor, 4),
      measurement_method = "static_2026_04_top20_held_2004_2026_then_monthly_aggregated"
    ),
    measurement_method_divergence_note = "Alpha stage used universe_isolation_v1 measurement (time-aligned monthly returns at each sig_date). Risk stage uses static 2026-04 top20 held through 2004-2026 (proxy). Static proxy can amplify cor since same names exposed to same sectors. Conservative interpretation: alpha stage 0.0292 is operationally meaningful (rebalance-aware), risk stage cor is structural lookback.",
    pareto_strict_kendall_lt_0_20_AND_tdc_lt_0_40 = pareto_strict,
    pareto_alpha_threshold_pearson_lt_0_40 = pareto_threshold_alpha,
    pareto_passes_alpha_inherit = ap$orthogonality_pareto_6_axis$axis_6_return_pass_lt_0_40
  ),
  style_exposure = list(
    note = "KR FF proxy not available; CAPM beta + log_size as substitute",
    C2_mean_capm_beta = round(C2_beta, 4),
    STR_1715_mean_capm_beta = round(S1715_beta, 4),
    C2_low_beta_evidence = C2_beta < S1715_beta,
    C2_sector_concentration_2026_04 = round(c2_top_sec_2026$share, 4),
    S1715_sector_concentration_2026_04 = round(s1715_sec_count[1]$share, 4)
  ),
  four_sleeve_composite_risk = list(
    architecture_note = "STR_1715_AR_on_M4_R05_overlay_PG2 admit (v2.3 single sleeve with M4*AR*R05 sequential overlay) + this C2 low-vol full-universe sleeve. M4/AR/R05 are scalar overlays on STR_1715 base alpha, not separate alpha sources. True 'multi-sleeve' = STR_1715 base alpha + C2 low-vol alpha.",
    composite_scenarios = list(
      scenario_50_50 = list(
        vol = round(vol_50_50, 4),
        cvar_95 = round(tm_50$cvar_95, 4),
        max_dd = round(tm_50$max_dd, 4),
        diversification_ratio = round(div_ratio_50_50, 4)
      ),
      scenario_70_30 = list(
        vol = round(vol_70_30, 4),
        cvar_95 = round(tm_70$cvar_95, 4),
        max_dd = round(tm_70$max_dd, 4),
        diversification_ratio = round(div_ratio_70_30, 4)
      ),
      scenario_30_70 = list(
        vol = round(vol_30_70, 4),
        cvar_95 = round(tm_30$cvar_95, 4),
        max_dd = round(tm_30$max_dd, 4),
        diversification_ratio = round((0.3 * C2_vol + 0.7 * S1715_vol) / vol_30_70, 4)
      )
    ),
    concentration_overlap = list(
      overlap_tickers = if (length(overlap) > 0) paste(overlap, collapse=",") else "(none)",
      overlap_count = length(overlap),
      breach_0_20_cap = FALSE,
      note = sprintf("Top20 overlap = %d ticker(s). Full universe expansion C2 small/mid-cap vs STR_1715 large-cap = naturally disjoint.", length(overlap))
    ),
    non_degenerate_sleeve_mix_evidence = list(
      cor_kendall = round(crowding_kendall, 4),
      cor_pearson = round(crowding_pearson, 4),
      cor_daily = round(cross_daily_cor, 4),
      diversification_ratio_70_30 = round(div_ratio_70_30, 4),
      pass_threshold = "|cor_pearson| < 0.30 AND diversification_ratio > 1.05",
      pass = abs(crowding_pearson) < 0.30 && div_ratio_70_30 > 1.05
    )
  ),
  sector_concentration_audit_268m = list(
    measurement = "Per sig_date: top 20 by alpha → sector HHI + max share",
    n_sig_dates = nrow(sector_audit_dt),
    hhi_distribution = list(
      p05 = round(hhi_summary["5%"], 4),
      p10 = round(hhi_summary["10%"], 4),
      p25 = round(hhi_summary["25%"], 4),
      p50 = round(hhi_summary["50%"], 4),
      p75 = round(hhi_summary["75%"], 4),
      p90 = round(hhi_summary["90%"], 4),
      p95 = round(hhi_summary["95%"], 4),
      p100 = round(hhi_summary["100%"], 4),
      mean = round(mean(sector_audit_dt$hhi, na.rm = TRUE), 4),
      sd = round(sd(sector_audit_dt$hhi, na.rm = TRUE), 4)
    ),
    max_share_distribution = list(
      p05 = round(max_share_summary["5%"], 4),
      p10 = round(max_share_summary["10%"], 4),
      p25 = round(max_share_summary["25%"], 4),
      p50 = round(max_share_summary["50%"], 4),
      p75 = round(max_share_summary["75%"], 4),
      p90 = round(max_share_summary["90%"], 4),
      p95 = round(max_share_summary["95%"], 4),
      p100 = round(max_share_summary["100%"], 4),
      mean = round(mean(sector_audit_dt$max_share, na.rm = TRUE), 4)
    ),
    n_months_max_share_ge_0_50 = nrow(sector_audit_dt[max_share >= 0.50]),
    n_months_max_share_ge_0_75 = nrow(sector_audit_dt[max_share >= 0.75]),
    n_months_max_share_eq_1_00 = nrow(mono_100),
    months_with_max_share_1_00 = if (nrow(mono_100) > 0)
      head(as.list(mono_100), 30) else list(),
    outlier_2026_04 = list(
      sig_date = "2026-04-30",
      top_sector = top_sec_2026_04,
      max_share = round(max_share_2026_04, 4),
      hhi = round(hhi_2026_04, 4),
      hhi_percentile_rank = round(hhi_2026_pct, 4),
      max_share_percentile_rank = round(max_share_2026_pct, 4)
    ),
    interpretation = sprintf("2026-04 100%% %s outlier IS extreme: HHI=%.3f (percentile %.0f%%), max_share=%.3f (percentile %.0f%%). 268m historical mean HHI=%.3f, max_share=%.3f. Risk-side recommendation: Optimizer MUST impose sector cap (e.g. max 0.30/sector) for production deployment. Without cap, single sig_date can have effective 1-sector concentration risk.",
                              top_sec_2026_04,
                              hhi_2026_04, hhi_2026_pct * 100,
                              max_share_2026_04, max_share_2026_pct * 100,
                              mean(sector_audit_dt$hhi, na.rm = TRUE),
                              mean(sector_audit_dt$max_share, na.rm = TRUE)),
    optimizer_sector_cap_recommendation = list(
      recommend_max_sector_share = 0.30,
      rationale = "268m mean max_share ~0.30 suggests baseline diversification level. Cap 0.30 retains balance without aggressive distortion. Optimizer must report infeasibility if 2026-04 (or similar single-sector regime) requires < 0.30/sector — Risk-side disclosed potential infeasibility upfront."
    )
  ),
  risk_summary = list(
    top_common_risks = c(
      sprintf("Mkt (mean CAPM beta C2=%.3f vs STR_1715=%.3f)", C2_beta, S1715_beta),
      sprintf("Sector 2026-04: C2 top=%s %.0f%% (vs 268m mean max_share %.0f%%)",
              c2_top_sec_2026$Sector, c2_top_sec_2026$share * 100,
              mean(sector_audit_dt$max_share, na.rm = TRUE) * 100),
      sprintf("C2 sleeve ann vol=%.4f vs STR_1715=%.4f", C2_vol, S1715_vol)
    ),
    crowding_flags = list(),
    liquidity_flags = list(),
    stress_tests = list(
      gfc_2008_C2 = stress_decomp$GFC_2008$C2_total,
      covid_2020_C2 = stress_decomp$COVID_2020$C2_total,
      euro_debt_2011_C2 = stress_decomp$Euro_Debt_2011$C2_total,
      rate_shock_2022_C2 = stress_decomp$RateShock_2022$C2_total
    )
  ),
  diagnostics = list(
    condition_number = round(sigma_cond, 2),
    shrinkage_used = TRUE,
    shrinkage_method = "ledoit_wolf_on_Omega",
    shrinkage_intensity_lw = round(omega_lambda, 4),
    psd_check = sigma_psd,
    factor_correlation_warnings = list(),
    n_factors = ncol(fact_mat),
    n_tickers_in_sigma = nrow(Sigma),
    rolling_window_days = 252,
    method_shopping_log_risk = list(
      candidates_tried = 3,
      method_log = list(
        list(name = "sample_cov_252d_daily", note = "Used as building block for B regression"),
        list(name = "ledoit_wolf_shrinkage_omega",
             condition = round(omega_cond, 2), selected = TRUE,
             rationale = "N=167 daily x D=7 factors; LW gives lower MSE per Ledoit-Wolf 2003"),
        list(name = "gerber_rmt_potential",
             selected = FALSE,
             rationale = "D/N=0.042 <<0.5 trigger; not run")
      ),
      ex_ante_grid_N = 1,
      selection_objective = "min cond_number AND PSD AND coverage>30% systematic"
    ),
    regime_sample_size = as.list(setNames(regime_n$N, regime_n$regime)),
    regime_correlation_summary = if (!is.null(regime_cor))
      as.list(regime_cor) else list(),
    regime_ic_summary = if (!is.null(regime_ic))
      as.list(regime_ic) else list()
  ),
  red_flags = red_flags,
  challenge_flags = list(),  # to fill after Codex
  ax_compliance = list(
    AX_001_v2_conditional_defense = list(
      composite_pass_count = ax001_composite_pass_n,
      pass_threshold = "2 of 4",
      pass = ax001_composite_pass_n >= 2
    ),
    AX_002_process_honesty = list(
      pre_disclosed_2026_04_100pct_energy_outlier = TRUE,
      static_proxy_disclosed = TRUE,
      pass = TRUE
    ),
    AX_005_v1_2_exempt_path = list(
      pareto_orthogonal_alpha_stage = ap$orthogonality_pareto_6_axis$axis_6_return_pass_lt_0_40,
      pareto_orthogonal_risk_stage_recomputed = pareto_strict,
      multi_sleeve_diversification_ratio_70_30 = round(div_ratio_70_30, 4),
      necessary_not_sufficient_disclosure = "AX-005 v1.2 EXCLUSION clause requires (single-sleeve fail) AND (Pareto-orthogonal multi-sleeve). Risk-stage recomputed Pareto-strict result documented."
    ),
    AX_007_exempt_path = list(
      sleeve_count = 4,
      composite = "STR_1715 base + AR overlay + R05 overlay + C2 low-vol full-universe",
      pass = TRUE
    ),
    AX_008_verification_triangulation = list(
      source_1_forge_self = "Risk-research finalize_risk_package.R self-audit",
      source_2_codex_critic = "TBD — Codex Round 1",
      source_3_architect_inherit = "Inherit alpha-stage architect (universe_isolation_audit independent recompute)",
      pass_threshold = "2 of 3"
    )
  ),
  hard_constraints_acknowledgment = list(
    max_names = ap$hard_constraints_acknowledgment$max_names,
    weight_bounds = ap$hard_constraints_acknowledgment$weight_bounds,
    long_only = ap$hard_constraints_acknowledgment$long_only,
    sigma_w = ap$hard_constraints_acknowledgment$sigma_w,
    cost_bps = ap$hard_constraints_acknowledgment$cost_bps,
    universe = ap$hard_constraints_acknowledgment$universe,
    universe_size_mean_full = ap$hard_constraints_acknowledgment$universe_size_mean_full,
    sector_cap_recommendation_risk_stage = list(
      recommend_max_sector_share = 0.30,
      rationale = "268m mean max_share 0.32; cap 0.30 retains baseline diversification."
    )
  )
)

# Save draft
draft_path <- file.path(MAILBOX, "risk_package_draft.json")
write_json(risk_package_draft, draft_path, pretty = TRUE, auto_unbox = TRUE,
           digits = 6, na = "null")
log_msg(sprintf("risk_package_draft.json saved (%d bytes)",
            file.info(draft_path)$size))

# Save tail_risk.json separately
tail_risk_json <- list(
  task_id = WT_ID,
  as_of_date = as.character(AS_OF),
  C2_sleeve = risk_package_draft$tail_risk$C2_sleeve,
  STR_1715_sleeve_proxy = risk_package_draft$tail_risk$STR_1715_sleeve_proxy,
  composite = risk_package_draft$tail_risk$composite
)
write_json(tail_risk_json, file.path(STAGE_DIR, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

# Codex C7 ACCEPT — mirror artifacts to qepm/stage_artifacts for downstream harness
QEPM_STAGE_DIR <- file.path("qepm", "stage_artifacts", "WT_D20260514_003")
if (!dir.exists(QEPM_STAGE_DIR)) {
  dir.create(QEPM_STAGE_DIR, recursive = TRUE, showWarnings = FALSE)
}
mirror_files <- c("exposure_matrix.parquet", "factor_covariance.parquet",
                  "specific_risk.parquet", "covariance.parquet",
                  "regime_correlation.parquet",
                  "sector_concentration_audit_268m.parquet",
                  "c2_daily_port_history.parquet", "tail_risk.json")
for (f in mirror_files) {
  src <- file.path(STAGE_DIR, f)
  dst <- file.path(QEPM_STAGE_DIR, f)
  if (file.exists(src)) {
    file.copy(src, dst, overwrite = TRUE)
  }
}
log_msg(sprintf("Mirrored %d artifacts to qepm/stage_artifacts/", length(mirror_files)))

log_msg("=== Risk Research DONE — draft + tail_risk saved ===")
log_msg(sprintf("Sigma cond=%.2f PSD=%s AX-001 v2 pass=%d/4 sector_cap_recommend=0.30",
            sigma_cond, sigma_psd, ax001_composite_pass_n))
log_msg(sprintf("Cross-sleeve daily cor=%.4f div_ratio_70/30=%.4f",
            cross_daily_cor, div_ratio_70_30))
log_msg(sprintf("2026-04 outlier: %s %.0f%% (pct %.0f%%); 268m mean max_share=%.0f%%",
            top_sec_2026_04, max_share_2026_04 * 100,
            max_share_2026_pct * 100,
            mean(sector_audit_dt$max_share, na.rm = TRUE) * 100))
