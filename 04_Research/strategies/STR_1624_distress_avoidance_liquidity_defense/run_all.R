cat("=== STR_1624: Distress Avoidance Liquidity Defense (Altman-Z + fPBR + BidAsk) ===\n")
## 핵심아이디어: Q24_Altman_Z(40%) + V05_fPBR(35%) + L04_Bid_Ask_Proxy(25%)
## 재무부실 회피 + 저밸류에이션 + 유동성 안전망 = Defense 3축 복합.
## S1 순수 팩터 신호. DD/VT/Regime overlay 없음.
## 학술근거: Altman (1968) distress prediction + Fama-French (1992) value + Amihud (2002) liquidity.

set.seed(20240408)
t0 <- Sys.time()

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(STRAT_DIR, "stage_artifacts"), showWarnings = FALSE)

source(file.path(FUNC_PATH, "config.R"))
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID   <- "STR_1624"
STRATEGY_FAM  <- "defense"
N_HOLD        <- 30L
LIQ_THRESHOLD <- 2e8
COMMISSION    <- 0.0015
MAX21D_EXCL   <- 0.80
W_Q24 <- 0.40; W_V05 <- 0.35; W_L04 <- 0.25
TARGET_FACTORS <- c("Q24_Altman_Z", "V05_fPBR", "L04_Bid_Ask_Proxy")

source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
preflight_check(STRATEGY_ID, family = STRATEGY_FAM)

cat("\n[Step 2] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)

RAWDATA[, Date := as.Date(Date)]; BM_DT[, Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]; BM_DT <- BM_DT[Date >= ANALYSIS_START_DATE]

drop_cols <- intersect(c("Open","High","Low","source","Market"), names(RAWDATA))
if (length(drop_cols) > 0) RAWDATA[, (drop_cols) := NULL]

setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, 20L, align="right", na.rm=TRUE), by = Ticker]
RAWDATA[, LIQ_20d := shift(LIQ_20d, 1L, type = "lag"), by = Ticker]  # C10: t-1 lag
RAWDATA[, TradVal := NULL]

RAWDATA[, Ret_abs    := abs(Ret)]
RAWDATA[, MAX21d_raw := Reduce(pmax, lapply(0:20, function(k) shift(Ret_abs, k, type="lag", fill=NA))), by = Ticker]
RAWDATA[, MAX21d     := shift(MAX21d_raw, 1L, type="lag"), by = Ticker]
RAWDATA[, c("Ret_abs","MAX21d_raw") := NULL]

RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setorder(sig_dates_dt, sig_date)
SIG_DATES <- sig_dates_dt[sig_date >= SIGNAL_START_DATE, sig_date]

SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close), .(Date, Ticker, Close, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d","MAX21d","YM") := NULL]
setkey(RAWDATA, Date, Ticker); gc(verbose = FALSE)

cat(sprintf("[Step 2] %s rows | %d tickers | %d signal dates\n",
            format(nrow(RAWDATA), big.mark=","), uniqueN(RAWDATA$Ticker), length(SIG_DATES)))

# Bulk preload (OPT-1 compliant: lapply, not for-loop)
cat("\n[Step 3] Bulk preloading factor DB...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

FDB_ALL <- rbindlist(lapply(SIG_DATES, function(sd_i) {
  fdb <- tryCatch(load_month_factors(sd_i, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) == 0L) return(NULL)
  fdb_sub <- fdb[Factor_Name %in% TARGET_FACTORS]
  if (nrow(fdb_sub) == 0L) return(NULL)
  fdb_sub[, sig_date := sd_i]; fdb_sub
}), fill = TRUE)

if (nrow(FDB_ALL) == 0L) stop("[ABORT] No factor data loaded.")
setkey(FDB_ALL, sig_date, Ticker, Factor_Name)
cat(sprintf("[Step 3] FDB_ALL: %s rows | %d dates\n",
            format(nrow(FDB_ALL), big.mark=","), uniqueN(FDB_ALL$sig_date)))
gc(verbose = FALSE)

cat("\n[Step 4] Building composite scores...\n")

z_safe <- function(x) {
  n <- sum(!is.na(x)); if (n < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

FACTORS <- rbindlist(lapply(seq_along(SIG_DATES), function(i) {
  sd_i <- SIG_DATES[i]

  univ <- SIG_SNAP[Date == sd_i & !is.na(LIQ_20d) & LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < N_HOLD) return(NULL)
  q80 <- quantile(univ$MAX21d, MAX21D_EXCL, na.rm = TRUE)
  univ <- univ[is.na(MAX21d) | MAX21d <= q80]
  if (nrow(univ) < N_HOLD) return(NULL)

  fdb_i <- FDB_ALL[sig_date == sd_i & Ticker %in% univ$Ticker]
  if (nrow(fdb_i) == 0L) return(NULL)

  fdb_wide <- dcast(fdb_i, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  fdb_wide <- merge(fdb_wide, univ[, .(Ticker)], by = "Ticker")

  miss <- setdiff(TARGET_FACTORS, names(fdb_wide))
  if (length(miss) > 0L) fdb_wide[, (miss) := NA_real_]

  # C13: Z_Score_Aligned 직접 사용, 방향 반전 금지
  fdb_wide[, z_Q24 := z_safe(Q24_Altman_Z)]
  fdb_wide[, z_V05 := z_safe(V05_fPBR)]
  fdb_wide[, z_L04 := z_safe(L04_Bid_Ask_Proxy)]

  # 유효 팩터 수에 따른 fallback
  fdb_wide[, n_valid := (!is.na(z_Q24)) + (!is.na(z_V05)) + (!is.na(z_L04))]
  fdb_wide[, Composite := {
    w_q <- fifelse(!is.na(z_Q24), W_Q24, 0)
    w_v <- fifelse(!is.na(z_V05), W_V05, 0)
    w_l <- fifelse(!is.na(z_L04), W_L04, 0)
    w_sum <- w_q + w_v + w_l
    fifelse(w_sum > 0,
      (fifelse(!is.na(z_Q24), w_q * z_Q24, 0) +
       fifelse(!is.na(z_V05), w_v * z_V05, 0) +
       fifelse(!is.na(z_L04), w_l * z_L04, 0)) / w_sum,
      NA_real_)
  }]

  valid <- fdb_wide[!is.na(Composite) & n_valid >= 2L]
  if (nrow(valid) < N_HOLD) return(NULL)
  setorder(valid, -Composite)
  data.table(Date = sd_i, Ticker = head(valid$Ticker, N_HOLD), Score = head(valid$Composite, N_HOLD))
}))

rm(FDB_ALL, SIG_SNAP); gc(verbose = FALSE)
cat(sprintf("[Step 4] FACTORS: %d rows | %d months | %s ~ %s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$Date), max(FACTORS$Date)))
if (nrow(FACTORS) == 0L) stop("[ABORT] No factor signals generated.")

cat("\n[Step 5] Running S1 backtest (EW, no overlay)...\n")
sim <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS,
  n_holdings    = N_HOLD,
  weight_method = "equal",
  commission    = COMMISSION,
  buffer_zone   = list(keep_n = 35L, entry_n = 30L)
)

perf_strat <- summarise_perf(sim$strategy_xts, "STR_1624")
perf_bm    <- summarise_perf(sim$bm_xts, "KOSPI200")
to_ann     <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)

cat("\n================================================================\n")
cat("   STR_1624 Distress Avoidance Liquidity Defense — S1 결과\n")
cat("================================================================\n")
print(rbind(perf_strat, perf_bm))
cat(sprintf("  Turnover (ann.): %.1f%%\n", to_ann))

strat_ret <- as.numeric(sim$strategy_xts); bm_ret <- as.numeric(sim$bm_xts)
vi <- !is.na(strat_ret) & !is.na(bm_ret)
beta_full <- if (sum(vi) > 12L) coef(lm(strat_ret[vi] ~ bm_ret[vi]))[2] else NA_real_
cat(sprintf("\n  Beta: %s\n", ifelse(is.na(beta_full),"NA",sprintf("%.3f",beta_full))))

generate_charts(sim, output_dir = OUT_DIR, strategy_name = "STR_1624 Distress Avoidance Defense")

source(file.path(FUNC_PATH, "hurdle_gate.R"))
tryCatch(run_hurdle_gate(sim, STRATEGY_ID, stage = "S1"),
         error = function(e) cat(sprintf("  [WARN] hurdle: %s\n", conditionMessage(e))))

# Defense conditional
stress_tbl <- stress_test(sim$strategy_xts, sim$bm_xts); print(stress_tbl)
both_idx   <- index(sim$strategy_xts)
excess_vec <- as.numeric(sim$strategy_xts) - as.numeric(sim$bm_xts)
bad_dates  <- (both_idx >= "2007-10-01" & both_idx <= "2009-03-31") |
              (both_idx >= "2020-01-01" & both_idx <= "2020-06-30") |
              (both_idx >= "2022-01-01" & both_idx <= "2022-12-31")
bad_ex  <- excess_vec[bad_dates  & !is.na(excess_vec)]
norm_ex <- excess_vec[!bad_dates & !is.na(excess_vec)]
bad_ic_ratio <- if (length(bad_ex) >= 3L && length(norm_ex) >= 3L)
  (mean(bad_ex)/(sd(bad_ex)+1e-8)) / (mean(norm_ex)/(sd(norm_ex)+1e-8)) else NA_real_
cat(sprintf("  bad_IC_ratio: %s\n", ifelse(is.na(bad_ic_ratio),"NA",sprintf("%.3f",bad_ic_ratio))))

fwrite(FACTORS, file.path(OUT_DIR, "factors.csv"))
fwrite(sim$DAILY_NAV_DT, file.path(OUT_DIR, "daily_nav.csv"))

perf_json <- list(
  strategy = STRATEGY_ID, stage = "S1",
  description = "Q24_Altman_Z(40%) + V05_fPBR(35%) + L04_Bid_Ask_Proxy(25%) defense",
  factors_used = TARGET_FACTORS,
  factor_weights = list(Q24_Altman_Z = W_Q24, V05_fPBR = W_V05, L04_Bid_Ask_Proxy = W_L04),
  expected_role = "defense",
  perf_strategy = as.list(perf_strat), perf_bm = as.list(perf_bm),
  beta_full = beta_full, turnover_ann = to_ann, bad_ic_ratio = bad_ic_ratio,
  n_signal_months = uniqueN(FACTORS$Date),
  run_time_secs = as.numeric(difftime(Sys.time(), t0, units="secs"))
)
write_json(perf_json, file.path(OUT_DIR, "performance.json"), pretty=TRUE, auto_unbox=TRUE)

s1_art <- list(
  strategy_id = STRATEGY_ID, stage = "S1", factors = TARGET_FACTORS,
  implementation_profile = list(
    turnover_risk = ifelse(to_ann > 400, "HIGH", ifelse(to_ann > 200, "MEDIUM", "LOW")),
    capacity_risk = "MEDIUM", pit_compliance = "C13/C14/C15 준수"
  ),
  perf = list(sr=as.numeric(perf_strat[["Sharpe"]]), cagr=as.numeric(perf_strat[["CAGR"]]),
              mdd=as.numeric(perf_strat[["MDD"]]), to=to_ann, beta=beta_full),
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
write_json(s1_art,
  file.path(STRAT_DIR, "stage_artifacts", sprintf("s1_construction_%s.json", STRATEGY_ID)),
  pretty=TRUE, auto_unbox=TRUE)

cat(sprintf("\n[DONE] STR_1624 | SR:%.3f CAGR:%.1f%% MDD:%.1f%% TO:%.1f%% (%.0fs)\n",
            as.numeric(perf_strat[["Sharpe"]]), as.numeric(perf_strat[["CAGR"]])*100,
            as.numeric(perf_strat[["MDD"]])*100, to_ann,
            as.numeric(difftime(Sys.time(),t0,units="secs"))))
cat("=== END STR_1624 ===\n")
