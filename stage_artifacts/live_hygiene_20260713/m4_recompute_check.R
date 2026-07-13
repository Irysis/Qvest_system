# =============================================================================
# m4_recompute_check.R — task #49 item 1 (2026-07-13)
# 2026-06 recon m4 = 1.0(rds) vs 0.8064(재생성) 판별용 PIT 재계산.
# READ-ONLY: recon rds / book_state / live_book_series / m4_extended.csv 무수정.
# 신규 산출물만 본 디렉토리에 기록:
#   - m4_recompute_vs_csv.csv       (엔진 재계산 vs 현행 CSV 전행 대조)
#   - m4_recompute_recent.csv       (2025-10 이후 근접행 디테일)
#   - m4_inputs_snapshot.csv        (monthly regime 2025-08~2026-07 슬라이스)
#   - m4_recon_delta.json           (정답 m4 / recon Δ / 시리즈 영향 진단)
# 규율: 단일스레드 + arrow io(2) + .R source 실행.
# =============================================================================

Sys.setenv(R_DATATABLE_NUM_THREADS = "1", OMP_NUM_THREADS = "1",
           OPENBLAS_NUM_THREADS = "1")
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
  library(PerformanceAnalytics)
})
try(arrow::set_io_thread_count(2), silent = TRUE)

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/live_hygiene_20260713")

P_M4CSV  <- file.path(ROOT, "stage_artifacts/WT-D20260430_001_m4_extended.csv")
P_REGMON <- file.path(ROOT, ".cache/unified_regime_signal.parquet")
P_PR     <- file.path(ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
P_RDS    <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
P_LIVE   <- file.path(ROOT, "06_Registry/live_track/STR_1715_on_M4_R05_noLayer4_PG2/live_book_series.csv")
P_ENGINE <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R")
P_ALPHA  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")

cat("=== [0] input vintages (mtime) ===\n")
for (p in c(P_M4CSV, P_REGMON, P_PR, P_RDS, P_LIVE, P_ALPHA)) {
  cat(sprintf("  %-55s %s\n", basename(p), format(file.mtime(p))))
}

# ── [1] monthly regime parquet 슬라이스 (Cash_Pct가 m4 Case-A의 유일 입력) ──
cat("\n=== [1] .cache/unified_regime_signal.parquet 2025-08 ~ 2026-07 ===\n")
reg <- as.data.table(read_parquet(P_REGMON))
reg[, Date := as.Date(Date)]
reg_slice <- reg[YM >= "2025-08",
                 .(Date, YM, Regime_Score, Category, Cash_Pct, MSM_Crisis_Prob)]
print(reg_slice)
fwrite(reg_slice, file.path(OUT, "m4_inputs_snapshot.csv"))

# ── [2] 07-02 07:31 vintage alpha_scores.parquet (엔진 산출 그대로) ──
cat("\n=== [2] WT-D20260430_001 alpha_scores.parquet (07-02 vintage) Date>=2025-10 ===\n")
asp <- as.data.table(read_parquet(P_ALPHA))
asp[, Date := as.Date(Date)]
print(asp[Date >= as.Date("2025-10-01"),
          .(Date, YM, Cash_Pct_lag, Regime_Score_lag, decay_signal,
            bocpd_short_run_mass_lag, weight_str1715, weight_cash)])

# ── [3] 현행 m4_extended.csv ──
cat("\n=== [3] m4_extended.csv Date>=2025-10 ===\n")
m4csv <- fread(P_M4CSV)
m4csv[, Date := as.Date(Date)]
print(m4csv[Date >= as.Date("2025-10-01")])

# ── [4] 계약 rds 2026-06 행 검증 (read-only) ──
cat("\n=== [4] bt_result_C_noL4_CLEAN_ann12.rds 검증 ===\n")
bt <- readRDS(P_RDS)
cat("  components:", paste(names(bt), collapse = ", "), "\n")
pr_rds <- as.data.table(bt$period_returns)
cat("  period_returns cols:", paste(names(pr_rds), collapse = ", "), "\n")
ymcol <- intersect(c("realized_ym", "ym", "YM"), names(pr_rds))[1]
if (is.na(ymcol)) {
  dcol <- intersect(c("date", "Date", "anchor_date"), names(pr_rds))[1]
  pr_rds[, realized_ym := format(as.Date(get(dcol)), "%Y-%m")]
  ymcol <- "realized_ym"
}
print(pr_rds[get(ymcol) %in% c("2026-04", "2026-05", "2026-06")])
rds_jun <- pr_rds[get(ymcol) == "2026-06"]
retcol <- intersect(c("ret_net", "ret", "portfolio_return"), names(pr_rds))[1]
rds_jun_ret <- as.numeric(rds_jun[[retcol]][1])
cat(sprintf("  rds 2026-06 %s = %.15f\n", retcol, rds_jun_ret))

# ── [5] 03_period_returns.csv June 행 (ret_orig 확인) ──
cat("\n=== [5] 03_period_returns.csv tail ===\n")
pr <- fread(P_PR)
pr[, date := as.Date(date)]
print(pr[date >= as.Date("2026-03-01"), .(date, ret_net, ret_gross, turnover)])
ret_orig_jun <- pr[format(date, "%Y-%m") == "2026-06", ret_net][1]
cat(sprintf("  ret_orig(2026-06) = %.15f\n", ret_orig_jun))

# ── [6] 엔진 PIT 재계산 (factor_engine.R 함수만 eval — main() 스킵, 파일 무기록) ──
cat("\n=== [6] factor_engine.R 재계산 (sandbox env, main() 미실행) ===\n")
Sys.setenv(PG2_AS_OF = "2026-07-01")   # 07-02 07:31 vintage와 동일 grid
eng <- new.env(parent = globalenv())
exprs <- parse(P_ENGINE)
skipped <- 0L
for (e in exprs) {
  txt <- paste(deparse(e), collapse = " ")
  if (grepl("result\\s*<-\\s*main\\(\\)", txt)) { skipped <- skipped + 1L; next }
  eval(e, envir = eng)
}
stopifnot(skipped == 1L)               # main() 호출 1개만 스킵됐는지 확인
out_new <- eng$run_engine()            # returns data.table — no file writes
out_new <- as.data.table(out_new)
out_new[, Date := as.Date(Date)]

cmp <- merge(m4csv[, .(Date, w_csv = weight_str1715)],
             out_new[, .(Date, w_recompute = weight_str1715)],
             by = "Date", all = TRUE)
cmp[, diff := w_recompute - w_csv]
fwrite(cmp, file.path(OUT, "m4_recompute_vs_csv.csv"))
cat(sprintf("  rows: csv=%d recompute=%d merged=%d\n",
            nrow(m4csv), nrow(out_new), nrow(cmp)))
cat(sprintf("  max |diff| = %.10f | n(|diff|>1e-9) = %d\n",
            max(abs(cmp$diff), na.rm = TRUE), sum(abs(cmp$diff) > 1e-9, na.rm = TRUE)))
recent <- merge(cmp[Date >= as.Date("2025-10-01")],
                out_new[Date >= as.Date("2025-10-01"),
                        .(Date, Cash_Pct_lag, Regime_Score_lag)],
                by = "Date", all.x = TRUE)
print(recent)
fwrite(recent, file.path(OUT, "m4_recompute_recent.csv"))

# ── [7] 판정: recon 컨벤션(ym join + weight lag 1)으로 2026-06 적용 m4 ──
cat("\n=== [7] 판정 — realized_ym 2026-06 적용 m4 (lag 컨벤션) ===\n")
sched <- copy(out_new)[, ym := format(Date, "%Y-%m")]
setorder(sched, Date)
sched[, w_lag := shift(weight_str1715, 1, fill = 1.0)]
m4_true <- sched[ym == "2026-06", w_lag][1]
m4_row_may  <- sched[ym == "2026-05", weight_str1715][1]
cat(sprintf("  재계산 m4 row 2026-05 = %.6f | row 2026-06 = %.6f\n",
            m4_row_may, sched[ym == "2026-06", weight_str1715][1]))
cat(sprintf("  ==> recon 2026-06 적용 m4 (lag) = %.6f\n", m4_true))

beta_r05  <- 0.5
cost_term <- 0.00075          # |Δβ_R05| × 15bps (repair_log 산식, 양측 동일)
ret_correct <- beta_r05 * m4_true * ret_orig_jun - cost_term
ret_rds     <- beta_r05 * 1.0     * ret_orig_jun - cost_term
cat(sprintf("  ret_net(정답 m4=%.4f) = %.15f\n", m4_true, ret_correct))
cat(sprintf("  ret_net(rds m4=1.0)   = %.15f (rds 실측 %.15f)\n", ret_rds, rds_jun_ret))
cat(sprintf("  recon 2026-06 Δ (정답 − rds) = %+.6f\n", ret_correct - rds_jun_ret))

# ── [8] 시리즈 영향 진단 (read-only: live_book_series 로드 후 메모리 상 교체) ──
cat("\n=== [8] 전 구간 영향 진단 (diagnostic — 표준함수만) ===\n")
lb <- fread(P_LIVE)
ymc <- intersect(c("realized_ym", "ym", "YM"), names(lb))[1]
dc  <- intersect(c("anchor_date", "date", "Date"), names(lb))[1]
cat("  live_book_series cols:", paste(names(lb), collapse = ", "), "\n")
lb[, d := as.Date(get(dc))]
setorder(lb, d)
r_base <- lb$ret_net
r_corr <- r_base
idx <- which(lb[[ymc]] == "2026-06")
stopifnot(length(idx) == 1L)
r_corr[idx] <- ret_correct
x_base <- xts(r_base, order.by = lb$d)
x_corr <- xts(r_corr, order.by = lb$d)
t_base <- table.AnnualizedReturns(x_base, scale = 12, Rf = 0)
t_corr <- table.AnnualizedReturns(x_corr, scale = 12, Rf = 0)
mdd_b  <- maxDrawdown(x_base)
mdd_c  <- maxDrawdown(x_corr)
cat(sprintf("  [현행 rds passthrough] SR_geo=%.4f CAGR=%.4f MDD=%.4f\n",
            as.numeric(t_base[3, 1]), as.numeric(t_base[1, 1]), mdd_b))
cat(sprintf("  [2026-06 정정 가정]    SR_geo=%.4f CAGR=%.4f MDD=%.4f\n",
            as.numeric(t_corr[3, 1]), as.numeric(t_corr[1, 1]), mdd_c))

res <- list(
  task = "live_hygiene_20260713_item1_adjudication",
  generated = format(Sys.time()),
  metric_type = "diagnostic(재계산 판별 재료 — recon 원본 무수정)",
  m4_recompute = list(
    row_2026_05 = m4_row_may,
    row_2026_06 = sched[ym == "2026-06", weight_str1715][1],
    applied_2026_06_lag_convention = m4_true,
    engine = "WT-D20260430_001 factor_engine.R run_engine() sandbox (PG2_AS_OF=2026-07-01)",
    max_abs_diff_vs_current_csv = max(abs(cmp$diff), na.rm = TRUE)
  ),
  recon_jun2026 = list(
    ret_orig = ret_orig_jun,
    ret_net_correct = ret_correct,
    ret_net_rds = rds_jun_ret,
    delta = ret_correct - rds_jun_ret
  ),
  series_impact_diagnostic = list(
    sr_geo_current = as.numeric(t_base[3, 1]),
    sr_geo_corrected = as.numeric(t_corr[3, 1]),
    cagr_current = as.numeric(t_base[1, 1]),
    cagr_corrected = as.numeric(t_corr[1, 1]),
    mdd_current = as.numeric(mdd_b),
    mdd_corrected = as.numeric(mdd_c)
  )
)
write_json(res, file.path(OUT, "m4_recon_delta.json"), pretty = TRUE,
           auto_unbox = TRUE, digits = 15)
cat("\n[save] m4_recon_delta.json / m4_recompute_vs_csv.csv / m4_recompute_recent.csv / m4_inputs_snapshot.csv\n")
cat("=== DONE ===\n")
