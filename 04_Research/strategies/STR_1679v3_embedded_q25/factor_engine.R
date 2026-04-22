## STR_1679v3 factor_engine — LIQ_THRESHOLD=2e8 C10 C13 C15 embedded blend
## 근거: Piotroski(2000)+Ohlson(1980)+Chordia&Swaminathan(2000). NO overlay (S1 pure signal)
## load_month_factors(sig_date) → Ticker, Factor_Name, Z_Score_Aligned (no sig_date col)

suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
cat("[factor_engine STR_1679v3] Earnings+Ohlson Quality Embedded Blend\n")

# C15: factor_db_connector.R 명시 로드 (load_month_factors 정의)
if (!exists("FUNC_PATH")) FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

if (!exists("LIQ_THRESHOLD")) LIQ_THRESHOLD <- 2e8
N_HOLD    <- 20L
W_C19     <- 0.55
W_Q25_INV <- 0.30  # Q25 Ohlson-O 반전
W_Q07     <- 0.15

# ── 시그널 날짜: RAWDATA 월말 ─────────────────────────────────────────────────
monthend_dates <- RAWDATA[, .(sig_date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
sig_dates_all  <- sort(monthend_dates[sig_date >= as.Date("2004-01-01"), sig_date])

# ── Factor DB 로드 (C15: load_month_factors(), lapply bulk) ───────────────────
NEEDED <- c("C19_Composite_Earnings", "Q25_Ohlson_O", "Q07_Earnings_Stability")

factor_list <- lapply(sig_dates_all, function(sig_d) {
  tryCatch({
    fd <- load_month_factors(sig_date = sig_d)
    fd <- fd[Factor_Name %in% NEEDED, .(Ticker, Factor_Name, Z_Score_Aligned)]
    # Date 컬럼 추가 (cbind 방식 — := by-reference 반환값 보장)
    cbind(Date = sig_d, fd)
  }, error = function(e) NULL)
})
FACTORS_RAW <- rbindlist(Filter(Negate(is.null), factor_list), use.names = TRUE, fill = TRUE)
setkey(FACTORS_RAW, Date, Ticker)

cat(sprintf("[factor_engine] Loaded: %d rows | %d periods\n",
  nrow(FACTORS_RAW), uniqueN(FACTORS_RAW$Date)))

# ── 와이드 변환 (C13: Z_Score_Aligned, NEGATE_FACTORS 금지) ──────────────────
FACTORS_WIDE <- dcast(
  FACTORS_RAW[, .(Date, Ticker, Factor_Name, Z_Score_Aligned)],
  Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned"
)
# 컬럼명 안전 rename
cols_present <- names(FACTORS_WIDE)
if ("C19_Composite_Earnings" %in% cols_present) setnames(FACTORS_WIDE, "C19_Composite_Earnings", "z_C19")
if ("Q25_Ohlson_O"           %in% cols_present) setnames(FACTORS_WIDE, "Q25_Ohlson_O",           "z_Q25_raw")
if ("Q07_Earnings_Stability" %in% cols_present) setnames(FACTORS_WIDE, "Q07_Earnings_Stability", "z_Q07")

# Q25 Ohlson-O: 높을수록 부실위험 HIGH → 명시적 반전 (C13 NEGATE 금지)
FACTORS_WIDE[, z_Q25_inv := -1.0 * z_Q25_raw]

# Composite signal
FACTORS_WIDE[, signal := W_C19 * z_C19 + W_Q25_INV * z_Q25_inv + W_Q07 * z_Q07]

# ── LIQ 필터 (C10: LIQ_THRESHOLD=2e8, AvgTV20 lag=1 from run_all.R) ──────────
LIQ_SNAP <- RAWDATA[
  Date %in% sig_dates_all & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD,
  .(Date, Ticker)
]
setkey(LIQ_SNAP, Date, Ticker)

FACTORS_LIQ <- FACTORS_WIDE[LIQ_SNAP, on = .(Date, Ticker), nomatch = 0L]
FACTORS_LIQ <- FACTORS_LIQ[!is.na(signal)]

# ── Top N_HOLD 선택 (EW) ─────────────────────────────────────────────────────
FACTORS <- FACTORS_LIQ[
  order(-signal),
  .SD[seq_len(min(.N, N_HOLD))],
  by = Date
][, .(Date, Ticker, Score = signal, z_C19, z_Q25_inv, z_Q07)]

n_periods <- uniqueN(FACTORS$Date)
cat(sprintf("[factor_engine] %d periods | %.1f tickers avg/period\n",
  n_periods, nrow(FACTORS) / max(n_periods, 1L)))
