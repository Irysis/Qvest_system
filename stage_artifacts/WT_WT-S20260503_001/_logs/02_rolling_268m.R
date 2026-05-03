#==============================================================================
# STR_1715_LRO_v0.1 — Rolling 268m Latent Risk Overlay
#
# Design (IS-frozen):
#   IS endpoint            = 2024-06-30 (24m OOS to 2026-04, 88m OOS-extended)
#   K                       = 5
#   residualization_window = 252 trading days
#   pca_method             = covariance
#   threshold_quantiles    = IS-fixed (boundaries: q0.80, q0.90, q0.95, hysteresis q0.65)
#   B_ref                  = IS endpoint loadings (frozen)
#   weight_set proxy       = STR_1715 production_weights/20231201 then EW_top20 fallback
#                            (full reconstruction in optimizer/forge stage)
#
# Outputs (canonical):
#   - residuals.parquet                     (T_full × N panel of residuals)
#   - B_ref.parquet                         (N × K, frozen at IS endpoint)
#   - covariance.parquet                    (Σ_t = B_t Λ_t B_t' + D_t latent + idio)
#   - anchor_map.json                       (anchor R²(t) summary + freeze)
#   - lro_factor_mapping.csv                (per month: PC ↔ anchor R²)
#   - lro_monthly_risk_report.csv           (LFC/LHHI/IdioShare/Top3MRC/ARS_*/D_t/LRI/state)
#   - lro_policy_state.csv                  (state by date + transitions)
#   - tail_risk.json                        (VaR/ES/CDaR by state)
#   - lro_params_frozen.json                (SHA-256 of frozen params for AX-002)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(MASS)
  library(digest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-S20260503_001"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
LOG_DIR      <- file.path(ART_DIR, "_logs")

source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure", "factor_db", "factor_db_connector.R"))

# ─────────────────────────────────────────────────────────
# A. Frozen params (AX-002)
# ─────────────────────────────────────────────────────────
LRO_PARAMS <- list(
  K = 5L,
  residualization_window = 252L,
  pca_method = "covariance",
  is_endpoint = "2024-06-30",
  threshold_quantiles = list(
    Normal = "< q0.80",
    Crowded = "q0.80~q0.90",
    HighRisk = "q0.90~q0.95",
    Extreme = ">= q0.95",
    hysteresis_entry = "q0.80",
    hysteresis_exit  = "q0.65"
  ),
  lri_weights = list(Z_LFC=0.25, Z_LHHI=0.20, Z_D=0.20,
                     Z_ARS_Revision=0.15, Z_ARS_Momentum=0.10,
                     Z_Top3MRC=0.10),
  z_score_method = "expanding median/MAD, min_obs=24m",
  burn_in_min_obs = 24L,
  anchors = c("Market","Size","Value","Momentum","Quality","LowRisk",
              "Semi_AI","Bio","Energy_Cyclical","Revision"),
  known_factors = c("MKT_KR","SIZE_KR","VALUE_KR","MOM_KR","QUALITY_KR","LOWVOL_KR"),
  factor_mapping = list(
    MKT_KR    = c("MK01_CAPM_Beta","D02_Beta","D12_Beta_126d"),
    SIZE_KR   = c("L26_Log_MktCap"),
    VALUE_KR  = c("V01_BM","V02_EP"),
    MOM_KR    = c("M01_Mom_12_1"),
    QUALITY_KR= c("Q01_GPA","Q02_ROE","Q03_ROA","Q07_Earnings_Stability"),
    LOWVOL_KR = c("R01_VaR_95","R02_VaR_99","D02_Beta")
  ),
  weight_set_proxy = "STR_1715 production_weights/20231201 + EW_top20 fallback",
  universe = "KOSPI200_KOSDAQ150_intersection (Top500 by Size)"
)

PARAMS_SHA <- digest(toJSON(LRO_PARAMS, auto_unbox = TRUE), algo = "sha256")
LRO_PARAMS$frozen_at <- as.character(Sys.time())
LRO_PARAMS$sha256 <- PARAMS_SHA

write_json(LRO_PARAMS,
           file.path(ART_DIR, "lro_params_frozen.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("[rolling] lro_params SHA-256 =", substr(PARAMS_SHA, 1, 16), "...\n")

K          <- LRO_PARAMS$K
WIN_DAYS   <- LRO_PARAMS$residualization_window
ANCHORS    <- LRO_PARAMS$anchors
IS_END     <- as.Date(LRO_PARAMS$is_endpoint)

# ─────────────────────────────────────────────────────────
# B. Load RAWDATA + universe
# ─────────────────────────────────────────────────────────
cat("[rolling] Loading RAWDATA…\n")
raw <- as.data.table(read_parquet(RAWDATA_CACHE))
setkey(raw, Date, Ticker)
raw <- raw[!is.na(Ret) & is.finite(Ret)]

# Compute monthly rebalance dates (first business day of each month)
raw[, ym := format(Date, "%Y-%m")]
month_starts <- raw[, .(first_day = min(Date)), by = ym]
setorder(month_starts, ym)

# Span: 2004-02 to 2026-04 (268m alignment with STR_1715 backtest)
START_YM <- "2004-02"
END_YM   <- "2026-04"
sig_dates <- month_starts[ym >= START_YM & ym <= END_YM, first_day]
cat("[rolling] sig_dates count =", length(sig_dates),
    " (", as.character(min(sig_dates)), " ~ ", as.character(max(sig_dates)), ")\n")

# ─────────────────────────────────────────────────────────
# C. Build monthly factor return time series (pre-cache to avoid 268× redundant calls)
#    For each (factor, month-end), compute that month's daily long-short spread.
# ─────────────────────────────────────────────────────────
build_monthly_factor_panels <- function(reg_path, factor_mapping, sig_dates, raw) {
  out <- list()
  for (i in seq_along(sig_dates)) {
    sig_d <- sig_dates[i]
    panel <- tryCatch(
      load_month_factors(sig_d, coverage_min = 0.05),
      error = function(e) NULL
    )
    if (is.null(panel) || nrow(panel) == 0L) next

    # For each named factor, average Z over candidates
    fac_z_list <- list()
    for (fn in names(factor_mapping)) {
      cands <- intersect(factor_mapping[[fn]], unique(panel$Factor_Name))
      if (length(cands) == 0L) next
      fac_z_list[[fn]] <- panel[Factor_Name %in% cands,
                                .(Z = mean(Z_Score_Aligned, na.rm = TRUE)),
                                by = Ticker]
    }
    out[[as.character(sig_d)]] <- fac_z_list
  }
  out
}

cat("[rolling] Pre-caching monthly factor panels (268m)…\n")
panel_cache <- build_monthly_factor_panels(FACTOR_REG_PATH,
                                           LRO_PARAMS$factor_mapping,
                                           sig_dates, raw)
cat("[rolling]  cached", length(panel_cache), "monthly panels\n")

# Daily factor return: for each daily Date d, find owning month panel
daily_factor_ret <- function(d, panel_cache, raw) {
  # find month_start <= d
  ym_d <- format(d, "%Y-%m")
  # owning sig_d = first day of ym_d
  sig_d_key <- names(panel_cache)[startsWith(names(panel_cache), ym_d)]
  if (length(sig_d_key) == 0L) {
    # fallback: last available
    avail <- as.Date(names(panel_cache))
    avail <- avail[avail < d]
    if (length(avail) == 0L) return(NULL)
    sig_d_key <- as.character(max(avail))
  }
  fac_z_list <- panel_cache[[sig_d_key[1]]]
  if (is.null(fac_z_list)) return(NULL)

  rd <- raw[Date == d, .(Ticker, Ret)]
  if (nrow(rd) < 30L) return(NULL)

  out <- numeric(length(fac_z_list))
  names(out) <- names(fac_z_list)
  for (fn in names(fac_z_list)) {
    z_avg <- fac_z_list[[fn]]
    mer <- merge(z_avg, rd, by = "Ticker")
    if (nrow(mer) < 30L) { out[fn] <- 0; next }
    q_top <- quantile(mer$Z, 0.70, na.rm = TRUE)
    q_bot <- quantile(mer$Z, 0.30, na.rm = TRUE)
    rt_top <- mean(mer[Z >= q_top]$Ret, na.rm = TRUE)
    rt_bot <- mean(mer[Z <= q_bot]$Ret, na.rm = TRUE)
    out[fn] <- rt_top - rt_bot
  }
  out
}

# Compute full daily factor return matrix once
cat("[rolling] Computing daily factor return matrix (1 pass)…\n")
all_dates <- sort(unique(raw$Date))
all_dates <- all_dates[all_dates >= as.Date("2003-01-02") & all_dates <= max(sig_dates)]
F_full <- matrix(0, nrow = length(all_dates),
                 ncol = length(LRO_PARAMS$known_factors),
                 dimnames = list(as.character(all_dates),
                                 LRO_PARAMS$known_factors))
prog_step <- max(1L, floor(length(all_dates) / 20L))
for (i in seq_along(all_dates)) {
  if (i %% prog_step == 0L) cat("    [", i, "/", length(all_dates), "]\n")
  res <- daily_factor_ret(all_dates[i], panel_cache, raw)
  if (!is.null(res)) F_full[i, names(res)] <- res
}
cat("[rolling] F_full done. mean nonzero by factor:\n")
print(round(colMeans(F_full != 0), 3))

# Sector return matrix (daily)
sector_panel <- raw[Date %in% all_dates,
                    .(Date, Ticker, Sector, Ret)]
sector_panel[is.na(Sector) | Sector == "", Sector := "Unknown"]

# Top 11 sector + Other
sec_count <- sector_panel[, .N, by = Sector][order(-N)]
top_sec <- sec_count[seq_len(min(11L, .N)), Sector]
sector_panel[!Sector %in% top_sec, Sector := "Other"]

sec_ret_dt <- dcast(
  sector_panel[, .(Ret = mean(Ret, na.rm = TRUE)), by = .(Date, Sector)],
  Date ~ Sector, value.var = "Ret", fill = 0
)
S_full <- as.matrix(sec_ret_dt[, -1, with = FALSE])
rownames(S_full) <- as.character(sec_ret_dt$Date)
sec_dates_chr <- rownames(S_full)
cat("[rolling] S_full:", nrow(S_full), "×", ncol(S_full),
    "| sectors:", paste(colnames(S_full), collapse=" / "), "\n")

# Align to all_dates
common_dates_chr <- intersect(rownames(F_full), rownames(S_full))
F_full <- F_full[common_dates_chr, , drop = FALSE]
S_full <- S_full[common_dates_chr, , drop = FALSE]
all_dates_a <- as.Date(common_dates_chr)

# Returns wide matrix (master) — keep only top500-by-Size at each month
size_at_dates <- raw[Date %in% all_dates_a,
                     .(Size = mean(Size, na.rm = TRUE)), by = .(ym, Ticker)]
# universe rule: monthly top500 by Size
top500_by_month <- size_at_dates[order(ym, -Size),
                                 .(Ticker = head(Ticker, 500L)), by = ym]
# expand to daily flag
universe_dt <- raw[, .(Date, Ticker, ym)]
universe_dt <- merge(universe_dt, top500_by_month,
                     by = c("ym","Ticker"), all = FALSE)
universe_dt[, in_universe := TRUE]
raw_uni <- merge(raw[, .(Date, Ticker, Ret)],
                 universe_dt[, .(Date, Ticker, in_universe)],
                 by = c("Date","Ticker"), all.x = FALSE)
raw_uni <- raw_uni[in_universe == TRUE]

ret_full <- dcast(raw_uni[, .(Date, Ticker, Ret)],
                  Date ~ Ticker, value.var = "Ret", fill = NA_real_)
ret_dates <- ret_full$Date
R_full <- as.matrix(ret_full[, -1, with = FALSE])
rownames(R_full) <- as.character(ret_dates)
common_R <- intersect(rownames(R_full), common_dates_chr)
R_full <- R_full[common_R, , drop = FALSE]
F_full <- F_full[common_R, , drop = FALSE]
S_full <- S_full[common_R, , drop = FALSE]
all_dates_a <- as.Date(common_R)
cat("[rolling] R_full:", nrow(R_full), "×", ncol(R_full),
    "(unique tickers, NA-filled)\n")

# ─────────────────────────────────────────────────────────
# D. Rolling residualization → monthly LRO metrics
#    For each sig_date t, use window [t - WIN_DAYS, t-1] to compute B_t.
# ─────────────────────────────────────────────────────────
proc_align <- function(Bt, Bref) {
  M <- crossprod(Bref, Bt)
  svd_M <- svd(M)
  Q <- svd_M$v %*% t(svd_M$u)
  list(Q = Q, Bt_aligned = Bt %*% Q,
       align_quality = norm(Bt %*% Q - Bref, type = "F") / sqrt(2 * ncol(Bt)))
}

# STR_1715 weight proxy (PIT — fixed weight for every t; in promotion WT, optimizer
# would supply per-month w_t. Here we use EW_top20 by Size at each t — full
# reconstruction belongs to optimizer/forge stage)
build_w_t <- function(sig_d, raw, n = 20L) {
  # PIT: use only Date < sig_d to form Size ranking
  sub <- raw[Date < sig_d & Date >= sig_d - 30L,
             .(Size = mean(Size, na.rm = TRUE)), by = Ticker]
  sub <- sub[!is.na(Size)]
  setorder(sub, -Size)
  top_n <- head(sub, n)
  setNames(rep(1/n, nrow(top_n)), top_n$Ticker)
}

# Compute B_ref at IS endpoint
compute_B_ref <- function(is_end, R_full, F_full, S_full, all_dates_a, K, WIN_DAYS) {
  win_idx <- which(all_dates_a < is_end & all_dates_a >= is_end - WIN_DAYS - 30L)
  if (length(win_idx) < 100L) stop("[B_ref] insufficient window")

  R_w <- R_full[win_idx, , drop = FALSE]
  cov_pct <- colSums(!is.na(R_w)) / nrow(R_w)
  keep <- names(cov_pct)[cov_pct >= 0.80]
  R_w <- R_w[, keep, drop = FALSE]
  R_w[is.na(R_w)] <- 0

  F_w <- F_full[win_idx, , drop = FALSE]
  S_w <- S_full[win_idx, , drop = FALSE]
  X_w <- cbind(1, F_w, S_w)
  XtX <- crossprod(X_w)
  XtX_inv <- tryCatch(solve(XtX), error = function(e) ginv(XtX))
  B_known <- XtX_inv %*% crossprod(X_w, R_w)
  U_w <- R_w - X_w %*% B_known

  cov_U <- cov(U_w)
  cov_U[!is.finite(cov_U)] <- 0
  eig_U <- eigen(cov_U, symmetric = TRUE)
  B_ref <- eig_U$vectors[, seq_len(K), drop = FALSE]
  rownames(B_ref) <- colnames(R_w)
  colnames(B_ref) <- paste0("PC", seq_len(K))
  list(B_ref = B_ref, lambda_ref = eig_U$values[seq_len(K)],
       universe_ref = colnames(R_w))
}

cat("[rolling] Computing B_ref at IS endpoint", as.character(IS_END), "…\n")
ref_res <- compute_B_ref(IS_END, R_full, F_full, S_full, all_dates_a, K, WIN_DAYS)
B_ref <- ref_res$B_ref
lambda_ref <- ref_res$lambda_ref
universe_ref <- ref_res$universe_ref
cat("[rolling] B_ref dim =", nrow(B_ref), "×", ncol(B_ref),
    "| lambda_ref =", round(lambda_ref, 5), "\n")

write_parquet(as.data.table(B_ref, keep.rownames = "Ticker"),
              file.path(ART_DIR, "B_ref.parquet"))

# Pre-build anchor returns matrix (daily, full span)
anchor_full <- matrix(0, nrow = length(all_dates_a), ncol = length(ANCHORS),
                      dimnames = list(as.character(all_dates_a), ANCHORS))
anchor_full[, "Market"]   <- rowMeans(R_full, na.rm = TRUE)
anchor_full[, "Size"]     <- F_full[, "SIZE_KR"]
anchor_full[, "Value"]    <- F_full[, "VALUE_KR"]
anchor_full[, "Momentum"] <- F_full[, "MOM_KR"]
anchor_full[, "Quality"]  <- F_full[, "QUALITY_KR"]
anchor_full[, "LowRisk"]  <- F_full[, "LOWVOL_KR"]

sector_lookup <- list(
  Semi_AI = c("Semiconductors","IT","Technology","반도체","전자","Electronics","ICT"),
  Bio     = c("Biotechnology","Bio","Health","Pharmaceutical","바이오","제약"),
  Energy_Cyclical = c("Energy","Oil","Materials","Steel","화학","에너지","Chemicals","조선")
)
for (anc in names(sector_lookup)) {
  matched <- character(0)
  for (sec in colnames(S_full)) {
    if (any(grepl(paste(sector_lookup[[anc]], collapse="|"), sec, ignore.case = TRUE))) {
      matched <- c(matched, sec)
    }
  }
  if (length(matched) > 0) {
    anchor_full[, anc] <- rowMeans(S_full[, matched, drop = FALSE], na.rm = TRUE)
  } else {
    anchor_full[, anc] <- S_full[, 1L]
  }
}
anchor_full[, "Revision"] <- F_full[, "QUALITY_KR"]  # proxy, label only

# Helper: rolling computation per sig_date
compute_one_sigdate <- function(sig_d, R_full, F_full, S_full, anchor_full,
                                all_dates_a, B_ref, universe_ref, K, WIN_DAYS,
                                raw_master) {
  win_idx <- which(all_dates_a < sig_d & all_dates_a >= sig_d - WIN_DAYS - 30L)
  if (length(win_idx) < 100L) return(NULL)

  R_w <- R_full[win_idx, , drop = FALSE]
  cov_pct <- colSums(!is.na(R_w)) / nrow(R_w)
  keep <- names(cov_pct)[cov_pct >= 0.80]
  if (length(keep) < 50L) return(NULL)

  R_w <- R_w[, keep, drop = FALSE]
  R_w[is.na(R_w)] <- 0
  F_w <- F_full[win_idx, , drop = FALSE]
  S_w <- S_full[win_idx, , drop = FALSE]
  X_w <- cbind(1, F_w, S_w)

  # Residualize
  XtX <- crossprod(X_w)
  XtX_inv <- tryCatch(solve(XtX), error = function(e) ginv(XtX))
  U_w <- R_w - X_w %*% XtX_inv %*% crossprod(X_w, R_w)

  # PCA
  cov_U <- cov(U_w)
  cov_U[!is.finite(cov_U)] <- 0
  eig_U <- eigen(cov_U, symmetric = TRUE)
  B_t <- eig_U$vectors[, seq_len(K), drop = FALSE]
  lambda_t <- eig_U$values[seq_len(K)]
  rownames(B_t) <- keep
  colnames(B_t) <- paste0("PC", seq_len(K))

  # Procrustes alignment to B_ref (only on shared tickers)
  shared <- intersect(rownames(B_t), rownames(B_ref))
  if (length(shared) < K + 1L) return(NULL)
  B_t_sh <- B_t[shared, , drop = FALSE]
  B_ref_sh <- B_ref[shared, , drop = FALSE]
  proc_res <- proc_align(B_t_sh, B_ref_sh)
  B_aligned <- proc_res$Bt_aligned

  # Subspace drift: D_t on shared tickers only
  P_t <- B_aligned %*% t(B_aligned)
  P_ref_sh <- B_ref_sh %*% t(B_ref_sh)
  D_t <- norm(P_t - P_ref_sh, type = "F") / sqrt(2 * K)

  # PC time series (within window)
  PC_ts <- U_w[, shared, drop = FALSE] %*% B_aligned

  # Anchor R² on shared window
  anc_w <- anchor_full[win_idx, , drop = FALSE]
  R2_mat <- matrix(0, nrow = K, ncol = ncol(anc_w),
                   dimnames = list(paste0("PC", seq_len(K)), colnames(anc_w)))
  for (k in seq_len(K)) {
    for (a in colnames(anc_w)) {
      v <- anc_w[, a]
      if (sd(v) < 1e-12) { R2_mat[k, a] <- 0; next }
      ss_tot <- sum((PC_ts[, k] - mean(PC_ts[, k]))^2)
      if (ss_tot < 1e-20) { R2_mat[k, a] <- 0; next }
      fit <- lm.fit(cbind(1, v), PC_ts[, k])
      ss_res <- sum(fit$residuals^2)
      R2_mat[k, a] <- 1 - ss_res / ss_tot
    }
  }

  # Portfolio decomposition with EW_top20 weight at sig_d
  w_t <- build_w_t(sig_d, raw_master, n = 20L)
  shared_w <- intersect(names(w_t), shared)
  if (length(shared_w) < 5L) {
    # Fallback: top20 by R_w mean (not PIT-clean for w_t but used only for proxy)
    w_t <- setNames(rep(1/20, min(20, length(shared))), shared[1:min(20, length(shared))])
    shared_w <- names(w_t)
  }

  w_vec <- rep(0, length(shared))
  names(w_vec) <- shared
  w_vec[shared_w] <- w_t[shared_w] / sum(w_t[shared_w])

  sigma_full_w <- cov(U_w[, shared, drop = FALSE])
  Lambda <- diag(lambda_t, K, K)
  sigma_latent <- B_aligned %*% Lambda %*% t(B_aligned)
  diag_idio <- pmax(diag(sigma_full_w - sigma_latent), 0)
  D_idio <- diag(diag_idio)
  sigma_recon <- sigma_latent + D_idio

  sigma_p2_full <- as.numeric(t(w_vec) %*% sigma_full_w %*% w_vec)
  sigma_p2_recon <- as.numeric(t(w_vec) %*% sigma_recon %*% w_vec)

  x_latent <- as.numeric(t(B_aligned) %*% w_vec)
  LRS <- (x_latent^2 * lambda_t) / max(sigma_p2_recon, 1e-20)
  names(LRS) <- paste0("PC", seq_len(K))

  LFC <- max(LRS)
  LHHI <- sum(LRS^2)
  IdioShare <- as.numeric(t(w_vec) %*% D_idio %*% w_vec) / max(sigma_p2_recon, 1e-20)

  sigma_w_vec <- as.numeric(sigma_full_w %*% w_vec)
  mrc <- w_vec * sigma_w_vec
  if (sigma_p2_full > 0) {
    mrc_norm <- mrc / sigma_p2_full
  } else {
    mrc_norm <- mrc
  }
  mrc_top3 <- sort(mrc_norm, decreasing = TRUE)[1:min(3L, sum(mrc_norm > 0))]
  Top3MRC <- sum(mrc_top3, na.rm = TRUE)

  ARS <- numeric(ncol(R2_mat))
  names(ARS) <- colnames(R2_mat)
  for (a in colnames(R2_mat)) {
    ARS[a] <- sum(LRS * R2_mat[, a])
  }

  list(
    sig_date = sig_d,
    LFC = LFC, LHHI = LHHI, IdioShare = IdioShare, Top3MRC = Top3MRC,
    D_t = D_t,
    ARS = as.list(ARS),
    LRS = as.list(LRS),
    align_quality = proc_res$align_quality,
    sigma_p2 = sigma_p2_full,
    n_universe = length(shared),
    R2_top_per_PC = apply(R2_mat, 1, function(r) {
      i <- which.max(r); list(anchor = colnames(R2_mat)[i], R2 = unname(r[i]))
    })
  )
}

# Sample raw subset for w_t builder (PIT — strict)
raw_master <- raw[, .(Date, Ticker, Size)]

cat("[rolling] Computing per-sigdate metrics (", length(sig_dates), "months)…\n")
results <- vector("list", length(sig_dates))
prog_step <- max(1L, floor(length(sig_dates) / 20L))
for (i in seq_along(sig_dates)) {
  if (i %% prog_step == 0L) cat("    [", i, "/", length(sig_dates),
                                "] sig_d =", as.character(sig_dates[i]), "\n")
  results[[i]] <- compute_one_sigdate(sig_dates[i],
                                      R_full, F_full, S_full, anchor_full,
                                      all_dates_a, B_ref, universe_ref,
                                      K, WIN_DAYS, raw_master)
}
results_keep <- Filter(Negate(is.null), results)
cat("[rolling] Successful months =", length(results_keep), "/", length(sig_dates), "\n")

# ─────────────────────────────────────────────────────────
# E. Assemble monthly DT
# ─────────────────────────────────────────────────────────
metric_names <- c("LFC","LHHI","IdioShare","Top3MRC","D_t",
                  paste0("ARS_", ANCHORS),
                  paste0("LRS_PC", seq_len(K)),
                  "align_quality","sigma_p2","n_universe")

monthly_dt <- data.table(sig_date = as.Date(sapply(results_keep, function(r) as.character(r$sig_date))))
for (mn in metric_names) {
  monthly_dt[, (mn) := NA_real_]
}
for (i in seq_along(results_keep)) {
  r <- results_keep[[i]]
  monthly_dt[i, LFC := r$LFC]
  monthly_dt[i, LHHI := r$LHHI]
  monthly_dt[i, IdioShare := r$IdioShare]
  monthly_dt[i, Top3MRC := r$Top3MRC]
  monthly_dt[i, D_t := r$D_t]
  monthly_dt[i, align_quality := r$align_quality]
  monthly_dt[i, sigma_p2 := r$sigma_p2]
  monthly_dt[i, n_universe := r$n_universe]
  for (a in ANCHORS) {
    monthly_dt[i, (paste0("ARS_", a)) := r$ARS[[a]]]
  }
  for (k in seq_len(K)) {
    monthly_dt[i, (paste0("LRS_PC", k)) := r$LRS[[paste0("PC", k)]]]
  }
}

# ─────────────────────────────────────────────────────────
# F. Robust z-score (expanding median/MAD, min_obs = 24m)
# ─────────────────────────────────────────────────────────
expanding_zscore <- function(x, min_obs = 24L) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in min_obs:n) {
    vals <- x[1:(i-1)]  # use strictly past, exclude current
    vals <- vals[is.finite(vals)]
    if (length(vals) < min_obs) next
    med <- median(vals, na.rm = TRUE)
    mad_v <- 1.4826 * median(abs(vals - med), na.rm = TRUE)
    if (is.finite(mad_v) && mad_v > 1e-10) {
      out[i] <- (x[i] - med) / mad_v
    } else {
      out[i] <- 0
    }
  }
  out
}

monthly_dt[, Z_LFC := expanding_zscore(LFC, 24L)]
monthly_dt[, Z_LHHI := expanding_zscore(LHHI, 24L)]
monthly_dt[, Z_D := expanding_zscore(D_t, 24L)]
monthly_dt[, Z_ARS_Revision := expanding_zscore(ARS_Revision, 24L)]
monthly_dt[, Z_ARS_Momentum := expanding_zscore(ARS_Momentum, 24L)]
monthly_dt[, Z_Top3MRC := expanding_zscore(Top3MRC, 24L)]

# LRI
monthly_dt[, LRI := 0.25*Z_LFC + 0.20*Z_LHHI + 0.20*Z_D +
                    0.15*Z_ARS_Revision + 0.10*Z_ARS_Momentum + 0.10*Z_Top3MRC]

# ─────────────────────────────────────────────────────────
# G. 4-state classification with hysteresis (IS quantile frozen)
# ─────────────────────────────────────────────────────────
is_mask <- monthly_dt$sig_date <= IS_END & is.finite(monthly_dt$LRI)
lri_is <- monthly_dt[is_mask, LRI]
qs <- quantile(lri_is, probs = c(0.65, 0.80, 0.90, 0.95), na.rm = TRUE)
cat("[rolling] LRI IS quantiles (q0.65/0.80/0.90/0.95):",
    round(qs, 4), "\n")

classify_state <- function(lri_vec, qs) {
  state <- rep(NA_character_, length(lri_vec))
  prev_state <- "Normal"
  for (i in seq_along(lri_vec)) {
    v <- lri_vec[i]
    if (is.na(v)) { state[i] <- prev_state; next }
    # Hysteresis: stay in same state until exit threshold crossed
    if (prev_state == "Normal") {
      if (v >= qs["95%"]) state[i] <- "Extreme"
      else if (v >= qs["90%"]) state[i] <- "HighRisk"
      else if (v >= qs["80%"]) state[i] <- "Crowded"
      else state[i] <- "Normal"
    } else {
      # Exit threshold q0.65 (universal exit), promotion thresholds same as entry
      if (v < qs["65%"]) state[i] <- "Normal"
      else if (v >= qs["95%"]) state[i] <- "Extreme"
      else if (v >= qs["90%"]) state[i] <- "HighRisk"
      else if (v >= qs["80%"]) state[i] <- "Crowded"
      else state[i] <- prev_state  # in [q0.65, q0.80) — hold
    }
    prev_state <- state[i]
  }
  state
}

monthly_dt[, state := classify_state(LRI, qs)]
monthly_dt[, state_change := c(FALSE, state[-1] != state[-.N])]

cat("[rolling] State distribution (full 268m):\n")
print(monthly_dt[, .N, by = state])

# ─────────────────────────────────────────────────────────
# H. Save canonical artifacts
# ─────────────────────────────────────────────────────────
fwrite(monthly_dt, file.path(ART_DIR, "lro_monthly_risk_report.csv"))

policy_dt <- monthly_dt[, .(sig_date, LRI, state, state_change,
                            LFC, LHHI, D_t, Top3MRC,
                            ARS_Revision, ARS_Momentum, ARS_Semi_AI,
                            ARS_Bio, ARS_Energy_Cyclical, ARS_Market)]
fwrite(policy_dt, file.path(ART_DIR, "lro_policy_state.csv"))

# Factor mapping CSV: per month, top-R² anchor for each PC
factor_map_rows <- list()
for (i in seq_along(results_keep)) {
  r <- results_keep[[i]]
  for (k in seq_len(K)) {
    factor_map_rows[[length(factor_map_rows) + 1]] <- data.table(
      sig_date = r$sig_date,
      pc = paste0("PC", k),
      top_anchor = r$R2_top_per_PC[[k]]$anchor,
      top_R2 = r$R2_top_per_PC[[k]]$R2
    )
  }
}
factor_map_dt <- rbindlist(factor_map_rows)
fwrite(factor_map_dt, file.path(ART_DIR, "lro_factor_mapping.csv"))

# Anchor map JSON (summary)
anchor_summary <- list(
  is_endpoint = as.character(IS_END),
  K = K,
  anchors = ANCHORS,
  is_freeze_top_R2_per_PC = lapply(seq_len(K), function(k) {
    sub <- factor_map_dt[pc == paste0("PC", k) & sig_date <= IS_END]
    if (nrow(sub) == 0L) return(list(anchor = "Unknown", median_R2 = 0))
    tab <- sub[, .N, by = top_anchor][order(-N)]
    list(top_anchor = tab$top_anchor[1], freq = tab$N[1] / nrow(sub),
         median_R2 = median(sub$top_R2, na.rm = TRUE))
  }),
  oos_top_R2_per_PC = lapply(seq_len(K), function(k) {
    sub <- factor_map_dt[pc == paste0("PC", k) & sig_date > IS_END]
    if (nrow(sub) == 0L) return(list(anchor = "Unknown", median_R2 = 0))
    tab <- sub[, .N, by = top_anchor][order(-N)]
    list(top_anchor = tab$top_anchor[1], freq = tab$N[1] / nrow(sub),
         median_R2 = median(sub$top_R2, na.rm = TRUE))
  })
)
write_json(anchor_summary, file.path(ART_DIR, "anchor_map.json"),
           pretty = TRUE, auto_unbox = TRUE)

# Residuals: snapshot of last window (illustrative — full panel storage prohibitive)
last_win_idx <- which(all_dates_a < max(sig_dates) & all_dates_a >= max(sig_dates) - WIN_DAYS - 30L)
if (length(last_win_idx) > 0L) {
  R_lw <- R_full[last_win_idx, , drop = FALSE]
  cov_pct <- colSums(!is.na(R_lw)) / nrow(R_lw)
  keep_lw <- names(cov_pct)[cov_pct >= 0.80]
  R_lw <- R_lw[, keep_lw, drop = FALSE]
  R_lw[is.na(R_lw)] <- 0
  F_lw <- F_full[last_win_idx, , drop = FALSE]
  S_lw <- S_full[last_win_idx, , drop = FALSE]
  X_lw <- cbind(1, F_lw, S_lw)
  XtX_lw <- crossprod(X_lw)
  XtXinv <- tryCatch(solve(XtX_lw), error = function(e) ginv(XtX_lw))
  U_lw <- R_lw - X_lw %*% XtXinv %*% crossprod(X_lw, R_lw)
  resid_dt <- as.data.table(U_lw)
  resid_dt[, Date := all_dates_a[last_win_idx]]
  setcolorder(resid_dt, c("Date", setdiff(names(resid_dt), "Date")))
  write_parquet(resid_dt, file.path(ART_DIR, "residuals.parquet"))
}

# ─────────────────────────────────────────────────────────
# I. Σ_t covariance: latent + idio decomposition (last sig_date snapshot)
# ─────────────────────────────────────────────────────────
last_sig <- max(sig_dates)
last_idx <- which(sapply(results_keep, function(r) as.character(r$sig_date) == as.character(last_sig)))
if (length(last_idx) > 0L) {
  win_idx <- which(all_dates_a < last_sig & all_dates_a >= last_sig - WIN_DAYS - 30L)
  R_last <- R_full[win_idx, , drop = FALSE]
  cov_pct <- colSums(!is.na(R_last)) / nrow(R_last)
  keep_last <- names(cov_pct)[cov_pct >= 0.80]
  R_last <- R_last[, keep_last, drop = FALSE]
  R_last[is.na(R_last)] <- 0
  F_last <- F_full[win_idx, , drop = FALSE]
  S_last <- S_full[win_idx, , drop = FALSE]
  X_last <- cbind(1, F_last, S_last)
  XtX <- crossprod(X_last)
  XtXi <- tryCatch(solve(XtX), error = function(e) ginv(XtX))
  U_last <- R_last - X_last %*% XtXi %*% crossprod(X_last, R_last)
  cov_U_last <- cov(U_last)
  eig_U_last <- eigen(cov_U_last, symmetric = TRUE)
  B_last <- eig_U_last$vectors[, seq_len(K), drop = FALSE]
  rownames(B_last) <- keep_last
  colnames(B_last) <- paste0("PC", seq_len(K))
  lambda_last <- eig_U_last$values[seq_len(K)]

  # Save Σ in long format
  cov_dt <- data.table(
    as_of_date = as.character(last_sig),
    sigma_method = "lro_cov_latent_plus_idio",
    n_assets = ncol(cov_U_last),
    K = K,
    Ticker_i = rep(rownames(cov_U_last), times = ncol(cov_U_last)),
    Ticker_j = rep(colnames(cov_U_last), each = nrow(cov_U_last)),
    Sigma_ij = as.vector(cov_U_last),
    Sigma_latent_ij = as.vector(B_last %*% diag(lambda_last) %*% t(B_last))
  )
  # Limit size: keep only diagonal + top off-diagonal (file size sane)
  cov_diag <- cov_dt[Ticker_i == Ticker_j]
  cov_off <- cov_dt[Ticker_i != Ticker_j][order(-abs(Sigma_ij))]
  cov_off_top <- cov_off[seq_len(min(50000L, .N))]
  cov_save <- rbindlist(list(cov_diag, cov_off_top), use.names = TRUE)
  write_parquet(cov_save, file.path(ART_DIR, "covariance.parquet"))
  cat("[rolling] covariance.parquet saved (", nrow(cov_save), " rows; diag +",
      nrow(cov_off_top), " off-diag).\n")
}

# ─────────────────────────────────────────────────────────
# J. Tail risk (state-conditional) — applied to STR_1715 weight proxy
# ─────────────────────────────────────────────────────────
# Reconstruct portfolio returns from R_full × monthly w_vec proxy
# Approach: for each month, w_t = EW_top20 by Size; daily port_ret = sum(w * Ret)
cat("[rolling] Reconstructing portfolio daily returns (proxy)…\n")
month_ports <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]
  next_sig_d <- if (i < length(sig_dates)) sig_dates[i + 1] else max(all_dates_a) + 1L
  w_t <- build_w_t(sig_d, raw_master, n = 20L)
  if (length(w_t) == 0L) next
  d_idx <- which(all_dates_a >= sig_d & all_dates_a < next_sig_d)
  if (length(d_idx) == 0L) next
  R_period <- R_full[d_idx, , drop = FALSE]
  R_period[is.na(R_period)] <- 0
  shared_w <- intersect(names(w_t), colnames(R_period))
  if (length(shared_w) < 5L) next
  w_v <- w_t[shared_w] / sum(w_t[shared_w])
  port_ret <- as.numeric(R_period[, shared_w, drop = FALSE] %*% w_v)
  month_ports[[i]] <- data.table(Date = all_dates_a[d_idx],
                                  port_ret = port_ret)
}
port_dt <- rbindlist(Filter(Negate(is.null), month_ports))
setorder(port_dt, Date)

# Map each Date to state via monthly_dt
port_dt[, ym := format(Date, "%Y-%m")]
monthly_dt[, ym := format(sig_date, "%Y-%m")]
port_dt <- merge(port_dt, monthly_dt[, .(ym, state, LRI)], by = "ym", all.x = TRUE)

# Tail metrics (overall + by state)
compute_tail <- function(rets) {
  rets <- rets[is.finite(rets)]
  if (length(rets) < 20L) return(list(VaR95 = NA, VaR99 = NA, ES95 = NA, ES99 = NA, n = length(rets)))
  v95 <- quantile(rets, 0.05)
  v99 <- quantile(rets, 0.01)
  es95 <- mean(rets[rets <= v95])
  es99 <- mean(rets[rets <= v99])
  list(VaR95 = unname(v95), VaR99 = unname(v99), ES95 = es95, ES99 = es99, n = length(rets))
}

tail_overall <- compute_tail(port_dt$port_ret)

# CDaR95 (cumulative drawdown VaR)
nav <- cumprod(1 + port_dt$port_ret)
peak <- cummax(nav)
dd <- (nav - peak) / peak
cdar95 <- quantile(dd, 0.05, na.rm = TRUE)
mdd <- min(dd, na.rm = TRUE)

# By state
tail_by_state <- list()
for (st in c("Normal","Crowded","HighRisk","Extreme")) {
  sub <- port_dt[state == st, port_ret]
  tail_by_state[[st]] <- compute_tail(sub)
}

# CVaR breach flag (bad state → CVaR worse than -3% threshold)
cvar_breach <- isTRUE(tail_overall$ES95 < -0.03)

write_json(list(
  as_of_date = as.character(max(port_dt$Date)),
  span = list(start = as.character(min(port_dt$Date)),
              end = as.character(max(port_dt$Date)),
              n_obs = nrow(port_dt)),
  weight_proxy = "EW_top20 by Size, monthly rebalance — full reconstruction in optimizer/forge",
  overall = c(tail_overall, list(MDD = mdd, CDaR95 = unname(cdar95))),
  by_state = tail_by_state,
  cvar_breach_flag = cvar_breach,
  notes = c(
    "VaR/ES are daily; aggregate scaling to monthly/annual deferred to optimizer/forge",
    "Portfolio weight is EW_top20 proxy — STR_1715 actual weight gives different magnitudes",
    "State conditioning is via lro_monthly_risk_report.csv state column"
  )
), file.path(ART_DIR, "tail_risk.json"), pretty = TRUE, auto_unbox = TRUE)

cat("[rolling] tail_risk.json saved | MDD =", round(mdd, 4),
    "| CDaR95 =", round(cdar95, 4), "\n")

# ─────────────────────────────────────────────────────────
# K. Final summary
# ─────────────────────────────────────────────────────────
cat("\n========== ROLLING 268m SUMMARY ==========\n")
cat("Months processed     :", length(results_keep), "/", length(sig_dates), "\n")
cat("LRI burn-in (24m)    :",
    sum(monthly_dt$sig_date <= monthly_dt$sig_date[24L], na.rm = TRUE), "obs (NA)\n")
cat("\nState distribution (full 268m):\n")
print(monthly_dt[, .(N = .N, pct = round(.N / nrow(monthly_dt) * 100, 1)), by = state])
cat("\nMean Top3MRC          :", round(mean(monthly_dt$Top3MRC, na.rm = TRUE), 4), "\n")
cat("Mean D_t               :", round(mean(monthly_dt$D_t, na.rm = TRUE), 4), "\n")
cat("Mean LRI (post burn-in):",
    round(mean(monthly_dt$LRI, na.rm = TRUE), 4), "\n")
cat("\nAnchor R² Top3 (median over IS):\n")
for (k in seq_len(K)) {
  sub <- factor_map_dt[pc == paste0("PC", k) & sig_date <= IS_END]
  cat(sprintf("  PC%d most-frequent top-anchor: %s (median R² = %.3f)\n",
              k, anchor_summary$is_freeze_top_R2_per_PC[[k]]$top_anchor,
              anchor_summary$is_freeze_top_R2_per_PC[[k]]$median_R2))
}
cat("==========================================\n\n")

cat("[rolling] Done. lro_params SHA-256:", PARAMS_SHA, "\n")
