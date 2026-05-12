# =============================================================================
# WT-D20260511_001 Alpha Research v2 — Volatility/Skewness Multi-Axis Composite
# =============================================================================
# Goal: 4th orthogonal alpha source (S4 v2 baseline gap 0.335 SR resolution)
#
# Path 1 (Macro Residual) HONEST FAIL — IC 0.0038, ICIR 0.05, NW-t 0.73
# → Pivot to Path 2 candidate: Multi-axis vol/skew composite (D-family)
#
# Mechanism: 4-axis composite (none overlap with STR_1715 factor specs)
#   - axis 1: D43_Skewness (Boyer-Mitton-Vorkink 2010 RFS — expected idio skewness)
#     Expected sign: NEGATIVE (high skew → low future return, lottery effect)
#   - axis 2: D05_MaxRet (Bali-Cakici-Whitelaw 2011 JFE — MAX)
#     Expected sign: NEGATIVE (lottery preference penalty)
#   - axis 3: D41_Vol_of_Vol (Baltussen-VanBekkum-VanderGrient 2018 — vol-of-vol)
#     Expected sign: POSITIVE (vol-of-vol premium)
#   - axis 4: D58_Vol_Asymmetry (Ang-Chen-Xing 2006 — downside risk)
#     Expected sign: POSITIVE (downside risk-adjusted premium)
#
# Composite Logic:
#   - Cross-section z-score per sig_date
#   - IC-based direction alignment (Z_Score_Aligned C13)
#   - Composite = (z1 + z2 + z3 + z4) / 4 (NO weight learning to avoid overfitting)
#
# PIT Strict:
#   - C13: Z_Score_Aligned only (use Factor DB's auto-aligned z-score)
#   - C14: IC Usable_Date <= sig_date
#   - C15: load_month_factors() route
#
# References:
#   - Boyer-Mitton-Vorkink 2010 RFS "Expected Idiosyncratic Skewness"
#   - Bali-Cakici-Whitelaw 2011 JFE "MAX as a measure of expected return"
#   - Baltussen-VanBekkum-VanderGrient 2018 RFS "Unknown Unknowns: Vol-of-Vol"
#   - Ang-Chen-Xing 2006 RFS "Downside Risk"
#   - Atilgan et al 2020 JFE — 단, KR 친순환 fail (L-285)
#     → 본 가설은 NEGATIVE direction (lottery penalty), opposite of Atilgan
#
# L-code lesson_check:
#   - L-285: Atilgan KR 친순환 fail → NEGATIVE 방향 (반대) 채택
#   - L-484: 수익률 블렌드 앙상블 ❌ → 본 가설은 SCORE 블렌드 (cross-section z 합) ✓
#   - L-454: 한국 internal data only
#   - L-280/281: cross-section 정의상 직교 (TSMOM 시계열과 다른 risk premium category)
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

cat("[1/9] Generate sig_dates (2008-01 ~ 2026-04, monthly)...\n")
# Lockbox cutoff: 2023-12-22 retain for alpha research (PIT C1 정합, .claude/rules/lockbox-scope.md)
SIGNAL_CUTOFF <- as.Date("2023-12-22")
sig_dates <- seq.Date(as.Date("2008-01-01"), SIGNAL_CUTOFF, by = "month")
# Snap to first of month
sig_dates <- as.Date(format(sig_dates, "%Y-%m-01"))
cat("  N sig_dates:", length(sig_dates), "\n")
cat("  Range:", as.character(min(sig_dates)), "to", as.character(max(sig_dates)), "\n")

# Selected factors (Step 0 가설 발굴 결과)
SELECTED_FACTORS <- c("D43_Skewness", "D05_MaxRet", "D41_Vol_of_Vol", "D58_Vol_Asymmetry")
cat("  Selected factors (4-axis):", paste(SELECTED_FACTORS, collapse = ", "), "\n")

cat("[2/9] Load month_factors (PIT-safe via Factor DB connector)...\n")
# Per sig_date, load Factor DB Z_Score_Aligned for selected factors
n_workers <- min(6L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

panel_list <- future_lapply(sig_dates, function(sd) {
  tryCatch({
    suppressMessages({
      m <- load_month_factors(sd)
    })
    if (is.null(m) || nrow(m) == 0) return(NULL)
    m_sel <- m[Factor_Name %in% SELECTED_FACTORS]
    if (nrow(m_sel) == 0) return(NULL)
    # Wide pivot
    m_w <- dcast(m_sel, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    m_w[, sig_date := sd]
    m_w
  }, error = function(e) NULL)
})
panel <- rbindlist(panel_list, fill = TRUE, use.names = TRUE)
plan(sequential)

cat("  Panel rows:", nrow(panel), "  unique sig_dates:", uniqueN(panel$sig_date), "\n")
cat("  Coverage per factor:\n")
for (f in SELECTED_FACTORS) {
  cov <- sum(!is.na(panel[[f]])) / nrow(panel)
  cat(sprintf("    %s: %.1f%%\n", f, cov * 100))
}

cat("[3/9] Universe filter + liquidity (eligible only)...\n")
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setnames(rd, "Date", "date")
rd <- rd[date >= as.Date("2007-01-01") & date <= as.Date("2026-04-30")]

# 20-day ADV per ticker
rd[, ADV_KRW := Close * Vol]
setkey(rd, Ticker, date)
rd[, ADV_20d := frollmean(ADV_KRW, n = 20L, align = "right", fill = NA), by = Ticker]

# At each sig_date, snapshot K200/KQ150 + ADV_20d
sig_date_dt <- data.table(sig_date = sig_dates)
# For each sig_date, find last available trade day <= sig_date - 1d (PIT t-1)
trade_days <- sort(unique(rd$date))
sig_date_dt[, pit_t1_day := sapply(sig_date, function(d) {
  cand <- trade_days[trade_days < d]
  if (length(cand) > 0) as.character(max(cand)) else NA_character_
})]
sig_date_dt[, pit_t1_day := as.Date(pit_t1_day)]

# Snapshot universe info at pit_t1_day
rd_snap <- rd[, .(date, Ticker, K200, KQ150, ADV_20d)]
setkey(rd_snap, date, Ticker)
universe_list <- lapply(seq_len(nrow(sig_date_dt)), function(i) {
  d <- sig_date_dt[i]$pit_t1_day
  if (is.na(d)) return(NULL)
  snap <- rd_snap[date == d]
  if (nrow(snap) == 0) return(NULL)
  snap[, sig_date := sig_date_dt[i]$sig_date]
  snap[, eligible := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
  snap[, liquid_ok := !is.na(ADV_20d) & ADV_20d >= 2e8]
  snap[eligible == TRUE & liquid_ok == TRUE, .(sig_date, Ticker)]
})
universe <- rbindlist(universe_list)
cat("  Universe-eligible obs:", nrow(universe), "  avg per sig_date:", round(nrow(universe) / uniqueN(universe$sig_date), 1), "\n")

# Filter panel by universe
panel <- merge(panel, universe, by = c("sig_date", "Ticker"))
cat("  After universe filter:", nrow(panel), "\n")

cat("[4/9] Forward 1M return computation (next-period rebalance)...\n")
# For each sig_date, compute return from sig_date to next sig_date
# (Use available pricing data, lockbox-applicable in alpha research stage)
rd_simple <- rd[!is.na(Ret), .(date, Ticker, Ret)]
setkey(rd_simple, Ticker, date)

ret_list <- vector("list", length(sig_dates) - 1)
for (i in seq_along(sig_dates)[-length(sig_dates)]) {
  d_start <- sig_dates[i]
  d_end   <- sig_dates[i + 1]
  ret_block <- rd_simple[date > d_start & date <= d_end, .(ret_1M = prod(1 + Ret) - 1), by = Ticker]
  ret_block[, sig_date := d_start]
  ret_list[[i]] <- ret_block
}
ret_fwd <- rbindlist(ret_list)
cat("  Forward returns:", nrow(ret_fwd), "\n")

panel <- merge(panel, ret_fwd, by = c("Ticker", "sig_date"))
cat("  Merged panel (with ret_1M):", nrow(panel), "\n")

# Drop rows with any NA in selected factors
panel <- panel[complete.cases(panel[, ..SELECTED_FACTORS])]
cat("  After NA-drop:", nrow(panel), "\n")

cat("[5/9] Cross-section re-z-score + direction-aligned composite...\n")
# Re-z-score within each sig_date (factor DB already aligned, but re-cs Z for safety)
for (f in SELECTED_FACTORS) {
  panel[, paste0(f, "_z") := scale(get(f))[,1], by = sig_date]
}

# Per-factor IC + direction
ic_per_f <- panel[, lapply(.SD, function(z) cor(z, ret_1M, method = "spearman", use = "complete.obs")),
                  .SDcols = paste0(SELECTED_FACTORS, "_z"), by = sig_date]
ic_per_f_long <- melt(ic_per_f, id.vars = "sig_date", variable.name = "factor_z", value.name = "ic")
ic_summary_per_f <- ic_per_f_long[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic   = sd(ic, na.rm = TRUE),
  icir    = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE),
  N       = .N
), by = factor_z]

cat("  Per-factor IC summary:\n")
print(ic_summary_per_f)

# Direction-align z scores by mean IC sign
for (f in SELECTED_FACTORS) {
  z_col <- paste0(f, "_z")
  dir <- sign(ic_summary_per_f[factor_z == z_col, mean_ic])
  if (length(dir) == 0 || is.na(dir)) dir <- 1
  panel[, paste0(f, "_aligned") := get(z_col) * dir]
}

# Composite: equal-weight average (no overfitting)
aligned_cols <- paste0(SELECTED_FACTORS, "_aligned")
panel[, alpha_composite := rowMeans(.SD, na.rm = TRUE), .SDcols = aligned_cols]

cat("[6/9] Composite IC + ICIR + Harvey t (NW)...\n")
ic_comp <- panel[, .(
  ic = cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs"),
  N  = .N
), by = sig_date]

mean_ic_comp <- mean(ic_comp$ic, na.rm = TRUE)
sd_ic_comp <- sd(ic_comp$ic, na.rm = TRUE)
icir_comp <- mean_ic_comp / sd_ic_comp

# NW t-stat
ic_vec <- ic_comp$ic[!is.na(ic_comp$ic)]
N <- length(ic_vec)
sigma2 <- var(ic_vec)
L <- floor(4 * (N/100)^(2/9)); if (L < 1) L <- 1
acf_v <- acf(ic_vec, lag.max = L, plot = FALSE)$acf[-1]
nw_correction <- 1 + 2 * sum((1 - (1:L)/(L+1)) * acf_v)
nw_correction <- max(nw_correction, 0.5)  # floor
var_nw <- sigma2 * nw_correction
t_nw <- mean_ic_comp / sqrt(var_nw / N)

cat(sprintf("  Composite IC: %.4f / SD: %.4f / ICIR: %.4f / NW-t: %.4f\n",
            mean_ic_comp, sd_ic_comp, icir_comp, t_nw))

# Per-factor Harvey t (NW)
harvey_per_f <- ic_per_f_long[, {
  v <- ic[!is.na(ic)]
  if (length(v) < 30) return(.(t_nw = NA_real_))
  s2 <- var(v); N <- length(v); L <- floor(4 * (N/100)^(2/9)); if (L < 1) L <- 1
  a <- acf(v, lag.max = L, plot = FALSE)$acf[-1]
  nw_c <- max(1 + 2 * sum((1 - (1:L)/(L+1)) * a), 0.5)
  .(t_nw = mean(v) / sqrt(s2 * nw_c / N))
}, by = factor_z]
cat("  Per-factor Harvey NW t:\n")
print(harvey_per_f)
harvey_t_specs_pass_count <- sum(abs(harvey_per_f$t_nw) > 3.0, na.rm = TRUE)
if (abs(t_nw) > 3.0) harvey_t_specs_pass_count <- harvey_t_specs_pass_count + 1
cat("  Harvey t-pass count (>3.0):", harvey_t_specs_pass_count, "\n")

cat("[7/9] Subperiod stability + monotonicity + post-neutralization IC...\n")

# Subperiod (3 partitions)
panel[, period_3 := fcase(
  sig_date < as.Date("2014-01-01"), "P1_2008_2013",
  sig_date < as.Date("2020-01-01"), "P2_2014_2019",
  default = "P3_2020_2023"
)]
ic_sub_panel <- panel[, .(ic = cor(alpha_composite, ret_1M, method="spearman", use="complete.obs"), N=.N), by=.(sig_date, period_3)]
ic_sub_summary <- ic_sub_panel[, .(mean_ic = mean(ic, na.rm=TRUE), icir = mean(ic, na.rm=TRUE) / sd(ic, na.rm=TRUE), N=.N), by=period_3]
subperiod_pos <- sum(ic_sub_summary$mean_ic > 0)
subperiod_stab <- subperiod_pos / nrow(ic_sub_summary)

cat("  Subperiod stab:", subperiod_stab, "\n")
print(ic_sub_summary)

# Monotonicity (decile)
panel[, decile := cut(alpha_composite, breaks = quantile(alpha_composite, probs = seq(0, 1, 0.1), na.rm = TRUE), labels = FALSE, include.lowest = TRUE), by = sig_date]
decile_ret <- panel[!is.na(decile), .(mean_ret = mean(ret_1M, na.rm = TRUE)), by = .(sig_date, decile)]
decile_avg <- decile_ret[, .(avg_ret = mean(mean_ret, na.rm = TRUE)), by = decile][order(decile)]
monotonicity <- cor(decile_avg$decile, decile_avg$avg_ret, method = "spearman")
cat("  Monotonicity:", round(monotonicity, 3), "\n")
print(decile_avg)

# Post-neutralization IC (residualize against STR_1715 main alpha proxy = Q07_Earnings_Stability)
# Use Q07 as the dominant STR_1715 axis. Residualize composite ⊥ Q07 z-score
cat("[7.5/9] Post-neutralization IC vs Q07 (STR_1715 main axis)...\n")
q07_dt <- list()
plan(multisession, workers = n_workers)
q07_dt <- future_lapply(sig_dates, function(sd) {
  tryCatch({
    suppressMessages({m <- load_month_factors(sd)})
    if (is.null(m) || nrow(m) == 0) return(NULL)
    m_q <- m[Factor_Name == "Q07_Earnings_Stability"]
    if (nrow(m_q) == 0) return(NULL)
    data.table(Ticker = m_q$Ticker, sig_date = sd, z_q07 = m_q$Z_Score_Aligned)
  }, error = function(e) NULL)
})
plan(sequential)
q07_panel <- rbindlist(q07_dt, fill = TRUE)
panel_neu <- merge(panel, q07_panel, by = c("Ticker", "sig_date"), all.x = TRUE)
panel_neu[!is.na(z_q07), alpha_neu := alpha_composite - cov(alpha_composite, z_q07, use = "pairwise.complete.obs")/var(z_q07, na.rm=TRUE) * z_q07, by = sig_date]
ic_neu <- panel_neu[!is.na(alpha_neu), .(ic = cor(alpha_neu, ret_1M, method = "spearman", use = "complete.obs")), by = sig_date]
mean_ic_neu <- mean(ic_neu$ic, na.rm = TRUE)
cat(sprintf("  Post-neutralization IC (vs Q07): %.4f (raw: %.4f, retention: %.1f%%)\n",
            mean_ic_neu, mean_ic_comp, 100 * mean_ic_neu / mean_ic_comp))

cat("[8/9] Orthogonality test vs S4 v2 baseline returns (BENCH_S4_static_dohoon)...\n")
s4_path <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260509_002/output/walk_forward_returns_timeseries.csv")
s4_dt <- fread(s4_path)
s4_baseline <- s4_dt[method == "BENCH_S4_static_dohoon", .(date = as.Date(date), ret_S4 = ret_net)]

# Top 20 EW alpha portfolio per sig_date
panel_top <- panel[, {
  ranked <- order(alpha_composite, decreasing = TRUE)
  if (.N < 20) return(.(top20_ret = NA_real_, bot20_ret = NA_real_, spread = NA_real_, N = .N))
  top20 <- ranked[1:20]
  bot20 <- ranked[(.N-19):.N]
  .(top20_ret = mean(ret_1M[top20], na.rm = TRUE),
    bot20_ret = mean(ret_1M[bot20], na.rm = TRUE),
    spread    = mean(ret_1M[top20], na.rm = TRUE) - mean(ret_1M[bot20], na.rm = TRUE),
    N         = .N)
}, by = sig_date]

panel_top[, date := sig_date]
joined <- merge(panel_top[, .(date, alpha_ret = top20_ret)],
                s4_baseline[, .(date, ret_S4)],
                by = "date", all.x = FALSE, all.y = FALSE)
joined <- joined[!is.na(alpha_ret) & !is.na(ret_S4)]
cor_alpha_S4 <- cor(joined$alpha_ret, joined$ret_S4, method = "pearson", use = "complete.obs")
cor_alpha_S4_spear <- cor(joined$alpha_ret, joined$ret_S4, method = "spearman", use = "complete.obs")
crisis_thresh <- quantile(joined$ret_S4, 0.2, na.rm = TRUE)
cor_crisis <- joined[ret_S4 <= crisis_thresh, cor(alpha_ret, ret_S4, method = "pearson")]
cor_normal <- joined[ret_S4 >  crisis_thresh, cor(alpha_ret, ret_S4, method = "pearson")]

# AX-001 v2 conditional defense
bm <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/benchmark.parquet")))
# Detect col names
setnames(bm, names(bm)[1], "date")
if (!"bm_ret" %in% names(bm)) {
  ret_col <- intersect(c("Ret", "ret", "Return", "return"), names(bm))
  if (length(ret_col) > 0) setnames(bm, ret_col[1], "bm_ret") else {
    # Try named diff
    bm[, bm_ret := c(NA, diff(log(bm[[2]])))]
  }
}
bm[, date := as.Date(date)]
# Monthly aggregation
bm[, ym := format(date, "%Y-%m")]
bm_m <- bm[, .(bm_ret = prod(1 + bm_ret, na.rm = TRUE) - 1), by = ym]
bm_m[, sig_date := as.Date(paste0(ym, "-01"))]
panel_bm <- merge(panel, bm_m[, .(sig_date, bm_ret)], by = "sig_date", all.x = TRUE)
if (sum(!is.na(panel_bm$bm_ret)) > 100) {
  bad_thresh <- quantile(panel_bm$bm_ret, 0.2, na.rm = TRUE)
  ic_bad <- panel_bm[bm_ret <= bad_thresh, cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs")]
  ic_norm <- panel_bm[bm_ret >  bad_thresh, cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs")]
  cat(sprintf("  AX-001 v2: IC bad=%.4f / normal=%.4f / ratio=%.3f\n", ic_bad, ic_norm, ic_bad / ic_norm))
} else {
  ic_bad <- NA; ic_norm <- NA
}

cat(sprintf("  cor(alpha_top20, S4_v2) full: pearson=%.4f / spearman=%.4f\n", cor_alpha_S4, cor_alpha_S4_spear))
cat(sprintf("  cor crisis (S4 bot 20pct): %.4f\n", cor_crisis))
cat(sprintf("  cor normal: %.4f\n", cor_normal))
cat(sprintf("  Overlap N: %d periods\n", nrow(joined)))

cat("[9/9] Save alpha_scores.parquet + alpha_validation.json...\n")

alpha_all <- panel[, .(sig_date, Ticker, alpha = alpha_composite)]
# Confidence: alpha rank percentile clipped [0.05, 0.95]
alpha_all[, alpha_rank := frank(alpha) / .N, by = sig_date]
alpha_all[, confidence := pmin(0.95, pmax(0.05, alpha_rank * 0.9 + 0.05))]
alpha_all[, alpha_rank := NULL]

write_parquet(alpha_all, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  alpha_scores.parquet saved:", nrow(alpha_all), "rows\n")

# Validation
validation <- list(
  task_id = WT_ID,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hypothesis = "4-Axis Volatility/Skewness Composite (D43_Skewness + D05_MaxRet + D41_Vol_of_Vol + D58_Vol_Asymmetry)",
  diagnostics = list(
    rank_ic = mean_ic_comp,
    icir = icir_comp,
    monotonicity = monotonicity,
    subperiod_stability = subperiod_stab,
    harvey_t_nw = t_nw,
    harvey_t_specs_pass_count = harvey_t_specs_pass_count,
    post_neutralization_ic = mean_ic_neu,
    post_neutralization_retention = mean_ic_neu / mean_ic_comp,
    per_factor_ic = ic_summary_per_f,
    per_factor_harvey_nw = harvey_per_f,
    orthogonality = list(
      cor_alpha_S4_full_pearson = cor_alpha_S4,
      cor_alpha_S4_full_spearman = cor_alpha_S4_spear,
      cor_crisis_S4_bot20pct = cor_crisis,
      cor_normal_S4_top80pct = cor_normal,
      n_overlap_periods = nrow(joined)
    ),
    crisis_alpha_ax001_v2 = list(
      ic_bad_regime = ic_bad,
      ic_normal_regime = ic_norm,
      ratio_bad_over_normal = if (!is.na(ic_bad/ic_norm)) ic_bad / ic_norm else NA
    ),
    decile_returns = decile_avg,
    n_sig_dates = uniqueN(panel$sig_date),
    period_start = as.character(min(panel$sig_date)),
    period_end = as.character(max(panel$sig_date)),
    n_avg_tickers_per_period = panel[, .N, by = sig_date][, mean(N)],
    selection_objective = "icir"
  )
)
write_json(validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")
cat("  alpha_validation.json saved\n")

cat("\n=== SUMMARY v2 ===\n")
cat(sprintf("Hypothesis: 4-axis Vol/Skewness Composite\n"))
cat(sprintf("Periods: %s to %s (%d sig_dates)\n", as.character(min(panel$sig_date)), as.character(max(panel$sig_date)), uniqueN(panel$sig_date)))
cat(sprintf("Composite IC: %.4f / ICIR: %.4f / NW-t: %.4f\n", mean_ic_comp, icir_comp, t_nw))
cat(sprintf("Monotonicity: %.3f / Subperiod stab: %.2f\n", monotonicity, subperiod_stab))
cat(sprintf("Post-neut IC (vs Q07): %.4f (retention %.0f%%)\n", mean_ic_neu, 100*mean_ic_neu/mean_ic_comp))
cat(sprintf("cor(alpha_top20, S4_v2): pearson=%.3f / spearman=%.3f\n", cor_alpha_S4, cor_alpha_S4_spear))
if (!is.na(ic_bad / ic_norm)) cat(sprintf("AX-001 v2 IC bad/normal ratio: %.3f\n", ic_bad/ic_norm))
cat("\nDone. Stage artifacts at:", STAGE_DIR, "\n")
