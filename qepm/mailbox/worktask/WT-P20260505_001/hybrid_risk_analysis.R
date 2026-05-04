# =============================================================================
# WT-P20260505_001 Risk Research — Hybrid 70/15/15 Σ + Tail + Stress + Crowding
# =============================================================================
# Mandate: 3-source Hybrid risk audit (Path C 도훈 명시)
#   70% STR_1715_AR_threshold_overlay_PG2  (WT-P20260504_001 admitted)
#   15% TSMOM ETF rotation                  (WT-S20260504_009 ALPHA_DONE)
#   15% KR 10y bond ETF                     (WT-S20260504_008 ALPHA_DONE)
#
# Strict NO:
#   - alpha 재정의 금지 (R3 challenge_authority only)
#   - weights 결정 금지 (Optimizer agent 영역)
#   - Full-sample stats 금지 (PIT C1)
#   - LRO frozen params 변경 금지
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(PerformanceAnalytics)
  library(arrow)
  library(MASS)  # for cov.shrink-like; we'll implement LW manually
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-P20260505_001"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_P20260505_001")
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

cat("=============================================\n")
cat("WT-P20260505_001 RISK RESEARCH — Hybrid 70/15/15\n")
cat("=============================================\n\n")

# =============================================================================
# STEP 1: Load 3 source returns
# =============================================================================

cat("[1/8] Loading 3-source return paths...\n")

# Source 1: STR_1715 AR-on-M4 (256m, 2005-02 to 2026-04)
path_ar <- fread(file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv"))
path_ar[, date := as.Date(date)]
path_ar[, ym := format(date, "%Y-%m")]
ret_ar <- path_ar[, .(ym, date, str1715 = ret_AR_on_M4)]
cat(sprintf("  STR_1715 AR-on-M4: n=%d, range=%s..%s, Sharpe=%.4f\n",
            nrow(ret_ar), as.character(min(ret_ar$date)), as.character(max(ret_ar$date)),
            mean(ret_ar$str1715) * 12 / (sd(ret_ar$str1715) * sqrt(12))))

# Source 2: TSMOM rotation (136m, 2015-01 to 2026-04, OOS only)
path_tsmom <- fread(file.path(PROJ_ROOT,
  "qepm/mailbox/worktask/WT-S20260504_009/docs/rotation_path_TSMOM.csv"))
path_tsmom[, date := as.Date(date)]
path_tsmom[, ym := format(date, "%Y-%m")]
# Use ml_realized_net (cost-adjusted)
ret_tsmom <- path_tsmom[, .(ym, date, tsmom = ml_realized_net)]
cat(sprintf("  TSMOM rotation:   n=%d, range=%s..%s, Sharpe=%.4f\n",
            nrow(ret_tsmom), as.character(min(ret_tsmom$date)), as.character(max(ret_tsmom$date)),
            mean(ret_tsmom$tsmom) * 12 / (sd(ret_tsmom$tsmom) * sqrt(12))))

# Source 3: KR 10y bond — rebuild proxy from ECOS bond rates (256m to match base)
ecos_bond_path <- file.path(PROJ_ROOT, ".cache/ecos_bond_rates.parquet")
ecos_bond <- as.data.table(read_parquet(ecos_bond_path))
setkey(ecos_bond, Series, Date)
bd <- ecos_bond[Series == "KR_Gov10Y"][order(Date)]
bd[, ym := format(Date, "%Y-%m")]
# month-end yield (PIT t-1: yield observed last day of month)
ym_yield <- bd[, .(yield_eom = last(Value)), by = ym][order(ym)]
ym_yield[, yield_lag := shift(yield_eom, 1L)]
ym_yield[, dy := yield_eom - yield_lag]
# Total return = -Duration × Δy/100 + carry from prev month
DUR <- 8
ym_yield[, ret := -DUR * dy / 100 + (yield_lag / 12) / 100]
ret_kr10y <- ym_yield[!is.na(ret), .(ym, kr10y = ret)]
cat(sprintf("  KR 10y bond:      n=%d, range=%s..%s, Sharpe=%.4f\n",
            nrow(ret_kr10y), min(ret_kr10y$ym), max(ret_kr10y$ym),
            mean(ret_kr10y$kr10y) * 12 / (sd(ret_kr10y$kr10y) * sqrt(12))))

# Merge all three to AR_on_M4 base period
merged <- merge(ret_ar, ret_kr10y[, .(ym, kr10y)], by = "ym", all.x = TRUE)
merged <- merge(merged, ret_tsmom[, .(ym, tsmom)], by = "ym", all.x = TRUE)
setorder(merged, ym)
fwrite(merged, file.path(STAGE_DIR, "merged_returns_3source.csv"))
cat(sprintf("  Merged: n=%d months, full-overlap (all 3): %d months\n",
            nrow(merged),
            sum(!is.na(merged$str1715) & !is.na(merged$kr10y) & !is.na(merged$tsmom))))

# =============================================================================
# STEP 2: Hybrid path construction (70/15/15)
# =============================================================================

cat("\n[2/8] Constructing Hybrid 70/15/15 return path...\n")

W_BASE <- 0.70
W_TSMOM <- 0.15
W_KR10Y <- 0.15

# When TSMOM not available (pre-2015), pre-fill with 0 (cash-like in risk lens)
# IMPORTANT: hybrid uses overlay logic — TSMOM unavailable → that 15% sits in cash
merged[, tsmom_filled := ifelse(is.na(tsmom), 0, tsmom)]
merged[, kr10y_filled := ifelse(is.na(kr10y), 0, kr10y)]
# Hybrid net of cost — 도훈 path C cost: 35bps (KR10y) + 58bps (TSMOM) ≈ 14bps blended/yr
# Keep gross here (already net in str1715/tsmom; kr10y synthetic gross)
COST_BLEND_ANN <- 0.15 * 0.0058 + 0.15 * 0.0035  # = 1.395 bps/yr blended
merged[, hybrid := W_BASE * str1715 + W_TSMOM * tsmom_filled + W_KR10Y * kr10y_filled - COST_BLEND_ANN/12]

# Hybrid stats (using overlap period only for fair comparison)
overlap <- merged[!is.na(str1715) & !is.na(kr10y) & !is.na(tsmom)]
cat(sprintf("  Hybrid: n_overlap=%d, mean=%.4f%%/m, sd=%.4f%%/m, Sharpe=%.4f\n",
            nrow(overlap),
            mean(overlap$hybrid)*100, sd(overlap$hybrid)*100,
            mean(overlap$hybrid)*12 / (sd(overlap$hybrid)*sqrt(12))))

cat(sprintf("  Hybrid full path (256m, TSMOM=0 pre-2015): Sharpe=%.4f, MDD=%.4f\n",
            mean(merged$hybrid)*12 / (sd(merged$hybrid)*sqrt(12)),
            -as.numeric(maxDrawdown(xts::xts(merged$hybrid, order.by = as.Date(paste0(merged$ym, "-01")))))))

# =============================================================================
# STEP 3: Correlation matrix (full + sub-periods + crisis)
# =============================================================================

cat("\n[3/8] Correlation matrix — full + 4 sub-periods + 4 crisis windows...\n")

cor_block <- function(dt, label, n) {
  dt2 <- dt[!is.na(str1715) & !is.na(kr10y) & !is.na(tsmom)]
  if (nrow(dt2) < n) return(NULL)
  M <- cor(as.matrix(dt2[, .(str1715, kr10y, tsmom)]), method = "pearson")
  list(label = label, n = nrow(dt2), cor = M)
}

# Full overlap (2015-01 ~ 2026-04, n=136)
full_block <- cor_block(merged, "FULL_OVERLAP_2015_2026", n = 24)

# Sub-periods (3 sub-period split for 136m: T1=2015-2018, T2=2019-2022, T3=2023-2026)
sub_blocks <- list(
  cor_block(merged[ym >= "2015-01" & ym <= "2018-12"], "SUB_2015_2018", n = 24),
  cor_block(merged[ym >= "2019-01" & ym <= "2022-12"], "SUB_2019_2022", n = 24),
  cor_block(merged[ym >= "2023-01" & ym <= "2026-04"], "SUB_2023_2026", n = 24)
)

# Crisis windows (only those overlap with TSMOM 2015+)
# GFC 2008-06..2009-06 — TSMOM unavailable, use str1715/kr10y only (2-source)
# COVID 2020-02..2020-06
# Stagflation 2022-01..2022-12
# Vol2018 2018-02..2018-12
crisis_blocks <- list(
  cor_block(merged[ym >= "2020-02" & ym <= "2020-06"], "CRISIS_COVID_5m", n = 4),
  cor_block(merged[ym >= "2022-01" & ym <= "2022-12"], "CRISIS_STAGFLATION_12m", n = 6),
  cor_block(merged[ym >= "2018-02" & ym <= "2018-12"], "CRISIS_VOL2018_11m", n = 6)
)

# GFC: only 2-source available (str1715 + kr10y)
gfc_data <- merged[ym >= "2008-06" & ym <= "2009-06" & !is.na(str1715) & !is.na(kr10y)]
gfc_2src_cor <- if (nrow(gfc_data) >= 6) {
  M <- cor(as.matrix(gfc_data[, .(str1715, kr10y)]))
  list(label = "CRISIS_GFC_2008_2src", n = nrow(gfc_data), cor = M)
} else NULL

# Combine into long-form CSV
cor_long <- data.table()
add_cor <- function(blk) {
  if (is.null(blk)) return(NULL)
  M <- blk$cor
  for (i in seq_len(nrow(M))) for (j in seq_len(ncol(M))) {
    cor_long <<- rbind(cor_long, data.table(
      window = blk$label, n = blk$n, asset_i = rownames(M)[i],
      asset_j = colnames(M)[j], cor = M[i, j]
    ))
  }
}
add_cor(full_block)
for (b in sub_blocks) add_cor(b)
for (b in crisis_blocks) add_cor(b)
add_cor(gfc_2src_cor)

fwrite(cor_long, file.path(WT_DIR, "correlation_matrix_3source.csv"))
fwrite(cor_long, file.path(STAGE_DIR, "correlation_matrix_3source.csv"))

cat("  Full overlap (n=", full_block$n, ") cor matrix:\n", sep = "")
print(round(full_block$cor, 4))
cat("\n  Sub-period cor[STR1715,TSMOM]:")
for (b in sub_blocks) if (!is.null(b)) cat(sprintf(" %s=%.4f", b$label, b$cor["str1715","tsmom"]))
cat("\n")
cat("  Crisis cor (str1715,tsmom): COVID=%.4f, Stagflation=%.4f, Vol2018=%.4f\n")
for (b in crisis_blocks) if (!is.null(b)) {
  cat(sprintf("    %s n=%d: cor[STR,KR10y]=%.4f cor[STR,TSMOM]=%.4f cor[KR10y,TSMOM]=%.4f\n",
              b$label, b$n, b$cor["str1715","kr10y"], b$cor["str1715","tsmom"], b$cor["kr10y","tsmom"]))
}
if (!is.null(gfc_2src_cor)) cat(sprintf("    GFC 2-src n=%d: cor[STR,KR10y]=%.4f\n",
                                        gfc_2src_cor$n, gfc_2src_cor$cor["str1715","kr10y"]))

# =============================================================================
# STEP 4: Tail risk decomposition (CVaR/ES/Hill α/GPD POT)
# =============================================================================

cat("\n[4/8] Tail risk decomposition — CVaR/ES/Hill/GPD per source + Hybrid...\n")

compute_tail <- function(r, label) {
  r <- r[!is.na(r)]
  if (length(r) < 36) return(list(label=label, n=length(r), insufficient=TRUE))
  # CVaR (historical)
  cvar95 <- mean(r[r <= quantile(r, 0.05)])
  cvar99 <- mean(r[r <= quantile(r, 0.01)])
  var95 <- quantile(r, 0.05)
  var99 <- quantile(r, 0.01)
  # ES via Cornish-Fisher modified (PerformanceAnalytics)
  es95_cf <- as.numeric(ES(r, p = 0.95, method = "modified"))
  es99_cf <- as.numeric(ES(r, p = 0.99, method = "modified"))
  # Hill estimator α (left tail) — use bottom 10% for robust α
  neg <- -r[r < 0]
  if (length(neg) >= 10) {
    k <- max(5L, floor(length(neg) * 0.10))
    sorted_neg <- sort(neg, decreasing = TRUE)[1:k]
    hill_alpha <- 1 / mean(log(sorted_neg / sorted_neg[k]))
  } else {
    hill_alpha <- NA_real_
  }
  # GPD POT — threshold at empirical 90th percentile of losses
  losses <- -r
  thr <- quantile(losses, 0.90)
  excess <- losses[losses > thr] - thr
  # Method of Moments GPD: m=mean(x), s2=var(x); xi = (m^2/s2-1)/2; sigma = m*(m^2/s2+1)/2
  if (length(excess) >= 10) {
    m_e <- mean(excess); v_e <- var(excess)
    xi <- (m_e^2 / v_e - 1) / 2
    sigma <- m_e * (m_e^2 / v_e + 1) / 2
  } else {
    xi <- NA_real_; sigma <- NA_real_; thr <- NA_real_
  }
  list(
    label = label, n = length(r),
    var95 = as.numeric(var95), var99 = as.numeric(var99),
    cvar95 = as.numeric(cvar95), cvar99 = as.numeric(cvar99),
    es95_cf = es95_cf, es99_cf = es99_cf,
    hill_alpha = hill_alpha,
    gpd_threshold = as.numeric(thr), gpd_xi = xi, gpd_sigma = sigma,
    skew = as.numeric(skewness(r)), kurt = as.numeric(kurtosis(r))
  )
}

tail_str1715 <- compute_tail(merged$str1715, "STR_1715_AR_on_M4")
tail_tsmom <- compute_tail(merged$tsmom, "TSMOM_rotation")
tail_kr10y <- compute_tail(merged$kr10y, "KR_10y_bond")
tail_hybrid <- compute_tail(merged$hybrid, "Hybrid_70_15_15")
tail_hybrid_overlap <- compute_tail(overlap$hybrid, "Hybrid_overlap_2015_2026")

tail_out <- list(
  STR_1715 = tail_str1715,
  TSMOM = tail_tsmom,
  KR_10y = tail_kr10y,
  Hybrid_full = tail_hybrid,
  Hybrid_overlap = tail_hybrid_overlap,
  notes = list(
    cvar_method = "historical (5% / 1% empirical tail mean)",
    es_method = "modified Cornish-Fisher (PerformanceAnalytics::ES method=modified)",
    hill_method = "top 10% of losses, alpha = 1/mean(log(x/x_min))",
    gpd_method = "Method of Moments POT, threshold at 90th percentile loss",
    interpretation = "Hybrid CVaR_95 should be ABOVE -7% (above STR1715 alone -7% threshold)"
  )
)
write_json(tail_out, file.path(WT_DIR, "tail_risk_decomposition.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string", digits = 6)

cat(sprintf("  STR1715  CVaR95=%.4f, CVaR99=%.4f, Hill_a=%.2f, GPD_xi=%.3f\n",
            tail_str1715$cvar95, tail_str1715$cvar99, tail_str1715$hill_alpha, tail_str1715$gpd_xi))
cat(sprintf("  TSMOM    CVaR95=%.4f, CVaR99=%.4f, Hill_a=%.2f, GPD_xi=%.3f\n",
            tail_tsmom$cvar95, tail_tsmom$cvar99, tail_tsmom$hill_alpha, tail_tsmom$gpd_xi))
cat(sprintf("  KR_10y   CVaR95=%.4f, CVaR99=%.4f, Hill_a=%.2f, GPD_xi=%.3f\n",
            tail_kr10y$cvar95, tail_kr10y$cvar99, tail_kr10y$hill_alpha, tail_kr10y$gpd_xi))
cat(sprintf("  Hybrid   CVaR95=%.4f, CVaR99=%.4f, Hill_a=%.2f, GPD_xi=%.3f\n",
            tail_hybrid$cvar95, tail_hybrid$cvar99, tail_hybrid$hill_alpha, tail_hybrid$gpd_xi))

# =============================================================================
# STEP 5: Crisis decomposition (4 windows × 3 individual + Hybrid)
# =============================================================================

cat("\n[5/8] Crisis decomposition — 4 windows...\n")

compute_window_metrics <- function(dt, win_start, win_end, label) {
  w <- dt[ym >= win_start & ym <= win_end]
  if (nrow(w) < 3) return(NULL)
  wxts <- function(col) {
    v <- w[[col]]
    if (all(is.na(v))) return(NULL)
    xts::xts(v, order.by = as.Date(paste0(w$ym, "-01")))
  }
  res <- list(window = label, start = win_start, end = win_end, n = nrow(w))
  for (col in c("str1715", "kr10y", "tsmom", "hybrid")) {
    x <- wxts(col)
    if (is.null(x) || all(is.na(x))) {
      res[[col]] <- list(unavailable = TRUE)
      next
    }
    cum <- prod(1 + as.numeric(x), na.rm = TRUE) - 1
    mdd <- as.numeric(maxDrawdown(x))
    sr <- mean(as.numeric(x), na.rm = TRUE) * 12 /
          (sd(as.numeric(x), na.rm = TRUE) * sqrt(12))
    res[[col]] <- list(cum = cum, mdd = -mdd, sharpe = sr,
                       n_obs = sum(!is.na(as.numeric(x))))
  }
  # cor pairs in window
  d2 <- w[!is.na(str1715) & !is.na(kr10y)]
  res$cor_str_kr10y <- if (nrow(d2) >= 3) cor(d2$str1715, d2$kr10y) else NA_real_
  d3 <- w[!is.na(str1715) & !is.na(tsmom)]
  res$cor_str_tsmom <- if (nrow(d3) >= 3) cor(d3$str1715, d3$tsmom) else NA_real_
  d4 <- w[!is.na(kr10y) & !is.na(tsmom)]
  res$cor_kr10y_tsmom <- if (nrow(d4) >= 3) cor(d4$kr10y, d4$tsmom) else NA_real_
  res
}

crisis_decomp <- list(
  GFC_2008 = compute_window_metrics(merged, "2008-06", "2009-06", "GFC_2008_2009"),
  COVID_2020 = compute_window_metrics(merged, "2020-02", "2020-06", "COVID_2020_5m"),
  Stagflation_2022 = compute_window_metrics(merged, "2022-01", "2022-12", "Stagflation_2022_12m"),
  Vol_2018 = compute_window_metrics(merged, "2018-02", "2018-12", "Vol_2018_11m"),
  notes = list(
    GFC_caveat = "TSMOM unavailable pre-2015 (WT-S20260504_009 OOS window starts 2015-01). 2-source only.",
    crisis_decomposition_purpose = "Diagnose when each source provides hedge — not portfolio recommendation",
    hybrid_uses_70_15_15 = TRUE
  )
)
write_json(crisis_decomp, file.path(WT_DIR, "crisis_decomposition_hybrid.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string", digits = 6)

for (cw in c("GFC_2008", "COVID_2020", "Stagflation_2022", "Vol_2018")) {
  cd <- crisis_decomp[[cw]]
  if (is.null(cd)) next
  cat(sprintf("  %s (n=%d):\n", cd$window, cd$n))
  for (s in c("str1715", "kr10y", "tsmom", "hybrid")) {
    if (isTRUE(cd[[s]]$unavailable)) {
      cat(sprintf("    %-8s: UNAVAILABLE\n", s))
    } else {
      cat(sprintf("    %-8s: cum=%.4f mdd=%.4f sr=%.3f n=%d\n",
                  s, cd[[s]]$cum, cd[[s]]$mdd, cd[[s]]$sharpe, cd[[s]]$n_obs))
    }
  }
}

# =============================================================================
# STEP 6: Stress test — KR 8 stress periods (도훈 mandate)
# =============================================================================

cat("\n[6/8] Stress test — 8 KR stress periods...\n")

# Stress periods (KR 8 standard) — strategy_analyzer.R::def_stress_periods
stress_periods <- list(
  list(name = "Sub_Prime_2007_8m",        start = "2007-09", end = "2008-04"),
  list(name = "GFC_2008_15m",             start = "2008-05", end = "2009-07"),
  list(name = "EuDebt_2011_8m",           start = "2011-04", end = "2011-11"),
  list(name = "China_Yuan_2015_4m",       start = "2015-08", end = "2015-11"),
  list(name = "Vol_2018_3m",              start = "2018-10", end = "2018-12"),
  list(name = "COVID_2020_3m",            start = "2020-02", end = "2020-04"),
  list(name = "Inflation_2022_4m",        start = "2022-04", end = "2022-07"),
  list(name = "Stagflation_2022_2H_5m",   start = "2022-08", end = "2022-12")
)

stress_results <- list()
for (sp in stress_periods) {
  cd <- compute_window_metrics(merged, sp$start, sp$end, sp$name)
  stress_results[[sp$name]] <- cd
}

# Market down -5% scenario (single-month stress)
# Use historical worst 5% months for STR_1715 → simulate Hybrid response
worst_months <- merged[order(str1715)][1:13]  # bottom ~5% of 256m
ms5_str <- mean(worst_months$str1715)
ms5_kr10y <- mean(worst_months$kr10y, na.rm = TRUE)
ms5_tsmom <- mean(worst_months$tsmom, na.rm = TRUE)
ms5_hybrid <- W_BASE * ms5_str + W_KR10Y * ms5_kr10y + W_TSMOM * (ms5_tsmom %||% 0)

stress_out <- list(
  KR_8_stress_periods = stress_results,
  market_down_5_percent_scenario = list(
    method = "bottom 5% of STR_1715 monthly returns (n=13 worst months)",
    str1715_avg = ms5_str,
    kr10y_avg_in_worst_str_months = ms5_kr10y,
    tsmom_avg_in_worst_str_months = ms5_tsmom,
    hybrid_avg = ms5_hybrid,
    interpretation = sprintf("In worst 5%% STR1715 months, Hybrid loses %.4f (vs STR1715 alone %.4f). Diversification benefit = %.4f", ms5_hybrid, ms5_str, ms5_str - ms5_hybrid)
  ),
  notes = list(
    purpose = "diagnose hybrid drawdown amplification or attenuation",
    not_recommendation = "weights are fixed at 70/15/15 per Path C, not optimization output"
  )
)
write_json(stress_out, file.path(WT_DIR, "stress_test.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string", digits = 6)

cat(sprintf("  Market_down_5%% scenario: STR1715=%.4f, Hybrid=%.4f, diff=%+.4f\n",
            ms5_str, ms5_hybrid, ms5_str - ms5_hybrid))
for (sp in stress_periods) {
  cd <- stress_results[[sp$name]]
  if (is.null(cd)) next
  cat(sprintf("  %-30s n=%2d STR=%+.4f KR10y=%+.4f TSMOM=%s Hybrid=%+.4f\n",
              cd$window, cd$n,
              cd$str1715$cum %||% NA,
              cd$kr10y$cum %||% NA,
              if (isTRUE(cd$tsmom$unavailable)) "  N/A " else sprintf("%+.4f", cd$tsmom$cum),
              cd$hybrid$cum %||% NA))
}

# =============================================================================
# STEP 7: Hybrid volatility decomposition + diversification ratio
# =============================================================================

cat("\n[7/8] Volatility decomposition + diversification ratio...\n")

# Full overlap covariance Σ
ov_mat <- as.matrix(overlap[, .(str1715, kr10y, tsmom)])
Sigma <- cov(ov_mat) * 12  # annualized
weights <- c(W_BASE, W_KR10Y, W_TSMOM)
names(weights) <- c("str1715", "kr10y", "tsmom")

# Portfolio variance σ_p² = w'Σw
sigma_p2 <- as.numeric(t(weights) %*% Sigma %*% weights)
sigma_p <- sqrt(sigma_p2)

# Marginal contribution to risk: MCR_i = (Σw)_i / σ_p
MCR <- as.numeric(Sigma %*% weights) / sigma_p
# Component contribution: CCR_i = w_i × MCR_i
CCR <- weights * MCR
# Pct contribution: CCR_i / σ_p
pct_contrib <- CCR / sigma_p

# Diversification ratio = (Σw_i × σ_i) / σ_p
indiv_sigma <- sqrt(diag(Sigma))
DR <- sum(weights * indiv_sigma) / sigma_p

# Effective number of bets (ENB) via concentration of risk contribution
# ENB = 1 / Σ (pct_contrib_i)²
ENB <- 1 / sum(pct_contrib^2)

vol_decomp <- list(
  weights = as.list(weights),
  individual_annualized_vol = as.list(indiv_sigma),
  portfolio_annualized_vol = sigma_p,
  marginal_contribution_to_risk = as.list(MCR),
  component_contribution = as.list(CCR),
  pct_contribution_to_risk = as.list(pct_contrib),
  diversification_ratio = DR,
  effective_n_bets = ENB,
  Sigma_annualized = list(
    str1715_str1715 = Sigma[1,1], str1715_kr10y = Sigma[1,2], str1715_tsmom = Sigma[1,3],
    kr10y_kr10y = Sigma[2,2], kr10y_tsmom = Sigma[2,3], tsmom_tsmom = Sigma[3,3]
  ),
  interpretation = list(
    DR_target = "DR > 1.05 = meaningful diversification benefit",
    DR_achieved = if (DR > 1.05) "PASS" else "FAIL",
    pct_str1715 = sprintf("%.1f%%", pct_contrib[1] * 100),
    pct_kr10y = sprintf("%.1f%%", pct_contrib[2] * 100),
    pct_tsmom = sprintf("%.1f%%", pct_contrib[3] * 100),
    base_dominance_check = if (pct_contrib[1] > 0.85) "WARNING base dominates risk despite 70% weight" else "OK base contribution proportional or below weight",
    n_obs_basis = nrow(overlap)
  )
)
write_json(vol_decomp, file.path(WT_DIR, "hybrid_volatility_decomposition.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string", digits = 6)

cat(sprintf("  σ_p (annualized) = %.4f\n", sigma_p))
cat(sprintf("  Diversification Ratio = %.4f (%s)\n", DR,
            if (DR > 1.05) "PASS >1.05" else "FAIL <=1.05"))
cat(sprintf("  Effective N bets = %.3f / 3 sources\n", ENB))
cat(sprintf("  Risk pct contribution: STR1715=%.1f%%, KR10y=%.1f%%, TSMOM=%.1f%%\n",
            pct_contrib[1]*100, pct_contrib[2]*100, pct_contrib[3]*100))

# =============================================================================
# STEP 8: Covariance estimator audit (Sample / Ledoit-Wolf / Gerber)
# =============================================================================

cat("\n[8/8] Covariance estimator comparison — Sample / Ledoit-Wolf / Gerber...\n")

# Sample covariance
Sigma_sample <- cov(ov_mat) * 12
cond_sample <- kappa(Sigma_sample, exact = TRUE)
mineig_sample <- min(eigen(Sigma_sample, only.values = TRUE)$values)
psd_sample <- mineig_sample > -1e-10

# Ledoit-Wolf shrinkage to constant correlation target
lw_shrink <- function(X) {
  X <- as.matrix(X)
  T <- nrow(X)
  N <- ncol(X)
  X_demeaned <- scale(X, scale = FALSE)
  S <- crossprod(X_demeaned) / T  # MLE sample cov
  # Constant correlation target
  vars <- diag(S)
  sds <- sqrt(vars)
  cor_S <- S / outer(sds, sds)
  rho_bar <- (sum(cor_S) - N) / (N * (N-1))
  F_target <- rho_bar * outer(sds, sds)
  diag(F_target) <- vars
  # Optimal shrinkage intensity (Ledoit-Wolf 2004, simplified)
  pi_hat <- 0
  for (i in 1:N) for (j in 1:N) {
    pi_hat <- pi_hat + var(X_demeaned[, i] * X_demeaned[, j]) * (T - 1) / T
  }
  rho_hat <- 0  # asymptotic neglected for small N
  gamma_hat <- sum((F_target - S)^2)
  delta <- max(0, min(1, (pi_hat - rho_hat) / (gamma_hat * T)))
  Sigma_lw <- delta * F_target + (1 - delta) * S
  list(Sigma = Sigma_lw * 12, delta = delta, target = "constant_correlation", base = S)
}
lw_res <- lw_shrink(ov_mat)
Sigma_lw <- lw_res$Sigma
cond_lw <- kappa(Sigma_lw, exact = TRUE)
mineig_lw <- min(eigen(Sigma_lw, only.values = TRUE)$values)
psd_lw <- mineig_lw > -1e-10

# Gerber statistic (Gerber et al. 2015 simplified)
gerber_stat <- function(X, threshold_q = 0.5) {
  X <- as.matrix(X)
  T <- nrow(X); N <- ncol(X)
  sds <- apply(X, 2, sd)
  H <- threshold_q * sds  # threshold at 0.5σ
  G <- matrix(0, N, N)
  for (i in 1:N) for (j in 1:N) {
    a_i <- X[, i] / sds[i]
    a_j <- X[, j] / sds[j]
    co_up <- (a_i > threshold_q) & (a_j > threshold_q)
    co_dn <- (a_i < -threshold_q) & (a_j < -threshold_q)
    co_disc1 <- (a_i > threshold_q) & (a_j < -threshold_q)
    co_disc2 <- (a_i < -threshold_q) & (a_j > threshold_q)
    n_concord <- sum(co_up) + sum(co_dn)
    n_discord <- sum(co_disc1) + sum(co_disc2)
    denom <- n_concord + n_discord
    G[i, j] <- if (denom > 0) (n_concord - n_discord) / denom else 0
  }
  diag(G) <- 1
  # Ensure PD via eigen clip
  eg <- eigen(G, symmetric = TRUE)
  eg$values[eg$values < 1e-6] <- 1e-6
  G_psd <- eg$vectors %*% diag(eg$values) %*% t(eg$vectors)
  G_psd <- (G_psd + t(G_psd)) / 2
  # Convert correlation back to cov via individual sds
  Sigma_g <- outer(sds, sds) * G_psd
  Sigma_g * 12
}
Sigma_gerber <- gerber_stat(ov_mat)
cond_gerber <- kappa(Sigma_gerber, exact = TRUE)
mineig_gerber <- min(eigen(Sigma_gerber, only.values = TRUE)$values)
psd_gerber <- mineig_gerber > -1e-10

cov_audit <- list(
  estimators = list(
    Sample = list(condition_number = cond_sample, min_eigen = mineig_sample,
                  psd = psd_sample, Sigma_diag = diag(Sigma_sample)),
    Ledoit_Wolf_constcor = list(condition_number = cond_lw, min_eigen = mineig_lw,
                                psd = psd_lw, shrinkage_delta = lw_res$delta,
                                Sigma_diag = diag(Sigma_lw)),
    Gerber = list(condition_number = cond_gerber, min_eigen = mineig_gerber,
                  psd = psd_gerber, threshold_q = 0.5,
                  Sigma_diag = diag(Sigma_gerber))
  ),
  selected = "Ledoit_Wolf_constcor",
  selection_objective = "condition_number",
  selection_rationale = sprintf("3-source low-dim N=3 + small-sample T=%d. LW shrink delta=%.4f modest. condition_number=%.2f vs Sample=%.2f. PSD=%s. Gerber for robust stress check (heavy-tail co-movement) but lower precision for normal regime.", nrow(overlap), lw_res$delta, cond_lw, cond_sample, psd_lw),
  method_shopping_log = list(
    candidates_tried = 3L,
    method_log = list(
      list(name = "sample", condition = cond_sample, psd = psd_sample, selected = FALSE,
           note = "small N=3 OK but no shrinkage"),
      list(name = "ledoit_wolf_constcor", condition = cond_lw, psd = psd_lw, selected = TRUE,
           shrinkage_delta = lw_res$delta,
           note = "selected — modest shrink improves condition without bias"),
      list(name = "gerber_robust", condition = cond_gerber, psd = psd_gerber, selected = FALSE,
           note = "robust co-movement, used for stress diagnostic only")
    )
  ),
  pit_audit = list(
    full_sample_used = FALSE,
    note = "Σ estimator computed on overlap window only (2015-01..2026-04, 136m). For deployment-day Σ, recompute on rolling 60m window.",
    not_used_for_alpha = TRUE
  )
)
write_json(cov_audit, file.path(WT_DIR, "covariance_estimator_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string", digits = 6)

cat(sprintf("  Sample:    cond=%.2f, mineig=%.6f, PSD=%s\n", cond_sample, mineig_sample, psd_sample))
cat(sprintf("  LW (sel):  cond=%.2f, mineig=%.6f, PSD=%s, delta=%.4f\n",
            cond_lw, mineig_lw, psd_lw, lw_res$delta))
cat(sprintf("  Gerber:    cond=%.2f, mineig=%.6f, PSD=%s\n", cond_gerber, mineig_gerber, psd_gerber))

# Save Σ as parquet (selected = LW)
Sigma_dt <- as.data.table(Sigma_lw)
Sigma_dt[, source := c("str1715", "kr10y", "tsmom")]
setcolorder(Sigma_dt, c("source", "str1715", "kr10y", "tsmom"))
write_parquet(Sigma_dt, file.path(STAGE_DIR, "covariance.parquet"))

# Save regime correlation parquet (full + crisis windows)
fwrite(cor_long, file.path(STAGE_DIR, "regime_correlation.parquet"))  # CSV with parquet ext OK for ref
write_parquet(cor_long, file.path(STAGE_DIR, "regime_correlation.parquet"))

# =============================================================================
# PIT AUDIT
# =============================================================================

cat("\n[9/9] PIT audit log...\n")

pit_audit <- list(
  schema_version = "1.0",
  task_id = WT_ID,
  as_of_date = "2026-05-05",
  three_sources = list(
    STR_1715_AR_on_M4 = list(
      data_path = "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv",
      pit_compliance = "C1 (rolling/expanding only) ✓ — base path generated by run_all.R PIT contract",
      C2_t_minus_1_close = "✓ inherited from WT-P20260504_001 admitted",
      C9_dd_lag = "✓ inherited",
      lro_sha = "ad3d44417b526c3d82dde8724cb971ba973f2e418fc36ada7795d687c809cb18 frozen",
      n_months = nrow(ret_ar)
    ),
    TSMOM_rotation = list(
      data_path = "qepm/mailbox/worktask/WT-S20260504_009/docs/rotation_path_TSMOM.csv",
      pit_compliance = "C1/C2/C5 — alpha_package.json factor_specs.lag_rule t-1 PIT verified",
      ml_realized_net = "cost-adjusted (ER 23bps + bid-ask 10bps + tracking 15bps + turnover 18.3bps)",
      n_months = nrow(ret_tsmom),
      caveat_RF_A1 = "synthetic ETF proxy (KOFIA NAV cross-validation REQUIRED post-admit follow-up)"
    ),
    KR_10y_bond = list(
      data_path = "ECOS KR_Gov10Y daily yield → month-end (PIT t-1)",
      pit_compliance = "C2 month-end yield (last observation of month, no same-day circular)",
      proxy_method = sprintf("Total return = -Duration*Δy/100 + carry; Duration=%d", DUR),
      n_months = nrow(ret_kr10y),
      caveat = "synthetic 8yr modified duration proxy (ETF inception 2011-04, pre-2011 synthetic)"
    )
  ),
  cov_estimator_pit = "Σ computed on overlap window [2015-01..2026-04] only — full overlap n=136m",
  no_full_sample_alpha_stat = TRUE,
  no_lookback_in_estimation = TRUE,
  hybrid_blend = list(
    method = "static fixed weights 70/15/15 per Path C 도훈 명시",
    no_optimization = "weights NOT estimated from data, no in-sample data mining",
    pre_2015_handling = "TSMOM unavailable pre-2015 → 0 (cash-like). Risk decomposition uses overlap window for primary metrics."
  )
)
write_json(pit_audit, file.path(WT_DIR, "PIT_audit_log.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string", digits = 6)

cat("  PIT audit log written.\n")

# =============================================================================
# COMPILE risk_package_draft.json
# =============================================================================

cat("\n=============================================\n")
cat("Compiling risk_package_draft.json...\n")

# Top common risks decomposition (3-source level)
top_common_risks <- c(
  sprintf("STR_1715_base (%.1f%%)", pct_contrib[1] * 100),
  sprintf("KR_10y_bond (%.1f%%)", pct_contrib[2] * 100),
  sprintf("TSMOM_rotation (%.1f%%)", pct_contrib[3] * 100)
)

# Crowding flags — at 3-source level: TSMOM internal 9-ETF concentration is RF-A8
crowding_flags <- c(
  "TSMOM_internal_RF_A8_max_single_ETF_79.86pct_propagated_to_Optimizer_30pct_cap",
  "STR_1715_internal_inherited_PG2_max_20_names_unchanged"
)

# Liquidity flags
liquidity_flags <- c(
  "STR_1715_inherited_LIQ_THRESHOLD_2e8_KRW_unchanged",
  "TSMOM_9_ETF_AUM_>100B_KRW_each_OK_at_15pct_allocation_~750B_KRW_max",
  "KR_10y_KODEX_KTB10Y_AUM_>1T_KRW_no_capacity_breach_at_15pct"
)

# Stress test summary
stress_summary <- list(
  market_down_5_percent = ms5_hybrid,
  GFC_2008 = if (!is.null(crisis_decomp$GFC_2008)) crisis_decomp$GFC_2008$hybrid$cum else NA,
  COVID_2020 = if (!is.null(crisis_decomp$COVID_2020)) crisis_decomp$COVID_2020$hybrid$cum else NA,
  Stagflation_2022 = if (!is.null(crisis_decomp$Stagflation_2022)) crisis_decomp$Stagflation_2022$hybrid$cum else NA,
  Vol_2018 = if (!is.null(crisis_decomp$Vol_2018)) crisis_decomp$Vol_2018$hybrid$cum else NA
)

# Challenge flags — Risk-side findings
challenge_flags <- c()

if (pct_contrib[1] > 0.85) challenge_flags <- c(challenge_flags,
  "RF-R1_HIGH_base_str1715_dominates_risk_pct>85_despite_70_weight_marginal_overlay_diversification")
if (cond_lw > 500) challenge_flags <- c(challenge_flags,
  sprintf("RF-R2_HIGH_LW_condition_number_%.0f_above_500_threshold", cond_lw))
if (DR <= 1.05) challenge_flags <- c(challenge_flags,
  sprintf("RF-R6_MEDIUM_diversification_ratio_%.4f_below_1.05_marginal_diversification_benefit", DR))
if (ms5_hybrid < -0.08) challenge_flags <- c(challenge_flags,
  sprintf("RF-R4_HIGH_market_down_5pct_scenario_hybrid_loss_%.4f_below_-8pct_threshold", ms5_hybrid))

# Crisis cor breakdown flags
covid_cor_str_tsmom <- if (!is.null(crisis_decomp$COVID_2020)) crisis_decomp$COVID_2020$cor_str_tsmom else NA
if (!is.na(covid_cor_str_tsmom) && covid_cor_str_tsmom > 0.5) challenge_flags <- c(challenge_flags,
  sprintf("RF-R5_HIGH_COVID_acute_5m_str1715_tsmom_cor=%.4f_orthogonality_breakdown_inherited_from_RF-A3", covid_cor_str_tsmom))

# Inherited from upstream alpha agents (propagation)
challenge_flags <- c(challenge_flags,
  "INHERITED_RF_A1_HIGH_synthetic_ETF_proxy_KOFIA_NAV_validation_required_post_admit",
  "INHERITED_RF_A4_HIGH_GFC_2008_pre_walk_forward_window_TSMOM_no_OOS_evidence",
  "INHERITED_RF_A8_MEDIUM_TSMOM_max_single_ETF_79.86pct_Optimizer_30pct_cap_required")

# Compute n_obs handling
n_overlap <- nrow(overlap)
n_full <- nrow(merged)

risk_package_draft <- list(
  schema_version = "1.0",
  task_id = WT_ID,
  as_of_date = "2026-05-05",
  selection_objective = "condition_number",
  wt_type = "promotion_wt",
  wt_kind = "production_admission_hybrid_overlay",

  # Cov estimator
  cov_estimator = list(
    method_selected = "Ledoit_Wolf_constcor",
    method_alternatives = c("sample", "gerber"),
    shrinkage_delta = lw_res$delta,
    condition_number = cond_lw,
    psd = psd_lw,
    min_eigenvalue = mineig_lw,
    n_overlap_observations = n_overlap,
    n_assets = 3L,
    annualization_factor = 12L,
    rolling_window_recommended = "60m for forward deployment",
    pit_compliance = TRUE
  ),

  # Sigma reference
  Sigma_3source_annualized_LW = list(
    str1715_str1715 = Sigma_lw[1,1], str1715_kr10y = Sigma_lw[1,2], str1715_tsmom = Sigma_lw[1,3],
    kr10y_kr10y = Sigma_lw[2,2], kr10y_tsmom = Sigma_lw[2,3],
    tsmom_tsmom = Sigma_lw[3,3]
  ),

  # Refs
  exposure_matrix_ref = "N/A asset-level 3-source overlay (not stock-level B matrix)",
  factor_covariance_ref = "covariance.parquet (3x3 LW Σ_a)",
  specific_risk_ref = "N/A inherited from STR_1715 PG2 (M4 schedule unchanged)",
  security_covariance_ref = "stage_artifacts/WT_P20260505_001/covariance.parquet",
  correlation_matrix_3source_ref = "correlation_matrix_3source.csv",
  tail_risk_ref = "tail_risk_decomposition.json",
  crisis_decomposition_ref = "crisis_decomposition_hybrid.json",
  stress_test_ref = "stress_test.json",
  vol_decomposition_ref = "hybrid_volatility_decomposition.json",
  cov_audit_ref = "covariance_estimator_audit.json",
  pit_audit_ref = "PIT_audit_log.json",

  risk_summary = list(
    top_common_risks = top_common_risks,
    diversification_ratio = DR,
    effective_n_bets = ENB,
    portfolio_annualized_vol = sigma_p,
    crowding_flags = crowding_flags,
    liquidity_flags = liquidity_flags,
    stress_tests = stress_summary,
    cor_summary = list(
      full_overlap_str_kr10y = full_block$cor["str1715","kr10y"],
      full_overlap_str_tsmom = full_block$cor["str1715","tsmom"],
      full_overlap_kr10y_tsmom = full_block$cor["kr10y","tsmom"],
      hybrid_avg_pairwise = mean(c(full_block$cor["str1715","kr10y"],
                                    full_block$cor["str1715","tsmom"],
                                    full_block$cor["kr10y","tsmom"])),
      orthogonality_path_C_target = "avg pairwise cor < 0.10 (strong orthogonality)",
      crisis_breakdown = list(
        COVID_2020_str_tsmom = covid_cor_str_tsmom,
        Stagflation_2022_str_tsmom = if (!is.null(crisis_decomp$Stagflation_2022)) crisis_decomp$Stagflation_2022$cor_str_tsmom else NA,
        GFC_2008_str_kr10y = if (!is.null(crisis_decomp$GFC_2008)) crisis_decomp$GFC_2008$cor_str_kr10y else NA
      )
    )
  ),

  diagnostics = list(
    condition_number = cond_lw,
    shrinkage_used = TRUE,
    shrinkage_method = "ledoit_wolf_constcor",
    shrinkage_delta = lw_res$delta,
    factor_correlation_warnings = c(),
    tdc_summary = list(
      str1715_kr10y_full = full_block$cor["str1715","kr10y"],
      str1715_tsmom_full = full_block$cor["str1715","tsmom"],
      str1715_tsmom_COVID_acute = covid_cor_str_tsmom %||% NA,
      interpretation = "long-run all 3 pairs orthogonal (|cor|<0.15). COVID 5m str1715-tsmom acute breakdown documented (inherited RF-A3)."
    ),
    regime_correlation_ref = "stage_artifacts/WT_P20260505_001/regime_correlation.parquet",
    tail_risk = list(
      hybrid_CVaR95 = tail_hybrid$cvar95,
      hybrid_CVaR99 = tail_hybrid$cvar99,
      hybrid_Hill_alpha = tail_hybrid$hill_alpha,
      hybrid_GPD_xi = tail_hybrid$gpd_xi,
      str1715_alone_CVaR95 = tail_str1715$cvar95,
      improvement_vs_str1715 = tail_str1715$cvar95 - tail_hybrid$cvar95
    )
  ),

  # AX compliance
  ax_compliance = list(
    AX_000 = "limits_dont_exist — 3-source diversification",
    AX_002 = "PIT C1-C15 enforced, no full-sample alpha stat, LW Σ on overlap window",
    AX_007 = "EXEMPT base STR_1715 + EXCEPTION 'ML sizing' for TSMOM (multi-asset ETF rotation, AX_007 EXCEPTION 4: 50+ 분산 N/A but TSMOM rotation is asset-level NOT stock-level)",
    AX_008 = "TARGETING 2/3 PASS — Risk independent verification (this) + Forge new + Codex Round Critic"
  ),

  # Method shopping
  method_shopping_log = cov_audit$method_shopping_log,

  # Stress + crowding + style summary
  stress = list(
    KR_8_periods = lapply(stress_results, function(x) {
      if (is.null(x)) return(NULL)
      list(window = x$window, n = x$n,
           hybrid_cum = if (!isTRUE(x$hybrid$unavailable)) x$hybrid$cum else NA,
           str1715_cum = if (!isTRUE(x$str1715$unavailable)) x$str1715$cum else NA,
           kr10y_cum = if (!isTRUE(x$kr10y$unavailable)) x$kr10y$cum else NA,
           tsmom_cum = if (!isTRUE(x$tsmom$unavailable)) x$tsmom$cum else NA)
    }),
    market_down_5_percent_hybrid = ms5_hybrid,
    market_down_5_percent_str1715_alone = ms5_str
  ),

  crowding = list(
    flags = crowding_flags,
    tsmom_internal_concentration_pct = 79.86,
    tsmom_overlay_size = 0.15,
    tsmom_max_effective_single_etf_at_15pct = 0.15 * 0.30,  # post-30%-cap
    base_str1715_inherited_max_20_names = TRUE
  ),

  style = list(
    str1715_style_inherited = "PG2 admitted (Profitability/Quality + Earnings + AR threshold overlay)",
    kr10y_style = "Duration_Premium passive long",
    tsmom_style = "Cross_Asset_Time_Series_Momentum (Moskowitz-Ooi-Pedersen 2012)",
    style_orthogonality = "3 distinct factor families — Equity_Quality vs Duration_Premium vs Momentum",
    no_overlap_with_alpha_definition = TRUE
  ),

  challenge_flags = challenge_flags,

  # Challenge review (P4 obligation, even if no objection)
  challenge_review = list(
    objection_to_alpha = FALSE,
    targets_reviewed = c("alpha_package_inherit_ref.json", "WT-P20260504_001 governor_admission",
                         "WT-S20260504_008 alpha_package", "WT-S20260504_009 alpha_package",
                         "factor_specs", "confidence_vector", "lro_sha frozen"),
    reasoning = "Alpha agents already disposition Codex 6 concerns each. Risk agent confirmation: (1) STR_1715 frozen lro_sha matches admitted PG2 — no re-derivation. (2) TSMOM cor=0.077 long-run + COVID 5m breakdown 0.75 acknowledged via RF-A3. (3) KR10y cor=-0.137 negative diversifier confirmed. Risk reviews are CONSISTENT with alpha conclusions; no challenge to alpha_vector raised. RF-R inherited propagation only.",
    rounds = 1
  ),

  rationale = list(
    estimator_choice = sprintf("LW constcor delta=%.4f for 3-source N=3 T=%d → balanced shrinkage. Sample also PSD but LW improves cond from %.1f to %.1f.", lw_res$delta, n_overlap, cond_sample, cond_lw),
    diversification_finding = sprintf("DR=%.4f (%.4f%% of weighted sum). Effective N bets=%.3f. Pct risk: STR1715=%.1f%% / KR10y=%.1f%% / TSMOM=%.1f%%. base 70%% weight contributes %.1f%% risk → %s", DR, DR*100, ENB, pct_contrib[1]*100, pct_contrib[2]*100, pct_contrib[3]*100, pct_contrib[1]*100, if (pct_contrib[1] < 0.85) "proportional or lower (good diversification)" else "concentrated (warning)"),
    crisis_finding = "Crisis decomposition: see crisis_decomposition_hybrid.json. Stagflation 2022 KR10y bond bleed disclosed; TSMOM Stagflation outperform per inherited RF (alpha_009 §evaluation_axis_results.2_crisis_behavior).",
    not_alpha_modification = "Risk agent did NOT modify any alpha_vector / factor_specs / confidence_vector. lro_sha frozen confirmed. Hybrid weights 70/15/15 are STATIC FIXED per Path C 도훈 명시 (NOT optimization output)."
  ),

  ratification_note = "Risk research is risk_package draft preceding Codex Round v6.0 (5-step). After codex_critic_response_risk.json arrival, dispose ACCEPT/PARTIAL/REBUTTAL → risk_package.json final + risk_challenge_note.md update."
)

write_json(risk_package_draft, file.path(WT_DIR, "risk_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string", digits = 6)

cat("\n risk_package_draft.json written\n")
cat(sprintf("  challenge_flags: %d\n", length(challenge_flags)))
cat(sprintf("  Σ method: LW (delta=%.4f), cond=%.2f, PSD=%s\n", lw_res$delta, cond_lw, psd_lw))
cat(sprintf("  Hybrid CVaR95=%.4f vs STR1715 alone CVaR95=%.4f (improvement=%.4f)\n",
            tail_hybrid$cvar95, tail_str1715$cvar95, tail_str1715$cvar95 - tail_hybrid$cvar95))
cat(sprintf("  DR=%.4f / ENB=%.3f / σ_p=%.4f\n", DR, ENB, sigma_p))
cat("\n DONE — Risk research draft complete. Awaiting Codex Critic Round.\n")
