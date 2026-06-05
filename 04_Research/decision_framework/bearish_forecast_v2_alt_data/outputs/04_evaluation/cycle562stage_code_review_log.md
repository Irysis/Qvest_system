# Cycle 56-2stage Code Review Log (Codex CLI)

**Date**: 2026-05-21
**Reviewer**: Codex CLI 0.128.0 (effort=medium, read-only)
**Scope**: Stage 2 XGB meta scripts (data leakage / PIT / α-grid forward-looking / time-series CV correctness)

## Files reviewed

1. `scripts/149_xgb_meta_ecos_stage2.R` (Stage 2 trainer, 3 variants)
2. `scripts/150_stage2_aggregate.R` (Aggregate + period-balanced + bootstrap CI)

## Verdict

**CLEAN — no CRITICAL or HIGH data leakage / PIT violation / α-grid forward-looking bug.**

## Findings detail

### LOW (1)

**LOW-1 Feature lag naming hard-coded but not asserted generically**
- Refs: `scripts/149_xgb_meta_ecos_stage2.R:62, 105`
- ECOS and US macro feature vectors are all `_lag1` by name; presence is checked via `stopifnot`; PIT-clean as written.
- Suggestion (non-blocking): add `grepl("_lag1$", ...)` assertion to harden against future edits.
- Action taken: None (current code correct, hardening deferred to next cycle).

### Verified Clean (5)

**Stage 2 uses Stage 1 OOS only**
- `split == "oos"` and `target == "y_tail_q126"` asserted before merge.
- Ref: `scripts/149_xgb_meta_ecos_stage2.R:108`

**Time-series CV is chronological**
- Each fold trains on rows strictly before `te_start`, tests on `te_start:te_end`.
- Fold 1 has empty train set → correctly skipped.
- Refs: `scripts/149_xgb_meta_ecos_stage2.R:128, 190`

**V1/V2/V3 per-fold predictions are leak-free**
- XGB trained only on `train_idx`, predicted only on `test_idx`.
- Refs: `scripts/149_xgb_meta_ecos_stage2.R:196, 205, 219`

**V3 α-grid is forward-clean relative to test fold**
- α selected on last 20% of train fold only; no test-fold labels/predictions used.
- Final test blend uses fixed per-fold α.
- Refs: `scripts/149_xgb_meta_ecos_stage2.R:230, 246, 260`

**Full-OOS XGB refit is diagnostic-only**
- Used only for feature importance ranking display.
- Prediction files saved from per-fold OOF columns (not refit).
- Refs: `scripts/149_xgb_meta_ecos_stage2.R:326, 351`

**Aggregator (150) is evaluation-only**
- Merges saved OOF predictions; reconstructs fold IDs; computes T1/T2/T3/T4 metrics.
- No retraining or selection on test data.
- Refs: `scripts/150_stage2_aggregate.R:94, 102`

## Pre-existing finding (not introduced by Cycle 56-2stage)

**Fold 5 phantom-0 labels** — `outputs/02_targets/targets_long_horizon.parquet` fills `y_tail_q126 = 0` for end-of-data dates where `ret_q126` is `NaN` (forward 126-day window not yet observable). Affects Fold 5 (302/410 observable, 3 events / 410 rows). Inherited from Cycle 48A target file generation. Documented in Tier T3 (observable-only) aggregate metric for full visibility.

## AX-008 status

- Forge (Q-Lead direct R execution): Stage 1 reused from 53H, Stage 2 + aggregate ran end-to-end
- Codex: PASS (this review)
- Result: 2-source PASS (Forge + Codex) — AX-008 minimum met
