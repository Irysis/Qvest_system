# =============================================================================
# dm_engine.R — Daniel & Moskowitz (2016, JFE) "Momentum crashes"
#               dynamic momentum 코어 (KR 충실 복제)
# =============================================================================
# 논문 메커니즘(충실 복제 — w20439 NBER WP / JFE 122:221-247):
#   WML(decile) = D10(winners) − D1(losers), value-weighted, 월간 리밸런싱.
#     랭킹 = 누적수익 t-12~t-2 (직전 1개월 skip, 12-2). 10분위(decile) 브레이크포인트.
#     (DM: 유니버스=NYSE/AMEX/NASDAQ common, NYSE breakpoints. KR=K200∪KQ150 단일분위.)
#   bear indicator  I_B,t-1 = 1 if 과거 24개월(2년) 누적 시장수익 < 0, else 0.  (line 1236-37)
#   μ̂_{t-1} = E_{t-1}[R_WML,t] 예측. eq(4) 회귀의 interaction proxy(논문 Table 5 마지막 열,
#     line 1318-1323): R_WML,t = γ0 + γB·I_B + γσ2m·σ̂²_m + γint·(I_B·σ̂²_m) + ε.
#     σ̂²_m = 직전 126거래일 일간 시장수익 분산. (★PIT: 본 구현은 expanding-window OOS로
#     매월 γ 재추정 — DM 원전은 in-sample 전기간 추정이나 도훈 mandate PIT 준수 위해 OOS.
#     DM도 §4 OOS 버전 제시. 이는 명시적 보충/일탈.)
#   σ̂²_{t-1} = E_{t-1}[(R_WML,t−μ)²] 예측. DM: GJR-GARCH 예측 + 직전 126일 WML 실현분산의
#     선형결합(line 1340-42). 본 구현 = 126일 WML 실현분산(연율²) 주축 (BSC 엔진과 동일
#     실현변동성 추정 재사용). GARCH 성분은 보충 미구현(명시) — 실현분산 단독.
#   weight  eq(5):  w*_{t-1} = (1/2λ)·(μ̂_{t-1} / σ̂²_{t-1}).
#     λ = in-sample 연율변동성이 target_vol(=19%, DM은 CRSP-VW 전기간 vol)이 되도록 스케일.
#     ★λ는 전기간 실현변동성 매칭 상수 1개 — vol 매칭은 비교가능성(DM Fig.5 정의)이며
#     수익 lookahead 아님(BSC σ_target과 동격, 분산정규화 상수). w 자체는 PIT(μ̂·σ̂² 모두 t-1).
#
#   비교 3종 (DM Fig.5 정의):
#     1. raw WML  (static $1-long/$1-short, 무스케일)
#     2. cvol     (constant-vol = BSC형, σ_target/σ̂ scaling, target_vol 매칭)
#     3. dyn      (dynamic = eq(5), μ̂/σ̂², target_vol 매칭)
#   헤드라인 = dyn~raw 회귀 α (위험관리·μ타이밍 증분) + Sharpe/MDD + dyn~cvol 증분.
#
# ===== PIT (C1~C15) =====
#   - WML 시그널: prior return 과거 가격(shift)만. 멤버십 시그널 월말(시변). 유동성 t-1.
#     동일시점 순환참조 없음 — 시그널 d 확정 후 (exec_date, next_exec] 일간수익 적용.
#   - I_B,t-1: 직전 24개월 시장 누적수익(월말 d 이전 정보만). σ̂²_m: 직전 126일 시장수익.
#   - μ̂ 회귀: expanding-window(t 시점까지 데이터만)로 γ 추정 → t+1 적용 (OOS, full-sample 금지).
#   - σ̂²_WML: 직전 126일 WML 일간수익 분산(월말 d까지만). λ·μ̂·σ̂² 모두 t-1 → w_t PIT.
#   - 자체합성 없음 — leg/포트 수익 = Return.portfolio, 월간집계 = apply.monthly(Return.cumulative).
#
# 비용모델 한계(B0 2026-06-10): 엔진 비용 = 회전율 무관 flat per-rebalance 매수 15bps.
#   WML L/S 양다리 + dynamic 레버리지 → one-way TO 과소계상 가능(명시 보고).
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics)
}))

# Newey-West HAC 공분산 (bsc_engine .bsc_nw_vcov 동일 구현)
.dm_nw_vcov <- function(fit, L = NULL) {
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

# ---- 1. WML decile(D10−D1) VW 일간수익 구성 ---------------------------------
#   RAWDATA: data.table(Date, Ticker, Close, Vol, Ret, Size, K200, KQ150)
#   prior return = Close[d-skip_d]/Close[d-look_d]-1  (d=시그널 월말, 12-2)
#   반환 list:
#     daily : data.table(Date, WML, Win, Los)  일간수익 (Win=D10 long leg)
#     diag  : data.table(MEnd, n_uni, n_win, n_los)
dm_build_wml_decile <- function(RAWDATA, all_dates, sig_dates,
                                skip_d = 21L, look_d = 252L,
                                liq_thresh = 2e8, liq_win = 20L,
                                n_deciles = 10L) {
  setorder(RAWDATA, Ticker, Date)
  RAWDATA[, .prior := shift(Close, skip_d) / shift(Close, look_d) - 1, by = Ticker]
  RAWDATA[, .tv := Close * Vol]
  RAWDATA[, .adv := shift(frollmean(.tv, liq_win, align = "right"), 1L), by = Ticker]

  win_list <- los_list <- vector("list", length(sig_dates))
  diag_list <- vector("list", length(sig_dates))

  build_port_daily <- function(picks, wts, exec_date, hold_end) {
    sub <- RAWDATA[Ticker %in% picks & Date >= exec_date & Date <= hold_end & is.finite(Ret),
                   .(Date, Ticker, Ret)]
    if (!nrow(sub)) return(NULL)
    w <- dcast(sub, Date ~ Ticker, value.var = "Ret"); setorder(w, Date)
    rmat <- as.matrix(w[, -1, with = FALSE]); rmat[!is.finite(rmat)] <- 0
    rx <- xts(rmat, order.by = w$Date)
    cols <- colnames(rx); wv <- wts[match(cols, names(wts))]; wv[!is.finite(wv)] <- 0
    if (sum(wv) <= 0) return(NULL)
    wv <- wv / sum(wv)
    pr <- tryCatch(Return.portfolio(rx, weights = wv, rebalance_on = NA), error = function(e) NULL)
    if (is.null(pr)) return(NULL)
    data.table(Date = as.Date(index(pr)), Ret = as.numeric(pr[, 1]))
  }

  for (i in seq_along(sig_dates)) {
    d <- sig_dates[i]
    md <- RAWDATA[Date == d & is.finite(.prior) & is.finite(Size) & Size > 0 &
                    (K200 %in% c(TRUE, 1) | KQ150 %in% c(TRUE, 1)) &
                    is.finite(.adv) & .adv >= liq_thresh,
                  .(Ticker, prior = .prior, size = Size)]
    n <- nrow(md); if (n < 30L) next
    # decile 분위: prior 기준 n_deciles 등분. 최하 = Losers(D1), 최상 = Winners(D10).
    brks <- quantile(md$prior, probs = seq(0, 1, length.out = n_deciles + 1L), na.rm = TRUE)
    md[, dec := cut(prior, breaks = brks, include.lowest = TRUE, labels = FALSE)]
    md[is.na(dec) & prior <= brks[2], dec := 1L]
    md[is.na(dec) & prior >= brks[length(brks) - 1L], dec := n_deciles]

    exec_date <- get_execution_date(d, all_dates); if (is.na(exec_date)) next
    next_exec <- if (i < length(sig_dates)) get_execution_date(sig_dates[i + 1L], all_dates) else NA_Date_
    hold_end  <- if (!is.na(next_exec)) max(all_dates[all_dates < next_exec]) else max(all_dates)
    if (hold_end < exec_date) hold_end <- exec_date

    win <- md[dec == n_deciles]; los <- md[dec == 1L]
    if (nrow(win) < 3L || nrow(los) < 3L) next
    win_list[[i]] <- build_port_daily(win$Ticker, setNames(win$size, win$Ticker), exec_date, hold_end)
    los_list[[i]] <- build_port_daily(los$Ticker, setNames(los$size, los$Ticker), exec_date, hold_end)
    diag_list[[i]] <- data.table(MEnd = d, n_uni = n, n_win = nrow(win), n_los = nrow(los))
  }
  RAWDATA[, c(".prior", ".tv", ".adv") := NULL]

  binder <- function(lst) {
    out <- rbindlist(Filter(Negate(is.null), lst), use.names = TRUE)
    if (!nrow(out)) return(NULL); setorder(out, Date)
    out[, .(Ret = mean(Ret)), by = Date]
  }
  win <- binder(win_list); los <- binder(los_list)
  if (is.null(win) || is.null(los)) stop("[dm] decile leg 구성 실패(데이터 부족).")
  m <- merge(setnames(copy(win), "Ret", "Win"), setnames(copy(los), "Ret", "Los"),
             by = "Date", all = TRUE)
  for (cc in c("Win", "Los")) m[!is.finite(get(cc)), (cc) := 0]
  m[, WML := Win - Los]; setorder(m, Date)
  list(daily = m, diag = rbindlist(Filter(Negate(is.null), diag_list), use.names = TRUE))
}

# ---- 2. bear indicator + 시장 126일 분산 (월말 시점, PIT) --------------------
#   BM_DT: data.table(Date, BM_Ret)  시장(벤치마크) 일간수익
#   month_ends: 시그널 월말 벡터
#   반환 data.table(MEnd, I_B, sig2_m)  — 모두 직전 정보만(t-1)
dm_bear_and_mktvar <- function(BM_DT, month_ends, bear_lookback_m = 24L, var_win = 126L) {
  b <- copy(BM_DT)[is.finite(BM_Ret)]; setorder(b, Date)
  out <- data.table(MEnd = sort(month_ends))
  out[, I_B := NA_real_]; out[, sig2_m := NA_real_]
  for (i in seq_len(nrow(out))) {
    d <- out$MEnd[i]
    # 24개월 누적수익: 월말 d 이전(포함) 일간수익으로 직전 24개월. PIT — d까지만.
    cutoff_24m <- seq(d, length.out = 2, by = paste0("-", bear_lookback_m, " months"))[2]
    r24 <- b[Date > cutoff_24m & Date <= d, BM_Ret]
    if (length(r24) >= 20L) {
      cum24 <- prod(1 + r24) - 1   # 누적수익 (지표 산출용, Sharpe 분자 아님 — 부호만 사용)
      out$I_B[i] <- as.numeric(cum24 < 0)
    }
    # 126일 시장 분산: d 이전(포함) 직전 var_win 거래일 일간수익 분산.
    r126 <- tail(b[Date <= d, BM_Ret], var_win)
    if (length(r126) >= var_win) out$sig2_m[i] <- var(r126)
  }
  out[]
}

# ---- 3. μ̂ 예측 (eq.4 interaction proxy, expanding-window OOS) ---------------
#   wml_monthly: data.table(ym, MEnd, WML_m)  월간 WML 수익
#   bear_dt    : data.table(MEnd, I_B, sig2_m)
#   반환 data.table(MEnd, mu_hat, I_B, sig2_m, X_int)  — mu_hat = t+1 적용 예측(PIT)
#   X_int = I_B,t-1 · σ̂²_m,t-1 (eq.4 interaction term)
dm_forecast_mu <- function(wml_monthly, bear_dt = NULL, min_obs = 60L) {
  # bear_dt=NULL이면 wml_monthly가 이미 I_B/sig2_m 포함(pre-merged) 가정.
  d <- if (is.null(bear_dt)) copy(wml_monthly) else merge(copy(wml_monthly), bear_dt, by = "MEnd", all.x = TRUE)
  setorder(d, MEnd)
  d[, X_int := I_B * sig2_m]          # 핵심 예측변수 (interaction)
  d[, mu_hat := NA_real_]
  # expanding window: 시점 i의 mu_hat은 [1, i-1] 데이터로 회귀 추정 후 i의 X로 예측.
  #   R_WML,t = γ0 + γB·I_B + γσ2m·σ̂²_m + γint·X_int + ε  (eq.4 full)
  for (i in seq_len(nrow(d))) {
    train <- d[seq_len(i - 1L)]
    train <- train[is.finite(WML_m) & is.finite(I_B) & is.finite(sig2_m) & is.finite(X_int)]
    if (nrow(train) < min_obs) next
    cur <- d[i]
    if (!is.finite(cur$I_B) || !is.finite(cur$sig2_m) || !is.finite(cur$X_int)) next
    fit <- tryCatch(lm(WML_m ~ I_B + sig2_m + X_int, data = train), error = function(e) NULL)
    if (is.null(fit)) next
    cf <- coef(fit)
    d$mu_hat[i] <- cf[["(Intercept)"]] +
      (if ("I_B" %in% names(cf)) cf[["I_B"]] * cur$I_B else 0) +
      (if ("sig2_m" %in% names(cf)) cf[["sig2_m"]] * cur$sig2_m else 0) +
      (if ("X_int" %in% names(cf)) cf[["X_int"]] * cur$X_int else 0)
  }
  d[]
}

# ---- 4. dynamic weighting eq(5) + cvol(BSC형) -------------------------------
#   wml_daily: data.table(Date, WML, Win)
#   mu_dt    : data.table(MEnd, mu_hat, I_B, sig2_m)  (월별 μ̂)
#   target_vol: 연율 목표변동성 (DM=0.19). λ·c 매칭 기준.
#   rv_win   : WML 실현분산 윈도우(126).
#   반환 list(daily, monthly):
#     daily: (Date, ym, WML, Win, sig2_wml, mu_hat, w_dyn, WML_dyn, lambda_cvol, WML_cvol)
dm_dynamic_series <- function(wml_daily, mu_dt, target_vol = 0.19, rv_win = 126L) {
  d <- copy(wml_daily); setorder(d, Date)
  d[, ym := format(Date, "%Y-%m")]
  me <- d[, .(MEnd = max(Date)), by = ym]; setorder(me, MEnd)

  # σ̂²_WML 월말 = 직전 rv_win 일간 WML 분산 (연율²). PIT — 월말 d까지만.
  sig2_wml_fn <- function(cutoff) {
    sub <- tail(d[Date <= cutoff & is.finite(WML), WML], rv_win)
    if (length(sub) < rv_win) return(NA_real_)
    var(sub) * 252            # 연율 분산 (일간분산 × 252)
  }
  me[, sig2_wml := vapply(MEnd, sig2_wml_fn, numeric(1))]
  # σ̂_ann (constant-vol BSC형용)
  me[, sigma_wml_ann := sqrt(sig2_wml)]
  # t-1 적용: month t 확정 → month t+1. shift.
  me[, sig2_wml_lag := shift(sig2_wml, 1L, type = "lag")]
  me[, sigma_wml_lag := shift(sigma_wml_ann, 1L, type = "lag")]

  # μ̂ (이미 t+1 적용 예측, dm_forecast_mu에서 expanding) — 월말 MEnd 기준 join
  me <- merge(me, mu_dt[, .(MEnd, mu_hat, I_B, sig2_m)], by = "MEnd", all.x = TRUE)
  setorder(me, MEnd)

  # eq(5): w_dyn ∝ μ̂ / σ̂²_WML  (μ̂ 월간수익, σ̂² 연율분산 → 월간분산으로 환산: /12)
  #   상수 (1/2λ)는 전기간 vol 매칭으로 사후 결정 → 우선 raw ratio 산출.
  me[, w_raw := ifelse(is.finite(mu_hat) & is.finite(sig2_wml_lag) & sig2_wml_lag > 0,
                       mu_hat / (sig2_wml_lag / 12), NA_real_)]
  # constant-vol BSC형 λ = target_vol / σ̂ (캡 없음, faithful)
  me[, lambda_cvol := ifelse(is.finite(sigma_wml_lag) & sigma_wml_lag > 0,
                             target_vol / sigma_wml_lag, NA_real_)]

  # 일간 매핑
  d <- merge(d, me[, .(ym, sig2_wml = sig2_wml_lag, sigma_wml = sigma_wml_lag,
                       mu_hat, I_B, sig2_m, w_raw, lambda_cvol)], by = "ym", all.x = TRUE)
  setorder(d, Date)
  d[, WML_dyn_raw := w_raw * WML]
  d[, WML_cvol := lambda_cvol * WML]

  # λ(dynamic) 상수: 전기간 in-sample 연율변동성 = target_vol 매칭 (DM Fig.5 정의).
  #   c_dyn = target_vol / annualized_vol(WML_dyn_raw)
  sub_dyn <- d[is.finite(WML_dyn_raw), WML_dyn_raw]
  ann_vol_dyn_raw <- if (length(sub_dyn) > 30L) sd(sub_dyn) * sqrt(252) else NA_real_
  c_dyn <- if (is.finite(ann_vol_dyn_raw) && ann_vol_dyn_raw > 0) target_vol / ann_vol_dyn_raw else NA_real_
  d[, WML_dyn := c_dyn * WML_dyn_raw]
  d[, w_dyn := c_dyn * w_raw]

  monthly <- me[, .(ym, MEnd, sig2_wml = sig2_wml_lag, sigma_wml = sigma_wml_lag,
                    mu_hat, I_B, sig2_m, w_raw, lambda_cvol)]
  monthly[, w_dyn := c_dyn * w_raw]
  list(daily = d, monthly = monthly, c_dyn = c_dyn, target_vol = target_vol)
}

# ---- 5. 헤드라인 회귀 α: y ~ x (월간, NW HAC) -------------------------------
dm_regression_alpha <- function(y_xts, x_xts, nw_lag = NULL) {
  yy <- apply.monthly(y_xts, Return.cumulative); xx <- apply.monthly(x_xts, Return.cumulative)
  dt <- merge(yy, xx, join = "inner"); dt <- dt[complete.cases(dt)]
  if (nrow(dt) < 24L) return(NULL)
  y <- as.numeric(dt[, 1]); x <- as.numeric(dt[, 2])
  fit <- lm(y ~ x)
  L <- if (is.null(nw_lag)) max(1L, floor(nrow(dt)^(1/3))) else nw_lag
  V <- .dm_nw_vcov(fit, L = L); se <- sqrt(diag(V)); cf <- coef(fit); tval <- cf / se
  pval <- 2 * stats::pt(abs(tval), df = nrow(dt) - 2L, lower.tail = FALSE)
  list(alpha_m = unname(cf[1]), alpha_ann_pct = unname(cf[1]) * 12 * 100,
       alpha_t = unname(tval[1]), alpha_p = unname(pval[1]),
       beta = unname(cf[2]), beta_t = unname(tval[2]),
       r2 = summary(fit)$r.squared, n = nrow(dt), nw_lag = L)
}

# ---- 6. 분포 통계 (skew/kurt, 월간) ----------------------------------------
dm_dist_stats <- function(ret_xts) {
  m <- as.numeric(apply.monthly(ret_xts[!is.na(ret_xts)], Return.cumulative))
  m <- m[is.finite(m)]
  list(skew = as.numeric(PerformanceAnalytics::skewness(m)),
       kurt = as.numeric(PerformanceAnalytics::kurtosis(m)),
       worst_m = min(m), n_m = length(m))
}

# ---- 7. sim_result 호환 (implementable long-only → 백엔드 재사용) -----------
#   impl_daily: data.table(Date, Ret)  implementable 전략 일간수익
#   monthly_w : data.table(MEnd, w)    turnover proxy
dm_build_sim_result <- function(impl_daily, bm_dt, monthly_w) {
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

cat("[dm_engine] loaded — Daniel & Moskowitz (2016) dynamic momentum core.\n")
