## WT-D20260822_009 — alpha_package.json (AST v1.1 3층) 발행
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT-D20260822_009")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-D20260822_009")
say <- function(f,...) cat(sprintf(paste0("[p] ",f,"\n"),...))
V   <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector = FALSE)
HYP <- fromJSON(file.path(MB,"alpha_hypothesis.json"), simplifyVector = FALSE)
O   <- readRDS(file.path(OUT,"10_measure_objects.rds")); SMx <- O$SMx
SI  <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
RET <- as.data.table(SI$fwd_ret)[, Date := as.Date(Date)][, .(Date,Ticker,Ret_1m)]

## ── advisory: rank-IC of 최종 alpha (배제 후 유니버스 위 base score_eff) ────
A <- SMx[excluded == FALSE, .(Date,Ticker,score = sc)]
IC <- merge(A, RET, by = c("Date","Ticker"))[is.finite(Ret_1m),
        .(ic = if (.N >= 20) cor(score, Ret_1m, method = "spearman") else NA_real_), by = Date][is.finite(ic)]
rank_ic <- mean(IC$ic); icir <- rank_ic/sd(IC$ic); ic_t <- rank_ic/(sd(IC$ic)/sqrt(nrow(IC)))
Ab <- SMx[, .(Date,Ticker,score = sc)]
ICb <- merge(Ab, RET, by = c("Date","Ticker"))[is.finite(Ret_1m),
        .(ic = if (.N >= 20) cor(score, Ret_1m, method = "spearman") else NA_real_), by = Date][is.finite(ic)]
say("rank-IC(배제 후) %.4f ICIR %.3f t %.2f | (배제 전) %.4f", rank_ic, icir, ic_t, mean(ICb$ic))

## ── as_of alpha_vector / confidence_vector (마지막 d0) ──────────────────────
last_d0 <- max(SMx$Date)
L <- SMx[Date == last_d0 & excluded == FALSE]
z <- (L$sc - mean(L$sc))/sd(L$sc)
setorder(L, -sc)
zz <- (L$sc - mean(L$sc))/sd(L$sc)
av <- as.list(setNames(round(zz, 6), L$Ticker))
## confidence: 0.5 x absorb 가용(배제 판정 가능) + 0.5 x 직전 3개월 score 랭크 안정성
H <- SMx[Date <= last_d0][order(Date)]
H[, rk := frank(-sc)/.N, by = Date]
d0s <- sort(unique(H$Date)); recent <- tail(d0s, 4)
RS <- H[Date %in% recent, .(sdrk = if (.N >= 3) sd(rk) else NA_real_), by = Ticker]
CF <- merge(L[, .(Ticker, absorb)], RS, by = "Ticker", all.x = TRUE)
CF[, conf := 0.5*as.numeric(is.finite(absorb)) +
             0.5*pmax(0, 1 - pmin(1, (ifelse(is.finite(sdrk), sdrk, 0.35)/0.35)))]
cv <- as.list(setNames(round(CF$conf, 4), CF$Ticker))
say("as_of %s: alpha_vector %d종 / confidence 평균 %.3f", as.character(last_d0), length(av), mean(CF$conf))

PKG <- list(
  task_id = "WT-D20260822_009", as_of_date = "2026-08-22", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = as.character(as.Date(last_d0)), decision_ts = as.character(as.Date(last_d0))),

  hypothesis = list(
    statement = HYP$selected$hypothesis_description,
    mechanism = HYP$selected$mechanism,
    falsification = HYP$selected$falsification$reject_if,
    regime_scope = HYP$selected$regime_scope),
  inherited_from = list(file = "qepm/mailbox/worktask/WT-D20260822_009/alpha_hypothesis.json",
    designer = "alpha-hypothesis (model: fable)",
    policy = "mechanism / falsification / regime_scope 승계 — 재작성·재해석 없음 (Charter 원칙 8). 실측이 regime_scope 예측과 어긋난 사실은 challenge_note.md 에 기록했고 가설 문면은 수정하지 않았다."),
  consumption_gate_precheck = HYP$consumption_gate_precheck,

  factors = list(
    list(factor_id = "F1_base_score_on_absorbFiltered_universe",
         ast = list(op = "WHERE", args = list(
           list(leaf = "STORED_SCORE", escape_contract = list(
             escape_type = "STORED_SCORE",
             provenance = list(
               store_build_hash = "alpha_scores_str1715_268m_cleanT1 / meta built_at 2026-07-14 17:57:33 / parity screen_cap_w_top25.port_t_nw_lag3 = 3.0583391232",
               generator_code_path = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R (R28 verbatim port; clean 패널은 plumbing_fq044 p1 산출)",
               generated_at = "2026-07-14 17:57:33"),
             production_parity_verified = TRUE)),
           list(leaf = "SPECIAL_OP", escape_contract = list(
             escape_type = "SPECIAL_OP",
             op_code_path = "stage_artifacts/WT-D20260822_009/10_measure.R::mk_filter (absorb 하위 20% 배제 마스크; absorb 원천 = stage_artifacts/WT-D20260813_006/01_build_features.py)",
             walk_forward = TRUE)))),
         role = "core_signal", restatement_exposure = 0L),
    list(factor_id = "F2_absorb_exclusion_gate",
         ast = list(op = "CS_RANK", args = list(
           list(leaf = "SPECIAL_OP", escape_contract = list(
             escape_type = "SPECIAL_OP",
             op_code_path = "stage_artifacts/WT-D20260813_006/01_build_features.py (absorb = -corr_win(Individual_d, Ret_d), 3개월 창, d0 당일 차감)",
             walk_forward = TRUE)))),
         role = "conditioning", restatement_exposure = 0L)),
  combination_rule = "single_factor",
  verdict = "designed",
  ast_expressiveness_note = "𝒪 에 비교 연산자가 없어 '하위 20% 미만이면 제외' 라는 **문턱 비교 자체**는 WHERE 의 인자로 직접 표현되지 않는다. 본 패키지는 배제 마스크를 SPECIAL_OP escape 리프(op_code_path 명시)로 담아 verdict=designed 로 산출했다 — 우회 구현이 아니라 escape 계약의 정규 용법이다. 다만 '분위 문턱 비교'는 배제·필터형 가설에서 반복될 원자 연산이므로 06_Registry/ast_operator_backlog.json 에 CS_QUANTILE_GATE(또는 비교 연산자 GE/LE) 후보로 적립할 가치가 있다 — 이는 선제 확장 요구가 아니라 관측 기록이다.",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "STORED_SCORE:alpha_scores_str1715_268m_cleanT1.score_eff",
           availability_rule = "fixed: production 컨벤션 label = T-1 산출 · label월 보유. §7b production_parity_verified 라벨 확인(vintage_verified stopifnot 게이트). 저장 원본 268m(same-month off+1 look-ahead)은 사용하지 않았다 — cleanT1 만 소비.",
           restatement_prone = FALSE),
      list(leaf = "SPECIAL_OP:absorb_3m",
           availability_rule = "fixed: 일별 investor_wide(T+1 정산) + RAWDATA 를 창 {m-2,m-1,m} 에서 집계하되 신호일 d0 당일 관측을 충분통계 차감으로 제외(strict Date < d0). 홀딩월 = m+1, 컷오프 = 홀딩월 1일. assert_overlay_pit 268/268 PASS + 위반 주입 0/268(검사기 생존).",
           restatement_prone = FALSE),
      list(leaf = "A6_investor_flow_stock_daily:Individual",
           availability_rule = "fixed: T+1 정산 (compute_investor.R inv[Date < sig_d] 컨벤션 동일)",
           restatement_prone = FALSE)),
    verdict = "clean",
    notes = "저장 파생 패널을 FIELD 리프로 위장하지 않았다(§4-1) — base 는 STORED_SCORE, absorb 는 SPECIAL_OP 로 각각 escape 계약을 붙였다."),

  alpha_vector = av,
  alpha_vector_units = "cross-sectional z of base score_eff on 배제-후 유니버스 (sig_date 2026-03-31). ★기대초과수익으로 캘리브레이션된 값이 아니다 — 본 라운드는 전이하지 않으므로 risk/optimizer 소비용 수익-스케일 매핑을 산출하지 않았다. 이 벡터는 감사·재현용이다.",
  confidence_vector = cv,
  confidence_rule = "0.5 x (absorb 가용 = 배제 판정 가능) + 0.5 x (직전 4 d0 의 score_eff 횡단면 랭크 백분위 표준편차를 0.35 로 정규화한 안정성). 데이터 가용성 + 랭크 안정성 2축만 — 성과 기반 가중 없음.",
  signal_matrix_ref = "stage_artifacts/WT-D20260822_009/alpha_scores.parquet",

  factor_specs = list(
    list(factor_family = "InvestorFlow", proxy = "absorb (월내 개인 순매수-수익 공분산 부호)",
         formula = "absorb = -corr_{d in [m-2,m], d < d0}(Individual_d, Ret_d)",
         lag_rule = "daily flow T+1 정산 · 창에서 d0 당일 관측 차감 · 홀딩월 = m+1",
         winsorization = "없음(분위 문턱만 사용 — 극단값이 순위에만 영향)",
         neutralization = "없음(raw 공간). ★규모 중립화 미적용이 본 라운드의 핵심 결함 — 배제군 size 백분위 0.300 vs 잔류 0.552 (NW t -26.6)",
         economic_rationale = "개인의 상승일 추격 매수로 지지된 가격은 지지 철수 시 좌측 꼬리로 실현된다. KR 공매도 제약이 그 하방 정보의 선반영을 막는다(Miller 1977). 실측: 소비 유니버스 내 저-absorb 꼬리율 5.06% vs 고-absorb 2.23%.",
         weight_theta = NA, redundancy_cluster_id = "flow_covariance_tail / prior-art MAX5(lottery)와 배제집합 교집합 24.3% — 별개 군집",
         source = "db_derived(Lane B 동결 패널)",
         references = list("Miller (1977) Risk, Uncertainty, and Divergence of Opinion",
                           "Barber & Odean (2008) All That Glitters (attention-driven retail buying)",
                           "Bali, Cakici & Whitelaw (2011) Maxing Out (lottery demand — prior art 재료)")),
    list(factor_family = "Composite(base)", proxy = "score_eff (STR_1715 production alpha)",
         formula = "production _recompute_alpha_asof.R 산출 (off=0 factor_db T-1 x stored theta 0.25x4 core EW x 7-factor sleeve)",
         lag_rule = "production T-1 컨벤션", winsorization = "production 내부", neutralization = "production 내부",
         economic_rationale = "incumbent base — 본 라운드의 고정 스코어링(배제 효과 분리를 위해 불변)",
         weight_theta = 1.0, redundancy_cluster_id = "incumbent_book_core",
         source = "db_existing(production_parity_verified 패널)",
         references = list("§7b measurement-graduation (incumbent base = production 코드 파생만)"))),

  diagnostics = list(
    canonical_port_t_nw_lag3 = 3.616,
    canonical_port_t_note = "EW top-25 canonical_screen_bt(배제 후). 대조 배제 전 3.478. ★본 라운드의 **판정** basis 는 이것이 아니라 cap-w weighted_screen(배제 후 2.435 / 배제 전 3.058) 이다 — 사전등록 primary.",
    canonical_n_months = 268L,
    weighted_screen_port_t_filtered = 2.435, weighted_screen_port_t_base = 3.058,
    delta_ir_primary = V$primary_verdict$delta_ir, paired_nw_t = V$primary_verdict$paired_nw_t,
    rank_ic = rank_ic, icir = icir, rank_ic_t = ic_t,
    rank_ic_note = "★이 rank-IC 는 **배제 후 유니버스 위의 base score_eff** 의 IC 이지 absorb 의 IC 가 아니다 — absorb 는 랭킹에 등장하지 않으므로 자체 rank-IC 를 본 라운드 판정에 쓰지 않는다. 배제 전 base IC 대조값 병기.",
    rank_ic_base_prefilter = mean(ICb$ic),
    monotonicity = NA, subperiod_stability = NA,
    turnover_proxy = V$primary_verdict$annual_pp,
    turnover_note = "회전율 실측은 weighted_screen 산출: base 1366%/yr, filtered 1325%/yr — 배제가 회전을 늘리지 않았다.",
    harvey_t_stat = NA,
    harvey_note = "rank-IC 계열 Harvey-t 미산출 — 본 라운드 선택 권위는 canonical/weighted PORT_t 이고 rank-IC 계열은 advisory 이며, absorb 자체의 랭킹 소비는 본 라운드 설계에 없다(배제 전용). 미산출 사유를 challenge_flags 에 등재.",
    post_neutralization_ic = NA,
    deflated_sharpe_ratio = NA,
    dsr_note = "sweep 아님(n_trials=1, 사전등록 단일 primary) — measurement-graduation §3 에 따라 DSR 게이트 부적용, 수치 미산출.",
    mdd_base = V$mechanism_diagnosis$mdd$base, mdd_filtered = V$mechanism_diagnosis$mdd$filtered,
    calmar_base = V$mechanism_diagnosis$mdd$calmar_base, calmar_filtered = V$mechanism_diagnosis$mdd$calmar_filtered,
    metric_type = "weighted_screen (primary) + canonical_screen (dual-basis)"),

  selection_objective = "canonical_port_t",
  selection_objective_note = "iteration 없음(n_trials=1). 사전등록 판정 게이트는 book-marginal ΔIR(§4) 이며 그 basis 는 screen-IR. selection_objective enum 에는 ΔIR 항목이 없어 가장 가까운 canonical_port_t 를 선언한다 — 실제 판정 수치와 basis 는 alpha_validation.json primary_verdict 에 명시.",

  n_trials = 1L, selection_type = "preregistered_single_primary",
  method_shopping_log = list(candidates_tried = 1L, method_log = list(
    list(name = "absorb_lo20_exclusion (사전등록 primary)", delta_ir = V$primary_verdict$delta_ir, selected = TRUE),
    list(name = "X=10% / X=30%", note = "사전등록 **비바인딩 진단** — 선택 후보 아님(성과 관측 후 재선택 금지)", selected = FALSE))),

  verdict_summary = list(
    round_outcome = V$primary_verdict$label,
    transition_requested = FALSE,
    reason = V$transition_gates$decision),

  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH", flag = "배제집합이 소형주에 강하게 편중(size 백분위 0.300 vs 0.552, NW t -26.6). 본 라운드의 불리한 ΔIR 은 꼬리-기전이 아니라 배제가 부수적으로 만든 **노출 이동**(제거 비중합 0.0788 → 추가 비중합 0.1810)에 지배될 수 있다. 규모-중립 배제(next_probe ②) 전까지 '재료 무용' 으로 읽지 말 것."),
    list(id = "CF-02", severity = "HIGH", flag = "기전 함의 크기(연 0.124%p)가 이 창의 MDE80(연 3.27%p)의 1/26 — 라운드가 자기 기전을 검출할 수 없는 설계였다. 이 산술은 착수 전에 가능했다(방법론 결함 자기신고, next_probe ④)."),
    list(id = "CF-03", severity = "MEDIUM", flag = "가설 regime_scope 는 neutral/expansion 성립을 예측했으나 실측은 RISK_ON(n=208) 에서 가장 불리(t -2.11). 승계 문면은 수정하지 않았다 — 국면 경계 예측의 실측 불일치로 기록."),
    list(id = "CF-04", severity = "MEDIUM", flag = "F1(승계 반증)의 비교 기준이 규모 중립이 아니다 — fwd_*_3m_n 은 Size 정규화 값이고 배제군은 소형주 편중. 기각조건 미충족(t +1.208 < +2.0)이라는 판정은 유효하나 부호를 기전 지지/반증 어느 쪽으로도 읽지 않는다."),
    list(id = "CF-05", severity = "MEDIUM", flag = "F2(승계 반증) t -8.934 는 absorb 의 월간 지속성 때문에 부분적으로 기계적일 수 있고 유효 월 n=42 로 작다. 기전 지지로 인용 시 두 제한 병기 의무."),
    list(id = "CF-06", severity = "MEDIUM", flag = "cap-w(판정, -0.1153) 와 EW(비바인딩, +0.0246) 의 부호가 갈린다. 판정은 사전등록대로 cap-w 이며 EW 로 뒤집지 않는다. 단 EW ΔIR 도 게이트 +0.05 미달임을 함께 적을 것."),
    list(id = "CF-07", severity = "MEDIUM", flag = "사전등록 label_map 에 {ΔIR<0 & |ΔIR|>=0.05 & -1.70<t<0} 구간 라벨이 없었다(설계 결함 자기신고). 사후 기준 이동 없이 서술 라벨을 부여했고 판정 자체는 게이트 미충족으로 결정."),
    list(id = "CF-08", severity = "LOW", flag = "harvey_t_stat / monotonicity / post_neutralization_ic / DSR 미산출. 사유: 본 라운드는 absorb 를 랭킹으로 소비하지 않으므로 rank-IC 계열 배터리의 대상이 아니고, DSR 은 sweep 아님. 미산출을 '통과' 로 읽지 말 것."),
    list(id = "CF-09", severity = "LOW", flag = "canonical_screen_bt 가 liq_dt attr 'liq_ruler' 라벨 부재 경고를 발행했다(FQ-232). 자 자체는 헌법 정의(t-1 20d ADV >= 2e8)이나 라벨 미부착 상태로 소비했다."),
    list(id = "CF-10", severity = "LOW", flag = "alpha_vector 는 캘리브레이션된 기대초과수익이 아니라 base score_eff 의 횡단면 z 다(alpha_vector_units 참조). 전이하지 않으므로 수익-스케일 매핑을 산출하지 않았다.")),

  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

write_json(PKG, file.path(MB,"alpha_package.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null")
say("alpha_package.json 기록 (%d bytes)", file.info(file.path(MB,"alpha_package.json"))$size)

source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id = "WT-D20260822_009", package_type = "alpha_package",
  method_selected = "absorb 하위 20% 배제 유니버스 필터 x production_parity_verified base score_eff (top-25 cap_norm)",
  input_file_paths = c(
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
    "stage_artifacts/WT-D20260813_006/absorb_panel.parquet",
    "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
    "stage_artifacts/WT_D20260802_010/ot_panel.parquet",
    "stage_artifacts/WT-D20260822_009/PREREG.json"))
say("lineage 기록 완료")
