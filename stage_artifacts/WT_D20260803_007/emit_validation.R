# =============================================================================
# emit_validation.R — WT-D20260803_007 (FQ-135) alpha_validation.json + L-code
# 실행: Rscript stage_artifacts/WT_D20260803_007/emit_validation.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
WT <- "WT-D20260803_007"; OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
say <- function(fmt, ...) cat(sprintf(paste0("[wt007V] ", fmt, "\n"), ...))
MB <- readRDS(file.path(OUT, "memberships.rds")); AR <- readRDS(file.path(OUT, "arm_results.rds"))
PH <- readRDS(file.path(OUT, "posthoc_results.rds")); XP <- readRDS(file.path(OUT, "adversarial_probes.rds"))
SUM <- AR$summary; PAIRS <- AR$pairs
gv <- function(a, c) SUM[arm == a, get(c)]
dt2l <- function(d) lapply(seq_len(nrow(d)), function(i) as.list(d[i]))

V <- list(
  task_id = WT, fq = "FQ-135", generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type = "canonical_screen", gate_eligible = FALSE, capital_claim = "none",
  selection_type = "chain", dsr_gate_applicability = "not_applicable (chain — 사전등록 단일 선택규칙, argmax/threshold-pick 없음)",
  preregistration_ref = "stage_artifacts/WT_D20260803_007/preregistration.json",
  build_hash = MB$build_hash,

  harness = list(
    measurement = "02_Infrastructure/contracts/canonical_screen_bt.R::canonical_screen_bt()",
    portfolio = "top-25 EW long-only", cost_bps_oneway = 15, liq_min_won = 2e8,
    universe = "KOSPI200 ∪ KOSDAQ150 (RAWDATA 시변 멤버십)",
    benchmark_basis = "cap-w 유니버스 시총가중 forward return (build_monthly_forward_returns) — WT-004/005 동일 vintage",
    signal_path = "load_month_factors(sig_date) (C15) → Z_Score_Aligned (C13 NEGATE/FLIP 없음)",
    pool = sprintf("%d factor (WT-005 가용성 규칙 + active 상관 0.99 중복제거 후)", length(MB$pool)),
    walk_forward = "IS0=120월 확장 IS / OOS 블록 24월 / step 7 / OOS 167월 (2012-08-31 ~ 2026-06-30)",
    era_definition = "IS 끝 정렬 비중첩 36개월 창, 유효 >= 30월",
    composite = "z_score_aligned_equal_weight, 멤버 커버리지 >= 60%"),

  discriminants = list(
    a_selector_discriminates = list(
      definition = "OOS paired NW(lag3) t( active[A_REL_TOP] - active[A_REL_BOT] ) >= +2.0",
      t = AR$disc$a_t, mean_diff_annual = PAIRS[pair == "A_REL_TOP - A_REL_BOT", mean_diff_ann],
      win_rate = PAIRS[pair == "A_REL_TOP - A_REL_BOT", win_rate],
      verdict = ifelse(AR$disc$a, "PASS", "FAIL")),
    b_construction_beats_single = list(
      definition = "OOS paired NW(lag3) t( active[A_REL_TOP] - active[SINGLE_BEST] ) >= +2.0  ★진짜 관문",
      t = AR$disc$b_t, mean_diff_annual = PAIRS[pair == "A_REL_TOP - SINGLE_BEST", mean_diff_ann],
      win_rate = PAIRS[pair == "A_REL_TOP - SINGLE_BEST", win_rate],
      verdict = ifelse(AR$disc$b, "PASS", "FAIL")),
    combined_reading = "neither — 사전등록 해석: '예측도 안 되고 robust 선별도 안 된다. 현 재료에서 이 구성 lane 은 닫힌다.' 단 아래 power_limit 및 dual_basis 유보를 함께 읽을 것."),

  arms = dt2l(SUM),
  paired_tests = dt2l(PAIRS),

  posthoc_attribution = list(
    note = "★사전등록 아님 — 판별 (a)/(b) 산출·기록 후 기전 귀속 목적으로 arm 1개만 추가. 판별 문턱에 재적용하지 않았다.",
    arm = "LEVEL_TOP_K20 = IS 전기간 level PORT_t 상위 20 (walk-forward, IS-only) = SINGLE_BEST(K=1)의 K=20 확장",
    port_t = PH$port_t, ew_basis_port_t = PH$ew_port_t, ir = PH$ir, turnover = PH$turnover,
    random_null_percentile = PH$rand_pct,
    pairs = dt2l(PH$pairs),
    conclusion = sprintf("A_REL_TOP − LEVEL_TOP_K20 paired t = %+.3f (음수). era-robustness 는 IS level 대비 순증분이 없다. 독립 2경로 확증: (i) level-직교 arm A_PERP_TOP standalone PORT_t %+.3f (ii) 사후 귀속 음수.",
      PH$pairs[pair == "A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3], gv("A_PERP_TOP", "port_t"))),

  random_null = list(
    n_draw = nrow(AR$rand), mean_port_t = mean(AR$rand$port_t, na.rm = TRUE),
    q025 = unname(quantile(AR$rand$port_t, .025, na.rm = TRUE)),
    q975 = unname(quantile(AR$rand$port_t, .975, na.rm = TRUE)),
    a_rel_top_percentile = 100 * mean(AR$rand$port_t <= gv("A_REL_TOP","port_t"), na.rm = TRUE),
    a_rel_bot_percentile = 100 * mean(AR$rand$port_t <= gv("A_REL_BOT","port_t"), na.rm = TRUE),
    paired_vs_random_median_t = median(AR$rand_paired$t_nw, na.rm = TRUE),
    paired_vs_random_share_ge2 = mean(AR$rand_paired$t_nw >= 2, na.rm = TRUE),
    interpretation = "★본 하네스의 귀무는 0 이 아니다 — cap-w 벤치 하 무작위 K=20 composite 평균 PORT_t 가 음수. A_REL_TOP 은 귀무 99.0 백분위(A_REL_BOT 68.0)로 선택자가 무작위와는 분리되나, 그 분리의 원천은 사후 귀속상 level 이다."),

  violation_injection = list(
    fired = AR$disc$injection_fired,
    clean_a_t = AR$disc$a_t,
    leak_fullsample_vs_bot_t = PAIRS[pair == "LEAK_FULLSAMPLE - A_REL_BOT", t_nw_lag3],
    leak_oracle_vs_bot_t = PAIRS[pair == "LEAK_ORACLE_OOS - A_REL_BOT", t_nw_lag3],
    leak_fullsample_port_t = gv("LEAK_FULLSAMPLE", "port_t"),
    leak_oracle_port_t = gv("LEAK_ORACLE_OOS", "port_t"),
    reading = "OOS 정보를 robustness 판정에 섞으면 결과가 실제로 좋아진다(1.212 → 2.092 → 4.367). IS-only 규율이 실구속임이 실증됐고, clean 판정이 '검사력 부족으로 아무것도 안 잡힌 것'이 아님을 보장."),

  robustness = list(
    parity = list(p1_composite_top80_truncation = dt2l(AR$parity$p1),
                  p2_fastpath = dt2l(AR$parity$p2),
                  note = "둘 다 max_abs_diff = 0 — composite 저장 절단과 선택 재현이 canonical 과 완전 일치"),
    lag1_stress = dt2l(AR$lag1),
    placebo_shuffle = list(port_t = AR$placebo$port_t, mean_active = AR$placebo$mean_active,
      note = "월내 ticker 셔플. 기대 0 이 아니라 무작위 귀무([-2.079, 0.257]) 내부여야 정상 — 실측 -1.585 는 구간 내부 = 하네스 정상."),
    era_window_sensitivity = dt2l(XP$ap1),
    threshold_fragility_block_bootstrap = dt2l(XP$ap4),
    basis_invariance = dt2l(XP$ap5),
    ic_lag_attribution = dt2l(XP$ap3),
    metric_degeneracy = list(per_step = dt2l(XP$ap2), mean_abs_era_t = XP$ap2_mabs),
    turnover_annual = list(A_REL_TOP = gv("A_REL_TOP","turnover_annual"),
      SINGLE_BEST = gv("SINGLE_BEST","turnover_annual"), LEVEL_TOP_K20 = PH$turnover,
      ceiling = 11.0, breach = gv("A_REL_TOP","turnover_annual") > 11.0)),

  dual_basis = list(
    note = "v8.3 M2 — cap-w HARD 판정 권위 불변. EW-유니버스 대비는 비바인딩 진단(metric_type=canonical_screen_diag).",
    cap_w_vs_ew = dt2l(SUM[, .(arm, port_t_capw = port_t, port_t_ew_universe = ew_port_t,
                               cap_share_mega = cap_mega, cap_share_mid = cap_mid)]),
    level_top_k20_ew = PH$ew_port_t,
    label = "cap-w FAIL ∧ EW-대비 생존 — A_REL_TOP 0.897→2.193, LEVEL_TOP_K20 1.028→2.860. '벤치 구성 미스매치 가능' 라벨 부여, screen_route 재분류 검토 대상. 단 ★paired 판별식 (a)/(b) 는 basis 불변(AP5)이므로 이 유보가 판정을 뒤집지 않는다 — 유보의 대상은 standalone PORT_t 해석뿐."),

  conditional_decomposition = list(
    ax001_v2_and_subperiod = dt2l(AR$cond),
    ax001_note = "AX-001 v2 — 방어 family 는 WT-005 지속률 최저(0.465)이나 그 저지속은 위기 캘린더 종속(cor +0.842). 본 라운드는 방어형을 전기간 SR/PORT_t 로 채점하지 않고 BM<0 월 조건부로 병기했다.",
    family_share_vs_wt005 = dt2l(as.data.table(AR$fam)),
    family_spearman = as.list(AR$fam_spearman),
    membership_jaccard = dt2l(AR$memb_turnover),
    wt005_consistency = sprintf("A_REL_BOT 의 family 구성은 WT-005 지속률과 Spearman %+.3f (역방향 = 정합: 저지속 family 인 defense 0.193 / liquidity 0.143 / risk 0.121 를 하위가 흡수). A_REL_TOP 은 %+.3f 로 약함 — 상위 tail 은 value 0.243 / consensus 0.193 편중이며 WT-005 지속률 순위와 정렬되지 않는다. cap-tier 는 WT-005(소형 0.614 > 대형 0.514)와 정합적으로 A_REL_TOP 의 MEGA 비중이 낮다.",
      AR$fam_spearman[["bot"]], AR$fam_spearman[["top"]])),

  power_limit = list(
    n_oos_months = 167,
    a_p_reach_2 = XP$ap4$p_reach_2[1], b_p_reach_2 = XP$ap4$p_reach_2[2],
    posthoc_p_reach_2 = XP$ap4$p_reach_2[3],
    honest_statement = "★'효과 없음'을 증명한 것이 아니다. 167개월 블록 부트스트랩에서 (a)/(b) 가 문턱 +2.0 에 도달할 확률이 각각 20.9% / 21.3% 남아 있다. 판정은 '사전등록 문턱 미달'이며 '부재 증명'이 아니다. 반면 사후 귀속(era-robustness 순증분 <= 0)은 P(t>=2)=0.85% 로 훨씬 조밀 — 이 라운드가 실제로 확정한 것은 (a)/(b) 실패보다 '순증분 없음' 쪽이다."),

  base_and_parity = list(incumbent_base_consumed = FALSE, production_parity_verified = "not_applicable",
    rationale = "모든 arm 이 factor DB z 로부터 자기완결 구성 — 05_Production 파생 저장 패널이나 book incumbent 시계열을 base 로 소비하지 않음(2026-07-14 동월 look-ahead 실사고 노출면 없음). 후속 라운드가 arm 을 production rank-tilt 위 개입으로 소비할 때 parity 라벨 의무 발생."),

  verdict = list(
    headline = "era-robust 성분 선별은 현 재료에서 순증분이 없다 — 우위의 원천은 era-robustness 가 아니라 IS level 이었다",
    a = ifelse(AR$disc$a, "PASS", "FAIL"), b = ifelse(AR$disc$b, "PASS", "FAIL"),
    metric_discriminates = sprintf("부분 — 무작위 대비는 분리(99.0 백분위)하나 상위-하위 대비는 문턱 미달(t %+.3f). 하위 tail 은 무작위보다 오히려 나음(백분위 68.0) = 지표의 음의 정보가 없다.", AR$disc$a_t),
    construction_lane = "config-scoped 미달 — 구조 판결 아님. era-robust 축(minimax, 절대/상대/level-직교 3변형 x K∈{10,20,40} x W∈{24,36,48})에서 survivors 0.",
    what_was_established = list(
      "era-robustness(level 순증분)는 <= 0 — 독립 2경로(A_PERP_TOP -1.068, 사후 귀속 -0.571) 확증",
      "level 제거 시 지표는 inert factor 선택기로 퇴화 (선택 멤버 평균 |era t| 0.843 < 풀 0.890 이하 수준, defense/quality/liquidity 편중)",
      "본 하네스의 cap-w 귀무는 0 이 아니라 약 -0.94 — EW top-25 의 구조적 음수 드리프트 (16/16 admission FAIL 을 읽는 새 좌표)",
      "IS level 상위 20 EW composite = 시험한 선택자 중 최선(cap-w 1.028 / EW-basis 2.860 / 무작위 100 백분위)이나 여전히 2.95 벽 미달·post2017 음수",
      "IC→PORT_t 전이 벽 독립 재현 — POOL_EW rank IC(0.063, t 4.58) > A_REL_TOP(0.027, t 3.01) 인데 PORT_t 는 역전")),

  next_probe = list(
    list(id = "NP-1", title = "cap-w 귀무의 정체 분해 — 사이즈 중립 composite 이 EW-basis 2.86 을 cap-w 로 옮길 수 있는가",
      rationale = "본 라운드가 처음 정량화한 사실: 무작위 K=20 composite 의 cap-w PORT_t 평균이 -0.941, EW-유니버스 basis 로는 LEVEL_TOP_K20 이 2.860. 즉 벽의 상당분이 신호가 아니라 사이즈 노출이다. 미측정: 사이즈-중립화(또는 cap-tier 별 정원 배분)한 composite 의 cap-w PORT_t.",
      measurable_now = TRUE, consumption_surface = "①팩터 랭킹 + ⑥선별 라벨"),
    list(id = "NP-2", title = "MID-tier 국소화 — level 선별의 post-2017 음수(-0.490)가 MEGA 벤치 아티팩트인가",
      rationale = "v8.3 실측(MID tier LS t=3.02 vs MEGA 0.59)과 본 라운드 cap_share 분해를 결합. 미측정: LEVEL_TOP_K20 을 MID(11-30위) 유니버스로 제한했을 때 post2017 PORT_t.",
      measurable_now = TRUE, consumption_surface = "②유니버스 필터"),
    list(id = "NP-3", title = "지표를 선택기 아닌 '배제기'로 — inert factor 제거가 풀 품질을 올리는가",
      rationale = "본 라운드는 top-tail 만 시험했다. A_PERP 상위 = inert(평균 |era t| 0.843 ≪ 풀) 임이 실측됐으므로, 그 집합을 풀에서 *빼고* level 선별을 재구성하는 방향은 미측정. 2026-08-02 실측 선례: 랭킹으로 죽은 MAX5 가 필터로는 ΔIR +0.169.",
      measurable_now = TRUE, consumption_surface = "②유니버스 필터 + ⑥선별 라벨"),
    list(id = "NP-4", title = "era_sd 를 risk 레인의 factor 불안정성 입력으로 이식",
      rationale = "era 간 t 표준편차는 본 라운드에서 선택에는 무용했으나 factor-수준 불안정성 지표로는 미소비. risk-research 의 crowding/style 진단 입력 후보 — alpha 경계 밖이므로 이관.",
      measurable_now = TRUE, consumption_surface = "④위험모델·β예산 (risk lane 이관)")),

  consumption_surface_sweep = list(
    note = "answer-principles §4 소비면 7종 명시 순회",
    p1_factor_ranking = "측정 — 본 라운드 주제. era-robust 랭킹 cap-w 미달, level 랭킹이 최선이나 2.95 미달. NP-1 로 계속.",
    p2_universe_filter = "미측정 → NP-2 / NP-3 등재",
    p3_overlay_regime_input = "해당 없음 — era 는 WT-006 이 사전 관측 불가로 확정. 본 라운드는 era 예측을 시도하지 않았다.",
    p4_risk_beta_budget = "미측정 → NP-4 (risk lane 이관, alpha 경계 밖)",
    p5_monitoring_signal = "미측정 — worst-era 를 라이브 decay tripwire 로 쓰는 안은 유계지표+고정 z 문턱의 구조적 침묵(2026-08-02 실측) 위험이 있어 '도달가능성 라벨' 선설계 없이는 등재하지 않음",
    p6_screen_label = "적용 — dual-basis 라벨(cap-w FAIL ∧ EW 생존) 부여. screen_route 재분류은 judge/governor 권한이므로 권고만.",
    p7_cross_mode = "RAMP Gate4 순수팩터 sleeve 진단에 worst-era 지표 이식 가능 — 단 본 라운드가 선택기로는 무용을 실측했으므로 진단축으로만 권고"),

  revival_conditions_inv7 = list(
    "관측 가능한 era 라벨이 확보되는 경우 (자격 관문: 전이-조건부 적중 > base ∧ 순열 p<0.05) — 그때는 era-robust(수동적)가 아니라 era-conditional(능동적) 선별이 되살아난다",
    "비-return 리프(FQ-136 대차/공매도 잔고 등)가 풀에 들어와 era 민감도의 구조가 달라지는 경우 — 현 풀은 전량 return/재무 파생이라 era 공통성분을 공유한다",
    "cap-w 벤치 아티팩트가 NP-1/NP-2 로 분해되어 EW-basis 2.86 이 cap-w 로 옮겨지는 경우 — 그때 선택자 비교를 재실행(현재는 모든 arm 이 구조적 음수 드리프트 아래 눌려 판별력 자체가 낮다)"),

  boundaries = list(covariance_estimated = FALSE, weights_proposed = FALSE,
    graduation_declared = FALSE, book_claim = FALSE,
    note = "composite = alpha score 합성(z_score_aligned_equal_weight). top-25 EW 는 canonical_screen_bt 고정 규격이며 weight 결정 행위 아님.")
)
write_json(V, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
say("alpha_validation.json 저장 (%.1f KB)", file.info(file.path(OUT, "alpha_validation.json"))$size / 1024)

# ── L-code 아티팩트 ────────────────────────────────────────────────────────
dir.create("stage_artifacts/l_code/alpha_research", recursive = TRUE, showWarnings = FALSE)
lesson <- paste0(
"WT-005/006 이 'era 공통성분이 자격을 지배하고 era 는 사전 관측 불가'를 확정한 뒤, 질문을 '언제 통하나'에서 ",
"'어느 era 에서도 덜 죽나'로 바꿔 실측했다. 사전등록 primary 지표 = era-demean 후 각 era PORT_t 의 최소값(minimax). ",
sprintf("285-factor 풀, walk-forward 7 step(IS 확장 / OOS 24월 블록, 총 167월 2012-08~2026-06), K=20 EW composite, canonical top-25 EW 15bps. "),
sprintf("결과: (a) 상위-하위 paired NW(lag3) t = %+.3f, (b) 상위-단일최강 = %+.3f — 사전등록 문턱 +2.0 양쪽 미달. ", AR$disc$a_t, AR$disc$b_t),
sprintf("★핵심은 사후 기전 귀속이다: A_REL_TOP - LEVEL_TOP_K20(IS level 상위20) paired t = %+.3f (음수)이고 level-직교 arm A_PERP_TOP standalone PORT_t = %+.3f. ",
  PH$pairs[pair == "A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3], gv("A_PERP_TOP","port_t")),
sprintf("독립 2경로가 같은 결론 — 무작위 200 draw 대비 99.0 백분위라는 A_REL_TOP(PORT_t %+.3f)의 우위는 era-robustness 가 아니라 IS level 의 재선택이었다. ", gv("A_REL_TOP","port_t")),
sprintf("더 나아가 level 을 제거하면 지표는 '조용한(inert) factor 선택기'로 퇴화한다 — 선택 멤버 평균 |era t| %.3f vs 풀 %.3f, cor(perp, era_sd) %.2f~%.2f, family 는 defense 0.34/quality 0.20/liquidity 0.14 로 WT-005 최저 지속률 family(방어 0.465·유동성 0.487)에 정확히 겹친다. ",
  XP$ap2_mabs$perp, XP$ap2_mabs$pool, min(XP$ap2$cor_perp_erasd), max(XP$ap2$cor_perp_erasd)),
"사전에 metric ④(era 간 분산 단독)의 실패모드로 예고했던 '죽은 factor 선택'이 metric ③ 의 level-잔차화에서 실현된 것이다. ",
sprintf("창 길이 W∈{24,36,48}, K∈{10,20,40}, 단일분할(IS191/OOS96) 대조 전부에서 (a)/(b) 최대 t = %.3f / %.3f 로 미달 — 결론은 격자에 강건. ",
  max(XP$ap1[grepl("BOT", pair), t_nw_lag3], na.rm=TRUE), max(XP$ap1[grepl("SINGLE_BEST", pair), t_nw_lag3], na.rm=TRUE)),
sprintf("위반 주입 2종은 발화했다(전기간 지표 사용 시 paired t %.3f→%.3f, OOS oracle %.3f) — IS-only 규율이 실구속이고 clean 판정이 검사력 부족의 산물이 아님을 보장. ",
  AR$disc$a_t, PAIRS[pair=="LEAK_FULLSAMPLE - A_REL_BOT", t_nw_lag3], PAIRS[pair=="LEAK_ORACLE_OOS - A_REL_BOT", t_nw_lag3]),
sprintf("★부수 확립(다음 라운드 좌표): 본 하네스의 cap-w 귀무는 0 이 아니라 %.3f 다(무작위 K=20 composite 200 draw 평균 PORT_t; POOL_EW %.3f, placebo %.3f). ",
  mean(AR$rand$port_t, na.rm=TRUE), gv("POOL_EW","port_t"), AR$placebo$port_t),
sprintf("EW-유니버스 basis 로 옮기면 LEVEL_TOP_K20 %.3f / A_REL_TOP %.3f 로 부호가 뒤집힌다 — top-25 EW 의 구조적 사이즈 노출이 전이 벽의 상당분을 차지한다는 정량 근거다. ",
  PH$ew_port_t, gv("A_REL_TOP","ew_port_t")),
sprintf("단 판별식은 paired 차라 벤치가 정확히 상쇄되므로(AP5 잔차 %.1e) 이 유보는 (a)/(b) 판정을 바꾸지 않고 standalone PORT_t 해석에만 걸린다. ", max(XP$ap5$value)),
sprintf("정직 한계: 167개월 블록 부트스트랩(block=12, B=2000)에서 (a)/(b) 가 +2.0 에 도달할 확률이 각각 %.1f%% / %.1f%% 남아 있어 '효과 부재'를 증명한 것이 아니다 — 이 라운드가 확정한 것은 순증분 <= 0 쪽이다(P(t>=2)=%.2f%%). ",
  100*XP$ap4$p_reach_2[1], 100*XP$ap4$p_reach_2[2], 100*XP$ap4$p_reach_2[3]),
sprintf("추가 재현: IC→PORT_t 전이 벽 — POOL_EW rank IC %.4f(t %.2f) > A_REL_TOP %.4f(t %.2f) 인데 PORT_t 는 %.3f vs %.3f 로 역전. rank-IC advisory 강등의 독립 근거 1건 추가. ",
  XP$ap3[arm=="POOL_EW", ic_lag0], XP$ap3[arm=="POOL_EW", t_ic_lag0], XP$ap3[arm=="A_REL_TOP", ic_lag0],
  XP$ap3[arm=="A_REL_TOP", t_ic_lag0], gv("POOL_EW","port_t"), gv("A_REL_TOP","port_t")),
sprintf("구현 규율: A_REL_TOP 회전율 %.2f/yr > 상한 11.0 — 구성 lane 이 살아났더라도 별도 관문에 걸린다.", gv("A_REL_TOP","turnover_annual")))

LC <- list(
  l_code = "L-WT20260803_007", strategy_id = WT, research_mode = "alpha_research", fq = "FQ-135",
  title = "era-robust 성분 선별은 순증분 0 — '어느 era 에서도 덜 죽는' 기준은 level 을 재선택하거나 죽은 factor 를 고른다",
  type = "ANTI-PATTERN", grade = "F", metric_type = "canonical_screen",
  record_type = "measurement_round", gate_eligible = FALSE, capital_claim = "none",
  issued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), issued_by = "alpha-research (WT-D20260803_007)",
  core_reference = "WT-D20260803_005 (FQ-131 자격 지속성 — era 유지 0.959 vs 전환 0.304) + WT-D20260803_006 (FQ-133 era 사전 추정 불가 0.2593) + WT-D20260803_004 (조합 자격 IS/OOS 반전, V01_SECREL +2.634→-0.389) + Harvey-Liu-Zhu (2016) + McLean-Pontiff (2016) + Bai-Perron (1998)",
  lesson_text = lesson,
  key_metrics = list(discriminant_a_t = AR$disc$a_t, discriminant_b_t = AR$disc$b_t,
    posthoc_robustness_increment_t = PH$pairs[pair == "A_REL_TOP - LEVEL_TOP_K20", t_nw_lag3],
    a_rel_top_port_t = gv("A_REL_TOP","port_t"), a_perp_top_port_t = gv("A_PERP_TOP","port_t"),
    level_top_k20_port_t = PH$port_t, single_best_port_t = gv("SINGLE_BEST","port_t"),
    pool_ew_port_t = gv("POOL_EW","port_t"), random_null_mean_port_t = mean(AR$rand$port_t, na.rm=TRUE),
    a_rel_top_ew_basis = gv("A_REL_TOP","ew_port_t"), level_top_k20_ew_basis = PH$ew_port_t,
    n_oos_months = 167L, n_pool_factors = length(MB$pool), turnover_annual = gv("A_REL_TOP","turnover_annual")),
  next_probe = lapply(V$next_probe, function(x) list(id = x$id, title = x$title, measurable_now = x$measurable_now)),
  consumption_surface = V$consumption_surface_sweep,
  revival_conditions = V$revival_conditions_inv7,
  source_paths = "stage_artifacts/WT_D20260803_007/alpha_validation.json")
write_json(LC, "stage_artifacts/l_code/alpha_research/l_code_WT_D20260803_007_era_robust_zero_increment.json",
           pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
say("L-code 저장 — L-WT20260803_007 (%d자)", nchar(lesson))
saveRDS(list(V = V, lesson = lesson), file.path(OUT, "validation_bits.rds"))
