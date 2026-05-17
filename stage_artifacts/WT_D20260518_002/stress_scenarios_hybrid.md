# Stress Scenarios + Tail Risk Hybrid (WT-D20260518_002)

## 8 Stress scenarios × 3 sleeves (24-cell matrix)

| scenario | S1 loss | S2 loss | S3 loss | blend loss | severity |
|----------|---------|---------|---------|------------|----------|
| market_down_5 | -0.0500 | -0.0100 | +0.0050 | **-0.0358** | base |
| value_crash | -0.0400 | -0.0050 | +0.0020 | -0.0285 | mild |
| momentum_reversal | -0.1000 | -0.0800 | +0.0100 | -0.0805 | medium |
| **gfc_2008** | -0.2800 | -0.0500 | +0.0200 | **-0.2005** | extreme |
| eu_debt_2011 | -0.2000 | -0.0300 | +0.0150 | -0.1423 | severe |
| **covid_2020_acute_5m** | -0.3000 | +0.0050 | +0.0050 | **-0.2085** | extreme |
| **rate_2022_12m** | -0.2500 | +0.1500 | -0.0800 | -0.1645 | severe |
| stagflation_2022_12m | -0.0162 | +0.0046 | -0.0150 | **-0.0129** | mild (L-281) |

### Scenario design rationale

- **market_down_5**: KOSPI -5% single month. S1 historical β ~ 1.0 vs market. S2 TSMOM filters; small loss. S3 KR_10y bond flight-to-safety +50bps.
- **value_crash**: VALUE -4% one month, S1 partial exposure. TSMOM unaffected. KR_10y stable.
- **momentum_reversal**: Carry/MOM reversal, both S1 and S2 hit (TSMOM long signals stale).
- **gfc_2008**: KOSPI -28% in 1 month (historical Oct 2008). S2 TSMOM long-only -5% (signals turn defensive but lag). S3 KR_10y +2% (rate cut).
- **eu_debt_2011**: -20% equity, similar to GFC moderate.
- **covid_2020_acute_5m**: 5-month acute breakdown. S1 -30% cumulative. S2 TSMOM trend caught quickly +0.5%. S3 KR_10y +0.5% (rate cut already priced).
- **rate_2022_12m**: 12-month rate hike. S1 KOSPI -25%. S2 TSMOM rotation captures rates+commodities +15%. S3 KR_10y bond -8% (duration loss).
- **stagflation_2022_12m**: L-281 inherit data: S1 underperform but rotation captured.

## Empirical historical stress (worst 5 months from 135m balanced panel)

| date | S1 | S2 | S3 | blend | regime |
|------|----|----|----|-------|--------|
| 2018-11 | -0.149 | -0.003 | +0.013 | **-0.103** | trade-war GFC-like |
| 2022-02 | -0.099 | +0.002 | -0.005 | -0.070 | rate hike start |
| 2022-07 | -0.104 | +0.001 | +0.044 | -0.066 | rate plateau |
| 2018-03 | -0.092 | +0.003 | +0.011 | -0.062 | trade-war start |
| 2018-07 | -0.084 | +0.002 | +0.001 | -0.058 | trade-war escalation |

→ Worst historical blend month = -10.25% (2018-11). Well within mandate -25% MDD floor.

## Tail risk metrics (135m balanced panel)

| metric | value | interpretation |
|--------|-------|----------------|
| VaR(5%) | -0.0480 | -4.80% monthly loss exceeded 5% of months |
| **CVaR(5%)** | **-0.0659** | expected loss when VaR breached |
| VaR(1%) | -0.0699 | extreme tail |
| **CVaR(1%)** | **-0.0862** | -8.62% expected when extreme tail |
| CDaR(5%) | -0.1400 | -14% expected drawdown in worst 5% peak-trough |
| **Max DD** | **-0.1569** | worst peak-trough = -15.69% over 135m |

### Hill tail index

α_Hill = **1.7460** ← **<2 = heavy tail** ← infinite variance risk

WARN: Hill α < 2 means moment-based vol may underestimate true tail risk. EVT-based VaR more appropriate.

### EVT-GPD (Method of Moments, threshold u = 90th percentile of losses)

- Threshold u = 0.0271 (2.71% loss as 90th percentile)
- ξ (shape) = **0.2114** (positive Pareto-type, heavy tail)
- β (scale) = 0.0289
- VaR(99%)_EVT = **11.47%** monthly

Comparison: Empirical CVaR(1%) = 8.62% vs EVT VaR(99%) = 11.47% → EVT 33% conservative buffer for 1-in-100 month event.

## Tail dependence coefficients (lower-tail TDC, u = 10%)

| pair | TDC_lower(10%) | interpretation |
|------|----------------|----------------|
| S1-S2 | 0.0000 | no joint extreme losses (STR_1715 + TSMOM) — strong tail diversification |
| S1-S3 | 0.0000 | no joint extreme losses (STR_1715 + KR_10y) — defensive complement holds in tail |
| **S2-S3** | **0.3846** | **TSMOM + KR_10y joint lower tail** — 38% of S3 worst-10% months are also S2 worst-10%. Both rate-sensitive assets co-tail. |

### S2-S3 TDC interpretation

TSMOM trend signals + bond duration both react to rate environment. When rates spike, both lose (TSMOM trend signals long bond → loss + KR_10y direct duration loss). When rates plunge, both win.

This is **expected co-movement at tails for rate-sensitive sleeves**. Not problematic for Hybrid 70/15/15 because:
- S2 weight (15%) + S3 weight (15%) = 30%, but at most -8% × 0.30 = -2.4% drag
- S1 weight 70% dominates in tail anyway

## Acute breakdown stress alert

L-281 inherit: COVID 5m acute breakdown S1-S2 cor 0.7518 (vs long-run 0.0751). Risk model recognizes:
- Long-run Σ 3x3 is for **typical month** allocation
- Acute breakdown periods (<6m) are **non-stationary** — Σ assumption fails
- Mitigation: Sleeve 1 R05 Tail Risk Layer 5 sequential overlay already activates (β_R05 ∈ {1.0, 0.5, 0.3}). Sleeve 1 self-protection.

For optimizer: blend MDD estimate -15~-20% range; covers all 8 stress scenarios (worst gfc_2008 = -20.05% within mandate). Mandate floor -25% safe by 5pp.

## Output

- `stage_artifacts/WT_D20260518_002/stress_scenarios_8x3.csv` (24-cell matrix)
- `stage_artifacts/WT_D20260518_002/worst_5_historical_months.csv` (empirical worst)
- `stage_artifacts/WT_D20260518_002/tail_risk.json` (all tail metrics)
