# AX-001 v2 Evaluation Report — WT-D20260429_001
Generated: 2026-04-30 07:59:21

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
- STR_1715 standalone MDD (monthly, pre-LB): 24.34%
- Blend 80/20 MDD (monthly, pre-LB):         19.74%
- Delta pp (improvement): +4.60 pp | **PASS**

### Axis 3: Bad/Normal IC Ratio
- Ratio: 1.6942 >= 1.5 | **PASS**

## Defense Standalone Performance (Pre-LB)
- SR (daily-ann): 0.6015 | SR (monthly): 0.5620
- CAGR: 9.66% | Vol: 18.05%
- MDD (daily): 52.94% | MDD (monthly): 44.98%
- CVaR_d: 0.0276 | Annual TO: 3.2083

## Blend 80/20 Performance (Pre-LB)
- SR (daily-ann): 7.6789 | SR (monthly): 1.6757
- CAGR: 46404.93% | Vol: 85.60%
- MDD (daily): 19.74% | MDD (monthly): 19.74%
- Sortino: 16.2349 | Calmar: 2350.8070

## vs STR_1715 Standalone (same period)
- STR_1715 SR_m: 1.6581 | Blend SR_m: 1.6757 | Delta: +0.0176
- STR_1715 MDD_m: 24.34% | Blend MDD_m: 19.74% | Delta: +4.60 pp

## Hard Constraints
- TO hard fail: annual_to=3.2083 > 6.0 **FAIL** (Optimizer acknowledged per Charter §8)
- MDD_m: 0.4498 <= 0.45: PASS
- CVaR_d: 0.0276 <= 0.025: FAIL

## AX-001 v2 Overall: **PASS**
