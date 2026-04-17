## 핵심아이디어: AC17(Accrual Reversal) + L22(Ret Autocorr) + Q04(Piotroski F) × Low-Beta Filter
## Expanding-window CAPM beta 하위 40% 유니버스 → 3F EW z-score composite
## 역할: Diversifier (SR gap +0.757 기준)  RoleBias_Diversifier
##
## S0 Debate R2 승인 (63/100 APPROVE_CONDITIONAL) — H_1642_v2
## 3 economic_family: accrual × microstructure × quality
##
## PIT 체크리스트:
## C2: Beta expanding window t-1 lag 필수 (same-day circular 금지)
## C4: AC17/Q04 재무제표 → Factor DB Usable_Date lag 내부 처리
## C5: 오버레이 없음 (S1 순수 팩터)
## C9: DD/VT 없음 (S1)
## C10: 유동성 필터 → AvgTV20, t-1 lag (shift(frollmean(TradingValue,20),1))
## C13: Z_Score_Aligned만 사용. 수동 방향 반전 금지 (all higher_better)
## C14: Usable_Date 기반 접근 (load_month_factors 내부 처리)
## C15: Factor DB → load_month_factors() 경유 필수

cat("[factor_engine] STR_1642: AC17 + L22 + Q04 × Low-Beta(expanding) Filter...\n")

source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))

NEEDED_FACTORS <- c("AC17_Accrual_Reversal", "L22_Ret_Autocorr", "Q04_Piotroski_F")

# ---- 상수 ----
BETA_WINDOW    <- 252L       # expanding CAPM beta: 최소 252 거래일 후 시작
BETA_CUTOFF    <- 0.40       # 하위 40% 유니버스 포함
BETA_FALLBACK  <- 0.50       # 유니버스 < 80종목 시 완화
MIN_UNIV_SIZE  <- 80L        # 최소 유니버스 크기 (완화 전)
AC17_START     <- as.Date("2011-01-01")  # AC17 데이터 안정화 시작 (n≈175)

# ---- 사전 계산: expanding beta (C2 — t-1 lag) ----
# RAWDATA에서 CAPM beta 계산: Ret ~ BM_Ret, expanding window
# beta[t] = cov(R_i, R_m)[1:(t-1)] / var(R_m)[1:(t-1)]
# -> ecdf 기반 percentile: beta_pctile[t] = ecdf(beta[1:(t-1)])(beta[t])
# 최소 BETA_WINDOW일 필요 → 그 이전 구간은 NA

cat("  [Beta] Expanding-window CAPM beta 계산 중 (data.table 벡터화)...\n")

setorder(RAWDATA, Ticker, Date)

# BM_Ret을 RAWDATA에 merge (Date 기준)
if (!"BM_Ret" %in% names(RAWDATA)) {
  bm_sub <- BM_DT[, .(Date, BM_Ret)]
  RAWDATA <- merge(RAWDATA, bm_sub, by = "Date", all.x = TRUE)
}

# Expanding OLS beta: O(N) 누적합 방식
# beta(t) = Cov_xy / Var_x (expanding, t-1 lag)
# Cov_xy = (sum(x*y) - n*mean(x)*mean(y)) / (n-1)
# Var_x  = (sum(x^2) - n*mean(x)^2) / (n-1)
# C2: t-1 lag — shift 1 후 적용
RAWDATA[, xy := Ret * BM_Ret]
RAWDATA[, x2 := BM_Ret^2]

RAWDATA[, `:=`(
  cum_x  = cumsum(replace(BM_Ret, is.na(BM_Ret), 0)),
  cum_y  = cumsum(replace(Ret, is.na(Ret), 0)),
  cum_xy = cumsum(replace(xy, is.na(xy), 0)),
  cum_x2 = cumsum(replace(x2, is.na(x2), 0)),
  cum_n  = cumsum(as.integer(!is.na(BM_Ret) & !is.na(Ret)))
), by = Ticker]

# Expanding beta at row t = cov(x[1:t], y[1:t]) / var(x[1:t])
RAWDATA[, Beta_Raw := {
  n   <- cum_n
  mx  <- cum_x / pmax(n, 1L)
  my  <- cum_y / pmax(n, 1L)
  cov_xy <- (cum_xy - n * mx * my) / pmax(n - 1L, 1L)
  var_x  <- (cum_x2 - n * mx^2)   / pmax(n - 1L, 1L)
  ifelse(n >= BETA_WINDOW & var_x > 1e-10, cov_xy / var_x, NA_real_)
}, by = Ticker]

# C2: t-1 lag — 당일 신호에는 전날까지의 beta 사용
RAWDATA[, Beta_Lag := shift(Beta_Raw, 1L, type = "lag"), by = Ticker]

# 임시 컬럼 정리
RAWDATA[, c("xy", "x2", "cum_x", "cum_y", "cum_xy", "cum_x2", "cum_n", "Beta_Raw") := NULL]

cat("  [Beta] 완료. Expanding percentile 계산 진행...\n")

# ---- 유동성 사전 계산 ----
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"), 1L, type = "lag"),
        by = Ticker]

# ---- 월별 시그널 날짜 ----
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]

# ---- Prefeasibility 컨테이너 ----
pf_counts <- list(
  date        = character(0),
  n_liq       = integer(0),
  n_beta40    = integer(0),
  n_beta50    = integer(0),
  cutoff_used = numeric(0)
)

factor_list <- vector("list", length(signal_dates))
n_done <- 0L; n_skip <- 0L

for (i in seq_along(signal_dates)) {
  sig_d <- as.Date(signal_dates[i])

  # 유동성 + beta 스냅샷 (C10: AvgTV20 t-1 lag, C2: Beta_Lag t-1 lag)
  snap <- RAWDATA[Date == sig_d,
                  .(Ticker, Close, AvgTV20, Beta_Lag, Sector)]
  snap <- snap[!is.na(Close) & Close > 0 &
               !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  n_liq <- nrow(snap)

  # Beta percentile 계산: 해당 날짜 snap 내 Beta_Lag의 cross-sectional percentile
  snap_beta <- snap[!is.na(Beta_Lag)]
  n40 <- 0L; n50 <- 0L; cutoff_used <- BETA_CUTOFF

  if (nrow(snap_beta) >= 30L) {
    # Beta_Lag의 cross-sectional percentile (해당 날짜 기준)
    snap_beta[, Beta_Pctile := rank(Beta_Lag, ties.method = "average") / .N]
    n40 <- sum(snap_beta$Beta_Pctile <= BETA_CUTOFF)
    n50 <- sum(snap_beta$Beta_Pctile <= BETA_FALLBACK)

    # 유니버스 선택: 하위 40% 기본, 80종목 미달 시 50% 완화
    if (n40 >= MIN_UNIV_SIZE) {
      univ <- snap_beta[Beta_Pctile <= BETA_CUTOFF, .(Ticker)]
      cutoff_used <- BETA_CUTOFF
    } else {
      univ <- snap_beta[Beta_Pctile <= BETA_FALLBACK, .(Ticker)]
      cutoff_used <- BETA_FALLBACK
    }
    snap <- merge(univ, snap, by = "Ticker")
  } else {
    snap <- snap[0]  # beta 데이터 부족 → 스킵
  }

  # Prefeasibility 기록
  pf_counts$date        <- c(pf_counts$date, as.character(sig_d))
  pf_counts$n_liq       <- c(pf_counts$n_liq, n_liq)
  pf_counts$n_beta40    <- c(pf_counts$n_beta40, n40)
  pf_counts$n_beta50    <- c(pf_counts$n_beta50, n50)
  pf_counts$cutoff_used <- c(pf_counts$cutoff_used, cutoff_used)

  if (nrow(snap) < 20L) { n_skip <- n_skip + 1L; next }

  # ---- Factor DB 로드 (C15: load_month_factors 경유) ----
  fdt_all <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) NULL
  )
  if (is.null(fdt_all) || nrow(fdt_all) == 0L) { n_skip <- n_skip + 1L; next }

  # ---- 3F vs 2F 분기: AC17 가용 여부 (n=175, ~2011년~) ----
  avail_factors <- intersect(NEEDED_FACTORS, unique(fdt_all$Factor_Name))

  if (sig_d < AC17_START || !"AC17_Accrual_Reversal" %in% avail_factors) {
    # AC17 불가 → L22 + Q04 2F 운용
    use_factors <- c("L22_Ret_Autocorr", "Q04_Piotroski_F")
  } else {
    use_factors <- NEEDED_FACTORS
  }

  use_factors <- intersect(use_factors, avail_factors)
  if (length(use_factors) == 0L) { n_skip <- n_skip + 1L; next }

  # Wide format (C13: Z_Score_Aligned만 사용)
  fdt <- fdt_all[Factor_Name %in% use_factors]
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # 유니버스 join
  dt <- merge(snap[, .(Ticker)], fdt_wide, by = "Ticker")
  fcols <- intersect(use_factors, names(dt))
  if (length(fcols) == 0L) { n_skip <- n_skip + 1L; next }

  # EW composite (feedback_composite_zscore.md: z-score 합산)
  # C13: Z_Score_Aligned 원시값 그대로. 추가 rolling z-score 변환 금지 (L-591)
  dt[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
  dt <- dt[!is.na(Score)]
  if (nrow(dt) < 10L) { n_skip <- n_skip + 1L; next }

  dt[, Date := sig_d]
  dt[, n_factors := length(fcols)]
  factor_list[[i]] <- dt[, .(Date, Ticker, Score, n_factors)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

# ---- Prefeasibility 보고 ----
pf_dt <- as.data.table(pf_counts)
pf_recent <- pf_dt[date >= "2010-01-01"]

cat("\n======== Prefeasibility Check: Beta Universe ========\n")
if (nrow(pf_recent) > 0) {
  cat(sprintf("  전체 기간  Beta 40%%: mean=%.0f, min=%d, <80종목 월=%.1f%%\n",
              mean(pf_recent$n_beta40, na.rm=TRUE),
              min(pf_recent$n_beta40, na.rm=TRUE),
              sum(pf_recent$n_beta40 < MIN_UNIV_SIZE) / nrow(pf_recent) * 100))
  cat(sprintf("  완화(50%%) 적용 월: %d건 (전체 %.1f%%)\n",
              sum(pf_recent$cutoff_used > BETA_CUTOFF, na.rm=TRUE),
              sum(pf_recent$cutoff_used > BETA_CUTOFF, na.rm=TRUE) / nrow(pf_recent) * 100))
  cat(sprintf("  유동성 통과 평균 종목수: %.0f\n", mean(pf_recent$n_liq, na.rm=TRUE)))
}
cat("=====================================================\n\n")

# Prefeasibility 저장
saveRDS(pf_dt, file.path(output_dir, "prefeasibility_beta_universe.rds"))

# 임시 컬럼 정리
for (col in c("YM", "TradingValue", "AvgTV20", "Beta_Expanding", "Beta_Lag")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d dates done (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
