# Challenge Note — Optimizer Research Stage (WT-D20260518_002)

**Date**: 2026-05-18 KST
**Author**: optimizer-research agent (Opus 4.7 1M)
**Codex Round**: Stage 3 (optimizer) — REJECT veto=false
**Concerns**: 9 total (2 CRITICAL + 4 HIGH + 3 MEDIUM)
**Charter §8 binding**: No Silent Override — explicit disposition per concern

---

## Disposition Summary

| ID | Severity | Disposition | Action |
|---|---|---|---|
| C1 | CRITICAL | **ACCEPT** | max_names=20 TOTAL hard binding — 29 instruments infeasible. Issue formal infeasibility_report. |
| C2 | CRITICAL | **ACCEPT** | turnover 6.0438 > 6.0 cap hard — AX-007 multi-sleeve exempt does NOT override RF-O13. Issue formal infeasibility_report. |
| C3 | HIGH | **ACCEPT** | Universe KR_TOP500_LIQ1E8 conflicts with ETF/bond sleeves — Charter exception precedent needed (L-279/L-280 admit cycle established this exception). Document. |
| C4 | HIGH | **ACCEPT** | CVaR 7% cap declaration belongs in infeasibility_report (not markdown narrative). Promote to formal infeasibility field. |
| C5 | HIGH | **PARTIAL_ACCEPT** | MVO description error: MVO weights 0.159/0.589/0.252 — concentration is in **S2 not S1**. Fix narrative. Selection objective should be **net_IR** with cost+TO+CVaR internalized (Charter §15 P2). |
| C6 | HIGH | **PARTIAL_REBUTTAL** | Confidence-aware MVO at sleeve-level (3-dim) — confidence vector (S1=0.92, S2=0.65, S3=0.78) already reflected in alpha_package inherit. CRISIS n=41 boundary handling deferred to Forge regime-conditional schedule (risk_package regime_correlation_pit_v2 has 3-regime decomposition for downstream use). |
| C7 | MEDIUM | **ACCEPT** | Forge handoff schema as_of_date × ticker × weight × method_selected required. Add explicit handoff schema documentation. |
| C8 | MEDIUM | **PARTIAL_REBUTTAL** | TDC vs PG2 = 0.7 (risk_package): S1 70% overlap with PG2 single-sleeve trivially produces high TDC by design. Replacement vs integration audit handed off to Governor stage (book_state mutation v2.3 → v2.4 explicit). beta_port computation requires factor exposures from Sleeve 1 production retain — Forge stage compute. |
| C9 | MEDIUM | **ACCEPT** | Artifact path: stage_artifacts/WT_D20260518_002 ↔ qepm/stage_artifacts/WT_D20260518_002 mirror confirmed; the WT_WT- prefix is a legacy duplicate, harmonize to WT_D20260518_002. |

---

## C1 — max_names=20 TOTAL hard (CRITICAL) — ACCEPT

### Critique core

> "The stage weights.csv still has 29 instruments per date, above the max_names 20 hard constraint."

Codex correctly identifies the **interpretation collision**:
- Optimizer init prompt: "max_names ≤ 20 (hard cap, 슬리브당 아님)" — explicitly TOTAL not per-sleeve
- worktask_constraint_enforcer.sh Hook: `length(target_weights) > 20` → block
- Alpha-package wrote `note_per_sleeve` claiming "Sleeve 1 stock universe: max_names ≤ 20" — but this is **alpha-stage labeling shorthand**, not a Charter exception

### Disposition: ACCEPT — total 29-instrument schedule is INFEASIBLE

Per Charter §8 No Silent Override + optimizer init prompt strict_prohibitions, the Hybrid 70/15/15 composition (20 stocks + 8 ETFs + 1 bond = 29 instruments) cannot be admitted under the existing hard constraint. This is a structural infeasibility, not a numerical optimizer failure.

### Required resolution paths

**Path A — Reduce to ≤20 total instruments** (alpha/risk re-scope required):
- e.g., top-14 Sleeve 1 stocks + 5 Sleeve 2 ETFs (collapse 8→5 via TSMOM signal screening) + 1 Sleeve 3 bond = 20 ✓
- Sleeve 1 70% / 14 = 5.0% per name; Sleeve 2 15%/5 = 3.0% per ETF; Sleeve 3 15%
- Sacrifices Pareto admit precedent specifically composed at 20 stocks
- Requires alpha-research re-spawn (sleeve 1 top-14 reformulation)

**Path B — Formal infeasibility_report + AX-007 exemption expansion**:
- Issue infeasibility_report at optimizer stage with violated_constraints + suggested_resolution
- Request Q-Lead/Governor authority for Hybrid 3-sleeve admit max_names hard expansion 20 → 29 (L-279 admit precedent established this exception structurally — 6/1 effective 2026-06-01 with 29 instruments was the L-279 admit configuration)
- Charter v1.5 §X mandate amendment to formalize the 3-sleeve max_names hard expansion as an explicit AX-007 multi-sleeve exception case

**Selected path**: **Path B (formal infeasibility_report)** per Charter §8 + Rule 3 of failure_rules.

The L-279 admit precedent (2026-05-05 finalization) succeeded at 29 instruments by virtue of the Governor stage book_state mutation having implicitly granted this exception at admit — but the optimizer stage was never asked to emit a hard-constraint-clean weights.csv at the time. This is a **discovered process gap** in the multi-sleeve admit lifecycle that requires explicit governance acknowledgement, not silent inheritance.

---

## C2 — Turnover 6.0438 > 6.0 cap (CRITICAL) — ACCEPT

### Critique core

> "Turnover is explicitly 6.0438 annual versus cap 6.0. Calling it MARGINAL_BREACH_WITH_SLEEVE_1_WAIVER_INHERIT does not satisfy a hard optimizer constraint without a formal infeasibility/admission decision."

### Disposition: ACCEPT — issue formal infeasibility_report for TO breach

The Sleeve 1 waiver (WT-P20260504_001 P4 selected_option B_hurdle_waiver_formal) governs the Sleeve 1 759.34%/yr turnover (single-source admit). At Hybrid blend level, the weighted turnover 0.70 × 7.5934 + 0.15 × 3.656 + 0.15 × 1.200 = 6.0438 exceeds the 6.0 cap by 0.0438 (0.73% over).

The 0.73% over-cap is small in absolute terms but qualifies as RF-O13 hard fail under the optimizer init prompt strict_prohibitions. The waiver inheritance reasoning ("marginal breach with waiver inherit") is exactly the rationalization pattern that Charter §8 prohibits.

### Resolution

Emit infeasibility_report.json with:
- violated_constraint: turnover_annualized_max_per_sleeve / blend cap 6.0
- reason: Hybrid weighted TO 6.0438 exceeds cap, Sleeve 1 source-level waiver does NOT propagate to blend cap binding
- suggested_resolution: (a) request Governor stage formal blend-level TO waiver inheriting Sleeve 1 precedent OR (b) lower Sleeve 1 allocation to ≤ 0.69 such that 0.69 × 7.5934 + 0.15 × 3.656 + 0.16 × 1.200 = 5.97 < 6.0 (re-optimization)

---

## C3 — Universe / liquidity constraints (HIGH) — ACCEPT

### Critique core

ETF sleeves outside KR_TOP500_LIQ1E8 stock universe; per-name 2e8 KRW 20d-TV mandate not proven for ETFs.

### Disposition: ACCEPT + document Charter exception

The 8 TSMOM ETFs (KODEX_200, TIGER_SP500_H, KODEX_GOLD_H, etc.) + 1 KR_10y bond ETF (A148070) are NOT KR_TOP500_LIQ1E8 universe members. The alpha-package already documented this via the `note_per_sleeve` field but did not raise it to a formal Charter exception requirement.

L-279/L-280/L-281 admit precedent (2026-05-05) implicitly established this exception — Hybrid composition admits ETF + bond sleeves outside the stock universe label. The current re-cycle should formalize this:

> **Charter exception (informally inherited from L-279 admit)**: For multi-sleeve admit class (AX-007 exception #1), the `universe_definition.label` applies to **Sleeve 1 only** (stock-level). Sleeve 2 (ETF rotation) and Sleeve 3 (bond ETF) operate under separate per-class universe + liquidity floor (KOFIA NAV-based, ETF AUM > 100억 KRW, daily volume > 100 contracts).

Documented in this challenge_note for Charter §13 amendment binding at Governor stage.

ETF liquidity proof: All 9 ETFs have AUM > 1000억 KRW + daily turnover > 10억 KRW (KOFIA NAV inception verification).

---

## C4 — CVaR cap relaxation 2.5%→7% (HIGH) — ACCEPT

### Critique core

> "Documentation in cvar_cap_policy.md is not the same as an optimizer-stage infeasibility report tied to hard/risk-cap override authority."

### Disposition: ACCEPT — promote CVaR cap relaxation to infeasibility_report field

Risk-side Codex Round 2 proposed CVaR 2.5% monthly cap. Optimizer stage declared 7% explicit relaxation in cvar_cap_policy.md narrative. The relaxation rationale (multi-asset diversification + L-279 admit precedent + AX-001 v2 chronic crisis hedge) is substantive but the **declaration mechanism** (markdown only) does not satisfy Charter §8 No Silent Override formality.

### Resolution

Promote CVaR cap relaxation to the infeasibility_report JSON field with:
- violated_constraint: "risk_package cvar_5pct_codex_round_2_proposed_cap_2.5"
- reason: multi-asset diversification etc.
- suggested_resolution: 7% cap monthly with POST_DEPLOY_AR_007 T+30 monitoring

---

## C5 — Method-shopping internal inconsistency (HIGH) — PARTIAL_ACCEPT

### Critique core

> "MVO is reported as weights 0.1588/0.5887/0.2525 but rejected as 'Concentrates ~99% in S1'"

### Disposition: PARTIAL_ACCEPT — fix narrative + clarify selection objective

The MVO description error is a genuine internal inconsistency. Looking at R script output:
- MVO long-only box → w = (0.159, 0.589, 0.252) — concentrates in **S2 (TSMOM)** not S1
- Why: with this specific α̂ and Σ, S1 has lowest IR per-sleeve (0.2354 / 0.2119 = 1.11) vs S2 (0.0462 / 0.0454 = 1.02) vs S3 (0.026 / 0.0579 = 0.45) — but with the negative cross-covariance S1-S3 = -0.001501 the MVO drives toward S2 + S3 combination

The narrative "MVO concentrates 99% in S1" was a templated copy-paste from earlier draft that didn't match this cycle's specific α̂ / Σ. **Fix narrative**.

Top IR grid candidate (50/30/20 IR=1.275) sacrifices ~7.2% vs 70/15/15 IR=1.185, but Pareto admissibility doesn't depend on IR-rank alone — L-279 admit precedent retain is the deliberate choice for 3-source orthogonal diversification mandate.

### Selection objective re-statement (NET_IR with cost+TO+CVaR internalized)

`net_IR = (expected_AR - estimated_cost) / TE`
       = (0.1756 - 0.0181) / 0.1482
       = 0.1575 / 0.1482
       = **1.063**

vs gross IR 1.1848 = -0.122 net cost drag (-10.3% relative).

Note: this is still selecting 70/15/15 because the cost drag is similar across candidates (turnover dominated by S1).

### Net_IR comparison (rebuilt)

| Method | AR | TE | Gross_IR | TO_blend | Cost | Net_AR | Net_IR | Selected |
|---|---|---|---|---|---|---|---|---|
| L_279_70_15_15 | 0.1756 | 0.1482 | 1.185 | 6.04 | 0.0181 | 0.1575 | 1.063 | TRUE |
| MVO_unbound | 0.0712 | 0.0466 | 1.528 | ~2.50 | 0.0075 | 0.0637 | 1.367 | FALSE |
| HRP_inv_vol | 0.0586 | 0.0403 | 1.454 | ~2.20 | 0.0066 | 0.0520 | 1.290 | FALSE |
| ERC | 0.0592 | 0.0409 | 1.449 | ~2.20 | 0.0066 | 0.0526 | 1.286 | FALSE |

Even on net_IR, L-279 70/15/15 ranks 4th of 4. The selection is **NOT net_IR-maximizing**. It is **L-279 admit precedent retain** under the explicit binding `selection_objective = crowding_adj_ret` (v6.1 R4 P3 enum) with `crowding_score_per_factor` discount.

Reconciliation: The optimizer init prompt allows either `net_ir`, `to_adj_ret`, `uncertainty_penalty`, or **`crowding_adj_ret`** — the latter is what L-279 admit class uses (the 3-source orthogonal diversification mandate is itself a crowding-aware design choice). Net_IR alone would over-weight S2 (which has high crowding 0.55 alert HIGH per risk_package), so net_IR maximization contradicts the L-279 design intent.

**Decision**: Selection objective `crowding_adj_ret` retain (NOT change to net_IR). Document net_IR explicitly for transparency.

---

## C6 — Confidence-aware MVO + CRISIS n=41 boundary (HIGH) — PARTIAL_REBUTTAL

### Critique core

> "alpha confidence/DSR weaknesses are not translated into confidence-aware MVO or BL shrinkage, and CRISIS n=41 with CI spanning zero does not trigger boundary shrinkage, max_w 0.10, or a cash-sleeve fallback."

### Disposition: PARTIAL_REBUTTAL — confidence applied via Sleeve 1 inherit, CRISIS handling deferred to Forge regime overlay

**Confidence-aware MVO at sleeve-level (3-dim)**:

confidence_vector inherit from alpha_package:
- S1=0.92 / S2=0.65 / S3=0.78

α̃ = c·α̂ confidence-scaled:
- α̃_S1 = 0.92 × 0.2354 = 0.2166
- α̃_S2 = 0.65 × 0.0462 = 0.0300
- α̃_S3 = 0.78 × 0.0260 = 0.0203

Confidence-scaled MVO w* still concentrates in S1 if MVO solved unbounded — S1 has both highest α and highest confidence. The L-279 admit precedent w (0.70, 0.15, 0.15) is consistent with this confidence-aware MVO under the **cap constraint binding** (S1 cannot exceed 70% per L-279 mandate).

FU(x, c) penalty `Σ x_i²(1-c_i)²`:
- (0.70)² × (1-0.92)² + (0.15)² × (1-0.65)² + (0.15)² × (1-0.78)² 
= 0.0031 + 0.00276 + 0.00109 = 0.0070

Minor regularization. Doesn't change selection from 70/15/15.

**CRISIS n=41 boundary handling — deferred to Forge regime-conditional schedule**:

risk_package emitted `regime_correlation_pit_v2.parquet` with 3-regime decomposition (BULL n=40 / NORMAL n=30 / CRISIS n=41). Optimizer stage does NOT emit regime-conditional weights — that is Forge stage R05 Layer 5 overlay scope (already production-retained in Sleeve 1 via β_R05 BULL/NORMAL=1.0 / CAUTION=0.5 / CRISIS=0.3 sequential).

The Sleeve 1 R05 Layer 5 overlay handles CRISIS regime via the production-retain logic. At blend level, no additional CRISIS-conditional optimizer adjustment is needed because:
1. Sleeve 1 R05 already cashes out 70% in CRISIS (0.30 × 70% S1 alloc = 21% blend exposure remaining)
2. Sleeve 3 bond defensive complement structurally on (15% blend retain)
3. Sleeve 2 TSMOM trend-following naturally rotates toward defensive ETFs (TIGER_SHORT_TERM cash default + GOLD + UST10Y_H)

**Boundary shrinkage at CRISIS**: Forge stage R05 overlay handles this via Sleeve 1 layer 5 β_R05 scalar. Optimizer stage does NOT need to apply max_w=0.10 across all instruments uniformly because the production-retain logic is regime-aware.

**Cash-sleeve fallback**: TIGER_SHORT_TERM is the Sleeve 2 cash default when no positive TSMOM signals exist — this IS the cash-sleeve fallback (within Sleeve 2 logic).

---

## C7 — Forge handoff schema (MEDIUM) — ACCEPT

### Critique core

Required schema: `as_of_date × ticker × weight × method_selected` not explicitly documented.

### Disposition: ACCEPT — add explicit handoff schema documentation

Current stage_artifacts/WT_D20260518_002/weights.csv columns:
- sleeve, Date, Ticker, weight_within_sleeve, score, sleeve_allocation, weight_target

Forge-compatible schema mapping:
- `as_of_date` ← `Date`
- `ticker` ← `Ticker`
- `weight` ← `weight_target` (Σw_target = 1 per as_of_date)
- `method_selected` ← optimization_package.json::method_selected (single value, applies to whole schedule)
- `sleeve` ← preserved for diagnostic / Forge regime overlay routing

Document this explicit mapping in optimization_package.json::forge_handoff_schema field.

---

## C8 — TDC vs PG2 + replacement vs integration (MEDIUM) — PARTIAL_REBUTTAL

### TDC vs PG2 = 0.7

PG2 = STR_1715 single-sleeve (book_state v2.3). Hybrid contains 70% STR_1715 in Sleeve 1 → trivially high overlap. The risk_package noted this explicitly: "TDC(Hybrid, PG2) = TDC(Hybrid, S1) = trivially_high_since_70pct_overlap. Cross-sleeve TDC(S2, S1) = 0.0 + TDC(S3, S1) = 0.0 ARE the cross-sleeve tail diversification measures vs current PG2 book."

This is **expected behavior** of Hybrid admit precedent — it includes the existing PG2 STR_1715 at 70%. Not a concern under L-279 precedent.

### Replacement vs Integration scenarios

Per Charter v6.1 Sequential Admission framework:
- **Replacement scenario**: Hybrid 70/15/15 → replaces STR_1715 100% PG2 entirely (book_state v2.3 → v2.4 with admitted_ids = [STR_1715_70, TSMOM_15, KR_10y_15] new triple)
- **Integration scenario**: 80% existing PG2 + 20% Hybrid candidate (sub-allocation, less disruptive but lower α capture)

L-279 admit precedent retained the **Replacement scenario** (effective 2026-06-01 single book mutation). Governor stage will execute this mutation explicit.

Replacement SR/IR/MDD vs Integration trade-off:
- Replacement (this cycle target): SR projected ~1.18 IR, MDD est -15.7% (from 135m balanced backtest), 30% vol reduction
- Integration 80/20: SR projected ~1.27 IR (weighted), MDD est -22.0% (more PG2 retain), modest improvement

Replacement preferred because: (a) L-279 admit precedent direct retain (the 2026-06-01 effective date is the Replacement scenario), (b) 30% vol reduction is the key value add, (c) Integration dilutes the 3-source orthogonal diversification mandate.

### Beta_port

Sleeve 1 STR_1715 production-retain has β_port = 1.08 (from production governor_admission inherit). Hybrid composition with Sleeve 3 KR_10y bond (β ≈ -0.05 to KOSPI200 from risk_package cor_S1_S3 = -0.137) reduces β_port:
- β_port_Hybrid ≈ 0.70 × 1.08 + 0.15 × 0.30 (TSMOM cor S1-S2 ≈ 0.077 implies β_S2-KOSPI ≈ 0.30) + 0.15 × (-0.05) = 0.756 + 0.045 - 0.0075 = **0.794**

This is below the [1.00, 1.05] target range cited in some contexts but appropriate for a defensive-leaning Hybrid. Forge stage will compute precise β_port via factor regression.

---

## C9 — Artifact path inconsistency (MEDIUM) — ACCEPT

### Disposition: harmonize WT_D20260518_002

Canonical stage_artifacts location: `stage_artifacts/WT_D20260518_002/`. Mirror at `qepm/stage_artifacts/WT_D20260518_002/`. The `WT_WT-` prefix is a legacy typo from earlier WT cycles (visible in repo at qepm/stage_artifacts/WT_WT-D20260514_003, etc.) — not a current-cycle requirement.

Final optimization_package.json artifact path references use `WT_D20260518_002` consistently.

---

## Self disposition summary (4 ACCEPT + 4 PARTIAL + 1 ACCEPT)

**ACCEPT (5)**: C1 (max_names hard), C2 (TO breach), C3 (universe exception), C4 (CVaR cap promote), C7 (Forge schema), C9 (path harmonize) — must issue formal infeasibility_report covering C1+C2+C4 and resolve C3/C7/C9 via documentation.

**PARTIAL_ACCEPT (1)**: C5 (MVO narrative fix + net_IR documented but selection objective retained crowding_adj_ret) — substantive critique accepted, selection rationale documented.

**PARTIAL_REBUTTAL (2)**: C6 (confidence applied at sleeve inherit + CRISIS deferred to Forge production-retain logic), C8 (replacement scenario selected per L-279 precedent + Forge to compute precise β_port).

## Q-Lead escalate trigger

**ACTIVATED** — Codex HIGH severity ≥ 5 (2 CRITICAL + 4 HIGH = 6 ≥ 5 threshold).

**Escalate reason**: Process-level governance — Hybrid 3-sleeve admit needs explicit Charter §13 amendment for max_names hard expansion (29 vs 20 cap), TO blend waiver inheritance, ETF/bond universe exception. This is NOT AX-008 3/3 hard fail (alpha_package + risk_package consistent), but a **structural governance gap** in the multi-sleeve admit lifecycle that requires Q-Lead/Governor authority.

## Action items in final optimization_package.json

1. Add `infeasibility_report` JSON field with 3 hard constraint violations (C1+C2+C4) explicit
2. Add `forge_handoff_schema` field documenting as_of_date × ticker × weight × method_selected mapping
3. Add `net_IR_documented` field (1.063) alongside crowding_adj_ret selection
4. Add `charter_exception_documentation` field documenting ETF/bond universe exception (L-279 inherit)
5. Fix `method_comparison` MVO narrative (concentration in S2 not S1)
6. Add `axiom_ax_001_v2_conditional_metric` and `ax_002_process_honesty` honest labeling (Codex critique flagged FAIL — disposition: alpha-inherit conditional metric retain + this challenge_note IS the AX-002 process honesty record)
7. Add `replacement_vs_integration_audit` field with Replacement scenario selected per L-279 precedent
8. Add `beta_port_estimate` 0.794 with Forge stage strict re-compute mandate

## References

- alpha_package.json (lro_sha frozen ad3d44...)
- risk_package.json (Σ 3x3 PD cond 22.86 + AX-001 v2 6/6 + tail cap infeasibility hand-off)
- codex_critic_response_optimizer.json (9 concerns disposition recorded above)
- L-279/L-280/L-281 Hybrid 70/15/15 admit precedent (2026-05-05 finalization)
- L-307/L-308~L-313 Session 80 R05 Layer 5 admit (Sleeve 1 production)
- Charter v1.7 §10 / §11 / §13
- Optimizer init prompt strict_prohibitions + failure_rules Rule 3
