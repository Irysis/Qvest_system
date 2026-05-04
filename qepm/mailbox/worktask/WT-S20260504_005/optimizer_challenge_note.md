# Optimizer Challenge Note — WT-S20260504_005

**Task**: STR_1715 Factor Beta Hedge — sizing_only / recommendation_only
**Codex round**: 1
**Codex stance**: REJECT (7 critical_concerns)
**Codex output**: `qepm/mailbox/worktask/WT-S20260504_005/codex_critic_response_optimizer.json`
**Generated**: 2026-05-04 by optimizer-research_agent
**AX-008 status**: 2-source review (Claude optimizer-research + Codex GPT-5.5) — establishes triangulation initial bracket; Forge measurement = 3rd source.

---

## Summary

Codex returned REJECT with 7 critical concerns spanning hard-constraint compliance (RF-O13 turnover, RF-O7 cash accounting, RF-O8 CVaR), selection-objective insufficiency (β_F1 only, no MDD/vol/cost metrics), PIT timing (IRAN_LMR_2026 → 2026-05-01), and AX-008 establishment.

**Net resolution**: 5 ACCEPT, 1 PARTIAL, 1 REBUTTAL. Empirical post-cost metrics revealed FactorBeta_Hedge **worsens** net IR vs S1 baseline (−0.16 / −0.37), failing spec `decision_rule.PASS` (CAGR ≥20% required; M4=17.3%). Per Charter v1.7 §8 + Optimizer `failure_rules` Rule 3 ("예상 순알파 < 비용 → HOLD"), this WT closes as **MONITORING_ONLY** verdict per spec `decision_rule.MONITORING_ONLY` clause ("factor regression quality OK + trading damage 큼"). `wt_kind=recommendation_only` confirms no production weight modification.

---

## Per-Concern Resolution

### C1 — Turnover RF-O13 (CRITICAL)

| field | value |
|---|---|
| **classification** | **ACCEPT_WITH_INFEASIBILITY_INHERITED** |
| Codex claim | annual one-way turnover 778.7% > 600% hard cap |
| Verified observation | S1=716.6% / FH=778.7% / M4=748.9% one-way × 12 |

**Acceptance reasoning**: Codex correct on the absolute breach. **Source attribution**: 716.6% S1 baseline turnover is INHERITED from STR_1715 monthly score_eff rebalance — the per-date 20-name set rotates substantially each month (different alpha-decile composition). FactorBeta_Hedge optimizer adds only +62.1pp on top of inherited S1 (716.6 → 778.7). M4 adds slightly less (+32.3pp). **Sizing_only WT cannot modify parent monthly schedule.**

`infeasibility_report.violations[1]` issued with `source=INHERITED_FROM_STR_1715_MONTHLY_RANK_REBALANCE` and explicit `resolution` (future deployment WT must reduce frequency to quarterly OR add explicit turnover penalty in alpha generation OR accept high cost-adjusted gross alpha).

L-code anchor: L-484 (rebalance frequency × top-20 long-only structural turnover). Charter v1.7 §8 No Silent Override — accepted, documented, deferred to successor WT.

### C2 — Cash accounting (CRITICAL)

| field | value |
|---|---|
| **classification** | **ACCEPT_REBUILT_TOTAL_CONVENTION** |
| Codex claim | risk weights sum=1.0 + cash_pct=0.40 → total can reach 1.4 |
| Verified | weights.csv v1 had risk-only sum=1, cash_pct stored separately — ambiguous |

**Resolution**: Rebuilt all 3 variants in `total_portfolio_convention_v2`:
- `weight` column = total fraction of portfolio (= risk_weight × (1 - cash_pct))
- `weight_risk_only_excluding_cash` column retained for traceability
- `Ticker='CASH_KRW'` rows added per Date when cash_pct > 0
- Per-Date sum = 1.0 always (verified, all 269 dates)

`cash_definition_audit.json` updated. Canonical `weights.csv` follows total convention. STR_1715 production (parent) format = identical convention (Weight column sums to 1, cash implicit if not in 20).

### C3 — CVaR breach + no infeasibility_report (HIGH)

| field | value |
|---|---|
| **classification** | **ACCEPT_INFEASIBILITY_REPORT_ISSUED** |
| Codex claim | CVaR_95 = -12.89% breach -10% threshold, no infeasibility_report |

**Resolution**: `infeasibility_report.violations[2]` issued with severity=HIGH. Source = STR_1715 268m actual concentration tail (inherited from L-274). Spec WT-S20260504_005 prescribes 3-variant comparison only — CVaR_LP / Min CDaR / HRP+CDaR not in scope. Spec scope-bound. Recommended successor: explore CVaR-LP per FRM Pfaff Ch12.

### C4 — Selection objective β_F1 only (HIGH)

| field | value |
|---|---|
| **classification** | **ACCEPT_FULL_MULTI_METRIC_COMPARISON_ADDED** |
| Codex claim | selection on β_F1 reduction without net_IR/MDD/vol/cost |

**Resolution**: Added `cost_post_metrics` block to remediated optimization_package. Empirical post-cost metrics (15bps one-way) for all 3 variants:

| Variant | SR_post | CAGR_post | Vol | MDD | Sortino | Calmar | ToAnn | Cost/yr | Win |
|---|---|---|---|---|---|---|---|---|---|
| S1 | **0.815** | 20.96% | 25.74% | -48.01% | 1.025 | 0.437 | 714.0% | 1.07% | 56.9% |
| FactorBeta_Hedge | 0.781 | 19.23% | 24.62% | -47.50% | 0.883 | 0.405 | 775.8% | 1.16% | 60.6% |
| M4+FactorBeta_Hedge | 0.779 | 17.33% | 22.26% | -46.26% | 0.881 | 0.375 | 746.1% | 1.12% | 60.6% |

| Net IR | vs S1 |
|---|---|
| FactorBeta_Hedge | **-0.163** |
| M4+FactorBeta_Hedge | **-0.366** |

**Honest finding**: β_p,F1 reduction (63.22%) is empirically real, but post-cost net IR is NEGATIVE. Hedge-induced QP weight perturbation costs +62pp annual one-way turnover, eroding gross alpha by ~1.7pp CAGR (M4 vs S1). MDD improvement is only -1.75pp (S1 -48.01 → M4 -46.26), short of spec target -3pp.

**Spec decision_rule mapping**:
- PASS requires CAGR≥20% + MDD≤-25% OR -3pp + vol -20% — **M4 fails CAGR (17.3%)**
- CONDITIONAL_PASS requires CAGR≥20% + MDD 1~3pp + vol -10% — **also fails CAGR**
- **MONITORING_ONLY** ("factor regression quality OK + trading damage 큼") ← **best fit**

This is an honest measurement-only finding, not a method-shopping defect. Per Optimizer `failure_rules` Rule 3 ("예상 순알파 < 비용 → HOLD"), method_selected updated to **`M4+FactorBeta_Hedge_MONITORING_ONLY`** with no production change recommended.

### C5 — Alpha-weight rank correlation 0.153 (MEDIUM)

| field | value |
|---|---|
| **classification** | **PARTIAL** |
| Codex claim | top-decile alpha names have zero weight on 101/269 dates; Spearman avg 0.153 |

**Partial reasoning**: QP weight `w` is anchored to `w_anchor = STR_1715 alpha-proportional baseline` (rank-preserving by construction within the per-date 20-name set). However Codex measures `alpha_scores` against final QP weights, where the β-hedge term adds non-alpha component. Spearman 0.153 reflects the **β-hedge perturbation strength** — directly visible in net IR -0.37 (C4). C5 and C4 are the same phenomenon viewed differently. ACCEPT the empirical finding (Spearman drift); the mechanism is the QP β-hedge anchor competition, already documented in C4.

### C6 — PIT C2 IRAN_LMR_2026 to 2026-05-04 informing 2026-05-01 (HIGH)

| field | value |
|---|---|
| **classification** | **REBUTTAL** |
| Codex claim | IRAN_LMR_2026 (window 2026-04-01 to 2026-05-04) used in crisis_prone identification supporting F1, but deploy_cutoff is 2026-05-01 → potential future-info leak |

**Rebuttal — 3-axis defense**:

1. **Robustness invariance check (quantitative)**: Removing IRAN_LMR_2026 entirely from the crisis set, the remaining 5 historical crises (EM_2004, COMMODITY_2006, GFC_2007_09, COVID_2020, FED_2022) ALL rank F1 worst by minDD (rank=1 for each). 5/5 invariance → k_crisis=F1 selection IS NOT dependent on IRAN_LMR_2026 inclusion. The 6/6 → 5/5 robustness preserves F1 selection.

2. **Risk-package SHA-frozen documentation**: `lro_params_frozen.json::cross_sectional_regression$sha256_loadings = 9e9784f7...` is SHA-frozen at IS cutoff 2024-06-30. Per AX-002 compliance assertion in the parent risk_package, factor_set + crisis_prone_k are SHA-locked to IS cutoff. The IRAN_LMR_2026 crisis window is a POST-HOC verification window, NOT used in factor extraction (PCA fit at 2024-06-30, OOS projection only).

3. **L-code anchor + academic citation**: 
   - L-441 / L-450: "FRED 시차 1일 lag 또는 expanding percentile" — same principle (post-hoc crisis labeling for verification ≠ training-period leak)
   - PIT C11 spec: "데이터 시간축 검증" — IRAN_LMR_2026 included in the AS-OF labeling for verification purposes (not as factor input). The factor returns matrix at 2026-05-01 uses ONLY data up to 2026-05-01 (cf. risk_package `pit_compliance.notes`: "PCA IS-frozen at 2024-06-30 → OOS factor returns via projection only").

**Conclusion**: F1 selection is INVARIANT to IRAN_LMR_2026 inclusion. PIT C2 is satisfied. Codex concern noted but rebutted with quantitative robustness check (5/5 invariance). `pit_audit.robustness_5_of_5_without_iran_lmr` block added.

### C7 — AX-008 establishment (MEDIUM)

| field | value |
|---|---|
| **classification** | **ACCEPT_THIS_DOC_RECORDS_2_SOURCE** |
| Codex claim | risk Codex waived after timeout, no optimizer challenge_note exists, only future-promise of triangulation |

**Resolution**: This `optimizer_challenge_note.md` IS the 2-source record. Source 1 = Claude optimizer-research_agent (this Q-Lead spawn). Source 2 = Codex GPT-5.5 critic (codex_critic_response_optimizer.json). 3rd source = Forge measurement (next pipeline stage). Per AX-008 minimum 2-source requirement — this WT achieves it at OPTIMIZER_DONE state. Risk-stage Codex waiver (timeout retry, recorded in `risk_package.json::codex_round_status=round1_timeout_round2_waiver_applied`) was Q-Lead-approved waiver per Charter §8 exception — Forge measurement will confirm/deny risk findings via independent path.

---

## Self-Rationalization Audit (Charter v1.7 §8 Stage)

Reviewing my draft for the 6 forbidden expressions (`미미`, `관행적`, `보수적이면 OK`, `대부분 결과 동일`, `이미 반영`, `실무적`):

- Original draft contained: `"already exhibit slight defensive loading"`, `"ALREADY_NEUTRAL"`, `"sizing_only로 해소 불가"`, `"Marked borderline-pass per AX-002 spec frozen"`. Codex flagged these in `rationalization_red_flags`.

**Removed/replaced in remediated package**:
- `"already exhibit slight defensive loading"` → kept context but supplemented with empirical `mean β_p,F1 reduction 63.22%` + post-cost net IR -0.37 honest finding
- `"sizing_only로 해소 불가"` → replaced with explicit `infeasibility_report` + future deployment WT path
- `"Marked borderline-pass"` → replaced with R²=0.299 borderline observation + spec-bounded explanation

---

## Unresolved Disputes (forwarded to Forge)

1. `qepm/mailbox/worktask/WT-S20260504_005/weights.csv` not present (only stage_artifacts canonical) — Forge will create per pipeline contract.
2. `qepm/stage_artifacts/.../alpha_scores.parquet` path absent — alpha_package is `inherited_alpha_stub`; STR_1715 alpha_scores via parent `forge_may2026/alpha_scores_extended.parquet` — Forge handoff explicit.
3. Liquidity floor evidence per-name — inherited from STR_1715 production (parent `20260501_capacity_check_cap_0p20.json`).
4. Benchmark beta_port [1.00, 1.05] not measured — out of scope (latent F1 only per spec).
5. TDC vs PG2, replacement, integration scenario — recommendation_only WT, no PG2 admission planned (`governor_concord_status=DEFERRED_TO_PROMOTION_WT`).

---

## AX-008 Triangulation status

| Source | Stance | Path |
|---|---|---|
| 1. Claude optimizer-research_agent | constructive (this note + remediated package) | `optimization_package_remediated_draft.json` + this note |
| 2. Codex GPT-5.5 critic | REJECT round 1 → addressed in remediation | `codex_critic_response_optimizer.json` |
| 3. Forge measurement (pending) | TBD | next pipeline |
| 4. Architect (optional) | TBD | not invoked (sizing_only minimal scope) |

**Status**: 2/3 PASS pending Forge. `ax_008_status=PENDING_FORGE_3RD_SOURCE`.

---

## Final Verdict per spec decision_rule

```
decision_rule.PASS         : FAIL  (CAGR M4=17.3% < 20%)
decision_rule.CONDITIONAL  : FAIL  (CAGR < 20%)
decision_rule.MONITORING   : MATCH (factor regression R²=0.299 OK + trading damage net_IR=-0.37 큼)
decision_rule.FAIL_HARD    : N/A   (factor identification stable 6/6 → 5/5 invariant)
```

→ `verdict_classification = "MONITORING_ONLY"` recorded in optimization_package. `production_grade=FALSE`. `wt_kind=recommendation_only` reaffirmed. No PG2 admission. No book_state write.

Forge handoff will measure all 3 variants for archival cross-reference; Judge will confirm/deny MONITORING_ONLY classification.
