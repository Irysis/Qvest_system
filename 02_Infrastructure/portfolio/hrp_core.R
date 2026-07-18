#==============================================================================
# hrp_core.R — HRP + Gerber + RMT 공유 코어 (Codex 제안: Separation of Concerns)
#
# 역할:
#   backtest_harness.R에 정의된 HRP 관련 함수들을 advanced_weights.R에서
#   안전하게 참조할 수 있도록 한다.
#   - 직접 함수 정의(duplicate) 없이 하네스 로드 여부를 감지
#   - 하네스 미로드 시 standalone 폴백 정의 제공
#
# Usage (advanced_weights.R 또는 전략 파일):
#   source("02_Infrastructure/portfolio/hrp_core.R")
#   w <- calc_hrp_weights(tickers, ret_dt)
#
# Note:
#   backtest_harness.R을 source()한 환경에서는 이 파일의 정의가 불필요하므로
#   이미 존재하는 함수는 재정의하지 않는다.
#==============================================================================

# ── 의존성 ────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages(library(data.table))

# ── 하네스 로드 감지 ──────────────────────────────────────────────────────────
# backtest_harness.R이 이미 로드된 경우 재정의 스킵
.hrp_core_already_loaded <- exists("calc_hrp_weights", mode = "function") &&
                             exists(".hrp_bisect",    mode = "function") &&
                             exists(".gerber_cor",    mode = "function")

if (.hrp_core_already_loaded) {
  cat("[hrp_core] backtest_harness.R 로드 감지 → standalone 정의 스킵\n")
} else {
  cat("[hrp_core] standalone 모드 → HRP/Gerber/RMT 함수 정의\n")

  # ── Rcpp 플래그 (없으면 FALSE) ───────────────────────────────────────────────
  if (!exists(".USE_RCPP_WEIGHT_ENGINE")) .USE_RCPP_WEIGHT_ENGINE <- FALSE

  # ─────────────────────────────────────────────────────────────────────────────
  # Gerber Statistic Correlation (Gerber, Hurst, Konev 2022)
  # Noise-robust: co-movements beyond threshold × sd만 계산
  # ─────────────────────────────────────────────────────────────────────────────
  .gerber_cor <- function(ret_mat, threshold = 0.5) {
    if (isTRUE(.USE_RCPP_WEIGHT_ENGINE) && exists("cpp_gerber_cor")) {
      return(cpp_gerber_cor(ret_mat, threshold))
    }
    p   <- ncol(ret_mat)
    sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
    h   <- threshold * sds
    cor_mat <- diag(p)
    for (i in 1:(p - 1)) {
      xi <- ret_mat[, i]; hi <- h[i]
      for (j in (i + 1):p) {
        xj <- ret_mat[, j]; hj <- h[j]
        up_i <- xi > hi;  dn_i <- xi < -hi
        up_j <- xj > hj;  dn_j <- xj < -hj
        conc  <- sum((up_i & up_j) | (dn_i & dn_j), na.rm = TRUE)
        disc  <- sum((up_i & dn_j) | (dn_i & up_j), na.rm = TRUE)
        denom <- conc + disc
        cor_mat[i, j] <- cor_mat[j, i] <- if (denom > 0) (conc - disc) / denom else 0
      }
    }
    colnames(cor_mat) <- rownames(cor_mat) <- colnames(ret_mat)
    cor_mat
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # RMT 잡음 제거 (Marchenko-Pastur eigenvalue filtering)
  # ─────────────────────────────────────────────────────────────────────────────
  .rmt_denoise <- function(cor_mat, q_ratio) {
    if (isTRUE(.USE_RCPP_WEIGHT_ENGINE) && exists("cpp_rmt_denoise")) {
      return(cpp_rmt_denoise(cor_mat, q_ratio))
    }
    n <- nrow(cor_mat)
    if (n < 3 || q_ratio < 1) return(cor_mat)
    lambda_plus <- (1 + 1 / sqrt(q_ratio))^2
    eig <- eigen(cor_mat, symmetric = TRUE)
    vals <- eig$values; vecs <- eig$vectors
    noise_idx <- which(vals <= lambda_plus)
    if (length(noise_idx) > 0 && length(noise_idx) < n) {
      vals[noise_idx] <- mean(vals[noise_idx])
    }
    D <- matrix(0, n, n); diag(D) <- vals
    cor_clean <- vecs %*% D %*% t(vecs)
    diag(cor_clean) <- 1.0
    cor_clean <- (cor_clean + t(cor_clean)) / 2
    colnames(cor_clean) <- rownames(cor_clean) <- colnames(cor_mat)
    cor_clean
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # 공분산/상관 전처리 디스패처
  # ─────────────────────────────────────────────────────────────────────────────
  # ── Ledoit-Wolf (2020) analytical nonlinear shrinkage (NLS) 헬퍼 ──────────────
  #   analytical_shrinkage.m 포트 (Ledoit & Wolf 2020, Annals of Statistics 48(5)).
  #   Epanechnikov 커널 밀도 + 표본 고유값 Hilbert 변환. p>n에서도 full-rank PSD.
  #   FQ-057 (2026-07-18) 5-estimator estimation-quality 1위 → NP3로 등재.
  #   ★러너 원본 04_Research/method_frontier/fq057_captier_sigma/estimators.R::
  #     est_lw_nls 와 수치 파리티(bit) 유지 — 본체 로직 수정 금지(run_np3_parity.R 검증).
  .lw_nls_cov <- function(R) {
    n <- nrow(R); p <- ncol(R)
    X <- scale(R, center = TRUE, scale = FALSE)
    n_eff <- n - 1                              # effective sample size (paper)
    S <- crossprod(X) / n_eff
    eg <- eigen(S, symmetric = TRUE)
    lambda_all <- rev(eg$values)                # ascending
    u <- eg$vectors[, rev(seq_len(p)), drop = FALSE]
    keep <- max(1, p - n_eff + 1):p
    lambda <- lambda_all[keep]
    lambda[lambda < .Machine$double.eps] <- .Machine$double.eps
    m <- length(lambda)                         # = min(p, n_eff)
    L  <- matrix(lambda, nrow = m, ncol = m)    # lambda in rows repeated cols
    Ht <- (n_eff^(-1/3)) * t(L)                 # bandwidth matrix H = h * lambda_j
    x  <- (L - t(L)) / Ht
    ftilde <- (3 / (4 * sqrt(5))) * rowMeans(pmax(1 - x^2 / 5, 0) / Ht)
    Hftemp <- (-3 / (10 * pi)) * x +
              (3 / (4 * sqrt(5) * pi)) * (1 - x^2 / 5) *
              log(abs((sqrt(5) - x) / (sqrt(5) + x)))
    sel <- abs(x) == sqrt(5)
    if (any(sel)) Hftemp[sel] <- (-3 / (10 * pi)) * x[sel]
    Hftemp[!is.finite(Hftemp)] <- 0
    Hftilde <- rowMeans(Hftemp / Ht)
    c_ratio <- p / n_eff
    if (p <= n_eff) {
      dtilde <- lambda / ((pi * c_ratio * lambda * ftilde)^2 +
                          (1 - c_ratio - pi * c_ratio * lambda * Hftilde)^2)
    } else {
      h <- n_eff^(-1/3)
      Hftilde0 <- (1 / pi) * (3 / (10 * h^2) +
                   3 / (4 * sqrt(5) * h) * (1 - 1 / (5 * h^2)) *
                   log((1 + sqrt(5) * h) / (1 - sqrt(5) * h))) * mean(1 / lambda)
      dtilde0 <- 1 / (pi * (p - n_eff) / n_eff * Hftilde0)
      dtilde1 <- lambda / (pi^2 * lambda^2 * (ftilde^2 + Hftilde^2))
      dtilde  <- c(rep(dtilde0, p - n_eff), dtilde1)
    }
    Sig <- u %*% diag(dtilde) %*% t(u)
    Sig <- (Sig + t(Sig)) / 2
    dimnames(Sig) <- dimnames(S)
    Sig
  }

  .get_cor_cov <- function(ret_mat, cov_method = "sample") {
    .lw_degenerate_info <- NULL
    if (cov_method == "gerber_rmt") {
      q_ratio <- nrow(ret_mat) / ncol(ret_mat)
      cor_mat <- .gerber_cor(ret_mat)
      cor_mat <- .rmt_denoise(cor_mat, q_ratio)
      sds     <- apply(ret_mat, 2, sd, na.rm = TRUE)
      cov_mat <- cor_mat * outer(sds, sds)
    } else if (cov_method == "ledoit_wolf") {
      p   <- ncol(ret_mat); n_obs <- nrow(ret_mat)
      S   <- cov(ret_mat, use = "pairwise.complete.obs")
      mu  <- mean(diag(S))
      rho <- min(((n_obs - 2) / n_obs * sum(diag(S)^2) + sum(S)^2) /
                   ((n_obs + 2) * (sum(S^2) - sum(diag(S)^2) / p)), 1)
      cov_mat <- (1 - rho) * S + rho * mu * diag(p)
      sds     <- sqrt(diag(cov_mat))
      cor_mat <- cov_mat / outer(sds, sds); diag(cor_mat) <- 1
      # ── p>n 퇴화 가드 (FQ-057 NP3, 2026-07-18 도훈 승인) ───────────────────────
      # 인라인 LW(OAS 변형)는 p>n에서 rho→1(cap 바인딩) → Σ≈μ·I (cond≈1, 상관구조
      # 전멸, MVP=EW 붕괴). WT 규모(p≤25)는 비바인딩·무해하나 대형 유니버스는 금지.
      # ★경고 + 진단 attr("lw_degenerate")만 부여 — 값/기본동작 변경 없음(자동 폴백 아님).
      #   대안: cov_method="lw_nls"(analytical NLS, full-rank PSD) 또는 factor Σ.
      if (p > n_obs) {
        .lw_degenerate_info <- list(
          degenerate      = TRUE,
          method          = "ledoit_wolf",
          reason          = "p>n: inline LW shrinkage cap (rho->1) collapses Sigma toward mu*I",
          p               = p,
          n_obs           = n_obs,
          rho             = rho,
          rho_cap_binding = isTRUE(rho >= 1 - 1e-12),
          guidance        = "do NOT consume for large-universe Sigma; use cov_method='lw_nls' or a factor model"
        )
        warning(sprintf(
          "[.get_cor_cov] ledoit_wolf p>n degeneracy: p(%d) > n(%d), rho=%.6f%s -> Sigma collapses toward mu*I (cond~1, correlation structure destroyed). Do NOT use for large-universe Sigma; prefer cov_method='lw_nls'. [attr 'lw_degenerate' attached]",
          p, n_obs, rho,
          if (isTRUE(rho >= 1 - 1e-12)) " [cap binding]" else ""),
          call. = FALSE)
      }
    } else if (cov_method == "lw_nls") {
      cov_mat <- .lw_nls_cov(ret_mat)
      sds     <- sqrt(diag(cov_mat))
      cor_mat <- cov_mat / outer(sds, sds); diag(cor_mat) <- 1
    } else {
      cor_mat <- cor(ret_mat, use = "pairwise.complete.obs")
      cov_mat <- cov(ret_mat, use = "pairwise.complete.obs")
    }
    cor_mat[is.na(cor_mat)] <- 0
    cov_mat[is.na(cov_mat)] <- 0
    out <- list(cor = cor_mat, cov = cov_mat)
    if (!is.null(.lw_degenerate_info)) attr(out, "lw_degenerate") <- .lw_degenerate_info
    out
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # 수익률 행렬 구축 헬퍼
  # ─────────────────────────────────────────────────────────────────────────────
  .build_ret_matrix <- function(tickers, ret_dt, n_days) {
    sub        <- ret_dt[Ticker %in% tickers, .(Date, Ticker, Ret)]
    last_dates <- tail(sort(unique(sub$Date)), n_days)
    sub        <- sub[Date %in% last_dates]
    if (nrow(sub) == 0) return(NULL)
    wide      <- dcast(sub, Date ~ Ticker, value.var = "Ret")
    mat       <- as.matrix(wide[, -1, drop = FALSE])
    good_cols <- colSums(!is.na(mat)) >= 30
    if (sum(good_cols) < 3) return(NULL)
    mat <- mat[, good_cols, drop = FALSE]
    good_rows <- rowSums(!is.na(mat)) >= ncol(mat) * 0.5
    mat <- mat[good_rows, , drop = FALSE]
    if (nrow(mat) < 30) return(NULL)
    mat[is.na(mat)] <- 0
    mat
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # 클러스터 분산
  # ─────────────────────────────────────────────────────────────────────────────
  .cluster_var <- function(cov_mat, idx) {
    if (length(idx) == 1) return(cov_mat[idx, idx])
    sub_cov <- cov_mat[idx, idx, drop = FALSE]
    ivp <- 1 / diag(sub_cov); ivp <- ivp / sum(ivp)
    as.numeric(t(ivp) %*% sub_cov %*% ivp)
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # HRP Recursive Bisection
  # ─────────────────────────────────────────────────────────────────────────────
  .hrp_bisect <- function(cov_mat, order_idx) {
    if (isTRUE(.USE_RCPP_WEIGHT_ENGINE) && exists("cpp_hrp_weights")) {
      return(as.numeric(cpp_hrp_weights(cov_mat, order_idx)))
    }
    n <- length(order_idx)
    w <- rep(1.0, n)
    clusters <- list(order_idx)
    while (length(clusters) > 0) {
      new_clusters <- list()
      for (cl in clusters) {
        if (length(cl) <= 1) next
        mid   <- ceiling(length(cl) / 2)
        left  <- cl[1:mid]; right <- cl[(mid + 1):length(cl)]
        vl    <- .cluster_var(cov_mat, left)
        vr    <- .cluster_var(cov_mat, right)
        alpha <- 1 - vl / (vl + vr)
        w[left]  <- w[left]  * alpha
        w[right] <- w[right] * (1 - alpha)
        if (length(left)  > 1) new_clusters[[length(new_clusters) + 1]] <- left
        if (length(right) > 1) new_clusters[[length(new_clusters) + 1]] <- right
      }
      clusters <- new_clusters
    }
    w
  }

  # ─────────────────────────────────────────────────────────────────────────────
  # calc_hrp_weights — Lopez de Prado (2016)
  # ─────────────────────────────────────────────────────────────────────────────
  calc_hrp_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                               cov_method = "sample") {
    ret_mat <- .build_ret_matrix(tickers, ret_dt, n_days)
    if (is.null(ret_mat) || ncol(ret_mat) < 3) {
      return(rep(1 / length(tickers), length(tickers)))
    }
    survived <- colnames(ret_mat)
    dropped  <- setdiff(tickers, survived)
    cc <- tryCatch(
      .get_cor_cov(ret_mat, cov_method),
      error = function(e) .get_cor_cov(ret_mat, "sample")
    )
    cor_mat <- cc$cor; cov_mat <- cc$cov
    d       <- 0.5 * (1 - cor_mat); d[d < 0] <- 0
    dist_mat <- as.dist(sqrt(d))
    hc       <- hclust(dist_mat, method = "ward.D2")
    order_idx <- hc$order
    w_sub <- tryCatch({
      ws <- .hrp_bisect(cov_mat, order_idx)
      ws / sum(ws)
    }, error = function(e) rep(1 / length(survived), length(survived)))
    names(w_sub) <- survived

    w_full <- rep(0, length(tickers)); names(w_full) <- tickers
    if (length(dropped) > 0) {
      for (tk in dropped) w_full[tk] <- 1 / length(tickers)
      hrp_scale <- 1 - sum(w_full)
      for (tk in survived) w_full[tk] <- w_sub[tk] * hrp_scale
    } else {
      w_full[survived] <- w_sub[survived]
    }
    w_full <- w_full / sum(w_full)
    if (any(w_full > max_w)) { w_full <- pmin(w_full, max_w); w_full <- w_full / sum(w_full) }
    w_full
  }
}

cat("[hrp_core] Ready. Functions: calc_hrp_weights, .hrp_bisect, .gerber_cor, .rmt_denoise, .get_cor_cov\n")
