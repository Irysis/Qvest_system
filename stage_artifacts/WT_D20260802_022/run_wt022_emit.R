# =============================================================================
# run_wt022_emit.R — WT-D20260802_022 산출물 발행 (측정 재실행 없음 — rds 소비)
#   alpha_package.json(AST v1.1) → lineage → alpha_validation.json → parquet → charts
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(ggplot2); library(scales)
  library(lubridate)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_022")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_022")
say <- function(fmt, ...) cat(sprintf(paste0("[wt022e] ", fmt, "\n"), ...))

res <- readRDS(file.path(OUT, "wt022_eval_results.rds"))
DD  <- readRDS(file.path(OUT, "wt022_decomp.rds"))
MECH <- readRDS(file.path(OUT, "wt022_mechanism_dropped_vs_added.rds"))
pri <- res$primary; dg <- res$diagnostics

# ── 1. 배제 신호 패널 (stage artifact parquet) ───────────────────────────────
alpha_scores <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))
alpha_scores[, Date := as.Date(Date)]
MAX5 <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_014/alpha_scores.parquet"))
MAX5[, Date := as.Date(Date)]
MAX5 <- MAX5[is.finite(max5), .(d0 = Date, Ticker, max5)]
MAX5[, sig_ym := format(as.Date(format(d0, "%Y-%m-01")) %m+% months(1), "%Y-%m")]
AS <- alpha_scores[!is.na(score_eff), .(Date, Ticker, score_eff)]
AS[, sig_ym := format(Date, "%Y-%m")]
P <- merge(AS, MAX5[, .(sig_ym, Ticker, max5, d0)], by = c("sig_ym", "Ticker"), all.x = TRUE)
P[, `:=`(thr = { v <- max5[is.finite(max5)]
                 if (length(v) >= 30L) quantile(v, 0.90, type = 7, names = FALSE) else Inf }),
  by = Date]
P[, excluded_x10 := is.finite(max5) & max5 >= thr]
wb <- res$series$weights_base[, .(Date = sig_label, Ticker, in_top20_base = TRUE)]
wf <- res$series$weights_f10[, .(Date = sig_label, Ticker, in_top20_filt = TRUE)]
P <- merge(P, wb, by = c("Date", "Ticker"), all.x = TRUE)
P <- merge(P, wf, by = c("Date", "Ticker"), all.x = TRUE)
P[is.na(in_top20_base), in_top20_base := FALSE]
P[is.na(in_top20_filt), in_top20_filt := FALSE]
write_parquet(P[, .(Date, Ticker, score_eff, max5, signal_d0 = d0, excluded_x10,
                    in_top20_base, in_top20_filt)],
              file.path(OUT, "alpha_scores.parquet"))
say("alpha_scores.parquet: %d행 (%d 신호월)", nrow(P), uniqueN(P[!is.na(max5), Date]))

# alpha_vector: 마지막 max5 가용 sig월 배제 신호 (−z(max5)) — 기록용 (실코드 소비 부정 판정)
last_sig <- P[is.finite(max5), max(Date)]
LV <- P[Date == last_sig & is.finite(max5)]
LV[, z := (max5 - mean(max5)) / sd(max5)]
alpha_vec <- as.list(setNames(round(-LV$z, 4), LV$Ticker))
conf_vec  <- as.list(setNames(rep(0.15, nrow(LV)), LV$Ticker))

# ── 2. alpha_package.json (AST v1.1) ─────────────────────────────────────────
pkg <- list(
  task_id = "WT-D20260802_022",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = "MAX5_63 상위 10% 배제(복권형 제외)가 현 PG2 실코드 경로(STR_1715_on_M4_R05_noLayer4_PG2: score_eff top-20 linear-tilt λ=1.5 + TOphi=3 + M4×β_R05_V5)의 net active를 개선한다.",
    mechanism = list(
      agent = "개인투자자 복권 선호 수요 (고 MAX5 종목의 체계적 과대평가) — Bali-Cakici-Whitelaw 2011 MAX effect",
      friction = "KR 공매도 제약 — 고평가 복권형 종목을 숏으로 지울 수 없어 배제만이 long-only 소비 수단",
      path = "익월 평균수익이 낮은 복권형 종목을 선별 유니버스에서 제거 → 포트 평균수익·꼬리 개선"
    ),
    falsification = "배제 대상(후보 내 max5 상위)의 익월 수익이 대체 종목(차순위 랭크)보다 낮지 않으면 기전 기각. ★실측: 배제 종목이 대체 종목보다 +1.16%/월 우위(NW t +1.54, n=248) — 실코드 top-랭크 후보 조건부에서 기전 '기각'. (WT-020 정합: 전기간 수익 스프레드 t −0.12 = 무차별인데, alpha-rank 조건부에서는 양(+)의 승자 표지)",
    regime_scope = list(
      holds_in = list("NEUTRAL"),
      weakens_or_reverses_in = list("CRISIS", "RISK_ON"),
      boundary_rationale = "WT-020: MAX5 상위군은 crash·boom 양측 꼬리 확대 — 스트레스 국면 상방 지배(CAUTION ret_spread +1.76%/월). 배제는 평균수익 소비."
    )
  ),
  factors = list(list(
    factor_id = "F1_max5_exclusion_realcode",
    ast = list(op = "WHERE",
      ast_note = "WHERE(x=score_eff, cond=0.90-CS_RANK(max5)) — 상위 10% 배제를 production 후보 프레임에 적용. WT-016 F1과 동일 규칙, 소비 기질만 실코드 경로로 교체",
      args = list(list(leaf = "STORED_SCORE",
        field = "score_eff (WT_D20260425_010 — production alpha lineage, forward_weights_R05_noLayer4.R이 직접 소비하는 패널)",
        escape_contract = list(escape_type = "STORED_SCORE",
          panel_path = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
          vintage = as.character(res$vintage[input == "alpha", mtime]),
          production_parity_verified = TRUE,
          parity_evidence = "GATE A: 재현 루프 vs production 03_period_returns.csv(20260802_LIVE) 271/271개월 max|Δret| 5.13e-16")),
        list(leaf = "SPECIAL_OP",
        field = "max5_63 (WT-010 ot_panel 동결분 — 63거래일 MAX5, 창 종점 d0=전월말)",
        escape_contract = list(escape_type = "SPECIAL_OP",
          code_path = "stage_artifacts/WT_D20260802_010 (동결 패널, 재계산 없음)",
          walk_forward = "d0 < 첫 매수일 구조 보장 + assert_overlay_pit 256/256 PASS + 위반주입 발화 확인")))),
    role = "exclusion_filter",
    restatement_exposure = 0L
  )),
  combination_rule = "single_factor",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = list(
      list(leaf = "SPECIAL_OP:max5_63", availability_rule = "fixed: 저장 일간 Ret, 창 종점 d0(전월말) < start_d(첫 매수일). C5/C10", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE:score_eff", availability_rule = "production 코드 직소비 패널 — GATE A parity로 vintage 무결 실증 (§7b)", restatement_prone = FALSE),
      list(leaf = "STORED_SCORE:R05_Tail_Risk_Z", availability_rule = "β_R05 재산출: expanding past-only q20 (C1), realized_ym=sig+1m 조인 (run_layer5 VERBATIM)", restatement_prone = FALSE)),
    verdict = "clean"
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  alpha_vector_note = sprintf("마지막 신호월(%s) 배제 신호 −z(max5) — 기록용. 판정이 WITHDRAW이므로 실코드 경로 소비 금지. confidence 0.15 flat (부정 판정 반영)", as.character(last_sig)),
  alpha_discovery_count = 0L,
  discovery_of = "WT-D20260802_014",
  signal_matrix_ref = "stage_artifacts/WT_D20260802_022/alpha_scores.parquet",
  factor_specs = list(list(
    factor_family = "lottery_demand",
    proxy = "MAX5_63 (63d mean of top-5 daily returns)",
    formula = "cross-sectional quantile(0.90) exclusion in production candidate frame",
    lag_rule = "d0 = 전월말 거래일 (홀딩월 시작 전, C5/C10)",
    winsorization = "none (rank/quantile 기반)",
    neutralization = "none",
    economic_rationale = "lottery preference mispricing (Bali et al. 2011) — 단 실측: 실코드 top-랭크 조건부에서는 승자 표지로 반전 (기전 기각)",
    weight_theta = 0,
    references = list("Bali-Cakici-Whitelaw 2011 JFE", "WT-D20260802_010/014/016/020")
  )),
  diagnostics = list(
    canonical_port_t_nw_lag3 = NULL,
    canonical_port_t_note = "canonical_screen_bt 미사용 — 본 라운드 측정 프레임 = production 실코드 recon (§7b mandate). PORT_t는 아래 realcode 라벨 값 참조. 사유: 측정 대상이 표준 스크린이 아니라 배포 경로 자체",
    realcode_port_t_base = pri$port_t_base,
    realcode_port_t_filt = pri$port_t_filt,
    primary_delta_ir = pri$delta_ir,
    primary_paired_t_nw_lag3 = pri$paired_t,
    ir_base = pri$ir_base, ir_filt = pri$ir_filt,
    n_months_paired = pri$n,
    abs_base = pri$abs_base, abs_filt = pri$abs_filt,
    delta_ir_basis_label = "net_active_recon_v1 (recon net − 정본 KOSPI200 월복리, IR=mean/sd×√12) — WT-016 weighted_screen basis와 구분",
    metric_type = "realcode_recon (production parity-verified 재현 경로, backtested-등가; forge 계약 빌드는 비대상 — Δ 판정 라운드)",
    turnover_annual_base = dg$turnover$to_annual[1],
    turnover_annual_filt = dg$turnover$to_annual[2],
    rank_ic = NA, icir = NA, monotonicity = NA, subperiod_stability = NA,
    harvey_t_stat = NA,
    advisory_note = "rank-IC 계열 미산출 — 배제 필터(이진 개입)라 횡단면 IC 프레임 부적합. WT-010/014 진단 승계"
  ),
  selection_objective = "canonical_port_t",
  n_trials = 1L,
  selection_type = "preregistered_single_primary_chain",
  method_shopping_log = list(alpha_agent = list(candidates_tried = 1L,
    method_log = list(list(name = "MAX5_X10_realcode_full_path", selected = TRUE,
      note = "사전등록 단일 primary. X5/X20/regime-off/same-β/EW/lag1은 사전등록 진단 — 선택 비사용")))),
  challenge_flags = list(
    "판정 WITHDRAW: ΔIR −0.1489 (기준 <0) — 실배치 상신 철회",
    "WT-016 근사 프레임(+0.1284) 대비 부호 반전 — 낙관 편의 = +0.277 IR",
    "부호 반전 축 = 가중 규칙 (decomp: capnorm25 +0.158 / tilt·EW 전 config 음수)",
    "기전 기각: 배제 종목이 대체 종목보다 +1.16%/월 우위 (승자 컷)",
    "GATE B m4 6개월 불일치 = m4_extended.csv 08-02 재생성 귀속 (입력 vintage, 배선 무결)"
  ),
  verdict_summary = sprintf(
    "실코드 full-path ΔIR %+.4f (IR %.4f→%.4f), paired NW t %+.3f, n=%d → 사전등록 판정 WITHDRAW(상신 철회). 진단 7 arm 전부 음수. 기전: 실코드 top-랭크 조건부에서 MAX5 상위 = 승자 표지(배제-대체 스프레드 +1.16%%/월). 필터 유효 영역 = size-weighted screen 계층 한정(capnorm25 ΔIR +0.158, WT-014 재현).",
    pri$delta_ir, pri$ir_base, pri$ir_filt, pri$paired_t, pri$n)
)
write_json(pkg, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
say("alpha_package.json 발행")

# lineage (L-194: package write 후)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_022",
  package_type = "alpha_package",
  method_selected = "MAX5_X10_exclusion_realcode_full_path (preregistered single primary)",
  input_file_paths = c(
    "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
    "stage_artifacts/WT_D20260802_014/alpha_scores.parquet",
    ".cache/rawdata.parquet", ".cache/benchmark.parquet",
    "stage_artifacts/WT-D20260430_001_m4_extended.csv",
    "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet",
    "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
say("lineage 기록")

# ── 3. alpha_validation.json ─────────────────────────────────────────────────
val <- list(
  task_id = "WT-D20260802_022",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "realcode_recon (production_parity_verified 재현 경로 — GATE A max|Δ| 5.13e-16) — 라벨 병기",
  gate_eligible = FALSE,
  selection_type = "preregistered_single_primary_chain",
  n_trials = 1,
  preregistration = "stage_artifacts/WT_D20260802_022/preregistration.json (측정 전 고정)",
  input_vintage = res$vintage[, .(input, path, mtime)],
  parity_gates = list(
    A_stock_layer = list(pass = TRUE, n = 271, max_abs_dret = res$gates$A$max_dret,
      note = "재현 루프 vs production 03_period_returns.csv (run_id 20260802_LIVE) — production_parity_verified"),
    B_overlay_recon = list(pass = TRUE, beta_mismatch = 0, n = 269,
      m4_mismatch_months = 6, cor_vs_stored_23 = res$gates$B$cor_vs_23,
      diagnosis = "m4 6개월(2008-01/03/04·2009-06·2012-01/02) + ret |Δ|>1e-4 6개월 전수 = m4_extended.csv 08-02 재생성 + rawdata 07월 수리 이후 갱신 귀속 — 입력 vintage 차이, 배선 무결. 사전등록 분류: 측정 유효 지속"),
    C_pit_guard = list(pass = TRUE, note = "assert_overlay_pit 256/256 PASS + 위반 주입 시 stop() 발화 확인 (가드 생존)"),
    D_bench_anchor = list(pass = TRUE, jul_2026 = res$gates$D$jul_bm,
      note = "정본 .cache/benchmark.parquet — WT-020 플래그 자산(screen_inputs.rds bench) 미사용")
  ),
  primary = list(
    name = "PG2_realcode_MAX5_X10_exclusion_full_path",
    n_months = pri$n,
    delta_ir = pri$delta_ir, ir_base = pri$ir_base, ir_filt = pri$ir_filt,
    paired_t_nw_lag3 = pri$paired_t,
    mean_delta_active_monthly = pri$mean_d_monthly,
    port_t_base = pri$port_t_base, port_t_filt = pri$port_t_filt,
    abs_base = pri$abs_base, abs_filt = pri$abs_filt,
    delta_ir_basis = "net_active_recon_v1 (recon net − 정본 KOSPI200 월복리) — WT-016은 weighted_screen basis (비교 시 라벨 필수)",
    decision_rule = "ΔIR ≥ +0.05 ∧ t > 0 유지 / ΔIR < 0 철회 (사전 고정)",
    verdict = "WITHDRAW (상신 철회) — ΔIR -0.1489 < 0"
  ),
  approx_frame_bias = list(
    wt016_overlay_on_delta_ir = 0.1284, wt014_bare_delta_ir = 0.1692,
    realcode_full_path_delta_ir = pri$delta_ir, realcode_bare_delta_ir = dg$bare$delta_ir,
    optimism_bias_ir = round(0.1284 - pri$delta_ir, 4),
    verdict = "근사 프레임 낙관 편의 = +0.277 IR (부호 반전). overlay 유무는 원인 아님(bare arm도 -0.113)"
  ),
  mechanism_decomposition = list(
    question = "무엇이 base를 다르게 만들어 필터 부호를 뒤집었나 (Q-Lead 지시 #3)",
    method = "동일 하네스(production alpha panel·raw 윈도우·liq·15bps·벤치) 안에서 config 축만 교체 — 사후 진단, 선택 비사용",
    table = DD,
    attribution = "★부호 반전 축 = 가중 규칙. cap_norm(Size) top-25(WT-014 스타일)만 ΔIR +0.1579(WT-014 +0.1692 재현 — 점수 소스·수익 윈도우가 달라도 재현)이고, score-rank tilt(20/25종·TOphi 유무 불문)·EW 전부 음수. N(20↔25)·TOphi·overlay·점수 소스는 부호를 바꾸지 못함",
    mechanism_detail = list(
      dropped_vs_added_spread_monthly = 0.0116,
      dropped_vs_added_nw_t = 1.54, n = 248,
      dropped_mean = 0.0328, added_mean = 0.0212,
      note = "배제된 base top-20 종목이 대체 종목(차순위)보다 +1.16%/월 우위 — 실코드 프레임에서 필터는 '승자 컷'. cap_norm 프레임에서는 배제 대상이 소형주(OTHER tier)라 Size 가중상 거의 무게 0 → 평균 손실 없이 변동성만 제거되어 IR 상승(ΔIR +0.158인데 paired t −0.25 = 분모 효과). tier Δ기여: OTHER -4.46%/yr vs MEGA/MID 합 +1.0%/yr",
      systemic_lesson = "ΔIR은 base의 가중 규칙에 조건부인 국소량 — size-weighted 스크린에서 검증된 필터를 rank-weighted book에 이식할 수 없다 ('어느 base 위에서 잰 개선인가'). WT-016 parity STOP(cor 0.668)이 이 계층 차이의 조기 경보였음"
    )
  ),
  diagnostics_preregistered = list(
    d1_regime_off = dg$regime_off, d2_x05 = dg$x05, d2_x20 = dg$x20,
    d3_same_beta = dg$same_beta, d4_ew_dual_basis = dg$ew,
    d6_stock_layer_bare = dg$bare, d7_lag1_stress = dg$lag1,
    all_negative = TRUE,
    regime_decomposition_production = dg$regime_prod,
    regime_decomposition_unified = dg$regime_unified,
    d1_verdict = "국면조건부 해제(CRISIS/CAUTION off)도 더 나쁨(-0.155 vs -0.149) — WT-020 양측 꼬리와 정합: 실코드 손실원은 NORMAL(t -2.28) 승자 컷이라 위기 해제로 못 구함",
    cap_tier = dg$tier,
    turnover = dg$turnover,
    firing = dg$firing,
    beta_path_diff_months = dg$beta_path_diff_months,
    ax001_conditional = list(crisis_n = 3, crisis_mean_d = 0.0039,
      note = "production regime CRISIS n=3 — 판정 불가. unified CRISIS n=13 mean_d +0.0040 t 1.14 (위기월 소폭 양) — AX-001 조건부 병기: 필터는 위기에 살짝 돕고 평시에 크게 해침(발화월 비례 유해 구조와 상동)")
  ),
  next_probe = list(
    np1 = "FQ 등재: alpha-rank 조건부 MAX5 상호작용 — 실코드 top-랭크 후보 내 max5 상위 = 승자 표지(+1.16%/월, t 1.54, 유의 미달)를 FM(max5 × score_eff rank interaction)으로 확정. 유의 시 배제가 아니라 조건부 보정 신호(방향 반전 소비)",
    np2 = "WT-014/016 결과의 소비처 한정 재라우팅: size-weighted screen 계층(cap_norm 계열 모듈 — FR/RAMP size-weighted 소비면)에서만 유효. screen_route 라벨을 'size-weighted screen 전용'으로 부기",
    np3 = "63d 꼬리-변동성의 위험모델 소비(WT-020 NP 합류): capnorm IR 개선의 실체가 분모(변동성) 효과 → 배제가 아니라 Σ/β예산 입력이 정공 — risk-research 소비면 (frontier 살아있음)"
  ),
  revival_conditions = list(
    "book stock layer가 size-weighted(cap_norm 계열)로 교체되면 WT-014/016 결과 직접 이식 재검",
    "np1 상호작용 FM 유의(|t|≥2) 시 조건부 신호로 방향 반전 재도전",
    "score_eff와 max5의 상관 구조 변화(현재: top-랭크 조건부 승자 표지) 모니터링 신호 발화 시"
  ),
  consumption_face_7 = list(
    factor_ranking = "배제 신호 부정(본 라운드). 조건부 상호작용 미측정 → np1",
    universe_filter = "실코드 top-20 부정 (본 판정). size-weighted screen 한정 유효",
    overlay_regime_input = "국면조건부 해제도 열세(-0.155) — config-scoped 닫힘",
    risk_model_beta_budget = "63d tail-vol Σ 반영 — WT-020 NP 합류, 살아있음 (np3)",
    monitoring_signal = "MAX5 상위 편입 경보 무근거(승자 컷) — 닫힘",
    screening_label = "WT-014/016 screen_route를 size-weighted 전용으로 부기 (np2)",
    other_mode_transplant = "FR/RAMP size-weighted 모듈에는 WT-014 결과 이식 가능 (계층 일치 조건)"
  ),
  capital_claim = "없음 — book_state 무변경, governor 미접촉. 실배치 상신 철회는 '필터 미적용 현행 유지' 권고 (도훈 수동)"
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
say("alpha_validation.json 발행")

# ── 4. 차트 ──────────────────────────────────────────────────────────────────
PD <- res$series$PD
nav <- PD[order(anchor_date), .(anchor_date,
  base = cumprod(1 + r_b), filt = cumprod(1 + r_f))]
BMW <- res$series$BMW[anchor_date %in% PD$anchor_date][order(anchor_date)]
BMW[, bm_nav := cumprod(1 + fifelse(is.finite(bmw), bmw, 0))]
ch1 <- merge(nav, BMW[, .(anchor_date, bm_nav)], by = "anchor_date")
ch1_l <- melt(ch1, id.vars = "anchor_date", variable.name = "series", value.name = "nav")
ch1_l[, series := factor(series, c("base", "filt", "bm_nav"),
  c("현행 PG2 (무필터)", "복권필터 적용판", "KOSPI200"))]
g1 <- ggplot(ch1_l, aes(anchor_date, nav, color = series)) +
  geom_line(linewidth = 0.7) + scale_y_log10(labels = comma) +
  scale_color_manual(values = c("#1f77b4", "#d62728", "grey50")) +
  labs(title = "WT-022 실코드 recon NAV — 복권필터는 현 PG2를 해친다 (ΔIR −0.149)",
       subtitle = sprintf("paired 256m (2005-01~2026-04) | SR %.2f→%.2f | MDD %.1f%%→%.1f%%",
         pri$abs_base$SR, pri$abs_filt$SR, 100 * pri$abs_base$MDD, 100 * pri$abs_filt$MDD),
       x = NULL, y = "NAV (log)", color = NULL) +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")
ggsave(file.path(OUT, "charts/wt022_nav_recon.png"), g1, width = 9, height = 5.2, dpi = 130)

DD2 <- copy(DD)
DD2[, label := factor(config,
  c("realcode_tilt20_tophi", "tilt20_no_tophi", "tilt25_tophi", "ew25", "capnorm25_wt014_style"),
  c("실코드\ntilt20+TOphi", "tilt20\n(TOphi off)", "tilt25\n+TOphi", "EW25", "cap_norm25\n(WT-014 프레임)"))]
g2 <- ggplot(DD2, aes(label, delta_ir, fill = delta_ir > 0)) +
  geom_col(width = 0.62) +
  geom_hline(yintercept = 0, color = "grey30") +
  geom_text(aes(label = sprintf("%+.3f", delta_ir)), vjust = ifelse(DD2$delta_ir > 0, -0.5, 1.4), size = 3.4) +
  scale_fill_manual(values = c(`TRUE` = "#2ca02c", `FALSE` = "#d62728"), guide = "none") +
  labs(title = "부호 반전 축 = 가중 규칙 (동일 필터·동일 하네스, config만 교체)",
       subtitle = "cap_norm(Size)만 양수(+0.158, WT-014 +0.169 재현) — rank-tilt·EW 전부 음수 = '승자 컷'",
       x = NULL, y = "필터 ΔIR (bare, paired 256m)") +
  theme_minimal(base_size = 11)
ggsave(file.path(OUT, "charts/wt022_decomp_weighting.png"), g2, width = 8.5, height = 5, dpi = 130)
say("차트 2종 저장")

# ── 5. status / governance ───────────────────────────────────────────────────
write_json(list(task_id = "WT-D20260802_022", current_phase = "ALPHA_DONE",
                updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"),
                blocker = NULL),
           file.path(MB, "status.json"), pretty = TRUE, auto_unbox = TRUE, null = "null")
gl_path <- file.path(MB, "governance_log.json")
gl <- if (file.exists(gl_path)) fromJSON(gl_path, simplifyVector = FALSE) else list()
gl[[length(gl) + 1]] <- list(
  ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900"), actor = "alpha-research",
  event = "ALPHA_DONE",
  note = "실코드 full-path ΔIR -0.1489 (t -1.976) → 사전등록 WITHDRAW. 게이트 A/B/C/D PASS. 기전 분해: 부호 반전 축 = 가중 규칙 (capnorm만 +0.158). challenge_note.md 기록.")
write_json(gl, gl_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
say("status/governance 갱신. DONE")
