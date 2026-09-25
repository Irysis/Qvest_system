##=============================================================================
## factor_db_daily_phase7.R — 나머지 123 GAP 팩터 추가
## Phase 6 parquet에 additive merge
##=============================================================================

cat("═══ Phase 7: 123 GAP 팩터 추가 ═══\n")
cat("시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(Rcpp)
})

.SELF_DIR <- tryCatch(dirname(sys.frame(1)$ofile),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/factor_db")
INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
sourceCpp(file.path(.SELF_DIR, "factor_db_daily_rcpp.cpp"))
# PIT C11 수리(2026-09-24): 해외 계열 가용시점 층(S0) + 일간 fdb PIT 도우미. 없으면 여기서 멈춘다.
source(file.path(INFRA_DIR, "data", "fred_availability.R"))
source(file.path(.SELF_DIR, "factor_db_daily_pit.R"))

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")
START <- as.Date("1989-01-01"); OUT_START <- as.Date("1990-01-01")
t0 <- proc.time()

lag_n <- function(x, n) { m <- length(x); if(m<=n) rep(NA_real_,m) else c(rep(NA_real_,n), x[1:(m-n)]) }
safe_div <- function(a, b, min_b=0) fifelse(!is.na(a) & !is.na(b) & abs(b) > min_b, a/b, NA_real_)

# ═══ 1. RAWDATA 로드 ════════════════════════════════════════════════════════
cat("[1/6] 데이터 로드...\n")
RW <- as.data.table(read_parquet(RAWDATA_CACHE))
INCR_YM <- Sys.getenv("FDB_INCR_YM", ""); INCR_ON <- nzchar(INCR_YM)  # 증분 단일월 모드 (2026-07-18 task#5)
.load_start <- if (INCR_ON) max(START, as.Date(paste0(INCR_YM, "01"), format = "%Y%m%d") - 2200) else START  # ≥1300 거래일 룩백
setkey(RW, Ticker, Date); RW <- RW[Date >= .load_start]
# BM_Ret: prefer RAWDATA's own (Date-class, populated) — phase6 uses the same guard.
# 2026-07-18 fix: benchmark.parquet was rebuilt with POSIXct Date (09:00:00) + a
# BM_Ret column (not "Ret"), so the old UNCONDITIONAL re-merge joined POSIXct vs
# RAWDATA's Date class -> BM_Ret ALL-NA -> every beta-derived phase7 factor
# (M08_Residual_Mom / D09_Dimson_Beta / RE02..09 ~54 factors) went all-NA while
# phase6 (guarded) stayed correct. Guard on RAWDATA BM_Ret + coerce Date on re-merge.
if (!"BM_Ret" %in% names(RW) || all(is.na(RW$BM_Ret))) {
  BM <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  setnames(BM, "Ret", "BM_Ret", skip_absent = TRUE)
  BM[, Date := as.Date(Date)]
  if("BM_Ret" %in% names(RW)) RW[, BM_Ret := NULL]
  RW <- BM[, .(Date, BM_Ret)][RW, on = "Date"]
}
tk_counts <- RW[, .N, by=Ticker]
RW <- RW[Ticker %in% tk_counts[N >= 30L, Ticker]]
cat(sprintf("  RAWDATA: %s rows, %d tickers\n", format(nrow(RW),big.mark=","), length(unique(RW$Ticker))))

# Investor
INV <- tryCatch(as.data.table(read_parquet(file.path(CACHE_DIR,"investor_stock","investor_wide.parquet"))),
                error=function(e) NULL)
if(!is.null(INV)) { INV[, Date := as.Date(Date)]; setkey(INV, Ticker, Date) }

# Regime
REGIME <- as.data.table(read_parquet(file.path(CACHE_DIR,"regime_daily_v2.parquet")))
REGIME[, Date := as.Date(Date)]; setkey(REGIME, Date)
# ★PIT C11(2026-09-24 · 판정서 V-11): RE04/RE05 는 MRS 를 한국 날짜 d 행끼리 결합한다 — 생산자 수리판 스탬프
#   (c11_avail_regime_key) 없으면 MRS 전부 NA → RE04/RE05 NA(fail-closed). 상세 = factor_db_daily_pit.R.
fdb_regime_c11_mask(REGIME, c("MRS"), file.path(CACHE_DIR, "regime_daily_v2.parquet"), label = "phase7 RE04/RE05")

# Consensus
CONS_DIR_PATH <- file.path(CACHE_DIR, "consensus")
cat("  완료.\n\n")

# ═══ 2. RAWDATA-only GAP 팩터 (by=Ticker) ══════════════════════════════════
cat("[2/6] RAWDATA GAP 팩터 (59개)...\n")
t1 <- proc.time()

PART_R <- RW[, {
  ret <- as.double(Ret); bm <- as.double(BM_Ret); cl <- as.double(Close)
  hi <- as.double(High); lo <- as.double(Low); op <- as.double(Open)
  vol <- as.double(Vol); sz <- as.double(Size); m <- .N

  # ─── Defense GAP (19) ─────────────────────────────────────────────
  beta252 <- roll_beta_cpp(ret, bm, 252L)
  # D09 Dimson Beta: sum of lag-1, concurrent, lead-1 betas (illiquidity correction)
  D09_Dimson_Beta <- beta252  # simplified: concurrent beta as proxy
  # D15 Conditional Bear Beta
  bear <- fifelse(!is.na(bm) & bm < -0.01, 1.0, 0.0)
  D15_Cond_Bear_Beta <- roll_cond_beta_cpp(ret, bm, 252L, TRUE)
  # D16 Coskewness: E[ret * bm^2] / (sd(ret)*sd(bm)^2)
  D16_Coskewness <- roll_skew_cpp(ret * fifelse(is.na(bm),0,bm), 252L)
  # D17 Cokurtosis
  D17_Cokurtosis <- roll_kurt_cpp(ret * fifelse(is.na(bm),0,bm), 252L)
  # D18 BAB Rank (cross-sectional → use raw beta)
  D18_BAB_Rank <- beta252
  # D19/D20 EW Beta (exponentially weighted)
  D19_EW_Beta_63 <- roll_beta_cpp(ret, bm, 63L)
  D20_EW_Beta_126 <- roll_beta_cpp(ret, bm, 126L)
  # D24 Systematic Risk Proportion = R^2
  corr_rb <- roll_corr_cpp(ret, bm, 252L)
  D24_Systematic_Risk_Prop <- fifelse(!is.na(corr_rb), corr_rb^2, NA_real_)
  # D25/D26 Tail Beta
  D25_Left_Tail_Beta <- roll_cond_beta_cpp(ret, bm, 252L, TRUE)
  D26_Right_Tail_Beta <- roll_cond_beta_cpp(ret, bm, 252L, FALSE)
  # D27 Beta Stability: sd of rolling 63d betas
  b63 <- roll_beta_cpp(ret, bm, 63L)
  D27_Beta_Stability <- roll_sd_cpp(b63, 126L)
  # D30 FM Beta 21d
  D30_FM_Beta_21d <- roll_beta_cpp(ret, bm, 21L)
  # D31 Relative Beta: beta / mean(beta)
  D31_Relative_Beta <- beta252  # cross-sectional normalization in post
  # D33 Beta Persistence
  D33_Beta_Persistence <- roll_corr_cpp(b63, lag_n(b63, 63L), 126L)
  # D39 Rogers-Satchell Vol
  lhc <- log(pmax(hi,1e-9)/pmax(cl,1e-9)); lho <- log(pmax(hi,1e-9)/pmax(op,1e-9))
  llc <- log(pmax(lo,1e-9)/pmax(cl,1e-9)); llo <- log(pmax(lo,1e-9)/pmax(op,1e-9))
  rs_raw <- lho*lhc + llo*llc
  D39_RogersSatchell_Vol <- roll_mean_cpp(fifelse(is.na(rs_raw),0,sqrt(pmax(rs_raw,0))), 252L)
  # D40 Yang-Zhang Vol
  oc <- log(pmax(op,1e-9)/pmax(lag_n(cl,1L),1e-9))
  D40_YangZhang_Vol <- roll_sd_cpp(oc, 252L)
  # D51 Ulcer Index: sqrt(mean(drawdown^2))
  D51_Ulcer_Index <- roll_mdd_cpp(ret, 252L)  # proxy with MDD

  # ─── Liquidity GAP (19) ───────────────────────────────────────────
  ami <- abs(ret)/pmax(sz/1e8, 1e-9)
  turn <- vol/pmax(sz,1)
  ba <- (hi-lo)/pmax(cl,1)
  # L08 Roll Spread: 2*sqrt(-cov(ret_t, ret_{t-1}))
  ac1 <- roll_autocorr_cpp(ret, 252L)
  sd252 <- roll_sd_cpp(ret, 252L)
  L08_Roll_Spread <- fifelse(!is.na(ac1) & ac1 < 0 & !is.na(sd252),
                              2*sd252*sqrt(pmax(-ac1,0)), NA_real_)
  # L12 PS Gamma proxy
  L12_PS_Gamma <- roll_corr_cpp(abs(ret), lag_n(vol,1L), 252L)
  # L13 Vol Variance Ratio
  vv <- roll_sd_cpp(vol, 252L); vm <- roll_mean_cpp(vol, 252L)
  L13_Vol_Variance_Ratio <- safe_div(vv^2, vm^2)
  # L17 LOT Measure
  L17_LOT_Measure <- roll_zero_count_cpp(ret, 252L, 0.005)
  # L18 Effective Spread proxy
  L18_Eff_Spread_Proxy <- roll_mean_cpp(ba, 63L)
  # L19 Price Delay
  L19_Price_Delay <- 1 - D24_Systematic_Risk_Prop  # 1 - R^2 = delay proxy
  # L21 Market Depth
  L21_Market_Depth <- roll_mean_cpp(abs(log(pmax(vol,1))-roll_mean_cpp(log(pmax(vol,1)),252L)), 252L)
  # L23 Vol Autocorrelation
  L23_Vol_Autocorr <- roll_autocorr_cpp(vol, 252L)
  # L24 Range per Volume
  L24_Range_per_Vol <- roll_mean_cpp(ba/pmax(sqrt(pmax(vol,1)),1e-9), 252L)
  # L25 Amihud × Vol
  L25_Amihud_Vol <- roll_mean_cpp(ami, 252L) * sd252
  # L34 Vol Spike
  v20 <- roll_mean_cpp(vol,20L); v20p <- lag_n(v20, 20L)
  L34_Vol_Spike_Ratio <- safe_div(v20, v20p)
  # L35 Reversal Intensity
  L35_Reversal_Intensity <- roll_mean_cpp(abs(ret) * fifelse(!is.na(ret)&!is.na(lag_n(ret,1L))&ret*lag_n(ret,1L)<0,1,0), 252L)
  # L36 CLV Stability
  clv <- fifelse(hi>lo, (2*cl-hi-lo)/(hi-lo), 0)
  L36_CLV_Stability <- roll_sd_cpp(clv, 252L)
  # L37 Relative Vol (cross-sectional → use raw)
  L37_Relative_Vol <- vol
  # L40 VWAP Spread proxy
  L40_VWAP_Spread <- roll_mean_cpp(abs(cl-(hi+lo+cl)/3)/pmax(cl,1), 252L)
  # L41 Intraday Vol proxy
  L41_Intraday_Vol_Proxy <- roll_mean_cpp(ba/pmax(sqrt(pmax(vol,1)),1e-9), 252L)
  # L43 Turnover Change
  t20 <- roll_mean_cpp(turn,20L); t20p <- lag_n(t20,63L)
  L43_Turnover_Change <- fifelse(!is.na(t20)&!is.na(t20p), t20-t20p, NA_real_)
  # L44 Vol Ret Asymmetry
  uv <- fifelse(!is.na(ret)&ret>0, vol, 0); dv <- fifelse(!is.na(ret)&ret<0, vol, 0)
  uvs <- roll_sum_cpp(uv,252L); dvs <- roll_sum_cpp(dv,252L); tvs <- uvs+dvs
  L44_Vol_Ret_Asymmetry <- fifelse(!is.na(tvs)&tvs>0, abs(uvs-dvs)/tvs, NA_real_)

  # ─── Risk/Crowding/Trend GAP (10) ─────────────────────────────────
  R09_Coskewness <- D16_Coskewness
  R10_Cokurtosis <- D17_Cokurtosis
  # Crowding
  CR01_Sector_Comovement <- roll_corr_cpp(ret, bm, 63L)  # proxy: corr with market
  CR03_Herding_Dispersion <- roll_sd_cpp(ret, 21L)  # cross-section proxy
  CR04_Ownership_Concentration <- roll_mean_cpp(turn, 20L)
  CR05_Short_Pressure_Proxy <- {
    ami_dn <- roll_mean_cpp(ami*fifelse(!is.na(ret)&ret<0,1,0), 252L)
    ami_up <- roll_mean_cpp(ami*fifelse(!is.na(ret)&ret>0,1,0), 252L)
    safe_div(ami_dn, ami_up)
  }
  CR06_DTC_Proxy <- safe_div(sz, roll_mean_cpp(vol,20L)*pmax(cl,1))
  CR08_Volume_Price_Divergence <- {
    pt <- roll_trend_cpp(cl, 42L)
    vt <- roll_mean_cpp(vol,21L)/pmax(roll_mean_cpp(vol,63L),1)-1
    abs(fifelse(!is.na(pt)&!is.na(vt), pt*vt, NA_real_))
  }
  # Trend
  TR01_ADX_Proxy <- {
    dm_p <- pmax(hi-lag_n(hi,1L), 0)
    dm_n <- pmax(lag_n(lo,1L)-lo, 0)
    atr <- roll_mean_cpp(pmax(hi-lo, abs(hi-lag_n(cl,1L)), abs(lo-lag_n(cl,1L))), 14L)
    di_p <- safe_div(roll_mean_cpp(dm_p,14L), atr)
    di_n <- safe_div(roll_mean_cpp(dm_n,14L), atr)
    dx <- safe_div(abs(di_p-di_n), di_p+di_n) * 100
    roll_mean_cpp(fifelse(is.na(dx),0,dx), 14L)
  }
  # Size
  S02_Float_Size <- log(pmax(sz * 0.7, 1))  # float proxy: 70% of market cap

  # ─── Momentum GAP (RAWDATA-only subset) ────────────────────────────
  # M08 Residual Momentum: sum of CAPM residuals
  ivol <- roll_ivol_cpp(ret, bm, 252L)
  alpha <- roll_mean_cpp(ret,252L) - fifelse(!is.na(beta252), beta252*roll_mean_cpp(bm,252L), NA_real_)
  M08_Residual_Mom <- fifelse(!is.na(ivol)&ivol>0, alpha/ivol, NA_real_)

  .(Date = Date,
    D09_Dimson_Beta, D15_Cond_Bear_Beta, D16_Coskewness, D17_Cokurtosis,
    D18_BAB_Rank, D19_EW_Beta_63, D20_EW_Beta_126, D24_Systematic_Risk_Prop,
    D25_Left_Tail_Beta, D26_Right_Tail_Beta, D27_Beta_Stability,
    D30_FM_Beta_21d, D31_Relative_Beta, D33_Beta_Persistence,
    D39_RogersSatchell_Vol, D40_YangZhang_Vol, D51_Ulcer_Index,
    L08_Roll_Spread, L12_PS_Gamma, L13_Vol_Variance_Ratio, L17_LOT_Measure,
    L18_Eff_Spread_Proxy, L19_Price_Delay, L21_Market_Depth, L23_Vol_Autocorr,
    L24_Range_per_Vol, L25_Amihud_Vol, L34_Vol_Spike_Ratio, L35_Reversal_Intensity,
    L36_CLV_Stability, L37_Relative_Vol, L40_VWAP_Spread, L41_Intraday_Vol_Proxy,
    L43_Turnover_Change, L44_Vol_Ret_Asymmetry,
    R09_Coskewness, R10_Cokurtosis,
    CR01_Sector_Comovement, CR03_Herding_Dispersion, CR04_Ownership_Concentration,
    CR05_Short_Pressure_Proxy, CR06_DTC_Proxy, CR08_Volume_Price_Divergence,
    TR01_ADX_Proxy, S02_Float_Size, M08_Residual_Mom)
}, by = Ticker]

cat(sprintf("  %d 팩터, %.1f분\n\n", ncol(PART_R)-2, (proc.time()-t1)["elapsed"]/60))

# ═══ 3. Investor 팩터 (INV01~INV12) ════════════════════════════════════════
cat("[3/6] Investor 팩터 (12개)...\n")
t2 <- proc.time()
INV_F <- NULL
if(!is.null(INV)) {
  INV_F <- INV[, {
    frn <- as.double(Foreign); inst <- as.double(Institutional)
    indv <- as.double(Individual); oc <- as.double(OtherCorp)
    smart <- frn + inst
    .(Date = Date,
      INV01_Foreign_NetBuy_20d = roll_mean_cpp(frn, 20L),
      INV02_Foreign_NetBuy_60d = roll_mean_cpp(frn, 60L),
      INV03_Inst_NetBuy_20d = roll_mean_cpp(inst, 20L),
      INV04_Inst_NetBuy_60d = roll_mean_cpp(inst, 60L),
      INV05_Foreign_Momentum = {
        f20<-roll_mean_cpp(frn,20L); f252<-roll_mean_cpp(frn,252L)
        fifelse(!is.na(f20)&!is.na(f252)&abs(f252)>0, f20/abs(f252)-1, NA_real_)},
      INV06_Inst_Momentum = {
        i20<-roll_mean_cpp(inst,20L); i252<-roll_mean_cpp(inst,252L)
        fifelse(!is.na(i20)&!is.na(i252)&abs(i252)>0, i20/abs(i252)-1, NA_real_)},
      INV07_Retail_Contrarian = roll_mean_cpp(indv, 20L),
      INV08_Foreign_Inst_Agreement = fifelse(
        roll_mean_cpp(frn,20L)*roll_mean_cpp(inst,20L) > 0, 1, 0),
      INV09_Flow_Persistence = roll_autocorr_cpp(smart, 63L),
      INV10_Smart_Money_Flow = roll_mean_cpp(smart, 20L),
      INV11_Foreign_Concentration = roll_sd_cpp(frn, 63L),
      INV12_Supply_Demand_Imbalance = safe_div(
        roll_sum_cpp(smart,20L), roll_sum_cpp(abs(smart),20L)))
  }, by = Ticker]
  setkey(INV_F, Ticker, Date)
  cat(sprintf("  %d 팩터 완료\n", ncol(INV_F)-2))
}
rm(INV); gc(verbose=FALSE)

# ═══ 4-pre. Stage 1 NEW: Macro-derived daily Regime (RE10/11/13/14) ════════
# ★PIT C11·C1 수리(2026-09-24 · 판정서 V-12 · ⑤-4 · decision PIT-C11-CONVENTIONS ③⑤):
#   구판 = (1) RE10·RE13 전표본 frank/.N(C1 — RE10 2020-03-12 = −0.9991059 = 전표본 순위)
#          (2) 전 계열 FRED 관측일 같은 날짜 roll 결합(C11 — RE11 2020-03-16 = 같은 날짜 판)
#          (3) RE14 = 행 기준 shift(12)(CPI 2025-10 결측 → 13개월 변화) + M-01 라벨 결합(2020-03-02 에 04-10 공표 3월 CPI).
#   수리판 = 관측 시계열 위에서 '그 관측까지'만 쓰는 통계(누적 백분위·EWMA·날짜 기준 12개월 변화)를 만든 뒤
#   S0 가용시점 층 fred_asof_join(mode="decision_close")으로 한국 날짜에 싣는다(fdb_fred_stat_on_kr_dates —
#   가용일 단조 확인 포함 · 규칙 = 06_Registry/fred_availability_rules.json: VIX 미국 날짜<한국 날짜 · HY 한국 d+2 ·
#   CPI 라벨+48일/셧다운 override). 계열별 실패 = 그 열 전부 NA(fail-closed · 경고) — 같은 날짜 판으로 되돌아가지 않는다.
cat("[4-pre/6] Macro daily Regime (RE10/11/13/14)...\n")
.macro_path_p7 <- file.path(CACHE_DIR, "macro_fred.parquet")
MACRO_F <- NULL
if (file.exists(.macro_path_p7)) {
  tryCatch({
    .m_p7 <- as.data.table(read_parquet(.macro_path_p7, mmap = FALSE))
    .m_p7[, Date := as.Date(Date)]
    .m_p7 <- .m_p7[!is.na(Value)]

    .ewma_d <- function(x, halflife = 21) {
      alpha <- 1 - exp(-log(2) / halflife)
      n <- length(x); out <- rep(NA_real_, n)
      if (n == 0L) return(out)
      out[1] <- x[1]
      for (k in 2:n) {
        if (is.na(x[k])) out[k] <- out[k-1]
        else if (is.na(out[k-1])) out[k] <- x[k]
        else out[k] <- alpha * x[k] + (1-alpha) * out[k-1]
      }
      out
    }

    .all_dates <- data.table(Date = sort(unique(RW$Date)))
    MACRO_F <- copy(.all_dates)
    .kr_p7 <- MACRO_F$Date

    # 계열 1개 → 관측 시계열 통계 → 가용일 결합. 실패 = 전부 NA + 경고(fail-closed).
    .macro_col_p7 <- function(col, series_id, stat_fun) {
      tryCatch({
        .obs <- fdb_fred_obs(.m_p7, series_id)
        if (is.null(.obs) || !nrow(.obs)) stop("관측 0행")
        .j <- fdb_fred_stat_on_kr_dates(.kr_p7, .obs, series_id, stat_fun)
        cat(sprintf("  %s ← %s (C11 avail · decision_close): %d/%d 한국일 값\n",
                    col, series_id, sum(!is.na(.j$value)), nrow(.j)))
        .j$value
      }, error = function(e) {
        cat(sprintf("  !! [C11] %s(%s) 실패 → 전부 NA(fail-closed): %s\n", col, series_id, conditionMessage(e)))
        warning(sprintf("[C11] phase7 %s(%s): %s", col, series_id, conditionMessage(e)), call. = FALSE)
        rep(NA_real_, length(.kr_p7))
      })
    }

    # RE10 VIX expanding percentile (negate: high VIX = bad) — 누적 백분위(그 관측까지의 VIX 중 순위)
    MACRO_F[, RE10_VIX_Pctile := .macro_col_p7("RE10_VIX_Pctile", "VIXCLS",
                                               function(v, d) -fdb_expanding_pct(v))]
    # RE11 VIX log-change EWMA(반감기 21 관측 — 구판 그대로)
    MACRO_F[, RE11_VIX_Change_EWMA := .macro_col_p7("RE11_VIX_Change_EWMA", "VIXCLS", function(v, d) {
      .ch <- c(NA_real_, diff(log(v))); .ch[!is.finite(.ch)] <- NA_real_
      -.ewma_d(.ch, 21)
    })]
    # RE13 HY OAS expanding percentile — 누적 백분위(FRED 가 ICE 이력을 3년 창으로만 준다: 판정서 1-7)
    MACRO_F[, RE13_Credit_Spread_Pctile := .macro_col_p7("RE13_Credit_Spread_Pctile", "BAMLH0A0HYM2",
                                                         function(v, d) -fdb_expanding_pct(v))]
    # RE14 CPI YoY (negate: high inflation = bad) — 날짜 기준 12개월 변화(YoY 정의 · CONVENTIONS ③)
    MACRO_F[, RE14_Inflation_YoY := .macro_col_p7("RE14_Inflation_YoY", "CPIAUCSL",
                                                  function(v, d) -fdb_change_by_date(v, d, months = 12L))]
    MACRO_F[, YM := format(Date, "%Y%m")]
    setkey(MACRO_F, Date)
    .macro_cols <- setdiff(names(MACRO_F), c("Date","YM"))
    cat(sprintf("  macro daily: %d factors (%s)\n",
                length(.macro_cols), paste(.macro_cols, collapse=", ")))
  }, error = function(e) {
    cat(sprintf("  macro merge failed: %s\n", conditionMessage(e)))
    MACRO_F <<- NULL
  })
}

# ═══ 4. Regime 팩터 (RE02~RE09) ════════════════════════════════════════════
cat("[4/6] Regime 팩터 (8개)...\n")
t3 <- proc.time()
RW_RG <- RW[, .(Ticker, Date, Ret, BM_Ret)]
setkey(RW_RG, Date)
RW_RG <- REGIME[RW_RG, on="Date"]
setkey(RW_RG, Ticker, Date)

REG_F <- RW_RG[, {
  ret <- as.double(Ret); bm_r <- as.double(BM_Ret); mrs <- as.double(MRS)
  mu <- roll_mean_cpp(ret, 252L); sd_r <- roll_sd_cpp(ret, 252L)
  mu_bm <- roll_mean_cpp(bm_r, 252L); sd_bm <- roll_sd_cpp(bm_r, 252L)
  .(Date = Date,
    RE02_Vol_Regime_Pctile = roll_sd_cpp(bm_r, 21L),
    RE03_Mkt_Drawdown = roll_mdd_cpp(bm_r, 252L),
    RE04_HighVol_Beta = roll_cond_beta_cpp(ret, fifelse(is.na(mrs),0,mrs/100), 252L, TRUE),
    RE05_LowVol_Beta = roll_cond_beta_cpp(ret, fifelse(is.na(mrs),0,mrs/100), 252L, FALSE),
    RE06_Beta_Asymmetry = {
      db <- roll_cond_beta_cpp(ret, bm_r, 252L, TRUE)
      ub <- roll_cond_beta_cpp(ret, bm_r, 252L, FALSE)
      fifelse(!is.na(db)&!is.na(ub), db-ub, NA_real_)},
    RE07_Crisis_Beta = roll_cond_beta_cpp(ret, bm_r, 252L, TRUE),
    RE08_Down_Market_Excess = {
      dm <- fifelse(!is.na(bm_r)&bm_r<0, ret-bm_r, NA_real_)
      roll_mean_cpp(fifelse(is.na(dm),0,dm), 252L)},
    RE09_Capture_Ratio = {
      up_r <- fifelse(!is.na(bm_r)&bm_r>0, ret, NA_real_)
      dn_r <- fifelse(!is.na(bm_r)&bm_r<0, ret, NA_real_)
      up_m <- roll_mean_cpp(fifelse(is.na(up_r),0,up_r), 252L)
      dn_m <- roll_mean_cpp(fifelse(is.na(dn_r),0,dn_r), 252L)
      safe_div(up_m, dn_m)})
}, by = Ticker]
setkey(REG_F, Ticker, Date)
rm(RW_RG, RW); gc(verbose=FALSE)
cat(sprintf("  %d 팩터 완료\n\n", ncol(REG_F)-2))

# ═══ 5. 월별 merge + 저장 ══════════════════════════════════════════════════
cat("[5/6] 월별 merge...\n")
t4 <- proc.time()

PART_R <- PART_R[Date >= OUT_START]; setkey(PART_R, Date, Ticker)
PART_R[, YM := format(Date, "%Y%m")]
if(!is.null(INV_F)) { INV_F <- INV_F[Date >= OUT_START]; INV_F[, YM := format(Date, "%Y%m")] }
REG_F <- REG_F[Date >= OUT_START]; REG_F[, YM := format(Date, "%Y%m")]

r_cols <- setdiff(names(PART_R), c("Date","Ticker","YM"))
inv_cols <- if(!is.null(INV_F)) setdiff(names(INV_F), c("Date","Ticker","YM")) else character(0)
reg_cols <- setdiff(names(REG_F), c("Date","Ticker","YM"))

files <- list.files(FDB_DIR, pattern="fdb_daily_.*parquet", full.names=TRUE)
months <- gsub(".*fdb_daily_(\\d+)\\.parquet","\\1", basename(files))
if (INCR_ON) { .keep <- months == INCR_YM; files <- files[.keep]; months <- months[.keep] }  # 증분: 단일월만 merge
pb <- max(1L, length(files) %/% 20L)

for(i in seq_along(files)) {
  ym <- months[i]
  chunk <- as.data.table(read_parquet(files[i]))
  setkey(chunk, Date, Ticker)

  # RAWDATA merge
  r_ym <- PART_R[YM == ym, c("Date","Ticker",r_cols), with=FALSE]
  if(nrow(r_ym)>0) { setkey(r_ym, Date, Ticker); chunk <- merge(chunk, r_ym, by=c("Date","Ticker"), all.x=TRUE) }

  # Investor merge
  if(length(inv_cols)>0) {
    iv_ym <- INV_F[YM == ym, c("Date","Ticker",inv_cols), with=FALSE]
    if(nrow(iv_ym)>0) { setkey(iv_ym, Date, Ticker); chunk <- merge(chunk, iv_ym, by=c("Date","Ticker"), all.x=TRUE) }
  }

  # Regime merge
  rg_ym <- REG_F[YM == ym, c("Date","Ticker",reg_cols), with=FALSE]
  if(nrow(rg_ym)>0) { setkey(rg_ym, Date, Ticker); chunk <- merge(chunk, rg_ym, by=c("Date","Ticker"), all.x=TRUE) }

  # Stage 1: Macro daily (Date-level broadcast to all tickers)
  if (!is.null(MACRO_F)) {
    mf_ym <- MACRO_F[YM == ym, setdiff(names(MACRO_F), "YM"), with=FALSE]
    if (nrow(mf_ym) > 0L) chunk <- merge(chunk, mf_ym, by="Date", all.x=TRUE)
  }

  # temp-rename write (arrow Windows mmap 1224 회피 — read_parquet(files[i]) mmap이
  # 같은 경로 write_parquet과 충돌. factor_db_builder.R:901-904 검증 패턴)
  .tmp_out <- paste0(files[i], ".tmp")
  write_parquet(chunk, .tmp_out, compression="snappy")  # tmp write (mmap 1224 회피)
  gc()                                                   # read mmap 해제 (Windows 파일락)
  file.copy(.tmp_out, files[i], overwrite=TRUE); file.remove(.tmp_out)
  if(i %% pb == 0 || i == length(files))
    cat(sprintf("  [%d/%d] %s (%d cols)\n", i, length(files), ym, ncol(chunk)))
}
cat(sprintf("  merge 완료 (%.1fs)\n\n", (proc.time()-t4)["elapsed"]))

# ═══ 6. Registry 업데이트 ══════════════════════════════════════════════════
cat("[6/6] Registry...\n")
new_facs <- c(r_cols, inv_cols, reg_cols)
reg <- list(n_factors = NA_integer_)
if (!INCR_ON) {   # 증분: 글로벌 registry(전 439월 factor_list) 보존 — n_factors 중복가산·version 하향 방지
  reg_path <- file.path(FDB_DIR, "factor_db_daily_registry.json")
  reg <- if(file.exists(reg_path)) fromJSON(reg_path) else list()
  reg$version <- "7.0.0"
  reg$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  reg$n_factors <- reg$n_factors + length(new_facs)
  reg$phase7 <- list(n_factors = length(new_facs), factors = new_facs)
  reg$factor_list <- c(reg$factor_list, new_facs)
  write(toJSON(reg, pretty=TRUE, auto_unbox=TRUE), reg_path)
}

total_min <- (proc.time()-t0)["elapsed"]/60
cat(sprintf("\n═══ Phase 7 완료 ═══\n  추가: %d팩터 (RAWDATA %d + INV %d + REG %d)\n  총 누적: %d팩터\n  소요: %.1f분\n",
    length(new_facs), length(r_cols), length(inv_cols), length(reg_cols),
    reg$n_factors, total_min))
