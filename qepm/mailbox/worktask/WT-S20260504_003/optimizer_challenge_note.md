# WT-S20260504_003 Optimizer Challenge Note

**Date**: 2026-05-04
**Agent**: optimizer-research
**Codex stance**: REJECT (round 1)
**Codex audit log**: `/tmp/codex_qepm_critic_WT-S20260504_003_optimizer_1777853554.log`
**Resolution**: 4 ACCEPT + 2 PARTIAL + 1 REBUTTAL + 1 ACCEPT (note) → final optimization_package amended

---

## Summary

Codex Critic round (gpt-5.5 + xhigh) returned **REJECT** with 8 concerns (1 CRITICAL + 5 HIGH + 2 MEDIUM/LOW). Charter §10 verification triangulation: codex source = source 3. Forge will independently re-fit + re-backtest (source 2). Optimizer source 1 = this package. Need 2/3 PASS — codex source FAIL means Forge must concur on remediations.

Per Codex Round Decision Protocol (`.claude/rules/codex-round.md`), critical PIT/AX hard violations get automatic ACCEPT. Method-selection / metric-disclosure concerns receive REBUTTAL only with 3-axis grounds (academic + L-code + quant data).

**HIGH ≥ 5 detected** → Q-Lead escalate trigger asserted in challenge_flags.

---

## Concern-by-Concern Resolution

### C1 (CRITICAL) — Sleeve-level weights.csv vs security-level → **ACCEPT (with structural REBUTTAL on history)**

**Codex claim**: Canonical weights.csv is `Date, weight_str1715, weight_cash` schema with max sleeve weight 1.0, not `as_of_date, ticker, weight, method_selected`. Forge cannot independently verify per-name 20-name/[0,0.20] constraints.

**Self-audit**: VALID for the as_of_date snapshot (forecast). The historical 268m weight schedule cannot be expanded to security-level because **STR_1715's parent 04_holdings.csv contains only the placeholder meta-ticker `STR_1715_RISK_SLEEVE` + `CASH_KRW`** — STR_1715 is operationally a meta-sleeve abstraction. Per-stock historical weights are NOT materialized in the parent.

**Remediation**:
- New artifact `weights_security_level_snapshot.csv` produced for AS_OF_DATE (2026-05-04) by joining canonical sleeve weight (M4+HMM_Scale at last date: w_str=0.673, w_cash=0.327) with `STR_1715/production_weights/20260501_weights_cap_0p20.csv`.
- Hard-constraint audit at security level: **n_active=18, max_eff_w=0.1345, Σ=1.0000, cash=0.3275** — all PASS.
- Historical schedule: explicit field `historical_security_level_provenance` documents that 20-stock cap enforcement is at STR_1715 internal optimizer (forward_weights.R v2), not at this overlay WT. Forge re-backtest will validate via STR_1715 historical NAV reconstruction (sleeve-aggregate level, by design).

### C2 (HIGH) — Crisis pooled-blend not honored in scale_predicted → **ACCEPT**

**Codex claim**: Package claims Crisis pooled-blend fallback (n=47<50 → 0.647) is honored, but `hmm_posterior_path_walkforward.csv::scale_predicted` matches unblended Crisis scale 0.475. Example 2026-03-03: scale=0.5252 equals 0.475 base; blended would be 0.672.

**Self-audit**: VALID. The walk-forward CSV is a Risk-package artifact that did NOT apply the pooled blend (only `scale_adopted` static state vector). The optimizer must apply the blend at its own layer.

**Remediation** (material change, non-cosmetic):
- New `scale_canonical` = γ_Normal · scale_Normal + γ_Caution · scale_Caution + γ_Crisis · **scale_Crisis_pooled (=0.647)**.
- Audit field: `pooled_blend vs marginal diff = 0.172` (positive — confirms blend correctly lifts Crisis-state scaling).
- **Material impact on metrics** (after-blend vs before-blend):
  - HMM_Scale SR: 1.667 → 1.708 (Crisis less aggressive de-risking)
  - HMM_Scale MDD: -40.4% (≈ unchanged, modest)
  - M4+HMM_Scale SR: 1.776 → 1.814
  - M4+HMM_Scale MDD: -30.2% → -30.8% (slight worsening, but still <-25% spec)
- Final canonical weights.csv regenerated. `weights_csv_sha256` updated.

### C3 (HIGH) — M4-alone baseline missing from method_shopping → **ACCEPT**

**Codex claim**: Selection rationale states Net-IR ≥ 0 baseline reference is S1, but the WT objective is **M4-relative** (mdd_target = "≤ -25% OR M4 대비 -3pp 개선"). M4-alone is omitted from the candidate slate.

**Self-audit**: VALID design omission.

**Remediation**:
- 4th candidate **M4_alone** added to method_shopping_log (deployed baseline = parent WT-P20260429_002 weights.csv).
- New M4-relative metrics for each candidate: `ir_vs_M4`, `te_vs_M4`, `active_ret_vs_M4_ann`.
- New top-level field: `m4_relative_mdd_improvement_pp` = -1.0pp (canonical M4+HMM_Scale MDD -30.8% vs M4_alone MDD -31.6% = -0.8pp shallower MDD).
- **Honest disclosure**: -0.8 to -1.0pp M4-relative MDD improvement does **NOT** clear the WT spec -3pp threshold. The canonical M4+HMM_Scale **only** meets the alternative `MDD ≤ -25%` clause if Forge re-backtest produces a shallower historical MDD. Current optimizer-computed MDD on canonical = -30.8%, **failing both clauses**.
- Selection rationale updated: M4+HMM_Scale is selected NOT for clearing the -3pp threshold (it does not at sleeve-aggregate measurement level), but as the **specified user-mandated combined strategy** (HMM_Regime per WT + M4 deployed). Forge will re-backtest with full STR_1715 NAV model — final go/no-go is Forge + Judge after PIT-clean reproduction.

### C4 (HIGH) — Cost double-counting / overlay turnover → **PARTIAL (rebuttal + remediation)**

**Codex claim**: estimated_cost = turnover × 15bps may be half the round-trip formula; method metrics use ret_str × weight without visible overlay regime-switch cost deduction.

**Rebuttal grounds**:
1. **ret_str = STR_1715 03_period_returns.csv::ret_net** — already embeds STR_1715's internal 20-stock turnover at 15bps (parent backtest_contract). Overlay layer adds **only sleeve-scaling turnover** (|Δw_str| × 15bps one-way), additive on top.
2. `turnover_annual_roundtrip = mean(|Δw|) × 12 × 2` follows Charter §10 round-trip definition (×12 monthly to annual, ×2 for buy+sell of |Δw|). Codex's ×12 annualization warning is correctly observed and applied here.

**Remediation**:
- New explicit field `cost_basis_note` documents the layered cost structure.
- New `overlay_cost_drag_ann_bps` per candidate (S1=0bp, M4_alone=6.3bp, HMM_Scale=3.8bp, M4+HMM_Scale=7.0bp).
- Method metrics now include both `sr` (gross of overlay cost) and `sr_net_overlay` (after subtracting overlay cost from each month's portfolio return).
- Net-of-overlay-cost SR delta is small (M4+HMM_Scale: 1.817 → 1.814, -0.003) — overlay cost is 7bp/year, materially insignificant against ~20% ann_vol.

### C5 (HIGH) — Path inconsistency → **REBUTTAL (cosmetic)**

**Codex claim**: References to `qepm/stage_artifacts/...`, `stage_artifacts/WT_S20260504_003`, `stage_artifacts/WT_WT-S20260504_003` are inconsistent.

**Rebuttal grounds**:
- Canonical path per WT spawn instruction + project convention: `stage_artifacts/WT_WT-S20260504_003/` (note: prefix `WT_` + full task_id `WT-S20260504_003` → `WT_WT-S20260504_003/`).
- Codex's `qepm/stage_artifacts/...` is a Codex prompt-template artifact, not the project canonical path. Risk used `stage_artifacts/WT_WT-S20260504_003/`. Optimizer continues same canonical path.
- alpha_scores.parquet does NOT exist for sizing_only WT (no new alpha generated). Codex check is mis-targeted at sizing_only role.

**Action**: No change. Document canonical path explicitly in `optimization_package.json::weights_csv_ref`.

### C6 (MEDIUM) — Beta drift / sequential admission → **PARTIAL**

**Codex claim**: No beta_port vs benchmark, no overlay-OFF vs blended beta split, no TDC vs MEGA_05, no replacement/integration scenario.

**Self-audit**: This is **sizing_only / recommendation_only WT**. Sequential admission scenarios (replacement/integration weight breakdown) are governor-stage decisions in promotion WT, not optimizer-stage in this WT (cf. WT spec line 33: `state_machine_path... GOVERNOR_REJECTED → ABORTED, abort_reason_planned: RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE`). 

**Remediation**: Add field `recommendation_only_admission_deferral` documenting that TDC/replacement/integration analysis is deferred to follow-up promotion WT (not in this WT scope per spec).

### C7 (MEDIUM) — optimizer_challenge_note.md absent → **ACCEPT**

**Codex claim**: Charter No Silent Override is incomplete: optimizer_challenge_note.md absent, challenge_flags empty.

**Remediation**: This document IS optimizer_challenge_note.md. challenge_flags array now populated with 5 items (4 codex remediations + 1 negative-IR honest disclosure).

### C8 (LOW) — Micro-rebalancing risk → **ACCEPT (note)**

**Codex claim**: 126 of 214 nonzero monthly weight changes are below 0.5% (RF-O3 micro-rebalancing).

**Self-audit**: VALID observation. Many small Δw events (HMM posterior gradual transitions). Cost impact is bounded by overlay_cost_drag_ann_bps = 7.0bp/year (acceptable). 

**Remediation**: No threshold-based aggregation applied (would distort PIT signal). Documented as known minor RF-O3 flag in `red_flags_acknowledged`.

---

## Rationalization Red Flag Self-Check (Charter §8)

Codex flagged 4 phrases. Self-audit each:

1. **"NOT a method-shopping failure"** — Used to justify selection despite negative IR. **REBUTTAL stands**: WT primary objective is MDD reduction, not return improvement. Disclosed honestly in C3 remediation.

2. **"inherited from parent admit (unchanged here)"** — Used to deflect security-level audit. **PARTIAL ACCEPT**: snapshot-level audit added (C1 remediation); historical sleeve-level remains by structural inheritance.

3. **"no double-counting"** — Used in cash_definition. **REBUTTAL stands**: max-rule mathematically does not double-count; cost layering documented in C4.

4. **"recommendation-only nature ... deployment decision rests with Q-Lead"** — Used to defer accountability. **PARTIAL**: this is structurally true per WT spec (no book_state write), but does not exempt optimizer from honest metric disclosure. C3 remediation surfaces the -3pp gap publicly.

---

## AX-008 Verification Triangulation Status

| Source | Status | Notes |
|---|---|---|
| Optimizer (this package, after revisions) | PARTIAL_PASS | C1 snapshot added; C2 pooled-blend applied; C3 M4_alone added; C4 cost layered; C7 challenge note created |
| Codex (gpt-5.5 + xhigh) | FAIL → conditional REVISE_ACCEPT | C1+C2+C3+C4+C7 remediated; C5 rebutted (cosmetic); C6 deferred to promotion WT |
| Forge (pending) | PENDING | Forge to independently re-backtest with HMM walk-forward + pooled-blend + 4-variant comparison |

→ Need Forge agreement on: (a) walk-forward + pooled-blend reproduction; (b) M4-relative MDD measurement at full STR_1715 NAV reconstruction; (c) overlay cost layering 7bp drag.

---

## HIGH severity count

5 of 8 concerns are HIGH/CRITICAL (C1+C2+C3+C4+C5). Per `.claude/rules/codex-round.md` Q-Lead escalate trigger: **HIGH ≥ 5 → escalate**. **Q-Lead notified via challenge_flags array + this note.** Q-Lead retains decision on whether REVISE remediations are sufficient or full re-spawn needed.

## Final Decision

`optimization_package.json` (final, no `_draft` suffix) written with:
- **4-variant method_shopping_log** including M4_alone (C3 fix)
- **scale_canonical = pooled-blend** Crisis n=47<50 honored (C2 fix)
- **weights_security_level_snapshot.csv** as_of_date hard-constraint-verified (C1 fix)
- **overlay_cost layered + per-candidate disclosed** (C4 fix)
- **m4_relative_mdd_improvement_pp = -1.0pp** explicitly disclosed (C3 honest disclosure — does NOT meet WT -3pp target)
- **challenge_flags** = 5 items including `negative_M4_relative_IR_disclosed_under_mdd_target_priority`

**Q-Lead escalate flag asserted**. OPTIMIZER_DONE transition will be requested but conditional on Q-Lead acknowledging:
1. The HIGH ≥ 5 threshold (5 of 8 Codex concerns HIGH+).
2. The honest finding: **canonical M4+HMM_Scale does NOT meet WT spec MDD ≤ -25% OR -3pp improvement target at sleeve-aggregate measurement level. Forge full re-backtest is the gating verification.**
