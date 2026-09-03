#==============================================================================
# WT-R20260829_006 — Forge emit: charts + authoritative_remeasure.json + forge_package.json
#   ★EX-POST EVALUATOR ONLY. 의사결정 경로 아님(결정경로 = run_all.R [5] 절).
#   여기의 sd()*sqrt() 계열은 사후 평가기이며 신호·비중 구성에 관여하지 않는다.
#==============================================================================
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(xts)})
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

WT_ID     <- "WT-R20260829_006"
WT_DIR    <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "stage_artifacts", "WT_R20260829_006")
OUT_DIR   <- file.path(STAGE_DIR, "output"); dir.create(OUT_DIR, showWarnings = FALSE)

bt  <- readRDS(file.path(STAGE_DIR, "bt_result.rds"))
ess <- readRDS(file.path(STAGE_DIR, "forge_essence.rds"))
FE  <- readRDS(file.path(STAGE_DIR, "forge_env.rds"))
opt_pkg  <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)
risk_pkg <- fromJSON(file.path(WT_DIR, "risk_package.json"), simplifyVector = FALSE)
recon <- fromJSON(file.path(STAGE_DIR, "forge_baseline_reconciliation.json"), simplifyVector = TRUE)
pitbi <- fromJSON(file.path(STAGE_DIR, "forge_pit_bidirectional.json"), simplifyVector = TRUE)

M  <- as.data.table(bt$metrics); BC <- as.data.table(bt$benchmark_compare)
getm  <- function(n) { v <- M[metric_name == n, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
getbc <- function(n) { v <- BC[metric_name == n, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
# ★build_benchmark_compare 의 active_value 는 Beta/Correlation/Capture/Hit 행에서 strategy - benchmark 다.
#   수준값은 strategy_value 를 읽어야 한다. IR/TE/PORT_t 는 본래 active 량이라 active_value 가 맞다.
getbs <- function(n) { v <- BC[metric_name == n, strategy_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }

PR <- as.data.table(bt$period_returns)[order(date)]
BR <- as.data.table(bt$benchmark_returns)[order(date)]
CMP <- merge(PR[, .(date, ret_net)], BR[, .(date, benchmark_ret)], by = "date")
setorder(CMP, date)
CMP[, nav_s := cumprod(1 + ret_net)]
CMP[, nav_b := cumprod(1 + benchmark_ret)]

TITLE <- "WT-R20260829_006 EL2022 factor-momentum spanning (EW_band40)"

#---------------------------------------------------------------- charts
png(file.path(OUT_DIR, "equity_curve.png"), width = 1400, height = 800, res = 110)
plot(CMP$date, CMP$nav_s, type = "l", log = "y", col = "#1f5fbf", lwd = 2,
     xlab = "", ylab = "Growth of 1 (log)",
     main = paste(TITLE, "\nForge realized (net, share-based) vs KOSPI200"))
lines(CMP$date, CMP$nav_b, col = "#999999", lwd = 2)
legend("topleft", c("Strategy (net, share-based)", "KOSPI200"),
       col = c("#1f5fbf", "#999999"), lwd = 2, bty = "n")
grid(); dev.off()

yr <- CMP[, .(s = prod(1 + ret_net) - 1, b = prod(1 + benchmark_ret) - 1), by = .(y = year(date))]
png(file.path(OUT_DIR, "annual_returns.png"), width = 1400, height = 800, res = 110)
barplot(t(as.matrix(yr[, .(s, b)])), beside = TRUE, names.arg = yr$y, las = 2,
        col = c("#1f5fbf", "#bbbbbb"),
        main = paste("Annual returns — Strategy (net) vs KOSPI200 —", WT_ID),
        ylab = "annual return")
abline(h = 0); legend("topright", c("Strategy", "KOSPI200"), fill = c("#1f5fbf", "#bbbbbb"), bty = "n")
dev.off()

z0 <- max(CMP$date) - 365 * 5
Z <- CMP[date >= z0]; Z[, ns := cumprod(1 + ret_net)]; Z[, nb := cumprod(1 + benchmark_ret)]
png(file.path(OUT_DIR, "oos_zoom_chart.png"), width = 1400, height = 800, res = 110)
plot(Z$date, Z$ns, type = "l", col = "#1f5fbf", lwd = 2, ylim = range(c(Z$ns, Z$nb)),
     xlab = "", ylab = "Growth of 1", main = sprintf("Recent 5Y zoom (%s ~ %s) — %s", z0, max(CMP$date), WT_ID))
lines(Z$date, Z$nb, col = "#999999", lwd = 2)
legend("topleft", c("Strategy (net)", "KOSPI200"), col = c("#1f5fbf", "#999999"), lwd = 2, bty = "n")
grid(); dev.off()

# regime decomposition — forge 자체 조작화: 벤치 누적낙폭 <= -20% 인 날 = drawdown state.
#   ★risk 의 KR_Bear 조작화와 다른 정의다(재현 주장 아님).
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
HD <- as.data.table(bt$holdings)
n_max_rebal <- HD[, uniqueN(ticker), by = date][, max(V1)]
plg <- as.data.table(readRDS(file.path(STAGE_DIR, "forge_sim.rds"))$PORTFOLIO_LOG)
to_ann <- if ("Traded_Frac" %in% names(plg)) mean(plg$Traded_Frac[-1], na.rm = TRUE) * 12 else NA_real_
cost_ann <- if (is.finite(to_ann)) to_ann * 0.0015 else NA_real_

sr_realized <- getm("Sharpe")                       # daily basis (af=252) — 권위
MON <- CMP[, .(rs = prod(1 + ret_net) - 1, rb = prod(1 + benchmark_ret) - 1),
           by = .(ym = format(date, "%Y-%m"))]
sr_monthly_basis <- mean(MON$rs) / sd(MON$rs) * sqrt(12)

# factor-engine(연속수익 집계) SR — forge 가 weighted_screen_bt 로 상류 basis 를 재현한 값.
fe_sr <- as.numeric(recon$upstream_basis_reproduce$port_t_nw3)  # placeholder overwritten below
fe_sr <- 0.57867699   # weighted_screen_bt abs_net_sr (상류 basis 재현, forge_diag_recon.R 실측)
div_pp     <- fe_sr - sr_realized
div_pp_mon <- fe_sr - sr_monthly_basis
.diagband <- function(d) {
  if (!is.finite(d)) return(NA_character_)
  if (abs(d) < 0.1) return("NEGLIGIBLE")
  if (abs(d) < 0.3) return("MINOR_DRIFT")
  if (abs(d) < 0.6) return("SIGNIFICANT_DRAG")
  "FABRICATION_SUSPECTED"
}
diag_lbl <- .diagband(div_pp); diag_mon <- .diagband(div_pp_mon)

#---------------------- monthly-basis 대조 (진단 — 권위는 daily 계약값)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
MPR <- CMP[, .(ret_net = prod(1 + ret_net) - 1,
               benchmark_ret = prod(1 + benchmark_ret) - 1,
               date = max(date)), by = .(ym = format(date, "%Y-%m"))]
setorder(MPR, date)
bc_m <- as.data.table(build_benchmark_compare(
  data.table(date = MPR$date, ret_net = MPR$ret_net, frequency = "monthly"),
  data.table(date = MPR$date, benchmark_ret = MPR$benchmark_ret, benchmark_id = "KOSPI200"),
  run_id = "FORGE_MONTHLY_DIAG", strategy_id = "WTR20260829_006_monthly_basis",
  annualization_factor = 12))
gmb <- function(n, col = "active_value") { v <- bc_m[metric_name == n, get(col)]
                                           if (length(v)) as.numeric(v[1]) else NA_real_ }
.mdd <- function(r) { cum <- cumprod(1 + r); min(cum / cummax(cum) - 1, na.rm = TRUE) }
monthly_diag <- list(
  declared_as = "diagnostic — 권위 아님. 권위 = daily(af=252) 계약값(lean/alpha-search 레인 규약 동일).",
  n_months = nrow(MPR),
  portfolio_alpha_t_nw_lag3 = gmb("Portfolio_Alpha_t_NW_lag3"),
  portfolio_alpha_t_pvalue = gmb("Portfolio_Alpha_t_pvalue"),
  net_ir = gmb("Information_Ratio"),
  tracking_error = gmb("Tracking_Error"),
  alpha_annualized = gmb("Alpha_Annualized", "strategy_value"),
  beta_to_benchmark = gmb("Beta_to_Benchmark", "strategy_value"),
  sharpe_monthly_basis = sr_monthly_basis,
  mdd_monthly_basis = .mdd(MPR$ret_net),
  mdd_daily_basis = -getm("MDD"),
  mdd_basis_note = paste("월말 basis MDD 는 일중·월중 경로를 못 본다. 권위 MDD 는 일별 경로 기준이라",
                         "상류(월별) 값보다 깊게 나오는 것이 정상이다 — 알파 악화가 아니라 해상도 차이다.",
                         "Calmar 는 이 MDD 를 분모로 쓰므로 같은 이유로 상류보다 낮다."),
  upstream_reported = list(port_t = 1.219, net_ir = 0.2987, alpha_ann = 0.0722,
                           cagr = 0.1299, mdd = -0.5341, calmar = 0.2432),
  note = paste("NW lag-3 는 일별에서 월간 리밸런싱의 자기상관을 담지 못하므로 daily PORT_t 와",
               "monthly PORT_t 는 다른 양이다. 두 basis 를 나란히 둔다."))
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
cond_pass_n <- sum(vapply(cond, function(z) isTRUE(z$pass), logical(1)))

auth <- list(
  status = if (identical(es$metric_type, "backtested") &&
                !identical(bt$manifest$integrity_status[1], "FAIL")) "OK" else "FAIL",
  wt_id = WT_ID, wt_type = "reinforcement", axis = "multifactor",
  round_label = "JT1993 강화 6/20 — 팩터 모멘텀 스패닝 검정 (Ehsani-Linnainmaa 2022)",
  strategy_id = bt$manifest$strategy_id[1],
  strategy_name = "EL2022 factor-momentum spanning — EW_band40 (WT-R20260829_006)",
  remeasured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  run_id = bt$manifest$run_id[1],
  bt_result_path = file.path(STAGE_DIR, "bt_result.rds"),
  measurement_basis_primary = "forge_realized_share_based",
  measurement_note = paste("weights.csv 역사 248 sig_date x 25종 as-is -> t+1 종가 집행 -> 정수 주식수 ->",
                           "일별 share-based NAV -> 15bps one-way(v2.4_delta). 빈도 daily, af=252.",
                           "as_of(2026-08-28) 25행은 미래 집행분이라 백테스트에서 제외했다."),
  metric_type = es$metric_type,
  grade = es$grade,
  essence_grade = es$grade,
  grade_basis = "essence_score(bt_result) — 권위. hurdle_result.json proxy 미인용(2026-05-31 DEMOTED)",
  grade_a_conditions = cond,
  grade_a_conditions_passed = cond_pass_n,
  grade_a_conditions_total = 5L,
  essence = es$essence,
  structural_drawdown = es$structural_drawdown,
  structural_drawdown_note = paste("MDD 는 어느 층에서도 등급을 접지 않는다(도훈 지시 2026-08-24).",
                                   "위험 축은 Calmar 하나. 구조 낙폭은 라벨로만 남아 오버레이 라우팅 근거가 된다."),
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
    audit_warn = nrow(AU[status == "WARN"]), audit_total = nrow(AU),
    audit_non_pass = if (nrow(AU[status != "PASS"])) as.list(AU[status != "PASS"]) else list(),
    components_present = names(bt),
    cagr = getm("CAGR"), sharpe = getm("Sharpe"), mdd = getm("MDD"), calmar = getm("Calmar"),
    ann_vol = getm("Annualized_Volatility"),
    net_ir = getbc("Information_Ratio"),
    tracking_error = getbc("Tracking_Error"),
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue = getbc("Portfolio_Alpha_t_pvalue"),
    alpha_annualized = getbs("Alpha_Annualized"),
    beta_to_benchmark_full_sample = getbs("Beta_to_Benchmark"),
    beta_label = paste("전기간 CAPM 단일 추정치. risk 가 실측한 롤링 베타 범위와 함께 읽어야 하며",
                       "단일 수치로 소비하지 말 것."),
    correlation_vs_bm = getbs("Correlation"),
    up_capture = getbs("Up_Capture"), down_capture = getbs("Down_Capture"),
    hit_ratio_vs_bm = getbs("Hit_Ratio_vs_BM"),
    n_obs_daily = nrow(PR),
    period = c(as.character(min(PR$date)), as.character(max(PR$date)))
  ),
  benchmark_basis = list(
    authoritative_benchmark = "KOSPI200 — .cache/benchmark.parquet BM_Ret (production harness BM_DT)",
    authoritative_benchmark_scope = paste("canonical_screen_bt · run_alpha_search · essence 코퍼스 공통 벤치.",
                                          "권위 등급은 이 벤치에서만 매겨진다."),
    upstream_benchmark = "alpha engine build_monthly_forward_returns bench_dt (알파 패널 구성)",
    upstream_port_t_reproduced_by_forge = recon$upstream_basis_reproduce$port_t_nw3,
    upstream_port_t_declared = 1.219,
    authoritative_port_t_daily = getbc("Portfolio_Alpha_t_NW_lag3"),
    authoritative_port_t_monthly = monthly_diag$portfolio_alpha_t_nw_lag3,
    attribution_2x2 = recon$basis_table,
    port_t_attribution = recon$port_t_attribution,
    benchmark_series_diff = recon$benchmark_series,
    strategy_series_diff = recon$strategy_series,
    reading = paste("상류 PORT_t 와 권위 PORT_t 는 **다른 양**이다 — 벤치 계열이 다르다.",
                    "실측 귀속: 상류 basis 1.2211 -> 벤치 교체 -0.3277 -> 전략실현 교체 -0.0239 ->",
                    "권위(월별 basis) 0.8695. 지배항은 5/20 과 동일하게 **벤치 계열**이다.",
                    "248개월 누적 벤치가 4.983(production) vs 3.996(alpha panel) 로 서로 다른 구성물이다."),
    verdict_invariance = recon$verdict_invariance
  ),
  upstream_residuals_reproduction = list(
    port_t = list(upstream_declared = 1.219,
                  forge_reproduced_on_upstream_basis = recon$upstream_basis_reproduce$port_t_nw3,
                  authoritative_daily = getbc("Portfolio_Alpha_t_NW_lag3"),
                  authoritative_monthly = monthly_diag$portfolio_alpha_t_nw_lag3,
                  reproduced = TRUE,
                  reading = "상류 잔여는 재현된다. 권위 basis 에서 더 낮아지지만 A 문턱 2.95 와의 거리는 어느 basis 에서도 본질적으로 같다."),
    oos_retention = list(upstream_approx = -0.458,
                         upstream_method = "anchored 3분할 {55/65/75} 중앙값 진단 근사(상류 자칭 '권위 아님')",
                         authoritative = es$essence$oos_retention,
                         authoritative_method = paste("essence_score.R", es$oos_stat_version),
                         band_status = es$oos_band_status,
                         splits = es$oos_retention_splits,
                         reproduced_sign = TRUE,
                         reading = paste("부호(음수)는 재현된다. 크기는 권위 산식에서 더 나쁘다",
                                         "(-0.458 -> ", round(es$essence$oos_retention, 4), ").",
                                         "OOS 소멸이 이 후보의 구속 축이다.")),
    subperiod_ir = recon$subperiod_ir,
    subperiod_reading = paste("2020+ 부기간 IR 이 권위 basis 에서도 음수(-0.369)로 재현된다.",
                              "회전 제어는 감쇠를 완화만 했다는 상류 진술과 정합.")
  ),
  implementation = list(
    n_max_rebalance_distinct = as.integer(n_max_rebal),
    holdings_cap = 25L, holdings_cap_pass = isTRUE(n_max_rebal <= 25L),
    turnover_ann_oneway_realized = to_ann,
    turnover_upstream_declared = 8.739,
    turnover_cap = 11.0, turnover_pass = isTRUE(is.finite(to_ann) && to_ann <= 11.0),
    cost_ann_realized = cost_ann,
    long_only = TRUE, sum_w_max_dev = FE$max_sumw_dev, max_weight = FE$max_w,
    weight_cap_policy = "v10 — 종목별 비중 상한 폐지. Σw=1 · w>=0 · <=25종만 강제.",
    exec_drop_dates = if (!is.null(FE$exec_drop) && length(FE$exec_drop) && nrow(FE$exec_drop)) nrow(FE$exec_drop) else 0L,
    deploy_extension_days = FE$deploy_extension_days,
    deploy_extension_note = paste("마지막 리밸(2026-07-31 신호 -> t+1 집행) 이후 보유 동결 상태로",
                                  FE$deploy_extension_days, "거래일을 2026-08-28 까지 연장 측정했다.")
  ),
  schedule_fidelity = FE$schedule,
  as_of_handling = list(
    as_of_date = "2026-08-28",
    as_of_rows = FE$as_of_rows_excluded,
    excluded_from_backtest = TRUE,
    reason = "as_of 비중은 다음 리밸까지 frozen 인 미래 집행분 — 실현수익이 존재하지 않는다.",
    history_rebalances_used = FE$schedule$weights_csv_history_dates_count
  ),
  monthly_basis_diagnostic = monthly_diag,
  regime_decomposition_forge_operationalization = list(
    definition = "벤치(KOSPI200) 누적 낙폭 <= -20% 인 일자 = drawdown state. forge 자체 조작화.",
    caveat = "risk / optimizer 의 국면 조작화와 다르다. 재현 주장 아님.",
    table = as.list(rg)
  ),
  vs_factor_engine = list(
    factor_engine_claimed_sr = fe_sr,
    factor_engine_basis = paste("weighted_screen_bt(weights.csv as-is, alpha 패널 forward 수익/벤치)로",
                                "forge 가 재현한 상류 연속수익 basis SR (monthly aggregation)."),
    forge_realized_sr_daily = sr_realized,
    forge_realized_sr_monthly_basis = sr_monthly_basis,
    divergence_pp_daily_basis = div_pp, diagnosis_daily_basis = diag_lbl,
    divergence_pp_same_frequency = div_pp_mon, diagnosis_same_frequency = diag_mon,
    note = paste("same-frequency 대조가 fabrication 판정의 정본이다. daily-basis 격차는 집계빈도 효과를 포함한다.")
  ),
  upstream_claims_carried_as_labels_not_metrics = list(
    momentum_exposure = paste("x_f_momentum 이 밴드로 오히려 상승(+0.187 -> +0.226 sigma, as_of +0.615).",
                              "결함이 아니라 설계 산물 — EL2022 가설이 개별주 모멘텀을 팩터 모멘텀의 그림자로",
                              "보므로 x_mom 을 0 으로 묶으면 검정 대상 자체가 사라진다.",
                              "중립화 가격 실측: net -0.83%/yr, t -0.615, 회전 8.74 -> 11.45."),
    tail = paste("t(5)/GPD 인용. VaR1 0.2058(실측) / t5 0.2120 / GPD xi 0.0094 VaR99 0.2218 ES99 0.2894.",
                 "정규-Sigma 0.1892 는 8% 과소. Hill alpha 1.721 < 2 — 유한분산 경계 아래.",
                 "forge 는 이 수치를 재계산하지 않고 라벨로 승계한다."),
    crowding = "판정 불가 — composite 구조 상한 0.7345 < 문턱 0.75 라 원리적으로 발화 불가. '군집 없음'으로 읽지 않는다.",
    stress = "risk 스트레스 6구간 커버리지 <85% (UNRELIABLE) — hard-fail 근거로 쓰지 않았다.",
    market_exposure = "RF-R1 시장 노출 68.8% 는 long-only + Σw=1 + 25종 하에서 optimizer 층이 닫을 수 없어 오버레이 층으로 이월. forge 는 오버레이 미적용(S0/S1 금지 준수).",
    band_width = "B=40 은 사전 고정. forge 도 B 를 바꾸지 않았다(사후 최적화 금지 준수).",
    turnover_tradeoff = paste("실증 명제는 '회전을 27% 줄여도 알파가 깎이는 증거가 없다'이지",
                              "'회전 제어가 알파를 만든다'가 아니다. 비용 절감 0.486%p 만 회계적으로 확정이고",
                              "gross +0.476%p 는 t 0.438 로 0 과 구별되지 않는다.")
  ),
  pit = list(
    detector = pitbi$detector,
    decision_path_file = "stage_artifacts/WT_R20260829_006/run_all.R",
    decision_path_result = sprintf("CLEAN (318 lines scanned, %s violations)", pitbi$baseline_violations),
    expost_evaluator_files = c("stage_artifacts/WT_R20260829_006/forge_emit.R",
                               "stage_artifacts/WT_R20260829_006/forge_diag_recon.R"),
    bidirectional_control = list(
      positive_control = pitbi$positive_control,
      negative_coverage = pitbi$negative_coverage,
      verdict = paste("양성 1/3 · 음성 0/5. 검출기는 살아 있으나 커버리지가 **선언 idiom 중",
                      "sd()*sqrt() 계열 한 갈래**로 좁다 — quantile()·scale() 주입도 미발화했다.",
                      "5/20 forge 가 기록한 '선언 idiom 2/2 발화'보다 좁게 측정됐다.",
                      "따라서 CLEAN 은 PIT 증명이 아니며, 실제 논거는 아래 structural_argument 다.")
    ),
    structural_argument = pitbi$structural_argument,
    structural_argument_reading = paste(
      "① 종목선택·비중을 forge 가 만들지 않는다 — 집행 6,200 (date,ticker) 쌍이 weights.csv 의",
      "6,200 쌍과 완전 일치(초과 0). ② 신호 t -> 집행 t+1: exec-sig 간격 최소 1일·최대 11일,",
      "0 이하 0건. ③ 전 표본 통계 0 — 일별 NAV 는 보유 주식수 x 당일 종가의 경로 누적.",
      "④ 재선택 패턴 부재 — run_all.R 의 'alpha_scores' 1회는 금지 주석이고 setorder 2회는",
      "(Date,-w,Ticker) 와 (nav,Date) 정렬로 score 기반 top-N 이 아니며 head() 0회."),
    c_checks = list(
      C1 = "PASS — forge 층에 전 표본 추정치 0. NAV 는 경로 누적.",
      C2 = "PASS — sig_date 신호를 다음 거래일 종가로 집행(간격 >=1일).",
      C3 = "PASS — 동기간 집계 후 소급적용 없음.",
      C4 = "N/A — 재무제표 lag 는 alpha 소관(승계).",
      C5 = "N/A — 오버레이 미적용.",
      C6 = "PASS — RAWDATA 전종목 패널 + alpha 월별 PIT 멤버십 승계. 생존편향 도입 없음.",
      C7 = "PASS — 검출기 정적 스캔 CLEAN(단 커버리지 한계 위 기록).",
      C8 = "N/A — FM weight 미사용.",
      C9 = "N/A — VT/DD 오버레이 미적용.",
      C10 = "PASS — 유동성 필터는 alpha t-1 ADV20 승계. forge 추가 필터 0.",
      C11 = "N/A — 외부 매크로 미사용.",
      C13 = "N/A — 부호 반전 없음.",
      C14 = "N/A — IC 재계산 없음.",
      C15 = "PASS — Factor DB parquet 직접 load 0 (audit Check 14 실측: lmf=0/align=0 hits)."
    )
  ),
  self_adversarial_challenge = list(
    performed = TRUE, items = 10L, note_ref = "stage_artifacts/WT_R20260829_006/challenge_note_forge.md",
    escalate_to_qlead = FALSE,
    escalate_reason = "Hard Constraint 위반 0 · fabrication 신호 0 · 미해결 HIGH 3건 전부 판정 불변",
    unresolved_high = list(
      F01_detector_coverage = paste("detect_lookahead 양방향 대조 양성 1/3 · 음성 0/5 —",
                                    "CLEAN 은 PIT 증명이 아니다. 논거는 구조."),
      F02_dsr_trial_count = paste("n_trials_cumulative=5 는 optimizer 내부 열거만 센다.",
                                  "본 건은 JT1993 강화 6/20 이므로 사다리 누적 시행은 최소 6라운드 x 내부 열거.",
                                  "DSR 0.436 은 낙관 방향. ★판정 불변 — PORT_t 1.002 가 B 문턱 2.0 에도 미달이라",
                                  "등급은 시행수 가정과 무관하게 C."),
      F04_benchmark_basis = paste("상류 PORT_t 1.221 과 권위 1.002 는 다른 양(벤치 계열).",
                                  "혼동 시 알파 소멸로 오독된다. 네 basis 전부 B 문턱 미만이라 등급 불변.")),
    accepted_medium = list(
      F03_turnover_realization = paste("실현 회전 9.386 > 상류 선언 8.739 (+7.4%). 정수 주식수·비중 표류·",
                                       "라운딩 탓. 실격게이트 11.0 은 실현치에서도 통과 — 선택 불변.",
                                       "단 '회전 27% 감축'·'비용 -0.486%p' 는 연속 규약 값이며 실현 basis 에서는 축소된다."),
      F06_deploy_extension = "18거래일 — OOS 주장을 지탱하지 못한다. OOS 증거로 인용 금지.",
      F09_as_of_unmeasured = paste("as_of book(2026-08-28, 모멘텀 노출 +0.615σ)은 한 번도 측정되지 않았다.",
                                   "역사 248개월의 성질을 as_of book 에 전이하지 말 것."),
      F08_sr_provenance_self_reference = paste("optimizer 가 SR 을 선언하지 않아 factor_engine SR 은 forge 가",
                                               "weighted_screen_bt 로 재현한 값이다. divergence 는 '두 집행 규약' 대조이지",
                                               "'두 독립 계열' 대조가 아니다. 상류 PORT_t 1.219 -> 1.2211 재현으로 검증력 보강."))
  ),
  known_instrument_defects = list(
    worktask_schema_json = paste("schema.json:17 task_id 정규식 ^WT-[DPSH][0-9]{8}_[0-9]{3}$ 에 v10 접두 'R' 이",
                                 "없고(실측 match=FALSE) wt_type enum 에 'reinforcement' 가 없다(실측 FALSE).",
                                 "우회하지 않았다 — 내용 기반 검증(10-component · audit 19 · essence)은",
                                 "그대로 완주했고 사실만 기록한다. 수리는 별건 태스크.",
                                 "증거: stage_artifacts/WT_R20260829_006/forge_schema_probe.json"),
    wt_validate_package_no_forge_branch = paste("wt_validate_package(WT, 'forge_package') = valid TRUE 인데,",
                                 "그 함수의 switch 에는 forge 분기가 **아예 없어** required_fields=character(0) 다",
                                 "— 내용 무관 무조건 TRUE. 통과가 아니라 검사 부재다.",
                                 "5/20 이 'required 필드만 봐서 valid=TRUE' 로 적은 것보다 한 단계 더 비어 있다.",
                                 "실질 검증은 schema.json forge_package 정의의 required 10필드를 forge 가",
                                 "직접 대조해 수행했다(missing = 0). 부수 발견: wt_list 정규식",
                                 "^WT-?[DP]?[0-9]{8}_[0-9]{3}$ 도 WT-R 을 못 본다."),
    schedule_fidelity_check_sh = paste(".claude/settings.json 미등록(무발화) + 필드명 불일치",
                                       "(sig_dates_count vs canonical_n_months). 방어선으로 세지 않고",
                                       "밀도를 산출물에서 직접 재도출했다 — 248/248 = 1.000."),
    audit_check16_vacuous = paste("Check 16(nav_cadence_label_consistency)은 manifest$frequency 가",
                                  "strategy_spec$rebalance_frequency('monthly')에서 채워지므로",
                                  "월간 리밸 전략에서는 daily-라벨 검사가 **원리적으로 발화하지 않는다**.",
                                  "여기 PASS 는 공허 PASS 다. 실질 증거는 직접 재도출: nav 중앙 간격 1.0일 ·",
                                  "5,091 일별 관측 · af=252."),
    audit_check13_regex = paste("Check 13 정규식은 't+1'/'t1' 만 인식해서 'month_end_signal_t_plus_1'",
                                "표기로는 skip(공허 PASS)이 된다. execution_date_rule 에 'T+1' 을",
                                "명시해 실제로 발화시켰고(sample 1건 entry_date >= date),",
                                "부족한 표본 크기는 structural_argument 의 248건 간격 실측으로 보강했다."),
    lookahead_detector_coverage = "위 pit.bidirectional_control 참조 — 양성 1/3 · 음성 0/5."
  ),
  artifacts = list(
    run_all = "stage_artifacts/WT_R20260829_006/run_all.R",
    bt_result_rds = "stage_artifacts/WT_R20260829_006/bt_result.rds",
    contract_csv = "stage_artifacts/WT_R20260829_006/00_manifest.csv ~ 10_audit.csv (10-component + audit)",
    baseline_reconciliation = "stage_artifacts/WT_R20260829_006/forge_baseline_reconciliation.json",
    schema_probe = "stage_artifacts/WT_R20260829_006/forge_schema_probe.json",
    pit_bidirectional = "stage_artifacts/WT_R20260829_006/forge_pit_bidirectional.json",
    challenge_note = "stage_artifacts/WT_R20260829_006/challenge_note_forge.md",
    charts = file.path("stage_artifacts/WT_R20260829_006/output",
                       c("equity_curve.png", "annual_returns.png",
                         "oos_zoom_chart.png", "regime_decomposition.png")),
    forge_package = "qepm/mailbox/worktask/WT-R20260829_006/forge_package.json"),
  hash_audit = list(start = as.list(FE$hash_start), end = as.list(.h_end), identical = .hash_ok,
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
  weights_csv_unique_dates_count = FE$schedule$weights_csv_unique_dates_total,
  weights_csv_history_dates_count = FE$schedule$weights_csv_history_dates_count,
  alpha_sig_dates_count = FE$schedule$alpha_sig_dates_count,
  schedule_density_ratio = FE$schedule$schedule_density_ratio_forge_recomputed,
  schedule_density_pass = isTRUE(FE$schedule$match),
  pure_function_violation = FALSE,
  portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
  net_ir = getbc("Information_Ratio"),
  essence_grade = es$grade,
  grade_basis = auth$grade_basis,
  grade_a_conditions_passed = cond_pass_n,
  backtest_summary = list(
    full_period = list(sr = sr_realized, cagr = getm("CAGR"), mdd = getm("MDD"),
                       calmar = getm("Calmar"),
                       start = as.character(min(PR$date)), end = as.character(max(PR$date)))),
  hard_caps = list(
    to_pass = if (is.finite(to_ann)) to_ann <= 11.0 else NA,
    turnover_ann_oneway = to_ann,
    holdings_cap_pass = isTRUE(n_max_rebal <= 25L), n_max = as.integer(n_max_rebal),
    long_only_pass = TRUE, sum_w_pass = isTRUE(FE$max_sumw_dev < 1e-6)),
  hash_audit_pass = .hash_ok,
  judge_ready = FALSE,
  judge_ready_reason = "Judge 는 essence Grade A 확정 후에만 스폰된다 — 현 등급 C.",
  authoritative_remeasure_ref = "stage_artifacts/WT_R20260829_006/authoritative_remeasure.json"
)
write_json(fp, file.path(WT_DIR, "forge_package.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, null = "null", na = "null")
cat("[emit] forge_package.json written\n")
cat(sprintf("[emit] grade=%s | PORT_t=%.4f | OOS=%.4f | SR=%.4f | CAGR=%.4f | Calmar=%.4f | MDD=%.4f | TO=%.3f\n",
            es$grade, es$essence$portfolio_alpha_t_nw_lag3 %||% NA_real_,
            es$essence$oos_retention %||% NA_real_, es$essence$net_sharpe,
            es$essence$cagr, es$essence$calmar, es$essence$mdd, to_ann))
