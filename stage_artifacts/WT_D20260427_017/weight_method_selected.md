# Iter 32 Weight Method Selected — L1.5_TO3_CN10_CC15_CR30

## User Mandate (정확 인용)
PG2 = z-score(STR_1715) × 0.8 + z-score(STR_1656) × 0.2 → top-20 종목 → portfolio → monthly rebal walk-forward → 실측 SR

## Phase A: Z-Blend Construction (alpha_scores_combined.parquet)
- per Date z-score 정규화 (cross-section)
- score_blend = 0.8 × z(score_str1715) + 0.2 × z(score_str1656)
- Verified via blend_audit.json (mean cor recomputed-vs-stored = 1.000000)
- Mean top-20 overlap blend vs STR_1715-only: 79.0% (diversification 21.0% from STR_1656 leg)

## Phase B: Targeted Sweep (36 combos)
- λ Linear Tilt ∈ {1.0, 1.2, 1.5}
- TOphi turnover ∈ {3, 5, 8}
- Cash NORMAL ∈ {5%, 10%}
- Cash (CAUTION, CRISIS) ∈ {(15,30), (20,40)}

Fixed: BULL cash 0%, max_w 0.20, max_names 20, long-only, Σw=1, liquidity 2e8, cost 15bps.

## Best Combo
- combo_id: L1.5_TO3_CN10_CC15_CR30
- λ = 1.5
- TOphi = 3
- Cash overlay = (BULL=0, NORMAL=10%, CAUTION=15%, CRISIS=30%)

## Performance (real walk-forward, 181 sig_dates)
- **SR_ann_net: 0.6428**
- CAGR_net: 11.36%
- MDD: -46.77%
- Turnover_ann: 547%
- CVaR_d_proxy: 2.5102%
- Harvey_t (pooled): 2.496
- DSR_post: 0.9936
- AX-001 v2: 2/4 PASS

## Hard Caps
- TO ≤ 600%: TRUE
- MDD ≤ 45%: FALSE
- CVaR_d ≤ 2.5%: FALSE
- All caps PASS: FALSE

## Selection Basis
best-effort SR (caps may all be breached)

## Top 3 Combos
- [1] L1.5_TO3_CN10_CC15_CR30 — SR=0.6428 / CAGR=11.36% / MDD=-46.77% / TO=547% / AX001=2/4
- [2] L1.0_TO8_CN10_CC15_CR30 — SR=0.6412 / CAGR=11.30% / MDD=-46.39% / TO=524% / AX001=2/4
- [3] L1.5_TO5_CN10_CC15_CR30 — SR=0.6408 / CAGR=11.39% / MDD=-46.97% / TO=530% / AX001=2/4

## Comparison to Prior PG2 Estimates
| Iter | Method | SR | Notes |
|------|--------|----|----|
| Iter 28 | NAV-level proxy | 1.4625 | proxy only |
| Iter 29 | NAV-level proxy | 1.5243 | proxy only |
| Iter 30 | NAV-level proxy | 1.9222 | proxy only |
| **Iter 32** | **TRUE z-blend score-level** | **0.6428** | **REAL walk-forward** |

## Lessons Applied
- L-220: Vol-reduction quarterly avoidance
- L-224: Alpha inheritance score_blend (concentrated 80% on STR_1715)
- L-226: ERC near-EW avoidance via LinTilt+TOphi
- L-237: BULL dominance — cash NORMAL grid explored
- L-238: sig_date direct calibration on 181-date panel
- L-242: Metric verification mandate — REAL backtest (NOT NAV proxy)
- L-484: Score-level composite (z-blend foundation)

## References
- Markowitz (1952), Bergstra-Bengio (2012), Iter 31 STR_1701 production
- Barroso-Santa-Clara (2015) risk-managed momentum
- Gu-Kelly-Xiu (2020) RFS for STR_1656 leg

Generated: 2026-04-27T16:18:26+0900

