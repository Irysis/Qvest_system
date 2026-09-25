##=============================================================================
## factor_db_daily_phase9b.R — D29/V21/RE04 버그 수정
##
## D29_Accounting_Beta: 다기간 ROE 회귀 (Fund 시계열)
## V21_Composite_Equity_Issuance: 5년 시가총액 변화 - 수익률 (전 기간 by=Ticker)
## RE04_HighVol_Beta: MRS percentile 기반 conditional beta (threshold 완화)
##=============================================================================

cat("═══ Phase 9b: D29/V21/RE04 수정 ═══\n")
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
# ★C11 2단계 수리(2026-09-25 · 재빌드 스모크 적발): 스탬프 가드(fdb_regime_c11_ok)는 현행 규칙 epoch 를
#   fred_avail_rules_meta() 로 읽는다. 9b 는 phase6·7 과 달리 **별도 R 프로세스로 혼자** 돌고, 이 줄이 없으면 그 함수가
#   없어 현행 키 = NA → 스탬프가 맞아도 MRS 전부 NA → RE04 전 기간 NA(fail-closed 가 상시 발화 — 수리한 C1 누적 백분위가
#   한 번도 산출되지 않는다). phase6·7 과 같은 순서로 S0 가용시점 층을 먼저 싣는다. 검사: 08_Tests/factor_db/test_phase9b_standalone_regime_key.R
source(file.path(INFRA_DIR, "data", "fred_availability.R"))
# PIT C1 수리(2026-09-24): 일간 fdb PIT 도우미(RE04 누적 백분위 · regime 스탬프 가드). 없으면 여기서 멈춘다.
source(file.path(.SELF_DIR, "factor_db_daily_pit.R"))

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")
OUT_START <- as.Date("1990-01-01")
t0 <- proc.time()

# ═══ 1. V21 + RE04: RAWDATA by=Ticker (Rcpp) ══════════════════════════════
cat("[1/4] V21 + RE04 계산 (by=Ticker Rcpp)...\n")
t1 <- proc.time()

RW <- as.data.table(read_parquet(RAWDATA_CACHE))
setkey(RW, Ticker, Date)
RW <- RW[Date >= as.Date("1984-01-01")]  # 1990 - 6년 look-back

BM <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
setnames(BM, "Ret", "BM_Ret", skip_absent = TRUE)
if ("BM_Ret" %in% names(RW)) RW[, BM_Ret := NULL]
RW <- BM[, .(Date, BM_Ret)][RW, on = "Date"]

REGIME <- as.data.table(read_parquet(file.path(CACHE_DIR, "regime_daily_v2.parquet")))
REGIME[, Date := as.Date(Date)]; setkey(REGIME, Date)
# ★PIT C11(2026-09-24 · 판정서 V-11): MRS 는 한국 날짜 d 행끼리 결합한다 — 생산자 수리판 스탬프(c11_avail_regime_key)
#   없으면 MRS 전부 NA → RE04 NA(fail-closed). 상세 = factor_db_daily_pit.R.
fdb_regime_c11_mask(REGIME, c("MRS"), file.path(CACHE_DIR, "regime_daily_v2.parquet"), label = "phase9b RE04")
RW <- REGIME[, .(Date, MRS)][RW, on = "Date"]

tk_counts <- RW[, .N, by = Ticker]
RW <- RW[Ticker %in% tk_counts[N >= 30L, Ticker]]
# ★PIT C1 수리(2026-09-24 · 판정서 1-4 · decision PIT-C11-CONVENTIONS ⑤ "RE04 는 검증 후"):
#   검증 = 운영 식(PART_VR)의 절단 불변성 — T 이후 행을 잘라내면 T 이전 RE04 값의 71.8~89.1% 가 바뀌었다
#   (표본 40종목 · T = 2008-12-31·2012-12-31·2016-06-30) → 구판 :64 의 종목별 전표본 frank/n 이 미래 MRS 로 과거
#   고변동 플래그를 정했다 = C1 확정. 수리판 = 결정일까지 누적 백분위(아래 주석이 적은 원래 의도 '해당 시점까지'):
#   날짜 d 의 플래그 = 그날 MRS 가 d 이하 한국 거래일 MRS 중 상위 30% 인가. 모집단 = 시장 MRS 일자열(상장기간 의존 제거).
RW <- fdb_attach_mrs_expanding_pct(RW)

PART_VR <- RW[, {
  ret <- as.double(Ret); sz <- as.double(Size); mrs <- as.double(MRS)
  bm <- as.double(BM_Ret); m <- .N

  # ─── V21: Composite Equity Issuance ──────────────────────────────────
  # CEI = log(ME_t / ME_{t-1260}) - cumret_1260
  # 5년(1260 거래일) 시가총액 변화에서 수익률 차감 = 순수 발행 효과
  sz_lag <- shift(sz, 1260L, type = "lag")
  cr1260 <- roll_cumret_cpp(ret, 1260L)
  V21_Composite_Equity_Issuance <- fifelse(
    !is.na(sz) & !is.na(sz_lag) & sz_lag > 0 & !is.na(cr1260),
    log(sz / sz_lag) - log(1 + cr1260), NA_real_)

  # ─── RE04: HighVol Beta ──────────────────────────────────────────────
  # 기존 문제: MRS > 50 조건이 너무 엄격 → 대부분 NA
  # 수정: MRS의 expanding percentile 상위 30% 구간에서 conditional beta
  # 즉, 해당 시점까지 MRS가 상위 30%인 날만 사용
  # (C1 수리 2026-09-24: 구판 frank(mrs)/sum(!is.na(mrs)) = 종목 전표본 순위 → 누적 백분위 MRS_Pct_Exp)
  mrs_pctile <- fifelse(!is.na(mrs), as.double(MRS_Pct_Exp), NA_real_)
  # 상위 30% = percentile > 0.7
  hi_vol_ret <- fifelse(!is.na(mrs_pctile) & mrs_pctile > 0.7, ret, NA_real_)
  hi_vol_bm <- fifelse(!is.na(mrs_pctile) & mrs_pctile > 0.7, bm, NA_real_)
  RE04_HighVol_Beta <- roll_beta_cpp(hi_vol_ret, hi_vol_bm, 252L)

  .(Date = Date, V21_Composite_Equity_Issuance, RE04_HighVol_Beta)
}, by = Ticker]

PART_VR <- PART_VR[Date >= OUT_START]
setkey(PART_VR, Date, Ticker)
PART_VR[, YM := format(Date, "%Y%m")]
cat(sprintf("  V21 valid: %d, RE04 valid: %d (%.1fs)\n\n",
            sum(!is.na(PART_VR$V21_Composite_Equity_Issuance)),
            sum(!is.na(PART_VR$RE04_HighVol_Beta)),
            (proc.time() - t1)["elapsed"]))

# ═══ 2. D29: Accounting Beta (Fund 시계열) ═════════════════════════════════
cat("[2/4] D29 Accounting Beta...\n")
t2 <- proc.time()

FUND <- as.data.table(read_parquet(file.path(CACHE_DIR, "fundamental_merged.parquet")))
FUND[, Factor_Date := as.Date(Factor_Date)]

# 종목별 ROE 시계열 구축
roe_data <- FUND[Item %in% c("NetIncome", "TotalEquity")]
roe_data <- roe_data[, .(Value = Value[.N]), by = .(Ticker, Factor_Date, Item)]
roe_wide <- dcast(roe_data, Ticker + Factor_Date ~ Item, value.var = "Value")
roe_wide[, ROE := fifelse(!is.na(NetIncome) & !is.na(TotalEquity) & abs(TotalEquity) > 0,
                           NetIncome / TotalEquity, NA_real_)]

# 시장 평균 ROE (cross-sectional median per Factor_Date)
mkt_roe <- roe_wide[!is.na(ROE), .(Mkt_ROE = median(ROE)), by = Factor_Date]
roe_wide <- merge(roe_wide, mkt_roe, by = "Factor_Date")

# 종목별 Accounting Beta = cov(ROE_firm, ROE_market) / var(ROE_market)
# 최소 4개 관측치 필요
acct_beta <- roe_wide[!is.na(ROE) & !is.na(Mkt_ROE), {
  if (.N < 4L) {
    .(Factor_Date = Factor_Date, D29_Accounting_Beta = NA_real_)
  } else {
    # expanding window: 각 시점까지의 누적 beta
    ab <- rep(NA_real_, .N)
    for (j in 4L:.N) {
      r <- ROE[1:j]; mr <- Mkt_ROE[1:j]
      v <- var(mr); if (is.na(v) || v < 1e-12) next
      ab[j] <- cov(r, mr) / v
    }
    .(Factor_Date = Factor_Date, D29_Accounting_Beta = ab)
  }
}, by = Ticker]

# 일간으로 forward-fill (rolling join)
setnames(acct_beta, "Factor_Date", "Date")
setkey(acct_beta, Ticker, Date)
# locf within ticker
acct_beta[, D29_Accounting_Beta := nafill(D29_Accounting_Beta, type = "locf"), by = Ticker]

cat(sprintf("  D29 valid: %d (%.1fs)\n\n",
            sum(!is.na(acct_beta$D29_Accounting_Beta)),
            (proc.time() - t2)["elapsed"]))

rm(FUND, roe_data, roe_wide, mkt_roe); gc(verbose = FALSE)

# ═══ 3. 월별 merge ═════════════════════════════════════════════════════════
cat("[3/4] 월별 merge...\n")
t3 <- proc.time()

files <- sort(list.files(FDB_DIR, pattern = "fdb_daily_.*parquet", full.names = TRUE))
months <- gsub(".*fdb_daily_(\\d+)\\.parquet", "\\1", basename(files))
pb <- max(1L, length(files) %/% 20L)

for (i in seq_along(files)) {
  ym <- months[i]
  # mmap = FALSE: 같은 경로에 곧 write_parquet 한다 — 매핑이 살아 있으면 Windows error 1224 로 쓰기가 실패한다
  #   (2026-09-24 샌드박스 실측: 구판 그대로는 첫 파일에서 중단 · phase7 :397-402 와 같은 원인)
  dt <- as.data.table(read_parquet(files[i], mmap = FALSE))
  setkey(dt, Date, Ticker)

  # 기존 NA 컬럼 제거
  for (col in c("V21_Composite_Equity_Issuance", "RE04_HighVol_Beta", "D29_Accounting_Beta")) {
    if (col %in% names(dt)) dt[, (col) := NULL]
  }

  # V21 + RE04 merge
  vr <- PART_VR[YM == ym, .(Ticker, Date, V21_Composite_Equity_Issuance, RE04_HighVol_Beta)]
  if (nrow(vr) > 0) {
    setkey(vr, Date, Ticker)
    dt <- merge(dt, vr, by = c("Date", "Ticker"), all.x = TRUE)
  }

  # D29 merge (rolling join)
  price_ym <- dt[, .(Ticker, Date)]
  setkey(price_ym, Ticker, Date)
  d29 <- acct_beta[price_ym, roll = Inf, on = .(Ticker, Date)]
  d29 <- d29[, .(Ticker, Date, D29_Accounting_Beta)]
  setkey(d29, Date, Ticker)
  dt <- merge(dt, d29, by = c("Date", "Ticker"), all.x = TRUE)

  write_parquet(dt, files[i], compression = "snappy")
  if (i %% pb == 0 || i == length(files))
    cat(sprintf("  [%d/%d] %s (%d cols)\n", i, length(files), ym, ncol(dt)))
}
cat(sprintf("  완료 (%.1fs)\n\n", (proc.time() - t3)["elapsed"]))

# ═══ 4. 검증 + 텔레그램 ═══════════════════════════════════════════════════
cat("[4/4] 검증...\n")
dt_check <- as.data.table(read_parquet(file.path(FDB_DIR, "fdb_daily_202012.parquet")))
for (col in c("V21_Composite_Equity_Issuance", "RE04_HighVol_Beta", "D29_Accounting_Beta")) {
  v <- sum(!is.na(dt_check[[col]]))
  cat(sprintf("  %s: %d/%d (%.1f%%)\n", col, v, nrow(dt_check), v / nrow(dt_check) * 100))
}

total_min <- (proc.time() - t0)["elapsed"] / 60
cat(sprintf("\n═══ Phase 9b 완료 (%.1f분) ═══\n", total_min))

tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  tg_send(sprintf("✅ [Q-Lead] Phase 9b 완료!

🔧 수정 내용:
• V21_Composite_Equity_Issuance: 5년 시총변화-수익률 (Rcpp cumret)
• RE04_HighVol_Beta: MRS percentile>70%% conditional beta
• D29_Accounting_Beta: expanding ROE 회귀 (Fund 시계열)

⏱️ 소요: %.1f분", total_min))
}, error = function(e) cat("  텔레그램 전송 실패\n"))
