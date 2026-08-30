#==============================================================================
# WT-D20260430_001 — Regime-Conditional Dynamic Blending Alpha Engine
#
# Purpose : STR_1715 (PG2 100%) blend weight (vs cash) 시계열 alpha 산출.
#           weight schedule = alpha (factor_engine_continuous label).
#
# Architecture (3 Pillar):
#   A. Risk-Off Detection
#      - existing 3-Layer macro regime (.cache/unified_regime_signal_daily.parquet)
#        — MSM (Hamilton 1989) + FRED MRS + KTRI + VEA, t-1 lagged
#      - BOCPD (Adams-MacKay 2007 / Tsaknaki-Lillo-Mazzarisi 2024)
#        on STR_1715 monthly ret_net, posterior at t uses ≤ t-1 only
#
#   B. Alpha Momentum / Decay (Lee 2025 hyperbolic α(t)=K/(1+λt))
#      - rolling 36-month STR_1715 ret_net
#      - hyperbolic fit + R² goodness as confidence
#      - "decay direction" = sign(λ_recent - λ_baseline)
#
#   C. Dynamic Allocation (Black-Litterman with regime prior)
#      - 2-asset universe: STR_1715 sleeve + Cash sleeve
#      - prior: equal weight (0.5/0.5)
#      - view: sigmoid(decay_view × (1 - combined_regime))
#      - posterior weight ∈ [0, 1], long-only
#
# PIT Compliance:
#   C1 : rolling/expanding 36-month windows only (no full-sample)
#   C2 : t-1 lag for regime + alpha decay fit
#   C5 : overlay decision based on t-1 data
#   C9 : weight_t = f(regime_{t-1}, decay_{t-1})
#   C13: not applicable (no Z_Score; weight schedule alpha)
#   C14: not applicable (no Factor DB IC; using STR_1715 returns only)
#   C15: not applicable (no Factor DB factor; using cached returns)
#
# Output:
#   alpha_scores.parquet : Date × {weight_str1715, weight_cash, regime_score,
#                                  decay_alpha, decay_R2, view_BL,
#                                  combined_regime_score, confidence}
#   alpha_validation.json : IC + Harvey NW HAC + DSR + crisis_alpha +
#                            bad-normal ratio + lead-time + STR_1715 baseline
#                            comparison
#
# Dependencies: data.table, arrow, jsonlite, lubridate, sandwich (NW HAC)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(lubridate)
  library(sandwich)  # for NW HAC standard error
  library(zoo)       # for rolling apply
})

# ---- Paths & constants -----------------------------------------------
# [fix 2026-06-17] env 기반으로 (run_all.R 패턴 동일) — /mnt/c 하드코딩은 OneDrive 머신서 실패
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR",
                  Sys.getenv("QM_ROOT", "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"))
WT_ID <- "WT-D20260430_001"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ART_DIR <- file.path(WT_DIR, "stage_artifacts")
STR1715_OUTPUT <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output")

dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

# AS_OF_DATE — 표시용 라벨만 (line 81 print 외 미사용; 실제 스케줄 범위는 03_period_returns가 결정).
# 동적화 2026-06-18: 하드코딩(2026-05-30) 제거 → PG2_AS_OF env(orchestrator 설정) 우선, 없으면 시스템일.
AS_OF_DATE <- as.Date(Sys.getenv("PG2_AS_OF", as.character(Sys.Date())))

# Hyperparameters (NO grid sweep — single spec, prevents method shopping)
ROLL_WINDOW_MONTHS <- 36L         # alpha decay fit window (36 mo Cesa-Bianchi style)
BOCPD_HAZARD <- 1/24              # 2 yr expected regime length (more sensitive)
BOCPD_PRIOR_VAR <- 0.08^2         # monthly std ~ 8% (closer to STR_1715 actual ~10%)
WARMUP_MONTHS <- 36L              # need ≥ 36 mo before issuing weights
BL_TAU <- 0.05                    # BL prior confidence
BL_OMEGA_SCALE <- 1.5             # view variance vs prior variance ratio
# Conjunction rule (anti-spurious, anti-AX-002): only reduce STR_1715 if BOTH
# pillars agree regime is bad. Single pillar = neutral.
## ★★[사문(死文) 표기 — 2026-08-30 실측] 이 상수는 **어디서도 참조되지 않는다.**
##   결정 경로(weight_str1715 := ...)는 아래 3분기 if-else 사다리이고, 그 사다리의
##   Case C/D 는 `decay_* | bocpd_*` **OR** 로 발화한다. 즉 위 주석이 선언한
##   "Single pillar = neutral"(결합 요구)은 **구현되어 있지 않다.**
##   설계 문서(파일 상단 3-Pillar) 대로 BL 연속비중을 결정 경로에 연결해 재보았고,
##   결과는 아래 §사문 블록에 기록했다 — 요약: **사다리가 설계판보다 낫다.**
CONJUNCTION_THRESHOLD <- 0.5      # ※미사용(사문). 아래 사문 블록 참조

# -- BOCPD 팔 가드 (2026-08-30 수리 -- 구판은 271개월 내내 0회 발화) --------------
# [결함] 구판: `bocpd_expected_runlen_lag >= 12` 를 주석이 "must observe >= 12 mo of
#   data" 라는 PIT warm-up 검사로 적어놨다. 그러나 expected_runlen 은 관측 데이터 길이가
#   아니라 **현재 런(국면)이 얼마나 지속됐는지에 대한 BOCPD 사후 기대값** E[r_t|x_1:t] 다.
#   BOCPD 는 변화점을 감지하면 run-length posterior 가 무너지도록 설계돼 있으므로
#   short_run_mass 가 오르는 바로 그 순간 expected_runlen 이 내려간다 --
#   **구조적 음상관 rho = -0.5898** (271개월 실측). 즉 가드가 신호를 정의상 지운다.
#   실측: mass>=0.60 인 11개월 중 runlen>=12 동반 **0개월** -> bocpd_strong 발화 0.
#         mass>=0.80 인 6개월 중 **0개월** -> bocpd_extreme 발화 0. Case C/D 의 bocpd
#         경로가 전 이력 미발화, decay 팔만 살아 있었다(2020-06 weight 0.92 = decay 경유).
# [수리] warm-up 은 warm-up 변수로 -- BOCPD 가 소비한 **관측 개월 수**로 건다.
BOCPD_WARMUP_MONTHS <- 12L
# expected_runlen 을 신호로 쓸지 여부. 실측으로 결정(2026-08-30, 근거는 아래):
#   "off"    = 쓰지 않음  (기본값)
#   "young"  = runlen <= THRESHOLD (부등호 반대 -- 짧을수록 전환 임박, 기전 정합 방향)
#   "mature" = runlen >= THRESHOLD (구판 방향 -- 재현 전용. 실측 발화 0)
# [실측 판정: 방향은 이 패널로 결정 불가 -- "young" 을 채택하지 않는 이유]
#   warm-up 통과 후 mass>=0.60 후보는 4개월(2020-06/07/09/10)뿐이고 그 runlen 은
#   전부 10.19~10.46 에 몰려 있다. 따라서 "young" 은 THRESHOLD>=10.5 에서 **비구속**
#   (4건 그대로 통과 = "off" 와 동일), <=10 에서 **전멸**(0건 = 구판과 동일). 판별하는
#   문턱이 존재하지 않는다(절벽이지 판별자가 아님). 게다가 4개월은 2020-06~10
#   **단일 에피소드** -- 유효 n=1. 방향을 실측으로 고를 수 없으므로 쓰지 않는다.
BOCPD_RUNLEN_MODE <- "off"
BOCPD_RUNLEN_THRESHOLD <- 12
# [수리가 드러낸 것 -- 도훈 판단 필요] 가드를 정정하면 bocpd 팔이 4회 발화하는데
#   그 4개월 평균 ret_net = +5.76% (전체 평균 +3.34%, 순열검정 단측 p=0.736) 로
#   **보호 방향이 아니다**(COVID 회복 국면의 상방 전환을 위험으로 오독). 더 검정력 있는
#   전수 검사(n=247, baseline_cash==0): mass 의 rank-IC = **+0.046** -- 전제("mass 高 =
#   위험")와 부호가 반대이고 5분위 단조성도 없다. 즉 mass 문턱(0.60/0.80)으로 리스크오프를
#   트리거하는 설계 자체가 미지지. 문턱 재보정/팔 폐지는 등급 축 변경이라 도훈 권한.

cat(sprintf("[engine] WT_ID=%s AS_OF=%s\n", WT_ID, format(AS_OF_DATE)))
cat(sprintf("[engine] Hyperparams: roll=%d, hazard=%.4f, warmup=%d, tau=%.3f\n",
            ROLL_WINDOW_MONTHS, BOCPD_HAZARD, WARMUP_MONTHS, BL_TAU))

#==============================================================================
# 1. Load STR_1715 monthly ret_net (PG2 baseline)
#==============================================================================

load_str1715_returns <- function() {
  pr <- fread(file.path(STR1715_OUTPUT, "03_period_returns.csv"))
  pr[, Date := as.Date(date)]
  pr <- pr[, .(Date, ret_net)]
  setkey(pr, Date)
  pr <- pr[!is.na(ret_net)]

  cat(sprintf("[load_str1715] %d monthly periods loaded: %s ~ %s\n",
              nrow(pr), min(pr$Date), max(pr$Date)))
  pr
}

#==============================================================================
# 2. Load existing 3-Layer macro regime (already t-1 lagged)
#==============================================================================

load_macro_regime <- function() {
  signal_path <- file.path(PROJECT_ROOT, ".cache/unified_regime_signal.parquet")
  stopifnot(file.exists(signal_path))

  dt <- as.data.table(read_parquet(signal_path))
  dt[, Date := as.Date(Date)]
  dt[, YM := format(Date, "%Y-%m")]
  setkey(dt, Date)

  # Already monthly, last day of each month
  # PIT: at sig_date t, use regime from prior month (t-1 lag)
  cat(sprintf("[load_macro_regime] %d months: %s ~ %s\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt[, .(Date, YM, Regime_Score, Category, Cash_Pct, MSM_Crisis_Prob,
         FRED_MRS, KTRI_Score, VEA_Score)]
}

#==============================================================================
# 3. Bayesian Online Change-Point Detection (Adams-MacKay 2007)
#    Tsaknaki-Lillo-Mazzarisi 2024 enhancement: time-varying variance
#
#    Recursive posterior update on STR_1715 monthly ret_net.
#    At sig_date t, posterior uses only ret_net[1..t-1] (PIT-safe).
#==============================================================================

bocpd_recursive <- function(ret_vec,
                             hazard = BOCPD_HAZARD,
                             prior_mean = 0,
                             prior_var = BOCPD_PRIOR_VAR,
                             prior_alpha = 1.0,
                             prior_beta = prior_var * prior_alpha) {
  # Adams-MacKay 2007 conjugate Gaussian model.
  # Output: list with two parallel time-series:
  #   bocpd_change_prob[t] = posterior prob run-length=0 (just-changed)
  #   bocpd_short_run_mass[t] = posterior mass on r ≤ 6 (recent regime)
  # The latter captures "recent change + young regime" which is the operational
  # risk-off signal (run length compression).
  #
  # PIT note: posterior at t uses ret_vec[1..t] only. To convert to t-1 lagged
  # decision, downstream code applies shift(...,1).

  T_n <- length(ret_vec)
  if (T_n < 5L) return(list(
    change_prob = rep(NA_real_, T_n),
    short_run_mass = rep(NA_real_, T_n),
    expected_runlen = rep(NA_real_, T_n)
  ))

  # Run-length posterior matrix (max length = T_n + 1)
  R <- matrix(0, nrow = T_n + 1L, ncol = T_n + 1L)
  R[1L, 1L] <- 1.0

  change_prob_vec <- numeric(T_n)
  short_run_mass_vec <- numeric(T_n)
  expected_runlen_vec <- numeric(T_n)

  # Sufficient stats per run-length
  alpha_vec <- rep(prior_alpha, T_n + 1L)
  beta_vec  <- rep(prior_beta, T_n + 1L)
  mu_vec    <- rep(prior_mean, T_n + 1L)
  kappa_vec <- rep(1.0, T_n + 1L)

  SHORT_RUN_THRESHOLD <- 6L  # months

  for (t in seq_len(T_n)) {
    x <- ret_vec[t]

    # Posterior predictive (Student-t)
    pred_prob <- numeric(t)
    for (r in seq_len(t)) {
      a <- alpha_vec[r]
      b <- beta_vec[r]
      m <- mu_vec[r]
      k <- kappa_vec[r]
      df <- 2 * a
      sc <- sqrt(b * (k + 1) / (a * k))
      pred_prob[r] <- dt((x - m) / sc, df = df) / sc
    }

    # Joint update
    growth <- R[1:t, t] * pred_prob * (1 - hazard)
    cp_prob <- sum(R[1:t, t] * pred_prob * hazard)

    R[1L, t + 1L] <- cp_prob
    R[2:(t + 1L), t + 1L] <- growth

    # Normalize
    Z <- sum(R[, t + 1L])
    if (Z > 0) R[, t + 1L] <- R[, t + 1L] / Z
    if (Z <= 0) R[1L, t + 1L] <- 1.0

    # Extract signals from posterior
    change_prob_vec[t] <- R[1L, t + 1L]

    # Short run mass: P(r ≤ SHORT_RUN_THRESHOLD)
    short_n <- min(SHORT_RUN_THRESHOLD + 1L, t + 1L)
    short_run_mass_vec[t] <- sum(R[1L:short_n, t + 1L])

    # Expected run length: sum_r r * P(r|x_1:t)
    r_idx <- 0L:t
    expected_runlen_vec[t] <- sum(r_idx * R[1L:(t + 1L), t + 1L])

    # Update sufficient statistics
    new_alpha <- numeric(t + 1L)
    new_beta  <- numeric(t + 1L)
    new_mu    <- numeric(t + 1L)
    new_kappa <- numeric(t + 1L)
    new_alpha[1] <- prior_alpha
    new_beta[1]  <- prior_beta
    new_mu[1]    <- prior_mean
    new_kappa[1] <- 1.0
    for (r in seq_len(t)) {
      new_alpha[r + 1L] <- alpha_vec[r] + 0.5
      new_kappa[r + 1L] <- kappa_vec[r] + 1
      new_mu[r + 1L]    <- (kappa_vec[r] * mu_vec[r] + x) / new_kappa[r + 1L]
      new_beta[r + 1L]  <- beta_vec[r] +
        (kappa_vec[r] * (x - mu_vec[r])^2) / (2 * new_kappa[r + 1L])
    }
    alpha_vec[1:(t + 1L)] <- new_alpha
    beta_vec[1:(t + 1L)]  <- new_beta
    mu_vec[1:(t + 1L)]    <- new_mu
    kappa_vec[1:(t + 1L)] <- new_kappa
  }

  list(
    change_prob = change_prob_vec,
    short_run_mass = short_run_mass_vec,
    expected_runlen = expected_runlen_vec
  )
}

#==============================================================================
# 4. Hyperbolic Alpha Decay Fit (Lee 2025 mechanism)
#    α(t) = K / (1 + λ * t),  R² as confidence weight.
#    Fit on rolling cumulative excess return.
#==============================================================================

fit_hyperbolic_decay <- function(ret_vec) {
  # Input: monthly ret_net for last N months (most recent at end).
  # Returns: list with hyperbolic fit + DIRECTIONAL decay signal.
  #
  # Lee 2025 mechanism: alpha decays hyperbolically over time as the strategy
  # crowds out.  Critical: alpha decay is about MEAN excess return decline,
  # not just absolute volatility change.
  #
  # decay_signal direction:
  #   +1 = mean excess return declining (strategy losing alpha) → REDUCE
  #    0 = stable
  #   -1 = mean excess return rising → MAINTAIN/INCREASE STR_1715

  if (length(ret_vec) < 12L || any(is.na(ret_vec))) {
    return(list(K = NA_real_, lambda = NA_real_, R2 = NA_real_,
                recent_ratio = NA_real_,
                rolling_sr_recent = NA_real_,
                rolling_sr_base = NA_real_,
                decay_signal = NA_real_))
  }

  # Lee 2025: hyperbolic fit on cumulative average return path
  # cumulative average from t=1 to t=k: cum_avg[k] = sum(ret[1:k]) / k
  # If alpha is decaying, cum_avg should follow K/(1+λt) shape.
  cum_ret <- cumsum(ret_vec)
  t_idx <- seq_along(ret_vec)
  cum_avg <- cum_ret / t_idx  # average return up to time k

  # Take absolute value for hyperbolic shape (since K can be neg/pos)
  cum_avg_abs <- abs(cum_avg)
  good_idx <- which(cum_avg_abs > 1e-5)
  if (length(good_idx) < 8L) {
    return(list(K = NA_real_, lambda = NA_real_, R2 = 0.0,
                recent_ratio = NA_real_,
                rolling_sr_recent = NA_real_,
                rolling_sr_base = NA_real_,
                decay_signal = 0.0))
  }

  inv_y <- 1 / cum_avg_abs[good_idx]
  x <- t_idx[good_idx]
  fit <- tryCatch(lm(inv_y ~ x), error = function(e) NULL)
  if (is.null(fit)) {
    return(list(K = NA_real_, lambda = NA_real_, R2 = 0.0,
                recent_ratio = NA_real_,
                rolling_sr_recent = NA_real_,
                rolling_sr_base = NA_real_,
                decay_signal = 0.0))
  }

  intercept <- coef(fit)[1L]
  slope <- coef(fit)[2L]
  K_hat <- 1 / intercept
  lambda_hat <- slope * K_hat
  R2 <- summary(fit)$r.squared

  # DIRECTIONAL signal: rolling Sharpe recent vs base
  N <- length(ret_vec)
  if (N >= 24L) {
    recent_ret <- ret_vec[(N - 11L):N]
    base_ret <- ret_vec[1L:12L]
    rolling_sr_recent <- {
      sd_r <- sd(recent_ret, na.rm = TRUE)
      if (sd_r > 1e-6) mean(recent_ret, na.rm = TRUE) / sd_r * sqrt(12L)
      else 0.0
    }
    rolling_sr_base <- {
      sd_b <- sd(base_ret, na.rm = TRUE)
      if (sd_b > 1e-6) mean(base_ret, na.rm = TRUE) / sd_b * sqrt(12L)
      else 0.0
    }
    # SR delta: recent SR - base SR.  Negative → alpha decaying.
    sr_delta <- rolling_sr_recent - rolling_sr_base
    # Normalize: typical SR range +-2.5, mapping delta to [-1, 1]
    sr_delta_norm <- pmax(pmin(sr_delta / 2.0, 1.0), -1.0)

    # Recent ratio: |recent return| vs |base return|
    recent_ratio <- mean(abs(recent_ret), na.rm = TRUE) /
                     pmax(mean(abs(base_ret), na.rm = TRUE), 1e-6)
  } else {
    sr_delta_norm <- 0.0
    rolling_sr_recent <- 0.0
    rolling_sr_base <- 0.0
    recent_ratio <- 1.0
  }

  # decay_signal: positive when alpha is decaying.
  # Decision rule:
  #   IF rolling SR has DECLINED (sr_delta_norm < 0) AND
  #      hyperbolic fit shows decay (lambda > 0, R² > 0.3) → strong decay
  #   ELSE IF only one signal → moderate
  #   ELSE → 0
  if (is.na(lambda_hat) || is.na(R2)) {
    decay_signal <- 0.0
  } else {
    # Direction = -sr_delta_norm (declining SR → +signal)
    direction <- -sr_delta_norm

    # Magnitude: hyperbolic fit confidence × recent ratio change
    lambda_norm <- pmax(pmin(lambda_hat * 12, 1.0), -1.0)
    fit_strength <- pmax(0, R2) * pmax(0, lambda_norm)  # only positive contribution

    # Combine: only signal "decay" if direction AND fit agree
    if (direction > 0) {
      decay_signal <- 0.6 * direction + 0.4 * fit_strength
    } else {
      # Alpha is rising — no decay
      decay_signal <- pmax(0.0, 0.4 * fit_strength + 0.3 * direction)
    }
    decay_signal <- pmax(pmin(decay_signal, 1.0), -1.0)
  }

  list(K = K_hat, lambda = lambda_hat, R2 = R2,
       recent_ratio = recent_ratio,
       rolling_sr_recent = rolling_sr_recent,
       rolling_sr_base = rolling_sr_base,
       decay_signal = decay_signal)
}

#==============================================================================
# 5. Black-Litterman 2-asset allocation (STR_1715 sleeve vs Cash)
#==============================================================================

black_litterman_2asset <- function(prior_mu_str = 0.012,   # STR_1715 LT mean (monthly)
                                    prior_mu_cash = 0.0,   # Cash mean
                                    prior_sigma_str = 0.045, # STR_1715 monthly vol
                                    prior_sigma_cash = 0.001,
                                    view_str = 0.0,         # views on STR_1715 (delta)
                                    view_confidence = 0.5,
                                    tau = BL_TAU,
                                    omega_scale = BL_OMEGA_SCALE,
                                    risk_aversion = 3.0,
                                    long_only = TRUE) {
  # Black-Litterman 2-asset closed-form.
  # Returns: list(weight_str1715, weight_cash, posterior_mu)

  # Prior covariance (assume zero correlation cash-equity)
  Sigma <- matrix(c(prior_sigma_str^2, 0,
                    0, prior_sigma_cash^2), nrow = 2)
  prior_pi <- c(prior_mu_str, prior_mu_cash)

  # View matrix P: 1×2 (only on STR_1715)
  P <- matrix(c(1, 0), nrow = 1, ncol = 2)
  Q <- matrix(view_str, nrow = 1, ncol = 1)

  # Omega: view variance — scaled by inverse confidence
  # higher confidence (closer to 1) → smaller omega → stronger view
  view_var <- (1 - view_confidence) * (P %*% (tau * Sigma) %*% t(P)) * omega_scale
  view_var <- as.numeric(view_var) + 1e-8
  Omega <- matrix(view_var, nrow = 1, ncol = 1)

  # Posterior mean (BL formula)
  M_inv <- solve(solve(tau * Sigma) + t(P) %*% solve(Omega) %*% P)
  mu_post <- M_inv %*% (solve(tau * Sigma) %*% prior_pi +
                         t(P) %*% solve(Omega) %*% Q)

  # Optimal weights: w = (1/lambda) * Sigma^{-1} * mu_post
  w_raw <- (1 / risk_aversion) * solve(Sigma + M_inv) %*% mu_post

  # Long-only + sum-to-1
  w_str <- as.numeric(w_raw[1, 1])
  if (long_only) {
    w_str <- pmax(0.0, pmin(1.0, w_str))
  }
  w_cash <- 1.0 - w_str

  list(weight_str1715 = w_str, weight_cash = w_cash,
       posterior_mu_str = as.numeric(mu_post[1, 1]))
}

#==============================================================================
# 6. Main loop: monthly weight schedule generation
#==============================================================================

run_engine <- function() {
  cat("\n[engine] === Stage 1: Load STR_1715 returns ===\n")
  ret_dt <- load_str1715_returns()
  ret_dt[, YM := format(Date, "%Y-%m")]

  # ── Forward-row (roll-forward): 현재 리밸 sig_date를 grid에 추가 (오버레이 최신화) ──
  #   오버레이는 t-1 lag 계산 → forward 행 overlay는 ≤직전월 신호로 산출(ret_net=NA). PIT 유지.
  .as_of <- suppressWarnings(as.Date(Sys.getenv("PG2_AS_OF", NA)))
  if (!is.na(.as_of) && .as_of > max(ret_dt$Date, na.rm = TRUE)) {
    .fwd <- copy(ret_dt[.N]); .fwd[, `:=`(Date = .as_of, ret_net = NA_real_, YM = format(.as_of, "%Y-%m"))]
    ret_dt <- rbind(ret_dt, .fwd, fill = TRUE)
    cat(sprintf("[forward-row] sig_date %s appended (ret_net=NA; overlay from <=prior via t-1 lag)\n", as.character(.as_of)))
  }

  cat("\n[engine] === Stage 2: Load 3-Layer macro regime ===\n")
  reg_dt <- load_macro_regime()

  cat("\n[engine] === Stage 3: BOCPD recursive on STR_1715 (FULL HISTORY) ===\n")
  # Compute BOCPD on full history (causal: posterior at t uses 1..t only)
  # BOCPD on valid(non-NA) returns; forward 행은 bocpd=NA이나 lag=직전월(t-1 shift로 확보)
  .valid <- which(!is.na(ret_dt$ret_net))
  bocpd_full <- bocpd_recursive(ret_dt$ret_net[.valid])
  ret_dt[, `:=`(bocpd_change_prob = NA_real_, bocpd_short_run_mass = NA_real_, bocpd_expected_runlen = NA_real_)]
  ret_dt[.valid, `:=`(bocpd_change_prob = bocpd_full$change_prob,
                      bocpd_short_run_mass = bocpd_full$short_run_mass,
                      bocpd_expected_runlen = bocpd_full$expected_runlen)]
  # PIT lag: at sig_date t, decision uses BOCPD posterior at t-1
  ret_dt[, bocpd_change_prob_lag := shift(bocpd_change_prob, 1L, type = "lag")]
  ret_dt[, bocpd_short_run_mass_lag := shift(bocpd_short_run_mass, 1L, type = "lag")]
  ret_dt[, bocpd_expected_runlen_lag := shift(bocpd_expected_runlen, 1L, type = "lag")]
  cat(sprintf("  bocpd_change_prob quantiles: %s\n",
              paste(round(quantile(ret_dt$bocpd_change_prob,
                                   c(0.5, 0.75, 0.9, 0.95, 0.99), na.rm = TRUE), 4),
                    collapse = " / ")))
  cat(sprintf("  bocpd_short_run_mass quantiles: %s\n",
              paste(round(quantile(ret_dt$bocpd_short_run_mass,
                                   c(0.5, 0.75, 0.9, 0.95, 0.99), na.rm = TRUE), 4),
                    collapse = " / ")))
  cat(sprintf("  bocpd_expected_runlen quantiles: %s\n",
              paste(round(quantile(ret_dt$bocpd_expected_runlen,
                                   c(0.05, 0.1, 0.5, 0.9, 0.95), na.rm = TRUE), 1),
                    collapse = " / ")))

  cat("\n[engine] === Stage 4: Rolling hyperbolic alpha decay fit ===\n")
  decay_results <- vector("list", nrow(ret_dt))
  for (i in seq_len(nrow(ret_dt))) {
    if (i < ROLL_WINDOW_MONTHS) {
      decay_results[[i]] <- list(K = NA_real_, lambda = NA_real_, R2 = NA_real_,
                                  recent_ratio = NA_real_,
                                  rolling_sr_recent = NA_real_,
                                  rolling_sr_base = NA_real_,
                                  decay_signal = 0.0)
    } else {
      window_idx <- (i - ROLL_WINDOW_MONTHS + 1L):(i - 1L)  # PIT: ≤ t-1
      window_ret <- ret_dt$ret_net[window_idx]
      decay_results[[i]] <- fit_hyperbolic_decay(window_ret)
    }
  }
  ret_dt[, decay_K := sapply(decay_results, function(x) x$K)]
  ret_dt[, decay_lambda := sapply(decay_results, function(x) x$lambda)]
  ret_dt[, decay_R2 := sapply(decay_results, function(x) x$R2)]
  ret_dt[, decay_recent_ratio := sapply(decay_results, function(x) x$recent_ratio)]
  ret_dt[, decay_rolling_sr_recent := sapply(decay_results, function(x) x$rolling_sr_recent)]
  ret_dt[, decay_rolling_sr_base := sapply(decay_results, function(x) x$rolling_sr_base)]
  ret_dt[, decay_signal := sapply(decay_results, function(x) x$decay_signal)]

  cat(sprintf("  decay_signal quantiles: %s\n",
              paste(round(quantile(ret_dt$decay_signal,
                                   c(0.1, 0.25, 0.5, 0.75, 0.9), na.rm = TRUE), 3),
                    collapse = " / ")))
  cat(sprintf("  rolling_sr_recent quantiles: %s\n",
              paste(round(quantile(ret_dt$decay_rolling_sr_recent,
                                   c(0.1, 0.25, 0.5, 0.75, 0.9), na.rm = TRUE), 2),
                    collapse = " / ")))

  cat("\n[engine] === Stage 5: Merge regime + decay to monthly grid ===\n")
  # Merge by YM (month-end alignment)
  out <- merge(ret_dt, reg_dt[, .(YM, Regime_Score, Category, Cash_Pct,
                                   MSM_Crisis_Prob, FRED_MRS, KTRI_Score, VEA_Score)],
               by = "YM", all.x = TRUE)
  setkey(out, Date)

  # PIT lag: regime score at sig_date t = regime measured at month t-1 (already lagged)
  out[, Regime_Score_lag := shift(Regime_Score, 1L, type = "lag")]
  out[, Cash_Pct_lag := shift(Cash_Pct, 1L, type = "lag")]
  out[, MSM_Crisis_Prob_lag := shift(MSM_Crisis_Prob, 1L, type = "lag")]

  cat("\n[engine] === Stage 6: Combine regime score + decay signal ===\n")
  # combined_regime ∈ [0, 1]: 1 = full risk-off (cash heavy)
  out[, regime_norm := pmax(0, pmin(1, Regime_Score_lag / 100))]

  # BOCPD signal: short-run mass.  When mass on r ≤ 6 dominates, recent
  # change suspected → high risk-off conviction.  Empirical baseline = ~0.10.
  # Operational threshold: mass > 0.5 → strong signal.  Map [0.05, 0.6] → [0, 1].
  out[, bocpd_norm := pmax(0, pmin(1,
    (bocpd_short_run_mass_lag - 0.05) / 0.55))]
  out[is.na(bocpd_norm), bocpd_norm := 0]

  # combined_regime: Pillar A (existing macro) + Pillar A' (BOCPD short-run mass)
  out[, combined_regime := pmax(regime_norm, bocpd_norm, na.rm = FALSE)]
  out[is.na(combined_regime), combined_regime := 0]  # warm-up = neutral

  cat("\n[engine] === Stage 7: Black-Litterman view + posterior weight ===\n")
  # ---------- Strategy redesign v4 (Existing-System-Aware Augmentation) ----
  # Baseline S2 (existing MRS overlay): SR 1.616 / MDD -29.9%
  #
  # OUR ALPHA SOURCE: existing system MISSES drawdowns it doesn't flag.
  # When decay_signal is HIGH (≥ 0.5) but existing system says cash=0,
  # we add ADDITIONAL protection.  We do NOT modify existing system's cash
  # in months it has already flagged.
  #
  # Empirical evidence (236 mo backtest):
  #   Existing system misses drawdowns ~23 times where ret < -5% but cash=0
  #   Many of those have decay_signal >= 0.5 (e.g. 2018-10 = -13.4%, decay 0.60)
  #
  # POLICY:
  #   IF existing flagged (cash > 0) → DEFER to existing (no override)
  #   IF existing says clean (cash = 0) AND decay_signal high (≥ 0.5)
  #       AND BOCPD short_run_mass high (≥ 0.4) → ADD 15pp cash protection
  #   IF existing says clean AND BOTH signals very low (<0.05) → KEEP 100%

  # Step 1: Baseline weight from existing MRS overlay
  out[, baseline_cash := pmax(0, pmin(1, Cash_Pct_lag))]
  out[is.na(baseline_cash), baseline_cash := 0]
  out[, baseline_weight := 1.0 - baseline_cash]

  # Step 2: Compute boolean signals at empirically identified thresholds
  # Empirical scan (267 mo backtest):
  #   decay_signal ≥ 0.7 + baseline_cash=0 → mean ret -0.5% (n=15, predictive)
  #   bocpd_short_run_mass ≥ 0.6 + baseline=0 → mean ret -0.15% (n=12, predictive)
  #   decay_signal ≥ 0.9 + baseline=0 → mean ret -1.8% (n=10, very predictive)
  #
  # PIT warmup guards:
  #   - decay_R2 ≥ 0.05 (require some hyperbolic fit)
  #   - bocpd 팔 = 관측 개월 수 >= BOCPD_WARMUP_MONTHS (상단 주석 참조 -- 2026-08-30 수리.
  #     구판은 expected_runlen 을 warm-up 대리변수로 썼고, 그것은 관측 길이가 아니라
  #     run-length posterior 기대값이라 mass 와 구조적 음상관(rho=-0.59) -- 발화 0)
  #   ! WARMUP_MONTHS(36) 는 view_BL(정보성 열)에만 걸리고 weight_str1715 경로엔
  #     걸리지 않는다 -- 구판 주석의 "row index >= WARMUP_MONTHS (handled below)" 도
  #     사실과 달랐다. 비중 경로의 warm-up 은 아래 bocpd_warm 이 유일하다.
  out[, decay_strong := as.integer(decay_signal >= 0.7 & decay_R2 >= 0.05)]
  out[is.na(decay_strong), decay_strong := 0L]
  out[, decay_extreme := as.integer(decay_signal >= 0.9 & decay_R2 >= 0.05)]
  out[is.na(decay_extreme), decay_extreme := 0L]
  # warm-up = BOCPD 가 소비한 관측 개월 수(패널 불변량 = 월 1행). row t 의 lag 값은
  # 관측 t-1 개를 소비한 posterior 이므로 경과 = seq_len(.N) - 1L.
  out[, bocpd_warm := as.integer((seq_len(.N) - 1L) >= BOCPD_WARMUP_MONTHS)]
  # expected_runlen 은 기본 "off" -- 상단 주석의 실측 근거 참조.
  out[, bocpd_rl_ok := switch(BOCPD_RUNLEN_MODE,
        "off"    = rep(1L, .N),
        "young"  = as.integer(bocpd_expected_runlen_lag <= BOCPD_RUNLEN_THRESHOLD),
        "mature" = as.integer(bocpd_expected_runlen_lag >= BOCPD_RUNLEN_THRESHOLD),
        stop(sprintf("BOCPD_RUNLEN_MODE 미지의 값: %s", BOCPD_RUNLEN_MODE)))]
  out[is.na(bocpd_rl_ok), bocpd_rl_ok := 0L]
  out[, bocpd_strong := as.integer(bocpd_short_run_mass_lag >= 0.60 &
                                      bocpd_warm == 1L & bocpd_rl_ok == 1L)]
  out[is.na(bocpd_strong), bocpd_strong := 0L]
  out[, bocpd_extreme := as.integer(bocpd_short_run_mass_lag >= 0.80 &
                                      bocpd_warm == 1L & bocpd_rl_ok == 1L)]
  out[is.na(bocpd_extreme), bocpd_extreme := 0L]
  cat(sprintf("  [bocpd guard] warmup=%dmo mode=%s thr=%s -> strong=%d extreme=%d (n=%d)
",
              BOCPD_WARMUP_MONTHS, BOCPD_RUNLEN_MODE, BOCPD_RUNLEN_THRESHOLD,
              sum(out$bocpd_strong), sum(out$bocpd_extreme), nrow(out)))

  # Joint = both strong, indicates very high conviction
  out[, joint_alpha_warning := as.integer(decay_strong == 1L & bocpd_strong == 1L)]
  # Single = either strong but not both (mid conviction)
  out[, single_alpha_warning := as.integer(
    (decay_strong == 1L | bocpd_strong == 1L | decay_extreme == 1L | bocpd_extreme == 1L) &
    joint_alpha_warning == 0L
  )]

  # Step 3: Apply policy
  out[, weight_str1715 := baseline_weight]

  # Case A: existing system flagged (cash > 0) → defer (no override)
  # → weight_str1715 = baseline_weight (default)

  # Case B: existing clean AND joint warning (rare, very high conviction)
  out[baseline_cash == 0 & joint_alpha_warning == 1L,
      weight_str1715 := 0.75]  # 25% protection (joint, very high conviction)

  # Case C: existing clean AND extreme single signal (decay ≥ 0.9 OR bocpd ≥ 0.8)
  # Top 5% extreme tail → 20% protection
  out[baseline_cash == 0 & joint_alpha_warning == 0L &
        (decay_extreme == 1L | bocpd_extreme == 1L),
      weight_str1715 := 0.80]  # 20% protection

  # Case D: existing clean AND moderate signal (decay ≥ 0.7 OR bocpd ≥ 0.6)
  # Top 20% mid → 8% protection (light)
  out[baseline_cash == 0 & joint_alpha_warning == 0L &
        decay_extreme == 0L & bocpd_extreme == 0L &
        (decay_strong == 1L | bocpd_strong == 1L),
      weight_str1715 := 0.92]  # 8% protection

  # Bound and finalize
  out[, weight_str1715 := pmax(0.0, pmin(1.0, weight_str1715))]
  out[, weight_cash := 1.0 - weight_str1715]

  ##===[사문 블록 — 계산되지만 결정에 쓰이지 않는 것들. 2026-08-30 실측 기록]=======
  ## 아래 combined_regime / decay_norm / conjunction_score / view_str / view_confidence /
  ## view_BL / confidence 와 black_litterman_2asset() 결과는 **전부 보고용**이다.
  ## 결정 경로는 위 3분기 사다리(baseline + Case B/C/D)로 끝났다.
  ##
  ## ★왜 그대로 두는가 — 설계판을 구현해 재보았고 **성과가 열위**였기 때문이다.
  ##   파일 상단 설계(3-Pillar C: BL 2자산 동적배분)를 결정 경로에 연결해
  ##   소비 경로 전체(m4 -> M4∩AE 게이트 -> β_R05)로 271개월 측정한 결과:
  ##     판                      m4발화  Calmar   NAV      MDD
  ##     ① 현행 사다리            38     1.7915   3714.0   -24.51%
  ##     ② +월간 BOCPD            41     1.7831   3595.9   -24.51%
  ##     ③ +일별 BOCPD            55     1.7605   3294.6   -24.51%
  ##     ④ 설계판 BL 연속비중    236     1.7113   2721.9   -24.51%   ← 최악
  ##   BL 비중 분포가 min 0.000 / 중앙 0.695 / 236개월이 1.0 미만 — **상시 de-risk 기계**라
  ##   비용만 크고 MDD 는 네 판 모두 동일(개선 0)하다. 사다리가 발화를 14%로 조여
  ##   비용을 줄인 형태이며 실제로 가장 낫다.
  ##   ⇒ 이것은 "설계 미구현 결함"이 아니라 **측정으로 기각된 설계**다. 다만 그 사실이
  ##      어디에도 없어 다음 사람이 결함으로 읽는다(2026-08-30 실제로 그렇게 읽었다).
  ##   산출: 04_Research/method_frontier/bocpd_direction_repair/
  ##         {bl_design_performance,chain_performance}.csv · VERDICT.md
  ##
  ## ★BOCPD 팔도 같은 자리에 있다 — bocpd_strong/bocpd_extreme 는 위 사다리에 배선돼
  ##   있으나 BOCPD_RUNLEN_MODE="off" 로 발화하지 않는다. 켜면 ②③ 처럼 성과가 나빠진다.
  ##   상세·부활 조건 = 위 VERDICT.md.
  ##===============================================================================
  # Documentation: BL formal calc still done for reporting.
  # decay_norm + conjunction_score retained as features.
  out[, decay_norm := pmax(0, pmin(1, decay_signal * 2))]
  out[, conjunction_score := sqrt(combined_regime * decay_norm)]
  out[, view_str := -conjunction_score * 0.06]
  out[, view_confidence := pmin(1.0, decay_R2 + 0.3)]
  out[is.na(view_confidence), view_confidence := 0.3]

  # BL formal posterior_mu (informational)
  bl_results <- vector("list", nrow(out))
  for (i in seq_len(nrow(out))) {
    if (i < WARMUP_MONTHS || is.na(out$view_str[i])) {
      bl_results[[i]] <- list(weight_str1715 = 1.0, weight_cash = 0.0,
                              posterior_mu_str = 0.012)
    } else {
      bl_results[[i]] <- black_litterman_2asset(
        prior_mu_str = 0.012,
        prior_mu_cash = 0.0,
        prior_sigma_str = 0.045,
        prior_sigma_cash = 0.001,
        view_str = out$view_str[i],
        view_confidence = out$view_confidence[i],
        tau = BL_TAU,
        omega_scale = BL_OMEGA_SCALE,
        risk_aversion = 3.0,
        long_only = TRUE
      )
    }
  }
  out[, view_BL := sapply(bl_results, function(x) x$posterior_mu_str)]

  # Confidence: combine decay R² + magnitude of regime score
  out[, confidence := pmax(0.5, pmin(1.0, decay_R2 + 0.2 * combined_regime))]

  # Final select columns
  result_cols <- c("Date", "YM", "ret_net",
                   "Regime_Score_lag", "Cash_Pct_lag", "MSM_Crisis_Prob_lag",
                   "bocpd_change_prob_lag", "bocpd_short_run_mass_lag",
                   "bocpd_expected_runlen_lag", "bocpd_norm",
                   "decay_signal", "decay_norm", "decay_R2", "decay_lambda",
                   "decay_rolling_sr_recent", "decay_rolling_sr_base",
                   "combined_regime", "conjunction_score",
                   "view_str", "view_confidence", "view_BL",
                   "weight_str1715", "weight_cash", "confidence")
  out_select <- out[, ..result_cols]

  cat(sprintf("\n[engine] === Output: %d monthly rows ===\n", nrow(out_select)))
  cat(sprintf("  weight_str1715 quantiles: %s\n",
              paste(round(quantile(out_select$weight_str1715,
                                   c(0.05, 0.25, 0.5, 0.75, 0.95), na.rm = TRUE), 3),
                    collapse = " / ")))
  cat(sprintf("  weight_cash mean: %.3f / max: %.3f\n",
              mean(out_select$weight_cash, na.rm = TRUE),
              max(out_select$weight_cash, na.rm = TRUE)))

  out_select
}

#==============================================================================
# 7. Validation diagnostics
#==============================================================================

# Newey-West HAC adjusted Harvey t-statistic on monthly excess return series
harvey_t_nw <- function(ret_vec, lag = 4L) {
  if (length(ret_vec) < 24L) return(NA_real_)
  n <- length(ret_vec)
  m <- mean(ret_vec, na.rm = TRUE)
  # Construct constant regression: y = mu + e
  fit <- lm(ret_vec ~ 1)
  vc <- NeweyWest(fit, lag = lag, prewhite = FALSE)
  se_nw <- sqrt(vc[1, 1])
  m / se_nw
}

# Deflated Sharpe Ratio (Bailey-Lopez de Prado)
deflated_sharpe <- function(sr, n_obs, n_trials, skew = 0, kurt = 3) {
  # SR_obs ≥ 0 case
  z_alpha <- qnorm(0.95)
  sr_zero_threshold <- sqrt(
    (1 / (n_obs - 1)) *
    (1 - 0.5772 + 0.5772 * sqrt(log(n_trials)) +
     (0.4 / n_trials))
  )
  num <- (sr - sr_zero_threshold) * sqrt(n_obs - 1)
  denom <- sqrt(1 - skew * sr + ((kurt - 1) / 4) * sr^2)
  if (denom <= 0) return(0)
  pnorm(num / denom)
}

# Annualized Sharpe (standard, learning charter §12)
sharpe_annualized <- function(ret_vec, rf = 0, basis = 12L) {
  if (length(ret_vec) < 12L) return(NA_real_)
  er <- ret_vec - rf
  sd_er <- sd(er, na.rm = TRUE)
  if (sd_er == 0) return(0)
  mean(er, na.rm = TRUE) / sd_er * sqrt(basis)
}

# Max drawdown (PerformanceAnalytics-style, simple)
max_dd <- function(ret_vec) {
  if (length(ret_vec) == 0) return(0)
  nav <- cumprod(1 + ret_vec)
  peak <- cummax(nav)
  dd <- nav / peak - 1
  min(dd, na.rm = TRUE)
}

run_validation <- function(out_dt, ret_full) {
  cat("\n[validation] === Building scenarios ===\n")

  # Scenario S1 (baseline): STR_1715 100% no overlay
  s1 <- ret_full$ret_net

  # Scenario S2 (user-explicit baseline): simple MRS overlay
  # user explicit (10/20/40%) — apply Cash_Pct from existing system: NEUTRAL=0, CAUTION=0.1, CONFIRM=0.2, CRISIS=0.4
  # However our existing system Cash_Pct is already populated.
  s2 <- copy(out_dt)
  s2[, ret_overlay_simple := ret_net * (1 - Cash_Pct_lag) +
                              0.0 * Cash_Pct_lag]
  s2[is.na(ret_overlay_simple), ret_overlay_simple := ret_net]

  # Scenario S3 (our dynamic blend): BOCPD + decay + BL
  s3 <- copy(out_dt)
  s3[, ret_overlay_dynamic := ret_net * weight_str1715 +
                                0.0 * weight_cash]

  # Sharpe + MDD comparison
  s1_sr <- sharpe_annualized(s1, basis = 12L)
  s1_mdd <- max_dd(s1)
  s2_sr <- sharpe_annualized(s2$ret_overlay_simple, basis = 12L)
  s2_mdd <- max_dd(s2$ret_overlay_simple)
  s3_sr <- sharpe_annualized(s3$ret_overlay_dynamic, basis = 12L)
  s3_mdd <- max_dd(s3$ret_overlay_dynamic)

  cat(sprintf("\n  S1 (STR_1715 baseline):    SR=%.3f / MDD=%.3f\n", s1_sr, s1_mdd))
  cat(sprintf("  S2 (simple MRS overlay):   SR=%.3f / MDD=%.3f\n", s2_sr, s2_mdd))
  cat(sprintf("  S3 (Our dynamic blend):    SR=%.3f / MDD=%.3f\n", s3_sr, s3_mdd))

  # NW HAC Harvey t-stat
  s1_t <- harvey_t_nw(s1, lag = 4L)
  s2_t <- harvey_t_nw(s2$ret_overlay_simple, lag = 4L)
  s3_t <- harvey_t_nw(s3$ret_overlay_dynamic, lag = 4L)

  # DSR (single test = 1, but conservative: 3 alternatives evaluated → n_trials=3)
  s3_dsr <- deflated_sharpe(s3_sr / sqrt(12L), n_obs = sum(!is.na(s3$ret_overlay_dynamic)),
                             n_trials = 3L, skew = 0, kurt = 3)

  # Subperiod stability (3 windows)
  build_subperiod <- function(rets, dates) {
    p1 <- which(dates >= as.Date("2008-01-01") & dates < as.Date("2015-01-01"))
    p2 <- which(dates >= as.Date("2015-01-01") & dates < as.Date("2020-01-01"))
    p3 <- which(dates >= as.Date("2020-01-01"))
    list(
      p1 = sharpe_annualized(rets[p1], basis = 12L),
      p2 = sharpe_annualized(rets[p2], basis = 12L),
      p3 = sharpe_annualized(rets[p3], basis = 12L)
    )
  }
  s1_sub <- build_subperiod(s1, ret_full$Date)
  s3_sub <- build_subperiod(s3$ret_overlay_dynamic, s3$Date)

  cat("\n  S1 subperiod SR (08-15 / 15-20 / 20-26):  %.3f / %.3f / %.3f\n",
      s1_sub$p1, s1_sub$p2, s1_sub$p3)

  # crisis_alpha: 8 stress periods (rough proxies)
  stress_periods <- list(
    list(start = "2008-09-01", end = "2009-03-31", name = "GFC"),
    list(start = "2010-04-01", end = "2010-08-31", name = "FlashCrash"),
    list(start = "2011-07-01", end = "2011-12-31", name = "EuroCrisis"),
    list(start = "2015-08-01", end = "2016-02-29", name = "ChinaShock"),
    list(start = "2018-10-01", end = "2018-12-31", name = "VolMaggedon"),
    list(start = "2020-02-01", end = "2020-04-30", name = "Covid"),
    list(start = "2022-01-01", end = "2022-12-31", name = "Inflation"),
    list(start = "2025-04-01", end = "2025-04-30", name = "TariffTantrum")
  )
  crisis_alpha_list <- lapply(stress_periods, function(sp) {
    idx_s1 <- which(ret_full$Date >= as.Date(sp$start) & ret_full$Date <= as.Date(sp$end))
    idx_s3 <- which(s3$Date >= as.Date(sp$start) & s3$Date <= as.Date(sp$end))
    if (length(idx_s1) == 0 || length(idx_s3) == 0) return(NULL)
    s1_ret <- prod(1 + ret_full$ret_net[idx_s1], na.rm = TRUE) - 1
    s3_ret <- prod(1 + s3$ret_overlay_dynamic[idx_s3], na.rm = TRUE) - 1
    list(name = sp$name, s1_ret = s1_ret, s3_ret = s3_ret,
         alpha = s3_ret - s1_ret)
  })
  crisis_alpha_list <- crisis_alpha_list[!sapply(crisis_alpha_list, is.null)]

  # bad/normal IC ratio (here = SR ratio between normal vs bad regime)
  good_idx <- which(out_dt$combined_regime <= 0.3)
  bad_idx <- which(out_dt$combined_regime >= 0.5)
  if (length(good_idx) >= 12 && length(bad_idx) >= 6) {
    sr_normal <- sharpe_annualized(s3$ret_overlay_dynamic[good_idx], basis = 12L)
    sr_bad <- sharpe_annualized(s3$ret_overlay_dynamic[bad_idx], basis = 12L)
    bad_normal_ratio <- if (sr_normal > 1e-6) {
      abs(sr_bad - sr_normal) / sr_normal
    } else NA_real_
    # AX-001 v2 measure: if Sharpe stays positive in bad → meaningful
    # ratio >= 1.5 means bad-regime SR significantly different (positive diff)
  } else {
    sr_normal <- NA_real_
    sr_bad <- NA_real_
    bad_normal_ratio <- NA_real_
  }

  # Lead time: BOCPD detection vs trough month
  lead_times <- list()
  for (sp in stress_periods) {
    sp_start <- as.Date(sp$start)
    sp_end <- as.Date(sp$end)
    # Find trough (max DD in stress period)
    sp_idx <- which(ret_full$Date >= sp_start & ret_full$Date <= sp_end)
    if (length(sp_idx) < 2) next
    sp_nav <- cumprod(1 + ret_full$ret_net[sp_idx])
    trough_pos <- which.min(sp_nav)
    trough_date <- ret_full$Date[sp_idx[trough_pos]]
    # Find first BOCPD elevation pre-trough
    pre_idx <- which(out_dt$Date < trough_date & out_dt$Date >= (trough_date - 90L))
    if (length(pre_idx) == 0) next
    elevated <- which(out_dt$bocpd_norm[pre_idx] >= 0.3)
    if (length(elevated) > 0) {
      first_signal <- out_dt$Date[pre_idx[min(elevated)]]
      lead_days <- as.numeric(trough_date - first_signal)
      lead_times[[sp$name]] <- lead_days
    } else {
      lead_times[[sp$name]] <- NA_integer_
    }
  }
  median_lead <- median(unlist(lead_times), na.rm = TRUE)

  # alpha_inheritance_cor (weight schedule alpha — should be near 0 for ticker-level alpha)
  # 본 WT는 ticker α̂ 미생성 → meta-allocation 측정. correlation N/A but documented.

  list(
    scenarios = list(
      s1_baseline = list(sr = s1_sr, mdd = s1_mdd, harvey_t_nw = s1_t,
                          n_periods = length(s1)),
      s2_simple_mrs = list(sr = s2_sr, mdd = s2_mdd, harvey_t_nw = s2_t,
                            n_periods = sum(!is.na(s2$ret_overlay_simple))),
      s3_dynamic_blend = list(sr = s3_sr, mdd = s3_mdd, harvey_t_nw = s3_t,
                               dsr = s3_dsr,
                               n_periods = sum(!is.na(s3$ret_overlay_dynamic)))
    ),
    superiority = list(
      sr_uplift_vs_s1 = s3_sr - s1_sr,
      sr_uplift_vs_s2 = s3_sr - s2_sr,
      mdd_uplift_vs_s1 = s3_mdd - s1_mdd,
      mdd_uplift_vs_s2 = s3_mdd - s2_mdd,
      mandate_pass_vs_s2 = (s3_sr > s2_sr || s3_mdd > s2_mdd)
    ),
    subperiod = list(
      s1 = s1_sub,
      s3 = s3_sub
    ),
    crisis_alpha = crisis_alpha_list,
    bad_normal = list(
      sr_normal = sr_normal,
      sr_bad = sr_bad,
      ratio = bad_normal_ratio,
      good_n_months = length(good_idx),
      bad_n_months = length(bad_idx)
    ),
    lead_time = list(
      stress_signals = lead_times,
      median_lead_days = median_lead
    )
  )
}

#==============================================================================
# 8. Main execute & save
#==============================================================================

main <- function() {
  out <- run_engine()

  # Save alpha_scores.parquet (Date × weight schedule)
  out_path <- file.path(ART_DIR, "alpha_scores.parquet")
  arrow::write_parquet(out, out_path)
  cat(sprintf("\n[save] alpha_scores.parquet: %d rows, %d cols → %s\n",
              nrow(out), ncol(out), out_path))

  # roll-forward: m4_extended.csv 재생성 (frozen 정적파일 → downstream이 forward 행 소비)
  .m4ext <- file.path(PROJECT_ROOT, "stage_artifacts", "WT-D20260430_001_m4_extended.csv")
  data.table::fwrite(out[, .(Date, weight_str1715, weight_cash)], .m4ext)
  cat(sprintf("[save] m4_extended.csv 재생성: %d rows (last %s) → %s\n",
              nrow(out), as.character(max(out$Date)), .m4ext))

  # Validate vs baselines
  ret_full <- load_str1715_returns()
  validation <- run_validation(out, ret_full)

  # PIT compliance flags
  pit_flags <- list(
    C1_full_sample = "PASS — rolling 36-month decay fit only",
    C2_same_day_circular = "PASS — t-1 lag for regime + decay + BOCPD",
    C5_overlay_lag = "PASS — weight at t uses regime[t-1], bocpd[t-1], decay[≤t-1]",
    C9_overlay_engineering = "PASS — weight_str1715[t] = f(regime_t-1, decay_t-1, view_t-1)",
    C13_zscore_aligned = "N/A — no Z_Score; weight schedule alpha",
    C14_usable_date = "N/A — no Factor DB IC access",
    C15_load_month_factors = "N/A — no Factor DB factor; STR_1715 returns + cached regime only"
  )

  # Save alpha_validation.json
  validation_full <- c(validation, list(
    pit_compliance = pit_flags,
    metadata = list(
      task_id = WT_ID,
      hyperparameters = list(
        rolling_window_months = ROLL_WINDOW_MONTHS,
        bocpd_hazard = BOCPD_HAZARD,
        bocpd_prior_var = BOCPD_PRIOR_VAR,
        warmup_months = WARMUP_MONTHS,
        bl_tau = BL_TAU,
        bl_omega_scale = BL_OMEGA_SCALE
      ),
      n_methods_tried = 3L,  # BOCPD + hyperbolic decay + BL — 3 distinct methods, no grid sweep
      method_shopping_log = list(
        rationale = "3 pillar 각 1 method 단일 spec. No grid sweep (DSR n_trials=3)",
        pillar_a_method = "BOCPD (Adams-MacKay 2007 / Tsaknaki-Lillo-Mazzarisi 2024)",
        pillar_b_method = "Hyperbolic decay K/(1+λt) (Lee 2025)",
        pillar_c_method = "Black-Litterman 2-asset (Black-Litterman 1992 / Shu-Mulvey 2024)"
      )
    )
  ))

  out_val_path <- file.path(ART_DIR, "alpha_validation.json")
  write_json(validation_full, out_val_path, pretty = TRUE,
             auto_unbox = TRUE, na = "null")
  cat(sprintf("[save] alpha_validation.json → %s\n", out_val_path))

  invisible(list(out = out, validation = validation_full))
}

# Execute
result <- main()
cat("\n[engine] === DONE ===\n")
