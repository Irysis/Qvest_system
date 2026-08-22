## WT-D20260822_010 — 산출물 발행: alpha_scores.parquet + alpha_validation.json + alpha_package.json
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260822_010")
say <- function(f, ...) cat(sprintf(paste0("[e] ", f, "\n"), ...))
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }

PC <- fromJSON(file.path(OUT, "00_precheck.json"))
M  <- fromJSON(file.path(OUT, "10_measure.json"))
FA <- fromJSON(file.path(OUT, "11_falsify.json"))
DX <- fromJSON(file.path(OUT, "12_decomp.json"))
HY <- fromJSON(file.path(MBX, "alpha_hypothesis.json"), simplifyVector = FALSE)
O  <- readRDS(file.path(OUT, "10_measure_objects.rds")); SMx <- O$SMx; cb <- O$cb; cf <- O$cf
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
RET <- as.data.table(SI$fwd_ret)[, Date := as.Date(Date)][, .(Date, Ticker, Ret_1m)]

## ── 1. alpha_scores.parquet ────────────────────────────────────────────────
AS <- SMx[, .(Date, Ticker, base_score_eff = sc, score_orth, excluded)]
AS[, alpha_score := ifelse(excluded, NA_real_, base_score_eff)]
AS[, `:=`(metric_type = "weighted_screen",
          spec_id = "WT010_orthAbsorb_lo20_exclusion",
          direction_note = "alpha_score = base score_eff (높을수록 선호), 배제 종목은 NA. score_orth = vol/size 직교화 absorb 잔차(낮을수록 배제 대상). base 원본 패널은 복제하지 않고 필터 결과만 기록.")]
write_parquet(AS, file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet: %d행 / %d월 / 배제 %d행", nrow(AS), uniqueN(AS$Date), AS[, sum(excluded)])

## ── 2. advisory rank-IC (배제 후 유니버스 위 base score) ───────────────────
IC <- merge(AS[excluded == FALSE, .(Date, Ticker, s = alpha_score)], RET, by = c("Date","Ticker"))
ic_m <- IC[, .(ic = suppressWarnings(cor(s, Ret_1m, method = "spearman", use = "complete.obs")), n = .N),
           by = Date][is.finite(ic) & n >= 25]
IC0 <- merge(AS[, .(Date, Ticker, s = base_score_eff)], RET, by = c("Date","Ticker"))
ic0_m <- IC0[, .(ic = suppressWarnings(cor(s, Ret_1m, method = "spearman", use = "complete.obs")), n = .N),
             by = Date][is.finite(ic) & n >= 25]
rank_ic <- mean(ic_m$ic); icir <- rank_ic/sd(ic_m$ic); ic_t <- nw_t(ic_m$ic)
say("advisory rank-IC(배제 후) %.5f / ICIR %.4f / NW t %.3f | 배제 전 %.5f", rank_ic, icir, ic_t, mean(ic0_m$ic))

## ── 3. alpha_vector / confidence_vector (최종 sig_date) ────────────────────
last_d <- max(AS$Date)
LV <- AS[Date == last_d & excluded == FALSE]
LV[, z := (base_score_eff - mean(base_score_eff))/sd(base_score_eff)]
alpha_vector <- setNames(as.list(round(LV$z, 6)), LV$Ticker)
dd <- sort(unique(AS$Date)); recent <- tail(dd, 5)
ST <- AS[Date %in% recent, .(Date, Ticker, base_score_eff)]
ST[, pr := frank(base_score_eff)/.N, by = Date]
stab <- ST[, .(sdp = sd(pr), k = .N), by = Ticker][k >= 3]
conf <- merge(LV[, .(Ticker, has_axis = is.finite(score_orth))], stab, by = "Ticker", all.x = TRUE)
conf[, c1 := as.numeric(has_axis)]
conf[, c2 := pmax(0, pmin(1, 1 - (sdp/0.35)))]
conf[!is.finite(c2), c2 := 0.5]
conf[, cv := round(pmax(0, pmin(1, 0.5*c1 + 0.5*c2)), 4)]
confidence_vector <- setNames(as.list(conf$cv), conf$Ticker)
say("alpha_vector n=%d (sig_date %s) / confidence 평균 %.3f", length(alpha_vector), as.character(last_d), mean(conf$cv))

## ── 4. alpha_validation.json ───────────────────────────────────────────────
V <- list(
  wt_id = "WT-D20260822_010", fq_ref = "FQ-234 NP2 → WT-009 NP2 (규모-중립 배제)",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  prereg = list(gate = "stage_artifacts/WT-D20260822_010/PREREG_GATE.json",
                measurement = "stage_artifacts/WT-D20260822_010/PREREG.json"),
  differentiation_vs_prior = list(
    wt009 = "배제집합 = raw absorb 하위 20% — size 노출과 뒤섞인 축",
    wt010 = "배제집합 = vol·size 직교화 잔차(score_orth) 하위 20% — FQ-234 NP2 가 이미 측정한 객체",
    not_a_sweep = "X 는 0.20 동일 고정. 바뀐 것은 문턱이 아니라 배제집합을 정의하는 객체다.",
    hypothesis_index_lookup = list(queried = c("absorb","tail exclusion→exclusion","size neutral→neutral","universe filter exclusion"),
      prior_art = c("WT-D20260802_014_016_LOTTERY_EXCLUSION_FILTER (양성 대조로 재측정)",
                    "WT-D20260718_002_insider_sell_exclusion", "WT-D20260714_001 top25_capw_exclusion",
                    "WT-D20260822_009 (직전 라운드, 본 라운드의 대조군)"),
      novel_combination = "직교화 잔차 공간 배제 = 인덱스 기준 미측정 조합")),
  precheck_gate = PC$gate,
  object_identity = PC$object_identity,
  orth_axis = PC$orth_axis,
  base_anchor = PC$base_anchor,
  census = PC$census,
  exposure_neutrality = list(
    all_excl_srank = PC$exposure_neutrality$all_excl_srank,
    all_keep_srank = PC$exposure_neutrality$all_keep_srank,
    size_gap = FA$N1$size_gap, size_nw_t = FA$N1$size_nw_t,
    vol_gap = FA$N1$vol_gap, vol_nw_t = FA$N1$vol_nw_t,
    residual_share_vs_raw = FA$N1$residual_share_vs_raw_size,
    top25_excl_srank = PC$exposure_neutrality$top25_excl_srank,
    top25_keep_srank = PC$exposure_neutrality$top25_keep_srank,
    top25_excl_meanw = PC$exposure_neutrality$top25_excl_meanw,
    top25_keep_meanw = PC$exposure_neutrality$top25_keep_meanw,
    substitution_weight_ratio = M$substitution$weight_sum_ratio,
    wt009 = PC$exposure_neutrality$wt009,
    verdict = "중립화 성립(문턱 기준) — size gap 0.2522 → 0.0815(67.7% 제거), 치환 비중합 비율 2.296배 → 1.144배. 단 NW t 는 여전히 유의(-19.5)라 '완전 중립'이 아니라 '문턱-충족 중립'."),
  primary = list(basis = "cap-w top25 cap_norm weighted_screen 15bps (사전등록 고정)",
    base = M$base, filtered = M$filtered, paired = M$paired,
    delta_ir = M$paired$delta_ir, gate = 0.05, pass = (M$paired$delta_ir >= 0.05)),
  paired_ci = DX$paired_ci,
  basis_comparison = list(cap_w = list(delta_ir = M$paired$delta_ir, port_t_base = M$base$port_t, port_t_filt = M$filtered$port_t, binding = TRUE),
    ew_top25 = list(delta_ir = M$ew$delta_ir, port_t_base = M$ew$base$port_t, port_t_filt = M$ew$filtered$port_t, binding = FALSE),
    ew_universe_bench = M$ew$ew_universe_bench,
    note = "판정 basis 는 cap-w 고정. EW 도 이번엔 같은 부호(-0.0105)라 WT-009 처럼 갈리지 않았다."),
  positive_control = M$poscontrol,
  falsification = list(N1 = FA$N1, N2 = FA$N2, N3 = FA$N3, fired_count = FA$fired_count),
  transition_wall = FA$transition_wall,
  exposure_removal_accounting = FA$exposure_removal_accounting,
  pnl_decomposition = DX$pnl_decomposition,
  mechanism_consistency = DX$mechanism_consistency,
  label = DX$label,
  window_reachability = DX$window_reachability,
  robustness = list(lag1 = M$lag1, x_sensitivity_diagnostic = M$xdiag,
    window_split = M$window_split, regime = M$regime_tab, mdd = M$mdd,
    x_note = "X=0.10/0.30 은 진단 병기 — 판정 사용 금지(사전등록). 세 값 전부 음수 ΔIR 이라 문턱 선택이 결과를 만든 것이 아님을 보인다."),
  advisory_ic = list(rank_ic_postfilter = rank_ic, icir = icir, rank_ic_nw_t = ic_t,
    rank_ic_prefilter = mean(ic0_m$ic), n_months = nrow(ic_m),
    note = "배제 후 유니버스 위 base score_eff 의 IC — absorb 자체의 IC 가 아니다(absorb 는 랭킹에 등장하지 않음). advisory."),
  pit = PC$pit,
  metric_type = "weighted_screen (primary) + canonical_screen (dual-basis diag)",
  capital_eligible = FALSE,
  capital_note = "screening tier. HARD 3종(PORT_t/oos_retention/calmar)은 forge-authoritative 산출이며 본 라운드는 전이하지 않았다."
)
write_json(V, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
saveRDS(V, file.path(OUT, "alpha_validation.rds"))
say("alpha_validation.json 기록")

## ── 5. alpha_package.json ──────────────────────────────────────────────────
STORED_PROV <- list(
  store_build_hash = "alpha_scores_str1715_268m_cleanT1 / parity screen_cap_w_top25.port_t_nw_lag3 = 3.0583391232 (본 라운드 anchor STOP 재현)",
  generator_code_path = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code/_recompute_alpha_asof.R",
  generated_at = "2026-07-14 17:57:33", production_parity_verified = TRUE)
AP <- list(
  task_id = "WT-D20260822_010", as_of_date = "2026-08-22", forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  pit = list(sig_date = as.character(last_d), decision_ts = as.character(last_d)),
  hypothesis = HY$hypothesis,
  inherited_from = list(file = "qepm/mailbox/worktask/WT-D20260822_010/alpha_hypothesis.json",
    designer = "alpha-hypothesis (model: fable)",
    policy = "mechanism / falsification / regime_scope 승계 — 재작성·재해석 없음(Charter 원칙 8). 실측이 가설 문면과 어긋난 지점은 challenge_note.md 에 기록하고 문면은 수정하지 않았다."),
  consumption_gate_precheck = list(
    this_round_consumption_form = "모집단 배제(universe pre-filter). score_orth 는 '선정 자격 집합'만 줄이고 랭킹·weight 어디에도 등장하지 않는다.",
    verdict_metric = "평균 basis 실측만 — weighted_screen(cap-w) ΔIR/PORT_t + canonical_screen 병기. 분포 통계량은 판정 수치에 등장하지 않는다.",
    inherited_from_wt009 = "WT-D20260822_009 alpha_package.json$consumption_gate_precheck 의 4중 근거·잔여 긴장 1건 그대로 승계(재해석 없음).",
    np4_gate = list(applied = TRUE, ratio = PC$gate$ratio, threshold = 0.10, pass = PC$gate$pass,
      note = "착수 전 크기 산술 관문 — WT-009 결손의 항구 수리. 이번엔 통과(0.1465 = 1/6.8) 후 측정했다.")),
  factors = list(
    list(factor_id = "F1_base_score_on_orthAbsorbFiltered_universe",
      ast = list(op = "WHERE", args = list(
        list(leaf = "STORED_SCORE", provenance = STORED_PROV, production_parity_verified = TRUE,
             escape_contract = list(escape_type = "STORED_SCORE", provenance = STORED_PROV,
                                    production_parity_verified = TRUE)),
        list(leaf = "SPECIAL_OP",
             op_code_path = "stage_artifacts/WT-D20260822_010/00_precheck.R::mk_filter (score_orth 하위 20% 배제 마스크)",
             walk_forward = TRUE,
             escape_contract = list(escape_type = "SPECIAL_OP",
               op_code_path = "stage_artifacts/WT-D20260822_010/00_precheck.R::mk_filter",
               walk_forward = TRUE)))),
      role = "core_signal", restatement_exposure = 1,
      restatement_note = "STORED_SCORE 리프가 ast_field_map 미등재 → 보수적 restatement 표시(WARN_RESTATEMENT). 저장 패널은 2026-07-14 동결이나 상류 factor_db vintage 를 본 라운드가 증명하지 못했으므로 '확인 불가'를 '확인 완료'로 내려앉히지 않는다."),
    list(factor_id = "F2_orth_absorb_exclusion_gate",
      ast = list(op = "CS_RANK", args = list(
        list(leaf = "SPECIAL_OP",
          op_code_path = "stage_artifacts/WT-D20260822_010/00_precheck.R (score_orth = z(resid(lm(winsor(absorb_raw) ~ z(rank(win_vol)) + z(rank(log_size))))) by Date, 계약 distribution_target_screen.R::.dts_orthogonalize_by_date 호출) — absorb_raw 원천 = stage_artifacts/WT-D20260813_006/01_build_features.py (absorb = -corr_win(Individual_d, Ret_d), 3개월 창, d0 당일 차감)",
          walk_forward = TRUE,
          escape_contract = list(escape_type = "SPECIAL_OP",
            op_code_path = "stage_artifacts/WT-D20260822_010/00_precheck.R + 02_Infrastructure/contracts/distribution_target_screen.R::.dts_orthogonalize_by_date",
            walk_forward = TRUE)))),
      role = "conditioning", restatement_exposure = 0)),
  combination_rule = "single_factor",
  verdict = "designed",
  ast_expressiveness_note = "직교화(월별 횡단면 OLS 잔차)는 𝒪 최소집합으로 표현 불가 — SPECIAL_OP escape 리프 + escape_contract 로 정직 산출. 우회 구현(예: 근사 CS 연산 조합)으로 위장하지 않았다.",
  self_pit_check = list(performed = TRUE, leaves_checked = list(
    list(leaf = "STORED_SCORE:alpha_scores_str1715_268m_cleanT1.score_eff",
      availability_rule = "fixed: production 컨벤션 label = T-1 산출 · label월 보유. §7b production_parity_verified 라벨 stopifnot 게이트 + anchor PORT_t 3.0583 재현 STOP.",
      restatement_prone = FALSE),
    list(leaf = "SPECIAL_OP:orth_absorb_3m",
      availability_rule = "fixed: 일별 investor_wide(T+1 정산) + RAWDATA 를 창 {m-2,m-1,m} 집계, 신호일 d0 당일 관측 차감(strict Date < d0). 직교화는 **동월 횡단면만** 사용(pooled/full-sample 회귀 경로 없음 — 계약이 물리 차단). 홀딩월 = m+1, 컷오프 = 홀딩월 1일. assert_overlay_pit 268/268 PASS + 위반 주입 0/268(검사기 생존).",
      restatement_prone = FALSE),
    list(leaf = "A1_RAWDATA_OHLCVS_daily:Size / win_vol (통제축)",
      availability_rule = "fixed: t-1 종가·거래량 기반. 통제축은 신호일 횡단면에서만 사용.",
      restatement_prone = FALSE)),
    verdict = "clean",
    notes = "저장 파생 패널을 FIELD 리프로 위장하지 않았다(§4-1) — base 는 STORED_SCORE, 직교화 absorb 는 SPECIAL_OP."),
  alpha_vector = alpha_vector,
  alpha_vector_units = "cross-sectional z of base score_eff on 배제-후 유니버스 (sig_date 위 pit.sig_date). ★기대초과수익으로 캘리브레이션된 값이 아니다 — 본 라운드는 전이하지 않으므로 수익-스케일 매핑을 산출하지 않았다. 감사·재현용.",
  confidence_vector = confidence_vector,
  confidence_rule = "0.5 x (직교화 축 가용 = 배제 판정 가능) + 0.5 x (직전 5 sig_date 의 score_eff 횡단면 랭크 백분위 표준편차를 0.35 로 정규화한 안정성). 데이터 가용성 + 랭크 안정성 2축 — 성과 기반 가중 없음.",
  signal_matrix_ref = "stage_artifacts/WT-D20260822_010/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "flow_covariance_residual", proxy = "orth_absorb_3m (vol/size 직교화)",
    formula = "z(resid(lm(winsor(absorb_raw,[.01,.99]) ~ z(rank(win_vol)) + z(rank(log_size))))) by Date; absorb_raw = -corr_{m-2..m}(Individual_d, Ret_d)",
    lag_rule = "daily flow T+1 정산 · 창 종점 = 신호일 d0 직전(당일 차감) · 홀딩월 m+1",
    winsorization = "회귀 좌변 [0.01, 0.99] 월별 횡단면 (버킷팅 미적용 — 계약 규약)",
    neutralization = "vol + size (월별 횡단면 rank-OLS)",
    economic_rationale = "개인 추격매수가 지지하는 가격은 지지 철회 시 좌측 꼬리로 실현된다. 규모·변동성으로 설명되는 부분을 걷어낸 잔차 성분에서 그 행태가 남아 있어야 주체 주장이 성립하며, NP2 직교화 실측(tail_dn_prob_diff NW-t -4.32/-3.10, disjoint 2창 부호일치)이 그 잔차의 판별력을 보였다.",
    redundancy_cluster_id = "CL_flow_intramonth_covariance (absorb 계열 — WT-D20260813_006 / WT-D20260822_003 / WT-D20260822_009 와 동일 클러스터. 본 라운드는 같은 원천의 **직교화 변형**이므로 신규 팩터가 아니라 기존 재료의 재정의)",
    weight_theta = NA, role = "universe_exclusion_gate (랭킹 미참여)",
    references = list("Miller 1977 (공매도 제약 하 의견 불일치)", "FQ-234 NP2 실측 stage_artifacts/WT-D20260822_003"))),
  diagnostics = list(
    canonical_port_t_nw_lag3 = round(cf$portfolio_alpha_t_nw_lag3, 4),
    canonical_port_t_note = "EW top-25 canonical_screen_bt(배제 후). 대조 배제 전 3.4782. ★판정 basis 는 이것이 아니라 cap-w weighted_screen(배제 후 2.5151 / 배제 전 3.0583) — 사전등록 primary.",
    canonical_n_months = M$base$n_months,
    weighted_screen_port_t_filtered = round(M$filtered$port_t, 4),
    weighted_screen_port_t_base = round(M$base$port_t, 4),
    delta_ir_primary = M$paired$delta_ir, paired_nw_t = M$paired$paired_nw_t,
    rank_ic = rank_ic, icir = icir, rank_ic_t = ic_t, rank_ic_base_prefilter = mean(ic0_m$ic),
    rank_ic_note = "배제 후 유니버스 위 base score_eff 의 IC — score_orth 의 IC 가 아니다(랭킹 미참여). advisory.",
    monotonicity = NULL, subperiod_stability = NULL,
    turnover_proxy = M$paired$annual_pp,
    turnover_note = sprintf("회전율 실측(weighted_screen): base %.0f%%/yr → filtered %.0f%%/yr (+%.1f%%p) — 배제가 회전을 늘렸다(WT-009 는 줄였다).",
      100*M$base$turnover_annual, 100*M$filtered$turnover_annual, 100*(M$filtered$turnover_annual - M$base$turnover_annual)),
    harvey_t_stat = NULL,
    harvey_note = "rank-IC 계열 Harvey-t 미산출 — 선택 권위는 PORT_t 이고 score_orth 는 랭킹에 등장하지 않는다(배제 전용). 미산출 사유 challenge_flags 등재.",
    post_neutralization_ic = NULL,
    deflated_sharpe_ratio = NULL,
    dsr_note = "sweep 아님(n_trials=1, 사전등록 단일 primary — X 고정·축 사전지정). measurement-graduation §3 chain 규약에 따라 DSR 게이트 부적용. X=0.10/0.30 은 판정 사용 금지 진단이며 argmax 선택에 쓰이지 않았다.",
    mdd_base = M$mdd$base, mdd_filtered = M$mdd$filtered,
    calmar_base = M$mdd$calmar_base, calmar_filtered = M$mdd$calmar_filtered,
    metric_type = "weighted_screen (primary) + canonical_screen (dual-basis)"),
  selection_objective = "canonical_port_t",
  selection_objective_note = "후보 선택 행위 자체가 없다(사전등록 단일 primary). 게이트는 base 대비 paired ΔIR.",
  n_trials = 1, selection_type = "preregistered_single_primary",
  method_shopping_log = list(candidates_tried = 1, parallel_exec = FALSE,
    method_log = list(list(name = "orth_absorb_lo20_exclusion", delta_ir = M$paired$delta_ir, selected = TRUE))),
  verdict_summary = list(
    round_outcome = "MECHANISM_CONFIRMED_CONSUMPTION_FORM_ADVERSE",
    transition_requested = FALSE,
    reason = sprintf(paste0("전이 요청 없음. 사전등록 transition_gates 4종 중 3종(alpha_discovery_count>=1 · screen_pass 1절 · 반증 발화 0)은 충족하나 ",
      "판정 게이트 ΔIR >= +0.05 가 역방향 미충족(%+.4f). 사전등록이 '하나라도 미충족이면 협상 없이 negative' 를 명시했으므로 risk-research 전이를 요청하지 않는다. ",
      "★본 라운드의 정보값: 노출 이동을 67.7%% 제거했는데 ΔIR 결손은 15.3%%만 회복됐다 — WT-009 실패의 지배 요인은 size 노출이 아니었다."),
      M$paired$delta_ir)),
  challenge_flags = list(
    list(id = "CF1", severity = "HIGH",
      note = "기전 4축 전부 정합 + 반증 3건 전부 미발화인데 ΔIR 은 음수다. 기전의 참·거짓과 '배제 형태 소비의 손익'이 다른 문제임을 보이는 실측 — 이 구분을 흐리지 않는다."),
    list(id = "CF2", severity = "MEDIUM",
      note = "노출 중립성은 '문턱 충족'이지 '완전 중립'이 아니다(size gap -0.0815, NW t -19.5 여전히 유의). 잔존 노출이 결손의 일부를 설명할 여지는 남는다 — 다만 67.7% 제거로 15.3%만 회복된 기울기로 외삽하면 완전 중립화가 게이트를 넘기지 못한다."),
    list(id = "CF3", severity = "MEDIUM",
      note = "양성 대조의 paired NW t 도 1.566 으로 2 미만 — 이 하네스의 전도성은 ΔIR 점추정 수준이지 유의성 수준이 아니다. '검출됨'을 '유의하게 검출됨'으로 읽지 않는다."),
    list(id = "CF4", severity = "MEDIUM",
      note = "검출축 라벨은 '미결(underpowered)' 이다 — 기전-함의 상한(연 +0.48%p)이 paired 95% CI [-3.63, +1.37]%p 안에 있다. 자본축은 점추정 게이트라 FAIL 이 확정이다. 두 축을 섞지 않는다."),
    list(id = "CF5", severity = "LOW",
      note = "rank-IC 계열 Harvey-t / post-neutralization IC / DSR 미산출 — 사유는 diagnostics 각 note 에 기재(랭킹 미참여 · sweep 아님)."),
    list(id = "CF6", severity = "LOW",
      note = "유동성 자는 2e8(헌법 LIQ_THRESHOLD)로 걸었고 request.json 의 5e7 보다 보수적이다. WT-009 와의 비교 가능성 보존이 이유이며, 완화 방향이 아니므로 mandate 위반이 아니다.")),
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
write_json(AP, file.path(MBX, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("alpha_package.json 기록 (%s)", file.path(MBX, "alpha_package.json"))

## ── 6. lineage (write 직후 순서 준수, L-194) ───────────────────────────────
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(task_id = "WT-D20260822_010", package_type = "alpha_package",
  method_selected = "orth-absorb(vol/size 직교화 잔차) 하위 20% 유니버스 배제 x base score_eff top-25 cap-w",
  input_file_paths = c(
    "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet",
    "stage_artifacts/WT-D20260813_006/alpha_scores.parquet",
    "stage_artifacts/WT-D20260813_006/absorb_panel.parquet",
    "stage_artifacts/WT_D20260714_004/screen_inputs.rds",
    "stage_artifacts/WT_D20260802_010/ot_panel.parquet",
    "qepm/mailbox/worktask/WT-D20260822_010/alpha_hypothesis.json"))
say("lineage 기록 완료")
say("done")
