# Forge Challenge Note — WT-S20260504_004

**WT**: WT-S20260504_004 RMT Denoised Σ Forge backtest
**Role**: forge
**Stage**: FORGE_DONE
**Generated**: 2026-05-04 09:30 KST
**Codex Round Status**: round1_async_background_spawn_in_flight (auto-trigger upon draft Write)

## Codex Round 1 Auto-Trigger

`forge_package_draft.json` Write event triggers `codex_round_auto_trigger.sh` PostToolUse hook → background Codex critic spawn (~9-15 min). Response will land at `codex_critic_response_forge.json`. This challenge_note pre-records self-critique anticipating likely critic concerns; final `forge_package.json` will reflect any rebuttals/accepts after Codex response.

## Self-Critique (Forge anticipating Codex)

### Concern A1: M4_baseline_recomputed disagrees with MEMORY.md L-274 carry (SR 1.7477 → 1.5646, MDD -32.05% → -35.32%)

**Severity**: MEDIUM (process integrity, not methodology)

**ACCEPT**: Diagnosis correct — MEMORY.md L-274 carry value is STALE.

**Evidence**:
1. Parent M4 weights at `WT-P20260429_002/weights.csv` shows `weight_str1715=1, weight_cash=0` for early years (e.g., 2004-03-01). The L-274 numerical reference came from a period when STR_1715 base ALSO applied Iter31 regime-conditional cash (10/20/40 by regime), since deprecated (STR_1715 run_all.R line 110: "DEPRECATED. Cash 결정은 M4 outer schedule 단독 담당").
2. Cross-verification: `WT-P20260429_002/forge_may2026/output_full_rebacktest/06_metrics.csv` reports scope=Full n=268 SR=1.5726 MDD=-35.56% — **consistent with my fresh recompute** (SR 1.5646 / MDD -35.32%).
3. Schedule fidelity: I used parent_M4_weights.csv as-is (md5 2f7c8f034103) without re-derivation.

**Action**: forge_package documents memory_carry vs fresh_recompute delta + diagnosis. Q-Lead memory MAY need update post-judge (deferred to L-275+ housekeeping).

### Concern A2: RMT marginal value over M4 alone is small (SR -0.026 / CAGR -1.86pp / MDD 0pp)

**Severity**: HIGH (decision impact)

**ACCEPT**: True observation, requires judge interpretation.

**Mechanism**:
- max(M4_cash, RMT_cash_bridge) is strict OR. M4 schedule binds in 105 of 137 cash months. RMT alone binds in 117 months but only 32 are unique (RMT signals stress when M4 calm).
- In those 32 RMT-unique months, RMT clips returns by avg ~-0.7% per month (cash drag without offsetting tail clip — M4-calm regime).
- RMT-overlay legitimate value: the 50 HIGH_RISKOFF months (combo_str < 0.85) where worst-month tail S1 -18.6% → -13.6% (5pp tail relief). This IS Sharpe-positive vs S1 (canonical Sharpe 1.539 > S1 1.507), but vs M4 alone (1.565), RMT addition is net-negative.

**Implication**: Judge should consider whether the safety net value (tail clipping in extreme months) justifies operational complexity (additional RMT estimation pipeline, lro_params freeze, monthly recompute). **Recommendation**: MONITORING_ONLY verdict appropriate per request decision_rule. RMT vol-target framework retained for future multi-sleeve / multi-strategy contexts where the marginal benefit may be larger.

### Concern A3: HIGH_VOL regime (rmt_scale < 0.75) never triggers — original stratification empty

**Severity**: LOW (analysis design, not result)

**ACCEPT**: Initial RMT-only stratification (HIGH_VOL/MID_VOL/LOW_VOL by RMT scale) had 0 obs in HIGH_VOL since vol_scale_path.csv span is [0.7589, 1.0]. Re-stratified by combined w_combo_str (combined sleeve), which captures both M4 and RMT signals.

**Action**: Final stratification uses HIGH_RISKOFF / MID_RISKOFF / FULL_RISK based on combined sleeve weight. 50/62/155 obs distribution provides meaningful tail vs body decomposition.

### Concern A4: AX-008 tally only 1/3 (forge only)

**Severity**: HIGH (architecture mandate)

**PARTIAL**: Forge stage cannot complete 2/3 alone. Codex Round 1 spawning async; Architect re-verification deferred to judge stage. Per AX-008, minimum 2/3 required AT STAGE GATE — not at every artifact emission. Judge will evaluate triangulation final.

**Lineage carry**:
- Alpha: codex round 1 PARTIAL_ACCEPT (codex_critic_response_alpha.json)
- Risk: codex round 1 REJECT → round 2 waiver (codex_critic_response_risk.json + risk_challenge_note.md)
- Optimizer: codex round 1 REJECT (cond=412 inherited) → waiver (optimizer_challenge_note.md, codex_critic_response_optimizer.json)
- Forge: round 1 background async; this challenge_note pre-records anticipated critique.

**Action**: Final forge_package emits `ax_008_tally.current_count: "1/3 (forge only)"` honestly + judge stage delegated to complete triangulation.

### Concern A5: Schedule density 267/268 = 0.9963 vs request 268m

**Severity**: LOW (alignment convention)

**ACCEPT**: weight schedule covers 267 sig_dates (2004-01..2026-03), STR_1715 base ret covers 268 (2004-02..2026-05). Last ret month (May 2026) has no overlay weight — May 2026 is live forward, governed by separate `production_weights/20260501_weights_cap_0p20.csv` snapshot (n_active=18, scale 0.7596, cash bridge 0.2404).

Per Schedule Fidelity Mandate (Charter §9): density 0.9963 ≥ 0.95 threshold PASS. No fabrication. infeasibility_report empty (no 5-day windows missing).

### Concern A6: Sharpe formula conformance (Charter v1.4 §12)

**ACCEPT**: My `compute_metrics()` uses `mean(rets) / sd(rets) * sqrt(12)` directly (Rf=0). For canonical M4+RMT: SR=1.5391. This matches the Backtest Contract v1.0 / Charter §12 formula. PerformanceAnalytics SortinoRatio used for Sortino (annualized × sqrt(12)).

### Concern A7: Cost double-counting risk

**ACCEPT_NO_ISSUE**: STR_1715 base ret_net already cost-net 15bps both sides (cost_model_version v2.3_kr_retail_15bps). Sleeve transitions w_str: 1 → 0.85 → 1 do NOT trigger additional STR_1715 internal rebalance (the 18 underlying stocks unchanged); only the outer cash% changes. Recommendation_only WT — no production trade execution. Cost = STR_1715 internal cost only. No double-count.

## Q-Lead Escalation Triggers

- HIGH severity ≥ 5: NO (1 HIGH = A2 Sharpe-negative vs M4 alone, 1 HIGH = A4 AX-008 tally)
- AX hard FAIL ≥ 3: NO
- PIT C1 violation: NO (lookahead_prevention C1 expanding + C2 t-1 lag + C9 weight at sig_date d → ret [d, next_d) ALL passed audit)

**No Q-Lead escalation required**. Judge stage continues per workflow.

## Final Package Decision Rule Verdict

**Verdict**: MONITORING_ONLY (matches request decision_rule §): RMT statistical quality OK + trading damage thin (vs M4 alone). Canonical M4+RMT achieves vs S1 baseline:
- Sharpe +0.032 (1.5068 → 1.5391)
- MDD relief 6.37pp (-41.69% → -35.32%)
- Vol -2.2pp (26.4% → 24.2%)
- CAGR drag -2.7pp (43.2% → 40.5%)

But vs M4 baseline alone (SR 1.5646 / MDD -35.32%): RMT adds drag without MDD improvement. RMT value lies in worst-month tail clipping (HIGH_RISKOFF S1 -18.6% → combo -13.6%), but this is M4-calm RMT-stress months only.

**Action recommended to judge**: Pass forge audit (integrity WARNING acceptable, all PIT/cost/schedule checks PASS). Recommendation_only WT — no governor admit, no book_state write. Lineage frozen for potential future revisit if multi-sleeve / multi-strategy context emerges where RMT marginal value increases.

## Hash Audit Confirmation

All 9 input artifacts hash-matched start vs end (see lro_hash_audit.csv). Pure function compliance verified.

---
*Auto-recorded prior to Codex Round 1 response. Final forge_package.json emitted with codex_round_status reflecting actual response upon Codex completion.*
