"""
calibration.py — PIT histogram + reliability + chi-square calibration tests

Reference:
- Rosenblatt 1952 — Probability Integral Transform
- Diebold-Gunther-Tay 1998 — PIT calibration
- Gneiting-Balabdaoui-Raftery 2007 — reliability diagram + calibration

Functions:
- pit_chi_square(pit_values, n_bins=10) — uniform GOF test
- pit_ks_test(pit_values) — Kolmogorov-Smirnov vs U(0,1)
- pit_berkowitz(pit_values) — Berkowitz 2001 LR test (transformed normal)
- reliability_data(predicted_probs, realized_binary, n_bins=10) — for plotting
- expected_calibration_error(predicted_probs, realized, n_bins=10)
"""
from __future__ import annotations
import math

import numpy as np
from scipy import stats as sp_stats


def pit_chi_square(pit_values: np.ndarray, n_bins: int = 10) -> dict:
    """Chi-square goodness of fit test for PIT uniformity.

    H_0: PIT ~ U(0, 1)
    """
    n = len(pit_values)
    if n == 0:
        return {'test_stat': float('nan'), 'p_value': float('nan'), 'pass_at_005': False, 'n_bins': n_bins}
    counts, _ = np.histogram(pit_values, bins=n_bins, range=(0, 1))
    expected = n / n_bins
    chi2_stat = ((counts - expected) ** 2 / expected).sum()
    df = n_bins - 1
    p_value = 1 - sp_stats.chi2.cdf(chi2_stat, df=df)
    return {
        'test_stat': float(chi2_stat),
        'p_value': float(p_value),
        'pass_at_005': p_value > 0.05,
        'n_bins': n_bins,
        'observed_counts': counts.tolist(),
        'expected_per_bin': float(expected),
    }


def pit_ks_test(pit_values: np.ndarray) -> dict:
    """Kolmogorov-Smirnov test against U(0, 1)."""
    n = len(pit_values)
    if n == 0:
        return {'test_stat': float('nan'), 'p_value': float('nan'), 'pass_at_005': False}
    ks_stat, p_value = sp_stats.kstest(pit_values, 'uniform')
    return {
        'test_stat': float(ks_stat),
        'p_value': float(p_value),
        'pass_at_005': p_value > 0.05,
        'n_obs': n,
    }


def pit_berkowitz(pit_values: np.ndarray) -> dict:
    """Berkowitz 2001 LR test — transform PIT to z via Φ⁻¹, test z ~ N(0, 1).

    Often more powerful than chi-square for tail mis-specification.
    """
    eps = 1e-6
    pit_clipped = np.clip(pit_values, eps, 1 - eps)
    z = sp_stats.norm.ppf(pit_clipped)
    # Fit z to AR(1) with mean and variance (unrestricted)
    # Test H_0: mean=0, var=1, no AR
    n = len(z)
    if n < 30:
        return {'test_stat': float('nan'), 'p_value': float('nan'), 'pass_at_005': False, 'note': 'small sample'}
    mu_hat = z.mean()
    sigma2_hat = z.var(ddof=1)
    # Restricted log-lik
    log_lik_null = -0.5 * n * math.log(2 * math.pi) - 0.5 * np.sum(z ** 2)
    # Unrestricted (with mu, sigma²)
    log_lik_alt = -0.5 * n * math.log(2 * math.pi) - 0.5 * n * math.log(sigma2_hat) \
                  - 0.5 * np.sum((z - mu_hat) ** 2) / sigma2_hat
    lr_stat = -2 * (log_lik_null - log_lik_alt)
    p_value = 1 - sp_stats.chi2.cdf(lr_stat, df=2)
    return {
        'test_stat': float(lr_stat),
        'p_value': float(p_value),
        'pass_at_005': p_value > 0.05,
        'mu_hat': float(mu_hat),
        'sigma2_hat': float(sigma2_hat),
    }


def reliability_data(
    predicted_probs: np.ndarray,
    realized_binary: np.ndarray,
    n_bins: int = 10,
) -> dict:
    """Build reliability diagram data (Gneiting-Balabdaoui-Raftery 2007).

    Args:
        predicted_probs: (N,) forecasted probability of event (e.g., P(r ≤ -5%))
        realized_binary: (N,) realized binary outcome
        n_bins: bin count

    Returns:
        {'bin_centers': [...], 'observed_freq': [...], 'avg_predicted': [...], 'counts': [...]}
    """
    bins = np.linspace(0, 1, n_bins + 1)
    bin_idx = np.digitize(predicted_probs, bins) - 1
    bin_idx = np.clip(bin_idx, 0, n_bins - 1)
    obs_freq = np.zeros(n_bins)
    avg_pred = np.zeros(n_bins)
    counts = np.zeros(n_bins, dtype=int)
    for i in range(n_bins):
        mask = bin_idx == i
        if mask.sum() > 0:
            obs_freq[i] = realized_binary[mask].mean()
            avg_pred[i] = predicted_probs[mask].mean()
            counts[i] = mask.sum()
    centers = (bins[:-1] + bins[1:]) / 2
    return {
        'bin_centers': centers.tolist(),
        'observed_freq': obs_freq.tolist(),
        'avg_predicted': avg_pred.tolist(),
        'counts': counts.tolist(),
    }


def expected_calibration_error(
    predicted_probs: np.ndarray,
    realized_binary: np.ndarray,
    n_bins: int = 10,
) -> float:
    """ECE = Σ_b (n_b / N) |acc_b - conf_b|"""
    rel = reliability_data(predicted_probs, realized_binary, n_bins)
    n_total = sum(rel['counts'])
    if n_total == 0:
        return float('nan')
    ece = 0.0
    for cnt, obs, pred in zip(rel['counts'], rel['observed_freq'], rel['avg_predicted']):
        if cnt > 0:
            ece += (cnt / n_total) * abs(obs - pred)
    return ece


__all__ = [
    'pit_chi_square',
    'pit_ks_test',
    'pit_berkowitz',
    'reliability_data',
    'expected_calibration_error',
]
