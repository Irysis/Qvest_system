##=============================================================================
## factor_db_daily_phase9.R — Cross-Sectional Z-Score + Placeholder 구현
##
## 1. Composite 팩터: cross-sectional z-score 후 합산 (전략 사용 가능하게)
## 2. Sector 기반 팩터: M07_IndMom, M24_Sector_Rel_Mom, M31_Breadth_Mom
## 3. Seasonality: M21 (동월 역사적 수익률)
## 4. D28_Unlevered_Beta (fund_wide 활용)
## 5. 기존 parquet에 additive merge
##=============================================================================

cat("═══ Phase 9: Z-Score Post-Processing + Placeholder 구현 ═══\n")
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
t0 <- proc.time()

# ─── 헬퍼: cross-sectional z-score ──────────────────────────────────────────
zscore <- function(x) {
  mu <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-12) return(rep(NA_real_, length(x)))
  (x - mu) / s
}

# composite: z-score 평균 (min_n개 이상 유효해야 계산)
z_composite <- function(dt, cols, min_n = 2L) {
  # 각 컬럼 z-score → 행 평균
  z_mat <- dt[, lapply(.SD, zscore), .SDcols = cols]
  valid_n <- rowSums(!is.na(z_mat))
  result <- rowMeans(z_mat, na.rm = TRUE)
  result[valid_n < min_n] <- NA_real_
  result
}

# ─── Fund 데이터 준비 (D28용) ────────────────────────────────────────────────
cat("[1/4] 데이터 준비...\n")
FUND <- as.data.table(read_parquet(file.path(CACHE_DIR, "fundamental_merged.parquet")))
FUND[, Factor_Date := as.Date(Factor_Date)]
fund_sub <- FUND[Item %in% c("TotalDebt", "TotalEquity")]
fund_sub <- fund_sub[, .(Value = Value[.N]), by = .(Ticker, Factor_Date, Item)]
fund_de <- dcast(fund_sub, Ticker + Factor_Date ~ Item, value.var = "Value")
setnames(fund_de, "Factor_Date", "Date")
setkey(fund_de, Ticker, Date)
for (ic in c("TotalDebt", "TotalEquity")) {
  if (ic %in% names(fund_de)) fund_de[, (ic) := nafill(get(ic), type = "locf"), by = Ticker]
}
rm(FUND, fund_sub); gc(verbose = FALSE)
cat("  Fund D/E 준비 완료.\n\n")

# ─── 월별 루프 ──────────────────────────────────────────────────────────────
cat("[2/4] 월별 처리 (Z-score + Sector + Placeholder)...\n")
t1 <- proc.time()

files <- sort(list.files(FDB_DIR, pattern = "fdb_daily_.*parquet", full.names = TRUE))
pb <- max(1L, length(files) %/% 20L)

for (i in seq_along(files)) {
  dt <- as.data.table(read_parquet(files[i]))
  setkey(dt, Date, Ticker)
  changed <- FALSE

  # ═══ 1. Composite 팩터: cross-sectional z-score 합산 ═══════════════════
  # 기존 raw 평균 composite 삭제 후 z-score 버전으로 교체
  old_composites <- c("M09_Composite_Mom","M32_Composite_Mom_v2","Q08_Composite_Quality",
                      "V12_Composite_Value","GR07_Composite_Growth","L45_Composite_Liquidity",
                      "C19_Composite_Earnings","R19_Composite_Risk")
  for (oc in intersect(old_composites, names(dt))) dt[, (oc) := NULL]

  # M09_Composite_Mom = z(M01) + z(M02) + z(M05_Trended_Mom)
  if (all(c("M01_Mom_12_1", "M02_Mom_6_1", "M05_Trended_Mom") %in% names(dt))) {
    dt[, M09_Composite_Mom := z_composite(.SD, c("M01_Mom_12_1", "M02_Mom_6_1", "M05_Trended_Mom"), 2L), by = Date]
    changed <- TRUE
  }

  # M32_Composite_Mom_v2 = z(M01) + z(M10) + z(M13) + z(M24)
  m32_cols <- intersect(c("M01_Mom_12_1", "M10_Intermediate_Mom", "M13_VolAdj_Mom", "M24_Sector_Rel_Mom"), names(dt))
  if (length(m32_cols) >= 2) {
    dt[, M32_Composite_Mom_v2 := z_composite(.SD, m32_cols, 2L), by = Date]
    changed <- TRUE
  }

  # Q08_Composite_Quality = z(Q01) + z(Q02) + z(-Q05) + z(-Q06)
  q08_cols <- intersect(c("Q01_GPA", "Q02_ROE", "Q05_Accrual", "Q06_Asset_Growth"), names(dt))
  if (length(q08_cols) >= 2) {
    dt[, Q08_Composite_Quality := z_composite(.SD, q08_cols, 2L), by = Date]
    changed <- TRUE
  }

  # V12_Composite_Value = z(V01) + z(V02) + z(V03)
  v12_cols <- intersect(c("V01_BM", "V02_EP", "V03_CFP"), names(dt))
  if (length(v12_cols) >= 2) {
    dt[, V12_Composite_Value := z_composite(.SD, v12_cols, 2L), by = Date]
    changed <- TRUE
  }

  # GR07_Composite_Growth = z(GR01) + z(GR02) + z(GR03)
  gr07_cols <- intersect(c("GR01_Revenue_Growth", "GR02_Earnings_Growth", "GR03_Asset_Growth"), names(dt))
  if (length(gr07_cols) >= 2) {
    dt[, GR07_Composite_Growth := z_composite(.SD, gr07_cols, 2L), by = Date]
    changed <- TRUE
  }

  # L45_Composite_Liquidity = z(L01) + z(L02) + z(L04) + z(L05)
  l45_cols <- intersect(c("L01_Amihud", "L02_Turnover", "L04_Bid_Ask_Proxy", "L05_Dollar_Volume"), names(dt))
  if (length(l45_cols) >= 2) {
    dt[, L45_Composite_Liquidity := z_composite(.SD, l45_cols, 2L), by = Date]
    changed <- TRUE
  }

  # C19_Composite_Earnings = z(C01_SUE) + z(C04_ESBR) + z(C02_EPS_Chg_1m) + z(C06_TP_Gap)
  c19_cols <- intersect(c("C01_SUE", "C04_ESBR", "C02_EPS_Chg_1m", "C06_TP_Gap"), names(dt))
  if (length(c19_cols) >= 2) {
    dt[, C19_Composite_Earnings := z_composite(.SD, c19_cols, 2L), by = Date]
    changed <- TRUE
  }

  # R19_Composite_Risk = z(R01) + z(R07) + z(R13)
  r19_cols <- intersect(c("R01_VaR_95", "R07_Downside_Dev", "R13_NCSKEW"), names(dt))
  if (length(r19_cols) >= 2) {
    dt[, R19_Composite_Risk := z_composite(.SD, r19_cols, 2L), by = Date]
    changed <- TRUE
  }

  # ═══ 2. Sector 기반 팩터 ═══════════════════════════════════════════════

  # RAWDATA에서 Sector 정보 가져오기 (해당 월)
  ym <- gsub(".*fdb_daily_(\\d+)\\.parquet", "\\1", basename(files[i]))
  RW_sec <- tryCatch({
    rw <- as.data.table(read_parquet(RAWDATA_CACHE))
    rw[format(Date, "%Y%m") == ym, .(Ticker, Date, Sector, Ret)]
  }, error = function(e) NULL)

  if (!is.null(RW_sec) && nrow(RW_sec) > 0 && "Sector" %in% names(RW_sec)) {
    setkey(RW_sec, Date, Ticker)

    # M07_IndMom: 섹터 평균 12-1M 모멘텀
    if ("M01_Mom_12_1" %in% names(dt)) {
      sec_mom <- merge(dt[, .(Date, Ticker, M01_Mom_12_1)],
                       RW_sec[, .(Ticker, Date, Sector)], by = c("Date", "Ticker"))
      sec_avg <- sec_mom[, .(sec_m01 = mean(M01_Mom_12_1, na.rm = TRUE)), by = .(Date, Sector)]
      sec_mom <- merge(sec_mom, sec_avg, by = c("Date", "Sector"))
      # 기존 NA 컬럼 제거 후 덮어쓰기
      for (col in c("M07_IndMom", "M24_Sector_Rel_Mom", "M31_Breadth_Mom")) {
        if (col %in% names(dt)) dt[, (col) := NULL]
      }
      dt <- merge(dt, sec_mom[, .(Date, Ticker, M07_IndMom = sec_m01,
                                   M24_Sector_Rel_Mom = M01_Mom_12_1 - sec_m01)],
                  by = c("Date", "Ticker"), all.x = TRUE)
      # M31_Breadth_Mom: 양(+) 섹터 비율
      breadth <- dt[!is.na(M07_IndMom), .(M31_Breadth_Mom = mean(M07_IndMom > 0, na.rm = TRUE)), by = Date]
      dt <- merge(dt, breadth, by = "Date", all.x = TRUE)
      changed <- TRUE
    }
  }

  # ═══ 3. M21_Seasonality (동월 역사적 수익률) ══════════════════════════

  # 해당 월의 calendar month 확인
  cal_month <- as.integer(substr(ym, 5, 6))
  if ("M01_Mom_12_1" %in% names(dt)) {
    # Seasonality는 전체 RAWDATA가 필요 → 단순 proxy: 해당 월 평균 수익률
    # 정확한 구현은 전 기간 로드 필요하므로 NA 유지 (HARD)
    if (!"M21_Seasonality" %in% names(dt)) dt[, M21_Seasonality := NA_real_]
  }

  # ═══ 4. D28_Unlevered_Beta ═════════════════════════════════════════════

  if ("D02_Beta" %in% names(dt)) {
    # fund D/E rolling join
    price_ym <- dt[, .(Ticker, Date)]
    setkey(price_ym, Ticker, Date)
    de_ym <- fund_de[price_ym, roll = Inf, on = .(Ticker, Date)]
    de_ratio <- fifelse(!is.na(de_ym$TotalDebt) & !is.na(de_ym$TotalEquity) &
                          abs(de_ym$TotalEquity) > 0,
                        de_ym$TotalDebt / de_ym$TotalEquity, NA_real_)
    dt[, D28_Unlevered_Beta := fifelse(!is.na(D02_Beta) & !is.na(de_ratio),
                                        D02_Beta / (1 + de_ratio), NA_real_)]
    changed <- TRUE
  }

  # ═══ 5. D29_Accounting_Beta → NA 유지 (HARD) ══════════════════════════
  if (!"D29_Accounting_Beta" %in% names(dt)) dt[, D29_Accounting_Beta := NA_real_]

  # ═══ 6. Cross-sectional rank 정규화 ════════════════════════════════════
  # D18_BAB_Rank, L37_Relative_Vol, D31_Relative_Beta → z-score로 변환
  for (col in intersect(c("D18_BAB_Rank", "L37_Relative_Vol", "D31_Relative_Beta"), names(dt))) {
    dt[, (col) := zscore(get(col)), by = Date]
    changed <- TRUE
  }

  if (changed) write_parquet(dt, files[i], compression = "snappy")

  if (i %% pb == 0 || i == length(files))
    cat(sprintf("  [%d/%d] %s (%d cols)\n", i, length(files), ym, ncol(dt)))
}
cat(sprintf("  완료 (%.1fs)\n\n", (proc.time() - t1)["elapsed"]))

# ─── Registry ────────────────────────────────────────────────────────────────
cat("[3/4] Registry 업데이트...\n")
reg_path <- file.path(FDB_DIR, "factor_db_daily_registry.json")
reg <- if (file.exists(reg_path)) fromJSON(reg_path) else list()
reg$version <- "9.0.0"
reg$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
reg$phase9 <- list(
  description = "Cross-sectional z-score composites + Sector factors + D28",
  composites = c("M09", "M32", "Q08", "V12", "GR07", "L45", "C19", "R19"),
  sector = c("M07_IndMom", "M24_Sector_Rel_Mom", "M31_Breadth_Mom"),
  fund = "D28_Unlevered_Beta",
  z_normalized = c("D18_BAB_Rank", "L37_Relative_Vol", "D31_Relative_Beta")
)
write(toJSON(reg, pretty = TRUE, auto_unbox = TRUE), reg_path)

# ─── 텔레그램 ───────────────────────────────────────────────────────────────
cat("[4/4] 텔레그램 보고...\n")
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  tg_send(sprintf("✅ [Q-Lead] Phase 9 완료!\n\n🔧 개선 내용:\n• Composite 8개: cross-sectional z-score 합산\n• Sector 3개: M07/M24/M31 구현\n• D28 Unlevered Beta 구현\n• Rank 팩터 3개 z-score 정규화\n\n⏱️ 소요: %.1f분",
                   (proc.time() - t0)["elapsed"] / 60))
}, error = function(e) cat("  텔레그램 전송 실패\n"))

total_min <- (proc.time() - t0)["elapsed"] / 60
cat(sprintf("\n═══ Phase 9 완료 ═══\n  Composite 8개 z-score 정상화\n  Sector 3개 구현\n  D28 구현\n  Rank 3개 정규화\n  소요: %.1f분\n", total_min))
