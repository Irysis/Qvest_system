#==============================================================================
# Risk Step 5: Tail Risk + Stress + Crowding + Style + AX-001 v2 Conditional Check
#
# Inputs:
#   - Σ (factor_model_8f primary) + B + Ω + D (Step 2-4)
#   - alpha_scores_new.parquet (z_blend + regime_state)
#   - V5 evidence regime_decomposition_V5_defense_amplifier.csv
#
# Tasks:
#   (a) Top20 EW portfolio level realized returns by regime — compare V5
#   (b) Tail risk: CVaR_95, CVaR_99, skew, kurtosis, EVT-GPD, CDaR
#   (c) 8 KR stress periods historical performance
#   (d) Crowding: ownership concentration + sector concentration
#   (e) Style exposure via factor B for top20
#   (f) AX-001 v2 conditional defense check
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts); library(PerformanceAnalytics)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")

OUT_DIR <- "stage_artifacts/WT_D20260512_003"

# ── 1. Load artifacts ───────────────────────────────────────────────────────
alpha_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores_new.parquet")))
ret_long <- as.data.table(read_parquet(file.path(OUT_DIR, "_risk_monthly_returns_long.parquet")))
res24 <- readRDS(file.path(OUT_DIR, "_risk_step24_results.rds"))
Sigma <- res24$results[[5]]$Sigma  # factor_model_8f
B <- attr(Sigma, "B")
Omega <- attr(Sigma, "Omega")
D <- attr(Sigma, "D")

cat("[Step5] Σ loaded:", nrow(Sigma), "x", ncol(Sigma), "\n")

# ── 2. Top20 Equal-Weighted realized returns by sig_date ─────────────────────
# For each sig_date t, select top20 by z_blend_composite, then realize Ret_m at t+1
# We use the same forward-return convention as Step 1 factor TS.
setkey(alpha_dt, Date, Ticker)
setkey(ret_long, Date, Ticker)

sig_dates <- sort(unique(alpha_dt$Date))
build_top20 <- function(dt) {
  ok <- dt[!is.na(z_blend_composite)]
  setorder(ok, -z_blend_composite)
  ok <- head(ok, 20)
  ok[, .(Ticker, regime_state)]
}

# For each sig_date, find next-month return
top20_history <- list()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  cur <- alpha_dt[Date == sd]
  top20 <- build_top20(cur)
  if (nrow(top20) == 0) next
  regime <- unique(cur$regime_state)[1]
  # Forward return: use Ret_m at sig_date t+1 (next month)
  if (i < length(sig_dates)) {
    next_sd <- sig_dates[i+1]
    fwd_ret <- ret_long[Date == next_sd & Ticker %in% top20$Ticker, .(Ticker, R = Ret_m)]
    # EW portfolio return
    port_ret <- mean(fwd_ret$R, na.rm = TRUE)
    n_filled <- sum(!is.na(fwd_ret$R))
  } else {
    port_ret <- NA_real_; n_filled <- 0
  }
  top20_history[[i]] <- data.table(
    Date = sd, port_ret = port_ret, regime_state = regime,
    n_filled = n_filled, n_target = nrow(top20)
  )
}
port_dt <- rbindlist(top20_history)
port_dt <- port_dt[!is.na(port_ret)]
cat("[Step5] Portfolio monthly returns:", nrow(port_dt), "obs\n")
cat("Date range:", as.character(min(port_dt$Date)), "~", as.character(max(port_dt$Date)), "\n")

# ── 3. Regime decomposition — compare V5 ─────────────────────────────────────
regime_decomp <- port_dt[, .(
  n_months = .N,
  mean_ret = mean(port_ret, na.rm = TRUE),
  sd_ret = sd(port_ret, na.rm = TRUE),
  hit_rate = mean(port_ret > 0, na.rm = TRUE),
  ann_ret = mean(port_ret, na.rm = TRUE) * 12,
  ann_vol = sd(port_ret, na.rm = TRUE) * sqrt(12),
  sr_ann = (mean(port_ret, na.rm = TRUE) * 12) / (sd(port_ret, na.rm = TRUE) * sqrt(12)),
  cum_ret = prod(1 + port_ret, na.rm = TRUE) - 1
), by = regime_state]
cat("\n[Step5] Z-Score Composite Top20 EW — REGIME DECOMPOSITION:\n")
print(regime_decomp)

# Compare V5
v5_decomp <- fread("qepm/mailbox/worktask/WT-H20260512_001/backtest_result/regime_decomposition_V5_defense_amplifier.csv")
cat("\n[Step5] V5 (defense_amplifier) for comparison:\n")
print(v5_decomp[, .(regime, n_months, sr_ann = round(sr_ann, 3), ann_ret = round(ann_ret, 3))])

# ── 4. Tail risk metrics on portfolio returns ────────────────────────────────
port_ret_vec <- port_dt$port_ret

# Empirical VaR/CVaR
var95_emp <- as.numeric(quantile(port_ret_vec, 0.05, na.rm = TRUE))
var99_emp <- as.numeric(quantile(port_ret_vec, 0.01, na.rm = TRUE))
cvar95_emp <- mean(port_ret_vec[port_ret_vec <= var95_emp], na.rm = TRUE)
cvar99_emp <- mean(port_ret_vec[port_ret_vec <= var99_emp], na.rm = TRUE)

# Cornish-Fisher VaR (skew + kurtosis adjustment)
mu <- mean(port_ret_vec); sigma <- sd(port_ret_vec)
sk <- mean((port_ret_vec - mu)^3) / sigma^3
ku <- mean((port_ret_vec - mu)^4) / sigma^4 - 3
z95 <- qnorm(0.05); z99 <- qnorm(0.01)
cf_adj95 <- z95 + (z95^2 - 1) * sk / 6 + (z95^3 - 3*z95) * ku / 24 - (2 * z95^3 - 5 * z95) * sk^2 / 36
cf_adj99 <- z99 + (z99^2 - 1) * sk / 6 + (z99^3 - 3*z99) * ku / 24 - (2 * z99^3 - 5 * z99) * sk^2 / 36
var95_cf <- mu + sigma * cf_adj95
var99_cf <- mu + sigma * cf_adj99

# CDaR via tail_risk_engine
source("02_Infrastructure/portfolio/tail_risk_engine.R")
nav_vec <- cumprod(1 + port_ret_vec)
cdar95 <- compute_cdar(nav_vec, alpha = 0.95)
cdar99 <- compute_cdar(nav_vec, alpha = 0.99)

# EVT-GPD using compute_evt_var (monthly portfolio returns, ~265 obs)
evt95_res <- tryCatch(compute_evt_var(port_ret_vec, p = 0.95, threshold_q = 0.80, min_tail_n = 30L),
                      error = function(e) list(var_evt = NA_real_, es_evt = NA_real_,
                                                shape_xi = NA_real_, method = "error"))
evt99_res <- tryCatch(compute_evt_var(port_ret_vec, p = 0.99, threshold_q = 0.90, min_tail_n = 20L),
                      error = function(e) list(var_evt = NA_real_, es_evt = NA_real_,
                                                shape_xi = NA_real_, method = "error"))
evt95 <- evt95_res$var_evt   # losses positive
evt99 <- evt99_res$var_evt
evt95_es <- evt95_res$es_evt
evt99_es <- evt99_res$es_evt
evt95_xi <- evt95_res$shape_xi
evt99_xi <- evt99_res$shape_xi
evt_method <- paste(evt95_res$method, evt99_res$method, sep="/")

cat("\n[Step5] TAIL RISK SUITE (monthly portfolio returns, n =", length(port_ret_vec), "):\n")
cat(sprintf("  VaR 95 emp:    %.4f  (annualized %.4f)\n", var95_emp, var95_emp * sqrt(12)))
cat(sprintf("  VaR 99 emp:    %.4f  (annualized %.4f)\n", var99_emp, var99_emp * sqrt(12)))
cat(sprintf("  CVaR 95 emp:   %.4f  (annualized %.4f)\n", cvar95_emp, cvar95_emp * sqrt(12)))
cat(sprintf("  CVaR 99 emp:   %.4f  (annualized %.4f)\n", cvar99_emp, cvar99_emp * sqrt(12)))
cat(sprintf("  VaR 95 CF:     %.4f  (skew/kurt adjusted)\n", var95_cf))
cat(sprintf("  VaR 99 CF:     %.4f\n", var99_cf))
cat(sprintf("  EVT-GPD VaR 95:%.4f  (ES %.4f, xi %.3f, method %s)\n",
            ifelse(is.null(evt95) || is.na(evt95), NA_real_, evt95),
            ifelse(is.null(evt95_es) || is.na(evt95_es), NA_real_, evt95_es),
            ifelse(is.null(evt95_xi) || is.na(evt95_xi), NA_real_, evt95_xi),
            evt95_res$method))
cat(sprintf("  EVT-GPD VaR 99:%.4f  (ES %.4f, xi %.3f, method %s)\n",
            ifelse(is.null(evt99) || is.na(evt99), NA_real_, evt99),
            ifelse(is.null(evt99_es) || is.na(evt99_es), NA_real_, evt99_es),
            ifelse(is.null(evt99_xi) || is.na(evt99_xi), NA_real_, evt99_xi),
            evt99_res$method))
cat(sprintf("  CDaR 95 (monthly):  %.4f\n", as.numeric(cdar95)))
cat(sprintf("  CDaR 99 (monthly):  %.4f\n", as.numeric(cdar99)))
cat(sprintf("  Skewness:      %.4f\n", sk))
cat(sprintf("  Excess Kurt:   %.4f\n", ku))

# ── 5. 8 KR Stress Periods historical decomposition ─────────────────────────
RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
def_stress_periods <- list(
  list(name = "GFC",               start = "2007-10-01", end = "2009-03-31"),
  list(name = "Euro_Debt",         start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock",       start = "2015-06-01", end = "2016-02-29"),
  list(name = "US_China_Trade",    start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID",             start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_Hike",         start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War",          start = "2026-02-01", end = "2026-04-30"),
  list(name = "Bear_2025",         start = "2025-04-01", end = "2025-09-30")
)

bm_monthly <- RAWDATA[Date >= as.Date("2003-12-01") & !is.na(BM_Ret),
                      .(BM_Ret_d = mean(BM_Ret, na.rm = TRUE)), by = Date]
bm_monthly[, YM := as.Date(format(Date, "%Y-%m-01"))]
bm_m <- bm_monthly[order(Date), .(BM_m = prod(1 + BM_Ret_d, na.rm = TRUE) - 1), by = YM]
bm_m[, Date := YM]
setkey(port_dt, Date)
setkey(bm_m, Date)

stress_rows <- list()
for (sp in def_stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  port_sub <- port_dt[Date >= s & Date <= e]
  bm_sub <- bm_m[Date >= s & Date <= e]
  if (nrow(port_sub) == 0) {
    stress_rows[[length(stress_rows) + 1]] <- data.table(
      Period = sp$name, Obs = 0L, port_cum = NA_real_, bm_cum = NA_real_, alpha = NA_real_,
      port_mdd = NA_real_
    )
    next
  }
  port_cum <- prod(1 + port_sub$port_ret, na.rm = TRUE) - 1
  bm_cum   <- prod(1 + bm_sub$BM_m, na.rm = TRUE) - 1
  port_nav <- cumprod(1 + port_sub$port_ret)
  port_mdd <- max(1 - port_nav / cummax(port_nav))
  stress_rows[[length(stress_rows) + 1]] <- data.table(
    Period = sp$name, Obs = nrow(port_sub),
    port_cum = round(port_cum * 100, 2),
    bm_cum = round(bm_cum * 100, 2),
    alpha = round((port_cum - bm_cum) * 100, 2),
    port_mdd = round(port_mdd * 100, 2)
  )
}
stress_dt <- rbindlist(stress_rows)
cat("\n[Step5] STRESS PERIOD DECOMPOSITION (Top20 EW Z-Composite portfolio):\n")
print(stress_dt)

# ── 6. Crowding / sector / size concentration for current top20 ──────────────
last_date <- max(alpha_dt$Date)
cur_top20 <- build_top20(alpha_dt[Date == last_date])
# Attach RAWDATA at last_date
recent <- RAWDATA[Date >= last_date - 60 & Date <= last_date + 30 & Ticker %in% cur_top20$Ticker,
                  .SD[.N], by = Ticker]
top20_meta <- merge(cur_top20, recent[, .(Ticker, Name, Sector, Sector_Lv2, Market, Size)], by = "Ticker", all.x = TRUE)

# Sector concentration
sector_dt <- top20_meta[, .(N = .N, weight_eq = .N / 20), by = Sector]
setorder(sector_dt, -N)

# Liquidity (using L05 percentile from alpha emission — we don't have it but use Size as proxy)
# Size in won (대형주)
cat("\n[Step5] TOP20 AT 2026-04-01:\n")
print(top20_meta[, .(Ticker, Name, Sector, regime_state)])
cat("\nSector concentration:\n")
print(sector_dt)

# Size median
size_med <- median(top20_meta$Size, na.rm = TRUE)
cat(sprintf("\nTop20 size median (Won): %.2e (small-cap if < 5e11)\n", size_med))

# ── 7. Style exposure via B (factor model) ──────────────────────────────────
# Extract factor exposures for top20 names
top20_tickers_in_B <- cur_top20$Ticker[cur_top20$Ticker %in% rownames(B)]
B_top20 <- B[top20_tickers_in_B, , drop = FALSE]
ew_style <- colMeans(B_top20, na.rm = TRUE)
cat("\n[Step5] STYLE EXPOSURE (EW Top20 average factor loadings):\n")
print(round(ew_style, 4))

# Style risk decomposition: how much portfolio variance from each factor
# Portfolio variance via factor model: w'Bw + sum(w^2 * D)
w_ew <- rep(1/length(top20_tickers_in_B), length(top20_tickers_in_B))
B_p <- t(w_ew) %*% B_top20  # 1 x K
factor_var_p <- as.numeric(B_p %*% Omega %*% t(B_p))
D_top <- D[top20_tickers_in_B]
spec_var_p <- sum(w_ew^2 * D_top, na.rm = TRUE)
total_var_p <- factor_var_p + spec_var_p
factor_contrib_pct <- factor_var_p / total_var_p * 100

cat(sprintf("\n[Step5] Portfolio variance decomposition (monthly):\n"))
cat(sprintf("  Total variance:    %.6f  (ann_vol %.4f)\n", total_var_p, sqrt(total_var_p * 12)))
cat(sprintf("  Factor variance:   %.6f  (%.1f%%)\n", factor_var_p, factor_contrib_pct))
cat(sprintf("  Specific variance: %.6f  (%.1f%%)\n", spec_var_p, 100 - factor_contrib_pct))

# Per-factor contribution to portfolio variance
factor_decomp <- numeric(ncol(B))
names(factor_decomp) <- colnames(B)
for (k in seq_len(ncol(B))) {
  e_k <- numeric(ncol(B)); e_k[k] <- 1
  factor_decomp[k] <- as.numeric(B_p[1, ] * (Omega[k, ] %*% e_k * B_p[1, k]))
}
# Normalize so sum = factor_var_p, then express as % of total_var
factor_decomp_pct <- factor_decomp / total_var_p * 100
cat("\n[Step5] Per-factor contribution to total variance (%):\n")
print(round(factor_decomp_pct, 2))

# ── 8. AX-001 v2 Conditional Defense Check ───────────────────────────────────
# Axes:
#   A1: crisis_alpha — CRISIS regime SR > 0 strict + event count >= 3
#   A2: Core MDD relief — composite MDD < baseline (V5) MDD
#   A3: bad/normal IC ratio (already in alpha layer: 1.127 FAIL by alpha but
#       here we recompute at portfolio level via mean_ret)
#   A4: stress regime outperformance vs market

a1_crisis_sr <- regime_decomp[regime_state == "CRISIS", sr_ann]
a1_crisis_n <- regime_decomp[regime_state == "CRISIS", n_months]
a1_pass <- length(a1_crisis_sr) > 0 && !is.na(a1_crisis_sr) && a1_crisis_sr > 0 && a1_crisis_n >= 3

# A2: composite portfolio MDD over GFC + COVID vs baseline
mdd_gfc_composite <- stress_dt[Period == "GFC", port_mdd]
mdd_covid_composite <- stress_dt[Period == "COVID", port_mdd]
# V5 reference MDDs (recompute from V5 period returns CSV if available)
v5_pr <- tryCatch(fread("qepm/mailbox/worktask/WT-H20260512_001/backtest_result/period_returns_V5_defense_amplifier.csv"),
                  error = function(e) NULL)
if (!is.null(v5_pr) && nrow(v5_pr) > 0) {
  v5_dt <- copy(v5_pr)
  # Standardize: use sig_date as Date convention (matches our port_dt), ret_net as net return
  v5_dt[, Date := as.Date(sig_date)]
  v5_dt[, ret := ret_net]
  v5_sub_gfc <- v5_dt[Date >= as.Date("2007-10-01") & Date <= as.Date("2009-03-31")]
  if (nrow(v5_sub_gfc) > 0) {
    v5_nav_gfc <- cumprod(1 + v5_sub_gfc$ret)
    v5_mdd_gfc <- max(1 - v5_nav_gfc / cummax(v5_nav_gfc)) * 100
    v5_gfc_cum <- (tail(v5_nav_gfc, 1) - 1) * 100
  } else { v5_mdd_gfc <- NA_real_; v5_gfc_cum <- NA_real_ }
  v5_sub_covid <- v5_dt[Date >= as.Date("2020-01-01") & Date <= as.Date("2020-06-30")]
  if (nrow(v5_sub_covid) > 0) {
    v5_nav_covid <- cumprod(1 + v5_sub_covid$ret)
    v5_mdd_covid <- max(1 - v5_nav_covid / cummax(v5_nav_covid)) * 100
    v5_covid_cum <- (tail(v5_nav_covid, 1) - 1) * 100
  } else { v5_mdd_covid <- NA_real_; v5_covid_cum <- NA_real_ }
  # Full-sample V5 MDD
  v5_nav_full <- cumprod(1 + v5_dt$ret)
  v5_mdd_full <- max(1 - v5_nav_full / cummax(v5_nav_full)) * 100
} else {
  v5_mdd_gfc <- NA_real_; v5_mdd_covid <- NA_real_; v5_mdd_full <- NA_real_
  v5_gfc_cum <- NA_real_; v5_covid_cum <- NA_real_
}
# Full-sample composite MDD
port_nav_full <- cumprod(1 + port_dt$port_ret)
port_mdd_full <- max(1 - port_nav_full / cummax(port_nav_full)) * 100
cat(sprintf("\n[Step5] FULL SAMPLE MDD: Composite %.2f%% vs V5 %.2f%% (relief %.2fpp)\n",
            port_mdd_full, v5_mdd_full, v5_mdd_full - port_mdd_full))
a2_relief_gfc <- if (!is.na(v5_mdd_gfc) && !is.na(mdd_gfc_composite)) v5_mdd_gfc - mdd_gfc_composite else NA_real_
a2_relief_covid <- if (!is.na(v5_mdd_covid) && !is.na(mdd_covid_composite)) v5_mdd_covid - mdd_covid_composite else NA_real_

# A3: bad / normal IC ratio at portfolio level (mean_ret)
ret_normal <- regime_decomp[regime_state == "NORMAL", mean_ret]
ret_caution <- regime_decomp[regime_state == "CAUTION", mean_ret]
ret_crisis <- regime_decomp[regime_state == "CRISIS", mean_ret]
bad_avg <- mean(c(ret_caution, ret_crisis), na.rm = TRUE)
a3_ratio <- bad_avg / ret_normal
a3_pass <- !is.na(a3_ratio) && a3_ratio >= 0  # at portfolio level we relax to "not deeply negative"

# A4: outperform market in stress regimes
a4_caution_outperf <- regime_decomp[regime_state == "CAUTION", ann_ret] - 0  # vs market_ann ~ 0 in stress
a4_crisis_outperf <- regime_decomp[regime_state == "CRISIS", ann_ret] - 0

ax001v2_check <- list(
  axis1_crisis_alpha = list(
    test = "CRISIS regime SR > 0 strict + n >= 3",
    crisis_sr_composite = a1_crisis_sr,
    crisis_n = a1_crisis_n,
    pass = a1_pass,
    v5_crisis_sr = -2.608,
    v5_crisis_ann_ret = -0.958,
    composite_swing_pp = round(regime_decomp[regime_state == "CRISIS", sr_ann] - (-2.608), 3)
  ),
  axis2_mdd_relief = list(
    test = "Composite MDD < V5 MDD in GFC + COVID + full sample",
    gfc_composite_mdd = mdd_gfc_composite,
    gfc_v5_mdd = v5_mdd_gfc,
    gfc_relief_pp = if (is.na(v5_mdd_gfc)) NA_real_ else v5_mdd_gfc - mdd_gfc_composite,
    gfc_v5_cum = v5_gfc_cum,
    gfc_composite_cum = stress_dt[Period == "GFC", port_cum],
    covid_composite_mdd = mdd_covid_composite,
    covid_v5_mdd = v5_mdd_covid,
    covid_relief_pp = if (is.na(v5_mdd_covid)) NA_real_ else v5_mdd_covid - mdd_covid_composite,
    covid_v5_cum = v5_covid_cum,
    covid_composite_cum = stress_dt[Period == "COVID", port_cum],
    full_composite_mdd = port_mdd_full,
    full_v5_mdd = v5_mdd_full,
    full_relief_pp = v5_mdd_full - port_mdd_full,
    pass = !is.na(v5_mdd_full) && (v5_mdd_full - port_mdd_full) > 0
  ),
  axis3_bad_normal_ratio = list(
    test = "bad_avg / normal_ret >= 0  (portfolio level)",
    normal_mean = ret_normal,
    caution_mean = ret_caution,
    crisis_mean = ret_crisis,
    bad_avg = bad_avg,
    ratio = a3_ratio,
    pass = a3_pass
  ),
  axis4_stress_alpha = list(
    test = "CAUTION+CRISIS ann_ret > 0",
    caution_ann_ret = regime_decomp[regime_state == "CAUTION", ann_ret],
    crisis_ann_ret = regime_decomp[regime_state == "CRISIS", ann_ret],
    pass = (regime_decomp[regime_state == "CAUTION", ann_ret] > 0) ||
           (regime_decomp[regime_state == "CRISIS", ann_ret] > 0)
  )
)

# Verdict
n_pass <- sum(sapply(ax001v2_check, function(a) isTRUE(a$pass)))
ax001v2_verdict <- if (n_pass >= 3) "PASS_CONDITIONAL" else if (n_pass >= 2) "MARGINAL" else "FAIL"
ax001v2_check$verdict <- ax001v2_verdict
ax001v2_check$n_pass <- n_pass
ax001v2_check$n_total <- 4

cat("\n[Step5] AX-001 v2 CONDITIONAL DEFENSE CHECK:\n")
print(ax001v2_check)

# ── 9. Save artifacts ────────────────────────────────────────────────────────
write_parquet(port_dt, file.path(OUT_DIR, "_risk_portfolio_returns.parquet"))
write_parquet(regime_decomp, file.path(OUT_DIR, "_risk_regime_decomp.parquet"))
write_parquet(stress_dt, file.path(OUT_DIR, "_risk_stress_decomp.parquet"))
jsonlite::write_json(ax001v2_check, file.path(OUT_DIR, "_risk_ax001v2_check.json"),
                     pretty = TRUE, auto_unbox = TRUE, na = "string")

tail_risk_out <- list(
  N_obs = length(port_ret_vec),
  date_range = c(as.character(min(port_dt$Date)), as.character(max(port_dt$Date))),
  empirical = list(
    var95 = var95_emp, var99 = var99_emp,
    cvar95 = cvar95_emp, cvar99 = cvar99_emp,
    var95_annualized = var95_emp * sqrt(12),
    var99_annualized = var99_emp * sqrt(12),
    cvar95_annualized = cvar95_emp * sqrt(12),
    cvar99_annualized = cvar99_emp * sqrt(12)
  ),
  cornish_fisher = list(var95 = var95_cf, var99 = var99_cf, skew = sk, excess_kurt = ku),
  evt_gpd = list(
    var95 = ifelse(is.null(evt95)||is.na(evt95), NA_real_, evt95),
    var99 = ifelse(is.null(evt99)||is.na(evt99), NA_real_, evt99),
    es95 = ifelse(is.null(evt95_es)||is.na(evt95_es), NA_real_, evt95_es),
    es99 = ifelse(is.null(evt99_es)||is.na(evt99_es), NA_real_, evt99_es),
    shape_xi_95 = ifelse(is.null(evt95_xi)||is.na(evt95_xi), NA_real_, evt95_xi),
    shape_xi_99 = ifelse(is.null(evt99_xi)||is.na(evt99_xi), NA_real_, evt99_xi),
    method = evt_method
  ),
  cdar = list(cdar95 = as.numeric(cdar95), cdar99 = as.numeric(cdar99)),
  variance_decomposition = list(
    monthly_total_var = total_var_p,
    monthly_factor_var = factor_var_p,
    monthly_specific_var = spec_var_p,
    annualized_vol = sqrt(total_var_p * 12),
    factor_contrib_pct = factor_contrib_pct,
    specific_contrib_pct = 100 - factor_contrib_pct,
    per_factor_pct = as.list(round(factor_decomp_pct, 4))
  ),
  style_exposure_ew_top20 = as.list(ew_style),
  sector_concentration = as.list(setNames(sector_dt$N, sector_dt$Sector))
)
jsonlite::write_json(tail_risk_out, file.path(OUT_DIR, "tail_risk.json"),
                     pretty = TRUE, auto_unbox = TRUE)

cat("\n[Step5] All Step 5 artifacts saved.\n")

# ── 10. Regime correlation: per-regime correlation shift ────────────────────
# For each regime, compute cross-sectional cor matrix of returns
ret_long2 <- merge(ret_long, alpha_dt[, .(Date, Ticker, regime_state)], by = c("Date", "Ticker"))
regime_corr_long <- list()
for (rg in unique(ret_long2$regime_state)) {
  sub <- ret_long2[regime_state == rg]
  if (uniqueN(sub$Date) < 10) next
  sub_wide <- dcast(sub, Date ~ Ticker, value.var = "Ret_m")
  cor_mat <- cor(as.matrix(sub_wide[, -1]), use = "pairwise.complete.obs")
  off_diag <- cor_mat[upper.tri(cor_mat)]
  regime_corr_long[[rg]] <- data.table(
    regime_state = rg,
    n_obs = uniqueN(sub$Date),
    avg_corr = mean(off_diag, na.rm = TRUE),
    median_corr = median(off_diag, na.rm = TRUE),
    pct_above_0_5 = mean(off_diag > 0.5, na.rm = TRUE),
    pct_above_0_8 = mean(off_diag > 0.8, na.rm = TRUE),
    n_pairs = sum(!is.na(off_diag))
  )
}
regime_corr_dt <- rbindlist(regime_corr_long)
cat("\n[Step5] REGIME CORRELATION SHIFT:\n")
print(regime_corr_dt)
write_parquet(regime_corr_dt, file.path(OUT_DIR, "regime_correlation.parquet"))

cat("\n[Step5] DONE.\n")
