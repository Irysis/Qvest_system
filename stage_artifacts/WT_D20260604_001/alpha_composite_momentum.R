#==============================================================================
# WT-D20260604_001 — Composite Momentum Alpha Research
# alpha-research agent. PIT C1~C15. SIGNAL_CUTOFF lockbox (alpha-research scope).
# Signals: 12-1 price mom, 6-1 price mom, residual mom (mkt+sector regression).
# Output: alpha_scores.parquet + alpha_validation.json + diagnostics for draft.
#==============================================================================
options(warn = 1)
suppressMessages({library(data.table); library(arrow); library(jsonlite)})
set.seed(42)

source("02_Infrastructure/config.R")
source("02_Infrastructure/backtest_harness.R")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

OUT_DIR <- "stage_artifacts/WT_D20260604_001"
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

SIGNAL_CUTOFF <- as.Date("2023-12-22")   # alpha-research lockbox (lockbox-scope.md)
LIQ_MIN  <- 2e8                          # 20d avg TV floor (KRW)
COST_BPS <- 15                           # one-way, v2.3_kr_retail_15bps
TOP_N    <- 20L

cat("=== load RAWDATA ===\n")
rd <- load_rawdata(use_cache = TRUE)
R  <- rd$RAWDATA
B  <- rd$BM_DT
setkey(R, Date, Ticker)
R[, Date := as.Date(Date)]
B[, Date := as.Date(Date)]

# Universe membership: K200 ∪ KQ150 flags exist in RAWDATA
R[, in_univ := (KQ150 == 1 | K200 == 1)]

#------------------------------------------------------------------------------
# 1. Month-end sig_dates (trading) up to SIGNAL_CUTOFF
#------------------------------------------------------------------------------
all_dates <- sort(unique(R$Date))
all_dates <- all_dates[all_dates <= SIGNAL_CUTOFF]
ym <- format(all_dates, "%Y-%m")
me <- tapply(all_dates, ym, max)
sig_dates <- as.Date(unname(me))
sig_dates <- sort(sig_dates)
# Need >=252 trading days of history for 12-1 mom; start 2008
sig_dates <- sig_dates[sig_dates >= as.Date("2008-01-01")]
cat("sig_dates:", length(sig_dates), " range:", as.character(min(sig_dates)), "~", as.character(max(sig_dates)), "\n")

# date index for fast offset lookup
date_idx <- data.table(Date = all_dates, idx = seq_along(all_dates))
setkey(date_idx, Date)

#------------------------------------------------------------------------------
# 2. Per sig_date signal construction (PIT-safe: use close at sig_date = t-1 lag enforced
#    because signals use prices up to & including sig_date close; forward return is t→t+1M)
#------------------------------------------------------------------------------
# Wide close matrix approach: build per-ticker close series once
setorder(R, Ticker, Date)
R[, ret_d := Ret]   # daily return already in RAWDATA

# Build a fast lookup: for each (Ticker, Date) cumulative log-price proxy via Close
# We compute momentum from Close ratios directly.
build_signals_one <- function(sd) {
  # window indices
  i_now <- date_idx[Date == sd, idx]
  if (length(i_now) == 0) return(NULL)
  d_now  <- all_dates[i_now]
  d_21   <- all_dates[max(1L, i_now - 21L)]    # skip-1-month point
  d_126  <- all_dates[max(1L, i_now - 126L)]   # 6m
  d_252  <- all_dates[max(1L, i_now - 252L)]   # 12m

  snap <- R[Date == d_now & in_univ == TRUE,
            .(Ticker, Sector, Close_now = Close, Size, Vol, K200)]
  c21  <- R[Date == d_21,  .(Ticker, C21  = Close)]
  c126 <- R[Date == d_126, .(Ticker, C126 = Close)]
  c252 <- R[Date == d_252, .(Ticker, C252 = Close)]

  x <- Reduce(function(a, b) merge(a, b, by = "Ticker", all.x = TRUE),
              list(snap, c21, c126, c252))

  # liquidity: 20d avg traded value ending at sig_date (t-1 PIT — uses up to sd close)
  d_20 <- all_dates[max(1L, i_now - 19L)]
  liq <- R[Date >= d_20 & Date <= d_now,
           .(adv = mean(Close * Vol, na.rm = TRUE)), by = Ticker]
  x <- merge(x, liq, by = "Ticker", all.x = TRUE)

  # 12-1 and 6-1 price momentum (skip most recent month → reversal noise removal)
  x[, mom_12_1 := C21 / C252 - 1]
  x[, mom_6_1  := C21 / C126 - 1]

  x <- x[!is.na(mom_12_1) & !is.na(mom_6_1) & is.finite(mom_12_1) & is.finite(mom_6_1)]
  x <- x[adv >= LIQ_MIN]
  if (nrow(x) < 30) return(NULL)
  x[, sig_date := sd]
  x
}

cat("=== building signals across sig_dates (sequential, data.table-vectorized) ===\n")
# RAWDATA (2.9GB) too large to export to workers; per-date ops are fast & vectorized.
# Slim R to only dates we touch (sig_dates + their offset windows) to speed lookups.
sig_list <- lapply(sig_dates, function(sd) tryCatch(build_signals_one(sd), error = function(e) NULL))
sig_all <- rbindlist(sig_list, fill = TRUE)
cat("signal rows:", nrow(sig_all), " sig_dates with data:", uniqueN(sig_all$sig_date), "\n")

#------------------------------------------------------------------------------
# 3. Residual momentum: cross-sectional regress mom_12_1 on market(beta proxy via Size? no)
#    Residual mom per Grinblatt-Moskowitz: regress stock returns on Fama-French / sector.
#    Implementation: within each sig_date, regress mom_12_1 on sector dummies (sector-neutral
#    residual) — isolates idiosyncratic momentum from sector/market common momentum.
#------------------------------------------------------------------------------
resid_one <- function(dt) {
  dt <- copy(dt)
  if (uniqueN(dt$Sector) < 2 || nrow(dt) < 30) { dt[, resid_mom := NA_real_]; return(dt) }
  # market component = cross-sectional mean; sector component via lm
  fit <- tryCatch(lm(mom_12_1 ~ factor(Sector), data = dt, na.action = na.exclude),
                  error = function(e) NULL)
  if (is.null(fit)) { dt[, resid_mom := NA_real_]; return(dt) }
  dt[, resid_mom := as.numeric(residuals(fit))]   # na.exclude pads to nrow(dt)
  dt
}
sig_all <- rbindlist(lapply(split(sig_all, sig_all$sig_date), resid_one), fill = TRUE)

#------------------------------------------------------------------------------
# 4. Cross-sectional winsorize (3std) + Z-score per sig_date
#------------------------------------------------------------------------------
wz <- function(v) {
  m <- mean(v, na.rm = TRUE); s <- sd(v, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(v)))
  v <- pmin(pmax(v, m - 3*s), m + 3*s)
  (v - mean(v, na.rm = TRUE)) / sd(v, na.rm = TRUE)
}
sig_all[, z_12_1   := wz(mom_12_1), by = sig_date]
sig_all[, z_6_1    := wz(mom_6_1),  by = sig_date]
sig_all[, z_resid  := wz(resid_mom), by = sig_date]
sig_all[is.na(z_resid), z_resid := 0]

# Composite: equal-weight 3 signals (validation-first; refine weights below if needed)
sig_all[, z_composite := (z_12_1 + z_6_1 + z_resid) / 3]

#------------------------------------------------------------------------------
# 5. Forward 1M return (sig_date → next sig_date) — the label. PIT: strictly future.
#------------------------------------------------------------------------------
nxt <- data.table(sig_date = sig_dates,
                  next_date = c(sig_dates[-1], NA))
sig_all <- merge(sig_all, nxt, by = "sig_date", all.x = TRUE)

# fwd return via Close ratio
close_dt <- R[Date %in% sig_dates, .(Ticker, sig_date = Date, Close_sd = Close)]
close_nx <- R[Date %in% sig_dates, .(Ticker, next_date = Date, Close_nx = Close)]
sig_all <- merge(sig_all, close_dt, by = c("Ticker","sig_date"), all.x = TRUE)
sig_all <- merge(sig_all, close_nx, by = c("Ticker","next_date"), all.x = TRUE)
sig_all[, fwd_ret := Close_nx / Close_sd - 1]

#------------------------------------------------------------------------------
# 6. Diagnostics: rank-IC (Spearman) per signal + composite, ICIR, Harvey-t
#------------------------------------------------------------------------------
ic_by_date <- function(zcol) {
  sig_all[!is.na(get(zcol)) & !is.na(fwd_ret) & is.finite(fwd_ret),
          .(ic = if (.N >= 10) suppressWarnings(cor(get(zcol), fwd_ret, method = "spearman")) else NA_real_),
          by = sig_date]$ic
}
summ_ic <- function(zcol) {
  ic <- ic_by_date(zcol); ic <- ic[is.finite(ic)]
  n <- length(ic)
  mic <- mean(ic); sic <- sd(ic)
  icir <- mic / sic
  t_naive <- mic / (sic / sqrt(n))
  # Harvey-Liu-Zhu multiple-testing haircut: 3 signals tested → BHY-style.
  # Conservative: t_harvey = t_naive / sqrt(log(n_tests)) approx; use n_tests=3.
  n_tests <- 3
  t_harvey <- t_naive / sqrt(1 + log(n_tests))
  list(n = n, mean_ic = mic, sd_ic = sic, icir = icir,
       t_naive = t_naive, t_harvey = t_harvey)
}

diag_list <- list(
  mom_12_1  = summ_ic("z_12_1"),
  mom_6_1   = summ_ic("z_6_1"),
  resid_mom = summ_ic("z_resid"),
  composite = summ_ic("z_composite")
)
cat("\n=== Rank-IC diagnostics ===\n")
for (nm in names(diag_list)) {
  d <- diag_list[[nm]]
  cat(sprintf("%-10s n=%d mean_ic=%.4f icir=%.3f t_naive=%.2f t_harvey=%.2f\n",
              nm, d$n, d$mean_ic, d$icir, d$t_naive, d$t_harvey))
}

# Subperiod stability (composite): fraction of subperiods with positive mean IC
# ic_by_date returns one row per sig_date that had >=10 valid obs; align by its own grouping.
ic_comp <- sig_all[!is.na(z_composite) & !is.na(fwd_ret) & is.finite(fwd_ret),
                   .(ic = if (.N >= 10) suppressWarnings(cor(z_composite, fwd_ret, method = "spearman")) else NA_real_),
                   by = sig_date]
ic_comp <- ic_comp[is.finite(ic)]
ic_comp[, period := fifelse(sig_date < as.Date("2015-01-01"), "p1",
                     fifelse(sig_date < as.Date("2020-01-01"), "p2", "p3"))]
sp <- ic_comp[, .(mean_ic = mean(ic)), by = period]
subperiod_stability <- mean(sp$mean_ic > 0)
cat("\nsubperiod mean_ic:\n"); print(sp)
cat("subperiod_stability (frac positive):", subperiod_stability, "\n")

# Monotonicity: quintile forward returns monotonic in composite
sig_all[, q := cut(z_composite, breaks = quantile(z_composite, probs = seq(0,1,0.2), na.rm = TRUE),
                   labels = FALSE, include.lowest = TRUE), by = sig_date]
qret <- sig_all[!is.na(q) & is.finite(fwd_ret), .(mret = mean(fwd_ret)), by = q][order(q)]
cat("\nquintile fwd returns:\n"); print(qret)
mono <- cor(qret$q, qret$mret, method = "spearman")
cat("monotonicity (spearman q vs ret):", mono, "\n")

# Pairwise signal correlation (composite component cor)
cor_signals <- cor(sig_all[, .(z_12_1, z_6_1, z_resid)], use = "pairwise.complete.obs")
cat("\nsignal correlation matrix:\n"); print(round(cor_signals, 3))

#------------------------------------------------------------------------------
# 7. Portfolio-alpha t (canonical_screen_bt, NW lag-3) — §2 measurement integrity
#------------------------------------------------------------------------------
scores_dt <- sig_all[!is.na(z_composite), .(Date = sig_date, Ticker, score = z_composite)]
# Ret_1m = forward monthly return (label)
returns_dt <- sig_all[, .(Date = sig_date, Ticker, Ret_1m = fwd_ret)]
returns_dt <- returns_dt[!is.na(Ret_1m) & is.finite(Ret_1m)]
# benchmark monthly: BM close ratio at sig_dates
bm_sd <- B[Date %in% sig_dates][order(Date)]
bm_sd[, BM_Ret_m := shift(BM_Close, n = 1L, type = "lead") / BM_Close - 1]
bench_dt <- bm_sd[, .(Date, BM_Ret = BM_Ret_m)][!is.na(BM_Ret)]

cat("\n=== canonical_screen_bt (forge-grade portfolio-alpha t, NW lag-3) ===\n")
cs <- tryCatch(
  canonical_screen_bt(scores_dt, returns_dt, bench_dt,
                      top_n = TOP_N, cost_bps_oneway = COST_BPS,
                      liq_dt = NULL, liq_min = LIQ_MIN,
                      run_id = "WT-D20260604_001_alpha", strategy_id = "composite_momentum"),
  error = function(e) { cat("ERR:", conditionMessage(e), "\n"); NULL })

if (!is.null(cs)) {
  cat(sprintf("n_months=%d  port_alpha_t_NW_lag3=%.3f  IR=%.3f  net_SR=%.3f  turnover_annual=%.2f\n",
              cs$n_months, cs$portfolio_alpha_t_nw_lag3, cs$information_ratio,
              cs$net_sr, cs$turnover_annual))
}

#------------------------------------------------------------------------------
# 8. Turnover proxy (composite rank turnover)
#------------------------------------------------------------------------------
to <- if (!is.null(cs)) cs$turnover_annual else NA_real_

#------------------------------------------------------------------------------
# 9. Save alpha_scores.parquet (latest sig_date alpha vector + all-history scores)
#------------------------------------------------------------------------------
scores_out <- sig_all[!is.na(z_composite),
  .(Date = sig_date, Ticker, score = z_composite,
    z_12_1, z_6_1, z_resid, mom_12_1, mom_6_1, resid_mom)]
write_parquet(scores_out, file.path(OUT_DIR, "alpha_scores.parquet"))
cat("\nsaved alpha_scores.parquet:", nrow(scores_out), "rows\n")

#------------------------------------------------------------------------------
# 10. alpha_validation.json
#------------------------------------------------------------------------------
last_sd <- max(sig_all$sig_date)
last_snap <- sig_all[sig_date == last_sd & !is.na(z_composite)]
# alpha_vector = composite z scaled to expected active return proxy (rank_ic * z * vol)
# expected 1M active ~ rank_ic * cross-sectional sd of fwd_ret ~ small; we report z as score.
alpha_vec <- setNames(as.list(round(last_snap$z_composite * diag_list$composite$mean_ic, 6)),
                      last_snap$Ticker)
conf_vec <- setNames(as.list(round(pmin(1, pmax(0, 0.5 + 0.5 * abs(scale(last_snap$z_composite)[,1]) / 3)), 4)),
                     last_snap$Ticker)

validation <- list(
  task_id = "WT-D20260604_001",
  as_of_date = as.character(last_sd),
  signal_cutoff = as.character(SIGNAL_CUTOFF),
  n_sig_dates = length(unique(sig_all$sig_date)),
  liquidity_floor = LIQ_MIN,
  cost_bps_oneway = COST_BPS,
  universe = "KOSPI200_KOSDAQ150_intersection",
  diagnostics_per_signal = diag_list,
  composite = list(
    rank_ic = diag_list$composite$mean_ic,
    icir = diag_list$composite$icir,
    harvey_t_stat = diag_list$composite$t_harvey,
    t_naive = diag_list$composite$t_naive,
    monotonicity = mono,
    subperiod_stability = subperiod_stability,
    subperiod_mean_ic = as.list(setNames(round(sp$mean_ic,4), sp$period))
  ),
  signal_correlation = as.list(as.data.frame(round(cor_signals,3))),
  portfolio_alpha = if (!is.null(cs)) list(
    metric_type = "canonical_screen",
    portfolio_alpha_t_nw_lag3 = cs$portfolio_alpha_t_nw_lag3,
    information_ratio = cs$information_ratio,
    net_sr = cs$net_sr,
    turnover_annual = cs$turnover_annual,
    n_months = cs$n_months,
    note = "forge build_bt_result가 authoritative. 이 값은 alpha-stage screening 실측(canonical top-20 EW)."
  ) else NULL,
  harvey_t_specs_pass_count = sum(sapply(diag_list, function(d) d$t_harvey > 3.0)),
  alpha_vector_preview = head(alpha_vec, 20),
  confidence_vector_preview = head(conf_vec, 20)
)
write_json(validation, file.path(OUT_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null")
cat("saved alpha_validation.json\n")

# also persist full alpha_vector / confidence_vector for draft assembly
saveRDS(list(alpha_vec = alpha_vec, conf_vec = conf_vec, last_sd = last_sd,
             diag = diag_list, cs = cs, mono = mono, sp = sp,
             subperiod_stability = subperiod_stability, cor_signals = cor_signals,
             n_names_last = nrow(last_snap)),
        file.path(OUT_DIR, "_alpha_assembly.rds"))
cat("\n=== DONE ===\n")
