## A10 — alpha_package.json (AST v1.1 3층) + alpha_validation.json 발행
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
say <- function(fmt, ...) cat(sprintf(paste0("[A10] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
MB  <- "qepm/mailbox/worktask/WT-D20260809_004"
P <- readRDS(file.path(OUT,"panels.rds")); L <- readRDS(file.path(OUT,"layers.rds"))
AR <- readRDS(file.path(OUT,"arms.rds")); S <- readRDS(file.path(OUT,"stress.rds"))
DG <- readRDS(file.path(OUT,"diagnostics.rds")); IH <- readRDS(file.path(OUT,"inherit.rds"))
HY <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector = FALSE)

sel <- as.data.table(DG$scp)
av <- setNames(as.list(round(sel$alpha_hat, 6)), sel$Ticker)
cv <- setNames(as.list(round(sel$conf, 4)), sel$Ticker)
say("alpha_vector %d종목 · confidence 평균 %.3f (sd %.3f · 최소 %.3f)",
    length(av), mean(sel$conf), sd(sel$conf), min(sel$conf))

pl05 <- S$PL[["b12_l0.5"]]; pl10 <- S$PL[["b12_l1.0"]]

pkg <- list(
  task_id = "WT-D20260809_004",
  as_of_date = as.character(DG$asof),
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = as.character(DG$asof),
             decision_ts = as.character(DG$asof),
             note = "홀딩월 = as_of 다음달. 전 리프 컷오프 <= sig_date, assert_overlay_pit 5축 HARD PASS + 위반 주입 검출 확인(a9_pit_assert.R)"),

  ## ── 승계층 (alpha-hypothesis/fable 발행분 — 재작성 없음. 배열 스키마 전사만) ──
  hypothesis = list(
    statement = HY$selected$hypothesis_description,
    mechanism = list(agent = HY$selected$mechanism$agent,
                     friction = HY$selected$mechanism$friction,
                     path = HY$selected$mechanism$path),
    falsification = list(
      list(field = "A1_RAWDATA_OHLCVS_daily",
           expectation = paste0("원자재-연동 섹터(에너지·소재)의 β_s > 0, 규제-가격(유틸리티·통신) 및 ",
             "장기듀레이션(소프트웨어·건강관리·미디어) 섹터의 β_s < 0 이 표본 대부분에서 유지. ",
             "부호가 무작위면 성과가 나와도 인플레 기전이 아니다 (성과-독립 관측). ",
             "[실측 2026-08-09] 예측 부여 10섹터 일치율 0.649 (stride-12 0.638, 이항 p=0.0005) → 기각되지 않음. ",
             "단 방향 비대칭: 음(-) 예측 5섹터 전건 통과 vs 양(+) 예측은 철강 0.799·화학 0.732 만 통과, 에너지 0.434·상사자본재 0.105 는 예측 반대."),
           source_leaf = "A1_RAWDATA_OHLCVS_daily (Sector 26종 + 월수익 → 섹터 EW 초과수익)"),
      list(field = "E1_fred_macro_raw",
           expectation = paste0("합성 인플레 지수의 T5YIE(Breakeven_5Y)·Copper_Price 성분이 실재 신호를 담아야 한다. ",
             "F4 블록순열 플라시보(블록 12, 200판)에서 실측 층-증분이 95분위를 넘어야 한다. ",
             "[실측] λ=0.5 백분위 80.5% (95분위 +1.796%/yr, 실측 +1.094%/yr) · λ=1.0 백분위 71.0% → 95분위 미달."),
           source_leaf = "E1_fred_macro_raw (T5YIE 일간 · PCOPPUSDM 월간)"),
      list(field = "E2_ecos_kr_rates",
           expectation = paste0("KR_CPI(901Y009) YoY 성분이 참조월 M-2 정렬에서 가용해야 하고, ",
             "발표 lag 을 M-1 로 당기면 동월 누출이 된다. [실측] 캐시 최신 거래일 2026-08-07 시점 최신 참조월 ",
             "KR_CPI=2026-07·Copper=2026-06 → 두 계열 모두 M-2 로 보수 고정."),
           source_leaf = "E2_ecos_kr_rates (KR_CPI)"),
      list(fields = c("C01_SUE","C02_EPS_Chg_1m","M26_Revenue_Mom"),
           expectation = paste0("컨센서스 3종의 lag_rule 이 'Date <= sig_d'(same-day) 이므로 offset 스캔에서 ",
             "동시월 IC 가 forward IC 보다 뚜렷이 커야 한다(=동시성 상관 실재 확인). ",
             "[실측] offset0 t_NW3 13.264 vs offset+1 5.054 (배수 2.62, FQ-165 M26 3.34 계통) → 본 라운드는 offset+1 만 소비."),
           source_leaf = "FDB-B3_registry_consensus_daily / C-REGISTRY-PTR-FUND"),
      list(field = "A9_liquidity_avgtv20_convention",
           expectation = "발행 패널 전행이 adv20 >= 2e8 을 만족해야 한다 (2026-08-08 위반 사고 재발 방지). [실측] 최소 adv20 = 2.003e8, assert 통과."),
      list(field = "F1_lag1_timing_stress",
           field_ref = "A1_RAWDATA_OHLCVS_daily",
           expectation = paste0("신호 1개월 지연판에서 층-증분이 base 대비 50% 미만으로 축소되면 타이밍 아티팩트. ",
             "[실측] λ=0.5 잔존율 0.84 · λ=1.0 잔존율 1.20 → 타이밍 아티팩트 아님. ",
             "단 base 증분 자체가 비유의하므로 이 통과는 정보량이 낮다."))
    ),
    regime_scope = list(
      holds_in = unlist(HY$selected$regime_scope$holds_in),
      weakens_or_reverses_in = unlist(HY$selected$regime_scope$weakens_or_reverses_in),
      boundary_rationale = HY$selected$regime_scope$boundary_rationale
    )
  ),

  ## ── ⑤ AST 층 (alpha-research 소관) ──
  factors = list(
    list(factor_id = "C01_SUE", role = "core_signal", ast = list(leaf = "C01_SUE"),
         note = "load_month_factors 의 Z_Score_Aligned (C13 방향정렬·C15 관문). 동일가중 결합, 스윕 없음.",
         restatement_exposure = 0),
    list(factor_id = "C02_EPS_Chg_1m", role = "core_signal", ast = list(leaf = "C02_EPS_Chg_1m"),
         note = "동일", restatement_exposure = 0),
    list(factor_id = "M26_Revenue_Mom", role = "core_signal", ast = list(leaf = "M26_Revenue_Mom"),
         note = "동일", restatement_exposure = 0),
    list(factor_id = "F2_inflation_compass_index",
         role = "conditioner_market_level",
         ast = list(leaf = "SPECIAL_OP",
                    op_code_path = "stage_artifacts/WT-D20260809_004/a1_build_panels.R::exp_z (expanding z, 최소 36개월) + 4성분 동일가중",
                    walk_forward = TRUE,
                    escape_contract = list(escape_type = "SPECIAL_OP",
                      op_code_path = "stage_artifacts/WT-D20260809_004/a1_build_panels.R::exp_z (expanding z, 최소 36개월) + 4성분 동일가중",
                      walk_forward = TRUE)),
         note = paste0("z1=z(T5YIE-2.0) · z2=z(T5YIE 60거래일 모멘텀) · z3=z(KR_CPI YoY, 참조월 M-2) · ",
           "z4=z(Copper YoY, 참조월 M-2). ★escape 사유: 𝒪 의 TS_MEAN/TS_STD 는 **고정 창**이라 ",
           "expanding window z 를 표현할 수 없다. 우회 근사(큰 고정창) 대신 escape 리프로 정직 선언한다."),
         restatement_exposure = 0),
    list(factor_id = "F3_sector_inflation_beta",
         role = "conditioner_sector_level",
         ast = list(leaf = "SPECIAL_OP",
                    op_code_path = "stage_artifacts/WT-D20260809_004/a3_layers.R (섹터 EW 초과수익 집계 + trailing 60m cov/var) · a4_tilt_scale.R (scale-only 정규화)",
                    walk_forward = TRUE,
                    escape_contract = list(escape_type = "SPECIAL_OP",
                      op_code_path = "stage_artifacts/WT-D20260809_004/a3_layers.R (섹터 EW 초과수익 집계 + trailing 60m cov/var) · a4_tilt_scale.R (scale-only 정규화)",
                      walk_forward = TRUE)),
         note = paste0("β_s,t = cov(r_s, Δinfl)/var(Δinfl), trailing 60개월·최소 36개월, sig_date 이전 실현월만. ",
           "판정판은 월별 섹터 횡단면 scale-only 정규화 β/sd (부호 보존율 1.0000). ",
           "★escape 사유: 𝒪 에 TS_BETA 는 있으나 **섹터 그룹 EW 집계**(횡단면 그룹 평균)가 없다."),
         restatement_exposure = 0)
  ),
  combination_rule = "z_score_aligned_equal_weight",
  combination_rule_detail = paste0(
    "α̂(종목) = mean(Z_Score_Aligned: C01_SUE, C02_EPS_Chg_1m, M26_Revenue_Mom) — 동일가중 고정, 스윕 없음. ",
    "★조립층은 alpha 산출 밖이다: 본 라운드가 측정한 포트폴리오 구성 규칙 ",
    "w_s ∝ base_s·exp(λ·β̃_s,t·infl_t) → n_s = largest-remainder(25·w_s) → 섹터 내 α̂ 상위 n_s 는 ",
    "combination_rule enum 5종 어디에도 없다(전부 종목-레벨 결합 전제). 그 층은 F3 귀속 판정에서 ",
    "**알파 기여 미확립**으로 나왔으므로 α̂ 정의에 포함하지 않고 factors[] 의 conditioner 역할과 ",
    "alpha_validation.json arms 절에 실측으로만 남긴다."),
  verdict = "designed",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "C01_SUE", availability_rule = "registry availability=fixed / lag_rule 'Date <= sig_d' (same-day 컨센서스)", restatement_prone = FALSE,
           note = "선언 T-1 과 코드 강제점 비대칭 — offset 스캔으로 forward 정렬 실증(t0/t1 = 2.62)"),
      list(leaf = "C02_EPS_Chg_1m", availability_rule = "동일 (same-day 컨센서스)", restatement_prone = FALSE),
      list(leaf = "M26_Revenue_Mom", availability_rule = "동일 (same-day 컨센서스) — FQ-165 offset0/1 3.34배 당사자", restatement_prone = FALSE),
      list(leaf = "E1_fred_macro_raw:Breakeven_5Y", availability_rule = "fixed / 시장가 일간, sig_date 이하 roll", restatement_prone = FALSE),
      list(leaf = "E1_fred_macro_raw:Copper_Price", availability_rule = "fixed / 월간, **실측 발표 lag M-2**", restatement_prone = FALSE),
      list(leaf = "E2_ecos_kr_rates:KR_CPI", availability_rule = "regulatory / 월간, 참조월 M-2 (FQ-068 규약)", restatement_prone = FALSE),
      list(leaf = "A1_RAWDATA_OHLCVS_daily", availability_rule = "fixed / T-1 close", restatement_prone = FALSE),
      list(leaf = "A9_liquidity_avgtv20_convention", availability_rule = "fixed / sig_date 포함 직전 20 거래일 mean(Close*Vol)", restatement_prone = FALSE)
    ),
    verdict = "clean",
    evidence = "a9_pit_assert.R — 5축 assert_overlay_pit HARD PASS + 위반 주입 시 발화 확인(검사기 생존 실증)"
  ),

  alpha_vector = av,
  confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT-D20260809_004/alpha_scores.parquet",

  factor_specs = list(
    list(factor_family = "Growth/Consensus_Revision", proxy = "C01_SUE",
         formula = "(Actual - Forecast)/std, Z_Score_Aligned", lag_rule = "Date <= sig_d (same-day 컨센서스 — offset+1 소비)",
         winsorization = "factor_db 빌더 기본", neutralization = "none (섹터 중립화는 조립층 정원이 대행)",
         economic_rationale = "behavioral",
         economic_rationale_detail = "어닝 서프라이즈는 컨센 개정 지연으로 1~3개월 drift — 인플레 전가력 실현을 이익 수치로 먼저 입증한 종목",
         weight_theta = 1/3, redundancy_cluster_id = "DUPC-005 (redundant; canonical=C05_ESCR, cor 0.990)",
         references = I(c("Bernard-Thomas 1989 PEAD"))),
    list(factor_family = "Growth/Consensus_Revision", proxy = "C02_EPS_Chg_1m",
         formula = "1M EPS forecast revision, Z_Score_Aligned", lag_rule = "Date <= sig_d (same-day — offset+1 소비)",
         winsorization = "factor_db 빌더 기본", neutralization = "none",
         economic_rationale = "behavioral",
         economic_rationale_detail = "애널리스트 개정 모멘텀 — 정보 반영 지연",
         weight_theta = 1/3, redundancy_cluster_id = "DUPC-006 (canonical; 동군 M27_Analyst_Rev_Mom)",
         references = I(c("Chan-Jegadeesh-Lakonishok 1996"))),
    list(factor_family = "Growth/Revenue_Revision", proxy = "M26_Revenue_Mom",
         formula = "(rev_fy1_now - rev_fy1_63d)/|rev_fy1_63d|, Z_Score_Aligned", lag_rule = "Date <= sig_d (same-day — offset+1 소비)",
         winsorization = "factor_db 빌더 기본", neutralization = "none",
         economic_rationale = "behavioral",
         economic_rationale_detail = "매출 전망 개정 — 인플레기 명목 매출 성장과 마진 훼손을 구별하는 축",
         weight_theta = 1/3, redundancy_cluster_id = "미지정 (dedup 클러스터 없음)",
         references = I(c("FQ-165 / WT-D20260808_002 실측"))),
    list(factor_family = "Macro/Inflation_Conditioner", proxy = "infl_t 합성 지수",
         formula = "mean(z(T5YIE-2.0), z(T5YIE 60d mom), z(KR_CPI YoY M-2), z(Copper YoY M-2)), expanding z >=36m",
         lag_rule = "T5YIE: <= sig_date / KR_CPI·Copper: 참조월 M-2",
         winsorization = "none", neutralization = "n/a (시장 레벨 스칼라)",
         economic_rationale = "structural",
         economic_rationale_detail = "기대(T5YIE)+실현(KR_CPI)+실물확인(Copper) 3축으로 인플레 국면 강도를 연속 측정",
         weight_theta = 0, redundancy_cluster_id = "n/a — 조건화 변수(종목 스코어 아님)",
         references = I(c("cssanalytics Inflation Compass 2026-07-27 (출발점, 승인서 아님)"))),
    list(factor_family = "Macro/Sector_Sensitivity", proxy = "β_s,t",
         formula = "cov(r_s^excess, Δinfl)/var(Δinfl), trailing 60m, 실현월만, 섹터 횡단면 scale-only 정규화",
         lag_rule = "추정창 종점 < sig_date",
         winsorization = "none", neutralization = "n/a",
         economic_rationale = "structural",
         economic_rationale_detail = "원가 전가력·듀레이션 차이를 KR 데이터에서 추정 (논문 고정 매핑 이식 근거 부재)",
         weight_theta = 0, redundancy_cluster_id = "n/a",
         references = I(c("본 라운드 실측 — 부호 패턴 일치율 0.649")))
  ),

  diagnostics = list(
    ## ★1급 (선택 권위) — canonical_screen_bt 실측, metric_type = canonical_screen
    canonical_port_t_nw_lag3 = 2.479,
    canonical_port_t_pvalue = as.numeric(DG$r0_full$portfolio_alpha_t_pvalue),
    canonical_n_months = 284L,
    canonical_metric_type = "canonical_screen",
    canonical_basis = "cap-w 벤치(유니버스 Size 가중) · top-25 EW · 15bps · adv20>=2e8 · 전창 284개월",
    canonical_scope_note = paste0("이 값은 발행 alpha_vector 의 재료인 **층3(성장 합성) 단독**이다. ",
      "설계 전체(인플레 틸트 결합)의 공통창 값은 아래 arms_common_window_209m 참조 — ",
      "★서로 다른 창이므로 나란히 비교 금지."),
    rank_ic = DG$ic_full$rank_ic, icir = DG$ic_full$icir,
    harvey_t_stat = DG$ic_full$t_nw3,
    monotonicity = DG$mono,
    subperiod_stability = DG$sp_stab,
    turnover_proxy = as.numeric(DG$r0_full$turnover_annual),
    post_neutralization_ic = DG$ic_neu,
    deflated_sharpe_ratio = 0.000,
    deflated_sharpe_note = "n_trials=7 사전등록 열거 기준 진단치. selection_type=diagnostic_no_argmax 이므로 게이트 부적용(measurement-graduation §3).",
    alpha_inheritance_cor = IH$inh_mean,
    alpha_inheritance_note = sprintf("STR_1715 base score_eff 대비 월별 횡단면 Spearman 평균 %.4f (n=272월) · top-25 이름 중복 %.2f/25. 문턱 0.95 PASS. ⚠ base 는 저장 파생 패널(production_parity 미검증) — 상속 판별 진단 전용, book-marginal 주장 불가.", IH$inh_mean, IH$top25_overlap),
    alpha_discovery_count = 1L
  ),
  selection_objective = "canonical_port_t",

  challenge_flags = c(
    "[F3 귀속 — 사전등록 규칙 발동] 틸트 단독 arm(A, 섹터 내 무작위 20시드) PORT_t 평균 -0.889(λ=0.5)/-1.163(λ=1.0), 짝 통제 A0 -1.039 → 인플레 틸트 단독 알파 없음. 결합-종목선택 증분 +1.094%/yr(t 1.07)·+1.369%/yr(t 0.98) 비유의, 플라시보 백분위 80.5%/71.0%(95분위 미달). ⇒ **결합 성과를 인플레 층에 귀속 금지. 알파는 종목선택(층3) 것이다.**",
    "[★검정력 라벨 — 소비면 종료 근거 아님] 층-증분의 관측/필요 비 = 0.46(λ=0.5)/0.39(λ=1.0), verdict_with_power = INCONCLUSIVE_BAR_RESTATES_T (implied_t 2.34/2.50 = t 검정 재진술 구간). FQ-172 비대칭 규약에 따라 '인플레 층 기각' 라벨을 발동하지 않는다 — config-scoped 미확립이며 부활 조건은 next_probes 참조.",
    "[HARD 미달] canonical PORT_t 2.479(층3 전창) / 1.746(층3 공통창) / 1.399(결합 λ=1.0 공통창) 전건 < 2.95. 자본 자격 주장 없음 — 상신 자격도 미충족.",
    "[★설계 스케일 수정 — No Silent Override 고지] 승계 가설의 문자 그대로의 exp(λ·β_s·infl) 는 λ∈{0.5,1.0} 에서 산술적으로 불활성(25슬롯 중 교체 0인 달 60.8~65.6%). 판정판을 scale-only 정규화 β/sd 로 고정하고(부호 보존율 1.0000) 문자 그대로 판도 병기 측정(PORT_t 1.062/1.066, 증분 -0.05%/yr). 근거·전후 수치 = prereg_amendment_1.json. 승계 mechanism/falsification/regime_scope 는 무수정.",
    "[★진단 오용 자가 적발·수리] 초판은 scores_dt 에 선택 25종만 실어 canonical 의 diag_ew_universe 벤치가 포트 자신의 gross 가 됐다(active = -비용 → PORT_t -53~-66). 전-유니버스 점수판으로 수리, cap-w 본판정 parity 차 0.00e+00 확인. 수리 후 EW-유니버스 진단 = R0 +3.001 / B +2.505 / C_l0.5 +2.697 / C_l1.0 +2.621 (공통창), R0 전창 +3.126.",
    "[★dual-basis 라벨] cap-w(권위)에서는 전건 HARD 미달이나 EW-유니버스 진단에서는 R0 가 3.00~3.13 으로 2.95 를 넘는다. cap-tier 분해상 보유의 91%가 OTHER(31위 밖)이라 v8.3 M2 가 문서화한 **cap-w 벤치 구성 미스매치** 형태에 정확히 해당한다. 진단은 비바인딩 — 판정은 cap-w 유지하되 screen_route 재분류 검토 대상으로 부기.",
    "[감쇠] 성장 합성 IC 부기간: 2003-2014 0.0406(t 5.22) → 2015-2019 0.0102(t 1.12) → 2020-2026 0.0148(t 1.63). post2017 EW-대비 t 1.63. 전창 우세가 초기 구간에 집중된다.",
    "[구조 손실] 섹터 정원 구조 자체(B − R0)가 -2.986%/yr (t -1.35). 즉 '섹터 대표성 배분'은 top-25 성장 단순 선별 대비 비용이며, 틸트가 그 중 1.1~1.4%p 를 되돌리는 형태다. 논문식 섹터-우선 구조가 KR 25종 제약에서 불리하다는 실측.",
    "[RF-A2 유사] composite(결합 설계)가 baseline(R0 단순 top-25) 대비 개선이 아니라 **악화**(1.399 vs 1.746). Red Flag 규칙의 '개선 <5%' 보다 강한 형태 — 조립층을 알파 근거로 쓸 수 없다.",
    "[창 불일치 고지] 결합 arm 공통창 = 209개월(2009-03~2026-07, β_s burn-in 구속). 승계 설계 문서의 '2003~ 280개월'은 T5YIE 원계열 기준이었고 expanding z 36개월 + β 36개월 burn-in 을 반영하면 실제 창은 이렇게 짧다. 헌법 고정창 2005~ 와도 다르다.",
    "[컨센서스 same-day] 3종 전부 lag_rule 'Date <= sig_d'. offset 스캔 t0/t1 = 2.62 (13.264 vs 5.054) — 동시성 상관이 실재하므로 이 계열을 쓰는 후속 라운드는 반드시 forward 정렬을 실증할 것.",
    "[C01_SUE 중복] registry dedup 상 C01_SUE = DUPC-005 redundant(canonical C05_ESCR, cor 0.990). 3종 pairwise Spearman 은 낮으나(C01~C02 0.074·C01~M26 0.058·C02~M26 0.178) 동일 클러스터 canonical 로의 교체가 next_probe 대상.",
    "[유동성 근사] 본 라운드는 20거래일 평균 mean(Close*Vol) 을 adv 로 썼다(repo 표준 canonical 경로의 단일일 Vol0*Close0 근사보다 엄격). 두 정의의 차이는 미측정 — 비교 인용 시 정의 라벨 확인 필요.",
    "[대안 보관 — 승계] 종목-레벨 β_i 직접 랭킹 / 오버레이 소비면 / KR_CPI 단독 단순판 (alpha_hypothesis.json challenge_flags 승계)",
    "[★인프라 결함 발견 — 본 패키지 결함 아님] schema.json ast_node 와 02_Infrastructure/ast/ast_verify.py 의 리프·연산자 방언이 갈라져 있다. ①리프: schema 는 {\"leaf\":\"<factor_id>\"} 를 정본으로 두는데(system prompt 예시·기존 v1.1 패키지 전부 이 형태) ast_verify 는 leaf 값을 *종류*(FIELD/REGISTRY/...)로 읽어 '알 수 없는 리프 종류'로 반려한다. ②연산자: schema enum 의 DIV_GUARD/CS_ZSCORE/CS_WINSORIZE/CS_NEUTRALIZE/CS_DEMEAN/TS_DELTA 가 ast_verify 의 DIV/ZSCORE/WINSORIZE/NEUTRALIZE/DEMEAN/DELTA 와 이름이 다르다. 실증: 기존 WT-D20260802_003 도 동일하게 FAIL_CONTRACT(leaf_count 1 에서 순회 중단). ALB-005/006 과 같은 계약 표면 분열 계통이며 ast_spec_gate 가 FAIL_CONTRACT 를 non-block 으로 둔 덕에 드러나지 않고 있었다. 본 패키지는 저장소 정본 방언(기존 패키지와 동일)을 따랐다."
  )
)

write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA, null = "null")
say("발행: %s/alpha_package.json (%.1f KB)", MB, file.size(file.path(MB,"alpha_package.json"))/1024)

## ── alpha_validation.json ──
val <- list(
  wt_id = "WT-D20260809_004", fq_id = "FQ-173", as_of = "2026-08-09",
  metric_type = "canonical_screen",
  capital_claim = FALSE, governor_invoked = FALSE,
  vintage = P$vintage,
  measurement_order_followed = c("①검정력 바(a2)", "②사전등록(preregistration.json + amendment_1)",
                                 "③층 분해 F3(a5)", "④결합/스트레스/플라시보(a6)"),
  power_bar = list(
    screen_sd_reference = 0.0394,
    required_annual_pct = list(n284 = 7.014, n246 = 7.536, n209 = 8.137),
    port_t_2p95_required_annual_pct_n209 = 12.06,
    confirmatory_external_sd = list(lambda0.5 = S$pw$`l0.5`$sd_ext, lambda1.0 = S$pw$`l1.0`$sd_ext),
    confirmatory_required_annual_pct = list(lambda0.5 = S$pw$`l0.5`$required_annual_pct,
                                            lambda1.0 = S$pw$`l1.0`$required_annual_pct),
    observed_over_required = list(lambda0.5 = S$pw$`l0.5`$ratio, lambda1.0 = S$pw$`l1.0`$ratio),
    verdict = list(lambda0.5 = S$pw$`l0.5`$verdict, lambda1.0 = S$pw$`l1.0`$verdict)
  ),
  pit = list(
    offset_scan = list(offset_plus1_ic = 0.0270, offset_plus1_t_nw3 = 5.054,
                       offset0_ic = 0.0989, offset0_t_nw3 = 13.264, ratio = 2.62,
                       reading = "same-day 컨센서스의 동시성 상관 실재. 본 라운드는 offset+1 만 소비."),
    assert_overlay_pit = "5축 HARD PASS (T5YIE / KR_CPI·Copper M-2 / 성장팩터 / β_s / adv20)",
    violation_injection_test = "PASS — 컷오프를 홀딩월 시작 이후로 주입 시 검사기 발화 확인",
    adv_floor_on_emitted_panel = list(min_adv20 = 2.003e8, threshold = 2e8, pass = TRUE)
  ),
  falsification_results = list(
    primary_beta_sign = list(hit_rate = 0.649, hit_rate_stride12 = 0.638, n = 1919L,
      binom_p = 0.0005, ci95 = c(0.559, 0.712), threshold = 0.50, verdict = "PASS",
      asymmetry = "음(-) 예측 5섹터 전건 통과 / 양(+) 예측은 철강 0.799·화학 0.732 만 통과, 에너지 0.434·상사자본재 0.105 반대",
      per_sector = L$persec),
    F1_lag1 = list(retention_l0.5 = 0.84, retention_l1.0 = 1.20, threshold = 0.50, verdict = "PASS",
      caveat = "base 증분 자체가 비유의 — 통과의 정보량 낮음"),
    F2_beta_stability = list(flip_rate_predicted = 0.234, flip_rate_all = 0.209, threshold = 0.30,
      verdict = "PASS",
      overlapping_window_evidence = "예측 섹터 β 평균 t: NW60(정본) vs NW3(오용) = 화학 3.14/5.06 · 철강 3.43/7.97 · 상사자본재 -4.38/-9.63 · 통신 -3.52/-7.59 (1.6~2.3배 부풀림)"),
    F3_attribution = list(
      tilt_alone_port_t = list(A0_base_random = -1.039, A_l0.5 = -0.889, A_l1.0 = -1.163,
                               seed_sd = c(0.471, 0.525, 0.325), n_seeds = 20L),
      increment_c_minus_b = list(l0.5 = list(annual_pct = 1.094, t_nw3 = 1.07, sd_monthly = 0.0109),
                                 l1.0 = list(annual_pct = 1.369, t_nw3 = 0.98, sd_monthly = 0.0156)),
      structure_cost_b_minus_r0 = list(annual_pct = -2.986, t_nw3 = -1.35),
      verdict = "틸트 단독 무효 ∧ 증분 비유의 → 인플레 층 제외, 종목선택 알파로 재라벨 (사전등록 규칙 그대로)"),
    F4_placebo = list(block_judged = 12L, draws = 200L,
      l0.5 = list(observed_annual_pct = 1.094, placebo_mean = mean(pl05$ann), placebo_sd = sd(pl05$ann),
                  percentile = 80.5, p95 = as.numeric(quantile(pl05$ann, .95))),
      l1.0 = list(observed_annual_pct = 1.369, placebo_mean = mean(pl10$ann), placebo_sd = sd(pl10$ann),
                  percentile = 71.0, p95 = as.numeric(quantile(pl10$ann, .95))),
      block_sensitivity_diagnostic_only = list(b6_pct = 79.0, b24_pct = 82.0),
      verdict = "95분위 미달 — 단 검정력 조건 미충족이라 '기각' 라벨 미발동 (INCONCLUSIVE)")
  ),
  arms_common_window_209m = list(
    window = "2009-03-31 ~ 2026-07-31 (β_s burn-in 구속)",
    R0_growth_only = list(port_t = 1.746, p = 0.0807, ir = 0.464, alpha_ann = 0.0841, net_sr = 0.464, to = 14.21),
    B_lambda0 = list(port_t = 1.090, ir = 0.266, alpha_ann = 0.0668, to = 15.20),
    C_combined_l0.5 = list(port_t = 1.299, ir = 0.328, alpha_ann = 0.0776, to = 15.21),
    C_combined_l1.0 = list(port_t = 1.399, ir = 0.363, alpha_ann = 0.0788, to = 14.89),
    Craw_literal_l0.5 = list(port_t = 1.062), Craw_literal_l1.0 = list(port_t = 1.066),
    no_argmax = "어떤 arm 도 챔피언으로 승격하지 않음. selection_type = diagnostic_no_argmax."
  ),
  layer3_full_window_284m = list(
    window = "2002-12-30 ~ 2026-07-31 · ★공통창 수치와 병렬 비교 금지",
    port_t = 2.479, ir = 0.558, alpha_ann = 0.0838, net_sr = 0.558, to = 13.55),
  dual_basis_diagnostic = list(
    binding = FALSE, metric_type = "canonical_screen_diag",
    ew_universe_common_window = list(R0 = 3.001, B = 2.505, C_l0.5 = 2.697, C_l1.0 = 2.621),
    ew_universe_post2017_t = list(R0 = 1.63, B = 1.65, C_l0.5 = 1.05, C_l1.0 = 0.95),
    ew_universe_oos_approx = list(R0 = 0.549, B = 0.964, C_l0.5 = 0.686, C_l1.0 = 0.833),
    ew_universe_full_window_R0 = list(port_t = 3.126, post2017_t = 1.63, oos_approx = 0.642),
    cap_tier_weight_share = list(MEGA = 0.040, MID = 0.055, OTHER = 0.906, basis = "R0 공통창"),
    label = "cap-w FAIL ∧ EW-대비 생존 → v8.3 M2 '벤치 구성 미스매치 가능' 라벨. 판정 권위는 cap-w 불변."
  ),
  advisory_battery = list(
    rank_ic_full = DG$ic_full$rank_ic, icir_full = DG$ic_full$icir, t_nw3_full = DG$ic_full$t_nw3,
    rank_ic_common = DG$ic_win$rank_ic, t_nw3_common = DG$ic_win$t_nw3,
    subperiod = DG$sp, monotonicity = DG$mono,
    decile_d10_minus_d1_annual_pct = 10.61,
    post_neutral_ic = DG$ic_neu, post_neutral_retention = DG$ic_neu/DG$ic_full$rank_ic,
    pairwise_spearman = list(C01_C02 = 0.074, C01_M26 = 0.058, C02_M26 = 0.178)
  ),
  hard_gate_status = list(
    port_t_2p95 = "FAIL (max 2.479, 층3 전창 cap-w)",
    oos_retention = "alpha 단계 미산출 — forge-authoritative. 진단 근사(EW-basis) 0.549~0.964",
    calmar = "alpha 단계 미산출 — forge-authoritative",
    conclusion = "graduation 미충족. 상신 자격 없음. 자본 자격 주장 없음."
  ),
  next_probes = list(
    list(id = "NP-1", probe = "층3 단독(성장 합성)을 cap-w 가 아니라 EW-유니버스 기준으로 재판정 — R0 가 3.00~3.13 으로 문턱을 넘고 보유의 91%가 OTHER tier 다. cap-tier 조건부 재분류(MID/OTHER 국소화)가 진짜 알파인지 벤치 아티팩트인지 분리.", owner = "open"),
    list(id = "NP-2", probe = "감쇠 진단: 성장 합성 IC 가 2015 이후 1/4 로 축소. 컨센서스 커버리지 확대(월평균 커버 724→2629)가 원인인지, 재료 소진인지 — 커버리지-정합 부분표본으로 분리.", owner = "open"),
    list(id = "NP-3", probe = "인플레 틸트의 부활 조건: 본 라운드는 '무효'가 아니라 '미확립'(관측/필요 0.39~0.46). 검정력을 얻는 경로 = ①창 확장(β burn-in 을 36→24 로 낮춰 +36개월) ②증분 분산 축소(정원 대신 종목-레벨 β_i 랭킹 = 승계 후보 3) ③사건 조건부(월<-10% 등 심한 국면에서만 — 라벨 자격은 사건 정의에 조건부라는 2026-08-08 실측).", owner = "open"),
    list(id = "NP-4", probe = "β_s 패널 자체의 소비면: 예측 부호 일치율 0.649·부호 안정 0.234 로 β_s 는 실재하는 섹터 민감도 지도다. 선택 알파로는 실패했으나 ①위험모델 섹터 노출 예산 ②오버레이 입력 ③유니버스 필터 면에서 미측정 — FQ 등재 대상.", owner = "open"),
    list(id = "NP-5", probe = "C01_SUE 를 dedup canonical C05_ESCR 로 교체한 3종 합성 재측정 (DUPC-005 redundant 해소).", owner = "open"),
    list(id = "NP-6", probe = "양(+) 예측 실패 2섹터(에너지 β≈0·상사자본재 β<0) 의 기전 진단 — KR '에너지' 섹터는 정유(원가=원유)라 전가력이 아니라 재고효과가 지배할 수 있다. 채널 재정식화 후보.", owner = "open")
  )
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA, null = "null")
say("발행: %s/alpha_validation.json (%.1f KB)", OUT, file.size(file.path(OUT,"alpha_validation.json"))/1024)

## lineage — ★alpha_package.json write 직후 (L-194 순서)
lu <- "02_Infrastructure/worktask/lineage_utils.R"
if (file.exists(lu)) {
  source(lu)
  tryCatch({
    record_package_lineage(task_id = "WT-D20260809_004", package_type = "alpha_package",
      method_selected = "F1 growth consensus composite (C01_SUE+C02_EPS_Chg_1m+M26_Revenue_Mom, EW z) + 인플레 틸트 조립층(층3 귀속 판정)",
      input_file_paths = c(".cache/rawdata.parquet", ".cache/fred_macro.parquet",
                           ".cache/ecos_bond_rates.parquet", ".cache/factor_db/factor_db_202607.parquet"))
    say("lineage 기록 완료")
  }, error = function(e) say("lineage 기록 실패: %s", conditionMessage(e)))
} else say("lineage_utils.R 부재 — lineage 미기록")
