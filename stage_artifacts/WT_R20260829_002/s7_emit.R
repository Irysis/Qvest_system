# S7 — alpha_validation.json + alpha_package.json 발행 (WT-R20260829_002)
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_002")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_002")
rj <- function(f) fromJSON(file.path(OUT, f), simplifyVector = FALSE)
S2 <- rj("s2_cells.json"); S3 <- rj("s3_diag.json"); S4 <- rj("s4_beta_pit.json")
S5 <- rj("s5_alpha_meta.json"); S6 <- rj("s6_neutral.json")
O5 <- readRDS(file.path(OUT, "s5_objects.rds")); CS <- O5$CS
HYP <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
num <- function(x) if (is.null(x)) NA_real_ else as.numeric(x)

cA <- S2$contrasts$A_c2_minus_c1; cB <- S2$contrasts$B_c4_minus_c2; cBL <- S2$contrasts$B_LS_c3_minus_c1
c1 <- S2$cells$cell1_LS_decile; c2 <- S2$cells$cell2_LO_decile
c3 <- S2$cells$cell3_LS_top25;  c4 <- S2$cells$cell4_LO_top25
ns4 <- S3$no_signal_control$gates$cell4_LO_top25; ns2 <- S3$no_signal_control$gates$cell2_LO_decile

## ── 사전등록 판정 ───────────────────────────────────────────────────────────
verdicts <- list(
  primary_axisA_short_leg = list(
    contrast = "Delta(cell2 - cell1) — 숏 레그 제거",
    raw_mean_ann = num(cA$mean_ann), raw_nw_t = num(cA$nw_t),
    beta_controlled_alpha_ann = num(cA$beta_alpha$alpha_ann),
    beta_controlled_t_alpha = num(cA$beta_alpha$t_alpha),
    beta_of_contrast = num(cA$beta_alpha$beta),
    beta_contrib_ann = num(cA$beta_alpha$beta_contrib_ann),
    reject_if_1_fired = TRUE,
    verdict = "REJECTED_AS_PREREGISTERED — '숏 레그가 기저 F 의 원인' 기각",
    basis = "reject_if ① |NW-t| < 2 : raw 1.995 < 2.000 (발동) · 병기 의무 기준인 β-통제 α 차 t(α)=0.557 도 <2 로 일치. 두 기준이 갈리지 않는다.",
    power = list(raw_axis = S2$power$primary_axisA, beta_controlled_axis = S5$power_beta_controlled$axisA),
    disposition_label = "미결(underpowered) — '효과 없음' 아님. β-통제 축 ratio 0.430 · 기대 t 1.205 · 검정력 22.5% (3단 처분 (b) 조건부 구간)",
    identity_caveat = "★Delta(cell2-cell1) 는 항등적으로 패자 데실의 총수익 r_lose 다(cell1 = r_win - r_lose, cell2 = r_win). 그 raw 평균의 81%가 시장 노출이다(β 0.849 · β기여 +9.90%/yr 대 α +2.28%/yr). 따라서 raw NW-t 1.995 는 '숏 레그의 알파 기여' 를 재는 통계량이 아니며, 문턱 2.0 을 0.005 차로 비껴간 것을 강도의 근거로 읽어서는 안 된다. 판정을 지탱하는 것은 β-통제 t 0.557 이다."),
  secondary_axisB_concentration = list(
    contrast = "Delta(cell4 - cell2) — 데실(35종) -> top-25",
    raw_mean_ann = num(cB$mean_ann), raw_nw_t = num(cB$nw_t),
    beta_controlled_alpha_ann = num(cB$beta_alpha$alpha_ann),
    beta_controlled_t_alpha = num(cB$beta_alpha$t_alpha),
    reject_if_2_fired = FALSE,
    verdict = "NOT_REJECTED — Delta = +1.59%/yr > 0 이므로 reject_if ②(Delta<=0) 미발동. 집중 형태는 기각되지 않는다.",
    significance = "단 |t| < 2 (raw 1.524 · β-통제 1.392) — 불기각이지 확증 아님",
    power = list(raw_axis = S2$power$secondary_axisB, beta_controlled_axis = S5$power_beta_controlled$axisB),
    disposition_label = "미결(underpowered) — ratio 0.571 · 기대 t 1.600 · 검정력 35.9%",
    additivity_check = list(
      contrast = "Delta(cell3 - cell1) — 롱숏 하 동일 집중 축",
      raw_mean_ann = num(cBL$mean_ann), raw_nw_t = num(cBL$nw_t),
      beta_controlled_alpha_ann = num(cBL$beta_alpha$alpha_ann),
      beta_controlled_t_alpha = num(cBL$beta_alpha$t_alpha),
      note = "부호·크기 정합(+2.19%/yr vs +1.43%/yr, t 1.535 vs 1.392) — 두 축 가법성 지지, 상호작용 증거 없음")),
  reject_if_3_fingerprints = list(
    fired = FALSE,
    a_short_leg_loss_concentrates_in_rebound = list(
      holds = TRUE,
      recovery_dummy_coef_monthly = num(S3$fingerprint_a_short_leg_rebound$test$coef_recovery_monthly),
      recovery_dummy_t = num(S3$fingerprint_a_short_leg_rebound$test$t_recovery),
      beta_controlled = S4$fingerprint_a_beta_controlled,
      up_month_contrast = S4$up_month_contrast,
      note = "무통제 t −4.403. ★BM 수익 통제 후에도 recovery 계수 −0.0427/월 t −2.367 로 생존 = '패자주가 고β라서' 로 환원되지 않는다. 시장 방향을 거의 고정한 대조(expansion bm +59.5%/yr vs recovery bm +62.8%/yr)에서 패자 데실 수익이 +34.9% vs +94.3% 로 2.7배."),
    b_loser_decile_small_cap_tilt = list(
      holds = TRUE,
      loser_minus_winner_size_pct = num(S3$fingerprint_b_loser_small_tilt$test$loser_minus_winner_size_pct),
      nw_t = num(S3$fingerprint_b_loser_small_tilt$test$nw_t),
      loser_minus_universe = num(S3$fingerprint_b_loser_small_tilt$test$loser_minus_universe),
      nw_t_vs_universe = num(S3$fingerprint_b_loser_small_tilt$test$nw_t_vs_universe),
      note = "size_pct 0=최대형 1=최소형. 패자 데실 0.634 vs 승자 0.462 vs 유니버스 0.500."),
    verdict = "지문 (a)(b) 모두 성립 — 마찰 기전 서사(공매도 제약 하 패자 과대가격 · 반등월 옵션형 손실 · 소형 편중) 불기각"),
  reject_if_4_smallcap_attribution = list(
    fired = FALSE,
    cell4_ew_universe_port_t = num(c4$diag_ew_universe$port_t),
    cell4_capw_port_t = num(c4$port_t_capw),
    cell4_other_tier_weight_share = num(c4$diag_cap_tier$weight_share_avg$OTHER),
    verdict = "미발동 — 연언(EW-유니버스 대비 소멸 ∧ OTHER tier 지배) 중 앞항 불성립. EW-유니버스 대비 t +1.426 로 소멸하지 않고 cap-w(+1.294)보다 오히려 높다. OTHER tier 91.2% 는 성립.",
    contrast_with_attempt1 = "강화 1/20 의 mom_only(M02) 는 EW-유니버스 PORT_t −0.064 로 소멸했다. 본 라운드의 6-6 신호는 그 축에서 살아남는다 = 두 관측쌍의 신호 축 차이가 실재했다는 사후 증거(설계의 [제3축 경고] 확증).",
    ew_basis_caveat = "★EW-basis 는 t 배율기다(실측 se_EW/se_capw 중앙 0.729 = t x1.37). 여기 관측된 배율은 1.426/1.294 = 1.10 로 그 전형값보다 작다 — 즉 배율을 걷어내면 EW-대비가 cap-w 대비보다 강하지 않다. '벤치를 바꿨더니 살아났다' 로 읽으면 안 된다."),
  no_signal_control_gate = list(
    mandatory_for = "롱온리 셀 2·4 (measurement-graduation §3 무신호 대조 의무)",
    control_spec = S3$no_signal_control$control_spec_v10,
    control_beta_check = S3$no_signal_control$control_beta_check,
    control_beta_verdict = "PASS — 대조군 β 1.072(cap 1.00) / 1.026(cap 0.20). 1/20 의 홀딩월 라벨 정렬 결함(β 0.041) 재발 없음. 라벨 = 시그널월 t 의 다음 캘린더월(t+1) 로 넘겼다.",
    cell4 = list(diff_ann = num(ns4$vs_cap1_00$diff_ann), diff_nw_t = num(ns4$vs_cap1_00$diff_nw_t),
                 corr = num(ns4$vs_cap1_00$corr), verdict = ns4$vs_cap1_00$verdict),
    cell2 = list(diff_ann = num(ns2$vs_cap1_00$diff_ann), diff_nw_t = num(ns2$vs_cap1_00$diff_nw_t),
                 corr = num(ns2$vs_cap1_00$corr), verdict = ns2$vs_cap1_00$verdict),
    consequence = "두 롱온리 셀 모두 INDISTINGUISHABLE_FROM_NO_SIGNAL → screen-tier 등재 불가. cell4 의 양(+) 수치를 알파로 인용할 수 없다."),
  regime_boundary_cell_specific = list(
    method = S3$regime_definition$method,
    beta_controlled_residual_ann = S4$beta_controlled_regime$resid_ann,
    beta_controlled_residual_nw_t = S4$beta_controlled_regime$resid_nw_t,
    recovery_axis = "지지(방향) — β-통제 잔차 숏 보유 셀 −30.6%/−28.3%/yr vs 롱온리 셀 +9.9%/+14.2%/yr 로 부호가 셀-특정으로 갈린다. 단 개별 |t| 는 1.16/1.09 로 유의 미달.",
    crisis_axis = "기각 — 설계는 '전 셀 약화' 를 예측했으나 실측은 롱온리 셀만 유의 약화(cell2 −17.8%/yr t −2.45 · cell4 −18.0% t −2.28)이고 숏 보유 셀은 무변(+2.3%/+2.9%, t 0.26/0.32)이다. 국면 약화의 소유자가 예측과 반대다.",
    verdict = "regime_scope 부분 지지 — recovery 경계는 셀-특정으로 살아 있고, crisis 경계('전 셀 약화')는 반증됐다. 오버레이 미적용(S0/S1 준수) — 이 라벨은 어떤 셀의 비중에도 쓰이지 않았다."),
  attribution_conclusion = list(
    answer = "신호",
    one_line = "기저 F 는 숏 레그가 알파를 파괴해서도, 데실이 너무 넓어서도 아니다 — 형태를 최대로 교정한 cell4 조차 β-통제 α t 1.205 · rank-IC 0.0072 · OOS retention −0.066 · 무신호 대조 구별 불가이고, 기저의 음(−) PORT_t 자체는 β 0.199 짜리 롱숏을 β 1 벤치로 재는 basis 산술(−9.38%/yr)이 만든 것이다.",
    arithmetic = list(
      cell1_active_ann = num(c1$mean_active_net_ann), cell1_alpha_ann = num(c1$beta_controlled$alpha_ann),
      cell1_beta = num(c1$beta_controlled$beta), cell1_beta_contrib_ann = num(c1$beta_controlled$beta_contrib_ann),
      cell4_active_ann = num(c4$mean_active_net_ann), cell4_alpha_ann = num(c4$beta_controlled$alpha_ann),
      cell4_beta = num(c4$beta_controlled$beta), cell4_beta_contrib_ann = num(c4$beta_controlled$beta_contrib_ann),
      form_change_total_active_ann = num(c4$mean_active_net_ann) - num(c1$mean_active_net_ann),
      of_which_beta_basis = num(c4$beta_controlled$beta_contrib_ann) - num(c1$beta_controlled$beta_contrib_ann),
      of_which_alpha = num(c4$beta_controlled$alpha_ann) - num(c1$beta_controlled$alpha_ann),
      note = "형태 전면 교정의 활성수익 개선 +13.77%/yr 중 73%(+10.06%p)가 β basis 이고 27%(+3.71%p)만 α 다. 그 α 차조차 t 문턱 밖."),
    residual_uncertainty = "축 A 는 '미결' 이다(검정력 22.5%) — 숏 레그 축을 통계적으로 닫은 것이 아니다. 다만 KR 공매도 제약상 숏은 실투 경로가 아니므로 잔여 18회의 자원을 여기에 더 쓸 근거는 약하다.",
    consequence_for_remaining_attempts = "'형태 교정' 축(숏 제거·집중도)은 소진에 가깝다. 잔여 시도는 신호 자체(재료·창·표적)를 바꾸는 축으로 가야 한다."))

## ── 도달가능성 / 창 ──
reach <- S5$reachability_ceiling

alpha_validation <- list(
  schema = "alpha_validation/v1", task_id = "WT-R20260829_002", wt_type = "reinforcement",
  as_of_date = "2026-08-29", attempt = "2/20", axis = "weighting(형태) — 숏 레그 x 집중",
  base = list(base_id = "RP_20260829_122020_9192", base_grade = "F",
              base_reported_port_t = -1.291, base_mdd = 0.867, base_cagr = 0.010),
  metric_type = "canonical_screen",
  metric_type_note = "선택/보고 권위 = canonical_screen_bt 실측 경로(아래 parity 로 실증). admission authoritative 아님(그건 forge build_bt_result). 등급 권위 = essence_score.R — 본 산출물은 등급을 선언하지 않는다.",
  measurement_engine = list(
    description = "4셀 공통 엔진 — 월간 패널 x 비중, delta 기반 15bps, contract build_benchmark_compare 경유.",
    positive_control = S2$parity,
    positive_control_note = "★cell4(top-25 롱온리)를 canonical_screen_bt(top_n=25) 와 대조해 max|Δret_net| = 0.000e+00 · |ΔPORT_t| = 0.000e+00 (259/259 개월). 즉 본 엔진은 canonical 경로의 롱숏·가변데실 확장이며, 확장분에 대해서만 계약 밖이다. 이 양성 대조 없이는 셀 1·2·3 의 수치를 canonical 급으로 인용할 수 없다."),
  fixed_axes = list(
    signal = "기저 엔진 stage_artifacts/replication/_pilot/fe_jt1993_momentum.R 그대로 (J=6 형성 · skip 1M · 월말 시그널). 4셀 전부 동일 — 설계의 제3축(신호) 교란 차단.",
    universe = "K200 ∪ KQ150 (PIT 시변 멤버십)", window = "2005-01-31 ~ 2026-08-28 · 259 수익월",
    cost = "15bps one-way, delta 기반 (v2.4_kr_retail_15bps 규약)",
    liquidity = "20일 평균 거래대금(t-1) >= 2e8 KRW — liq_ruler='adv20_t1'(헌법 자, source=injected_adv20). 4셀 전부 동일 적용.",
    weighting = "레그 내 EW", rebalance = "monthly",
    eligible_names = list(median = S2$meta$elig_names_median, min = S2$meta$elig_names_min, max = S2$meta$elig_names_max)),
  cell_profiles = list(
    cell1_LS_decile = list(profile = "replication", axis_violations = c("short leg 보유 — long_only_mandate 위반", "n_max 70 > 25 위반"),
                           tradability = "실투 불가 — 재현·대조 전용"),
    cell2_LO_decile = list(profile = "replication_diagnostic", axis_violations = c("n_max 35 > 25 위반"),
                           tradability = "실투 불가 — 진단 전용"),
    cell3_LS_top25  = list(profile = "replication_diagnostic", axis_violations = c("short leg 보유 — long_only_mandate 위반", "n_max 50 > 25 위반"),
                           tradability = "실투 불가 — 진단 전용"),
    cell4_LO_top25  = list(profile = "production", axis_violations = character(0),
                           tradability = "유일한 실투형 셀 — long-only · n_max 25 · Sigma w = 1 · 개별 비중 상한 없음(v10)"),
    short_leg_feasibility = "★숏 보유 셀(1·3)은 KR 공매도 제약을 무시한 가정 위에 서 있다: 개인 접근 제한 · 소형주 차입 풀 부재 · 2023-11~2025 전면금지 구간 포함. 차입비용·업틱룰·차입 가용성 전부 0 으로 가정했다. 이 두 셀의 어떤 수치도 실투 성과로 읽어서는 안 되며, 본 라운드에서 이들의 역할은 축 분해의 대조항뿐이다."),
  cells = S2$cells,
  contrasts = S2$contrasts,
  preregistered_verdicts = verdicts,
  base_reproduction = S4$base_reproduction,
  base_reproduction_verdict = "PASS — cell1 을 기저 규약 쪽으로 되돌린 4변형의 PORT_t 가 −1.120 ~ −1.465 이고 기저 보고치 −1.291 이 그 구간 안에 있다. 차이의 원인은 (a)유동성필터 추가 (b)벤치(cap-w 유니버스 프록시 vs KOSPI200 지수) (c)일간 하네스 vs 월간 패널 — 셋 다 4셀에 공통이라 축 대비는 상쇄된다.",
  regime_and_fingerprints = list(
    regime_definition = S3$regime_definition,
    fingerprint_a = S3$fingerprint_a_short_leg_rebound,
    fingerprint_b = S3$fingerprint_b_loser_small_tilt,
    regime_by_cell_raw_active = S3$regime_cell_specific,
    regime_by_cell_beta_controlled = S4$beta_controlled_regime),
  no_signal_control = S3$no_signal_control,
  advisory_battery = c(S3$advisory_battery, list(post_neutralization = S6)),
  reachability_ceiling = c(reach, list(
    verdict = "이 창에서 PORT_t 2.95 는 원리적으로 도달 가능하다 — 필요 활성수익 +13.25%/yr, 관측 +5.82%/yr (44%). 즉 본 미달은 '창이 짧아서' 가 아니라 '효과가 작아서' 다. (단 축 A/B 대비 자체는 여전히 미결 구간)")),
  pit = list(
    hard_gate = S4$pit_gate,
    hard_gate_note = "detect_lookahead(fe_jt1993_momentum.R) CLEAN · 위반 0 (45줄 스캔)",
    c1 = "full-sample 통계 미사용 — 시그널은 t-2..t-7 월간수익 shift 만. 단면 z/랭크는 당월 단면 내부 연산(미래 미참조).",
    c2 = "same-day 순환참조 없음 — 시그널일 t 의 수익은 t+1 캘린더월 forward(build_monthly_forward_returns).",
    c4 = "재무제표 리프 미사용 (가격 파생 신호 단독) — 해당 없음",
    c5 = "오버레이 미적용(S0/S1 금지 준수). 국면 라벨은 사후 귀속 진단이며 어떤 셀의 비중에도 진입하지 않았다.",
    c6 = "survivorship — K200/KQ150 멤버십을 각 시그널일의 실제 값으로 시변 적용(RAWDATA PIT 멤버십). 상장폐지 종목은 그 시점 유니버스에 그대로 남는다.",
    c10 = "유동성 t-1 — build_adv20_t1() 이 당일을 창에서 제외(shift 1)한 20일 평균 거래대금. liq_ruler='adv20_t1' 라벨 기록.",
    c13 = "NEGATE/FLIP 미사용 — Score 부호는 엔진 정의 그대로(승자=고득점).",
    c14 = "해당 없음 — Factor DB IC 히스토리 미소비.",
    c15 = "★부분 적용 — 본 신호는 Factor DB parquet 이 아니라 RAWDATA 가격 패널에서 기저 엔진이 직접 산출한다(강화 시도의 신호 고정 의무). load_month_factors() 경유 대상 리프 사용 0건이므로 C15 위반 없음.",
    stored_panel_reuse = "없음 — 저장 파생 패널 미사용. 패널은 본 라운드에서 RAWDATA 로부터 재빌드(동월 look-ahead 2.08x 전례 회피)."),
  challenge_flags = c(
    "[RF-A5 인접] cell4/cell2 보유의 cap-tier OTHER(31위 밖) 비중 평균 91.2%/90.8% — 유동성 하한(2e8)은 전부 통과하나 대형주 노출은 사실상 없다. 무신호 대조 구별불가와 함께 읽을 것.",
    "[미결 라벨 2건] 축 A(검정력 22.5%) · 축 B(35.9%) 둘 다 3단 처분 (b) 조건부 구간이다. '효과 없음' 으로 승격하지 말 것 — 본 라운드가 남기는 것은 귀속 산술(β basis 분해)·기전 지문 2종·재사용 패널이다.",
    "[cell1 != 기저 bit-parity] 유동성필터 추가 + 벤치/하네스 차이로 기저와 동일 수치가 아니다(−1.120 vs −1.291). 재현 대조 4변형으로 구간 포함을 실증했으나, 기저 수치를 인용할 때는 기저 산출물을 인용할 것.",
    "[숏 실행가능성] 셀 1·3 은 KR 공매도 제약(전면금지 구간 포함)·차입비용 0 가정 위에 있다 — 진단 전용.",
    "[국면 라벨 품질] regime 라벨은 벤치 실현수익 + 시그널시점 낙폭으로 만든 사후 귀속 라벨이다. 라벨 품질이 병목이라는 기존 실측(메모리)이 그대로 적용되며, 그래서 1차 판정은 무조건부 4셀 대비로 두었다.",
    "[falsification 형식 전사] alpha_hypothesis.json 의 falsification 은 {observable, field_dictionary_refs, reject_if} 객체인데 schema 는 필드 지목 객체배열을 요구한다. 내용을 재작성하지 않고 필드별로 분해 전사했다(원문은 alpha_hypothesis.json 이 정본).",
    "[대안 승계] 설계자가 보관한 대안 4건(6M 호라이즌 · size 층별 1차검정 · crash-state 1차검정 · 비중방법론 축)은 잔여 18 시도 후보로 그대로 유지."),
  selection_objective = "canonical_port_t",
  n_trials = 4L, selection_type = "chain",
  selection_type_rationale = "사전등록 2x2 직교 4셀 — argmax/threshold-pick 부재. 셀 선택이 아니라 축 분해다. DSR 게이트 부적용(measurement-graduation §3), 수치는 진단 산출(0.598).",
  grade_declaration = "없음 — 등급 권위는 essence_score.R 하나이며 alpha 구간은 등급을 선언하지 않는다. 본 라운드는 risk/optimizer/forge 스폰 근거도 만들지 못했다(무신호 대조 구별불가 + 축 A 기각 + 축 B 미결)."
)
write_json(alpha_validation, file.path(OUT, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S7] alpha_validation.json written\n")

## ── alpha_package.json (AST v1.1 3층) ───────────────────────────────────────
av <- setNames(as.list(round(CS$alpha_hat, 6)), CS$Ticker)
cv <- setNames(as.list(round(CS$confidence, 4)), CS$Ticker)
H <- HYP$selected
pkg <- list(
  task_id = "WT-R20260829_002", as_of_date = "2026-08-29", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = "2026-08-28", decision_ts = "2026-08-28"),
  hypothesis = list(
    statement = H$hypothesis_description,
    mechanism = H$mechanism,
    falsification = list(
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Ret",
           expectation = "숏 레그 원인이 참이면 패자 데실(cell1 숏 레그)의 손실이 시장 반등월에 집중되고 무국면 균일이 아니어야 한다. [실측] recovery 더미 계수 −0.0817/월 t −4.403 · BM 통제 후 −0.0427/월 t −2.367 → 성립."),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "BM_Ret",
           expectation = "반등월 식별(직전 드로다운 상태에서 벤치 수익 상위 월)의 기준 필드. 시장 방향을 거의 고정한 대조(expansion bm +59.5%/yr vs recovery +62.8%/yr)에서 패자 수익이 +34.9% vs +94.3% → 반등 특이성 성립."),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Size",
           expectation = "패자 데실 구성이 Size 하위(소형) 편중이어야 한다. [실측] size_pct 패자 0.634 vs 승자 0.462 (차 +0.169, NW-t +10.03) · 유니버스 대비 +0.133 (NW-t +17.25) → 성립."),
      list(field = "A1_RAWDATA_OHLCVS_daily", field_column = "Vol",
           expectation = "유동성 하한(20일 평균 거래대금 t-1 >= 2e8)의 산출 필드 — 소형 편중이 거래 불가 구간에서 온 것이 아님을 보증. 4셀 공통 적용, 적격 종목 월 중앙 343종.")),
    regime_scope = H$regime_scope),
  ## ★AST 는 두 방언을 동시에 싣는다 — schema(#/definitions/ast_node)는 args 배열을,
  ##   정적검증기(02_Infrastructure/ast/ast_verify.py)는 children + 명명 파라미터(k/window)를
  ##   요구한다. 한 방언만 실으면 게이트는 통과하되 검증기가 리프 0개를 순회해
  ##   "빈 검증"이 된다(실측: TRAVERSAL 리프 0개 · 노드 형상 오류 6). 둘 다 실어 실제로 검증되게 한다.
  ast_dialect_note = "schema=args / ast_verify=children+k·window 두 방언 병기 (계약 표면 분열 회피)",
  factors = list(local({
    lf <- list(leaf = "SPECIAL_OP",
               escape_contract = list(escape_type = "SPECIAL_OP",
                 op_code_path = "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R (mret 블록 — 캘린더월 복리 log(1+mr))",
                 walk_forward = TRUE),
               op_code_path = "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R",
               walk_forward = TRUE)
    lag <- list(op = "TS_LAG", args = list(lf, 2), children = list(lf), k = 2L, unit = "m")
    root <- list(op = "TS_SUM", args = list(lag, 6), children = list(lag), window = 6L)
    list(factor_id = "F1_JT1993_mom_J6_skip1", ast = root,
         role = "core_signal", restatement_exposure = 0L)})),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Ret", availability_rule = "fixed: 일간 종가 확정 T+0, 시그널은 t-2..t-7 월만 참조(shift)", restatement_prone = FALSE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Vol", availability_rule = "fixed: 일간 거래량 T+0 — adv20 은 당일 제외 shift(1)", restatement_prone = FALSE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily:Size", availability_rule = "fixed: 시총 T+0 (cap-tier 진단·지문 (b) 전용, 신호 미진입)", restatement_prone = FALSE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily:BM_Ret", availability_rule = "fixed: 벤치 일간수익 T+0 (사후 국면 라벨·β 통제 전용, 신호 미진입)", restatement_prone = FALSE),
      list(leaf = "SPECIAL_OP", availability_rule = "코드 경로 escape — 캘린더월 복리는 t-2 이전 월만 입력. detect_lookahead CLEAN.", restatement_prone = FALSE)),
    verdict = "clean",
    notes = "재무·컨센서스 리프 0 — 1/20 의 fail_lookahead_suspected(C01_SUE 컨센서스 축) 이 본 라운드에는 존재하지 않는다. 가격 파생 단독."),
  alpha_vector = av, confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT_R20260829_002/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "Momentum", proxy = "J6/skip1 누적 로그수익 (JT1993 6-6 계열)",
    formula = "sum_{k=2..7} log(1 + monthly_ret_{t-k})",
    lag_rule = "price t-1 close · 형성기 t-2..t-7 (직전 1개월 skip)",
    winsorization = "none (엔진 원형 유지 — 신호 고정 의무)",
    neutralization = "none (진단으로 size 중립화 IC 병기: 0.0030, retention 0.414)",
    economic_rationale = "behavioral",
    weight_theta = 1.0,
    references = list(
      "Jegadeesh & Titman (1993, JF 48(1):65-91) https://www.bauer.uh.edu/rsusmel/phd/jegadeesh-titman93.pdf",
      "Israel & Moskowitz (2013, JFE 108(2):275-301) https://www.sciencedirect.com/science/article/pii/S0304405X12002401 (공개판 https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2089466)"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = num(c4$port_t_capw),
    canonical_port_t_pvalue = num(c4$port_p),
    canonical_n_months = 259L,
    canonical_port_t_note = "실투형 셀(cell4) 값. 진단 셀 = cell1 −1.120 / cell2 +0.961 / cell3 −0.803.",
    rank_ic = num(S6$rank_ic_raw), icir = num(S3$advisory_battery$icir),
    harvey_t_stat = num(S6$rank_ic_raw_t_nw),
    harvey_t_stat_note = "rank-IC 월계열의 NW lag-3 t. advisory — portfolio-alpha t 와 구분(measurement-graduation §2). 다중검정 haircut 불요(문턱 근처 아님).",
    portfolio_alpha_t_beta_controlled = num(c4$beta_controlled$t_alpha),
    portfolio_alpha_beta_controlled_ann = num(c4$beta_controlled$alpha_ann),
    beta = num(c4$beta_controlled$beta),
    monotonicity = num(S3$advisory_battery$monotonicity_spearman),
    subperiod_stability = num(S3$advisory_battery$subperiod_stability),
    turnover_proxy = num(c4$turnover_annual),
    net_sr = num(c4$net_sr),
    deflated_sharpe_ratio = num(S3$advisory_battery$dsr_diagnostic$cell4),
    oos_retention_approx = num(S3$advisory_battery$oos_retention_approx$cell4),
    post_neutralization_ic = num(S6$post_neutralization_ic),
    alpha_inheritance_cor = 1.0,
    alpha_inheritance_note = "기저 RP_20260829_122020_9192 와 신호 동일(엔진 그대로 승계) — 본 라운드가 바꾼 것은 형태(레그·집중)뿐이다. wt_type=reinforcement 이므로 신규 alpha 발굴이 산출물이 아니며 alpha_discovery_certificate 미발급이 정상.",
    harvey_t_specs_pass_count = 0L),
  alpha_discovery_count = 0L,
  selection_objective = "canonical_port_t",
  challenge_flags = alpha_validation$challenge_flags,
  validation_ref = "stage_artifacts/WT_R20260829_002/alpha_validation.json",
  attribution_conclusion = verdicts$attribution_conclusion
)
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("[S7] alpha_package.json written\n")

## ── lineage (write_json 이후 순서 — L-194) ──
source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-R20260829_002", package_type = "alpha_package",
  method_selected = "IM2013 4셀 직교 분해 (숏 레그 x 집중) — 신호 = JT1993 J6/skip1 고정",
  input_file_paths = c(
    file.path(ROOT, "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R"),
    file.path(ROOT, ".cache/rawdata.parquet"),
    file.path(MBX, "alpha_hypothesis.json"),
    file.path(OUT, "alpha_scores.parquet"),
    file.path(OUT, "alpha_validation.json")))
cat("[S7] lineage recorded\n")
