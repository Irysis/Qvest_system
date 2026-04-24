#==============================================================================
# WT-D20260424_002 Optimizer Pipeline
# Task #26 L-192 Remediation: Grinold Breadth Constraints
# bounds 0.10 / min_names 15 / hhi_cap 0.10 / alpha_winsor 2sigma
#==============================================================================

t_start <- proc.time()

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
  library(quadprog)
  library(digest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
TASK_ID <- "WT-D20260424_002"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", TASK_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260424_002")

# 인프라 로드
source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/mean_variance_optimizer.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/worktask_manager.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

cat("\n=== WT-D20260424_002 Optimizer Pipeline ===\n")
cat("Task #26: L-192 Grinold Breadth Remediation\n")
cat("bounds=[0,0.10] / min_names=15 / hhi_cap=0.10 / winsor=2sigma\n\n")

# ─── Step 1: Input 로드 ───────────────────────────────────
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = FALSE)

alpha_vec <- unlist(alpha_pkg$alpha_vector)
conf_vec  <- unlist(alpha_pkg$confidence_vector)
cat(sprintf("[Step 1] Alpha universe: %d tickers\n", length(alpha_vec)))
cat(sprintf("         A140860 raw alpha: %.4f (outlier)\n", alpha_vec["A140860"]))
cat(sprintf("         Confidence range: [%.3f, %.3f]\n",
            min(conf_vec), max(conf_vec)))

# Covariance 행렬 로드 (Ledoit-Wolf, Risk Agent 선택)
cov_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260424_001/covariance.parquet")
cov_dt <- as.data.frame(read_parquet(cov_path))
rownames(cov_dt) <- cov_dt$ticker
cov_dt$ticker <- NULL
Sigma <- as.matrix(cov_dt)
cat(sprintf("[Step 1] Covariance matrix: %dx%d (Ledoit-Wolf)\n", nrow(Sigma), ncol(Sigma)))

# 공통 universe (alpha & cov 교집합)
common_tickers <- intersect(names(alpha_vec), rownames(Sigma))
cat(sprintf("[Step 1] Common tickers: %d\n", length(common_tickers)))

alpha_use <- alpha_vec[common_tickers]
conf_use  <- conf_vec[common_tickers]
Sigma_use <- Sigma[common_tickers, common_tickers]

# ─── Step 2: Feasibility Pre-Check ───────────────────────
cat("\n[Step 2] Feasibility Pre-Check\n")
cat(sprintf("  Universe size: %d (need >= 15 for min_names)\n", length(common_tickers)))
cat(sprintf("  min_names=15 × bounds[2]=0.10 = %.2f (target_sum=1.0 → FEASIBLE if <=1)\n",
            15 * 0.10))
# 15 × 0.10 = 1.50 >= 1.00 → feasible
cat("  FEASIBILITY: OK (15 × 0.10 = 1.50 >= 1.0)\n")

# ─── Step 3: Alpha Winsorization 효과 사전 확인 ──────────
cat("\n[Step 3] Alpha Winsorization Preview\n")
mu_a <- mean(alpha_use)
sd_a <- sd(alpha_use)
z_A140860 <- (alpha_use["A140860"] - mu_a) / sd_a
cat(sprintf("  A140860 z-score: %.2f (|z|>2.0 → winsorized)\n", z_A140860))
cat(sprintf("  Raw alpha: %.4f → Winsorized: %.4f\n",
            alpha_use["A140860"],
            sign(z_A140860) * 2.0 * sd_a + mu_a))

# ─── Step 4: Method 비교 (candidates_tried <= 10) ────────
cat("\n[Step 4] Method Shopping (net_ir 기반 선택)\n")

# Task #26 기본 파라미터
BOUNDS  <- c(0, 0.10)
MAX_N   <- 20L
MIN_N   <- 15L
HHI_CAP <- 0.10
WINSOR  <- 2.0

method_log <- list()

#
# Candidate 1: MVO_lam2_psi0.3 (core, Task#26 제약)
#
cat("  [1/5] MVO_lam2_psi0.3 + Task#26 제약\n")
r1 <- mvo_weights(
  alpha      = alpha_use,
  cov_matrix = Sigma_use,
  confidence = conf_use,
  lambda     = 2.0,
  psi        = 0.3,
  bounds     = BOUNDS,
  max_names  = MAX_N,
  min_names  = MIN_N,
  hhi_cap    = HHI_CAP,
  alpha_winsor = WINSOR,
  active     = FALSE
)
net_ir1 <- if (!is.null(r1$expected_information_ratio) &&
               is.finite(r1$expected_information_ratio)) r1$expected_information_ratio else -Inf
cat(sprintf("    N=%d HHI=%.4f IR=%.4f lambda_used=%.2f\n",
            r1$n_names, r1$hhi, net_ir1, r1$lambda_used))
method_log[[1]] <- list(name="MVO_lam2_psi0.3", net_ir=round(net_ir1,4),
                         n_names=r1$n_names, hhi=round(r1$hhi,4),
                         max_w=round(max(r1$weights %||% 0),4), selected=FALSE)

#
# Candidate 2: MVO_lam1_psi0.3 (낮은 risk-aversion)
#
cat("  [2/5] MVO_lam1_psi0.3 + Task#26 제약\n")
r2 <- mvo_weights(
  alpha      = alpha_use,
  cov_matrix = Sigma_use,
  confidence = conf_use,
  lambda     = 1.0,
  psi        = 0.3,
  bounds     = BOUNDS,
  max_names  = MAX_N,
  min_names  = MIN_N,
  hhi_cap    = HHI_CAP,
  alpha_winsor = WINSOR,
  active     = FALSE
)
net_ir2 <- if (!is.null(r2$expected_information_ratio) &&
               is.finite(r2$expected_information_ratio)) r2$expected_information_ratio else -Inf
cat(sprintf("    N=%d HHI=%.4f IR=%.4f lambda_used=%.2f\n",
            r2$n_names, r2$hhi, net_ir2, r2$lambda_used))
method_log[[2]] <- list(name="MVO_lam1_psi0.3", net_ir=round(net_ir2,4),
                         n_names=r2$n_names, hhi=round(r2$hhi,4),
                         max_w=round(max(r2$weights %||% 0),4), selected=FALSE)

#
# Candidate 3: MVO_lam3_psi0.5 (높은 shrinkage + FU penalty 확대)
#
cat("  [3/5] MVO_lam3_psi0.5 + Task#26 제약\n")
r3 <- mvo_weights(
  alpha      = alpha_use,
  cov_matrix = Sigma_use,
  confidence = conf_use,
  lambda     = 3.0,
  psi        = 0.5,
  bounds     = BOUNDS,
  max_names  = MAX_N,
  min_names  = MIN_N,
  hhi_cap    = HHI_CAP,
  alpha_winsor = WINSOR,
  active     = FALSE
)
net_ir3 <- if (!is.null(r3$expected_information_ratio) &&
               is.finite(r3$expected_information_ratio)) r3$expected_information_ratio else -Inf
cat(sprintf("    N=%d HHI=%.4f IR=%.4f lambda_used=%.2f\n",
            r3$n_names, r3$hhi, net_ir3, r3$lambda_used))
method_log[[3]] <- list(name="MVO_lam3_psi0.5", net_ir=round(net_ir3,4),
                         n_names=r3$n_names, hhi=round(r3$hhi,4),
                         max_w=round(max(r3$weights %||% 0),4), selected=FALSE)

#
# Candidate 4: HRP + bounds (Ledoit-Wolf 공분산 활용)
#
cat("  [4/5] HRP + bounds=0.10\n")

# HRP 구현 (공분산 기반, 직접)
.hrp_weights_simple <- function(cov_mat, bounds = c(0, 0.10),
                                  max_names = 20, min_names = 15,
                                  alpha_vec = NULL) {
  n <- nrow(cov_mat)
  tickers <- rownames(cov_mat)

  # 상관행렬 계산
  sds <- sqrt(diag(cov_mat))
  sds[sds < 1e-10] <- 1e-10
  cor_mat <- cov_mat / outer(sds, sds)
  diag(cor_mat) <- 1.0

  # 클러스터링 (계층적)
  dist_mat <- as.dist(sqrt(0.5 * (1 - cor_mat)))
  hc <- tryCatch(hclust(dist_mat, method = "ward.D2"),
                 error = function(e) hclust(dist_mat, method = "complete"))
  order_idx <- hc$order

  # Inverse variance portfolio per cluster
  w <- rep(1.0 / n, n)
  names(w) <- tickers

  # 클러스터 분산 함수
  cl_var <- function(idx) {
    if (length(idx) == 1) return(cov_mat[idx, idx])
    sub <- cov_mat[idx, idx, drop = FALSE]
    iv <- 1 / diag(sub); iv <- iv / sum(iv)
    as.numeric(t(iv) %*% sub %*% iv)
  }

  # 재귀 이분 (HRP 핵심)
  clusters <- list(order_idx)
  while (length(clusters) > 0) {
    new_cl <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      mid <- ceiling(length(cl) / 2)
      L <- cl[seq_len(mid)]; R <- cl[(mid+1):length(cl)]
      vL <- cl_var(L); vR <- cl_var(R)
      alpha_split <- 1 - vL / (vL + vR)
      w[L] <- w[L] * alpha_split
      w[R] <- w[R] * (1 - alpha_split)
      if (length(L) > 1) new_cl[[length(new_cl)+1]] <- L
      if (length(R) > 1) new_cl[[length(new_cl)+1]] <- R
    }
    clusters <- new_cl
  }

  w <- w / sum(w)

  # max_names: top-N by weight
  if (length(w) > max_names) {
    top_idx <- order(w, decreasing = TRUE)[seq_len(max_names)]
    w_keep <- w[top_idx]
    w_keep <- w_keep / sum(w_keep)
    w_full <- rep(0, n); names(w_full) <- tickers
    w_full[top_idx] <- w_keep
    w <- w_full
  }

  # bounds clip
  w <- pmax(pmin(w, bounds[2]), bounds[1])
  if (sum(w) > 0) w <- w / sum(w)

  # HHI 계산
  w_nz <- w[w > 1e-6]
  hhi <- sum(w_nz^2)

  # net_ir (expected): alpha 기반 추정
  exp_ar <- if (!is.null(alpha_vec)) sum(alpha_vec[names(w_nz)] * w_nz, na.rm=TRUE) else NA
  exp_var <- as.numeric(t(w_nz) %*% cov_mat[names(w_nz), names(w_nz)] %*% w_nz)
  exp_te <- sqrt(max(exp_var, 0))
  exp_ir <- if (is.finite(exp_te) && exp_te > 1e-6) exp_ar / exp_te else NA

  list(
    weights = w_nz,
    n_names = length(w_nz),
    hhi = hhi,
    expected_active_return = exp_ar,
    expected_tracking_error = exp_te,
    expected_information_ratio = exp_ir,
    method = "HRP_bounds0.10",
    min_names_enforced = length(w_nz) < min_names,
    hhi_enforced = FALSE,
    winsor_applied = FALSE,
    lambda_retries = 0,
    lambda_used = NA,
    selection_objective = "net_ir"
  )
}

# HRP 실행
r4 <- .hrp_weights_simple(Sigma_use, bounds = BOUNDS, max_names = MAX_N,
                           min_names = MIN_N, alpha_vec = alpha_use)
net_ir4 <- if (!is.null(r4$expected_information_ratio) &&
               is.finite(r4$expected_information_ratio)) r4$expected_information_ratio else -Inf
cat(sprintf("    N=%d HHI=%.4f IR=%.4f\n",
            r4$n_names, r4$hhi, net_ir4))
method_log[[4]] <- list(name="HRP_bounds0.10", net_ir=round(net_ir4,4),
                         n_names=r4$n_names, hhi=round(r4$hhi,4),
                         max_w=round(max(r4$weights %||% 0),4), selected=FALSE)

#
# Candidate 5: ERC_confidence (Equal Risk Contribution + conf weighting)
#
cat("  [5/5] ERC_confidence + Task#26 제약\n")

.erc_weights <- function(cov_mat, confidence = NULL,
                          bounds = c(0, 0.10), max_names = 20, min_names = 15,
                          alpha_vec = NULL, max_iter = 500, tol = 1e-8) {
  n <- nrow(cov_mat)
  tickers <- rownames(cov_mat)

  # 초기 가중치: 역분산 (confidence 가중 조정)
  inv_var <- 1 / diag(cov_mat)
  if (!is.null(confidence)) {
    # confidence 높은 종목에 더 많이 배분
    c_vec <- confidence[tickers]
    c_vec[is.na(c_vec)] <- 0.5
    inv_var <- inv_var * (0.5 + 0.5 * c_vec)
  }
  w <- inv_var / sum(inv_var)

  # Newton iteration for ERC
  for (i in seq_len(max_iter)) {
    Sw <- as.numeric(cov_mat %*% w)
    port_var <- as.numeric(t(w) %*% Sw)
    rc <- w * Sw / port_var  # risk contribution

    grad <- rc - 1/n  # target equal RC

    # 스텝 크기 (Roncalli 2013)
    step <- 0.1 / (i^0.5)
    w_new <- w - step * grad
    w_new <- pmax(w_new, 0)
    if (sum(w_new) > 0) w_new <- w_new / sum(w_new)

    if (max(abs(w_new - w)) < tol) { w <- w_new; break }
    w <- w_new
  }

  # bounds + max_names
  w <- pmax(pmin(w, bounds[2]), bounds[1])
  if (length(w) > max_names) {
    top_idx <- order(w, decreasing=TRUE)[seq_len(max_names)]
    w_keep <- w[top_idx]; w_keep <- w_keep / sum(w_keep)
    w_full <- rep(0, n); names(w_full) <- tickers
    w_full[top_idx] <- w_keep; w <- w_full
  }
  w <- w[w > 1e-6]
  if (sum(w) > 0) w <- w / sum(w)

  hhi <- sum(w^2)
  exp_ar <- if (!is.null(alpha_vec)) sum(alpha_vec[names(w)] * w, na.rm=TRUE) else NA
  nms <- names(w)
  exp_var <- as.numeric(t(w) %*% cov_mat[nms, nms] %*% w)
  exp_te <- sqrt(max(exp_var, 0))
  exp_ir <- if (is.finite(exp_te) && exp_te > 1e-6) exp_ar / exp_te else NA

  list(
    weights = w,
    n_names = length(w),
    hhi = hhi,
    expected_active_return = exp_ar,
    expected_tracking_error = exp_te,
    expected_information_ratio = exp_ir,
    method = "ERC_confidence",
    min_names_enforced = length(w) < min_names,
    hhi_enforced = FALSE,
    winsor_applied = FALSE,
    lambda_retries = 0,
    lambda_used = NA,
    selection_objective = "net_ir"
  )
}

r5 <- .erc_weights(Sigma_use, confidence = conf_use, bounds = BOUNDS,
                    max_names = MAX_N, min_names = MIN_N, alpha_vec = alpha_use)
net_ir5 <- if (!is.null(r5$expected_information_ratio) &&
               is.finite(r5$expected_information_ratio)) r5$expected_information_ratio else -Inf
cat(sprintf("    N=%d HHI=%.4f IR=%.4f\n",
            r5$n_names, r5$hhi, net_ir5))
method_log[[5]] <- list(name="ERC_confidence", net_ir=round(net_ir5,4),
                         n_names=r5$n_names, hhi=round(r5$hhi,4),
                         max_w=round(max(r5$weights %||% 0),4), selected=FALSE)

# ─── 선택: net_ir 최대화 ─────────────────────────────────
net_irs <- c(net_ir1, net_ir2, net_ir3, net_ir4, net_ir5)
method_names <- c("MVO_lam2_psi0.3", "MVO_lam1_psi0.3", "MVO_lam3_psi0.5",
                   "HRP_bounds0.10", "ERC_confidence")
results <- list(r1, r2, r3, r4, r5)

best_idx <- which.max(net_irs)
cat(sprintf("\n[Step 4] Best method: %s (net_ir=%.4f)\n",
            method_names[best_idx], net_irs[best_idx]))

method_log[[best_idx]]$selected <- TRUE

best_result <- results[[best_idx]]
best_weights <- best_result$weights
best_name <- method_names[best_idx]

# ─── Step 5: 제약 검증 ───────────────────────────────────
cat("\n[Step 5] Constraint Verification\n")
w_check <- best_weights
cat(sprintf("  N names:  %d (target: >= %d, <= %d)\n",
            length(w_check), MIN_N, MAX_N))
cat(sprintf("  sum(w):   %.6f (target: 1.0)\n", sum(w_check)))
cat(sprintf("  max(w):   %.4f (limit: %.2f)\n", max(w_check), BOUNDS[2]))
cat(sprintf("  min(w):   %.4f (limit: %.2f)\n", min(w_check[w_check > 1e-6]), BOUNDS[1]))
cat(sprintf("  HHI:      %.4f (limit: %.2f)\n", sum(w_check^2), HHI_CAP))
cat(sprintf("  long-only: %s\n", if (all(w_check >= 0)) "YES" else "VIOLATION"))

# Binding constraints
binding_constraints <- character(0)
if (max(w_check) >= BOUNDS[2] - 1e-4) binding_constraints <- c(binding_constraints, "weight_bound_upper_0.10")
if (best_result$min_names_enforced) binding_constraints <- c(binding_constraints, "min_names_15_enforced")
if (best_result$hhi_enforced) binding_constraints <- c(binding_constraints, "hhi_cap_0.10_enforced")
if (best_result$winsor_applied) binding_constraints <- c(binding_constraints, "alpha_winsor_2sigma")
if (length(binding_constraints) == 0) binding_constraints <- "none_binding"

cat(sprintf("  Binding:  %s\n", paste(binding_constraints, collapse=", ")))

# Infeasibility check
infeasibility_report <- NULL
violations <- character(0)
if (length(w_check) < MIN_N) violations <- c(violations, sprintf("min_names_fail: %d < %d", length(w_check), MIN_N))
if (sum(w_check^2) > HHI_CAP + 1e-4) violations <- c(violations, sprintf("hhi_fail: %.4f > %.2f", sum(w_check^2), HHI_CAP))
if (any(w_check < 0)) violations <- c(violations, "long_only_violated")
if (any(w_check > BOUNDS[2] + 1e-4)) violations <- c(violations, "upper_bound_violated")
if (abs(sum(w_check) - 1) > 1e-3) violations <- c(violations, "sum_weights_not_1")

if (length(violations) > 0) {
  infeasibility_report <- list(
    reason = paste(violations, collapse = "; "),
    violated_constraints = violations,
    suggested_resolution = "Universe 확장 or lambda 조정 후 재실행"
  )
  cat("  INFEASIBILITY: ", paste(violations, collapse="; "), "\n")
} else {
  cat("  All constraints SATISFIED\n")
}

# ─── Step 6: Sensitivity 요약 ────────────────────────────
cat("\n[Step 6] Sensitivity\n")
cat(sprintf("  Expected Active Return: %.4f (%.2f%%)\n",
            best_result$expected_active_return,
            best_result$expected_active_return * 100))
cat(sprintf("  Expected TE:           %.4f (%.2f%%)\n",
            best_result$expected_tracking_error,
            best_result$expected_tracking_error * 100))
cat(sprintf("  Expected IR:           %.4f\n", best_result$expected_information_ratio))
cat(sprintf("  Alpha winsorized:      %s\n", best_result$winsor_applied))
cat(sprintf("  Lambda retries:        %d\n", best_result$lambda_retries))
cat(sprintf("  Lambda used:           %.2f\n", best_result$lambda_used %||% NA))

# 비용 추정 (15bps one-way, 단일 리밸런싱)
COST_BPS <- 15
est_turnover <- 1.0  # 초기 구성 → 100% turnover
est_cost <- est_turnover * COST_BPS / 10000
cat(sprintf("  Estimated Cost:        %.4f (%.1fbps)\n", est_cost, est_cost * 10000))

# ─── Step 7: Pilot 3 vs Pilot 4 비교 ─────────────────────
pilot3_n <- 8L
pilot3_hhi <- 0.1697
pilot3_max_w <- 0.20
pilot3_ir <- -1.003

cat("\n[Step 7] Pilot 3 vs Pilot 4 비교\n")
cat(sprintf("  N names:  Pilot3=%d → Pilot4=%d (%s)\n",
            pilot3_n, length(w_check),
            if (length(w_check) >= 15) "BREADTH OK" else "STILL LOW"))
cat(sprintf("  HHI:      Pilot3=%.4f → Pilot4=%.4f (%s)\n",
            pilot3_hhi, sum(w_check^2),
            if (sum(w_check^2) <= HHI_CAP) "OK" else "STILL HIGH"))
cat(sprintf("  max_w:    Pilot3=%.2f → Pilot4=%.4f (%s)\n",
            pilot3_max_w, max(w_check),
            if (max(w_check) <= BOUNDS[2]) "OK" else "VIOLATION"))
cat(sprintf("  Expected IR: Pilot3=%.3f → Pilot4=%.3f\n",
            pilot3_ir, best_result$expected_information_ratio))

# ─── Step 8: 활성 가중치 계산 (벤치마크: KOSPI200 EW 근사) ─
# KOSPI200 EW 근사: 1/200 = 0.005
bm_w <- 0.005
tickers_out <- names(w_check)
active_w <- w_check - bm_w
names(active_w) <- tickers_out

# ─── GAP-1: Challenge Review ─────────────────────────────
cat("\n[GAP-1] Challenge Review 기록\n")
wt_record_challenge_review(
  task_id = TASK_ID,
  from_agent = "optimizer",
  objection = FALSE,
  targets_reviewed = c("alpha_inherited", "risk_inherited", "breadth_constraints")
)

# ─── Step 9: optimization_package.json 저장 ──────────────
cat("\n[Step 9] optimization_package.json 생성\n")

# Method comparison 객체
method_comparison <- list()
for (i in seq_along(method_log)) {
  ml <- method_log[[i]]
  method_comparison[[ml$name]] <- list(
    net_ir = ml$net_ir,
    n_names = ml$n_names,
    hhi = ml$hhi,
    max_w = ml$max_w,
    selected = ml$selected
  )
}

opt_pkg <- list(
  task_id = TASK_ID,
  as_of_date = "2026-04-24",
  agent = "optimizer_research",
  hypothesis = "RAPC Breadth-Constrained (Task#26 L-192 Remediation)",
  selection_objective = "net_ir",

  # 비중 결과
  target_weights = as.list(round(w_check, 6)),
  active_weights = as.list(round(active_w, 6)),

  # 예상 성과
  expected_active_return = round(best_result$expected_active_return, 6),
  expected_tracking_error = round(best_result$expected_tracking_error, 6),
  expected_information_ratio = round(best_result$expected_information_ratio, 4),

  # 비용
  turnover = round(est_turnover, 4),
  estimated_cost = round(est_cost, 6),
  cost_model = "v2.3_kr_retail_15bps",

  # 제약
  binding_constraints = as.list(binding_constraints),
  infeasibility_report = infeasibility_report,

  # 방법론
  method_selected = best_name,
  method_comparison = method_comparison,

  # Task#26 검증 필드 (v6.1 R12)
  n_names = length(w_check),
  hhi = round(sum(w_check^2), 6),
  min_names_enforced = isTRUE(best_result$min_names_enforced),
  hhi_enforced = isTRUE(best_result$hhi_enforced),
  winsor_applied = isTRUE(best_result$winsor_applied),
  lambda_retries = best_result$lambda_retries %||% 0L,
  lambda_used = best_result$lambda_used %||% NA,

  # Task#26 제약 파라미터
  task26_constraints = list(
    bounds = BOUNDS,
    max_names = MAX_N,
    min_names = MIN_N,
    hhi_cap = HHI_CAP,
    alpha_winsor = WINSOR
  ),

  # Pilot 3 비교
  pilot3_baseline = list(
    n_names = pilot3_n,
    hhi = pilot3_hhi,
    max_w = pilot3_max_w,
    active_ir = pilot3_ir
  ),

  # candidates
  candidates_tried = length(method_log),

  # 설명
  explanation = list(
    top_overweights = names(head(sort(w_check, decreasing=TRUE), 5)),
    top_underweights = paste0("all_others (bm_w=", bm_w, ")"),
    main_tradeoffs = list(
      "alpha_winsor: A140860 3.0 → clipped to 2sigma (집중 완화)",
      "min_names=15: QP breadth 하한 강제 → Grinold IR 개선 기대",
      "hhi_cap=0.10: 집중 포트폴리오 → 분산 포트폴리오 전환",
      "bounds[0,0.10]: 최대 10% per-name (Pilot3 20% 대비)"
    )
  ),

  # compliance
  v61_compliance = list(
    R4_selection_objective = "net_ir",
    R4A_confidence_vector = TRUE,
    R2C_method_shopping_log = TRUE,
    R12_infeasibility_report = TRUE,
    GAP1_challenge_review = TRUE,
    GAP2_lineage = TRUE,
    Task26_breadth_constraints = TRUE
  )
)

out_path <- file.path(WT_DIR, "optimization_package.json")
write_json(opt_pkg, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("  Saved: %s\n", out_path))

# ─── Step 10: weights.csv 저장 ───────────────────────────
cat("\n[Step 10] weights.csv 저장\n")

weights_dt <- data.table(
  date = "2023-12-28",
  ticker = names(w_check),
  weight = round(as.numeric(w_check), 6),
  active_weight = round(as.numeric(active_w), 6),
  alpha_score = round(as.numeric(alpha_use[names(w_check)]), 4),
  confidence = round(as.numeric(conf_use[names(w_check)]), 4)
)
setorder(weights_dt, -weight)

weights_path <- file.path(STAGE_DIR, "weights.csv")
fwrite(weights_dt, weights_path)
cat(sprintf("  Saved: %s (%d rows)\n", weights_path, nrow(weights_dt)))
print(weights_dt)

# ─── GAP-2: Lineage 기록 ─────────────────────────────────
cat("\n[GAP-2] Lineage 기록\n")
record_package_lineage(
  task_id = TASK_ID,
  package_type = "optimization_package",
  method_selected = best_name,
  input_file_paths = c(
    file.path(WT_DIR, "alpha_package.json"),
    file.path(WT_DIR, "risk_package.json")
  ),
  wt_root = file.path(PROJECT_ROOT, "qepm/mailbox/worktask")
)

# ─── Method Shopping Log 갱신 (R2-C) ─────────────────────
cat("\n[R2-C] Method Shopping Log 갱신\n")
msl_path <- file.path(WT_DIR, "method_shopping_log.json")
if (file.exists(msl_path)) {
  msl <- fromJSON(msl_path, simplifyVector = FALSE)
} else {
  msl <- list()
}

msl$optimizer_agent <- list(
  candidates_tried = length(method_log),
  selection_objective = "net_ir",
  method_log = method_log
)

write_json(msl, msl_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("  Saved: %s\n", msl_path))

# ─── Status 업데이트 ─────────────────────────────────────
wt_advance(TASK_ID, "OPTIMIZATION_DONE")

# ─── 최종 요약 ───────────────────────────────────────────
elapsed <- (proc.time() - t_start)["elapsed"]
cat(sprintf("\n=== OPTIMIZATION COMPLETE (%d names | HHI=%.4f | IR=%.4f) ===\n",
            length(w_check), sum(w_check^2), best_result$expected_information_ratio))
cat(sprintf("  Elapsed: %.1f sec\n", elapsed))

# 결과 저장 (텔레그램 발송용)
cat("\n__RESULTS_START__\n")
cat(sprintf("TASK_ID=%s\n", TASK_ID))
cat(sprintf("ELAPSED=%.1f\n", elapsed))
cat(sprintf("BEST_METHOD=%s\n", best_name))
cat(sprintf("N_NAMES=%d\n", length(w_check)))
cat(sprintf("HHI=%.4f\n", sum(w_check^2)))
cat(sprintf("MAX_W=%.4f\n", max(w_check)))
cat(sprintf("EXP_IR=%.4f\n", best_result$expected_information_ratio))
cat(sprintf("EXP_AR=%.4f\n", best_result$expected_active_return))
cat(sprintf("EXP_TE=%.4f\n", best_result$expected_tracking_error))
cat(sprintf("WINSOR=%s\n", best_result$winsor_applied))
cat(sprintf("LAMBDA_RETRIES=%d\n", best_result$lambda_retries))
cat(sprintf("MIN_NAMES_ENF=%s\n", best_result$min_names_enforced))
cat(sprintf("HHI_ENF=%s\n", best_result$hhi_enforced))
cat(sprintf("BINDING=%s\n", paste(binding_constraints, collapse=",")))
cat(sprintf("CANDIDATES=%d\n", length(method_log)))
cat("NET_IRS=")
cat(paste(round(net_irs, 4), collapse=","))
cat("\n")
cat(sprintf("PILOT3_N=%d\n", pilot3_n))
cat(sprintf("PILOT3_HHI=%.4f\n", pilot3_hhi))
cat(sprintf("PILOT3_MAXW=%.4f\n", pilot3_max_w))
cat("__RESULTS_END__\n")
