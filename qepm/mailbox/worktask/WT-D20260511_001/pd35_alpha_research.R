#==============================================================================
# WT-D20260511_001 PD35 — Multi-Axis Quality × Tail Risk × Earnings Quality
#
# Goal: 5th orthogonal alpha source for PG2 (C_softmax) enhancement.
# Target: SR target 2.0 vs raw 1.008 = gap 0.99. New source needs cor<0.30 with
#         PD27 1715 H1 (C_softmax base) + crisis IC > 0 (AX-001 v2 conditional defense).
#
# Approach: Literature-rich 3-axis composite using EXPANDING 36m PIT-strict
# direction alignment (NO full-sample sign flip). Mechanisms:
#   AXIS 1 — Profitability Quality (Novy-Marx 2013, Asness-Frazzini-Pedersen 2014):
#            Q10_Gross_Margin + Q01_GPA + Q17_ROIC (multi-axis quality composite)
#   AXIS 2 — Tail Risk Reversal (Bali-Cakici-Whitelaw 2011 MAX effect,
#            Boyer-Mitton-Vorkink 2010 ex-ante skewness):
#            M22_Max_Return (lottery penalty, IC-aligned) + D44_Kurtosis (downside)
#   AXIS 3 — Earnings Quality / Accrual Stability (Sloan 1996,
#            Hirshleifer-Hou-Teoh-Zhang 2004): AC22_Accrual_Volatility + Q33_Earnings_Persistence
#
# Compliance:
#   - PIT C13/C14/C15: load_month_factors() expanding 36m, sig_date passed
#   - AX-001 v2 conditional defense: crisis IC test
#   - AX-007 Exception 1 multi-sleeve integration (5th sleeve added to S4 v2)
#   - AX-004 EXCLUSION: NOT single-signal long-only quality (multi-axis composite)
#   - AX-005 EXCLUSION: NOT defense low-beta top20 (tail risk reversal mech)
#   - Hurdle v2.2 robustness (subperiod stability)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Setup ----
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
FACTOR_DB_DIR <- file.path(PROJ_ROOT, ".cache/factor_db")

# Source connector
FUNC_PATH <- file.path(PROJ_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

OUTPUT_PARQUET <- file.path(STAGE_DIR, "alpha_scores_pd35_quality_tail_earnings.parquet")
DIAGNOSTIC_JSON <- file.path(WT_DIR, "pd35_diagnostic_log.json")

# ---- Configuration ----
# Factor set per axis (literature-grounded)
AXIS_PROFIT_QUALITY <- c("Q10_Gross_Margin", "Q01_GPA", "Q17_ROIC")
AXIS_TAIL_RISK      <- c("M22_Max_Return", "D44_Kurtosis")
AXIS_EARNINGS_QUAL  <- c("AC22_Accrual_Volatility", "Q33_Earnings_Persistence")

ALL_FACTORS <- c(AXIS_PROFIT_QUALITY, AXIS_TAIL_RISK, AXIS_EARNINGS_QUAL)
N_FACTORS <- length(ALL_FACTORS)

# Axis weights (EW across 3 axes)
AXIS_WEIGHTS <- c(profit_quality = 1/3, tail_risk = 1/3, earnings_quality = 1/3)

# Date range — match PD27 (298 months, 2001-07 ~ 2026-04)
sig_dates_all <- seq(as.Date("2001-07-01"), as.Date("2026-04-01"), by = "month")
cat(sprintf("[PD35] Date range: %s to %s (%d months)\n",
            min(sig_dates_all), max(sig_dates_all), length(sig_dates_all)))

# Load RAWDATA for forward returns (Ret_1m)
RAWDATA_PATH <- file.path(PROJ_ROOT, ".cache/factor_db_daily/rawdata_cache.rds")
if (!file.exists(RAWDATA_PATH)) {
  # fallback: load monthly returns from PD27 alpha_scores
  cat("[PD35] RAWDATA cache absent — using PD27 Ret_1m column\n")
  pd27 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")))
  pd27_ret <- pd27[, .(Date, Ticker, Ret_1m)]
  setkey(pd27_ret, Date, Ticker)
} else {
  raw <- readRDS(RAWDATA_PATH)
  raw_dt <- as.data.table(raw)
  setnames(raw_dt, old = c("Date", "Ticker", "Ret"), new = c("Date", "Ticker", "Ret_d"), skip_absent = TRUE)
  pd27_ret <- raw_dt[, .(Date, Ticker, Ret_1m = Ret_d)]
  setkey(pd27_ret, Date, Ticker)
}

# ---- Step 1: Loop sig_dates and build composite alpha ----
build_pd35_alpha <- function(sig_dates_iter) {
  result_list <- list()
  for (i in seq_along(sig_dates_iter)) {
    sd <- sig_dates_iter[i]
    if (i %% 12 == 0) cat(sprintf("[PD35] sig_date %s (%d/%d)\n", sd, i, length(sig_dates_iter)))
    factors_dt <- tryCatch(
      load_month_factors(sd, coverage_min = 0.05),
      error = function(e) { cat(sprintf("[ERR] %s: %s\n", sd, conditionMessage(e))); NULL }
    )
    if (is.null(factors_dt) || nrow(factors_dt) == 0) next
    factors_dt <- factors_dt[Factor_Name %in% ALL_FACTORS]
    if (nrow(factors_dt) == 0) next
    # Wide format
    wide <- dcast(factors_dt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned", fill = NA)
    present_factors <- intersect(names(wide), ALL_FACTORS)
    if (length(present_factors) < 4) next  # need ≥4/7 factors min coverage
    # ---- Axis composites (EW within axis, ignoring NA) ----
    axis_profit_cols <- intersect(AXIS_PROFIT_QUALITY, present_factors)
    axis_tail_cols   <- intersect(AXIS_TAIL_RISK, present_factors)
    axis_earn_cols   <- intersect(AXIS_EARNINGS_QUAL, present_factors)
    if (length(axis_profit_cols) == 0 || length(axis_tail_cols) == 0 || length(axis_earn_cols) == 0) next
    # row-mean per axis
    wide[, axis_profit := rowMeans(.SD, na.rm = TRUE), .SDcols = axis_profit_cols]
    wide[, axis_tail   := rowMeans(.SD, na.rm = TRUE), .SDcols = axis_tail_cols]
    wide[, axis_earn   := rowMeans(.SD, na.rm = TRUE), .SDcols = axis_earn_cols]
    # Re-standardize each axis (cross-sectional z-score)
    for (col in c("axis_profit", "axis_tail", "axis_earn")) {
      mu <- mean(wide[[col]], na.rm = TRUE)
      sg <- sd(wide[[col]], na.rm = TRUE)
      if (!is.na(sg) && sg > 1e-9) wide[, (col) := (.SD[[1]] - mu) / sg, .SDcols = col]
    }
    # ---- Composite alpha (EW across 3 axes) ----
    wide[, alpha_pd35 := AXIS_WEIGHTS["profit_quality"] * axis_profit +
                         AXIS_WEIGHTS["tail_risk"]      * axis_tail +
                         AXIS_WEIGHTS["earnings_quality"] * axis_earn]
    # Final cross-sectional z-score
    mu <- mean(wide$alpha_pd35, na.rm = TRUE)
    sg <- sd(wide$alpha_pd35, na.rm = TRUE)
    if (!is.na(sg) && sg > 1e-9) wide[, alpha_pd35 := (alpha_pd35 - mu) / sg]
    result_list[[as.character(sd)]] <- data.table(
      Date = sd, Ticker = wide$Ticker, alpha_pd35 = wide$alpha_pd35,
      axis_profit = wide$axis_profit, axis_tail = wide$axis_tail, axis_earn = wide$axis_earn,
      n_factors_used = length(present_factors)
    )
  }
  rbindlist(result_list, use.names = TRUE, fill = TRUE)
}

cat("[PD35] Building composite alpha across", length(sig_dates_all), "sig_dates...\n")
alpha_dt <- build_pd35_alpha(sig_dates_all)

cat(sprintf("[PD35] Built %d rows across %d sig_dates\n", nrow(alpha_dt), uniqueN(alpha_dt$Date)))

# ---- Step 2: Merge forward returns ----
alpha_dt <- merge(alpha_dt, pd27_ret, by = c("Date", "Ticker"), all.x = TRUE)
cat(sprintf("[PD35] After Ret_1m merge: %d rows, %d with non-NA Ret_1m\n",
            nrow(alpha_dt), sum(!is.na(alpha_dt$Ret_1m))))

# ---- Step 3: IC diagnostics ----
ic_per_date <- alpha_dt[!is.na(Ret_1m) & !is.na(alpha_pd35),
                        .(rank_IC = suppressWarnings(cor(alpha_pd35, Ret_1m, method = "spearman")),
                          N_stocks = .N),
                        by = Date]
ic_per_date <- ic_per_date[!is.na(rank_IC)]
mean_IC <- mean(ic_per_date$rank_IC, na.rm = TRUE)
sd_IC <- sd(ic_per_date$rank_IC, na.rm = TRUE)
ICIR_full <- mean_IC / sd_IC * sqrt(length(ic_per_date$rank_IC))
ICIR_naive <- mean_IC / sd_IC
t_naive <- mean_IC / (sd_IC / sqrt(nrow(ic_per_date)))

# Newey-West SE with 6 lag
nw_t <- tryCatch({
  ic_demean <- ic_per_date$rank_IC - mean_IC
  gamma0 <- mean(ic_demean^2)
  L <- 6
  acov <- 0
  for (h in 1:L) {
    weight <- 1 - h / (L + 1)
    g_h <- mean(ic_demean[1:(length(ic_demean) - h)] * ic_demean[(h + 1):length(ic_demean)])
    acov <- acov + 2 * weight * g_h
  }
  nw_var <- (gamma0 + acov) / nrow(ic_per_date)
  nw_se <- sqrt(nw_var)
  mean_IC / nw_se
}, error = function(e) NA)

cat(sprintf("[PD35] mean_IC=%.4f sd_IC=%.4f ICIR_full=%.4f ICIR_naive=%.4f t_naive=%.4f t_NW6=%.4f\n",
            mean_IC, sd_IC, ICIR_full, ICIR_naive, t_naive, nw_t))

# ---- Step 4: Subperiod stability ----
ic_per_date[, period := fcase(
  Date < as.Date("2009-01-01"), "P1_2001_2008",
  Date < as.Date("2018-01-01"), "P2_2009_2017",
  default = "P3_2018_2026"
)]
subperiod_ic <- ic_per_date[, .(rank_IC = mean(rank_IC, na.rm = TRUE), n_months = .N), by = period]
subperiod_ic[, period := factor(period, levels = c("P1_2001_2008", "P2_2009_2017", "P3_2018_2026"))]
subperiod_ic <- subperiod_ic[order(period)]
min_max_ratio <- min(subperiod_ic$rank_IC) / max(subperiod_ic$rank_IC)
sign_consistency <- all(sign(subperiod_ic$rank_IC) == sign(subperiod_ic$rank_IC[1]))
cat(sprintf("[PD35] Subperiod min_max_ratio=%.4f sign_consistency=%s\n", min_max_ratio, sign_consistency))
print(subperiod_ic)

# ---- Step 5: Crisis-conditional IC (AX-001 v2) ----
# Crisis windows per PD32 standard (2008 GFC + Euro 2011 + China 2015 + COVID 2020 + Stagflation 2022)
crisis_ranges <- list(
  c("2008-09-01", "2009-03-01"),
  c("2011-08-01", "2011-12-01"),
  c("2015-06-01", "2016-02-01"),
  c("2020-02-01", "2020-04-01"),
  c("2022-05-01", "2022-10-01")
)
ic_per_date[, regime := "normal"]
for (r in crisis_ranges) {
  ic_per_date[Date >= as.Date(r[1]) & Date <= as.Date(r[2]), regime := "crisis"]
}
ic_regime <- ic_per_date[, .(rank_IC = mean(rank_IC, na.rm = TRUE), n_months = .N), by = regime]
crisis_IC <- ic_regime[regime == "crisis", rank_IC]
normal_IC <- ic_regime[regime == "normal", rank_IC]
crisis_normal_ratio <- crisis_IC / normal_IC
ax001_v2_pass <- crisis_IC > 0 && crisis_normal_ratio > 1.0
cat(sprintf("[PD35] crisis_IC=%.4f normal_IC=%.4f ratio=%.4f AX-001-v2-pass=%s\n",
            crisis_IC, normal_IC, crisis_normal_ratio, ax001_v2_pass))

# ---- Step 6: Correlation vs PD27 1715 H1 (orthogonality constraint cor<0.30) ----
pd27 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")))
pd27_slim <- pd27[, .(Date, Ticker, score_pd27 = score_eff)]
cor_dt <- merge(alpha_dt[, .(Date, Ticker, alpha_pd35)], pd27_slim, by = c("Date", "Ticker"))
cor_per_date <- cor_dt[, .(cor = suppressWarnings(cor(alpha_pd35, score_pd27, method = "spearman"))), by = Date]
cor_per_date <- cor_per_date[!is.na(cor)]
cor_mean <- mean(cor_per_date$cor, na.rm = TRUE)
cor_sd <- sd(cor_per_date$cor, na.rm = TRUE)
cor_overall <- with(cor_dt, suppressWarnings(cor(alpha_pd35, score_pd27, method = "spearman", use = "pairwise.complete.obs")))
cat(sprintf("[PD35] cor_overall=%.4f cor_per_date_mean=%.4f cor_per_date_sd=%.4f\n",
            cor_overall, cor_mean, cor_sd))

# ---- Step 7: Harvey-Liu-Zhu multi-testing adjustment ----
# n_trials: 7 base (Iter1+Iter2+Iter3+Iter4+Iter5+PD24+PD27) + 4 PD32 v2 + 3 PD32 v3b + 1 PD35 = 15
N_TRIALS <- 15
t_threshold_HLZ <- sqrt(2 * log(N_TRIALS)) + 0.55  # conservative adj approx
hlz_pass <- !is.na(nw_t) && nw_t > t_threshold_HLZ
cat(sprintf("[PD35] HLZ N_trials=%d threshold_approx=%.4f t_NW=%.4f pass=%s\n",
            N_TRIALS, t_threshold_HLZ, nw_t, hlz_pass))

# ---- Step 8: Deflated Sharpe (Bailey-LdP closed-form, IC-based proxy) ----
# Using IC ICIR as SR proxy for IC-based DSR
N <- nrow(ic_per_date)
sr_ic <- ICIR_naive  # ICIR ~ SR (monthly)
# Skew & kurt of IC for BLP DSR
gamma3 <- mean(((ic_per_date$rank_IC - mean_IC) / sd_IC)^3, na.rm = TRUE)
gamma4 <- mean(((ic_per_date$rank_IC - mean_IC) / sd_IC)^4, na.rm = TRUE) - 3
sigma_sr <- sqrt((1 - gamma3 * sr_ic + (gamma4 / 4) * sr_ic^2) / (N - 1))
z_blp_vs_zero <- sr_ic / sigma_sr

# E[SR_max] under null with N trials
# Lopez de Prado closed-form: E[SR_max] ≈ ((1-γ)·Φ^(-1)(1-1/N) + γ·Φ^(-1)(1-1/(N·e)))·σ_sr
gamma_em <- 0.5772156649
em_phi1 <- qnorm(1 - 1/N_TRIALS)
em_phi2 <- qnorm(1 - 1/(N_TRIALS * exp(1)))
E_SR_max_null <- (em_phi1 * (1 - gamma_em) + em_phi2 * gamma_em) * sigma_sr
DSR_z <- (sr_ic - E_SR_max_null) / sigma_sr
DSR_pval <- 2 * (1 - pnorm(abs(DSR_z)))
cat(sprintf("[PD35] DSR sigma=%.5f z_vs_zero=%.4f E_SR_max_null=%.4f DSR_z=%.4f pval=%.6f\n",
            sigma_sr, z_blp_vs_zero, E_SR_max_null, DSR_z, DSR_pval))

# ---- Step 9: Save alpha scores + diagnostic ----
# Save parquet
write_parquet(alpha_dt[, .(Date, Ticker, alpha_pd35, axis_profit, axis_tail, axis_earn, Ret_1m, n_factors_used)],
              OUTPUT_PARQUET)
cat(sprintf("[PD35] Saved alpha scores to %s\n", OUTPUT_PARQUET))

# Diagnostic JSON
diag <- list(
  pd_phase = "PD35_quality_tail_earnings_PIT_strict",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  factor_axes = list(
    profit_quality = AXIS_PROFIT_QUALITY,
    tail_risk = AXIS_TAIL_RISK,
    earnings_quality = AXIS_EARNINGS_QUAL
  ),
  n_factors = N_FACTORS,
  axis_weights = as.list(AXIS_WEIGHTS),
  n_rows = nrow(alpha_dt),
  n_sig_dates = uniqueN(alpha_dt$Date),
  date_range_start = as.character(min(alpha_dt$Date)),
  date_range_end = as.character(max(alpha_dt$Date)),
  diagnostics = list(
    mean_IC = mean_IC,
    sd_IC = sd_IC,
    ICIR_naive = ICIR_naive,
    t_naive = t_naive,
    t_NW_lag6 = nw_t,
    n_months = nrow(ic_per_date),
    ic_positive_share = mean(ic_per_date$rank_IC > 0, na.rm = TRUE)
  ),
  subperiod = list(
    P1_2001_2008 = list(rank_IC = subperiod_ic[period == "P1_2001_2008", rank_IC],
                        n_months = subperiod_ic[period == "P1_2001_2008", n_months]),
    P2_2009_2017 = list(rank_IC = subperiod_ic[period == "P2_2009_2017", rank_IC],
                        n_months = subperiod_ic[period == "P2_2009_2017", n_months]),
    P3_2018_2026 = list(rank_IC = subperiod_ic[period == "P3_2018_2026", rank_IC],
                        n_months = subperiod_ic[period == "P3_2018_2026", n_months]),
    min_max_ratio = min_max_ratio,
    sign_consistency = sign_consistency,
    pass_subperiod_50 = min_max_ratio >= 0.50 && sign_consistency
  ),
  ax001_v2_crisis = list(
    crisis_IC = crisis_IC,
    normal_IC = normal_IC,
    ratio_c_over_n = crisis_normal_ratio,
    n_crisis = ic_regime[regime == "crisis", n_months],
    n_normal = ic_regime[regime == "normal", n_months],
    ax001_v2_pass = ax001_v2_pass
  ),
  cor_vs_pd27 = list(
    cor_overall = cor_overall,
    cor_per_date_mean = cor_mean,
    cor_per_date_sd = cor_sd,
    constraint_lt_0_30_pass = abs(cor_mean) < 0.30 && abs(cor_overall) < 0.30
  ),
  harvey_lz_multi_test = list(
    n_trials = N_TRIALS,
    t_threshold_approx = t_threshold_HLZ,
    t_NW_observed = nw_t,
    pass = hlz_pass
  ),
  deflated_sharpe = list(
    method = "BLP_2014_closed_form_IC_based",
    sr_ic_proxy = sr_ic,
    sigma_sr = sigma_sr,
    z_vs_zero = z_blp_vs_zero,
    E_SR_max_null = E_SR_max_null,
    DSR_z = DSR_z,
    DSR_pval = DSR_pval,
    threshold_0_5_pass = DSR_z > 0.5
  ),
  graduation_gates_8 = list(
    rank_IC_gate = list(value = mean_IC, threshold = 0.02, pass = mean_IC > 0.02),
    ICIR_gate = list(value = ICIR_naive, threshold = 0.20, pass = ICIR_naive > 0.20),
    t_NW_gate = list(value = nw_t, threshold = 3.0, pass = !is.na(nw_t) && nw_t > 3.0),
    hlz_gate = list(value = nw_t, threshold = t_threshold_HLZ, pass = hlz_pass),
    dsr_gate = list(value = DSR_z, threshold = 0.5, pass = DSR_z > 0.5),
    subperiod_gate = list(value = min_max_ratio, threshold = 0.50, pass = min_max_ratio >= 0.50 && sign_consistency),
    cor_pd27_gate = list(value = cor_mean, threshold = 0.30, pass = abs(cor_mean) < 0.30),
    ax001_v2_gate = list(crisis_IC = crisis_IC, normal_IC = normal_IC, ratio = crisis_normal_ratio, pass = ax001_v2_pass)
  )
)

writeLines(toJSON(diag, pretty = TRUE, auto_unbox = TRUE, na = "string"), DIAGNOSTIC_JSON)
cat(sprintf("[PD35] Diagnostic saved to %s\n", DIAGNOSTIC_JSON))

# ---- Summary print ----
gates <- sapply(diag$graduation_gates_8, function(g) isTRUE(g$pass))
cat(sprintf("\n[PD35 SUMMARY] gates passed: %d/8\n", sum(gates)))
for (gn in names(diag$graduation_gates_8)) {
  g <- diag$graduation_gates_8[[gn]]
  cat(sprintf("  %s: pass=%s\n", gn, isTRUE(g$pass)))
}
cat("\n[PD35] Complete.\n")
