# Cross-Mode Bridge Summary

- batch_dir: `/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_rerun_turnover1100`
- plan_rows: 434
- status_rows: 14
- manifest: `/mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/batch_434/20260612_rerun_turnover1100/cross_mode_bridge_manifest.csv`

## Execution Classes
- BUILD_THEN_RUN: 360
- DIAGNOSTIC_BUILD_THEN_RUN: 30
- ML_BUILD_THEN_RUN: 22
- RUN_ALPHA_SINGLE_FACTOR: 10
- DATA_FIRST: 5
- RUN_ALPHA_SEARCH_FE: 3
- MISSING_BASE_CODE: 2
- LOW_PRIORITY_RUN: 1
- RUN_EXISTING_R: 1

## Mapping Quality
- UNKNOWN_LEGACY_PLAN: 434

## QEPM Mode Status
- NOT_EXECUTED: 420
- RECORDED_ALPHA_SEARCH: 13
- EXECUTION_FAILED: 1

## Factor Rotation Status
- BUILD_REQUIRED: 360
- DIAGNOSTIC_BUILD_REQUIRED: 30
- ML_REQUIRED: 22
- FR_BORROW_CANDIDATE_NEEDS_CONTRACT: 13
- DATA_REQUIRED: 5
- MISSING_BASE_CODE: 2
- EXECUTION_FAILED: 1
- LOW_PRIORITY_NOT_RUN: 1

## Grades
- F: 7
- B: 6

## Notes
- FR borrow-candidate statuses are grade-agnostic. Overall A/B/C/F is recorded for diagnostics only.
- `BASE_SIGNAL_ONLY` and `PROXY_SPEC_MISMATCH` are allowed as borrow candidates only under their own identity, not as exact source-strategy equivalence.
- Actual FR consumption still requires authoritative contract/freeze/hash registration outside alpha-search quarantine plus RCMA admission.
