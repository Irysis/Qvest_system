#==============================================================================
# WT-D20260508_004 — Step 4: Cross-Section IC + Composite Alpha (FIXED)
#
# Design (PIT-strict):
#   1. predictor at month t = β_{j,i,t-1}  (lag-1 of rolling 24M β)
#   2. target = FwdRet_1M[t] (return month t→t+1)
#   3. cross-section Spearman IC per (month, macro)
#   4. direction inference via EXPANDING IC mean (≥36 months burn-in)
#      Z_aligned = sign(IC_expanding_mean) × cross_section_z(β)
#   5. composite α̂_i,t = mean over top informative macros (selected expanding)
#   6. long-horizon smooth: 6M EMA on Z to dampen turnover
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(zoo); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")

cat("[04] loading β + panel …\n")
beta_dt <- as.data.table(read_parquet(file.path(OUT, "macro_betas_monthly.parquet")))
panel  <- as.data.table(read_parquet(file.path(OUT, "panel_monthly.parquet")))

beta_cols <- grep("^beta_", names(beta_dt), value = TRUE)

# Lag β by 1 month per ticker (PIT)
setorder(beta_dt, Ticker, ym)
for (bc in beta_cols) {
  beta_dt[, paste0(bc, "_lag1") := shift(get(bc), 1L, type="lag"), by = Ticker]
}
lag_cols <- paste0(beta_cols, "_lag1")

# Merge with panel forward returns + eligibility
panel_use <- panel[!is.na(FwdRet_1M)]
mm <- merge(panel_use[, .(Ticker, ym, Date_eom, eligible, FwdRet_1M, FwdRet_6M, FwdRet_12M, Sector, Size_eom)],
            beta_dt[, .SD, .SDcols = c("Ticker", "ym", lag_cols)],
            by = c("Ticker", "ym"), all.x = TRUE)

mm <- mm[eligible == TRUE & ym >= "2010-01"]
cat("[04] eligible rows post-2010:", nrow(mm),
    "ms:", uniqueN(mm$ym), "tk:", uniqueN(mm$Ticker), "\n")

# ---- Cross-section z-score per macro per month (winsorized) ----
z_cols <- character(0)
for (lc in lag_cols) {
  zc <- sub("_lag1$", "_z", lc)
  z_cols <- c(z_cols, zc)
  mm[, (zc) := {
    x <- get(lc)
    if (sum(!is.na(x)) >= 30) {
      mu <- mean(x, na.rm = TRUE); sd0 <- sd(x, na.rm = TRUE)
      if (is.na(sd0) || sd0 < 1e-12) return(rep(NA_real_, length(x)))
      x_w <- pmax(pmin(x, mu + 3*sd0), mu - 3*sd0)
      mu2 <- mean(x_w, na.rm=TRUE); sd2 <- sd(x_w, na.rm=TRUE)
      if (is.na(sd2) || sd2 < 1e-12) rep(0, length(x)) else (x_w - mu2)/sd2
    } else rep(NA_real_, length(x))
  }, by = ym]
}

# ---- Per-macro per-month rank IC ----
ic_long <- list()
for (zc in z_cols) {
  ic_m <- mm[!is.na(get(zc)) & !is.na(FwdRet_1M),
             .(rank_ic = cor(get(zc), FwdRet_1M, method = "spearman", use = "complete.obs"),
               n = .N),
             by = ym]
  ic_m[, macro := sub("^beta_", "", sub("_z$", "", zc))]
  ic_long[[zc]] <- ic_m
}
ic_long <- rbindlist(ic_long)

ic_agg <- ic_long[, .(
  rank_ic_mean = mean(rank_ic, na.rm=TRUE),
  rank_ic_sd   = sd(rank_ic, na.rm=TRUE),
  n_periods    = .N,
  hit_pos      = mean(rank_ic > 0, na.rm = TRUE),
  abs_ic       = mean(abs(rank_ic), na.rm = TRUE)
), by = macro]
ic_agg[, icir := rank_ic_mean / pmax(rank_ic_sd, 1e-8)]
ic_agg[, t_stat := rank_ic_mean / (rank_ic_sd / sqrt(pmax(n_periods,1)))]
setorder(ic_agg, -abs_ic)
fwrite(ic_agg, file.path(OUT, "per_macro_ic_aggregate.csv"))

# ---- Expanding-window direction inference + selection (per month) ----
TOP_K <- 4L
BURN <- 36L
months <- sort(unique(mm$ym))
ic_long[, ym_idx := match(ym, months)]

ic_wide <- dcast(ic_long, ym ~ macro, value.var = "rank_ic")
setorder(ic_wide, ym)
macro_names <- setdiff(names(ic_wide), "ym")

# Build per-month direction (sign expanding mean) and use (top-K by |expanding mean|)
n_periods <- nrow(ic_wide)
dir_mat <- matrix(0, nrow = n_periods, ncol = length(macro_names),
                  dimnames = list(NULL, macro_names))
use_mat <- matrix(0, nrow = n_periods, ncol = length(macro_names),
                  dimnames = list(NULL, macro_names))

for (mc in macro_names) {
  v <- ic_wide[[mc]]
  exp_mean <- rep(NA_real_, n_periods)
  for (t in 2:n_periods) {
    h <- v[1:(t-1)]; h <- h[!is.na(h)]
    if (length(h) >= 12) exp_mean[t] <- mean(h)
  }
  dir_mat[, mc] <- ifelse(is.na(exp_mean), 0, sign(exp_mean))
  # store abs_exp for later top-K selection per row
  attr(dir_mat, paste0("abs_", mc)) <- abs(exp_mean)
}

# Top-K per row from |expanding mean|
for (t in seq_len(n_periods)) {
  if (t < BURN) next
  abs_vals <- sapply(macro_names, function(mc) attr(dir_mat, paste0("abs_", mc))[t])
  if (all(is.na(abs_vals))) next
  ranked <- rank(-abs_vals, ties.method = "first", na.last = "keep")
  for (mc in macro_names) {
    if (!is.na(ranked[mc]) && ranked[mc] <= TOP_K) use_mat[t, mc] <- 1L
  }
}

# Build wide selection table for merge
sel_wide <- data.table(ym = ic_wide$ym)
for (mc in macro_names) {
  sel_wide[, paste0("dir_", mc) := dir_mat[, mc]]
  sel_wide[, paste0("use_", mc) := use_mat[, mc]]
}

# Merge sel_wide into mm by ym (one row per ym in sel_wide)
mm <- merge(mm, sel_wide, by = "ym", all.x = TRUE)
setorder(mm, Ticker, ym)
cat("[04] mm rows after sel_wide merge:", nrow(mm), "\n")
cat("[04] sample sel cols (post-burn):\n")
print(mm[ym == "2014-01", .(Ticker, ym, dir_KR_FX_lr, use_KR_FX_lr,
                              dir_VIX_lr, use_VIX_lr)][1:3])

# ---- Composite α̂ ----
mm[, alpha_raw := 0.0]
mm[, n_used := 0L]
for (mc in macro_names) {
  zc <- paste0("beta_", mc, "_z")
  dc <- paste0("dir_", mc); uc <- paste0("use_", mc)
  z_v <- mm[[zc]]; d_v <- mm[[dc]]; u_v <- mm[[uc]]
  signed_z <- ifelse(is.na(z_v) | is.na(u_v) | u_v == 0, 0, d_v * z_v)
  mm[, alpha_raw := alpha_raw + signed_z]
  mm[, n_used := n_used + as.integer(!is.na(z_v) & !is.na(u_v) & u_v == 1L)]
}
mm[, alpha_pre := ifelse(n_used > 0, alpha_raw / n_used, NA_real_)]

cat("[04] alpha_pre non-NA:", sum(!is.na(mm$alpha_pre)),
    " mean n_used:", round(mean(mm$n_used),2), "\n")

# ---- 6M EMA smoothing per ticker ----
ema6 <- function(x, lambda = 2/(6+1)) {
  y <- rep(NA_real_, length(x))
  s <- NA_real_
  for (i in seq_along(x)) {
    if (is.na(x[i])) { y[i] <- s; next }
    s <- if (is.na(s)) x[i] else (1 - lambda) * s + lambda * x[i]
    y[i] <- s
  }
  y
}
mm[, alpha_smooth := ema6(alpha_pre), by = Ticker]

# Re-z per month
mm[, alpha := {
  v <- alpha_smooth
  if (sum(!is.na(v)) >= 20) {
    mu <- mean(v, na.rm=TRUE); sd0 <- sd(v, na.rm=TRUE)
    if (is.na(sd0) || sd0 < 1e-12) rep(0, length(v)) else (v - mu)/sd0
  } else rep(NA_real_, length(v))
}, by = ym]

# Sector-neutral alpha
mm[, alpha_sn := alpha - mean(alpha, na.rm=TRUE), by = .(ym, Sector)]
mm[, alpha_sn := {
  v <- alpha_sn
  if (sum(!is.na(v)) >= 20) {
    sd0 <- sd(v, na.rm=TRUE)
    if (is.na(sd0) || sd0 < 1e-12) rep(0, length(v)) else (v - mean(v, na.rm=TRUE))/sd0
  } else rep(NA_real_, length(v))
}, by = ym]

# ---- Composite IC (post-burn) ----
ic_comp <- mm[ym >= "2013-01" & !is.na(alpha) & !is.na(FwdRet_1M),
              .(rank_ic = cor(alpha, FwdRet_1M, method="spearman"), n=.N), by = ym]
ic_sn   <- mm[ym >= "2013-01" & !is.na(alpha_sn) & !is.na(FwdRet_1M),
              .(rank_ic = cor(alpha_sn, FwdRet_1M, method="spearman"), n=.N), by = ym]

cat("\n[04] COMPOSITE IC (post-2013 OOS, after burn-in + smoothing):\n")
cat("  raw smoothed:   IC mean =", round(mean(ic_comp$rank_ic, na.rm=TRUE),4),
    "ICIR =", round(mean(ic_comp$rank_ic, na.rm=TRUE) / sd(ic_comp$rank_ic, na.rm=TRUE), 3),
    "n =", nrow(ic_comp), "\n")
cat("  sector-neutral: IC mean =", round(mean(ic_sn$rank_ic, na.rm=TRUE),4),
    "ICIR =", round(mean(ic_sn$rank_ic, na.rm=TRUE) / sd(ic_sn$rank_ic, na.rm=TRUE), 3),
    "n =", nrow(ic_sn), "\n")

# Subperiod stability
subps <- list(p1=c("2013-01","2016-12"), p2=c("2017-01","2020-12"), p3=c("2021-01","2026-12"))
sub_summary <- lapply(names(subps), function(pn) {
  rng <- subps[[pn]]
  sub <- ic_comp[ym >= rng[1] & ym <= rng[2]]
  if (nrow(sub) < 6) return(data.table(p=pn, ic_mean=NA_real_, icir=NA_real_, n=nrow(sub)))
  data.table(p = pn,
             ic_mean = mean(sub$rank_ic, na.rm=TRUE),
             icir = mean(sub$rank_ic, na.rm=TRUE) / sd(sub$rank_ic, na.rm=TRUE),
             n = nrow(sub))
}) |> rbindlist()
cat("\n[04] Subperiod stability (raw smoothed):\n"); print(sub_summary)

# Hit rate (sign stability)
overall_sign <- sign(mean(ic_comp$rank_ic, na.rm=TRUE))
sub_signs <- sub_summary[!is.na(ic_mean), sign(ic_mean)]
sub_stab <- if (length(sub_signs) > 0) mean(sub_signs == overall_sign) else NA_real_
cat("[04] Subperiod sign stability:", round(sub_stab, 3), "\n")

# Save
fwrite(ic_comp, file.path(OUT, "ic_composite_monthly.csv"))
fwrite(ic_sn,   file.path(OUT, "ic_composite_sectorneutral_monthly.csv"))
write_parquet(mm[, .(Ticker, ym, Date_eom, Sector, alpha_raw, alpha_pre, alpha_smooth,
                     alpha, alpha_sn, FwdRet_1M, FwdRet_6M, FwdRet_12M, n_used, eligible)],
              file.path(OUT, "alpha_panel.parquet"))
cat("\n[04] alpha_panel saved.\n")

# Predictor lag-1 autocor (cross-sectional / per ticker average)
acf_dt <- mm[!is.na(alpha), .(Ticker, ym, alpha)]
setorder(acf_dt, Ticker, ym)
acf_dt[, alpha_lag1 := shift(alpha, 1L), by = Ticker]
# use ym numeric to detect gaps: strip "-" and compare
acf_dt[, ym_num := as.integer(gsub("-", "", ym))]
acf_dt[, ym_lag := shift(ym_num, 1L), by = Ticker]
# consecutive month gap = +1 in calendar (e.g., 201501 → 201502 = +1, 201512 → 201601 = +89)
# use 5 max gap (lenient)
acf_dt[, gap_ok := (ym_num - ym_lag) %in% c(1, 89)]
acf_calc <- acf_dt[gap_ok == TRUE & !is.na(alpha) & !is.na(alpha_lag1)]
ac1 <- if (nrow(acf_calc) >= 100) cor(acf_calc$alpha, acf_calc$alpha_lag1) else NA_real_
cat("[04] predictor lag-1 autocor =", round(ac1, 3),
    " (n =", nrow(acf_calc), ")\n")

ac_diag <- list(
  predictor_name = "alpha (composite, EMA6 smoothed)",
  lag1_autocor = if (is.na(ac1)) NA else round(ac1, 4),
  threshold_warn = 0.95,
  status = if (is.na(ac1)) "INSUFFICIENT_DATA"
           else if (ac1 > 0.95) "WARN_HIGH_AUTOCOR"
           else if (ac1 > 0.85) "MID_HIGH_NORMAL_FOR_LONG_HORIZON"
           else "OK",
  rationale = "long-horizon design intentionally smooths predictor; mid-high autocor expected; > 0.95 indicates near-static (WT_001 lessons)",
  n_pairs = nrow(acf_calc)
)
write_json(ac_diag, file.path(OUT, "predictor_autocor_diagnosis.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat("[04] saved predictor_autocor_diagnosis.json\n")
