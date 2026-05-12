# Weight Method Selected — WT-D20260511_002

## Decision: **01_static_baseline_retain** (50/25/20/5)

**Date**: 2026-05-11
**Agent**: optimizer-research
**Method selection objective**: `net_ir_strict_improve_DM_test_p_lt_0p05`
**Selected variant**: S4 v2 4-sleeve admit (paradigm-free DRO Wasserstein convergence point, 도훈 mandate 2026-05-09)

## Rationale

도훈 mandate 2026-05-11 KST의 **"레짐이나 해당시점 리스크기반 동적비중조절 방법론 리서치"** 에 대한 정직 답변:

1. **16 candidate dynamic method** 자율 비교 (Risk Agent finding 활용 ⭐ CRISIS state str1715-tsmom +0.234 sig 기반 9 regime variants + Classical MVO/HRP/ERC + Robust DRO + Bayesian BL + Kelly + CVaR LP + Vol target):

   | Method | SR_net_256m | MDD_256m | Turnover_yr | DM_p_vs_baseline | Selected |
   |---|---|---|---|---|---|
   | **01_static_baseline** | **1.8603** | -0.1523 | 0.0 | baseline | ✅ |
   | 02_static_ew4 | 1.9333 | -0.0670 | 0.0 | 0.1773 | (alpha 침범 REJECT) |
   | 03_mvo_rolling | 1.8415 | -0.1523 | 0.0716 | 0.7498 | (NS, MVO down) |
   | 07_regime_crisis_mild | 1.8924 | -0.1491 | 0.0941 | 0.3669 | 3rd |
   | **09_regime_crisis_aggr** | 1.9090 | -0.1451 | 0.1882 | 0.5132 | **2nd** |
   | 13_dro_wasserstein | 1.3853 (135m) | - | 0.1182 | **0.0428** ⚠️ | (static DOMINATES) |
   | 18_regime_crisis_tsmom_down | 1.8895 | -0.1463 | 0.1882 | 0.5798 | NS |

2. **Strict improve criterion (3 criteria)**:
   - ΔSR DM test t > 2 (Memmel 2003 closed form, Diebold-Mariano)
   - Δ MDD ≤ 2pp
   - Turnover ≤ 30%/yr

3. **모든 dynamic candidate가 DM test p > 0.05 미달**. 가장 가까운 후보 02_static_ew4 (p=0.18)도 stat sig 미달 + alpha thesis 침범 reject. 09_regime_crisis_aggr이 가장 sensible candidate but p=0.51 명백 NS.

4. **R12 No Silent Override 정합**: dynamic adoption은 조용히 (silently) 진행 불가 → **static retain** 명시적 결정.

5. **Risk Agent finding_9 정확 입증**: "Dynamic improvement must overcome regime classification noise" — 정확. paradigm-free static convergence robust.

## 2nd Candidate: 09_regime_crisis_aggr (Future watch)

CRISIS regime aggressive shift:
- Base: `(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)`
- CRISIS shift: `(str1715=-0.20, kr10y=+0.10, tsmom=+0.05, cash=+0.05)`
- CRISIS weights: `(str1715=0.30, kr10y=0.30, tsmom=0.30, cash=0.10)`

**측정값**:
- 256m SR_net 1.9090 (vs baseline 1.8603, ΔSR +0.0487)
- 256m MDD -14.51% (vs -15.23%, -0.72pp 개선)
- CVaR_95 monthly 5.07% (vs 5.51%, -0.44pp 개선)
- GFC 2008 sub-period cum +10.50% (vs +6.95%, +3.55pp 명확 우월)
- Turnover 18.82%/yr

**채택 보류 사유**: DM t=0.654 p=0.5132 NS. bootstrap 95% CI [-0.22, -0.07]에 baseline MDD -0.1523 포함. statistically indistinguishable.

**Future research path**: sample 확장 (256m + future) → DM power 증가 시 stat sig 도달 여부 재평가.

## Codex Critic Round (REJECT → REVISED)

**stance: REJECT** + 8 concern. 모두 challenge_note.md에 ACCEPT/PARTIAL/REBUTTAL 분류 후 final package 반영:

- C1 (CRITICAL) sleeve vs ticker level: PARTIAL ACCEPT — constraint_convention_layer 명시
- C2 (HIGH) method shopping ≤10 cap: ACCEPT — top10 + supplementary 분리
- C3 (HIGH) CVaR cap waiver: ACCEPT — formal infeasibility_report 발행
- C4 (HIGH) walk-forward schema: PARTIAL REBUTTAL — forge_handoff path 명시
- C5 (HIGH) cost understated: ACCEPT — sleeve_internal_proxy 추가
- C6 (HIGH) covariance cond: ACCEPT — solver-safe primary 3-sleeve cond=21.7
- C7 (MEDIUM) RF-R1 dominance: REBUTTAL — sleeve-aggregate convention (López de Prado 2016 + He-Litterman 1999) + L-280/286/287
- C8 (HIGH) alpha cert: PARTIAL ACCEPT — 도훈 C7 sizing_only inherit path

## 핵심 발견

**Paradigm-free static convergence finding의 정량 확증** (L-286 reconfirmation):

도훈 mandate user-fixed 50/25/20/5 allocation은 사후 정당화가 아니라 256m walk-forward + 16 dynamic 비교에서 **모든 dynamic alternative 대비 statistically indistinguishable or DOMINANT** 결과. 특히 13_dro_wasserstein (Esfahani-Kuhn 2018) 자체가 static baseline에 statistical dominated (DM p=0.0428) — DRO 자체가 robust point estimate임을 입증.

**Risk Agent finding_9 직접 인용**:
> "Dynamic weight rule research design guidance to Optimizer: (a) CRISIS regime confirmed only state with statistically significant cor shift. (b) Other regime cors NS — small sample issue. (c) Consider 2-state simplification. (d) TDC_lower=0 for str1715-kr10y/tsmom = lower tail diversification preserved → static admit (50/25/20/5) is paradigm-free defensible baseline. **Dynamic improvement must overcome regime classification noise.**"

→ Risk Agent guidance 정확. dynamic improvement 부재 = method/sample limitation, not alpha/risk error.

## Next Stage

- **Forge agent**: 본 optimization_package.json + weights.csv (256 rows sleeve-level) + 4 sleeve alpha source inherit → ticker-level expansion + 256m + OOS backtest
- **Judge agent**: forge backtest 결과 PASS gate 0~18 + PIT C1-C15 audit
- **Governor agent**: PG2 admit 후보 진입 시 book_state.json update (단, 본 결과는 도훈 mandate의 user-fixed S4 v2 admit confirmation — 새로운 admit 아님)

## Lineage

- Input: alpha_package.json (S4 v2 4-sleeve inherit) + risk_package.json (Sample Σ + MRS 4-state + bootstrap CI + tail risk + TDC)
- Output: optimization_package.json + weights.csv + method_comparison_v2/v3 + sensitivity_bootstrap + crisis_subperiods + challenge_note (optimizer section) + codex_critic_response

## References

- Memmel C. (2003) "Performance Hypothesis Testing with the Sharpe Ratio" — DM test for SR diff
- Diebold-Mariano (1995) "Comparing Predictive Accuracy" — DM test framework
- Esfahani-Kuhn (2018) "Data-driven Distributionally Robust Optimization Using the Wasserstein Metric" — DRO Wasserstein
- López de Prado (2016) "Building Diversified Portfolios that Outperform Out of Sample" — HRP
- Maillard-Roncalli-Teïletche (2010) "The Properties of Equally Weighted Risk Contribution Portfolios" — ERC
- Moskowitz-Ooi-Pedersen (2012) "Time Series Momentum" — TSMOM
- Rockafellar-Uryasev (2000) "Optimization of Conditional Value-at-Risk" — CVaR LP
- He-Litterman (1999) "The Intuition Behind Black-Litterman Model Portfolios" — Black-Litterman dynamic
- Ang-Bekaert (2002) "Regime Switches in Interest Rates" — Markov-RS MVO
- Hamilton (1989) "A New Approach to the Economic Analysis of Nonstationary Time Series" — HMM regime
- Adams-MacKay (2007) "Bayesian Online Changepoint Detection" — BOCPD (이미 M4 적용)
- Kritzman-Page-Turkington (2011) FAJ "Regime Shifts: Implications for Dynamic Strategies" — AR threshold (이미 1715 H1 sleeve 내부 적용)

## L-code references

- L-280 Path C single direct hybrid (cross-asset orthogonal source 결합 시너지)
- L-281 Cross-Asset TSMOM KR empirical 입증 (cor 0.077)
- L-282 PerformanceAnalytics convention reconcile (+0.19 SR drift)
- L-285 S4 v2 alpha-updated admit + 1715 H1 정식 명명
- L-286 Walk-forward Dynamic Convergence Finding (DRO Wasserstein ε=0.1 → 50/30/20/0 도훈 framing 정확 수렴, 사후 정당화 X 정량 수렴점) ⭐
- L-287 60/40 paradigm retract → orthogonal 4-sleeve 진화
- L-288 TSMOM A148070 overlap 해소 single asset cap 0.20 정합
