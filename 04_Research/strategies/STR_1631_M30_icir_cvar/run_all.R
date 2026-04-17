cat("=== STR_1631_M30: ICIR Factor Scaling x CVaR LP (2-Axis) ===\n")
## 핵심 아이디어: Factor축(ICIR scaling) + Stock축(CVaR LP 가중) 동시 적용
## Factor축: IC_mean / IC_vol 로 팩터별 가중 (M29 동일, Barroso & Santa-Clara 2015)
## Stock축: CVaR LP 최적화 (Rockafellar & Uryasev 2000, Pfaff 2016 Ch.12)
## M29 대비 변경: Step 4 HRP+ScoreTilt -> CVaR LP weights
## PIT: expanding IC 기반, t-1 lag (C1/C5 준수), CVaR lookback t-1 (C9 준수)
## Ref: Barroso & Santa-Clara (2015) JFE + Rockafellar & Uryasev (2000)

t0 <- Sys.time()

# ===================================================================
# 0. Environment Setup
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR   <- file.path(CACHE_DIR, "consensus")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD  <- 2e8
N_HOLD         <- 20L
MAX21D_EXCL    <- 0.80
CVAR_LOOKBACK  <- 120L     # M30: CVaR LP lookback (trading days)
CVAR_ALPHA     <- 0.95     # M30: CVaR confidence level
MAX_W          <- 0.15     # M30: max single-stock weight
REBAL_MONTHS   <- 2L
IC_MIN_MONTHS  <- 12L
IC_VOL_WINDOW  <- 12L

cat(sprintf("[M30] ICIR x CVaR LP | IC_vol_window=%dm | CVaR_lb=%dd alpha=%.2f | Bimonthly\n",
            IC_VOL_WINDOW, CVAR_LOOKBACK, CVAR_ALPHA))

# ===================================================================
# 1. Load RAWDATA (single load, OPT-1 compliant)
# ===================================================================
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]
dc <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(dc) > 0) RAWDATA[, (dc) := NULL]
if (!"Name" %in% names(RAWDATA) || !"Sector" %in% names(RAWDATA)) {
  ud <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "universe.parquet"))); ud[, Date := as.Date(Date)]
  setorder(ud, Ticker, -Date); ti <- ud[, .(Name = Name[1], Sector = Sector[1]), by = Ticker]
  if (!"Name" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Name)], by = "Ticker", all.x = TRUE)
  if (!"Sector" %in% names(RAWDATA)) RAWDATA <- merge(RAWDATA, ti[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)
  rm(ud, ti)
}
gc(verbose = FALSE)

RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]; setorder(sd_dt, sig_date)
sd_dt <- sd_dt[sig_date >= SIGNAL_START_DATE]
ALL_SIG_DATES <- sd_dt$sig_date
SIG_DATES <- ALL_SIG_DATES[seq(1, length(ALL_SIG_DATES), by = REBAL_MONTHS)]
cat(sprintf("[Step 1] Monthly dates: %d | Bimonthly SIG_DATES: %d\n",
            length(ALL_SIG_DATES), length(SIG_DATES)))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := shift(frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE),
                            n = 1L, type = "lag"), by = Ticker]  # C10: t-1 lag (LIQ_THRESHOLD=2e8)
RAWDATA[, TradVal := NULL]
RAWDATA[, Ret_abs := abs(Ret)]
RAWDATA[, MAX21d_raw := {
  ra <- Ret_abs; n <- length(ra)
  if (n < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, n = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(MAX21d_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("Ret_abs", "MAX21d_raw") := NULL]

SIG_SNAP <- RAWDATA[Date %in% ALL_SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ===================================================================
# 2. Load Consensus (single bulk load, OPT-1 compliant)
# ===================================================================
cat("\n[Step 2] Loading Consensus...\n")
lc <- function(f) {
  dt <- as.data.table(arrow::read_parquet(file.path(CONS_DIR, f))); dt[, Date := as.Date(Date)]
  dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date)
  cat(sprintf("  > %s: %s rows\n", f, format(nrow(dt), big.mark = ","))); dt
}
SUE_DT   <- lc("sue.parquet")
ESBR_DT  <- lc("esbr.parquet")
EPS1M_DT <- lc("eps_chg_1m.parquet")
COV_DT   <- lc("coverage.parquet")
TP_DT    <- lc("target_price.parquet")

# ===================================================================
# 3. IC computation (vectorized lapply) + Factor Vol Scaled weights
# ===================================================================
cat("\n[Step 3] Computing expanding IC + Factor Vol Scaling...\n")
z_safe <- function(x) {
  nv <- sum(!is.na(x)); if (nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x))); (x - mu) / s
}

# Step 3a: forward returns (vectorized via lapply)
fwd_map <- setNames(lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]
  if (i >= length(ALL_SIG_DATES)) return(NULL)
  next_sd <- ALL_SIG_DATES[i + 1]
  RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
}), as.character(ALL_SIG_DATES))

# Step 3b: raw z-scores (vectorized via lapply)
raw_scores_list <- lapply(seq_along(ALL_SIG_DATES), function(i) {
  sd <- ALL_SIG_DATES[i]
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) return(NULL)
  mq <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= mq]; if (nrow(univ) < 30L) return(NULL)
  probe <- data.table(Ticker = univ$Ticker, Date = sd); setkey(probe, Ticker, Date)
  sue_j   <- SUE_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, sue)]
  esbr_j  <- ESBR_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, esbr)]
  eps1m_j <- EPS1M_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, eps_chg_1m)]
  cov_j   <- COV_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, coverage)]
  tp_j    <- TP_DT[probe, roll = 7L, nomatch = NA][, .(Ticker, target_price)]
  sig <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = FALSE),
                list(univ[, .(Ticker, Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]; if (nrow(sig) < 20L) return(NULL)
  sig[, TP_Gap := (target_price - Close) / Close]
  sig[, z_sue := z_safe(sue)]; sig[, z_esbr := z_safe(esbr)]
  sig[, z_eps1m := z_safe(eps_chg_1m)]; sig[, z_tpgap := z_safe(TP_Gap)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if (nrow(sig) < 20L) return(NULL)
  data.table(Date = sd, Ticker = sig$Ticker,
    z_sue = sig$z_sue, z_esbr = sig$z_esbr, z_eps1m = sig$z_eps1m, z_tpgap = sig$z_tpgap)
})
RAW_SCORES <- rbindlist(raw_scores_list[!sapply(raw_scores_list, is.null)])

# Step 3c: expanding IC (vectorized via lapply)
unique_dates <- sort(unique(RAW_SCORES$Date))
ic_list <- lapply(seq_along(unique_dates), function(i) {
  sd <- unique_dates[i]
  fr <- fwd_map[[as.character(sd)]]; if (is.null(fr)) return(NULL)
  sc <- RAW_SCORES[Date == sd]; mg <- merge(sc, fr, by = "Ticker")
  if (nrow(mg) < 10L) return(NULL)
  data.table(Date = sd,
    ic_sue   = fifelse(is.na(cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_sue,   mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_esbr  = fifelse(is.na(cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_esbr,  mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_eps1m = fifelse(is.na(cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_eps1m, mg$fwd_ret, method = "spearman", use = "complete.obs")),
    ic_tpgap = fifelse(is.na(cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")), 0,
                       cor(mg$z_tpgap, mg$fwd_ret, method = "spearman", use = "complete.obs")))
})
ic_history <- rbindlist(ic_list[!sapply(ic_list, is.null)])
cat(sprintf("[Step 3c] IC history: %d months\n", nrow(ic_history)))

# Step 3d: M29 Factor Vol Scaled IC weights on BIMONTHLY dates
ic_weight_log <- list()
FACTORS_list <- lapply(seq_along(SIG_DATES), function(i) {
  sd <- SIG_DATES[i]
  sc <- RAW_SCORES[Date == sd]; if (nrow(sc) < 20L) return(NULL)
  past_ic <- ic_history[Date < sd]

  if (nrow(past_ic) < IC_MIN_MONTHS) {
    w_factors <- c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25)
  } else {
    mean_ic <- c(sue = mean(past_ic$ic_sue, na.rm = TRUE), esbr = mean(past_ic$ic_esbr, na.rm = TRUE),
                 eps1m = mean(past_ic$ic_eps1m, na.rm = TRUE), tpgap = mean(past_ic$ic_tpgap, na.rm = TRUE))
    recent_ic <- tail(past_ic, IC_VOL_WINDOW)
    vol_ic <- c(sue = sd(recent_ic$ic_sue, na.rm = TRUE), esbr = sd(recent_ic$ic_esbr, na.rm = TRUE),
                eps1m = sd(recent_ic$ic_eps1m, na.rm = TRUE), tpgap = sd(recent_ic$ic_tpgap, na.rm = TRUE))
    vol_ic <- pmax(vol_ic, 0.01)
    mean_ic_pos <- pmax(mean_ic, 0)
    vs_ic <- mean_ic_pos / vol_ic
    ic_sum <- sum(vs_ic)
    w_factors <- if (ic_sum < 1e-8) c(sue = 0.25, esbr = 0.25, eps1m = 0.25, tpgap = 0.25) else vs_ic / ic_sum
  }
  ic_weight_log[[as.character(sd)]] <<- w_factors

  sc[, C19_icw := w_factors["sue"] * z_sue + w_factors["esbr"] * z_esbr +
                  w_factors["eps1m"] * z_eps1m + w_factors["tpgap"] * z_tpgap]
  setorder(sc, -C19_icw); top <- head(sc, N_HOLD)
  data.table(Date = sd, Ticker = top$Ticker, Score = top$C19_icw)
})
FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
cat(sprintf("[Step 3d] FACTORS: %d rows | %d bimonthly months\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(SUE_DT, ESBR_DT, EPS1M_DT, COV_DT, TP_DT, RAW_SCORES, FACTORS_list, SIG_SNAP)
gc(verbose = FALSE)

# ===================================================================
# 4. CVaR LP Weights (M30: Stock axis change from HRP+ScoreTilt)
# ===================================================================
cat("\n[Step 4] Computing CVaR LP weights (bimonthly)...\n")

source(file.path(FUNC_PATH, "portfolio/advanced_weights.R"))

FACTORS_cvar <- copy(FACTORS); FACTORS_cvar[, Weight_cvar := NA_real_]
cvar_success <- 0L; cvar_fallback <- 0L

all_sig_dates_sorted <- sort(unique(FACTORS$Date))

cvar_results <- lapply(all_sig_dates_sorted, function(sd) {
  tickers <- FACTORS_cvar[Date == sd, Ticker]
  n_tk <- length(tickers)

  # Build return matrix using past data only (t-1, C9 compliant)
  ad <- sort(unique(RAWDATA[Date < sd, Date]))
  if (length(ad) < 30L) {
    return(list(sd = sd, w = setNames(rep(1/n_tk, n_tk), tickers), fb = TRUE))
  }
  lb_dates <- tail(ad, CVAR_LOOKBACK)
  rs <- RAWDATA[Date %in% lb_dates & Ticker %in% tickers, .(Date, Ticker, Ret)]

  # CVaR LP from advanced_weights.R (Rockafellar-Uryasev 2000)
  w <- tryCatch({
    wv <- calc_cvar_lp_weights(tickers, rs, alpha = CVAR_ALPHA,
                               n_days = CVAR_LOOKBACK, max_w = MAX_W)
    names(wv) <- tickers
    wv
  }, error = function(e) {
    cat(sprintf("  [CVaR LP fallback] %s: %s\n", sd, e$message))
    setNames(rep(1/n_tk, n_tk), tickers)
  })

  is_fb <- (max(w) - min(w)) < 1e-6
  list(sd = sd, w = w, fb = is_fb)
})

invisible(lapply(cvar_results, function(r) {
  tickers <- names(r$w)
  sapply(tickers, function(tk) FACTORS_cvar[Date == r$sd & Ticker == tk, Weight_cvar := r$w[tk]])
  if (r$fb) cvar_fallback <<- cvar_fallback + 1L else cvar_success <<- cvar_success + 1L
}))
cat(sprintf("[Step 4] CVaR LP: %d success, %d EW fallback\n", cvar_success, cvar_fallback))

# Inject CVaR weights into simulation via calc_ivol_weights hook
hwl <- list()
invisible(lapply(as.character(unique(FACTORS_cvar$Date)), function(d) {
  mf <- FACTORS_cvar[Date == as.Date(d)]; w <- mf$Weight_cvar
  if (all(is.na(w))) w <- rep(1 / nrow(mf), nrow(mf))
  hwl[[d]] <<- setNames(w, mf$Ticker)
}))
oi <- calc_ivol_weights
calc_ivol_weights <<- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  lapply(names(hwl), function(d) {
    hw <- hwl[[d]]; if (all(tickers %in% names(hw))) { w <- hw[tickers]; return(as.numeric(w / sum(w))) }
    NULL
  }) -> matches
  matches <- matches[!sapply(matches, is.null)]
  if (length(matches) > 0) return(matches[[1]])
  rep(1 / length(tickers), length(tickers))
}
sim_base <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = N_HOLD,
  weight_method = "ivol", commission = 0.0015, buffer_zone = list(keep_n = 35L, entry_n = 20L))
calc_ivol_weights <<- oi
perf_base <- summarise_perf(sim_base$strategy_xts, "M30_Base")
to_base <- calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

# ===================================================================
# 5. Regime-based risk layer (S5 mutation, artifact exists)
# ===================================================================
source(file.path(REGIME_DIR, "regime_engine_daily.R"))
REGIME <- build_daily_regime(use_cache = TRUE); setkey(REGIME, Date)
ip <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")
ID <- if (file.exists(ip)) { dt <- fread(ip); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt } else NULL
nd <- copy(sim_base$DAILY_NAV_DT); setkey(nd, Date)
nd <- REGIME[, .(Date, MRS, n_axes_firing)][nd, roll = TRUE]
nd <- merge(nd, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
if (!is.null(ID)) {
  nd <- merge(nd, ID[, .(Date, Ret_Inv)], by = "Date", all.x = TRUE)
  nd[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nd[, Ret_Inv := -BM_Ret]
nd[is.na(Ret_Inv), Ret_Inv := 0]; nd[is.na(MRS), MRS := 0]; nd[is.na(n_axes_firing), n_axes_firing := 0L]
nd[, crisis_flag := fifelse(MRS >= 60 & n_axes_firing >= 5, 1L, 0L)]
nd[, crisis_consec := {
  out <- integer(.N); cnt <- 0L
  idx <- seq_len(.N)
  sapply(idx, function(j) { if (nd$crisis_flag[j] == 1L) cnt <<- cnt + 1L else cnt <<- 0L; out[j] <<- cnt })
  out
}]
nd[, Layer := fifelse(crisis_consec >= 3L, 3L, fifelse(MRS >= 30, 2L, 1L))]
nd[, Ret_adj := fcase(
  Layer == 1L, Strategy_Ret,
  Layer == 2L, { fw <- pmax(0.5, 1.0 - (MRS - 30) / 60); fw * Strategy_Ret + (1 - fw) * 0 },
  Layer == 3L, 0.50 * Strategy_Ret + 0.20 * Ret_Inv + 0.30 * 0
)]
nd[, NAV_adj := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_adj)]
ov_xts <- xts(nd$Ret_adj, order.by = nd$Date); names(ov_xts) <- "Strategy"

# ===================================================================
# 6. Summary & Save
# ===================================================================
po <- summarise_perf(ov_xts, "M30_RegimeAdj"); pb <- summarise_perf(sim_base$bm_xts, "KOSPI200")
cat("\n================================================================\n")
cat("   STR_1631 M30: ICIR Factor Scaling x CVaR LP (2-Axis)\n")
cat("================================================================\n")
cat("--- Base ---\n"); print(perf_base)
cat("--- Regime Adjusted ---\n"); print(po)
cat("--- BM ---\n"); print(pb)
cat(sprintf("Turnover: %.1f%% | ICIR(IC_mean/IC_vol, %dm) x CVaR_LP(alpha=%.2f, lb=%dd) | Bimonthly\n",
            to_base, IC_VOL_WINDOW, CVAR_ALPHA, CVAR_LOOKBACK))

# Log IC weight evolution
ic_wt_dt <- rbindlist(lapply(names(ic_weight_log), function(d) {
  w <- ic_weight_log[[d]]
  data.table(Date = as.Date(d), w_sue = w["sue"], w_esbr = w["esbr"],
             w_eps1m = w["eps1m"], w_tpgap = w["tpgap"])
}))
fwrite(ic_wt_dt, file.path(OUT_DIR, "ic_weight_evolution.csv"))
cat("\n[IC Weight Dynamics] Last 5:\n")
print(tail(ic_wt_dt, 5))

source(file.path(FUNC_PATH, "hurdle_gate.R"))
sim_ov_h <- list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_adj, Strategy_Ret = Ret_adj)],
  PORTFOLIO_LOG = sim_base$PORTFOLIO_LOG)
hr <- run_hurdle_gate(sim_ov_h, FACTORS,
  strategy_name = "STR_1631_M30_icir_cvar", output_dir = OUT_DIR)
cat("--- Hurdle ---\n"); print(hr[c("pass", "score")])

generate_charts(list(strategy_xts = ov_xts, bm_xts = sim_base$bm_xts,
  DAILY_NAV_DT = nd[, .(Date, NAV = NAV_adj, Strategy_Ret = Ret_adj)]),
  output_dir = OUT_DIR, strategy_name = "STR_1631 M30 - ICIR x CVaR LP")

write_json(list(
  strategy = "STR_1631_M30_icir_cvar",
  mutation = "M30: ICIR Factor Scaling (Barroso) x CVaR LP (Rockafellar-Uryasev) 2-Axis",
  parent = "STR_1631_M29_facvol",
  change = "stock_weight axis: HRP+ScoreTilt -> CVaR LP. factor_weight unchanged (ICIR).",
  factor_axis = "IC_vol_scaled = expanding_mean_IC / rolling_12m_IC_vol (M29 identical)",
  stock_axis = sprintf("CVaR LP: alpha=%.2f, lookback=%dd, max_w=%.2f", CVAR_ALPHA, CVAR_LOOKBACK, MAX_W),
  ic_vol_window = IC_VOL_WINDOW,
  rebal_months = REBAL_MONTHS,
  pit_notes = list(C1 = "expanding IC only", C5 = "IC vol uses t-1 data",
                   C9 = "CVaR LP uses strictly past returns (Date < sd)"),
  base = as.list(perf_base), regime_adj = as.list(po), benchmark = as.list(pb),
  turnover = to_base, hurdle_pass = hr$pass, hurdle_score = hr$score,
  cvar_stats = list(success = cvar_success, fallback = cvar_fallback),
  final_ic_weights = as.list(tail(ic_wt_dt, 1)),
  run_time = as.numeric(difftime(Sys.time(), t0, units = "secs"))
), file.path(OUT_DIR, "performance.json"), pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[DONE] M30 complete in %.1f sec\n", difftime(Sys.time(), t0, units = "secs")))
