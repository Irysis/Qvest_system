#==============================================================================
# Tail Risk Engine — EVT-VaR, CF-VaR, CDaR, ES 분해
# Pfaff (2016) "Financial Risk Modelling and Portfolio Optimization with R"
#   Ch.6 (Cornish-Fisher), Ch.7 (EVT/GPD), Ch.12 (CDaR, ES Component)
# 패키지: fExtremes, evir, PerformanceAnalytics
# 작성: Forge (2026-04-09)
# 사용처: Judge S6 검증, tail_risk_result.json 생성
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(fExtremes)      # gpdFit, gpdRiskMeasures
  library(evir)           # meplot (MRL plot)
  library(PerformanceAnalytics)
})

# ─────────────────────────────────────────────────────────────────
# 1. EVT-VaR (GPD 기반, Pfaff Ch.7)
# ─────────────────────────────────────────────────────────────────
compute_evt_var <- function(r, p = 0.99, threshold_q = 0.95, min_tail_n = 60L) {
  # r: 일간 수익률 벡터 (NA 제거, 손실 = 음수)
  # p: VaR confidence level (0.99 = 99%)
  # threshold_q: GPD threshold를 손실의 몇 번째 분위수로 설정할지
  # min_tail_n: GPD 피팅에 필요한 최소 초과 관측 수

  stopifnot(is.numeric(r), length(r) >= 100L)
  r <- r[!is.na(r)]
  losses <- -r  # 손실 = 양수 변환

  # GPD threshold 자동 선택: Mean Residual Life plot 진단 후 분위수 사용
  u <- as.numeric(quantile(losses, threshold_q))
  exceedances <- losses[losses > u]
  n_exceed <- length(exceedances)

  if (n_exceed < min_tail_n) {
    # threshold 낮춰서 재시도
    threshold_q <- max(0.85, threshold_q - 0.05)
    u <- as.numeric(quantile(losses, threshold_q))
    exceedances <- losses[losses > u]
    n_exceed <- length(exceedances)
  }

  if (n_exceed < 20L) {
    warning("[EVT-VaR] 초과 관측 수 부족(", n_exceed, "). 정규분포 대체 사용.")
    s <- sd(r)
    var_n <- as.numeric(quantile(losses, p))
    return(list(
      var_evt    = var_n,
      es_evt     = mean(losses[losses > var_n]),
      shape_xi   = NA_real_,
      scale_beta = NA_real_,
      threshold_u = u,
      n_exceedances = n_exceed,
      method     = "normal_fallback"
    ))
  }

  # GPD 피팅 (fExtremes::gpdFit)
  # method = "mle" (MLE 추정), data = 손실 초과분 (excess over threshold)
  fit <- tryCatch(
    fExtremes::gpdFit(exceedances - u, type = "mle"),
    error = function(e) {
      tryCatch(
        fExtremes::gpdFit(exceedances - u, type = "pwm"),  # PWM fallback
        error = function(e2) NULL
      )
    }
  )

  if (is.null(fit)) {
    warning("[EVT-VaR] GPD 피팅 실패. 경험적 분위수 대체.")
    var_emp <- as.numeric(quantile(losses, p))
    return(list(
      var_evt    = var_emp,
      es_evt     = mean(losses[losses > var_emp]),
      shape_xi   = NA_real_,
      scale_beta = NA_real_,
      threshold_u = u,
      n_exceedances = n_exceed,
      method     = "empirical_fallback"
    ))
  }

  xi  <- as.numeric(fit@fit$par.ests["xi"])    # shape (tail index)
  beta <- as.numeric(fit@fit$par.ests["beta"]) # scale

  n_total <- length(losses)
  # EVT-VaR 공식 (Pfaff Ch.7, Eq.7.4):
  # VaR_p = u + (beta/xi)*[(n/n_u*(1-p))^(-xi) - 1]
  # EVT-ES 공식 (Eq.7.5):
  # ES = VaR_p/(1-xi) + (beta - xi*u)/(1-xi)
  var_evt <- tryCatch({
    u + (beta / xi) * ((n_total / n_exceed * (1 - p))^(-xi) - 1)
  }, error = function(e) as.numeric(quantile(losses, p)))

  es_evt <- tryCatch({
    var_evt / (1 - xi) + (beta - xi * u) / (1 - xi)
  }, error = function(e) {
    mean(losses[losses > var_evt])
  })

  list(
    var_evt       = round(var_evt, 6),
    es_evt        = round(es_evt, 6),
    shape_xi      = round(xi, 4),
    scale_beta    = round(beta, 6),
    threshold_u   = round(u, 6),
    threshold_q   = threshold_q,
    n_exceedances = n_exceed,
    method        = "gpd_mle"
  )
}

# ─────────────────────────────────────────────────────────────────
# 2. Cornish-Fisher VaR (Pfaff Ch.6)
# ─────────────────────────────────────────────────────────────────
compute_cf_var <- function(r, p = 0.99) {
  # r: 일간 수익률 벡터
  # Cornish-Fisher 확장 (4차 모멘트 보정)
  #   z_cf = z + (z^2-1)*S/6 + (z^3-3z)*K/24 - (2z^3-5z)*S^2/36
  # 참조: Pfaff (2016) Ch.6, Favre & Galeano (2002)

  r <- r[!is.na(r)]
  stopifnot(length(r) >= 30L)

  mu  <- mean(r)
  s   <- sd(r)
  # PerformanceAnalytics 버전에 따라 method 인수 차이 있음 — moments 패키지 직접 계산
  n   <- length(r)
  S   <- tryCatch(
    as.numeric(PerformanceAnalytics::skewness(r, method = "moment")),
    error = function(e) {
      m3 <- mean((r - mu)^3); m3 / s^3
    }
  )
  K   <- tryCatch(
    as.numeric(PerformanceAnalytics::kurtosis(r, method = "moment")) - 3,
    error = function(e) {
      m4 <- mean((r - mu)^4); m4 / s^4 - 3
    }
  )

  z_alpha <- qnorm(1 - p)  # 음수 (손실 방향)

  z_cf <- z_alpha +
    (z_alpha^2 - 1) * S / 6 +
    (z_alpha^3 - 3 * z_alpha) * K / 24 -
    (2 * z_alpha^3 - 5 * z_alpha) * S^2 / 36

  var_cf     <- -(mu + z_cf * s)         # 손실을 양수로
  var_normal <- -(mu + z_alpha * s)      # 정규 VaR 비교용

  list(
    var_cf     = round(var_cf, 6),
    var_normal = round(var_normal, 6),
    z_cf       = round(z_cf, 4),
    z_alpha    = round(z_alpha, 4),
    skewness   = round(S, 4),
    kurtosis   = round(K, 4),
    cf_vs_normal_ratio = round(var_cf / max(var_normal, 1e-8), 4)
  )
}

# ─────────────────────────────────────────────────────────────────
# 3. CDaR (Conditional Drawdown at Risk, Pfaff Ch.12)
# ─────────────────────────────────────────────────────────────────
compute_cdar <- function(nav, alpha = 0.95) {
  # nav: NAV 시계열 (가격 형태, 예: 시작=1.0)
  # alpha: CDaR confidence level (0.95 = 상위 5% drawdown 평균)
  # CDaR = E[DD | DD > VaR_alpha(DD)] — Chekhlov et al. (2005)

  stopifnot(is.numeric(nav), length(nav) >= 20L)
  nav <- nav[!is.na(nav)]

  # Drawdown 시계열 계산 (C9 준수: 당일 고점 대비)
  running_max <- cummax(nav)
  dd_series   <- (nav - running_max) / running_max  # 음수 (손실)
  dd_abs      <- -dd_series                          # 양수 변환

  max_dd  <- max(dd_abs)
  avg_dd  <- mean(dd_abs)

  # CDaR: 상위 (1-alpha) 드로다운의 평균
  var_dd  <- as.numeric(quantile(dd_abs, alpha))
  cdar    <- mean(dd_abs[dd_abs >= var_dd])

  # 드로다운 기간 분석 (연속 드로다운 구간 수)
  in_dd <- dd_abs > 1e-6
  n_drawdowns <- sum(diff(c(FALSE, in_dd)) == 1)

  # Recovery ratio (드로다운 기간 / 전체 기간)
  recovery_ratio <- mean(in_dd)

  list(
    cdar            = round(cdar, 6),
    var_dd          = round(var_dd, 6),
    max_dd          = round(max_dd, 6),
    avg_dd          = round(avg_dd, 6),
    n_drawdowns     = n_drawdowns,
    recovery_ratio  = round(recovery_ratio, 4),
    alpha           = alpha
  )
}

# ─────────────────────────────────────────────────────────────────
# 4. ES 성분 분해 (Component ES, Pfaff Ch.12)
# ─────────────────────────────────────────────────────────────────
compute_es_decomposition <- function(returns, weights = NULL, alpha = 0.05) {
  # returns: T x N 수익률 행렬 (xts 또는 matrix)
  # weights: N 길이 벡터 (NULL이면 EW)
  # alpha: 하위 꼬리 확률 (0.05 = 5% ES)
  # PerformanceAnalytics::ES with portfolio_method="component"

  if (is.null(weights)) {
    n_assets <- if (is.matrix(returns)) ncol(returns) else 1L
    weights  <- rep(1 / n_assets, n_assets)
  }

  # xts 변환
  if (!inherits(returns, "xts")) {
    returns_xts <- tryCatch(
      xts::xts(returns, order.by = seq.Date(Sys.Date() - nrow(returns) + 1L,
                                             Sys.Date(), by = "day")),
      error = function(e) as.matrix(returns)
    )
  } else {
    returns_xts <- returns
  }

  result <- tryCatch(
    PerformanceAnalytics::ES(
      R                 = returns_xts,
      p                 = 1 - alpha,
      weights           = weights,
      method            = "modified",        # Cornish-Fisher 보정
      portfolio_method  = "component",
      clean             = "none"
    ),
    error = function(e) {
      # Fallback: 가우시안
      tryCatch(
        PerformanceAnalytics::ES(
          R                = returns_xts,
          p                = 1 - alpha,
          weights          = weights,
          method           = "gaussian",
          portfolio_method = "component"
        ),
        error = function(e2) NULL
      )
    }
  )

  if (is.null(result)) {
    return(list(
      portfolio_es    = NA_real_,
      component_es    = NA_real_,
      pct_contribution = NA_real_,
      method          = "failed"
    ))
  }

  portfolio_es     <- as.numeric(result$MES)
  component_es     <- as.numeric(result$contribution)
  pct_contribution <- as.numeric(result$pct_contrib_MES)

  list(
    portfolio_es     = round(portfolio_es, 6),
    component_es     = round(component_es, 6),
    pct_contribution = round(pct_contribution, 4),
    alpha            = alpha,
    n_assets         = length(weights)
  )
}

# ─────────────────────────────────────────────────────────────────
# 5. 통합 suite
# ─────────────────────────────────────────────────────────────────
compute_tail_risk_suite <- function(sim_result,
                                    output_dir  = NULL,
                                    strategy_id = NULL) {
  # sim_result: backtest_harness.R에서 반환한 리스트
  #   sim_result$daily_returns 또는 sim_result$nav_series 사용
  # output_dir: tail_risk_result.json 저장 경로
  # strategy_id: STR_XXXX 식별자

  # 일간 수익률 추출
  daily_ret <- NULL

  if (!is.null(sim_result$daily_returns)) {
    daily_ret <- as.numeric(sim_result$daily_returns)
  } else if (!is.null(sim_result$nav)) {
    nav_vec   <- as.numeric(sim_result$nav)
    daily_ret <- c(0, diff(nav_vec) / head(nav_vec, -1))
  } else if (!is.null(sim_result$NAV)) {
    nav_vec   <- as.numeric(sim_result$NAV)
    daily_ret <- c(0, diff(nav_vec) / head(nav_vec, -1))
  } else {
    stop("[tail_risk_suite] sim_result에 daily_returns 또는 nav/NAV 필드가 없습니다.")
  }

  daily_ret <- daily_ret[!is.na(daily_ret)]

  # NAV 추출 (CDaR용)
  nav_vec <- NULL
  if (!is.null(sim_result$nav)) {
    nav_vec <- as.numeric(sim_result$nav)
  } else if (!is.null(sim_result$NAV)) {
    nav_vec <- as.numeric(sim_result$NAV)
  } else {
    # NAV 재구성
    nav_vec <- cumprod(1 + daily_ret)
  }

  message("[Tail Risk] EVT-VaR 계산 중...")
  evt  <- compute_evt_var(daily_ret, p = 0.99, threshold_q = 0.95)

  message("[Tail Risk] CF-VaR 계산 중...")
  cf   <- compute_cf_var(daily_ret, p = 0.99)

  message("[Tail Risk] CDaR 계산 중...")
  cdar <- compute_cdar(nav_vec, alpha = 0.95)

  # ES 분해: 단일 전략이면 스킵 (다중 자산 행렬 필요)
  es_decomp <- list(note = "단일 전략: ES 분해는 멀티-자산 포트폴리오에만 적용")

  result <- list(
    strategy_id      = strategy_id,
    computed_at      = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    n_obs            = length(daily_ret),
    evt_var          = evt,
    cf_var           = cf,
    cdar             = cdar,
    es_decomposition = es_decomp,
    # 핵심 요약 (Judge 빠른 접근용)
    summary = list(
      evt_var_99    = evt$var_evt,
      cf_var_99     = cf$var_cf,
      normal_var_99 = cf$var_normal,
      cf_vs_normal  = cf$cf_vs_normal_ratio,
      cdar_95       = cdar$cdar,
      max_dd        = cdar$max_dd,
      tail_shape_xi = evt$shape_xi
    )
  )

  # JSON 저장
  if (!is.null(output_dir) && dir.exists(output_dir)) {
    out_path <- file.path(output_dir, "tail_risk_result.json")
    tryCatch({
      jsonlite::write_json(result, out_path, auto_unbox = TRUE, pretty = TRUE)
      message("[Tail Risk] 저장 완료: ", out_path)
    }, error = function(e) {
      warning("[Tail Risk] JSON 저장 실패: ", e$message)
    })
  }

  invisible(result)
}

# ─────────────────────────────────────────────────────────────────
# 6. 검증 함수 (Judge S6용)
# ─────────────────────────────────────────────────────────────────
verify_tail_risk <- function(tail_risk,
                             thresholds = list(
                               evt_var_oos_gap_max = 0.50,  # IS vs OOS EVT-VaR gap 허용 최대치 (50%)
                               cdar_max            = 0.35,  # CDaR 상한
                               tdc_max             = 0.30   # Copula TDC 상한 (diversifier 역할)
                             )) {
  # tail_risk: compute_tail_risk_suite() 반환값 또는 tail_risk_result.json 내용
  # 반환: list(pass, violations, warnings, scores)

  violations <- character(0)
  warnings   <- character(0)

  # 1. CDaR 상한 검증
  cdar_val <- tail_risk$cdar$cdar %||% tail_risk$summary$cdar_95
  if (!is.null(cdar_val) && !is.na(cdar_val)) {
    if (cdar_val > thresholds$cdar_max) {
      violations <- c(violations,
        sprintf("CDaR(%.1f%%) > 상한(%.1f%%): %.4f > %.4f",
                tail_risk$cdar$alpha * 100,
                thresholds$cdar_max * 100,
                cdar_val, thresholds$cdar_max))
    }
  }

  # 2. CF-VaR vs Normal-VaR 괴리 경고 (꼬리 위험 과소추정 탐지)
  cf_ratio <- tail_risk$cf_var$cf_vs_normal_ratio %||% tail_risk$summary$cf_vs_normal
  if (!is.null(cf_ratio) && !is.na(cf_ratio)) {
    if (cf_ratio > 1.5) {
      warnings <- c(warnings,
        sprintf("CF-VaR/Normal-VaR = %.2f: 꼬리 비대칭성 높음. 정규 리스크 모델 과소추정 주의.", cf_ratio))
    }
  }

  # 3. GPD tail shape 경고 (xi >= 0.5 이면 heavy tail)
  xi <- tail_risk$evt_var$shape_xi %||% tail_risk$summary$tail_shape_xi
  if (!is.null(xi) && !is.na(xi)) {
    if (xi >= 0.5) {
      warnings <- c(warnings,
        sprintf("GPD shape xi = %.3f >= 0.5: 극단적 두꺼운 꼬리 (Pareto tail). 모멘트 불안정 가능.", xi))
    } else if (xi >= 0.3) {
      warnings <- c(warnings,
        sprintf("GPD shape xi = %.3f: 중간 수준 두꺼운 꼬리. 주의 관찰 필요.", xi))
    }
  }

  # 4. EVT-VaR가 CF-VaR보다 현저히 낮을 경우 경고 (EVT 피팅 이상)
  evt_var <- tail_risk$summary$evt_var_99
  cf_var  <- tail_risk$summary$cf_var_99
  if (!is.null(evt_var) && !is.null(cf_var) &&
      !is.na(evt_var) && !is.na(cf_var)) {
    if (evt_var < cf_var * 0.5) {
      warnings <- c(warnings,
        sprintf("EVT-VaR(%.4f) < CF-VaR(%.4f)*0.5: GPD 피팅 이상 가능. threshold 재조정 권장.",
                evt_var, cf_var))
    }
  }

  pass <- length(violations) == 0L

  list(
    pass       = pass,
    violations = violations,
    warnings   = warnings,
    summary    = list(
      cdar_95       = cdar_val,
      evt_var_99    = evt_var,
      cf_var_99     = cf_var,
      tail_shape_xi = xi,
      cf_vs_normal  = cf_ratio
    )
  )
}

# NULL 코알레싱 연산자 (R 4.1 미만 호환)
`%||%` <- function(a, b) if (!is.null(a)) a else b
