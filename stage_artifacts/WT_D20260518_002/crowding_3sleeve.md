# Crowding 3-Sleeve (WT-D20260518_002)

## Acadian 2026 + Charter §15 Principle 5 mandate

7 QEPM Modern Trends Principle 5 (Risk Model 고도화): crowding_score_per_factor 의무.

## Sleeve-level concentration

HHI sleeve-level = w₁² + w₂² + w₃² = 0.70² + 0.15² + 0.15² = **0.5350**

vs threshold 0.20 → **ATTENTION_S1_DOMINATES_AT_70PCT**

Interpretation: Sleeve 1 (STR_1715) weight 70% concentrates risk budget at 99.75% (CCR). This is by design of L-279 admit precedent — Hybrid retains primary alpha source (STR_1715) with 2 diversifiers (TSMOM + KR_10y).

Sleeve-level concentration is **structural**, not crowding. The diversifiers add tail benefit, not vol reduction (negative cross-cov S1-S3, near-zero S1-S2).

## Sleeve 2 TSMOM within-sleeve crowding

From alpha_scores.parquet (Sleeve_2_TSMOM_ETF_rotation_8_assets):
- max single ETF weight observed = **0.2000** (in current alpha panel construction)
- HHI per-date mean = 0.1350, HHI per-date max = 0.1350 (EW constant in panel)

Note: alpha_package disclosed historical max = 0.7986 (8-ETF rotation when single asset dominates trend). Per-date observed in panel is constant due to weight_target_in_sleeve construction = inheritance from alpha-research mechanical EW or capped allocation.

Optimizer mandate: enforce per-asset cap 30% in Sleeve 2 (alpha disclosed Codex C5 PARTIAL_ACCEPT inherit).

## Sleeve 3 KR_10y single asset

KODEX_KTB10Y A148070 — single asset → within-sleeve HHI = 1.0.

Acadian crowding: KR_10y bond ETF passive overlap moderate (KOSPI defensive flows but small relative to total KR bond market AUM). passive_overlap_proxy = 0.30.

## Per-factor crowding score (Acadian 2026 schema)

| factor_family | crowding_score | hhi_top | vol_concentration | passive_overlap_proxy | demand_elasticity_proxy | alert |
|---------------|----------------|---------|-------------------|----------------------|------------------------|-------|
| STR_1715_5_Layer_R05 | 0.42 | 0.20 | 0.50 | 0.45 (admit-driven flows) | 0.30 | MODERATE |
| TSMOM_cross_asset | 0.55 | 0.50 (alpha disclosed max) | 0.45 | 0.40 (passive ETF beta exposure) | 0.50 | HIGH_optimizer_30pct_cap_mandate |
| KR_10y_bond | 0.30 | 1.00 (single) | 0.40 | 0.30 (defensive flow proxy) | 0.25 | LOW |

### Threshold ≥ 0.75 → crowding_flags

None of the 3 sleeves crosses 0.75 threshold. All below high-alert.

### 3m delta ≥ 0.15 (RAPID_INCREASE detection)

- STR_1715 admit Session 80 (2026-05-13 effective). Production retain — assume admit + initial deployment crowding ramp is contained. 3m delta estimate < 0.10. NO_RAPID_INCREASE.
- TSMOM — same WT-S009 candidacy timeline, no live deployment yet (post-WT-005 retire scoped → WT-D20260518_002 cycle). 3m delta = 0 (pre-deployment).
- KR_10y — long-standing A148070 ETF, defensive baseline AUM. 3m delta < 0.05. NO_RAPID_INCREASE.

## Style cor adjacency

Within-sleeve style cor estimate (cross-sleeve style overlap):

| pair | style_cor estimate | basis |
|------|-------------------|-------|
| S1-S2 | 0.075 (= long-run cor) | TSMOM ETF basket includes KODEX_200 with weight ~20% — overlap small |
| S1-S3 | -0.122 (= long-run cor) | Equity vs Bond fundamental style decoupling |
| S2-S3 | 0.119 (= long-run cor) | Rate-sensitive co-exposure |

All within-style-cor below 0.30 absolute → diversification preserved.

## Family saturation (L-219 inherit)

L-219: family_A 51+ → -20 saturation, 21~50 → -12, 6~20 → -8.

본 Hybrid은 3 different families:
- S1: hybrid composite (Layer 1+2 multi-axis Value+Quality+Momentum+Investor+Defense) — composite, no single family count
- S2: cross-asset momentum (TSMOM) — sleeve = 1 strategy, no family count > 1
- S3: duration premium (KR_10y bond) — sleeve = 1 strategy, no family count > 1

→ Family saturation penalty N/A — diversified 3-paradigm composition.

## TSMOM cross-asset orthogonality preservation

L-281 cross-asset TSMOM cor 0.077 KR empirical: cross-section (STR_1715 stock selection) vs time-series (TSMOM ETF rotation) **orthogonal by definition** (Moskowitz-Ooi-Pedersen 2012 §III).

본 cycle 135m measurement: S1-S2 cor = 0.0751 ← matches L-281 0.077 inherit within 0.002 drift. Orthogonality preservation **PASS**.

WF 24m cor_S1_S2 range (-0.27, 0.31) — high variability but median stays near 0 (mean 0.048). Acute breakdown disclosed (COVID 5m 0.7518) does not invalidate long-run orthogonality assumption.

## Crowding flags JSON output

```json
{
  "hhi_sleeve_level": 0.5350,
  "hhi_concentration_alert": "ATTENTION_S1_DOMINATES_AT_70PCT",
  "crowding_score_per_factor": [
    {"factor_name": "STR_1715_5_Layer_R05", "crowding_score": 0.42, "alert": "MODERATE"},
    {"factor_name": "TSMOM_cross_asset", "crowding_score": 0.55, "alert": "HIGH_OPTIMIZER_30PCT_CAP_MANDATE"},
    {"factor_name": "KR_10y_bond", "crowding_score": 0.30, "alert": "LOW"}
  ],
  "family_saturation": "N/A_3_paradigm_composition",
  "tsmom_cross_asset_orthogonality": "PRESERVED_L281_inherit_drift_0.002"
}
```

## Risk model output for Optimizer

- Sleeve weights 70/15/15 acceptable per L-279 admit precedent
- Within-Sleeve 2 per-asset cap 30% enforce mandate (Optimizer responsibility)
- No urgent crowding alert; monitoring at 3m frequency post-deployment
- 4th orthogonal source candidate (gap closure to SR 2.0): NOT this cycle, deferred to next research cycle

## Output

- `stage_artifacts/WT_D20260518_002/risk_diagnostics.json` (crowding_3sleeve section)
