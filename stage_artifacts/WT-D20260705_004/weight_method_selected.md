# Weight Method Selected — WT-D20260705_004 (Optimizer Research)

**Selected**: `EW_top25` (BLIND best = alpha baseline A = point μ̂ top-25 equal-weight)
**selection_objective**: net_ir
**verdict on core question**: **uncertainty-AWARE does NOT beat uncertainty-BLIND** (thesis refuted at sizing/robust-optimization level).

## The decisive question
Does uncertainty-AWARE robust portfolio optimization (the textbook σ̂ consumption level — robust MVO, Bayesian shrinkage, resampling) beat uncertainty-BLIND optimization on realized PORT_t? Alpha already showed crude-selection FAIL (ΔPORT_t −0.40). This is the final test at the *legitimate* level.

## Answer: NO — clean, doubly-robust refutation

### Validity anchor (pre-flight, mandatory)
EW-of-top25 via contract `weighted_screen_bt` (NW lag-3) reproduces alpha baseline A **exactly**: full 0.9698 / recent2017 −0.7248 (alpha reported identical, 4dp). Benchmark forward-alignment + pipeline validated. No proxy hand-calc.

### Primary comparison (pre-registered single λ=5, κ=1, γ=λ)
| Design | BLIND best | AWARE best | ΔPORT_t (full) | ΔPORT_t (recent) |
|---|---|---|---|---|
| D1 sizing isolation (fixed top-25 names) | EW **0.9698** | ROBUST_BOX 0.4649 | **−0.505** | −0.284 |
| D1 sizing, common 172m (like-for-like) | EW **0.6254** | ROBUST_BOX 0.4649 | **−0.161** | −0.284 |
| D2 selection+sizing (pool top-40, 166m) | EW **0.3946** | BL_SHRINK 0.2371 | **−0.158** | −0.227 |

### Full method table (Design 1, fixed top-25 name set, full-period)
| method | group | full PORT_t | net IR | turnover | recent2017 |
|---|---|---|---|---|---|
| **EW** | BLIND | **0.9698** | 0.2794 | 12.28 | −0.7248 |
| HRP | BLIND | 0.5089 | 0.1609 | 13.76 | −0.7918 |
| ROBUST_BOX | AWARE | 0.4649 | 0.1387 | 15.70 | −1.0085 |
| RESAMPLED | AWARE | 0.3298 | 0.1022 | 13.59 | −0.5827 |
| ERC | BLIND | 0.3042 | 0.0948 | 13.21 | −0.9298 |
| MINVAR | BLIND | 0.2344 | 0.0738 | 15.10 | −1.1874 |
| BL_SHRINK | AWARE | 0.1341 | 0.0415 | 15.69 | −0.8937 |
| EST_PENALTY | AWARE | 0.0346 | 0.0108 | 15.22 | −1.0631 |
| MVO | BLIND | −0.0295 | −0.0092 | 16.21 | −1.2663 |

## Why EW wins (rationale)
1. **DeMiguel-Garlappi-Uppal (2009) 1/N**: for 25-name broad alpha, every risk/uncertainty-based sizing method (BLIND MVO/HRP/ERC/minvar AND AWARE robust-box/est-penalty/BL-shrink/resampled) **dilutes** realized net PORT_t vs equal-weight. Estimation error in Σ and μ̂ overwhelms the theoretical sizing gain.
2. **σ̂ carries no realized-PORT_t edge at the sizing level.** σ̂ is calibrated (+0.207 vs |realized active|, per alpha), yet consumed through 4 orthogonal textbook channels it fails to beat EW. The failure is the **IC→PORT_t transition wall itself**, orthogonal to the uncertainty dimension — the same wall that defeated crude selection.
3. Alpha's edge is in **name selection** (score_eff composite IC), not in sizing (Grinold breadth). Optimization cannot manufacture edge that isn't in the sizing dimension.

## Self-adversarial robustness (challenge_note CF-O1)
24-cell hyperparameter grid: AWARE grid-max = ROBUST_BOX(λ=2,κ=2) 0.6686 > blind-EW-covered 0.5825 by +0.086. This is **NOT** a real advantage: (a) argmax-of-24 = selection/overfit; (b) that cell's recent2017 = −1.0122 (reverses OOS); (c) never beats true baseline-A EW 0.9698; (d) the winning corner (heavy worst-case shrinkage) ≈ EW-mimic. Pre-registered comparison (no cherry-pick) stands.

## Hard constraints (deliverable EW top-25, final as_of 2026-04)
- n_names = 25 (≤ 25 ✓), Σw = 1.000000 ✓, max_w = 0.0400 (≤ 0.20 ✓), long-only ✓
- turnover_annual = 12.28 (within 1,100% cap ✓)
- schedule density = 196/196 = **1.0000** (≥ 0.95 ✓)
- metric_type = weighted_screen (estimated; forge authoritative). production_grade = FALSE.

## Infeasibility note (No Silent Override)
AWARE risk-based methods cover only 172/196 sig_dates (0.878 < 0.95) by construction (trailing-cov ≥24m PIT burn-in drops 2010-2011). Documented, not silently skipped — AWARE weights are A/B diagnostics; the **deliverable (EW) is fully dense (196/196)**. No constraint relaxation.

## Bottom line
Uncertainty-aware optimization is REJECTED at the robust-portfolio-optimization level, mirroring the alpha-stage crude-selection rejection. **The IC→PORT_t transition wall is robust to the uncertainty dimension at BOTH selection AND sizing.** capital-grade was off the table (0.97 ≪ 2.95); the clean scientific finding is that σ̂ neither helps nor is the missing ingredient. EW (1/N) is the un-improvable blind ceiling for 25-name broad KR alpha. Delivered weights = EW top-25 (the blind best) for forge to confirm authoritatively.
