#!/usr/bin/env Rscript
#==============================================================================
# validate_rcpp_speedup.R — Rcpp 정합성 + 속도 검증
#
# 목적:
#   1. fast_rolling.cpp 컴파일 확인
#   2. 기존 factor_db_daily_20050103.parquet vs Rcpp 재빌드 비교
#      → 팩터별 Pearson 상관계수 >= 0.9999 확인
#   3. 1날짜 빌드 시간 측정 (목표: 5초 이하)
#   4. 롤링 함수 단위 테스트 (rolling_mean/sd/beta/idiovol)
#
# 실행:
#   cd "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
#   Rscript -e 'source("04_Research/validate_rcpp_speedup.R")'
#==============================================================================

cat("=== Rcpp Speedup Validation ===\n")
cat("Started:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ── 0. 환경 설정 ─────────────────────────────────────────────────────────────
.self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot/04_Research"
  }
)
proj_root <- dirname(.self_dir)
infra_dir <- file.path(proj_root, "02_Infrastructure")

source(file.path(infra_dir, "config.R"))
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ── 1. Rcpp 컴파일 테스트 ─────────────────────────────────────────────────────
cat("── 1. Rcpp 컴파일 ──────────────────────────────────────────────────────\n")
rcpp_helpers_path <- file.path(infra_dir, "factor_db", "rcpp_helpers.R")
if (!file.exists(rcpp_helpers_path)) {
  stop("rcpp_helpers.R 없음: ", rcpp_helpers_path)
}
source(rcpp_helpers_path)

if (isTRUE(.rcpp_env$.use_rcpp)) {
  cat("[PASS] Rcpp 컴파일 성공\n\n")
} else {
  cat("[WARN] Rcpp 미적재 — R fallback 사용 (결과는 동일, 속도만 차이)\n\n")
}

# ── 2. 롤링 함수 단위 테스트 ──────────────────────────────────────────────────
cat("── 2. 롤링 함수 단위 테스트 ────────────────────────────────────────────\n")
set.seed(42)
N   <- 500
x   <- c(rnorm(N - 20), rep(NA_real_, 20))  # NA 포함
y   <- rnorm(N)
w   <- 60L

# 참조: 순수 R 구현
ref_mean <- function(x, w) {
  out <- rep(NA_real_, length(x))
  for (i in w:length(x)) out[i] <- mean(x[(i-w+1):i], na.rm = TRUE)
  out
}
ref_sd <- function(x, w) {
  out <- rep(NA_real_, length(x))
  for (i in w:length(x)) out[i] <- sd(x[(i-w+1):i], na.rm = TRUE)
  out
}
ref_beta <- function(s, m, w) {
  out <- rep(NA_real_, length(s))
  for (i in w:length(s)) {
    sv <- s[(i-w+1):i]; mv <- m[(i-w+1):i]
    ok <- !is.na(sv) & !is.na(mv)
    if (sum(ok) < 5) next
    vm <- var(mv[ok]); if (is.na(vm) || vm < 1e-14) next
    out[i] <- cov(sv[ok], mv[ok]) / vm
  }
  out
}

# 테스트 함수
.check <- function(name, got, ref, tol = 1e-6) {
  # 비교 가능한 위치만
  ok <- !is.na(got) & !is.na(ref)
  if (sum(ok) < 10) {
    cat(sprintf("  [SKIP] %s: 비교 가능 위치 부족 (%d)\n", name, sum(ok)))
    return(invisible(FALSE))
  }
  max_diff <- max(abs(got[ok] - ref[ok]))
  cor_val  <- cor(got[ok], ref[ok])
  if (max_diff < tol && cor_val > 0.9999) {
    cat(sprintf("  [PASS] %-20s max_diff=%.2e  cor=%.7f\n", name, max_diff, cor_val))
    return(invisible(TRUE))
  } else {
    cat(sprintf("  [FAIL] %-20s max_diff=%.2e  cor=%.7f\n", name, max_diff, cor_val))
    return(invisible(FALSE))
  }
}

.check("rolling_mean", .roll_mean(x, w), ref_mean(x, w))
.check("rolling_sd",   .roll_sd(x, w),   ref_sd(x, w))
.check("rolling_beta", .roll_beta(x, y, w), ref_beta(x, y, w), tol = 1e-5)

# rank_pct 검증: 동점 처리
rx <- c(1, 2, 2, 3, NA)
rp <- .rank_pct(rx)
expected <- c(0, 0.5, 0.5, 1, NA)
rp_ok <- all(is.na(rp) == is.na(expected)) &&
         max(abs(rp[!is.na(rp)] - expected[!is.na(expected)])) < 1e-10
cat(sprintf("  [%s] %-20s values=%s\n",
            if (rp_ok) "PASS" else "FAIL",
            "rank_pct",
            paste(round(rp, 3), collapse=",")))

# rolling_idiovol: 양수 확인
iv <- .roll_idiovol(x, y, w)
iv_ok <- all(is.na(iv) | iv >= 0)
cat(sprintf("  [%s] %-20s all_non_negative=%s\n",
            if (iv_ok) "PASS" else "FAIL",
            "rolling_idiovol", iv_ok))
cat("\n")

# ── 3. 속도 비교: .roll_mean / .roll_sd vs R base ─────────────────────────────
cat("── 3. 속도 비교 (N=2000, window=252, 1000종목 시뮬) ────────────────────\n")
N2 <- 2000L
x2 <- rnorm(N2)

t_rcpp <- system.time(replicate(1000, .roll_mean(x2, 252L)))["elapsed"]
t_r    <- system.time(replicate(1000, ref_mean(x2, 252L)))["elapsed"]
speedup <- if (t_rcpp > 0) round(t_r / t_rcpp, 1) else Inf
cat(sprintf("  rolling_mean: Rcpp=%.3fs  R=%.3fs  speedup=%.1fx\n",
            t_rcpp, t_r, speedup))

t_rcpp_sd <- system.time(replicate(1000, .roll_sd(x2, 252L)))["elapsed"]
t_r_sd    <- system.time(replicate(1000, ref_sd(x2, 252L)))["elapsed"]
speedup_sd <- if (t_rcpp_sd > 0) round(t_r_sd / t_rcpp_sd, 1) else Inf
cat(sprintf("  rolling_sd:   Rcpp=%.3fs  R=%.3fs  speedup=%.1fx\n",
            t_rcpp_sd, t_r_sd, speedup_sd))
cat("\n")

# ── 4. 기존 parquet vs 재빌드 정합성 검증 ────────────────────────────────────
cat("── 4. 기존 parquet 정합성 검증 ──────────────────────────────────────────\n")
daily_dir <- file.path(CACHE_DIR, "factor_db_daily")
ref_file  <- file.path(daily_dir, "factor_db_daily_20050103.parquet")

if (!file.exists(ref_file)) {
  cat("  [SKIP] 기존 parquet 없음:", ref_file, "\n\n")
} else {
  ref_dt <- as.data.table(read_parquet(ref_file))
  cat(sprintf("  기존 parquet: %d rows, %d factors, %d tickers\n",
              nrow(ref_dt), uniqueN(ref_dt$Factor_Name), uniqueN(ref_dt$Ticker)))

  # Factor DB builder 로드
  source(file.path(infra_dir, "factor_db_builder.R"))

  cat("  재빌드 시작 (force=TRUE)...\n")
  t_rebuild <- system.time({
    new_dt <- tryCatch(
      build_factor_db("2005-01-03", save = FALSE, force = TRUE),
      error = function(e) { cat("  [ERROR]", conditionMessage(e), "\n"); NULL }
    )
  })["elapsed"]

  cat(sprintf("  재빌드 소요: %.1f초 (목표: ≤5초)\n", t_rebuild))
  if (t_rebuild <= 5) cat("  [PASS] 속도 목표 달성\n")
  else cat(sprintf("  [INFO] 속도 %.1f초 — 추가 최적화 여지\n", t_rebuild))

  if (!is.null(new_dt) && nrow(new_dt) > 0) {
    # 팩터별 상관계수 비교
    # 두 dt 모두 Date, Ticker, Factor_Name, Z_Score_Aligned 또는 Z_Score
    val_col <- if ("Z_Score_Aligned" %in% names(ref_dt)) "Z_Score_Aligned" else "Z_Score"
    if (!(val_col %in% names(ref_dt))) val_col <- "Raw_Value"

    ref_wide <- dcast(ref_dt[Coverage == TRUE],
                      Ticker ~ Factor_Name, value.var = val_col)
    new_wide <- dcast(new_dt[Coverage == TRUE],
                      Ticker ~ Factor_Name, value.var = val_col)

    common_factors <- intersect(names(ref_wide)[-1], names(new_wide)[-1])
    common_tickers <- intersect(ref_wide$Ticker, new_wide$Ticker)

    cat(sprintf("  공통 팩터 %d개, 공통 종목 %d개\n",
                length(common_factors), length(common_tickers)))

    if (length(common_factors) > 0 && length(common_tickers) > 10) {
      ref_sub <- ref_wide[Ticker %in% common_tickers, c("Ticker", common_factors), with=FALSE]
      new_sub <- new_wide[Ticker %in% common_tickers, c("Ticker", common_factors), with=FALSE]
      setkey(ref_sub, Ticker); setkey(new_sub, Ticker)

      cor_results <- sapply(common_factors, function(f) {
        rv <- ref_sub[[f]]; nv <- new_sub[[f]]
        ok <- !is.na(rv) & !is.na(nv)
        if (sum(ok) < 5) return(NA_real_)
        cor(rv[ok], nv[ok])
      })
      cor_results <- cor_results[!is.na(cor_results)]

      n_pass <- sum(cor_results >= 0.9999, na.rm = TRUE)
      n_warn <- sum(cor_results >= 0.999 & cor_results < 0.9999, na.rm = TRUE)
      n_fail <- sum(cor_results < 0.999, na.rm = TRUE)
      min_cor <- min(cor_results, na.rm = TRUE)
      median_cor <- median(cor_results, na.rm = TRUE)

      cat(sprintf("  상관계수 요약: median=%.6f, min=%.6f\n", median_cor, min_cor))
      cat(sprintf("  >=0.9999: %d팩터 [PASS]  >=0.999: %d팩터 [WARN]  <0.999: %d팩터 [FAIL]\n",
                  n_pass, n_warn, n_fail))

      if (n_fail > 0) {
        fail_names <- names(cor_results)[cor_results < 0.999]
        cat("  FAIL 팩터:", paste(head(fail_names, 10), collapse=", "), "\n")
      }

      if (n_pass == length(cor_results)) {
        cat("  [PASS] 전체 팩터 정합성 확인\n")
      } else {
        cat("  [WARN] 일부 팩터 수치 차이 발생 — 확인 필요\n")
      }
    }
  }
  cat("\n")
}

# ── 5. 병렬화 설정 확인 ───────────────────────────────────────────────────────
cat("── 5. 병렬화 환경 확인 ──────────────────────────────────────────────────\n")
n_cores <- tryCatch(parallel::detectCores(logical = FALSE), error = function(e) NA)
cat(sprintf("  물리 코어: %s\n", n_cores))
cat(sprintf("  OS 타입: %s\n", .Platform$OS.type))
can_fork <- .Platform$OS.type == "unix"
cat(sprintf("  fork 사용 가능: %s\n", can_fork))
if (can_fork) {
  workers_plan <- max(1L, min(20L, n_cores - 2L))
  cat(sprintf("  예상 workers: %d (30코어 환경 → workers=20)\n", workers_plan))
  cat("  예상 병렬 속도: 43초/날짜 / 20worker ~= 2초/날짜\n")
  cat(sprintf("  5245날짜 예상 소요: %.1f시간\n",
              5245 * 43 / 20 / 3600))
} else {
  cat("  WSL2 환경: fork 비활성 — workers=1 (직렬) 강등 적용됨\n")
  cat("  병렬화 대안: future.apply + multisession (소켓 기반)\n")
}
cat("\n")

cat("=== Validation Complete:", format(Sys.time(), "%H:%M:%S"), "===\n")
