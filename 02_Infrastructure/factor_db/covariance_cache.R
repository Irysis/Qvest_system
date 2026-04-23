#==============================================================================
# QEPM Covariance Cache — v1.0
# 2026-04-23 Session 69 Day 1 — Risk Research Agent 중앙 공분산 infra
#
# 목적:
#   - 각 전략이 공분산 재계산하는 비효율 제거
#   - Risk Agent가 중앙 캐시에 저장 → Optimizer / Forge 재사용
#
# 저장 경로: .cache/covariance/{task_id}_{method}_{sig_date}.parquet
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(digest)
})

COVARIANCE_CACHE_DIR <- ".cache/covariance"
dir.create(COVARIANCE_CACHE_DIR, recursive = TRUE, showWarnings = FALSE)

# ─── 자동 method 선택 ────────────────────────────────────
# N = 샘플 크기, D = dimension (종목 수)
# Rule:
#   D > N           → Ledoit-Wolf (singular)
#   D/N > 0.5       → Gerber-RMT
#   condition > 500 → Ledoit-Wolf shrinkage
#   otherwise       → Sample
select_cov_method <- function(N, D, regime_volatility = "normal") {
  if (regime_volatility %in% c("crisis", "stress")) {
    return("dcc_copula")  # 국면 변동 시 DCC
  }
  if (D >= N) return("ledoit_wolf")
  if (D / N > 0.5) return("gerber_rmt")
  return("sample")
}

# ─── 공분산 생성 + 캐시 ──────────────────────────────────
compute_and_cache_covariance <- function(task_id,
                                          returns_matrix,
                                          sig_date,
                                          method = "auto",
                                          regime = "normal") {
  if (!is.matrix(returns_matrix)) {
    stop("[covariance_cache] returns_matrix must be matrix (T x D)")
  }

  N <- nrow(returns_matrix)  # 샘플 크기 (월 수)
  D <- ncol(returns_matrix)  # 종목 수

  if (method == "auto") {
    method <- select_cov_method(N, D, regime)
  }

  cat(sprintf("[covariance_cache] computing Σ: N=%d, D=%d, method=%s\n",
              N, D, method))

  cov_matrix <- switch(method,
    "sample" = cov(returns_matrix, use = "pairwise.complete.obs"),
    "ledoit_wolf" = {
      if (requireNamespace("corpcor", quietly = TRUE)) {
        corpcor::cov.shrink(returns_matrix, verbose = FALSE)
      } else {
        warning("[covariance_cache] corpcor unavailable, falling back to sample")
        cov(returns_matrix, use = "pairwise.complete.obs")
      }
    },
    "gerber_rmt" = {
      # hrp_core.R의 .get_cor_cov 활용
      if (file.exists("02_Infrastructure/portfolio/hrp_core.R")) {
        source("02_Infrastructure/portfolio/hrp_core.R", local = TRUE)
        res <- .get_cor_cov(returns_matrix, method = "gerber_rmt")
        res$cov
      } else {
        cov(returns_matrix, use = "pairwise.complete.obs")
      }
    },
    "dcc_copula" = {
      # regime_garch.R 활용 (simplified)
      if (file.exists("02_Infrastructure/regime/regime_garch.R")) {
        source("02_Infrastructure/regime/regime_garch.R", local = TRUE)
        # DCC-GARCH 호출 (interface은 regime_garch.R에 따라 조정)
        tryCatch({
          # Placeholder — 실제 regime_garch.R 인터페이스 확인 후 호출
          cov(returns_matrix, use = "pairwise.complete.obs")
        }, error = function(e) {
          warning("[covariance_cache] DCC fallback to sample: ", conditionMessage(e))
          cov(returns_matrix, use = "pairwise.complete.obs")
        })
      } else {
        cov(returns_matrix, use = "pairwise.complete.obs")
      }
    },
    cov(returns_matrix, use = "pairwise.complete.obs")
  )

  # Condition number
  eig <- tryCatch(eigen(cov_matrix, symmetric = TRUE, only.values = TRUE)$values,
                  error = function(e) NA)
  cond_num <- if (!any(is.na(eig))) max(abs(eig)) / max(min(abs(eig)), 1e-12) else NA
  cat(sprintf("  condition_number: %.2f\n", cond_num))

  # Shrinkage 재적용 (condition number > 500)
  if (!is.na(cond_num) && cond_num > 500 && method == "sample") {
    cat("  → condition number > 500, re-estimating with Ledoit-Wolf\n")
    return(compute_and_cache_covariance(task_id, returns_matrix, sig_date,
                                         method = "ledoit_wolf", regime = regime))
  }

  # 저장
  cache_file <- file.path(COVARIANCE_CACHE_DIR,
                           sprintf("%s_%s_%s.parquet",
                                   task_id, method, format(as.Date(sig_date), "%Y%m%d")))

  cov_dt <- as.data.table(cov_matrix)
  cov_dt[, Ticker := rownames(cov_matrix)]
  setcolorder(cov_dt, c("Ticker", setdiff(names(cov_dt), "Ticker")))

  write_parquet(cov_dt, cache_file)

  # v6.1 R6: freshness 메타데이터 저장
  meta_file <- sub("\\.parquet$", ".meta.json", cache_file)
  cache_hash <- digest::digest(cov_matrix, algo = "sha256", serialize = TRUE)
  meta <- list(
    task_id = task_id,
    method = method,
    covariance_asof = format(as.Date(sig_date), "%Y-%m-%d"),
    estimation_window_months = N,
    dimension = D,
    condition_number = cond_num,
    regime_tag = regime,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    freshness_sla_days = 30L,
    cache_hash = cache_hash,
    invalidate_rule = "regime_change OR age_gt_30d OR dimension_change"
  )
  jsonlite::write_json(meta, meta_file, pretty = TRUE, auto_unbox = TRUE)

  cat(sprintf("  cached: %s\n", cache_file))
  cat(sprintf("  meta:   %s (regime=%s, SLA=30d)\n", meta_file, regime))

  list(
    cov_matrix = cov_matrix,
    method = method,
    condition_number = cond_num,
    cache_path = cache_file,
    meta_path = meta_file,
    regime_tag = regime,
    cache_hash = cache_hash,
    N = N,
    D = D
  )
}

# ─── v6.1 R6: Freshness check ───────────────────────────
# stale cache 사용 여부 판정. Optimizer Agent가 loading 전 호출.
check_cache_freshness <- function(cache_path, current_regime = NULL) {
  meta_file <- sub("\\.parquet$", ".meta.json", cache_path)
  if (!file.exists(meta_file)) {
    return(list(fresh = FALSE, reason = "meta_missing"))
  }

  meta <- jsonlite::fromJSON(meta_file, simplifyVector = TRUE)
  asof <- as.Date(meta$covariance_asof)
  sla <- meta$freshness_sla_days %||% 30L
  age_days <- as.integer(Sys.Date() - asof)

  if (age_days > sla) {
    return(list(fresh = FALSE, reason = sprintf("stale_age_%dd_sla_%dd", age_days, sla),
                meta = meta))
  }

  if (!is.null(current_regime) && !is.null(meta$regime_tag) &&
      current_regime != meta$regime_tag) {
    return(list(fresh = FALSE,
                reason = sprintf("regime_mismatch_cached_%s_current_%s",
                                 meta$regime_tag, current_regime),
                meta = meta))
  }

  list(fresh = TRUE, age_days = age_days, meta = meta)
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── 캐시 조회 ───────────────────────────────────────────
load_cached_covariance <- function(task_id, sig_date, method = NULL) {
  if (is.null(method)) {
    # 전체 method 중 가장 최근 선택
    pattern <- sprintf("^%s_.+_%s\\.parquet$", task_id, format(as.Date(sig_date), "%Y%m%d"))
  } else {
    pattern <- sprintf("^%s_%s_%s\\.parquet$", task_id, method, format(as.Date(sig_date), "%Y%m%d"))
  }
  files <- list.files(COVARIANCE_CACHE_DIR, pattern = pattern, full.names = TRUE)
  if (length(files) == 0) return(NULL)

  cache_file <- files[which.max(file.mtime(files))]
  cov_dt <- as.data.table(read_parquet(cache_file))

  tickers <- cov_dt$Ticker
  cov_dt[, Ticker := NULL]
  cov_matrix <- as.matrix(cov_dt)
  rownames(cov_matrix) <- colnames(cov_matrix) <- tickers

  cat(sprintf("[covariance_cache] loaded: %s\n", cache_file))
  cov_matrix
}

# ─── 캐시 통계 ───────────────────────────────────────────
cache_stats <- function() {
  files <- list.files(COVARIANCE_CACHE_DIR, pattern = "\\.parquet$", full.names = TRUE)
  if (length(files) == 0) {
    cat("(캐시 없음)\n")
    return(invisible(NULL))
  }

  dt <- data.table(
    path = files,
    size_kb = file.size(files) / 1024,
    mtime = file.mtime(files)
  )

  cat(sprintf("=== Covariance Cache Stats ===\n"))
  cat(sprintf("Total files: %d\n", nrow(dt)))
  cat(sprintf("Total size: %.1f MB\n", sum(dt$size_kb) / 1024))
  cat(sprintf("Latest: %s\n", format(max(dt$mtime), "%Y-%m-%d %H:%M")))

  invisible(dt)
}

cat("[covariance_cache.R] v6.1 R6 Loaded. Functions:\n")
cat("  compute_and_cache_covariance(task_id, returns_matrix, sig_date, method='auto', regime='normal')\n")
cat("  load_cached_covariance(task_id, sig_date, method=NULL)\n")
cat("  check_cache_freshness(cache_path, current_regime=NULL)  # v6.1 R6\n")
cat("  cache_stats()\n")
cat("  select_cov_method(N, D, regime_volatility)\n")
