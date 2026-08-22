# =============================================================================
# factor_engine_vol_hurst.R — VOL_HURST 팩터 엔진
# =============================================================================
# 논문: Bianchi, Ceccato, et al. (2026) arXiv:2608.16749
#       "Rough Volatility Across Assets"
#
# 팩터 아이디어:
#   개별 주식의 일별 실현변동성(RV = r^2, 제곱 로그수익률)이 나타내는
#   Hurst 지수 H를 R/S Analysis(Rescaled Range)로 추정.
#   논문 핵심 발견: 미국 3,926개 주식의 H 중앙값 ≈ 0.13 (rough, H<0.5=반-지속성).
#   횡단면 팩터로 활용: H가 낮은 종목(더 거친 변동성) vs H가 높은 종목 비교.
#
# 부호 가설 (이 엔진은 낮은-H 프리미엄 가설):
#   낮은 H = 더 거칠고 예측하기 어려운 변동성 = 위험 프리미엄 요구 → 고수익?
#   Score = -H (낮은 H → 높은 Score → 매수 우선)
#   즉: low-H 종목을 long. 반대 가설(high-H)은 별도 엔진 참조.
#
# PIT 체크리스트:
#   [C1]  rolling 252 거래일 window만 — 전체표본 통계 없음
#   [C2]  월말 스냅샷 후 t+1월 수익률 평가 — 동일시점 순환참조 없음
#   [C3]  동기간 집계-적용 없음
#   [C5]  홀딩월 시작 전 데이터만 사용 (월말 snap → 다음달 수익률)
#   [C10] 유동성 필터는 LiqPass (20일 평균TV ≥ 2e8, 전일 기준 — 당일 TV 미사용)
#
# RV 정의:
#   rv_t = r_t^2,  r_t = log(Close_t / Close_{t-1}) (RAWDATA Ret 컬럼 사용)
#   Ret 컬럼은 이미 종가 로그수익률로 계산된 값임 (RAWDATA 계약)
#
# R/S Analysis (Rescaled Range):
#   sub-windows n in c(22, 44, 66, 132, 252) 거래일
#   각 n에 대해 non-overlapping 블록에서 E[R(n)/S(n)] 계산:
#     R(n) = range(cumsum(rv - mean(rv)))
#     S(n) = sd(rv)
#   OLS: log(E[R(n)/S(n)]) = H * log(n) + const → slope = H
#   유효 점 < 3이면 NA
#
# 구현 주의:
#   - Ret^2를 rv로 사용 (RAWDATA Ret = log-return)
#   - 월별 252일 rolling 처리 → 계산량 많음, 종목별 순차 처리
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

# ---- Hurst R/S 함수 (RV 시계열 입력) ----------------------------------------
# x: numeric vector (RV = r^2, non-negative)
# sub_windows: 크기 단계
hurst_rs_rv <- function(x, sub_windows = c(22L, 44L, 66L, 132L, 252L)) {
  x <- x[!is.na(x) & x >= 0]
  n <- length(x)
  if (n < 60L) return(NA_real_)

  valid_wins <- sub_windows[sub_windows <= n]
  if (length(valid_wins) < 3L) return(NA_real_)

  rs_vals <- vapply(valid_wins, function(m) {
    n_blocks <- floor(n / m)
    if (n_blocks < 2L) return(NA_real_)
    # non-overlapping 블록 순차 처리
    rs_blk <- numeric(n_blocks)
    for (b in seq_len(n_blocks)) {
      blk <- x[((b - 1L) * m + 1L):(b * m)]
      S <- sd(blk)
      if (!is.finite(S) || S <= 0) { rs_blk[b] <- NA_real_; next }
      dev <- cumsum(blk - mean(blk))
      R   <- max(dev) - min(dev)
      rs_blk[b] <- R / S
    }
    rs_blk_ok <- rs_blk[is.finite(rs_blk) & rs_blk > 0]
    if (length(rs_blk_ok) == 0L) NA_real_ else mean(rs_blk_ok)
  }, numeric(1L))

  valid_idx <- is.finite(rs_vals) & rs_vals > 0
  if (sum(valid_idx) < 3L) return(NA_real_)

  log_n  <- log(valid_wins[valid_idx])
  log_rs <- log(rs_vals[valid_idx])
  # OLS slope
  H_val  <- coef(lm(log_rs ~ log_n))[2L]
  if (!is.finite(H_val) || H_val < 0 || H_val > 1.5) return(NA_real_)
  H_val
}

# ---- 데이터 정렬 및 준비 -------------------------------------------------------
setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ym := format(Date, "%Y-%m")]

.month_ends_dt  <- RAWDATA[, .(me_Date = max(Date)), by = .ym]
.month_end_set  <- .month_ends_dt[["me_Date"]]

cat(sprintf("[fe_vol_hurst] 월말 거래일 %d개 | 데이터 %s ~ %s\n",
            length(.month_end_set),
            format(min(RAWDATA$Date)),
            format(max(RAWDATA$Date))))

WIN <- 252L  # rolling 252 거래일 (논문 명시)

# ---- 종목별 거래일 순번 부여 --------------------------------------------------
RAWDATA[, .tidx := seq_len(.N), by = Ticker]

# ---- 월말 인덱스 패널 ----------------------------------------------------------
.me_panel <- RAWDATA[Date %in% .month_end_set,
                     .(Ticker, Date, .tidx, LiqPass)]

cat(sprintf("[fe_vol_hurst] 월말 패널: %d행, 종목 %d개\n",
            nrow(.me_panel), uniqueN(.me_panel$Ticker)))

# ---- RV = Ret^2 일별 패널 준비 -----------------------------------------------
# RAWDATA$Ret = 로그수익률 (이미 계약으로 보장)
RAWDATA_RV <- RAWDATA[, .(Ticker, .tidx, rv = Ret^2)]
setkey(RAWDATA_RV, Ticker, .tidx)

# ---- 종목별 순차 처리 ---------------------------------------------------------
.tickers   <- unique(.me_panel$Ticker)
.res_list  <- vector("list", length(.tickers))

cat(sprintf("[fe_vol_hurst] 종목 %d개 RV-Hurst 연산 시작...\n", length(.tickers)))

for (i in seq_along(.tickers)) {
  tk <- .tickers[i]
  dk <- RAWDATA_RV[.(tk), nomatch = 0L]

  rv_vec   <- dk$rv
  idxs_vec <- dk$.tidx

  me_tk <- .me_panel[Ticker == tk]
  rows  <- vector("list", nrow(me_tk))

  for (j in seq_len(nrow(me_tk))) {
    end_idx   <- me_tk$.tidx[j]
    start_idx <- end_idx - WIN + 1L
    if (start_idx < 1L) {
      rows[[j]] <- list(Ticker = tk, Date = me_tk$Date[j],
                        H_val  = NA_real_, LiqPass = me_tk$LiqPass[j])
      next
    }
    mask    <- idxs_vec >= start_idx & idxs_vec <= end_idx
    H_est   <- hurst_rs_rv(rv_vec[mask])
    rows[[j]] <- list(Ticker = tk, Date = me_tk$Date[j],
                      H_val  = H_est, LiqPass = me_tk$LiqPass[j])
  }
  .res_list[[i]] <- rbindlist(rows)

  if (i %% 100L == 0L)
    cat(sprintf("  [fe_vol_hurst] %d / %d 종목 완료\n", i, length(.tickers)))
}

FACTORS_RAW <- rbindlist(.res_list, fill = TRUE)
rm(.res_list, dk, rows); gc(verbose = FALSE)

# ---- H 분포 진단 --------------------------------------------------------------
H_valid <- FACTORS_RAW$H_val[is.finite(FACTORS_RAW$H_val)]
cat(sprintf("[fe_vol_hurst] H 유효 관측 %d건\n", length(H_valid)))
if (length(H_valid) > 0) {
  cat(sprintf("[fe_vol_hurst] H: min=%.4f  Q25=%.4f  median=%.4f  Q75=%.4f  max=%.4f\n",
              min(H_valid),
              quantile(H_valid, 0.25),
              median(H_valid),
              quantile(H_valid, 0.75),
              max(H_valid)))
}

# ---- 부호 설정: low-H 프리미엄 가설 ------------------------------------------
# Score = -H  →  낮은 H 종목이 상위 순위 (low-H long 포트폴리오)
# PIT 위반 없음: 모두 과거 252일 롤링 추정값
FACTORS <- FACTORS_RAW[LiqPass == TRUE & is.finite(H_val),
                        .(Date, Ticker, Score = -H_val)]

cat(sprintf("[fe_vol_hurst] FACTORS (low-H 부호): %d행 | 유효 날짜 %d개\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

# ---- RAWDATA 임시 컬럼 정리 ---------------------------------------------------
RAWDATA[, c(".ym", ".tidx") := NULL]
rm(RAWDATA_RV, FACTORS_RAW, .me_panel, .month_end_set, .month_ends_dt)
gc(verbose = FALSE)
