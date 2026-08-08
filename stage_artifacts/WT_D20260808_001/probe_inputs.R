# =============================================================================
# probe_inputs.R — FQ-122 착수 전 입력 실측 (첫 출력 = 입력 형태 assert)
#   목적: 행수 · 관측단위 · 기간 · 컬럼 · 패널 간 날짜 정합을 측정 전에 인쇄한다.
#   근거: feedback-assert-input-shape-before-measuring (2026-08-08, 하루 5회 같은 뿌리)
#   라벨: metric_type = input_assert (성과 주장 아님)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
say <- function(fmt, ...) cat(sprintf(paste0("[in] ", fmt, "\n"), ...))

shape <- function(nm, dt, datecol = "Date") {
  say("%-22s rows=%8d cols=[%s]", nm, nrow(dt), paste(names(dt), collapse = ","))
  if (datecol %in% names(dt)) {
    d <- as.Date(dt[[datecol]])
    ud <- sort(unique(d))
    gaps <- if (length(ud) > 1) as.numeric(diff(ud)) else NA_real_
    say("%-22s unique %s: %d (%s ~ %s) | 간격 중앙 %.1f일 => 관측단위 %s",
        "", datecol, length(ud), as.character(min(ud)), as.character(max(ud)),
        stats::median(gaps, na.rm = TRUE),
        if (isTRUE(stats::median(gaps, na.rm = TRUE) > 20)) "월간" else "일간/기타")
  }
}

# ── 1. WT-009 tuned panel (D03_EWMA / Q01_EB / M01_PATHQ 원천) ────────────────
TUNED <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_009/tuned_panel.parquet"))
TUNED[, Date := as.Date(Date)]
shape("WT009 tuned_panel", TUNED)
say("Factor_Name 분포:"); print(TUNED[, .(rows = .N, n_month = uniqueN(Date),
      d_min = min(Date), d_max = max(Date)), by = Factor_Name][order(Factor_Name)])

# ── 2. production alpha panel (score_eff) ────────────────────────────────────
AP <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
AP[, Date := as.Date(Date)]
shape("prod alpha_scores", AP)
say("score_eff non-NA %d / regime_state 값: %s", sum(!is.na(AP$score_eff)),
    paste(sort(unique(as.character(AP$regime_state))), collapse = ","))

# ── 3. 날짜 정합 (tuned vs prod) ─────────────────────────────────────────────
d_t <- sort(unique(TUNED$Date)); d_p <- sort(unique(AP[!is.na(score_eff)]$Date))
say("tuned 월 %d (%s~%s) / prod 월 %d (%s~%s) / 교집합 %d",
    length(d_t), as.character(min(d_t)), as.character(max(d_t)),
    length(d_p), as.character(min(d_p)), as.character(max(d_p)),
    length(intersect(as.character(d_t), as.character(d_p))))
say("tuned에만 있는 월 %d / prod에만 %d",
    length(setdiff(as.character(d_t), as.character(d_p))),
    length(setdiff(as.character(d_p), as.character(d_t))))

# ── 4. rawdata / benchmark ───────────────────────────────────────────────────
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date","Ticker","Close","Vol","Ret","Size")))
raw[, Date := as.Date(Date)]
shape("rawdata", raw)
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
shape("benchmark", bm)

# ── 5. production 03_period_returns (parity 대조) ────────────────────────────
pp <- "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"
if (file.exists(pp)) {
  PR <- fread(pp); PR[, date := as.Date(date)]
  say("prod 03_period_returns rows=%d (%s ~ %s) cols=[%s]",
      nrow(PR), as.character(min(PR$date)), as.character(max(PR$date)),
      paste(names(PR), collapse = ","))
} else say("prod 03_period_returns 부재: %s", pp)

# ── 6. 커버리지 교차 (월별 팩터 동시 관측 종목수) ────────────────────────────
W <- dcast(TUNED, Date + Ticker ~ Factor_Name, value.var = "score")
say("wide 패널 rows=%d cols=[%s]", nrow(W), paste(names(W), collapse = ","))
cov_tab <- W[, .(n_ticker = .N,
                 n_M01 = sum(is.finite(M01_PATHQ)),
                 n_D03 = sum(is.finite(D03_EWMA)),
                 n_Q01 = sum(is.finite(Q01_EB)),
                 n_M01_D03 = sum(is.finite(M01_PATHQ) & is.finite(D03_EWMA)),
                 n_M01_Q01 = sum(is.finite(M01_PATHQ) & is.finite(Q01_EB))), by = Date]
say("월별 커버리지 요약 (중앙값): ticker %.0f / M01 %.0f / D03 %.0f / Q01 %.0f / M01∩D03 %.0f / M01∩Q01 %.0f",
    median(cov_tab$n_ticker), median(cov_tab$n_M01), median(cov_tab$n_D03),
    median(cov_tab$n_Q01), median(cov_tab$n_M01_D03), median(cov_tab$n_M01_Q01))
say("커버리지 최소월: M01∩D03 %d / M01∩Q01 %d",
    min(cov_tab$n_M01_D03), min(cov_tab$n_M01_Q01))
say("횡단면 상관 (전체 pooled spearman): D03~Q01 %.4f / M01~D03 %.4f / M01~Q01 %.4f",
    W[, cor(D03_EWMA, Q01_EB, method="spearman", use="complete.obs")],
    W[, cor(M01_PATHQ, D03_EWMA, method="spearman", use="complete.obs")],
    W[, cor(M01_PATHQ, Q01_EB, method="spearman", use="complete.obs")])
saveRDS(list(cov_tab = cov_tab, d_tuned = d_t, d_prod = d_p),
        "stage_artifacts/WT_D20260808_001/probe_inputs.rds")
say("완료")
