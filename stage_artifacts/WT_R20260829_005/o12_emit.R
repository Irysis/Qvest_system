## WT-R20260829_005 Optimizer — Step D: 산출물 발행
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(jsonlite); library(arrow)})

S5  <- readRDS("stage_artifacts/WT_R20260829_005/opt_r5.rds")
S7  <- readRDS("stage_artifacts/WT_R20260829_005/opt_r7.rds")
S11 <- readRDS("stage_artifacts/WT_R20260829_005/opt_r11.rds")
ap  <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json", simplifyVector = FALSE)
rp  <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/risk_package.json", simplifyVector = FALSE)

SEL <- S11$SELECTED; res <- S7$res; sched <- S7$sched; tab <- S11$tab
LCF <- S11$LCF; d_last <- S11$d_last
W   <- copy(sched[[SEL]]$W)
A   <- S5$A
BCV <- as.data.table(read_parquet("stage_artifacts/WT_R20260829_005/benchmark_covariance.parquet"))

## ---------- weights.csv (walk-forward schedule, RF-O9) ----------
meta <- A[, .(Date, Ticker, alpha_hat, alpha_lb, confidence, score)]
WC <- merge(W, meta, by = c("Date","Ticker"), all.x = TRUE)
setorder(WC, Date, -score)
WC[, `:=`(sig_date = Date, as_of_date = as.character(d_last), method = SEL)]
out <- WC[, .(sig_date, Ticker, weight = w, as_of_date, method,
              alpha_hat = round(alpha_hat, 8), alpha_lb = round(alpha_lb, 8),
              confidence = round(confidence, 6), score = round(score, 8))]
fwrite(out, "stage_artifacts/WT_R20260829_005/weights.csv")
n_dates <- uniqueN(out$sig_date); n_sig <- uniqueN(A$Date)
cat("weights.csv rows", nrow(out), "unique sig_dates", n_dates, "/ alpha sig_dates", n_sig,
    "= density", round(n_dates/n_sig, 4), "\n")

## ---------- 제약 실증 ----------
chk <- out[, .(n = .N, sw = sum(weight), wmin = min(weight), wmax = max(weight)), by = sig_date]
cat("constraint proof: max n =", max(chk$n), "| max |Sw-1| =", max(abs(chk$sw-1)),
    "| min w =", min(chk$wmin), "| max w =", max(chk$wmax), "\n")
stopifnot(max(chk$n) <= 25, max(abs(chk$sw-1)) < 1e-9, min(chk$wmin) >= 0)

## ---------- as-of 벡터 ----------
tk <- S11$tk; w <- S11$w
bw <- setNames(BCV$bench_weight_proxy, BCV$Ticker)
tw  <- as.list(round(w, 10)); names(tw) <- tk
aw_v <- w - ifelse(is.na(bw[tk]), 0, bw[tk])
aw  <- as.list(round(aw_v, 10)); names(aw) <- tk
R_sel <- merge(sched[[SEL]]$R, S5$BM, by = "Date")
to_asof <- sched[[SEL]]$R[Date == d_last]$to
cost_ann <- res[[SEL]]$to_ann * 0.0015

mk <- function(n) { x <- res[[n]]; list(
  net_ir = round(x$net_ir,5), gross_ir = round(x$gross_ir,5),
  mean_active_net_ann = round(x$mean_act_ann,5), te_realized_ann = round(x$te_ann,5),
  turnover_ann_oneway = round(x$to_ann,4), cost_ann = round(x$to_ann*0.0015,5),
  cagr = round(x$cagr,5), mdd = round(x$mdd,5), calmar = round(x$calmar,5),
  sr_total = round(x$sr_total,5), hhi_mean = round(x$hhi,5), w_max = round(x$wmax,5),
  active_cvar95_monthly = round(x$act_cvar95,5),
  ew_fallback_months = x$fallback_n,
  disqualified = unname(tab[method==n]$dq_turnover),
  disqualify_reason = if (unname(tab[method==n]$dq_turnover)) "turnover_ann > 11.0 (Implementation Discipline hard cap)" else NULL,
  selected = (n == SEL)) }
mc <- lapply(setNames(names(res), names(res)), mk)

bd <- S11$bear_diag
bear_list <- lapply(setNames(bd$method, bd$method), function(n) {
  r <- bd[method == n]; list(bear_strat_cum = round(r$bear_strat_cum,5),
    bear_bench_cum = round(r$bear_bench_cum,5), bear_excess_pp = round(r$bear_excess_pp,5),
    bear_active_ann = round(r$bear_act_ann,5), nonbear_active_ann = round(r$norm_act_ann,5)) })
sub_list <- lapply(setNames(S11$sub$method, S11$sub$method), function(n)
  list(net_ir = round(S11$sub[method==n]$sub_net_ir,5), turnover_ann = round(S11$sub[method==n]$sub_to,4)))
to_list <- lapply(setNames(S11$tocmp$method, S11$tocmp$method), function(n) {
  r <- S11$tocmp[method==n]; list(oneway_nodrift_x12 = round(r$to_nodrift_x12,4),
    oneway_drifted_x12 = round(r$to_drift_x12,4), roundtrip_x2 = round(r$to_roundtrip_x2,4)) })
sens_list <- lapply(S11$sens, function(ww) list(hhi = round(sum(ww^2),5), w_max = round(max(ww),5),
  n_effective = round(1/sum(ww^2),2), l1_distance_to_ew = round(sum(abs(ww-1/25)),4)))

secd <- S11$sd_; sect <- as.list(round(secd$w,4)); names(sect) <- secd$Sector

pkg <- list(
  task_id = "WT-R20260829_005",
  wt_type = "reinforcement",
  agent = "optimizer-research",
  spec_version = "optimizer_v1.3 / qvest-opt-style / v10 constraints",
  as_of_date = as.character(d_last),
  deploy_cutoff = as.character(d_last),
  deploy_cutoff_note = paste0(
    "alpha 의 train/PIT cutoff 와 deploy cutoff 가 일치한다(v10 은 lockbox 미적용, alpha 가 전기간 2005-01-31~2026-07-31 을 소비). ",
    "선택된 EW 는 추정 파라미터가 없으므로 forge 는 재적합 없이 2026-07-31 이후로 규칙(상위 25종 by alpha score -> 균등)을 그대로 연장할 수 있다. ",
    "weights.csv 는 259개 sig_date 전량을 담고 frozen extension 은 하지 않았다 — 연장 시점의 신호는 alpha 소관이다."),
  upstream = list(
    alpha_package = "qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json",
    risk_package  = "qepm/mailbox/worktask/WT-R20260829_005/risk_package.json",
    alpha_modified = FALSE, risk_sigma_modified = FALSE,
    note = "alpha_vector / alpha_lower_bound / confidence 및 Sigma·노출·개별위험·꼬리 전부 read-only 소비. 재계산·재정규화·필터링 없음."),

  weights_csv_ref = "stage_artifacts/WT_R20260829_005/weights.csv",
  weights_csv_schema = "sig_date, Ticker, weight, as_of_date, method, alpha_hat, alpha_lb, confidence, score (1열 = 스케줄 날짜)",
  weights_csv_unique_dates_count = n_dates,
  alpha_sig_dates_count = n_sig,
  schedule_density_ratio = round(n_dates/n_sig, 4),
  schedule_density_pass = (n_dates/n_sig) >= 0.95,
  schedule_density_note = paste0(
    "259/259 = 1.000. 스킵 0. ★계기 주의: schedule_fidelity_check.sh 는 alpha_package.diagnostics.sig_dates_count 를 읽는데 ",
    "본 alpha_package 는 그 키 대신 canonical_n_months/n_months(=259)를 쓴다 — 훅의 fallback 체인도 이 키를 못 잡아 SIG_DATES=0 이 되고 ",
    "인증서가 자동 발급되지 않는다(차단도 아니고 warn 도 아닌 무발화). 밀도 사실은 본 필드가 보유한다. alpha_package 는 수정하지 않았다."),

  selection_objective = "net_ir",
  selection_rule_preregistered = list(
    declared_before_results = TRUE,
    primary = "net_ir = annualized IR of net-of-cost ACTIVE monthly returns, 전 259개월 walk-forward",
    cost_model = "v2.4_kr_retail_15bps one-way, delta 기반. delta = |w_t - w_{t-1}| (직전 **목표**비중 대비, 드리프트 미반영) — alpha 단계 규약을 실증 재현으로 확정(아래 baseline_reconciliation)",
    materiality_band = 0.10,
    materiality_band_rationale = "259개월에서 SE(annualized IR) ~ sqrt(1/21.6) = 0.215. 그 절반 미만 격차는 비결정으로 둔다.",
    tie_break = c("1) 낮은 연회전율", "2) 단순한 방법(EW 가 최단순)"),
    hard_disqualify = c("turnover_ann > 11.0 (도훈 mandate 2026-05-29)", "n>25 / Sw!=1 / w<0"),
    method_cap = 5,
    axis_changed_after_results = FALSE),

  baseline_reconciliation = list(
    target = "period_returns_production.csv (alpha 단계 실측 EW top-25 월별 순수익)",
    max_abs_diff = 5.27e-16, mean_abs_diff = 5.82e-17,
    turnover_ann_reproduced = 8.8198, turnover_ann_alpha_reported = 8.819768,
    conclusion = "비용·구성 규약이 alpha 와 기계적으로 동일함을 실증. 이 재현이 성립하지 않으면 아래 method 비교의 basis 가 alpha 와 어긋난다."),

  method_selected = SEL,
  method_selected_full = "EW_top25 (alpha score 상위 25종 균등, 월별 리밸런싱)",
  method_selection_reason = paste0(
    "적격 3종(EW 0.2492 / IVP 0.2497 / ALB_tilt 0.2406)의 net_IR 격차가 최대 0.0091 로 사전선언 materiality band 0.10 안이다 -> 비결정. ",
    "선언된 tie-break ①(최저 회전율)에서 EW 8.820 < ALB 8.938 < IVP 9.760 이므로 EW. ",
    "HRP(11.33)와 MinCVaR(15.64)은 회전율 hard cap 11.0 초과로 사전선언대로 실격(제약 완화 아님)."),
  method_comparison = mc,
  method_shopping_log = list(
    candidates_tried = 5L, cap = 10L, task_cap = 5L,
    posterior_default = TRUE,
    posterior_note = "DeMiguel-Garlappi-Uppal 2009 (1/N OOS 우위) + Cycle 2 실측(20~25종 broad alpha 에서 MVO/HRP/ERC/CVaR 집중이 net SR 을 낮춤)이 사전 posterior. 본 라운드는 그 posterior 를 반증하지 못했다.",
    ladder = "단순 -> 복잡: EW -> IVP(naive RP) -> HRP -> MinCVaR LP -> ALB_tilt(uncertainty-aware)",
    method_log = lapply(names(res), function(n) list(name = n, net_ir = round(res[[n]]$net_ir,5),
      turnover_ann = round(res[[n]]$to_ann,4), selected = (n==SEL),
      disqualified = unname(tab[method==n]$dq_turnover))),
    mvo_not_in_ladder = paste0(
      "walk-forward MVO 는 후보에 넣지 않았다. 이유는 사전선언한 5종 상한과 사다리 구성이며, ",
      "'risk 경계' 같은 사후 정당화가 아니다(IVP/HRP/MinCVaR 도 트레일링 2차 모멘트를 쓴다). ",
      "대신 권위 Sigma 로 as-of 민감도에서 MVO(lambda=2, long-only)를 측정했다 — n_effective 7.7 / w_max 0.261 로 ",
      "Grinold breadth 와 정면 충돌하고, 분산 가능한 몫의 상한(walk-forward 개별위험비중 8.6%)을 고려하면 방향이 불리하다."),
    parallel_exec = FALSE, n_workers = 1L),

  disqualified_methods = list(
    HRP = list(turnover_ann = round(res$HRP$to_ann,4), cap = 11.0, net_ir = round(res$HRP$net_ir,5),
               action = "실격 — 회전율 상한 완화 없음"),
    MinCVaR = list(turnover_ann = round(res$MinCVaR$to_ann,4), cap = 11.0, net_ir = round(res$MinCVaR$net_ir,5),
               action = "실격 — 회전율 상한 완화 없음",
               note = "LP 꼭짓점 해라 25종 중 소수에 몰린다(HHI 0.233 / w_max 0.882). 60개월 시나리오로 25자산 CVaR 을 푸는 것은 표본 대비 과적합이고 실측이 그것을 확인했다(net_IR -0.003).")),

  target_weights = tw,
  active_weights = aw,
  active_weights_basis = "w - bench_weight_proxy (K200 cap-w 194종, benchmark_covariance.parquet). 보유 25종 밖 벤치 종목의 음(-)액티브는 벡터에 포함하지 않았다(롱온리 25종 스코프).",
  n_names = length(tk),
  hhi = round(sum(w^2), 6),
  n_effective_names = round(1/sum(w^2), 2),
  sector_distribution = sect,
  sector_hhi = round(sum(secd$w^2), 6),
  n_effective_sectors = round(1/sum(secd$w^2), 3),
  kq150_share = round(S11$secs[mkt != "K200", sum(w)], 4),
  min_adv20_won = format(min(S11$secs$adv, na.rm = TRUE), scientific = FALSE),

  expected_active_return = round(S11$exp_act * 12, 6),
  expected_active_return_monthly = round(S11$exp_act, 8),
  expected_active_return_lower_bound = round(S11$exp_act_lb * 12, 6),
  expected_active_return_note = "w'alpha_hat (alpha_hat 자체가 벤치 대비 1M 활성수익). lower_bound = w'alpha_lb (alpha_hat - 1*SE, Liao et al. 2025 취지). 둘 다 alpha 원본 소비 — 재계산 없음.",
  expected_tracking_error = round(S11$te_ann_raw, 6),
  expected_tracking_error_calibrated = round(S11$te_ann_cal, 6),
  expected_information_ratio = round((S11$exp_act*12)/S11$te_ann_raw, 5),
  expected_information_ratio_calibrated = round((S11$exp_act*12)/S11$te_ann_cal, 5),
  realized_information_ratio_259m = round(res[[SEL]]$net_ir, 5),

  risk_metrics = list(
    sigma_source = "stage_artifacts/WT_R20260829_005/covariance.parquet (factor BOmegaB'+D, monthly, 원본 그대로 · 재추정 없음)",
    level_calibration_factor = LCF,
    level_calibration_applied_to = c("predicted_vol_ann_calibrated","tracking_error_calibrated","cvar95_parametric_calibrated"),
    level_calibration_not_applied_to = c("target_weights (스칼라배 불변)","method_comparison net_ir (실현수익 기반)"),
    predicted_vol_ann = round(S11$vol_ann_raw, 6),
    predicted_vol_ann_calibrated = round(S11$vol_ann_cal, 6),
    cvar95_parametric_monthly = round(S11$cvar95_m_raw, 6),
    cvar95_parametric_monthly_calibrated = round(S11$cvar95_m_cal, 6),
    cvar95_parametric_note = "정규 가정 CVaR = 2.0627 * sigma_m. tail_risk.json 의 excess kurtosis 3.73 / GPD xi 0.170 에서 정규 가정은 낙관적이다 — 아래 실현/EVT 값과 병기해서만 읽을 것.",
    cvar95_realized_total_monthly = round(S11$realized_cvar_total, 6),
    cvar95_realized_active_monthly = round(S11$realized_cvar_act, 6),
    es99_evt_monthly_from_risk_pkg = 0.238743,
    daily_tail_caveat = "risk 의 일별 Hill alpha 1.833 / GPD xi 0.281 은 월별(alpha 3.14 / xi 0.170)보다 두껍다. 월간 Sigma 로 산출한 위 CVaR 은 일중 꼬리를 담지 못한다 — 월 CVaR 단독으로 꼬리 예산을 잡지 말 것(risk 명시 경고 승계).",
    te_inconsistency_disclosure = paste0(
      "as-of 예측 TE(raw 0.2704 / calibrated 0.3742)가 259개월 실현 활성 TE 0.1704 보다 크다. 같은 양이 아니다 — ",
      "예측치는 2026-07-31 단일 종목집합 x 2023-06~2026-07 창 x cap-w 194종 프록시 벤치 기준이고, 실현치는 21.6년 시변 보유 x 실제 KOSPI200 TR 기준이다. ",
      "숫자를 맞추지 않고 둘 다 보고한다."),
    beta_usage = paste0(
      "beta 를 상수로 쓰지 않았다. risk walk-forward 실현 롤링36m beta 평균 1.041 · 범위 0.536~1.481 · 1 미만 창 35% · 최근12개월 0.640 ",
      "(alpha 의 전기간 단일 0.869 는 그 분포의 한 점이다). 본 최적화의 목적함수·제약 어디에도 beta 상수가 들어가지 않으므로 창 민감도가 비중에 전이되지 않는다."),
    market_variance_share_used = list(
      walk_forward_mean = 0.81208, as_of = 0.749192, random25_no_signal = 0.874,
      note = "as-of 0.749 는 인용하지 않는다(risk 정정 ①: walk-forward 평균 0.812 가 판정치). 무신호 무작위 25종 0.874 와의 격차는 0.749 대비가 아니라 0.812 대비로 읽어야 하고, 그만큼 작다."),
    diversifiable_ceiling = list(specific_variance_share_wf_mean = 0.085943,
      note = "분산으로 줄일 수 있는 몫의 상한이 8.6%(as-of 5.3% 아님). 사이징 방법론 간 격차가 net_IR 에서 0.01 미만으로 나온 것과 정합한다.")),

  turnover = round(res[[SEL]]$to_ann, 5),
  turnover_convention = "annualized one-way = mean_monthly(sum|w_t - w_{t-1}|) x 12. 직전 목표비중 대비(드리프트 미반영) — alpha 규약 재현치.",
  turnover_conventions_all = to_list,
  turnover_vs_alpha_baseline = list(alpha_reported = 8.819768, optimizer_selected = round(res[[SEL]]$to_ann,5),
    delta = round(res[[SEL]]$to_ann - 8.819768, 6),
    note = "EW 선택이므로 회전율은 alpha 기준선과 동일하다. 회전 제어를 위해 알파를 포기한 부분이 없다(교환 자체가 발생하지 않음)."),
  turnover_cap = 11.0,
  turnover_pass = res[[SEL]]$to_ann <= 11.0,
  estimated_cost = round(cost_ann, 6),
  estimated_cost_monthly_asof = round(to_asof * 0.0015, 6),
  turnover_asof_month = round(to_asof, 5),

  binding_constraints = list("max_names_25 (스케줄 전 구간에서 정확히 25 — 알파 상위 25종 절단이 상시 구속)"),
  binding_constraints_not_binding = c("long_only (EW 는 구조적으로 w>0)", "weight_bounds 상한 (v10 폐지)",
    "liquidity 2e8 (as-of 최소 ADV20 = 4.34e9, 21배 여유)", "turnover_cap 11.0 (선택안 8.82)"),
  constraint_proof = list(n_max_over_schedule = max(chk$n), sum_w_max_abs_dev = max(abs(chk$sw-1)),
    min_weight = min(chk$wmin), max_weight = max(chk$wmax), schedule_dates = n_dates,
    verified_on = "weights.csv 전 259 스케줄일 재검(요약이 아니라 전수)"),
  infeasibility_report = NULL,
  no_silent_override = list(relaxed_any_constraint = FALSE,
    note = "회전율 상한 초과 2종(HRP/MinCVaR)은 상한을 완화하지 않고 실격 처리했다. 제약은 하나도 움직이지 않았다."),

  diagnostics = list(
    drawdown_state_diagnostic = list(
      declared_as = "diagnostic (선택축 아님) — risk 정정 ② 수신 후 추가. 선택은 사전선언 net_ir 로 이미 확정됐고 바꾸지 않았다.",
      state_definition = "벤치(KOSPI200 TR) 누적 낙폭 <= -20% 인 신호월. 54 / 259 개월(20.8%).",
      state_definition_caveat = "risk 가 보고한 KR_Bear 125개월과 다른 조작화다. risk 의 정확한 상태정의를 재현했다고 주장하지 않는다 — 본 진단은 내 정의 위에서만 해석할 것.",
      by_method = bear_list,
      finding = paste0(
        "★선택안 EW 는 낙폭상태에서 벤치 대비 -1.97%p 열위(-63.3% vs -61.3%)인 반면, 실격된 MinCVaR(+4.11%p)과 밴드 내 IVP(+4.22%p)는 우위였다. ",
        "즉 위험기반 사이징의 실측 이득은 '평균'이 아니라 '낙폭상태'에 몰려 있고, 전구간 net_IR 은 정상상태 열위와 상쇄되어 무차별해진다 ",
        "(EW 정상상태 활성 +5.30%/yr vs IVP +4.45%/yr). 이것이 risk 정정 ②(낙폭상태 초과손실은 베타 밖에 있다)와 같은 방향의 독립 관측이다.")),
    subsample_2007on = list(
      declared_as = "diagnostic — 위험기반 arm 이 트레일링 24개월 미충족으로 EW 로 fallback 한 초기 24개월을 제외한 구간",
      by_method = sub_list,
      finding = "부표본에서도 EW(0.1419) >= IVP(0.1382) > ALB(0.1322) 로 순위가 뒤집히지 않는다. 전구간 결론이 fallback 구간의 인공적 동일화 때문이 아님을 확인."),
    asof_sensitivity_authoritative_sigma = list(
      declared_as = "Step 5 민감도 — 권위 Sigma 25종 부분행렬. 선택 후보 아님(walk-forward 미측정).",
      by_method = sens_list,
      ew_reference = list(hhi = round(sum(w^2),5), w_max = round(max(w),5), n_effective = 25),
      finding = paste0("MinVar/MVO 계열은 유효종목수를 25 -> 7.3~8.5 로 떨어뜨리면서 예측 연변동성을 0.3424 -> 0.301~0.306 으로 ",
        "12%p 상대 낮추는 데 그친다. 시장분산비중이 walk-forward 평균 81.2% 인 구조에서 예상되는 크기이며, ",
        "그 대가로 breadth 를 3분의 1 토막 낸다.")),
    ew_dominance_reading = paste0(
      "본 라운드의 실측 결론: 이 알파에서 사이징은 net 기여가 없다. 5종 중 어느 것도 EW 대비 net_IR 을 materiality band 밖으로 개선하지 못했고 ",
      "2종은 회전율 상한을 넘겨 실격했다. edge 는 name selection(랭크결합 상위 25종)에 있고 sizing 에는 없다 — Grinold breadth / DGU2009 / Cycle 2 교훈과 정합. ",
      "이 문장은 성과 주장이 아니라 optimizer 기여도 0 의 정직 보고다."),
    red_flags = list(
      `RF-O1_binding_ge_half_K` = list(triggered = FALSE, value = 1, threshold = 12.5),
      `RF-O2_active_lt_2x_cost` = list(triggered = FALSE, expected_active_ann = round(S11$exp_act*12,5), cost_ann_x2 = round(cost_ann*2,5)),
      `RF-O3_turnover_lt_0.02` = list(triggered = FALSE, value = round(res[[SEL]]$to_ann,4)),
      `RF-O4_dual_gt_1000` = list(triggered = FALSE, note = "선택안이 QP 해가 아니라 닫힌형(EW)이라 dual 부재. 민감도의 QP 는 활성 부등식 dual 유한."),
      `RF-O5_names_gt_25` = list(triggered = FALSE, value = max(chk$n)),
      `RF-O6_sumw_ne_1` = list(triggered = FALSE, value = max(abs(chk$sw-1))),
      `RF-O7_negative_weight` = list(triggered = FALSE, value = min(chk$wmin),
        note = "v10 에서 종목별 상한은 폐지 — 하한(w>=0)만 검사."),
      `RF-O9_single_snapshot` = list(triggered = FALSE, unique_dates = n_dates,
        note = "weights.csv 는 259개 as_of/sig_date 시계열 schedule. 단일 스냅샷 아님."),
      `RF-R1_handoff_market_share` = list(received = TRUE, walk_forward_mean = 0.81208,
        optimizer_action = paste0("롱온리·Sw=1·현금불가 구조에서 시장노출을 줄일 레버가 없다. 제약 완화(숏/현금/25종 초과)는 INV-7 로 금지이므로 제안하지 않는다. ",
          "가능한 레버(분산·회전·꼬리)를 5종으로 실측했고 net 기여가 없음을 보고한다. 오버레이는 S0/S1 금지로 미적용."))),
    pit_compliance = list(
      C1 = "PASS — 트레일링 2차 모멘트는 rolling 60개월(확장창 아님). full-sample 통계 0. 권위 Sigma(2023-06~2026-07 창)는 as-of 보고에만 쓰고 과거 스케줄에 소급하지 않았다(소급하면 그 자체가 C1 위반).",
      C2 = "PASS — sig_date t 의 비중은 Ret_1m@Date<t 만 사용. Ret_1m@Date=e 는 홀딩월 e+1 실현이므로 e<t 가 기지집합이다. 동일월 순환참조 없음.",
      C5 = "N/A — 오버레이 미적용(S0/S1 금지 준수).",
      C6 = "PASS — 종목집합은 alpha 의 월별 PIT 멤버십 상위 25종 승계. 생존편향 도입 없음.",
      C8 = "PASS — FM lambda 는 alpha 소관이며 본 단계에서 재추정하지 않았다. alpha_hat/alpha_lb 는 원본 소비.",
      C10 = "PASS — 유동성은 alpha 단계 t-1 ADV20 필터 승계. 본 단계 추가 필터 없음.",
      C11 = "PASS — 259 sig_date 전량이 alpha 패널 범위 내. 외부 시계열 추가 없음.",
      C13 = "N/A — 부호 반전/NEGATE 없음.",
      C15 = "PASS — Factor DB parquet 직접 load 없음. alpha_scores.parquet(상류 산출물) + risk parquet 만 소비.",
      lookahead_detector = "detect_lookahead() 실행 기록은 optimizer_pit_gate 필드 참조."),
    optimizer_pit_gate = list(
      tool = "02_Infrastructure/validation/lookahead_detector.R :: detect_lookahead()",
      decision_path = list(
        file = "stage_artifacts/WT_R20260829_005/o14_decision_path.R",
        provenance = "o7_methods.R 원문 행 24-142 를 손으로 다시 쓰지 않고 프로그램으로 잘라낸 것(동일 텍스트). 5개 비중규칙 + build() 전체.",
        clean = TRUE, n_violations = 0L),
      expost_evaluator = list(
        file = "stage_artifacts/WT_R20260829_005/o14_expost_evaluator.R",
        clean = FALSE, n_violations = 2L,
        flagged = c("[C1] sd(act)*sqrt(12) — net_ir 분모", "[C1] sd(act)*sqrt(12) — te_ann"),
        adjudication = paste0(
          "두 건 다 **이미 생성된** walk-forward 수익계열의 사후 성과통계(연율 IR·TE)다. 최적화 입력이 아니다. ",
          "합리화가 아니라 구조로 증명한다 — ①의사결정 경로 파일은 CLEAN(0건)이고 sd(.)*sqrt( 패턴을 아예 쓰지 않는다 ",
          "②build() 본문은 eval_sched/stats_of 를 참조하지 않는다(문자열 검색 FALSE) ",
          "③트레일링 창은 rw_dates < d 단 한 줄로 결정되며 미래 인덱스 참조가 없다. ",
          "즉 평가기가 만든 어떤 수치도 비중으로 되돌아가는 경로가 없다. 탐지기 출력을 지우거나 패턴을 우회 수정하지 않고 그대로 기록한다."),
        not_suppressed = TRUE),
      other_files = list(o5_recon = "CLEAN", o12_emit = "CLEAN", o11_diag = "1건 — 동일 사후 통계 패턴(부표본 net_IR 분모)")),
    sigma_boundary_disclosure = list(
      risk_sigma_reestimated = FALSE,
      risk_sigma_file_untouched = TRUE,
      optimizer_side_trailing_input = paste0(
        "IVP/HRP/MinCVaR 은 각 sig_date 에서 트레일링 60개월 월별 수익 표본을 썼다. 이것은 risk 의 Sigma 를 재정의한 것이 아니라, ",
        "risk 가 단일 as-of Sigma 만 발행했기 때문에 walk-forward 스케줄에 쓸 수 없어서(2005년에 2023-2026 창을 쓰면 C1 위반) ",
        "optimizer 측 PIT 트레일링 입력을 따로 만든 것이다. 원본 Sigma 는 파일도 값도 손대지 않았고 as-of 위험보고 전량이 원본에서 나온다."),
      declared_conventions = c("창 60개월 rolling · 최소 24개월",
        "관측 12개월 미만 종목의 분산 = 그 달 횡단면 중앙분산",
        "관측쌍 부족 상관 = 0(독립) 취급",
        "MinCVaR 시나리오 결측 셀 = 그 달 관측종목 횡단면 평균(시장동형 중립 대체)",
        "트레일링 24개월 미충족 시 EW fallback — 조용한 대체 아님, 월수 기록(IVP/HRP 24, MinCVaR 31, ALB 36)"),
      ledoit_wolf = "미사용 — risk 가 이 데이터에서 LW 축퇴(상관 보존율 0.000)를 실증했다. 복귀하지 않았다.",
      condition_number_not_cited_as_stability = TRUE,
      regime_correlation_not_cited = "risk 가 철회(에피소드 단위 p=0.585) — 전제로 쓰지 않았다."),
    selection_objective_note = "sharpe 단독 최대화 금지(R4 P3). net_ir 로만 선택했고 결과 확인 후 축을 바꾸지 않았다."),

  explanation = list(
    top_overweights = out[sig_date == d_last][order(-score)][1:5, Ticker],
    top_underweights = "N/A — 25종 균등이므로 종목간 상대 오버/언더가 없다. 액티브 언더웨이트는 미보유 벤치 종목 전체이며 종목별 선호가 아니다.",
    main_tradeoffs = c(
      "회전율 상한 11.0 이 HRP/MinCVaR 을 잘라냈다 — 두 방법의 낙폭상태 이득(MinCVaR +4.11%p)은 그 대가로 포기된 몫이다.",
      "사전선언 tie-break 가 IVP 대신 EW 를 골랐다. IVP 는 Calmar 0.270 vs 0.253 / MDD -51.1% vs -53.0% / 낙폭상태 +4.22%p 로 위험축이 낫지만 net_IR 격차가 +0.0005 로 밴드 안이고 회전율이 +0.94/yr 높다. 사후 축 교체는 하지 않았다.",
      "롱온리·Sw=1·현금불가에서 시장분산비중 81.2% 를 줄일 레버가 없다 — 제약 완화는 INV-7 금지이므로 제안하지 않는다.")),

  challenge_note_ref = "stage_artifacts/WT_R20260829_005/challenge_note_optimizer.md",
  method_note_ref = "stage_artifacts/WT_R20260829_005/weight_method_selected.md",
  chain_obligation_ack = "체인 완주 의무(도훈 2026-08-29). 사이징 기여 0 은 체인을 멈추는 근거가 아니다. forge 가 소비할 완전한 스케줄을 발행했다.",
  grade_declared = FALSE,
  grade_note = "등급은 essence_score.R(체인 종점) 단독 권위. 본 패키지는 등급을 선언하지 않는다.",
  boundary_selfcheck = list(alpha_reinterpreted = FALSE, new_alpha_signal_created = FALSE,
    risk_sigma_redefined = FALSE, overlay_applied = FALSE, constraint_silently_relaxed = FALSE,
    grade_declared = FALSE, wrote_outside_own_wt = FALSE),
  verdict = "optimizer_complete_sizing_adds_no_net_value"
)

json <- toJSON(pkg, auto_unbox = TRUE, pretty = TRUE, digits = 10, null = "null", na = "null")
writeLines(json, "stage_artifacts/WT_R20260829_005/optimization_package.staging.json")
cat("staging package bytes:", file.size("stage_artifacts/WT_R20260829_005/optimization_package.staging.json"), "\n")
cat("target_weights n =", length(tw), " sum =", sum(unlist(tw)), " min =", min(unlist(tw)), "\n")
saveRDS(pkg, "stage_artifacts/WT_R20260829_005/opt_pkg.rds")
