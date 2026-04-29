# AX-001 v2 Evaluation Report — WT-D20260429_001
Generated: 2026-04-30 08:52:54

## Strategy
Regime-Conditional Low IVOL Defense (D47_CVaR_5pct + D01_IdioVol + D04_Downside_Beta)
HRP weights, monthly rebalance, 20 names, 15bps cost

## Evaluation Framework: AX-001 v2 3-Axis
Defense strategies evaluated on conditional criteria, NOT full-period SR.
### Axis 1: Crisis Alpha
- GFC_2008 IC:      0.1610
- TradeWar_2020 IC: 0.0349
- RateHike_2022 IC: 0.1328
- n_pass: 3/3 | Gate: >=2 | **PASS**

### Axis 2: Core MDD Complement (Forge Realized)
- STR_1715 standalone MDD (monthly, pre-LB): 0.3556
- Blend 80/20 MDD (monthly, pre-LB):         0.3686
- Delta pp (improvement): -0.0130 | **FAIL**

### Axis 3: Bad/Normal IC Ratio
- Ratio: 1.6942 >= 1.5 | **PASS**

## Defense Standalone Performance (Pre-LB)
- SR (daily-ann): 0.6015 | SR (monthly): 0.5620
- CAGR: 9.66% | Vol: 18.05%
- MDD (daily): 52.94% | MDD (monthly): 44.98%
- CVaR_d: 0.0276 | Annual TO: 3.2083

## Blend 80/20 Performance (Pre-LB — monthly grid v2)
- SR (monthly-ann): 1.3281 | n_monthly_obs: 240
- CAGR: 0.2942 | Vol_m_ann: 0.2130
- MDD (monthly): 0.3686 | frequency_mislabel_fix: v1_daily252→v2_monthly12
- Sortino: 2.5609 | Calmar: 0.7983

## vs STR_1715 Standalone (same monthly grid)
- STR_1715 SR_m: 1.4359 | Blend SR_m: 1.3281 | Delta: -0.1079
- STR_1715 MDD_m: 0.3556 | Blend MDD_m: 0.3686 | Delta: -0.0130 pp

## Hard Constraints
- TO hard fail: annual_to=3.2083 > 6.0 **FAIL** (Optimizer acknowledged per Charter §8)
- MDD_m: 0.4498 <= 0.45: PASS
- CVaR_d: 0.0276 <= 0.025: FAIL

## AX-001 v2 Overall: **FAIL**
