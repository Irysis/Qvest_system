## STR_1655 GSCD: GR02_Earnings_Growth + Q07_Earnings_Stability + Q28_Cash_Conversion
## Beta 하위 40% 유니버스 제한 (expanding window, t-1 lag, C2)
## Cross-exposure 필터: AC21 z > -1.5, M01 z > -1.5
## S1 순수 팩터 — overlay 없음
## Bimonthly rebalance (격월), EW N=20, commission=15bps
##
## 역할: Diversifier (RoleBias_Diversifier)
## PIT: C2 beta t-1 / C10 LIQ t-1 / C13 Z_Score_Aligned / C15 Arrow bulk preload
##
## OPT-1 준수: Arrow open_dataset bulk preload 1회, lapply 메모리 필터만
## OPT-3 준수: 인라인 NAV 루프 없음, run_monthly_simulation() 사용

cat("[factor_engine] STR_1655: GR02 + Q07 + Q28 x Low-Beta(40%) Filter...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
library(arrow)
library(dplyr, warn.conflicts = FALSE)

NEEDED_FACTORS    <- c("GR02_Earnings_Growth", "Q07_Earnings_Stability", "Q28_Cash_Conversion")
CROSS_EXP_FACTORS <- c("AC21_Accrual_Quality", "M01_Momentum_12M")
ALL_FDB_FACTORS   <- c(NEEDED_FACTORS, CROSS_EXP_FACTORS)

BETA_WINDOW     <- 252L
BETA_CUTOFF     <- 0.40
BETA_FALLBACK   <- 0.50
MIN_UNIV_SIZE   <- 80L
CROSS_Z_MIN     <- -1.5

# ─────────────────────────────────────────────────────────────
# [A] Factor DB BULK PRELOAD — Arrow 1회 (OPT-1)
# ─────────────────────────────────────────────────────────────
FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
cat(sprintf("  [FDB] Arrow bulk preload: %s\n", FDB_DIR))

# .parquet 파일만 명시 — factor_registry.json 등 비-parquet 파일 제외
fdb_files <- list.files(FDB_DIR, pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("  [FDB] parquet 파일 수: %d\n", length(fdb_files)))

ds      <- open_dataset(fdb_files, format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% ALL_FDB_FACTORS) |>
  collect() |>
  as.data.table()
rm(ds)

cat(sprintf("  [FDB] %s rows | 팩터: %s\n",
            format(nrow(FDB_ALL), big.mark = ","),
            paste(sort(unique(FDB_ALL$Factor_Name)), collapse = ", ")))

registry <- .load_registry()
FDB_ALL  <- align_factor_direction(FDB_ALL, registry)
FDB_ALL[, Date := as.Date(Date)]
setkey(FDB_ALL, Date, Ticker)
gc(verbose = FALSE)

# ─────────────────────────────────────────────────────────────
# [B] Expanding CAPM Beta 벡터화 계산 (C2: t-1 lag)
# ─────────────────────────────────────────────────────────────
cat("  [Beta] Expanding-window CAPM beta 계산 중...\n")
setorder(RAWDATA, Ticker, Date)

if (!"BM_Ret" %in% names(RAWDATA)) {
  RAWDATA <- merge(RAWDATA, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
}

RAWDATA[, r_xy := Ret * BM_Ret]
RAWDATA[, r_x2 := BM_Ret ^ 2]
RAWDATA[, `:=`(
  cx  = cumsum(replace(BM_Ret, is.na(BM_Ret), 0)),
  cy  = cumsum(replace(Ret,    is.na(Ret),    0)),
  cxy = cumsum(replace(r_xy,   is.na(r_xy),   0)),
  cx2 = cumsum(replace(r_x2,   is.na(r_x2),   0)),
  cn  = cumsum(as.integer(!is.na(BM_Ret) & !is.na(Ret)))
), by = Ticker]

RAWDATA[, Beta_Raw := {
  n  <- cn
  mx <- cx / pmax(n, 1L); my <- cy / pmax(n, 1L)
  cv <- (cxy - n * mx * my) / pmax(n - 1L, 1L)
  vx <- (cx2 - n * mx ^ 2)  / pmax(n - 1L, 1L)
  ifelse(n >= BETA_WINDOW & vx > 1e-10, cv / vx, NA_real_)
}, by = Ticker]

RAWDATA[, Beta_Lag := shift(Beta_Raw, 1L, type = "lag"), by = Ticker]
RAWDATA[, c("r_xy","r_x2","cx","cy","cxy","cx2","cn","Beta_Raw") := NULL]
cat("  [Beta] 완료.\n")

# ─────────────────────────────────────────────────────────────
# [C] 유동성 사전 계산 (C10: t-1 lag)
# ─────────────────────────────────────────────────────────────
RAWDATA[, TV := Close * Vol]
RAWDATA[, LIQ20 := shift(frollmean(TV, 20L, align = "right"), 1L, type = "lag"), by = Ticker]

# ─────────────────────────────────────────────────────────────
# [D] 격월 시그널 날짜 — 홀수 월 말일
# ─────────────────────────────────────────────────────────────
RAWDATA[, YM := format(Date, "%Y-%m")]
ym_last <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
ym_last[, MN := as.integer(substr(YM, 6, 7))]
signal_dates <- sort(ym_last[MN %% 2 == 1L, Signal_Date])
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]
cat(sprintf("  [Signal dates] 격월 %d개 (%s ~ %s)\n",
            length(signal_dates), min(signal_dates), max(signal_dates)))

# ─────────────────────────────────────────────────────────────
# [E] 월별 시그널 생성 — lapply (루프 없음, OPT-1/OPT-3)
# ─────────────────────────────────────────────────────────────
.one_signal <- function(sig_d) {
  # 유동성 스냅샷 (t-1 값 이미 LIQ20에 저장됨)
  snap_cols <- c("Ticker", "LIQ20", "Beta_Lag")
  snap <- RAWDATA[Date == sig_d, .SD, .SDcols = snap_cols]
  snap <- snap[!is.na(LIQ20) & LIQ20 >= LIQ_THRESHOLD]

  # Beta percentile 필터
  snap_b <- snap[!is.na(Beta_Lag)]
  if (nrow(snap_b) < 30L) return(NULL)

  snap_b[, Bp := rank(Beta_Lag, ties.method = "average") / .N]
  n40 <- sum(snap_b$Bp <= BETA_CUTOFF)
  cutoff_used <- if (n40 >= MIN_UNIV_SIZE) BETA_CUTOFF else BETA_FALLBACK
  univ <- snap_b[Bp <= cutoff_used, .(Ticker)]
  if (nrow(univ) < 20L) return(NULL)

  # FDB 메모리 필터 (parquet 재로드 없음)
  fdt <- FDB_ALL[Date == sig_d]
  if (nrow(fdt) == 0L) return(NULL)

  fdt_main <- fdt[Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt_main) == 0L) return(NULL)

  wide <- dcast(fdt_main, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  dt   <- merge(univ, wide, by = "Ticker")

  # Cross-exposure 필터
  fdt_cx <- fdt[Factor_Name %in% CROSS_EXP_FACTORS]
  if (nrow(fdt_cx) > 0L) {
    cx_wide <- dcast(fdt_cx, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    dt <- merge(dt, cx_wide, by = "Ticker", all.x = TRUE)
    if ("AC21_Accrual_Quality" %in% names(dt))
      dt <- dt[is.na(AC21_Accrual_Quality) | AC21_Accrual_Quality > CROSS_Z_MIN]
    if ("M01_Momentum_12M" %in% names(dt))
      dt <- dt[is.na(M01_Momentum_12M) | M01_Momentum_12M > CROSS_Z_MIN]
    rm_cx <- intersect(CROSS_EXP_FACTORS, names(dt))
    if (length(rm_cx) > 0L) dt[, (rm_cx) := NULL]
  }
  if (nrow(dt) < 20L) return(NULL)

  fcols <- intersect(NEEDED_FACTORS, names(dt))
  if (length(fcols) == 0L) return(NULL)

  dt[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
  dt <- dt[!is.na(Score)]
  if (nrow(dt) < 10L) return(NULL)

  dt[, Date      := sig_d]
  dt[, n_factors := length(fcols)]
  dt[, .(Date, Ticker, Score, n_factors)]
}

factor_list <- lapply(signal_dates, .one_signal)
FACTORS     <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

n_done <- sum(!sapply(factor_list, is.null))
n_skip <- length(signal_dates) - n_done

# ─────────────────────────────────────────────────────────────
# [F] 결과 보고
# ─────────────────────────────────────────────────────────────
cat(sprintf("\n  FACTORS: %s rows | %d dates done (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))

rm_cols <- c("YM", "TV", "LIQ20", "Beta_Lag")
invisible(lapply(rm_cols, function(cn) {
  if (cn %in% names(RAWDATA)) RAWDATA[, (cn) := NULL]
}))
rm(FDB_ALL, factor_list); gc(verbose = FALSE)
