#!/usr/bin/env Rscript
# test_weight_engine.R — weight_engine.cpp 컴파일 + R vs Rcpp 결과 비교 + 속도 벤치마크
# 실행: Rscript -e 'source("test_weight_engine.R")'

cat("=== weight_engine.cpp 컴파일 + 검증 ===\n")
cat("시작:", format(Sys.time()), "\n\n")

# ── 경로 설정 ─────────────────────────────────────────────────────────────────
proj_root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
cpp_path  <- file.path(proj_root, "02_Infrastructure/portfolio/weight_engine.cpp")
harness_path <- file.path(proj_root, "02_Infrastructure/backtest_harness.R")

# ── 1. Rcpp 컴파일 ────────────────────────────────────────────────────────────
cat("[1] Rcpp::sourceCpp 컴파일 중...\n")
compile_ok <- tryCatch({
  Rcpp::sourceCpp(cpp_path)
  TRUE
}, error = function(e) {
  cat("  [FAIL] 컴파일 에러:", conditionMessage(e), "\n")
  FALSE
})
if (!compile_ok) quit(save = "no", status = 1)
cat("  [OK] 컴파일 성공\n\n")

# ── 2. R 정본 함수 로드 ───────────────────────────────────────────────────────
cat("[2] R 정본 함수 로드 (backtest_harness.R)...\n")
# backtest_harness.R은 무거운 의존성을 가질 수 있으므로 필요한 함수만 직접 정의
.gerber_cor_R <- function(ret_mat, threshold = 0.5) {
  p   <- ncol(ret_mat)
  sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
  h   <- threshold * sds
  cor_mat <- diag(p)
  for (i in 1:(p - 1)) {
    xi <- ret_mat[, i]; hi <- h[i]
    for (j in (i + 1):p) {
      xj <- ret_mat[, j]; hj <- h[j]
      up_i <- xi >  hi; dn_i <- xi < -hi
      up_j <- xj >  hj; dn_j <- xj < -hj
      conc  <- sum((up_i & up_j) | (dn_i & dn_j), na.rm = TRUE)
      disc  <- sum((up_i & dn_j) | (dn_i & up_j), na.rm = TRUE)
      denom <- conc + disc
      cor_mat[i, j] <- cor_mat[j, i] <- if (denom > 0) (conc - disc) / denom else 0
    }
  }
  colnames(cor_mat) <- rownames(cor_mat) <- colnames(ret_mat)
  cor_mat
}

.rmt_denoise_R <- function(cor_mat, q_ratio) {
  n <- nrow(cor_mat)
  if (n < 3 || q_ratio < 1) return(cor_mat)
  lambda_plus <- (1 + 1 / sqrt(q_ratio))^2
  eig  <- eigen(cor_mat, symmetric = TRUE)
  vals <- eig$values; vecs <- eig$vectors
  noise_idx <- which(vals <= lambda_plus)
  if (length(noise_idx) > 0 && length(noise_idx) < n)
    vals[noise_idx] <- mean(vals[noise_idx])
  D <- matrix(0, n, n); diag(D) <- vals
  cor_clean <- vecs %*% D %*% t(vecs)
  diag(cor_clean) <- 1.0
  cor_clean <- (cor_clean + t(cor_clean)) / 2
  colnames(cor_clean) <- rownames(cor_clean) <- colnames(cor_mat)
  cor_clean
}

.cluster_var_R <- function(cov_mat, idx) {
  if (length(idx) == 1) return(cov_mat[idx, idx])
  sub_cov <- cov_mat[idx, idx, drop = FALSE]
  ivp     <- 1 / diag(sub_cov); ivp <- ivp / sum(ivp)
  as.numeric(t(ivp) %*% sub_cov %*% ivp)
}

.hrp_bisect_R <- function(cov_mat, order_idx) {
  n        <- length(order_idx)
  w        <- rep(1.0, n)
  clusters <- list(order_idx)
  while (length(clusters) > 0) {
    new_clusters <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      mid   <- ceiling(length(cl) / 2)
      left  <- cl[1:mid]; right <- cl[(mid + 1):length(cl)]
      var_l <- .cluster_var_R(cov_mat, left)
      var_r <- .cluster_var_R(cov_mat, right)
      alpha <- 1 - var_l / (var_l + var_r)
      w[left]  <- w[left]  * alpha
      w[right] <- w[right] * (1 - alpha)
      if (length(left)  > 1) new_clusters[[length(new_clusters) + 1]] <- left
      if (length(right) > 1) new_clusters[[length(new_clusters) + 1]] <- right
    }
    clusters <- new_clusters
  }
  w
}

.crisis_consec_R <- function(crisis_flag) {
  n   <- length(crisis_flag)
  out <- integer(n)
  cnt <- 0L
  for (i in seq_len(n)) {
    if (crisis_flag[i] == 1L) { cnt <- cnt + 1L } else { cnt <- 0L }
    out[i] <- cnt
  }
  out
}
cat("  [OK] R 정본 함수 정의 완료\n\n")

# ── 3. 테스트 데이터 생성 ─────────────────────────────────────────────────────
set.seed(42)
T_obs  <- 120
N_assets <- 20
ret_mat <- matrix(rnorm(T_obs * N_assets, 0, 0.02), T_obs, N_assets)
colnames(ret_mat) <- paste0("A", seq_len(N_assets))

# 일부 NA 삽입 (실제 데이터 시뮬레이션)
na_pos <- sample(length(ret_mat), 30)
ret_mat_na <- ret_mat
ret_mat_na[na_pos] <- NA

# crisis_flag 테스트 데이터
set.seed(7)
crisis_flag <- sample(0L:1L, 500L, replace = TRUE, prob = c(0.85, 0.15))

cat("[3] 테스트 데이터 생성 완료 (T=", T_obs, ", N=", N_assets, ")\n\n")

# ── 4. 결과 일치 검증 ─────────────────────────────────────────────────────────
cat("[4] R vs Rcpp 결과 비교\n")
TOL <- 1e-8

## 4-1. Gerber (NA 없는 버전)
r_gerber   <- .gerber_cor_R(ret_mat)
cpp_gerber <- cpp_gerber_cor(ret_mat)
eq_gerber  <- isTRUE(all.equal(r_gerber, cpp_gerber, tolerance = TOL))
cat(sprintf("  Gerber cor (no NA)  : %s  (max_diff = %.2e)\n",
            if (eq_gerber) "[PASS]" else "[FAIL]",
            max(abs(r_gerber - cpp_gerber))))

## 4-2. Gerber (NA 포함)
r_gerber_na   <- .gerber_cor_R(ret_mat_na)
cpp_gerber_na <- cpp_gerber_cor(ret_mat_na)
eq_gerber_na  <- isTRUE(all.equal(r_gerber_na, cpp_gerber_na, tolerance = TOL))
cat(sprintf("  Gerber cor (w/ NA)  : %s  (max_diff = %.2e)\n",
            if (eq_gerber_na) "[PASS]" else "[FAIL]",
            max(abs(r_gerber_na - cpp_gerber_na))))

## 4-3. RMT denoise
q_ratio     <- T_obs / N_assets  # = 6
r_rmt       <- .rmt_denoise_R(r_gerber, q_ratio)
cpp_rmt     <- cpp_rmt_denoise(r_gerber, q_ratio)
# 대각 = 1 확인
diag_ok     <- all(abs(diag(cpp_rmt) - 1.0) < 1e-10)
eq_rmt      <- isTRUE(all.equal(r_rmt, cpp_rmt, tolerance = 1e-6))
cat(sprintf("  RMT denoise         : %s  (max_diff = %.2e, diag=1: %s)\n",
            if (eq_rmt) "[PASS]" else "[FAIL]",
            max(abs(r_rmt - cpp_rmt)),
            if (diag_ok) "OK" else "FAIL"))

## 4-4. HRP bisection
cov_mat   <- r_gerber * outer(apply(ret_mat, 2, sd), apply(ret_mat, 2, sd))
d_mat     <- as.dist(sqrt(0.5 * (1 - r_gerber)))
hc        <- hclust(d_mat, method = "ward.D2")
order_idx <- hc$order

r_hrp     <- .hrp_bisect_R(cov_mat, order_idx)
cpp_hrp   <- cpp_hrp_weights(cov_mat, order_idx)
eq_hrp    <- isTRUE(all.equal(r_hrp, as.numeric(cpp_hrp), tolerance = TOL))
cat(sprintf("  HRP bisection       : %s  (max_diff = %.2e, sum_w = %.6f)\n",
            if (eq_hrp) "[PASS]" else "[FAIL]",
            max(abs(r_hrp - as.numeric(cpp_hrp))),
            sum(cpp_hrp)))

## 4-5. crisis_consec
r_cc      <- .crisis_consec_R(crisis_flag)
cpp_cc    <- cpp_crisis_consec(crisis_flag)
eq_cc     <- identical(r_cc, as.integer(cpp_cc))
cat(sprintf("  crisis_consec       : %s  (max_diff = %d)\n",
            if (eq_cc) "[PASS]" else "[FAIL]",
            max(abs(r_cc - as.integer(cpp_cc)))))

cat("\n")

# ── 5. 속도 벤치마크 ──────────────────────────────────────────────────────────
cat("[5] 속도 벤치마크 (microbenchmark 없는 경우 system.time 사용)\n")
N_rep <- 50

bench_fn <- function(label, r_fn, cpp_fn) {
  t_r   <- system.time(for (i in seq_len(N_rep)) r_fn())[["elapsed"]]
  t_cpp <- system.time(for (i in seq_len(N_rep)) cpp_fn())[["elapsed"]]
  speedup <- if (t_cpp > 0) t_r / t_cpp else Inf
  cat(sprintf("  %-20s  R: %.3fs  Rcpp: %.3fs  speedup: %.1fx\n",
              label, t_r, t_cpp, speedup))
}

bench_fn("Gerber (T=120,N=20)",
         function() .gerber_cor_R(ret_mat),
         function() cpp_gerber_cor(ret_mat))

bench_fn("RMT denoise",
         function() .rmt_denoise_R(r_gerber, q_ratio),
         function() cpp_rmt_denoise(r_gerber, q_ratio))

bench_fn("HRP bisection",
         function() .hrp_bisect_R(cov_mat, order_idx),
         function() cpp_hrp_weights(cov_mat, order_idx))

bench_fn("crisis_consec (n=500)",
         function() .crisis_consec_R(crisis_flag),
         function() cpp_crisis_consec(crisis_flag))

# ── 더 큰 행렬에서도 벤치마크 ─────────────────────────────────────────────────
cat("\n  [더 큰 데이터 — T=250, N=30]\n")
set.seed(99)
big_mat <- matrix(rnorm(250 * 30, 0, 0.02), 250, 30)
colnames(big_mat) <- paste0("B", seq_len(30))
N_rep_big <- 10

t_r_big   <- system.time(for (i in seq_len(N_rep_big)) .gerber_cor_R(big_mat))[["elapsed"]]
t_cpp_big <- system.time(for (i in seq_len(N_rep_big)) cpp_gerber_cor(big_mat))[["elapsed"]]
cat(sprintf("  %-20s  R: %.3fs  Rcpp: %.3fs  speedup: %.1fx\n",
            "Gerber (T=250,N=30)", t_r_big, t_cpp_big,
            if (t_cpp_big > 0) t_r_big / t_cpp_big else Inf))

cat("\n")

# ── 6. 최종 결과 요약 ─────────────────────────────────────────────────────────
all_pass <- eq_gerber && eq_gerber_na && eq_rmt && eq_hrp && eq_cc
cat("=== 최종 결과 ===\n")
cat(sprintf("  컴파일    : OK\n"))
cat(sprintf("  결과 일치 : %s\n", if (all_pass) "전체 PASS" else "일부 FAIL — 위 로그 확인"))
cat("완료:", format(Sys.time()), "\n")

if (!all_pass) quit(save = "no", status = 1)
