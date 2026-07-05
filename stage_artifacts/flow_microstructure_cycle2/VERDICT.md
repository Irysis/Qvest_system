# Cycle 2 — Flow / Microstructure Near-Miss: CLOSED

**Date:** 2026-07-06 | **metric_type:** canonical_screen (screening tier; forge build_bt_result remains authoritative)
**Builds on:** Cycle 1 Track S prereg FLOW-S01..S09 (2026-06-12). `investor_wide.parquet` max Date = **2026-03-26, UNCHANGED** since prior run (today's RAWDATA rebuild did NOT refresh the investor flow raw cache) → base single+composite numbers are the frozen prior fair-trial, reproduced exactly (S04 sig≤202512 = 2.075 ≡ prior 2.077).

## Milestone gate (active PORT_t≥2.95 ∧ post-2017>0 ∧ oos_retention≥0.7 ∧ not closet-indexing)
**Result: NO candidate. Near-miss CLOSED.**

## Flow signals table (canonical top-25 EW, K200∪KQ150, 15bps delta, liq≥2e8 t-1, 2005-01…2026-03)

| signal | rank basis | PORT_t full | PORT_t 2017+ | oos_ret_med | active-share | mega top-2 wt | ex-mega PORT_t | metric_type |
|---|---|---|---|---|---|---|---|---|
| S04 composite (5-factor) | −mean(Z F60,I60,persist,conc,retail), re-z | **2.077**† (1.37‡) | 0.487† (−0.14‡) | **0.147** | 0.94 | 0.005 | 1.42 | canonical_screen |
| S01 Foreign NetBuy 60d rev | −Z | 1.758† (1.00‡) | 0.688† (0.00‡) | 0.302 | 0.94 | 0.003 | 0.93 | canonical_screen |
| S03 Retail-follow | −Z(−individual) | 1.398† | 0.118† | −0.113 | 0.96 | 0.001 | 0.79 | canonical_screen |
| S02 Inst NetBuy 60d rev | −Z | 0.204 | −0.512 | −0.720 | — | — | — | canonical_screen |
| S05 Smart-money flow | −Z | 0.813 | −1.284 | −1.037 | — | — | — | canonical_screen |
| S06 Foreign momentum (cont.) | +Z | −3.119 | −2.492 | — | — | — | — | canonical_screen |
| S07 Foreign resid 63d | −Z | −0.194 | −1.063 | −2.328 | — | — | — | canonical_screen |
| S08 Foreign-Inst agreement | −Z | −0.175 | −1.425 | −1.779 | — | — | — | canonical_screen |
| S09 Flow persistence | −Z | 0.397 | −1.570 | −1.241 | — | — | — | canonical_screen |
| **REV 1-month reversal** | −prior-1m return | **−0.889** | −1.486 | −3.557 | 0.95 | 0.002 | −0.90 | canonical_screen |

† frozen prior basis (sig≤202512-equiv, investor tail 2026-03). ‡ this run with 2026 mega-cap rally now in-sample.

## Why CLOSED (three independent reasons — decision-grade)
1. **Over-fit composite, not signal.** Best flow signal S04 reaches full PORT_t 2.08 but **collapses post-2017 to 0.49** and **fails oos_retention 0.147 << 0.7** (3-split median). No single flow factor exceeds full PORT_t 1.96 (max single = S01 1.76). This is the documented near-miss dying on over-fit + post-2017 decay — re-confirmed.
2. **NOT closet-indexing — the opposite.** Active-share ≈ **0.94–0.96** (maximally active, NOT benchmark-hugging). Top-2 mega-cap weight ≈ **0.005** — the flow book essentially *never holds Samsung/Hynix*. Ex-mega-cap re-test (drop top-2 mcap, re-rank) barely moves anything (S04 1.42 vs 1.37) → the (weak) edge is **not** a mega-cap-exposure artifact. The closet-index hypothesis is ruled OUT; the failure is genuine.
3. **1-month reversal does NOT survive.** Flatly negative every window (full −0.89, 2017+ −1.49, oos −3.56). The classic retail-overreaction anomaly is dead in the KR liquid top-25 monthly cross-section.

## Mega-cap regime interaction (reconciliation)
Adding sig months 202601–202603 (whose forward returns land in the **2026 cap-w KOSPI200 rally: +33% Apr, +35% May**) drops full PORT_t 2.08→1.37. This is **real regime**, not a bug (see `reference-kr-2025-megacap-semi-regime`). The flow book is *maximally active away from* the mega-caps driving the index (AS 0.94), which is exactly why it loses relative ground in this regime — the same mega-cap wall the session's other tracks hit.

## Adversarial self-check (AX-008)
- **Survivor by luck?** No survivor exists — the strongest (S04) is oos 0.147, S01 oos 0.302; both < 0.7. Anchored 3-split (55/65/75) all show OOS PORT_t ≤ 0.68 and collapsing (S04 0.75-split OOS PORT_t = −0.51). Not luck; consistent decay.
- **Closet-index artifact?** Explicitly tested and ruled out (AS 0.94, mega wt 0.005, ex-mega ≈ same). The flow edge is not mega-cap flow.
- **post-2017 an artifact of one regime?** The frozen 2017+ (0.49 for S04) is already the post-decay period; it degrades further to −0.14 once the 2026 mega regime enters. Consistent decay across sub-periods, not a single-regime artifact.

## Artifacts
- `stage_artifacts/flow_microstructure_cycle2/flow_closet_reversal_result.json` (full metrics + reconciliation + base 9-spec frozen)
- `stage_artifacts/flow_microstructure_cycle2/flow_diag_v2.R` (diagnostic engine), `prep_monthly.py` (Python preproc — R arrow segfaults on 419MB rawdata), `recon.R` (reconciliation)
- Prior fair-trial: `04_Research/composition_search/cycle1_trackS/flow_stage_a_detail.json`, `prereg_flow_specs.json`, `adversarial_verify_result.json`

## Recommendation to Q-Lead
**Do not escalate to forge.** Flow/microstructure was the last documented standalone near-miss; it is now closed on over-fit + post-2017 decay (NOT closet-indexing, NOT reversible via ex-mega-cap). Consistent with the session's mega-cap finding: standalone non-mega-cap signals cannot clear the cap-w benchmark in the current KR regime. Flow's residual value, if any, is as a DPL feature (screen_route=DPL_FEATURE), not standalone capital.
