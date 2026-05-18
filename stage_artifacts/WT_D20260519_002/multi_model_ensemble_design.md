# Multi-Model Ensemble Design — Step 2.3

**WT-D20260519_002 Bear Prediction Engine v1.0**

**v5 fail mode 직접 fix**: "Single model (LightGBM only)" — sub-window 0/4 stability fail.

**v1 redesign**: **5-model ensemble** with diverse paradigms + Platt scaling calibration + ensemble strategy compare.

---

## 1. Design philosophy

각 model이 다른 inductive bias 가지므로 ensemble 시 noise reduction + sub-window robustness ↑:

| Model | Inductive bias | Strength | Weakness |
|---|---|---|---|
| **Logistic Regression** | Linear additive | Interpretable + L1 feature selection + stable | Cannot capture interaction |
| **LightGBM** | Tree gradient boost | Interaction + nonlinearity + NaN native | Overfit short windows |
| **Random Forest** | Tree bagging | Variance reduction + feature importance stability | Less calibrated |
| **LSTM/GRU** | Sequential temporal | Captures vol clustering + autocorrelation | Data-hungry + black box |
| **Markov Switching** | State transition probability | Regime persistence + economic interpretability | Limited feature capacity |

**Ensemble target**: each model individually may pass G1 partially; ensemble overlap = stable detection.

---

## 2. Model 1 — Logistic Regression (L1 regularized baseline)

### Architecture

```r
library(glmnet)
fit_logistic <- function(X_train, y_train, X_val, y_val) {
  # L1 regularization (lasso) for feature selection
  cv_fit <- cv.glmnet(
    x = as.matrix(X_train),
    y = y_train,
    family = "binomial",
    alpha = 1,           # L1
    type.measure = "auc",
    nfolds = 5,
    foldid = time_series_folds(nrow(X_train), n=5)  # Purged WF
  )
  # Predict val
  p_val <- predict(cv_fit, newx = as.matrix(X_val), s = "lambda.1se", type = "response")
  return(list(model = cv_fit, p_val = as.vector(p_val)))
}
```

### Hyperparameters (pre-declared, no shopping)

- α = 1 (L1 only)
- λ via 5-fold CV (purged WF aware)
- standardize = TRUE
- type.measure = "auc"

### Role

- **Interpretable baseline** — feature coefficients direct economic meaning
- L1 sparsity → top features identified (sparse + economically meaningful)
- Stability across sub-windows expected high (linear additive less overfit)

### Expected metric

- AUC: 0.55~0.65 (moderate)
- Calibration: good (logistic is naturally calibrated)
- Sub-window stability: high (linear robust)

---

## 3. Model 2 — LightGBM (v5 baseline, retain for compare)

### Architecture

```r
library(lightgbm)
fit_lgbm <- function(X_train, y_train, X_val, y_val) {
  dtrain <- lgb.Dataset(as.matrix(X_train), label = y_train)
  dval <- lgb.Dataset(as.matrix(X_val), label = y_val)
  params <- list(
    objective = "binary",
    metric = "auc",
    learning_rate = 0.05,
    num_leaves = 31,
    max_depth = 6,
    min_data_in_leaf = 30,
    feature_fraction = 0.7,
    bagging_fraction = 0.7,
    bagging_freq = 5,
    lambda_l1 = 0.1,
    lambda_l2 = 0.1,
    is_unbalance = TRUE,    # class imbalance handling
    verbose = -1
  )
  fit <- lgb.train(
    params = params,
    data = dtrain,
    valids = list(val = dval),
    nrounds = 500,
    early_stopping_rounds = 30
  )
  p_val <- predict(fit, as.matrix(X_val))
  return(list(model = fit, p_val = p_val))
}
```

### Hyperparameters (pre-declared)

- learning_rate = 0.05
- num_leaves = 31
- max_depth = 6
- min_data_in_leaf = 30
- feature_fraction = 0.7
- bagging_fraction = 0.7
- lambda_l1 = lambda_l2 = 0.1
- is_unbalance = TRUE (class_weight handling)

### Role

- v5 inherit (baseline for direct compare)
- NaN native handling (stratum S1 limited features OK)
- Interaction capture

### Expected metric

- AUC: 0.60~0.70
- Calibration: needs Platt scaling
- Sub-window stability: moderate

---

## 4. Model 3 — Random Forest (variance reduction)

### Architecture

```r
library(ranger)
fit_rf <- function(X_train, y_train, X_val, y_val) {
  fit <- ranger(
    formula = y ~ .,
    data = data.frame(X_train, y = y_train),
    num.trees = 500,
    mtry = floor(sqrt(ncol(X_train))),
    min.node.size = 10,
    sample.fraction = 0.7,
    probability = TRUE,
    importance = "impurity",
    case.weights = ifelse(y_train == 1, 5, 1),  # class imbalance
    seed = 42
  )
  p_val <- predict(fit, X_val)$predictions[, "1"]
  return(list(model = fit, p_val = p_val))
}
```

### Hyperparameters (pre-declared)

- num.trees = 500
- mtry = √n_features
- min.node.size = 10
- sample.fraction = 0.7
- case.weights = 5x for positive class

### Role

- Bagging variance reduction (orthogonal to boosting)
- Feature importance stability check
- NaN handling: impute median per stratum

### Expected metric

- AUC: 0.55~0.65
- Calibration: needs Platt scaling
- Feature importance: stable across sub-windows

---

## 5. Model 4 — LSTM/GRU (sequential temporal)

### Architecture

```python
import torch
import torch.nn as nn

class BearPredictorLSTM(nn.Module):
    def __init__(self, n_features, hidden_size=32, n_layers=2, dropout=0.3):
        super().__init__()
        self.lstm = nn.LSTM(
            input_size=n_features,
            hidden_size=hidden_size,
            num_layers=n_layers,
            dropout=dropout,
            batch_first=True
        )
        self.fc = nn.Linear(hidden_size, 1)
        self.sigmoid = nn.Sigmoid()
    
    def forward(self, x):
        # x: (batch, seq_len=20, n_features)
        h, _ = self.lstm(x)
        last = h[:, -1, :]  # last time step
        out = self.fc(last)
        return self.sigmoid(out).squeeze()
```

### Hyperparameters (pre-declared)

- hidden_size = 32 (small, ~5K params)
- n_layers = 2
- dropout = 0.3
- seq_len = 20 (4 weeks lookback)
- batch_size = 64
- learning_rate = 1e-3
- optimizer = Adam
- weight_decay = 1e-4
- n_epochs = 50 with early stopping (patience=10)
- loss = BCELoss with pos_weight = 4 (imbalance)

### Role

- Sequential pattern capture (vol clustering, autocorrelation)
- Required input: feature sequence shape (T, 20, n_features)
- Architecture small (~5K params) — over-parameterization prevention (L-328 DPL_KR_v1 165K fail learning)

### Caveat (L-328 learning)

**DPL_KR_v1 165K params over-parameterized vs ~5K effective obs**. 본 cycle은:
- **Feature input = 32 features (small)**
- **Hidden = 32 (small)**
- **Total params ~5K**
- **Effective obs = 437 monthly OR ~9000 daily** (depending on aggregation)
- Daily mode: ~9000 obs vs ~5K params = OK (1.8× ratio)
- Monthly mode: ~437 obs vs ~5K params = **over-parameterized** → use monthly LSTM only as ensemble member, not solo

### Expected metric

- AUC: 0.55~0.70 (high variance)
- Calibration: needs Platt scaling
- Sub-window stability: moderate (sequential pattern can overfit specific periods)

---

## 6. Model 5 — Markov Switching Model (Hamilton 1989)

### Architecture

```r
library(MSwM)  # or mhsmm

fit_msm <- function(BM_Ret_train, X_train_macro) {
  # 2-state MSM: bull (state 1) vs bear (state 2)
  # Mean / vol regime switch
  # Optional: time-varying transition with macro features
  
  fit <- msmFit(
    object = lm(BM_Ret ~ X_train_macro),  # Conditional mean depends on macro
    k = 2,                                  # 2 states
    sw = c(TRUE, FALSE, FALSE, FALSE, TRUE),  # intercept + var switching
    p = 1                                   # AR(1)
  )
  
  # Smoothed probability of being in bear state
  p_bear_smooth <- fit@Fit@smoProb[, 2]
  
  return(list(model = fit, p_bear = p_bear_smooth))
}
```

### Hyperparameters (pre-declared)

- n_states = 2 (bull + bear) — most parsimonious
- Switching: intercept + variance (NOT all coefficients)
- AR order: p = 1
- Conditional mean: linear in macro features (top 5 from L1 feature selection)
- EM iterations: 200 with convergence tol 1e-6

### Role

- **Regime probability output** = direct economic interpretation
- Time-varying transition probability (macro feature aware)
- Hamilton 1989 classical recession model

### Caveat

- Restricted feature capacity (cannot use all 32, only top 5 to avoid singular Σ)
- Computational: EM convergence sensitive
- Pre-declared feature subset: F01 (yield curve), F11 (VIX), F23 (credit spread), F29 (foreign flow), F14 (KOSPI vol)

### Expected metric

- AUC: 0.55~0.65
- Sub-window stability: HIGH (state model robust to noise)
- Calibration: smoothed probability natively calibrated

---

## 7. Ensemble Strategy — 3 strategies compared

### Strategy 1: Simple average

```r
p_ensemble_t = (p_logistic_t + p_lgbm_t + p_rf_t + p_lstm_t + p_msm_t) / 5
```

- Pros: simplest, no meta-learning, robust
- Cons: no model weighting by individual quality

### Strategy 2: Stacking (logistic meta-learner)

```r
# Stack: each model trained on train, predict on val + test
# Meta-learner: logistic regression on validation predictions
meta_fit <- glmnet(
  x = cbind(p_logistic_val, p_lgbm_val, p_rf_val, p_lstm_val, p_msm_val),
  y = y_val,
  family = "binomial",
  alpha = 1
)
p_ensemble_test <- predict(meta_fit, cbind(p_logistic_test, ..., p_msm_test), s = "lambda.1se", type = "response")
```

- Pros: learns optimal blend
- Cons: meta-overfitting risk on small val set

### Strategy 3: Voting (majority hard vote)

```r
# Each model thresholds at 0.5, vote
votes_t = (p_logistic_t > 0.5) + (p_lgbm_t > 0.5) + (p_rf_t > 0.5) + (p_lstm_t > 0.5) + (p_msm_t > 0.5)
p_ensemble_t = votes_t / 5
```

- Pros: discrete, intuitive
- Cons: discards probability gradient

**Default**: Strategy 1 (simple average) + Strategy 2 (stacking) compare in Forge. Voting as ablation only.

---

## 8. Calibration — Platt scaling + isotonic

### Platt scaling (default)

```r
# After ensemble probability p_ensemble_val
fit_platt <- glm(y_val ~ p_ensemble_val, family = binomial)
# Predict on test
p_calibrated_test <- predict(fit_platt, newdata = data.frame(p_ensemble_val = p_ensemble_test), type = "response")
```

### Isotonic regression (alternative)

```r
library(stats)
fit_iso <- isoreg(p_ensemble_val, y_val)
p_calibrated_test <- approx(fit_iso$x, fit_iso$yf, p_ensemble_test, rule = 2)$y
```

### Calibration metric

- Brier score < 0.20 (G1)
- Expected Calibration Error (ECE) over 10 bins < 0.05
- Reliability diagram slope ≈ 1.0 ± 0.1

---

## 9. Training protocol (Purged Walk-Forward)

### Walk-forward refit schedule

```
Initial fit:         train 1990-01~2010-12 (252m) — fit all 5 models
Refit cadence:       every 12 months (annual)
Embargo:             1 month between train/val and val/test
Final OOS test:      2015-01~2026-05 (137m)
```

### Per-window train/val/test split

```
For window k (refit-k):
  Train ending at:  2010-12 + 12*(k-1) months
  Val window:       next 12 months after train (with 1m embargo before train end)
  Test window:      next 12 months after val (with 1m embargo)
```

### Sub-window evaluation (5 sub-windows)

| Sub-window | Period | Train | Val | Test |
|---|---|---|---|---|
| W1 | 2015-01~2017-12 | 1990~2014-12 | 2014-01~2014-12 | 2015-01~2017-12 |
| W2 | 2018-01~2020-12 | 1990~2017-12 | 2017-01~2017-12 | 2018-01~2020-12 (COVID + 2018 vol) |
| W3 | 2021-01~2022-12 | 1990~2020-12 | 2020-01~2020-12 | 2021-01~2022-12 (Inflation) |
| W4 | 2023-01~2024-12 | 1990~2022-12 | 2022-01~2022-12 | 2023-01~2024-12 |
| W5 | 2025-01~2026-05 | 1990~2024-12 | 2024-01~2024-12 | 2025-01~2026-05 (incl 2026-03) |

**Sub-window stability G1**: at least **4/5 windows** all pass (AUC≥0.60, Brier<0.20, Recall≥0.60, Precision≥0.40).

---

## 10. Hyperparameter discipline (no shopping mandate)

**모든 hyperparameter pre-declared above. NO grid search post-hoc.**

If Forge cycle empirical shows specific model fails, **disable that model from ensemble** rather than re-tune (= data mining 회피).

**Allowed adjustments**:
- learning_rate ±factor 2 only (e.g., 0.05 → 0.025 OR 0.1) for convergence
- early_stopping_rounds increase (30 → 50) for stability
- Documented in `method_shopping_log` if used

**Forbidden**:
- Threshold tuning for G1 sub-windows specifically
- Feature subset tuning per-window
- Model architecture changes per-window

---

## 11. Method shopping log (R2-C 정합)

**candidates_tried = 1** (단일 5-model ensemble design family — 8 학술 backbone + 5 diverse model paradigms = single coherent design).

각 model은 sub-component (단일 family within ensemble), 별도 method 아님.

**Ensemble strategy variants** (max 3 candidates):
1. Simple average
2. Stacking
3. Voting (ablation)

Default emit: simple average. Stacking compare via Forge.

---

## 12. Audit conclusion

도훈 mandate **"5-model ensemble + Platt scaling calibration"** 정합 PASS:

1. ✅ 5 models pre-declared (Logistic L1 + LightGBM + RF + LSTM + MSM Hamilton)
2. ✅ Each model architecture + hyperparams 명시 (no post-hoc shopping)
3. ✅ 3 ensemble strategies (simple avg / stacking / voting), default simple avg
4. ✅ Platt scaling + isotonic calibration
5. ✅ Purged WF + 1m embargo (Lopez de Prado)
6. ✅ 5 sub-windows G1 stability 4/5 binding
7. ✅ Class imbalance handled (is_unbalance + case.weights + pos_weight)
8. ✅ L-328 learning (LSTM small 5K params for monthly mode)

**v5 fix evidence**:
- "Single model (LightGBM only)" → "5-model ensemble"
- "sub-window stability 0/4" → "sub-window stability 4/5 mandate via diverse paradigms"

---

## 참조

- Hamilton 1989 Econometrica (Markov Switching)
- Friedman, J. (2001). Greedy function approximation: A gradient boosting machine. *Annals of Statistics*. [LightGBM grounding]
- Breiman, L. (2001). Random forests. *Machine Learning*. [RF grounding]
- Hochreiter, S., & Schmidhuber, J. (1997). Long short-term memory. *Neural Computation*. [LSTM]
- Platt, J. (1999). Probabilistic outputs for support vector machines. [Platt scaling]
- Zadrozny, B., & Elkan, C. (2002). Transforming classifier scores into accurate multiclass probability estimates. KDD. [isotonic]
- Tibshirani, R. (1996). Regression shrinkage and selection via the lasso. *JRSSB*. [L1]
- López de Prado, M. (2018). *Advances in Financial Machine Learning*. Ch 7 (Purged WF + Embargo)
- L-328 (DPL_KR_v1 165K params over-parameterized learning)
