## STR_935: OtherCorp + fPER + Revenue Momentum (GARP Trifecta)
## 핵심아이디어: GARP 3중 확인 — insider demand (OtherCorp level) + forward valuation
##   (fPER, V04_fPER) + price momentum (12M-1M RevMom) = 수요 + 저평가 + 성장 가속
## Signal weights: 35% IdioVol (sd 경량) + 25% OC_40d + 20% fPER + 20% RevMom
## S1 순수 팩터 신호 측정: EW 20종목 + 15bps + 유동성 필터. 오버레이 없음.
## PIT: C2 flow t-1 sig_date | C4 fPER consensus lag | C13 Z_Score_Aligned | C15 load_month_factors
## Academic: Asness et al. (2019); Jegadeesh & Titman (1993); Grinblatt & Keloharju (2000)
## Artifact: stage_artifacts/s1_construction_STR_935_oc_fper_revmom.json
cat("=== STR_935: OtherCorp + fPER + RevMom (GARP Trifecta) ===\n\n")
set.seed(42); options(scipen = 999)

STRATEGY_NAME <- "STR_935"
STRATEGY_DESC <- "OtherCorp + fPER + Revenue Momentum GARP Trifecta"

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(INFRA_DIR, "factor_db", "factor_db_connector.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

# ─── 파라미터 ────────────────────────────────────────────────────────────────
LIQ_THRESHOLD <- 2e8; N_HOLDINGS <- 20L
LOOKBACK <- 252L; MIN_OBS <- 60L; VOL_FLOOR_Q <- 0.05
# 가중: 35% IdioVol + 25% OC_40d + 20% fPER + 20% RevMom
W_IVOL <- 0.35; W_OC <- 0.25; W_FPER <- 0.20; W_REVMOM <- 0.20

# Phase 1: RAWDATA (use_cache=TRUE, 1회)
cat("[Phase 1] Loading RAWDATA...\n")
res          <- load_rawdata(use_cache = TRUE)
RAWDATA      <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)
cat(sprintf("  RAWDATA: %d rows | %s ~ %s\n",
  nrow(RAWDATA), as.character(min(RAWDATA$Date)), as.character(max(RAWDATA$Date))))

# Phase 2: STR_930 data_loader.R 재사용 (OtherCorp flow + macro regime)
# OPT-1: parquet 호출은 data_loader.R에만. run_all.R 내 parquet 직접 로드 없음.
cat("[Phase 2] Sourcing STR_930 data_loader.R (reuse)...\n")
STR930_DIR <- file.path(SCRIPT_DIR, "..", "STR_930_oc_foreign_esbr")
source(file.path(STR930_DIR, "data_loader.R"))
# 결과: inv_preloaded, esbr_monthly, macro_regime_dt 전역 등록됨

mcap_all <- unique(RAWDATA_ORIG[, .(Date, Ticker, Size)])
setkey(mcap_all, Date, Ticker)

# Phase 3: Monthly signal construction
cat("[Phase 3] Computing factor signals...\n")
setorder(RAWDATA, Ticker, Date); RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- sort(RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date)
all_dates        <- sort(unique(RAWDATA$Date))
monthly_dates    <- all_signal_dates[
  all_signal_dates >= all_dates[min(LOOKBACK + 1L, length(all_dates))]
]
bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)

# C15: load_month_factors() 경유 fPER 로드
# 월별 중복 로드 방지: 환경 캐시 사용 (동일 월 Factor DB 1회 로드)
fper_cache_env <- new.env(parent = emptyenv())

.get_fper_for_month <- function(sig_d) {
  ym_tag <- format(sig_d, "%Y%m")
  if (exists(ym_tag, envir = fper_cache_env)) {
    return(get(ym_tag, envir = fper_cache_env))
  }
  # C15: load_month_factors() 경유 (직접 read_parquet 금지)
  # C14: load_month_factors 내부에서 sig_date 이전 파일 선택 → PIT 자동 보장
  fdb <- tryCatch(
    load_month_factors(sig_date = sig_d, coverage_min = 0.05),
    error = function(e) { cat(sprintf("  [fPER] load 실패 %s: %s\n", sig_d, e$message)); NULL }
  )
  if (is.null(fdb) || nrow(fdb) == 0L) {
    assign(ym_tag, NULL, envir = fper_cache_env)
    return(NULL)
  }
  # C13: Z_Score_Aligned 사용. direction=lower_better → align_factor_direction이 자동 반전
  # 반환 시 높을수록 저PER (cheap) = 매수 선호 방향 (수동 반전 금지)
  fper_dt <- fdb[Factor_Name == "V04_fPER", .(Ticker, fper_z = Z_Score_Aligned)]
  assign(ym_tag, fper_dt, envir = fper_cache_env)
  fper_dt
}

.build_one_month <- function(sig_d) {
  sig_d  <- as.Date(sig_d)
  idx    <- which(all_dates == sig_d); if (length(idx) == 0L) return(NULL)

  lb_start <- all_dates[max(1L, idx - LOOKBACK)]
  window   <- RAWDATA[Date >= lb_start & Date <= sig_d]

  # IdioVol: sd(Ret) 경량 방식 (OLS 대신 — 타임아웃 방지)
  # RevMom: ret_12m - ret_1m (12M-1M skip 모멘텀)
  # C1: window 내부 계산만 (full-sample 통계 금지)
  stats <- window[!is.na(Ret), {
    n <- .N
    if (n < MIN_OBS) {
      list(idiovol = NA_real_, avg_vol = NA_real_, ret_12m = NA_real_, ret_1m = NA_real_)
    } else {
      ivol  <- sd(Ret, na.rm = TRUE)
      avg_v <- mean(tail(Vol, 20L), na.rm = TRUE)
      ret_12 <- prod(1 + Ret, na.rm = TRUE) - 1
      ret_1  <- if (n >= 21L) prod(1 + tail(Ret, 21L), na.rm = TRUE) - 1 else NA_real_
      list(idiovol = ivol, avg_vol = avg_v, ret_12m = ret_12, ret_1m = ret_1)
    }
  }, by = Ticker]

  stats <- stats[!is.na(idiovol)]
  stats[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q & (is.na(ret_12m) | ret_12m > -0.40)]
  if (nrow(stats) < 30L) return(NULL)

  # RevMom = ret_12m - ret_1m
  stats[, revmom := fifelse(!is.na(ret_12m) & !is.na(ret_1m), ret_12m - ret_1m, NA_real_)]

  # C2: OC flow rolling 40d pre-computed in data_loader.R; sig_d snapshot = t-1 guaranteed
  flow_snap <- inv_preloaded[Date == sig_d, .(Ticker, oc_40d, oc_active)]
  size_snap <- mcap_all[Date == sig_d, .(Ticker, Size)]
  flow_snap <- merge(flow_snap, size_snap, by = "Ticker", all.x = TRUE)
  flow_snap[, oc_norm := fifelse(
    oc_active >= 5L & !is.na(Size) & Size > 0,
    oc_40d / Size, NA_real_
  )]

  # C15: fPER from load_month_factors() 캐시 경유
  fper_dt <- .get_fper_for_month(sig_d)

  stats <- merge(stats, flow_snap[, .(Ticker, oc_norm)], by = "Ticker", all.x = TRUE)
  if (!is.null(fper_dt) && nrow(fper_dt) > 0L) {
    stats <- merge(stats, fper_dt, by = "Ticker", all.x = TRUE)
  } else {
    stats[, fper_z := NA_real_]
  }

  # 점수 산출: 분위 랭킹 → 가중합
  stats[, rank_ivol := frank(-idiovol, ties.method = "average") / .N]

  has_oc <- sum(!is.na(stats$oc_norm)) >= 15L
  if (has_oc) {
    stats[!is.na(oc_norm), rank_oc := frank(oc_norm,  ties.method = "average") / sum(!is.na(oc_norm))]
    stats[is.na(oc_norm),  rank_oc := 0.5]
  } else { stats[, rank_oc := 0.5] }

  has_fper <- sum(!is.na(stats$fper_z)) >= 15L
  if (has_fper) {
    stats[!is.na(fper_z), rank_fper := frank(fper_z,  ties.method = "average") / sum(!is.na(fper_z))]
    stats[is.na(fper_z),  rank_fper := 0.5]
  } else { stats[, rank_fper := 0.5] }

  has_rm <- sum(!is.na(stats$revmom)) >= 15L
  if (has_rm) {
    stats[!is.na(revmom), rank_rm := frank(revmom,   ties.method = "average") / sum(!is.na(revmom))]
    stats[is.na(revmom),  rank_rm := 0.5]
  } else { stats[, rank_rm := 0.5] }

  stats[, Score := W_IVOL * rank_ivol + W_OC * rank_oc + W_FPER * rank_fper + W_REVMOM * rank_rm]

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

# Phase 4: Liquidity Filter
cat("[Phase 4] Applying liquidity filter...\n")
RAWDATA_LIQ <- copy(RAWDATA_ORIG)
RAWDATA_LIQ[, TradeVal := Close * Vol]; setorder(RAWDATA_LIQ, Ticker, Date)
RAWDATA_LIQ[, AvgTV_20d := frollmean(TradeVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA_LIQ[, YM := format(Date, "%Y-%m")]
liq_monthly <- RAWDATA_LIQ[, .(AvgTradeVal = tail(AvgTV_20d[!is.na(AvgTV_20d)], 1L)), by = .(YM, Ticker)]
setkey(liq_monthly, YM, Ticker)
FACTORS[, YM := format(Date, "%Y-%m")]
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

# Phase 5: Monthly Simulation (S1 순수 — 오버레이 없음)
cat("[Phase 5] Running monthly simulation (S1 pure, no overlay)...\n")
sim <- run_monthly_simulation(
  copy(RAWDATA_ORIG), copy(BM_DT_ORIG), FACTORS,
  n_holdings  = N_HOLDINGS, weight_method = "equal", commission = 0.0015,
  buffer_zone = list(keep_n = 40L, entry_n = 20L),
  vol_target  = NULL, vol_lookback = 60L
)

# Phase 6: Performance + Output + Hurdle
perf <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
cat(sprintf("\n  === %s (S1 pure) ===\n  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%%\n",
  STRATEGY_NAME, perf$CAGR, perf$Sharpe, perf$MDD))

out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
generate_charts(sim, output_dir = out_dir, strategy_name = sprintf("%s: %s", STRATEGY_NAME, STRATEGY_DESC))
source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, copy(FACTORS), copy(RAWDATA_ORIG), BM_DT_ORIG, out_dir, strategy_name = STRATEGY_NAME)
QEPM_AUTO_COMMIT <- TRUE; source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_NAME, output_dir = out_dir)

tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_NAME, hr, out_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

cat(sprintf("\n[%s] Complete.\n", STRATEGY_NAME))
