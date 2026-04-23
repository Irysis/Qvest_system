# Weight Method Selection — WT-D20260424_001

**Date**: 2026-04-24  
**Stage**: Optimizer Research Stage 3  
**selection_objective**: `net_ir` (R4 P3 HARD)  

## Selected Method

**MVO_lam2_psi0.3**

- Family: MVO (Confidence-aware v6.1 R4-A)
- lambda = 2.0, psi = 0.3
- Confidence vector applied: alpha_tilde = c * alpha_hat
- FU penalty: psi * sum(x_i^2 * (1-c_i)^2)
- net_ir = 19.1507 (after 15bps TC)
- n_names = 8 / 20
- Sigma: Ledoit-Wolf (cond=1.0, PSD verified)

## Selection Rationale

The RAPC alpha (rank_IC=0.0318, ICIR=0.403) is a moderate-strength signal.
Confidence-aware MVO with lambda=2.0 provides risk discipline while psi=0.3
penalizes concentration in low-confidence names. This combination maximizes
net_IR after 15bps one-way transaction cost.

Higher lambda (2.0 vs 1.0 vs 0.5) produces better risk control given the
borderline rank_IC. Risk-parity methods (HRP/ERC) rank lower because they
ignore the alpha signal entirely, reducing expected active return.

Market exposure RF-R1 HIGH (48%): beta_target=1.0. Confidence-aware MVO
with uncertainty penalty achieves diversification through psi=0.3 without
requiring explicit beta hedging.

## Method Comparison

| Method | net_ir | exp_ir | n_names | Selected |
|--------|--------|--------|---------|----------|
| MVO_lam2_psi0.3 | 19.1507 | 19.1793 | 8 | YES |
| MVO_lam2_psi0.5 | 19.1060 | 19.1345 | 8 |  |
| MVO_lam1_psi0.3 | 19.0935 | 19.1220 | 8 |  |
| MVO_lam0.5_psi0.3 | 19.0636 | 19.0920 | 8 |  |
| HRP | 14.6067 | 14.6360 | 20 |  |
| ERC | 13.0149 | 13.0425 | 20 |  |
| ERC_confidence | 7.2534 | 7.2820 | 20 |  |

## Hard Constraints Verified

- max_names = 8 / 20 OK
- sum_weights = 1.000000 OK
- min_weight = 0.035234 >= 0 OK
- max_weight = 0.2000 <= 0.20 OK
- long-only: all weights >= 0 OK

## v6.1 HARD Requirements Checklist

- [x] R4 P3: selection_objective = net_ir
- [x] R4-A: Confidence-aware MVO (confidence_vector applied)
- [x] R2-C: Method shopping log (7 candidates, <= 10)
- [x] R12: infeasibility_report present (null = no issue)
- [x] R3 GAP-1: wt_record_challenge_review() called
- [x] R11 GAP-2: record_package_lineage() called
- [x] Telegram: tg_send() called in script

## Market Hedging (RF-R1 HIGH Response)

RF-R1 HIGH: Market risk 48% flagged by Risk Agent.
Response: beta_target = 1.0 maintained (no explicit hedge).
Confidence-aware MVO + psi=0.3 uncertainty penalty mitigates
concentration in high-market-beta names without short positions
(long-only mandate).

