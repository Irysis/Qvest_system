# DPL_KR_v3 Training Protocol

**WT-D20260519_001 · alpha-research Step 2.4**
**Date**: 2026-05-18
**Author**: alpha-research agent (autonomous)
**Lineage**: dpl_kr_v3_architecture.md §4 + v1/v2 training_protocol inherit + v5 100-trial DSR lesson

---

## 1. Walk-Forward Cross-Validation Schema

### 1.1 5-Window Shift-12m Overlapping (v1/v2 inherit canonical)

| Window | Train | Val | Test | Test Months |
|---|---|---|---|---|
| 1 | 2016-01 ~ 2020-12 (60m) | 2021-01 ~ 2021-12 (12m) | 2022-01 ~ 2022-12 (12m) | 12 |
| 2 | 2017-01 ~ 2021-12 (60m) | 2022-01 ~ 2022-12 (12m) | 2023-01 ~ 2023-12 (12m) | 12 |
| 3 | 2018-01 ~ 2022-12 (60m) | 2023-01 ~ 2023-12 (12m) | 2024-01 ~ 2024-12 (12m) | 12 |
| 4 | 2019-01 ~ 2023-12 (60m) | 2024-01 ~ 2024-12 (12m) | 2025-01 ~ 2025-12 (12m) | 12 |
| 5 | 2020-01 ~ 2024-12 (60m) | 2025-01 ~ 2025-12 (12m) | 2026-01 ~ 2026-04 (4m) | 4 |
| **Total** | | | | **52 test months** |

### 1.2 Purged WF Embargo

- **Purged**: train/val and val/test boundaries enforce 1-month embargo (per López de Prado 2018 Ch 7)
- **Rationale**: prevent label leakage between adjacent sig_dates (monthly rebal → 1-month forward return overlap with next sig_date's features)

### 1.3 sig_date Effective Count

- Total effective sig_dates: 124 (v1 inherit canonical)
- Training: 60m × 5 windows (overlapping)
- Validation: 12m × 5 windows
- Test: 52 total test months

---

## 2. Hyperparameter Random Search

### 2.1 Grid Definition (3^3 = 27 combinations, sample 20)

| Hyperparam | Values |
|---|---|
| τ (softmax temperature) | {0.5, 1.0, 2.0} |
| λ_to (turnover penalty coefficient) | {1.0, 2.0, 4.0} |
| λ_conc (concentration penalty coefficient) | {0.5, 1.0, 2.0} |

**Total combinations**: 27 = 3 × 3 × 3.

**Random subsample**: 20 trials drawn uniformly without replacement (seed=42 for reproducibility).

### 2.2 Trial Allocation

- 20 trials per walk-forward window × 5 windows = **100 total trials**
- Used for DSR Bailey-LdP `n_trials=100` deflation (G4 gate)
- Per-window best trial selected by val Sharpe; reported test metric is best-trial test Sharpe per window

### 2.3 Trial Selection Criterion

Per window, select trial maximizing **val Sharpe** (NOT test Sharpe, to avoid validation overfitting). Test Sharpe reported per window.

Aggregated reported metric: median val-best test Sharpe across 5 windows.

---

## 3. Adam Optimizer & Schedule

### 3.1 Optimizer

```python
optimizer = torch.optim.Adam(
    model.parameters(),
    lr=0.001,
    betas=(0.9, 0.999),
    eps=1e-8,
    weight_decay=1e-5
)
```

### 3.2 Learning Rate Schedule

- Cosine annealing: lr_max=0.001 → lr_min=1e-5 over 50 epochs
- Warmup: 5 epochs linear lr=0 → 0.001

### 3.3 Early Stopping

- Patience: 10 epochs of no val Sharpe improvement
- Min epochs: 20 (avoid premature termination)
- Max epochs: 50

### 3.4 Batch Configuration

- Batch size: 1 sig_date per batch (cross-section primary mode)
- Per-batch loss aggregation across all 60 train sig_dates per window
- Gradient accumulation: optional 12-sig_date accumulation (Forge ablation flag)

### 3.5 Mixed Precision

- FP16 forward (encoder + score head)
- FP32 backward + projection (numerical stability for PAN)
- Adam state FP32 (m, v)

### 3.6 Random Seed Control

```python
torch.manual_seed(42)
np.random.seed(42)
random.seed(42)
```

Per-trial seed = 42 + trial_idx for reproducibility.

---

## 4. Loss Configuration

### 4.1 Composite Loss

```python
L_total = L_sharpe + lam_to * L_to + lam_conc * L_conc
```

### 4.2 Per-Term Implementation

```python
def loss_fn(w_t, w_tm1, r_tp1, lam_to, lam_conc, hhi_target=0.10):
    # Term 1: Sharpe surrogate
    r_p = (w_t * r_tp1).sum()
    sigma_p = max(r_p.std(), 1e-6)
    L_sharpe = -r_p.mean() / sigma_p
    
    # Term 2: Turnover (round-trip × 2)
    L_to = torch.abs(w_t - w_tm1).sum() * 0.0015 * 2
    
    # Term 3: Concentration penalty
    hhi = (w_t ** 2).sum()
    L_conc = (hhi - hhi_target) ** 2
    
    return L_sharpe + lam_to * L_to + lam_conc * L_conc
```

### 4.3 Gradient Clipping

- `torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)`
- Rationale: prevent gradient explosion in early epochs

---

## 5. Per-Epoch Audit (Forge Mandate)

### 5.1 Convergence Audit

Per epoch end (over all sig_dates in current window's train fold):

```python
# Projection convergence
violation_count = sum(1 for w in weights if w.max() > 0.20 + 1e-6 or abs(w.sum() - 1) > 1e-6)
violation_rate = violation_count / len(weights)
assert violation_rate < 0.01, f"PAN violation_rate={violation_rate} > 1%"

# HHI audit
hhi_mean = mean(hhi for w in weights)
assert hhi_mean > 0.06, f"EW collapse detected: hhi_mean={hhi_mean} <= 0.06"

# TO_annual estimate
to_per_sig = mean(|w_t - w_{t-1}|.sum() for adj pairs)
to_annual = to_per_sig * 12
assert to_annual < 6.0, f"TO violation: to_annual={to_annual} > 6.0"
```

### 5.2 Log Schema

```json
{
  "epoch": 25,
  "window": 1,
  "trial": 5,
  "tau": 1.0,
  "lam_to": 2.0,
  "lam_conc": 1.0,
  "train_loss": -0.42,
  "val_sharpe": 1.15,
  "hhi_mean": 0.082,
  "hhi_max": 0.18,
  "to_annual_estimate": 5.4,
  "violation_rate": 0.0,
  "lr": 0.0008
}
```

---

## 6. Reproducibility & Provenance

### 6.1 Hash Bindings (v4 Anti-Fabrication Inherit)

- `rawdata.parquet.sha256` = c86e4ae5c6cc3e733efe35db4aa9bf335f434f85aa90f0a6fdd086183464659c
- `feature_allowlist_v2.csv.sha256` = b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee
- `bt_result.rds.sha256` (Forge cycle emit, post-train)
- `weights.csv.sha256` (Forge cycle emit, post-train)
- `alpha_scores.parquet.sha256` (Forge cycle emit, post-train)

### 6.2 self_synthesis_used Audit

- All emitted artifacts must declare `self_synthesis_used = false`
- Codex C1 audit obligation post-Forge

### 6.3 PIT Lookahead Scan

Forge cycle obligation:
```bash
Rscript 02_Infrastructure/validation/lookahead_detector.R \
    --target=WT-D20260519_001 \
    --artifacts=stage_artifacts/WT_D20260519_001/
```

Expected: PASS_NO_LOOKAHEAD or HARD_ABORT.

---

## 7. GPU & Compute Budget

### 7.1 RTX 4080 SUPER 16 GB

- Per-batch memory: ~50 MB (17K params + activation + Adam state + gradient)
- 200+ sig_dates per batch potential (memory-bound 아님)
- Compute: 0.5 hours per trial per window estimate

### 7.2 Total Compute Budget

- 100 trials total × 0.5 h = 50 GPU-hours (single-process)
- Parallel: 4 trials concurrent × 12.5 h = ~13 GPU-hours wall-clock with 4-process parallelism

---

## 8. Output Schema

### 8.1 weights.csv (per Forge emit)

```
sig_date | Ticker | weight | trial_id | window_id | tau | lam_to | lam_conc | hhi | to
```

### 8.2 alpha_scores.parquet

```
sig_date | Ticker | alpha_score | rank | trial_id | window_id
```

### 8.3 ic_history.parquet

```
sig_date | Usable_Date | n_stocks | rank_ic | ic_std | trial_id | window_id
```

Assert: `all(Usable_Date <= sig_date)` (C14).

### 8.4 forge_package.json (8-field schema)

```json
{
  "task_id": "WT-D20260519_001",
  "agent": "forge",
  "model_id": "DPL_KR_v3",
  "SR_test_median": ...,
  "SR_test_window_array": [...],
  "MDD_test_median": ...,
  "CAGR_test_median": ...,
  "Harvey_t_5spec": {...},
  "DSR_Bailey_LdP_Z": ...,
  "cor_vs_str1715_test": ...,
  "HHI_mean_test": ...,
  "TO_annual_test": ...,
  "self_synthesis_used": false,
  "rawdata_sha256": "c86e4ae5...",
  "bt_result_sha256": "..."
}
```

### 8.5 bt_result.rds (Backtest Result Contract v1.0 10-component)

1. manifest
2. strategy_spec
3. nav
4. period_returns
5. holdings
6. benchmark_returns
7. metrics
8. benchmark_compare
9. rolling_metrics
10. drawdowns
11. audit

---

## 9. Codex Round Post-Forge

After Forge emits `forge_package_draft.json`:

```bash
bash 02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh \
    --role=forge \
    --task_id=WT-D20260519_001 \
    --package=qepm/mailbox/worktask/WT-D20260519_001/forge_package_draft.json \
    --output=qepm/mailbox/worktask/WT-D20260519_001/codex_critic_response_forge.json
```

---

## 10. Risk Mitigation Checklist (per Forge audit)

- [ ] PIT C1~C15 PASS (lookahead_detector.R)
- [ ] rawdata.parquet sha256 = c86e4ae5...
- [ ] feature_allowlist_v2.csv sha256 = b3d667...
- [ ] self_synthesis_used = false declared
- [ ] HHI > 0.06 majority sig_dates (G7)
- [ ] TO annual < 6.0 (Hard constraint)
- [ ] max(weights) ≤ 0.20 + 1e-6 all sig_dates
- [ ] min(weights) ≥ 0 all sig_dates
- [ ] abs(sum(weights) - 1.0) < 1e-6 all sig_dates
- [ ] count(weight > 0) ≤ 20 all sig_dates
- [ ] LIQ_20d ≥ 2e8 all (sig_date, Ticker) in alpha_scores.parquet (Codex C4 v1 fix)
- [ ] 52 test months total
- [ ] 100 trial DSR Bailey-LdP n_trials reported
- [ ] Harvey-t 5-spec genuine count reported (FF5/FF6 may be structural duplicate if no RMW/CMA data, per v5 lesson)
- [ ] bt_result.rds SHA256 hash binding
- [ ] alpha_scores.parquet schema valid (Date × Ticker × score)

---

## 11. AX-008 Triangulation

| Source | Status | Obligation |
|---|---|---|
| **Forge** | Pending Forge cycle | Run training + emit weights.csv + alpha_scores.parquet + bt_result.rds + forge_package.json. Pass G0~G7 gates. |
| **Codex** | Pending Codex round on Forge package | Critic Round on forge_package_draft.json. Stance ∈ {APPROVE, APPROVE_CONDITIONAL, REVISE, REJECT}. |
| **Architect** | Pending Architect audit | Independent reproduction of test SR + per-window stability + Harvey-t + DSR. Concurrent with Forge or post. |

**G6 admission**: ≥ 2/3 PASS required.

---

**End of Training Protocol v3**

Lineage: dpl_kr_v3_architecture.md §4 + training_protocol.md v1 inherit + training_protocol_v2.md v2 inherit + v4 anti-fabrication audit + v5 DSR n_trials=100 lesson.
