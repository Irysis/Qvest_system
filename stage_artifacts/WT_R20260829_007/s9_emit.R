# S9 — alpha_validation.json + alpha_package.json (AST v1.1) + lineage
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_007")
rj <- function(f) fromJSON(file.path(OUT, f), simplifyVector = FALSE)
S1 <- rj("s1_panel.json"); S2 <- rj("s2_power.json"); S3 <- rj("s3_primary_fm.json")
S4 <- rj("s4_confound.json"); S4b <- rj("s4b_reattribution.json"); S4c <- rj("s4c_prior_returnpath.json")
S4d <- rj("s4d_universe_reattribution.json"); S5 <- rj("s5_production.json"); S6 <- rj("s6_side.json")
S7 <- rj("s7_pit.json"); S8 <- rj("s8_alpha_meta.json")
S5b <- rj("s5b_strict_pit.json"); S5c <- rj("s5c_strict_mf.json"); S11 <- rj("s11_adversarial.json")
HYP <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
O8 <- readRDS(file.path(OUT, "s8_objects.rds")); O5 <- readRDS(file.path(OUT, "s5_objects.rds"))
O5b <- readRDS(file.path(OUT, "s5b_objects.rds"))
num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)

## ★발행 사양 = strict-PIT (S5b 판정). same-close 판은 A/B 대조로만 남는다.
STR <- S5b$ab$strict_pit_t_minus_1
M <- list(portfolio_alpha_t_nw_lag3 = STR$port_t,
          portfolio_alpha_t_pvalue = { v <- O5b$cs_s$portfolio_alpha_t_pvalue; if (is.null(v)) NA_real_ else as.numeric(v) },
          beta_controlled = STR$beta_controlled,
          turnover_annual_measured = STR$turnover_annual,
          net_sr_active = STR$net_sr, mean_active_net_ann = STR$active_ann,
          n_names_max = STR$n_names_max, n_names_median = STR$n_names_median,
          selected_ret_coverage = STR$selected_ret_coverage,
          diag_ew_universe = STR$diag_ew_universe, diag_cap_tier = STR$diag_cap_tier,
          liq_ruler = "adv20_t1")
ADV <- c(S5b$strict_advisory, S5c[c("post_neutralization_ic","post_neutralization_retention",
                                    "monotonicity_spearman","decile_ann_returns")])
F1 <- S3$F1_market_internal_M06_252d

## ══ 선행 런 좌표 공개 (mandatory_prior_run_disclosure) ══════════════════════
prior_disclosure <- list(
  mandated_by = "Q-Lead 착수 지시 (2026-08-29) — 선행 런 좌표를 그대로 실을 것",
  prior_run = list(
    strategy_id = "STR_AS_20260612_132740_321992", title = "52-Week High Anchor Momentum",
    date = "2026-06-12", lane = "alpha_search",
    essence_grade_regraded_20260824 = "C", portfolio_alpha_t_nw_lag3 = 0.303,
    oos_retention = -1.131, calmar = 0.188, mdd = 0.644, cagr = 0.121, sharpe = 0.671,
    turnover_annual_pct = 664, ff3_alpha_annual_pct = 3.46, ff3_alpha_t = 1.178,
    carhart4_alpha_annual_pct = 0.71, carhart4_alpha_t = 0.275,
    fmb_score_lambda = 0.00494, fmb_score_t_nw = 3.199,
    fmb_momentum_t_nw = -1.886, fmb_size_t_nw = -3.225,
    rank_ic_mean = 0.0403, icir = 0.295,
    engine = "02_Infrastructure/alpha_search/fe_mom52w.R",
    analyzer = "02_Infrastructure/strategy_analyzer.R"),
  dist_ar_041_category_judgment = list(
    verdict = "belongs_to_category (설계 승계 — 재해석 없음)",
    note = "M06 은 100% 가격-파생이며 DIST-AR-041 의 저EV 근거는 기전이 아니라 소비면 전이 실패의 반복 실측이다. 본 라운드가 그 판정을 뒤집을 증거를 만들지 못했다."),
  gh2004_expectation_lowering = list(
    self_financing_74pct_in_short_leg = TRUE,
    winner_leg_does_not_beat_JT_in_raw = "GH2004 raw: 52wh winner +0.16%/월 (t 3.06) vs JT winner +0.17%/월 (t 2.07)",
    kr_measured_here = list(
      FHH = num(F1$coefficients$FHH$mean_monthly), FHH_nw_t = num(F1$coefficients$FHH$nw_t),
      FHL = num(F1$coefficients$FHL$mean_monthly), FHL_nw_t = num(F1$coefficients$FHL$nw_t),
      short_leg_share_of_spread = abs(num(F1$coefficients$FHL$mean_monthly)) /
        (abs(num(F1$coefficients$FHH$mean_monthly)) + abs(num(F1$coefficients$FHL$mean_monthly))),
      reading = "KR 에서 숏 레그 편중은 미국(74%)보다 더 심하다. 롱온리에서 수확 가능한 부분이 더 작다.")),
  self_declared_repackaging_verdict = list(
    question = "결과가 선행 런과 사실상 같으면 재포장으로 자기신고하라.",
    answer = "PARTIAL_REPACKAGING — 소비면 결론은 같고, 진단 층은 새롭다.",
    what_is_the_same = c(
      "소비면(top-25 롱온리) 판정: 선행 PORT_t 0.303 / 본 라운드 발행판(strict) 0.929 · A/B판(same-close) 0.703 — 셋 다 2.95 에 한참 못 미친다.",
      "OOS 붕괴: 선행 oos_retention -1.131 / 본 라운드 -0.383 — 둘 다 0.5 하한 미만 무조건 FAIL 구간. 부기간도 같은 형태다(2020~2026 활성 -4.71%/yr).",
      "고회전 체질: 선행 664%/yr(편도 관행) / 본 라운드 편도 환산 762%/yr.",
      "신호 정체: 본 라운드 발행 신호와 등재 M06_High_52w 의 월별 Spearman = 0.986 (same-close 판은 1.0000) — 동일 대상이다.",
      "★모멘텀 팩터 흡수도 같다: 선행 FF3 3.46 -> Carhart4 0.71 / 본 라운드(라벨 정렬 후) FF3 7.76 -> Carhart4 3.87, WML 로딩 0.473."),
    what_is_new = c(
      "★선행 런의 FM Score NW-t +3.199 가 **mandate 유니버스에서 측정된 적이 없음**을 실측으로 확정했다 — 그 회귀의 월평균 단면 N = 1397.7(analysis_fmb.csv) 로 K200 union KQ150(월중앙 340)이 아니라 전 시장이었다. 같은 사양·같은 정의·같은 NW 공식을 유니버스만 mandate 로 좁히면 t = -0.090 이다(S4d U3).",
      "GH2004 Table V 9변수 회귀의 KR 최초 이식(F1) — 근접도 winner 더미는 비유의(t +0.910), loser 더미만 유의(t -2.616).",
      "GH2004 Table VI 장기 무반전(F2)의 KR 최초 실측 — 근접도는 k=12~48 전 구간 무반전이고 JT 모멘텀만 반전한다(k=12 t -2.01, k=48 t -2.87). anchoring 과 수익률 외삽의 분기점이 KR 에서 재현됐다.",
      "GK2001 주체 증거(F3)의 KR 최초 실측 — 근접도 상위 코호트에서 개인 순매수가 유의 음(-0.51%/월·시총대비, t -21.4)이고 기관·외국인이 그 거울상이다.",
      "L-family/변동성/산업모멘텀 통제 사다리(F4) — 통제 후 신호 소멸(t +0.877 -> +0.097).",
      "누출 귀무가 신호를 넘는다 — L11_Kyle_Lambda +2.557 / D35_RealVol_63d +2.111 / rv63 -2.118 vs 신호 자신 +1.541."))
)

## ══ 사전등록 판정 ══════════════════════════════════════════════════════════
verdicts <- list(
  F1_primary_cross_sectional = list(
    tier = "primary_cross_sectional_statistic",
    envelope_applicability = "NOT_APPLICABLE — 단면 회귀 계수 검정. 실투형 envelope 미적용. 포트폴리오 판정 아님.",
    preregistered_statement = HYP$selected$falsification$primary_preregistered$observable,
    reject_if_1 = HYP$selected$falsification$primary_preregistered$reject_if,
    measured_primary_spec = "시장-내(K200 내부 / KQ150 내부) 랭킹 · M06 252d 규약 · j=2..7 (1개월 skip) · n=259월 · 1554 단면회귀",
    FHH = F1$coefficients$FHH, FHL = F1$coefficients$FHL,
    JH = F1$coefficients$JH, JL = F1$coefficients$JL,
    MH = F1$coefficients$MH, ML = F1$coefficients$ML,
    spreads = F1$spreads,
    reject_if_1_fired = S3$preregistered_verdict$reject_if_1_fired,
    reject_if_2_fired = S3$preregistered_verdict$reject_if_2_fired,
    convention_robustness = list(
      GH2004_12month_convention = S3$F1_market_internal_GH_12m$coefficients$FHH,
      pooled_ranking = S3$F1_pooled_M06_252d$coefficients$FHH,
      reading = "규약(252 거래일 vs 12 캘린더월)과 랭킹 모드(혼합 vs 시장-내)를 바꿔도 FHH 는 +0.85 ~ +0.99 로 비유의다 — 판정이 규약 선택의 산물이 아니다."),
    verdict = "REJECTED_AS_PREREGISTERED (reject_if 1 발동) — 롱온리 관련 반쪽인 FHH 는 KR 에서 유의하지 않다(+0.095%/월, NW-t +0.910). 동시에 GH2004 의 비대칭이 KR 에서 더 강하게 재현됐다: FHL -0.310%/월 (t -2.616) 로 효과가 숏 레그에 몰려 있다.",
    dominance_reading = "(FHH-FHL) = +0.404%/월 (t +2.114) 이 (JH-JL) = +0.084%/월 (t +0.458) 보다 크다 — GH2004 의 '지배' 주장 자체는 KR 에서도 방향이 맞다. 그러나 이 값은 숏 레그를 포함하므로 reference_only_not_verdict_bearing 이며, 두 스프레드 차의 NW-t 는 2 미만이라 통계적 지배는 미확정이다.",
    labeling_constraint = HYP$selected$falsification$primary_preregistered$labeling_constraint),

  F4_confound_rejection = list(
    tier = "confound_rejection_mandatory",
    preregistered_statement = HYP$selected$falsification$side_observations[[3]]$observable,
    reject_if = HYP$selected$falsification$side_observations[[3]]$reject_if,
    ladder_market_internal = lapply(S4$ladder_market_internal, function(x)
      list(step = x$step, controls = x$controls, lambda_monthly = x$signal_lambda_monthly,
           lambda_ann_pct = x$signal_lambda_ann_pct, nw_t = x$signal_nw_t)),
    ladder_pooled = lapply(S4$ladder_pooled, function(x)
      list(step = x$step, lambda_monthly = x$signal_lambda_monthly, nw_t = x$signal_nw_t)),
    before_after = list(t_no_control = num(S4$verdict$t_no_control),
                        t_after_Lfamily_vol = num(S4$verdict$t_after_Lfamily_vol),
                        t_full_spec = num(S4$verdict$t_full_spec),
                        reading = "통제 전 +0.877 -> L-family+변동성 후 +1.096 -> 전 통제(D35+M17 포함) 후 +0.097. 신호는 통제로 죽기 전에 이미 유의하지 않았다."),
    leakage_null_by_axis = S4$leakage_null_by_axis,
    leakage_null_verdict = "★누출 귀무 3축(L11_Kyle_Lambda +2.557 · D35_RealVol_63d +2.111 · rv63 -2.118)이 신호 자신(+1.541)을 넘는다. 승자 단면을 실제로 가르는 축은 근접도가 아니라 변동성/가격충격 계열이다.",
    orthogonality_cutplane = list(
      raw = S4$orthogonalized$raw, rank = S4$orthogonalized$rank,
      reading = "직교화 후 전 구간 Spearman 은 rv +0.025 / amihud +0.016 / size -0.005 로 사실상 0 이지만, 절단면(십분위) 양끝/중앙 비율은 rv63 1.1123 로 1 에서 벗어난다 — 통제축이 절단면 위에서 일부 되살아난다. 규약(raw/rank) 두 판이 거의 동일해 '변환 규약 갈림' 은 이 축에서 발생하지 않았다.",
      label = "VOL_INDEPENDENCE_UNPROVEN — 단, 여기서는 '증명 안 된 독립성' 이자 동시에 '분리할 유의 신호 부재' 다."),
    market_dummy_artifact = S4$market_dummy_artifact_check,
    market_dummy_verdict = "혼합 랭킹 z 는 KQ150 더미와 rho -0.165 로 시장 축에 오염돼 있고(상위 30% KQ 비중 25.9% vs 하위 30% 41.1%), 시장-내 랭킹이 그것을 정확히 0 으로 제거한다. 다만 3/20 과 달리 이 오염이 '유의' 를 만들어내지는 않았다 — 두 모드 모두 FHH 비유의.",
    positive_control = list(
      own_signal_vs_registry_M06 = S4$parity_own_signal_vs_factordb_M06,
      reading = "자체 산출 fh252 와 등재 M06_High_52w 의 월별 |Spearman| = 1.0000 (전 259월, 최솟값도 1.0000). 신호 산출 경로에 결함이 없음을 등재 팩터로 교차확인했다."),
    verdict = "CONFOUND_NOT_SEPARABLE — 통제 전 신호가 이미 비유의하므로 '통제 후 소멸' 을 물을 대상이 없다. 실측된 것은 ①근접도의 KR 예측력 자체가 롱온리 반쪽에서 부재 ②승자 단면을 가르는 축은 변동성/가격충격 계열 ③시장 더미 오염은 존재하나 판정을 만들지는 않았다."),

  F4b_prior_run_reattribution = list(
    tier = "reattribution_of_inhouse_positive_observation",
    question = "선행 런의 FM Score NW-t +3.199 는 무엇이었나.",
    axis_1_definition = S4b$definition_discrepancy,
    axis_1_verdict = "정의 축 기각 — 선행 정의(Close/직전252일최고 - 1, 당일 제외)와 GH2004 정의(Close/당일포함252일최고)의 월별 Spearman = 0.9995. 순위 동치이므로 정의는 원인이 아니다.",
    axis_2_spec = S4b$reattribution_grid,
    axis_2_verdict = "사양 축 기각 — 선행 FM 사양(raw-sd z · 12개월 무skip 모멘텀 통제 · L=floor(T^(1/3)) NW)을 그대로 써도 본 라운드 표본에서 t = +0.032(선행 정의) / +0.050(GH2004 정의).",
    axis_3_return_path = S4c$grid,
    axis_3_verdict = "수익 경로 축 기각 — 선행 방식(일간 Ret 복리, 월간 방화벽 없음)으로 종속변수를 재구성해도 t = -0.393. 두 수익 경로의 상관 0.972, 방화벽 발화 0건.",
    axis_4_universe = S4d$grid,
    axis_4_verdict = "★유니버스 축 확정 — 선행 런 analysis_fmb.csv 의 월평균 단면 N = 1397.7 이다. 전 시장 + 유동성 통과 표본을 복원하면 N중앙 1457 에서 t(Score) +1.458 이고 t(Size) -2.362 · t(Mom) -3.078 로 **선행 런의 부호 패턴(Size -3.225 · Mom -1.886)이 재현**된다. 같은 사양을 mandate 유니버스(K200 union KQ150 + 유동성, N중앙 340)로 좁히면 t(Score) = -0.090 · t(Mom) = +1.778 로 부호까지 뒤집힌다.",
    conclusion = "주장을 두 층으로 분리한다. ①**확정** — mandate 유니버스(K200 union KQ150 + 유동성)에서 같은 정의·사양·NW 공식으로 재면 t(Score) = -0.090 이다(U3). 이건 재현 문제가 아니라 직접 측정이다. 따라서 선행 런의 +3.199 를 '근접도가 KR 단면을 지배한다' 의 in-house 증거로 **인용할 수 없다**. ②**정황** — 양(+) t 는 전 시장 표본에서 산다(U1 t +1.458, N중앙 1457). 부호 패턴은 선행 런과 일치하나(Size -2.362 vs -3.225 · Mom -3.078 vs -1.886) 크기는 절반이다. 잔여 격차는 미해명으로 남긴다(선행 하네스 내부의 정확한 표본 기간 · frollapply NA 전파로 인한 252일 완전이력 요구 · LiqPass 산출 세부 · Period_Ret 경계). ★자기적대검증 W4 에서 이 과대주장 위험을 PARTIAL 로 인정하고 층을 나눴다.",
    self_adversarial_note = "W4 (PARTIAL) — U1 이 +3.199 가 아니라 +1.458 이므로 '완전 재현' 을 주장하지 않는다. 판정을 지는 것은 U3 의 직접 측정(-0.090)이다.",
    disclosure = "본 에이전트는 선행 산출물을 수정하지 않았다(Charter 원칙 8). 재측정 좌표만 기록한다."),

  F2_long_horizon_no_reversal = list(
    tier = "mechanism_discriminant",
    preregistered_statement = HYP$selected$falsification$side_observations[[1]]$observable,
    reject_if = HYP$selected$falsification$side_observations[[1]]$reject_if,
    results = S6$F2_long_horizon_no_reversal$results,
    verdict = "NOT_REJECTED — 기전 판별에서 GH2004 Table VI 가 KR 에서 재현됐다. 근접도 winner(FHH) 계수는 gap k=12/24/36/48 에서 -0.066/-0.018/+0.025/-0.032 %/월, NW-t -0.98/-0.26/+0.37/-0.47 로 **전 구간 무반전**이다. 반면 JT winner(JH)는 k=12 에서 -0.203 (t -2.01), k=48 에서 -0.260 (t -2.87) 로 유의 반전하고, 산업 winner(MH)도 k=12 에서 -0.239 (t -2.49) 로 반전한다. GH2004 미국 실측(JT winner -0.09 t -2.63 · MG winner -0.11 t -2.42 · 52wh 무반전)의 패턴과 부호·유의 구조가 일치한다.",
    consequence = "근접도는 과거수익률 외삽의 재파라미터화가 아니다 — anchoring 라벨은 이 축에서 철회되지 않는다. 동시에 이것은 성과 청구가 아니다(F2 는 부수 관측).",
    caveat = "FHL(loser)은 k=12 에서 -0.193 (t -2.08) 로 약한 유의 음이 남는다 — 근접도 하위 종목의 열위가 1년 뒤에도 완전히 사라지지는 않는다. GH2004 는 이 자리도 비유의였다."),

  F3_agent_evidence_individual_flow = list(
    tier = "mechanism_agent_evidence",
    preregistered_statement = HYP$selected$falsification$side_observations[[2]]$observable,
    reject_if = HYP$selected$falsification$side_observations[[2]]$reject_if,
    cohort_means = S6$F3_individual_flow_near_high$cohort_means,
    regression_form = S6$F3_individual_flow_near_high$regression_form,
    verdict = "NOT_REJECTED — 근접도 시장-내 상위 30% 코호트의 월간 개인 순매수는 시가총액 대비 -0.511% (NW-t -21.4), 하위 30% 는 +0.546% (t +22.3), H-L = -1.057% (t -35.3). 회귀판(규모 통제)에서도 lambda(z 근접도) = -0.00467 (t -34.98). GK2001 이 핀란드에서 실증한 '역사적 고가 부근 종목을 매도' 가 KR 에서 같은 부호로 나타난다. reject_if(개인 순매수가 유의 양) 미발동.",
    identification_caveat = "★부호는 기전 정합이나 이것이 '개인이 편향 주체' 를 식별하지는 않는다 — 순매수는 제로섬이라 개인 음(-)은 기관 양(+)의 거울상이며(institutional +0.303%, foreign +0.214%), 어느 쪽이 한계 가격결정자인지는 이 관측이 답하지 않는다. GH2004 의 기전 서술과 **양립**한다는 것이 정확한 진술이다.",
    data_caveat = S6$F3_individual_flow_near_high$data_caveat,
    flow_data_end_ym = S6$F3_individual_flow_near_high$flow_data_end_ym),

  F5_reference_point_identification = list(
    tier = "mechanism_identification",
    preregistered_statement = HYP$selected$falsification$side_observations[[4]]$observable,
    reject_if = HYP$selected$falsification$side_observations[[4]]$reject_if,
    mktint = S3$F5_low52_identification_mktint$coefficients,
    pooled = S3$F5_low52_identification_pooled$coefficients,
    verdict = "NOT_REJECTED (그러나 식별력 없음) — M17_Low_52w 를 동시에 넣어도 FHH 는 +0.100%/월 (t +0.930) 로 사실상 불변이고 FHL 은 -0.315%/월 (t -2.723) 로 오히려 강해진다. lo52 더미 자신은 lo52_H -0.117 (t -0.888) · lo52_L +0.082 (t +0.868) 로 비유의다. 즉 저가 준거점이 고가 준거점을 흡수하지 않는다 — reject_if 미발동.",
    but = "★그러나 '식별됐다' 고 읽으면 안 된다. 흡수되지 않은 대상(FHH)이 애초에 유의하지 않기 때문이다. 이 관측이 말할 수 있는 것은 '52주 저가 위치가 대안 설명이 아니다' 까지다.",
    side_effect = "M17 을 넣으면 JT winner(JH)가 +0.250%/월 (t +2.680) 로 유의해진다 — 가격 레인지 위치를 통제하면 KR 에서 개별 모멘텀이 살아난다는 관측이며 별도 축의 좌표다."),

  production_candidate = list(
    tier = "single_measurement_production_form",
    discipline = "★도훈 지시 1 — arm 배터리 폐지. 대비 arm / 탐색 arm / 아티팩트 대조 / 무신호 대조 미구축. 한 시도 = 실투형 후보 하나. 판정은 체인 종점의 essence 등급이다.",
    published_spec = "strict_pit_t_minus_1 — 신호를 월말 직전 거래일 종가로 계산(TS_LAG k=1 unit='d'). ast_field_map_v0 의 A1_RAWDATA_OHLCVS_daily 가용성 't1' 규칙과 request.json data_lag_rules(price = t-1 close) 정합.",
    strict_pit_ab = S5b$ab,
    strict_pit_reading = "★하네스 관행(월말 t 종가로 결정·집행)이 ast_verify 에서 FAIL_LOOKAHEAD 로 잡혔다. 합리화하지 않고 양쪽을 다 쟀다. 결과는 관행판이 **디플레이션** 쪽이었다 — same-close PORT_t +0.703 / alpha +5.43%/yr vs strict PORT_t +0.929 / alpha +6.99%/yr (상대 -31.2%). 즉 관행 규약이 성과를 부풀린 사례가 아니다. 그럼에도 PIT 가 제1법이므로 발행 사양은 엄격판이다. 보유 종목 겹침 78.5%.",
    spec = S5$spec, measurements = M, multifactor_alpha = S5c$multifactor_alpha,
    multifactor_alpha_same_close_ab = S5$multifactor_alpha,
    reachability_ceiling = S5b$strict_reachability, post_hoc_power = S5$post_hoc_power,
    turnover_reading = sprintf(paste0(
      "회전율 = 계약 규약(sum|dw| x 12) %.2f/yr. 편도(one-way) 환산 %.0f%%/yr — 선행 런 보고치 664%%/yr 도 편도 관행값이므로 편도끼리 비교한다. ",
      "15bps 편도 비용이 연 %.2f%%p 를 깎고 이는 gross 활성수익 %+.2f%%/yr 의 %.1f%% 다. ",
      "★자기적대검증(S11 W8)이 초판의 '15bps 가 이 축의 급소' 진술을 PARTIAL 로 반박했다 — 손익분기 편도 비용은 %.1f bps 로 현행의 2.7배이고, ",
      "비용을 0 으로 놓아도 활성수익 NW-t 는 %+.3f 에 그친다. 이 후보를 죽이는 것은 비용이 아니라 신호다. 비용은 실질 부담이되 구속 제약이 아니다."),
      num(M$turnover_annual_measured), 100*num(M$turnover_annual_measured)/2,
      num(S11$W8_cost_binding_check$cost_drag_ann_pct),
      num(S11$W8_cost_binding_check$gross_active_ann_pct),
      100*num(S11$W8_cost_binding_check$cost_share_of_gross_active),
      num(S11$W8_cost_binding_check$breakeven_cost_bps_oneway),
      num(S11$W8_cost_binding_check$cost_sensitivity[[1]]$nw_t)),
    cost_binding_check = S11$W8_cost_binding_check,
    basis_arithmetic = sprintf(paste0(
      "PORT_t %+.3f 인데 beta-통제 alpha 는 %+.2f%%/yr (t %+.3f) 다. beta = %.3f < 1 이므로 ",
      "(beta-1)*E[bm] = %+.2f%%/yr 만큼 활성수익이 깎여 PORT_t 가 alpha 를 **과소** 표시한다 ",
      "(measurement-graduation §2 거울상). 판정은 불변 — t(alpha) %+.3f 역시 유의 문턱에 못 미친다."),
      num(M$portfolio_alpha_t_nw_lag3), 100*num(M$beta_controlled$alpha_ann), num(M$beta_controlled$t_alpha),
      num(M$beta_controlled$beta), 100*num(M$beta_controlled$beta_contrib_ann), num(M$beta_controlled$t_alpha)),
    multifactor_caveat = sprintf(paste0(
      "★자기적대검증(S11)이 초판을 반박했다. 초판은 FF3 +15.59%%/yr (t 3.178) 를 싣고 'in-house MKT 가 mandate 벤치와 다르다' 고 적었는데 그 진술이 틀렸다 — ",
      "원인은 팩터 캐시가 아니라 넘긴 시계열의 **날짜 라벨**이었다. period_returns 의 date 는 신호월 말이고 수익은 다음 달에 실현되므로 팩터를 신호월 라벨로 붙이면 1개월 어긋난다. ",
      "정렬(홀딩월) 후 실측: mandate 벤치 초과수익을 in-house MKT 로 회귀하면 cor %.4f · beta %.3f · alpha %+.2f%%/yr (t %+.3f) · adjR2 %.3f 로 두 시장 대리는 사실상 같은 것을 잰다. ",
      "전략 알파도 정렬 후 FF3 %+.2f%%/yr (t %+.3f) · Carhart4 %+.2f%%/yr (t %+.3f) 이며 WML 로딩 %.3f 다. ",
      "★따라서 선행 런의 FF3->Carhart4 소멸 패턴(3.46->0.71)은 본 후보에서도 **재현된다**(%.2f->%.2f — 모멘텀 팩터가 알파의 절반을 흡수). 초판의 '재현되지 않는다' 진술은 철회한다. ",
      "인용 기준은 여전히 mandate 벤치 대비 beta-통제 alpha 이며(H5 승계) FF 계열은 병기 진단이다. mandate 벤치 대비 활성수익 = %+.2f%%/yr."),
      num(S11$W7_inhouse_MKT_vs_mandate_bench$aligned_holding_month$cor),
      num(S11$W7_inhouse_MKT_vs_mandate_bench$aligned_holding_month$beta),
      num(S11$W7_inhouse_MKT_vs_mandate_bench$aligned_holding_month$alpha_ann_pct),
      num(S11$W7_inhouse_MKT_vs_mandate_bench$aligned_holding_month$alpha_t),
      num(S11$W7_inhouse_MKT_vs_mandate_bench$aligned_holding_month$adj_r2),
      num(S11$W7b_factor_model_label_alignment$aligned_holding_month$FF3$alpha_ann_pct),
      num(S11$W7b_factor_model_label_alignment$aligned_holding_month$FF3$alpha_t),
      num(S11$W7b_factor_model_label_alignment$aligned_holding_month$Carhart4$alpha_ann_pct),
      num(S11$W7b_factor_model_label_alignment$aligned_holding_month$Carhart4$alpha_t),
      num(S11$W7b_factor_model_label_alignment$aligned_holding_month$Carhart4$loadings$WML),
      num(S11$W7b_factor_model_label_alignment$aligned_holding_month$FF3$alpha_ann_pct),
      num(S11$W7b_factor_model_label_alignment$aligned_holding_month$Carhart4$alpha_ann_pct),
      100*num(M$mean_active_net_ann)),
    multifactor_aligned = S11$W7b_factor_model_label_alignment,
    bench_vs_inhouse_mkt = S11$W7_inhouse_MKT_vs_mandate_bench,
    verdict = sprintf("자본 문턱 전면 미달 — PORT_t %+.3f (< 2.95) · oos_retention %.3f (< 0.5 무조건 FAIL 구간) · 활성수익 도달가능성 비율 %.3f. 부기간 붕괴가 구조적이다(2005-2014 +11.61%%/yr SR 0.80 t 2.39 -> 2015-2019 -0.12%% -> 2020-2026 -4.71%%). 등급은 선언하지 않는다(권위 = essence_score.R).",
                      num(M$portfolio_alpha_t_nw_lag3), num(ADV$oos_retention_v2_median),
                      num(S5b$strict_reachability$coverage_ratio))),

  power_contract_step0 = list(
    gate_rule = S2$gate$rule, verdict = S2$gate$verdict,
    anchors = S2$anchors, forbidden_anchor = S2$forbidden_anchor,
    band = S2$gate$band,
    reading = sprintf(paste0(
      "지배 ratio %.3f ~ %.3f (검정력 %.1f%% ~ %.1f%%) 로 (b) 조건부 착수 구간이었고, 최저 앵커(A raw)가 0.156 으로 ",
      "착수금지 문턱 0.15 를 간신히 넘었다. 금지 앵커(자기금융 0.65%%/월)를 썼다면 ratio 0.635 · 검정력 42.9%% 로 ",
      "약 4배 과대 산출됐을 것이다 — 사전등록 금지가 실제로 게이트를 지켰다."),
      num(S2$gate$min_governing_ratio), num(S2$gate$max_governing_ratio),
      100*num(S2$anchors$A_paper_winner_leg_raw$power), 100*num(S2$anchors$C_inhouse_prior_ff3$power)),
    what_this_round_left = S2$gate$what_this_round_leaves_if_undecided))

## ══ alpha_validation.json ══════════════════════════════════════════════════
challenge_flags <- c(
  "[재포장 자기신고 · PARTIAL] 소비면 결론은 선행 런과 같다(PORT_t 0.303 -> 0.703, 둘 다 2.95 미달 · oos_retention -1.131 -> -0.388, 둘 다 0.5 미만). 신호는 등재 M06 과 Spearman 1.0000 으로 동일 대상이다. 새로운 것은 진단 층(F1/F2/F3/F4/재귀속)이지 알파가 아니다.",
  "[★선행 in-house 양(+) 관측의 귀속 확정] 선행 런 FM t +3.199 는 mandate 유니버스에서 측정된 적이 없다 — 그 회귀의 월평균 단면 N = 1397.7(전 시장)이고, 같은 사양을 K200 union KQ150 로 좁히면 t = -0.090 이다. 정의(Spearman 0.9995)·사양·수익경로 축은 전부 기각됐고 유니버스 축만 부호 패턴을 재현했다.",
  "[1급 기각 · 검정력 6~12%] FHH NW-t +0.910 으로 reject_if 1 발동. 단 GH2004 winner-leg 앵커에 대한 검정력이 6.4~12.1% 라 '효과 없음' 으로 승격 금지 — 라벨은 '미결 위의 비유의' 다.",
  "[숏 레그 편중이 미국보다 심하다] KR 실측 FHH +0.095%/월(t +0.910) vs FHL -0.310%/월(t -2.616) — 스프레드의 76.6%가 숏 레그다(미국 74%). 롱온리 KR 에서 수확 가능한 부분이 더 작다. 이는 제약 귀속이 아니라 마찰 서술(공매도 제약)의 실측 확인이다 — 제약 완화 레버 미제시(INV-7).",
  "[누출 귀무 > 신호] L11_Kyle_Lambda +2.557 · D35_RealVol_63d +2.111 · rv63 -2.118 이 신호 자신 +1.541 을 넘는다. 근접도의 독립성은 증명되지 않았고, 증명할 유의 신호도 없다. 라벨 = VOL_INDEPENDENCE_UNPROVEN.",
  "[절단면 잔존] 직교화 후 전 구간 Spearman 은 rv +0.025 로 0 이지만 십분위 양끝/중앙 비율은 rv63 1.1123 이다. raw/rank 두 통제 규약이 거의 동일한 결과를 줘 이 축에서는 규약 갈림이 발생하지 않았다.",
  "[기전 지문은 살아 있는데 알파가 없다] F2(장기 무반전)와 F3(신고가 부근 개인 순매도)이 둘 다 GH2004/GK2001 예측대로 나왔다. 그런데 F1 의 롱온리 반쪽과 소비면 전이는 실패했다. 이 조합이 이 라운드의 실질 산출이다 — 기전의 존재는 수확 가능성을 함의하지 않는다.",
  "[F3 식별 한계] 개인 순매수 음(-)은 기관·외국인 양(+)의 거울상(제로섬)이라 '개인이 편향 주체' 를 식별하지 않는다. 양립 진술까지가 정확하다.",
  "[★자기적대검증이 초판을 반박 1 — FF 알파는 라벨 정렬 아티팩트였다] 초판은 FF3 +15.59%/yr (t 3.178) 를 싣고 'in-house MKT 가 mandate 벤치와 다르다' 고 적었으나, 원인은 팩터 캐시가 아니라 넘긴 시계열의 **날짜 라벨**이었다(신호월 vs 홀딩월 1개월 어긋남). 정렬 후: 벤치 초과수익 ~ MKT 회귀 cor 0.968 · beta 0.943 · alpha -0.11%/yr (t -0.099) · adjR2 0.937 — 두 시장 대리는 같은 것을 잰다. 전략 알파는 FF3 +7.76%/yr (t 2.023) -> Carhart4 +3.87%/yr (t 1.225, WML 로딩 0.473). ★선행 런의 FF3->Carhart4 소멸 패턴은 본 후보에서도 재현된다 — 초판의 '재현되지 않는다' 진술 철회. run_multifactor_regression 호출 규약(넘기는 시계열의 날짜 라벨)이 하네스 수리 대상이다.",
  "[회전율 급소] 편도 환산 768%/yr · 15bps 가 연 %s 를 깎는다. 선행 런 664%/yr 와 같은 체질이다.",
  "[중복성] fh252 = 등재 M06_High_52w (Spearman 1.0000). 신규 발굴이 아니라 기존 등재 팩터의 재검증이다(Factor Zoo 축소 ① 정합). M02_Mom_6_1 과 +0.573, M17_Low_52w 와 -0.461.",
  "[검출기 발화 2건 · 보고경로] detect_lookahead 가 s5_production.R 에서 C1 'sd() on full vector * sqrt()' 2건 발화. 둘 다 실현 수익 시계열의 사후 요약통계(net SR)이며 점수·선별·비중 어디에도 입력되지 않는다. 위반 주입 없이 발화한 것은 검출기 생존의 양성 대조다.",
  "[승계분 무수정] alpha_hypothesis.json 의 mechanism / falsification / regime_scope 를 재작성하지 않았다(Charter 원칙 8). 설계 에이전트의 착수 비권고(verdict_qualifier)도 그대로 승계 기록한다.",
  "[★strict-PIT A/B 실시] ast_verify 가 FAIL_LOOKAHEAD 로 잡은 것은 하네스 관행(월말 t 종가 결정·집행) vs ast_field_map 의 A1 가용성 't1' 규칙 불일치다. 합리화 금지 규약에 따라 양쪽을 다 쟀다 — same-close PORT_t +0.703 / alpha +5.43%/yr vs strict PORT_t +0.929 / alpha +6.99%/yr. 관행판이 오히려 낮다(상대 -31.2%) = 관행이 성과를 부풀린 사례가 아니다. 그럼에도 발행 사양은 엄격판이며 AST 에 TS_LAG(k=1, unit='d') 로 명시했다. 보유 겹침 78.5%. ★이 불일치는 기저 arm·2/20 cell4·3/20 을 포함한 전 라운드 공통이며 하네스 수리 대상으로 기록한다(본 에이전트는 계약 파일을 고치지 않는다).",
  "[2급 취소 승계] 설계의 2급(cell4 대비 증분)은 도훈 지시 3 으로 취소됐다. 그 자리를 체인 종점 essence 등급이 대신하므로 본 산출물은 증분 검정을 수행하지 않았고 cell4 대조 arm 도 짓지 않았다. 검정력 앵커 B(증분)는 산출·기록만 했다(ratio raw -0.010 / risk-adj 0.108).")
challenge_flags[11] <- sprintf(paste0(
  "[★자기적대검증이 초판을 반박 2 — 급소는 비용이 아니라 신호다] 편도 회전율 %.0f%%/yr · 15bps 가 연 %.2f%%p(gross 활성수익의 %.1f%%)를 먹는 것은 사실이고 ",
  "선행 런 664%%/yr 와 같은 체질이다. 그러나 손익분기 편도 비용은 %.1f bps 로 현행 15bps 의 2.7배이고, 비용 0 에서도 활성수익 NW-t 는 %+.3f 다. ",
  "초판의 '15bps 편도 비용이 이 축의 급소' 진술을 PARTIAL 로 정정한다 — 비용은 실질 부담이되 구속 제약이 아니다."),
  100*num(M$turnover_annual_measured)/2, num(S11$W8_cost_binding_check$cost_drag_ann_pct),
  100*num(S11$W8_cost_binding_check$cost_share_of_gross_active),
  num(S11$W8_cost_binding_check$breakeven_cost_bps_oneway),
  num(S11$W8_cost_binding_check$cost_sensitivity[[1]]$nw_t))

alpha_validation <- list(
  schema = "alpha_validation/v1", task_id = "WT-R20260829_007", wt_type = "reinforcement",
  as_of_date = "2026-08-29", attempt = "7/20", axis = "multifactor — 52주 신고가 근접도 신호 교체 (George-Hwang 2004)",
  base = list(base_id = "RP_20260829_122020_9192", base_grade = "F",
              inherited_cell4 = "2/20 cell4: PORT_t 1.294 · beta-통제 alpha +5.14%/yr t 1.205"),
  paper = list(citation = "George, T.J. & Hwang, C.-Y. (2004), The 52-Week High and Momentum Investing, Journal of Finance 59(5):2145-2176",
               doi = "10.1111/j.1540-6261.2004.00695.x",
               url = "https://onlinelibrary.wiley.com/doi/abs/10.1111/j.1540-6261.2004.00695.x",
               open_pdf = "https://www.bauer.uh.edu/tgeorge/papers/gh4-paper.pdf",
               read_by = "alpha-hypothesis (원문 직접 판독 — alpha_hypothesis.json::paper_reading)"),
  metric_type = "canonical_screen",
  metric_type_note = "실투형 후보 수치는 canonical_screen_bt() 경유 실측(계약 grade). 단면 회귀(F1/F2/F3/F4/F5)는 metric_type='cross_sectional_regression' 이며 포트폴리오 판정이 아니다. 등급은 선언하지 않는다 — 권위는 essence_score.R 하나.",
  round_discipline = list(
    single_measurement = "arm 배터리 폐지(도훈 지시 1). 실투형 후보 1건만 측정. 대비 arm / 탐색 arm / 아티팩트 대조 / 무신호 대조 미구축.",
    chain_completion = "음성 판정이 체인을 멈추지 않는다(도훈 지시 2). 본 산출물은 risk -> optimizer -> forge 로 넘어가 등급을 받으므로 alpha_hat / confidence / 유니버스 / 시점 규약 결측 0 으로 발행한다.",
    secondary_cancelled = "설계 2급(cell4 증분)은 취소(도훈 지시 3). 1급(F1)과 부수관측(F2/F3/F5) + 필수 교란기각(F4)은 유지."),
  mandatory_prior_run_disclosure = prior_disclosure,
  fixed_axes = list(
    signal = S5$spec$signal, selection = S5$spec$selection, weighting = S5$spec$weighting,
    universe = S5$spec$universe, liquidity = S5$spec$liquidity, cost = S5$spec$cost,
    window = S5$spec$window, rebalance = S5$spec$rebalance,
    long_only = TRUE, max_names = 25L,
    skip_convention = S5$spec$skip_convention,
    paper_assumption_broken = S5$spec$paper_assumption_broken),
  h1_precheck_split_adjustment = S1$h1_precheck,
  step0_power_contract = S2,
  primary_F1 = S3, confound_F4 = S4,
  reattribution_F4b = S4b, reattribution_F4c = S4c, reattribution_F4d = S4d,
  production_candidate_same_close_ab = S5, production_candidate_strict_pit = S5b,
  production_candidate_strict_multifactor = S5c, self_adversarial_quantitative = S11,
  side_observations = S6,
  alpha_construction = S8,
  preregistered_verdicts = verdicts,
  pit = S7,
  challenge_flags = challenge_flags,
  selection_objective = "canonical_port_t",
  n_trials = 1L, selection_type = "chain",
  selection_type_rationale = "실투형 후보 1건. argmax/threshold-pick 부재 — 사양은 사전등록(근접도 top-25)으로 고정됐고 성과를 보고 고르지 않았다. DSR 게이트 부적용(measurement-graduation §3), 수치는 진단 산출.",
  grade_declaration = "없음 — 등급 권위는 essence_score.R 하나. 본 라운드는 등급을 선언하지 않는다.")
write_json(alpha_validation, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S9] alpha_validation.json written\n")

## ══ AST (𝒪 안 · 방언 분열 회피: DIV_GUARD/DIV 대신 LOG-SUB 단조 동치) ══════
CL0 <- list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = "Close")
## ★TS_LAG(k=1, unit="d") = strict-PIT 발행 사양. ast_field_map A1 가용성 't1'(일자 d 종가는 d+1 가용)
##   와 request.json data_lag_rules(price = t-1 close) 를 AST 에 명시 표현한다. S5b 가 실측 대조를 병기.
CL <- list(op = "TS_LAG", args = list(CL0, 1), children = list(CL0), k = 1L, unit = "d")
hi <- list(op = "TS_MAX", args = list(CL, 252), children = list(CL), window = 252L, unit = "d")
lg1 <- list(op = "LOG", args = list(CL), children = list(CL))
lg2 <- list(op = "LOG", args = list(hi), children = list(hi))
sub <- list(op = "SUB", args = list(lg1, lg2), children = list(lg1, lg2))
AST <- list(op = "CS_RANK", args = list(sub), children = list(sub))

pkg <- list(
  task_id = "WT-R20260829_007",
  strategy_id = "WT-R20260829_007_GH2004_52w_high_proximity_top25",
  as_of_date = "2026-08-29", forecast_horizon = "1M", spec_version = "ast_v1.1",
  pit = list(sig_date = S8$as_of_date, decision_ts = S8$as_of_date),
  hypothesis = list(
    statement = HYP$selected$hypothesis_description,
    mechanism = HYP$selected$mechanism,          # 승계 — 재작성 금지 (Charter 원칙 8)
    falsification = list(
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Close",
           expectation = sprintf("[F1 1급] GH2004 Table V 9변수 FM 에서 근접도 winner 더미(FHH)가 유의 양(+). [실측] FHH %+0.4f%%/월 NW-t %+0.3f (시장-내 랭킹 · n=259월 · 1554 단면회귀) -> reject_if 1 발동. loser 더미 FHL %+0.4f%%/월 t %+0.3f 만 유의.",
                                 100*num(F1$coefficients$FHH$mean_monthly), num(F1$coefficients$FHH$nw_t),
                                 100*num(F1$coefficients$FHL$mean_monthly), num(F1$coefficients$FHL$nw_t))),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Ret",
           expectation = "[F2 부수관측] 기전이 anchoring 이면 근접도는 장기(k=12~48)에 반전하지 않아야 한다. [실측] FHH 계수 t -0.98/-0.26/+0.37/-0.47 전 구간 무반전. 대조적으로 JT winner 는 k=12 t -2.01 · k=48 t -2.87 로 유의 반전 -> GH2004 Table VI 의 KR 재현. reject_if 미발동."),
      list(field = "A6_investor_flow_stock_daily", field_column = "Individual",
           expectation = "[F3 주체 증거] 근접도 상위 코호트에서 개인 순매수가 음(-)이어야 한다(GK2001). [실측] top30 -0.511%/월(시총 대비) NW-t -21.4 · H-L -1.057% t -35.3 · 회귀판 lambda -0.00467 t -34.98. reject_if(유의 양) 미발동. 단 제로섬 거울상이라 주체 식별은 아니다."),
      list(field = "FDB-B2_registry_rawdata_price_daily", field_column = "L11_Kyle_Lambda",
           expectation = "[F4 필수 교란기각] L-family/변동성/산업모멘텀 통제 후 신호가 소멸하면 재명명. [실측] 통제 전 t +0.877 -> L-family+vol 후 +1.096 -> 전 통제 후 +0.097. 통제 전에 이미 비유의. 누출 귀무 L11_Kyle_Lambda +2.557 · D35_RealVol_63d +2.111 이 신호(+1.541)를 넘는다."),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Low",
           expectation = "[F5 준거점 식별] M17_Low_52w 가 M06 을 흡수하면 '신고가가 준거점' 주장 불성립. [실측] lo52 더미 비유의(t -0.888 / +0.868) · FHH 불변(+0.930). reject_if 미발동. 단 흡수 대상 자체가 비유의라 식별력은 없다.")),
    regime_scope = HYP$selected$regime_scope),   # 승계 — 재작성 금지
  ast = AST,
  ast_dialect_note = "★방언 분열 회피 설계: 나눗셈 연산자는 schema.json enum 이 DIV_GUARD, ast_verify.py operator_library 가 DIV 로 갈려 있다(3/20 실측 FAIL_CONTRACT). 본 라운드는 근접도를 P/high 대신 **log P - log high** 로 표기했다 — 두 표기는 단조 동치이고 소비가 CS_RANK(순위) 이므로 선택 결과가 **정확히** 동일하다. LOG/SUB/TS_MAX/CS_RANK 는 두 정본 모두에 존재하므로 분열이 발생하지 않는다. 구조 방언(schema=args / ast_verify=children)은 두 키를 모두 실어 처리했다. top-level ast 를 두어 검증기가 리프 0개를 순회하는 빈 검증(2/20 전례)을 회피하고, 실제 순회 리프 수를 ast_verify_result 에 기록한다.",
  factors = list(list(
    factor_id = "F1_GH2004_52w_high_proximity",
    ast = AST, role = "core_signal", restatement_exposure = 0L)),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Close", availability_rule = "fixed: 일간 종가 T+0 — 근접도 분자(월말 t 종가)와 분모(t 까지 252 거래일 최고가) 모두 t 이하만 참조",
           restatement_prone = TRUE)),
    verdict = "warn_restatement",
    notes = "RAWDATA 는 수정주가 원장이라 restatement_prone=true(액면분할·배당 시 과거 전 구간 재작성). H1 사전점검 실측: 'Close 로그점프 |>log(3)| 인데 |일간 Ret|<0.5' 지문 0건 / 4,306,892행 · 2018-05 삼성전자 50:1 분할 구간에서 implied shares(Size/Close) 불변 -> 분자·분모 조정 정합 확인. 재무·컨센서스 리프 0. pin_cache 미사용(단일 스냅샷에서 전 측정 동시 산출 — 다중 라운드 비교 시 pin 의무, measurement-graduation §7)."),
  alpha_vector = setNames(as.list(round(O8$CS$alpha_hat, 6)), O8$CS$Ticker),
  confidence_vector = setNames(as.list(round(O8$CS$confidence, 4)), O8$CS$Ticker),
  alpha_vector_note = sprintf("as_of %s · %d종(K200 union KQ150 적격 전수). alpha_hat = lambda_FM x z(근접도, 시장-내 정규분위) - 단면평균. lambda_FM = %+0.6f/월 (무통제 Fama-MacBeth 시계열 평균 — 데이터 추정, 하드코딩 0). 병기 컬럼 alpha_hat_full_control 은 전 통제 사양 lambda %+0.6f/월 로 스케일한 판이며 감쇠 배율 %.3f 다. 실투형 후보는 이 점수 상위 25종.",
                              S8$as_of_date, nrow(O8$CS), num(S8$lambda_no_control_monthly),
                              num(S8$lambda_full_control_monthly), num(S8$lambda_attenuation)),
  signal_matrix_ref = "stage_artifacts/WT_R20260829_007/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "Behavioral / Price reference point",
    proxy = "52주 신고가 근접도 FH = Close_t / max(Close, 최근 252 거래일)  [= 등재 M06_High_52w, Spearman 1.0000]",
    formula = "exp( log(Close_t) - log(TS_MAX(Close, 252)) )  — CS_RANK 소비이므로 log 표기와 비율 표기가 선택 동치",
    lag_rule = "price t-1 close 규약 · 월말 t 결정/집행(실투 후보는 skip 없음). GH2004 의 1개월 skip 은 회귀 검정 규약이며 F1/F2 에만 적용.",
    winsorization = "none (단면 순위 소비)",
    neutralization = "none (실투 후보). 통제판은 F4 사다리에서 별도 측정(L-family + 실현변동성 + 산업모멘텀 + 규모).",
    economic_rationale = "behavioral — 52주 신고가를 준거점(anchor)으로 삼는 거래층의 호가 상향 주저가 좋은 뉴스의 분할 반영을 낳고 후속 드리프트로 실현된다(George-Hwang 2004). KR 마찰 = 개인 거래 비중 · 기관 신규편입 지연 · 15bps 비용 문턱 · 공매도 제약(far 레그).",
    redundancy_cluster_id = "MOM_price_derived / DIST-AR-041 (가격-파생 모멘텀 변형 — 소진 계열). 등재 M06_High_52w 와 동일 대상이므로 신규 발굴이 아니라 재검증.",
    weight_theta = 1.0,
    references = list("George, T.J. & Hwang, C.-Y. (2004), JF 59(5):2145-2176. https://www.bauer.uh.edu/tgeorge/papers/gh4-paper.pdf",
                      "Grinblatt, M. & Keloharju, M. (2001), JF 56(2):589-616 (주체 증거 — GH2004 인용)"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = num(M$portfolio_alpha_t_nw_lag3),
    canonical_port_t_pvalue = num(M$portfolio_alpha_t_pvalue),
    canonical_n_months = 259L,
    canonical_port_t_note = "발행 사양(strict-PIT) 실투형 후보(근접도 top-25 EW) 값 +0.929. same-close 규약 A/B 판은 +0.703. 선행 런은 0.303. 셋 다 자본 문턱 2.95 에 한참 못 미친다. ★무신호 대조는 본 라운드 규율상 미구축(도훈 지시 1) — 따라서 이 값의 **신호 기여는 증명되지 않았다**(제약형 롱온리는 형태 자체가 대형주 노출을 담는다).",
    portfolio_alpha_t_beta_controlled = num(M$beta_controlled$t_alpha),
    portfolio_alpha_beta_controlled_ann = num(M$beta_controlled$alpha_ann),
    beta = num(M$beta_controlled$beta),
    beta_contrib_ann = num(M$beta_controlled$beta_contrib_ann),
    ff3_alpha_annual = num(S11$W7b_factor_model_label_alignment$aligned_holding_month$FF3$alpha_ann_pct)/100,
    ff3_alpha_t = num(S11$W7b_factor_model_label_alignment$aligned_holding_month$FF3$alpha_t),
    carhart4_alpha_annual = num(S11$W7b_factor_model_label_alignment$aligned_holding_month$Carhart4$alpha_ann_pct)/100,
    carhart4_alpha_t = num(S11$W7b_factor_model_label_alignment$aligned_holding_month$Carhart4$alpha_t),
    carhart4_wml_loading = num(S11$W7b_factor_model_label_alignment$aligned_holding_month$Carhart4$loadings$WML),
    multifactor_basis = "★홀딩월(t+1) 라벨 정렬판. in-house KR factor cache(kr_factor_returns_v2) 대비 / 초과수익 기준 RF. 자기적대검증(S11)이 신호월 라벨 산출(FF3 +15.59%/yr t 3.178)을 정렬 아티팩트로 적발했다 — 정렬 후 FF3 +7.76%/yr (t 2.023), Carhart4 +3.87%/yr (t 1.225, WML loading 0.473).",
    ff3_alpha_annual_misaligned_label = num(S5c$multifactor_alpha$FF3$alpha_annual_pct)/100,
    ff3_alpha_t_misaligned_label = num(S5c$multifactor_alpha$FF3$alpha_t),
    multifactor_misalignment_record = "신호월 라벨로 xts 를 넘기면 MKT 로딩이 0.091 / adjR2 0.016 으로 붕괴하고 알파가 +15.59%/yr 로 부풀려진다. 정렬판은 MKT 로딩 0.745 / adjR2 0.509. 호출 규약(run_multifactor_regression 에 넘기는 시계열의 날짜 라벨)이 하네스 수리 대상이다.",
    fm_lambda_no_control = num(S8$lambda_no_control_monthly),
    fm_t_no_control = num(S4$verdict$t_no_control),
    fm_t_after_controls = num(S4$verdict$t_full_spec),
    fm_FHH_dummy_monthly = num(F1$coefficients$FHH$mean_monthly),
    fm_FHH_dummy_nw_t = num(F1$coefficients$FHH$nw_t),
    fm_FHL_dummy_nw_t = num(F1$coefficients$FHL$nw_t),
    rank_ic = num(ADV$rank_ic), icir = num(ADV$icir),
    harvey_t_stat = num(ADV$harvey_t_stat),
    harvey_t_stat_note = "근접도 rank-IC 월계열의 NW lag-3 t (advisory). ★portfolio-alpha t 와 명시 구분 — measurement-graduation §2.",
    harvey_t_specs_pass_count = 0L,
    monotonicity = num(ADV$monotonicity_spearman),
    subperiod_stability = num(ADV$subperiod_stability),
    turnover_proxy = num(M$turnover_annual_measured),
    turnover_convention = "계약 규약 sum|dw| x 12 (양방향). 편도 환산 = 절반. 선행 런 664%/yr 는 편도 관행값.",
    net_sr = num(M$net_sr_active),
    deflated_sharpe_ratio = num(ADV$deflated_sharpe_ratio),
    oos_retention_approx = num(ADV$oos_retention_v2_median),
    post_neutralization_ic = num(ADV$post_neutralization_ic),
    post_neutralization_retention = num(ADV$post_neutralization_retention),
    diag_ew_universe_port_t = num(S5$measurements$diag_ew_universe$portfolio_alpha_t_nw_lag3),
    diag_cap_tier_weight_share = S5$measurements$diag_cap_tier$weight_share_avg,
    reachability_coverage_ratio = num(S5b$strict_reachability$coverage_ratio),
    reachability_required_active_ann_for_t295 = num(S5b$strict_reachability$required_active_ann_for_t295),
    alpha_inheritance_cor = 0.0,
    alpha_inheritance_note = "기저 RP_20260829_122020_9192(JT1993 6-6 과거수익률)와 **신호 자체가 다르다** — 누적 3회가 소진한 '동일 신호 위의 조작'을 처음 벗어난 시도다. 단 등재 M06_High_52w 와는 Spearman 1.0000 으로 동일 대상이므로 alpha_discovery 는 0 이다(재검증). wt_type=reinforcement 이므로 certificate 미발급이 정상."),
  alpha_discovery_count = 0L,
  selection_objective = "canonical_port_t",
  n_trials = 1L, selection_type = "chain",
  challenge_flags = challenge_flags,
  mandatory_prior_run_disclosure = prior_disclosure,
  preregistered_verdicts = verdicts,
  handoff_to_risk = list(
    chain_completion_mandate = "★음성 판정이 체인을 멈추지 않는다(도훈 지시 2). 본 패키지는 risk -> optimizer -> forge 로 넘어가 essence 등급을 받는다.",
    alpha_vector_complete = TRUE, confidence_vector_complete = TRUE,
    universe_declared = "K200 union KQ150 (PIT 시변 멤버십) · 유동성 20일 평균 거래대금(t-1) >= 2e8 KRW",
    timing_convention = "월말 t 신호 -> t+1 캘린더월 보유. 오버레이 미적용(S0/S1 준수).",
    period_returns_production = "stage_artifacts/WT_R20260829_007/period_returns_production.csv (신호월 라벨 + 홀딩월 라벨 + gross/cost/net + 벤치마크 + n_names + traded)",
    known_weaknesses_for_downstream = c(
      "회전율이 급소다 — 편도 768%/yr. optimizer 단계의 turnover penalty 가 이 후보의 생사를 가른다.",
      "oos_retention -0.388 (2020~2026 활성 -4.31%/yr) — 후반부 붕괴가 구조적이다.",
      "beta 0.766 — 방어적 노출이라 PORT_t 가 alpha 를 과소 표시한다(measurement-graduation §2 거울상).",
      "MDD 는 선행 런에서 64.4% 였다. 본 라운드는 MDD 를 산출하지 않았다(forge 소관).")),
  validation_ref = "stage_artifacts/WT_R20260829_007/alpha_validation.json")
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S9] alpha_package.json written\n")

source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-R20260829_007", package_type = "alpha_package",
  method_selected = "GH2004 52주 신고가 근접도 — 단일 실투형 후보 top-25 + Table V/VI 이식 FM + 선행 런 재귀속",
  input_file_paths = c(
    file.path(ROOT, ".cache/RAWDATA.parquet"),
    file.path(MBX, "alpha_hypothesis.json"),
    file.path(OUT, "alpha_scores.parquet"),
    file.path(OUT, "alpha_validation.json"),
    file.path(OUT, "period_returns_production.csv")))
cat("[S9] lineage recorded\n")
