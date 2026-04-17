#==============================================================================
# Regime GARCH — DCC-GARCH 동적 상관 + Copula ES
# Pfaff (2016) Ch.8 GARCH, Ch.9 Copula
# Phase 2a — 2026-04-09
#
# 패키지: rugarch, rmgarch, copula, QRM
#
# 함수 목록:
#   fit_dcc_garch()           — DCC-GARCH 동적 상관 추정
#   forecast_conditional_es() — 조건부 ES(Expected Shortfall) 예측
#   compute_copula_es()       — GARCH-Copula ES (Ch.9 8단계 알고리즘)
#   compute_copula_tdc()      — Copula TDC(Tail Dependence Coefficient)
#   generate_stress_scenarios() — MC 기반 스트레스 시나리오 생성
#   test_regime_garch()       — C19+Q07 2팩터 DCC-GARCH 통합 테스트
#
# PIT 준수:
#   - DCC-GARCH는 expanding window (in-sample) 추정 후 1-step-ahead forecast
#   - 테스트 시 전체 샘플 통계량 사용 금지 — rolling_fit_dcc() 제공
#   - C9: t-1 lag 기반 시그널만 사용
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  # normalizePath() 금지 (WSL 한글 경로 버그) — sys.frame 방식 사용
  .script_dir <- tryCatch(
    dirname(sys.frame(1)$ofile),
    error = function(e) dirname(dirname(getwd()))
  )
  source(file.path(dirname(.script_dir), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

.check_garch_pkgs <- function() {
  required <- c("rugarch", "rmgarch", "copula")
  missing  <- required[!sapply(required, requireNamespace, quietly = TRUE)]
  if (length(missing) > 0) {
    stop(sprintf(
      "[regime_garch] 필수 패키지 미설치: %s\n  install.packages(c('%s'))",
      paste(missing, collapse = ", "),
      paste(missing, collapse = "', '")
    ))
  }
  invisible(TRUE)
}

cat("[regime_garch] DCC-GARCH + Copula ES module loaded (Phase 2a)\n")


#==============================================================================
# 1. fit_dcc_garch() — DCC-GARCH 동적 상관 추정
#    Pfaff (2016) Ch.8: 각 자산에 개별 GARCH(1,1)-t → DCC 결합
#==============================================================================

fit_dcc_garch <- function(ret_mat,
                          dist        = "std",
                          garch_order = c(1L, 1L),
                          verbose     = FALSE) {
  ## ret_mat: data.frame 또는 matrix, 각 열 = 팩터/슬리브 수익률
  ##          행은 날짜 순서대로 정렬되어 있어야 함
  ## dist   : 개별 GARCH 오차 분포 — "std"(Student-t) 또는 "norm"
  ## garch_order: c(p, q) — GARCH(p,q)
  ##
  ## 반환: list(
  ##   fit              = dccfit 객체,
  ##   time_varying_cor = array [T x K x K],
  ##   conditional_vol  = matrix [T x K],
  ##   diagnostics      = list(log_lik, AIC, BIC, convergence)
  ## )

  .check_garch_pkgs()
  library(rugarch, quietly = TRUE)
  library(rmgarch, quietly = TRUE)

  ret_mat <- as.matrix(ret_mat)
  n_assets <- ncol(ret_mat)
  n_obs    <- nrow(ret_mat)

  if (n_assets < 2L)
    stop("[fit_dcc_garch] 최소 2개 자산(열) 필요")
  if (n_obs < 60L)
    warning("[fit_dcc_garch] 관측치 ", n_obs, "개 — 60개 미만, 추정 불안정 가능")

  # --- Step 1: 개별 univariate GARCH spec 설정 (Pfaff Ch.8) ---
  uspec <- rugarch::ugarchspec(
    variance.model = list(
      model        = "sGARCH",
      garchOrder   = garch_order
    ),
    mean.model     = list(
      armaOrder    = c(0L, 0L),
      include.mean = TRUE
    ),
    distribution.model = dist  # "std" = Student-t
  )

  # 각 열에 동일 spec 복제 (multispec은 rugarch 패키지 소속)
  multi_spec <- rugarch::multispec(replicate(n_assets, uspec))

  # --- Step 2: DCC-GARCH spec (Engle 2002) ---
  dcc_spec <- rmgarch::dccspec(
    uspec          = multi_spec,
    dccOrder       = c(1L, 1L),
    distribution   = "mvt"   # 다변량 Student-t
  )

  # --- Step 3: DCC fit ---
  fit <- tryCatch(
    rmgarch::dccfit(dcc_spec, data = ret_mat, fit.control = list(eval.se = FALSE)),
    error = function(e) {
      stop(sprintf("[fit_dcc_garch] DCC 추정 실패: %s", conditionMessage(e)))
    }
  )

  # --- Step 4: 동적 상관 + 조건부 변동성 추출 ---
  # rcor(): [K x K x T] 배열 — 시간에 따른 상관계수 행렬
  tv_cor   <- rmgarch::rcor(fit)          # array [K, K, T]
  cond_vol <- sigma(fit)                  # matrix [T, K] — stats::sigma dispatch

  # --- Step 5: 진단 통계 ---
  lik <- tryCatch(rugarch::likelihood(fit), error = function(e) NA_real_)
  # infocriteria는 rmgarch에 없음 — 직접 계산
  n_params <- tryCatch(length(rugarch::coef(fit)), error = function(e) NA_integer_)
  n_obs_ic <- nrow(ret_mat)
  aic_val  <- if (!is.na(lik) && !is.na(n_params)) -2 * lik + 2 * n_params else NA_real_
  bic_val  <- if (!is.na(lik) && !is.na(n_params)) -2 * lik + log(n_obs_ic) * n_params else NA_real_

  diag_out <- list(
    log_lik    = lik,
    AIC        = aic_val,
    BIC        = bic_val,
    convergence = fit@mfit$convergence  # 0 = 수렴
  )

  if (verbose) {
    cat(sprintf("[fit_dcc_garch] K=%d, T=%d | LogL=%.2f | AIC=%.4f | Conv=%d\n",
                n_assets, n_obs,
                diag_out$log_lik, diag_out$AIC, diag_out$convergence))
  }

  list(
    fit              = fit,
    time_varying_cor = tv_cor,
    conditional_vol  = cond_vol,
    diagnostics      = diag_out
  )
}


#==============================================================================
# 2. forecast_conditional_es() — 조건부 ES 예측
#    Pfaff (2016) Ch.8: Student-t ES 공식
#    ES(α) = σ * [dt(qt(α,ν), ν) / (1-α)] * [(ν + qt(α,ν)^2) / (ν-1)]
#==============================================================================

forecast_conditional_es <- function(dcc_fit,
                                    weights  = NULL,
                                    p        = 0.975,
                                    horizon  = 1L) {
  ## dcc_fit : fit_dcc_garch() 반환 리스트 또는 dccfit 객체
  ## weights : 포트폴리오 가중치 벡터 (NULL이면 동일가중)
  ## p       : ES 신뢰수준 (예: 0.975 = 2.5% tail)
  ## horizon : 예측 기간 (현재 1만 완전 지원)
  ##
  ## 반환: list(
  ##   conditional_es_per_factor = 각 팩터 1-step-ahead ES 벡터,
  ##   portfolio_es              = 포트폴리오 ES 스칼라,
  ##   conditional_vol_forecast  = 1-step-ahead 조건부 변동성,
  ##   df_estimates              = 자유도 추정치 벡터
  ## )

  .check_garch_pkgs()
  library(rugarch, quietly = TRUE)
  library(rmgarch, quietly = TRUE)

  fit_obj <- if (inherits(dcc_fit, "DCCfit")) dcc_fit else dcc_fit$fit

  # --- Step 1: 1-step-ahead 예측 ---
  fc <- tryCatch(
    rmgarch::dccforecast(fit_obj, n.ahead = horizon),
    error = function(e) stop(sprintf("[forecast_conditional_es] 예측 실패: %s", conditionMessage(e)))
  )

  # 조건부 변동성 추출: [K x 1] (horizon=1)
  # sigma() dispatch는 stats에서 처리
  cond_vol_fc <- as.numeric(sigma(fc)[, , 1L])
  n_assets    <- length(cond_vol_fc)

  # --- Step 2: 자유도 추정치 추출 ---
  # rugarch 객체에서 각 univariate fit의 shape 파라미터(df) 추출
  # DCCfit 슬롯: @mfit (ufit 없음) — coef()로 직접 shape 추출
  df_vec <- sapply(seq_len(n_assets), function(i) {
    # rugarch::coef(fit_obj, i)로 i번째 자산 파라미터 추출
    cf <- tryCatch(rugarch::coef(fit_obj)[i, ], error = function(e) NULL)
    if (is.null(cf)) {
      # 전체 coef 시도
      cf_all <- tryCatch(rugarch::coef(fit_obj), error = function(e) NULL)
      if (!is.null(cf_all) && is.matrix(cf_all)) cf <- cf_all[i, ]
    }
    if (!is.null(cf) && "shape" %in% names(cf)) {
      max(cf["shape"], 2.5)
    } else {
      5.0  # fallback: Student-t df=5
    }
  })

  # --- Step 3: Student-t ES 계산 (Pfaff Ch.8 공식) ---
  # ES(p) = σ * f(q_p, ν) / (1-p) * (ν + q_p^2) / (ν-1)
  # f(q,ν) = dt(q,ν), q_p = qt(p, ν)
  es_per_factor <- mapply(function(sigma_i, nu_i) {
    q_p   <- qt(p, df = nu_i)
    f_q   <- dt(q_p, df = nu_i)
    sigma_i * (f_q / (1 - p)) * ((nu_i + q_p^2) / (nu_i - 1))
  }, cond_vol_fc, df_vec)

  # sigma(fit_obj)는 xts [T x K] — colnames로 팩터명 추출
  factor_names <- tryCatch(colnames(sigma(fit_obj)), error = function(e) paste0("F", seq_len(n_assets)))
  names(es_per_factor) <- factor_names

  # --- Step 4: 포트폴리오 ES (가중 평균 근사 — 선형 근사) ---
  if (is.null(weights)) {
    weights <- rep(1.0 / n_assets, n_assets)
  }
  weights <- weights / sum(weights)
  portfolio_es <- as.numeric(weights %*% es_per_factor)

  list(
    conditional_es_per_factor = es_per_factor,
    portfolio_es              = portfolio_es,
    conditional_vol_forecast  = cond_vol_fc,
    df_estimates              = df_vec
  )
}


#==============================================================================
# 3. compute_copula_es() — GARCH-Copula ES (Pfaff Ch.9 8단계 알고리즘)
#==============================================================================

compute_copula_es <- function(ret_mat,
                              weights = NULL,
                              p       = 0.975,
                              family  = "t",
                              n_sim   = 100000L) {
  ## ret_mat : data.frame/matrix [T x K]
  ## weights : 포트폴리오 가중치 (NULL = EW)
  ## p       : ES 신뢰수준
  ## family  : copula 종류 — "t" (t-copula), "gumbel", "clayton", "frank"
  ## n_sim   : MC 시뮬레이션 횟수
  ##
  ## 반환: list(
  ##   portfolio_es       = ES 스칼라,
  ##   portfolio_var      = VaR 스칼라,
  ##   simulated_losses   = MC 손실 벡터 (n_sim),
  ##   copula_fit         = 피팅된 copula 객체,
  ##   garch_fits         = 각 팩터 ugarchfit 리스트
  ## )

  .check_garch_pkgs()
  library(rugarch, quietly = TRUE)
  library(copula,  quietly = TRUE)

  ret_mat  <- as.matrix(ret_mat)
  n_assets <- ncol(ret_mat)
  n_obs    <- nrow(ret_mat)

  if (is.null(weights)) weights <- rep(1.0 / n_assets, n_assets)
  weights <- weights / sum(weights)

  # --- Step 1: 각 팩터 GARCH(1,1)-t fit (Pfaff Ch.9) ---
  uspec <- rugarch::ugarchspec(
    variance.model     = list(model = "sGARCH", garchOrder = c(1L, 1L)),
    mean.model         = list(armaOrder = c(0L, 0L), include.mean = TRUE),
    distribution.model = "std"
  )

  garch_fits <- lapply(seq_len(n_assets), function(i) {
    tryCatch(
      rugarch::ugarchfit(uspec, data = ret_mat[, i], solver = "hybrid"),
      error = function(e) {
        warning(sprintf("[compute_copula_es] 자산 %d GARCH fit 실패: %s", i, conditionMessage(e)))
        NULL
      }
    )
  })

  # --- Step 2: 표준화 잔차 추출 ---
  # z_i = (r_i - mu_i) / sigma_i
  std_resid <- do.call(cbind, lapply(garch_fits, function(gf) {
    if (is.null(gf)) return(rep(NA_real_, n_obs))
    as.numeric(rugarch::residuals(gf, standardize = TRUE))
  }))

  # --- Step 3: 의사균일(pseudo-uniform) 변환 — pt(z, df) ---
  # PIT: 표준화 잔차 → [0,1] 균일 변환
  df_vec <- sapply(garch_fits, function(gf) {
    if (is.null(gf)) return(5.0)
    cf <- tryCatch(rugarch::coef(gf), error = function(e) NULL)
    if (!is.null(cf) && "shape" %in% names(cf)) max(cf["shape"], 2.5) else 5.0
  })

  unif_resid <- do.call(cbind, lapply(seq_len(n_assets), function(i) {
    pt(std_resid[, i], df = df_vec[i])
  }))

  # NA 행 제거
  valid_rows <- complete.cases(unif_resid)
  if (sum(valid_rows) < 50L)
    stop("[compute_copula_es] 유효 관측치 부족 (< 50)")
  unif_resid <- unif_resid[valid_rows, , drop = FALSE]

  # --- Step 4: Copula 피팅 ---
  cop_obj <- switch(family,
    "t"       = copula::tCopula(dim = n_assets, dispstr = "un"),
    "gumbel"  = copula::gumbelCopula(dim = n_assets),
    "clayton" = copula::claytonCopula(dim = n_assets),
    "frank"   = copula::frankCopula(dim = n_assets),
    stop(sprintf("[compute_copula_es] 미지원 copula family: %s", family))
  )

  cop_fit <- tryCatch(
    copula::fitCopula(cop_obj, data = unif_resid, method = "mpl"),
    error = function(e) {
      warning(sprintf("[compute_copula_es] Copula 피팅 실패: %s", conditionMessage(e)))
      NULL
    }
  )

  # --- Step 5-6: MC 시뮬레이션 → 균일 → 역변환 ---
  if (!is.null(cop_fit)) {
    sim_unif <- tryCatch(
      copula::rCopula(n_sim, cop_fit@copula),
      error = function(e) {
        warning("[compute_copula_es] MC 시뮬레이션 실패, 독립 fallback")
        matrix(runif(n_sim * n_assets), nrow = n_sim, ncol = n_assets)
      }
    )
  } else {
    sim_unif <- matrix(runif(n_sim * n_assets), nrow = n_sim, ncol = n_assets)
  }

  # 역변환: 균일 → t-분포 잔차 → 수익률 공간
  # 마지막 GARCH 조건부 vol/mu 사용 (1-step-ahead 근사)
  sim_ret <- do.call(cbind, lapply(seq_len(n_assets), function(i) {
    gf     <- garch_fits[[i]]
    nu_i   <- df_vec[i]
    # 역t 변환 (Step 6)
    z_sim  <- qt(sim_unif[, i], df = nu_i)
    # 마지막 조건부 sigma + mu
    if (!is.null(gf)) {
      last_sigma <- tail(as.numeric(rugarch::sigma(gf)), 1L)
      last_mu    <- tail(as.numeric(fitted(gf)), 1L)
    } else {
      last_sigma <- sd(ret_mat[, i], na.rm = TRUE)
      last_mu    <- mean(ret_mat[, i], na.rm = TRUE)
    }
    last_mu + last_sigma * z_sim
  }))

  # --- Step 7: 포트폴리오 손실 분포 ---
  # 손실 = -수익률 × 가중치
  port_ret    <- as.numeric(sim_ret %*% weights)
  sim_losses  <- -port_ret  # 손실 = 음의 수익률

  # --- Step 8: ES 계산 ---
  threshold <- quantile(sim_losses, probs = p, na.rm = TRUE)
  tail_loss <- sim_losses[sim_losses > threshold]
  es_val    <- if (length(tail_loss) > 0L) mean(tail_loss) else threshold

  list(
    portfolio_es     = es_val,
    portfolio_var    = threshold,
    simulated_losses = sim_losses,
    copula_fit       = cop_fit,
    garch_fits       = garch_fits
  )
}


#==============================================================================
# 4. compute_copula_tdc() — Tail Dependence Coefficient
#    Pfaff (2016) Ch.9 + Ch.11: 꼬리 의존성 계수
#==============================================================================

compute_copula_tdc <- function(ret_a,
                               ret_b,
                               method = "clayton") {
  ## ret_a, ret_b : 수익률 벡터 (같은 길이)
  ## method       : "clayton" (하방), "gumbel" (상방), "empirical"
  ##
  ## 반환: list(
  ##   tdc_lower    = 하방 꼬리 의존성,
  ##   tdc_upper    = 상방 꼬리 의존성,
  ##   kendall_tau  = Kendall tau 상관계수,
  ##   theta        = copula 파라미터
  ## )

  .check_garch_pkgs()
  library(copula, quietly = TRUE)

  n <- length(ret_a)
  if (n != length(ret_b)) stop("[compute_copula_tdc] 길이 불일치")
  valid <- complete.cases(ret_a, ret_b)
  ra    <- ret_a[valid]
  rb    <- ret_b[valid]

  # Kendall's tau
  tau <- cor(ra, rb, method = "kendall")

  # 모수적 TDC (method 기반)
  tdc_lower <- NA_real_
  tdc_upper <- NA_real_
  theta     <- NA_real_

  if (method == "clayton") {
    # Clayton copula: 하방 꼬리 의존성만 존재
    # theta = 2*tau / (1 - tau)  (Pfaff Ch.9)
    theta     <- max(2 * tau / (1 - tau), 1e-6)
    tdc_lower <- 2^(-1 / theta)  # lambda_L
    tdc_upper <- 0.0             # Clayton은 상방 의존성 없음

  } else if (method == "gumbel") {
    # Gumbel copula: 상방 꼬리 의존성만 존재
    # theta = 1 / (1 - tau)
    theta     <- max(1 / (1 - tau), 1.0 + 1e-6)
    tdc_upper <- 2 - 2^(1 / theta)  # lambda_U
    tdc_lower <- 0.0

  } else if (method == "empirical") {
    # 비모수 TDC 추정 (Coles et al. 1999 방법)
    # 경험적 분포함수 기반 꼬리 추정
    ecdf_a  <- rank(ra) / (n + 1)
    ecdf_b  <- rank(rb) / (n + 1)
    q_level <- 0.1  # 하위 10% 기준

    tdc_lower <- mean(ecdf_a <= q_level & ecdf_b <= q_level) / q_level
    tdc_upper <- mean(ecdf_a >= (1 - q_level) & ecdf_b >= (1 - q_level)) / q_level
    theta     <- tau  # 비모수는 tau를 대리 사용

  } else {
    stop(sprintf("[compute_copula_tdc] 미지원 method: %s", method))
  }

  list(
    tdc_lower   = tdc_lower,
    tdc_upper   = tdc_upper,
    kendall_tau = tau,
    theta       = theta
  )
}


#==============================================================================
# 5. generate_stress_scenarios() — MC 기반 스트레스 시나리오
#    Copula에서 n_sim 샘플 생성, 하위 5% = 스트레스
#==============================================================================

generate_stress_scenarios <- function(ret_mat,
                                      n_sim   = 10000L,
                                      family  = "t",
                                      weights = NULL,
                                      stress_pct = 0.05) {
  ## ret_mat    : [T x K] 수익률 행렬
  ## n_sim      : MC 시뮬레이션 횟수
  ## family     : copula 종류
  ## stress_pct : 스트레스 시나리오 정의 (하위 %)
  ##
  ## 반환: list(
  ##   scenarios        = [n_sim x K] 전체 MC 시나리오,
  ##   stress_scenarios = 스트레스 시나리오만 (portfolio loss 기준 상위),
  ##   stress_es        = 스트레스 ES 스칼라,
  ##   stress_threshold = 스트레스 포트폴리오 손실 임계값
  ## )

  .check_garch_pkgs()
  library(copula, quietly = TRUE)
  library(rugarch, quietly = TRUE)

  ret_mat  <- as.matrix(ret_mat)
  n_assets <- ncol(ret_mat)
  if (is.null(weights)) weights <- rep(1.0 / n_assets, n_assets)
  weights <- weights / sum(weights)

  # GARCH fit (간략 버전 — 조건부 분포 추정용)
  uspec <- rugarch::ugarchspec(
    variance.model     = list(model = "sGARCH", garchOrder = c(1L, 1L)),
    mean.model         = list(armaOrder = c(0L, 0L), include.mean = TRUE),
    distribution.model = "std"
  )

  garch_fits <- lapply(seq_len(n_assets), function(i) {
    tryCatch(
      rugarch::ugarchfit(uspec, data = ret_mat[, i], solver = "hybrid"),
      error = function(e) NULL
    )
  })

  # 의사균일 변환
  df_vec <- sapply(garch_fits, function(gf) {
    if (is.null(gf)) return(5.0)
    cf <- tryCatch(rugarch::coef(gf), error = function(e) NULL)
    if (!is.null(cf) && "shape" %in% names(cf)) max(cf["shape"], 2.5) else 5.0
  })

  std_resid <- do.call(cbind, lapply(seq_along(garch_fits), function(i) {
    gf <- garch_fits[[i]]
    if (is.null(gf)) return(scale(ret_mat[, i]))
    as.numeric(rugarch::residuals(gf, standardize = TRUE))
  }))

  unif_mat <- do.call(cbind, lapply(seq_len(n_assets), function(i) {
    pt(std_resid[, i], df = df_vec[i])
  }))
  unif_mat <- unif_mat[complete.cases(unif_mat), , drop = FALSE]

  # Copula 피팅
  cop_obj <- switch(family,
    "t"       = copula::tCopula(dim = n_assets, dispstr = "un"),
    "gumbel"  = copula::gumbelCopula(dim = n_assets),
    "clayton" = copula::claytonCopula(dim = n_assets),
    stop(sprintf("[generate_stress_scenarios] 미지원 family: %s", family))
  )

  cop_fit <- tryCatch(
    copula::fitCopula(cop_obj, data = unif_mat, method = "mpl"),
    error = function(e) { warning("[generate_stress_scenarios] Copula 피팅 실패"); NULL }
  )

  # MC 샘플
  sim_unif <- if (!is.null(cop_fit)) {
    copula::rCopula(n_sim, cop_fit@copula)
  } else {
    matrix(runif(n_sim * n_assets), nrow = n_sim, ncol = n_assets)
  }

  # 역변환
  sim_ret <- do.call(cbind, lapply(seq_len(n_assets), function(i) {
    gf        <- garch_fits[[i]]
    nu_i      <- df_vec[i]
    z_sim     <- qt(sim_unif[, i], df = nu_i)
    last_sigma <- if (!is.null(gf)) tail(as.numeric(rugarch::sigma(gf)), 1L) else sd(ret_mat[, i], na.rm = TRUE)
    last_mu    <- if (!is.null(gf)) tail(as.numeric(fitted(gf)), 1L) else mean(ret_mat[, i], na.rm = TRUE)
    last_mu + last_sigma * z_sim
  }))

  # 포트폴리오 손실
  port_losses <- -(sim_ret %*% weights)

  # 스트레스 시나리오 = 상위 stress_pct 손실
  stress_threshold  <- quantile(port_losses, probs = 1 - stress_pct, na.rm = TRUE)
  stress_idx        <- which(port_losses >= stress_threshold)
  stress_scenarios  <- sim_ret[stress_idx, , drop = FALSE]
  stress_es         <- mean(port_losses[stress_idx])

  cat(sprintf("[generate_stress_scenarios] 총 %d 시나리오 중 %d개 스트레스 (%.0f%% tail)\n",
              n_sim, length(stress_idx), stress_pct * 100))
  cat(sprintf("  스트레스 ES = %.4f | 임계값 = %.4f\n", stress_es, stress_threshold))

  list(
    scenarios         = sim_ret,
    stress_scenarios  = stress_scenarios,
    stress_es         = stress_es,
    stress_threshold  = as.numeric(stress_threshold)
  )
}


#==============================================================================
# 6. rolling_fit_dcc() — PIT 준수 롤링 DCC-GARCH
#    C1 준수: expanding window만 허용, full-sample 통계 금지
#==============================================================================

rolling_fit_dcc <- function(ret_mat,
                             min_window = 120L,
                             step       = 21L,
                             dist       = "std") {
  ## PIT 준수 rolling/expanding DCC-GARCH
  ## min_window : 최소 학습 기간 (거래일 기준, 약 6개월)
  ## step       : 몇 행마다 재추정할지 (21 = 매월)
  ## 반환: data.table [Date x 동적상관 벡터]

  ret_mat <- as.matrix(ret_mat)
  n_obs   <- nrow(ret_mat)
  n_assets <- ncol(ret_mat)
  dates   <- if (!is.null(rownames(ret_mat))) as.Date(rownames(ret_mat)) else seq_len(n_obs)

  refit_indices <- seq(min_window, n_obs, by = step)

  results <- lapply(refit_indices, function(end_idx) {
    # expanding window: 1:end_idx만 사용 (미래참조 없음)
    sub_ret <- ret_mat[1L:end_idx, , drop = FALSE]
    fit_res <- tryCatch(
      fit_dcc_garch(sub_ret, dist = dist, verbose = FALSE),
      error = function(e) NULL
    )
    if (is.null(fit_res)) return(NULL)

    # 마지막 시점 상관행렬 추출
    last_cor <- fit_res$time_varying_cor[, , dim(fit_res$time_varying_cor)[3L]]
    # 상삼각 요소만 벡터화
    cor_pairs <- last_cor[upper.tri(last_cor)]
    pair_names <- outer(seq_len(n_assets), seq_len(n_assets),
                        FUN = function(i, j) paste0("cor_", i, "_", j))[upper.tri(matrix(0, n_assets, n_assets))]
    data.table::data.table(
      Date        = dates[end_idx],
      t(setNames(cor_pairs, pair_names)),
      window_size = end_idx
    )
  })

  data.table::rbindlist(results[!sapply(results, is.null)], fill = TRUE)
}


#==============================================================================
# 7. test_regime_garch() — C19 + Q07 2팩터 DCC-GARCH 통합 테스트
#    kr_factor_returns.parquet 또는 직접 제공 수익률 사용
#==============================================================================

test_regime_garch <- function(ret_mat  = NULL,
                              use_cache = TRUE) {
  ## 테스트용 함수
  ## ret_mat  : NULL이면 .cache/kr_factor_returns.parquet에서 MKT + SMB 사용
  ## 위기 시 상관 급등 여부 확인

  library(data.table, quietly = TRUE)
  library(arrow, quietly = TRUE)

  cat("\n=== regime_garch 통합 테스트 (Phase 2a) ===\n")

  if (is.null(ret_mat)) {
    # Factor 수익률 proxy: MKT + SMB (C19 ~ MKT momentum, Q07 ~ SMB quality)
    fp <- file.path(CACHE_DIR, "kr_factor_returns.parquet")
    if (!file.exists(fp)) stop("[test_regime_garch] kr_factor_returns.parquet 없음")

    dt <- as.data.table(arrow::read_parquet(fp))
    dt[, Date := as.Date(Date)]
    dt <- dt[!is.na(MKT) & !is.na(SMB)]
    cat(sprintf("  데이터: %d 관측치 (%s ~ %s)\n",
                nrow(dt),
                format(min(dt$Date), "%Y-%m"),
                format(max(dt$Date), "%Y-%m")))

    ret_mat <- as.matrix(dt[, .(MKT, SMB)])
    rownames(ret_mat) <- as.character(dt$Date)
  }

  # --- DCC-GARCH fit ---
  cat("  1. DCC-GARCH 추정 중...\n")
  dcc_res <- fit_dcc_garch(ret_mat, dist = "std", verbose = TRUE)

  # --- 동적 상관: 위기 vs 평온 ---
  tv_cor      <- dcc_res$time_varying_cor
  time_dim    <- dim(tv_cor)[3L]
  cor_series  <- sapply(seq_len(time_dim), function(t) tv_cor[1L, 2L, t])

  dates_all <- if (!is.null(rownames(ret_mat))) as.Date(rownames(ret_mat)) else seq_len(nrow(ret_mat))
  # 위기 구간 정의: 2008H2, 2020Q1 (reference_stress_periods.md 기준)
  crisis_mask <- (dates_all >= as.Date("2008-07-01") & dates_all <= as.Date("2009-06-30")) |
                 (dates_all >= as.Date("2020-01-01") & dates_all <= as.Date("2020-06-30"))

  if (sum(crisis_mask) > 0 && sum(!crisis_mask) > 0) {
    cor_crisis  <- mean(cor_series[crisis_mask], na.rm = TRUE)
    cor_normal  <- mean(cor_series[!crisis_mask], na.rm = TRUE)
    cat(sprintf("  동적 상관 — 평온기: %.3f | 위기기: %.3f | 급등: %s\n",
                cor_normal, cor_crisis,
                ifelse(cor_crisis > cor_normal + 0.05, "YES (예상 일치)", "No")))
  }

  # --- ES 예측 ---
  cat("  2. 조건부 ES 예측 중...\n")
  es_res <- tryCatch(
    forecast_conditional_es(dcc_res, p = 0.975),
    error = function(e) { cat("    ES 예측 실패:", conditionMessage(e), "\n"); NULL }
  )
  if (!is.null(es_res)) {
    cat(sprintf("  ES(97.5%%) — 팩터별: %s | 포트폴리오: %.4f\n",
                paste(round(es_res$conditional_es_per_factor, 4), collapse = ", "),
                es_res$portfolio_es))
  }

  # --- Copula TDC ---
  cat("  3. Copula TDC 계산 중...\n")
  tdc_res <- compute_copula_tdc(ret_mat[, 1L], ret_mat[, 2L], method = "clayton")
  cat(sprintf("  TDC (Clayton) — tau=%.3f | theta=%.3f | lambda_L=%.3f\n",
              tdc_res$kendall_tau, tdc_res$theta, tdc_res$tdc_lower))

  cat("\n=== 테스트 완료 ===\n")
  invisible(list(dcc = dcc_res, es = es_res, tdc = tdc_res))
}
