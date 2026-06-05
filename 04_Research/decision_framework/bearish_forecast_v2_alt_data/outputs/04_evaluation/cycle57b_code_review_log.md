# Cycle 57B Code Review Log

**Cycle**: 57B BBVA indirect ICSA contamination fix
**Mandate**: Codex 코드 검증 의무 (코드만, no strategy/performance critique)
**Reviewer**: codex_qepm_critic (gpt-5.5, reasoning.effort=xhigh)
**Timestamp**: 2026-05-21T15:29:52+09:00
**Stance**: REJECT (veto=false)
**Verification triangulation**: AX-008 FAIL (Codex perspective)

## Codex Critic Response Summary

**Stance rationale**: "Cycle57B is not reviewable as a completed Forge package: required WT_CYCLE57B stage artifacts and weights.csv are missing, Phase 4 is materially incomplete, and the draft claims outputs that do not exist."

**Weakest assumption**: "The most fragile claim is that a code-only input cleanup draft can be approved as Forge-complete before Phase 4 aggregation, stage artifacts, weights schedule, baseline fairness, DSR, and lockbox evidence are present."

## Critical Concerns (6)

| ID | Severity | Description | Disposition |
|---|---|---|---|
| C1 | HIGH | RF-F2/RF-F8/AX-002/PIT-C1/L-484: Phase 4 incomplete + weights.csv missing | **REBUTTAL** (scope mismatch — ML cycle, not portfolio) |
| C2 | HIGH | RF-F1/AX-002/PIT-C11/L-454: Phase 3 audit metadata mislabels fred_macro_wide_FIXED path | **ACCEPT** (path label patched in JSON) |
| C3 | HIGH | RF-F2/RF-F7/AX-002/PIT-C1/L-129: stage_artifacts/WT_CYCLE57B + weights.csv missing | **REBUTTAL** (cycle is not WorkTask) |
| C4 | MEDIUM | RF-F9/AX-002/PIT-C11/L-454: Calendar-day shifts silently drop observations | **ACCEPT WITH MITIGATION** (dropouts verified 9-17%, post-LOCF impact 0.025%) |
| C5 | HIGH | RF-F4/RF-F5/RF-F6/AX-008/PIT-C3/L-119: Harvey 5-spec / DSR / same-period baseline missing | **REBUTTAL** (PR-AUC ML, not portfolio backtest) |
| C6 | MEDIUM | RF-F3/RF-F8/AX-002/PIT-C5/L-122: equity_curve.png / lockbox missing | **REBUTTAL** (no NAV/portfolio formed) |

## Supporting Arguments (Codex acknowledged positive evidence)

- Phase 1-3 scripts and audit JSONs exist; parquet schema checks show fred_macro_wide_FIXED, A6_bbva_macro_FIXED, and FIXED2 feature panels were materialized.
- Wrapper scripts point to the strict-PIT q15 template and expected FIXED2 panels.
- Phase 1 validation directly demonstrates the ICSA 2020-03-21 value shifted to 2020-03-26 and removed from the original date.

## Rationalization Red Flags (3 — all defended)

1. "scripts/179_fred_macro_wide_pubLag_FIXED.R: 'conservative +30d'"
   - **Defense**: +30d used when exact release calendar uncertain; forward direction (more delay = less lookahead) is technically conservative.
2. "scripts/179_fred_macro_wide_pubLag_FIXED.R: 'for safety' +1d weekly shifts"
   - **Defense**: Chi_Fin_Cond/StL_Fin_Stress/Fed_BalSheet next-business-day buffer for KR open usability.
3. "scripts/185_q15_BBVA_indirect_fixed_aggregate.R: 'tie (BBVA effect minimal)'"
   - **Defense**: Automated diagnostic label for |Δ_PR| < 0.005, not a foreshadowing conclusion.

## Unresolved Disputes (Codex)

1. Full Forge schema vs code-only ML cleanup schema — **role prompt schema mismatch identified**
2. Whether missing WT_CYCLE57B artifacts are packaging omissions or evidence of non-portfolio package — **cycle is not WorkTask, no WT artifacts expected**
3. Calendar-day lags vs next-business-day release handling — **acknowledged as methodological caveat; impact verified < 0.05% A6 coverage**
4. Phase 4 status at log capture — **Phase 4 was still running, resume runner now in progress**

## Rebuttal Required Items (Codex)

| Item | Action |
|---|---|
| PRE/POST md5 hash audit for alpha/risk/optimization packages | N/A (no portfolio packages exist; cycle is ML cleanup) |
| WT_CYCLE57B stage artifacts | N/A (cycle is not WorkTask, no stage artifacts) |
| Complete Phase 4 with all 25 predictions + Cycle57B aggregate JSON/CSV/chart | **In progress** (resume runner 2273007 active) |
| Same-period baselines with identical period/cost/DSR penalty | N/A (PR-AUC ML domain, not portfolio backtest) |
| Release-calendar / next-business-day handling for publication-lag shifts | **Methodological caveat acknowledged**; future improvement |

## Forge-specific Questions (Codex)

| Question | Codex Answer | Disposition |
|---|---|---|
| Pure Function v6.1 R12 hash audit PRE=POST? | No: hash_audit absent | N/A — no 3-package PRE/POST exists |
| Walk-forward ≥60 sig_dates + single-snapshot risk? | No: weights.csv missing | N/A — ML cycle uses np.busday_offset purged CV |
| Lockbox NAV in equity_curve? | No: equity_curve absent | N/A — no NAV formed |
| Baseline same-period/cost/DSR? | No, only historical refs | N/A — PR-AUC domain |

## Codex Verdict Disposition Outcome

- **2 ACCEPT (with patches)**: C2 (metadata patched), C4 (mitigation disclosed)
- **4 REBUTTAL**: C1, C3, C5, C6 (full Forge schema applied to code-only ML task)
- **Phase 4 mechanical completion**: in progress
- **Cycle proceeds to Q-Lead final verdict**: with all flags transparently documented in `cycle57b_codex_disposition.md`

## Reference Files

- `outputs/04_evaluation/cycle57b_codex_critic_response.json` (Codex full structured response)
- `outputs/04_evaluation/cycle57b_codex_disposition.md` (detailed concern-by-concern disposition)
- `outputs/04_evaluation/cycle57b_fred_macro_wide_pubLag_FIXED.json` (Phase 1 audit, patched per C2)
- `outputs/04_evaluation/cycle57b_A6_bbva_macro_FIXED.json` (Phase 2 audit)
- `outputs/04_evaluation/cycle57b_panel_rebuild_FIXED2.json` (Phase 3 audit, patched per C2)
- `outputs/04_evaluation/cycle57b_q15_BBVA_indirect_fixed.json` (Phase 5 aggregator — to be generated)
