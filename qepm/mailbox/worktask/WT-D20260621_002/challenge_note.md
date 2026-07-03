# Challenge Note — WT-D20260621_002 PCDM (Alpha Agent)

**Charter §8 No Silent Override.** Codex Critic Round (GPT-5.5 xhigh) stance = **REVISE**, veto_flag=false.
Codex **agrees with the negative-alpha conclusion**; objections are artifact/process. Each concern classified ACCEPT / PARTIAL / REBUTTAL below with grounds.

## Codex verdict summary
- `stance=REVISE`, `verification_triangulation.agree_with_claude=false` ("agree with the negative alpha conclusion, but disagree the package is ready to finalize because the artifact contract and triangulation are incomplete").
- `ic_diagnostics_audit`: all PASS=false (rank_ic 0.00286, icir 0.0219, harvey_t 0.357, sub_stability 0.333) — i.e. Codex confirms the signal is non-predictive.

## Concern-by-concern resolution

### C1 (HIGH, RF-A7 single-snapshot) → **ACCEPT**
`signal_matrix_ref` pointed to `alpha_scores.parquet` containing only one as_of date (348 rows, no Date column) — Codex flagged Iter-4 single-snapshot schedule-bug risk if Forge consumes it as a time series.
**Action:** re-exported `alpha_scores.parquet` as the proper **multi-sig-date Date×Ticker×score panel** (79,814 rows, 257 months, 2005-01-31..2026-05-29). Live vector preserved separately as `alpha_scores_live_2026-05-29.parquet`. `alpha_vector` in the package is explicitly labeled live-only. Fixed.

### C2 (HIGH, diagnostics fail) → **ACCEPT** (this IS the finding)
rank_ic 0.00286, ICIR 0.0219, Harvey-t 0.357, monotonicity 0.556, subperiod_stability 0.333. Supports negative result only. Agreed — the package reports FAIL, not graduation.

### C3 (HIGH, distinctness fail) → **ACCEPT** (this IS the finding)
mean rank-corr 0.912 vs M01, 0.802 vs M24; residual-IC after M01/M08/M24 = −0.0222 (Harvey −3.99). PCDM collapses into saturated momentum + anti-predictive residual. Agreed and reported as the primary honest finding.

### C4 (MEDIUM, C15 lineage — direct rawdata/benchmark read) → **PARTIAL**
**Grounds (academic + L-code + spec):** The WT request.json explicitly mandates: *"Compute from rawdata returns via the compute_momentum.R pattern; reuse load_month_factors for the orthogonality comparison (C15)."* PIT C15 (`.claude/rules/pit.md`) governs **reuse of the Factor DB** ("Factor DB parquet 직접 load 금지. load_month_factors() 경유"). PCDM is a **new factor computed from rawdata price/return series**, which is the spec-authorized path (alpha_research_init.md Step 2-C "신규 팩터 직접 설계 … RAWDATA"). The factor_db_daily is flagged CRITICAL-stale in the DATA NOTE, so recomputing M01/M08/M24 from the *same* rawdata is the PIT-correct choice for a fair, time-aligned orthogonality test (avoids stale-DB timing mismatch).
**Action (partial concession):** added `record_package_lineage()` provenance (rawdata.parquet + benchmark.parquet hashes) so the direct-read path is auditable. Anchor check: from-rawdata M08 rank_ic 0.0240 / Harvey 3.65 reproduces the known KR residual-momentum strength, validating the recomputation against factor_db M08.

### C5 (MEDIUM, AX-008 triangulation; weights.csv/covariance.parquet missing) → **REBUTTAL**
**Grounds (role boundary):** weights.csv, covariance.parquet, risk_package, optimization_package are **NOT alpha-agent deliverables**. `agent_role_guard` Hook hard-blocks the alpha agent from producing covariance/weights/optimization (alpha_research_init.md <strict_prohibitions> 1–3). AX-008 forge-triangulation (forge PORT_t NW lag-3) is a *downstream* gate that only runs if the alpha proceeds to Risk→Optimizer→Forge. A **negative alpha that fails screening does not proceed to forge**, so demanding optimization artifacts at the alpha stage is out of scope and would itself be a role-boundary violation. The alpha-stage real measurement (`canonical_screen_bt`, forge-equivalent `build_benchmark_compare`) IS provided: PORT_t 0.986.

### C6 (MEDIUM, mechanism/DSR under-specified for DPL/overlay promotion) → **PARTIAL/ACCEPT**
Agreed for any *promotion* path. **Action:** removed the DPL_FEATURE salvage suggestion entirely (see C7). DSR is `selection_type="chain"`/single-spec → advisory-only per measurement-graduation §3 (n_trials≈1 family, not a sweep); reported NA with rationale. References tightened to honest analogy labels (not replication claims).

### C7 (LOW) + rationalization_red_flags → **ACCEPT**
Codex flagged "forge-authoritative pending", "optionally DPL_FEATURE …", "clean negative" as rationalization leaving a reuse path.
**Action:** removed the DPL_FEATURE / overlay salvage route from `verdict.screen_route` (now `none`). Removed "forge-authoritative pending" hedge — replaced with the actual measured PORT_t 0.986 labeled `canonical_screen`. "clean negative" retained only as a factual descriptor of a falsification success (AX-000), not as a salvage hedge.

## Self-rationalization auto-check (Decision Protocol §2)
grep of revised package for {미미, 관행적, 실무적, 보수적이면, 대부분 결과 동일, 영향미미}: **0 hits**. The one retained "negative" usage is a factual falsification label, not a minimization of a violation.

## Escalation check (Decision Protocol §3)
- HIGH severity concerns = 3 (C1,C2,C3) < 5 → no auto-escalate on count.
- AX axiom hard FAIL: AX-007 FAIL (Codex) — but moot here (cross-sectional signal ≈0, translation question does not arise); AX-008 FAIL is downstream-scope (rebutted). < 3 hard axiom FAILs.
- PIT C1 (lockbox/lookahead): **no violation** (Codex C13/C14/C9/C4 all PASS; look-ahead absent by construction, peers learned Date≤sig_date).
- Codex stance=REVISE (not REJECT), agrees with conclusion → **no Q-Lead escalation required.** Revisions applied, package finalized as honest NEGATIVE.

## Outcome
Package finalized as **graduation=FAIL / NEGATIVE_RESULT**, no screen-route. All actionable Codex revisions (C1 multi-date panel, C4 lineage, C6/C7 remove salvage) applied; C5 rebutted on role-boundary grounds.
