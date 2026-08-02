# run_wt014_emit.R — WT-D20260802_014 alpha_package.json + alpha_validation.json 발행
#   순서 의무: alpha_package write → record_package_lineage (L-194)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_014")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_014")
W10 <- file.path(ROOT, "stage_artifacts/WT_D20260802_010")
say <- function(fmt, ...) cat(sprintf(paste0("[wt014e] ", fmt, "\n"), ...))
R <- readRDS(file.path(OUT, "wt014_eval_results.rds"))

# ── alpha_vector: 최신월(2026-06-30 d0) 제외신호 = −z(winsor3(max5)) ─────────
PAN <- as.data.table(read_parquet(file.path(W10, "ot_panel.parquet")))
PAN[, Date := as.Date(Date)]
last_d0 <- max(PAN$Date)
L <- PAN[Date == last_d0 & is.finite(max5), .(Ticker, max5, n_days)]
mu <- mean(L$max5); s <- sd(L$max5)
L[, xw := pmin(pmax(max5, mu - 3 * s), mu + 3 * s)]
L[, score := -(xw - mean(xw)) / sd(xw)]
L[, thr := quantile(max5, 0.90, type = 7, names = FALSE)]
L[, excluded := max5 >= thr]
L[, conf := pmin(1, n_days / 63) * 0.8]     # 데이터 충족도 기반 (단일 신호 — 상한 0.8)
alpha_vec <- setNames(as.list(round(L$score, 5)), L$Ticker)
conf_vec  <- setNames(as.list(round(L$conf, 3)), L$Ticker)
say("alpha_vector: %s 기준 %d종 (배제 플래그 %d종)", as.character(last_d0), nrow(L), L[, sum(excluded)])

esc_max5 <- list(escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT_D20260802_010/ot_w1_lib.R::ot_stock_quantiles (max5 성분)",
  walk_forward = TRUE)
esc_base <- list(escape_type = "STORED_SCORE",
  panel_path = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
  built_at = "2026-07-14", vintage = "factor_db_T-1_off0_clean",
  production_parity_verified = TRUE)

pkg <- list(
  task_id = "WT-D20260802_014",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = "MAX5_63 상위(복권형) 10%를 incumbent 후보 집합에서 배제하면 top-25 선별의 net active 성과가 개선된다 — 랭킹이 아닌 제외-필터 소비면(WT-010 NP-1 승계).",
    mechanism = list(
      agent = "복권선호 개인투자자 — 배제군(고-MAX5) 종목을 홀딩월에 잔여 후보 대비 유의하게 순매수(실측 NW t=+3.90, 본 라운드 반증검정)",
      friction = "KR 공매도 제약 — 복권형 고평가를 즉시 차익거래로 지울 수 없어 overpricing이 홀딩월까지 지속(long-only 시장 구조)",
      path = "신호월 극단 상방수익(MAX5) 종목은 홀딩월 기대수익이 낮다(Bali-Cakici-Whitelaw 2011 MAX effect) — 후보 집합에서 선제 배제하여 저수익 편입을 회피, 랭킹 slot 점유 없이 소비"
    ),
    falsification = "배제군의 홀딩월 개인 순매수(A6_investor_flow 리프, /ADV·일)가 잔여 후보 대비 높지 않으면(NW t<1) 복권수요 기전 기각 — 실측 +0.0077, t=+3.90로 기전 지지",
    regime_scope = list(
      holds_in = list("NEUTRAL", "RISK_ON"),
      weakens_or_reverses_in = list("CRISIS"),
      boundary_rationale = "사전등록 병기 가설(위기월 더 유효)은 반증됨 — 실측 CRISIS Δ −0.33%/월(t −1.78): 위기 중 고-MAX5는 과매도 반등 국면과 겹쳐 배제가 역효과. 편익은 NEUTRAL(t +2.28) 집중 — 복권 수요가 형성·지속되는 평시 국면에서 고평가 해소가 규칙적으로 진행"
    )
  ),
  factors = list(
    list(factor_id = "F1_max5_exclusion",
      ast = list(op = "WHERE",
        args = list(
          list(op = "LT",
            args = list(
              list(op = "CS_RANK_PCT",
                args = list(list(leaf = "SPECIAL_OP",
                  field = "max5_63d (63거래일 창 상위 5일 저장 Ret 평균 — WT-010 ot_panel 동결분 소비)",
                  op_code_path = esc_max5$op_code_path, walk_forward = TRUE,
                  escape_contract = esc_max5))),
              0.90)),
          list(leaf = "STORED_SCORE",
            field = "score_eff (STR_1715 cleanT1 — incumbent 선별 점수, 필터의 소비 기질)",
            escape_contract = esc_base))),
      role = "exclusion_filter",
      restatement_exposure = 0,
      restatement_note = "가격(저장 Ret) 리프 + production parity 저장점수 — 재무 재작성 비대상. Ret 재계산 없음(rawdata Ret 방화벽)."
    )
  ),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "SPECIAL_OP:max5_63", availability_rule = "fixed: 저장 일간 Ret t-1까지 — 창 종점 d0(전월말), 홀딩 시작 전 1거래일 간격 (C5)", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE:score_eff", availability_rule = "manual_export: cleanT1 production_parity_verified (§7b 라벨 게이트 stopifnot 통과) — vintage factor_db_T-1_off0_clean", restatement_prone = FALSE),
      list(leaf = "A6_investor_flow(반증검정 전용)", availability_rule = "t-1 settlement — 홀딩월 실현분을 반증검정에만 사용(신호 미사용)", restatement_prone = FALSE)
    ),
    verdict = "clean"
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_014/alpha_scores.parquet (Date,Ticker,max5,excluded — 제외-필터 신호 패널)",
  factor_specs = list(list(
    factor_family = "Lottery/MAX",
    proxy = "MAX5_63 상위 10% 횡단면 제외-필터",
    formula = "excluded_i,t = 1{ max5_i,t >= Q90_t(max5) } — 후보 집합(liq 통과) 내 당월 분위",
    lag_rule = "price t-1 (창 종점 = 전월말 d0)",
    winsorization = "필터는 분위 컷 — winsor 불요 (alpha_vector 표현만 3std)",
    neutralization = "없음 (사전등록 단일 primary — 중립화 변형 미시험)",
    economic_rationale = "behavioral: 복권수요 overpricing (Bali-Cakici-Whitelaw 2011) x KR 공매도 제약 — 본 라운드 반증검정에서 배제군 홀딩월 개인 순매수 t=+3.90 실측으로 기전 지지",
    weight_theta = 1.0,
    references = list("Bali, Cakici, Whitelaw 2011 JFE (Maxing Out)", "WT-D20260802_010 scalar_moment_controls 실측")
  )),
  diagnostics = list(
    canonical_port_t_nw_lag3 = round(R$ew$filtered$portfolio_alpha_t_nw_lag3, 3),
    canonical_port_t_note = "필터 적용판 EW top-25 canonical_screen_bt 실측(metric_type=canonical_screen). 무필터 base EW = 3.396 — 본 WT의 발견은 수준이 아니라 Δ(base 알파는 incumbent 소유).",
    canonical_port_t_pvalue = round(R$ew$filtered$portfolio_alpha_t_pvalue, 5),
    canonical_n_months = R$ew$filtered$n_months,
    delta_ir_screen_basis = round(R$paired$delta_ir, 4),
    delta_ir_basis_label = "weighted_screen(cap_norm(Size) top-25, net 15bps) — §4 admission net_active_recon_v1 아님. 특성화 수치.",
    paired_t_nw_lag3 = round(R$paired$paired_t_nw_lag3, 3),
    rank_ic = 0.04736,
    rank_ic_note = "WT-010 승계 advisory (MAX5_63 랭킹 IC, t 4.41) — 본 라운드는 랭킹 미소비",
    icir = NA,
    monotonicity = NA,
    subperiod_stability = "paired Δ: pre2015 +1.59 / 2015-19 −1.13 / 2020+ +1.70 (이질 — challenge_note C4)",
    turnover_proxy = round(R$filtered$turnover_annual, 2),
    harvey_t_stat = NA,
    post_neutralization_ic = NA
  ),
  selection_objective = "canonical_port_t",
  alpha_discovery_count = 1,
  challenge_flags = list(
    "paired t 1.565 — ΔIR 점추정은 사전등록 기준 3.4배이나 통계 확증 보통 (challenge_note C1)",
    "lag1 붕괴 = fast-decay 신호 — 리밸 1개월 지연 시 편익 소멸, 동월 누출은 구조 부재로 반박 (C2)",
    "CRISIS 역효과 t −1.78 — 사전등록 병기 가설 반증, regime_scope 실측 반영 (C3)",
    "2015-19 부기간 음수 (C4)",
    "screen-IR basis — book recon NAV IR 아님, 자본 주장 없음 (C5)",
    "overlay(R05) 미반영 bare 선별 계층 측정 (C6)"
  ),
  verdict_summary = "특성화 positive: 사전등록 ΔIR +0.1692(기준 +0.05) 충족 + 발동 실효 95.7%(base top-25 내 월평균 3.34종 실제 배제) + liq 긴장 0월 + abs MDD 11.4pp 개선 + 기전 반증검정 지지(t +3.90). 제한: paired t 1.57 보통 유의 + 국면·부기간 이질. 자본 주장 없음 — admission은 governor+도훈 수동.",
  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(name = "MAX5_63_top10pct_exclusion", delta_ir = round(R$paired$delta_ir, 4), selected = TRUE)),
    note = "사전등록 단일 primary — X∈{5,20}%는 진단 병기(선택 미사용), lag1은 스트레스"
  ))
)
write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
say("alpha_package.json 발행 (%s)", file.path(MB, "alpha_package.json"))

# lineage (write 후 — L-194 순서)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_014",
  package_type = "alpha_package",
  method_selected = "MAX5_63 top-10% exclusion filter on production-parity base (preregistered single primary)",
  input_file_paths = c(
    file.path(W10, "ot_panel.parquet"),
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
    "stage_artifacts/WT_D20260714_004/screen_inputs.rds"
  )
)
say("lineage 기록 완료")

# ── alpha_validation.json ────────────────────────────────────────────────────
val <- list(
  task_id = "WT-D20260802_014",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "weighted_screen + canonical_screen (라벨 병기)",
  gate_eligible = FALSE,
  selection_type = "preregistered_single_primary",
  n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260802_014/preregistration.json (측정 전 고정)",
  base_anchor = list(target = 3.0583, observed = round(R$base_full$portfolio_alpha_t_nw_lag3, 4),
                     status = "PASS — parity 하네스 재현 정확 (268m)"),
  primary = list(
    name = "MAX5_63_top10pct_exclusion",
    delta_ir = round(R$paired$delta_ir, 4),
    delta_ir_threshold = 0.05,
    delta_ir_basis = "weighted_screen cap_norm(Size) top-25 net 15bps — net_active_recon_v1(book recon NAV) 아님",
    paired_t_nw_lag3 = round(R$paired$paired_t_nw_lag3, 3),
    mean_delta_active_monthly = round(R$paired$mean_d_active, 5),
    n_months = R$paired$n_months,
    base = list(port_t = round(R$base$portfolio_alpha_t_nw_lag3, 3), ir = round(R$base$information_ratio, 4),
                abs_mdd = round(R$post_diag$abs$base$abs_mdd, 4), turnover_annual = round(R$base$turnover_annual, 2)),
    filtered = list(port_t = round(R$filtered$portfolio_alpha_t_nw_lag3, 3), ir = round(R$filtered$information_ratio, 4),
                    abs_mdd = round(R$post_diag$abs$filtered$abs_mdd, 4), turnover_annual = round(R$filtered$turnover_annual, 2))
  ),
  effectiveness = list(
    fire_share = round(R$effectiveness$fire_share, 4),
    mean_swap_names = round(R$effectiveness$mean_swap, 2),
    mean_cut_in_base_top25 = round(R$effectiveness$mean_cut_in_base_top25, 2),
    max_cut = R$effectiveness$max_cut,
    coverage_max5 = "후보 집합 내 99.9%",
    verdict = "발동 실효 — honest null(incumbent가 이미 복권형 회피) 기각: base top-25에 월평균 3.34종 복권형 실재"
  ),
  liq_tension = list(months_under_25 = nrow(R$liq_short_months), verdict = "긴장 없음 — 배제 후 전월 후보 ≥25종"),
  regime_conditional = lapply(seq_len(nrow(R$regime_tab)), function(i) as.list(R$regime_tab[i, .(Category, n, mean_d, t_nw)])),
  ax001_conditional = list(
    crisis_delta_monthly = R$regime_tab[Category == "CRISIS", mean_d],
    crisis_t = R$regime_tab[Category == "CRISIS", t_nw],
    verdict = "사전등록 병기 가설(위기월 더 유효) 반증 — CRISIS Δ 음수(t −1.78), 편익 NEUTRAL 집중(t +2.28). AX-001 조건부 병기 의무 이행."
  ),
  lag1_stress = list(delta_ir = round(R$lag1$delta_ir, 4), paired_t = round(R$lag1$paired_t, 3),
    verdict = "1개월 지연 시 편익 소멸 — fast-decay 신호(문헌 정합). 동월 누출은 창 하드슬라이스로 구조 부재(challenge_note C2 REBUTTAL). 운용 함의: 리밸 지연 불허."),
  x_sensitivity_diagnostic_only = R$xdiag,
  dual_basis = list(
    ew_top25 = list(base_port_t = round(R$ew$base$portfolio_alpha_t_nw_lag3, 3),
                    filtered_port_t = round(R$ew$filtered$portfolio_alpha_t_nw_lag3, 3),
                    delta_ir = round(R$ew$filtered$information_ratio - R$ew$base$information_ratio, 4)),
    ew_universe_diag = list(base_t = round(R$ew$base$diag_ew_universe$portfolio_alpha_t_nw_lag3, 2),
                            filtered_t = round(R$ew$filtered$diag_ew_universe$portfolio_alpha_t_nw_lag3, 2)),
    verdict = "cap-w·EW 양 basis 동방향(+0.169 / +0.093) — basis 아티팩트 아님"
  ),
  falsification = list(
    field = "A6_investor_flow (Individual, 홀딩월)",
    excluded_minus_rest_spread = round(R$falsification$mean_spread, 6),
    t_nw = round(R$falsification$t_nw, 2),
    n_months = R$falsification$n_months,
    verdict = "MECHANISM_SUPPORTED — 배제군을 개인이 홀딩월에 유의하게 더 순매수(t +3.90): 복권수요 실재"
  ),
  subperiod_paired = R$post_diag$subperiod_paired,
  graduation_hard_gates = list(
    note = "본 라운드 = 소비면 특성화 — forge 미제출, graduation 판정 비대상. 필터 적용판의 canonical PORT_t 3.866/weighted 3.620은 base 알파(incumbent 소유) 포함 수준값 — 필터 자체의 기여는 Δ로만 평가",
    capital_claim = "없음 (admission = governor + 도훈 수동)"
  )
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
say("alpha_validation.json 발행 완료")
