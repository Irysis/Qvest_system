# =============================================================================
# WT-D20260511_001 Alpha Research v4 — PIT-Strict Expanding Direction Align
# =============================================================================
# v2 issue: full-sample sign(mean_ic) align = C1 violation
# v3 issue: factor_ic_monthly.parquet 부재 → Factor DB Z_Score_Aligned가 default
#   higher_better로 작동 → 4 factor의 lottery effect (high vol = low return)
#   direction 무시 → IC = -0.126
# v4 fix: 본 script에서 expanding IC 직접 계산 (sig_date 이전 IC만 사용) →
#   direction align → composite 합성 → forward 1M return 측정
#
# 결과: v4 IC는 v2와 유사하지만 C1 strict (no look-ahead) 보장
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

cat("[1/9] PIT-strict expanding alignment...\n")
SIGNAL_CUTOFF <- as.Date("2023-12-22")
# Burn-in: first 36m for expanding IC computation (학술 일반 burn-in = 24~36m)
BURN_IN_MONTHS <- 36L
sig_dates <- seq.Date(as.Date("2008-01-01"), SIGNAL_CUTOFF, by = "month")
sig_dates <- as.Date(format(sig_dates, "%Y-%m-01"))

SELECTED_FACTORS <- c("D43_Skewness", "D05_MaxRet", "D41_Vol_of_Vol", "D58_Vol_Asymmetry")

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
cat("  Panel rows:", nrow(panel), "\n")

# Universe filter
cat("[2/9] Universe + liquidity filter...\n")
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setnames(rd, "Date", "date")
rd <- rd[date >= as.Date("2007-01-01") & date <= as.Date("2026-04-30")]
rd[, ADV_KRW := Close * Vol]
setkey(rd, Ticker, date)
rd[, ADV_20d := frollmean(ADV_KRW, n = 20L, align = "right", fill = NA), by = Ticker]

trade_days <- sort(unique(rd$date))
sig_date_dt <- data.table(sig_date = sig_dates)
sig_date_dt[, pit_t1_day := sapply(sig_date, function(d) {
  cand <- trade_days[trade_days < d]
  if (length(cand) > 0) as.character(max(cand)) else NA_character_
})]
sig_date_dt[, pit_t1_day := as.Date(pit_t1_day)]

rd_snap <- rd[, .(date, Ticker, K200, KQ150, ADV_20d)]
setkey(rd_snap, date, Ticker)
universe_list <- lapply(seq_len(nrow(sig_date_dt)), function(i) {
  d <- sig_date_dt[i]$pit_t1_day
  if (is.na(d)) return(NULL)
  snap <- rd_snap[date == d]
  if (nrow(snap) == 0) return(NULL)
  snap[, eligible := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
  snap[, liquid_ok := !is.na(ADV_20d) & ADV_20d >= 2e8]
  snap_e <- snap[eligible == TRUE & liquid_ok == TRUE]
  if (nrow(snap_e) == 0) return(NULL)
  snap_e[, sig_date := sig_date_dt[i]$sig_date]
  snap_e[, .(sig_date, Ticker)]
})
universe <- rbindlist(universe_list)
panel <- merge(panel, universe, by = c("sig_date", "Ticker"))
cat("  After universe filter:", nrow(panel), "\n")

cat("[3/9] Forward 1M return + 1M IC computation per sig_date...\n")
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
cat("  After ret-merge + NA-drop:", nrow(panel), "\n")

# Compute monthly IC for each (sig_date, factor) using forward 1M return
# This is the IC for that sig_date — to be used in EXPANDING (sig_date+1, sig_date+2, ...)
ic_per_sig <- panel[, .(
  ic_D43 = cor(D43_Skewness, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D05 = cor(D05_MaxRet, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D41 = cor(D41_Vol_of_Vol, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D58 = cor(D58_Vol_Asymmetry, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
setkey(ic_per_sig, sig_date)
cat("  IC per sig_date computed:", nrow(ic_per_sig), "rows\n")
cat("  Sample IC:\n")
print(head(ic_per_sig, 5))

cat("[4/9] Expanding direction sign per sig_date (PIT-safe: use only sig_date-1 history)...\n")
# For each sig_date_t, direction sign for factor f = sign(mean of ic[sig_date < sig_date_t])
# during burn-in (first BURN_IN periods), direction = registry default (default higher_better → +1)
ic_per_sig_sorted <- ic_per_sig[order(sig_date)]

# Compute expanding mean IC PER FACTOR per sig_date (excludes current sig_date IC)
expanding_dir <- data.table(sig_date = ic_per_sig_sorted$sig_date)
for (f_col in c("ic_D43", "ic_D05", "ic_D41", "ic_D58")) {
  factor_name <- gsub("ic_", "", f_col)
  vec_ic <- ic_per_sig_sorted[[f_col]]
  # Expanding (cumulative) mean, lag 1 (exclude current period to avoid look-ahead)
  cum_n <- cumsum(!is.na(vec_ic))
  cum_sum <- cumsum(ifelse(is.na(vec_ic), 0, vec_ic))
  # mean(IC[1:t-1]) for period t (lag1)
  cum_mean_lag1 <- shift(cum_sum / pmax(cum_n, 1), 1, fill = NA)
  cum_n_lag1 <- shift(cum_n, 1, fill = 0)
  # If sufficient history (>=BURN_IN), use sign(mean); else fallback +1
  dir_signs <- ifelse(cum_n_lag1 >= BURN_IN_MONTHS,
                      ifelse(cum_mean_lag1 >= 0, 1L, -1L),
                      1L)  # fallback +1 = "higher_better" assumption
  expanding_dir[, paste0("dir_", factor_name) := dir_signs]
}
cat("  Expanding direction signs (sample first 5 + last 5):\n")
print(head(expanding_dir, 5))
print(tail(expanding_dir, 5))

cat("[5/9] Merge expanding direction → aligned composite alpha...\n")
panel <- merge(panel, expanding_dir, by = "sig_date", all.x = TRUE)

# Aligned z-score (z * direction)
panel[, D43_aligned := D43_Skewness * dir_D43]
panel[, D05_aligned := D05_MaxRet * dir_D05]
panel[, D41_aligned := D41_Vol_of_Vol * dir_D41]
panel[, D58_aligned := D58_Vol_Asymmetry * dir_D58]

# Composite
panel[, alpha_composite := (D43_aligned + D05_aligned + D41_aligned + D58_aligned) / 4]

# DROP burn-in (no direction available)
panel_eval <- panel[sig_date >= sig_dates[BURN_IN_MONTHS + 1]]
cat("  After burn-in drop (eval period):", nrow(panel_eval), "\n")
cat("  Eval period: ", as.character(min(panel_eval$sig_date)), "to", as.character(max(panel_eval$sig_date)), "\n")

cat("[6/9] Composite IC + ICIR + Harvey NW-t (PIT-strict expanding align)...\n")
ic_eval <- panel_eval[, .(ic = cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs"), N = .N), by = sig_date]
mean_ic <- mean(ic_eval$ic, na.rm = TRUE)
sd_ic <- sd(ic_eval$ic, na.rm = TRUE)
icir <- mean_ic / sd_ic
ic_vec <- ic_eval$ic[!is.na(ic_eval$ic)]
N <- length(ic_vec); sigma2 <- var(ic_vec); L <- floor(4 * (N/100)^(2/9)); if (L < 1) L <- 1
acf_v <- acf(ic_vec, lag.max = L, plot = FALSE)$acf[-1]
nw_c <- max(1 + 2 * sum((1 - (1:L)/(L+1)) * acf_v), 0.5)
t_nw <- mean_ic / sqrt(sigma2 * nw_c / N)

# Per-factor IC + Harvey t (post-alignment)
ic_per_factor_aligned <- panel_eval[, .(
  ic_D43 = cor(D43_aligned, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D05 = cor(D05_aligned, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D41 = cor(D41_aligned, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D58 = cor(D58_aligned, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
ic_per_f_long <- melt(ic_per_factor_aligned, id.vars = "sig_date", variable.name = "factor", value.name = "ic")
ic_per_f_summary <- ic_per_f_long[, .(mean_ic = mean(ic, na.rm = TRUE), sd_ic = sd(ic, na.rm = TRUE), icir = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE)), by = factor]
harvey_per_f <- ic_per_f_long[, {
  v <- ic[!is.na(ic)]
  if (length(v) < 30) return(.(t_nw = NA_real_))
  s2 <- var(v); Nf <- length(v); Lf <- floor(4 * (Nf/100)^(2/9)); if (Lf < 1) Lf <- 1
  a <- acf(v, lag.max = Lf, plot = FALSE)$acf[-1]
  nw_c2 <- max(1 + 2 * sum((1 - (1:Lf)/(Lf+1)) * a), 0.5)
  .(t_nw = mean(v) / sqrt(s2 * nw_c2 / Nf))
}, by = factor]

harvey_t_specs_pass_count <- sum(abs(harvey_per_f$t_nw) > 3.0, na.rm = TRUE)
if (abs(t_nw) > 3.0) harvey_t_specs_pass_count <- harvey_t_specs_pass_count + 1

cat(sprintf("  Eval composite IC: %.4f / ICIR: %.4f / NW-t: %.4f\n", mean_ic, icir, t_nw))
cat("  Per-factor (aligned):\n"); print(ic_per_f_summary)
cat("  Per-factor Harvey NW-t:\n"); print(harvey_per_f)
cat("  Harvey t-pass count (>3.0):", harvey_t_specs_pass_count, "\n")

cat("[7/9] Subperiod + monotonicity + post-neutralization vs Q07...\n")
panel_eval[, period_3 := fcase(
  sig_date < as.Date("2014-01-01"), "P1_2011_2013",
  sig_date < as.Date("2020-01-01"), "P2_2014_2019",
  default = "P3_2020_2023"
)]
ic_sub <- panel_eval[, .(ic = cor(alpha_composite, ret_1M, method="spearman", use="complete.obs"), N=.N), by=.(sig_date, period_3)]
ic_sub_s <- ic_sub[, .(mean_ic = mean(ic, na.rm=TRUE), icir = mean(ic, na.rm=TRUE) / sd(ic, na.rm=TRUE)), by=period_3]
subperiod_pos <- sum(ic_sub_s$mean_ic > 0)
subperiod_stab <- subperiod_pos / nrow(ic_sub_s)
print(ic_sub_s)

panel_eval[, decile := cut(alpha_composite, breaks = quantile(alpha_composite, probs = seq(0, 1, 0.1), na.rm = TRUE), labels = FALSE, include.lowest = TRUE), by = sig_date]
decile_ret <- panel_eval[!is.na(decile), .(mean_ret = mean(ret_1M, na.rm = TRUE)), by = .(sig_date, decile)]
decile_avg <- decile_ret[, .(avg_ret = mean(mean_ret, na.rm = TRUE)), by = decile][order(decile)]
monotonicity <- cor(decile_avg$decile, decile_avg$avg_ret, method = "spearman")
cat("  Subperiod stab:", subperiod_stab, "  Monotonicity:", round(monotonicity, 3), "\n")
print(decile_avg)

# Post-neutralization vs Q07
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
cat(sprintf("  Post-neut IC (vs Q07): %.4f (raw %.4f, retention %.0f%%)\n", mean_ic_neu, mean_ic, 100*mean_ic_neu/mean_ic))

cat("[8/9] Orthogonality vs S4 v2 + AX-001 v2...\n")
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
cor_normal <- joined[ret_S4 >  ct, cor(alpha_ret, ret_S4, method = "pearson")]
top20_sharpe <- mean(joined$alpha_ret) * 12 / (sd(joined$alpha_ret) * sqrt(12))
top20_ret_ann <- mean(joined$alpha_ret) * 12

bm_path <- file.path(PROJ_ROOT, ".cache/benchmark.parquet")
ic_bad <- NA; ic_norm <- NA
if (file.exists(bm_path)) {
  bm <- tryCatch(as.data.table(read_parquet(bm_path)), error = function(e) NULL)
  if (!is.null(bm)) {
    setnames(bm, names(bm)[1], "date")
    bm[, date := as.Date(date)]
    rc <- intersect(c("Ret", "ret", "BM_Ret", "return"), names(bm))
    if (length(rc) > 0) setnames(bm, rc[1], "bm_ret")
    if ("bm_ret" %in% names(bm)) {
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
}

cat(sprintf("  Top20 EW Sharpe: %.3f / Ret_ann: %.2f%%\n", top20_sharpe, top20_ret_ann*100))
cat(sprintf("  cor S4_v2 full: pearson=%.4f / spearman=%.4f\n", cor_full_p, cor_full_s))
cat(sprintf("  cor crisis (S4 bot 20pct): %.4f / normal: %.4f\n", cor_crisis, cor_normal))
cat(sprintf("  AX-001 v2 IC bad/normal: bad=%.4f / norm=%.4f / ratio=%.3f\n",
            ifelse(is.na(ic_bad), NA, ic_bad), ifelse(is.na(ic_norm), NA, ic_norm), ifelse(is.na(ic_bad/ic_norm), NA, ic_bad/ic_norm)))

cat("[9/9] Save artifacts...\n")
alpha_all <- panel_eval[, .(sig_date, Ticker, alpha = alpha_composite)]
alpha_all[, alpha_rank := frank(alpha) / .N, by = sig_date]
alpha_all[, confidence := pmin(0.95, pmax(0.05, alpha_rank * 0.9 + 0.05))]
alpha_all[, alpha_rank := NULL]
write_parquet(alpha_all, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  alpha_scores.parquet:", nrow(alpha_all), "rows\n")

validation <- list(
  task_id = WT_ID, version = "v4_expanding_align_pit_strict",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hypothesis = "4-Axis Vol/Skewness Composite (D43+D05+D41+D58) — Expanding Direction Align PIT-Strict",
  pit_compliance_check = list(
    c1_no_full_sample_align = TRUE,
    z_score_source = "Factor DB Z_Score_Aligned (already PIT-safe expanding)",
    direction_alignment = "Expanding mean IC sign (sig_date-1 lag) with 36-month burn-in",
    burn_in_months = BURN_IN_MONTHS,
    composite_method = "equal-weight aligned (no IC sign multiply at full-sample)",
    cutoff = as.character(SIGNAL_CUTOFF)
  ),
  diagnostics = list(
    rank_ic = mean_ic, icir = icir,
    monotonicity = monotonicity,
    subperiod_stability = subperiod_stab,
    harvey_t_nw = t_nw,
    harvey_t_specs_pass_count = harvey_t_specs_pass_count,
    per_factor_ic = ic_per_f_summary,
    per_factor_harvey_nw = harvey_per_f,
    post_neutralization_ic = mean_ic_neu,
    post_neutralization_retention = mean_ic_neu / mean_ic,
    orthogonality = list(
      cor_alpha_S4_full_pearson = cor_full_p,
      cor_alpha_S4_full_spearman = cor_full_s,
      cor_crisis_S4_bot20pct = cor_crisis,
      cor_normal_S4_top80pct = cor_normal,
      n_overlap_periods = nrow(joined),
      top20_portfolio_sharpe_ann = top20_sharpe,
      top20_portfolio_ret_ann = top20_ret_ann
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
    n_avg_tickers_per_period = panel_eval[, .N, by = sig_date][, mean(N)],
    selection_objective = "icir"
  )
)
write_json(validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")

cat("\n=== SUMMARY v4 PIT-STRICT EXPANDING ALIGN ===\n")
cat(sprintf("Eval period: %s to %s (%d sig_dates, post burn-in)\n", as.character(min(panel_eval$sig_date)), as.character(max(panel_eval$sig_date)), uniqueN(panel_eval$sig_date)))
cat(sprintf("Composite IC: %.4f / ICIR: %.4f / NW-t: %.4f\n", mean_ic, icir, t_nw))
cat(sprintf("Monotonicity: %.3f / Subperiod stab: %.2f\n", monotonicity, subperiod_stab))
cat(sprintf("Post-neut IC vs Q07: %.4f (retention %.0f%%)\n", mean_ic_neu, 100*mean_ic_neu/mean_ic))
cat(sprintf("cor(alpha_top20, S4_v2): pearson=%.3f / spearman=%.3f\n", cor_full_p, cor_full_s))
cat(sprintf("AX-001 v2 IC bad/normal: %.3f\n", ifelse(is.na(ic_bad/ic_norm), NA, ic_bad/ic_norm)))
cat(sprintf("Top20 Sharpe: %.3f, ret_ann: %.2f%%\n", top20_sharpe, top20_ret_ann*100))
cat("Done.\n")
