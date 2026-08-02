# =============================================================================
# run_wt009_emit.R — WT-D20260802_009 AST v1.1 alpha_package + validation + lineage
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_009/run_wt009_emit.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_009")
`%||%` <- function(a, b) if (is.null(a)) b else a
num <- function(x, d = 4) if (is.null(x) || !is.finite(as.numeric(x))) NA else round(as.numeric(x), d)
say <- function(fmt, ...) cat(sprintf(paste0("[emit] ", fmt, "\n"), ...))

R <- readRDS(file.path(OUT, "wt009_eval_results.rds"))
PAIRS <- data.table(
  pair = c("P1_VALUE", "P2_MOMENTUM", "P3_LOWVOL", "P4_QUALITY", "P5_DIVIDEND"),
  base = c("V01_BM", "M01_Mom_12_1", "D03_RealVol", "Q01_GPA", "V06_fDY"),
  tuned = c("V01_SECREL", "M01_PATHQ", "D03_EWMA", "Q01_EB", "V06_EB"))

# ── alpha_vector / confidence (primary carrier = M01_PATHQ 최종 횡단면) ──────
TUNED <- as.data.table(read_parquet(file.path(OUT, "tuned_panel.parquet")))
TUNED[, Date := as.Date(Date)]
BASEP <- as.data.table(read_parquet(file.path(OUT, "base_panel.parquet")))
BASEP[, Date := as.Date(Date)]
SC <- TUNED[Factor_Name == "M01_PATHQ"]
last_d <- SC[, max(Date)]
LV <- SC[Date == last_d][order(-score)]
alpha_vector <- as.list(setNames(round(LV$score, 6), LV$Ticker))
cov_m <- SC[, .N, by = Ticker][, setNames(pmin(1, N / 120), Ticker)]
confidence_vector <- as.list(setNames(
  vapply(LV$Ticker, function(tk) round(max(0.3, min(1, as.numeric(cov_m[[tk]] %||% 0.5))), 3),
         numeric(1)), LV$Ticker))
write_parquet(SC[, .(Date, Ticker, score)], file.path(OUT, "alpha_scores.parquet"))

arm_stats <- function(a) {
  b <- R$bt[[a]]; ew <- b$diag_ew_universe; ct <- b$diag_cap_tier
  list(port_t = num(b$portfolio_alpha_t_nw_lag3, 3), net_sr = num(b$net_sr, 3),
       ir = num(b$information_ratio, 3), turnover_annual = num(b$turnover_annual, 2),
       n_months = b$n_months,
       ew_uni_t = num(ew$portfolio_alpha_t_nw_lag3, 3),
       ew_uni_post2017_t = num(ew$post2017_t_nw_lag3, 3),
       ew_uni_oos_retention_approx = num(ew$oos_retention_approx, 4),
       cap_tier_weight_share = ct$weight_share_avg,
       cap_tier_contrib = ct$contrib_gross_annualized)
}
paired_of <- function(p) {
  x <- R$paired[[p]]
  list(paired_t_nw = num(x$paired_t_nw, 3), n_months = x$n_months,
       mean_d_annualized_pct = num(100 * x$mean_d_annualized, 3),
       sub_pre2015 = num(x$sub_pre2015, 2), sub_2015_19 = num(x$sub_2015_19, 2),
       sub_2020p = num(x$sub_2020p, 2), sub_post2017 = num(x$sub_post2017, 2))
}
verdict_of <- function(t) {
  if (!is.finite(t)) "NA"
  else if (t >= 2.0) "REPLACE_CANDIDATE (도훈 confirm 필요)"
  else if (t >= 1.0) "DIRECTIONAL_POSITIVE (교체 근거 부족)"
  else if (t > -1.0) "NULL_TUNING (무효)"
  else "NEGATIVE (정제가 손해 — no-flip, 기전 기록)"
}
PT <- lapply(setNames(PAIRS$pair, PAIRS$pair), paired_of)
ARM <- lapply(setNames(c(PAIRS$base, PAIRS$tuned), c(PAIRS$base, PAIRS$tuned)), arm_stats)

cormat_l <- function(M) { l <- as.list(as.data.frame(round(M, 3))); l }

esc_p2 <- list(escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT_D20260802_009/run_wt009_tuned.R (path efficiency 252/21)",
  walk_forward = TRUE)
esc_p3 <- list(escape_type = "SPECIAL_OP",
  op_code_path = "stage_artifacts/WT_D20260802_009/run_wt009_tuned.R (EWMA hl63 w252)",
  walk_forward = TRUE)

eb_ast <- function(field) {
  leaf <- list(leaf = "FIELD", source = "factor_db_monthly", field = field)
  ts_sd <- list(op = "TS_STD", args = list(leaf, 36))
  var36 <- list(op = "MUL", args = list(ts_sd, ts_sd))
  wgt <- list(op = "DIV_GUARD", args = list(1, list(op = "ADD", args = list(1, var36))))
  list(op = "MUL", args = list(leaf, wgt))
}

factors <- list(
  list(factor_id = "V01_SECREL", role = "tuned_variant_paired_ab", restatement_exposure = 1,
       ast = list(op = "CS_ZSCORE", args = list(list(op = "CS_NEUTRALIZE",
         args = list(list(leaf = "FIELD", source = "factor_db_monthly", field = "V01_BM"),
                     "Sector"), params = list(min_group = 8, small_to = "OTHER_POOL"))))),
  list(factor_id = "M01_PATHQ", role = "tuned_variant_paired_ab", restatement_exposure = 0,
       ast = list(op = "CS_ZSCORE", args = list(list(op = "CS_WINSORIZE", args = list(
         list(leaf = "SPECIAL_OP", field = "signed_path_efficiency_252_21",
              op_code_path = esc_p2$op_code_path, walk_forward = TRUE,
              escape_contract = esc_p2), 3), params = list(sd = 3))))),
  list(factor_id = "D03_EWMA", role = "tuned_variant_paired_ab", restatement_exposure = 0,
       ast = list(op = "CS_ZSCORE", args = list(list(op = "CS_WINSORIZE", args = list(
         list(leaf = "SPECIAL_OP", field = "neg_ewma_vol_hl63_w252",
              op_code_path = esc_p3$op_code_path, walk_forward = TRUE,
              escape_contract = esc_p3), 3), params = list(sd = 3))))),
  list(factor_id = "Q01_EB", role = "tuned_variant_paired_ab", restatement_exposure = 1,
       ast = eb_ast("Q01_GPA")),
  list(factor_id = "V06_EB", role = "tuned_variant_paired_ab", restatement_exposure = 0,
       ast = eb_ast("V06_fDY")))

fs <- function(fam, proxy, formula, lag, neut, rat, refs, src) list(
  factor_family = fam, proxy = proxy, formula = formula, lag_rule = lag,
  winsorization = "3std (base는 registry 1/99+clip3 표준)", neutralization = neut,
  economic_rationale = rat, weight_theta = NA, source = src,
  redundancy_cluster_id = paste0(fam, "_cluster"), references = refs)

factor_specs <- list(
  fs("Value", "V01_SECREL vs V01_BM",
     "z_sec = (z - mean_sector)/sd_sector (월별, min8, 소섹터 풀)",
     "quarterly+45d / annual 3-31 (registry)", "sector",
     "B/M 수준의 산업 회계-집약 이질성 제거 — universe-z 상위는 섹터 정적 베팅. 실측: 전제 확증(HHI t+3.34)이나 섹터 베팅 성분 자체가 수익 원천이어서 paired -0.77",
     list("Asness-Porter-Stevens 2000"), "db_derived"),
  fs("Momentum", "M01_PATHQ vs M01_Mom_12_1",
     "E = sum(log(1+Ret)) / sum(|log(1+Ret)|), 창 [n-251,n-21], n=252, 유효>=150",
     "price t-1 (창 = sig_date 이하)", "none",
     "frog-in-the-pan: 연속 드리프트 모멘텀이 점프-주도 대비 지속 — 실측 paired +2.03(문턱 충족)이나 F2 반증 미통과(t+1.05)로 기전 미확증",
     list("Da-Gurun-Warachka 2014 (RFS)"), "new_designed"),
  fs("LowVol", "D03_EWMA vs D03_RealVol",
     "sigma2 = sum(w r^2)/sum(w), w=0.5^(age/63), 창 252행 n>=120, raw=-sigma",
     "price t-1", "none",
     "vol clustering — EWMA가 미래 1개월 vol의 우월 추정기(F3 승률 92%, MSE -26%). 그러나 저변동-롱 top-25 소비 프레임 자체가 손실(base -1.43)이라 순도 상승 = 손실 순화(paired -1.74)",
     list("Engle 1982", "RiskMetrics 1996"), "new_designed"),
  fs("Quality", "Q01_EB vs Q01_GPA",
     "tuned = z / (1 + Var_36m(z_{t-1..t-36})), min12, 이력부족=CS중앙 w",
     "quarterly+45d / annual 3-31 (registry)", "none",
     "회계 추정 노이즈의 EB 수축(Stein) — 노이즈 식별은 강성립(F4 t+13.4)이나 tau2=1 온건 수축은 방향 양성(+1.14)에 그침",
     list("Stein 1956", "Efron-Morris 1975"), "db_derived"),
  fs("Dividend", "V06_EB vs V06_fDY",
     "P4 동일 수식 — 노이즈 원천 = 컨센서스 실효성(급락+미갱신 DPS value trap)",
     "consensus T-1 선언 (registry known_discrepancy 병기)", "none",
     "노이즈 식별 강성립(F5 t+44.6)이나 수축이 수익 손해(paired -1.36) — 극단 불안정 고배당의 위험 프리미엄이 실현되는 표본. 방어 렌즈(AX-001)에서는 소폭 개선(MDD 47.3→46.5, CRISIS active -1.13→-0.91%/월)",
     list("Stein 1956"), "db_derived"))

pkg <- list(
  task_id = "WT-D20260802_009",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",

  hypothesis = list(
    statement = paste0(
      "대표 스마트베타 5종(V01_BM/M01/D03/Q01_GPA/V06_fDY)의 registry 표준 정의를 유지한 채 ",
      "추정·정규화·가중의 수학만 고도화하면(팩터당 1개 사전등록 기법) top-25 EW 실현 net active가 ",
      "개선된다 — 팩터별 paired A/B 5개 독립 가설. 사전등록 stage_artifacts/WT_D20260802_009/preregistration.json ",
      "(측정 전 고정, no-flip·no-sweep 조항 포함)."),
    mechanism = list(
      agent = paste0("팩터별 측정 노이즈 주체: 섹터 회계-집약 이질성(P1) / 점프-주도 경로 조성(P2) / ",
        "구식 등가중 vol 추정(P3) / 회계 일회성 노이즈(P4) / 미갱신 컨센서스 DPS(P5) — 각 pair 상세는 factor_specs"),
      friction = paste0("스크리너 관행의 표준화 고착(등가중 sd·universe-z·액면 소비) — 종목별 신뢰도/경로/섹터 ",
        "구조를 반영하는 계산 비용이 정제를 지연. KR 공매도 제약이 과대평가측 즉시 조정을 차단"),
      path = "측정 순도 상승 → top-25 랭킹의 참-신호 비중 증가 → 월말 신호 → 익월 실현 active 개선"),
    falsification = paste0(
      "성과-독립 4종 사전등록: F1 섹터HHI(base top-25 섹터집중, A1 rawdata Sector 리프) 실측 t=+3.34 지지 / ",
      "F2 jump기여 차별화(가격 리프) t=+1.05 미지지 — P2 기전 미확증 / F3 EWMA 익월 vol 예측 MSE(가격 리프) ",
      "승률 92% 지지(t+1.03) / F4·F5 sigma2의 익월 z-이동 예측(factor_db 리프) t=+13.4/+44.6 강지지"),
    regime_scope = list(
      holds_in = list("RISK_ON", "NEUTRAL"),
      weakens_or_reverses_in = list("CRISIS"),
      boundary_rationale = paste0(
        "위기 국면 공통 청산 충격은 횡단면 측정-순도 차이를 압도 — 실측: CRISIS에서 양 arm active 동반 음수, ",
        "paired 차이 판별력 소실 (AX-001 표 참조). P2 개선의 pre2015 편중(+2.84 vs 2015-19 -0.85)은 사전 미도출 — 정직 기재"))),

  factors = factors,
  combination_rule = "single_factor",
  verdict = "designed",

  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "factor_db_monthly:V01_BM,Q01_GPA", availability_rule = "regulatory: quarterly+45d, annual 익년3/31 (C4)", restatement_prone = TRUE),
      list(leaf = "factor_db_monthly:M01_Mom_12_1,D03_RealVol", availability_rule = "fixed: T-1 (Date<=sig_d)", restatement_prone = TRUE),
      list(leaf = "factor_db_monthly:V06_fDY", availability_rule = "fixed 선언 T-1 — registry known_discrepancy(제공시각 메타 부재) 승계", restatement_prone = FALSE),
      list(leaf = "A1_rawdata:Ret", availability_rule = "fixed: t-1 종가 확정. 저장 Ret 참값 사용(재계산 금지 준수)", restatement_prone = TRUE),
      list(leaf = "A1_rawdata:Sector", availability_rule = "월말 스냅샷 (t 시점 분류)", restatement_prone = FALSE)),
    verdict = "clean",
    verdict_rationale = paste0(
      "C1: 전 튜닝이 trailing 결정론(적합 파라미터 0, full-sample 통계 없음 — EB 분산은 t-1..t-36, ",
      "orientation 상속은 신호간 관계로 수익 무참조). C15: base는 load_month_factors 유일 관문 ",
      "(WT-004 패널과 parity — 정렬 165개월 diff 0, stale 93개월은 컴파일러 결함으로 규명·별건 발행). ",
      "lag1 스트레스: tuned 감쇠가 base와 대칭(P2 -44% vs base M01 -46%) — 차등 누출 지문 없음. ",
      "F3 반증만 미래 21d 사용(사후 진단 전용, 신호 비유입).")),

  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_009/tuned_panel.parquet (5 tuned) + base_panel.parquet (registry 5)",
  factor_specs = factor_specs,

  diagnostics = list(
    canonical_port_t_nw_lag3 = num(R$bt$M01_PATHQ$portfolio_alpha_t_nw_lag3, 3),
    canonical_port_t_pvalue = num(R$bt$M01_PATHQ$portfolio_alpha_t_pvalue, 4),
    canonical_n_months = R$bt$M01_PATHQ$n_months,
    metric_type = "canonical_screen",
    primary_carrier_note = "package 스키마상 대표 1계열 = M01_PATHQ(유일 문턱 통과). 라운드 판정은 아래 paired_ab_table 5쌍 전체",
    paired_ab_table = PT,
    paired_verdicts = lapply(PT, function(x) verdict_of(x$paired_t_nw)),
    arm_stats = ARM,
    correlation_5x5 = list(
      common_months = length(R$common_m),
      base = cormat_l(R$cor_base), tuned = cormat_l(R$cor_tuned),
      mean_abs_offdiag_base = num(mean(abs(R$cor_base[upper.tri(R$cor_base)])), 3),
      mean_abs_offdiag_tuned = num(mean(abs(R$cor_tuned[upper.tri(R$cor_tuned)])), 3),
      pair_self_cor = as.list(setNames(round(R$pair_selfcor, 3), PAIRS$pair)),
      breadth_verdict = "튜닝이 팩터 간 상관을 낮춤(0.209→0.145) — breadth 훼손 없음, P1 섹터-상대화가 최대 기여"),
    ax001_conditional = lapply(R$ax001, function(x) list(
      mdd = num(x$mdd, 4),
      regime = lapply(seq_len(nrow(x$regime)), function(i) list(
        regime = x$regime$Category[i], n = x$regime$n[i],
        mean_active = num(x$regime$mean_active[i], 5), t_nw = num(x$regime$t_nw[i], 2))))),
    lag1_stress = lapply(R$lag1, num, d = 3),
    lag1_base_m01 = 0.70,
    falsification_tests = list(
      F1_sector_hhi = list(base = num(R$fals$f1$hhi_base, 4), tuned = num(R$fals$f1$hhi_tuned, 4),
        t_diff = num(R$fals$f1$t_diff, 2), verdict = "SUPPORTED"),
      F2_jump_contrib = list(base = num(R$fals$f2$jc_base, 4), tuned = num(R$fals$f2$jc_tuned, 4),
        t_diff = num(R$fals$f2$t_diff, 2), verdict = "NOT_SUPPORTED — P2 기전 미확증 (challenge C1)"),
      F3_vol_mse = list(mse_sd = R$fals$f3$mse_sd, mse_ewma = R$fals$f3$mse_ew,
        t_diff = num(R$fals$f3$t_diff, 2), ewma_win_share = num(R$fals$f3$win_share, 3),
        verdict = "SUPPORTED (승률 92%, t는 위기월 팻테일로 약함)"),
      F4_eb_quality = list(rho = num(R$fals$f4$mean_rho, 3), t = num(R$fals$f4$t_nw, 2), verdict = "SUPPORTED"),
      F5_eb_dividend = list(rho = num(R$fals$f5$mean_rho, 3), t = num(R$fals$f5$t_nw, 2), verdict = "SUPPORTED")),
    advisory = lapply(R$diag, function(d) list(rank_ic = num(d$rank_ic, 5), icir = num(d$icir, 4),
      monotonicity = num(d$monotonicity, 3), ic_pre2015 = num(d$ic_pre2015, 4),
      ic_2015_2019 = num(d$ic_2015_2019, 4), ic_2020p = num(d$ic_2020p, 4))),
    rank_ic = num(R$diag$M01_PATHQ$rank_ic, 5),
    icir = num(R$diag$M01_PATHQ$icir, 4),
    harvey_t_stat = num(R$diag$M01_PATHQ$ic_t, 3),
    monotonicity = num(R$diag$M01_PATHQ$monotonicity, 3),
    subperiod_stability = NA,
    turnover_proxy = num(R$bt$M01_PATHQ$turnover_annual, 2),
    post_neutralization_ic = NA,
    ast_sidecar_live_with_ast = list(before = 36, after = 47),
    n_iterations = 1, n_trials = 5, selection_type = "preregistered_paired_ab",
    deflated_sharpe_ratio = NA,
    dsr_note = paste0("5쌍 = 독립 사전등록 가설(팩터별 1튜닝, argmax 없음) — sweep 아님, DSR 게이트 비발동. ",
      "family-wise caveat: 독립 null 5개에서 max t>=2.0 확률 ~11% (challenge C2 ACCEPT — 정직 병기)")),

  selection_objective = "canonical_port_t",
  alpha_discovery_count = 0,

  challenge_flags = list(
    list(id = "CF-01", severity = "HIGH",
         flag = paste0("P2 교체 후보는 '통계 문턱 충족(+2.03)·기전 미확증' — F2 반증 t+1.05 미통과, ",
           "개선 pre2015 편중(+2.84/-0.85/+0.96), 저변동 tilt 대안설명 잔존(diff-cor +0.108). ",
           "교체 confirm 전 후속 사전등록 기전 검증 권고 (challenge_note C1 PARTIAL)")),
    list(id = "CF-02", severity = "MEDIUM",
         flag = "family-wise: 5쌍 중 문턱 통과 1건 — 독립 null 하에서도 ~11% 확률 사건 (C2 ACCEPT)"),
    list(id = "CF-03", severity = "MEDIUM",
         flag = paste0("1차 측정 무효 사고: 유니버스 선-제한 누락 + canonical liq 'adv결측=통과' 시맨틱 결합 ",
           "→ top-25 비유니버스 오염(포트 연vol 1.5% 물리불가로 적발, random 통제로 확증) — 수리 후 전량 재측정, ",
           "설계·문턱 변경 0 (C3 documented)")),
    list(id = "CF-04", severity = "MEDIUM",
         flag = paste0("P3: EWMA는 우월 추정기(F3 승률 92%)이나 paired -1.74 — 저변동-롱 top-25 소비 프레임 자체가 ",
           "손실(base -1.43, IC +0.042인데 PORT_t 음수 = IC→PORT_t 전이 벽 재확인). 소비처는 리스크 모델 이식이 정도 (C4)")),
    list(id = "CF-05", severity = "LOW",
         flag = "P4/P5 EB tau2=1 온건 수축은 저검정력(self-cor 0.994+) — '온건 파라미터화의 무효'로 한정 해석 (C5)"),
    list(id = "CF-06", severity = "INFO",
         flag = paste0("병렬 발견 2건: ast_compile factor_db_monthly 1개월 stale(93/258달, task_5fef96aa 발행) / ",
           "registry D03 정렬 실효 방향 = 저변동 롱 278/295개월 (WT-004 기록과 상반 서술 — 소비자 재확인 필요)"))),

  verdict_summary = list(
    result = "paired_ab_5_measured__1_replace_candidate_with_caveat__breadth_improved",
    gate_eligible = FALSE,
    statement = paste0(
      "정의-내 수리 정제 5쌍 paired A/B (295/263개월, canonical top-25 EW cap-w): ",
      "P2 모멘텀 경로효율 +2.03 유일 문턱 충족(단 기전 반증 미통과 — CF-01), P4 퀄리티 EB +1.14 방향 양성, ",
      "P1/P3/P5 무효 또는 음수(-0.77/-1.74/-1.36). 튜닝 축의 정직 평가: 개별 수익 개선 레버로는 약함 — ",
      "그러나 5x5 상관 0.209→0.145 개선(P1 주도)과 반증 4/5 지지로 '측정 순도 상승' 자체는 실증. ",
      "순도 상승이 수익으로 전이되지 않는 지점(P3·P1)은 base 팩터의 수익 원천이 '순수 신호'가 아니라 ",
      "구조 베팅(섹터·고변동)에 있었음을 역으로 실측 — 이것이 본 라운드의 핵심 지식. 현 config 수렴 + next_probe 5건."),
    consumption_scan_7 = list(
      factor_ranking = "P2 조건부(도훈 confirm + 후속 기전 검증), P4는 다팩터 문맥 재평가 후보",
      universe_filter = "비적합 (정제는 랭킹 변환 — 필터 신호 아님)",
      overlay_regime_input = "비적합 — CRISIS에서 paired 판별력 소실 실측",
      risk_model_beta_budget = "적합 — EWMA vol(F3 승률 92%)을 Sigma 추정·vol-targeting 입력으로 이식 (NP-2)",
      monitoring_signal = "적합 — EB sigma2(F4/F5 강성립)를 보유종목 신호 신뢰도 모니터로 (NP-3 연계)",
      screening_label = "P1 섹터-상대 value = 풀 breadth 기여자(상관 최대 감소) — 다팩터 합성 문맥 라벨",
      cross_mode_transfer = "RAMP 순수팩터 추출에 P1 섹터-상대화 규약 이식 후보"),
    next_probe = list(
      list(id = "NP-1", priority = "P1",
           probe = paste0("P2 기전 확증 라운드: 경로효율의 vol-성분을 명시 직교화(E를 D03z에 월별 CS 잔차화)한 ",
             "순수 경로-질 신호 사전등록 재검증 — 잔차판 paired가 0으로 죽으면 P2 개선은 vol-tilt 아티팩트로 확정, ",
             "생존하면 교체 근거 완성"),
           rationale = "CF-01 해소의 유일 경로 — 교체 confirm의 전제"),
      list(id = "NP-2", priority = "P1",
           probe = "EWMA vol(hl63)을 risk-research Sigma 추정기·vol-targeting 입력으로 이식 — F3 확립 능력(익월 vol 예측 -26% MSE)을 소비면이 맞는 곳에 배선. 알파 랭킹 소비는 손실 프레임 실측으로 종료",
           rationale = "능력이 확립된 축(예측)과 소비된 축(랭킹)의 불일치 해소"),
      list(id = "NP-3", priority = "P2",
           probe = "EB 강수축판: 월별 empirical tau2 = max(0, var_cs - median(sigma2))로 재사전등록 (P4 +1.14가 온건 수축에서 나온 방향성 — 수축 강도의 dose-response 확인)",
           rationale = "C5 저검정력 한계 해소"),
      list(id = "NP-4", priority = "P2",
           probe = "P1 섹터-상대 value를 다팩터 등가중 풀(base 4 + V01_SECREL)로 WT-003 breadth 프레임 재측정 — 상관 감소(0.209→0.145)가 풀 수준 IR로 전이되는지",
           rationale = "P1의 가치는 standalone이 아니라 breadth — 맞는 소비면에서 재평가"),
      list(id = "NP-5", priority = "P3",
           probe = "canonical_screen_bt 'adv결측=통과' 시맨틱에 유니버스-검증 assert 추가 제안(scores가 returns_dt 커버리지의 k배 초과 시 warn) — 본 라운드 1차 측정 무효 사고 재발 방지",
           rationale = "CF-03 배관 재발 방지"))),

  method_shopping_log = list(alpha_agent = list(
    candidates_tried = 5,
    method_log = lapply(seq_len(nrow(PAIRS)), function(i) list(
      name = paste0(PAIRS$pair[i], ":", PAIRS$tuned[i], "_vs_", PAIRS$base[i]),
      canonical_port_t = num(R$bt[[PAIRS$tuned[i]]]$portfolio_alpha_t_nw_lag3, 3),
      paired_t = num(R$paired[[PAIRS$pair[i]]]$paired_t_nw, 3),
      selected = PAIRS$pair[i] == "P2_MOMENTUM",
      note = "5쌍 전부 사전등록 1-tuning — 상호 선택/argmax 없음, selected는 문턱 통과 표시일 뿐")))))

write_json(pkg, file.path(MB, "alpha_package.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_package.json 저장")

val <- list(
  task_id = "WT-D20260802_009",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen",
  gate_eligible = FALSE,
  selection_type = "preregistered_paired_ab", n_trials = 5,
  preregistration = "stage_artifacts/WT_D20260802_009/preregistration.json (측정 전 고정)",
  paired_ab_table = PT,
  paired_verdicts = pkg$diagnostics$paired_verdicts,
  arm_stats = ARM,
  correlation_5x5 = pkg$diagnostics$correlation_5x5,
  ax001_conditional = pkg$diagnostics$ax001_conditional,
  falsification_tests = pkg$diagnostics$falsification_tests,
  lag1 = list(tuned = pkg$diagnostics$lag1_stress, base_m01 = 0.70),
  universe_comparison = list(
    note = "배포 유니버스(K200∪KQ150) 직접 측정 — v2 확장 비교는 ICIR attenuation 진단 비해당(paired 설계가 유니버스 공통이라 상쇄)",
    dual_basis_by_arm = lapply(ARM, function(a) list(cap_w = a$port_t, ew_uni = a$ew_uni_t,
                                                     ew_post2017 = a$ew_uni_post2017_t)),
    cap_tier_by_arm = lapply(ARM, function(a) list(weight_share = a$cap_tier_weight_share,
                                                   contrib = a$cap_tier_contrib))),
  graduation_hard_gates = list(
    portfolio_alpha_t_nw = list(required = 2.95,
      observed_best_canonical = num(R$bt$M01_PATHQ$portfolio_alpha_t_nw_lag3, 3),
      status = "FAIL", note = "canonical screening 실측 — forge 미제출(자본 판정 아님). 라운드 목적은 paired A/B"),
    oos_retention = list(required = 0.7,
      observed_approx_ew_best = num(R$bt$M01_PATHQ$diag_ew_universe$oos_retention_approx, 4),
      status = "DIAG_ONLY", note = "진단 근사 — 권위는 essence_score"),
    calmar = list(required = 0.64, observed = NA, status = "NOT_COMPUTED", note = "forge 미제출")),
  production_constraints = list(turnover_annual_limit = 11.0,
    observed_by_arm = lapply(ARM, function(a) a$turnover_annual),
    verdict = "전 arm 1.3~7.9x/yr 수준 환산(연 131~789%) — M01 계열이 상한 근접, 교체 시 TO 증분(+67%p) 명기"),
  incident_log = list(
    first_measurement_invalidated = paste0("유니버스 선-제한 누락 → canonical top-25 비유니버스 오염(연vol 1.5% ",
      "물리불가 + random-25 t -3.2로 적발) → 수리 후 전량 재측정. 설계 변경 0 — challenge_note C3"),
    parallel_defect_found = "ast_compile factor_db_monthly 1개월 stale (task_5fef96aa)"),
  sidecar_live_with_ast = list(before = 36, after = 47))
write_json(val, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null", digits = 8)
say("alpha_validation.json 저장")

# lineage (package write 이후 — L-194 순서)
try({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(
    task_id = "WT-D20260802_009", package_type = "alpha_package",
    method_selected = "5쌍 사전등록 paired A/B (V01_SECREL/M01_PATHQ/D03_EWMA/Q01_EB/V06_EB vs registry 표준)",
    input_file_paths = c(".cache/RAWDATA.parquet",
                         file.path(OUT, "base_panel.parquet"),
                         file.path(OUT, "tuned_panel.parquet"),
                         file.path(OUT, "preregistration.json"),
                         ".cache/unified_regime_signal.parquet"))
  say("lineage 기록 완료")
}, silent = FALSE)

st <- list(task_id = "WT-D20260802_009", current_phase = "ALPHA_DONE",
           updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), blocker = NULL)
write_json(st, file.path(MB, "status.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
gl <- fromJSON(file.path(MB, "governance_log.json"), simplifyVector = FALSE)
gl$events <- c(gl$events, list(list(
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
  agent = "alpha-research",
  action = "ALPHA_PACKAGE_EMITTED",
  summary = paste0("스마트베타 5종 수리 튜닝 paired A/B — P2 +2.03 유일 문턱 통과(기전 미확증 caveat), ",
    "P4 +1.14 방향 양성, P1/P3/P5 무효·음수. 상관 0.209→0.145 개선. 반증 4/5 지지. ",
    "1차 측정 무효 사고 수리·재측정. challenge_note 7 concern. next_probe 5건."))))
write_json(gl, file.path(MB, "governance_log.json"), auto_unbox = TRUE, pretty = TRUE, null = "null")
say("status/governance 갱신 완료")
