## STR_933: OtherCorp Acceleration + ESBR + Coverage Expansion
## 핵심 아이디어: 기타법인 매수 가속도(단기-장기 모멘텀 차이) + 이익서프라이즈 + 애널리스트 커버리지 확장
##   기타법인 수요가 단순 누적 수준이 아닌 "가속 구간"에 있는 종목이 정보 우위를 보유할 가능성 높음.
##   애널리스트 커버리지 증가 종목은 리서치 관심 증가로 저평가 해소 기대.
## Signal weights: 35% SimpleVol + 25% OC_accel + 20% ESBR + 20% Coverage_exp
## S1 Stage: 순수 팩터 신호 측정. EW 20종목 + 15bps. overlay 없음 (S5에서 추가).
## PIT: C2 OC_accel t-1 lag | C13 Z_Score_Aligned | C14 Usable_Date<=sig_date | C15 load_month_factors()
## Academic: Ben-David & Hirshleifer (2012) local info; Jegadeesh et al. (2004) analyst coverage
## s1_construction_STR_933_oc_accel_esbr_coverage.json 참조
cat("=== STR_933: OtherCorp Acceleration + ESBR + Coverage Expansion ===\n\n")
set.seed(42); options(scipen = 999)

STRATEGY_NAME <- "STR_933"
STRATEGY_DESC <- "OtherCorp Accel + ESBR + Coverage Expansion"

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

# ── 파라미터 ──────────────────────────────────────────────────────────────────
LIQ_THRESHOLD <- 2e8; N_HOLDINGS <- 20L
LOOKBACK      <- 252L; MIN_OBS <- 200L; VOL_FLOOR_Q <- 0.05
# 가중: SimpleVol=35%, OC_accel=25%, ESBR=20%, Coverage_exp=20%
W_IVOL <- 0.35; W_OCAC <- 0.25; W_ESBR <- 0.20; W_COV <- 0.20

cat(sprintf("[Params] W_IVOL=%.2f | W_OCAC=%.2f | W_ESBR=%.2f | W_COV=%.2f\n",
  W_IVOL, W_OCAC, W_ESBR, W_COV))

# ── Phase 1: RAWDATA (use_cache=TRUE, 1회) ────────────────────────────────────
cat("[Phase 1] Loading RAWDATA...\n")
res          <- load_rawdata(use_cache = TRUE)
RAWDATA      <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)
cat(sprintf("  RAWDATA: %d rows | %s ~ %s\n",
  nrow(RAWDATA), as.character(min(RAWDATA$Date)), as.character(max(RAWDATA$Date))))

# ── Phase 2: data_loader.R (parquet 로드 전담, OPT-1) ────────────────────────
# 결과 전역: inv_preloaded, esbr_monthly, coverage_monthly, macro_regime_dt
cat("[Phase 2] Sourcing data_loader.R...\n")
source(file.path(SCRIPT_DIR, "data_loader.R"))

mcap_all <- unique(RAWDATA_ORIG[, .(Date, Ticker, Size)])
setkey(mcap_all, Date, Ticker)

# Coverage 가용 여부 플래그 (폴백: 3팩터 35/35/30)
COVERAGE_AVAIL <- nrow(coverage_monthly) > 0L
if (!COVERAGE_AVAIL) {
  cat("  [INFO] Coverage 없음 → 3팩터 fallback: W_IVOL=0.35, W_OCAC=0.35, W_ESBR=0.30\n")
  W_IVOL <- 0.35; W_OCAC <- 0.35; W_ESBR <- 0.30; W_COV <- 0.0
} else {
  cat(sprintf("  coverage_monthly: %d rows | %d months\n",
    nrow(coverage_monthly), uniqueN(coverage_monthly$YM)))
}

# ── Phase 3: Monthly signal construction ─────────────────────────────────────
cat("[Phase 3] Computing factor signals...\n")
setorder(RAWDATA, Ticker, Date); RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- sort(RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date)
all_dates        <- sort(unique(RAWDATA$Date))
monthly_dates    <- all_signal_dates[
  all_signal_dates >= all_dates[min(LOOKBACK + 1L, length(all_dates))]
]
bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)

.build_one_month <- function(sig_d) {
  sig_d  <- as.Date(sig_d); sig_ym <- format(sig_d, "%Y-%m")
  idx    <- which(all_dates == sig_d); if (length(idx) == 0L) return(NULL)
  lb_start <- all_dates[max(1L, idx - LOOKBACK)]
  window   <- RAWDATA[Date >= lb_start & Date <= sig_d]

  # SimpleVol: 252d expanding simple sd(Ret) — OLS 대신 경량화
  stats <- window[!is.na(Ret), {
    n <- .N
    if (n < MIN_OBS) {
      list(idiovol = NA_real_, avg_vol = NA_real_, ret_12m = NA_real_)
    } else {
      list(idiovol = sd(Ret),
           avg_vol = mean(tail(Vol, 20L), na.rm = TRUE),
           ret_12m = prod(1 + Ret, na.rm = TRUE) - 1)
    }
  }, by = Ticker]
  stats <- stats[!is.na(idiovol)]
  stats[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q & ret_12m > -0.40]
  if (nrow(stats) < 30L) return(NULL)

  # ── OC_accel: (OC_40d - OC_80d/2) / |OC_80d| / Size ────────────────────
  # C2: data_loader.R에서 rolling 사전 계산 완료 (sig_date snapshot = t-1 보장)
  oc_snap   <- inv_preloaded[Date == sig_d, .(Ticker, oc_40d, oc_80d, oc_active)]
  size_snap <- mcap_all[Date == sig_d, .(Ticker, Size)]
  oc_snap   <- merge(oc_snap, size_snap, by = "Ticker", all.x = TRUE)
  oc_snap[, oc_accel := fifelse(
    oc_active >= 5L & !is.na(Size) & Size > 0 &
    !is.na(oc_80d) & abs(oc_80d) > 0,
    ((oc_40d - oc_80d / 2) / abs(oc_80d)) / Size * 1e8,
    NA_real_
  )]

  # ── ESBR: C14 esbr_monthly[YM == sig_ym] ────────────────────────────────
  esbr_snap <- esbr_monthly[YM == sig_ym]
  if (nrow(esbr_snap) == 0L) {
    prev_ym   <- format(as.Date(paste0(sig_ym, "-01")) - 1L, "%Y-%m")
    esbr_snap <- esbr_monthly[YM == prev_ym]
  }

  # ── Coverage expansion: coverage_monthly[YM == sig_ym] ──────────────────
  cov_snap <- if (COVERAGE_AVAIL) {
    coverage_monthly[YM == sig_ym, .(Ticker, cov_exp)]
  } else {
    data.table(Ticker = character(0), cov_exp = numeric(0))
  }

  # ── 팩터 합산 ────────────────────────────────────────────────────────────
  stats <- merge(stats, oc_snap[, .(Ticker, oc_accel)], by = "Ticker", all.x = TRUE)
  if (nrow(esbr_snap) > 0L) {
    stats <- merge(stats, esbr_snap[, .(Ticker, esbr_val)], by = "Ticker", all.x = TRUE)
  } else { stats[, esbr_val := NA_real_] }
  if (nrow(cov_snap) > 0L) {
    stats <- merge(stats, cov_snap, by = "Ticker", all.x = TRUE)
  } else { stats[, cov_exp := NA_real_] }

  # 순위 기반 점수 (C13: 방향 내재화, 수동 반전 금지)
  stats[, rank_ivol := frank(-idiovol, ties.method = "average") / .N]  # 낮은 변동성 선호

  has_ocac <- sum(!is.na(stats$oc_accel)) >= 15L
  if (has_ocac) {
    stats[!is.na(oc_accel), rank_ocac := frank(oc_accel, ties.method="average") / sum(!is.na(oc_accel))]
    stats[is.na(oc_accel),  rank_ocac := 0.5]
  } else { stats[, rank_ocac := 0.5] }

  has_esbr <- sum(!is.na(stats$esbr_val)) >= 15L
  if (has_esbr) {
    stats[!is.na(esbr_val), rank_esbr := frank(esbr_val, ties.method="average") / sum(!is.na(esbr_val))]
    stats[is.na(esbr_val),  rank_esbr := 0.5]
  } else { stats[, rank_esbr := 0.5] }

  has_cov <- COVERAGE_AVAIL && sum(!is.na(stats$cov_exp)) >= 15L
  if (has_cov) {
    stats[!is.na(cov_exp), rank_cov := frank(cov_exp, ties.method="average") / sum(!is.na(cov_exp))]
    stats[is.na(cov_exp),  rank_cov := 0.5]
  } else { stats[, rank_cov := 0.5] }

  stats[, Score := W_IVOL * rank_ivol + W_OCAC * rank_ocac +
                   W_ESBR * rank_esbr + W_COV * rank_cov]

  # 섹터 중립화
  sector_snap <- unique(RAWDATA[Date == sig_d, .(Ticker, Sector)])
  stats <- merge(stats, sector_snap, by = "Ticker", all.x = TRUE)
  stats[!is.na(Sector), Score := Score - mean(Score, na.rm = TRUE), by = Sector]

  stats[, Date := sig_d]
  stats[!is.na(Score), .(Date, Ticker, Score)]
}

factor_list <- lapply(monthly_dates, .build_one_month)
factor_list <- factor_list[!sapply(factor_list, is.null)]
n_skipped   <- length(monthly_dates) - length(factor_list)
FACTORS     <- rbindlist(factor_list); setorder(FACTORS, Date, -Score)
if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
cat(sprintf("[factor] %d rows | %d dates | %d skipped\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped))

# ── Phase 4: Liquidity Filter ─────────────────────────────────────────────────
cat("[Phase 4] Applying liquidity filter...\n")
RAWDATA_LIQ <- copy(RAWDATA_ORIG)
RAWDATA_LIQ[, TradeVal := Close * Vol]; setorder(RAWDATA_LIQ, Ticker, Date)
RAWDATA_LIQ[, AvgTV_20d := frollmean(TradeVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA_LIQ[, YM := format(Date, "%Y-%m")]
liq_monthly <- RAWDATA_LIQ[, .(AvgTradeVal = tail(AvgTV_20d[!is.na(AvgTV_20d)], 1L)), by = .(YM, Ticker)]
setkey(liq_monthly, YM, Ticker); FACTORS[, YM := format(Date, "%Y-%m")]
fac_dates <- sort(unique(FACTORS$Date))
filtered_list <- lapply(fac_dates, function(dt) {
  dt2 <- as.Date(dt); ym2 <- format(dt2, "%Y-%m")
  fd  <- FACTORS[Date == dt2]; lm2 <- liq_monthly[YM == ym2]
  if (nrow(lm2) > 0L) { liq <- lm2[AvgTradeVal >= LIQ_THRESHOLD, Ticker]; fd <- fd[Ticker %in% liq] }
  if (nrow(fd) >= N_HOLDINGS) fd else NULL
})
filtered_list <- filtered_list[!sapply(filtered_list, is.null)]
FACTORS <- rbindlist(filtered_list); FACTORS[, YM := NULL]
setorder(FACTORS, Date, -Score)
cat(sprintf("  After liq filter: %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(RAWDATA_LIQ, liq_monthly); gc()

# ── Phase 5: Monthly Simulation ───────────────────────────────────────────────
cat("[Phase 5] Running monthly simulation...\n")
sim <- run_monthly_simulation(
  copy(RAWDATA_ORIG), copy(BM_DT_ORIG), FACTORS,
  n_holdings    = N_HOLDINGS,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 40L, entry_n = 20L),
  vol_target    = 0.25, vol_lookback = 60L
)

# ── Phase 6: Performance + Output + Hurdle ────────────────────────────────────
perf <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
cat(sprintf("\n=== %s 결과 (S1 순수 팩터) ===\n  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
  STRATEGY_NAME, perf$CAGR, perf$Sharpe, perf$MDD))
cat(sprintf("  (참조: STR_930 — CAGR=4.85%%, Sharpe=0.481, MDD=54.2%%)\n\n"))

out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
generate_charts(sim, output_dir = out_dir,
  strategy_name = sprintf("%s: %s", STRATEGY_NAME, STRATEGY_DESC))
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, copy(FACTORS), copy(RAWDATA_ORIG), BM_DT_ORIG, out_dir, strategy_name = STRATEGY_NAME)

QEPM_AUTO_COMMIT <- TRUE; source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_NAME, output_dir = out_dir)
tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_NAME, hr, out_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat(sprintf("\n[%s] Complete.\n", STRATEGY_NAME))
