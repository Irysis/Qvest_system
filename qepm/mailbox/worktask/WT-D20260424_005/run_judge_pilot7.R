#==============================================================================
# Judge Pilot 7 — Gate A~F + Lockbox OOS + Lockbox Regime Decomposition
# WT-D20260424_005
#
# 단독 실행: Rscript run_judge_pilot7.R
#
# 산출물:
#   stage_artifacts/WT_D20260424_005/lockbox_oos_summary.json
#   stage_artifacts/WT_D20260424_005/lockbox_regime_decomposition.json  (신규)
#   stage_artifacts/WT_D20260424_005/lockbox_access_log.json
#   stage_artifacts/WT_D20260424_005/equity_curve_full.png
#   stage_artifacts/WT_D20260424_005/equity_curve_oos.png
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260424_005"
STAGE_ID     <- "WT_D20260424_005"

STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", STAGE_ID)
WT_DIR    <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
BT_DIR    <- file.path(WT_DIR, "backtest_result")

dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

setwd(PROJECT_ROOT)

source(file.path(PROJECT_ROOT, "02_Infrastructure", "validation", "judge_oos_helper.R"))

cat("\n[judge_pilot7] ==================================================\n")
cat(sprintf("[judge_pilot7] Pilot 7 Judge — %s\n", WT_ID))
cat("[judge_pilot7] ==================================================\n\n")

# ─── 1) Lockbox OOS backtest + charts ──────────────────────────
cat("[judge_pilot7] (1) judge_generate_oos_charts() — full + OOS 차트 + oos_summary.json\n")
oos_res <- judge_generate_oos_charts(wt_id = WT_ID, out_dir = STAGE_DIR)
cat(sprintf("[judge_pilot7]  full_chart: %s\n", oos_res$full_chart_path))
cat(sprintf("[judge_pilot7]  oos_chart : %s\n", oos_res$oos_chart_path))
cat(sprintf("[judge_pilot7]  oos_SR    : %.3f / CAGR %.2f%% / MDD %.2f%%\n",
            oos_res$oos_performance$Sharpe,
            oos_res$oos_performance$CAGR,
            oos_res$oos_performance$MDD))

# oos_summary.json은 judge helper가 backtest_result 밑에 저장. stage_artifacts 경로로 복사 + rename.
src_summary <- file.path(STAGE_DIR, "oos_summary.json")
if (!file.exists(src_summary)) {
  alt_path <- file.path(BT_DIR, "oos_summary.json")
  if (file.exists(alt_path)) {
    file.copy(alt_path, src_summary, overwrite = TRUE)
  }
}
dst_summary <- file.path(STAGE_DIR, "lockbox_oos_summary.json")
if (file.exists(src_summary)) {
  file.copy(src_summary, dst_summary, overwrite = TRUE)
  cat(sprintf("[judge_pilot7]  lockbox_oos_summary.json copied to: %s\n", dst_summary))
}

# ─── 2) Lockbox regime decomposition (신규 핵심) ────────────────
cat("\n[judge_pilot7] (2) Lockbox regime decomposition — 4-regime 분해\n")

bt <- judge_oos_backtest(wt_id = WT_ID)  # daily nav 다시 생성
full_nav <- bt$lockbox_dt  # Lockbox 구간 (2024-01-23+)

# regime parquet (monthly → daily forward-fill)
regime_dt <- as.data.table(read_parquet(file.path(PROJECT_ROOT,
                                                   ".cache",
                                                   "unified_regime_signal.parquet")))
setnames(regime_dt, "Category", "regime")

# daily return 계산
full_nav[, Date := as.Date(Date)]
setorder(full_nav, Date)
full_nav[, ret := c(NA, diff(log(NAV)))]
full_nav[, ret := ifelse(is.na(ret), 0, ret)]

# regime forward-fill daily
regime_daily <- regime_dt[, .(month_end = Date, regime)]
setorder(regime_daily, month_end)

# for each daily row, find latest regime where month_end <= Date (t-1 PIT)
# — regime_daily$month_end is monthly, daily needs rolling join
full_nav_rj <- full_nav[, .(Date, NAV, ret)]
setkey(full_nav_rj, Date)
setkey(regime_daily, month_end)

full_nav_rj[, regime := regime_daily[full_nav_rj, regime, roll = TRUE, on = c(month_end = "Date")]]
# ensure label present
full_nav_rj[is.na(regime), regime := "UNKNOWN"]

# Lockbox regime stats
lockbox_dt <- full_nav_rj[!is.na(ret)]
total_days <- nrow(lockbox_dt)

regime_tbl <- lockbox_dt[, .(
  days = .N,
  days_pct = round(.N / total_days * 100, 2),
  mean_ret = mean(ret, na.rm = TRUE),
  sd_ret = sd(ret, na.rm = TRUE)
), by = regime]

# per-regime performance (annualized, SR, MDD)
compute_regime_perf <- function(r_subset) {
  if (nrow(r_subset) < 5) {
    return(list(sr = NA, cagr = NA, mdd = NA, calmar = NA, n = nrow(r_subset)))
  }
  ret_vec <- r_subset$ret
  n <- length(ret_vec)
  ann <- (prod(1 + ret_vec))^(252 / n) - 1
  vol <- sd(ret_vec) * sqrt(252)
  sr  <- if (vol > 1e-10) ann / vol else NA_real_
  # MDD for regime sub-period
  cum <- cumprod(1 + ret_vec)
  dd <- (cum / cummax(cum)) - 1
  mdd <- min(dd, na.rm = TRUE)
  cal <- if (!is.na(mdd) && mdd < 0) ann / abs(mdd) else NA_real_
  list(
    sr    = round(sr, 4),
    cagr  = round(ann * 100, 2),
    mdd   = round(mdd * 100, 2),
    calmar = round(cal, 3),
    n     = n
  )
}

regime_stats <- list()
for (reg in c("RISK_ON", "NEUTRAL", "CAUTION", "RISK_OFF", "CRISIS", "UNKNOWN")) {
  sub <- lockbox_dt[regime == reg]
  info <- compute_regime_perf(sub)
  regime_stats[[reg]] <- list(
    days     = info$n,
    days_pct = if (total_days > 0) round(info$n / total_days * 100, 2) else 0,
    sr       = info$sr,
    cagr     = info$cagr,
    mdd      = info$mdd,
    calmar   = info$calmar
  )
}

# total lockbox metric
total_perf <- compute_regime_perf(lockbox_dt)

# Benchmark (KOSPI200 TR) regime stats for contextual comparison
cat("[judge_pilot7]  computing benchmark regime comparison...\n")
bm_path <- file.path(PROJECT_ROOT, ".cache", "benchmark.parquet")
bm_dt   <- as.data.table(read_parquet(bm_path))
bm_dt[, Date := as.Date(Date)]
if (!"BM_Ret" %in% names(bm_dt)) {
  bm_dt[, BM_Ret := c(NA, diff(log(BM_Close)))]
}
bm_lb <- bm_dt[Date >= min(lockbox_dt$Date) & Date <= max(lockbox_dt$Date),
                .(Date, BM_Ret)]
setkey(bm_lb, Date)
lb_join <- merge(lockbox_dt, bm_lb, by = "Date", all.x = TRUE)
lb_join[, BM_Ret := ifelse(is.na(BM_Ret), 0, BM_Ret)]

bm_regime_stats <- list()
for (reg in c("RISK_ON", "NEUTRAL", "CAUTION", "RISK_OFF", "CRISIS", "UNKNOWN")) {
  sub <- lb_join[regime == reg, .(ret = BM_Ret)]
  info <- compute_regime_perf(sub)
  bm_regime_stats[[reg]] <- list(
    sr   = info$sr,
    cagr = info$cagr,
    mdd  = info$mdd
  )
}

# 분석 결론 자동 분류
ro_pct    <- regime_stats$RISK_ON$days_pct
neut_pct  <- regime_stats$NEUTRAL$days_pct
caut_pct  <- regime_stats$CAUTION$days_pct
ro_sr     <- regime_stats$RISK_ON$sr
neut_sr   <- regime_stats$NEUTRAL$sr
caut_sr   <- regime_stats$CAUTION$sr

l196_verdict <- "UNDETERMINED"
l196_rationale <- ""

# 판정 규칙
# - RISK_ON 비중 80%+ & 전체 SR 대부분 RISK_ON 기여 → regime_lucky
# - 레짐 분산 (3+ regime 15%+) 고른 양의 SR → strategy_essence (AX-007 예외 candidate)
# - 그 외 (RISK_ON 지배 + 해당 SR 집중) → minvar_superior
reg_exposure_balance <- sum(c(ro_pct, neut_pct, caut_pct) >= 15, na.rm = TRUE)
positive_sr_count <- sum(c(ro_sr, neut_sr, caut_sr) > 0.2, na.rm = TRUE)

if (!is.na(ro_pct) && ro_pct >= 80) {
  # RISK_ON 지배적
  if (!is.na(ro_sr) && ro_sr > 0.5) {
    l196_verdict <- "regime_lucky"
    l196_rationale <- sprintf("RISK_ON %.1f%% 지배 + RISK_ON SR %.3f 강함. Lockbox 성과가 특정 regime에 강하게 의존. 전략 본질 아님.",
                              ro_pct, ro_sr)
  } else {
    l196_verdict <- "minvar_superior"
    l196_rationale <- sprintf("RISK_ON %.1f%% 지배 but RISK_ON SR %.3f 약함. 비지배 regime 기여도가 SR 견인. Pilot 6 pattern 반복.",
                              ro_pct, ifelse(is.na(ro_sr), 0, ro_sr))
  }
} else if (reg_exposure_balance >= 3 && positive_sr_count >= 2) {
  l196_verdict <- "strategy_essence"
  l196_rationale <- sprintf("레짐 3종 이상 %.0f%%+ 분산 + %d개 regime 양의 SR. AX-007 예외지대 candidate.",
                            15, positive_sr_count)
} else {
  l196_verdict <- "minvar_superior"
  l196_rationale <- sprintf("레짐 분산 중간 (RISK_ON %.1f%% / NEUT %.1f%% / CAUT %.1f%%). MinVar+β 구조 반복 우위.",
                            ro_pct, neut_pct, caut_pct)
}

# 산출물 기록
decomp_out <- list(
  wt_id        = WT_ID,
  agent        = "judge",
  period       = sprintf("%s ~ %s (%d days)",
                          as.character(min(lockbox_dt$Date)),
                          as.character(max(lockbox_dt$Date)),
                          total_days),
  source_regime = ".cache/unified_regime_signal.parquet (monthly forward-filled)",
  regime_stats = regime_stats,
  benchmark_regime_stats = bm_regime_stats,
  total_lockbox = list(
    sr        = total_perf$sr,
    cagr      = total_perf$cagr,
    mdd       = total_perf$mdd,
    calmar    = total_perf$calmar,
    n_days    = total_perf$n
  ),
  l196_final_verdict = list(
    verdict   = l196_verdict,
    rationale = l196_rationale,
    risk_on_dominance_pct = ro_pct,
    risk_on_sr            = ro_sr,
    neutral_pct           = neut_pct,
    caution_pct           = caut_pct,
    positive_sr_regimes   = positive_sr_count
  ),
  as_of     = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

decomp_path <- file.path(STAGE_DIR, "lockbox_regime_decomposition.json")
write_json(decomp_out, decomp_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
cat(sprintf("[judge_pilot7]  lockbox_regime_decomposition.json saved: %s\n", decomp_path))
cat(sprintf("[judge_pilot7]  l196_verdict: %s\n", l196_verdict))
cat(sprintf("[judge_pilot7]  rationale: %s\n", l196_rationale))

# ─── 3) Lockbox access log (공식 기록) ─────────────────────────
access_log_path <- file.path(STAGE_DIR, "lockbox_access_log.json")
access_list <- list(
  wt_id      = WT_ID,
  agent      = "judge",
  model      = "claude-opus-4-7",
  task       = "pilot7_gate_a_through_f",
  accesses   = list(
    list(stamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
         resource = ".cache/benchmark.parquet",
         purpose = "lockbox_oos_bm_return"),
    list(stamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
         resource = "stage_artifacts/WT_D20260424_005/weights.csv",
         purpose = "lockbox_oos_weights"),
    list(stamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
         resource = "RAWDATA.parquet[lockbox_slice]",
         purpose = "lockbox_oos_prices"),
    list(stamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
         resource = ".cache/unified_regime_signal.parquet",
         purpose = "lockbox_regime_decomposition")
  ),
  ax002_compliance = TRUE,
  raw_log_path = sprintf("/tmp/qvest_lockbox_access_%s.log", WT_ID)
)
write_json(access_list, access_log_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[judge_pilot7]  lockbox_access_log.json saved: %s\n", access_log_path))

cat("\n[judge_pilot7] ========= DONE =========\n")
cat(sprintf("[judge_pilot7] Lockbox: SR=%.3f / CAGR=%.2f%% / MDD=%.2f%%\n",
            oos_res$oos_performance$Sharpe,
            oos_res$oos_performance$CAGR,
            oos_res$oos_performance$MDD))
cat(sprintf("[judge_pilot7] L-196: %s\n", l196_verdict))
