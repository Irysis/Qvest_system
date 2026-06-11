# =============================================================================
# WT-D20260611_001 — Full-universe risk-aware value composite sleeve re-derivation
# Alpha Research Agent (real-computation, measurement-graduation §1).
#
# Spec (reconstructed, MUST re-measure):
#   value composite = EW Z of {V02_EP, V14_EBIT_EV, V07_EV_EBITDA, V20_SP,
#                              V13_EV_Sales, V01_BM}  (Z_Score_Aligned, C13)
#                    + 0.5 * Z(R05_Tail_Risk aligned)   (tail tilt)
#   universe = KR_ALL_LIQ2E8 (20d avg traded value >= 2e8, t-1 PIT C10)
#   long-only top-N EW screen, monthly rebal, 15bps one-way.
#
# Performance via canonical_screen_bt() ONLY (no proxy hand-calc).
# Orthogonality vs production ret_orig (vanilla STR_1715).
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE  <- file.path(PROJECT_ROOT, ".cache")
FDB    <- file.path(CACHE, "factor_db")
OUTDIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_WT-D20260611_001_value_sleeve")
STAGE  <- file.path(PROJECT_ROOT, "stage_artifacts/WT-D20260611_001")
dir.create(STAGE, recursive = TRUE, showWarnings = FALSE)

# ---- load contract helpers ----
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
# Explicit source of contract BEFORE canonical_screen_bt (its internal ofile-based
# source() fails when nested-sourced → build_benchmark_compare not found).
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

VALUE_FACTORS <- c("V02_EP","V14_EBIT_EV","V07_EV_EBITDA","V20_SP","V13_EV_Sales","V01_BM")
TAIL_FACTOR   <- "R05_Tail_Risk"
TAIL_WEIGHT   <- 0.5
LIQ_MIN       <- 2e8
TOP_N         <- 20L
COST_BPS      <- 15

# =============================================================================
# 1. RAWDATA → monthly returns (compounded daily Ret) + month-end liquidity (t-1 ADV)
# =============================================================================
cat("[1] Loading RAWDATA...\n")
raw <- as.data.table(read_parquet(file.path(CACHE, "rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Ret",
                 "AdminStock","TradingHalt","UnfaithfulDisc")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2005-01-01") & Date <= as.Date("2026-06-30")]
raw[, ym := format(Date, "%Y%m")]
setorder(raw, Ticker, Date)

# month-end trading dates
me_dates <- raw[, .(eom = max(Date)), by = ym]
setorder(me_dates, ym)
me_dates[, eom_chr := as.character(eom)]

# Monthly compounded return per ticker per month: prod(1+daily Ret)-1
# NOTE: this is the ASSET monthly return input to canonical_screen_bt (Ret_1m),
#       which is allowed (asset-level realized return). Portfolio return composition
#       is done by the contract, not here. (python-policy §4 / answer-principles).
mret <- raw[!is.na(Ret), .(mret = prod(1 + Ret) - 1, ndays = .N), by = .(Ticker, ym)]
mret <- mret[ndays >= 5]   # require >=5 trading days in month

# benchmark monthly (from BM)
bm <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[Date >= as.Date("2005-01-01")]
bm[, ym := format(Date, "%Y%m")]
bmret <- bm[!is.na(BM_Ret), .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]

# =============================================================================
# 2. Universe per sig_date: 20d avg traded value (Vol*Close) over last ~20 td
#    using data with Date <= sig_eom (t-1 PIT: 20d window ends at month-end,
#    membership applied to NEXT month's forward return → no lookahead).
# =============================================================================
cat("[2] Building monthly liquidity (20d ADV, t-1 PIT)...\n")
raw[, tv := Vol * Close]
# rolling 20-trading-day ADV per ticker, aligned to each trading date
setorder(raw, Ticker, Date)
raw[, adv20 := frollmean(tv, 20, align = "right"), by = Ticker]
# clean-status flags at month end (no admin/halt/unfaithful)
# value at month-end date
me_liq <- raw[Date %in% me_dates$eom,
              .(Ticker, ym, adv20,
                bad = (AdminStock %in% 1) | (TradingHalt %in% 1) | (UnfaithfulDisc %in% 1))]
me_liq[is.na(bad), bad := FALSE]

# =============================================================================
# 3. Per-month value composite scores (load_month_factors → Z_Score_Aligned)
#    sig_date = month-end of factor month ym; forward return = month ym+1.
# =============================================================================
cat("[3] Computing value composite scores per month (load_month_factors)...\n")
months <- me_dates$ym
months <- months[months >= "200508" & months <= "202605"]

build_score_for_month <- function(ym_tag) {
  eom <- me_dates[ym == ym_tag, eom]
  fm <- tryCatch(load_month_factors(eom, coverage_min = 0.05),
                 error = function(e) NULL)
  if (is.null(fm) || nrow(fm) == 0) return(NULL)
  fm <- as.data.table(fm)
  # value composite = mean of aligned value factor Z
  vf <- fm[Factor_Name %in% VALUE_FACTORS]
  if (nrow(vf) == 0) return(NULL)
  val <- vf[, .(value_z = mean(Z_Score_Aligned, na.rm = TRUE),
                n_val = .N), by = Ticker]
  # tail tilt
  tf <- fm[Factor_Name == TAIL_FACTOR, .(Ticker, tail_z = Z_Score_Aligned)]
  sc <- merge(val, tf, by = "Ticker", all.x = TRUE)
  sc[is.na(tail_z), tail_z := 0]
  # require at least 3 of 6 value factors present (avoid thin composites)
  sc <- sc[n_val >= 3]
  sc[, score := value_z + TAIL_WEIGHT * tail_z]
  sc[, ym := ym_tag]
  sc[, .(ym, Ticker, score, value_z, tail_z, n_val)]
}

SCORE_CACHE <- file.path(OUTDIR, "scores_cache.parquet")
if (file.exists(SCORE_CACHE) && !identical(Sys.getenv("FORCE_RESCORE"), "1")) {
  scores <- as.data.table(read_parquet(SCORE_CACHE))
  cat(sprintf("   [cache] loaded scores: months=%d rows=%d\n", uniqueN(scores$ym), nrow(scores)))
} else {
  t0 <- Sys.time()
  score_list <- lapply(months, build_score_for_month)
  scores <- rbindlist(score_list, fill = TRUE)
  write_parquet(scores, SCORE_CACHE)
  cat(sprintf("   scored months=%d, rows=%d, elapsed=%.1fs\n",
              uniqueN(scores$ym), nrow(scores), as.numeric(Sys.time() - t0, "secs")))
}

# =============================================================================
# 4. Assemble scores_dt / returns_dt / bench_dt / liq_dt for canonical_screen_bt
#    Convention: at sig month ym, score known; forward return = month ym+1.
#    canonical_screen_bt aligns scores_dt$Date with returns_dt$Date (same Date),
#    so we map BOTH to the sig month-end Date, with Ret_1m = NEXT month return,
#    and liquidity adv = ADV at sig month-end (t-1 for next month → PIT-safe).
# =============================================================================
cat("[4] Aligning forward returns + liquidity...\n")
# Build ym -> next ym map (sequential month-end ordering)
ym_sorted <- sort(unique(me_dates$ym))
next_map <- data.table(ym = ym_sorted[-length(ym_sorted)],
                       ym_next = ym_sorted[-1])

# forward returns: join sig ym to next-month asset return
fwd <- merge(next_map, mret[, .(Ticker, ym_next = ym, Ret_1m = mret)],
             by = "ym_next", allow.cartesian = TRUE)
fwd <- fwd[, .(ym, Ticker, Ret_1m)]

# sig month-end Date for each ym
ym2date <- me_dates[, .(ym, Date = eom)]

scores_dt <- merge(scores[, .(ym, Ticker, score)], ym2date, by = "ym")[, .(Date, Ticker, score)]
returns_dt <- merge(fwd, ym2date, by = "ym")[, .(Date, Ticker, Ret_1m)]
# liquidity at sig month-end (applies to next-month selection → t-1 PIT)
liq_dt <- merge(me_liq[bad == FALSE, .(ym, Ticker, adv = adv20)], ym2date, by = "ym")[, .(Date, Ticker, adv)]

# bench: forward (next-month) benchmark return aligned to sig Date
bench_fwd <- merge(next_map, bmret[, .(ym_next = ym, BM_Ret = bm_mret)], by = "ym_next")
bench_dt <- merge(bench_fwd[, .(ym, BM_Ret)], ym2date, by = "ym")[, .(Date, BM_Ret)]

# drop months with no forward return (last month)
valid_dates <- intersect(unique(returns_dt$Date), unique(bench_dt$Date))
scores_dt <- scores_dt[Date %in% valid_dates]
returns_dt <- returns_dt[Date %in% valid_dates]
bench_dt  <- bench_dt[Date %in% valid_dates]
liq_dt    <- liq_dt[Date %in% valid_dates]

cat(sprintf("   scores_dt rows=%d months=%d | returns_dt rows=%d | liq_dt rows=%d\n",
            nrow(scores_dt), uniqueN(scores_dt$Date), nrow(returns_dt), nrow(liq_dt)))

# =============================================================================
# 5. canonical_screen_bt: full + 2017+ subperiod + anchored 3-split OOS
# =============================================================================
cat("[5] Running canonical_screen_bt (full + subperiods)...\n")

run_screen <- function(sdt, rdt, bdt, ldt, tag) {
  res <- canonical_screen_bt(sdt, rdt, bdt, top_n = TOP_N,
                             cost_bps_oneway = COST_BPS,
                             liq_dt = ldt, liq_min = LIQ_MIN,
                             run_id = tag, strategy_id = tag)
  res
}

full <- run_screen(scores_dt, returns_dt, bench_dt, liq_dt, "value_full")

# 2017+ subperiod (critical: restricted-universe value was negative here)
d2017 <- as.Date("2017-01-01")
sub17 <- run_screen(scores_dt[Date >= d2017], returns_dt[Date >= d2017],
                    bench_dt[Date >= d2017], liq_dt[Date >= d2017], "value_2017plus")

# anchored 3-split OOS: train [first, q], OOS [q, last] for q in {55%,65%,75%}
all_dates <- sort(unique(scores_dt$Date))
n_d <- length(all_dates)
oos_res <- list()
for (frac in c(0.55, 0.65, 0.75)) {
  cut_idx <- floor(n_d * frac)
  cut_date <- all_dates[cut_idx]
  is_dates <- all_dates[all_dates <= cut_date]
  oos_dates <- all_dates[all_dates > cut_date]
  is_r  <- run_screen(scores_dt[Date %in% is_dates], returns_dt[Date %in% is_dates],
                      bench_dt[Date %in% is_dates], liq_dt[Date %in% is_dates],
                      sprintf("value_IS_%d", round(frac*100)))
  oos_r <- run_screen(scores_dt[Date %in% oos_dates], returns_dt[Date %in% oos_dates],
                      bench_dt[Date %in% oos_dates], liq_dt[Date %in% oos_dates],
                      sprintf("value_OOS_%d", round(frac*100)))
  oos_res[[as.character(frac)]] <- list(
    cut_date = as.character(cut_date),
    is_sr = is_r$net_sr, oos_sr = oos_r$net_sr,
    is_port_t = is_r$portfolio_alpha_t_nw_lag3,
    oos_port_t = oos_r$portfolio_alpha_t_nw_lag3,
    retention = if (!is.na(is_r$net_sr) && is_r$net_sr != 0) oos_r$net_sr / is_r$net_sr else NA_real_
  )
}
retentions <- sapply(oos_res, function(x) x$retention)
oos_retention_median <- median(retentions, na.rm = TRUE)

# =============================================================================
# 6. Rank-IC diagnostics (advisory) + monthly sleeve net return series for cor
# =============================================================================
cat("[6] Rank-IC + sleeve return series for orthogonality...\n")
# rank-IC per month: spearman(score, forward Ret_1m) within liquid universe
ic_dt <- merge(scores_dt, returns_dt, by = c("Date","Ticker"))
ic_dt <- merge(ic_dt, liq_dt, by = c("Date","Ticker"))
ic_dt <- ic_dt[adv >= LIQ_MIN | is.na(adv)]
ic_by_m <- ic_dt[, .(ic = if (.N >= 10) cor(score, Ret_1m, method = "spearman") else NA_real_), by = Date]
ic_by_m <- ic_by_m[!is.na(ic)]
rank_ic <- mean(ic_by_m$ic)
icir <- rank_ic / sd(ic_by_m$ic)
# Harvey-t on rank-IC (NW not applied here — advisory): t = mean/se
harvey_t <- rank_ic / (sd(ic_by_m$ic) / sqrt(nrow(ic_by_m)))

# sleeve monthly net return series (reconstruct from canonical weights for cor)
# We recompute the canonical top-20 EW net series to correlate with production.
build_sleeve_series <- function(sdt, rdt, bdt, ldt) {
  S <- copy(sdt)[!is.na(score)]
  if (!is.null(ldt)) {
    S <- merge(S, ldt[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
    S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  }
  setorder(S, Date, -score)
  W <- S[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
  R <- rdt[!is.na(Ret_1m)]
  WR <- merge(W, R, by = c("Date","Ticker"), all.x = TRUE); WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  port[, cost := traded[as.character(Date)] * COST_BPS / 1e4]
  port[, ret_net := port_gross - cost]
  port[, .(Date, sleeve_ret = ret_net)]
}
sleeve_series <- build_sleeve_series(scores_dt, returns_dt, bench_dt, liq_dt)

# production ret_orig (vanilla 1715). anchor_date = sig date, realized_ym = return month.
prod_csv <- file.path(PROJECT_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
prod <- fread(prod_csv)
prod[, anchor_date := as.Date(anchor_date)]
# sleeve sig Date = month-end; production anchor_date = sig date. Align by realized_ym:
# sleeve Date corresponds to sig month; forward return realized in next month (ym+1).
# production realized_ym is the return month. Map sleeve Date -> realized ym (next month).
sleeve_series <- merge(sleeve_series, me_dates[, .(Date = eom, sig_ym = ym)], by = "Date")
sleeve_series <- merge(sleeve_series, next_map[, .(sig_ym = ym, realized_ym_tag = ym_next)],
                       by = "sig_ym")
sleeve_series[, realized_ym := paste0(substr(realized_ym_tag,1,4),"-",substr(realized_ym_tag,5,6))]
cor_dt <- merge(sleeve_series[, .(realized_ym, sleeve_ret)],
                prod[, .(realized_ym, ret_orig)], by = "realized_ym")
cor_dt <- cor_dt[!is.na(sleeve_ret) & !is.na(ret_orig)]
cor_vs_orig <- if (nrow(cor_dt) >= 12) cor(cor_dt$sleeve_ret, cor_dt$ret_orig) else NA_real_

# CAGR (from full net series, PerformanceAnalytics-style geometric)
# Use full$benchmark_compare for alpha; CAGR computed geometrically on net series.
nav_growth <- prod(1 + sleeve_series$sleeve_ret, na.rm = TRUE)
n_years <- nrow(sleeve_series) / 12
cagr <- nav_growth^(1/n_years) - 1
calmar <- {
  nav <- cumprod(1 + sleeve_series[order(Date)]$sleeve_ret)
  dd <- nav / cummax(nav) - 1
  mdd <- min(dd, na.rm = TRUE)
  if (mdd < 0) cagr / abs(mdd) else NA_real_
}

# =============================================================================
# 7. Emit results
# =============================================================================
cat("[7] Writing results...\n")
out <- list(
  meta = list(
    task_id = "WT-D20260611_001",
    as_of = "2026-06-11",
    universe = "KR_ALL_LIQ2E8",
    liq_min = LIQ_MIN, top_n = TOP_N, cost_bps = COST_BPS,
    value_factors = VALUE_FACTORS, tail_factor = TAIL_FACTOR, tail_weight = TAIL_WEIGHT,
    n_months = uniqueN(scores_dt$Date),
    date_range = as.character(range(scores_dt$Date)),
    metric_type = "canonical_screen",
    selection_type = "chain"
  ),
  full = list(
    n_months = full$n_months,
    portfolio_alpha_t_nw_lag3 = full$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue = full$portfolio_alpha_t_pvalue,
    information_ratio = full$information_ratio,
    alpha_annualized = full$alpha_annualized,
    net_sr = full$net_sr,
    turnover_annual = full$turnover_annual,
    cagr = cagr, calmar = calmar
  ),
  subperiod_2017plus = list(
    n_months = sub17$n_months,
    portfolio_alpha_t_nw_lag3 = sub17$portfolio_alpha_t_nw_lag3,
    net_sr = sub17$net_sr,
    information_ratio = sub17$information_ratio
  ),
  oos = list(splits = oos_res, retention_median = oos_retention_median),
  rank_ic_diag = list(rank_ic = rank_ic, icir = icir, harvey_t_rankic = harvey_t,
                      n_ic_months = nrow(ic_by_m)),
  orthogonality = list(cor_vs_ret_orig = cor_vs_orig, n_overlap = nrow(cor_dt)),
  metric_type = "canonical_screen"
)

write_json(out, file.path(STAGE, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
write_json(out, file.path(OUTDIR, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)

# alpha_scores.parquet: latest month alpha vector + confidence
latest_date <- max(scores_dt$Date)
latest_scores <- scores[ym == format(latest_date, "%Y%m")]
# alpha_vector = cross-sectional z of composite score -> expected active return proxy
latest_scores[, alpha_hat := score]  # composite score = standardized expected active proxy
# confidence: based on n_val coverage (3..7) scaled
latest_scores[, confidence := pmin(1, (n_val) / length(VALUE_FACTORS))]
write_parquet(latest_scores[, .(Ticker, alpha_hat, confidence, value_z, tail_z, n_val)],
              file.path(STAGE, "alpha_scores.parquet"))

cat("\n========== SUMMARY ==========\n")
cat(sprintf("FULL:      net_SR=%.3f  PORT_t=%.3f  IR=%.3f  CAGR=%.1f%%  TO=%.1f%%/yr  calmar=%.3f\n",
            full$net_sr, full$portfolio_alpha_t_nw_lag3, full$information_ratio,
            cagr*100, full$turnover_annual*100, calmar))
cat(sprintf("2017+:     net_SR=%.3f  PORT_t=%.3f  IR=%.3f\n",
            sub17$net_sr, sub17$portfolio_alpha_t_nw_lag3, sub17$information_ratio))
cat(sprintf("OOS:       retention_median=%.3f  (splits: %s)\n",
            oos_retention_median, paste(sprintf("%.2f", retentions), collapse=", ")))
cat(sprintf("Rank-IC:   ic=%.4f  icir=%.3f  harvey_t=%.3f  (advisory)\n", rank_ic, icir, harvey_t))
cat(sprintf("Orthog:    cor_vs_ret_orig=%.4f  (n_overlap=%d)\n", cor_vs_orig, nrow(cor_dt)))
cat("=============================\n")
saveRDS(out, file.path(OUTDIR, "alpha_result.rds"))
cat("DONE\n")
