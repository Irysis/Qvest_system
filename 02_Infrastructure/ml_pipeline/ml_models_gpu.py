"""GPU-accelerated bootstrap (PyTorch CUDA) — Ridge closed-form batch fit.

도훈 mandate 2026-05-15: Bootstrap M1 Ridge × 50 × 5 folds = 250 fits → GPU 가속.

Strategy:
  - Ridge closed-form: β = (X^T X + α I)^(-1) X^T y
  - Per-bootstrap subsample (n × p) → GPU matrix solve
  - Chunked batching (memory-bounded): 5-10 bootstraps at a time
  - Expected speedup: 5-10× vs sklearn single-thread CPU

GPU memory budget (RTX 4080 SUPER 16GB):
  - X full: 120k × 1044 × 4B = ~500 MB
  - X^T X: 1044 × 1044 × 4B = ~4.4 MB
  - Per-bootstrap subsample (n=96k, sample_frac=0.8): ~400 MB
  - Batch size 5: ~2 GB peak → safe

Compatible with sklearn API:
  - bootstrap_predictions_gpu(X_train, y_train, X_val, n_bootstraps, sample_frac)
  - returns same dict as ml_models.bootstrap_predictions
"""
import numpy as np
import pandas as pd

try:
    import torch
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False


def _to_tensor(arr, device, dtype=torch.float32 if TORCH_AVAILABLE else None):
    if isinstance(arr, pd.DataFrame):
        arr = arr.values
    return torch.as_tensor(arr, device=device, dtype=dtype)


def _ridge_closed_form_gpu(X: "torch.Tensor", y: "torch.Tensor",
                            alpha: float = 1.0) -> "torch.Tensor":
    """Ridge closed-form: β = (X^T X + α I)^(-1) X^T y on GPU."""
    p = X.shape[1]
    XtX = X.T @ X
    A = XtX + alpha * torch.eye(p, device=X.device, dtype=X.dtype)
    Xty = X.T @ y
    beta = torch.linalg.solve(A, Xty)
    return beta


def _standardize_gpu(X: "torch.Tensor"):
    """Median imputation + Standardize on GPU. Returns (X_std, mean, std)."""
    median = torch.nanmedian(X, dim=0).values
    nan_mask = torch.isnan(X)
    X_imp = torch.where(nan_mask, median.unsqueeze(0).expand_as(X), X)
    mean = X_imp.mean(dim=0)
    std = X_imp.std(dim=0)
    std = torch.where(std < 1e-8, torch.ones_like(std), std)
    X_std = (X_imp - mean) / std
    return X_std, mean, std


def _apply_standardize_gpu(X: "torch.Tensor", mean: "torch.Tensor",
                            std: "torch.Tensor", median: "torch.Tensor"):
    nan_mask = torch.isnan(X)
    X_imp = torch.where(nan_mask, median.unsqueeze(0).expand_as(X), X)
    return (X_imp - mean) / std


def bootstrap_predictions_gpu(X_train, y_train, X_val,
                               n_bootstraps: int = 50,
                               sample_frac: float = 0.8,
                               alpha: float = 1.0,
                               random_state: int = 42,
                               batch_chunk: int = 5,
                               device: str = "cuda") -> dict:
    """GPU-accelerated bootstrap predictions (Ridge closed-form).

    Args:
        X_train, y_train: training data
        X_val: validation features
        n_bootstraps: number of bootstrap rounds (default 50)
        sample_frac: per-bootstrap subsample fraction (default 0.8)
        alpha: Ridge regularization (default 1.0, matches train_ridge)
        random_state: seed
        batch_chunk: bootstraps per GPU batch (memory-bounded, default 5)
        device: "cuda" or "cpu"

    Returns: same as ml_models.bootstrap_predictions (mean/std/p05~p95)
    """
    if not TORCH_AVAILABLE:
        raise ImportError("PyTorch not available. Install: pip install torch")

    if device == "cuda" and not torch.cuda.is_available():
        print("[bootstrap_predictions_gpu] CUDA not available, falling back to CPU")
        device = "cpu"

    rng = np.random.default_rng(random_state)
    n_train = len(X_train) if hasattr(X_train, "__len__") else X_train.shape[0]
    sample_size = int(n_train * sample_frac)

    X_train_arr = X_train.values if hasattr(X_train, "values") else X_train
    y_train_arr = np.asarray(y_train, dtype=np.float32)
    X_val_arr = X_val.values if hasattr(X_val, "values") else X_val

    # Cast to float32 for GPU speed
    X_train_arr = np.asarray(X_train_arr, dtype=np.float32)
    X_val_arr = np.asarray(X_val_arr, dtype=np.float32)

    # Move training data to GPU once
    X_train_t = _to_tensor(X_train_arr, device)
    y_train_t = _to_tensor(y_train_arr, device)
    X_val_t = _to_tensor(X_val_arr, device)

    # Pre-compute global median for fallback imputation
    global_median = torch.nanmedian(X_train_t, dim=0).values

    all_preds = []
    failed_iters = 0

    for chunk_start in range(0, n_bootstraps, batch_chunk):
        chunk_end = min(chunk_start + batch_chunk, n_bootstraps)
        for b in range(chunk_start, chunk_end):
            try:
                idx = rng.choice(n_train, size=sample_size, replace=True)
                idx_t = torch.as_tensor(idx, device=device, dtype=torch.long)
                X_b = X_train_t[idx_t]
                y_b = y_train_t[idx_t]

                # Standardize on this bootstrap's data
                X_b_std, b_mean, b_std = _standardize_gpu(X_b)

                # Ridge closed-form
                beta = _ridge_closed_form_gpu(X_b_std, y_b, alpha=alpha)

                # Apply same standardization to X_val + predict
                X_val_std = _apply_standardize_gpu(X_val_t, b_mean, b_std, global_median)
                pred = X_val_std @ beta
                all_preds.append(pred.cpu().numpy())

                # Free per-bootstrap tensors
                del X_b, y_b, X_b_std, beta, X_val_std, pred
            except Exception as e:
                failed_iters += 1
                print(f"  [bootstrap iter {b}] FAIL: {str(e)[:80]}")
                continue

        # Periodic GPU cache clean
        if device == "cuda":
            torch.cuda.empty_cache()

    if len(all_preds) < 10:
        # Fallback: zero std (no useful uncertainty)
        print(f"[bootstrap_predictions_gpu] WARN: only {len(all_preds)}/{n_bootstraps} succeeded")
        zero_pred = np.zeros(X_val_arr.shape[0])
        return {"mean": zero_pred, "std": zero_pred,
                "p05": zero_pred, "p25": zero_pred,
                "p50": zero_pred, "p75": zero_pred, "p95": zero_pred,
                "n_bootstraps": len(all_preds), "n_failed": failed_iters,
                "device": device}

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
        "n_failed": failed_iters,
        "device": device,
    }
