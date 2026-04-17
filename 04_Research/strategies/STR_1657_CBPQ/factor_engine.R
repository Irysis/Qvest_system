## STR_1657 CBPQ: Q35_CashBased_OpProf + Q09_CFOA + AC07_Operating_Accruals
## Beta 하위 40% 유니버스 제한 (expanding window, t-1 lag, C2)
## S1 순수 팩터 — overlay 없음
## Bimonthly rebalance (격월), EW N=20, commission=15bps
##
## 역할: Diversifier (RoleBias_Diversifier)
## 근거: Chib et al. (2025) Bayesian EFDR spanning test
##       Ball et al. (2016 JFE) cash-based profitability
##
## PIT:
##   C2  : Beta t-1 lag (expanding window, shift 1L)
##   C9  : Beta/LIQ 당일 미사용
##   C10 : LIQ20 t-1 lag
##   C13 : Z_Score_Aligned만 사용 (방향 반전 금지)
##   C14 : IC 접근 시 Usable_Date <= sig_date
##   C15 : FDB Arrow bulk preload 1회 (load_month_factors 경유 아닌 bulk 방식)
##
## OPT-1: Arrow open_dataset bulk preload 1회, lapply 메모리 필터만
## OPT-3: 인라인 NAV 루프 없음, run_monthly_simulation() 사용
##
## S0 조건:
##   COND_01: Q35-Q09 내부 상관 확인 (>0.7이면 하나 제거)
##   COND_03: AC07 한국 ICIR 확인 (<0.10이면 제거)

cat("[factor_engine] STR_1657: Q35 + Q09 + AC07 x Low-Beta(40%) Filter...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
library(arrow)
library(dplyr, warn.conflicts = FALSE)

NEEDED_FACTORS  <- c("Q35_CashBased_OpProf", "Q09_CFOA", "AC07_Operating_Accruals")

BETA_WINDOW     <- 252L     # expanding window: 최소 252일(약 1년) 데이터 필요
BETA_CUTOFF     <- 0.40     # Beta 하위 40%
BETA_FALLBACK   <- 0.50     # 유니버스 부족 시 fallback
MIN_UNIV_SIZE   <- 80L      # Beta 필터 후 최소 유니버스 크기
MIN_HOLDINGS    <- 20L      # 최소 종목수

# ─────────────────────────────────────────────────────────────
# [A] Factor DB BULK PRELOAD — Arrow 1회 (OPT-1, C15)
# ─────────────────────────────────────────────────────────────
FDB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
cat(sprintf("  [FDB] Arrow bulk preload: %s\n", FDB_DIR))

# .parquet 파일만 명시 — factor_registry.json 등 비-parquet 파일 제외
fdb_files <- list.files(FDB_DIR, pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("  [FDB] parquet 파일 수: %d\n", length(fdb_files)))

ds      <- open_dataset(fdb_files, format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  collect() |>
  as.data.table()
rm(ds)

cat(sprintf("  [FDB] %s rows | 팩터: %s\n",
            format(nrow(FDB_ALL), big.mark = ","),
            paste(sort(unique(FDB_ALL$Factor_Name)), collapse = ", ")))

# C13: Z_Score_Aligned 방향 정렬 (수동 반전 금지)
registry <- .load_registry()
FDB_ALL  <- align_factor_direction(FDB_ALL, registry)
FDB_ALL[, Date := as.Date(Date)]
setkey(FDB_ALL, Date, Ticker)
gc(verbose = FALSE)

# ─────────────────────────────────────────────────────────────
# [A2] S0 COND_01 + COND_03: 팩터 프로파일 확인
# ─────────────────────────────────────────────────────────────
cat("\n  [COND_01] Q35-Q09 내부 상관 검증...\n")
# 최근 60개월 cross-sectional 데이터로 스피어만 상관 계산
recent_dates <- sort(unique(FDB_ALL$Date), decreasing = TRUE)[1:60]
pair_wide <- dcast(
  FDB_ALL[Date %in% recent_dates &
          Factor_Name %in% c("Q35_CashBased_OpProf", "Q09_CFOA") &
          !is.na(Z_Score_Aligned)],
  Date + Ticker ~ Factor_Name,
  value.var = "Z_Score_Aligned"
)

if (ncol(pair_wide) >= 4L && nrow(pair_wide) >= 50L) {
  q35_vec <- pair_wide$Q35_CashBased_OpProf
  q09_vec <- pair_wide$Q09_CFOA
  valid_both <- !is.na(q35_vec) & !is.na(q09_vec)
  if (sum(valid_both) >= 50L) {
    corr_q35_q09 <- cor(q35_vec[valid_both], q09_vec[valid_both],
                        method = "spearman")
    cat(sprintf("  [COND_01] Q35-Q09 Spearman rho = %.3f\n", corr_q35_q09))
    if (corr_q35_q09 > 0.7) {
      # COND_01 위반: Q09 제거 (Q35가 더 포괄적인 Cash-based 지표)
      cat("  [COND_01] WARNING: rho > 0.70 — Q09 제거, Q35 + AC07 2팩터 composite 사용\n")
      NEEDED_FACTORS <- c("Q35_CashBased_OpProf", "AC07_Operating_Accruals")
      FDB_ALL <- FDB_ALL[Factor_Name %in% NEEDED_FACTORS]
    } else {
      cat("  [COND_01] PASS: rho <= 0.70 — 3팩터 유지\n")
    }
  } else {
    cat("  [COND_01] 데이터 부족 — 3팩터 유지\n")
    corr_q35_q09 <- NA_real_
  }
} else {
  cat("  [COND_01] 페어 데이터 부족 — 3팩터 유지\n")
  corr_q35_q09 <- NA_real_
}
assign("CBPQ_CORR_Q35_Q09", corr_q35_q09, envir = .GlobalEnv)
rm(pair_wide)

cat("\n  [COND_03] AC07 한국 ICIR 확인...\n")
# factor_ic_monthly.parquet에서 AC07 ICIR 확인 (C14: Usable_Date 기준)
tryCatch({
  ic_hist_path <- file.path(FDB_DIR, "factor_ic_monthly.parquet")
  if (file.exists(ic_hist_path)) {
    ic_dt <- as.data.table(read_parquet(ic_hist_path))
    ic_dt[, Date := as.Date(Date)]
    # C14: Usable_Date <= 현재 날짜 적용
    if ("Usable_Date" %in% names(ic_dt)) {
      ic_ac07 <- ic_dt[Factor_Name == "AC07_Operating_Accruals" &
                       Usable_Date <= Sys.Date()]
    } else {
      ic_ac07 <- ic_dt[Factor_Name == "AC07_Operating_Accruals" &
                       Date <= Sys.Date()]
    }
    if (nrow(ic_ac07) >= 12L) {
      ac07_icir <- mean(ic_ac07$IC, na.rm = TRUE) / sd(ic_ac07$IC, na.rm = TRUE)
      ac07_icir_36m <- {
        recent_ic <- tail(ic_ac07[order(Date)], 36L)
        if (nrow(recent_ic) >= 12L)
          mean(recent_ic$IC, na.rm = TRUE) / sd(recent_ic$IC, na.rm = TRUE)
        else NA_real_
      }
      cat(sprintf("  [COND_03] AC07 ICIR (전체) = %.3f | ICIR (최근 36M) = %.3f\n",
                  ac07_icir, ac07_icir_36m))
      if (!is.na(ac07_icir) && abs(ac07_icir) < 0.10) {
        cat("  [COND_03] WARNING: AC07 ICIR < 0.10 — AC07 제거, Q35 + Q09 2팩터 사용\n")
        NEEDED_FACTORS <- setdiff(NEEDED_FACTORS, "AC07_Operating_Accruals")
        FDB_ALL <- FDB_ALL[Factor_Name %in% NEEDED_FACTORS]
      } else {
        cat("  [COND_03] PASS: AC07 ICIR >= 0.10 — 유지\n")
      }
    } else {
      cat("  [COND_03] AC07 IC 이력 부족 — 유지 (default)\n")
      ac07_icir <- NA_real_
    }
    rm(ic_dt, ic_ac07)
  } else {
    cat("  [COND_03] factor_ic_monthly.parquet 미발견 — AC07 유지 (default)\n")
    ac07_icir <- NA_real_
  }
}, error = function(e) {
  cat("  [COND_03]", e$message, "\n")
  ac07_icir <<- NA_real_
})
assign("CBPQ_AC07_ICIR", ac07_icir, envir = .GlobalEnv)

cat(sprintf("\n  [팩터 구성] 최종: %s\n",
            paste(NEEDED_FACTORS, collapse = " + ")))
assign("CBPQ_ACTIVE_FACTORS", NEEDED_FACTORS, envir = .GlobalEnv)

# ─────────────────────────────────────────────────────────────
# [B] Expanding CAPM Beta 벡터화 계산 (C2: t-1 lag, C9)
# ─────────────────────────────────────────────────────────────
cat("  [Beta] Expanding-window CAPM beta 계산 중...\n")
setorder(RAWDATA, Ticker, Date)

if (!"BM_Ret" %in% names(RAWDATA)) {
  RAWDATA <- merge(RAWDATA, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
}

# Expanding 누적 합산 (벡터화, 루프 없음)
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
  # BETA_WINDOW 일수 이상 데이터 확보 후에만 유효 (warm-up)
  ifelse(n >= BETA_WINDOW & vx > 1e-10, cv / vx, NA_real_)
}, by = Ticker]

# C2/C9: t-1 lag — 당일 beta 사용 금지
RAWDATA[, Beta_Lag := shift(Beta_Raw, 1L, type = "lag"), by = Ticker]
RAWDATA[, c("r_xy","r_x2","cx","cy","cxy","cx2","cn","Beta_Raw") := NULL]
cat("  [Beta] 완료.\n")

# ─────────────────────────────────────────────────────────────
# [C] 유동성 사전 계산 (C10: t-1 lag)
# ─────────────────────────────────────────────────────────────
RAWDATA[, TV := Close * Vol]
# C10: 20일 평균 거래대금을 t-1 lag — 당일 거래량 사용 금지
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
  # [E1] 유동성 스냅샷 (LIQ20 = t-1 값 이미 저장됨, C10)
  snap_cols <- c("Ticker", "LIQ20", "Beta_Lag")
  snap <- RAWDATA[Date == sig_d, .SD, .SDcols = snap_cols]
  snap <- snap[!is.na(LIQ20) & LIQ20 >= LIQ_THRESHOLD]

  # [E2] Beta percentile 필터 (Beta_Lag = t-1, C2/C9)
  snap_b <- snap[!is.na(Beta_Lag)]
  if (nrow(snap_b) < 30L) return(NULL)

  snap_b[, Bp := rank(Beta_Lag, ties.method = "average") / .N]
  n40 <- sum(snap_b$Bp <= BETA_CUTOFF)
  cutoff_used <- if (n40 >= MIN_UNIV_SIZE) BETA_CUTOFF else BETA_FALLBACK
  univ <- snap_b[Bp <= cutoff_used, .(Ticker)]
  if (nrow(univ) < MIN_HOLDINGS) return(NULL)

  # [E3] FDB 메모리 필터 (parquet 재로드 없음, OPT-1)
  fdt <- FDB_ALL[Date == sig_d & Factor_Name %in% NEEDED_FACTORS]
  if (nrow(fdt) == 0L) return(NULL)

  wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  dt   <- merge(univ, wide, by = "Ticker")

  if (nrow(dt) < MIN_HOLDINGS) return(NULL)

  # [E4] Composite Score — Z_Score_Aligned 단순 평균 (C13: 수동 반전 금지)
  fcols <- intersect(NEEDED_FACTORS, names(dt))
  if (length(fcols) == 0L) return(NULL)

  dt[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
  dt <- dt[!is.na(Score)]
  if (nrow(dt) < MIN_HOLDINGS) return(NULL)

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
cat(sprintf("  Active factors: %s\n", paste(NEEDED_FACTORS, collapse = " + ")))

rm_cols <- c("YM", "TV", "LIQ20", "Beta_Lag")
invisible(lapply(rm_cols, function(cn) {
  if (cn %in% names(RAWDATA)) RAWDATA[, (cn) := NULL]
}))
rm(FDB_ALL, factor_list); gc(verbose = FALSE)
