# =============================================================================
# run_wt016_emit.R — WT-D20260802_016 alpha_package.json + alpha_validation.json 발행
#   순서 의무: alpha_package write → record_package_lineage (L-194)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_016/run_wt016_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_016")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_016")
W10 <- file.path(ROOT, "stage_artifacts/WT_D20260802_010")
W14 <- file.path(ROOT, "stage_artifacts/WT_D20260802_014")
say <- function(fmt, ...) cat(sprintf(paste0("[wt016e] ", fmt, "\n"), ...))
R <- readRDS(file.path(OUT, "wt016_eval_results.rds"))

# ── alpha_scores.parquet: WT-014 제외신호 패널 승계 + 월별 exposure 병기 ─────
EX <- as.data.table(read_parquet(file.path(W14, "alpha_scores.parquet")))
EX[, Date := as.Date(Date)]
ym_add <- function(ym, k) { y <- as.integer(substr(ym,1,4)); m <- as.integer(substr(ym,6,7))+k
  y <- y+(m-1L)%/%12L; m <- (m-1L)%%12L+1L; sprintf("%04d-%02d", y, m) }
L5 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
L5[, exposure := as.numeric(m4_weight_lag)*as.numeric(beta_threshold_lag)*as.numeric(beta_R05_V5)]
EX[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
EX <- merge(EX, L5[, .(hold_ym = return_ym, exposure)], by = "hold_ym", all.x = TRUE)[, hold_ym := NULL]
write_parquet(EX, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet: %d행 (제외신호 + book exposure 병기)", nrow(EX))

# ── alpha_vector: WT-014 승계 (동일 신호 — 본 라운드는 소비면 측정, 신규 발굴 0) ──
pkg14 <- fromJSON(file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_014/alpha_package.json"),
                  simplifyVector = FALSE)

esc_max5 <- list(escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT_D20260802_010/ot_w1_lib.R::ot_stock_quantiles (max5 성분)",
  walk_forward = TRUE)
prov_base <- list(store_build_hash = "sha256:56914c56b2b3b879",
  generator_code_path = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code (cleanT1 재빌드, production_code_direct parity spearman 0.975~0.997)",
  generated_at = "2026-07-14", production_parity_verified = TRUE)
esc_base <- list(escape_type = "STORED_SCORE",
  panel_path = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
  built_at = "2026-07-14", vintage = "factor_db_T-1_off0_clean",
  production_parity_verified = TRUE, provenance = prov_base[1:3])
prov_expo <- list(store_build_hash = "sha256:98fa32778613ffe6",
  generator_code_path = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code/run_layer5_R05_overlay.R",
  generated_at = "production PG2 admit 산출 (read-only 소비)", production_parity_verified = TRUE)
esc_expo <- list(escape_type = "STORED_SCORE",
  panel_path = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
  built_at = "production PG2 산출물 (read-only)", vintage = "book 실현 β_combined = m4_weight_lag x beta_threshold_lag x beta_R05_V5",
  production_parity_verified = TRUE,
  parity_evidence = "행-수준 cor(e, ret_L5_V5/ret_orig)=0.9996, max|diff|=0.035(스위칭 비용 항, resid-db cor -0.81) + β-스캔 k=0 정렬 확정",
  provenance = prov_expo[1:3])

pkg <- list(
  task_id = "WT-D20260802_016",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = "2026-06-30", decision_ts = "2026-08-02",
    note = "sig_date = alpha_vector 기준 d0 (ot_panel 최신월말). 측정 패널은 2004-12~2026-04 전기간 저장분 소비"),
  hypothesis = list(
    statement = "WT-014 확립 MAX5_63 상위 10% 제외-필터의 한계기여가 현 book overlay(M4xR05_V5 β_combined)를 얹은 상태에서도 유지된다 — 실배치 판정 관문 (FQ-111).",
    mechanism = list(
      agent = "복권선호 개인투자자 — 배제군(고-MAX5)을 홀딩월에 잔여 후보 대비 유의 순매수 (WT-014 실측 NW t=+3.90 승계)",
      friction = "KR 공매도 제약 — 복권형 overpricing 즉시 차익거래 불가. overlay는 종목축이 아닌 월별 노출 스칼라(e_t)라 필터의 종목 선택 기여를 지우지 못하고 e_t 재가중만 가함 (d_ov,t = e_t x d_bare,t 항등)",
      path = "고-MAX5 배제 → 홀딩월 저수익 편입 회피(월평균 3.3종 실교체). overlay-ON에서는 CRISIS 저노출(e̅ 0.38)이 필터의 위기월 역효과 크기를 축소하는 경로가 추가"
    ),
    falsification = list(list(
      field = "A6_investor_flow_stock_daily",
      observation = "배제군의 홀딩월 개인 순매수(/ADV·일)가 잔여 후보 대비 높지 않으면(NW t<1) 복권수요 기전 기각 — WT-014 실측 t=+3.90 승계(기전 지지)")),
    falsification_note_round_specific = "overlay가 필터 기여를 지운다면 상호작용(d_ov−d_bare)이 유의 음수여야 — 실측 t=-1.14 (미유의, 기각 안 됨). 성과-부수 관측이라 falsification 사전이 아닌 진단 병기로 분류",
    regime_scope = list(
      holds_in = list("NEUTRAL", "RISK_ON"),
      weakens_or_reverses_in = list("CRISIS"),
      boundary_rationale = "overlay-ON에서도 국면 구조 보존: NEUTRAL Δ +0.42%/월(t +1.89) 편익 집중, CRISIS Δ 음수 유지(-0.13%/월, t -1.59) — 단 overlay 저노출이 CRISIS 역효과 크기를 61% 흡수(-0.33 → -0.13%/월). 부호는 흡수 안 됨(β 축소는 크기 축소만 가능)"
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
                  field = "max5_63d (WT-010 ot_panel 동결분 소비 — 재계산 없음)",
                  op_code_path = esc_max5$op_code_path, walk_forward = TRUE,
                  escape_contract = esc_max5))),
              0.90)),
          list(leaf = "STORED_SCORE",
            field = "score_eff (STR_1715 cleanT1 — incumbent 선별 점수, 필터의 소비 기질)",
            escape_contract = esc_base))),
      role = "exclusion_filter",
      restatement_exposure = 0,
      restatement_note = "가격(저장 Ret) + production parity 저장점수 — 재무 재작성 비대상."
    ),
    list(factor_id = "F2_book_overlay_exposure_context",
      ast = list(op = "MUL",
        args = list(
          list(leaf = "STORED_SCORE", field = "exposure = m4_weight_lag x beta_threshold_lag x beta_R05_V5 (return_ym 조인)",
               escape_contract = esc_expo),
          "port_ret_net")),
      role = "evaluation_context",
      restatement_exposure = 0,
      restatement_note = "알파 신호 아님 — 측정 맥락(현 book 실현 노출). 양팔 동일 적용이라 paired 추론에 자체 알파 기여 없음."
    )
  ),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "SPECIAL_OP:max5_63", availability_rule = "fixed: 저장 일간 Ret, 창 종점 d0(전월말) — 홀딩 시작 전 1거래일 간격 (C5, WT-014 승계)", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE:score_eff", availability_rule = "manual_export: cleanT1 production_parity_verified (§7b stopifnot 통과)", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE:exposure_layer5", availability_rule = "regulatory 아님 — production shift 구조: β_R05 t-1 EOM 결정 → t월 적용, m4/threshold shift(1). 신호컷 = 홀딩월 M-1월말 < M 시작. assert_overlay_pit HARD PASS + 위반 주입(M월말 컷) stop() 발화 실증", restatement_prone = FALSE)
    ),
    verdict = "clean"
  ),
  alpha_vector = pkg14$alpha_vector,
  confidence_vector = pkg14$confidence_vector,
  alpha_vector_note = "WT-014 승계 (동일 신호, 최신월 제외신호 -z(winsor3(max5))). 본 라운드 신규 발굴 없음 — alpha_inheritance = WT-014 cor 1.0",
  alpha_discovery_count = 0,
  discovery_of = "WT-D20260802_014",
  signal_matrix_ref = "stage_artifacts/WT_D20260802_016/alpha_scores.parquet (Date,Ticker,max5,excluded,exposure)",
  factor_specs = pkg14$factor_specs,
  diagnostics = list(
    canonical_port_t_nw_lag3 = round(R$ew_ov$filt$portfolio_alpha_t_nw_lag3, 3),
    canonical_port_t_note = "EW top-25 overlay-ON 필터판 (weighted_screen w=1/25 + exposure, metric_type=weighted_screen). 무필터 overlay-ON EW = 2.188. 본 WT의 발견은 수준이 아니라 Δ (base 알파+overlay는 incumbent 소유)",
    canonical_port_t_pvalue = round(R$ew_ov$filt$portfolio_alpha_t_pvalue, 5),
    canonical_n_months = R$ew_ov$filt$n_months,
    primary_delta_ir_overlay_on = round(R$primary$delta_ir_ov, 4),
    primary_paired_t_overlay_on = round(R$primary$paired_t_ov, 3),
    delta_ir_basis_label = "weighted_screen(cap_norm(Size) top-25, net 15bps) x book exposure — §4 admission net_active_recon_v1 아님",
    bare_reference = list(delta_ir = round(R$bare_ref$delta_ir, 4), paired_t = round(R$bare_ref$paired_t, 3)),
    interaction_t = round(R$interaction$t, 3),
    rank_ic = 0.04736,
    rank_ic_note = "WT-010 승계 advisory — 본 라운드 랭킹 미소비",
    icir = NA,
    monotonicity = NA,
    subperiod_stability = "국면 분해로 대체 (regime_conditional 참조) — overlay-ON에서도 NEUTRAL 집중·CRISIS 음수 구조 보존",
    turnover_proxy = round(R$cells$filt_ov$turnover_annual, 2),
    harvey_t_stat = NA,
    post_neutralization_ic = NA
  ),
  selection_objective = "canonical_port_t",
  challenge_flags = list(
    "overlay parity 사전등록 STOP 발동(cor 0.668<0.95) — 진단 확정: 배선 정확(β-스캔 k=0 + 행-수준 e cor 0.9996), 미달 원인 = 기준의 보조가정 오류(book ret_orig=AR 전략 계층 vs base=parity 스크린 계층, 계층 정체성 가정) (challenge_note C1)",
    "primary paired t 1.551 — WT-014 bare 1.565와 사실상 동일, 통계 확증 보통 (C2)",
    "상호작용 t -1.14: overlay가 필터 ΔIR을 -24% 축소(0.169→0.128) — 미유의이나 점추정은 부분 중복 방향 (C3)",
    "CRISIS 역효과 부호 잔존(t -1.59) — overlay는 크기만 61% 흡수, 국면조건부 해제는 사후선택이라 미채택 (C4)",
    "lag1 시 편익 소멸(overlay-ON 동일) — fast-decay, 리밸 지연 불허 (C5)",
    "종목계층 회전 13.5x/yr — incumbent base 속성(필터는 -0.27 감소), overlay β-schedule 회전은 book 계층 별도 (C6)"
  ),
  verdict_summary = "실배치 관문 통과: overlay-ON paired t +1.551 (닫힘 기준 t<1 비발동) + ΔIR +0.1284 (기준 +0.05 충족, bare 대비 76% 보존). CRISIS 역효과는 overlay가 크기 61% 흡수(-0.33→-0.13%/월), 부호는 유지. MDD 축은 부분 독립: overlay 단독 15.6pp + 필터 추가 7.3pp(bare 11.4pp 대비 64% 잔존) = 중복 아님. 자본 주장 없음 — 실배치 여부는 governor + 도훈 수동.",
  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(name = "MAX5_X10_exclusion_x_book_overlay_V5",
                           delta_ir = round(R$primary$delta_ir_ov, 4), selected = TRUE)),
    note = "사전등록 단일 primary — exposure 타이밍 변형(leak/lag1)·EW·2x2 셀은 전부 진단 병기, 선택 미사용"
  ))
)
write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
say("alpha_package.json 발행")

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_016",
  package_type = "alpha_package",
  method_selected = "MAX5_63 top-10% exclusion filter x book overlay(M4xR05_V5) paired A/B (preregistered single primary)",
  input_file_paths = c(
    file.path(W10, "ot_panel.parquet"),
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
    "stage_artifacts/WT_D20260714_004/screen_inputs.rds"
  )
)
say("lineage 기록 완료")

# ── alpha_validation.json ────────────────────────────────────────────────────
rt <- R$regime_tab
val <- list(
  task_id = "WT-D20260802_016",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "weighted_screen (cap_norm top-25 + book exposure_dt) — 라벨 병기",
  gate_eligible = FALSE,
  selection_type = "preregistered_single_primary",
  n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260802_016/preregistration.json (측정 전 고정)",
  base_anchor = list(target = 3.0583, observed = round(R$anchor$observed, 4),
                     status = "PASS — WT-014/parity 하네스 재현 정확 (268m)"),
  primary = list(
    name = "MAX5_X10_exclusion_under_book_overlay_V5",
    close_rule = "overlay-ON paired t < 1 → 이 base 소비면 ② 닫힘 (사전등록)",
    paired_t_nw_lag3_overlay_on = round(R$primary$paired_t_ov, 3),
    close_rule_fired = FALSE,
    delta_ir_overlay_on = round(R$primary$delta_ir_ov, 4),
    delta_ir_threshold = 0.05,
    delta_ir_basis = "weighted_screen cap_norm(Size) top-25 net 15bps x book 실현 β_combined — net_active_recon_v1 아님",
    mean_delta_active_monthly = round(R$primary$mean_d_ov, 5),
    n_months = R$primary$n_months
  ),
  cells_2x2 = list(
    base_bare = list(port_t = round(R$cells$base_bare$portfolio_alpha_t_nw_lag3, 3), ir = round(R$cells$base_bare$information_ratio, 4),
                     abs_sr = round(R$cells$base_bare$abs_net_sr, 3), abs_cagr = round(R$cells$base_bare$abs_cagr, 4),
                     abs_mdd = round(R$cells$base_bare$abs_mdd, 4), turnover_annual = round(R$cells$base_bare$turnover_annual, 2)),
    filt_bare = list(port_t = round(R$cells$filt_bare$portfolio_alpha_t_nw_lag3, 3), ir = round(R$cells$filt_bare$information_ratio, 4),
                     abs_sr = round(R$cells$filt_bare$abs_net_sr, 3), abs_cagr = round(R$cells$filt_bare$abs_cagr, 4),
                     abs_mdd = round(R$cells$filt_bare$abs_mdd, 4), turnover_annual = round(R$cells$filt_bare$turnover_annual, 2)),
    base_overlay = list(port_t = round(R$cells$base_ov$portfolio_alpha_t_nw_lag3, 3), ir = round(R$cells$base_ov$information_ratio, 4),
                        abs_sr = round(R$cells$base_ov$abs_net_sr, 3), abs_cagr = round(R$cells$base_ov$abs_cagr, 4),
                        abs_mdd = round(R$cells$base_ov$abs_mdd, 4)),
    filt_overlay = list(port_t = round(R$cells$filt_ov$portfolio_alpha_t_nw_lag3, 3), ir = round(R$cells$filt_ov$information_ratio, 4),
                        abs_sr = round(R$cells$filt_ov$abs_net_sr, 3), abs_cagr = round(R$cells$filt_ov$abs_cagr, 4),
                        abs_mdd = round(R$cells$filt_ov$abs_mdd, 4)),
    bare_reference = list(delta_ir = round(R$bare_ref$delta_ir, 4), paired_t = round(R$bare_ref$paired_t, 3),
                          note = "WT-014 재현 정확 (ΔIR +0.1692 / t +1.565)"),
    interaction = list(paired_t = round(R$interaction$t, 3), mean_monthly = round(R$interaction$mean, 5),
                       verdict = "overlay는 필터 기여를 유의하게 지우지 못함(t -1.14) — 점추정 축소 -24%는 e̅ 0.79 재가중의 산술 결과"),
    mdd_overlap = list(overlay_alone_pp = 15.6, filter_alone_pp = 11.4, filter_on_top_of_overlay_pp = 7.3,
                       verdict = "부분 중복(필터 MDD 편익 36% 흡수) — 잔여 7.3pp 독립 기여. 축이 다름(종목선택 vs 노출조절) 가설이 우세")
  ),
  regime_conditional = lapply(seq_len(nrow(rt)), function(i) as.list(rt[i])),
  ax001_conditional = list(
    crisis_delta_monthly_bare = rt[Category == "CRISIS", mean_d_bare],
    crisis_delta_monthly_overlay = rt[Category == "CRISIS", mean_d_ov],
    crisis_t_bare = rt[Category == "CRISIS", t_bare],
    crisis_t_overlay = rt[Category == "CRISIS", t_ov],
    crisis_mean_exposure = rt[Category == "CRISIS", mean_e],
    verdict = "판별 질문(CRISIS 역효과가 β 축소와 상쇄되는가) 답: 크기는 61% 흡수(-0.33 → -0.13%/월, e̅ 0.38), 부호·t는 잔존(-1.78 → -1.59). 편익 NEUTRAL 집중 구조 보존(t +2.28 → +1.89). AX-001 조건부 병기 이행."
  ),
  lag1_stress = list(delta_ir = round(R$lag1_filter_ov$delta_ir, 4), paired_t = round(R$lag1_filter_ov$paired_t, 3),
    verdict = "overlay-ON에서도 1개월 지연 시 편익 소멸(ΔIR -0.024, t -0.44) — WT-014 bare와 동일 fast-decay. 리밸 지연 불허."),
  exposure_timing_diagnostics = list(
    strict_current = list(delta_ir = round(R$primary$delta_ir_ov, 4), paired_t = round(R$primary$paired_t_ov, 3),
                          base_abs_sr = round(R$cells$base_ov$abs_net_sr, 4)),
    leak_M_end = list(delta_ir = round(R$expo_variants$leak_Mend$delta_ir, 4), paired_t = round(R$expo_variants$leak_Mend$paired_t, 3),
                      base_abs_sr = round(R$expo_variants$leak_Mend$base_abs_sr, 4)),
    expo_lag1 = list(delta_ir = round(R$expo_variants$expo_lag1$delta_ir, 4), paired_t = round(R$expo_variants$expo_lag1$paired_t, 3),
                     base_abs_sr = round(R$expo_variants$expo_lag1$base_abs_sr, 4)),
    lookahead_ab = list(inflation = round(R$leak_ab$inflation, 4), suspected = R$leak_ab$lookahead_suspected,
      verdict = "leak(동월누출 방향) 변형이 strict보다 오히려 나쁨(absSR 0.795 vs 0.874, 인플레 -9.0%) — 현 타이밍에 look-ahead 이득 부재. paired Δ는 타이밍 변형에 강건(0.121~0.128)")
  ),
  dual_basis = list(
    ew_top25_overlay_on = list(base_port_t = round(R$ew_ov$base$portfolio_alpha_t_nw_lag3, 3),
                               filt_port_t = round(R$ew_ov$filt$portfolio_alpha_t_nw_lag3, 3),
                               delta_ir = round(R$ew_ov$delta_ir, 4), paired_t = round(R$ew_ov$paired_t, 3)),
    cap_tier = list(source = "WT-014 canonical diag 승계 (exposure는 월별 스칼라 — 횡단면 tier 귀속 불변, 구조 명기)",
                    base_contrib_ann = list(MEGA = 0.0185, MID = 0.0196, OTHER = 0.202),
                    filt_contrib_ann = list(MEGA = 0.0194, MID = 0.025, OTHER = 0.207),
                    note = "필터 증분은 MID(+0.54%p)·OTHER(+0.5%p) 발원, MEGA 미미 아님-표기: +0.09%p (소폭)"),
    verdict = "cap-w ΔIR +0.128 / EW +0.064 동방향 — basis 아티팩트 아님 (EW는 약함, cap_norm 판이 primary)"
  ),
  overlay_parity_diagnosis = list(
    prereg_stop_fired = TRUE,
    portfolio_level_cor = 0.6684,
    diagnosis = list(
      alignment = "β-스캔: return_ym+k 조인 k=0에서만 cor 0.71(타 offset ≤0.10, realized_ym 조인 0.06) — 월 정렬 정확",
      exposure_wiring = "행-수준 cor(e, ret_L5_V5/ret_orig)=0.9996, max|diff|=0.035, 잔차는 overlay 스위칭 비용 항(resid-db cor -0.81) — exposure 배선 정확",
      root_cause = "기준의 보조가정 오류: book ret_orig = AR 전략 계층(월평균 +1.81%p 고수익) vs 내 base = WT-014 parity 스크린 계층. 계층이 다른 두 시계열의 identity를 요구한 기준 설계 오류 — 배선 결함 아님",
      disposition = "사전등록 규정(STOP 후 배선 진단 보고) 이행 — 진단 2축으로 배선 무결 확정 후 측정 유효 판정. challenge_note C1 기록"
    )
  ),
  exposure_coverage = list(n_months = 256, n_na = 0, months_e_lt_1 = 149, share_e_lt_1 = 0.582, mean_exposure = 0.7918),
  pit_verification = list(
    assert_overlay_pit = "PASS — 신호컷(M-1월말) < 홀딩월 시작, 256/256행",
    violation_injection = "FIRED — 컷오프를 M월말로 주입 시 stop() 발화 확인 (가드 생존 실증)",
    strict_pit_ab = "leak 변형 열세(-9.0%) — look-ahead 인플레 부재",
    c5_filter = "max5 창 종점 d0(전월말), 간격 1거래일 — WT-014 판정 승계"
  ),
  graduation_hard_gates = list(
    note = "본 라운드 = 실배치 관문 특성화 — forge 미제출, graduation 판정 비대상. 수준값(filt/overlay PORT_t 2.458 등)은 incumbent 알파+overlay 포함 수치 — 필터 기여는 Δ로만 평가",
    capital_claim = "없음 (실배치/admission = governor + 도훈 수동)"
  )
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)
say("alpha_validation.json 발행")

# ── status.json + governance_log ─────────────────────────────────────────────
st <- list(task_id = "WT-D20260802_016", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), blocker = NULL)
write_json(st, file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
gl <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
gl$events[[length(gl$events) + 1]] <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_DONE",
  summary = "overlay-ON paired t +1.551 (닫힘 기준 t<1 비발동) / ΔIR +0.1284 (기준 충족). CRISIS 역효과 크기 61% 흡수·부호 잔존. 사전등록 parity STOP 1회 발동→배선 진단 2축으로 무결 확정. 신규 발굴 0 (WT-014 승계, alpha_discovery_count=0 정직 표기) — certificate 비대상 소비면 특성화."
)
gl$events[[length(gl$events) + 1]] <- list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "reclassify_note",
  summary = "wt_type=discovery이나 alpha 신호는 WT-014 상속(cor 1.0) — 본질은 소비면 측정 라운드. role card 기준 hyperparameter/sizing 아님(신호 소비 방식 검증). alpha_discovery_certificate 미발급이 정상 산출."
)
write_json(gl, file.path(MB, "governance_log.json"), pretty = TRUE, auto_unbox = TRUE)
say("status ALPHA_DONE + governance_log 2건 기록")
