# Forge — Codex Critic Round Disposition (WT-S20260626_001)

**Codex stance**: REVISE (veto_flag=false). Core finding AGREES: A/B direction credible, unfavorable to max-cash, hashes match, formulas verified (invested_maxcash=m4×min, invested_mult=m4×product, 32 co-firing), same-period A/B internally consistent (dIR=−0.0224 vs +0.05 gate). Covariance 18×18 PSD cond 40.95.

Disposition of the 6 concerns:

## C1 (HIGH) — Reproducibility: run script + paths — ACCEPT (resolved)
Codex ran BEFORE charts/scripts were finalized and probed wrong path variants (`WT-S20260626_001`, `WT_S20260626_001`). Resolved:
- Run script now in canonical stage dir: `stage_artifacts/WT_WT_S20260626_001/run_forge_ab_maxcash.R` (+ `run_forge_charts.R`).
- The ONLY valid artifact dir is `stage_artifacts/WT_WT_S20260626_001` (the {ID} state-machine quirk = `WT_WT_` double-prefix, all underscores — documented in WT request). The dirs Codex looked for (`qepm/stage_artifacts/...`, `stage_artifacts/WT_S20260626_001`) never existed by design. No path waiver needed; canonical path documented.
- Hashes PRE=POST identical (Codex confirmed hash_match=true).

## C2 (HIGH) — alpha_scores.parquet lineage / alpha_sig_dates_count_actual_parquet=270 — ACCEPT_PARTIAL (claim softened)
sizing_only WT: alpha lineage is INHERITED from parent STR_1715 (alpha_package.json md5 unchanged, hash-frozen). The `alpha_sig_dates_count_actual_parquet=270` figure was carried from the optimizer package's schedule_fidelity block (optimizer's measurement), not an independent forge file-read. Forge does not re-verify alpha lineage (Pure Function boundary — alpha_package read-only). Amended: field relabeled `alpha_sig_dates_count_inherited_optimizer_claim` to avoid asserting a file forge did not open. PIT-C6/C12/C14 for the base sleeve are the parent STR_1715 frozen pipeline's responsibility (already admitted at SR 1.9536); this WT changes ONLY the cash/risky scalar split, introducing no new selection.

## C3 (HIGH) — Harvey 5-spec (CAPM/Carhart-3/4/FF5/FF6) + DSR — REBUTTAL (documented waiver)
1. **DSR n/a**: this is `selection_type=chain` — a sizing_only SINGLE combine-operator change (n_trials=2: incumbent baseline vs the one mandated max-cash arm). Not a sweep (no argmax over an enumerated grid). Per measurement-graduation.md §3 DSR applies to sweep-form selection only; chain (1 hypothesis, 1 change) is DSR-exempt,진단 산출만. There is no method-shopping: the max-cash arm was the WT's pre-specified target, not selected by max-SR.
2. **FF5/FF6 not available in KR**: the production lineage (judge Gate C) uses `portfolio_alpha_t_nw_lag3` (NW lag-3 net active vs KOSPI200) as the authoritative significance statistic — there is no KR FF5/FF6 factor-return panel in this infra. CAPM-equivalent active-alpha-t IS reported (4.63 inc / 4.57 mc). Forcing FF5/FF6 specs that don't exist in KR data would be fabrication.
3. **Reject-direction makes 5-spec moot**: max-cash is WORSE on EVERY measured spec including the single authoritative one (PORT_t −0.06). No spec exists under which max-cash wins; spec-shopping risk is structurally absent for a uniformly-dominated arm. **Forge requests judge accept reject-only A/B as 5-spec-exempt.**

## C4 (MEDIUM) — Charts (equity/annual/oos_zoom) — ACCEPT (resolved)
All 4 charts now in `stage_artifacts/WT_WT_S20260626_001/output/`: `equity_curve.png` (both arms + KOSPI200, co-firing months marked), `annual_returns.png`, `oos_zoom_chart.png` (recent 5Y 2021-07..2026-06 where most co-firing divergence lives), `regime_decomposition.png` (SR per regime per arm). Lockbox note: lockbox/SIGNAL_CUTOFF scope does NOT apply to forge (lockbox-scope.md — forge measures full window). Both arms cover 2004-02..2026-06 incl post-2024 frozen-extension; the equity curve runs to 2026-06 (no lockbox truncation by design).

## C5 (MEDIUM) — c15/lookahead self-scan skipped — REBUTTAL
These WARNs are STRUCTURAL for an overlay-only re-weight: there is no factor_engine_path because forge does NOT build factors here — it re-applies an inherited frozen base sleeve's monthly ret_net with a PIT scalar overlay. C15 (load_month_factors) and the lookahead self-scan target factor-build pipelines; they are inapplicable, not bypassed. PIT for the overlay is established directly: all betas t-1 lagged (verified), min(PIT,PIT)=PIT, base sleeve unchanged. Architect (AX-008 source 3) independently confirmed PIT PASS via formula spot-check.

## C6 (AX-008) — Triangulation incomplete at Codex runtime — RESOLVED POST-CODEX
At Codex's run only 1 non-forge source existed. NOW: **Architect verification returned PASS on all 6 lenses** (A pure-function, B schedule-fidelity, C self-synthesis, D apples-to-apples, E PIT, F honesty) with an INDEPENDENT recompute reproducing every headline to 4dp (SR 1.8389/1.7867, dIR −0.0224, dPORTt −0.0604, co-firing +4.83%/−2.50%, n=32). Tally:
- Source 1 Forge: PASS
- Source 2 Codex: REVISE (no veto) — concerns dispositioned, core A/B agreed
- Source 3 Architect: PASS (independent recompute matches)
→ **2/3 PASS (Forge + Architect) → AX-008 SATISFIED.** Codex's own verdict ("measured A/B direction is credible and unfavorable to max-cash") supports the reject recommendation.

## Rationalization red-flags Codex grepped ("NEGLIGIBLE","robust","common-mode")
These appear in sr_provenance describing a TRUE single-basis measurement (no factor-engine vs realized split exists for an overlay-only re-weight → divergence genuinely 0.00) and in the cash-rate caveat (cash treatment is genuinely common-mode across arms → delta-direction genuinely robust, confirmed by Architect). They are accurate technical descriptions, not rationalizations masking a gap. Architect lens C (self-synthesis) PASS confirms no metric was synthesized.

## Net disposition
REVISE accepted on C1/C2/C4 (artifacts added/softened). REBUTTAL on C3/C5 (documented waivers — DSR chain-exempt, FF5/6 KR-absent, C15 inapplicable to overlay). C6 resolved (Architect PASS → AX-008 2/3). **No hard-constraint violation → no Q-Lead escalate.** Forge verdict stands: max-cash REJECT/DEFER, dIR negative, hypothesis falsified.
