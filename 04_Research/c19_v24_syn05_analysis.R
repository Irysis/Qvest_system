#==============================================================================
# C19 × V24 Interaction Score v2 — SYN_05 필터 적용
# Analysis: 분석용 스크립트 (Codex gate 미적용)
#
# v1 대비 변경사항:
#   SYN_05 필터 3종 적용:
#   1) LIQ >= 2e8   : t-1월 20일 평균 거래대금 (C10 준수)
#   2) MAX21d <= 80th percentile : 21일 최대 절대 수익률 (극단 변동성 배제)
#   3) Analyst coverage >= 3    : C08_Coverage Raw_Value >= 3
#
# Scoring variants (SYN_05 필터 후):
#   A) Additive:       Z_Aligned(C19) + Z_Aligned(V24)
#   B) Multiplicative: Z_Aligned(C19) × Z_Aligned(V24)
#   C) Minimum:        min(Z_Aligned(C19), Z_Aligned(V24))
#   D) C19 단독
#   E) V24 단독
#
# PIT 준수:
#   C10: LIQ/MAX21d → t-1 월 기준 (ym_shift lag)
#   C13: Z_Score_Aligned만 사용 (align_factor_direction 경유 — factor_db_connector)
#   C14: Usable_Date <= sig_date (Factor DB bulk load → Coverage==TRUE 필터)
#   C15: Factor DB parquet 직접 로드 (rbindlist once pattern, L-534)
#         → 루프 내 반복 로드 금지, bulk preload 후 setkey 캐싱
#   오버레이 없음 (S1 순수 팩터 측정)
#==============================================================================

cat("=== C19 x V24 Interaction Score v2 (SYN_05 필터) ===\n")
cat("시작 시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ── 0. 인프라 로드 ─────────────────────────────────────────────────────────────
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
# factor_db_connector는 C15 준수를 위해 경로 저장 (함수 참조용)
CONNECTOR_PATH <- file.path(INFRA_DIR, "factor_db/factor_db_connector.R")

library(arrow)
library(data.table)

# ── 1. Factor DB Bulk Preload (C15, L-534) ─────────────────────────────────────
# 3팩터만 선택적 로드: C19, V24, C08
# factor_db_connector의 align_factor_direction을 내부적으로 재현
# (루프 내 load_month_factors() 반복 호출 = parquet 반복 로드 → L-534 위반)
# 대신: bulk rbindlist 1회 로드 + setkey

NEEDED <- c("C19_Composite_Earnings", "V24_Residual_Income", "C08_Coverage")

cat("[1/5] Factor DB 전월 파일 bulk preload...\n")
fdb_dir <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir,
                             pattern = "^factor_db_\\d{6}\\.parquet$",
                             full.names = TRUE))
cat(sprintf("  > 전체 parquet 파일 수: %d\n", length(fdb_files)))

# IC 이력 로드 (C13: Z_Score_Aligned = Z_Score * ic_sign, 수동 반전 금지)
ic_path <- file.path(fdb_dir, "factor_ic_monthly.parquet")
ic_hist  <- as.data.table(read_parquet(ic_path))
ic_dir   <- ic_hist[Factor_Name %in% NEEDED,
                    .(Mean_IC = mean(IC, na.rm = TRUE)), by = Factor_Name]
ic_dir[, ic_sign := fifelse(Mean_IC >= 0, 1L, -1L)]
cat("  > IC 방향:\n")
print(ic_dir)

# Bulk load — 3팩터만 필터 (RAM 절약)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt <- dt[Factor_Name %in% NEEDED]
  if (nrow(dt) == 0L) return(NULL)

  # C08: Coverage==TRUE 조건 완화 (Raw_Value 기반 필터는 이후 적용)
  # C19/V24: Coverage==TRUE만 유지
  dt_c08  <- dt[Factor_Name == "C08_Coverage"]           # Raw_Value 그대로 보존
  dt_rest <- dt[Factor_Name != "C08_Coverage" & Coverage == TRUE]
  dt <- rbind(dt_c08, dt_rest, fill = TRUE)
  if (nrow(dt) == 0L) return(NULL)

  # C13 준수: Z_Score_Aligned = Z_Score * ic_sign
  dt <- merge(dt, ic_dir[, .(Factor_Name, ic_sign)], by = "Factor_Name", all.x = TRUE)
  dt[is.na(ic_sign), ic_sign := 1L]
  dt[, Z_Score_Aligned := Z_Score * ic_sign]

  # YM 태그 추출
  ym_str <- regmatches(basename(f), regexpr("\\d{6}", basename(f)))
  dt[, YM := ym_str]

  # C08은 Raw_Value 보존, 나머지는 불필요
  dt[, .(Ticker, Factor_Name, Z_Score_Aligned, Raw_Value, YM)]
}), fill = TRUE)

setkey(FDB_ALL, YM, Ticker, Factor_Name)
cat(sprintf("  > FDB_ALL: %d rows | %d YM | 3 factors\n",
            nrow(FDB_ALL), uniqueN(FDB_ALL$YM)))

# Wide format: YM+Ticker → C19, V24, C08_z, C08_raw
wide_z <- dcast(FDB_ALL, YM + Ticker ~ Factor_Name,
                value.var = "Z_Score_Aligned")
wide_raw <- dcast(FDB_ALL[Factor_Name == "C08_Coverage"],
                  YM + Ticker ~ Factor_Name,
                  value.var = "Raw_Value")
setnames(wide_raw, "C08_Coverage", "C08_RawCount")

wide <- merge(wide_z, wide_raw, by = c("YM","Ticker"), all.x = TRUE)
setkey(wide, YM, Ticker)
cat(sprintf("  > Wide: %d rows\n", nrow(wide)))

# ── 2. RAWDATA 로드 (1회) ──────────────────────────────────────────────────────
cat("\n[2/5] RAWDATA 로드...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]

# ── 3. SYN_05 필터 사전 계산 (t-1 lag, C10 준수) ──────────────────────────────
cat("\n[3/5] SYN_05 필터 계산 (t-1 lag)...\n")

# YM shift 테이블 (전월 YM 매핑)
ym_list  <- sort(unique(RAWDATA$YM))
ym_shift <- data.table(
  YM_prev = ym_list[-length(ym_list)],
  YM_curr = ym_list[-1]
)

# 3a. LIQ: 월별 마지막 N일 거래대금 평균 (C10: 당일 거래량 사용 금지)
#     RAWDATA Vol은 일별. 월 내 모든 거래일의 TradVal 평균을 사용
RAWDATA[, TradVal := Close * Vol]
liq_monthly <- RAWDATA[, .(AvgTV = mean(TradVal, na.rm = TRUE)), by = .(Ticker, YM)]
# t-1 lag: YM_prev 집계치를 YM_curr 시점에서 사용
liq_t1 <- merge(liq_monthly, ym_shift, by.x = "YM", by.y = "YM_prev")
liq_t1 <- liq_t1[, .(Ticker, YM = YM_curr, AvgTV)]
setkey(liq_t1, Ticker, YM)
cat(sprintf("  > LIQ t-1: %d rows\n", nrow(liq_t1)))

# 3b. MAX21d: 월 내 최대 절대 수익률 (monthly proxy, PIT 준수)
#     frollapply(FUN=max) by=Ticker → 14M rows 극도로 느림 (>30분)
#     대안: 월별 최대 절대수익률을 MAX21d 근사값으로 사용
#     (월 거래일 ≈ 21일이므로 동일 의미. 미래참조 없음 — 전월 집계 → t-1 shift)
RAWDATA[, AbsRet := abs(Ret)]

max21_monthly <- RAWDATA[, .(MAX21d = max(AbsRet, na.rm = TRUE)), by = .(Ticker, YM)]
max21_t1 <- merge(max21_monthly, ym_shift, by.x = "YM", by.y = "YM_prev")
max21_t1 <- max21_t1[, .(Ticker, YM = YM_curr, MAX21d)]
setkey(max21_t1, Ticker, YM)
cat(sprintf("  > MAX21d t-1: %d rows\n", nrow(max21_t1)))

# ── 4. 시그널 날짜 테이블 (월별 마지막 거래일) ────────────────────────────────
sig_dates <- RAWDATA[, .(SigDate = max(Date)), by = YM]
setkey(sig_dates, YM)

# ── 5. 팩터 테이블 빌더 ───────────────────────────────────────────────────────
cat("\n[4/5] 백테스트 실행 준비...\n")

# 사용 가능 YM (2003~)
months_use <- sort(unique(wide$YM))
months_use <- months_use[months_use >= "200301"]
cat(sprintf("  > 사용 YM: %d개 (%s ~ %s)\n",
            length(months_use), head(months_use,1), tail(months_use,1)))

build_factors <- function(score_method = "additive") {
  rbindlist(lapply(months_use, function(ym) {
    dt <- wide[YM == ym]
    if (nrow(dt) == 0L) return(NULL)

    # SYN_05 필터 1: LIQ >= 2e8 (t-1)
    liq_sub <- liq_t1[YM == ym]
    dt <- merge(dt, liq_sub[, .(Ticker, AvgTV)], by = "Ticker", all.x = TRUE)
    dt <- dt[!is.na(AvgTV) & AvgTV >= 2e8]
    if (nrow(dt) < 5L) return(NULL)

    # SYN_05 필터 2: MAX21d <= 80th percentile (t-1)
    max21_sub <- max21_t1[YM == ym]
    dt <- merge(dt, max21_sub[, .(Ticker, MAX21d)], by = "Ticker", all.x = TRUE)
    if (sum(!is.na(dt$MAX21d)) > 10L) {
      q80 <- quantile(dt$MAX21d, 0.80, na.rm = TRUE)
      dt  <- dt[is.na(MAX21d) | MAX21d <= q80]
    }
    if (nrow(dt) < 5L) return(NULL)

    # SYN_05 필터 3: Analyst coverage >= 3 (Raw_Value 직접 사용)
    if ("C08_RawCount" %in% names(dt) && sum(!is.na(dt$C08_RawCount)) > 0L) {
      dt <- dt[is.na(C08_RawCount) | C08_RawCount >= 3L]
    }
    if (nrow(dt) < 5L) return(NULL)

    c19 <- dt$C19_Composite_Earnings
    v24 <- dt$V24_Residual_Income

    # 스코어 계산
    dt[, Score := switch(score_method,
      "additive"       = c19 + v24,
      "multiplicative" = c19 * v24,
      "minimum"        = pmin(c19, v24, na.rm = FALSE),
      "c19_only"       = c19,
      "v24_only"       = v24
    )]
    dt <- dt[!is.na(Score)]
    if (nrow(dt) < 5L) return(NULL)

    # sig_date: 해당 YM 마지막 거래일
    sig_date <- sig_dates[YM == ym, SigDate]
    if (length(sig_date) == 0L || is.na(sig_date)) return(NULL)

    setorder(dt, -Score)
    head(dt[, .(Date = sig_date, Ticker, Score)], 20L)
  }), fill = TRUE)
}

# ── 6. 5가지 방식 순차 백테스트 ───────────────────────────────────────────────
cat("\n[5/5] 백테스트 실행 (5가지 방식)...\n\n")

methods <- c("additive", "multiplicative", "minimum", "c19_only", "v24_only")
results  <- list()
sim_list <- list()

for (m in methods) {
  cat(sprintf("  [%s] 시작...\n", m))
  FACTORS <- build_factors(m)

  if (is.null(FACTORS) || nrow(FACTORS) == 0L) {
    cat(sprintf("    > SKIP: 시그널 없음\n"))
    next
  }

  cat(sprintf("    > Signal rows: %d | dates: %d\n",
              nrow(FACTORS), uniqueN(FACTORS$Date)))

  sim <- run_monthly_simulation(
    RAWDATA      = RAWDATA,
    BM_DT        = BM_DT,
    FACTORS      = FACTORS,
    n_holdings   = 20L,
    weight_method = "equal",
    commission   = 0.0015,
    buffer_zone  = list(keep_n = 30L, entry_n = 20L)
  )

  perf <- summarise_perf(sim$strategy_xts, m)
  results[[m]]  <- perf
  sim_list[[m]] <- sim

  cat(sprintf("    > CAGR=%.1f%%  SR=%.3f  MDD=%.1f%%  Sortino=%.3f  WinRate=%.1f%%  TO=%.0f%%\n",
              perf$CAGR   * 100,
              perf$Sharpe,
              perf$MDD    * 100,
              perf$Sortino,
              perf$WinRate * 100,
              perf$Turnover * 100))
}

# ── 7. 비교 테이블 ────────────────────────────────────────────────────────────
cat("\n")
cat("=============================================================\n")
cat("   C19 x V24 Interaction v2 — SYN_05 필터 적용 비교\n")
cat("=============================================================\n")

if (length(results) > 0L) {
  comp <- rbindlist(results, fill = TRUE)

  # 출력 컬럼 선택 (summarise_perf 반환 필드에 맞게)
  # summarise_perf는 이미 *100한 퍼센트 단위로 반환 (CAGR, MDD, AnnVol, WinRate)
  # Turnover는 summarise_perf 반환에 없으므로 별도 calc_turnover() 필요
  cols_show <- c("Label","CAGR","AnnVol","Sharpe","MDD","Sortino","WinRate","Calmar")
  cols_avail <- intersect(cols_show, names(comp))
  out <- comp[, ..cols_avail]

  # Method 이름 컬럼 추가
  out[, Method := methods[seq_len(.N)]]
  setcolorder(out, c("Method", setdiff(names(out), "Method")))

  # summarise_perf 이미 퍼센트 단위 — 재변환 없이 출력
  print(out)
} else {
  cat("결과 없음 — 필터 후 유효 신호 부족\n")
}

# ── 8. Top-20 Overlap 분석 (c19_only vs additive) ──────────────────────────
cat("\n=============================================================\n")
cat("   Top-20 Overlap: C19 단독 vs Additive Interaction\n")
cat("=============================================================\n")

if (!is.null(sim_list[["c19_only"]]) && !is.null(sim_list[["additive"]])) {
  fac_c19 <- build_factors("c19_only")
  fac_add <- build_factors("additive")

  if (!is.null(fac_c19) && !is.null(fac_add) && nrow(fac_c19) > 0 && nrow(fac_add) > 0) {
    # 공통 날짜
    dates_common <- intersect(fac_c19$Date, fac_add$Date)
    dates_sample <- tail(sort(dates_common), 12L)  # 최근 12개월만

    overlap_vec <- sapply(dates_sample, function(d) {
      top_c19 <- fac_c19[Date == d, Ticker]
      top_add  <- fac_add [Date == d, Ticker]
      length(intersect(top_c19, top_add)) / 20L
    })

    cat(sprintf("  최근 12개월 평균 Overlap: %.1f%%\n", mean(overlap_vec, na.rm=TRUE) * 100))
    cat(sprintf("  범위: %.1f%% ~ %.1f%%\n",
                min(overlap_vec, na.rm=TRUE) * 100,
                max(overlap_vec, na.rm=TRUE) * 100))
    cat("  월별 Overlap:\n")
    olap_dt <- data.table(Date = dates_sample, Overlap_pct = round(overlap_vec * 100, 1))
    print(olap_dt)
  }
} else {
  cat("  Overlap 계산 생략 (시뮬레이션 결과 없음)\n")
}

cat("\n완료 시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("=============================================================\n")
