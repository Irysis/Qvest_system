# Cycle 54A — Code Review Log (Codex direct review)

**Date**: 2026-05-21
**Workflow**: code → codex review → fix → retrain (Codex Critic Round 5-step REPLACED per 도훈 mandate 2026-05-21)
**Scope**: code verification only (PIT, logit collapse bug, label semantics, leakage, numerical correctness)

---

## Codex review summary (verbatim findings)

Review output: `/tmp/codex_review_139_FIXED.md`
Reviewer: codex exec 0.128.0, sandbox=workspace-write, model=default (gpt-5.4 inferred)
Duration: ~7 min wall (08:38 → 08:44)

### 1. Bug Confirmation
- **VERDICT**: v5d_v1 was a **fresh retrain, not a copied file**.
- **Evidence**: per_fold_diagnostics.json shows real run diagnostics for v1_baseline (seed=42, oos_pr=0.3454, avg_best_epoch=26, per-fold PR [0.8335, 0.1054, null, 0.1707, 0.0308], elapsed_sec=880.7, gpu_mem_peak_mb=884.8).
- **Cause**: same seed + same baseline hyperparameters + same data/windows/folds + effectively deterministic CUDA/AMP trajectory → converged to same collapsed local minimum.
- **NOT** file reuse.

### 2. PIT Integrity (129 + 139)
- **C1-C15**: NONE found in inspected PIT surfaces.
- 139 keeps expanding folds + q126 Fold3 skip (line 150-165)
- Train/valid masks date-disjoint (line 425-433)
- OOS strictly post-train (lines 557-560, 677-685)
- Standardization mean/std/imputation on `train_mask` only (lines 337-349) — matches 129 (lines 296-308)
- Labels excluded from `feature_cols` (lines 320-331); no valid/OOS label enters train
- **Caveat**: `fillna(0)` on labels (line 331) is not leakage but raises evaluation-target validity issue for unresolved q126 tail dates

### 3. FIX Architectural Review
- **Determinism**: ADEQUATE.
  - CUBLAS_WORKSPACE_CONFIG set before torch import (lines 88-102) ✓
  - cuDNN deterministic/benchmark flags (lines 123-128) ✓
  - DataLoader generator seeded (lines 444-449) ✓
  - **Caveat**: `warn_only=True` is not fail-fast, PYTHONHASHSEED set inside process is mostly documentary
- **Collapse detector**: REASONABLE/CONSERVATIVE for q126 base rate ~25%
  - Requires `p_max < 1e-4` AND `logit_median < -15` (line 389-401) — both conditions, AND not OR
  - Normal calibrated outputs should not trip it
- **Reseed rescue**: ACCEPTABLE as failure-mode mitigation, NOT label method-shopping
  - Selection on prediction-distribution collapse (p_max + logit_median), NOT on OOS PR/y → bias is bounded
  - All attempts logged (lines 688-694)
  - **Caveat**: changes estimand from fixed-seed to "first non-collapsed seed"
- **All-collapse handling**: ACCEPTABLE for diagnostics if downstream excludes collapsed=True; current code records last collapsed attempt (lines 719-729)
- **Period slicing**: WELL-DESIGNED contiguous OOS slices with insufficient-event guard (line 582-613)
  - **Caveat**: S2025-26 inherits unresolved-label `fillna(0)` issue

### 4. Numerical Correctness
- **pr_auc**: 139 uses same trapezoid PR integral as 129 (lines 282-290 vs 240-248) — does NOT match sklearn step-rule semantics but internally comparable to 129/125
- **ic_spearman**: NOT exact tie-aware Spearman. 139/129 use argsort-of-argsort ordinal ranks (lines 293-299 vs 251-257); 125 used pandas tie-aware ranks (line 218-224). Binary y has many ties.
- **detect_logit_collapse**: math OK — clips with eps=1e-30, log(p/(1-p)), AND threshold

### 5. Pre-Run REQUIRED Fixes (Codex flagged)
1. **Add advertised per_fold_diagnostics.json writer** OR remove from output contract (header line 78-80 advertises it; main writes only provenance + variant_diagnostics + period analysis)
2. **Preserve target NaNs and mask unresolved labels for scoring** — current fillna(0) (line 331) makes unknown q126 tail outcomes count as non-bear in OOS PR/IC + period metrics

### 6. Pre-Run OPTIONAL Improvements (Codex suggested)
1. Replace ic_spearman with tie-aware ranks (`pandas.Series.rank()` or `scipy.stats.rankdata`)
2. Fix docstring mismatch: comment says `p_max<1e-4 OR logit_median<-15` (lines 50-54) but code uses AND (line 401)
3. If all reseeds collapse, set `oos_pr=None` for leaderboard use while still saving predictions/diagnostics
4. Consider `torch.use_deterministic_algorithms(True, warn_only=False)` for strict reproducibility audit run

### 7. Run-Time Risk Estimate
- GPU hours: ~1.5-2.5 hours for q126-only seed-42 sweep; ~3-6 hours worst-case if many variants collapse and reseed
- OOM risk: LOW-MODERATE. 129 peaks under 1.5GB; 139 raises CUDA fraction to 0.50
- Non-completion: MODERATE from runtime/reseed expansion, LOW from syntax (py_compile passed)

---

## Q-Lead Disposition of Codex findings

| # | Finding | Disposition | Action |
|---|---|---|---|
| 1 | Add per_fold_diagnostics writer | **ACCEPT** | Added at line 952+ (writes per_fold_diagnostics.json with provenance + folds + per_variant fold_results_detailed) |
| 2 | Mask unresolved labels for OOS PR/IC | **ACCEPT** | Added `y_resolved_mask` in prepare_data_full + threaded through predict_oos + period_balanced_metrics + filters in `selected_oop[oos_resolved]` for PR/IC |
| 3 (opt) | Tie-aware ic_spearman | **ACCEPT** | Switched to `pd.Series(p).rank().values` (line 295-304) |
| 4 (opt) | Docstring AND/OR mismatch | **ACCEPT** | Updated header (line 50-54) to "AND" |
| 5 (opt) | All-collapse → oos_pr=None | **ACCEPT** | Added `all_collapsed` flag + sets `selected_oos_pr=None` when all 4 attempts collapse (still saves predictions) |
| 6 (opt) | warn_only=False | **REJECT** | Keep `warn_only=True` — some non-deterministic ops (e.g., index_put_ in AMP) are acceptable; hard fail would block runs that v5b/v5d_orig also tolerated |
| 7 (caveat) | PYTHONHASHSEED documentary | **ACKNOWLEDGE** | Retained — torch + numpy + cuda seeds are the load-bearing ones |
| 8 (caveat) | Changes estimand from fixed-seed to first-non-collapsed | **ACKNOWLEDGE** | This is the explicit intent. All attempts logged in `final_attempts` for transparency |
| 9 (caveat) | S2025-26 unresolved-label issue | **FIX-LINKED** | Resolved by Action 2 — period metrics now respect mask |

**Disposition result**: 2 REQUIRED fixes + 3 OPTIONAL improvements ACCEPTED; 1 REJECT (warn_only); 3 ACKNOWLEDGED caveats.

**No PIT violations found.** Sweep cleared for execution.

---

## Post-fix verification

- `python3 -m py_compile scripts/139_patchtst_q126_sweep_FIXED.py` → **PASS**
- Re-launched 2026-05-21 08:50 KST, PID 1674161
- Runtime estimate: 1.5-2.5 GPU hours per Codex estimate, potentially longer due to GPU shared with parallel 140_multiseed.py (PID 1644098)

## Codex review file location
- Prompt: `/tmp/cycle54a_codex_review_prompt_v2.md`
- Output: `/tmp/codex_review_139_FIXED.md`
- Session log: `/tmp/codex_review_output_v2.json`

## REVIEW WORKFLOW COMPLETE
