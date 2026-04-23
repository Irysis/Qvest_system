#==============================================================================
# KTRI v3 Signal Builder (재구축 v1.0 — 2026-04-24)
#
# Purpose: KTRI v3 signal (KTRI_Score + VEA_Score) 재구축.
#   원본 KTRI_v3_reinforced.R 소실 (git 이력 없음) → minimal 대체.
#
# Input:
#   .cache/ktri_indices.parquet (ktri_index_collector.R 산출)
#     cols: Date, IKS200, IKS001~004, IKQ001~004, IKQ150, IKS221(VKOSPI)
#
# Output:
#   04_Research/regime_comparison/output/ktri_v3_signals.csv
#     cols: DATE, KTRI, VEA
#
# Formula (minimal viable):
#   KTRI  = market trend strength (KOSPI200 vs 252d MA, z-score → 0~100 scale)
#   VEA   = volatility/exposure composite (VKOSPI z-score + KOSDAQ relative)
#
# Note: 원본 공식과 정확히 일치 보장 못함. 신호 형태 (0~100 score) 맞춤.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
}
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")

KTRI_INDEX_CACHE <- file.path(CACHE_DIR, "ktri_indices.parquet")
KTRI_V3_OUT_DIR <- file.path(PROJECT_ROOT, "04_Research/regime_comparison/output")
KTRI_V3_CSV <- file.path(KTRI_V3_OUT_DIR, "ktri_v3_signals.csv")

#─── score helpers ────────────────────────────────────────────
.z_to_score <- function(z) {
  # z-score → 0~100 score. z=0 → 50, z=+2 → ~85, z=-2 → ~15.
  pmax(0, pmin(100, 50 + 12.5 * z))
}

.rolling_z <- function(x, w = 252L) {
  # rolling z (w-day window). NA for first w-1.
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < w) next
    win <- x[(i - w + 1L):i]
    m <- mean(win, na.rm = TRUE)
    s <- sd(win, na.rm = TRUE)
    out[i] <- if (is.finite(s) && s > 0) (x[i] - m) / s else 0
  }
  out
}

#─── build KTRI v3 ────────────────────────────────────────────
# Source priority:
#   1. .cache/ktri_indices.parquet (ktri_index_collector, IKS200 + VKOSPI 등)
#   2. .cache/benchmark.parquet (BM_Close, 1990-2026 장기 fallback)
build_ktri_v3 <- function(output = KTRI_V3_CSV, window = 252L) {
  idx <- NULL
  use_bench <- FALSE

  if (file.exists(KTRI_INDEX_CACHE)) {
    cand <- as.data.table(read_parquet(KTRI_INDEX_CACHE))
    if (nrow(cand) >= window && "IKS200" %in% names(cand)) {
      idx <- cand
      cat("[ktri_v3] using ktri_indices.parquet\n")
    } else {
      cat(sprintf("[ktri_v3] ktri_indices too short (%d rows < %d) — fallback to benchmark\n",
                  nrow(cand), window))
    }
  }

  if (is.null(idx)) {
    bench_path <- file.path(CACHE_DIR, "benchmark.parquet")
    if (!file.exists(bench_path)) {
      stop("[ktri_v3] no KTRI source: ktri_indices & benchmark both missing")
    }
    bench <- as.data.table(read_parquet(bench_path))
    if (!"BM_Close" %in% names(bench)) {
      stop("[ktri_v3] benchmark.parquet missing BM_Close")
    }
    idx <- data.table(Date = as.Date(bench$Date), IKS200 = bench$BM_Close)
    use_bench <- TRUE
    cat(sprintf("[ktri_v3] fallback benchmark.parquet (%d rows, %s ~ %s)\n",
                nrow(idx), min(idx$Date), max(idx$Date)))
  }

  setorder(idx, Date)
  idx[, Date := as.Date(Date)]

  if (!"IKS200" %in% names(idx)) {
    stop("[ktri_v3] missing IKS200 after source selection")
  }

  # KTRI: KOSPI200 trend strength
  # z = (price - MA252) / SD252 → score
  idx[, IKS200_z := .rolling_z(IKS200, w = window)]
  idx[, KTRI := .z_to_score(IKS200_z)]

  # VEA: volatility exposure
  # 1) VKOSPI (IKS221) z-score (higher z = more vol)
  # 2) KOSDAQ relative weakness (IKQ150 log return z)
  has_vkospi <- !use_bench && "IKS221" %in% names(idx)
  has_kosdaq <- !use_bench && "IKQ150" %in% names(idx)

  if (has_vkospi) {
    idx[, VKOSPI_z := .rolling_z(IKS221, w = window)]
    idx[, VEA_vol := .z_to_score(VKOSPI_z)]
  } else {
    idx[, VEA_vol := 50]
  }

  if (has_kosdaq) {
    idx[, IKQ150_z := .rolling_z(IKQ150, w = window)]
    idx[, VEA_kq := .z_to_score(-IKQ150_z)] # 약세 = 높은 점수
  } else {
    idx[, VEA_kq := 50]
  }

  idx[, VEA := 0.7 * VEA_vol + 0.3 * VEA_kq]

  # Clamp
  idx[, KTRI := pmax(0, pmin(100, KTRI))]
  idx[, VEA := pmax(0, pmin(100, VEA))]

  # tg_regime_briefing가 기대하는 IKS200 컬럼 포함 (fwd20 계산용)
  out <- idx[!is.na(KTRI), .(DATE = Date, KTRI, VEA, IKS200)]

  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  fwrite(out, output)

  cat(sprintf("[ktri_v3] built: %d rows | %s ~ %s\n",
              nrow(out), min(out$DATE), max(out$DATE)))
  cat(sprintf("[ktri_v3] saved: %s\n", output))

  invisible(out)
}

# Convenience: ensure indices exist then build
build_ktri_v3_safe <- function() {
  if (!file.exists(KTRI_INDEX_CACHE)) {
    cat("[ktri_v3] ktri_indices not found — running ktri_collect_indices first\n")
    idx_src <- file.path(PROJECT_ROOT, "02_Infrastructure/data/ktri_index_collector.R")
    if (file.exists(idx_src)) {
      source(idx_src, local = TRUE)
      tryCatch(ktri_collect_indices(),
               error = function(e) cat(sprintf("[ktri_v3] collect failed: %s\n", e$message)))
    }
  }
  tryCatch(build_ktri_v3(),
           error = function(e) {
             cat(sprintf("[ktri_v3] build failed: %s\n", e$message))
             invisible(NULL)
           })
}

cat("[ktri_v3_builder.R] Loaded. Functions:\n")
cat("  build_ktri_v3(output, window=252)\n")
cat("  build_ktri_v3_safe()  # ensure indices + build\n")
