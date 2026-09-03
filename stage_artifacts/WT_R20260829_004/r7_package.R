# R7 — risk_package.json 조립 + lineage + challenge review
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
S1<-readRDS(file.path(OUT,"risk_calc_stage1.rds")); S2<-readRDS(file.path(OUT,"risk_calc_stage2.rds"))
S3<-readRDS(file.path(OUT,"risk_calc_stage3.rds")); S4<-readRDS(file.path(OUT,"risk_calc_stage4.rds"))
TID <- "WT-R20260829_004"; SIG <- "2026-08-28"
fs <- sort(S2$fac_share, decreasing=TRUE)
grp <- S2$grp_share; spec <- S2$spec_share
top_common <- c(sprintf("Market (%.1f%%)", 100*grp[["Market"]]),
                sprintf("Style_Momentum (%.1f%%)", 100*S2$fac_share[["x_mom"]]),
                sprintf("Style_Volatility (%.1f%%)", 100*S2$fac_share[["x_vol"]]),
                sprintf("Sector_반도체 (%.1f%%)", 100*S2$fac_share[["SEC_반도체"]]),
                sprintf("Specific (%.1f%%)", 100*spec))
MSL <- lapply(S1$MS, function(x) list(
  name=x$name, cond_omega_live=x$cond_omega_live, cond_sigma=x$cond_sigma, psd_sigma=x$psd_sigma,
  bias_stat_random_all=x$bias_random, bias_stat_random_highvol=x$bias_random_highvol,
  bias_stat_sleeve_all=x$bias_sleeve, n_random=x$n_random,
  implied_port_vol_ann_ew=x$port_vol_ann_ew,
  selected=identical(x$name, S2$SEL)))
names(MSL) <- NULL

reg <- S2$reg
CSn <- S4$CSn
crowd <- lapply(seq_len(nrow(CSn)), function(i){ z <- as.list(CSn[i]); z })
crowd_flags <- as.character(CSn[alert!="none"]$factor_name)

conc <- S3$concentration
liq  <- S3$liquidity
sc   <- S3$stress_scenarios
stt  <- S3$stress_historical

## ── Red flags ─────────────────────────────────────────────────────────────
rf <- list()
add_rf <- function(id, sev, cond, msg) if (isTRUE(cond)) rf[[length(rf)+1L]] <<- list(id=id, severity=sev, message=msg)
add_rf("RF-R1","HIGH", grp[["Market"]] > 0.40,
  sprintf("as-of 총위험의 %.1f%% 가 Market 단일 성분(문턱 40%%). ★단일 스냅샷 아티팩트 방어: walk-forward 평균 시장share %.1f%%(n=%d), alpha F2 실현분산 분해 50.4%% — 세 계기가 모두 40%% 초과이므로 아티팩트가 아니라 구조다. as-of 값이 큰 것은 현 vintage 의 시장변동성 국면 탓.",
          100*grp[["Market"]], 100*S4$wf_share$Market, S4$wf_share$n))
add_rf("RF-R2","HIGH", S2$cs_a$cond > 500, sprintf("Sigma condition number %.1f > 500", S2$cs_a$cond))
add_rf("RF-R3","MEDIUM", length(crowd_flags) > 0, paste("crowding flags:", paste(crowd_flags, collapse=",")))
add_rf("RF-R4","HIGH", sc$market_down_5 < -0.08, sprintf("market_down_5 = %.3f < -8%%", sc$market_down_5))
add_rf("RF-R5","MEDIUM", nrow(S2$fc_warn) >= 2,
  sprintf("요인 상관 |rho|>0.8 쌍 %d개 (섹터 요인 간 — 시장 제거 후 잔여 공통성분 잔존)", nrow(S2$fc_warn)))
add_rf("RF-R6-CONCENTRATION","HIGH", conc$top_sector_weight > 0.50,
  sprintf("섹터 집중 극단: %s %.0f%% (13/25 종목) — failure_rules '>50%% 극단' 해당. 섹터 HHI %.3f",
          conc$top_sector, 100*conc$top_sector_weight, conc$sector_hhi))
add_rf("RF-R7-VINTAGE","HIGH", TRUE,
  sprintf("현 vintage 위험수준이 표본 최고치: as-of Sigma 함의 연율 vol %.1f%% (표본 평균 실현 %.1f%%, 직전 12개월 실현 62.7%%). Market factor EWMA 연율 vol 59.4%% (전기간 23.4%%). Sigma 수준을 through-the-cycle 로 소비하지 말 것.",
          100*sc$portfolio_vol_ann, 100*0.3114))

## ── data integrity (비-침묵 보고) ─────────────────────────────────────────
di <- list(
  finding="일간 수익 패널에 법정 가격제한폭 초과 관측 267건(0.00754%) — 무상증자/액면분할 미조정 아티팩트(+9.0=x10, +4.0=x5, 최대 +65.86=x66.9)",
  handling="Sigma 추정 substrate 에 한해 KRX 일간 가격제한폭 규칙으로 winsorize(2015-06-15 이후 ±31%, 이전 ±16%). 규칙 기반이며 데이터 스누핑 아님. alpha 산출물은 수정하지 않음(read-only).",
  worst_dates=c("2026-04-30 (17건, 최대 +6586%)","2026-08-28","2026-07-31","2026-07-21","2026-08-14","2026-08-25"),
  n_affected_obs=267L, pct_of_panel=0.0000754,
  impact_on_alpha_selection="형성창(J=6 skip1) 경유로 오염 종목이 그 달 top-25 에 진입한 사례 12건 / 6475 보유슬롯(0.19%). 현재 top-25 및 pool-50 에는 오염 종목 0건. 오염월 ∩ 패닉 신호월 = 공집합 → 패닉 분기(저변동 선택)의 26개월은 무오염.",
  impact_on_sigma="winsorize 전후 as-of EW 연율 vol 62.8% -> 65.3% (요인 substrate 재추정). 방향은 결함 제거가 vol 을 낮추는 쪽이 아니었다 — 즉 현 vintage 의 고위험은 오염이 만든 것이 아니다.",
  market_vintage_check=list(
    note="BM(KOSPI200) 2026 연율 vol 69.5%(전기간 23.4%) 이 벤치 계열 결함인지 실제 국면인지 통제로 판별",
    bm_2026_vol_ann=0.6953, cap_weighted_universe_2026_vol_ann=0.6563,
    equal_weighted_universe_2026_vol_ann=0.4094, corr_bm_vs_capweighted_2026=0.9932,
    verdict="BM 결함 아님 — 시가총액가중 유니버스가 동일하게 65.6% 이고 상관 0.993. 2026 고변동은 실데이터 국면이며 대형주 구간에 집중(EW 40.9% << CW 65.6%)."),
  escalation="Q-Lead/judge 판단 대상. risk 는 Sigma substrate 정정만 수행하고 alpha 값을 고치지 않았다(Charter 원칙 8).")

## ── 국면별 Sigma 이질성 ───────────────────────────────────────────────────
WF <- S2$WF
regime_block <- list(
  label_source="stage_artifacts/WT_R20260829_004/regime_signal_timeseries.parquet (alpha 산출)",
  c5_compliance="일자 d 의 국면 라벨 = d 가 속한 홀딩월의 라벨. 그 라벨은 used_cutoff(<= holding_month_start)로 확정 — 홀딩월 정보 미사용. risk 는 라벨을 재산출하지 않고 소비만 함.",
  n_panic_months=reg$n_panic_months, n_panic_episodes=4L,
  n_panic_days=reg$n_panic_days, n_normal_days=reg$n_normal_days,
  small_sample_caveat="에피소드 4건(2008-11~2009-09 / 2020-03~07 / 2022-10~2023-05 / 2024-02~03). 실질 자유도는 26개월이 아니라 에피소드 4 — 국면-조건부 Sigma 의 모든 배율은 이 해상도 안에서만 읽을 것.",
  structural_sigma_same_B=list(
    method="현재 노출 B 고정 · Omega 만 국면별(sample + eigen-floor) · D 는 국면 특이분산 배율 kappa 적용",
    vol_ann_panic=reg$vol_ann_panic, vol_ann_normal=reg$vol_ann_normal, vol_ratio=reg$vol_ratio,
    mean_pairwise_corr_panic=reg$mean_pairwise_corr_panic,
    mean_pairwise_corr_normal=reg$mean_pairwise_corr_normal,
    variance_share_panic=reg$share_panic, variance_share_normal=reg$share_normal,
    market_factor_vol_ann_panic=reg$market_factor_vol_ann_panic,
    market_factor_vol_ann_normal=reg$market_factor_vol_ann_normal,
    specific_var_kappa_panic_over_normal=reg$specific_var_kappa,
    cond_panic=reg$cond_panic, cond_normal=reg$cond_normal,
    reading="패닉에서 바뀌는 것은 상관(0.2201 -> 0.2213, 사실상 불변)이 아니라 시장성분 비중(46.5% -> 54.4%, +7.9pp)이다. 총 vol 배율은 1.08 에 그친다. 즉 이 책의 패닉 위험은 '전면 동조화'가 아니라 '시장성분 회전'으로 온다."),
  realized_holdings_level=list(
    method="보유 25종의 일간 상관/슬리브 vol 을 홀딩월 단위로 실측(구성 전환 포함)",
    n_months_panic=26L, n_months_normal=233L,
    mean_pairwise_corr_panic=S2$realized[panic==1]$mean_corr,
    mean_pairwise_corr_normal=S2$realized[panic==0]$mean_corr,
    vol_ann_panic=S2$realized[panic==1]$vol_ann, vol_ann_normal=S2$realized[panic==0]$vol_ann,
    vol_ratio_realized=S2$realized[panic==1]$vol_ann/S2$realized[panic==0]$vol_ann,
    reading="실현 패닉 vol 은 오히려 0.81배로 낮다. 구조 Sigma(동일 B)가 1.08배를 말하는데 실현이 0.81배라는 것은 그 격차가 전부 **구성 전환(B 의 이동)** 에서 왔다는 뜻이다 — 이 라운드의 de-risking 레버는 Omega 가 아니라 B 에서 작동했다."),
  ex_ante_knowability=list(
    method="각 패닉월 시작 전 데이터만으로 panic-Omega / normal-Omega 를 추정해 vol 배율을 예측하고 실현 배율과 대조(PIT walk-forward). 첫 에피소드(2008-11~2009-04)는 선행 패닉표본 부재로 제외.",
    n=nrow(WF), pred_ratio_median=median(WF$pred_ratio, na.rm=TRUE),
    realized_ratio_median=median(WF$realized_ratio, na.rm=TRUE),
    correlation=suppressWarnings(cor(WF$pred_ratio, WF$realized_ratio, use="complete.obs")),
    baseline_note="pred 의 분모는 직전 504일 rolling normal-Omega, realized 의 분모는 그 시점까지의 비패닉월 평균 실현 vol — 분모 정의가 다르므로 수준 비교가 아니라 **순위 정보 유무**로 읽을 것.",
    verdict="NO_TIMING_INFORMATION",
    reading="상관 0.169(n=20). 국면-조건부 Sigma 배율은 사전에 알 수 없다. optimizer 가 패닉 국면 예측 Sigma 로 위험회피를 스케일하면, 실현이 오히려 낮았던 달에 과잉 de-risking 하게 된다. ★이 축의 오버레이 소비는 'Sigma 배율 타이밍'이 아니라 '구성(B) 전환'으로만 정당화된다."),
  artifacts=list(panic="stage_artifacts/WT_R20260829_004/covariance_panic.parquet",
                 normal="stage_artifacts/WT_R20260829_004/covariance_normal.parquet",
                 regime_correlation="stage_artifacts/WT_R20260829_004/regime_correlation.parquet"))

## ── challenge flags ───────────────────────────────────────────────────────
chal <- list(
  list(id="RISK-CH1", severity="HIGH", to="optimizer",
       message=sprintf("섹터 집중 %s %.0f%%(13/25). failure_rules 의 '섹터/스타일 집중 극단(>50%%)' 조건에 해당한다. Rule 2 로는 STOP 권고 사안이나 2026-08-29 도훈 체인완주 지시에 따라 ABORT 하지 않고 flag 로 넘긴다 — optimizer 는 섹터 제약을 명시적으로 다루거나, 다루지 않기로 한 근거를 남길 것. (risk 는 비중을 제안하지 않는다)",
                       conc$top_sector, 100*conc$top_sector_weight)),
  list(id="RISK-CH2", severity="HIGH", to="optimizer/forge",
       message="as-of Sigma 는 표본 최고 변동성 vintage 에서 추정됐다(EW 함의 연율 vol 68.8%, 전기간 실현 31.1%). Sigma 수준을 through-the-cycle 위험으로 쓰면 과대 de-risking, 반대로 장기 평균 Sigma 를 쓰면 현 vintage 과소. 두 vintage 를 병기해 두었으니 어느 쪽을 소비했는지 forge 산출물에 명시할 것."),
  list(id="RISK-CH3", severity="HIGH", to="alpha/Q-Lead",
       message="데이터 무결성: 법정 가격제한폭 초과 267건(무상증자·액면분할 미조정). alpha 선택 경로 침투는 12/6475 슬롯(0.19%)이고 패닉월과는 공집합이라 alpha 실측 판정은 바뀌지 않는다. 다만 원장 수준의 수리 대상이다 — risk 는 Sigma substrate 만 정정했고 alpha 값은 손대지 않았다."),
  list(id="RISK-CH4", severity="MEDIUM", to="optimizer",
       message="국면-조건부 Sigma 배율은 사전 인지 불가(pred vs realized 상관 0.169, n=20). 패닉 Sigma 예측으로 위험회피를 스케일하는 설계는 근거 없음. 실현 패닉 vol 은 비패닉의 0.81배였고 그 개선은 전부 구성 전환(B)에서 왔다."),
  list(id="RISK-CH5", severity="MEDIUM", to="alpha",
       message="alpha F2(시장성분 50.4%)에 대한 독립 확인: 요인모형 walk-forward 평균 시장분산 share 42.7%(n=235), as-of 68.8%. 두 계기가 방법이 다른데 같은 방향이므로 F2 의 시장지배 판정은 강화된다 — 이 축의 위험은 특이성분이 아니라 시장에 있다."),
  list(id="RISK-CH6", severity="MEDIUM", to="optimizer/forge",
       message="꼬리: 좌측 Hill alpha 2.60(3차 적률 발산) · EVT-GPD xi 0.156>0(Frechet) · 시장과의 하방 tail dependence 0.579 · CDaR95 57.6%. 정규성 가정 위험모형(평균-분산 단독)은 이 책의 꼬리를 과소평가한다.")
)

pkg <- list(
  task_id=TID, as_of_date=SIG, agent="risk-research", spec_version="risk_package_v1.2",
  wt_type="reinforcement", keyword_axis="risk_overlay",
  upstream=list(alpha_package="qepm/mailbox/worktask/WT-R20260829_004/alpha_package.json",
                alpha_verdict_note="F2 FAIL · F6 FAIL · F7 FAIL (검정력 0.876 powered null). risk 는 판정을 바꾸지 않으며 체인 완주 지시(2026-08-29)에 따라 하류 소비 가능한 완전형을 발행한다.",
                alpha_vector_modified=FALSE, weights_proposed=FALSE, overlay_applied=FALSE,
                grade_declared=FALSE),
  pit=list(sig_date=SIG, decision_ts=SIG,
    C1_rolling_only="Omega = 직전 504 영업일 EWMA(hl=126) · D = 직전 24개월 EWMA(hl=6M) · beta = 252일 rolling(Blume). full-sample 통계 없음. 국면 Omega 는 <= sig_date 전체 표본이지만 미래참조 없음이며, 사전 인지가능성은 별도 walk-forward 로 실증(ex_ante_knowability).",
    C5_regime_timing="국면 라벨 재산출 없음 — alpha 의 regime_signal_timeseries(used_cutoff <= holding_month_start) 소비만. anchor_date / realized_ym 미사용. 일자 라벨은 그 일자가 속한 홀딩월의 사전확정 라벨.",
    C6_survivorship="K200/KQ150 시변 멤버십(PIT) 패널 승계 — 생존자 소급 없음.",
    C9_dd_lag="낙폭 계열 진단은 전기 값만: dd_lag <- c(0, dd_pct[-n]). 동일자 낙폭/변동성 스케일 참조 없음.",
    C10_liquidity="ADV20 은 t-1 이전 20영업일만(Date < sig_date).",
    C11_time_axis="외부 매크로 미사용 — 시계열 축은 KRX 거래일 하나. 벤치 일간 수익도 동일 축.",
    C15_factor_db="Factor DB parquet 직접 로드 없음 — 패널은 alpha 가 넘긴 panel.rds / alpha_scores.parquet 소비.",
    overlay_applied=FALSE,
    overlay_note="S0/S1 오버레이 금지 준수 — risk 는 오버레이를 적용하지 않는다. 패닉 국면의 Sigma 구조만 진단해 optimizer 가 소비할 형태로 넘긴다."),
  exposure_matrix_ref="stage_artifacts/WT_R20260829_004/exposure_matrix.parquet",
  factor_covariance_ref="stage_artifacts/WT_R20260829_004/factor_covariance.parquet",
  specific_risk_ref="stage_artifacts/WT_R20260829_004/specific_risk.parquet",
  security_covariance_ref="stage_artifacts/WT_R20260829_004/covariance.parquet",
  security_covariance_panic_ref="stage_artifacts/WT_R20260829_004/covariance_panic.parquet",
  security_covariance_normal_ref="stage_artifacts/WT_R20260829_004/covariance_normal.parquet",
  tail_risk_ref="stage_artifacts/WT_R20260829_004/tail_risk.json",
  regime_correlation_ref="stage_artifacts/WT_R20260829_004/regime_correlation.parquet",
  covariance_units=list(matrix="monthly variance (1M horizon)", n_assets=25L,
    annualize="x12", diagnostic_basis="EW w=1/25 — 진단 집계 기준일 뿐 비중 제안 아님(optimizer 소관)"),
  model=list(
    structure="Sigma = B Omega B' + D",
    factors=list(market="beta(252d rolling, Blume 0.67b+0.33) x KOSPI200 일간수익",
                 sector="27개 섹터 더미(시장성분 제거 후 일간 횡단면 WLS, sqrt(Size) 가중)",
                 style=c("x_size(log 시총 z)","x_mom(JT1993 6M skip1 z)","x_vol(126d 실현변동성 z)","x_liq(log ADV20 z)")),
    n_factors=32L, n_live_factors=length(attr(S2$Om_f,"live")),
    estimation="일간 횡단면 회귀 5321일(2005-02~2026-08) → 요인수익 시계열 → Omega(EWMA hl126, 504일) · D(월별 특이분산 EWMA hl 6M, 24개월)",
    exposure_timing="신호월말(t) 노출 → 홀딩월(t+1) 일간수익 회귀 (월내 노출 고정)"),
  risk_summary=list(
    top_common_risks=top_common,
    variance_decomposition_asof=list(Market=grp[["Market"]], Sector=grp[["Sector"]],
                                     Style=grp[["Style"]], Specific=spec),
    variance_decomposition_walkforward_mean=list(Market=S4$wf_share$Market, Sector=S4$wf_share$Sector,
      Style=S4$wf_share$Style, Specific=S4$wf_share$Specific, n_months=S4$wf_share$n,
      note="as-of 단일 스냅샷 아티팩트 방어(risk-style Cycle2 교훈). 판정은 walk-forward 로 읽을 것."),
    residual_D_share=list(asof=spec, normal_regime=reg$share_normal$Specific,
      panic_regime=reg$share_panic$Specific,
      reading=sprintf("as-of 특이분산 비중 %.1f%% — 시장성분이 %.1f%% 를 먹고 잔차가 거의 남지 않는다. 장기(normal-Omega) 기준으로는 %.1f%% 로 회복되므로, '잔차가 없다'가 아니라 '현 vintage 에서 시장에 눌려 있다'가 정확한 서술.",
        100*spec, 100*grp[["Market"]], 100*reg$share_normal$Specific)),
    portfolio_beta=list(asof_exposure_weighted=sc$portfolio_beta, walk_forward_mean=S4$wf_beta,
      alpha_regression_beta=1.035,
      note="노출가중 beta(0.967/0.893)보다 alpha 의 회귀 beta(1.035)가 높다 — 모멘텀 슬리브의 실현 베타가 추정 베타를 상회하는 전형(beta drift). optimizer 는 RF-R1 exposure bound 설계 시 회귀 beta 를 보수측으로 볼 것."),
    portfolio_vol_ann_asof=sc$portfolio_vol_ann,
    crowding_flags=crowd_flags,
    crowding_score_per_factor=crowd,
    crowding_note="Acadian 2026 4성분(HHI/vol집중/passive overlap/수요탄력). 전 요인 0.75 미만 · 3개월 delta 0.15 미만 → LEVEL_HIGH·RAPID_INCREASE 모두 미발화. passive_overlap_proxy=1 은 유니버스 자체가 K200∪KQ150 이라 구조적 상수(판별력 없음) — 해석에서 제외할 것.",
    liquidity_flags=if (liq$n_below_floor>0) sprintf("%d종 ADV20 < 2e8", liq$n_below_floor) else list(),
    liquidity=liq,
    concentration=conc,
    cap_tier_decomposition=S3$cap_tier_decomposition,
    regime_sigma_heterogeneity=regime_block,
    stress_tests=list(
      scenario_sigma_based=sc,
      historical_periods=stt,
      coverage_rule="book coverage < 0.85 구간은 UNRELIABLE 명시(부분 상장 아티팩트 hard-fail 금지). 본 라운드는 전 구간 coverage 1.00 — 단 Terror_9_11 은 표본시작(2005-02) 이전이라 산출 자체가 없다.",
      reading=sprintf("GFC 에서 슬리브 %.1f%% vs BM %.1f%%, 구간 MDD %.1f%% — 전체 MDD(-63.5%%)가 이 한 구간에서 나온다. 2026H2(최근) 에서는 BM +2.2%% 인데 슬리브 -15.9%%, 구간 MDD -38.0%% 로 현 vintage 에서도 하방이 열려 있다.",
                      100*stt$GFC$strat_cum, 100*stt$GFC$bm_cum, 100*stt$GFC$mdd)),
    tail_risk=S3$tail_risk),
  diagnostics=list(
    selection_objective="condition_number",
    selection_rule="① HARD: PSD ∧ cond(Sigma)<500 ② 구조보존: cond(Omega_live)>=10 (등방 붕괴 배제 — FQ-057 NP3 posterior) ③ 위험예측 캘리브레이션: 무작위 롱온리 25종 EW 포트 walk-forward bias statistic(sd(실현/예측), 이상치 1.0). ★알파 수익·SR·IR 참조 없음(R4 P3). ④ 동률 시 cond(Sigma) 최소.",
    selection_decisive_axis="현 횡단면이 유니버스 변동성 상위 터셀에 있으므로 HIGH-vol 터셀 bias 를 결정축으로 사용: ewma_hl126 1.047 vs sample 1.123 / lw_nls 1.129 / ledoit_wolf 1.113 / gerber_rmt 1.199. 정적 창 추정기는 현 국면에서 위험을 12~20% 과소예측한다.",
    ledoit_wolf_rejected="cond(Omega)=1.87 = 등방(mu*I) 붕괴 — 요인 분산 스케일이 이질적일 때 인라인 LW(OAS 변형)가 구조를 전멸시킨다(FQ-057 NP3 와 동형 병리). 슬리브 bias 0.623(60% 과대예측)이 그 귀결.",
    condition_number=S2$cs_a$cond, condition_number_before_floor=S2$cs_b$cond,
    condition_number_omega_before=S2$c_before$cond, condition_number_omega_after=S2$c_after$cond,
    psd_verified=S2$cs_a$psd, min_eigenvalue=S2$cs_a$min_ev,
    shrinkage_used=TRUE, shrinkage_method="ewma_hl126 + eigen-floor(lambda_min = lambda_max/400) on Omega",
    shrinkage_rationale="Sigma cond 는 이미 163(<500)이었으나 Omega cond 8903 은 요인공간 준특이 — 소수 섹터 요인의 EWMA 분산이 0 에 근접. eigen-floor 로 400 으로 조인 뒤 Sigma cond 177(<500) 유지, PSD 확인.",
    method_shopping_log=list(candidates_tried=length(MSL), cap=5L, method_log=MSL),
    factor_correlation_warnings=lapply(seq_len(nrow(S2$fc_warn)), function(i) as.list(S2$fc_warn[i])),
    factor_correlation_note="시장성분 제거 후에도 섹터 요인 간 |rho|>0.8 쌍이 7개 — 27개 섹터가 독립 요인이 아니라는 뜻. Omega 를 그대로 역행렬 하는 최적화(MVO)는 이 지점에서 불안정해진다(HRP/ERC 계열이 이 구조에 더 안전하다는 것은 optimizer 판단 영역).",
    tdc_summary=list(sleeve_vs_market_lower_q05=S3$tail_risk$tail_dependence_lower_vs_market_q05),
    model_fit=S3$model_fit,
    regime_correlation_ref="stage_artifacts/WT_R20260829_004/regime_correlation.parquet",
    covariance_freshness=list(cache_used=FALSE, computed_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S"),
                              covariance_asof=SIG, stale=FALSE,
                              note="R6 SLA — .cache/covariance 캐시 미사용, 본 WT 에서 직접 추정."),
    data_integrity=di),
  evaluation_criteria_selfcheck=list(
    sigma_psd=S2$cs_a$psd, cond_lt_500=(S2$cs_a$cond<500),
    factor_coverage_gt_80pct=(1-spec)>0.80,
    factor_coverage_value=1-spec,
    factor_coverage_note="포트 수준 요인분산 비중 97.0%(기준 충족). 단 개별종목 수준으로 보면 시장성분 제거 후 잔여를 섹터+스타일이 설명한 일간 R2 는 평균 21.8% — 종목 특이위험은 여전히 크고, 25종 EW 집계에서 상쇄되어 포트 비중이 낮게 보이는 것이다.",
    stress_policy_ok=(sc$market_down_5 > -0.08),
    ir_estimate_note="alpha-risk 결합 IR 추정치는 산출하지 않는다 — alpha 수익 참조는 R4 P3 selection_objective 금지 대상이며, 결합 판정은 optimizer/forge 소관."),
  red_flags=rf,
  challenge_flags=chal,
  self_adversarial_challenge_ref="qepm/mailbox/worktask/WT-R20260829_004/challenge_note.md (## risk 구간)",
  verdict="risk_package_complete"
)

write_json(pkg, file.path(MB,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, null="null", na="null")
cat("[R7] risk_package.json 기록 완료:", file.path(MB,"risk_package.json"), "\n")

## lineage — write_json 이후 호출(순서 엄수)
source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(task_id=TID, package_type="risk_package",
  method_selected="ewma_hl126_eigenfloor_factor_model_BOmegaB_plus_D",
  input_file_paths=c("qepm/mailbox/worktask/WT-R20260829_004/alpha_package.json",
                     "stage_artifacts/WT_R20260829_004/alpha_scores.parquet",
                     "stage_artifacts/WT_R20260829_004/regime_signal_timeseries.parquet",
                     "stage_artifacts/WT_R20260829_004/period_returns_production.csv"),
  windows=list(list(name="omega_estimation", start="2024-08-16", end=SIG, n_days=504L),
               list(name="specific_risk", start="2024-09", end="2026-08", n_months=24L),
               list(name="cross_section_regression", start="2005-02", end="2026-08", n_days=5321L)),
  random_seed=20260829L,
  extra=list(selection_objective="condition_number", cond_sigma=S2$cs_a$cond, psd=S2$cs_a$psd))
cat("[R7] lineage 기록 완료\n")
