cat("=== STR_1690 REBUILD: WT-D20260425_006 MEGA_05 Crisis Overlay (Iter 1) — Walk-Forward Opus 4.7 ===\n")
## 핵심아이디어: MEGA_05 6F baseline + DD Brake (6/8/20) + VolReg (12%/60d) overlay
##   — 이전 sonnet 4.6 결과 무효 (single-snapshot weights 22년 정적 적용 = invalid)
##   — Opus 4.7 walk-forward: 매 sig_date마다 alpha 재산출 + 동적 ranking + dynamic weights
##   — alpha_scores.parquet 252 sig_dates × 3033 tickers 시계열 활용
##   — overlay_signals.parquet 252 monthly multipliers (PIT t-1 lag) 활용
##   — Pure function: alpha_pkg / risk_pkg / opt_pkg READ-ONLY (md5 시작/완료 동일)
## L-122 Barroso-Santa-Clara (2015) risk-managed framework KR multifactor 응용
## AX-002 process honesty: 하네스 walk-forward만 유효 / single-snapshot 정적 적용 무효

# ──────────────────────────────────────────────────────────────────────────────
# Forge Integration Audit v6.1 — Pure Function 경계 선언
# ──────────────────────────────────────────────────────────────────────────────
# BOUNDARY_PASS_START: alpha_package / risk_package / optimization_package READ-ONLY
# target_weights snapshot: 참조용만 (n=20 cap, max_w=0.20 등 method spec 추출)
# alpha_scores.parquet: 시계열 score_eff (매 sig_date) 사용 — 252 dates 모두 활용
# overlay_signals.parquet: 시계열 overlay_mult (매 sig_date, t-1 lag) 사용
# Sigma: 재추정 금지 — 단, walk-forward 시 weight_method 호출 시 cov는 PIT-rolling 사용
# 허용 write: run_all.R, backtest_result/*

t0 <- Sys.time()
QEPM_AUTO_COMMIT <- TRUE
WK_ID  <- "WT-D20260425_006"
STR_ID <- "STR_1690_WT006_CrisisOverlay"

# ──────────────────────────────────────────────────────────────────────────────
# 0. Environment
# ──────────────────────────────────────────────────────────────────────────────
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
WT_DIR     <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WK_ID)
ARTIF_DIR  <- file.path(PROJECT_ROOT, "qepm/stage_artifacts", paste0("WT_", WK_ID))
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile),
                        error = function(e) {
                          file.path(PROJECT_ROOT, "04_Research/strategies", STR_ID)
                        })
OUT_DIR    <- file.path(STRAT_DIR, "backtest_result")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite); library(digest)
})
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))
cat(sprintf("[setup] WK_ID: %s | STR_ID: %s\n", WK_ID, STR_ID))
cat(sprintf("[setup] OUT_DIR: %s\n", OUT_DIR))

# ──────────────────────────────────────────────────────────────────────────────
# 1. Hash 검증 (시작) — 3-package md5
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 1] Hash verification — 3-package PIT boundary check\n")
PKG_ALPHA <- file.path(WT_DIR, "alpha_package.json")
PKG_RISK  <- file.path(WT_DIR, "risk_package.json")
PKG_OPT   <- file.path(WT_DIR, "optimization_package.json")

HASH_START <- list(
  alpha_md5 = digest(readLines(PKG_ALPHA, warn = FALSE), algo = "md5"),
  risk_md5  = digest(readLines(PKG_RISK,  warn = FALSE), algo = "md5"),
  opt_md5   = digest(readLines(PKG_OPT,   warn = FALSE), algo = "md5")
)
cat(sprintf("  alpha_pkg md5: %s\n  risk_pkg  md5: %s\n  opt_pkg   md5: %s\n",
            HASH_START$alpha_md5, HASH_START$risk_md5, HASH_START$opt_md5))

# ──────────────────────────────────────────────────────────────────────────────
# 2. Load 3-agent packages (READ-ONLY)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 2] Load 3-agent packages (read-only)\n")
alpha_pkg <- fromJSON(PKG_ALPHA, simplifyVector = FALSE)
risk_pkg  <- fromJSON(PKG_RISK,  simplifyVector = FALSE)
opt_pkg   <- fromJSON(PKG_OPT,   simplifyVector = FALSE)

# Alpha overlay params (from primary_config) — declarative spec only
OVL_DD_ENTRY <- alpha_pkg$primary_config$overlay$dd_brake$entry      # 0.06
OVL_DD_EXIT  <- alpha_pkg$primary_config$overlay$dd_brake$exit       # 0.08
OVL_DD_LB    <- alpha_pkg$primary_config$overlay$dd_brake$lookback   # 20
OVL_DD_MULT  <- alpha_pkg$primary_config$overlay$dd_brake$mult_on    # 0.5
OVL_VOL_T    <- alpha_pkg$primary_config$overlay$volreg$target_vol_ann # 0.12
OVL_VOL_LB   <- alpha_pkg$primary_config$overlay$volreg$lookback     # 60
OVL_CAP_KR   <- 1.0   # KR long-only mandate (Optimizer confirmed): cap deduce-only
OVL_CAP_ALPHA <- 1.5  # Alpha spec cap (reference)

# Optimizer method spec (READ-ONLY)
OPT_METHOD   <- opt_pkg$method_selected             # "Ensemble_Top3"
OPT_MAX_W    <- opt_pkg$weight_cap_used             # 0.20
OPT_N_HOLD   <- length(opt_pkg$target_weights)      # 20
SNAPSHOT_TICKERS <- names(opt_pkg$target_weights)

cat(sprintf("  Alpha: %s | ICIR=%.3f | Harvey t=%.2f\n",
            alpha_pkg$hypothesis_title,
            alpha_pkg$diagnostics$icir, alpha_pkg$diagnostics$harvey_t_stat))
cat(sprintf("  Risk: %s | cond=%.2f | vol_red=%.1f%%\n",
            risk_pkg$selected_estimator$name,
            risk_pkg$selected_estimator$primary_cond,
            risk_pkg$overlay_impact$overall_vol_reduction_pct))
cat(sprintf("  Optimizer: %s | n_hold=%d | max_w=%.2f\n",
            OPT_METHOD, OPT_N_HOLD, OPT_MAX_W))
cat(sprintf("  Snapshot tickers (sig=2024-01-22): %d names\n",
            length(SNAPSHOT_TICKERS)))

# ──────────────────────────────────────────────────────────────────────────────
# 3. PIT Pre-flight + Lockbox boundaries
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 3] PIT pre-flight + Lockbox\n")
stopifnot(grepl("^PASS", alpha_pkg$pit_compliance$C9))
stopifnot(grepl("^PASS", alpha_pkg$pit_compliance$C2))
stopifnot(grepl("^PASS", alpha_pkg$pit_compliance$C13))
stopifnot(grepl("^PASS", alpha_pkg$pit_compliance$C15))
stopifnot(grepl("ENFORCED", alpha_pkg$pit_compliance$lockbox))
cat("  C2/C9/C13/C15: PASS | Lockbox: ENFORCED\n")

PRE_LB_END    <- as.Date("2024-01-22")
LOCKBOX_START <- as.Date("2024-01-23")

# ──────────────────────────────────────────────────────────────────────────────
# 4. Load alpha_scores.parquet (시계열 — 252 sig_dates × 3033 tickers)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 4] Loading alpha_scores.parquet (walk-forward signal time series)\n")

ALPHA_SCORES_PATH <- file.path(ARTIF_DIR, "alpha_scores.parquet")
OVERLAY_PATH      <- file.path(ARTIF_DIR, "overlay_signals.parquet")
stopifnot(file.exists(ALPHA_SCORES_PATH), file.exists(OVERLAY_PATH))

ASCORES <- as.data.table(read_parquet(ALPHA_SCORES_PATH))
ASCORES[, Date := as.Date(Date)]
setkey(ASCORES, Date, Ticker)

OVERLAY_DT <- as.data.table(read_parquet(OVERLAY_PATH))
OVERLAY_DT[, Date := as.Date(Date)]
setkey(OVERLAY_DT, Date)

cat(sprintf("  ALPHA_SCORES: %s rows | %d sig_dates | %d tickers | %s ~ %s\n",
            format(nrow(ASCORES), big.mark = ","),
            uniqueN(ASCORES$Date), uniqueN(ASCORES$Ticker),
            min(ASCORES$Date), max(ASCORES$Date)))
cat(sprintf("  OVERLAY: %d rows | brake_on pct=%.1f%% | mult mean=%.3f\n",
            nrow(OVERLAY_DT),
            mean(OVERLAY_DT$dd_brake_state == "ON", na.rm = TRUE) * 100,
            mean(OVERLAY_DT$overlay_mult, na.rm = TRUE)))

# ──────────────────────────────────────────────────────────────────────────────
# 5. Load RAWDATA + BM (한 번만, cached)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 5] Loading RAWDATA + BM (use_cache=TRUE)\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res_raw <- load_rawdata(use_cache = TRUE)
RAWDATA <- res_raw$RAWDATA
BM_DT   <- res_raw$BM_DT
rm(res_raw); gc(verbose = FALSE)

RAWDATA[, Date := as.Date(Date)]
BM_DT[,   Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
BM_DT   <- BM_DT[Date   >= ANALYSIS_START_DATE]

drop_cols <- intersect(c("Open", "High", "Low", "source", "Market"), names(RAWDATA))
if (length(drop_cols)) RAWDATA[, (drop_cols) := NULL]
setkey(RAWDATA, Ticker, Date)

cat(sprintf("  RAWDATA: %s rows | %d tickers | %s ~ %s\n",
            format(nrow(RAWDATA), big.mark = ","),
            uniqueN(RAWDATA$Ticker), min(RAWDATA$Date), max(RAWDATA$Date)))

# Liquidity filter (C10 t-1)
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE),
        by = Ticker]
RAWDATA[, TradVal := NULL]
LIQ_THRESHOLD <- 2e8

# ──────────────────────────────────────────────────────────────────────────────
# 6. Build per-sig_date FACTORS (Walk-Forward Top-N selection by score_eff)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 6] Walk-forward FACTORS construction (top-N by score_eff per sig_date)\n")

# Restrict ASCORES to sig_dates within RAWDATA range and >= SIGNAL_START_DATE
SIG_DATES_ALL <- sort(unique(ASCORES$Date))
SIG_DATES_ALL <- SIG_DATES_ALL[SIG_DATES_ALL >= as.Date("2003-01-01")]

cat(sprintf("  sig_dates_all: %d (%.0f → %.0f)\n",
            length(SIG_DATES_ALL),
            as.numeric(format(min(SIG_DATES_ALL), "%Y")),
            as.numeric(format(max(SIG_DATES_ALL), "%Y"))))

# For each sig_date: pick top-N by score_eff (after liquidity filter)
FACTORS_list <- vector("list", length(SIG_DATES_ALL))

for (i in seq_along(SIG_DATES_ALL)) {
  sd <- SIG_DATES_ALL[i]

  # Universe: liquidity filter on sig_date
  univ <- RAWDATA[Date == sd & !is.na(LIQ_20d) & LIQ_20d >= LIQ_THRESHOLD,
                  .(Ticker)]
  if (nrow(univ) < OPT_N_HOLD) next

  # Alpha scores for sig_date
  scores_sd <- ASCORES[Date == sd, .(Ticker, score_eff)]
  if (nrow(scores_sd) == 0) next

  # Filter to liquidity-passing universe
  scores_filt <- scores_sd[Ticker %in% univ$Ticker & !is.na(score_eff)]
  if (nrow(scores_filt) < OPT_N_HOLD) next

  setorder(scores_filt, -score_eff)
  top <- scores_filt[1:OPT_N_HOLD]

  FACTORS_list[[i]] <- data.table(
    Date   = sd,
    Ticker = top$Ticker,
    Score  = top$score_eff,
    N      = OPT_N_HOLD
  )
}

FACTORS <- rbindlist(FACTORS_list[!sapply(FACTORS_list, is.null)])
RAWDATA[, LIQ_20d := NULL]
gc(verbose = FALSE)

cat(sprintf("  FACTORS: %d rows | %d months | %s ~ %s | %.1f names/month\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            min(FACTORS$Date), max(FACTORS$Date),
            nrow(FACTORS) / uniqueN(FACTORS$Date)))

# ──────────────────────────────────────────────────────────────────────────────
# 7. Build overlay_mult lookup (per sig_date, post-multiplication scaler)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 7] Overlay multiplier lookup (PIT t-1 from overlay_signals.parquet)\n")

# overlay_mult on each sig_date is already PIT t-1 lagged (per overlay_pkg PIT C9)
# Two cap variants: KR mandate [0,1.0] vs Alpha spec [0,1.5]
OVERLAY_LKP <- OVERLAY_DT[, .(
  sig_date = Date,
  brake_on_state = dd_brake_state,
  vol_lag = vol_60d_lag,
  mult_kr   = pmin(pmax(overlay_mult, 0), OVL_CAP_KR),    # [0, 1.0] KR
  mult_alpha= pmin(pmax(overlay_mult, 0), OVL_CAP_ALPHA)  # [0, 1.5] Alpha spec
)]
setkey(OVERLAY_LKP, sig_date)

cat(sprintf("  overlay_mult mean (KR cap [0,1.0]): %.3f | (Alpha [0,1.5]): %.3f\n",
            mean(OVERLAY_LKP$mult_kr,    na.rm = TRUE),
            mean(OVERLAY_LKP$mult_alpha, na.rm = TRUE)))
cat(sprintf("  brake ON pct: %.1f%% (DD=%.0f%%/exit=%.0f%%/lb=%dd)\n",
            mean(OVERLAY_LKP$brake_on_state == "ON", na.rm = TRUE) * 100,
            OVL_DD_ENTRY * 100, OVL_DD_EXIT * 100, OVL_DD_LB))

# ──────────────────────────────────────────────────────────────────────────────
# 8. WALK-FORWARD BACKTEST — 3 scenarios
#    (A) Baseline_NoOverlay   : score_tilt weights, no overlay
#    (B) Overlay_KR_cap10     : score_tilt × mult_kr (KR mandate primary)
#    (C) Overlay_Alpha_cap15  : score_tilt × mult_alpha (Alpha spec)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 8] Walk-forward backtest — 3 scenarios via run_monthly_simulation\n")

# Common run helper. Overlay applied as cash-sleeve scaling:
#   Equity portion at sig_date t = mult(t-1)
#   Strategy_Ret_adj_t = mult × Strategy_Ret + (1-mult) × cash_ret(=0)
# This honors Optimizer's Option_A_post_multiplication (cash sleeve = 1 - equity_sum)

run_walkforward <- function(label, mult_col, use_overlay) {
  cat(sprintf("  [%s] use_overlay=%s\n", label, use_overlay))

  sim <- run_monthly_simulation(
    RAWDATA, BM_DT, FACTORS,
    n_holdings    = OPT_N_HOLD,
    weight_method = "score_tilt",        # HRP × score blend (Ensemble proxy)
    cov_method    = "ledoit_wolf",       # rolling Ledoit-Wolf (PIT-respect)
    commission    = 0.0015,
    buffer_zone   = list(keep_n = 30L, entry_n = 20L)
  )

  nav_dt <- copy(sim$DAILY_NAV_DT)
  nav_dt[, Date := as.Date(Date)]
  setorder(nav_dt, Date)

  if (use_overlay) {
    # Map each trading day to its applied sig_date
    sig_dates_ord <- sort(OVERLAY_LKP$sig_date)
    nav_dt[, sig_date_applied := sig_dates_ord[
      pmax(1L, findInterval(Date, sig_dates_ord))
    ]]
    nav_dt <- merge(nav_dt,
                    OVERLAY_LKP[, .(sig_date,
                                    eff_mult = get(mult_col))],
                    by.x = "sig_date_applied", by.y = "sig_date",
                    all.x = TRUE)
    nav_dt[is.na(eff_mult), eff_mult := 1.0]

    # Cash sleeve: equity_frac = eff_mult, cash_frac = 1 - eff_mult
    # Cap eff_mult at 1.0 (KR long-only, no leverage)
    nav_dt[, eff_mult := pmin(pmax(eff_mult, 0), 1.0)]
    nav_dt[, Strategy_Ret_adj := eff_mult * Strategy_Ret]
  } else {
    nav_dt[, eff_mult := 1.0]
    nav_dt[, Strategy_Ret_adj := Strategy_Ret]
  }

  setorder(nav_dt, Date)
  # Build adjusted NAV
  nav_dt[, NAV_adj := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Strategy_Ret_adj)]
  adj_xts <- xts(nav_dt$Strategy_Ret_adj, order.by = nav_dt$Date)

  list(label    = label,
       sim      = sim,
       nav_dt   = nav_dt,
       adj_xts  = adj_xts,
       use_overlay = use_overlay)
}

cat("  >>> Running Scenario A (Baseline No Overlay) ...\n")
res_A <- run_walkforward("A_Baseline_NoOverlay", NA, FALSE)

cat("  >>> Running Scenario B (Overlay KR cap=[0,1.0]) ...\n")
res_B <- run_walkforward("B_Overlay_KR_cap10", "mult_kr", TRUE)

cat("  >>> Running Scenario C (Overlay Alpha cap=[0,1.5]) ...\n")
res_C <- run_walkforward("C_Overlay_Alpha_cap15", "mult_alpha", TRUE)

# ──────────────────────────────────────────────────────────────────────────────
# 9. Performance metrics (Pre-LB / Lockbox / Stress / Regime)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 9] Performance metrics — Pre-LB / Lockbox / Stress / Regime\n")

compute_metrics <- function(res, label_prefix) {
  if (is.null(res)) return(NULL)
  xts_full <- res$adj_xts
  bm_xts   <- res$sim$bm_xts
  nav_dt   <- res$nav_dt

  prelb_xts <- xts_full[paste0("/", PRE_LB_END)]
  lb_xts    <- xts_full[paste0(LOCKBOX_START, "/")]

  monthly_full  <- tryCatch(as.numeric(apply.monthly(xts_full, Return.cumulative)),
                             error = function(e) NULL)
  monthly_prelb <- tryCatch(as.numeric(apply.monthly(prelb_xts, Return.cumulative)),
                             error = function(e) NULL)

  perf_full  <- summarise_perf(xts_full,  paste0(label_prefix, "_Full"))
  perf_prelb <- summarise_perf(prelb_xts, paste0(label_prefix, "_PreLB"))
  perf_lb    <- summarise_perf(lb_xts,    paste0(label_prefix, "_Lockbox"))
  perf_bm    <- summarise_perf(bm_xts,    "BM_KOSPI")

  to_ann <- tryCatch(
    calc_turnover(res$sim$PORTFOLIO_LOG, res$sim$DAILY_NAV_DT),
    error = function(e) NA_real_
  )

  # 8-period stress test
  stress_periods <- list(
    list(label = "2008_GFC",          start = "2007-10-01", end = "2009-03-31"),
    list(label = "2011_EuDebt",       start = "2011-06-01", end = "2012-01-31"),
    list(label = "2015_China",        start = "2015-06-01", end = "2016-01-31"),
    list(label = "2016_Brexit",       start = "2016-06-01", end = "2016-12-31"),
    list(label = "2018_Volmageddon",  start = "2018-01-01", end = "2018-12-31"),
    list(label = "2020_COVID",        start = "2020-01-01", end = "2020-06-30"),
    list(label = "2022_Inflation",    start = "2022-01-01", end = "2022-12-31"),
    list(label = "2022_KR_LiqCrisis", start = "2022-08-01", end = "2022-12-31")
  )
  merged <- merge(xts_full, bm_xts, join = "inner")
  stress_dt <- rbindlist(lapply(stress_periods, function(sp) {
    sub <- merged[paste0(sp$start, "/", sp$end)]
    if (nrow(sub) < 5) return(NULL)
    p_s  <- summarise_perf(sub[, 1], paste0("STR|", sp$label))
    p_b  <- summarise_perf(sub[, 2], paste0("BM|",  sp$label))
    p_s[, period := sp$label]
    p_s[, excess := CAGR - p_b$CAGR]
    p_s
  }))

  # Regime metrics (if cache available)
  regime_dt <- NULL
  reg_path <- file.path(CACHE_DIR, "unified_regime_signal.parquet")
  if (file.exists(reg_path)) {
    rd <- tryCatch({
      r <- as.data.table(read_parquet(reg_path))
      r[, Date := as.Date(Date)]; r
    }, error = function(e) NULL)

    if (!is.null(rd) && "Regime" %in% names(rd)) {
      mr <- merge(nav_dt[, .(Date, Strategy_Ret_adj)],
                  rd[, .(Date, Regime)],
                  by = "Date", all.x = TRUE)
      mr[is.na(Regime), Regime := "NORMAL"]
      regime_dt <- mr[, {
        r_xts <- xts(Strategy_Ret_adj, order.by = Date)
        p <- summarise_perf(r_xts, Regime[1])
        p[, n_days := .N]; p
      }, by = Regime]
    }
  }

  list(perf_full     = perf_full,
       perf_prelb    = perf_prelb,
       perf_lb       = perf_lb,
       perf_bm       = perf_bm,
       turnover      = to_ann,
       stress        = stress_dt,
       regime        = regime_dt,
       monthly_full  = monthly_full,
       monthly_prelb = monthly_prelb)
}

m_A <- compute_metrics(res_A, "A_Base")
m_B <- compute_metrics(res_B, "B_KR")
m_C <- compute_metrics(res_C, "C_Alpha")

print_perf <- function(m, label) {
  if (is.null(m)) { cat(sprintf("  %s: FAILED\n", label)); return() }
  cat(sprintf("\n  === %s ===\n", label))
  cat(sprintf("  Full:   SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | TO=%.0f%%\n",
              m$perf_full$Sharpe, m$perf_full$CAGR, m$perf_full$MDD, m$turnover))
  cat(sprintf("  PreLB:  SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n",
              m$perf_prelb$Sharpe, m$perf_prelb$CAGR, m$perf_prelb$MDD))
  if (!is.null(m$perf_lb) && !is.na(m$perf_lb$Sharpe)) {
    cat(sprintf("  LB(ref):SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n",
                m$perf_lb$Sharpe, m$perf_lb$CAGR, m$perf_lb$MDD))
  }
}

print_perf(m_A, "A: Baseline NoOverlay")
print_perf(m_B, "B: Overlay KR cap[0,1.0] (PRIMARY)")
print_perf(m_C, "C: Overlay Alpha cap[0,1.5]")

# ──────────────────────────────────────────────────────────────────────────────
# 10. Newey-West Harvey t-stat (Pre-LB)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 10] Newey-West Harvey t-stat (Pre-LB)\n")
compute_nw_t <- function(monthly_ret, lags = 4L) {
  if (is.null(monthly_ret) || length(monthly_ret) < 24) return(NA_real_)
  mu <- mean(monthly_ret, na.rm = TRUE)
  Tn <- length(monthly_ret)
  g0 <- mean((monthly_ret - mu)^2, na.rm = TRUE)
  nw_var <- g0
  for (j in seq_len(lags)) {
    w <- 1 - j / (lags + 1)
    gj <- mean((monthly_ret[-(1:j)] - mu) *
               (monthly_ret[-((Tn - j + 1):Tn)] - mu), na.rm = TRUE)
    nw_var <- nw_var + 2 * w * gj
  }
  if (nw_var <= 0) return(NA_real_)
  (mu / sqrt(nw_var / Tn)) * sqrt(12)
}

nw_A <- compute_nw_t(m_A$monthly_prelb)
nw_B <- compute_nw_t(m_B$monthly_prelb)
nw_C <- compute_nw_t(m_C$monthly_prelb)
cat(sprintf("  Pre-LB t_NW: A=%.2f | B=%.2f | C=%.2f (Harvey 3.0)\n", nw_A, nw_B, nw_C))

# ──────────────────────────────────────────────────────────────────────────────
# 11. CVaR (book level)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 11] CVaR measurement (book level)\n")
compute_cvar <- function(mret, conf = 0.95) {
  if (is.null(mret) || length(mret) < 12) return(NA_real_)
  q <- quantile(mret, 1 - conf, na.rm = TRUE)
  -mean(mret[mret <= q], na.rm = TRUE)
}
cvar_A <- compute_cvar(m_A$monthly_full)
cvar_B <- compute_cvar(m_B$monthly_full)
cvar_C <- compute_cvar(m_C$monthly_full)
cat(sprintf("  CVaR95 monthly: A=%.4f | B=%.4f | C=%.4f (cap %.4f)\n",
            cvar_A, cvar_B, cvar_C, risk_pkg$tail_risk$cvar_cap))

# ──────────────────────────────────────────────────────────────────────────────
# 12. MEGA_05 comparison (replacement vs integration)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 12] MEGA_05 comparison\n")
MEGA05_SR    <- 1.258
MEGA05_CAGR  <- 26.90
MEGA05_MDD   <- -36.95
PG2_TARGET   <- 1.80

iter1_sr_full   <- as.numeric(m_B$perf_full$Sharpe)
iter1_sr_prelb  <- as.numeric(m_B$perf_prelb$Sharpe)
iter1_cagr      <- as.numeric(m_B$perf_full$CAGR)
iter1_mdd       <- as.numeric(m_B$perf_full$MDD)

replacement_sr  <- iter1_sr_full
int_8020_sr     <- 0.80 * MEGA05_SR + 0.20 * iter1_sr_full
int_7030_sr     <- 0.70 * MEGA05_SR + 0.30 * iter1_sr_full
int_6040_sr     <- 0.60 * MEGA05_SR + 0.40 * iter1_sr_full

cat(sprintf("  MEGA_05 baseline: SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n",
            MEGA05_SR, MEGA05_CAGR, MEGA05_MDD))
cat(sprintf("  Iter1-B (KR cap10): SR=%.3f (Pre-LB %.3f) | CAGR=%.2f%% | MDD=%.2f%%\n",
            iter1_sr_full, iter1_sr_prelb, iter1_cagr, iter1_mdd))
cat(sprintf("  Replacement (100%% Iter1):  SR=%.3f\n", replacement_sr))
cat(sprintf("  Integration 80/20 / 70/30 / 60/40: SR~%.3f / %.3f / %.3f\n",
            int_8020_sr, int_7030_sr, int_6040_sr))

# ──────────────────────────────────────────────────────────────────────────────
# 13. Hash verification (END) — Pure function audit
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 13] Hash verification (end)\n")
HASH_END <- list(
  alpha_md5 = digest(readLines(PKG_ALPHA, warn = FALSE), algo = "md5"),
  risk_md5  = digest(readLines(PKG_RISK,  warn = FALSE), algo = "md5"),
  opt_md5   = digest(readLines(PKG_OPT,   warn = FALSE), algo = "md5")
)
audit_pass <- all(
  HASH_START$alpha_md5 == HASH_END$alpha_md5,
  HASH_START$risk_md5  == HASH_END$risk_md5,
  HASH_START$opt_md5   == HASH_END$opt_md5
)
cat(sprintf("  alpha: %s | risk: %s | opt: %s\n",
            ifelse(HASH_START$alpha_md5 == HASH_END$alpha_md5, "UNCHANGED", "CHANGED"),
            ifelse(HASH_START$risk_md5  == HASH_END$risk_md5,  "UNCHANGED", "CHANGED"),
            ifelse(HASH_START$opt_md5   == HASH_END$opt_md5,   "UNCHANGED", "CHANGED")))
if (!audit_pass) stop("[AUDIT FAIL] 3-package hashes changed!")
cat("  Pure function boundary: PASS\n")

# ──────────────────────────────────────────────────────────────────────────────
# 14. Charts (B = primary, A = baseline reference)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 14] Generating charts\n")

# B: primary scenario — equity_curve.png + annual_returns.png + drawdown.png
# Replace strategy_xts in sim with overlay-adjusted xts for chart fidelity
sim_B_charts <- res_B$sim
sim_B_charts$strategy_xts <- res_B$adj_xts
generate_charts(sim_B_charts, output_dir = OUT_DIR,
                strategy_name = "STR_1690 Crisis Overlay (KR cap10) WALK-FWD")

# A: baseline (subdirectory)
dir.create(file.path(OUT_DIR, "scenario_A_baseline"),
            showWarnings = FALSE, recursive = TRUE)
sim_A_charts <- res_A$sim
sim_A_charts$strategy_xts <- res_A$adj_xts
generate_charts(sim_A_charts,
                output_dir = file.path(OUT_DIR, "scenario_A_baseline"),
                strategy_name = "STR_1690 Baseline NoOverlay WALK-FWD")

# ──────────────────────────────────────────────────────────────────────────────
# 15. Save artifacts
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 15] Saving artifacts\n")
safe_num <- function(x) {
  v <- suppressWarnings(as.numeric(x))
  if (length(v) == 0 || is.na(v)) return(NA_real_)
  round(v, 4)
}

# 15a. performance_summary.json
perf_summary <- list(
  task_id      = WK_ID,
  strategy_id  = STR_ID,
  rebuild_note = "Opus 4.7 walk-forward rebuild — 이전 sonnet 4.6 결과 무효 (single-snapshot 22년 정적 적용)",
  prev_invalidated = TRUE,
  as_of_date   = as.character(Sys.Date()),
  n_sig_dates_walkforward = uniqueN(FACTORS$Date),
  walkforward_design = list(
    score_source         = "alpha_scores.parquet (252 sig_dates × 3033 tickers)",
    overlay_source       = "overlay_signals.parquet (252 monthly multipliers, t-1 lag)",
    selection            = "top-N by score_eff after liquidity filter (LIQ_20d >= 2e8)",
    weight_method        = "score_tilt (HRP × score blend, Ensemble_Top3 proxy)",
    cov_method           = "ledoit_wolf (rolling, PIT)",
    overlay_application  = "Option_A_post_multiplication (cash sleeve = 1 - mult)",
    n_holdings           = OPT_N_HOLD,
    weight_cap           = OPT_MAX_W,
    commission_one_way   = 0.0015
  ),
  pure_function_audit = list(
    alpha_md5_start = HASH_START$alpha_md5,
    risk_md5_start  = HASH_START$risk_md5,
    opt_md5_start   = HASH_START$opt_md5,
    alpha_md5_end   = HASH_END$alpha_md5,
    risk_md5_end    = HASH_END$risk_md5,
    opt_md5_end     = HASH_END$opt_md5,
    audit_pass      = audit_pass
  ),
  pit_compliance = list(C2 = "PASS", C9 = "PASS", C13 = "PASS",
                          C15 = "PASS", lockbox = "ENFORCED"),
  scenarios = list(
    A_baseline_no_overlay = list(
      sr_full     = safe_num(m_A$perf_full$Sharpe),
      sr_prelb    = safe_num(m_A$perf_prelb$Sharpe),
      sr_lb       = safe_num(m_A$perf_lb$Sharpe),
      cagr_full   = safe_num(m_A$perf_full$CAGR),
      mdd_full    = safe_num(m_A$perf_full$MDD),
      ann_vol     = safe_num(m_A$perf_full$AnnVol),
      sortino     = safe_num(m_A$perf_full$Sortino),
      calmar      = safe_num(m_A$perf_full$Calmar),
      win_rate    = safe_num(m_A$perf_full$WinRate),
      worst_month = safe_num(m_A$perf_full$WorstMonth),
      es99_m      = safe_num(m_A$perf_full$ES99_m),
      cvar95_m    = safe_num(cvar_A),
      turnover    = safe_num(m_A$turnover),
      nw_t_prelb  = safe_num(nw_A)
    ),
    B_overlay_kr_cap10 = list(
      sr_full     = safe_num(m_B$perf_full$Sharpe),
      sr_prelb    = safe_num(m_B$perf_prelb$Sharpe),
      sr_lb       = safe_num(m_B$perf_lb$Sharpe),
      cagr_full   = safe_num(m_B$perf_full$CAGR),
      mdd_full    = safe_num(m_B$perf_full$MDD),
      ann_vol     = safe_num(m_B$perf_full$AnnVol),
      sortino     = safe_num(m_B$perf_full$Sortino),
      calmar      = safe_num(m_B$perf_full$Calmar),
      win_rate    = safe_num(m_B$perf_full$WinRate),
      worst_month = safe_num(m_B$perf_full$WorstMonth),
      es99_m      = safe_num(m_B$perf_full$ES99_m),
      cvar95_m    = safe_num(cvar_B),
      turnover    = safe_num(m_B$turnover),
      nw_t_prelb  = safe_num(nw_B)
    ),
    C_overlay_alpha_cap15 = list(
      sr_full     = safe_num(m_C$perf_full$Sharpe),
      sr_prelb    = safe_num(m_C$perf_prelb$Sharpe),
      sr_lb       = safe_num(m_C$perf_lb$Sharpe),
      cagr_full   = safe_num(m_C$perf_full$CAGR),
      mdd_full    = safe_num(m_C$perf_full$MDD),
      ann_vol     = safe_num(m_C$perf_full$AnnVol),
      sortino     = safe_num(m_C$perf_full$Sortino),
      calmar      = safe_num(m_C$perf_full$Calmar),
      cvar95_m    = safe_num(cvar_C),
      turnover    = safe_num(m_C$turnover),
      nw_t_prelb  = safe_num(nw_C)
    )
  ),
  mega05_comparison = list(
    mega05_sr_full        = MEGA05_SR,
    mega05_cagr           = MEGA05_CAGR,
    mega05_mdd            = MEGA05_MDD,
    pg2_target_sr         = PG2_TARGET,
    replacement_sr        = safe_num(replacement_sr),
    integration_80_20_sr  = safe_num(int_8020_sr),
    integration_70_30_sr  = safe_num(int_7030_sr),
    integration_60_40_sr  = safe_num(int_6040_sr),
    replacement_milestone = replacement_sr  >= PG2_TARGET,
    int8020_milestone     = int_8020_sr     >= PG2_TARGET,
    int7030_milestone     = int_7030_sr     >= PG2_TARGET
  ),
  open_question_resolution = list(
    OQ1_cvar_cap = list(
      sleeve_level = risk_pkg$tail_risk$cvar_95_monthly,
      book_level_B = safe_num(cvar_B),
      cap          = risk_pkg$tail_risk$cvar_cap,
      verdict      = if (!is.na(cvar_B) && cvar_B <= risk_pkg$tail_risk$cvar_cap)
                      "PASS_book" else
                      sprintf("FAIL_book %.2fx", cvar_B / risk_pkg$tail_risk$cvar_cap)
    ),
    OQ2_beta = list(
      baseline = opt_pkg$beta_baseline,
      blended  = opt_pkg$beta_blended,
      target   = c(1.0, 1.05),
      note     = "Overlay reduces market beta (feature for crisis protection — AX-001 v2)"
    ),
    OQ3_cvar_breach_severity = list(
      sleeve_ratio = risk_pkg$tail_risk$cvar_95_monthly / risk_pkg$tail_risk$cvar_cap,
      book_ratio_B = safe_num(cvar_B) / risk_pkg$tail_risk$cvar_cap,
      action       = "REPORT (not relax) — Optimizer RF-O8 retained as documentation"
    ),
    OQ4_mult_cap = list(
      kr_mandate_cap   = OVL_CAP_KR,
      alpha_spec_cap   = OVL_CAP_ALPHA,
      primary_scenario = "B (KR cap [0,1.0]) — Optimizer confirmed deduce-only mandate",
      reference        = "C (Alpha [0,1.5]) — comparison only"
    )
  )
)

write(toJSON(perf_summary, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      file = file.path(OUT_DIR, "performance_summary.json"))
cat(sprintf("  performance_summary.json saved (%.0f bytes)\n",
            file.info(file.path(OUT_DIR, "performance_summary.json"))$size))

# 15b. daily_nav.csv
nav_save <- res_B$nav_dt[, .(Date, NAV = NAV_adj, Strategy_Ret = Strategy_Ret_adj,
                              eff_mult, BM_NAV = NAV * 0)]  # placeholder for BM
# Add BM
bm_xts <- res_B$sim$bm_xts
bm_dt_sub <- data.table(Date = index(bm_xts),
                          BM_Ret = as.numeric(coredata(bm_xts)))
bm_dt_sub <- bm_dt_sub[!is.na(BM_Ret)]
setorder(bm_dt_sub, Date)
bm_dt_sub[, BM_NAV := DEFAULT_INITIAL_CAPITAL * cumprod(1 + BM_Ret)]
nav_save[, BM_NAV := NULL]
nav_save <- merge(nav_save, bm_dt_sub[, .(Date, BM_NAV, BM_Ret)],
                  by = "Date", all.x = TRUE)
fwrite(nav_save, file.path(OUT_DIR, "daily_nav.csv"))
cat(sprintf("  daily_nav.csv saved (%d rows)\n", nrow(nav_save)))

# 15c. monthly_returns.parquet
mret_dt <- data.table(
  Date = index(apply.monthly(res_B$adj_xts, Return.cumulative)),
  Ret_B  = as.numeric(apply.monthly(res_B$adj_xts, Return.cumulative)),
  Ret_A  = as.numeric(apply.monthly(res_A$adj_xts, Return.cumulative)),
  Ret_C  = as.numeric(apply.monthly(res_C$adj_xts, Return.cumulative))
)
write_parquet(mret_dt, file.path(OUT_DIR, "monthly_returns.parquet"))
cat(sprintf("  monthly_returns.parquet saved (%d months)\n", nrow(mret_dt)))

# 15d. stress_test_results.json
stress_save <- list(
  A_baseline = if (!is.null(m_A$stress)) as.list(m_A$stress) else NULL,
  B_kr_cap10 = if (!is.null(m_B$stress)) as.list(m_B$stress) else NULL,
  C_alpha_cap15 = if (!is.null(m_C$stress)) as.list(m_C$stress) else NULL
)
write(toJSON(stress_save, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      file.path(OUT_DIR, "stress_test_results.json"))

# 15e. mega05_comparison.json
mega_save <- perf_summary$mega05_comparison
write(toJSON(mega_save, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      file.path(OUT_DIR, "mega05_comparison.json"))

# ──────────────────────────────────────────────────────────────────────────────
# 16. forge_package.json (REBUILD output for downstream Judge/Governor)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 16] Building forge_package.json (REBUILD)\n")

forge_pkg <- list(
  task_id        = WK_ID,
  strategy_id    = STR_ID,
  agent          = "forge_v6.1_opus_4_7_walkforward",
  rebuild_status = "OPUS_4_7_WALKFORWARD_REBUILD",
  prev_invalidated = TRUE,
  prev_invalidation_reason = "sonnet 4.6 result used single-snapshot weights (sig_date 2024-01-22) applied statically across 22 years — invalid, AX-002 violation",
  as_of_date     = as.character(Sys.Date()),
  inherits_from  = list(alpha = HASH_START$alpha_md5,
                          risk  = HASH_START$risk_md5,
                          opt   = HASH_START$opt_md5),
  pure_function_audit_pass = audit_pass,
  pit_compliance = list(C2 = "PASS", C9 = "PASS", C13 = "PASS",
                          C15 = "PASS", lockbox = "ENFORCED"),
  walkforward = list(
    n_sig_dates           = uniqueN(FACTORS$Date),
    sig_date_range        = c(as.character(min(FACTORS$Date)),
                                as.character(max(FACTORS$Date))),
    selection_method      = "top-20 by alpha_scores.score_eff (walk-forward)",
    weight_method         = "score_tilt (HRP × score, ledoit_wolf cov)",
    overlay_application   = "Option_A_post_multiplication via cash sleeve",
    overlay_cap_kr        = OVL_CAP_KR,
    overlay_cap_alpha     = OVL_CAP_ALPHA
  ),
  scenarios = perf_summary$scenarios,
  mega05_comparison = perf_summary$mega05_comparison,
  open_question_resolution = perf_summary$open_question_resolution,
  charts = list(
    equity_curve_png  = file.path(OUT_DIR, "equity_curve.png"),
    annual_returns_png = file.path(OUT_DIR, "annual_returns.png"),
    drawdown_png      = file.path(OUT_DIR, "drawdown.png")
  ),
  artifacts = list(
    performance_summary    = file.path(OUT_DIR, "performance_summary.json"),
    daily_nav              = file.path(OUT_DIR, "daily_nav.csv"),
    monthly_returns        = file.path(OUT_DIR, "monthly_returns.parquet"),
    stress_test            = file.path(OUT_DIR, "stress_test_results.json"),
    mega05_comparison_json = file.path(OUT_DIR, "mega05_comparison.json")
  ),
  status = list(
    boundary_pass         = audit_pass,
    forge_done            = TRUE,
    judge_ready           = TRUE,
    rebuild_invalidated_prev = TRUE
  )
)

forge_pkg_path <- file.path(WT_DIR, "forge_package.json")
write(toJSON(forge_pkg, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      forge_pkg_path)
cat(sprintf("  forge_package.json written: %s (%.0f bytes)\n",
            forge_pkg_path, file.info(forge_pkg_path)$size))

# ──────────────────────────────────────────────────────────────────────────────
# 17. Telegram brief (v4 ENFORCE — tg_agent_brief 단일 진입점)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[Step 17] Telegram brief (tg_agent_brief v4)\n")

tryCatch({
  source(file.path(FUNC_PATH, "telegram/telegram_notify.R"))

  # Section 1 (table): scenario performance
  scen_df <- data.frame(
    Scenario = c("A:Base", "B:KR_cap10", "C:Alpha_cap15"),
    SR_Full  = c(round(as.numeric(m_A$perf_full$Sharpe), 3),
                  round(as.numeric(m_B$perf_full$Sharpe), 3),
                  round(as.numeric(m_C$perf_full$Sharpe), 3)),
    SR_PreLB = c(round(as.numeric(m_A$perf_prelb$Sharpe), 3),
                  round(as.numeric(m_B$perf_prelb$Sharpe), 3),
                  round(as.numeric(m_C$perf_prelb$Sharpe), 3)),
    CAGR_pct = c(round(as.numeric(m_A$perf_full$CAGR), 2),
                  round(as.numeric(m_B$perf_full$CAGR), 2),
                  round(as.numeric(m_C$perf_full$CAGR), 2)),
    MDD_pct  = c(round(as.numeric(m_A$perf_full$MDD), 2),
                  round(as.numeric(m_B$perf_full$MDD), 2),
                  round(as.numeric(m_C$perf_full$MDD), 2)),
    stringsAsFactors = FALSE
  )

  # Section 2 (table): MEGA_05 comparison
  mega_df <- data.frame(
    Allocation = c("MEGA_05 100%", "Replacement", "Int 80/20", "Int 70/30", "Int 60/40"),
    SR         = c(MEGA05_SR,
                    round(replacement_sr, 3),
                    round(int_8020_sr, 3),
                    round(int_7030_sr, 3),
                    round(int_6040_sr, 3)),
    Milestone  = c("baseline",
                    ifelse(replacement_sr  >= PG2_TARGET, "PASS", "FAIL"),
                    ifelse(int_8020_sr     >= PG2_TARGET, "PASS", "FAIL"),
                    ifelse(int_7030_sr     >= PG2_TARGET, "PASS", "FAIL"),
                    ifelse(int_6040_sr     >= PG2_TARGET, "PASS", "FAIL")),
    stringsAsFactors = FALSE
  )

  # Section 3 (text): rebuild rationale
  rebuild_text <- sprintf(
    "이전 sonnet 4.6 결과 무효 처리. 단일 sig_date(2024-01-22) snapshot weights를 22년에 정적 적용한 invalid backtest. Opus 4.7 walk-forward 재구축으로 alpha_scores.parquet 252 sig_dates 시계열 + overlay_signals.parquet PIT t-1 multipliers 활용. n_sig_dates=%d, weight_method=score_tilt(HRP+score) ledoit_wolf cov. AX-002 process honesty 회복.",
    uniqueN(FACTORS$Date))

  # Section 4 (kv): 4 open questions resolution
  oq_kv <- list(
    "OQ1 CVaR (book B)" = sprintf("%.4f vs cap %.4f → %s",
                                     cvar_B, risk_pkg$tail_risk$cvar_cap,
                                     ifelse(!is.na(cvar_B) && cvar_B <= risk_pkg$tail_risk$cvar_cap,
                                            "PASS", sprintf("FAIL %.2fx", cvar_B / risk_pkg$tail_risk$cvar_cap))),
    "OQ2 Beta target" = sprintf("base %.3f / blend %.3f / target [1.0,1.05]",
                                  opt_pkg$beta_baseline, opt_pkg$beta_blended),
    "OQ3 CVaR severity" = sprintf("sleeve %.2fx / book %.2fx (REPORT not relax)",
                                     risk_pkg$tail_risk$cvar_95_monthly / risk_pkg$tail_risk$cvar_cap,
                                     cvar_B / risk_pkg$tail_risk$cvar_cap),
    "OQ4 mult cap" = sprintf("KR [0,%.1f] PRIMARY, Alpha [0,%.1f] reference",
                                OVL_CAP_KR, OVL_CAP_ALPHA),
    "Pure function audit" = ifelse(audit_pass, "PASS (3 md5 unchanged)", "FAIL"),
    "n_sig_dates walk-fwd" = uniqueN(FACTORS$Date),
    "Harvey t Pre-LB B" = sprintf("%.2f", nw_B)
  )

  # Section 5 (bullet): 8 stress periods (B scenario)
  stress_items <- if (!is.null(m_B$stress) && nrow(m_B$stress) > 0) {
    sprintf("%s: CAGR %.1f%% / MDD %.1f%% / excess %.1fpp",
              m_B$stress$period,
              m_B$stress$CAGR,
              m_B$stress$MDD,
              m_B$stress$excess)
  } else {
    c("Stress not computed", "—", "—")
  }

  sections <- list(
    list(heading = "Scenario Performance (3 walk-fwd)",
          type = "table", df = scen_df),
    list(heading = "MEGA_05 Comparison (PG2 target SR≥1.80)",
          type = "table", df = mega_df),
    list(heading = "REBUILD rationale (Opus 4.7 walk-forward)",
          type = "text", body = rebuild_text),
    list(heading = "4 Open Questions Resolution + Audit",
          type = "kv", kv = oq_kv),
    list(heading = "8 Stress Periods (Scenario B)",
          type = "bullet", items = stress_items)
  )

  brief_res <- tg_agent_brief(
    agent = "Forge",
    title = sprintf("STR_1690 REBUILD %s — Opus 4.7 walk-forward", WK_ID),
    sections = sections,
    as_of = as.character(Sys.Date()),
    footer = sprintf("REBUILD: prev_invalidated=TRUE, n_sig_dates=%d, audit=%s",
                       uniqueN(FACTORS$Date),
                       ifelse(audit_pass, "PASS", "FAIL"))
  )

  if (isTRUE(brief_res$ok) || is.null(brief_res$error)) {
    # Send charts (equity_curve, annual_returns, drawdown) via Single-Dispatch unlock
    tryCatch({
      eq_path  <- file.path(OUT_DIR, "equity_curve.png")
      ann_path <- file.path(OUT_DIR, "annual_returns.png")
      dd_path  <- file.path(OUT_DIR, "drawdown.png")
      if (file.exists(eq_path))  tg_send_photo(eq_path,
                                                 caption = sprintf("📈 STR_1690 REBUILD equity curve (B: KR cap10) — SR=%.3f / MDD=%.2f%%",
                                                                    as.numeric(m_B$perf_full$Sharpe),
                                                                    as.numeric(m_B$perf_full$MDD)))
      if (file.exists(ann_path)) tg_send_photo(ann_path,
                                                 caption = sprintf("📊 STR_1690 REBUILD annual returns — CAGR=%.2f%%",
                                                                    as.numeric(m_B$perf_full$CAGR)))
      if (file.exists(dd_path))  tg_send_photo(dd_path,
                                                 caption = "🔻 STR_1690 REBUILD drawdown chart")
    }, error = function(e) cat(sprintf("  [tg charts WARN] %s\n", e$message)))
  }
  cat("  Telegram brief dispatched.\n")
}, error = function(e) cat(sprintf("  [tg brief WARN] %s\n", e$message)))

# ──────────────────────────────────────────────────────────────────────────────
# 18. Final summary
# ──────────────────────────────────────────────────────────────────────────────
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
cat(sprintf("\n[DONE] Elapsed: %.1f min\n", elapsed))
cat(sprintf("FORGE_DONE — STR_1690 REBUILD opus, replacement_SR=%.3f, integration_SR=%.3f, MDD=%.2f%%, n_sig_dates_walkforward=%d, prev_invalidated=TRUE\n",
            replacement_sr, int_8020_sr,
            as.numeric(m_B$perf_full$MDD), uniqueN(FACTORS$Date)))

# BOUNDARY_PASS_END
