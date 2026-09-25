##=============================================================================
## factor_db_daily_phase6.R — 일간 Factor DB 완전 재구축 (288팩터, 월간 네이밍)
##
## 기존 Phase 1~5 (206팩터, 자체 네이밍) 삭제 후
## 월간 DB와 동일한 288팩터를 동일 네이밍으로 재구축
##
## 3단계:
##   A. RAWDATA-only 팩터 (by=Ticker Rcpp) ~170개
##   B. Fundamental + Price 팩터 (forward-fill) ~80개
##   C. Consensus + Investor + Regime ~38개
##
## PIT: C4 lag pre-applied in fundamental_merged, rolling join forward-fill
##=============================================================================

cat("══════════════════════════════════════════════════════\n")
cat("  factor_db_daily_phase6.R — 288팩터 완전 재구축\n")
cat("═��════════════════════════════════════════════════════\n")
cat("시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(Rcpp)
})

.SELF_DIR <- tryCatch(dirname(sys.frame(1)$ofile),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/factor_db")
INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
sourceCpp(file.path(.SELF_DIR, "factor_db_daily_rcpp.cpp"))
# PIT C11 수리(2026-09-24): 해외 계열 가용시점 층(S0) + 일간 fdb PIT 도우미. 없으면 여기서 멈춘다
#   ([0/8] 전체 삭제 전 — 같은 날짜 판으로 조용히 재빌드하지 않는다).
source(file.path(INFRA_DIR, "data", "fred_availability.R"))
source(file.path(.SELF_DIR, "factor_db_daily_pit.R"))

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")
dir.create(FDB_DIR, recursive = TRUE, showWarnings = FALSE)
START <- as.Date("1989-01-01")  # 252d look-back
OUT_START <- as.Date("1990-01-01")
t0 <- proc.time()

lag_n <- function(x, n) { m <- length(x); if(m<=n) rep(NA_real_,m) else c(rep(NA_real_,n), x[1:(m-n)]) }

# ─── 0. 기존 일간 DB 전체 삭제 (fdb_daily + factor_db_daily 모두) ────────────
# 단일월 증분 모드(FDB_INCR_YM=YYYYMM): 삭제·registry 재작성 스킵 + RW 윈도우 + 단일월 출력.
# 미설정 시 기존 full-rebuild 동작 완전 불변. (2026-07-18 task#5)
INCR_YM <- Sys.getenv("FDB_INCR_YM", "")
INCR_ON <- nzchar(INCR_YM)
if (INCR_ON) {
  cat(sprintf("[0/8] 증분 모드 FDB_INCR_YM=%s — 전체삭제 스킵(additive 단일월)\n", INCR_YM))
} else {
  cat("[0/8] 기존 일간 parquet 전체 삭제...\n")
  old <- list.files(FDB_DIR, pattern = "\\.parquet$", full.names = TRUE)
  if (length(old) > 0) { file.remove(old); cat(sprintf("  %d 파일 삭제\n", length(old))) }
  old_reg <- file.path(FDB_DIR, "factor_db_daily_registry.json")
  if (file.exists(old_reg)) file.remove(old_reg)
}
cat("\n")

# ─── 1. 데이터 로드 ──────────────────────────────────────────────────────��──
cat("[1/8] 전체 데이터 로드...\n")
RW <- as.data.table(read_parquet(RAWDATA_CACHE))
setkey(RW, Ticker, Date)
# 증분: 룩백 창 ≥1300 거래일(M12_LR_Reversal=1260d 롤링) → ~2200 캘린더일. full: START(1989).
.load_start <- if (INCR_ON) max(START, as.Date(paste0(INCR_YM, "01"), format = "%Y%m%d") - 2200) else START
RW <- RW[Date >= .load_start]
if (!"BM_Ret" %in% names(RW) || all(is.na(RW$BM_Ret))) {
  BM <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  setnames(BM, "Ret", "BM_Ret", skip_absent = TRUE)
  if ("BM_Ret" %in% names(RW)) RW[, BM_Ret := NULL]
  RW <- BM[, .(Date, BM_Ret)][RW, on = "Date"]
}
cat(sprintf("  RAWDATA: %s rows, %d tickers\n", format(nrow(RW), big.mark=","), length(unique(RW$Ticker))))

# ── VIX column from macro_fred (for D32_Beta_VIX) ──────────────────────────
# ★PIT C11 수리(2026-09-24 · 판정서 V-09 · ⑤-1): 구판은 FRED 관측일(미국 거래일)을 한국 날짜에 같은 날짜
#   roll 결합해 한국 d 행에 미국 d 종가(KRX 종가 뒤 약 14시간)를 실었다(fdb_daily_202003 1,200셀 100% 일치).
#   수리판 = S0 가용시점 층 fred_asof_join(mode="decision_close"): 한국 d 15:30 결정에 쓸 수 있는 최신 관측만
#   (VIXCLS = 미국 날짜 < 한국 날짜 · 규칙 정본 06_Registry/fred_availability_rules.json · factor_db_daily_pit.R).
#   RW 에 이미 VIX 열이 있으면 시간축을 모르므로 버리고 다시 싣는다. 실패 = VIX 전부 NA → D32 전부 NA(fail-closed).
.macro_path_p6 <- file.path(CACHE_DIR, "macro_fred.parquet")
if ("VIX" %in% names(RW)) {
  cat("  [C11] RW 의 기존 VIX 열은 가용일 미확인 — 버리고 가용일 결합으로 다시 싣는다\n")
  RW[, VIX := NULL]
}
if (file.exists(.macro_path_p6)) {
  tryCatch({
    .macro <- as.data.table(read_parquet(.macro_path_p6, mmap = FALSE))
    .vix_obs <- fdb_fred_obs(.macro, "VIXCLS")
    if (!is.null(.vix_obs) && nrow(.vix_obs) > 0L) {
      # 한국 거래일마다 그날 15:30 에 가용한 최신 VIX(미국 휴일·주말은 직전 관측이 이어진다)
      .vix_filled <- fdb_fred_on_kr_dates(sort(unique(RW[["Date"]])), .vix_obs, "VIXCLS")[, .(Date, VIX = value)]
      RW <- merge(RW, .vix_filled, by = "Date", all.x = TRUE)
      setkey(RW, Ticker, Date)
      cat(sprintf("  VIX column merged (C11 avail · decision_close): %d carried values\n", sum(!is.na(RW$VIX))))
    } else {
      cat("  !! [C11] macro_fred 에 VIXCLS 관측 없음 → D32 전부 NA\n")
    }
  }, error = function(e) {
    cat(sprintf("  !! [C11] VIX 가용일 결합 실패 → D32 전부 NA(fail-closed): %s\n", conditionMessage(e)))
    warning("[C11] phase6 VIX 가용일 결합 실패: ", conditionMessage(e), call. = FALSE)
  })
}
# Ensure VIX column exists even if merge skipped (NA fallback for by=Ticker)
if (!("VIX" %in% names(RW))) RW[, VIX := NA_real_]

FUND <- as.data.table(read_parquet(file.path(CACHE_DIR, "fundamental_merged.parquet")))
FUND[, Factor_Date := as.Date(Factor_Date)]
cat(sprintf("  FUND: %s rows\n", format(nrow(FUND), big.mark=",")))

CONS_DIR_PATH <- file.path(CACHE_DIR, "consensus")
INV <- tryCatch(as.data.table(read_parquet(file.path(CACHE_DIR, "investor_stock", "investor_wide.parquet"))), error=function(e) NULL)
if(!is.null(INV)) { INV[, Date := as.Date(Date)]; setkey(INV, Ticker, Date) }
cat(sprintf("  INV: %s rows\n", if(!is.null(INV)) format(nrow(INV),big.mark=",") else "NULL"))

REGIME <- as.data.table(read_parquet(file.path(CACHE_DIR, "regime_daily_v2.parquet")))
REGIME[, Date := as.Date(Date)]; setkey(REGIME, Date)
cat(sprintf("  REGIME: %s rows\n\n", format(nrow(REGIME), big.mark=",")))

# ═══════════════════════════════════════════════════════════════════════════════
# PART A: RAWDATA-only 팩터 (by=Ticker Rcpp)
# ══════════════════���═════════════════════════════��══════════════════════════════
cat("[2/8] PART A: RAWDATA-only 팩터 (Rcpp by=Ticker)...\n")
t1 <- proc.time()

# 짧은 종목 제거 (30관측 미만 → by=Ticker에서 type 불일치 방지)
tk_counts <- RW[, .N, by=Ticker]
RW <- RW[Ticker %in% tk_counts[N >= 30L, Ticker]]
cat(sprintf("  최소 30관측 필터 후: %d tickers\n", length(unique(RW$Ticker))))

PART_A <- RW[, {
  ret <- as.double(Ret); bm <- as.double(BM_Ret); cl <- as.double(Close)
  hi <- as.double(High); lo <- as.double(Low); op <- as.double(Open)
  vol <- as.double(Vol); sz <- as.double(Size); m <- .N

  # ─── MOMENTUM (M01~M32 RAWDATA subset) ──────────────────────────────
  cr252 <- roll_cumret_cpp(ret, 252L); cr126 <- roll_cumret_cpp(ret, 126L)
  cr63 <- roll_cumret_cpp(ret, 63L); cr21 <- roll_cumret_cpp(ret, 21L)
  cr5 <- roll_cumret_cpp(ret, 5L); cr10 <- roll_cumret_cpp(ret, 10L)
  cr42 <- roll_cumret_cpp(ret, 42L); cr189 <- roll_cumret_cpp(ret, 189L)
  cr1260 <- roll_cumret_cpp(ret, 1260L); cr273 <- roll_cumret_cpp(ret, 273L)

  M01_Mom_12_1     <- if(m>21L) lag_n(cr252, 21L) else rep(NA_real_, m)
  M02_Mom_6_1      <- if(m>21L) lag_n(cr126, 21L) else rep(NA_real_, m)
  M03_Mom_3_1      <- if(m>21L) lag_n(cr63, 21L) else rep(NA_real_, m)
  M04_Mom_1        <- cr21
  M05_Trended_Mom  <- roll_trend_cpp(cl, 252L)
  M06_High_52w     <- cl / pmax(roll_max_cpp(cl, 252L), 1e-9)
  M10_Intermediate_Mom <- fifelse(!is.na(M01_Mom_12_1) & !is.na(M02_Mom_6_1),
                                  M01_Mom_12_1 - M02_Mom_6_1, NA_real_)
  M11_ST_Reversal  <- cr5
  M12_LR_Reversal  <- fifelse(!is.na(cr1260) & !is.na(cr273), cr1260 - cr273, NA_real_)
  sd252 <- roll_sd_cpp(ret, 252L)
  M13_VolAdj_Mom   <- fifelse(!is.na(M01_Mom_12_1) & !is.na(sd252) & sd252>1e-9,
                              M01_Mom_12_1 / (sd252 * sqrt(252)), NA_real_)
  mu252 <- roll_mean_cpp(ret, 252L)
  M14_RiskAdj_Mom  <- fifelse(!is.na(mu252) & !is.na(sd252) & sd252>1e-9,
                              mu252 / sd252 * sqrt(252), NA_real_)
  M15_Mom_3        <- cr63
  ma5 <- roll_mean_cpp(cl,5L); ma20 <- roll_mean_cpp(cl,20L); ma50 <- roll_mean_cpp(cl,50L)
  ma100 <- roll_mean_cpp(cl,100L); ma200 <- roll_mean_cpp(cl,200L)
  M16_Trend_Factor <- (as.numeric(cl>ma5)+as.numeric(cl>ma20)+as.numeric(cl>ma50)+
                        as.numeric(cl>ma100)+as.numeric(cl>ma200))/5
  M16_Trend_Factor[is.na(ma200)] <- NA_real_
  M17_Low_52w      <- cl / pmax(roll_min_cpp(cl, 252L), 1e-9)
  M18_RSI          <- roll_rsi_cpp(ret, 14L)
  ml <- roll_mean_cpp(cl,12L) - roll_mean_cpp(cl,26L)
  M19_MACD         <- ml - roll_mean_cpp(ml, 9L)
  M20_Keller_Mom   <- fifelse(!is.na(cr21)&!is.na(cr63)&!is.na(cr126)&!is.na(cr252),
                              12*cr21+4*cr63+2*cr126+cr252, NA_real_)
  M22_Max_Return   <- roll_max_cpp(ret, 21L)
  m6s <- if(m>21L) lag_n(cr126,21L) else rep(NA_real_,m)
  m6p <- if(m>84L) lag_n(cr126,84L) else rep(NA_real_,m)
  M23_Acceleration <- fifelse(!is.na(m6s)&!is.na(m6p), m6s-m6p, NA_real_)
  M29_Mom_5d       <- cr5
  M30_Mom_10d      <- cr10

  # ─── DEFENSE (D01~D58) ──────────────────────────────────────────────
  D01_IdioVol         <- roll_ivol_cpp(ret, bm, 252L)
  D02_Beta            <- roll_beta_cpp(ret, bm, 252L)
  D03_RealVol         <- sd252
  D04_Downside_Beta   <- roll_cond_beta_cpp(ret, bm, 252L, TRUE)
  D05_MaxRet          <- roll_max_cpp(ret, 21L)
  D06_Upside_Beta     <- roll_cond_beta_cpp(ret, bm, 252L, FALSE)
  D07_Beta_Asymmetry  <- fifelse(!is.na(D04_Downside_Beta)&!is.na(D06_Upside_Beta),
                                 D04_Downside_Beta-D06_Upside_Beta, NA_real_)
  D10_Blume_Adj_Beta  <- fifelse(!is.na(D02_Beta), 0.371+0.635*D02_Beta, NA_real_)
  D11_FP_Beta         <- fifelse(!is.na(D02_Beta), 0.6*D02_Beta+0.4, NA_real_)
  D12_Beta_126d       <- roll_beta_cpp(ret, bm, 126L)
  D13_Beta_63d        <- roll_beta_cpp(ret, bm, 63L)
  D14_Beta_Change     <- fifelse(!is.na(D13_Beta_63d)&!is.na(D02_Beta), D13_Beta_63d-D02_Beta, NA_real_)
  D21_CAPM_Alpha      <- mu252 - fifelse(!is.na(D02_Beta), D02_Beta*roll_mean_cpp(bm,252L), NA_real_)
  D22_Tracking_Error  <- roll_sd_cpp(ret-bm, 252L)
  D23_Info_Ratio      <- fifelse(!is.na(D22_Tracking_Error)&D22_Tracking_Error>1e-9,
                                 (mu252-roll_mean_cpp(bm,252L))/D22_Tracking_Error, NA_real_)
  D34_RealVol_21d     <- roll_sd_cpp(ret, 21L)
  D35_RealVol_63d     <- roll_sd_cpp(ret, 63L)
  D36_RealVol_126d    <- roll_sd_cpp(ret, 126L)
  D37_Parkinson_Vol   <- roll_parkinson_vol_cpp(hi, lo, 252L)
  D38_GarmanKlass_Vol <- roll_gk_vol_cpp(hi, lo, cl, op, 252L)
  D41_Vol_of_Vol      <- roll_sd_cpp(D34_RealVol_21d, 63L)
  D42_EWMA_Vol        <- roll_ewma_vol_cpp(ret, 252L, 0.94)
  D43_Skewness        <- roll_skew_cpp(ret, 252L)
  D44_Kurtosis        <- roll_kurt_cpp(ret, 252L)
  D45_Downside_Dev    <- roll_downside_dev_cpp(ret, 252L)
  D46_Sortino         <- fifelse(!is.na(mu252)&!is.na(D45_Downside_Dev)&D45_Downside_Dev>1e-9,
                                 mu252/D45_Downside_Dev, NA_real_)
  D47_CVaR_5pct       <- roll_cvar_cpp(ret, 252L, 0.05)
  D48_VaR_5pct        <- roll_quantile_cpp(ret, 252L, 0.05)
  D49_VaR_1pct        <- roll_quantile_cpp(ret, 252L, 0.01)
  D50_MaxDrawdown     <- roll_mdd_cpp(ret, 252L)
  D52_MinRet          <- roll_min_cpp(ret, 252L)
  ba_raw <- (hi-lo)/pmax(cl,1)
  D53_Range_Vol       <- roll_mean_cpp(ba_raw, 252L)
  D54_Neg_Ret_Prop    <- roll_neg_prop_cpp(ret, 252L)
  D55_Vol_Trend       <- fifelse(!is.na(D35_RealVol_63d)&D36_RealVol_126d>1e-9,
                                 log(D35_RealVol_63d/D36_RealVol_126d), NA_real_)
  rp <- fifelse(!is.na(ret)&ret>0, ret, NA_real_)
  rn <- fifelse(!is.na(ret)&ret<0, ret, NA_real_)
  D56_Up_Vol          <- roll_sd_cpp(rp, 252L)
  D57_Down_Vol        <- roll_sd_cpp(rn, 252L)
  D58_Vol_Asymmetry   <- fifelse(!is.na(D57_Down_Vol)&!is.na(D56_Up_Vol),
                                 D57_Down_Vol-D56_Up_Vol, NA_real_)

  # ─── Stage 1 NEW: D08 Tail Beta + D32 Beta VIX ──────────────────────
  # D08: filter by |bm| > 2*sd — tail-day slope of ret on bm (sign flipped)
  # ★PIT C1 수리(2026-09-24 · 판정서 1-4 · decision PIT-C11-CONVENTIONS ⑤): 구판은 종목 전 이력의 sd·꼬리일로
  #   계수 1개를 추정해 모든 날짜에 복제했다(2008-01 = 2026-06, 1,177/1,177종목 동일) → 날짜 t 값에 t 이후 수익이 섞였다.
  #   수리판 = 결정일까지 누적(expanding): t 의 sd·꼬리 판정·회귀가 전부 t 이하 행만 쓴다(roll_expanding_tail_beta_cpp).
  #   정의 수치(2σ · 꼬리 ≥60일)는 구판 그대로. 차이: 꼬리일 중 ret NA 행은 회귀에서 뺀다(구판은 lm.fit 오류로 종목 전체 NA).
  D08_Tail_Beta <- fdb_d08_expanding_tail_beta(ret, bm, k_sd = 2, min_tail = 60L)
  # D32: rolling 252d beta of ret vs daily VIX log-change
  #   VIX 열은 위 [1/8] 에서 가용일(C11)로 결합됐다 — t 행 = 한국 t 15:30 까지 가용한 최신 VIX(미국 날짜 < t).
  #   그래서 roll_beta 창 [t−251, t] 가 당일 t 를 포함해도 ret_t(t 종가까지)·ΔlogVIX_t(미국 t−1 종가까지) 모두 t 결정 시점 정보다.
  vix_chg <- if (exists("VIX") && any(!is.na(VIX))) {
    v <- as.double(VIX); v[v <= 0] <- NA_real_
    c(NA_real_, diff(log(v)))
  } else rep(NA_real_, m)
  vix_chg[!is.finite(vix_chg)] <- NA_real_
  D32_Beta_VIX <- if (sum(!is.na(vix_chg) & !is.na(ret)) >= 60L) {
    roll_beta_cpp(ret, vix_chg, 252L)
  } else rep(NA_real_, m)

  # ─── LIQUIDITY (L01~L45 subset) ────────────────────────────────────
  ami <- abs(ret)/pmax(sz/1e8, 1e-9)
  L01_Amihud          <- roll_mean_cpp(ami, 252L)
  turn <- vol/pmax(sz, 1)
  L02_Turnover        <- roll_mean_cpp(turn, 20L)
  L03_Volume_Mom      <- fifelse(roll_mean_cpp(vol,252L)>0, roll_mean_cpp(vol,20L)/roll_mean_cpp(vol,252L), NA_real_)
  L04_Bid_Ask_Proxy   <- roll_mean_cpp(ba_raw, 252L)
  dv <- cl*vol
  L05_Dollar_Volume   <- log(pmax(roll_mean_cpp(dv, 20L), 1))
  L06_Zero_Trade_Days <- roll_zero_count_cpp(vol, 252L, 0.5)
  L07_Zero_Return_Days <- roll_zero_count_cpp(ret, 252L, 0.001)
  L09_Amihud_20d      <- roll_mean_cpp(ami, 21L)
  L10_Amihud_Ratio    <- fifelse(!is.na(L09_Amihud_20d)&!is.na(L01_Amihud)&L01_Amihud>1e-12,
                                 L09_Amihud_20d/L01_Amihud, NA_real_)
  L11_Kyle_Lambda     <- roll_mean_cpp(abs(ret)/pmax(sqrt(pmax(vol,1)),1e-9), 252L)
  L14_Price_Impact    <- roll_mean_cpp(abs(ret)/pmax(log(1+vol),1e-9), 252L)
  L15_Turnover_252d   <- roll_mean_cpp(turn, 252L)
  L16_Turnover_Vol    <- roll_sd_cpp(turn, 252L)
  L20_Trade_Frequency <- 1 - roll_zero_count_cpp(vol, 252L, 0.5)
  L22_Ret_Autocorr    <- roll_autocorr_cpp(ret, 252L)
  L26_Log_MktCap      <- log(pmax(sz, 1))
  L27_Price_Level     <- log(pmax(cl, 1))
  L28_Vol_Mom_63d     <- fifelse(roll_mean_cpp(vol,63L)>0, roll_mean_cpp(vol,21L)/roll_mean_cpp(vol,63L)-1, NA_real_)
  a21 <- roll_mean_cpp(ami,21L); a21l <- lag_n(a21,21L)
  L29_Illiq_Change    <- fifelse(!is.na(a21)&!is.na(a21l), a21-a21l, NA_real_)
  L31_Vol_Concentration <- fifelse(roll_mean_cpp(vol,252L)>0, roll_mean_cpp(vol,20L)/roll_mean_cpp(vol,252L), NA_real_)
  L32_Ret_Vol_Corr    <- roll_corr_cpp(ret, vol, 252L)
  L33_AbsRet_Vol_Corr <- roll_corr_cpp(abs(ret), vol, 252L)
  L38_DolVol_Mom      <- fifelse(roll_mean_cpp(dv,252L)>0, roll_mean_cpp(dv,20L)/roll_mean_cpp(dv,252L)-1, NA_real_)
  gap <- op/pmax(lag_n(cl,1L),1e-9)-1
  L39_Overnight_Spread <- roll_mean_cpp(abs(gap), 252L)
  L42_Vol_Skewness    <- roll_skew_cpp(vol, 252L)

  # ─── RISK (R01~R16) ────────────────────────────────────────────────
  R01_VaR_95       <- roll_quantile_cpp(ret, 252L, 0.05)
  R02_VaR_99       <- roll_quantile_cpp(ret, 252L, 0.01)
  R03_CVaR_95      <- roll_cvar_cpp(ret, 252L, 0.05)
  R04_CVaR_99      <- roll_cvar_cpp(ret, 252L, 0.01)
  R05_Tail_Risk    <- fifelse(!is.na(R01_VaR_95)&!is.na(mu252)&abs(mu252)>1e-9, abs(R01_VaR_95/mu252), NA_real_)
  R06_MDD          <- roll_mdd_cpp(ret, 252L)
  R07_Downside_Dev <- D45_Downside_Dev
  R08_Semi_Variance <- fifelse(!is.na(D45_Downside_Dev), D45_Downside_Dev^2, NA_real_)
  R13_NCSKEW       <- roll_ncskew_cpp(ret, 252L)
  R14_DUVOL        <- roll_duvol_cpp(ret, 252L)
  R11_Systematic_Risk <- fifelse(!is.na(roll_corr_cpp(ret,bm,252L)), roll_corr_cpp(ret,bm,252L)^2, NA_real_)
  R12_Idiosyncratic_Risk <- D01_IdioVol
  R15_Sortino      <- D46_Sortino
  R16_Calmar       <- fifelse(!is.na(mu252)&!is.na(R06_MDD)&R06_MDD>1e-9, mu252*252/R06_MDD, NA_real_)

  # ─── CROWDING / TREND ──────────────────────────────────────────────
  CR02_Volume_Concentration <- L31_Vol_Concentration
  uv <- roll_sum_cpp(fifelse(!is.na(ret)&ret>0,vol,0),252L)
  dnv <- roll_sum_cpp(fifelse(!is.na(ret)&ret<0,vol,0),252L)
  tv2 <- uv+dnv
  CR09_Money_Flow_Ratio <- fifelse(!is.na(tv2)&tv2>0, (uv-dnv)/tv2, NA_real_)
  CR10_Convergence_Premium <- roll_autocorr_cpp(ret, 252L)
  CR11_Idiosyncratic_Return <- fifelse(!is.na(R11_Systematic_Risk), 1-R11_Systematic_Risk, NA_real_)
  TR02_Trend_Consistency <- {
    pp <- roll_mean_cpp(as.numeric(ret>0), 63L)
    fifelse(!is.na(pp), abs(pp-0.5)*2, NA_real_)
  }

  # ─── SIZE ──────────────────────────────────────────────────────────
  S01_Size        <- log(pmax(sz, 1))

  # ─── TECHNICAL (Phase 1 동일) ──────────────────────────────────────
  T01_RSI14 <- roll_rsi_cpp(ret,14L); T10_RSI28 <- roll_rsi_cpp(ret,28L)
  ma20c <- roll_mean_cpp(cl,20L); sd20c <- roll_sd_cpp(cl,20L)
  T03_BB20 <- fifelse(!is.na(sd20c)&sd20c>1e-9, (cl-(ma20c-2*sd20c))/(4*sd20c), NA_real_)
  obv_dir <- vol*sign(ret); obv_dir[is.na(obv_dir)] <- 0; obvc <- cumsum(obv_dir)
  T04_OBV21 <- (obvc-lag_n(obvc,21L))/(abs(lag_n(obvc,21L))+1)
  tp <- (hi+lo+cl)/3; mfr <- tp*vol; tpd <- tp-lag_n(tp,1L)
  T05_MFI14 <- 100-100/(1+roll_sum_cpp(fifelse(!is.na(tpd)&tpd>0,mfr,0),14L)/(roll_sum_cpp(fifelse(!is.na(tpd)&tpd<0,mfr,0),14L)+1))
  T06_PMA5 <- cl/pmax(roll_mean_cpp(cl,5L),1e-9)-1
  T07_PMA20 <- cl/pmax(roll_mean_cpp(cl,20L),1e-9)-1
  T08_PMA60 <- cl/pmax(roll_mean_cpp(cl,60L),1e-9)-1
  T09_PMA120 <- cl/pmax(roll_mean_cpp(cl,120L),1e-9)-1
  T13_Gap <- gap
  T14_HLRange <- roll_mean_cpp(ba_raw, 21L)
  T15_AutoCorr <- roll_autocorr_cpp(ret, 22L)

  .(Date = Date,
    M01_Mom_12_1, M02_Mom_6_1, M03_Mom_3_1, M04_Mom_1, M05_Trended_Mom,
    M06_High_52w, M10_Intermediate_Mom, M11_ST_Reversal, M12_LR_Reversal,
    M13_VolAdj_Mom, M14_RiskAdj_Mom, M15_Mom_3, M16_Trend_Factor,
    M17_Low_52w, M18_RSI, M19_MACD, M20_Keller_Mom, M22_Max_Return,
    M23_Acceleration, M29_Mom_5d, M30_Mom_10d,
    D01_IdioVol, D02_Beta, D03_RealVol, D04_Downside_Beta, D05_MaxRet,
    D06_Upside_Beta, D07_Beta_Asymmetry, D10_Blume_Adj_Beta, D11_FP_Beta,
    D12_Beta_126d, D13_Beta_63d, D14_Beta_Change, D21_CAPM_Alpha,
    D22_Tracking_Error, D23_Info_Ratio, D34_RealVol_21d, D35_RealVol_63d,
    D36_RealVol_126d, D37_Parkinson_Vol, D38_GarmanKlass_Vol,
    D41_Vol_of_Vol, D42_EWMA_Vol, D43_Skewness, D44_Kurtosis,
    D45_Downside_Dev, D46_Sortino, D47_CVaR_5pct, D48_VaR_5pct,
    D49_VaR_1pct, D50_MaxDrawdown, D52_MinRet, D53_Range_Vol,
    D54_Neg_Ret_Prop, D55_Vol_Trend, D56_Up_Vol, D57_Down_Vol, D58_Vol_Asymmetry,
    D08_Tail_Beta, D32_Beta_VIX,
    L01_Amihud, L02_Turnover, L03_Volume_Mom, L04_Bid_Ask_Proxy,
    L05_Dollar_Volume, L06_Zero_Trade_Days, L07_Zero_Return_Days,
    L09_Amihud_20d, L10_Amihud_Ratio, L11_Kyle_Lambda, L14_Price_Impact,
    L15_Turnover_252d, L16_Turnover_Vol, L20_Trade_Frequency,
    L22_Ret_Autocorr, L26_Log_MktCap, L27_Price_Level, L28_Vol_Mom_63d,
    L29_Illiq_Change, L31_Vol_Concentration, L32_Ret_Vol_Corr,
    L33_AbsRet_Vol_Corr, L38_DolVol_Mom, L39_Overnight_Spread, L42_Vol_Skewness,
    R01_VaR_95, R02_VaR_99, R03_CVaR_95, R04_CVaR_99, R05_Tail_Risk,
    R06_MDD, R07_Downside_Dev, R08_Semi_Variance, R11_Systematic_Risk,
    R12_Idiosyncratic_Risk, R13_NCSKEW, R14_DUVOL, R15_Sortino, R16_Calmar,
    CR02_Volume_Concentration, CR09_Money_Flow_Ratio, CR10_Convergence_Premium,
    CR11_Idiosyncratic_Return, TR02_Trend_Consistency,
    S01_Size,
    T01_RSI14, T10_RSI28, T03_BB20, T04_OBV21, T05_MFI14,
    T06_PMA5, T07_PMA20, T08_PMA60, T09_PMA120,
    T13_Gap, T14_HLRange, T15_AutoCorr)
}, by = Ticker]

cat(sprintf("  PART A: %d 팩터, %.1f분\n", ncol(PART_A)-2, (proc.time()-t1)["elapsed"]/60))

# ─── Part A 월별 저장 + 메모리 해제 ─────────────────────────────────────────
cat("  Part A 월별 저장 (메모리 절약)...\n")
PART_A <- PART_A[Date >= OUT_START]
setkey(PART_A, Date, Ticker)
PART_A[, YM := format(Date, "%Y%m")]
if (INCR_ON) PART_A <- PART_A[YM == INCR_YM]   # 증분: 해당 월만 출력
a_months <- sort(unique(PART_A$YM))
TEMP_DIR <- file.path(FDB_DIR, "_temp_a")
dir.create(TEMP_DIR, showWarnings = FALSE)
for (ym in a_months) {
  write_parquet(PART_A[YM == ym, !"YM"], file.path(TEMP_DIR, paste0(ym, ".parquet")),
                compression = "snappy")
}
cat(sprintf("  %d months 저장 완료\n\n", length(a_months)))
rm(PART_A); gc(verbose = FALSE)

# ═══════════════════════════════════════════════════════════════════════════════
# PART B: Fundamental + Consensus + Investor + Regime (월별 merge)
# ═══════════════════════════════════════════════════════════════════════════════
cat("[3/8] PART B: Fundamental forward-fill 준비...\n")
t2 <- proc.time()

FUND_ITEMS <- c("TotalEquity","Revenue","NetIncome","OperatingProfit","TotalAssets",
  "TotalLiab","CashAndEquiv","GrossProfit","OperatingCF","DepAmort","RandD",
  "RetainedEarnings","CapitalStock","COGS","SGAExpense","PretaxIncome",
  "CurrentAssets","CurrentLiab","AccountsRecv","Inventory","AccountsPay",
  "TangibleAssets","IntangibleAssets","NonCurrentAssets","NonCurrentLiab",
  "TotalDebt","ShortTermBorr","InvestCF","FinanceCF","Dividends","WorkingCapital","FCF2",
  "InterestExp","InterestIncome")

fund_sub <- FUND[Item %in% FUND_ITEMS]
fund_sub <- fund_sub[, .(Value=Value[.N]), by=.(Ticker, Factor_Date, Item)]
fund_wide <- dcast(fund_sub, Ticker + Factor_Date ~ Item, value.var="Value")
setnames(fund_wide, "Factor_Date", "Date")
setkey(fund_wide, Ticker, Date)
# ★ 핵심 수정: 아이템별 보고 주기 차이로 인한 NA를 forward-fill
item_cols <- setdiff(names(fund_wide), c("Ticker","Date"))
for (ic in item_cols) {
  fund_wide[, (ic) := nafill(get(ic), type="locf"), by = Ticker]
}
cat(sprintf("  fund_wide: %s rows, %d tickers, locf applied to %d cols\n",
            format(nrow(fund_wide), big.mark=","), length(unique(fund_wide$Ticker)), length(item_cols)))

# 이전 기간 값 (YoY growth)
fund_prev <- fund_sub[, {
  d <- sort(unique(Factor_Date))
  if(length(d) >= 2) .SD[Factor_Date == d[length(d)-1]] else NULL
}, by=.(Ticker, Item)]
fp_wide <- NULL
if(nrow(fund_prev) > 0) {
  fp_wide <- dcast(fund_prev, Ticker + Factor_Date ~ Item, value.var="Value")
  setnames(fp_wide, "Factor_Date", "Date")
  prev_cols <- setdiff(names(fp_wide), c("Ticker","Date"))
  setnames(fp_wide, prev_cols, paste0("prev_", prev_cols))
  setkey(fp_wide, Ticker, Date)
}

# Consensus 로드
CONS_DIR_PATH <- file.path(CACHE_DIR, "consensus")
cons_list <- list()
cons_map <- list(C01_SUE="sue", C02_EPS_Chg_1m="eps_chg_1m", C03_EPS_Chg_3m="eps_chg_3m",
                 C04_ESBR="esbr", C05_ESCR="escr", C08_Coverage="coverage",
                 target_price="target_price", eps_1y="eps_1y", bps_1y="bps_1y", dps_1y="dps_1y")
for (cname in names(cons_map)) {
  fp <- file.path(CONS_DIR_PATH, paste0(cons_map[[cname]], ".parquet"))
  if (!file.exists(fp)) next
  cc <- as.data.table(read_parquet(fp))
  cc[, Date := as.Date(Date)]
  vc <- setdiff(names(cc), c("Date","Ticker"))
  if (length(vc)==0) next
  cc <- cc[, .(Ticker, Date, val = get(vc[1]))]
  setnames(cc, "val", cname)
  setkey(cc, Ticker, Date)
  cons_list[[cname]] <- cc
}

# Investor 로드
INV <- tryCatch(as.data.table(read_parquet(file.path(CACHE_DIR,"investor_stock","investor_wide.parquet"))),
                error=function(e) NULL)
if(!is.null(INV)) { INV[, Date := as.Date(Date)]; setkey(INV, Ticker, Date) }

# Regime 로드
REGIME <- as.data.table(read_parquet(file.path(CACHE_DIR,"regime_daily_v2.parquet")))
REGIME[, Date := as.Date(Date)]; setkey(REGIME, Date)
# ★PIT C11(2026-09-24 · 판정서 V-10·V-11): RE_* 는 한국 날짜 d 행끼리 결합한다(아래 REGIME2) — regime_daily_v2 의
#   d 행이 'd 15:30 까지 가용한 정보만' 담을 때만 옳다. 그 보장은 생산자(regime_engine_daily.R) 수리판의 스탬프
#   (c11_avail_regime_key — R 속성·parquet 메타데이터·열 · factor_db_daily_pit.R)로만 받는다. 없으면 regime 값 열 전부 NA(fail-closed).
fdb_regime_c11_mask(REGIME, c("MRS", "exposure", "VIX_z_smooth", "HY_z_smooth", "TS_z_smooth"),
                    file.path(CACHE_DIR, "regime_daily_v2.parquet"), label = "phase6 RE_*")

rm(FUND); gc(verbose = FALSE)
cat(sprintf("  준비 완료 (%.1fs)\n\n", (proc.time()-t2)["elapsed"]))

# Part B는 월별 루프에서 직접 수행 (메모리 절약)
cat("[4/8] Fund 팩터는 월별 루프에서 계산 (메모리 절약)\n\n")

# Close, Size 추출 (월별 루프에서 사용)
RW_PRICE <- RW[Date >= OUT_START, .(Ticker, Date, Close, Size)]
RW_PRICE[, YM := format(Date, "%Y%m")]
setkey(RW_PRICE, Ticker, Date)

safe_div <- function(a, b, min_b=0) fifelse(!is.na(a) & !is.na(b) & abs(b) > min_b, a/b, NA_real_)
# Fund 팩터 계산 함수 (월별 루프에서 호출)
compute_fund_factors <- function(dt) {
  # dt = fund_wide rolling join 결과 (Ticker, Date, Close, Size, + fund items)
  dt[, `:=`(
    Q01_GPA = safe_div(GrossProfit, TotalAssets),
    Q02_ROE = safe_div(NetIncome, TotalEquity),
    Q03_ROA = safe_div(NetIncome, TotalAssets),
    Q05_Accrual = -safe_div(NetIncome - OperatingCF, TotalAssets),
    Q09_CFOA = safe_div(OperatingCF, TotalAssets),
    Q10_Gross_Margin = safe_div(GrossProfit, Revenue),
    Q11_Net_Margin = safe_div(NetIncome, Revenue),
    Q12_Asset_Turnover = safe_div(Revenue, TotalAssets),
    Q13_Fin_Leverage = -safe_div(TotalAssets, TotalEquity),
    Q14_Current_Ratio = safe_div(CurrentAssets, CurrentLiab),
    Q15_Debt_to_Equity = -safe_div(TotalDebt, TotalEquity),
    Q16_Debt_to_Assets = -safe_div(TotalDebt, TotalAssets),
    Q17_ROIC = safe_div(OperatingProfit, TotalEquity + fifelse(is.na(TotalDebt),0,TotalDebt)),
    Q18_Op_Leverage = safe_div(fifelse(is.na(COGS),0,COGS)+fifelse(is.na(SGAExpense),0,SGAExpense), TotalAssets),
    Q19_Cash_to_Assets = safe_div(CashAndEquiv, TotalAssets),
    Q26_RnD_Intensity = safe_div(RandD, Revenue),
    Q28_Cash_Conversion = safe_div(OperatingCF, abs(NetIncome), 1e-6),
    Q29_Inventory_Turnover = safe_div(Revenue, Inventory),
    Q30_Receivables_Turnover = safe_div(Revenue, AccountsRecv),
    Q31_WC_to_Assets = safe_div(CurrentAssets-fifelse(is.na(CurrentLiab),0,CurrentLiab), TotalAssets),
    Q32_Interest_Coverage = safe_div(OperatingProfit, abs(fifelse(is.na(InterestExp),TotalDebt*0.05,InterestExp)), 1e-6),
    Q35_CashBased_OpProf = safe_div(OperatingCF, TotalAssets),
    V01_BM = safe_div(TotalEquity, Size),
    V02_EP = safe_div(NetIncome, Size),
    V03_CFP = safe_div(OperatingCF, Size),
    V08_PSR = safe_div(Size, Revenue),
    V10_FCF_Yield = safe_div(OperatingCF-fifelse(is.na(InvestCF),0,abs(InvestCF)), Size),
    V11_Shareholder_Yield = safe_div(Dividends, Size),
    V16_Tobins_Q = safe_div(Size+fifelse(is.na(TotalLiab),0,TotalLiab), TotalAssets),
    V18_AM = safe_div(TotalAssets, Size),
    V20_SP = safe_div(Revenue, Size),
    V24_Residual_Income = safe_div(NetIncome-TotalEquity*0.08, Size),
    D60_Leverage = safe_div(TotalDebt, TotalEquity),
    R17_Market_Leverage = safe_div(TotalDebt, Size),
    R18_Book_Leverage = safe_div(TotalDebt, TotalAssets),
    AC01_Total_Accruals_CF = -safe_div(NetIncome-OperatingCF, TotalAssets),
    AC05_NOA = -safe_div((TotalAssets-fifelse(is.na(CashAndEquiv),0,CashAndEquiv))-
                          (TotalLiab-fifelse(is.na(TotalDebt),0,TotalDebt)), TotalAssets),
    AC10_Pct_Accruals = -safe_div(NetIncome-OperatingCF, abs(NetIncome), 1e-6),
    IN01_CapEx_to_Assets = safe_div(abs(InvestCF), TotalAssets),
    IN02_CapEx_to_Revenue = safe_div(abs(InvestCF), Revenue)
  )]
  # EV-based
  ev <- dt$Size + fifelse(is.na(dt$TotalDebt),0,dt$TotalDebt) - fifelse(is.na(dt$CashAndEquiv),0,dt$CashAndEquiv)
  dt[, V07_EV_EBITDA := safe_div(ev, OperatingProfit+fifelse(is.na(DepAmort),0,DepAmort))]
  dt[, V13_EV_Sales := safe_div(ev, Revenue)]
  dt[, V14_EBIT_EV := safe_div(OperatingProfit, ev)]
  # Growth (prev_ columns)
  if("prev_Revenue" %in% names(dt)) {
    dt[, `:=`(
      GR01_Revenue_Growth = safe_div(Revenue-prev_Revenue, abs(prev_Revenue), 1e-6),
      GR02_Earnings_Growth = safe_div(NetIncome-prev_NetIncome, abs(prev_NetIncome), 1e-6),
      GR03_Asset_Growth = -safe_div(TotalAssets-prev_TotalAssets, abs(prev_TotalAssets), 1e-6),
      Q06_Asset_Growth = -safe_div(TotalAssets-prev_TotalAssets, abs(prev_TotalAssets), 1e-6),
      Q21_Revenue_Growth = safe_div(Revenue-prev_Revenue, abs(prev_Revenue), 1e-6),
      Q22_Earnings_Growth = safe_div(NetIncome-prev_NetIncome, abs(prev_NetIncome), 1e-6),
      Q34_GP_Growth = safe_div(GrossProfit-prev_GrossProfit, abs(prev_GrossProfit), 1e-6)
    )]
  }
  # 팩터 컬럼만 반환
  fac <- grep("^Q[0-9]|^V[0-9]|^GR[0-9]|^IN[0-9]|^AC[0-9]|^D60|^R1[78]", names(dt), value=TRUE)
  dt[, c("Ticker","Date",fac), with=FALSE]
}
cat("  compute_fund_factors() 정의 완료.\n\n")
# fund_wide + fp_wide는 월별 루프에서 rolling join용으로 보존

# [5/8] Consensus 준비 (저장만, merge는 월별 루프에서)
cat("[5/8] Consensus 데이터 준비 완료 (cons_list in memory)\n\n")

# [6/8] Investor 팩터
cat("[6/8] Investor 팩터...\n")
INV_F <- NULL
if (!is.null(INV)) {
  INV_F <- INV[, {
    frn <- as.double(Foreign); inst <- as.double(Institutional); indv <- as.double(Individual)
    .(Date = Date,
      INV01_Foreign_NetBuy_20d = roll_mean_cpp(frn, 20L),
      INV02_Foreign_NetBuy_60d = roll_mean_cpp(frn, 60L),
      INV03_Inst_NetBuy_20d = roll_mean_cpp(inst, 20L),
      INV04_Inst_NetBuy_60d = roll_mean_cpp(inst, 60L),
      INV05_Foreign_Momentum = {
        f20 <- roll_mean_cpp(frn,20L); f252 <- roll_mean_cpp(frn,252L)
        fifelse(!is.na(f20)&!is.na(f252)&abs(f252)>0, f20/abs(f252)-1, NA_real_)
      },
      INV06_Inst_Momentum = {
        i20 <- roll_mean_cpp(inst,20L); i252 <- roll_mean_cpp(inst,252L)
        fifelse(!is.na(i20)&!is.na(i252)&abs(i252)>0, i20/abs(i252)-1, NA_real_)
      },
      INV07_Retail_Contrarian = roll_mean_cpp(indv, 20L),
      INV10_Smart_Money_Flow = roll_mean_cpp(frn+inst, 20L))
  }, by = Ticker]
  setkey(INV_F, Ticker, Date)
  INV_F[, YM := format(Date, "%Y%m")]
  cat(sprintf("  %d investor 팩터\n", ncol(INV_F)-3))
}
rm(INV); gc(verbose = FALSE)

# Regime 종목별 팩터 — RW에서 Ret+BM_Ret 추출 후 Regime join
cat("  Regime 팩터...\n")
# RW가 아직 있으면 사용, 없으면 rawdata에서 다시 로드
if (!exists("RW") || nrow(RW) == 0) {
  RW <- as.data.table(read_parquet(RAWDATA_CACHE))[Date >= START, .(Ticker, Date, Ret)]
  BM <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  setnames(BM, "Ret", "BM_Ret", skip_absent = TRUE)
  RW <- BM[, .(Date, BM_Ret)][RW, on = "Date"]
  setkey(RW, Ticker, Date)
}
RW_RG <- RW[, .(Ticker, Date, Ret, BM_Ret)]
setkey(RW_RG, Date)
RW_RG <- REGIME[RW_RG, on = "Date"]
setkey(RW_RG, Ticker, Date)
REG_F <- RW_RG[, {
  ret <- as.double(Ret); bm_r <- as.double(BM_Ret)
  .(Date = Date,
    RE01_Mkt_EWMA_21d = roll_mean_cpp(ret, 21L),
    MK01_CAPM_Beta = roll_beta_cpp(ret, fifelse(is.na(bm_r),0,bm_r), 252L))
}, by = Ticker]
setkey(REG_F, Ticker, Date)
REG_F[, YM := format(Date, "%Y%m")]
rm(RW_RG, RW); gc(verbose = FALSE)
cat("  완료.\n\n")

# ═══════════════════════════════════════════════════════════════════════════════
# MERGE + SAVE (월별 청크 — OOM 방지)
# ═══════════════════════════════════════════════════════════════════════════════
cat("[7/8] 월별 청크 merge + 저장...\n")
t6 <- proc.time()

# fund_cols는 compute_fund_factors()에서 동적 결정 (temp_b 불필요)

# Investor YM 추가 (INV_F가 나중에 생성되므로 여기서는 inv_cols만 선언)
inv_cols <- character(0)

# Regime YM 추가
reg_cols <- grep("^RE0|^MK0", names(REG_F), value=TRUE)
REG_F[, YM := format(Date, "%Y%m")]

# Regime market-level
REGIME2 <- REGIME[Date >= OUT_START, .(Date, RE_MRS=MRS, RE_exposure=exposure,
  RE_VIX_z=VIX_z_smooth, RE_HY_z=HY_z_smooth, RE_TS_z=TS_z_smooth)]
setkey(REGIME2, Date)

pb_every <- max(1L, length(a_months) %/% 20L)
total_rows <- 0L
all_fac_cols <- NULL

for (i in seq_along(a_months)) {
  ym <- a_months[i]
  tf <- file.path(TEMP_DIR, paste0(ym, ".parquet"))
  if (!file.exists(tf)) next

  # Part A 월별 로드
  chunk <- as.data.table(read_parquet(tf))
  setkey(chunk, Date, Ticker)

  # Fund: 해당 월 RW_PRICE에 fund_wide rolling join → 팩터 계산
  price_ym <- RW_PRICE[YM == ym, .(Ticker, Date, Close, Size)]
  if (nrow(price_ym) > 0) {
    setkey(price_ym, Ticker, Date)
    fd_ym <- fund_wide[price_ym, roll=Inf, on=.(Ticker, Date)]
    if (!is.null(fp_wide)) fd_ym <- fp_wide[fd_ym, roll=Inf, on=.(Ticker, Date)]
    # DEBUG: 첫 월에 fund join 결과 확인
    if (i == 1L) {
      cat(sprintf("  [DEBUG] fund_wide rows=%d, tickers=%d\n", nrow(fund_wide), length(unique(fund_wide$Ticker))))
      cat(sprintf("  [DEBUG] price_ym rows=%d, tickers=%d\n", nrow(price_ym), length(unique(price_ym$Ticker))))
      cat(sprintf("  [DEBUG] fd_ym rows=%d, TotalAssets valid=%d\n", nrow(fd_ym), sum(!is.na(fd_ym$TotalAssets))))
    }
    fd_ym <- compute_fund_factors(fd_ym)
    setkey(fd_ym, Date, Ticker)
    chunk <- merge(chunk, fd_ym, by=c("Date","Ticker"), all.x=TRUE)
    if (i == 1L) {
      cat(sprintf("  [DEBUG] after merge: Q01_GPA valid=%d/%d\n",
                  sum(!is.na(chunk$Q01_GPA)), nrow(chunk)))
    }
  }

  # Consensus rolling join (per-month)
  for (cname in names(cons_list)) {
    cc <- cons_list[[cname]]
    cc_ym <- cc[Date <= max(chunk$Date) & Date >= min(chunk$Date) - 90]
    if (nrow(cc_ym) > 0) chunk <- cc_ym[chunk, roll=Inf, on=.(Ticker, Date)]
  }
  # Consensus-derived (컬럼 존재 확인)
  if ("Close" %in% names(price_ym) && nrow(price_ym) > 0) {
    cl_dt <- price_ym[, .(Ticker, Date, .Close = Close)]
    setkey(cl_dt, Date, Ticker)
    chunk <- merge(chunk, cl_dt, by=c("Date","Ticker"), all.x=TRUE)
    if ("target_price" %in% names(chunk))
      chunk[, C06_TP_Gap := safe_div(target_price - .Close, .Close)]
    if ("eps_1y" %in% names(chunk))
      chunk[, V04_fPER := safe_div(.Close, eps_1y)]
    if ("bps_1y" %in% names(chunk))
      chunk[, V05_fPBR := safe_div(.Close, bps_1y)]
    if ("dps_1y" %in% names(chunk))
      chunk[, V06_fDY := safe_div(dps_1y, .Close)]
    chunk[, .Close := NULL]
  }

  # Investor merge
  if (exists("INV_F") && !is.null(INV_F)) {
    iv_ym <- INV_F[YM == ym, c("Ticker","Date",inv_cols), with=FALSE]
    if (nrow(iv_ym) > 0) {
      setkey(iv_ym, Date, Ticker)
      chunk <- merge(chunk, iv_ym, by=c("Date","Ticker"), all.x=TRUE)
    }
  }

  # Regime stock-level merge
  rg_ym <- REG_F[YM == ym, c("Ticker","Date",reg_cols), with=FALSE]
  if (nrow(rg_ym) > 0) {
    setkey(rg_ym, Date, Ticker)
    chunk <- merge(chunk, rg_ym, by=c("Date","Ticker"), all.x=TRUE)
  }

  # Regime market-level merge
  chunk <- REGIME2[chunk, on="Date"]

  # 저장
  fpath <- file.path(FDB_DIR, sprintf("fdb_daily_%s.parquet", ym))
  write_parquet(chunk, fpath, compression="snappy")
  total_rows <- total_rows + nrow(chunk)
  if (is.null(all_fac_cols)) all_fac_cols <- setdiff(names(chunk), c("Date","Ticker"))

  if (i %% pb_every == 0 || i == length(a_months))
    cat(sprintf("  [%d/%d] %s (%s rows, %d cols)\n", i, length(a_months), ym,
                format(nrow(chunk),big.mark=","), ncol(chunk)))
}

# Temp 파일 정리
unlink(TEMP_DIR, recursive = TRUE)
cat(sprintf("  저장: %d months (%.1fs)\n\n", length(a_months), (proc.time()-t6)["elapsed"]))

# ─── 8. Registry ────────────────────────────────────────────────────────────
cat("[8/8] Registry...\n")
fac_cols <- if(!is.null(all_fac_cols)) all_fac_cols else character(0)
if (!INCR_ON) {   # 증분: 글로벌 registry(전 439월 factor_list) 보존 — 재작성 스킵
  registry <- list(
    version = "6.0.0",
    created = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    n_factors = length(fac_cols),
    n_months = length(a_months),
    total_rows = total_rows,
    factor_list = sort(fac_cols),
    naming = "monthly_db_compatible"
  )
  write(toJSON(registry, pretty=TRUE, auto_unbox=TRUE), file.path(FDB_DIR, "factor_db_daily_registry.json"))
}

total_min <- (proc.time()-t0)["elapsed"]/60
cat(sprintf("\n══════════════════════════════════════════════════════\n"))
cat(sprintf("  Phase 6 완전 재구축 완료\n"))
cat(sprintf("  팩터: %d개\n", length(fac_cols)))
cat(sprintf("  월 수: %d\n", length(a_months)))
cat(sprintf("  총 rows: %s\n", format(total_rows, big.mark=",")))
cat(sprintf("  소요: %.1f분\n", total_min))
cat(sprintf("══════════════════════════════════════════════════════\n"))
