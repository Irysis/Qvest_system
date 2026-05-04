# Weight Method Selected — WT-S20260504_006 (IPCA Round 2)

## Canonical method: `S1_baseline_Iter31`

**Selection rationale (post-Codex Round)**:
- IPCA refinement attempted via QP `min ½γ ||B_t' w||² − α'w + ε||w||²` with time-varying β_i,t = Γ_β' z_i,t
- Time-varying β yielded **53% mean panel LFC reduction** (vs WT-001 PCA static B_ref ~83% endpoint), but at cost of **887%/yr one-way turnover** (vs Charter §8 hard cap 600%/yr)
- Codex C1 CRITICAL: 'transparency ≠ approval' — cannot designate hard-cap-breaching method as canonical
- Codex C2 CRITICAL: Γ_β trained on 2021-2024 IS panel applied across 2004-2026 walk-forward = PIT C1 forward-looking on pre-2024 dates
- **Canonical demoted to S1** (TO 512%/yr PASS, no PIT issue — IPCA loadings unused at S1 level)
- IPCA_Hedge / M4+IPCA_Hedge retained as **non-canonical variants** for Forge OOS sub-period (2024-07~2026-05) comparison

## Selection objective: `to_adj_ret`

Turnover-adjusted return — IPCA variants generate 266bps/yr realized cost (15bps × 8.87/yr × 2). Forge to measure realized net SR/MDD/CAGR; if IPCA net beats S1 by ≥266bps/yr, the TO breach is justified by hedge value.

## Method shopping log

| Method | LFC@2026-05-01 | LFC reduction | TO one-way | Selected |
|---|---|---|---|---|
| S1_baseline_Iter31 | 3.249 | (reference) | 5.125 (512%/yr) | **CANONICAL** |
| IPCA_Hedge γ=1000 | 1.001 | -69.19% (endpoint) / -53% (panel mean) | 8.866 (887%/yr) | variant |
| M4+IPCA_Hedge | 1.001 sleeve | -69.19% (sleeve) | 8.866 (sleeve) | variant |

γ calibration sweep (`method_shopping.json` gamma_sweep): plateau at γ ≥ 10 (LFC = 1.001 unchanged). γ=1000 selected mirroring WT-001.

φ_TO calibration sweep (`_logs/phi_to_sweep.json`): TO penalty STRUCTURALLY INEFFECTIVE — best (φ=10000) reduces 887% only to 720% with LFC degradation 53% → 45%. φ=0 retained.

## Alpha lineage (PIT)

- Parent WT-P20260429_002 alpha_package SHA: `34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984`
- alpha_package_inherit_ref.json: cert_exempt=alpha_discovery, no_new_alpha=TRUE
- Alpha realization = STR_1715 Iter31 linear_tilt (λ=1.5, φ=3, cap 0.20) — used as direct portfolio weights, not a proxy
- Z scores per sig_date loaded via factor_db_connector.load_month_factors() (PIT C13~C15 enforced)

## Schedule density

- 269 unique as_of_date in canonical weights.csv (S1 variant)
- 269 / 269 = **1.000** (RF-O9 PASS, threshold 0.95)

## Constraint compliance (canonical S1)

| Constraint | Value | PASS |
|---|---|---|
| max_names ≤ 20 | 20 | ✓ |
| weight_bounds [0, 0.20] | [0, 0.20] | ✓ |
| Σw = 1 | max dev 9.6e-7 | ✓ |
| long_only | min_w = 0 | ✓ |
| TO one-way ≤ 600%/yr | 5.125 (512%/yr) | ✓ |
| schedule_density ≥ 0.95 | 1.000 | ✓ |

## Codex Round disposition

- **Round 1 stance**: REJECT (2 CRITICAL + 4 HIGH + 1 MEDIUM)
- **Resolution**: 2 ACCEPT (C1 canonical→S1, C2 PIT routing to Forge OOS sub-period) + 2 REBUTTAL (C3 risk threshold, C5 alpha lineage) + 3 PARTIAL (C4 selection, C6 SHA, C7 CRISIS max_w)
- Full classification table: `optimizer_challenge_note.md` Section 5

## Forge handoff

- `weights.csv` (canonical S1) for full 22-year backtest
- `weights_variants/{IPCA_Hedge, M4+IPCA_Hedge}.csv` for OOS sub-period (2024-07~2026-05) comparison
- 6 forge_responsibilities listed in optimization_package.json `handoff_to_forge.forge_responsibilities`
