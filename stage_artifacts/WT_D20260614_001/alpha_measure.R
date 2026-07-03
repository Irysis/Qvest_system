# =============================================================================
# alpha_measure.R — WT-D20260614_001 VAL_DIVERSIFIER value-4 sleeve
# de-contam recipe: V01_BM + V03_CFP + V10_FCF_Yield + V11_Shareholder_Yield
# EW z-composite, n=30 canonical, monthly, KOSPI200∪KQ150, 2e8 LIQ, 15bps.
# PIT: scores at sig_date (month-end t), forward 1M realized returns t->t+1.
# C15: factors via load_month_factors() only. C13: Z_Score_Aligned as-is.
# =============================================================================
suppressMessages({
  library(arrow); library(data.table); library(dplyr); library(jsonlite)
})
options(warn = 1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root)
out_dir <- file.path(root, "stage_artifacts", "WT_D20260614_001")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

FACTORS_USE <- c("V01_BM", "V03_CFP", "V10_FCF_Yield", "V11_Shareholder_Yield")
START_DATE  <- as.Date("2005-01-01")
TOP_N       <- 30L      # de-contam recipe n=30 (canonical screen)
LIQ_MIN     <- 2e8
COST_BPS    <- 15

# ---- 1. Load connector + RAWDATA ----------------------------------------
source(file.path(root, "02_Infrastructure", "factor_db", "factor_db_connector.R"))
source(file.path(root, "02_Infrastructure", "contracts", "canonical_screen_bt.R"))

rp <- file.path(root, ".cache", "rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(rp,
  col_select = c("Date", "Ticker", "Close", "Vol", "K200", "KQ150", "Ret", "BM_Ret")))
RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)

# ---- 2. Month-end membership universe (K200∪KQ150 + 20d ADV>=2e8) --------
rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150, Ret, BM_Ret)]
rd[, ym := format(Date, "%Y-%m")]
month_ends <- sort(rd[, .(Date = max(Date)), by = ym]$Date)
month_ends <- month_ends[month_ends >= START_DATE]

rd[, TV := Close * Vol]
rd[, AvgTV20 := frollmean(TV, 20L, align = "right"), by = Ticker]

mem <- rd[Date %in% month_ends & (K200 == 1 | KQ150 == 1) &
            !is.na(AvgTV20) & AvgTV20 >= LIQ_MIN, .(Date, Ticker, adv = AvgTV20)]
setkey(mem, Date, Ticker)

# ---- 3. Monthly forward 1M return per ticker (t -> t+1 month-end) --------
# month-end close per ticker
me_close <- rd[Date %in% month_ends, .(Date, Ticker, Close)]
setorder(me_close, Ticker, Date)
me_close[, Close_next := shift(Close, -1L), by = Ticker]
me_close[, Date_next  := shift(Date,  -1L), by = Ticker]
me_close[, Ret_1m := Close_next / Close - 1]   # forward realized 1M
returns_dt <- me_close[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]

# benchmark monthly forward return: compound daily BM_Ret within (t, t+1]
# SOT = benchmark.parquet (RAWDATA broadcast BM_Ret has sporadic NA snapshots, e.g. 2026-03)
bm_src <- as.data.table(read_parquet(file.path(root, ".cache", "benchmark.parquet"),
                                     col_select = c("Date", "BM_Ret")))
bm_src[, Date := as.Date(Date)]
bm_daily <- bm_src[is.finite(BM_Ret), .(Date, BM_Ret)]
setorder(bm_daily, Date)
# map each daily date to the owning month-end bucket index, then compound forward
me_idx <- data.table(Date = month_ends, me_id = seq_along(month_ends))
bm_daily[, me_owner := findInterval(Date, month_ends)]  # number of month_ends <= Date
# forward month return for sig month-end i = compound of daily BM over (me_i, me_{i+1}]
bm_fwd <- bm_daily[me_owner >= 1 & me_owner < length(month_ends),
                   .(bm_fwd = prod(1 + BM_Ret) - 1), by = me_owner]
bm_fwd[, Date := month_ends[me_owner]]
bench_dt <- bm_fwd[, .(Date, BM_Ret = bm_fwd)]
bench_dt <- bench_dt[is.finite(BM_Ret)]   # drop benchmark-data gap months (e.g. 2026-03 NA)

# liquidity table for canonical_screen_bt
liq_dt <- mem[, .(Date, Ticker, adv)]

# ---- 4. Value-4 EW z-composite scores (PIT load_month_factors) ----------
.scores_cache <- file.path(out_dir, "alpha_scores.parquet")
if (file.exists(.scores_cache) && !nzchar(Sys.getenv("FORCE_RECOMPUTE"))) {
  scores_dt <- as.data.table(read_parquet(.scores_cache))
  scores_dt[, Date := as.Date(Date)]
  cat("[scores] reloaded from cache:", .scores_cache, "\n")
} else {
score_list <- vector("list", length(month_ends))
for (i in seq_along(month_ends)) {
  d <- month_ends[i]
  uni_tk <- mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = FACTORS_USE),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  fz <- fdt[Factor_Name %in% FACTORS_USE & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
            .(Ticker, Factor_Name, Z = Z_Score_Aligned)]
  if (!nrow(fz)) next
  # EW composite: require all 4 factors present (FACTOR_MIN_COUNT = 4)
  comp <- fz[, .(score = mean(Z), kf = .N), by = Ticker][kf == length(FACTORS_USE), .(Ticker, score)]
  if (nrow(comp) < 20L) next
  comp[, Date := d]
  score_list[[i]] <- comp[, .(Date, Ticker, score)]
}
scores_dt <- rbindlist(Filter(Negate(is.null), score_list), use.names = TRUE)
write_parquet(scores_dt, .scores_cache)
}
cat(sprintf("[scores] months=%d rows=%d avgN/m=%.0f\n",
            uniqueN(scores_dt$Date), nrow(scores_dt),
            nrow(scores_dt) / uniqueN(scores_dt$Date)))

# ---- 5. Rank-IC / ICIR / Harvey-t / monotonicity / subperiod ------------
SR <- merge(scores_dt, returns_dt, by = c("Date", "Ticker"))
SR <- SR[is.finite(score) & is.finite(Ret_1m)]

ic_by_month <- SR[, .(ic = if (.N >= 10) cor(score, Ret_1m, method = "spearman") else NA_real_,
                      n = .N), by = Date][is.finite(ic)]
setorder(ic_by_month, Date)
ic_vec <- ic_by_month$ic
n_months_ic <- length(ic_vec)
rank_ic <- mean(ic_vec)
ic_sd <- sd(ic_vec)
icir <- rank_ic / ic_sd                      # monthly ICIR
# Harvey-t on rank-IC with NW lag-3 (autocorrelation-robust)
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n
  s <- g0
  for (l in 1:lag) {
    if (l >= n) break
    w <- 1 - l / (lag + 1)
    gl <- sum(e[(l + 1):n] * e[1:(n - l)]) / n
    s <- s + 2 * w * gl
  }
  se <- sqrt(s / n)
  mu / se
}
harvey_t_rankic <- nw_t(ic_vec, 3L)
# plain t for reference
ic_t_plain <- rank_ic / (ic_sd / sqrt(n_months_ic))

# Monotonicity: decile (here quintile, robust for ~30-150 names) mean fwd ret monotonic
SR[, q := {
  cut(frank(score, ties.method = "average") / .N, breaks = seq(0, 1, 0.2),
      labels = 1:5, include.lowest = TRUE)
}, by = Date]
dec <- SR[!is.na(q), .(mret = mean(Ret_1m)), by = .(q = as.integer(q))][order(q)]
mono <- if (nrow(dec) == 5) cor(dec$q, dec$mret, method = "spearman") else NA_real_

# Subperiod stability: mean-IC sign-consistency / magnitude across 3 blocks
ic_by_month[, period := fifelse(Date < as.Date("2015-01-01"), "p1_0514",
                       fifelse(Date < as.Date("2020-01-01"), "p2_1519", "p3_2026"))]
sub <- ic_by_month[, .(mean_ic = mean(ic), icir = mean(ic) / sd(ic), n = .N), by = period][order(period)]
# stability score = fraction of subperiods with positive mean IC, weighted
subperiod_stability <- mean(sub$mean_ic > 0)

# ---- 6. canonical_screen_bt: portfolio-alpha t (authoritative carry) -----
csb <- canonical_screen_bt(
  scores_dt = scores_dt, returns_dt = returns_dt, bench_dt = bench_dt,
  top_n = TOP_N, cost_bps_oneway = COST_BPS,
  liq_dt = liq_dt, liq_min = LIQ_MIN,
  run_id = "WT-D20260614_001_val4", strategy_id = "VAL_DIVERSIFIER_val4")

# also top_n=25 (deployment mandate) for reference
csb25 <- canonical_screen_bt(
  scores_dt = scores_dt, returns_dt = returns_dt, bench_dt = bench_dt,
  top_n = 25L, cost_bps_oneway = COST_BPS, liq_dt = liq_dt, liq_min = LIQ_MIN,
  run_id = "WT-D20260614_001_val4_n25", strategy_id = "VAL_DIVERSIFIER_val4_n25")

# ---- 7. per-name alpha-hat + confidence for latest as_of month -----------
as_of <- max(scores_dt$Date)
last_scores <- scores_dt[Date == as_of]
# alpha-hat = rank_ic * cross-sectional z of score (expected active return scale).
# Calibrate scale via IC: E[active | z] ~= rank_ic * sigma_xs_ret * z_std (use realized active sd).
realized_active_sd <- SR[, sd(Ret_1m - mean(Ret_1m)), by = Date][, mean(V1, na.rm = TRUE)]
last_scores[, z := (score - mean(score)) / sd(score)]
last_scores[, alpha_hat := rank_ic * realized_active_sd * z]   # monthly expected active

# confidence: per-name coverage(all 4 present already) + cross-sectional rank stability
# proxy via |z| dampening (extreme ranks more confident) bounded [0.3,0.9], plus global ICIR factor
icir_conf <- pmin(pmax(abs(icir) / 0.5, 0), 1)  # global signal reliability scaler
last_scores[, confidence := pmin(0.9, pmax(0.3, 0.45 + 0.25 * (abs(z) / max(abs(z))) )) * (0.5 + 0.5 * icir_conf)]

alpha_vector <- setNames(round(last_scores$alpha_hat, 6), last_scores$Ticker)
confidence_vector <- setNames(round(last_scores$confidence, 4), last_scores$Ticker)

# ---- 8. diversifier: active-basis correlation diagnostic input ----------
# value-4 sleeve canonical net active series (top_n=30) for risk/governor to correlate vs incumbent
WR <- {
  S <- copy(scores_dt); setorder(S, Date, -score)
  W <- S[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = 1 / n) }, by = Date]
  RR <- merge(W, returns_dt, by = c("Date", "Ticker"), all.x = TRUE)
  RR[is.na(Ret_1m), Ret_1m := 0]
  port <- RR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  port
}
sleeve_active <- merge(WR, bench_dt, by = "Date")
sleeve_active[, active_gross := port_gross - BM_Ret]
write_parquet(sleeve_active[, .(Date, port_gross, BM_Ret, active_gross)],
              file.path(out_dir, "sleeve_active_series.parquet"))

# ---- 9. Save scores parquet + diagnostics json --------------------------
write_parquet(scores_dt, file.path(out_dir, "alpha_scores.parquet"))
write_parquet(ic_by_month, file.path(out_dir, "ic_by_month.parquet"))

diagnostics <- list(
  recipe = list(factors = FACTORS_USE, combine = "equal_weight_zscore_composite",
                top_n = TOP_N, rebalance = "monthly", universe = "KOSPI200_KOSDAQ150",
                liq_min_won = LIQ_MIN, cost_bps_oneway = COST_BPS,
                period = c(as.character(min(scores_dt$Date)), as.character(max(scores_dt$Date))),
                n_signal_months = uniqueN(scores_dt$Date)),
  rank_ic = round(rank_ic, 5),
  icir_monthly = round(icir, 4),
  icir_annualized = round(icir * sqrt(12), 4),
  ic_t_plain = round(ic_t_plain, 3),
  harvey_t_rankic_nw3 = round(harvey_t_rankic, 3),
  n_months_ic = n_months_ic,
  monotonicity_quintile = round(mono, 3),
  decile_returns = as.list(round(dec$mret, 5)),
  subperiod = lapply(seq_len(nrow(sub)), function(i)
    list(period = sub$period[i], mean_ic = round(sub$mean_ic[i], 5),
         icir = round(sub$icir[i], 4), n = sub$n[i])),
  subperiod_stability = round(subperiod_stability, 3),
  realized_active_sd_monthly = round(realized_active_sd, 5),
  canonical_screen_n30 = list(
    metric_type = csb$metric_type,
    portfolio_alpha_t_nw_lag3 = round(csb$portfolio_alpha_t_nw_lag3, 3),
    portfolio_alpha_t_pvalue = round(csb$portfolio_alpha_t_pvalue, 4),
    information_ratio = round(csb$information_ratio, 4),
    alpha_annualized = round(csb$alpha_annualized, 5),
    net_sr = round(csb$net_sr, 4),
    mean_active_net_monthly = round(csb$mean_active_net, 5),
    turnover_annual = round(csb$turnover_annual, 4),
    n_months = csb$n_months),
  canonical_screen_n25 = list(
    portfolio_alpha_t_nw_lag3 = round(csb25$portfolio_alpha_t_nw_lag3, 3),
    information_ratio = round(csb25$information_ratio, 4),
    net_sr = round(csb25$net_sr, 4),
    turnover_annual = round(csb25$turnover_annual, 4))
)
write_json(diagnostics, file.path(out_dir, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 8)

# alpha/confidence vectors to RDS for package builder
saveRDS(list(as_of = as_of, alpha_vector = alpha_vector, confidence_vector = confidence_vector,
             n_names = length(alpha_vector)),
        file.path(out_dir, "_alpha_vectors.rds"))

cat("\n===== SUMMARY =====\n")
cat(sprintf("period: %s ~ %s | signal months: %d\n",
            min(scores_dt$Date), max(scores_dt$Date), uniqueN(scores_dt$Date)))
cat(sprintf("rank_IC=%.4f  ICIR(monthly)=%.3f  ICIR(ann)=%.3f  Harvey-t(NW3)=%.3f  IC_t_plain=%.3f\n",
            rank_ic, icir, icir * sqrt(12), harvey_t_rankic, ic_t_plain))
cat(sprintf("monotonicity(quintile spearman)=%.3f  subperiod_stability=%.3f\n", mono, subperiod_stability))
cat("decile fwd ret:", paste(round(dec$mret, 4), collapse = " "), "\n")
cat("subperiod mean IC:\n"); print(sub)
cat(sprintf("\n[canonical n=30] PORT_alpha_t_NW3=%.3f (p=%.4f) | IR=%.4f | netSR=%.4f | alpha_ann=%.4f | TO_ann=%.3f | n=%d\n",
            csb$portfolio_alpha_t_nw_lag3, csb$portfolio_alpha_t_pvalue, csb$information_ratio,
            csb$net_sr, csb$alpha_annualized, csb$turnover_annual, csb$n_months))
cat(sprintf("[canonical n=25] PORT_alpha_t_NW3=%.3f | IR=%.4f | netSR=%.4f | TO_ann=%.3f\n",
            csb25$portfolio_alpha_t_nw_lag3, csb25$information_ratio, csb25$net_sr, csb25$turnover_annual))
cat(sprintf("as_of=%s  n_names=%d  alpha_hat range=[%.4f, %.4f]\n",
            as_of, length(alpha_vector), min(alpha_vector), max(alpha_vector)))
cat("DONE\n")
