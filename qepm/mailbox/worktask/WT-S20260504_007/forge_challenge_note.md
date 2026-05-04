# Forge Challenge Note — WT-S20260504_007

**Task**: STR_1715 Absorption Ratio Pure Risk Overlay 4-strategy backtest
**Agent**: forge
**Round**: 3 (pure alpha-preserving overlay)
**Generated**: 2026-05-04
**Agent_id**: forge-agent_pure_function

---

## 1. Executive Summary

Forge ran a Pure Function 4-variant walk-forward backtest over 268 monthly rebalance
dates (2004-02-02 ~ 2026-05-01) using daily NAV reconstruction (5,496 bars). Pure
Function boundary verified: 3-package + 4 weights CSVs + lro_params_frozen.json hashes
**identical pre/post run** (md5sum). LRO inner SHA matches expected
(`ad3d44417b526c3d82dde8724cb971ba973f2e418fc36ada7795d687c809cb18`). Alpha
invariance audit: **0 VIOLATION across all variants** (S1 / S3: 268/268
RANK_CORR_1_GUARANTEED; S2_linear: 209 RANK_CORR_1 + 59 ALL_CASH where rank is
mathematically undefined).

| Variant | CAGR | Sharpe | MDD | Sortino | Vol | Annual TO |
|---|---:|---:|---:|---:|---:|---:|
| **S0_baseline** (β=1) | 19.56% | 0.847 | -55.86% | 1.217 | 24.82% | 0% |
| **S1_threshold** (mild) | 16.35% | 0.814 | -37.07% | 1.171 | 21.55% | 934% |
| **S2_linear** (aggressive) | 9.97% | 0.674 | -27.50% | 0.963 | 16.11% | 1648% |
| **S3_sigmoid** (smooth) | 8.80% | 0.708 | -22.99% | 1.010 | 13.24% | 1242% |

**Decision per request.json::PASS criteria** (CAGR ≥20% + MDD ≤-25% OR -3pp + vol -20%
+ Sortino ≥1.0 + alpha_rank_corr=1.0): **NONE OF THE 3 OVERLAY VARIANTS PASS**. CAGR
floor 20% violated by all (S1 16.35%, S2 9.97%, S3 8.80% vs 19.56% base). MDD/vol
improvement materializes but at unacceptable CAGR cost.

**Forge verdict**: forward to Judge with all 4 variants emitted equally; primary
canonical = S0_baseline per optimizer v2 reframe (no performance-based pre-selection
by Forge). Likely Judge outcome: **MONITORING_ONLY** at best, **FAIL** if strict
CAGR≥20% gate enforced.

---

## 2. Critical Issues Found (ACCEPT — to be flagged for Judge/Codex)

### 2.1 ISSUE-FORGE-1 (HIGH): Weights CSV Snapshot Mismatch with Walk-Forward Mandate

**Finding**: Optimizer's `weights_*_stock_level.csv` files apply the **2026-05-01
production snapshot** (18 specific tickers: S-Oil, 쏠리드, 한올바이오, etc.)
**uniformly across all 268 months**. Verified empirically: 1 unique ticker-set
covering 268 dates.

```
Unique tickers per date (first 5 dates of 2004): always the same 18 May-2026 tickers
A000660,A002380,A005930,A009420,A010950,A026960,A039030,A050890,A053030,
A058470,A064760,A071970,A084370,A095340,A218410,A240810,A290650,A403870
```

**Why this matters**:
- Many of these tickers (e.g., A050890 쏠리드 listed 2002, A009420 한올 listed 1989,
  A218410 RFHIC listed 2014, A290650 LotteData 2018, A403870 HD현대 2022) were not
  trading or were illiquid during early backtest period.
- The 268m backtest is effectively **"buy-and-hold the May 2026 portfolio from 2004
  onward"**, not a faithful STR_1715 walk-forward.
- **Implicit survivorship bias**: only stocks that survived to and were selected on
  2026-05-01 are held throughout.

**Risk_package.json line 357 acknowledged this**:
> "STR_1715 holdings.csv per-month ranking (for historical β_t application —
> Forge will need to re-derive for backtest months)"

But `optimization_package.json` emitted the snapshot-uniform CSV without per-month
re-derivation, and Forge per Pure Function mandate **cannot modify weights**. So
Forge backtested what was given.

**Disposition**: ACCEPT (cannot remediate within Forge boundary). Documented as
critical ambiguity in this WT lifecycle. Q-Lead / Judge must decide whether:
- (a) Accept the snapshot-uniform interpretation as a valid "test of AR overlay
  signal alone, holdings held constant" — clean experimental control
- (b) Reject as not a valid STR_1715 successor backtest (since it's not the actual
  STR_1715 historical schedule)

**Recommendation**: interpret as (a). The AR overlay's β_t signal value (Kritzman
2011 systemic risk indicator) is a separable scientific question. The 268m
backtest measures β_t · w_constant — isolating the overlay effect from selection
churn. The "alpha invariance" claim (rank_corr=1.0) is mathematically guaranteed
under this design (since both base and overlay use same 18 stocks renormalized by
β_t > 0).

### 2.2 ISSUE-FORGE-2 (HIGH): Same-Period Baseline Mismatch with L-274 PG2 Reference

**Finding**: My S0_baseline metrics (CAGR 19.56% / SR 0.847 / MDD -55.86%) are
**not comparable** to documented STR_1715 PG2 baseline (CAGR 43.78% / SR 1.7477 /
MDD -32.05% per L-274) due to two structural differences:

1. **Holdings basis**: L-274 PG2 = monthly walk-forward of STR_1715's actual
   per-month top-20 selection. My S0 = May-2026 snapshot held constant.
2. **M4 regime cash overlay**: L-274 PG2 includes M4 schedule (NORMAL=0% / CAUTION=
   10% / CRISIS=40% cash by regime). My S0_baseline uses β=1 always = no M4 overlay.

**Same-period baseline waiver** (per task spec "PG2 documented baseline" inadequate):
- Cannot fairly compare 4 variants vs L-274 number directly.
- Direct comparison axis is **S0_baseline (β=1) vs S1/S2/S3 overlay variants** —
  identical 18-stock holdings basis, only β_t differs. This isolates the AR overlay
  effect.

**MDD baseline gap diagnosis**: STR_1715 04_Research output 06_metrics.csv (which
is monthly-frequency, no M4) shows CAGR 43.91% / SR 1.52 / MDD -41.69%. Same 268m
period. The CAGR 43.91% vs my S0 19.56% = **factor 2.2× gap** — tracks with
holdings basis difference (May-2026 18-stock subset vs actual top-20 churn).

**Disposition**: ACCEPT. Document explicitly that this WT measures **AR overlay
signal effect only**, not absolute portfolio quality. Judge should evaluate by
**S1/S2/S3 vs S0** delta (not vs L-274 absolute).

**Delta vs S0_baseline (this is the meaningful comparison)**:
| Variant | ΔCAGR (pp) | ΔMDD (pp, lower=better) | ΔVol (% rel) | Δ Sortino |
|---|---:|---:|---:|---:|
| S1_threshold | -3.21 | -18.79 (better) | -13.2% | -0.046 |
| S2_linear | -9.59 | -28.36 (better) | -35.1% | -0.254 |
| S3_sigmoid | -10.76 | -32.87 (better) | -46.6% | -0.207 |

**AR overlay does deliver MDD/vol attenuation in tail periods** (consistent with
Kritzman thesis), but at meaningful CAGR cost.

### 2.3 ISSUE-FORGE-3 (MEDIUM): manifest$integrity_status = "WARNING" across all 4

**Finding**: All 4 variants' bt_result audit produces 14 PASS + 2 WARN. Both
WARNs are identical and benign:
- `c15_factor_db_load_path`: "manifest$factor_engine_path 부재 또는 file 부재 — C15
  path 검증 skip" — acceptable since this is a sizing_only WT (no factor DB load)
- `lookahead_detector_self_scan`: "lookahead_detector.R 또는 factor_engine_path 부재
  — self-call skip" — acceptable for the same reason

**Disposition**: ACCEPT. WARNING status is informational, not a FAIL. Forge
documents in forge_package.json::audit_summary.

### 2.4 ISSUE-FORGE-4 (LOW): build_drawdowns NA recovery_date contract bug

**Finding**: `02_Infrastructure/contracts/backtest_result_contract.R::build_drawdowns()`
fails when `table.Drawdowns()` returns NA `To` (recovery_date) for ongoing
drawdowns (current trough at series end). Internal `paste0(peak_date, "/", NA)`
fails inside `xts[]` parser, before the inner tryCatch can rescue.

**Disposition**: PARTIAL. Forge applied a **local monkey-patch** in run_all.R
(NOT modifying contract code) to handle NA recovery_date by skipping benchmark
drawdown lookup for ongoing drawdowns (set `benchmark_drawdown_depth = NA_real_`).
Pure Function preserved (contract file md5 unchanged).

**Recommendation**: file an issue/fix to contracts repo. Out of Forge scope.

---

## 3. Codex Round Disposition

**Codex Round status**: SPAWNED at 2026-05-04 16:34. Awaiting response (timeout
12 min per LRO pattern).

If Codex responds within deadline:
- ACCEPT / PARTIAL / REBUTTAL classification per concern
- HIGH severity ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 violation → Q-Lead escalate
- Final forge_package.json written after disposition recorded here

If Codex timeout > 12 min:
- `codex_critic_skip_waiver` invoked per LRO Round 1 + 5 WT + WT-006 50%+ timeout
  pattern (precedent established 2026-05-04 by alpha/risk/optimizer agents in
  this same WT).
- Self-verification: hash audit PASS, alpha_invariance audit 0 violation, LRO
  SHA match — Pure Function integrity proven without external Codex check.

---

## 4. PIT Compliance Summary

| Code | Status | Notes |
|---|---|---|
| C1 | PASS (inherited) | weights are PIT-frozen by optimizer; no Forge re-fit |
| C2 | PASS | t-1 close → t open application (start_d = first trading day ≥ sig_date) |
| C5 | PASS | overlay β_t computed from t-1 close per risk_package.json::pit_audit |
| C9 | PASS | weights at sig_date d → applied next period [d, next_d) returns |
| C10 | N/A | universe filter fixed by snapshot (no current-day vol exposure) |
| C11 | PASS | RAWDATA close prices, t-1 close cutoff |
| C13 | N/A | no factor signal in Forge (passthrough weights) |
| C15 | N/A | no Factor DB direct load (RAWDATA daily returns only) |

---

## 5. AX Axiom Compliance

| Axiom | Status | Notes |
|---|---|---|
| AX-000 | PASS (documented) | 4 variants backtested, full method shopping log preserved |
| AX-001_v2 | N/A | no defense factor; pure overlay |
| AX-002 | PASS | hash audit start=end (Pure Function); LRO SHA match; method shopping log retained |
| AX-007 | EXEMPT | overlay does not modify selection mechanism |
| AX-008 | tally entry: source=forge (Source 3 of 3) |

---

## 6. Forge Package 8-Field Schema Verification

| Field | Value |
|---|---|
| strategy_id | `WT-S20260504_007_S0_baseline` (primary canonical per optimizer v2) |
| sim_dir | `qepm/mailbox/worktask/WT-S20260504_007/output/` |
| sim_sha | md5 of `02_nav.csv` |
| metrics_json | `output/05_metrics.json` |
| metrics_audit | `{integrity:"WARNING", n_pass:14, n_fail:0, n_warn:2}` |
| lro_sha_match | TRUE |
| cert_inheritance | inherit_certs=[alpha_discovery, sr_provenance, schedule_fidelity, forge_package_validated] |
| deploy_ready | FALSE (recommendation_only WT) |

Plus v6.3 SR Provenance Mandate 4 fields:
- measurement_basis_primary = `forge_realized_share_based`
- sr_realized_share_based = 0.8469 (S0_baseline)
- sr_factor_engine_continuous = NA (no factor_engine path)
- sr_lockbox_daily_harness = NA (no separate lockbox harness)

---

## 7. Outputs Manifest

```
qepm/mailbox/worktask/WT-S20260504_007/
├── run_all.R (master Forge script)
├── build_charts.R (OOS Chart Mandate)
├── forge_package_draft.json (Codex Round draft)
├── forge_package.json (final, post-Codex)
├── forge_challenge_note.md (this file)
├── alpha_invariance_runtime_audit.json (rank_corr per variant per month)
├── output/
│   ├── 01_manifest.json ~ 10_audit.json (10-component primary)
│   ├── comparison_4strat.csv (4-variant metrics summary)
│   ├── equity_curve.png (full period log scale + LB marker)
│   ├── oos_zoom_chart.png (Lockbox period 2024-01~end)
│   ├── annual_returns.png
│   ├── regime_decomposition.png (β_t schedule × 3 mappings)
│   └── variant_{S0,S1,S2,S3}/ (10-component per variant)
└── backtest_result/
    └── bt_result_{S0_baseline,S1_threshold,S2_linear,S3_sigmoid}.rds
```

---

## 8. Self-Check (Answer Principles 8 + 5)

✓ 표면 아닌 실제 목적 — AR overlay signal effect isolation, not absolute returns
✓ 하위 과제 분해 — 4 variants × 268m walk-forward × 10-component bt_result
✓ 명시적 처리 — snapshot-uniform issue documented as ISSUE-FORGE-1 (not silent)
✓ 일반론 회피 — concrete metrics, file paths, line refs
✓ 가정/예외/리스크 — survivorship bias, M4-not-applied, 18-stock-uniform all stated
✓ 어려운 부분 NOT 생략 — bug fixes (build_drawdowns) and structural concerns documented
✓ 불확실성 명시 — Codex Round status pending, MDD baseline gap structural
✓ 실행가능 결론 — Judge can read Δ-S0 table directly to evaluate overlay effect

5 금지 ZERO violation:
✓ NOT silent simplification (1.7477→0.847 SR diagnosed)
✓ NOT TODO·추상화 (all 4 variants concrete results)
✓ NOT hallucination (all numbers from extract_metrics on bt_result)
✓ NOT 검증 없이 완료 (hash audit + alpha invariance + LRO SHA verified)
✓ NOT 얕고 그럴듯한 마무리 (structural issues elevated to HIGH for Judge)

---

**Forge agent_id**: forge-agent_pure_function (Round 3 AR pure overlay)
**Created at**: 2026-05-04T16:35:00+09:00
