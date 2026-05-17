# Purged Walk-Forward Validation Protocol

**WT-D20260517_002 · alpha-research Step 2.2c**
**Date**: 2026-05-17
**Author**: alpha-research agent
**Reference**: López de Prado (2018) "Advances in Financial Machine Learning" Chapter 7

**도훈 mandate B.6**: Random k-fold CV 절대 금지. Purged walk-forward validation 의무.

---

## 1. Why Random K-Fold CV Fails for Financial Data

### 1.1. Classical assumption violation

Random k-fold CV는 i.i.d. data 가정. 주식 return은:
- **Time-series serial correlation**: r_t ↔ r_{t+1} (autocorrelation, weak but present)
- **Cross-section overlap**: same stock 학습/검증/테스트 모두 등장
- **Label leakage**: target (next-month return) 학습 set에 포함

→ k-fold CV 결과는 **systematic over-fitting** (in-sample SR 1.5+ but OOS SR < 0).

### 1.2. L-323 / L-325 / L-326 학습

- L-323: Path A baseline 60m subsample SR 2.267 sample-biased
- L-325: WT_013 ABORT sample bias misdiagnosed
- L-326: STR_1715 84m SR 2.0054 ≈ canon 255m 1.9536 (baseline robust, sample 부족 문제 없음)

이 모든 사례에서 **walk-forward + sample 충분성**이 결정적. Random k-fold는 KR 124 sig_dates × 1500-2000 stocks 환경에서 가장 큰 위협.

---

## 2. Purged Walk-Forward Validation (López de Prado 2018 Ch 7.4)

### 2.1. Core idea

Classical walk-forward = train [t_0, t_1] → val [t_1, t_1+v] → test [t_1+v, t_1+v+w].

**Problem**: Sample at t_i depends on features that overlap with sample at t_j when |t_j - t_i| < label horizon. Features at t_i가 t_i+1까지 forward look (1-month forward return target) → t_j ∈ [t_i, t_i+1]에서 학습된 정보는 t_i+1 prediction에 직접 영향 → leakage.

**Purge**: Remove train samples that overlap with val/test horizon.

**Embargo**: Remove additional samples right after train/val/test boundary to handle label-feature smoothing.

### 2.2. Protocol for DPL_KR_v2

Walk-forward 5 windows × 60m train + 12m val + 12m test (v1 inherit):

```
W1: Train 2016-01 ~ 2020-12 (60m) | Val 2021-01 ~ 2021-12 (12m) | Test 2022-01 ~ 2022-12 (12m)
W2: Train 2017-01 ~ 2021-12       | Val 2022-01 ~ 2022-12       | Test 2023-01 ~ 2023-12
W3: Train 2018-01 ~ 2022-12       | Val 2023-01 ~ 2023-12       | Test 2024-01 ~ 2024-12
W4: Train 2019-01 ~ 2023-12       | Val 2024-01 ~ 2024-12       | Test 2025-01 ~ 2025-12
W5: Train 2020-01 ~ 2024-12       | Val 2025-01 ~ 2025-12       | Test 2026-01 ~ 2026-04 (4m partial)
```

**Purge logic**:
- Label horizon = 1 month (target = next-month return)
- Train end at 2020-12 → target 2021-01 → purge train samples at 2020-12 (1-month look-forward overlap)
- **Effective train end**: 2020-11 (drop last 1 month of train per window)

**Embargo logic**:
- Embargo = 1 month buffer after train end before val start
- Train 2020-01 ~ 2020-11 → embargo 2020-12 (no use) → val 2021-01 ~ 2021-12
- Similarly val end 2021-12 → embargo 2022-01 (already test start, so embargo absorbed into test handling, no additional)

### 2.3. Purged WF with Embargo Schedule

```
W1: 
  Train: 2016-01 ~ 2020-11 (59m, last month purged)
  Embargo: 2020-12 (skip)
  Val:   2021-01 ~ 2021-11 (11m, last month purged for cross-val to test)
  Embargo: 2021-12 (skip)
  Test:  2022-01 ~ 2022-12 (12m)

W2: shift 12m
  Train: 2017-01 ~ 2021-11 (59m)
  Embargo: 2021-12
  Val: 2022-01 ~ 2022-11
  Embargo: 2022-12
  Test: 2023-01 ~ 2023-12

... (W3, W4, W5 same shift pattern)

W5 (partial test):
  Train: 2020-01 ~ 2024-11 (59m)
  Embargo: 2024-12
  Val: 2025-01 ~ 2025-11
  Embargo: 2025-12
  Test: 2026-01 ~ 2026-04 (4m partial)
```

**Net test months**: 12 + 12 + 12 + 12 + 4 = 52 months (overlapping)

### 2.4. Cross-section purge

KR equity universe에서 stock-level purge 추가:
- Stock i의 training 마지막 observation = sig_date 2020-11
- Stock i의 val/test observation = sig_date 2021-01 이후
- 1 month embargo는 cross-section에도 자동 적용

**Special case**: 신규 IPO stocks. IPO date > train_end - 12m → val/test 진입 시 학습 부족. Mitigation: minimum data history requirement 12 months 이전 IPO만 universe inclusion.

---

## 3. Combinatorial Purged Cross-Validation (CPCV) - Optional Extension

López de Prado (2018) Ch 12 CPCV는 더 strict한 OOS test (k-fold variant with purge + embargo). v2 baseline은 purged WF (above), CPCV는 alternative if Codex Round 권고.

### 3.1. CPCV Spec (Reference)

- Divide time-series into N_groups groups (e.g., 13 quarters × 1-year offset)
- Generate k-fold splits via combinatorial sampling
- Apply purge + embargo to each fold
- Average performance across folds

**Caveat**: CPCV 12 sig_dates per group × 5 groups = 60m, KR 124 sig_dates → 12 quarter groups manageable. 단 computational cost 5-10× walk-forward.

**v2 decision**: purged WF baseline retain, CPCV는 final admission cycle에서 robustness check로만 사용.

---

## 4. Hyperparameter Search Protocol (v2 정합)

### 4.1. Per-window hyperparam search

For each walk-forward window:
1. **Train** model on purged training set
2. **Validate** on val set → compute val_IR_net
3. **Random search**: 20 hyperparam configs sampled (lr / dropout / κ_evar / λ_to / τ / α) per window
4. **Select best** config by val_IR_net
5. **Predict** on test set using best config

### 4.2. Aggregate metrics

After 5 windows:
- Concatenate test predictions: 12 + 12 + 12 + 12 + 4 = 52 months
- Compute aggregate metrics: SR / CAGR / MDD / etc.

### 4.3. DSR Bailey-LdP n_trials

- 20 random search × 5 windows = **100 trials**
- DSR n_trials = 100 (Codex C3 학습 from v1)
- Deflation factor for SR: `SR_deflated = SR_obs · (1 - α · sqrt(2 ln(100)/n_obs))` (Bailey-LdP 2014 formula)

---

## 5. Tracking / Audit Mandates

### 5.1. Per-window logging

Forge cycle 의무 (build_forge_package_draft.py v2 신규):
```python
forge_run_log_v2.json = {
  "window_id": w,
  "train_period": (start, end_purged, embargo, val_start),
  "val_period": (val_start, val_end_purged, embargo, test_start),
  "test_period": (test_start, test_end),
  "hyperparam_trials": [{config, val_IR_net, ...} for trial in 20],
  "best_config": {...},
  "test_metrics": {SR, CAGR, MDD, IR, TE, TO, ADVUsage, FactorAdjustedAlpha, SectorActiveRisk, HitRatio, RollingIR12m, RollingDD12m},
  "constraint_violations": [...]
}
```

### 5.2. Leakage scan

Per window, **automated leakage check**:
- Feature value at sig_date t with Usable_Date > t → FLAG (PIT C1 violation)
- Target return at t depends on action at t' ≥ t → FLAG (forward look)
- Train embedding contains test stocks at test sig_dates → FLAG (cross-section leakage)

Lookahead detector `lookahead_detector.R` 의무 호출 (PIT C1 strict).

---

## 6. Compared with v1 Protocol

| Aspect | v1 protocol | v2 protocol |
|---|---|---|
| Walk-forward windows | 5 overlapping shift-12m | 5 overlapping shift-12m (retain) |
| Train window | 60m | 59m (1m purge) |
| Val window | 12m | 11m (1m purge for embargo) |
| Test window | 12m (W5: 4m) | 12m (W5: 4m) (retain) |
| Embargo | implicit (1m gap) | explicit 1m embargo + 1m purge |
| Random k-fold CV | NOT USED | NOT USED |
| Hyperparam trials | 100 (20×5) | 100 (20×5) (retain) |
| DSR n_trials | 100 | 100 (retain) |
| Lookahead scan | lookahead_scan.json | lookahead_scan_v2.json |
| Cross-section purge | none | explicit (IPO < train_end - 12m) |

**Net effect**: v2 is **stricter** by 2 months per window (purge + embargo) → slightly less training data, but **OOS validity 강화**.

---

## 7. Codex Round Audit Points

1. **Embargo length 1m sufficient?** L-323 학습: KR monthly rebalance, label horizon = 1m → 1m embargo 정합. Codex 권고 시 2m로 conservative.
2. **W5 partial test 4m**: 학습 sample 적음. Codex 권고: W5 결과는 secondary, primary W1-W4 16+ months 우선 평가.
3. **Cross-section purge IPO threshold**: 12 months 이전 IPO. Stocks with < 12m history excluded from training. Forge cycle data load 시 enforce.
4. **CPCV deferred**: v2 primary = purged WF. CPCV는 Codex 권고 시 robustness check.

---

## 8. Mandate Compliance Cross-Reference

| 도훈 mandate | 본 protocol 정합 |
|---|---|
| B.4 PIT strict | ✓ purge + embargo + cross-section purge |
| B.5 survivorship + look-ahead + restatement bias 제거 | ✓ delisted stocks retained until delisting date / no forward look / restatement = use first reported (annual May lag) |
| B.6 random k-fold 금지, purged WF 의무 | ✓ purged WF + 1m embargo + 1m purge |
| B.7 gross + net 분리 | ✓ Forge cycle 의무 |

---

**Submitted**: 2026-05-17 alpha-research Step 2.2c. Purged walk-forward protocol with embargo + cross-section purge + DSR n_trials=100. 도훈 mandate B.4~B.7 모두 정합.
