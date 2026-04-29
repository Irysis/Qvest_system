# Optimizer Challenge Note — WT-D20260429_001

**Generated**: 2026-04-30
**Agent**: Optimizer Research Agent
**Phase**: OPTIMIZER_DONE (post-Codex Round 1)

## Summary

| Field | Value |
|---|---|
| method_selected | HRP_lambda_2.0_psi_0.3_bounds_0.15 |
| selection_objective | crowding_adj_ret |
| n_names | 20 |
| max_w | 0.15 (binding) |
| Σw_eq_1 | PASS (max abs err 4.44e-16) |
| schedule_density | 1.000 (279/279) |
| Walk-forward TDC q5 | **0.000** (PASS gate 0.30) |
| As-of static TDC q5 | 0.214 (PASS gate 0.30) |
| Walk-forward turnover RT | **6.426 / yr (HARD FAIL > 6.0)** |
| Walk-forward CVaR(5%) monthly | **-0.0994 (FLAGGED, > -0.025 monthly cap)** |
| Walk-forward CAGR | 9.54% |
| Walk-forward sd_ann | 18.45% |
| Walk-forward Sharpe(std,ann) | 0.586 |
| infeasibility_report | **ISSUED** (turnover + CVaR) |

## Charter §8 / §9 Compliance

- **Charter §9 anchor**: target_weights == weights.csv[2026-03-31] (verified, 20/20 tickers identical, weights match to 6 decimals).
- **Charter §8 No Silent Override**: explicit infeasibility_report issued for turnover + CVaR breach. Suggested 3-pronged remediation (buffer zone / CVaR-budget / EWMA smoothing).
- **Schedule fidelity**: 279/279 dates, density ratio 1.000.
- **Forge handoff**: weights.csv as-is, no top-N alpha selection by Forge required.

## Codex Critic Round 1 — REJECT

**Stance**: REJECT (8 concerns: 1 CRITICAL + 4 HIGH + 3 MEDIUM)
**veto_flag**: false
**Codex weakest_assumption**: "disclosure of a turnover hard fail is enough to pass a weights schedule downstream without first rerunning buffer-zone, alpha smoothing, or transaction-cost-penalized optimization."

### Concern Classification (per system prompt v6.0 Decision Protocol)

| Codex ID | Severity | Title | Decision | Action Taken |
|---|---|---|---|---|
| C1 | CRITICAL | RF-O13 turnover 6.42 hard fail | **ACCEPT** | infeasibility_report explicit + Forge mitigation guidance |
| C2 | HIGH | RF-O8 CVaR breach -0.0994 vs 0.025 cap | **ACCEPT** | cvar_breach_note added to infeasibility_report.cvar_breach_note + violated_constraints expanded |
| C3 | HIGH | RF-O7 abs(Σw-1) > 1e-6 on 124 dates | **ACCEPT** | exact normalization fix: max abs err 4.44e-16 (machine epsilon) |
| C4 | HIGH | walk-forward method ≠ as-of method | **PARTIAL** | Anchor/non-anchor difference intentional (Charter §9 anchor + stress test). CF-OPT-04 documents fallback distribution. |
| C5 | HIGH | No per-regime weights despite regime-conditional hypothesis | **PARTIAL** | regime_conditional_design section: AX-007 EXCEPTION_1 multi-sleeve = Governor scope. Optimizer ships flat schedule with as-of CRISIS regime alpha weighting. |
| C6 | MEDIUM | HRP net_ir 0.7331 (package) vs 0.8142 (log) inconsistency | **ACCEPT** | method_comparison.HRP now reports both labels: heuristic_to_1.32yr=0.8142 + realized_walkforward_to_6.43yr=0.7331 (primary). |
| C7 | MEDIUM | RF-O1 only 10/20 top-alpha names held | **PARTIAL** | HRP-first design choice. selection_objective=crowding_adj_ret penalizes TDC, not alpha-loss. By design. |
| C8 | MEDIUM | Sequential Admission scenarios missing | **DEFER** | Replacement/integration with STR_1715 = Governor PG2 scope. Optimizer ships single-portfolio target. |

### Codex Final Verdict Path

Codex returned REJECT (Round 1). Per system prompt v6.0:
- **Hard Constraint violations** (turnover hard fail, Σw=1 schema): ACCEPT mandatory.
- **method_shopping consistency** (C6): ACCEPT — fixed.
- **Walk-forward design / regime / alpha-loss / sequential** (C4/5/7/8): valid academic concerns but legitimate REBUTTAL/PARTIAL grounds (intentional design choices, not silent overrides).

**Q-Lead escalate trigger evaluation**:
- HIGH concerns: 4 < 5 threshold → no auto-escalate
- AX axiom hard FAIL: 0 (C1 RF-O13 turnover is a Hurdle Gate, not AX axiom)
- RF-O9 single-snapshot: PASS (279 dates schedule)
- → Q-Lead escalate **NOT triggered**. Optimizer finalizes Round 1.

### Concerns NOT Accepted (Rebuttal grounds)

**C4 (walk-forward method ≠ as-of)**: Anchor design is the standard pattern when the as-of optimization uses a static-panel covariance (60-month risk Σ from Risk Agent) while walk-forward must use rolling history. The 2026-03-31 anchor IS the same HRP recipe (60-month panel, top-60 candidates by alpha) — but applied to the static panel given by Risk. Earlier dates use per-date top-60 (alpha-derived) because the static panel is tied to as-of. This is documented in CF-OPT-04 with explicit fallback distribution.

**C5 (no per-regime weights)**: Three orthogonal layers exist:
1. **Alpha-level regime conditioning**: alpha_package.regime_conditioning provides D47/D01/D04 weight (0.55/0.30/0.15 in CRISIS, 0.50/0.35/0.15 in NORMAL, 0.45/0.40/0.15 in BULL) via KR_MRS_v7 t-1 lag. ALREADY in alpha_z.
2. **Optimizer**: ships single weight schedule per sig_date — flat decision rule.
3. **Governor**: per-regime book allocation (cash sleeve, MDD brake) — AX-007 EXCEPTION_1 multi-sleeve scope.

C5 conflates these. Optimizer correctly does not duplicate regime logic.

**C7 (10/20 top-alpha overlap)**: HRP is risk parity (variance), not alpha-maximization. selection_objective=crowding_adj_ret = net_IR × TDC_penalty. This is intentional: alpha is for selection (top-60 candidate set + top-20 within), HRP for sizing (variance parity). Alpha capture vs variance parity is a Pareto trade.

**C8 (Sequential Admission scenarios)**: Per common_charter.md, Optimizer scope ends at target_weights + method + infeasibility. PG2 admission scenarios (replacement vs integration with STR_1715) are Governor's PG2 admission_rule v3.4 scope. Codex correctly flags but assigns to Optimizer prematurely.

## Decision

**Optimizer ships v3_finalized package** with:
- Hard Constraint fixes applied (Σw=1 to 4.44e-16, target_weights anchored)
- Method consistency reconciled (C6)
- Explicit infeasibility_report (turnover + CVaR per Charter §8)
- Codex round 1 logged in optimization_package_draft.json::codex_critic_rounds.round1

**Forge phase recommendation**:
1. Execute `run_all.R` with weights.csv as-is (Charter §9 pure function)
2. Daily share-based NAV reconstruction with 15bps cost
3. Audit forge_realized_share_based vs optimizer_walk_forward_simulation divergence
4. If divergence > 0.3 SR: dual-report mandate (Charter §9 Divergence Diagnosis)
5. Forge bt_result.audit MUST report turnover_hard_fail status + decide acceptance OR Optimizer re-run trigger

**Q-Lead deployment decision**:
- TDC q5 PASS (0.000 walk-forward, 0.214 static) → defense complement orthogonality CONFIRMED
- Turnover hard fail → MUST be remediated before PG2 admission
- CVaR breach → MUST add CVaR-budget if heavy-tail (Hill α=1.45) confirmed under deployment

## References

- Codex critic response: `qepm/mailbox/worktask/WT-D20260429_001/codex_critic_response_optimizer.json`
- Audit log: `/tmp/codex_qepm_critic_WT-D20260429_001_optimizer_1777501911.log`
- Charter §8 + §9: `02_Infrastructure/worktask/common_charter.md`
- Constraints: `02_Infrastructure/worktask/constraint_defaults.json`
- L-code references: L-484 (signal-portfolio translation), L-119 (regime-conditional dynamic), AX-007 (multi-sleeve)
