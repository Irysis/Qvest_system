"""
p3_hansen_skewt_bounded.py — P3: Hansen 1994 with bounded ν

P2 (p1_hansen_skewt.py) → P3 개선:
  ν unbounded (Normal limit 가능) → ν ∈ (2.5, 50) bounded

Why bounded ν:
- P2에서 일부 fold (안정 시기)에 ν → ∞ 발산 → Normal limit으로 수렴
- 이는 fat-tail 정보 상실 → PIT shape imperfect 원인 중 하나
- ν ∈ (2.5, 50)으로 강제 → 항상 finite kurtosis + Normal limit 회피

Reparameterization:
  ν = 2.5 + 47.5 / (1 + exp(-θ2))  ∈ (2.5, 50)

기타: P2와 동일 (Hansen 1994, closed-form CDF/quantile, L-BFGS-B CDF-matching fit).
"""
from __future__ import annotations

import numpy as np
from scipy import stats as sp_stats
from scipy import optimize as sp_opt
from scipy.special import gammaln


# Hansen constants (identical to P2)
def _hansen_abc(nu, lam):
    log_c = gammaln((nu + 1.0) / 2.0) - gammaln(nu / 2.0) - 0.5 * np.log(np.pi * (nu - 2.0))
    c = np.exp(log_c)
    a = 4.0 * lam * c * (nu - 2.0) / (nu - 1.0)
    b_sq = 1.0 + 3.0 * lam * lam - a * a
    b = np.sqrt(np.maximum(b_sq, 1e-12))
    return a, b, c


def hansen_cdf_std(z, nu, lam):
    z = np.atleast_1d(np.asarray(z, dtype=np.float64))
    a, b, _ = _hansen_abc(nu, lam)
    boundary_z = -a / b
    is_left = z < boundary_z
    u_left = (b * z + a) / (1.0 - lam)
    u_right = (b * z + a) / (1.0 + lam)
    scale = np.sqrt(nu / (nu - 2.0))
    T_left = sp_stats.t.cdf(u_left * scale, df=nu)
    T_right = sp_stats.t.cdf(u_right * scale, df=nu)
    F_left = (1.0 - lam) * T_left
    F_right = -lam + (1.0 + lam) * T_right
    return np.where(is_left, F_left, F_right)


def hansen_quantile_std(p, nu, lam):
    p = np.atleast_1d(np.asarray(p, dtype=np.float64))
    a, b, _ = _hansen_abc(nu, lam)
    boundary_p = (1.0 - lam) / 2.0
    is_left = p < boundary_p
    p_left = np.clip(p / (1.0 - lam), 1e-12, 1.0 - 1e-12)
    p_right = np.clip((p + lam) / (1.0 + lam), 1e-12, 1.0 - 1e-12)
    scale = np.sqrt(nu / (nu - 2.0))
    q_left_hansen = sp_stats.t.ppf(p_left, df=nu) / scale
    q_right_hansen = sp_stats.t.ppf(p_right, df=nu) / scale
    z_left = ((1.0 - lam) * q_left_hansen - a) / b
    z_right = ((1.0 + lam) * q_right_hansen - a) / b
    return np.where(is_left, z_left, z_right)


def hansen_cdf(x, mu, sigma, nu, lam):
    z = (np.asarray(x, dtype=np.float64) - mu) / sigma
    return hansen_cdf_std(z, nu, lam)


def hansen_quantile(p, mu, sigma, nu, lam):
    z = hansen_quantile_std(p, nu, lam)
    return mu + sigma * z


# ─── P3 bounded ν parameterization ──────────────────────────────────────────

NU_MIN = 2.5
NU_MAX = 50.0
NU_RANGE = NU_MAX - NU_MIN  # 47.5


def _unpack_bounded(theta):
    """Unpack with bounded ν ∈ (2.5, 50).

    μ free | σ = exp(θ1) > 0 | ν = 2.5 + 47.5 σ(θ2) | λ = 0.98 tanh(θ3) ∈ (-0.98, 0.98)
    """
    mu = theta[0]
    sigma = np.exp(theta[1])
    # sigmoid θ2 → ν ∈ (NU_MIN, NU_MAX)
    nu = NU_MIN + NU_RANGE / (1.0 + np.exp(-theta[2]))
    lam = 0.98 * np.tanh(theta[3])
    return mu, sigma, nu, lam


def _pack_bounded(mu, sigma, nu, lam):
    """Inverse pack — solve for θ2 such that ν = NU_MIN + NU_RANGE * σ(θ2)."""
    nu_clip = np.clip(nu, NU_MIN + 1e-3, NU_MAX - 1e-3)
    frac = (nu_clip - NU_MIN) / NU_RANGE  # ∈ (eps, 1-eps)
    theta2 = np.log(frac / (1.0 - frac))  # logit
    return np.array([
        mu,
        np.log(max(sigma, 1e-6)),
        theta2,
        np.arctanh(np.clip(lam / 0.98, -0.97, 0.97)),
    ])


def fit_hansen_to_quantiles(Q, taus, init=None, maxiter=100):
    """L-BFGS-B fit with bounded ν ∈ (2.5, 50)."""
    Q = np.asarray(Q, dtype=np.float64).flatten()
    taus = np.asarray(taus, dtype=np.float64).flatten()

    if init is None:
        mu0 = float(np.median(Q))
        sigma0 = float((np.quantile(Q, 0.84) - np.quantile(Q, 0.16)) / 2.0)
        sigma0 = max(sigma0, 0.1)
        init = (mu0, sigma0, 8.0, -0.10)

    def obj(theta):
        mu, sigma, nu, lam = _unpack_bounded(theta)
        try:
            F = hansen_cdf(Q, mu, sigma, nu, lam)
            return float(np.sum((F - taus) ** 2))
        except (ValueError, FloatingPointError):
            return 1e10

    x0 = _pack_bounded(*init)
    try:
        res = sp_opt.minimize(
            obj, x0, method='L-BFGS-B',
            options={'maxiter': maxiter, 'gtol': 1e-6, 'ftol': 1e-10},
        )
        return _unpack_bounded(res.x)
    except Exception:
        return init


def derive_metrics_per_obs(Q_matrix, taus, bear_thresholds=(-5.0, -7.0, -10.0)):
    """Per-obs Hansen fit with bounded ν, derive VaR/ES/bear probabilities."""
    N = Q_matrix.shape[0]
    mu = np.zeros(N)
    sigma = np.zeros(N)
    nu = np.zeros(N)
    lam = np.zeros(N)
    var_05 = np.zeros(N)
    var_01 = np.zeros(N)
    var_005 = np.zeros(N)
    var_001 = np.zeros(N)
    es_05 = np.zeros(N)
    p_neg = {k: np.zeros(N) for k in bear_thresholds}

    prev = None
    for i in range(N):
        Q_i = np.sort(Q_matrix[i])
        mu_i, sigma_i, nu_i, lam_i = fit_hansen_to_quantiles(Q_i, taus, init=prev)
        prev = (mu_i, sigma_i, nu_i, lam_i)
        mu[i], sigma[i], nu[i], lam[i] = mu_i, sigma_i, nu_i, lam_i

        ps = np.array([0.05, 0.01, 0.005, 0.001])
        qs = hansen_quantile(ps, mu_i, sigma_i, nu_i, lam_i)
        var_05[i], var_01[i], var_005[i], var_001[i] = qs

        u_mc = np.random.uniform(1e-6, 0.05, 400)
        es_05[i] = float(hansen_quantile(u_mc, mu_i, sigma_i, nu_i, lam_i).mean())

        for thr in bear_thresholds:
            p_neg[thr][i] = float(hansen_cdf(np.array([thr]), mu_i, sigma_i, nu_i, lam_i)[0])

    return {
        'mu': mu, 'sigma': sigma, 'nu': nu, 'lam': lam,
        'var_05': var_05, 'var_01': var_01, 'var_005': var_005, 'var_001': var_001,
        'es_05': es_05,
        'p_minus_5': p_neg[-5.0],
        'p_minus_7': p_neg[-7.0],
        'p_minus_10': p_neg[-10.0],
    }


def pit_per_obs(y, mu, sigma, nu, lam):
    N = len(y)
    pit = np.zeros(N)
    for i in range(N):
        pit[i] = float(hansen_cdf(np.array([y[i]]), mu[i], sigma[i], nu[i], lam[i])[0])
    return pit


__all__ = [
    'NU_MIN', 'NU_MAX',
    'hansen_cdf_std', 'hansen_quantile_std',
    'hansen_cdf', 'hansen_quantile',
    'fit_hansen_to_quantiles',
    'derive_metrics_per_obs', 'pit_per_obs',
]
