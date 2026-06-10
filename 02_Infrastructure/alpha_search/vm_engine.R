# =============================================================================
# vm_engine.R — Moreira & Muir (2017, JF) "Volatility-Managed Portfolios" 코어
# =============================================================================
# 논문 메커니즘(충실 복제):
#   f^σ_{t+1} = (c / σ̂²_t(f)) · f_{t+1}
#     σ̂²_t : 직전 1개월(month t) 일간수익으로 추정한 실현분산 (PIT: t시점 가용)
#     c    : managed가 unmanaged와 동일 (전기간) 변동성을 갖게 하는 정규화 상수
#            (단일 양(+)의 스칼라 → Sharpe/회귀-α t에 불변 = scale-invariant)
#   헤드라인 검정: managed를 unmanaged에 회귀한 α (유의 양(+) = 변동성 타이밍이 SR 개선)
#
# 본 엔진은 종목을 고르지 않는다(횡단면 X) — 단일 기저 시계열 f의 시계열 scaling.
#   run_alpha_search(횡단면 top-N 선택기)와 구조가 다르므로 별도 엔진으로 분리.
#
# 두 버전 산출:
#   (A) faithful     : 무제약 w = c_full/σ̂²  (레버리지 허용, 논문 원형). 회귀 α 헤드라인용.
#   (B) implementable: w = min(c_exp/σ̂², 1), 나머지 현금 (KR long-only no-leverage).
#                      c_exp = expanding-window 정규화(전기간 미사용 → PIT strict).
#
# PIT: σ̂²_t는 month t 일간수익만 사용 → month t+1 적용. c는 (A) scale-invariant,
#      (B) expanding이라 lookahead 없음. self-synthesis 없음(일간수익 = w·r 정의값,
#      equity/월간집계는 호출측 PerformanceAnalytics 경유).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(xts)
  library(PerformanceAnalytics)
}))

# Newey-West HAC 공분산 (Bartlett kernel, lag = floor(T^(1/3))) — sandwich 의존 회피,
# factor_portfolios.R `.nw_hac_vcov`와 동일 구현(자기상관/이분산 보정).
.vm_nw_vcov <- function(fit, L = NULL) {
  X <- stats::model.matrix(fit); u <- as.numeric(stats::residuals(fit)); n <- nrow(X)
  if (is.null(L)) L <- max(1L, floor(n^(1/3)))
  bread <- solve(crossprod(X)); Xu <- X * u; meat <- crossprod(Xu)
  for (l in seq_len(L)) {
    w <- 1 - l / (L + 1)
    G <- crossprod(Xu[(l + 1):n, , drop = FALSE], Xu[1:(n - l), , drop = FALSE])
    meat <- meat + w * (G + t(G))
  }
  bread %*% meat %*% bread
}

# ---- 1. 일간수익 → 월간 실현분산 + 월말 날짜 ---------------------------------
#  ret_dt: data.table(Date, Ret)  (기저자산 f의 일간 단순수익)
#  반환  : data.table(ym, MEnd, RV, NDays)  — RV = Σ_{d∈month}(r_d - r̄_month)²
.vm_monthly_rv <- function(ret_dt) {
  stopifnot(all(c("Date", "Ret") %in% names(ret_dt)))
  d <- copy(ret_dt)[is.finite(Ret)]
  setorder(d, Date)
  d[, ym := format(Date, "%Y-%m")]
  mv <- d[, .(MEnd = max(Date), NDays = .N,
              RV = sum((Ret - mean(Ret))^2)),   # 실현분산(평균제거). c가 상수배 흡수
           by = ym]
  setorder(mv, MEnd)
  mv[]
}

# ---- 2. vol-managed 일간 시계열 생성 ----------------------------------------
#  ret_dt          : data.table(Date, Ret) 기저 일간수익
#  min_hist_months : implementable c_exp 계산 최소 히스토리(이전엔 w=1 = 기저 보유)
#  cap             : implementable 노출 상한(no-leverage = 1.0)
#  반환 list(daily, monthly):
#    daily   : data.table(Date, Ret_base, Ret_faithful, Ret_impl, w_faithful, w_impl)
#    monthly : data.table(ym, MEnd, RV, w_faithful, w_impl)  (w_*는 *다음달 적용* 노출)
vm_managed_series <- function(ret_dt, min_hist_months = 24L, cap = 1.0) {
  d  <- copy(ret_dt)[is.finite(Ret)]; setorder(d, Date)
  d[, ym := format(Date, "%Y-%m")]
  mv <- .vm_monthly_rv(d)

  # u_t = 1/σ̂²_{t-1} : month t에 적용할 (정규화 전) 노출. shift(RV)로 직전월 분산.
  mv[, RV_lag := shift(RV, 1L, type = "lag")]           # PIT: month t는 month t-1 RV 사용
  mv[, u := ifelse(is.finite(RV_lag) & RV_lag > 0, 1 / RV_lag, NA_real_)]

  # 일간에 월별 u 매핑 (managed_raw_daily = u_month · r_daily)
  d <- merge(d, mv[, .(ym, RV_lag, u)], by = "ym", all.x = TRUE)
  setorder(d, Date)
  d[, mraw := u * Ret]                                   # 정규화 전 managed 일간

  # (A) faithful c: 전기간 동일 변동성 매칭 (scale-invariant → α/Sharpe 불변)
  ok <- is.finite(d$mraw) & is.finite(d$Ret)
  c_full <- if (sum(ok) > 30L) sd(d$Ret[ok]) / sd(d$mraw[ok]) else NA_real_
  d[, w_faithful := c_full * u]
  d[, Ret_faithful := w_faithful * Ret]                 # 무제약(레버리지 허용)

  # (B) implementable c_exp: expanding-window 정규화 (각 월말 시점 히스토리만)
  #   c_exp_t = sd(Ret[≤t-1]) / sd(mraw[≤t-1]).  부족분(min_hist) 이전엔 w=1.
  mvx <- merge(mv, unique(d[, .(ym)]), by = "ym")       # u/RV_lag 보유 월
  setorder(mvx, MEnd)
  # 월별 일간 통계 누적용: 각 월의 Ret, mraw 표준편차 누적은 일간을 expanding으로 봐야 정확.
  # → 월말까지의 일간 vector로 expanding sd 계산.
  months <- mvx$ym
  c_exp <- rep(NA_real_, length(months))
  for (i in seq_along(months)) {
    cutoff <- mvx$MEnd[i]
    sub <- d[Date <= cutoff & is.finite(mraw) & is.finite(Ret)]
    # 히스토리 충분(개월수) 검사
    n_m <- uniqueN(sub$ym)
    if (n_m >= min_hist_months && sd(sub$mraw) > 0)
      c_exp[i] <- sd(sub$Ret) / sd(sub$mraw)
  }
  mvx[, c_exp := c_exp]
  mvx[, w_impl := {
    w <- c_exp * u
    w[!is.finite(w)] <- 1.0                              # 히스토리 부족 → 기저 보유(w=1)
    pmin(pmax(w, 0), cap)                                # long-only no-leverage 캡
  }]

  d <- merge(d, mvx[, .(ym, w_impl)], by = "ym", all.x = TRUE)
  setorder(d, Date)
  d[!is.finite(w_impl), w_impl := 1.0]
  d[, Ret_impl := w_impl * Ret]                          # 나머지 현금(rf≈0)

  monthly <- mvx[, .(ym, MEnd, RV, w_faithful = c_full * u, w_impl)]
  daily <- d[, .(Date, Ret_base = Ret, Ret_faithful, Ret_impl, w_faithful, w_impl)]
  list(daily = daily, monthly = monthly, c_full = c_full)
}

# ---- 3. 헤드라인 검정: managed ~ unmanaged 회귀 α (NW HAC) -------------------
#  managed_xts, base_xts : 일간 수익 xts. 월간 집계(PerformanceAnalytics) 후 회귀.
#  반환 list(alpha_m, alpha_ann_pct, t, p, beta, r2, n)
vm_regression_alpha <- function(managed_xts, base_xts, nw_lag = NULL) {
  mm <- apply.monthly(managed_xts, Return.cumulative)
  bm <- apply.monthly(base_xts,    Return.cumulative)
  dt <- merge(mm, bm, join = "inner")
  dt <- dt[complete.cases(dt)]
  if (nrow(dt) < 24L) return(NULL)
  y <- as.numeric(dt[, 1]); x <- as.numeric(dt[, 2])
  fit <- lm(y ~ x)
  L <- if (is.null(nw_lag)) max(1L, floor(nrow(dt)^(1/3))) else nw_lag
  V  <- .vm_nw_vcov(fit, L = L)
  se <- sqrt(diag(V))
  cf <- coef(fit)
  tval <- cf / se
  pval <- 2 * stats::pt(abs(tval), df = nrow(dt) - 2L, lower.tail = FALSE)
  list(
    alpha_m       = unname(cf[1]),
    alpha_ann_pct = unname(cf[1]) * 12 * 100,
    alpha_t       = unname(tval[1]),
    alpha_p       = unname(pval[1]),
    beta          = unname(cf[2]),
    beta_t        = unname(tval[2]),
    r2            = summary(fit)$r.squared,
    n             = nrow(dt),
    nw_lag        = L
  )
}

# ---- 4. sim_result 호환 객체 구성 (기존 백엔드 재사용용) ---------------------
#  managed_daily : data.table(Date, Ret)  (전략 일간수익 — 보통 implementable)
#  bm_dt         : data.table(Date, BM_Ret)  벤치마크(시장)
#  monthly_w     : data.table(MEnd, w_impl) — turnover 산출용
build_vm_sim_result <- function(managed_daily, bm_dt, monthly_w) {
  md <- copy(managed_daily)[is.finite(Ret)]; setorder(md, Date)
  DAILY_NAV_DT <- md[, .(Date, Strategy_Ret = Ret)]
  strategy_xts <- xts(DAILY_NAV_DT$Strategy_Ret, order.by = DAILY_NAV_DT$Date)
  names(strategy_xts) <- "Strategy"
  bma <- bm_dt[Date %in% DAILY_NAV_DT$Date]
  bm_xts <- xts(bma$BM_Ret, order.by = bma$Date); names(bm_xts) <- "Benchmark"

  # 월간 turnover = |Δw| (노출 변화). 연율화 위해 PORTFOLIO_LOG에 적재.
  mw <- copy(monthly_w); setorder(mw, MEnd)
  mw[, dW := abs(w_impl - shift(w_impl, 1L, type = "lag"))]
  PORTFOLIO_LOG <- mw[is.finite(dW), .(Exec_Date = MEnd, Turnover_Pct = 100 * dW)]

  list(
    DAILY_NAV_DT  = DAILY_NAV_DT,
    PORTFOLIO_LOG = PORTFOLIO_LOG,
    HOLDINGS_LOG  = data.table(),
    strategy_xts  = strategy_xts,
    bm_xts        = bm_xts
  )
}

cat("[vm_engine] loaded — Moreira-Muir (2017) volatility-managed core.\n")
