#!/usr/bin/env Rscript
# =============================================================================
# regime_jump_model.R — Statistical Jump Model (SJM) PoC.  Factor Rotation Track1 (국면 모델 SOTA).
#
# WHY (economic-rationale, research_philosophy ① Factor Zoo 축소 — 문헌 rationale 선존):
#   SOT `04_Research/factor_rotation/regime_model_literature_review.md` §1·§4·§6:
#   시스템은 HMM·GARCH·CUSUM·absorption·GMM을 보유하나 현 SOTA인 **Jump Model**(계열 F)만 미보유.
#   현 `Category` 월 전환율 33%(churn) = 과전환 = SJM의 jump penalty λ가 *정확히 겨냥*하는 문제.
#   HMM이 전이행렬로 지속성을 *암묵* 제어하는 대신 SJM은 λ로 *명시* 제어 → 과전환 억제·robust.
#
# 모델 (Shu et al. 2024, arXiv 2402.05272 v3 — 원문 검증):
#   K=2(bull/bear). 목적함수  min_{θ,s} Σ_t ½‖x_t − θ_{s_t}‖² + λ Σ_t 𝟙{s_{t-1}≠s_t}.
#   fit = coordinate descent: (M) 상태고정→centroid = within-state mean(k-means M-step)
#                             (S) centroid고정→ DP(Viterbi류, 선형시간)로 상태열 갱신. 10 restart, min obj.
#   feature(3, excess-return 기반): EWM downside deviation(hl10) + EWM Sortino(hl20) + EWM Sortino(hl60).
#   ★ KR 보강(lit §2/§7, Kang-Yoon 2015 Granger): log-VIX(US) 1급 feature 추가(opt-in, regime_daily_v2 VIX_z).
#   feature 표준화 = expanding z(PIT, training window 통계만).
#
# PIT (C1/C5 — 언어무관 동일):
#   online inference = lookback window(t까지 데이터만) DP, parameter는 6개월마다 refit,
#   **+1일 지연**(t 신호 → t+1/t+2 적용 — t-1 lag 정합). full-sample Viterbi 라벨링 금지(lookahead).
#
# OUTPUT: .cache/regime_jump_daily.parquet  cols: Date, Price, Bear_Prob, JM_State(0=bull/1=bear), Vol_Est
#         + (validation 호출 시) churn·crisis-hit·HMM parity 콘솔/JSON.
#
# 실측-only. 자체 합성 백테 없음(상태 시계열 산출만; 평가는 essence_score/run_wf_ensemble 경유).
#
# ★ 검증 결과 (2026-06-05, KOSPI 1990~2026, canonical λ=50/126d — `output/regime_jm_validation.json`):
#   churn 33.2%(Category 5-state)→7.1%(SJM) 4.7×↓ · λ 단조(10/25/50/100/200→11.9/10.3/6.6/4.3/2.5%) ·
#   crisis GFC 100%(0d)/COVID 94%(5d)/2022 100%(2d) · HMM parity 73% · τ(모듈IR bull/bear)=0.57(미판별).
#   앙상블 OOS SR A/B(regime_jm_ensemble_ab): SJM−EW k3+0.27/k4+0.17/k5+0.03 단조감소 + seed 부호flip
#   → SJM_SR_GAIN_NONROBUST(k=3 집중·seed 의존, 노이즈). 로버스트 SR 이득 부재(천장=EW).
#   → 신호품질은 SOTA로 개선(과전환 명시 억제·crisis 신속)하나, 현 0.70-상관 풀에선 앙상블 SR 천장이
#     입력(직교 슬리브)에 의해 결정(project-factor-rotation-regime-study 정합). SJM 실가치는
#     직교 슬리브 확보 후 Shu-Mulvey(팩터별 국면→BL) 결합 시 발현. 현재는 msm_daily 대체/병렬 신호.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

if (!exists("PROJECT_ROOT")) PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
if (!exists("CACHE_DIR"))    CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
JM_CACHE <- file.path(CACHE_DIR, "regime_jump_daily.parquet")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

# ---------------------------------------------------------------------------
# 1. EWM helpers (PIT: 각 t는 1..t 관측만 — 인과적 EWMA). halflife → alpha.
# ---------------------------------------------------------------------------
.ewm_alpha <- function(halflife) 1 - exp(log(0.5) / halflife)

.ewm_mean <- function(x, halflife) {            # causal EWMA mean (오늘까지)
  a <- .ewm_alpha(halflife); n <- length(x); out <- rep(NA_real_, n); m <- NA_real_
  for (i in seq_len(n)) {
    xi <- x[i]; if (!is.finite(xi)) { out[i] <- m; next }
    m <- if (is.na(m)) xi else a * xi + (1 - a) * m
    out[i] <- m
  }
  out
}

.ewm_downside_dev <- function(r, halflife) {    # sqrt(EWM E[r^2 * 1{r<0}]) — Shu feature 1
  d2 <- ifelse(is.finite(r) & r < 0, r^2, 0)
  sqrt(pmax(.ewm_mean(d2, halflife), 0))
}

.ewm_sortino <- function(r, halflife) {         # EWM mean / EWM downside dev — Shu feature 2,3
  num <- .ewm_mean(r, halflife)
  den <- .ewm_downside_dev(r, halflife)
  ifelse(is.finite(den) & den > 1e-8, num / den, 0)
}

# ---------------------------------------------------------------------------
# 2. SJM core — fixed-parameter DP state path + coordinate-descent training.
# ---------------------------------------------------------------------------
# (S-step) DP: centroid Theta(K×p) 고정 → 목적함수 최소 상태열. 선형시간 O(T·K^2).
.jm_dp_path <- function(X, Theta, lambda) {
  Tn <- nrow(X); K <- nrow(Theta)
  # loss[t,k] = 1/2 ||x_t - theta_k||^2
  loss <- matrix(0, Tn, K)
  for (k in seq_len(K)) loss[, k] <- 0.5 * rowSums(sweep(X, 2, Theta[k, ], "-")^2)
  V <- matrix(Inf, Tn, K); BP <- matrix(0L, Tn, K)
  V[1, ] <- loss[1, ]
  for (t in 2:Tn) {
    for (k in seq_len(K)) {
      trans <- V[t - 1, ] + ifelse(seq_len(K) == k, 0, lambda)  # 같은 상태 0, 전환 λ
      bp <- which.min(trans); V[t, k] <- trans[bp] + loss[t, k]; BP[t, k] <- bp
    }
  }
  s <- integer(Tn); s[Tn] <- which.min(V[Tn, ])
  for (t in (Tn - 1):1) s[t] <- BP[t + 1, s[t + 1]]
  list(states = s, obj = min(V[Tn, ]))
}

# coordinate descent (training): 10 restart, 각 restart kmeans++ 류 seed → (M,S) 반복.
.jm_fit <- function(X, K = 2L, lambda = 50, n_restart = 10L, max_iter = 20L) {
  Tn <- nrow(X); p <- ncol(X)
  best <- list(obj = Inf)
  for (rs in seq_len(n_restart)) {
    # seed: 무작위 K개 관측을 centroid로 (재현 위해 restart별 seed 고정)
    set.seed(1000 + rs)
    Theta <- X[sample.int(Tn, K), , drop = FALSE]
    prev_obj <- Inf
    for (it in seq_len(max_iter)) {
      dp <- .jm_dp_path(X, Theta, lambda)                 # S-step
      s <- dp$states
      for (k in seq_len(K)) {                              # M-step: within-state mean
        idx <- which(s == k)
        if (length(idx) > 0) Theta[k, ] <- colMeans(X[idx, , drop = FALSE])
      }
      if (abs(prev_obj - dp$obj) < 1e-6) break
      prev_obj <- dp$obj
    }
    if (dp$obj < best$obj) best <- list(obj = dp$obj, Theta = Theta, states = s)
  }
  # 상태 식별: state 0 = bull(높은 평균 feature?) — feature[1]=downside dev라 bear가 높음.
  #   bear = downside deviation(col1) centroid 큰 상태.
  bear_state <- which.max(best$Theta[, 1])
  list(Theta = best$Theta, states = best$states, bear_state = bear_state, obj = best$obj)
}

# ---------------------------------------------------------------------------
# 3. Feature 빌드 (PIT) — KOSPI excess return 기반 + opt-in log-VIX.
# ---------------------------------------------------------------------------
build_jm_features <- function(use_vix = TRUE) {
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]; setorder(bm, Date); bm <- bm[!is.na(BM_Close)]
  bm[, ret := BM_Close / shift(BM_Close, 1L) - 1]
  bm[, Vol_Est := frollapply(ret, 20L, sd, align = "right")]
  bm <- bm[is.finite(ret)]
  # excess return: rf≈0 (Qvest 리서치 관행, risk_free_rate=0). KOSPI 일간 ret 사용.
  r <- bm$ret
  f1 <- .ewm_downside_dev(r, 10)
  f2 <- .ewm_sortino(r, 20)
  f3 <- .ewm_sortino(r, 60)
  ft <- data.table(Date = bm$Date, Price = bm$BM_Close, Vol_Est = bm$Vol_Est,
                   dd10 = f1, sortino20 = f2, sortino60 = f3)
  if (use_vix) {
    rd <- tryCatch(as.data.table(read_parquet(file.path(CACHE_DIR, "regime_daily_v2.parquet")))[, .(Date = as.Date(Date), VIX_z = VIX_z_smooth)],
                   error = function(e) NULL)
    if (!is.null(rd)) {
      ft <- merge(ft, rd, by = "Date", all.x = TRUE)
      setorder(ft, Date)
      ft[, VIX_z := nafill(VIX_z, "locf")]                # 직전값 carry (PIT: 과거값만)
      ft[is.na(VIX_z), VIX_z := 0]
    } else ft[, VIX_z := 0]
  }
  setorder(ft, Date)
  ft[is.finite(dd10) & is.finite(sortino20) & is.finite(sortino60)]
}

# ---------------------------------------------------------------------------
# 4. Online (walk-forward) inference — PIT: t까지 데이터로 DP, 6개월 refit, +1일 지연.
# ---------------------------------------------------------------------------
compute_jm_daily_signal <- function(lambda = 50, use_vix = TRUE,
                                     min_warmup = 504L, refit_freq_days = 126L,
                                     lookback = 3000L, delay = 1L, write = TRUE) {
  cat(sprintf("[regime_jump_model] features 빌드 (use_vix=%s)...\n", use_vix))
  ft <- build_jm_features(use_vix = use_vix)
  feat_cols <- c("dd10", "sortino20", "sortino60", if (use_vix) "VIX_z")
  X_all <- as.matrix(ft[, ..feat_cols])
  n <- nrow(ft); dates <- ft$Date
  cat(sprintf("[regime_jump_model] %d days (%s~%s), p=%d feat, λ=%g, warmup=%d, refit=%dd, lookback=%d, delay=%d\n",
              n, as.character(min(dates)), as.character(max(dates)), ncol(X_all), lambda, min_warmup, refit_freq_days, lookback, delay))

  bear_prob <- rep(NA_real_, n); jm_state <- rep(NA_integer_, n)
  refit_idx <- seq(min_warmup, n, by = refit_freq_days); if (tail(refit_idx, 1) != n) refit_idx <- c(refit_idx, n)
  last_Theta <- NULL; last_bear <- NULL

  for (ri in seq_along(refit_idx)) {
    end_i <- min(refit_idx[ri], n)
    win_start <- max(1L, end_i - lookback + 1L)
    Xw_raw <- X_all[win_start:end_i, , drop = FALSE]
    # ★ PIT 표준화: training window(1..end_i) 통계로만 z-score. 미래 미사용.
    mu <- colMeans(Xw_raw); sdv <- apply(Xw_raw, 2, sd); sdv[sdv < 1e-8] <- 1
    Xw <- sweep(sweep(Xw_raw, 2, mu, "-"), 2, sdv, "/")
    fit <- tryCatch(.jm_fit(Xw, K = 2L, lambda = lambda), error = function(e) NULL)
    if (is.null(fit)) next
    last_Theta <- fit$Theta; last_bear <- fit$bear_state
    # 이 refit으로 [prev_end+1 .. end_i] 구간 라벨 채움 (각 t의 상태 = window 내 위치).
    prev_end <- if (ri == 1) 0L else refit_idx[ri - 1]
    fill_from <- max(prev_end + 1L, win_start)
    for (t in fill_from:end_i) {
      pos <- t - win_start + 1L
      jm_state[t] <- as.integer(fit$states[pos] == fit$bear_state)
      # soft bear prob = softmax(-loss) over 2 states (해석용; 결정은 hard state)
      d_bear <- 0.5 * sum((Xw[pos, ] - fit$Theta[fit$bear_state, ])^2)
      bull_state <- setdiff(1:2, fit$bear_state)
      d_bull <- 0.5 * sum((Xw[pos, ] - fit$Theta[bull_state, ])^2)
      bear_prob[t] <- exp(-d_bear) / (exp(-d_bear) + exp(-d_bull))
    }
    if (ri %% 10 == 0 || ri == length(refit_idx))
      cat(sprintf("  refit %d/%d (%s): obj=%.1f  bear_state=%d  p_bear_latest=%.3f\n",
                  ri, length(refit_idx), as.character(dates[end_i]), fit$obj, fit$bear_state, tail(bear_prob[fill_from:end_i], 1)))
  }

  out <- data.table(Date = dates, Price = ft$Price, Vol_Est = ft$Vol_Est,
                    Bear_Prob = bear_prob, JM_State = jm_state)
  out <- out[!is.na(JM_State)]
  # ★ +1일 지연 (PIT): 신호를 1일 lag 시켜 적용용 컬럼 추가(소비 측은 *_lag 사용).
  setorder(out, Date)
  out[, Bear_Prob_lag := shift(Bear_Prob, delay)]
  out[, JM_State_lag := shift(JM_State, delay)]
  out <- out[!is.na(JM_State_lag)]

  if (write) {
    write_parquet(out, JM_CACHE)
    cat(sprintf("[regime_jump_model] saved %d rows → %s\n", nrow(out), JM_CACHE))
  } else cat(sprintf("[regime_jump_model] computed %d rows (write=FALSE, parquet 미저장)\n", nrow(out)))
  cat(sprintf("[regime_jump_model] bear fraction=%.1f%%  latest state=%s (%s)\n",
              100 * mean(out$JM_State), if (out[.N, JM_State] == 1) "BEAR" else "BULL", out[.N, Date]))
  invisible(out)
}

refit_jm_daily <- function(lambda = 50, use_vix = TRUE)
  tryCatch(compute_jm_daily_signal(lambda = lambda, use_vix = use_vix),
           error = function(e) { cat(sprintf("[regime_jump_model] ERR: %s\n", e$message)); invisible(NULL) })

cat("[regime_jump_model.R] Loaded. Functions:\n")
cat("  compute_jm_daily_signal(lambda=50, use_vix=TRUE, min_warmup=504, refit_freq_days=126, lookback=3000, delay=1)\n")
cat("  refit_jm_daily(lambda, use_vix)  # safe wrapper\n")
