# ── R6 — risk_package.json 발행 + lineage + challenge review
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
MB  <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005")
TID <- "WT-R20260829_005"

R1<-readRDS(file.path(OUT,"risk_r1.rds")); R2<-readRDS(file.path(OUT,"risk_r2.rds"))
R3<-readRDS(file.path(OUT,"risk_r3.rds")); R4<-readRDS(file.path(OUT,"risk_r4.rds"))
R5<-readRDS(file.path(OUT,"risk_r5.rds"))
SIG <- R1$SIG; ASSETS <- R2$ASSETS; win_d <- R2$win_d; D <- R1$D

## ── 기준바스켓 베타 실측 (alpha 의 beta 0.869 주장에 대한 risk 층 대조) ─────
Dw <- D[Date %in% win_d & Ticker %in% R4$top25, .(Date,Ticker,Ret)]
W <- dcast(Dw, Date ~ Ticker, value.var="Ret"); wd <- W$Date; W[,Date:=NULL]; W<-as.matrix(W)
rb <- rowMeans(W, na.rm=TRUE)
bmv <- R1$BMd[Date %in% wd][order(Date), BM_Ret]
ok <- is.finite(rb) & is.finite(bmv)
beta_now <- cov(rb[ok], bmv[ok])/var(bmv[ok])
## 유니버스 EW 도 같이 (기준바스켓 특이성인지 유니버스 구조인지 분리)
Du <- D[Date %in% win_d & Ticker %in% ASSETS, .(Date,Ticker,Ret)]
Wu <- dcast(Du, Date ~ Ticker, value.var="Ret"); Wu[,Date:=NULL]; Wu<-as.matrix(Wu)
ru <- rowMeans(Wu, na.rm=TRUE)
beta_ew <- cov(ru[ok], bmv[ok])/var(bmv[ok])
cat(sprintf("[R6] window daily beta vs KOSPI200: EW top-25 = %.3f | EW universe 340 = %.3f (alpha full-history monthly beta = 0.869)\n",
            beta_now, beta_ew))

grp <- R4$grp; sc <- R4$sec_contrib
top_common <- c(sprintf("Market/MKT (%.1f%%)", 100*grp[["MKT.MKT"]]),
                sprintf("Sector_total (%.1f%%)", 100*grp[["SECTOR_TOTAL"]]),
                sprintf("Specific/idiosyncratic (%.1f%%)", 100*grp[["SPECIFIC"]]),
                sprintf("Style_Beta (%.1f%%)", 100*grp[["X_BETA"]]),
                sprintf("Style_ResidVol (%.1f%%)", 100*grp[["X_RVOL"]]),
                sprintf("Style_Momentum (%.1f%%)", 100*grp[["X_MOM"]]))
cat("[R6] top_common_risks:\n"); print(top_common)

CR <- R4$CR; CRd <- R4$CRd
crowd_list <- lapply(seq_len(nrow(CR)), function(i) {
  r <- CR[i]; d <- CRd[factor_name == r$factor_name]
  x <- list(factor_name = r$factor_name, crowding_score = r$crowding_score,
            hhi_top = r$hhi_top, vol_concentration = r$vol_concentration,
            passive_overlap_proxy = r$passive_overlap_proxy,
            demand_elasticity_proxy = r$demand_elasticity_proxy,
            n_universe = r$n_universe, n_top = r$n_top,
            crowding_score_3m_ago = if (nrow(d)) d$cs_3m_ago else NA_real_,
            delta_3m = if (nrow(d)) d$delta_3m else NA_real_)
  if (is.finite(r$crowding_score) && r$crowding_score >= 0.75) x$alert <- "LEVEL_HIGH"
  if (nrow(d) && is.finite(d$delta_3m) && d$delta_3m >= 0.15) x$alert <- "RAPID_INCREASE"
  x })
crowding_flags <- character(0)
for (i in seq_len(nrow(CR))) if (is.finite(CR$crowding_score[i]) && CR$crowding_score[i] >= 0.75)
  crowding_flags <- c(crowding_flags, sprintf("%s crowding_score %.2f", CR$factor_name[i], CR$crowding_score[i]))

liq <- R4$liq
liquidity_flags <- character(0)
if (any(liq$days_to_liq > 3, na.rm=TRUE))
  liquidity_flags <- c(liquidity_flags, sprintf("%d names > 3 days-to-liquidate @ 100억 book / 10%% ADV",
                                                sum(liq$days_to_liq > 3, na.rm=TRUE)))
STR <- R4$STR; scen <- R4$scen
stress_tests <- as.list(round(unlist(scen), 6))
for (i in seq_len(nrow(STR))) {
  nm <- paste0("hist_", tolower(STR$scenario[i]))
  stress_tests[[nm]] <- if (is.na(STR$strat_cum[i])) NA_real_ else round(STR$strat_cum[i], 6)
}
ph <- R4$pl_hist
stress_tests[["hist_replay_worst_month_current_exposures"]] <- round(min(ph$pnl), 6)

DUAL <- R4$DUAL
tiers <- lapply(seq_len(nrow(DUAL)), function(i) list(
  tier = DUAL$tier[i],
  active_risk_share = round(DUAL$basket_risk_share[i], 6),
  weight_share_basket_ew = round(DUAL$basket_top25_ew[i], 6),
  base_ew_universe = round(DUAL$ew_universe[i], 6),
  base_capw_universe = round(DUAL$capw_universe[i], 6),
  divergence_vs_ew_universe = round(DUAL$divergence_vs_ew_universe[i], 6),
  signal_alive = NA))

REG <- R4$REG
regime_tbl <- lapply(seq_len(nrow(REG)), function(i) as.list(REG[i]))

TD <- R4$TD
fcor <- R4$fcor; hp <- R4$hi_pairs; kf <- rownames(fcor)
fw_warn <- if (nrow(hp)) vapply(seq_len(nrow(hp)), function(i)
  sprintf("%s ~ %s = %.3f", kf[hp[i,1]], kf[hp[i,2]], fcor[hp[i,1],hp[i,2]]), "") else character(0)

## ── method shopping log (상한 5) ────────────────────────────────────────────
deg <- R3$deg; bias <- R3$bias
mlog <- lapply(c("sample","ledoit_wolf","lw_nls","gerber_rmt","factor_bwb_d"), function(nm) {
  d <- deg[[nm]]; b <- bias[method == nm]
  list(name = nm, condition = round(d$cond, 2), min_eigenvalue = signif(d$min_eig, 4),
       mean_abs_offdiag_corr = round(d$mean_abs_offdiag_corr, 4),
       corr_structure_retention = round(d$corr_structure_retention, 4),
       walkforward_bias_stat = if (nrow(b)) round(b$bias_stat, 4) else NA_real_,
       selected = nm == "factor_bwb_d",
       reject_reason = switch(nm,
         sample       = "condition 4173 >> 500 (RF-R2). p=330 vs n=756 에서 표본 고유값 확산이 그대로 남는다.",
         ledoit_wolf  = "★축퇴. rho 가 상한에 붙어 Sigma -> mu*I. 상관구조 보존율 0.000, cond=1, bias 3.04. p<n(330<756) 이라 hrp_core 의 p>n 가드가 발화하지 않았다.",
         lw_nls       = "condition 928 > 500. 구조 보존(0.931)·PD 는 양호하나 조건수 기준 미달.",
         gerber_rmt   = "condition 1.008e4 (최악). 상관 보존율 1.626 = 표본 대비 상관을 60% 증폭 — 다른 대상을 재고 있다. bias 1.069 로 가장 좋으나 그 이유가 증폭이라 조건수와 상충.",
         factor_bwb_d = NA_character_))
})

pkg <- list(
  task_id = TID,
  as_of_date = as.character(SIG),
  agent = "risk-research",
  spec_version = "risk_v1.2",
  upstream = list(alpha_package = "qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json",
                  alpha_package_modified = FALSE,
                  note = "alpha_vector / confidence / alpha_lower_bound 는 read-only 소비. 재해석·재계산·정규화 없음."),
  exposure_matrix_ref  = "stage_artifacts/WT_R20260829_005/exposure_matrix.parquet",
  factor_covariance_ref= "stage_artifacts/WT_R20260829_005/factor_covariance.parquet",
  specific_risk_ref    = "stage_artifacts/WT_R20260829_005/specific_risk.parquet",
  security_covariance_ref = "stage_artifacts/WT_R20260829_005/covariance.parquet",
  benchmark_covariance_ref= "stage_artifacts/WT_R20260829_005/benchmark_covariance.parquet",
  tail_risk_ref        = "stage_artifacts/WT_R20260829_005/tail_risk.json",
  regime_correlation_ref  = "stage_artifacts/WT_R20260829_005/regime_correlation.parquet",

  covariance_contract = list(
    structure = "Sigma = B Omega B^T + D",
    units = "monthly variance/covariance (daily Sigma x 21 trading days) — alpha_vector 의 1M 지평과 정합",
    annualization_factor = 12,
    n_assets = length(ASSETS), asset_id_column = "Ticker",
    parquet_layout = "wide: 1열 Ticker + 340개 Ticker 열 (i행 j열 = Cov(i,j))",
    factors = list(n = length(R2$fac_names), market = 1L,
                   sectors = length(R2$SECLV) - 1L, styles = R2$STY,
                   sector_coding = "contr.sum (sum-to-zero, 기준수준 = 마지막 섹터)"),
    estimation_window = list(type = "rolling", trading_days = R2$WIN_D,
                             from = as.character(min(win_d)), to = as.character(max(win_d)),
                             note = "C1 — full-sample 통계 미사용. 노출 z-score 도 각 월 횡단면 독립."),
    positive_definite = TRUE, min_eigenvalue = signif(R5$min_eig_m, 6),
    condition_number = round(R5$cond_m, 2)),

  risk_summary = list(
    diagnostic_basis = paste0("아래 진단의 기준바스켓 = alpha_hat 상위 25종 **균등가중**. ",
      "이것은 비중 권고가 아니라 위험구조를 읽기 위한 기준선이다(비중 결정 = Optimizer 소관). ",
      "유니버스 EW(340종) 및 K200 cap-w 두 기준을 병기해 바스켓 특이성과 유니버스 구조를 분리했다."),
    reference_basket_n = length(R4$top25),
    predicted_vol_ann = round(sqrt(R4$tot_var_d * 252), 6),
    factor_variance_share = round(R4$fac_var_d / R4$tot_var_d, 6),
    specific_variance_share = round(R4$spec_var_d / R4$tot_var_d, 6),
    top_common_risks = top_common,
    variance_decomposition_pct = as.list(round(100*grp, 3)),
    top_sector_contributions_pct = as.list(round(100*head(sc, 5), 3)),
    factor_exposures_reference_basket = as.list(round(R4$x[c("MKT",R2$STY)], 4)),
    measured_beta_vs_kospi200 = list(
      reference_basket_daily_window = round(beta_now, 4),
      ew_universe_daily_window = round(beta_ew, 4),
      alpha_reported_full_history_monthly = 0.86878443,
      note = "동일 대상의 다른 창/주기 추정치다. alpha 의 0.869 는 2005~2026 월별, 위 값은 2023-08~2026-07 일별. 판정용이 아니라 안정성 대조용."),
    concentration = list(
      hhi_name = round(R4$hhi_name, 6), n_effective_names = round(R4$n_eff_name, 3),
      hhi_sector = round(R4$hhi_sec, 6), n_effective_sectors = round(R4$n_eff_sec, 3),
      n_sectors_held = nrow(R4$secw),
      top_sector_weights = as.list(setNames(round(R4$secw[order(-sw)]$sw, 4), R4$secw[order(-sw)]$Sector))),
    cap_tier_decomposition = list(
      basis = "cap_w_and_ew_uni",
      tier_def = "MEGA = 전체 상장 시총랭크 1-10 / MID = 11-30 / OTHER = 31+ (canonical_screen_bt 정의)",
      tiers = tiers,
      dual_basis_divergence_flag = any(abs(DUAL$divergence_vs_ew_universe) > 0.10),
      interpretation = paste0(
        "alpha diagnostics 의 OTHER 92.7%(259개월 평균)는 소형주 베팅의 증거가 아니다 — ",
        "K200∪KQ150 유니버스 자체의 EW 기준 OTHER 비중이 ", round(100*DUAL[tier=="OTHER", ew_universe],1),
        "% 다(as-of 실측). as-of 기준바스켓의 OTHER 는 ", round(100*DUAL[tier=="OTHER", basket_top25_ew],1),
        "% 로 오히려 유니버스 기준선보다 **낮고** MID 가 ", round(100*DUAL[tier=="MID", basket_top25_ew],1),
        "%(기준선 ", round(100*DUAL[tier=="MID", ew_universe],1), "%)로 과표집이다. ",
        "즉 이 전략의 tier 분포는 '31위 밖'이라는 라벨의 산술이지 소형주 집중이 아니다. ",
        "단 본 수치는 as-of 단일 단면이고 alpha 의 92.7% 는 259개월 평균이므로 직접 대체가 아니라 대조다.")),
    crowding_flags = crowding_flags,
    crowding_score_per_factor = crowd_list,
    crowding_note = paste0("passive_overlap_proxy 가 3팩터 모두 1.000 으로 포화 — 유니버스가 이미 ",
      "K200∪KQ150(벤치 구성종목)이라 이 성분은 본 설계에서 판별력이 없다. ",
      "실질 판별은 hhi_top 에서 나온다: Momentum leg 0.388 vs Value leg 0.027 — ",
      "모멘텀 축은 소수 대형주에 집중되고 가치 축은 분산된다. 결합점수의 0.095 는 그 중간이다."),
    liquidity_flags = liquidity_flags,
    liquidity = list(book_assumption_krw = 1e10, participation_rate = 0.10,
                     median_days_to_liquidate = round(median(liq$days_to_liq, na.rm=TRUE), 4),
                     p90_days_to_liquidate = round(as.numeric(quantile(liq$days_to_liq, .9, na.rm=TRUE)), 4),
                     max_days_to_liquidate = round(max(liq$days_to_liq, na.rm=TRUE), 4),
                     note = "유동성 하한(20일 평균 거래대금 >= 2e8 KRW)이 alpha 단계에서 이미 걸려 있어 잔여 용량압력은 100억 book 기준 1일 미만."),
    stress_tests = stress_tests,
    stress_test_detail = list(
      historical_episodes = lapply(seq_len(nrow(STR)), function(i) as.list(STR[i])),
      coverage_rule = "coverage < 0.85 인 구간은 reliability=UNRELIABLE 로 표기하고 판정에 쓰지 않는다(부분 상장/기간 아티팩트).",
      factor_shock_method = "E[f | f_k = s] = Omega[,k]/Omega[k,k] * s (다변량 정규 조건부 평균). 조건부 베타는 척도불변이므로 일별 Omega 로 구해 월 규모 1회 충격 s 를 태운다.",
      style_shock_size = as.list(round(2*R4$f_mo_sd[R2$STY], 5)),
      historical_replay = list(
        note = "현행 노출 x 실제 월별 팩터 실현치 (모수가정 없음, 59개월)",
        worst_5 = lapply(1:5, function(i) list(ym = R4$pl_hist$ym[i], pnl = round(R4$pl_hist$pnl[i],5))))),
    regime_correlation = list(
      method = paste0("후행 24개월 창마다 그 창 안에서 완전관측인 종목만으로 평균 쌍상관 rho_bar 산출 후 ",
                      "국면에 배정. 국면별 pooling 을 쓰지 않은 이유 = pooling 하면 이름집합이 국면마다 달라져 ",
                      "(실측 101 vs 210종) 상관 차이가 국면이 아니라 구성에서 온다."),
      n_windows = nrow(R4$RHO), median_names_per_window = median(R4$RHO$n_names),
      table = regime_tbl,
      finding = paste0("방향(BULL ", round(REG[regime=="BULL", mean_pairwise_cor],4),
        " vs BEAR ", round(REG[regime=="BEAR", mean_pairwise_cor],4), ")은 공동움직임을 거의 바꾸지 않는다. ",
        "바꾸는 것은 변동성 국면이다(HIGHVOL ", round(REG[regime=="HIGHVOL", mean_pairwise_cor],4),
        " vs LOWVOL ", round(REG[regime=="LOWVOL", mean_pairwise_cor],4), " = ",
        round(100*(REG[regime=="HIGHVOL", mean_pairwise_cor]/REG[regime=="LOWVOL", mean_pairwise_cor]-1),1),
        "% 상승). 분산효과는 필요할 때 사라지는 것이 아니라 **변동성이 오를 때** 사라진다."))),

  diagnostics = list(
    selection_objective = "condition_number",
    selection_objective_note = "추정품질 지표만 사용. alpha 수익/SR/IR 은 추정기 선택에 일절 참조하지 않았다(R4 P3).",
    estimator_selected = "factor_bwb_d",
    condition_number = round(R5$cond_m, 2),
    condition_number_before_shrinkage = round(R3$cal[floor_frac == 0.25, cond], 2),
    shrinkage_used = TRUE,
    shrinkage_method = "specific_variance_floor + eigenvalue_floor_on_Omega + observation-count Bayes shrinkage of D",
    shrinkage_detail = list(
      specific_variance_floor_frac = R3$floor_frac,
      floor_rationale = paste0("3년 창 측정 개별분산이 횡단면 중앙값의 ", R3$floor_frac,
        "배 미만인 종목은 KR 저유동 stale-price 아티팩트가 주 원인이다. 바닥 상향은 (i) 조건수를 ",
        round(R3$cal[floor_frac==0.25, cond],1), " -> ", round(R5$cond_m,1),
        " 로 낮추고 (ii) 소형주 개별위험 **과소평가**라는 위험한 방향의 오차를 줄인다."),
      n_names_floored = sum(R3$Ds$v_base < R3$floor_frac * R3$med_v),
      calibration_grid = lapply(seq_len(nrow(R3$cal)), function(i) as.list(R3$cal[i])),
      omega_eigen_floor = "max(eig) * 1e-6",
      specific_bayes_shrink = "w = min(1, 120/n_obs) 로 횡단면 중앙값 방향 축소 (James-Stein 취지)"),
    factor_correlation_warnings = fw_warn,
    tdc_summary = as.list(round(unlist(TD), 4)),
    tdc_note = "경험적 하방 tail dependence: P(f_j <= q10 | f_i <= q10), 일별 팩터수익 756일.",
    cross_sectional_r2_daily_mean = round(R2$r2_xs, 4),
    omega_condition_number = round(R2$cond_omega, 2),
    specific_risk_estimated_names = length(ASSETS) - R2$n_short_specific,
    specific_risk_fallback_names = R2$n_short_specific,
    universe_coverage = list(alpha_universe = 340L, exposures_built = length(ASSETS),
                             missing = length(R2$missing_u),
                             names_below_90pct_daily_coverage = 340L - length(R2$keep_t),
                             note = "표본/LW/Gerber 계열은 완전행렬을 요구해 10종을 버려야 했다. 팩터모형은 결측일을 그 날의 횡단면에서만 제외하므로 340/340 을 모두 싣는다 — 이 라운드에서 팩터모형을 고른 두 번째 이유."),
    method_shopping_log = list(candidates_tried = 5L, cap = 5L, method_log = mlog),
    validation = list(
      in_sample_daily_calibration = lapply(seq_len(nrow(R5$CAL)), function(i) as.list(R5$CAL[i])),
      walkforward_bias_test = list(
        design = "24 테스트월 x 100 무작위 균등 25종 바스켓. 각 월의 Sigma 는 그 달 시작 이전 756거래일만으로 재추정(C1). 무작위 바스켓이므로 alpha 와 독립 — 추정품질 계기이지 비중 권고가 아니다.",
        bias_stat_final_config = round(R5$bias_final$bias_stat, 4),
        mean_z = round(R5$bias_final$mean_z, 4), n_observations = R5$bias_final$n,
        ideal = 1.0,
        per_method = lapply(seq_len(nrow(bias)), function(i) as.list(bias[i]))),
      temporal_aggregation_check = list(
        monthly_realized_vol_ann = round(R5$mo_vol_ann, 5),
        sqrt21_scaled_daily_vol_ann = round(R5$CAL[basis=="ew_top25_reference", realized_vol_ann], 5),
        ratio = round(R5$agg_ratio, 4)),
      benchmark_window_realized_vol_ann = round(R5$bm_win_ann, 5),
      underprediction_decomposition = paste0(
        "walk-forward bias ", round(R5$bias_final$bias_stat,3), " = (a) 일별 in-sample 보정 ",
        round(R5$CAL[basis=="ew_top25_reference", ratio],3), " x (b) 시간집계 ",
        round(R5$agg_ratio,3), " x (c) 잔여 out-of-sample 노후화 ",
        round(R5$bias_final$bias_stat / (R5$CAL[basis=="ew_top25_reference", ratio] * R5$agg_ratio), 3),
        ". (b)는 일별 공분산 x21 이 월간 실현분산을 재현하지 못한다는 뜻이고(변동성 군집), ",
        "(c)는 후행 3년 창이 국면 전환을 늦게 따라간다는 뜻이다. ",
        "★따라서 본 Sigma 의 **수준**은 월간 위험을 약 ", round(100*(R5$bias_final$bias_stat-1)), "% 과소표시한다. ",
        "MVO 계열 비중은 Sigma 의 균일 스칼라배에 불변이므로 비중 자체에는 영향이 없으나, ",
        "위험목표·CVaR 예산·TE 상한을 **수준**으로 거는 소비자는 이 배율을 알아야 한다."),
      covariance_freshness = list(cache_used = FALSE, computed_at = as.character(Sys.time()),
                                  asof = as.character(SIG),
                                  note = "R6 SLA — .cache/covariance/*.parquet 재사용 없이 본 WT 에서 신규 추정. stale 판정 대상 아님.")),
    parallel_exec = FALSE, n_workers = 1L),

  red_flags = list(
    list(id="RF-R1", severity="HIGH", triggered=TRUE,
         value=round(100*grp[["MKT.MKT"]],2),
         detail=paste0("top_common_risks[0] = Market ", round(100*grp[["MKT.MKT"]],1), "% > 40%. ",
           "롱온리·Sigma w=1·25종 제약 아래에서는 구조적이다(무신호 EW 유니버스도 시장분산 지배). ",
           "노출 상한 조정은 optimizer scope — 여기서는 측정·통보만 한다."),
         handoff="optimizer"),
    list(id="RF-R2", severity="HIGH", triggered=FALSE,
         value=round(R5$cond_m,2),
         detail=paste0("shrinkage 후 condition ", round(R5$cond_m,1), " <= 500. ",
           "shrinkage 전 ", round(R3$cal[floor_frac==0.25, cond],1), " 였다. 자동 재추정 조건 해소.")),
    list(id="RF-R3", severity="MEDIUM", triggered=length(crowding_flags) > 0,
         value=round(max(CR$crowding_score, na.rm=TRUE),4),
         detail=paste0("최대 crowding_score ", round(max(CR$crowding_score, na.rm=TRUE),3),
           " (Momentum_6_1) < 0.75 임계. 3개월 delta 최대 +",
           round(max(CRd$delta_3m, na.rm=TRUE),3), " < 0.15 → RAPID_INCREASE 아님.")),
    list(id="RF-R4", severity="HIGH", triggered=scen$market_down_5 < -0.08,
         value=round(scen$market_down_5,5),
         detail=paste0("market_down_5 = ", round(100*scen$market_down_5,2), "% (임계 -8%). ",
           "미발화이나 여유가 크지 않다 — 조건부 시장베타가 1 을 넘는다(", round(scen$market_down_5/-0.05,3), "배).")),
    list(id="RF-R5", severity="MEDIUM", triggered=nrow(hp) >= 2,
         value=nrow(hp),
         detail=paste0("핵심 스타일 간 |corr|>0.8 쌍 ", nrow(hp), "개 (임계 2개). ",
           if (nrow(hp)) paste0("발견: ", paste(fw_warn, collapse="; "),
           ". Size 와 Liquidity 는 KR 에서 사실상 같은 축이며 이 다중공선성이 cap-w 극단 틸트의 분산추정을 부풀린다(cap-w proxy 예측/실현 비 ",
           round(R5$CAL[basis=="k200_capw_proxy", ratio],3), " vs EW 유니버스 ",
           round(R5$CAL[basis=="ew_universe_340", ratio],3), ").") else ""))),

  evaluation_criteria_selfcheck = list(
    sigma_positive_semidefinite = list(pass=TRUE, min_eigenvalue=signif(R5$min_eig_m,6)),
    condition_number_lt_500 = list(pass = R5$cond_m < 500, value = round(R5$cond_m,2)),
    factor_coverage_gt_80 = list(pass = (R4$fac_var_d/R4$tot_var_d) > 0.80,
      portfolio_factor_variance_share = round(R4$fac_var_d/R4$tot_var_d,4),
      daily_cross_sectional_r2 = round(R2$r2_xs,4),
      note = "두 수를 구분할 것. 94.7% 는 기준바스켓 **분산**의 팩터 설명분(분산화로 개별위험이 상쇄된 결과)이고, 31.8% 는 개별종목 일별수익의 횡단면 R2 다. 전자를 '종목 수익의 94.7% 를 설명한다'로 읽으면 과대주장이다."),
    stress_policy = list(pass = scen$market_down_5 > -0.10, market_down_5 = round(scen$market_down_5,5)),
    combined_ir_estimate = list(
      note = "본 항목은 계기이지 산출물이 아니다. 비중 벡터는 계산하지도 저장하지도 않았다.",
      unconstrained_ir_ceiling_grinold_kahn = NA,
      reason_not_computed = "제약 없는 IR 상한 sqrt(alpha' Sigma^-1 alpha) 는 그 정의상 Sigma^-1 alpha(=제약없는 MVO 비중)를 경유한다. 역할 경계(비중 결정 = Optimizer)를 형식적으로도 넘지 않기 위해 계산을 생략한다. 대신 optimizer 가 소비할 수 있도록 Sigma·벤치 공분산·alpha 를 모두 갖춘 상태로 넘긴다.")),

  challenge_flags = list(
    list(id="RISK-1", severity="HIGH", target="infrastructure/hrp_core.R",
         claim="인라인 ledoit_wolf 는 p<n 에서도 축퇴한다 — 기존 가드는 p>n 에서만 경고한다.",
         evidence=paste0("p=330, n=756 (p<n) 인데 cond=1.000, 상관구조 보존율 0.000, walk-forward bias 3.042. ",
           "hrp_core.R 의 lw_degenerate 가드는 조건이 p>n_obs 라 발화하지 않았고 경고도 attr 도 붙지 않았다. ",
           "즉 '경고 없음'이 '건전함'을 뜻하지 않는 구간이 존재한다."),
         action="본 WT 는 해당 추정기를 배제하고 factor_bwb_d 를 채택. 인프라 수정은 본 에이전트 권한 밖이므로 통보만 한다."),
    list(id="RISK-2", severity="MEDIUM", target="alpha_package.diagnostics.beta",
         claim="beta 0.869 는 창 의존적이다 — 다른 창에서 다른 값이 나오므로 인용 시 창을 명시해야 한다. ★본 실측은 alpha 의 논거를 뒤집지 않고 오히려 같은 방향이다.",
         evidence=paste0("2023-08~2026-07 **일별** 창에서 기준바스켓 beta = ", round(beta_now,3),
           ", 유니버스 EW 340종 beta = ", round(beta_ew,3), ". alpha 의 0.869 는 2005~2026 **월별** 추정이다. ",
           "★자기적대검증에서 이 항목의 초안 주장('현재는 beta 가 1 근처')이 자기 수치로 반증됐다 — ",
           "실측 ", round(beta_now,3), " 은 0.869 보다 **더 낮다**. 따라서 alpha 의 거울상 논거(beta<1 이면 ",
           "PORT_t 가 알파를 과소표시)는 최근 창에서 약화되는 게 아니라 오히려 강화된다. ",
           "남는 실질 이의는 부호가 아니라 **폭**이다: 같은 대상의 beta 가 창/주기에 따라 0.61~0.87 로 흩어지므로 ",
           "'과소표시' 보정의 크기를 이 값으로 정량화하면 창 선택이 결론을 만든다."),
         action=paste0("alpha_vector 는 수정하지 않는다(read-only). 하류가 beta 논거를 인용할 때 ",
           "추정 창·주기를 함께 적을 것을 권고한다. 부호 주장 자체에는 이의 없음.")),
    list(id="INFRA-1", severity="LOW", target="02_Infrastructure/portfolio/tail_risk_engine.R",
         claim="fExtremes 미설치로 tail_risk_engine.R 이 로드 자체가 불가하다.",
         evidence="library(fExtremes) 에서 'there is no package called fExtremes'. evir / PerformanceAnalytics 는 설치되어 있다.",
         action="공유 인프라를 수정하지 않고 evir 기반으로 GPD/CF/CDaR 를 국소 재구현(Pfaff 2016 Ch.6/7/12 동형). 수치 출처는 본 WT 스크립트 r4_diagnostics.R.")),

  boundary_selfcheck = list(
    alpha_signal_added = FALSE, alpha_vector_modified = FALSE,
    weights_proposed = FALSE, weight_vector_emitted = FALSE,
    stock_quality_judgement = FALSE, overlay_applied = FALSE,
    grade_declared = FALSE,
    note = "기준바스켓 EW 는 위험구조를 읽기 위한 진단 기준선이며 risk_package 어디에도 비중 벡터를 저장하지 않았다. 종목 언급은 유동성 표(days-to-liquidate 상위 5)뿐이고 그것은 용량 측정이지 종목 선호가 아니다."),

  pit_compliance = list(
    sig_date = as.character(SIG),
    hard_cut = "RAWDATA 14,097,000 -> 14,045,583 rows (sig_date 초과 51,417행 폐기). BM_DT 동일 컷.",
    C1 = "PASS — Sigma/Omega/D 전부 롤링 756거래일. 노출 z-score 는 각 월 횡단면 독립. full-sample 통계 0.",
    C2 = "PASS — 노출 B_m 은 월말 m-1, 팩터수익은 m 월 일별. 동일일 순환참조 없음.",
    C4 = "PASS — 재무(TotalEquity)는 상류 S1 의 Factor_Date <= sig_date rolling join 승계.",
    C6 = "PASS — 각 월 횡단면은 그 달의 PIT 멤버십(mem)만. 레짐 상관도 창별 생존종목만 사용.",
    C9 = "N/A — DD/VT 오버레이 미적용(S0/S1 금지 준수).",
    C10 = "PASS — 유동성 ADV20 는 t-1 기준(build_adv20_t1) 승계분.",
    C11 = "PASS — 실현 월별 계열을 holding_ym <= 2026-07 로 절단(259 -> 258). 2026-08 은 sig_date 시점 미실현.",
    C15 = "PASS — V01_BM 은 상류 S1 이 load_month_factors() 경유로 적재. 본 단계 parquet 직접 load 없음.",
    lookahead_detector = "미해당 — 본 단계 산출물에 신호/전략 코드 없음(공분산 추정만). 하드 게이트는 상류 alpha 단계에서 통과."),

  handoff_to_optimizer = list(
    sigma_units = "monthly (annualize x 12)",
    alpha_units = "expected 1M active return (alpha_package 원문) — 단위 정합 확인됨",
    n_assets = length(ASSETS),
    tracking_error_recipe = "TE^2 = (w - w_b)' Sigma (w - w_b). w_b 는 benchmark_covariance.parquet 의 bench_weight_proxy (K200 cap-w, 194종). Cov(r_i, r_bench) 는 같은 파일의 cov_with_bench_monthly.",
    level_caveat = paste0("Sigma 의 수준은 월간 실현위험을 약 ", round(100*(R5$bias_final$bias_stat-1)),
      "% 과소표시한다(walk-forward bias ", round(R5$bias_final$bias_stat,3),
      "). 상대비중 최적화에는 무해하나 절대 위험목표에는 배율 보정이 필요하다."),
    structural_finding = paste0(
      "MDD -53.03% 의 위험 귀속: 기준바스켓 분산의 ", round(100*grp[["MKT.MKT"]],1),
      "% 가 시장, 개별위험은 ", round(100*grp[["SPECIFIC"]],1), "% 뿐이다. GFC 구간 실측도 전략 -42.0% vs 벤치 -36.5% 로 ",
      "초과손실이 -5.4%p 에 그친다. 즉 이 낙폭은 종목선택 실패가 아니라 **베타 낙폭**이다. ",
      "롱온리·Sigma w=1·25종 안에서 분산으로 줄일 수 있는 몫은 개별위험 ", round(100*grp[["SPECIFIC"]],1),
      "% 가 상한이며, 그 상한은 국면에 따라 더 줄어든다(HIGHVOL 평균 쌍상관이 LOWVOL 대비 ",
      round(100*(REG[regime=="HIGHVOL", mean_pairwise_cor]/REG[regime=="LOWVOL", mean_pairwise_cor]-1),1),
      "% 높다). 오버레이는 S0/S1 금지이므로 본 단계에서 적용하지 않았고, 이 사실은 판정이 아니라 좌표다."),
    not_provided = list(weights = "Optimizer 소관", alpha_reinterpretation = "Alpha 소관",
                        grade = "essence_score.R (체인 종점)")),

  verdict = "risk_package_emitted",
  chain_obligation_ack = "도훈 2026-08-29 체인 완주 의무 — alpha 구간의 음성 판정(AMP2013 음상관 전제의 KR 구성 아티팩트 판정)은 본 구간을 멈추는 근거가 아니며, 하류 optimizer/forge 가 그대로 소비 가능한 완전 패키지를 발행했다."
)

write_json(pkg, file.path(MB, "risk_package.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 10, na = "null")
cat(sprintf("[R6] risk_package.json written (%.1f KB)\n", file.size(file.path(MB,"risk_package.json"))/1024))

## ── lineage (write_json 이후 — L-194 순서 규약) ─────────────────────────────
source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
lin <- tryCatch(record_package_lineage(
  task_id = TID, package_type = "risk_package", method_selected = "factor_bwb_d",
  input_file_paths = c(file.path(MB, "alpha_package.json"),
                       file.path(OUT, "alpha_scores.parquet"),
                       file.path(OUT, "period_returns_production.csv")),
  windows = list(list(name="estimation_rolling", from=as.character(min(win_d)), to=as.character(max(win_d)), trading_days=R2$WIN_D),
                 list(name="biastest_walkforward", from="2024-08-30", to="2026-07-31", months=24))),
  error = function(e) paste("LINEAGE_ERR:", conditionMessage(e)))
print(lin)

## ── challenge (R3) — 반론 있음 ──────────────────────────────────────────────
source(file.path(ROOT, "02_Infrastructure/worktask/worktask_manager.R"))
ch <- if (nzchar(Sys.getenv("SKIP_CHALLENGE"))) "SKIPPED (already recorded round 1)" else tryCatch(wt_challenge(TID, from_agent="risk", to_agent="alpha",
  reason=paste0("RISK-2: beta 는 창 의존 — 2023-08~2026-07 일별 창 실측 beta = ", round(beta_now,3),
                " (유니버스 EW ", round(beta_ew,3), ") vs alpha 의 전기간 월별 0.869. ",
                "부호 주장(beta<1)에는 이의 없고 오히려 강화된다 — 이의는 폭(0.61~0.87 산포)이며 ",
                "'과소표시' 보정을 정량화할 때 창 명시가 필요하다는 것이다. alpha_vector 수정 요구 아님. ",
                "별건 RISK-1(hrp_core ledoit_wolf p<n 축퇴)은 인프라 통보.")),
  error = function(e) paste("CHALLENGE_ERR:", conditionMessage(e)))
print(ch)
cat("[R6] done\n")
