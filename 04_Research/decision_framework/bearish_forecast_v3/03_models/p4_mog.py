"""
p4_mog.py — Mixture Gaussian (MoG) distribution module for P4

도훈 mandate 2026-05-27 (P4-MoG paradigm shift):
- Hansen Skewed-t 22d horizon 구조적 실패 (200/200 calibration FAIL)
- Mixture Gaussian (2-3 component) 대체 — 정상 regime + 위기 regime 명시적 표현
- LASSO Quantile 11 quantile output → MoG fit (nonlinear least squares on quantile points)

Parameterization (2-component):
    f(y) = π · N(y | μ1, σ1²) + (1-π) · N(y | μ2, σ2²)

Identifiability: σ1 ≤ σ2 (component 1 = stable, 2 = stress).

Functions:
- mog_cdf(y, params) — closed-form mixture CDF
- mog_quantile(p, params, ...) — bisection inverse CDF
- mog_pit(y, params) — PIT value
- fit_mog_from_quantiles(Q_emp, taus, n_components=2) — fit per-obs
- derive_metrics_per_obs(Q_pred, taus, n_components) — VaR, ES, bear probs (P-vector parallel)
"""
from __future__ import annotations
import numpy as np
from scipy.optimize import minimize
from scipy.stats import norm


# ─── MoG 2-component primitives ────────────────────────────────────────────────
def mog2_cdf(y, pi, mu1, sigma1, mu2, sigma2):
    """2-component MoG CDF at y."""
    return pi * norm.cdf(y, mu1, sigma1) + (1 - pi) * norm.cdf(y, mu2, sigma2)


def mog2_pdf(y, pi, mu1, sigma1, mu2, sigma2):
    return pi * norm.pdf(y, mu1, sigma1) + (1 - pi) * norm.pdf(y, mu2, sigma2)


def mog2_quantile(p, pi, mu1, sigma1, mu2, sigma2, n_iter=25):
    """Bisection inverse CDF for MoG2. n_iter=25 → 1e-7 precision (sufficient)."""
    p = np.clip(p, 1e-9, 1 - 1e-9)
    sigma_max = max(sigma1, sigma2)
    mu_min, mu_max = min(mu1, mu2), max(mu1, mu2)
    lo = mu_min - 10 * sigma_max
    hi = mu_max + 10 * sigma_max
    for _ in range(n_iter):
        mid = 0.5 * (lo + hi)
        cdf_mid = mog2_cdf(mid, pi, mu1, sigma1, mu2, sigma2)
        if cdf_mid < p:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def mog2_es(alpha, pi, mu1, sigma1, mu2, sigma2):
    """Expected Shortfall E[Y | Y ≤ VaR_α] for MoG2."""
    var_alpha = mog2_quantile(alpha, pi, mu1, sigma1, mu2, sigma2)
    # ES = (1/α) ∫_{-∞}^{VaR} y f(y) dy
    # For Normal: ∫_{-∞}^{c} y φ((y-μ)/σ) dy = μ Φ((c-μ)/σ) - σ φ((c-μ)/σ)
    z1 = (var_alpha - mu1) / sigma1
    z2 = (var_alpha - mu2) / sigma2
    e1 = mu1 * norm.cdf(z1) - sigma1 * norm.pdf(z1)
    e2 = mu2 * norm.cdf(z2) - sigma2 * norm.pdf(z2)
    return (pi * e1 + (1 - pi) * e2) / alpha


# ─── 3-component MoG primitives (optional) ────────────────────────────────────
def mog3_cdf(y, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3):
    p3 = 1.0 - p1 - p2
    return (p1 * norm.cdf(y, mu1, sigma1)
            + p2 * norm.cdf(y, mu2, sigma2)
            + p3 * norm.cdf(y, mu3, sigma3))


def mog3_quantile(p, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3, n_iter=50):
    p = np.clip(p, 1e-9, 1 - 1e-9)
    sigma_max = max(sigma1, sigma2, sigma3)
    mus = [mu1, mu2, mu3]
    lo = min(mus) - 10 * sigma_max
    hi = max(mus) + 10 * sigma_max
    for _ in range(n_iter):
        mid = 0.5 * (lo + hi)
        cdf_mid = mog3_cdf(mid, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
        if cdf_mid < p:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


# ─── Fitting: 11 LASSO Quantile points → MoG params ───────────────────────────
def fit_mog2_quantiles(Q_emp: np.ndarray, taus: np.ndarray) -> dict:
    """Fit 2-component MoG to (taus, Q_emp) via fast LSQ.

    OPTIMIZED 2026-05-27:
    - π fixed at 0.5 (reduces 5D → 4D)
    - maxiter 100 → 20 (mostly converges in <10 iter)
    - ftol 1e-8 → 1e-5 (sufficient for calibration)
    - warm start from quantile statistics (median + IQR + tail spread)
    """
    median = float(np.interp(0.5, taus, Q_emp))
    q25 = float(np.interp(0.25, taus, Q_emp))
    q75 = float(np.interp(0.75, taus, Q_emp))
    q05 = float(np.interp(0.05, taus, Q_emp))
    q95 = float(np.interp(0.95, taus, Q_emp))
    iqr = q75 - q25
    tail_spread = q95 - q05
    sigma_iqr = max(iqr / 1.349, 0.05)        # normal IQR mapping
    sigma_tail = max(tail_spread / 3.29, 0.05) # normal 5-95% spread

    # Warm start: comp1 = stable (sigma_iqr), comp2 = tail-shifted (sigma_tail)
    # Asymmetry direction: if Q05 deviates more from median than Q95, lean comp2 to bear side
    left_dev = median - q05
    right_dev = q95 - median
    skew_sign = -1.0 if left_dev > right_dev else 1.0
    PI_FIXED = 0.5  # symmetric mixture — let mu1/mu2 carry asymmetry

    x0 = np.array([
        median + 0.5 * sigma_iqr * skew_sign,      # mu1 (away from tail)
        sigma_iqr,                                  # sigma1 (smaller, stable)
        median - 1.0 * sigma_tail * skew_sign,     # mu2 (toward tail)
        max(sigma_tail, sigma_iqr * 1.2),          # sigma2 (larger, tail)
    ])

    def loss4(params):
        mu1, sigma1, mu2, sigma2 = params
        # mog2_quantile call uses pi=PI_FIXED
        Q_pred = np.array([mog2_quantile(t, PI_FIXED, mu1, sigma1, mu2, sigma2)
                            for t in taus])
        return float(np.sum((Q_pred - Q_emp) ** 2))

    bounds = [
        (median - 10 * sigma_tail, median + 10 * sigma_tail),  # mu1
        (0.05, 5 * sigma_iqr),                                  # sigma1
        (median - 10 * sigma_tail, median + 10 * sigma_tail),  # mu2
        (0.05, 10 * sigma_tail),                                # sigma2
    ]

    try:
        result = minimize(loss4, x0, method='L-BFGS-B', bounds=bounds,
                          options={'maxiter': 20, 'ftol': 1e-5})
        mu1, sigma1, mu2, sigma2 = result.x
        pi = PI_FIXED
        # identifiability: σ1 ≤ σ2 (comp 1 = stable)
        if sigma1 > sigma2:
            pi, mu1, sigma1, mu2, sigma2 = 1 - pi, mu2, sigma2, mu1, sigma1
        return {
            'pi': float(pi),
            'mu1': float(mu1), 'sigma1': float(sigma1),
            'mu2': float(mu2), 'sigma2': float(sigma2),
            'fit_status': 'OK' if result.success else 'WARN',
            'fit_loss': float(result.fun),
        }
    except Exception as e:
        return {
            'pi': 0.5, 'mu1': median, 'sigma1': sigma_iqr,
            'mu2': median, 'sigma2': sigma_iqr,
            'fit_status': f'FAIL: {e}', 'fit_loss': float('inf'),
        }


def fit_mog3_quantiles(Q_emp: np.ndarray, taus: np.ndarray) -> dict:
    """Fit 3-component MoG."""
    median = float(np.interp(0.5, taus, Q_emp))
    iqr = float(np.interp(0.75, taus, Q_emp) - np.interp(0.25, taus, Q_emp))
    sigma_init = max(iqr / 1.349, 0.05)

    # 3-component init: positive regime + neutral + negative regime
    x0 = np.array([
        0.25,                         # p1 (positive)
        0.50,                         # p2 (neutral)
        median + 1.5 * sigma_init,    # mu1
        0.8 * sigma_init,             # sigma1
        median,                       # mu2
        sigma_init,                   # sigma2
        median - 1.5 * sigma_init,    # mu3
        1.5 * sigma_init,             # sigma3
    ])

    def loss(params):
        p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3 = params
        if p1 + p2 > 0.99: return 1e9
        Q_pred = np.array([mog3_quantile(t, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
                            for t in taus])
        return float(np.sum((Q_pred - Q_emp) ** 2))

    bounds = [
        (0.05, 0.6), (0.05, 0.6),  # p1, p2 (sum < 0.99 → p3 ≥ 0.01)
        (median - 10 * sigma_init, median + 10 * sigma_init),
        (0.05 * sigma_init, 5 * sigma_init),
        (median - 10 * sigma_init, median + 10 * sigma_init),
        (0.05 * sigma_init, 5 * sigma_init),
        (median - 10 * sigma_init, median + 10 * sigma_init),
        (0.05 * sigma_init, 10 * sigma_init),
    ]

    try:
        result = minimize(loss, x0, method='L-BFGS-B', bounds=bounds,
                          options={'maxiter': 150, 'ftol': 1e-8})
        p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3 = result.x
        return {
            'p1': float(p1), 'p2': float(p2), 'p3': float(1 - p1 - p2),
            'mu1': float(mu1), 'sigma1': float(sigma1),
            'mu2': float(mu2), 'sigma2': float(sigma2),
            'mu3': float(mu3), 'sigma3': float(sigma3),
            'fit_status': 'OK' if result.success else 'WARN',
            'fit_loss': float(result.fun),
        }
    except Exception as e:
        return {
            'p1': 0.33, 'p2': 0.34, 'p3': 0.33,
            'mu1': median, 'sigma1': sigma_init,
            'mu2': median, 'sigma2': sigma_init,
            'mu3': median, 'sigma3': sigma_init,
            'fit_status': f'FAIL: {e}', 'fit_loss': float('inf'),
        }


# ─── Per-observation derivation ───────────────────────────────────────────────
def derive_metrics_per_obs(Q_pred: np.ndarray, taus: np.ndarray, n_components: int = 2) -> dict:
    """Per-row MoG fit + VaR / ES / bear probs.

    Args:
        Q_pred: (N, n_taus) LASSO Quantile predictions
        taus: (n_taus,) tau levels
        n_components: 2 or 3

    Returns:
        dict with arrays:
        - mu (composite mean), sigma (composite std), mog_params (per-row params)
        - var_05, var_01, var_005, var_001 (negative numbers)
        - es_05
        - p_minus_5, p_minus_7, p_minus_10 (bear probabilities)
    """
    N = Q_pred.shape[0]
    mu_arr = np.zeros(N)
    sigma_arr = np.zeros(N)
    var_05 = np.zeros(N)
    var_01 = np.zeros(N)
    var_005 = np.zeros(N)
    var_001 = np.zeros(N)
    es_05 = np.zeros(N)
    p_minus_5 = np.zeros(N)
    p_minus_7 = np.zeros(N)
    p_minus_10 = np.zeros(N)
    # Extra: pi (component weight) for diagnostic — store as separate arrays
    pi_arr = np.zeros(N) if n_components == 2 else None
    sigma1_arr = np.zeros(N) if n_components == 2 else None
    sigma2_arr = np.zeros(N) if n_components == 2 else None
    mu1_arr = np.zeros(N) if n_components == 2 else None
    mu2_arr = np.zeros(N) if n_components == 2 else None
    fit_status_arr = []

    for i in range(N):
        Q_i = Q_pred[i]
        if n_components == 2:
            params = fit_mog2_quantiles(Q_i, taus)
            pi, mu1, sigma1, mu2, sigma2 = (params['pi'], params['mu1'], params['sigma1'],
                                              params['mu2'], params['sigma2'])
            mu_arr[i] = pi * mu1 + (1 - pi) * mu2
            # composite variance: var = E[Var] + Var[E] = π σ1² + (1-π) σ2² + π(μ1-μ)² + (1-π)(μ2-μ)²
            var_total = (pi * sigma1**2 + (1 - pi) * sigma2**2
                         + pi * (mu1 - mu_arr[i])**2 + (1 - pi) * (mu2 - mu_arr[i])**2)
            sigma_arr[i] = np.sqrt(var_total)
            pi_arr[i] = pi
            mu1_arr[i] = mu1; sigma1_arr[i] = sigma1
            mu2_arr[i] = mu2; sigma2_arr[i] = sigma2
            var_05[i] = mog2_quantile(0.05, pi, mu1, sigma1, mu2, sigma2)
            var_01[i] = mog2_quantile(0.01, pi, mu1, sigma1, mu2, sigma2)
            var_005[i] = mog2_quantile(0.005, pi, mu1, sigma1, mu2, sigma2)
            var_001[i] = mog2_quantile(0.001, pi, mu1, sigma1, mu2, sigma2)
            es_05[i] = mog2_es(0.05, pi, mu1, sigma1, mu2, sigma2)
            # Note: P(-5%) = CDF(-5%), but y in % scale → threshold = -5.0
            p_minus_5[i] = mog2_cdf(-5.0, pi, mu1, sigma1, mu2, sigma2)
            p_minus_7[i] = mog2_cdf(-7.0, pi, mu1, sigma1, mu2, sigma2)
            p_minus_10[i] = mog2_cdf(-10.0, pi, mu1, sigma1, mu2, sigma2)
        elif n_components == 3:
            params = fit_mog3_quantiles(Q_i, taus)
            p1, p2, p3 = params['p1'], params['p2'], params['p3']
            mu1, sigma1 = params['mu1'], params['sigma1']
            mu2, sigma2 = params['mu2'], params['sigma2']
            mu3, sigma3 = params['mu3'], params['sigma3']
            mu_arr[i] = p1 * mu1 + p2 * mu2 + p3 * mu3
            var_total = (p1 * sigma1**2 + p2 * sigma2**2 + p3 * sigma3**2
                         + p1 * (mu1 - mu_arr[i])**2 + p2 * (mu2 - mu_arr[i])**2
                         + p3 * (mu3 - mu_arr[i])**2)
            sigma_arr[i] = np.sqrt(var_total)
            var_05[i] = mog3_quantile(0.05, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
            var_01[i] = mog3_quantile(0.01, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
            var_005[i] = mog3_quantile(0.005, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
            var_001[i] = mog3_quantile(0.001, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
            # ES not implemented for 3-comp (acceptable fallback: mog2 es of dominant 2 comps);
            # use empirical from quantiles instead
            es_05[i] = float(np.mean(Q_i[taus <= 0.05])) if (taus <= 0.05).sum() > 0 else var_05[i]
            p_minus_5[i] = mog3_cdf(-5.0, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
            p_minus_7[i] = mog3_cdf(-7.0, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
            p_minus_10[i] = mog3_cdf(-10.0, p1, p2, mu1, sigma1, mu2, sigma2, mu3, sigma3)
        else:
            raise ValueError(f"n_components must be 2 or 3, got {n_components}")
        fit_status_arr.append(params['fit_status'])

    out = {
        'mu': mu_arr,
        'sigma': sigma_arr,
        'var_05': var_05, 'var_01': var_01, 'var_005': var_005, 'var_001': var_001,
        'es_05': es_05,
        'p_minus_5': p_minus_5,
        'p_minus_7': p_minus_7,
        'p_minus_10': p_minus_10,
    }
    if n_components == 2:
        out.update({
            'pi': pi_arr,
            'mu1': mu1_arr, 'sigma1': sigma1_arr,
            'mu2': mu2_arr, 'sigma2': sigma2_arr,
        })
    return out


def pit_per_obs(y: np.ndarray, mog_params_arr: dict, n_components: int = 2) -> np.ndarray:
    """PIT per observation using fitted MoG params.

    mog_params_arr: dict of per-row arrays from derive_metrics_per_obs.
    """
    N = len(y)
    pit = np.zeros(N)
    if n_components == 2:
        for i in range(N):
            pit[i] = mog2_cdf(y[i],
                               mog_params_arr['pi'][i],
                               mog_params_arr['mu1'][i],
                               mog_params_arr['sigma1'][i],
                               mog_params_arr['mu2'][i],
                               mog_params_arr['sigma2'][i])
    else:
        raise NotImplementedError("3-comp PIT requires per-row 3-comp params stored")
    return pit


def sample_from_mog2(pi, mu1, sigma1, mu2, sigma2, n_samples=300, rng=None):
    """Sample from 2-component MoG (for empirical CRPS computation)."""
    rng = rng or np.random.default_rng()
    component = rng.uniform(size=n_samples) < pi
    samples = np.where(
        component,
        rng.normal(mu1, sigma1, size=n_samples),
        rng.normal(mu2, sigma2, size=n_samples),
    )
    return samples


# ─── Module load ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    # Self-test: fit MoG to synthetic Hansen Skewed-t like quantiles
    print("[p4_mog] Self-test...")
    taus = np.array([0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99])
    # Synthetic skew-normal mixture
    Q_test = np.array([-8.0, -6.5, -5.0, -3.5, -1.2, 0.3, 1.8, 3.5, 4.8, 6.0, 7.5])
    fit = fit_mog2_quantiles(Q_test, taus)
    print(f"  Fit: pi={fit['pi']:.3f}  mu1={fit['mu1']:+.3f}  sigma1={fit['sigma1']:.3f}  "
          f"mu2={fit['mu2']:+.3f}  sigma2={fit['sigma2']:.3f}  status={fit['fit_status']}")
    print(f"  VaR 5%: {mog2_quantile(0.05, **{k: fit[k] for k in ['pi','mu1','sigma1','mu2','sigma2']}):+.3f}")
    print(f"  PIT(y=0): {mog2_cdf(0.0, **{k: fit[k] for k in ['pi','mu1','sigma1','mu2','sigma2']}):.4f}")
