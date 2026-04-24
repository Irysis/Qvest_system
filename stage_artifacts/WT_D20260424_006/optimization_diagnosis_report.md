# Optimization Diagnosis Report — WT-D20260424_006 Pilot 8 Path A
**Date**: 2026-04-24
**Task**: L-196 판정 + Active IR breakthrough 검증
**Verdict**: L-196 `minvar_retreat_again` (3rd consecutive pilot)

---

## 1. Alpha-aware MVO vs MinVar Detailed Comparison

### IR Comparison Table

| Criterion | MVO_alpha_lam2.0 | MinVar_BetaSoft | Delta |
|-----------|-----------------|-----------------|-------|
| net_IR | 7.938 | **12.084** | MinVar +4.146 |
| E[AR] (raw) | ~0.34 | ~0.34 | ~same |
| E[TE] | ~0.043 | 0.028 | MinVar -35% |
| HHI | 0.0589 | 0.0615 | ~same |
| n_names | 20 | 20 | same |
| beta_port | 1.022 | 1.022 | same |

**Key finding**: MVO and MinVar produce nearly identical expected AR (~0.34) because all 40 tickers have positive alpha (range 0.25–0.51). The differentiating factor is TE: MinVar's lower variance gives it decisively higher net IR, not alpha signal utilization.

### Why alpha-aware MVO failed to differentiate in Pilot 8

**Root cause**: alpha_divergence_filter 0.80 created a paradox:
- At the full universe (1899 names): filter successfully selected diverse alpha tickers (unique/n = 0.875, cluster 15%)
- At the risk sub-universe (40 names): ALL selected tickers have alpha > 0.25, mean = 0.373
- Alpha CV = 0.229 (sd/mean) — compressed relative to Pilot 7 where negatives existed
- MVO confidence-scaled alpha: α̃ = conf × alpha. With conf mean=0.49, the signal is further diluted
- Result: MVO weight distribution ≈ equal weight + tiny confidence-rank perturbation ≈ MinVar solution

**Contrast with Pilot 7**:
- Pilot 7: cap cluster 65% → MVO collapsed to 7 names (high alpha cluster), MinVar spread to 19-20 names → MinVar won by breadth
- Pilot 8: cap cluster 15% → MVO spreads to 20 names BUT alpha is now uniformly positive → no differentiation → MinVar wins by lower variance

Both mechanisms lead to MinVar dominance, but through different structural paths.

---

## 2. L-196 Pilot 8 Verdict: CONFIRMED

**Status**: `minvar_retreat_again` — 3rd consecutive pilot

| Pilot | L-195a fix | beta change | MinVar IR | Best alpha-aware IR | L-196 |
|-------|-----------|-------------|-----------|--------------------|----|
| 6 | None | 0.75 hard | ~12 | ~7 | confirm |
| 7 | alpha_winsor 2→3σ, conf_floor 0→0 | 0.75 hard | 12.16 | 6.74 (7 names) | confirm |
| 8 | alpha_divergence_filter 0.80 | 0.90 soft (gamma=0.5) | **12.08** | 10.60 (Kelly) | confirm |

**L-196 definition (confirmed)**: In a KR KOSPI/KOSDAQ long-only 20-name concentrated portfolio with RAPC 5-factor alpha (rank_IC ≈ 0.038, ICIR 0.63, MEDIUM tier), MinVar + beta soft constraint systematically outperforms all alpha-aware methods by net IR. This is a structural property, not an implementation artifact.

**Structural mechanism** (from 3-pilot analysis):
1. Low T/N ratio (q=0.925) → Sigma is noisy → MinVar exploits shrinkage better
2. rank_IC = 0.038 < 0.04 threshold → alpha signal too weak to overcome variance noise advantage
3. Long-only + 20-name concentrated → universe constraints bind before alpha can differentiate
4. Beta constraint binds uniformly (uniform beta proxy) → no cross-sectional differentiation

**L-195a resolution status: ORTHOGONAL**. The fix (cap_cluster 65%→15%) addressed the symptom (uniform alpha collapse) but the structural mechanism is different from what was hypothesized. The filter creates a different form of uniformity within the sub-universe.

---

## 3. Final Portfolio Diagnostics

### Portfolio Characteristics
- **Method**: MinVar_BetaSoft (minimize variance + soft beta=0.90 penalty)
- **N names**: 20 (exactly, min_names=max_names enforced)
- **HHI**: 0.0615 (below cap 0.15, Grinold breadth adequate)
- **Beta portfolio**: 1.022 (soft target 0.90 not binding — uniform beta proxy)
- **Max weight**: 12.49% (A049720) — below 15% cap
- **Min weight**: 2.37% (A000070)

### Risk Profile
- **E[TE]**: 2.81% monthly (~9.7% annualized) — LOW tracking error vs index
- **Market risk**: ~100% of port variance (beta=1.022 × EW baseline)
- **Expected AR**: 34.15% (all 40 names positive alpha — but raw alpha level, not IC-adjusted)

### Constraint Compliance (Hard + Soft v2.3)
All hard constraints PASS. Beta soft constraint not binding (uniform beta proxy limitation).

---

## 4. Challenge Findings (P4)

### Challenge 1 — ALPHA_CV_CHECK (INFO)
Alpha cross-variation (CV = sd/mean = 0.229) is compressed within the 40-name risk universe. This is expected given alpha_divergence_filter selection, but it structurally limits MVO differentiation. **No alpha objection** (Path A: alpha frozen).

### Challenge 2 — BETA_PROXY_UNIFORM (INFO)
Per-ticker beta not available in risk_package. Uniform beta = 1.022 (port_mean_ew) used for soft constraint. **Implication**: soft beta constraint is non-differentiating across names — it applies equal penalty to all weights, functionally equivalent to a scalar shift. **Recommendation for Risk Agent**: include per-ticker beta_blume in future risk_package schema (beta column in covariance.parquet or separate beta_vector.json).

---

## 5. Forge Handoff — Regime Decomposition Re-validation Required

**To Forge / Judge / Governor**: The following regime decomposition re-verification is requested after Forge completes the full backtest:

1. **Alpha utility across regimes**: Does RAPC 5-factor alpha show higher IC in RISK_ON vs CRISIS? If alpha IC is regime-conditional, regime-switching weight method (MVO in RISK_ON, MinVar in CRISIS) may break the L-196 trap.

2. **Active IR decomposition**: Decompose Active IR = α-attribution + factor-beta attribution + residual. If market risk (beta > 1.0) is driving Active IR down, reducing beta (or hedging) is the fix, not alpha quality.

3. **Multi-sleeve test (Path B)**: 
   - Sleeve A: MinVar 15 names (risk control, 75% allocation)
   - Sleeve B: Top-alpha 5 names with concentrated weight (alpha, 25% allocation)
   - Target: combined SR improvement vs single-sleeve MinVar

4. **Alpha signal refresh**: rank_IC = 0.038 is below 0.04 graduation threshold. If Full SR improvement is blocked, Scout S0 for a higher-IC alpha signal should be prioritized.

5. **Beta per-ticker data**: Include beta_blume per ticker in risk_package for Pilot 9. Uniform beta proxy limits soft constraint effectiveness.

---

## 6. L-196 → Path B Decision Framework

Based on 3-pilot L-196 confirmation, the following decision framework is proposed:

| Condition | Action |
|-----------|--------|
| rank_IC < 0.04 AND MEDIUM confidence tier | Stay with MinVar (current) — alpha not strong enough for MVO |
| rank_IC >= 0.04 AND HIGH confidence tier | Re-test MVO with full per-ticker beta vector |
| Multi-sleeve architecture | Use MinVar as risk base + concentrated alpha overlay (5 names) |
| Regime-conditional | MVO in RISK_ON + MinVar in CRISIS (regime_switching_cost.R) |

**Current recommendation**: MinVar_BetaSoft is the optimal single-sleeve weight method for this alpha/risk combination. Path B multi-sleeve should be designed and tested in the next Pilot (Path B designation).

---

## Appendix: Method Shopping Log

10 methods tested in parallel (R13, 5 workers, 2.52 seconds total):

| # | Method | net_ir | alpha_used | ok |
|---|--------|--------|------------|-----|
| 1 | MVO_alpha_lam0.5 | 7.878 | confidence_scaled | yes |
| 2 | MVO_alpha_lam1.0 | 7.899 | confidence_scaled | yes |
| 3 | MVO_alpha_lam2.0 | 7.938 | confidence_scaled | yes |
| 4 | MVO_alpha_lam4.0 | 8.007 | confidence_scaled | yes |
| 5 | MinVar_BetaSoft | 12.084 | zero_minvar | yes |
| 6 | ERC | 11.882 | ignored_erc | yes |
| 7 | HRP_pure | 10.270 | hrp_pure | yes |
| 8 | HRP_alpha_tilt | 9.578 | hrp_alpha_tilt | yes |
| 9 | BlackLitterman | 6.359 | confidence_scaled | yes |
| 10 | Kelly_f025 | 10.600 | kelly_fractional | yes |

`parallel_exec=TRUE, n_workers=5, total_seconds=2.52`

All 10 methods feasible. No infeasibility_report triggered.
