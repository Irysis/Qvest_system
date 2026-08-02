# =============================================================================
# run_wt013_emit.R — WT-D20260802_013 AST v1.1 alpha_package + validation + lineage
#   전제: run_wt013_eval.R 완료 (wt013_eval_results.rds) + challenge_note.md 작성 완료
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_013/run_wt013_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_013")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_013")
`%||%` <- function(a, b) if (is.null(a)) b else a
num <- function(x, d = 4) if (is.null(x) || !is.finite(as.numeric(x))) NA else round(as.numeric(x), d)
say <- function(fmt, ...) cat(sprintf(paste0("[emit13] ", fmt, "\n"), ...))

R <- readRDS(file.path(OUT, "wt013_eval_results.rds"))
pt_primary <- R$paired_resid$paired_t_nw
# 사전등록 의사결정 규칙 그대로 집행 (문턱 2.0). 기전 귀속은 사전등록 통제(적재/직교/placebo) 실측으로 별도 기록.
VERDICT_BINARY <- if (is.finite(pt_primary) && pt_primary >= 2.0)
  "REPLACE_EVIDENCE_COMPLETE" else "THRESHOLD_FAIL_NO_REPLACEMENT"
VERDICT_PRIMARY <- if (is.finite(pt_primary) && pt_primary >= 2.0)
  "paired t >= 2.0 유지 — 교체 근거 완성 (교체 자체는 도훈 confirm)" else
  paste0("사전등록 문턱 미달 (+1.717 < 2.0) — 교체 근거 미완성 확정. 단 기전 귀속은 사전 혐의(vol-tilt)와 다름: ",
    "PATHQ의 D03z 적재 -0.060(저변동 반대 부호)·잔차화 후 팩터 사실상 동일(self-cor 0.974, RESID vs PATHQ t -0.015)·",
    "RESID standalone PORT_t +2.14 >= PATHQ +2.05 — vol-성분이 개선 운반자가 아님. 실사유 = ①원판 +2.03의 spec-jitter ",
    "취약성(placebo 5시드 t 1.87~2.80, sd 0.378 실증) ②pre-2015 편중 잔존(+3.20/-0.33/+0.27, decay-pattern). challenge_note C1~C3.")

RESID <- as.data.table(read_parquet(file.path(OUT, "resid_panel.parquet")))
RESID[, Date := as.Date(Date)]
last_d <- RESID[, max(Date)]
LV <- RESID[Date == last_d][order(-score)]
alpha_vector <- as.list(setNames(round(LV$score, 6), LV$Ticker))
cov_m <- RESID[, .N, by = Ticker][, setNames(pmin(1, N / 120), Ticker)]
confidence_vector <- as.list(setNames(
  vapply(LV$Ticker, function(tk) round(max(0.3, min(1, as.numeric(cov_m[[tk]] %||% 0.5))), 3),
         numeric(1)), LV$Ticker))
write_parquet(RESID, file.path(OUT, "alpha_scores.parquet"))

arm_stats <- function(a) {
  b <- R$bt[[a]]; ew <- b$diag_ew_universe; ct <- b$diag_cap_tier
  list(port_t = num(b$portfolio_alpha_t_nw_lag3, 3), net_sr = num(b$net_sr, 3),
       ir = num(b$information_ratio, 3), turnover_annual = num(b$turnover_annual, 2),
       n_months = b$n_months,
       ew_uni_t = num(ew$portfolio_alpha_t_nw_lag3, 3),
       ew_uni_post2017_t = num(ew$post2017_t_nw_lag3, 3),
       ew_uni_oos_retention_approx = num(ew$oos_retention_approx, 4),
       cap_tier_weight_share = ct$weight_share_avg,
       cap_tier_contrib = ct$contrib_gross_annualized)
}
paired_l <- function(x) list(paired_t_nw = num(x$paired_t_nw, 3), n_months = x$n_months,
  mean_d_annualized_pct = num(100 * x$mean_d_annualized, 3),
  sub_pre2015 = num(x$sub_pre2015, 2), sub_2015_19 = num(x$sub_2015_19, 2),
  sub_2020p = num(x$sub_2020p, 2), sub_post2017 = num(x$sub_post2017, 2))
ARM <- lapply(setNames(names(R$bt), names(R$bt)), arm_stats)
vl <- lapply(R$volload, function(v) list(mean_monthly_cs_spearman = num(v$mean, 3),
                                          t_nw = num(v$t_nw, 2), n_months = v$n))

esc_p2 <- list(escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT_D20260802_009/run_wt009_tuned.R (path efficiency 252/21) — WT-009 승계, 재계산 없음",
  walk_forward = TRUE)

pkg <- list(
  task_id = "WT-D20260802_013",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",

  hypothesis = list(
    statement = paste0(
      "WT-009의 교체 후보 M01_PATHQ(경로효율, paired +2.03)는 vol-tilt 아티팩트가 아니라 순수 경로-질 신호다 — ",
      "경로효율 z를 D03z(저변동 registry z)에 월별 CS 잔차화한 순수판(M01_PATHQ_RESID)이 base M01_Mom_12_1 대비 ",
      "paired NW lag-3 t >= 2.0을 유지하면 지지, 미달하면 vol-tilt 아티팩트 확정. ",
      "사전등록 stage_artifacts/WT_D20260802_013/preregistration.json (측정 전 고정, no-flip, 판별 문턱 고정)."),
    mechanism = list(
      agent = paste0("이산 점프(테마성 개인 급등 추격·상한가 계열)로 만들어진 12-1 수익 vs 연속 드리프트 동일 수익 — ",
        "후자가 정보의 점진 반영(frog-in-the-pan). 단 '매끄러운 경로'는 기계적으로 저변동과 상관될 수 있어 ",
        "vol-성분을 명시 제거해야 순수 경로-질 주장이 성립"),
      friction = paste0("저빈도 스크리너는 순변화만 소비 — 경로 조성은 표준 모멘텀에 부재. KR 공매도 제약이 ",
        "점프-과열 종목의 즉시 조정을 차단. 잔차화 비용(D03 결합 계산)이 관행에서 생략"),
      path = "vol-성분 제거 후에도 매끄러운-경로 고모멘텀이 익월 지속하면 경로-질 자체가 가격 반영 지연 정보"),
    falsification = paste0(
      "성과-독립 F2 재검(가격 리프): RESID top-25 보유종목의 12-1 순수익 중 상위-5 |일간| 기여가 base 대비 ",
      "유의하게 낮아야(t>=2) 경로-질 차별화 실재 — WT-009 원판에서 t+1.05 미지지였던 반증의 잔차판 재판정. ",
      "보조: 월별 CS cor(RESID, D03z) ~ 0 직교성 확인 + placebo(노이즈 잔차화 5시드)가 원판과 유사해야 ",
      "잔차화 연산 자체의 파괴 아님 확인"),
    regime_scope = list(
      holds_in = list("RISK_ON", "NEUTRAL"),
      weakens_or_reverses_in = list("CRISIS"),
      boundary_rationale = paste0(
        "위기 국면 공통 청산 충격은 경로-질 횡단면 차이를 압도(WT-009 실측: CRISIS에서 양 arm active 동반 음수·",
        "paired 판별력 소실). 모멘텀 계열 공통 crash 취약성 상속"))),

  factors = list(
    list(factor_id = "M01_PATHQ_RESID", role = "purified_variant_paired_ab", restatement_exposure = 1,
         ast = list(op = "CS_NEUTRALIZE",
           args = list(
             list(op = "CS_ZSCORE", args = list(list(op = "CS_WINSORIZE", args = list(
               list(leaf = "SPECIAL_OP", field = "signed_path_efficiency_252_21",
                    op_code_path = esc_p2$op_code_path, walk_forward = TRUE,
                    escape_contract = esc_p2), 3), params = list(sd = 3)))),
             list(leaf = "FIELD", source = "factor_db_monthly", field = "D03_RealVol")),
           params = list(method = "monthly_cs_ols_residual", regressors = "D03z_only", min_pairs = 50)))),
  combination_rule = "single_factor",
  verdict = "designed",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "wt009:tuned_panel:M01_PATHQ", availability_rule = "fixed: t-1 가격 창 [n-251,n-21], WT-009 사전등록 검증 승계 (lag1 대칭 감쇠 실측)", restatement_prone = FALSE),
      list(leaf = "factor_db_monthly:D03_RealVol", availability_rule = "fixed: T-1 (Date<=sig_d), load_month_factors 경유 C15 — WT-009 base_panel 승계", restatement_prone = TRUE),
      list(leaf = "A1_rawdata:Ret", availability_rule = "fixed: t-1 종가 확정 (F2 재검·canonical 하네스)", restatement_prone = TRUE)),
    verdict = "clean",
    verdict_rationale = paste0(
      "C1: 잔차화는 월별 CS 연산(당월 신호끼리) — 시계열 참조 없음, 적합 파라미터 0(b_t는 폐형식 월별 추정). ",
      "C2: 동월 신호-신호 회귀는 circular 아님(수익 무참조). C15: D03z는 base_panel(load_month_factors) 승계. ",
      "입력 재계산 0 — WT-009 산출 그대로 소비(승계 mandate). lag1 스트레스 별도 실측.")),

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_013/resid_panel.parquet (+ 승계: WT_D20260802_009/{tuned,base}_panel.parquet)",
  factor_specs = list(list(
    factor_family = "Momentum",
    proxy = "M01_PATHQ_RESID vs M01_Mom_12_1 (paired) — PATHQ의 D03z-잔차 순수판",
    formula = "resid_{i,t} = PATHQ_z - (a_t + b_t*D03z), 월별 CS OLS, D03z 단독, min_pairs 50",
    lag_rule = "price t-1 (경로효율 창 sig_date 이하) + D03z T-1",
    winsorization = "승계 (PATHQ 3std) — 잔차에 추가 winsorize 없음",
    neutralization = "D03_RealVol (월별 CS OLS)",
    economic_rationale = paste0("frog-in-the-pan 경로-질에서 vol-성분을 외과 제거 — 남는 것이 순수 경로 정보인지의 판별. ",
      "실측 판정: ", VERDICT_BINARY),
    weight_theta = NA, source = "db_derived",
    redundancy_cluster_id = "Momentum_cluster",
    references = list("Da-Gurun-Warachka 2014 (RFS)", "Asness et al 2020 (factor purification)"))),

  diagnostics = list(
    canonical_port_t_nw_lag3 = num(R$bt$M01_PATHQ_RESID$portfolio_alpha_t_nw_lag3, 3),
    canonical_port_t_pvalue = num(R$bt$M01_PATHQ_RESID$portfolio_alpha_t_pvalue, 4),
    canonical_n_months = R$bt$M01_PATHQ_RESID$n_months,
    metric_type = "canonical_screen",
    paired_primary = c(paired_l(R$paired_resid),
      list(threshold_preregistered = 2.0, verdict = VERDICT_BINARY)),
    paired_parity_pathq_vs_base = c(paired_l(R$paired_pathq_parity),
      list(wt009_reference = 2.028, note = "재현 parity — WT-009 +2.028과 일치해야 하네스 동질성 성립")),
    paired_resid_vs_pathq = paired_l(R$paired_resid_vs_pathq),
    paired_placebo_5seeds = lapply(R$paired_placebo, paired_l),
    placebo_interpretation = paste0("placebo(노이즈 잔차화)가 원판 +2.03 근방 유지 = 잔차화 연산·교집합 자체는 ",
      "비파괴 — RESID와 placebo의 차이가 곧 D03-성분의 기여"),
    vol_loading = vl,
    vol_beta_b_series_ref = "stage_artifacts/WT_D20260802_013/vol_beta_series.parquet",
    arm_stats = ARM,
    f2_recheck = list(jc_base = num(R$f2$jc_base, 4), jc_resid = num(R$f2$jc_resid, 4),
      t_diff = num(R$f2$t_diff, 2),
      verdict = if (is.finite(R$f2$t_diff) && R$f2$t_diff >= 2.0) "SUPPORTED (잔차판에서 기전 지지로 전환)"
                else "NOT_SUPPORTED (jump-기여 차별화 여전히 미확증)"),
    lag1_stress = list(base_t = num(R$bt$M01_PATHQ_RESID$portfolio_alpha_t_nw_lag3, 3),
                       lag1_t = num(R$lag1_t, 3)),
    ax001_conditional = lapply(R$ax001, function(x) list(
      mdd = num(x$mdd, 4),
      regime = lapply(seq_len(nrow(x$regime)), function(i) list(
        regime = x$regime$Category[i], n = x$regime$n[i],
        mean_active = num(x$regime$mean_active[i], 5), t_nw = num(x$regime$t_nw[i], 2))))),
    advisory = lapply(R$diag, function(d) list(rank_ic = num(d$rank_ic, 5), icir = num(d$icir, 4),
      monotonicity = num(d$monotonicity, 3), ic_pre2015 = num(d$ic_pre2015, 4),
      ic_2015_2019 = num(d$ic_2015_2019, 4), ic_2020p = num(d$ic_2020p, 4))),
    rank_ic = num(R$diag$M01_PATHQ_RESID$rank_ic, 5),
    icir = num(R$diag$M01_PATHQ_RESID$icir, 4),
    harvey_t_stat = num(R$diag$M01_PATHQ_RESID$ic_t, 3),
    monotonicity = num(R$diag$M01_PATHQ_RESID$monotonicity, 3),
    subperiod_stability = NA,
    turnover_proxy = num(R$bt$M01_PATHQ_RESID$turnover_annual, 2),
    post_neutralization_ic = num(R$diag$M01_PATHQ_RESID$rank_ic, 5),
    n_iterations = 1, n_trials = 1, selection_type = "chain",
    deflated_sharpe_ratio = NA,
    dsr_note = "단일 사전등록 가설 1-shot (placebo 5시드 = 통제군, 후보 아님) — DSR 게이트 비발동"),

  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,
  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH",
         flag = paste0("사전등록 label '<2.0 = vol-tilt 아티팩트 확정'의 기전 귀속이 실측과 불일치 — 의사결정(교체 불가)은 ",
           "규칙대로 집행하되, 사전등록 통제가 vol-tilt을 반증(적재 -0.060, self-cor 0.974, RESID vs PATHQ t -0.015). ",
           "실사유 = 취약통계 + pre-2015 편중 (challenge_note C1 PARTIAL)")),
    list(id = "CF-02", severity = "HIGH",
         flag = paste0("WT-009 원판 +2.028은 문턱 근방의 단일 draw — placebo(미소 섭동) paired t 1.87~2.80 (sd 0.378) 산포 실증. ",
           "top-25 멤버십 jitter만으로 판정이 뒤집히는 프레임 — 교체류 판정은 soft-membership paired 분포로 재설계 필요 (C2 ACCEPT)")),
    list(id = "CF-03", severity = "MEDIUM",
         flag = "pre-2015 편중 잔존 (+3.20/-0.33/+0.27, post2017 +0.18) — 잔차화 무관 구조 특성, placebo 5시드 전부 동형. decay-pattern (C3 ACCEPT)"),
    list(id = "CF-04", severity = "MEDIUM",
         flag = "F2 재검 t +1.92 (원판 +1.05) — borderline. jump-기여 차별화가 완전 부재는 아니나 SUPPORTED 선언 불가 — mechanism-direct probe 승계 (C4 PARTIAL)"),
    list(id = "CF-05", severity = "LOW",
         flag = "RESID 회전 793%/yr (base 722 대비 +71%p, 상한 1100% 이내) — 교체 반대 결론으로 소멸되나 기록 (C5)"),
    list(id = "CF-06", severity = "INFO",
         flag = "lag1 +2.14→+1.70 (-21%) — base 계열 -44~-46% 대비 완만, 차등 누출 지문 없음 (C6 REBUTTAL). Spearman 잔여 직교 -0.039 (C7)")),

  verdict_summary = list(
    result = VERDICT_BINARY,
    gate_eligible = FALSE,
    statement = VERDICT_PRIMARY,
    consumption_scan_7 = list(
      factor_ranking = "교체 보류 확정 — M01_Mom_12_1 base 유지. PATHQ/RESID는 문턱-근방 취약 통계 + pre-2015 편중",
      universe_filter = "비적합 (랭킹 변환 계열 — 필터 신호 아님)",
      overlay_regime_input = "비적합 — CRISIS 판별력 소실 (WT-009 실측 승계)",
      risk_model_beta_budget = "비적합 — vol-적재 자체가 -0.06으로 무시 수준 (이식할 vol 성분 없음)",
      monitoring_signal = "placebo-jitter 프레임(멤버십 섭동 paired 분포)은 교체류 판정 일반의 모니터링 규약 후보 — NP-1",
      screening_label = "RESID standalone PORT_t +2.14 = screen-tier 통과권(screen_route 소비 가능)이나 pre-2015 편중으로 자본 트랙 부적격",
      cross_mode_transfer = "jump-share 직접 팩터화(NP-2)는 alpha-search 경량 lane 이식 가능"),
    next_probe = list(
      list(id = "NP-1", priority = "P1",
           probe = paste0("교체류 판정 프레임 강화: top-25 멤버십 섭동(노이즈 잔차화 k시드 또는 top-N sweep 평균) 기반 ",
             "paired 분포의 하한(q05)으로 판정하는 규약 사전등록 — 본 라운드 placebo가 단일-draw 취약성(sd 0.378)을 실증. ",
             "PATHQ 재상정도 이 프레임에서만"),
           rationale = "CF-02 해소 — 문턱 근방 단일 draw로 교체 판정하는 구조 자체가 재현성 결함"),
      list(id = "NP-2", priority = "P2",
           probe = paste0("jump-share 직접 팩터화: 12-1 창 상위-5 |일간| 기여 비중 자체를 명시 신호로 설계(저 jump-share 롱) — ",
             "F2 재검 +1.92 borderline이 남긴 mechanism-direct 각도. PATHQ의 암묵 전달 대신 표적 측정"),
           rationale = "CF-04 승계 — 경로-질 기전의 잔여 검증 경로"),
      list(id = "NP-3", priority = "P3",
           probe = "PATHQ 계열 post-2015 소생 조건 탐색: pre-2015 편중의 기전 분해(개인 수급 구조 변화? 공매도 제도 변천?) — EW-uni post2017 t +1.37~+1.54가 잔존 신호의 존재는 시사",
           rationale = "CF-03의 decay 귀속을 '왜'로 심화 — 부활 조건 정의의 전제"),
      revival_condition = paste0("부활 조건: NP-1 soft-membership 프레임에서 paired 분포 q05 > 0 확립 시 교체안 재상정. ",
        "또는 post-2015 부기간 paired t > 1.5 단독 성립 시 (현 +0.27/-0.33)"))),

  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(name = "M01_PATHQ_RESID_vs_M01_Mom_12_1",
      canonical_port_t = num(R$bt$M01_PATHQ_RESID$portfolio_alpha_t_nw_lag3, 3),
      paired_t = num(pt_primary, 3), selected = TRUE,
      note = "단일 사전등록 판별 가설 — 대안 스펙 탐색 없음 (no-flip, no-sweep)")))))

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_package.json 저장 (paired_t=%+.3f verdict=%s)", pt_primary, VERDICT_BINARY)

val <- list(
  task_id = "WT-D20260802_013",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen",
  gate_eligible = FALSE,
  selection_type = "chain", n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260802_013/preregistration.json (측정 전 고정)",
  discriminating_question = "M01_PATHQ +2.03이 vol-tilt 아티팩트인가 — D03z-잔차 순수판 paired 재측정",
  primary = pkg$diagnostics$paired_primary,
  parity = pkg$diagnostics$paired_parity_pathq_vs_base,
  resid_vs_pathq = pkg$diagnostics$paired_resid_vs_pathq,
  placebo_5seeds = pkg$diagnostics$paired_placebo_5seeds,
  vol_loading = vl,
  f2_recheck = pkg$diagnostics$f2_recheck,
  lag1 = pkg$diagnostics$lag1_stress,
  arm_stats = ARM,
  ax001_conditional = pkg$diagnostics$ax001_conditional,
  advisory = pkg$diagnostics$advisory,
  universe_comparison = list(
    note = "배포 유니버스(K200∪KQ150) 직접 측정 — paired 설계 유니버스 공통(상쇄), v2 확장 비교 비해당",
    dual_basis_by_arm = lapply(ARM, function(a) list(cap_w = a$port_t, ew_uni = a$ew_uni_t,
                                                     ew_post2017 = a$ew_uni_post2017_t)),
    cap_tier_by_arm = lapply(ARM, function(a) list(weight_share = a$cap_tier_weight_share,
                                                   contrib = a$cap_tier_contrib))),
  graduation_hard_gates = list(
    portfolio_alpha_t_nw = list(required = 2.95,
      observed_canonical = num(R$bt$M01_PATHQ_RESID$portfolio_alpha_t_nw_lag3, 3),
      status = if (is.finite(R$bt$M01_PATHQ_RESID$portfolio_alpha_t_nw_lag3) &&
                   R$bt$M01_PATHQ_RESID$portfolio_alpha_t_nw_lag3 >= 2.95) "PASS_SCREEN_ONLY" else "FAIL",
      note = "canonical screening 실측 — forge 미제출(자본 판정 아님). 라운드 목적은 판별"),
    oos_retention = list(required = 0.7,
      observed_approx_ew = num(R$bt$M01_PATHQ_RESID$diag_ew_universe$oos_retention_approx, 4),
      status = "DIAG_ONLY", note = "진단 근사 — 권위는 essence_score"),
    calmar = list(required = 0.64, observed = NA, status = "NOT_COMPUTED", note = "forge 미제출")),
  production_constraints = list(turnover_annual_limit = 11.0,
    observed_by_arm = lapply(ARM, function(a) a$turnover_annual),
    verdict = sprintf("RESID 회전 %.2fx/yr (base 7.22 / PATHQ 7.89) — 상한 11.0 대비 판정 요소 명기",
      as.numeric(ARM$M01_PATHQ_RESID$turnover_annual))),
  sidecar_live_with_ast = R$sidecar)
write_json(val, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_validation.json 저장")

try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_013", package_type = "alpha_package",
    method_selected = "M01_PATHQ_RESID (D03z 월별 CS OLS 잔차 순수판) vs M01_Mom_12_1 사전등록 paired 판별",
    input_file_paths = c(".cache/RAWDATA.parquet",
                         file.path(SRC, "base_panel.parquet"),
                         file.path(SRC, "tuned_panel.parquet"),
                         file.path(OUT, "resid_panel.parquet"),
                         file.path(OUT, "preregistration.json"),
                         ".cache/unified_regime_signal.parquet"))
  say("lineage 기록 완료")
}, silent = FALSE)

st <- list(task_id = "WT-D20260802_013", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), blocker = NULL)
write_json(st, file.path(MB, "status.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
gl <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
gl$events <- c(gl$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_PACKAGE_EMITTED",
  summary = sprintf("M01_PATHQ_RESID 판별 완료 — primary paired t %+.3f (문턱 2.0) → %s. placebo/F2재검/lag1/dual-basis 동봉.",
    pt_primary, VERDICT_BINARY))))
write_json(gl, file.path(MB, "governance_log.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
say("status/governance 갱신 완료")
