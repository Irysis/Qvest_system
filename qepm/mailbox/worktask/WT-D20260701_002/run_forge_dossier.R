## ============================================================================
## WT-D20260701_002 Forge — PG2 오버레이 개선안 capital-grade dossier 측정
## Pure measurement: verify_overlay_series.csv (ret_faith 개선 / ret_book 현행)
##   → build_bt_result 10-component + audit + benchmark_compare(NW lag-3) + register
## Overlay 스펙/β/수익경로 수정 없음. PerformanceAnalytics 표준함수만(계약 경유).
## ============================================================================

suppressPackageStartupMessages({
  library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)
})

ROOT   <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PROJECT_ROOT <- ROOT  # save/register root resolver
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260701_002")
OUT    <- file.path(WT_DIR, "output"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/save_bt_result.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/registry_writer.R"))

d <- fread(file.path(WT_DIR, "verify_overlay_series.csv"))
d[, date := as.Date(date)]
setorder(d, date)
cat(sprintf("[data] %d months | %s ~ %s\n", nrow(d),
            as.character(min(d$date)), as.character(max(d$date))))

## ── 정직 캐비앗 (manifest/audit 명기용) ─────────────────────────────────────
HONEST_CAVEATS <- c(
  "MECHANISM_GENERIC=개선 오버레이 메커니즘은 generic 비대칭 추세추종(하락추세 방어) — 논문4(Safari-Schmidhuber) 고유 아님. plain-TS-mom도 계약SR 1.97(개선의 ~93%).",
  "PROXY_PROMOTION=proxy 재구성(python ar_faithful_v3) 월수익 시리즈를 forge full build_bt_result로 official(backtested) 승격.",
  "DSR_MULTIPLE_TESTING=다변형(T=8/16/32/64 + regime map + combine) 탐색 → DSR 다중검정 haircut 여지. 단 사전약정 논문계수가 placebo+oos_retention 통과.",
  "GFC2008_AR_SUPERIOR=2008 GFC 구간낙폭은 현행 AR(-9.3%)이 개선 충실(-17.5%) 우위. 충실은 추세 de-risk지 systemic-crash 탐지 아님.",
  "PURE_MEASUREMENT=forge는 주어진 ret_faith/ret_book를 계약으로 측정만 함. 오버레이 β/수익경로/alpha/weight 재해석 없음.")

## ── sim_result shim (monthly) ────────────────────────────────────────────────
## build_bt_result가 요구: strategy_xts(월수익) / DAILY_NAV_DT(월 NAV path) / bm_xts(월수익)
## frequency="monthly" → build_period_returns가 apply.monthly(Return.cumulative) 적용
## (월-키 1obs → 자기값 반환, 자체합성 없음). annualization_factor=12.
make_sim_result <- function(ret_vec, dates, bm_vec) {
  strat_xts <- xts(ret_vec, order.by = dates)
  # NAV path: PerformanceAnalytics cumulative (Return.portfolio 없이 단일 시리즈이므로
  #           계약 build_nav는 nav_net을 요구 → cumprod NAV 제공. Return.cumulative 동등.)
  nav_net   <- as.numeric(cumprod(1 + ret_vec))
  nav_dt <- data.table(Date = dates, NAV = nav_net, NAV_gross = nav_net)
  list(
    strategy_xts = strat_xts,
    DAILY_NAV_DT = nav_dt,
    bm_xts = xts(bm_vec, order.by = dates),
    HOLDINGS_LOG = NULL,       # book 원본과 동일: holdings=NULL (scalar overlay, holding 불변)
    PORTFOLIO_LOG = NULL
  )
}

spec_for <- function(strategy_id, label, cav) {
  list(
    strategy_id = strategy_id,
    strategy_name = label,
    strategy_family = "overlay_pg2_str1715",
    signal_description = paste0(
      "STR_1715_AR_on_M4_R05_overlay_PG2 sequential scalar overlay. ",
      "ret = beta_R05_V5 x beta_overlay x m4_weight_lag x ret_orig - Dbeta_overlay*15bps - Dbeta_R05*15bps. ",
      "현행=beta_AR(absorption ratio) / 개선=논문4 충실 예측변동성(sigma2_t+1=0.13+0.79 sigma2_t-0.17 phi_t+0.09 phi2_t) 확장백분위 -> {0.4,0.7,1.0} 계단."),
    universe_rule = "KOSPI200 U KOSDAQ150 (STR_1715 admit lineage, holdings 불변)",
    rebalance_frequency = "monthly",
    signal_date_rule = "sig_date t-1 EOM (phi/sigma2 KOSPI benchmark.parquet <=t-1, 월말 lag-1, 확장백분위 과거만)",
    execution_date_rule = "month_first_biz_day (realized month t)",
    weighting_method = "Iter31 production linear_tilt baked in PR ret_net (scalar overlay only, NOT EW)",
    max_position_weight = 0.20,
    max_leverage = 1.0,
    cash_rule = "scalar de-risk (beta<1 -> implicit cash), no explicit cash sleeve",
    cost_model = "v2.4_kr_retail_15bps delta-based: |Dbeta_overlay|*15bps + |Dbeta_R05|*15bps on top of PR ret_net",
    missing_data_rule = "beta default 1.0 pre-warmup / expanding past-only quantile NA->1.0",
    risk_controls = "AX-001 v2 conditional defense (CRISIS/CAUTION), max 25 names, long-only, Sw=1",
    lookahead_prevention = paste0(
      "PIT C1_C5_C11_C13_C14: signal phi/sigma2 KOSPI <=t-1, beta decision t-1 EOM applied to t (shift(1)), ",
      "expanding past-only percentile. 입력 시리즈 python 재구성 PIT (dossier_input.md 참조). look-ahead 재검=신호 lag t-1 확인."),
    survivorship_bias_control = "STR_1715 admit lineage universe (survivorship-aware factor DB)",
    honest_caveats = paste(cav, collapse = " || ")
  )
}

measure <- function(ret_col, strategy_id, label) {
  cat(sprintf("\n================ MEASURE: %s (%s) ================\n", strategy_id, ret_col))
  sim <- make_sim_result(d[[ret_col]], d$date, d$bmret)
  spec <- spec_for(strategy_id, label, HONEST_CAVEATS)

  bt <- build_bt_result(
    sim_result = sim, strategy_spec = spec,
    run_id = paste0("WT-D20260701_002_", ret_col),
    strategy_id = strategy_id, strategy_version = "v1.0_dossier",
    benchmark_id = "KOSPI200_total_return", benchmark_name = "KOSPI200 total return (monthly)",
    transaction_cost_bps = 15, slippage_bps = 0, risk_free_rate = 0,
    frequency = "monthly", annualization_factor = 12,
    universe_id = "KOSPI200_KOSDAQ150", code_version = "run_forge_dossier_v1",
    created_by_agent = "forge"
  )
  # honest caveats into manifest
  bt$manifest[, honest_caveats := paste(HONEST_CAVEATS, collapse = " || ")]
  bt$manifest[, measurement_note := "monthly period_returns direct-fed; nav=cumprod(1+ret); benchmark=KOSPI monthly. holdings=NULL (scalar overlay). proxy->backtested promotion."]

  bt <- audit_bt_result(bt)

  # add honest-caveat rows to audit table for surfacing
  cav_rows <- rbindlist(lapply(seq_along(HONEST_CAVEATS), function(i) data.table(
    run_id = bt$manifest$run_id[1], check_group = "honest_caveat",
    check_name = sprintf("caveat_%d", i), status = "NOTE",
    details = HONEST_CAVEATS[i], affected_metrics = "", severity = "info")))
  bt$audit <- rbind(bt$audit, cav_rows, fill = TRUE)

  bt
}

bt_faith <- measure("ret_faith", "STR_1715_AR_on_M4_R05_overlay_PG2_PAPER4_FAITHFUL", "PG2 overlay 개선(논문4 충실 추세)")
bt_book  <- measure("ret_book",  "STR_1715_AR_on_M4_R05_overlay_PG2_CURRENT_AR",     "PG2 overlay 현행(AR absorption ratio)")

## ── official 지표 추출 helper ────────────────────────────────────────────────
gm <- function(bt, nm) {
  m <- bt$metrics
  v <- m[metric_name == nm & is_official == TRUE, metric_value]
  if (length(v) == 0) NA_real_ else as.numeric(v[1])
}
gbc <- function(bt, nm) {
  bc <- bt$benchmark_compare
  v <- bc[metric_name == nm, active_value]
  if (length(v) == 0) NA_real_ else as.numeric(v[1])
}
gbc_s <- function(bt, nm) {
  bc <- bt$benchmark_compare
  v <- bc[metric_name == nm, strategy_value]
  if (length(v) == 0) NA_real_ else as.numeric(v[1])
}

comp <- data.table(
  metric = c("Sharpe","CAGR","Ann_Vol","MDD","Calmar","Sortino",
             "Portfolio_Alpha_t_NW_lag3","Portfolio_Alpha_t_pvalue",
             "Information_Ratio","Alpha_Annualized","Beta_to_BM","Correlation","Hit_vs_BM"),
  improved_faith = c(gm(bt_faith,"Sharpe"), gm(bt_faith,"CAGR"), gm(bt_faith,"Annualized_Volatility"),
                     gm(bt_faith,"MDD"), gm(bt_faith,"Calmar"), gm(bt_faith,"Sortino"),
                     gbc(bt_faith,"Portfolio_Alpha_t_NW_lag3"), gbc(bt_faith,"Portfolio_Alpha_t_pvalue"),
                     gbc(bt_faith,"Information_Ratio"), gbc(bt_faith,"Alpha_Annualized"),
                     gbc_s(bt_faith,"Beta_to_Benchmark"), gbc_s(bt_faith,"Correlation"),
                     gbc_s(bt_faith,"Hit_Ratio_vs_BM")),
  current_book   = c(gm(bt_book,"Sharpe"), gm(bt_book,"CAGR"), gm(bt_book,"Annualized_Volatility"),
                     gm(bt_book,"MDD"), gm(bt_book,"Calmar"), gm(bt_book,"Sortino"),
                     gbc(bt_book,"Portfolio_Alpha_t_NW_lag3"), gbc(bt_book,"Portfolio_Alpha_t_pvalue"),
                     gbc(bt_book,"Information_Ratio"), gbc(bt_book,"Alpha_Annualized"),
                     gbc_s(bt_book,"Beta_to_Benchmark"), gbc_s(bt_book,"Correlation"),
                     gbc_s(bt_book,"Hit_Ratio_vs_BM"))
)
comp[, delta_improved_minus_current := improved_faith - current_book]

cat("\n================ CONTRACT OFFICIAL COMPARISON (improved vs current) ================\n")
print(comp, digits = 5)

cat(sprintf("\n[integrity] faith=%s (%s) | book=%s (%s)\n",
            bt_faith$manifest$integrity_status[1],
            unique(bt_faith$metrics$metric_type)[1],
            bt_book$manifest$integrity_status[1],
            unique(bt_book$metrics$metric_type)[1]))

## ── paired NW t-stat (개선 − 현행 월수익) : 정직 재산출 ─────────────────────
diff_ret <- d$ret_faith - d$ret_book
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x)
  mu <- mean(x); e <- x - mu; g0 <- sum(e^2)/n; s <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); g <- sum(e[(l+1):n]*e[1:(n-l)])/n; s <- s + 2*w*g }
  mu / sqrt(s/n)
}
paired_t <- nw_t(diff_ret, 3L)
cat(sprintf("\n[paired] NW lag-3 t(개선-현행 월수익) = %+.3f (mean diff=%.5f, n=%d)\n",
            paired_t, mean(diff_ret), length(diff_ret)))

## ── save + register (audit PASS면 register) ─────────────────────────────────
save_bt_result(bt_faith, file.path(OUT, "faith_improved"), save_xlsx = FALSE)
save_bt_result(bt_book,  file.path(OUT, "book_current"),   save_xlsx = FALSE)
fwrite(comp, file.path(OUT, "official_comparison_improved_vs_current.csv"))

reg_faith <- register_bt_result(bt_faith)
reg_book  <- register_bt_result(bt_book)
cat(sprintf("\n[register] faith blocked=%s | book blocked=%s\n",
            !is.null(reg_faith$blocked) && isTRUE(reg_faith$blocked),
            !is.null(reg_book$blocked)  && isTRUE(reg_book$blocked)))

## ── audit FAIL/WARN 요약 출력 ────────────────────────────────────────────────
cat("\n================ AUDIT (faith improved) — non-PASS rows ================\n")
print(bt_faith$audit[status != "PASS" & check_group != "honest_caveat",
                     .(check_name, status, severity, details)])

## dossier json summary
summ <- list(
  wt_id = "WT-D20260701_002", agent = "forge", measurement = "capital-grade dossier (contract official)",
  period = list(start = as.character(min(d$date)), end = as.character(max(d$date)), n_months = nrow(d)),
  improved_faith = as.list(setNames(comp$improved_faith, comp$metric)),
  current_book   = as.list(setNames(comp$current_book,   comp$metric)),
  delta          = as.list(setNames(comp$delta_improved_minus_current, comp$metric)),
  paired_nw_t_improved_minus_current = round(paired_t, 4),
  integrity = list(faith = bt_faith$manifest$integrity_status[1],
                   book  = bt_book$manifest$integrity_status[1]),
  metric_type = list(faith = unique(bt_faith$metrics$metric_type)[1],
                     book  = unique(bt_book$metrics$metric_type)[1]),
  register = list(faith_blocked = isTRUE(reg_faith$blocked), book_blocked = isTRUE(reg_book$blocked)),
  honest_caveats = HONEST_CAVEATS,
  sharpe_reconciliation = list(
    note = "두 Sharpe 정의 차이(자체합성 아님, 둘 다 표준). 계약 build_metrics는 arithmetic mean-ER Sharpe(Charter v1.4 §12, graduation-authoritative). verify/book원본 run_layer5는 table.AnnualizedReturns[3,1] geometric Sharpe.",
    contract_arithmetic_meanER = list(faith = round(gm(bt_faith,"Sharpe"),4), book = round(gm(bt_book,"Sharpe"),4), delta = round(gm(bt_faith,"Sharpe")-gm(bt_book,"Sharpe"),4)),
    verify_geometric_tableAnn   = list(faith = 2.1112, book = 1.8365, delta = round(2.1112-1.8365,4)),
    direction = "개선>현행 두 정의 모두 일관. delta +0.20(계약) / +0.27(geometric)."),
  vs_dossier_input_verify = list(
    note = "dossier_input verify: faith SR 2.111 / book SR 1.837 (=geometric). 계약 official(arithmetic mean-ER)은 faith 1.875 / book 1.675 — graduation Gate 권위.",
    faith_sr_verify_geometric = 2.111, book_sr_verify_geometric = 1.837)
)
write_json(summ, file.path(OUT, "forge_dossier_summary.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("\n[done] outputs in ", OUT, "\n")
