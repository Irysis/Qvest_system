# =============================================================================
# regime_display_diag.R — task #49 item 2 (2026-07-13)
# 엔진 CRISIS vs gap_vector NEUTRAL 표시 불일치 — ⓑ MSM 입력 sanity 진단.
# READ-ONLY. 신규 산출물: regime_msm_recent.csv
# =============================================================================

Sys.setenv(R_DATATABLE_NUM_THREADS = "1", OMP_NUM_THREADS = "1",
           OPENBLAS_NUM_THREADS = "1")
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})
try(arrow::set_io_thread_count(2), silent = TRUE)

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts/live_hygiene_20260713")

P_DAILY <- file.path(ROOT, ".cache/unified_regime_signal_daily.parquet")
P_MSM   <- file.path(ROOT, ".cache/msm_daily_latest.parquet")
P_BM    <- file.path(ROOT, ".cache/benchmark.parquet")

# ── [1] unified daily 최근 rows ──
cat("=== [1] unified_regime_signal_daily 최근 30행 ===\n")
ud <- as.data.table(read_parquet(P_DAILY))
ud[, Date := as.Date(Date)]
setorder(ud, Date)
print(tail(ud[, .(Date, Regime_Score, Regime_Score_smooth, Category, Cash_Pct,
                  MSM_Crisis_Prob)], 30))
# trailing 연속 MSM>=0.9 일수
msm_v <- ud$MSM_Crisis_Prob
n <- length(msm_v); k <- 0L
while (k < n && !is.na(msm_v[n - k]) && msm_v[n - k] >= 0.9) k <- k + 1L
cat(sprintf("\n  trailing 연속 MSM_Crisis_Prob >= 0.9 : %d 거래일 (최종 %s)\n",
            k, format(max(ud$Date))))
cat(sprintf("  최종행: Score=%.2f Category=%s Cash_Pct=%.3f MSM=%.4f\n",
            ud[.N, Regime_Score], ud[.N, Category], ud[.N, Cash_Pct],
            ud[.N, MSM_Crisis_Prob]))
# 역사 baseline: MSM>=0.9 에피소드 빈도
ud[, msm_hi := !is.na(MSM_Crisis_Prob) & MSM_Crisis_Prob >= 0.9]
r <- rle(ud$msm_hi)
ep <- data.table(len = r$lengths, hi = r$values)[hi == TRUE]
cat(sprintf("  역사 MSM>=0.9 에피소드: %d회 | 길이 median=%.0f p90=%.0f max=%d\n",
            nrow(ep), median(ep$len), quantile(ep$len, 0.9), max(ep$len)))

# ── [2] msm_daily_latest 원천 sanity ──
cat("\n=== [2] msm_daily_latest.parquet 최근 30행 ===\n")
ms <- as.data.table(read_parquet(P_MSM))
ms[, Date := as.Date(Date)]
setorder(ms, Date)
print(tail(ms, 30))
cat(sprintf("  범위: %s ~ %s | NA(Crisis_Prob)=%d | dup(Date)=%d\n",
            format(min(ms$Date)), format(max(ms$Date)),
            sum(is.na(ms$Crisis_Prob)), sum(duplicated(ms$Date))))
gaps <- as.integer(diff(tail(ms$Date, 65)))
cat(sprintf("  최근 65행 date-gap max = %d일\n", max(gaps)))

# ── [3] benchmark.parquet (MSM 입력) 최근 60거래일 sanity ──
cat("\n=== [3] benchmark.parquet 최근 60거래일 log-ret sanity ===\n")
bm <- as.data.table(read_parquet(P_BM))
bm[, Date := as.Date(Date)]
setorder(bm, Date)
cat("  cols:", paste(names(bm), collapse = ", "), "\n")
pc <- intersect(c("Close", "close", "Price", "Index", "BM_Close"), names(bm))[1]
bm[, lr := log(get(pc) / shift(get(pc)))]
b60 <- tail(bm, 61)
cat(sprintf("  구간: %s ~ %s | NA=%d | dup=%d | max date-gap=%d일\n",
            format(min(b60$Date)), format(max(b60$Date)),
            sum(is.na(b60$lr[-1])), sum(duplicated(b60$Date)),
            max(as.integer(diff(b60$Date)))))
cat(sprintf("  log-ret: min=%+.4f max=%+.4f sd(60d,ann)=%.3f | n(|lr|>3%%)=%d n(|lr|>5%%)=%d\n",
            min(b60$lr, na.rm = TRUE), max(b60$lr, na.rm = TRUE),
            sd(b60$lr, na.rm = TRUE) * sqrt(252),
            sum(abs(b60$lr) > 0.03, na.rm = TRUE),
            sum(abs(b60$lr) > 0.05, na.rm = TRUE)))
# 최근 1년 대비 현재 vol 수준
b1y <- tail(bm, 253)
sd20_now  <- sd(tail(bm$lr, 20), na.rm = TRUE) * sqrt(252)
sd20_hist <- frollapply(b1y$lr, 20, sd)
cat(sprintf("  20d vol(ann): 현재=%.3f | 최근1y median=%.3f p90=%.3f\n",
            sd20_now, median(sd20_hist * sqrt(252), na.rm = TRUE),
            quantile(sd20_hist * sqrt(252), 0.9, na.rm = TRUE)))
cat("\n  최근 15거래일 벤치:\n")
print(tail(bm[, .(Date, price = get(pc), lr)], 15))

# ── [4] 저장 ──
sl <- merge(tail(ud[, .(Date, Regime_Score, Category, Cash_Pct, MSM_Crisis_Prob)], 65),
            tail(ms[, .(Date, msm_src_prob = Crisis_Prob, Vol_Est)], 65),
            by = "Date", all = TRUE)
sl <- merge(sl, tail(bm[, .(Date, bm_price = get(pc), bm_logret = lr)], 65),
            by = "Date", all = TRUE)
fwrite(sl, file.path(OUT, "regime_msm_recent.csv"))
cat("\n[save] regime_msm_recent.csv\n=== DONE ===\n")
