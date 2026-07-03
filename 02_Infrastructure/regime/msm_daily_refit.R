#==============================================================================
# MSM Daily Refit — v1.0 (2026-04-24, Step 3 of regime infra 재구축)
#
# Purpose: benchmark.parquet 일간 log return → 2-state HMM fit → daily Crisis_Prob
#   기존 compute_hmm_signal()은 월간만. 일간 MSM 별도 builder.
#
# Output: .cache/msm_daily_latest.parquet
#   cols: Date, Price, Vol_Est, Crisis_Prob
#
# Logic:
#   1. benchmark.parquet 로드 → daily log return
#   2. Expanding window HMM fit (min 252 days warmup)
#   3. Vol_Est = rolling 20d sd
#   4. Crisis_Prob = smoother γ[, stress state]
#
# Warm start: 이전 fit의 mu/sigma 전달하여 EM iteration 빠름
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

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
  stop("[msm_daily_refit] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- .qvest_root()
}
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")

MSM_DAILY_CACHE <- file.path(CACHE_DIR, "msm_daily_latest.parquet")

# regime_hmm.R의 .hmm_em() 재사용
source_hmm_em <- function() {
  hmm_path <- file.path(PROJECT_ROOT, "02_Infrastructure/regime/regime_hmm.R")
  if (!file.exists(hmm_path)) stop("regime_hmm.R not found")
  # Load only the function (avoid compute_hmm_signal auto-run)
  env <- new.env()
  source(hmm_path, local = env)
  env$.hmm_em
}

#─── Daily HMM refit ──────────────────────────────────────────
compute_hmm_daily_signal <- function(min_warmup = 252L,
                                      refit_freq_days = 30L) {
  cat("[msm_daily_refit] Loading benchmark.parquet...\n")
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  setorder(bm, Date)
  bm <- bm[!is.na(BM_Close)]

  # Daily log return
  bm[, log_ret := log(BM_Close / shift(BM_Close, 1L))]
  bm[, Vol_Est := frollapply(log_ret, 20L, sd, align = "right")]

  returns_all <- bm$log_ret
  dates_all <- bm$Date

  n <- length(returns_all)
  if (n < min_warmup + 1) {
    stop(sprintf("[msm_daily_refit] Not enough data (need %d, have %d)",
                 min_warmup + 1, n))
  }

  cat(sprintf("[msm_daily_refit] %d trading days (%s ~ %s), warmup=%d, refit every %d days\n",
              n, min(bm$Date), max(bm$Date), min_warmup, refit_freq_days))

  hmm_em <- source_hmm_em()

  # Output 초기화
  crisis_prob <- rep(NA_real_, n)
  hmm_state <- rep(NA_integer_, n)

  # Warm start params
  last_mu <- c(0.0005, -0.002)        # normal / stress log daily
  last_sigma <- c(0.010, 0.025)       # ~vol 1% / 2.5%

  # Refit schedule: 매 refit_freq_days마다 fit, 그 사이는 smoother forward apply
  refit_idx <- seq(min_warmup + 1, n, by = refit_freq_days)
  if (tail(refit_idx, 1) != n) refit_idx <- c(refit_idx, n)

  cat(sprintf("[msm_daily_refit] %d refit points (expanding window)\n",
              length(refit_idx)))

  for (i in seq_along(refit_idx)) {
    end_i <- refit_idx[i]
    if (end_i > n) end_i <- n

    window_rets <- returns_all[1:end_i]
    window_rets <- window_rets[!is.na(window_rets)]
    if (length(window_rets) < min_warmup) next

    fit <- tryCatch(
      hmm_em(window_rets, max_iter = 50L, tol = 1e-5,
             mu_init = last_mu, sigma_init = last_sigma),
      error = function(e) NULL
    )

    if (is.null(fit)) next

    # stress state = higher vol state
    stress_state <- if (fit$sigma[2] > fit$sigma[1]) 2L else 1L

    # γ[, stress_state] at recent positions
    n_fit <- length(window_rets)
    gamma_stress <- fit$gamma[, stress_state]

    # Assign to crisis_prob at matching positions
    # 안전하게 end_i position에만 assign. 이전 refit window는 그 때 계산됨.
    # Alternative: full backfill
    prev_end <- if (i == 1) 0 else refit_idx[i-1]
    fill_from <- max(prev_end + 1, 1)
    fill_to <- end_i

    # returns_all NA 제거 후 매핑
    valid_idx <- which(!is.na(returns_all[1:end_i]))
    if (length(valid_idx) == length(gamma_stress)) {
      crisis_prob[valid_idx] <- gamma_stress
      hmm_state[valid_idx] <- apply(fit$gamma, 1, which.max)
    }

    # Warm-start 업데이트
    last_mu <- fit$mu
    last_sigma <- fit$sigma

    if (i %% 10 == 0 || i == length(refit_idx)) {
      cat(sprintf("  refit %d/%d (%s): mu=[%.4f, %.4f], sigma=[%.4f, %.4f], p_stress_latest=%.3f\n",
                  i, length(refit_idx), as.character(dates_all[end_i]),
                  fit$mu[1], fit$mu[2], fit$sigma[1], fit$sigma[2],
                  tail(gamma_stress, 1)))
    }
  }

  # 결과 df
  out <- data.table(
    Date = dates_all,
    Price = bm$BM_Close,
    Vol_Est = bm$Vol_Est,
    Crisis_Prob = crisis_prob,
    HMM_State = hmm_state
  )

  # warmup 앞부분 drop
  out <- out[!is.na(Crisis_Prob)]

  # 저장
  write_parquet(out, MSM_DAILY_CACHE)
  cat(sprintf("[msm_daily_refit] saved %d rows | %s ~ %s\n",
              nrow(out), min(out$Date), max(out$Date)))
  cat(sprintf("[msm_daily_refit] latest Crisis_Prob: %.3f (%s)\n",
              out[.N, Crisis_Prob], out[.N, Date]))

  invisible(out)
}

refit_msm_daily <- function() {
  tryCatch(compute_hmm_daily_signal(),
           error = function(e) {
             cat(sprintf("[msm_daily_refit] ERR: %s\n", e$message))
             invisible(NULL)
           })
}

cat("[msm_daily_refit.R] Loaded. Functions:\n")
cat("  compute_hmm_daily_signal(min_warmup=252, refit_freq_days=30)\n")
cat("  refit_msm_daily()  # safe wrapper\n")
