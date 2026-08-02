# =============================================================================
# ax001_conditional.R — WT-D20260802_005 miscored 후보 AX-001 v2 조건부 재채점
#
# 대상: 방어형 성격 후보(vol_rank_stability_v1 / C_VolRankStability_3M)가
#       전기간 SR/CAGR/MDD로 채점되어 Grade F가 된 것이 AX-001 위반(miscored)인지 판정.
# 입력: canonical_screen_bt 산출 period_returns CSV (ret_net = canonical top-25 EW
#       net, benchmark_ret = KOSPI200). metric_type = "canonical_screen_diag".
# 축 (AX-001 v2): ① crisis_alpha (위기월 active 평균)  ② Core(BM) 대비 MDD 완화
#       ③ bad/normal 조건부 성과 ratio (IC 부재 시 active-return ratio로 근사 — 라벨 명시)
# 표준함수: maxDrawdown(PerformanceAnalytics)만. 자체 NAV 합성 없음.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts", "WT-D20260802_005")

crisis_windows <- list(
  GFC        = c("2008-06-01", "2009-03-31"),
  EU2011     = c("2011-08-01", "2011-12-31"),
  COVID      = c("2020-02-01", "2020-03-31"),
  RATE2022   = c("2022-01-01", "2022-10-31"),
  CRASH2607  = c("2026-07-01", "2026-07-31")
)

score_one <- function(label) {
  f <- file.path(OUT, sprintf("period_returns_%s.csv", label))
  if (!file.exists(f)) return(NULL)
  pr <- fread(f)
  pr[, date := as.Date(date)]
  pr[, active := ret_net - benchmark_ret]
  in_crisis <- rep(FALSE, nrow(pr))
  for (w in crisis_windows) in_crisis <- in_crisis | (pr$date >= as.Date(w[1]) & pr$date <= as.Date(w[2]))
  x_strat <- xts(pr$ret_net, order.by = pr$date)
  x_bm    <- xts(pr$benchmark_ret, order.by = pr$date)
  bad     <- pr$benchmark_ret < 0
  list(
    label = label,
    metric_type = "canonical_screen_diag",
    n_months = nrow(pr), n_crisis_months = sum(in_crisis),
    crisis_alpha_monthly_mean = mean(pr$active[in_crisis]),
    crisis_alpha_hit_rate = mean(pr$active[in_crisis] > 0),
    normal_alpha_monthly_mean = mean(pr$active[!in_crisis]),
    mdd_strategy = as.numeric(maxDrawdown(x_strat)),
    mdd_core_bm  = as.numeric(maxDrawdown(x_bm)),
    mdd_relief_vs_core = as.numeric(maxDrawdown(x_bm)) - as.numeric(maxDrawdown(x_strat)),
    bad_month_active_mean = mean(pr$active[bad]),
    normal_month_active_mean = mean(pr$active[!bad]),
    bad_normal_ratio_note = "IC 부재 — active-return 조건부 평균으로 근사 (AX-001 bad/normal IC ratio 대용, 라벨 명시)",
    ax001_verdict = NA_character_
  )
}

labels <- c("vol_rank_stability_v1", "C_VolRankStability_3M", "hill_tail_index")
res <- Filter(Negate(is.null), lapply(labels, score_one))
for (r in res) {
  # 방어형 자격: 위기월 active > 0 AND Core 대비 MDD 완화 > 0 AND bad월 active > normal월 active
  ok <- (r$crisis_alpha_monthly_mean > 0) + (r$mdd_relief_vs_core > 0) + (r$bad_month_active_mean > r$normal_month_active_mean)
  r$ax001_verdict <- if (ok >= 2) "DEFENSIVE_QUALIFIED (miscored 개연 — 조건부 재채점 통과 2/3+)" else "NOT_DEFENSIVE (전기간 채점 정당 — miscored 아님)"
  cat(sprintf("[%s] crisis_a=%.4f hit=%.2f | mdd strat %.3f vs BM %.3f (relief %.3f) | bad %.4f vs normal %.4f | %s\n",
              r$label, r$crisis_alpha_monthly_mean, r$crisis_alpha_hit_rate,
              r$mdd_strategy, r$mdd_core_bm, r$mdd_relief_vs_core,
              r$bad_month_active_mean, r$normal_month_active_mean, r$ax001_verdict))
}
write_json(res, file.path(OUT, "ax001_conditional_20260802.json"), auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 6)
cat("saved ax001_conditional_20260802.json\n")
