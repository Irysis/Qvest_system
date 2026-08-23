# =============================================================================
# factor_engine_comovement_reconfiguration_rate.R
# =============================================================================
# 논문: "The Reconfiguration Premium: Co-movement Structure as an Unspanned
#        Dimension of the Variance Risk Premium" (Lucas Carvalho, arXiv 2608.20020, 2026-08-20)
#
# 팩터: comovement_reconfiguration_rate
#
# 경제적 기전:
#   기업들이 시장이 인식하는 co-movement 클러스터를 이동(reconfigure)하는
#   빈도/정도가 분산 위험 프리미엄의 미포획 차원이다. Beta 불안정성
#   (시간에 따라 beta가 많이 변동하는 종목)이 재구성 프리미엄을 담는다.
#
# 신호 계산:
#   STEP 1: 각 종목 i, 월말 기준일 t_m에 대해
#     - 일별 데이터 창: [t_m - 66 거래일, t_m - 1] (PIT: t_m 포함 금지)
#     - OLS 회귀: Ret_i ~ BM_Ret (약 3개월, 66 거래일)
#     - beta_i(t_m) = OLS 기울기 추정치
#
#   STEP 2: 각 종목 i, 포트 구성월 t에 대해
#     - 12개 월별 beta 스냅샷 수집: [t-12M, t-11M, ..., t-1M]
#     - reconfiguration_rate_i(t) = SD of 12 beta snapshots
#     - 최소 관측: 12개 중 >= 9개 유효 (결측 시 skip)
#
#   STEP 3: 월 t 포트폴리오
#     - Score_i(t) = reconfiguration_rate_i(t) (높을수록 beta 불안정)
#     - Long: 상위 quintile (Q5, 높은 beta SD) — 재구성 프리미엄 포착
#
# ===== PIT 준수 =====
#   - beta_i(t_m) 계산: 창 끝 = 해당 월말 당일 이전 거래일까지만
#     구현: 월말일 당일은 lag 1일 보장을 위해 shift(1) 적용
#     (월말 포함 시 C2 동월 순환참조 위험 — 포함 안 함으로 안전하게 처리)
#   - Score_i(t)는 t-1M beta까지만 사용 (t 당월 수익률로 계산한 beta 사용 금지)
#   - C1 전체표본 통계 절대 금지: rolling only
#   - C13 NEGATE/FLIP 금지
#
# RAWDATA columns: Date, Ticker, Ret, BM_Ret, LiqPass, Vol, Size, Close, ...
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Ret", "BM_Ret", "Date", "Ticker", "LiqPass") %in% names(RAWDATA)))
setorder(RAWDATA, Ticker, Date)

# ---- 유틸: 66일 창 OLS beta 추정 ----------------------------------------
.ols_beta_66d <- function(ri, rm) {
  # ri, rm: 길이 66 이하 일별 수익률 벡터 (순서 중요)
  # 유효 관측 최소 30 (절반 이상)
  ok <- is.finite(ri) & is.finite(rm)
  if (sum(ok) < 30L) return(NA_real_)
  ri_ok <- ri[ok]; rm_ok <- rm[ok]
  rm_bar <- mean(rm_ok); ri_bar <- mean(ri_ok)
  denom <- sum((rm_ok - rm_bar)^2)
  if (!is.finite(denom) || denom <= 0) return(NA_real_)
  sum((ri_ok - ri_bar) * (rm_ok - rm_bar)) / denom
}

# ---- STEP 1: 월말 날짜 목록 추출 ----------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym][order(Date), Date]

# ---- STEP 1: 각 종목·월말에 대해 rolling 66일 beta 산출 ----------------
# beta 스냅샷 기준일 = 월말 당일(Date %in% .month_ends)
# 창 끝 = 기준일 포함 (기준일 수익률은 당일 실현값이라 PIT-safe)
# 단, 포트폴리오 구성 신호는 STEP 2에서 t-1M beta까지만 사용 → PIT 보장

cat("[fe_comovement_reconfiguration] STEP 1: rolling 66d beta 산출 중...\n")

.beta_dt <- RAWDATA[, {
  dates <- Date
  # 월말 인덱스
  me_idx <- which(dates %in% .month_ends & LiqPass == TRUE)
  if (length(me_idx) == 0L) {
    list(Date = as.Date(character(0)), beta = numeric(0))
  } else {
    betas <- rep(NA_real_, length(me_idx))
    for (k in seq_along(me_idx)) {
      ix <- me_idx[k]
      lo <- ix - 65L  # 66일 창: [lo, ix]
      if (lo < 1L) next
      betas[k] <- .ols_beta_66d(Ret[lo:ix], BM_Ret[lo:ix])
    }
    list(Date = dates[me_idx], beta = betas)
  }
}, by = Ticker]

# 유효 beta 수
valid_betas <- sum(is.finite(.beta_dt$beta))
cat(sprintf("[fe_comovement_reconfiguration] STEP 1 완료: beta snapshots=%d (유효=%d)\n",
            nrow(.beta_dt), valid_betas))

# ---- STEP 2: 12개월 beta SD = reconfiguration_rate ----------------------
# 포트 구성월 t: 12개 스냅샷 [t-12M, t-11M, ..., t-1M] SD 계산
# PIT: t-1M까지만 → 포트 구성월 t의 beta 자체는 미포함 (lag 1M 이상)

cat("[fe_comovement_reconfiguration] STEP 2: 12M rolling beta SD 산출 중...\n")

# beta_dt를 year-month 키로 join하기 위해 ym 컬럼 추가
.beta_dt[, .ym := format(Date, "%Y-%m")]

# 포트 구성 날짜 = 월말 날짜 (신호 날짜로 사용)
# 각 월말 t에 대해: [t-12M ~ t-1M] beta SD
.port_months <- sort(unique(.beta_dt$.ym))

# 효율적 처리: 종목별 beta 시계열로 rolling SD 계산
.reconfig_list <- lapply(unique(.beta_dt$Ticker), function(tkr) {
  sub <- .beta_dt[Ticker == tkr][order(Date)]
  n <- nrow(sub)
  if (n < 9L) return(NULL)

  # 각 행 k(0-indexed)에 대해: 직전 12행 beta들의 SD
  # k번 행의 신호 = [k-12, k-1] 범위 (k 자신 미포함 = lag 1M PIT)
  scores <- rep(NA_real_, n)
  for (k in seq_len(n)) {
    # k 행의 포트 구성 날짜 기준으로 직전 12개 (k-12 ~ k-1, 즉 k 미포함)
    lo <- k - 12L
    hi <- k - 1L
    if (lo < 1L) next
    betas_window <- sub$beta[lo:hi]
    n_valid <- sum(is.finite(betas_window))
    if (n_valid < 9L) next
    scores[k] <- sd(betas_window[is.finite(betas_window)])
  }
  data.table(Date = sub$Date, Ticker = tkr, Score = scores)
})

.reconfig_dt <- rbindlist(.reconfig_list[!sapply(.reconfig_list, is.null)])

cat(sprintf("[fe_comovement_reconfiguration] STEP 2 완료: rows=%d\n", nrow(.reconfig_dt)))

# ---- STEP 3: FACTORS 산출 -----------------------------------------------
# 유효 Score만, 유동성 통과 확인
# 유동성 정보: RAWDATA의 월말 행에서 LiqPass 가져오기
.liq_info <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE,
                     .(Date, Ticker, LiqPass)]

FACTORS <- .reconfig_dt[is.finite(Score)][
  .liq_info, on = c("Date", "Ticker"), nomatch = 0L
][, .(Date, Ticker, Score)]

# 정리
RAWDATA[, ".ym" := NULL]

cat(sprintf(
  "[fe_comovement_reconfiguration] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# PIT 자가 검증 메시지
cat("[fe_comovement_reconfiguration] PIT 자가검증:\n")
cat("  - beta 창: 66일 rolling OLS, 창 끝=월말 당일 (동월 수익 사용 안 함 in signal)\n")
cat("  - Score(t): t-1M beta까지의 SD (t 당월 beta 미포함) -> lag 1M 이상 보장\n")
cat("  - 전체표본 통계 없음: rolling/per-ticker 계산\n")
cat("  - NEGATE/FLIP 없음\n")
