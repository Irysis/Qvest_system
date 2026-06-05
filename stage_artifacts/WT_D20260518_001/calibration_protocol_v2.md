# Bear Regime Prediction Engine v2.0 — Calibration Protocol

## 1. Root Cause Diagnosis (v1.0 lesson)

v1.0 Forge cycle (WT-D20260519_002) measured:
- **Ranking power exists**: W4 AUC=0.79, W5 AUC=0.85, ensemble mean AUC=0.6117 across 4 OOS windows
- **Threshold-based decisioning fails**: Recall@τ=0.5 = **0** across all 4 evaluable windows (W1 had no positive class)
- **Diagnosis from forge_package.json**: `p_mean_bear_class=0.120, p_mean_non_bear_class=0.130, p_max_bear_class=0.397`

Interpretation: ensemble raw probabilities are **systematically biased toward base rate (~0.11–0.13 bear class ratio)**. The classifier outputs reflect the prior (P(bear)≈0.13) rather than calibrated posterior probabilities. Therefore even for true bear months, p_bad rarely exceeds 0.4 and never reaches 0.5.

This is the **canonical "uncalibrated classifier on imbalanced class" failure mode** (Niculescu-Mizil & Caruana 2005, Platt 1999).

## 2. v2.0 Mandate (4 axes, all MANDATORY)

### Axis 1: Probability Calibration (Platt or Isotonic) — MANDATORY

| Method | Reference | When Best | Forge cycle binding |
|---|---|---|---|
| **Platt scaling** (sigmoid) | Platt (1999) | parametric monotonic, low N | Logistic L1, MarkovSwitching |
| **Isotonic regression** | Zadrozny-Elkan (2002) | nonparametric monotonic, high N (>1000 obs) | LightGBM, RandomForest, LSTM, Ensemble |
| **Beta calibration** | Kull-Silva-Flach (2017) | flexible monotonic via Beta CDF | Optional ensemble compare |

**Binding rule (Forge Stage 3)**:
- Each base model fit on **train_window** (expanding) → score on **calibration_window** (last 12 months of train, held out)
- Fit calibrator on calibration_window predictions → apply on **validation_window** + **test_window**
- **No future-leakage**: calibrator fit timestamp = train_window_end, not full-sample
- **PIT enforcement**: calibrator parameters frozen per walk-forward window

Pseudocode (Python sklearn-style, Forge cycle):
```python
# Train base classifier on expanding window train_window
clf.fit(X_train, y_train, sample_weight=cost_sensitive_weights)

# Score held-out calibration_window (last 12m of train_window)
p_raw_calib = clf.predict_proba(X_calib)[:, 1]

# Fit isotonic regressor on (p_raw_calib, y_calib)
calibrator = IsotonicRegression(out_of_bounds='clip')
calibrator.fit(p_raw_calib, y_calib)

# Apply on validation + test
p_calibrated_val = calibrator.transform(clf.predict_proba(X_val)[:, 1])
p_calibrated_test = calibrator.transform(clf.predict_proba(X_test)[:, 1])
```

R alternative (`CORElearn::calibrate` or `glmnet` Platt manual):
```r
# Platt scaling manual
calib_fit <- glm(y_calib ~ p_raw_calib, family = binomial())
p_calibrated <- predict(calib_fit, newdata = data.frame(p_raw_calib = p_raw_test), type = "response")

# Isotonic
isotonic_fit <- isoreg(p_raw_calib, y_calib)
# Apply via stepfun interpolation (manual)
```

### Axis 2: Cost-sensitive Classifier — MANDATORY

**Class imbalance**: bear class ratio ~11–13% (v1.0 empirical) → naive classifier overweights majority class.

**Binding rule**:
- LightGBM: `scale_pos_weight = (1 - p_bear) / p_bear ≈ 8.0` (computed per window, not full-sample)
- RandomForest: `class_weight = "balanced"` (sklearn) or `classwt = c(1, 1/p_bear)`
- Logistic L1: sample_weight = `1/p_bear` for positive class, `1/(1-p_bear)` for negative class
- LSTM: weighted BCE loss `loss = -[w_pos * y * log(p) + w_neg * (1-y) * log(1-p)]` where w_pos/w_neg = inverse class prior
- MarkovSwitching: prior probability `pi_bear = 0.5` (uninformative) rather than empirical 0.13

**Rationale (He-Garcia 2009 IEEE TKDE)**: For minority class detection (bear regime), naive ML reaches Bayes-optimal decision boundary at base rate. Cost-sensitive learning shifts the boundary to balance Type I / Type II error tradeoff.

**Critical distinction**: cost-sensitive weighting addresses the **classifier's internal optimization** (it now tries harder to predict bear). Calibration (Axis 1) addresses **probability output scale** (it now produces well-calibrated posterior). Both are necessary — neither alone fixes Recall@0.5=0.

### Axis 3: Threshold Optimization — MANDATORY

**Current failure**: τ=0.5 hard-coded → never reached because raw probs biased to base rate.

**Alternative threshold selection** (per walk-forward window):

| Method | Formula | Reference | Recommended |
|---|---|---|---|
| **Youden's J** | argmax_τ [TPR(τ) - FPR(τ)] | Youden (1950) | **primary** |
| **Cost-weighted** | argmin_τ [c_FN * FN(τ) + c_FP * FP(τ)] | Elkan (2001) | secondary (asymmetric cost) |
| **F1 maximization** | argmax_τ F1(τ) | — | tertiary |
| **Base-rate scaled** | τ = P(bear) | naive baseline | for benchmark only |

**Binding rule (Forge Stage 3)**:
- Compute τ_optimal on **calibration_window** (same window as Axis 1 calibrator fit)
- Apply τ_optimal on validation + test
- Report metrics at both τ=0.5 (legacy) AND τ_optimal (v2.0 fix)
- Report τ_optimal per window — must be > 0.1 and < 0.9 (sanity bounds)

**Cost-weighted formula** (for crisis_alpha role):
- c_FN (cost of missing bear) > c_FP (cost of false alarm)
- Default: c_FN / c_FP = 3 (asymmetric — missing a crisis is 3x worse than spurious defensive scaling)
- Justification: Layer 6 β_bear schedule transitions on false positive add 30bps round-trip cost vs missing -15% crisis is catastrophic

### Axis 4: W3 Feature Drift Stratified Retrain (Pesaran-Timmermann 2007) — MANDATORY

**v1.0 W3 failure**: 2021-2022 sub-window AUC=0.364 (anti-predictive). Diagnosis: post-COVID regime is structurally different from 2018-2020 train → feature relationships drift.

**Binding rule**:
- 3 macro regime strata pre-declared at sig_date level (NOT looking forward):
  - **REGIME_LOW_VOL_QE**: VIX < 20 AND FED_Funds_Rate < 1% (loose monetary, low vol)
  - **REGIME_HIGH_VOL_TAPER**: VIX ≥ 20 AND FED_Funds_Rate rising (tightening cycle, vol spike)
  - **REGIME_INFLATION**: CPI_YoY > 3% AND FED_Funds_Rate > 3% (inflation regime)
- Each sig_date assigned to regime via macro features at t-1 (no future info)
- **Stratified retrain**: train separate model per regime (3 sub-models)
- **Inference**: at sig_date t, assign current regime → use corresponding sub-model
- **Fallback**: if current_regime sub-sample < 30 obs in train_window, use full-history model (avoid overfitting)
- Regime detection method: rule-based pre-declared (no in-sample optimization of thresholds — Pesaran-Timmermann 2007 §3 emphasis)

**Pesaran-Timmermann 2007 reference**: "Regimes (defined by macro state) are exogenously segmented to avoid in-sample structural break detection bias". Our rule-based stratification matches this requirement.

## 3. Validation Protocol (Forge cycle Stage 3 binding)

### Per-window report (5 sub-windows × G1 5-subgate × 3 strata × 2 thresholds = 150 metrics)

Per (sub_window, regime_stratum, threshold), report:
- AUC
- Brier score
- Recall@τ
- Precision@τ
- F1@τ
- Calibration error (Expected Calibration Error, ECE)
- Reliability diagram bins (10 quantile bins)

### Aggregate report (Forge Stage 4)

| Metric | v1.0 actual | v2.0 target | v2.0 hard threshold |
|---|---|---|---|
| AUC | 0.6117 mean | ≥ 0.65 mean, ≥ 0.60 in 4/5 windows | ≥ 0.60 in 4/5 |
| Brier | 0.155 mean | < 0.15 mean | < 0.20 in 4/5 |
| **Recall@τ_optimal** | **0.0** | **≥ 0.60 mean, ≥ 0.50 in 4/5 windows** | **≥ 0.60 in 4/5** |
| **Precision@τ_optimal** | 0 (degenerate) | ≥ 0.40 in 4/5 | ≥ 0.40 in 4/5 |
| ECE (Expected Calibration Error) | not measured | < 0.05 mean | < 0.10 mean |

### Per-crisis epoch report (subset of stress set A from v1.0)

For each of 8 crisis epochs (1997 IMF / 2000 dotcom / 2008 GFC / 2011 EU / 2015 CN / 2018 vol / 2020 COVID / 2022 inflation):
- Recall@τ_optimal during crisis months
- Precision@τ_optimal during crisis months
- False positive rate during non-crisis months immediately before/after

### Lock-in (NO method shopping post-hoc)

Per Codex C4 disposition from v1.0 (inherit binding):
- All trial counts pre-declared in `method_shopping_log_v2.json` before Forge cycle Stage 3
- 4 axes = 4 trial dimensions
- 5 base models × 3 calibration methods × 2 threshold methods × 3 strata = **90 effective trials** (vs v1.0 declared 20)
- Harvey-Liu-Zhu 2016 t_NW threshold: 3.0 (NW lag-12), DSR n_trials = 90 in Bailey-LdP formula

## 4. Per-window Calibration Audit (PIT C1, C11 strict)

For each walk-forward window, save audit row:
```json
{
  "window_id": "W2",
  "train_window": "1990-01-01_2017-12-31",
  "calibration_window": "2017-01-01_2017-12-31",
  "validation_window": "2018-01-01_2019-12-31",
  "test_window": "2020-01-01_2021-12-31",
  "n_train": 336,
  "n_calib": 12,
  "n_val": 24,
  "n_test": 24,
  "bear_ratio_train": 0.131,
  "bear_ratio_calib": 0.083,
  "scale_pos_weight": 6.60,
  "calibrator_method": "isotonic",
  "tau_optimal_youden": 0.32,
  "tau_optimal_cost_weighted_3to1": 0.27,
  "ece_validation": 0.043,
  "ece_test": 0.052
}
```

## 5. References

- **Platt, J. (1999)**. Probabilistic outputs for support vector machines and comparisons to regularized likelihood methods. *Advances in Large Margin Classifiers*, 10(3), 61–74.
- **Zadrozny, B., & Elkan, C. (2002)**. Transforming classifier scores into accurate multiclass probability estimates. *KDD '02 Proceedings*, 694–699.
- **Niculescu-Mizil, A., & Caruana, R. (2005)**. Predicting good probabilities with supervised learning. *ICML '05 Proceedings*, 625–632.
- **Kull, M., Silva Filho, T., & Flach, P. (2017)**. Beta calibration: a well-founded and easily implemented improvement on logistic calibration for binary classifiers. *AISTATS 2017*.
- **He, H., & Garcia, E. A. (2009)**. Learning from imbalanced data. *IEEE TKDE*, 21(9), 1263–1284.
- **Elkan, C. (2001)**. The foundations of cost-sensitive learning. *IJCAI '01 Proceedings*, 17(1), 973–978.
- **Youden, W. J. (1950)**. Index for rating diagnostic tests. *Cancer*, 3(1), 32–35.
- **Pesaran, M. H., & Timmermann, A. (2007)**. Selection of estimation window in the presence of breaks. *Journal of Econometrics*, 137(1), 134–161.

## 6. Forge Cycle Stage 3 Pre-declared Bindings (v2.0 contract)

1. **Calibration**: isotonic primary, Platt secondary, Beta tertiary — all 3 fit per window, ECE comparison reported
2. **Cost-sensitive**: `scale_pos_weight = (1-p_bear_train)/p_bear_train` computed per window from train data only (PIT-safe)
3. **Threshold**: Youden's J primary, cost-weighted 3:1 secondary, F1 tertiary — all 3 selected per window, all reported
4. **Stratified retrain**: 3 regime sub-models per window, fallback to full-history if sub-sample < 30

Failure to satisfy all 4 axes = v2.0 Phase A design invalidation. Forge cycle pre-execution audit binding.
