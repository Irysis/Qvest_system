# STR_1626: Q01_GPA (30%) + Q04_Piotroski_F (70%) — Profitability Fortress Defense
# 학술 근거:
#   Novy-Marx (2013) "The Other Side of Value" — Gross Profitability Premium
#     GPA = (Revenue - COGS) / Total Assets: 단순·강건한 수익성 신호
#   Piotroski (2000) "Value Investing: The Use of Historical Financial Statement Info"
#     F-Score (9 binary signals): 수익성/레버리지/운영효율 복합 재무건전성
#   메커니즘: 재무제표 기반 낮은 회전율 + high-quality screening
#             → 시장이 천천히 반영하는 재무 개선/악화 신호 (PEAD 유사)
#             → defense 역할: 수익성 높은 종목 = 경기침체 시 생존력 높음
# PIT 준수:
#   C2: same-day circular 금지 (Factor DB Usable_Date 기반)
#   C10: 유동성 전월 기준 (AvgTV20 t-1 lag)
#   C13: Z_Score_Aligned만 사용 (방향 반전 금지)
#   C14: Usable_Date <= sig_date (Factor DB 내장)
#   C15: Factor DB 일괄 프리로드 경유 (loop 내 I/O 금지)
# optimized-backtest 원칙 1: Q01 + Q04만 일괄 프리로드 → 메모리 필터

cat("[factor_engine] STR_1626: Q01_GPA(30%) + Q04_Piotroski_F(70%) — bulk-load mode...\n")
set.seed(1626)

LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 20L
W_Q01         <- 0.30   # GPA weight
W_Q04         <- 0.70   # Piotroski F-Score weight
NEEDED_FACTORS <- c("Q01_GPA", "Q04_Piotroski_F")

# ─── 원칙 1: Factor DB Q01 + Q04만 일괄 프리로드 (루프 내 I/O 금지) ──────
cat("[OPT] Bulk-loading Factor DB (Q01_GPA + Q04_Piotroski_F only)...\n")
if (!exists("INFRA_DIR")) {
  INFRA_DIR <- file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    "02_Infrastructure"
  )
}
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                         full.names = TRUE)
if (length(fdb_files) == 0) stop("[FDB] No factor_db parquet files found in ", fdb_dir)

FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(f))
  # Q01 + Q04만 필터 (268팩터 전체 로드 금지 — 메모리 절약)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE]
  if (nrow(dt) == 0L) return(NULL)
  ym <- gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", basename(f))
  dt[, YM := ym]
  dt
}), use.names = TRUE, fill = TRUE)

if (nrow(FDB_ALL) == 0L) {
  stop("[FDB] Q01_GPA / Q04_Piotroski_F not found in Factor DB.")
}

# C13: align_factor_direction() 1회 적용 (방향 반전 금지, IC 기반 자동 정렬)
registry <- .load_registry()
FDB_ALL  <- align_factor_direction(FDB_ALL, registry)
setkey(FDB_ALL, YM, Ticker, Factor_Name)

cat(sprintf("[OPT] FDB_ALL: %s rows | %d months | %.1f MB\n",
            format(nrow(FDB_ALL), big.mark = ","),
            uniqueN(FDB_ALL$YM),
            object.size(FDB_ALL) / 1e6))
cat(sprintf("[OPT] Factors available: %s\n",
            paste(unique(FDB_ALL$Factor_Name), collapse = ", ")))

# ─── 원칙 6: LIQ 사전 계산 (t-1 lag, C10 준수) ──────────────────────────
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
RAWDATA[, TradingValue := Close * Vol]

# 월말 날짜 인덱스 (신호 생성 기준일)
monthly_last <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setorder(monthly_last, YM)
all_ym <- sort(monthly_last$YM)

# 유동성 집계: 각 월의 마지막 20 거래일 평균 거래대금
LIQ_RAW <- RAWDATA[, .(
  AvgTV20 = mean(tail(TradingValue, 20L), na.rm = TRUE)
), by = .(Ticker, YM)]

# t-1 lag: 당월 종목 필터에 전월 유동성 사용 (C10)
ym_shift <- data.table(
  YM_prev = all_ym[-length(all_ym)],
  YM_use  = all_ym[-1L]
)
LIQ_MONTHLY <- merge(LIQ_RAW, ym_shift, by.x = "YM", by.y = "YM_prev")
LIQ_MONTHLY <- LIQ_MONTHLY[, .(Ticker, YM = YM_use, AvgTV20)]

# ─── YM 포맷 정규화 (FDB_ALL: "YYYYMM", RAWDATA: "YYYY-MM") ─────────────
LIQ_MONTHLY[, YM_fdb := gsub("-", "", YM)]
setkey(LIQ_MONTHLY, Ticker, YM_fdb)

# 월말 신호일 매핑 테이블 (YM → sig_date)
sig_date_map <- monthly_last[, .(YM, sig_date, YM_fdb = gsub("-", "", YM))]
setkey(sig_date_map, YM_fdb)

# 사용할 YM 목록: FDB_ALL과 LIQ_MONTHLY 교집합 (양 팩터 모두 있는 월만)
ym_q01 <- unique(FDB_ALL[Factor_Name == "Q01_GPA", YM])
ym_q04 <- unique(FDB_ALL[Factor_Name == "Q04_Piotroski_F", YM])
ym_both <- intersect(ym_q01, ym_q04)
ym_fdb_avail <- sort(intersect(ym_both, unique(LIQ_MONTHLY$YM_fdb)))

cat(sprintf("[OPT] Q01 months: %d | Q04 months: %d | overlap: %d\n",
            length(ym_q01), length(ym_q04), length(ym_fdb_avail)))

# 최소 253 거래일 이후 (안정화 기간)
all_dates <- sort(unique(RAWDATA$Date))
min_date  <- all_dates[min(253L, length(all_dates))]
ym_fdb_avail <- ym_fdb_avail[ym_fdb_avail >= format(min_date, "%Y%m")]

factor_list <- vector("list", length(ym_fdb_avail))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(ym_fdb_avail)) {
  ym <- ym_fdb_avail[i]

  # FDB에서 Q01, Q04 Z_Score_Aligned 추출 (메모리 필터 — I/O 없음)
  fdt_q01 <- FDB_ALL[YM == ym & Factor_Name == "Q01_GPA",
                     .(Ticker, Z_Q01 = Z_Score_Aligned)]
  fdt_q04 <- FDB_ALL[YM == ym & Factor_Name == "Q04_Piotroski_F",
                     .(Ticker, Z_Q04 = Z_Score_Aligned)]

  if (nrow(fdt_q01) == 0L || nrow(fdt_q04) == 0L) {
    n_skipped <- n_skipped + 1L
    next
  }

  # 두 팩터 병합 (inner join: 양쪽 모두 있는 종목만)
  fdt <- merge(fdt_q01, fdt_q04, by = "Ticker")
  if (nrow(fdt) < N_HOLDINGS) {
    n_skipped <- n_skipped + 1L
    next
  }

  # 유동성 필터 (C10: 전월 AvgTV20 t-1 lag)
  liq <- LIQ_MONTHLY[YM_fdb == ym, .(Ticker, AvgTV20)]
  fdt <- merge(fdt, liq, by = "Ticker")
  fdt <- fdt[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt) < N_HOLDINGS) {
    n_skipped <- n_skipped + 1L
    next
  }

  # 복합 Score: 0.30 × Z_Q01 + 0.70 × Z_Q04 (C13: Z_Score_Aligned 사용)
  fdt[, Score := W_Q01 * Z_Q01 + W_Q04 * Z_Q04]
  fdt <- fdt[!is.na(Score)]
  if (nrow(fdt) < N_HOLDINGS) {
    n_skipped <- n_skipped + 1L
    next
  }

  # Score 상위 N_HOLDINGS 선택
  setorder(fdt, -Score)
  fdt <- fdt[1L:N_HOLDINGS]

  # 신호일 날짜 매핑
  sig_d <- sig_date_map[YM_fdb == ym, sig_date]
  if (length(sig_d) == 0L) {
    n_skipped <- n_skipped + 1L
    next
  }
  fdt[, Date := as.Date(sig_d)]

  factor_list[[i]] <- fdt[, .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

# ─── Cleanup ─────────────────────────────────────────────────────────────
for (col in c("YM", "TradingValue")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL, LIQ_RAW, LIQ_MONTHLY, ym_shift, sig_date_map, fdb_files,
   fdt_q01, fdt_q04, factor_list)
gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d dates (skip %d) | avg N=%.0f\n",
            format(nrow(FACTORS), big.mark = ","),
            n_done, n_skipped,
            if (n_done > 0) nrow(FACTORS) / n_done else 0))
cat(sprintf("  Weight: Q01_GPA %.0f%% + Q04_Piotroski_F %.0f%%\n",
            W_Q01 * 100, W_Q04 * 100))
