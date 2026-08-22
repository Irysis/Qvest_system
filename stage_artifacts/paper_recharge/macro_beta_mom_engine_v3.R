# =============================================================================
# macro_beta_mom_engine_v3.R — macro_beta_momentum (사전계산 parquet 로드)
# =============================================================================
# 논문: arXiv 2608.12283  Score_i,t = sum_j [ beta_ij,t × Δm_j_20d,t ]
# 사전계산: compute_macro_beta_v2.py → .cache/macro_beta_scores.parquet
#   (260 month-end dates × 3462 tickers, 507,076 rows, NA score = 0)
# PIT: Python 스크립트가 rolling 60d OLS (d-1 FRED lag) 으로 생산 — C1/C2/C11 준수
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

suppressWarnings(suppressMessages({
  library(arrow)
  library(data.table)
}))

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR",
                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

.scores_path <- file.path(PROJ, ".cache", "macro_beta_scores.parquet")
stopifnot(file.exists(.scores_path))

# ---- 1. 사전계산 점수 로드 ---------------------------------------------------
.mbs <- as.data.table(arrow::read_parquet(.scores_path))

# POSIXct → Date 정규화
if (inherits(.mbs$Date, "POSIXct")) {
  .mbs[, Date := as.Date(Date, tz = "UTC")]
}
cat(sprintf("[macro_beta_v3] loaded parquet: %d rows | %d dates | %d tickers\n",
            nrow(.mbs), uniqueN(.mbs$Date), uniqueN(.mbs$Ticker)))

# ---- 2. RAWDATA 월말 날짜 추출 ----------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- 3. 유동성 필터 (RAWDATA LiqPass 기준, 월말 날짜) ----------------------
.liq_dt <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE, .(Date, Ticker)]

# ---- 4. 월말 scores 와 유동성 inner-join -----------------------------------
.mbs_end <- .mbs[Date %in% .month_ends]
FACTORS  <- merge(.mbs_end, .liq_dt, by = c("Date", "Ticker"), all = FALSE)
FACTORS  <- FACTORS[is.finite(Score), .(Date, Ticker, Score)]
setorder(FACTORS, Date, Ticker)

cat(sprintf("[macro_beta_v3] FACTORS: %d rows | %d signal dates | %d tickers\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# 임시 컬럼 정리
RAWDATA[, .ym := NULL]
rm(.mbs, .mbs_end, .liq_dt, .month_ends)
gc(verbose = FALSE)
