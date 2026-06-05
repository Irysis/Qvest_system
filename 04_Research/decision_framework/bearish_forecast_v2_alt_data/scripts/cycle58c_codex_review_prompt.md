# Cycle 58C — Codex Code Review (Code Only) Prompt

## Scope (코드만)
4 scripts created for Cycle 58C:
1. `scripts/190_panel_v5h_interactions.R` — v5h panel build (91 features = v5g 86 + 5 cross-market × KR interactions)
2. `scripts/191_v5g_q15_10seed_extension.py` — 10 NEW seeds extension of 53I_v5g_cross_market q15 (15-seed mean ensemble)
3. `scripts/192_patchtst_v5h_q15_strict.py` — v5h 5-seed driver (re-uses 167b template)
4. `scripts/193_patchtst_v5g_FIXED2_q15.py` — Phase 4 DEFERRED stub (parity-verified)
5. `scripts/194_q15_58c_aggregate.R` — 3-variants aggregator + bootstrap significance test

## Review focus

### Q1. 10 NEW seeds reproducibility (191)
- Does 191 properly import `prepare_data` + `run_one_seed` from 167b template module?
- Does it correctly inherit the strict determinism settings (CUBLAS_WORKSPACE_CONFIG, cudnn.deterministic, per-seed manual_seed_all)?
- File-naming: `predictions_53I_v5g_cross_market_seed{S}_y_tail_q15.parquet` — matches 188 exactly?
- 5-seed copy step (Existing → 15seed dir) preserves predictions byte-identical?

### Q2. Interaction features correctness (190)
- Are all 5 interactions products of `_lag1` source columns? (PIT-safe)
- The `asia_joint_momentum_z_lag1` uses `rolling_z()` with width=252d. Is the rolling-z PIT-safe (no future leakage)?
- The `rolling_z` uses `rollapplyr(..., partial=TRUE)` — does partial=TRUE introduce lookahead at the start? (Likely safe since it's left-aligned)
- The fillna(0) policy for pre-2000 history — is this consistent with 187_panel_v5g_cross_market.py?

### Q3. v5g_FIXED2 Phase 4 deferral (193)
- Does the pre-cycle audit (`cycle58c_bear_date_audit.R` Step 4) correctly verify BBVA columns?
- max_abs_diff = 0.000000 for 8/8 BBVA cols between v5f_FIXED2 and v5g — sufficient evidence for PARITY?
- Would v5g_FIXED2 model run produce strictly identical predictions to 58B v5g run? Justify.

### Q4. Bootstrap CI implementation (194)
- `boot_pr()`: B=1000, paired-bootstrap idx? Or independent samples?
- `boot_delta_pr()` (paired delta): samples same idx for both p_new and p_base. Correct for paired test?
- 15-seed mean ensemble: arithmetic mean across seeds (not weighted by per-seed std). Standard convention?
- CI lower > baseline CI upper criterion: conservative but standard (no overlap = significant).
- `p_gt_0` from paired-delta bootstrap: thresholds 0.95/0.90 for STAT_SIG/MARGINAL — sufficient?

### Q5. Edge cases
- `prepare_data` in 167b loads `targets_long_horizon_observable.parquet` with phantom-0 guard. Does 191 inherit this guard correctly (since it imports prepare_data directly)?
- `run_one_seed` writes pred file to `output_dir` — does 191 set output_dir = cycle58c_v5g_15seed correctly?
- 192 driver: identical CLI to 188 except cycle name + panel + output_dir + n_features=91. Any inherited args drift?
- 194 aggregator: SEEDS_15 = c(SEEDS_5, NEW_10). When iterating, accepts both `p_oos` and `p_strict`/`p_expert` column names. Robust?

### Q6. PIT discipline checks
- Cross-market × KR interaction features: all source features `_lag1`-shifted at source. Product preserves lag1 stamp. PIT-safe. ✓ (verify with code)
- No `prod(1+r)-1`, no `cumprod(1+r)`, no `0.8*r1+0.2*r2` self-aggregation in any script.
- Forward labels (Cycle 50 fix) — does 167b template use them via targets_long_horizon_observable.parquet?

### Q7. Reproducibility
- All seeds deterministic on same panel + same hparams: same predictions across runs?
- Bootstrap reproducibility: `set.seed(42)` in `boot_pr` and `boot_delta_pr` — produces same CIs across reruns?

## Output format
- For each Q1~Q7: ACCEPT / PARTIAL / REBUTTAL with line reference (file:line)
- Critical concerns list
- weakest_assumption
- recommendation: PASS_CODE_ONLY / NEEDS_FIX / BLOCK
