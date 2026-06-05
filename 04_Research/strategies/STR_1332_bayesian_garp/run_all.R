cat("=== STR_1332: Bayesian Shrinkage GARP ===\n")
## 핵심아이디어: Value(EP) + Quality(Piotroski,EarnStab) + Growth(RevGrowth) 교차.
## Bayesian Shrinkage: w_post = (1-lambda)*w_ICIR + lambda*w_EW.
## D01_IdioVol 25% fixed. Novy-Marx(2013), Ledoit & Wolf(2004).
## 자원 최적화: Factor DB + IC 1회 로드+캐싱 (L-534)

set.seed(1332); options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
STRATEGY_NAME   <- "Bayesian Shrinkage GARP"
STRATEGY_ID     <- "STR_1332"
STRATEGY_FAMILY <- "bayesian_garp"
QEPM_AUTO_COMMIT <- TRUE
LIQ_THRESHOLD   <- 2e8

# ── Infrastructure ──
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "02_Infrastructure"
  )
}

suppressPackageStartupMessages({ library(data.table); library(xts) })
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

tryCatch({
  source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
  la <- detect_lookahead(file.path(SCRIPT_DIR, "run_all.R"))
  if (!la$clean) stop("PIT violation")
  cat("[PIT] CLEAN\n")
}, error = function(e) {
  if (grepl("PIT violation", e$message)) stop(e$message)
  cat("[PIT] Warning:", e$message, "\n")
})

# ===========================================================================
# PHASE 1: Data
# ===========================================================================
cat("\n[Phase 1] Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
setkey(RAWDATA, Date, Ticker)

# ===========================================================================
# PHASE 2: Factor DB + IC 1회 로드 (L-534)
# ===========================================================================
cat("\n[Phase 2] Factor DB 1-pass load (6 factors)...\n")

GARP_FACTORS   <- c("V02_EP", "Q04_Piotroski_F", "Q07_Earnings_Stability", "GR01_Revenue_Growth")
DEFENSE_FACTOR <- "D01_IdioVol"
DEFENSE_WEIGHT <- 0.25
SIGNAL_WEIGHT  <- 0.75
GATE_FACTOR    <- "D47_CVaR_5pct"
ALL_FACTORS    <- c(GARP_FACTORS, DEFENSE_FACTOR, GATE_FACTOR)

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)

FDB_ALL <- rbindlist(lapply(fdb_files, function(fp) {
  dt <- as.data.table(arrow::read_parquet(fp,
    col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage")))
  dt <- dt[Factor_Name %in% ALL_FACTORS & Coverage == TRUE]
  ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  dt[, sig_ym := ym][, Coverage := NULL]
  dt
}))

# Direction alignment (IC sign 기반, C13)
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
ic_hist_dir <- tryCatch(.load_ic_history(), error = function(e) NULL)
if (!is.null(ic_hist_dir) && nrow(ic_hist_dir) > 0) {
  ic_dir <- ic_hist_dir[Factor_Name %in% ALL_FACTORS,
                         .(Mean_IC = mean(IC, na.rm = TRUE)), by = Factor_Name]
  ic_dir[, ic_sign := fifelse(Mean_IC >= 0, 1L, -1L)]
  FDB_ALL <- merge(FDB_ALL, ic_dir[, .(Factor_Name, ic_sign)], by = "Factor_Name", all.x = TRUE)
  FDB_ALL[is.na(ic_sign), ic_sign := 1L]
  FDB_ALL[, Z_Score_Aligned := Z_Score * ic_sign]
  FDB_ALL[, c("Z_Score", "ic_sign") := NULL]
} else {
  setnames(FDB_ALL, "Z_Score", "Z_Score_Aligned")
}

setkey(FDB_ALL, sig_ym, Factor_Name, Ticker)

# IC 1회 로드
IC_ALL <- as.data.table(arrow::read_parquet(file.path(fdb_dir, "factor_ic_monthly.parquet")))
IC_ALL[, Date := as.Date(Date)]
if ("Usable_Date" %in% names(IC_ALL)) IC_ALL[, Usable_Date := as.Date(Usable_Date)]
IC_ALL <- IC_ALL[Factor_Name %in% GARP_FACTORS]
setkey(IC_ALL, Factor_Name, Date)

SECTOR_MAP <- unique(RAWDATA[!is.na(Sector), .(Ticker, Date, Sector)])
setkey(SECTOR_MAP, Date, Ticker)

cat(sprintf("  FDB: %s rows | IC: %s rows\n",
            format(nrow(FDB_ALL), big.mark = ","), format(nrow(IC_ALL), big.mark = ",")))

# ===========================================================================
# PHASE 3: Bayesian scoring (memory-only loop)
# ===========================================================================
cat("\n[Phase 3] Bayesian scoring...\n")
sig_dates <- RAWDATA[, .(sig_date = max(Date)), by = .(YM = format(Date, "%Y-%m"))
                     ][order(YM), sig_date]

IC_LOOKBACK <- 36L; MIN_IC_MONTHS <- 12L
factor_list <- vector("list", length(sig_dates))
n_done <- 0L; n_skip <- 0L

for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  ym <- format(sd, "%Y%m")

  fdt <- FDB_ALL[sig_ym == ym]
  if (nrow(fdt) == 0) { n_skip <- n_skip + 1L; next }

  avail <- unique(fdt$Factor_Name)
  garp_avail <- intersect(GARP_FACTORS, avail)
  if (length(garp_avail) < 2) { n_skip <- n_skip + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Gate: D47_CVaR bottom 10% excluded
  if (GATE_FACTOR %in% names(fdt_wide)) {
    n_gate <- sum(!is.na(fdt_wide[[GATE_FACTOR]]))
    if (n_gate >= 30) {
      fdt_wide[, g_rank := frank(get(GATE_FACTOR), na.last = "keep") / n_gate]
      fdt_wide <- fdt_wide[is.na(g_rank) | g_rank >= 0.10]
      fdt_wide[, g_rank := NULL]
    }
  }

  # IC-based Bayesian weights
  cutoff <- sd - as.difftime(IC_LOOKBACK * 30.5, units = "days")
  if ("Usable_Date" %in% names(IC_ALL)) {
    ic_sub <- IC_ALL[Usable_Date <= sd & Date >= cutoff & Factor_Name %in% garp_avail]
  } else {
    ic_sub <- IC_ALL[Date < sd & Date >= cutoff & Factor_Name %in% garp_avail]
  }

  K <- length(garp_avail)
  if (nrow(ic_sub) > 0) {
    icir_dt <- ic_sub[, {
      n <- .N
      if (n < MIN_IC_MONTHS) list(ICIR = 0, hit = 0.5, n_m = n)
      else {
        m <- mean(IC, na.rm = TRUE); s <- sd(IC, na.rm = TRUE)
        list(ICIR = if (s > 0) m / s else 0, hit = mean(IC > 0, na.rm = TRUE), n_m = n)
      }
    }, by = Factor_Name]

    icir_dt[, w_ols := pmax(abs(ICIR), 0.01)]
    icir_dt[, w_ols := w_ols / sum(w_ols)]
    avg_hit <- mean(icir_dt$hit, na.rm = TRUE)
    avg_n   <- mean(icir_dt$n_m, na.rm = TRUE)
    lambda  <- max(0.2, min(0.9, 1 - (avg_hit - 0.45) * 2 - (avg_n - 36) / 200))
    icir_dt[, w_post := (1 - lambda) * w_ols + lambda * (1 / K)]
    icir_dt[, w_post := w_post / sum(w_post)]
  } else {
    icir_dt <- data.table(Factor_Name = garp_avail, w_post = 1 / K)
    lambda <- 1.0
  }

  # Compute score
  signal_score <- rep(0, nrow(fdt_wide))
  for (j in seq_len(nrow(icir_dt))) {
    fn <- icir_dt$Factor_Name[j]; wt <- icir_dt$w_post[j]
    if (fn %in% names(fdt_wide)) {
      vals <- fdt_wide[[fn]]; vals[is.na(vals)] <- 0
      signal_score <- signal_score + wt * vals
    }
  }

  # Defense anchor
  def_score <- if (DEFENSE_FACTOR %in% names(fdt_wide)) {
    v <- fdt_wide[[DEFENSE_FACTOR]]; v[is.na(v)] <- 0; v
  } else rep(0, nrow(fdt_wide))

  fdt_wide[, Score := SIGNAL_WEIGHT * signal_score + DEFENSE_WEIGHT * def_score]

  # Liquidity
  liq_dt <- RAWDATA[Date <= sd, .(AvgTV20 = mean(tail(Vol * Close, 20), na.rm = TRUE)), by = Ticker]
  fdt_wide <- merge(fdt_wide, liq_dt, by = "Ticker", all.x = TRUE)
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

  # Sector neutral
  sec <- SECTOR_MAP[.(sd, fdt_wide$Ticker), .(Ticker, Sector), nomatch = 0L]
  if (nrow(sec) > 0) {
    fdt_wide <- merge(fdt_wide, sec, by = "Ticker", all.x = TRUE)
    fdt_wide[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]
  }

  fdt_wide[, Date := sd]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
  if (n_done %% 50 == 0) cat(sprintf("  [%d/%d skip] %s — %d tickers, lambda=%.2f\n",
                                        n_done, n_skip, sd, nrow(fdt_wide), lambda))
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score); setkey(FACTORS, Date, Ticker)
rm(FDB_ALL, IC_ALL, SECTOR_MAP); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d months\n", format(nrow(FACTORS), big.mark = ","), uniqueN(FACTORS$Date)))

# ===========================================================================
# PHASE 4-5: Backtest (EW + VT)
# ===========================================================================
cat("\n[Phase 4] EW baseline...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim_ew <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
  n_holdings = 30L, weight_method = "equal", commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L))
perf_ew <- summarise_perf(sim_ew$strategy_xts, "EW")
perf_bm <- summarise_perf(sim_ew$bm_xts, "KOSPI")

cat("\n[Phase 5] VT overlay...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim_vt <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
  n_holdings = 30L, weight_method = "equal", commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L),
  vol_target = 0.20, vol_lookback = 60L)
perf_vt <- summarise_perf(sim_vt$strategy_xts, "VT")

# ===========================================================================
# PHASE 6: DD + MRS overlay
# ===========================================================================
cat("\n[Phase 6] DD + MRS overlay...\n")
raw_ret <- as.numeric(sim_vt$strategy_xts); raw_dates <- as.Date(index(sim_vt$strategy_xts)); n_f <- length(raw_ret)
nav_dd <- cumprod(1 + raw_ret); dd_pct <- 1 - nav_dd / cummax(nav_dd)
dd_lag <- c(0, dd_pct[-n_f])
dd_exp_lagged <- ifelse(dd_lag <= 0.05, 1, ifelse(dd_lag >= 0.35, 0.3, pmax(0.3, 1 - (dd_lag - 0.05) / 0.30 * 0.70)))
after_dd <- raw_ret * dd_exp_lagged

mrs_lag <- rep(0, n_f); mrs_exp <- rep(1, n_f)
MRS_LOW <- 15; MRS_HIGH <- 30; MRS_MIN <- 0.30
tryCatch({
  if (file.exists(file.path(REGIME_DIR, "regime_engine_option2.R"))) {
    source(file.path(REGIME_DIR, "regime_engine_option2.R")); regime_dt <- build_regime_option2(use_cache = TRUE)
  } else {
    source(file.path(REGIME_DIR, "regime_engine_v7.R")); regime_dt <- build_regime_v7(use_cache = TRUE)
  }
  rd <- data.table(Date = regime_dt$apply_start, MRS = regime_dt$MRS); setkey(rd, Date)
  dd2 <- rd[data.table(Date = raw_dates), roll = TRUE, on = "Date"]; dd2[is.na(MRS), MRS := 0]
  mrs_lag <- c(0, dd2$MRS[-n_f])
  mrs_exp <- ifelse(mrs_lag < MRS_LOW, 1, ifelse(mrs_lag >= MRS_HIGH, MRS_MIN,
    1 - (mrs_lag - MRS_LOW) / (MRS_HIGH - MRS_LOW) * (1 - MRS_MIN)))
}, error = function(e) cat("[MRS]", e$message, "\n"))

final_ret <- after_dd * mrs_exp
sim <- sim_vt; sim$strategy_xts <- xts(final_ret, order.by = raw_dates)
sim$DAILY_NAV_DT <- data.table(Date = raw_dates, NAV = cumprod(1 + final_ret) * 10000, Strategy_Ret = final_ret)

# ===========================================================================
# PHASE 7: Analysis + Hurdle
# ===========================================================================
cat("\n[Phase 7] Analysis + Hurdle...\n")
output_dir <- file.path(SCRIPT_DIR, "output"); dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
perf_final <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
cat(sprintf("  EW: SR=%.3f | VT: SR=%.3f | Final: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
            perf_ew$Sharpe, perf_vt$Sharpe, perf_final$Sharpe, perf_final$CAGR, perf_final$MDD))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_ew, perf_vt, perf_final, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))

RAWDATA <- copy(RAWDATA_ORIG)
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, FACTORS = FACTORS,
  strategy_name = STRATEGY_NAME, strategy_file = file.path(SCRIPT_DIR, "run_all.R"), output_dir = output_dir)

# Telegram + Handoff
tryCatch({
  hr <- tryCatch(jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json")),
                 error = function(e) list(grade = hurdle$grade, score = hurdle$score))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

tryCatch({
  validate_msg <- list(from = "forge2", to = "judge", cmd = "validate",
    strategy = STRATEGY_ID, family = STRATEGY_FAMILY,
    timestamp = format(Sys.time(), "%Y%m%d_%H%M%S"),
    grade = hurdle$grade, score = hurdle$score,
    metrics = list(cagr_ew = perf_ew$CAGR, sharpe_ew = perf_ew$Sharpe,
                   cagr_final = perf_final$CAGR, sharpe_final = perf_final$Sharpe, mdd_final = perf_final$MDD),
    output_dir = output_dir)
  judge_inbox <- file.path(PROJECT_ROOT, "qepm", "mailbox", "judge", "inbox")
  dir.create(judge_inbox, showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(validate_msg,
    file.path(judge_inbox, paste0("validate_", STRATEGY_ID, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".json")),
    auto_unbox = TRUE, pretty = TRUE)
}, error = function(e) cat("[Handoff]", e$message, "\n"))

cat(sprintf("\n=== STR_1332 Complete. Grade: %s | Score: %.1f ===\n", hurdle$grade, hurdle$score))
