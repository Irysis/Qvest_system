# =============================================================================
# run_wt001_emit.R — WT-D20260803_001 alpha_package + alpha_validation + lineage
#   순서 의무 (L-194): alpha_package.json write → record_package_lineage
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_001/run_wt001_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_001")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260803_001")
say <- function(fmt, ...) cat(sprintf(paste0("[wt001-emit] ", fmt, "\n"), ...))
rnd <- function(x, k = 4) round(as.numeric(x), k)

R <- readRDS(file.path(OUT, "wt001_fm_results.rds"))
SIG <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
SIG[, Date := as.Date(Date)]
last_d <- max(SIG$Date)
LS <- SIG[Date == last_d][order(-interaction)]
alpha_vec <- setNames(as.list(rnd(LS$interaction, 4)), LS$Ticker)
conf_vec  <- setNames(as.list(rep(0.10, nrow(LS))), LS$Ticker)

t_B <- R$verdict$t_B; t_A <- R$verdict$t_A; t_C <- R$verdict$t_C; t_L <- R$verdict$t_lag1
summB <- R$arms$B$summ

pkg <- list(
  task_id = "WT-D20260803_001",
  as_of_date = "2026-08-03",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = "rank-tilt base의 최상위 알파 랭크 후보 안에서 MAX5_63 상위는 '복권'이 아니라 승자 표지다 — FM 상호작용항(alpha_rank_z × max5_z)이 양(+)으로 유의하면 배제가 아니라 가산 방향 소비로 재설계.",
    mechanism = list(
      agent = "알파 상위(펀더멘털·수급 우량) 종목에서의 정보 이벤트 도착 주체 (대형 단일일 수익 = 정보 신호) + 저랭크에서의 개인 복권 수요 주체 (Bali-Cakici-Whitelaw 2011 과대평가) — 랭크가 두 주체를 분기",
      friction = "KR 공매도 제약 + 월간 리밸런싱 주기 — 고랭크 과소반영·저랭크 과대평가 어느 쪽도 1개월 내 차익거래로 지워지지 않음",
      path = "고랭크 조건부: 급등(정보 도착) 후 1~3개월 연속 반영으로 초과수익 / 저랭크 조건부: 복권형 되돌림 — 상호작용항이 두 경로의 분기를 식별"
    ),
    falsification = "부수 관측: 고랭크×고MAX5 종목의 기관 순매수(investor_flow 리프)가 급등 후 후속 증가하지 않으면 '정보 도착' 기전 기각. 판별 검정: FM 상호작용 NW t < +2.0이면 승자 표지 기각 — ★본 라운드 실측 +0.234로 기각됨 (WT-022 +1.16%/월은 우연 범위 확정)",
    regime_scope = list(
      holds_in = list("NEUTRAL", "CAUTION"),
      weakens_or_reverses_in = list("CRISIS"),
      boundary_rationale = "WT-020 실측: MAX5 상위군의 상방 꼬리는 CAUTION에서 지배(ret_spread +1.76%/월 t+2.08), CRISIS에서는 유동성 청산이 정보 신호를 압도 — 경계는 승계 실측에서 도출 (설계 시점 고정)"
    )
  ),
  factors = list(list(
    factor_id = "F1_rank_max5_interaction",
    ast = list(
      op = "MUL",
      ast_note = "MUL(CS_ZSCORE(CS_RANK(score_eff)), CS_ZSCORE(max5)) — 후보 프레임 월내 z 상호작용. 판정 소비는 FM 회귀 계수(특성화)이며 포트 구성 아님",
      args = list(
        list(leaf = "STORED_SCORE",
             field = "score_eff (WT_D20260425_010 — production alpha lineage)",
             escape_contract = list(
               escape_type = "STORED_SCORE",
               panel_path = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
               vintage = "2026-08-02 01:01:39",
               production_parity_verified = TRUE,
               parity_evidence = "WT-022 GATE A: 재현 루프 vs production 03_period_returns.csv(20260802_LIVE) 271/271개월 max|Δret| 5.13e-16")),
        list(leaf = "SPECIAL_OP",
             field = "max5_63 (WT-010 ot_panel 동결분 — 63거래일 상위 5일 수익 평균, 창 종점 d0=전월말)",
             escape_contract = list(
               escape_type = "SPECIAL_OP",
               code_path = "stage_artifacts/WT_D20260802_010 (동결 패널, 재계산 없음)",
               walk_forward = "d0 < 홀딩월 시작 구조 보장 + 동월 라벨 위반 주입 시 검증기 stop() 발화 실증"))
      )
    ),
    role = "core_signal",
    restatement_exposure = 0
  )),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "STORED_SCORE:score_eff",
           availability_rule = "production 코드 직소비 패널 — WT-022 GATE A parity로 vintage 무결 실증 (§7b)",
           restatement_prone = FALSE),
      list(leaf = "SPECIAL_OP:max5_63",
           availability_rule = "fixed: 저장 일간 Ret, 창 종점 d0(전월말) < 홀딩월 시작. C5/C10",
           restatement_prone = FALSE),
      list(leaf = "FIELD:D35_RealVol_63d (통제)",
           availability_rule = "load_month_factors(d0) 경유 — Usable_Date <= d0 로더 강제 (C14/C15). registry availability fixed T-1",
           restatement_prone = TRUE),
      list(leaf = "FIELD:D45_Downside_Dev (통제)",
           availability_rule = "load_month_factors(d0) 경유 — Usable_Date <= d0 로더 강제 (C14/C15)",
           restatement_prone = TRUE),
      list(leaf = "FIELD:Ret_1m (라벨)",
           availability_rule = "그리드 (d0, d0_next] 익월 수익 — 독립 재계산 cor 1.0000 + 동월 주입 발화. d0 <= 2026-03-31 (data_currency_flag)",
           restatement_prone = FALSE)
    ),
    verdict = "clean"
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  alpha_vector_note = sprintf("마지막 신호월(d0=%s) 상호작용 z(zrank×zmax5) — 기록용. 판정 INCONCLUSIVE(t +0.234 < +2.0)이므로 랭킹/필터 소비 금지. confidence 0.10 flat (미확정 판정 반영)", as.character(last_d)),
  alpha_discovery_count = 0,
  discovery_of = "WT-D20260802_022",
  signal_matrix_ref = "stage_artifacts/WT_D20260803_001/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "lottery_demand_x_alpha_rank",
    proxy = "zrank(score_eff) × z(MAX5_63) interaction",
    formula = "FM: Ret_1m ~ zrank + zmax5 + zrank:zmax5 + D35_RealVol_63d + D45_Downside_Dev + zsize + zliq (월별 횡단면, NW lag-3)",
    lag_rule = "전 회귀변수 d0(전월말 거래일) 이전 데이터만 — 라벨은 (d0, d0_next]",
    winsorization = "3std (월내, zrank/zmax5/zsize/zliq)",
    neutralization = "D35/D45/size/liq 통제 (회귀)",
    economic_rationale = "고랭크 조건부 정보-도착 vs 저랭크 복권 수요 분기 가설 — 실측 기각 (상호작용 t +0.234)",
    weight_theta = 0,
    references = list("Bali-Cakici-Whitelaw 2011 JFE", "Fama-MacBeth 1973", "WT-D20260802_014/016/020/022")
  )),
  diagnostics = list(
    canonical_port_t_nw_lag3 = NULL,
    canonical_port_t_note = "canonical_screen_bt 미실행 — 본 라운드 primary = FM 횡단면 회귀 특성화 (포트폴리오 성과 주장 없음). 조건부 소비 arm(실코드 ΔIR)은 trigger(t>=+2.0) 미충족으로 사전등록대로 미실행 — 미실행이 결론",
    fm_interaction_t_nw_lag3 = rnd(t_B, 3),
    fm_interaction_mean_b = rnd(summB["mean", "zrank:zmax5"], 6),
    fm_arm_A_no_vol_controls_t = rnd(t_A, 3),
    fm_arm_C_attribution_t = rnd(t_C, 3),
    fm_lag1_t = rnd(t_L, 3),
    fm_zrank_main_t = rnd(summB["t", "zrank"], 3),
    fm_zmax5_main_t = rnd(summB["t", "zmax5"], 3),
    eff_top_q90_t = rnd(R$eff_top_q90$t, 3),
    placebo_t_5seeds = rnd(R$placebo, 2),
    top40_local_t = rnd(R$top40$ctrl$t, 3),
    n_months = 256, n_stock_months = nrow(SIG),
    collinearity_zmax5_d35 = rnd(mean(R$collinearity$c_d35), 3),
    metric_type = "fm_cross_sectional (사전등록 FM 회귀 실측 — 성과수치 아님. 소비 arm 미실행이라 canonical/backtested 수치 부재)",
    rank_ic = NULL, icir = NULL, monotonicity = NULL, subperiod_stability = NULL,
    harvey_t_stat = NULL,
    advisory_note = "rank-IC 계열 미산출 — 판별 대상이 단일 신호 랭킹력이 아니라 상호작용 계수. 부기간·국면·tier 분해는 alpha_validation.json"
  ),
  selection_objective = "canonical_port_t",
  n_trials = 1,
  selection_type = "preregistered_single_primary_chain",
  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(
      name = "FM_interaction_alpha_rank_x_max5",
      selected = TRUE,
      note = "사전등록 단일 primary. Arm A/C·lag1·placebo·top40·부기간·국면·tier·이중정렬은 사전등록 진단 — 선택 비사용"))
  )),
  challenge_flags = list(
    "판정 INCONCLUSIVE: 상호작용 NW t +0.234 (문턱 +2.0 미달) — WT-022 +1.16%/월은 우연 범위 확정",
    "방향 반전 소비 arm 미실행 (trigger 미충족) — 배제도 가산도 실코드 소비 근거 없음, rank-tilt book 무변경이 실측 정답",
    "D35 통제 전/후 병기: 통제 전 t -0.083 / 통제 후 +0.234 / rank×D35 병렬 +1.281 — 어느 스펙에서도 문턱 미달",
    "CAUTION 셀 t +2.05 (n=13) — WT-020과 독립 2회 정합, 승격 아닌 next_probe 사전등록 대상 (challenge_note Concern 2)",
    "MEGA 셀 t +2.76 — 축약 스펙 저검정력 (n=10/월, vol 통제 불가) — 미확정 프론티어",
    "D35_RealVol_63d = factor DB 등재 상태였으나 소비자 0 — 있는데 안 쓴 것 (본 라운드가 첫 리서치 소비)"
  ),
  verdict_summary = "FM 상호작용(후보 프레임 256개월, 월평균 231종) NW t +0.234 → 사전등록 판정 INCONCLUSIVE. 3갈래 국소 검정(top-40 t +0.34 / rank-Q5 스프레드 t +1.54 / 승계 t 1.54) 전부 문턱 미달로 일관. placebo 5 seeds 전부 |t|<=1.2 (검정 실효). 스코프: 선형 z-상호작용·1M — CAUTION 조건부/mega-cap/비선형은 미검 프론티어."
)

json_path <- file.path(MB, "alpha_package.json")
write_json(pkg, json_path, pretty = TRUE, auto_unbox = TRUE, null = "null", digits = 8)
say("alpha_package.json 저장 — %s", json_path)

# Step 2: lineage (alpha_package write 이후 — L-194)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260803_001",
  package_type = "alpha_package",
  method_selected = "FM interaction alpha_rank_z x max5_z (D35/D45 controls, preregistered single primary)",
  input_file_paths = c(
    "stage_artifacts/WT_D20260802_014/alpha_scores.parquet",
    "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
    "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
    "stage_artifacts/WT_D20260803_001/controls_panel_d35.parquet",
    ".cache/RAWDATA.parquet",
    ".cache/unified_regime_signal.parquet"))
say("lineage 기록 완료")

# alpha_validation.json
val <- list(
  task_id = "WT-D20260803_001",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "fm_cross_sectional (사전등록 FM 회귀 실측 — 성과수치 아님)",
  gate_eligible = FALSE,
  selection_type = "preregistered_single_primary_chain",
  n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260803_001/preregistration.json (측정 전 고정 + Q-Lead 통제 소스 개정 반영)",
  input_vintage = R$vintage,
  pit_guards = list(
    label_direction = list(pass = TRUE, cor_all = rnd(R$validator$cor_all, 4),
                           n_pairs = R$validator$n_pairs),
    violation_injection = list(fired = TRUE,
                               note = "동월 수익 라벨 위장 주입 → 검증기 stop() 발화 (cor 0.0066)"),
    c14_c15 = "D35/D45 = load_month_factors(d0) 경유 (Usable_Date <= d0 로더 강제)",
    data_currency = "d0 <= 2026-03-31 (WT-020 flag: screen_inputs d0 >= 2026-04-30 라벨 소비 금지)"
  ),
  primary = list(
    name = "FM_interaction_alpha_rank_x_max5",
    arm_B_with_d35_d45 = list(mean_b = rnd(summB["mean", "zrank:zmax5"], 6), t_nw_lag3 = rnd(t_B, 3), n_months = 256),
    arm_A_no_vol_controls = list(t_nw_lag3 = rnd(t_A, 3)),
    arm_C_rank_x_d35_parallel = list(t_nw_lag3 = rnd(t_C, 3),
      note = "b_int 점추정 +0.00242로 증가하나 공선성(cor zmax5~D35 = -0.918)으로 SE 팽창 — attribution gate는 primary 미확정으로 미발동"),
    lag1_stress = list(t_nw_lag3 = rnd(t_L, 3)),
    main_effects = list(zrank_t = rnd(summB["t", "zrank"], 2), zmax5_t = rnd(summB["t", "zmax5"], 2)),
    eff_at_rank_q90 = list(mean = rnd(R$eff_top_q90$mean, 5), t_nw = rnd(R$eff_top_q90$t, 3)),
    decision_rule = "t >= +2.0 승자표지 / |t| < 2.0 미확정 / t <= -2.0 배제 지지 (사전 고정)",
    verdict = "INCONCLUSIVE — WT-022 +1.16%/월(t 1.54)은 우연 범위 확정. 소비 arm trigger 미충족으로 미실행",
    threshold_proximity = "t +0.234 — [1.5, 2.5] 밖이라 섭동 분포 조건 미충족 (사전등록 규약 준수)"
  ),
  diagnostics_preregistered = list(
    placebo_t_5seeds = rnd(R$placebo, 2),
    top40_local = list(with_controls_t = rnd(R$top40$ctrl$t, 3), no_controls_t = rnd(R$top40$noctrl$t, 3)),
    subperiod = R$subperiod,
    regime = R$regime,
    ax001_conditional = list(
      crisis = R$ax001_crisis,
      note = "CRISIS 셀 b +0.00219 t +0.69 (n=13) — 방향 양(+)이나 비유의. CAUTION 셀 t +2.05는 WT-020(CAUTION ret_spread t +2.08)과 독립 2회 정합 — 승격 아닌 next_probe (다중검정: 진단 셀 20+ 중 2개 |t|>2는 무효과 하 기대 범위)"),
    cap_tier = R$tier,
    double_sort_spread_by_rank = R$double_sort$spread_by_rank,
    collinearity_monthly_mean = list(zmax5_d35 = rnd(mean(R$collinearity$c_d35), 3),
                                     zmax5_d45 = rnd(mean(R$collinearity$c_d45), 3),
                                     zmax5_zrank = rnd(mean(R$collinearity$c_rank), 3))
  ),
  d35_consumption_fact = "D35_RealVol_63d: factor DB 등재(2026-03-24, active)이나 본 라운드 이전 소비자 0 (factor_db 내부 4곳 참조뿐) — '없어서 못 쓴 게 아니라 있는데 안 쓴 것'. 본 라운드 = 첫 리서치 소비 (Q-Lead 지시 3)",
  next_probe = list(
    np1 = "CAUTION 국면-조건부 MAX5 소비 사전등록 라운드 — WT-020(ret_spread +1.76%/월 t+2.08) + 본 라운드(CAUTION b_int +0.0063 t+2.05) 독립 2회 정합. 검정력 확보 설계(CAUTION 정의 확장 또는 pooled 패널 + 국면 더미 상호작용)로 FQ 등재",
    np2 = "MEGA tier 상호작용 재검 (t +2.76, 축약 스펙 저검정력) — pooled panel(월 FE + 종목 클러스터 SE)로 vol 통제 포함 full-spec 검정. WT-022 cap-tier MEGA Δ기여 +0.73%/yr 방향 정합 여부 확인",
    np3 = "D35_RealVol_63d 소비 배선 — 위험모델(Σ/β예산) 입력으로 첫 배선 (WT-020 NP-3 risk_integration_proposal과 합류, risk-research 소비면). 생산-소비 단절 계통의 회수 사례"
  ),
  revival_conditions = list(
    "np1 CAUTION-조건부 사전등록 검정 유의(|t|>=2) 시 국면-조건부 방향 반전(가산 tilt) 재도전",
    "np2 mega-cap full-spec 검정 t >= 2 시 mega-cap 한정 상호작용 소비 재도전",
    "비선형/문턱형 상호작용(top-decile max5 × top-rank 이진 셀) 신규 증거 발화 시 — 본 라운드는 선형 z-상호작용 config-scoped",
    "book stock layer가 size-weighted로 교체되면 WT-014/016 필터 직접 이식 재검 (WT-022 승계 불변)"
  ),
  consumption_face_7 = list(
    factor_ranking = "가산 tilt 부정 (본 라운드) — 배제(WT-022 철회)와 가산 모두 근거 없음 → rank-tilt book 무변경이 실측 정답",
    universe_filter = "배제 프레임 재지지 없음 (t <= -2.0 아님) — WT-022 철회 유지, size-weighted screen 한정 라벨 불변",
    overlay_regime_input = "CAUTION 조건부 셀 2회 정합 — np1로 사전등록 대상화 (살아있음)",
    risk_model_beta_budget = "MAX5 재료의 정공 소비면 재확인 — 63d 꼬리변동성 Σ 입력 (WT-020 NP-3, np3로 D35 배선 합류)",
    monitoring_signal = "MAX5 경보 무근거 유지 (WT-022 닫힘 승계)",
    screening_label = "변경 없음 — WT-014/016 screen_route size-weighted 전용 부기 유지",
    other_mode_transplant = "FR/RAMP size-weighted 모듈 이식 가능성 불변 (WT-022 NP-2) + mega-cap 프레임 재검은 np2"
  ),
  capital_claim = "없음 — book_state 무변경, governor 미접촉, Σ/weights 산출 없음"
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, null = "null", digits = 8)
say("alpha_validation.json 저장")

# status + governance_log
st <- list(task_id = "WT-D20260803_001", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), blocker = NULL)
write_json(st, file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
gl_path <- file.path(MB, "governance_log.json")
gl <- fromJSON(gl_path, simplifyVector = FALSE)
gl$events[[length(gl$events) + 1L]] <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_DONE",
  summary = "FM 상호작용 t +0.234 → 사전등록 INCONCLUSIVE (WT-022 +1.16%/월 = 우연 범위 확정). 소비 arm trigger 미충족 미실행. 위반주입 발화·placebo 정상. D35 첫 소비 + 소비자 0 사실 기록. challenge_note.md 5 concern.")
write_json(gl, gl_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
say("status ALPHA_DONE + governance_log 기록 — DONE")
