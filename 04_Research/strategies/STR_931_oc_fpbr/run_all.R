## STR_931: OtherCorp + fPBR Value Targeting
## 핵심아이디어: OC_40d (내부자 수요) + V05_fPBR (장부가치 저평가) + IdioVol (리스크 통제)
## 가설: 내부자가 인식하는 book/market 저평가(fPBR)는 EV/EBITDA와 다른 value dimension 제공
## 신호 가중: 35% IdioVol + 25% OC_40d + 40% fPBR (Z_Score_Aligned)
## 학술근거: Ke & Petroni (2004); Fama & French (1992) B/M premium
## PIT: C2 flow t-1 | C13 Z_Score_Aligned | C14 Usable_Date | C15 load_month_factors
## Stage: S1 순수 팩터. overlay 없음 (S5에서만 허용)
cat("=== STR_931: OtherCorp + fPBR Value Targeting ===\n\n")
set.seed(931); options(scipen = 999)

STRATEGY_NAME <- "STR_931"
STRATEGY_DESC <- "OtherCorp + fPBR Value Targeting"

SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())

.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(INFRA_DIR, "telegram", "telegram_notify.R"))

LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 20L
LOOKBACK      <- 252L
MIN_OBS       <- 200L
VOL_FLOOR_Q   <- 0.05
FLOW_WINDOW   <- 40L
W_IVOL <- 0.35
W_OC   <- 0.25
W_FPBR <- 0.40

TARGET_FACTORS <- c("V05_fPBR")

# ===================================================================
# Phase 1: RAWDATA 로드 (use_cache=TRUE, 1회)
# ===================================================================
cat("[Phase 1] Loading RAWDATA...\n")
res          <- load_rawdata(use_cache = TRUE)
RAWDATA      <- res$RAWDATA; BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA); BM_DT_ORIG <- copy(BM_DT)
cat(sprintf("  RAWDATA: %d rows | %s ~ %s\n",
  nrow(RAWDATA), as.character(min(RAWDATA$Date)), as.character(max(RAWDATA$Date))))

# ===================================================================
# Phase 2: OtherCorp 투자자 데이터 로드 (C2: t-1 보장)
# ===================================================================
cat("[Phase 2] Loading investor flow data...\n")
inv_raw <- as.data.table(load_investor(fmt = "wide"))
inv_raw[, Date := as.Date(Date)]
setorder(inv_raw, Ticker, Date)

# C2: frollsum은 sig_date 이전 데이터만 누적 (t-1 보장)
inv_raw[, oc_40d    := frollsum(OtherCorp, n = FLOW_WINDOW, align = "right", na.rm = TRUE), by = Ticker]
inv_raw[, oc_nz     := as.numeric(abs(OtherCorp) > 0)]
inv_raw[, oc_active := frollsum(oc_nz, n = FLOW_WINDOW, align = "right", na.rm = TRUE), by = Ticker]
inv_raw[, oc_nz := NULL]
setkey(inv_raw, Date, Ticker)
cat(sprintf("  investor_wide: %d rows | %s ~ %s\n",
  nrow(inv_raw), as.character(min(inv_raw$Date)), as.character(max(inv_raw$Date))))

# ===================================================================
# Phase 3: Factor DB 전처리 — C15: load_month_factors 경유 필수
# ===================================================================
cat("[Phase 3] Bulk preloading V05_fPBR from Factor DB (C15)...\n")
source(file.path(INFRA_DIR, "factor_db", "factor_db_connector.R"))

RAWDATA[, YM := format(Date, "%Y-%m")]
all_signal_dates <- sort(RAWDATA[, .(Signal_Date = max(Date)), by = YM]$Signal_Date)
all_dates        <- sort(unique(RAWDATA$Date))
monthly_dates    <- all_signal_dates[
  all_signal_dates >= all_dates[min(LOOKBACK + 1L, length(all_dates))]
]

# OPT-1: lapply 일괄 로드 (루프 내 반복 금지)
FDB_ALL <- rbindlist(lapply(monthly_dates, function(sd_i) {
  fdb <- tryCatch(load_month_factors(sd_i, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) == 0L) return(NULL)
  fdb_sub <- fdb[Factor_Name %in% TARGET_FACTORS]
  if (nrow(fdb_sub) == 0L) return(NULL)
  fdb_sub[, sig_date := sd_i]; fdb_sub
}), fill = TRUE)

if (is.null(FDB_ALL) || nrow(FDB_ALL) == 0L) {
  cat("[WARN] V05_fPBR Factor DB 없음. fPBR 신호 없이 OC + IdioVol만으로 진행.\n")
  FDB_ALL <- data.table(sig_date = as.Date(character()), Ticker = character(),
                        Factor_Name = character(), Z_Score_Aligned = numeric())
}
setkey(FDB_ALL, sig_date, Ticker, Factor_Name)
cat(sprintf("  FDB_ALL: %d rows | %d dates\n",
  nrow(FDB_ALL), uniqueN(FDB_ALL$sig_date)))

# ===================================================================
# Phase 4: 월별 팩터 계산
# ===================================================================
cat("[Phase 4] Computing monthly factor scores...\n")

setorder(RAWDATA, Ticker, Date)
bm_daily <- unique(RAWDATA[, .(Date, BM_Ret)]); setorder(bm_daily, Date)
mcap_all <- unique(RAWDATA_ORIG[, .(Date, Ticker, Size)])
setkey(mcap_all, Date, Ticker)

z_safe <- function(x) {
  n <- sum(!is.na(x)); if (n < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

.build_one_month <- function(sig_d) {
  sig_d  <- as.Date(sig_d)
  idx    <- which(all_dates == sig_d); if (length(idx) == 0L) return(NULL)

  lb_start <- all_dates[max(1L, idx - LOOKBACK)]
  window   <- RAWDATA[Date >= lb_start & Date <= sig_d]

  # IdioVol: CAPM 잔차 변동성 (expanding window)
  stats <- window[!is.na(Ret), {
    n <- .N
    if (n < MIN_OBS) { list(idiovol = NA_real_, avg_vol = NA_real_) } else {
      bm_w <- bm_daily[Date >= lb_start & Date <= sig_d]
      m    <- merge(data.table(Date = Date, Ret = Ret), bm_w, by = "Date", all.x = TRUE)
      m    <- m[!is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(m) < MIN_OBS) {
        list(idiovol = NA_real_, avg_vol = mean(tail(Vol, 20L), na.rm = TRUE))
      } else {
        fit <- .lm.fit(cbind(1, m$BM_Ret), m$Ret)
        list(idiovol = sd(fit$residuals), avg_vol = mean(tail(Vol, 20L), na.rm = TRUE))
      }
    }
  }, by = Ticker]

  stats <- stats[!is.na(idiovol)]
  stats[, vol_rank := frank(avg_vol, ties.method = "average") / .N]
  stats <- stats[vol_rank > VOL_FLOOR_Q]
  if (nrow(stats) < 30L) return(NULL)

  # C2: OtherCorp flow snap (sig_d 기준, frollsum이 t-1 보장)
  flow_snap <- inv_raw[Date == sig_d, .(Ticker, oc_40d, oc_active)]
  size_snap <- mcap_all[Date == sig_d, .(Ticker, Size)]
  flow_snap <- merge(flow_snap, size_snap, by = "Ticker", all.x = TRUE)
  flow_snap[, oc_norm := fifelse(
    oc_active >= 5L & !is.na(Size) & Size > 0,
    oc_40d / Size, NA_real_)]

  # C14: fPBR — load_month_factors(sig_date) 이미 Usable_Date <= sig_date 보장
  # C13: Z_Score_Aligned 직접 사용 (방향 자동 정렬: 낮은 fPBR = 고득점)
  fpbr_snap <- FDB_ALL[sig_date == sig_d, .(Ticker, fpbr_z = Z_Score_Aligned)]

  stats <- merge(stats, flow_snap[, .(Ticker, oc_norm)], by = "Ticker", all.x = TRUE)
  stats <- merge(stats, fpbr_snap, by = "Ticker", all.x = TRUE)
  if (nrow(stats) < 30L) return(NULL)

  # 순위 점수화
  stats[, rank_ivol := frank(-idiovol, ties.method = "average") / .N]

  has_oc <- sum(!is.na(stats$oc_norm)) >= 15L
  if (has_oc) {
    stats[!is.na(oc_norm), rank_oc := frank(oc_norm, ties.method = "average") / sum(!is.na(oc_norm))]
    stats[is.na(oc_norm),  rank_oc := 0.5]
  } else {
    stats[, rank_oc := 0.5]
  }

  has_fpbr <- sum(!is.na(stats$fpbr_z)) >= 15L
  if (has_fpbr) {
    stats[!is.na(fpbr_z), rank_fpbr := frank(fpbr_z, ties.method = "average") / sum(!is.na(fpbr_z))]
    stats[is.na(fpbr_z),  rank_fpbr := 0.5]
  } else {
    stats[, rank_fpbr := 0.5]
  }

  # Composite Score
  stats[, Score := W_IVOL * rank_ivol + W_OC * rank_oc + W_FPBR * rank_fpbr]

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
cat(sprintf("  factor: %d rows | %d dates | %d skipped\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), n_skipped))

# ===================================================================
# Phase 5: 유동성 필터
# ===================================================================
cat("[Phase 5] Liquidity filter (>= 2억원 20일 평균)...\n")
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
  if (nrow(lm2) > 0L) {
    liq <- lm2[AvgTradeVal >= LIQ_THRESHOLD, Ticker]
    fd  <- fd[Ticker %in% liq]
  }
  if (nrow(fd) >= N_HOLDINGS) fd else NULL
})
filtered_list <- filtered_list[!sapply(filtered_list, is.null)]
FACTORS <- rbindlist(filtered_list); FACTORS[, YM := NULL]
setorder(FACTORS, Date, -Score)
cat(sprintf("  After liq filter: %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
rm(RAWDATA_LIQ, liq_monthly); gc()

# ===================================================================
# Phase 6: 월별 백테스트 (S1: 순수 팩터, overlay 없음)
# ===================================================================
cat("[Phase 6] Monthly simulation (S1: EW 20종목, 15bps, overlay 없음)...\n")
sim <- run_monthly_simulation(
  copy(RAWDATA_ORIG), copy(BM_DT_ORIG), FACTORS,
  n_holdings    = N_HOLDINGS,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 40L, entry_n = 20L),
  vol_target    = NULL,
  vol_lookback  = NULL
)

# ===================================================================
# Phase 7: 성과 요약 + 출력 + 허들
# ===================================================================
out_dir <- file.path(SCRIPT_DIR, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

perf <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
cat(sprintf("\n  === %s (S1 순수 신호) ===\n", STRATEGY_NAME))
cat(sprintf("  CAGR=%.2f%% | Sharpe=%.3f | MDD=%.1f%% | Vol=%.1f%%\n",
  perf$CAGR, perf$Sharpe, perf$MDD, perf$AnnVol))

saveRDS(sim, file.path(SCRIPT_DIR, "sim_result.rds"))
generate_charts(sim, output_dir = out_dir,
  strategy_name = sprintf("%s: %s", STRATEGY_NAME, STRATEGY_DESC))

source(file.path(INFRA_DIR, "strategy_analyzer.R"))
run_analysis(sim, copy(FACTORS), copy(RAWDATA_ORIG), BM_DT_ORIG, out_dir,
  strategy_name = STRATEGY_NAME)

QEPM_AUTO_COMMIT <- TRUE
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result = sim, strategy_name = STRATEGY_NAME, output_dir = out_dir)

# 텔레그램 보고
tryCatch({
  hr <- jsonlite::fromJSON(file.path(out_dir, "hurdle_result.json"))
  msg <- sprintf(
    "[Forge] STR_931: OtherCorp+fPBR\nCAGR %.1f%% | SR %.2f | MDD %.1f%%\nGrade: %s | Score: %s",
    perf$CAGR, perf$Sharpe, perf$MDD,
    hr$grade, hr$total_score
  )
  tg_send(msg)
}, error = function(e) cat("  Telegram skip:", e$message, "\n"))

cat("\n=== STR_931 완료 ===\n")
