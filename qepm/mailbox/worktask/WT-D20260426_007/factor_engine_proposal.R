#==============================================================================
# WT-D20260426_007 — STR_1701_V2 Confidence-Aware Linear Tilt
# Factor Engine Proposal (Alpha Agent V14)
#
# Mandate:
#   - INHERIT STR_1701 multi-sleeve base alpha (Slot A Consensus_4F + B ML + C Quality)
#   - ADD per-name confidence-aware sizing
#   - DO NOT change alpha base (Iter 11 dominant SR/CAGR/MDD inheritance)
#
# Iter 13 lessons enforced (BLOCKING):
#   1. Universe filter (KOSPI200 ∪ KOSDAQ150) BEFORE any computation
#   2. AvgTV20 = Close × Vol (not Size)
#   3. NW-HAC Harvey (not simple t-stat)
#   4. Codex resolution 9/9 (no silent omission)
#   5. honest disclosure of method (no fake ensemble labels)
#
# Confidence vector definition (chosen — multi-component):
#   c_i = sigmoid(α₁ * sub_stab_i + α₂ * (-residual_std_i) + α₃ * coverage_i)
#   - sub_stab_i: per-name 36M rolling IC sign consistency (3 sub-periods 검사)
#   - residual_std_i: walk-forward 12M residual std (low = high confidence)
#   - coverage_i: data coverage fraction (slot A∩B∩C present)
#
# Tilt formula:
#   z_i ∝ rank(score_i)^λ × c_i^κ (after normalization)
#   λ × κ grid sweep → choose joint optimal sub_stab + ICIR
#
# References (Step 0 hypothesis sourcing):
#   - Black-Litterman 1992: confidence-weighted Bayesian portfolio
#   - Lopez de Prado 2018 Ch.11: ML uncertainty quantification
#   - Avramov-Cheng-Metzker 2023 (RFS): confidence-aware ML sizing in equity premia
#   - Grinold-Kahn 1999 Active PM: IR optimization with uncertainty
#   - Pastor-Stambaugh 2003 (JF): model uncertainty in cross-section premia
#==============================================================================

# Window:
#   Pre-LB end: 2024-01-22 (Lockbox sealed)
#   Train+Validation only — Alpha cannot touch lockbox/paper_trade
#   Source base: STR_1701 alpha_scores parquet (already computed)

# Pipeline:
#   Step 1: Load STR_1701 base alpha (per-month per-ticker score_combined)
#   Step 2: Universe filter (K200 ∪ KQ150) — applied PRE-DIAGNOSTICS
#   Step 3: Liquidity filter (Close × Vol 20d ≥ 50M won, t-1 lag)
#   Step 4: Confidence vector construction (3-component composite)
#   Step 5: λ × κ grid sweep (4 × 3 = 12 combinations)
#   Step 6: Diagnostics — IC, ICIR, monotonicity, sub_stab (3 subperiods)
#   Step 7: Harvey NW-HAC + DSR + 5-spec FF regression PASS count
#   Step 8: Pick optimal (λ*, κ*) jointly maximizing ICIR × sub_stab penalty
#   Step 9: Emit alpha_package.json + alpha_validation.json + alpha_scores.parquet
#   Step 10: Lineage + Telegram + Codex R1
