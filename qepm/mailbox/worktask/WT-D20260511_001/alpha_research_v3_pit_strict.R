# =============================================================================
# WT-D20260511_001 Alpha Research v3 — PIT-Strict (No Look-Ahead Direction Align)
# =============================================================================
# v2 issue: 본 script에서 `sign(mean_ic)` direction align는 full-sample IC sign
#   사용 → C1 violation 가능.
# v3 fix: Factor DB Z_Score_Aligned는 이미 expanding PIT-safe align됨.
#   본 script의 추가 sign(mean_ic) multiply 제거.
#   Z_Score_Aligned 그대로 composite avg → IC 재측정.
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

cat("[1/8] PIT-strict reload (no full-sample direction align)...\n")
SIGNAL_CUTOFF <- as.Date("2023-12-22")
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

cat("[2/8] Universe filter (KOSPI200 ∪ KOSDAQ150 + ADV ≥ 2e8)...\n")
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
cat("  Universe-eligible obs:", nrow(universe), "  avg/period:", round(nrow(universe) / uniqueN(universe$sig_date), 1), "\n")
panel <- merge(panel, universe, by = c("sig_date", "Ticker"))
cat("  After universe filter:", nrow(panel), "\n")

cat("[3/8] Forward 1M returns...\n")
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

cat("[4/8] Cross-section composite (NO additional direction align — PIT strict)...\n")
# Factor DB Z_Score_Aligned는 이미 expanding PIT-safe direction align됨
# 본 script는 추가 alignment 없이 그대로 평균 → composite
panel[, alpha_composite := (D43_Skewness + D05_MaxRet + D41_Vol_of_Vol + D58_Vol_Asymmetry) / 4]

cat("[5/8] IC + ICIR + Harvey t (NW)...\n")
ic_per <- panel[, .(ic = cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs"), N = .N),
                by = sig_date]
mean_ic <- mean(ic_per$ic, na.rm = TRUE)
sd_ic <- sd(ic_per$ic, na.rm = TRUE)
icir <- mean_ic / sd_ic

# Per-factor IC (no alignment)
ic_per_f <- panel[, .(
  ic_D43 = cor(D43_Skewness, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D05 = cor(D05_MaxRet, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D41 = cor(D41_Vol_of_Vol, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D58 = cor(D58_Vol_Asymmetry, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
ic_f_long <- melt(ic_per_f, id.vars = "sig_date", variable.name = "factor", value.name = "ic")
ic_f_summary <- ic_f_long[, .(
  mean_ic = mean(ic, na.rm = TRUE),
  sd_ic = sd(ic, na.rm = TRUE),
  icir = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE)
), by = factor]
cat("  Per-factor IC (PIT-strict, no extra align):\n")
print(ic_f_summary)

# NW t-stat for composite
ic_vec <- ic_per$ic[!is.na(ic_per$ic)]
N <- length(ic_vec)
sigma2 <- var(ic_vec)
L <- floor(4 * (N/100)^(2/9)); if (L < 1) L <- 1
acf_v <- acf(ic_vec, lag.max = L, plot = FALSE)$acf[-1]
nw_correction <- max(1 + 2 * sum((1 - (1:L)/(L+1)) * acf_v), 0.5)
var_nw <- sigma2 * nw_correction
t_nw <- mean_ic / sqrt(var_nw / N)

# Per-factor NW t
harvey_per <- ic_f_long[, {
  v <- ic[!is.na(ic)]
  if (length(v) < 30) return(.(t_nw = NA_real_))
  s2 <- var(v); Nf <- length(v); Lf <- floor(4 * (Nf/100)^(2/9)); if (Lf < 1) Lf <- 1
  a <- acf(v, lag.max = Lf, plot = FALSE)$acf[-1]
  nw_c <- max(1 + 2 * sum((1 - (1:Lf)/(Lf+1)) * a), 0.5)
  .(t_nw = mean(v) / sqrt(s2 * nw_c / Nf))
}, by = factor]

harvey_t_specs_pass_count <- sum(abs(harvey_per$t_nw) > 3.0, na.rm = TRUE)
if (abs(t_nw) > 3.0) harvey_t_specs_pass_count <- harvey_t_specs_pass_count + 1

cat(sprintf("  Composite (PIT-strict) IC: %.4f / SD: %.4f / ICIR: %.4f / NW-t: %.4f\n",
            mean_ic, sd_ic, icir, t_nw))
cat("  Per-factor Harvey NW-t:\n"); print(harvey_per)
cat("  Harvey t-pass count (>3.0):", harvey_t_specs_pass_count, "\n")

cat("[6/8] Subperiod + monotonicity...\n")
panel[, period_3 := fcase(
  sig_date < as.Date("2014-01-01"), "P1_2008_2013",
  sig_date < as.Date("2020-01-01"), "P2_2014_2019",
  default = "P3_2020_2023"
)]
ic_sub <- panel[, .(ic = cor(alpha_composite, ret_1M, method="spearman", use="complete.obs"), N=.N), by=.(sig_date, period_3)]
ic_sub_s <- ic_sub[, .(mean_ic = mean(ic, na.rm=TRUE), icir = mean(ic, na.rm=TRUE) / sd(ic, na.rm=TRUE)), by=period_3]
subperiod_pos <- sum(ic_sub_s$mean_ic > 0)
subperiod_stab <- subperiod_pos / nrow(ic_sub_s)
cat("  Subperiod stab:", subperiod_stab, "(", subperiod_pos, "/", nrow(ic_sub_s), ")\n")
print(ic_sub_s)

# Monotonicity
panel[, decile := cut(alpha_composite, breaks = quantile(alpha_composite, probs = seq(0, 1, 0.1), na.rm = TRUE), labels = FALSE, include.lowest = TRUE), by = sig_date]
decile_ret <- panel[!is.na(decile), .(mean_ret = mean(ret_1M, na.rm = TRUE)), by = .(sig_date, decile)]
decile_avg <- decile_ret[, .(avg_ret = mean(mean_ret, na.rm = TRUE)), by = decile][order(decile)]
monotonicity <- cor(decile_avg$decile, decile_avg$avg_ret, method = "spearman")
cat("  Monotonicity:", round(monotonicity, 3), "\n")
print(decile_avg)

cat("[7/8] Orthogonality vs S4 v2 baseline + AX-001 v2...\n")
s4_path <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260509_002/output/walk_forward_returns_timeseries.csv")
s4_dt <- fread(s4_path)
s4_b <- s4_dt[method == "BENCH_S4_static_dohoon", .(date = as.Date(date), ret_S4 = ret_net)]

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
                s4_b[, .(date, ret_S4)], by = "date")
joined <- joined[!is.na(alpha_ret) & !is.na(ret_S4)]
cor_full_p <- cor(joined$alpha_ret, joined$ret_S4, method = "pearson")
cor_full_s <- cor(joined$alpha_ret, joined$ret_S4, method = "spearman")
ct <- quantile(joined$ret_S4, 0.2, na.rm = TRUE)
cor_crisis <- joined[ret_S4 <= ct, cor(alpha_ret, ret_S4, method = "pearson")]
cor_normal <- joined[ret_S4 >  ct, cor(alpha_ret, ret_S4, method = "pearson")]

# top20 portfolio Sharpe
top20_sharpe <- mean(joined$alpha_ret) * 12 / (sd(joined$alpha_ret) * sqrt(12))
top20_ret_ann <- mean(joined$alpha_ret) * 12

# AX-001 v2 conditional defense
bm <- tryCatch({
  bm_x <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/benchmark.parquet")))
  setnames(bm_x, names(bm_x)[1], "date")
  bm_x[, date := as.Date(date)]
  # detect ret col
  rc <- intersect(c("Ret", "ret", "Return", "return", "BM_Ret"), names(bm_x))
  if (length(rc) > 0) setnames(bm_x, rc[1], "bm_ret")
  bm_x
}, error = function(e) NULL)
if (!is.null(bm) && "bm_ret" %in% names(bm)) {
  bm[, ym := format(date, "%Y-%m")]
  bm_m <- bm[, .(bm_ret = prod(1 + bm_ret, na.rm = TRUE) - 1), by = ym]
  bm_m[, sig_date := as.Date(paste0(ym, "-01"))]
  panel_bm <- merge(panel, bm_m[, .(sig_date, bm_ret)], by = "sig_date", all.x = TRUE)
  if (sum(!is.na(panel_bm$bm_ret)) > 100) {
    bad_thresh <- quantile(panel_bm$bm_ret, 0.2, na.rm = TRUE)
    ic_bad <- panel_bm[bm_ret <= bad_thresh, cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs")]
    ic_norm <- panel_bm[bm_ret >  bad_thresh, cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs")]
  } else { ic_bad <- NA; ic_norm <- NA }
} else { ic_bad <- NA; ic_norm <- NA }

cat(sprintf("  Top20 EW Sharpe annual: %.3f  CAGR-like ret_ann: %.2f%%\n", top20_sharpe, top20_ret_ann*100))
cat(sprintf("  cor(alpha_top20, S4_v2) full: pearson=%.4f / spearman=%.4f\n", cor_full_p, cor_full_s))
cat(sprintf("  cor crisis (S4 bot 20pct): %.4f\n", cor_crisis))
cat(sprintf("  cor normal: %.4f\n", cor_normal))
if (!is.na(ic_bad/ic_norm)) cat(sprintf("  AX-001 v2 IC bad/normal: %.3f (bad=%.4f, norm=%.4f)\n", ic_bad/ic_norm, ic_bad, ic_norm))

cat("[8/8] Save artifacts...\n")
alpha_all <- panel[, .(sig_date, Ticker, alpha = alpha_composite)]
alpha_all[, alpha_rank := frank(alpha) / .N, by = sig_date]
alpha_all[, confidence := pmin(0.95, pmax(0.05, alpha_rank * 0.9 + 0.05))]
alpha_all[, alpha_rank := NULL]
write_parquet(alpha_all, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  alpha_scores.parquet:", nrow(alpha_all), "rows\n")

validation <- list(
  task_id = WT_ID, version = "v3_pit_strict",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hypothesis = "4-Axis Vol/Skewness Composite (D43+D05+D41+D58) — PIT-strict (no full-sample align)",
  pit_compliance_check = list(
    c1_no_full_sample_align = TRUE,
    z_score_source = "Factor DB Z_Score_Aligned (expanding PIT-safe min_months=36, fallback 1-2)",
    composite_method = "equal-weight raw average (no IC sign multiply)",
    cutoff = as.character(SIGNAL_CUTOFF)
  ),
  diagnostics = list(
    rank_ic = mean_ic,
    icir = icir,
    monotonicity = monotonicity,
    subperiod_stability = subperiod_stab,
    harvey_t_nw = t_nw,
    harvey_t_specs_pass_count = harvey_t_specs_pass_count,
    per_factor_ic = ic_f_summary,
    per_factor_harvey_nw = harvey_per,
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
    n_sig_dates = uniqueN(panel$sig_date),
    period_start = as.character(min(panel$sig_date)),
    period_end = as.character(max(panel$sig_date)),
    n_avg_tickers_per_period = panel[, .N, by = sig_date][, mean(N)],
    selection_objective = "icir"
  )
)
write_json(validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")

cat("\n=== SUMMARY v3 PIT-STRICT ===\n")
cat(sprintf("Periods: %s to %s (%d sig_dates)\n", as.character(min(panel$sig_date)), as.character(max(panel$sig_date)), uniqueN(panel$sig_date)))
cat(sprintf("Composite IC: %.4f / ICIR: %.4f / NW-t: %.4f\n", mean_ic, icir, t_nw))
cat(sprintf("Monotonicity: %.3f / Subperiod stab: %.2f\n", monotonicity, subperiod_stab))
cat(sprintf("cor(alpha_top20, S4_v2): pearson=%.3f / spearman=%.3f\n", cor_full_p, cor_full_s))
if (!is.na(ic_bad/ic_norm)) cat(sprintf("AX-001 v2 IC bad/normal ratio: %.3f\n", ic_bad/ic_norm))
cat(sprintf("Top20 portfolio Sharpe annual: %.3f, return ann: %.2f%%\n", top20_sharpe, top20_ret_ann*100))
cat("Done.\n")
