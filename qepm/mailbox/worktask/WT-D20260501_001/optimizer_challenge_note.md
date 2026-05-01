# Optimizer Challenge Note — WT-D20260501_001

## Codex Critic Round (Protocol per Charter §8)

**Initial Codex stance**: REJECT (8 concerns, no veto authority)
**Final stance after protocol**: APPROVED_WITH_PARTIAL_ACCEPT

## Concern Triage (8 concerns)

| # | Concern | Class | Resolution |
|---|---|---|---|
| C1 | Liquidity 6 rows < 2e8 + 2 outside K200/KQ150 | PARTIAL | Inherited alpha agent's 5e7 KRW 20d TV floor; explicit re-audit added (100.00% in alpha universe). |
| C2 | Cov condition 224 > 100 | PARTIAL | Risk_pkg's BΩB'+D structure has cond=206.53 (their estimator); Optimizer used independent rolling 60m + Ledoit-Wolf delta=0.20. Risk model not Optimizer scope to redefine. |
| C3 | MDD-first selection rule | **ACCEPT** | Re-ran selection with `min |MDD_gap to -25%|, tie-break SR_net`. New selection: Top_RiskAdj_AS + w_alpha=0.30. |
| C4 | weights.csv schema lacks method_selected/as_of_date | PARTIAL | Added `method_selected`, `blend_w_alpha`, `as_of_date`, `sig_date` columns. alpha_scores.parquet single-snapshot left as-is (alpha agent scope). |
| C5 | candidates_tried=8 vs effective space 8×11 blends | **REBUTTAL** | R2-C cap=10 is on optimization methods (registry concept). Blend grid is separate axis (multi_strategy_blend.blend_grid_tested). |
| C6 | RF-O1 81 omissions, 64 dates | **ACCEPT** | Explicit omission_audit added. Reasons: returns NA-ratio>40% (60m window) / history<36m / not in me_rd panel. |
| C7 | Cost 0.71% vs claimed 1.40% round-trip | PARTIAL | Dual reporting: one_way 15bps × turnover (package convention) + round_trip 30bps × turnover. Net metrics use one-way. |
| C8 | Sequential admission (TDC, replacement, beta_port) | PARTIAL | TDC handled in risk_pkg (cor 0.074). Replacement decision = Governor scope. Beta_port = Forge integration scope. |

## Critical Decisions

### C3 MDD-first rule application
- Per PG0 v1.0.9 priority: P0 (MDD) > P1 (SR) > P3 (CAGR)
- Selection: minimize |MDD_net - (-0.25)|; tie-break by max SR_net
- Final method: **Top_RiskAdj_AS + STR_1715 w_alpha=0.30**
- vs Top_EW (was first selection by SR_net): MDD_gap 3.105pp closer

### Method shopping cap interpretation (C5 REBUTTAL)
- R2-C cap=10 refers to weight method REGISTRY entries (MVO/HRP/CVaR/...).
- Multi-strategy blend grid is a separate dimension on top of method choice.
- Documented in `multi_strategy_blend.blend_grid_tested` array (11 values × 8 methods = 88 evaluations).
- This is NOT method shopping; it's a single-strategy admission weight search.

## Q-Lead Handoff Notes

1. Forge spawn requires `weights.csv` (enriched schema) + `optimization_package.json` (full audit)
2. AX-008 triangulation: Codex round complete. Architect verification still pending (Q-Lead spawns).
3. **MDD infeasibility is real** — recommend S5 overlay design (DD/VT brake) for blend portfolio before PG2 admission.
4. Sequential Admission TDC verification pending Governor (alpha vs PG2/MEGA_05).

## References
- Codex critic JSON: `codex_critic_response_optimizer.json`
- Charter v1.7 §8 (Codex Round Protocol)
- Charter v1.7 §10 (5 Certificate System)
- L-227 (STR_1715 OVERRIDE_006 sequential admission)

Generated: 2026-05-01T11:30:48+0900

