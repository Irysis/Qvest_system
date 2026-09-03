## RISK Stage 7 — risk_package.json 발행 + lineage + challenge review
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
WT<-"WT-R20260829_006"; AR<-"stage_artifacts/WT_R20260829_006"
R1<-readRDS(file.path(O,"r1_reg.rds")); R2<-readRDS(file.path(O,"r2_omega.rds"))
R3<-readRDS(file.path(O,"r3_sigma.rds")); R4<-readRDS(file.path(O,"r4_diag.rds"))
R5<-readRDS(file.path(O,"r5_tail.rds")); R6<-readRDS(file.path(O,"r6_emit.rds"))
rd <- function(x,n=4) round(as.numeric(x),n)

g <- R4$gcon; mc <- R4$mc; xp <- R4$xp; names(xp) <- R3$FACN
top3 <- sort(g[names(g)!="Specific"], decreasing=TRUE)
top_common <- c(sprintf("Market (%.1f%%)", g[["Market"]]*100),
                sprintf("Family/Style-composite (%.1f%%)", g[["Family"]]*100),
                sprintf("Sector (%.1f%%, 최대 INDUST %.1f%%)", g[["Sector"]]*100, mc[["s_INDUST"]]*100),
                sprintf("Size/Liquidity/Beta style (%.1f%%)", g[["Style"]]*100),
                sprintf("Specific (%.1f%%)", g[["Specific"]]*100))

ml <- R2$mlog
method_log <- lapply(names(ml), function(m) list(
  name=m, condition=rd(ml[[m]]$condition,1), min_eigen=rd(ml[[m]]$min_eigen,8),
  pd=isTRUE(ml[[m]]$pd), splithalf_relfro=rd(ml[[m]]$splithalf_relfro),
  oos_rolling60m_mean_loglik=rd(ml[[m]]$oos_mean_loglik,3),
  mean_rolling_condition=rd(mean(readRDS(file.path(O,"r2b_paired.rds"))$CND[,m]),1),
  selected=(m=="lw_nls")))

CMP <- R4$TO
crow <- R6$CMP
crow_rows <- lapply(seq_len(nrow(crow)), function(i) {
  r <- crow[i]
  out <- list(factor_name=r$factor_name, crowding_score=rd(r$crowding_score),
              hhi_top=rd(r$hhi_top), vol_concentration=rd(r$vol_concentration),
              passive_overlap_proxy=rd(r$passive_overlap_proxy),
              demand_elasticity_proxy=rd(r$demand_elasticity_proxy),
              delta_3m=rd(r$delta_3m))
  if (r$crowding_score>=0.75) out$alert <- "LEVEL_HIGH"
  if (!is.na(r$delta_3m) && r$delta_3m>=0.15) out$alert <- "RAPID_INCREASE"
  out })

STR <- R5$STR
stress_rows <- lapply(seq_len(nrow(STR)), function(i) { r<-STR[i]
  list(period=r$period, window=paste(r$start,"~",r$end), n_months=r$n_months,
       strat_cum=rd(r$strat), bench_cum=rd(r$bench), alpha_cum=rd(r$alpha),
       strat_mdd=rd(r$mdd), book_coverage=rd(r$book_coverage,3), reliability=r$reliability) })
SC <- R5$SC
scen <- setNames(as.list(rd(SC$book_ret)), SC$scenario)

TIER <- R4$TIER
tier_rows <- lapply(seq_len(nrow(TIER)), function(i){ r<-TIER[i]
  list(tier=r$tier, n_book=r$n_book, active_risk_share=rd(r$active_risk_share),
       alpha_share=rd(r$alpha_share),
       signal_alive=(r$alpha_share > 0.0 & r$n_book>0)) })

fam_contr <- R4$contr
fam_rows <- lapply(names(sort(fam_contr,decreasing=TRUE)), function(f)
  list(family=f, alpha_weight_theta=rd(R4$wf[[f]]), variance_share=rd(fam_contr[[f]])))

het <- R3$cmp
het_rows <- lapply(seq_len(nrow(het)), function(i){ r<-het[i]
  list(factor=r$factor, vol_ann_pre2015_pct=r$vol_pre, vol_ann_post2015_pct=r$vol_post,
       ratio=r$ratio) })

cf <- c(
 sprintf("RF-R1 [HIGH] 공통위험 1위 = Market %.1f%% > 40%% 게이트. 진단 book(top-25 EW)의 팩터 분산 기여 91.5%% 중 시장 절편이 68.8%%다. 전략의 능동위험은 신호가 아니라 시장 방향에 실려 있다.", g[["Market"]]*100),
 sprintf("RF-R2 [부분] cond(Sigma) %.1f — 500 게이트 통과, 다만 200 권고선 초과. 분해: cond(Omega)=%.1f(lw_nls 축소 후) · cond(D)=%.1f. 조건수는 추정잡음이 아니라 347종 특이변동성의 실제 분산이 만든다. 200 이하로 내리려면 특이변동성을 2.4%% 이상 왜곡(10/90 winsor)해야 한다 — 하지 않았고 사다리 전체를 기록한다.",
         R3$cond_sigma, R6$cond_om, R6$cond_D),
 "RF-R3 [미발화·계기결함] crowding_score 최대 0.4159(size) < 0.75. ★그러나 본 유니버스에서 composite 의 구조적 상한이 0.7345 라 게이트 0.75 는 원리적으로 발화 불가다 — passive_overlap_proxy 는 유니버스=벤치(K200∪KQ150)라 전 계열 1.0 로 고정이고 vol_concentration 은 13계열 중 9계열에서 정확히 0 이다. 양성 대조 없는 계기이므로 '군집 없음'이 아니라 '이 계기로는 판정 불가'로 읽어야 한다.",
 "RF-R4 [미발화] market_down_5 조건부 book 수익 -4.40% > -8% 정책선.",
 "RF-R5 [미발화] |rho|>0.8 팩터쌍 0개. 최대 0.754.",
 sprintf("WT006R-01 [HIGH] 구간 이질성이 실증됐다. 계열 상관구조 pre/post-2015 Jennrich chi2=%.1f (df 66, p=%.2g) — 동일 구조 가설 기각. 팩터 상관행렬 relFro 0.536. 횡단면 R2 0.2622->0.2110(공통성 -19.5%%), 특이변동성 32.24%%->35.86%%(+11.2%%). 알파가 타이밍하는 계열들의 변동성이 일제히 하락(regime -24.8%% · investor_flow -23.6%% · leverage -22.7%% · growth -22.5%%): **타이밍 대상 자체의 진폭이 줄었다**. 2015~ alpha -0.05%%(t -0.009)의 위험-측 대응물이다.",
         R4$jt$stat, R4$jt$p),
 sprintf("WT006R-02 [HIGH] 계열 집중. 12계열 mean|rho| %.4f -> Nyholt n_eff %.2f (상류 신고 3.25 재현) · 고유값 참여비 %.2f · PC1 이 분산의 34.7%%. 알파-가중 분산기여 HHI 0.1072(n_eff 9.3)로 가중치는 고르지만 **기저 축이 3~5개뿐**이라 12계열 분산은 명목이다. post-2015 에는 참여비가 5.28->4.65 로 더 줄었다 — 감쇠 구간에서 해상도가 더 나빠진다.",
         R4$fam_rho, 12/(1+11*R4$fam_rho), R4$fam_pr),
 sprintf("WT006R-03 [HIGH] 회전 위험. 명부 회전 월 %.1f%%(연 양방향 %.2f회, 상류 turnover_proxy 11.98 과 일치 재현). 진입종목-이탈종목의 익월 수익차 평균 %.4f/월 (t %.2f) — **교체되는 절반에서 측정 가능한 우위가 없다**. 그 교체가 만드는 분산은 연 10.59%%. 비용은 15bps 에서 연 1.80%%, 30bps 3.59%%, 45bps 5.39%% 로 선형 증가한다.",
         mean(CMP$to)*100, R5$to2, mean(CMP$gap,na.rm=TRUE),
         mean(CMP$gap,na.rm=TRUE)/(sd(CMP$gap,na.rm=TRUE)/sqrt(sum(!is.na(CMP$gap))))),
 sprintf("WT006R-04 [HIGH] 꼬리. Hill alpha %.3f < 2 — 표본 꼬리지수가 유한분산 경계 아래다. 실측 월 VaR1 %.4f / ES1 %.4f 인데 정규-Sigma 는 %.4f 로 1%% 지점을 17%% 과소평가한다(5%% 지점은 반대로 보수적). 하류는 꼬리 소비 시 t(5) 또는 GPD(xi %.4f) 값을 쓸 것. 월간 n=248·초과 25 라 EVT 는 소표본이다.",
         R5$TAIL$full$hill_alpha, R5$TAIL$full$emp_var_1, R5$TAIL$full$emp_es_1,
         -qnorm(0.01)*R5$sig_m, R5$TAIL$full$gpd_xi),
 sprintf("WT006R-05 [MEDIUM] 스트레스 신뢰도. 8구간 중 Terror_9_11 은 수익 커버리지 0(UNRELIABLE), GFC~Rate_Hike 6구간은 **현 book 종목 커버리지 52~84%%로 85%% 미만**이라 UNRELIABLE 표기. 부분상장 아티팩트를 hard-fail 로 쓰지 않되 해석에 실을 수 없다. 유일한 완전커버(Iran_War 2026-02~04)는 상류 WT006-17 벤치 무결성 의심 구간과 겹친다."),
 sprintf("WT006R-06 [MEDIUM] cap-tier 편중. 진단 book 25종 중 MEGA %d종이 능동위험의 %.1f%%·알파의 %.1f%%를 갖는다. dual-basis 괴리: TE(vs cap-w 유니버스) %.2f%% vs TE(vs EW 유니버스) %.2f%% = %.2fpp. 상류 EW-유니버스 대비 PORT_t 1.4615 와 cap-w 대비 1.044 의 격차가 위험-측에서도 같은 부호로 재현된다.",
         TIER[tier=="MEGA"]$n_book, TIER[tier=="MEGA"]$active_risk_share*100,
         TIER[tier=="MEGA"]$alpha_share*100, R4$te_capw, R4$te_ew, abs(R4$te_capw-R4$te_ew)),
 sprintf("WT006R-07 [MEDIUM · Risk->Alpha 이의] '비-모멘텀 12계열' 구성이 모멘텀 중립을 뜻하지 않는다. 진단 book 의 x_f_momentum 노출 %+0.3f sigma, 분산기여 %.2f%%. 모멘텀 계열을 알파에서 뺐어도 12계열 가중합이 모멘텀과 상관된 종목을 고르고 있다. alpha_package 수정 요구가 아니라 소비 시 인지 요구다(공식 wt_challenge 대신 review-with-objection 으로 기록 — 체인 완주 의무상 phase 되돌림 금지).",
         xp[["x_f_momentum"]], mc[["x_f_momentum"]]*100),
 sprintf("WT006R-08 [MEDIUM] 섹터 집중. book 섹터 HHI %.4f (n_eff %.2f) vs 유니버스 0.1790. INDUST 10종·IT 7종으로 2개 매크로섹터가 68%%다. 섹터가 book 분산의 %.1f%%(그중 INDUST 단독 %.1f%%)를 설명한다.",
         R4$shhi, 1/R4$shhi, g[["Sector"]]*100, mc[["s_INDUST"]]*100),
 sprintf("WT006R-09 [LOW] 추정 이력 결손: beta 이력<24개월 57종(Blume 사전값 1.0 대체) · 특이위험 이력<12개월 47종(횡단면 중앙값 혼합). Sigma 유니버스 347 전건이 as_of 유니버스∩유동성(adv20 t-1 >= 2e8)을 통과했다 — 상류 as_of 347 과 정확히 일치."),
 "WT006R-10 [LOW] 인프라: tail_risk_engine.R 은 fExtremes 미설치로 로드 불가. GPD(MLE)·Hill·Cornish-Fisher 를 본 라운드에서 자체 구현해 사용했다. 은닉하지 않고 기록한다."
)

pkg <- list(
 task_id=WT, as_of_date="2026-08-28", agent="risk-research", spec_version="risk_v1.2",
 pit=list(sig_date="2026-08-28", decision_ts=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
   estimation_window="2005-12-29 ~ 2026-07-31 (248 monthly cross-sections, expanding to sig_date)",
   c1_rule="Omega/D 는 sig_date 이전 관측만 사용하는 확장창. full-sample 미래참조 없음. 추정기 선택도 rolling-60m OOS 우도(매 시점 직전 60개월만)로 판정.",
   c15_rule="계열 z 는 load_month_factors(sig_date) 경유 · Z_Score_Aligned(C13) · PIT-strict 제외 23리프 승계",
   c10_rule="유동성 adv20 = build_adv20_t1 (당일 미포함 shift(1))",
   c6_rule="유니버스는 월별 K200|KQ150 실측 멤버십 스냅샷 — 생존편향 없음",
   c9_rule="rolling beta 는 당월 forward 수익 제외(Date < d)"),
 exposure_matrix_ref=paste0(AR,"/exposure_matrix.parquet"),
 factor_covariance_ref=paste0(AR,"/factor_covariance.parquet"),
 specific_risk_ref=paste0(AR,"/specific_risk.parquet"),
 security_covariance_ref=paste0(AR,"/covariance.parquet"),
 tail_risk_ref=paste0(AR,"/tail_risk.json"),
 regime_correlation_ref=paste0(AR,"/regime_correlation.parquet"),
 sigma_period_heterogeneity_ref=paste0(AR,"/sigma_period_heterogeneity.parquet"),
 model=list(
   form="Sigma = B * Omega * B' + D",
   n_assets=nrow(R3$U), n_factors=length(R3$FACN),
   factor_blocks=list(market="Intercept (횡단면 등가중 시장수익)",
     style=c("x_beta(Blume 60m)","x_size(log 시총)","x_liq(log adv20)"),
     family=paste0("x_f_", R1$FAMS),
     sector=paste0("s_", R1$SEC_LV), sector_reference="IT (+ 미분류 OTHER 흡수)"),
   factor_return_estimation="월별 횡단면 OLS (평균 n=284 · 평균 R2 0.2335 · 248개월)",
   omega_estimator="lw_nls (Ledoit-Wolf analytical nonlinear shrinkage, hrp_core::.get_cor_cov 등재분)",
   specific_risk_estimator="EWMA(halflife 24m) of cross-sectional residual^2, winsor 5/95, 이력<12m 은 횡단면 중앙값과 50:50 혼합",
   universe_alignment="alpha_vector 347종 전건 = as_of K200|KQ150 ∩ adv20_t1 >= 2e8. 결격 0."),
 risk_summary=list(
  top_common_risks=top_common,
  variance_decomposition_book=list(
    basis="진단용 기준 book = 전략 사양 그대로의 top-25 EW (비중 제안 아님 — optimizer 소관)",
    book_ann_vol_pct=rd(R4$book_vol,2), factor_share=rd(R4$book_fac_share),
    specific_share=rd(1-R4$book_fac_share),
    market=rd(g[["Market"]]), family=rd(g[["Family"]]), sector=rd(g[["Sector"]]),
    style=rd(g[["Style"]]), specific=rd(g[["Specific"]]),
    top_single_factors=as.list(rd(sort(mc,decreasing=TRUE)[1:8]))),
  book_factor_exposures=as.list(rd(xp[order(-abs(xp))][1:12],3)),
  family_concentration=list(
    n_declared=12L, mean_abs_rho=rd(R4$fam_rho),
    n_eff_nyholt=rd(12/(1+11*R4$fam_rho),2),
    n_eff_participation_ratio=rd(R4$fam_pr,2),
    pc1_variance_share=0.3469, cum_eigen_share_top3=0.639,
    alpha_weight_hhi=0.0907, alpha_weight_n_eff=11.02,
    variance_contribution_hhi=0.1072,
    per_family=fam_rows,
    interpretation="12계열 가중합의 실효 해상도는 3.25(Nyholt) ~ 5.42(참여비). 가중치는 고르게 퍼져 있으나(HHI 0.0907) 기저 축이 3~5개라 분산은 명목이다."),
  period_heterogeneity=list(
    split="2015-01-01", n_pre=109L, n_post=139L,
    correlation_relfro=0.536, jennrich_chi2=rd(R4$jt$stat,1), jennrich_df=66L,
    jennrich_p=signif(R4$jt$p,4),
    cross_sectional_r2=list(pre=0.2622, post=0.2110),
    specific_vol_ann_pct=list(pre=32.24, post=35.86),
    family_mean_abs_rho=list(pre=0.2767, post=0.2816),
    family_participation_ratio=list(pre=5.28, post=4.65),
    omega_condition=list(pre=178.0, post=137.4),
    factor_vol_ratio_post_over_pre=het_rows,
    verdict="공통구조 약화 + 특이위험 증가 + 알파 타이밍 대상 계열의 진폭 축소. 상류 기간절단(2015~ alpha -0.05%)의 위험-측 대응물."),
  cap_tier_decomposition=list(basis="cap_w_and_ew_uni", tiers=tier_rows,
    te_vs_capw_universe_pct=rd(R4$te_capw,2), te_vs_ew_universe_pct=rd(R4$te_ew,2),
    dual_basis_divergence_pp=rd(abs(R4$te_capw-R4$te_ew),2),
    dual_basis_divergence_flag=TRUE),
  concentration=list(book_sector_hhi=rd(R4$shhi), book_sector_n_eff=rd(1/R4$shhi,2),
    universe_sector_hhi=0.1790, n_names=25L),
  crowding_score_per_factor=crow_rows,
  crowding_flags=character(0),
  crowding_instrument_note=sprintf("crowding_score_per_factor() 를 라이브 유니버스(347종·as_of) 기준으로 호출. ★본 유니버스에서 composite 의 구조적 상한 = %.4f 이라 threshold 0.75 는 발화 불가 — passive_overlap_proxy 가 전 계열 1.0 고정(유니버스=벤치)이고 vol_concentration 이 9/13 계열에서 0. '군집 없음'이 아니라 '이 계기로는 판정 불가'.", R6$max_reach),
  liquidity_flags=character(0),
  liquidity_diagnostics=list(
    book_adv20_median_krw=6.396e10, book_adv20_min_krw=2.717e9, names_below_5e8=0L,
    days_to_trade_at_10pct_participation=list(
      aum_10bn=list(median=0.06,max=1.47,n_gt_5d=0L),
      aum_50bn=list(median=0.31,max=7.36,n_gt_5d=3L),
      aum_100bn=list(median=0.63,max=14.72,n_gt_5d=4L))),
  turnover_risk=list(monthly_name_turnover=rd(mean(CMP$to)),
    annual_two_way_turnover=rd(R5$to2,2),
    traded_leg_gap_mean_monthly=rd(mean(CMP$gap,na.rm=TRUE),5),
    traded_leg_gap_t=rd(mean(CMP$gap,na.rm=TRUE)/(sd(CMP$gap,na.rm=TRUE)/sqrt(sum(!is.na(CMP$gap)))),2),
    trade_timing_risk_ann_pct=10.59,
    cost_drag_pct=list(bps15=1.80, bps30=3.59, bps45=5.39),
    note="상류 turnover_proxy 11.9826 을 명부 재구성으로 독립 재현(11.98). 권고선 11.0/yr 초과."),
  stress_tests=c(scen, list(
    realized_windows=stress_rows,
    kr_bear=list(n_months=R5$bear$n, mean_strat=rd(R5$bear$strat),
                 mean_bench=rd(R5$bear$bench), mean_active=rd(R5$bear$active)),
    scenario_method="Omega 조건부 기댓값 E[f | f_k = shock] = Omega[,k]/Omega[k,k]*shock, book 노출 내적",
    coverage_note="GFC~Rate_Hike 6구간은 현 book 종목 커버리지 52~84% (<85%) 로 UNRELIABLE. hard-fail 아님."))),
 diagnostics=list(
  condition_number=rd(R3$cond_sigma,1),
  condition_number_omega=rd(R6$cond_om,1),
  condition_number_d=rd(R6$cond_D,1),
  min_eigenvalue=signif(R3$min_eig,4), positive_definite=TRUE,
  shrinkage_used=TRUE, shrinkage_method="ledoit_wolf_analytical_nls (Omega) + winsor 5/95 EWMA (D)",
  condition_before_shrinkage=194.7, condition_after_shrinkage=132.8,
  condition_sensitivity_ladder=R6$sens,
  factor_correlation_warnings=if(length(R6$pairs_hi)) R6$pairs_hi else "none (max |rho| 0.754)",
  factor_variance_share_trace=rd(R3$fac_share),
  specific_variance_share_trace=rd(1-R3$fac_share),
  mean_pairwise_correlation=0.1842, mean_asset_ann_vol_pct=49.18,
  regime_correlation_ref=paste0(AR,"/regime_correlation.parquet"),
  estimation_fallbacks=list(beta_history_lt_24m=57L, specific_history_lt_12m=47L),
  infra_note="tail_risk_engine.R(fExtremes) 미설치 — GPD/Hill/CF 자체 구현"),
 selection_objective="shrinkage_quality",
 method_shopping_log=list(risk_agent=list(candidates_tried=4L, cap=5L,
   selection_criterion="rolling-60m out-of-sample Gaussian log-likelihood (일차) + condition number (이차) — 수익/SR/IR 미참조",
   decision=paste0("lw_nls 선택. 페어드 DM-t(NW lag3) = +5.23 vs ledoit_wolf (dLL +2.579/월). ",
     "linear LW 가 조건수(59.6 vs 132.8)·분할반쪽 안정성(0.421 vs 0.547)에서 앞서지만, ",
     "예측우도 차가 결정적이고 두 후보 모두 cond<500 이라 예측력을 택했다. ",
     "p(24) << n(248) 이라 v8.3.1 posterior 의 linear-LW p>n 퇴화 조건은 비발동."),
   method_log=method_log, parallel_exec=FALSE, n_workers=1L)),
 challenge_flags=cf,
 challenge_review=list(from_agent="risk", to_agent="alpha", objection=TRUE,
   round=1L, mechanism="wt_record_challenge_review(objection=TRUE)",
   why_not_formal_challenge="wt_challenge 는 phase 를 alpha 로 되돌린다. 2026-08-29 도훈 체인 완주 지시에 따라 phase 되돌림 없이 이의를 원장에 기록하고 하류가 인지하도록 한다. alpha_package 는 무수정.",
   targets_reviewed=c("alpha_package","alpha_vector","confidence_vector","factor_specs","challenge_note.md","alpha_validation.json"),
   reason="WT006R-07: '비-모멘텀 12계열' 이 모멘텀 중립이 아니다(book x_f_momentum +0.469 sigma, 분산기여 1.63%). 추가로 WT006R-01(구간 이질성)·WT006R-03(교체 레그 무우위)은 alpha 의 기간절단·회전율 자기신고와 정합하나 위험-측 정량은 본 패키지가 소유한다."),
 boundary_declaration=list(
   alpha_vector_modified=FALSE, weights_proposed=FALSE, grade_declared=FALSE,
   overlay_applied=FALSE,
   note="alpha_vector 347 read-only. 진단용 기준 book(top-25 EW)은 전략 사양의 재현이며 비중 제안이 아니다. 등급 권위는 essence_score.R. S0/S1 오버레이 미적용.")
)
write_json(pkg, file.path("qepm/mailbox/worktask",WT,"risk_package.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=10, null="null")
cat("[write] risk_package.json ok\n")

source("02_Infrastructure/worktask/lineage_utils.R")
invisible(record_package_lineage(task_id=WT, package_type="risk_package",
  method_selected="lw_nls_factor_model_ewma_specific",
  input_file_paths=c(file.path("qepm/mailbox/worktask",WT,"alpha_package.json"),
                     paste0(AR,"/alpha_scores.parquet"),
                     paste0(AR,"/period_returns_production.csv")),
  windows=list(list(name="estimation", start="2005-12-29", end="2026-07-31"),
               list(name="as_of", start="2026-08-28", end="2026-08-28"))))
cat("[write] lineage ok\n")

source("02_Infrastructure/worktask/worktask_manager.R")
invisible(wt_record_challenge_review(task_id=WT, from_agent="risk", objection=TRUE,
  reason="WT006R-07 비-모멘텀 구성이 모멘텀 중립 아님(book x_f_momentum +0.469sd) + 구간 이질성/회전 레그 무우위 정량화. alpha 무수정.",
  targets_reviewed=c("alpha_package","confidence_vector","factor_specs")))
cat("[write] challenge review ok\n")
cat("[done]\n")
