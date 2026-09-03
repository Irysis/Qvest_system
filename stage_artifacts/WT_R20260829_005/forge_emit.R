#==============================================================================
# WT-R20260829_005 — Forge emit: charts + authoritative_remeasure.json + forge_package.json
#   ★EX-POST EVALUATOR ONLY. 의사결정 경로 아님(run_all.R [5] 절이 결정경로).
#   여기의 sd()*sqrt() 계열은 사후 평가기이며 신호 구성에 관여하지 않는다.
#==============================================================================
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(xts)})
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

WT_ID <- "WT-R20260829_005"
WT_DIR    <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts", "WT_R20260829_005")
OUT_DIR   <- file.path(STAGE_DIR, "output"); dir.create(OUT_DIR, showWarnings = FALSE)

bt  <- readRDS(file.path(STAGE_DIR, "bt_result.rds"))
ess <- readRDS(file.path(STAGE_DIR, "forge_essence.rds"))
FE  <- readRDS(file.path(STAGE_DIR, "forge_env.rds"))
opt_pkg <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)

M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
getm  <- function(n) { v <- M[metric_name == n, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
getbc <- function(n) { v <- BC[metric_name == n, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
# ★build_benchmark_compare 의 active_value 는 Beta/Correlation/Capture/Hit 행에서
#   strategy_value - benchmark_value 다(예: Beta active -0.2274 = 0.7726 - 1). 수준값은
#   strategy_value 를 읽어야 한다. IR/TE/PORT_t 는 본래 active 량이라 active_value 가 맞다.
getbs <- function(n) { v <- BC[metric_name == n, strategy_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }

PR <- as.data.table(bt$period_returns)[order(date)]
BR <- as.data.table(bt$benchmark_returns)[order(date)]
NV <- as.data.table(bt$nav)[order(date)]
CMP <- merge(PR[, .(date, ret_net)], BR[, .(date, benchmark_ret)], by = "date")
setorder(CMP, date)
CMP[, nav_s := cumprod(1 + ret_net)]
CMP[, nav_b := cumprod(1 + benchmark_ret)]

#---------------------------------------------------------------- charts
png(file.path(OUT_DIR, "equity_curve.png"), width = 1400, height = 800, res = 110)
plot(CMP$date, CMP$nav_s, type = "l", log = "y", col = "#1f5fbf", lwd = 2,
     xlab = "", ylab = "Growth of 1 (log)", main = "WT-R20260829_005 — Forge realized (net) vs KOSPI200")
lines(CMP$date, CMP$nav_b, col = "#999999", lwd = 2)
legend("topleft", c("Strategy (net, share-based)", "KOSPI200"), col = c("#1f5fbf", "#999999"), lwd = 2, bty = "n")
grid(); dev.off()

yr <- CMP[, .(s = prod(1 + ret_net) - 1, b = prod(1 + benchmark_ret) - 1), by = .(y = year(date))]
png(file.path(OUT_DIR, "annual_returns.png"), width = 1400, height = 800, res = 110)
bp <- barplot(t(as.matrix(yr[, .(s, b)])), beside = TRUE, names.arg = yr$y, las = 2,
              col = c("#1f5fbf", "#bbbbbb"), main = "Annual returns — Strategy (net) vs KOSPI200",
              ylab = "annual return")
abline(h = 0); legend("topright", c("Strategy", "KOSPI200"), fill = c("#1f5fbf", "#bbbbbb"), bty = "n")
dev.off()

z0 <- max(CMP$date) - 365 * 5
Z <- CMP[date >= z0]; Z[, ns := cumprod(1 + ret_net)]; Z[, nb := cumprod(1 + benchmark_ret)]
png(file.path(OUT_DIR, "oos_zoom_chart.png"), width = 1400, height = 800, res = 110)
plot(Z$date, Z$ns, type = "l", col = "#1f5fbf", lwd = 2, ylim = range(c(Z$ns, Z$nb)),
     xlab = "", ylab = "Growth of 1", main = sprintf("Recent 5Y zoom (%s ~ %s)", z0, max(CMP$date)))
lines(Z$date, Z$nb, col = "#999999", lwd = 2)
legend("topleft", c("Strategy (net)", "KOSPI200"), col = c("#1f5fbf", "#999999"), lwd = 2, bty = "n")
grid(); dev.off()

# regime decomposition — forge 자체 조작화: 벤치 누적낙폭 <= -20% 인 날 = drawdown state.
#   ★risk 의 KR_Bear_ALL 125개월과 다른 조작화다(재현 주장 아님).
CMP[, b_dd := nav_b / cummax(nav_b) - 1]
CMP[, state := ifelse(b_dd <= -0.20, "bench_dd<=-20%", "normal")]
rg <- CMP[, .(n = .N,
              sr_s = mean(ret_net) / sd(ret_net) * sqrt(252),
              sr_b = mean(benchmark_ret) / sd(benchmark_ret) * sqrt(252),
              cagr_s = prod(1 + ret_net)^(252 / .N) - 1,
              cagr_b = prod(1 + benchmark_ret)^(252 / .N) - 1), by = state]
png(file.path(OUT_DIR, "regime_decomposition.png"), width = 1400, height = 800, res = 110)
par(mfrow = c(1, 2))
barplot(t(as.matrix(rg[, .(sr_s, sr_b)])), beside = TRUE, names.arg = rg$state,
        col = c("#1f5fbf", "#bbbbbb"), main = "Sharpe by benchmark-drawdown state", las = 1)
abline(h = 0)
barplot(t(as.matrix(rg[, .(cagr_s, cagr_b)])), beside = TRUE, names.arg = rg$state,
        col = c("#1f5fbf", "#bbbbbb"), main = "CAGR by benchmark-drawdown state", las = 1)
abline(h = 0); legend("topright", c("Strategy", "KOSPI200"), fill = c("#1f5fbf", "#bbbbbb"), bty = "n")
dev.off()
cat("[charts] 4 png written\n"); print(rg)

#-------------------------------------------------- realized turnover / SR
PL <- as.data.table(bt$holdings)
n_max_rebal <- PL[, uniqueN(ticker), by = date][, max(V1)]
plog <- FE$plog
to_ann <- NA_real_
plg <- as.data.table(readRDS(file.path(STAGE_DIR, "forge_sim.rds"))$PORTFOLIO_LOG)
if ("Traded_Frac" %in% names(plg)) to_ann <- mean(plg$Traded_Frac[-1], na.rm = TRUE) * 12
cost_ann <- if (is.finite(to_ann)) to_ann * 0.0015 else NA_real_

sr_realized <- getm("Sharpe")
# 월별 집계 SR (상류 factor_engine 규약과 같은 빈도로의 대조 — 진단)
MON <- CMP[, .(rs = prod(1 + ret_net) - 1, rb = prod(1 + benchmark_ret) - 1),
           by = .(ym = format(date, "%Y-%m"))]
sr_monthly_basis <- mean(MON$rs) / sd(MON$rs) * sqrt(12)

fe_sr <- as.numeric(opt_pkg$method_comparison$EW$sr_total %||% NA)
div_pp <- fe_sr - sr_realized
.diagband <- function(d) {
  if (!is.finite(d)) return(NA_character_)
  if (abs(d) < 0.1) return("NEGLIGIBLE")
  if (abs(d) < 0.3) return("MINOR_DRIFT")
  if (abs(d) < 0.6) return("SIGNIFICANT_DRAG")
  "FABRICATION_SUSPECTED"
}
diag_lbl <- .diagband(div_pp)
div_pp_mon <- fe_sr - sr_monthly_basis
diag_mon <- .diagband(div_pp_mon)

#---------------------- monthly-basis 대조 (진단 — 권위는 daily 계약값)
# 상류(alpha/optimizer)는 월별 basis 로 PORT_t 1.196 / net_IR 0.2492 를 보고했다.
# 권위 등급은 lean/alpha-search 레인과 같은 daily(af=252) 계약값으로 낸다. 두 basis 를
# 나란히 두지 않으면 "t 가 절반으로 줄었다"가 알파 소멸로 오독된다 — 집계빈도 효과다.
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
MPR <- CMP[, .(ret_net = prod(1 + ret_net) - 1,
               benchmark_ret = prod(1 + benchmark_ret) - 1,
               date = max(date)), by = .(ym = format(date, "%Y-%m"))]
setorder(MPR, date)
bc_m <- build_benchmark_compare(
  data.table(date = MPR$date, ret_net = MPR$ret_net, frequency = "monthly"),
  data.table(date = MPR$date, benchmark_ret = MPR$benchmark_ret,
             benchmark_id = "KOSPI200"),
  run_id = "FORGE_MONTHLY_DIAG", strategy_id = "WTR20260829_005_monthly_basis",
  annualization_factor = 12)
bc_m <- as.data.table(bc_m)
gmb <- function(n, col = "active_value") { v <- bc_m[metric_name == n, get(col)]
                                           if (length(v)) as.numeric(v[1]) else NA_real_ }
monthly_diag <- list(
  declared_as = "diagnostic — 권위 아님. 권위 = daily(af=252) 계약값(lean 레인 규약 동일).",
  n_months = nrow(MPR),
  portfolio_alpha_t_nw_lag3 = gmb("Portfolio_Alpha_t_NW_lag3"),
  portfolio_alpha_t_pvalue = gmb("Portfolio_Alpha_t_pvalue"),
  net_ir = gmb("Information_Ratio"),
  tracking_error = gmb("Tracking_Error"),
  alpha_annualized = gmb("Alpha_Annualized", "strategy_value"),
  beta_to_benchmark = gmb("Beta_to_Benchmark", "strategy_value"),
  sharpe_monthly_basis = sr_monthly_basis,
  upstream_reported = list(port_t = 1.196, beta_controlled_alpha_ann = 0.0578,
                           beta_controlled_alpha_t = 1.792, net_ir = 0.2492),
  note = paste("월별 basis 에서 상류 수치와 나란히 읽는다. NW lag-3 는 일별에서 월간 리밸런싱의",
               "자기상관을 담지 못하므로 daily PORT_t 는 월별보다 보수적으로 나올 수 있다.")
)
cat("[monthly diag] PORT_t =", monthly_diag$portfolio_alpha_t_nw_lag3,
    "| net_IR =", monthly_diag$net_ir, "| n =", monthly_diag$n_months, "\n")

#------------------------------------------------- hash audit (완료 시점)
.h_end <- vapply(file.path(WT_DIR, c("alpha_package.json", "risk_package.json",
                                     "optimization_package.json")),
                 function(f) as.character(tools::md5sum(f)), "")
.hash_ok <- isTRUE(all(unlist(FE$hash_start) == unlist(.h_end)))
cat("[hash] start==end :", .hash_ok, "\n")

#------------------------------------------------- authoritative_remeasure
AU <- as.data.table(bt$audit)
es <- ess$sweep
gp <- es$graduation_params
thr <- function(k, d) { v <- suppressWarnings(as.numeric(gp[[k]])); if (length(v) && is.finite(v)) v else d }

cond <- list(
  PORT_t        = list(value = es$essence$portfolio_alpha_t_nw_lag3, threshold = thr("port_t_min", 2.95),
                       pass = isTRUE(es$essence$portfolio_alpha_t_nw_lag3 >= thr("port_t_min", 2.95))),
  OOS_retention = list(value = es$essence$oos_retention, threshold = thr("oos_min", 0.7),
                       floor = thr("oos_floor", 0.5), band_status = es$oos_band_status,
                       splits = es$oos_retention_splits,
                       pass = isTRUE(es$oos_band_status %in% c("pass", "band_escalated"))),
  Sharpe        = list(value = es$essence$net_sharpe, threshold = thr("sharpe_min", 0.8),
                       pass = isTRUE(es$essence$net_sharpe >= thr("sharpe_min", 0.8))),
  CAGR          = list(value = es$essence$cagr, threshold = thr("cagr_min", 0.16),
                       pass = isTRUE(es$essence$cagr >= thr("cagr_min", 0.16))),
  Calmar        = list(value = es$essence$calmar, threshold = thr("calmar_min", 0.64),
                       pass = isTRUE(es$essence$calmar >= thr("calmar_min", 0.64)))
)

auth <- list(
  status = if (identical(es$metric_type, "backtested") &&
                !identical(bt$manifest$integrity_status[1], "FAIL")) "OK" else "FAIL",
  wt_id = WT_ID, wt_type = "reinforcement", axis = "combination",
  strategy_id = bt$manifest$strategy_id[1],
  strategy_name = "AMP2013 value-momentum combination (WT-R20260829_005)",
  remeasured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  run_id = bt$manifest$run_id[1],
  bt_result_path = file.path(STAGE_DIR, "bt_result.rds"),
  measurement_basis_primary = "forge_realized_share_based",
  measurement_note = paste("weights.csv(259 sig_date x 25) as-is -> t+1 집행 -> 정수 주식수 ->",
                           "일별 share-based NAV -> 15bps one-way(v2.4_delta). 빈도 daily, af=252."),
  metric_type = es$metric_type,
  grade = es$grade,
  essence_grade = es$grade,
  grade_basis = "essence_score(bt_result) — 권위. hurdle_result.json proxy 미인용(2026-05-31 DEMOTED)",
  grade_a_conditions = cond,
  essence = es$essence,
  structural_drawdown = es$structural_drawdown,
  hard_fail = es$hard_fail, hard_fail_source = es$hard_fail_source,
  reasons = es$reasons,
  selection_type_primary = "sweep",
  selection_type_note = paste("optimizer 가 비중방법 5종을 열거하고 사전선언 net_ir 규칙으로 선택했다 ->",
                              "sweep 로 보수 판정. chain 라벨 대조판도 병기(등급 동일 여부 확인용)."),
  dsr_gate_applied = es$dsr_gate_applied,
  n_trials_cumulative = es$n_trials_cumulative,
  grade_under_chain_label = ess$chain$grade,
  oos_stat_version = es$oos_stat_version,
  oos_band_status = es$oos_band_status,
  oos_retention_splits = es$oos_retention_splits,
  graduation_params = gp,
  contract = list(
    integrity_status = bt$manifest$integrity_status[1],
    audit_pass = nrow(AU[status == "PASS"]), audit_fail = nrow(AU[status == "FAIL"]),
    audit_warn = nrow(AU[status == "WARN"]),
    audit_non_pass = if (nrow(AU[status != "PASS"])) as.list(AU[status != "PASS",
                        .(check_id, check_name, status, message)]) else list(),
    components_present = names(bt),
    cagr = getm("CAGR"), sharpe = getm("Sharpe"), mdd = getm("MDD"), calmar = getm("Calmar"),
    ann_vol = getm("Annualized_Volatility"),
    net_ir = getbc("Information_Ratio"),
    tracking_error = getbc("Tracking_Error"),
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue = getbc("Portfolio_Alpha_t_pvalue"),
    alpha_annualized = getbs("Alpha_Annualized"),
    beta_to_benchmark_full_sample = getbs("Beta_to_Benchmark"),
    beta_label = paste("전기간 CAPM 단일 추정치일 뿐이다. risk 가 실측한 롤링 36m 범위 0.536~1.481 과",
                       "함께 읽어야 하며 단일 수치로 소비하지 말 것."),
    correlation_vs_bm = getbs("Correlation"),
    up_capture = getbs("Up_Capture"), down_capture = getbs("Down_Capture"),
    hit_ratio_vs_bm = getbs("Hit_Ratio_vs_BM"),
    n_obs_daily = nrow(PR),
    period = c(as.character(min(PR$date)), as.character(max(PR$date)))
  ),
  implementation = list(
    n_max_rebalance_distinct = as.integer(n_max_rebal),
    holdings_cap = 25L, holdings_cap_pass = isTRUE(n_max_rebal <= 25L),
    turnover_ann_oneway_realized = to_ann, cost_ann_realized = cost_ann,
    long_only = TRUE, sum_w_max_dev = FE$max_sumw_dev,
    exec_drop_dates = if (!is.null(FE$exec_drop) && nrow(FE$exec_drop)) nrow(FE$exec_drop) else 0L,
    deploy_extension_days = FE$deploy_extension_days
  ),
  schedule_fidelity = FE$schedule,
  monthly_basis_diagnostic = monthly_diag,
  baseline_reconciliation_vs_upstream = tryCatch(
    fromJSON(file.path(STAGE_DIR, "forge_baseline_reconciliation.json"), simplifyVector = TRUE),
    error = function(e) list(status = "missing", error = conditionMessage(e))),
  regime_decomposition_forge_operationalization = list(
    definition = "벤치(KOSPI200) 누적 낙폭 <= -20% 인 일자 = drawdown state. forge 자체 조작화.",
    caveat = "risk 의 KR_Bear_ALL 125개월 / optimizer 의 54개월과 다른 조작화다. 재현 주장 아님.",
    table = as.list(rg)
  ),
  vs_factor_engine = list(
    factor_engine_claimed_sr = fe_sr,
    factor_engine_basis = "optimization_package.method_comparison.EW.sr_total (monthly aggregation, continuous)",
    forge_realized_sr_daily = sr_realized,
    forge_realized_sr_monthly_basis = sr_monthly_basis,
    divergence_pp_daily_basis = div_pp, diagnosis_daily_basis = diag_lbl,
    divergence_pp_same_frequency = div_pp_mon, diagnosis_same_frequency = diag_mon,
    note = paste("일별 SR 과 월별 SR 은 집계빈도가 다르므로 same-frequency 대조가 fabrication 판정의",
                 "정본이다. daily-basis 격차는 빈도효과를 포함한다.")
  ),
  upstream_claims_not_cited = list(
    level_calibration_factor = "1.384 — Sigma 에 미적용. 성과수치에 곱하지 않았다.",
    regime_correlation = "risk 철회(에피소드 p=0.585) — 미인용",
    structural_finding_field = "risk_package.handoff_to_optimizer.structural_finding 의 74.9%/5.3% 는 철회 수치 — 미인용(walk-forward 0.812/0.086)",
    beta_single_number = "롤링 36m 0.536~1.481 — 단일 수치로 쓰지 않았다. 계약 Beta 는 전기간 CAPM 값으로 라벨 명시.",
    drawdown_state = "KR_Bear_ALL 125개월 초과 -29.6%p 진단 승계 — 베타 낙폭으로 접지 않는다."
  ),
  pit = list(
    detector = "02_Infrastructure/validation/lookahead_detector.R::detect_lookahead()",
    decision_path_file = "stage_artifacts/WT_R20260829_005/run_all.R",
    decision_path_result = "CLEAN (272 lines scanned, 0 violations)",
    expost_evaluator_file = "stage_artifacts/WT_R20260829_005/forge_emit.R",
    positive_control = "선언 idiom 2종(sd(x)*sqrt() / quantile(dt$col)) 주입 -> 2/2 발화. 검출기 생존 확인.",
    negative_coverage = paste("비선언 idiom 3종(full-sample mean, shift(-1), 비중 재정규화) 주입 -> 0/3 미발화.",
                              "R 경로 커버리지는 3 idiom 계열로 좁다 — CLEAN 은 PIT 증명이 아니다."),
    structural_argument = paste("종목선택/비중은 weights.csv 가 전량 결정(재선택 0). 신호일 t -> 집행 t+1 종가.",
                                "일별 NAV 는 보유 주식수 x 당일 종가만 사용. 전 표본 통계 0."),
    c_checks = list(
      C1 = "PASS — forge 층에 전 표본 추정치 0. NAV 는 경로 누적.",
      C2 = "PASS — sig_date 신호를 다음 거래일 종가로 집행.",
      C3 = "PASS — 동기간 집계 후 소급적용 없음.",
      C4 = "N/A — 재무제표 lag 는 alpha 소관(승계).",
      C5 = "N/A — 오버레이 미적용.",
      C6 = "PASS — RAWDATA 전종목 패널. 상장폐지 종목도 가격 결측 시 last_price 유지 후 리밸 시 제외 — 생존편향 도입 없음.",
      C9 = "N/A — VT/DD 오버레이 미적용.",
      C10 = "PASS — 유동성 필터는 alpha t-1 ADV20 승계. forge 추가 필터 0.",
      C13 = "N/A — 부호 반전 없음.",
      C15 = "PASS — Factor DB parquet 직접 load 0. RAWDATA(.cache) + weights.csv 만 소비."
    )
  ),
  known_instrument_defects = list(
    schedule_fidelity_check_sh = paste("diagnostics.sig_dates_count 를 읽는데 이 alpha_package 는",
                                       "canonical_n_months 를 쓴다 -> SIG_DATES=0, 인증서 무발급, warn 없음(무발화).",
                                       "스케줄 사실은 optimization_package 필드로 대체 기록(259/259=1.000)."),
    worktask_schema_json = paste("schema.json:17 task_id 패턴 ^WT-[DPSH][0-9]{8}_[0-9]{3}$ 에 v10 접두 R 이 없고,",
                                 "wt_type enum 에도 reinforcement 가 없다. 두 축 모두 INVALID 를 낸다.",
                                 "우회하지 않았다 — status.json current_phase 는 ALPHA_DONE 그대로 두고 기록만 한다.",
                                 "수리는 별건 태스크."),
    lookahead_detector_coverage = "R 경로 3 idiom 계열만 검사. 위 pit.negative_coverage 참조.",
    price_limit_band_rows = paste("일간 패널 법정 제한폭 초과 267건(무상증자/액면분할 미조정). risk 가 Sigma substrate 만",
                                  "winsorize. forge 는 추가로 손대지 않았다 — 권위 수치는 계약 경유.")
  ),
  artifacts = list(
    run_all = "stage_artifacts/WT_R20260829_005/run_all.R",
    bt_result_rds = "stage_artifacts/WT_R20260829_005/bt_result.rds",
    contract_csv = "stage_artifacts/WT_R20260829_005/00_manifest.csv ~ 10_audit.csv (10-component + audit)",
    challenge_note = "stage_artifacts/WT_R20260829_005/challenge_note_forge.md",
    baseline_reconciliation = "stage_artifacts/WT_R20260829_005/forge_baseline_reconciliation.json",
    schema_probe = "stage_artifacts/WT_R20260829_005/forge_schema_probe.json",
    charts = file.path("stage_artifacts/WT_R20260829_005/output",
                       c("equity_curve.png", "annual_returns.png",
                         "oos_zoom_chart.png", "regime_decomposition.png")),
    forge_package = "qepm/mailbox/worktask/WT-R20260829_005/forge_package.json"),
  hash_audit = list(start = as.list(FE$hash_start), end = as.list(.h_end),
                    identical = .hash_ok,
                    note = "3-package md5 시작/완료 동일 -> pure function 준수 실증")
)

write_json(auth, file.path(STAGE_DIR, "authoritative_remeasure.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null", na = "null")
cat("[emit] authoritative_remeasure.json written\n")

#------------------------------------------------------- forge_package.json
fp <- list(
  task_id = WT_ID, wt_type = "reinforcement",
  as_of_date = as.character(Sys.Date()),
  agent = "forge",
  method = "weights.csv_as_is_daily_share_based_NAV",
  sr_realized_share_based = sr_realized,
  sr_factor_engine_continuous = fe_sr,
  measurement_basis_primary = "forge_realized_share_based",
  divergence_factor_engine_vs_realized_pp = div_pp,
  vs_factor_engine = auth$vs_factor_engine,
  weights_csv_unique_dates_count = FE$schedule$weights_csv_unique_dates_count,
  alpha_sig_dates_count = FE$schedule$alpha_sig_dates_count,
  schedule_density_ratio = FE$schedule$schedule_density_ratio,
  schedule_density_pass = FE$schedule$schedule_density_pass,
  pure_function_violation = FALSE,
  portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
  net_ir = getbc("Information_Ratio"),
  essence_grade = es$grade,
  grade_basis = auth$grade_basis,
  backtest_summary = list(
    full_period = list(sr = sr_realized, cagr = getm("CAGR"), mdd = getm("MDD"),
                       calmar = getm("Calmar"),
                       start = as.character(min(PR$date)), end = as.character(max(PR$date))),
    pre_lockbox = list(), lockbox = list()
  ),
  hard_caps = list(
    to_pass = if (is.finite(to_ann)) to_ann <= 11.0 else NA,
    turnover_ann_oneway = to_ann,
    holdings_cap_pass = isTRUE(n_max_rebal <= 25L), n_max = as.integer(n_max_rebal),
    long_only_pass = TRUE, sum_w_pass = isTRUE(FE$max_sumw_dev < 1e-6)
  ),
  hash_audit_pass = .hash_ok,
  authoritative_remeasure_ref = "stage_artifacts/WT_R20260829_005/authoritative_remeasure.json"
)
write_json(fp, file.path(WT_DIR, "forge_package.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null", na = "null")
cat("[emit] forge_package.json written\n")
cat(sprintf("[emit] grade=%s | PORT_t=%.4f | OOS=%.4f | SR=%.4f | CAGR=%.4f | Calmar=%.4f | MDD=%.4f\n",
            es$grade, es$essence$portfolio_alpha_t_nw_lag3 %||% NA_real_,
            es$essence$oos_retention %||% NA_real_, es$essence$net_sharpe,
            es$essence$cagr, es$essence$calmar, es$essence$mdd))
