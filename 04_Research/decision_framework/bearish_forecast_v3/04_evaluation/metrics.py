"""
metrics.py — CRPS / NLL / Pinball / LPS evaluation utilities

Used in Phase 5 across B1/B5/A/F/C components for distributional forecast eval.

Functions:
- crps_normal(mu, sigma, y) — closed-form
- crps_empirical(samples, y) — Gneiting-Raftery Eq 21 kernel form
- pinball_loss(quantile_preds, y, tau) — Koenker-Bassett 1978
- log_predictive_score(log_pdf_values) — LPS
- nll_per_obs(theta, y, dist) — per-obs NLL
"""
from __future__ import annotations
import math

import numpy as np
from scipy import stats as sp_stats


def crps_normal_np(mu: np.ndarray, sigma: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Closed-form Gaussian CRPS (Gneiting-Raftery 2007 §4).

    CRPS(N(μ, σ²), y) = σ [(y-μ)/σ (2Φ(z) - 1) + 2φ(z) - 1/√π]
    Returns: per-obs CRPS array.
    """
    eps = 1e-8
    z = (y - mu) / (sigma + eps)
    phi = sp_stats.norm.pdf(z)
    Phi = sp_stats.norm.cdf(z)
    return sigma * (z * (2 * Phi - 1) + 2 * phi - 1.0 / math.sqrt(math.pi))


def crps_empirical_np(samples: np.ndarray, y: np.ndarray) -> np.ndarray:
    """Empirical CRPS via Gneiting-Raftery Eq 21 kernel form.

    samples: (N, n_samples) — MC samples from forecast distribution
    y: (N,) observed values
    Returns: (N,) per-obs CRPS
    """
    # E |X - y|
    abs_xy = np.abs(samples - y[:, None]).mean(axis=1)
    # E |X - X'| via paired permutation
    n_s = samples.shape[1]
    perm = np.random.permutation(n_s)
    samples_p = samples[:, perm]
    abs_xx = np.abs(samples - samples_p).mean(axis=1)
    return abs_xy - 0.5 * abs_xx


def pinball_loss(q_pred: np.ndarray, y: np.ndarray, tau: float) -> np.ndarray:
    """Koenker-Bassett 1978 pinball loss for quantile prediction.

    L_tau(y, q) = (y - q)(tau - 1{y < q})
    Returns: per-obs pinball loss.
    """
    diff = y - q_pred
    return np.where(diff > 0, tau * diff, -(1 - tau) * diff)


def lps(log_pdf_values: np.ndarray) -> float:
    """Log Predictive Score = mean(log f(y)) — higher is better.

    Often reported as negative LPS = NLL.
    """
    return float(np.mean(log_pdf_values))


def crps_skill_score(crps_model: float, crps_baseline: float) -> float:
    """Skill score: 1 - crps_model / crps_baseline. Positive = model better than baseline.

    NOTE: Gneiting-Raftery 2007 §2.3 — many skill scores are improper. Use with caution.
    """
    return 1.0 - (crps_model / crps_baseline) if crps_baseline > 0 else float('nan')


def aggregate_metrics(
    crps_per_obs: np.ndarray,
    nll_per_obs: np.ndarray,
    pinball_per_obs_dict: dict | None = None,
) -> dict:
    """Aggregate metrics into a summary dict.

    Returns:
        {
            'crps_mean': float,
            'crps_std': float,
            'nll_mean': float,
            'nll_std': float,
            'pinball_<tau>_mean': float for each tau (if provided),
            'n_obs': int,
        }
    """
    result = {
        'crps_mean': float(np.mean(crps_per_obs)),
        'crps_std': float(np.std(crps_per_obs)),
        'nll_mean': float(np.mean(nll_per_obs)),
        'nll_std': float(np.std(nll_per_obs)),
        'n_obs': int(len(crps_per_obs)),
    }
    if pinball_per_obs_dict:
        for tau, vals in pinball_per_obs_dict.items():
            result[f'pinball_{tau}_mean'] = float(np.mean(vals))
    return result


def diebold_mariano(
    loss_a: np.ndarray,
    loss_b: np.ndarray,
    lag: int = 21,
) -> dict:
    """Diebold-Mariano 1995 test for forecast accuracy difference (HAC variance).

    Args:
        loss_a, loss_b: (N,) per-obs loss (e.g., CRPS, squared error)
        lag: Newey-West HAC lag (paper: ≥ horizon = 21)

    Returns:
        {'dm_stat': float, 'p_value': float, 'mean_diff': float}
    """
    d = loss_a - loss_b
    n = len(d)
    mean_d = d.mean()
    # Newey-West HAC variance with bartlett kernel
    var_d = np.var(d, ddof=0)
    for k in range(1, lag + 1):
        if k >= n:
            break
        gamma_k = np.mean((d[:-k] - mean_d) * (d[k:] - mean_d))
        w_k = 1.0 - k / (lag + 1)
        var_d += 2 * w_k * gamma_k
    var_d = max(var_d, 1e-12)
    se = math.sqrt(var_d / n)
    dm_stat = mean_d / se if se > 0 else float('nan')
    p_value = 2 * (1 - sp_stats.norm.cdf(abs(dm_stat))) if not math.isnan(dm_stat) else float('nan')
    return {'dm_stat': float(dm_stat), 'p_value': float(p_value), 'mean_diff': float(mean_d)}


__all__ = [
    'crps_normal_np',
    'crps_empirical_np',
    'pinball_loss',
    'lps',
    'crps_skill_score',
    'aggregate_metrics',
    'diebold_mariano',
]
