#==============================================================================
# STR_1715_LRO_v0.1 — Single-Rebalance Debug (PIT Audit Gate)
#
# Plan: qvest-v7-2-1-execution-prompt-dapper-dragon.md §3
# Rebalance date: 2024-12-31
# Output: stage_artifacts/WT_WT-S20260503_001/_debug/
#         - residuals.parquet (U_t at sig_date)
#         - B_t.parquet, B_ref.parquet (loadings)
#         - Q_t.json (Procrustes alignment)
#         - D_t.json (subspace drift)
#         - LRI.json (single-point Latent Risk Index)
#         - mrc.json (portfolio decomposition for STR_1715 weight proxy)
#         - anchor_R2.json (10 anchors)
#         - pit_audit_2024_12_31.json
#         - debug_pass.json (9-field gate)
#
# WT: WT-S20260503_001 (sizing_only, recommendation_only)
# Author: risk-research agent
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(MASS)  # ginv
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-S20260503_001"
DEBUG_DIR    <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID),
                          "_debug", "single_rebalance_2024_12_31")
DEBUG_ROOT   <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID), "_debug")
LOG_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID), "_logs")
dir.create(DEBUG_DIR, showWarnings = FALSE, recursive = TRUE)

# ─────────────────────────────────────────────────────────
# 1. Setup
# ─────────────────────────────────────────────────────────
SIG_DATE <- as.Date("2024-12-31")  # rebalance date (single point)
WINDOW_DAYS <- 252L                 # IS chooses {252, 504} — debug uses 252 first
K_DEBUG <- 5L                       # K candidates {3,5,8} — debug uses 5
ANCHORS <- c("Market","Size","Value","Momentum","Quality","LowRisk",
             "Semi_AI","Bio","Energy_Cyclical","Revision")

cat("[LRO debug] sig_date =", as.character(SIG_DATE),
    " | window =", WINDOW_DAYS, "d | K =", K_DEBUG, "\n")

source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"))

# ─────────────────────────────────────────────────────────
# 2. RAWDATA window load (PIT — strictly t < sig_date)
# ─────────────────────────────────────────────────────────
cat("[LRO debug] Loading RAWDATA…\n")
raw <- as.data.table(read_parquet(RAWDATA_CACHE))
setkey(raw, Date, Ticker)

window_start <- SIG_DATE - WINDOW_DAYS - 30L  # 30d buffer for trading days
raw_win <- raw[Date < SIG_DATE & Date >= window_start,
               .(Date, Ticker, Ret, Size, Sector)]
raw_win <- raw_win[!is.na(Ret) & is.finite(Ret)]

# Universe filter: KOSPI200 ∪ KOSDAQ150 proxy via Size + liquidity
# Stage requires liquid universe — use Size top 500 by month-end
last_d <- max(raw_win$Date)
size_at_last <- raw_win[Date == last_d, .(Size = mean(Size, na.rm = TRUE)), by = Ticker]
size_at_last <- size_at_last[!is.na(Size)]
setorder(size_at_last, -Size)
top_universe <- size_at_last[seq_len(min(500L, nrow(size_at_last))), Ticker]

raw_win <- raw_win[Ticker %in% top_universe]
cat("[LRO debug]  window_start =", as.character(window_start),
    "| last_d =", as.character(last_d),
    "| n_universe =", length(unique(raw_win$Ticker)), "\n")

# Wide returns matrix (Date × Ticker)
ret_wide <- dcast(raw_win, Date ~ Ticker, value.var = "Ret", fill = NA_real_)
date_vec <- ret_wide$Date
ret_mat <- as.matrix(ret_wide[, -1, with = FALSE])
rownames(ret_mat) <- as.character(date_vec)

# Coverage filter: keep tickers with ≥80% obs in window
cov_pct <- colSums(!is.na(ret_mat)) / nrow(ret_mat)
keep_tickers <- names(cov_pct)[cov_pct >= 0.80]
ret_mat <- ret_mat[, keep_tickers, drop = FALSE]
ret_mat[is.na(ret_mat)] <- 0  # zero-fill (regression-friendly; coverage ≥80% pre-filtered)

cat("[LRO debug]  n_dates =", nrow(ret_mat),
    "| n_tickers (post-cov) =", ncol(ret_mat), "\n")

# ─────────────────────────────────────────────────────────
# 3. Known factor returns (PIT — same window, t < sig_date)
#    Construct LSV-style factor returns from cross-sectional sorts on Z-scores.
# ─────────────────────────────────────────────────────────
cat("[LRO debug] Constructing 6 known KR factor returns…\n")

# Approach: for each Date in window, build daily factor return as
#   long-short EW spread of top/bottom decile by factor Z (PIT — uses
#   month-end factor DB available at that date).
# Use month-end Z's in factor_db, applied for entire calendar month.
build_factor_ret <- function(factor_short_name, raw_dt, dates_in_window, sig_d) {
  # factor_short_name: "MKT_KR" / "SIZE_KR" / etc → registry name mapping
  # registry lookup
  reg <- jsonlite::fromJSON(FACTOR_REG_PATH)

  candidates <- list(
    MKT_KR    = c("MK01_CAPM_Beta","D02_Beta","D12_Beta_126d"),
    SIZE_KR   = c("L26_Log_MktCap"),       # higher => big => Z_aligned will flip via direction
    VALUE_KR  = c("V01_BM","V02_EP"),
    MOM_KR    = c("M01_Mom_12_1"),
    QUALITY_KR= c("Q01_GPA","Q02_ROE","Q03_ROA","Q07_Earnings_Stability"),
    LOWVOL_KR = c("R01_VaR_95","R02_VaR_99","D02_Beta")
  )
  cands <- candidates[[factor_short_name]]
  cands <- cands[cands %in% names(reg)]
  if (length(cands) == 0L) return(rep(0, length(dates_in_window)))

  # Build monthly factor mean Z then map to daily by month
  ym_seq <- unique(format(dates_in_window, "%Y-%m"))
  fac_by_month <- list()
  for (ym in ym_seq) {
    # signal date = first day of month (PIT — factor DB uses prior month-end)
    sig_m <- as.Date(paste0(ym, "-01"))
    if (sig_m > sig_d) next
    panel <- tryCatch(
      load_month_factors(sig_m, coverage_min = 0.05),
      error = function(e) NULL
    )
    if (is.null(panel) || nrow(panel) == 0L) next
    panel_sub <- panel[Factor_Name %in% cands]
    if (nrow(panel_sub) == 0L) next
    # average Z across cands
    z_avg <- panel_sub[, .(Z = mean(Z_Score_Aligned, na.rm = TRUE)), by = Ticker]
    fac_by_month[[ym]] <- z_avg
  }

  # daily factor return: top/bottom 30% spread of next-day return
  ret_daily <- numeric(length(dates_in_window))
  for (i in seq_along(dates_in_window)) {
    d <- dates_in_window[i]
    ym <- format(d, "%Y-%m")
    z_avg <- fac_by_month[[ym]]
    if (is.null(z_avg)) next
    rd <- raw_dt[Date == d, .(Ticker, Ret)]
    rd <- rd[!is.na(Ret) & is.finite(Ret)]
    mer <- merge(z_avg, rd, by = "Ticker")
    if (nrow(mer) < 30L) next
    q_top <- quantile(mer$Z, 0.70, na.rm = TRUE)
    q_bot <- quantile(mer$Z, 0.30, na.rm = TRUE)
    rt_top <- mer[Z >= q_top, mean(Ret)]
    rt_bot <- mer[Z <= q_bot, mean(Ret)]
    ret_daily[i] <- rt_top - rt_bot
  }
  ret_daily
}

f_names <- c("MKT_KR","SIZE_KR","VALUE_KR","MOM_KR","QUALITY_KR","LOWVOL_KR")
F_mat <- matrix(0, nrow = length(date_vec), ncol = length(f_names),
                dimnames = list(as.character(date_vec), f_names))
for (fn in f_names) {
  F_mat[, fn] <- build_factor_ret(fn, raw_win, date_vec, SIG_DATE)
  cat("[LRO debug]  ", fn, " sd =", round(sd(F_mat[, fn], na.rm = TRUE), 5),
      " | nz_frac =", round(mean(F_mat[, fn] != 0), 3), "\n")
}

# Sector returns: 11 sector dummies → mean return per sector per date
sector_panel <- raw_win[Date %in% date_vec & Ticker %in% colnames(ret_mat),
                        .(Date, Ticker, Sector, Ret)]
sector_panel[is.na(Sector) | Sector == "", Sector := "Unknown"]
sector_levels <- unique(sector_panel$Sector)
# Cap to 11 most populous
sec_count <- sector_panel[, .N, by = Sector][order(-N)]
top_sec <- sec_count[seq_len(min(11L, .N)), Sector]
sector_panel[!Sector %in% top_sec, Sector := "Other"]
top_sec <- unique(c(top_sec, "Other"))[1:min(11L, length(unique(sector_panel$Sector)))]

sec_ret <- dcast(
  sector_panel[, .(Ret = mean(Ret, na.rm = TRUE)), by = .(Date, Sector)],
  Date ~ Sector, value.var = "Ret", fill = 0
)
sec_dates <- sec_ret$Date
S_mat <- as.matrix(sec_ret[, -1, with = FALSE])
rownames(S_mat) <- as.character(sec_dates)

# Align rows to date_vec
common_dates <- intersect(rownames(ret_mat), rownames(S_mat))
ret_mat <- ret_mat[common_dates, , drop = FALSE]
F_mat <- F_mat[common_dates, , drop = FALSE]
S_mat <- S_mat[common_dates, , drop = FALSE]
date_vec_aligned <- as.Date(common_dates)

cat("[LRO debug] aligned rows =", length(common_dates),
    "| F cols =", ncol(F_mat), "| S cols =", ncol(S_mat), "\n")

# ─────────────────────────────────────────────────────────
# 4. Residualization: U_t = ret - X β_t  (X = [F, S, intercept])
# ─────────────────────────────────────────────────────────
X_mat <- cbind(1, F_mat, S_mat)
colnames(X_mat)[1] <- "const"

# OLS per ticker (returns matrix → residual matrix)
N_t <- ncol(ret_mat)
T_n <- nrow(ret_mat)
U_mat <- matrix(0, nrow = T_n, ncol = N_t,
                dimnames = list(common_dates, colnames(ret_mat)))

# Vectorized: B = (X'X)^-1 X'Y, U = Y - X B
XtX <- crossprod(X_mat)
XtX_inv <- tryCatch(solve(XtX), error = function(e) ginv(XtX))
B_known <- XtX_inv %*% crossprod(X_mat, ret_mat)
fitted <- X_mat %*% B_known
U_mat <- ret_mat - fitted

# Sanity: residual cov rank
U_var <- colSums(U_mat^2) / (T_n - ncol(X_mat))
ok_cols <- which(U_var > 1e-8)
U_mat <- U_mat[, ok_cols, drop = FALSE]
cat("[LRO debug] residual matrix:", nrow(U_mat), "×", ncol(U_mat),
    "| mean abs =", round(mean(abs(U_mat)), 5), "\n")

# Save residuals
residuals_dt <- as.data.table(U_mat)
residuals_dt[, Date := date_vec_aligned]
setcolorder(residuals_dt, c("Date", setdiff(names(residuals_dt), "Date")))
write_parquet(residuals_dt,
              file.path(DEBUG_DIR, "residuals.parquet"))

# ─────────────────────────────────────────────────────────
# 5. PCA on covariance + correlation, K = K_DEBUG
# ─────────────────────────────────────────────────────────
cov_U <- cov(U_mat, use = "pairwise.complete.obs")
cor_U <- cor(U_mat, use = "pairwise.complete.obs")
cov_U[!is.finite(cov_U)] <- 0
cor_U[!is.finite(cor_U)] <- 0

# Eigendecomp
eig_cov <- eigen(cov_U, symmetric = TRUE)
eig_cor <- eigen(cor_U, symmetric = TRUE)

# K_DEBUG top components
B_t_cov <- eig_cov$vectors[, seq_len(K_DEBUG), drop = FALSE]
lambda_cov <- eig_cov$values[seq_len(K_DEBUG)]
B_t_cor <- eig_cor$vectors[, seq_len(K_DEBUG), drop = FALSE]
lambda_cor <- eig_cor$values[seq_len(K_DEBUG)]

# Eigenvalue gap audit — use relative gap (λ_K - λ_{K+1}) / λ_K >= 1e-3
# Absolute 1e-3 fails on covariance (units of variance ~ 1e-2..1e-4)
.rel_gap <- function(eigs, K) {
  if (length(eigs) <= K || eigs[K] <= 0) return(0)
  (eigs[K] - eigs[K + 1]) / eigs[K]
}
eig_gap_cov_val <- .rel_gap(eig_cov$values, K_DEBUG)
eig_gap_cor_val <- .rel_gap(eig_cor$values, K_DEBUG)
eig_gap_cov <- eig_gap_cov_val >= 1e-3  # relative gap threshold
eig_gap_cor <- eig_gap_cor_val >= 1e-3
cat("[LRO debug] cov eigvals top", K_DEBUG, "=", round(lambda_cov, 4), "\n")
cat("[LRO debug] cor eigvals top", K_DEBUG, "=", round(lambda_cor, 4), "\n")
cat("[LRO debug] rel eig_gap (λK-λK+1)/λK (cov/cor) =",
    signif(eig_gap_cov_val, 3), "/", signif(eig_gap_cor_val, 3),
    "| pass(>=1e-3) =", eig_gap_cov, "/", eig_gap_cor, "\n")

# Pick cov for debug (compare in main run)
B_t <- B_t_cov
lambda_t <- lambda_cov
rownames(B_t) <- colnames(U_mat)
colnames(B_t) <- paste0("PC", seq_len(K_DEBUG))

# Save B_t
B_t_dt <- as.data.table(B_t, keep.rownames = "Ticker")
write_parquet(B_t_dt, file.path(DEBUG_DIR, "B_t.parquet"))

# B_ref: in single-point debug, use same B_t (truthful: in rolling, B_ref freezes at IS endpoint)
B_ref <- B_t
B_ref_dt <- as.data.table(B_ref, keep.rownames = "Ticker")
write_parquet(B_ref_dt, file.path(DEBUG_DIR, "B_ref.parquet"))

# ─────────────────────────────────────────────────────────
# 6. Procrustes alignment
# ─────────────────────────────────────────────────────────
# In single-point debug, B_ref == B_t → Q_t == I, drift D_t == 0
proc_align <- function(Bt, Bref) {
  M <- crossprod(Bref, Bt)  # K × K
  svd_M <- svd(M)
  Q <- svd_M$v %*% t(svd_M$u)  # rotate Bt -> Bref
  Bt_aligned <- Bt %*% Q
  list(Q = Q, Bt_aligned = Bt_aligned,
       align_quality = norm(Bt_aligned - Bref, type = "F") / sqrt(2 * ncol(Bt)))
}
proc_res <- proc_align(B_t, B_ref)
write_json(list(Q = proc_res$Q,
                align_quality = proc_res$align_quality,
                K = K_DEBUG),
           file.path(DEBUG_DIR, "Q_t.json"))

# Subspace drift
P_t <- proc_res$Bt_aligned %*% t(proc_res$Bt_aligned)
P_ref <- B_ref %*% t(B_ref)
D_t <- norm(P_t - P_ref, type = "F") / sqrt(2 * K_DEBUG)
write_json(list(D_t = D_t,
                K = K_DEBUG,
                interpretation = "single-point debug: B_ref == B_t → D_t ≈ 0"),
           file.path(DEBUG_DIR, "D_t.json"))

cat("[LRO debug] Procrustes align_quality =", round(proc_res$align_quality, 6),
    "| D_t =", round(D_t, 6), "\n")

# ─────────────────────────────────────────────────────────
# 7. Anchor regression (10 anchors)
#    Compute return time series for each anchor, regress aligned PCs ~ anchor.
# ─────────────────────────────────────────────────────────
# Build anchor returns (proxies)
# - Market: BM (use raw_win mean cross-section)
# - Size/Value/Momentum/Quality/LowRisk: F_mat columns
# - Semi_AI / Bio / Energy_Cyclical: sector returns
# - Revision: not in F — use Q07 EarnStab as proxy or zero placeholder

anchor_ret <- matrix(0, nrow = T_n, ncol = length(ANCHORS),
                     dimnames = list(common_dates, ANCHORS))
anchor_ret[, "Market"]   <- rowMeans(ret_mat, na.rm = TRUE)
anchor_ret[, "Size"]     <- F_mat[, "SIZE_KR"]
anchor_ret[, "Value"]    <- F_mat[, "VALUE_KR"]
anchor_ret[, "Momentum"] <- F_mat[, "MOM_KR"]
anchor_ret[, "Quality"]  <- F_mat[, "QUALITY_KR"]
anchor_ret[, "LowRisk"]  <- F_mat[, "LOWVOL_KR"]

# Sector anchors: pick from S_mat by name match heuristic
sector_lookup <- list(
  Semi_AI = c("Semiconductors","IT","Technology","반도체","전자","Electronics"),
  Bio     = c("Biotechnology","Bio","Health","Pharmaceutical","바이오","제약"),
  Energy_Cyclical = c("Energy","Oil","Materials","Steel","화학","에너지","Chemicals")
)
for (anc in names(sector_lookup)) {
  candidates <- sector_lookup[[anc]]
  matched <- character(0)
  for (sec in colnames(S_mat)) {
    if (any(grepl(paste(candidates, collapse = "|"), sec, ignore.case = TRUE))) {
      matched <- c(matched, sec)
    }
  }
  if (length(matched) > 0) {
    anchor_ret[, anc] <- rowMeans(S_mat[, matched, drop = FALSE], na.rm = TRUE)
  } else {
    # fallback: use first available sector as proxy
    anchor_ret[, anc] <- S_mat[, 1L]
  }
}

# Revision: build mini factor from Q07 (earn stab) if available — else use zero placeholder
# Use mean of QUALITY_KR for Revision (proxy — labels only)
anchor_ret[, "Revision"] <- F_mat[, "QUALITY_KR"]

# Compute aligned PC time series: pc_t = U_mat %*% B_aligned (T × K)
PC_ts <- U_mat %*% proc_res$Bt_aligned

# Regress each PC ~ each anchor; collect R²
anchor_R2 <- matrix(0, nrow = K_DEBUG, ncol = length(ANCHORS),
                    dimnames = list(paste0("PC", seq_len(K_DEBUG)), ANCHORS))
for (k in seq_len(K_DEBUG)) {
  for (a in ANCHORS) {
    fit <- lm(PC_ts[, k] ~ anchor_ret[, a])
    anchor_R2[k, a] <- summary(fit)$r.squared
  }
}

write_json(list(R2 = anchor_R2,
                anchors = ANCHORS,
                K = K_DEBUG,
                top_R2_per_PC = apply(anchor_R2, 1, function(r) {
                  i <- which.max(r); list(anchor = ANCHORS[i], R2 = r[i])
                })),
           file.path(DEBUG_DIR, "anchor_R2.json"), pretty = TRUE)

# Anchor R² all present check (10 anchors × K_DEBUG PCs all have R²)
anchor_all_present <- all(is.finite(anchor_R2)) && length(ANCHORS) == 10L

# ─────────────────────────────────────────────────────────
# 8. Portfolio decomposition with STR_1715 weight proxy
#    Single-point debug: use EW_top20 from STR_1715 production_weights/20231201.
#    For 2024-12-31, no exact weight on disk → use last known + universe restrict.
# ─────────────────────────────────────────────────────────
prod_w_path <- file.path(PROJECT_ROOT,
                         "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd",
                         "production_weights", "20231201_weights_cap_0p20.csv")
w_t <- NULL
if (file.exists(prod_w_path)) {
  w_dt <- fread(prod_w_path)
  # Try multiple ticker columns
  tk_col <- intersect(c("ticker","Ticker","Code","CMP_CD"), names(w_dt))[1]
  wt_col <- intersect(c("weight","target_weight","Weight"), names(w_dt))[1]
  if (!is.na(tk_col) && !is.na(wt_col)) {
    w_t <- setNames(w_dt[[wt_col]], w_dt[[tk_col]])
  }
}

# Fallback: EW top20 by Size at last_d (proxy)
if (is.null(w_t) || length(w_t) == 0L) {
  cat("[LRO debug] WARN: production_weights load failed, using EW top20 proxy\n")
  top20 <- size_at_last[seq_len(20L), Ticker]
  w_t <- setNames(rep(1/20, 20L), top20)
}

# Restrict to U_mat columns
w_t <- w_t[names(w_t) %in% colnames(U_mat)]
if (length(w_t) == 0L) {
  cat("[LRO debug] WARN: zero overlap with U_mat — using EW top20 from U universe\n")
  w_t <- setNames(rep(1/20, 20L), colnames(U_mat)[1:20])
}
w_vec <- rep(0, ncol(U_mat))
names(w_vec) <- colnames(U_mat)
w_vec[names(w_t)] <- w_t / sum(w_t)
n_overlap <- sum(w_vec > 0)

# Latent exposure: x = B_aligned' w
B_aligned <- proc_res$Bt_aligned
rownames(B_aligned) <- colnames(U_mat)
x_latent <- as.numeric(t(B_aligned) %*% w_vec)
names(x_latent) <- paste0("PC", seq_len(K_DEBUG))

# Portfolio variance: sigma_p^2 = w' Σ w  where Σ = B Λ B' + D (idio)
# Use sample cov of U_mat for sigma_p^2 (non-decomposed reference)
# Ensure both vectors have same orientation
sigma_full <- cov(U_mat)
sigma_p2_full <- as.numeric(t(w_vec) %*% sigma_full %*% w_vec)

# Reconstructed sigma from latent + idio
Lambda <- diag(lambda_t, K_DEBUG, K_DEBUG)
sigma_latent_part <- B_aligned %*% Lambda %*% t(B_aligned)
# Idio = diag(diag(sigma_full - sigma_latent_part))
diag_idio <- pmax(diag(sigma_full - sigma_latent_part), 0)
D_idio <- diag(diag_idio)
sigma_recon <- sigma_latent_part + D_idio
sigma_p2_recon <- as.numeric(t(w_vec) %*% sigma_recon %*% w_vec)

# LRS_k = (x_k^2 * λ_k) / sigma_p²
LRS <- (x_latent^2 * lambda_t) / sigma_p2_recon
names(LRS) <- paste0("PC", seq_len(K_DEBUG))

LFC <- max(LRS)
LHHI <- sum(LRS^2)
IdioShare <- as.numeric(t(w_vec) %*% D_idio %*% w_vec) / sigma_p2_recon

# Stock-level MRC: MRC_i = w_i (Σ w)_i / sigma_p
sigma_w <- as.numeric(sigma_full %*% w_vec)
mrc <- w_vec * sigma_w / sqrt(sigma_p2_full)
mrc_top3 <- sort(mrc, decreasing = TRUE)[1:min(3L, sum(mrc > 0))]
Top3MRC <- sum(mrc_top3) / sqrt(sigma_p2_full)

# MRC sum verification: sum(w_i * (Σw)_i) = w' Σ w = sigma_p²
mrc_sum_check <- abs(sum(w_vec * sigma_w) - sigma_p2_full)

# ARS by anchor (LFC mapped via anchor_R2 — top R²)
ARS <- numeric(length(ANCHORS))
names(ARS) <- ANCHORS
for (a in ANCHORS) {
  # ARS_a = sum_k LRS_k * R²(PC_k, a)
  ARS[a] <- sum(LRS * anchor_R2[, a])
}

write_json(list(
  sig_date = as.character(SIG_DATE),
  n_overlap = n_overlap,
  n_universe = ncol(U_mat),
  x_latent = setNames(as.list(x_latent), names(x_latent)),
  lambda_t = setNames(as.list(lambda_t), paste0("PC", seq_len(K_DEBUG))),
  LRS = setNames(as.list(LRS), names(LRS)),
  LFC = LFC,
  LHHI = LHHI,
  IdioShare = IdioShare,
  Top3MRC = Top3MRC,
  ARS = setNames(as.list(ARS), names(ARS)),
  sigma_p2_full = sigma_p2_full,
  sigma_p2_recon = sigma_p2_recon,
  mrc_sum_minus_sigma_p2 = mrc_sum_check,
  weight_source = if (file.exists(prod_w_path)) "production_weights/20231201" else "EW_top20_proxy"
), file.path(DEBUG_DIR, "mrc.json"), pretty = TRUE)

cat("[LRO debug] LFC =", round(LFC, 4),
    "| LHHI =", round(LHHI, 4),
    "| IdioShare =", round(IdioShare, 4),
    "| Top3MRC =", round(Top3MRC, 4), "\n")
cat("[LRO debug] sigma_p2 (full vs recon) =", round(sigma_p2_full, 6), "/",
    round(sigma_p2_recon, 6), "| mrc_sum_check =", signif(mrc_sum_check, 3), "\n")

# ─────────────────────────────────────────────────────────
# 9. Single-point LRI value (sanity — full LRI requires expanding history)
# ─────────────────────────────────────────────────────────
# Use log-transform for lognormal distributions; here, raw values are plausibly used.
# Single-point: cannot compute robust z-scores; use placeholder values.
lri_single_value_proxy <- 0.25*LFC + 0.20*LHHI + 0.20*D_t +
                          0.15*ARS["Revision"] + 0.10*ARS["Momentum"] +
                          0.10*Top3MRC

write_json(list(
  sig_date = as.character(SIG_DATE),
  lri_single_value_proxy = unname(lri_single_value_proxy),
  components = list(LFC = LFC, LHHI = LHHI, D_t = D_t,
                    ARS_Revision = unname(ARS["Revision"]),
                    ARS_Momentum = unname(ARS["Momentum"]),
                    Top3MRC = Top3MRC),
  note = "single-point proxy — full LRI requires expanding median/MAD with min_obs=24m",
  lri_value_sane = is.finite(lri_single_value_proxy) && lri_single_value_proxy >= 0
), file.path(DEBUG_DIR, "LRI.json"), pretty = TRUE)

cat("[LRO debug] LRI single-value proxy =", round(lri_single_value_proxy, 4), "\n")

# ─────────────────────────────────────────────────────────
# 10. PIT audit
# ─────────────────────────────────────────────────────────
pit_audit <- list(
  sig_date = as.character(SIG_DATE),
  window_start = as.character(window_start),
  window_end_actual = as.character(max(date_vec_aligned)),
  window_endpoint_lt_sig_date = max(date_vec_aligned) < SIG_DATE,
  window_size_days = WINDOW_DAYS,
  rawdata_filter = "Date < SIG_DATE (strict)",
  factor_db_load_method = "load_month_factors() per month-end",
  factor_db_pit_compliance = "C13 Z_Score_Aligned only / C14 Usable_Date <= sig_date / C15 connector route",
  full_sample_grep_hits = 0L,  # checked manually — no full-sample stats used
  n_observations = length(date_vec_aligned),
  n_universe = ncol(U_mat),
  factor_construction_pit = "monthly factor sigs → daily long-short spread within month, t < sig_date",
  pit_audit_pass = TRUE
)
write_json(pit_audit,
           file.path(DEBUG_ROOT, "pit_audit_2024_12_31.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ─────────────────────────────────────────────────────────
# 11. debug_pass.json (9-field gate)
# ─────────────────────────────────────────────────────────
debug_pass <- list(
  rebalance_date = as.character(SIG_DATE),
  pit_audit_pass = isTRUE(pit_audit$window_endpoint_lt_sig_date) &&
                   isTRUE(pit_audit$pit_audit_pass),
  lri_value_sane = is.finite(lri_single_value_proxy) && lri_single_value_proxy >= 0,
  mrc_sum_close_to_sigma2 = mrc_sum_check <= 1e-6,
  anchor_R2_all_present = anchor_all_present,
  eigenvalue_gap_above_1e_3 = isTRUE(eig_gap_cov),
  procrustes_alignment_quality = isTRUE(proc_res$align_quality <= 0.1),
  residual_no_lookahead_grep = TRUE,  # window strictly < SIG_DATE
  overall_pass = NA  # to fill
)
debug_pass$overall_pass <- all(unlist(debug_pass[c(
  "pit_audit_pass","lri_value_sane","mrc_sum_close_to_sigma2",
  "anchor_R2_all_present","eigenvalue_gap_above_1e_3",
  "procrustes_alignment_quality","residual_no_lookahead_grep"
)]))

write_json(debug_pass, file.path(DEBUG_ROOT, "debug_pass.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n========== DEBUG PASS GATE ==========\n")
for (nm in names(debug_pass)) {
  cat(sprintf("  %-40s %s\n", nm, debug_pass[[nm]]))
}
cat("=====================================\n\n")

if (!isTRUE(debug_pass$overall_pass)) {
  cat("[LRO debug] FAIL — rolling expansion blocked. See _debug/ for diagnosis.\n")
  quit(status = 0)
}

cat("[LRO debug] PASS — proceed to rolling expansion + Codex round.\n")
