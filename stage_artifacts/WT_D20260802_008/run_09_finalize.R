## run_09_finalize.R — NP-2 alpha_vector / alpha_validation / alpha_package(mailbox) + lineage
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_008"
MB <- "qepm/mailbox/worktask/WT-D20260802_008"
TID <- "WT-D20260802_008"

## ★ 대상 파일을 read 하지 않는다 — Windows arrow mmap 열림 상태에서 같은 경로 write 가
##   IOError 1224 로 실패(WT-002 run_09 실측). run_04 와 동일 레시피로 원천에서 재구성.
SI0 <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
A <- as.data.table(read_parquet(file.path(TD, "cov_panel.parquet"))); A[, Date := as.Date(Date)]
setorder(A, Date, Ticker)
A <- merge(A, as.data.table(SI0$fwd_ret)[, .(Date, Ticker, Ret_1m)], by = c("Date", "Ticker"), all.x = TRUE)
A[, gate := frank(-cov_l0, ties.method = "first") <= ceiling(.N / 2), by = Date]
setnames(A, "score", "alpha_score_base")
A <- A[, .(Date, Ticker, alpha_score_base, cov_l0, cov_l1, gate, adv, Size, Ret_1m)]
AR <- readRDS(file.path(TD, "arms_results.rds")); DG <- readRDS(file.path(TD, "diagnostics.rds"))
AD <- readRDS(file.path(TD, "adversarial.rds")); AT <- readRDS(file.path(TD, "ast_run.rds"))
PR <- readRDS(file.path(TD, "premise.rds"))

## confidence (WT-002 동일 정의)
setorder(A, Ticker, Date)
A[, pct := frank(alpha_score_base, ties.method = "first") / .N, by = Date]
A[, pct_prev := shift(pct), by = Ticker]
A[, rank_stab := fifelse(is.na(pct_prev), 0.5, 1 - abs(pct - pct_prev))]
A[, liq_ok := as.numeric(is.finite(adv) & adv >= 2e8)]
A[, conf := pmin(1, pmax(0, 0.5 * 1 + 0.3 * rank_stab + 0.2 * liq_ok))]
A[, pct_prev := NULL]
write_parquet(A, file.path(TD, "alpha_scores.parquet"))

d_last <- max(A$Date)
cs <- A[Date == d_last][order(-alpha_score_base)]
av <- list(
  as_of_sig_date = as.character(d_last),
  basis = "score_eff (STR_1715 core, cleanT1 production_parity_verified) — 본 라운드 미가공 상속",
  n_names = nrow(cs), gate_pass_n = sum(cs$gate),
  alpha_vector = setNames(as.list(round(cs$alpha_score_base, 6)), cs$Ticker),
  confidence_vector = setNames(as.list(round(cs$conf, 4)), cs$Ticker),
  gate_flag = setNames(as.list(cs$gate), cs$Ticker),
  units = "cross-sectional composite z (기대초과수익 순서통계 — 수익률 단위 아님)",
  downstream_note = "verdict = config-scoped negative (게이트 불활성). 게이트 미적용판이 base 이며 downstream 소비 권고 없음.")
write_json(av, file.path(TD, "alpha_vector_2026_03_31.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("[alpha_vector] %s n=%d gate_pass=%d\n", d_last, nrow(cs), sum(cs$gate)))

sm <- AR$summ; gv <- function(a, b) sm[arm == a & basis == b, port_t]
pd <- as.data.table(AR$paired)
pl <- AR$placebo

VAL <- list(
  task_id = TID, fq_id = "FQ-084-NP2", parent_wt = "WT-D20260802_002",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type = "canonical_screen",
  instrument = "02_Infrastructure/contracts/canonical_screen_bt.R::canonical_screen_bt (top_n=25, 15bps, liq 2e8)",
  window = list(n_months = 268L, from = "2004-01", to = "2026-04",
                selection_type = "chain", n_trials = 1L, is_only_selection = TRUE,
                holdout_consumed = FALSE),
  preregistration = file.path(TD, "preregistration.json"),
  harness_anchor = list(
    a_base_capw = gv("A_base", "capw"), wt002_reference = 3.47810711240596,
    exact_match = abs(gv("A_base", "capw") - 3.47810711240596) < 1e-6,
    note = "WT-002 BASE(gate_panel ∩ liq 2e8) verbatim 재사용 — A_base 268개월 cap-w PORT_t 소수점 일치"),
  premise_check = list(
    premise = "배포 유니버스에 애널리스트 커버리지 0 종목이 존재한다 (WT-002 CF-08 형 선검증)",
    share_cov0 = PR$share_cov0, share_cov_le1 = PR$share_cov_le1,
    top25_share_cov0 = PR$top25_share_cov0, top25_share_le1 = PR$top25_share_le1,
    cor_cov_adv = PR$cor_cov_adv, cor_cov_size = PR$cor_cov_size,
    verdict = "PREMISE_HOLDS — cov0 = 20.1% 종목-월 (top-25 내 11.4%). WT-002 외국인 축(94.3% 포화 공허)과 달리 전제가 실재 → 측정 진행."),
  primary_result = list(
    A_base_capw = gv("A_base", "capw"), B_cov_capw = gv("B_cov", "capw"),
    A_base_ewuni = gv("A_base", "ewuni"), B_cov_ewuni = gv("B_cov", "ewuni"),
    paired_B_minus_A = as.list(pd[arm == "B_cov", .(mean_diff_ann, nw_t_diff)]),
    prereg_necessary_criterion = "B_cov > A_base AND paired NW-t >= 2.0",
    prereg_outcome = "FAILED — cap-w 점수치는 상회(3.922>3.478)하나 paired NW-t = -0.66 (알파 연 -1.3%p 감소, t 상승은 변동성 축소 산물). EW-uni basis 역전(3.310<4.218). placebo 분포 안.",
    dual_basis_agreement = FALSE,
    dual_basis_note = "cap-w 점수치 상승 vs EW-uni 하락 — basis 불일치 자체가 '개선 없음'의 증거(사전등록 paired 기준이 판정 권위)"),
  full_arms = sm,
  paired_vs_base = pd,
  placebo = list(n_draws = 20L, mean = mean(pl), sd = sd(pl),
                 q05 = unname(quantile(pl, .05)), q50 = unname(quantile(pl, .5)),
                 q95 = unname(quantile(pl, .95)), max = max(pl),
                 b_cov_position = "q50(3.576)~q95(4.315) 사이 = 무작위 절반 축소와 구분 불가(무의미)",
                 b_cov_low_position = "2.683 — q05(2.497) 위 하위꼬리 = 해악 판정도 불성립"),
  cap_tier = AR$cap_tier,
  advisory_battery = list(
    A_base = DG$batt_all[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability","post_neutralization_ic","post_neut_retention","n_months")],
    B_cov = DG$batt_gate[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability","post_neutralization_ic","post_neut_retention","n_months")],
    B_cov_low = DG$batt_low[c("rank_ic","icir","ic_nw_t","monotonicity","subperiod_stability","post_neutralization_ic","post_neut_retention","n_months")]),
  mechanism_diagnostics = list(
    ic_by_cov_quartile = DG$by_cov_quartile,
    ic_existence_boundary = list(cov0 = DG$ic_cov0, cov1plus = DG$ic_cov1p),
    top25_gate_pass_rate = DG$top25_pass,
    top25_pass_minus_drop_monthly = DG$top25_diff_mo, top25_pass_minus_drop_nw_t = DG$top25_diff_t,
    cov_standalone_rank_ic = DG$cov_ic, cov_standalone_ic_nw_t = DG$cov_ic_t,
    reading = "기전 반증 3중: ① 사분위 IC 역방향(Q4 고커버 최약 0.0324) ② cov==0 부분집합에서도 IC +0.0329 (t 3.47) 유의 — '커버리지 없으면 신호 미정의' 전제 기각 ③ top-25 통과-탈락 수익차 t +0.55 무의미"),
  adversarial = list(
    C1_join_scramble = list(concern = "as-of 조인 정렬 스크램블 (구축 중 자기적발)",
      detection = "cov~Size +0.016 비정상 + 연도별 중앙값 요동 → 원천 진단(삼성전자 연속 20명대)으로 조인 결함 귀속",
      resolution = "unkeyed on= 조인 + identical() 정렬 가드. 수리 후 cov~Size +0.736. arm 측정 전 적발 — 오염 산출물 0", verdict = "ACCEPTED_FIXED"),
    C2_integer_ties = list(concern = "정수 동률 분할 임의성",
      tie_at_cut_mean = AD$tie_at_cut_mean, port_t_ticker_reversed = AD$port_t_tierev,
      port_t_ast_path = AT$ast_port_t, jaccard_ast_vs_handbuilt = AT$jaccard_vs_handbuilt,
      verdict = "ACCEPTED_QUANTIFIED — B_cov 에 ±0.2 동률노이즈 내재, 세 변형 전부 placebo 안 = 판정 불변"),
    C3_export_gap_artifact = list(concern = "cov==0 이 export 갭 아티팩트일 가능성",
      d0_obs30_min = AD$d0_obs30_min, cov0_agree_30_60 = AD$cov0_agree_30_60, port_t_60d = AD$port_t_60d,
      verdict = "REBUTTED — 3축(밀도 min 16일 / 60d 일치율 99.03% / 60d 판 3.914 결과 불변)"),
    C5_metric_shopping = list(concern = "cap-w 점수치 상승(3.92>3.48)을 개선으로 오독",
      verdict = "REBUTTED_BY_PREREG — paired -0.66 + placebo 안 + EW-uni 역전. 사전등록 프레임이 사후 basis 선택 봉쇄")),
  pit_checks = list(
    coverage_file_max_date = PR$cov_file_max_date,
    staleness_note = "QuantiWise 수동 export — max(Date) 2026-07-24, 측정창 최종 d0(2026-03-31) 대비 충분. 라이브 소비 시 스테일 재확인 의무(원천 케이던스 구조 잔존).",
    lag1_stress_port_t = gv("B_cov_lag1", "capw"),
    lag1_note = "1개월 추가 지연판 3.767 vs 원판 3.922 — 안정적. 동월 누출 부풀림 징후 없음(애초 개선 자체가 없어 부풀림 대상 부재)."),
  ast = list(features = AT$features, op_counts = AT$op_counts,
             ast_path_port_t = AT$ast_port_t, jaccard_vs_handbuilt = AT$jaccard_vs_handbuilt,
             sidecar_live_with_ast = AT$sidecar,
             note = "WT-002 const-free 형과 동일 구조(WHERE/SIGN/CS_DEMEAN/CS_RANK) — 게이트 리프만 교체. 컴파일 경로 3.803 vs 손빌드 3.922 차이는 정수 동률 경계(Jaccard 0.9787) — C2 로 정량."),
  verdict = "CONFIG_SCOPED_NEGATIVE",
  verdict_detail = paste0(
    "사전등록 필요조건 미충족 — 커버리지 게이트는 개선도 해악도 아닌 불활성(paired -0.66, placebo 분포 안). ",
    "기전은 방향 반증: base 신호의 IC 는 고커버 구간이 아니라 저커버 구간에서 (약하게) 더 높고, cov==0 부분집합에서도 유의(+0.0329, t 3.47). ",
    "WT-002(외국인 축, 유의 해악 -1.945)와 합산 판정: '정보전달 인프라 존재' 계열 조건화 축은 독립 2회 실측으로 무효 확정(1해악+1불활성). ",
    "조건화 프레임 자체의 사망이 아니라 축 계열의 사망 — 알파가 인프라-존재 상위 구간에 살지 않는다는 것이 두 라운드의 공통 실측이며, ",
    "이 축 계열로 유니버스를 좁히는 시도는 재제안 금지(부활조건 명시)."),
  graduation_claim = "NONE — canonical screening 실측이며 forge-authoritative 값이 아니다. HARD 3종 판정 대상 아님.")
write_json(VAL, file.path(TD, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat("[SAVED] alpha_validation.json\n")

## ── alpha_package.json (mailbox) ────────────────────────────────────────────────
ast_inline <- fromJSON(file.path(TD, "ast_F1_cov_gated_score.json"), simplifyVector = FALSE)
PKG <- list(
  task_id = TID, as_of_date = "2026-08-02", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = as.character(d_last), decision_ts = as.character(d_last),
             note = "패널 최종 sig_date(d0) = 2026-03-31. 게이트 관측 = coverage as-of d0 (30일 창) — 홀딩월(2026-04) 데이터 0 사용."),
  hypothesis = list(
    statement = "base 신호(score_eff)는 컨센서스-파생이므로, 애널리스트 커버리지가 존재/충분한 종목으로 적용 유니버스를 조건화하면 동일 신호의 IC→PORT_t 전이가 개선된다. (실측 결과 기전이 방향 반증됨 — verdict_empirical 참조)",
    mechanism = list(
      agent = "셀사이드 애널리스트 — 리비전·목표가·추정치를 생산하는 정보 생산 주체. 커버리지가 없으면 base 신호의 컨센서스 성분(SUE/EPS수정/ESBR/TP갭)이 정의되지 않거나 스테일하다.",
      friction = "KR 소형·저관심 종목의 커버리지 공백(배포 유니버스 종목-월의 20.1% 가 커버리지 0 실측) — 신규 커버리지 개시는 느리고 리서치 비용 구조상 차익거래가 즉시 메꾸지 못한다.",
      path = "sig_date 시점 커버리지 존재 종목에서는 리비전 정보가 홀딩월 내 기관·외국인 매매로 가격 반영 → 실현 초과수익. 커버리지 부재 종목의 스코어는 스테일/노이즈로 top-25 슬롯만 소모."),
    falsification = list(
      list(field = "C-CONSENSUS-QW",
           expectation = "커버리지 상위 구간의 base-score rank-IC 가 하위 구간보다 높아야 한다.",
           measured = "Q1(저커버) 0.0423 / Q2 0.0593 / Q3 0.0412 / Q4(고커버) 0.0324 — 고커버 최약. 기전 REJECTED.",
           verdict = "FALSIFIED"),
      list(field = "C-CONSENSUS-QW",
           expectation = "커버리지 0 종목에서는 base 신호의 횡단 예측력이 소멸(IC ≈ 0)해야 한다.",
           measured = "cov==0 부분집합 rank-IC = +0.0329, NW t = +3.47 (266개월) — 유의하게 작동. '커버리지 없으면 신호 미정의' 전제 기각 (score_eff 의 defense 3팩터는 비컨센서스 원천).",
           verdict = "FALSIFIED"),
      list(field = "A9_liquidity_avgtv20_convention",
           expectation = "게이트가 유동성 필터 재명명이라면 동일 카디널리티 C_liq_matched 와 근사해야 한다.",
           measured = "B_cov 3.922 vs C_liq 3.681 (cap-w). cov~adv Spearman +0.613 (강상관 — WT-002 게이트의 +0.009 와 달리 유동성과 얽힘). paired 기준 양쪽 다 base 대비 무의미(-0.66 / -0.20).",
           verdict = "ENTANGLED_BOTH_INERT"),
      list(field = "A1_RAWDATA_OHLCVS_daily",
           expectation = "size 주입이라면 size 5분위 내 게이트(E_cov_sizeneut)에서 효과가 소멸해야 한다.",
           measured = "E_cov_sizeneut 4.102 (cap-w) — B_cov 3.922 보다 오히려 높으나 placebo q95(4.315) 안 + paired t +0.62 무의미. size 아티팩트 여부 판정 불요(개선 자체가 불성립).",
           verdict = "NO_EFFECT_TO_ATTRIBUTE")),
    regime_scope = list(
      holds_in = list("neutral", "expansion"),
      weakens_or_reverses_in = list("crisis", "post_2017_megacap_regime"),
      boundary_rationale = "메커니즘 도출 경계: 위기 국면은 커버리지 유무와 무관한 유동성 청산이 지배해 정보 생산의 가격 반영이 지연/압도된다. post-2017 은 커버리지가 초대형 반도체 축에 편중되어 커버리지 강도가 인덱스 편입/패시브 흐름의 대리변수로 변질된다. 실측 정합: B_cov 유니버스의 EW-대비 post2017 t = 2.343 vs base 1.943 — 경계 예측과 달리 게이트 유니버스가 소폭 낫지만 유의 차 아님.")),
  factors = list(list(
    factor_id = "F1_cov_gated_base_score",
    ast_file = file.path(TD, "ast_F1_cov_gated_score.json"),
    ast = ast_inline,
    role = "universe_conditioner",
    restatement_exposure = 1,
    note = "base 스코어 리프 verbatim 상속(신호 가공 0) — WHERE 조건부(커버리지 상위 50%)만 신규. WT-002 const-free 정본과 동일 연산 구조.")),
  combination_rule = "single_factor",
  verdict = "designed",
  verdict_empirical = "config_scoped_negative_mechanism_directionally_falsified",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "STORED_SCORE|stored_panel|alpha_score_base",
           availability_rule = "manual_export 파생 — 패널 Date = d0(월말 sig_date), factor_db T-1(off=0) 산출로 d0 가용",
           restatement_prone = TRUE,
           restatement_note = "수정주가·재무 restatement 노출. vintage pin 미적용 — 다중라운드 재판정 시 pin_cache 의무(§7)"),
      list(leaf = "STORED_SCORE|stored_panel|cov_l0",
           availability_rule = "manual_export(C-CONSENSUS-QW 일별 as-of) — 관측 = 마지막 Date <= d0 (30일 스테일 한도). 홀딩월 시작 전 관측 종료 → t-1 성립. 제공 시각 미상(C10 유사 경계)은 일 단위 as-of 로 흡수",
           restatement_prone = FALSE,
           restatement_note = "consensus incremental 은 Date > max append-only (과거행 불변, consensus_parser.R:249) — 소급수정 위험 낮음")),
    verdict = "warn_restatement",
    verdict_rationale = "base 스코어 리프 restatement_prone + vintage pin 미적용. look-ahead 징후 없음 — as-of 창이 홀딩월 이전 종료(코드 강제 + 정렬 가드) + lag1 판(3.767) 안정 + 60d 창 민감도(3.914) 통과.",
    field_map_note = "게이트 원천 리프 = C-CONSENSUS-QW coverage (field_map 등재 그룹). STORED_SCORE 패널 2종은 파생 — base 리프만 production_parity_verified."),
  alpha_vector = list(
    `_note` = "본 라운드는 신규 α̂ 를 생성하지 않는다 — base 스코어(production_parity_verified) verbatim 상속 + 적용 유니버스 조건화 검정. alpha_vector = 최종 d0(2026-03-31) 단면.",
    `_gate_applied` = FALSE,
    `_ref` = file.path(TD, "alpha_vector_2026_03_31.json"),
    `_inheritance` = "alpha_inheritance_cor = 1.0 vs incumbent (설계상 의도 — NP-2 가 base 신호 신규 생성을 금지)"),
  confidence_vector = list(
    `_note` = "종목별 confidence 는 alpha_scores.parquet 의 conf 컬럼 동봉. verdict negative 라 downstream 소비 전제 아님.",
    `_ref` = file.path(TD, "alpha_scores.parquet")),
  signal_matrix_ref = paste0("file://", file.path(TD, "alpha_scores.parquet")),
  factor_specs = list(
    list(factor_family = "Composite_EarningsRevision_Defense",
         proxy = "score_eff (STR_1715 core 4팩터 EW + defense 3팩터, regime-blended)",
         formula = "Z_Score_Aligned 합성 — core{C01_SUE, C02_EPS_Chg_1m, C04_ESBR, C06_TP_Gap} + defense{Q07, M08_ResidMom, Q25_Ohlson_O} 국면 블렌드",
         lag_rule = "factor_db T-1 (off=0). 연간 재무 = 익년 3/31, 분기 45d (C4)",
         winsorization = "factor_db 빌더 내부 (3std)", neutralization = "none (base 상속)",
         economic_rationale = "PEAD 계열 점진 반영 + 수익성 안정성 방어축 — 현직 book 검증 신호의 base 상속",
         weight_theta = 1.0,
         references = list("Bernard-Thomas 1989 (PEAD)", "Novy-Marx 2013 (profitability)"),
         source = "db_existing_production_inherited",
         redundancy_cluster_id = "CLUSTER_STR1715_CORE_INCUMBENT",
         redundancy_note = "incumbent 동일 클러스터 — 발굴 아닌 적용면 검증 (Factor Zoo 축소 정합)"),
    list(factor_family = "InformationInfra_AnalystCoverage",
         proxy = "COV_asof = coverage.parquet 마지막 관측(<= d0, 30일 창), 부재=0",
         formula = "CS_RANK(cov_l0) 상위 50% 게이트 (WHERE cond)",
         lag_rule = "as-of daily, Date <= d0 (t-1 대비 홀딩월)",
         winsorization = "none (순위 기반)", neutralization = "대조군 3종(C_liq/D_size/E_sizeneut) 병행",
         economic_rationale = "정보 생산 인프라의 존재/강도 — 컨센서스-파생 신호의 정의 가능성 마찰 (실측 반증됨)",
         weight_theta = 0.0,
         weight_theta_note = "α̂ 성분 아님 — 유니버스 조건(WHERE cond) 전용",
         references = list("Hong-Lim-Stein 2000 (analyst coverage and momentum)", "J. Jeong et al. PBFJ (parent WT-002 계보)"),
         source = "new_designed",
         redundancy_cluster_id = "CLUSTER_KR_CONSENSUS_META",
         redundancy_note = "컨센서스 메타데이터(커버리지 수) — 리비전 값 자체(C01/C02 등 base 성분)와 구분되는 메타 축")),
  diagnostics = list(
    canonical_port_t_nw_lag3 = gv("B_cov", "capw"),
    canonical_port_t_pvalue = sm[arm_key == "B_cov|capw", p],
    canonical_n_months = 268L,
    canonical_port_t_base_no_gate = gv("A_base", "capw"),
    canonical_port_t_delta = round(gv("B_cov", "capw") - gv("A_base", "capw"), 3),
    canonical_delta_note = "★점수치 delta +0.44 는 개선 아님 — paired NW-t -0.66 (알파 연 -1.3%p 감소, t 상승 = 변동성 축소 산물) + placebo 분포 안 + EW-uni 역전. 사전등록 판정 = FAILED.",
    metric_type = "canonical_screen",
    rank_ic = DG$batt_gate$rank_ic, rank_ic_base_no_gate = DG$batt_all$rank_ic,
    icir = DG$batt_gate$icir, icir_base_no_gate = DG$batt_all$icir,
    harvey_t_stat = DG$batt_gate$ic_nw_t,
    harvey_t_stat_note = "rank-IC NW lag-3 t (ADVISORY). base 7.70 → 게이트 4.62 — 게이트가 IC 계층에서도 신호를 깎는다(고커버 구간 IC 최약이므로).",
    monotonicity = DG$batt_gate$monotonicity,
    subperiod_stability = DG$batt_gate$subperiod_stability,
    turnover_proxy = sm[arm_key == "B_cov|capw", turnover_ann],
    turnover_proxy_unit = "annual (Σ|Δw|×12) — 10.79 < 제약 11.0/yr (base 12.45 는 초과 — canonical 규격 성질)",
    post_neutralization_ic = DG$batt_gate$post_neutralization_ic,
    post_neutralization_retention = DG$batt_gate$post_neut_retention,
    net_sr = sm[arm_key == "B_cov|capw", net_sr], net_sr_base_no_gate = sm[arm_key == "A_base|capw", net_sr],
    information_ratio = sm[arm_key == "B_cov|capw", ir],
    alpha_annualized = sm[arm_key == "B_cov|capw", alpha_ann],
    deflated_sharpe_ratio = 1.0,
    deflated_sharpe_ratio_note = "n_trials=1 (chain, 사전등록 단일 설계) → DSR 축퇴(정보량 없음). 게이트 부적용 — 과적합 방어 = 사전등록 + 대조군 + placebo 20-draw.",
    n_trials = 1L, n_iterations = 1L,
    ax001_v2_bad_normal_ic_ratio = DG$ax001_bad_norm,
    alpha_inheritance_cor = 1.0,
    alpha_inheritance_cor_note = "base verbatim 상속 (NP-2 설계 요구) — discovery certificate 요건(<0.95) 미충족, reclassify_proposal 을 governance_log 에 기록.",
    cor_vs_admitted_book = 1.0),
  ab_test_results = list(
    instrument = "canonical_screen_bt (top_n=25, 15bps, liq 2e8, 268m 2004-01~2026-04)",
    capw_basis = setNames(as.list(round(sm[basis == "capw", port_t], 3)), sm[basis == "capw", arm]),
    ew_universe_basis = setNames(as.list(round(sm[basis == "ewuni", port_t], 3)), sm[basis == "ewuni", arm]),
    placebo_random_50pct = list(n_draws = 20L, mean = round(mean(pl), 3), sd = round(sd(pl), 3),
      q05 = round(unname(quantile(pl, .05)), 3), q50 = round(unname(quantile(pl, .5)), 3),
      q95 = round(unname(quantile(pl, .95)), 3), max = round(max(pl), 3),
      interpretation = "B_cov 3.922 는 q50~q95 사이 = 무작위 절반 축소와 구분 불가. B_cov_low 2.683 은 q05 위 하위꼬리 — 해악 판정도 불성립. WT-002 와 대조: 외국인 게이트는 20/20 draw 아래(능동 해악), 커버리지 게이트는 분포 안(불활성)."),
    paired_nw_lag3_vs_base = setNames(
      lapply(seq_len(nrow(pd)), function(i) list(mean_diff_ann = round(pd$mean_diff_ann[i], 4), nw_t = round(pd$nw_t_diff[i], 3))),
      pd$arm),
    cap_tier_decomposition = list(
      tier_def = "MEGA = cap rank 1-10 / MID = 11-30 / OTHER = 31+",
      table = AR$cap_tier,
      interpretation = "게이트는 포트를 대형 tier 로 이동(MEGA 6.0%→11.3%, MID 8.7%→14.7%) — cov~Size +0.736 강상관의 기계적 귀결. OTHER tier 연율 gross 기여 19.8%→16.4% 감소. D_size_matched 와 tier 프로필 근사(MEGA 10.8%/MID 15.3%) = 게이트의 tier 이동은 사실상 size 이동."),
    ic_by_coverage_quartile = list(
      Q1_low = as.list(DG$by_cov_quartile[1, .(mean_ic, nw_t)]), Q2 = as.list(DG$by_cov_quartile[2, .(mean_ic, nw_t)]),
      Q3 = as.list(DG$by_cov_quartile[3, .(mean_ic, nw_t)]), Q4_high = as.list(DG$by_cov_quartile[4, .(mean_ic, nw_t)]),
      interpretation = "고커버 최약(Q4 0.0324) — WT-002 외국인 사분위와 동형의 역방향. 알파는 정보인프라 상위 구간에 살지 않는다(2축 재현)."),
    existence_boundary = list(
      cov0_ic = DG$ic_cov0, cov1plus_ic = DG$ic_cov1p,
      interpretation = "커버리지 0 부분집합에서도 IC +0.0329 (t 3.47) — score_eff 의 defense 축(비컨센서스)이 무커버 종목에서 판별력 유지. 가설의 friction 전제가 과대 서술이었음(challenge_note C4)."),
    mechanism_damage_path = list(
      top25_gate_pass_rate = round(DG$top25_pass, 3),
      top25_pass_minus_drop_monthly = round(DG$top25_diff_mo, 4),
      top25_pass_minus_drop_nw_t = round(DG$top25_diff_t, 2),
      interpretation = "게이트는 base top-25 픽의 46.3% 를 제거하나 제거분과 잔존분의 실현수익 차 t = +0.55 무의미 — 정보 없는 슬롯 교체(불활성)."),
    tie_robustness = list(port_t_ticker_reversed = AD$port_t_tierev, port_t_60d_window = AD$port_t_60d,
                          port_t_ast_path = AT$ast_port_t)),
  controls_verdict = list(
    vs_liquidity_filter = "ENTANGLED — cov~adv Spearman +0.613 (WT-002 게이트의 +0.009 와 달리 유동성과 강하게 얽힘). C_liq 3.681 과 paired 기준 양쪽 다 무의미 — '커버리지 조건화'의 상당분은 유동성/size 필터의 재표현이며 독립 정보가 없다.",
    vs_size_injection = "SIZE_DOMINANT — cov~Size +0.736. cap-tier 이동 프로필이 D_size_matched 와 근사. E_cov_sizeneut(4.102)이 B_cov 보다 높지만 placebo 안 — size 제거 후 잔여 커버리지 정보도 무의미.",
    vs_random_subsetting = "INDISTINGUISHABLE — placebo 20-draw 분포(mean 3.481, sd 0.546) 안. 능동 해악(WT-002)도 개선도 아닌 불활성."),
  pit_triple_check = list(
    t_minus_1_lag = "PASS — coverage as-of 관측이 d0 에서 종료, 홀딩월 d0+1 시작. lag1 판 3.767 안정(부풀림 대상 자체 부재).",
    quantiwise_export_lag = "ACKNOWLEDGED — coverage.parquet max(Date)=2026-07-24 (as_of 2026-08-02, 9일 지연). 백테 clean / 라이브 스테일 구조 잔존. verdict negative 라 배포 경로 진입 없음.",
    join_alignment = "PASS(수리 후) — 초판 rolling join 정렬 스크램블을 arm 측정 전 자기적발·수리 (challenge_note C1). identical() 정렬 가드 상설."),
  scope_limitation = list(
    threshold_scope = "게이트 = 월별 중앙값 분할(사전 고정). k명 존재형(cov>=k)·상위 30%/70% 등 다른 임계의 판결 아님 — 단 기전 반증(사분위 역방향 + cov0 IC 유의)은 임계 무관하게 '커버리지 상위 조건화' 방향 전체를 기각.",
    config_scope = "top-25 EW long-only / liq 2e8 / K200∪KQ150 / 15bps / 268m / base = STR_1715 core. 다른 base 신호·다른 종목수의 판결 아님."),
  selection_objective = "canonical_port_t",
  selection_type = "chain",
  alpha_discovery_count = 0L,
  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH", flag = "PREREGISTERED_HYPOTHESIS_FALSIFIED",
         detail = "necessary(paired NW-t >= 2.0) 미충족 — 실측 -0.66. 기전은 방향 반증(사분위 IC 역방향 + cov0 부분집합 IC 유의)."),
    list(id = "CF-02", severity = "HIGH", flag = "ROLE_CARD_MISMATCH_RECLASSIFY",
         detail = "wt_type=discovery 인데 alpha_inheritance_cor = 1.0 (설계 요구). certificate 자격 없음 — reclassify_proposal 기록 (WT-002 CF-02 동형)."),
    list(id = "CF-03", severity = "MEDIUM", flag = "GATE_VARIABLE_CONFOUNDED",
         detail = "cov~adv +0.613 / cov~Size +0.736 — WT-002 게이트(직교)와 달리 커버리지는 유동성·size 와 강하게 얽힘. '커버리지 조건화'는 상당분 size/유동성 필터의 재표현."),
    list(id = "CF-04", severity = "MEDIUM", flag = "INTEGER_TIE_NOISE",
         detail = "중앙값 경계 동률(평균 12.7종목)로 B_cov 값에 ±0.2 노이즈 — 티커역순 3.718 / AST 경로 3.803 / 원판 3.922. 전부 placebo 안 = 판정 불변."),
    list(id = "CF-05", severity = "LOW", flag = "JOIN_SCRAMBLE_CAUGHT_PREFLIGHT",
         detail = "as-of 조인 정렬 결함을 arm 측정 전 자기적발·수리 (음성 대조 상관 진단이 적발). 오염 산출물 0 — challenge_note C1."),
    list(id = "CF-06", severity = "INFO", flag = "PREMISE_HOLDS_UNLIKE_WT002",
         detail = "WT-002 CF-08(전제 공허)와 달리 커버리지 0 종목은 실재(20.1% 종목-월, top-25 내 11.4%) — 전제는 성립했으나 기전이 반증됨. ast_sidecar live_with_ast 19->20.")),
  next_probe = list(
    list(id = "NP-A", title = "컨센서스 분산(disagreement) 조건화 — 정보 불확실성 축 (WT-002 NP-2(b) 잔여 미검 절반)",
         rationale = "인프라-존재 축 2건(외국인·커버리지)은 무효 확정이나, 분산 축은 기전이 다르다 — 존재가 아니라 '의견 불일치의 크기'가 mispricing 진폭을 규정한다는 가설(Diether-Malloy-Scherbina 2002). esbr/escr·target_price 갭 분산 리프(C-CONSENSUS-QW 등재) 재사용, 동일 하네스. 사전 확률 갱신: 인프라-존재 2연속 무효 posterior 를 반영해 '개선' 아닌 '역방향(고분산 회피)' 도 사전등록 대칭 검정.",
         reusable_asset = "stage_artifacts/WT_D20260802_008/run_03_arms.R — arm 목록만 교체"),
    list(id = "NP-B", title = "커버리지 개시/증가 이벤트 신호 — 레벨 조건화가 아닌 변화 이벤트",
         rationale = "레벨 조건화는 size 와 +0.736 얽혀 불활성. 커버리지 *개시*(0→1+)는 이산 이벤트라 size 직교 여지 + 문헌 선례(coverage initiation drift). ★착수 전 hypothesis_index dedup 확인 의무 + FQ 등재 후 사전등록.",
         risk = "이벤트 희소성 — WT-007 CF-06 동형(월 커버리지 미달 시 portfolio-tier 측정 불성립)의 재현 위험을 census 로 선확인"),
    list(id = "NP-C", title = "cov 자체 standalone rank-IC +0.0350 (t 3.72) — screen-tier 등재만",
         rationale = "커버리지 수준 자체가 약한 순-예측 (attention premium 계열). rank-IC 는 ADVISORY 이고 IC→PORT_t 전이 벽 posterior 상 자본 경로 사전 확률 낮음 — screen-tier 후보 등재만, 자본 경로 진입 금지.",
         priority = "low")),
  consumption_surfaces = list(
    factor_ranking = "NO — 게이트는 랭킹을 개선하지 않음(IC 계층에서도 base 7.70 → 게이트 4.62 로 하락)",
    universe_filter = "NEGATIVE_KNOWLEDGE — '커버리지 상위 조건화'는 유니버스 필터 후보에서 제외 확정. 인프라-존재 계열 2축 연속 무효로 계열 자체를 큐에서 강등",
    overlay_regime_input = "NO — 커버리지는 시계열-국면 변수로서의 검정 미수행(미검 축이나 레벨이 size 대리라 사전 확률 낮음)",
    risk_model_beta_budget = "INPUT_AVAILABLE — cov~Size +0.736 실측과 cap-tier 이동 프로필은 risk agent concentration 진단의 '커버리지=size 대리' 근거로 전달 가치",
    monitoring_signal = "CANDIDATE — 보유 종목의 커버리지 급감(개시의 역) 은 monitoring tripwire 후보 (자본 판정 아님)",
    screening_label = "적용 — screen-tier 판정. graduation 경로 진입 없음",
    cross_mode_transfer = "조건화-검정 하네스(사전등록+카디널리티 매칭+placebo)는 WT-002 에서 재사용 실증 완료 — NP-A 에 3회차 재사용 예정"),
  revival_conditions = list(
    condition_1 = "base 신호가 순수 컨센서스-파생(예: 리비전 단일팩터)으로 교체될 때 — 본 반증의 핵심(기전5: defense 축이 무커버에서 판별력 유지)은 base 가 합성 신호라는 사실에 의존한다.",
    condition_2 = "커버리지 데이터가 추정기관 실명 단위(개시/철수 이벤트 식별 가능)로 확보될 때 — NP-B 의 이벤트 축이 레벨 축과 다른 판정을 받을 수 있다.",
    condition_3 = "배포 유니버스가 커버리지 공백이 지배적인 영역(예: KQ150 밖 소형)으로 확장될 때 — 단 이는 Production Constraints(고정 축) 밖이므로 mandate 변경 시에만."),
  lineage = list(
    base_panel = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
    screen_inputs = "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
    gate_source = ".cache/consensus/coverage.parquet (max Date 2026-07-24, 2,762,182 rows, 1,949 tickers)",
    parent_harness = "stage_artifacts/WT_D20260802_002/ (gate_panel.parquet BASE 재사용 + run_03_arms.R 하네스)",
    scripts = list(
      "stage_artifacts/WT_D20260802_008/run_01_premise.R",
      "stage_artifacts/WT_D20260802_008/run_02_source_diag.R",
      "stage_artifacts/WT_D20260802_008/run_03_arms.R",
      "stage_artifacts/WT_D20260802_008/run_04_diagnostics.R",
      "stage_artifacts/WT_D20260802_008/run_05_adversarial.R",
      "stage_artifacts/WT_D20260802_008/run_06_ast.R"),
    preregistration = file.path(TD, "preregistration.json"),
    challenge_note = file.path(TD, "challenge_note.md")),
  premise_check = list(
    premise = "애널리스트 커버리지 0 종목이 배포 유니버스에 존재한다 (WT-002 CF-08 형 선검증 의무)",
    test = "coverage as-of d0 (30일 창, 행 부재=0) — BASE 78,131 종목-월 전수",
    measured = "cov==0 = 20.13% / cov<=1 = 30.10% (연도별 11.6%~26.2% 안정). A_base top-25 내 cov==0 = 11.4%",
    verdict = "PREMISE_HOLDS",
    implication = "WT-002 외국인 축(94.3% 포화 = 전제 공허)과 달리 커버리지 공백은 실재하고 top-25 선택도 실제로 바꾼다(월평균 게이트 통과율 53.7%). 따라서 본 negative 는 '축의 판별력 부재'가 아니라 '기전 자체의 방향 반증'이다 — 더 강한 부정."),
  challenge_note_ref = file.path(TD, "challenge_note.md"))
write_json(PKG, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat("[SAVED] mailbox alpha_package.json\n")

## challenge_note mailbox 사본
file.copy(file.path(TD, "challenge_note.md"), file.path(MB, "challenge_note.md"), overwrite = TRUE)

## governance_log — reclassify_proposal (WT-002 동형)
gl_path <- file.path(MB, "governance_log.json")
gl <- fromJSON(gl_path, simplifyVector = FALSE)
gl$entries <- c(gl$entries, list(list(
  ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), agent = "alpha-research",
  event = "reclassify_proposal",
  detail = "wt_type=discovery 이나 alpha_inheritance_cor=1.0 (base verbatim 상속 = NP-2 설계 요구). 적정 분류 = 'universe_conditioning_test' (기존 4종 enum 밖 — WT-002 CF-02 동형). 사용자 confirm 대상.")))
write_json(gl, gl_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("[SAVED] governance_log reclassify_proposal\n")

## lineage (package write 이후 — L-194 순서)
ok <- tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = TID, package_type = "alpha_package",
    method_selected = "analyst-coverage conditioning gate (COV_asof top-50%) on inherited STR_1715 core score — prereg chain, n_trials=1",
    input_file_paths = c(
      "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
      "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
      "stage_artifacts/WT_D20260802_002/gate_panel.parquet",
      ".cache/consensus/coverage.parquet"))
  TRUE
}, error = function(e) { cat("[lineage] 실패:", conditionMessage(e), "\n"); FALSE })
cat(sprintf("[lineage] recorded=%s\n[DONE]\n", ok))
