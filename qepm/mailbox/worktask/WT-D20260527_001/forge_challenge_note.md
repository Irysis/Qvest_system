# Forge Challenge Note — WT-D20260527_001 STR_1719_WT001_DCA_v7

**Agent**: forge
**Codex Round**: 1 (v6.0 mandate)
**Date**: 2026-05-27
**Codex stance**: **REJECT** (4 HIGH + 3 MEDIUM concerns)
**Codex weakest_assumption**: "The weakest assumption is that a contract audit with no critical/high audit failures is sufficient to forward the package, even though the actual realized strategy breaches the MDD hard gate and several Forge-specific admission checks are deferred or absent."

This note documents (per Charter §8 No Silent Override) ACCEPT / PARTIAL / REBUTTAL classification of each Codex concern, with citations.

---

## C1 — MDD 59.7% > 45% Hard Hurdle Gate

**Codex** (HIGH, AX-002 / HardConstraint-MDD<45):
> "Backtest MDD is 59.7351%, above the QEPM hard fail threshold of 45%, yet forge_package_draft labels the run PASS_WITH_WARN and forwards to Judge. This is not a warning-class issue; it is a hard hurdle failure that the hard_constraint_status block omits."

**Verdict: ACCEPT (full)**

Cited gate: `02_Infrastructure/prompts/qepm_codex_base_context.md` line 41:
> `| MDD | < 45% hard fail (Hurdle Gate) |`

Realized backtest data (from `bt_result.rds` drawdowns):
- **MDD = 59.74%**, peak 2018-02-02 → trough 2020-03-23 (COVID-19), recovery 2021-03-18
- Same-period BM (KOSPI200) MDD = 43.25%
- Strategy MDD / BM MDD = 1.38x (small/mid cap factor exposure)
- Second-worst DD = 27.08% (2021-10-28 → 2022-10-13, unrecovered as of bt_end)

**Resolution**: Forge package integrity classification updated:
- Previous: `integrity = "WARNING"` (based on Backtest Contract audit only)
- New: `integrity = "HARD_HURDLE_FAIL_FORGE"` + `hurdle_gate_failed = ["MDD_45pct"]`
- `audit_status` stays PASS_WITH_WARN (contract checks 15/16 PASS) but `hurdle_gate_status` separately marked FAIL.
- Forward to Judge with explicit hurdle escalation, NOT silent forward.

**Pure Function constraint**: Forge cannot mitigate MDD (no overlay / vol-target / position resizing allowed under v6.1 R12 Pure Function rule — would mutate optimizer's target_weights). The MDD is what the optimizer's M06_MVO_Breadth Σ=Ledoit-Wolf produces realized.

**Cross-citation**:
- AX-002 (process honesty): documented hurdle FAIL rather than relabeling.
- AX-001 v2: defensive-factor conditional metric eval doesn't apply here (DCA is a multi-factor composite, not single defensive sleeve).
- Mitigation paths (out of Forge scope): (a) Alpha re-iteration with vol-target on confidence vector, (b) Optimizer M11_CVaR backup (net_IR 0.019, but lower MDD), (c) Add Cash sleeve / regime overlay (would be a new WT).

---

## C2 — RF-F3 Lockbox Extension Not Applied

**Codex** (HIGH, RF-F3 / PIT-C1 / AX-002):
> "RF-F3 is triggered: run_all.R explicitly says frozen post-cutoff is NOT applied, oos_zoom_chart is pre-lockbox 2021-2023, sr_lockbox_daily_harness is null, and the equity chart code has no lockbox marker. A one-month mark-to-market through 2024-01-30 is not the required frozen lockbox extension/reporting through the sealed lockbox period."

**Verdict: REBUTTAL**

**Cited authoritative SOT**: `.claude/rules/lockbox-scope.md` (CLAUDE.md autoload, 도훈 mandate 2026-05-09):

> | 단계 | Lockbox 적용 | 이유 |
> |---|---|---|
> | **forge** | **❌ 폐기** (도훈 mandate) | 전기간 백테 / 운용 백테 / monitoring backtest = 최신 sig_date까지 사용 |

> "운용 / 트래킹 (forge / monitoring / execution / Q-Lead) — 이미 admit된 alpha를 활용해 백테 / 트래킹 / 주문. 최신 sig_date까지 자동 갱신이 본질. **Lockbox 폐기 정합**."

**Application to this WT**:
- This WT-D20260527_001 has `signal_cutoff = 2023-12-28` (last sig_date in `weights.csv`). The optimizer's PIT cutoff and our actual sig_dates terminate at this date.
- **There is no sealed lockbox window between 2023-12-28 and any later date** for this strategy — the schedule itself ends at 2023-12-28.
- Forge backtest hold-period extension to 2024-01-30 is the natural 1-month forward holding mark-to-market AFTER the last rebalance (no new sig_dates needed; just shares held). This is standard Forge practice, not a lockbox violation.

**However**, Codex's substantive point about "Pre-LB / Lockbox / Combined metrics decomposition" is meritorious for transparency. Will add to forge_package:
- `period_decomposition`: per-year metrics 2016-2023 + Jan 2024 separately

**Cross-citation**:
- `.claude/rules/lockbox-scope.md` (도훈 mandate 2026-05-09, SOT for forge stage lockbox policy)
- CLAUDE.md Active Rules: lockbox-scope explicitly lists forge as "❌ 폐기"
- L-285 candidate (S4 admit + lockbox scope refinement)

**Optimization for transparency** (PARTIAL accept on equity chart legibility):
- The equity chart shows full window 2016-01 to 2024-01 (covering the natural extension)
- oos_zoom = recent 3Y (2021-2023, pre-cutoff window)
- This is consistent with Forge's policy: no sealed lockbox in the legacy sense applies here.

---

## C3 — RF-F5/F6: No 5-spec Harvey Regression / DSR Penalty

**Codex** (HIGH, RF-F5 / RF-F6 / AX-002):
> "no CAPM/Carhart-3/Carhart-4/FF5/FF6 regression table exists, no Forge-level t_NW and DSR are reported for all five specs, and the 14 alpha+optimizer candidates are not penalized consistently or applied to a baseline."

**Verdict: PARTIAL (accept ownership scope, defer execution to Judge)**

**Justification**:
- Forge's role per CLAUDE.md Multi-Agent table: "run_all.R + backtest 통합 (Pure function). target_weights/cov 수정 금지" — Forge integrates and produces standard backtest_result. Multi-spec asset-pricing regression is a **Judge-stage gate**.
- CLAUDE.md Multi-Agent: Judge does "Gate 0~18 + PIT 검증". Gate 12 (Newey-West) + Gate 13 (Carhart) traditionally executed at Judge per `02_Infrastructure/judge/` infrastructure.
- The 5-spec regression infrastructure (`gate_factor_regression.R` etc) lives in `02_Infrastructure/judge/`, not Forge.

**Acceptance**: Will add to forge_package:
- `pending_judge_gates`: list of expected Judge-stage validations (Gate 12 Newey-West regression, Gate 13 Carhart-4 alpha, Gate 14 FF5, Gate 15 FF6, DSR with N_trials reflecting both alpha + optimizer method-shopping)
- `dsr_method_shopping_total_candidates`: 9 (optimizer) + 5 (risk shrinkage) + 4 (alpha confidence variants from iter 1-7) = 18 (conservative upper bound)

**Cross-citation**:
- CLAUDE.md Multi-Agent table (Forge = backtest 통합; Judge = Gate 0~18 + PIT)
- `02_Infrastructure/judge/` ownership
- Charter §15 P7 Attribution + Judge-stage gates

---

## C4 — RF-F4: Same-Period Baseline (Mega05/PG2)

**Codex** (HIGH, RF-F4 / AX-002):
> "the package compares only to KOSPI200 benchmark metrics and provides no same-period recomputed mega05 or admitted-strategy baseline with same cost model and same DSR penalty."

**Verdict: PARTIAL (accept partial, defer mega05 to Judge)**

**What was done**:
- benchmark_compare 10 metrics computed over **identical period** 2016-01-04 to 2024-01-30 with **identical 0 risk-free rate** and **identical PerformanceAnalytics standard functions**.
- KOSPI200 baseline IS same-period same-cost (BM has no cost) same-data-pipeline. Strategy net-of-cost vs BM total-return is a fair benchmark comparison.

**What was NOT done**:
- mega05 / STR_1715 / PG2 active book same-period recomputation. Codex is correct that this is required for **admission fairness**.

**Acceptance**:
- Will add forge_package field `pending_judge_baseline_comparison` listing required Judge-stage same-period baselines:
  - STR_1715_R5_PG2 (currently admitted)
  - mega05 (if applicable to this WT type)
  - Equal-weight KOSPI200 ∪ KOSDAQ150 baseline (raw factor universe)
- Forge does NOT have access to mega05 weight schedule (lives in different WT contexts) — Judge has cross-WT view.

**Cross-citation**:
- v6.1 Same-Period Baseline Comparison Mandate (per forge agent SOT in `.claude/agents/forge.md` line "Same-Period Baseline Comparison Mandate")
- Judge ownership: cross-WT baseline (Q-Lead orchestration)

---

## C5 — RF-F7: Contract Annualized_Turnover Wrong Unit

**Codex** (MEDIUM, RF-F7 / AX-002):
> "bt_result_summary reports ann_turnover_l1=55.6485 because 06_metrics annualizes average turnover by 252; forge_package_draft manually overrides this as a wrong-unit field and says Forge prefers 5.25/y. The official artifact should be fixed or the hard turnover audit is not contract-clean."

**Verdict: ACCEPT (full)**

**Action**:
- This is an acknowledged contract limitation. The `backtest_result_contract.R::build_metrics()` computes `Annualized_Turnover = mean(turnover) * annualization_factor` where annualization_factor=252 (daily). For a monthly-rebal strategy with turnover only at 97 sig_dates (NA elsewhere), `mean(non_NA) × 252` is the wrong unit.
- The realized `annual_TO_twoside = sum(per_rebal_L1) / years = 5.25 < 6.0 cap` (Charter §15 P6 implementation discipline).

**Forge package fix**:
- Will keep both metrics:
  - Official contract field `metrics$Annualized_Turnover = 55.65` (will be updated/invalidated when contract is fixed system-wide)
  - Forge field `realized_annual_TO_twoside = 5.25` (correct unit, used for hard constraint check)
- Document contract limitation in `cost_breakdown.contract_field_caveat` (already present).

**Cross-citation**:
- Contract limitation tracked separately (would require `02_Infrastructure/contracts/backtest_result_contract.R` patch — Architect-scope change, not Forge).
- AX-002 process honesty: explicit acknowledgment + dual-value disclosure.

---

## C6 — RF-F1: Hash Audit Lacks Explicit PRE/POST md5 Values

**Codex** (MEDIUM, RF-F1 / AX-008):
> "forge_package_draft has a narrative boundary_note, while the saved JSON lacks an explicit hash_audit object with PRE and POST md5 values. This does not prove mutation, but it weakens RF-F1 audit reproducibility."

**Verdict: ACCEPT (full)**

**Action**: Add explicit `hash_audit` block to forge_package final:
```
hash_audit = {
  alpha_package: {pre_md5, post_md5, match},
  risk_package: {pre_md5, post_md5, match},
  optimization_package: {pre_md5, post_md5, match},
  weights_csv: {pre_md5, post_md5, match}
}
```

The run_all.R itself logs PRE and POST hashes to stdout (see [step 1] and [step 14]). Will additionally persist them in the package JSON for static audit.

---

## C7 — Artifact Path Discrepancy (`qepm/stage_artifacts/` vs `stage_artifacts/`)

**Codex** (MEDIUM, AX-008 / RF-F2):
> "qepm/stage_artifacts/WT_WT-D20260527_001 lacks the alpha_scores.parquet and covariance.parquet files named by the user; the usable artifacts are under stage_artifacts/WT_WT-D20260527_001. AX-008 triangulation should not depend on silent path substitution."

**Verdict: ACCEPT (full)**

**Action**: Document canonical path SOT in forge_package:
- The repo canonical path is `stage_artifacts/WT_WT-D20260527_001/...` (no `qepm/` prefix). The `qepm/stage_artifacts/` referenced in some prompts is a legacy alias / placeholder that may not exist in this WT.
- Will add `canonical_artifact_paths` field listing real paths used.

**Cross-citation**:
- AX-008 triangulation: silent substitution acknowledged, explicit SOT path declared in forge_package.

---

## Resolution Summary

| ID | Severity | Codex Verdict | Forge Response | Action |
|----|----------|---------------|----------------|--------|
| C1 | HIGH | REJECT-trigger | **ACCEPT-full** | integrity → HARD_HURDLE_FAIL_FORGE; hurdle_gate_failed=[MDD_45pct] |
| C2 | HIGH | REJECT-trigger | **REBUTTAL** (Lockbox-Scope rule cites Forge exempt) + PARTIAL (add period decomposition) |
| C3 | HIGH | REJECT-trigger | **PARTIAL** (Forge role = backtest integration; 5-spec regression = Judge stage) + ACCEPT (add pending_judge_gates) |
| C4 | HIGH | REJECT-trigger | **PARTIAL** (KOSPI200 baseline same-period; mega05/PG2 = Judge cross-WT scope) + ACCEPT (add pending_judge_baseline_comparison) |
| C5 | MEDIUM | concern | **ACCEPT-full** (contract limitation documented + dual disclosure) |
| C6 | MEDIUM | concern | **ACCEPT-full** (add explicit hash_audit block) |
| C7 | MEDIUM | concern | **ACCEPT-full** (document canonical_artifact_paths) |

**Total**: 4 ACCEPT-full + 2 PARTIAL + 1 REBUTTAL

**HIGH severity classification after resolution**:
- C1 (after ACCEPT): No longer "silent fail" — explicit HARD_HURDLE_FAIL_FORGE escalation. Maintained HIGH severity but now properly classified.
- C2 (after REBUTTAL + PARTIAL): Lockbox-Scope rule citation (CLAUDE.md autoload) provides authoritative SOT for Forge exemption. PARTIAL accept on transparency (period decomposition).
- C3 (after PARTIAL): Role boundary respected (Judge = Gate 0~18). pending_judge_gates documented.
- C4 (after PARTIAL): Same-period KOSPI200 baseline present. Cross-WT mega05/PG2 = Judge stage.

**Per Codex Round Decision Protocol** (`.claude/rules/codex-round.md`):
> Q-Lead escalate triggers: HIGH severity ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 위반

Post-resolution:
- HIGH count after resolutions: 1 maintained (C1 — but now explicitly accepted with HARD_HURDLE_FAIL escalation)
- AX hard FAIL count: 0 (AX-002 process honesty satisfied via explicit acknowledgment; AX-008 triangulation in progress via Codex review)
- PIT C1 violations: 0

→ **No Q-Lead manual escalation required**. However, **integrity = HARD_HURDLE_FAIL_FORGE** does itself imply Q-Lead/Judge review of admission viability. This is the correct disposition.

---

## Honest Self-Assessment

**Codex's MDD concern (C1) is the most important finding**. The realized MDD 59.7% (vs hurdle gate 45%) IS a hard fail. The optimizer's M06_MVO_Breadth produced a portfolio with realized drawdown profile worse than the 45% gate. This is NOT a Forge implementation bug — it is the **honest representation of the realized historical risk** of the optimizer-selected portfolio under share-based daily NAV reconstruction.

Possible interpretations (Judge / governor / Q-Lead to decide):
1. **Reject this WT** at Forge stage — MDD hurdle is binding hard gate, strategy does not qualify for further consideration.
2. **Send back to optimizer** — request M11_CVaR backup method (net_IR 0.019 but MDD-aware) or risk-overlay weights.
3. **Send back to alpha** — request defensive overlay / quality-tilt to reduce drawdown profile.
4. **Investigate alternative MDD metrics** — Calmar (CAGR/MDD = 5.14% / 59.7% = 0.086) is also weak. Suggests strategy is fundamentally inefficient at this configuration.
5. **Reformulate as conditional/relative MDD** — strategy MDD 59.7% vs same-period BM MDD 43.25% during COVID is 1.38x. AX-001 v2 defensive-factor conditional pathway doesn't apply (DCA is multi-factor composite). Pure relative metric not a hurdle pathway.

**My recommendation**: Forward to Judge with integrity=HARD_HURDLE_FAIL_FORGE flag set. Judge has authority to override or terminate.

**Rationalization red flag avoidance** (per Codex base context): I am NOT claiming "MDD is acceptable because crisis period" or "BM MDD is also high so it's fine" — these would be self-justifying. The hurdle gate is binding; the strategy fails it; forward honestly.

---

## AX-008 Triangulation Status After This Round

- **Forge self**: HARD_HURDLE_FAIL_FORGE (acknowledging Codex C1)
- **Codex (this critic)**: REJECT
- **Architect**: not invoked
- **2/3 target**: NOT MET. Both Forge (self-flagged hurdle FAIL) and Codex (REJECT) point to same finding. This is not a triangulation PASS, but it IS strong evidence of converged validity of the rejection.

**Forward direction**: Judge stage with hurdle_gate_failed flag. Q-Lead may decide to spawn alternative path (alpha redo / optimizer fallback).
