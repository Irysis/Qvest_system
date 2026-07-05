# Axiom Engine Verdict — cross-family regime-conditional composite (5-card convergence)

WT `axiom_engine_research_20260705` · 2026-07-05 · metric_type=canonical_screen (backtested-tier) · selection_type=chain
Emit id: **L-QPM-20260705_105130** (on disk, callable, idempotent dry_run PASS)

---

## (A) What the regime-conditional cross-family composite showed on canonical PORT_t

Construction: value(V02/V01/V12) · multi-axis quality(Q08/Q02/Q07/Q04) · residual momentum(M08/M01) ·
tail-defense(D48/D45/D47), each family weighted by **t-1 regime expanding-window conditional-IC**
(RISK_ON→momentum+value, NEUTRAL→quality+momentum, CAUTION/CRISIS→tail-defense+quality). Top-25 EW
long-only K200∪KQ150, 159 measured months, canonical_screen_bt NW lag-3, 15bps delta-cost.

| metric | regime-cond | static ICW | static EW | gate | verdict |
|---|---|---|---|---|---|
| PORT_t | **0.838** | −0.573 | −0.036 | ≥2.95 | FAIL |
| oos_retention (v2 median) | **−0.553** | −1.516 | −1.062 | ≥0.70 | FAIL (all 3 splits neg) |
| calmar | **0.360** | 0.165 | 0.242 | ≥0.64 | FAIL |
| post-2017 PORT_t | **−0.535** | −2.129 | −2.171 | — | decay wall NOT breached |

- **vs static**: regime-conditioning lifts the raw PORT_t **level** materially (delta vs static-ICW +1.41,
  vs EW +0.87; both static baselines are outright negative). Regime decomposition confirms the mechanism
  is *directionally real* — CRISIS active SR 1.55 (n=5), RISK_ON 0.66 (n=127), NEUTRAL is the drag −1.35 (n=17).
- **BUT the lift is not significant.** AX-008 adversarial verify (verify.md §③, paired NW-t, ratios forbidden):
  cond−static_icw **NW-t 1.77**, cond−static_ew **0.97** (both <2.0); cond−lag1 −1.74 (lag1 marginally
  *better*). The "+1.41/+0.87 delta" are PORT_t **level** differences, **not** paired significance tests.
- **post-2017 / graduation**: era SR pre2018 +0.63 → 2018-22 +0.86 → 2023+ **−0.83**. The 2023+ cohort decay
  is the binding wall; post-2017 PORT_t −0.535, oos_retention −0.553 (OOS active Sharpe flips negative).
  **Graduation FAIL on all 3 HARD gates.**
- **Not an artifact, not a leak** (verify.md §①⑤): lag1 stress *rises* +0.18 (FaithTrend disease = a *drop*;
  none here), asof-toggle L1(w_expanding − w_oracle) mean 0.41 (leaking design → L1 collapses to 0), and the
  full-sample regime-IC oracle itself is unprofitable in CRISIS/CAUTION (value IC only +0.031/+0.054, all
  other families negative) → no profitable vein even *with* look-ahead. Benchmark/alignment clean (β-scan
  peaks sharply at off=0, no realized_ym/IKS200 bug). It is a **DECAY WALL** — real, leak-free, but weak.

**(A) verdict: FALSIFIED at capital grade.** Regime-conditional cross-family activation is a genuine
mechanism that lifts a negative static composite to a small positive but **statistically insignificant**
edge, and still cannot clear the KR post-2017 decay. Reproduces measurement-graduation §6
"직교 ≠ 수익" + SR ceiling ~1.1, now confirmed at the *meta-composite* level.

---

## (B) Engine-drive proof — did the self-development loop close? **knowledge_shaped_research = TRUE**

The loop ran end-to-end and is closed:

1. **Injected frontier → consumed** (consume_result.json): 5 distilled cards (DIST-QPM-003/002/006,
   DIST-AR-001/003) were read, and their `retry_condition`/`frontier` fields were shown to **converge on one
   point** — every card says "don't use your family single/standalone; combine cross-family + regime-conditional
   activation." The chosen frontier (cross-family regime-conditional meta-composite) is the intersection of
   those 5 pointers, not a fresh guess.
2. **New construction built from that knowledge, avoiding DISTILLED_NEG naively**:
   - single-signal long-only → avoided (4-family, each internally multi-axis: quality 4-comp, value 3-comp,
     defense 3-comp).
   - naked standalone top-N → avoided (regime-conditional cross-family weighting; no standalone family top-N).
   - 전기간-lens defense evaluation → avoided (tail-defense activates only CAUTION/CRISIS, episode-lens per AX-001 v2).
   - **the already-FALSIFIED frontier(b)** ("quality CRISIS/CAUTION 단독 tilt", L-QPM-20260705_102041) → NOT
     repeated. Instead the **regime→family mapping was corrected using the refutation's own realized-regime-IC**
     (quality was WORST in CRISIS −78.2%/yr → moved to NEUTRAL; CRISIS handed to tail-defense). The engine
     literally re-used the prior failure's measured payoff surface to re-map the new construction. This is the
     signature of knowledge shaping research.
3. **Measured (canonical_screen, real computation) → emitted**: PORT_t 0.838 / FAIL, emit L-QPM-20260705_105130,
   idempotent dry_run re-verified callable (EMIT_CALLABLE:TRUE, on-disk id match). E2E refutation
   (L-QPM-20260705_102041) confirmed already on disk and consumed into DIST-QPM-003.
4. **Ledger fed back into the injected card**: DIST-QPM-003 `falsified_frontiers` gained frontier_index 1
   (the meta-composite) and a `new_frontier_20260705` block; `exhaustion_note` updated. The card that *shaped*
   this research was *reshaped by* its result. Loop closed.

**Correction applied during this step (honesty firewall):** the on-disk L-code originally framed the static
baselines as `survived` with "beats static materially." Adversarial verify.md §③ shows the paired NW-t is
insignificant (1.77/0.97). I corrected the ledger `falsification_attempts` to `weakened` +
"raw level lift but paired NW-t <2.0 INSIGNIFICANT" and rewrote lesson_text so the ledger carries the
verified (not the overclaimed) conclusion. The **FALSIFIED verdict is unchanged**; only the "beats static"
overclaim was demoted. This is the ledger doing its job.

Naive DISTILLED_NEG paths were genuinely avoided (4/4 forbidden constructs sidestepped with named
differentiators), so `knowledge_shaped_research = TRUE`.

---

## (C) Next frontier — what this left in the engine

- **Narrowed (soaked up):** return-derived **cross-family recombination — static AND regime-conditional
  alike — cannot bypass the KR post-2017 decay.** superfactor 5-static (prior) + regime-conditional
  meta-composite (this) are both exhausted. Regime-conditioning adds directional but insignificant lift; the
  ceiling is a real cohort-decay wall, not orthogonality or leak. Recorded in DIST-QPM-003.frontier_index 1
  + exhaustion_note.
- **New frontier (next retry conditions):**
  1. **DPL** (direct portfolio learning — features→weights end-to-end, net-SR directly optimized): feed the
     *failed* return-derived alphas in as **features** rather than recombining them into scores
     (measurement-graduation §5). This is the differentiated mechanism the INV-7 gate requires.
  2. **non-return DART** (insider / cashflow-quality) — currently BLOCKED (elestock document.xml parser
     not started); the one information source not spanned by the return-derived families.
- **Axiom candidate?** No. This is a **negative provisional (INV-7 failure-ledger)**, PORT_t 0.84 ≪ 2.95 →
  not an axiom-candidate path. The retry-ban is scoped to *same return-derived recombination*; a differentiated
  mechanism (DPL / non-return) remains a legitimate revival target, not a closed dead-end (AX-000).

---

### Summary line
(A) regime-conditional cross-family composite = **capital-grade FALSIFIED** (PORT_t 0.838, all 3 HARD gates
fail, post-2017 −0.535); mechanism directionally real but paired-NW-t **insignificant** (1.77/0.97), decay
wall not artifact/leak. (B) self-development loop **CLOSED** — injected 5-card frontier → consumed →
new construction (avoided all 4 DISTILLED_NEG naively, re-mapped regime→family from the prior refutation's
own payoff surface) → measured → emitted → fed back into DIST-QPM-003; **knowledge_shaped_research=TRUE**.
(C) narrowed: return-derived recombination (static+regime-conditional) exhausted vs post-2017 decay; new
frontier = DPL / non-return DART; negative provisional, not axiom candidate. Emit id **L-QPM-20260705_105130**.
