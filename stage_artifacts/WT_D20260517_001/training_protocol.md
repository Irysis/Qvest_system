# DPL_KR_v1 Training Protocol

**WT-D20260517_001 · alpha-research Step 2.4**
**Author**: alpha-research agent
**Date**: 2026-05-17
**Lineage**: literature_review.md §5 / pit_audit.json effective_sig_date_count_after_caveats / dpl_architecture.md §4

---

## 0. Purpose

본 protocol은 DPL_KR_v1 모델의 walk-forward training 절차를 정의한다. **Forge agent의 정확한 구현이 의무**. PIT C1~C15 strict + Charter §1 (PIT-only).

---

## 1. Sample availability (post-PIT audit)

**Effective sig_dates** (post pit_audit.json caveats — REVISED with macro_ prefix scan):

- **Option A (24m features INCLUDED)**: 2016-01-30 ~ 2026-04-30 = **124 sig_dates** with **644 features** (955 KEEP - 320 macro-prefixed - 8 reconciliation)
- **Option B (24m features EXCLUDED)**: 2015-02-27 ~ 2026-04-30 = **134 sig_dates** with **608 features** (644 - 36 rolling 24m/12m)
- **Option C (HARSH PIT, deferred)**: full lookahead_detector.R scan + automated PIT C1 violation HARD ABORT at Forge entry

**Recommendation**: **Option A** (more features, fewer sig_dates). Rationale: DPL is high-dimensional learner; 36 rolling features (24/12m) provide regime-conditional signal. 10 sig_date sample loss is acceptable cost.

**MACRO DROP RATIONALE**: 320 macro-prefixed features (60 direct family=Macro + 260 macro-derived via F/G/H/I layers) have NA rate = 1.0 for most of training period due to FRED/ECOS data source coverage gaps. Including them creates a degenerate signal source (constant NA → imputed cross-section median → information leak risk + zero alpha contribution). Drop is PIT-correct mitigation.

---

## 2. Walk-forward Configuration

### 2.1. Request.json original spec (infeasible)

```
train 60m + val 12m + test 12m × 5 windows non-overlap
first_train_start 2010-01, last_test_end 2026-04
```

**Infeasibility**:
- 5 × 84m = 420 sig_date-months required (non-overlap)
- Effective sample under Option A = 112 sig_dates × 1 month = 112 sig_dates
- **Discrepancy**: 420 vs 112 — request infeasible by **3.75×**.

### 2.2. Adjusted protocol (RECOMMENDED)

**Option B-modified (overlapping windows, 5 windows shift 12m)** — start 2016-01:

```
Window 1: train 2016-01 ~ 2020-12 (60m, 60 sig_dates) | val 2021-01 ~ 2021-12 (12m, 12 sig_dates) | test 2022-01 ~ 2022-12 (12m, 12 sig_dates)
Window 2: train 2017-01 ~ 2021-12 (60m)               | val 2022-01 ~ 2022-12 (12m)               | test 2023-01 ~ 2023-12 (12m)
Window 3: train 2018-01 ~ 2022-12 (60m)               | val 2023-01 ~ 2023-12 (12m)               | test 2024-01 ~ 2024-12 (12m)
Window 4: train 2019-01 ~ 2023-12 (60m)               | val 2024-01 ~ 2024-12 (12m)               | test 2025-01 ~ 2025-12 (12m)
Window 5: train 2020-01 ~ 2024-12 (60m)               | val 2025-01 ~ 2025-12 (12m)               | test 2026-01 ~ 2026-04 (4m, partial)
```

- **5 walk-forward windows shift 12 months each**
- **Coverage**: train spans 2016-01 ~ 2024-12 (9 years), val/test spans 2021-01 ~ 2026-04
- **Effective test sample**: Window 1-4 test (48m), Window 5 partial test (4m)
- **Net usable test**: ~48 + 4 = **52 sig_date-months**
- **Pros**: 5 windows confirms stability; non-overlap test periods 2022~2026; sample efficient
- **Cons**: Overlapping train sets (Windows 1-4 share 2020~2022); standard cross-validation independence assumption relaxed

### 2.3. Alternative Option A-modified (non-overlap, 3 windows)

```
Window 1: train 2017-01 ~ 2020-12 (48m) | val 2021-01 ~ 2021-12 (12m) | test 2022-01 ~ 2022-12 (12m)
Window 2: train 2018-01 ~ 2022-12 (60m) | val 2023-01 ~ 2023-12 (12m) | test 2024-01 ~ 2024-12 (12m)
Window 3: train 2019-01 ~ 2024-12 (72m) | val 2025-01 ~ 2025-12 (12m) | test 2026-01 ~ 2026-04 (4m)
```

- 3 walk-forward windows with **growing train sets** (48m → 60m → 72m)
- Non-overlap test
- **Net usable test**: 12 + 12 + 4 = 28 sig_date-months
- **Cons**: Only 3 windows; reduced stability signal

### 2.4. PROTOCOL DECISION

**Adopted: Option B-modified (5 overlapping shift-12m)**. Justification: 5 windows provide better stability assessment despite overlapping train sets; 40 sig_date-months net usable test > 28 of Option A-modified.

---

## 3. Per-window training pipeline

```
[Read features_master.parquet]
  ↓
[Filter sig_date ∈ train_window]
  ↓
[Subset to 895 KEEP-effective features] (or 850 if Option B w/o 36m)
  ↓
[Per sig_date: liquidity LIQ_20d >= 2e8 KRW + admin/halt/UnfaithfulDisc filter]
  ↓
[Per sig_date: cross-section median imputation per feature]
  ↓
[Per sig_date: 1st-99th percentile winsorization per feature]
  ↓
[Per sig_date: cross-section Z-score per feature (Z_Score_Aligned C13)]
  ↓
[Build target: t+1 return r_{i,t+1} = (P_{i,t+1} - P_{i,t}) / P_{i,t}]
  ↓
[Forward through DPL_KR_v1 — see dpl_architecture.md §2]
  ↓
[Compute Net-Sharpe Utility Loss — dpl_architecture.md §3]
  ↓
[Adam backprop, lr=1e-4, β1=0.9, β2=0.999, weight_decay=1e-4]
  ↓
[End of epoch: validate on val_window]
  ↓
[Early stop: patience=5 epochs no val improvement]
```

---

## 4. Hyperparameter Grid

| HP | Grid | Default | Notes |
|---|---|---|---|
| lr | {1e-4, 5e-5, 1e-5} | 1e-4 | Adam standard |
| dropout | {0.2, 0.3, 0.4} | 0.3 | Sample-bias prone |
| γ_cost | {0.5, 1.0, 2.0} | 1.0 | Wang-Hasuike 2026 §5 range |
| λ_cvar | {0.25, 0.5, 1.0} | 0.5 | Tail penalty |
| τ_anneal_min | {0.05, 0.1, 0.2} | 0.1 | Gumbel softmax low limit |

**Search strategy**: Random search 20 trials per walk-forward window (Bergstra-Bengio 2012 — far more efficient than grid). 100 total runs. **Per-run GPU time ≈ 30 min (estimate, GPU-bound, RTX 4080 SUPER). Total ≈ 50 GPU hours**.

**Cost-aware ablation deferred**: γ_cost grid sweep is the highest priority ablation post-Forge. If admit, scale down to 5 trials × 5 windows for production retrain.

---

## 5. Stopping Criteria

### 5.1. Early stopping (per window)

- **Metric**: val_window loss (Net-Sharpe Utility Loss)
- **Patience**: 5 epochs of no improvement
- **Restore best**: track best val_loss epoch, restore params from that epoch

### 5.2. Failure cutoff abort

Per request.json failure_cutoffs:

| Condition | Action |
|---|---|
| `train NaN explode` | ABORT, hyperparam retune |
| `val loss diverge for > 10 epochs` | ABORT, model architecture issue |
| `constraint violation rate > 1%` (post-projection audit) | ABORT, projection re-design |
| PIT C1 violation detected mid-training | **HARD ABORT** |

### 5.3. ABORT entire cycle

- **DPL alone OOS SR (148m subset, or 40m test) < 0.8** across all 5 windows → ABORT, Path E feature engineering pivot deferred
- **cor vs STR_1715 > 0.7** average across windows → DEFER (high overlap, blend invalid)
- **Codex Round REJECT unanimous (3/3 stance=REJECT)** → DEFER, disposition cycle

---

## 6. Performance Reporting

Per-window output:

```python
window_id, train_start, train_end, val_start, val_end, test_start, test_end,
hp_lr, hp_dropout, hp_gamma, hp_lambda, hp_tau_min,
best_epoch, best_val_loss,
test_period_SR, test_period_CAGR, test_period_MDD, test_period_Sortino,
test_period_TO_annualized, test_period_avg_weight, test_period_n_active_avg,
test_period_alpha_mean, test_period_alpha_std,
test_cor_vs_STR_1715_pearson, test_cor_vs_STR_1715_spearman,
constraint_violation_count
```

Final cycle output:

```python
overall_test_SR, overall_test_CAGR, overall_test_MDD,
DSR_z (Deflated Sharpe Ratio Bailey-LdP),
Harvey_t_NW (Newey-West stationary bootstrap, lag=12),
5_spec_panel: CAPM_t, FF3_t, FF5_t, Carhart4_t, FF6_t,
cor_matrix_5_windows (between-window correlation),
subperiod_stability_score (per Acadian 2026 §3)
```

---

## 7. Cost Model

- **Transaction cost**: 15bps one-way (cost_model_version v2.3_kr_retail_15bps)
- **Applied to**: Σ_i |w_{i,t} - w_{i,t-1}| × 0.0015 per rebalance
- **At test time**: Net Sharpe computed = (E[r_p_net] - 0) / σ[r_p_net]
- **Sharpe annualized**: × √12 (monthly to annual)

---

## 8. Reproducibility Mandate

### 8.1. Random seed

- **Master seed**: 42 (fixed, request.json default)
- **Sub-seeds**: PyTorch torch.manual_seed(42), CUDA torch.cuda.manual_seed_all(42), numpy np.random.seed(42)
- **Gumbel softmax**: each forward pass uses Gumbel noise — seeded via `torch.use_deterministic_algorithms(True)`
- **Walk-forward**: each window seeded with `seed = 42 + window_id × 1000`

### 8.2. Versioned artifacts

- `forge_dpl_v1.py` (or `forge_dpl_v1.R-Python_bridge`)
- `forge_run_log.json` (hyperparam grid + per-trial val_loss + best params)
- `alpha_scores.parquet` (final, all windows merged)
- `ic_history.parquet` (per-sig_date IC stats)
- `bt_result.rds` (Backtest Contract v1.0 10-component, Forge cycle)
- `dpl_v1_weights.pt` (best params, per window or aggregated)

### 8.3. Hash freeze

- Final `forge_package.json` includes:
  - `features_master_parquet_sha256` (1.06 GB file)
  - `dpl_v1_weights_pt_sha256`
  - `alpha_scores_parquet_sha256`
- Hash mismatch → forge audit FAIL

---

## 9. PIT Compliance @ Training Time

### 9.1. Feature subset enforcement

```python
# Forge agent training-time enforcement
ALLOWED_FEATURES = pd.read_csv("stage_artifacts/WT_D20260517_001/feature_allowlist.csv")["feature_id"].tolist()
# 644 features (Option A) or 608 features (Option B excluding 24m/12m)
assert len(ALLOWED_FEATURES) in (644, 608)

# Disallowed feature read → assert error
for col in features_master.columns:
    if col not in ("sig_date", "Ticker", "Sector_Lv2") + tuple(ALLOWED_FEATURES):
        raise PITViolationError(f"Feature {col} not in allowlist")
```

(Note: alpha-research agent will emit `feature_allowlist.csv` as part of Step 2.6 alpha_package emission.)

### 9.2. Sig_date filter enforcement

```python
EFFECTIVE_FIRST_SIG_DATE = "2016-01-30"  # Option A (24m warm-up complete with 644 features)
# OR "2015-02-27" for Option B (12m warm-up complete with 608 features)

train_data = features_master[
    (features_master.sig_date >= EFFECTIVE_FIRST_SIG_DATE) &
    (features_master.sig_date <= train_window_end)
]
```

### 9.3. No future leakage

- Target r_{t+1} is constructed per Ticker per sig_date by looking ahead **only at training time**
- Test-time predictions w_t use features at sig_date_t only — **no future returns leak**
- Cross-section statistics (median, percentile, Z-score) computed within sig_date — no inter-sig-date pooling

### 9.4. Lookahead detector scan

Forge agent MUST run:
```bash
Rscript 02_Infrastructure/validation/lookahead_detector.R \
  --target=stage_artifacts/WT_D20260517_001/alpha_scores.parquet \
  --features=stage_artifacts/WT_D20260514_008/features_master.parquet \
  --output=stage_artifacts/WT_D20260517_001/lookahead_scan.json
```

Output `lookahead_scan.json` MUST have `violations: []` (empty array). Non-empty → HARD ABORT.

---

## 10. Expected Resources

### 10.1. GPU

- **Hardware**: RTX 4080 SUPER 16 GB CUDA
- **Per-window training**: ~30 minutes (param × FLOPS + I/O overhead, see dpl_architecture.md §2.6)
- **5 windows × 20 trials**: 100 runs × 30 min = **50 GPU hours**
- **+ 8 trials default + 12 trials grid extension** estimate

### 10.2. CPU

- **Parquet read**: 1.06 GB features_master read per training start — ~30s per window — minor
- **Preprocessing**: cross-section transforms per sig_date — ~1 sec each — minor
- **Final alpha_scores.parquet write**: ~5 MB — minor

### 10.3. Disk

- **Forge artifacts**: ~50 MB (weights × 5 windows + logs + JSON)
- **alpha_scores.parquet**: ~10 MB (148 sig_dates × ~2000 tickers × 3 cols)

### 10.4. Wall-clock total (Forge cycle)

- **Optimistic** (parallelism, GPU 80% utilization): 25 hours
- **Realistic** (single-process I/O bound, 30% utilization): 75 hours
- **Pessimistic** (debug + restart, 10% utilization): 150 hours

**Request.json estimate**: "GPU train 2-3h" — **massive underestimate**. Forge agent should plan for **24~48 hours** minimum for full cycle.

---

## 11. Forge Cycle Interface

### 11.1. Inputs to Forge

- `qepm/mailbox/worktask/WT-D20260517_001/alpha_package.json` (this WT's final emission)
- `stage_artifacts/WT_D20260514_008/features_master.parquet` (1.06 GB)
- `stage_artifacts/WT_D20260517_001/dpl_architecture.md` (spec)
- `stage_artifacts/WT_D20260517_001/pit_audit.json` (PIT compliance)
- `stage_artifacts/WT_D20260517_001/training_protocol.md` (this file)
- `stage_artifacts/WT_D20260517_001/feature_allowlist.csv` (alpha-research Step 2.6 emission)

### 11.2. Outputs from Forge to Optimizer / Judge

- `qepm/mailbox/worktask/WT-D20260517_001/forge_package.json` (Backtest Contract v1.0 8-field)
- `stage_artifacts/WT_D20260517_001/alpha_scores.parquet`
- `stage_artifacts/WT_D20260517_001/ic_history.parquet`
- `stage_artifacts/WT_D20260517_001/bt_result.rds` (10-component)
- `stage_artifacts/WT_D20260517_001/dpl_v1_weights.pt`
- `stage_artifacts/WT_D20260517_001/forge_run_log.json`
- `stage_artifacts/WT_D20260517_001/lookahead_scan.json`

---

**Submitted**: 2026-05-17 alpha-research Step 2.4 deliverable. Forge agent의 PyTorch training 의무 사양. Walk-forward 5-overlap Option B-modified 적용 의무.
