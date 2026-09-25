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
# 모델 (Shu, Yu & Mulvey 2024, arXiv 2402.05272 v3 — https://arxiv.org/html/2402.05272v3 원문 검증):
#   K=2(bull/bear). 목적함수  min_{θ,s} Σ_t ½‖x_t − θ_{s_t}‖² + λ Σ_t 𝟙{s_{t-1}≠s_t}.
#   fit = coordinate descent: (M) 상태고정→centroid = within-state mean(k-means M-step)
#                             (S) centroid고정→ DP(Viterbi류, 선형시간)로 상태열 갱신. 10 restart, min obj.
#   feature(3, excess-return 기반): EWM downside deviation(hl10) + EWM Sortino(hl20) + EWM Sortino(hl60).
#   ★ KR 보강(lit §2/§7, Kang-Yoon 2015 Granger): log-VIX(US) 1급 feature 추가(opt-in, regime_daily_v2 VIX_z).
#   feature 표준화 = 훈련 창(refit 일 이하) 통계만.
#
# PIT (C1/C5/C11 — 언어무관 동일) — ★jm_causal v1 (2026-09-24 · 도훈 결정 PIT-C11-JM-C1 "전방 필터로 수리"):
#   구판 결함(C1 · C11 1단계 S3 jm_lookahead_probe): refit 블록 (prev_end, end_i] 의 상태를 **end_i 까지의 창**으로
#     적합한 Viterbi *역추적* 경로·중심점·표준화로 매겼다 → 블록 안 t 의 상태가 t 이후 최대 125거래일 정보를 썼다
#     (2020-03~09 표본 8시점 중 2개 상태 뒤집힘). 역추적은 끝점에서 거꾸로 상태를 정하므로 인과적이지 않다.
#     또 마지막 행 n 에 강제 refit 을 붙여 마지막 블록 전체를 그날의 끝점 정보로 매일 다시 썼다(과거 이력이 매일 바뀜).
#   수리(원문 절차 그대로):
#     (1) 모수 Θ·bear 식별·표준화 μ/σ = refit 일 r_k 이하 창 [r_k−l+1, r_k] 로만 적합 → 블록 (r_k, r_{k+1}] 에 적용.
#         원문 §3.4.1: 모수는 6개월마다 3000일 훈련 창으로 갱신(refit_freq_days=126 · lookback=3000 이 그 값).
#     (2) 블록 안 각 t 의 상태 = 창 [t−l+1, t] 에 (1)의 **고정 모수**로 DP 전방 재귀 → 종점 상태 ŝ_t(역추적 없음).
#         원문 §3.4.2: t 에서 끝나는 3000일 lookback 창에 DP 를 돌려 "마지막 상태"를 그날의 온라인 국면으로 쓴다.
#         → t 의 출력은 t 이하 입력만의 함수(접두 불변 · 미래 섭동 불변 = 08_Tests/regime/test_jm_causal.R).
#     (3) Bear_Prob = 고정 모수 기준 softmax(−loss) — 구판과 같은 정의, 모수만 인과판.
#     (4) 첫 refit(min_warmup) 이하 = 적용할 모수 없음 → 행 없음(구판은 창 내 in-sample 라벨로 채웠다).
#     (5) refit 실패 = 직전 성공 모수 유지(과거 정보라 인과). 구판의 '행 n 강제 refit' 제거.
#   **+1일 지연**(t 신호 → t+1 종가부터 집행 = 원문 §3.1 "t+2 부터 적용" 규약). 소비자는 *_lag 열.
#   입력 VIX_z(regime_daily_v2) = C11 표식 계약 관문(overlay_pit_guard::c11_legacy_gate · 가용일 결합 c11_asof_align).
#     legacy/stale epoch 판이면 중단(fail-closed · 정책 QVEST_C11_LEGACY_REGIME=label 은 진단 전용 — 산출 속성에 표식).
#
# OUTPUT: .cache/regime_jump_daily.parquet
#   cols: Date, Price, Vol_Est, Bear_Prob, JM_State(0=bull/1=bear), Bear_Prob_lag, JM_State_lag,
#         JM_Fit_Date(그 행 상태에 쓴 모수의 refit 일 — 항상 < Date · 인과 표식 열)
#   속성: jm_causal(= JM_CAUSAL_VERSION) · jm_causal_spec · jm_input_c11_status · jm_input_c11_regime_key
#   소비자 판독: jm_causal_status(panel) — "causal" 이 아니면 C1 미해소 판(구판 = legacy_noncausal).
#
# 실측-only. 자체 합성 백테 없음(상태 시계열 산출만; 평가는 essence_score/run_wf_ensemble 경유).
#
# ⚠ 아래 2026-06-05 검증 수치는 **구판(블록 미래참조 · C1 위반) 산출**이다 — 결론 근거로 인용 금지
#   (소비자 C1 표식 = 06_Registry/pit_jm_c1_consumer_notices.json). jm_causal 판으로 재측정 전까지 무효.
#   (구판 기록) churn 33.2%→7.1% · λ 단조 · crisis GFC 100%/COVID 94%/2022 100% · HMM parity 73% · τ=0.57 ·
#   앙상블 OOS SR A/B SJM−EW k3+0.27/k4+0.17/k5+0.03 → SJM_SR_GAIN_NONROBUST.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

.qvest_root <- function() {
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[regime_jump_model] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}

if (!exists("PROJECT_ROOT")) PROJECT_ROOT <- .qvest_root()
if (!exists("CACHE_DIR"))    CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
JM_CACHE <- file.path(CACHE_DIR, "regime_jump_daily.parquet")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a

# 인과 표식 판(버전 문자열 — 수치 결정 아님). 추론 규칙을 바꾸면 올린다 → 옛 판은 stale_version 으로 읽힌다.
JM_CAUSAL_VERSION <- "jm_causal:v1"

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
#    (훈련 = 창 전체 in-sample 이 정당하다: 창은 refit 일 이하 데이터뿐이다. 추론은 §2b 전방 재귀만.)
# ---------------------------------------------------------------------------
# (S-step) DP: centroid Theta(K×p) 고정 → 목적함수 최소 상태열. 선형시간 O(T·K^2). **훈련 전용**(역추적 포함).
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
  # 상태 식별: bear = downside deviation(col1) centroid 큰 상태.
  bear_state <- which.max(best$Theta[, 1])
  list(Theta = best$Theta, states = best$states, bear_state = bear_state, obj = best$obj)
}

# ---------------------------------------------------------------------------
# 2b. ★온라인 추론(원문 §3.4.2) — 고정 모수로 각 t 의 창 [s_t, t] 에 DP 전방 재귀 → 종점 argmin.
#   전방 재귀 V_t(k) = loss_t(k) + min(V_{t-1}(k), min_j V_{t-1}(j) + λ) 는 .jm_dp_path 의 값 재귀와 같다
#   (min_j{V_{t-1}(j) + λ·1[j≠k]} 의 닫힌 꼴). 종점 argmin = 그 창에서 푼 Viterbi 의 마지막 상태.
#   역추적을 하지 않으므로 t 의 상태는 x_{s_t..t} 와 고정 모수만의 함수다. 행 최솟값 차감 = argmin·전이 비교 불변.
#   Z: 표준화 feature(고정 μ/σ), t_rel·s_rel: Z 행 기준 각 t 의 끝·시작 위치. 여러 t 를 끝 정렬로 벡터화한다.
# ---------------------------------------------------------------------------
.jm_row_min <- function(M) { m <- M[, 1]; if (ncol(M) > 1L) for (k in 2:ncol(M)) m <- pmin(m, M[, k]); m }

.jm_online_states <- function(Z, Theta, lambda, t_rel, s_rel) {
  K <- nrow(Theta); nt <- length(t_rel)
  stopifnot(length(s_rel) == nt, all(s_rel >= 1L), all(s_rel <= t_rel), all(t_rel <= nrow(Z)))
  loss <- matrix(0, nrow(Z), K)
  for (k in seq_len(K)) loss[, k] <- 0.5 * rowSums(sweep(Z, 2, Theta[k, ], "-")^2)
  L <- max(t_rel - s_rel + 1L)
  V <- matrix(0, nt, K)                                  # 창 시작 전 = 0 → 첫 단계 V = loss(구 V[1,] 와 같다)
  for (m in seq_len(L)) {
    idx <- t_rel - L + m                                 # 각 t 의 이번 단계 데이터 행(끝 정렬: m = L 에서 idx = t)
    act <- which(idx >= s_rel)
    if (!length(act)) next
    Va <- V[act, , drop = FALSE]
    Vn <- loss[idx[act], , drop = FALSE] + pmin(Va, .jm_row_min(Va) + lambda)
    V[act, ] <- Vn - .jm_row_min(Vn)
  }
  max.col(-V, ties.method = "first")                     # which.min(V[t,]) 와 같은 동률 규칙(첫 상태)
}

# softmax(−loss) over 2 states = plogis(d_bull − d_bear) (구판 exp(−d_b)/(exp(−d_b)+exp(−d_u)) 와 같은 값 · 언더플로 안전)
.jm_bear_prob <- function(Z, Theta, bear) {
  bull <- setdiff(seq_len(nrow(Theta)), bear)[1]
  d_bear <- 0.5 * rowSums(sweep(Z, 2, Theta[bear, ], "-")^2)
  d_bull <- 0.5 * rowSums(sweep(Z, 2, Theta[bull, ], "-")^2)
  stats::plogis(d_bull - d_bear)
}

# ---------------------------------------------------------------------------
# 3. Feature 빌드 (PIT) — KOSPI excess return 기반 + opt-in log-VIX(C11 관문 경유).
# ---------------------------------------------------------------------------
# C11 표식 계약 관문 — overlay_pit_guard.R 를 사적 환경에 적재(전역 오염 없음).
.jm_c11_env <- function() {
  g <- file.path(PROJECT_ROOT, "02_Infrastructure/validation/overlay_pit_guard.R")
  if (!file.exists(g)) stop("[regime_jump_model] overlay_pit_guard.R 부재 — VIX 입력 C11 관문 불가(fail-closed): ", g)
  e <- new.env(parent = globalenv())
  suppressMessages(sys.source(g, envir = e))
  for (fn in c("c11_legacy_gate", "c11_asof_align"))
    if (!exists(fn, envir = e, inherits = FALSE)) stop("[regime_jump_model] overlay_pit_guard.R 에 ", fn, " 없음(fail-closed)")
  e
}

build_jm_features <- function(use_vix = TRUE, c11_policy = NULL) {
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
  c11 <- list(status = "not_used", key = NA_character_)
  if (use_vix) {
    # ★구판은 읽기 실패 시 조용히 VIX_z=0 으로 진행했다(특성 하나가 소리 없이 사라짐) → 이제 중단(fail-closed).
    rd_path <- file.path(CACHE_DIR, "regime_daily_v2.parquet")
    rd <- tryCatch(as.data.table(read_parquet(rd_path)),
                   error = function(e) stop("[regime_jump_model] regime_daily_v2 판독 실패(use_vix=TRUE · fail-closed): ",
                                            conditionMessage(e), call. = FALSE))
    rd[, Date := as.Date(Date)]
    ce <- .jm_c11_env()
    gate <- ce$c11_legacy_gate(rd, "VIX_z_smooth", site = "regime_jump_model::build_jm_features",
                               source_desc = "regime_daily_v2.parquet", policy = c11_policy)
    keys <- if ("c11_regime_key" %in% names(rd)) unique(as.character(rd$c11_regime_key)) else character(0)
    c11 <- list(status = as.character(gate$status), key = if (length(keys)) paste(keys, collapse = ",") else NA_character_)
    if (!isTRUE(gate$legacy)) {
      # 가용일 결합: KR 거래일 d 에 '가용일 ≤ d' 인 최신 행(= 행 d 는 한국 d 15:30 결정 가용분 · 판정서 ② 형태 a).
      al <- ce$c11_asof_align(ft$Date, rd, "VIX_z_smooth")
      ft[, VIX_z := al$value]
    } else {
      # label 정책(진단 전용) — legacy 날짜 결합. 산출 속성 jm_input_c11_status 에 미해소 표식이 남는다.
      ft <- merge(ft, rd[, .(Date, VIX_z = VIX_z_smooth)], by = "Date", all.x = TRUE)
      setorder(ft, Date)
      ft[, VIX_z := nafill(VIX_z, "locf")]              # 직전값 carry (과거값만)
    }
    ft[is.na(VIX_z), VIX_z := 0]                        # VIX 이력 이전 구간 = 0(구판과 같은 규약)
  }
  setorder(ft, Date)
  ft <- ft[is.finite(dd10) & is.finite(sortino20) & is.finite(sortino60)]
  setattr(ft, "jm_c11", c11)
  ft
}

# ---------------------------------------------------------------------------
# 4. Online (walk-forward) inference — 모수 = 블록 시작 전(refit 일 이하) 적합 · 상태 = lookback DP 종점 · +1일 지연.
# ---------------------------------------------------------------------------
compute_jm_daily_signal <- function(lambda = 50, use_vix = TRUE,
                                     min_warmup = 504L, refit_freq_days = 126L,
                                     lookback = 3000L, delay = 1L, write = TRUE,
                                     out_path = JM_CACHE, c11_policy = NULL) {
  cat(sprintf("[regime_jump_model] features 빌드 (use_vix=%s)...\n", use_vix))
  ft <- build_jm_features(use_vix = use_vix, c11_policy = c11_policy)
  c11 <- attr(ft, "jm_c11", exact = TRUE)
  feat_cols <- c("dd10", "sortino20", "sortino60", if (use_vix) "VIX_z")
  X_all <- as.matrix(ft[, ..feat_cols])
  n <- nrow(ft); dates <- ft$Date
  min_warmup <- as.integer(min_warmup); refit_freq_days <- as.integer(refit_freq_days)
  lookback <- as.integer(lookback); delay <- as.integer(delay)
  if (n <= min_warmup) stop(sprintf("[regime_jump_model] 표본 %d ≤ warmup %d — 적용할 모수 없음", n, min_warmup))
  cat(sprintf("[regime_jump_model] %d days (%s~%s), p=%d feat, λ=%g, warmup=%d, refit=%dd, lookback=%d, delay=%d · %s\n",
              n, as.character(min(dates)), as.character(max(dates)), ncol(X_all), lambda, min_warmup,
              refit_freq_days, lookback, delay, JM_CAUSAL_VERSION))

  bear_prob <- rep(NA_real_, n); jm_state <- rep(NA_integer_, n); fit_i <- rep(NA_integer_, n)
  # refit 격자 = 행 index min_warmup + k·refit (구판의 '행 n 강제 refit' 제거 — 마지막 블록도 직전 refit 모수).
  refit_idx <- seq(min_warmup, n, by = refit_freq_days)
  block_end <- c(refit_idx[-1], n)                      # 블록 = (refit_idx[k], block_end[k]]
  par <- NULL; n_fail <- 0L

  for (ri in seq_along(refit_idx)) {
    r_i <- refit_idx[ri]
    win_start <- max(1L, r_i - lookback + 1L)
    Xw_raw <- X_all[win_start:r_i, , drop = FALSE]      # ★모수 창 = refit 일 r_i 이하만(블록 데이터 0행)
    mu <- colMeans(Xw_raw); sdv <- apply(Xw_raw, 2, sd); sdv[!is.finite(sdv) | sdv < 1e-8] <- 1
    Xw <- sweep(sweep(Xw_raw, 2, mu, "-"), 2, sdv, "/")
    fit <- tryCatch(.jm_fit(Xw, K = 2L, lambda = lambda), error = function(e) NULL)
    if (!is.null(fit)) {
      par <- list(Theta = fit$Theta, bear = fit$bear_state, mu = mu, sd = sdv, i = r_i, obj = fit$obj)
    } else {
      n_fail <- n_fail + 1L
      cat(sprintf("  [WARN] refit %s 실패 — %s\n", as.character(dates[r_i]),
                  if (is.null(par)) "직전 모수 없음 → 블록 비움" else sprintf("직전 모수(%s) 유지", as.character(dates[par$i]))))
    }
    if (is.null(par)) next
    t_from <- r_i + 1L; t_to <- block_end[ri]
    if (t_from > t_to) next
    ts <- t_from:t_to
    ss <- pmax(1L, ts - lookback + 1L)                   # 각 t 의 lookback 창 시작(원문 l=3000)
    a  <- min(ss)
    Z  <- sweep(sweep(X_all[a:t_to, , drop = FALSE], 2, par$mu, "-"), 2, par$sd, "/")   # 고정 μ/σ(refit 창 통계)
    st <- .jm_online_states(Z, par$Theta, lambda, t_rel = ts - a + 1L, s_rel = ss - a + 1L)
    jm_state[ts]  <- as.integer(st == par$bear)
    bear_prob[ts] <- .jm_bear_prob(Z[ts - a + 1L, , drop = FALSE], par$Theta, par$bear)
    fit_i[ts]     <- par$i
    if (ri %% 10 == 0 || ri == length(refit_idx))
      cat(sprintf("  refit %d/%d (%s): obj=%.1f  bear_state=%d  block→%s  p_bear_last=%.3f\n",
                  ri, length(refit_idx), as.character(dates[r_i]), par$obj, par$bear,
                  as.character(dates[t_to]), bear_prob[t_to]))
  }

  out <- data.table(Date = dates, Price = ft$Price, Vol_Est = ft$Vol_Est,
                    Bear_Prob = bear_prob, JM_State = jm_state, JM_Fit_Date = dates[fit_i])
  out <- out[!is.na(JM_State)]
  # ★ +1일 지연 (PIT): 신호를 1일 lag 시켜 적용용 컬럼 추가(소비 측은 *_lag 사용).
  setorder(out, Date)
  out[, Bear_Prob_lag := shift(Bear_Prob, delay)]
  out[, JM_State_lag := shift(JM_State, delay)]
  out <- out[!is.na(JM_State_lag)]
  setcolorder(out, c("Date", "Price", "Vol_Est", "Bear_Prob", "JM_State", "Bear_Prob_lag", "JM_State_lag", "JM_Fit_Date"))
  setattr(out, "jm_causal", JM_CAUSAL_VERSION)
  setattr(out, "jm_causal_spec", sprintf(paste0(
    "params(Theta,bear,mu,sd) fit on [r_k-l+1,r_k] applied to (r_k,r_k+1]; state_t = terminal argmin of forward DP on [t-l+1,t] ",
    "with fixed params (no backtracking); lambda=%g l=%d refit=%d warmup=%d delay=%d use_vix=%s; ",
    "Shu-Yu-Mulvey 2024 arXiv:2402.05272v3 s3.4.1-3.4.2; decision PIT-C11-JM-C1"),
    lambda, lookback, refit_freq_days, min_warmup, delay, use_vix))
  setattr(out, "jm_input_c11_status", as.character(c11$status %||% NA_character_))
  setattr(out, "jm_input_c11_regime_key", as.character(c11$key %||% NA_character_))

  # 자체검증(fail-closed): 모든 행의 모수 refit 일 < 행 날짜 · 표식 판독기 = causal. 실패면 캐시를 쓰지 않는다.
  #   ★(2026-09-25 적대 검증 JM N3) C11 미해소 입력(label 정책 = legacy 날짜 결합 VIX)은 판독기가 'c11_unresolved' 로 읽는다 —
  #   진단 계산(write=FALSE)은 허용하되 캐시 기록은 거부한다(미해소 판이 'causal' 표식을 달고 소비자에게 가지 않게).
  ck <- jm_causal_status(out)
  if (!identical(ck, "causal") && !(identical(ck, "c11_unresolved") && !isTRUE(write)))
    stop(sprintf("[regime_jump_model] 인과 자체검증 FAIL(%s) — 캐시 미기록(fail-closed)", ck))

  if (write) {
    ap <- file.path(PROJECT_ROOT, "02_Infrastructure/utils/atomic_parquet.R")
    if (!exists("qvest_atomic_write_parquet", mode = "function")) source(ap)
    qvest_atomic_write_parquet(out, out_path, tag = "regime_jump_model")
    cat(sprintf("[regime_jump_model] saved %d rows → %s (%s)\n", nrow(out), out_path, JM_CAUSAL_VERSION))
  } else cat(sprintf("[regime_jump_model] computed %d rows (write=FALSE, parquet 미저장)\n", nrow(out)))
  cat(sprintf("[regime_jump_model] bear fraction=%.1f%%  latest state=%s (%s) · 모수 refit=%s · refit 실패 %d · C11 입력=%s\n",
              100 * mean(out$JM_State), if (out[.N, JM_State] == 1) "BEAR" else "BULL", out[.N, Date],
              as.character(out[.N, JM_Fit_Date]), n_fail, attr(out, "jm_input_c11_status")))
  invisible(out)
}

# ---------------------------------------------------------------------------
# 5. 소비자 판독기 — 패널이 인과판(jm_causal)인지. "causal" 외 = C1 미해소 판(결론 근거 인용 금지).
#   legacy_noncausal = 표식 없음(구판 블록 미래참조) · stale_version = 다른 판 · malformed = JM_Fit_Date 없음 ·
#   violated = 모수 refit 일 ≥ 행 날짜(또는 NA) 행 존재.
#   c11_unresolved = VIX 입력 C11 상태가 avail_annotated·not_used 가 아님(label 정책 진단판 — 2026-09-25 N3).
# ---------------------------------------------------------------------------
jm_causal_status <- function(panel) {
  v <- attr(panel, "jm_causal", exact = TRUE)
  if (is.null(v)) return("legacy_noncausal")
  if (!identical(as.character(v), JM_CAUSAL_VERSION)) return("stale_version")
  if (!all(c("Date", "JM_Fit_Date") %in% names(panel))) return("malformed")
  fd <- as.Date(panel[["JM_Fit_Date"]]); d <- as.Date(panel[["Date"]])
  if (!length(d) || anyNA(fd) || anyNA(d) || any(fd >= d)) return("violated")
  cs <- attr(panel, "jm_input_c11_status", exact = TRUE)                 # (N3) VIX 입력이 C11 미해소(label 정책)면 인과판이 아니다
  if (!is.null(cs) && !(as.character(cs)[1] %in% c("avail_annotated", "not_used"))) return("c11_unresolved")
  "causal"
}

refit_jm_daily <- function(lambda = 50, use_vix = TRUE)
  tryCatch(compute_jm_daily_signal(lambda = lambda, use_vix = use_vix),
           error = function(e) { cat(sprintf("[regime_jump_model] ERR: %s\n", e$message)); invisible(NULL) })

cat("[regime_jump_model.R] Loaded (", JM_CAUSAL_VERSION, "). Functions:\n", sep = "")
cat("  compute_jm_daily_signal(lambda=50, use_vix=TRUE, min_warmup=504, refit_freq_days=126, lookback=3000, delay=1)\n")
cat("  refit_jm_daily(lambda, use_vix)  # safe wrapper\n")
cat("  jm_causal_status(panel)          # 소비자 판독 — 'causal' 이 아니면 C1 미해소 판\n")
