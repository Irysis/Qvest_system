# Training Protocol v2 — DPL_KR_v2 + 8 Comparison Models

**WT-D20260517_002 · alpha-research Step 2.5**
**Date**: 2026-05-17
**Author**: alpha-research agent
**Reference**: dpl_kr_v2_architecture.md + champion_challenger_comparison_framework.md + purged_walk_forward_protocol.md

---

## 1. Training Data

| Parameter | Value | Source |
|---|---|---|
| Features | 80 (family-balanced) | feature_allowlist_v2.csv sha256 f1778f67... |
| Sig_dates | 124 (2016-01 ~ 2026-04, 24m warm-up post 2014-01) | features_master.parquet inherit |
| Stocks | KR_TOP500_LIQ1E8 (2e8 KRW 20d ADV) | request.json mandate |
| Target | r_{t+1} = next-month total return (KOSPI200 cum + dividend reinvest) | RAWDATA + dividend split adj |
| Benchmark | KOSPI200 cap-weight (rebalanced quarterly per index methodology) | KRX KOSPI200 index daily file |

**Effective panel size**: 124 sig_dates × ~1500-2000 stocks/sig_date × 80 features ≈ **15-20M training observations**.

---

## 2. Walk-Forward Splits (Purged + Embargo)

```
W1: Train 2016-01 ~ 2020-11 (59m, 1m purge)
    Embargo: 2020-12
    Val:   2021-01 ~ 2021-11 (11m, 1m purge)
    Embargo: 2021-12
    Test:  2022-01 ~ 2022-12 (12m)

W2: shift +12m
    Train 2017-01 ~ 2021-11
    Val 2022-01 ~ 2022-11
    Test 2023-01 ~ 2023-12

W3: Train 2018-01 ~ 2022-11, Val 2023-01 ~ 2023-11, Test 2024-01 ~ 2024-12
W4: Train 2019-01 ~ 2023-11, Val 2024-01 ~ 2024-11, Test 2025-01 ~ 2025-12
W5: Train 2020-01 ~ 2024-11, Val 2025-01 ~ 2025-11, Test 2026-01 ~ 2026-04 (4m partial)
```

**Net test months**: 12 + 12 + 12 + 12 + 4 = **52 months**

---

## 3. Hyperparameter Search (Random Search)

### 3.1. Search space (DPL_KR_v2 / Model 6)

| Hyperparam | Range | Default | Sample dist |
|---|---|---|---|
| lr | [1e-5, 1e-3] | 1e-4 | log-uniform |
| dropout | [0.1, 0.4] | 0.2 | uniform |
| κ_evar (EVaR weight) | [0.05, 1.0] | 0.3 | log-uniform |
| λ_to (TO penalty weight) | [0.1, 2.0] | 0.5 | log-uniform |
| τ_softmin (EVaR concentration) | [0.05, 0.3] | 0.1 | log-uniform |
| α_partial (portfolio adjustment) | [0.4, 0.9] | 0.6 | uniform |
| τ_size (sizing softmax) | [0.5, 2.0] | 1.0 | log-uniform |
| set_module_dim | {16, 32, 64} | 32 | discrete |
| seq_hidden | {16, 32, 64} | 32 | discrete |
| weight_decay (L2) | [1e-5, 1e-3] | 1e-4 | log-uniform |

**Random search**: 20 configs per window × 5 windows = **100 trials**

### 3.2. Selection Criterion

For each window:
- Train with 20 random configs
- Evaluate on val set: compute `val_score = 0.5 · IR_net + 0.3 · (1 - max(MDD, 0.25)/0.25) + 0.2 · (1 - max(TO, 6)/6)`
- Select config with max `val_score`
- Predict on test set using best config

### 3.3. DSR Bailey-LdP n_trials

```
DSR_Z = (SR_obs - SR_null) / SE(SR_obs) - sqrt(2 · ln(n_trials) / n_obs) · sd_skew_kurt_adj
n_trials = 100 (DSR escalated, Codex C3 학습 from v1)
```

Bailey-LdP (2014) formula with `n_trials = 100` deflation.

---

## 4. 8-Model Comparison Schedule (도훈 mandate G)

본 cycle = design only. **Forge cycle 의무 (Q-Lead confirm 후)**:

| Model | Type | Implementation | Est. GPU time |
|---|---|---|---|
| 1 Linear Factor Composite | Champion | factor_engine + factor weights cross-val | 15m |
| 2 ElasticNet + MVO | Champion | sklearn ElasticNet + cvxpy MVO | 30m |
| 3 GBM + MVO | Champion | LightGBM + cvxpy MVO | 1h |
| 4 Linear PPP (Brandt) | Challenger | gradient descent closed-form | 20m |
| 5 GBM Direct Active | Challenger | LightGBM with surrogate target | 1h |
| 6 Neural Direct Active (DPL_KR_v2) | Challenger | **PyTorch Set-Sequence 본 spec** | 3h GPU × 5 windows × 20 trials = 75h... |
| 7 Differentiable Opt Layer | Challenger | CvxpyLayer + NN backbone | 2h |
| 8 Cost-aware DPL (4-term obj) | Challenger | Model 6 + objective E | 75h |

**Total GPU time estimate**: ~80h on RTX 4080 SUPER. **Forge cycle**: 분할 implementation 권고.

**Practical reduction**:
- 20 random trials × 5 windows for Model 6 + 8 only (core challenger)
- Models 1-5 + 7: 5 windows × default hyperparams (no grid search) — faster baseline
- Models 6 + 8: 20 × 5 = 100 trials each (DSR strict)

Revised total: ~40-50h.

---

## 5. Sub-sampling per Sig_date (DSPO §3.5 inherit)

For each training sig_date t:
- Compute target r_{t+1} for all stocks in universe
- Rank stocks by r_{t+1} (descending)
- **Sub-sample 200 stocks**: top 100 + bottom 100
- Train on sub-sample (200 stocks × 80 features per sig_date)
- Test inference uses **full universe** (no sub-sampling)

**Rationale (DSPO 2024)**:
- Reduces overfitting / training instability (limited cross-section sample)
- Increases effective sample diversity per epoch
- Long-only KR retain: top + bottom for ranking signal (Plackett-Luce listwise learns ordering, bottom needed for "what NOT to buy")

---

## 6. Computational Budget

| Resource | Limit | Usage estimate |
|---|---|---|
| GPU | RTX 4080 SUPER 16GB VRAM | ~10GB per training run (batch 12m × 200 sub-sample × 80 features) |
| RAM | 64GB | ~20GB peak (data loading + model + grad) |
| Disk | ~10GB | trained weights + predictions + logs per cycle |
| Wall time per trial | ~30-45m | depends on early stop |
| Wall time total | ~40-50h | with parallel limited by GPU |

---

## 7. Output Artifacts (Forge Cycle Mandate)

### 7.1. Per model
- `model_weights_{i}.pt` (PyTorch trained weights) OR `model_{i}.pkl` (sklearn)
- `predictions_{i}_test.parquet` (predicted scores OR active weights, 52m × ~1500-2000 stocks)
- `weights_{i}_test.csv` (final w_t, 52m × universe)
- `metrics_{i}.json` (12 metric values)
- `forge_run_log_{i}.json` (per-window training log)

### 7.2. Aggregate
- `champion_vs_challenger_comparison.json` (8 models × 12 metrics matrix)
- `rejection_criteria_check_{i}.json` (6 rejection per model)
- `pareto_dominance.json` (DPL vs Champion BEST comparison)
- `final_admit_recommendation.json` (substitution / 4th orthogonal / reject)

---

## 8. Codex Round Audit Points

1. **Sub-sampling per sig_date 200 = top/bottom 100**: KR universe 1500-2000 stocks → 200 sub-sample = ~10-13% — DSPO 2024 China A-share에서는 4000 stocks → 200 sub-sample = 5%. KR ratio higher, sample diversity 더 충분.
2. **20 random trials per window**: total 100 trials for DSR. Codex 권고 시 50 trials per window (250 total) more conservative.
3. **40-50h GPU time**: 도훈 confirm 후 Forge cycle 진행. Reasonable for RTX 4080 SUPER.
4. **8 모델 동시 vs sequential**: 의존성 없음 → parallel 가능. 단 GPU shared, sequential safer.
5. **purged 1m + embargo 1m**: 2m boundary per train/val/test. Codex 권고 시 strict 2m purge + 2m embargo (4m total) → 학습 sample 추가 -8m / window.

---

## 9. Forge Cycle Entry Mandate (Q-Lead confirm 후)

본 alpha-research cycle = design only. Forge cycle 진입 의무:

1. **도훈 confirm**: code 작성 진행 OK (mandate B.2)
2. **Code 작성 위치**: `02_Infrastructure/ml_pipeline/forge_dpl_v2/` (신규 dir, v1 retain)
3. **신규 Python scripts**:
   - `forge_dpl_v2_main.py` (main training driver)
   - `model_set_sequence.py` (Set-Sequence + GAT + Score Head)
   - `loss_3term_composite.py` (ListMLE + EVaR SoftMin + TO hinge)
   - `constraint_enforcer.py` (Dykstra + TE shrinkage + sector rebalance + ADV scale)
   - `purged_walk_forward.py` (purged WF + embargo + sub-sample)
   - `champion_models.py` (Models 1-5 implementation)
   - `differentiable_opt_layer.py` (Model 7 CvxpyLayer)
4. **Codex Round 5단계** (forge stage)
5. **Audit obligations**: AX-008 verification triangulation (Forge + Codex + Architect) ≥ 2/3 PASS

---

## 10. Failure Cutoff (재확인)

- DPL_v2 SR < 1.0 (52m subset) → ABORT
- EW collapse detected (HHI ≈ 0.05 majority sig_dates) → HARD ABORT
- TO > 8.0 / yr after mitigation → ABORT
- MDD > 30% → ABORT
- Constraint violation rate > 5% → ABORT
- Any 6 rejection criteria triggered → ABORT or DEFER
- Codex unanimous REJECT → DEFER

---

**Submitted**: 2026-05-17 alpha-research Step 2.5 training protocol v2. Purged WF + 80 features + 100 trials DSR + 8-model comparison + 12-metric evaluation + 6-rejection criteria 모두 정합. Q-Lead confirm 후 Forge cycle 진입 ready.
