#==============================================================================
# WT-D20260614_003 — QUAL_DEFENSE Alpha Research (alpha-research role)
# Q01_GPA + Q04_Piotroski_F + Q09_CFOA + Q07_Earnings_Stability EW z-composite
# n=30 monthly, KOSPI200 ∪ KOSDAQ150 (PIT), 2005-01 ~ 2026-06.
# Role: α̂ only. NO covariance / NO weights / NO optimization.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr); library(jsonlite)
})
options(stringsAsFactors = FALSE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/universe_expanded_v2.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

WT <- "WT-D20260614_003"
OUT_AF <- file.path(ROOT, "stage_artifacts", "WT_D20260614_003")
dir.create(OUT_AF, showWarnings = FALSE, recursive = TRUE)

FACTORS <- c("Q01_GPA", "Q04_Piotroski_F", "Q09_CFOA", "Q07_Earnings_Stability")
TOP_N   <- 30L
LIQ_MIN <- 2e8           # 헌법 hard floor (request 5e7 < 2e8 → 보수적으로 2e8 적용)
COST_BPS <- 15           # cost_model_version v2.4_kr_retail_15bps
START   <- as.Date("2005-01-01")
END     <- as.Date("2026-06-30")

cat("=== Loading rawdata (monthly panel) ===\n")
ds <- open_dataset(".cache/rawdata.parquet")
raw <- as.data.table(ds %>%
  select(Date, Ticker, K200, KQ150, Close, Vol, Ret, BM_Ret) %>%
  filter(Date >= as.Date("2004-06-01")) %>%
  collect())
setorder(raw, Ticker, Date)
raw[, Date := as.Date(Date)]

# --- Proper MONTHLY benchmark return (compound daily BM_Ret within each calendar month) ---
# BM_Ret in rawdata is DAILY. Month-end snapshot's single-day BM_Ret is NOT the monthly BM.
bm_daily <- unique(raw[, .(Date, BM_Ret)])[order(Date)]
bm_daily[, ymb := format(Date, "%Y%m")]
bm_monthly <- bm_daily[!is.na(BM_Ret), .(BM_Ret_m = prod(1 + BM_Ret) - 1), by = ymb]
# map to canonical month-end date below (after me_dates built)

# --- 20d avg trading value (ADV) PIT: trailing 20 trading days (uses Vol * Close) ---
# Vol is share volume; trading value = Vol * Close. Trailing 20d mean per ticker.
raw[, tv := Vol * Close]
raw[, adv20 := frollmean(tv, 20, align = "right"), by = Ticker]

# --- Canonical market-wide month-end date per calendar month ---
# (NOT per-ticker last-obs — that scrambles sig_date alignment across tickers.)
raw[, ym := format(Date, "%Y%m")]
me_dates <- raw[, .(me_date = max(Date)), by = ym]          # one date per month, market-wide
# attach proper monthly BM return to each canonical month-end date
me_dates <- merge(me_dates, bm_monthly, by.x = "ym", by.y = "ymb", all.x = TRUE)
setkey(me_dates, ym)
bm_monthly_by_date <- me_dates[, .(Date = me_date, BM_Ret_m)]
# month-end snapshot = each ticker's row ON the canonical month-end date.
# A ticker that did not trade on the exact me_date is absent that month (conservative).
me <- merge(raw, me_dates, by = "ym")
me <- me[Date == me_date]
me[, ym_int := as.integer(ym)]
setorder(me, Ticker, ym_int)

# --- Forward 1M return: next CANONICAL month-end close / this close - 1 ---
me[, fwd_close := shift(Close, type = "lead"), by = Ticker]
me[, fwd_ym_int := shift(ym_int, type = "lead"), by = Ticker]
me[, Ret_1m := fwd_close / Close - 1]
# guard: only consecutive calendar months (no gap > 1 month → set NA, avoids stale joins)
me[, gap_ok := {
  y1 <- ym_int %/% 100; m1 <- ym_int %% 100
  y2 <- fwd_ym_int %/% 100; m2 <- fwd_ym_int %% 100
  (y2 * 12 + m2) - (y1 * 12 + m1) == 1
}]
me[gap_ok == FALSE | is.na(gap_ok), Ret_1m := NA_real_]

cat("=== Building monthly signal dates (canonical month-end) ===\n")
# signal dates = one canonical month-end per calendar month
sig_dates <- sort(unique(me_dates$me_date))
sig_dates <- sig_dates[sig_dates >= START & sig_dates <= END]

# ---- Per-month: universe (K200∪KQ150 PIT) + liquidity + 4-factor EW z composite ----
build_month <- function(sd) {
  ym_tag <- format(sd, "%Y%m")
  snap <- me[ym == ym_tag]
  if (nrow(snap) == 0) return(NULL)
  # PIT universe membership at sig_date (K200 / KQ150 flags from rawdata month-end)
  snap[, in_univ := (K200 == 1 | KQ150 == 1)]
  snap[is.na(in_univ), in_univ := FALSE]
  # liquidity filter: trailing 20d ADV >= LIQ_MIN (C10 — uses data up to month-end = t-1 for next-month decision)
  snap[, liq_ok := !is.na(adv20) & adv20 >= LIQ_MIN]
  univ <- snap[in_univ == TRUE & liq_ok == TRUE]
  if (nrow(univ) < TOP_N) return(NULL)

  # Load 4 quality factors (PIT-safe connector, C15)
  ff <- tryCatch(load_month_factors(sd, coverage_min = 0.05, factor_names = FACTORS),
                 error = function(e) NULL)
  if (is.null(ff) || nrow(ff) == 0) return(NULL)
  ff <- ff[Ticker %in% univ$Ticker]
  # wide: one row per ticker, columns = factor z (already direction-aligned, higher=better)
  w <- dcast(ff, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = function(x) x[1])
  have <- intersect(FACTORS, names(w))
  if (length(have) < 2L) return(NULL)   # need >=2 factors present
  # EW composite z: re-standardize each available factor cross-sectionally then average.
  for (f in have) {
    z <- w[[f]]
    mu <- mean(z, na.rm = TRUE); sg <- sd(z, na.rm = TRUE)
    w[[f]] <- if (is.finite(sg) && sg > 0) (z - mu) / sg else NA_real_
  }
  w[, score := rowMeans(.SD, na.rm = TRUE), .SDcols = have]
  w[, n_have := rowSums(!is.na(.SD)), .SDcols = have]
  w <- w[n_have >= 2L & is.finite(score)]
  if (nrow(w) < TOP_N) return(NULL)

  # attach forward returns + adv (for liq_dt) from snap. BM = proper MONTHLY return.
  m <- merge(w[, .(Ticker, score)], snap[, .(Ticker, Ret_1m, adv20)],
             by = "Ticker", all.x = TRUE)
  m[, Date := sd]
  m[, BM_Ret := bm_monthly_by_date[Date == sd, BM_Ret_m][1]]
  m
}

cat("=== Computing", length(sig_dates), "months ===\n")
panel_list <- lapply(sig_dates, build_month)
panel <- rbindlist(panel_list, fill = TRUE)
panel <- panel[!is.na(score)]
cat("Panel rows:", nrow(panel), " months with data:", uniqueN(panel$Date), "\n")

#==============================================================================
# DIAGNOSTICS
#==============================================================================
# --- Rank IC (Spearman) per month: score vs Ret_1m ---
ic_tbl <- panel[!is.na(Ret_1m), .(
  ic = suppressWarnings(cor(score, Ret_1m, method = "spearman", use = "complete.obs")),
  n = .N
), by = Date][n >= 10 & is.finite(ic)]
setorder(ic_tbl, Date)

rank_ic <- mean(ic_tbl$ic, na.rm = TRUE)
ic_sd   <- sd(ic_tbl$ic, na.rm = TRUE)
icir    <- rank_ic / ic_sd                      # monthly ICIR
n_ic    <- nrow(ic_tbl)
# Harvey-t on rank-IC series (Newey-West would be ideal; report simple t + note)
ic_t_simple <- rank_ic / (ic_sd / sqrt(n_ic))
# Newey-West lag-3 t on IC mean
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n
  v <- g0
  for (l in 1:lag) {
    wl <- 1 - l / (lag + 1)
    gl <- sum(e[(l + 1):n] * e[1:(n - l)]) / n
    v <- v + 2 * wl * gl
  }
  se <- sqrt(v / n)
  mu / se
}
ic_t_nw <- nw_t(ic_tbl$ic, 3L)
harvey_t <- ic_t_nw   # rank-IC Harvey-style t (NW lag-3)

# --- Monotonicity: decile mean forward return monotonic increasing fraction ---
mono_by_month <- panel[!is.na(Ret_1m), {
  if (.N >= 20) {
    q <- cut(frank(score), breaks = 5, labels = FALSE)  # quintiles
    dm <- tapply(Ret_1m, q, mean)
    if (length(dm) == 5 && !any(is.na(dm))) {
      # Spearman of quintile index vs mean return
      cor(seq_along(dm), as.numeric(dm), method = "spearman")
    } else NA_real_
  } else NA_real_
}, by = Date]
monotonicity <- mean((mono_by_month$V1 + 1) / 2, na.rm = TRUE)  # map [-1,1]->[0,1]

# --- Subperiod stability: rank-IC mean sign consistency across 3 subperiods ---
ic_tbl[, sp := fcase(
  Date < as.Date("2014-01-01"), "p1_2005_2013",
  Date < as.Date("2020-01-01"), "p2_2014_2019",
  default = "p3_2020_2026"
)]
sp_ic <- ic_tbl[, .(mean_ic = mean(ic), n = .N), by = sp]
# stability = fraction of subperiods with same sign as overall, weighted
sp_same <- mean(sign(sp_ic$mean_ic) == sign(rank_ic))
subperiod_stability <- sp_same

cat(sprintf("rank_ic=%.4f icir=%.3f harvey_t(NW3)=%.2f mono=%.3f subperiod=%.2f n_ic=%d\n",
            rank_ic, icir, harvey_t, monotonicity, subperiod_stability, n_ic))

#==============================================================================
# CONDITIONAL IC (AX-001 v2 — bad / normal regime)
#==============================================================================
# Regime def: bad month = BM in trailing-3m drawdown OR negative BM return month.
# Use month-end BM return series.
bm_m <- unique(panel[, .(Date, BM_Ret)])[order(Date)]
# trailing benchmark cumulative & drawdown on monthly basis
bm_m[, bm_cum := cumprod(1 + ifelse(is.na(BM_Ret), 0, BM_Ret))]
bm_m[, bm_peak := cummax(bm_cum)]
bm_m[, bm_dd := bm_cum / bm_peak - 1]
# bad regime: in drawdown deeper than -10% (stress) — PIT: dd known at month-end (sig_date)
bm_m[, regime := fifelse(bm_dd <= -0.10, "bad", "normal")]
ic_reg <- merge(ic_tbl[, .(Date, ic)], bm_m[, .(Date, regime, bm_dd, BM_Ret)], by = "Date")
ic_bad <- mean(ic_reg[regime == "bad", ic], na.rm = TRUE)
ic_normal <- mean(ic_reg[regime == "normal", ic], na.rm = TRUE)
n_bad <- ic_reg[regime == "bad", .N]; n_normal <- ic_reg[regime == "normal", .N]
bad_normal_ic_ratio <- ic_bad / ic_normal

cat(sprintf("IC bad=%.4f (n=%d) normal=%.4f (n=%d) ratio=%.2f\n",
            ic_bad, n_bad, ic_normal, n_normal, bad_normal_ic_ratio))

#==============================================================================
# CANONICAL SCREEN BACKTEST (real-computation, n=30 EW long-only, net of 15bps)
#==============================================================================
scores_dt  <- panel[, .(Date, Ticker, score)]
returns_dt <- panel[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
bench_dt   <- bm_m[, .(Date, BM_Ret)]
liq_dt     <- panel[, .(Date, Ticker, adv = adv20)]

csb <- canonical_screen_bt(scores_dt, returns_dt, bench_dt,
                           top_n = TOP_N, cost_bps_oneway = COST_BPS,
                           liq_dt = liq_dt, liq_min = LIQ_MIN,
                           run_id = "QUAL_DEFENSE", strategy_id = "QUAL_DEFENSE")

cat(sprintf("\n=== CANONICAL SCREEN (top%d, net %dbps) ===\n", TOP_N, COST_BPS))
cat(sprintf("n_months=%d portfolio_alpha_t_NW3=%.3f IR=%.3f net_SR=%.3f alpha_ann=%.4f TO_ann=%.3f\n",
            csb$n_months, csb$portfolio_alpha_t_nw_lag3, csb$information_ratio,
            csb$net_sr, csb$alpha_annualized, csb$turnover_annual))

#==============================================================================
# CRISIS ALPHA — net active return during stress months (regime == bad)
#==============================================================================
# Reconstruct top-N EW net port return series for crisis decomposition.
setorder(scores_dt, Date, -score)
W <- merge(scores_dt, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
W <- W[is.na(adv) | adv >= LIQ_MIN]
W <- W[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = 1/n) }, by = Date]
WR <- merge(W, returns_dt, by = c("Date","Ticker"), all.x = TRUE)
WR[is.na(Ret_1m), Ret_1m := 0]
port_m <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date][order(Date)]
# turnover & net
dts <- port_m$Date
traded <- numeric(length(dts)); prev <- data.table(Ticker = character(0), w = numeric(0))
for (i in seq_along(dts)) {
  cur <- W[Date == dts[i], .(Ticker, w)]
  mm <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_c","_p"))
  mm[is.na(w_c), w_c := 0]; mm[is.na(w_p), w_p := 0]
  traded[i] <- sum(abs(mm$w_c - mm$w_p)); prev <- cur
}
port_m[, ret_net := port_gross - traded * COST_BPS / 1e4]
port_m <- merge(port_m, bm_m[, .(Date, BM_Ret, regime, bm_dd)], by = "Date")
port_m[, active_net := ret_net - BM_Ret]

crisis <- port_m[regime == "bad"]
crisis_alpha_mean <- mean(crisis$active_net, na.rm = TRUE)
crisis_alpha_events <- nrow(crisis[active_net > 0])
crisis_n <- nrow(crisis)
crisis_hit <- crisis_alpha_events / max(crisis_n, 1)
# MDD of the sleeve (net) — for defense MDD complement
sleeve_cum <- cumprod(1 + port_m$ret_net)
sleeve_mdd <- min(sleeve_cum / cummax(sleeve_cum) - 1, na.rm = TRUE)
bm_mdd <- min(bm_m$bm_dd, na.rm = TRUE)

cat(sprintf("\n=== CRISIS / DEFENSE ===\n"))
cat(sprintf("crisis months(n)=%d  active>0 events=%d  hit=%.2f  crisis_alpha_mean=%.4f\n",
            crisis_n, crisis_alpha_events, crisis_hit, crisis_alpha_mean))
cat(sprintf("sleeve_net_MDD=%.3f  BM_MDD=%.3f\n", sleeve_mdd, bm_mdd))

#==============================================================================
# DSR (diagnostic only — chain/single, advisory per request severity)
#==============================================================================
# Deflated Sharpe via single-trial approximation (n_trials=1 → DSR≈Φ((SR)*sqrt(T-1)/...))
T_obs <- csb$n_months
sr_m <- csb$net_sr / sqrt(12)   # per-month SR
# skew/kurt of active series
act <- port_m$active_net
sk <- mean((act - mean(act))^3) / sd(act)^3
ku <- mean((act - mean(act))^4) / sd(act)^4
sr_star <- 0  # benchmark SR threshold (single hypothesis)
dsr_num <- (sr_m - sr_star) * sqrt(T_obs - 1)
dsr_den <- sqrt(1 - sk * sr_m + (ku - 1)/4 * sr_m^2)
dsr <- pnorm(dsr_num / dsr_den)

#==============================================================================
# PER-NAME α̂ + confidence_vector at as_of_date (latest month-end)
#==============================================================================
as_of <- max(panel$Date)
latest <- panel[Date == as_of]
# α̂ = score-implied expected active return. Scale: map cross-sectional score to
# expected 1M active return via realized IC * cross-sectional return dispersion.
# Conservative (uncertainty-aware ③): use net IC and shrink.
ret_disp <- sd(returns_dt$Ret_1m, na.rm = TRUE)  # cross-time/section dispersion proxy
# expected active ≈ rank_ic_net_proxy * z_score * monthly_active_vol
monthly_active_vol <- sd(port_m$active_net, na.rm = TRUE)
# shrink: μ̃ = μ̂ - k*SE ; k=0.5 conservative
k_shrink <- 0.5
latest[, z := scale(score)[,1]]
latest[, alpha_hat_raw := rank_ic * z * ret_disp]  # gross-ish point estimate
# confidence: based on z magnitude rank stability proxy + coverage
latest[, conf := pmin(1, pmax(0.2, 0.4 + 0.3 * pnorm(abs(z)) ))]
# uncertainty shrink toward 0
latest[, alpha_hat := alpha_hat_raw * (1 - k_shrink * (1 - conf))]
setorder(latest, -alpha_hat)

alpha_vector <- setNames(round(latest$alpha_hat, 6), latest$Ticker)
conf_vector  <- setNames(round(latest$conf, 4), latest$Ticker)

cat(sprintf("\n=== PER-NAME α̂ @ %s ===\n", as_of))
cat("N names:", nrow(latest), " top5:", paste(head(latest$Ticker,5), collapse=","), "\n")
cat("alpha_hat mean:", round(mean(latest$alpha_hat),5),
    " top: ", round(max(latest$alpha_hat),5), "\n")

#==============================================================================
# SAVE alpha_scores.parquet
#==============================================================================
scores_out <- panel[, .(Date, Ticker, score, Ret_1m, adv20, BM_Ret)]
write_parquet(scores_out, file.path(OUT_AF, "alpha_scores.parquet"))
# latest per-name for handoff
latest_out <- latest[, .(Ticker, score, z, alpha_hat, conf)]
write_parquet(latest_out, file.path(OUT_AF, "alpha_latest.parquet"))

#==============================================================================
# Emit diagnostics RDS for the package builder
#==============================================================================
diag <- list(
  rank_ic = rank_ic, icir = icir, ic_sd = ic_sd, n_ic = n_ic,
  harvey_t_nw3 = harvey_t, ic_t_simple = ic_t_simple,
  monotonicity = monotonicity, subperiod_stability = subperiod_stability,
  subperiod_ic = as.list(setNames(round(sp_ic$mean_ic,4), sp_ic$sp)),
  subperiod_n = as.list(setNames(sp_ic$n, sp_ic$sp)),
  ic_bad = ic_bad, ic_normal = ic_normal, n_bad = n_bad, n_normal = n_normal,
  bad_normal_ic_ratio = bad_normal_ic_ratio,
  portfolio_alpha_t_nw_lag3 = csb$portfolio_alpha_t_nw_lag3,
  portfolio_alpha_t_pvalue = csb$portfolio_alpha_t_pvalue,
  information_ratio = csb$information_ratio,
  alpha_annualized = csb$alpha_annualized,
  net_sr = csb$net_sr, turnover_annual = csb$turnover_annual,
  crisis_n = crisis_n, crisis_alpha_events = crisis_alpha_events,
  crisis_hit = crisis_hit, crisis_alpha_mean = crisis_alpha_mean,
  sleeve_net_mdd = sleeve_mdd, bm_mdd = bm_mdd,
  dsr = dsr, n_trials = 1L, T_obs = T_obs,
  as_of = as.character(as_of), n_names_latest = nrow(latest),
  n_months_panel = uniqueN(panel$Date)
)
saveRDS(diag, file.path(OUT_AF, "diag.rds"))
saveRDS(list(alpha_vector = alpha_vector, conf_vector = conf_vector),
        file.path(OUT_AF, "vectors.rds"))
# monthly active series for risk/optimizer downstream
write_parquet(port_m[, .(Date, ret_net, BM_Ret, active_net, regime, bm_dd)],
              file.path(OUT_AF, "sleeve_monthly.parquet"))

cat("\n=== DONE. Artifacts written to", OUT_AF, "===\n")
cat("DSR(diag, single-trial)=", round(dsr,3), "\n")
