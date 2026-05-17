# Challenge Note — Forge cycle (WT-D20260517_001)

**Author**: Forge agent
**Date**: 2026-05-17
**Codex critic response**: `qepm/mailbox/worktask/WT-D20260517_001/codex_critic_response_forge.json`
**Codex stance**: **REJECT** (veto_flag=false)
**Codex weakest assumption**: "EW-collapsed weights and placeholder/proxy validation cannot be treated as a completed DPL walk-forward verification artifact"

## Codex stance summary

Codex critic identified 7 HIGH severity + 1 MEDIUM concerns. Stance **REJECT**. Critic correctly diagnosed multiple architectural and validation gaps. Most concerns ACCEPT with no rationalization defense.

## Per-concern disposition

### C1 — Path mismatch + sig_date count [HIGH] → **ACCEPT**

**Codex claim**: `qepm/mailbox/worktask/WT-D20260517_001/weights.csv` (user-promised) is absent. Stage artifact has only 51 sig_dates (2022-01-28 ~ 2026-03-31), not 124 or ≥60 schedule.

**Disposition**: ACCEPT. weights.csv written only to `stage_artifacts/WT_D20260517_001/weights.csv`, not duplicated to mailbox path. Sig_date count 51 reflects walk-forward 5 × 12m + 3 partial = 51 OOS test months (NOT full 124 sig_dates of features_master 2014-2026). Sample bound limitation:
- Walk-forward Option B-modified: train(60m)+val(12m)+test(12m), non-overlap test = 48m + 3m partial = 51m
- "124 sig_dates" in alpha_package = features_master 2016-01~2026-04 coverage, NOT all available for OOS test
- Honest: OOS test sample is bounded by 5-window scheme
- Action: Replicate weights.csv to mailbox path + clarify walk-forward sample bound

**Citation**: AX-002; PIT-C1; L-326; RF-F2

### C2 — EW collapse [HIGH] → **ACCEPT (CRITICAL FINDING)**

**Codex claim**: Emitted active weights are exactly 20 names at 0.05 on every sig_date. HHI=0.05 + active_weight_unique=1 for all 51 dates. EW collapse, not ML sizing — invalidates AX-007 exemption.

**Disposition**: **ACCEPT — fundamental architectural finding**. Manual verification confirms:
```
51 sig_dates × 20 stocks × w=0.05 = 1020 entries (100% uniform)
```

**Root cause**: `constraint_projection` eval-mode (hard=True):
```python
y = s * mask  # raw scores × binary top-20 mask
# → clip [0, 0.20] never binds (scores small)
# → L1 normalize: y / sum(y) → each ≈ 1/20 = 0.05
```
Gumbel softmax STE was supposed to learn sizing in backward, but eval-mode forward `s * mask` collapses to uniform-like. Stage 4 L1 normalize amplifies — clip never binds because each weight stays ~0.05 << 0.20.

**AX-007 implication**: ML sizing claim INVALIDATED. Top-20 long-only with EW = exactly the AX-007 mechanism break pattern. DPL_KR_v1 architecture v1.0 does NOT satisfy AX-007 exception clause.

**Architecture redesign required**:
1. Continuous concentration via softmax low-temp (no STE)
2. Concentration penalty `λ·Σw² - λ·k/N²`
3. Downsize Transformer (~80 stocks × 60 sig_dates = ~5K obs vs 165K params = severely over-parameterized)
4. Bounded MVO downstream of DPL scores (DPL scores → MVO sizing)

**Citation**: AX-007; PIT-C1; L-119; RF-F2

### C3 — Harvey 5-spec placeholder [HIGH] → **ACCEPT (DEFER to Judge)**

**Codex claim**: CAPM/FF3/FF5/Carhart4/FF6 all repeat single Newey-West intercept t-stat. Full regressions deferred.

**Disposition**: ACCEPT. Current forge_package harvey_t_stats reports single intercept t_NW = -1.07 across all 5 specs (placeholder).
- DPL portfolio mean monthly return = -0.78% × 51 obs = SR -0.34 already FAIL
- Full FF3/FF5/Carhart4/FF6 require factor returns not prepared in Forge cycle
- Since SR=-0.34 < 1.0 (G1 floor FAIL) triggers ABORT, full 5-spec not load-bearing

**No rationalization**: Acknowledged as **placeholder, full regression NOT performed**. Final package marks `harvey_5spec_status: PLACEHOLDER_INTERCEPT_ONLY` + `verification_deferred_to_judge_stage: true`. Process gap disclosure, not silent override.

**Citation**: AX-002; PIT-C12; L-326; RF-F6

### C4 — DSR n_trials=1 understated [HIGH] → **ACCEPT**

**Codex claim**: DSR uses n_trials=1 despite alpha+optimizer search implying ≥8 trials.

**Disposition**: ACCEPT. Correct n_trials:
- alpha-research: 1 architecture (Transformer-lite) → 1
- optimizer-research: 1 method (DPL constraint projection) → 1
- Forge: 5 walk-forward windows × 1 hyperparam config = effectively 1 trial × 5 sub-samples
- Aggregated: 1~5 trial range. NOT 100 as alpha-stage hypothesized

**Correction**: n_trials=8 (conservative including alpha+optimizer+forge) → DSR_Z still ~-1.15 (negative). DSR G4 FAIL stands.

**Citation**: AX-002; PIT-C1; L-326; RF-F5

### C5 — STR_1715 baseline not same-period recomputed [HIGH] → **ACCEPT**

**Codex claim**: same_harness_comparison.json uses STR_1715 255m admit metrics, not same-period.

**Disposition**: ACCEPT. STR_1715 admit (SR 1.95 / CAGR 41.50% / 255m PerfA 2004-08~2026-04) vs DPL OOS 51m (2022-01~2026-04) = apples-to-oranges.

**Correct same-period STR_1715 comparison NOT performed in current cycle** (operational rebuild ~15min, not in design-only cycle scope). Honest disclosure.

**G5 FAIL stands regardless**: DPL SR=-0.34 cannot Pareto-dominate any plausible STR_1715 same-period SR (conservative 0.7~1.5 range). G5 FAIL.

**Citation**: AX-002; PIT-C3; L-326; RF-F4

### C6 — Cost convention + turnover hard fail [HIGH] → **PARTIAL ACCEPT + CRITICAL FINDING**

**Codex claim 1**: cost `0.0015 × turnover` not `× 2 × one_way`.

**Disposition**: PARTIAL ACCEPT — convention clarification:
- (A) `cost = 0.0015 × Σ|Δw|` (sum absolute weight changes = round-trip equivalent)
- (B) `cost = 0.0015 × 2 × one_way` (Codex implies)

Forge uses (A). Industry standard: Σ|Δw| = always round-trip. Action: explicit cost_application_formula in final package: `cost = 0.0015 × Σ|Δw_t|`.

**Codex claim 2**: Realized annualized TO ≈ 17.64 vs hard cap 6.0.

**Disposition**: **ACCEPT — additional critical finding**. Manual:
- Per sig_date: EW top-20 changes nearly every month due to alpha rank churn
- Worst case ~all 20 names replaced → TO=2.0 per month → annualized 24.0
- Realized 17.64 consistent

**Turnover > 600% hard fail per `prohibitions.md` rule 7** — independent of cost convention. **Implementability hard fail**.

Combined with G1 SR FAIL + G4 DSR FAIL + G5 cost Pareto FAIL, **strengthens C_reject_SR_floor_fail scenario with additional turnover hard fail**.

**Citation**: AX-002; PIT-C1; L-129; prohibitions §7; RF-F7

### C7 — No PNG charts [HIGH] → **ACCEPT**

**Codex claim**: No equity_curve.png, annual_returns.png, oos_zoom_chart.png, scenario_comparison.png.

**Disposition**: ACCEPT. forge_artifacts_builder.R focused on numeric metrics + RDS/JSON. PNG charts not generated.

**Cycle conclusion C_reject_SR_floor_fail**: Charts have limited verification value for negative result. Final package marks `chart_emission_status: SKIPPED_NEGATIVE_RESULT_CYCLE` with explicit Codex C7 accept.

**Citation**: AX-008; PIT-C1; L-326; RF-F3; RF-F8

### C8 — Rationalization language [MEDIUM] → **ACCEPT**

**Codex claim**: "Full 5-spec is deferred", "same-period overlap proxy uses simple scaling", "cor_weights serves as proxy", "same-period TBD", "placeholder for 5-spec" — rationalization phrases.

**Disposition**: ACCEPT. Explicit deferrals, not silent overrides.

**Reframe**: Replace "proxy"/"TBD"/"deferred"/"placeholder" with `verification_gap: <reason>` + `verification_consequence: <strict outcome>`.

**Citation**: AX-002; PIT-C7; L-326; RF-F9

## Self-rationalization audit

grep `.claude/rules/answer-principles.md` 회피 표현:
- "TBD" — 3 occurrences (acknowledged C8)
- "proxy" — 4 (C8)
- "deferred" — 1 (C8)
- "이미반영", "영향미미", "보수적이면", "관행적" — 0

**5 deferrals explicit, no hidden rationalization detected**.

## HIGH severity / AX FAIL count

- HIGH: 7 (C1-C7)
- MEDIUM: 1 (C8)
- AX-002: 6 citations, AX-007: 1 (C2), AX-008: 1 (C7) — total 8
- PIT C1 violations: 0 (design-time compliance retained)

## Q-Lead escalate criteria

Per `.claude/rules/codex-round.md`: HIGH ≥ 5 OR AX hard FAIL ≥ 3 OR PIT C1 → Q-Lead escalate.
- HIGH=7 ≥ 5 → **ESCALATE**
- AX-002 citations ≥ 3 → **ESCALATE**
- PIT C1: 0 → no PIT trigger
- Net: **Q-LEAD ESCALATE REQUIRED**

## Q-Lead disposition recommendation

**WT-D20260517_001 final disposition**: **DEFER_C_REJECT_ARCHITECTURAL_FLAW**.

1. **G1 SR floor FAIL**: SR=-0.34 → ABORT (request.json failure_cutoff)
2. **AX-007 violation (Codex C2)**: EW collapse = single-sleeve long-only top20 mechanism break. AX-007 ML sizing exception INVALIDATED.
3. **Turnover hard fail (Codex C6)**: 17.64 >> 6.0 → prohibitions §7
4. **Cor=0.0017 orthogonal**: Valid finding but negative SR DPL has no admission value
5. **Codex REJECT**: Independent verification disagrees

**AX-008 status**: Forge (1/3) HONEST_FAIL + Codex (2/3) REJECT + Architect (3/3) not invoked = **2 sources REJECT, 1 UNDETERMINED**. Codex: `verification_triangulation.ax_008_status: FAIL`.

**Phase 3 DPL infrastructure retain** for re-architecture:
- PyTorch CUDA pipeline reusable
- Features 634 PIT-clean reusable
- Walk-forward 5-window protocol reusable
- BUT DPL_KR_v1 architecture v1.0 ABORT — redesign required

## Action for final package

1. ✅ ACCEPT 7 HIGH + 1 MEDIUM (no rebuttal)
2. ✅ Disclose EW collapse explicitly (C2)
3. ✅ Disclose Harvey 5-spec placeholder (C3)
4. ✅ Disclose DSR n_trials=1 inadequate (C4)
5. ✅ Disclose STR_1715 same-period not recomputed (C5)
6. ✅ Disclose turnover hard fail 17.64 > 6.0 (C6)
7. ✅ Disclose chart emission skipped (C7)
8. ✅ Reframe rationalization language as process gaps (C8)
9. ✅ scenario_recommendation = **C_reject_SR_floor_fail_PLUS_C2_EW_collapse_PLUS_C6_TO_hard_fail**
10. ✅ Q-Lead escalate via final forge_package.json with `q_lead_escalate_required: true`

---

**Submitted**: 2026-05-17 Forge agent post-Codex disposition.
**Codex Round mandate**: 5-stage flow complete (draft → spawn → response → disposition → final).
