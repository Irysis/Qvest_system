# PD006 — Architect 3rd-Source Verification (overlay cycle STR_1715_AR_on_M4_R05_overlay_PG2)

- Date: 2026-06-12 | Cycle 2 Track P | AX-008 third-source axis (codex governor C3 resolution)
- Subject: WT-H20260513_001 Layer-5 R05 V2 overlay, PG2 admit 2026-05-13, book_state v2.3
- Method: read-only audit (production read via Read tool only; no rerun, no mutation)

## VERDICT: ARCHITECT_CONDITIONAL (no blocking finding)

Measurement substance passes on all 3 axes. Conditional because end-to-end re-execution on the
current clone is broken by 3 restorable curation gaps (not methodology flaws).

## Axis 1 — PIT / lineage: PASS with one lineage gap

Lag audit of `01_reproducible_code/run_layer5_R05_overlay.R`:
- M4 `shift(1)` L116-117; AR beta `shift(1)` L125 with `db_thr = |delta beta_AR_lag|` L139.
- R05: signal computed at sig_date, `realized_ym = sig_date + 1m` (L175) -> decision t-1 EOM
  applied to month t. V4/V5 quantiles strictly past-only (`dates < dates[i]`, L189-203).
  Admitted V2 uses no quantile at all (pure regime map) — C1-immune.
- PIT honesty evidence in the data itself: 2008-10 row is regime=NORMAL with beta_R05_V2=1.0
  (full exposure in the Lehman month; the cut arrives 2008-11 CRISIS). The lag is real.
- Consistent with admit-time architect PIT walkthrough 15/15 PASS; re-confirmed here at code level.
- Note: possible conservative double-lag of m4 (source may already be shifted) — extra delay only,
  anchored by the in-script L4 sanity check (delta vs 1.7486 = 0.0000).

Lineage (5 inputs, md5 dual-recorded in architect JSON + governor admission): 4/5 exist at
recorded paths. **GAP: `stage_artifacts/WT_D20260425_010/alpha_scores.parquet` (md5 cbd8282e...)
is missing on this clone** — required by script section 3 (R05 top20 signal); production retains
`02_holdings_universe/alpha_scores_str1715_268m.parquet` (presumed copy, hash not verifiable
under read-only constraint).

## Axis 2 — Structure (5-layer roles / double-charging / determinism): PASS with 2 advisories

- Roles clean: L1/L2 frozen (alpha+Iter31 baked in PR ret_net, zero holding change), L3 M4 frozen
  schedule, L4 AR frozen mapping, L5 V2 deterministic regime map {1.0/0.5/0.3}. Monthly EOM,
  t-1 apply — schedule fully deterministic given frozen inputs.
- No double-charging: base cost once in PR ret_net; AR leg once; R05 leg incremental only.
  Separate-leg vs composite-delta pricing difference: +1.96bps/yr, max monthly 0.00045
  (Track O incumbent reconciliation) — immaterial.
- **Advisory 1 (under-charge): M4 scalar leg is uncosted** in L4/L5 formulas. Measured this audit
  (proxy, from WT-D20260430_001 weights.csv): sum|delta m4| = 6.5527 over 267m -> 0.2945x/yr
  one-way -> ~4.4 bps/yr at 15bps/leg. Immaterial vs delta-SR +0.205 / delta-CAGR +2.82pp; price
  it in any v2.4 re-measure.
- **Advisory 2 (label): package costs are v2.3 flat-engine on the base layer**; current standard is
  v2.4 delta (2026-06-11). Base one-way TO 7.5x/yr sits in B0's mild under-charge zone. Label
  discipline mandatory on any cross-cost-model comparison.
- Decision-vs-code: the script's own hard gates yield best_eligible=NULL (audit.json
  `best_eligible_variant: null`; coded AX-001v2 + MDD-strictly-better fail for V2). The admit was
  made via judge phase2 adjudication (AX-001 v2 -> N/A pure-overlay) + governor 8-metric eval
  + TO 0.68>0.5 informal waiver — fully documented, not silent; but the admit decision is only
  reproducible from judge/governor artifacts, not from the code alone.
- Standing caveat retained: CRISIS n=3 / CAUTION n=15; crash-onset months entered at full
  exposure by construction (t-1 lag). Minor narrative slip in judge text (calls 2008-10 a CAUTION
  month; data says NORMAL) — numbers unaffected.

## Axis 3 — Reproducibility: recomposition PASS / re-execution blocked on this clone

- Cited: Cycle 1 Track O (04_Research/composition_search/cycle1_trackO/) recomposed ret_L5_V2
  from the production period_returns: **max residual 5.13e-16**; db identities 5.6e-17 / 0;
  6-month deep-guard beta diff 0. [backtested identity recomposition]
- Supplemented this audit: manual deep-guard on 2008-11 (worst base month) — L4 -0.0590553,
  V2 -0.0193966, V5 -0.0191716 all EXACT vs stored CSV. Cross-document consistency: SR 1.9536 /
  MDD -0.2481 / CAGR 0.4150 (255m) identical across audit.json, selection table, manifest, judge,
  governor; 267m SR 1.8861 consistent; TO V2 0.6824 consistent.
- Admit-time architect independent reproduction (03_admit_artifacts JSON): 32/32 metrics within
  0.005 (max 0.0044), 5/5 md5 unchanged, KR FF5/Carhart 5/5 t_NW>3 — artifact retained.
- **Re-execution gaps (the CONDITIONAL):**
  1. GAP-1 missing WT_D20260425_010 alpha parquet (script section 3 cannot load);
  2. GAP-2 dead hardcoded BASE_DIR `/mnt/c/Users/User/OneDrive/...` (L70) + OUT_DIR -> empty mailbox;
  3. GAP-3 architect repro scripts lost with the WT-H20260513_001 mailbox (T+30 review confirms
     mailbox EMPTY; only the JSON result survives).

## Gate re-read under current rules (advisory)

PORT-alpha t 5.56-6.77 >> 2.95 PASS (lag-6 vs lag-3 immaterial at this margin) | DSR: V1~V5 is a
sweep -> gate applies, N=5 ex-ante Z=1.448 PASS; V6 N=21/37 FAIL disclosed + DEFERRED (correct
under current sweep rule) | OOS strict ratio 1.8715 (>0.7; predates v2 3-split median) |
Calmar 1.6730 >= 0.64 PASS.

## Conditions for full ARCHITECT_PASS

1. Restore WT_D20260425_010/alpha_scores.parquet + md5-check vs cbd8282ef3cdaa9333d08faf130de5af.
2. Portable BASE_DIR (QM_ROOT) — via approved promote path or a staged corrected copy in a scratch WT.
3. Re-materialize architect verification scripts into a retained location (rewrite-from-spec OK;
   methodology fully specified in the JSON), per T+30 ax008_rerun_targets restage pattern.
4. Price the M4 leg (~4.4bps/yr proxy) and carry cost_model_version labels in any v2.4 re-measure.

AX-008 position: with Forge admit-time PASS + this Architect CONDITIONAL, the cycle stands at
2/3 strict + conditional third source; promotion-class 3/3 additionally needs the codex re-run
already enabled per T+30 (codex-cli 0.139.0 restored).
