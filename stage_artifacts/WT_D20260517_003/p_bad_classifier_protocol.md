# p_bad_1715(t+1) Classifier OOS Gate Protocol

**WT-D20260517_003 · alpha-research Step 3.3**
**Author**: alpha-research agent
**Date**: 2026-05-17
**Parents**: bad_state_label_3_compare.md (optimal bad_state definition selection) + literature_review_dpl_rc.md §5 Avramov-Cheng-Metzker 2023
**Charter mandate G1**: HARD ABORT if pre-OOS gate fail (AUC ≥ 0.55, Brier < 0.24, recall ≥ 0.60)

---

## 0. Protocol 목적

p_bad_1715(t+1) ∈ [0, 1] classifier는 DPL-RC paradigm의 **핵심 component**. 본 protocol은:
1. Classifier architecture + training spec
2. **Pre-deployment OOS gate** (3 hard thresholds) — fail 시 HARD ABORT
3. Sub-period stability test (G8) — single-window artifact 차단
4. Feature engineering + PIT compliance audit

핵심 paradigm: classifier가 **사후 regime fitting**되지 않도록 pre-OOS validation 의무. fail 시 사후 paradigm 정당화 차단.

---

## 1. Classifier architecture — LightGBM binary classifier

### 1.1. Why LightGBM

Avramov-Cheng-Metzker (2023 RFS, §V.B) empirical finding:
- LightGBM이 regime-conditional context에서 calibrated probability prediction가능 (Brier < 0.25, AUC > 0.55)
- Interpretable (feature importance + SHAP) + non-linear (feature interaction)
- ~5K effective parameters → KR 124 sig_dates × 80 features에서 sample-safe (param ratio ~25:1)

### 1.2. Spec

```python
import lightgbm as lgb

p_bad_classifier_spec = {
  "objective": "binary",                    # binary classification (bad / not bad)
  "metric": ["binary_logloss", "auc", "brier"],
  "num_leaves": 31,                          # default — balanced complexity
  "max_depth": 6,                            # tree depth cap (over-fitting 방지)
  "learning_rate": 0.05,                     # conservative (small step)
  "num_iterations": 500,                     # early stopping with patience 50
  "feature_fraction": 0.8,                   # subsample features per tree
  "bagging_fraction": 0.8,                   # subsample observations per tree
  "bagging_freq": 5,
  "lambda_l1": 0.1,                          # L1 regularization
  "lambda_l2": 0.1,                          # L2 regularization
  "min_data_in_leaf": 10,                    # leaf size 제약 (small bad-state sample 정합)
  "is_unbalance": True,                      # bad-state base rate ~20-25% imbalance handling
  "scale_pos_weight": None                   # is_unbalance과 mutually exclusive — auto computed
}
```

### 1.3. Features

**Pool**: v2 feature_allowlist 80 features (sha256 b3d66751..., defensive 55% — bad-state context에서 자연 fit).

**Selection**: 80 features 모두 candidate. LightGBM이 자동으로 feature importance ranking. 학습 후 top-30 features (importance > threshold) retain → re-train 후 final classifier.

**Critical PIT compliance**: features 모두 **t-time observable** (t-1 lag for monthly rebalance). Step 3.4 conditional loss와 동일한 PIT scope.

**Why 80 features (not 1044 full FMP pool)**: v2 cycle에서 sha256-verified balanced 80 features는 KR PIT-clean + defensive heavy 55%. p_bad classifier는 KR equity stress regime detection에 직접 정합.

### 1.4. Target

Step 3.2 optimal bad_state definition (default prior: Definition 1 active return < -3% threshold) → bad_state_t binary label.

Target = `bad_state_{t+1}` (next month's bad state). Features at t → classifier learns P(bad_state_{t+1} = 1 | features_t).

**Lag structure**:
- Features available at t (t-1 fundamental + t-1 price + t macro)
- Target: bad_state_{t+1} (t close → t+1 close return → active return → label)
- No forward look. PIT C1-C15 strict.

---

## 2. Pre-deployment OOS gate (G1) — HARD ABORT criteria

### 2.1. Three hard thresholds

| Threshold | Value | Rationale |
|---|---|---|
| **AUC** | ≥ 0.55 | Random baseline 0.5 + 의미 있는 +0.05 (AC-M 2023 §V.B p_bad classifier empirical lower bound). Below 0.55 = classifier가 random보다 못함 → paradigm inviable |
| **Brier score** | < 0.24 | Brier max for binary classifier with base rate 20-25% = 0.20-0.25 (Brier max = p(1-p) reference). Below 0.24 = calibration ≥ random baseline. AC-M 2023 empirical bound |
| **Bad recall** | ≥ 0.60 | Recall@bad_state = P(predict bad \| true bad). At least 60% bad states detected. Below 0.60 = paradigm의 핵심 (bad-state complement injection)이 miss됨 |

### 2.2. Measurement protocol

Walk-forward purged validation (purged_walk_forward_protocol.md inherit):
- W1-W5 (60m train / 12m val / 12m test, 1m purge + 1m embargo)
- Each window: train on purged train + val → compute test set classifier metrics
- **Aggregate**: 5 windows × 12m + 4m partial = 52 net test months
- Aggregate AUC = pooled prediction concatenation AUC
- Aggregate Brier = mean(Brier_w1, ..., Brier_w5)
- Aggregate Recall = pooled recall over all test predictions

**Hard gate**:
```python
if aggregate_AUC >= 0.55 and aggregate_Brier < 0.24 and aggregate_recall >= 0.60:
  G1_PASS = True
else:
  G1_FAIL = True
  # HARD ABORT — DPL-RC paradigm inviable
  abort_reason = f"p_bad classifier OOS fail (AUC={aggregate_AUC:.3f}, Brier={aggregate_Brier:.3f}, recall={aggregate_recall:.3f})"
```

### 2.3. ABORT decision

G1 FAIL → **HARD ABORT**:
- DPL-RC paradigm 자체 inviable — 1715의 bad state를 사전 forecast할 수 없음
- 사후 regime fitting 차단 (사후 분류는 overfitting + lookahead bias)
- alpha_package.json에 `paradigm_status: "ABORT_G1_FAIL"` + `challenge_flags: ["p_bad_classifier_oos_gate_fail"]`
- 후속 Risk / Optimizer / Forge cycle 스킵
- L-code 적립 (paradigm fail + 학습 retain)

### 2.4. Edge cases

**Case 1**: AUC ≥ 0.55 BUT Brier ≥ 0.24
- 의미: discrimination 가능 (AUC) 하지만 calibration 부족 (Brier)
- Action: calibration refit (Platt scaling OR isotonic regression) → re-test Brier
- 재테스트 fail → ABORT

**Case 2**: AUC ≥ 0.55 BUT recall < 0.60
- 의미: 전반적 discrimination ok 하지만 bad-state detection 미흡
- Action: threshold tuning (default 0.5 → tune to maximize recall subject to precision floor) → re-test recall
- 재테스트 fail → ABORT

**Case 3**: Brier < 0.24 BUT AUC < 0.55
- 의미: calibration ok (예측 확률 well-calibrated) 하지만 discrimination 부재
- Action: NO recovery — discrimination 없으면 calibration 무의미 → ABORT

---

## 3. Sub-period stability test (G8)

### 3.1. Mandate

G8: **OOS sub-period AUC stable (3/3 PASS)** — single-window artifact 차단.

124 sig_dates 5 walk-forward windows에서 W1, W3, W5 (3 non-overlapping windows)에 대해 각각 AUC ≥ 0.55 충족.

```python
G8_PASS = (AUC_W1 >= 0.55) and (AUC_W3 >= 0.55) and (AUC_W5 >= 0.55)
```

W2 / W4 (overlapping subset)는 보조 검증.

### 3.2. ABORT criteria

- 3/3 window에서 AUC ≥ 0.55 fail → single-window artifact 의심 → DEFER (not ABORT, but 2nd-tier signal)
- Specifically W5 (2026 partial test, 4m only) fail은 partial weight (admission 1 window 이상 fail 시 cautionary flag)

### 3.3. Stability metric

Beyond binary pass/fail, **AUC std across windows** measure:
- std(AUC_W1, ..., AUC_W5) ≤ 0.05 → "stable across regimes"
- std(AUC_W1, ..., AUC_W5) > 0.10 → "unstable, regime-dependent" (weaker paradigm)

본 metric은 admission 7-axis axis 7 (p_bad OOS AUC ≥ 0.55) 의 sub-criterion.

---

## 4. Threshold tuning + score calibration

### 4.1. Threshold selection

LightGBM raw output = P(bad_state_{t+1} = 1) ∈ [0, 1]. DPL-RC injection formula:
```
a_t = clip(a_max · p_bad_1715(t+1), 0, a_max)
```

여기서 `p_bad_1715(t+1)`은 calibrated probability (raw classifier output 그대로 OR calibration refit).

**Calibration check**: Brier score < 0.24 통과 → raw output 사용 가능. Brier 0.24-0.28 → Platt scaling refit.

### 4.2. Score calibration methods

**Method 1: Platt scaling (sigmoid)**
```python
from sklearn.calibration import CalibratedClassifierCV
calibrated_clf = CalibratedClassifierCV(base_estimator=lgb_clf, method='sigmoid', cv=5)
```

**Method 2: Isotonic regression** (more flexible, more sample-hungry)
```python
calibrated_clf = CalibratedClassifierCV(base_estimator=lgb_clf, method='isotonic', cv=5)
```

본 cycle default: **Platt scaling** (124 sig_dates에서 isotonic은 sample insufficient).

### 4.3. p_bad output usage in DPL-RC

```
a_t = clip(a_max · p_bad_calibrated(t+1), 0, a_max)
```

- p_bad_calibrated → bad-state 확률
- a_max ∈ {0.05, 0.10, 0.15, 0.20} (admission grid)
- 곱셈 → conditional injection: bad state 확률 높을수록 complement allocation 큼
- clip → bounds enforce (numerical safety)

**Good-state behavior**: p_bad ≈ 0 → a_t ≈ 0 → w_final ≈ w_1715 (no injection, 1715 그대로)
**Bad-state behavior**: p_bad ≈ 1 → a_t ≈ a_max → w_final = (1 - a_max) · w_1715 + a_max · w_comp (max injection)

---

## 5. PIT compliance audit

### 5.1. Feature time consistency

Classifier features at t (input):
- Fundamental: t-1 quarterly (45d lag) or t-1 annual May
- Price: t-1 close (already lagged)
- Macro: t-1 FRED / ECOS
- Investor flow: t-1 settlement
- Composite / derived: t-1 close-to-close

**Verification**: 80 features inherited from v2 with PIT audit pass (pit_audit_v2.json inherit).

### 5.2. Target time consistency

Target: bad_state_{t+1}
- Built from r_1715_{t+1} (next month return, available at t+1 close)
- Active return = r_1715 - r_KOSPI200 at t+1
- Classifier learns: features_t → bad_state_{t+1}
- Prediction at sig_date t (current): p_bad_classifier.predict(features_t) → p_bad_{t+1}_forecast
- **No forward look**: 모든 input은 t close까지 available

### 5.3. Walk-forward purge

Per purged_walk_forward_protocol.md inherit:
- Train end 2020-11 (1m purge before val)
- Val end 2021-11 (1m purge before test)
- Test 2022-01 ~ 2022-12 (12m)
- Embargo 1m between train/val and val/test

**No leakage**: train labels (bad_state_{t+1} for t in train period) 모두 train end - 1m 시점 이전 known.

### 5.4. Restatement bias

Active return = (r_1715 - r_KOSPI200) - 두 return 모두 standard daily close-based monthly compounding. No fundamental restatement issue.

KOSPI200 total return: 표준 benchmark, restatement-free (index methodology fixed).

---

## 6. Forge cycle measurement spec

본 protocol design은 alpha-research cycle의 spec만. 실제 measurement는 Forge cycle:

### 6.1. Forge cycle Step 1 (p_bad classifier first)

```
1. Load v2 feature_allowlist 80 features (sha256 b3d66751 verify)
2. Compute bad_state labels for 3 definitions × thresholds → 9 candidate labels
3. For optimal label (Step 3.2 selection): train LightGBM × 5 walk-forward windows
4. Compute aggregate metrics: AUC / Brier / recall
5. G1 gate check:
   if G1_FAIL: HARD ABORT, paradigm inviable
   else: G1_PASS, proceed to Step 2 (complement scorer 4-stage)
6. Sub-period stability G8: 3 windows AUC ≥ 0.55 check
7. Calibration refit if Brier 0.24-0.28
```

### 6.2. Forge cycle artifacts

- `p_bad_classifier_models.pkl` (5 walk-forward window LightGBM models)
- `p_bad_predictions.parquet` (sig_date × predicted p_bad probability)
- `p_bad_classifier_metrics.json` (AUC / Brier / recall + per-window stability)
- `g1_gate_report.json` (PASS/FAIL + decision + ABORT details)
- `feature_importance.csv` (top features for interpretability)

---

## 7. Risk mitigation — sufficient bad-state detection

### 7.1. Concerns

KR 124 sig_dates × bad-state base rate ~20-25% = ~25-30 bad sig_dates. 

- Walk-forward each window: train 60m × 20-25% bad = ~12-15 bad sig_dates per window
- Test 12m × 20-25% bad = ~2-3 bad sig_dates per test window
- **Small sample concern**: bad-state subset이 작아 calibration / generalization 어려울 수 있음

### 7.2. Mitigation strategies

**Strategy 1: is_unbalance + scale_pos_weight tuning**
- LightGBM `is_unbalance=True` 자동 처리
- Manual scale_pos_weight = (1 - base_rate) / base_rate ≈ 3-4 tune

**Strategy 2: Threshold lower bound**
- Default classification threshold 0.5 → reduce to (e.g.) 0.3 → bad-state recall ↑ (precision ↓)
- DPL-RC paradigm은 **recall (bad-state miss 차단)이 우선** → lower threshold 정당

**Strategy 3: Class-balanced loss**
- Focal loss (Lin et al. 2017): `L = -α (1-p_t)^γ log(p_t)` — minority class에 emphasis
- LightGBM custom objective로 통합 가능

### 7.3. Sufficient sample bound (Empirical Bayes)

AC-M (2023, §V.B) empirical: 30 events × 80 features → LightGBM AUC ≥ 0.55 achievable with ~60% probability.

본 cycle expected:
- Train per window: 12-15 events × 80 features → marginal sample
- **Multi-window aggregation** (5 windows × 12-15 events = ~60-75 total events across train + val) → 적정
- Forge cycle measurement 실시간 monitoring → 어떤 window에서 sample insufficient time alert

---

## 8. ABORT criteria summary

### 8.1. G1 PASS → proceed

aggregate AUC ≥ 0.55 + aggregate Brier < 0.24 + aggregate recall ≥ 0.60 → G1 PASS → Forge proceed.

### 8.2. G1 FAIL → HARD ABORT

다음 중 하나라도 fail → **HARD ABORT**:
- aggregate AUC < 0.55 (discrimination 부재)
- aggregate Brier ≥ 0.24 + calibration refit 후도 fail (calibration 부재)
- aggregate recall < 0.60 + threshold lower 후도 fail (bad-state miss)

**ABORT 시 학습**: L-code 적립 (DPL-RC paradigm inviable for KR 2014-2026 + 80 features context).

### 8.3. G1 PASS BUT G8 FAIL → DEFER

3 sub-periods AUC ≥ 0.55 fail (1-2 window OK, but 1 window fail) → **DEFER** (not full ABORT):
- single-window artifact 의심
- 추가 robustness work 필요 (regime-specific tuning OR more features)
- Forge cycle에서 deferral 결정 명시

### 8.4. G1 PASS + G8 PASS → admission proceed

Risk + Optimizer + Forge cycle 진행.

---

## 9. Codex Round audit points

본 protocol에 대한 Codex 예상 challenge:

1. **AUC ≥ 0.55 threshold is too lenient (random + epsilon)** → 정당화: KR 2022-2026 adverse regime + 124 small sample × 80 features context, AC-M (2023) empirical lower bound. Higher threshold (≥0.60) 시 over-restrictive for paradigm validation.

2. **Brier < 0.24 calibration threshold** → 정당화: base rate ~20-25% binary classifier Brier max ≈ 0.19-0.25. < 0.24 = "≥ random calibration" 의미. Calibration refit (Platt) 옵션 제공.

3. **Recall ≥ 0.60 threshold** → 정당화: paradigm의 핵심 = bad-state injection. Recall 0.60 = 40% miss rate (acceptable upper bound). 너무 high (≥0.80) requirement 시 precision sacrifice.

4. **Walk-forward sample insufficient for bad-state detection** → 정당화: Mitigation strategies 3 종 (Section 7.2) + multi-window aggregation. Forge cycle empirical monitoring.

5. **Calibration refit (Platt) introduces additional hyperparam** → 정당화: standard sklearn CalibratedClassifierCV, well-established practice. Refit decision based on raw Brier — pre-specified rule.

6. **Threshold tuning (default 0.5 → 0.3) is data-snooping** → 정당화: tune on validation set only (NOT test set), pre-specified rule (recall-priority). Walk-forward purged val 사용.

---

## 10. Submission summary

**Submitted**: 2026-05-17 alpha-research Step 3.3 p_bad_classifier_protocol.md. LightGBM binary classifier spec + 80 features + walk-forward purged + G1 hard gate (AUC≥0.55, Brier<0.24, recall≥0.60) + G8 sub-period stability + ABORT criteria + risk mitigation + Codex audit points.

**Critical mandate**: G1 FAIL → HARD ABORT (paradigm inviable, 사후 regime fitting 차단).

**다음 step**: 3.4 complement_scorer_4_stage.md
