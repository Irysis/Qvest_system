# =============================================================================
# WT-D20260511_001 Alpha Research v5 — Sector-Neutral Robust Check
# =============================================================================
# v4 issue: D05_MaxRet IC 0.307 비현실 강함 → spurious sector/size bias 의심
# v5 fix: per sig_date sector-neutralize each factor + composite, re-measure IC
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

cat("[1/8] Reload + universe filter + sector info...\n")
SIGNAL_CUTOFF <- as.Date("2023-12-22")
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

# Load RAWDATA + sector info
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setnames(rd, "Date", "date")
rd <- rd[date >= as.Date("2007-01-01") & date <= as.Date("2026-04-30")]
rd[, ADV_KRW := Close * Vol]
setkey(rd, Ticker, date)
rd[, ADV_20d := frollmean(ADV_KRW, n = 20L, align = "right", fill = NA), by = Ticker]

# Snapshot universe + sector + market cap at pit_t1_day
trade_days <- sort(unique(rd$date))
sig_date_dt <- data.table(sig_date = sig_dates)
sig_date_dt[, pit_t1_day := sapply(sig_date, function(d) {
  cand <- trade_days[trade_days < d]
  if (length(cand) > 0) as.character(max(cand)) else NA_character_
})]
sig_date_dt[, pit_t1_day := as.Date(pit_t1_day)]

rd_snap <- rd[, .(date, Ticker, K200, KQ150, ADV_20d, Sector, Size)]
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
  snap_e[, .(sig_date, Ticker, Sector, Size)]
})
universe <- rbindlist(universe_list)
panel <- merge(panel, universe, by = c("sig_date", "Ticker"))
cat("  After universe + sector merge:", nrow(panel), "\n")

cat("[2/8] Forward 1M returns...\n")
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
cat("  After ret + sector NA-drop:", nrow(panel), "\n")

cat("[3/8] Expanding direction sign (PIT-safe burn-in 36m)...\n")
ic_per_sig <- panel[, .(
  ic_D43 = cor(D43_Skewness, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D05 = cor(D05_MaxRet, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D41 = cor(D41_Vol_of_Vol, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D58 = cor(D58_Vol_Asymmetry, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
setkey(ic_per_sig, sig_date)

ic_per_sig_sorted <- ic_per_sig[order(sig_date)]
expanding_dir <- data.table(sig_date = ic_per_sig_sorted$sig_date)
for (f_col in c("ic_D43", "ic_D05", "ic_D41", "ic_D58")) {
  factor_name <- gsub("ic_", "", f_col)
  vec_ic <- ic_per_sig_sorted[[f_col]]
  cum_n <- cumsum(!is.na(vec_ic))
  cum_sum <- cumsum(ifelse(is.na(vec_ic), 0, vec_ic))
  cum_mean_lag1 <- shift(cum_sum / pmax(cum_n, 1), 1, fill = NA)
  cum_n_lag1 <- shift(cum_n, 1, fill = 0)
  dir_signs <- ifelse(cum_n_lag1 >= BURN_IN_MONTHS,
                      ifelse(cum_mean_lag1 >= 0, 1L, -1L), 1L)
  expanding_dir[, paste0("dir_", factor_name) := dir_signs]
}
panel <- merge(panel, expanding_dir, by = "sig_date", all.x = TRUE)

panel[, D43_aligned := D43_Skewness * dir_D43]
panel[, D05_aligned := D05_MaxRet * dir_D05]
panel[, D41_aligned := D41_Vol_of_Vol * dir_D41]
panel[, D58_aligned := D58_Vol_Asymmetry * dir_D58]
panel[, alpha_composite := (D43_aligned + D05_aligned + D41_aligned + D58_aligned) / 4]

panel_eval <- panel[sig_date >= sig_dates[BURN_IN_MONTHS + 1]]
cat("  Eval period rows:", nrow(panel_eval), "  N sig_dates:", uniqueN(panel_eval$sig_date), "\n")

cat("[4/8] Sector-neutralize: per sig_date, demean each aligned factor by sector...\n")
# Sector-neutralize: x_neutral = x - mean(x | sector)
panel_eval[, D43_sn := D43_aligned - mean(D43_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel_eval[, D05_sn := D05_aligned - mean(D05_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel_eval[, D41_sn := D41_aligned - mean(D41_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel_eval[, D58_sn := D58_aligned - mean(D58_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel_eval[, alpha_sn := (D43_sn + D05_sn + D41_sn + D58_sn) / 4]

# Size-neutralize (Quintile of Size, demean within quintile)
panel_eval[, size_quintile := cut(Size, breaks = quantile(Size, probs = seq(0, 1, 0.2), na.rm = TRUE), labels = FALSE, include.lowest = TRUE), by = sig_date]
panel_eval[!is.na(size_quintile), D05_sn_sz := D05_sn - mean(D05_sn, na.rm = TRUE), by = .(sig_date, Sector, size_quintile)]

cat("[5/8] Compare IC raw vs sector-neutral vs sector+size neutral...\n")

# Raw (aligned)
ic_raw_per <- panel_eval[, .(ic = cor(alpha_composite, ret_1M, method = "spearman", use = "complete.obs")), by = sig_date]
mean_ic_raw <- mean(ic_raw_per$ic, na.rm = TRUE); icir_raw <- mean_ic_raw / sd(ic_raw_per$ic, na.rm = TRUE)
ic_raw_vec <- ic_raw_per$ic[!is.na(ic_raw_per$ic)]
N <- length(ic_raw_vec); s2 <- var(ic_raw_vec); L <- floor(4 * (N/100)^(2/9)); if (L < 1) L <- 1
a <- acf(ic_raw_vec, lag.max = L, plot = FALSE)$acf[-1]
nw_c_raw <- max(1 + 2 * sum((1 - (1:L)/(L+1)) * a), 0.5)
t_nw_raw <- mean_ic_raw / sqrt(s2 * nw_c_raw / N)

# Sector-neutral
ic_sn_per <- panel_eval[, .(ic = cor(alpha_sn, ret_1M, method = "spearman", use = "complete.obs")), by = sig_date]
mean_ic_sn <- mean(ic_sn_per$ic, na.rm = TRUE); icir_sn <- mean_ic_sn / sd(ic_sn_per$ic, na.rm = TRUE)
ic_sn_vec <- ic_sn_per$ic[!is.na(ic_sn_per$ic)]
s2 <- var(ic_sn_vec); a <- acf(ic_sn_vec, lag.max = L, plot = FALSE)$acf[-1]
nw_c_sn <- max(1 + 2 * sum((1 - (1:L)/(L+1)) * a), 0.5)
t_nw_sn <- mean_ic_sn / sqrt(s2 * nw_c_sn / N)

# Per-factor sector-neutral IC
ic_per_sn <- panel_eval[, .(
  D43 = cor(D43_sn, ret_1M, method = "spearman", use = "complete.obs"),
  D05 = cor(D05_sn, ret_1M, method = "spearman", use = "complete.obs"),
  D41 = cor(D41_sn, ret_1M, method = "spearman", use = "complete.obs"),
  D58 = cor(D58_sn, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
ic_per_sn_long <- melt(ic_per_sn, id.vars = "sig_date", variable.name = "factor", value.name = "ic")
ic_per_sn_summary <- ic_per_sn_long[, .(mean_ic = mean(ic, na.rm = TRUE), icir = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE)), by = factor]

cat("\nRAW (aligned, no neutralization):\n")
cat(sprintf("  Composite IC: %.4f / ICIR: %.4f / NW-t: %.4f\n", mean_ic_raw, icir_raw, t_nw_raw))

cat("\nSECTOR-NEUTRAL:\n")
cat(sprintf("  Composite IC: %.4f / ICIR: %.4f / NW-t: %.4f\n", mean_ic_sn, icir_sn, t_nw_sn))
cat("  Per-factor sector-neutral IC:\n")
print(ic_per_sn_summary)

# IC retention sector-neutralized / raw
cat(sprintf("\n  IC retention (sector-neutral / raw): %.1f%%\n", 100 * mean_ic_sn / mean_ic_raw))

cat("[6/8] Subperiod + monotonicity for sector-neutral composite...\n")
panel_eval[, period_3 := fcase(
  sig_date < as.Date("2014-01-01"), "P1_2011_2013",
  sig_date < as.Date("2020-01-01"), "P2_2014_2019",
  default = "P3_2020_2023"
)]
ic_sub_sn <- panel_eval[, .(ic = cor(alpha_sn, ret_1M, method="spearman", use="complete.obs"), N=.N), by=.(sig_date, period_3)]
ic_sub_sn_s <- ic_sub_sn[, .(mean_ic = mean(ic, na.rm=TRUE), icir = mean(ic, na.rm=TRUE) / sd(ic, na.rm=TRUE)), by=period_3]
subperiod_pos <- sum(ic_sub_sn_s$mean_ic > 0)
subperiod_stab_sn <- subperiod_pos / nrow(ic_sub_sn_s)

panel_eval[, decile_sn := cut(alpha_sn, breaks = quantile(alpha_sn, probs = seq(0, 1, 0.1), na.rm = TRUE), labels = FALSE, include.lowest = TRUE), by = sig_date]
decile_ret_sn <- panel_eval[!is.na(decile_sn), .(mean_ret = mean(ret_1M, na.rm = TRUE)), by = .(sig_date, decile_sn)]
decile_avg_sn <- decile_ret_sn[, .(avg_ret = mean(mean_ret, na.rm = TRUE)), by = decile_sn][order(decile_sn)]
mono_sn <- cor(decile_avg_sn$decile_sn, decile_avg_sn$avg_ret, method = "spearman")

cat(sprintf("  Sector-neutral: Subperiod stab=%.2f, Monotonicity=%.3f\n", subperiod_stab_sn, mono_sn))
print(ic_sub_sn_s)
print(decile_avg_sn)

cat("[7/8] Orthogonality + AX-001 v2 for sector-neutral...\n")
s4_dt <- fread(file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260509_002/output/walk_forward_returns_timeseries.csv"))
s4_b <- s4_dt[method == "BENCH_S4_static_dohoon", .(date = as.Date(date), ret_S4 = ret_net)]
panel_top_sn <- panel_eval[, {
  ranked <- order(alpha_sn, decreasing = TRUE)
  if (.N < 20) return(.(top20_ret = NA_real_))
  top20 <- ranked[1:20]
  .(top20_ret = mean(ret_1M[top20], na.rm = TRUE))
}, by = sig_date]
panel_top_sn[, date := sig_date]
joined_sn <- merge(panel_top_sn[, .(date, alpha_ret = top20_ret)], s4_b[, .(date, ret_S4)], by = "date")
joined_sn <- joined_sn[!is.na(alpha_ret) & !is.na(ret_S4)]
cor_full_p_sn <- cor(joined_sn$alpha_ret, joined_sn$ret_S4, method = "pearson")
cor_full_s_sn <- cor(joined_sn$alpha_ret, joined_sn$ret_S4, method = "spearman")
ct <- quantile(joined_sn$ret_S4, 0.2, na.rm = TRUE)
cor_crisis_sn <- joined_sn[ret_S4 <= ct, cor(alpha_ret, ret_S4, method = "pearson")]
cor_normal_sn <- joined_sn[ret_S4 > ct, cor(alpha_ret, ret_S4, method = "pearson")]
sharpe_sn <- mean(joined_sn$alpha_ret) * 12 / (sd(joined_sn$alpha_ret) * sqrt(12))
ret_ann_sn <- mean(joined_sn$alpha_ret) * 12

cat(sprintf("  Sector-neutral top20 Sharpe: %.3f / Ret_ann: %.2f%%\n", sharpe_sn, ret_ann_sn*100))
cat(sprintf("  cor S4_v2 full: pearson=%.4f / spearman=%.4f\n", cor_full_p_sn, cor_full_s_sn))
cat(sprintf("  cor crisis: %.4f / normal: %.4f\n", cor_crisis_sn, cor_normal_sn))

# AX-001 v2
bm <- tryCatch(as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/benchmark.parquet"))), error = function(e) NULL)
ic_bad_sn <- NA; ic_norm_sn <- NA
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
      ic_bad_sn <- panel_bm[bm_ret <= bt, cor(alpha_sn, ret_1M, method = "spearman", use = "complete.obs")]
      ic_norm_sn <- panel_bm[bm_ret >  bt, cor(alpha_sn, ret_1M, method = "spearman", use = "complete.obs")]
    }
  }
}
cat(sprintf("  AX-001 v2 sector-neutral IC bad/normal: bad=%.4f / norm=%.4f / ratio=%.3f\n",
            ifelse(is.na(ic_bad_sn), NA, ic_bad_sn), ifelse(is.na(ic_norm_sn), NA, ic_norm_sn),
            ifelse(is.na(ic_bad_sn/ic_norm_sn), NA, ic_bad_sn/ic_norm_sn)))

cat("[8/8] Save alpha_scores.parquet (sector-neutral version)...\n")
alpha_all <- panel_eval[, .(sig_date, Ticker, alpha = alpha_sn)]
alpha_all[, alpha_rank := frank(alpha) / .N, by = sig_date]
alpha_all[, confidence := pmin(0.95, pmax(0.05, alpha_rank * 0.9 + 0.05))]
alpha_all[, alpha_rank := NULL]
write_parquet(alpha_all, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  alpha_scores.parquet (sector-neutral):", nrow(alpha_all), "rows\n")

validation <- list(
  task_id = WT_ID, version = "v5_sector_neutral",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hypothesis = "4-Axis Vol/Skewness Composite (D43+D05+D41+D58) — Sector-Neutral PIT-Strict",
  pit_compliance_check = list(
    c1_no_full_sample_align = TRUE,
    z_score_source = "Factor DB Z_Score_Aligned + expanding direction (36m burn-in)",
    neutralization = "sector demean per sig_date",
    cutoff = as.character(SIGNAL_CUTOFF)
  ),
  diagnostics = list(
    raw_composite = list(
      rank_ic = mean_ic_raw, icir = icir_raw, harvey_t_nw = t_nw_raw
    ),
    sector_neutral_composite = list(
      rank_ic = mean_ic_sn,
      icir = icir_sn,
      harvey_t_nw = t_nw_sn,
      monotonicity = mono_sn,
      subperiod_stability = subperiod_stab_sn,
      per_factor_sn_ic = ic_per_sn_summary,
      subperiod_breakdown = ic_sub_sn_s
    ),
    ic_retention_sn_over_raw = mean_ic_sn / mean_ic_raw,
    orthogonality = list(
      cor_alpha_S4_full_pearson = cor_full_p_sn,
      cor_alpha_S4_full_spearman = cor_full_s_sn,
      cor_crisis_S4_bot20pct = cor_crisis_sn,
      cor_normal_S4_top80pct = cor_normal_sn,
      n_overlap_periods = nrow(joined_sn),
      top20_portfolio_sharpe_ann_sn = sharpe_sn,
      top20_portfolio_ret_ann_sn = ret_ann_sn
    ),
    crisis_alpha_ax001_v2_sn = list(
      ic_bad_regime = ic_bad_sn, ic_normal_regime = ic_norm_sn,
      ratio_bad_over_normal = if (!is.na(ic_bad_sn/ic_norm_sn)) ic_bad_sn / ic_norm_sn else NA
    ),
    decile_returns_sn = decile_avg_sn,
    n_sig_dates_eval = uniqueN(panel_eval$sig_date),
    selection_objective = "icir"
  )
)
write_json(validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")

cat("\n=== SUMMARY v5 SECTOR-NEUTRAL ===\n")
cat(sprintf("Eval: %s to %s (%d sig_dates)\n", as.character(min(panel_eval$sig_date)), as.character(max(panel_eval$sig_date)), uniqueN(panel_eval$sig_date)))
cat(sprintf("RAW composite: IC %.4f / ICIR %.4f / NW-t %.4f\n", mean_ic_raw, icir_raw, t_nw_raw))
cat(sprintf("SECTOR-NEUTRAL: IC %.4f / ICIR %.4f / NW-t %.4f / Mono %.3f / SubStab %.2f\n",
            mean_ic_sn, icir_sn, t_nw_sn, mono_sn, subperiod_stab_sn))
cat(sprintf("IC retention SN/raw: %.0f%%\n", 100 * mean_ic_sn / mean_ic_raw))
cat(sprintf("Top20 SN Sharpe: %.3f / Ret_ann: %.2f%%\n", sharpe_sn, ret_ann_sn*100))
cat(sprintf("cor S4_v2 SN: pearson=%.3f / spearman=%.3f\n", cor_full_p_sn, cor_full_s_sn))
if (!is.na(ic_bad_sn/ic_norm_sn)) cat(sprintf("AX-001 v2 SN IC bad/normal ratio: %.3f\n", ic_bad_sn/ic_norm_sn))
cat("Done.\n")
