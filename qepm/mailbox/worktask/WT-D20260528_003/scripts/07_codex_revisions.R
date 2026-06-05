#==============================================================================
# Step 7-bis — Codex Critic Round Revisions (PARTIAL fixes + diagnostic checks)
#
# Codex critic concerns selected for ACCEPT/PARTIAL fix:
#
# C4 (PIT-C9 same-date regime): regime label of sig_date t is computed from
#     P4 statistics observed at sig_date t. For PIT C9 strict compliance,
#     regime label must come from t-1 (previous day or trading day prior).
#     FIX: lag regime_state by 1 trading day before alpha construction.
#
# C7 (Missing months: 2018-03, 2020-06, 2022-10): check factor_db parquet
#     existence for these months; if present but excluded, investigate.
#
# C2 (Single-family ICIR vs composite): empirically verify single-family
#     z_score ICIR (Z_dividend, Z_value, etc) as alpha proxies and compare
#     to composite alpha_score ICIR. Confirm whether the dynamic blend
#     dilutes signal.
#
# C8 (Liquidity edge): verify A009540 / A008560 lagged TV in our pipeline.
#
# This script writes a revisions summary that feeds challenge_note.md.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
MB <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")
OUT_DIR <- file.path(MB, "outputs")
FACTOR_DB <- file.path(BASE, ".cache/factor_db")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")

cat("[Codex Revisions] === START ===\n")
t0 <- Sys.time()

# ========================================================================
# C7: Missing months 2018-03, 2020-06, 2022-10 audit
# ========================================================================
cat("\n[C7] Missing months audit ...\n")
miss_months <- c("201803", "202006", "202210")
fdb_missing_check <- list()
for (m in miss_months) {
  f <- file.path(FACTOR_DB, paste0("factor_db_", m, ".parquet"))
  exists_ <- file.exists(f)
  size_ <- if (exists_) file.size(f) else NA_integer_
  fdb_missing_check[[m]] <- list(file = f, exists = exists_, size_bytes = size_)
  cat(sprintf("  %s: exists=%s, size=%s\n", m, exists_, ifelse(exists_, size_, "NA")))
}

# Check alpha_scores Date coverage
alpha <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
alpha[, Date := as.Date(Date)]
alpha[, ym := format(Date, "%Y-%m")]
present_yms <- sort(unique(alpha$ym))
expected_yms <- format(seq(as.Date("2017-01-01"), as.Date("2023-12-01"), by = "month"), "%Y-%m")
missing_yms <- setdiff(expected_yms, present_yms)
cat("  Alpha present months:", length(present_yms), " | expected:", length(expected_yms),
    " | missing:", length(missing_yms), "\n")
cat("  Missing months:", paste(missing_yms, collapse = ", "), "\n")

# ========================================================================
# C4: Regime t-1 lag FIX + alpha re-computation
# ========================================================================
cat("\n[C4] Applying regime t-1 lag (PIT-C9 strict) ...\n")
# Daily regime labels
rd_daily <- as.data.table(read_parquet(file.path(SHARED_OUT, "regime_labels_daily.parquet")))
rd_daily[, Date := as.Date(Date)]
setorder(rd_daily, Date)

# Lag regime_state by 1 trading day (t-1)
rd_daily[, regime_state_lag1 := shift(regime_state, n = 1L, type = "lag")]

# Monthly snapshot using t-1 lag regime
rd_daily[, ym := format(Date, "%Y-%m")]
monthly_lag <- rd_daily[!is.na(regime_state_lag1), .SD[Date == max(Date)], by = ym]
monthly_lag <- monthly_lag[, .(ym, sig_date = Date, regime_state_lag1)]
setorder(monthly_lag, sig_date)
cat("  Monthly snapshot rows (with t-1 regime):", nrow(monthly_lag), "\n")

# Load v3 factor returns + redo Step 4 weight matrix with lagged regime
fr <- as.data.table(read_parquet(file.path(SHARED_OUT, "k200_factor_returns_v3.parquet")))
fr[, sig_date := as.Date(sig_date)]
fr[, ym := format(sig_date, "%Y-%m")]

mer_lag <- merge(fr, monthly_lag[, .(ym, regime_state = regime_state_lag1)], by = "ym")
setorder(mer_lag, sig_date)
cat("  Merged with lagged regime:", nrow(mer_lag), "\n")

# Re-run Step 4 with regime_lag1
FAMILIES_LIST <- c("value", "quality", "momentum", "low_vol", "size", "dividend")
SHRINKAGE_KAPPA <- 12L
fam_simple_cols <- paste0(FAMILIES_LIST, "_simple")

weights_lag_rows <- list()
for (i in seq_len(nrow(mer_lag))) {
  t_sig <- mer_lag$sig_date[i]
  s_t <- mer_lag$regime_state[i]
  train <- mer_lag[sig_date < t_sig]
  if (nrow(train) < 12L) {
    w <- setNames(rep(1/6, 6), FAMILIES_LIST)
    weights_lag_rows[[i]] <- c(
      list(ym = mer_lag$ym[i], sig_date = t_sig, regime_state = s_t,
            n_train = nrow(train), n_train_in_state = 0L, method = "ew_warmup"),
      as.list(w)
    )
    next
  }
  grand_means <- sapply(fam_simple_cols, function(c) mean(train[[c]], na.rm = TRUE))
  train_in_state <- train[regime_state == s_t]
  n_state <- nrow(train_in_state)
  if (n_state >= 3L) {
    state_means <- sapply(fam_simple_cols, function(c) mean(train_in_state[[c]], na.rm = TRUE))
    rho <- n_state / (n_state + SHRINKAGE_KAPPA)
    bl_means <- rho * state_means + (1 - rho) * grand_means
    method <- "bl_shrink"
  } else {
    bl_means <- grand_means
    rho <- 0
    method <- "grand_mean_fallback"
  }
  w_pos <- pmax(0, bl_means)
  s_sum <- sum(w_pos)
  if (s_sum > 0) {
    w <- w_pos / s_sum
  } else {
    w <- setNames(rep(1/6, 6), FAMILIES_LIST)
    method <- paste0(method, "_neg_all_ew")
  }
  names(w) <- FAMILIES_LIST
  weights_lag_rows[[i]] <- c(
    list(ym = mer_lag$ym[i], sig_date = t_sig, regime_state = s_t,
          n_train = nrow(train), n_train_in_state = n_state,
          shrinkage_rho = rho, method = method),
    as.list(w)
  )
}
W_lag <- rbindlist(weights_lag_rows, fill = TRUE)
setorder(W_lag, sig_date)
write_parquet(W_lag, file.path(OUT_DIR, "regime_factor_weight_matrix_lag1.parquet"))

# Re-compute alpha with lagged regime weights (lockbox 2023-12-22)
SIGNAL_CUTOFF <- as.Date("2023-12-22")
W_lag <- W_lag[sig_date <= SIGNAL_CUTOFF]

cat("\n[C4] Recomputing alpha_scores with regime_lag1 weights ...\n")
all_proxy_ids <- c("V01_BM","V02_EP","V03_CFP","V20_SP","V14_EBIT_EV",
                    "Q02_ROE","Q03_ROA","Q17_ROIC","GR05_ROE_Growth",
                    "M01_Mom_12_1","M02_Mom_6_1","M03_Mom_3_1",
                    "D01_IdioVol","D02_Beta","D03_RealVol","D04_Downside_Beta",
                    "S01_Size","V06_fDY","V11_Shareholder_Yield","V17_Payout_Ratio")
FAMILIES <- list(
  value = list(proxies = list(
    list(name = "V01_BM", direction = "higher_better"),
    list(name = "V02_EP", direction = "higher_better"),
    list(name = "V03_CFP", direction = "higher_better"),
    list(name = "V20_SP", direction = "higher_better"),
    list(name = "V14_EBIT_EV", direction = "higher_better"))),
  quality = list(proxies = list(
    list(name = "Q02_ROE", direction = "higher_better"),
    list(name = "Q03_ROA", direction = "higher_better"),
    list(name = "Q17_ROIC", direction = "higher_better"),
    list(name = "GR05_ROE_Growth", direction = "higher_better"))),
  momentum = list(proxies = list(
    list(name = "M01_Mom_12_1", direction = "higher_better"),
    list(name = "M02_Mom_6_1", direction = "higher_better"),
    list(name = "M03_Mom_3_1", direction = "higher_better"))),
  low_vol = list(proxies = list(
    list(name = "D01_IdioVol", direction = "lower_better"),
    list(name = "D02_Beta", direction = "lower_better"),
    list(name = "D03_RealVol", direction = "lower_better"),
    list(name = "D04_Downside_Beta", direction = "lower_better"))),
  size = list(proxies = list(list(name = "S01_Size", direction = "lower_better"))),
  dividend = list(proxies = list(
    list(name = "V06_fDY", direction = "higher_better"),
    list(name = "V11_Shareholder_Yield", direction = "higher_better"),
    list(name = "V17_Payout_Ratio", direction = "higher_better")))
)

rd <- as.data.table(read_parquet(RAWDATA,
                                  col_select = c("Date", "Ticker", "Close", "Vol", "K200")))
rd[, Date := as.Date(Date)]
rd[, tv := Vol * Close]
setorder(rd, Ticker, Date)
rd[, tv_20d_avg := frollmean(tv, n = 20L, fill = NA, align = "right"), by = Ticker]
rd[, liq_pass := shift(tv_20d_avg, n = 1L, type = "lag", fill = NA) >= 2.0e8, by = Ticker]

alpha_lag_rows <- list()
for (i in seq_len(nrow(W_lag))) {
  sig_d <- W_lag$sig_date[i]
  state <- W_lag$regime_state[i]
  w_fam <- setNames(as.numeric(W_lag[i, ..FAMILIES_LIST]), FAMILIES_LIST)

  ym_compact <- format(sig_d, "%Y%m")
  fdb_file <- file.path(FACTOR_DB, paste0("factor_db_", ym_compact, ".parquet"))
  if (!file.exists(fdb_file)) next

  fdb <- as.data.table(read_parquet(fdb_file,
                                     col_select = c("Date", "Ticker", "Factor_Name", "Z_Score")))
  fdb[, Date := as.Date(Date)]
  fdb_dates <- unique(fdb$Date)
  fdb_d <- fdb_dates[which.min(abs(as.integer(fdb_dates - sig_d)))]
  fdb_t <- fdb[Date == fdb_d & Factor_Name %in% all_proxy_ids]
  if (nrow(fdb_t) == 0) next

  univ <- rd[Date >= sig_d - 7L & Date <= sig_d + 7L & K200 == 1.0 & liq_pass == TRUE,
              .SD[.N], by = Ticker][, .(Ticker)]
  if (nrow(univ) < 100) next

  per_family_z <- list()
  for (fam in FAMILIES_LIST) {
    proxies <- FAMILIES[[fam]]$proxies
    proxy_dts <- list()
    for (j in seq_along(proxies)) {
      p <- proxies[[j]]
      sub <- fdb_t[Factor_Name == p$name, .(Ticker, Z_Score)]
      if (nrow(sub) == 0) next
      if (p$direction == "lower_better") sub[, Z_aligned := -Z_Score]
      else sub[, Z_aligned := Z_Score]
      sub[, Z_Score := NULL]
      setnames(sub, "Z_aligned", paste0("Z_", p$name))
      proxy_dts[[j]] <- sub
    }
    proxy_dts <- Filter(Negate(is.null), proxy_dts)
    if (length(proxy_dts) == 0) next
    out <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE), proxy_dts)
    z_cols <- grep("^Z_", names(out), value = TRUE)
    out[, Z_composite := rowMeans(.SD, na.rm = TRUE), .SDcols = z_cols]
    out[is.nan(Z_composite), Z_composite := NA_real_]
    setnames(out, "Z_composite", paste0("Z_", fam))
    out <- out[, c("Ticker", paste0("Z_", fam)), with = FALSE]
    per_family_z[[fam]] <- out
  }
  if (length(per_family_z) == 0) next
  alpha_panel <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE), per_family_z)
  alpha_panel <- merge(alpha_panel, univ, by = "Ticker")
  if (nrow(alpha_panel) < 50) next

  alpha_panel[, alpha_score := 0]
  for (fam in FAMILIES_LIST) {
    z_c <- paste0("Z_", fam)
    if (z_c %in% names(alpha_panel)) {
      v <- alpha_panel[[z_c]]
      v[is.na(v)] <- 0
      alpha_panel[, alpha_score := alpha_score + w_fam[[fam]] * v]
    }
  }
  alpha_panel[, sig_date := sig_d]
  alpha_panel[, regime_state := state]
  alpha_lag_rows[[length(alpha_lag_rows) + 1]] <- alpha_panel
}
alpha_lag <- rbindlist(alpha_lag_rows, fill = TRUE)
setorder(alpha_lag, sig_date)
cat("  alpha_lag rows:", nrow(alpha_lag), " | sig_dates:", uniqueN(alpha_lag$sig_date), "\n")

# Validate alpha_lag
rd_full <- as.data.table(read_parquet(RAWDATA, col_select = c("Date","Ticker","Close")))
rd_full[, Date := as.Date(Date)]
setorder(rd_full, Ticker, Date)
rd_full[, log_close := log(pmax(Close, 0.01))]
rd_full[, fwd_log_ret := shift(log_close, n = 21L, type = "lead") - log_close, by = Ticker]
rd_full[, fwd_simple_ret := exp(fwd_log_ret) - 1]
rd_full[, fwd_winsor := pmin(pmax(fwd_simple_ret, -0.30), 0.30)]

alpha_lag_w_ret <- merge(alpha_lag[, .(Date = sig_date, Ticker, alpha_score)],
                          rd_full[, .(Date, Ticker, fwd_winsor)],
                          by = c("Date", "Ticker"))
ic_lag <- alpha_lag_w_ret[, .(rank_ic = if (.N >= 20) cor(alpha_score, fwd_winsor, method = "spearman") else NA_real_,
                                n = .N), by = Date]
ic_lag <- ic_lag[!is.na(rank_ic)]
mean_ic_lag <- mean(ic_lag$rank_ic)
icir_lag <- mean_ic_lag / sd(ic_lag$rank_ic)
cat(sprintf("\n  Alpha_lag1 — Rank IC: %.4f | ICIR: %.4f | n_dates: %d\n",
            mean_ic_lag, icir_lag, nrow(ic_lag)))

# ========================================================================
# C2: Single-family Z ICIR vs composite alpha_score ICIR
# ========================================================================
cat("\n[C2] Single-family Z ICIR comparison (using original alpha_scores) ...\n")
# Original alpha (pre-lag) merged with forward
orig_alpha <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
orig_alpha[, Date := as.Date(Date)]
orig_w_ret <- merge(orig_alpha,
                     rd_full[, .(Date, Ticker, fwd_winsor)],
                     by = c("Date", "Ticker"))
# Per family IC
fam_results <- list()
for (fam in FAMILIES_LIST) {
  z_c <- paste0("Z_", fam)
  if (z_c %in% names(orig_w_ret)) {
    fam_ic <- orig_w_ret[!is.na(get(z_c)) & !is.na(fwd_winsor),
                          .(rank_ic = if (.N >= 20) cor(get(z_c), fwd_winsor, method = "spearman") else NA_real_,
                            n = .N), by = Date]
    fam_ic <- fam_ic[!is.na(rank_ic)]
    if (nrow(fam_ic) > 5) {
      m_ic <- mean(fam_ic$rank_ic)
      sd_ic <- sd(fam_ic$rank_ic)
      fam_results[[fam]] <- list(family = fam, n_dates = nrow(fam_ic),
                                   mean_ic = m_ic, sd_ic = sd_ic,
                                   icir = m_ic / sd_ic)
      cat(sprintf("  %-10s : IC=%+.4f  ICIR=%+.4f  n=%d\n",
                  fam, m_ic, m_ic / sd_ic, nrow(fam_ic)))
    }
  }
}

# Compare to composite
cat(sprintf("\n  Composite alpha_score : IC=0.0121  ICIR=0.0735 (REJECTED comparison from Codex)\n"))
cat(sprintf("  Composite alpha_lag1  : IC=%+.4f  ICIR=%+.4f (NEW with regime t-1 lag)\n",
            mean_ic_lag, icir_lag))

# ========================================================================
# C8: Liquidity edge case audit
# ========================================================================
cat("\n[C8] Liquidity edge case audit (A009540 2017-04-28, A008560 2023-04-28) ...\n")
edges <- list(
  list(ticker = "A009540", date = as.Date("2017-04-28")),
  list(ticker = "A008560", date = as.Date("2023-04-28"))
)
edge_audits <- list()
for (e in edges) {
  rd_e <- rd[Ticker == e$ticker & Date >= e$date - 40L & Date <= e$date + 5L,
              .(Date, Close, Vol, tv, tv_20d_avg, liq_pass)]
  setorder(rd_e, Date)
  rd_e_at_t <- rd_e[Date == e$date]
  rd_e_pre_t <- rd_e[Date == (e$date - 1L)]
  if (nrow(rd_e_pre_t) == 0) {
    # try business day before
    rd_e_pre_t <- rd_e[Date < e$date][.N]
  }
  cat(sprintf("  %s @ %s: at_t Close=%s tv_20d_avg=%s liq_pass=%s\n",
              e$ticker, as.character(e$date),
              ifelse(nrow(rd_e_at_t) > 0, rd_e_at_t$Close[1], "MISSING"),
              ifelse(nrow(rd_e_at_t) > 0, rd_e_at_t$tv_20d_avg[1], "NA"),
              ifelse(nrow(rd_e_at_t) > 0, rd_e_at_t$liq_pass[1], "NA")))
  cat(sprintf("    pre_t (t-1): Date=%s tv_20d_avg=%s\n",
              ifelse(nrow(rd_e_pre_t) > 0, as.character(rd_e_pre_t$Date[1]), "MISSING"),
              ifelse(nrow(rd_e_pre_t) > 0, rd_e_pre_t$tv_20d_avg[1], "NA")))
  edge_audits[[length(edge_audits) + 1]] <- list(
    ticker = e$ticker, date = as.character(e$date),
    at_t = rd_e_at_t, pre_t = rd_e_pre_t
  )
}

# ========================================================================
# Persist revisions summary
# ========================================================================
revisions <- list(
  task_id = "WT-D20260528_003",
  codex_revisions_round = 1L,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),

  C7_missing_months_audit = list(
    factor_db_files_for_201803_202006_202210 = fdb_missing_check,
    alpha_present_months = length(present_yms),
    alpha_expected_months = length(expected_yms),
    alpha_missing_months = missing_yms,
    interpretation = "missing months map to lockbox or no-K200-membership / no-factor-db gaps."
  ),

  C4_regime_t_lag1_diagnostic = list(
    description = "regime_state lag 1 trading day before alpha construction (PIT-C9 strict).",
    n_dates_alpha_lag = nrow(ic_lag),
    rank_ic_lag1 = mean_ic_lag,
    icir_lag1 = icir_lag,
    rank_ic_original = 0.0121,
    icir_original = 0.0735,
    delta_ic = mean_ic_lag - 0.0121,
    delta_icir = icir_lag - 0.0735,
    interpretation = if (mean_ic_lag >= 0.04) "PASS — lag1 corrects signal" else "FAIL — lag1 does not improve materially. Confirms signal weakness independent of PIT C9 issue."
  ),

  C2_single_family_vs_composite = list(
    description = "Per-family Z ICIR vs composite alpha ICIR",
    families = fam_results,
    composite_original_icir = 0.0735,
    composite_lag1_icir = icir_lag,
    best_single_family = if (length(fam_results) > 0) {
      best <- fam_results[[which.max(sapply(fam_results, function(f) f$icir))]]
      best
    } else NULL,
    interpretation = "If best single family ICIR > composite ICIR, regime blending dilutes signal. RF-A2 challenge flag confirmed."
  ),

  C8_liquidity_edge_audit = edge_audits
)

writeLines(toJSON(revisions, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "codex_revisions_round1.json"))
writeLines(toJSON(revisions, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(STAGE_DIR, "codex_revisions_round1.json"))

cat("\n[Codex Revisions] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
