# =============================================================================
# emit_alpha_package.R — WT-D20260802_001 / FQ-073
#   AST v1.1 3층 alpha_package + alpha_validation + lineage
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_001")
`%||%` <- function(a, b) if (is.null(a)) b else a

z   <- readRDS(file.path(OUT, "fq073_ast_results.rds"))
dg  <- readRDS(file.path(OUT, "fq073_diag_results.rds"))
DIA <- fromJSON(file.path(OUT, "fq073_diagnostics.json"), simplifyVector = FALSE)
FAL <- fromJSON(file.path(OUT, "fq073_falsification.json"), simplifyVector = FALSE)
MET <- fromJSON(file.path(OUT, "fq073_export_exposure_chapter_meta.json"), simplifyVector = FALSE)
r1  <- z$results$F1_export_surprise
ast1 <- fromJSON(file.path(OUT, "ast_F1_export_surprise.json"), simplifyVector = FALSE)

P1 <- as.data.table(read_parquet(file.path(OUT, "alpha_scores_F1_export_surprise.parquet")))
P1 <- P1[!is.na(value)]
last_d <- P1[, max(Date)]
LV <- P1[Date == last_d][order(-value)]
alpha_vector <- as.list(setNames(round(LV$value, 6), LV$Ticker))
# confidence: 매핑 해상도(동점 아님) + 데이터 커버리지 기반 [0,1]
cov_m <- P1[, .N, by = Ticker][, setNames(pmin(1, N / 120), Ticker)]
conf <- vapply(LV$Ticker, function(tk) {
  base <- as.numeric(cov_m[[tk]] %||% 0.5)
  round(max(0, min(1, 0.5 * base + 0.5 * 0.644)), 4)   # 0.644 = 유효 횡단면 distinct 비율
}, numeric(1))
confidence_vector <- as.list(setNames(conf, LV$Ticker))

verdicts <- c("F1_export_surprise", "F2_export_yoy_level", "F3_export_accel",
              "F4_export_surprise_secneutral")
method_log <- lapply(verdicts, function(fid) {
  r <- z$results[[fid]]
  list(name = fid,
       canonical_port_t_nw_lag3 = round(r$portfolio_alpha_t_nw_lag3, 4),
       ew_universe_port_t = round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_, 4),
       turnover_annual = round(r$turnover_annual, 3),
       n_months = r$n_months, selected = identical(fid, "F1_export_surprise"),
       mechanism_note = switch(fid,
         F1_export_surprise = "PRIMARY — 레벨은 이미 가격 반영이라는 메커니즘의 직접 표현(서프라이즈)",
         F2_export_yoy_level = "대조군: 서프라이즈가 성장 레벨보다 나은가",
         F3_export_accel = "대조군: 3M 가속이 별도 정보인가",
         F4_export_surprise_secneutral = "대조군: FQ-066/067 sector-rotation negative 대비 firm-level 증분 분리"))
})

pkg <- list(
  task_id = "WT-D20260802_001",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",

  hypothesis = list(
    statement = paste0(
      "관세청 HS 월별 수출을 DART 사업부문 제품믹스로 종목에 귀속한 '수출 nowcast 서프라이즈'는 ",
      "분기 재무제표(45일+ 지연)보다 선행하는 firm-level 펀더멘털 flow이며, ",
      "특히 KOSPI200 대형 제조·반도체·화학 종목에 직접 귀속되므로 ",
      "return-derived 후보들이 소멸한 cap-tier x cap-w 전이 벽을 넘을 수 있다."),
    mechanism = list(
      agent = paste0("국내외 sell-side 애널리스트 및 기관 트레이더 — KR 대형 제조사 커버리지에서 ",
                     "분기 실적 공시(45일+ 지연)를 실적 갱신의 주된 앵커로 삼는 참여자군. ",
                     "월별 통관 수출은 그보다 빠르나 HS코드-기업 귀속표가 공개 존재하지 않아 대부분 소비하지 않는다."),
      friction = paste0("① 귀속 비용 — HS 10자리 14,153개를 사업보고서 제품 텍스트와 매핑해야 하며 ",
                        "이 작업의 시장가격이 TRASS/Aicel 유료 벤더의 존재로 실증된다. ",
                        "② KR 공매도 제약 — 수출 부진의 negative 정보는 가격에 반영되기 어려워 long 쪽으로 비대칭. ",
                        "③ 월간 이산 공표 — 연속 재평가 대상이 아니라 갱신 시점에 정보가 몰린다."),
      path = paste0("데이터월 M 수출 서프라이즈 → M+1월 15일 1차 현행화 공표 → M+1 거래월말 스코어 배치 → ",
                    "홀딩월 M+2 동안 후속 컨센서스 영업이익 상향 및 분기 실적 발표를 통해 가격 반영")),
    falsification = paste0(
      "수출 서프라이즈 상위 5분위 종목의 후속 3M 컨센서스 영업이익 추정치(op_profit_fy1, ",
      "field_dictionary C-CONSENSUS-QW)가 하위 5분위 대비 유의하게(t>=2) 상향되지 않으면 ",
      "'수출→실적기대' 경로가 끊어진 것이므로 기전 기각. (가격·성과를 참조하지 않는 부수 관측)"),
    regime_scope = list(
      holds_in = list("neutral", "expansion"),
      weakens_or_reverses_in = list("crisis", "krw_shock"),
      boundary_rationale = paste0(
        "수출액은 USD 표시다. 급격한 환율 국면에서는 USD 수출 증가가 KRW 실적 증가와 괴리되어 ",
        "신호-실적 연결이 끊긴다. 또한 위기 국면은 유동성 청산이 펀더멘털 정보를 압도한다. ",
        "경계는 '통관 통계의 표시통화'라는 메커니즘 속성에서 도출된 것이지 사후 성과 관찰이 아니다."))),

  factors = list(list(
    factor_id = "F1_export_surprise",
    ast = ast1,
    role = "core_signal",
    restatement_exposure = 1,
    restatement_note = paste0(
      "관세청 원천은 '매월 15일경 전월까지의 자료를 전체 현행화, 개정 종료일 없음'(data.go.kr 15101609 원문) ",
      "= 저장소 내 최고 수준 restatement 원천. 단 field_map 미등재로 ast_verify 는 ",
      "restatement_leaves=[] 로 통과시켰다 (ALB-003)."))),
  combination_rule = "single_factor",
  verdict = "designed",

  # ── 이중 계약 충족 (ALB-005/006) ─────────────────────────────────────────────
  # schema.json 은 hypothesis.falsification 을 **string** 으로, ast_spec_gate.sh 는
  # **필드참조 객체 배열**로 요구한다 — 두 계층이 같은 필드의 타입에 대해 모순.
  # 또 schema 는 AST 를 factors[].ast 에 두지만 gate 의 extract_ast() 는
  # top-level / factor_definition / spec 만 본다.
  # 아래 두 키는 동일 내용의 기계가독 표현이며 새 주장 추가가 아니다(정보 중복, 왜곡 아님).
  # gate ③ 이 in-process ast_verify 를 돌릴 때 요구하는 PIT 앵커 (schema 미정의 키).
  pit = list(sig_date = "2026-07-31", decision_ts = "2026-07-31"),
  falsification = list(list(
    field = "C-CONSENSUS-QW",
    observation = paste0("수출 서프라이즈 Q5 종목의 후속 3M op_profit_fy1 컨센서스 개정이 ",
                         "Q1 대비 유의(t>=2) 상향되지 않으면 기전 기각"),
    executed = TRUE, result_t_stat = FAL$results$H63d$t_stat,
    result_spread_logrev = FAL$results$H63d$q5_minus_q1_logrev,
    verdict = FAL$verdict)),
  ast = ast1,

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "STORED_SCORE:fq073_export_exposure",
           availability_rule = "manual_export/derived — avail_ts = data_ym(M)+1개월 15일 (PIT_plan_fq073 §1-c 1차 현행화). 패널 내 avail_ts 컬럼이 권위(암묵 0 아님)",
           restatement_prone = TRUE, vintage_available = FALSE),
      list(leaf = "FIELD:rawdata:Sector (F4 전용)",
           availability_rule = "A1_RAWDATA_OHLCVS_daily — verify 기준 t+1. TS_LAG(1d) 적용으로 준수",
           restatement_prone = TRUE, vintage_available = FALSE)),
    verdict = "warn_restatement",
    verdict_rationale = paste0(
      "타이밍(C5) 은 clean — 버퍼 14~17일 실측, assert_overlay_pit HARD PASS, lag1 스트레스 무변화. ",
      "그러나 ① customs 개정판 기반(first-release 소급 복원 불가) ② crosswalk static_current ",
      "(2024-25 사업보고서 1 vintage를 전 역사 귀속 = C1/C3) 두 노출이 실재하므로 clean 선언 불가.")),

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_001/alpha_scores_F1_export_surprise.parquet",

  factor_specs = list(list(
    factor_family = "Fundamental_Flow_NonReturn",
    proxy = "customs_HS_export_surprise_via_DART_segment_crosswalt",
    formula = "CS_ZSCORE(CS_WINSORIZE(G - TS_MEAN(G,12), 0.02)), G = LOG(x) - LOG(TS_LAG(x,12)), x = Sum_h w_ih * HS4_monthly_export_USD",
    lag_rule = "data_ym M -> usable M+1/15 -> score M+1 month-end -> holding M+2 (buffer 14~17d)",
    winsorization = "cross-sectional 2% both tails",
    neutralization = "none (F4 = sector-neutral variant)",
    economic_rationale = "firm-level 통관 수출은 분기 재무제표보다 선행하는 실물 매출 flow이며, 귀속 비용이 차익거래 마찰로 작동한다",
    weight_theta = 1.0,
    redundancy_cluster_id = "nonreturn_customs_export_fq073",
    source = "new_designed",
    references = list("FQ-073 frontier queue", "PIT_plan_fq073.md (2026-07-25)"))),

  diagnostics = list(
    canonical_port_t_nw_lag3 = round(r1$portfolio_alpha_t_nw_lag3, 4),
    canonical_port_t_pvalue = round(r1$portfolio_alpha_t_pvalue, 4),
    canonical_n_months = r1$n_months,
    metric_type = "canonical_screen",
    rank_ic = DIA$rank_ic$rank_ic,
    icir = DIA$rank_ic$icir,
    harvey_t_stat = DIA$rank_ic$ic_t_stat,
    monotonicity = NA,
    subperiod_stability = DIA$subperiod_port_t,
    turnover_proxy = round(r1$turnover_annual, 3),
    post_neutralization_ic = NA,
    information_ratio = round(r1$information_ratio, 4),
    net_sr = round(r1$net_sr, 4),
    gross_0bps_port_t = DIA$gross_vs_net$gross_0bps_port_t,
    dual_basis = list(
      cap_w_port_t = round(r1$portfolio_alpha_t_nw_lag3, 4),
      ew_universe_port_t = round(r1$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_, 4),
      cap_tier_weight_share = r1$diag_cap_tier$weight_share_avg,
      cap_tier_contrib_annualized = r1$diag_cap_tier$contrib_gross_annualized,
      verdict = "EW-대비도 음수 — cap-w 벤치 아티팩트 아님. cap-tier 는 OTHER 88.9% 로 소형주 국소화 재현."),
    large_cap_restricted_F5 = DIA$F5_large_cap_restricted,
    effective_cross_section = DIA$effective_cross_section,
    falsification_test = FAL$results,
    falsification_verdict = FAL$verdict,
    dynamic_pit = list(lag1 = DIA$dynamic_lag1_stress, strict_ab = DIA$dynamic_strict_pit_ab,
                       vintage_swap = DIA$dynamic_vintage_swap,
                       label_direction_cor = 1.0),
    ast_verify = list(honest = "FAIL_CONTRACT (production_parity_verified)",
                      counterfactual_parity_true = "PASS",
                      lookahead_violations_after_fix = 0,
                      first_run_caught = "F4 sector-neutral FAIL_LOOKAHEAD (rawdata Sector t+1) — TS_LAG(1d)로 수정"),
    n_iterations = 5, selection_type = "chain",
    deflated_sharpe_ratio = NA,
    dsr_note = "selection_type=chain (가설주도 순차 대조군) — measurement-graduation §3 상 DSR 게이트 부적용. 수치도 미산출(전 후보 음수라 진단 무의미)."),

  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,

  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH",
         flag = "crosswalk static_current = C1/C3 사업구성 look-ahead. 원 크로스워크 자체가 gate_eligible=FALSE 로 라벨링. 본 측정은 진단 lane이며 graduation 판정 자격 없음."),
    list(id = "CF-02", severity = "HIGH",
         flag = "'상한(upper bound)' 논증의 한계 — 매핑 vintage 오류는 favorable bias 가 아니라 attenuating noise 일 개연이 크다. 따라서 '상한이 음수이므로 clean lane 도 음수'는 강한 신호에만 성립하고 약한 신호는 배제하지 못한다 (self-adversarial ACCEPT)."),
    list(id = "CF-03", severity = "HIGH",
         flag = "rank-IC ~ 0 (-0.0034, t -0.30) 인데 top-25 PORT_t = -1.71. 광범위 횡단면 신호가 아니라 극단 tail 선택 효과. top-25 가 최고변동 niche HS4 버킷(소형주)을 구조적으로 선택 — 수출 정보가 아니라 lottery-stock 페널티를 재측정했을 개연."),
    list(id = "CF-04", severity = "MEDIUM",
         flag = "회전율 1288%/yr — Production Constraints 상 TO<=1100% 초과. 양(+) 신호였더라도 현 horizon 에서는 구현 불가."),
    list(id = "CF-05", severity = "MEDIUM",
         flag = "regime_scope 예측 반증 — crisis 에서 약화를 예측했으나 2020-22(COVID) 부기간 PORT_t 는 +1.53 으로 유일한 양수 구간. 메커니즘에서 도출한 국면 경계가 데이터와 어긋난다."),
    list(id = "CF-06", severity = "MEDIUM",
         flag = "유효 횡단면 해상도 0.644 — 월평균 183 종목 중 서로 다른 스코어 116개. 동일 HS4 단일매핑 종목은 구분 불가하므로 'firm-level' 주장이 64%만 실현됨."),
    list(id = "CF-07", severity = "MEDIUM",
         flag = "survivorship — crosswalk 474사는 현재 상장 기업 기반. 과거 유니버스의 상장폐지 종목은 스코어 풀에 부재(C6)."),
    list(id = "CF-08", severity = "LOW",
         flag = "vintage-swap 무증거 — 스냅샷 2개가 6일 간격이고 개정일(15일)을 포함하지 않아 개정폭 미측정. 무증거는 무개정이 아니다."),
    list(id = "CF-09", severity = "INFO",
         flag = "AST 계층 결함 4건 적립 — 06_Registry/ast_leaf_table_bugs.jsonl ALB-001~004 (방언 분기 / production_parity 범위 / field_map 미등재 무검사 / rawdata 가용성 불일치).")),

  verdict_summary = list(
    result = "config_scoped_negative",
    lane = "LANE_UPPER_BOUND (static_current 매핑 + revised vintage)",
    gate_eligible = FALSE,
    statement = paste0(
      "본 config(월간 HS4 서프라이즈 x static_current 크로스워크 x top-25 cap-w EW long-only x 15bps)",
      "에서 FQ-073 은 양(+)의 알파를 산출하지 않는다. 4개 신호형 전부 cap-w·EW 양 basis 에서 음수이며, ",
      "대형주 제한(F5)에서는 음수가 사라지되 알파도 없다(PORT_t -0.33, p 0.74). ",
      "선언한 반증 검정에서 컨센서스 영업이익 상향은 방향은 맞으나(Q5 +1.78% vs Q1 +0.29%) ",
      "사전등록 기준 t>=2 에 미달(t=1.969) — 기전의 1차 링크는 약하게 존재하고 2차 링크(가격 전이)는 부재. ",
      "구조 판결 아님 — 미검 축은 next_probe 참조."))
)

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
cat("[emit] alpha_package.json 저장\n")

# alpha_validation.json (stage_artifacts)
val <- list(task_id = "WT-D20260802_001", generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
            metric_type = "canonical_screen", lane = "LANE_UPPER_BOUND", gate_eligible = FALSE,
            factors = method_log, diagnostics = DIA, falsification = FAL,
            panel_provenance = MET,
            ast_verify_verdicts = list(
              F1_honest = "FAIL_CONTRACT", F1_counterfactual_parity_true = "PASS",
              F2 = "FAIL_CONTRACT", F3 = "FAIL_CONTRACT", F4 = "FAIL_CONTRACT",
              note = "전 FAIL_CONTRACT 사유는 동일 — STORED_SCORE production_parity_verified. ALB-002."),
            graduation_hard_gates = list(
              portfolio_alpha_t_nw = list(required = 2.95, observed_canonical = round(r1$portfolio_alpha_t_nw_lag3, 4),
                                          status = "FAIL", note = "forge-authoritative 아님 — canonical screen 실측"),
              oos_retention = list(required = 0.7, observed = NA, status = "NOT_COMPUTED",
                                   note = "PORT_t 음수로 forge 승격 미도달 — 산출 무의미"),
              calmar = list(required = 0.64, observed = NA, status = "NOT_COMPUTED")))
write_json(val, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
cat("[emit] alpha_validation.json 저장\n")

# alpha_scores.parquet (계약 표준 이름)
write_parquet(as.data.table(read_parquet(file.path(OUT, "alpha_scores_F1_export_surprise.parquet"))),
              file.path(OUT, "alpha_scores.parquet"))
cat("[emit] alpha_scores.parquet 저장\n")

# lineage — alpha_package.json write 이후 (L-194 순서 규약)
try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_001", package_type = "alpha_package",
    method_selected = "F1_export_surprise (AST v1.1, STORED_SCORE customs export exposure)",
    input_file_paths = c(
      file.path(OUT, "fq073_export_exposure_chapter.parquet"),
      "stage_artifacts/method_frontier/firm_level_scaffold/fq073/customs_hs_monthly.parquet",
      "stage_artifacts/method_frontier/firm_level_scaffold/fq073/firm_hs_crosswalk.parquet"))
  cat("[emit] lineage 기록 완료\n")
}, silent = FALSE)
