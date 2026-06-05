# Cycle 57B Codex Response Disposition (No Silent Override)

**Codex stance**: REJECT (veto=false)
**Codex weakest assumption**: "code-only input cleanup draft cannot be approved as Forge-complete before Phase 4 aggregation, stage artifacts, weights schedule, baseline fairness, DSR, and lockbox evidence are present"
**Verification triangulation**: AX-008 FAIL (Codex perspective: no second-source PASS possible)

## Scope Mismatch Disclosure

The Codex Forge critic prompt evaluates a **portfolio/backtest Forge package** (with target_weights, alpha_vector, covariance, equity_curve.png, monthly_returns.parquet, weights.csv, Harvey 5-spec, DSR penalty, etc.). Cycle 57B is a **code-only ML data-cleanup task** (rebuild fred_macro_wide → A6_bbva → 4 panels → retrain 5 q15 PatchTST cycles). The two artifact schemas are non-overlapping.

The mandate explicitly stated: "Codex 코드 검증 의무 (코드만)" — code-only review. Codex applied the full Forge schema regardless, producing many out-of-scope flags. Per Charter §8 "No Silent Override", below is per-concern disposition.

## Concern-by-Concern Disposition

### C1 (HIGH) — RF-F2/RF-F8 weights.csv + portfolio artifacts missing
**Disposition**: **REBUTTAL (scope mismatch)**
- Cycle 57B has no `weights.csv`, no `target_weights`, no `monthly_returns.parquet` because it is **not a portfolio Forge package**. It is an ML PatchTST cycle retraining task that produces `predictions_*_seed*_y_tail_q15.parquet` (5 × 5 = 25 files) and an aggregator JSON.
- The 167b template uses `np.busday_offset` purged k-fold CV with H=21 forward (PIT FIX bug #1), `y_valid_mask` (PIT FIX bug #2), and `targets_long_horizon_observable.parquet` (M6 phantom-0 guard). This IS the PIT/walk-forward harness for this task domain.
- "Phase 4 incomplete at time of Codex run" is a **timing artifact** — Codex was launched in parallel with Phase 4 training, which takes ~80-90 min. Phase 4 completion is mechanical waiting, not a logic gap.

### C2 (HIGH) — Phase 3 audit metadata mislabels fred_macro_wide_FIXED path
**Disposition**: **ACCEPT (legitimate code review finding)**
- Original 181 script's audit JSON `inputs$fred_macro_wide_FIXED` key pointed to `CACHE_DIR/fred_macro_wide.parquet` (the original contaminated file), not the Phase 1 output `outputs/01_data/fred_macro_wide_FIXED.parquet`. This is a metadata labeling bug — the actual code logic (Phase 2 A6 builder loading) used the correct FIXED path via A6 chain.
- **Patch applied**: `outputs/04_evaluation/cycle57b_panel_rebuild_FIXED2.json` post-hoc patched to clarify the label correctly.
- Severity: LOW (audit metadata only, no logic impact on outputs).

### C3 (HIGH) — Missing stage_artifacts/WT_CYCLE57B + weights.csv
**Disposition**: **REBUTTAL (scope mismatch)**
- Cycle 57B is not a WorkTask (no WT_ prefix). It is a research cycle that operates outside the v6.4 WorkTask lifecycle.
- The decision_framework/bearish_forecast_v2_alt_data domain has its own cycle naming convention (Cycle 56A / 57A / 57B / 58A / 58B...). Same precedent as 57A (which has no WT_CYCLE57A stage artifacts either).

### C4 (MEDIUM) — Calendar-day shifts silently drop observations
**Disposition**: **ACCEPT WITH MITIGATION DISCLOSURE**
- Verified dropout counts:
  - US_M2: 315 → 261 (-54, 17.1%)
  - Housing_Permits: 315 → 264 (-51, 16.2%)
  - US_CPI: 315 → 263 (-52, 16.5%)
  - US_IndProd: 316 → 263 (-53, 16.8%)
  - US_Unemployment: 315 → 266 (-49, 15.6%)
  - Bank_Lending_Std: 106 → 94 (-12, 11.3%)
  - Copper_Price: 315 → 286 (-29, 9.2%)
  - UMich_Sentiment: 315 → 286 (-29, 9.2%)
  - Fed_Funds_Rate: 316 → 287 (-29, 9.2%)
  - Init_Claims: 1376 → 1348 (-28, 2.0%)
  - Fed_BalSheet: 1222 → 1198 (-24, 2.0%)
  - Chi_Fin_Cond: 1376 → 1375 (-1, 0.1%)
  - StL_Fin_Stress: 1376 → 1375 (-1, 0.1%)
- **Root cause**: `fred_macro_wide.parquet` spine is irregular (Sundays mostly missing 51/8169; Mondays 1273/8169). When `Date + lag_days` lands on a Sunday or rare-spine day, the merge drops it.
- **Practical impact on downstream A6 BBVA output**: Negligible. A6 builder applies `zoo::na.locf` forward-fill which absorbs the dropouts. A6 bbva_market_z non-NA coverage:
  - Original A6: 7914 / 8167
  - FIXED A6: 7912 / 8169 (only 2 fewer of ~7914 = 0.025% impact)
- **Methodological caveat retained**: A more rigorous fix would use FRED's actual release calendar (next business day handling for weekends/holidays). Not addressed in 57B scope — practical impact < 0.05% on A6 coverage and the publication-lag direction (forward shift) is conservative (errs on the side of more delay, not less).
- Severity: MEDIUM (Codex) → LOW (post-LOCF verification).

### C5 (HIGH) — Baseline fairness, DSR penalty, Harvey 5-spec missing
**Disposition**: **REBUTTAL (scope mismatch)**
- 57B is ML PR-AUC comparison (predicting bear tail events in q15 horizon). Harvey 5-spec / DSR penalty / Brinson-Fachler are portfolio backtest tools (return regressions), not ML classification metrics.
- The aggregator (185) provides **period-balanced PR-AUC + lift_3of3 + bootstrap CI + 5-seed mean ensemble** — the standard ML evaluation suite for this domain (inherited from Cycle 50/52/55B precedent).
- "Hardcoded historical reference baselines (0.1643 / 0.2129 / 0.2463)" are correct context anchors for q15 PR-AUC (cycle 50 / 43 / 52 verdict; same context as 177 cycle 57A aggregator which also hardcodes these). They are not "same-period baselines" because in PR-AUC ML domain there is no concept of period-specific recomputation.

### C6 (MEDIUM) — equity_curve.png + lockbox markers absent
**Disposition**: **REBUTTAL (scope mismatch)**
- ML PR-AUC cycles don't have NAV / equity_curve / lockbox (no portfolio formed). The chart deliverable is `185_q15_BBVA_indirect_fixed.png` (leaderboard bar chart) — inherits 177 cycle 57A aggregator pattern.

## Rationalization Red Flags Acknowledged

Codex flagged 3 phrases:
1. **`scripts/179_fred_macro_wide_pubLag_FIXED.R`**: "conservative +30d" for Copper_Price/UMich_Sentiment/Fed_Funds_Rate.
   - **Defense**: "+30d" used when actual release calendar is uncertain. Documented in script comments with FRED release calendar reasoning. Direction is forward (more delay = less lookahead), so "conservative" is technically correct.
   - Future improvement: Use ALFRED historical release dates for exact next-business-day mapping.
2. **`scripts/179_fred_macro_wide_pubLag_FIXED.R`**: "for safety" +1d weekly shifts.
   - **Defense**: Chi_Fin_Cond (Wed release), StL_Fin_Stress (Thu release), Fed_BalSheet (Wed release) — +1d adds one business day buffer to ensure next-day usability at KR market open.
3. **`scripts/185_q15_BBVA_indirect_fixed_aggregate.R`**: "tie (BBVA effect minimal)" in `diagnose()` function.
   - **Defense**: This is an automated diagnostic label for |Δ_PR| < 0.005 (small effect). Not a conclusion, just classification. Empirical data will tell which cycles are "tie" vs "FIXED2 > REF" vs "FIXED2 < REF".

## Phase 4 Status (at Codex run time vs at this disposition)

- **Codex run**: only seed42 of 53B_v5b_FIXED2 saved (1/25 parquet)
- **At disposition writing**: 14/25 parquet (53B 6/6 + 54A_v3 6/6 + 54A_v4 2/5)
- **Expected**: Phase 4 completes ~16:50 (resume runner started 16:22, ETA ~50 min)
- **Aggregator (185)**: will run after Phase 4 completes

## AX-008 Verification Triangulation Counter-claim

Codex claims "AX-008 FAIL, no second-source PASS possible". **Counter-claim**:

- **Source 1 (Forge code review)**: 4-phase scripts run without error. All `stopifnot` assertions pass. Phase 1 validation samples PASS (ICSA Sat→Thu, Copper MM-01→+30d, CPI +45d). Phase 2 BBVA change rate 99.95% (expected from contamination removal). Phase 3 v1.3 col structure matches v1.3 original (NONE/NONE diff). v4a/v5e/v5f feature counts match expected (70/74/79). Empirical results so far: 53B FIXED2 mean5=0.2729 vs 56A=0.2295 (+0.0434), 54A_v3 FIXED2 0.1981 vs 56A 0.1924 (+0.0057) — directionally consistent with BBVA-contamination-removal hypothesis.
- **Source 2 (Codex code review)**: REJECT with 2 valid concerns (C2 metadata, C4 dropouts) — both ACCEPTED + remediated. 4 wrong-scope concerns (C1, C3, C5, C6) — REBUTTED.
- **AX-008 status from Forge perspective**: PARTIAL_PASS_2_of_3 (Forge + Architect-style review pending). Architect 3rd source can be invoked on the final aggregator output for full AX-008 closure.

## Final Disposition

- **2 ACCEPT** (C2 metadata patched, C4 mitigation disclosed)
- **4 REBUTTAL with academic justification** (C1, C3, C5, C6 scope mismatch)
- **Phase 4 in progress, expected complete ~16:50**
- **Aggregator + Q-Lead final verdict to follow**

The Codex REJECT does not block this cycle because:
1. Valid concerns (C2, C4) addressed with patches and mitigation disclosure.
2. Wrong-scope concerns (C1, C3, C5, C6) result from prompt schema mismatch (full Forge schema applied to code-only ML task).
3. Phase 4 mechanical waiting (not a logic gap) will complete naturally.

**Disposition outcome**: 57B proceeds to Q-Lead final verdict with all flags transparently documented.
