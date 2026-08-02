# =============================================================================
# run_wt007_emit.R — WT-D20260802_007 alpha_package.json + alpha_validation.json + lineage
#   순서 의무(L-194): alpha_package.json write → record_package_lineage
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_007/run_wt007_emit.R", encoding="UTF-8")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_007")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_007")
say <- function(fmt, ...) cat(sprintf(paste0("[wt007m] ", fmt, "\n"), ...))
`%||%` <- function(a, b) if (is.null(a)) b else a

R <- readRDS(file.path(OUT, "wt007_eval_results.rds"))
SC <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
PRIM <- "INS_MAGQ3"
btp <- R$bt[[PRIM]]
rnd <- function(x, k = 4) if (is.null(x) || !is.finite(x)) NULL else round(x, k)

## ── alpha/confidence vector (최신 신호월) ────────────────────────────────────
last_d <- max(SC$Date)
av <- SC[Date == last_d][order(-score)]
alpha_vec <- as.list(setNames(round(av$score, 6), av$Ticker))
conf_vec  <- as.list(setNames(rep(1, nrow(av)), av$Ticker))

## ── dual basis / cap tier ────────────────────────────────────────────────────
ew <- btp$diag_ew_universe
ct <- btp$diag_cap_tier
dual_basis <- list(
  cap_w_port_t = rnd(btp$portfolio_alpha_t_nw_lag3, 3),
  ew_universe_port_t = rnd(ew$portfolio_alpha_t_nw_lag3, 3),
  ew_universe_post2017_t = rnd(ew$post2017_t_nw_lag3, 3),
  ew_universe_oos_retention_approx = rnd(ew$oos_retention_approx, 4),
  cap_tier_weight_share = lapply(ct$weight_share_avg, rnd, k = 4),
  cap_tier_contrib_annualized = lapply(ct$contrib_gross_annualized, rnd, k = 4),
  verdict = paste0(
    "v8.3 기각-전 확인 의무 이행: cap-w +1.37 / EW-uni -0.79 — EW 기준으로 더 약함(벤치 아티팩트 구제 없음, ",
    "insider 신호는 EW 유니버스 대비 초과 아님 = 소형주 광역 프리미엄에 흡수). cap-tier: OTHER 55.6% + UNRANKED 22.4%",
    "(초기 연도 Size 결측) + MID 13.6% > MEGA 8.4% — mid/small 국소(R33 tier 구조 재현), cap-w 트랩 아님(EW도 약함).")
)

## ── 대조축 요약 ──────────────────────────────────────────────────────────────
axis_row <- function(tag) {
  b <- R$bt[[tag]]; e <- b$diag_ew_universe
  list(port_t = rnd(b$portfolio_alpha_t_nw_lag3, 3), net_sr = rnd(b$net_sr, 3),
       turnover_annual = rnd(b$turnover_annual, 2), n_months = b$n_months,
       ew_uni_t = rnd(e$portfolio_alpha_t_nw_lag3 %||% NA_real_, 3),
       ew_uni_post2017_t = rnd(e$post2017_t_nw_lag3 %||% NA_real_, 3))
}
contrasts <- lapply(setNames(nm = c("INS_MAG_NOFILT3", "INS01_BASE3", "INS_SEQ12",
                                    "INS_EVT3", "INS02_BREADTH6")), axis_row)

dg <- R$diag[[PRIM]]
pkg <- list(
  task_id = "WT-D20260802_007",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = paste0(
      "insider '참여의 질' 3축: R9가 죽인 것은 '참여 여부'(건수/금액 집계) — 참여의 질(크기/순서/맥락) 축은 그 벽을 비껴간다는 가설. ",
      "primary = FQ-078 magnitude 정규화(보유지분 대비 commitment ratio cr, symbolic 하위 tercile 제거, trailing 3m signed-cr 합). ",
      "사전등록 단일 primary — stage_artifacts/WT_D20260802_007/preregistration.json (측정 전 고정, no-flip, 3축 argmax 봉쇄)."),
    mechanism = list(
      agent = "상장사 임원 (자기 금융재산의 유의미한 몫을 자사주에 거는 내부정보 보유 주체) — vs symbolic 매수자(주가 방어 시그널링·의례적 소액 매수 임원)",
      friction = "KR 공매도 제약 + 시장이 insider 공시를 '건수·금액'으로만 소비(보유대비 커밋 비중 재랭킹의 정보처리 비용) + symbolic 매수가 단순 집계 신호를 희석",
      path = "대형-커밋 매수 공시(T+0) → 1~3개월 기관·외국인 후속 매수로 가격 반영 (flow 링크가 직접 관측 경로)"),
    falsification = paste0(
      "A6_investor_flow(investor_wide Foreign+Institutional): primary Q5 종목의 후속 홀딩월 순매수/ADV·일이 Q1 대비 NW t<1이면 '정보성 축적' 기전 기각. ",
      "실측 t=+1.41 (211개월) — 기각선(t<1)은 넘었으나 지지선(t>=2) 미달 = 기전 미확립(WT-006 매집 시그니처 t=+4.08과 대조적). 성과 동어반복 아님."),
    regime_scope = list(
      holds_in = list("RISK_ON"),
      weakens_or_reverses_in = list("CRISIS", "NEUTRAL"),
      boundary_rationale = paste0(
        "사전등록: 위기 = 강제청산 공통충격 + 저가 방어 symbolic 매수 급증이 신호 오염. 실측: RISK_ON t=+2.42 지지 / CRISIS t=-0.10 약화 지지 / ",
        "NEUTRAL t=-0.12 (역전 아닌 무신호 — 사전등록 holds_in의 neutral 포함은 과대선언이었음을 정직 반영해 갱신)."))
  ),
  factors = list(list(
    factor_id = "INS_MAGQ3",
    ast = list(op = "CS_ZSCORE", args = list(list(
      op = "CS_WINSORIZE",
      args = list(list(
        leaf = "SPECIAL_OP",
        field = "insider_commitment_magq3 (D1_dart_insider_hist_events 파생)",
        op_code_path = "stage_artifacts/WT_D20260802_007/run_wt007_panel.R::build_axes",
        walk_forward = TRUE,
        escape_contract = list(
          escape_type = "SPECIAL_OP",
          op_code_path = "stage_artifacts/WT_D20260802_007/run_wt007_panel.R::build_axes",
          walk_forward = TRUE)), 3),
      params = list(sd = 3)))),
    role = "core_signal",
    restatement_exposure = 0,
    restatement_note = "DART 임원 지분변동 신고 — 재무 재작성 비대상. 정정공시는 별도 rcept append(원 행 불변, field map D1 규약)."
  )),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "D1_dart_insider_hist_events:qty_change/qty_before/qty_after/price/rcept_dt",
           availability_rule = "regulatory: rcept 당일 T+0 공개 — 신호월 = 접수월, forward = m+1월(C5). truncation-invariance 3표본월 PASS",
           restatement_prone = FALSE),
      list(leaf = "disc_ck (부정 이벤트, FQ-080 대조축만)",
           availability_rule = "regulatory: rcept T+0. ★348 corp 생존 tilt(C6) — diagnostic-grade 라벨",
           restatement_prone = FALSE)),
    verdict = "clean",
    verdict_rationale = paste0(
      "C1: trailing 창(3m/36m rolling tercile) 결정론 — full-sample 통계 없음, truncation-invariance @201105/201710/202404 PASS. ",
      "C5: 신호월=rcept월, forward=m+1월. C6: primary/SEQ는 전 유니버스 크롤(341종) — 생존 tilt 없음. EVT 대조축만 C6 caveat. ",
      "lag1 +1.37→+0.78 완만 감쇠 — 동월 누출 지문 없음(rcept월 규약 구조상 clean).")
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_007/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "Insider_NonReturn",
    proxy = "Commitment_ratio_magnitude_3m",
    formula = paste0("cr = min(1,|dQ|/max(Q_before,Q_after)); b_m = rolling-36m 하위 1/3 분위(월 m까지); ",
                     "score = sum_{3m, cr>=b_m} sign(dQ)*cr; CS winsorize 3sd -> z"),
    lag_rule = "rcept 접수월 = 신호월 (T+0 공개), forward return m+1월",
    winsorization = "3std",
    neutralization = "none",
    economic_rationale = paste0(
      "자기 보유의 큰 몫을 거는 임원 매수만 정보를 담는다(Wang-Yang-Sun 2026 symbolic 분리). 실측: cr-정규화는 notional baseline 대비 ",
      "paired +21.1bps/m(t=+1.84, NOFILT arm) 개선 — 단 symbolic tercile cut 자체는 no-op(rank-cor 0.998, paired t=-1.45)이고 ",
      "flow 링크 미확립(t=+1.41)로 기전의 '정보성' 서사는 미입증."),
    weight_theta = 1,
    redundancy_cluster_id = "insider_family_r9_r42",
    source = "new_designed",
    references = list(
      "Wang-Yang-Sun 2026 (IREF 108:105190, symbolic insider purchases)",
      "Cohen-Malloy-Pomorski 2012 (routine vs opportunistic)",
      "preregistration.json 2026-08-02"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = rnd(btp$portfolio_alpha_t_nw_lag3, 3),
    canonical_port_t_pvalue = rnd(btp$portfolio_alpha_t_pvalue, 4),
    canonical_n_months = btp$n_months,
    metric_type = "canonical_screen",
    rank_ic = rnd(dg$rank_ic, 4),
    icir = rnd(dg$icir, 4),
    harvey_t_stat = rnd(dg$ic_t, 3),
    monotonicity = rnd(dg$monotonicity, 3),
    subperiod_stability = list(ic_pre2015 = rnd(dg$ic_pre2015, 4),
                               ic_2015_2019 = rnd(dg$ic_2015_2019, 4),
                               ic_2020p = rnd(dg$ic_2020p, 4)),
    subperiod_port_t = lapply(R$sub_port_t, rnd, k = 3),
    turnover_proxy = rnd(btp$turnover_annual, 2),
    post_neutralization_ic = NULL,
    information_ratio = rnd(btp$information_ratio, 4),
    net_sr = rnd(btp$net_sr, 4),
    dual_basis = dual_basis,
    contrast_axes = contrasts,
    paired_tests = lapply(R$paired, function(p)
      list(n = p$n, mean_diff_bps_m = rnd(p$mean_diff_bps_m, 2), t_nw = rnd(p$t_nw, 3))),
    rank_cor_axes = lapply(R$rank_cor, function(p)
      list(mean = rnd(p$mean, 3), sd = rnd(p$sd, 3), n_months = p$n_months)),
    orthogonality = lapply(R$orth, function(o)
      list(rho_mean = rnd(o$mean, 3), rho_sd = rnd(o$sd, 3))),
    placebo_shuffle = lapply(R$placebo, function(p)
      list(port_t = rnd(p$port_t, 3), rank_ic = rnd(p$rank_ic, 5))),
    placebo_note = paste0(
      "cr 월내 무작위 재배정 5시드(크기 정보 파괴, 참여/방향 구조 보존): PORT_t [+0.45,+1.33] vs primary +1.37 — ",
      "primary가 5/5 시드 상회하나 여유 얇음(최대 시드 +1.33). magnitude 고유 증분은 실재하되 얇다 — ",
      "개선의 상당분은 signed-cr 함수형(placebo 평균 +0.88 > base +0.55)에서 온다."),
    lag1_stress = list(base_port_t = rnd(btp$portfolio_alpha_t_nw_lag3, 3),
                       lag1_port_t = rnd(R$bt_lag1$portfolio_alpha_t_nw_lag3, 3),
                       verdict = "완만 감쇠(+1.37→+0.78) — 동월 누출 지문 아님(rcept월 규약 + truncation PASS)"),
    falsification_test = list(
      field = "A6_investor_flow (Foreign+Institutional / ADV·일)",
      primary = list(q5_q1_spread_mean = rnd(R$falsification$primary$mean_spread, 5),
                     t_nw = rnd(R$falsification$primary$t_nw, 3),
                     n_months = R$falsification$primary$n_months),
      seq12 = list(t_nw = rnd(R$falsification$seq12$t_nw, 3)),
      base3 = list(t_nw = rnd(R$falsification$base3$t_nw, 3)),
      verdict = "MECHANISM_NOT_ESTABLISHED — t=+1.41 (기각선 1 초과, 지지선 2 미달). insider 매수는 WT-006 매집 시그니처(t=+4.08)와 달리 후속 기관 flow를 예측하지 못함"),
    regime_conditional = lapply(seq_len(nrow(R$regime_tab)), function(i)
      list(regime = R$regime_tab$Category[i], n = R$regime_tab$n[i],
           mean_active = rnd(R$regime_tab$mean_active[i], 5), t_nw = rnd(R$regime_tab$t_nw[i], 3))),
    label_direction_cor = rnd(R$label_direction_ic, 4),
    pit_truncation_invariance = R$pit_truncation,
    ast_sidecar_live_with_ast = R$sidecar,
    n_iterations = 1,
    selection_type = "preregistered_single_primary",
    deflated_sharpe_ratio = NULL,
    dsr_note = paste0(
      "사전등록 단일 primary(n_trials=1) — 3축 동시후보 argmax 구조를 사전 봉쇄(sweep 아님, DSR 게이트 비발동). ",
      "실측에서 대조축 NOFILT(+1.59)가 primary(+1.37)보다 높았으나 no-flip/no-argmax 조항대로 선택하지 않음 — ",
      "프로토콜 준수의 실증. n_contrasts=5 사후감사 기록.")
  ),
  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,
  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH",
         flag = "canonical PORT_t +1.37 (p=0.171) — HARD 2.95 미달. 자본-tier 승격 불가"),
    list(id = "CF-02", severity = "HIGH",
         flag = "dual-basis 양쪽 미달: EW-uni t=-0.79 (cap-w보다 약함) — 벤치 아티팩트 구제 없음. insider 신호는 EW 유니버스 광역 소형주 프리미엄을 못 이김"),
    list(id = "CF-03", severity = "HIGH",
         flag = "FQ-079 시퀀스 = R33 breadth 재탕 실측(rank-cor +0.805±0.044 ≥ 사전등록 기각선 0.7) — 별도 축 주장 기각. gap-가중(FQ-079 전반부)만 미실측 frontier"),
    list(id = "CF-04", severity = "MEDIUM",
         flag = "symbolic tercile cut = no-op(prim vs NOFILT rank-cor 0.998, paired t=-1.45 소폭 역효과) — 논문의 symbolic 제거 기전은 KR config에서 부가가치 없음. 개선 원천 = cr-정규화 함수형"),
    list(id = "CF-05", severity = "MEDIUM",
         flag = "flow 링크 미확립(t=+1.41 < 2) — '정보성 축적의 공시 지문' 서사 미입증. placebo 여유 얇음(최대 시드 +1.33 vs +1.37)"),
    list(id = "CF-06", severity = "MEDIUM",
         flag = "FQ-080 이벤트-조건부: 월 중앙값 2명 커버리지 — portfolio-tier 측정 불성립(PORT_t +0.96은 n=189 희소월 diagnostic). 이벤트 census 자체는 확보(크롤 0, 668건) + 348corp 생존 tilt C6"),
    list(id = "CF-07", severity = "LOW",
         flag = "paired 개선 방향성 실재: base(R9 재현) +0.55 → NOFILT +1.59 / primary +1.37 (+16~21bps/m, t 1.44~1.84) — 유의 미달이나 '참여의 질' 축이 벽을 구부린 실측. turnover 741% < 1100% 제약 내"),
    list(id = "CF-08", severity = "INFO",
         flag = "PIT truncation-invariance 3/3 PASS + 라벨 방향 감사 +0.0107 + 직교성 기존 5팩터 |rho|<=0.21. ast_sidecar live_with_ast 18->19")
  ),
  verdict_summary = list(
    result = "config_scoped_negative_capital_tier__quality_axis_bends_not_breaks_r9_wall",
    gate_eligible = FALSE,
    statement = paste0(
      "본 config(top-25 cap-w EW long-only, 15bps, 월간, K200∪KQ150)에서 insider '참여의 질' 축은 자본-tier 알파가 아니다",
      "(primary +1.37 < 2.95, EW-uni -0.79, flow 링크 t=+1.41 미확립). 판정 본체에 대한 정직 답: '참여의 질'은 R9의 '참여 여부' 벽을 ",
      "비껴가지 못했고 구부리는 데 그쳤다 — cr-정규화가 notional 집계 대비 +21bps/m(t=+1.84)을 더하지만 유의 미달이고, ",
      "symbolic 제거는 no-op이며, 시퀀스 축은 R33 재탕(0.805)이고, 이벤트 축은 커버리지가 portfolio-tier에 못 미친다. ",
      "현 config 수렴 + 부활 조건: ① gap-가중(FQ-079 미실측 절반) 사전등록 라운드 ② cr-가중 신호의 monitoring 소비면(R34~R42 배선) 유효 실측 ③ 이벤트 census 전 상폐 확장."),
    consumption_scan_7 = list(
      factor_ranking = "미달 (현 config)",
      universe_filter = "후보 약함 — insider commitment 하위 필터는 EW-uni 음수라 필터 가치 불확실",
      overlay_regime_input = "비적합 — RISK_ON 국소(t+2.42)이나 regime 교차결합은 settled-negative 계열(INV-7)",
      risk_model_beta_budget = "비적합",
      monitoring_signal = "1순위 소비 — R34~R42 SAFE tripwire에 cr-가중 commitment 보조축 추가(INS02 breadth 문턱과의 증분은 rank-cor 0.71이라 존재) — NP-1",
      screening_label = "insider 계열 스코어링의 표준을 notional 집계→cr-정규화로 교체 권고(비용 0, 전 계열 +16~21bps/m 방향성)",
      cross_mode_transfer = "RAMP Insider family(INS01~03) 빌더에 cr-정규화 변형 추가 후보 — capital 주장 없이 패널 확장만"),
    next_probe = list(
      list(id = "NP-1", priority = "P1",
           probe = "monitoring 소비면: R34~R42 SAFE 상태기계에 INS_MAGQ3 z>=+1 보조 tripwire 사전등록 후 R38-스타일 월별-paired(SUSTAIN vs OFF) 실측 — 자본 아닌 per-holding 안전 특성화 축",
           rationale = "capital 미달 신호의 1순위 소비 경로(WT mandate). breadth와 rank-cor 0.71 = 증분 정보 존재"),
      list(id = "NP-2", priority = "P2",
           probe = "FQ-079 미실측 절반 = 공시지연 gap 가중(거래일→공시일 gap 역수) — 시퀀스와 달리 R33과 무관한 순수 타이밍 축. 사전등록 별도 라운드",
           rationale = "본 라운드가 재탕으로 판정한 것은 run-length 시퀀스뿐 — gap 축은 미측정 frontier(FRL 2026 논문 근거)"),
      list(id = "NP-3", priority = "P2",
           probe = "cr-정규화 함수형 분해: participation-count arm vs signed-cr arm vs notional arm 3-way paired — placebo(+0.88 평균)가 시사한 '함수형 vs 크기정보' 기여 분리",
           rationale = "개선 원천의 기전 미귀속 — 크기 정보가 아니라 log1p(notional)의 왜곡 제거일 가능성"),
      list(id = "NP-4", priority = "P3",
           probe = "FQ-080 이벤트 census 확장: 전 상폐 포함 census(생존 tilt 해소) + 창 [0,+120d] + 이벤트-풀 전용 소형 유니버스 측정 — portfolio-tier 불가는 이미 실측이므로 monitoring/선별 라벨 면 한정",
           rationale = "668건/348corp 커버리지가 바인딩 제약 — 신호 부재와 커버리지 부족의 분리 필요"))
  ),
  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(
      name = "INS_MAGQ3", canonical_port_t = rnd(btp$portfolio_alpha_t_nw_lag3, 3),
      selected = TRUE,
      note = "사전등록 단일 primary. 대조 5종(NOFILT/BASE/SEQ/EVT/BREADTH)은 축-구분·분해 관측 — 선택 비사용(NOFILT +1.59 > primary였으나 no-argmax 준수)"))))
)

write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, null = "null")
say("alpha_package.json 저장 (%d bytes)", file.size(file.path(MB, "alpha_package.json")))

## ── alpha_validation.json (stage_artifacts) ──────────────────────────────────
val <- list(
  task_id = "WT-D20260802_007",
  validated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  preregistration = "stage_artifacts/WT_D20260802_007/preregistration.json (측정 전 고정)",
  metric_type = "canonical_screen",
  harness = "canonical_screen_bt top-25 EW long-only, 15bps one-way, liq 2e8, K200∪KQ150 월말 멤버십, build_monthly_forward_returns",
  primary = list(factor_id = PRIM, canonical_port_t_nw_lag3 = rnd(btp$portfolio_alpha_t_nw_lag3, 3),
                 pvalue = rnd(btp$portfolio_alpha_t_pvalue, 4), n_months = btp$n_months,
                 net_sr = rnd(btp$net_sr, 4), turnover_annual = rnd(btp$turnover_annual, 3),
                 subperiod_port_t = lapply(R$sub_port_t, rnd, k = 3)),
  dual_basis = dual_basis,
  contrast_axes = contrasts,
  paired_tests = lapply(R$paired, function(p) list(n = p$n, mean_diff_bps_m = rnd(p$mean_diff_bps_m, 2), t_nw = rnd(p$t_nw, 3))),
  axis_identity = list(
    fq079_vs_r33_rank_cor = list(mean = rnd(R$rank_cor$seq_vs_breadth$mean, 3),
                                 sd = rnd(R$rank_cor$seq_vs_breadth$sd, 3),
                                 prereg_kill_line = 0.7,
                                 verdict = "DUPLICATE_AXIS — FQ-079 시퀀스는 R33 breadth와 동일 정보축(재탕). 사전등록 의무 조항에 따라 자체 기각"),
    full_matrix = lapply(R$rank_cor, function(p) list(mean = rnd(p$mean, 3), sd = rnd(p$sd, 3)))),
  adversarial = list(
    lag1 = list(base = rnd(btp$portfolio_alpha_t_nw_lag3, 3), lag1 = rnd(R$bt_lag1$portfolio_alpha_t_nw_lag3, 3)),
    placebo_cr_shuffle_5seed = lapply(R$placebo, function(p) list(port_t = rnd(p$port_t, 3), rank_ic = rnd(p$rank_ic, 5))),
    pit_truncation_invariance = R$pit_truncation,
    label_direction_audit = rnd(R$label_direction_ic, 4)),
  falsification_flow_link = list(
    primary_t = rnd(R$falsification$primary$t_nw, 3),
    verdict = "MECHANISM_NOT_ESTABLISHED (t=+1.41: 기각선 1 초과, 지지선 2 미달)"),
  universe_comparison = list(
    note = "v2 universe 비교 비발동 — primary ICIR 0.29 > 0.15 (L-227 trigger 미충족). dual-basis EW-uni 진단이 유니버스 한계 축을 대체 커버"),
  known_traps_audit = list(
    corp_code_is_stock_code = "반영 (universe_corpcodes.csv stock_code 조인, 매칭 100%)",
    encoding_utf8 = "반영 (전 스크립트 encoding='UTF-8' 소스)",
    stale_parquet_avoided = "insider_trades_clean.parquet 미사용 — D1 체크포인트 직접",
    d3_panel_7b = "outputs/ramp/insider_factor_scores.parquet 미소비 — INS01/INS02 재현도 D1 원천에서 자체 재계산"),
  verdict = "config_scoped_negative_capital_tier__quality_axis_bends_not_breaks_r9_wall"
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, null = "null")
say("alpha_validation.json 저장")

## ── lineage (alpha_package 이후 — L-194 순서) ────────────────────────────────
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_007",
  package_type = "alpha_package",
  method_selected = "INS_MAGQ3 (사전등록 단일 primary — insider commitment-ratio magnitude, symbolic tercile cut)",
  input_file_paths = c(
    ".cache/dart/insider_backfill/202606.csv",
    ".cache/dart/universe_corpcodes.csv",
    ".cache/RAWDATA.parquet",
    ".cache/investor_stock/investor_wide.parquet",
    "stage_artifacts/WT_D20260802_007/insider_axes_panel.parquet",
    "stage_artifacts/WT_D20260802_007/neg_events.parquet",
    "stage_artifacts/WT_D20260802_007/preregistration.json"))
say("lineage 기록 완료")
say("DONE")
