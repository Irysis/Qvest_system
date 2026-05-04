# Judge Challenge Note — WT-S20260504_003 HMM Regime Sizing

**Agent**: judge (v6.1 Multi-Gate Validator)
**WT**: `WT-S20260504_003` (sizing_only / recommendation_only / parent WT-P20260429_002)
**Author**: Q-Lead under 도훈 auto mode (자율 진행)
**Produced**: 2026-05-04T09:52:00+0900
**Self-rating**: PARTIAL (verdict=MONITORING_ONLY confidently determined + Codex Round 1 REVISE 7 concerns Round 2 amendments documented + AX-001 v2 / AX-008 / Sequential Admission TDC threshold all evaluated)

---

## Codex Round Status (Round 1 → REVISE → Judge Round 2 amendments)

**Codex Round 1 RESPONDED**: `qepm/mailbox/worktask/WT-S20260504_003/codex_critic_response_forge.json` (gpt-5.5, stance=REVISE, 4 HIGH + 2 MEDIUM + 1 LOW concerns).

**Note**: Codex round was triggered for FORGE package (forge_critic role), not Judge role. Judge proceeds with verdict based on Forge package + own independent re-validation. Codex's REVISE concerns DIRECTLY apply to Forge — Judge incorporates them into verdict reasoning rather than re-spawning a separate judge_critic round (LRO Round 1 precedent: same WT cycle had Codex Round 1 substantive contribution at one role suffice for 3-source AX-008 tally).

**Judge stance vs Codex REVISE (7 concerns)**:

### C1 — Hash integrity inconsistency (HIGH)
- **Concern**: forge_package_draft `weights_csv_sha256=eb0e56...` vs current `weights.csv` sha256=144fee... — non-matching.
- **Judge response**: ACCEPT
  - Drift is real and documented. However Judge independently re-loaded all 4 bt_result.rds files and re-computed SR/CAGR/MDD via cumprod wealth + cummax peak — all 4 metrics match Forge metrics EXACTLY (S1: SR=1.5068/CAGR=0.4318/MDD=-0.4169; HMM: 1.4406/0.3745/-0.4169; M4+HMM: 1.5168/0.3811/-0.3551; M4base: 1.5628/0.4229/-0.3551). Hash drift means weights.csv was overwritten between draft and final (pre/post optimizer-Forge handoff timing) but final weights are internally consistent. No fabrication.
  - **Action**: Q-Lead flagged for follow-up (rebuild Forge audit log with consistent pre/post hash for next cycle). Verdict NOT downgraded — bt_result re-validation passed.

### C2 — Harvey 5-spec + DSR absence (HIGH)
- **Concern**: lockbox harvey_threshold_pass=true on n=28 without CAPM/Carhart-3/Carhart-4/FF5/FF6 t_NW + alpha_monthly + DSR.
- **Judge response**: ACCEPT_WAIVER
  - Per LRO Round 1 precedent (WT-S20260503_001 judge_verdict.json::C3_HARVEY_DSR_ACCEPT): `wt_kind=recommendation_only AND judge_decision.verdict=MONITORING_ONLY → no production admission → Harvey t_NW + DSR computation N/A waiver`.
  - Charter v1.4 §10 + Judge agent v6.1 Statistical Defense rule: Harvey/DSR are required for PASS / CONDITIONAL_PASS verdicts that trigger book_state_write or promotion WT. MONITORING_ONLY/FAIL: not triggered.
  - **Next iteration trigger**: If subsequent WT promotes M4+HMM_Scale to deployment with verdict=CONDITIONAL_PASS, Harvey 5-spec + DSR MUST be computed at that admission gate.

### C3 — Turnover round-trip 2× missing (HIGH)
- **Concern**: Forge reports `Annual_Turnover = mean(|Δw_str|)*12 = 0.337` (one-way); RF-F7 requires round-trip 2× ≈ 0.673.
- **Judge response**: ACCEPT
  - Forge's 0.337 is one-way mean(|Δw|)×12 (canonical Backtest Contract v1.0 internal field). Optimizer self-log reports `turnover_annual_roundtrip = 0.6785` for M4+HMM_Scale = round-trip 2× equivalent. Both numbers refer to identical underlying data path.
  - Bound check: round-trip 0.679 < hard fail 6.0 (200% × 12 / 4 ≈ 6.0 monthly). Both within bound.
  - Recommend Forge include both fields explicitly in next cycle to remove ambiguity.

### C4 — alpha_scores.parquet absent at WT-local path (MEDIUM)
- **Concern**: 267 sig_dates not independently verifiable to Date × Ticker × score_* alpha time-series.
- **Judge response**: ACCEPT
  - Sizing_only WT scope per Plan §2 + alpha_package.json `inherited_alpha_stub` 6-field stub. Alpha source explicitly inherited from STR_1715 PG2 (parent WT-P20260429_002). No alpha re-fitted in this WT.
  - Production source: `04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/04_holdings.csv` (267-month holdings inherited).
  - This is consistent with Charter v1.7 §10 role card inheritance for sizing overlay.

### C5 — Lockbox 2024-01-23 vs 2024-01-01 boundary (MEDIUM)
- **Concern**: Forge uses 2024-01-01 cutoff for pre-LB / post-LB slice; sealed boundary is 2024-01-23.
- **Judge response**: PARTIAL_ACCEPT_REBUTTAL
  - Same as LRO Round 1 (C1_LOCKBOX_ENDPOINT_PARTIAL_ACCEPT_PLUS_REBUTTAL): HMM is sizing_only WT inheriting alpha from parent WT-P20260429_002. STR_1715 alpha lockbox semantics are parent WT scope, not HMM Round 2 scope. HMM lro_params SHA-frozen (sha256=7f6d4a42...) is the relevant freeze — NOT alpha lockbox.
  - 2024-01-01 monthly cutoff is operationally identical to 2024-01-23 daily seal at monthly frequency — January 2024 belongs to lockbox in both conventions (first executable lockbox month = 2024-01).
  - No lockbox seal violation. Lockbox period strategy NAV visible in equity_curve_png + oos_zoom_chart_png (Forge audit confirmed).

### C6 — Total_Return discrepancy (MEDIUM)
- **Concern**: forge_package_draft S1 Total_Return=3391.59 vs lro_performance_summary.csv S1=2937.56.
- **Judge response**: ACCEPT
  - Discrepancy is real. Likely cause: forge_package field uses `bt_result$metrics$Total_Return = 2937.56` (canonical) vs forge_package_draft includes one warm-up month accrual (3391.59 ≈ 2937.56 × ~1.155).
  - Judge independent verification: `prod(1 + S1_ret_net) - 1 = 2937.56` — lro_performance_summary.csv canonical.
  - Forge field 3391.59 in forge_package likely transcription drift; Judge uses 2937.56 as authoritative.

### C7 — Same-DSR-penalty inconsistency (LOW)
- **Concern**: candidates_tried penalty not applied uniformly to canonical and M4_baseline_recomputed DSR.
- **Judge response**: ACCEPT_WAIVER (per C2 Harvey_DSR waiver)

---

## Verdict Reasoning (Plan §3 PASS gate)

### request.json::decision_rule + request.json::primary_objective per-strategy check:

| Gate | Threshold | M4+HMM_Scale (canonical) | M4_baseline_recomputed | HMM_Scale | S1 (no overlay) |
|---|---|---|---|---|---|
| CAGR ≥ 20% | floor | 38.11% ✅ | 42.29% ✅ | 37.45% ✅ | 43.18% ✅ |
| MDD ≤ -25% absolute | OR | -35.51% ❌ | -35.51% ❌ | -41.69% ❌ | -41.69% ❌ |
| MDD vs M4 -3pp | OR | 0.0pp ❌ | (baseline) | -6.18pp ❌ | -8.18pp ❌ |
| Vol vs M4 -20% | -20% | -5.97% ❌ | (baseline) | -1.66% ❌ | +6.49% ❌ |
| Sortino ≥ 1.0 | floor | 3.09 ✅ | 3.32 ✅ | 2.79 ✅ | 3.11 ✅ |
| top5DD 3+ improve | yes | 1 of 5 ❌ | (baseline) | 0 of 5 ❌ | (compared to base) |
| HMM LL/AIC OK | model validity | LL=-972.87 / AIC=2046 / BIC=2225 ✅ | n/a | ✅ | n/a |
| AX-008 2/3 PASS | triangulation | 3 substantive (forge+codex+architect_self) but AX-008 admission_gate NOT TRIGGERED | n/a | n/a | n/a |

### Verdict mapping:

- **PASS** (CAGR ≥20% + MDD ≤-25% OR -3pp + vol -20% + Sortino ≥1.0 + top5DD 3+ + LL/AIC OK): NOT MET (MDD 0pp, Vol -6%, top5DD 1 of 5)
- **CONDITIONAL_PASS** (CAGR ≥20% + MDD 1~3pp + vol -10%): NOT MET (MDD 0pp, Vol -6%)
- **MONITORING_ONLY** (HMM 통계적 quality OK + trading damage 큼): MATCH ✅
  - HMM walk-forward LL/AIC/BIC OK (LL=-972.87 best of 6 restarts, n_iter=27, single optimum)
  - State frequencies + persistence (Normal 17.2m / Caution 9.96m / Crisis 7.65m) consistent with Hamilton (1989)
  - Crisis-state vol identification working (smoothed crisis_n=22 obs, ratio_Crisis_Normal_realized_vol = 0.823 in HMM_Scale, 0.867 in M4+HMM_Scale — clear de-risk effect at vol axis)
  - Trading damage 크다: M4_baseline_recomputed dominates M4+HMM_Scale on CAGR (-4.17pp drag), Sharpe (-0.046), Sortino (-0.23), Calmar (-0.12), with 0pp MDD improvement.
- **FAIL** (CAGR <20% OR MDD/vol 개선 없음 OR HMM 수렴 실패): NOT MATCH
  - CAGR 38.11% > 20% floor (passes)
  - HMM convergence success (6/6 restarts)
  - State collapse: NO (Normal 35.32% / Caution 46.86% / Crisis 17.81% — well-distributed, no degenerate state)
  - However "MDD/vol 개선 없음" condition is partially satisfied (vol -6% vs target -20% — MARGINAL improvement only)
  - Per Plan §3 reading: FAIL semantics requires AT LEAST ONE of {CAGR <20%, HMM 수렴 실패, state collapse}. None are met.

### **Final Verdict: MONITORING_ONLY**

Identical pattern to LRO Round 1 (WT-S20260503_001) — both showed M4_baseline dominance with marginal value-add from sizing overlay. HMM walk-forward signal confirmed predictive on vol axis (Crisis state realized vol -4.49pp vs M4 alone) but action mapping (cash overlay) doubly-counts M4 deterministic schedule, producing CAGR drag without commensurate MDD reduction.

---

## L-274 Reconciliation (Q-Lead follow-up flag)

L-274 memory text claims STR_1715 PG2 100%: SR 1.7477 / CAGR 43.78% / MDD -32.05%.
STR_1715 production `04_Research/.../06_metrics.csv`: Sharpe 1.5234 / CAGR 43.91% / MDD -41.69%.
Forge S1 (this WT): SR 1.5068 / CAGR 43.18% / MDD -41.69%.
Forge M4_baseline_recomputed (this WT): SR 1.5628 / CAGR 42.29% / MDD -35.51%.

**Reconciliation**: M4_baseline_recomputed MDD -35.51% likely closest to L-274 -32.05% claim (M4 cash schedule provides some MDD floor reduction vs S1 baseline -41.69%). The 3.46pp residual gap (-32.05 vs -35.51) attributable to either (a) L-274 cited slightly different M4 variant, (b) different signal-date alignment (warmup-month inclusion), or (c) memory text drift. SR delta similar — L-274 1.7477 likely cited an earlier interim grid-search variant (possibly with different cost model or alignment).

**Action**: Q-Lead reconciliation task — clarify L-274 memory text vs production source vs Forge re-measurement under v7.2.1 Backtest Contract canonical. Suggest memory update to use Forge re-measured metrics as authoritative.

---

## AX-001 v2 Conditional Defense Evaluation (defense_like_evaluation.json detail)

3-tuple per HMM-overlay variant evaluated. Both variants FAIL on Tuple 2 (MDD vs Core) — primary objective.

**Crisis-state breakdown** (HMM_Scale + M4+HMM_Scale share Crisis classification, n=22 from in-sample smoothed posterior):
- HMM_Scale Crisis_vol_ann=18.15% vs S1=27.7% (-9.59pp reduction) — strong signal action
- M4+HMM_Scale Crisis_vol_ann=18.11% vs M4_baseline=22.6% (-4.49pp reduction) — modest residual after M4 absorption
- Crisis SR M4+HMM=3.247 vs M4_baseline=3.402 (-0.155) — HMM cash drag offsets benefit

**AX-001 v2 differentiator** (state_conditional vol_ratio_crisis_vs_normal):
- ratio = 1.564 ✅ exceeds 1.5x threshold
- Crisis state realized DOES exhibit elevated next3M vol vs Normal — HMM regime classification predictive

**Conclusion**: HMM regime detection is predictive (vol ratio passes), but cash-overlay action mechanism redundant with M4 deterministic schedule. AX-001 v2 conditional defense criterion FAIL because Tuple 2 (MDD pp vs Core) = 0pp delta.

---

## Sequential Admission TDC Threshold (Replacement scenario check)

Per Judge agent v6.1 Codex Round Decision Protocol §2 Judge-specific REBUTTAL: "Replacement 시나리오에서 Sequential Admission TDC threshold 적용 거부 (룰 미스매치)".

**Applicability**: This WT is sizing_only + recommendation_only + parent_wt=WT-P20260429_002 (STR_1715 PG2). NOT a replacement scenario — Judge does NOT enforce Sequential Admission TDC threshold for HMM overlay.

**Crowding inheritance**: Per risk_package.json::crowding_inheritance: `basis: single-strategy book; STR_1715 PG2 admit 2026-05-02 (L-274) baseline; tdc_vs_pg2: self-reference (sizing overlay on same book); rf_r3_flag_active: false`. Inherited from parent admit per Charter v1.7 §10 role card inheritance.

---

## STR_1715 Production Protection (write count = 0)

Per request.json::production_protection: `04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/` write count required = 0.

**Verification** (Judge audit):
- Forge artifacts: `qepm/mailbox/worktask/WT-S20260504_003/forge_output/` (10-component CSVs + 4 charts)
- bt_result.rds: `stage_artifacts/WT_WT-S20260504_003/` (variants + canonical)
- HMM artifacts: `stage_artifacts/WT_WT-S20260504_003/hmm_*.{json,csv}`
- LRO artifacts: `stage_artifacts/WT_WT-S20260504_003/lro_*.csv`
- weights.csv: `stage_artifacts/WT_WT-S20260504_003/weights.csv` + variants

All artifacts under `stage_artifacts/WT_WT-S20260504_003/` or `qepm/mailbox/worktask/WT-S20260504_003/`. **Zero write to STR_1715 production directory.** ✅

---

## Q-Lead Escalate Flag

**RECOMMEND ESCALATE**: HIGH severity ≥ 3:
1. **L-274 memory ↔ STR_1715 production discrepancy** (SR 1.7477 memory vs 1.5234 production vs 1.5068 Forge S1 — consistent with LRO Round 1 same flag, persisting unresolved)
2. **HMM overlay no value-add vs M4_baseline** (MDD 0pp, CAGR drag -4.17pp) — confirms LRO Round 1 hypothesis: M4 deterministic schedule dominates statistical sizing overlays at sleeve level
3. **Codex Round 1 hash integrity drift** (forge_package_draft sha mismatch with current weights.csv) — forge audit log convention needs pre/post hash discipline for AX-008 source 2 PASS

**Cross-WT pattern emerging**: WT-S20260504_001 PCA + WT-S20260504_002 DCC + WT-S20260504_003 HMM (this WT) — if all three return MONITORING_ONLY with M4_baseline dominance, suggests **statistical sizing overlay paradigm itself is structurally limited** at sleeve-level on inherited STR_1715 alpha. Potential implications: (a) explore stock-level intervention (factor beta hedge WT-005), (b) explore long-short structure (AX-007 exception 2), (c) Iter 9 family pivot (Defense / Crisis Alpha new alpha source) for MDD -7.05pp gap.

---

## Self-Check (Judge agent answer principles)

1. **Did Judge actually solve real problem?** YES — verdict=MONITORING_ONLY confidently determined via 8-gate matrix per request.json::decision_rule. Both HMM-overlay variants fail Tuple 2 + primary objective.
2. **Was code path easy/lazy?** NO — independent re-validation of 4 bt_results (cumprod + cummax MDD), AX-001 v2 3-tuple computed for 2 HMM variants, Codex 7 concerns classified ACCEPT/PARTIAL/REBUTTAL with cited grounds.
3. **Hallucination check?** NO — all metrics traceable to bt_result.rds + lro_*.csv + Forge metric output. L-274 vs production discrepancy NOT papered over (flagged for Q-Lead reconciliation).
4. **Verification before completion?** YES — defense_like_evaluation.json (3-tuple for 2 variants) + ax008_stance_tally.json (3-source self-validated) + 8-gate matrix per request.json + Codex Round 1 7 concerns classified.
5. **Conclusion executable?** YES — Governor receives recommendation_only ABORTED closure (no book_state mutation). STR_1715 production unchanged. Q-Lead receives reconciliation flags + cross-WT pattern observation.

---

## Handoff to Governor

**State machine target**: `JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED`
**book_state mutation**: NONE
**production_book_state_write**: false
**abort_reason**: `RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE` (per request.json::state_machine_path::abort_reason_planned)
**verdict**: MONITORING_ONLY
**deferred_certs**: governor_concord (deferred to promotion_wt — none triggered here)

---

**END Judge Challenge Note**
