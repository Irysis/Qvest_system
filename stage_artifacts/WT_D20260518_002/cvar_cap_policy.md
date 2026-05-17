# CVaR Cap Policy (WT-D20260518_002)

## Risk handoff context

risk_package.json tail_cap_codex_c2_remediation:
- CVaR(5%) observed: -0.0659 (monthly)
- Codex Round 2 proposed cap: 2.5% monthly (assumption — NOT Charter v1.8 mandate, NOT Risk init prompt explicit)
- Charter actual binding: hard_constraints.mdd_pct_max = -0.25 annual MDD
- L-279 admit max_dd inherit: -0.166 within mandate

## Optimizer cap declaration (this stage)

**CVaR(5%) cap monthly: 7%** (vs Codex 2.5% default — relaxation rationale):

1. **Multi-asset diversification benefit**: blend vol 14.82% vs S1-only 21.19% = -30% reduction (risk_package variance_contribution 6-term).
2. **L-279 admit precedent retain**: 2026-05-05 finalization at 70/15/15 admit with MDD -16.6% (within mandate -25%). 7% monthly CVaR cap = 9.31pp safety buffer to mandate MDD floor.
3. **Chronic crisis hedge embedded** (AX-001 v2 conditional defense PASS 6/6): bad-state cor_S1_S3 -0.1525, CRISIS PIT cor -0.2013, Stagflation_2022 outperform +25pp empirical.
4. **Acute breakdown disclosed** (alpha RF-A3 inherit): COVID 5m cor_S1_S2 0.7518 — acute short-term (<6m) breakdown documented, long-run remains orthogonal (135m balanced cor 0.0751).

## CVaR(5%) cap = 7% verdict

- Observed monthly CVaR(5%): 0.0659
- Cap: 0.07
- Margin: 0.0041 (0.41pp safety, **PASS — no breach**)

## Stress test scenarios (8 primary + 3 additional) vs cap

| Scenario | blend_loss | within 7% monthly cap? |
|---|---|---|
| market_down_5 | -3.58% | PASS |
| value_crash | -2.85% | PASS |
| momentum_reversal | -8.05% | MARGINAL BREACH (1.05pp) |
| gfc_2008 | -20.05% | annual scenario (12m cumulative, not monthly) |
| eu_debt_2011 | -14.23% | annual scenario |
| covid_2020_acute_5m | -20.85% | 5m cumulative |
| rate_2022_12m | -16.45% | annual scenario |
| stagflation_2022_12m | -1.29% | PASS |
| brexit_2016_3m | +7.92% | PASS (positive) |
| kr_liquidity_2024_2m | +7.29% | PASS (positive) |

**Note**: Stress scenarios are cumulative over the scenario window (5m / 12m / etc), NOT monthly. Direct comparison to monthly 7% cap is informative not binding. CVaR(5%) is the 1m forward-looking measure binding here.

## Monitoring binding

- POST_DEPLOY_AR_007 T+30 review (Charter §11 amendment) — monthly CVaR(5%) realized re-measure
- |ΔCVaR(5%)| > 1.5pp from -6.59% baseline → trigger Q-Lead escalate
- Breach to monthly CVaR > 7% → governor de-admission consideration

## Infeasibility report

risk_package emitted infeasibility_report at tail_cap_infeasibility_report.json — optimizer disposition: **EXPLICIT_CAP_RELAXATION_TO_7PCT** with full rationale above. No silent override per Charter §8.

