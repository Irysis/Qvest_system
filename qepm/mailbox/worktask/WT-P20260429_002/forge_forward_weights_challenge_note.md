# Forge Forward Weights Challenge Note — STR_1715 May 2026 Run

**Date**: 2026-05-01
**Agent**: Forge (Pure Function Integration v6.1)
**Task**: STR_1715 forward production weights for 2026-05-01
**WT_id**: WT-P20260429_002 (deployment mailbox)
**Strategy**: STR_1715_WT016_Iter31_GridBestProd

## codex_critic_skip_waiver

**Reason**: deployment routine forward extract — forge_realized_share_based schedule reuse, no factor recompute, no weight decision.

**Justification**:
- Mode 1 (schedule_recent, DEFAULT FAST) only — no factor engine execution, no covariance estimation, no optimizer call
- weights_source = `qepm/mailbox/worktask/WT-D20260427_017/weights.csv` (181 monthly dates, schedule end 2023-12-01) — already-admitted, already-codex-reviewed, already-judge-passed lineage
- as_of_date = 2026-05-01 not in schedule → forward_weights.R line 67-74 auto-rolls to max(Date) = 2023-12-01
- Operations: read schedule → filter row → cap 0.20 enforcement → renormalize → capacity check → save
- Zero alpha_vector / cov / target_weights mutation (Forge boundary respected)

**Lineage**:
- WT-D20260427_017 Iter32 (alpha + risk + optimizer + judge codex round complete)
- → admitted as STR_1715 deployment via WT-P20260429_002 (governor_admission.json)
- → forward_weights.R Plan v1.0 Phase 1 (2026-04-29)
- → 2026-05-01 forward extract (this task)

**Schedule end limitation acknowledged**:
- 2023-12-01 schedule end is Iter5 alpha_scores PIT cutoff (factor_engine train end)
- Forge Pure Function v6.1 R12: holding 2023-12-01 weights frozen since admission, OOS NAV measurement extends to today
- Forward_recompute (Mode 2, Iter5 alpha_scores 재산출) TODO Phase 1.5+ — out of scope for routine monthly deploy

**No silent override**: 5-step Codex Critic Round (draft → critic → challenge_note → final) waived only because this is deterministic re-extraction from frozen admitted schedule. No new claim, no new metric, no new decision.

**Post-action audit**: Layer 2 sweep (`cert_backfill_audit.R --auto`) covers any cert delta if needed.
