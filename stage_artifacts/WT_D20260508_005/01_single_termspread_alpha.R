#==============================================================================
# WT-D20260508_005 — Step 1: Single KR Term Spread β alpha (no composite dilution)
#
# Goal: Inherit WT_004 macro_betas_monthly.parquet (PIT-strict 24M rolling β
#       on AR(1)-residual KR_TermSpread_d shocks) and build STANDALONE
#       single-factor alpha. No composite — direct test of WT_004's strongest
#       per-macro signal (|ICIR| 0.187, t_stat -2.62 vs raw cross-section IC).
#
# PIT contract (inherited from WT_004 Steps 1-3, audited):
#   - Predictor at month t = β_KR_TermSpread_d_{i, t-1} (lag-1 of rolling 24M β)
#   - Target = FwdRet_1M[t]  (return month t → t+1)
#   - Direction inferred via EXPANDING |IC| sign (≥12 obs burn-in)
#   - 6M EMA smoothing optional variant
#
# Outputs:
#   - alpha_panel_single.parquet (Ticker × ym × alpha_raw / alpha_smooth /
#     alpha_z / alpha_sn / FwdRet_1M / FwdRet_6M / FwdRet_12M)
#   - per_period_ic_single.csv
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SRC  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")  # inherit
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_005")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

cat("[01] WT-D20260508_005 single-macro KR_TermSpread_d alpha\n")
cat("[01] inheriting from WT_004 (PIT-clean): macro_betas_monthly + panel_monthly\n")

beta_dt <- as.data.table(read_parquet(file.path(SRC, "macro_betas_monthly.parquet")))
panel   <- as.data.table(read_parquet(file.path(SRC, "panel_monthly.parquet")))

# Keep only KR_TermSpread_d beta column
keep_cols <- c("Ticker", "ym", "beta_KR_TermSpread_d")
stopifnot(all(keep_cols %in% names(beta_dt)))
beta_dt <- beta_dt[, ..keep_cols]
setorder(beta_dt, Ticker, ym)

# ---- PIT lag-1 (predictor at month t = β at t-1) ----
beta_dt[, beta_lag1 := shift(beta_KR_TermSpread_d, 1L, type = "lag"), by = Ticker]

# ---- Merge with eligibility + forward returns ----
panel_use <- panel[!is.na(FwdRet_1M)]
mm <- merge(
  panel_use[, .(Ticker, ym, Date_eom, eligible, in_univ_eom, in_univ_lag1,
                FwdRet_1M, FwdRet_6M, FwdRet_12M, Sector, Size_eom, ADV20_lag1)],
  beta_dt[, .(Ticker, ym, beta_lag1)],
  by = c("Ticker", "ym"), all.x = TRUE)
setorder(mm, Ticker, ym)

# Eligibility filter (in_univ_lag1 + ADV20 ≥ 50M, post-2010 for burn-in coverage)
mm <- mm[eligible == TRUE & ym >= "2010-01"]
cat("[01] eligible rows post-2010:", nrow(mm),
    "ms:", uniqueN(mm$ym), "tk:", uniqueN(mm$Ticker), "\n")

# ---- Cross-section z-score per month (winsorize 3std → re-z) ----
mm[, beta_z := {
  x <- beta_lag1
  if (sum(!is.na(x)) >= 30) {
    mu <- mean(x, na.rm = TRUE); sd0 <- sd(x, na.rm = TRUE)
    if (is.na(sd0) || sd0 < 1e-12) return(rep(NA_real_, length(x)))
    x_w <- pmax(pmin(x, mu + 3*sd0), mu - 3*sd0)
    mu2 <- mean(x_w, na.rm = TRUE); sd2 <- sd(x_w, na.rm = TRUE)
    if (is.na(sd2) || sd2 < 1e-12) rep(0, length(x)) else (x_w - mu2) / sd2
  } else rep(NA_real_, length(x))
}, by = ym]

# ---- Per-period rank IC (raw beta_z direction) ----
ic_raw <- mm[!is.na(beta_z) & !is.na(FwdRet_1M),
             .(rank_ic = cor(beta_z, FwdRet_1M, method = "spearman", use = "complete.obs"),
               n = .N),
             by = ym]
setorder(ic_raw, ym)
overall_ic_raw <- mean(ic_raw$rank_ic, na.rm = TRUE)
overall_icir_raw <- overall_ic_raw / sd(ic_raw$rank_ic, na.rm = TRUE)
cat(sprintf("[01] raw IC mean = %.4f / ICIR = %.3f / n = %d\n",
            overall_ic_raw, overall_icir_raw, nrow(ic_raw)))

# ---- EXPANDING-WINDOW SIGN INFERENCE (PIT-safe direction) ----
# At month t, sign for predictor = sign of expanding mean IC over months 1..t-1
# Burn-in: 12 months minimum (<- per WT_004 internal note)
ic_raw_v <- ic_raw$rank_ic
months_v <- ic_raw$ym
n_p <- length(ic_raw_v)
sign_dir <- rep(NA_real_, n_p)
for (t in 2:n_p) {
  h <- ic_raw_v[1:(t-1)]
  h <- h[!is.na(h)]
  if (length(h) >= 12) sign_dir[t] <- sign(mean(h))
}
sign_dt <- data.table(ym = months_v, dir = sign_dir)

mm <- merge(mm, sign_dt, by = "ym", all.x = TRUE)
mm[, alpha_signed := ifelse(is.na(dir) | is.na(beta_z), NA_real_, dir * beta_z)]

# ---- Smoothing variants ----
ema_fn <- function(x, lambda_window) {
  lambda <- 2 / (lambda_window + 1)
  y <- rep(NA_real_, length(x)); s <- NA_real_
  for (i in seq_along(x)) {
    if (is.na(x[i])) { y[i] <- s; next }
    s <- if (is.na(s)) x[i] else (1 - lambda) * s + lambda * x[i]
    y[i] <- s
  }
  y
}
mm[, alpha_ema3  := ema_fn(alpha_signed, 3),  by = Ticker]
mm[, alpha_ema6  := ema_fn(alpha_signed, 6),  by = Ticker]
mm[, alpha_ema12 := ema_fn(alpha_signed, 12), by = Ticker]

# Re-z per month for each variant (so IC computation is invariant to scale)
re_z <- function(v) {
  if (sum(!is.na(v)) >= 20) {
    mu <- mean(v, na.rm = TRUE); sd0 <- sd(v, na.rm = TRUE)
    if (is.na(sd0) || sd0 < 1e-12) rep(0, length(v)) else (v - mu) / sd0
  } else rep(NA_real_, length(v))
}
mm[, alpha_signed_z := re_z(alpha_signed), by = ym]
mm[, alpha_ema3_z   := re_z(alpha_ema3),   by = ym]
mm[, alpha_ema6_z   := re_z(alpha_ema6),   by = ym]
mm[, alpha_ema12_z  := re_z(alpha_ema12),  by = ym]

# Sector-neutral alpha (using EMA6 as primary)
mm[, alpha_sn := alpha_ema6_z - mean(alpha_ema6_z, na.rm = TRUE), by = .(ym, Sector)]
mm[, alpha_sn := re_z(alpha_sn), by = ym]

# ---- Save panel ----
keep_out <- c("Ticker", "ym", "Date_eom", "Sector", "eligible",
              "beta_lag1", "beta_z",
              "alpha_signed", "alpha_signed_z",
              "alpha_ema3_z", "alpha_ema6_z", "alpha_ema12_z",
              "alpha_sn",
              "FwdRet_1M", "FwdRet_6M", "FwdRet_12M",
              "ADV20_lag1", "Size_eom")
write_parquet(mm[, ..keep_out], file.path(OUT, "alpha_panel_single.parquet"))

# ---- Quick IC summary across variants ----
variants <- list(
  raw_signed   = "alpha_signed_z",
  ema3         = "alpha_ema3_z",
  ema6         = "alpha_ema6_z",
  ema12        = "alpha_ema12_z",
  sector_neut  = "alpha_sn"
)

ic_summary <- list()
for (vn in names(variants)) {
  vc <- variants[[vn]]
  mm_v <- mm[!is.na(get(vc)) & !is.na(FwdRet_1M)]
  ic_v <- mm_v[, .(rank_ic = cor(get(vc), FwdRet_1M, method = "spearman", use = "complete.obs"),
                   n = .N),
               by = ym]
  setorder(ic_v, ym)
  ic_v <- ic_v[ym >= "2013-01"]  # burn-in past 36m
  if (nrow(ic_v) > 0) {
    icir_v <- mean(ic_v$rank_ic, na.rm = TRUE) / sd(ic_v$rank_ic, na.rm = TRUE)
    fwrite(ic_v, file.path(OUT, sprintf("per_period_ic_%s.csv", vn)))
    ic_summary[[vn]] <- data.table(
      variant = vn,
      ic_mean = mean(ic_v$rank_ic, na.rm = TRUE),
      ic_sd   = sd(ic_v$rank_ic, na.rm = TRUE),
      icir    = icir_v,
      n_periods = nrow(ic_v),
      hit_pos = mean(ic_v$rank_ic > 0, na.rm = TRUE),
      t_stat  = mean(ic_v$rank_ic, na.rm = TRUE) / (sd(ic_v$rank_ic, na.rm = TRUE) / sqrt(nrow(ic_v)))
    )
  }
}
ic_summary <- rbindlist(ic_summary, fill = TRUE)
fwrite(ic_summary, file.path(OUT, "ic_variant_summary.csv"))
cat("\n[01] IC summary across variants (post-2013, burn-in cleared):\n")
print(ic_summary)

# ---- Predictor lag-1 autocor (PIT-WT_001 lesson) ----
acf_dt <- mm[!is.na(alpha_ema6_z), .(Ticker, ym, alpha_ema6_z)]
setorder(acf_dt, Ticker, ym)
acf_dt[, alpha_lag1 := shift(alpha_ema6_z, 1L), by = Ticker]
acf_dt[, ym_num := as.integer(gsub("-", "", ym))]
acf_dt[, ym_lag := shift(ym_num, 1L), by = Ticker]
acf_dt[, gap_ok := (ym_num - ym_lag) %in% c(1, 89)]
acf_calc <- acf_dt[gap_ok == TRUE & !is.na(alpha_ema6_z) & !is.na(alpha_lag1)]
ac1 <- if (nrow(acf_calc) >= 100) cor(acf_calc$alpha_ema6_z, acf_calc$alpha_lag1) else NA_real_

# Also compute for non-smoothed signed (raw)
acf_raw <- mm[!is.na(alpha_signed_z), .(Ticker, ym, alpha_signed_z)]
setorder(acf_raw, Ticker, ym)
acf_raw[, alpha_lag1 := shift(alpha_signed_z, 1L), by = Ticker]
acf_raw[, ym_num := as.integer(gsub("-", "", ym))]
acf_raw[, ym_lag := shift(ym_num, 1L), by = Ticker]
acf_raw[, gap_ok := (ym_num - ym_lag) %in% c(1, 89)]
acf_raw_calc <- acf_raw[gap_ok == TRUE & !is.na(alpha_signed_z) & !is.na(alpha_lag1)]
ac1_raw <- if (nrow(acf_raw_calc) >= 100) cor(acf_raw_calc$alpha_signed_z, acf_raw_calc$alpha_lag1) else NA_real_

ac_diag <- list(
  raw_signed_z_lag1_autocor = if (is.na(ac1_raw)) NA else round(ac1_raw, 4),
  ema6_smoothed_lag1_autocor = if (is.na(ac1)) NA else round(ac1, 4),
  threshold_warn = 0.95,
  raw_status = if (is.na(ac1_raw)) "INSUFFICIENT_DATA"
               else if (ac1_raw > 0.95) "WARN_HIGH_AUTOCOR"
               else if (ac1_raw > 0.85) "MID_HIGH_NORMAL"
               else "OK",
  smoothed_status = if (is.na(ac1)) "INSUFFICIENT_DATA"
                    else if (ac1 > 0.95) "WARN_HIGH_AUTOCOR"
                    else if (ac1 > 0.85) "MID_HIGH_NORMAL_FOR_LONG_HORIZON"
                    else "OK",
  rationale_raw = "raw signed z (no smoothing) — autocor reflects underlying β persistence",
  rationale_smoothed = "EMA6 smoothing intentional for long-horizon design",
  n_pairs_raw = nrow(acf_raw_calc),
  n_pairs_smoothed = nrow(acf_calc),
  pit_check = "predictor uses β at t-1 (lag-1) — no current-month leak"
)
write_json(ac_diag, file.path(OUT, "predictor_autocor_diagnosis.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[01] predictor autocor: raw=%.3f / EMA6=%.3f\n",
            ac1_raw, ac1))

cat("\n[01] DONE. Best variant by ICIR will be selected in Step 2.\n")
