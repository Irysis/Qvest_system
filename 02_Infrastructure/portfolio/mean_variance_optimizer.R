#==============================================================================
# QEPM Mean-Variance Optimizer — v2.1 (v6.1 Grinold Breadth Enforcement)
# 2026-04-23 v1.0 정통 MVO 복원
# 2026-04-24 v2.0 — Confidence-aware + ForecastUncertaintyPenalty
# 2026-04-24 v2.1 — min_names + HHI_cap + Alpha winsorization (Task #26, L-192)
#
# 목적함수 (v2.0):
#   max x'α̃ - (λ/2) x'Σx - φ·TC(x) - ψ·FU(x, c)
#   where α̃_i = c_i · α̂_i (confidence scaled)
#         FU(x, c) = Σ_i x_i² (1-c_i)² (low confidence 집중 penalty)
#   subject to 1'x = 1 (absolute) or 1'x = 0 (active)
#
# v6.1 R4 개선:
#   - Alpha confidence가 weight 결정에 수학적 반영
#   - 불안정 alpha (낮은 c)에는 집중 penalty
#
# v6.1 Task #26 (L-192 Remediation):
#   - min_names: Grinold IR = IC × √breadth 강화 (≥15 종목)
#   - hhi_cap:   Σ w_i² ≤ 0.10 (집중 방지)
#   - bounds:    default 0.20 → 0.10 (per-name 상한 축소)
#   - winsor:    alpha ±2σ clip (outlier 집중 방지)
#
# v2.4 (2026-07-18, FQ-057 NP4 — 병행 두 수리를 단일 파일로 통합):
#  ── RF-O5 (HHI projection 누출, task_1b9e50a3) ──
#   (1) max_names 절단(D > max_names) 시 HHI projection 을 support(non-zero) 부분벡터로
#       제한. 구코드 .project_hhi absorber(w<bounds[2])가 w=0 유니버스 종목을 포함해
#       top-N 밖 비중 누출 → n_names > max_names (p≈300 실측). D ≤ max_names 는 전체벡터 유지.
#   (2) .project_hhi absorber 부재 판정을 감액 *전*으로 이동 → Σw=target_sum 보존
#       (감액-후-break Σw=0.995 잠복버그; box-vertex 포트폴리오는 D ≤ max_names 에서도 노출 —
#       "전체벡터 경로엔 w=0 absorber 항상 존재" 가정은 거짓, 적대검증 L3. NEW 가 Σw=1 로 더 정확).
#   (3) min_names > max_names 모순 config 를 fail-loud infeasible 로 반환.
#  ── dead-parameter (turnover_penalty φ 배선, task_89b2050e) ──
#   current_weights·turnover_penalty(φ)를 QP에 실배선 — 종전엔 시그니처·method 라벨에만 존재하고
#   목적함수(Dmat/dvec) 미반영(no-op)이었음. TC(x)=Σ_i |x_i − x_prev,i| (L1)를 z=[x;u;v] 변수분리
#   확장 QP로 정확 표현(등식 x − u + v = x_prev, u,v ≥ 0, 선형비용 φ·1'(u+v), meq = 1+D).
#   φ=0 또는 current_weights=NULL 이면 v2.2 경로·반환객체 완전 불변(parity 65/65 identical).
#   φ 단위 = 알파와 동일 기간수익 단위 레그당 비용률(15bps=0.0015, cost_model v2.4_kr_retail_15bps 정합).
#  ── 통합 노트: 두 수리는 코드 영역이 직교(RF-O5=.project_hhi+post-QP projection+precheck /
#   dead-param=QP Dmat/dvec/Amat 확장) — 헤더·배너만 수동 reconcile. 각 수리는 독립 검증 통과.
#==============================================================================

suppressPackageStartupMessages({
  library(quadprog)
  library(data.table)
})

# ─── Alpha Winsorization Helper ───────────────────────────
# alpha z-score 계산 후 |z| > winsor 이면 sign(z) * winsor * sd + mean 로 clip.
# 전체 cross-section 기준.
.winsorize_alpha <- function(alpha_vec, winsor = 2.0) {
  if (is.na(winsor) || is.null(winsor) || winsor <= 0) return(alpha_vec)
  mu <- mean(alpha_vec, na.rm = TRUE)
  sd_ <- stats::sd(alpha_vec, na.rm = TRUE)
  if (!is.finite(sd_) || sd_ < 1e-12) return(alpha_vec)
  z <- (alpha_vec - mu) / sd_
  over <- !is.na(z) & abs(z) > winsor
  if (any(over)) {
    alpha_vec[over] <- sign(z[over]) * winsor * sd_ + mu
  }
  alpha_vec
}

# ─── HHI Projection Helper ─────────────────────────────────
# HHI = sum(w^2). Cap 초과 시 top weight 0.01 감소 → 나머지 non-cap 종목에
# 균등 재분배 → HHI 재계산. 수렴 혹은 max_iter 도달까지 반복.
# long-only + bounds + 합=target_sum 유지.
#
# ★Σw 보존 (2026-07-18): absorber(상한 여유 종목) 부재 시 종료를 top weight
# 감액 *전*에 판정한다. 구버전은 감액 후 break 하여 Σw = target - dec 로 파손됐다.
# 이 no-absorber 케이스는 (a) RF-O5 support-제한 projection 의 소규모 support(예:
# 2종), 그리고 (b) box-vertex 고정 포트폴리오(D×bounds[2] ≈ target_sum → 전 종목이
# 상한에 고정, w=0 종목 부재)에서 발생한다 — 후자는 D ≤ max_names 전체벡터 경로
# 에서도 발생하므로 "전체벡터 경로엔 w=0 absorber 가 항상 존재"는 거짓이다
# (적대검증 L3 실측). absorber SET 은 top_idx 를 setdiff 로 제외하므로 감액 전/후
# 동일 — 재분배 케이스는 bit-불변, no-absorber 케이스만 "감액 없이 종료
# (Σw=target 보존, converged=FALSE)"로 교정한다.
.project_hhi <- function(w,
                          cap = 0.15,
                          bounds = c(0, 0.15),
                          target_sum = 1,
                          step = 0.01,
                          max_iter = 500,
                          tol = 1e-6) {
  w <- as.numeric(w)
  N <- length(w)
  if (N == 0) return(w)

  # Guard: lower bound * N > target_sum 이면 infeasible → early return
  if (bounds[1] * N - target_sum > tol) return(w)

  hhi <- sum(w^2)
  iter <- 0
  while (hhi > cap + tol && iter < max_iter) {
    iter <- iter + 1
    # 제일 큰 weight (bounds[1] 초과, 즉 감축 가능) 선택
    reducible <- w > bounds[1] + tol
    if (!any(reducible)) break
    top_idx <- which.max(w * reducible)

    # 감축 가능량
    dec <- min(step, w[top_idx] - bounds[1])
    if (dec <= tol) break

    # 상한 여유 있는 다른 종목(absorber) 존재를 *감액 전*에 확인 —
    # 부재 시 감액 없이 종료해 Σw=target_sum 을 보존한다. (top_idx 제외 후 set 은
    # 감액 전/후 동일하므로 재분배 대상엔 영향 없음.)
    absorber <- setdiff(which(w < bounds[2] - tol), top_idx)
    if (length(absorber) == 0) break

    w[top_idx] <- w[top_idx] - dec

    # 각 absorber에 배분 시 상한 고려 (iterative fill)
    remaining <- dec
    absorber_order <- absorber[order(w[absorber])]  # 작은 weight 우선 fill
    for (ix in absorber_order) {
      if (remaining <= tol) break
      room <- bounds[2] - w[ix]
      add_ <- min(room, remaining / max(1, length(which(absorber_order == ix | absorber_order > ix))))
      # simple equal split → 남은 건 다음 iteration
      add_ <- min(room, remaining)
      add_ <- add_ / max(1, sum(absorber_order %in% absorber_order[seq(match(ix, absorber_order), length(absorber_order))]))
      add_ <- min(room, remaining)
      # 단순 greedy fill (복잡도 회피)
      put_ <- min(room, remaining)
      w[ix] <- w[ix] + put_
      remaining <- remaining - put_
    }

    # 합 재조정 (미세 오차 보정)
    s <- sum(w)
    if (abs(s - target_sum) > tol) {
      scale <- target_sum / s
      w <- w * scale
      # 상한 재clip
      over_cap <- w > bounds[2]
      if (any(over_cap)) {
        excess <- sum(w[over_cap] - bounds[2])
        w[over_cap] <- bounds[2]
        under_cap <- which(w < bounds[2] - tol)
        if (length(under_cap) > 0) {
          w[under_cap] <- w[under_cap] + excess / length(under_cap)
        }
      }
      # 하한 clip
      w <- pmax(w, bounds[1])
    }

    hhi <- sum(w^2)
  }

  list(w = w, hhi = hhi, iter = iter, converged = hhi <= cap + tol)
}

# ─── MVO Confidence-aware 구현 (v2.1) ────────────────────
# Inputs:
#   alpha: named vector (Ticker → expected active return)
#   confidence: named vector (Ticker → confidence [0,1]), optional
#   cov_matrix: symmetric PD matrix (Ticker × Ticker)
#   lambda: risk-aversion (default 1.0)
#   psi: forecast uncertainty penalty (default 0.3; 0 = disable)
#   bounds: c(min_w, max_w) = c(0, 0.10)  (v2.1: 0.20→0.10)
#   max_names: hard cap (default 20)
#   min_names: breadth 하한 (default 15L; NA 시 disable)
#   hhi_cap: HHI 상한 (default 0.10; NA 시 disable)
#   alpha_winsor: alpha z-score clip (default 2.0; NA 시 disable)
#   current_weights: named vector (for turnover penalty)
#   turnover_penalty: φ (default 0.0)
#   active: TRUE = active (Σw=0) / FALSE = absolute (Σw=1)
#
# v6.1 R4: confidence NULL이면 1.0으로 취급 (backward compat)
# v6.1 Task#26: min_names + hhi_cap + alpha_winsor 신규 (L-192)
mvo_weights <- function(alpha,
                         cov_matrix,
                         confidence = NULL,
                         lambda = 1.0,
                         psi = 0.3,
                         bounds = c(0, 0.15),
                         max_names = 25,
                         min_names = 20L,
                         hhi_cap = 0.15,
                         alpha_winsor = 2.0,
                         current_weights = NULL,
                         turnover_penalty = 0.0,
                         active = FALSE) {

  # Input 검증
  if (!is.numeric(alpha) || is.null(names(alpha))) {
    stop("[mvo_weights] alpha must be named numeric vector")
  }
  if (!is.matrix(cov_matrix) || nrow(cov_matrix) != ncol(cov_matrix)) {
    stop("[mvo_weights] cov_matrix must be square")
  }
  if (length(bounds) != 2 || bounds[1] > bounds[2]) {
    stop("[mvo_weights] bounds invalid")
  }

  # Universe 정합 (alpha와 cov 종목 일치)
  common <- intersect(names(alpha), rownames(cov_matrix))
  if (length(common) == 0) {
    stop("[mvo_weights] alpha and cov_matrix share no tickers")
  }

  alpha_vec <- alpha[common]
  Sigma <- cov_matrix[common, common]
  D <- length(common)

  # Confidence vector (v6.1 R4)
  if (is.null(confidence)) {
    c_vec <- rep(1.0, D)
  } else {
    c_vec <- confidence[common]
    c_vec[is.na(c_vec)] <- 0.5  # missing → neutral
    c_vec <- pmax(pmin(c_vec, 1.0), 0.0)  # [0, 1] clip
  }
  names(c_vec) <- common

  # v2.1 Task#26: Alpha winsorization (±winsor σ)
  winsor_applied <- FALSE
  alpha_raw <- alpha_vec
  if (!is.null(alpha_winsor) && !is.na(alpha_winsor) && alpha_winsor > 0) {
    alpha_vec_w <- .winsorize_alpha(alpha_vec, winsor = alpha_winsor)
    winsor_applied <- !isTRUE(all.equal(as.numeric(alpha_vec_w), as.numeric(alpha_vec)))
    alpha_vec <- alpha_vec_w
  }

  # α̃_i = c_i · α̂_i (confidence-scaled alpha)
  alpha_tilde <- c_vec * alpha_vec

  # Forecast Uncertainty Penalty: FU(x, c) = Σ_i x_i² (1-c_i)²
  fu_diag <- psi * (1 - c_vec)^2

  # ── v2.3 Turnover penalty 활성 판정 ─────────────────────
  # 활성 조건: current_weights 제공 ∧ φ>0. current_weights 없이 φ>0 이면
  # long-only Σx=1 하에서 Σ|x_i−0|=1 상수 → argmax 불변이므로 기존 경로가
  # 그대로 정확해(근사 아님). 비활성 시 v2.2 QP 경로·반환 객체 완전 불변.
  tc_active <- !is.null(current_weights) && length(turnover_penalty) == 1L &&
    isTRUE(is.finite(turnover_penalty) && turnover_penalty > 0)
  w_prev <- NULL
  if (tc_active) {
    if (is.null(names(current_weights))) {
      stop("[mvo_weights] current_weights must be a named vector (Ticker align)")
    }
    # 유니버스 정렬: 신규 진입 종목은 이전 비중 0. 유니버스 탈락 종목의 강제
    # 청산 비용은 이 QP 밖(외생) — walk-forward A/B에서 양 arm 동일하게 발생.
    w_prev <- as.numeric(current_weights)[match(common, names(current_weights))]
    w_prev[is.na(w_prev)] <- 0
    names(w_prev) <- common
  }

  # quadprog formulation:
  #   min  (1/2) x'Dmat x - d_vec'x
  # MVO v2: max x'α̃ - (λ/2) x'Σx - ψ·x' diag((1-c)²) x
  #  ⇔ min (1/2) x'(λΣ + 2·ψ·diag((1-c)²))x - α̃'x
  Dmat <- lambda * Sigma + diag(2 * fu_diag)
  dvec <- as.vector(alpha_tilde)

  # Numerical stability: add small diagonal
  diag(Dmat) <- diag(Dmat) + 1e-8

  # Constraints:
  # 1'x = 1 (or 0 for active)  — equality
  # x >= bounds[1]              — inequality
  # -x >= -bounds[2]            — inequality (x <= bounds[2])
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(if (active) 0 else 1,
            rep(bounds[1], D),
            rep(-bounds[2], D))
  meq <- 1  # 1st constraint is equality

  # v2.1 Feasibility pre-check:
  #   target_sum=1 과 bounds[2] 일관성 + min_names × bounds[2] >= target_sum 확인.
  #   min_names 종목에 고르게 분배 시 종목당 target_sum/min_names_eff 필요.
  #   단, D >= min_names 이고 universe 전체가 bound 채우면 달성 가능하므로
  #   실제로 infeasible 한 경우는 min_names × bounds[2] < target_sum 이 엄격히 맞을 때.
  target_sum <- if (active) 0 else 1
  min_names_eff <- if (is.null(min_names) || is.na(min_names)) 1L else as.integer(min_names)

  # RF-O5 정합 (2026-07-18): min_names > max_names 는 모순 config — min_names 보충
  # (post-QP)이 max_names 절단 *뒤*에 실행되어 n_names 를 하드캡 위로 밀어 올린다.
  # 조용한 위반 대신 fail-loud infeasible 로 반환. (registry/NP4 기본 min<=max 는 무영향.)
  if (!is.null(max_names) && !is.na(max_names) && min_names_eff > max_names) {
    return(list(
      weights = NULL,
      method = "mvo",
      infeasible = TRUE,
      reason = sprintf("min_names (%d) > max_names (%d)", min_names_eff, as.integer(max_names)),
      infeasibility_report = list(
        violated_constraints = c("min_names", "max_names"),
        suggested_resolution = "Set min_names <= max_names"
      )
    ))
  }

  if (!active && min_names_eff > 1) {
    # min_names 종목에 고르게 분배 시 종목당 target_sum/min_names_eff 필요
    per_name_need <- target_sum / min_names_eff
    if (per_name_need > bounds[2] + 1e-9) {
      return(list(
        weights = NULL,
        method = "mvo",
        infeasible = TRUE,
        reason = sprintf("min_names_vs_upper_bound: %d × %.3f < %.3f",
                          min_names_eff, bounds[2], target_sum),
        infeasibility_report = list(
          violated_constraints = c("min_names", "weight_bounds_upper"),
          suggested_resolution = sprintf("bounds[2] >= %.4f or min_names <= %d",
                                          per_name_need, floor(target_sum / bounds[2]))
        )
      ))
    }
  }
  # Universe 크기 vs min_names
  if (!active && min_names_eff > D) {
    return(list(
      weights = NULL,
      method = "mvo",
      infeasible = TRUE,
      reason = sprintf("min_names (%d) > universe size (%d)", min_names_eff, D),
      infeasibility_report = list(
        violated_constraints = c("min_names", "universe_size"),
        suggested_resolution = "Expand universe or lower min_names"
      )
    ))
  }

  # Solve QP (1st attempt)
  # v2.3: tc_active 시 z=[x;u;v] 확장 QP. 등식 x−u+v=w_prev + u,v≥0 하에서
  #   min (1/2)x'Dmat_i x − α̃'x + φ·1'(u+v) 는 φ·Σ|x−w_prev| L1의 정확 표현
  #   (φ>0 최적해에서 min(u_i,v_i)=0 — u,v 동시 감소가 목적함수를 엄격 개선).
  #   u,v 블록의 eps ridge는 quadprog PD 요건용 — φ 대비 무시가능 스케일.
  mvo_solve <- function(lam_val) {
    Dmat_i <- lam_val * Sigma + diag(2 * fu_diag)
    diag(Dmat_i) <- diag(Dmat_i) + 1e-8
    if (!tc_active) {
      return(tryCatch(
        solve.QP(Dmat_i, dvec, Amat, bvec, meq = meq),
        error = function(e) NULL
      ))
    }
    eps_uv <- max(1e-10, 1e-6 * mean(diag(Dmat_i)))
    Dz <- diag(rep(eps_uv, 3 * D))
    Dz[seq_len(D), seq_len(D)] <- Dmat_i
    dz <- c(dvec, rep(-turnover_penalty, 2 * D))
    ID <- diag(D)
    Z0 <- matrix(0, D, D)
    Az <- cbind(
      c(rep(1, D), rep(0, 2 * D)),   # Σx = target (등식)
      rbind(ID, -ID, ID),            # x − u + v = w_prev (등식 D개)
      rbind(ID, Z0, Z0),             # x ≥ lb
      rbind(-ID, Z0, Z0),            # −x ≥ −ub
      rbind(Z0, ID, Z0),             # u ≥ 0
      rbind(Z0, Z0, ID)              # v ≥ 0
    )
    bz <- c(if (active) 0 else 1, as.numeric(w_prev),
            rep(bounds[1], D), rep(-bounds[2], D), rep(0, 2 * D))
    sol <- tryCatch(
      solve.QP(Dz, dz, Az, bz, meq = 1L + D),
      error = function(e) NULL
    )
    if (is.null(sol)) return(NULL)
    sol$solution <- sol$solution[seq_len(D)]
    sol
  }

  sol <- mvo_solve(lambda)
  lambda_used <- lambda

  if (is.null(sol)) {
    return(list(
      weights = NULL,
      method = "mvo",
      infeasible = TRUE,
      reason = "QP_solve_failed"
    ))
  }

  w_full <- sol$solution
  names(w_full) <- common

  # ── v2.1 min_names 1차 확보: QP 결과 종목수 < min_names 면 lambda 감소 재시도 ──
  lambda_retries <- 0
  active_names <- function(w) sum(abs(w) > 1e-6)
  if (!active && min_names_eff > 0) {
    while (active_names(w_full) < min_names_eff && lambda_retries < 4) {
      lambda_retries <- lambda_retries + 1
      lambda_used <- lambda_used * 0.5
      sol2 <- mvo_solve(lambda_used)
      if (is.null(sol2)) break
      w_full <- sol2$solution
      names(w_full) <- common
    }
  }

  # v2.3: QP 단계 회전 L1 (max_names/HHI post-stage 이전 시점) — 감사용
  trade_l1_qp <- if (tc_active) sum(abs(w_full - w_prev)) else NA_real_

  # max_names hard cap: top-N by |weight|
  max_names_truncated <- FALSE
  if (length(w_full) > max_names) {
    max_names_truncated <- TRUE
    top_idx <- order(abs(w_full), decreasing = TRUE)[seq_len(max_names)]
    w_sparse <- numeric(length(w_full))
    w_sparse[top_idx] <- w_full[top_idx]

    # Renormalize to maintain Σw = 1 (or 0)
    current_sum <- sum(w_sparse)

    if (!active && current_sum > 0) {
      w_sparse <- w_sparse * (target_sum / current_sum)
    }

    # Clip to bounds
    w_sparse <- pmax(pmin(w_sparse, bounds[2]), bounds[1])

    # Final renormalization
    if (!active && sum(w_sparse) > 0) {
      w_sparse <- w_sparse * (target_sum / sum(w_sparse))
    }

    names(w_sparse) <- common
    w_full <- w_sparse
  }

  # ── v2.1 min_names 최종 강제 (post-QP): 여전히 부족하면 top alpha로 보충 ──
  min_names_enforced <- FALSE
  if (!active && min_names_eff > 0 && active_names(w_full) < min_names_eff) {
    n_need <- min_names_eff - active_names(w_full)
    # 현재 active가 아닌 종목 중 alpha_tilde 상위 n_need 선택
    inactive_idx <- which(abs(w_full) <= 1e-6)
    if (length(inactive_idx) > 0) {
      alpha_inactive <- alpha_tilde[inactive_idx]
      add_order <- inactive_idx[order(alpha_inactive, decreasing = TRUE)]
      add_idx <- head(add_order, n_need)

      # 초기 baseline weight 부여 (target_sum / min_names_eff)
      baseline <- target_sum / min_names_eff
      baseline <- min(baseline, bounds[2])
      w_full[add_idx] <- baseline

      # 기존 active 종목의 weight를 비례 축소해서 합=target_sum 유지
      existing_idx <- setdiff(which(abs(w_full) > 1e-6), add_idx)
      excess <- sum(w_full) - target_sum
      if (excess > 0 && length(existing_idx) > 0) {
        scale_factor <- (sum(w_full[existing_idx]) - excess) / sum(w_full[existing_idx])
        scale_factor <- max(scale_factor, 0)
        w_full[existing_idx] <- w_full[existing_idx] * scale_factor
      }

      # bounds clip + 최종 재정규화
      w_full <- pmax(pmin(w_full, bounds[2]), bounds[1])
      if (!active && sum(w_full) > 0) {
        w_full <- w_full * (target_sum / sum(w_full))
      }
      min_names_enforced <- TRUE
    }
  }

  # ── v2.1 HHI cap projection ──
  # v2.3 (RF-O5 수리): max_names 절단이 있었던 경우 projection을 support(non-zero)
  # 부분벡터로 제한 — 전체벡터 호출은 .project_hhi absorber가 w=0 종목을 포함해
  # top-N 밖 비중 누출 = max_names 하드캡 위반 (FQ-057 NP4, task_1b9e50a3).
  # D ≤ max_names(절단 미발생)는 기존 전체벡터 경로 유지 → max_names 위반은 구조적
  # 불가(support ≤ D ≤ max_names)이며 일반 케이스는 OLD 와 bit-identical. 단
  # box-vertex 고정 포트폴리오는 .project_hhi Σw-보존 교정으로 OLD 와 소폭 상이(NEW 가
  # Σw=1 로 더 정확, header 참조).
  # support가 작아 cap 미도달(min HHI = 1/n_support > cap)이면 support 확장 대신
  # hhi_converged=FALSE + infeasibility_report로 정직 보고한다.
  hhi_applied <- FALSE
  hhi_converged <- TRUE
  if (!active && !is.null(hhi_cap) && !is.na(hhi_cap) && hhi_cap > 0) {
    current_hhi <- sum(w_full^2)
    if (current_hhi > hhi_cap + 1e-6) {
      proj_idx <- if (max_names_truncated) which(abs(w_full) > 1e-6) else seq_along(w_full)
      proj <- .project_hhi(w_full[proj_idx],
                            cap = hhi_cap,
                            bounds = bounds,
                            target_sum = target_sum,
                            step = 0.005,
                            max_iter = 500)
      w_full[proj_idx] <- proj$w
      names(w_full) <- common
      hhi_applied <- TRUE
      hhi_converged <- isTRUE(proj$converged)
    }
  }

  # Non-zero만 반환
  w_out <- w_full[abs(w_full) > 1e-6]
  n_final <- length(w_out)
  hhi_final <- sum(w_out^2)

  # Expected metrics (use RAW alpha for realistic expected_active_return)
  exp_ar <- sum(alpha_raw[names(w_out)] * w_out)
  exp_var <- as.numeric(t(w_out) %*% Sigma[names(w_out), names(w_out)] %*% w_out)
  exp_te <- sqrt(max(exp_var, 0))

  # Infeasibility summary (soft — weights still returned if non-NULL)
  infeasibility_report <- NULL
  violations <- character(0)
  if (!active && min_names_eff > 0 && n_final < min_names_eff) {
    violations <- c(violations, "min_names")
  }
  if (!is.null(hhi_cap) && !is.na(hhi_cap) && hhi_final > hhi_cap + 1e-4) {
    violations <- c(violations, "hhi_cap")
  }
  if (length(violations) > 0) {
    infeasibility_report <- list(
      violated_constraints = violations,
      n_final = n_final,
      min_names_required = min_names_eff,
      hhi_final = hhi_final,
      hhi_cap = hhi_cap,
      hhi_converged = hhi_converged,
      suggested_resolution = "Expand universe, raise bounds[2], or lower min_names/hhi_cap"
    )
  }

  out <- list(
    weights = w_out,
    method = sprintf("MVO_lambda_%.2f_psi_%.2f_phi_%.2f",
                     lambda_used, psi, turnover_penalty),
    expected_active_return = exp_ar,
    expected_tracking_error = exp_te,
    expected_information_ratio = if (exp_te > 1e-6) exp_ar / exp_te else NA,
    n_names = n_final,
    hhi = hhi_final,
    confidence_used = !is.null(confidence),
    mean_confidence = mean(c_vec[names(w_out)]),
    min_names_enforced = min_names_enforced,
    hhi_enforced = hhi_applied,
    winsor_applied = winsor_applied,
    lambda_retries = lambda_retries,
    lambda_used = lambda_used,
    infeasible = length(violations) > 0,
    reason = if (length(violations) > 0) paste(violations, collapse = ",") else NULL,
    infeasibility_report = infeasibility_report,
    selection_objective = "net_ir"  # R4 P3: Optimizer는 net_ir로 선택
  )
  # v2.3: TC 필드는 tc_active 시에만 부가 — 비활성 반환 객체는 v2.2와 identical 유지
  if (tc_active) {
    out$tc_penalty_active <- TRUE
    out$phi_used <- turnover_penalty
    out$trade_l1_qp <- trade_l1_qp
    out$trade_l1_final <- sum(abs(w_full - w_prev))
  }
  out
}

# ─── MVO Grid Search (lambda + phi 탐색) ─────────────────
# v2.3: current_weights 관통 추가 — 미제공(NULL) 시 phi_grid는 종전처럼 no-op.
mvo_grid_search <- function(alpha, cov_matrix,
                             lambda_grid = c(0.5, 1.0, 2.0, 5.0),
                             phi_grid = c(0.0, 0.2, 0.5),
                             bounds = c(0, 0.15),
                             max_names = 25,
                             min_names = 20L,
                             hhi_cap = 0.15,
                             alpha_winsor = 2.0,
                             current_weights = NULL) {
  results <- list()
  i <- 0
  for (lam in lambda_grid) {
    for (ph in phi_grid) {
      i <- i + 1
      r <- mvo_weights(alpha, cov_matrix,
                        lambda = lam, bounds = bounds, max_names = max_names,
                        min_names = min_names, hhi_cap = hhi_cap,
                        alpha_winsor = alpha_winsor,
                        current_weights = current_weights,
                        turnover_penalty = ph)
      r$lambda <- lam
      r$phi <- ph
      results[[i]] <- r
    }
  }

  # SR 최대 선택
  srs <- sapply(results, function(r) if (!is.null(r$expected_information_ratio)) r$expected_information_ratio else -Inf)
  best_idx <- which.max(srs)
  best <- results[[best_idx]]

  list(
    best = best,
    all_results = results,
    n_tested = length(results)
  )
}

cat("[mean_variance_optimizer.R] v2.4 (RF-O5 HHI-projection support-restrict + TC-aware phi*|x-x_prev| L1 into QP) Loaded. Functions:\n")
cat("  mvo_weights(alpha, cov, confidence=NULL, lambda=1.0, psi=0.3,\n")
cat("              bounds=c(0,0.15), max_names=25, min_names=20, hhi_cap=0.15, alpha_winsor=2.0,\n")
cat("              current_weights=NULL, turnover_penalty=0.0)\n")
cat("  mvo_grid_search(alpha, cov, lambda_grid, phi_grid, current_weights=NULL)\n")
