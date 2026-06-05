# Cycle 58B — Codex Code Review Log

- **Scripts reviewed**:
  - `scripts/186_cross_market_fetch.py` — 7 cross-market features fetch + lag1
  - `scripts/187_panel_v5g_cross_market.py` — v5f_FIXED2 + 7 cross-market merge
  - `scripts/188_patchtst_v5g_q15_strict.py` — Phase 3 driver (delegates to 167b template)
  - `scripts/189_q15_cross_market_aggregate.R` — leaderboard + XGB importance + verdict
- **Reviewed at**: 2026-05-21 15:50 KST
- **Reviewer**: Codex CLI 0.128.0 (`codex exec --sandbox read-only`)
- **Scope**: code correctness ONLY (strategy / cross-market choice / verdict thresholds excluded)
- **Inputs verified**: cross_market_daily.parquet + feature_panel_v5g_cross_market.parquet + 167b_template

## Codex Verdict: CONDITIONAL_PASS

> No future-leak detected. Two MEDIUM-severity FIX items + one NOTE (unit-convention).
> All requested PIT checks (N225/HSI lag1, SPX/DXY/VIX/WTI lag1, USDKRW direction, merge_asof, strict-PIT template, XGB importance) PASS for no future leak.

## Critical Issues (BLOCK)
**None.** No future-leak. No PIT C1 violation. No template assertion mismatch.

## Medium Severity (FIX) — Applied Before Final Run

### C1. FRED VIX/KRW_USD not filtered to non-null observations before merge_asof
- **Location**: `186_cross_market_fetch.py:97 / :151 / :178 / :196` (align_to_spine helper)
- **Issue**: For FRED-sourced series (VIX, KRW_USD), `merge_asof(direction="backward")` was called on the raw df_foreign DataFrame which contains NaN rows for non-trading-day or weekend gaps. As-of merge sees these NaN dates as the "latest" observation, producing post-first-valid NaN holes on the KR spine. Empirical: pre-fix `vix_change_5d_lag1` had 301 post-first-valid NaN, `usdkrw_change_5d_lag1` had 384.
- **Why this is NOT a future leak**: The bug suppresses signal availability (NaN instead of last valid close) — it does not create access to future information.
- **Fix applied (Q-Lead 2026-05-21)**: Added `df_foreign[["Date", name]].dropna(subset=[name]).sort_values("Date")` inside align_to_spine() before merge_asof. Phase 1+2 rebuilt.
- **Verification (post-fix)**:
  - VIX: 2756 NaN → 2455 NaN (301 forward-filled correctly, matches Codex's count exactly)
  - USDKRW: 2839 NaN → 2455 NaN (384 forward-filled correctly)
  - Pre-2000 NaN (2455) remaining = expected (no FRED data exists pre-2000-01-12)
- **Disposition**: FIXED before final Phase 3 launch.

### C2. R aggregate silently accepts missing seeds + does not assert Date/y alignment
- **Location**: `189_q15_cross_market_aggregate.R:83 / :94 / :100 / :104`
- **Issue**: Loop skips missing seed files with `next` and assumes ref_y / ref_dates from first-loaded seed match subsequent seeds without verification. If a seed had even-by-1-row Date misalignment (e.g. from earlier-failed training), mean5 ensemble would silently average misaligned rows.
- **Why this did not fire**: PatchTST template writes deterministic per-fold output Date arrays — empirically all 5 seeds in same cycle have identical Date / y. But the assertion is good practice.
- **Fix applied (Q-Lead 2026-05-21)**: Added 3 assertions per seed loop (row count, Date identical, y identical). Plus loud WARN if <5 seeds present (continues to compute mean but flags as non-canonical).
- **Disposition**: FIXED before Phase 4 run.

## Note (ACCEPT_DOCUMENTED)

### C3. Decimal vs %% unit inconsistency with existing ecos_krw_usd_change_5d_lag1
- **Location**: `186_cross_market_fetch.py:161 / :173` vs `134_ecos_fetch_kr_macro.R:193`
- **Issue**: New cross-market `usdkrw_change_5d_lag1` is decimal (e.g. 0.012 = 1.2%). Existing `ecos_krw_usd_change_5d_lag1` from cycle 53I v5f base panel is in percent (e.g. 1.2). So the panel has BOTH conventions for the same conceptual signal.
- **Why this is acceptable for OOS PR-AUC**: PatchTST template standardizes per-feature (line 296-312) before encoding, so unit difference becomes scale invariance.
- **Disposition**: ACCEPT_DOCUMENTED. Add to backlog: future cycle should normalize all derived-rate features to decimal convention. Not blocking 58B.

## Requested Checks (per prompt)

| Check | Verdict | Notes |
|---|---|---|
| N225 / HSI lag1 PIT | PASS | Row d uses prior KR trading day's Asia close, available before KR 09:00 open on d. |
| SPX / DXY / VIX / WTI lag1 PIT | PASS | Same-date US labels neutralized by `.shift(1)`. US close 16:00 ET = KR 06:00 next day available to KR market open d+1, but lag1 uses d-1 close → conservative double-safe. |
| USDKRW direction (KRW/USD direct) | PASS | Higher = KRW weaker (1500 vs 1100 KRW per USD). Sign convention consistent with expectations (KRW weaker → KR bearish). |
| merge_asof(direction="backward") | FIX-APPLIED | Pre-fix: FRED VIX/KRW NaN propagated as latest observation. Post-fix (C1): dropna before as-of. |
| VIX vs us_stlfsi_lag1 redundancy | PASS | Correlation -0.014 (essentially independent, NOT a duplicate). |
| Strict-PIT template inherit (n_features=86) | PASS | Driver passes `--n_features 86`; template asserts expected count (line 269); train-window col-median fill (line 303-305) handles NaN. |
| XGB importance leak-back risk | PASS | Computed POST leaderboard/verdict, used as diagnostic only, not fed back into PatchTST training/evaluation. |

## Disposition Summary (Q-Lead — code scope)

- C1: **FIXED** in `186_cross_market_fetch.py:104-111` (dropna before as-of). Phase 1+2 rebuilt. Phase 3 relaunched with corrected panel.
- C2: **FIXED** in `189_q15_cross_market_aggregate.R:90-95` (3 assertions per seed + WARN on <5 seeds).
- C3: **ACCEPT_DOCUMENTED**. Added to backlog. Not blocking 58B.

## Post-Phase-4 Self-Discovered Issues (Q-Lead, NOT raised by Codex)

### C4. Panel Date class POSIXct vs target Date class mismatch
- **Location**: `189_q15_cross_market_aggregate.R` XGB section, merge with targets_long_horizon_observable.parquet
- **Issue**: feature_panel_v5g_cross_market.parquet has Date column as POSIXct (with KST 09:00 timestamp), while targets_long_horizon_observable.parquet has Date class. data.table merge produced ALL-NA on ret_q15 (0 rows after na drop).
- **Why this did not fire in 57A aggregate**: 57A scripts use predictions parquets which have Date stored uniformly. XGB importance was a 58B-new addition that bridges panel + targets directly.
- **Fix applied (Q-Lead 2026-05-21)**: Coerce BOTH panel$Date and tgt$Date to as.Date BEFORE merge.
- **Disposition**: FIXED in scripts/189_q15_cross_market_aggregate.R post Phase-4 first run.

### C5. xgboost::xgb.DMatrix pointer alignment error on data.table-derived matrix
- **Location**: `189_q15_cross_market_aggregate.R` XGB DMatrix construction
- **Issue**: `as.matrix(m[, ..feat_cols])` produced a matrix that xgboost rejected with "Input pointer misalignment" error.
- **Fix applied (Q-Lead 2026-05-21)**: Force contiguous via `as.data.frame()` → `as.numeric()` per column → `as.matrix()` → `storage.mode(X_mat) <- "double"`.
- **Disposition**: FIXED, XGB importance now runs (top 30 features ranked correctly).

## Sign-Off

- Codex code review: CONDITIONAL_PASS with 2 FIX requested. Both Codex FIX applied.
- Q-Lead self-discovered FIX: 2 additional (C4 Date class merge, C5 xgboost pointer alignment).
- Net additional latency from C1 fix: ~30s panel rebuild + ~10 GPU-min wasted from buggy Phase 3 (killed at Fold2 boundary).
- Net additional latency from C4+C5 fixes: ~3 min (2 R aggregate reruns).
- Total cycle 58B (Phase 1+2+3+4 + Codex review + 4 FIX): 50 min.
