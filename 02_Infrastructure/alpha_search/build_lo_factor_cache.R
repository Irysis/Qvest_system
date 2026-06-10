# =============================================================================
# build_lo_factor_cache.R — long-only batch OOM 근본 fix: 필요 factor만 1회 일괄 캐시
# =============================================================================
# 근본원인(확정): driver_lo_screen.R Part 2가 각 factor run마다 me_dates(254월)를 순회하며
#   load_month_factors(d)를 호출 → 매 호출이 (a) full 월별 parquet(~300 factor) read +
#   (b) align_factor_direction(전체 factor 대상 expanding IC 방향추론, factor_ic_monthly
#   parquet 스캔)를 수행. batch = 23 factor × 254월 = ~5,800 회 full read → arrow 메모리/
#   핸들 누적 → 비결정 segfault/OOM. 이전 fix(RAWDATA 해제·독립 프로세스·gc)는 이 *반복
#   read 자체*를 못 잡음(RAWDATA가 아니라 factor parquet 반복 read가 진짜 누적원).
#
# ★ 근본 fix: batch 시작 전 *단 1회* 월별 load_month_factors(d)를 순회(254회, batch 전체에
#   1번뿐)하며 24개 대상 factor의 Z_Score_Aligned만 slim 추출 → RDS 캐시. 이후 모든 factor
#   run은 이 RDS를 슬라이스만 함(arrow parquet read 0회) → OOM 근본 제거.
#
# ===== PIT (C1~C15) 보장 =====
#   - load_month_factors(d) 경유(C15) → align_factor_direction PIT-safe(Usable_Date<=d, C14).
#     캐시는 그 출력(Date,Ticker,Factor_Name,Z_Score_Aligned)을 그대로 보존 → 부호/정렬 동일.
#   - C13: NEGATE/FLIP 없음(Aligned 그대로). 캐시가 어떤 변형도 가하지 않음.
#   - 각 sig_date d의 z는 그 시점 cross-section + d 이하 IC만으로 산출(미래 무참조).
#
# 출력: stage_artifacts/alpha_search/lo_screen/_factor_cache.rds
#   data.table(Date, Ticker, Factor_Name, Z_Score_Aligned)  — 24 factor × 254월 × universe
#   + attr: target_factors, build_hash, n_months, generated_at
#
# 실행(PowerShell, arrow 안전; -f 금지, BOM 없이):
#   $env:CLAUDE_PROJECT_DIR='G:/Quant_Module_Moltbot'
#   Rscript -e "source('02_Infrastructure/alpha_search/build_lo_factor_cache.R')"
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))

PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))                 # load_rawdata
source(file.path(INFRA, "factor_db", "factor_db_connector.R")) # load_month_factors (C15 경유)

OUT_DIR    <- file.path(PROJ, "stage_artifacts", "alpha_search", "lo_screen")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
CACHE_PATH <- file.path(OUT_DIR, "_factor_cache.rds")
FDB_MIN    <- as.Date("2002-08-01")   # factor DB 재무 의존 factor 가용 시작
COVERAGE_MIN <- 0.05

# ---- BATCH 2 대상 factor 39종 (38 candidate + V01_BM 대조군) ----
#   ★ 2026-06-06 batch 2: _verify_factors_batch2.R로 load_month_factors(C15) 3개 probe date에서
#     38종 전부 실재(coverage 1700~2600 ticker, 0 missing) 확인 후 등재. registry≠parquet 함정 회피.
#   prior batch 1(23 LO 완주: CR/V/AC/IN/C 계열)은 lo_screen/*.json 존재 → 본 캐시 제외.
TARGET_FACTORS <- c(
  # D 계열 12종 (tail/skew/vol — 방어 가능성 높음)
  "D01_IdioVol","D04_Downside_Beta","D05_MaxRet","D16_Coskewness","D17_Cokurtosis",
  "D25_Left_Tail_Beta","D43_Skewness","D44_Kurtosis","D45_Downside_Dev","D46_Sortino",
  "D50_MaxDrawdown","D51_Ulcer_Index",
  # R 계열 10종 (risk — CVaR/tail/coskew/downside)
  "R03_CVaR_95","R05_Tail_Risk","R07_Downside_Dev","R09_Coskewness","R10_Cokurtosis",
  "R13_NCSKEW","R14_DUVOL","R15_Sortino","R16_Calmar","R19_Composite_Risk",
  # M 나머지 8종 (momentum/reversal/maxret)
  "M02_Mom_6_1","M03_Mom_3_1","M10_Intermediate_Mom","M13_VolAdj_Mom","M14_RiskAdj_Mom",
  "M16_Trend_Factor","M22_Max_Return","M23_Acceleration",
  # Q 나머지 8종 (quality — accrual/CFOA/turnover/ROIC 등)
  "Q05_Accrual","Q09_CFOA","Q12_Asset_Turnover","Q17_ROIC","Q23_Sustainable_Growth",
  "Q28_Cash_Conversion","Q33_Earnings_Persistence","Q35_CashBased_OpProf",
  # value(BM) 대조군 (driver의 다축 상관용)
  "V01_BM"
)

cat(sprintf("\n=== [build_lo_factor_cache] BATCH 2 대상 %d factor (38 verified + V01_BM) ===\n", length(TARGET_FACTORS)))

# ---- 1. RAWDATA로 universe(멤버십+유동성) + month-end grid 산출 (1회) ----
#   캐시는 universe-한정으로 slim 유지(전종목 z를 다 담지 않음 → 캐시 크기↓, 슬라이스↑).
res <- load_rawdata(use_cache = TRUE); RAWDATA <- res$RAWDATA; rm(res); gc(FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
.rd <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
rm(RAWDATA); gc(FALSE)
setorder(.rd, Ticker, Date)
.rd[, .ym := format(Date, "%Y-%m")]
me_dates <- sort(.rd[, .(Date = max(Date)), by = .ym]$Date)
.rd[, .ym := NULL]
me_dates <- me_dates[me_dates >= FDB_MIN]
.rd[, .TV := Close * Vol]
.rd[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]   # PIT 과거 윈도우(t-1 포함 우측정렬)
mem <- .rd[Date %in% me_dates & (K200 == TRUE | KQ150 == TRUE) &
             !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
rm(.rd); gc(FALSE)
cat(sprintf("[cache] universe months=%d (%s..%s) | universe-month rows=%d\n",
            length(me_dates), as.character(min(me_dates)), as.character(max(me_dates)), nrow(mem)))

# ---- 2. ★ 단 1회 월별 순회 — load_month_factors(d) 호출 후 24 factor만 slim 추출 ----
#   batch 전체에 *이 루프 1번뿐*. full dt는 호출 직후 24 factor × universe로 줄이고 즉시 폐기.
tf_set <- TARGET_FACTORS
cache_list <- vector("list", length(me_dates))
t0 <- Sys.time(); build_hash <- "unknown"
for (i in seq_along(me_dates)) {
  d <- me_dates[i]
  uni_tk <- mem[.(d), Ticker, nomatch = 0L]; if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = COVERAGE_MIN), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
  if (i == 1L) { bh <- attr(fdt, "factor_db_build_hash"); if (!is.null(bh)) build_hash <- bh }
  # 호출 직후 24 factor × universe만 남기고 full(~300 factor) dt 즉시 폐기(누적 차단)
  slim <- fdt[Factor_Name %in% tf_set & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
              .(Ticker, Factor_Name, Z_Score_Aligned)]
  rm(fdt)
  if (nrow(slim)) { slim[, Date := d]; cache_list[[i]] <- slim[, .(Date, Ticker, Factor_Name, Z_Score_Aligned)] }
  if (i %% 24L == 0L) {
    gc(FALSE)
    cat(sprintf("[cache] %d/%d months (%.0fs elapsed)\n", i, length(me_dates),
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
}
CACHE <- rbindlist(Filter(Negate(is.null), cache_list), use.names = TRUE)
rm(cache_list); gc(FALSE)
setkey(CACHE, Factor_Name, Date, Ticker)

# ---- 3. 저장 (+ 메타 attr) ----
attr(CACHE, "target_factors") <- tf_set
attr(CACHE, "build_hash")     <- build_hash
attr(CACHE, "n_months")       <- uniqueN(CACHE$Date)
attr(CACHE, "generated_at")   <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
saveRDS(CACHE, CACHE_PATH, compress = TRUE)

# 진단: factor별 가용 월/행
diag <- CACHE[, .(months = uniqueN(Date), rows = .N,
                  first = as.character(min(Date)), last = as.character(max(Date))), by = Factor_Name]
setorder(diag, Factor_Name)
cat(sprintf("\n[cache] SAVED %s | total rows=%d | distinct months=%d | %.0fs\n",
            CACHE_PATH, nrow(CACHE), uniqueN(CACHE$Date),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cat("[cache] per-factor coverage:\n")
print(diag)
miss <- setdiff(tf_set, unique(CACHE$Factor_Name))
if (length(miss)) cat(sprintf("[cache] ★ 캐시에 0행(죽은/부재) factor: %s\n", paste(miss, collapse = ", ")))
