# Challenge Note — WT-D20260529_005 Track MULTI_HORIZON (Alpha)

Codex Critic Round (gpt-5.5 xhigh) stance = **REJECT** on draft. Per Charter §8 (No Silent Override)
+ Codex Round Decision Protocol, each concern classified ACCEPT / PARTIAL / REBUTTAL with the
3-axis basis (academic + L-code + quant data) where REBUTTAL is used. Rationalization grep run.

Codex weakest_assumption: *"full-lockbox ICIR weights can validate a horizon-decay diversification edge
on the same history used to choose those weights."* — **CORRECT. Root cause of C1. Accepted and fixed.**

---

## C1 [HIGH] PIT-C1/C3/C14/AX-002 — in-sample weight schedule (look-ahead in weight selection)
**Classification: ACCEPT (spec fixed).**
- Codex is right: the original blend used ICIR weights computed on the *entire* lockbox and applied to
  the *same* dates → process-level look-ahead in the weight schedule (not in the data, but in the
  weight choice). This is a legitimate AX-002 / PIT-C1 concern.
- **Fix**: rebuilt with a **WALK-FORWARD (expanding-window) weight schedule** — for each sig_date t,
  weights = ICIR(+)-proportional from sleeve IC of months **strictly before t** (24m warmup → EW before).
  `mh_alpha_build.R` §5-WF.
- **Result after fix**: BLEND_wf lockbox ICIR 0.386 still > best single SHORT 0.360 (edge survives), but
  **OOS (>2023-12-22) blend 0.221 < SHORT 0.237 → blend does NOT beat best single OOS.** Reported honestly.

## C2 [HIGH] AX-002/AX-007/L-484 — portfolio-alpha t below hurdle + TO/max_names
**Classification: ACCEPT (this is the finding) + clarify.**
- Authoritative canonical portfolio-alpha t (NW lag-3, KOSPI200) = **0.74 full / 1.33 lockbox (top-25)**;
  **1.04 full / 1.55 lockbox (top-20)** — all far below the 2.95 hard hurdle. This is exactly the reported
  scoped FAIL (Cycle 2 lesson: strong rank-IC ≠ realized long-only alpha). Not disputed.
- max_names: WT request mandate = 25 (`hard_constraints.max_names`-equivalent per track spec TO≤11/25);
  base Production Constraints = 20. **Added top-20 canonical** for base-mandate compliance (still FAIL).
- Turnover: canonical TO≈9.8–10.3/yr (union-notional definition) is within the **WT track cap 11.0**; it
  exceeds the *base default 6/yr*. Inline name-turnover = 4.99/yr. Both reported; this track honors the
  WT-specified TO≤11. Net SR is reported net-of-15bps regardless.

## C3 [HIGH] AX-007 — "multi-sleeve" claim
**Classification: PARTIAL (reframed — AX-007 exception NOT claimed).**
- Codex correctly notes the handoff is a single scalar `BLEND_wf` → long-only top-N, not a genuine
  multi-sleeve/long-short/50+/ML-sizing portfolio. **I do not claim AX-007 graduation.** Reframed in
  `axiom_compliance.AX_007`: this is a multi-HORIZON CONSTRUCTION whose output is a feature/template
  (DPL input per measurement-graduation §5), not a standalone graduating portfolio.

## C4 [HIGH] AX-008 — triangulation artifacts absent
**Classification: REBUTTAL.**
- Academic/process basis: this is an **alpha-stage fan-out task** (request `wt_type=discovery`, theme =
  "신규 construction 각도"). weights.csv / covariance.parquet / risk_package / optimization_package do
  not exist *by design* — risk/optimizer/forge are downstream agents not yet spawned (Q-Lead orchestration,
  CLAUDE.md Active Path). AX-008 triangulation (Forge+Codex+Architect 2/3) applies at the *graduation/admit*
  gate, not the alpha-discovery handoff.
- Path note ACCEPTED: stage dir is `stage_artifacts/WT_WT_D20260529_005_MULTI_HORIZON` (this note + package
  reference it explicitly). The CAP_TIER challenge_note Codex saw belongs to a sibling track, not this one.

## C5 [MEDIUM] RF-A4 / RF-A5 — sector-neutral test + hard liquidity
**Classification: ACCEPT (both added).**
- RF-A4: **sector-neutral ICIR test added** (`mh_alpha_build.R` §6b). Demean BLEND_wf within Sector per
  Date → ICIR 0.502 vs raw 0.386 → **retention 1.30** (>0.5; alpha is NOT a sector bet, slightly stronger
  sector-neutral). PASS.
- RF-A5: **hard 2e8 ADV (t-1) filter applied at the alpha handoff** (§10) — 687 rows dropped, 78,800 kept.
  top-25 realized median ADV 4.1e9, only 1.6% below 2e8 (now hard-filtered out of handoff).

## C6 [MEDIUM] AX-003/AX-004 — value/quality near KR failure patterns; references thin
**Classification: PARTIAL + REBUTTAL.**
- REBUTTAL basis (3-axis): (academic) value+quality here are the **LONG sleeve only**, multi-axis composite
  (V02+V01+V20+Q01+Q07), not EP-standalone (AX-003 is EP_STANDALONE+LOW_TURNOVER) nor single-signal quality
  long-only (AX-004 is quality single-signal). The AX-004 *exclusion* explicitly permits "multi-axis quality
  composite within multi-sleeve". (L-code) AX-003 L-132/135, AX-004 L-133/134/139 are scoped to those exact
  structures. (quant) LONG sleeve lockbox ICIR = 0.290, Harvey-t basis positive across all 3 subperiods.
- PARTIAL: references are author-year; titles can be expanded by Judge if needed. KR applicability shown via
  subperiod_stability=1.0 + sector-neutral retention, not paper existence (Charter principle 4).

## C7 [MEDIUM] L-219/AX-007 — realized return cor 0.79 vs STR_1715 (crowding)
**Classification: REBUTTAL (this is established structural truth, not rationalization).**
- (academic/quant) measurement-graduation §6 + memory [[reference-str1715-structure]]: KR long-only
  realized return cor vs STR_1715 is **structurally high (1st covariance eigenmode / market beta), not
  eliminable under no-short** — BAB (β−0.04) and VALUE (β−0.074) both market-neutral yet 0.78/0.76 return
  cor. MH realized beta = −0.10 (defensive), signal cor vs 1715 = 0.099 (low) yet realized return cor 0.79
  → confirms the eigenmode mechanism, not crowding. This is the documented AX-000 honest-limit finding,
  not a rationalization. Capacity: median ADV 4.1e9 >> 2e8, capacity not binding.

---

## Rationalization self-grep
Checked draft+final for: "미미 / 관행적 / 보수적이면 / 대부분 결과 동일 / 실무적 / 영향미미". 
- Only "structurally" / "structural" used — backed by §6 + quant (beta, eigenmode, BAB/VALUE 0.78/0.76).
  Not a hand-wave: it is the documented established truth with numeric basis. No hit requiring strengthening.

## Escalate triggers
- HIGH concerns = 4 (<5, no auto-escalate). AX hard FAIL = 0 (axioms not hard-failed; AX-007 not claimed).
  PIT C1 found → **fixed in-spec (walk-forward)**, not violated in final. No Q-Lead escalate required.
- Codex stance REJECT but rebuttals are NOT "ALL" (4 ACCEPT/PARTIAL + 3 REBUTTAL/PARTIAL) → no auto-escalate.

## Net resolution
REJECT addressed: C1/C2/C5 fixed in-spec; C3 reframed; C4/C6/C7 rebutted with basis. Final finding is a
**scoped FAIL** on portfolio-alpha t (this construction, N=k), with the in-sample-only decay-diversification
edge honestly disclosed (OOS does not beat best single horizon). Package finalized as discovery evidence /
DPL multi-horizon feature template — **NOT a graduation claim**.
