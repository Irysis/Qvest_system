# Weight Method Selection — WT-D20260423_001

## Selected Method
**MVO_lam5_psi0.3** (Confidence-aware MVO, lambda=5.0, psi=0.3)

## Selection Rationale
- selection_objective = `net_ir` (R4 P3 HARD compliant)
- MVO_lam5_psi0.3 achieves highest net_IR (z-score units)=46.9787
- IC-scaled net_IR (annual) = 4.188 [AR_ann=101.8% / TE_ann=24.2%]
- lambda=5.0: higher risk-aversion → tighter portfolio, better TE control for defense quality
- psi=0.3: FU penalty discounts low-confidence alpha positions (R4-A)
- alpha_tilde = confidence × raw_alpha applied before QP solve

## v6.1 Compliance
| Rule | Status |
|------|--------|
| R4-A confidence_vector | APPLIED |
| R4 selection_objective = net_ir | PASS |
| R2-C candidates_tried <= 10 | PASS (5/10) |
| R12 No Silent Override | PASS (infeasibility_report = null) |

## Method Comparison
| Method | AR | TE | IR | net_IR | N |
|--------|----|----|----|----|---|
| MVO_lam2_psi0.3 | 3.2866 | 0.0713 | 46.108 | 46.087 | 6 |
| MVO_lam1_psi0.5 | 3.2866 | 0.0713 | 46.100 | 46.079 | 6 |
| MVO_lam5_psi0.3 ** | 3.2894 | 0.0700 | 47.000 | 46.979 | 6 |
| HRP | -0.4551 | 0.0481 | -9.460 | -9.491 | 20 |
| ERC | -1.2978 | 0.0457 | -28.374 | -28.406 | 20 |

## Tradeoffs
- max_names=20 hard cap: concentrates into highest net_IR names
- TDC Q07-Q32=0.62 MEDIUM-HIGH: optimizer naturally diversifies via Sigma structure
- FU penalty avoids over-concentration in low-confidence tickers
- Discovery WT AX-005 exception: Deployment WT requires multi-sleeve restructuring

Generated: 2026-04-23 15:53:10.207983
