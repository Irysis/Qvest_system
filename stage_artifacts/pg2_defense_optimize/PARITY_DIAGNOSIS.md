# PG2 Defense-Optimize Harness — Parity Diagnosis (2026-07-03)

## VERDICT: parity_pass = FALSE — cache vintage drift (candidates 진행 무의미)

The harness (`eval_defense.R`) is functionally complete and its overlay/metric/decomposition
machinery is **proven faithful** by isolation testing. Parity fails **only** because two frozen
upstream artifacts (factor DB/IC cache, and rawdata) have been rebuilt since `alpha_scores.parquet`
was frozen, so reconstruction from the *current* cache cannot reproduce the frozen values to 1e-4.

## Gate results (current defense = Q07/M08/Q25 EW)

| Gate | Result | Target | Pass |
|---|---|---|---|
| (i) def_z vs stored score_defense_z | max\|diff\|=**4.16**, cor=0.849 | <1e-4 | ✗ |
| (ii) score_eff_new vs stored score_eff | max\|diff\|=1.456, cor=0.970 | reproduce | ✗ |
| (iii) SR | 1.8196 | 1.898 ±0.03 | ✗ |
| (iii) MDD | 0.2340 | 0.233 ±0.5pp | ✓ |
| (iii) PORT_t | 5.466 | 6.21 ±0.15 | ✗ |
| (iii) IR | 1.242 | 1.416 ±0.03 | ✗ |

## Decomposition + engine paths are CORRECT (isolation test, `parity_stored.R`)

1. `0.65·score_core_z(stored) + 0.35·score_defense_z(stored) == stored score_eff`
   → **max\|diff\|=0.00e+00, cor=1.000000**. The "core fixed, def-swap" architecture is exact.
2. **5-panel `ret_orig` (frozen) → my overlay path → noL4 SR=1.8947, MDD=0.2329** (targets 1.898/0.233).
   The overlay (stored beta_R05×m4), 15bps delta cost, pinned-IKS200 benchmark, and contract
   `build_metrics`/`build_benchmark_compare` (annualization=12) reproduce the baseline to <0.003.

## Two independent vintage-drift sources (both confirmed, neither is a harness bug)

**A. def_z drift — factor DB + IC-alignment cache rebuilt.** Per-year def_z recon vs stored:
- 2009,2011,2012,2017–2024: **cor 0.99+** (maxdiff 0.5–0.9) — near-faithful.
- 2004–2008, 2013–2016, 2025–2026: cor 0.26–0.88, maxdiff 3–4 — badly off.
- Mechanism (`diag4.R`): at 2008-01, aligned **Q25_Ohlson_O correlates −0.44** with stored def_z
  (vs +0.58/+0.45 at 2018/2022) = a **direction-alignment SIGN FLIP** driven by expanding-IC vintage
  change in `.cache/factor_db/factor_ic_monthly.parquet`. Early months have thin IC history → unstable sign.
- 2026-05 also loses M08 (`n_valid=0` in `factor_db_202605.parquet`, documented partial-rebuild gap);
  handled by prior-month fallback in the panel, but underlying Z still differs from freeze vintage.

**B. rawdata drift — forward returns rebuilt.** Feeding even the **STORED** score_eff through the
carrier walk-forward gives base_gross with max\|diff\|=0.238 (cor 0.97) vs the frozen 5-panel `ret_orig`,
and SR 1.9745 (vs 1.895 book-verbatim). i.e. the current `.cache/rawdata.parquet` (Ret column) no longer
matches the vintage that produced the frozen `ret_orig` (IKS200/BM_Ret fixes + universe refresh touched it).

## What is required to pass parity (remediation, not attempted here)

Parity needs the **frozen cache vintage**, which no longer exists on disk:
- a pinned `factor_db_*` + `factor_ic_monthly` snapshot matching the alpha_scores freeze, AND
- a pinned `rawdata` snapshot matching the frozen `ret_orig`.
Only `stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet` and
`factor_db_202605_PRE_m08rebuild.parquet` were found — no full factor-DB/rawdata freeze snapshot exists.

**Alternative (design change, needs 도훈 confirm):** redefine the candidate baseline as the harness's
own self-consistent current-cache reconstruction (recon-def-current → SR 1.82/PORT_t 5.47/IR 1.24),
and evaluate candidates as *deltas vs that recon baseline* rather than vs the frozen noLayer4 book.
This sidesteps vintage drift but breaks the promised numeric equivalence to the deployed book.

## Artifacts
- Harness: `stage_artifacts/pg2_defense_optimize/eval_defense.R`
- Panel cache: `stage_artifacts/pg2_defense_optimize/defense_factor_panel.parquet` (715122 rows, 271 sig_dates, 9 factors)
- Gate driver: `parity_gate.R` → `parity_result.rds`; isolation: `parity_stored.R`; sign diag: `diag4.R`
