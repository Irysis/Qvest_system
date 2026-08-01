# =============================================================================
# emit_alpha_package_r2.R — WT-D20260802_001 R2 / FQ-073
#   AST v1.1 3층 alpha_package (R2 판) + alpha_validation + lineage
#   R1 판은 alpha_package_r1.json / challenge_note_r1.md / alpha_validation_r1.json 로 보존.
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_001")
`%||%` <- function(a, b) if (is.null(a)) b else a

RES <- fromJSON(file.path(OUT, "fq073_r2_results.json"), simplifyVector = FALSE)
DIA <- fromJSON(file.path(OUT, "fq073_r2_diagnostics.json"), simplifyVector = FALSE)
ADV <- fromJSON(file.path(OUT, "fq073_r2_adversarial.json"), simplifyVector = FALSE)
METE <- fromJSON(file.path(OUT, "fq073_export_exposure_chapter_meta.json"), simplifyVector = FALSE)
METM <- fromJSON(file.path(OUT, "fq073_export_materiality_meta.json"), simplifyVector = FALSE)
astG1 <- fromJSON(file.path(OUT, "ast_R2_G1_mat_surprise.json"), simplifyVector = FALSE)
astG5 <- fromJSON(file.path(OUT, "ast_R2_G5_mat_sue_sm6.json"), simplifyVector = FALSE)

PRIM <- "R2_G1_mat_surprise"
r1 <- RES$full_window[[PRIM]]
g5 <- RES$full_window$R2_G5_mat_sue_sm6
g4 <- RES$full_window$R2_G4_mat_sue_sm3
b0 <- RES$full_window$B0_R1_F1

P <- as.data.table(read_parquet(file.path(OUT, "alpha_scores_R2_G1_mat_surprise.parquet")))[!is.na(value)]
last_d <- P[, max(Date)]
LV <- P[Date == last_d][order(-value)]
alpha_vector <- as.list(setNames(round(LV$value, 6), LV$Ticker))
cov_m <- P[, .N, by = Ticker][, setNames(pmin(1, N / 120), Ticker)]
dratio <- DIA$effective_cross_section$R2_G1_mat_surprise$distinct_ratio
conf <- vapply(LV$Ticker, function(tk) {
  round(max(0, min(1, 0.5 * as.numeric(cov_m[[tk]] %||% 0.5) + 0.5 * dratio)), 4)
}, numeric(1))
confidence_vector <- as.list(setNames(conf, LV$Ticker))

# ── method shopping log (전 변형, 사전선언 귀속설계) ────────────────────
mech <- c(
  R2_G1_mat_surprise = "PRIMARY(P1) — materiality x 서프라이즈. 균등배분을 경제적 노출 크기로 재척도. cap-tier 판별 담당",
  R2_G1c_matcred_surprise = "대조 A — credibility 보정 materiality min(R,1/R). R_h>1(매핑이 흐름을 설명 못함)을 감쇠",
  R2_G2_sue = "대조 B — 변동성 표준화만. R1 진단(효과가 고변동 니치 버킷 꼬리에 몰림)의 직접 대조",
  R2_G3_mat_sue = "결합 — materiality x SUE (2x2 귀속설계의 both-on 칸)",
  R2_G4_mat_sue_sm3 = "P2 — 3M 평활. R1 회전율 1288%/yr 의 제약(1100%) 초과 해소 시도",
  R2_G5_mat_sue_sm6 = "P2 사다리 2단 — 6M 평활. 고빈도 성분이 본체인지 판별")
method_log <- lapply(names(mech), function(fid) {
  v <- RES$full_window[[fid]]; cw <- RES$common_window$results[[fid]]
  list(name = fid,
       canonical_port_t_nw_lag3 = v$portfolio_alpha_t_nw_lag3,
       common_window_port_t = cw$portfolio_alpha_t_nw_lag3,
       ew_universe_port_t = v$ew_universe_port_t,
       turnover_annual = v$turnover_annual,
       turnover_constraint_pass = isTRUE(v$turnover_annual <= 11.0),
       n_months = v$n_months,
       cap_tier_weight_share = v$cap_tier_weight_share,
       selected = identical(fid, PRIM), mechanism_note = mech[[fid]])
})

pkg <- list(
  task_id = "WT-D20260802_001",
  round = "R2",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",

  hypothesis = list(
    statement = paste0(
      "R1 은 HS4 산업 수출 성장을 그 버킷에 매핑된 모든 기업에 균등 배분했다. ",
      "그 결과 신호 강도가 기업의 경제적 노출이 아니라 버킷의 변동성에 지배됐다는 것이 R1 진단이다. ",
      "따라서 각 기업의 HS4 노출을 **경제적 크기(수출 의존도)**로 재척도하면 ",
      "① 선택이 고변동 니치 버킷에서 실질 수출기업으로 이동하고 ",
      "② 그 이동이 cap-tier 분포에 나타난다 — 이것이 R1 의 소형주 국소화가 ",
      "크로스워크 아티팩트인지 수출 신호 자체의 성질인지를 가른다."),
    mechanism = list(
      agent = paste0("국내외 sell-side 애널리스트 및 기관 트레이더 — KR 제조사 커버리지에서 분기 실적 공시",
                     "(45일+ 지연)를 실적 갱신의 주된 앵커로 삼는 참여자군. 월별 통관 수출은 그보다 빠르나 ",
                     "HS코드-기업 귀속표가 공개 존재하지 않아 대부분 소비하지 않는다."),
      friction = paste0("① 귀속 비용 — HS 10자리 14,153개를 사업보고서 제품 텍스트와 매핑해야 하며 그 시장가격이 ",
                        "TRASS/Aicel 유료 벤더의 존재로 실증된다. ② KR 공매도 제약으로 수출 부진의 negative 정보는 ",
                        "가격 반영이 비대칭. ③ 월간 이산 공표 — 정보가 갱신 시점에 몰린다. ",
                        "R2 추가: ④ 노출 크기 추정 비용 — 산업 수출을 개별 기업 매출로 환산하려면 ",
                        "부문 매출·수출 의존도가 필요하고 이는 표준 필드가 아니라 서술문에 흩어져 있다."),
      path = paste0("데이터월 M 수출 서프라이즈 x 기업 수출의존도 → M+1월 15일 1차 현행화 공표 → ",
                    "M+1 거래월말 스코어 배치 → 홀딩월 M+2 동안 컨센서스 영업이익 상향과 실적 발표로 가격 반영. ",
                    "의존도 가중은 pass-through 크기(ΔRevenue/Revenue ≈ 수출의존도 x 수출성장)를 직접 표현한다.")),
    falsification = paste0(
      "materiality 가중 상위 5분위 종목의 후속 3M 컨센서스 영업이익(op_profit_fy1, field_dictionary ",
      "C-CONSENSUS-QW)이 하위 5분위 대비 유의(t>=2) 상향되지 않으면 기전 기각. ",
      "R2 강화 조건: materiality 가 실제 경제적 노출을 잡는다면 이 링크는 R1 무가중(t=1.969) 대비 ",
      "**강해져야** 한다. 약해지면 materiality 구성 자체가 반증된다."),
    regime_scope = list(
      holds_in = list("neutral", "expansion"),
      weakens_or_reverses_in = list("crisis", "krw_shock"),
      boundary_rationale = paste0(
        "수출액은 USD 표시다. 급격한 환율 국면에서는 USD 수출 증가가 KRW 실적 증가와 괴리되어 신호-실적 ",
        "연결이 끊긴다. 위기 국면은 유동성 청산이 펀더멘털 정보를 압도한다. 경계는 '통관 통계의 표시통화'와 ",
        "'청산 우위'라는 메커니즘 속성에서 도출된 것이지 사후 성과 관찰이 아니다. ",
        "다만 R1·R2 실측 모두 2020-22(COVID) 부기간이 유일한 양(+) 구간으로 이 경계와 어긋난다 — CF-05 참조."))),

  factors = list(
    list(factor_id = "R2_G1_mat_surprise", ast = astG1, role = "core_signal",
         restatement_exposure = 2,
         restatement_note = paste0("STORED_SCORE 리프 2종(수출노출·materiality)이 모두 관세청 원천 파생. ",
           "관세청은 '매월 15일경 전월까지 자료를 전체 현행화, 개정 종료일 없음' — 저장소 내 최고 수준 ",
           "restatement 원천. ast_verify 는 ALB-003 수리 이후 미등재 리프를 보수적으로 ",
           "WARN_RESTATEMENT 로 표시한다(R1 은 조용히 통과했다).")),
    list(factor_id = "R2_G5_mat_sue_sm6", ast = astG5, role = "turnover_constrained_variant",
         restatement_exposure = 2,
         restatement_note = "동일 리프 2종 + 6M 평활. Production Constraints 회전율 1100%/yr 충족(508%).")),
  combination_rule = "single_factor",
  verdict = "designed",

  pit = list(sig_date = "2026-07-31", decision_ts = "2026-07-31"),
  falsification = list(
    list(field = "C-CONSENSUS-QW",
         observation = paste0("materiality 가중 Q5 종목의 후속 3M op_profit_fy1 컨센서스 개정이 Q1 대비 ",
                              "유의(t>=2) 상향되지 않으면 기전 기각. 추가로 R1 무가중(t=1.969) 대비 강화되어야 한다."),
         executed = TRUE,
         result_t_stat_r1_unweighted = DIA$falsification$B0_R1_F1$H63d$t_stat,
         result_t_stat_r2_materiality = DIA$falsification$R2_G1_mat_surprise$H63d$t_stat,
         result_spread_logrev = DIA$falsification$R2_G1_mat_surprise$H63d$q5_minus_q1_logrev,
         verdict = DIA$falsification$verdict)),
  ast = astG1,

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "STORED_SCORE:fq073_export_exposure",
           availability_rule = "manual_export/derived — avail_ts = data_ym(M)+1개월 15일. 패널 내 avail_ts 컬럼이 권위(암묵 0 아님)",
           restatement_prone = TRUE, vintage_available = FALSE),
      list(leaf = "STORED_SCORE:fq073_export_materiality",
           availability_rule = paste0("동일 avail 규약(M+1/15). 분모 Revenue 는 fundamental_dart Factor_Date=익년 3/31(C4) ",
                                      "이며 데이터월 말 기준으로만 조회 = avail_ts 보다 항상 이른 보수적 컷"),
           restatement_prone = TRUE, vintage_available = FALSE)),
    verdict = "warn_restatement",
    verdict_rationale = paste0(
      "타이밍(C5)은 clean — 버퍼 14~17일 실측, assert_overlay_pit HARD PASS, lag1 스트레스 전 변형 NO_INFLATION. ",
      "그러나 ① customs 개정판 기반(first-release 소급 복원 불가) ② crosswalk static_current(2024-25 사업보고서 ",
      "1 vintage 를 전 역사 귀속 = C1/C3) 두 노출이 R1 그대로 잔존한다. R2 는 이 노출을 해소하지 않았다 ",
      "— P3(vintage 크로스워크)는 미착수. 따라서 clean 선언 불가, gate_eligible=FALSE 승계.")),

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_001/alpha_scores.parquet",

  factor_specs = list(list(
    factor_family = "Fundamental_Flow_NonReturn",
    proxy = "customs_HS_export_surprise x estimated_export_dependence",
    formula = paste0("CS_ZSCORE(CS_WINSORIZE(S x CLIP(M,0,1), 0.02)); ",
                     "S = G - TS_MEAN(G,12), G = LOG(x) - LOG(TS_LAG(x,12)), x = Σ_h w_ih·Flow_h; ",
                     "M = Σ_h w_ih·[Flow_h(TTM,USD)·FX / Σ_j Rev_j·w_jh]"),
    lag_rule = "data_ym M -> usable M+1/15 -> score M+1 month-end -> holding M+2 (buffer 14~17d)",
    winsorization = "cross-sectional 2% both tails",
    neutralization = "none",
    economic_rationale = paste0("1차 pass-through: ΔRevenue/Revenue ≈ 수출의존도 x 수출성장. ",
      "의존도 M 은 Rev_i 가 소거되는 scale-free 분수라 시총에 기계적으로 단조가 아니다 ",
      "(시총 단조 가중치를 쓰면 cap-tier 판별이 순환논증이 되므로 의도적으로 배제)."),
    weight_theta = 1.0,
    redundancy_cluster_id = "nonreturn_customs_export_fq073",
    source = "new_designed",
    references = list("FQ-073 frontier queue", "PIT_plan_fq073.md (2026-07-25)",
                      "WT-D20260802_001 R1 alpha_package_r1.json"))),

  diagnostics = list(
    canonical_port_t_nw_lag3 = r1$portfolio_alpha_t_nw_lag3,
    canonical_port_t_pvalue = r1$p,
    canonical_n_months = r1$n_months,
    metric_type = "canonical_screen",
    rank_ic = DIA$rank_ic$R2_G1$rank_ic,
    icir = DIA$rank_ic$R2_G1$icir,
    harvey_t_stat = DIA$rank_ic$R2_G1$ic_t_stat,
    monotonicity = NA,
    subperiod_stability = DIA$subperiod_port_t$R2_G1,
    turnover_proxy = r1$turnover_annual,
    post_neutralization_ic = NA,
    information_ratio = r1$information_ratio,
    net_sr = r1$net_sr,
    dual_basis = list(
      cap_w_port_t = r1$portfolio_alpha_t_nw_lag3,
      ew_universe_port_t = r1$ew_universe_port_t,
      cap_tier_weight_share = r1$cap_tier_weight_share,
      cap_tier_contrib_annualized = r1$cap_tier_contrib_annualized,
      base_rate = RES$base_rate,
      verdict = paste0("★R2 핵심 — cap-tier 는 base rate 대비로 읽어야 한다. K200∪KQ150 에서 ",
        "MEGA=10·MID=20 종목은 정의상 고정이므로 OTHER base ≈ 0.915(유니버스)·0.909(스코어풀)다. ",
        "R1 의 OTHER 0.889 는 base 아래(lift 0.978)이고 MEGA 0.0595 는 base 위(lift_pool 1.384 / ",
        "lift_univ 2.097) — 즉 R1 은 '소형주 국소화'가 아니라 오히려 약한 대형주 초과편입이었다. ",
        "materiality 재척도 후 OTHER 0.915(lift 1.007)·MEGA 0.0442(lift_pool 1.030) 로 ",
        "**대형 tier 쪽 이동은 없었고 오히려 base 중립으로 되돌아갔다**.")),
    r2_variant_table = RES$full_window,
    common_window_table = RES$common_window,
    tier_lift_table = RES$tier_table,
    effective_cross_section = DIA$effective_cross_section,
    materiality_profile = DIA$materiality_profile,
    falsification_test = DIA$falsification,
    falsification_verdict = DIA$falsification$verdict,
    dynamic_pit = DIA$dynamic_pit,
    label_direction_cor = 1.0,
    adversarial_measurements = ADV,
    ast_verify = list(
      R2_G1_mat_surprise = "WARN_RESTATEMENT", R2_G1c_matcred_surprise = "WARN_RESTATEMENT",
      R2_G2_sue = "WARN_RESTATEMENT", R2_G3_mat_sue = "WARN_RESTATEMENT",
      R2_G4_mat_sue_sm3 = "WARN_RESTATEMENT", R2_G5_mat_sue_sm6 = "WARN_RESTATEMENT",
      leaf_count_range = "5~9 (R1 F1 은 leaf_count=0 으로 빈 PASS 였다 — ALB-007 수리 후 실검증)",
      violations = 0, contract_failures = 0,
      parity_unverified_count = "5~9 (정직 선언 false — ALB-002 수리로 통과+플래그)",
      unmapped_restatement_count = "5~9 (field_map 미등재 STORED_SCORE — ALB-003 수리로 표면화)",
      dialect_args_used = TRUE,
      note = "R1 대비 변화: 단일 방언(컴파일러 트리 그대로)으로 검증. R1 의 FAIL_CONTRACT 5건은 전부 해소."),
    n_iterations = 6, selection_type = "chain",
    deflated_sharpe_ratio = NA,
    dsr_note = paste0("6 변형은 사전선언 귀속설계(materiality on/off x 변동성표준화 on/off 의 2x2 + ",
      "평활 사다리 2단)이며 argmax 로 최종안을 고르는 sweep 이 아니다 — measurement-graduation §3 상 ",
      "selection_type=chain, DSR 게이트 부적용. 더 결정적으로 **어떤 변형도 승격 후보로 제출하지 않는다** ",
      "(전 변형 PORT_t < 2.95, 최고치도 p=0.891). 따라서 선택 편향이 개입할 판정 자체가 없다. ",
      "n_trials=6 은 사후 감사용으로 기록.")),

  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,

  challenge_flags = list(
    list(id = "R2-CF-01", severity = "HIGH",
         flag = paste0("★라운드 전제 자체가 base rate 오류 — R1 의 'OTHER 88.9% = 소형주 국소화' 판독은 ",
           "K200∪KQ150 의 OTHER base 0.915(정의상 MEGA 10 + MID 20 고정)와 대조하지 않은 결과다. ",
           "실제로 R1 은 MEGA lift 2.097(유니버스 대비)로 약한 대형주 초과편입이었다. ",
           "R2 는 이 오독을 정정한다 (self-adversarial ACCEPT).")),
    list(id = "R2-CF-02", severity = "HIGH",
         flag = paste0("materiality 는 **버킷 수준**이라 버킷 내 동점을 깨지 못한다. M_i = Σ_h w_ih·R_h 에서 ",
           "Rev_i 가 소거되므로 단일-HS4 매핑 기업(180/315)끼리는 여전히 동일 스코어다. ",
           "실측 distinct_ratio 0.6439 → 0.6488(무변화). '5% vs 80% 노출' 구분은 버킷 간으로만 실현됐고 ",
           "버킷 내에서는 실현되지 않았다 — 이 라운드가 P1 을 절반만 집행했음을 인정한다 (ACCEPT).")),
    list(id = "R2-CF-03", severity = "HIGH",
         flag = paste0("반증 검정이 materiality 에 불리 — 링크1(수출→컨센 영업이익 상향) t 가 ",
           "R1 무가중 1.969 → R2 materiality 가중 0.744 로 **약해졌다**. materiality 가 실제 경제적 노출을 ",
           "잡았다면 강해져야 했다. 사전등록한 R2 강화 조건에 대한 명시적 반증 (ACCEPT).")),
    list(id = "R2-CF-04", severity = "MEDIUM",
         flag = paste0("변형 간 n_months 불일치(112 → 95)로 개선처럼 보일 수 있어 공통창(96개월 2018-08~2026-07) ",
           "재측정을 병기했다. 공통창에서도 B0 -1.398 → G5 +0.137 로 방향은 유지되나, ",
           "G5 의 p=0.891 은 '개선'이 아니라 '0 과 구분 불가'다 (REBUTTAL — 근거 병기).")),
    list(id = "R2-CF-05", severity = "MEDIUM",
         flag = paste0("G4(3M 평활)의 lag1 스트레스가 base(-0.767)보다 높다(+0.443, 인플레 -1.21). ",
           "누출 방향은 아니지만(누출이면 base > lag1) 선언한 'M+2 홀딩월 반영' 타이밍이 데이터와 맞지 않음을 시사. ",
           "메커니즘의 시점 주장은 미확립 상태로 남는다.")),
    list(id = "R2-CF-06", severity = "MEDIUM",
         flag = paste0("PIT 노출 R1 그대로 잔존 — crosswalk static_current(C1/C3) + customs 개정판 vintage + ",
           "C6 survivorship. R2 의 materiality 분모(Rev_j·w_jh)도 **같은 static 크로스워크 가중치**를 쓰므로 ",
           "노출이 해소가 아니라 승계된다. gate_eligible=FALSE.")),
    list(id = "R2-CF-07", severity = "MEDIUM",
         flag = paste0("M>1(수출의존도 정의 위반) 이 패널의 40.0% — 매핑된 상장사 매출로 흐름을 설명하지 못하는 ",
           "구간이 그만큼 넓다. CLIP(0,1)은 이를 '최대 의존도'로 saturate 시키는데, 오히려 귀속 실패 신호일 수 있다. ",
           "credibility 보정판(G1c, min(R,1/R))을 대조군으로 병기했고 결과는 더 나쁘다(-1.190). ",
           "어느 처리도 결론을 바꾸지 않는다 (PARTIAL — 인정 + 대조 실측 병기).")),
    list(id = "R2-CF-08", severity = "LOW",
         flag = paste0("FX(TTM 월평균 KRW/USD)는 횡단면 공통 스칼라라 랭킹에 무영향이나 CLIP 경계는 시간에 따라 ",
           "움직인다 — saturate 되는 기업 수가 환율에 약하게 의존한다. 영향 미측정.")),
    list(id = "R2-CF-09", severity = "INFO",
         flag = paste0("AST 계층 수리 검증 — R1 이 적립한 ALB-001/002/003/005/006/007 수리 후 첫 라운드. ",
           "6 스펙 전량 WARN_RESTATEMENT(통과+플래그), leaf_count 5~9(R1 F1 은 0 = 빈 PASS), ",
           "violations 0, contract_failures 0. 단일 방언으로 축소(두 벌 유지 폐지). ",
           "ast_sidecar live_with_ast 5 → 11.")),
    list(id = "R2-CF-10", severity = "INFO",
         flag = paste0("자기 적대검증 C2 는 실측으로 REBUTTED — 'cap-tier 가 안 움직인 건 크로스워크에 대형주가 ",
           "없어서'라는 반론은 틀렸다. MEGA 커버리지 0.625(월평균 7.73/10 종목 스코어 보유)로 OTHER(0.409)보다 ",
           "높다. 25 슬롯에 대형주를 넣을 여지가 실재하는데 선택되지 않았다."))),

  verdict_summary = list(
    result = "config_scoped_negative",
    lane = "LANE_UPPER_BOUND (static_current 매핑 + revised vintage)",
    gate_eligible = FALSE,
    p1_answer = paste0(
      "materiality 재척도 후에도 보유 cap-tier 는 대형 tier 로 이동하지 않았다 ",
      "(MEGA 0.0595 → 0.0442, OTHER 0.889 → 0.915). 다만 R1 의 'OTHER 88.9% = 소형주 국소화'라는 ",
      "전제 자체가 base rate 오류였다 — 스코어풀 OTHER base 는 0.909 이므로 R1 도 R2 도 tier 구성은 ",
      "base 근방이다. 따라서 정확한 판정은 '아티팩트냐 신호의 성질이냐'가 아니라 ",
      "**'수출 신호에는 애초에 cap-tier 를 움직일 횡단면 선택력이 없다'** 이다. ",
      "MEGA 커버리지 0.625(월 7.73종목)로 선택 여지는 실재했다."),
    p2_answer = paste0(
      "회전율 제약은 해소된다 — 3M 평활 712%/yr, 6M 평활 508%/yr 로 모두 1100% 이내. ",
      "평활이 신호를 죽이지 않았고 오히려 음(-)을 제거했다(PORT_t -1.708 → +0.137, EW-uni -1.605 → +1.446). ",
      "즉 R1 의 음수는 상당부분 고빈도 성분 + 비용의 산물이었다. 단 +0.137(p 0.891)은 알파가 아니라 0 이다."),
    statement = paste0(
      "본 config(월간 HS4 서프라이즈 x 수출의존도 재척도 x static_current 크로스워크 x top-25 cap-w EW ",
      "long-only x 15bps)에서 FQ-073 은 양(+)의 알파를 산출하지 않는다. R1 대비 실질 변화는 ",
      "①음수의 소멸(-1.708 → +0.137, 원인은 materiality 30% + 변동성표준화 + 평활) ",
      "②회전율 제약 충족 ③cap-tier 전제의 정정. 변하지 않은 것은 ",
      "①알파 부재(전 변형 |t| < 1.3, PORT_t 2.95 HARD 미달) ②firm-level 해상도(distinct_ratio 0.64 그대로) ",
      "③PIT 노출(C1/C3 static mix, C6, customs 개정) ④반증 검정 미지지(오히려 약화). ",
      "구조 판결 아님 — 미검 축은 next_probe 참조."),
    next_probe = list(
      list(id = "NP-R2-1", priority = "P1",
           probe = paste0("버킷 내 해상도 확보 — firm-level 수출 의존도 직접 추출. DART 사업보고서 '매출실적' ",
             "표의 수출/내수 행을 파싱해 기업별 수출비중 패널을 만든다. R1 probe 는 정규식 상한 18.4%(58/315, ",
             "중앙값 56.65%)를 확인했다. 이 축이 열려야 M 이 버킷 수준을 벗어나 firm-level 이 된다 ",
             "— 현재 distinct_ratio 0.64 의 천장이 여기다."),
           rationale = "R2-CF-02 가 확정한 구조적 병목. 정규화로는 절대 못 넘는다 = 데이터 축."),
      list(id = "NP-R2-2", priority = "P1",
           probe = paste0("P3 vintage 크로스워크 — pull_dart_products.py 가 이미 연도-파라미터화(FQ073_BGN/END)",
             "돼 있으므로 effective_from 다행 구조로 재구축. 현재 C1/C3 노출을 해소하면 gate_eligible 가 열리고, ",
             "'상한 lane 이 음수'라는 R1/R2 논증의 attenuating-noise 반론(R1 CF-02)도 판별 가능해진다."),
           rationale = "R2 는 P3 를 미착수로 남겼다. gate 자격의 전제."),
      list(id = "NP-R2-3", priority = "P2",
           probe = paste0("평활 6M 이 음수를 제거한 기전 규명 — 고빈도 성분이 (a) 비용 (b) 단기 반전 ",
             "(c) 버킷 변동성 중 무엇인가. gross(0bps) vs net 재측정 + 신호 자기상관 구조 + ",
             "월별 회전 기여 분해. 이 규명은 FQ-073 밖 다른 월간 flow 신호에 이식 가능한 지식이다."),
           rationale = "R2 최대 실측 변화(-1.708→+0.137)의 원인이 미귀속 상태."),
      list(id = "NP-R2-4", priority = "P2",
           probe = paste0("소비면 이식 — 수출 서프라이즈를 랭킹 팩터가 아니라 ①유니버스 필터 ",
             "(수출 급감 버킷 제외) ②monitoring tripwire(보유 종목의 수출 버킷 급변 경보) ",
             "③국면 입력(총수출 모멘텀 = macro overlay 후보)으로 소비. 횡단면 선택력이 없다는 것이 ",
             "시계열 정보가 없다는 뜻은 아니다."),
           rationale = "answer-principles 4호 소비면 7종 순회 — 랭킹 실패가 폐기 사유가 아니다."))))

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
cat("[emit-r2] alpha_package.json (R2) 저장\n")

val <- list(task_id = "WT-D20260802_001", round = "R2",
            generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            metric_type = "canonical_screen", lane = "LANE_UPPER_BOUND", gate_eligible = FALSE,
            selection_type = "chain", n_trials = 6,
            base_rate = RES$base_rate,
            factors = method_log,
            common_window = RES$common_window,
            tier_lift_table = RES$tier_table,
            diagnostics = DIA, adversarial = ADV,
            panel_provenance = list(export_exposure = METE, materiality = METM),
            ast_verify_verdicts = list(
              R2_G1_mat_surprise = "WARN_RESTATEMENT", R2_G1c_matcred_surprise = "WARN_RESTATEMENT",
              R2_G2_sue = "WARN_RESTATEMENT", R2_G3_mat_sue = "WARN_RESTATEMENT",
              R2_G4_mat_sue_sm3 = "WARN_RESTATEMENT", R2_G5_mat_sue_sm6 = "WARN_RESTATEMENT",
              violations = 0, contract_failures = 0,
              note = "R1 의 FAIL_CONTRACT 5건(production_parity_verified) 전량 해소 — ALB-002 수리 반영. leaf_count 5~9 로 실검증(R1 F1 은 0)."),
            graduation_hard_gates = list(
              portfolio_alpha_t_nw = list(required = 2.95,
                observed_canonical_primary = r1$portfolio_alpha_t_nw_lag3,
                observed_canonical_best_variant = g5$portfolio_alpha_t_nw_lag3,
                status = "FAIL", note = "forge-authoritative 아님 — canonical screen 실측. 승격 후보 제출 없음."),
              oos_retention = list(required = 0.7, observed = NA, status = "NOT_COMPUTED",
                                   note = "PORT_t 가 0 근방이라 forge 승격 미도달 — 산출 무의미"),
              calmar = list(required = 0.64, observed = NA, status = "NOT_COMPUTED")),
            production_constraints = list(
              turnover_annual_limit = 11.0,
              primary_G1 = r1$turnover_annual, G4_sm3 = g4$turnover_annual, G5_sm6 = g5$turnover_annual,
              verdict = "P2 충족 — 평활 3M/6M 변형이 제약 이내(712%/508%). R1(1288%)은 초과였다."))
write_json(val, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
cat("[emit-r2] alpha_validation.json 저장\n")

write_parquet(as.data.table(read_parquet(file.path(OUT, "alpha_scores_R2_G1_mat_surprise.parquet"))),
              file.path(OUT, "alpha_scores.parquet"))
cat("[emit-r2] alpha_scores.parquet 저장 (PRIMARY = R2_G1_mat_surprise)\n")

try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_001", package_type = "alpha_package",
    method_selected = "R2_G1_mat_surprise (AST v1.1, STORED_SCORE export exposure x materiality)",
    input_file_paths = c(
      file.path(OUT, "fq073_export_exposure_chapter.parquet"),
      file.path(OUT, "fq073_export_materiality.parquet"),
      ".cache/fundamental_dart.parquet", ".cache/ecos_krw_usd.parquet",
      "stage_artifacts/method_frontier/firm_level_scaffold/fq073/customs_hs_monthly.parquet",
      "stage_artifacts/method_frontier/firm_level_scaffold/fq073/firm_hs_crosswalk.parquet"))
  cat("[emit-r2] lineage 기록 완료\n")
}, silent = FALSE)
