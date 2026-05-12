# =============================================================================
# WT-D20260511_001 Alpha Research FINAL — 3-Axis Vol-Skew Composite (D43+D41+D58)
# =============================================================================
# Final selection after v1-v5 iterative refinement:
#   - v1 Macro Residual: HONEST FAIL (IC 0.004, NW-t 0.73)
#   - v2 4-axis full-sample align: PIT C1 violation suspected (IC 0.19 inflated)
#   - v3 4-axis raw: IC negative (direction not aligned, anti-momentum)
#   - v4 4-axis expanding-align: IC 0.20 but D05_MaxRet IC 0.30 비현실
#   - v5 4-axis sector-neutral: IC 0.17, D05 IC 0.27 still inflated
#   - FINAL 3-axis D05-excluded sector-neutral: IC 0.074, top20 SR 1.85, cor S4 -0.135
#
# Hypothesis: KR equity volatility-asymmetry/skewness composite alpha
#   - D43_Skewness (Boyer-Mitton-Vorkink 2010 RFS — expected idio skewness)
#   - D41_Vol_of_Vol (Baltussen-VanBekkum-VanderGrient 2018 RFS — vol-of-vol)
#   - D58_Vol_Asymmetry (Ang-Chen-Xing 2006 RFS — downside risk)
#
# Mechanism: KR investors over-pay for lottery (skewed, high vol-of-vol, downside-risk)
#   → low skew / low vol-of-vol / low asymmetry stocks earn higher future returns
#
# Why excluded D05_MaxRet: IC 0.27 비현실 (KR known-good Q07 IC 0.030 대비 9배) →
#   single factor inflate suspect (penny stocks survivorship / small-cap bias)
#
# PIT Compliance:
#   - C1: No full-sample IC sign use. Expanding mean IC with 36m burn-in.
#   - C13: Z_Score_Aligned from Factor DB + own expanding direction (NO FLIP_SIGN raw).
#   - C14: Usable_Date <= sig_date via load_month_factors()
#   - C15: load_month_factors() route only
#
# Orthogonality vs S4 v2:
#   - cor full pearson -0.135 (target <0.30, PASS)
#   - cor crisis (S4 bot 20pct) -0.338 (strong crisis hedge, defensive)
#   - cor normal +0.043 (low normal-regime correlation)
#
# Quality Metrics (eval 2011-01 ~ 2023-11, post 36m burn-in):
#   - rank_IC: 0.074, ICIR: 0.869 (target 0.04/0.20, ✓ 1.9x/4.3x)
#   - Harvey NW-t: 8.62 (target >3.0, ✓ 2.9x)
#   - Sector-neutral retention: 82% (mild sector bias retain)
#   - Top20 EW portfolio SR: 1.85, ret_ann: 52.84%
#
# Subperiod stability + Monotonicity: 측정 후 기록 (이전 v5 4-axis 1.0/1.0)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(future); library(future.apply)
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260511_001"
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts", "WT_D20260511_001")
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

SIGNAL_CUTOFF <- as.Date("2023-12-22")
BURN_IN_MONTHS <- 36L
sig_dates <- seq.Date(as.Date("2008-01-01"), SIGNAL_CUTOFF, by = "month")
sig_dates <- as.Date(format(sig_dates, "%Y-%m-01"))

# FINAL 3-axis composite (D05 excluded per inflate diagnostic)
SELECTED_FACTORS <- c("D43_Skewness", "D41_Vol_of_Vol", "D58_Vol_Asymmetry")
cat("FINAL 3-axis composite:\n")
cat("  Factors:", paste(SELECTED_FACTORS, collapse=", "), "\n")
cat("  Period: 2008-01 to 2023-12 (lockbox, alpha research stage PIT)\n")
cat("  Burn-in: 36 months\n\n")

n_workers <- min(6L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

panel_list <- future_lapply(sig_dates, function(sd) {
  tryCatch({
    suppressMessages(m <- load_month_factors(sd))
    if (is.null(m) || nrow(m) == 0) return(NULL)
    m_sel <- m[Factor_Name %in% SELECTED_FACTORS]
    if (nrow(m_sel) == 0) return(NULL)
    m_w <- dcast(m_sel, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    m_w[, sig_date := sd]
    m_w
  }, error = function(e) NULL)
})
panel <- rbindlist(panel_list, fill = TRUE, use.names = TRUE)
plan(sequential)
cat("Panel rows:", nrow(panel), "\n")

# Universe + sector
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setnames(rd, "Date", "date")
rd <- rd[date >= as.Date("2007-01-01") & date <= as.Date("2026-04-30")]
rd[, ADV_KRW := Close * Vol]
setkey(rd, Ticker, date)
rd[, ADV_20d := frollmean(ADV_KRW, n = 20L, align = "right", fill = NA), by = Ticker]

trade_days <- sort(unique(rd$date))
sig_date_dt <- data.table(sig_date = sig_dates)
sig_date_dt[, pit_t1_day := as.Date(sapply(sig_date, function(d) {
  cand <- trade_days[trade_days < d]; if (length(cand) > 0) as.character(max(cand)) else NA_character_
}))]

rd_snap <- rd[, .(date, Ticker, K200, KQ150, ADV_20d, Sector, Size)]
setkey(rd_snap, date, Ticker)
universe_list <- lapply(seq_len(nrow(sig_date_dt)), function(i) {
  d <- sig_date_dt[i]$pit_t1_day
  if (is.na(d)) return(NULL)
  snap <- rd_snap[date == d]
  snap[, eligible := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
  snap[, liquid_ok := !is.na(ADV_20d) & ADV_20d >= 2e8]
  e <- snap[eligible & liquid_ok]
  if (nrow(e) == 0) return(NULL)
  e[, sig_date := sig_date_dt[i]$sig_date]
  e[, .(sig_date, Ticker, Sector, Size)]
})
universe <- rbindlist(universe_list)
panel <- merge(panel, universe, by = c("sig_date", "Ticker"))
cat("Universe-filtered:", nrow(panel), "\n")

# Forward returns
rd_simple <- rd[!is.na(Ret), .(date, Ticker, Ret)]
setkey(rd_simple, Ticker, date)
ret_list <- vector("list", length(sig_dates) - 1)
for (i in seq_along(sig_dates)[-length(sig_dates)]) {
  d_s <- sig_dates[i]; d_e <- sig_dates[i + 1]
  rb <- rd_simple[date > d_s & date <= d_e, .(ret_1M = prod(1 + Ret) - 1), by = Ticker]
  rb[, sig_date := d_s]
  ret_list[[i]] <- rb
}
ret_fwd <- rbindlist(ret_list)
panel <- merge(panel, ret_fwd, by = c("Ticker", "sig_date"))
panel <- panel[complete.cases(panel[, ..SELECTED_FACTORS])]
panel <- panel[!is.na(Sector)]
cat("Final panel:", nrow(panel), "\n\n")

# Expanding direction (PIT-safe, lag 1, 36m burn-in)
ic_per_sig <- panel[, .(
  ic_D43 = cor(D43_Skewness, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D41 = cor(D41_Vol_of_Vol, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D58 = cor(D58_Vol_Asymmetry, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
setkey(ic_per_sig, sig_date)
ic_sorted <- ic_per_sig[order(sig_date)]
expanding_dir <- data.table(sig_date = ic_sorted$sig_date)
for (col in c("ic_D43", "ic_D41", "ic_D58")) {
  f <- gsub("ic_", "", col); v <- ic_sorted[[col]]
  cn <- cumsum(!is.na(v)); cs <- cumsum(ifelse(is.na(v), 0, v))
  cm <- shift(cs / pmax(cn, 1), 1, fill = NA); cnl <- shift(cn, 1, fill = 0)
  expanding_dir[, paste0("dir_", f) := ifelse(cnl >= BURN_IN_MONTHS, ifelse(cm >= 0, 1L, -1L), 1L)]
}
panel <- merge(panel, expanding_dir, by = "sig_date", all.x = TRUE)
panel[, D43_aligned := D43_Skewness * dir_D43]
panel[, D41_aligned := D41_Vol_of_Vol * dir_D41]
panel[, D58_aligned := D58_Vol_Asymmetry * dir_D58]
panel[, alpha_raw := (D43_aligned + D41_aligned + D58_aligned) / 3]

# Sector-neutral
panel[, D43_sn := D43_aligned - mean(D43_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel[, D41_sn := D41_aligned - mean(D41_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel[, D58_sn := D58_aligned - mean(D58_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel[, alpha_composite := (D43_sn + D41_sn + D58_sn) / 3]  # FINAL composite = sector-neutral

panel_eval <- panel[sig_date >= sig_dates[BURN_IN_MONTHS + 1]]
cat("Eval period:", as.character(min(panel_eval$sig_date)), "to", as.character(max(panel_eval$sig_date)),
    " (", uniqueN(panel_eval$sig_date), "sig_dates)\n\n")

# Full diagnostics
cat("=== DIAGNOSTICS ===\n")

# 1. IC + ICIR + Harvey NW
ic_eval <- panel_eval[, .(ic = cor(alpha_composite, ret_1M, method="spearman", use="complete.obs"), N=.N), by=sig_date]
mean_ic <- mean(ic_eval$ic, na.rm=TRUE)
sd_ic <- sd(ic_eval$ic, na.rm=TRUE)
icir <- mean_ic / sd_ic
v <- ic_eval$ic[!is.na(ic_eval$ic)]; N <- length(v); L <- floor(4 * (N/100)^(2/9)); if (L<1) L <- 1
a <- acf(v, lag.max=L, plot=FALSE)$acf[-1]
nw_c <- max(1 + 2 * sum((1 - (1:L)/(L+1)) * a), 0.5)
t_nw <- mean_ic / sqrt(var(v) * nw_c / N)

cat(sprintf("Composite IC: %.4f / ICIR: %.4f / NW-t: %.4f / N=%d\n", mean_ic, icir, t_nw, N))

# 2. Per-factor diagnostic (sector-neutral)
ic_per <- panel_eval[, .(
  D43_sn_ic = cor(D43_sn, ret_1M, method = "spearman", use = "complete.obs"),
  D41_sn_ic = cor(D41_sn, ret_1M, method = "spearman", use = "complete.obs"),
  D58_sn_ic = cor(D58_sn, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
ic_per_long <- melt(ic_per, id.vars = "sig_date", variable.name = "factor", value.name = "ic")
ic_per_summary <- ic_per_long[, .(mean_ic = mean(ic, na.rm = TRUE), icir = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE)), by = factor]
harvey_per <- ic_per_long[, {
  v2 <- ic[!is.na(ic)]; if (length(v2) < 30) return(.(t_nw = NA_real_))
  s2 <- var(v2); Nf <- length(v2); Lf <- floor(4 * (Nf/100)^(2/9)); if (Lf<1) Lf <- 1
  a2 <- acf(v2, lag.max=Lf, plot=FALSE)$acf[-1]
  nw_c2 <- max(1 + 2 * sum((1 - (1:Lf)/(Lf+1)) * a2), 0.5)
  .(t_nw = mean(v2) / sqrt(s2 * nw_c2 / Nf))
}, by = factor]
cat("\nPer-factor (sector-neutral, post-align):\n")
print(merge(ic_per_summary, harvey_per, by = "factor"))
harvey_t_pass <- sum(abs(harvey_per$t_nw) > 3.0, na.rm = TRUE)
if (abs(t_nw) > 3.0) harvey_t_pass <- harvey_t_pass + 1
cat("Harvey t-pass count (>3.0):", harvey_t_pass, "\n")

# 3. Subperiod stability
panel_eval[, period_3 := fcase(
  sig_date < as.Date("2014-01-01"), "P1_2011_2013",
  sig_date < as.Date("2020-01-01"), "P2_2014_2019",
  default = "P3_2020_2023"
)]
ic_sub <- panel_eval[, .(ic = cor(alpha_composite, ret_1M, method="spearman", use="complete.obs"), N=.N), by=.(sig_date, period_3)]
ic_sub_s <- ic_sub[, .(mean_ic = mean(ic, na.rm=TRUE), icir = mean(ic, na.rm=TRUE) / sd(ic, na.rm=TRUE), N=.N), by=period_3]
subperiod_pos <- sum(ic_sub_s$mean_ic > 0)
subperiod_stab <- subperiod_pos / nrow(ic_sub_s)
cat("\nSubperiod stab:", subperiod_stab, "\n")
print(ic_sub_s)

# 4. Monotonicity
panel_eval[, decile := cut(alpha_composite, breaks = quantile(alpha_composite, probs = seq(0, 1, 0.1), na.rm = TRUE), labels = FALSE, include.lowest = TRUE), by = sig_date]
decile_ret <- panel_eval[!is.na(decile), .(mean_ret = mean(ret_1M, na.rm = TRUE)), by = .(sig_date, decile)]
decile_avg <- decile_ret[, .(avg_ret = mean(mean_ret, na.rm = TRUE)), by = decile][order(decile)]
mono <- cor(decile_avg$decile, decile_avg$avg_ret, method = "spearman")
cat("\nMonotonicity:", round(mono, 3), "\n"); print(decile_avg)

# 5. Post-neutralization vs Q07_Earnings_Stability
plan(multisession, workers = n_workers)
q07_lst <- future_lapply(sig_dates, function(sd) {
  tryCatch({
    suppressMessages(m <- load_month_factors(sd))
    m_q <- m[Factor_Name == "Q07_Earnings_Stability"]
    if (nrow(m_q) == 0) return(NULL)
    data.table(Ticker = m_q$Ticker, sig_date = sd, z_q07 = m_q$Z_Score_Aligned)
  }, error = function(e) NULL)
})
plan(sequential)
q07_panel <- rbindlist(q07_lst, fill = TRUE)
panel_neu <- merge(panel_eval, q07_panel, by = c("Ticker", "sig_date"))
panel_neu[!is.na(z_q07), alpha_neu := {
  if (sd(z_q07, na.rm = TRUE) > 1e-6) {
    coef_q07 <- cov(alpha_composite, z_q07, use = "pairwise.complete.obs") / var(z_q07, na.rm = TRUE)
    alpha_composite - coef_q07 * z_q07
  } else alpha_composite
}, by = sig_date]
ic_neu_eval <- panel_neu[!is.na(alpha_neu), .(ic = cor(alpha_neu, ret_1M, method = "spearman", use = "complete.obs")), by = sig_date]
mean_ic_neu <- mean(ic_neu_eval$ic, na.rm = TRUE)
post_retention <- mean_ic_neu / mean_ic
cat(sprintf("\nPost-neutralization IC (⊥ Q07): %.4f (retention %.0f%%)\n", mean_ic_neu, 100*post_retention))

# 6. Orthogonality vs S4 v2
s4_dt <- fread(file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260509_002/output/walk_forward_returns_timeseries.csv"))
s4_b <- s4_dt[method == "BENCH_S4_static_dohoon", .(date = as.Date(date), ret_S4 = ret_net)]
panel_top <- panel_eval[, {
  ranked <- order(alpha_composite, decreasing = TRUE)
  if (.N < 20) return(.(top20_ret = NA_real_, bot20_ret = NA_real_, spread = NA_real_, N = .N))
  top20 <- ranked[1:20]; bot20 <- ranked[(.N-19):.N]
  .(top20_ret = mean(ret_1M[top20], na.rm = TRUE),
    bot20_ret = mean(ret_1M[bot20], na.rm = TRUE),
    spread    = mean(ret_1M[top20], na.rm = TRUE) - mean(ret_1M[bot20], na.rm = TRUE),
    N = .N)
}, by = sig_date]
panel_top[, date := sig_date]
joined <- merge(panel_top[, .(date, alpha_ret = top20_ret)], s4_b[, .(date, ret_S4)], by = "date")
joined <- joined[!is.na(alpha_ret) & !is.na(ret_S4)]
cor_full_p <- cor(joined$alpha_ret, joined$ret_S4, method = "pearson")
cor_full_s <- cor(joined$alpha_ret, joined$ret_S4, method = "spearman")
ct <- quantile(joined$ret_S4, 0.2, na.rm = TRUE)
cor_crisis <- joined[ret_S4 <= ct, cor(alpha_ret, ret_S4, method = "pearson")]
cor_normal <- joined[ret_S4 > ct, cor(alpha_ret, ret_S4, method = "pearson")]
sharpe_top <- mean(joined$alpha_ret) * 12 / (sd(joined$alpha_ret) * sqrt(12))
ret_ann <- mean(joined$alpha_ret) * 12

# 7. AX-001 v2
bm <- tryCatch(as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/benchmark.parquet"))), error = function(e) NULL)
ic_bad <- NA; ic_norm <- NA
if (!is.null(bm)) {
  setnames(bm, names(bm)[1], "date")
  bm[, date := as.Date(date)]
  rc <- intersect(c("Ret", "BM_Ret", "ret"), names(bm))
  if (length(rc) > 0) {
    setnames(bm, rc[1], "bm_ret")
    bm[, ym := format(date, "%Y-%m")]
    bm_m <- bm[, .(bm_ret = prod(1 + bm_ret, na.rm = TRUE) - 1), by = ym]
    bm_m[, sig_date := as.Date(paste0(ym, "-01"))]
    panel_bm <- merge(panel_eval, bm_m[, .(sig_date, bm_ret)], by = "sig_date", all.x = TRUE)
    if (sum(!is.na(panel_bm$bm_ret)) > 50) {
      bt <- quantile(panel_bm$bm_ret, 0.2, na.rm = TRUE)
      ic_bad <- panel_bm[bm_ret <= bt, cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs")]
      ic_norm <- panel_bm[bm_ret >  bt, cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs")]
    }
  }
}

cat("\nOrthogonality vs S4 v2 baseline (BENCH_S4_static_dohoon):\n")
cat(sprintf("  Top20 SR: %.3f / Ret_ann: %.2f%% (N overlap: %d)\n", sharpe_top, ret_ann*100, nrow(joined)))
cat(sprintf("  cor full: pearson=%.4f / spearman=%.4f\n", cor_full_p, cor_full_s))
cat(sprintf("  cor crisis (S4 bot 20pct): %.4f / normal: %.4f\n", cor_crisis, cor_normal))
cat(sprintf("  AX-001 v2 IC bad/normal: bad=%.4f / norm=%.4f / ratio=%.3f\n",
            ifelse(is.na(ic_bad), NA, ic_bad), ifelse(is.na(ic_norm), NA, ic_norm),
            ifelse(is.na(ic_bad/ic_norm), NA, ic_bad/ic_norm)))

# 8. Turnover proxy
# 매 sig_date top20 vs prev sig_date top20 — Jaccard
sig_dts_eval <- sort(unique(panel_eval$sig_date))
turnover_list <- vector("list", length(sig_dts_eval) - 1)
for (i in seq_along(sig_dts_eval)[-length(sig_dts_eval)]) {
  curr <- panel_eval[sig_date == sig_dts_eval[i]]
  prev <- panel_eval[sig_date == sig_dts_eval[i + 1]]
  top_curr <- curr[order(-alpha_composite)][1:min(20, .N), Ticker]
  top_prev <- prev[order(-alpha_composite)][1:min(20, .N), Ticker]
  if (length(top_curr) == 0 || length(top_prev) == 0) next
  jacc <- length(intersect(top_curr, top_prev)) / length(union(top_curr, top_prev))
  turnover_list[[i]] <- data.table(date = sig_dts_eval[i + 1], jaccard = jacc, turnover_1way = 1 - jacc)
}
turnover_dt <- rbindlist(turnover_list)
mean_turnover_1m <- mean(turnover_dt$turnover_1way)
annual_turnover_proxy <- mean_turnover_1m * 12  # one-way per month → annual approx (one-way × 12 ≈ annual two-way × 0.5)
cat(sprintf("\nTurnover: monthly mean 1-way=%.3f, annual proxy=%.2f%%\n", mean_turnover_1m, annual_turnover_proxy*100))

# 9. Save alpha_scores.parquet
alpha_all <- panel_eval[, .(sig_date, Ticker, alpha = alpha_composite)]
alpha_all[, alpha_rank := frank(alpha) / .N, by = sig_date]
alpha_all[, confidence := pmin(0.95, pmax(0.05, alpha_rank * 0.9 + 0.05))]
alpha_all[, alpha_rank := NULL]
write_parquet(alpha_all, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("\nalpha_scores.parquet saved:", nrow(alpha_all), "rows\n")

# 10. alpha_validation.json
validation <- list(
  task_id = WT_ID, version = "FINAL_3axis_sector_neutral_pit_strict",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hypothesis = "3-Axis KR Equity Volatility-Skewness Composite (D43_Skewness + D41_Vol_of_Vol + D58_Vol_Asymmetry, sector-neutral)",
  selection_objective = "icir",
  pit_compliance = list(
    c1_no_full_sample = TRUE,
    c13_z_score_aligned = TRUE,
    c14_usable_date = TRUE,
    c15_factor_db_route = TRUE,
    direction_alignment = "Expanding mean IC lag-1, 36m burn-in",
    composite_method = "sector-demean per sig_date then equal-weight average",
    cutoff = as.character(SIGNAL_CUTOFF)
  ),
  diagnostics = list(
    rank_ic = mean_ic,
    icir = icir,
    monotonicity = mono,
    subperiod_stability = subperiod_stab,
    harvey_t_nw = t_nw,
    harvey_t_specs_pass_count = harvey_t_pass,
    per_factor_summary = merge(ic_per_summary, harvey_per, by = "factor"),
    post_neutralization_ic = mean_ic_neu,
    post_neutralization_retention = post_retention,
    turnover_proxy_annual = annual_turnover_proxy,
    turnover_monthly_1way = mean_turnover_1m,
    orthogonality = list(
      cor_alpha_S4_full_pearson = cor_full_p,
      cor_alpha_S4_full_spearman = cor_full_s,
      cor_crisis_S4_bot20pct = cor_crisis,
      cor_normal_S4_top80pct = cor_normal,
      n_overlap_periods = nrow(joined),
      top20_portfolio_sharpe_ann = sharpe_top,
      top20_portfolio_ret_ann = ret_ann
    ),
    crisis_alpha_ax001_v2 = list(
      ic_bad_regime = ic_bad,
      ic_normal_regime = ic_norm,
      ratio_bad_over_normal = if (!is.na(ic_bad/ic_norm)) ic_bad / ic_norm else NA
    ),
    decile_returns = decile_avg,
    subperiod_breakdown = ic_sub_s,
    n_sig_dates = uniqueN(panel_eval$sig_date),
    period_start = as.character(min(panel_eval$sig_date)),
    period_end = as.character(max(panel_eval$sig_date)),
    n_avg_tickers_per_period = panel_eval[, .N, by = sig_date][, mean(N)]
  ),
  refinement_path = list(
    v1_macro_residual = "HONEST FAIL: IC 0.004, NW-t 0.73 — univariate β regression insufficient",
    v2_4axis_full_sample_align = "PIT C1 violation suspected: IC 0.19 inflate from full-sample sign(mean_ic)",
    v3_4axis_raw_pit_strict = "IC -0.126 — raw factor direction reverse, no align",
    v4_4axis_expanding_align = "IC 0.20, BUT D05_MaxRet single-factor IC 0.31 비현실 inflate",
    v5_4axis_sector_neutral = "IC 0.17, D05 IC 0.27 still inflated",
    FINAL_3axis_sector_neutral = "IC 0.074, NW-t 8.6, sector-neutral, D05_MaxRet excluded — defensive realistic"
  ),
  why_d05_excluded = list(
    reason = "D05_MaxRet IC 0.27 비현실 inflate (KR known-good Q07_Earnings_Stability IC 0.030 대비 9배)",
    suspect = "small-cap / micro-cap / penny stock 영향 + survivorship bias 가능성",
    learning_loop = "Codex Round critique 검토 후 D05 재포함 vs 영구 제외 결정"
  ),
  honest_concerns = list(
    "D05_MaxRet 단독 IC 0.27 비정상 (KR specific 강도일 수도 있으나 conservative 제외)",
    "3-axis 모두 D-family (volatility) → factor 다양성 부족, AX-005 v1.2 single-sleeve standalone fail 위험은 multi-axis 직교 검증으로 mitigate",
    "post_neutralization_retention check vs Q07 필요 — STR_1715 main axis와 직교성 입증 의무",
    "turnover proxy은 1-way monthly. 12 곱하면 annual proxy하나 actual round-trip은 ~2배"
  )
)
write_json(validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")
cat("alpha_validation.json saved\n")

cat("\n=== FINAL SUMMARY ===\n")
cat(sprintf("Hypothesis: 3-axis KR vol/skew composite (D43+D41+D58, sector-neutral)\n"))
cat(sprintf("Eval: %s ~ %s (%d sig_dates)\n", as.character(min(panel_eval$sig_date)), as.character(max(panel_eval$sig_date)), uniqueN(panel_eval$sig_date)))
cat(sprintf("rank_IC: %.4f / ICIR: %.4f / NW-t: %.4f\n", mean_ic, icir, t_nw))
cat(sprintf("Monotonicity: %.3f / Subperiod stab: %.2f\n", mono, subperiod_stab))
cat(sprintf("Harvey t-pass count (>3.0): %d (composite + 3 sub-factors)\n", harvey_t_pass))
cat(sprintf("Post-neut IC ⊥ Q07: %.4f (retention %.0f%%)\n", mean_ic_neu, 100*post_retention))
cat(sprintf("Top20 SN portfolio SR: %.3f / Ret_ann: %.2f%%\n", sharpe_top, ret_ann*100))
cat(sprintf("cor S4_v2 full: pearson=%.3f / spearman=%.3f / crisis: %.3f\n", cor_full_p, cor_full_s, cor_crisis))
cat(sprintf("AX-001 v2 IC bad/normal: %.3f\n", ifelse(is.na(ic_bad/ic_norm), NA, ic_bad/ic_norm)))
cat(sprintf("Turnover proxy annual: %.1f%%\n", annual_turnover_proxy*100))
cat("\nGraduation criteria check:\n")
cat(sprintf("  min_rank_ic ≥ 0.04: %s (%.4f)\n", ifelse(mean_ic >= 0.04, "PASS", "FAIL"), mean_ic))
cat(sprintf("  min_icir ≥ 0.20: %s (%.3f)\n", ifelse(icir >= 0.20, "PASS", "FAIL"), icir))
cat(sprintf("  min_subperiod_stab ≥ 0.50: %s (%.2f)\n", ifelse(subperiod_stab >= 0.50, "PASS", "FAIL"), subperiod_stab))
cat(sprintf("  min_harvey_t ≥ 3.0: %s (%.4f)\n", ifelse(abs(t_nw) >= 3.0, "PASS", "FAIL"), t_nw))
cat("Done.\n")
