# 409 AlphaSearch Deep Research Review

- Source: `/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409`
- Review artifact dir: `/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_codegen_direct_409/deep_research_review`
- Backtested artifact rows: 388
- Unique metric signatures: 166
- Correlation clusters: 0.95=70 / 0.90=43 / 0.80=9
- Standalone candidate clusters: 1 (raw strategies=8)
- Non-core FR-sleeve candidate clusters: 2 (core-cluster variants excluded)

## Executive Conclusion

The search did not discover dozens of independent production-grade alphas. It discovered one strong standalone alpha family, a few conditional sleeve candidates, and many redundant aliases or noisy variants.

The strongest family is a Korean equity quality/momentum/defense/value composite: low idiosyncratic volatility and beta, industry momentum, 12-1/trended momentum, profitability/quality, CFOA/earnings-stability, Piotroski, and sometimes value or accrual. Many strategy names converge to this same return stream.

## Data Integrity

- All 409 runner rows finished with exit code 0 after retry.
- 388 rows have AlphaSearch return-series artifacts.
- 21 rows are no-alpha-artifact/data-blocked/placeholder cases and should not be interpreted as failed post-2008 return histories.
- Post-2008 return-series gap flags: 0.

## Compression Of The Research Space

- 388 backtested rows compress to 166 exact metric signatures.
- 388 rows compress to 70 clusters at daily-return correlation >= 0.95.
- At correlation >= 0.90 only 43 clusters remain.
- At correlation >= 0.80 only 9 broad risk/alpha families remain.

Interpretation: strategy-name proliferation is large. The architecture should treat correlation clusters, not raw strategy count, as the research inventory unit.

## Top Correlation Clusters

| corr_cluster_95 | N | best_item | best_grade | best_utility | max_cagr | max_ir | med_mdd | min_severe45 | standalone_any | fr_sleeve_any |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 12.0 | 15.0 | RC_16_disp_vol_dual | A | 0.8 | 17.3 | 0.4 | 48.4 | 1.0 | TRUE | TRUE |
| 28.0 | 24.0 | EN_61_paradigm_rot | C | 0.5 | 16.5 | 0.4 | 62.1 | 3.0 | FALSE | TRUE |
| 31.0 | 11.0 | MF_GG1_EXP_DECAY | C | 0.5 | 14.5 | 0.3 | 49.2 | 0.0 | FALSE | TRUE |
| 48.0 | 1.0 | MF_GGGG1_FACTOR_TREND | B | 0.4 | 17.4 | 0.4 | 55.6 | 10.0 | FALSE | FALSE |
| 17.0 | 16.0 | FM_15_factor_rev_3m | F | 0.3 | 14.6 | 0.3 | 61.4 | 3.0 | FALSE | FALSE |
| 6.0 | 37.0 | MF_L1_BARBELL | C | 0.3 | 12.9 | 0.2 | 51.1 | 1.0 | FALSE | FALSE |
| 40.0 | 33.0 | FM_20_cond_fm_vol | C | 0.3 | 13.2 | 0.2 | 54.6 | 0.0 | FALSE | FALSE |
| 23.0 | 11.0 | ML_12_svm | C | 0.2 | 12.2 | 0.1 | 46.6 | 0.0 | FALSE | FALSE |
| 1.0 | 8.0 | EVO_1036_6TH_FRICTION | B | 0.2 | 12.5 | 0.1 | 56.0 | 1.0 | FALSE | FALSE |
| 68.0 | 1.0 | ML_14_moe | B | 0.2 | 12.7 | 0.1 | 59.7 | 3.0 | FALSE | FALSE |
| 19.0 | 20.0 | ALPHA_01 | F | 0.2 | 11.8 | 0.1 | 47.8 | 1.0 | FALSE | FALSE |
| 2.0 | 10.0 | ALPHA_18 | B | 0.2 | 12.4 | 0.1 | 57.6 | 1.0 | FALSE | FALSE |

## Standalone Alpha Candidate

Only one independent 0.95-correlation cluster passes the strict standalone filter: CAGR >= 15%, Sharpe >= 0.70, IR >= 0.30, MDD <= 50%, turnover <= 200%, severe45 <= 3.

| item_id | grade | score | cagr_pct | sharpe | ir | mdd_pct | turnover_ann_pct | severe45_count | corr_core | alpha_utility |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RC_16_disp_vol_dual | A | 45.800 | 17.240 | 0.803 | 0.438 | 48.430 | 121.600 | 1.0 | 1.000 | 0.800 |
| RC_33_disp_quintile | A | 45.800 | 17.240 | 0.803 | 0.438 | 48.430 | 121.600 | 1.0 | 1.000 | 0.800 |
| SF_05_mom_def_barbell | B | 40.800 | 17.240 | 0.803 | 0.438 | 48.430 | 121.600 | 1.0 | 1.000 | 0.800 |
| MF_EEE1_MOM_QUAL_BARBELL | B | 46.200 | 17.130 | 0.784 | 0.430 | 46.800 | 118.800 | 2.0 | 0.984 | 0.786 |
| MF_A2_FIXED_BALANCED | B | 43.900 | 17.070 | 0.796 | 0.429 | 48.430 | 121.000 | 1.0 | 0.999 | 0.782 |
| MF_H1_CONDITIONAL | B | 43.900 | 17.070 | 0.796 | 0.429 | 48.430 | 121.000 | 1.0 | 0.999 | 0.782 |
| SF_19_6f_no_mom | B | 43.900 | 17.070 | 0.796 | 0.429 | 48.430 | 121.000 | 1.0 | 0.999 | 0.782 |
| RC_18_macro_momentum | B | 40.400 | 16.250 | 0.754 | 0.373 | 48.120 | 118.800 | 1.0 | 0.994 | 0.685 |
| ALPHA_19 | B | 38.000 | 15.570 | 0.720 | 0.328 | 50.100 | 138.800 | 3.0 | 0.979 | 0.606 |
| MF_I1_MULTI_HORIZON | B | 36.800 | 15.490 | 0.716 | 0.321 | 50.100 | 139.700 | 3.0 | 0.980 | 0.595 |
| RC_49_trend_strength | B | 36.800 | 15.490 | 0.716 | 0.321 | 50.100 | 139.700 | 3.0 | 0.980 | 0.595 |
| SF_20_dvq_gate | B | 36.800 | 15.490 | 0.716 | 0.321 | 50.100 | 139.700 | 3.0 | 0.980 | 0.595 |
| ALPHA_15 | B | 46.300 | 17.290 | 0.676 | 0.405 | 56.030 | 133.200 | 9.0 | 0.953 | 0.409 |
| SF_33_mom_brk | B | 46.300 | 17.290 | 0.676 | 0.405 | 56.030 | 133.200 | 9.0 | 0.953 | 0.409 |
| SF_41_mom_mrs1225 | B | 46.300 | 17.290 | 0.676 | 0.405 | 56.030 | 133.200 | 9.0 | 0.953 | 0.409 |

Research read: RC_16/RC_33/SF_05 are not three independent discoveries. They are the same core stream. MF_EEE1 is a close quality/accrual variation with slightly lower MDD and nearly identical alpha.

## Factor Recipe Insight

The winning recipe is not a complex ML or regime model. The robust core is a simple equal-weight multi-factor composite over 30 holdings:

- Defense: D01_IdioVol, D02_Beta
- Momentum: M07_IndMom, M01_Mom_12_1, M05_Trended_Mom
- Quality/profitability: Q01_GPA, Q04_Piotroski_F, Q09_CFOA, Q07_Earnings_Stability
- Optional value/accrual: V01_BM or AC07_Operating_Accruals

The surprising part is that the best cluster does not need a heavy overlay to show strong alpha. Overlay-heavy and regime-heavy variants mostly help classification but often add drawdown or decay.

## FR/QEPM Sleeve Candidates

These are not clean standalone strategies, but they are useful for QEPM or factor-rotation experiments because they provide partially different timing/risk exposure. ALPHA_19-like rows are core-cluster variants and should not count as independent sleeves.

| item_id | title | grade | score | cagr_pct | sharpe | ir | mdd_pct | turnover_ann_pct | severe45_count | corr_core | corr_cluster_95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EN_31_ff5_alpha_w | FF5 Alpha 가중 앙상블 — 전략별 FF5 alpha t-stat 비례 가중 | C | 21.700 | 14.900 | 0.690 | 0.291 | 62.070 | 125.500 | 3.0 | 0.701 | 28.0 |
| RC_53_best_triple | Best Triple Regime — RC_50 상위 3개 시그널 다수결 | C | 19.000 | 14.340 | 0.712 | 0.261 | 49.220 | 131.100 | 3.0 | 0.947 | 31.0 |
| ALPHA_19 | Contrarian Composite — 한국시장 역방향 시그널 결합 (IC 실증 기반) | B | 38.000 | 15.570 | 0.720 | 0.328 | 50.100 | 138.800 | 3.0 | 0.979 | 12.0 |

Interpretation:

- Cluster 28 is the most useful diversifier: core correlation about 0.70, CAGR/IR strong, but MDD around 62-64%. It belongs in regime-gated sleeve tests, not direct admission.
- Cluster 31 is cleaner on MDD but more correlated to core, roughly 0.94-0.95. It is more of a stabilizer/variant than a true diversifier.
- Cluster 48, MF_GGGG1_FACTOR_TREND, is unique and strong but has 10 severe 45%+ drawdown episodes. It needs overlay/QEPM risk budget before consideration.

## Defensive Candidates

These are not alpha engines. They have low drawdown and zero severe45 episodes, but negative IR versus benchmark-like comparison. Treat them as brakes, overlays, or crisis sleeves only.

| item_id | title | grade | score | cagr_pct | sharpe | ir | mdd_pct | turnover_ann_pct | severe45_count | corr_core | corr_cluster_95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RC_19_speed_adaptive | 국면 속도 적응형 Overlay — MRS 변화 속도에 따라 DD/VT 파라미터 동적 조절 | A_DEF | 25.600 | 7.790 | 0.834 | -0.188 | 25.240 | 131.400 | 0.0 | 0.900 | 31.0 |
| ALPHA_QUALREV_OVERLAY | Quality+Reversal Composite(STR_1095) + BRK overlay → Grade A 승격 | A_DEF | 17.700 | 5.990 | 0.736 | -0.292 | 26.830 | 143.600 | 0.0 | 0.844 | 13.0 |
| ML_06_online_learning | Online Learning — 매월 1-step 업데이트로 모델 점진 학습 | A_DEF | 17.300 | 3.300 | 0.682 | -0.414 | 19.040 | 153.400 | 0.0 | 0.685 | 62.0 |
| MF_VVVV1_INV_DD_SIZE | Inverse Drawdown Sizing — 종목별 최근 DD 역수로 가중 (낙폭 적은 종목 선호) | A_DEF | 16.500 | 2.870 | 0.597 | -0.430 | 20.010 | 102.200 | 0.0 | 0.622 | 50.0 |
| BRK_06 | STR_1036 Ultimate Minimal: Sleeve VT 제거 + DD8 + MRS Binary (4중→2중) | A_DEF | 20.900 | 5.300 | 0.597 | -0.349 | 33.870 | 146.900 | 0.0 | 0.752 | 4.0 |
| RC_58_mrs_thresh_sweep | [진단] MRS Threshold Sweep — Low(10/12/15/18) × High(22/25/28/30) = 16조합 | C | 15.800 | 5.940 | 0.588 | -0.242 | 29.400 | 149.400 | 0.0 | 0.393 | 32.0 |
| BRK_04 | STR_1036 오버레이 극단 단순화: DD_med(8%) + MRS Binary ONLY | C | 15.600 | 4.410 | 0.569 | -0.320 | 21.890 | 149.600 | 0.0 | 0.378 | 10.0 |

## F-Grade Salvage Candidates

F-grade does not mean useless, but most F-grade salvage candidates fail for real reasons: structural drawdown, long underwater periods, or decay. These should be hypothesis material, not direct imports.

| item_id | title | score | cagr_pct | sharpe | ir | mdd_pct | turnover_ann_pct | severe45_count | corr_core | corr_cluster_95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EN_04_diversity_max | Diversity-Maximized Ensemble — 상관 최저 3전략 score 합산 | 44.400 | 15.900 | 0.542 | 0.266 | 64.570 | 149.400 | 8.0 | 0.893 | 25.0 |
| FM_15_factor_rev_3m | 3m Factor Reversal — 최근 3m 최악 팩터 매수 (단기 팩터 역전) | 45.100 | 14.010 | 0.564 | 0.241 | 62.070 | 221.300 | 3.0 | 0.867 | 17.0 |
| FM_19_mean_rev_speed | Factor Mean-Reversion Speed — OU 프로세스 속도로 FM vs 역FM 결정 | 45.100 | 14.010 | 0.564 | 0.241 | 62.070 | 221.300 | 3.0 | 0.867 | 17.0 |
| ARCH_02_DISP_CONDWEIGHT | 5-Sleeve Dispersion CondWeight: 분산도 기반 슬리브 배분 동적 조절 | 29.500 | 15.160 | 0.565 | 0.215 | 73.190 | 219.400 | 25.0 | 0.749 | 21.0 |
| ALPHA_01 | DART 내부자 거래 공시 기반 Contrarian Alpha (한국 고유 데이터) | 14.900 | 11.840 | 0.685 | 0.080 | 50.170 | 124.400 | 1.0 | 0.823 | 19.0 |
| MF_DD1_SEASONAL | 계절성 팩터 로테이션 — 1월 효과/실적 시즌/세금 매도 활용 | 14.700 | 11.630 | 0.672 | 0.063 | 50.170 | 125.200 | 1.0 | 0.822 | 19.0 |

## C-Grade Candidates Worth Keeping For Mode Borrowing

| item_id | title | grade | score | cagr_pct | sharpe | ir | mdd_pct | turnover_ann_pct | severe45_count | corr_core | corr_cluster_95 | alpha_utility |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EN_61_paradigm_rot | Paradigm Rotation — 전통/ML/국면 3패러다임 중 OOS 최강 1개 선택 | C | 23.500 | 15.860 | 0.676 | 0.354 | 64.300 | 113.900 | 3.0 | 0.713 | 28.0 | 0.504 |
| MF_GG1_EXP_DECAY | 지수 감쇠 시그널 — 최근 시그널에 높은 가중 (EWMA scoring) | C | 20.500 | 14.490 | 0.719 | 0.270 | 49.220 | 131.400 | 3.0 | 0.948 | 31.0 | 0.494 |
| FM_20_cond_fm_vol | 조건부 FM by Vol — 저변동 시 장기FM, 고변동 시 단기FM (FM_08 정밀화) | C | 22.300 | 13.220 | 0.673 | 0.200 | 54.580 | 153.400 | 4.0 | 0.808 | 40.0 | 0.265 |

## Score/Hurdle Caveat

Raw score is not a pure alpha-quality score. Correlations with key metrics:

| metric | corr |
| --- | --- |
| cagr_pct | 0.427 |
| sharpe | 0.074 |
| ir | 0.405 |
| mdd_pct | 0.428 |
| turnover_ann_pct | 0.289 |
| severe45_count | 0.385 |
| severe55_count | 0.384 |

Score has positive correlation with MDD and severe drawdown count. This is why high-score names such as MF_GGGG1_FACTOR_TREND or several FM/regime models are not automatically better than the A-grade core.

## Avoid / Deprioritize

High score but poor alpha utility should be deprioritized. These tend to have negative IR, high drawdown, or too many severe episodes.

| item_id | title | grade | score | cagr_pct | sharpe | ir | mdd_pct | severe45_count | corr_cluster_95 | alpha_utility |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ML_21_rfe | Recursive Feature Elimination — 자동 팩터 선택 후 XGBoost | F | 34.800 | 12.710 | 0.488 | 0.108 | 61.370 | 33.0 | 25.0 | -1.370 |
| MF_YYY1_ANTI_HERDING | Anti-Herding — 기관/외국인 과매수 종목 회피 + 소외 종목 선호 | F | 31.600 | 3.630 | 0.164 | -0.548 | 62.720 | 15.0 | 64.0 | -1.275 |
| MF_MMMM1_VALUATION_SPREAD | 팩터 밸류에이션 스프레드 — 팩터 long/short 밸류에이션 차이로 crowding 측정 | C | 38.200 | 5.460 | 0.257 | -0.439 | 56.940 | 10.0 | 3.0 | -0.858 |
| ML_18_vae | VAE 잠재 팩터 — Variational Autoencoder로 잠재 팩터 추출 후 scoring | C | 39.500 | 4.130 | 0.252 | -0.495 | 56.180 | 2.0 | 70.0 | -0.557 |
| FM_11_factor_spread | Factor Spread FM — Top-Bottom 스프레드 수익률로 FM 계산 | B | 43.000 | 6.930 | 0.330 | -0.323 | 55.740 | 5.0 | 3.0 | -0.480 |
| MF_UU1_MV_FACTOR | Mean-Variance 팩터 최적화 — 팩터 기대수익률/공분산으로 최적 가중 | B | 42.300 | 8.840 | 0.451 | -0.163 | 55.690 | 8.0 | 66.0 | -0.470 |
| FM_16_regime_fm_blend | Regime-Aware FM Blend — 정상: long-term FM + 위기: short-term FM | B | 45.100 | 10.520 | 0.460 | -0.017 | 61.050 | 7.0 | 3.0 | -0.302 |
| MF_PPPP1_FM_REVERSAL_BLEND | FM+역FM 블렌드 — 단기(3m) 역FM + 장기(12m) FM 결합 | B | 45.100 | 10.520 | 0.460 | -0.017 | 61.050 | 7.0 | 3.0 | -0.302 |
| FM_26_roll_vs_expand | [진단] Rolling vs Expanding FM — 6m rolling FM vs expanding FM 비교 | B | 38.400 | 7.230 | 0.478 | -0.261 | 53.030 | 2.0 | 58.0 | -0.291 |
| MF_LLLL1_DOWNSIDE_BETA | 하방 베타 팩터 — 시장 하락일만의 베타로 방어 종목 선별 | B | 40.800 | 7.500 | 0.447 | -0.251 | 53.450 | 3.0 | 45.0 | -0.286 |
| EN_36_harmonic | Harmonic Mean Ensemble — 조화평균으로 score 합산 (저score 패널티) | B | 39.400 | 9.570 | 0.464 | -0.090 | 57.230 | 5.0 | 3.0 | -0.262 |
| EN_40_rank_w | Rank-Weighted Ensemble — 전략 SR 순위 역수로 가중 | B | 39.400 | 9.570 | 0.464 | -0.090 | 57.230 | 5.0 | 3.0 | -0.262 |
| EN_57_ml_vote | ML Model Vote — XGB+RF+NN 3모델 종목 선정 투표 | B | 39.400 | 9.570 | 0.464 | -0.090 | 57.230 | 5.0 | 3.0 | -0.262 |
| FM_45_ml_fret_pred | ML Factor Return Prediction — 종목이 아닌 팩터 수익률 직접 예측 앙상블 | B | 39.400 | 9.570 | 0.464 | -0.090 | 57.230 | 5.0 | 3.0 | -0.262 |
| EN_10_layered | 계층 앙상블 — 1차 SF/MF 앙상블 → 2차 EV 앙상블 → 최종 | B | 44.300 | 10.890 | 0.492 | 0.012 | 57.270 | 7.0 | 3.0 | -0.216 |

## Family-Level Observations

| prefix | N | unique_sig | cluster95 | Bplus | F | med_score | med_cagr | med_ir | med_mdd | standalone | fr_sleeve |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| MF | 91.0 | 53.0 | 28.0 | 30.0 | 13.0 | 21.1 | 10.9 | 0.0 | 51.7 | 3.0 | 11.0 |
| RC | 61.0 | 32.0 | 20.0 | 13.0 | 22.0 | 19.9 | 9.3 | -0.1 | 51.1 | 3.0 | 9.0 |
| SF | 48.0 | 33.0 | 18.0 | 18.0 | 9.0 | 22.4 | 10.9 | 0.0 | 51.8 | 2.0 | 4.0 |
| EN | 63.0 | 30.0 | 15.0 | 33.0 | 6.0 | 34.8 | 10.9 | 0.0 | 57.3 | 0.0 | 7.0 |
| FM | 52.0 | 24.0 | 13.0 | 18.0 | 6.0 | 21.9 | 11.4 | 0.0 | 54.6 | 0.0 | 2.0 |
| ALPHA | 7.0 | 7.0 | 5.0 | 5.0 | 1.0 | 38.0 | 12.4 | 0.1 | 51.6 | 0.0 | 1.0 |
| REGIME | 2.0 | 2.0 | 2.0 | 0.0 | 0.0 | 19.9 | 14.1 | 0.2 | 54.9 | 0.0 | 1.0 |
| SLE | 10.0 | 5.0 | 4.0 | 8.0 | 0.0 | 32.7 | 11.2 | 0.0 | 57.4 | 0.0 | 0.0 |
| ML | 22.0 | 13.0 | 8.0 | 5.0 | 1.0 | 21.5 | 12.2 | 0.1 | 54.6 | 0.0 | 0.0 |
| STR | 6.0 | 6.0 | 6.0 | 4.0 | 1.0 | 26.4 | 9.7 | -0.1 | 56.1 | 0.0 | 0.0 |
| NCO | 4.0 | 3.0 | 3.0 | 3.0 | 1.0 | 27.4 | 8.6 | -0.2 | 54.1 | 0.0 | 0.0 |
| BRK | 6.0 | 6.0 | 5.0 | 2.0 | 2.0 | 18.2 | 5.7 | -0.3 | 41.0 | 0.0 | 0.0 |
| EVO | 8.0 | 6.0 | 4.0 | 2.0 | 1.0 | 20.1 | 9.1 | -0.1 | 52.6 | 0.0 | 0.0 |
| ARCH | 3.0 | 3.0 | 3.0 | 1.0 | 1.0 | 29.5 | 11.5 | 0.1 | 53.3 | 0.0 | 0.0 |
| PROD | 1.0 | 1.0 | 1.0 | 1.0 | 0.0 | 34.6 | 10.2 | 0.0 | 50.3 | 0.0 | 0.0 |
| BACKLOG | 2.0 | 2.0 | 2.0 | 0.0 | 0.0 | 20.4 | 9.0 | -0.1 | 48.2 | 0.0 | 0.0 |
| CONS | 1.0 | 1.0 | 1.0 | 0.0 | 1.0 | 8.8 | 0.8 | -0.5 | 21.1 | 0.0 | 0.0 |
| PIOTROSKI | 1.0 | 1.0 | 1.0 | 0.0 | 1.0 | 4.9 | 1.4 | -0.5 | 50.6 | 0.0 | 0.0 |

## Recommended Research Actions

1. Canonicalize cluster 12 as the primary alpha family. Keep RC_16_disp_vol_dual or RC_33_disp_quintile as the main representative; keep MF_EEE1 as a quality/accrual variant.
2. Add cluster-aware de-duplication to AlphaSearch output. The unit of research inventory should be a return-correlation cluster, not a strategy ID.
3. Do not promote all B-grade names. B-grade median IR is weak because many B strategies are high-score but high-tail-risk aliases.
4. Test cluster 28 only inside QEPM/Factor Rotation with explicit risk budget and regime gating. It has attractive IR but unacceptable standalone MDD.
5. Treat A_DEF/defensive candidates as overlays, not alpha. They reduce MDD but do not create excess return.
6. Re-run top cluster representatives through PIT/code review and OOS split diagnostics before Axiom promotion.
7. Build the next paper/search pool around variants that can diversify cluster 12, not more variants of the same low-beta/quality/momentum/value recipe.
