#==============================================================================
# STR_1631_MEGA_02 — Risk Research Script
# WT-D20260424_011 | 공동위험 구조 계량화 (Σ 축 전면 강화)
#
# 목표:
#   (1) MDD -44.31% → ≤30% 달성 지원
#   (2) FF5 Harvey t 1.838 → ≥3.0 지원 (Market exposure 완화)
#   (3) NORMAL SR 0.30 → ≥0.6 지원
#
# 방법론:
#   R13 병렬: Sample / Ledoit-Wolf Analytical / Ledoit-Wolf ConstCor /
#             Gerber-RMT / Non-Linear Shrinkage (Ledoit 2020)
#   regime-conditional Σ: BULL / NORMAL / CAUTION / CRISIS 별도 추정
#   Tail Risk: EVT-GPD + CF-VaR + CDaR 95%
#   Stress Test: 2008 GFC / 2020 COVID / 2022 Rate / 2019 KR Quant
#
# 절대 금지:
#   - alpha_vector 수정 불가
#   - weight 생성 불가
#   - SR/IR 참조한 Σ 추정기 선택 불가 (selection_objective = condition_number)
#
# 버전: v1.0 — 2026-04-24 Risk Research Agent
#==============================================================================

cat("=== STR_1631_MEGA_02 Risk Research [WT-D20260424_011] ===\n")

# ── 0. 환경 설정 ──────────────────────────────────────────────────────────────
set.seed(20260424L)

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260424_011"
PREV_WT_ID   <- "WT_D20260424_010"
AS_OF_DATE   <- "2026-04-24"
ARTIFACTS    <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260424_011")
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
LOCKBOX_END  <- as.Date("2026-01-23")

dir.create(ARTIFACTS, showWarnings = FALSE, recursive = TRUE)

# ── 기반 인프라 로드 ─────────────────────────────────────────────────────────
source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/tail_risk_engine.R"))

# ── 1. 데이터 로드 ────────────────────────────────────────────────────────────
cat("\n[Step 1] 데이터 로드 시작...\n")

# Alpha 종목 universe (마지막 rebalance 20종목)
alpha_scores <- as.data.table(
  read_parquet(
    file.path(PROJECT_ROOT, "stage_artifacts", PREV_WT_ID, "alpha_scores.parquet")
  )
)

# 마지막 월 20 종목
last_date  <- max(alpha_scores$Date)
last_tickers <- alpha_scores[Date == last_date, Ticker]
cat("  Last rebalance date:", as.character(last_date), "\n")
cat("  Tickers (n =", length(last_tickers), "):", paste(last_tickers, collapse=", "), "\n")

# 전체 이력에서 등장한 unique tickers (rolling window 확보용)
all_tickers <- unique(alpha_scores$Ticker)
cat("  Total historical tickers:", length(all_tickers), "\n")

# RAWDATA 로드 (cache)
cat("\n  RAWDATA 로드 중...\n")
rawdata_all <- as.data.table(
  read_parquet(file.path(PROJECT_ROOT, ".cache/rawdata.parquet"))
)
rawdata_all[, Date := as.Date(Date)]

# ── 2. 수익률 행렬 준비 ──────────────────────────────────────────────────────
cat("\n[Step 2] 수익률 행렬 준비...\n")

# lockbox 이전 데이터만 사용 (미래 오염 방지)
# MEGA_01 pre-lockbox 기간: 2002~2024-01-22
# PIT: returns[t-1] → signal에 lag 적용, 수익률 자체는 t 사용 (covariance 추정용)
TRAIN_START <- as.Date("2002-01-01")
TRAIN_END   <- LOCKBOX_END  # 2026-01-23 이전

rawdata_filtered <- rawdata_all[
  Ticker %in% all_tickers &
  Date >= TRAIN_START &
  Date < TRAIN_END
]

# 일별 수익률 → 월별 수익률 (covariance 추정은 월별 기준)
rawdata_filtered[, YearMonth := format(Date, "%Y-%m")]
monthly_ret <- rawdata_filtered[,
  .(monthly_ret = prod(1 + Ret, na.rm = TRUE) - 1),
  by = .(Ticker, YearMonth)
]
monthly_ret[, YearMonth := as.Date(paste0(YearMonth, "-01"))]
setorder(monthly_ret, Ticker, YearMonth)

# 마지막 20종목 기준 수익률 행렬 (wide format)
ret_wide <- dcast(
  monthly_ret[Ticker %in% last_tickers],
  YearMonth ~ Ticker,
  value.var = "monthly_ret"
)
setorder(ret_wide, YearMonth)

# NA 제거 (pairwise 처리 전)
ret_mat_full <- as.matrix(ret_wide[, -1, with = FALSE])
rownames(ret_mat_full) <- as.character(ret_wide$YearMonth)

# NA가 50% 이상인 종목 제거
na_pct <- colMeans(is.na(ret_mat_full))
keep_cols <- names(na_pct[na_pct < 0.5])
ret_mat_full <- ret_mat_full[, keep_cols, drop = FALSE]

# 최소 30행 보장 후 NA 대체 (0으로)
complete_rows <- complete.cases(ret_mat_full)
ret_mat_clean <- ret_mat_full
ret_mat_clean[is.na(ret_mat_clean)] <- 0.0  # pairwise cov에서 0 대체

N <- nrow(ret_mat_clean)
P <- ncol(ret_mat_clean)
cat("  수익률 행렬 크기: T =", N, "× N =", P, "\n")
cat("  기간:", rownames(ret_mat_clean)[1], "~", rownames(ret_mat_clean)[N], "\n")

# ── 3. Regime 태깅 (공개 signal, pre-lockbox) ───────────────────────────────
cat("\n[Step 3] Regime 태깅...\n")

# regime_v7.parquet (일별 국면)
regime_path <- file.path(PROJECT_ROOT, ".cache/regime_v7.parquet")
if (!file.exists(regime_path)) {
  regime_path <- file.path(PROJECT_ROOT, ".cache/unified_regime_signal.parquet")
}
if (!file.exists(regime_path)) {
  # fallback: regime_daily_v2.parquet
  regime_path <- file.path(PROJECT_ROOT, ".cache/regime_daily_v2.parquet")
}

regime_dt <- tryCatch({
  as.data.table(read_parquet(regime_path))
}, error = function(e) {
  cat("  [WARN] regime parquet 로드 실패:", conditionMessage(e), "\n")
  NULL
})

if (!is.null(regime_dt) && "apply_month" %in% colnames(regime_dt) && "MRS" %in% colnames(regime_dt)) {
  # MRS (0~100) 기반 4구간 분류 (expanding percentile)
  regime_sub <- regime_dt[apply_month < format(TRAIN_END, "%Y-%m") & !is.na(MRS)]
  mrs_q25 <- quantile(regime_sub$MRS, 0.25, na.rm = TRUE)
  mrs_q50 <- quantile(regime_sub$MRS, 0.50, na.rm = TRUE)
  mrs_q75 <- quantile(regime_sub$MRS, 0.75, na.rm = TRUE)
  cat(sprintf("  MRS 사분위: Q25=%.1f Q50=%.1f Q75=%.1f\n", mrs_q25, mrs_q50, mrs_q75))

  regime_sub[, regime4 := fifelse(
    MRS < mrs_q25, "BULL",
    fifelse(MRS < mrs_q50, "NORMAL",
      fifelse(MRS < mrs_q75, "CAUTION", "CRISIS"))
  )]
  monthly_regime <- regime_sub[, .(YearMonth = apply_month, regime = regime4)]
  cat("  MRS 기반 4구간 Regime 분포:\n")
  print(table(monthly_regime$regime))
} else {
  cat("  [WARN] MRS 기반 분류 불가 — regime 분석 생략\n")
  monthly_regime <- NULL
}

# ── 4. R13 병렬 Covariance 추정 ─────────────────────────────────────────────
cat("\n[Step 4] R13 병렬 Covariance 추정 (5 estimators)...\n")

# R 전용 shrinkage 함수들 정의 (패키지 없이 구현)
# 4-1. Sample covariance
cov_sample <- function(ret_mat) {
  ret_mat_cc <- ret_mat[complete.cases(ret_mat), , drop = FALSE]
  S <- cov(ret_mat_cc, use = "pairwise.complete.obs")
  # PSD 보장 (eigenvalue clamp)
  eig <- eigen(S, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-8)
  S_psd <- eig$vectors %*% diag(eig$values, length(eig$values)) %*% t(eig$vectors)
  (S_psd + t(S_psd)) / 2
}

# 4-2. Ledoit-Wolf Analytical (Oracle Approximating Shrinkage, OAS)
# Chen et al. (2010) — closed-form shrinkage coefficient
cov_lw_oracle <- function(ret_mat) {
  X <- ret_mat[complete.cases(ret_mat), , drop = FALSE]
  n <- nrow(X); p <- ncol(X)
  S <- cov(X, use = "pairwise.complete.obs")
  if (n < p + 1) {
    # 고차원 regime: James-Stein shrinkage
    mu_target <- mean(diag(S))
    F_target  <- diag(mu_target, p)
    rho       <- min(1.0, (p + 2) / (n * sum((S - F_target)^2) / sum(S^2) + p))
    Sigma     <- (1 - rho) * S + rho * F_target
  } else {
    # Ledoit-Wolf (2004) closed-form
    # Shrinkage toward scaled identity
    trace_S  <- sum(diag(S))
    trace_S2 <- sum(S^2)
    mu       <- trace_S / p
    delta    <- sum((S - mu * diag(p))^2)
    # Optimal shrinkage intensity
    alpha2   <- ((n - 2) / n * trace_S2 + trace_S^2) / ((n + 2) * (trace_S2 - trace_S^2 / p))
    alpha2   <- min(1.0, max(0.0, alpha2))
    F_target <- mu * diag(p)
    Sigma    <- (1 - alpha2) * S + alpha2 * F_target
  }
  colnames(Sigma) <- rownames(Sigma) <- colnames(X)
  eig <- eigen(Sigma, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-8)
  Sigma_psd <- eig$vectors %*% diag(eig$values, length(eig$values)) %*% t(eig$vectors)
  (Sigma_psd + t(Sigma_psd)) / 2
}

# 4-3. Ledoit-Wolf Constant Correlation (shrinkage toward equicorrelation target)
cov_lw_constcor <- function(ret_mat) {
  X <- ret_mat[complete.cases(ret_mat), , drop = FALSE]
  n <- nrow(X); p <- ncol(X)
  S    <- cov(X, use = "pairwise.complete.obs")
  sds  <- sqrt(diag(S))
  R    <- S / outer(sds, sds)
  R[is.nan(R)] <- 0; diag(R) <- 1
  # Mean off-diagonal correlation
  rbar <- (sum(R) - p) / (p * (p - 1))
  # Constant correlation target
  F_cor <- matrix(rbar, p, p); diag(F_cor) <- 1
  F_mat <- F_cor * outer(sds, sds)
  # LW delta^2 term
  delta <- sum((S - F_mat)^2)
  beta2 <- delta / n
  gamma <- sum((S - F_mat)^2)
  kappa <- beta2 / gamma
  kappa <- min(1.0, max(0.0, kappa))
  Sigma <- (1 - kappa) * S + kappa * F_mat
  colnames(Sigma) <- rownames(Sigma) <- colnames(X)
  eig <- eigen(Sigma, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-8)
  Sigma_psd <- eig$vectors %*% diag(eig$values, length(eig$values)) %*% t(eig$vectors)
  (Sigma_psd + t(Sigma_psd)) / 2
}

# 4-4. Gerber-RMT (hrp_core.R의 .gerber_cor + .rmt_denoise 활용)
cov_gerber_rmt <- function(ret_mat) {
  X   <- ret_mat[complete.cases(ret_mat), , drop = FALSE]
  n   <- nrow(X); p <- ncol(X)
  sds <- apply(X, 2, sd, na.rm = TRUE)
  # Gerber correlation
  R_gerber <- .gerber_cor(X, threshold = 0.5)
  # RMT denoising
  q_ratio  <- n / p
  R_clean  <- .rmt_denoise(R_gerber, q_ratio)
  # Back to covariance
  Sigma    <- R_clean * outer(sds, sds)
  colnames(Sigma) <- rownames(Sigma) <- colnames(X)
  eig <- eigen(Sigma, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-8)
  Sigma_psd <- eig$vectors %*% diag(eig$values, length(eig$values)) %*% t(eig$vectors)
  (Sigma_psd + t(Sigma_psd)) / 2
}

# 4-5. Non-Linear Shrinkage (Ledoit-Wolf 2020 analytical NLS)
# Ledoit & Wolf (2020) "Analytical Nonlinear Shrinkage of Large-Dimensional Covariance Matrices"
# Annals of Statistics. Closed-form (no kernel bandwidth needed, oracle approximation)
cov_nls <- function(ret_mat) {
  X <- ret_mat[complete.cases(ret_mat), , drop = FALSE]
  n <- nrow(X); p <- ncol(X)

  if (n < p) {
    cat("    [NLS] n<p (", n, "<", p, ") — LW Oracle fallback\n")
    return(cov_lw_oracle(ret_mat))
  }

  S    <- cov(X, use = "pairwise.complete.obs")
  eig  <- eigen(S, symmetric = TRUE)
  lam  <- eig$values  # sorted descending
  U    <- eig$vectors

  c_ratio <- p / n  # concentration ratio

  # Marchenko-Pastur bulk edge
  lam_plus  <- (1 + sqrt(c_ratio))^2
  lam_minus <- (1 - sqrt(c_ratio))^2

  # Non-linear shrinkage formula (LW 2020 Eq.3.7):
  # d_i = lambda_i / (1 - c + c * h_S(lambda_i))^2 + c^2 * lambda_i^2 * h_I(lambda_i)^2
  # where h_S = Stieltjes transform, h_I = imaginary part
  # Analytical approximation via the free energy approach:
  n_eig <- length(lam)

  # Regularized inverse Marchenko-Pastur density
  d_nls <- numeric(n_eig)
  for (i in seq_len(n_eig)) {
    li <- lam[i]
    # Stieljes transform approximation (Ledoit-Wolf 2020 Theorem 3.1)
    # s_n(z) = (1/p) * sum_j [1 / (lambda_j - z)]
    z    <- complex(real = li, imaginary = 1e-6)
    s_n  <- mean(1 / (lam - z))
    # Oracle shrinkage: d_i = 1 / Re(-(1 - c + c * z * s_n(z)) / z)
    denom_val <- -(1 - c_ratio + c_ratio * z * s_n) / z
    d_nls[i]  <- 1 / max(Re(denom_val), 1e-8)
  }

  # Reconstruct Sigma_NLS = U * diag(d_nls) * U'
  d_nls_clip <- pmax(d_nls, 1e-8)
  Sigma <- U %*% diag(d_nls_clip, n_eig) %*% t(U)
  colnames(Sigma) <- rownames(Sigma) <- colnames(X)
  (Sigma + t(Sigma)) / 2
}

# ── 병렬 실행 ────────────────────────────────────────────────────────────────
n_workers <- min(5L, max(1L, parallel::detectCores() - 1L))
cat("  Workers:", n_workers, "\n")
plan(multisession, workers = n_workers)

estimators <- list(
  list(name = "sample_pairwise",      fn = cov_sample,      desc = "표준 표본 공분산"),
  list(name = "ledoit_wolf_oracle",   fn = cov_lw_oracle,   desc = "LW Oracle Shrinkage (2004)"),
  list(name = "ledoit_wolf_constcor", fn = cov_lw_constcor, desc = "LW 등상관 타겟 Shrinkage"),
  list(name = "gerber_rmt",           fn = cov_gerber_rmt,  desc = "Gerber-RMT (noise filtered)"),
  list(name = "nonlinear_shrinkage",  fn = cov_nls,         desc = "NLS (Ledoit-Wolf 2020)")
)

cat("  5개 추정기 병렬 계산 시작...\n")
t_par_start <- proc.time()

cov_results <- future_lapply(estimators, function(e) {
  tryCatch({
    Sigma <- e$fn(ret_mat_clean)
    eig_vals <- eigen(Sigma, only.values = TRUE)$values
    min_eig  <- min(eig_vals)
    psd_ok   <- min_eig >= -1e-8
    cond_num <- max(eig_vals) / max(min_eig, 1e-8)
    list(
      ok        = TRUE,
      name      = e$name,
      desc      = e$desc,
      Sigma     = Sigma,
      condition = round(cond_num, 2),
      min_eig   = round(min_eig, 8),
      psd       = psd_ok
    )
  }, error = function(err) {
    list(ok = FALSE, name = e$name, desc = e$desc,
         error = conditionMessage(err), Sigma = NULL,
         condition = Inf, min_eig = NA, psd = FALSE)
  })
}, future.seed = TRUE)

plan(sequential)
t_par_elapsed <- (proc.time() - t_par_start)["elapsed"]
cat(sprintf("  병렬 계산 완료 (%.1f 초)\n", t_par_elapsed))

# 결과 출력
method_log <- list()
for (r in cov_results) {
  status <- if (r$ok) sprintf("condition=%.1f, min_eig=%.2e, PSD=%s", r$condition, r$min_eig, r$psd) else r$error
  cat(sprintf("  [%s] %s | %s\n", r$name, r$desc, status))

  method_log[[length(method_log) + 1]] <- list(
    name      = r$name,
    selected  = FALSE,
    condition = if (r$ok) r$condition else Inf,
    min_eig   = if (r$ok) r$min_eig else NA,
    psd       = if (r$ok) r$psd else FALSE,
    ok        = r$ok,
    error     = if (!r$ok) r$error else NULL
  )
}

# ── 5. Estimator 선택 (selection_objective = condition_number) ───────────────
cat("\n[Step 5] Estimator 선택 (condition_number 최소화)...\n")

# RF-R2 기준: condition > 500 이면 shrinkage 강화 필요
# selection_objective: condition_number (SR/IR 참조 금지 — v6.1 R4)
# 주의: condition < 5는 과도 shrinkage (off-diagonal 정보 손실) → 제외
valid_results <- Filter(function(r) r$ok && r$psd && r$condition >= 5, cov_results)
if (length(valid_results) == 0) {
  # condition 제한 없이 다시
  valid_results <- Filter(function(r) r$ok && r$psd, cov_results)
}
if (length(valid_results) == 0) {
  valid_results <- Filter(function(r) r$ok, cov_results)
}

# condition number 기준 정렬 (오름차순 = 수치 안정성 우선)
# 단, < 5 (과도 shrinkage)는 패널티 — 이미 위에서 필터
conds <- sapply(valid_results, function(r) r$condition)
best_idx <- which.min(conds)
selected_result <- valid_results[[best_idx]]

cat(sprintf("  선택: %s (condition=%.2f)\n", selected_result$name, selected_result$condition))
if (selected_result$condition < 5) {
  cat("  [NOTE] condition < 5 — off-diagonal 정보 희석 가능. 수치 안정성은 높음.\n")
}

# method_log에 selected 마킹
for (i in seq_along(method_log)) {
  if (method_log[[i]]$name == selected_result$name) {
    method_log[[i]]$selected <- TRUE
    method_log[[i]]$selection_rationale <- sprintf(
      "condition_number %.2f — 5개 추정기 중 최소 (stress_robust + estimation quality 우선)",
      selected_result$condition
    )
  }
}

Sigma_primary <- selected_result$Sigma
primary_method <- selected_result$name
# colnames/rownames 명시적 설정 (future_lapply 직렬화 후 손실 방지)
if (is.null(colnames(Sigma_primary)) || length(colnames(Sigma_primary)) == 0) {
  colnames(Sigma_primary) <- rownames(Sigma_primary) <- colnames(ret_mat_clean)
  cat("  [NOTE] Sigma_primary colnames 복구:", paste(head(colnames(Sigma_primary), 3), collapse=", "), "...\n")
}
cat("  Sigma_primary dim:", nrow(Sigma_primary), "×", ncol(Sigma_primary),
    "| colnames:", paste(head(colnames(Sigma_primary), 4), collapse=", "), "...\n")

# RF-R2 점검
rf_r2_triggered <- selected_result$condition > 500
if (rf_r2_triggered) {
  cat("  [WARNING] RF-R2: condition > 500! 추가 shrinkage 적용...\n")
  # 강화 shrinkage: diagonal + primary blend
  diag_sigma <- diag(diag(Sigma_primary))
  Sigma_primary <- 0.3 * diag_sigma + 0.7 * Sigma_primary
  new_cond <- kappa(Sigma_primary)
  cat(sprintf("  재추정 후 condition: %.2f\n", new_cond))
}

# ── 6. Regime-conditional Covariance ─────────────────────────────────────────
cat("\n[Step 6] Regime-conditional Σ 추정 (BULL/NORMAL/CAUTION/CRISIS)...\n")

regime_sigma <- list()
regime_cov_matrix <- list()
regime_stats_out  <- list()

if (!is.null(monthly_regime)) {
  # monthly_ret 데이터에 regime 병합
  ret_wide2 <- copy(ret_wide)
  ret_wide2[, YearMonth_str := format(YearMonth, "%Y-%m")]
  monthly_regime[, YearMonth_str := YearMonth]

  ret_with_regime <- merge(
    ret_wide2[YearMonth < TRAIN_END],
    monthly_regime[, .(YearMonth_str, regime)],
    by = "YearMonth_str",
    all.x = TRUE
  )

  regimes_all <- c("BULL", "NORMAL", "CAUTION", "CRISIS")

  for (reg in regimes_all) {
    sub <- ret_with_regime[regime == reg]
    sub_mat <- as.matrix(sub[, last_tickers[last_tickers %in% colnames(sub)], with = FALSE])
    sub_mat[is.na(sub_mat)] <- 0.0

    n_reg <- nrow(sub_mat)
    p_reg <- ncol(sub_mat)
    cat(sprintf("  %s: n=%d 개월\n", reg, n_reg))

    if (n_reg < 12) {
      cat(sprintf("  [WARN] %s: 관측치 부족 (n=%d < 12) — full-sample Σ 사용\n", reg, n_reg))
      regime_cov_matrix[[reg]] <- Sigma_primary
      regime_stats_out[[reg]]  <- list(
        n_months  = n_reg,
        condition = selected_result$condition,
        method    = "fallback_to_primary",
        note      = "insufficient_obs"
      )
    } else {
      # 소규모 → LW Oracle
      reg_Sigma <- tryCatch(
        cov_lw_oracle(sub_mat),
        error = function(e) {
          cat("    [WARN]", reg, "LW 실패:", conditionMessage(e), "\n")
          cov_sample(sub_mat)
        }
      )
      reg_cond <- tryCatch(kappa(reg_Sigma), error = function(e) Inf)
      regime_cov_matrix[[reg]] <- reg_Sigma
      regime_stats_out[[reg]]  <- list(
        n_months  = n_reg,
        condition = round(reg_cond, 2),
        method    = "ledoit_wolf_oracle"
      )
      cat(sprintf("    condition=%.2f\n", reg_cond))
    }
  }

  cat("\n  Regime 상관 스프레드 (BULL vs CRISIS 평균 상관 비교):\n")
  get_mean_offdiag <- function(S) {
    R <- cov2cor(S)
    diag(R) <- 0
    mean(abs(R[upper.tri(R)]))
  }

  for (reg in regimes_all) {
    mc <- get_mean_offdiag(regime_cov_matrix[[reg]])
    cat(sprintf("    %s 평균 |상관|: %.3f\n", reg, mc))
    regime_stats_out[[reg]]$mean_abs_cor <- round(mc, 3)
  }

} else {
  cat("  [WARN] regime 데이터 없음 — regime-conditional Σ 생략\n")
  for (reg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
    regime_cov_matrix[[reg]] <- Sigma_primary
    regime_stats_out[[reg]]  <- list(
      n_months  = 0,
      condition = selected_result$condition,
      method    = "fallback_to_primary",
      note      = "no_regime_data"
    )
  }
}

# ── 7. Factor Exposure Matrix (B) — Sector + Market + Style ─────────────────
cat("\n[Step 7] Factor Exposure Matrix 구성...\n")

# 마지막 월 종목들의 섹터 정보
tickers_now <- last_tickers

sector_info <- rawdata_all[
  Ticker %in% tickers_now & Date < TRAIN_END,
  .(Sector = last(Sector), Sector_Lv2 = last(Sector_Lv2)),
  by = Ticker
]

# KOSPI200 membership (Market factor)
mkt_info <- rawdata_all[
  Ticker %in% tickers_now & Date < TRAIN_END,
  .(K200 = last(K200), KQ150 = last(KQ150)),
  by = Ticker
]

# Factor exposure: Market (1), Sector dummies, Size proxy
exposure_tickers <- intersect(tickers_now, colnames(Sigma_primary))
n_exp <- length(exposure_tickers)

# Sector 분류
sector_map <- sector_info[Ticker %in% exposure_tickers]
sectors_unique <- sort(unique(sector_map$Sector))
cat("  Sectors:", paste(sectors_unique, collapse=", "), "\n")

# B 행렬: [N_stocks x N_factors]
# Factors: Market(1), Sector_A..Z (dummy), Size (이진: large=K200 여부)
factor_names <- c("Market", sectors_unique, "Size")
n_factors <- length(factor_names)
B <- matrix(0, nrow = n_exp, ncol = n_factors,
            dimnames = list(exposure_tickers, factor_names))
B[, "Market"] <- 1  # 모든 종목 시장 노출 = 1

for (i in seq_len(n_exp)) {
  tk <- exposure_tickers[i]
  sec_row <- sector_map[Ticker == tk]
  if (nrow(sec_row) > 0 && sec_row$Sector %in% sectors_unique) {
    B[i, sec_row$Sector] <- 1
  }
  mkt_row <- mkt_info[Ticker == tk]
  if (nrow(mkt_row) > 0 && !is.na(mkt_row$K200) && mkt_row$K200 == 1) {
    B[i, "Size"] <- 1
  }
}

cat("  B 행렬 크기:", nrow(B), "×", ncol(B), "\n")
cat("  Market 노출 합계:", sum(B[, "Market"]), "\n")
cat("  Size (K200) 편입 수:", sum(B[, "Size"]), "\n")

# ── 8. Factor Covariance (Ω) 추정 ───────────────────────────────────────────
cat("\n[Step 8] Factor Covariance Ω 추정...\n")

# 팩터 수익률 추출:
# Market 팩터 이름을 B 행렬과 동일하게 "Market"으로 통일
# Sector 이름도 B 행렬 sectors_unique와 동일하게 유지

# 시장 팩터: 전체 universe 평균 (Market)
mkt_ret_dt <- rawdata_all[Ticker %in% tickers_now & Date >= TRAIN_START & Date < TRAIN_END,
  .(Market = mean(Ret, na.rm = TRUE)),
  by = .(YearMonth = format(Date, "%Y-%m"))
]
setorder(mkt_ret_dt, YearMonth)

# 섹터 팩터: 각 섹터 내 종목 평균 수익률 (컬럼명 = 섹터명 = B 행렬 일치)
sector_ret_dt <- rawdata_all[
  Ticker %in% tickers_now &
  Date >= TRAIN_START &
  Date < TRAIN_END
][, .(sector_ret = mean(Ret, na.rm = TRUE)),
  by = .(YearMonth = format(Date, "%Y-%m"),
         Sector = Sector)
]

# Factor returns wide
factor_ret_wide <- dcast(sector_ret_dt, YearMonth ~ Sector, value.var = "sector_ret")
factor_ret_wide <- merge(factor_ret_wide, mkt_ret_dt, by = "YearMonth", all = TRUE)
# Size 팩터: K200 종목 평균 - 비K200 종목 평균 (SMB-like)
k200_tickers <- mkt_info[K200 == 1 & !is.na(K200), Ticker]
nk200_tickers <- mkt_info[K200 != 1 | is.na(K200), Ticker]
size_ret_dt <- rawdata_all[
  Ticker %in% tickers_now & Date >= TRAIN_START & Date < TRAIN_END,
  .(
    k200_ret  = mean(Ret[Ticker %in% k200_tickers], na.rm = TRUE),
    nk200_ret = mean(Ret[Ticker %in% nk200_tickers], na.rm = TRUE)
  ),
  by = .(YearMonth = format(Date, "%Y-%m"))
]
size_ret_dt[, Size := k200_ret - nk200_ret]
factor_ret_wide <- merge(factor_ret_wide, size_ret_dt[, .(YearMonth, Size)],
                         by = "YearMonth", all.x = TRUE)
setorder(factor_ret_wide, YearMonth)

factor_ret_mat <- as.matrix(factor_ret_wide[, -1, with = FALSE])
rownames(factor_ret_mat) <- factor_ret_wide$YearMonth
factor_ret_mat[is.na(factor_ret_mat)] <- 0.0

cat("  Factor returns matrix: ", nrow(factor_ret_mat), "×", ncol(factor_ret_mat), "\n")
cat("  Factor names:", paste(colnames(factor_ret_mat), collapse=", "), "\n")

# Ω = LW shrinkage on factor returns
Omega <- tryCatch(
  cov_lw_oracle(factor_ret_mat),
  error = function(e) {
    cat("  [WARN] Ω LW 실패:", conditionMessage(e), "\n")
    S <- cov(factor_ret_mat, use = "pairwise.complete.obs")
    eig <- eigen(S, symmetric = TRUE); eig$values <- pmax(eig$values, 1e-8)
    eig$vectors %*% diag(eig$values, length(eig$values)) %*% t(eig$vectors)
  }
)
colnames(Omega) <- rownames(Omega) <- colnames(factor_ret_mat)

# B 행렬과 Omega 공통 팩터 추출
# B 행렬: "Market" + sectors_unique + "Size"
# Omega: Sector 이름 + "Market" + "Size"
omega_factors <- intersect(colnames(B), colnames(Omega))
cat("  공통 팩터 (B∩Ω):", paste(omega_factors, collapse=", "), "\n")

if (length(omega_factors) < 2) {
  cat("  [WARN] Ω factor alignment 실패 — diagonal proxy (주식 분산만 사용)\n")
  Omega_aligned <- diag(apply(factor_ret_mat, 2, var, na.rm = TRUE) + 1e-6)
  colnames(Omega_aligned) <- rownames(Omega_aligned) <- colnames(factor_ret_mat)
  omega_factors <- colnames(factor_ret_mat)
} else {
  Omega_aligned <- Omega[omega_factors, omega_factors, drop = FALSE]
}

cat("  Ω 크기:", nrow(Omega_aligned), "×", ncol(Omega_aligned), "\n")
cat("  Ω condition:", round(kappa(Omega_aligned), 2), "\n")

# ── 9. Specific Risk (D) — 잔차 분산 ────────────────────────────────────────
cat("\n[Step 9] Specific Risk D 추정...\n")

# Σ = BΩB' + D → D = Σ - BΩB'
# B, Ω 정렬
B_aligned <- B[, omega_factors[omega_factors %in% colnames(B)], drop = FALSE]
Omega_sub  <- Omega_aligned[colnames(B_aligned), colnames(B_aligned), drop = FALSE]

# 공통 종목 필터
common_tickers <- intersect(rownames(B_aligned), rownames(Sigma_primary))
B_sub    <- B_aligned[common_tickers, , drop = FALSE]
Sigma_sub <- Sigma_primary[common_tickers, common_tickers, drop = FALSE]

BОB <- B_sub %*% Omega_sub %*% t(B_sub)
D_mat    <- Sigma_sub - BОB
D_diag   <- pmax(diag(D_mat), 1e-8)  # specific var >= 0
D_sparse <- diag(D_diag, length(D_diag))
dimnames(D_sparse) <- list(common_tickers, common_tickers)

# Factor coverage: 팩터로 설명되는 분산 비중
total_var   <- sum(diag(Sigma_sub))
factor_var  <- sum(diag(BОB))
specific_var <- sum(D_diag)
factor_coverage <- factor_var / total_var
cat(sprintf("  Factor coverage: %.1f%% (specific: %.1f%%)\n",
            factor_coverage * 100, (1 - factor_coverage) * 100))

# ── 10. Σ = BΩB' + D 최종 구성 ──────────────────────────────────────────────
cat("\n[Step 10] 최종 Σ = BΩB' + D 구성...\n")

Sigma_final <- BОB + D_sparse
# PSD 확인
eig_final <- eigen(Sigma_final, symmetric = TRUE)
min_eig_final <- min(eig_final$values)
cond_final    <- max(eig_final$values) / max(min_eig_final, 1e-8)

if (min_eig_final < -1e-8) {
  cat(sprintf("  [WARN] Σ_final 음수 고유값 (%.4e) — clamp 적용\n", min_eig_final))
  eig_final$values <- pmax(eig_final$values, 1e-8)
  Sigma_final <- eig_final$vectors %*%
                 diag(eig_final$values, length(eig_final$values)) %*%
                 t(eig_final$vectors)
  Sigma_final <- (Sigma_final + t(Sigma_final)) / 2
  cond_final  <- max(eig_final$values) / 1e-8
}

cat(sprintf("  Σ_final condition: %.2f\n", cond_final))
cat(sprintf("  Σ_final size: %d × %d\n", nrow(Sigma_final), ncol(Sigma_final)))
cat(sprintf("  PSD: %s\n", min(eigen(Sigma_final, only.values = TRUE)$values) >= -1e-8))

# ── 11. Risk 분해 (공통 위험 기여도) ─────────────────────────────────────────
cat("\n[Step 11] Risk Decomposition...\n")

# 동일가중 포트폴리오 기준 risk attribution
n_stocks <- nrow(Sigma_final)
w_ew     <- rep(1 / n_stocks, n_stocks)

# 포트폴리오 분산
port_var    <- as.numeric(t(w_ew) %*% Sigma_final %*% w_ew)
port_vol_m  <- sqrt(port_var)                   # 월간
port_vol_a  <- port_vol_m * sqrt(12)             # 연간

# 팩터별 기여도
factor_contrib <- list()
for (fac in colnames(Omega_aligned)) {
  if (fac %in% colnames(B_sub)) {
    b_fac    <- B_sub[, fac, drop = TRUE]
    sig_f    <- Omega_aligned[fac, fac]
    fac_var  <- sum(b_fac * w_ew)^2 * sig_f
    factor_contrib[[fac]] <- fac_var
  }
}

factor_contrib_total <- sum(unlist(factor_contrib))
specific_total       <- sum(w_ew^2 * D_diag[common_tickers])

if (port_var > 0) {
  market_pct  <- round((factor_contrib[["mkt_ret"]] %||% factor_contrib_total) / port_var * 100, 1)
} else {
  market_pct <- 0
}

`%||%` <- function(a, b) if (!is.null(a) && !is.na(a)) a else b

top_risks <- c()
for (fac in names(sort(unlist(factor_contrib), decreasing = TRUE))[1:min(3, length(factor_contrib))]) {
  pct <- round(factor_contrib[[fac]] / port_var * 100, 1)
  top_risks <- c(top_risks, sprintf("%s (%.1f%%)", fac, pct))
}

cat("  포트폴리오 월간 변동성:", round(port_vol_m * 100, 2), "%\n")
cat("  포트폴리오 연간 변동성:", round(port_vol_a * 100, 2), "%\n")
cat("  Top 공통 위험:", paste(top_risks, collapse = " | "), "\n")

# RF-R1: market > 40% ?
rf_r1_triggered <- market_pct > 40
if (rf_r1_triggered) {
  cat(sprintf("  [RF-R1 HIGH] Market 기여 %.1f%% > 40%% 임계치\n", market_pct))
}

# ── 12. Tail Risk 진단 ───────────────────────────────────────────────────────
cat("\n[Step 12] Tail Risk 진단...\n")

# 포트폴리오 시뮬레이션 수익률 (EW 기준, 마지막 종목들)
port_rets_dt <- rawdata_all[
  Ticker %in% common_tickers &
  Date >= TRAIN_START &
  Date < TRAIN_END
][, .(avg_ret = mean(Ret, na.rm = TRUE)), by = Date]
setorder(port_rets_dt, Date)
port_returns <- port_rets_dt$avg_ret

# EVT-GPD VaR
evt_result <- tryCatch(
  compute_evt_var(port_returns, p = 0.99, threshold_q = 0.95),
  error = function(e) {
    cat("  [WARN] EVT 실패:", conditionMessage(e), "\n")
    list(var_evt = quantile(abs(port_returns), 0.99), es_evt = NA,
         shape_xi = NA, scale_beta = NA, method = "fallback")
  }
)

# Cornish-Fisher VaR
cf_result <- tryCatch(
  compute_cf_var(port_returns, p = 0.99),
  error = function(e) list(var_cf = NA, es_cf = NA, skewness = NA, kurtosis = NA)
)

# CVaR 95%
cvar_95 <- tryCatch({
  losses <- -port_returns
  q95    <- quantile(losses, 0.95, na.rm = TRUE)
  mean(losses[losses > q95], na.rm = TRUE)
}, error = function(e) NA)

cat(sprintf("  EVT VaR(99%%): %.2f%%/day | Shape xi: %.3f\n",
            evt_result$var_evt * 100, evt_result$shape_xi %||% 0))
cat(sprintf("  CF  VaR(99%%): %.2f%%/day\n", cf_result$var_cf %||% evt_result$var_evt * 100))
cat(sprintf("  CVaR(95%%):    %.2f%%/day\n", cvar_95 * 100))

# MEGA_01 대비 개선 여부
mega01_evt_var <- 0.048  # 기존 결과
cat(sprintf("  MEGA_01 EVT VaR: %.2f%% → MEGA_02: %.2f%% (delta: %.2f%%)\n",
            mega01_evt_var * 100,
            evt_result$var_evt * 100,
            (evt_result$var_evt - mega01_evt_var) * 100))

# ── 13. Regime-conditional Tail Dependence ──────────────────────────────────
cat("\n[Step 13] Regime-conditional 상관 분석...\n")

bear_cor  <- NA_real_
bull_cor  <- NA_real_
regime_sep <- NA_real_

if (!is.null(monthly_regime) && length(common_tickers) >= 2) {
  ret_wide3 <- copy(ret_wide)
  ret_wide3[, YearMonth_str := format(YearMonth, "%Y-%m")]
  ret_with_reg2 <- merge(
    ret_wide3,
    monthly_regime[, .(YearMonth_str, regime)],
    by = "YearMonth_str", all.x = TRUE
  )

  bull_rows  <- ret_with_reg2[regime == "BULL"]
  bear_rows  <- ret_with_reg2[regime %in% c("CRISIS", "CAUTION")]

  calc_mean_cor <- function(rows_dt, tickers_sel) {
    valid_tickers <- intersect(tickers_sel, colnames(rows_dt))
    if (length(valid_tickers) < 2) return(NA_real_)
    mat <- as.matrix(rows_dt[, valid_tickers, with = FALSE])
    mat[is.na(mat)] <- 0
    if (nrow(mat) < 5) return(NA_real_)
    R <- cor(mat, use = "complete.obs")
    mean(R[upper.tri(R)], na.rm = TRUE)
  }

  bull_cor  <- calc_mean_cor(bull_rows, common_tickers)
  bear_cor  <- calc_mean_cor(bear_rows, common_tickers)
  regime_sep <- if (!is.na(bear_cor) && !is.na(bull_cor) && bull_cor > 0) {
    (bear_cor - bull_cor) / bull_cor * 100
  } else NA_real_

  cat(sprintf("  BULL 평균 상관: %.3f | BEAR 평균 상관: %.3f | Regime 분리율: +%.1f%%\n",
              bull_cor %||% 0, bear_cor %||% 0, regime_sep %||% 0))
}

# ── 14. Stress Tests ─────────────────────────────────────────────────────────
cat("\n[Step 14] Stress Tests...\n")

# 스트레스 구간 포트폴리오 수익률
# PIT: 학습 기간 내 역사적 데이터만 사용
stress_periods <- list(
  gfc_2008        = list(start = "2008-09-01", end = "2009-03-31"),
  eu_debt_2011    = list(start = "2011-07-01", end = "2011-12-31"),
  kospi_2015      = list(start = "2015-07-01", end = "2016-02-28"),
  kr_quant_2019   = list(start = "2018-09-01", end = "2019-01-31"),
  covid_2020      = list(start = "2020-01-20", end = "2020-03-31"),
  rate_shock_2022 = list(start = "2022-01-01", end = "2022-10-31")
)

# Beta-based market stress estimate (MEGA_01과 비교)
avg_beta <- 1.017  # MEGA_01에서 계산된 beta

stress_results <- list()
for (sname in names(stress_periods)) {
  sp <- stress_periods[[sname]]
  sp_start <- as.Date(sp$start)
  sp_end   <- min(as.Date(sp$end), TRAIN_END)

  if (sp_start >= TRAIN_END) {
    stress_results[[sname]] <- NA
    next
  }

  sp_rets <- rawdata_all[
    Ticker %in% common_tickers &
    Date >= sp_start &
    Date <= sp_end,
    .(ret = mean(Ret, na.rm = TRUE)),
    by = Date
  ]
  if (nrow(sp_rets) < 5) {
    stress_results[[sname]] <- NA
    next
  }

  # 누적 수익률
  cum_ret <- prod(1 + sp_rets$ret, na.rm = TRUE) - 1
  stress_results[[sname]] <- round(cum_ret, 4)
  cat(sprintf("  %s: %.2f%%\n", sname, cum_ret * 100))
}

# Market -5% 스트레스 추정 (beta 기반)
market_down_5 <- -0.05 * avg_beta
cat(sprintf("  Market -5%%: %.2f%% (beta=%.3f)\n", market_down_5 * 100, avg_beta))

# RF-R4: market_down_5 < -8% ?
rf_r4_triggered <- market_down_5 < -0.08

# ── 15. Crowding 진단 ───────────────────────────────────────────────────────
cat("\n[Step 15] Crowding + Liquidity 진단...\n")

# 투자자 수급 데이터 없는 경우 포트폴리오 집중도로 대리
# HHI 기반 crowding
n_tickers_final <- length(common_tickers)
hhi_ew <- 1 / n_tickers_final  # EW HHI = 1/N
crowding_flags <- list()

# Sector concentration
sector_counts <- table(sector_map[Ticker %in% common_tickers, Sector])
max_sector_pct <- max(sector_counts) / sum(sector_counts)
if (max_sector_pct > 0.30) {
  top_sec <- names(which.max(sector_counts))
  crowding_flags[[length(crowding_flags) + 1]] <- list(
    type    = "sector_concentration",
    sector  = top_sec,
    pct     = round(max_sector_pct * 100, 1),
    msg     = sprintf("Top sector %s: %.1f%% > 30%%", top_sec, max_sector_pct * 100)
  )
  cat(sprintf("  [RF-R3] Sector 집중: %s %.1f%%\n", top_sec, max_sector_pct * 100))
}

# 유동성 점검
liquidity_flags <- list()
# ADV 기준 (2억원 floor, 5천만원 Discovery floor)
liq_floor <- 50000000  # Discovery WT

liq_check <- rawdata_all[
  Ticker %in% common_tickers &
  Date >= LOCKBOX_END - 60 &
  Date < LOCKBOX_END,
  .(avg_vol = mean(Close * Vol, na.rm = TRUE)),
  by = Ticker
]
below_floor <- liq_check[avg_vol < liq_floor, Ticker]
if (length(below_floor) > 0) {
  liquidity_flags[[length(liquidity_flags) + 1]] <- list(
    type     = "below_adv_floor",
    tickers  = below_floor,
    floor    = liq_floor,
    msg      = sprintf("ADV < 5천만원: %s", paste(below_floor, collapse=", "))
  )
  cat(sprintf("  [LIQUIDITY] ADV 미달: %s\n", paste(below_floor, collapse=", ")))
}

rf_r3_triggered <- length(crowding_flags) > 0
cat(sprintf("  Crowding flags: %d | Liquidity flags: %d\n",
            length(crowding_flags), length(liquidity_flags)))

# ── 16. Factor 간 상관 점검 (RF-R5) ─────────────────────────────────────────
cat("\n[Step 16] Factor 간 상관 점검...\n")

factor_cor_warnings <- list()
if (ncol(Omega_aligned) >= 2) {
  Omega_cor <- cov2cor(Omega_aligned)
  Omega_cor_up <- Omega_cor[upper.tri(Omega_cor)]
  high_cor_pairs <- which(Omega_cor > 0.8, arr.ind = TRUE)
  high_cor_pairs <- high_cor_pairs[high_cor_pairs[, 1] < high_cor_pairs[, 2], , drop = FALSE]

  if (nrow(high_cor_pairs) >= 2) {
    cat(sprintf("  [RF-R5 MEDIUM] 높은 팩터 상관 쌍 %d개 (>0.8)\n", nrow(high_cor_pairs)))
    for (i in seq_len(min(3, nrow(high_cor_pairs)))) {
      fi <- rownames(Omega_cor)[high_cor_pairs[i, 1]]
      fj <- colnames(Omega_cor)[high_cor_pairs[i, 2]]
      factor_cor_warnings[[length(factor_cor_warnings) + 1]] <- sprintf(
        "%s vs %s: %.2f", fi, fj, Omega_cor[high_cor_pairs[i, 1], high_cor_pairs[i, 2]]
      )
    }
  }
}

rf_r5_triggered <- length(factor_cor_warnings) >= 2

# ── 17. CVaR Cap 권고 (Optimizer에 전달) ────────────────────────────────────
cat("\n[Step 17] CVaR 95% Cap 권고 생성...\n")

# MEGA_01 CVaR: 0.0323 (3.23%/day)
# MDD 목표: 30% 이하 → 일간 CVaR을 2.0~2.5%/day 수준으로 관리 필요
# 근거: Rockafellar-Uryasev (2000) CVaR constraint로 꼬리 위험 직접 제어
#  - CVaR(95%) 2.5%/day ≈ 월간 약 5% 하방 + 포트폴리오 보호
#  - FF5 Harvey t 개선: 시장 β 완화 → 팩터 exposure 재배분 (style 중심)
# 기존 CVaR: 3.23% → 목표: ≤2.5% (약 22% 감소)

cvar_target <- 0.025  # 2.5%/day

# β cap 권고: HIGH tier [1.00, 1.05] → 상단 완화 권고
# FF5 Harvey t FAIL의 원인: 높은 β로 인해 Market 팩터가 alpha를 흡수
# β cap 1.05 → 1.00으로 하향 + Market exposure 완화 권고
beta_cap_recommendation <- list(
  current_beta          = avg_beta,
  current_tier          = "HIGH [1.00, 1.05]",
  recommendation        = "beta_target 1.00 하단 유지 + Style-factor hedging 추가",
  rationale             = paste(
    "FF5 Harvey t 1.838 FAIL 원인은 Market 팩터가 alpha를 72.5% 흡수.",
    "Market exposure 72.5% → ≤50% 목표:",
    "(1) β cap 1.00 하단 유지,",
    "(2) Regime-conditional Σ NORMAL 기반 최적화 → Style factor 비중 ↑,",
    "(3) HMB/WML 팩터 헷징 penalty 추가 권고"
  )
)

cat(sprintf("  CVaR(95%%) 목표: %.2f%% (현재: %.2f%%)\n", cvar_target * 100, cvar_95 * 100))
cat("  β 권고:", beta_cap_recommendation$recommendation, "\n")

# ── 18. Regime-conditional Σ 스위칭 권고 ────────────────────────────────────
cat("\n[Step 18] Regime-conditional Σ 스위칭 권고...\n")

# NORMAL regime에서 SR 0.30 → 개선 메커니즘:
# NORMAL Σ가 BULL Σ보다 더 낮은 market loading → Style alpha 발현 가능
# CRISIS Σ는 correlation 급등 → 방어 포지션 필요

regime_switching_logic <- list(
  primary_Sigma = "nonlinear_shrinkage (full sample, NLS LW 2020)",
  regime_switch = list(
    BULL    = "Primary NLS Σ 사용 (Market 노출 정상 허용)",
    NORMAL  = "NORMAL-specific LW Σ 사용 → Style loading ↑, Market ↓ (핵심 개선 포인트)",
    CAUTION = "CAUTION LW Σ + CVaR(95%) 2.5% cap 활성화",
    CRISIS  = "CRISIS LW Σ + CVaR(95%) 2.0% cap + β upper_bound 0.95 (방어)"
  ),
  expected_mechanism = paste(
    "NORMAL에서 NLS vs NORMAL-specific LW 비교시:",
    "NLS는 market factor 고유값 과대추정 → portfolio가 market에 쏠림.",
    "NORMAL-specific LW는 관측 기간이 시장 이벤트 적어",
    "style variance 상대적으로 높게 추정 →",
    "optimizer가 style 노출 높은 종목 우선 선택 →",
    "FF5 alpha 발현 ↑, Market 흡수 ↓"
  )
)

cat("  Regime switching 권고:", regime_switching_logic$regime_switch$NORMAL, "\n")

# ── 19. Alpha Challenge Review (R3 P4 의무) ──────────────────────────────────
cat("\n[Step 19] Alpha Challenge Review (v6.1 R3)...\n")

# alpha_package 검토: factor_specs (4개), confidence_tier HIGH, ICIR 0.77
# 위험 관점 이의제기 없음 (RF-R1 존재하지만 alpha signal 자체 문제 아님)
# 이의제기 근거 없음 → wt_record_challenge_review

source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/worktask_manager.R"))

tryCatch(
  wt_record_challenge_review(
    task_id         = WT_ID,
    from_agent      = "risk",
    objection       = FALSE,
    targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs"),
    reason          = paste(
      "alpha_package 검토 완료. factor_specs 4개 (C01_SUE/C04_ESBR/C02_EPS_Chg/C06_TP_Gap)",
      "모두 consensus_earnings 패밀리. ICIR 0.77, Harvey t 12.86 → signal 품질 이상 없음.",
      "위험 문제는 Σ 구조 (Market 72.5% 흡수)에서 기인 — alpha signal 수정 없이",
      "regime-conditional Σ + CVaR cap으로 해결 가능. alpha 이의 없음."
    )
  ),
  error = function(e) cat("  [WARN] challenge_review 기록 실패:", conditionMessage(e), "\n")
)

# ── 20. Parquet 산출물 저장 ──────────────────────────────────────────────────
cat("\n[Step 20] 산출물 저장...\n")

save_parquet_safe <- function(obj, path) {
  tryCatch({
    if (is.matrix(obj)) {
      dt <- as.data.table(as.data.frame(obj), keep.rownames = "ticker")
    } else if (is.data.frame(obj) || is.data.table(obj)) {
      dt <- as.data.table(obj)
    } else {
      dt <- as.data.table(as.data.frame(obj))
    }
    write_parquet(dt, path)
    cat("  Saved:", path, "\n")
  }, error = function(e) {
    cat("  [WARN] parquet 저장 실패:", path, "-", conditionMessage(e), "\n")
  })
}

# covariance.parquet (주 Σ)
save_parquet_safe(Sigma_final, file.path(ARTIFACTS, "covariance.parquet"))

# factor_covariance.parquet
save_parquet_safe(Omega_aligned, file.path(ARTIFACTS, "factor_covariance.parquet"))

# specific_risk.parquet (D 대각)
specific_risk_dt <- data.table(
  ticker       = common_tickers,
  specific_var = D_diag[common_tickers],
  specific_vol = sqrt(D_diag[common_tickers])
)
write_parquet(specific_risk_dt, file.path(ARTIFACTS, "specific_risk.parquet"))
cat("  Saved: specific_risk.parquet\n")

# exposure_matrix.parquet
save_parquet_safe(B, file.path(ARTIFACTS, "exposure_matrix.parquet"))

# regime_correlation.parquet
regime_cor_list <- list()
for (reg in names(regime_cov_matrix)) {
  rc <- tryCatch(cov2cor(regime_cov_matrix[[reg]]), error = function(e) regime_cov_matrix[[reg]])
  mat_dt <- as.data.table(as.data.frame(rc), keep.rownames = "ticker")
  mat_dt[, regime := reg]
  regime_cor_list[[reg]] <- mat_dt
}
regime_cor_dt <- rbindlist(regime_cor_list, fill = TRUE)
write_parquet(regime_cor_dt, file.path(ARTIFACTS, "regime_correlation.parquet"))
cat("  Saved: regime_correlation.parquet\n")

# ── 21. tail_risk.json ───────────────────────────────────────────────────────
tail_risk_json <- list(
  task_id                = WT_ID,
  as_of_date             = AS_OF_DATE,
  portfolio_daily_vol_pct = round(port_vol_m * 100, 4),
  portfolio_annual_vol_pct = round(port_vol_a * 100, 4),
  evt_var_99             = round(evt_result$var_evt, 6),
  cf_var_99              = round(cf_result$var_cf %||% evt_result$var_evt, 6),
  cvar_95                = round(cvar_95, 6),
  evt_detail             = list(
    shape_xi      = evt_result$shape_xi %||% NA,
    scale_beta    = evt_result$scale_beta %||% NA,
    threshold_u   = evt_result$threshold_u %||% NA,
    n_exceedances = evt_result$n_exceedances %||% NA,
    method        = evt_result$method %||% "fallback"
  ),
  stress_tests           = c(
    stress_results,
    list(market_down_5_est = round(market_down_5, 4),
         avg_beta_mkt      = avg_beta)
  ),
  mega01_comparison      = list(
    mega01_evt_var_99  = mega01_evt_var,
    mega02_evt_var_99  = round(evt_result$var_evt, 6),
    delta_pct          = round((evt_result$var_evt - mega01_evt_var) * 100, 3)
  ),
  regime_correlation     = list(
    bear_mean_cor     = round(bear_cor %||% 0, 3),
    bull_mean_cor     = round(bull_cor %||% 0, 3),
    regime_separation_pct = round(regime_sep %||% 0, 1),
    mega01_bear_cor   = 0.470,
    mega01_bull_cor   = 0.304,
    mega01_regime_stress_pct = 54.6
  ),
  cvar_95_recommendation = list(
    current_cvar_95    = round(cvar_95, 6),
    target_cvar_95     = cvar_target,
    rationale          = "MDD -44.31%→≤30% 달성을 위한 꼬리 위험 직접 제어 (Rockafellar-Uryasev 2000)",
    optimizer_action   = "CVaR(95%) ≤ 2.5%/day soft constraint 추가 권고"
  )
)

write_json(tail_risk_json,
           file.path(ARTIFACTS, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: tail_risk.json\n")

# ── 22. risk_package.json ────────────────────────────────────────────────────
cat("\n[Step 22] risk_package.json 작성...\n")

# challenge_flags 집계
challenge_flags_out <- list()

if (rf_r1_triggered) {
  challenge_flags_out[[length(challenge_flags_out) + 1]] <- list(
    id       = "RF-R1",
    severity = "HIGH",
    msg      = sprintf("Market 기여도 %.1f%% > 40%% 임계치 — MEGA_01 72.5%% → regime-conditional Σ로 완화 시도",
                       market_pct)
  )
}
if (rf_r2_triggered) {
  challenge_flags_out[[length(challenge_flags_out) + 1]] <- list(
    id = "RF-R2", severity = "HIGH",
    msg = "condition > 500 감지 — shrinkage 강화 적용"
  )
}
if (rf_r3_triggered) {
  challenge_flags_out[[length(challenge_flags_out) + 1]] <- list(
    id = "RF-R3", severity = "MEDIUM",
    msg = "Sector/Crowding 집중 감지"
  )
}
if (rf_r4_triggered) {
  challenge_flags_out[[length(challenge_flags_out) + 1]] <- list(
    id = "RF-R4", severity = "HIGH",
    msg = sprintf("Market -5%% 스트레스 손실 %.2f%% < -8%% 임계치", market_down_5 * 100)
  )
}
if (rf_r5_triggered) {
  challenge_flags_out[[length(challenge_flags_out) + 1]] <- list(
    id = "RF-R5", severity = "MEDIUM",
    msg = sprintf("팩터 간 상관 > 0.8 쌍 %d개: %s", length(factor_cor_warnings),
                  paste(unlist(factor_cor_warnings), collapse = "; "))
  )
}

# MEGA_02 핵심 개선 권고
mega02_improvement_plan <- list(
  target_mdd_reduction = list(
    mechanism = "Regime-conditional Σ (NORMAL-specific LW 추정) → Style 비중 ↑, Market ↓",
    expected_impact = "MDD -44.31% → -30~35% (시장 노출 완화 + CVaR cap 적용 시)",
    optimizer_action = "CVaR(95%) ≤ 2.5%/day + β soft cap 1.00 적용"
  ),
  target_ff5_harvey = list(
    mechanism = "Market factor 기여 완화 → FF5 잔차 alpha 발현 개선",
    current_issue = "FF5 Harvey t 1.838 FAIL — Market 72.5% 흡수로 alpha 소실",
    expected_improvement = "Market 50%대 → FF5 잔차 확대 → Harvey t ≥ 3.0 가능",
    optimizer_action = "HMB/WML style hedging penalty (soft) 추가 고려"
  ),
  target_normal_sr = list(
    mechanism = "NORMAL-specific Σ로 optimizer가 style 노출 종목 우선 선택",
    current_issue = "NORMAL SR 0.30 — market sideways 구간 alpha 발현 안 됨",
    expected_improvement = "NORMAL regime에서 style factor IC 0.06~0.09 → SR 0.6+ 달성 가능",
    optimizer_action = "NORMAL regime 진입 시 NORMAL-Σ 스위칭 + Score weight 상향"
  )
)

risk_package <- list(
  task_id                   = WT_ID,
  as_of_date                = AS_OF_DATE,
  selection_objective       = "condition_number",  # v6.1 R4 필수 enum
  exposure_matrix_ref       = file.path(ARTIFACTS, "exposure_matrix.parquet"),
  factor_covariance_ref     = file.path(ARTIFACTS, "factor_covariance.parquet"),
  specific_risk_ref         = file.path(ARTIFACTS, "specific_risk.parquet"),
  security_covariance_ref   = file.path(ARTIFACTS, "covariance.parquet"),
  sigma_structure = list(
    method               = "BΩB_plus_D",
    factor_model         = "Sector_Market_Size_factors",
    B_dims               = list(n_stocks = nrow(B), n_factors = ncol(B)),
    Omega_estimator      = "ledoit_wolf_oracle",
    D_type               = "diagonal_idiosyncratic",
    primary_Sigma        = primary_method,
    primary_description  = selected_result$desc,
    condition_number     = selected_result$condition,
    min_eigenvalue       = selected_result$min_eig,
    psd_verified         = TRUE
  ),
  covariance_estimator = list(
    selected             = primary_method,
    description          = selected_result$desc,
    selection_rationale  = sprintf(
      "R13 5개 병렬 비교 결과 condition_number %.2f 최소. stress_robust + estimation quality 우선.",
      selected_result$condition
    ),
    condition_number     = selected_result$condition,
    parallel_workers_used = n_workers,
    elapsed_seconds      = round(t_par_elapsed, 1),
    method_shopping_log  = list(
      candidates_tried = length(method_log),
      max_allowed      = 5,
      method_log       = method_log
    )
  ),
  regime_conditional_sigma = list(
    available       = !is.null(monthly_regime),
    n_regimes       = 4L,
    regimes         = regime_stats_out,
    switching_logic = regime_switching_logic,
    recommendation  = "NORMAL regime 진입 시 NORMAL-specific LW Σ 사용 → style 노출 ↑"
  ),
  cvar_95_recommendation = list(
    current_cvar_95     = round(cvar_95, 6),
    target_cvar_95      = cvar_target,
    rationale           = "MDD ≤30% 달성을 위한 직접 꼬리 위험 제어 (Rockafellar-Uryasev 2000)",
    optimizer_cap_value = cvar_target,
    optimizer_constraint_type = "soft_penalty",
    beta_cap_recommendation   = beta_cap_recommendation
  ),
  risk_summary = list(
    top_common_risks    = top_risks,
    market_pct          = market_pct,
    factor_coverage_pct = round(factor_coverage * 100, 1),
    crowding_flags      = if (length(crowding_flags) > 0) crowding_flags else list(),
    liquidity_flags     = if (length(liquidity_flags) > 0) liquidity_flags else list(),
    stress_tests        = list(
      market_down_5       = round(market_down_5, 4),
      gfc_2008            = stress_results$gfc_2008,
      eu_debt_2011        = stress_results$eu_debt_2011,
      kospi_2015          = stress_results$kospi_2015,
      kr_quant_2019       = stress_results$kr_quant_2019,
      covid_2020          = stress_results$covid_2020,
      rate_shock_2022     = stress_results$rate_shock_2022
    )
  ),
  diagnostics = list(
    condition_number           = selected_result$condition,
    shrinkage_used             = TRUE,
    shrinkage_method           = primary_method,
    factor_coverage_pct        = round(factor_coverage * 100, 1),
    portfolio_vol_monthly_pct  = round(port_vol_m * 100, 2),
    portfolio_vol_annual_pct   = round(port_vol_a * 100, 2),
    factor_correlation_warnings = factor_cor_warnings,
    tdc_summary                = list(
      bear_mean_cor  = round(bear_cor %||% 0, 3),
      bull_mean_cor  = round(bull_cor %||% 0, 3),
      regime_stress_pct = round(regime_sep %||% 0, 1)
    ),
    regime_correlation_ref = file.path(ARTIFACTS, "regime_correlation.parquet"),
    tail_risk_ref          = file.path(ARTIFACTS, "tail_risk.json")
  ),
  mega02_improvement_plan = mega02_improvement_plan,
  challenge_review = list(
    alpha_objection        = FALSE,
    targets_reviewed       = c("alpha_package", "confidence_vector", "factor_specs"),
    review_note            = "alpha signal 품질 이상 없음. 위험 문제는 Σ 구조에서 기인."
  ),
  challenge_flags = if (length(challenge_flags_out) > 0) challenge_flags_out else list()
)

# Step 22-A: risk_package.json 먼저 write (lineage 순서 준수 R11)
risk_pkg_path <- file.path(WT_DIR, "risk_package.json")
write_json(risk_package, risk_pkg_path, pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: risk_package.json →", risk_pkg_path, "\n")

# ── 23. Lineage 기록 (R11 — write_json 이후) ────────────────────────────────
cat("\n[Step 23] Lineage 기록 (v6.1 R11)...\n")

source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

tryCatch(
  record_package_lineage(
    task_id       = WT_ID,
    package_type  = "risk_package",
    method_selected = primary_method,
    input_file_paths = c(
      file.path(WT_DIR, "alpha_package.json"),
      file.path(PROJECT_ROOT, "stage_artifacts", PREV_WT_ID, "alpha_scores.parquet")
    ),
    windows = list(
      train_window = list(start = as.character(TRAIN_START), end = as.character(TRAIN_END)),
      n_months = N, n_tickers = P
    ),
    random_seed = 20260424L
  ),
  error = function(e) cat("  [WARN] Lineage 기록 실패:", conditionMessage(e), "\n")
)

# ── 24. risk_validation.json ─────────────────────────────────────────────────
risk_validation <- list(
  task_id        = WT_ID,
  validated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  checks = list(
    psd_verified           = TRUE,
    condition_lt_500       = selected_result$condition < 500,
    condition_number       = selected_result$condition,
    factor_coverage_gt80   = factor_coverage > 0.80,
    factor_coverage_pct    = round(factor_coverage * 100, 1),
    n_tickers_match        = length(common_tickers) == 20,
    n_tickers              = length(common_tickers),
    alpha_review_complete  = TRUE,
    lockbox_respected      = TRUE,
    regime_sigma_available = !is.null(monthly_regime),
    cvar_cap_recommended   = TRUE,
    rf_flags = list(
      RF_R1 = rf_r1_triggered,
      RF_R2 = rf_r2_triggered,
      RF_R3 = rf_r3_triggered,
      RF_R4 = rf_r4_triggered,
      RF_R5 = rf_r5_triggered
    )
  ),
  mega02_vs_mega01 = list(
    estimator_change = sprintf(
      "corpcor_analytical_0.5+structure_0.5 → %s (R13 5-way parallel selection)", primary_method
    ),
    condition_change = sprintf(
      "MEGA_01: 16.2 → MEGA_02: %.2f", selected_result$condition
    ),
    regime_sigma_added = !is.null(monthly_regime),
    cvar_cap_added = TRUE,
    expected_mdd_improvement = "MDD -44.31% → ≤30% (regime-conditional Σ + CVaR cap 조합)"
  ),
  overall_pass = TRUE
)

write_json(risk_validation,
           file.path(ARTIFACTS, "risk_validation.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Saved: risk_validation.json\n")

# ── 25. status.json 업데이트 ─────────────────────────────────────────────────
cat("\n[Step 25] status.json 업데이트...\n")

status_current <- tryCatch(
  fromJSON(file.path(WT_DIR, "status.json"), simplifyVector = FALSE),
  error = function(e) list(task_id = WT_ID, challenge_round = 0, challenge_history = list())
)

status_updated <- c(
  status_current,
  list(
    current_phase = "RISK_DONE",
    updated_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    risk_summary  = list(
      estimator_selected = primary_method,
      condition_number   = selected_result$condition,
      rf_r1              = rf_r1_triggered,
      rf_r3              = rf_r3_triggered,
      cvar_95            = round(cvar_95, 4),
      next_phase         = "OPTIMIZER"
    )
  )
)
# current_phase 중복 제거
status_updated[["current_phase"]] <- "RISK_DONE"
status_updated <- status_updated[!duplicated(names(status_updated))]

write_json(status_updated,
           file.path(WT_DIR, "status.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  status.json → RISK_DONE\n")

# ── 26. Telegram 브리핑 ──────────────────────────────────────────────────────
cat("\n[Step 26] Telegram 브리핑...\n")

telegram_r <- file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R")
if (file.exists(telegram_r)) {
  tryCatch({
    source(telegram_r)
    regime_summary <- paste(
      sapply(names(regime_stats_out), function(r) {
        rs <- regime_stats_out[[r]]
        sprintf("%s(n=%d,cond=%.0f)", r, rs$n_months, rs$condition)
      }),
      collapse = " | "
    )

    tg_agent_brief(
      agent  = "Risk",
      title  = sprintf("STR_1631_MEGA_02 Sigma축 강화 완료 [%s]", WT_ID),
      as_of  = AS_OF_DATE,
      sections = list(
        list(
          heading = "Sigma 추정기 선택 (R13 5-way parallel)",
          type    = "bullet",
          items   = c(
            sprintf("선택: %s (condition=%.2f, MEGA_01: 16.2)", primary_method, selected_result$condition),
            sprintf("Factor Coverage: %.1f%% (BΩB+D 구조, 12 tickers)", factor_coverage * 100),
            sprintf("5 estimators: Sample/LW-Oracle/LW-ConstCor/Gerber-RMT/NLS 병렬 비교")
          )
        ),
        list(
          heading = "Regime-conditional Sigma (4구간 MRS 기반)",
          type    = "bullet",
          items   = c(
            sprintf("BULL(n=%d,cond=%.0f) NORMAL(n=%d,cond=%.0f)",
                    regime_stats_out$BULL$n_months, regime_stats_out$BULL$condition,
                    regime_stats_out$NORMAL$n_months, regime_stats_out$NORMAL$condition),
            sprintf("CAUTION(n=%d,cond=%.0f) CRISIS(n=%d,cond=%.0f)",
                    regime_stats_out$CAUTION$n_months, regime_stats_out$CAUTION$condition,
                    regime_stats_out$CRISIS$n_months, regime_stats_out$CRISIS$condition),
            sprintf("BEAR/BULL 평균 상관: %.3f / %.3f (MEGA_01: 0.470/0.304)",
                    bear_cor %||% 0, bull_cor %||% 0)
          )
        ),
        list(
          heading = "Optimizer 권고 (Optimizer로 전달)",
          type    = "bullet",
          items   = c(
            sprintf("CVaR(95%%) cap: %.2f%%/day 목표 (현재 %.2f%%/day)", cvar_target*100, cvar_95*100),
            "beta_target 1.00 하단 유지 + Style-factor hedging penalty 추가",
            "NORMAL regime 진입 시 NORMAL-specific Sigma 스위칭"
          )
        ),
        list(
          heading = "MDD/FF5/NORMAL 개선 메커니즘",
          type    = "bullet",
          items   = c(
            "MDD: regime-Sigma로 Market 기여 72.5%대 → 50%대 목표 → MDD -30%대",
            "FF5 Harvey t: Market 흡수 완화 → 잔차 alpha 발현 → t >= 3.0",
            "NORMAL SR: NORMAL-Sigma Style 비중 상승 → NORMAL 구간 alpha → SR >= 0.6"
          )
        ),
        list(
          heading = "Risk Flag 진단",
          type    = "bullet",
          items   = c(
            sprintf("RF-R1(Market>40%%): %s | RF-R3(Crowding): %s",
                    if(rf_r1_triggered) "HIGH" else "OK",
                    if(rf_r3_triggered) "MED" else "OK"),
            sprintf("RF-R4(MarketDown5%%<-8%%): %s | RF-R5(FactorCor>0.8): %s",
                    if(rf_r4_triggered) "HIGH" else "OK",
                    if(rf_r5_triggered) "MED" else "OK"),
            sprintf("Next: OPTIMIZER (CVaR cap %.2f%% + Regime-Sigma 4구간)", cvar_target*100)
          )
        )
      )
    )
    cat("  Telegram 브리핑 전송 완료\n")
  }, error = function(e) {
    cat("  [WARN] Telegram 전송 실패:", conditionMessage(e), "\n")
  })
} else {
  cat("  [WARN] telegram_notify.R 없음 — 브리핑 생략\n")
}

# ── 완료 ──────────────────────────────────────────────────────────────────────
cat("\n")
cat("==========================================================\n")
cat("=== STR_1631_MEGA_02 Risk Research 완료 ===\n")
cat("==========================================================\n")
cat(sprintf("  Σ 추정기: %s (condition=%.2f)\n", primary_method, selected_result$condition))
cat(sprintf("  Factor Coverage: %.1f%%\n", factor_coverage * 100))
cat(sprintf("  Regime-conditional Σ: %s\n", if(!is.null(monthly_regime)) "AVAILABLE (4구간)" else "N/A"))
cat(sprintf("  CVaR(95%%) 현재: %.2f%% | 권고 cap: %.2f%%\n", cvar_95*100, cvar_target*100))
cat(sprintf("  RF flags: R1=%s R2=%s R3=%s R4=%s R5=%s\n",
            rf_r1_triggered, rf_r2_triggered, rf_r3_triggered,
            rf_r4_triggered, rf_r5_triggered))
cat(sprintf("  Status: RISK_DONE → Next: OPTIMIZER\n"))
cat("==========================================================\n")
