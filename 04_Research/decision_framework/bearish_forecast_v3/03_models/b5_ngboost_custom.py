"""
b5_ngboost_custom.py — NGBoost custom Distribution class for skewed Student-t

Reference:
- Duan et al 2020 ICML "NGBoost" arxiv 1910.03225v4
- Fernandez-Steel 1998 JASA 93(441):359-371 "On Bayesian modeling of fat tails and skewness"

ngboost.distns.Distribution interface requirements (v0.5.10):
- log_pdf(y) — per-obs log likelihood
- sample(n) — Monte Carlo samples
- fit(y) — marginal MLE for initialization
- _params2dist() — parameter unpacking
- d_score / metric / fisher info for natural gradient

This is intentionally a lightweight wrapper. For Stage 1 B5 baseline, the built-in
Normal/Laplace/Exponential distributions suffice. Skewed-t custom is needed for
Phase 5a-2.B Stage 2 to match B1 skewed-t paradigm.
"""
from __future__ import annotations
import numpy as np
import scipy.stats
import scipy.special
from typing import Any

from ngboost.distns.distn import RegressionDistn
from ngboost.scores import LogScore


# ─── Parameter clipping ────────────────────────────────────────────────────
EPS = 1e-8
SIGMA_MIN = 1e-4
SIGMA_MAX = 100.0
NU_MIN = 2.5
NU_MAX = 60.0
XI_MIN = 0.1
XI_MAX = 10.0


def _softplus(x):
    """Numerically stable softplus."""
    return np.where(x > 30, x, np.log1p(np.exp(np.clip(x, -50, 30))))


def _softplus_inv(y, eps=1e-6):
    """Inverse softplus for initialization."""
    return np.log(np.expm1(np.maximum(y, eps)))


# ─── Skewed Student-t (Fernandez-Steel 1998) ───────────────────────────────
class SkewedTLogScore(LogScore):
    """Log-likelihood (negative for boost minimization).

    f_sst(y; μ, σ, ν, ξ) = (2 / (ξ + 1/ξ)) · f_t(z * ξ^(-sign(z)); ν) / σ
    where z = (y - μ) / σ
    """

    def score(self, Y):
        """Per-obs log likelihood (returned as positive value, ngboost handles sign)."""
        mu, sigma, nu, xi = self.dist.params_unpacked()
        z = (Y - mu) / sigma
        sign_z = np.sign(z + EPS)
        z_scaled = z * np.power(xi, -sign_z)
        # log t density on z_scaled (standardized t)
        log_norm = (
            scipy.special.gammaln((nu + 1) / 2)
            - scipy.special.gammaln(nu / 2)
            - 0.5 * np.log(nu * np.pi)
        )
        log_kernel = -0.5 * (nu + 1) * np.log1p(z_scaled ** 2 / nu)
        log_f_t = log_norm + log_kernel
        log_fs_norm = np.log(2.0) - np.log(xi + 1.0 / xi) - np.log(sigma)
        log_pdf = log_f_t + log_fs_norm
        # Return negative log score for NGBoost (lower is better)
        return -log_pdf

    def d_score(self, Y):
        """Gradient w.r.t. parameter vector (raw, before softplus etc).

        For Stage 1 simplicity, return numerical gradient.
        For Stage 2 production, replace with analytical (paper Section 3.3).
        """
        n = len(Y)
        p = 4
        grad = np.zeros((n, p))
        eps = 1e-5
        params0 = self.dist._params.copy()
        for j in range(p):
            params_plus = params0.copy()
            params_plus[j] += eps
            self.dist._params = params_plus
            self.dist._refresh_params()
            s_plus = self.score(Y)
            params_minus = params0.copy()
            params_minus[j] -= eps
            self.dist._params = params_minus
            self.dist._refresh_params()
            s_minus = self.score(Y)
            grad[:, j] = (s_plus - s_minus) / (2 * eps)
        self.dist._params = params0
        self.dist._refresh_params()
        return grad

    def metric(self):
        """Fisher information ≈ I = E[g g^T]. For natural gradient.

        Use sample-based estimate (paper Section 3.3): I ≈ (1/n) Σ g_i g_i^T.
        Returns per-obs metric (N, p, p).
        """
        # Use identity as fallback — proper Fisher requires analytical derivation
        # which is paper Section 3.3 (skip for Stage 1 MVP).
        p = 4
        n = self.dist.n_samples if hasattr(self.dist, 'n_samples') else 1
        I = np.eye(p)[np.newaxis, :, :].repeat(n, axis=0)
        return I


class SkewedT(RegressionDistn):
    """NGBoost-compatible skewed Student-t distribution.

    Raw parameters (ngboost optimizer space):
        params[:, 0] = mu (location)
        params[:, 1] = log_sigma  (sigma = exp + clip)
        params[:, 2] = nu_raw     (nu = softplus + offset)
        params[:, 3] = xi_raw     (xi = softplus + offset)

    Transformations applied in params_unpacked().
    """
    n_params = 4
    scores = [SkewedTLogScore]

    def __init__(self, params):
        """params: (N, 4) raw parameters from ngboost."""
        self._params = np.asarray(params, dtype=np.float64)
        self.n_samples = self._params.shape[0]
        self._refresh_params()

    def _refresh_params(self):
        """Apply transformations: sigma = exp(clip), nu = softplus + 2.5, xi = softplus + 0.1."""
        self.mu = self._params[:, 0]
        log_sigma = np.clip(self._params[:, 1], -10, 6)
        self.sigma = np.clip(np.exp(log_sigma), SIGMA_MIN, SIGMA_MAX)
        nu_raw = _softplus(self._params[:, 2])
        self.nu = np.clip(nu_raw + NU_MIN, NU_MIN, NU_MAX)
        xi_raw = _softplus(self._params[:, 3])
        self.xi = np.clip(xi_raw + XI_MIN, XI_MIN, XI_MAX)

    def params_unpacked(self):
        return self.mu, self.sigma, self.nu, self.xi

    @staticmethod
    def fit(Y):
        """Marginal MLE for initialization. Use sample statistics."""
        Y = np.asarray(Y)
        mu_init = float(np.mean(Y))
        sigma_init = float(np.std(Y) + 1e-3)
        # log_sigma raw
        log_sigma_raw = float(np.log(sigma_init))
        # nu_raw: target nu ≈ 8 (moderate tail), inverse softplus
        nu_init = 5.0
        nu_raw_init = float(_softplus_inv(nu_init - NU_MIN))
        # xi_raw: target xi=1 (symmetric), inverse softplus
        xi_init = 0.9
        xi_raw_init = float(_softplus_inv(xi_init - XI_MIN))
        return np.array([mu_init, log_sigma_raw, nu_raw_init, xi_raw_init])

    def sample(self, n_samples: int = 1000) -> np.ndarray:
        """Draw samples (N_obs, n_samples) — uses Fernandez-Steel mixture.

        Standard FS sample:
        1. Draw z ~ t_nu
        2. Mixture sign via Bernoulli(xi/(xi + 1/xi))
        """
        N = self.n_samples
        samples = np.zeros((N, n_samples))
        for i in range(N):
            z = scipy.stats.t.rvs(df=self.nu[i], size=n_samples)
            abs_z = np.abs(z)
            p_right = self.xi[i] / (self.xi[i] + 1.0 / self.xi[i])
            u = np.random.rand(n_samples)
            is_right = u < p_right
            z_star = np.where(is_right, abs_z / self.xi[i], -abs_z * self.xi[i])
            samples[i] = self.mu[i] + self.sigma[i] * z_star
        return samples

    def logpdf(self, Y):
        """Per-obs log pdf (for evaluation, NOT for boost score)."""
        Y = np.asarray(Y)
        z = (Y - self.mu) / self.sigma
        sign_z = np.sign(z + EPS)
        z_scaled = z * np.power(self.xi, -sign_z)
        log_norm = (
            scipy.special.gammaln((self.nu + 1) / 2)
            - scipy.special.gammaln(self.nu / 2)
            - 0.5 * np.log(self.nu * np.pi)
        )
        log_kernel = -0.5 * (self.nu + 1) * np.log1p(z_scaled ** 2 / self.nu)
        log_f_t = log_norm + log_kernel
        log_fs_norm = np.log(2.0) - np.log(self.xi + 1.0 / self.xi) - np.log(self.sigma)
        return log_f_t + log_fs_norm

    def mean(self) -> np.ndarray:
        """Skewed-t mean — for Fernandez-Steel 1998 closed-form.

        E[X] = μ + σ · (xi - 1/xi) · M_1
        where M_1 = E[|t_ν|] = 2 sqrt(ν/π) · Γ((ν+1)/2) / ((ν-1) · Γ(ν/2))
        for ν > 1.
        """
        valid_nu = self.nu > 1
        M_1 = np.where(
            valid_nu,
            2 * np.sqrt(self.nu / np.pi)
                * np.exp(scipy.special.gammaln((self.nu + 1) / 2) - scipy.special.gammaln(self.nu / 2))
                / (self.nu - 1),
            0.0,
        )
        return self.mu + self.sigma * (self.xi - 1.0 / self.xi) * M_1


def quick_check():
    """Sanity check: fit + sample + logpdf return reasonable values."""
    np.random.seed(0)
    n = 500
    p = 4
    params = np.zeros((n, p))
    # init from sample fit
    Y = np.random.standard_t(df=5, size=n)
    fit_params = SkewedT.fit(Y)
    params[:] = fit_params[np.newaxis, :]
    dist = SkewedT(params)
    print(f"SkewedT init: μ={dist.mu[0]:.4f} σ={dist.sigma[0]:.4f} ν={dist.nu[0]:.4f} ξ={dist.xi[0]:.4f}")
    log_pdf = dist.logpdf(Y)
    print(f"  Mean log pdf = {log_pdf.mean():.4f}")
    samples = dist.sample(n_samples=200)
    print(f"  Sample shape: {samples.shape}, sample mean per row[0] = {samples[0].mean():.4f}")
    score_obj = SkewedTLogScore()
    score_obj.dist = dist
    score = score_obj.score(Y)
    print(f"  Mean score (neg log lik) = {score.mean():.4f}")


__all__ = ['SkewedT', 'SkewedTLogScore']


if __name__ == "__main__":
    quick_check()
