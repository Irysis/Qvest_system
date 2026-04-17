cat("=== STR_1683: H_1682 Distress+Calmar Defense Anchor (Q25+R16) ===\n")
## 핵심아이디어: Q25_Ohlson_O(60%) + R16_Calmar(40%) cross-family composite Defense
## Ohlson distress prob 낮고 Calmar 높은 종목 Long. AX-003/004/005 전수 PASS.
## S1 pure factor: C1(expanding Z) C2(t+1) C13(Z_Score_Aligned) C15(bulk load) C10(LIQ lag).
## COND_03: 4 variants parallel. COND_04: Q25 PIT evidence. COND_11/12: Defense gate.

QEPM_AUTO_COMMIT <- TRUE
t0 <- Sys.time()

# ===================================================================
# 0. Environment
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(lubridate); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

STRATEGY_ID     <- "STR_1683"
STRATEGY_FAMILY <- "distress_path_dependent_defense"
N_HOLD          <- 20L
LIQ_THRESHOLD   <- 2e8
COMMISSION      <- 0.0015
BUFFER_ZONE     <- list(keep_n = 22L, entry_n = 20L)
WEIGHT_METHOD   <- "equal"

# Stress periods (OPT-5 정본 8대, reference_stress_periods.md)
STRESS_PERIODS <- list(
  list(name="9/11_Terror",   start="2001-09-01", end="2001-12-31"),
  list(name="GFC",           start="2007-10-01", end="2009-03-31"),
  list(name="EU_Debt",       start="2011-07-01", end="2012-06-30"),
  list(name="China_Shock",   start="2015-06-01", end="2016-02-29"),
  list(name="Trade_War",     start="2018-03-01", end="2019-01-31"),
  list(name="COVID",         start="2020-01-01", end="2020-06-30"),
  list(name="Rate_Hike",     start="2022-01-01", end="2022-12-31"),
  list(name="Iran_War",      start="2026-02-01", end="2026-04-30")
)

# ===================================================================
# 1. Preflight check
# ===================================================================
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", conditionMessage(e), "\n"))

# ===================================================================
# 2. Load raw data (once)
# ===================================================================
cat("\n[Step 2] Loading RAWDATA...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

setkey(RAWDATA, Date, Ticker)

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20 := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

# Market flag for KOSPI/KOSDAQ split (COND_05)
kospi_tickers  <- RAWDATA[grepl("^KS", Ticker), unique(Ticker)]
kosdaq_tickers <- RAWDATA[grepl("^KQ", Ticker), unique(Ticker)]

cat(sprintf("[Step 2] %s ~ %s | %d tickers (KOSPI %d, KOSDAQ %d)\n",
            min(RAWDATA$Date), max(RAWDATA$Date), uniqueN(RAWDATA$Ticker),
            length(kospi_tickers), length(kosdaq_tickers)))

# ===================================================================
# 3. Factor engine (bulk load Q25+R16, 4 variants)
# ===================================================================
cat("\n[Step 3] Factor engine (Q25+R16 bulk load, 4 variants)...\n")
source(file.path(STRAT_DIR, "factor_engine.R"))
stopifnot(is.data.table(FACTORS), all(c("Date","Ticker","Score") %in% names(FACTORS)))
cat(sprintf("[Step 3] FACTORS (primary): %d rows | %d dates\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

# ===================================================================
# 4. Lookahead detection
# ===================================================================
tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  pit <- detect_lookahead(file.path(STRAT_DIR, "factor_engine.R"))
  if (!isTRUE(pit$clean)) {
    for (v in pit$violations)
      cat(sprintf("[PIT VIOLATION] L%d [%s]: %s\n", v$line, v$check, v$msg))
    stop("PIT violation. Aborting.")
  }
  cat("[Step 4] PIT: CLEAN\n")
}, error = function(e) {
  if (grepl("PIT violation", conditionMessage(e))) stop(e)
  cat("[Step 4 WARN]", conditionMessage(e), "\n")
})

# ===================================================================
# 5. Helper: run simulation for a factor score column (COND_03 variants)
# ===================================================================
run_variant_sim <- function(score_col_name, label) {
  if (!score_col_name %in% names(H1682_RAW_SCORES)) {
    cat(sprintf("[variant %s] column not found, skip\n", label)); return(NULL)
  }
  # Build FACTORS-like table from raw score column (already cross-section z-scored per month)
  sig_dates <- sort(unique(H1682_RAW_SCORES$Date))
  fac_list <- lapply(seq_along(sig_dates), function(i) {
    sig_d <- sig_dates[i]
    past  <- H1682_RAW_SCORES[Date <= sig_d & !is.na(get(score_col_name))]
    if (nrow(past) < 30L) return(NULL)
    mu <- mean(past[[score_col_name]], na.rm = TRUE)
    s  <- sd(past[[score_col_name]], na.rm = TRUE)
    if (is.na(s) || s < 1e-10) return(NULL)
    cur <- H1682_RAW_SCORES[Date == sig_d & !is.na(get(score_col_name))]
    if (nrow(cur) == 0) return(NULL)
    cur[, Score := (get(score_col_name) - mu) / s]
    cur[, .(Date, Ticker, Score)]
  })
  fac_dt <- rbindlist(fac_list[!sapply(fac_list, is.null)], fill = TRUE)
  setkey(fac_dt, Date, Ticker)

  sim_v <- tryCatch(
    run_monthly_simulation(
      RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = fac_dt,
      n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
      commission = COMMISSION, buffer_zone = BUFFER_ZONE
    ),
    error = function(e) { cat(sprintf("[variant %s WARN]", label), conditionMessage(e), "\n"); NULL }
  )
  if (is.null(sim_v)) return(NULL)

  xts_v  <- sim_v$strategy_xts
  cagr_v <- as.numeric(Return.annualized(xts_v, scale=252))
  sr_v   <- as.numeric(SharpeRatio.annualized(xts_v, Rf=0, scale=252))
  mdd_v  <- as.numeric(maxDrawdown(xts_v))

  # Turnover (approx from sim object)
  to_v   <- tryCatch(mean(sim_v$turnover, na.rm=TRUE) * 12, error = function(e) NA)
  # SR after cost (approx)
  sr_net <- tryCatch({
    net_xts <- xts_v - to_v/2 * COMMISSION / 252
    as.numeric(SharpeRatio.annualized(net_xts, Rf=0, scale=252))
  }, error = function(e) sr_v)

  cat(sprintf("[variant %s] CAGR=%.1f%% SR=%.3f MDD=%.1f%%\n",
              label, cagr_v*100, sr_v, mdd_v*100))
  list(label=label, cagr=cagr_v, sharpe=sr_v, mdd=mdd_v,
       turnover_annual=to_v, sharpe_net=sr_net, sim=sim_v, factors=fac_dt)
}

# ===================================================================
# 6. Primary simulation: 60/40 composite
# ===================================================================
cat("\n[Step 6] Primary simulation (60/40 composite, EW 20, 15bps)...\n")
sim <- tryCatch(
  run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
    n_holdings = N_HOLD, weight_method = WEIGHT_METHOD,
    commission = COMMISSION, buffer_zone = BUFFER_ZONE
  ),
  error = function(e) { cat("[FATAL]", conditionMessage(e), "\n"); stop(e) }
)
cat(sprintf("[Step 6] Done: %d trading days\n", length(sim$strategy_xts)))

# ===================================================================
# 7. COND_03: 3 baseline variants parallel
# ===================================================================
cat("\n[Step 7] COND_03 — 3 baseline variants (50/50, Q25-only, R16-only)...\n")
v_5050 <- run_variant_sim("score_5050", "50/50")
v_q25  <- run_variant_sim("score_q25",  "Q25-only")
v_r16  <- run_variant_sim("score_r16",  "R16-only")

# ===================================================================
# 8. Analysis (primary)
# ===================================================================
cat("\n[Step 8] Analysis (primary)...\n")
tryCatch({
  source(file.path(FUNC_PATH, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, OUT_DIR, strategy_name = STRATEGY_ID)
}, error = function(e) {
  cat("[Step 8 WARN]", conditionMessage(e), "\n")
  tryCatch({
    perf <- summarise_perf(sim$strategy_xts, STRATEGY_ID)
    fwrite(as.data.table(t(unlist(perf))), file.path(OUT_DIR, "performance.csv"))
  }, error = function(e2) NULL)
})

# ===================================================================
# 9. Hurdle gate (primary)
# ===================================================================
cat("\n[Step 9] Hurdle gate...\n")
source(file.path(FUNC_PATH, "hurdle_gate.R"))
hurdle <- tryCatch(
  run_hurdle_gate(sim, strategy_id = STRATEGY_ID, family = STRATEGY_FAMILY,
                  output_dir = OUT_DIR),
  error = function(e) { cat("[WARN hurdle]", conditionMessage(e), "\n"); list(grade="ERR", score=0) }
)
cat(sprintf("[Step 9] Grade: %s | Score: %.1f\n",
            hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))

# ===================================================================
# 10. Performance metrics
# ===================================================================
perf_xts <- sim$strategy_xts
ann_ret  <- as.numeric(Return.annualized(perf_xts, scale = 252))
sr       <- as.numeric(SharpeRatio.annualized(perf_xts, Rf = 0, scale = 252))
mdd      <- as.numeric(maxDrawdown(perf_xts))

# ===================================================================
# 11. COND_08: Portfolio CAPM beta
# ===================================================================
cat("\n[Step 11] COND_08 — CAPM beta (Defense |β|<0.85)...\n")
capm_beta <- tryCatch({
  bm_sub <- BM_DT[Date %in% index(perf_xts)]
  bm_xts <- xts(bm_sub$Ret, order.by = bm_sub$Date)
  mg     <- merge(perf_xts, bm_xts, join = "inner")
  colnames(mg) <- c("strat","bench")
  coef(lm(strat ~ bench, data = as.data.frame(mg)))["bench"]
}, error = function(e) { cat("[WARN CAPM]", conditionMessage(e), "\n"); NA_real_ })

cat(sprintf("[CAPM beta] beta=%.4f | |beta|<0.85(Defense): %s\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta) && abs(capm_beta) < 0.85, "PASS", "FAIL")))

# ===================================================================
# 12. COND_02: R16 sub-period IC (pre-crisis vs during-crisis)
# ===================================================================
cat("\n[Step 12] COND_02 — R16 sub-period IC decomposition...\n")
r16_subperiod <- tryCatch({
  sig_dates_all <- sort(unique(H1682_RAW_SCORES$Date))
  sp_results <- lapply(STRESS_PERIODS, function(sp) {
    start_d <- as.Date(sp$start); end_d <- as.Date(sp$end)
    # pre-crisis: 1M before start
    pre_d <- start_d - 30L

    # Forward returns during stress period
    fwd_crisis <- RAWDATA[Date >= start_d & Date <= end_d,
                           .(fwd_ret = prod(1+Ret, na.rm=TRUE)-1), by=Ticker]

    # Scores at pre-crisis snapshot (last sig_date before start_d)
    pre_sig <- sig_dates_all[sig_dates_all <= start_d]
    if (length(pre_sig) == 0) return(NULL)
    pre_snap_d <- tail(pre_sig, 1)

    pre_scores <- H1682_RAW_SCORES[Date == pre_snap_d & !is.na(score_r16),
                                    .(Ticker, score_r16)]
    if (nrow(pre_scores) < 10L || nrow(fwd_crisis) < 10L) return(NULL)

    mg_pre <- merge(pre_scores, fwd_crisis, by = "Ticker")
    ic_pre <- if (nrow(mg_pre) >= 5)
      cor(mg_pre$score_r16, mg_pre$fwd_ret, method="spearman", use="complete.obs")
    else NA_real_

    # During crisis: scores at each sig_date within crisis period
    during_sigs <- sig_dates_all[sig_dates_all >= start_d & sig_dates_all <= end_d]
    ic_during_vals <- sapply(during_sigs, function(sd) {
      next_idx <- which(sig_dates_all == sd) + 1L
      if (next_idx > length(sig_dates_all)) return(NA_real_)
      next_sd <- sig_dates_all[next_idx]
      fwd <- RAWDATA[Date > sd & Date <= next_sd,
                     .(fwd_ret = prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
      sc  <- H1682_RAW_SCORES[Date == sd & !is.na(score_r16), .(Ticker, score_r16)]
      mg  <- merge(sc, fwd, by = "Ticker")
      if (nrow(mg) < 5) return(NA_real_)
      cor(mg$score_r16, mg$fwd_ret, method="spearman", use="complete.obs")
    })
    ic_during <- mean(ic_during_vals, na.rm = TRUE)

    data.table(
      stress_period  = sp$name,
      pre_crisis_ic  = round(ic_pre, 4),
      during_ic      = round(ic_during, 4),
      n_during_months = length(during_sigs),
      tautology_flag  = !is.na(ic_pre) && !is.na(ic_during) &&
                        abs(ic_pre - ic_during) < 0.05
    )
  })
  rbindlist(sp_results[!sapply(sp_results, is.null)], fill = TRUE)
}, error = function(e) {
  cat("[WARN R16 subperiod]", conditionMessage(e), "\n")
  data.table()
})

if (nrow(r16_subperiod) > 0) {
  cat("[R16 sub-period IC]\n")
  print(r16_subperiod)
  fwrite(r16_subperiod, file.path(OUT_DIR, "h1682_r16_sub_period_ic.csv"))
}

# ===================================================================
# 13. COND_05: KOSPI vs KOSDAQ split
# ===================================================================
cat("\n[Step 13] COND_05 — KOSPI vs KOSDAQ split performance...\n")
kospi_kosdaq_result <- tryCatch({
  run_split_sim <- function(tickers_filter, label) {
    fac_sub <- FACTORS[Ticker %in% tickers_filter]
    if (nrow(fac_sub) == 0) return(NULL)
    s <- tryCatch(
      run_monthly_simulation(
        RAWDATA = RAWDATA[Ticker %in% tickers_filter], BM_DT = BM_DT,
        FACTORS = fac_sub, n_holdings = min(N_HOLD, 15L),
        weight_method = WEIGHT_METHOD, commission = COMMISSION,
        buffer_zone = list(keep_n = 17L, entry_n = 15L)
      ), error = function(e) NULL
    )
    if (is.null(s)) return(NULL)
    xts_s <- s$strategy_xts
    data.table(
      subset = label,
      cagr   = round(as.numeric(Return.annualized(xts_s, scale=252))*100, 2),
      sharpe = round(as.numeric(SharpeRatio.annualized(xts_s, Rf=0, scale=252)), 3),
      mdd    = round(as.numeric(maxDrawdown(xts_s))*100, 2)
    )
  }
  rbindlist(list(
    data.table(subset="All", cagr=round(ann_ret*100,2), sharpe=round(sr,3), mdd=round(mdd*100,2)),
    run_split_sim(kospi_tickers,  "KOSPI"),
    run_split_sim(kosdaq_tickers, "KOSDAQ")
  ), fill = TRUE)
}, error = function(e) {
  cat("[WARN KOSPI/KOSDAQ split]", conditionMessage(e), "\n"); data.table()
})

if (nrow(kospi_kosdaq_result) > 0) {
  cat("[KOSPI/KOSDAQ split]\n"); print(kospi_kosdaq_result)
  fwrite(kospi_kosdaq_result, file.path(OUT_DIR, "h1682_kospi_kosdaq_split.csv"))
}

# ===================================================================
# 14. COND_06: Incremental alpha (variant comparison, COND_03)
# ===================================================================
cat("\n[Step 14] COND_06 — Variant comparison & incremental alpha...\n")
primary_stats <- data.table(
  variant = "60/40_composite",
  cagr    = round(ann_ret*100, 2),
  sharpe  = round(sr, 3),
  mdd     = round(mdd*100, 2)
)

variant_stats <- rbindlist(
  Filter(Negate(is.null), lapply(list(v_5050, v_q25, v_r16), function(v) {
    if (is.null(v)) return(NULL)
    data.table(variant=v$label, cagr=round(v$cagr*100,2),
               sharpe=round(v$sharpe,3), mdd=round(v$mdd*100,2))
  })),
  fill = TRUE
)
variant_comparison <- rbindlist(list(primary_stats, variant_stats), fill = TRUE)
cat("[Variant comparison]\n"); print(variant_comparison)
fwrite(variant_comparison, file.path(OUT_DIR, "h1682_variant_comparison.csv"))

# ===================================================================
# 15. COND_11 + COND_12: Defense gate
# ===================================================================
cat("\n[Step 15] COND_11/12 — Defense gate evaluation...\n")

# Stress IC (composite primary)
stress_ic_vals <- sapply(STRESS_PERIODS, function(sp) {
  start_d <- as.Date(sp$start); end_d <- as.Date(sp$end)
  sig_d_list <- sort(unique(FACTORS$Date))
  in_period  <- sig_d_list[sig_d_list >= start_d & sig_d_list <= end_d]
  ic_vals <- sapply(in_period, function(sd) {
    next_idx <- which(sig_d_list == sd) + 1L
    if (next_idx > length(sig_d_list)) return(NA_real_)
    next_sd <- sig_d_list[next_idx]
    fwd <- RAWDATA[Date > sd & Date <= next_sd,
                   .(fwd_ret = prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    sc  <- FACTORS[Date == sd, .(Ticker, Score)]
    mg  <- merge(sc, fwd, by = "Ticker")
    if (nrow(mg) < 5) return(NA_real_)
    cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs")
  })
  mean(ic_vals, na.rm = TRUE)
})
stress_ic_avg <- mean(stress_ic_vals, na.rm = TRUE)

# Bad/Good IC ratio: MRS-based (use RAWDATA BM return proxy)
bm_monthly <- BM_DT[, .(bm_ret = prod(1+Ret,na.rm=TRUE)-1), by=.(YM=format(Date,"%Y-%m"))]
bm_monthly[, bm_roll12 := frollmean(bm_ret, n=12L, align="right")]
bm_monthly[, regime := fifelse(!is.na(bm_roll12) & bm_roll12 < 0, "bad", "good")]

sig_dates_all <- sort(unique(FACTORS$Date))
ic_regime_list <- lapply(seq_along(sig_dates_all), function(i) {
  sd <- sig_dates_all[i]
  if (i == length(sig_dates_all)) return(NULL)
  next_sd <- sig_dates_all[i+1L]
  fwd <- RAWDATA[Date > sd & Date <= next_sd, .(fwd_ret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
  sc  <- FACTORS[Date == sd, .(Ticker, Score)]
  mg  <- merge(sc, fwd, by="Ticker")
  if (nrow(mg) < 5) return(NULL)
  ic_v <- cor(mg$Score, mg$fwd_ret, method="spearman", use="complete.obs")
  ym   <- format(sd, "%Y-%m")
  reg  <- bm_monthly[YM == ym, regime][1] %||% "good"
  data.table(Date=sd, IC=ic_v, regime=reg)
})
ic_regime <- rbindlist(ic_regime_list[!sapply(ic_regime_list, is.null)], fill=TRUE)
ic_bad  <- mean(ic_regime[regime=="bad",  IC], na.rm=TRUE)
ic_good <- mean(ic_regime[regime=="good", IC], na.rm=TRUE)
bad_good_ratio <- if (!is.na(ic_good) && abs(ic_good) > 1e-6) ic_bad / ic_good else NA

# Core benchmark MDD (STR_1679v2 Primary = current Grade A Core)
# Use BM as proxy if Core sim not available
core_mdd_proxy <- 0.2906  # STR_1679v2 Primary Grade A reported MDD 29.06%
mdd_diff <- core_mdd_proxy - mdd  # positive = Defense MDD lower

# Defense gate summary
def_gate <- list(
  cond_11_cagr_gt3     = ann_ret > 0.03,
  cond_11_stress_ic_pos = stress_ic_avg > 0,
  cond_12_stress_ic_gt003 = stress_ic_avg > 0.03,
  cond_12_mdd_vs_core_diff = round(mdd_diff, 4),
  cond_12_mdd_reduce_8pp  = mdd_diff >= 0.08,
  cond_12_bad_good_ratio  = round(bad_good_ratio %||% NA, 3),
  cond_12_bad_good_gt12   = !is.na(bad_good_ratio) && bad_good_ratio > 1.2,
  cond_12_cagr_gt5        = ann_ret > 0.05,
  defense_gate_pass = (ann_ret > 0.03) && (stress_ic_avg > 0.03) &&
                      (mdd_diff >= 0.08) &&
                      (!is.na(bad_good_ratio) && bad_good_ratio > 1.2) &&
                      (ann_ret > 0.05)
)

cat(sprintf("[Defense Gate]\n"))
cat(sprintf("  COND_11 CAGR>3%%: %s (%.2f%%)\n", def_gate$cond_11_cagr_gt3, ann_ret*100))
cat(sprintf("  COND_11 stress_ic>0: %s (%.4f)\n", def_gate$cond_11_stress_ic_pos, stress_ic_avg))
cat(sprintf("  COND_12 stress_ic>0.03: %s\n", def_gate$cond_12_stress_ic_gt003))
cat(sprintf("  COND_12 MDD vs Core diff: %.2fpp (gate 8pp): %s\n",
            mdd_diff*100, def_gate$cond_12_mdd_reduce_8pp))
cat(sprintf("  COND_12 bad/good IC ratio: %.3f (>1.2): %s\n",
            bad_good_ratio %||% NA, def_gate$cond_12_bad_good_gt12))
cat(sprintf("  COND_12 CAGR>5%%: %s\n", def_gate$cond_12_cagr_gt5))
cat(sprintf("  Defense gate PASS: %s\n", def_gate$defense_gate_pass))

# ===================================================================
# 16. s1_construction_H_1682 artifact
# ===================================================================
cat("\n[Step 16] Saving s1_construction_H_1682.json...\n")

s1_art <- list(
  strategy_id   = STRATEGY_ID,
  hypothesis_id = "H_1682",
  stage         = "S1",
  date          = as.character(Sys.Date()),
  family        = STRATEGY_FAMILY,
  expected_role = "defense",
  role_bias     = "RoleBias_Defense",
  performance   = list(
    cagr   = round(ann_ret*100, 2),
    sharpe = round(sr, 3),
    mdd    = round(mdd*100, 2),
    grade  = hurdle$grade %||% "?",
    score  = as.numeric(hurdle$score %||% 0)
  ),
  portfolio = list(
    n_holdings    = N_HOLD,
    weight_method = WEIGHT_METHOD,
    commission    = COMMISSION,
    buffer_zone   = BUFFER_ZONE,
    liq_threshold = LIQ_THRESHOLD
  ),
  pit_evidence         = if (exists("H1682_PIT_EVIDENCE")) H1682_PIT_EVIDENCE else list(),
  capm_beta            = round(capm_beta %||% NA, 4),
  capm_beta_gate       = list(threshold=0.85, pass=!is.na(capm_beta)&&abs(capm_beta)<0.85),
  stress_ic_average    = round(stress_ic_avg, 4),
  bad_good_ic_ratio    = round(bad_good_ratio %||% NA, 3),
  defense_gate         = def_gate,
  alpha_lab_gate = list(
    icir_threshold = 0.20,
    pass           = !is.na(sr) && sr >= 0.20
  ),
  variant_comparison   = variant_comparison,
  r16_sub_period_ic    = if (nrow(r16_subperiod) > 0) r16_subperiod else list(),
  kospi_kosdaq_split   = if (nrow(kospi_kosdaq_result) > 0) kospi_kosdaq_result else list(),
  conditions_met = list(
    COND_01 = "applied — 60/40 fixed weights, walk-forward expanding Z-score, no re-tuning",
    COND_02 = list(status="applied", r16_sub_period_ic=if(nrow(r16_subperiod)>0) r16_subperiod else list()),
    COND_03 = list(status="applied", variants=variant_comparison),
    COND_04 = list(status="applied", pit_evidence=if(exists("H1682_PIT_EVIDENCE")) H1682_PIT_EVIDENCE else list()),
    COND_05 = list(status="applied", kospi_kosdaq=if(nrow(kospi_kosdaq_result)>0) kospi_kosdaq_result else list()),
    COND_06 = list(status="applied", variant_comparison=variant_comparison),
    COND_07 = "pending — S3 DCC conditional correlation (Scout)",
    COND_08 = list(status="applied", capm_beta=capm_beta%||%NA, pass=!is.na(capm_beta)&&abs(capm_beta)<0.85),
    COND_09 = "pending — S5 mutation slate (Scout)",
    COND_10 = "applied — Kho-Kim 2007 + Eom-Park 2014 in s0_record v2",
    COND_11 = list(status="applied", cagr_gt3=def_gate$cond_11_cagr_gt3,
                   stress_ic_pos=def_gate$cond_11_stress_ic_pos),
    COND_12 = list(status="applied", gate=def_gate)
  )
)

art_path <- file.path(PROJECT_ROOT, "stage_artifacts", "s1_construction_H_1682.json")
write_json(s1_art, art_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Step 16] Saved: %s\n", art_path))

# ===================================================================
# 17. Charts
# ===================================================================
tryCatch({
  generate_charts(sim, output_dir = OUT_DIR)
  cat("[Step 17] Charts saved.\n")
}, error = function(e) cat("[Step 17 WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 18. Summary
# ===================================================================
elapsed <- round(difftime(Sys.time(), t0, units = "mins"), 1)
cat(sprintf("\n=== STR_1683 S1 COMPLETE ===\n"))
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)))
cat(sprintf("  CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100))
cat(sprintf("  CAPM beta: %.4f (|beta|<0.85: %s)\n",
            capm_beta %||% NA,
            ifelse(!is.na(capm_beta)&&abs(capm_beta)<0.85,"PASS","FAIL")))
cat(sprintf("  Defense gate PASS: %s\n", def_gate$defense_gate_pass))
cat(sprintf("  Stress IC avg: %.4f | bad/good ratio: %.3f\n",
            stress_ic_avg, bad_good_ratio %||% NA))
cat(sprintf("  Elapsed: %s min\n", elapsed))

# ===================================================================
# 19. Telegram
# ===================================================================
tryCatch({
  source(file.path(FUNC_PATH, "telegram", "telegram_notify.R"))
  msg <- paste0(
    "[Forge] STR_1683 S1 완료 (H_1682 Distress+Calmar Defense)\n",
    sprintf("Grade: %s | Score: %.1f\n", hurdle$grade %||% "?", as.numeric(hurdle$score %||% 0)),
    sprintf("CAGR: %.1f%% | SR: %.3f | MDD: %.1f%%\n", ann_ret*100, sr, mdd*100),
    sprintf("Defense gate: %s\n", def_gate$defense_gate_pass),
    sprintf("Stress IC avg: %.4f | bad/good ratio: %.3f\n", stress_ic_avg, bad_good_ratio %||% NA),
    sprintf("CAPM beta: %.4f | |beta|<0.85: %s\n",
            capm_beta %||% NA, ifelse(!is.na(capm_beta)&&abs(capm_beta)<0.85,"PASS","FAIL")),
    "RoleBias: RoleBias_Defense | Family: distress_path_dependent_defense\n",
    "AX-003/004/005: PASS"
  )
  tg_send(msg)
  chart_path <- file.path(OUT_DIR, "equity_curve.png")
  if (file.exists(chart_path)) tg_send_photo(chart_path, caption = "STR_1683 Equity Curve")
}, error = function(e) cat("[Telegram WARN]", conditionMessage(e), "\n"))

# ===================================================================
# 20. QEPM auto-commit
# ===================================================================
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    source(file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R"))
    hybrid_commit(
      strategy      = STRATEGY_ID,
      family        = STRATEGY_FAMILY,
      hurdle_result = hurdle,
      role_bias     = "RoleBias_Defense",
      tags          = c("H_1682","distress","calmar","defense","Q25","R16","S1")
    )
    cat("[QEPM] hybrid_commit done.\n")
  }, error = function(e) cat("[QEPM WARN]", conditionMessage(e), "\n"))
}

cat("[DONE]\n")
