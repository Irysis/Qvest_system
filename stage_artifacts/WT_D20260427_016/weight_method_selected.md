# Iter 31 Weight Method Selected — L1.5_TO3_CN10_CC20_CR40

## User Mandate
1701 튜닝 그리드서치 레벨로 진행 — PG2 레벨 X, 1701 strategy hyperparameter 단위.

## Grid Search 4-Dim (5×5×3×3 = 225 combinations)
- Dim 1 (λ Linear Tilt): {0.5, 0.8, 1.0, 1.2, 1.5}
- Dim 2 (TOphi turnover): {3, 5, 8, 12, 15}
- Dim 3 (Cash NORMAL%): {0%, 5%, 10%}
- Dim 4 (Cash (CAUTION%, CRISIS%)): {(10,20), (15,30), (20,40)}

Fixed: BULL cash 0%, max_w 0.20, max_names 20, long-only, Σw=1, liquidity 2e8, cost 15bps.

## Best Combo (selected)
- combo_id: L1.5_TO3_CN10_CC20_CR40
- λ = 1.5
- TOphi = 3
- Cash overlay = (BULL=0, NORMAL=10%, CAUTION=20%, CRISIS=40%)

## Performance
- SR_ann_net: **0.1230**
- CAGR_net: 0.21%
- MDD: -41.93%
- Turnover_ann: 202%
- CVaR_d_proxy: 3.0081%
- Harvey_t (pooled): 0.341
- DSR_post: 0.6327
- AX-001 v2: 2/4 PASS

## Hard Caps
- TO ≤ 600%: TRUE
- MDD ≤ 45%: TRUE
- CVaR_d ≤ 2.5%: FALSE
- All caps PASS: FALSE

## Selection Basis
TO+MDD pass only (CVaR breach disclosed) + max(SR) + tiebreakers

## Top 3 Combos
- [1] L1.5_TO3_CN10_CC20_CR40 — SR=0.1230 / CAGR=0.21% / MDD=-41.93% / TO=202% / AX001=2/4
- [2] L1.5_TO3_CN10_CC15_CR30 — SR=0.1227 / CAGR=0.20% / MDD=-42.06% / TO=200% / AX001=2/4
- [3] L1.5_TO3_CN10_CC10_CR20 — SR=0.1223 / CAGR=0.19% / MDD=-42.20% / TO=199% / AX001=2/4

## Iter 11 Baseline Reference
λ=1.0 TOphi=8 cash(0/5/15/30) — production STR_1701

## Lessons Applied
- L-220: vol-reduction quarterly avoidance
- L-224: cor=1.0 (≥0.95 strict) PASS
- L-226: ERC near-EW avoidance via LinTilt+TOphi
- L-237: BULL dominance — cash NORMAL grid {0,5,10}% explored
- L-238: sig_date direct calibration on 92-date Iter 18 panel

## References
- Bergstra-Bengio (2012) Random Search for Hyperparameter Optimization
- Iter 11 STR_1701 production baseline
- Barroso-Santa-Clara (2015) risk-managed momentum (cash overlay)

Generated: 2026-04-27T14:33:49+0900

