# RK10 — tail_risk.json + risk_package.json 발행 + lineage + challenge review
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT<-getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
WT  <- "WT-R20260829_007"; WTD <- file.path(ROOT,"qepm/mailbox/worktask",WT)
o3<-readRDS(file.path(OUT,"rk3_objects.rds")); o4<-readRDS(file.path(OUT,"rk4_objects.rds"))
o6<-readRDS(file.path(OUT,"rk6_objects.rds")); o7<-readRDS(file.path(OUT,"rk7_objects.rds"))
o8<-readRDS(file.path(OUT,"rk8_objects.rds")); o9<-readRDS(file.path(OUT,"rk9_objects.rds"))
WF <- readRDS(file.path(OUT,"rk5_wf.rds"))
Om<-o4$Om_lw; Om_s<-o4$Om_s; STY<-o3$STY; Sig<-o6$Sig; asof<-o4$asof
PR <- fread(file.path(OUT,"period_returns_production.csv"))
r3 <- function(x,d=6) if(is.null(x)||all(is.na(x))) NULL else round(as.numeric(x),d)

## LW shrinkage intensity on Omega
Fm2 <- o4$Fm2; p<-ncol(Fm2); n<-nrow(Fm2); S<-cov(Fm2); mu<-mean(diag(S))
rho_om <- min(((n-2)/n*sum(diag(S)^2)+sum(S)^2)/((n+2)*(sum(S^2)-sum(diag(S)^2)/p)),1)

## RF-R5: 요인 상관 > 0.8 pair
sdv <- sqrt(diag(Om)); C <- Om/outer(sdv,sdv)
ut <- which(upper.tri(C) & abs(C)>0.8, arr.ind=TRUE)
fc_warn <- if(nrow(ut)>0) apply(ut,1,function(i) sprintf("%s~%s rho=%.3f", rownames(C)[i[1]], colnames(C)[i[2]], C[i[1],i[2]])) else character(0)
# 스타일/시장 축만 따로
Cs <- C[c("MKT",STY),c("MKT",STY)]
uts <- which(upper.tri(Cs) & abs(Cs)>0.6, arr.ind=TRUE)
fc_style <- if(nrow(uts)>0) apply(uts,1,function(i) sprintf("%s~%s rho=%.3f", rownames(Cs)[i[1]], colnames(Cs)[i[2]], Cs[i[1],i[2]])) else character(0)

## top common risks
grp <- c(MKT="MKT", setNames(rep("SECTOR",length(o4$secs_a)),o4$secs_a), setNames(STY,STY))
cs_tot <- sort(o6$cs, decreasing=TRUE); cs_act <- sort(o7$cs_a, decreasing=TRUE)
mkstr <- function(v) unname(sapply(seq_along(v), function(i) sprintf("%s (%.1f%%)", names(v)[i], 100*v[i])))

## walk-forward bias
mu_r <- mean(WF$ret)
bstat <- function(v){ z<-(WF$ret-mu_r)/sqrt(v); c(bias=sd(z,na.rm=TRUE), n=sum(is.finite(z))) }
wfb <- list(struct_lw_omega=bstat(WF$v_struct_l), struct_sample_omega=bstat(WF$v_struct_s),
            direct_sample=bstat(WF$v_dir_s), direct_lw_linear=bstat(WF$v_dir_l), direct_lw_nls=bstat(WF$v_dir_n))

## method shopping log (상한 5)
methods_tried <- list(
 list(name="sample_direct", family="direct_asset_cov", scope="347 asset universe (120M window, 139 complete-history names)",
      condition_number=r3(o4$diag$r_sample["cond"],1), min_eigenvalue=r3(o4$diag$r_sample["min"],12), psd=FALSE,
      walkforward_bias_25name=r3(wfb$direct_sample["bias"],4), selected=FALSE,
      reject_reason="p>n 에서 특이(rank deficient). 347 자산 도메인에서 PD 아님 — optimizer 가 소비 불가."),
 list(name="ledoit_wolf_linear_direct", family="direct_asset_cov", scope="same",
      condition_number=r3(o4$diag$r_lw["cond"],3), min_eigenvalue=r3(o4$diag$r_lw["min"],8), psd=TRUE,
      walkforward_bias_25name=r3(wfb$direct_lw_linear["bias"],4), selected=FALSE,
      reject_reason=".get_cor_cov p>n 퇴화 가드 발화(rho=1.000 cap binding, cond=1.000 → 상관구조 전멸). 25종 walk-forward bias 2.194 = 위험 과소예측 2.2배."),
 list(name="lw_nls_direct", family="direct_asset_cov", scope="same",
      condition_number=r3(o4$diag$r_nls["cond"],1), min_eigenvalue=r3(o4$diag$r_nls["min"],8), psd=TRUE,
      walkforward_bias_25name=r3(wfb$direct_lw_nls["bias"],4), selected=FALSE,
      reject_reason="PD·조건수 양호하나 완전이력 139/347(coverage 40.1%)만 커버. 347 자산 Σ 를 못 낸다. (FQ-057 P1c 의 'lw_nls 가 linear LW 보다 총분산 채널에서 강건' 은 본 실측에서도 재현: bias 1.107 vs 2.194)"),
 list(name="structural_BOB_D_sample_omega", family="factor_model", scope="347 x 347",
      condition_number=r3(o6$cb["cond"],1), min_eigenvalue=r3(o6$cb["mn"],8), psd=TRUE,
      walkforward_bias_25name=r3(wfb$struct_sample_omega["bias"],4), selected=FALSE,
      reject_reason="PD 이나 조건수 1185.8 > 500 (RF-R2 정책 위반). shrinkage 미적용판."),
 list(name="structural_BOB_D_lw_omega_bayes_D", family="factor_model", scope="347 x 347",
      condition_number=r3(o6$ca["cond"],1), min_eigenvalue=r3(o6$ca["mn"],8), psd=TRUE,
      walkforward_bias_25name=r3(wfb$struct_lw_omega["bias"],4), selected=TRUE,
      selected_reason="347 자산 전역에서 PD · 조건수 301.9 < 500 · walk-forward bias 0.858(보수 방향 14% 과대예측). 유일하게 optimizer 가 요구하는 도메인(347종) 전체를 PD 로 덮는다."))

## crowding
cw <- o8$cw
crowding_list <- lapply(seq_len(nrow(cw)), function(i) c(as.list(cw[i]),
  list(alert = if(cw$crowding_score[i]>=0.75) "LEVEL_HIGH" else if(cw$delta_3m[i]>=0.15) "RAPID_INCREASE" else "NONE")))
crowding_flags <- unlist(lapply(crowding_list, function(z) if(z$alert!="NONE") sprintf("%s: score %.3f (%s)", z$factor_name, z$crowding_score, z$alert) else NULL))
if(is.null(crowding_flags)) crowding_flags <- character(0)

## liquidity
capa <- o8$capa
liq_flags <- c(
  sprintf("CAPACITY_TIGHT: 참여율 10%%·1일 집행 기준 AUM 상한 중앙 %.0f억 KRW (p10 %.0f억). 편도 회전 762%%/yr 가 분모다.",
          median(capa$aum_cap_10pct)/1e8, quantile(capa$aum_cap_10pct,.10)/1e8),
  sprintf("ILLIQUIDITY_TILT: active LIQ(Amihud) 노출 %+.2f sigma (as_of) · 표본평균 %+.2f sigma — 벤치 대비 비유동 편향이 상시적이다.",
          o8$Bd["LIQ"], mean(o7$mono$LIQ_a)))

## stress
ST <- o8$ST
stress_tests <- list(
  market_down_5  = r3(ST$market_down_5["total"]),
  market_down_10 = r3(ST$market_down_10["total"]),
  momentum_reversal_2sd = r3(ST$momentum_reversal_2sd["total"]),
  signal_crash_2sd      = r3(ST$signal_crash_2sd["total"]),
  liquidity_shock_2sd   = r3(ST$liquidity_shock_2sd["total"]),
  vol_shock_2sd         = r3(ST$vol_shock_2sd["total"]),
  size_shock_2sd        = r3(ST$size_shock_2sd["total"]),
  reversal_shock_2sd    = r3(ST$reversal_shock_2sd["total"]),
  gfc_2008      = r3(o7$cr[regime=="GFC_2008",book_ret]),
  eudebt_2011   = r3(o7$cr[regime=="EuDebt_2011",book_ret]),
  china_2015    = r3(o7$cr[regime=="China_2015",book_ret]),
  covid_2020    = r3(o7$cr[regime=="COVID_2020",book_ret]),
  rate_2022     = r3(o7$cr[regime=="RateHike_2022",book_ret]),
  kr_bear_2018  = r3(o7$cr[regime=="KR_Bear_2018",book_ret]))
crisis_detail <- lapply(seq_len(nrow(o7$cr)), function(i) c(as.list(o7$cr[i]),
  list(coverage_note = if(o7$cr$coverage[i] >= 0.85) "OK" else "UNRELIABLE_book_coverage_below_85pct")))

## cap tier
tf <- o9$tier_full; ts_ <- o9$tier_sub; rcr <- o9$rc_real
p3 <- ts_[sub=="P3_2020_2026"]
cap_tier <- list(basis="cap_w_and_ew_uni",
  tier_definition="universe Size tercile per month (SMALL/MID/MEGA). ★alpha 의 diag_cap_tier 는 rank 기반(MEGA=top10 / MID=11-30 / OTHER)이라 정의가 다르다 — 값 충돌이 아니라 정의 차이다.",
  tiers=lapply(c("MEGA","MID","SMALL"), function(k){
    list(tier=k,
         weight_share=r3(tf[tier==k,w_share],4),
         active_risk_share=r3(unname(rcr[k]),4),
         alpha_share_vs_capw=r3(tf[tier==k,contrib_vs_capw],5),
         alpha_share_vs_ewuni=r3(tf[tier==k,contrib_vs_ewuni],5),
         p3_contrib_vs_capw=r3(p3[tier==k,contrib_vs_capw],5),
         p3_contrib_vs_ewuni=r3(p3[tier==k,contrib_vs_ewuni],5),
         signal_alive_capw_basis = isTRUE(p3[tier==k,contrib_vs_capw] > 0),
         signal_alive_ewuni_basis = isTRUE(p3[tier==k,contrib_vs_ewuni] > 0))}),
  dual_basis_divergence_flag = TRUE,
  dual_basis_divergence_note = "P3(2020~) 에서 두 기준이 갈린다: MID 는 cap-w 대비 -3.29%/yr 인데 EW-uni 대비 +0.55%/yr, MEGA 는 cap-w +0.66% vs EW-uni +3.60%. 즉 최근 구간의 tier 판정은 벤치 선택에 종속된다 — 단일 기준으로 tier 사망을 선언하지 말 것.")

## regime heterogeneity
het <- o9$het; sp <- o7$sp
regime_het <- list(
  measurement_note="구간별 Ω 는 **후향적 구조 진단**이다(사후 라벨). 발행 Σ 는 확장창(2005-02~2026-08) 단일 추정이며 구간 Ω 를 소비하지 않는다 — C1 준수.",
  subperiods = lapply(seq_len(nrow(sp)), function(i){ s <- sp$sub[i]; h <- het[subperiod==s]
    list(subperiod=s, months=sp$months[i],
         realized_book_vol_ann=r3(sp$book_vol_ann[i],4),
         realized_name_vol_ann=r3(sp$avg_name_vol_ann[i],4),
         realized_avg_pairwise_corr=r3(sp$avg_pairwise_corr[i],4),
         realized_beta_daily=r3(sp$beta_daily[i],4),
         benchmark_vol_ann=r3(sp$bm_vol_ann[i],4),
         predicted_book_vol_ann_with_subperiod_omega=r3(h$book_vol_pred_ann,4),
         factor_share=r3(h$factor_share,4), specific_share=r3(h$specific_share,4),
         te_vs_capw_ann=r3(h$te_vs_capw_pred_ann,4),
         predicted_beta_vs_capw=r3(h$beta_pred_vs_capw,4))}),
  factor_vol_ann_by_subperiod = lapply(rownames(o7$FV), function(f)
      c(list(factor=f), setNames(as.list(r3(o7$FV[f,],4)), colnames(o7$FV)))),
  mkt_style_correlation_by_subperiod = lapply(names(o7$cormat), function(s)
      c(list(subperiod=s), setNames(as.list(r3(o7$cormat[[s]]["MKT",],4)), colnames(o7$cormat[[s]])))),
  label_free_cross_check = list(
    design="구간 절단점(2015-01 / 2020-01)이 이질성을 만든 것 아닌지 확인하려고 라벨 없는 rolling 36개월 창으로 다시 쟀다.",
    rolling36_book_vol_ann=list(min=0.1499, max=0.2692, ratio=1.80),
    rolling36_avg_pairwise_corr=list(min=0.0895, max=0.2212, ratio=2.47),
    cutpoint_version=list(book_vol_ratio=1.60, corr_ratio=1.50),
    verdict="라벨 없는 창이 오히려 더 넓다(vol 1.80배 vs 1.60배 · corr 2.47배 vs 1.50배). 이질성은 절단점의 산물이 아니다.",
    current_regime_warning="★rolling36 book 변동성의 표본 최댓값이 지금이다(2026-08 = 0.2692, 2026-07 = 0.2666). 확장창 Σ(전 구간 평균)는 **현재 국면 위험을 과소** 표시한다."),
  heterogeneity_verdict = "이질성은 크다. 실현 book 변동성 21.7%(P1) → 17.3%(P2) → 27.7%(P3), 평균 pairwise 상관 0.160 → 0.113 → 0.169, 종목 변동성 46.7% → 43.8% → 56.8%. 요인 축에서는 INDMOM 9.1→8.2→14.4%, REV 5.0→3.8→7.2%, VOL 5.2→5.5→8.0% 로 P3 에서 전 축이 증폭됐다. as_of B·D 를 고정하고 Ω 만 갈아끼우면 예측 TE 가 23.9% → 20.0% → 30.4% 로 27% 벌어진다 — 단일 Σ 로 전 구간을 덮는 것이 이 후보의 1차 모형위험이다.")

## turnover stress
tst <- o8$tstress
turn <- list(
  realized_turnover_twoway_ann=r3(o8$to_2way_ann,4),
  realized_turnover_oneway_ann=r3(o8$to_1way_ann,4),
  turnover_convention="sum|dw| x 12 (two-way). 편도 = 절반. alpha diagnostics turnover_proxy 15.2326 과 동일 원장(period_returns_production.csv::traded_notional).",
  mean_new_names_per_month=r3(mean(o8$turn_names$n_new),3),
  name_replacement_rate=r3(mean(o8$turn_names$n_new)/25,4),
  max_new_names=as.integer(max(o8$turn_names$n_new)),
  breakeven_cost_oneway_bps=r3(o8$be_exact*1e4,2),
  breakeven_multiple_of_15bps=r3(o8$be_exact/0.0015,3),
  cost_grid=lapply(seq_len(nrow(tst)), function(i) as.list(lapply(tst[i], function(z) if(is.numeric(z)) round(z,6) else z))),
  execution_timing_exposure_note="월 평균 15.9/25 종목(63.6%)이 교체된다 — 매 리밸일 book 의 2/3 가 신규 포지션이다. 집행이 하루 밀리면 그 하루의 종목 수익 분산이 그대로 성과 분산으로 들어온다(일간 종목 변동성 중앙 %s%%/yr 기준).",
  liquidity_capacity=list(
    rule="종목당 편도 거래 notional = AUM x (two-way TO / 2) / 25. 참여율 상한 10% of 20d ADV, 1일 집행, 보유 중 최소 ADV 가 구속.",
    aum_cap_median_krw=r3(median(capa$aum_cap_10pct),0),
    aum_cap_p10_krw=r3(quantile(capa$aum_cap_10pct,.10),0),
    aum_cap_last12m_median_krw=r3(median(tail(capa$aum_cap_10pct,12)),0),
    asof_top25_adv20_median_krw=if(nrow(o8$asof_liq)>0) r3(median(o8$asof_liq$adv),0) else NULL,
    asof_top25_adv20_min_krw=if(nrow(o8$asof_liq)>0) r3(min(o8$asof_liq$adv),0) else NULL),
  risk_verdict="회전 자체가 위험 축이다. 손익분기 편도 40.5bps 는 현행 15bps 의 2.70배이므로 '비용 가정 1축'이 성과 부호를 뒤집는 거리에 있다(50bps 에서 활성수익 -1.52%/yr). 동시에 유동성 용량이 회전에 반비례해 상한 AUM 중앙 31억 KRW 로 눌린다 — 비용과 용량이 같은 분모(회전)를 공유하므로 독립 위험이 아니라 **하나의 위험**이다.")
turn$execution_timing_exposure_note <- sprintf(
  "월 평균 %.1f/25 종목(%.1f%%)이 교체된다 — 매 리밸일 book 의 2/3 가 신규 포지션이다. 집행이 하루 밀리면 그 하루의 종목 수익 분산이 그대로 성과 분산으로 들어온다(보유종목 연율 변동성 표본평균 %.1f%%).",
  mean(o8$turn_names$n_new), 100*mean(o8$turn_names$n_new)/25, 100*mean(sp$avg_name_vol_ann))

## vol / liquidity 잔차 진단
fitc <- summary(o7$fit)$coefficients
vld <- list(
  upstream_label="VOL_INDEPENDENCE_UNPROVEN (alpha F4: L11_Kyle_Lambda +2.557 · D35_RealVol_63d +2.111 · rv63 -2.118 vs 신호 +1.541)",
  risk_side_finding="risk 층에서 재면 얽힘은 '미증명'이 아니라 **측정된다**. book 의 실현 활성수익(vs 벤치)을 위험요인에 회귀하면 LIQ +1.530 (t 9.30) · VOL +0.688 (t 4.84) · SIZE -1.775 (t -12.17) 로 유의하고 R2 0.405 다. 즉 이 후보의 활성수익은 유동성·변동성·규모 축과 동조한다.",
  active_return_on_risk_factors = lapply(rownames(fitc), function(k) list(term=k, beta=r3(fitc[k,1],4), t=r3(fitc[k,3],3), p=r3(fitc[k,4],6))),
  r_squared=r3(summary(o7$fit)$r.squared,4),
  book_style_exposure_asof = as.list(r3(o8$Bw[STY],4)),
  active_style_exposure_asof_vs_capw = as.list(r3(o8$Bd[STY],4)),
  historical_mean_active_exposure = list(VOL_a=r3(mean(o7$mono$VOL_a),4), LIQ_a=r3(mean(o7$mono$LIQ_a),4), SIZE_a=r3(mean(o7$mono$SIZE_a),4)),
  residual_D_entanglement = list(
    corr_specific_vol_vs_VOL_exposure=r3(cor(sqrt(o6$Dv[o6$top]*12), o3$X[Date==asof & Ticker %in% o6$top][match(o6$top,Ticker),VOL]),4),
    corr_specific_vol_vs_LIQ_exposure=r3(cor(sqrt(o6$Dv[o6$top]*12), o3$X[Date==asof & Ticker %in% o6$top][match(o6$top,Ticker),LIQ]),4),
    verdict="잔차 D 는 변동성 축과 무관하지 않다 — 보유 25종의 특이변동성과 VOL 노출의 상관이 +0.768 이다. 7요인을 뺀 뒤에도 vol 축이 D 안에 남는다. optimizer 가 D 를 '독립 잡음'으로 취급하면 vol 집중을 못 본다."),
  time_variation="active LIQ 노출은 상시 양(+1.12~1.31 sigma)으로 안정적이나 active VOL 노출은 P1 +0.36 → P3 +0.29 로 완만히 감소했고 as_of 스냅숏은 -0.76 이다. 단일 스냅숏 β 로 판정 금지(Cycle 2 교훈) — 표본평균과 병기했다.")

## ============ tail_risk.json ============
tail_risk <- list(
  task_id=WT, as_of_date=as.character(asof), agent="risk-research",
  series=list(
    monthly_net=list(n=nrow(PR), window=paste(PR$holding_ym[1],"~",PR$holding_ym[nrow(PR)]),
      mean_ann=r3(prod(1+PR$ret_net)^(12/nrow(PR))-1,5), vol_ann=r3(sd(PR$ret_net)*sqrt(12),5),
      skew=r3(mean((PR$ret_net-mean(PR$ret_net))^3)/sd(PR$ret_net)^3,4),
      excess_kurtosis=r3(mean((PR$ret_net-mean(PR$ret_net))^4)/sd(PR$ret_net)^4-3,4)),
    daily_gross=list(n=5321L, window="2005-02-01 ~ 2026-08-28",
      note="일간 book 은 홀딩월 시작 EW · 월중 drift 로 재구성했다. 월 집계가 period_returns_production.csv::ret_gross 와 최대오차 0.00000 으로 일치한다(재구성 검증).")),
  empirical=list(
    monthly_net=list(VaR_95=r3(o8$tail_emp$monthly_net$q05["VaR"],5), ES_95=r3(o8$tail_emp$monthly_net$q05["ES"],5),
                     VaR_99=r3(o8$tail_emp$monthly_net$q01["VaR"],5), ES_99=r3(o8$tail_emp$monthly_net$q01["ES"],5)),
    daily_gross=list(VaR_95=r3(o8$tail_emp$daily_gross$q05["VaR"],5), ES_95=r3(o8$tail_emp$daily_gross$q05["ES"],5),
                     VaR_99=r3(o8$tail_emp$daily_gross$q01["VaR"],5), ES_99=r3(o8$tail_emp$daily_gross$q01["ES"],5))),
  cornish_fisher=list(monthly_VaR_95=r3(o8$cf95,5), monthly_VaR_99=r3(o8$cf99,5)),
  evt_gpd=list(
    method="evir::gpd (POT / MLE). Pfaff FRM Ch.7.",
    monthly_net=c(lapply(o8$g_m, function(z) r3(z,6)), list(threshold_quantile=0.90)),
    daily_gross=c(lapply(o8$g_d, function(z) r3(z,6)), list(threshold_quantile=0.95)),
    interpretation="xi 0.179(월) / 0.126(일) > 0 → Frechet 영역. 정규 가정이 꼬리를 과소평가한다: 월간 ES99 경험 %s vs EVT 21.69%%."),
  hill_alpha=list(monthly=r3(o8$hill_m,4), daily=r3(o8$hill_d,4),
    interpretation="alpha ~2.5~2.9 → 분산은 유한하나 3·4차 적률은 발산 영역. 표본 분산·첨도 추정치는 불안정하며 Σ 기반 정규 VaR 은 하한이다."),
  drawdown=list(max_drawdown_monthly_net=r3(o8$mdd_m,5), max_drawdown_daily_gross=r3(o8$mdd_d,5),
    cdar_5pct=r3(o8$cdar05,5),
    note="MDD 는 어느 층에서도 등급을 접지 않는다(CLAUDE.md v9.21). 여기서는 구조 낙폭 서술로만 싣는다 — 위험 축 판정은 Calmar 소관이며 그 산출은 forge 다."),
  tail_dependence=list(lower_TDC_5pct=r3(o8$tdc[1],4), lower_TDC_10pct=r3(o8$tdc[2],4),
    benchmark="K200/KQ150 blended BM_Ret (일간)",
    interpretation="★핵심. 무조건부 beta 는 0.737 인데 하방 5% 꼬리에서의 동시발생 확률은 0.545 다(독립이면 0.05). 저-beta 는 '시장이 무너질 때 덜 무너진다'를 뜻하지 않는다 — 평시에 덜 움직였을 뿐이다. COVID 국면 실측 beta 0.946 · 평균 pairwise 상관 0.342(평시 0.141의 2.4배)가 같은 사실의 다른 얼굴이다."),
  regime_tail=lapply(crisis_detail, function(z) list(regime=z$regime, book_ret=r3(z$book_ret,5),
    bm_ret=r3(z$bm_ret,5), book_vol_ann=r3(z$book_vol_ann,5), max_dd=r3(z$max_dd,5),
    avg_pairwise_corr=r3(z$avg_pairwise_corr,4), beta=r3(z$beta,4),
    coverage=r3(z$coverage,3), coverage_note=z$coverage_note)))
tail_risk$evt_gpd$interpretation <- sprintf(
  "xi %.3f(월) / %.3f(일) > 0 → Frechet 영역(두꺼운 꼬리). 월간 ES99 는 경험 %.2f%% vs EVT %.2f%% 로 EVT 가 더 크다 — 표본 259개월이 1%% 꼬리를 4~5건으로만 덮기 때문이다.",
  o8$g_m$xi, o8$g_d$xi, 100*o8$tail_emp$monthly_net$q01["ES"], 100*o8$g_m$ES99)
write_json(tail_risk, file.path(OUT,"tail_risk.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
cat("[RK10] tail_risk.json written\n")

## ============ challenge flags ============
cf <- list()
cf[[length(cf)+1]] <- sprintf("[RF-R1 HIGH · 총위험 기준] top_common_risks[0] = MKT %.1f%% > 40%%. 롱온리 25종 book 의 **총**위험은 구조적으로 시장이 지배한다(w>=0, Sigma w=1 이면 시장 노출을 뺄 수 없다). 같은 Σ 로 **active(vs cap-w)** 를 재면 top 은 SECTOR %.1f%% 이고 MKT 는 0.0%%(active MKT 노출이 정의상 0)다. 40%% 문턱은 active 축에서만 의미가 있다 — 두 축 모두 기재했다.", 100*cs_tot[1], 100*cs_act[1])
cf[[length(cf)+1]] <- sprintf("[RF-R2 해소 · 기록] 구조 Σ 는 shrinkage 전 조건수 %.1f (>500) 였다. LW-Ω(rho=%.4f) + Bayes-D(k=24) + 특이위험 바닥 p10(%.1f%%/yr) 적용 후 %.1f 로 내렸다. ★조건수는 자산수 N 에 선형으로 커진다(공통 시장요인 때문) — 500 문턱은 N-의존이며 25종 walk-forward 에서는 중앙 42.2 였다. 문턱을 N-불변 상수로 읽지 말 것.", o6$cb["cond"], rho_om, 100*sqrt(o6$fl*12), o6$ca["cond"])
cf[[length(cf)+1]] <- sprintf("[★상류 라벨 격상 — VOL_INDEPENDENCE_UNPROVEN → 측정된 얽힘] alpha 는 F4 에서 '누출 귀무가 신호보다 셌다'까지 갔고 라벨을 '미증명'으로 남겼다. risk 층에서 book 의 실현 활성수익을 위험요인에 회귀하면 LIQ +1.530 (t 9.30) · VOL +0.688 (t 4.84) · SIZE -1.775 (t -12.17), R2 0.405 다. 얽힘은 이제 관측이다. ★이것은 alpha 수정이 아니라 위험 진단이며 alpha_vector 는 손대지 않았다.")
cf[[length(cf)+1]] <- sprintf("[★저-beta 의 오독 경고] 무조건부 beta 0.737(alpha) / Σ-예측 beta vs cap-w %.3f 인데 하방 5%% tail dependence 는 %.3f 다. COVID 국면 실측 beta %.3f · pairwise 상관 %.3f(평시 %.3f). 시장 노출이 작다는 것은 위험이 작다는 뜻이 아니라 **꼬리로 옮겨갔다**는 뜻이다. optimizer 가 beta 를 위험 대리로 쓰면 이 후보를 과대평가한다.", o7$bet_cap, o8$tdc[1], o7$cr[regime=="COVID_2020",beta], o7$cr[regime=="COVID_2020",avg_pairwise_corr], 0.1413)
cf[[length(cf)+1]] <- sprintf("[★회전-용량 결합 위험] 편도 회전 %.0f%%/yr · 손익분기 편도 %.1fbps(현행 15bps 의 %.2f배) · 참여율10%% AUM 상한 중앙 %.0f억 KRW. 비용과 용량이 같은 분모(회전)를 공유하므로 독립 위험이 아니다. 회전 제어는 optimizer 소관이며 본 에이전트는 비중을 제안하지 않는다 — 근거만 제공한다.", 100*o8$to_1way_ann, o8$be_exact*1e4, o8$be_exact/0.0015, median(capa$aum_cap_10pct)/1e8)
cf[[length(cf)+1]] <- "[★구간 Σ 이질성이 1차 모형위험] as_of B·D 고정 · Ω 만 구간별로 갈아끼우면 예측 TE 가 23.9%(P1) / 20.0%(P2) / 30.4%(P3) 로 갈린다. 발행 Σ 는 확장창 단일 추정이므로 P3 국면에서 위험을 과소, P2 국면에서 과대 표시한다. 구간 Ω 는 사후 라벨이라 발행 Σ 에 넣지 않았다(C1)."
cf[[length(cf)+1]] <- "[상류 handoff 수치 불일치 · 정보성] handoff_to_risk.known_weaknesses 는 '편도 768%/yr · beta 0.766' 을 싣고 있으나 같은 패키지의 diagnostics 는 turnover_proxy 15.2326(=편도 761.6%/yr) · beta 0.73724 다. alpha 자신의 challenge_flags[11] 이 762%/yr 로 정정했으므로 handoff 블록이 정정 전 값을 남긴 것으로 보인다. 본 패키지는 diagnostics·원장(period_returns_production.csv) 값을 썼다. alpha 산출물은 수정하지 않았다(Charter 8)."
cf[[length(cf)+1]] <- sprintf("[cap-tier 정의 갈림 · silent override 방지] 본 패키지 tier = 월별 유니버스 Size 3분위(SMALL/MID/MEGA), alpha 의 diag_cap_tier = rank 기반(MEGA=top10 / MID=11-30 / OTHER). 그래서 MEGA 비중이 %.3f(본) vs 0.838(alpha) 로 다르다 — 값 충돌이 아니라 정의 차이다. 두 정의를 모두 기재한다.", tf[tier=="MEGA",w_share])
cf[[length(cf)+1]] <- sprintf("[crowding 하위성분 퇴화 · 진단 한계] crowding_score 는 %.3f~%.3f 로 전부 0.75 미만이고 3M delta 최대 %+.3f(<0.15) 라 flag 0 이다. 단 vol_concentration 성분이 5개 팩터 전부 0.000 으로 바닥에 붙었다 — 함수의 중립 기준선이 n_universe=3925(RAWDATA 전 종목)로 잡혀 K200∪KQ150(347종) 대비 희석되기 때문이다. passive_overlap 도 1.000 포화다(mandate 유니버스가 곧 벤치 구성원). 즉 본 점수는 HHI·elasticity 두 축만 실질 변별한다. 낮은 점수를 '군집 없음'의 강한 증거로 읽지 말 것.", min(cw$crowding_score), max(cw$crowding_score), cw$delta_3m[which.max(abs(cw$delta_3m))])
if(length(fc_warn)>0) cf[[length(cf)+1]] <- sprintf("[RF-R5] 요인 상관 |rho|>0.8 pair %d건: %s", length(fc_warn), paste(fc_warn, collapse=" / "))
cf[[length(cf)+1]] <- "[★자기적대검증 결과 1 — 특이위험 바닥은 사후 선택이다] p10 바닥은 조건수 556.8 을 보고 나서 골랐다. 정책 통과 최소치는 p05(431.97)이므로 나는 필요보다 강하게 눌렀다. 보고 수치(book vol 23.64→23.67% · TE 25.88→25.91% · beta 0.4409→0.4411)는 상대 0.15% 이내로만 움직이지만 그것을 면죄부로 쓰지 않는다 — 실제 부작용은 347종 중 35종의 특이위험이 인위적으로 올라가 최소분산·위험예산형 목적함수가 그 종목들을 덜 선호하게 된다는 것이다. 민감도 전량을 diagnostics.specific_risk_floor_sensitivity 에 실었다."
cf[[length(cf)+1]] <- "[★자기적대검증 결과 2 — '신호를 위험으로 볼 것인가'가 수치를 바꾼다] SIGNAL 을 요인에서 빼고 재구성하면 예측 총변동성 23.67→25.45%, TE 25.91→23.26%, 예측 beta 0.441→0.555 로 갈린다. corr(MKT,SIGNAL)이 -0.219~-0.534 로 음(-)이라 신호 노출(+1.72 sigma)이 시장위험을 상쇄하기 때문이다. 발행 Σ 는 포함판이며 alpha_vector 는 손대지 않았다. optimizer 는 TE 예산 2.65%p 가 이 정의 선택에 걸려 있다는 것을 알고 소비할 것."
cf[[length(cf)+1]] <- "[★자기적대검증 결과 3 — 발행 Σ 는 지금 국면을 과소 표시한다] 라벨 없는 rolling 36개월 창으로 재면 book 변동성 최댓값이 표본 안에서 바로 지금이다(2026-08 = 26.9% · 2026-07 = 26.7%, 표본 최소 15.0%). 확장창 단일 Σ(전 구간 평균)는 정의상 이 최댓값보다 낮다. 구간 Ω 는 사후 라벨이라 발행 Σ 에 넣지 않았지만(C1), 그 결과 현재 국면 위험이 과소 표시된다는 사실은 결손으로 남는다 — PIT-청정 국면 분류기 없이는 메울 수 없다."

## ============ risk_package.json ============
pkg <- list(
  task_id=WT, strategy_id="WT-R20260829_007_GH2004_52w_high_proximity_top25",
  agent="risk-research", as_of_date=as.character(asof), spec_version="risk_v1.2",
  upstream=list(alpha_package="qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json",
    alpha_spec_consumed="strict_pit_t_minus_1 (period_returns_production.csv). same-close A/B 판은 대조용으로만 읽었고 소비하지 않았다.",
    alpha_vector_modified=FALSE, weights_proposed=FALSE, grade_declared=FALSE, overlay_applied=FALSE),
  pit=list(sig_date=as.character(asof), decision_ts=as.character(asof),
    checks=list(
      C1="Ω·D 는 walk-forward 에서 f_1..f_{j-1} / u_1..u_{j-1} 만 사용(결정시점 t 에 알려진 것). full-sample 통계는 발행 Σ 의 as_of 추정에만 쓰이며 이는 확장창의 종점이다. 구간별 Ω 는 사후 라벨로 분리 기재하고 Σ 에 넣지 않았다.",
      C2="같은 달 요인수익 f_j 는 홀딩월 j 에 실현되므로 결정시점 t(신호월말 j)에서 배제. same-day circular 없음.",
      C5="오버레이 미적용(S0/S1). 노출 B 는 신호월말 t 단면, 위험은 홀딩월 t+1 에 적용.",
      C6="유니버스는 alpha 가 발행한 PIT 시변 멤버십(alpha_scores.parquet)을 그대로 승계. ever-member 축소는 alpha 층에서 시변 적용됨.",
      C10="유동성 자 = build_adv20_t1 (t-1 ADV20). alpha 의 fwd$liq_dt 승계, 재계산 없음.",
      C11="시간축은 RAWDATA Date 단일축. 외부 시차 데이터(FRED 등) 미사용.",
      C13="부호 반전 없음. 노출은 z-score 정렬만(winsor +-3).",
      C15="Factor DB parquet 직접 load 0건. 본 패키지의 모든 특성은 RAWDATA(load_rawdata)와 alpha 발행 panel.rds 에서 산출했다 — load_month_factors 경유 대상(Factor DB)을 소비하지 않았다.",
      detect_lookahead="risk 산출 스크립트 12개 전량 스캔(rk1~rk12). 위반 11/12 파일 0건, rk8_tail_stress.R:74 에서 C1 1건 발화 — 회전 비용격자의 사후 SR 요약(sd(rn)*sqrt(12))이며 Σ·노출·선별·비중 어디에도 입력되지 않는다. 위반 주입 없이 발화한 것은 검출기 생존의 양성 대조다(alpha 층 2건과 같은 범주). Σ 추정 경로는 전부 결정시점-절단."),
    reconstruction_check="일간 book 재구성 → 월 집계 vs period_returns_production.csv::ret_gross 최대오차 0.00000 (259/259 월 일치)"),
  model=list(structure="Sigma = B Omega B' + D (BARRA-style cross-sectional factor model)",
    n_assets=length(o4$ASSETS), n_factors=ncol(o4$B),
    factors=list(market="MKT (intercept)", sector=sprintf("%d sectors (cap-weighted sum-to-zero 제약, 월별 6종목 미만 섹터는 기타 통합)", length(o4$secs_a)),
                 style=STY, style_definition=list(
                   SIZE="log(market cap) z", MOM="6M return (jt6) z", REV="1M return z",
                   VOL="63d realized vol z", LIQ="log(Amihud 20d) z — 높을수록 비유동",
                   INDMOM="sector 6M return z", SIGNAL="52주 신고가 근접도(fh252) z — 전략 신호를 위험요인으로도 실었다(공통 노출이므로). 알파 재해석 아님")),
    estimation="월별 가중최소제곱 단면회귀(가중 sqrt(cap)), 수익 1%/99% winsor. 요인수익 259개월(2005-02~2026-08). 가중 R2 평균 0.3086.",
    omega="Ledoit-Wolf 선형 shrinkage (rho=%s), 확장창 259개월",
    specific_risk="rolling 60개월 잔차분산 → 섹터 중앙값으로 Bayes shrink(k=24) → p10 바닥(연율 %s%%)",
    window=list(train="2005-02 ~ 2026-08 (259 months)", asof_exposure=as.character(asof))))
pkg$model$omega <- sprintf("Ledoit-Wolf 선형 shrinkage (rho=%.4f), 확장창 259개월", rho_om)
pkg$model$specific_risk <- sprintf("rolling 60개월 잔차분산 → 섹터 중앙값으로 Bayes shrink(k=24) → p10 바닥(연율 %.1f%%)", 100*sqrt(o6$fl*12))

pkg$exposure_matrix_ref   <- "stage_artifacts/WT_R20260829_007/exposure_matrix.parquet"
pkg$factor_covariance_ref <- "stage_artifacts/WT_R20260829_007/factor_covariance.parquet"
pkg$specific_risk_ref     <- "stage_artifacts/WT_R20260829_007/specific_risk.parquet"
pkg$security_covariance_ref <- "stage_artifacts/WT_R20260829_007/covariance.parquet"
pkg$tail_risk_ref         <- "stage_artifacts/WT_R20260829_007/tail_risk.json"
pkg$regime_correlation_ref <- "stage_artifacts/WT_R20260829_007/regime_correlation.parquet"
pkg$walkforward_validation_ref <- "stage_artifacts/WT_R20260829_007/rk_walkforward_sigma.csv"
pkg$book_daily_ref        <- "stage_artifacts/WT_R20260829_007/rk_book_daily.csv"

pkg$risk_summary <- list(
  reference_book=list(note="진단 전용 참조 book = 전략 자체 규칙(alpha_hat 상위 25 · EW). ★비중 제안이 아니다 — 최종 weight 는 optimizer 소관이며 본 패키지는 어떤 비중도 권고하지 않는다.",
    n_names=25L, predicted_vol_ann=r3(o6$sig_ann,5),
    factor_variance_share=r3(o6$fac_var/o6$sig2,4), specific_variance_share=r3(o6$spec_var/o6$sig2,4),
    predicted_beta_vs_capw=r3(o7$bet_cap,4), predicted_beta_vs_ew_uni=r3(o7$bet_ew,4),
    realized_beta_alpha_reported=0.73724227,
    te_vs_capw_ann=r3(sqrt(o7$av2*12),5), te_vs_ew_uni_ann=r3(sqrt(o7$av2e*12),5)),
  top_common_risks=mkstr(cs_tot[1:5]),
  top_common_risks_total_basis=lapply(names(cs_tot), function(k) list(source=k, variance_share=r3(unname(cs_tot[k]),5))),
  top_common_risks_active_basis_vs_capw=lapply(names(cs_act), function(k) list(source=k, variance_share=r3(unname(cs_act[k]),5))),
  top_common_risks_active_basis_vs_ewuni=lapply(names(sort(o7$cs_ae,decreasing=TRUE)), function(k) list(source=k, variance_share=r3(unname(o7$cs_ae[k]),5))),
  crowding_flags=crowding_flags,
  crowding_score_per_factor=crowding_list,
  liquidity_flags=liq_flags,
  concentration=list(n_effective_names=r3(o6$neff,3), hhi_names=r3(o6$hhi_name,5),
    sector_hhi=r3(o6$hhi_sec,5), n_effective_sectors=r3(o6$neff_sec,3),
    largest_sector=list(sector=o6$sec_w$sec[1], weight=r3(o6$sec_w$sw[1],4)),
    sector_weights=lapply(seq_len(nrow(o6$sec_w)), function(i) list(sector=o6$sec_w$sec[i], weight=r3(o6$sec_w$sw[i],4))),
    per_factor_variance_share=as.list(r3(o6$sty_share/100,5))),
  cap_tier_decomposition=cap_tier,
  stress_tests=stress_tests,
  stress_tests_active_basis=lapply(names(ST), function(k) list(scenario=k, active_pnl=r3(ST[[k]]["active"],5))),
  stress_adverse_2sd=lapply(seq_len(nrow(o9$adv)), function(i) as.list(lapply(o9$adv[i], function(z) if(is.numeric(z)) round(z,5) else z))),
  stress_historical_detail=lapply(crisis_detail, function(z) lapply(z, function(v) if(is.numeric(v)) round(v,5) else v)),
  stress_method="요인 shock 은 조건부 기댓값으로 전파한다: E[f | f_k = s] = Omega[,k]/Omega[k,k] * s. 단일 요인만 흔들고 나머지를 0 으로 두는 순진한 시나리오가 아니다.",
  turnover_stress=turn,
  regime_heterogeneity=regime_het,
  vol_liquidity_residual_diagnostic=vld)

pkg$diagnostics <- list(
  condition_number=r3(o6$ca["cond"],2),
  condition_number_before_shrinkage=r3(o6$cb["cond"],2),
  min_eigenvalue=r3(o6$ca["mn"],10), psd=TRUE, pd=TRUE,
  psd_check="eigen(Sigma) min = %s > 0 · 대칭화 (S+S')/2 후 검사. 347x347 전역 PD.",
  shrinkage_used=TRUE, shrinkage_method="ledoit_wolf_linear_on_Omega + bayes_shrink_D_to_sector_median + specific_risk_floor_p10",
  shrinkage_intensity_omega=r3(rho_om,5),
  specific_risk_floor_ann=r3(sqrt(o6$fl*12),5),
  specific_vol_ann=list(median=r3(median(sqrt(o6$Dv*12)),4), min=r3(min(sqrt(o6$Dv*12)),4), max=r3(max(sqrt(o6$Dv*12)),4)),
  cross_sectional_r2_weighted_mean=0.3086,
  methods_tried=methods_tried,
  method_shopping_count=5L,
  walkforward_bias_test=list(
    design="199개월(2010-02~2026-08) walk-forward. 매월 결정시점까지의 정보로만 Σ 추정 → 보유 25종 EW book 의 예측 월변동성 → 실현수익 표준화. bias = sd(z), 이상값 1.0.",
    results=lapply(names(wfb), function(k) list(method=k, bias=r3(wfb[[k]]["bias"],4), n=as.integer(wfb[[k]]["n"]))),
    verdict="선택 추정기 bias 0.858 = 위험을 14% **과대**예측(보수 방향). direct_lw_linear 2.194 는 반대 방향으로 2.2배 과소예측이라 소비 금지. ★이 실측은 FQ-057 P1c 의 'lw_nls 가 총분산 채널에서 강건 우월' 과 정합하며, 동시에 v8.3.1 posterior 의 'p<=25 소규모에서 linear LW 무해' 를 **본 book 에 한해 반증**한다(EW 25종·n=60 에서 유해)."),
  estimator_stability_split_half_relfrob=list(
    omega_sample=r3(o4$diag$st_s,4), omega_lw=r3(o4$diag$st_lw,4),
    direct_sample=r3(o4$diag$st_dir_s,4), direct_lw=r3(o4$diag$st_dir_lw,4), direct_lw_nls=r3(o4$diag$st_dir_nls,4),
    note="전반/후반 재추정의 상대 Frobenius 거리. Omega 축 ~1.00 은 구간 Σ 이질성(P1 vs P3 시장변동성 24.0% vs 25.6%, P2 14.4%)의 반영이지 코드 불안정이 아니다."),
  specific_risk_floor_sensitivity=list(
    design="바닥 분위 q 를 0/0.02/0.05/0.10/0.20/0.30 으로 바꿔 재추정. ★p10 은 조건수 정책(<500)을 통과시키려고 사후에 고른 값이다 — 그 사실을 먼저 적는다.",
    rows=list(
      list(floor_q=0.00, floor_vol_ann=0.0000, cond=556.82, book_vol_ann=0.23638, te_capw_ann=0.25883, beta_capw=0.4409, pass_500=FALSE),
      list(floor_q=0.02, floor_vol_ann=0.1852, cond=551.24, book_vol_ann=0.23638, te_capw_ann=0.25883, beta_capw=0.4409, pass_500=FALSE),
      list(floor_q=0.05, floor_vol_ann=0.2092, cond=431.97, book_vol_ann=0.23646, te_capw_ann=0.25887, beta_capw=0.4410, pass_500=TRUE),
      list(floor_q=0.10, floor_vol_ann=0.2503, cond=301.91, book_vol_ann=0.23674, te_capw_ann=0.25907, beta_capw=0.4411, pass_500=TRUE),
      list(floor_q=0.20, floor_vol_ann=0.2904, cond=224.16, book_vol_ann=0.23717, te_capw_ann=0.26215, beta_capw=0.4347, pass_500=TRUE),
      list(floor_q=0.30, floor_vol_ann=0.3180, cond=186.97, book_vol_ann=0.23771, te_capw_ann=0.26558, beta_capw=0.4278, pass_500=TRUE)),
    disclosure="정책을 통과시키는 최소 바닥은 p05(cond 431.97)이고 나는 그보다 강한 p10 을 썼다. 보고 수치(book vol · TE · beta)는 바닥 0 대비 상대 0.15% 이내로만 움직인다 — 그러나 그것을 '괜찮다'의 근거로 쓰지 않는다. 실제로 움직이는 것은 **347종 중 35종의 특이위험이 인위적으로 상향**된다는 사실이고, 최소분산·위험예산형 목적함수는 그 35종을 덜 선호하게 된다. optimizer 는 이 편향을 알고 소비해야 한다."),
  sensitivity_signal_as_risk_factor=list(
    design="전략 신호(SIGNAL = 52주 신고가 근접도)를 위험요인 목록에서 빼고 Σ 를 재구성(D 는 재추정 없이 고정 — SIGNAL 분산이 D 로 흡수되지 않는 보수적 설정).",
    with_signal=list(condition_number=301.91, book_vol_ann=0.23674, factor_share=0.8941, te_capw_ann=0.25907, beta_capw=0.4411, top_risk="MKT 72.4%"),
    without_signal=list(condition_number=295.71, book_vol_ann=0.25452, factor_share=0.9083, te_capw_ann=0.23262, beta_capw=0.5546, top_risk="MKT 73.4%"),
    verdict="★무해하지 않다. SIGNAL 을 요인으로 실으면 예측 총변동성이 1.78%p **내려가고** TE 는 2.65%p **올라가며** 예측 beta 가 0.441 vs 0.555 로 0.11 갈린다. 원인은 corr(MKT, SIGNAL) 이 구간별 -0.219~-0.534 로 음(-)이라 SIGNAL 노출(+1.72 sigma)이 시장위험을 상쇄하기 때문이다. 즉 '신호를 위험으로 볼 것인가'가 위험 수치를 바꾼다.",
    disclosure="발행 Σ 는 SIGNAL 포함판이다(book 이 실제로 +1.72 sigma 실린 공통 노출이므로). ★이는 alpha 재해석이 아니다 — alpha_vector 는 손대지 않았고 SIGNAL 요인수익은 단면회귀에서 기계적으로 나온 값이다. 다만 optimizer 가 TE 예산을 쓸 때 이 정의 선택이 2.65%p 를 좌우한다는 사실을 명시한다."),
  factor_correlation_warnings=as.list(fc_warn),
  factor_correlation_style_pairs_above_0p6=as.list(fc_style),
  tdc_summary=list(book_vs_benchmark_lower_5pct=r3(o8$tdc[1],4), book_vs_benchmark_lower_10pct=r3(o8$tdc[2],4)),
  regime_correlation_ref="stage_artifacts/WT_R20260829_007/regime_correlation.parquet",
  covariance_freshness=list(cache_used=FALSE, computed_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
    note="R6 SLA: .cache/covariance/*.parquet 미사용(전량 신규 추정). stale 위험 없음."),
  evaluation_criteria_check=list(
    sigma_psd=TRUE, condition_number_under_500=TRUE,
    factor_coverage_over_80pct=TRUE,
    factor_coverage_value=r3(o6$fac_var/o6$sig2,4),
    factor_coverage_note="book(25종 EW) 분산의 89.4%를 요인이 설명한다. 단일 종목 단면 R2(0.309)와 다른 양이다 — 분산 후 특이위험이 상쇄되기 때문.",
    stress_policy_ok=TRUE, stress_policy_note="market_down_5 = -3.97% > -8% (RF-R4 미발동)"))
pkg$diagnostics$psd_check <- sprintf("eigen(Sigma) min = %.3e > 0 · 대칭화 (S+S')/2 후 검사. 347x347 전역 PD.", o6$ca["mn"])

pkg$selection_objective <- "condition_number"
pkg$selection_objective_note <- "R4 P3 준수 — 추정기 선택은 조건수/PD/walk-forward bias(=추정품질)만으로 했다. alpha 수익·SR·IR 은 선택에 입력되지 않았다."
pkg$challenge_flags <- cf
pkg$handoff_to_optimizer <- list(
  chain_completion_mandate="음성 판정이 체인을 멈추지 않는다. 본 패키지는 optimizer -> forge 로 넘어가 essence 등급을 받는다.",
  sigma_ready=TRUE, sigma_domain=sprintf("%d x %d (alpha_vector 전량)", length(o4$ASSETS), length(o4$ASSETS)),
  sigma_pd=TRUE, sigma_condition_number=r3(o6$ca["cond"],2),
  known_weaknesses_for_downstream=list(
    "회전-용량 결합: 손익분기 편도 40.5bps(현행 15bps 의 2.70배) · 참여율10% AUM 상한 중앙 31억 KRW. turnover penalty 를 넣을 근거는 이 두 수치이며, 비용과 용량이 같은 분모를 공유하므로 하나의 제어변수로 다뤄야 한다.",
    "저-beta 오독 금지: Σ-예측 beta vs cap-w 0.441 · 무조건부 0.737 인데 하방 5% tail dependence 0.545 · COVID 국면 beta 0.946. beta 를 위험 대리로 쓰면 과대평가한다.",
    "구간 Σ 이질성: 예측 TE 가 P1 23.9% / P2 20.0% / P3 30.4%. 발행 Σ 는 확장창 단일 추정이라 P3 국면 위험을 과소 표시한다.",
    "잔차 D 의 vol 잔존: 보유 25종 특이변동성과 VOL 노출 상관 +0.768. D 를 독립 잡음으로 가정하면 변동성 집중을 못 본다.",
    "특이위험 바닥 p10(연율 25.0%)은 조건수 정책(<500)을 맞추기 위한 정규화다. 저변동 종목의 특이위험이 인위적으로 올라가 있으므로 최소분산형 목적함수는 그 종목들을 덜 선호하게 된다 — 알고 쓸 것.",
    "본 패키지는 어떤 비중도 제안하지 않았다. reference_book(top-25 EW)은 진단 좌표계일 뿐이다."),
  rf_r_bounds_advisory="RF-R1 등 exposure bound 는 optimizer scope 로 위임한다(본 에이전트는 측정·권고만).")
pkg$research_philosophy_compliance <- list(
  P5_risk_model="Sigma = B Omega B' + D + crowding_score_per_factor(5 factors) + sector HHI 0.0912 / n_effective 25.0 / per-factor variance share 전량 기재",
  P6_implementation_discipline="TO 15.23/yr 는 계약 상한 11.0/yr 를 초과한다 — 측정 사실로 기재하며 제어는 optimizer 소관",
  P3_uncertainty="점추정 대신 walk-forward bias 분포 · split-half 안정성 · EVT 꼬리로 불확실성 병기")

write_json(pkg, file.path(WTD,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
cat("[RK10] risk_package.json written\n")

## lineage (write 이후 — L-194 순서 규약)
source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(task_id=WT, package_type="risk_package",
  method_selected="structural_BOB_D_lw_omega_bayes_D",
  input_file_paths=c("qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json",
                     "stage_artifacts/WT_R20260829_007/alpha_scores.parquet",
                     "stage_artifacts/WT_R20260829_007/period_returns_production.csv",
                     "stage_artifacts/WT_R20260829_007/panel.rds"),
  windows=list(list(name="factor_return_train", start="2005-02-01", end="2026-08-28", n_months=259L),
               list(name="walkforward_validation", start="2010-02-01", end="2026-08-28", n_months=199L)),
  extra=list(condition_number=as.numeric(o6$ca["cond"]), shrinkage="ledoit_wolf_omega+bayes_D+floor_p10",
             n_assets=length(o4$ASSETS), n_factors=ncol(o4$B)))
cat("[RK10] lineage recorded\n")

## challenge review (R3 / P4)
if(!nzchar(Sys.getenv("RK_SKIP_REVIEW"))){
source(file.path(ROOT,"02_Infrastructure/worktask/worktask_manager.R"))
wt_record_challenge_review(task_id=WT, from_agent="risk", objection=TRUE,
  reason="VOL_INDEPENDENCE_UNPROVEN 을 risk 층에서 측정된 얽힘으로 격상(LIQ t 9.30 / VOL t 4.84) + handoff 수치 불일치(편도 768 vs 762%/yr, beta 0.766 vs 0.737) 기록. alpha 산출물은 수정하지 않았다.",
  targets_reviewed=c("alpha_package","alpha_vector","confidence_vector","factor_specs","handoff_to_risk","challenge_note.md"))
}
cat("[RK10] done\n")
