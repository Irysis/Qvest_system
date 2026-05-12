#!/usr/bin/env python
"""
WT-D20260508_011 — Final alpha_package.json (post-Codex REJECT, v4 REVISE honest)

Final disposition: DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX
Reason: PIT C9 strict t-1 lag 적용 후 ML OOS IC 0.0037, t_NW 0.47, LO Q5 net SR 0.57 → graduation gates 4/9 FAIL strict.
WT_001과 동일한 empirical pattern — VRP signal cross-section conversion으로 anti-hedge 일부 완화하나 alpha 부족.

Honest contributions retained (academic/infrastructure):
- KRX 옵션 chain 16y direct (4023일 / 6.18M rows) 인프라
- VKOSPI 자체 재구축 (CBOE methodology) — KRX official 정합
- 4 학술 모형 정밀 구현 (BKM 2003 + Carr-Wu 2009 + BTZ 2009 + VKOSPI)
- Cross-section structural transformation (overlay → cs)
"""

import json, os
import pandas as pd
import numpy as np

ROOT = '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot'
OUT = f'{ROOT}/stage_artifacts/WT_D20260508_011'
WT = f'{ROOT}/qepm/mailbox/worktask/WT-D20260508_011'

# Load v4 validation
with open(f'{OUT}/alpha_validation_v4.json','r') as f:
    val = json.load(f)

with open(f'{OUT}/alpha_validation.json','r') as f:
    val_v3 = json.load(f)

# Load forward Q5 (latest sig_date 2025-12-30 — 2026 train data exhausted in test split)
fwd = pd.read_parquet(f'{OUT}/alpha_scores_forward.parquet')
print(f'Forward Q5: {len(fwd)} names')

alpha_vec = dict(zip(fwd['Ticker'], fwd['score_ml_composite']))
conf_vec = {t: 1.0 for t in alpha_vec}

# 4 model factor specs (academic contributions retained)
factor_specs = [
    {
        'factor_family': 'VRP_VolatilityRiskPremium_BKM_2003',
        'proxy': 'vrp_bkm_lag1 = (BKM 2003 RFS Q-measure variance) - RV_22d_annualized (lagged t-1)',
        'formula': 'BKM 2003 RFS Theorem 1 — V(t,τ) = ∫S^∞ [2(1-ln(K/S))/K²]·C(K) dK + ∫0^S [2(1+ln(S/K))/K²]·P(K) dK. RV_22d_annual = sum(daily_var)·252/22.',
        'lag_rule': 't-1 month-end (PIT C9 conservative)',
        'winsorization': 'ATM band ±33% F (Bondarenko 2014 JFE)',
        'neutralization': 'cross-section rank IC + sector retention 0.74',
        'economic_rationale': 'Risk-neutral BKM 2003 variance minus realized variance — VRP is investor risk-aversion premium for equity variance exposure (Bollerslev-Tauchen-Zhou 2009 RFS).',
        'weight_theta': 0.45,
        'references': ['Bakshi G., Kapadia N., Madan D. (2003) Stock Return Characteristics, Skew Laws, and the Differential Pricing of Individual Equity Options. RFS 16(1):101-143','Bondarenko O. (2014) Why Are Put Options So Expensive? JFE.','Carr P., Wu L. (2009) Variance Risk Premiums. RFS 22(3):1311-1341'],
        'source': 'krx_options_chain_direct_4023days_201001_to_202605',
        'selection_objective': 'cs_rank_ic',
        'diagnostics': {
            'monthly_n': 197,
            'series_mean': 0.0090,
            'series_std': 0.0259,
            'cor_with_carr_wu': 0.995,
            'cor_with_vkospi_recon': 0.804,
            'cor_with_atm_iv': 0.612,
            'pit_c9_lag_t1': True
        }
    },
    {
        'factor_family': 'VRP_VolatilityRiskPremium_CarrWu_2009',
        'proxy': 'vrp_cw_lag1 = MFIV (Carr-Wu 2009 model-free) - RV_22d',
        'formula': 'MFIV = (2/T)·e^(rT)·Σ(ΔK/K²)·Q(K) - (1/T)·(F/K_atm-1)². Carr-Wu 2009 RFS variance swap synthetic.',
        'lag_rule': 't-1 month-end (PIT C9 conservative)',
        'winsorization': 'ATM band ±33% F + close>0.02 + (OI>0|VOL>0)',
        'neutralization': 'cross-section rank',
        'economic_rationale': 'Variance swap synthetic — bias-free implied variance under no-arbitrage. Direct Q-measure variance (excludes higher moments).',
        'weight_theta': 0.25,
        'references': ['Carr P., Wu L. (2009) Variance Risk Premiums. RFS 22(3):1311-1341'],
        'source': 'krx_options_chain_direct',
        'selection_objective': 'cs_rank_ic',
        'diagnostics': {'monthly_n': 196, 'cor_with_bkm': 0.995}
    },
    {
        'factor_family': 'VRP_VolatilityRiskPremium_VKOSPI_recon',
        'proxy': 'vkospi_recon_lag1 — self-reconstructed via CBOE 1993/2003 methodology',
        'formula': 'VKOSPI = 100·sqrt((T1·σ²(T1)·w1 + T2·σ²(T2)·w2)·(365/30)). 30-day blend of front + next month MFIV.',
        'lag_rule': 't-1 month-end',
        'winsorization': 'as MFIV',
        'neutralization': 'cross-section index conditional',
        'economic_rationale': 'Self-reconstructed VKOSPI matches KRX official series — 2020-03 92, 2017 50, 2026-04 110. CBOE methodology validated KRX implementation reproducible.',
        'weight_theta': 0.20,
        'references': ['CBOE 1993 VIX Whitepaper','CBOE 2003 VIX Methodology','KRX Derivatives Market Disclosure'],
        'source': 'krx_options_chain_direct_self_reconstruction',
        'selection_objective': 'infrastructure_validation',
        'diagnostics': {'historical_consistency': 'aligns with KRX VKOSPI: 2020-03 92, 2017 50, 2026-04 110, validated 5 sample dates'}
    },
    {
        'factor_family': 'VRP_VolatilityRiskPremium_BTZ_HAR_baseline',
        'proxy': 'vrp_btz_proxy = bkm_var - RV_22d (HAR-RV component)',
        'formula': 'Bollerslev-Tauchen-Zhou 2009 RFS — VRP = E[RV] - implied variance. HAR-RV components (rv_d/rv_w/rv_m) computed for future production rolling fit.',
        'lag_rule': 't-1 month-end',
        'winsorization': 'as BKM',
        'neutralization': 'cross-section rank',
        'economic_rationale': 'BTZ 2009 RFS — VRP predicts forward equity returns negatively. In-sample baseline; rolling HAR fit deferred.',
        'weight_theta': 0.10,
        'references': ['Bollerslev T., Tauchen G., Zhou H. (2009) Expected Stock Returns and Variance Risk Premia. RFS 22(11):4463-4492'],
        'source': 'krx_options_chain_direct + KOSPI200 RV',
        'selection_objective': 'baseline_research',
        'diagnostics': {'note': 'In-sample baseline. Production should rolling fit (deferred follow-up).'}
    }
]

# Build final package
package = {
    'task_id': 'WT-D20260508_011',
    'wt_type': 'discovery',
    'as_of_date': '2026-05-08',
    'forecast_horizon': '1M',
    'pipeline_version': 'v4_revise_post_codex_final',
    'alpha_vector': alpha_vec,
    'confidence_vector': conf_vec,
    'signal_matrix_ref': 'stage_artifacts/WT_D20260508_011/alpha_scores.parquet',
    'signal_matrix_schema': {
        'columns': ['Date','Ticker','Sector','score_ml_composite','fwd_1m_ret','tv_20d_lag1','vrp_bkm','vol_60d_lag1','beta_252d_lag1','vkospi','bkm_skew_30d','mom_12_1_lag1','skew_252d_lag1','Usable_Date'],
        'n_sig_dates': val['oos_n_dates'],
        'n_unique_tickers': 718,
        'n_total_rows': val['oos_panel_size'],
        'date_range': '2014-01-29 to 2025-12-30',
        'pit_c14_compliant': 'Usable_Date == Date (signal computed at month-end with t-1 lag features)'
    },
    'factor_specs': factor_specs,
    'diagnostics_pit_strict': {
        'rank_ic_oos': val['ml_oos_metrics']['rank_ic_oos_mean'],
        'icir_oos': val['ml_oos_metrics']['icir_oos'],
        't_NW_oos_ic': val['ml_oos_metrics']['t_NW_oos_ic'],
        'lo_q5_net_sr': val['lo_q5_quarterly_rebal_metrics']['net_sr_annual'],
        'lo_q5_net_t_NW': val['lo_q5_quarterly_rebal_metrics']['t_NW_net'],
        'turnover_round_trip_annual': val['lo_q5_quarterly_rebal_metrics']['turnover_annual_round_trip'],
        'turnover_pass_600pct': val['lo_q5_quarterly_rebal_metrics']['turnover_pass_600pct'],
        'sub_stab_3periods': val['lo_q5_quarterly_rebal_metrics']['subperiod_stability'],
        'sub_stab_srs': val['lo_q5_quarterly_rebal_metrics']['subperiod_srs'],
        'dsr_lo_q5_net': val['dsr']['lo_q5_net'],
        'dsr_n_trials': val['dsr']['n_trials'],
        'orthogonality_cor_hybrid_proxy': val['orthogonality']['cor_lo_q5_hybrid_proxy'],
        'crisis_high_vkospi_cor_with_bm': val['crisis_anti_hedge_check']['high_vkospi_cor_with_bm']
    },
    'graduation_strict_check': val['graduation_strict_v4'],
    'graduation_pass_count': val['graduation_pass_count'],
    'graduation_total': val['graduation_total'],
    'graduation_overall_strict': val['graduation_overall_strict'],
    'method_log_inheritance_v3_to_v4': {
        'v3_results': {
            'lag': 'NO same-day VRP signals',
            'rebalance': 'monthly',
            'liquidity': '5e7 KRW',
            'oos_ic': 0.0255,
            't_NW_oos': 2.77,
            'lo_q5_net_sr': 0.825,
            'lo_q5_net_t_NW': 3.09,
            'turnover_ann': 7.6056,
            'turnover_pass': False
        },
        'v4_results_post_codex_revise': {
            'lag': 't-1 month-end (PIT C9 conservative)',
            'rebalance': 'quarterly',
            'liquidity': '2e8 KRW (production hard)',
            'oos_ic': val['ml_oos_metrics']['rank_ic_oos_mean'],
            't_NW_oos': val['ml_oos_metrics']['t_NW_oos_ic'],
            'lo_q5_net_sr': val['lo_q5_quarterly_rebal_metrics']['net_sr_annual'],
            'lo_q5_net_t_NW': val['lo_q5_quarterly_rebal_metrics']['t_NW_net'],
            'turnover_ann': val['lo_q5_quarterly_rebal_metrics']['turnover_annual_round_trip'],
            'turnover_pass': val['lo_q5_quarterly_rebal_metrics']['turnover_pass_600pct']
        },
        'comparison_diagnosis': 'v3 uses same-day VRP (technically PIT-justified at month-end since vrp can be computed from sig_date close options) + monthly rebal + 5e7 floor. v4 strict t-1 lag + quarterly rebal + 2e8 floor. v4 alpha measures collapse to ~zero (IC 0.025 → 0.004, t_NW 2.77 → 0.47). This indicates v3 alpha is partially same-month signal aliasing rather than true predictive content. Honest disposition: alpha discovery insufficient under PIT-strict regime.'
    },
    'codex_round': {
        'round_executed': True,
        'stance_received': 'REJECT',
        'veto_flag': False,
        'critical_concerns_count': 8,
        'severity_HIGH_count': 5,
        'severity_MEDIUM_count': 3,
        'weakest_assumption': 'The weakest assumption is that a single-date ML Q5 snapshot can be treated as a valid PIT alpha vector and graduated because LO Q5 portfolio metrics pass despite strict IC gates failing.',
        'response_summary': 'Agent largely agrees with Codex. v4 REVISE applied 6 fixes addressing C1 (full Date×Ticker panel), C2 (honest IC strict gate), C4 (t-1 lag), C5 (quarterly rebal turnover<600%), C6 (2e8 KRW liquidity), rationalization cleanup. Result: alpha discovery insufficient under PIT-strict.',
        'concern_disposition': {
            'C1_alpha_scores_full_panel': 'ACCEPT — alpha_scores.parquet rebuilt as Date × Ticker × score, 49578 rows × 144 sig_dates × 718 tickers, dates 2014-01-29 to 2025-12-30',
            'C2_strict_ic_gates': 'ACCEPT — IC strict gates re-evaluated honestly. v4 OOS IC 0.0037, ICIR 0.033, t_NW 0.47 — all FAIL strict. Relaxed pass narrative removed.',
            'C3_pit_c13_z_score_aligned': 'PARTIAL — score = -(VRP × vol) is economic-sign-aligned design (high VRP regime + high vol = penalty per BTZ 2009 / Bondarenko 2014). Z_Score_Aligned formal registration deferred (not factor DB integration). Not strict PIT-C13 sign-flip violation under economic interpretation.',
            'C4_pit_c9_lag': 'ACCEPT — VRP/VKOSPI/bkm_skew all lagged t-1 in v4. Same-day VRP value at sig_date is technically PIT-valid (computed from options closing prices at month-end, no future info), but conservative lag preferred for strict consistency with vol_60d_lag1 etc. v4 alpha collapse confirms most signal was same-month.',
            'C5_turnover_hard_mandate': 'ACCEPT — v3 monthly rebal turnover 7.6× > 600% hard FAIL. v4 quarterly rebal 5.48× round-trip PASS. Net SR 0.568 + DSR 0.615.',
            'C6_universe_2e8_floor': 'ACCEPT — production constraint 2e8 KRW applied (request.json 5e7 was research universe definition, but mandate hard floor is 2e8). v4 panel 62434 rows after 2e8 filter.',
            'C7_no_silent_override': 'ACCEPT — challenge_note.md being created in this finalization. 3-agent context (risk + optimizer) deferred per discovery WT scope (alpha-only).',
            'C8_academic_implementation': 'PARTIAL — BTZ HAR-RV in-sample baseline + VKOSPI sample-check honest caveats retained. References enriched with citations. Full date-by-date VKOSPI vs KRX official deferred follow-up.'
        },
        'rationalization_red_flags_self_check': 0,
        'verification_triangulation_ax_008': '1/3 — Codex REJECT. Architect + Forge follow-up not requested for discovery WT.',
        'agent_agree_with_codex_majority': True,
        'qlead_escalate_required': True,
        'qlead_escalate_trigger': 'HIGH severity concerns >= 5 (auto)',
        'challenge_note_path': 'qepm/mailbox/worktask/WT-D20260508_011/challenge_note_alpha-research.md'
    },
    'predictor_autocor_diagnosis': {
        'best_signal_s3_lag1_autocor': -0.062,
        's3_pass_threshold_lt_04': True,
        'method_log_lag1_autocor': {
            's1_skew_diff': 0.367,
            's2_vrp_innov_z_x_vol': -0.246,
            's3_vrp_vol': -0.062,
            's4_vrp_beta': -0.099,
            's5_skew_x_lowbeta': 0.441,
            's6_vkospi_innov_x_vol': 0.662,
            's9_vrp_x_neg_mom': 0.305
        }
    },
    'feature_leakage_check': {
        'method': 'Time-based 5-fold CV (no shuffle, sorted by Date). All features t-1 lagged including VRP/VKOSPI in v4. fwd_1m_ret strictly future-only.',
        'lag_0_ban': True,
        'pit_pass_v4': True,
        'wt_001_ml_xgboost_naive_long_bias_check': 'In v3, ML pred was 95.8% positive (WT_001 cycle). In v4 with t-1 lag, IC collapse to 0.004 — ML composite indistinguishable from noise. Honest.'
    },
    'crisis_anti_hedge_check': {
        'note': 'WT_001 cycle 1 found cor(r_vrp_overlay, r_AR) = +0.515 anti-hedge in CRISIS. v3 cross-section conversion seemed to resolve (-0.12). v4 PIT-strict t-1 lag re-introduces +0.12 anti-hedge in HIGH-VKOSPI regime.',
        'v3_high_vkospi_cor_bm': -0.12,
        'v4_high_vkospi_cor_bm': val['crisis_anti_hedge_check']['high_vkospi_cor_with_bm'],
        'anti_hedge_resolved_in_v4_strict': bool(val['crisis_anti_hedge_check']['anti_hedge_resolved'])
    },
    'orthogonality_vs_hybrid': val['orthogonality'],
    'caveats': [
        'PIT-strict v4 results: ML OOS IC 0.0037 + t_NW 0.47 + LO Q5 net SR 0.57 + t_NW 1.94 — graduation strict 5/9 PASS, 4 strict FAIL.',
        'v3 vs v4 comparison: same-day VRP usage (v3) inflates alpha measures by ~5x. Conservative lag is honest standard.',
        'BTZ 2009 HAR-RV: in-sample baseline = bkm_var - rv_22d. Production rolling fit deferred.',
        'VKOSPI 자체 재구축 sample-check (5 dates) only. Full date-by-date validation vs KRX official deferred.',
        'XGBoost single seed=42 + 5-fold CV. Multi-seed ensemble + alternative ML (LightGBM, RF, Lasso) not tested.',
        'Hybrid orthogonality cor measured against PROXY (70% KOSPI200 + 15% TSMOM proxy + 15% KR_Gov10Y duration). Real STR_1715 + TSMOM + KR_10y full backtest cor not measured.',
        'WT_001 inheritance — predictor lag-1 autocor 0.40 / ML feature leakage / CRISIS anti-hedge — v4 PIT-strict diagnosis: anti-hedge issue NOT fully resolved by structural cs transform alone (HIGH-VKOSPI cor +0.12 in v4).',
        '6M / 12M forecast horizon test deferred (request.json horizon = 1M).',
        'Sector neutralization (subtract sector mean signal) not applied in v4 — sector retention 0.74 from v3 single signal s3 only.'
    ],
    'empirical_disposition': {
        'status': 'DISCOVERY_FAIL_REJECTED_AGENT_AGREES_CODEX',
        'rationale': 'Post-Codex REJECT v4 REVISE: PIT-strict t-1 lag + quarterly rebal + 2e8 KRW + full Date×Ticker panel applied. Result: ML OOS IC 0.0037 + ICIR 0.033 + t_NW 0.47 — alpha measures collapse to noise. LO Q5 net SR 0.568 + t_NW 1.94 — borderline FAIL strict 3.0. graduation strict 5/9 PASS (4 fail: rank_ic, icir, t_NW oos, lo_q5_t_NW). Anti-hedge issue +0.12 cor in HIGH-VKOSPI regime — partial WT_001 inheritance. Codex REJECT structural critique 정확하며 v4 PIT-strict 결과 alpha discovery insufficient.',
        'graduation_strict_proper_check': val['graduation_strict_v4'],
        'graduation_overall': 'FAIL_strict (5/9 PASS, 4/9 FAIL)',
        'wt_001_pattern_reproduction': True,
        'discovery_outcome': 'TERMINATE_pivot_required'
    },
    'next_step_recommendations': {
        'primary_recommendation': 'TERMINATE current VRP cross-section approach. Honest empirical FAIL under PIT-strict. WT_001 + WT_011 = 2 cycles VRP signal failed in KR top-universe.',
        'alternative_paths': [
            {'name': '6M / 12M horizon', 'desc': 'VRP signals slow-moving — rerun with forecast_horizon=6M may boost t-stat. Risk: WT_001 cycle 2 1M weakness retained.', 'priority': 'MEDIUM_RESEARCH'},
            {'name': 'Sector-neutral score + Style residual', 'desc': 'Subtract sector + style (size/value) means before ranking. Sector retention 0.74 indicates moderate sector loading.', 'priority': 'MEDIUM_RESEARCH'},
            {'name': 'KR-specific VRP variant', 'desc': 'Korean retail-driven option flow features (e.g., put/call OI ratio, IV term structure changes) may have distinct alpha vs US-style VRP.', 'priority': 'MEDIUM_RESEARCH'},
            {'name': 'Pivot to alternative 4th orthogonal source', 'desc': 'WT_001 + WT_011 both VRP cycle FAIL. Recommend Defense low-vol multi-sleeve (AX-005 v1.2 EXCLUSION) or Commodity (Gold/Copper KR ETF) per WT_001 next_step.', 'priority': 'HIGH'}
        ],
        'follow_ups_infrastructure_retained': [
            'KRX 옵션 chain 16y direct cache (.cache/krx_options/ 4023 days, 6.18M rows) — valuable infra for future VRP / option-derivative research',
            'VKOSPI 자체 재구축 (CBOE methodology) — valid implementation, KRX official 정합 5 sample dates verified',
            'BKM 2003 + Carr-Wu 2009 + BTZ 2009 4 학술 모형 정밀 implementation available for future cross-asset research',
            'option_chain_summary.parquet + vkospi_reconstruction.parquet daily 4023 days saved for future use'
        ]
    },
    'rcpp_used': False,
    'parallel_exec': False,
    'method_shopping_log_ref': 'stage_artifacts/WT_D20260508_011/cs_ic_v2.json (8 specs full search)',
    'pipeline_stage': 'alpha_discovery_terminate_post_codex_v4_revise',
    'alpha_geometry': 'cross_section_long_only_q5_top20pct_quarterly_rebal',
    'per_name_alpha_matrix_required': True,
    'per_name_alpha_matrix_provided': True,
    'forward_q5_n_names': len(fwd),
    'forward_q5_at_sig_date': str(fwd['Date'].iloc[0]) if 'Date' in fwd.columns else '2025-12-30',
    'hypothesis_source': 'user_defined',
    'hypothesis_title': 'KOSPI200 option chain direct VRP precise — discovery FAIL post PIT-strict v4 (post-Codex REJECT)',
    'v_history_summary': {
        'v1': 'monthly rebalance + same-day VRP merge + 5e7 KRW universe — IC 0.025, t_NW 2.77, LS SR 1.06, Q5 net SR 0.825 (relaxed)',
        'v2_self_audit': 'composite framework signal dilution risk identified (WT_004/006 lesson) — single signal s3 separately measured, IC -0.037 t_NW -3.02 LS SR -0.13 graduation FAIL',
        'v3_finalize': 'ML XGBoost 11-feature composite measured + relaxed graduation narrative (rank_ic strict FAIL but LO Q5 portfolio measures PASS) — submitted for Codex',
        'v4_revise_post_codex': 'PIT-C9 strict t-1 lag + quarterly rebal turnover<600% + 2e8 KRW + full Date×Ticker panel + rationalization cleanup. Result: IC 0.004 + t_NW 0.47 + LO Q5 net SR 0.57 + t_NW 1.94 — graduation strict 5/9 PASS, 4/9 FAIL. Honest discovery FAIL.'
    }
}

# Save final
with open(f'{WT}/alpha_package.json','w') as f:
    json.dump(package, f, indent=2, default=str, ensure_ascii=False)

print(f'\nSaved alpha_package.json (final post-Codex)')
print(f'Status: {package["empirical_disposition"]["status"]}')
print(f'Graduation: {package["graduation_pass_count"]}/{package["graduation_total"]} = {"PASS" if package["graduation_overall_strict"] else "FAIL"}')
print(f'Codex stance: {package["codex_round"]["stance_received"]}')
