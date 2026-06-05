"""
p4_ecdf.py — Empirical CDF distribution module for P4 (h=21)

도훈 mandate 2026-05-27 (P4-ECDF paradigm, MoG fit cost 분석 후):
- Hansen Skewed-t 22d FAIL (ν degenerate)
- MoG fit cost 26h/trial (비현실적)
- → 분포 가족 가정 자체 폐기, Empirical CDF (ECDF) paradigm

Approach:
- LASSO Quantile 11 quantile points → linear interp empirical CDF
- PIT = interp(y_actual, Q_pred, taus)  → calibration 거의 자동
- VaR = Q_pred[index of target tau] 직접
- ES = mean of Q_pred[taus <= target_tau]
- μ/σ/λ/ν 4-param summary = quantile statistics에서 derive (Bowley skew, tail spread ratio)
- fit 시간 = 0

Calibration:
- LASSO Quantile model 자체가 calibrated quantile 추정 → PIT 보장
- Hansen / MoG처럼 분포 fit이 calibration 깨뜨릴 risk 없음

Functions:
- derive_metrics_per_obs(Q_pred, taus): VaR / ES / 4-param summary
- pit_per_obs(y, Q_pred, taus): PIT values
- bear_probability(threshold, Q_pred, taus): P(y < threshold) via interp
"""
from __future__ import annotations
import numpy as np


def ecdf_pit_per_obs(y: np.ndarray, Q_pred: np.ndarray, taus: np.ndarray) -> np.ndarray:
    """PIT via linear interp of (Q_pred, taus) at y.

    Args:
        y: (N,) realized values
        Q_pred: (N, n_taus) predicted quantiles per obs
        taus: (n_taus,) tau levels (sorted ascending)

    Returns:
        (N,) PIT values in (0, 1).
    """
    N = len(y)
    pit = np.zeros(N)
    for i in range(N):
        Q_i = Q_pred[i]
        # Ensure monotonicity (fix_crossing should have been applied upstream)
        Q_sorted = np.sort(Q_i)
        if y[i] <= Q_sorted[0]:
            # Below smallest quantile — linear extrapolate to tau=0
            slope = taus[0] / max(Q_sorted[0] - (Q_sorted[1] - Q_sorted[0]) * 5, -1e9)
            pit[i] = max(0.001, taus[0] * (1 - (Q_sorted[0] - y[i]) / max(Q_sorted[1] - Q_sorted[0], 1e-6)))
        elif y[i] >= Q_sorted[-1]:
            pit[i] = min(0.999, taus[-1] + (1 - taus[-1]) * (y[i] - Q_sorted[-1]) /
                          max(Q_sorted[-1] - Q_sorted[-2], 1e-6))
        else:
            pit[i] = float(np.interp(y[i], Q_sorted, taus))
    return np.clip(pit, 0.001, 0.999)


def bear_probability(threshold: float, Q_pred_row: np.ndarray, taus: np.ndarray) -> float:
    """P(y < threshold) via inverse interp. Returns probability."""
    Q_sorted = np.sort(Q_pred_row)
    if threshold <= Q_sorted[0]:
        # below smallest quantile — extrapolate
        if Q_sorted[1] > Q_sorted[0]:
            return max(0.0, taus[0] - taus[0] * (Q_sorted[0] - threshold) /
                            max(Q_sorted[1] - Q_sorted[0], 1e-6))
        return 0.0
    if threshold >= Q_sorted[-1]:
        return 1.0
    return float(np.interp(threshold, Q_sorted, taus))


def derive_metrics_per_obs(Q_pred: np.ndarray, taus: np.ndarray) -> dict:
    """Per-row ECDF-based metrics.

    Returns dict with arrays:
    - mu (median proxy), sigma (IQR-based std proxy)
    - lam (Bowley skewness): (Q95 - Q50 - (Q50 - Q05)) / (Q95 - Q05)
    - nu (tail spread ratio, lower = fatter tail):
        (Q75 - Q25) / (Q95 - Q05), normalized so normal=0.412
        Inverse → higher = fatter tail
    - var_05, var_01, var_005, var_001 (interpolated quantiles)
    - es_05 (mean of bottom 5% tail)
    - p_minus_5, p_minus_7, p_minus_10 (bear probabilities via inverse interp)
    """
    N = Q_pred.shape[0]
    taus_np = np.asarray(taus)

    # Sort each row's quantiles (ensure monotone)
    Q_sorted = np.sort(Q_pred, axis=1)

    # ── Interpolated key quantiles ────────────────────────────────────────────
    def interp_tau(tau_target):
        return np.array([float(np.interp(tau_target, taus_np, Q_sorted[i])) for i in range(N)])

    q05 = interp_tau(0.05)
    q25 = interp_tau(0.25)
    q50 = interp_tau(0.50)
    q75 = interp_tau(0.75)
    q95 = interp_tau(0.95)
    q005 = interp_tau(0.005)
    q01 = interp_tau(0.01)
    q001 = interp_tau(0.001)

    # ── 4-param summary ───────────────────────────────────────────────────────
    mu = q50  # median proxy
    sigma_iqr = (q75 - q25) / 1.349   # IQR → std (normal mapping)
    # Bowley skewness (Galton-Bowley 1881): -1 (full left skew) ~ +1 (right skew)
    eps = 1e-8
    lam = ((q95 - q50) - (q50 - q05)) / (q95 - q05 + eps)
    # Tail spread ratio (Crow-Siddiqui or similar):
    # normal: (Q75 - Q25) / (Q95 - Q05) ≈ 0.413
    # fat-tail: ratio < 0.413 → 1/ratio used as nu proxy
    spread_ratio = (q75 - q25) / (q95 - q05 + eps)
    # nu proxy: lower spread_ratio = fatter tail = lower nu (Hansen-like)
    # normal ν=∞ → spread_ratio=0.413
    # fat-tail (ν=3) → spread_ratio ≈ 0.27
    # Empirical mapping: nu_proxy = 0.413 / spread_ratio (>1 = normal/thin, <1 = fat)
    # Convert to Hansen-like scale: nu ≈ 2 / (0.413 - spread_ratio + 0.1) ← rough heuristic
    # Safer: just report spread_ratio directly
    nu_proxy = np.where(spread_ratio > 0.413,
                         50.0,  # normal-ish
                         3.0 + 100.0 * (spread_ratio - 0.27))  # interp 3~50 for fat
    nu_proxy = np.clip(nu_proxy, 2.0, 1000.0)

    # ── VaR / ES ──────────────────────────────────────────────────────────────
    # ES_05: mean of all quantiles ≤ tau_0.05 (empirical tail mean)
    es_05 = np.zeros(N)
    for i in range(N):
        tail_mask = taus_np <= 0.05
        if tail_mask.sum() > 0:
            es_05[i] = Q_sorted[i, tail_mask].mean()
        else:
            es_05[i] = q05[i]

    # ── Bear probabilities ────────────────────────────────────────────────────
    p_minus_5 = np.array([bear_probability(-5.0, Q_sorted[i], taus_np) for i in range(N)])
    p_minus_7 = np.array([bear_probability(-7.0, Q_sorted[i], taus_np) for i in range(N)])
    p_minus_10 = np.array([bear_probability(-10.0, Q_sorted[i], taus_np) for i in range(N)])

    return {
        'mu': mu,
        'sigma': sigma_iqr,
        'lam': lam,
        'nu': nu_proxy,
        'var_05': q05, 'var_01': q01, 'var_005': q005, 'var_001': q001,
        'es_05': es_05,
        'p_minus_5': p_minus_5,
        'p_minus_7': p_minus_7,
        'p_minus_10': p_minus_10,
        'q25': q25, 'q75': q75, 'q95': q95,
    }


def sample_from_ecdf(Q_pred_row: np.ndarray, taus: np.ndarray, n_samples=300, rng=None):
    """Sample from empirical CDF via inverse transform."""
    rng = rng or np.random.default_rng()
    u = rng.uniform(0.001, 0.999, n_samples)
    Q_sorted = np.sort(Q_pred_row)
    samples = np.interp(u, taus, Q_sorted)
    return samples


# ─── Self test ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import time
    taus = np.array([0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99])
    np.random.seed(42)
    Q_test_batch = np.array([
        np.sort(np.linspace(-6, 6, 11) + np.random.randn(11) * 0.5)
        for _ in range(100)
    ])

    t0 = time.time()
    metrics = derive_metrics_per_obs(Q_test_batch, taus)
    t1 = time.time()
    per_obs_ms = (t1 - t0) / 100 * 1000
    print(f"derive_metrics_per_obs: {per_obs_ms:.3f} ms/row")
    print(f"For 5993 rows × 12 fold = 72k: ~{per_obs_ms * 72000 / 1000:.1f} sec/trial")
    print(f"For 200 trials: ~{per_obs_ms * 72000 * 200 / 1000 / 60:.1f} min")

    y_test = np.random.randn(100) * 2
    t0 = time.time()
    pit = ecdf_pit_per_obs(y_test, Q_test_batch, taus)
    t1 = time.time()
    print(f"\necdf_pit: {(t1-t0)/100*1000:.3f} ms/row")
    print(f"  PIT[:5]: {pit[:5]}")
    print(f"  μ[:3]: {metrics['mu'][:3]}")
    print(f"  σ[:3]: {metrics['sigma'][:3]}")
    print(f"  λ[:3]: {metrics['lam'][:3]}")
    print(f"  ν[:3]: {metrics['nu'][:3]}")
    print(f"  VaR_05[:3]: {metrics['var_05'][:3]}")
