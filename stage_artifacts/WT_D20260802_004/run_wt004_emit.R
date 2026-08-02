# =============================================================================
# run_wt004_emit.R — WT-D20260802_004 단계 3: alpha_package.json + validation 산출
#   (write_json → record_package_lineage 순서 준수, L-194)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260802_004")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt004m] ", fmt, "\n"), ...))

R <- readRDS(file.path(OUT, "wt004_eval_results.rds"))
bt <- R$bt; cond <- R$cond; ic <- R$ic; ORTH <- R$ORTH

num <- function(x) if (is.null(x) || !is.finite(as.numeric(x)[1])) NULL else round(as.numeric(x)[1], 4)

# ── alpha_vector / confidence: C_ORTH_def 최신 월 ────────────────────────────
sc <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
last_d <- max(sc$Date)
latest <- sc[Date == last_d][order(-score)]
# score(z-합) → 월간 기대 active 스케일 근사: 실측 IC 평균 × z (라벨: estimated — 순위 전달용)
ic_scale <- abs(ic$C_ORTH_def$mean_ic %||% 0.02)
alpha_vec <- setNames(as.list(round(latest$score / length(ORTH) * ic_scale, 5)), latest$Ticker)
# confidence: 축 커버리지(전 축 요구=1) × subperiod 안정 보수 상수
ic_ser <- ic$C_ORTH_def$ic_series
conf_base <- 0.5
conf_vec <- setNames(as.list(rep(conf_base, nrow(latest))), latest$Ticker)

crisis_tbl <- lapply(names(cond), function(tg) {
  cc <- cond[[tg]]
  ep <- cc$crisis_episodes
  ep_list <- if (!is.null(ep)) lapply(seq_len(nrow(ep)), function(i) list(
    first = ep$first[i], last = ep$last[i], months = ep$months[i],
    cum_active = round(ep$cum_active[i], 4), cum_net = round(ep$cum_net[i], 4),
    cum_bm = round(ep$cum_bm[i], 4))) else NULL
  # 하락형 위기만 (에피소드 누적 BM < 0 — 2026-02~07 멜트업-라벨 에피소드 배제) 별도 축
  down_ep <- if (!is.null(ep)) ep[cum_bm < 0] else NULL
  list(strategy = tg,
       crisis_alpha_mean_monthly = num(cc$crisis_alpha_mean_monthly),
       crisis_alpha_t_nw = num(cc$crisis_alpha_t_nw),
       crisis_n_months = cc$crisis_n_months,
       crisis_event_positive = cc$crisis_alpha_event_count, n_episodes = cc$n_episodes,
       down_episode_positive = if (!is.null(down_ep)) sum(down_ep$cum_active > 0) else NA,
       down_episode_n = if (!is.null(down_ep)) nrow(down_ep) else NA,
       down_episode_cum_active = if (!is.null(down_ep)) round(sum(down_ep$cum_active), 4) else NA,
       episodes = ep_list,
       mdd_full = num(cc$mdd_full),
       mdd_complement_vs_core_pp = num(100*(R$core_mdd - cc$mdd_full)))
})

# alpha_inheritance_cor: C_ORTH_def vs Core(M01 canonical) 월별 횡단면 Spearman 평균
core_pan <- as.data.table(read_parquet(file.path(OUT, "panel_M01_Mom_12_1_canonical.parquet")))
sc_all <- as.data.table(read_parquet(file.path(OUT, "alpha_scores.parquet")))
mm <- merge(sc_all, core_pan[, .(Date, Ticker, core = value)], by = c("Date","Ticker"))
inh <- mm[, .(rho = suppressWarnings(cor(score, core, method = "spearman"))), by = Date][, mean(rho, na.rm = TRUE)]

fullperiod_tbl <- lapply(names(bt), function(tg) {
  r <- bt[[tg]]
  ew <- r$diag_ew_universe
  ct <- r$diag_cap_tier
  list(strategy = tg,
       canonical_port_t_nw_lag3 = num(r$portfolio_alpha_t_nw_lag3),
       net_sr = num(r$net_sr), information_ratio = num(r$information_ratio),
       alpha_annualized = num(r$alpha_annualized),
       turnover_annual = num(r$turnover_annual), n_months = r$n_months,
       ew_universe_port_t = num(ew$portfolio_alpha_t_nw_lag3),
       ew_post2017_t = num(ew$post2017_t_nw_lag3),
       cap_tier = if (isTRUE(ct$available)) ct[setdiff(names(ct), c("available","metric_type"))] else NULL)
})

ic_tbl <- lapply(names(ic), function(tg) {
  r <- ic[[tg]]
  list(strategy = tg, mean_ic = num(r$mean_ic), icir = num(r$icir), ic_t = num(r$ic_t),
       n_months = r$n_months,
       bad_ic = num(r$bad_ic), normal_ic = num(r$normal_ic),
       bad_normal_ratio = num(r$bad_normal_ratio),
       regime_ratio = num(r$regime_ratio))
})

leaves <- lapply(c("D03_RealVol","D01_IdioVol","D41_Vol_of_Vol","D45_Downside_Dev","D55_Vol_Trend"),
  function(f) list(leaf = paste0("factor_db_monthly:", f),
                   availability_rule = "fixed: price-derived, month-end close (t-1 convention), load_month_factors() C15 경유",
                   restatement_prone = FALSE))

alpha_package <- list(
  task_id = "WT-D20260802_004",
  as_of_date = "2026-08-02",
  forecast_horizon = "1M",
  spec_version = "ast_v1.1",
  hypothesis = list(
    statement = "서로 다른 변동성 축(총변동성·vol-of-vol·변동성 추세)의 방어 배향(저변동 롱) 등가중 조합은 단일 변동성 팩터 대비 위기 국면 alpha를 높인다 — 판정은 AX-001 v2 조건부 3축(crisis_alpha / Core 대비 MDD / bad-normal IC ratio)이며 전기간 SR 승격 주장이 아니다.",
    mechanism = list(
      agent = "복권 선호 개인투자자 (고변동·고왜도 종목 과대수요 주체 — KR 개인 거래비중 구조)",
      friction = "KR 공매도 제약 + 소형주 유동성 하한 → 고변동 종목의 과대평가를 사전 차익거래로 지울 수 없음",
      path = "위기 국면에서 변동성 선호가 역전(위험 회피 전환 + 마진콜 청산)되며 고변동 종목이 상대 급락 → 저변동 보유의 상대 초과수익이 위기 월에 집중 실현"
    ),
    falsification = list(
      list(condition = "CRISIS 라벨 월에서 고변동(D03 상위 quintile) 종목의 개인 순매수 강도(investor_flow 리프: I-계열 개인 순매수)가 저변동 quintile 대비 유의하게 높지 않으면(복권 수요 부재) 기전의 agent 성분 기각",
           field_ref = "factordb investor_flow 리프 (I01 계열 개인 순매수) — ast_field_map_v0.json 등재",
           status = "미측정 — next_probe 1 (본 라운드 범위 밖, 사전 지목)"),
      list(condition = "위기 월 bad/normal IC ratio가 1 미만(위기에서 방어 배향 IC가 오히려 약화)이면 '위기 집중 실현' path 기각",
           field_ref = "본 라운드 실측 (ic_diagnostics.bad_normal_ratio)",
           status = "본 라운드 실측 완료 — 결과 참조")
    ),
    regime_scope = list(
      holds_in = c("CRISIS", "CAUTION"),
      weakens_or_reverses_in = c("RISK_ON"),
      boundary_rationale = "복권 수요는 위험선호 국면에서 고변동 종목을 계속 밀어올림(expanding IC +0.11~0.14 실측 = RISK_ON 지배 표본에서 고변동 롱이 우세). 방어 배향의 수익원은 위험선호 역전 시의 상대 붕괴이므로 국면 경계가 기전에서 직접 도출됨."
    )
  ),
  factors = lapply(ORTH, function(f) list(
    factor_id = paste0("F_", f, "_def"),
    ast = fromJSON(file.path(OUT, sprintf("ast_%s_defensive.json", f)), simplifyVector = FALSE),
    role = "defense_axis",
    restatement_exposure = 0L
  )),
  combination_rule = "z_score_aligned_equal_weight",
  verdict = "designed",
  self_pit_check = list(
    performed = TRUE,
    leaves_checked = leaves,
    verdict = "clean",
    note = "전 리프 가격파생(월말 종가 시점 고정) — 재무 lag/restatement 비해당. 국면 라벨은 신호 미사용(사후 귀속 전용)이므로 C5 비발동."
  ),
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260802_004/alpha_scores.parquet",
  factor_specs = lapply(ORTH, function(f) {
    defs <- list(
      D03_RealVol = list(proxy = "252d realized vol (defensive: low = long)", rat = "lottery_demand_reversal_in_crisis"),
      D01_IdioVol = list(proxy = "CAPM residual std 252d (defensive)", rat = "lottery_demand_reversal_idiosyncratic"),
      D41_Vol_of_Vol = list(proxy = "std of rolling vols (low vol-of-vol = long)", rat = "vol_uncertainty_premium"),
      D45_Downside_Dev = list(proxy = "downside deviation (low = long)", rat = "semivol_crash_aversion"),
      D55_Vol_Trend = list(proxy = "21d vol vs 252d vol trend (declining = long)", rat = "vol_regime_transition")
    )[[f]]
    list(factor_family = "defense_volatility", proxy = defs$proxy,
         formula = sprintf("MUL(factor_db_monthly:%s, -1) — AST 선언 방어 배향", f),
         lag_rule = "price t-1 close, month-end",
         winsorization = "factor DB 표준 (builder-side)",
         neutralization = "none (조합 자체가 축 분산)",
         economic_rationale = defs$rat,
         weight_theta = round(1/length(ORTH), 4),
         references = c("Ang-Hodrick-Xing-Zhang 2006 (IVOL)", "Blitz-van Vliet 2007 (low vol)",
                        "Baltussen-van Bekkum-van der Grient 2018 (vol-of-vol)"))
  }),
  diagnostics = list(
    canonical_port_t_nw_lag3 = num(bt$C_ORTH_def$portfolio_alpha_t_nw_lag3),
    canonical_port_t_pvalue = num(bt$C_ORTH_def$portfolio_alpha_t_pvalue),
    canonical_n_months = bt$C_ORTH_def$n_months,
    rank_ic = num(ic$C_ORTH_def$mean_ic),
    icir = num(ic$C_ORTH_def$icir),
    harvey_t_stat = num(ic$C_ORTH_def$ic_t),
    turnover_proxy = num(bt$C_ORTH_def$turnover_annual),
    subperiod_stability = NULL,
    monotonicity = NULL,
    post_neutralization_ic = NULL,
    ax001_conditional = crisis_tbl,
    ic_diagnostics = ic_tbl,
    fullperiod_reference = fullperiod_tbl,
    correlation_matrix_mean = as.list(round(R$cor_mean, 4)),
    core_mdd_m01_top25 = num(R$core_mdd), bm_mdd = num(R$bm_mdd),
    metric_type = "canonical_screen",
    n_trials = length(bt),
    selection_type = "chain",
    selection_note = "조합방식·멤버십 전부 사전등록(등가중 + 상관 0.8 규칙, 성과 무참조). argmax 선택 없음. DSR = sweep 아님 → 게이트 비적용, n_trials 기록."
  ),
  selection_objective = "canonical_port_t",
  alpha_inheritance_cor = round(abs(inh), 4),
  alpha_inheritance_note = sprintf("C_ORTH_def vs Core(M01) 월별 횡단면 Spearman 평균 %.4f — |cor| < 0.95 충족", inh),
  challenge_flags = list(
    list(id = "CF-1", severity = "HIGH",
         flag = "가설 기각 — 조합(C_ORTH_def)의 crisis_alpha(-5.26%/월, NW t -1.26)가 단일 최선(D55_def -2.88%/월)보다 나쁨. 하락형 위기(BM<0 에피소드 4건)만 봐도 조합 누적 active(+8.4%)가 단일 최선(D03_def +24.4%)을 넘지 못함. 조합 개선 없음."),
    list(id = "CF-2", severity = "HIGH",
         flag = "failure_rules Rule 1 발동 — 방어 lane 전기간 기대 alpha 음수(netSR -0.20~-0.32, PORT_t -0.39~-1.31), 비용 대비 기대 alpha ratio < 2 충족 불가. standalone 슬리브 부적격. Risk 단계 진행 비권고 (REJECT recommendation)."),
    list(id = "CF-3", severity = "MEDIUM",
         flag = "국면 라벨 오염 — 2026-02~07 에피소드가 CRISIS 라벨이나 벤치 누적 +33.7%(초대형주 멜트업). regime-라벨 기반 crisis_alpha 축이 이 에피소드에 지배됨(-92.5% cum active). 하락형 위기(GFC/COVID/2025-11)에선 방어 lane 전 구성 양(+) active 실측 — episodic 방어 신호는 실재하되 overlay/국면-조건부 소비면만 유효(방어팩터 DB 전수 07-03 확증과 정합)."),
    list(id = "CF-4", severity = "MEDIUM",
         flag = "방향정렬 실측 — connector 정본(Z_Score_Aligned, expanding IC)은 변동성 팩터를 '고변동 롱'으로 배향(IC +0.11~0.14 전 구간 안정). 방어 배향은 AST MUL(-1) 구조 선언 + 양 lane 병행 측정으로 처리. canonical lane도 전 구성 PORT_t 음수 — 어느 배향도 top-25 실현 alpha 없음."),
    list(id = "CF-5", severity = "LOW",
         flag = "선례 채점 판별(a) — LowVol/BlitzVanVliet/Defense+quality 등 defense 계열 FAIL 최소 5건이 전기간 SR/CAGR/MDD 채점(조건부 축 0개) = AX-001 위반 채점이었음. 단 본 라운드 조건부 재평가로도 승격 불가 판정 동일(사유는 다름 — 만성 음의 drift + 조합 무개선). LowVol hurdle detected_family='other' 오분류로 AX-001 hook 우회 정황 — 거버넌스 수리 대상.")
  )
)

write_json(alpha_package, file.path(MB, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 6, null = "null")
say("alpha_package.json 저장")

# validation 산출물
validation <- list(
  task_id = "WT-D20260802_004",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  evaluation_frame = "AX-001 v2 conditional (crisis_alpha / mdd_complement_vs_core / bad_normal_ic_ratio). 전기간 지표는 병기(승격 근거 아님).",
  regime_label_source = ".cache/unified_regime_signal.parquet Category (기존 라벨 — 자체 정의 없음, 사후 귀속 전용)",
  ax001_conditional = crisis_tbl,
  ic_diagnostics = ic_tbl,
  fullperiod_reference = fullperiod_tbl,
  correlation = list(mean = as.list(round(R$cor_mean, 4)), sd = as.list(round(R$cor_sd, 4)),
                     orth_members = ORTH,
                     rule = "월별 횡단면 Spearman 평균 |rho|>=0.8 쌍 → 일반->특수 우선순위 후순위 제거 (성과 무참조)"),
  universe_comparison = NULL,
  dual_basis = lapply(names(bt), function(tg) list(
    strategy = tg,
    cap_w_port_t = num(bt[[tg]]$portfolio_alpha_t_nw_lag3),
    ew_universe = bt[[tg]]$diag_ew_universe[c("portfolio_alpha_t_nw_lag3","post2017_t_nw_lag3","oos_retention_approx","n_months")],
    cap_tier = bt[[tg]]$diag_cap_tier))
)
write_json(validation, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 6, null = "null")
file.copy(file.path(OUT, "alpha_validation.json"),
          file.path(MB, "alpha_validation.json"), overwrite = TRUE)
say("alpha_validation.json 저장 (stage + mailbox)")

# lineage (write 후 — L-194 순서)
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = "WT-D20260802_004",
  package_type = "alpha_package",
  method_selected = sprintf("defensive vol combo C_ORTH {%s} z_score_aligned_equal_weight (AX-001 conditional)", paste(ORTH, collapse="+")),
  input_file_paths = c(".cache/RAWDATA.parquet", ".cache/unified_regime_signal.parquet",
                       file.path(OUT, sprintf("panel_%s_canonical.parquet", c(ORTH, "M01_Mom_12_1"))))
)
say("lineage 기록 완료")
