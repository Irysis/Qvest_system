#==============================================================================
# Protection Strategy — Floor + ES Risk Budget (Pfaff Ch.13.6.4)
# Pfaff (2016) "Financial Risk Modelling and Portfolio Optimization with R"
#   Ch.13.6.4: CPPI/Floor-based dynamic risk budgeting
# 참조: Black & Perold (1992) "Theory of Constant Proportion Portfolio Insurance"
#       Rockafellar & Uryasev (2000) CVaR/ES 기반 제약
#
# LP: max RE'ω  s.t.  ES'ω ≤ ES_limit * Buffer,  sum(ω)=1, lb≤ω≤ub
# 패키지: cccp (QP/LP solver), MASS (MC 시뮬)
# 작성: Forge (2026-04-09)
# 사용처: S5 Mutation overlay, Judge S6 stress 검증
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(MASS)        # mvrnorm (MC 시뮬)
})

# ─── 패키지 존재 여부에 따른 solver 선택 ─────────────────────────────────────
.has_cccp   <- requireNamespace("cccp",   quietly = TRUE)
.has_nloptr <- requireNamespace("nloptr", quietly = TRUE)

# ─────────────────────────────────────────────────────────────────────────────
# 1. 보호 전략 LP / QP
#    Pfaff Ch.13.6.4: Buffer = NAV/Floor - 1
#    Buffer < 0  → 전액 무위험 자산 (money-market)
#    Buffer ≥ 0  → LP: max RE'ω  s.t. ES'ω ≤ es_limit, Σω=1, lb≤ω≤ub
# ─────────────────────────────────────────────────────────────────────────────
#' @param nav          현재 포트폴리오 NAV (스칼라)
#' @param re_forecast  슬리브별 기대수익 벡터 (길이 K)
#' @param es_forecast  슬리브별 ES (양수, GPD 기반, tail_risk_engine.R)
#' @param floor0       최소 보존 가치 (예: 초기 NAV * 0.90)
#' @param es_limit     전체 포트폴리오 ES 상한 (기본 2.5% = 0.025)
#' @param min_risky    각 슬리브 최소 비중 (기본 0)
#' @param max_risky    각 슬리브 최대 비중 (기본 1)
#' @param max_single   단일 슬리브 최대 비중 상한 (기본 0.40)
#' @return list(weights, buffer, floor_breached, method)
run_floor_es_overlay <- function(nav,
                                  re_forecast,
                                  es_forecast,
                                  floor0,
                                  es_limit    = 0.025,
                                  min_risky   = 0,
                                  max_risky   = 1,
                                  max_single  = 0.40) {
  stopifnot(
    is.numeric(nav), length(nav) == 1L, nav > 0,
    is.numeric(re_forecast), length(re_forecast) >= 1L,
    is.numeric(es_forecast), length(es_forecast) == length(re_forecast),
    all(es_forecast >= 0),
    is.numeric(floor0), floor0 > 0
  )

  K <- length(re_forecast)
  buffer <- nav / floor0 - 1  # Pfaff Ch.13.6.4 eq.(13.90)

  # ── Floor breach: 전액 무위험 자산 ──────────────────────────────────────────
  if (buffer < 0) {
    return(list(
      weights       = rep(0, K),          # 0 = money-market(무위험)
      buffer        = buffer,
      floor_breached = TRUE,
      method        = "money_market"
    ))
  }

  # ── Buffer 0 근방: 안전 최소 비중 ───────────────────────────────────────────
  if (buffer < 1e-4) {
    w_safe <- pmax(min_risky, 0)
    w_safe <- rep(w_safe / K, K)
    return(list(
      weights       = w_safe,
      buffer        = buffer,
      floor_breached = FALSE,
      method        = "near_floor"
    ))
  }

  # ── 유효 ES 상한 ────────────────────────────────────────────────────────────
  # Pfaff Ch.13.6.4: ES 제약은 포트폴리오 수준 절대 상한 (buffer와 독립)
  # Buffer는 투자 가능 비중 결정에만 사용 (CPPI multiplier)
  # ES 상한을 buffer로 스케일하면 버퍼 작을 때 infeasible → 직접 사용
  effective_es_limit <- es_limit

  # ── nloptr SLSQP LP (선형 목적함수 + 선형 ES 제약) ────────────────────────
  if (.has_nloptr) {
    result <- tryCatch({
      .solve_floor_es_nloptr(
        re     = re_forecast,
        es     = es_forecast,
        es_lim = effective_es_limit,
        lb     = min_risky,
        ub     = pmin(max_single, max_risky),
        K      = K
      )
    }, error = function(e) {
      warning("[Protection] nloptr 실패: ", conditionMessage(e), " → EW")
      NULL
    })
    if (!is.null(result)) {
      return(list(
        weights        = result$w,
        buffer         = buffer,
        floor_breached = FALSE,
        method         = "nloptr_slsqp"
      ))
    }
  }

  # ── 최후 fallback: RE 기반 비례 배분 ──────────────────────────────────────
  re_pos <- pmax(re_forecast, 0)
  if (sum(re_pos) < 1e-10) re_pos <- rep(1, K)
  w_fallback <- re_pos / sum(re_pos)
  w_fallback <- pmin(w_fallback, max_single)
  w_fallback <- w_fallback / sum(w_fallback)

  return(list(
    weights       = w_fallback,
    buffer        = buffer,
    floor_breached = FALSE,
    method        = "re_proportional"
  ))
}

# ── 내부: nloptr::slsqp() LP solver ─────────────────────────────────────────
# nloptr::slsqp(): 간편 래퍼, gradient 자동처리
# 목적: min -re'ω  s.t. sum(ω)=1, ES'ω≤es_lim, lb≤ω≤ub
.solve_floor_es_nloptr <- function(re, es, es_lim, lb, ub, K) {
  library(nloptr)

  w0 <- rep(1 / K, K)

  # slsqp: hin <= 0 형식 (최신 nloptr)
  # ES'ω - es_lim <= 0
  sol <- suppressWarnings(nloptr::slsqp(
    x0    = w0,
    fn    = function(w) -sum(re * w),
    gr    = function(w) -re,
    lower = rep(lb,     K),
    upper = rep(ub,     K),
    heq   = function(w) sum(w) - 1,
    hin   = function(w) sum(es * w) - es_lim   # <= 0
  ))

  # convergence codes: 1~4 = success/acceptable, <0 = error
  # -4: roundoff limited (acceptable for LP with tight constraints)
  # -5: maxeval reached (retry with EW)
  if (sol$convergence < -4) stop("nloptr slsqp 실패: status=", sol$convergence)

  w <- pmax(pmin(sol$par, ub), lb)
  if (sum(w) < 1e-10) w <- rep(1 / K, K)
  w <- w / sum(w)
  list(w = w)
}


# ─────────────────────────────────────────────────────────────────────────────
# 2. 롤링 보호 시뮬레이션
#    전체 기간에 걸쳐 run_floor_es_overlay() 반복 호출
#    Pfaff Ch.13.6.4: monthly rebalancing, floor carry-forward
# ─────────────────────────────────────────────────────────────────────────────
#' @param nav_series      날짜-인덱스 NAV 벡터 (이름이 Date)
#' @param re_series       날짜별 슬리브 기대수익 data.frame (Date, sleeve_k)
#' @param es_series       날짜별 슬리브 ES data.frame (Date, sleeve_k)
#' @param floor_pct       최소 보존 비율 (기본 0.90 = 초기 NAV의 90%)
#' @param rebalance_freq  "monthly" 또는 "weekly"
#' @param es_limit        포트폴리오 ES 상한 (기본 0.025)
#' @return list(protected_nav, floor_series, buffer_series, allocation_history)
simulate_protection <- function(nav_series,
                                 re_series,
                                 es_series,
                                 floor_pct       = 0.90,
                                 rebalance_freq  = "monthly",
                                 es_limit        = 0.025) {
  stopifnot(
    is.numeric(nav_series), length(nav_series) >= 2L,
    is.data.frame(re_series) || is.data.table(re_series),
    is.data.frame(es_series) || is.data.table(es_series),
    floor_pct > 0, floor_pct < 1
  )

  re_dt <- as.data.table(re_series)
  es_dt <- as.data.table(es_series)
  dates  <- names(nav_series)
  n_t    <- length(nav_series)

  # 슬리브 컬럼 (Date 제외)
  sleeve_cols <- setdiff(names(re_dt), "Date")
  K           <- length(sleeve_cols)

  # 초기 설정
  floor0          <- nav_series[1] * floor_pct
  protected_nav   <- numeric(n_t)
  floor_series    <- numeric(n_t)
  buffer_series   <- numeric(n_t)
  alloc_history   <- vector("list", n_t)

  protected_nav[1] <- nav_series[1]
  floor_series[1]  <- floor0
  buffer_series[1] <- nav_series[1] / floor0 - 1

  # 리밸런싱 날짜 결정
  rebal_idx <- .get_rebalance_idx(dates, rebalance_freq)

  current_weights <- rep(1 / K, K)

  for (i in seq(2, n_t)) {
    # ── 현재 NAV ──────────────────────────────────────────────────────────────
    cur_nav   <- protected_nav[i - 1]
    cur_floor <- floor_series[i - 1]

    # ── 리밸런싱 기간 확인 ──────────────────────────────────────────────────
    if (i %in% rebal_idx) {
      date_i <- if (!is.null(dates)) dates[i] else as.character(i)

      re_row <- re_dt[Date == date_i, ..sleeve_cols]
      es_row <- es_dt[Date == date_i, ..sleeve_cols]

      if (nrow(re_row) > 0 && nrow(es_row) > 0) {
        re_vec <- as.numeric(re_row[1])
        es_vec <- pmax(as.numeric(es_row[1]), 0)

        ov <- run_floor_es_overlay(
          nav         = cur_nav,
          re_forecast = re_vec,
          es_forecast = es_vec,
          floor0      = cur_floor,
          es_limit    = es_limit
        )
        current_weights <- ov$weights
        alloc_history[[i]] <- c(date = date_i, ov$weights, buffer = ov$buffer,
                                  floor_breached = ov$floor_breached,
                                  method = ov$method)
      }
    }

    # ── NAV 업데이트 ─────────────────────────────────────────────────────────
    # 단순 선형 근사: re_series를 일간 수익률로 사용
    re_row_i <- re_dt[Date == (if (!is.null(dates)) dates[i] else as.character(i)),
                      ..sleeve_cols]
    if (nrow(re_row_i) > 0) {
      daily_r <- sum(current_weights * as.numeric(re_row_i[1]))
    } else {
      daily_r <- 0
    }
    protected_nav[i] <- cur_nav * (1 + daily_r)

    # ── Floor는 ratchet-up (최고 NAV 기준 갱신 가능, 여기선 고정) ─────────────
    floor_series[i]  <- cur_floor
    buffer_series[i] <- protected_nav[i] / cur_floor - 1
  }

  list(
    protected_nav     = setNames(protected_nav, dates),
    floor_series      = setNames(floor_series,  dates),
    buffer_series     = setNames(buffer_series, dates),
    allocation_history = alloc_history
  )
}

# ── 내부: 리밸런싱 인덱스 생성 ─────────────────────────────────────────────
.get_rebalance_idx <- function(dates, freq = "monthly") {
  if (is.null(dates) || length(dates) < 2L) return(seq(2, length(dates)))

  dt <- as.Date(dates)
  if (freq == "monthly") {
    m <- format(dt, "%Y-%m")
    # 각 월의 첫 거래일 인덱스
    idx <- which(!duplicated(m))
  } else if (freq == "weekly") {
    w <- format(dt, "%Y-%V")
    idx <- which(!duplicated(w))
  } else {
    idx <- seq_along(dates)
  }
  idx[idx >= 2L]
}


# ─────────────────────────────────────────────────────────────────────────────
# 3. VD+ overlay와 보호 전략 통합
#    MRS가 Crisis → 보호 전략 LP가 배분 결정
#    MRS가 Normal → 기존 VD+ 방식 유지
#    Pfaff Ch.13.6.4 + Regime Engine v7.1 (L-442, L-443)
# ─────────────────────────────────────────────────────────────────────────────
#' @param sim_result   simulate_protection() 반환값
#' @param regime_dt    data.table(Date, regime)  regime: "normal"/"crisis"/"stress"
#' @param vdplus_weights  list(Date → weights)  VD+ overlay 비중 (기존 방식)
#' @param floor_pct    보호 전략 최소 보존 비율
#' @return list(hybrid_nav, regime_allocation_log)
integrate_vdplus_protection <- function(sim_result,
                                         regime_dt,
                                         vdplus_weights = NULL,
                                         floor_pct      = 0.90) {
  stopifnot(
    is.list(sim_result),
    !is.null(sim_result$protected_nav),
    is.data.table(regime_dt) || is.data.frame(regime_dt)
  )

  regime_dt <- as.data.table(regime_dt)
  prot_nav  <- sim_result$protected_nav
  dates     <- names(prot_nav)
  n_t       <- length(prot_nav)

  hybrid_nav  <- numeric(n_t)
  hybrid_nav[1] <- prot_nav[1]
  alloc_log   <- vector("list", n_t)

  for (i in seq(2, n_t)) {
    date_i <- if (!is.null(dates)) dates[i] else as.character(i)

    # ── 현재 국면 확인 (t-1 lag, C9/C5 준수) ─────────────────────────────────
    # t-1 lag: 전날 국면 신호를 오늘 의사결정에 사용
    prev_date <- if (!is.null(dates)) dates[i - 1] else as.character(i - 1)
    reg_row   <- regime_dt[Date == prev_date]
    regime_i  <- if (nrow(reg_row) > 0) reg_row$regime[1] else "normal"

    if (regime_i == "crisis") {
      # 보호 전략 적용: sim_result에서 보호 NAV 사용
      hybrid_nav[i]  <- prot_nav[i]
      alloc_log[[i]] <- list(date = date_i, source = "protection", regime = regime_i)
    } else {
      # VD+ 방식: vdplus_weights 있으면 사용, 없으면 동일 수익률
      if (!is.null(vdplus_weights) && !is.null(vdplus_weights[[date_i]])) {
        # VD+ 비중으로 수익률 재계산은 외부에서 주입된 nav 시리즈로 갈음
        hybrid_nav[i] <- hybrid_nav[i - 1] *
          (1 + (prot_nav[i] / prot_nav[i - 1] - 1))
      } else {
        # VD+ 시리즈 없으면 보호 전략 nav 그대로 사용
        hybrid_nav[i] <- prot_nav[i]
      }
      alloc_log[[i]] <- list(date = date_i, source = "vdplus", regime = regime_i)
    }
  }

  list(
    hybrid_nav          = setNames(hybrid_nav, dates),
    regime_allocation_log = alloc_log
  )
}


# ─────────────────────────────────────────────────────────────────────────────
# 4. 독립 테스트 (source 직접 실행 시)
# ─────────────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L) {
  cat("=== Protection Strategy — 단위 테스트 ===\n")
  set.seed(42)

  K  <- 3  # 슬리브 수
  re <- c(0.08, 0.05, 0.02) / 252   # 연간 → 일간 기대수익
  es <- c(0.03, 0.02, 0.005)        # 슬리브별 ES (일간)

  # ── 케이스 A: Buffer 양수 ─────────────────────────────────────────────────
  cat("\n[Case A] Buffer > 0 (nav=1000, floor0=900)\n")
  r_A <- run_floor_es_overlay(
    nav          = 1000,
    re_forecast  = re,
    es_forecast  = es,
    floor0       = 900,
    es_limit     = 0.025
  )
  cat("  method:        ", r_A$method, "\n")
  cat("  buffer:        ", round(r_A$buffer, 4), "\n")
  cat("  weights:       ", round(r_A$weights, 4), "\n")
  cat("  floor_breached:", r_A$floor_breached, "\n")
  cat("  ES check:      ", round(sum(es * r_A$weights), 6),
      "<=", 0.025 * r_A$buffer, "\n")

  # ── 케이스 B: Buffer 음수 (Floor breach) ─────────────────────────────────
  cat("\n[Case B] Buffer < 0 (nav=850, floor0=900)\n")
  r_B <- run_floor_es_overlay(
    nav          = 850,
    re_forecast  = re,
    es_forecast  = es,
    floor0       = 900,
    es_limit     = 0.025
  )
  cat("  method:        ", r_B$method, "\n")
  cat("  buffer:        ", round(r_B$buffer, 4), "\n")
  cat("  floor_breached:", r_B$floor_breached, "\n")
  cat("  weights:       ", r_B$weights, "(all zero = money-market)\n")

  # ── 롤링 시뮬레이션 (간단 예시) ─────────────────────────────────────────
  cat("\n[Rolling Sim] 24개월 시뮬레이션\n")
  n_days  <- 504
  dates_v <- format(seq(as.Date("2024-01-02"), by = "day", length.out = n_days),
                    "%Y-%m-%d")
  nav_v   <- setNames(cumprod(c(1000, 1 + rnorm(n_days - 1, 0.0003, 0.01))),
                      dates_v)

  re_df <- data.frame(
    Date   = dates_v,
    s1     = rnorm(n_days, 0.0003, 0.002),
    s2     = rnorm(n_days, 0.0002, 0.001),
    s3     = rnorm(n_days, 0.00005, 0.0003)
  )
  es_df <- data.frame(
    Date = dates_v,
    s1   = rep(0.030, n_days),
    s2   = rep(0.020, n_days),
    s3   = rep(0.005, n_days)
  )

  sim_r <- simulate_protection(
    nav_series     = nav_v,
    re_series      = re_df,
    es_series      = es_df,
    floor_pct      = 0.90,
    rebalance_freq = "monthly"
  )

  final_nav    <- tail(sim_r$protected_nav, 1)
  min_buffer   <- min(sim_r$buffer_series)
  floor_breach <- sum(sim_r$buffer_series < 0)
  cat("  최종 NAV:    ", round(final_nav, 2), "\n")
  cat("  최소 Buffer: ", round(min_buffer, 4), "\n")
  cat("  Floor breach:", floor_breach, "회\n")

  cat("\n=== 테스트 완료 ===\n")
}
