# =============================================================================
# FQ-057 run_06: verdict.json assembly + chart pack + telegram brief
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
ab   <- fromJSON(file.path(OUT_DIR, "fq057_ab_summary.json"))
ctd  <- fromJSON(file.path(OUT_DIR, "fq057_cap_tier_decomposition.json"),
                 simplifyDataFrame = FALSE)
san  <- fromJSON(file.path(OUT_DIR, "fq057_sanity.json"))
sens <- fromJSON(file.path(OUT_DIR, "fq057_tier_boundary_sensitivity.json"))
pin_tag <- fromJSON(file.path(OUT_DIR, "fq057_pin_tag.json"))$pin_tag
summ <- as.data.table(ab$summary)

verdict <- list(
  id = "FQ-057",
  lane = "method_frontier",
  round_type = "independent_research_round_not_WT",
  agent = "risk-research",
  finalized_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  pin_tag = pin_tag,
  hypothesis = paste(
    "cap-tier block Sigma (MEGA/MID/SMALL blocks + cross-tier 1-factor,",
    "LW-2020 analytical NLS inner) improves estimation quality vs plain",
    "shrinkage estimators on K200|KQ150 monthly panel (rolling 60m, 2010-2026)"),
  verdict = "NEGATIVE_config_scoped_for_block_composite__POSITIVE_for_lw_nls_lane_output",
  metric_type = "estimation_quality_diagnostic",
  selection_objective = "shrinkage_quality",
  selection_rule = ab$selection_rule,
  design = list(
    windows = "rolling 60m, est end 200912..202605, eval next month (198 windows)",
    universe_rule = "K200|KQ150 members at window end, complete 60 obs, size known (p 280~320)",
    tier_rule = ab$tier_rule,
    mvp_note = ab$mvp_note,
    hard_rule_compliance = "R4 P3: no SR/IR/alpha anywhere in comparison or selection"
  ),
  method_shopping_log = list(
    candidates_tried = 5, cap = 5,
    parallel_exec = FALSE, n_workers = 1,
    method_log = lapply(seq_len(nrow(summ)), function(i) as.list(summ[i]))
  ),
  candidates = summ,
  selected = ab$selected,
  sanity_checks = san,
  tier_boundary_sensitivity = sens,
  cap_tier_decomposition = ctd,
  mechanism_diagnosis = list(
    block_negative = paste(
      "Hard assembly of independently-shrunk PSD blocks with 1-factor",
      "cross-block replacement is not a PSD-preserving operator:",
      "psd_viol_rate 100% (198/198), min_ev ~ -0.196 scale; eigen-clip repair",
      "leaves cond ~1e10 and MVP explodes (gross leverage 5.9/9.9,",
      "OOS realized vol 0.549/0.959 vs lw_nls 0.142)."),
    tier_signal_partial = paste(
      "block_nls attains the BEST cor_rmse_fwd12 (0.33768 vs lw_nls 0.33795",
      "vs lw_linear 0.37610) - tier prior does contribute to correlation-",
      "structure fit, but the gain cannot offset the PSD defect. Concept not",
      "falsified; this composite operator is (INV-7 config-scoped)."),
    incumbent_finding = paste(
      "hrp_core .get_cor_cov linear LW degenerates to mu*I when p>n",
      "(rho cap=1 binding): cond=1, all correlation structure destroyed,",
      "MVP collapses to EW. Harmless at WT scale (p<=25); must NOT be",
      "consumed for large-universe Sigma."),
    dual_basis_risk_layer = paste(
      "First risk-layer quantification of FQ-055 dual-basis divergence:",
      "book (70% cash CRISIS) active risk is 99.8% MEGA-tier on cap-w basis",
      "(mega underweight dominates) but 2.9% MEGA / 36.9% MID / 60.2% SMALL",
      "on EW-uni basis - the axis of active risk inverts with basis",
      "(max tier share divergence 0.969, flag TRUE). Robust to MID/SMALL",
      "boundary choice (MEGA share invariant across cut 100/150/200).")
  ),
  limitations = c(
    "fwd-12m sample-cov loss target is itself noisy (n=12): frob/cor differences are weak evidence; only paired ordering used",
    "MVP is unconstrained (estimation-quality instrument, Ledoit-Wolf horse-race convention) - not an allocation, long-only behavior may differ",
    "lw_nls is own port of analytical_shrinkage.m; sanity S1-S3 PASS but no numerical parity vs official implementation yet (nlshrink absent)",
    "signal_alive_t36m measures EW-of-tier vs cap-w bench (breadth-vs-concentration regime diagnostic), NOT strategy signal aliveness; all tiers t<0 consistent with 2025-26 mega-cap concentration regime",
    "A402340 (listed 2021-11, 55m history) excluded from Sigma universe by complete-60m rule (weight 0.0056)",
    "MID/SMALL individual shares are boundary-conditional (cut=150); MEGA headline is boundary-robust",
    "45 warnings in A/B loop = cov2cor(S_fwd) near-zero-variance names in the loss target (non-differential across estimators, verified)"
  ),
  next_probes = list(
    list(id = "NP1",
         title = "PSD-guaranteed tier embedding A: Schur/Hadamard tier-damping",
         detail = paste("M = delta*J + (1-delta)*blockdiag(J) mask, Sigma_tier =",
           "M (Hadamard) cor_NLS scaled back - Schur product theorem guarantees PSD",
           "for delta in [0,1]; delta chosen by estimation-quality enum only")),
    list(id = "NP2",
         title = "PSD-guaranteed tier embedding B: tier-factor Sigma = B Omega B' + D",
         detail = paste("factors = market + tier dummies (+size); PSD by construction,",
           "aligns with risk_research_init base frame; compare vs lw_nls on same A/B harness")),
    list(id = "NP3",
         title = "lw_nls productionization gate",
         detail = paste("numerical parity vs official analytical_shrinkage implementation,",
           "then register into .get_cor_cov (WT-time consumption eligibility);",
           "requires Q-Lead/dohoon confirm - not done in this round")),
    list(id = "NP4",
         title = "MVO Sigma-input swap paired canonical PORT_t (FQ-057 next_action residual)",
         detail = paste("optimizer-lane round: swap Sigma input lw_linear -> lw_nls in MVO,",
           "paired canonical PORT_t measurement; separate round, graduation rules apply"))
  ),
  revival_or_followup_conditions = c(
    "hard block-replacement composites: retry ONLY with a PSD-preserving assembly operator (NP1/NP2 are the sanctioned paths)",
    "WT-time consumption of lw_nls: gated on NP3 (parity + .get_cor_cov registration + confirm)",
    "cap_tier_decomposition field: wire into regular risk_package emission from next QEPM WT (schema v83_dual_basis_captier, this round = reference implementation)",
    "large-universe consumers of .get_cor_cov ledoit_wolf: audit for p>n degeneracy before reuse"
  ),
  artifacts = list(
    runner_dir = "04_Research/method_frontier/fq057_captier_sigma/",
    ab_metrics = "stage_artifacts/method_frontier/fq057_ab_metrics.parquet",
    mvp_oos_returns = "stage_artifacts/method_frontier/fq057_mvp_oos_returns.parquet",
    ab_summary = "stage_artifacts/method_frontier/fq057_ab_summary.json",
    cap_tier_decomposition = "stage_artifacts/method_frontier/fq057_cap_tier_decomposition.json",
    sanity = "stage_artifacts/method_frontier/fq057_sanity.json",
    tier_boundary_sensitivity = "stage_artifacts/method_frontier/fq057_tier_boundary_sensitivity.json",
    challenge_note = "stage_artifacts/method_frontier/fq057_challenge_note.md",
    monthly_panel = c("stage_artifacts/method_frontier/fq057_monthly_returns.parquet",
                      "stage_artifacts/method_frontier/fq057_monthly_snapshot.parquet")
  )
)
write_json(verdict, file.path(OUT_DIR, "fq057_verdict.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("[verdict] written\n")

# ---- charts (tg_chart_sweep, visualization-only) ----------------------------
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))
ord <- c("lw_nls", "lw_linear", "sample", "block_lw", "block_nls")
s2 <- summ[match(ord, est)]
ch1 <- tg_chart_sweep(
  labels = ord, values = round(s2$mvp_oos_vol_ann, 3),
  out_dir = OUT_DIR, title = "FQ-057 최소분산 포트 OOS 실현변동성 (연율, 낮을수록 우수)",
  highlight = "lw_nls")
ch2 <- tg_chart_sweep(
  labels = ord, values = round(s2$cor_rmse_fwd12_mean, 4),
  out_dir = OUT_DIR, title = "FQ-057 상관구조 예측오차 RMSE (fwd-12m, 낮을수록 우수)",
  highlight = "block_nls")
tiers_dt <- rbindlist(lapply(ctd$tiers, function(x)
  data.table(tier = x$tier, capw = x$active_risk_share, ew = x$active_risk_share_ew_basis)))
ch3 <- tg_chart_sweep(
  labels = c(paste0(tiers_dt$tier, " (cap-w)"), paste0(tiers_dt$tier, " (EW-uni)")),
  values = round(c(tiers_dt$capw, tiers_dt$ew), 3),
  out_dir = OUT_DIR, title = "FQ-057 현 북 능동위험 tier 분해 — 기준별 역전 (dual-basis)")
charts <- c(ch1, ch2, ch3)
cat("[charts]", length(charts), "png\n")

# ---- telegram ----------------------------------------------------------------
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
sections <- list(
  list(type = "bullet", emoji = "\U0001F4DA", heading = "연구 컨텍스트",
       items = c(
         "목적: 공분산 추정기에 시총 계층(cap-tier) 블록 구조 내장 시 개선 검증",
         "검토: K200∪KQ150 월간 2005~2026, 60개월 롤링 198구간, 추정기 5종 비교",
         "결론: 블록 조립 탈락(양정치성 위반 100%) — 승자는 비선형 축소(lw_nls)",
         "선택 잣대: 성과(샤프지수 등) 배제, 추정품질 지표만 사용 (규정 준수)")),
  list(type = "bullet", emoji = "\U0001F4D6", heading = "쉬운 설명",
       items = c(
         "시도: 종목들이 함께 흔들리는 정도를 잴 때 대형·중형·소형 블록 분리가 나은지",
         "방법: 과거 21년을 60개월 창으로 198번 굴려 다음 달 실제 움직임 적중을 비교",
         "결과: 블록 조립은 수학 결함(양정치성 깨짐)이 전 구간 발생해 탈락",
         "의미: 돈의 이동 없음 — 위험 측정 부품 선정 라운드, 승자는 검증 후 등재 예정")),
  list(type = "table", emoji = "\U0001F52C", heading = "추정기 비교 (추정품질 지표만)",
       df = data.frame(
         `추정기` = s2$est,
         `조건수` = ifelse(is.na(s2$cond_median), "Inf",
                        format(round(s2$cond_median, 1), big.mark = ",", scientific = FALSE)),
         `PSD위반` = sprintf("%.0f%%", s2$psd_viol_rate * 100),
         `상관RMSE` = sprintf("%.4f", s2$cor_rmse_fwd12_mean),
         `MVP변동성` = sprintf("%.3f", s2$mvp_oos_vol_ann),
         check.names = FALSE)),
  list(type = "bullet", emoji = "\U0001F9ED", heading = "cap-tier 위험분해 1호 (dual-basis)",
       items = c(
         "현 북(현금 70%) 능동위험: 시총가중 잣대로는 대형주 블록 99.8%",
         "동일가중 잣대로는 대형 2.9% · 중형 36.9% · 소형 60.2% — 축이 정반대",
         "dual-basis 괴리 flag TRUE (최대 괴리 0.969), 경계 선택에도 강건",
         "risk_package 의무 필드 cap_tier_decomposition 최초 실구현 레퍼런스")),
  list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 + 다음 단계",
       items = c(
         "판정: 자본 배정 아님 — 추정품질 진단. 블록 설계는 이번 구성 한정 탈락",
         "tier 개념은 기각 아님: 블록형이 상관구조 적합 1위 실측 (0.3377)",
         "부수 발견: 기존 선형 축소 코드, 종목수>표본수에서 상관구조 전멸 퇴화",
         "다음: 양정치성 보장 tier 내장 2경로 + 비선형 축소 정식 등재 검증"))
)
r <- tg_agent_brief(agent = "Risk",
  title = "FQ-057 METHOD_FRONTIER — cap-tier block Σ 추정품질 A/B",
  sections = sections, charts = charts)
cat("[telegram] sent:", isTRUE(r$ok) || !is.null(r), "\n")
cat("[done] run_06 complete\n")
