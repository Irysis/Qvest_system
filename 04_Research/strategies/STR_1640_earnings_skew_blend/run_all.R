cat("=== STR_1640: Earnings-Skewness Blend (C19 + D43) ===\n")
## 핵심아이디어: C19_Composite_Earnings(50%) + D43_Skewness(50%) EW z-score blend
## 애널리스트 컨센서스 상향 수정(earnings momentum) + 수익률 왜도 낮은 종목 선별.
## 왜도 낮은 종목 = 극단 하락 리스크 낮음 → Diversifier 특성.
## S1 순수 팩터 신호. DD/VT/Regime overlay 없음.
## 학술근거: Frazzini & Lamont (2007) earnings momentum + Harvey & Siddique (2000) skewness premium.

set.seed(20240408)
t0 <- Sys.time()

.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
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

STRATEGY_ID   <- "STR_1640"
STRATEGY_FAM  <- "earnings_skew"
N_HOLD        <- 20L
LIQ_THRESHOLD <- 2e8
COMMISSION    <- 0.0015
MAX21D_EXCL   <- 0.80
TARGET_FACTORS <- c("C19_Composite_Earnings", "D43_Skewness")

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

  # C13: Z_Score_Aligned 직접 사용 (방향 반전 금지)
  fdb_wide[, z_C19 := z_safe(C19_Composite_Earnings)]
  fdb_wide[, z_D43 := z_safe(D43_Skewness)]

  # EW blend: fallback to single factor if one missing
  fdb_wide[, Composite := fifelse(
    !is.na(z_C19) & !is.na(z_D43), 0.5 * z_C19 + 0.5 * z_D43,
    fifelse(!is.na(z_C19), z_C19, fifelse(!is.na(z_D43), z_D43, NA_real_))
  )]

  valid <- fdb_wide[!is.na(Composite)]
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
  buffer_zone   = list(keep_n = 25L, entry_n = 20L)
)

perf_strat <- summarise_perf(sim$strategy_xts, "STR_1640")
perf_bm    <- summarise_perf(sim$bm_xts, "KOSPI200")
to_ann     <- calc_turnover(sim$PORTFOLIO_LOG, sim$DAILY_NAV_DT)

cat("\n================================================================\n")
cat("   STR_1640 Earnings-Skewness Blend — S1 결과\n")
cat("================================================================\n")
print(rbind(perf_strat, perf_bm))
cat(sprintf("  Turnover (ann.): %.1f%%\n", to_ann))

strat_ret <- as.numeric(sim$strategy_xts); bm_ret <- as.numeric(sim$bm_xts)
vi <- !is.na(strat_ret) & !is.na(bm_ret)
beta_full <- if (sum(vi) > 12L) coef(lm(strat_ret[vi] ~ bm_ret[vi]))[2] else NA_real_
cat(sprintf("\n  Beta: %s\n", ifelse(is.na(beta_full),"NA",sprintf("%.3f",beta_full))))

generate_charts(sim, output_dir = OUT_DIR, strategy_name = "STR_1640 Earnings-Skewness Blend")

source(file.path(FUNC_PATH, "hurdle_gate.R"))
tryCatch(run_hurdle_gate(sim, STRATEGY_ID, stage = "S1"),
         error = function(e) cat(sprintf("  [WARN] hurdle: %s\n", conditionMessage(e))))

# IC Profile (S2 준비)
ic_res <- tryCatch({
  merged_ic <- merge(FACTORS, sim$DAILY_NAV_DT[, .(Date, Strategy_Ret)], by="Date", all.x=TRUE)
  merged_ic[, next_ret := shift(Strategy_Ret, -1, type="lag"), by = Ticker]
  ic_by_month <- merged_ic[!is.na(next_ret), .(IC = cor(Score, next_ret, use="complete.obs")), by = Date]
  list(IC_mean = mean(ic_by_month$IC, na.rm=TRUE),
       IC_sd   = sd(ic_by_month$IC,   na.rm=TRUE),
       ICIR    = mean(ic_by_month$IC, na.rm=TRUE) / (sd(ic_by_month$IC, na.rm=TRUE)+1e-8),
       n_months = nrow(ic_by_month))
}, error = function(e) list(IC_mean=NA,IC_sd=NA,ICIR=NA,n_months=0L))
cat(sprintf("  IC_mean: %.4f | ICIR: %.4f\n",
            ifelse(is.na(ic_res$IC_mean),NaN,ic_res$IC_mean),
            ifelse(is.na(ic_res$ICIR),NaN,ic_res$ICIR)))

fwrite(FACTORS, file.path(OUT_DIR, "factors.csv"))
fwrite(sim$DAILY_NAV_DT, file.path(OUT_DIR, "daily_nav.csv"))

perf_json <- list(
  strategy = STRATEGY_ID, stage = "S1",
  description = "C19_Composite_Earnings(50%) + D43_Skewness(50%) EW blend",
  factors_used = TARGET_FACTORS, expected_role = "diversifier",
  perf_strategy = as.list(perf_strat), perf_bm = as.list(perf_bm),
  beta_full = beta_full, turnover_ann = to_ann, ic_profile = ic_res,
  n_signal_months = uniqueN(FACTORS$Date),
  run_time_secs = as.numeric(difftime(Sys.time(), t0, units="secs"))
)
write_json(perf_json, file.path(OUT_DIR, "performance.json"), pretty=TRUE, auto_unbox=TRUE)

s1_art <- list(
  strategy_id = STRATEGY_ID, stage = "S1", factors = TARGET_FACTORS,
  implementation_profile = list(
    turnover_risk = ifelse(to_ann > 400,"HIGH",ifelse(to_ann > 200,"MEDIUM","LOW")),
    capacity_risk = "MEDIUM", pit_compliance = "C13/C14/C15 준수"
  ),
  perf = list(sr=as.numeric(perf_strat[["Sharpe"]]), cagr=as.numeric(perf_strat[["CAGR"]]),
              mdd=as.numeric(perf_strat[["MDD"]]), to=to_ann, beta=beta_full),
  ic_profile = ic_res,
  timestamp = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)
write_json(s1_art,
  file.path(STRAT_DIR, "stage_artifacts", sprintf("s1_construction_%s.json", STRATEGY_ID)),
  pretty=TRUE, auto_unbox=TRUE)

cat(sprintf("\n[DONE] STR_1640 | SR:%.3f CAGR:%.1f%% MDD:%.1f%% TO:%.1f%% ICIR:%s (%.0fs)\n",
            as.numeric(perf_strat[["Sharpe"]]), as.numeric(perf_strat[["CAGR"]])*100,
            as.numeric(perf_strat[["MDD"]])*100, to_ann,
            ifelse(is.na(ic_res$ICIR),"NA",sprintf("%.4f",ic_res$ICIR)),
            as.numeric(difftime(Sys.time(),t0,units="secs"))))
cat("=== END STR_1640 ===\n")
