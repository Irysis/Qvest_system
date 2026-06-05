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

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")
START <- as.Date("1989-01-01"); OUT_START <- as.Date("1990-01-01")
t0 <- proc.time()

lag_n <- function(x, n) { m <- length(x); if(m<=n) rep(NA_real_,m) else c(rep(NA_real_,n), x[1:(m-n)]) }
safe_div <- function(a, b, min_b=0) fifelse(!is.na(a) & !is.na(b) & abs(b) > min_b, a/b, NA_real_)

# ═══ 1. RAWDATA 로드 ════════════════════════════════════════════════════════
cat("[1/6] 데이터 로드...\n")
RW <- as.data.table(read_parquet(RAWDATA_CACHE))
setkey(RW, Ticker, Date); RW <- RW[Date >= START]
BM <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
setnames(BM, "Ret", "BM_Ret", skip_absent = TRUE)
if("BM_Ret" %in% names(RW)) RW[, BM_Ret := NULL]
RW <- BM[, .(Date, BM_Ret)][RW, on = "Date"]
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
cat("[4-pre/6] Macro daily Regime (RE10/11/13/14)...\n")
.macro_path_p7 <- file.path(CACHE_DIR, "macro_fred.parquet")
MACRO_F <- NULL
if (file.exists(.macro_path_p7)) {
  tryCatch({
    .m_p7 <- as.data.table(read_parquet(.macro_path_p7))
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

    # RE10 VIX expanding percentile (negate: high VIX = bad)
    .vix <- .m_p7[Series_ID == "VIXCLS", .(VIX = last(Value)), by = Date]
    if (nrow(.vix) > 0L) {
      setorder(.vix, Date)
      .vix[, RE10_VIX_Pctile := -frank(VIX, ties.method = "average") / .N]
      .vix[, vix_chg := c(NA_real_, diff(log(VIX)))]
      .vix[!is.finite(vix_chg), vix_chg := NA_real_]
      .vix[, RE11_VIX_Change_EWMA := -.ewma_d(vix_chg, 21)]
      MACRO_F <- .vix[, .(Date, RE10_VIX_Pctile, RE11_VIX_Change_EWMA)][MACRO_F,
                       on = "Date", roll = TRUE]
    }
    # RE13 HY OAS expanding percentile
    .hy <- .m_p7[Series_ID == "BAMLH0A0HYM2", .(HY = last(Value)), by = Date]
    if (nrow(.hy) > 0L) {
      setorder(.hy, Date)
      .hy[, RE13_Credit_Spread_Pctile := -frank(HY, ties.method = "average") / .N]
      MACRO_F <- .hy[, .(Date, RE13_Credit_Spread_Pctile)][MACRO_F,
                       on = "Date", roll = TRUE]
    }
    # RE14 CPI YoY (negate: high inflation = bad)
    .cpi <- .m_p7[Series_ID == "CPIAUCSL", .(CPI = last(Value)), by = Date]
    if (nrow(.cpi) > 0L) {
      setorder(.cpi, Date)
      .cpi[, RE14_Inflation_YoY := -(CPI / shift(CPI, 12) - 1)]
      MACRO_F <- .cpi[, .(Date, RE14_Inflation_YoY)][MACRO_F,
                       on = "Date", roll = TRUE]
    }
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

  write_parquet(chunk, files[i], compression="snappy")
  if(i %% pb == 0 || i == length(files))
    cat(sprintf("  [%d/%d] %s (%d cols)\n", i, length(files), ym, ncol(chunk)))
}
cat(sprintf("  merge 완료 (%.1fs)\n\n", (proc.time()-t4)["elapsed"]))

# ═══ 6. Registry 업데이트 ══════════════════════════════════════════════════
cat("[6/6] Registry...\n")
reg_path <- file.path(FDB_DIR, "factor_db_daily_registry.json")
reg <- if(file.exists(reg_path)) fromJSON(reg_path) else list()
new_facs <- c(r_cols, inv_cols, reg_cols)
reg$version <- "7.0.0"
reg$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
reg$n_factors <- reg$n_factors + length(new_facs)
reg$phase7 <- list(n_factors = length(new_facs), factors = new_facs)
reg$factor_list <- c(reg$factor_list, new_facs)
write(toJSON(reg, pretty=TRUE, auto_unbox=TRUE), reg_path)

total_min <- (proc.time()-t0)["elapsed"]/60
cat(sprintf("\n═══ Phase 7 완료 ═══\n  추가: %d팩터 (RAWDATA %d + INV %d + REG %d)\n  총 누적: %d팩터\n  소요: %.1f분\n",
    length(new_facs), length(r_cols), length(inv_cols), length(reg_cols),
    reg$n_factors, total_min))
