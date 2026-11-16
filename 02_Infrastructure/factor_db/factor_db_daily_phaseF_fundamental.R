##=============================================================================
## factor_db_daily_phaseF_fundamental.R — 일간 팩터 DB 재무 팩터(새 정의) 덮어쓰기
##
## 2026-11-16 도훈 "펀더멘털 데이터 캐시는 분기파일, 연간파일 하나씩 … 펀더멘털 팩터 정의를 새롭게 만든
##   펀더멘털 데이터 캐시 기반으로 재정의해" — 월간 팩터 DB 와 같은 정의(compute_fundamental.R · fund_access.R)를
##   일간 파일에도 쓴다. 단계 6 · 8 의 옛 재무 계산(fundamental_merged.parquet)은 껐다(빈 재무 표 → 옛 열 = NA).
## 이 단계가 하는 일(월 파일마다 · 거래일마다):
##   ① compute_fundamental(그날 RAWDATA 시가총액, 그날) — 재무 팩터 전부(결정일 최신 · Factor_Date <= 그날)
##   ② R17 · R18 · D60 · D29 · D28(그날 D02_Beta 열 사용) · S02(시가총액 × 유동비율) — 월간 모듈과 같은 식
##   ③ V09 · V12 — 컨센서스 열(V04 · V05 · V06)은 그대로 쓰고 실적 EPS · CFP 만 새 캐시로
##   ④ 옛 재무 열(LEGACY_FUND_COLS)과 ①~③ 이름을 지우고 새 값으로 붙여 원자 교체
## PIT: 재무 값은 fa_latest(Factor_Date <= 결정일 · 묵은 값 분기 15 · 연간 24개월) · 시가총액은 그날 종가 기준(일간 DB 관례).
## 실행: run_fdb_rebuild.sh 가 단계 8 뒤에 별도 R 프로세스로 부른다 · 단일 월 = 환경변수 FDB_INCR_YM=YYYYMM.
##=============================================================================

cat("═══ Phase F: 재무 팩터(새 정의) 덮어쓰기 ═══\n")
cat("시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

suppressPackageStartupMessages({ library(data.table); library(arrow) })

.SELF_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) file.path(getwd(), "factor_db"))
INFRA_DIR <- dirname(.SELF_DIR)
source(file.path(INFRA_DIR, "config.R"))
source(file.path(.SELF_DIR, "fund_access.R"))
source(file.path(.SELF_DIR, "compute_fundamental.R"))

FDB_DIR <- Sys.getenv("FDB_PHASEF_DIR", file.path(CACHE_DIR, "factor_db_daily"))   # 시험용 사본 폴더 = FDB_PHASEF_DIR
t0 <- proc.time()

# 단계 6 · 8 이 쓰던 옛 재무 열 — 새 정의로 다시 만들지 않는 열은 지운다(옛 정의 값이 남지 않게).
LEGACY_FUND_COLS <- c(
  "Q01_GPA","Q02_ROE","Q03_ROA","Q05_Accrual","Q09_CFOA","Q10_Gross_Margin","Q11_Net_Margin","Q12_Asset_Turnover",
  "Q13_Fin_Leverage","Q14_Current_Ratio","Q15_Debt_to_Equity","Q16_Debt_to_Assets","Q17_ROIC","Q18_Op_Leverage",
  "Q19_Cash_to_Assets","Q26_RnD_Intensity","Q28_Cash_Conversion","Q29_Inventory_Turnover","Q30_Receivables_Turnover",
  "Q31_WC_to_Assets","Q32_Interest_Coverage","Q35_CashBased_OpProf","V01_BM","V02_EP","V03_CFP","V08_PSR",
  "V10_FCF_Yield","V11_Shareholder_Yield","V16_Tobins_Q","V18_AM","V20_SP","V24_Residual_Income","D60_Leverage",
  "R17_Market_Leverage","R18_Book_Leverage","AC01_Total_Accruals_CF","AC05_NOA","AC10_Pct_Accruals",
  "IN01_CapEx_to_Assets","IN02_CapEx_to_Revenue","V07_EV_EBITDA","V13_EV_Sales","V14_EBIT_EV",
  "GR01_Revenue_Growth","GR02_Earnings_Growth","GR03_Asset_Growth","Q06_Asset_Growth","Q21_Revenue_Growth",
  "Q22_Earnings_Growth","Q34_GP_Growth","AC06_Comprehensive_Accruals","AC11_Accruals_to_Assets","AC18_Accrual_Quality",
  "AC21_CF_to_Accrual_Ratio","AC24_NOA_Growth","AC25_Accrual_Size_Interaction","AC17_Accrual_Reversal",
  "AC22_Accrual_Volatility","AC23_Accrual_Persistence","GR04_GPA_Growth","GR05_ROE_Growth","GR06_OCF_Growth",
  "IN05_Net_Debt_Issuance","IN06_Investment_to_Assets","Q04_Piotroski_F","Q07_Earnings_Stability",
  "Q23_Sustainable_Growth","Q24_Altman_Z","Q25_Ohlson_O","Q33_Earnings_Persistence","V09_PEG","V15_NetDebt_Adj_EP",
  "V17_Payout_Ratio","V19_Debt_to_Market","V22_FCFF_EV","Q27_CapEx_to_Rev","GR07_Composite_Growth",
  "Q08_Composite_Quality","V12_Composite_Value","V23_RAFI_Weight","D28_Unlevered_Beta","D29_Accounting_Beta",
  "S02_Float_Size")

z_safe <- function(x) { s <- sd(x, na.rm = TRUE); if (!is.finite(s) || s < 1e-8) return(rep(NA_real_, length(x))); (x - mean(x, na.rm = TRUE)) / s }

RW <- as.data.table(read_parquet(RAWDATA_CACHE, col_select = c("Ticker", "Date", "Close", "Size", "Float")))
RW[, Date := as.Date(Date)]
setkey(RW, Date)

# 하루치 재무 팩터(long: Ticker · Factor_Name · Raw_Value)
phaseF_day <- function(d, ch_d) {
  raw_d <- RW[.(d), nomatch = 0L]
  raw_d <- raw_d[is.finite(Size) & Size > 0]
  if (!nrow(raw_d)) return(NULL)
  out <- list(tryCatch(compute_fundamental(raw_d, d), error = function(e) NULL))
  mc <- raw_d[, .(Ticker, MC = Size, Close, Float)]
  q <- tryCatch(fa_latest(d, "q", c("TotalDebt", "TotalAssets", "BookEquity", "DebtToEquity", "EPSParentAdj")), error = function(e) NULL)
  if (!is.null(q) && nrow(q)) {
    for (k in setdiff(c("TotalDebt", "TotalAssets", "BookEquity", "DebtToEquity", "EPSParentAdj"), names(q))) q[, (k) := NA_real_]
    x <- merge(mc, q, by = "Ticker")
    out[[length(out) + 1L]] <- rbind(
      x[is.finite(TotalDebt), .(Ticker, Factor_Name = "R17_Market_Leverage", Raw_Value = -TotalDebt / MC)],
      x[is.finite(TotalDebt) & is.finite(TotalAssets) & TotalAssets > 0, .(Ticker, Factor_Name = "R18_Book_Leverage", Raw_Value = -TotalDebt / TotalAssets)],
      x[is.finite(DebtToEquity), .(Ticker, Factor_Name = "D60_Leverage", Raw_Value = -DebtToEquity)])
    if ("D02_Beta" %in% names(ch_d)) {
      b <- merge(ch_d[is.finite(D02_Beta), .(Ticker, beta = D02_Beta)], x[is.finite(TotalDebt) & is.finite(BookEquity) & BookEquity > 0], by = "Ticker")
      out[[length(out) + 1L]] <- b[, .(Ticker, Factor_Name = "D28_Unlevered_Beta", Raw_Value = -beta / (1 + TotalDebt / BookEquity))]
    }
    # V09 PEG = fPER / (EPS 성장% ) · 컨센서스 EPS = 종가 / V04(fPER) · 실적 EPS = EPSParentAdj(TTM) — compute_value.R 과 같은 식
    if ("V04_fPER" %in% names(ch_d)) {
      v <- merge(ch_d[is.finite(V04_fPER) & V04_fPER != 0, .(Ticker, V04 = V04_fPER)], x[, .(Ticker, Close, EPSParentAdj)], by = "Ticker")
      v[, eps_1y := Close / V04]
      v[, g := fifelse(is.finite(EPSParentAdj) & abs(EPSParentAdj) > 1e-6, (eps_1y - EPSParentAdj) / abs(EPSParentAdj), NA_real_)]
      out[[length(out) + 1L]] <- v[is.finite(g) & g > 0.01, .(Ticker, Factor_Name = "V09_PEG", Raw_Value = V04 / (g * 100))]
    }
  }
  a <- tryCatch(fa_latest(d, "a", "AccountingBeta"), error = function(e) NULL)
  if (!is.null(a) && nrow(a) && "AccountingBeta" %in% names(a))
    out[[length(out) + 1L]] <- a[is.finite(AccountingBeta), .(Ticker, Factor_Name = "D29_Accounting_Beta", Raw_Value = -AccountingBeta)]
  # S02 = -log(시가총액 × 유동비율%) · 유동비율 없으면 -log(시가총액) — compute_size.R 과 같은 식
  out[[length(out) + 1L]] <- mc[, .(Ticker, Factor_Name = "S02_Float_Size",
                                    Raw_Value = fifelse(is.finite(Float) & Float > 0, -log(MC * Float / 100), -log(MC)))]
  res <- rbindlist(out, use.names = TRUE)
  if (!nrow(res)) return(NULL)
  res <- res[is.finite(Raw_Value)]
  # V12 = 평균 z(-fPER, -fPBR, fDY, CFP) · 성분 2개 이상 — compute_value.R 과 같은 식(CFP = 새 V03)
  cfp <- res[Factor_Name == "V03_CFP", .(Ticker, V03 = Raw_Value)]
  comp <- merge(ch_d[, intersect(c("Ticker", "V04_fPER", "V05_fPBR", "V06_fDY"), names(ch_d)), with = FALSE], cfp, by = "Ticker", all = TRUE)
  for (k in setdiff(c("V04_fPER", "V05_fPBR", "V06_fDY"), names(comp))) comp[, (k) := NA_real_]
  comp[, `:=`(a = fifelse(is.finite(V04_fPER) & V04_fPER > 0, z_safe(-V04_fPER), NA_real_),
              b = fifelse(is.finite(V05_fPBR) & V05_fPBR > 0, z_safe(-V05_fPBR), NA_real_),
              c = fifelse(is.finite(V06_fDY), z_safe(V06_fDY), NA_real_),
              e = fifelse(is.finite(V03), z_safe(V03), NA_real_))]
  comp[, n := is.finite(a) + is.finite(b) + is.finite(c) + is.finite(e)]
  v12 <- comp[n >= 2L, .(Ticker, Factor_Name = "V12_Composite_Value", Raw_Value = rowMeans(cbind(a, b, c, e), na.rm = TRUE))]
  rbind(res, v12)
}

files <- sort(list.files(FDB_DIR, pattern = "^fdb_daily_\\d{6}\\.parquet$", full.names = TRUE))
months <- sub("^fdb_daily_(\\d{6})\\.parquet$", "\\1", basename(files))
INCR_YM <- Sys.getenv("FDB_INCR_YM", "")
if (nzchar(INCR_YM)) { k <- months == INCR_YM; files <- files[k]; months <- months[k] }
FROM_YM <- Sys.getenv("FDB_PHASEF_FROM", "")
if (nzchar(FROM_YM)) { k <- months >= FROM_YM; files <- files[k]; months <- months[k] }
cat(sprintf("[F] 월 파일 %d개\n", length(files)))
pb <- max(1L, length(files) %/% 20L)

for (i in seq_along(files)) {
  ch <- as.data.table(read_parquet(files[i]))
  ch[, Date := as.Date(Date)]
  dates <- sort(unique(ch$Date))
  long <- rbindlist(lapply(dates, function(d) { r <- phaseF_day(d, ch[Date == d]); if (!is.null(r)) r[, Date := d]; r }), use.names = TRUE)
  drop <- intersect(names(ch), unique(c(LEGACY_FUND_COLS, if (nrow(long)) unique(long$Factor_Name))))
  if (length(drop)) ch[, (drop) := NULL]
  if (nrow(long)) {
    wide <- dcast(long, Date + Ticker ~ Factor_Name, value.var = "Raw_Value", fun.aggregate = function(v) v[1L])
    ch <- merge(ch, wide, by = c("Date", "Ticker"), all.x = TRUE)
  }
  for (k in setdiff(LEGACY_FUND_COLS, names(ch))) ch[, (k) := NA_real_]   # 옛 스키마 유지(새 정의가 안 만드는 열 = NA)
  setkey(ch, Date, Ticker)
  tmp <- paste0(files[i], ".phF.tmp")
  write_parquet(ch, tmp)
  if (!file.rename(tmp, files[i])) { unlink(files[i]); if (!file.rename(tmp, files[i])) stop("[F] 교체 실패: ", files[i]) }
  if (i %% pb == 0L || i == length(files))
    cat(sprintf("  [F] %d/%d %s · 열 %d · 재무 %d · %.0fs\n", i, length(files), months[i], ncol(ch),
                if (nrow(long)) uniqueN(long$Factor_Name) else 0L, (proc.time() - t0)["elapsed"]))
}
cat(sprintf("═══ Phase F 완료 (%.1f분) ═══\n", (proc.time() - t0)["elapsed"] / 60))
