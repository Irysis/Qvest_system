# =============================================================================
# run_wt010_emit.R — WT-D20260802_010 AST v1.1 3층 alpha_package + validation + lineage
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_010/run_wt010_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_010")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_010")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[emit] ", fmt, "\n"), ...))

R   <- readRDS(file.path(OUT, "wt010_eval_results.rds"))
VER <- fromJSON(file.path(OUT, "verify_results.json"), simplifyVector = FALSE)
PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
b   <- R$bt$OT_W1_RTAIL_63
ew  <- b$diag_ew_universe
ct  <- b$diag_cap_tier
dg  <- R$diag$OT_W1_RTAIL_63
PAN <- as.data.table(read_parquet(file.path(OUT, "ot_panel.parquet")))
PAN[, Date := as.Date(Date)]

# ── alpha_vector / confidence_vector (최종 sig_date 횡단면) ──────────────────
SC <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
SC[, Date := as.Date(Date)]
last_d <- SC[, max(Date)]
LV <- SC[Date == last_d][order(-score)]
alpha_vector <- as.list(setNames(round(LV$score, 6), LV$Ticker))
cov_m <- SC[, .N, by = Ticker][, setNames(pmin(1, N / 120), Ticker)]
nd <- PAN[Date == last_d, setNames(pmin(1, n_days / 63), Ticker)]
conf <- vapply(LV$Ticker, function(tk)
  round(max(0, min(1, 0.5 * as.numeric(cov_m[[tk]] %||% 0.5) +
                       0.5 * as.numeric(nd[[tk]] %||% 0.5))), 4), numeric(1))
confidence_vector <- as.list(setNames(conf, LV$Ticker))

esc <- list(escape_type = "SPECIAL_OP",
            op_code_path = "stage_artifacts/WT_D20260802_010/ot_w1_lib.R::ot_stock_quantiles+ot_cs_decompose",
            walk_forward = TRUE)
ast_primary <- list(op = "CS_ZSCORE", args = list(list(op = "CS_WINSORIZE", args = list(
  list(leaf = "SPECIAL_OP",
       field = "ot_w1_rtail_63d (score = -RTAIL; robust-normalized quantile deviation from CS barycenter, right band u>0.8)",
       op_code_path = esc$op_code_path, walk_forward = TRUE,
       escape_contract = esc),
  3), params = list(sd = 3))))

num <- function(x, d = 4) if (is.null(x) || !is.finite(x)) NA else round(as.numeric(x), d)
plc <- lapply(R$placebo, function(p) list(port_t = num(p$port_t, 3), rank_ic = num(p$rank_ic, 5)))
orth <- lapply(R$orth, function(o) list(rho_mean = num(o$mean, 3), rho_sd = num(o$sd, 3)))
decomp <- lapply(R$bt[setdiff(names(R$bt), "OT_W1_RTAIL_63")], function(r)
  list(port_t = num(r$portfolio_alpha_t_nw_lag3, 3),
       ew_uni_t = num(r$diag_ew_universe$portfolio_alpha_t_nw_lag3, 3),
       net_sr = num(r$net_sr, 3), turnover_annual = num(r$turnover_annual, 2)))
scalar_ic <- lapply(R$diag[c("SKEW63", "KURT63", "MAX5_63")], function(d)
  list(rank_ic = num(d$rank_ic, 5), ic_t = num(d$ic_t, 3)))
reg_l <- lapply(seq_len(nrow(R$regime_tab)), function(i)
  list(regime = R$regime_tab$Category[i], n = R$regime_tab$n[i],
       mean_active = num(R$regime_tab$mean_active[i], 5), t_nw = num(R$regime_tab$t_nw[i], 2)))

pkg <- list(
  task_id = "WT-D20260802_010",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",

  hypothesis = list(
    statement = paste0(
      "종목-월 일간수익 경험분포를 robust 정규화(median/MAD) 후 횡단면 Wasserstein barycenter",
      "(1D 분위평균 닫힌형)와 비교 — 우미부 대역(u>0.8) 부호 있는 편차 RTAIL이 복권형/점프형 형상을 ",
      "포착하고 score=-RTAIL 상위(형상-온건) 종목이 익월 초과수익. 사전등록 단일 primary — ",
      "stage_artifacts/WT_D20260802_010/preregistration.json (측정 전 고정, no-flip + 자기기각 규칙 포함)."),
    mechanism = PRE$mechanism,
    falsification = paste0(
      "A6_investor_flow_stock_daily(investor_wide Individual): score 최하위 quintile(우미부-비대=복권형) ",
      "종목의 신호 창 내 개인 순매수/ADV·일이 최상위 quintile 대비 유의(NW t>=2) 높지 않으면 ",
      "'개인 복권수요 추격' 기전 기각. 실측: t=-7.27 부호 역전 — 기전 기각 확정 (개인은 오히려 순매도)."),
    regime_scope = list(
      holds_in = list(),
      weakens_or_reverses_in = list("RISK_ON", "NEUTRAL", "CAUTION", "CRISIS"),
      boundary_rationale = paste0(
        "사전등록 holds_in=[NEUTRAL,CRISIS] (복권 되돌림=투기수요 후퇴기) — 실측 반증: 전 국면 active 비양",
        "(RISK_ON -0.21 / NEUTRAL -1.53 / CAUTION -0.19 / CRISIS -0.85). 국면 경계 도출 실패를 정직 갱신. ",
        "단 IC는 위기에서 강화(bad/normal 2.91) — 신호는 위기-강화형이나 top-25 롱 전이가 전 국면 부재."))),

  factors = list(list(
    factor_id = "OT_W1_RTAIL_63",
    ast = ast_primary,
    role = "core_signal",
    restatement_exposure = 0,
    restatement_note = "가격(저장 Ret) 리프 단일 — 재무 재작성 비대상. Ret 재계산 없음(저장값 소비, rawdata Ret 방화벽)."
  )),
  combination_rule = "single_factor",
  verdict = "designed",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "A2_price_volume_daily:Ret",
           availability_rule = "fixed: t 종가 수익률 — 신호 창 = Date <= sig_date 하드 슬라이스 (C1 rolling). 저장 Ret 소비(재계산 금지)",
           restatement_prone = FALSE)),
    verdict = "clean",
    verdict_rationale = paste0(
      "C1: trailing 63일 창 + 당월 횡단면 barycenter의 결정론 함수(적합 파라미터 0, full-sample 통계 없음 — ",
      "barycenter는 같은 sig_date 횡단면만 사용). C2/C3: 신호(t 이하)와 라벨(t->t+1 forward, 하네스 표준) 분리 — ",
      sprintf("M01 라벨 방향 감사 %+.4f. C10: 유동성필터 하네스 표준 adv(t-1). ", R$label_direction_ic),
      "lag1(-1.24 -> -0.70): base 자체가 placebo 대역 내라 누출 판별 무의미 — 누출 기전 구조 부재(창 하드 슬라이스).")),

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_010/alpha_scores.parquet",

  factor_specs = list(list(
    factor_family = "Distribution_Shape_OT",
    proxy = "W1_barycenter_rtail_63d",
    formula = paste0("score = -RTAIL; RTAIL = mean_{u>0.8}[q_i(u) - qbar(u)], q_i = robust 정규화",
                     "((r-median)/MAD) 일간수익 분위(K=31 midpoint), qbar = 당월 횡단면 분위평균",
                     "(1D W2 barycenter 닫힌형). CS winsorize 3sd -> CS z"),
    lag_rule = "저장 Ret t 이하 (창 = sig_date 이하 63거래일), forward return t->t+1 월말",
    winsorization = "3std",
    neutralization = "none (robust 정규화가 location/scale 채널을 구성적으로 정확 소거 — 검증 T5)",
    economic_rationale = paste0(
      "복권수요 가설(Bali-Cakici-Whitlock MAX / Kumar / Barberis-Huang): 자기 일상변동 대비 우미부가 ",
      "횡단면 전형 형상보다 두꺼운(점프형) 종목은 개인 추격으로 과대가격 -> 익월 되돌림. ",
      "실측 반증: 신호창 개인 순매수 스프레드 t=-7.27 부호 역전 — 개인은 점프형 종목을 오히려 순매도",
      "(차익실현/역추세 — KR 개인 역추세 성향 문헌 정합). 기전 기각, 통계 패턴(IC +0.019)만 잔존."),
    weight_theta = 1.0,
    redundancy_cluster_id = "distribution_shape_ot_new__partial_overlap_moment_scalars",
    source = "new_designed",
    references = list(
      "Agueh-Carlier 2011 (Wasserstein barycenter)", "Villani 2003 (Optimal Transport)",
      "Bali-Cakici-Whitlock 2011 (MAX effect)", "Kumar 2009 (lottery stocks)",
      "preregistration.json 2026-08-02"))),

  diagnostics = list(
    canonical_port_t_nw_lag3 = num(b$portfolio_alpha_t_nw_lag3, 3),
    canonical_port_t_pvalue = num(b$portfolio_alpha_t_pvalue, 4),
    canonical_n_months = b$n_months,
    metric_type = "canonical_screen",
    rank_ic = num(dg$rank_ic, 5),
    icir = num(dg$icir, 4),
    harvey_t_stat = num(dg$ic_t, 3),
    monotonicity = num(dg$monotonicity, 3),
    subperiod_stability = list(ic_pre2015 = num(dg$ic_pre2015, 4),
                               ic_2015_2019 = num(dg$ic_2015_2019, 4),
                               ic_2020p = num(dg$ic_2020p, 4)),
    subperiod_port_t = lapply(R$sub_port_t, num, d = 3),
    turnover_proxy = num(b$turnover_annual, 2),
    post_neutralization_ic = NA,
    information_ratio = num(b$information_ratio, 4),
    net_sr = num(b$net_sr, 4),
    alpha_annualized = num(b$alpha_annualized, 4),
    dual_basis = list(
      cap_w_port_t = num(b$portfolio_alpha_t_nw_lag3, 3),
      ew_universe_port_t = num(ew$portfolio_alpha_t_nw_lag3, 3),
      ew_universe_post2017_t = num(ew$post2017_t_nw_lag3, 3),
      cap_tier_weight_share = ct$weight_share_avg,
      cap_tier_contrib_annualized = ct$contrib_gross_annualized,
      verdict = paste0(
        "v8.3 기각-전 확인 의무 이행: EW-uni t=-2.05가 cap-w(-1.24)보다 더 나쁨 — 벤치 아티팩트로 ",
        "구제되지 않음(양 basis 기각, EW가 더 부정적). cap-tier: OTHER 85.7% / MID 9.2% / MEGA 5.1% — ",
        "국소화 특이 없음. cap-w 트랩 비해당.")),
    decomposition = decomp,
    decomposition_note = paste0(
      "방향 분해 성분별 canonical: LTAIL -1.47 / SHAPE(총거리) -0.97 / RAW(비정규화) -0.40 / ",
      "MEANC(위치) +0.49 / SCALEC(스케일) -1.28 — 전 성분 게이트 미달. 어느 방향 분해도 canonical ",
      "전이에 실패. RAW의 IC(+0.0190)가 primary(+0.0187)와 동급 = 정규화가 IC 원천이 아님도 실측."),
    scalar_moment_controls = list(
      canonical = list(SKEW63 = decomp$SKEW63, KURT63 = decomp$KURT63, MAX5_63 = decomp$MAX5_63),
      rank_ic = scalar_ic,
      verdict = paste0(
        "재탕 판별 본체 실측: 동일창 스칼라 대조군 IC가 primary보다 강함 — MAX5 +0.0474(t 4.41) / ",
        "SKEW +0.0222(t 4.15) / KURT +0.0203(t 3.94) vs primary +0.0187(t 3.57). ",
        "W1 형상 성분은 스칼라 모멘트와 부분중복(rho 0.34~0.44, 자기기각 문턱 0.5 미만)이나 ",
        "독립 성분이 예측력을 추가하지 않음 — '분포-거리 > 스칼라 모멘트' 차별 주장 실측 미성립.")),
    orthogonality = orth,
    orthogonality_note = paste0(
      "admitted 축 |rho| <= 0.17 (M01 -0.014 / D03 +0.130 / D41 +0.168 / D45 +0.078 / D55 +0.169 / ",
      "D01 +0.154) — robust 정규화의 location/scale 구성적 소거가 실측으로도 성립(설계 목표 달성). ",
      "자기기각 규칙(사전등록): SKEW63 +0.435 / KURT63 +0.343 / MAX5 +0.396 — 0.5 미만이므로 ",
      "'스칼라 재조합' 자동기각은 비발동, 단 0.3~0.5 부분중복 밴드 = 차별 주장 약화 라벨 의무 발동."),
    placebo_gaussian = plc,
    placebo_note = paste0(
      "Gaussian 치환 placebo(형상 채널만 파괴, affine 불변으로 위치·스케일은 구성적 무관) 5시드: ",
      "PORT_t [-1.52, -0.25] / rank_IC [-0.0034, +0.0063]. primary PORT_t -1.24는 placebo 대역 내부 = ",
      "canonical 수준 형상 정보량 0. 단 primary rank_IC +0.0187(t 3.57)은 placebo IC 대역 밖 = ",
      "횡단면 회피-신호는 실재(우미부-비대 종목의 저성과) — advisory 계열."),
    lag1_stress = list(base_port_t = num(b$portfolio_alpha_t_nw_lag3, 3),
                       lag1_port_t = num(R$bt_lag1$portfolio_alpha_t_nw_lag3, 3),
                       verdict = "base 자체가 placebo 대역 내 — 누출 판별 비적용(창 하드 슬라이스로 누출 기전 구조 부재)"),
    falsification_test = list(
      field = "A6_investor_flow_stock_daily (Individual)",
      q1_q5_spread_mean = num(R$falsification$mean_spread, 6),
      t_nw = num(R$falsification$t_nw, 3),
      n_months = R$falsification$n_months,
      verdict = paste0("MECHANISM_REFUTED — 부호 역전(t=-7.27): 개인은 우미부-비대(점프형) 종목을 ",
                       "신호창에 강하게 순매도(추격이 아니라 차익실현). 사전등록 기각 기준(t<1) 초과 달성.")),
    regime_conditional = reg_l,
    ax001_conditional = list(
      crisis_alpha_monthly = num(R$ax001$crisis_alpha, 5),
      ic_bad = num(R$ax001$ic_bad, 4), ic_normal = num(R$ax001$ic_norm, 4),
      ic_ratio_bad_normal = num(R$ax001$ic_bad / R$ax001$ic_norm, 3),
      verdict = paste0("IC는 위기 강화(ratio 2.91 — 방어형 IC 프로파일)이나 crisis active -0.0197/월 음수 — ",
                       "조건부 평가로도 전이 부재. AX-001 조건부 병기 의무 이행.")),
    label_direction_cor = num(R$label_direction_ic, 4),
    implementation_verification = list(n_pass = VER$n_pass, n_total = VER$n_total,
      items = "Gaussian 위치/스케일 닫힌형, Uniform 해석적분, barycenter 분위평균 정리(정확), affine 불변(정확), 분해 항등식, grid 수렴+노이즈 바닥, 위반 주입 2종 검출"),
    sampling_noise_context = paste0(
      "정직 관측: n=63 동일분포 표본쌍의 W1 노이즈 바닥 중앙값 0.167 vs 실측 w1_shape 중앙값 0.156 — ",
      "횡단면 형상 편차의 전형 크기가 표본 노이즈 수준. 형상 신호의 유효 정보량이 원리적으로 얇은 창 길이."),
    ast_sidecar_live_with_ast = list(before = R$sidecar$before$live_with_ast,
                                     after = R$sidecar$after$live_with_ast),
    n_iterations = 1, selection_type = "preregistered_single_primary",
    deflated_sharpe_ratio = NA,
    dsr_note = paste0(
      "사전등록 단일 primary(n_trials=1) — sweep 아님, DSR 게이트 비발동(measurement-graduation §3). ",
      "8개 진단(방향 분해 5 + 스칼라 대조 3)은 측정 전 사전등록으로 선언·전량 보고, 무엇도 선택에 미사용",
      "(no-flip 준수 — 진단 중 primary보다 canonical 좋은 것도 없어 선택 유혹 부재: 전 계열 음수). n_diagnostics=8.")),

  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,

  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH",
         flag = "canonical PORT_t -1.24 (p=0.216) — HARD 2.95 미달 + placebo 대역 [-1.52,-0.25] 내부 = canonical 수준 형상 정보량 0"),
    list(id = "CF-02", severity = "HIGH",
         flag = "기전 반증 부호 역전: 신호창 개인 순매수 Q1-Q5 t=-7.27 — '개인 복권수요 추격' 서사 정반대(개인은 점프형을 순매도). mechanism REFUTED"),
    list(id = "CF-03", severity = "HIGH",
         flag = "차별 주장 실측 미성립: 스칼라 대조군 IC가 primary보다 강함(MAX5 +0.0474 vs +0.0187) — W1 분포-거리의 독립 성분(rho 0.34~0.44)이 예측력 무기여"),
    list(id = "CF-04", severity = "MEDIUM",
         flag = "dual-basis 양 기각: EW-uni -2.05가 cap-w -1.24보다 더 나쁨 — 벤치 아티팩트 구제 불가"),
    list(id = "CF-05", severity = "MEDIUM",
         flag = "turnover 1557%/yr > 1100% 제약 위반 (성립했어도 구현 규율 미달)"),
    list(id = "CF-06", severity = "MEDIUM",
         flag = "국면 사전등록 실패: holds_in=[NEUTRAL,CRISIS] 예측 — 실측 전 국면 active 비양. 경계 도출 오류 정직 갱신"),
    list(id = "CF-07", severity = "LOW",
         flag = "rank-IC +0.0187(t 3.57)은 placebo 대역 밖 — 회피-신호(우미부-비대 저성과)는 실재하나 advisory 계열 + top-25 롱 전이 부재"),
    list(id = "CF-08", severity = "INFO",
         flag = "구현 검증 9/9 (닫힌형 대조 + 위반 주입 검출). admitted 축 직교 성립 |rho|<=0.17. sidecar live_with_ast 35->36")),

  verdict_summary = list(
    result = "config_scoped_negative__mechanism_refuted__differentiation_not_established",
    gate_eligible = FALSE,
    statement = paste0(
      "본 config(63d W1 barycenter rtail, top-25 cap-w EW long-only, 15bps, 월간 리밸, K200∪KQ150)에서 ",
      "최적수송 형상 팩터는 자본-tier 알파를 산출하지 않는다(PORT_t -1.24, placebo 대역 내부, TO 1557%). ",
      "이 라운드가 확립한 것: ① 1D W1/barycenter 구현(닫힌형 검증 9/9) ② admitted 축과의 구성적 직교",
      "(location/scale 정확 소거 — |rho|<=0.17 실측) ③ 그러나 잔여 형상 성분은 스칼라 모멘트 대비 예측력 ",
      "추가 없음(재탕 아닌 '부분중복+무기여') ④ 기전 반증의 명확한 역-사실: 개인은 점프형 종목을 신호창에 ",
      "순매도(t=-7.27) — 이것이 본 라운드 최강 실측 ⑤ 스칼라->분포 기능 일반화로도 IC->PORT_t 전이 벽 불통과 ",
      "= 벽은 요약통계 표현력이 아니라 top-25 long-only 전이층이라는 반증 증거 1건 추가. ",
      "현 config 수렴 — 부활 조건: 회피-신호의 제외-필터 소비면 유효 실측, 또는 수급-흡수 조건부 재설계."),
    consumption_scan_7 = list(
      factor_ranking = "미달 (전 성분·전 대조군 canonical 음수)",
      universe_filter = "후보 — 고-복권형(고 MAX5/rtail) 제외 필터. IC가 회피쪽에서 발원 — NP-1",
      overlay_regime_input = "비적합 (전 국면 active 비양)",
      risk_model_beta_budget = "소재 제안 — 정규화 분위편차(rtail/ltail)는 tail-risk 진단 입력 후보 (risk-research에 비바인딩 제안, 역할 경계 준수)",
      monitoring_signal = "약한 후보 — 보유종목 rtail 급변 tripwire (IC 근거만, canonical 근거 없음)",
      screening_label = "없음 (canonical placebo-급 — screen_route 발급 요건 미달)",
      cross_mode_transfer = "비적합"),
    next_probe = list(
      list(id = "NP-1", priority = "P1",
           probe = paste0("복권형 제외-필터 소비면 라운드 — 본 라운드 실측이 지목한 더 강한 스칼라 MAX5",
             "(IC +0.0474, t 4.41, placebo 대역 밖)로 고-복권 분위 제외 필터를 admitted book 위에 ",
             "book-marginal(ΔIR)로 사전등록 측정. 회피-신호는 실재하나 top-25 롱 랭킹으로는 소비 불가라는 ",
             "본 라운드 구조 진단을 정직 소비하는 경로."),
           rationale = "IC 발원이 하위(복권형 저성과) — 랭킹이 아니라 배제가 자연 소비면. W1보다 스칼라가 강하다는 실측도 함께 소비"),
      list(id = "NP-2", priority = "P2",
           probe = paste0("수급-흡수 조건부 점프 라운드 — 본 라운드 최강 실측(개인이 점프형을 신호창 순매도 ",
             "t=-7.27)의 역면: 개인 매도를 흡수한 주체(기관/외인) 조건부로 점프 후 수익 분화(점프 질 판별). ",
             "WT-006의 flow-링크 프레임(기관+외인 매집 t=+4.08)과 접합 — 사전등록 별도 라운드."),
           rationale = "성과-독립으로 확립된 수급 규칙성(|t| 7.27)을 소비면으로 전개 — 엔진 원칙(실패=다음 가설 생성기)"),
      list(id = "NP-3", priority = "P3",
           probe = paste0("전이-벽 반증 증거 적립 — 스칼라(왜도/첨도/MAX) -> 분포 기능(W1) 일반화로도 벽 불통과 ",
             "실측을 layer_bottleneck_map 전이층 행에 반영 + risk-research에 tail-shape 분위편차 소재 제안",
             "(비바인딩). 표현력 확장 계열(시그니처 WT-006, W1 본 건) 2건 연속 동일 벽 = 벽 귀속의 교차 증거."),
           rationale = "동일 벽의 독립 재현 2건 — '요약통계 표현력이 병목'이라는 가설 계열의 반증 증거를 지도에 적립"))),

  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(name = "OT_W1_RTAIL_63", canonical_port_t = num(b$portfolio_alpha_t_nw_lag3, 3),
                           selected = TRUE,
                           note = "사전등록 단일 primary. 방향분해 5 + 스칼라 대조 3 = 진단 관측(선택 비사용) — diagnostics.decomposition / scalar_moment_controls 참조")))))

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_package.json 저장")

val <- list(
  task_id = "WT-D20260802_010",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen",
  gate_eligible = FALSE,
  selection_type = "preregistered_single_primary", n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260802_010/preregistration.json (측정 전 고정)",
  implementation_verification = VER,
  primary = list(
    factor_id = "OT_W1_RTAIL_63",
    canonical = list(port_t_nw_lag3 = num(b$portfolio_alpha_t_nw_lag3, 3),
                     pvalue = num(b$portfolio_alpha_t_pvalue, 4),
                     n_months = b$n_months, net_sr = num(b$net_sr, 4),
                     information_ratio = num(b$information_ratio, 4),
                     alpha_annualized = num(b$alpha_annualized, 4),
                     turnover_annual = num(b$turnover_annual, 2)),
    subperiod_port_t = lapply(R$sub_port_t, num, d = 3),
    advisory = list(rank_ic = num(dg$rank_ic, 5), icir = num(dg$icir, 4),
                    ic_t = num(dg$ic_t, 3), monotonicity = num(dg$monotonicity, 3))),
  universe_comparison = list(
    note = "본 라운드는 배포 유니버스(K200∪KQ150)에서 직접 설계 — v2 확장 비교 비해당(신호가 canonical 수준 placebo-급이라 유니버스 한계 가설 자체가 성립 안 함)",
    cap_w = num(b$portfolio_alpha_t_nw_lag3, 3),
    ew_universe = num(ew$portfolio_alpha_t_nw_lag3, 3),
    ew_post2017 = num(ew$post2017_t_nw_lag3, 3)),
  dual_basis = pkg$diagnostics$dual_basis,
  decomposition = decomp,
  scalar_moment_controls = pkg$diagnostics$scalar_moment_controls,
  orthogonality = orth,
  self_rejection_rule_outcome = paste0(
    "사전등록 자기기각 규칙 판정: SKEW63 +0.435 / KURT63 +0.343 / MAX5 +0.396 / D03 +0.130 / ",
    "D45 +0.078 / M01 -0.014 — 자동기각 문턱(|rho|>0.5) 비발동, 0.3~0.5 부분중복 밴드 발동 = ",
    "차별 주장 약화 라벨. 성과축 판별(IC 비교)에서 차별 미성립 — 최종: 재탕은 아니나 우월도 아님."),
  placebo = plc,
  lag1 = pkg$diagnostics$lag1_stress,
  falsification = pkg$diagnostics$falsification_test,
  regime_conditional = reg_l,
  ax001_conditional = pkg$diagnostics$ax001_conditional,
  sidecar_live_with_ast = pkg$diagnostics$ast_sidecar_live_with_ast,
  graduation_hard_gates = list(
    portfolio_alpha_t_nw = list(required = 2.95, observed_canonical = num(b$portfolio_alpha_t_nw_lag3, 3),
      status = "FAIL", note = "canonical screening 실측 — forge 승격 미제출(자본 판정 아님)"),
    oos_retention = list(required = 0.7, observed = NA, status = "NOT_COMPUTED",
      note = "PORT_t 음수 + placebo-급으로 forge 미제출 — 산출 무의미"),
    calmar = list(required = 0.64, observed = NA, status = "NOT_COMPUTED",
      note = "PORT_t 미달로 forge 미제출")),
  production_constraints = list(turnover_annual_limit = 11.0,
    observed = num(b$turnover_annual, 2), verdict = "FAIL — 성립했어도 구현 규율 미달"))
write_json(val, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_validation.json 저장")

# lineage (package write 이후 — L-194 순서)
try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_010", package_type = "alpha_package",
    method_selected = "OT_W1_RTAIL_63 (사전등록 단일 primary — 1D Wasserstein barycenter 우미부 편차, SPECIAL_OP escape)",
    input_file_paths = c(".cache/RAWDATA.parquet",
                         ".cache/investor_stock/investor_wide.parquet",
                         ".cache/unified_regime_signal.parquet",
                         file.path(OUT, "ot_panel.parquet"),
                         file.path(OUT, "preregistration.json")))
  say("lineage 기록 완료")
}, silent = FALSE)

st <- list(task_id = "WT-D20260802_010", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), blocker = NULL)
write_json(st, file.path(MB, "status.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
gl <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
gl$events <- c(gl$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_PACKAGE_EMITTED",
  summary = paste0("사전등록 단일 primary OT_W1_RTAIL_63 — canonical PORT_t -1.24 (placebo 대역 내) / ",
    "기전 반증 부호 역전(개인 순매도 t=-7.27) / 스칼라 대조군이 IC 우월 = 차별 미성립 / ",
    "config-scoped negative + mechanism-refuted. 구현 검증 9/9. next_probe 3건. challenge_note 작성."))))
write_json(gl, file.path(MB, "governance_log.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
say("status/governance 갱신 완료")
