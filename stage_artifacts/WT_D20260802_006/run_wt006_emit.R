# =============================================================================
# run_wt006_emit.R — WT-D20260802_006 AST v1.1 3층 alpha_package + validation + lineage
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_006/run_wt006_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_006")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_006")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[emit] ", fmt, "\n"), ...))

R   <- readRDS(file.path(OUT, "wt006_eval_results.rds"))
VER <- fromJSON(file.path(OUT, "verify_results.json"), simplifyVector = FALSE)
PRE <- fromJSON(file.path(OUT, "preregistration.json"), simplifyVector = FALSE)
b   <- R$bt$SIG_LEVY_PV_63
ew  <- b$diag_ew_universe
ct  <- b$diag_cap_tier
dg  <- R$diag$SIG_LEVY_PV_63
PAN <- as.data.table(read_parquet(file.path(OUT, "signature_panel.parquet")))

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
                       0.5 * as.numeric(nd[[tk]] %||% 0.5)))), numeric(1))
confidence_vector <- as.list(setNames(conf, LV$Ticker))

esc <- list(escape_type = "SPECIAL_OP",
            op_code_path = "stage_artifacts/WT_D20260802_006/signature_lib.R::sig_features_pv",
            walk_forward = TRUE)
ast_primary <- list(op = "CS_ZSCORE", args = list(list(op = "CS_WINSORIZE", args = list(
  list(leaf = "SPECIAL_OP",
       field = "levy_area_pv_63d (score = -A_pv)",
       op_code_path = esc$op_code_path, walk_forward = TRUE,
       escape_contract = esc),
  3), params = list(sd = 3))))

num <- function(x, d = 4) if (is.null(x) || !is.finite(x)) NA else round(as.numeric(x), d)
plc <- lapply(R$placebo, function(p) list(port_t = num(p$port_t, 3), rank_ic = num(p$rank_ic, 5)))
orth <- lapply(R$orth, function(o) list(rho_mean = num(o$mean, 3), rho_sd = num(o$sd, 3)))
lvl_decomp <- lapply(R$bt[setdiff(names(R$bt), "SIG_LEVY_PV_63")], function(r)
  list(port_t = num(r$portfolio_alpha_t_nw_lag3, 3),
       ew_uni_t = num(r$diag_ew_universe$portfolio_alpha_t_nw_lag3, 3),
       net_sr = num(r$net_sr, 3), turnover_annual = num(r$turnover_annual, 2)))
reg_l <- lapply(seq_len(nrow(R$regime_tab)), function(i)
  list(regime = R$regime_tab$Category[i], n = R$regime_tab$n[i],
       mean_active = num(R$regime_tab$mean_active[i], 5), t_nw = num(R$regime_tab$t_nw[i], 2)))

pkg <- list(
  task_id = "WT-D20260802_006",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",

  hypothesis = list(
    statement = paste0(
      "종목-월의 (log가격, log거래대금) 일간 경로의 truncated signature 레벨-2 비대칭 성분(Lévy area A_pv)은 ",
      "정보거래자 축적(거래-선행, A_pv<0)과 잡음거래자 추격(가격-선행, A_pv>0)을 부호로 구분하는 재매개화-불변 ",
      "기하 불변량이며, score=-A_pv 상위 종목이 익월 초과수익. 사전등록 단일 primary — ",
      "stage_artifacts/WT_D20260802_006/preregistration.json (측정 전 고정, no-flip 조항 포함)."),
    mechanism = PRE$mechanism,
    falsification = paste0(
      "A6_investor_flow_stock_daily(investor_wide Foreign/Institutional): score Q5 종목의 후속 홀딩월 ",
      "(외인+기관) 순매수/ADV·일이 Q1 대비 유의(t>=2) 높지 않으면 '축적 주체' 기전 기각. ",
      "성과 동어반복 아님 — 수익과 독립 판정."),
    regime_scope = list(
      holds_in = list("RISK_ON"),
      weakens_or_reverses_in = list("CRISIS", "NEUTRAL"),
      boundary_rationale = paste0(
        "사전등록: 위기=공통 유동성 청산이 횡단면 lead-lag 소거(→약화). 실측으로 CRISIS 약화 지지(t=-1.13), ",
        "RISK_ON 지지(t=+2.71). 단 NEUTRAL 역전(t=-2.47)은 사전 미도출 — 사전등록 holds_in=[neutral,recovery] 대비 ",
        "부분 오류를 정직 반영해 갱신(challenge_note C7 ACCEPT)."))),

  factors = list(list(
    factor_id = "SIG_LEVY_PV_63",
    ast = ast_primary,
    role = "core_signal",
    restatement_exposure = 0,
    restatement_note = "가격/거래량 리프 — 재무 재작성 비대상. 저장 Ret 재계산 없음(Close/Vol만 사용)."
  )),
  combination_rule = "single_factor",
  verdict = "designed",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "A2_price_volume_daily:Close",
           availability_rule = "fixed: t 종가 — 신호 창 = Date <= sig_date 하드 슬라이스 (C1 rolling)",
           restatement_prone = FALSE),
      list(leaf = "A2_price_volume_daily:Vol",
           availability_rule = "fixed: t 거래량. Vol=0/결측일은 경로에서 스킵(재매개화 불변성으로 정당 — 사전등록 명시)",
           restatement_prone = FALSE)),
    verdict = "clean",
    verdict_rationale = paste0(
      "C1: trailing 창 결정론 함수(적합 파라미터 0, full-sample 통계 없음). C2/C3: 신호(t 이하)와 ",
      "라벨(t→t+1 forward, 하네스 표준) 분리 — M01 라벨 방향 감사 +0.0107. C10: 유동성필터 하네스 표준 adv. ",
      "lag1 붕괴(+1.23→+0.24)는 challenge_note C1에서 누출 아닌 반감기로 판정(누출 기전 구조 부재).")),

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_006/alpha_scores.parquet",

  factor_specs = list(list(
    factor_family = "Path_Geometry_NonScalar",
    proxy = "Levy_area_price_volume_63d",
    formula = paste0("score = -A_pv; A_pv = (S^{pv} - S^{vp})/2, S = truncated signature lvl2, ",
                     "경로 = (log Close 누적/sd(일간증분), log(Close*Vol) 누적/sd(일간증분)), 63 거래일. ",
                     "CS winsorize 3sd -> CS z"),
    lag_rule = "price/volume t 종가 (창 = sig_date 이하), forward return t->t+1 월말",
    winsorization = "3std",
    neutralization = "none (표준화가 vol/거래대금 스케일 채널을 구성적으로 소거)",
    economic_rationale = paste0(
      "정보거래자 스텔스 축적은 거래대금이 가격을 선행(가격충격 절약 분할매집), 잡음거래자 추격은 역순. ",
      "저빈도 관찰자는 종점(수준)만 소비 — 경로 순서 정보는 표준 팩터에 부재. 위상차 해석해 A_pv=-pi*sin(phi)로 ",
      "방향 사전 도출(구현 검증 T5 재현). 반증 검정 실측: 후속월 기관+외인 flow Q5-Q1 NW t=+4.08 — 기전 지지."),
    weight_theta = 1.0,
    redundancy_cluster_id = "path_signature_geometry_new",
    source = "new_designed",
    references = list(
      "Lyons 1998 (rough paths)", "Gyurko-Lyons-Kontkowski-Field 2013 (lead-lag via signatures)",
      "Chevyrev-Kormilitzin 2016 (signature primer)", "preregistration.json 2026-08-02"))),

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
      ew_universe_oos_retention_approx = num(ew$oos_retention_approx, 4),
      cap_tier_weight_share = ct$weight_share_avg,
      cap_tier_contrib_annualized = ct$contrib_gross_annualized,
      verdict = paste0(
        "v8.3 기각-전 확인 의무 이행: EW-uni 전기간 t=+1.93으로 cap-w(+1.23)보다 강하나 post2017 EW t=-0.07 — ",
        "감쇠는 mega-cap 벤치 아티팩트로 구제되지 않는다(양 basis 공멸). cap-tier: OTHER 93.4% ",
        "(스코어풀 base ~90% 대비 lift ~1.03) — 국소화 미미, cap-w 트랩 아님.")),
    level_decomposition = lvl_decomp,
    level1_exclusion_rationale = paste0(
      "레벨-1 가격 성분(LVL1_P_63, 3M 표준화 모멘텀 등가) 단독 PORT_t +1.10 — primary와 rho 0.385로 겹치는 ",
      "저차 성분. 신호에서 제외(사전등록)한 것은 기존 모멘텀 커버 + 직교 잔차(레벨-2 비대칭)만 신규 기여이기 때문. ",
      "레벨-3 두 성분은 0 근방(+0.18/-0.12) — 이 config에서 추가 정보 없음 실측."),
    orthogonality = orth,
    placebo_shuffle = plc,
    placebo_note = paste0(
      "일간 증분 (dp,dv) 쌍 공동 셔플(순서만 파괴, 주변분포·공분산 보존) 5시드 전패널 재계산. ",
      "PORT_t 범위 [-1.16,+0.51] vs primary +1.23 — 상단 밖이나 여유 얇음(challenge_note C2 ACCEPT). ",
      "사전등록 문구(n=200)는 계산량으로 5시드 전패널로 집행 — 축소를 정직 기재."),
    lag1_stress = list(base_port_t = num(b$portfolio_alpha_t_nw_lag3, 3),
                       lag1_port_t = num(R$bt_lag1$portfolio_alpha_t_nw_lag3, 3),
                       verdict = "붕괴 — 누출 아닌 단반감기(challenge_note C1 PARTIAL). 월간 배포 부적합 신호속도."),
    falsification_test = list(
      field = "A6_investor_flow_stock_daily",
      q5_q1_spread_mean = num(R$falsification$mean_spread, 5),
      t_nw = num(R$falsification$t_nw, 3),
      n_months = R$falsification$n_months,
      verdict = "MECHANISM_SUPPORTED — 거래-선행 상위 종목에 후속 기관+외인 순매수 유의 유입(t=+4.08)"),
    regime_conditional = reg_l,
    label_direction_cor = num(R$label_direction_ic, 4),
    implementation_verification = list(n_pass = VER$n_pass, n_total = VER$n_total,
      items = "선형 닫힌형/원호 pi/Chen 항등식/재매개화 불변/위상차 -pi*sin(phi)/벡터화 parity/위반 주입"),
    ast_sidecar_live_with_ast = list(before = R$sidecar$before$live_with_ast,
                                     after = R$sidecar$after$live_with_ast),
    n_iterations = 1, selection_type = "preregistered_single_primary",
    deflated_sharpe_ratio = NA,
    dsr_note = paste0(
      "사전등록 단일 primary(n_trials=1) — sweep 아님, DSR 게이트 비발동(measurement-graduation §3). ",
      "레벨 분해·창 21/126·레벨3 등 8개 진단 실측은 전량 보고하되 무엇도 선택에 사용하지 않음(no-flip 조항 준수 ",
      "— 실제로 primary보다 좋은 진단이 없어 선택 유혹 자체가 없었음도 부기). n_diagnostics=8 사후감사 기록.")),

  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,

  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH",
         flag = "canonical PORT_t +1.23 (p=0.221) — HARD 2.95 미달. 자본-tier 승격 불가 (challenge_note C2/C4 ACCEPT)"),
    list(id = "CF-02", severity = "HIGH",
         flag = "post-2017 소멸: cap-w -1.07 / EW-uni -0.07 — dual-basis 양쪽 사망 = 벤치 아티팩트 구제 불가. oos_retention_approx 0.055 decay-pattern"),
    list(id = "CF-03", severity = "HIGH",
         flag = "turnover 1578%/yr > 1100% 제약 위반. 평활 미실측(사전등록 밖) — NP-2로 승계"),
    list(id = "CF-04", severity = "MEDIUM",
         flag = "rank-IC 음수(-0.0097) vs PORT_t 양수 — 효과는 top-tail 국소, 횡단면 단조성 미성립(mono 0.14). 기전 flow-링크는 성립(t=4.08)하나 flow→수익 고리가 약한 고리"),
    list(id = "CF-05", severity = "MEDIUM",
         flag = "placebo 5시드 분리 여유 얇음 — 경로-순서 정보의 수익 기여를 PORT_t 단독으로 확립 못함"),
    list(id = "CF-06", severity = "MEDIUM",
         flag = "lag1 +1.23→+0.24 붕괴 — 누출 기전 부재(창 하드 슬라이스)로 단반감기 판정이나 월간 리밸 부적합 신호속도"),
    list(id = "CF-07", severity = "LOW",
         flag = "국면 경계 사전등록 부분 오류 — NEUTRAL 역전(t=-2.47) 미도출. regime_scope 갱신 반영"),
    list(id = "CF-08", severity = "INFO",
         flag = "구현 검증 11/11 (이론값 대조 + 위반 주입). 직교성 실측 성립: 기존 5팩터 |rho|<=0.11. ast_sidecar live_with_ast 17->18")),

  verdict_summary = list(
    result = "config_scoped_negative_capital_tier__mechanism_confirmed",
    gate_eligible = FALSE,
    statement = paste0(
      "본 config(63d Lévy area, top-25 cap-w EW long-only, 15bps, 월간 리밸, K200∪KQ150)에서 ",
      "경로 시그니처 primary는 자본-tier 알파를 산출하지 않는다(PORT_t +1.23, post2017 사망, TO 1578%). ",
      "단 이 라운드가 확립한 것: ① 시그니처 불변량 구현(정리-수준 검증 11/11) ② 기존 팩터와 구조 직교 실측 ",
      "③ 기전의 flow-링크(후속 기관+외인 매집 t=+4.08) — '축적 측정'은 실재하고 '수익 전이'가 벽 ",
      "(인접 Hurst/TE/hill_tail과 동일 벽이나, 이들과 달리 기전 실재가 성과-독립으로 입증된 점이 차별). ",
      "현 config 수렴 — 부활 조건: 평활판 TO 충족 + post2017 생존, 또는 flow-예측 소비면 유효."),
    consumption_scan_7 = list(
      factor_ranking = "미달 (현 config)",
      universe_filter = "후보 — A_pv 상위(가격-선행 과열) 제외 필터. NP-3 연계",
      overlay_regime_input = "보류 — RISK_ON 국소 유효(t 2.71)이나 regime-conditional 교차결합은 settled-negative 계열(INV-7) — 부활신호 없이 미착수",
      risk_model_beta_budget = "비적합",
      monitoring_signal = "적합 — 보유종목 A_pv 급변(축적→분산 전환) tripwire + flow 선행지표(t=4.08 실측 근거)",
      screening_label = "frontier 큐 등재 후보 — flow-prediction lane",
      cross_mode_transfer = "RAMP 잔차 sleeve 후보군 비-return 계열 소재(조건부)"),
    next_probe = list(
      list(id = "NP-1", priority = "P1",
           probe = paste0("flow-예측 소비면 라운드 — A_pv가 후속월 기관+외인 순매수를 예측(t=+4.08, 259개월)한다는 ",
             "확립 능력을 수익 아닌 flow 예측으로 소비: ① monitoring tripwire(보유종목 축적/이탈 전환 경보) 배선 ",
             "② INV 계열 팩터(Foreign_NetBuy 등)의 경로-순서 조건부 강화(진짜 축적 vs 일회성 flow 구분) 사전등록 후 별도 라운드."),
           rationale = "이 라운드의 최강 실측(t=4.08)이 수익축이 아닌 flow축 — 능력을 확립한 축에서 소비하는 것이 정도"),
      list(id = "NP-2", priority = "P2",
           probe = "TS_MEAN 3M 평활 A_pv — TO 1578%→추정 ~500%대로 제약 충족 + 고빈도 성분 제거 후 post2017 생존 재측정 (WT_001 R2 평활이 음수 제거한 전례). 사전등록 별도 라운드(본 라운드 no-flip 준수로 미실측)",
           rationale = "CF-03 해소 경로. 단반감기(CF-06)와 상충 가능 — 평활이 신호를 죽이는지가 판별 질문"),
      list(id = "NP-3", priority = "P2",
           probe = "A_TP(시간-가격 area) 역방향 — EW-uni t=-2.04 실측: '후기-집중 수익 경로=과열' 가설로 부호 사전 고정 후 재도전. 본 라운드에서는 진단 관측일 뿐 선택하지 않음",
           rationale = "레벨-2 나머지 성분에서 유일하게 |t|>2 (EW basis) — 사전등록 요건 갖추면 독립 가설"),
      list(id = "NP-4", priority = "P3",
           probe = "pre-2015 강세(+3.69) 감쇠 귀속 — 계단 단절 시점 특정(FQ-055 함수형 진단 프레임 재사용) + 거래대금 데이터 미시구조 변화(2015 호가단위/2017 공매도 규제) 대조",
           rationale = "감쇠의 기전 미귀속 상태 — cohort-wide 벽과 개별 원인의 분리"))),

  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 1,
    method_log = list(list(name = "SIG_LEVY_PV_63", canonical_port_t = num(b$portfolio_alpha_t_nw_lag3, 3),
                           selected = TRUE,
                           note = "사전등록 단일 primary. 레벨분해/창강건성 8개는 진단 관측(선택 비사용) — diagnostics.level_decomposition 참조")))))

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_package.json 저장")

val <- list(
  task_id = "WT-D20260802_006",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen",
  gate_eligible = FALSE,
  selection_type = "preregistered_single_primary", n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260802_006/preregistration.json (측정 전 고정)",
  implementation_verification = VER,
  primary = list(
    factor_id = "SIG_LEVY_PV_63",
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
    note = "본 라운드는 배포 유니버스(K200∪KQ150)에서 직접 설계 — v2 확장 비교는 ICIR attenuation 진단 목적 아님(신호 자체가 post2017 소멸이라 유니버스 한계 가설 비해당)",
    cap_w = num(b$portfolio_alpha_t_nw_lag3, 3),
    ew_universe = num(ew$portfolio_alpha_t_nw_lag3, 3),
    ew_post2017 = num(ew$post2017_t_nw_lag3, 3)),
  dual_basis = pkg$diagnostics$dual_basis,
  level_decomposition = lvl_decomp,
  orthogonality = orth,
  placebo = plc,
  lag1 = pkg$diagnostics$lag1_stress,
  falsification = pkg$diagnostics$falsification_test,
  regime_conditional = reg_l,
  sidecar_live_with_ast = pkg$diagnostics$ast_sidecar_live_with_ast,
  graduation_hard_gates = list(
    portfolio_alpha_t_nw = list(required = 2.95, observed_canonical = num(b$portfolio_alpha_t_nw_lag3, 3),
      status = "FAIL", note = "canonical screening 실측 — forge 승격 미제출(자본 판정 아님)"),
    oos_retention = list(required = 0.7, observed_approx_ew = num(ew$oos_retention_approx, 4),
      status = "FAIL_APPROX", note = "진단 근사(권위는 essence_score) — decay-pattern"),
    calmar = list(required = 0.64, observed = NA, status = "NOT_COMPUTED",
      note = "PORT_t 미달로 forge 미제출")),
  production_constraints = list(turnover_annual_limit = 11.0,
    observed = num(b$turnover_annual, 2), verdict = "FAIL — NP-2 평활 승계"))
write_json(val, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_validation.json 저장")

# lineage (package write 이후 — L-194 순서)
try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_006", package_type = "alpha_package",
    method_selected = "SIG_LEVY_PV_63 (사전등록 단일 primary — path signature Levy area, SPECIAL_OP escape)",
    input_file_paths = c(".cache/RAWDATA.parquet",
                         ".cache/investor_stock/investor_wide.parquet",
                         ".cache/unified_regime_signal.parquet",
                         file.path(OUT, "signature_panel.parquet"),
                         file.path(OUT, "preregistration.json")))
  say("lineage 기록 완료")
}, silent = FALSE)

# status + governance 갱신
st <- list(task_id = "WT-D20260802_006", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), blocker = NULL)
write_json(st, file.path(MB, "status.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
gl <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
gl$events <- c(gl$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_PACKAGE_EMITTED",
  summary = paste0("사전등록 단일 primary SIG_LEVY_PV_63 — canonical PORT_t +1.23 (HARD 미달) / ",
    "기전 flow-링크 t=+4.08 확인 / 직교성 성립 / config-scoped negative(자본) + mechanism-confirmed. ",
    "구현 검증 11/11. next_probe 4건. challenge_note 8 concern."))))
write_json(gl, file.path(MB, "governance_log.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
say("status/governance 갱신 완료")
