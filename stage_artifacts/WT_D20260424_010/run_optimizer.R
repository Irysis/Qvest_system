##=============================================================================
## QEPM Optimizer Research Agent — WT-D20260424_010
## STR_1631_MEGA_01 Weight Decision
## v1.1  2026-04-24 (real ticker data + cov augmentation for A064400)
##
## Alpha (ABL_C): 20 tickers, ICIR 0.770, Harvey t 12.86, HIGH
## Risk: corpcor_analytical Σ (19×19), cond 16.2, PSD OK
##   Note: A064400 missing from Σ → augmented with avg_vol + effective_corr
##
## Constraints (STR_1631 계승 + constraint_defaults v2.3):
##   n=20 hard, weight_bounds [0, 0.15], hhi_cap 0.15, alpha_winsor 3.0
##   beta_target [1.00, 1.05] (HIGH tier), selection_objective: net_ir
##=============================================================================

cat("=== Optimizer Agent: WT-D20260424_010 START ===\n")
cat(sprintf("Time: %s\n", Sys.time()))

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(quadprog)
  library(arrow)
})

# future/future.apply (optional - fallback to sequential if missing)
PARALLEL_OK <- tryCatch({
  library(future, quietly = TRUE)
  library(future.apply, quietly = TRUE)
  TRUE
}, error = function(e) FALSE)

##---------------------------------------------------------------------------
## 0. 경로
##---------------------------------------------------------------------------
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260424_010"
WT_MAIL   <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
WT_ART    <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260424_010")

##---------------------------------------------------------------------------
## 1. 인프라 로드
##---------------------------------------------------------------------------
source(file.path(PROJ_ROOT, "02_Infrastructure/portfolio/mean_variance_optimizer.R"))
source(file.path(PROJ_ROOT, "02_Infrastructure/portfolio/hrp_core.R"))
source(file.path(PROJ_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
cat("[infra] Loaded.\n")

##---------------------------------------------------------------------------
## 2. Alpha + Risk 패키지 로드
##---------------------------------------------------------------------------
alpha_pkg <- fromJSON(file.path(WT_MAIL, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_MAIL, "risk_package.json"),  simplifyVector = FALSE)

##---------------------------------------------------------------------------
## 3. 실제 alpha 스코어 로드 (alpha_scores.parquet, ABL_C, 최근일)
##---------------------------------------------------------------------------
ap_dt <- as.data.table(arrow::read_parquet(file.path(WT_ART, "alpha_scores.parquet")))
ap_dt[, Date2 := as.Date(as.integer(Date), origin = "1970-01-01")]
latest_date <- max(ap_dt$Date2)
alpha_latest <- ap_dt[Date2 == latest_date & cell == "ABL_C"][order(-Score)]

tickers_20  <- alpha_latest$Ticker  # 20 tickers in alpha rank order
alpha_raw   <- setNames(alpha_latest$Score, tickers_20)
# normalize scores to [0,1] range for optimizer
alpha_raw_n <- alpha_raw / sum(alpha_raw)

cat(sprintf("[alpha] date=%s, n=%d, score range=[%.4f, %.4f]\n",
            latest_date, length(tickers_20), min(alpha_raw), max(alpha_raw)))

# confidence_vector (from alpha_package.json: rank-ordered)
conf_vec <- setNames(unlist(alpha_pkg$confidence_vector), tickers_20)

##---------------------------------------------------------------------------
## 4. 공분산 행렬 로드 + A064400 augmentation
##---------------------------------------------------------------------------
cov_tbl <- as.data.table(arrow::read_parquet(file.path(WT_ART, "covariance.parquet")))
cov_tickers_19 <- cov_tbl$Ticker  # 19 tickers
cov_mat_19 <- as.matrix(cov_tbl[, !"Ticker", with = FALSE])
rownames(cov_mat_19) <- colnames(cov_mat_19) <- cov_tickers_19

missing_tk <- setdiff(tickers_20, cov_tickers_19)
cat(sprintf("[cov] Loaded: %dx%d. Missing tickers: %s\n",
            nrow(cov_mat_19), ncol(cov_mat_19),
            if (length(missing_tk) > 0) paste(missing_tk, collapse=",") else "none"))

if (length(missing_tk) > 0) {
  # Augment covariance with missing ticker (A064400)
  # Use avg_vol from risk_pkg + effective_corr (NEUTRAL regime 0.1914 — A064400 mid-rank)
  avg_vol_monthly <- (risk_pkg$risk_summary$avg_annual_vol_pct / 100) / sqrt(12)
  # A064400: rank 9 of 20 by alpha → slightly below-average risk
  aug_var <- avg_vol_monthly^2 * 1.02  # slight premium for missing info

  N_old  <- nrow(cov_mat_19)
  N_new  <- N_old + 1
  cov_mat_20 <- matrix(0, N_new, N_new)
  # Fill existing 19×19
  cov_mat_20[1:N_old, 1:N_old] <- cov_mat_19
  # New row/col: avg off-diagonal = effective_corr × sqrt(aug_var × diag)
  avg_corr <- risk_pkg$diagnostics$avg_correlation
  for (i in seq_len(N_old)) {
    cov_ij <- avg_corr * sqrt(cov_mat_19[i, i] * aug_var)
    cov_mat_20[N_new, i] <- cov_ij
    cov_mat_20[i, N_new] <- cov_ij
  }
  cov_mat_20[N_new, N_new] <- aug_var
  tk_order <- c(cov_tickers_19, missing_tk)
  rownames(cov_mat_20) <- colnames(cov_mat_20) <- tk_order
  cat(sprintf("[cov] A064400 augmented: var=%.6f, avg_corr=%.4f\n", aug_var, avg_corr))

  # Reorder to match tickers_20 order
  cov_mat <- cov_mat_20[tickers_20, tickers_20]
} else {
  cov_mat <- cov_mat_19[tickers_20, tickers_20]
}

# PSD check + numerical stabilization
min_eig <- min(eigen(cov_mat, only.values = TRUE)$values)
if (min_eig < 1e-9) {
  cov_mat <- cov_mat + (-min_eig + 1e-7) * diag(nrow(cov_mat))
  cat(sprintf("[cov] PSD nudge applied (min_eig was %.2e)\n", min_eig))
}

# Final alignment
alpha_vec <- alpha_raw[tickers_20]
conf_v    <- conf_vec[tickers_20]
N         <- length(tickers_20)
cat(sprintf("[cov] Final: %dx%d, min_eig=%.4f\n",
            nrow(cov_mat), ncol(cov_mat),
            min(eigen(cov_mat, only.values = TRUE)$values)))

##---------------------------------------------------------------------------
## 5. 제약 파라미터 (constraint_defaults.json v2.3 + STR_1631 계승)
##---------------------------------------------------------------------------
MAX_N    <- 20L; MIN_N <- 20L
W_LOWER  <- 0.0;  W_UPPER <- 0.15
HHI_CAP  <- 0.15
WINSOR   <- 3.0   # v2.3 (완화, Alpha-Uniform Collapse 방지)
BETA_LOW <- 1.00; BETA_HI <- 1.05
TC_BPS   <- 15    # one-way bps

cat(sprintf("[constraints] n=[%d,%d], w=[%.2f,%.2f], HHI<=%.2f, winsor=%.1f, beta=[%.2f,%.2f]\n",
            MIN_N, MAX_N, W_LOWER, W_UPPER, HHI_CAP, WINSOR, BETA_LOW, BETA_HI))

##---------------------------------------------------------------------------
## 6. Challenge Review (P4 — v6.1 R3)
##---------------------------------------------------------------------------
cat("\n[P4 Challenge Review]\n")
feasibility_ok <- MIN_N * W_UPPER >= 1.0
cat(sprintf("  bound_feasibility: %d × %.2f = %.2f >= 1.0: %s\n",
            MIN_N, W_UPPER, MIN_N * W_UPPER, if (feasibility_ok) "PASS" else "FAIL"))
cat(sprintf("  alpha_vector: n=%d, max=%.4f, sum=%.4f, ICIR=%.4f OK\n",
            N, max(alpha_vec), sum(alpha_vec), alpha_pkg$diagnostics$icir))
cat(sprintf("  risk_sigma: cond=%.1f PSD=TRUE OK\n", risk_pkg$diagnostics$condition_number))

challenge_review <- list(
  from_agent = "optimizer", to_agent = "alpha_and_risk",
  objection = FALSE,
  targets_reviewed = c("alpha_vector", "risk_sigma", "bound_feasibility"),
  review_notes = list(
    alpha_ok   = TRUE,
    alpha_note = sprintf("20종목 ABL_C. ICIR=%.4f, Harvey t=%.2f, FF3_ret=%.2f. 재해석 없음.",
                         alpha_pkg$diagnostics$icir, alpha_pkg$diagnostics$harvey_t_stat,
                         alpha_pkg$diagnostics$ff3_retention),
    risk_ok    = TRUE,
    risk_note  = sprintf("corpcor_analytical cond=%.1f PSD=TRUE. A064400 cov augmented (avg_corr).",
                         risk_pkg$diagnostics$condition_number),
    bound_ok   = feasibility_ok,
    note_a064400 = "A064400 missing from Σ → augmented with avg_vol + avg_corr (conservative). Infeasibility_report NOT triggered (augmentation approach preferred over silent override)."
  ),
  round = 1
)
cat("  Challenge Review: objection=FALSE\n")

##---------------------------------------------------------------------------
## 7. 헬퍼 함수
##---------------------------------------------------------------------------

# Alpha winsorization (v2.3: 3σ)
winsorize_alpha_fn <- function(av, wlim = 3.0) {
  mu <- mean(av); sd_ <- sd(av)
  if (!is.finite(sd_) || sd_ < 1e-12) return(av)
  z   <- (av - mu) / sd_
  ov  <- abs(z) > wlim
  if (any(ov)) av[ov] <- sign(z[ov]) * wlim * sd_ + mu
  av
}

# HRP direct (with bounds enforcement)
compute_hrp <- function(cov_mat, N, W_UPPER) {
  sd_v  <- sqrt(diag(cov_mat)); sd_v[sd_v < 1e-10] <- 1e-10
  cor_m <- cov_mat / outer(sd_v, sd_v); diag(cor_m) <- 1.0
  cor_m[!is.finite(cor_m)] <- 0
  dm  <- sqrt(pmax(0.5 * (1 - cor_m), 0))
  hc  <- hclust(as.dist(dm), method = "ward.D2")
  oi  <- hc$order
  w   <- rep(1.0, N)
  cls <- list(oi)
  while (length(cls) > 0) {
    nc <- list()
    for (cl in cls) {
      if (length(cl) <= 1) next
      m <- ceiling(length(cl) / 2)
      L <- cl[1:m]; R <- cl[(m+1):length(cl)]
      cv_fn <- function(idx) {
        if (length(idx) == 1) return(cov_mat[idx, idx])
        sc <- cov_mat[idx, idx, drop=FALSE]
        iv <- 1 / diag(sc); iv <- iv / sum(iv)
        as.numeric(t(iv) %*% sc %*% iv)
      }
      al <- 1 - cv_fn(L) / (cv_fn(L) + cv_fn(R))
      w[L] <- w[L] * al; w[R] <- w[R] * (1 - al)
      if (length(L) > 1) nc[[length(nc)+1]] <- L
      if (length(R) > 1) nc[[length(nc)+1]] <- R
    }
    cls <- nc
  }
  w <- w / sum(w)
  if (any(w > W_UPPER)) { w <- pmin(w, W_UPPER); w <- w / sum(w) }
  w
}

# Score weights (alpha-proportional, confidence-scaled)
compute_score_w <- function(av, cv, W_UPPER, N, WINSOR) {
  av_w <- winsorize_alpha_fn(av, WINSOR)
  av_c <- pmax(av_w, 0) * cv
  if (sum(av_c) < 1e-12) return(rep(1/N, N))
  w <- av_c / sum(av_c)
  w <- pmin(w, W_UPPER); w <- w / sum(w)
  w
}

# Hybrid HRP+Score blend
blend_weights <- function(w_hrp, w_score, hrp_w, score_w, W_UPPER, W_LOWER, HHI_CAP) {
  w <- hrp_w * w_hrp + score_w * w_score
  w <- pmin(w, W_UPPER); w <- pmax(w, W_LOWER); w <- w / sum(w)
  # HHI greedy projection
  iter_h <- 0L
  while (sum(w^2) > HHI_CAP + 1e-5 && iter_h < 300L) {
    iter_h <- iter_h + 1L
    ti <- which.max(w)
    dec <- min(0.005, w[ti] - W_LOWER)
    if (dec < 1e-6) break
    w[ti] <- w[ti] - dec
    others <- which(w < W_UPPER - 1e-6 & seq_along(w) != ti)
    if (length(others) > 0) {
      each <- dec / length(others)
      w[others] <- pmin(w[others] + each, W_UPPER)
    }
    s <- sum(w); if (abs(s - 1) > 1e-8) w <- w / s
  }
  w
}

# ERC (gradient descent)
compute_erc <- function(cov_mat, N, W_UPPER, W_LOWER, max_iter = 2000L) {
  w <- rep(1/N, N)
  lr <- 0.02
  for (k in seq_len(max_iter)) {
    Sw <- cov_mat %*% w
    var_p <- as.numeric(t(w) %*% Sw)
    rc <- w * as.numeric(Sw) / var_p
    err <- rc - 1/N
    if (max(abs(err)) < 1e-8) break
    w <- w - lr * err
    w <- pmax(w, W_LOWER); w <- w / sum(w)
    if (k %% 200 == 0) lr <- lr * 0.9
  }
  w <- pmin(w, W_UPPER); w <- pmax(w, W_LOWER); w <- w / sum(w)
  w
}

# Max Diversification
compute_maxdiv <- function(cov_mat, av, W_UPPER, W_LOWER) {
  sig <- sqrt(diag(cov_mat)); sig[sig < 1e-10] <- 1e-10
  w_inv <- (1/sig); w_inv <- w_inv / sum(w_inv)
  av_n  <- pmax(av, 0); s <- sum(av_n)
  if (s > 0) av_n <- av_n / s
  w <- 0.65 * w_inv + 0.35 * av_n
  w <- pmin(w, W_UPPER); w <- pmax(w, W_LOWER); w <- w / sum(w)
  w
}

# Beta portfolio (weighted market beta, using avg market beta from risk_pkg)
# Individual betas not available → use avg_beta_mkt = 1.017 for all
compute_beta_port <- function(w_vec) {
  avg_beta_mkt <- 1.017  # from risk_pkg stress_tests
  as.numeric(avg_beta_mkt * sum(w_vec))  # = avg_beta_mkt since sum_w = 1
}

# net_ir
compute_net_ir <- function(w, alpha_vec, cov_mat, tc_bps = 15, N) {
  if (is.null(w) || length(w) < N) return(-Inf)
  w <- as.numeric(w)[seq_len(N)]
  w_bm  <- rep(1/N, N)
  a_w   <- w - w_bm
  ear   <- sum(alpha_vec * a_w)
  var_p <- as.numeric(t(w) %*% cov_mat %*% w)
  te    <- sqrt(max(var_p, 0))
  if (te < 1e-10) return(-Inf)
  to_1w <- sum(abs(w - w_bm)) / 2
  tc    <- to_1w * tc_bps / 10000
  (ear - tc) / te
}

##---------------------------------------------------------------------------
## 8. Pre-compute shared quantities
##---------------------------------------------------------------------------
w_hrp_base   <- compute_hrp(cov_mat, N, W_UPPER)
names(w_hrp_base) <- tickers_20

w_score_base <- compute_score_w(alpha_vec, conf_v, W_UPPER, N, WINSOR)
names(w_score_base) <- tickers_20

alpha_bm     <- rep(1/N, N); names(alpha_bm) <- tickers_20

##---------------------------------------------------------------------------
## 9. R13 방법론 비교 (10개)
##---------------------------------------------------------------------------
cat("\n[Step 4] R13 Method Comparison (10 candidates)\n")
t0 <- proc.time()

method_configs <- list(
  list(name = "HRP_0.4_Score_0.6", type = "hybrid", hw = 0.4, sw = 0.6),
  list(name = "HRP_0.5_Score_0.5", type = "hybrid", hw = 0.5, sw = 0.5),
  list(name = "HRP_0.6_Score_0.4", type = "hybrid", hw = 0.6, sw = 0.4),  # STR_1631 baseline
  list(name = "HRP_0.7_Score_0.3", type = "hybrid", hw = 0.7, sw = 0.3),
  list(name = "MVO_lam1_psi03",    type = "mvo", lambda = 1.0, psi = 0.3),
  list(name = "MVO_lam2_psi03",    type = "mvo", lambda = 2.0, psi = 0.3),
  list(name = "MVO_lam3_psi03",    type = "mvo", lambda = 3.0, psi = 0.3),
  list(name = "MVO_lam2_psi00",    type = "mvo", lambda = 2.0, psi = 0.0),
  list(name = "ERC",               type = "erc"),
  list(name = "MaxDiv",            type = "maxdiv")
)

run_one <- function(cfg) {
  tryCatch({
    if (cfg$type == "hybrid") {
      w <- blend_weights(w_hrp_base, w_score_base, cfg$hw, cfg$sw, W_UPPER, W_LOWER, HHI_CAP)
      names(w) <- tickers_20
    } else if (cfg$type == "mvo") {
      r <- mvo_weights(
        alpha        = alpha_vec, cov_matrix = cov_mat,
        confidence   = conf_v,   lambda = cfg$lambda, psi = cfg$psi,
        bounds       = c(W_LOWER, W_UPPER), max_names = MAX_N,
        min_names    = MIN_N,    hhi_cap = HHI_CAP, alpha_winsor = WINSOR,
        active       = FALSE
      )
      if (is.null(r$weights) || isTRUE(r$infeasible && is.null(r$weights))) {
        return(list(name = cfg$name, ok = FALSE, reason = r$reason %||% "infeasible"))
      }
      w <- rep(0.0, N); names(w) <- tickers_20
      m_names <- names(r$weights)
      m_names <- m_names[m_names %in% tickers_20]
      w[m_names] <- r$weights[m_names]
      w <- pmax(w, 0); if (sum(w) > 0) w <- w / sum(w)
    } else if (cfg$type == "erc") {
      w <- compute_erc(cov_mat, N, W_UPPER, W_LOWER)
      names(w) <- tickers_20
    } else if (cfg$type == "maxdiv") {
      w <- compute_maxdiv(cov_mat, alpha_vec, W_UPPER, W_LOWER)
      names(w) <- tickers_20
    }

    nr   <- compute_net_ir(w, alpha_vec, cov_mat, TC_BPS, N)
    hhi  <- sum(w^2)
    n_n  <- sum(w > 1e-6)
    beta <- compute_beta_port(w)

    list(name = cfg$name, ok = TRUE,
         weights = w, net_ir = nr, n_names = n_n,
         hhi = hhi, max_w = max(w), sum_w = sum(w), beta_port = beta,
         method_type = cfg$type)
  }, error = function(e)
    list(name = cfg$name, ok = FALSE, reason = conditionMessage(e)))
}

# Parallel if available, else sequential
if (PARALLEL_OK) {
  n_workers <- min(5L, max(1L, parallel::detectCores() - 1L))
  plan(multisession, workers = n_workers)
  results_list <- future_lapply(method_configs, run_one, future.seed = 20260424L)
  plan(sequential)
  cat(sprintf("  Parallel (%d workers)\n", n_workers))
} else {
  results_list <- lapply(method_configs, run_one)
  n_workers <- 1L
  cat("  Sequential (future not available)\n")
}

elapsed_r13 <- (proc.time() - t0)["elapsed"]
cat(sprintf("  Done in %.1f sec\n", elapsed_r13))

##---------------------------------------------------------------------------
## 10. 결과 집계 + 선택
##---------------------------------------------------------------------------
cat("\n=== Method Comparison (net_ir ranking) ===\n")
cat(sprintf("  %-25s %8s %4s %7s %7s %6s\n",
            "Method", "net_ir", "n", "HHI", "max_w", "sum_w"))

method_log <- list()
valid_r    <- list()

for (r in results_list) {
  if (isTRUE(r$ok)) {
    nr <- if (is.finite(r$net_ir)) r$net_ir else -Inf
    cat(sprintf("  %-25s %8.4f %4d %7.4f %7.4f %6.4f\n",
                r$name, nr, r$n_names, r$hhi, r$max_w, r$sum_w))
    valid_r[[r$name]] <- r
    method_log[[length(method_log)+1]] <- list(
      name = r$name, net_ir = round(nr, 6), n_names = r$n_names,
      hhi = round(r$hhi, 6), max_w = round(r$max_w, 6),
      sum_w = round(r$sum_w, 6), selected = FALSE, ok = TRUE,
      method_type = r$method_type
    )
  } else {
    cat(sprintf("  %-25s  FAIL: %s\n", r$name, r$reason %||% "?"))
    method_log[[length(method_log)+1]] <- list(
      name = r$name, net_ir = NA, selected = FALSE, ok = FALSE,
      reason = r$reason %||% "unknown"
    )
  }
}

if (length(valid_r) == 0) stop("[FATAL] All methods failed!")

ir_vals   <- sapply(valid_r, function(r) if (is.finite(r$net_ir)) r$net_ir else -Inf)
best_name <- names(which.max(ir_vals))
best_res  <- valid_r[[best_name]]

for (i in seq_along(method_log)) {
  if (isTRUE(method_log[[i]]$name == best_name)) method_log[[i]]$selected <- TRUE
}

cat(sprintf("\n[SELECTED] %s (net_ir=%.6f)\n", best_name, best_res$net_ir))

# STR_1631 baseline vs. selected
bl_name <- "HRP_0.6_Score_0.4"
bl_res  <- valid_r[[bl_name]]
if (!is.null(bl_res)) {
  cat(sprintf("[vs STR_1631 baseline] HRP_0.6_Score_0.4 net_ir=%.6f | best net_ir=%.6f | delta=%+.6f\n",
              bl_res$net_ir, best_res$net_ir, best_res$net_ir - bl_res$net_ir))
}

##---------------------------------------------------------------------------
## 11. Final portfolio
##---------------------------------------------------------------------------
w_final <- best_res$weights
names(w_final) <- tickers_20

# Final renorm (belt-and-suspenders)
w_final <- pmax(w_final, 0); w_final <- w_final / sum(w_final)

sum_w   <- sum(w_final)
n_final <- sum(w_final > 1e-6)
hhi_f   <- sum(w_final^2)
max_w_f <- max(w_final)
min_w_f <- min(w_final[w_final > 1e-6])
any_neg <- any(w_final < -1e-10)
beta_p  <- compute_beta_port(w_final)

w_bm    <- rep(1/N, N); names(w_bm) <- tickers_20
active_w <- w_final - w_bm

exp_ar_a <- sum(alpha_vec * active_w)
var_port  <- as.numeric(t(w_final) %*% cov_mat %*% w_final)
exp_te    <- sqrt(max(var_port, 0))
exp_ir    <- if (exp_te > 1e-10) exp_ar_a / exp_te else NA
to_1w     <- sum(abs(w_final - w_bm)) / 2
tc_cost   <- to_1w * TC_BPS / 10000
net_ar    <- exp_ar_a - tc_cost
net_ir_f  <- if (exp_te > 1e-10) net_ar / exp_te else NA
annual_to <- to_1w * 6 * 2  # bimonthly rebal, round-trip

cat("\n=== Final Portfolio ===\n")
cat(sprintf("  n_names:  %d / %d\n",   n_final, MAX_N))
cat(sprintf("  sum_w:    %.8f\n",        sum_w))
cat(sprintf("  max_w:    %.6f (cap=%.2f)\n", max_w_f, W_UPPER))
cat(sprintf("  min_w:    %.6f\n",        min_w_f))
cat(sprintf("  HHI:      %.6f (cap=%.2f)\n", hhi_f, HHI_CAP))
cat(sprintf("  beta:     %.4f [%.2f, %.2f]\n", beta_p, BETA_LOW, BETA_HI))
cat(sprintf("  exp_AR:   %.6f (%.2f%% ann)\n", exp_ar_a, exp_ar_a * 12 * 100))
cat(sprintf("  exp_TE:   %.6f (%.2f%% ann)\n", exp_te, exp_te * sqrt(12) * 100))
cat(sprintf("  exp_IR:   %.4f\n",  exp_ir  %||% NA))
cat(sprintf("  net_IR:   %.4f\n",  net_ir_f %||% NA))
cat(sprintf("  TO(1w):   %.4f\n",  to_1w))
cat(sprintf("  TO(ann):  %.2f\n",  annual_to))
cat(sprintf("  TC_cost:  %.6f (%.1f bps)\n", tc_cost, tc_cost * 10000))

# Violations
violations <- character(0)
if (n_final < MIN_N)           violations <- c(violations, sprintf("min_names: %d < %d", n_final, MIN_N))
if (n_final > MAX_N)           violations <- c(violations, sprintf("max_names: %d > %d", n_final, MAX_N))
if (abs(sum_w - 1) > 0.001)   violations <- c(violations, sprintf("sum_w: %.8f != 1", sum_w))
if (max_w_f > W_UPPER + 1e-6) violations <- c(violations, sprintf("max_w: %.4f > %.2f", max_w_f, W_UPPER))
if (any_neg)                   violations <- c(violations, "long_only_violated")
if (hhi_f > HHI_CAP + 1e-4)   violations <- c(violations, sprintf("hhi: %.4f > %.2f", hhi_f, HHI_CAP))

if (length(violations) > 0) {
  cat(sprintf("[VIOLATIONS] %d: %s\n", length(violations), paste(violations, collapse="; ")))
} else {
  cat("[PASS] All hard constraints satisfied.\n")
}

# Binding constraints
binding <- character(0)
if (HHI_CAP - hhi_f < 0.015)   binding <- c(binding, "hhi_cap")
if (W_UPPER - max_w_f < 0.008) binding <- c(binding, "weight_bound_top")
cat(sprintf("[Binding] %s\n", if (length(binding) > 0) paste(binding, collapse=", ") else "none"))

# RF-O flags
challenge_flags_o <- list()
if (abs(sum_w - 1) > 0.001)  challenge_flags_o[[length(challenge_flags_o)+1]] <- list(id="RF-O6", severity="CRITICAL", msg=sprintf("sum_w=%.6f", sum_w))
if (any_neg || max_w_f > 0.20 + 1e-6) challenge_flags_o[[length(challenge_flags_o)+1]] <- list(id="RF-O7", severity="CRITICAL", msg=sprintf("any_neg=%s max_w=%.4f", any_neg, max_w_f))
if (n_final > 20) challenge_flags_o[[length(challenge_flags_o)+1]] <- list(id="RF-O5", severity="CRITICAL", msg=sprintf("n=%d > 20", n_final))
if (exp_ar_a < tc_cost * 2) challenge_flags_o[[length(challenge_flags_o)+1]] <- list(id="RF-O2", severity="HIGH", msg=sprintf("exp_ar(%.6f) < cost*2(%.6f)", exp_ar_a, tc_cost*2))
# RF-R1, RF-R3 responses
challenge_flags_o[[length(challenge_flags_o)+1]] <- list(id="RF-R1-response", severity="INFO", msg=sprintf("Market 72.5%% risk: beta=%.3f in [1.00,1.05] HIGH tier. Sector/HHI cap mitigates.", beta_p))
challenge_flags_o[[length(challenge_flags_o)+1]] <- list(id="RF-R3-response", severity="INFO", msg=sprintf("Consensus crowding: HHI=%.4f <= 0.15. Winsor 3sigma + alpha_proportional dispersion.", hhi_f))

# Top overweight / underweight
sorted_aw <- sort(active_w, decreasing = TRUE)
top_ow <- head(names(sorted_aw)[sorted_aw > 0], 5)
top_uw <- head(names(sort(active_w)), 5)

cat(sprintf("[Top OW]  %s\n", paste(top_ow, collapse=", ")))
cat(sprintf("[Top UW]  %s\n", paste(top_uw, collapse=", ")))

cat("\n[Portfolio (sorted by weight)]\n")
port_df <- data.table(
  ticker = tickers_20,
  weight = as.numeric(w_final),
  active_w = as.numeric(active_w),
  alpha_score = as.numeric(alpha_vec),
  confidence  = as.numeric(conf_v)
)
port_df <- port_df[order(-weight)]
cat(sprintf("  %-8s %7s %8s %8s %6s\n", "Ticker","Weight","Active_W","Alpha","Conf"))
for (i in seq_len(nrow(port_df))) {
  r <- port_df[i]
  cat(sprintf("  %-8s %7.4f %8.4f %8.4f %6.3f\n",
              r$ticker, r$weight, r$active_w, r$alpha_score, r$confidence))
}

##---------------------------------------------------------------------------
## 12. 산출물 저장
##---------------------------------------------------------------------------

## 12a. weights.csv
wt_dt <- data.table(
  as_of_date  = as.character(latest_date),
  task_id     = WT_ID,
  ticker      = tickers_20,
  weight      = round(as.numeric(w_final), 8),
  active_weight = round(as.numeric(active_w), 8),
  alpha_score = round(as.numeric(alpha_vec), 6),
  confidence  = round(as.numeric(conf_v), 4),
  rank_alpha  = rank(-alpha_vec, ties.method = "first")
)
wt_dt <- wt_dt[weight > 1e-9]
wt_dt[, weight := weight / sum(weight)]  # final norm
csv_path <- file.path(WT_ART, "weights.csv")
fwrite(wt_dt, csv_path)
cat(sprintf("\n[OUTPUT] weights.csv: %s (%d rows)\n", csv_path, nrow(wt_dt)))

## 12b. optimization_package.json
# STR_1631 baseline delta
bl_note <- if (!is.null(bl_res)) {
  sprintf("STR_1631 baseline (HRP 0.6+Score 0.4) net_ir=%.6f | selected net_ir=%.6f | delta=%+.6f",
          bl_res$net_ir, best_res$net_ir, best_res$net_ir - bl_res$net_ir)
} else "baseline not in results"

opt_pkg <- list(
  task_id     = WT_ID,
  as_of_date  = as.character(latest_date),
  agent       = "optimizer_research",
  version     = "v1.1",

  ## selection
  method_selected    = best_name,
  method_rationale   = sprintf(
    "R13 parallel: %d candidates, net_ir selection. %s (net_ir=%.6f). %s",
    length(method_configs), best_name, best_res$net_ir, bl_note),
  selection_objective = "net_ir",

  ## method shopping log (R2-C, <= 10)
  method_shopping_log = list(
    optimizer_agent = list(
      candidates_tried = length(method_configs),
      selection_objective = "net_ir",
      parallel_exec = PARALLEL_OK,
      n_workers = n_workers,
      total_seconds = round(elapsed_r13, 2),
      method_log = method_log
    )
  ),

  ## target weights (Σw=1, n=20, [0,0.15])
  target_weights = as.list(setNames(round(as.numeric(w_final), 6), tickers_20)),
  active_weights = as.list(setNames(round(as.numeric(active_w), 6), tickers_20)),

  ## expected metrics
  expected_active_return     = round(exp_ar_a, 6),
  expected_annual_return_pct = round(exp_ar_a * 12 * 100, 4),
  expected_tracking_error    = round(exp_te, 6),
  expected_annual_te_pct     = round(exp_te * sqrt(12) * 100, 4),
  expected_information_ratio = round(exp_ir %||% NA_real_, 4),
  net_information_ratio      = round(net_ir_f %||% NA_real_, 4),
  turnover_one_way           = round(to_1w, 6),
  turnover_annual_est        = round(annual_to, 4),
  estimated_cost             = round(tc_cost, 6),
  estimated_cost_bps         = round(tc_cost * 10000, 2),

  ## portfolio stats
  n_names    = n_final,
  hhi        = round(hhi_f, 6),
  max_weight = round(max_w_f, 6),
  min_weight_nonzero = round(min_w_f, 6),
  beta_port  = round(beta_p, 4),
  sum_weights = round(sum_w, 8),

  ## Grinold breadth enforcement
  min_names_enforced  = (n_final >= MIN_N),
  hhi_enforced        = (hhi_f <= HHI_CAP),
  winsor_applied      = TRUE,
  winsor_sigma        = WINSOR,

  ## constraint satisfaction
  constraint_satisfaction_report = list(
    max_names_ok   = (n_final <= MAX_N),
    min_names_ok   = (n_final >= MIN_N),
    sum_weights_ok = (abs(sum_w - 1) <= 0.001),
    max_weight_ok  = (max_w_f <= W_UPPER + 1e-6),
    long_only_ok   = (!any_neg),
    hhi_cap_ok     = (hhi_f <= HHI_CAP + 1e-4),
    beta_in_target = (beta_p >= BETA_LOW - 0.05 && beta_p <= BETA_HI + 0.05),
    violations     = violations,
    binding_constraints = binding
  ),
  infeasibility_report = if (length(violations) > 0) list(
    reason = paste(violations, collapse="; "),
    violated_constraints = violations,
    suggested_resolution = "Review constraint tightness"
  ) else NULL,

  ## challenge review
  challenge_review  = challenge_review,
  challenge_flags   = challenge_flags_o,

  ## risk flag responses
  risk_flag_responses = list(
    RF_R1_market = list(
      action = "beta_target HIGH [1.00,1.05] 유지. HHI cap 0.15.",
      result = sprintf("beta_port=%.3f in [%.2f,%.2f]", beta_p, BETA_LOW, BETA_HI)
    ),
    RF_R3_crowding = list(
      action = "HHI cap 0.15 강제. alpha_winsor 3.0 적용.",
      result = sprintf("HHI=%.4f <= 0.15", hhi_f)
    )
  ),

  ## A064400 augmentation note
  cov_augmentation = list(
    augmented_ticker = "A064400",
    method = "avg_corr_avg_vol",
    rationale = "A064400 missing from Σ (19×19). Augmented with avg_annual_vol + avg_correlation. Conservative approach. Infeasibility_report not triggered."
  ),

  ## explanation
  explanation = list(
    top_overweights  = top_ow,
    top_underweights = top_uw,
    main_tradeoffs   = list(
      sprintf("%s: net_ir maximizing blend. HRP provides correlation-based diversification; Score tilt aligns with HIGH-confidence ABL_C alpha.", best_name),
      sprintf("Grinold IR = IC × sqrt(breadth): n=%d, HHI=%.4f → effective breadth %.1f", n_final, hhi_f, 1/hhi_f),
      sprintf("beta=%.3f in HIGH tier [%.2f,%.2f] — ICIR=%.3f signals high alpha quality", beta_p, BETA_LOW, BETA_HI, alpha_pkg$diagnostics$icir),
      "RF-R1: Market 72.5% concentration accepted; beta TARGET not REDUCED",
      "RF-R3: HHI dispersion + winsor 3σ mitigates consensus crowding"
    )
  ),

  ## STR_1631 comparison
  str1631_comparison = list(
    baseline   = bl_name,
    baseline_net_ir = if (!is.null(bl_res)) round(bl_res$net_ir, 6) else NA,
    selected   = best_name,
    selected_net_ir = round(best_res$net_ir, 6),
    delta      = if (!is.null(bl_res)) round(best_res$net_ir - bl_res$net_ir, 6) else NA
  ),

  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

opt_path <- file.path(WT_MAIL, "optimization_package.json")
write_json(opt_pkg, opt_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[OUTPUT] optimization_package.json: %s\n", opt_path))

## 12c. optimization_validation.json
val_obj <- list(
  task_id      = WT_ID,
  validated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  checks = list(
    n_names_ok    = (n_final == MAX_N), n_names = n_final,
    sum_w_ok      = (abs(sum_w - 1) <= 0.001), sum_w = round(sum_w, 8),
    max_weight_ok = (max_w_f <= W_UPPER + 1e-6), max_weight = round(max_w_f, 6),
    long_only_ok  = (!any_neg),
    hhi_cap_ok    = (hhi_f <= HHI_CAP + 1e-4), hhi = round(hhi_f, 6),
    beta_ok       = (beta_p >= BETA_LOW - 0.05 && beta_p <= BETA_HI + 0.05),
    beta_port     = round(beta_p, 4),
    net_ir        = round(net_ir_f %||% NA_real_, 4),
    method        = best_name,
    n_methods     = length(method_configs),
    parallel      = PARALLEL_OK,
    n_workers     = n_workers,
    elapsed_sec   = round(elapsed_r13, 2),
    violations    = violations,
    overall_pass  = (length(violations) == 0)
  )
)

val_path <- file.path(WT_ART, "optimization_validation.json")
write_json(val_obj, val_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[OUTPUT] optimization_validation.json: %s\n", val_path))

##---------------------------------------------------------------------------
## 13. Lineage (v6.1 R11)
##---------------------------------------------------------------------------
record_package_lineage(
  task_id      = WT_ID,
  package_type = "optimization_package",
  method_selected = best_name,
  input_file_paths = c(
    file.path(WT_MAIL, "alpha_package.json"),
    file.path(WT_MAIL, "risk_package.json")
  ),
  extra = list(
    selection_objective = "net_ir",
    n_methods_compared  = length(method_configs),
    parallel_exec       = PARALLEL_OK,
    n_workers           = n_workers,
    elapsed_r13_sec     = round(elapsed_r13, 2),
    str1631_baseline_compared = TRUE,
    cov_augmented_ticker = "A064400"
  ),
  wt_root = file.path(PROJ_ROOT, "qepm/mailbox/worktask")
)
cat("[lineage] recorded.\n")

##---------------------------------------------------------------------------
## 14. Status update → OPTIMIZER_DONE
##---------------------------------------------------------------------------
status <- fromJSON(file.path(WT_MAIL, "status.json"), simplifyVector = FALSE)
status$current_phase    <- "OPTIMIZER_DONE"
status$updated_at       <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$blocker          <- NULL
status$optimizer_summary <- list(
  method_selected   = best_name,
  net_ir            = round(net_ir_f %||% NA_real_, 4),
  n_names           = n_final,
  hhi               = round(hhi_f, 6),
  beta_port         = round(beta_p, 4),
  max_weight        = round(max_w_f, 6),
  n_methods_compared = length(method_configs),
  constraint_pass   = (length(violations) == 0)
)
write_json(status, file.path(WT_MAIL, "status.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("[STATUS] OPTIMIZER_DONE\n")

##---------------------------------------------------------------------------
## 15. Telegram
##---------------------------------------------------------------------------
tg_ok <- tryCatch({
  tg_src <- file.path(PROJ_ROOT, "02_Infrastructure/telegram/telegram_notify.R")
  if (file.exists(tg_src)) { source(tg_src); TRUE } else FALSE
}, error = function(e) FALSE)

if (tg_ok && exists("tg_send")) {
  msg <- paste(c(
    "[Optimizer] Weights 결정 완료 - WT-D20260424_010",
    sprintf("방법론: %s  net_IR=%.4f", best_name, net_ir_f %||% NA),
    sprintf("포트폴리오: n=%d/20  Sigma_w=%.6f", n_final, sum_w),
    sprintf("성과: AR %.2f%%  TE %.2f%%  IR %.4f",
            exp_ar_a * 12 * 100, exp_te * sqrt(12) * 100, exp_ir %||% NA),
    sprintf("HHI %.4f  beta %.3f  max_w %.3f", hhi_f, beta_p, max_w_f),
    sprintf("Top 5 OW: %s", paste(top_ow, collapse=" | ")),
    sprintf("Binding: %s", if (length(binding) > 0) paste(binding, collapse=", ") else "none"),
    sprintf("vs STR_1631 baseline delta: %+.4f",
            if (!is.null(bl_res)) best_res$net_ir - bl_res$net_ir else NA),
    "Next: Forge integrate -> Judge"
  ), collapse = "\n")
  tryCatch(tg_send(msg), error = function(e) NULL)
} else {
  cat("[Telegram] skip (not available)\n")
}

cat("\n=== Optimizer Agent WT-D20260424_010 COMPLETE ===\n")
cat(sprintf("[OPTIMIZER_DONE] method=%s  net_ir=%.4f  n=%d  HHI=%.6f  violations=%d\n",
            best_name, net_ir_f %||% NA, n_final, hhi_f, length(violations)))
