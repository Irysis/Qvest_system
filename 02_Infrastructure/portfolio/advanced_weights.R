#==============================================================================
# advanced_weights.R — 고급 통계 기반 비중 결정 방법론 (정본)
#
# Tier 1: CVaR, MaxDiv, NCO
# Tier 2: Entropy Pooling(simplified), Factor Risk Parity, Resampled MV, Robust MV
# Tier 3: Kelly, Higher Moment, Omega
#
# Usage:
#   source("02_Infrastructure/portfolio/advanced_weights.R")
#   w <- calc_cvar_weights(tickers, ret_dt)
#
# Dependencies: data.table, quadprog (for QP)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# ─── 의존: normalize_long_only (반복 재분배 **정본**) ─────────────────────────
#   .normalize 의 캡 강제를 여기에 위임한다. 재구현하지 않는다 — 정본이 둘이 되면
#   둘이 갈리고, 그 갈림은 "같은 이름의 규칙이 축마다 다른 것을 계산"으로 나타난다.
#   경로 해석: **코드는 자기 트리에서** 찾는다(sibling). env 루트(QM_ROOT)는 ~/.Renviron 이
#   main 으로 고정하므로 worktree 사본이 main 구판을 소싱하는 침묵 결함이 된다
#   (r-portability ④-b / feedback-code-root-is-not-data-root). 후보마다 marker 로
#   **정체성**을 검사하고(존재 검사 아님), 못 찾으면 조용히 내려앉지 않고 stop 한다.
.ADV_DIR <- local({
  ok <- function(d) is.character(d) && length(d) == 1L && !is.na(d) && nzchar(d) &&
    file.exists(file.path(d, "strategy_tilt_weights.R"))
  # ① self: source() 는 프레임에 ofile, sys.source() 는 file 을 남긴다. 중첩 source 시
  #    ofile 이 바깥 스크립트를 가리키는 기지 트랩은 위 marker 검사가 걸러낸다
  #    (sibling 이 없는 디렉터리는 기각되고 다음 tier 로 낙하).
  cand <- NA_character_
  for (.i in rev(seq_len(sys.nframe()))) {
    fr <- sys.frame(.i)
    for (.v in c("ofile", "file")) {
      p <- tryCatch(get(.v, envir = fr, inherits = FALSE), error = function(e) NULL)
      if (is.character(p) && length(p) == 1L && !is.na(p) && nzchar(p)) {
        d <- tryCatch(dirname(p), error = function(e) NA_character_)
        if (ok(d)) { cand <- d; break }
      }
    }
    if (!is.na(cand)) break
  }
  if (!is.na(cand)) cand else {
    # ② env·cwd 루트(데이터 루트 계열) — self 가 안 잡힐 때만.
    hit <- NA_character_
    for (r in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
      if (!nzchar(r)) next
      d <- file.path(gsub("\\\\", "/", r), "02_Infrastructure", "portfolio")
      if (ok(d)) { hit <- d; break }
    }
    if (is.na(hit))
      stop("[advanced_weights] strategy_tilt_weights.R 미발견 — normalize_long_only 없이 로드하지 않는다")
    hit
  }
})
if (!exists("normalize_long_only", mode = "function"))
  source(file.path(.ADV_DIR, "strategy_tilt_weights.R"), local = environment())

# ─── Helper: build return matrix ─────────────────────────────────────────────
.adv_ret_matrix <- function(tickers, ret_dt, n_days = 120) {
  recent <- tail(sort(unique(ret_dt$Date)), n_days)
  sub <- ret_dt[Date %in% recent & Ticker %in% tickers, .(Date, Ticker, Ret)]
  wide <- dcast(sub, Date ~ Ticker, value.var = "Ret")
  mat <- as.matrix(wide[, -1, with = FALSE])
  mat[is.na(mat)] <- 0
  colnames(mat) <- names(wide)[-1]
  mat
}

# ─── Helper: safe normalize ──────────────────────────────────────────────────
# ★캡을 합-정규화보다 **먼저** 걸면 신호가 통째로 사라진다 (2026-08-24 수리).
#   `calc_*` 들은 정규화되지 않은 **원 선호 벡터**를 넘긴다(factor_rp = 1/vol,
#   maxdiv = Σ⁻¹σ, robust_mv = Σ⁻¹1, higher_moment = (1/vol)(1+λ·skew) …).
#   원 스케일이 max_w(0.15)를 넘으면 `pmin(w, max_w)` 가 **전 원소를 같은 값으로**
#   만들고, 뒤이은 합-정규화가 그것을 **정확히 EW** 로 만든다. 예외도 경고도 없다.
#   실측(2026-08-24, weight_catalog.R::.wc_fixture 25종·260일):
#     · 정확히 EW 6종 — factor_rp · maxdiv · cvar · omega · robust_mv · higher_moment
#       (factor_rp 는 vol 이 3.4배 차이인데 산출이 0.04 균일 = 신호 완전 소멸)
#     · 부분 소멸 1종 — kelly: 25종 중 13종이 캡에 걸려 **선택만 남고 사이징이 전멸**
#       (13종 균등 1/13 + 12종 0). EW 와는 달라 보이므로 probe 의 EW-구별 축을 통과한다.
#   ★같은 병의 **세 번째** 발생이다. 이미 두 번 같은 사유로 수리됐고 이 파일만 남았다:
#     · methods/method_registry.R:73-78 (wrap_adapter) — minvar 빌트인이 정확히 1/25
#     · ops/auto_sigma_weighting_ab.R::.minvar_w/.mvo_w (2026-08-08) — minvar/MVO 3종이
#       "06-18 이래 EW 를 이름만 바꿔 재고 있었다"
#   수리: **합-정규화를 먼저**, 캡은 normalize_long_only(초과분 반복 재분배)에 위임.
#   순서를 되돌리면 세 지점이 동시에 되살아난다 — 08_Tests/contracts/test_weight_catalog.R
#   의 위반 주입 축(원 선호를 전부 캡 위로 밀어 넣기)이 그 되돌림을 잡는다.
.normalize <- function(w, max_w = 0.15) {
  w[is.na(w) | w < 0] <- 0
  if (sum(w) < 1e-10) return(rep(1/length(w), length(w)))
  nm <- names(w)
  w <- w / sum(w)                                    # ← 캡보다 **먼저**
  out <- normalize_long_only(w, lb = 0, ub = max_w, target_sum = 1)
  names(out) <- nm
  out
}

#==============================================================================
# TIER 1
#==============================================================================

#' CVaR Optimization — minimize Conditional Value-at-Risk
#' Rockafellar & Uryasev (2000)
#' Approximation: weight by inverse of historical ES contribution
calc_cvar_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                               alpha = 0.05) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  # Per-stock CVaR (Expected Shortfall at alpha)
  es <- sapply(valid, function(tk) {
    r <- mat[, tk]
    r <- r[!is.na(r)]
    if (length(r) < 10) return(Inf)
    cutoff <- quantile(r, alpha)
    -mean(r[r <= cutoff])  # positive = worse
  })

  es[is.infinite(es)] <- max(es[is.finite(es)]) * 2
  es[es <= 0] <- min(es[es > 0]) / 2

  # Inverse CVaR weighting
  w <- 1 / es
  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- w
  .normalize(w_full, max_w)
}


#' Maximum Diversification — maximize Diversification Ratio
#' Choueifaty & Coignard (2008)
#' DR = w'σ / sqrt(w'Σw), iterative optimization
calc_maxdiv_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                                 max_iter = 50) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  sigma_vec <- apply(mat_v, 2, sd, na.rm = TRUE)
  sigma_vec[sigma_vec < 1e-8] <- 1e-8
  cov_mat <- cov(mat_v, use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0

  # Iterative: w ∝ Σ^(-1) σ (analytic solution under long-only)
  tryCatch({
    cov_inv <- solve(cov_mat + diag(1e-6, ncol(cov_mat)))
    w_raw <- cov_inv %*% sigma_vec
    w_raw <- pmax(as.numeric(w_raw), 0)
  }, error = function(e) {
    w_raw <<- sigma_vec  # fallback to inverse-vol
  })

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- w_raw
  .normalize(w_full, max_w)
}


#' NCO — Nested Clustering Optimization
#' Lopez de Prado (2019)
#' Cluster via hclust → optimize within each cluster → HRP across clusters
calc_nco_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                              n_clusters = NULL) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 3L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  cor_mat <- cor(mat_v, use = "pairwise.complete.obs")
  cor_mat[is.na(cor_mat)] <- 0; diag(cor_mat) <- 1
  cov_mat <- cov(mat_v, use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0

  # Cluster
  dist_mat <- sqrt(0.5 * (1 - pmin(pmax(cor_mat, -1), 1)))
  diag(dist_mat) <- 0
  hc <- tryCatch(hclust(as.dist(dist_mat), method = "ward.D2"), error = function(e) NULL)
  if (is.null(hc)) return(.normalize(rep(1, n), max_w))

  if (is.null(n_clusters)) n_clusters <- max(2, min(floor(length(valid) / 3), 5))
  clusters <- cutree(hc, k = n_clusters)

  # Within-cluster: MinVar
  cluster_weights <- list()
  cluster_vars <- numeric(n_clusters)

  for (k in seq_len(n_clusters)) {
    idx <- which(clusters == k)
    if (length(idx) == 1) {
      cluster_weights[[k]] <- setNames(1.0, valid[idx])
      cluster_vars[k] <- cov_mat[idx, idx]
    } else {
      sub_cov <- cov_mat[idx, idx, drop = FALSE]
      # Simple inverse-variance within cluster
      sub_var <- pmax(diag(sub_cov), 1e-8)
      w_sub <- 1 / sub_var
      w_sub <- w_sub / sum(w_sub)
      cluster_weights[[k]] <- setNames(w_sub, valid[idx])
      cluster_vars[k] <- as.numeric(t(w_sub) %*% sub_cov %*% w_sub)
    }
  }

  # Across clusters: inverse variance
  cluster_vars[cluster_vars < 1e-10] <- 1e-10
  w_clusters <- 1 / cluster_vars
  w_clusters <- w_clusters / sum(w_clusters)

  # Combine
  w_final <- rep(0, length(valid)); names(w_final) <- valid
  for (k in seq_len(n_clusters)) {
    cw <- cluster_weights[[k]]
    for (nm in names(cw)) {
      w_final[nm] <- cw[nm] * w_clusters[k]
    }
  }

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- w_final[valid]
  .normalize(w_full, max_w)
}


#==============================================================================
# TIER 2
#==============================================================================

#' Resampled Efficient Frontier — Michaud (1998)
#' Monte Carlo: sample from (μ, Σ), optimize each, average weights
calc_resampled_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                                    n_sim = 100) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  mu_hat <- colMeans(mat_v, na.rm = TRUE)
  cov_hat <- cov(mat_v, use = "pairwise.complete.obs")
  cov_hat[is.na(cov_hat)] <- 0

  nv <- length(valid)
  T_obs <- nrow(mat_v)
  w_sum <- rep(0, nv)

  for (s in seq_len(n_sim)) {
    # Resample returns
    idx <- sample(T_obs, T_obs, replace = TRUE)
    mu_s <- colMeans(mat_v[idx, , drop = FALSE], na.rm = TRUE)
    cov_s <- cov(mat_v[idx, , drop = FALSE], use = "pairwise.complete.obs")
    cov_s[is.na(cov_s)] <- 0

    # MinVar on resampled
    cov_reg <- cov_s + diag(1e-6, nv)
    w_s <- tryCatch({
      ci <- solve(cov_reg)
      w <- ci %*% rep(1, nv)
      pmax(as.numeric(w), 0)
    }, error = function(e) rep(1/nv, nv))
    w_s <- w_s / sum(w_s)
    w_sum <- w_sum + w_s
  }

  w_avg <- w_sum / n_sim
  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- w_avg
  .normalize(w_full, max_w)
}


#' Robust Minimum Variance — uncertainty-aware optimization
#' Goldfarb & Iyengar (2003)
#' Shrink covariance more aggressively + eigenvalue floor
calc_robust_mv_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                                     shrinkage = 0.5) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  cov_hat <- cov(mat_v, use = "pairwise.complete.obs")
  cov_hat[is.na(cov_hat)] <- 0
  nv <- length(valid)

  # Aggressive shrinkage toward identity
  target <- diag(mean(diag(cov_hat)), nv)
  cov_robust <- (1 - shrinkage) * cov_hat + shrinkage * target

  # Eigenvalue floor (RMT-inspired)
  eig <- eigen(cov_robust, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-6)
  cov_robust <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)

  # MinVar on robust covariance
  tryCatch({
    ci <- solve(cov_robust)
    w_raw <- ci %*% rep(1, nv)
    w_raw <- pmax(as.numeric(w_raw), 0)
  }, error = function(e) {
    w_raw <<- rep(1/nv, nv)
  })

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- w_raw
  .normalize(w_full, max_w)
}


#' Factor Risk Parity — equal risk contribution from each factor group
#' Roncalli (2012)
#' Simplified: group stocks by sector, ERC within, ERC across
calc_factor_rp_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15) {
  # Simplified: use stock-level inverse vol (factor decomposition requires loadings)
  # True Factor RP needs factor model — here we approximate with sector-neutral RP
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  vol <- apply(mat_v, 2, sd, na.rm = TRUE)
  vol[vol < 1e-8] <- 1e-8

  # Risk Parity: w_i ∝ 1/vol_i (simplified ERC)
  # True ERC iterates, but for N=20 inverse-vol is close enough
  w_raw <- 1 / vol

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- w_raw
  .normalize(w_full, max_w)
}


#' Entropy Pooling (Simplified) — Meucci (2008)
#' Blend prior (EW) with views (momentum signal) via minimum relative entropy
calc_entropy_weights <- function(tickers, scores, ret_dt, n_days = 120,
                                  max_w = 0.15, view_confidence = 0.3) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))

  # Prior: equal weight
  p_prior <- rep(1/n, n)

  # View: score-proportional (higher score = higher expected return)
  sc <- if (is.null(names(scores))) scores[seq_len(n)] else scores[tickers]
  sc[is.na(sc)] <- 0
  sc <- sc - min(sc) + 0.01
  p_view <- as.numeric(sc / sum(sc))

  # Entropy pooling: blend prior and view
  # Minimizes KL(p || p_prior) subject to E[p] matching view direction
  # Simplified: geometric interpolation
  log_p <- (1 - view_confidence) * log(p_prior) + view_confidence * log(pmax(p_view, 1e-10))
  w <- exp(log_p)

  .normalize(w, max_w)
}


#==============================================================================
# TIER 3
#==============================================================================

#' Kelly Criterion — growth-rate optimal weights
#' Kelly (1956), fractional Kelly for practical use
calc_kelly_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                                fraction = 0.25) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  mu <- colMeans(mat_v, na.rm = TRUE)
  cov_mat <- cov(mat_v, use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0

  # Full Kelly: w* = Σ^(-1) μ
  tryCatch({
    cov_reg <- cov_mat + diag(1e-6, length(valid))
    w_kelly <- solve(cov_reg) %*% mu
    w_kelly <- as.numeric(w_kelly) * fraction  # fractional Kelly
    w_kelly <- pmax(w_kelly, 0)  # long-only
  }, error = function(e) {
    w_kelly <<- rep(1/length(valid), length(valid))
  })

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- w_kelly
  .normalize(w_full, max_w)
}


#' Higher Moment Optimization — skewness-aware weighting
#' Jondeau & Rockinger (2006)
#' Penalize negative skewness, reward positive
calc_higher_moment_weights <- function(tickers, ret_dt, n_days = 120,
                                        max_w = 0.15, skew_penalty = 0.5) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  vol <- apply(mat_v, 2, sd, na.rm = TRUE)
  vol[vol < 1e-8] <- 1e-8
  skew <- apply(mat_v, 2, function(x) {
    x <- x[!is.na(x)]
    if (length(x) < 10) return(0)
    m3 <- mean((x - mean(x))^3) / sd(x)^3
    m3
  })

  # Score: inverse vol + skewness bonus
  # Higher skewness = better (right tail heavier)
  score <- (1 / vol) * (1 + skew_penalty * skew)
  score[score <= 0] <- min(score[score > 0]) / 2

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- score
  .normalize(w_full, max_w)
}


#' Omega Ratio Optimization — maximize gain/loss ratio
#' Keating & Shadwick (2002)
#' w ∝ Omega_i = E[max(R-L,0)] / E[max(L-R,0)]
calc_omega_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                                threshold = 0) {
  n <- length(tickers)
  if (n < 2L) return(rep(1, n))
  mat <- .adv_ret_matrix(tickers, ret_dt, n_days)
  valid <- colnames(mat)[colnames(mat) %in% tickers]
  if (length(valid) < 2L) return(.normalize(rep(1, n), max_w))

  mat_v <- mat[, valid, drop = FALSE]
  omega <- apply(mat_v, 2, function(r) {
    r <- r[!is.na(r)]
    gain <- mean(pmax(r - threshold, 0))
    loss <- mean(pmax(threshold - r, 0))
    if (loss < 1e-10) return(100)
    gain / loss
  })

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- omega
  .normalize(w_full, max_w)
}



#==============================================================================
# SCORE TILT VARIANTS — S5 Mutation Lab (Scout Design 2026-04-08)
# 설계: s5_score_tilt_variants.json (V1/V2/V3/V4/V9/V10)
# PIT: Score_{t-1}, Regime_{t-1}, IC expanding window. C1+C2+C5 준수.
#==============================================================================

# ─── Helper: MRS -> Regime Layer (1=Normal, 2=Caution, 3=Crisis) ─────────────
# Regime Engine v7.1은 MRS 0~100 연속 스코어를 출력.
# Layer 매핑: MRS < 20 → Layer1(Normal), 20~50 → Layer2(Caution), >50 → Layer3(Crisis)
# 근거: exposure ramp (10~60 구간)에서 MRS>50이면 exposure<0.2 → Crisis 판단
.mrs_to_layer <- function(mrs) {
  ifelse(mrs < 20, 1L,
    ifelse(mrs <= 50, 2L, 3L))
}


#' V1: Regime-Conditional Alpha (Ang & Bekaert 2002, Guidolin & Timmermann 2007)
#'
#' alpha_t = f(Layer_{t-1}): Layer1 -> 0.5, Layer2 -> 0.2, Layer3 -> 0.0
#' HRP base + dynamically scaled score tilt based on Regime Engine v7.1 layer.
#' PIT: regime_dt already t-1 lagged from build_daily_regime(). No extra shift needed.
#'
#' @param tickers   character vector of selected tickers
#' @param scores    named numeric vector (Score per ticker)
#' @param ret_dt    data.table(Date, Ticker, Ret) for HRP covariance
#' @param regime_mrs  scalar: current MRS value (t-1 lagged, from REGIME[Date == exec_date])
#' @param n_days    HRP lookback (default 60)
#' @param max_w     max single-stock weight (default 0.15)
#' @param cov_method  "gerber_rmt" | "sample" | "ledoit_wolf"
#' @param alpha_map  c(normal, caution, crisis) alpha values (default c(0.5, 0.2, 0.0))
calc_regime_tilt_weights <- function(tickers, scores, ret_dt,
                                      regime_mrs = 0,
                                      n_days = 60, max_w = 0.15,
                                      cov_method = "gerber_rmt",
                                      alpha_map = c(0.5, 0.2, 0.0)) {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # Determine regime layer from MRS (already t-1 lagged)
  layer <- .mrs_to_layer(if (is.na(regime_mrs)) 0 else regime_mrs)
  alpha <- alpha_map[layer]

  # Pure HRP if Crisis (alpha = 0)
  if (alpha <= 0) {
    return(tryCatch(
      calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = max_w,
                       cov_method = cov_method),
      error = function(e) ew_fallback
    ))
  }

  # HRP base
  hrp_w <- tryCatch(
    calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     cov_method = cov_method),
    error = function(e) ew_fallback
  )
  if (length(hrp_w) != n) hrp_w <- ew_fallback

  # Score-proportional weights
  sc <- if (is.null(names(scores))) scores[seq_len(min(n, length(scores)))] else scores[tickers]
  sc[is.na(sc)] <- 0
  sc <- sc - min(sc) + 0.01
  sc_w <- as.numeric(sc / sum(sc))

  # Blend: w = (1-alpha)*HRP + alpha*score
  w <- (1 - alpha) * as.numeric(hrp_w) + alpha * sc_w
  w <- pmin(w, max_w)
  w / sum(w)
}


#' V2: Expanding IC Confidence Alpha (Grinold & Kahn 2000, Qian & Hua 2004)
#'
#' alpha_t = clip(IC_expanding / IC_target, 0.1, 0.6)
#' IC_expanding: Spearman(Score_{t-k}, Ret_{t-k+1}) for k=1..t-1
#' PIT: IC 계산에 미래 수익률 사용하지 않음. C1(expanding) + C2(t-1) 준수.
#'
#' @param tickers    character vector
#' @param scores     named numeric vector
#' @param ret_dt     data.table(Date, Ticker, Ret)
#' @param ic_history  numeric vector of past monthly IC values (expanding, already computed)
#' @param IC_target   target IC (default 0.10, ICIR=0.20/sqrt(12) 근사)
#' @param n_days     HRP lookback
#' @param max_w      max weight
#' @param cov_method  covariance method
calc_ic_tilt_weights <- function(tickers, scores, ret_dt,
                                  ic_history = NULL,
                                  IC_target = 0.10,
                                  n_days = 60, max_w = 0.15,
                                  cov_method = "gerber_rmt") {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # Compute alpha from expanding IC history
  # Minimum 12 months → fallback to prior 0.4
  IC_MIN_MONTHS <- 12L
  if (is.null(ic_history) || length(ic_history) < IC_MIN_MONTHS) {
    alpha <- 0.4
  } else {
    ic_mean <- mean(ic_history, na.rm = TRUE)
    alpha <- as.numeric(pmin(pmax(ic_mean / IC_target, 0.1), 0.6))
    if (is.na(alpha)) alpha <- 0.4
  }

  # HRP base
  hrp_w <- tryCatch(
    calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     cov_method = cov_method),
    error = function(e) ew_fallback
  )
  if (length(hrp_w) != n) hrp_w <- ew_fallback

  # Score-proportional
  sc <- if (is.null(names(scores))) scores[seq_len(min(n, length(scores)))] else scores[tickers]
  sc[is.na(sc)] <- 0
  sc <- sc - min(sc) + 0.01
  sc_w <- as.numeric(sc / sum(sc))

  w <- (1 - alpha) * as.numeric(hrp_w) + alpha * sc_w
  w <- pmin(w, max_w)
  w / sum(w)
}


#' V3: Rank Percentile Score Transformation (Blitz & Vliet 2007)
#'
#' rank_score_i = rank(Score_i) / (N+1): uniform spacing in (0,1)
#' Prevents outlier dominance while preserving rank order.
#' PIT: cross-sectional rank transform. 추가 시계열 이슈 없음.
#'
#' @param tickers  character vector
#' @param scores   named numeric vector
#' @param ret_dt   data.table for HRP
#' @param alpha    score tilt proportion (default 0.4)
#' @param n_days   HRP lookback
#' @param max_w    max weight
#' @param cov_method  covariance method
calc_rank_tilt_weights <- function(tickers, scores, ret_dt,
                                    alpha = 0.4,
                                    n_days = 60, max_w = 0.15,
                                    cov_method = "gerber_rmt") {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # HRP base
  hrp_w <- tryCatch(
    calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     cov_method = cov_method),
    error = function(e) ew_fallback
  )
  if (length(hrp_w) != n) hrp_w <- ew_fallback

  # Rank percentile transform: rank/(N+1) → uniform (0,1)
  sc <- if (is.null(names(scores))) scores[seq_len(min(n, length(scores)))] else scores[tickers]
  sc[is.na(sc)] <- 0
  rk <- rank(sc, ties.method = "average")
  sc_rank <- rk / (n + 1)  # range (0, 1), open interval
  sc_w <- as.numeric(sc_rank / sum(sc_rank))

  w <- (1 - alpha) * as.numeric(hrp_w) + alpha * sc_w
  w <- pmin(w, max_w)
  w / sum(w)
}


#' V4: Softmax Temperature Score (Garlappi et al. 2007, Kirby & Ostdiek 2012)
#'
#' softmax_i = exp((Score_i - max(Score)) / tau) / sum(exp(...))
#' tau=1.0 fixed (Score z-score의 자연 척도). Overflow 방지: subtract max.
#' PIT: cross-sectional softmax. 추가 이슈 없음.
#'
#' @param tickers   character vector
#' @param scores    named numeric vector
#' @param ret_dt    data.table for HRP
#' @param alpha     score tilt proportion (default 0.4)
#' @param tau       temperature (default 1.0). 낮을수록 집중, 높을수록 균등.
#' @param n_days    HRP lookback
#' @param max_w     max weight
#' @param cov_method  covariance method
calc_softmax_tilt_weights <- function(tickers, scores, ret_dt,
                                       alpha = 0.4, tau = 1.0,
                                       n_days = 60, max_w = 0.15,
                                       cov_method = "gerber_rmt") {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # HRP base
  hrp_w <- tryCatch(
    calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     cov_method = cov_method),
    error = function(e) ew_fallback
  )
  if (length(hrp_w) != n) hrp_w <- ew_fallback

  # Softmax transform: exp(score/tau) with overflow protection
  sc <- if (is.null(names(scores))) scores[seq_len(min(n, length(scores)))] else scores[tickers]
  sc[is.na(sc)] <- 0
  tau_safe <- max(tau, 0.01)
  sc_shifted <- sc - max(sc)  # subtract max to prevent overflow
  exp_sc <- exp(sc_shifted / tau_safe)
  sc_w <- as.numeric(exp_sc / sum(exp_sc))

  w <- (1 - alpha) * as.numeric(hrp_w) + alpha * sc_w
  w <- pmin(w, max_w)
  w / sum(w)
}


#' V9: Winsorized Z-Score Transformation (Tukey 1962, Green et al. 2017)
#'
#' Cross-sectional winsorize at ±2 sigma before proportional weighting.
#' Gentler than rank transform (V3): preserves more ordinal information.
#' PIT: cross-sectional. 추가 이슈 없음.
#'
#' @param tickers   character vector
#' @param scores    named numeric vector
#' @param ret_dt    data.table for HRP
#' @param alpha     score tilt proportion (default 0.4)
#' @param winsor_sd  winsorization threshold in SDs (default 2.0)
#' @param n_days    HRP lookback
#' @param max_w     max weight
#' @param cov_method  covariance method
calc_winsor_tilt_weights <- function(tickers, scores, ret_dt,
                                      alpha = 0.4, winsor_sd = 2.0,
                                      n_days = 60, max_w = 0.15,
                                      cov_method = "gerber_rmt") {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # HRP base
  hrp_w <- tryCatch(
    calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     cov_method = cov_method),
    error = function(e) ew_fallback
  )
  if (length(hrp_w) != n) hrp_w <- ew_fallback

  # Winsorize: clip to mu ± winsor_sd * sigma (cross-sectional)
  sc <- if (is.null(names(scores))) scores[seq_len(min(n, length(scores)))] else scores[tickers]
  sc[is.na(sc)] <- 0
  mu_sc <- mean(sc, na.rm = TRUE)
  sd_sc  <- sd(sc, na.rm = TRUE)
  if (is.na(sd_sc) || sd_sc < 1e-10) sd_sc <- 1
  sc_winz <- pmin(pmax(sc, mu_sc - winsor_sd * sd_sc), mu_sc + winsor_sd * sd_sc)

  # Shift to positive and proportionalize
  sc_winz <- sc_winz - min(sc_winz) + 0.01
  sc_w <- as.numeric(sc_winz / sum(sc_winz))

  w <- (1 - alpha) * as.numeric(hrp_w) + alpha * sc_w
  w <- pmin(w, max_w)
  w / sum(w)
}


#' V10: Regime Alpha + Softmax Score Synthesis (V1 + V4 결합)
#'
#' Regime에 따라 alpha와 tau를 동시 조절:
#'   Layer1(Normal):  alpha=0.5, tau=0.8  (집중 베팅)
#'   Layer2(Caution): alpha=0.3, tau=1.5  (분산 강화)
#'   Layer3(Crisis):  alpha=0.0           (pure HRP)
#' PIT: Regime_{t-1} (already lagged). Score_{t-1}. C2+C5 준수.
#'
#' @param tickers     character vector
#' @param scores      named numeric vector
#' @param ret_dt      data.table for HRP
#' @param regime_mrs  scalar MRS (t-1 lagged)
#' @param n_days      HRP lookback
#' @param max_w       max weight
#' @param cov_method  covariance method
#' @param regime_params  list with alpha_map and tau_map for each layer
calc_regime_softmax_weights <- function(tickers, scores, ret_dt,
                                         regime_mrs = 0,
                                         n_days = 60, max_w = 0.15,
                                         cov_method = "gerber_rmt",
                                         regime_params = list(
                                           alpha_map = c(0.5, 0.3, 0.0),
                                           tau_map   = c(0.8, 1.5, 1.0)
                                         )) {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # Determine layer
  layer <- .mrs_to_layer(if (is.na(regime_mrs)) 0 else regime_mrs)
  alpha <- regime_params$alpha_map[layer]
  tau   <- regime_params$tau_map[layer]

  # Pure HRP in Crisis
  if (alpha <= 0) {
    return(tryCatch(
      calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = max_w,
                       cov_method = cov_method),
      error = function(e) ew_fallback
    ))
  }

  # HRP base
  hrp_w <- tryCatch(
    calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     cov_method = cov_method),
    error = function(e) ew_fallback
  )
  if (length(hrp_w) != n) hrp_w <- ew_fallback

  # Softmax with regime-determined tau
  sc <- if (is.null(names(scores))) scores[seq_len(min(n, length(scores)))] else scores[tickers]
  sc[is.na(sc)] <- 0
  tau_safe <- max(tau, 0.01)
  sc_shifted <- sc - max(sc)
  exp_sc <- exp(sc_shifted / tau_safe)
  sc_w <- as.numeric(exp_sc / sum(exp_sc))

  w <- (1 - alpha) * as.numeric(hrp_w) + alpha * sc_w
  w <- pmin(w, max_w)
  w / sum(w)
}


#' V8: NCO + Score Tilt Hybrid (Lopez de Prado 2020)
#'
#' NCO(Nested Cluster Optimization) as base weight instead of HRP.
#' w = (1-alpha)*NCO_w + alpha*score_proportional, alpha=0.4
#' NCO: cluster stocks → within-cluster MinVar → HRP across clusters
#' PIT: NCO uses past 60d returns (t-1). Score: t-1 frozen. C2 준수.
#'
#' @param tickers     character vector
#' @param scores      named numeric vector
#' @param ret_dt      data.table(Date, Ticker, Ret)
#' @param alpha       score tilt proportion (default 0.4)
#' @param n_days      NCO lookback (default 60)
#' @param max_w       max weight
#' @param n_clusters  number of clusters (NULL = auto)
calc_nco_score_tilt_weights <- function(tickers, scores, ret_dt,
                                         alpha = 0.4, n_days = 60,
                                         max_w = 0.15, n_clusters = NULL) {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # NCO base weights (from existing calc_nco_weights)
  nco_w <- tryCatch(
    calc_nco_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     n_clusters = n_clusters),
    error = function(e) ew_fallback
  )
  if (length(nco_w) != n) nco_w <- ew_fallback

  # Score-proportional weights
  sc <- if (is.null(names(scores))) scores[seq_len(min(n, length(scores)))] else scores[tickers]
  sc[is.na(sc)] <- 0
  sc <- sc - min(sc) + 0.01
  sc_w <- as.numeric(sc / sum(sc))

  # Blend
  w <- (1 - alpha) * as.numeric(nco_w) + alpha * sc_w
  w <- pmin(w, max_w)
  w / sum(w)
}


cat("[advanced_weights] Loaded. 10 methods: cvar, maxdiv, nco, resampled, robust_mv, factor_rp, entropy, kelly, higher_moment, omega\n")
cat("[advanced_weights] Score Tilt Variants: regime_tilt(V1), ic_tilt(V2), rank_tilt(V3), softmax_tilt(V4), winsor_tilt(V9), regime_softmax(V10), nco_score_tilt(V8)\n")

# ==============================================================================
# Phase 2: Pfaff (2016) Ch.10-12 기반 고급 포트폴리오 최적화
# ==============================================================================
# 패키지 가용성 플래그
.HAS_CCCP  <- requireNamespace("cccp",  quietly = TRUE)
.HAS_RRCOV <- requireNamespace("rrcov", quietly = TRUE)
.HAS_FRAPO <- requireNamespace("FRAPO", quietly = TRUE)

# ── Phase 2 내부 헬퍼 ─────────────────────────────────────────────────────────

# 수익률 행렬 구축 (Phase 2 전용, .adv_ret_matrix와 동일하나 독립 유지)
.p2_ret_matrix <- function(tickers, ret_dt, n_days = 120) {
  recent <- tail(sort(unique(ret_dt$Date)), n_days)
  sub    <- ret_dt[Date %in% recent & Ticker %in% tickers, .(Date, Ticker, Ret)]
  if (nrow(sub) == 0L) return(NULL)
  wide   <- dcast(sub, Date ~ Ticker, value.var = "Ret")
  mat    <- as.matrix(wide[, -1, with = FALSE])
  mat[is.na(mat)] <- 0
  colnames(mat) <- names(wide)[-1]
  # 최소 관측 필터
  good <- colSums(mat != 0) >= 20L
  if (sum(good) < 2L) return(NULL)
  mat[, good, drop = FALSE]
}

# EW 폴백
.p2_ew <- function(tickers, max_w = 0.15) {
  n <- length(tickers)
  w <- rep(1 / n, n); names(w) <- tickers
  .normalize(w, max_w)
}

# ==============================================================================
# 1. CVaR LP 최적화 (Pfaff 2016 Ch.12, Rockafellar-Uryasev 2000)
#
# cccp::nnoc() 기반 LP 직접 구현 (Rglpk/FRAPO 없이):
#   min  nu + 1/((1-alpha)*T) * sum(s_t)
#   s.t. s_t >= 0
#        s_t + R_t'w + nu >= 0  (loss exceedance slack)
#        sum(w) = 1, 0 <= w <= max_w
#
# Variables: [w(p), s(T), nu(1)]
# ==============================================================================
calc_cvar_lp_weights <- function(tickers, ret_dt, alpha = 0.95,
                                  n_days = 120, max_w = 0.15) {
  n <- length(tickers)
  if (n < 2L) return(.p2_ew(tickers, max_w))

  mat <- .p2_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(mat)) return(.p2_ew(tickers, max_w))

  valid <- intersect(tickers, colnames(mat))
  if (length(valid) < 2L) return(.p2_ew(tickers, max_w))
  mat   <- mat[, valid, drop = FALSE]
  T_obs <- nrow(mat); p <- ncol(mat)
  alpha_bar <- 1 - alpha
  N_var <- p + T_obs + 1L

  result <- tryCatch({
    if (!.HAS_CCCP) stop("cccp not available")
    library(cccp, quietly = TRUE)

    # Objective: min [0...0(p), 1/(alpha_bar*T)...(T), 1(nu)]
    c_lp <- as.numeric(c(rep(0, p), rep(1 / (alpha_bar * T_obs), T_obs), 1))

    # Equality: sum(w) = 1
    A_eq <- matrix(0, 1, N_var); A_eq[1, 1:p] <- 1

    # Inequality (nnoc: G x <= h):
    # 1) s_t >= 0:  -I_s <= 0
    G1 <- matrix(0, T_obs, N_var)
    for (t in seq_len(T_obs)) G1[t, p + t] <- -1
    h1 <- rep(0, T_obs)
    # 2) s_t + R_t'w + nu >= 0:  -R_t'w - s_t - nu <= 0
    G2 <- matrix(0, T_obs, N_var)
    for (t in seq_len(T_obs)) {
      G2[t, 1:p]     <- -mat[t, ]
      G2[t, p + t]   <- -1
      G2[t, N_var]   <- -1
    }
    h2 <- rep(0, T_obs)
    # 3) w <= max_w
    G3 <- matrix(0, p, N_var); G3[, 1:p] <- diag(p); h3 <- rep(max_w, p)
    # 4) w >= 0:  -w <= 0
    G4 <- matrix(0, p, N_var); G4[, 1:p] <- -diag(p); h4 <- rep(0, p)

    G_all <- rbind(G1, G2, G3, G4)
    h_all <- as.numeric(c(h1, h2, h3, h4))

    res <- cccp(q     = c_lp,
                A     = A_eq,
                b     = 1,
                cList = list(nnoc(G_all, h_all)),
                optctrl = ctrl(trace = FALSE))

    if (getstatus(res)[[1]] == "optimal") {
      x_opt <- getx(res)
      w_opt <- pmax(as.numeric(x_opt[1:p]), 0)
      if (sum(w_opt) < 1e-10) stop("degenerate solution")
      w_opt / sum(w_opt)
    } else {
      stop(paste("cccp status:", getstatus(res)[[1]]))
    }
  }, error = function(e) {
    cat(sprintf("[cvar_lp] LP failed (%s), falling back to inverse-ES\n", e$message))
    NULL
  })

  # 폴백: 기존 calc_cvar_weights() 방식 (inverse ES)
  if (is.null(result)) {
    es <- sapply(valid, function(tk) {
      r <- mat[, tk, drop = TRUE]
      q <- quantile(r, 1 - alpha)
      tail_r <- r[r <= q]
      if (length(tail_r) == 0) return(Inf)
      -mean(tail_r)
    })
    es[is.infinite(es) | es <= 0] <- max(es[is.finite(es) & es > 0], na.rm = TRUE) * 2
    result <- 1 / es
  }

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- result
  .normalize(w_full, max_w)
}


# ==============================================================================
# 2. CVaR 위험기여도 예산 (Pfaff 2016 Ch.11, Boudt et al.)
#    각 자산의 CVaR 기여가 budget 비율을 충족하도록 최적화
#    budget=NULL → equal CVaR contribution (CVaR Parity)
#    cccp::rp() 기반 (risk parity = equal risk contribution)
# ==============================================================================
calc_cvar_budget_weights <- function(tickers, ret_dt, alpha = 0.95,
                                      n_days = 120, max_w = 0.15,
                                      budget = NULL) {
  n <- length(tickers)
  if (n < 2L) return(.p2_ew(tickers, max_w))

  mat <- .p2_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(mat)) return(.p2_ew(tickers, max_w))

  valid <- intersect(tickers, colnames(mat))
  if (length(valid) < 2L) return(.p2_ew(tickers, max_w))
  mat_v <- mat[, valid, drop = FALSE]
  p     <- ncol(mat_v)

  # budget 기본값: equal contribution
  if (is.null(budget)) {
    mrc_target <- rep(1 / p, p)
  } else {
    mrc_target <- budget[valid]
    if (any(is.na(mrc_target))) mrc_target <- rep(1 / p, p)
    mrc_target <- mrc_target / sum(mrc_target)
  }

  # CVaR 기반 공분산 추정:
  # Modified ES 공분산 (Boudt 2008): cov of tail returns
  T_obs   <- nrow(mat_v)
  alpha_i <- floor((1 - alpha) * T_obs)
  result  <- tryCatch({
    if (!.HAS_CCCP) stop("cccp not available")
    library(cccp, quietly = TRUE)

    # 포트폴리오 CVaR 기여도 ≈ marginal CVaR × weight
    # marginal CVaR_i ≈ E[r_i | portfolio return <= VaR]
    # rp()로 ES covariance 기반 risk parity 근사
    # ES Covariance: tail joint distribution (Rockafellar-Uryasev)
    w0   <- rep(1 / p, p)
    port_r <- as.numeric(mat_v %*% w0)
    var_p  <- quantile(port_r, 1 - alpha)
    tail_idx <- which(port_r <= var_p)
    if (length(tail_idx) < 3) tail_idx <- order(port_r)[1:max(3, alpha_i)]
    tail_cov <- cov(mat_v[tail_idx, , drop = FALSE])
    diag(tail_cov)[diag(tail_cov) <= 0] <- 1e-8

    res <- rp(x0  = w0,
              P   = tail_cov,
              mrc = mrc_target,
              optctrl = ctrl(trace = FALSE))

    if (getstatus(res)[[1]] == "optimal") {
      w_opt <- as.numeric(getx(res))
      w_opt[w_opt < 0] <- 0
      if (sum(w_opt) < 1e-10) stop("degenerate")
      w_opt / sum(w_opt)
    } else stop(paste("rp status:", getstatus(res)[[1]]))
  }, error = function(e) {
    cat(sprintf("[cvar_budget] failed (%s), falling back to inverse-CVaR\n", e$message))
    # 폴백: 각 자산 개별 CVaR의 역수로 budget 비례 가중
    es <- sapply(valid, function(tk) {
      r <- mat_v[, tk]
      q <- quantile(r, 1 - alpha)
      tail_r <- r[r <= q]
      if (length(tail_r) == 0) return(Inf)
      -mean(tail_r)
    })
    es[!is.finite(es) | es <= 0] <- max(es[is.finite(es) & es > 0]) * 2
    (1 / es) * mrc_target / sum((1 / es) * mrc_target)
  })

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- result
  .normalize(w_full, max_w)
}


# ==============================================================================
# 3. CDaR 최적화 (Pfaff 2016 Ch.12, Chekhlov et al. 2005)
#    Conditional Drawdown-at-Risk 최소화
#    FRAPO::PMinCDaR() 불가 시 순수 R LP 근사 구현
#
#    CDaR_alpha = E[DD_t | DD_t >= VaR_DD_alpha]
#    DD_t = max_{s<=t}(W_s) - W_t  (underwater from peak)
#
#    LP 공식화:
#      min  zeta + 1/((1-alpha)*T) * sum(u_t)
#      s.t. u_t >= D_t(w) - zeta  (u_t >= 0)
#           D_t(w) = peak_t(w) - W_t(w)
#    (선형 근사: 드로우다운 계산 내생화 필요 → 순차 LP)
# ==============================================================================
calc_cdar_weights <- function(tickers, ret_dt, alpha = 0.95,
                               n_days = 120, max_w = 0.15,
                               max_cdar = NULL) {
  n <- length(tickers)
  if (n < 2L) return(.p2_ew(tickers, max_w))

  mat <- .p2_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(mat)) return(.p2_ew(tickers, max_w))

  valid <- intersect(tickers, colnames(mat))
  if (length(valid) < 2L) return(.p2_ew(tickers, max_w))
  mat_v <- mat[, valid, drop = FALSE]
  T_obs <- nrow(mat_v); p <- ncol(mat_v)
  alpha_bar <- 1 - alpha

  # FRAPO 활용 (설치된 경우)
  if (.HAS_FRAPO) {
    result <- tryCatch({
      library(FRAPO, quietly = TRUE)
      prices_dummy <- apply(mat_v, 2, function(r) cumprod(1 + r)) * 100
      if (is.null(max_cdar)) {
        sol <- PMinCDaR(prices_dummy, percentage = FALSE)
      } else {
        sol <- PMinCDaR(prices_dummy, percentage = FALSE)  # max_cdar as constraint unsupported directly
      }
      as.numeric(Weights(sol))
    }, error = function(e) {
      cat(sprintf("[cdar] FRAPO failed (%s)\n", e$message)); NULL
    })
    if (!is.null(result) && length(result) == p) {
      w_full <- rep(0, n); names(w_full) <- tickers
      w_full[valid] <- result
      return(.normalize(w_full, max_w))
    }
  }

  # 순수 R 구현: CDaR LP (Chekhlov et al. 2005 정식화)
  # 누적 수익률을 가격 경로로 표현 후 LP 변수 내 드로우다운 선형화
  #
  # Vars: [w(p), u(T), q(T), zeta(1)]  총 N = p+2T+1
  # q_t = 누적 포트폴리오 가치  (portfolio cumulative value proxy)
  # D_t = max_{s<=t}(q_s) - q_t  (드로우다운)
  # q_t = q_{t-1} + R_t'w  (선형, q_0 = 1)
  # u_t >= D_t - zeta, u_t >= 0
  # CDaR = zeta + 1/(alpha_bar*T)*sum(u_t)
  result <- tryCatch({
    if (!.HAS_CCCP) stop("cccp not available")
    library(cccp, quietly = TRUE)

    # Return matrix: T_obs × p
    # q_t = sum_{s=1}^{t} R_s'w + 1  = 1 + cumsum(R)w
    # D_t = max_{s<=t}(q_s) - q_t 는 비선형(max 연산자)이라
    # LP에서 peak_t를 보조 변수 m_t로 도입:
    #   m_t >= q_t   for all t  →  m_t = peak_t (running max)
    #   m_t >= m_{t-1}          →  monotone non-decreasing
    #   D_t = m_t - q_t         (선형)
    # → Vars: [w(p), q(T), m(T), u(T), zeta(1)]  N2 = p+3T+1
    N2 <- p + 3 * T_obs + 1L
    iz_w    <- 1:p
    iz_q    <- (p + 1):(p + T_obs)
    iz_m    <- (p + T_obs + 1):(p + 2 * T_obs)
    iz_u    <- (p + 2 * T_obs + 1):(p + 3 * T_obs)
    iz_zeta <- N2

    c_obj3 <- as.numeric(rep(0, N2))
    c_obj3[iz_u]    <- 1 / (alpha_bar * T_obs)
    c_obj3[iz_zeta] <- 1

    # Equality 1: sum(w) = 1
    A_eq4 <- matrix(0, 1 + T_obs, N2)
    b_eq4 <- c(1, rep(0, T_obs))
    A_eq4[1, iz_w] <- 1
    # q_t - q_{t-1} = R_t'w  (q_0 = 1, so q_1 - 1 = R_1'w)
    for (tt in seq_len(T_obs)) {
      A_eq4[1 + tt, iz_q[tt]] <- 1
      A_eq4[1 + tt, iz_w]     <- -mat_v[tt, ]
      if (tt > 1) A_eq4[1 + tt, iz_q[tt - 1]] <- -1
      else        b_eq4[1 + tt] <- 1  # q_1 - R_1'w = 1 (initial)
    }

    # Inequality (nnoc: G*x <= h):
    # 1) m_t >= q_t:  q_t - m_t <= 0
    G1c <- matrix(0, T_obs, N2)
    for (tt in seq_len(T_obs)) {
      G1c[tt, iz_q[tt]] <- 1; G1c[tt, iz_m[tt]] <- -1
    }
    h1c <- rep(0, T_obs)
    # 2) m_t >= m_{t-1} (monotone):  m_{t-1} - m_t <= 0
    G2c <- matrix(0, T_obs - 1L, N2)
    for (tt in 2:T_obs) {
      G2c[tt - 1, iz_m[tt - 1]] <- 1; G2c[tt - 1, iz_m[tt]] <- -1
    }
    h2c <- rep(0, T_obs - 1L)
    # 3) u_t >= 0:  -u_t <= 0
    G3c <- matrix(0, T_obs, N2)
    for (tt in seq_len(T_obs)) G3c[tt, iz_u[tt]] <- -1
    h3c <- rep(0, T_obs)
    # 4) u_t >= D_t - zeta = m_t - q_t - zeta:
    #    m_t - q_t - zeta - u_t <= 0
    G4c <- matrix(0, T_obs, N2)
    for (tt in seq_len(T_obs)) {
      G4c[tt, iz_m[tt]]    <- 1
      G4c[tt, iz_q[tt]]    <- -1
      G4c[tt, iz_zeta]     <- -1
      G4c[tt, iz_u[tt]]    <- -1
    }
    h4c <- rep(0, T_obs)
    # 5) 0 <= w <= max_w
    G5c <- cbind(-diag(p), matrix(0, p, 3 * T_obs + 1L)); h5c <- rep(0, p)
    G6c <- cbind(diag(p),  matrix(0, p, 3 * T_obs + 1L)); h6c <- rep(max_w, p)
    # 6) m_t >= 1 (초기 피크 >= 1):  -m_t <= -1
    G7c <- matrix(0, T_obs, N2)
    for (tt in seq_len(T_obs)) G7c[tt, iz_m[tt]] <- -1
    h7c <- rep(-1, T_obs)
    # 7) zeta >= 0:  -zeta <= 0
    G8c <- matrix(0, 1, N2); G8c[1, iz_zeta] <- -1; h8c <- 0

    if (T_obs >= 2) {
      G_all3 <- rbind(G1c, G2c, G3c, G4c, G5c, G6c, G7c, G8c)
      h_all3 <- as.numeric(c(h1c, h2c, h3c, h4c, h5c, h6c, h7c, h8c))
    } else {
      G_all3 <- rbind(G1c, G3c, G4c, G5c, G6c, G7c, G8c)
      h_all3 <- as.numeric(c(h1c, h3c, h4c, h5c, h6c, h7c, h8c))
    }

    res_c <- cccp(q     = c_obj3,
                  A     = A_eq4,
                  b     = as.numeric(b_eq4),
                  cList = list(nnoc(G_all3, h_all3)),
                  optctrl = ctrl(trace = FALSE, maxiters = 200L))

    if (getstatus(res_c)[[1]] == "optimal") {
      x_opt <- getx(res_c)
      w_new <- pmax(as.numeric(x_opt[iz_w]), 0)
      if (sum(w_new) < 1e-10) stop("CDaR degenerate")
      w_new / sum(w_new)
    } else stop(paste("CDaR status:", getstatus(res_c)[[1]]))
  }, error = function(e) {
    cat(sprintf("[cdar] LP failed (%s), falling back to min-vol\n", e$message))
    # 폴백: EW 드로우다운 기반 cov 역수 가중
    cov_mat <- cov(mat_v)
    diag_inv <- 1 / pmax(diag(cov_mat), 1e-8)
    diag_inv / sum(diag_inv)
  })

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- result
  .normalize(w_full, max_w)
}


# ==============================================================================
# 4. MTD — 꼬리 의존성 최소화 (Pfaff 2016 Ch.11, Frahm et al.)
#    FRAPO::PMTD() 기반. 불가 시 tail-correlation 역수 가중
#    TDC(Tail Dependence Coefficient): Clayton copula 하위 꼬리
#    λ_ij = lim P(X_i <= VaR_i | X_j <= VaR_j) as alpha→0
# ==============================================================================
calc_pmtd_weights <- function(tickers, ret_dt, alpha = 0.95,
                               n_days = 120, max_w = 0.15) {
  n <- length(tickers)
  if (n < 2L) return(.p2_ew(tickers, max_w))

  mat <- .p2_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(mat)) return(.p2_ew(tickers, max_w))

  valid <- intersect(tickers, colnames(mat))
  if (length(valid) < 2L) return(.p2_ew(tickers, max_w))
  mat_v <- mat[, valid, drop = FALSE]
  p     <- ncol(mat_v)
  T_obs <- nrow(mat_v)

  # FRAPO 활용
  if (.HAS_FRAPO) {
    result <- tryCatch({
      library(FRAPO, quietly = TRUE)
      prices_dummy <- apply(mat_v, 2, function(r) cumprod(1 + r)) * 100
      # tdc(): tail dependence coefficient matrix
      tdc_mat <- tdc(mat_v, method = "EV")  # Extreme Value lower tail
      sol <- PMTD(tdc_mat)
      as.numeric(Weights(sol))
    }, error = function(e) {
      cat(sprintf("[pmtd] FRAPO failed (%s)\n", e$message)); NULL
    })
    if (!is.null(result) && length(result) == p) {
      w_full <- rep(0, n); names(w_full) <- tickers
      w_full[valid] <- result
      return(.normalize(w_full, max_w))
    }
  }

  # 순수 R 근사: 경험적 하위 꼬리 의존성 행렬 계산
  # λ_ij ≈ P(U_i <= alpha, U_j <= alpha) / alpha
  # (U_i = empirical rank / T)
  alpha_tdep <- 1 - alpha  # 하위 꼬리 분위수
  result <- tryCatch({
    # 경험적 rank 변환 (uniform marginal)
    u_mat <- apply(mat_v, 2, function(x) rank(x, ties.method = "average") / (T_obs + 1))
    tdc_mat <- matrix(0, p, p)
    diag(tdc_mat) <- 1
    for (i in seq_len(p - 1)) {
      for (j in (i + 1):p) {
        joint_tail <- mean(u_mat[, i] <= alpha_tdep & u_mat[, j] <= alpha_tdep)
        lambda_ij  <- joint_tail / alpha_tdep
        tdc_mat[i, j] <- tdc_mat[j, i] <- lambda_ij
      }
    }
    # 평균 꼬리 의존성이 낮은 자산에 높은 가중치
    avg_tdc <- rowMeans(tdc_mat) - diag(tdc_mat) / p
    avg_tdc <- pmax(avg_tdc, 1e-6)
    w_raw <- 1 / avg_tdc
    w_raw / sum(w_raw)
  }, error = function(e) {
    cat(sprintf("[pmtd] TDC failed (%s), falling back to EW\n", e$message))
    rep(1 / p, p)
  })

  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid] <- result
  .normalize(w_full, max_w)
}


# ==============================================================================
# 5. Robust SOCP (Pfaff 2016 Ch.10, Ben-Tal & Nemirovski 1998)
#    강건 공분산(OGK/MCD) + SOCP 불확실성 집합
#
#    Box uncertainty:  max_{|delta|<=theta} (mu+delta)'w → worst-case linear
#    Ellipsoid:        max_{||Theta^{1/2}delta||<=kappa} mu'w - kappa||Sigma^{1/2}w||
#      = mu'w - kappa * sqrt(w'Σw)  → SOCP:
#        max  mu'w - kappa * t
#        s.t. ||Sigma^{1/2}w|| <= t
#
#    cccp::socc() 구현
# ==============================================================================
solve_robust_socp_weights <- function(mu, Sigma, uncertainty = c("box", "ellipsoid"),
                                       theta = 0.5, long_only = TRUE, max_w = 0.15) {
  uncertainty <- match.arg(uncertainty)
  p <- length(mu)
  if (p < 2L) return(rep(1 / p, p))

  # 공분산 양정치 보장
  eig_min <- min(eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values)
  if (eig_min <= 0) {
    Sigma <- Sigma + (-eig_min + 1e-6) * diag(p)
  }

  result <- tryCatch({
    if (!.HAS_CCCP) stop("cccp not available")
    library(cccp, quietly = TRUE)

    if (uncertainty == "box") {
      # Box: worst-case mu = mu - theta (long-only)
      # min -(mu - theta)'w + 0.5*w'(2Sigma)w (QP 정규화)
      # cList: nnoc(G, h) 형태
      mu_wc  <- as.numeric(mu - theta)
      G_box  <- rbind(-diag(p), diag(p))          # -w <= 0; w <= max_w
      h_box  <- as.numeric(c(rep(0, p), rep(max_w, p)))
      res    <- cccp(P = 2 * Sigma,
                     q = as.numeric(-mu_wc),
                     A = matrix(rep(1, p), nrow = 1),
                     b = 1,
                     cList = list(nnoc(G_box, h_box)),
                     optctrl = ctrl(trace = FALSE))
      if (getstatus(res)[[1]] == "optimal") {
        w_opt <- pmax(as.numeric(getx(res)), 0)
        if (sum(w_opt) < 1e-10) stop("degenerate box")
        w_opt / sum(w_opt)
      } else stop(paste("box QP status:", getstatus(res)[[1]]))

    } else {
      # Ellipsoid: max mu'w - kappa*sqrt(w'Σw)
      # = min -mu'w + kappa*t  s.t. ||chol_S * w||_2 <= t
      # socc(F, g, d, f): ||F*x + g||_2 <= d'*x + f
      # F = [chol_S, 0_col(p x 1)], g = 0(p), d = [0...0, 1](p+1), f = 0
      kappa  <- theta * sqrt(qchisq(0.9, p))
      chol_S <- tryCatch(t(chol(Sigma)), error = function(e) {
        diag(sqrt(pmax(diag(Sigma), 1e-8)))
      })
      # vars: [w(p), t(1)], total p+1
      q_obj  <- as.numeric(c(-mu, kappa))
      F_mat  <- cbind(chol_S, rep(0, p))    # p x (p+1)
      g_vec  <- rep(0, p)
      d_vec  <- as.numeric(c(rep(0, p), 1)) # coefficient of t
      f_sca  <- 0.0
      A_eq   <- matrix(c(rep(1, p), 0), nrow = 1)
      # w >= 0, w <= max_w, t >= 0  via nnoc
      G_ineq <- rbind(
        cbind(-diag(p), rep(0, p)),    # -w <= 0
        cbind(diag(p),  rep(0, p)),    # w <= max_w
        c(rep(0, p), -1)               # -t <= 0
      )
      h_ineq <- as.numeric(c(rep(0, p), rep(max_w, p), 0))
      res <- cccp(q     = q_obj,
                  A     = A_eq,
                  b     = 1,
                  cList = list(
                    socc(F = F_mat, g = g_vec, d = d_vec, f = f_sca),
                    nnoc(G_ineq, h_ineq)
                  ),
                  optctrl = ctrl(trace = FALSE))
      if (getstatus(res)[[1]] == "optimal") {
        x_opt <- getx(res)
        w_opt <- pmax(as.numeric(x_opt[1:p]), 0)
        if (sum(w_opt) < 1e-10) stop("degenerate ellipsoid")
        w_opt / sum(w_opt)
      } else stop(paste("ellipsoid SOCP status:", getstatus(res)[[1]]))
    }
  }, error = function(e) {
    cat(sprintf("[robust_socp] failed (%s) — max-SR 근사(mu/sigma)로 폴백, 캡은 재분배로 강제\n",
                e$message))
    # 폴백: Sharpe 비율 최대화 (inverse-vol 비례)
    # ★2026-08-24 수리 — 여기가 .normalize 원 결함과 **자구까지 동일한** 마지막 지점이었다.
    #   구판: `w_raw <- pmin(w_raw, max_w); w_raw / sum(w_raw)`
    #   mu/sig 는 정규화되지 않은 raw Sharpe 벡터(임의 스케일)라, 전 원소가 max_w 를
    #   넘으면 pmin 이 전부 같은 값으로 눌러버리고 뒤이은 합-정규화가 그것을 **정확히
    #   EW** 로 만든다. 예외도 경고도 없다. 게다가 로그는 "max-SR approx" 라고 적어
    #   실제로 계산한 것과 다른 말을 했다 — 계기가 자기 산출을 거짓 보고한 형태다.
    #   ⇒ 합-정규화를 **먼저** 하고, 캡은 normalize_long_only(초과분 반복 재분배)에 위임.
    #   양성 대조 = test_weight_catalog.R 축 (f) socp_fallback.
    sig <- sqrt(pmax(diag(Sigma), 1e-8))
    w_raw <- mu / sig; w_raw[w_raw < 0] <- 0
    if (sum(w_raw) < 1e-10) w_raw <- rep(1 / p, p)
    nm_fb <- names(w_raw)
    w_raw <- w_raw / sum(w_raw)
    out_fb <- normalize_long_only(w_raw, lb = 0, ub = max_w, target_sum = 1)
    names(out_fb) <- nm_fb
    out_fb
  })

  result
}


# ==============================================================================
# 6. 강건 공분산 추정 유틸리티 (Pfaff 2016 Ch.10)
#    rrcov 패키지: OGK, MCD, SDE
#    반환: covariance matrix (named)
# ==============================================================================
compute_robust_cov <- function(ret_mat, method = c("OGK", "MCD", "SDE")) {
  method <- match.arg(method)
  p <- ncol(ret_mat)

  if (!.HAS_RRCOV) {
    cat("[robust_cov] rrcov not available, returning sample cov\n")
    return(cov(ret_mat, use = "pairwise.complete.obs"))
  }

  library(rrcov, quietly = TRUE)

  result <- tryCatch({
    cov_obj <- switch(method,
      OGK = CovOgk(ret_mat),
      MCD = CovMcd(ret_mat),
      SDE = CovSde(ret_mat)
    )
    cov_mat <- getCov(cov_obj)
    if (!is.null(colnames(ret_mat))) {
      colnames(cov_mat) <- rownames(cov_mat) <- colnames(ret_mat)
    }
    # 양정치 보장
    eig_min <- min(eigen(cov_mat, symmetric = TRUE, only.values = TRUE)$values)
    if (eig_min <= 0) cov_mat <- cov_mat + (-eig_min + 1e-7) * diag(p)
    cov_mat
  }, error = function(e) {
    cat(sprintf("[robust_cov] %s failed (%s), returning sample cov\n", method, e$message))
    cov(ret_mat, use = "pairwise.complete.obs")
  })

  result
}

# Phase 2 로드 확인
.p2_methods <- c("cvar_lp", "cvar_budget", "cdar", "pmtd", "robust_socp", "robust_cov")
cat(sprintf("[advanced_weights] Phase 2 loaded. New methods: %s\n", paste(.p2_methods, collapse = ", ")))
cat(sprintf("[advanced_weights] Phase 2 pkgs: cccp=%s, rrcov=%s, FRAPO=%s\n",
            if (.HAS_CCCP) "OK" else "MISSING (LP fallback)",
            if (.HAS_RRCOV) "OK" else "MISSING (sample cov)",
            if (.HAS_FRAPO) "OK" else "MISSING (pure-R fallback)"))
