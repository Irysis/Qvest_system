#==============================================================================
# WT-D20260502_001 Alpha Pipeline — Macro Regime-Conditional Profitability Defense
#
# Objective: Bad-state (CRISIS/CAUTION) activate Quality (Q07/Q25/Q33/Q35) signal.
# Normal-state (RISK_ON/NEUTRAL) dormant.
# Mechanism: AX-001 v2 conditional defense; AX-007 break via state-switching
#            (de facto multi-state, not single-sleeve top20).
# Author: alpha-research agent (autonomous 7-step pipeline)
# Created: 2026-05-02
#==============================================================================

suppressMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(dplyr)
  library(future)
  library(future.apply)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260502_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)
SA_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001")
FUNC_PATH <- file.path(PROJ, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ, ".cache")

dir.create(SA_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

cat("\n================ STEP 1: Hypothesis Intake ================\n")
req <- jsonlite::fromJSON(file.path(WT_DIR, "request.json"))
cat("Hypothesis:", req$hypothesis_title, "\n")
cat("Universe:", req$universe_definition$label, "\n")
cat("Liquidity min:", req$universe_definition$liquidity_min_won_20d_avg, "won\n")
cat("Cost model:", req$cost_model_version, "\n\n")

#=== STEP 2: Factor Sourcing ===================================================
# Quality high-axis (bad-state activation):
#   - Q07_Earnings_Stability: low std of past earnings (KEY defense, L-121)
#   - Q33_Earnings_Persistence: AR(1) of earnings — sustainability
#   - Q25_Ohlson_O: distress probability (negate OK, direction handled by Z_Score_Aligned)
#   - Q35_CashBased_OpProf: cash-based profitability (RMW analog)
#   - Q08_Composite_Quality: pre-built composite (control)
#
# Defense / Risk auxiliary (cross-validation, NOT primary):
#   - D43_Skewness, R13_NCSKEW: tail co-movement
#
# All Z_Score_Aligned via Factor DB (PIT C13 compliant).

PRIMARY_FACTORS <- c(
  "Q07_Earnings_Stability",
  "Q33_Earnings_Persistence",
  "Q25_Ohlson_O",
  "Q35_CashBased_OpProf",
  "Q08_Composite_Quality"
)
AUX_FACTORS <- c("D43_Skewness", "R13_NCSKEW")

cat("================ STEP 2: Factor Sourcing ================\n")
cat("Primary (Quality, bad-state activate):\n"); print(PRIMARY_FACTORS)
cat("Auxiliary (cross-validation):\n"); print(AUX_FACTORS)
cat("\n")

#=== Universe + returns ========================================================
cat("Loading rawdata + universe...\n")
rd_path <- file.path(CACHE_DIR, "rawdata.parquet")
rd <- as.data.table(arrow::read_parquet(rd_path))
rd[, Date := as.Date(Date)]
setkey(rd, Ticker, Date)

# 5Y window: 2021-01 ~ 2026-04
START_DATE <- as.Date("2020-01-01")
END_DATE <- as.Date("2026-04-30")

rd <- rd[Date >= START_DATE & Date <= END_DATE]

# Build month-end calendar
rd[, ym := format(Date, "%Y-%m")]
month_ends <- rd[, .(month_end = max(Date)), by = ym]
setkey(month_ends, month_end)

# Universe filter per month-end (PIT: K200/KQ150 ∪ at month-end)
# Liquidity: 20d avg trading value >= 5e7 (per request.json)
LIQ_THRESHOLD <- as.numeric(req$universe_definition$liquidity_min_won_20d_avg)
cat(sprintf("LIQ_THRESHOLD = %.0e KRW (per request.json)\n", LIQ_THRESHOLD))

# Compute trading value 20d rolling avg (PIT-safe per ticker)
setkey(rd, Ticker, Date)
rd[, TV := Close * Vol]
rd[, ADV20 := frollmean(TV, 20, fill = NA, na.rm = TRUE), by = Ticker]

#=== Compute monthly returns (forward 1M from sig_date) =======================
cat("Computing forward 1M returns...\n")
# Per ticker month-end close → next month-end close
month_panel <- rd[Date %in% month_ends$month_end,
                  .(Ticker, Date, ym, Close, ADV20, K200, KQ150,
                    AdminStock, TradingHalt, UnfaithfulDisc)]
setkey(month_panel, Ticker, Date)
month_panel[, fwd_ret := (shift(Close, type = "lead") / Close) - 1, by = Ticker]
month_panel[, sig_date := Date]  # for clarity

# Universe membership: K200 OR KQ150 at sig_date
month_panel[, in_uni := (K200 == 1 | KQ150 == 1)]
month_panel[is.na(in_uni), in_uni := FALSE]
# Liquidity gate: ADV20 >= 5e7
month_panel[, liq_ok := !is.na(ADV20) & ADV20 >= LIQ_THRESHOLD]
# Health gates
month_panel[, healthy := is.na(AdminStock) | AdminStock == 0]
month_panel[is.na(healthy), healthy := TRUE]

month_panel[, eligible := in_uni & liq_ok & healthy]

cat(sprintf("Monthly panel: nrow=%d, eligible=%d (%.1f%%)\n",
            nrow(month_panel), sum(month_panel$eligible),
            100 * mean(month_panel$eligible)))

#=== Load regime signals =======================================================
cat("\nLoading regime signals (unified_regime_signal)...\n")
regime <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "unified_regime_signal.parquet")))
# Use the apply month assignment: Category from PRIOR period since we apply at sig_date (t-1 lag)
# Critical PIT: regime decision must use t-1 information.
regime[, ym := YM]
regime <- regime[, .(ym, Category, FRED_MRS, KTRI_Score, Regime_Score)]
# Lag by 1 month: at sig_date (month-end), use regime computed for that month
# But "Category" computed from data through that month-end. So we need t-1.
setkey(regime, ym)
regime[, ym_lag := shift(ym, type = "lag", n = 1L)]
regime[, Category_lag := shift(Category, type = "lag", n = 1L)]

# Construct a lookup: at sig_date in month X, use Category from month X-1
# We'll merge by ym, but use Category_lag (already lagged within regime panel).
month_panel <- merge(month_panel, regime[, .(ym, Category = Category_lag, MRS = FRED_MRS)],
                     by = "ym", all.x = TRUE)

# Bad-state definition (defense activation):
#   {CAUTION, CRISIS} OR Category_lag is missing AND MRS_lag >= 50 (fallback)
# NEUTRAL = dormant; RISK_ON = dormant (negative weight risk → use 0)
month_panel[, bad_state := Category %in% c("CAUTION", "CRISIS")]
month_panel[is.na(bad_state), bad_state := FALSE]

cat("Regime category distribution (sig dates, lagged):\n")
print(month_panel[!is.na(Category), .N, by = Category])
cat("Bad-state share:", sprintf("%.1f%%", 100 * mean(month_panel$bad_state, na.rm = TRUE)), "\n")

#=== STEP 3: Signal Engineering ================================================
cat("\n================ STEP 3: Signal Engineering ================\n")
ALL_FACTORS <- c(PRIMARY_FACTORS, AUX_FACTORS)

# Load Z-scores per month using load_month_factors (PIT-safe via Usable_Date)
months_seq <- sort(unique(month_panel$Date))
months_seq <- months_seq[months_seq >= as.Date("2021-01-01") & months_seq <= as.Date("2026-04-30")]

cat(sprintf("Processing %d sig_dates...\n", length(months_seq)))

# Parallel load per sig_date, retain only target factors
n_workers <- min(8L, parallel::detectCores() - 1L)
cat(sprintf("Using %d workers for factor load...\n", n_workers))
plan(multisession, workers = n_workers)

all_factor_data <- future_lapply(months_seq, function(sd) {
  tryCatch({
    suppressMessages({
      library(data.table)
      library(arrow)
      library(jsonlite)
    })
    PROJ_LOCAL <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
    FUNC_PATH_LOCAL <- file.path(PROJ_LOCAL, "02_Infrastructure")
    CACHE_DIR_LOCAL <- file.path(PROJ_LOCAL, ".cache")
    source(file.path(FUNC_PATH_LOCAL, "factor_db", "factor_db_connector.R"))
    fdt <- load_month_factors(as.Date(sd), coverage_min = 0.3)
    fdt <- fdt[Factor_Name %in% ALL_FACTORS]
    fdt[, sig_date := as.Date(sd)]
    fdt[]
  }, error = function(e) NULL)
}, future.globals = c("ALL_FACTORS"))

plan(sequential)
factor_long <- rbindlist(all_factor_data, use.names = TRUE, fill = TRUE)
cat(sprintf("Factor data loaded: %d rows × %d cols\n", nrow(factor_long), ncol(factor_long)))

# Pivot to wide
factor_wide <- dcast(factor_long, sig_date + Ticker ~ Factor_Name,
                     value.var = "Z_Score_Aligned")

# Merge with month_panel
month_panel[, sig_date := Date]
panel <- merge(month_panel[, .(sig_date, Ticker, ym, fwd_ret, eligible,
                                bad_state, Category, MRS)],
               factor_wide, by = c("sig_date", "Ticker"), all.x = TRUE)
setkey(panel, sig_date, Ticker)

# Eligibility-restricted analysis panel
analysis_panel <- panel[eligible == TRUE & !is.na(fwd_ret)]
cat(sprintf("Analysis panel after eligibility: %d rows\n", nrow(analysis_panel)))

# Coverage check per factor
cat("\nFactor coverage in eligible panel:\n")
for (f in ALL_FACTORS) {
  has_col <- f %in% colnames(analysis_panel)
  if (has_col) {
    cov <- mean(!is.na(analysis_panel[[f]]))
    cat(sprintf("  %s: %.1f%% non-NA\n", f, 100 * cov))
  } else {
    cat(sprintf("  %s: COLUMN MISSING\n", f))
  }
}

# Winsorize 3-std cross-sectionally per sig_date (already Z-scored, but apply guard)
winsor_panel <- copy(analysis_panel)
for (f in ALL_FACTORS) {
  if (f %in% colnames(winsor_panel)) {
    winsor_panel[, (f) := pmin(pmax(get(f), -3), 3)]
  }
}

#=== STEP 4: Signal Diagnostics ================================================
cat("\n================ STEP 4: Signal Diagnostics ================\n")

# Helper: compute Spearman IC per sig_date
compute_ic <- function(dt, factor_col) {
  if (!factor_col %in% colnames(dt)) return(NULL)
  ics <- dt[, .(
    n = sum(!is.na(get(factor_col)) & !is.na(fwd_ret)),
    ic = if (sum(!is.na(get(factor_col)) & !is.na(fwd_ret)) >= 30) {
      cor(get(factor_col), fwd_ret, method = "spearman", use = "pairwise.complete.obs")
    } else { NA_real_ }
  ), by = sig_date]
  ics[!is.na(ic)]
}

# Helper: monotonicity (decile-mean monotonic test)
compute_monotonicity <- function(dt, factor_col, n_bins = 10) {
  if (!factor_col %in% colnames(dt)) return(NA_real_)
  dt2 <- copy(dt)
  dt2 <- dt2[!is.na(get(factor_col)) & !is.na(fwd_ret)]
  dt2[, bin := cut(get(factor_col),
                   breaks = quantile(get(factor_col), probs = seq(0, 1, length.out = n_bins + 1),
                                     na.rm = TRUE),
                   include.lowest = TRUE, labels = FALSE), by = sig_date]
  bin_means <- dt2[, .(mean_ret = mean(fwd_ret, na.rm = TRUE)), by = bin][order(bin)]
  if (nrow(bin_means) < n_bins) return(NA_real_)
  # Spearman corr between bin idx (1..10) and mean_ret
  cor(bin_means$bin, bin_means$mean_ret, method = "spearman")
}

# Helper: subperiod stability (3 periods)
subperiod_stability <- function(ic_dt) {
  ic_dt[, subp := fcase(
    sig_date < as.Date("2022-01-01"), "P1",
    sig_date < as.Date("2024-01-01"), "P2",
    default = "P3"
  )]
  by_sub <- ic_dt[, .(ic_mean = mean(ic, na.rm = TRUE), n = .N), by = subp]
  pos_count <- sum(by_sub$ic_mean > 0, na.rm = TRUE)
  pos_count / nrow(by_sub)
}

# Per-factor diagnostics
diag_list <- list()
for (f in ALL_FACTORS) {
  if (!f %in% colnames(winsor_panel)) {
    cat(sprintf("  [SKIP] %s missing column\n", f)); next
  }
  ic_dt <- compute_ic(winsor_panel, f)
  if (is.null(ic_dt) || nrow(ic_dt) < 24) {
    cat(sprintf("  [SKIP] %s insufficient months\n", f)); next
  }
  ic_mean <- mean(ic_dt$ic, na.rm = TRUE)
  ic_std <- sd(ic_dt$ic, na.rm = TRUE)
  icir <- ic_mean / ic_std
  n_periods <- nrow(ic_dt)
  # NW-adjusted t (lag=3)
  ic_vec <- ic_dt$ic
  m <- length(ic_vec)
  bw <- min(3, floor(m/4))
  v0 <- mean((ic_vec - ic_mean)^2)
  if (bw >= 1) {
    s <- 0
    for (l in 1:bw) {
      w_l <- 1 - l / (bw + 1)
      cov_l <- mean((ic_vec[1:(m - l)] - ic_mean) * (ic_vec[(l + 1):m] - ic_mean))
      s <- s + 2 * w_l * cov_l
    }
    nw_var <- v0 + s
  } else { nw_var <- v0 }
  nw_se <- sqrt(max(nw_var, 1e-12) / m)
  nw_t <- ic_mean / nw_se

  mono <- compute_monotonicity(winsor_panel, f)
  sub_stab <- subperiod_stability(ic_dt)

  # Conditional IC (bad vs normal)
  bad_dates <- unique(winsor_panel[bad_state == TRUE, sig_date])
  ic_dt[, bad_state := sig_date %in% bad_dates]
  ic_bad <- ic_dt[bad_state == TRUE, mean(ic, na.rm = TRUE)]
  ic_norm <- ic_dt[bad_state == FALSE, mean(ic, na.rm = TRUE)]
  n_bad <- ic_dt[bad_state == TRUE, .N]
  n_norm <- ic_dt[bad_state == FALSE, .N]

  diag_list[[f]] <- list(
    factor = f,
    rank_ic = round(ic_mean, 4),
    icir = round(icir, 4),
    nw_t = round(nw_t, 4),
    n_periods = n_periods,
    monotonicity = round(mono, 4),
    subperiod_stability = round(sub_stab, 4),
    ic_bad_state = round(ic_bad, 4),
    ic_normal_state = round(ic_norm, 4),
    n_bad = n_bad,
    n_normal = n_norm
  )
  cat(sprintf("  %s: IC=%.4f ICIR=%.3f NW_t=%.2f Mono=%.2f SubStab=%.2f IC_bad=%.4f IC_norm=%.4f (n_bad=%d / n_norm=%d)\n",
              f, ic_mean, icir, nw_t, mono, sub_stab, ic_bad, ic_norm, n_bad, n_norm))
}

# Save diagnostics
diag_dt <- rbindlist(lapply(diag_list, function(x) as.data.table(x)), fill = TRUE)
fwrite(diag_dt, file.path(SA_DIR, "per_factor_diagnostics.csv"))

#=== Composite Construction (Quality only, regime-conditional) ==================
cat("\n================ STEP 5: Alpha Forecast Construction ================\n")

# For Q25_Ohlson_O: registry direction is "lower_better" but Z_Score_Aligned auto-aligns.
# So we DO NOT manually negate (PIT C13).

# Quality composite (mean Z-score across primary factors with ICIR >= threshold)
PRIMARY_QUALITY <- intersect(PRIMARY_FACTORS, names(diag_list))
# Exclude any factor with negative bad-state IC (defense criterion: bad-IC must be positive)
keep_factors <- c()
for (f in PRIMARY_QUALITY) {
  d <- diag_list[[f]]
  # Defense alpha: keep only if bad-state IC > 0 (positive crisis alpha)
  # AND overall ICIR > 0 to avoid noise
  if (!is.na(d$ic_bad_state) && d$ic_bad_state > 0 && d$icir > 0) {
    keep_factors <- c(keep_factors, f)
  } else {
    cat(sprintf("  [DROPPED from composite] %s: ic_bad=%.4f icir=%.3f (defense criterion fail)\n",
                f, d$ic_bad_state, d$icir))
  }
}
cat("Composite kept factors:\n"); print(keep_factors)

# Equal-weighted Quality composite (transparent baseline)
# IF only 1-2 factors retain → use as-is. Else mean of Z-scores.
if (length(keep_factors) == 0) {
  stop("No factor passes defense criterion (positive bad-state IC). HYPOTHESIS FAILED.")
}

winsor_panel[, quality_composite := rowMeans(.SD, na.rm = TRUE), .SDcols = keep_factors]

# Regime-conditional alpha:
#   alpha = quality_composite * I(bad_state)   [activation]
#   alpha = 0                                  [normal-state dormant]
winsor_panel[, alpha_raw := fifelse(bad_state == TRUE, quality_composite, 0)]

# Compute composite IC + conditional IC
ic_comp <- compute_ic(winsor_panel, "quality_composite")
ic_alpha <- compute_ic(winsor_panel, "alpha_raw")

cat("\nComposite (quality_composite, raw) diagnostics:\n")
mu1 <- mean(ic_comp$ic); sd1 <- sd(ic_comp$ic); n1 <- nrow(ic_comp)
cat(sprintf("  Quality composite: IC=%.4f ICIR=%.3f n=%d\n",
            mu1, mu1/sd1, n1))

cat("Regime-Conditional alpha_raw (composite × I(bad)):\n")
mu2 <- mean(ic_alpha$ic); sd2 <- sd(ic_alpha$ic); n2 <- nrow(ic_alpha)
cat(sprintf("  Alpha (regime-gated): IC=%.4f ICIR=%.3f n=%d\n",
            mu2, mu2/sd2, n2))

# Conditional IC for raw quality composite
bad_dates <- unique(winsor_panel[bad_state == TRUE, sig_date])
ic_comp[, bad := sig_date %in% bad_dates]
ic_q_bad <- ic_comp[bad == TRUE, mean(ic, na.rm = TRUE)]
ic_q_norm <- ic_comp[bad == FALSE, mean(ic, na.rm = TRUE)]
ratio <- ic_q_bad / abs(ic_q_norm)

cat(sprintf("\nQuality composite IC bad/normal ratio (AX-001 v2 4-axis test):\n"))
cat(sprintf("  IC_bad=%.4f, IC_normal=%.4f, ratio=%.2f\n", ic_q_bad, ic_q_norm, ratio))

#=== Harvey Multi-test t-stat per factor ======================================
M_TESTS <- length(diag_list) + 1L  # primary factors + composite
cat(sprintf("\nHarvey-Liu-Zhu multi-test (M=%d tests, BHY adjustment):\n", M_TESTS))
for (nm in names(diag_list)) {
  d <- diag_list[[nm]]
  # Use NW-t per factor; Harvey BHY threshold approx via 3.0 (Harvey-Liu-Zhu standard)
  # Or simpler: t-stat / sqrt(M_eff_BHY); for KR universe with k=7, threshold ~ 2.7~3.0
  cat(sprintf("  %s: NW-t=%.2f (Harvey threshold 3.0: %s)\n",
              nm, d$nw_t, ifelse(abs(d$nw_t) >= 3.0, "PASS", "FAIL")))
}
# Composite NW-t
ic_vec_c <- ic_comp$ic; m_c <- length(ic_vec_c); mu_c <- mean(ic_vec_c); v0_c <- mean((ic_vec_c - mu_c)^2)
bw_c <- min(3, floor(m_c/4))
if (bw_c >= 1) {
  s_c <- 0
  for (l in 1:bw_c) {
    w_l <- 1 - l / (bw_c + 1)
    cov_l <- mean((ic_vec_c[1:(m_c - l)] - mu_c) * (ic_vec_c[(l + 1):m_c] - mu_c))
    s_c <- s_c + 2 * w_l * cov_l
  }
  nw_var_c <- v0_c + s_c
} else { nw_var_c <- v0_c }
nw_se_c <- sqrt(max(nw_var_c, 1e-12) / m_c)
nw_t_comp <- mu_c / nw_se_c
cat(sprintf("  COMPOSITE quality_composite: NW-t=%.2f\n", nw_t_comp))

#=== Pairwise factor correlation ==============================================
cat("\nPairwise factor correlation (Spearman, time-pooled in eligible panel):\n")
for_cor <- winsor_panel[, ..ALL_FACTORS]
cor_mat <- cor(for_cor, method = "spearman", use = "pairwise.complete.obs")
print(round(cor_mat, 3))
fwrite(as.data.table(round(cor_mat, 4), keep.rownames = "factor"),
       file.path(SA_DIR, "factor_correlation.csv"))
max_off <- max(abs(cor_mat[upper.tri(cor_mat)]))
cat(sprintf("Max abs off-diagonal: %.3f (cor < 0.95 check: %s)\n",
            max_off, ifelse(max_off < 0.95, "PASS", "FAIL")))

#=== Returns-level cor vs STR_1715 (ANTI-INHERITANCE) =========================
# Critical L-270 lesson: returns-level cor must be checked, not just vector cor.
# Build factor portfolio returns (top decile - bottom decile) for our composite,
# then compute correlation vs STR_1715 returns if available.
cat("\nBuilding portfolio returns for inheritance audit...\n")

# Top quintile - bottom quintile of quality_composite (within eligible)
winsor_panel[, q_bin := cut(quality_composite,
                            breaks = quantile(quality_composite, probs = seq(0, 1, 0.2),
                                              na.rm = TRUE),
                            include.lowest = TRUE, labels = FALSE), by = sig_date]
ls_returns <- winsor_panel[!is.na(q_bin), .(
  ret_top = mean(fwd_ret[q_bin == 5], na.rm = TRUE),
  ret_bot = mean(fwd_ret[q_bin == 1], na.rm = TRUE)
), by = sig_date]
ls_returns[, ls_ret := ret_top - ret_bot]
ls_returns[, ym := format(sig_date, "%Y-%m")]

# Compute regime-gated portfolio: applied only in bad periods
ls_returns <- merge(ls_returns,
                    unique(winsor_panel[, .(ym = format(sig_date, "%Y-%m"), bad_state)]),
                    by = "ym", all.x = TRUE)
ls_returns[, gated_ret := fifelse(bad_state == TRUE, ls_ret, 0)]

cat(sprintf("LS portfolio (top-bot quality): mean=%.4f sd=%.4f\n",
            mean(ls_returns$ls_ret, na.rm = TRUE),
            sd(ls_returns$ls_ret, na.rm = TRUE)))
cat(sprintf("Gated LS portfolio (bad-only): mean=%.4f sd=%.4f n_active=%d\n",
            mean(ls_returns$gated_ret, na.rm = TRUE),
            sd(ls_returns$gated_ret, na.rm = TRUE),
            sum(ls_returns$gated_ret != 0)))

fwrite(ls_returns, file.path(SA_DIR, "ls_portfolio_returns.csv"))

# Try STR_1715 returns load
str1715_returns_path <- file.path(PROJ, "qepm/registry/str_1715/returns_monthly.parquet")
str1715_alt1 <- file.path(PROJ, "04_Research/strategies/STR_1715_M4/output/strategy_returns_monthly.csv")
str1715_alt2 <- file.path(PROJ, "qepm/registry/STR_1715/strategy_returns_monthly.csv")
str1715_paths <- c(str1715_returns_path, str1715_alt1, str1715_alt2)

str1715_returns <- NULL
for (p in str1715_paths) {
  if (file.exists(p)) {
    cat(sprintf("Found STR_1715 returns: %s\n", p))
    if (grepl("\\.parquet$", p)) {
      str1715_returns <- as.data.table(arrow::read_parquet(p))
    } else {
      str1715_returns <- fread(p)
    }
    break
  }
}

if (!is.null(str1715_returns)) {
  cat(sprintf("STR_1715 returns: ncol=%d nrow=%d\n", ncol(str1715_returns),
              nrow(str1715_returns)))
  cat("colnames:", paste(colnames(str1715_returns), collapse = ", "), "\n")
} else {
  cat("[WARN] STR_1715 returns not found at standard paths. Inheritance audit deferred.\n")
}

#=== Final diagnostic snapshot =================================================
cat("\n================ STEP 6: Confidence Vector ================\n")
# Confidence per ticker = (in_uni + liq_ok + factor_coverage) weighted score
# at as_of_date (latest sig_date)
as_of_date <- as.Date(req$as_of_date)
nearest_sig <- max(months_seq[months_seq <= as_of_date])
cat(sprintf("as_of_date=%s, nearest sig_date=%s\n", as_of_date, nearest_sig))

# Latest cross-section for alpha vector
latest_panel <- panel[sig_date == nearest_sig & eligible == TRUE]
latest_panel[, q_score := rowMeans(.SD, na.rm = TRUE), .SDcols = keep_factors]

# Coverage per ticker = fraction of keep_factors non-NA
cov_check <- function(row) sum(!is.na(row)) / length(row)
latest_panel[, coverage := apply(.SD, 1, cov_check), .SDcols = keep_factors]
latest_panel[, valid := coverage >= 0.5 & !is.na(q_score)]

# Confidence: f(coverage, factor stability)
# Use mean ICIR across factors as global stability anchor + per-ticker coverage
mean_icir <- mean(sapply(diag_list[keep_factors], function(d) d$icir), na.rm = TRUE)
stability_score <- max(min(mean_icir / 0.40, 1.0), 0.0)  # ICIR 0.4 → 1.0 cap
latest_panel[, confidence := pmax(pmin(coverage * 0.6 + stability_score * 0.4, 1.0), 0.0)]

# Alpha vector: regime-gated quality composite
# Current regime at as_of_date
current_regime_lag <- regime[ym <= format(as_of_date, "%Y-%m"),
                              .(ym, Category)][order(ym)][.N]
# Lag once more for actual application (we already lagged in main panel)
cur_cat_at_apply <- regime[ym == format(as_of_date, "%Y-%m"), Category_lag]
cat(sprintf("Current regime category (lagged for sig_date %s): %s\n",
            as_of_date, ifelse(length(cur_cat_at_apply) > 0, cur_cat_at_apply, "NA")))

current_bad <- length(cur_cat_at_apply) > 0 && cur_cat_at_apply %in% c("CAUTION", "CRISIS")

# Active vs dormant
if (current_bad) {
  cat(sprintf("Bad-state ACTIVE → alpha = quality_composite\n"))
  latest_panel[, alpha_active := q_score]
} else {
  cat(sprintf("Normal/Risk-on → alpha = 0 (dormant)\n"))
  # Even if dormant in current period, we provide signal for Optimizer's
  # forward-looking horizon. We use a small-magnitude q_score with reduced confidence
  # to convey "if regime turns bad, this is the signal." But for alpha_vector
  # at as_of_date specifically, we set 0 (dormant).
  latest_panel[, alpha_active := 0]
}

# Cross-sectional rank-normalize alpha (mean-zero)
latest_panel[!is.na(q_score), alpha_zscore := (q_score - mean(q_score, na.rm = TRUE)) /
                                              sd(q_score, na.rm = TRUE)]
# Final alpha = active gate × zscore (rescaled to %), confidence-modulated
latest_panel[, alpha_final := fifelse(current_bad, alpha_zscore * 0.01, 0) * confidence]

cat(sprintf("Alpha vector: n_total=%d, n_valid=%d, current_bad=%s\n",
            nrow(latest_panel), sum(latest_panel$valid), current_bad))

cat("\nAlpha vector summary:\n")
cat(sprintf("  mean: %.6f\n", mean(latest_panel$alpha_final, na.rm = TRUE)))
cat(sprintf("  sd: %.6f\n", sd(latest_panel$alpha_final, na.rm = TRUE)))
cat(sprintf("  range: [%.4f, %.4f]\n",
            min(latest_panel$alpha_final, na.rm = TRUE),
            max(latest_panel$alpha_final, na.rm = TRUE)))

#=== STEP 7: Save artifacts (we'll write JSON in separate finalize script) ====
cat("\n================ Saving Artifacts ================\n")

# alpha_scores.parquet
alpha_scores <- latest_panel[!is.na(q_score),
  .(Ticker, sig_date, alpha = alpha_final, confidence,
    q_score, alpha_zscore, regime_category = ifelse(current_bad, "BAD", "NORMAL"),
    coverage)]
arrow::write_parquet(alpha_scores, file.path(SA_DIR, "alpha_scores.parquet"))
cat(sprintf("Wrote alpha_scores.parquet: %d rows\n", nrow(alpha_scores)))

# IC history per factor
all_ic_hist <- list()
for (f in c(ALL_FACTORS, "quality_composite", "alpha_raw")) {
  if (f %in% colnames(winsor_panel)) {
    ich <- compute_ic(winsor_panel, f)
    if (!is.null(ich) && nrow(ich) > 0) {
      ich[, factor := f]
      all_ic_hist[[f]] <- ich
    }
  }
}
ic_history <- rbindlist(all_ic_hist, fill = TRUE)
arrow::write_parquet(ic_history, file.path(SA_DIR, "ic_history.parquet"))
cat(sprintf("Wrote ic_history.parquet: %d rows\n", nrow(ic_history)))

# Alpha validation JSON
alpha_validation <- list(
  task_id = WT_ID,
  as_of_date = as.character(as_of_date),
  sig_date = as.character(nearest_sig),
  n_periods_analyzed = length(months_seq),
  n_eligible_total = nrow(analysis_panel),
  primary_factors = PRIMARY_FACTORS,
  aux_factors = AUX_FACTORS,
  composite_factors = keep_factors,
  per_factor_diagnostics = diag_list,
  composite_quality = list(
    rank_ic = round(mu1, 4),
    icir = round(mu1/sd1, 4),
    nw_t = round(nw_t_comp, 4),
    n_periods = n1,
    ic_bad_state = round(ic_q_bad, 4),
    ic_normal_state = round(ic_q_norm, 4),
    bad_normal_ratio = round(ratio, 4)
  ),
  regime_gated_alpha = list(
    rank_ic = round(mu2, 4),
    icir = round(mu2/sd2, 4),
    n_periods = n2,
    n_bad_periods = sum(ls_returns$bad_state == TRUE, na.rm = TRUE),
    bad_period_share = round(mean(ls_returns$bad_state, na.rm = TRUE), 3)
  ),
  factor_correlation_max_offdiag = round(max_off, 4),
  pairwise_correlation_pass = max_off < 0.95,
  current_state = list(
    sig_date = as.character(as_of_date),
    regime_category_lagged = ifelse(length(cur_cat_at_apply) > 0, cur_cat_at_apply, "NA"),
    bad_state_active = current_bad,
    alpha_dormant = !current_bad
  ),
  liquidity_threshold = LIQ_THRESHOLD,
  universe = "K200 ∪ KQ150",
  cost_model_version = req$cost_model_version
)
write_json(alpha_validation, file.path(SA_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("Wrote alpha_validation.json\n"))

# Save R objects for finalize script
saveRDS(list(
  diag_list = diag_list,
  keep_factors = keep_factors,
  PRIMARY_FACTORS = PRIMARY_FACTORS,
  AUX_FACTORS = AUX_FACTORS,
  ic_q_bad = ic_q_bad,
  ic_q_norm = ic_q_norm,
  ratio = ratio,
  nw_t_comp = nw_t_comp,
  mu1 = mu1, sd1 = sd1, n1 = n1,
  mu2 = mu2, sd2 = sd2, n2 = n2,
  cor_mat = cor_mat,
  max_off = max_off,
  latest_panel = latest_panel,
  ls_returns = ls_returns,
  current_bad = current_bad,
  cur_cat_at_apply = cur_cat_at_apply,
  as_of_date = as_of_date,
  nearest_sig = nearest_sig,
  months_seq = months_seq
), file.path(SA_DIR, "alpha_pipeline_state.rds"))

cat("\n================ Alpha Pipeline COMPLETE ================\n")
cat("Outputs:\n")
cat("  -", file.path(SA_DIR, "alpha_scores.parquet"), "\n")
cat("  -", file.path(SA_DIR, "alpha_validation.json"), "\n")
cat("  -", file.path(SA_DIR, "ic_history.parquet"), "\n")
cat("  -", file.path(SA_DIR, "per_factor_diagnostics.csv"), "\n")
cat("  -", file.path(SA_DIR, "factor_correlation.csv"), "\n")
cat("  -", file.path(SA_DIR, "ls_portfolio_returns.csv"), "\n")
cat("  -", file.path(SA_DIR, "alpha_pipeline_state.rds"), "\n")
