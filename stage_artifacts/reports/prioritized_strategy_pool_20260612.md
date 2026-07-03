# Prioritized Strategy Pool
Generated: 2026-06-12 12:24:37 KST

## Counts
- raw_inbox_json_files: 442
- expanded_items: 446
- analysis_worthy_loose_including_low_known_weak: 434
- analysis_worthy_strict_excluding_low_known_weak: 430
- drop_non_strategy_or_coordination: 9
- done_or_consumed: 3
- downloaded_papers_not_strategy_specs: 15

## Status Counts
- KEEP: 345
- KEEP_DIAGNOSTIC: 30
- KEEP_ARCH_OVERLAY: 23
- KEEP_ML: 22
- DROP_NON_STRATEGY: 8
- KEEP_DATA_FIRST: 6
- LOW_KNOWN_WEAK: 4
- DONE_OR_CONSUMED: 3
- KEEP_RERUN: 3
- DROP_COORDINATION_ONLY: 1
- KEEP_RESCOPED: 1

## Prefix / Status Counts
- KEEP / MF: 93
- KEEP / RC: 59
- KEEP / EN: 57
- KEEP / SF: 53
- KEEP / FM: 47
- KEEP / ALPHA: 15
- KEEP / SLE: 11
- KEEP / MSG_EVO:  3
- KEEP / BACKLOG:  2
- KEEP / REGIME:  2
- KEEP / CONS:  1
- KEEP / MSG:  1
- KEEP / PIOTROSKI:  1
- KEEP_ARCH_OVERLAY / EVO:  8
- KEEP_ARCH_OVERLAY / BRK:  6
- KEEP_ARCH_OVERLAY / NCO:  4
- KEEP_ARCH_OVERLAY / ARCH:  3
- KEEP_ARCH_OVERLAY / PROD:  2
- KEEP_DATA_FIRST / ALPHA:  3
- KEEP_DATA_FIRST / MF:  1
- KEEP_DATA_FIRST / RC:  1
- KEEP_DATA_FIRST / SF:  1
- KEEP_DIAGNOSTIC / EN:  8
- KEEP_DIAGNOSTIC / RC:  7
- KEEP_DIAGNOSTIC / SF:  7
- KEEP_DIAGNOSTIC / FM:  5
- KEEP_DIAGNOSTIC / MF:  3
- KEEP_ML / ML: 22
- KEEP_RERUN / MSG_RERUN:  3
- KEEP_RESCOPED / ALPHA:  1
- LOW_KNOWN_WEAK / ALPHA:  4

## Full Prioritized List
| # | Status | ID | Priority | Bucket | Prefix | Title | File | Reason |
|---:|---|---|---:|---|---|---|---|---|
| 1 | KEEP | EN_53_prod_decision | 1.00 | production | EN | Production Final Decision — EV_70 vs EN_50 vs STR_1060 최종 3파전 | EN_53_production_final_decision.json |  |
| 2 | KEEP | EN_50_final_prod_ens | 0.98 | production | EN | Final Production Ensemble — EV_60 단독 vs 앙상블 비교 후 최종 확정 | EN_50_final_production_ensemble.json |  |
| 3 | KEEP | EN_30_prod_shortlist | 0.95 | production | EN | Production Shortlist — 전체 결과에서 MDD<25% + OOS>0.6 + SR>1.2 필터 | EN_30_production_shortlist.json |  |
| 4 | KEEP | ALPHA_08 | 0.95 | exploit | ALPHA | 투자자 유형별 매매흐름 시그널 — 한국시장 실증 t=16.35 (외국인) / t=9.65 (기관) | ALPHA_08_order_flow_investor_type.json |  |
| 5 | KEEP | ALPHA_04 | 0.92 | explore | ALPHA | Trended Momentum: R² 추세명확도 기반 개별종목 모멘텀 (Industry Momentum과 완전 독립) | ALPHA_04_trended_momentum.json |  |
| 6 | KEEP | EN_07_production_trio | 0.91 | production | EN | Production Trio — EV_03 + EV_05 + EV_06 score 합산 (프로덕션 앙상블) | EN_07_production_trio.json |  |
| 7 | KEEP | FM_40_best_fm_nf | 0.90 | production | FM | Best FM + Best NF — FM_39 최적 메트릭 × EV_54 최적 NF 결합 | FM_40_best_fm_with_best_nf.json |  |
| 8 | KEEP | ALPHA_QUALREV_OVERLAY | 0.90 | exploit | ALPHA | Quality+Reversal Composite(STR_1095) + BRK overlay → Grade A 승격 | ALPHA_QUALREV_overlay.json |  |
| 9 | KEEP | SLE_W1 | 0.90 | exploit | SLE | Defense-Dominant 55/30/15 | SLE_W1_def55_cons30_ind15.json |  |
| 10 | KEEP | FM_41_best_fm_regime | 0.89 | production | FM | Best FM + Best Regime — FM_39 최적 × RC_50 최적 결합 | FM_41_best_fm_with_best_regime.json |  |
| 11 | KEEP | RC_51_best_single | 0.88 | production | RC | [진단] 단일 국면 시그널 최강 확정 후 해당 시그널로 전 전략 재실행 | RC_51_best_single_regime.json |  |
| 12 | KEEP | ALPHA_20 | 0.88 | exploit | ALPHA | Residual Reversal — FF3 잔차 기반 순수 과잉반응 포착 (Reversal의 'clean' 버전) | ALPHA_20_residual_reversal.json |  |
| 13 | KEEP | MF_Q1_STRATEGY_ENSEMBLE | 0.88 | exploit | MF | Grade A 전략 앙상블 — 종목레벨 Score 합산 (30종목 규칙 준수) | MF_Q1_strategy_ensemble.json |  |
| 14 | KEEP | MF_WWWW1_META_TOP5 | 0.88 | exploit | MF | Meta Ensemble Top 5 — 102유형 중 OOS 상위 5개 전략 앙상블 | MF_WWWW1_meta_ensemble_top5.json |  |
| 15 | KEEP | SLE_5F_QUALITY_VALUE | 0.88 | exploit | SLE | SLE 5-Factor: Defense + IndMom + Consensus + QualityRev + CashFlowYield | SLE_5F_quality_value.json |  |
| 16 | KEEP | SLE_W2 | 0.88 | exploit | SLE | Defense-Heavy 60/25/15 | SLE_W2_def60_cons25_ind15.json |  |
| 17 | KEEP | ALPHA_01_FULL | 0.88 | explore | ALPHA | DART 내부자 거래 공시 기반 Net Insider Buying Alpha | ALPHA_01_insider_full_contract.json |  |
| 18 | KEEP | ALPHA_05 | 0.88 | explore | ALPHA | 하방 꼬리 공통 팩터 (Common Idiosyncratic Quantile Factor) — IdioVol과 독립적 방어 시그널 | ALPHA_05_tail_quantile_risk.json |  |
| 19 | KEEP | ALPHA_13 | 0.87 | exploit | ALPHA | Cash Flow Yield (Ocp = 영업현금흐름/시가총액) — 한국 Value 최강 시그널 (t=4.843) | ALPHA_13_cashflow_yield.json |  |
| 20 | KEEP | MF_NNNN1_SIMPLE_BEST | 0.87 | exploit | MF | 극도 단순 — Defense + Consensus 2팩터 EW + BRK overlay (최소 복잡도) | MF_NNNN1_simple_is_best.json |  |
| 21 | KEEP | SLE_CW1 | 0.87 | exploit | SLE | Regime CondWeight Binary (Crisis 70/20/10 vs Normal 40/35/25) | SLE_CW1_regime_condweight.json |  |
| 22 | KEEP | EN_01_score_blend_top | 0.86 | exploit | EN | Top 전략 Score Blend — STR_1060 + MF_A1 + MF_NNNN1 종목 score 합산 | EN_01_score_blend_top_strategies.json |  |
| 23 | KEEP | MF_H1_CONDITIONAL | 0.86 | exploit | MF | 조건부 팩터 — Dispersion 기반 Defense/Momentum 스위칭 + Quality Gate | MF_H1_conditional_factor.json |  |
| 24 | KEEP | PIOTROSKI_OVERLAY_GRADEA | 0.86 | exploit | PIOTROSKI | Piotroski F-Score(STR_1099 Grade B 50.6) + BRK overlay → Grade A 확정 | PIOTROSKI_overlay_gradeA.json |  |
| 25 | KEEP | SLE_W3 | 0.86 | exploit | SLE | Balanced Alpha 45/35/20 | SLE_W3_def45_cons35_ind20.json |  |
| 26 | KEEP | EN_03_nco_mf_ensemble | 0.85 | exploit | EN | NCO × 멀티팩터 앙상블 — NCO 가중 + FM 가중 + EW의 3-method 평균 | EN_03_nco_multifactor_ensemble.json |  |
| 27 | KEEP | MF_A2_FIXED_BALANCED | 0.85 | exploit | MF | 고정 가중 멀티팩터 — 7-Factor Equal Weight (각 ~14%) | MF_A2_fixed_weight_balanced.json |  |
| 28 | KEEP | MF_SSSS1_ALL_WEATHER | 0.85 | exploit | MF | 전천후 멀티팩터 — 모든 국면에서 양의 alpha 목표 (Bridgewater 원리) | MF_SSSS1_all_weather_factor.json |  |
| 29 | KEEP | MF_W1_CONVICTION | 0.85 | exploit | MF | Conviction Scoring — 다수 팩터 상위에 동시 등장하는 종목에 가중 | MF_W1_conviction_count.json |  |
| 30 | KEEP | STR_1049 | 0.85 | exploit | MSG_EVO | STR_1049 — STR_1036에 vol_target=0.13 overlay 추가. 현재 ann_vol 15.75%를 13%로 억제. SR 1.284→1.5 기대. | msg_006_evo_batch.json |  |
| 31 | KEEP | STR_1050 | 0.85 | exploit | MSG_EVO | STR_1050 — STR_1036 + 6th sleeve로 STR_943 EPS Change 추가. 종목레벨 스코어 블렌드 N=30 유지. | msg_006_evo_batch.json |  |
| 32 | KEEP | STR_1051 | 0.85 | exploit | MSG_EVO | STR_1051 — STR_1048 + Margin Gate. fwd_margin < 0 종목 제거 후 Top 30. | msg_006_evo_batch.json |  |
| 33 | KEEP | SF_03_def_quality_gate | 0.85 | exploit | SF | Defense + Quality Gate — IdioVol+Beta scoring + PiotroskiF<3 제거 | SF_03_defense_quality_gate.json |  |
| 34 | KEEP | SF_44_2f_eq_mrs1225_qg | 0.85 | exploit | SF | 2F EW + MRS12/25 + Quality Gate — NNNN1의 MRS+Gate 업그레이드 | SF_44_defense_consensus_equal_mrs1225_qgate.json |  |
| 35 | KEEP | SLE_CW2 | 0.85 | exploit | SLE | Dispersion CondWeight (내생 시그널 기반 비중 전환) | SLE_CW2_dispersion_condweight.json |  |
| 36 | KEEP | CONS_BRK_OVERLAY_943 | 0.85 | stabilize | CONS | Consensus 최강 STR_943(EPS Change) + BRK overlay + DD t-1 fix → Score 80+ 시도 | CONS_BRK_overlay_943.json |  |
| 37 | KEEP | ALPHA_01 | 0.85 | explore | ALPHA | DART 내부자 거래 공시 기반 Contrarian Alpha (한국 고유 데이터) | ALPHA_01_insider_dart.json |  |
| 38 | KEEP | REGIME_01 | 0.85 | explore | REGIME | Statistical Jump Model (SJM) 기반 팩터별 독립 국면 감지 → 동적 팩터 배분 | REGIME_01_sjm_factor_regime.json |  |
| 39 | KEEP | EN_05_mdd_optimized | 0.84 | exploit | EN | MDD 최적화 앙상블 — MDD < 25% 전략만 score 합산 | EN_05_mdd_optimized_ensemble.json |  |
| 40 | KEEP | EN_16_antifragile | 0.84 | exploit | EN | Anti-Fragile 포트폴리오 — 위기 시 오히려 강해지는 전략 조합 | EN_16_antifragile_portfolio.json |  |
| 41 | KEEP | EN_26_stability_filter | 0.84 | exploit | EN | Stability-Filtered Ensemble — OOS retention 0.7+ 전략만 앙상블 | EN_26_stability_filtered.json |  |
| 42 | KEEP | EN_33_ff5_filtered | 0.84 | exploit | EN | FF5 Alpha Filtered Ensemble — FF5 alpha t>2.0 전략만 앙상블 | EN_33_ff5_filtered_ensemble.json |  |
| 43 | KEEP | EN_51_best3 | 0.84 | exploit | EN | Best 3 Ensemble — EN_49 최적 가중법 + 상관 최저 3전략 | EN_51_best_3_ensemble.json |  |
| 44 | KEEP | MF_CC1_SCORE_WEIGHTED | 0.84 | exploit | MF | Score-Weighted 포트폴리오 — EW 대신 composite score 비례 가중 | MF_CC1_score_weighted.json |  |
| 45 | KEEP | MF_RRRR1_HIERARCHICAL | 0.84 | exploit | MF | 계층적 팩터 — 1차 필터(Quality Gate) → 2차 정렬(FM Composite) → 3차 가중(NCO) | MF_RRRR1_hierarchical_factor.json |  |
| 46 | KEEP | MF_WWW1_MULTI_VOTE | 0.84 | exploit | MF | 다전략 투표 — 10개 MF 전략이 선정한 종목의 출현 빈도로 scoring | MF_WWW1_multi_strategy_vote.json |  |
| 47 | KEEP | RC_52_best_dual | 0.84 | exploit | RC | Best Dual Regime — RC_50 상위 2개 시그널 AND 조합 | RC_52_best_dual_regime.json |  |
| 48 | KEEP | SF_01_composite_quality | 0.84 | exploit | SF | Composite Quality — GP+PiotroskiF+DeltaROE+(-Accruals) + BRK overlay | SF_01_composite_quality.json |  |
| 49 | KEEP | SF_15_defense_only_brk | 0.84 | exploit | SF | Defense Only + BRK — 최소 팩터(IdioVol+Beta만) + 최적 overlay | SF_15_defense_only_brk.json |  |
| 50 | KEEP | SF_17_4f_core | 0.84 | exploit | SF | 4F Core — Defense + Consensus + IndMom + Quality (핵심 4축) | SF_17_4factor_core.json |  |
| 51 | KEEP | SF_21_3f_nco_v2 | 0.84 | exploit | SF | 3F v2 + NCO — Def+Cons+TP + NCO (SF_14의 NCO 버전) | SF_21_consensus_defense_tp_3f_nco.json |  |
| 52 | KEEP | SF_22_5f_qg_mrs1225 | 0.84 | exploit | SF | 5F + Quality Gate + MRS12/25 — 게이트+overlay 최적 조합 EW | SF_22_5f_quality_gate_mrs1225.json |  |
| 53 | KEEP | ALPHA_14 | 0.83 | exploit | ALPHA | Piotroski F-Score — 9개 재무건전성 바이너리 시그널 합산 (DART에 이미 계산됨) | ALPHA_14_piotroski_fscore.json |  |
| 54 | KEEP | EN_02_regime_ensemble | 0.83 | exploit | EN | 국면별 전략 앙상블 — 국면마다 다른 전략 조합 | EN_02_regime_conditional_ensemble.json |  |
| 55 | KEEP | EN_04_diversity_max | 0.83 | exploit | EN | Diversity-Maximized Ensemble — 상관 최저 3전략 score 합산 | EN_04_diversity_maximized.json |  |
| 56 | KEEP | EN_11_progressive | 0.83 | exploit | EN | Progressive Ensemble — 단순→복잡 순서로 전략 추가, marginal SR 양수만 유지 | EN_11_progressive_ensemble.json |  |
| 57 | KEEP | EN_24_score_w_top | 0.83 | exploit | EN | Score-Weighted 전략 앙상블 — Hurdle Score 비례 가중 | EN_24_score_weighted_top_strategies.json |  |
| 58 | KEEP | EN_25_regime_weighted | 0.83 | exploit | EN | Regime-Weighted Ensemble — 현재 국면에서의 trailing SR로 전략 가중 | EN_25_regime_weighted_ensemble.json |  |
| 59 | KEEP | EN_31_ff5_alpha_w | 0.83 | exploit | EN | FF5 Alpha 가중 앙상블 — 전략별 FF5 alpha t-stat 비례 가중 | EN_31_ff5_alpha_weighted.json |  |
| 60 | KEEP | EN_32_top3_regime | 0.83 | exploit | EN | Top 3 Regime Ensemble — 각 국면에서 OOS Top 3 전략 앙상블 | EN_32_top3_regime_ensemble.json |  |
| 61 | KEEP | FM_01_conditional_ic_mom | 0.83 | exploit | FM | 조건부 IC 모멘텀 — 국면 내에서의 IC 추세로 팩터 가중 | FM_01_conditional_ic_momentum.json |  |
| 62 | KEEP | MF_A3_DEFENSE_HEAVY | 0.83 | exploit | MF | 고정 가중 멀티팩터 — Defense Heavy (40% Defense + 25% Consensus + 15% Quality + 10% IndMom + 10% Value) | MF_A3_fixed_defense_heavy.json |  |
| 63 | KEEP | MF_OO1_TIERED | 0.83 | exploit | MF | 2단계 스크리닝 — Quality Gate + Alpha Scoring (Gate→Score 분리) | MF_OO1_tiered_scoring.json |  |
| 64 | KEEP | MF_RR1_REGIME_MOM_BLEND | 0.83 | exploit | MF | 국면-모멘텀 블렌드 — MRS 연속변수 × FM 가중 곱 (부드러운 동적 배분) | MF_RR1_regime_momentum_blend.json |  |
| 65 | KEEP | MF_X1_VOL_SCALING | 0.83 | exploit | MF | 팩터 변동성 스케일링 — Barroso-style 각 팩터를 역변동성으로 정규화 | MF_X1_factor_vol_scaling.json |  |
| 66 | KEEP | RC_11_multi_signal_cons | 0.83 | exploit | RC | 다중 시그널 국면 합의 — MRS+VRP+AR+CUSUM+Vol 5축 투표 | RC_11_multi_signal_consensus.json |  |
| 67 | KEEP | RC_53_best_triple | 0.83 | exploit | RC | Best Triple Regime — RC_50 상위 3개 시그널 다수결 | RC_53_best_triple_regime.json |  |
| 68 | KEEP | SF_09_3f_def_cons_val | 0.83 | exploit | SF | 3팩터 Core — Defense + Consensus + Value (최소 다양성 확보) | SF_09_3factor_defense_cons_value.json |  |
| 69 | KEEP | SF_14_def_cons_tp | 0.83 | exploit | SF | 3F Core v2 — Defense + Consensus + TPGap (검증된 3축 독립 alpha) | SF_14_defense_consensus_tp.json |  |
| 70 | KEEP | SF_18_5f_eq_mrs1225 | 0.83 | exploit | SF | 5F EW + MRS12/25 — 5팩터 EW + STR_1071 MDD 최적 overlay | SF_18_5f_equal_mrs1225.json |  |
| 71 | KEEP | SLE_ORT | 0.83 | stabilize | SLE | Orthogonalized Multi-Factor Score (직교화 3팩터) | SLE_ORT_orthogonalized.json |  |
| 72 | KEEP | EN_10_layered | 0.82 | exploit | EN | 계층 앙상블 — 1차 SF/MF 앙상블 → 2차 EV 앙상블 → 최종 | EN_10_layered_ensemble.json |  |
| 73 | KEEP | EN_18_regime_rotating | 0.82 | exploit | EN | 국면 회전 앙상블 — 국면별 최적 전략 1개씩 자동 선택+회전 | EN_18_regime_rotating_ensemble.json |  |
| 74 | KEEP | EN_22_nf_ensemble | 0.82 | exploit | EN | 팩터 수 앙상블 — 2F/4F/7F 세 전략의 score 합산 | EN_22_factor_count_ensemble.json |  |
| 75 | KEEP | EN_23_weighted_vote | 0.82 | exploit | EN | 가중 투표 앙상블 — 전략별 SR 비례로 투표 가중치 부여 | EN_23_weighted_vote.json |  |
| 76 | KEEP | EN_46_triple | 0.82 | exploit | EN | Triple Ensemble — 3전략(NNNN1+EV_06+SF_01) score 합산 (최소 앙상블) | EN_46_triple_ensemble.json |  |
| 77 | KEEP | EN_47_quintuple | 0.82 | exploit | EN | Quintuple Ensemble — 5전략 EW (기준선, 모든 앙상블의 baseline) | EN_47_quintuple_ensemble.json |  |
| 78 | KEEP | FM_07_regime_icir | 0.82 | exploit | FM | 국면별 ICIR 가중 — 현재 국면에서의 ICIR로 팩터 가중 | FM_07_regime_conditional_icir.json |  |
| 79 | KEEP | MF_AAA1_ENSEMBLE_CONST | 0.82 | exploit | MF | 구성법 앙상블 — EW+ScoreW+NCO+RP 4가지 구성법 평균 | MF_AAA1_ensemble_construction.json |  |
| 80 | KEEP | MF_AAAA1_ROBUST | 0.82 | exploit | MF | Robust Composite — Winsorized z-score + Median Polish + Sector-Industry 이중 중립 | MF_AAAA1_robust_composite.json |  |
| 81 | KEEP | MF_EE1_MIN_CORR | 0.82 | exploit | MF | 최소 상관 포트폴리오 — 높은 score + 낮은 상관 종목 30개 선택 | MF_EE1_min_corr_portfolio.json |  |
| 82 | KEEP | MF_L1_BARBELL | 0.82 | exploit | MF | 바벨 전략 — Defense 50% + 공격형 멀티팩터 50% (극단 양극화) | MF_L1_barbell.json |  |
| 83 | KEEP | RC_07_twin_regime | 0.82 | exploit | RC | Twin Regime — MRS(외부) × DD(내부) 이중 국면으로 4-state 배분 | RC_07_twin_regime.json |  |
| 84 | KEEP | RC_29_slow_crisis | 0.82 | exploit | RC | Slow Crisis Defense — L-442 원리: 평상시 헤지 안함 + 위기 확인 후에만 강력 방어 | RC_29_slow_crisis_defense.json |  |
| 85 | KEEP | RC_54_regime_ens | 0.82 | exploit | RC | Regime Signal Ensemble — RC_50 상위 5개 시그널 z-score 합산 | RC_54_regime_signal_ensemble.json |  |
| 86 | KEEP | SF_02_cfyield_overlay | 0.82 | exploit | SF | Cash Flow Yield + BRK overlay — IC 0.045 최강 Value 시그널 실투 버전 | SF_02_cashflow_value_overlay.json |  |
| 87 | KEEP | SF_06_sue_pure_overlay | 0.82 | exploit | SF | SUE Pure + BRK Overlay — Consensus 최강 단일 시그널 + 검증 overlay | SF_06_sue_pure_overlay.json |  |
| 88 | KEEP | SF_19_6f_no_mom | 0.82 | exploit | SF | 6F No Momentum — 7F에서 Momentum 제거 (추세 노이즈 배제) | SF_19_6f_no_momentum.json |  |
| 89 | KEEP | SF_24_dcqv_4f | 0.82 | exploit | SF | 4F v2: Def+Cons+Quality+Value — IndMom 제외 4F | SF_24_defense_consensus_quality_value_4f.json |  |
| 90 | KEEP | SF_37_def_mrs1225 | 0.82 | exploit | SF | 1F Defense + MRS12/25 — Defense 단독 + MDD 최적 overlay | SF_37_defense_mrs1225.json |  |
| 91 | KEEP | SLE_4F1 | 0.82 | explore | SLE | 4th Factor: TP Upside (45/25/15/15) | SLE_4F1_tp_upside_4th.json |  |
| 92 | KEEP | EN_06_calmar_weighted | 0.81 | exploit | EN | Calmar 가중 앙상블 — Calmar ratio 비례 전략 가중 | EN_06_calmar_weighted_ensemble.json |  |
| 93 | KEEP | EN_12_inv_corr_ensemble | 0.81 | exploit | EN | 역상관 가중 전략 앙상블 — 전략 간 상관 역수로 가중 | EN_12_inverse_corr_weighted_ensemble.json |  |
| 94 | KEEP | EN_17_max_sr | 0.81 | exploit | EN | Max SR Ensemble — 전략 공분산으로 SR 극대화 전략 가중 | EN_17_max_sr_ensemble.json |  |
| 95 | KEEP | EN_20_time_weighted | 0.81 | exploit | EN | 시간 가중 앙상블 — 최근 OOS 우수 전략에 높은 가중 (EWMA 전략 가중) | EN_20_time_weighted_ensemble.json |  |
| 96 | KEEP | EN_27_minvar_ensemble | 0.81 | exploit | EN | MinVar 전략 앙상블 — 전략 공분산 최소화 가중 | EN_27_min_variance_ensemble.json |  |
| 97 | KEEP | EN_41_oos_regime | 0.81 | exploit | EN | OOS × Regime Ensemble — 국면별 OOS SR + 전체 OOS SR 가중 결합 | EN_41_oos_regime_ensemble.json |  |
| 98 | KEEP | MF_CCCC1_VOL_MANAGED_FM | 0.81 | exploit | MF | Volatility-Managed FM — FM 가중에 역변동성 스케일링 결합 | MF_CCCC1_factor_momentum_crash_vol.json |  |
| 99 | KEEP | MF_HH1_MACRO_INTERACT | 0.81 | exploit | MF | 매크로-팩터 상호작용 — MRS 레벨별 팩터 효과 크기 조절 | MF_HH1_macro_factor_interaction.json |  |
| 100 | KEEP | MF_KK1_FACTOR_PAIR | 0.81 | exploit | MF | 팩터 페어 전략 — 상관 낮은 2팩터 쌍 최적 조합 탐색 | MF_KK1_factor_pair.json |  |
| 101 | KEEP | MF_NNN1_DD_SWITCH | 0.81 | exploit | MF | Drawdown 기반 팩터 전환 — 포트폴리오 DD 심화 시 방어 모드 | MF_NNN1_drawdown_factor_switch.json |  |
| 102 | KEEP | MF_R1_FACTOR_RP | 0.81 | exploit | MF | 팩터 리스크 패리티 — 각 팩터 기여 변동성을 균등화 | MF_R1_factor_risk_parity.json |  |
| 103 | KEEP | RC_23_composite_regime | 0.81 | exploit | RC | Composite Regime Score — MRS+KMRS+Dispersion+Vol 4축 통합 국면 점수 | RC_23_composite_regime_score.json |  |
| 104 | KEEP | RC_32_dual_mrs_kmrs | 0.81 | exploit | RC | Dual Regime — MRS(글로벌) AND KMRS(한국) 동시 위기일 때만 방어 | RC_32_dual_regime_mrs_kmrs.json |  |
| 105 | KEEP | SF_05_mom_def_barbell | 0.81 | exploit | SF | Momentum-Defense 바벨 — 극방어 15종목 + 극추세 15종목 (L1 정밀화) | SF_05_momentum_defense_barbell.json |  |
| 106 | KEEP | SF_11_sue_epschg | 0.81 | exploit | SF | SUE + EPS Change 블렌드 — 2대 Consensus 시그널 결합 | SF_11_sue_eps_chg_blend.json |  |
| 107 | KEEP | SF_20_dvq_gate | 0.81 | exploit | SF | Defense + Value + Quality Gate — 방어+가치 2축 + 재무 필터 | SF_20_defense_value_quality_gate.json |  |
| 108 | KEEP | EN_08_wf_best | 0.80 | exploit | EN | Walk-Forward Best — 매년 직전 12m OOS 최강 전략 선택 | EN_08_walk_forward_best.json |  |
| 109 | KEEP | EN_13_rp_strategy | 0.80 | exploit | EN | 전략 리스크 패리티 — 전략 간 변동성 균등 배분 | EN_13_risk_parity_strategy.json |  |
| 110 | KEEP | EN_15_shrinkage_ensemble | 0.80 | exploit | EN | Shrinkage Ensemble — 전략 가중을 EW prior로 수축 | EN_15_shrinkage_ensemble.json |  |
| 111 | KEEP | EN_34_trimmed_mean | 0.80 | exploit | EN | Trimmed Mean Ensemble — 종목별 score에서 최고/최저 전략 제거 후 평균 | EN_34_trimmed_mean_ensemble.json |  |
| 112 | KEEP | EN_42_expanding_best | 0.80 | exploit | EN | Expanding Best Ensemble — 전체 기간 누적 SR로 전략 가중 (장기 안정) | EN_42_expanding_best_ensemble.json |  |
| 113 | KEEP | EN_43_erc | 0.80 | exploit | EN | Equal Risk Contribution 전략 앙상블 — 전략별 위험 기여 균등화 | EN_43_equal_risk_contribution.json |  |
| 114 | KEEP | EN_52_regime_ens_size | 0.80 | exploit | EN | 국면별 앙상블 크기 — risk_on: 5전략, crisis: 2전략 (집중) | EN_52_regime_adaptive_ensemble_size.json |  |
| 115 | KEEP | FM_04_vol_adj_fm | 0.80 | exploit | FM | Vol-Adjusted FM — 팩터별 SR(=vol-adjusted return)로 가중 | FM_04_factor_momentum_volatility_adjusted.json |  |
| 116 | KEEP | FM_16_regime_fm_blend | 0.80 | exploit | FM | Regime-Aware FM Blend — 정상: long-term FM + 위기: short-term FM | FM_16_regime_aware_fm_blend.json |  |
| 117 | KEEP | FM_34_fm_with_gate | 0.80 | exploit | FM | FM + Quality Gate — FM 가중 + PiotroskiF<3 제거 결합 | FM_34_factor_momentum_with_gate.json |  |
| 118 | KEEP | MF_DDDD1_SMART_REBAL | 0.80 | exploit | MF | Smart Rebalance — 시그널 변화+비용 분석 후 교체 여부 결정 | MF_DDDD1_smart_rebalance.json |  |
| 119 | KEEP | MF_EEE1_MOM_QUAL_BARBELL | 0.80 | exploit | MF | Momentum×Quality 바벨 — 고모멘텀+고품질 교집합 종목 선정 | MF_EEE1_momentum_quality_barbell.json |  |
| 120 | KEEP | MF_FF1_DUAL_MOMENTUM | 0.80 | exploit | MF | 듀얼 모멘텀 멀티팩터 — 절대+상대 모멘텀 동시 적용 | MF_FF1_dual_momentum.json |  |
| 121 | KEEP | MF_GGG1_RISK_ON_ONLY | 0.80 | exploit | MF | Risk-On Only — 정상 국면에서만 투자, 위기 시 100% 현금 | MF_GGG1_risk_on_only.json |  |
| 122 | KEEP | MF_HHHH1_STABILITY_WEIGHTED | 0.80 | exploit | MF | 안정성 가중 — IC 안정성(ICIR)이 높은 팩터에 가중 확대 | MF_HHHH1_factor_combination_stability.json |  |
| 123 | KEEP | MF_NN1_SECTOR_NEUTRAL_STRICT | 0.80 | exploit | MF | 엄격 섹터중립 멀티팩터 — 각 섹터 내에서 Top/Bottom 선별 | MF_NN1_long_short_neutral.json |  |
| 124 | KEEP | MF_TTTT1_ALPHA_DECOMP | 0.80 | exploit | MF | Alpha 분해 전략 — 팩터별 alpha를 국면별로 분해하여 최적 배분 | MF_TTTT1_regime_alpha_decomp.json |  |
| 125 | KEEP | MF_Z1_ABSOLUTE_FM | 0.80 | exploit | MF | 절대 팩터 모멘텀 — 팩터 trailing SR > 0일 때만 활성화 (time-series FM) | MF_Z1_absolute_fm.json |  |
| 126 | KEEP | RC_17_factor_corr_regime | 0.80 | exploit | RC | 팩터 상관 국면 — 팩터 간 상관 급등 시 분산 효과 소멸 → 집중 배분 | RC_17_factor_correlation_regime.json |  |
| 127 | KEEP | RC_21_composite_macro | 0.80 | exploit | RC | Composite 매크로 시그널 — 6개 한국 매크로 변수 통합 z-score | RC_21_composite_macro_signal.json |  |
| 128 | KEEP | RC_28_regime_x_fm | 0.80 | exploit | RC | Regime × FM 교차 — MRS 방향 × FM 방향 4-state | RC_28_regime_momentum_factor_momentum.json |  |
| 129 | KEEP | RC_38_int_ext_combined | 0.80 | exploit | RC | Internal+External 결합 국면 — MRS(외부) + DD(내부) + Dispersion(내생) 3축 가중합 | RC_38_combined_internal_external.json |  |
| 130 | KEEP | SF_10_def_indmom | 0.80 | exploit | SF | Defense + IndMom 블렌드 — 방어 + 업종추세 2축 | SF_10_defense_indmom_blend.json |  |
| 131 | KEEP | SF_23_cons_tp_overlay | 0.80 | exploit | SF | Consensus + TP Only — 애널리스트 정보 2축 + BRK overlay | SF_23_consensus_tp_blend_overlay.json |  |
| 132 | KEEP | SF_43_sue_mrs1225 | 0.80 | exploit | SF | 1F SUE + MRS12/25 — SUE 단일 + MDD 최적 overlay | SF_43_sue_only_mrs1225.json |  |
| 133 | KEEP | SLE_IVW | 0.80 | exploit | SLE | InverseVol Weighting (50/30/20) | SLE_IVW_invvol_weighting.json |  |
| 134 | KEEP | ALPHA_12 | 0.80 | explore | ALPHA | 52주 신고가 근접도 (Price-to-52wk-High) — 앵커 기반 모멘텀, IndMom과 독립 | ALPHA_12_52week_high.json |  |
| 135 | KEEP | MF_B2_FM_IC | 0.80 | explore | MF | 팩터모멘텀 IC가중 — trailing 3m IC rank로 팩터 비중 조절 | MF_B2_factor_momentum_ic.json |  |
| 136 | KEEP | MF_I1_MULTI_HORIZON | 0.80 | explore | MF | 멀티호라이즌 팩터 결합 — 단기(Rev21d) + 중기(Mom6m) + 장기(Value/Quality) | MF_I1_multi_horizon.json |  |
| 137 | KEEP | EN_09_rank_fusion | 0.79 | exploit | EN | Score-Rank Fusion — z-score 앙상블 + rank 앙상블 결합 | EN_09_score_rank_fusion.json |  |
| 138 | KEEP | EN_35_median | 0.79 | exploit | EN | Median Ensemble — 종목별 score의 중앙값 사용 (평균 대신) | EN_35_median_ensemble.json |  |
| 139 | KEEP | EN_40_rank_w | 0.79 | exploit | EN | Rank-Weighted Ensemble — 전략 SR 순위 역수로 가중 | EN_40_rank_weighted_ensemble.json |  |
| 140 | KEEP | EN_59_trio | 0.79 | exploit | EN | Regime + ML + Traditional Trio — 3 패러다임 score 합산 | EN_59_regime_ml_traditional_trio.json |  |
| 141 | KEEP | FM_02_expanding_ic | 0.79 | exploit | FM | Expanding IC 가중 — 전체 기간 누적 IC로 팩터 가중 (장기 안정) | FM_02_expanding_ic_weighted.json |  |
| 142 | KEEP | FM_05_multi_horizon_fm | 0.79 | exploit | FM | 다중 호라이즌 FM — 1m/3m/6m/12m trailing SR 앙상블 가중 | FM_05_multi_horizon_fm.json |  |
| 143 | KEEP | FM_18_shrinkage_fm | 0.79 | exploit | FM | Shrinkage FM — FM 가중을 EW prior로 수축 (II1의 FM 특화) | FM_18_shrinkage_fm.json |  |
| 144 | KEEP | FM_21_dynamic_fm_ens | 0.79 | exploit | FM | Dynamic FM Ensemble — 3m/6m/12m FM 결과를 국면별로 자동 선택 | FM_21_dynamic_fm_ensemble.json |  |
| 145 | KEEP | MF_FFF1_MAX_DIV | 0.79 | exploit | MF | Maximum Diversification 멀티팩터 — 팩터 score + 최대분산 가중 | MF_FFF1_max_diversification.json |  |
| 146 | KEEP | MF_JJ1_DYNAMIC_EXCLUDE | 0.79 | exploit | MF | 동적 팩터 제외 — 연속 3m 음의 IC 팩터 자동 비활성화 | MF_JJ1_dynamic_exclusion.json |  |
| 147 | KEEP | MF_LL1_VIX_SWITCH | 0.79 | exploit | MF | VIX 레짐 스위치 — VIX z-score 기반 단순 2-state 팩터 전환 | MF_LL1_vix_regime_switch.json |  |
| 148 | KEEP | MF_LLLL1_DOWNSIDE_BETA | 0.79 | exploit | MF | 하방 베타 팩터 — 시장 하락일만의 베타로 방어 종목 선별 | MF_LLLL1_downside_beta_factor.json |  |
| 149 | KEEP | MF_PPP1_LIQUIDITY_TIMING | 0.79 | exploit | MF | 유동성 타이밍 — 시장 유동성 상태에 따른 팩터 전환 | MF_PPP1_liquidity_timing.json |  |
| 150 | KEEP | MF_S1_FM_CRASH_PROTECT | 0.79 | exploit | MF | 팩터모멘텀 크래시 방어 — FM 급반전 감지 시 EW fallback | MF_S1_fm_crash_protection.json |  |
| 151 | KEEP | MF_UUU1_IR_MAX | 0.79 | exploit | MF | IR 극대화 — KOSPI200 추적오차 최소화하면서 alpha 추출 | MF_UUU1_information_ratio_max.json |  |
| 152 | KEEP | RC_16_disp_vol_dual | 0.79 | exploit | RC | Dispersion × Vol 이중 조건 — 분산도+변동성 동시 참조 팩터 전환 | RC_16_dispersion_vol_dual.json |  |
| 153 | KEEP | RC_19_speed_adaptive | 0.79 | exploit | RC | 국면 속도 적응형 Overlay — MRS 변화 속도에 따라 DD/VT 파라미터 동적 조절 | RC_19_regime_speed_adaptive_overlay.json |  |
| 154 | KEEP | RC_34_mkt_dd_regime | 0.79 | exploit | RC | Market DD 국면 — KOSPI200 자체 DD로 3-state (내생 위기 감지) | RC_34_market_drawdown_regime.json |  |
| 155 | KEEP | RC_40_5axis_continuous | 0.79 | exploit | RC | 5축 연속 국면 — MRS+Disp+Vol+DD+Breadth 연속 z-score 합산 | RC_40_composite_5axis_continuous.json |  |
| 156 | KEEP | RC_43_5axis_strict | 0.79 | exploit | RC | 5축 Strict Vote — 4/5 이상 위기 신호일 때만 방어 (RC_11보다 엄격) | RC_43_regime_ensemble_5axis_vote.json |  |
| 157 | KEEP | RC_47_persistence_filter | 0.79 | exploit | RC | 국면 지속성 필터 — MRS 위기 2개월 연속 확인 후에만 방어 전환 | RC_47_regime_persistence_filter.json |  |
| 158 | KEEP | SF_07_indmom_qgate | 0.79 | exploit | SF | IndMom + Quality Gate — 업종모멘텀 scoring + 재무건전성 필터 | SF_07_indmom_quality_gate.json |  |
| 159 | KEEP | SF_16_quality_value | 0.79 | exploit | SF | Quality + Value 블렌드 — GP+PiotroskiF + OCF/MCap (한국 QV) | SF_16_quality_value_blend.json |  |
| 160 | KEEP | SF_51_double_sort | 0.79 | exploit | SF | Double Sort — Defense 상위 50% 내에서 Consensus Top 30 선정 | SF_51_double_sort.json |  |
| 161 | KEEP | EN_38_winsorized | 0.78 | exploit | EN | Winsorized Mean Ensemble — 극단 score ±2σ clip 후 평균 | EN_38_winsorized_mean_ensemble.json |  |
| 162 | KEEP | EN_44_regime_avg | 0.78 | exploit | EN | 국면별 최적 평균법 — risk_on: 산술, crisis: 중앙값 (EN_39 결과 적용) | EN_44_regime_specific_averaging.json |  |
| 163 | KEEP | EN_58_trad_ml_blend | 0.78 | exploit | EN | Traditional + ML 블렌드 — MF_A1(전통) 50% + SF_47(ML) 50% score 합산 | EN_58_traditional_ml_blend.json |  |
| 164 | KEEP | EN_60_dcml_trio | 0.78 | exploit | EN | Defense + Consensus + ML Trio — 3가지 독립 alpha source 합산 | EN_60_defense_consensus_ml_trio.json |  |
| 165 | KEEP | EN_62_simple_complex | 0.78 | exploit | EN | Simple + Complex 블렌드 — NNNN1(2F EW) 50% + MF_C1(국면FM) 50% | EN_62_simple_complex_blend.json |  |
| 166 | KEEP | FM_10_regime_switch_lb | 0.78 | exploit | FM | 국면 전환 시 FM Lookback 리셋 — 새 국면 시작부터 FM 재계산 | FM_10_regime_switch_fm_lookback.json |  |
| 167 | KEEP | FM_17_rel_strength | 0.78 | exploit | FM | Relative Strength FM — 각 팩터 vs BM 초과수익으로 FM 계산 | FM_17_relative_strength_factor.json |  |
| 168 | KEEP | FM_20_cond_fm_vol | 0.78 | exploit | FM | 조건부 FM by Vol — 저변동 시 장기FM, 고변동 시 단기FM (FM_08 정밀화) | FM_20_conditional_fm_by_vol.json |  |
| 169 | KEEP | FM_23_factor_carry | 0.78 | exploit | FM | Factor Carry — 팩터의 기대 수익률(carry) = IC × Vol로 가중 | FM_23_factor_carry.json |  |
| 170 | KEEP | FM_24_expanding_sr | 0.78 | exploit | FM | Expanding SR FM — 전체 기간 누적 SR로 가중 (FM_02의 SR 버전) | FM_24_expanding_sr_weighted.json |  |
| 171 | KEEP | FM_33_ic_sr_blend | 0.78 | exploit | FM | IC+SR Blend FM — 0.50*IC가중 + 0.50*SR가중 결합 | FM_33_ic_sr_blend_fm.json |  |
| 172 | KEEP | MF_BBBB1_BETA_NEUTRAL | 0.78 | exploit | MF | Beta-Neutral 멀티팩터 — 포트폴리오 beta를 1.0으로 강제 조정 | MF_BBBB1_factor_beta_neutral.json |  |
| 173 | KEEP | MF_DDD1_REGIME_N | 0.78 | exploit | MF | 국면별 종목수 — 위기 시 N=15 집중, 정상 시 N=30 분산 | MF_DDD1_regime_specific_n.json |  |
| 174 | KEEP | MF_GGGG1_FACTOR_TREND | 0.78 | exploit | MF | 팩터 추세추종 — 팩터 수익률의 이동평균 돌파로 on/off | MF_GGGG1_factor_trend_following.json |  |
| 175 | KEEP | MF_LLL1_BREADTH_TILT | 0.78 | exploit | MF | Market Breadth 틸트 — 시장 참여도에 따른 팩터 전환 | MF_LLL1_market_breadth_tilt.json |  |
| 176 | KEEP | MF_PPPP1_FM_REVERSAL_BLEND | 0.78 | exploit | MF | FM+역FM 블렌드 — 단기(3m) 역FM + 장기(12m) FM 결합 | MF_PPPP1_factor_momentum_reversal.json |  |
| 177 | KEEP | MF_TT1_TAIL_HEDGE | 0.78 | exploit | MF | Tail Hedge 로테이션 — 위기 선행 시 Defense→Quality 전환으로 비대칭 수익 | MF_TT1_tail_hedge_rotation.json |  |
| 178 | KEEP | RC_05_kr_credit_cycle | 0.78 | exploit | RC | 한국 신용 사이클 — 회사채 스프레드 변화율로 팩터 로테이션 | RC_05_korean_credit_cycle.json |  |
| 179 | KEEP | RC_09_vol_regime_3state | 0.78 | exploit | RC | 변동성 국면 3-state — Realized Vol z-score로 Low/Mid/High 배분 | RC_09_volatility_regime_3state.json |  |
| 180 | KEEP | RC_18_macro_momentum | 0.78 | exploit | RC | 매크로 모멘텀 — MRS 변화 방향이 팩터 선택보다 중요 | RC_18_macro_momentum.json |  |
| 181 | KEEP | RC_25_mkt_state_3var | 0.78 | exploit | RC | 시장 상태 3변수 — Return+Vol+Breadth 동시 참조 팩터 배분 | RC_25_mkt_state_3var.json |  |
| 182 | KEEP | RC_35_multi_tf_regime | 0.78 | exploit | RC | Multi-Timeframe Regime — 1m/3m/12m MRS 추세 3축 동시 참조 | RC_35_multi_timeframe_regime.json |  |
| 183 | KEEP | RC_41_vix_mrs | 0.78 | exploit | RC | VIX × MRS 교차 — 글로벌 공포 × 매크로 위험 2축 | RC_41_vix_mrs_combined.json |  |
| 184 | KEEP | SF_08_tp_def_blend | 0.78 | exploit | SF | TP Gap + Defense 블렌드 — 목표가 괴리율 + 저변동 결합 | SF_08_tp_gap_defense_blend.json |  |
| 185 | KEEP | SF_28_value_only_brk | 0.78 | exploit | SF | Value Only + BRK — OCF/MCap 단일 + Quality Gate + BRK overlay | SF_28_value_only_brk.json |  |
| 186 | KEEP | SF_32_indmom_brk | 0.78 | exploit | SF | 1F IndMom + BRK Overlay — 업종모멘텀 단일 + 검증 overlay | SF_32_indmom_brk_overlay.json |  |
| 187 | KEEP | SF_38_indmom_mrs1225 | 0.78 | exploit | SF | 1F IndMom + MRS12/25 — MRS 12/25 시리즈 3번째 | SF_38_indmom_mrs1225.json |  |
| 188 | KEEP | ALPHA_06 | 0.78 | explore | ALPHA | Accruals Anomaly (이익의 질) — QMJ composite와 다른 순수 발생액 시그널 | ALPHA_06_accruals_quality.json |  |
| 189 | KEEP | MF_Y1_RANK_SCORING | 0.78 | explore | MF | Rank Scoring — z-score 대신 percentile rank 합산 (극단값 강건) | MF_Y1_rank_vs_zscore.json |  |
| 190 | KEEP | SLE_4F2 | 0.78 | explore | SLE | Margin Gate (OPM bottom 10% 제거) + Score 50/30/20 | SLE_4F2_margin_gate.json |  |
| 191 | KEEP | EN_61_paradigm_rot | 0.77 | exploit | EN | Paradigm Rotation — 전통/ML/국면 3패러다임 중 OOS 최강 1개 선택 | EN_61_paradigm_rotation.json |  |
| 192 | KEEP | EN_63_conviction | 0.77 | exploit | EN | Conviction Ensemble — 5전략 모두 Top 30%인 종목만 선정 | EN_63_conviction_ensemble.json |  |
| 193 | KEEP | FM_11_factor_spread | 0.77 | exploit | FM | Factor Spread FM — Top-Bottom 스프레드 수익률로 FM 계산 | FM_11_pure_factor_spread.json |  |
| 194 | KEEP | FM_22_ic_momentum | 0.77 | exploit | FM | IC Momentum — IC 자체의 추세(IC가 증가 중인 팩터) 가중 | FM_22_information_coefficient_momentum.json |  |
| 195 | KEEP | FM_25_ewma_ic | 0.77 | exploit | FM | EWMA IC FM — IC의 EWMA(λ=0.9)로 최근 IC에 높은 가중 | FM_25_ewma_ic_fm.json |  |
| 196 | KEEP | FM_28_regime_carry | 0.77 | exploit | FM | Regime-Conditional Factor Carry — 국면별 IC×Vol 가중 | FM_28_regime_conditional_carry.json |  |
| 197 | KEEP | FM_30_pure_ic | 0.77 | exploit | FM | Pure IC FM — trailing 12m 평균 IC(절대값)로 가중 | FM_30_pure_ic_weighted.json |  |
| 198 | KEEP | FM_31_3_6_12_eq | 0.77 | exploit | FM | 3m/6m/12m FM Equal Blend — 3개 lookback EW (FM_05의 EW 버전) | FM_31_3m_6m_12m_equal_blend.json |  |
| 199 | KEEP | FM_38_regime_fm_metric | 0.77 | exploit | FM | 국면별 최적 FM 메트릭 — risk_on: SR, crisis: ICIR 사용 | FM_38_regime_specific_fm_metric.json |  |
| 200 | KEEP | MF_SSS1_FACTOR_DISP_TIMING | 0.77 | exploit | MF | 팩터 수익률 분산도 타이밍 — 팩터 간 수익률 차이 클 때만 FM 활성화 | MF_SSS1_factor_dispersion_timing.json |  |
| 201 | KEEP | MF_VVVV1_INV_DD_SIZE | 0.77 | exploit | MF | Inverse Drawdown Sizing — 종목별 최근 DD 역수로 가중 (낙폭 적은 종목 선호) | MF_VVVV1_inverse_drawdown_sizing.json |  |
| 202 | KEEP | RC_06_yield_curve_switch | 0.77 | exploit | RC | 수익률 곡선 기반 팩터 전환 — 장단기 금리차로 경기 국면 판단 | RC_06_yield_curve_factor_switch.json |  |
| 203 | KEEP | RC_12_mom_crash_regime | 0.77 | exploit | RC | 모멘텀 크래시 국면 — 급락 후 반등 시 모멘텀 해제 + 역전 팩터 | RC_12_momentum_crash_regime.json |  |
| 204 | KEEP | RC_26_earnings_season | 0.77 | exploit | RC | 실적 시즌 국면 — DART 공시 밀도로 Consensus 팩터 가중 자동 조절 | RC_26_earnings_season_regime.json |  |
| 205 | KEEP | RC_37_n20_crisis | 0.77 | exploit | RC | N=20 Crisis — 위기 시 종목수 20으로 축소 + Defense Heavy | RC_37_n20_crisis.json |  |
| 206 | KEEP | SF_36_quality_mrs1225 | 0.77 | exploit | SF | 1F Quality + MRS12/25 — Quality 단독 + MDD 최적 overlay | SF_36_quality_brk_mrs1225.json |  |
| 207 | KEEP | SF_39_value_mrs1225 | 0.77 | exploit | SF | 1F Value + MRS12/25 | SF_39_value_mrs1225.json |  |
| 208 | KEEP | SF_50_cs_reg | 0.77 | exploit | SF | Cross-Sectional Regression 종목선정 — 월별 FMB β로 직접 E[R] 예측 | SF_50_cross_sectional_regression.json |  |
| 209 | KEEP | SF_52_triple_sort | 0.77 | exploit | SF | Triple Sort — Defense Top50% → Quality Top50% → Consensus Top30 | SF_52_triple_sort.json |  |
| 210 | KEEP | ALPHA_18 | 0.77 | explore | ALPHA | Trading Friction 배치 — Amihud Illiquidity + Short-Term Reversal + Abnormal Volume (한국 유의 확인) | ALPHA_18_illiquidity_reversal_batch.json |  |
| 211 | KEEP | MF_II1_BAYESIAN_SHRINK | 0.77 | explore | MF | 베이지안 수축 가중 — 팩터 가중을 EW prior로 수축 | MF_II1_bayesian_shrinkage.json |  |
| 212 | KEEP | MF_M1_RESIDUAL_ALPHA | 0.77 | explore | MF | 잔차 Alpha 추출 — FF5 잔차에서 팩터 프리미엄 제거 후 순수 종목 alpha | MF_M1_residual_alpha.json |  |
| 213 | KEEP | EN_57_ml_vote | 0.76 | exploit | EN | ML Model Vote — XGB+RF+NN 3모델 종목 선정 투표 | EN_57_ml_model_vote.json |  |
| 214 | KEEP | EN_64_w_conviction | 0.76 | exploit | EN | Weighted Conviction — 전략 SR 가중 conviction count | EN_64_weighted_conviction.json |  |
| 215 | KEEP | EN_65_complexity_w | 0.76 | exploit | EN | Complexity-Weighted — 단순 전략에 높은 가중 (Occam 앙상블) | EN_65_complexity_weighted.json |  |
| 216 | KEEP | MF_XXX1_REGIME_SPEED | 0.76 | exploit | MF | 국면 전환 속도 팩터 — MRS 변화율로 전환 강도 반영 | MF_XXX1_regime_transition_speed.json |  |
| 217 | KEEP | RC_08_krw_usd_tilt | 0.76 | exploit | RC | 원달러 환율 기반 팩터 틸트 — KRW 약세시 수출주 팩터 강화 | RC_08_krw_usd_factor_tilt.json |  |
| 218 | KEEP | RC_66_factor_disp | 0.76 | exploit | RC | Factor Return Dispersion Regime — 팩터 수익률 차이 클 때 FM, 작을 때 EW | RC_66_factor_dispersion_regime.json |  |
| 219 | KEEP | SF_33_mom_brk | 0.76 | exploit | SF | 1F Momentum + BRK Overlay — TrendedMom+52wk + 검증 overlay | SF_33_momentum_brk_overlay.json |  |
| 220 | KEEP | SF_34_tp_brk | 0.76 | exploit | SF | 1F TPGap + BRK Overlay — 8번째 1F+BRK (1F BRK 완전 세트) | SF_34_tp_brk_overlay.json |  |
| 221 | KEEP | SF_40_tp_mrs1225 | 0.76 | exploit | SF | 1F TPGap + MRS12/25 | SF_40_tp_mrs1225.json |  |
| 222 | KEEP | SF_55_comp_risk | 0.76 | exploit | SF | Composite Risk Score — IdioVol+Beta+DownBeta+ES+VolOfVol 5축 방어 | SF_55_composite_risk_score.json |  |
| 223 | KEEP | ALPHA_15 | 0.76 | explore | ALPHA | Fundamental Momentum (Delta_* 시그널) — 재무지표 변화율 기반 모멘텀 (DART 이미 계산) | ALPHA_15_fundamental_momentum.json |  |
| 224 | KEEP | EN_14_jackknife | 0.76 | explore | EN | Jackknife Ensemble — N개 전략 중 1개씩 제거한 (N-1) 앙상블 평균 | EN_14_jackknife_ensemble.json |  |
| 225 | KEEP | EN_21_cond_best_n | 0.76 | explore | EN | 조건부 최적 N 앙상블 — 앙상블 전략 수(3~7)를 IC로 자동 결정 | EN_21_conditional_best_n.json |  |
| 226 | KEEP | MF_AA1_WALKFWD_SELECT | 0.76 | explore | MF | Walk-Forward 팩터 선택 — 12m OOS에서 IC 유의미한 팩터만 유지 | MF_AA1_walk_forward_selection.json |  |
| 227 | KEEP | MF_JJJJ1_PENALIZED_REG | 0.76 | explore | MF | Penalized Regression 팩터 가중 — LASSO/Ridge/ElasticNet 비교 | MF_JJJJ1_penalized_regression.json |  |
| 228 | KEEP | MF_SS1_BOOSTED | 0.76 | explore | MF | Boosted Composite — 약한 팩터를 순차적으로 잔차에 적합 (AdaBoost 원리) | MF_SS1_boosted_composite.json |  |
| 229 | KEEP | RC_33_disp_quintile | 0.76 | explore | RC | Dispersion Quintile — 분산도 5분위별 최적 팩터 배분 매핑 | RC_33_dispersion_quintile.json |  |
| 230 | KEEP | SF_04_insider_cons_blend | 0.76 | explore | SF | Insider + Consensus 블렌드 — DART 내부자 + 애널리스트 결합 | SF_04_insider_consensus_blend.json |  |
| 231 | KEEP | SF_45_def_n15_mrs1225 | 0.76 | explore | SF | 1F Defense N=15 + MRS12/25 — 집중 Defense | SF_45_defense_n15_mrs1225.json |  |
| 232 | KEEP | SF_46_def_n20_mrs1225 | 0.76 | explore | SF | 1F Defense N=20 + MRS12/25 | SF_46_defense_n20_mrs1225.json |  |
| 233 | KEEP | BACKLOG_MACRO_LOWVOL_V2 | 0.75 | exploit | BACKLOG | macro_gated_lowvol 패밀리 확장 — PASS 이력, 대체 구성 탐색 | BACKLOG_macro_gated_lowvol_v2.json |  |
| 234 | KEEP | SF_41_mom_mrs1225 | 0.75 | exploit | SF | 1F Momentum + MRS12/25 | SF_41_momentum_mrs1225.json |  |
| 235 | KEEP | SF_59_piv | 0.75 | exploit | SF | Price-to-Intrinsic Value — TP/Close × OCF yield × PiotroskiF 3축 가치 | SF_59_price_to_intrinsic_value.json |  |
| 236 | KEEP | SLE_N20 | 0.75 | stabilize | SLE | Concentrated N=20 (50/30/20) | SLE_N20_concentrated.json |  |
| 237 | KEEP | EN_19_bootstrap | 0.75 | explore | EN | Bootstrap Ensemble — 5전략 랜덤 3개 선택 × 100회 → 평균 | EN_19_bootstrap_ensemble.json |  |
| 238 | KEEP | FM_08_adaptive_lookback | 0.75 | explore | FM | 적응형 FM Lookback — 변동성에 따라 FM lookback 자동 조절 | FM_08_adaptive_lookback.json |  |
| 239 | KEEP | MF_BBB1_CV_BLEND | 0.75 | explore | MF | Walk-Forward CV 블렌드 — 3개 train window 예측 평균으로 가중 결정 | MF_BBB1_cross_validation_blend.json |  |
| 240 | KEEP | MF_E2_RANDOM_FOREST | 0.75 | explore | MF | ML 기반 팩터 배분 — Random Forest 다수결 예측 | MF_E2_random_forest.json |  |
| 241 | KEEP | MF_GG1_EXP_DECAY | 0.75 | explore | MF | 지수 감쇠 시그널 — 최근 시그널에 높은 가중 (EWMA scoring) | MF_GG1_exponential_decay_signal.json |  |
| 242 | KEEP | MF_IIII1_MAX_SR_FACTOR | 0.75 | explore | MF | Max Sharpe 팩터 포트폴리오 — 7팩터 Tangency Portfolio 가중 | MF_IIII1_max_sharpe_factor.json |  |
| 243 | KEEP | MF_XXXX1_PURE_ALPHA_FM | 0.75 | explore | MF | Pure Alpha FM — FF5 잔차 alpha에 FM 적용 (이중 정제) | MF_XXXX1_pure_alpha_residual_fm.json |  |
| 244 | KEEP | RC_13_ecos_leading | 0.75 | explore | RC | ECOS 선행지수 기반 팩터 전환 — 경기선행지수 순환변동치 활용 | RC_13_ecos_leading_index.json |  |
| 245 | KEEP | RC_45_transition_prob | 0.75 | explore | RC | 국면 전환 확률 — MRS 변화율로 위기 진입 확률 추정 → 연속 배분 | RC_45_regime_transition_probability.json |  |
| 246 | KEEP | SF_47_ml_stock | 0.75 | explore | SF | ML 종목 선정 — XGBoost로 직접 종목별 다음 달 수익률 예측 | SF_47_ml_stock_selection.json |  |
| 247 | KEEP | FM_45_ml_fret_pred | 0.74 | exploit | FM | ML Factor Return Prediction — 종목이 아닌 팩터 수익률 직접 예측 앙상블 | FM_45_ml_factor_return_pred.json |  |
| 248 | KEEP | FM_48_cons_mom | 0.74 | exploit | FM | Consensus Momentum — SUE/EPS/FPER 각각의 trailing IC로 Consensus 내 가중 | FM_48_consensus_momentum.json |  |
| 249 | KEEP | SF_58_rev_breadth | 0.74 | exploit | SF | Earnings Revision Breadth — 상향 애널리스트 비율로 scoring | SF_58_earnings_revision_breadth.json |  |
| 250 | KEEP | EN_36_harmonic | 0.74 | explore | EN | Harmonic Mean Ensemble — 조화평균으로 score 합산 (저score 패널티) | EN_36_harmonic_mean_ensemble.json |  |
| 251 | KEEP | FM_03_mom_of_mom | 0.74 | explore | FM | Momentum of Momentum — FM 가속도(FM 변화율)로 팩터 가중 | FM_03_regime_momentum_of_momentum.json |  |
| 252 | KEEP | FM_09_ic_decay_fm | 0.74 | explore | FM | IC Decay-Weighted FM — 팩터별 IC half-life 반영 FM lookback 차별화 | FM_09_ic_decay_weighted_fm.json |  |
| 253 | KEEP | FM_12_momentum_duration | 0.74 | explore | FM | FM Duration — 팩터 모멘텀의 지속 기간으로 가중 조절 | FM_12_momentum_duration.json |  |
| 254 | KEEP | FM_14_half_life_fm | 0.74 | explore | FM | Half-Life FM — 팩터 수익률의 반감기로 FM 신뢰도 조절 | FM_14_half_life_weighted_fm.json |  |
| 255 | KEEP | FM_27_mom_qual_interact | 0.74 | explore | FM | Momentum×Quality Interaction FM — 두 팩터 동시 강세 시에만 FM 활성화 | FM_27_momentum_quality_interaction_fm.json |  |
| 256 | KEEP | FM_35_fm_n15 | 0.74 | explore | FM | FM + N=15 — FM 가중 + 집중 포트폴리오 (high conviction) | FM_35_factor_momentum_n15.json |  |
| 257 | KEEP | FM_36_fm_n20 | 0.74 | explore | FM | FM + N=20 — FM 가중 + 중간 집중도 포트폴리오 | FM_36_factor_momentum_n20.json |  |
| 258 | KEEP | MF_J1_ADAPTIVE_N | 0.74 | explore | MF | 적응형 종목수 — 시그널 강도에 따라 N=15~30 동적 조절 | MF_J1_adaptive_n.json |  |
| 259 | KEEP | MF_MMM1_INVERSE_CORR | 0.74 | explore | MF | 역상관 가중 — 기존 포트폴리오와 상관 낮은 팩터에 가중 확대 | MF_MMM1_inverse_factor_corr.json |  |
| 260 | KEEP | MF_QQQQ1_TAIL_RISK_BUDGET | 0.74 | explore | MF | Tail Risk Budget — CVaR 기여도 균등화 가중 (꼬리 위험 관리) | MF_QQQQ1_tail_risk_budget.json |  |
| 261 | KEEP | MF_U1_TOURNAMENT | 0.74 | explore | MF | 토너먼트 선택 — 5개 멀티팩터 전략 병렬 → 최근 1등 포트폴리오 추종 | MF_U1_tournament.json |  |
| 262 | KEEP | MF_VV1_RETURN_PRED | 0.74 | explore | MF | 수익률 예측 Composite — 각 팩터의 예측 수익률로 종목 직접 순위 | MF_VV1_return_prediction_composite.json |  |
| 263 | KEEP | MF_WW1_TARGET_VOL_PER_F | 0.74 | explore | MF | 팩터별 목표 변동성 — 각 팩터 기여 변동성을 개별 목표로 관리 | MF_WW1_target_vol_per_factor.json |  |
| 264 | KEEP | MF_ZZZ1_SENTIMENT_PROXY | 0.74 | explore | MF | 센티먼트 프록시 — 거래량 서프라이즈 + 신용거래 비율로 과열/공포 측정 | MF_ZZZ1_sentiment_proxy.json |  |
| 265 | KEEP | RC_10_econ_surprise | 0.74 | explore | RC | 경제 서프라이즈 틸트 — 실제 매크로 vs 예상 차이로 팩터 전환 | RC_10_economic_surprise_tilt.json |  |
| 266 | KEEP | RC_15_foreign_flow_regime | 0.74 | explore | RC | 외국인 순매수 국면 — 외국인 대규모 매도 시 방어 전환 | RC_15_krx_foreign_flow_regime.json |  |
| 267 | KEEP | RC_24_vol_term | 0.74 | explore | RC | 변동성 기간구조 — 단기Vol vs 장기Vol 비율로 변동성 국면 판단 | RC_24_volatility_term_structure.json |  |
| 268 | KEEP | RC_30_hmm_regime | 0.74 | explore | RC | HMM 시장 국면 — Hidden Markov Model로 2-state 국면 자동 판별 | RC_30_market_regime_hmm.json |  |
| 269 | KEEP | RC_44_krw_vol | 0.74 | explore | RC | KRW 변동성 국면 — 원달러 환율 변동성으로 EM 스트레스 감지 | RC_44_krw_vol_combined.json |  |
| 270 | KEEP | RC_46_monthly_snapshot | 0.74 | explore | RC | Monthly MRS Snapshot — 월말 MRS 한 번만 확인 (일별 대신 월별 국면) | RC_46_monthly_mrs_snapshot.json |  |
| 271 | KEEP | RC_61_ml_regime | 0.74 | explore | RC | ML 국면 감지 — XGBoost로 다음 달 위기 확률 예측 → 팩터 전환 | RC_61_ml_regime_detection.json |  |
| 272 | KEEP | SF_48_rf_stock | 0.74 | explore | SF | RF 종목 선정 — Random Forest로 종목별 다음 달 수익률 예측 | SF_48_ml_rf_stock_selection.json |  |
| 273 | KEEP | FM_46_regime_carry | 0.73 | exploit | FM | Regime Factor Carry — 국면별 IC×Vol + ML 위기확률 결합 | FM_46_regime_factor_carry.json |  |
| 274 | KEEP | FM_50_def_mom | 0.73 | exploit | FM | Defense Momentum — Defense 팩터 자체의 모멘텀으로 Defense 가중 조절 | FM_50_defense_momentum.json |  |
| 275 | KEEP | RC_63_ml_regime_ens | 0.73 | exploit | RC | ML Regime Ensemble — XGB+RF+Logistic 3모델 위기 확률 평균 | RC_63_ml_regime_ensemble.json |  |
| 276 | KEEP | SF_35_rev_brk | 0.73 | exploit | SF | 1F Reversal + BRK Overlay — 9번째 1F+BRK | SF_35_reversal_brk_overlay.json |  |
| 277 | KEEP | SF_42_rev_mrs1225 | 0.73 | exploit | SF | 1F Reversal + MRS12/25 — MRS12/25 시리즈 8번째 (1F MRS12/25 완전) | SF_42_reversal_mrs1225.json |  |
| 278 | KEEP | EN_37_geometric | 0.73 | explore | EN | Geometric Mean Ensemble — 기하평균으로 score 합산 | EN_37_geometric_mean_ensemble.json |  |
| 279 | KEEP | EN_56_ml_stacking | 0.73 | explore | EN | ML Model Stacking — XGB+RF+Ridge+GRU 4-model Level-2 앙상블 | EN_56_ml_ensemble_stacking.json |  |
| 280 | KEEP | FM_13_cross_factor_mom | 0.73 | explore | FM | Cross-Factor Momentum — 팩터 A 강세 → 상관 높은 팩터 B도 가중 | FM_13_cross_factor_momentum.json |  |
| 281 | KEEP | MF_BB1_COST_BUDGET | 0.73 | explore | MF | 거래비용 예산 제약 — Net SR 극대화를 위한 turnover cap | MF_BB1_cost_budget.json |  |
| 282 | KEEP | MF_III1_MIXED_FREQ | 0.73 | explore | MF | 혼합 빈도 리밸런싱 — Defense 분기 + Momentum 2주 + Others 월간 | MF_III1_mixed_frequency.json |  |
| 283 | KEEP | MF_KKKK1_SIZE_COND | 0.73 | explore | MF | 시총 조건부 팩터 — 대형주/중소형주에서 다른 팩터 적용 | MF_KKKK1_size_conditional.json |  |
| 284 | KEEP | MF_P1_KOREAN_MACRO | 0.73 | explore | MF | 한국 매크로 팩터 — ECOS 금리/환율 시그널 직접 팩터화 | MF_P1_korean_macro_factor.json |  |
| 285 | KEEP | MF_QQ1_FACTOR_CLUSTER | 0.73 | explore | MF | 팩터 클러스터 틸트 — 유사 팩터 그룹화 후 그룹별 대표 선정 | MF_QQ1_factor_cluster_tilt.json |  |
| 286 | KEEP | MF_TTT1_GOVERNANCE | 0.73 | explore | MF | 지배구조 프리미엄 — 한국 특수: 오너 리스크 회피 + 거버넌스 개선 수혜 | MF_TTT1_governance_premium.json |  |
| 287 | KEEP | MF_UUUU1_SIGNAL_DECAY_W | 0.73 | explore | MF | 시그널 감쇠 가중 — 팩터 half-life에 반비례하여 리밸런싱 빈도 조절 | MF_UUUU1_signal_decay_weighted.json |  |
| 288 | KEEP | RC_20_bond_equity_ratio | 0.73 | explore | RC | 채권-주식 비율 팩터 전환 — 국고채 수익률 vs KOSPI 배당수익률 | RC_20_korean_bond_equity.json |  |
| 289 | KEEP | RC_27_cross_asset_mom | 0.73 | explore | RC | Cross-Asset Momentum — S&P500/원유/금 추세로 한국 팩터 전환 | RC_27_cross_asset_momentum.json |  |
| 290 | KEEP | RC_36_weekly_rebal | 0.73 | explore | RC | 주간 리밸런싱 — 위기 국면에서만 주간 리밸런싱 (정상 시 월간) | RC_36_weekly_rebalance.json |  |
| 291 | KEEP | RC_48_vol_of_mrs | 0.73 | explore | RC | MRS의 변동성 — MRS 자체가 불안정할 때 추가 방어 | RC_48_volatility_of_mrs.json |  |
| 292 | KEEP | SF_13_min_regret | 0.73 | explore | SF | Minimum Regret — 최악 시나리오 대비 후회 최소화 팩터 배분 | SF_13_min_regret_portfolio.json |  |
| 293 | KEEP | SF_53_resid_mom | 0.73 | explore | SF | Residual Momentum — FF3 잔차의 12m-1m 모멘텀 | SF_53_residual_momentum.json |  |
| 294 | KEEP | FM_29_sector_fm | 0.72 | explore | FM | Sector-Conditional FM — 섹터별로 다른 FM lookback 적용 | FM_29_sector_conditional_fm.json |  |
| 295 | KEEP | FM_43_ml_fm | 0.72 | explore | FM | ML Factor Momentum — XGBoost로 다음 달 최적 FM lookback 예측 | FM_43_ml_factor_momentum.json |  |
| 296 | KEEP | MF_JJJ1_FACTOR_PCA | 0.72 | explore | MF | PCA 팩터 — 7팩터의 주성분 1~3으로 차원 축소 후 scoring | MF_JJJ1_factor_pca.json |  |
| 297 | KEEP | MF_K1_SECTOR_FACTOR | 0.72 | explore | MF | 섹터-팩터 로테이션 — 섹터별 최적 팩터로 종목 선정 | MF_K1_sector_factor.json |  |
| 298 | KEEP | MF_OOO1_FACTOR_SURPRISE | 0.72 | explore | MF | 팩터 서프라이즈 — 기대 대비 실제 팩터 성과 차이로 가중 조절 | MF_OOO1_factor_surprise.json |  |
| 299 | KEEP | MF_PP1_KELLY | 0.72 | explore | MF | Kelly 기준 포지션 사이징 — 팩터 신뢰도에 비례한 전체 노출 조절 | MF_PP1_kelly_sizing.json |  |
| 300 | KEEP | MF_V1_IC_PREDICTION | 0.72 | explore | MF | IC 예측 모델 — 다음 달 IC 최고 팩터 예측 → 가중 결정 | MF_V1_ic_prediction.json |  |
| 301 | KEEP | MF_YYY1_ANTI_HERDING | 0.72 | explore | MF | Anti-Herding — 기관/외국인 과매수 종목 회피 + 소외 종목 선호 | MF_YYY1_herding_avoidance.json |  |
| 302 | KEEP | RC_14_put_call_ratio | 0.72 | explore | RC | Put/Call Ratio 팩터 전환 — KOSPI200 옵션 PCR로 극단 심리 감지 | RC_14_put_call_ratio.json |  |
| 303 | KEEP | RC_22_intraday_vol | 0.72 | explore | RC | 장중 변동성 시그널 — Open-Close vs High-Low 비율로 시장 불안 감지 | RC_22_intraday_vol_signal.json |  |
| 304 | KEEP | RC_42_realized_skew | 0.72 | explore | RC | Realized Skewness 국면 — 시장 수익률 비대칭도로 꼬리 위험 감지 | RC_42_realized_skew_regime.json |  |
| 305 | KEEP | RC_49_trend_strength | 0.72 | explore | RC | 추세 강도 국면 — ADX(Average Directional Index)로 추세/횡보 구분 | RC_49_trend_strength_regime.json |  |
| 306 | KEEP | RC_65_sentiment_regime | 0.72 | explore | RC | Sentiment Regime — 거래량+신용거래+IPO 종합 심리 지수 국면 | RC_65_sentiment_regime.json |  |
| 307 | KEEP | SF_54_es_factor | 0.72 | explore | SF | Expected Shortfall 팩터 — CVaR 낮은 종목 선호 (Defense 대안) | SF_54_expected_shortfall_factor.json |  |
| 308 | KEEP | SF_60_net_payout | 0.72 | explore | SF | Net Payout Yield — (배당 + 자사주매입 - 유상증자) / 시총 | SF_60_net_payout_yield.json |  |
| 309 | KEEP | FM_19_mean_rev_speed | 0.71 | explore | FM | Factor Mean-Reversion Speed — OU 프로세스 속도로 FM vs 역FM 결정 | FM_19_factor_mean_revert_speed.json |  |
| 310 | KEEP | FM_47_rel_ic_mom | 0.71 | explore | FM | Relative IC Momentum — 각 팩터 IC의 BM IC 대비 초과 IC로 가중 | FM_47_relative_ic_momentum.json |  |
| 311 | KEEP | FM_52_alpha_decay | 0.71 | explore | FM | Alpha Decay Adaptive FM — 팩터별 alpha decay 속도에 맞춘 FM 반응속도 | FM_52_alpha_decay_adaptive.json |  |
| 312 | KEEP | MF_KKK1_VOL_OF_VOL | 0.71 | explore | MF | Vol-of-Vol 시그널 — 변동성의 변동성이 높은 종목 회피 | MF_KKK1_volatility_of_volatility.json |  |
| 313 | KEEP | MF_MMMM1_VALUATION_SPREAD | 0.71 | explore | MF | 팩터 밸류에이션 스프레드 — 팩터 long/short 밸류에이션 차이로 crowding 측정 | MF_MMMM1_factor_valuation_spread.json |  |
| 314 | KEEP | MF_RRR1_CROSS_MARKET | 0.71 | explore | MF | 크로스마켓 시그널 — 미국/중국 팩터 수익률로 한국 팩터 예측 | MF_RRR1_cross_market_signal.json |  |
| 315 | KEEP | MF_T1_CARRY | 0.71 | explore | MF | Carry 팩터 — 배당수익률 + 이익수익률 결합 (한국 Carry Premium) | MF_T1_carry_factor.json |  |
| 316 | KEEP | MF_UU1_MV_FACTOR | 0.71 | explore | MF | Mean-Variance 팩터 최적화 — 팩터 기대수익률/공분산으로 최적 가중 | MF_UU1_mean_variance_factor.json |  |
| 317 | KEEP | RC_70_iv_rv | 0.71 | explore | RC | IV-RV Spread Regime — VKOSPI vs RV 차이로 공포 프리미엄 국면 | RC_70_implied_vs_realized_vol.json |  |
| 318 | KEEP | SF_49_nn_stock | 0.71 | explore | SF | NN 종목 선정 — 2-layer MLP로 종목별 수익률 예측 | SF_49_ml_nn_stock_selection.json |  |
| 319 | KEEP | SF_57_max_ret_conc | 0.71 | explore | SF | Max Return Concentration — 상위 10종목 집중 + 나머지 20종목 분산 | SF_57_max_return_concentration.json |  |
| 320 | KEEP | SF_61_op_leverage | 0.71 | explore | SF | Operating Leverage — 매출 변화 대비 영업이익 변화 민감도 | SF_61_operating_leverage.json |  |
| 321 | KEEP | BACKLOG_ANTI_LOTTERY_V2 | 0.70 | exploit | BACKLOG | anti_lottery 패밀리 확장 — 3 trials, PASS 이력, v7.1 업그레이드 | BACKLOG_anti_lottery_v2.json |  |
| 322 | KEEP | REGIME_02 | 0.70 | stabilize | REGIME | 기관 순매수 20d → 시장 타이밍 Regime Overlay (cor=+0.166, 데이터 이미 보유) | REGIME_02_institutional_flow_overlay.json |  |
| 323 | KEEP | ALPHA_09 | 0.70 | explore | ALPHA | 잔여이익 모형(RIM) V/P Ratio — BM 가치팩터 대체, FF5α 설명 불가 영역 포착 | ALPHA_09_residual_income_vp.json |  |
| 324 | KEEP | FM_06_contrarian_timing | 0.70 | explore | FM | Contrarian Factor Timing — 12m 최악 팩터에 가중 (장기 역전) | FM_06_contrarian_factor_timing.json |  |
| 325 | KEEP | FM_15_factor_rev_3m | 0.70 | explore | FM | 3m Factor Reversal — 최근 3m 최악 팩터 매수 (단기 팩터 역전) | FM_15_factor_reversal_3m.json |  |
| 326 | KEEP | FM_44_ml_metric | 0.70 | explore | FM | ML 최적 FM 메트릭 — XGBoost로 SR/IC/ICIR 중 최적 메트릭 예측 | FM_44_ml_optimal_fm_metric.json |  |
| 327 | KEEP | FM_49_sector_fm | 0.70 | explore | FM | Sector-Level Factor Momentum — 섹터별로 다른 팩터 FM 적용 | FM_49_sector_factor_momentum.json |  |
| 328 | KEEP | FM_51_cross_asset | 0.70 | explore | FM | Cross-Asset Factor Lead — 미국 팩터 ETF 수익률로 한국 팩터 FM | FM_51_cross_asset_factor_lead.json |  |
| 329 | KEEP | MF_N1_ANTI_CROWDING | 0.70 | explore | MF | Anti-Crowding 팩터 — 혼잡도 낮은 팩터에 역방향 가중 | MF_N1_factor_crowding_contrarian.json |  |
| 330 | KEEP | MF_YY1_EARNINGS_EVENT | 0.70 | explore | MF | 실적 이벤트 팩터 — 실적 발표 전후 윈도우에서만 팩터 활성화 | MF_YY1_earnings_event.json |  |
| 331 | KEEP | RC_67_cons_density | 0.70 | explore | RC | Consensus Density Regime — 애널리스트 커버리지 변화율로 정보 국면 | RC_67_consensus_density_regime.json |  |
| 332 | KEEP | RC_68_turnover_regime | 0.70 | explore | RC | Turnover Regime — 시장 전체 거래회전율로 과열/침체 감지 | RC_68_turnover_regime.json |  |
| 333 | KEEP | RC_71_corr_speed | 0.70 | explore | RC | Factor Correlation Speed — 팩터 상관 변화 속도로 위기 조기 감지 | RC_71_factor_correlation_speed.json |  |
| 334 | KEEP | MF_DD1_SEASONAL | 0.69 | explore | MF | 계절성 팩터 로테이션 — 1월 효과/실적 시즌/세금 매도 활용 | MF_DD1_seasonal_factor.json |  |
| 335 | KEEP | MF_QQQ1_NETWORK | 0.69 | explore | MF | 네트워크 중심성 팩터 — 수익률 상관 네트워크에서 주변부 종목 선호 | MF_QQQ1_network_centrality.json |  |
| 336 | KEEP | RC_62_ae_regime | 0.69 | explore | RC | Autoencoder 국면 감지 — 재구성 오류로 시장 이상 상태 감지 | RC_62_autoencoder_regime.json |  |
| 337 | KEEP | RC_69_size_rotation | 0.69 | explore | RC | Size Rotation Regime — 소형주/대형주 상대 강도로 팩터 전환 | RC_69_size_rotation_regime.json |  |
| 338 | KEEP | MF_EEEE1_AUTOML | 0.68 | explore | MF | AutoML 팩터 배분 — H2O AutoML로 최적 모델 자동 탐색 | MF_EEEE1_automl_factor.json |  |
| 339 | KEEP | MF_XX1_GENETIC_ALGO | 0.68 | explore | MF | 유전 알고리즘 팩터 가중 — Expanding OOS fitness로 진화 | MF_XX1_genetic_algo.json |  |
| 340 | KEEP | RC_39_calendar_anomaly | 0.68 | explore | RC | 캘린더 이상현상 — 월별 평균 수익률 기반 공격/방어 전환 | RC_39_calendar_anomaly.json |  |
| 341 | KEEP | RC_64_transition | 0.68 | explore | RC | ML Transition Matrix — 국면 전환 확률 행렬 학습 → 다음 국면 예측 | RC_64_ml_transition_matrix.json |  |
| 342 | KEEP | MF_ZZ1_COPULA_TAIL | 0.66 | explore | MF | Copula 기반 팩터 결합 — 꼬리 의존성 반영 비선형 결합 | MF_ZZ1_copula_factor.json |  |
| 343 | KEEP | MF_MM1_TRANSFORMER | 0.65 | explore | MF | Transformer 기반 팩터 배분 — Self-attention으로 팩터 간 관계 학습 | MF_MM1_transformer_factor.json |  |
| 344 | KEEP | ALPHA_22 | 0.60 | explore | ALPHA | Modified Amihud (AdjILLIQ) — 신흥시장 최적화 비유동성 측도, 한국 미검증 | ALPHA_22_modified_amihud.json |  |
| 345 | KEEP | STR_1041 |  |  | MSG | Detoned-NCO 가중 앙상블 — 3-sleeve 수익률에 RMT denoise + market eigenvalue 제거(detoning) + NCO 클러스터링 적용. STR_1033(NCO Score 78.1)의 방법론을 앙상블 레벨에 적용. | msg_002_build.json |  |
| 346 | KEEP_RESCOPED | ALPHA_21 | 0.95 | exploit | ALPHA | Quality+Reversal Composite — Bias-Free IC=+0.023, t=3.37 (Harvey 통과, 4th Alpha 확정 후보) | ALPHA_21_quality_reversal_composite.json | standalone backtest weak; keep only as gate/tilt/retest candidate |
| 347 | KEEP_ARCH_OVERLAY | EVO_1036_943_score_blend | 5.00 | EXPLOIT | EVO | Evolution: STR_1036 + STR_943 스코어 블렌드 → 독립 alpha 조합 | EVO_1036_943_score_blend.json |  |
| 348 | KEEP_ARCH_OVERLAY | EVO_1036_vol_target | 5.00 | EXPLOIT | EVO | Evolution: STR_1036 + vol_target overlay → SR 1.25→1.5 | EVO_1036_vol_target.json |  |
| 349 | KEEP_ARCH_OVERLAY | EVO_1048_dd_vt_overlay | 4.00 | EXPLOIT | EVO | Evolution: STR_1048 v2 + vol_target + DD start 0.08 → MDD 32%→25% | EVO_1048_dd_vt_overlay.json |  |
| 350 | KEEP_ARCH_OVERLAY | EVO_1036_hrp_maxw10 | 3.00 | EXPLOIT | EVO | Evolution: STR_1036 + HRP max_weight 15%→10% → 집중도 완화 | EVO_1036_hrp_maxw10.json |  |
| 351 | KEEP_ARCH_OVERLAY | BRK_06 | 0.96 | stabilize | BRK | STR_1036 Ultimate Minimal: Sleeve VT 제거 + DD8 + MRS Binary (4중→2중) | BRK_06_ultimate_minimal_overlay.json |  |
| 352 | KEEP_ARCH_OVERLAY | NCO_C11_FIX | 0.96 | stabilize | NCO | STR_1033/1107/1108/1109 Phase 4 regime_engine_daily.R 교체 (C11 필수 수정) | NCO_C11_FIX_regime_daily.json |  |
| 353 | KEEP_ARCH_OVERLAY | PROD_APRIL_2026 | 0.95 | production | PROD | 4월 실투 전략: STR_1060 기반, Daily Regime 없이, 월간 30종목 EW | PROD_april2026_simple_portfolio.json |  |
| 354 | KEEP_ARCH_OVERLAY | BRK_01 | 0.95 | stabilize | BRK | STR_1036 DD Brake 완화: DD_med 4%→8%, DD_short 2%→5% | BRK_01_dd_relax.json |  |
| 355 | KEEP_ARCH_OVERLAY | BRK_05 | 0.94 | stabilize | BRK | STR_1036 Sleeve-Level VT 완전 제거 (4중→2중 오버레이) | BRK_05_remove_sleeve_vt.json |  |
| 356 | KEEP_ARCH_OVERLAY | PROD_APRIL_NCO | 0.93 | production | PROD | 4월 투자 전략 업그레이드: STR_1060 vs NCO C11 fix 비교 후 최선택 | PROD_april2026_nco_upgrade.json |  |
| 357 | KEEP_ARCH_OVERLAY | BRK_02 | 0.93 | stabilize | BRK | STR_1036 Short DD Brake 완전 제거 (이중 헤지 해소) | BRK_02_remove_short_dd.json |  |
| 358 | KEEP_ARCH_OVERLAY | BRK_04 | 0.92 | stabilize | BRK | STR_1036 오버레이 극단 단순화: DD_med(8%) + MRS Binary ONLY | BRK_04_combined_overlay_simplify.json |  |
| 359 | KEEP_ARCH_OVERLAY | BRK_03 | 0.90 | stabilize | BRK | STR_1036 MRS Binary 전환: Soft Ramp → Crisis-Only Hard Switch | BRK_03_mrs_binary.json |  |
| 360 | KEEP_ARCH_OVERLAY | EVO_1033_MDD_REDUCTION | 0.88 | exploit | EVO | STR_1033 NCO MDD 24.8% → <22% 감소: Short DD 제거 + DD Brake 완화 적용 | EVO_1033_mdd_reduction.json |  |
| 361 | KEEP_ARCH_OVERLAY | ARCH_02_DISP_CONDWEIGHT | 0.84 | exploit | ARCH | 5-Sleeve Dispersion CondWeight: 분산도 기반 슬리브 배분 동적 조절 | ARCH_02_dispersion_condweight_5sleeve.json |  |
| 362 | KEEP_ARCH_OVERLAY | EVO_1036_6TH_FRICTION | 0.82 | exploit | EVO | STR_1036 + 6th Sleeve: Trading Friction (STR_1079 SR 0.657) — 5→6 sleeve 확장 | EVO_1036_6th_sleeve_friction.json |  |
| 363 | KEEP_ARCH_OVERLAY | NCO_EVO_DYNAMIC_K | 0.82 | exploit | NCO | NCO Dynamic Cluster Count: 위기 시 집중(k=2-3), 정상 시 분산(k=5-8) | NCO_EVO_dynamic_k.json |  |
| 364 | KEEP_ARCH_OVERLAY | EVO_1036_CONSGATE_REPLACE | 0.78 | exploit | EVO | STR_1036 ConsGate sleeve를 OCF_ROA gate로 대체 — bias-free t=3.28 활용 | EVO_1036_consgate_replace_accrual.json |  |
| 365 | KEEP_ARCH_OVERLAY | NCO_EVO_MULTI_LOOKBACK | 0.78 | exploit | NCO | NCO Multi-Lookback Ensemble: 60/120/252일 윈도우 가중 평균 | NCO_EVO_multi_lookback.json |  |
| 366 | KEEP_ARCH_OVERLAY | ARCH_01 | 0.75 | stabilize | ARCH | Bounded Multi-Factor Tilt Architecture — EW baseline + 팩터 tilt 제한으로 robust 포트폴리오 | ARCH_01_bounded_factor_tilt.json |  |
| 367 | KEEP_ARCH_OVERLAY | EVO_1036_QUALITY_GATE | 0.75 | stabilize | EVO | STR_1036 + DART Quality Gate (PiotroskiF<3 / IsZombie 제거) — 각 sleeve 선별 전 적용 | EVO_1036_quality_gate.json |  |
| 368 | KEEP_ARCH_OVERLAY | NCO_EVO_SPECTRAL_RMT | 0.72 | explore | NCO | NCO Spectral Clustering + RMT Covariance (Garcia-Medina 2023) | NCO_EVO_spectral_rmt.json |  |
| 369 | KEEP_ARCH_OVERLAY | ARCH_03_THRESHOLD_REBAL | 0.68 | explore | ARCH | Threshold-Based Rebalancing: Score 변동 임계치 초과 시에만 교체 | ARCH_03_threshold_rebal.json |  |
| 370 | KEEP_DATA_FIRST | RC_31_kr_internals_only | 0.80 | exploit | RC | 한국 내부 시그널 Only — ECOS+KRX 데이터만으로 국면 판단 (FRED 제외) | RC_31_korean_internals_only.json |  |
| 371 | KEEP_DATA_FIRST | ALPHA_02 | 0.80 | explore | ALPHA | Option-Implied Vol Skew (VKOSPI) → 종목별 위험 프리미엄 Alpha | ALPHA_02_option_implied.json |  |
| 372 | KEEP_DATA_FIRST | ALPHA_03 | 0.75 | explore | ALPHA | LLM/NLP 뉴스 센티먼트 Alpha (한국어 공시 + 뉴스) | ALPHA_03_nlp_sentiment.json |  |
| 373 | KEEP_DATA_FIRST | SF_56_disagreement | 0.73 | explore | SF | Analyst Disagreement — EPS 전망치 분산 낮은 종목 선호 | SF_56_analyst_disagreement.json |  |
| 374 | KEEP_DATA_FIRST | ALPHA_07 | 0.72 | explore | ALPHA | 애널리스트 공동커버리지 리드-래그 모멘텀 (Graph ML 없이 단순 구현) | ALPHA_07_analyst_cocoverage_mom.json |  |
| 375 | KEEP_DATA_FIRST | MF_VVV1_IMPLIED_VOL | 0.67 | explore | MF | 옵션 내재변동성 시그널 — IV-RV 스프레드로 과대평가 종목 회피 | MF_VVV1_option_implied_vol.json |  |
| 376 | KEEP_ML | ML_01_lightgbm | 0.74 | explore | ML | LightGBM 팩터 배분 — XGBoost 대비 속도 우위, leaf-wise 학습 | ML_01_lightgbm_factor.json |  |
| 377 | KEEP_ML | ML_02_catboost | 0.73 | explore | ML | CatBoost 팩터 배분 — Ordered Boosting으로 시계열 overfitting 방지 | ML_02_catboost_factor.json |  |
| 378 | KEEP_ML | ML_06_online_learning | 0.73 | explore | ML | Online Learning — 매월 1-step 업데이트로 모델 점진 학습 | ML_06_online_learning.json |  |
| 379 | KEEP_ML | ML_04_stacking | 0.72 | explore | ML | Stacking Meta-Learner — XGB+RF+EN 예측을 2차 모델로 결합 | ML_04_stacking_meta_learner.json |  |
| 380 | KEEP_ML | ML_07_feat_pruned | 0.72 | explore | ML | Feature-Pruned XGBoost — 중요도 하위 50% 피처 제거 후 재학습 | ML_07_feature_importance_pruned.json |  |
| 381 | KEEP_ML | ML_10_bayesian_ridge | 0.72 | explore | ML | Bayesian Ridge Regression — 불확실성 추정 + 팩터 가중 | ML_10_bayesian_ridge.json |  |
| 382 | KEEP_ML | ML_05_qrf | 0.71 | explore | ML | Quantile Regression Forest — 수익률 분포 예측 → CVaR 최소화 종목 선정 | ML_05_quantile_regression_forest.json |  |
| 383 | KEEP_ML | ML_14_moe | 0.71 | explore | ML | Mixture of Experts — 국면별 전문가 모델 자동 전환 | ML_14_mixture_of_experts.json |  |
| 384 | KEEP_ML | ML_19_interpretable | 0.71 | explore | ML | Interpretable ML — EBM(Explainable Boosting Machine) 팩터 배분 | ML_19_interpretable_ml.json |  |
| 385 | KEEP_ML | ML_08_nn_factor | 0.70 | explore | ML | Shallow NN 팩터 배분 — 2-layer MLP (32→16→7) 단순 신경망 | ML_08_neural_network_factor.json |  |
| 386 | KEEP_ML | ML_15_conformal | 0.70 | explore | ML | Conformal Prediction — 예측 구간으로 확신도 기반 팩터 가중 | ML_15_conformal_prediction.json |  |
| 387 | KEEP_ML | ML_17_iforest | 0.70 | explore | ML | Isolation Forest — 이상 종목 감지 후 제거 (anomaly gate) | ML_17_isolation_forest_anomaly.json |  |
| 388 | KEEP_ML | ML_21_rfe | 0.70 | explore | ML | Recursive Feature Elimination — 자동 팩터 선택 후 XGBoost | ML_21_feature_selection_rfe.json |  |
| 389 | KEEP_ML | ML_09_gru | 0.69 | explore | ML | GRU 팩터 배분 — LSTM 대비 경량 RNN | ML_09_gru_factor.json |  |
| 390 | KEEP_ML | ML_20_stock_cluster | 0.69 | explore | ML | Stock Clustering Selection — K-means로 종목 클러스터링 후 클러스터별 Top 선정 | ML_20_stock_clustering_selection.json |  |
| 391 | KEEP_ML | ML_11_gp | 0.68 | explore | ML | Gaussian Process Regression — 비선형 팩터 관계 + 불확실성 추정 | ML_11_gaussian_process.json |  |
| 392 | KEEP_ML | ML_03_tabnet | 0.67 | explore | ML | TabNet 팩터 배분 — Attention 기반 테이블 데이터 DL | ML_03_tabnet_factor.json |  |
| 393 | KEEP_ML | ML_12_svm | 0.67 | explore | ML | SVM Regression — Support Vector Machine 팩터 수익률 예측 | ML_12_svm_factor.json |  |
| 394 | KEEP_ML | ML_22_dae | 0.67 | explore | ML | Denoising Autoencoder — 팩터 데이터 노이즈 제거 후 scoring | ML_22_denoising_autoencoder.json |  |
| 395 | KEEP_ML | ML_13_knn | 0.66 | explore | ML | KNN Regression — 유사 과거 국면 k개 평균으로 팩터 수익률 예측 | ML_13_knn_factor.json |  |
| 396 | KEEP_ML | ML_16_rl | 0.65 | explore | ML | Reinforcement Learning — 팩터 배분을 행동(action)으로 학습 | ML_16_reinforcement_learning.json |  |
| 397 | KEEP_ML | ML_18_vae | 0.64 | explore | ML | VAE 잠재 팩터 — Variational Autoencoder로 잠재 팩터 추출 후 scoring | ML_18_variational_autoencoder.json |  |
| 398 | KEEP_RERUN | STR_1030 | 0.96 | rerun | MSG_RERUN | 재실행 — STR_1030 — 동일 원인. Gerber+BL 고유 조합. | msg_005_rerun_trio.json |  |
| 399 | KEEP_RERUN | STR_1033 | 0.96 | rerun | MSG_RERUN | 재실행 — STR_1033 — 동일 원인. NCO 아키텍처 유망, FF5 t=2.889. | msg_005_rerun_trio.json |  |
| 400 | KEEP_RERUN | STR_1035 | 0.96 | rerun | MSG_RERUN | 재실행 — STR_1035 — macro_regime.parquet가 cron에 의해 구MRS로 복원됐었음. v7.1 재교체 완료. 재실행 필요. | msg_005_rerun_trio.json |  |
| 401 | KEEP_DIAGNOSTIC | RC_50_regime_compare | 0.83 | diagnose | RC | [진단] 국면 시그널 전수 비교 — MRS/KMRS/VIX/Disp/Vol/DD/Breadth/AR/CUSUM 9종 | RC_50_final_regime_comparison.json |  |
| 402 | KEEP_DIAGNOSTIC | RC_58_mrs_thresh_sweep | 0.83 | diagnose | RC | [진단] MRS Threshold Sweep — Low(10/12/15/18) × High(22/25/28/30) = 16조합 | RC_58_mrs_threshold_sweep.json |  |
| 403 | KEEP_DIAGNOSTIC | EN_28_opt_size | 0.82 | diagnose | EN | [진단] 최적 앙상블 크기 — 1~10 전략 순차 추가 시 SR 변화 곡선 | EN_28_optimal_ensemble_size.json |  |
| 404 | KEEP_DIAGNOSTIC | EN_49_ensemble_compare | 0.82 | diagnose | EN | [진단] 앙상블 방법 전수 비교 — EW/SR/Calmar/Median/RP/MaxSR/FF5/Jackknife 8종 | EN_49_final_ensemble_comparison.json |  |
| 405 | KEEP_DIAGNOSTIC | FM_39_fm_compare | 0.81 | diagnose | FM | [진단] FM 방법 전수 비교 — SR/IC/ICIR/EWMA/Carry/Duration/Expanding 7종 | FM_39_final_fm_comparison.json |  |
| 406 | KEEP_DIAGNOSTIC | EN_29_meta_diag | 0.80 | diagnose | EN | [진단] Meta Diagnostic — 전체 앙상블 전략 간 상관/분산/기여 분석 | EN_29_meta_diagnostic.json |  |
| 407 | KEEP_DIAGNOSTIC | EN_39_complete_avg | 0.80 | diagnose | EN | [진단] 앙상블 평균법 비교 — 산술/기하/조화/중앙값/Trimmed/Winsorized 6종 | EN_39_complete_averaging.json |  |
| 408 | KEEP_DIAGNOSTIC | EN_55_ens_ablation | 0.80 | diagnose | EN | [진단] 앙상블 Ablation — 5전략 중 1전략씩 제거 시 앙상블 SR 변화 | EN_55_ensemble_ablation.json |  |
| 409 | KEEP_DIAGNOSTIC | RC_55_no_regime | 0.80 | diagnose | RC | [진단] No Regime Baseline — MRS 없이 DD+VT만 (국면 시그널 기여분 측정) | RC_55_no_regime_baseline.json |  |
| 410 | KEEP_DIAGNOSTIC | EN_48_n_strat_sweep | 0.79 | diagnose | EN | [진단] 앙상블 전략 수 sweep — 1/2/3/5/7/10 전략 EW 비교 | EN_48_n_strategy_sweep.json |  |
| 411 | KEEP_DIAGNOSTIC | EN_54_no_ensemble | 0.79 | diagnose | EN | [진단] No Ensemble Baseline — 단일 전략(EV_06) 대조군 | EN_54_no_ensemble_baseline.json |  |
| 412 | KEEP_DIAGNOSTIC | FM_42_no_fm | 0.79 | diagnose | FM | [진단] No FM Baseline — 7F EW 고정가중 (FM 없음, MF_A1 = 대조군) | FM_42_no_fm_baseline.json |  |
| 413 | KEEP_DIAGNOSTIC | RC_56_regime_ablation | 0.79 | diagnose | RC | [진단] 국면 시그널 Ablation — 9축 중 1축씩 제거 시 합산 국면 성과 변화 | RC_56_best_regime_with_ablation.json |  |
| 414 | KEEP_DIAGNOSTIC | RC_59_dd_full_sweep | 0.78 | diagnose | RC | [진단] DD Full Threshold Sweep — 20%/25%/30%/35%/40% 비교 | RC_59_dd_full_sweep.json |  |
| 415 | KEEP_DIAGNOSTIC | RC_60_dd_minexp_sweep | 0.78 | diagnose | RC | [진단] DD Min Exposure Sweep — 10%/20%/30%/40%/50% 비교 | RC_60_dd_min_exp_sweep.json |  |
| 416 | KEEP_DIAGNOSTIC | EN_45_pairwise | 0.77 | diagnose | EN | [진단] Pairwise Ensemble — 5C2=10개 2전략 쌍 전수 비교 | EN_45_pairwise_ensemble.json |  |
| 417 | KEEP_DIAGNOSTIC | MF_CCC1_FACTOR_QUALITY | 0.77 | diagnose | MF | 팩터 품질 필터 — IC/ICIR/Turnover 3축으로 팩터 자체의 품질 관리 | MF_CCC1_factor_quality_filter.json |  |
| 418 | KEEP_DIAGNOSTIC | RC_57_regime_interact | 0.77 | diagnose | RC | [진단] 국면 시그널 상호작용 — 2축 쌍별 AND vs OR 비교 | RC_57_regime_signal_interaction.json |  |
| 419 | KEEP_DIAGNOSTIC | FM_32_regime_lb_sweep | 0.76 | diagnose | FM | [진단] FM Lookback Sweep — 1m/3m/6m/9m/12m × 3 국면 = 15건 | FM_32_regime_conditional_lookback_sweep.json |  |
| 420 | KEEP_DIAGNOSTIC | FM_37_pure_sr | 0.76 | diagnose | FM | [진단] Pure SR FM vs Pure IC FM — SR vs IC 어느 쪽이 FM에 우수 | FM_37_pure_sr_no_ic.json |  |
| 421 | KEEP_DIAGNOSTIC | MF_O1_FACTOR_DECAY | 0.76 | diagnose | MF | [진단+전략] 팩터 Decay 분석 → 팩터별 최적 리밸런싱 주기 멀티팩터 | MF_O1_factor_decay_optimal_rebal.json |  |
| 422 | KEEP_DIAGNOSTIC | FM_26_roll_vs_expand | 0.75 | diagnose | FM | [진단] Rolling vs Expanding FM — 6m rolling FM vs expanding FM 비교 | FM_26_rolling_vs_expanding_fm.json |  |
| 423 | KEEP_DIAGNOSTIC | SF_12_7f_no_overlay | 0.75 | diagnose | SF | 7F EW No Overlay — 순수 팩터 alpha 측정용 (overlay 없는 baseline) | SF_12_7factor_equal_no_overlay.json |  |
| 424 | KEEP_DIAGNOSTIC | SF_25_2f_naked | 0.75 | diagnose | SF | 2F EW No Overlay — 순수 Def+Cons alpha (NNNN1의 naked baseline) | SF_25_2f_ew_no_overlay.json |  |
| 425 | KEEP_DIAGNOSTIC | SF_26_5f_naked | 0.74 | diagnose | SF | 5F EW No Overlay — naked baseline 세트 5F 지점 | SF_26_5f_naked.json |  |
| 426 | KEEP_DIAGNOSTIC | SF_27_1f_naked | 0.73 | diagnose | SF | 1F Defense No Overlay — 순수 저변동 프리미엄 baseline | SF_27_1f_defense_naked.json |  |
| 427 | KEEP_DIAGNOSTIC | SF_29_1f_quality_naked | 0.72 | diagnose | SF | 1F Quality No Overlay — GPA+PiotroskiF 순수 alpha baseline | SF_29_1f_quality_naked.json |  |
| 428 | KEEP_DIAGNOSTIC | SF_30_1f_value_naked | 0.72 | diagnose | SF | 1F Value No Overlay — OCF/MCap 순수 alpha baseline | SF_30_1f_value_naked.json |  |
| 429 | KEEP_DIAGNOSTIC | MF_HHH1_FACTOR_AGE | 0.70 | diagnose | MF | 팩터 노화 모델 — 출간 후 alpha decay 추적 (post-publication decay) | MF_HHH1_factor_age.json |  |
| 430 | KEEP_DIAGNOSTIC | SF_31_1f_rev_naked | 0.70 | diagnose | SF | 1F Reversal No Overlay — Rev21d 순수 alpha (8번째 1F naked) | SF_31_1f_reversal_naked.json |  |
| 431 | LOW_KNOWN_WEAK | ALPHA_19 | 0.90 | exploit | ALPHA | Contrarian Composite — 한국시장 역방향 시그널 결합 (IC 실증 기반) | ALPHA_19_contrarian_composite.json | SCOUT_ALERT_FINAL deprecated standalone contrarian composite |
| 432 | LOW_KNOWN_WEAK | ALPHA_16 | 0.84 | exploit | ALPHA | 효율성 시그널 배치 (InventoryTurnover/AssetTurnover/CCC) — 한국 LASSO 88% 선택률 | ALPHA_16_efficiency_turnover.json | SCOUT alert: weak/non-significant preliminary evidence |
| 433 | LOW_KNOWN_WEAK | ALPHA_17 | 0.73 | explore | ALPHA | Shareholder Yield (배당+자사주매입) — Korea Value-Up 수혜주 포착 | ALPHA_17_shareholder_yield.json | SCOUT alert: weak/non-significant preliminary evidence |
| 434 | LOW_KNOWN_WEAK | ALPHA_11 | 0.68 | explore | ALPHA | Asset Growth Anomaly — 총자산 증가율 역방향 시그널 (투자 팩터 대용) | ALPHA_11_asset_growth.json | SCOUT alert: weak/non-significant preliminary evidence |
| 435 | DONE_OR_CONSUMED | STR_1048 | 0.96 |  | MSG | 종목 레벨 3-factor 앙상블 (30종목 제한 준수) — 수익률 블렌드가 아닌 종목 레벨 score 합산. Defense(IdioVol+Beta) + Consensus(EPS change) + IndMom을 하나의 composite score로 결합하여 Top 30 선별. 단일 포트폴리오. | msg_004_stock_ensemble.json | result file exists in forge/outbox |
| 436 | DONE_OR_CONSUMED | ALPHA_10 | 0.82 | explore | ALPHA | Gross Profitability (GP/Assets) — 한국시장 SDF 유의, QMJ composite와 별개의 단일 시그널 | ALPHA_10_gross_profitability.json | Quality GP smoke run completed 2026-06-12: Grade F |
| 437 | DONE_OR_CONSUMED | STR_1039 |  |  | MSG | 국면 조건부 슬리브 배분 — v7.1 MRS에 따라 3-sleeve(STR_1037+STR_943+STR_898) 가중을 동적으로 조절. RISK_ON: Consensus heavy(50%), CRISIS: Defense heavy(60%) | msg_001_build.json | result file exists in forge/outbox |
| 438 | DROP_COORDINATION_ONLY | msg_003_pivot |  |  | MSG | 수익률 블렌드 앙상블 중단. 종목 레벨 앙상블로 전환. STR_1041(Detoned-NCO) 작업 중이면 완료 후 다음 작업은 종목 레벨 앙상블로 진행. 30종목 제한 준수 필수. | msg_003_pivot.json | pivot instruction, not a strategy spec |
| 439 | DROP_NON_STRATEGY | SCOUT_ALERT_bias_correction_final | 0.98 |  | SCOUT | FINAL: Bias-Free IC 결과 — 이전 모든 preliminary IC 결과 무효. Tail Risk 방향 반전. | SCOUT_ALERT_bias_correction_final.json | alert/note/data_requirement/diagnose command |
| 440 | DROP_NON_STRATEGY | SCOUT_ALERT_final_corrected | 0.98 |  | SCOUT | FINAL CORRECTED: DART Quality IC 전부 정방향 확인! 이전 ALERT_001 철회 | SCOUT_ALERT_final_corrected.json | alert/note/data_requirement/diagnose command |
| 441 | DROP_NON_STRATEGY | DIAGNOSE_SLEEVE_CORR | 0.75 | diagnose | DIAGNOSE | [진단] 5-Sleeve 시간변동 상관 분석 — 슬리브 중복/독립성 진단 | DIAGNOSE_sleeve_correlation.json | alert/note/data_requirement/diagnose command |
| 442 | DROP_NON_STRATEGY | ALPHA_08_data_collection_guide |  |  | ALPHA | ALPHA_08 KRX 투자자별 매매동향 데이터 수집 가이드 | ALPHA_08_data_collection_guide.json | alert/note/data_requirement/diagnose command |
| 443 | DROP_NON_STRATEGY | RESEARCH_NOTE_liquidity_risk_momentum |  |  | RESEARCH | 연구 메모: Pastor-Stambaugh 유동성 리스크가 모멘텀 수익의 50%를 설명 — IndMom sleeve 시사점 | RESEARCH_NOTE_liquidity_risk_momentum.json | alert/note/data_requirement/diagnose command |
| 444 | DROP_NON_STRATEGY | SCOUT_ALERT_ic_backtest_gap |  |  | SCOUT | ALPHA_21 prototype backtest BM 하회 — IC≠Backtest 괴리 발견 | SCOUT_ALERT_ic_backtest_gap.json | alert/note/data_requirement/diagnose command |
| 445 | DROP_NON_STRATEGY | SCOUT_ALERT_quality_reversal |  |  | SCOUT | CRITICAL: 한국시장 Quality/Profitability IC 전부 음수 — 가설 방향 수정 필요 | SCOUT_ALERT_quality_reversal.json | alert/note/data_requirement/diagnose command |
| 446 | DROP_NON_STRATEGY | SCOUT_ALERT_shared_denominator |  |  | SCOUT | CRITICAL: Reversal IC 0.95는 shared-denominator artifact — Forge 구현 시 반드시 수정 | SCOUT_ALERT_shared_denominator.json | alert/note/data_requirement/diagnose command |

## Downloaded Papers Not Yet Strategy Specs
| ID | Category | Title |
|---|---|---|
| P0248 | 1-5.Earnings_Consensus | Consensus-Bottleneck Asset Pricing Model |
| P0249 | 1-5.Earnings_Consensus | Generative AI for Stock Selection |
| P0250 | 1-5.Earnings_Consensus | Extracting Alpha from Financial Analyst Networks |
| P0251 | 1-5.Earnings_Consensus | Retail Investor Horizon and Earnings Announcements |
| P0252 | 1-5.Earnings_Consensus | Corporate Earnings Calls and Analyst Beliefs |
| P0253 | 1-6.IdioVol_LowRisk | Beyond Volatility: Common Factors in Idiosyncratic Quantile Risks |
| P0254 | 1-6.IdioVol_LowRisk | ML Enhanced Multi-Factor Quantitative Trading |
| P0255 | 1-6.IdioVol_LowRisk | The Low-Volatility Anomaly and Adaptive Multi-Factor Model |
| P0256 | 1-6.IdioVol_LowRisk | Liquidity Costs, IdioVol and Expected Stock Returns |
| P0257 | 2-1.Regime_Dynamic | Dynamic Factor Allocation Leveraging Regime-Switching Signals |
| P0258 | 2-1.Regime_Dynamic | Tactical Asset Allocation with Macroeconomic Regime Detection |
| P0259 | 2-1.Regime_Dynamic | RegimeFolio: Regime Aware ML for Sectoral Portfolio |
| P0260 | 3.Risk_Portfolio | Dynamic Inclusion and Bounded Multi-Factor Tilts |
| P0261 | 3.Risk_Portfolio | Downside Risk Reduction Using Regime-Switching Signals |
| P0262 | 3.Risk_Portfolio | Factor and Idiosyncratic VAR Volatility Matrix Models |
