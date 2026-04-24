# Weight Method Selection — Pilot 7 (WT-D20260424_005)
# L-196 Verification: alpha-aware MVO vs MinVar

**Date**: 2026-04-24  
**Agent**: Optimizer (v6.1)  
**Task**: WT-D20260424_005 Pilot 7 — RAPC5 + CAPM Blume + L-195 Fix

---

## Selected Method: MinVar_BetaHard

**Selection objective**: net_ir (P3 hard, v6.1)  
**Selection criteria**: net_ir maximized among methods satisfying (beta_port ≤ 0.81) AND (n_names = 20)  
**net_ir = 12.1637** (MinVar_BetaHard)  
**beta_port = 0.7485** (target 0.75, gap -0.0015)  
**n_names = 20**

---

## L-196 Verdict: MINVAR_SUPERIOR

### Comparison Table

| Method | net_ir | n_names | beta | HHI | alpha_used | Beta_OK | N_OK |
|--------|--------|---------|------|-----|-----------|---------|------|
| **MinVar_BetaHard** | **12.1637** | **20** | **0.7485** | 0.0598 | zero_minvar | YES | YES |
| HRP_alpha_tilt | 10.2894 | 20 | 0.7967 | — | hrp_alpha_tilt | YES | YES |
| Kelly_fraction | 9.5720 | 20 | 0.9268 | — | kelly | NO | YES |
| EW_top_alpha | 9.0869 | 20 | 1.0226 | — | ew_top | NO | YES |
| CVaR_proxy | 8.3075 | 20 | 0.9322 | — | invvol_alpha | NO | YES |
| ERC | 6.4620 | 20 | 1.0799 | — | ignored | NO | YES |
| MVO_alpha lam2.0 | 6.7364 | **7** | 0.8271 | — | conf_scaled | NO | **FAIL** |
| MVO_alpha lam5.0 | 6.7616 | **7** | 0.8327 | — | conf_scaled | NO | **FAIL** |
| MVO_alpha lam1.0 | 6.6977 | **7** | 0.8241 | — | conf_scaled | NO | **FAIL** |
| MVO_alpha lam0.5 | 6.6979 | **7** | 0.8239 | — | conf_scaled | NO | **FAIL** |

### Critical Finding: MVO Sparsity Problem

All 4 alpha-aware MVO variants (lambda=0.5/1.0/2.0/5.0) produce **n_names=7** (sparse QP solution). This occurs because:

1. The covariance universe (top-40 by Risk agent) has alpha range [0.358, 0.507] — ALL positive, concentrated high.
2. The QP solver concentrates on 7 highest-alpha / lowest-variance names.
3. Even with beta penalty (gamma=1.0), the optimum is a 7-name concentrated portfolio.
4. 7 names fails the hard min_names=20 constraint → all MVO_alpha disqualified.

### Root Cause Analysis

**Alpha-Cluster Bias in Cov40 Subspace**:
- Full universe (N=1899): alpha_std = 0.1307, range [-0.51, +0.51] (L-195 fix successful)
- Cov40 subspace: alpha_std = 0.0469, range [0.358, 0.507], **15 unique values**, 26/40 at cap
- The Risk agent's top-40 universe selection selected on high alpha → **survivorship bias in optimization subspace**

This means the L-195 fix (confidence_floor=0, winsor 3σ) improved full-universe differentiation, but the optimization subspace inherited the same cluster structure from Risk's universe selection.

### L-196 Verdict Rationale

**MINVAR_SUPERIOR confirmed:**
- Best MVO_alpha net_ir = 6.7616 (lam5.0) — but this uses only 7 names (disqualified)
- If we ignore n_names constraint: MVO_alpha max net_ir = 6.76 vs MinVar = 12.16 → ratio = 0.556
- MinVar wins by 80% margin even ignoring constraint
- The alpha_std = 0.047 in cov40 is insufficient to override the variance minimization benefit
- **Conclusion**: In the P7 cov40 universe, MinVar_BetaHard is structurally superior — alpha signal is too compressed in the risk subspace to be useful for QP optimization

### Three L-196 Branches Assessment

1. **strategy_essence** (MVO > MinVar by >2%): NOT MET. MVO < MinVar by 44%.
2. **regime_lucky** (|MVO - MinVar| < 2%): NOT MET. Gap is 44%.
3. **minvar_superior** (MinVar clearly better): **CONFIRMED**. Ratio = 0.556.

**Implication**: The Pilot 6 lockbox CAGR 20.37% (2024-2026) is likely:
- (a) Regime-dependent: RISK_ON regime amplifies MinVar+low-beta advantage
- (b) Structural: MinVar+beta constraint is a valid strategy independent of alpha
- (c) AX-007 territory: Single-sleeve long-only top-20 → signal-portfolio translation breakdown

---

## Forge Handoff Instructions

**Primary instruction**: Report MinVar vs MVO side-by-side performance.  
**Critical test**: Isolate non-RISK_ON regime performance.

```
Regime breakdown required:
- RISK_ON periods (signal_date 2023-12-28 = RISK_ON): How much of Lockbox CAGR?  
- NEUTRAL + CAUTION + CRISIS periods: Does MinVar still work?
- If MinVar fails in non-RISK_ON → regime_lucky confirmed → L-196 final = regime_lucky
- If MinVar robust across regimes → strategy_essence (MinVar variant) → AX-007 exception
```

**AX-007 note**: If MinVar+beta 단독 strategy proves regime-robust, this may qualify as an AX-007 exception:  
"예외 4종 중 미해당 (single_sleeve_long_only_top20)" — the mechanism here is beta reduction, not alpha signal translation, so it may be classified differently from typical AX-007 cases.

---

## Portfolio Characteristics

| Metric | Value | Constraint | Status |
|--------|-------|-----------|--------|
| n_names | 20 | = 20 | PASS |
| sum(weights) | 1.0000 | = 1.0 | PASS |
| HHI | 0.0598 | ≤ 0.15 | PASS |
| max_weight | 0.0906 (A093190) | ≤ 0.15 | PASS |
| beta_port | 0.7485 | target 0.75 | PASS (gap -0.0015) |
| market_risk | ~39% | ≤ 40% Gate D | PASS |
| winsor_applied | 3σ | Pilot 7 | PASS |

---

## Method Shopping Log Summary

- **Candidates tried**: 10 (= limit)
- **R13 parallel**: TRUE (5 workers, 1.8 seconds)
- **selection_objective**: net_ir
- **Valid (beta+n_names)**: MinVar_BetaHard, HRP_alpha_tilt (beta=0.80, marginal)
- **Selected**: MinVar_BetaHard (net_ir=12.16 > HRP=10.29)
