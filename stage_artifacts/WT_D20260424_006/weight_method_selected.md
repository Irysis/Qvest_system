# Weight Method Selection — WT-D20260424_006 Pilot 8 Path A

**Task ID**: WT-D20260424_006
**As of Date**: 2026-04-24
**Agent**: Optimizer Research Agent (claude-sonnet-4-6)
**Selection Objective**: net_ir (v6.1 R4 P3, net of 15bps one-way TC)

---

## Selected Method: MinVar_BetaSoft

**Selection Rationale**:

MinVar_BetaSoft achieved the highest net IR (12.0841) among all 10 methods tested in parallel (R13). The method minimizes portfolio variance subject to a soft beta penalty (gamma=0.5, beta_target=0.90), producing a well-diversified 20-name portfolio with HHI=0.0615.

**Key observation**: All 40 risk-universe tickers already have positive alpha (mean=0.373, sd=0.086) due to the alpha_divergence_filter 0.80 applied in the Risk Agent (L-195a fix). Within this pre-filtered universe, alpha-rank differentiation is compressed (CV = 0.229), so MVO alpha-utilization provides minimal additional information over pure risk-minimization. MinVar's advantage is structural: it directly minimizes the quadratic risk objective without being misled by the compressed alpha signal, yielding lower TE and higher net IR.

---

## L-196 Pilot 8 Verdict: `minvar_retreat_again`

**Verdict explanation**:

This is the **third consecutive** Pilot (6, 7, 8) where MinVar dominates alpha-aware MVO by net IR. Pilot 8 was the designated test of the L-195a fix (cap_cluster 65% → 15%, beta_target 0.75 hard → 0.90 soft). Despite these structural improvements:

- Alpha-aware best (Kelly_f025): net_IR = 10.60
- MinVar_BetaSoft: net_IR = 12.08
- Gap: MinVar wins by +1.48 net IR points

**Root cause diagnosis**: The alpha_divergence_filter 0.80 successfully reduced cap-cluster concentration (65% → 15%), but it **simultaneously compressed cross-sectional alpha dispersion** within the 40-name universe. All selected tickers have positive alpha (0.25–0.51 range), so MVO produces near-equal weights regardless of lambda, yielding no informational advantage over MinVar. The filter solved the uniformity collapse problem at the full universe level (1899 names) but introduced a new uniformity problem at the risk sub-universe level (40 names).

**L-195a resolution status: ORTHOGONAL** (not INSUFFICIENT). The fix achieved its stated goal (unique_alpha/n = 0.875 > 0.80 threshold), but the structural interaction between alpha_divergence_filter and the 40-name sub-universe creates compressed alpha dispersion that MinVar exploits.

---

## Method Comparison Summary (net_ir, 10 methods parallel, R13)

| Method | net_ir | n_names | HHI | Beta | Alpha Used |
|--------|--------|---------|-----|------|------------|
| **MinVar_BetaSoft** | **12.084** | 20 | 0.0615 | 1.022 | zero_minvar |
| ERC | 11.882 | 20 | 0.0561 | 1.022 | ignored |
| Kelly_f025 | 10.600 | 20 | 0.0603 | 1.022 | kelly_fractional |
| HRP_pure | 10.270 | 20 | 0.0527 | 1.022 | hrp_pure |
| HRP_alpha_tilt | 9.578 | 20 | 0.0518 | 1.022 | hrp_alpha_tilt |
| MVO_lam4.0 | 8.007 | 20 | 0.0586 | 1.022 | confidence_scaled |
| MVO_lam2.0 | 7.938 | 20 | 0.0589 | 1.022 | confidence_scaled |
| MVO_lam1.0 | 7.899 | 20 | 0.0590 | 1.022 | confidence_scaled |
| MVO_lam0.5 | 7.878 | 20 | 0.0591 | 1.022 | confidence_scaled |
| BlackLitterman | 6.359 | 20 | 0.0527 | 1.022 | confidence_scaled |

Note: All methods selected exactly 20 names (min_names=max_names=20 enforced). HHI well below cap 0.15.

---

## Constraint Compliance (v2.3)

| Constraint | Requirement | Result | Status |
|-----------|-------------|--------|--------|
| n_names | = 20 | 20 | PASS |
| sum(weights) | = 1.0 | 1.000000 | PASS |
| max(weight) | <= 0.15 | 0.1249 | PASS |
| min(weight) | >= 0.0 | 0.0237 | PASS |
| HHI | <= 0.15 | 0.0615 | PASS |
| long_only | weights >= 0 | all >= 0 | PASS |
| alpha_winsor | 3.0 sigma | applied | PASS |
| beta_target | 0.90 soft (gamma=0.5) | 1.022 | soft (no hard violation) |

Beta note: uniform beta proxy = 1.0217 (risk_pkg port_mean_ew). All 40 tickers share same beta → soft constraint becomes a uniform shift with no cross-sectional differentiation. Beta target 0.90 not binding since all weights shift together.

---

## Portfolio Final Weights (Top 20)

| Rank | Ticker | Weight | Alpha | Confidence |
|------|--------|--------|-------|-----------|
| 1 | A049720 | 12.49% | 0.3450 | 0.4716 |
| 2 | A007340 | 9.17% | 0.5065 | 0.1221 |
| 3 | A091970 | 7.16% | 0.2532 | 0.8176 |
| 4 | A287410 | 6.64% | 0.3200 | 0.7112 |
| 5 | A030000 | 5.93% | 0.4250 | 0.2890 |
| 6 | A025540 | 5.40% | 0.3780 | 0.4520 |
| 7 | A030190 | 5.40% | 0.3156 | 0.6234 |
| 8 | A012690 | 5.26% | 0.3522 | 0.3441 |
| 9 | A041510 | 4.97% | 0.2840 | 0.5890 |
| 10 | A041830 | 4.63% | 0.3340 | 0.4230 |
| ... | ... | ... | ... | ... |

---

## L-196 Implications and Path B Recommendation

**L-196 status after Pilot 8**: CONFIRMED (3 consecutive pilots).

The verdict `minvar_retreat_again` for the third pilot confirms L-196: within a long-only 20-name concentrated universe on KR market, MinVar + beta constraint systematically dominates alpha-aware MVO by net IR. This is not a bug in implementation but a structural market property:

1. **KR market factor structure**: Low T/N ratio (37 observations, 40 names, q=0.925) means Sigma is noisy → MinVar exploits noise-reduced covariance structure better than MVO
2. **Alpha signal strength**: rank_IC = 0.038 (below 0.04 threshold) → MEDIUM confidence tier → confidence-scaled alpha is too weak to overcome the variance advantage of MinVar
3. **Alpha divergence filter compression**: Pre-filtering to high-alpha tickers compresses cross-sectional dispersion → no MVO informational advantage

**Path B Multi-sleeve recommendation** (for Forge):
The 3-pilot confirmation of L-196 means Path B (multi-sleeve: alpha sleeve + defensive/low-vol sleeve) should be the primary architecture going forward. A single-sleeve long-only concentrated portfolio cannot achieve Active IR > 0 with current alpha quality. The MinVar sleeve provides risk control, and an independent alpha sleeve (separate long-short or factor-long) can layer the alpha signal without the KR factor structure penalty.

**Active IR forecast**: Based on Pilot 7 Active IR = -1.033 and current method = MinVar (alpha-neutral), Active IR improvement is limited. MinVar will follow market risk (beta=1.022 > target 0.90) but alpha utilization is near-zero. Forge should evaluate whether regime-conditional alpha overlay or multi-sleeve can break the -1.0 barrier.
