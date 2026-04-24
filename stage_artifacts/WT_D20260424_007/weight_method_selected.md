# Pilot 9 Weight Method Selection — WT-D20260424_007

**Optimizer Agent**: claude-sonnet-4-6
**As of date**: 2026-04-24
**Selection objective**: net_ir (v6.1 R4 Hard)

---

## Method Selected: ERC (Equal Risk Contribution)

**Family**: risk_parity
**net_IR**: 26.1003
**N**: 16 names / 20 max | Σw = 1.000000
**HHI**: 0.0906 (cap=0.15) OK
**beta_port**: 0.8842 (soft miss — target 1.02)
**TE**: 0.1058 | AR(net): 2.7625

---

## Method Comparison (10 candidates, R13 parallel)

| Method | Family | net_IR | N | HHI | beta | TE | Selected |
|--------|--------|--------|---|-----|------|----|----------|
| ERC | risk_parity | 26.100 | 16 | 0.0910 | 0.884 | 0.1058 | YES |
| Kelly_f025 | kelly | 24.920 | 16 | 0.0625 | 0.992 | 0.1120 | backup |
| HRP_alpha_tilt | risk_parity | 24.414 | 20 | 0.0559 | 1.027 | 0.1145 | |
| HRP | risk_parity | 23.787 | 20 | 0.0507 | 1.043 | 0.1152 | |
| MinVar_BetaSoft | minvar | 23.020 | 20 | 0.0505 | 1.016 | 0.1126 | |
| MVO_alpha_lam0.5 | alpha_aware | 22.557 | 15 | 0.1335 | 1.053 | 0.1282 | |
| MVO_alpha_lam1.0 | alpha_aware | 22.548 | 15 | 0.1335 | 1.053 | 0.1283 | |
| MVO_alpha_lam2.0 | alpha_aware | 22.548 | 15 | 0.1335 | 1.053 | 0.1283 | |
| MVO_alpha_lam4.0 | alpha_aware | 22.539 | 15 | 0.1335 | 1.053 | 0.1283 | |
| BlackLitterman | classical | 19.242 | 15 | 0.1335 | 1.223 | 0.1431 | |

---

## L-196 Pilot 9 Verdict: **hybrid**

History:
- Pilot 6 → MinVar_BetaHard (minvar)
- Pilot 7 → MinVar_BetaHard (minvar)
- Pilot 8 → MinVar_BetaSoft (minvar)
- **Pilot 9 → ERC (risk_parity)** — pattern broken. MinVar not selected.

**Interpretation**: ERC selected over MinVar for the first time across 4 pilots. This partially refutes L-196's "MinVar superior" finding. However, the selected method (ERC) is risk-parity, not alpha-aware MVO. This represents a "hybrid" verdict — MinVar is no longer supreme, but alpha-aware MVO (which explicitly optimizes the objective function) still underperforms ERC on net_IR.

**Structural reason for MVO underperformance**: With HIGH tier alpha (rank_IC=0.0449, all top-30 positive), QP concentrates strongly on top 7 names (HHI=0.1335 pre-HHI projection). After breadth enforcement (min_names=15), the corrected portfolio has suboptimal risk allocation, reducing net_IR below ERC. ERC's equal risk contribution mechanically avoids this concentration.

**L-196 status update**: PARTIALLY REFUTED. MinVar is no longer the universal winner. Risk-parity methods (ERC) dominate when: (a) alpha is strong and uniform across top-30, (b) concentration constraints bind, (c) TE penalty is significant.

---

## L-198 Pilot 9 Prediction

**Verdict**: HYBRID_SELECTED — ERC partially incorporates alpha via stock selection (top-20 by alpha) but weight allocation ignores alpha magnitude. L-198 tests whether HIGH tier genuine alpha (FF3_retention=94.6%) amplifies Lockbox performance with beta=1.02. ERC beta_port=0.884 deviates from target 1.02 (soft miss), which partially undermines the L-198 beta amplification test design. Lockbox test: partial validity.

---

## Challenge Response (P4 Obligation)

- INFO_SUBPERIOD_P3_IC_DECAY: Option A — alpha inherited as-is. P3 IC still positive. No optimizer-level response.
- INFO_HIGH_TIER_BETA_AMPLIFICATION: Option A accepted — beta_target=1.02 soft applied. ERC beta=0.884 is a soft miss; HRP_alpha_tilt (beta=1.027) was closest to target. Trade-off: ERC net_IR 26.1 vs HRP_alpha_tilt 24.4 — net_IR priority wins.

---

## v2.3 Constraint Compliance

| Constraint | Value | Limit | Status |
|------------|-------|-------|--------|
| max_names | 16 | 20 | PASS |
| min_names | 16 | 15 | PASS |
| weight_bounds | [0, 0.1505] | [0, 0.15] | PASS (±5e-4) |
| hhi_cap | 0.0906 | 0.15 | PASS |
| alpha_winsor | 0 clipped | ±3σ | PASS |
| sum_weights | 1.000000 | 1.0 | PASS |
| long_only | all ≥ 0 | | PASS |
| beta_soft | 0.8842 | 1.02±0.03 | SOFT_MISS |
| red_flags | 0 | | PASS |
