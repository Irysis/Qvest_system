"""5 ML candidates — Kelly-Malamud-Zhou 2024 정통 high-dim regularization + GPU.

M1 Ridge / M2 LASSO / M3 ElasticNet (glmnet equivalents via sklearn)
M4 XGBoost-GPU (RTX 4080) / M5 LightGBM (CPU, GPU optional)
+ M6 Ensemble (rank-average)
"""
import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge, Lasso, ElasticNet
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
import xgboost as xgb
import lightgbm as lgb


def _prep(X: pd.DataFrame, fit_scaler=None) -> tuple:
    """Median imputation + Standardize. Returns (X_array, scaler)."""
    imputer = SimpleImputer(strategy="median")
    X_imp = imputer.fit_transform(X)
    if fit_scaler is None:
        scaler = StandardScaler()
        X_std = scaler.fit_transform(X_imp)
        return X_std, scaler, imputer
    else:
        X_std = fit_scaler.transform(X_imp)
        return X_std, fit_scaler, None


def train_ridge(X_train, y_train, alpha=1.0):
    scaler = StandardScaler()
    imputer = SimpleImputer(strategy="median")
    X_imp = imputer.fit_transform(X_train)
    X_std = scaler.fit_transform(X_imp)
    model = Ridge(alpha=alpha, fit_intercept=True)
    model.fit(X_std, y_train)
    return {"model": model, "scaler": scaler, "imputer": imputer}


def train_lasso(X_train, y_train, alpha=0.01):
    scaler = StandardScaler()
    imputer = SimpleImputer(strategy="median")
    X_imp = imputer.fit_transform(X_train)
    X_std = scaler.fit_transform(X_imp)
    model = Lasso(alpha=alpha, fit_intercept=True, max_iter=10000)
    model.fit(X_std, y_train)
    return {"model": model, "scaler": scaler, "imputer": imputer}


def train_elastic_net(X_train, y_train, alpha=0.01, l1_ratio=0.5):
    scaler = StandardScaler()
    imputer = SimpleImputer(strategy="median")
    X_imp = imputer.fit_transform(X_train)
    X_std = scaler.fit_transform(X_imp)
    model = ElasticNet(alpha=alpha, l1_ratio=l1_ratio, fit_intercept=True, max_iter=10000)
    model.fit(X_std, y_train)
    return {"model": model, "scaler": scaler, "imputer": imputer}


def train_xgboost_gpu(X_train, y_train, n_rounds=200, max_depth=6, eta=0.05):
    """XGBoost on GPU (RTX 4080). tree_method=hist + device=cuda."""
    imputer = SimpleImputer(strategy="median")
    X_imp = imputer.fit_transform(X_train)
    dtrain = xgb.DMatrix(X_imp, label=y_train)
    params = {
        "tree_method": "hist",
        "device": "cuda",
        "objective": "reg:squarederror",
        "max_depth": max_depth,
        "eta": eta,
        "subsample": 0.8,
        "colsample_bytree": 0.6,
        "reg_lambda": 1.0,
        "verbosity": 0,
    }
    model = xgb.train(params, dtrain, num_boost_round=n_rounds)
    return {"model": model, "imputer": imputer, "type": "xgb"}


def train_lightgbm(X_train, y_train, n_rounds=200, max_depth=6, lr=0.05):
    """LightGBM (CPU default, GPU optional via device='gpu')."""
    imputer = SimpleImputer(strategy="median")
    X_imp = imputer.fit_transform(X_train)
    ds = lgb.Dataset(X_imp, label=y_train)
    params = {
        "objective": "regression",
        "metric": "rmse",
        "num_leaves": 2 ** max_depth,
        "learning_rate": lr,
        "feature_fraction": 0.6,
        "bagging_fraction": 0.8,
        "bagging_freq": 5,
        "verbosity": -1,
    }
    model = lgb.train(params, ds, num_boost_round=n_rounds)
    return {"model": model, "imputer": imputer, "type": "lgb"}


def predict(fitted: dict, X_val: pd.DataFrame) -> np.ndarray:
    """Unified predict across model types."""
    X_imp = fitted["imputer"].transform(X_val)
    typ = fitted.get("type")
    if typ == "xgb":
        return fitted["model"].predict(xgb.DMatrix(X_imp))
    if typ == "lgb":
        return fitted["model"].predict(X_imp)
    # sklearn linear (Ridge/LASSO/EN)
    X_std = fitted["scaler"].transform(X_imp)
    return fitted["model"].predict(X_std)


def predict_ensemble(predictions_dict: dict) -> np.ndarray:
    """Rank-average ensemble across model predictions.

    Args:
        predictions_dict: {model_name: np.array of predictions}
    Returns:
        rank-averaged ensemble prediction
    """
    rank_preds = []
    for name, pred in predictions_dict.items():
        rank_preds.append(pd.Series(pred).rank(pct=True).values)
    return np.mean(rank_preds, axis=0)


# =============================================================================
# Phase 1.A — Uncertainty-aware Forecasting (Liao-Ma-Neuhierl-Schilling 2025 RFS)
# =============================================================================

def bootstrap_predictions(train_fn, X_train, y_train, X_val,
                           n_bootstraps: int = 50,
                           sample_frac: float = 0.8,
                           random_state: int = 42) -> dict:
    """Bootstrap prediction interval via subsample bagging.

    Args:
        train_fn: callable(X, y) → fitted model dict (e.g., train_ridge)
        X_train, y_train: training data
        X_val: validation features
        n_bootstraps: number of bootstrap rounds (default 50, fast vs B=100)
        sample_frac: per-bootstrap subsample fraction
        random_state: seed for reproducibility

    Returns:
        {"mean": np.array, "std": np.array, "p05/p25/p50/p75/p95": np.arrays}
    """
    rng = np.random.default_rng(random_state)
    n_train = len(X_train) if hasattr(X_train, "__len__") else X_train.shape[0]
    sample_size = int(n_train * sample_frac)

    all_preds = []
    X_train_arr = X_train.values if hasattr(X_train, "values") else X_train
    y_train_arr = y_train if isinstance(y_train, np.ndarray) else np.asarray(y_train)

    for b in range(n_bootstraps):
        idx = rng.choice(n_train, size=sample_size, replace=True)
        X_b = X_train_arr[idx]
        y_b = y_train_arr[idx]
        try:
            # Reconstruct as DataFrame if original was DataFrame (preserve column names for some models)
            if hasattr(X_train, "columns"):
                X_b = pd.DataFrame(X_b, columns=X_train.columns)
            fitted = train_fn(X_b, y_b)
            pred = predict(fitted, X_val)
            all_preds.append(pred)
        except Exception as e:
            continue

    if len(all_preds) < 10:
        # Fallback: single fit, zero std
        fitted = train_fn(X_train, y_train)
        pred = predict(fitted, X_val)
        return {"mean": pred, "std": np.zeros_like(pred),
                "p05": pred, "p25": pred, "p50": pred, "p75": pred, "p95": pred,
                "n_bootstraps": 1}

    preds_arr = np.array(all_preds)  # (n_boot, n_val)
    return {
        "mean": preds_arr.mean(axis=0),
        "std":  preds_arr.std(axis=0, ddof=1),
        "p05":  np.percentile(preds_arr, 5, axis=0),
        "p25":  np.percentile(preds_arr, 25, axis=0),
        "p50":  np.percentile(preds_arr, 50, axis=0),
        "p75":  np.percentile(preds_arr, 75, axis=0),
        "p95":  np.percentile(preds_arr, 95, axis=0),
        "n_bootstraps": len(all_preds),
    }


def uncertainty_discounted_alpha(pred_mean: np.ndarray,
                                  pred_std: np.ndarray,
                                  k: float = 1.0) -> np.ndarray:
    """μ̃ = μ̂ - k·SE(μ̂) per Liao 2025 RFS.

    k ∈ [0.5, 2.0] typical. k=1.0 is one-sigma discount.
    """
    return pred_mean - k * pred_std


# =============================================================================
# Phase 1.B — Cost-aware ML Loss (Jensen-Kelly-Malamud-Pedersen 2022)
# =============================================================================

def train_xgboost_gpu_cost_aware(X_train, y_train,
                                   n_rounds: int = 200,
                                   max_depth: int = 6,
                                   eta: float = 0.05,
                                   cost_penalty_lambda: float = 0.0):
    """XGBoost-GPU with cost-aware regularization via stronger L2.

    Note: XGBoost objective customization for turnover is non-trivial since turnover
    depends on cross-sectional rank rather than absolute prediction. We approximate
    cost-aware via:
      (a) Stronger reg_lambda (penalizes prediction magnitude → smoother rankings → lower turnover)
      (b) Lower subsample / smaller eta (smoother fitted surface)
    Post-prediction turnover measurement in quality_metrics.cost_adjusted_ic provides
    the ex-post check.
    """
    imputer = SimpleImputer(strategy="median")
    X_imp = imputer.fit_transform(X_train)
    dtrain = xgb.DMatrix(X_imp, label=y_train)
    params = {
        "tree_method": "hist",
        "device": "cuda",
        "objective": "reg:squarederror",
        "max_depth": max_depth,
        "eta": eta * 0.6,                       # smoother
        "subsample": 0.7,                       # smoother
        "colsample_bytree": 0.5,                # smoother
        "reg_lambda": 1.0 + cost_penalty_lambda * 10.0,  # stronger L2 → lower turnover
        "verbosity": 0,
    }
    model = xgb.train(params, dtrain, num_boost_round=n_rounds)
    return {"model": model, "imputer": imputer, "type": "xgb"}
