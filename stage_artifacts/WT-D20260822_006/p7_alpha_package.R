## WT-D20260822_006 (FQ-246) P7 — alpha_package.json (AST v1.1 3층) + lineage
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260822_006"; MB <- "qepm/mailbox/worktask/WT-D20260822_006"
P  <- readRDS(file.path(OUT,"p2_arms.rds")); V3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
V4 <- readRDS(file.path(OUT,"p4_conduit.rds")); V5 <- readRDS(file.path(OUT,"p5_emit.rds"))
HY <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector=FALSE)$selected
BT <- P$BT; PRI <- V3$PRI; ADV <- V3$ADV; act <- P$act
LIVE <- V5$LIVE; last_d <- V5$last_d
PANEL <- "stage_artifacts/fq233_probe0_20260813/lane_a_feature_panel.parquet"
h_panel <- unname(tools::md5sum(PANEL))
h_sel   <- unname(tools::md5sum("stage_artifacts/WT-D20260822_004/p0_probe.rds"))

av <- setNames(as.list(round(LIVE$alpha_T3_DISP, 8)), LIVE$Ticker)
cv <- setNames(as.list(round(LIVE$confidence, 6)), LIVE$Ticker)
g <- function(a, f) as.numeric(PRI[contrast==a, get(f)])
adv <- function(a, f) as.numeric(ADV[arm==a, get(f)])

pkg <- list(
  task_id = "WT-D20260822_006",
  as_of_date = "2026-08-22",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = format(last_d), decision_ts = format(last_d),
    note = "월간 리밸 anchor. 상태변수 축1 은 당월 z 횡단면만의 함수(C0 와 동일 vintage), 축2 는 t-1 까지 실현된 수익 산포 — 홀딩월 자기 산포 미사용."),

  ## ── ① 가설층 (alpha-hypothesis 승계 — 자구 재작성 없음, 컨테이너 형태만 스키마 정합화) ──
  hypothesis = list(
    statement = HY$statement,
    mechanism = list(agent = HY$mechanism$agent, friction = HY$mechanism$friction, path = HY$mechanism$path),
    falsification = list(
      list(group_id = "FDB-B7_ic_history_monthly",
           expectation = "F1 조건부 매개 — 상태변수와 팩터별 차월 rank-IC 의 관계가 사전 선언 2군(유동성공급 g=+1 / 펀더멘털 g=-1) 간에 이질적이어야 한다. 월 단위 2군 IC 차 D_t 를 표준화 상태에 회귀한 기울기 NW lag-3 t >= +1.5. ★cluster_power.R 사전 선언이 계열-간(13 군집) 이질성 설계를 NO_GO 로 차단해 군집-내부 월-단위 설계로 교체함."),
      list(group_id = "FDB-B6_fdb_daily_store",
           expectation = "F2 처치 실효 — 상태 조건부 선택이 top-25 멤버십을 실제로 움직여야 한다(C0 대비 월별 Jaccard 중앙값 <= 0.90). 미이동 arm 의 성과 null 은 기전 반증이 아니라 처치 무력으로 라벨."),
      list(group_id = "A1_RAWDATA_OHLCVS_daily",
           expectation = "상태변수 축2(수익 횡단면 산포)의 원천 및 F2 멤버십 파생. 산포는 t-1 까지 실현분만 사용해야 하며 홀딩월 자기 산포 사용은 동월 look-ahead."),
      list(group_id = "A6_investor_flow_stock_daily",
           expectation = "F3 agent 실재 — 고분산 상태 월에 개인(Individual) 순매수의 횡단면 집중(HHI)이 상승해야 한다. 무상관이면 mechanism.agent 서술 기각(기전 강등, 가설 전체 기각 아님)."),
      list(group_id = "E6_sjm_bearprob",
           expectation = "보조 대조 arm 참조 전용 — 주 판정 미사용. bear_prob 은 팩터 수익에서 추정된 잠재 상태(성과-파생)라 alpha-hypothesis 가 주축에서 강등했다.")),
    regime_scope = list(
      holds_in = unlist(HY$regime_scope$holds_in),
      weakens_or_reverses_in = unlist(HY$regime_scope$weakens_or_reverses_in),
      boundary_rationale = HY$regime_scope$boundary_rationale),
    inheritance_note = "mechanism / falsification 취지 / regime_scope 는 alpha_hypothesis.json 자구 승계. alpha-research 는 스키마가 요구하는 컨테이너 형태(falsification: object → 필드-지목 객체배열)만 변환했고 내용을 재작성하지 않았다 — 변환 사실은 challenge_note.md 에 기록."),

  ## ── ② 팩터층 (AST) ──
  factors = list(
    list(factor_id = "F1_state_conditional_K5_composite",
         role = "core_signal",
         ast = list(op = "CS_ZSCORE", args = list(
           list(leaf = "SPECIAL_OP",
                escape_contract = list(
                  escape_type = "SPECIAL_OP",
                  op_code_path = "stage_artifacts/WT-D20260822_006/p2_arms.R::build() — 월별 선별 K=5 의 팩터 가중 w_k ∝ exp(u_agree_t·c̃_k + u_disp_t·g_k), 가중평균 후 결측 팩터는 분모에서 제외. u=0 에서 정확히 등가중(C0)으로 환원.",
                  walk_forward = TRUE,
                  walk_forward_detail = "상태 표준화는 확장창(expanding) 평균·sd 만 사용하고 [-2,+2] clip. 첫 36개월은 warm-up 으로 u=0. 미래 표본 미사용.")))),
         restatement_exposure = 0,
         economic_rationale = "슬롯 희소 top-25 long-only 에서 등가중 합의가 팩터 불일치 월에 solo-advocate 로 슬롯을 배분한다는 실측(FQ-244 R1a 중앙 64%)을 상태로 조절. 조건변수에 성과 미사용.",
         redundancy_cluster_id = "FQ244_C0_zscore_ew_cluster",
         cor_vs_baseline_active = as.numeric(V4$RED[arm=="T3_DISP", cor_active_vs_C0])),
    list(factor_id = "F2_selection_trajectory_inherited",
         role = "inherited_input",
         ast = list(leaf = "STORED_SCORE",
           escape_contract = list(
             escape_type = "STORED_SCORE",
             provenance = list(
               store_build_hash = paste0("panel:", h_panel, "|sel_rank:", h_sel),
               generator_code_path = "stage_artifacts/WT-D20260822_002 (FQ-237 SEL_RANK) → stage_artifacts/WT-D20260822_004/p0_probe.R → p0_probe.rds",
               generated_at = "2026-08-22"),
             production_parity_verified = FALSE)),
         restatement_exposure = 0,
         economic_rationale = "매월 320 팩터 풀에서 K=5 를 고르는 선별 궤적. 본 라운드는 이 축을 고정(FQ-237 소관)하고 그 위의 상태 조절만 움직인다.",
         redundancy_cluster_id = "FQ237_SEL_RANK",
         disclosure = "★production_parity_verified = FALSE — 저장 파생 패널이며 incumbent base 소비 자격 없음(measurement-graduation §7b). 본 라운드는 자본 주장을 하지 않으므로 연구용 소비만 성립한다. FIELD 리프로 위장하지 않고 STORED_SCORE 로 정직 선언(§4-1).")),

  combination_rule = "z_score_aligned_weighted_sum",
  verdict = "designed",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "SPECIAL_OP", availability_rule = "code-path; 확장창 표준화 = walk-forward, 미래 표본 미사용", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE", availability_rule = "fixed: 월말 anchor 시점 z 패널(FQ-237/FQ-244 승계, sig_date 컬럼 보유)", restatement_prone = FALSE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily", availability_rule = "fixed: t-1 close (축2 산포는 t-1 까지 실현분만)", restatement_prone = FALSE),
      list(leaf = "E6_sjm_bearprob", availability_rule = "fixed: effective_date(=Date+2영업일) < 홀딩월 첫날, locf, 진행월 소비 금지 (FQ-239 handoff 규약)", restatement_prone = FALSE),
      list(leaf = "A6_investor_flow_stock_daily", availability_rule = "fixed: t-1 settlement — F3 사후 진단 전용, 처치 입력 아님", restatement_prone = FALSE)),
    stress_measured = list(
      state_lag1_arm = "T2_LAG1",
      state_lag1_paired_t = g("T2_LAG1","t_nw3"),
      note = "상태를 1개월 지연시키면 -2.49%p/yr(t -1.670)로 오히려 악화 — 동월 누출 징후 부재. 지연판이 더 강했다면 타이밍 해석을 철회했어야 했다."),
    verdict = "clean"),

  ## ── ③ 산출층 ──
  alpha_vector = av,
  confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT-D20260822_006/alpha_scores.parquet (651,834행 · 9 arm · 221개월)",

  factor_specs = list(list(
    factor_family = "Composite_StateConditional",
    proxy = "state-modulated EW over monthly-selected K=5",
    formula = "score_i = Σ_k w_k·z_ik / Σ_k w_k ,  w_k ∝ exp(u_agree_t·c̃_k + u_disp_t·g_k)",
    lag_rule = "monthly anchor; 축1 = 당월 z 횡단면, 축2 = t-1 까지 실현 수익 산포",
    winsorization = "상태 표준화 clip [-2, +2] (스코어 자체 winsorize 없음 — C0 자구 유지)",
    neutralization = "none (C0 자구 유지 — 중립화 축은 본 라운드 미개봉)",
    economic_rationale = "오류 생성률(분산 관측) × 슬롯 배분 왜곡 규모(불일치 관측)의 곱 구조",
    weight_theta = 1.0,
    references = list("FQ-244 WT-D20260822_004 alpha_validation.json",
                      "FQ-116 WT-D20260802_021 (M1 slot 잠식)",
                      "WT-D20260803_005/007 (자격 = era 라벨, era 는 사전 관측 불가)"))),

  diagnostics = list(
    canonical_port_t_nw_lag3 = as.numeric(BT$T3_DISP$portfolio_alpha_t_nw_lag3),
    canonical_port_t_pvalue = as.numeric(BT$T3_DISP$portfolio_alpha_t_pvalue),
    canonical_n_months = as.integer(BT$T3_DISP$n_months),
    canonical_port_t_control_C0 = as.numeric(BT$C0$portfolio_alpha_t_nw_lag3),
    paired_vs_C0_annual_pct = g("T3_DISP","ann_pct"),
    paired_vs_C0_t_nw3 = g("T3_DISP","t_nw3"),
    paired_label = PRI[contrast=="T3_DISP", label],
    rank_ic = adv("T3_DISP","rank_ic"),
    icir = adv("T3_DISP","icir"),
    rank_ic_t_nw3 = adv("T3_DISP","ic_t_nw3"),
    harvey_t_stat = adv("T3_DISP","ic_t_nw3"),
    monotonicity = adv("T3_DISP","monotonicity"),
    subperiod_stability = adv("T3_DISP","subperiod_stability"),
    turnover_proxy = adv("T3_DISP","turnover"),
    post_neutralization_ic = NA,
    portfolio_alpha_t_vs_rank_ic_t_note = "★두 t 는 다른 양이다 (Cycle 2 교훈). rank-IC t 5.589 vs portfolio-alpha t 0.984 — IC→PORT_t 전이 벽의 재현. 판정 권위는 후자.",
    deflated_sharpe_ratio_diagnostic = as.numeric(V4$dsr),
    n_trials = 4L,
    selection_type = "preregistered_arms_no_champion",
    window_reachability_ORACLE_K_port_t = 4.64699909,
    headroom_recovery_pct = as.numeric(V3$REC[arm=="T3_DISP", recovery_share_of_headroom])*100,
    conduit_oracle_state_t = list(T2_form = as.numeric(V4$CON[contrast=="ORACLE_STATE_T2_form", t_nw3]),
                                  T3_form = as.numeric(V4$CON[contrast=="ORACLE_STATE_T3_form", t_nw3]),
                                  T1_form = as.numeric(V3$PC$t_nw3)),
    permutation_percentile = list(axis1 = as.numeric(V4$PERM[1, pct_of_perm_below_obs]),
                                  axis2 = as.numeric(V4$PERM[2, pct_of_perm_below_obs])),
    metric_type = "canonical_screen"),

  alpha_discovery_count = 1L,
  selection_objective = "canonical_port_t",

  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH",
         flag = "R1 수송 게이트 발화 — 완전예지 여유폭(연 +13.69%p)이 관측 가능 상태축 2종 어디에도 유의 종속 아님(t +0.876 / +0.384). 본 마디에서 상태 조건부 선택은 원리적 지렛대가 아니다."),
    list(id = "CF-02", severity = "HIGH",
         flag = "co-primary 2종 전부 POWERED_NULL_NO_MATERIAL_EFFECT. 여유폭 회수율 -8.01% / +1.94% — 실질 0. 자본 경로 미진입."),
    list(id = "CF-03", severity = "HIGH",
         flag = "순열 귀무분포(40 draws/축) 기준 관측 t 백분위 62.5 / 90.0 (one-sided p 0.375 / 0.100) — 어느 축도 무작위 상태를 5% 수준에서 이기지 못함. 규칙-형태 자체가 셔플 하에서 평균 -1.06 t 의 비용을 만든다."),
    list(id = "CF-04", severity = "MEDIUM",
         flag = "T1 형태(확신 첨예화)는 완전예지 상태로도 t 0.350 — 전도성 미확립. T1_AGREE 의 null 은 상태 부재 증거로 쓸 수 없다(FQ-244 LEAK1 미통과와 같은 계통)."),
    list(id = "CF-05", severity = "MEDIUM",
         flag = "★신규 상한 발견 — 완전예지 상태조차 소프트 가중 형태로는 여유폭의 25.2%(3.45/13.69)만 회수하고 PORT_t 1.70~1.82 로 벽 미달. ORACLE_K 4.647 은 이산 하드 선택의 상한이며 소프트 틸트 족 상한은 훨씬 낮다."),
    list(id = "CF-06", severity = "MEDIUM",
         flag = "승계한 regime_scope 의 holds_in '위기-회복 국면' 은 실측 미지지 — T3_DISP 위기 alpha -1.99%p vs 정상 +0.83%p(위기 t -0.971). 유의하지 않아 국면 주장으로 승격하지 않으나 승계분과 실측이 어긋난 사실을 기록(재작성 아님, Charter 원칙 8)."),
    list(id = "CF-07", severity = "MEDIUM",
         flag = "F2 사전 예약 라벨 — T1_AGREE(Jaccard 0.9231)·T3_BEAR(0.9231)는 매개 미이동 문턱 초과. 두 arm 의 null 은 기전 반증 증거 아님(봉인 전 고정)."),
    list(id = "CF-08", severity = "LOW",
         flag = "STORED_SCORE(선별 궤적·z 패널) production_parity_verified = FALSE — incumbent base 소비 자격 없음. 본 라운드는 자본 주장을 하지 않아 연구용 소비만 성립."),
    list(id = "CF-09", severity = "LOW",
         flag = "C0 자체 회전율 11.55/yr 로 Research Philosophy P6 권고(TO ≤ 11.0/yr) 상회 — 승계 하네스 속성. 처치는 +0.07~+1.06/yr 추가."),
    list(id = "CF-10", severity = "LOW",
         flag = "F3(agent 실재)는 통과 — 고분산 월 개인 순매수 집중 상승 cor +0.272(t +1.776). 기전의 주체는 실재하며 실패는 '상태 → 어느 팩터를 신뢰할지' 전이에서 발생. 소비면 ④⑤(위험/monitoring)로 미측정 잔존.")),

  round_verdict = "CONFIG_SCOPED_NEGATIVE__STATE_AXIS_DOES_NOT_INDEX_FACTOR_HEADROOM",
  validation_ref = "stage_artifacts/WT-D20260822_006/alpha_validation.json",
  prereg_ref = "stage_artifacts/WT-D20260822_006/PREREG.json"
)

write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[written]", file.path(MB,"alpha_package.json"), "\n")

## lineage — ★alpha_package.json write 후에 호출 (L-194 순서 규약)
src <- "02_Infrastructure/worktask/lineage_utils.R"
if (file.exists(src)) {
  source(src)
  record_package_lineage(
    task_id = "WT-D20260822_006", package_type = "alpha_package",
    method_selected = "state-conditional K=5 factor weighting (agreement + dispersion axes), preregistered arms no champion",
    input_file_paths = c(PANEL, "stage_artifacts/WT-D20260822_004/p0_probe.rds",
      "stage_artifacts/WT-D20260822_004/p1_arms.rds", "stage_artifacts/WT-D20260822_004/p4_verdict.rds",
      "outputs/ramp/smv_factor_regime_daily.parquet", ".cache/benchmark.parquet",
      ".cache/investor_stock/investor_wide.parquet", "02_Infrastructure/factor_db/factor_registry.json"))
  cat("[lineage] recorded\n")
} else cat("[lineage] lineage_utils.R 부재 — 미기록\n")
