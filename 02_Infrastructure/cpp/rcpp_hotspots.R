# =============================================================================
# rcpp_hotspots.R — Rcpp hot-spot wrapper + fallback
# =============================================================================
# 2026-04-24 · L-194/L-195 후속 · Pilot 8+ 사용
#
# Agents (Alpha / Risk / Optimizer / Forge) Rscript 내 `source(...)` 1줄로
# Rcpp hot-spot 2종 활성화. Rcpp 빌드 실패 시 R fallback으로 graceful degrade.
#
# 제공 함수:
#   - roll_beta_fast(y, x, window = 252L, with_r2 = TRUE)
#   - roll_beta_batch_fast(Y_matrix, x_mkt, window = 252L)
#   - bootstrap_ic_fast(alpha, ret, B = 1000L, seed = 42L)
#   - bootstrap_dsr_fast(returns, n_trials = 100L, B = 1000L, seed = 42L)
#
# 사용:
#   source("02_Infrastructure/cpp/rcpp_hotspots.R")
#   bt <- bootstrap_ic_fast(alpha_vec, ret_vec, B = 1000L)
#
# 빌드 캐시:
#   첫 호출 시 Rcpp::sourceCpp()로 컴파일 (~10초). 이후 세션은 cache에서 즉시 로드.
# =============================================================================

suppressPackageStartupMessages({
  library(Rcpp)
})

# ── Build paths ──────────────────────────────────────────────────────────────
.rcpp_cpp_dir <- tryCatch(
  normalizePath(dirname(sys.frame(1)$ofile), winslash = "/"),
  error = function(e) "02_Infrastructure/cpp"
)

.rcpp_build_status <- new.env(parent = emptyenv())
.rcpp_build_status$roll_beta <- FALSE
.rcpp_build_status$bootstrap <- FALSE

# ── Lazy build helper ────────────────────────────────────────────────────────
.build_rcpp_hotspot <- function(cpp_file, label) {
  path <- file.path(.rcpp_cpp_dir, cpp_file)
  if (!file.exists(path)) {
    warning(sprintf("[rcpp_hotspots] %s: file not found at %s",
                    label, path))
    return(FALSE)
  }
  result <- tryCatch({
    t0 <- Sys.time()
    suppressMessages(Rcpp::sourceCpp(path))
    elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat(sprintf("[rcpp_hotspots] %s compiled in %.1fs\n", label, elapsed))
    TRUE
  }, error = function(e) {
    warning(sprintf("[rcpp_hotspots] %s build FAILED: %s. Falling back to R impl.",
                    label, conditionMessage(e)))
    FALSE
  })
  result
}

# ── Rolling β — fast path + fallback ─────────────────────────────────────────
roll_beta_fast <- function(y, x, window = 252L, with_r2 = TRUE) {
  if (!.rcpp_build_status$roll_beta) {
    .rcpp_build_status$roll_beta <- .build_rcpp_hotspot("roll_beta_cpp.cpp",
                                                          "roll_beta_cpp")
  }
  if (isTRUE(.rcpp_build_status$roll_beta) && exists("roll_beta_cpp")) {
    return(roll_beta_cpp(as.numeric(y), as.numeric(x),
                          window = as.integer(window),
                          with_r2 = with_r2))
  }
  # ── R fallback ────────────────────────────────────────────────────────────
  n <- length(y)
  beta <- alpha <- r2 <- rep(NA_real_, n)
  for (t in seq(window, n)) {
    w_y <- y[(t - window + 1):t]
    w_x <- x[(t - window + 1):t]
    if (anyNA(w_y) || anyNA(w_x)) next
    vx <- var(w_x)
    if (vx < 1e-12) next
    b <- cov(w_y, w_x) / vx
    beta[t] <- b
    alpha[t] <- mean(w_y) - b * mean(w_x)
    if (with_r2) {
      vy <- var(w_y)
      r2[t] <- if (vy < 1e-12) 0 else (b * b * vx / vy)
    }
  }
  list(beta = beta, alpha = alpha, r2 = r2,
       window = window, n_valid = sum(!is.na(beta)))
}

roll_beta_batch_fast <- function(Y, x_mkt, window = 252L) {
  if (!.rcpp_build_status$roll_beta) {
    .rcpp_build_status$roll_beta <- .build_rcpp_hotspot("roll_beta_cpp.cpp",
                                                          "roll_beta_cpp")
  }
  if (isTRUE(.rcpp_build_status$roll_beta) && exists("roll_beta_batch_cpp")) {
    return(roll_beta_batch_cpp(as.matrix(Y), as.numeric(x_mkt),
                                 window = as.integer(window)))
  }
  # Fallback: per-column loop
  out <- matrix(NA_real_, nrow = nrow(Y), ncol = ncol(Y))
  colnames(out) <- colnames(Y)
  for (j in seq_len(ncol(Y))) {
    res <- roll_beta_fast(Y[, j], x_mkt, window = window, with_r2 = FALSE)
    out[, j] <- res$beta
  }
  out
}

# ── Bootstrap IC — fast path + fallback ──────────────────────────────────────
bootstrap_ic_fast <- function(alpha, ret, B = 1000L,
                                ci_lower = 0.025, ci_upper = 0.975,
                                seed = 42L, drop_na = TRUE) {
  if (!.rcpp_build_status$bootstrap) {
    .rcpp_build_status$bootstrap <- .build_rcpp_hotspot("bootstrap_cpp.cpp",
                                                           "bootstrap_cpp")
  }
  if (isTRUE(.rcpp_build_status$bootstrap) && exists("bootstrap_ic_cpp")) {
    return(bootstrap_ic_cpp(as.numeric(alpha), as.numeric(ret),
                              B = as.integer(B),
                              ci_lower = ci_lower, ci_upper = ci_upper,
                              seed = as.integer(seed), drop_na = drop_na))
  }
  # R fallback
  ok <- !is.na(alpha) & !is.na(ret)
  alpha <- alpha[ok]; ret <- ret[ok]
  n <- length(alpha)
  if (n < 10) stop("bootstrap_ic_fast: n < 10 after NA drop")
  ic_point <- cor(alpha, ret, method = "spearman")
  set.seed(seed)
  boot_ic <- replicate(B, {
    idx <- sample.int(n, n, replace = TRUE)
    cor(alpha[idx], ret[idx], method = "spearman")
  })
  qs <- quantile(boot_ic, c(ci_lower, ci_upper), na.rm = TRUE)
  pval <- 2 * min(mean(boot_ic <= 0), mean(boot_ic >= 0))
  list(ic_point = ic_point, ic_mean_boot = mean(boot_ic), ic_se = sd(boot_ic),
       ci_lower = qs[[1]], ci_upper = qs[[2]], p_value = min(pval, 1),
       B = B, n = n, seed = seed, boot_samples = boot_ic)
}

bootstrap_dsr_fast <- function(returns, n_trials = 100L, B = 1000L, seed = 42L) {
  if (!.rcpp_build_status$bootstrap) {
    .rcpp_build_status$bootstrap <- .build_rcpp_hotspot("bootstrap_cpp.cpp",
                                                           "bootstrap_cpp")
  }
  if (isTRUE(.rcpp_build_status$bootstrap) && exists("bootstrap_dsr_cpp")) {
    return(bootstrap_dsr_cpp(as.numeric(returns),
                               n_trials = as.integer(n_trials),
                               B = as.integer(B),
                               seed = as.integer(seed)))
  }
  # R fallback
  n <- length(returns)
  sr_full <- mean(returns) / sd(returns) * sqrt(252)
  mu <- mean(returns); sigma <- sd(returns)
  z <- (returns - mu) / sigma
  skew <- mean(z^3)
  kurt <- mean(z^4)
  set.seed(seed)
  boot_sr <- replicate(B, {
    s <- sample(returns, n, replace = TRUE)
    mean(s) / sd(s) * sqrt(252)
  })
  emc <- 0.5772156649
  sr_exp_max <- mean(boot_sr) + sd(boot_sr) *
    ((1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials * exp(1))))
  var_f <- (1 - skew * sr_full + (kurt - 1)/4 * sr_full^2) / (n - 1)
  sr_se <- sqrt(max(var_f, 1e-12))
  dsr <- pnorm((sr_full - sr_exp_max) / sr_se)
  list(sr_full = sr_full, sr_expected_max = sr_exp_max, sr_se = sr_se,
       dsr = dsr, skew = skew, kurtosis = kurt,
       n_trials = n_trials, B = B,
       boot_sr_mean = mean(boot_sr), boot_sr_sd = sd(boot_sr))
}

cat("[rcpp_hotspots.R] v1.0 Loaded. Functions:\n")
cat("  roll_beta_fast(y, x, window=252L)\n")
cat("  roll_beta_batch_fast(Y_matrix, x_mkt, window=252L)\n")
cat("  bootstrap_ic_fast(alpha, ret, B=1000L)\n")
cat("  bootstrap_dsr_fast(returns, n_trials=100L, B=1000L)\n")
cat("  (Rcpp lazy build on first call; R fallback if build fails)\n")
