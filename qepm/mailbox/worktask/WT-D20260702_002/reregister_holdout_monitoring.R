## ============================================================================
## WT-D20260702_002 Step 5 — Layer4 제거 book 기준 holdout/monitoring 재등록
##  (a) 구 faith holdout_interval mark_consumed (파라미터 변경=Layer4 제거)
##  (b) noLayer4 book 사전등록 holdout 구간 신규 save (C3 falsification, 불변 봉인)
##  (c) monitoring drift baseline 갱신 config 생성
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics); library(xts)})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/contracts/holdout_falsification.R"))
LT <- file.path(ROOT, "06_Registry/live_track")
COST <- 0.0015

## --- noL4 monthly returns 재구성 (Step3와 동일) ---
p <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym)
dR05 <- abs(p$beta_R05 - shift(p$beta_R05,1,fill=1.0))
p[, ret_noL4 := beta_R05*m4*ret_orig - dR05*COST]

## --- (a) 구 faith holdout 소모 표기 (파라미터 변경) ---
faith_ho <- file.path(LT, "STR_1715_FaithTrend_on_M4_R05_overlay_PG2/holdout_interval.json")
if(file.exists(faith_ho)){
  mark_consumed(faith_ho, "SUPERSEDED by Layer4 removal (WT-D20260702_002, 도훈 FINAL 2026-07-02). Layer4(β_faith) 제거로 전략 파라미터 변경 → C3 소모 규칙 적용. 후속 book=STR_1715_on_M4_R05_noLayer4_PG2 신규 사전등록 구간으로 대체.")
  cat("[a] faith holdout mark_consumed 완료:", faith_ho, "\n")
} else cat("[a] faith holdout 파일 부재 — skip\n")

## --- (b) noLayer4 사전등록 holdout 구간 신규 (불변 봉인) ---
noL4_dir <- file.path(LT, "STR_1715_on_M4_R05_noLayer4_PG2"); dir.create(noL4_dir, showWarnings=FALSE, recursive=TRUE)
noL4_ho <- file.path(noL4_dir, "holdout_interval.json")
iv <- build_holdout_interval(p$ret_noL4, holdout_months=21L, block=12L, B=4000L, seed=7L)
iv$strategy_id <- "STR_1715_on_M4_R05_noLayer4_PG2"
iv$generated <- "2026-07-02"
iv$supersedes <- "STR_1715_FaithTrend_on_M4_R05_overlay_PG2 (consumed via Layer4 removal WT-D20260702_002)"
iv$origin_wt <- "WT-D20260702_002"
if(file.exists(noL4_ho)){
  cat("[b] noL4 holdout 이미 존재 — 불변 원칙(overwrite 거부). 기존 유지.\n")
} else {
  save_holdout_interval(iv, noL4_ho, overwrite=FALSE)
  cat(sprintf("[b] noL4 사전등록 holdout 저장: q05=%.4f q95=%.4f boot_median=%.4f sr_input=%.4f\n",
      iv$q05, iv$q95, iv$boot_median, iv$sr_input))
}

## --- (c) monitoring drift baseline config 갱신 ---
x <- xts(p$ret_noL4, order.by=p$anchor_date)
tar <- table.AnnualizedReturns(x, scale=12)
mon_dir <- file.path(ROOT, "qepm/mailbox/monitoring"); dir.create(mon_dir, showWarnings=FALSE, recursive=TRUE)
mon <- list(
  strategy_id="STR_1715_on_M4_R05_noLayer4_PG2",
  generated="2026-07-02",
  origin="WT-D20260702_002 Layer4 removal (도훈 FINAL)",
  supersedes="STR_1715_FaithTrend_on_M4_R05_overlay_PG2 monitoring baseline",
  baseline_metrics=list(
    metric_type="backtested(contract)", frequency="monthly", n_periods=nrow(p),
    SR_geo=round(as.numeric(tar[3,1]),4), SR_arith_charter12=round(mean(p$ret_noL4)/sd(p$ret_noL4)*sqrt(12),4),
    CAGR=round(as.numeric(Return.annualized(x,scale=12)),4), MDD=round(as.numeric(maxDrawdown(x)),4),
    Calmar=round(as.numeric(CalmarRatio(x,scale=12)),4), PORT_t_NW_lag3=6.214, net_active_IR_geo=1.755, net_active_IR_arith=1.416),
  holdout_interval_ref=noL4_ho,
  drift_alerts=list(
    holdout_lower_breach="trailing 실측(paper/실계좌 NAV) 월간 대조, q05 하단 침범 시 Telegram alert (자동 퇴출 아님 — 도훈 수동)",
    exposure_note="Layer4 제거로 라이브 노출 상승(당월 +14.87%p). 강세국면 상대우위·조정국면 상대열위(R05×m4 방어 유지) — regime별 realized vs predicted 추적",
    check_freq="monthly"),
  note="Layer4 제거 book 기준 monitoring. 구 faith baseline supersede. 실투 퇴출은 도훈 수동(자동 아님)."
)
mon_path <- file.path(mon_dir, "STR_1715_on_M4_R05_noLayer4_PG2_monthly_drift_config.json")
write_json(mon, mon_path, auto_unbox=TRUE, pretty=TRUE, na="null", digits=6)
cat("[c] monitoring drift config 저장:", mon_path, "\n")
cat("\n[DONE] Step5 holdout/monitoring 재등록 완료\n")
