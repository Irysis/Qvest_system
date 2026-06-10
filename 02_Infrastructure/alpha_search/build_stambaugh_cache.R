# =============================================================================
# build_stambaugh_cache.R — Stambaugh-Yuan (2017, RFS) 11 anomaly Z 캐시 (OOM-safe)
# =============================================================================
# "Mispricing Factors" (Stambaugh & Yuan, RFS 2017). 11 anomaly를 2 cluster로
#   묶어 mispricing score 산출. 본 캐시는 11 anomaly의 PIT-safe Z_Score_Aligned만
#   load_month_factors(C15 경유, IC-direction PIT-safe) 1회 월별 순회로 slim 추출.
#
# ★ OOM 근본 fix (build_lo_factor_cache.R 패턴): batch 전 *단 1회* 월별 순회하며
#   11 factor의 Z_Score_Aligned만 추출 → RDS. factor_engine은 이 RDS 슬라이스만
#   (arrow parquet read 0회). 매 run arrow 반복 read 누적 segfault 제거.
#
# ★ 11 anomaly factor DB 매핑 (도훈 mandate + Stambaugh-Yuan 2017 Table 1):
#   [Management cluster — 기업 발행/투자 행동, 6종]
#     ① net stock issues        → IN04_Net_Equity_Issuance
#     ② composite equity issues  → V21_Composite_Equity_Issuance
#     ③ accruals                 → AC07_Operating_Accruals
#     ④ NOA (net op. assets)     → AC05_NOA
#     ⑤ asset growth             → GR03_Asset_Growth
#     ⑥ investment-to-assets     → IN06_Investment_to_Assets
#   [Performance cluster — 기업 성과/수익성, 5종]
#     ⑦ distress (failure prob.) → Q24_Altman_Z   (KR distress proxy)
#     ⑧ O-score                  → Q25_Ohlson_O
#     ⑨ momentum                 → M01_Mom_12_1
#     ⑩ gross profitability      → Q01_GPA
#     ⑪ ROA                      → Q03_ROA
#   = 11종 (원논문 NYSE-listed anomaly 11개와 1:1 / KR factor DB 전부 실재).
#   ※ 부족분: 없음(11/11 매핑). net stock issues는 IN04/Q20 중복 → IN04 단일 채택(논문 1 anomaly).
#
# ★ 부호 처리 (C13 NEGATE/FLIP 금지 준수): Z_Score_Aligned는 load_month_factors가
#   IC-direction PIT-safe로 "높을수록 기대수익↑"로 이미 정렬. Stambaugh-Yuan은
#   "저-mispricing = 저평가 = long" → 저평가 = 고-기대수익. 따라서 11 Z_Aligned를
#   2 cluster 평균 → 평균한 composite_alpha 가 **높을수록 long**(저-mispricing).
#   수동 부호반전 없음. mispricing_rank = (1 - alpha_pctile) 는 진단 표기용일 뿐,
#   long 선택은 composite_alpha 상위 = 저-mispricing 상위와 등가(C13 안전).
#
# 출력: stage_artifacts/alpha_search/stambaugh/_sy_cache.rds
#   data.table(Date, Ticker, Factor_Name, Z_Score_Aligned)  — 11 factor × universe-월
#
# 실행(PowerShell, arrow 안전; -f 금지, BOM 없이):
#   $env:CLAUDE_PROJECT_DIR='G:/Quant_Module_Moltbot'
#   Rscript -e "source('02_Infrastructure/alpha_search/build_stambaugh_cache.R')"
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))

PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))                 # load_rawdata
source(file.path(INFRA, "factor_db", "factor_db_connector.R")) # load_month_factors (C15)

OUT_DIR    <- file.path(PROJ, "stage_artifacts", "alpha_search", "stambaugh")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
CACHE_PATH <- file.path(OUT_DIR, "_sy_cache.rds")
FDB_MIN    <- as.Date("2002-08-01")   # factor DB 재무 의존 factor 가용 시작
COVERAGE_MIN <- 0.05

# ---- 11 anomaly (2 cluster) ----
MGMT_FACTORS <- c("IN04_Net_Equity_Issuance","V21_Composite_Equity_Issuance",
                  "AC07_Operating_Accruals","AC05_NOA","GR03_Asset_Growth",
                  "IN06_Investment_to_Assets")
PERF_FACTORS <- c("Q24_Altman_Z","Q25_Ohlson_O","M01_Mom_12_1","Q01_GPA","Q03_ROA")
TARGET_FACTORS <- c(MGMT_FACTORS, PERF_FACTORS)
stopifnot(length(TARGET_FACTORS) == 11L)

cat(sprintf("\n=== [build_stambaugh_cache] 11 anomaly (mgmt %d + perf %d) ===\n",
            length(MGMT_FACTORS), length(PERF_FACTORS)))

# ---- 1. RAWDATA → universe(K200∪KQ150 멤버십 + 유동성) + month-end grid (1회) ----
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
.rd[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]   # PIT 우측정렬(과거 윈도우)
mem <- .rd[Date %in% me_dates & (K200 == TRUE | KQ150 == TRUE) &
             !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
rm(.rd); gc(FALSE)
cat(sprintf("[cache] universe months=%d (%s..%s) | universe-month rows=%d\n",
            length(me_dates), as.character(min(me_dates)), as.character(max(me_dates)), nrow(mem)))

# ---- 2. ★ 단 1회 월별 순회 — load_month_factors(d) 후 11 factor만 slim ----
tf_set <- TARGET_FACTORS
cache_list <- vector("list", length(me_dates))
t0 <- Sys.time(); build_hash <- "unknown"
for (i in seq_along(me_dates)) {
  d <- me_dates[i]
  uni_tk <- mem[.(d), Ticker, nomatch = 0L]; if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = COVERAGE_MIN), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
  if (i == 1L) { bh <- attr(fdt, "factor_db_build_hash"); if (!is.null(bh)) build_hash <- bh }
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

# ---- 3. 저장 (+ 메타) ----
attr(CACHE, "target_factors") <- tf_set
attr(CACHE, "mgmt_factors")   <- MGMT_FACTORS
attr(CACHE, "perf_factors")   <- PERF_FACTORS
attr(CACHE, "build_hash")     <- build_hash
attr(CACHE, "n_months")       <- uniqueN(CACHE$Date)
attr(CACHE, "generated_at")   <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
saveRDS(CACHE, CACHE_PATH, compress = TRUE)

diag <- CACHE[, .(months = uniqueN(Date), rows = .N,
                  first = as.character(min(Date)), last = as.character(max(Date))), by = Factor_Name]
setorder(diag, Factor_Name)
cat(sprintf("\n[cache] SAVED %s | total rows=%d | distinct months=%d | %.0fs\n",
            CACHE_PATH, nrow(CACHE), uniqueN(CACHE$Date),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cat("[cache] per-factor coverage:\n"); print(diag)
miss <- setdiff(tf_set, unique(CACHE$Factor_Name))
if (length(miss)) cat(sprintf("[cache] ★ 캐시에 0행(부재) factor: %s\n", paste(miss, collapse = ", ")))
