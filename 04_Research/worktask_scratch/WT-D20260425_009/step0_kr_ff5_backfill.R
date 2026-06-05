#==============================================================================
# WT-D20260425_009 — Step 0: KR FF5 RMW/CMA + HML 백필 (2002-07~2026-03)
#
# 목적: alpha_package.json의 external_validation_framework="ff5_backfilled"
#       구현. Risk Agent가 DART TTM + RAWDATA 기반 6-portfolio 직접 구축.
#
# 출력: .cache/kr_factor_returns_v2.parquet
# 스키마: Date, MKT, SMB, HML, WML, RMW, CMA, RF, n_obs_meta
#
# Fama-French (1993, 2015) + Novy-Marx (2013) 표준:
#   - Size: ME median split (S/B)
#   - B/M: BE/ME tercile (Value/Neutral/Growth)
#   - OP : OperatingProfit/BookEquity tercile (Robust/Neutral/Weak)
#   - Inv: ΔTotalAssets/TotalAssets tercile (Conservative/Neutral/Aggressive)
#   - 2×3 = 6 portfolio per dimension
#
# PIT 규칙:
#   - 연간 결산(12월) → 5월 1일 적용 (5개월 lag)
#   - May rebalance: t년 5월 = t-1년 12월 결산 자료
#   - Monthly cumulative compounding 동안 같은 weight 유지
#   - C5: t-1 weights × t return
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
setwd(PROJECT_ROOT)

cat("\n=== Step 0: KR FF5 Backfill 시작 ===\n")

# ============ 1. RAWDATA 로드 (price + size) ============
cat("[1] RAWDATA 로드...\n")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RAW[, Date := as.Date(Date)]
setkey(RAW, Date, Ticker)

# 종목 universe: KR 등록 보통주 (A로 시작), 시가총액 양수, 가격 양수
RAW <- RAW[!is.na(Close) & Close > 0 & !is.na(Size) & Size > 0]
RAW[, MarketCap := Close * Size]   # KRW 단위

# 월말 snapshot 생성
RAW[, YM := format(Date, "%Y%m")]
month_end <- RAW[, .(Last_Date = max(Date)), by = YM]
setnames(month_end, "Last_Date", "MonthEnd")
RAW <- merge(RAW, month_end, by = "YM")
RAW_ME <- RAW[Date == MonthEnd, .(Date, Ticker, Close, MarketCap, Ret, BM_Ret)]
setkey(RAW_ME, Date, Ticker)

cat("  RAWDATA: ", nrow(RAW_ME), "월말 obs, ", uniqueN(RAW_ME$Ticker), "tickers\n")

# ============ 2. Fundamentals 로드 (merged: XLSX 2000-2014 + DART 2015+) ============
cat("[2] Fundamentals 로드 (XLSX + DART merged)...\n")
FM <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
FM[, Period_Date := as.Date(Period_Date)]
FM[, Factor_Date := as.Date(Factor_Date)]
FM[, Period := as.character(Period)]

# 연간 (12월 결산)만 추출 — Period 끝자리 12 (예: 200312, 200412)
FM[, FiscalMonth := substr(Period, 5, 6)]
FM_ANN <- FM[FiscalMonth == "12"]
cat("  Annual obs: ", nrow(FM_ANN), "(XLSX:", sum(FM_ANN$Source == "XLSX"), ", DART:", sum(FM_ANN$Source == "DART"), ")\n")

# Wide cast — Item별 분리 (Value만 사용; merged는 TTM_Value 컬럼 부재)
get_item_wide <- function(item) {
  d <- FM_ANN[Item == item, .(Ticker, Period_Date, Source, val = Value)]
  # 동일 Ticker-Period 중 DART 우선 (priority: DART > XLSX, 단 XLSX는 2014까지만 가용)
  setorder(d, Ticker, Period_Date, -Source)  # DART 알파벳상 D > X
  d_uniq <- d[, .SD[1], by = .(Ticker, Period_Date)]
  d_uniq[, Source := NULL]
  setnames(d_uniq, "val", item)
  d_uniq
}

ASSETS <- get_item_wide("TotalAssets")
EQUITY <- get_item_wide("TotalEquity")
OP     <- get_item_wide("OperatingProfit")

cat("  TotalAssets: ", nrow(ASSETS), "/ TotalEquity: ", nrow(EQUITY), "/ OperatingProfit: ", nrow(OP), "\n")

# Merge
FUND <- merge(merge(ASSETS, EQUITY, by = c("Ticker", "Period_Date"), all = TRUE),
              OP, by = c("Ticker", "Period_Date"), all = TRUE)
setkey(FUND, Ticker, Period_Date)

# Lagged TotalAssets (t-1 fiscal year): asset growth 계산용
FUND[, FiscalYear := as.integer(format(Period_Date, "%Y"))]
FUND_lag <- copy(FUND)[, .(Ticker, FiscalYear_lag = FiscalYear, Assets_lag = TotalAssets)]
FUND_lag[, FiscalYear := FiscalYear_lag + 1]
FUND <- merge(FUND, FUND_lag[, .(Ticker, FiscalYear, Assets_lag)], by = c("Ticker", "FiscalYear"), all.x = TRUE)
FUND[, AssetGrowth := (TotalAssets - Assets_lag) / Assets_lag]

cat("  FUND merged + AssetGrowth: ", nrow(FUND), "Ticker-FY rows\n")

# ============ 3. PIT mapping: rebalance month → fiscal year ============
# May rebalance: t년 5월 1일 = t-1년 12월 결산 사용
# 예: 2003-05 첫 리밸 → 2002-12-31 결산 자료
# 단순화: rebalance_year 의 fiscal year를 (rebalance_year - 1)로 매핑
# 매월 rebalance: 매월 첫 거래일 기준으로 가장 최근 가용 결산 사용 (5월 lag rule)
cat("[3] PIT rebalance mapping...\n")

# 모든 월말 시그널 날짜 추출
sig_dates <- sort(unique(RAW_ME$Date))
sig_dates <- sig_dates[sig_dates >= as.Date("2002-07-01")]
cat("  signal dates: ", length(sig_dates), "(", as.character(min(sig_dates)), "->", as.character(max(sig_dates)), ")\n")

# 각 sig_date에 대해 적용 가능한 fiscal year 결정
# Rule: sig_year의 5월 이후면 (sig_year - 1) 결산 사용; 5월 이전이면 (sig_year - 2) 결산
get_fiscal_year_for_sigdate <- function(sd) {
  yr <- as.integer(format(sd, "%Y"))
  mo <- as.integer(format(sd, "%m"))
  if (mo >= 5) yr - 1 else yr - 2
}

# ============ 4. 각 월별 6-portfolio 형성 + factor return 계산 ============
cat("[4] 월별 portfolio 형성 시작 (총", length(sig_dates), "개월)...\n")

results <- list()

for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  fy <- get_fiscal_year_for_sigdate(sd)

  # t-1 가격 snapshot (전월말 ME); 현 월 return을 위해 t-1 weights 사용 = C5 준수
  # = sig_date 시점의 ME를 weight로 사용, sig_date+1 ~ next_sig_date의 return을 weighted
  # 단순화: sig_date == 월말 close. weight = sig_date 시점 ME × t-1 fundamentals.
  # 다음 월 return은 다음 sig_date의 Ret 컬럼에서 추출 (월간 이미 t-1 close → t close ret).
  # ⇒ 본 루프에서는 sig_date의 weight로 sig_date의 (이미 끝난) ret 계산 시 PIT 위반.
  # 정정: weight (sig_date - 1 month) → ret (sig_date)
  #
  # 즉 t = sig_date라면 portfolio formation은 t-1 ME 사용, return은 t-1 → t.
  # 본 구현에서 sig_dates를 sig_date_t-1로 사용해 weight 형성, return은 sig_dates[i+1]에서.

  if (i == length(sig_dates)) break  # 마지막 월은 forward return 없음

  ret_date <- sig_dates[i + 1]   # 다음 월말 — return 적용

  # Universe: sig_date 시점의 가격/시총
  uni <- RAW_ME[Date == sd, .(Ticker, MarketCap_t = MarketCap, Close_t = Close)]
  if (nrow(uni) == 0) next

  # Fundamentals for fiscal year fy
  fund_fy <- FUND[FiscalYear == fy & !is.na(TotalEquity) & TotalEquity > 0,
                  .(Ticker, TotalAssets, TotalEquity, OperatingProfit, AssetGrowth)]
  if (nrow(fund_fy) == 0) next

  # Merge
  port_uni <- merge(uni, fund_fy, by = "Ticker")
  if (nrow(port_uni) < 30) next  # 최소 종목수 컷

  # Compute ratios (PIT-safe: t-1 fundamentals + t MarketCap)
  port_uni[, BM := TotalEquity / MarketCap_t]                 # B/M
  port_uni[, OP_BE := OperatingProfit / TotalEquity]           # OP/BE
  port_uni[, INV := AssetGrowth]                                # ΔAssets/Assets

  port_uni <- port_uni[is.finite(BM) & is.finite(OP_BE) & is.finite(INV) & BM > 0]

  if (nrow(port_uni) < 30) next

  # Size split: ME median
  size_med <- median(port_uni$MarketCap_t, na.rm = TRUE)
  port_uni[, SizeGrp := ifelse(MarketCap_t < size_med, "S", "B")]

  # B/M tercile (30/40/30)
  bm_q <- quantile(port_uni$BM, probs = c(0.30, 0.70), na.rm = TRUE)
  port_uni[, BMGrp := fcase(
    BM <= bm_q[1], "Growth",
    BM >= bm_q[2], "Value",
    default = "Neutral"
  )]

  # OP/BE tercile
  op_q <- quantile(port_uni$OP_BE, probs = c(0.30, 0.70), na.rm = TRUE)
  port_uni[, OPGrp := fcase(
    OP_BE <= op_q[1], "Weak",
    OP_BE >= op_q[2], "Robust",
    default = "Neutral"
  )]

  # INV tercile
  inv_q <- quantile(port_uni$INV, probs = c(0.30, 0.70), na.rm = TRUE)
  port_uni[, INVGrp := fcase(
    INV <= inv_q[1], "Conservative",   # low growth
    INV >= inv_q[2], "Aggressive",      # high growth
    default = "Neutral"
  )]

  # Forward return (sig_date → ret_date) using ret_date row (Ret = monthly cumulative)
  # RAW_ME$Ret는 월간 단위 수익률 (rolling)
  # 정확하게는 sig_date+1 ~ ret_date의 cumulative — 본 데이터는 일간 → 월말 ret 컬럼이 정확.
  # 단순화: ret_date 시점의 Ret = (ret_date_close - sig_date_close)/sig_date_close
  ret_t1 <- RAW_ME[Date == ret_date, .(Ticker, Ret_fwd = Ret)]
  port_uni <- merge(port_uni, ret_t1, by = "Ticker")
  port_uni <- port_uni[is.finite(Ret_fwd)]

  # ----- Value-weighted within each portfolio -----
  vw_port <- function(dt, grp_col) {
    dt2 <- copy(dt)
    dt2[, w_grp := MarketCap_t / sum(MarketCap_t, na.rm = TRUE), by = c("SizeGrp", grp_col)]
    dt2[, .(PortRet = sum(w_grp * Ret_fwd, na.rm = TRUE),
            N = .N),
        by = c("SizeGrp", grp_col)]
  }

  bm_ports  <- vw_port(port_uni, "BMGrp")
  op_ports  <- vw_port(port_uni, "OPGrp")
  inv_ports <- vw_port(port_uni, "INVGrp")

  # ----- Factor returns (Fama-French 1993/2015) -----
  # SMB_BM = ((SH+SN+SL)/3) - ((BH+BN+BL)/3)  (Size from BM 2×3)
  # HML    = ((SH+BH)/2) - ((SL+BL)/2)
  # SMB_OP = ((SR+SN+SW)/3) - ((BR+BN+BW)/3)
  # RMW    = ((SR+BR)/2) - ((SW+BW)/2)
  # SMB_INV = ((SC+SN+SA)/3) - ((BC+BN+BA)/3)
  # CMA    = ((SC+BC)/2) - ((SA+BA)/2)
  # SMB    = (SMB_BM + SMB_OP + SMB_INV) / 3

  pick <- function(dt, sz, gr, grp_col) {
    val <- dt[get(grp_col) == gr & SizeGrp == sz, PortRet]
    if (length(val) == 0 || !is.finite(val)) return(NA_real_)
    val[1]
  }

  SH <- pick(bm_ports, "S", "Value",   "BMGrp")
  SN <- pick(bm_ports, "S", "Neutral", "BMGrp")
  SL <- pick(bm_ports, "S", "Growth",  "BMGrp")
  BH <- pick(bm_ports, "B", "Value",   "BMGrp")
  BN <- pick(bm_ports, "B", "Neutral", "BMGrp")
  BL <- pick(bm_ports, "B", "Growth",  "BMGrp")

  SR <- pick(op_ports, "S", "Robust",  "OPGrp")
  SO_N <- pick(op_ports, "S", "Neutral","OPGrp")
  SW <- pick(op_ports, "S", "Weak",    "OPGrp")
  BR <- pick(op_ports, "B", "Robust",  "OPGrp")
  BO_N <- pick(op_ports, "B", "Neutral","OPGrp")
  BW <- pick(op_ports, "B", "Weak",    "OPGrp")

  SC <- pick(inv_ports, "S", "Conservative","INVGrp")
  SI_N <- pick(inv_ports, "S", "Neutral",   "INVGrp")
  SA <- pick(inv_ports, "S", "Aggressive", "INVGrp")
  BC <- pick(inv_ports, "B", "Conservative","INVGrp")
  BI_N <- pick(inv_ports, "B", "Neutral",   "INVGrp")
  BA <- pick(inv_ports, "B", "Aggressive", "INVGrp")

  SMB_BM  <- mean(c(SH, SN, SL), na.rm = TRUE) - mean(c(BH, BN, BL), na.rm = TRUE)
  SMB_OP  <- mean(c(SR, SO_N, SW), na.rm = TRUE) - mean(c(BR, BO_N, BW), na.rm = TRUE)
  SMB_INV <- mean(c(SC, SI_N, SA), na.rm = TRUE) - mean(c(BC, BI_N, BA), na.rm = TRUE)
  SMB_v2  <- mean(c(SMB_BM, SMB_OP, SMB_INV), na.rm = TRUE)

  HML <- mean(c(SH, BH), na.rm = TRUE) - mean(c(SL, BL), na.rm = TRUE)
  RMW <- mean(c(SR, BR), na.rm = TRUE) - mean(c(SW, BW), na.rm = TRUE)
  CMA <- mean(c(SC, BC), na.rm = TRUE) - mean(c(SA, BA), na.rm = TRUE)

  results[[length(results) + 1]] <- data.table(
    Date_form = sd,                  # weight formation
    Date      = ret_date,             # return realization (월말)
    SMB_v2 = SMB_v2,
    HML = HML,
    RMW = RMW,
    CMA = CMA,
    n_uni = nrow(port_uni)
  )

  if (i %% 50 == 0) cat(sprintf("    %d/%d processed (sig_date=%s, fy=%d, n_uni=%d)\n",
                                 i, length(sig_dates), as.character(sd), fy, nrow(port_uni)))
}

# Align Date to existing kr_factor_returns.parquet's month-end (last trading date per month)
# (필요시) — 우선 직접 비교용으로 v2 그대로 두고, merge 시 month-mapping 적용
# Existing kr_factor_returns.parquet의 Date도 RAW_ME 기반이므로 일치해야 정상.

ff5_v2 <- rbindlist(results, fill = TRUE)
cat("[4] 6-portfolio formation 완료: ", nrow(ff5_v2), "월 산출\n")
cat("    HML  range: ", as.character(min(ff5_v2$Date)), "~", as.character(max(ff5_v2$Date)), "\n")
cat("    HML  mean : ", round(mean(ff5_v2$HML, na.rm=TRUE)*100, 4), "% / sd: ", round(sd(ff5_v2$HML, na.rm=TRUE)*100, 4), "%\n")
cat("    RMW  mean : ", round(mean(ff5_v2$RMW, na.rm=TRUE)*100, 4), "% / sd: ", round(sd(ff5_v2$RMW, na.rm=TRUE)*100, 4), "%\n")
cat("    CMA  mean : ", round(mean(ff5_v2$CMA, na.rm=TRUE)*100, 4), "% / sd: ", round(sd(ff5_v2$CMA, na.rm=TRUE)*100, 4), "%\n")

# ============ 5. 기존 MKT/SMB/WML 병합 (Date를 calendar month-end로 정규화) ============
cat("[5] 기존 MKT/SMB/WML 병합...\n")
ex <- as.data.table(read_parquet(".cache/kr_factor_returns.parquet"))
ex[, Date := as.Date(Date)]
ex[, YM := format(Date, "%Y-%m")]
# v2의 ret_date도 YM 기반 매칭
ff5_v2[, YM := format(Date, "%Y-%m")]

# 합치기: YM 기반 inner-join 후 ex의 Date를 보존 (canonical)
combined <- merge(ex[, .(YM, Date, MKT, SMB, WML)],
                  ff5_v2[, .(YM, HML_v2 = HML, RMW_v2 = RMW, CMA_v2 = CMA, n_obs_meta = n_uni)],
                  by = "YM", all.x = TRUE)
combined[, YM := NULL]

# 결과: HML/RMW/CMA는 v2로 대체, MKT/SMB/WML은 기존 사용
combined[, HML := HML_v2]
combined[, RMW := RMW_v2]
combined[, CMA := CMA_v2]
combined[, c("HML_v2", "RMW_v2", "CMA_v2") := NULL]

# RF (KORIBOR3M / 12, monthly)
# 단순 가정: 0 (이미 ex의 MKT가 excess return으로 처리됨이 일반적이지만 명시 필요)
combined[, RF := 0]   # FIXME: 추후 ECOS KORIBOR 통합 시 갱신

setcolorder(combined, c("Date", "MKT", "SMB", "HML", "WML", "RMW", "CMA", "RF", "n_obs_meta"))
setorder(combined, Date)

cat("  combined: ", nrow(combined), "월 / col: ", paste(names(combined), collapse=","), "\n")
cat("  HML n_nonNA: ", sum(!is.na(combined$HML)), "(이전:", sum(!is.na(ex$HML)), ")\n")
cat("  RMW n_nonNA: ", sum(!is.na(combined$RMW)), "(이전:", sum(!is.na(ex$RMW)), ")\n")
cat("  CMA n_nonNA: ", sum(!is.na(combined$CMA)), "(이전:", sum(!is.na(ex$CMA)), ")\n")

# ============ 6. Validation: overlap correlation 검증 ============
cat("[6] Overlap validation (vs 기존 RMW/CMA 2017+)...\n")
ex_old <- merge(
  ex[!is.na(HML), .(Date, HML_old = HML, RMW_old = RMW, CMA_old = CMA)],
  ff5_v2[, .(Date, HML_v2 = HML, RMW_v2 = RMW, CMA_v2 = CMA)],
  by = "Date"
)
ex_old <- ex_old[!is.na(RMW_old) & !is.na(RMW_v2) & !is.na(CMA_old) & !is.na(CMA_v2) & !is.na(HML_old) & !is.na(HML_v2)]

if (nrow(ex_old) > 10) {
  cor_hml <- cor(ex_old$HML_old, ex_old$HML_v2)
  cor_rmw <- cor(ex_old$RMW_old, ex_old$RMW_v2)
  cor_cma <- cor(ex_old$CMA_old, ex_old$CMA_v2)
  cat(sprintf("  overlap n=%d (2017+ 구간)\n", nrow(ex_old)))
  cat(sprintf("  cor(HML_old, HML_v2) = %.3f\n", cor_hml))
  cat(sprintf("  cor(RMW_old, RMW_v2) = %.3f\n", cor_rmw))
  cat(sprintf("  cor(CMA_old, CMA_v2) = %.3f\n", cor_cma))
} else {
  cat("  overlap insufficient (<10 obs)\n")
  cor_hml <- NA; cor_rmw <- NA; cor_cma <- NA
}

# ============ 7. 출력 ============
cat("[7] kr_factor_returns_v2.parquet 저장...\n")
out_path <- ".cache/kr_factor_returns_v2.parquet"
write_parquet(combined, out_path)
cat("  saved:", out_path, "(", round(file.size(out_path)/1024, 1), "KB)\n")

# Stats summary
saveRDS(list(
  validation_overlap = list(
    n = nrow(ex_old),
    cor_hml = cor_hml,
    cor_rmw = cor_rmw,
    cor_cma = cor_cma
  ),
  factor_stats = list(
    HML_mean_pct = round(mean(combined$HML, na.rm=TRUE)*100, 4),
    HML_sd_pct = round(sd(combined$HML, na.rm=TRUE)*100, 4),
    HML_n = sum(!is.na(combined$HML)),
    RMW_mean_pct = round(mean(combined$RMW, na.rm=TRUE)*100, 4),
    RMW_sd_pct = round(sd(combined$RMW, na.rm=TRUE)*100, 4),
    RMW_n = sum(!is.na(combined$RMW)),
    CMA_mean_pct = round(mean(combined$CMA, na.rm=TRUE)*100, 4),
    CMA_sd_pct = round(sd(combined$CMA, na.rm=TRUE)*100, 4),
    CMA_n = sum(!is.na(combined$CMA))
  )
), "04_Research/worktask_scratch/WT-D20260425_009/step0_validation.rds")

cat("\n=== Step 0 완료 ===\n")
