# =============================================================================
# emit_all.R — WT-D20260803_006 (FQ-133) 산출물 emission
#   alpha_scores.parquet + alpha_validation.json + alpha_package.json + lineage
#   ★ 순서 계약 (L-194): alpha_package.json write → record_package_lineage
#   ★ 경계: 자본 주장 없음 / gate_eligible = FALSE / Σ·weights 없음
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260803_006")
say <- function(fmt, ...) cat(sprintf(paste0("[wt006E] ", fmt, "\n"), ...))
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
n4 <- function(x) if (is.null(x) || !length(x) || !all(is.finite(x))) NULL else round(as.numeric(x), 4)

R6  <- readRDS(file.path(OUT, "era_results.rds"))
PAR <- readRDS(file.path(OUT, "parity.rds"))
AP1 <- readRDS(file.path(OUT, "adversarial_probes.rds"))
AP2 <- readRDS(file.path(OUT, "adversarial_probes2.rds"))
AP3 <- readRDS(file.path(OUT, "adversarial_probes3.rds"))
BRT <- readRDS(file.path(OUT, "arm_vs_own_baserate.rds"))
REG <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
LAB <- as.data.table(readRDS(file.path(ROOT, "stage_artifacts/WT_D20260803_005/registry_labels.rds")))
Sp <- R6$Sp; P <- Sp$P; POOL <- R6$POOL

# ── 1. alpha_scores.parquet (본 라운드 산출 = 종목 스코어가 아니라 era 판정 패널) ──
SC <- data.table(
  Date = P$Date, t_index = P$t,
  era_forward_index_E = P$E,                 # (t, t+24] 팩터 양수비율 (실현 = 사후)
  era_true_sign = P$y,
  pred_rt_cusum = P$p_rt_cusum, val_rt_cusum = P$rt_cusum, cusum_tau_index = P$tau_hat,
  pred_br_rt = P$p_br_rt, val_br_rt = P$br_rt,
  pred_trail12 = P$p_trail12, pred_trail24 = P$p_trail24,
  pred_trail36 = P$p_trail36, pred_trail60 = P$p_trail60,
  pred_inj_peek6 = P$p_peek6, pred_inj_fullcusum = P$p_fullcusum, pred_inj_oracle = P$p_oracle,
  hit_rt_cusum = as.integer(P$p_rt_cusum == P$y))
SC[, monthly_breadth_B := R6$Bm[t_index]]
SC[, xsec_mean_active_G := R6$Gm[t_index]]
SC[, metric_type := "canonical_screen_derived"]
SC[, note := "종목 alpha 아님 — era(팩터 집단 자격 방향) 판정 패널. 예측은 전부 t 시점 정보만 사용(오라클/누출 arm 제외)."]
write_parquet(SC, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet %d행 x %d열", nrow(SC), ncol(SC))

# ── 2. alpha_validation.json ────────────────────────────────────────────────
arm_tab <- lapply(names(Sp$acc), function(cc) list(
  estimator = cc, accuracy_all = n4(Sp$acc[[cc]]),
  accuracy_transition_months = n4(Sp$acc_trans[[cc]]),
  accuracy_nonoverlap = n4(Sp$acc_noverlap[[cc]]),
  information_set = if (cc %in% c("peek6","fullcusum","oracle")) "LEAKED (위반 주입)" else "s <= t (PIT clean)"))

rob_tab <- lapply(names(R6$ROB), function(h) { s <- R6$ROB[[h]]; list(
  h_months = as.integer(h), n_eval = s$n_eval, n_episodes = s$n_episodes,
  base_rate_rt = n4(s$acc[["br_rt"]]), base_rate_majority = n4(s$BR_maj),
  rt_cusum_acc = n4(s$acc[["rt_cusum"]]),
  rt_cusum_acc_transition = n4(s$acc_trans[["rt_cusum"]]),
  delta_vs_base = n4(s$d1_mean), bootstrap_p = n4(s$d1_p),
  oracle_acc = n4(s$acc[["oracle"]])) })

VAL <- list(
  task_id = "WT-D20260803_006", fq = "FQ-133",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  gate_eligible = FALSE,
  gate_eligible_reason = "가능성 판정 라운드 — 전략 없음, 자본 주장 없음. graduation HARD 3종 미적용 대상.",
  selection_type = "chain",
  metric_type = "canonical_screen (원천 net-active 시계열) / diagnostic (본 라운드 통계)",
  preregistration_ref = "stage_artifacts/WT_D20260803_006/preregistration.json (측정 전 고정)",

  question = "t 시점까지의 정보만으로 다음 h개월 era(팩터 집단 자격 방향)를 base rate 보다 잘 맞힐 수 있는가",

  harness = list(
    source_panel = "stage_artifacts/WT_D20260803_005/canonical_pool.rds (canonical_screen_bt top-25 EW long-only, 15bps, LIQ 2e8, cap-w KOSPI200 벤치)",
    pool_n_raw = 322L, pool_n_dedup = length(POOL),
    dedup_rule = "|cor(net-active)| >= 0.99 클러스터 제거, 알파벳 tie-break (WT-005 사전등록 규칙 동일)",
    months = 287L, period = "2002-08-30 ~ 2026-06-30",
    era_index = "B_t = 그 달 net-active > 0 인 factor 비율 (월간 breadth, 스케일링·전기간 통계 미사용)",
    era_target = "y_t = 1{E_{t,h} > 0.5}, E = (t, t+h] 평균 net-active > 0 인 factor 비율",
    h_primary = 24L, burn_in_months = 60L, eval_n = Sp$n_eval,
    primary_estimator = "RT_CUSUM — 확장창 CUSUM argmax 로 단절 위치 추정 후, 단절 이후 구간(최소 12m)의 era 통계 부호. FQ-055 break-dating 프레임(run_break_dating_verify.R V2)의 실시간판."
  ),

  cross_round_parity = list(
    check = "WT-005 primary 격자(W=60 비중첩) 창별 양수비율 재현",
    wt005_reported = c(0.754, 0.908, 0.216, 0.021),
    wt006_measured_port_t = n4(PAR$par_tab$pos_ratio_PORTt),
    wt006_measured_mean_active = n4(PAR$par_tab$pos_ratio_meanactive),
    sign_agreement_port_t_vs_mean_active = n4(PAR$par_tab$sign_agree),
    verdict = if (isTRUE(PAR$parity_ok)) "PASS" else "REVIEW",
    interpretation = "본 라운드의 era 정의(mean-active 부호)가 WT-005 정의(PORT_t 부호)와 창 4개 전부에서 1.000 일치 — 같은 대상을 재고 있음이 실증됨. 라운드 간 정합 확보."
  ),

  primary_result = list(
    h_months = 24L, n_eval = Sp$n_eval, n_nonoverlap = Sp$n_noverlap,
    base_rate_rt_expanding = n4(Sp$acc[["br_rt"]]),
    base_rate_majority_expost = n4(Sp$BR_maj),
    rt_cusum_accuracy = n4(Sp$acc[["rt_cusum"]]),
    delta_vs_base_rt = n4(Sp$d1_mean),
    block_bootstrap_p = n4(Sp$d1_p),
    block_bootstrap_ci95 = n4(as.numeric(Sp$d1_ci)),
    block_months = Sp$block, effective_independent_blocks = n4(Sp$eff_n),
    transition_conditional_accuracy = n4(Sp$acc_trans[["rt_cusum"]]),
    transition_n = length(R6$tr_idx),
    transition_hits = sum(R6$hit_tr),
    transition_binomial_p_optimistic = n4(R6$tr_binom_p),
    transition_block_bootstrap_P_acc_ge_0.5 = n4(R6$tr_boot_p),
    transition_effective_blocks = n4(R6$tr_eff),
    verdict = R6$verdict
  ),

  estimator_arms = arm_tab,
  h_robustness = rob_tab,

  diagnostic_estimators = list(
    list(id = "XSEC_STRUCT", spec = "확장창 로지스틱 (횡단면 sd(12m 평균 active) + 평균 쌍상관 24m)",
         accuracy = n4(R6$L3$acc), n = R6$L3$n, verdict = "chance 미만"),
    list(id = "SPREAD_COMPRESS", spec = "확장창 로지스틱 (factor active q90-q10 스프레드 + 벤치 12m 수익 + 벤치 12m 변동성)",
         accuracy = n4(R6$L4$acc), n = R6$L4$n, verdict = "chance 미만"),
    list(id = "CONCENTRATION", spec = "확장창 로지스틱 (유니버스 top-10 시총 비중 + 12m 변화) — 메가캡 레짐 가설",
         accuracy = n4(R6$L5$acc), n = R6$L5$n,
         contemporaneous_cor_with_forward_era = n4(cor(R6$CONC$top10, c(P$E[match(seq_len(287), P$t)]), use = "complete.obs")),
         verdict = "chance 미만 — 동시대 상관 0.34 가 선행 정보로 전이되지 않음"),
    list(id = "REGIME_LABEL_NC", spec = "★음성 대조 (설계 제약상 추정자 아님) — 기존 국면 라벨 Category 의 확장창 era 매핑",
         accuracy = n4(R6$acc_nc),
         era_pos_ratio_by_category = list(RISK_ON = 0.4717, NEUTRAL = 0.6818, CAUTION = 0.6154, CRISIS = 0.4444),
         verdict = "0.3669 — chance 크게 미만. Q-Lead 사전 확인(창2/창3 국면 분포 동일) 을 독립 재확인")
  ),

  violation_injection = list(
    list(id = "INJ_ORACLE", role = "양성 대조 (배관 검증)", accuracy = n4(Sp$acc[["oracle"]]),
         expected = 1.0, fired = isTRUE(R6$oracle_ok),
         note = "1.000 정확 달성 — 측정 배관 정상. 이 값이 1 이 아니면 전 결과 무효였다."),
    list(id = "INJ_PEEK6", role = "부분 누출 (t+6까지)", accuracy = n4(Sp$acc[["peek6"]]),
         delta_vs_base = n4(Sp$acc[["peek6"]] - Sp$acc[["rt_cusum"]]),
         accuracy_transition = n4(Sp$acc_trans[["peek6"]]), fired = TRUE),
    list(id = "INJ_FULLSAMPLE_CUSUM", role = "고전적 look-ahead (전기간 CUSUM = 사후 era 분할)",
         accuracy = n4(Sp$acc[["fullcusum"]]),
         delta_vs_base = n4(Sp$acc[["fullcusum"]] - Sp$acc[["rt_cusum"]]),
         accuracy_transition = n4(Sp$acc_trans[["fullcusum"]]), fired = TRUE,
         note = "Δ +0.212 (전이월 Δ +0.333) — '사후에 era 를 나누는 것은 쉽다'의 직접 실증. 이 라운드 논지의 핵심 대조.")
  ),

  detection_lag = list(
    sustained_episodes = lapply(seq_len(nrow(R6$SUS)), function(i) list(
      from = as.character(R6$SUS$from[i]), to = as.character(R6$SUS$to[i]),
      sign = R6$SUS$sign[i], length_months = R6$SUS$len_m[i])),
    transitions = lapply(seq_len(nrow(R6$lag_sus)), function(i) list(
      change_date = as.character(R6$lag_sus$change_date[i]), to_sign = R6$lag_sus$to_sign[i],
      lag_rt_cusum_months = if (is.na(R6$lag_sus$lag_rt_cusum_m[i])) NULL else R6$lag_sus$lag_rt_cusum_m[i],
      detected = !is.na(R6$lag_sus$lag_rt_cusum_m[i]))),
    key_finding = "주요 era 전환 2회(2009-06 회복 / 2014-12 붕괴)의 탐지 지연 24개월·22개월 = 예측 지평 h=24 이상. 8회 중 2회는 끝내 미탐지. 실무상 사전 추정 불가."
  ),

  sensitivity = list(
    S1_fully_observed_only = list(n_factor = 246L, rt_cusum = n4(R6$Sf$acc[["rt_cusum"]]),
      base_rt = n4(R6$Sf$acc[["br_rt"]]), transition = n4(R6$Sf$acc_trans[["rt_cusum"]]),
      bootstrap_p = n4(R6$Sf$d1_p), verdict = "결론 불변"),
    S2_pool_halfsplit = list(cor_monthly_breadth = n4(R6$cor_half_B),
      cor_forward_era_index = n4(R6$cor_half_E), sign_agreement = n4(R6$agree_half),
      verdict = "era 는 pool 선택 아티팩트가 아닌 실재 공통성분 (상관 0.986/0.988)"),
    S3_alt_era_index_g = list(rt_cusum = n4(R6$Sg$acc[["rt_cusum"]]),
      transition = n4(R6$Sg$acc_trans[["rt_cusum"]]), bootstrap_p = n4(R6$Sg$d1_p),
      verdict = "결론 불변 (전이 0.284)"),
    S4_family_decomposition = lapply(seq_len(nrow(R6$fam_tab)), function(i) list(
      family = R6$fam_tab$family[i], n_factor = R6$fam_tab$n_factor[i],
      cor_with_pool_era = n4(R6$fam_tab$cor_with_pool[i]),
      sign_agreement = n4(R6$fam_tab$sign_agree[i]))),
    S5_clear_era_subset = list(criterion = "|E - 0.5| > 0.1", n = R6$clr_n,
      rt_cusum = n4(R6$clr_acc), transition_within = 0.2778,
      verdict = "명확 era 만 봐도 전이월 적중률 0.278 — knife-edge 아티팩트 아님")
  ),

  arm_vs_own_base_rate = list(
    note = paste0("★각 arm 을 **자기 평가 부분집합의 상수규칙**과 비교한다. 전역 base 와 비교하면 ",
      "평가창이 밀린 arm 에서 거짓 우위가 생긴다(CF-08 실사고). 초안의 '자기 base 를 넘은 것 0건' 은 ",
      "**과대주장이었고 이 표가 그것을 정정한다**(CF-09)."),
    rows = lapply(seq_len(nrow(BRT)), function(i) list(
      arm = BRT$arm[i], n = BRT$n[i], accuracy = n4(BRT$acc[i]),
      own_subset_base_rate = n4(BRT$own_base[i]), delta = n4(BRT$delta[i]),
      information_set = if (BRT$leaked[i]) "LEAKED (위반 주입)" else "s <= t (PIT clean)")),
    summary = paste0("PIT-clean arm 11종 중 자기 base 를 **명목상** 넘은 것 5건 — 전부 트레일링 계열이고 ",
      "초과폭 최대 +0.0493(rt_cusum), 그마저 block bootstrap p=0.362 로 미유의. 로지스틱 3종과 다변량은 ",
      "자기 base 대비 -0.157 ~ -0.200 으로 **미달**. 반면 누출 arm 초과폭은 +0.148 / +0.261 / +0.497 — ",
      "★가장 큰 clean 우위(+0.049)가 가장 작은 누출 우위(+0.148)의 1/3 이다. 이 대비가 판정의 하중."),
    correct_statement = "어느 PIT-clean arm 도 자기 base 대비 우위를 유의하게 확립하지 못했다 (명목 초과 최대 +0.049, p=0.362)"
  ),

  self_adversarial_probes = list(
    note = "★finalize 직전 자체 적대검증. 아래 2건은 '우위처럼 보였다가 통제로 무너진' 실측이며, 증거에서 제외했다 — 제외 사유까지 공개하는 것이 산출의 일부다.",
    A_lag1_stress = list(base_all = n4(AP1$lag1_all), base_transition = n4(AP1$lag1_tr),
      delta_all = n4(AP1$lag1_all - Sp$acc[["rt_cusum"]]),
      verdict = "1개월 지연으로 붕괴하지 않음 (Δ +0.018) — BASE arm 에 동월 누출 없음"),
    B_placebo_target = list(null_mean = n4(AP1$placebo_mean), null_ci95 = n4(as.numeric(AP1$placebo_ci)),
      observed = n4(Sp$acc[["rt_cusum"]]), percentile = n4(AP1$placebo_pct),
      verdict = "관측 0.552 는 순환이동 귀무분포의 65 백분위 — 우위 미확립 재확인"),
    C_insample_ceiling_VACUOUS = list(
      claim_tested = "트레일링 13피처를 전기간 적합하면 0.857 (전이 0.852) — '피처 공간에 정보가 있다'로 읽힐 뻔했다",
      permutation_null_mean = n4(AP2$perm_mean_all), permutation_p = n4(AP2$p_perm_all),
      permutation_null_mean_transition = n4(AP2$perm_mean_tr), permutation_p_transition = n4(AP2$p_perm_tr),
      verdict = "★VACUOUS — 무작위(블록 순환이동) target 도 0.850 으로 적합됨(p=0.477). 203개 자기상관 관측에 13피처는 어떤 target 이든 보간한다. 증거에서 제외.",
      lesson = "검증이 항상 통과하도록 설계되면 그 검증은 없는 것과 같다 — 순열 대조가 없었다면 이 0.857 을 '정보 존재'로 보고했을 것이다"),
    F_multivariate_realtime_ARTIFACT = list(
      claim_tested = "13피처 확장창 실시간 로지스틱 0.650 (전이 0.691) — 유일하게 base 를 넘는 것처럼 보였다",
      why_rejected_1_subsample_shift = list(
        eval_window = paste0(as.character(AP3$from), " ~ ", as.character(AP3$to)),
        n = AP3$n_eval, note = "학습 최소표본 60 조건 때문에 평가가 뒤쪽 59% 구간으로 밀림",
        subset_base_rate_constant_rule = n4(AP3$base_subset),
        constant_rule_accuracy = n4(AP3$const_acc),
        multivariate_accuracy = n4(AP3$F_acc),
        delta_vs_constant = n4(AP3$F_acc - AP3$const_acc),
        verdict = "★같은 구간에서 '항상 -1' 상수규칙이 0.7333 으로 F(0.6500)를 이긴다 — F 는 base 를 못 넘었다"),
      why_rejected_2_permutation = list(
        null_mean = n4(AP3$perm_mean), null_ci95 = n4(as.numeric(AP3$perm_ci)),
        p_value = n4(AP3$perm_p), p_value_transition = n4(AP3$perm_tr_p),
        verdict = "동일 파이프라인 순열 귀무 p=0.342 (전이 p=0.217) — 유의 미달"),
      why_rejected_3_class_imbalance = list(
        transition_subset_base_rate = 0.6324, multivariate_transition = n4(AP3$F_tr),
        pred_positive_ratio = n4(AP3$pred_pos_ratio), true_positive_ratio = n4(AP3$y_pos_ratio),
        verdict = "전이월 0.691 은 그 부분집합 클래스 불균형(0.632) 재현 수준"),
      verdict = "ARTIFACT — 증거에서 제외. 부분집합 이동 + 순열 미유의 + 클래스 불균형 3중 통제 전부 실패"),
    D_effective_sample_recheck = list(
      transition_raw = "21/81 = 0.2593",
      binomial_p_naive_overlap_ignored = n4(AP1$tr_binom_raw),
      block_bootstrap_P_acc_ge_half = n4(R6$tr_boot_p),
      binomial_p_effective_n_conservative = n4(AP1$tr_binom_eff),
      effective_trials = n4(AP1$n_eff),
      verdict = paste0("★세 값이 다르다: naive 0.00001 (중첩 무시, 과신) / block bootstrap 0.0165 (종속 직접 처리, 선호 통계) / ",
        "유효-n 환산 0.75 (과보수). 정직 라벨 = '방향은 10개 arm·4개 h 격자에서 일관되나 형식 유의는 통계 선택에 좌우된다'. ",
        "판정을 이 한 숫자에 걸지 않는다 — 판정 하중은 (i) 어떤 arm 도 자기 평가구간의 상수규칙을 못 이김 (ii) 누출 arm 은 즉시 발화 이 두 정성 사실에 있다."))
  ),

  power = list(
    effective_independent_blocks = n4(Sp$eff_n), block_months = Sp$block,
    mde_effective = n4(R6$mde_eff), mde_nonoverlap = n4(R6$mde_ni),
    blocks_needed_for_p05_on_observed_delta = R6$need_n,
    years_needed = n4(max(0, (R6$need_n - Sp$eff_n)) * Sp$block / 12),
    sustained_episodes = R6$n_sus,
    honest_statement = paste0(
      "★두 축의 검정력은 다르다. (i) 전체 적중률 축: 관측 Δ +0.049 를 p<0.05 로 확정하려면 ",
      "유효 독립 블록 279개(≈820년)가 필요 — 이 축은 표본을 더 모아도 해결되지 않는 구조적 미검정력이다. ",
      "따라서 '전체 적중률이 base rate 를 못 이긴다'는 증거의 부재이지 부재의 증거가 아니다. ",
      "(ii) 전이-조건부 축: 21/81 = 0.259 로 동전(0.5)보다 **유의하게 낮다**(block bootstrap P(acc>=0.5)=0.0165). ",
      "이건 증거의 부재가 아니라 방향이 있는 결과 — 트레일링 정보는 '끝나가는 era'를 보고한다. ",
      "단 이 축의 유효 독립 블록도 2.2 로 형식적 검정력은 낮다(정직 라벨)."))
)
write_json(VAL, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
say("alpha_validation.json 저장")

# ── 3. alpha_package.json (AST v1.1) ────────────────────────────────────────
avail_rule <- function(f) { e <- REG[[f]]; a <- e$availability
  if (is.null(a)) return("unknown"); paste0(a$type %||% "unknown", ": ", a$rule %||% "unknown") }
restate <- function(f) isTRUE(REG[[f]]$restatement_prone)
FACTORS <- lapply(POOL, function(f) list(factor_id = f,
  ast = list(leaf = "REGISTRY", factor = f),
  role = "pool_member_measured", restatement_exposure = as.integer(restate(f))))

FSPEC <- lapply(POOL, function(f) {
  fam <- LAB[Factor_Name == f, family]
  list(factor_family = if (length(fam)) fam[1] else "unknown", proxy = f,
       formula = "factor_db Z_Score_Aligned (load_month_factors, C15 · C13 부호변형 없음) — WT-005 canonical 시계열 상속",
       lag_rule = avail_rule(f), winsorization = "factor DB 빌드 단계", neutralization = "none (raw z)",
       economic_rationale = "본 라운드에서 alpha 후보가 아니라 *era 공통성분의 구성 관측치*로 소비됨 (자격 방향 판정의 원재료)",
       weight_theta = 0,
       references = list("Harvey-Liu-Zhu 2016", "McLean-Pontiff 2016", "Bai-Perron 1998"))
})

pkg <- list(
  task_id = "WT-D20260803_006", as_of_date = "2026-08-03", forecast_horizon = "1M",
  pit = list(sig_date = "2026-06-30", decision_ts = "2026-08-04",
    decision_ts_rationale = paste0("WT-005 와 동일 풀·동일 리프를 상속 소비한다. 마지막 신호월(2026-06-30)이 ",
      "풀 285 리프 중 가장 보수적인 지연(C11_publication_lag = FRED release 35d 상한, D32_Beta_VIX·MA01~MA04)",
      "까지 반영되어 실행 가능해지는 최초 시점 = 2026-06-30 + 35d = 2026-08-04. 본 라운드는 자본 결정을 ",
      "내리지 않으므로(gate_eligible FALSE, alpha_vector 빈 객체) 이 날짜는 실행 가능 시점의 정직한 선언이다.")),
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = paste0("팩터 자격의 시간구조를 지배하는 era 공통성분은 **실재하지만 사전 관측 불가**하다. ",
      "era 는 오늘 시점의 어떤 트레일링 통계(집단 breadth·횡단면 구조·집중도·벤치 상태·기존 국면 라벨)로도 ",
      "다음 지평의 방향을 base rate 이상으로 지목하지 못하며, 특히 era 가 실제로 바뀌는 국면에서는 ",
      "트레일링 정보가 체계적으로 '끝나가는 era'를 보고해 동전보다 못하다."),
    mechanism = list(
      agent = paste0("era 를 만드는 주체 = KOSPI200 cap-w 벤치를 구성하는 초대형주 패시브·지수 수급과 ",
        "그 반대편에서 top-25 EW 슬리브를 운용하는 리서치 파이프라인 자신. era 를 *추정하려는* 주체 = ",
        "과거 창의 실현 성과만 관측할 수 있는 실시간 판정 절차."),
      friction = paste0("KR 공매도 제약으로 long-only 슬리브는 β≈0.92 시장성분을 제거할 수 없어 285개 factor 가 ",
        "동시에 같은 방향으로 벤치 대비 움직인다(era 공통성분의 물리적 원천). 그리고 era 전환은 벤치 구성·수급 ",
        "레짐의 이산 단절이라 전환 *이전*의 실현 수익 표본에는 그 정보가 존재하지 않는다 — 관측자는 전환이 ",
        "이미 일어난 뒤 누적 편차가 쌓여야만 단절을 검출할 수 있고, 그 축적에 필요한 시간이 예측 지평보다 길다."),
      path = paste0("t 시점 트레일링 통계 → era 방향 추정 → 자격 게이트/성분 교체 판정. 그런데 트레일링 통계는 ",
        "직전 era 의 잔상이므로, 전환 직후 구간에서 추정 부호가 실제 부호와 반대가 된다. 실측 탐지 지연 ",
        "2009-06 전환 24개월 / 2014-12 전환 22개월 — 둘 다 지평 h=24 이상.")
    ),
    falsification = list(
      list(field = "A1_RAWDATA_OHLCVS_daily",
           expectation = paste0("era 가 초대형주 편중 레짐에서 온다면 유니버스 top-10 시총 비중(Size 리프 파생)의 ",
             "트레일링 수준·변화가 다음 era 방향을 선행 지목해야 한다."),
           measured = "확장창 로지스틱 실시간 적중률 0.4286 (n=140), 전이월 0.3824 — 동시대 상관은 0.34 인데 선행 정보로 전이되지 않음",
           result = "REJECTED — 집중도는 era 의 동반 현상이지 선행 지표가 아님"),
      list(field = "A4_benchmark_kospi200",
           expectation = paste0("era 가 벤치 구성 아티팩트라면 벤치 자체의 트레일링 수익·변동성(+ factor 스프레드 압축)이 ",
             "다음 era 방향을 지목해야 한다."),
           measured = "확장창 로지스틱 실시간 적중률 0.4714 (n=140)",
           result = "REJECTED — 벤치 상태량도 선행 정보 아님"),
      list(field = "E7_unified_regime_3layer",
           expectation = paste0("★음성 대조. era 가 기존 3-layer 국면 라벨과 같은 대상이라면 라벨의 확장창 era 매핑이 ",
             "base rate 를 넘어야 한다. Q-Lead 사전 확인(창2 0.908 vs 창3 0.216 인데 RISK_ON 90% vs 87%)의 독립 재검."),
           measured = "적중률 0.3669 (n=139). Category 별 era 양수비율 RISK_ON 0.472 / NEUTRAL 0.682 / CAUTION 0.615 / CRISIS 0.444",
           result = "CONFIRMED (사전 확인 재현) — 국면 라벨은 era 를 구별하지 못한다. 라벨 재사용 금지 설계 제약이 옳았음"),
      list(fields = c("V01_BM", "M01_Mom_12_1", "D01_IdioVol", "Q07_Earnings_Stability"),
           expectation = paste0("era 가 실재 공통성분이라면 pool 을 무작위 반분해도 두 반쪽의 era 지수가 일치해야 하고, ",
             "family 를 나눠도 풀 전체 era 와 정렬해야 한다(아니면 측정 대상 자체가 잡음)."),
           measured = "반분 월간 breadth 상관 0.9858 / forward era 지수 상관 0.9882 / 부호 일치 0.9430. family 12종 era 상관 0.75~0.96",
           result = "CONFIRMED — era 는 실재. 즉 본 라운드의 FAIL 은 '측정 대상이 잡음이라서'가 아니라 '관측가능성 부재'다")
    ),
    regime_scope = list(
      holds_in = list("era 지속 구간(전환 사이) — 이 구간에서는 트레일링 통계가 era 를 맞힌다(전체 적중률 0.552 > base 0.503)"),
      weakens_or_reverses_in = list("era 전환 국면 — 적중률 0.259 로 동전보다 유의하게 낮게 **반전**",
                                    "구조 단절 직후 12~24개월 (누적 편차 미축적 구간)"),
      boundary_rationale = paste0("경계는 기전에서 도출된다: 트레일링 추정량은 단절 이후 표본이 쌓여야 반응하므로, ",
        "지속 구간에서는 관성으로 맞고 전환 구간에서는 관성으로 틀린다. 따라서 '언제 맞는가'는 ",
        "'예측이 필요없는 때'와 정확히 겹치고, '틀리는 때'가 '예측이 필요한 때'다 — 이 정렬이 lane 을 닫는다.")
    )
  ),
  verdict = "blocked_by_capability",
  blocker = paste0("(1) 표현 계층: era 는 종목 횡단면 스코어가 아니라 **팩터 집단의 시계열 상태량**이며, ",
    "AST 𝒪(CS_5 + TS_10 + 산술 8 + 조건 3 + AS_OF/VINTAGE)에는 확장창 구조단절 탐지(CUSUM argmax) 연산자도 ",
    "'전 팩터 공통 상태'를 담는 리프도 없다. (2) ★더 근본적으로 — 본 라운드의 실측이 보이는 것은 ",
    "연산자를 추가해도 열리지 않는다는 것이다. 동일 정보집합 위의 서로 다른 8개 arm(CUSUM/트레일링 4종/",
    "횡단면 구조/스프레드·벤치/집중도)이 전부 전이 국면에서 chance 미만인 반면, 정보집합만 미래로 확장한 ",
    "누출 arm 은 즉시 발화(전기간 CUSUM 0.764 / 오라클 1.000)했다. 병목은 **연산자가 아니라 리프**다."),
  unblock_requirement = paste0("era 전환을 *선행*하는 비-return 관측치 리프. 후보 3종과 각각의 게이트: ",
    "① 대차/공매도 잔고(F1_short_interest_lending — 레짐 전환 전 포지셔닝 변화가 수익에 앞설 수 있음, 데이터 존재 확인 필요) ",
    "② 투자자 주체별 순매수의 집단 구조 변화(A6/A8 — 외인·기관 수급 레짐) ",
    "③ 매크로 vintage(E1_fred_macro_raw — 단 **현행 저장소는 vintage 미보존**이라 PIT-clean 실시간 재현 불가. ",
    "vintage 저장 배관이 선행 요건이며, 그 전에는 이 lane 측정 자체가 금지). ",
    "★𝒪 확장은 요청하지 않는다 — 연산자를 늘려도 열리지 않음이 본 라운드의 실측이고, ",
    "선제 확장 금지 규율(SOT §2)에 정합한다."),
  operator_backlog_requested = FALSE,
  operator_backlog_rationale = "𝒪 확장이 병목이 아님이 실측됨(누출 arm 은 같은 연산자로 발화). 근거 없는 연산자 확장 요청은 backlog 오염.",
  factors = FACTORS,
  factors_note = paste0("factors[] = 측정 대상 pool 285 (registry 리프 전량 열거). 본 라운드는 이들을 alpha 후보가 아니라 ",
    "era 공통성분의 구성 관측치로 소비했다 — 신규 alpha 산출 0건."),
  self_pit_check = list(performed = TRUE,
    leaves_checked_n = length(POOL),
    verdict = "clean",
    notes = list(
      "예측은 전부 s <= t 정보집합. 누출 arm 3종은 **의도적 위반 주입**으로 명시 라벨(peek6/fullcusum/oracle).",
      "target(y_t) 은 미래 수익을 쓰지만 그것은 평가 대상이지 예측 입력이 아니다.",
      "★잔여 PIT 주의 — pool composition survivorship: 285 factor 는 오늘 registry 기준으로 선택됐다. 완화 실측 2종: (a) 완전관측 246 한정 결론 불변 (b) pool 무작위 반분 era 지수 상관 0.988. 그러나 '오늘 존재하는 factor 집합'이라는 사실 자체는 제거 불가 — 정직 라벨.",
      "기존 국면 라벨(E7)은 **음성 대조로만** 사용, 추정자 재사용 금지 설계 제약 준수."),
    availability_note = "리프 가용성 규칙은 WT-005 상속 (factor_registry availability 기준, 연간 재무 익년 3/31 C4)"),
  combination_rule = "single_factor",
  alpha_vector = structure(list(), names = character(0)),
  alpha_vector_note = "빈 객체 = 정상. 본 라운드는 종목 alpha 를 산출하지 않는다(가능성 판정 라운드).",
  confidence_vector = structure(list(), names = character(0)),
  signal_matrix_ref = "stage_artifacts/WT_D20260803_006/alpha_scores.parquet (era 판정 패널 — 종목 스코어 아님)",
  factor_specs = FSPEC,
  alpha_discovery_count = 0L,
  alpha_inheritance_cor = 0,
  selection_objective = "canonical_port_t",
  selection_objective_note = paste0("원천 시계열은 canonical PORT_t 하네스 산출(WT-005 상속)이며, 본 라운드에는 ",
    "후보 선택 행위가 없다 — primary 추정자 1개를 측정 전 확정(chain). enum 준수를 위해 원천 목적함수를 기입."),
  diagnostics = list(
    canonical_port_t_nw_lag3 = NULL,
    canonical_port_t_note = paste0("단일 alpha 후보가 없어 단일 값 부여 불가(schema null 허용). 원천 풀 census 는 ",
      "WT-005 상속: 285 factor 전기간 canonical PORT_t 중앙값 -0.219 / >=2.95 통과 0건 (metric_type=canonical_screen, ",
      "본 라운드가 재산출한 값이 아님 — 상속 라벨)."),
    canonical_n_months = 287L,
    era_nowcast_accuracy = n4(Sp$acc[["rt_cusum"]]),
    era_nowcast_base_rate = n4(Sp$acc[["br_rt"]]),
    era_nowcast_delta = n4(Sp$d1_mean),
    era_nowcast_bootstrap_p = n4(Sp$d1_p),
    era_nowcast_transition_accuracy = n4(Sp$acc_trans[["rt_cusum"]]),
    era_nowcast_transition_bootstrap_P_ge_half = n4(R6$tr_boot_p),
    era_nowcast_oracle_accuracy = n4(Sp$acc[["oracle"]]),
    era_nowcast_lookahead_accuracy = n4(Sp$acc[["fullcusum"]]),
    detection_lag_major_transitions_months = c(24L, 22L),
    rank_ic = NULL, rank_ic_note = "본 라운드는 횡단면 신호를 산출하지 않아 rank IC 정의 불가. WT-005 상속값(풀 중앙값 0.0113)을 본 라운드 산출로 주장하지 않는다.",
    icir = NULL, monotonicity = NULL, post_neutralization_ic = NULL,
    subperiod_stability = n4(Sp$acc[["rt_cusum"]]),
    subperiod_stability_note = "본 라운드에서는 'era 방향 실시간 적중률'로 정의(h=24 primary, n=203).",
    turnover_proxy = NULL, turnover_note = "포트폴리오를 구성하지 않음.",
    deflated_sharpe_ratio = NULL,
    dsr_note = "selection_type=chain — primary 추정자 1개 측정 전 확정, argmax/threshold-pick 없음. DSR 게이트 부적용(measurement-graduation §3)."
  ),
  metric_type = "canonical_screen (원천) / diagnostic (본 라운드 통계)",
  gate_eligible = FALSE,
  gate_eligible_reason = "가능성 판정 라운드 — 전략·자본 주장 없음. graduation HARD 3종 적용 대상 아님.",
  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH", resolution = "ACCEPT",
         flag = "전체 적중률 축은 구조적으로 미검정력 — 관측 Δ +0.049 확정에 유효 블록 279개(≈820년) 필요.",
         handling = "'전체 적중률로는 판정 불가'를 명시 라벨. 판정 하중은 전이-조건부 축(방향 있는 결과)으로 이동."),
    list(id = "CF-02", severity = "HIGH", resolution = "REBUTTAL",
         flag = "전이 부분집합(y_t != y_{t-h})은 정의상 트레일링 추정자에 불리하다 — 0.259 는 인위적 낮음 아닌가.",
         handling = paste0("반증: 같은 부분집합에서 누출 arm 은 발화한다(INJ_PEEK6 0.407 / INJ_FULLSAMPLE_CUSUM 0.593 / ",
           "ORACLE 1.000). 부분집합이 구조적으로 모든 추정자를 눌렀다면 누출 arm 도 눌렸어야 한다. ",
           "★단 trail24 의 0.000 은 정의상 항등(예측 = y_{t-24}, 부분집합 = y_t != y_{t-24})이므로 증거에서 제외했다.")),
    list(id = "CF-03", severity = "MEDIUM", resolution = "PARTIAL",
         flag = "pool composition survivorship — 285 factor 는 오늘 registry 기준 선택.",
         handling = "완화 2종 실측(완전관측 246 한정 결론 불변 / 반분 상관 0.988). 제거 불가분은 정직 라벨로 잔존."),
    list(id = "CF-04", severity = "MEDIUM", resolution = "ACCEPT",
         flag = "지속 era 에피소드 9개 = 독립 정보량 상한. 어떤 결론도 대표본 주장 불가.",
         handling = "에피소드별 전환 8회를 표로 전량 공개(탐지 지연 포함). 요약 통계가 아니라 원시 사건이 증거."),
    list(id = "CF-05", severity = "HIGH", resolution = "PARTIAL",
         flag = "primary 추정자(RT_CUSUM)가 단지 약한 설계라서 실패한 것 아닌가 — AX-000 조기 한계 단정 위험.",
         handling = paste0("동일 정보집합 위 **10 arm**(CUSUM / 트레일링 4 / 횡단면구조 / 스프레드·벤치 / 집중도 / ",
           "13피처 다변량 실시간) + 음성대조 1 을 전부 측정. 자기 평가 부분집합 base 대비 **명목 초과 5건**",
           "(전부 트레일링 계열, 최대 +0.0493)이나 어느 것도 유의하지 않다(primary p=0.362). ",
           "로지스틱 3종·다변량은 자기 base 대비 -0.157~-0.200 미달. ",
           "★단 이것은 **정보집합-scoped negative** 이며 구조 판결이 아니다 — 검정력 자체가 낮아(유효 블록 5.6) ",
           "'우위 부재'를 확정할 힘이 없다. unblock_requirement 의 비-return 리프 3종은 미측정 축으로 열려 있다(INV-7).")),
    list(id = "CF-06", severity = "LOW", resolution = "ACCEPT",
         flag = "target 이 knife-edge(E>0.5)라 부호가 잡음일 수 있음.",
         handling = "|E-0.5|>0.1 부분집합 재측정 — 전체 0.625 로 오르지만 전이월은 0.278 로 동일 결론."),
    list(id = "CF-07", severity = "HIGH", resolution = "ACCEPT",
         flag = "★자체 적발 — 내가 만든 'in-sample 치팅 상한 0.857' 은 공허했다. 순열 귀무도 0.850 (p=0.477).",
         handling = paste0("증거에서 제외. 203개 자기상관 관측 위 13피처 로지스틱은 **무작위 target 도 보간**한다. ",
           "순열 대조를 붙이지 않았다면 이 값을 '트레일링 피처 공간에 정보가 실재한다'로 보고했을 것 — ",
           "발굴 조건이 검증 통과를 보장하면 그 검증은 없는 것과 같다(2026-08-02 계통)."),
         self_rationalization_check = "'대체로 정보가 있다고 볼 수 있다' 류 서술을 쓰지 않았는지 재검 — 해당 없음(수치로 기각)"),
    list(id = "CF-08", severity = "HIGH", resolution = "ACCEPT",
         flag = paste0("★자체 적발 — 13피처 실시간 arm 이 0.650(전이 0.691)로 유일하게 base 를 넘는 것처럼 보였다. ",
           "1차 로그에 내가 '전 피처를 줘도 base 근방/미만'이라고 **결과를 보기 전에 쓴 해석**이 실제 수치와 어긋났다."),
         handling = paste0("3중 통제로 기각: (i) 부분집합 이동 — 학습 최소표본 조건으로 평가가 2014-07~2024-06 로 밀렸고 ",
           "그 구간 상수규칙('항상 -1')이 0.7333 으로 F(0.6500)를 **이긴다** (ii) 동일 파이프라인 순열 귀무 p=0.342 ",
           "(전이 p=0.217) (iii) 전이월 0.691 은 그 부분집합 클래스 불균형 0.632 재현 수준. ",
           "★교훈: 부분집합이 이동하면 base rate 도 함께 이동한다 — 전역 base 와 비교하면 거짓 우위가 생긴다."),
         self_rationalization_check = "하드코딩된 해석 문구를 실측이 반증했고, 문구가 아니라 실측을 채택했다"),
    list(id = "CF-09", severity = "HIGH", resolution = "ACCEPT",
         flag = paste0("★자체 적발 — 초안 서술 '실시간 arm 10종 중 자기 평가구간 상수규칙을 넘은 것 0건' 은 ",
           "**과대주장이었다**. 전체표본 arm(rt_cusum 0.5517 / trail36·60 0.5468 / trail24 0.5271 / trail12 0.5123)은 ",
           "BR_maj 0.5025 를 명목상 **넘는다**. CF-08 로 F arm 을 기각한 뒤 그 표현을 전 arm 에 부주의하게 일반화했다."),
         handling = paste0("arm 전수를 자기 평가 부분집합 base 와 1:1 대조해 표로 재측정(arm_vs_own_base_rate 절, ",
           "arm_vs_own_baserate.csv). 정정 서술 = '명목 초과 5건이나 초과폭 최대 +0.0493 이고 primary bootstrap ",
           "p=0.362 — 어느 것도 우위를 유의하게 확립하지 못했다'. ★대신 더 강한 대비를 확보했다: ",
           "가장 큰 clean 우위 +0.049 vs 가장 작은 누출 우위 +0.148 = 3배. 판정 하중을 '0건'이라는 ",
           "취약한 절대 진술에서 '누출 대비 배수'라는 관측으로 옮겼다."),
         self_rationalization_check = "정정 후에도 결론(FAIL, 정보집합-scoped)은 불변임을 확인 — 결론 보존을 위해 수치를 고른 것이 아니라, 수치가 결론을 더 정확한 근거 위로 옮겼다")
  ),
  verdict_summary = paste0("FAIL(정보집합-scoped) — era 는 실재하는 공통성분이나(pool 반분 상관 0.988, family 상관 0.75~0.96, ",
    "WT-005 창별 양수비율 0.754/0.908/0.216/0.021 정확 재현) 현 정보집합에서 사전 관측 불가. ",
    "실시간 적중률 0.552 vs base 0.503 (Δ+0.049, block bootstrap p=0.362 미유의), era 전환 국면 0.259. ",
    "실시간 arm 10종 + 음성대조 1 중 자기 평가 부분집합 base 대비 우위를 **유의하게 확립한 것이 0건**",
    "(명목 초과 5건, 최대 +0.0493, p=0.362). ",
    "반면 정보집합만 미래로 연 누출 arm 은 즉시 발화(오라클 1.000 / 전기간 CUSUM 0.764 / peek6 0.650) — ",
    "대상은 예측 가능하되 과거로부터는 아니다. 주요 전환 2회 탐지 지연 24m·22m ≥ 지평 24m. ",
    "★자체 적대검증 2건이 거짓 우위를 걷어냈다(in-sample 상한 0.857 = 순열 귀무 0.850 로 공허 / ",
    "13피처 실시간 0.650 = 부분집합 상수규칙 0.733 에 패배). ",
    "⇒ 정적 자격 게이트 lane 은 현 정보집합에서 닫힘. 구조 판결 아님(검정력 유효 블록 5.6) — ",
    "여는 조건 = era 전환을 선행하는 비-return 리프.")
)

write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, null = "null")
say("alpha_package.json 저장 (factors %d / factor_specs %d)", length(FACTORS), length(FSPEC))

# ── 4. lineage (반드시 package write 이후 — L-194) ───────────────────────────
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260803_006",
  package_type = "alpha_package",
  method_selected = "RT_CUSUM 실시간 확장창 구조단절 탐지 (primary, 측정 전 확정) + 8-arm 대조 + 위반 주입 3종",
  input_file_paths = c(
    "stage_artifacts/WT_D20260803_005/canonical_pool.rds",
    "stage_artifacts/WT_D20260803_005/registry_labels.rds",
    "stage_artifacts/WT_D20260803_006/preregistration.json",
    ".cache/RAWDATA.parquet",
    ".cache/unified_regime_signal.parquet")
)
say("lineage 기록 완료")
say("DONE")
