# Challenge Note — WT-D20260529_004 Track CONDMOM (alpha-research)

**Codex stance**: REJECT (gpt-5.5 xhigh). **Agent verdict**: REJECT (concordant).
**Date**: 2026-05-29. **No Silent Override** (Charter §8): all 8 concerns classified below.

This is the rare concordant case — Codex REJECT aligns with the agent's own honest finding
(`interaction_beats_marginal = FALSE`). No rebuttal needed on the substance; concerns C1/C2/C7
*confirm* the agent's self-reported failure. C3/C4/C6 require calibration (Codex lacked the
Cycle-5 multi-track alpha-only context). Self-rationalization grep run at end.

## Escalation check
- HIGH severity concerns = 4 (< 5 trigger). No auto-escalate on HIGH count.
- AX axiom hard FAIL = 0. PIT C1 (lookahead) violation = none found.
- Codex REJECT + agent REJECT (concordant) → no adversarial rebuttal escalation. Q-Lead informed via verdict.

---

## C1 [HIGH] — Core IC diagnostics fail (rank_IC 0.0157<0.04, ICIR 0.103<0.20, Harvey-t 0.12<3.0, subperiod 0.33<0.50)
**ACCEPT.** Exactly the agent's own reported lockbox diagnostics. This is the basis of the agent's
REJECT. All graduation gates fail. No dispute — `diagnostics.subperiod_stability=0.333`,
`harvey_t_rankIC=0.12` are reported verbatim in the draft.

## C2 [HIGH] — Interaction adds negative incremental value (CONDMOM_tilt 0.103 < STATE 0.131, << MOM+STATE 0.197)
**ACCEPT.** This IS the central finding of the track. `interaction_beats_marginal_test.verdict=FAIL`.
The conditioning/interaction structure is not alpha-accretive — the value lives in the linear
combination (MOM+STATE ICIR 0.197, IC_t 3.06), not the interaction. QMJ lesson confirmed
(L: composite < single / sum-of-marginals). The mechanism (Hong-Stein diffusion) is *directionally*
confirmed (mom_ic_high 0.0263 > mom_ic_low 0.0198) but the delta (~0.0065 IC) is too weak to
dominate. **This concern is the reason for REJECT, not a flaw to rebut.**

## C3 [HIGH] — Missing artifacts (challenge_note, lineage, risk_package, optimization_package, weights, covariance)
**PARTIAL (calibration).** Codex evaluated against a full-pipeline expectation. This is a **Cycle-5
multi-track DISCOVERY alpha-research run** (one of QVALUE / CONDMOM / INTERACT_ML fan-out). Per role
boundary (`alpha_research_init.md` <strict_prohibitions>), the alpha agent is **forbidden** from
producing risk_package / optimization_package / weights.csv / covariance.parquet — those are
Risk/Optimizer agent artifacts produced only if the candidate is adopted into the dossier pipeline.
Their absence at the alpha stage is *correct* behavior, not a governance gap.
- **Action taken**: this `challenge_note_CONDMOM.md` is now written (addresses the challenge_note gap).
  `artifact_lineage.json` will be appended via `record_package_lineage()` after final package write
  (init <v61_lineage_obligation> order: write package → record lineage).
- Risk/Opt artifacts: N/A for a REJECTed discovery candidate (never advances to risk stage).

## C4 [HIGH] — Hard mandate mismatch: top25 evaluated vs base max_names 20; request.json relaxes to null/[0,1]
**PARTIAL (calibration).** The Work Task prompt explicitly mandates `max 25 names` (도훈 mandate,
20→25 for this cycle — consistent with Cycle 3 VALUE/ACCRUAL/TECHNICAL tracks all using N=25).
`request.json.hard_constraints.max_names=null` + `weight_bounds=[0,1]` is the *discovery* WT relaxation
(breadth allowed per init R1 wt_type=discovery). The top25 portfolio is an **evaluation construct**
for IC→portfolio translation, not a deployment weight vector. Final deployment 20-name / [0,0.20]
enforcement happens at the Optimizer stage (which CONDMOM never reaches, being REJECTed). No silent
override: N_NAMES=25 is documented in the build script + validation JSON. **This does not change the
REJECT** and does not affect the failing IC diagnostics.

## C5 [MEDIUM] — Liquidity not clean: 0.66% of top25 names below 2e8 floor
**ACCEPT (minor).** Reported honestly as `liq_pct_below_2e8=0.0066` (0.66%). Median 20d ADV of the
top25 is 9.2e9 KRW (46x the floor). The 0.66% breaches are a handful of month-stock cells in the
2004-2008 early sample; a deployment-stage hard LIQ prefilter (Optimizer) would drop them. Immaterial
to the REJECT (the alpha fails on IC, not liquidity). Documented in `liquidity_audit`.

## C6 [MEDIUM] — Lockbox labeling: 2004-2023 called lockbox; base context seals lockbox from 2024-01; no 3-way Pre-LB/LB/Combined report
**PARTIAL (calibration).** Terminology clarification: the agent uses `SIGNAL_CUTOFF=2023-12-22` as the
graduation-authoritative window per init `<v61_window_isolation>` (train/validation ≤ cutoff). The
2004-01..2023-12 window is the **in-sample-allowed** window (not "lockbox" in the sealed-OOS sense
Codex references); the agent reports BOTH lockbox (≤2023-12) and full (2004..2026) splits transparently
in `diagnostics_window_split`. The full-vs-lockbox split shows IC *improves* slightly OOS (full ICIR
0.132 vs lockbox 0.103) but recent36 ICIR is **-0.137** (post-2020 decay) — the honest OOS read is
*decay*, which strengthens REJECT. A formal 3-way Pre-LB/LB/Combined report is an Optimizer/Forge-stage
deliverable; not required to reject a discovery candidate failing in-window IC gates.

## C7 [MEDIUM] — Weak return orthogonality (0.876 vs 1715, 0.921 vs MOM, signal 0.864 vs MOM)
**ACCEPT.** Reported verbatim. This is the second reason the DPL-feature fallback ALSO fails: the
signal is momentum-family-saturated (signal cor 0.864, return cor 0.921 vs its own MOM marginal), so
its incremental value as a DPL interaction feature is near zero. Combined with C2 (no interaction
lift), there is no standalone *and* no DPL-feature justification. Confirms REJECT.

## C8 [MEDIUM] — RF-A4 uncleared: neutralization=none, no sector/size-neutral ICIR robustness
**ACCEPT (moot).** Neutralization was intentionally none (cross-sectional rank momentum-state, per
construction). Codex correctly notes vol/liquidity/dispersion axes can be sector/size proxies. The
agent did **not** run sector-neutral ICIR — a valid robustness gap. However: since the *raw* lockbox
ICIR (0.103) already fails the 0.20 gate by a wide margin, a sector-neutral version (which typically
*attenuates* IC) would not rescue it. The gap is moot for a candidate already REJECTed on raw IC.
Logged as a known limitation; would be mandatory if the raw signal had passed.

---

## Self-rationalization grep (mandatory)
Scanning this note for prohibited rationalization tokens: "미미 / 관행적 / 실무적 / 보수적이면 OK /
대부분 결과 동일 / 영향미미 / 이미반영".
- C5 uses "immaterial" / "minor" — but justified by quantified evidence (median ADV 46x floor, 0.66%
  breach confined to 2004-08, REJECT driven by IC not liquidity). Not a rationalization to pass a
  failing alpha — the alpha is REJECTed. ACCEPTABLE (label = honest minor-issue triage on a rejected candidate).
- C8 uses "moot" — justified: raw ICIR 0.103 << 0.20 gate, sector-neutralization attenuates IC, cannot
  rescue. Quantitative basis given. ACCEPTABLE.
- No token used to *defend* admitting the alpha. Verdict is REJECT; every concern either confirms the
  REJECT or is a calibration of pipeline-stage expectations.

## Final disposition
**REJECT** — concordant with Codex. Central test `interaction_beats_marginal = FALSE`: state-conditioning
of momentum is NOT a meaningful KR alpha source. The marginal factors combine additively (MOM+STATE
ICIR 0.197, IC_t 3.06 — itself unremarkable and not novel), the multiplicative/tilt interaction adds
nothing (0.103). Mechanism directionally confirmed (Hong-Stein) but quantitatively too weak. recent36
ICIR inverted (-0.137), subperiod 0.33, Harvey-t 0.12 all fail graduation; return cor vs 1715 0.876 +
vs own MOM 0.921 kills the DPL-feature fallback. **AX-000 honest finding**: proven limit reported, not
denied. This is a valid negative result for the factor-zoo-reduction discipline (Harvey-Liu-Zhu 2016).
