# =============================================================================
# bsc_engine.R — Barroso & Santa-Clara (2015, JFE) "Momentum has its moments"
#                risk-managed momentum 코어 (KR 충실 복제)
# =============================================================================
# 논문 메커니즘(충실 복제):
#   WML = 2x3 (size × prior 12-2) value-weighted L/S 모멘텀
#         = (Big High + Small High)/2 − (Big Low + Small Low)/2
#         월간 리밸런싱, prior return = t-12~t-2 (직전 1개월 skip)
#   위험관리: σ̂_t = 직전 126거래일 WML 일간수익 실현표준편차(연율화)
#            λ_t = σ_target / σ̂_t,  σ_target = 0.12 (12% 연율).  캡 없음(원전).
#            월간 빈도로 λ 갱신.  managed WML_t = λ_t · WML_t.
#   헤드라인 검정: managed를 unmanaged(raw WML)에 회귀한 α (논문 정의, 유의 양(+) =
#                위험관리가 SR 개선). + Sharpe/MDD/skew/kurtosis 비교 + 크래시 월.
#
# MM(Moreira-Muir)과 차이: MM은 c/σ²(분산 역수·scale-invariant 상수), BSC는
#   σ_target/σ̂(표준편차 역수·target-vol 명시 12%). BSC가 절대 노출 수준을 고정.
#
# ===== PIT (C1~C15) =====
#   - WML 시그널: prior return은 과거 가격(shift)만. 멤버십 K200/KQ150은 시그널 월말
#     시점 값(시변, PIT). 유동성은 t-1 (직전 20거래일 평균 거래대금). 동일시점 순환참조
#     없음 — 시그널 d에서 종목·비중 확정 후 (exec_date, next_exec] 일간수익 적용.
#   - σ̂_t (126d): 시그널 월말 d까지의 WML 일간수익만 (직전 126거래일). same-day 미사용.
#     λ_t는 month t에 확정되어 month t+1 적용 (C5/C9 정합).  full-sample 통계 없음(C1).
#   - VW 비중: Size(d) 사용 (월말 시총, PIT). 자체합성 없음 — leg/포트 수익 = Return.portfolio,
#     월간집계 = apply.monthly(Return.cumulative).  λ scaling은 일간수익에 직접 곱(정의값).
#
# 비용모델 한계(B0 2026-06-10): 엔진 비용 = 회전율 무관 flat per-rebalance 매수 15bps.
#   WML은 L/S 양다리(롱·숏 동시 회전) → one-way TO 산출·보고. TO>10x/yr이면 과소계상 경고.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
}))

# Newey-West HAC 공분산 (vm_engine .vm_nw_vcov 동일 구현)
.bsc_nw_vcov <- function(fit, L = NULL) {
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

# ---- 1. 월별 6-포트(2 size × 3 prior) VW leg 일간수익 + WML 구성 ----------------
#   RAWDATA: data.table(Date, Ticker, Close, Ret, Size, K200, KQ150)
#   반환 list:
#     daily   : data.table(Date, WML, Hi, Lo, BigHi, SmlHi, BigLo, SmlLo)  일간수익
#     monthly_holdings : data.table(MEnd, n_uni, n_hi, n_lo)  진단
#   prior return = Close[d-skip_d] / Close[d-look_d] - 1   (d = 시그널 월말)
bsc_build_wml <- function(RAWDATA, all_dates, sig_dates,
                          skip_d = 21L, look_d = 252L,
                          liq_thresh = 2e8, liq_win = 20L) {
  setorder(RAWDATA, Ticker, Date)
  # prior return (12-2): 직전 1개월(~21거래일) skip, 12개월(~252거래일) 룩백
  RAWDATA[, .prior := shift(Close, skip_d) / shift(Close, look_d) - 1, by = Ticker]
  # 유동성: t-1 기준 직전 liq_win 거래일 평균 거래대금(Close*Vol). 시그널일은 보지 않음(shift 1).
  RAWDATA[, .tv := Close * Vol]
  RAWDATA[, .adv := shift(frollmean(.tv, liq_win, align = "right"), 1L), by = Ticker]

  hi_list <- lo_list <- bighi_list <- smlhi_list <- biglo_list <- smllo_list <- vector("list", length(sig_dates))
  diag_list <- vector("list", length(sig_dates))

  build_port_daily <- function(picks, wts, exec_date, hold_end) {
    sub <- RAWDATA[Ticker %in% picks & Date >= exec_date & Date <= hold_end & is.finite(Ret),
                   .(Date, Ticker, Ret)]
    if (!nrow(sub)) return(NULL)
    w <- dcast(sub, Date ~ Ticker, value.var = "Ret")
    setorder(w, Date)
    rmat <- as.matrix(w[, -1, with = FALSE]); rmat[!is.finite(rmat)] <- 0
    rx <- xts(rmat, order.by = w$Date)
    # value-weight: Size(d) 기준. 보유종목 순서에 맞춰 정렬.
    cols <- colnames(rx)
    wv <- wts[match(cols, names(wts))]
    wv[!is.finite(wv)] <- 0
    if (sum(wv) <= 0) return(NULL)
    wv <- wv / sum(wv)
    pr <- tryCatch(Return.portfolio(rx, weights = wv, rebalance_on = NA),
                   error = function(e) NULL)
    if (is.null(pr)) return(NULL)
    data.table(Date = as.Date(index(pr)), Ret = as.numeric(pr[, 1]))
  }

  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    # 유니버스: K200∪KQ150 멤버십(시그널 월말 d, 시변 PIT) ∩ 유동성(t-1) ∩ 유효 prior/size
    md <- RAWDATA[Date == d & is.finite(.prior) & is.finite(Size) & Size > 0 &
                    (K200 %in% c(TRUE, 1) | KQ150 %in% c(TRUE, 1)) &
                    is.finite(.adv) & .adv >= liq_thresh,
                  .(Ticker, prior = .prior, size = Size)]
    n <- nrow(md); if (n < 30L) next
    # 2x3 독립 정렬: size median(NYSE 방식 대체 — KR 단일 median), prior 30/70 분위
    size_med <- median(md$size)
    p30 <- quantile(md$prior, 0.30); p70 <- quantile(md$prior, 0.70)
    md[, sgrp := ifelse(size <= size_med, "S", "B")]
    md[, pgrp := ifelse(prior <= p30, "L", ifelse(prior >= p70, "H", "M"))]

    exec_date <- get_execution_date(d, all_dates); if (is.na(exec_date)) next
    next_exec <- if (i < length(sig_dates)) get_execution_date(sig_dates[i + 1L], all_dates) else NA_Date_
    hold_end  <- if (!is.na(next_exec)) max(all_dates[all_dates < next_exec]) else max(all_dates)
    if (hold_end < exec_date) hold_end <- exec_date

    mk <- function(s, p) {
      x <- md[sgrp == s & pgrp == p]
      if (!nrow(x)) return(NULL)
      build_port_daily(x$Ticker, setNames(x$size, x$Ticker), exec_date, hold_end)
    }
    bighi_list[[i]] <- mk("B", "H"); smlhi_list[[i]] <- mk("S", "H")
    biglo_list[[i]] <- mk("B", "L"); smllo_list[[i]] <- mk("S", "L")
    diag_list[[i]] <- data.table(MEnd = d, n_uni = n,
                                 n_hi = sum(md$pgrp == "H"), n_lo = sum(md$pgrp == "L"))
  }
  RAWDATA[, c(".prior", ".tv", ".adv") := NULL]

  binder <- function(lst) {
    out <- rbindlist(Filter(Negate(is.null), lst), use.names = TRUE)
    if (!nrow(out)) return(NULL); setorder(out, Date)
    out[, .(Ret = mean(Ret)), by = Date]   # 경계 중복일 평균(연속 보유 정합)
  }
  bighi <- binder(bighi_list); smlhi <- binder(smlhi_list)
  biglo <- binder(biglo_list); smllo <- binder(smllo_list)
  if (is.null(bighi) || is.null(smlhi) || is.null(biglo) || is.null(smllo))
    stop("[bsc] 6-포트 leg 구성 실패(데이터 부족).")

  # 일간 정렬 merge → High = (BigHi+SmlHi)/2, Low = (BigLo+SmlLo)/2, WML = High-Low
  m <- Reduce(function(a, b) merge(a, b, by = "Date", all = TRUE), list(
    setnames(copy(bighi), "Ret", "BigHi"), setnames(copy(smlhi), "Ret", "SmlHi"),
    setnames(copy(biglo), "Ret", "BigLo"), setnames(copy(smllo), "Ret", "SmlLo")))
  for (cc in c("BigHi", "SmlHi", "BigLo", "SmlLo")) m[!is.finite(get(cc)), (cc) := 0]
  m[, Hi := (BigHi + SmlHi) / 2]
  m[, Lo := (BigLo + SmlLo) / 2]
  m[, WML := Hi - Lo]
  setorder(m, Date)
  list(daily = m, diag = rbindlist(Filter(Negate(is.null), diag_list), use.names = TRUE))
}

# ---- 2. BSC risk-managed scaling -------------------------------------------
#   wml_daily : data.table(Date, WML[, Hi])  WML 일간수익(+ long leg High)
#   sigma_target : 연율 목표변동성(0.12)
#   rv_win    : 실현변동성 윈도우(126 거래일)
#   반환 list(daily, monthly):
#     daily   : (Date, WML, WML_mgd, Hi, Hi_mgd, lambda)
#     monthly : (ym, MEnd, sigma_hat_ann, lambda)
bsc_managed_series <- function(wml_daily, sigma_target = 0.12, rv_win = 126L) {
  d <- copy(wml_daily); setorder(d, Date)
  d[, ym := format(Date, "%Y-%m")]
  # 월말 시점 σ̂ = 직전 rv_win 일간 WML sd × √252 (월말 d까지 정보만 = PIT)
  me <- d[, .(MEnd = max(Date)), by = ym]
  setorder(me, MEnd)
  sig_hat <- function(cutoff) {
    sub <- d[Date <= cutoff, WML]
    sub <- tail(sub[is.finite(sub)], rv_win)
    if (length(sub) < rv_win) return(NA_real_)
    sd(sub) * sqrt(252)
  }
  me[, sigma_hat_ann := vapply(MEnd, sig_hat, numeric(1))]
  # λ_t (month t 확정) → month t+1 적용. shift로 직전월 σ̂ 사용.
  me[, sigma_lag := shift(sigma_hat_ann, 1L, type = "lag")]
  me[, lambda := ifelse(is.finite(sigma_lag) & sigma_lag > 0, sigma_target / sigma_lag, NA_real_)]
  # 일간에 월별 λ 매핑
  d <- merge(d, me[, .(ym, lambda, sigma_hat_ann = sigma_lag)], by = "ym", all.x = TRUE)
  setorder(d, Date)
  # 히스토리 부족(초기) → λ=NA → managed 미정의: 해당 구간 제외(faithful은 레버리지 허용 무캡)
  d[, WML_mgd := lambda * WML]
  if ("Hi" %in% names(d)) {
    # implementable long-only: long leg(High)에 λ 캡 [0,1] 적용
    d[, lambda_cap := pmin(pmax(lambda, 0), 1)]
    d[, Hi_mgd := lambda_cap * Hi]   # 나머지 현금(rf≈0)
  }
  monthly <- me[, .(ym, MEnd, sigma_hat_ann, lambda)]
  list(daily = d, monthly = monthly)
}

# ---- 3. 헤드라인 검정: managed ~ raw WML 회귀 α (월간, NW HAC) ----------------
bsc_regression_alpha <- function(managed_xts, raw_xts, nw_lag = NULL) {
  mm <- apply.monthly(managed_xts, Return.cumulative)
  rr <- apply.monthly(raw_xts,     Return.cumulative)
  dt <- merge(mm, rr, join = "inner"); dt <- dt[complete.cases(dt)]
  if (nrow(dt) < 24L) return(NULL)
  y <- as.numeric(dt[, 1]); x <- as.numeric(dt[, 2])
  fit <- lm(y ~ x)
  L <- if (is.null(nw_lag)) max(1L, floor(nrow(dt)^(1/3))) else nw_lag
  V <- .bsc_nw_vcov(fit, L = L); se <- sqrt(diag(V)); cf <- coef(fit)
  tval <- cf / se
  pval <- 2 * stats::pt(abs(tval), df = nrow(dt) - 2L, lower.tail = FALSE)
  list(alpha_m = unname(cf[1]), alpha_ann_pct = unname(cf[1]) * 12 * 100,
       alpha_t = unname(tval[1]), alpha_p = unname(pval[1]),
       beta = unname(cf[2]), beta_t = unname(tval[2]),
       r2 = summary(fit)$r.squared, n = nrow(dt), nw_lag = L)
}

# ---- 4. 분포 통계 (skew/kurtosis, 월간수익 기준) ----------------------------
bsc_dist_stats <- function(ret_xts) {
  m <- as.numeric(apply.monthly(ret_xts[!is.na(ret_xts)], Return.cumulative))
  m <- m[is.finite(m)]
  list(skew = as.numeric(PerformanceAnalytics::skewness(m)),
       kurt = as.numeric(PerformanceAnalytics::kurtosis(m)),  # excess kurtosis
       worst_m = min(m), n_m = length(m))
}

# ---- 5. sim_result 호환 (implementable long-only → 백엔드 재사용) ------------
#   impl_daily : data.table(Date, Ret)  implementable 전략 일간수익
#   monthly_lam: data.table(MEnd, lambda_cap, n_hold) — turnover proxy
bsc_build_sim_result <- function(impl_daily, bm_dt, monthly_w) {
  md <- copy(impl_daily)[is.finite(Ret)]; setorder(md, Date)
  DAILY_NAV_DT <- md[, .(Date, Strategy_Ret = Ret)]
  strategy_xts <- xts(DAILY_NAV_DT$Strategy_Ret, order.by = DAILY_NAV_DT$Date); names(strategy_xts) <- "Strategy"
  bma <- bm_dt[Date %in% DAILY_NAV_DT$Date]
  bm_xts <- xts(bma$BM_Ret, order.by = bma$Date); names(bm_xts) <- "Benchmark"
  mw <- copy(monthly_w); setorder(mw, MEnd)
  mw[, dW := abs(w - shift(w, 1L, type = "lag"))]
  PORTFOLIO_LOG <- mw[is.finite(dW), .(Exec_Date = MEnd, Turnover_Pct = 100 * dW)]
  list(DAILY_NAV_DT = DAILY_NAV_DT, PORTFOLIO_LOG = PORTFOLIO_LOG,
       HOLDINGS_LOG = data.table(), strategy_xts = strategy_xts, bm_xts = bm_xts)
}

cat("[bsc_engine] loaded — Barroso & Santa-Clara (2015) risk-managed momentum core.\n")
