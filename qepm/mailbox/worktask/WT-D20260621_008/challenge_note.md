# Challenge Note — WT-D20260621_008 (M33 Overnight Return Momentum)

**Codex Critic Round (v6.0)** — role=alpha, model=gpt-5.5 xhigh, stance=**REVISE** (veto_flag=false)

Codex confirmed the core no-harvest conclusion is "directionally supported by negative IC,
failed portfolio t-stat, flat deciles, and failed Calmar." REVISE was for auditability/wording,
not for the verdict. Each concern classified per the v6.0 Decision Protocol (Charter §8).

## Concern resolution

| ID | Sev | Classification | Resolution |
|----|-----|----------------|------------|
| C1 | HIGH | **ACCEPT** | alpha_scores.parquet was a single-date snapshot (Iter-4 failure mode). FIXED: now a full Date×Ticker×score time-series (80,078 rows, 256 dates, 824 tickers, 2005-02 to 2026-05). |
| C2 | HIGH | **PARTIAL + REBUTTAL** | (a) Path mismatch ACCEPTED — artifacts documented under stage_artifacts/WT_WT-D20260621_008 (canonical for this WT). (b) Missing risk_package/optimization_package/weights.csv/covariance.parquet REBUTTED: the **alpha agent is hard-blocked from producing covariance/weights** (agent_role_guard). Their absence is CORRECT, not a defect. AX-008 triangulation for THIS stage = canonical_screen_bt (Forge-style contract path) + Codex critic + decile/orthogonality cross-checks; full 3-source 2/3 is a pipeline-level (post-risk/opt) check, N/A at alpha stage. challenge_note + lineage added. |
| C3 | HIGH | **ACCEPT** | No softening. Verdict is explicit FAIL: all hard gates FAIL (PORT_t -0.57, calmar 0.091), all advisory FAIL (rank_ic -0.012, ICIR -0.09, IC_t -1.43, monotonicity 0, sub_stability 0.33). verdict="SCREEN_ROUTE_NONE" / hard_gates all pass=FALSE. |
| C4 | MEDIUM | **REBUTTAL (with audit)** | Codex's "129 sub-2e8 in top-20" reconstructed top-20 WITHOUT the liquidity pre-filter. canonical_screen_bt applies `is.na(adv)|adv>=2e8` BEFORE top-N (line 54-58). Re-audited with the actual filter: **0 top-20 obs sub-2e8, 0 adv-NA bypass** (adv NA frac = 0; 20d ADV computed for 100% of eligible obs). Backtest IS clean under the floor. Evidence: liquidity_audit.json. |
| C5 | MEDIUM | **ACCEPT (wording)** | turnover_annual=11.41 is two-way (sum\|Δw\|, buy+sell) = **1141%** as a percent, which **exceeds the 1100% two-way screening cap**. My "under cap" claim was WRONG and is corrected. One-way basis = 570%. Moot for graduation (PORT_t already FAILs hard), but the factual claim is fixed. |
| C6 | MEDIUM | **ACCEPT** | Construction code shipped to stage_artifacts (m33_construction_pipeline.R, m33_base_screen.R, m33_decile.R, m33_orthogonality.R, m33_graduation.R) — Date<=sig_date enforcement in build_scores() now independently auditable. |
| C7 | LOW | **ACCEPT (wording)** | "fully deflated grid audit" language removed. 26/54 cells ran (process killed at cell 22 by OneDrive paging/memory + 4 bracketing single-runs covering all parameter extremes). DSR ledger note added: sweep argmax PORT_t=+0.46 << 2.95, so DSR deflation is moot. Wording now: "26 cells covering all extremes, all <0.5 PORT_t; conclusion robust, grid not exhaustively deflated." |

## Self-rationalization audit (auto-detection)
Grep of REBUTTAL text (C2, C4) for {미미, 관행적, 실무적, 보수적이면, 대부분 결과 동일}: **0 hits**.
C4 rebuttal rests on a code-line citation (canonical_screen_bt:54-58) + re-run quantitative audit
(0 sub-2e8), not on hand-waving. C2 rebuttal rests on an explicit role-boundary (agent_role_guard
hard-block on covariance/weights), not on dismissal.

## Escalation check
HIGH concerns = 3 (C1 fixed, C2 partial/rebutted, C3 accepted-no-softening). None is a PIT C1
lockbox/lookahead violation. AX axiom hard FAIL count = 0 (AX-007 PASS, AX-003/4/5 N/A). Codex
stance = REVISE (not REJECT), veto_flag=false. → **No Q-Lead auto-escalate trigger met.** Revisions
applied in-package; finalize.
