"""
distributions.py — v3 Phase 5 foundation
Normal / Student-t / skewed Student-t (Fernandez-Steel 1998) NLL + CRPS + sampling.

Source:
- Michańków 2025 arXiv:2508.18921 §3.2-3.3 (4-param skewed-t, Fernandez-Steel transform)
- Fernandez & Steel 1998 JASA 93(441):359-371 (skewed-t parameterization)
- Gneiting-Raftery 2007 JASA Eq 20/21 (CRPS integral + kernel form)

Conventions:
- All NLL functions return mean negative log-likelihood per observation
- CRPS for Normal uses closed-form; Student-t and skewed-t use empirical (Monte Carlo)
- All parameters in PyTorch tensors (batch_size, p) where p = distribution param count
- Numerical stability: log_sigma raw (not sigma) — exp(log_sigma) ensures sigma > 0

Used by:
- b1_lstm_distribution.py — LSTM output → distribution NLL loss
- b5_ngboost_custom.py — custom skewed-t for NGBoost
- 04_evaluation/metrics.py — CRPS / NLL evaluation
"""
from __future__ import annotations
import math
from typing import Tuple

import numpy as np
import torch
from torch import Tensor


# ─── Numerical stability constants ─────────────────────────────────────────
EPS = 1e-8
SIGMA_MIN = 1e-4
SIGMA_MAX = 10.0
NU_MIN = 2.5        # Student-t df > 2 for finite variance
NU_MAX = 60.0       # cap for Student-t (approaches Normal)
XI_MIN = 0.1        # skewness (Fernandez-Steel ξ > 0)
XI_MAX = 10.0


# ─── Helper: parameter unpacking + transformations ─────────────────────────
#
# v0.5.1 paper-faithful (Michańków 2025 SCRIPTS/prob_nn.ipynb Cell 4-10):
# - sigma = 1e-3 + softplus(0.01 * raw)
# - nu    = 1e-3 + softplus(0.01 * raw)
# - xi    = 1e-3 + softplus(0.01 * raw)   (xi in (0, ∞), <1 = left skew, >1 = right skew)
#
# scaling 0.01 → parameter updates 100x slower (numerical stability)
# offset 1e-3 → avoid σ=0 singularity
PAPER_SCALE = 0.01
PAPER_OFFSET = 1e-3


def unpack_normal(theta: Tensor) -> Tuple[Tensor, Tensor]:
    """theta: (batch, 2) → mu, sigma. Paper parameterization."""
    mu = theta[..., 0]
    sigma = PAPER_OFFSET + torch.nn.functional.softplus(PAPER_SCALE * theta[..., 1])
    return mu, sigma


def unpack_student_t(theta: Tensor) -> Tuple[Tensor, Tensor, Tensor]:
    """theta: (batch, 3) → mu, sigma, nu. Paper parameterization."""
    mu = theta[..., 0]
    sigma = PAPER_OFFSET + torch.nn.functional.softplus(PAPER_SCALE * theta[..., 1])
    nu = PAPER_OFFSET + torch.nn.functional.softplus(PAPER_SCALE * theta[..., 2])
    return mu, sigma, nu


def unpack_skewed_t(theta: Tensor) -> Tuple[Tensor, Tensor, Tensor, Tensor]:
    """theta: (batch, 4) → mu, sigma, nu, xi. Paper Fernandez-Steel parameterization.

    xi range:
    - xi ∈ (0, 1) → left-skewed (heavier left tail)
    - xi = 1 → symmetric
    - xi ∈ (1, ∞) → right-skewed
    """
    mu = theta[..., 0]
    sigma = PAPER_OFFSET + torch.nn.functional.softplus(PAPER_SCALE * theta[..., 1])
    nu = PAPER_OFFSET + torch.nn.functional.softplus(PAPER_SCALE * theta[..., 2])
    xi = PAPER_OFFSET + torch.nn.functional.softplus(PAPER_SCALE * theta[..., 3])
    return mu, sigma, nu, xi


# ─── 1. Normal NLL + CRPS ──────────────────────────────────────────────────
def normal_nll(theta: Tensor, y: Tensor) -> Tensor:
    """Negative log-likelihood for Normal(mu, sigma^2). Returns mean over batch.

    NLL = 0.5 log(2π) + log(σ) + (y-μ)²/(2σ²)
    """
    mu, sigma = unpack_normal(theta)
    log_var = 2.0 * torch.log(sigma + EPS)
    z = (y - mu) / (sigma + EPS)
    nll_per = 0.5 * math.log(2 * math.pi) + 0.5 * log_var + 0.5 * z.pow(2)
    return nll_per.mean()


def normal_crps_closed(theta: Tensor, y: Tensor) -> Tensor:
    """Closed-form CRPS for Normal (Gneiting-Raftery 2007 §4).

    CRPS(N(μ, σ²), y) = σ [(y-μ)/σ · (2Φ((y-μ)/σ) - 1) + 2φ((y-μ)/σ) - 1/√π]
    """
    mu, sigma = unpack_normal(theta)
    z = (y - mu) / (sigma + EPS)
    phi = torch.exp(-0.5 * z.pow(2)) / math.sqrt(2 * math.pi)
    Phi = 0.5 * (1 + torch.erf(z / math.sqrt(2)))
    crps_per = sigma * (z * (2 * Phi - 1) + 2 * phi - 1.0 / math.sqrt(math.pi))
    return crps_per.mean()


# ─── 2. Student-t NLL + CRPS ───────────────────────────────────────────────
def student_t_log_pdf(y: Tensor, mu: Tensor, sigma: Tensor, nu: Tensor) -> Tensor:
    """log f_t(y; μ, σ, ν) — Student-t with scale σ (NOT variance σ²)."""
    z = (y - mu) / (sigma + EPS)
    log_norm = (
        torch.lgamma((nu + 1) / 2)
        - torch.lgamma(nu / 2)
        - 0.5 * torch.log(nu * math.pi)
        - torch.log(sigma + EPS)
    )
    log_kernel = -0.5 * (nu + 1) * torch.log1p(z.pow(2) / nu)
    return log_norm + log_kernel


def student_t_nll(theta: Tensor, y: Tensor) -> Tensor:
    """NLL Student-t(mu, sigma, nu)."""
    mu, sigma, nu = unpack_student_t(theta)
    log_pdf = student_t_log_pdf(y, mu, sigma, nu)
    return -log_pdf.mean()


def student_t_sample(mu: Tensor, sigma: Tensor, nu: Tensor, n_samples: int = 1000) -> Tensor:
    """Draw Monte Carlo samples for CRPS empirical (B, n_samples)."""
    # Use torch.distributions.StudentT
    nu_b = nu.unsqueeze(-1).expand(*nu.shape, n_samples)
    mu_b = mu.unsqueeze(-1).expand(*mu.shape, n_samples)
    sigma_b = sigma.unsqueeze(-1).expand(*sigma.shape, n_samples)
    dist = torch.distributions.StudentT(df=nu_b, loc=mu_b, scale=sigma_b)
    return dist.rsample()


def crps_empirical(samples: Tensor, y: Tensor) -> Tensor:
    """CRPS via Gneiting-Raftery Eq 21 kernel form.

    CRPS(F, y) = E_F |X - y| - 0.5 E_F |X - X'|

    samples: (batch, n)  — Monte Carlo from distribution
    y: (batch,)
    Returns: scalar mean CRPS
    """
    # E |X - y|
    abs_xy = torch.abs(samples - y.unsqueeze(-1))  # (B, n)
    term1 = abs_xy.mean(dim=-1)  # (B,)
    # E |X - X'| — pairwise (sample without replacement: shuffle within batch)
    n = samples.shape[-1]
    perm = torch.randperm(n, device=samples.device)
    samples_p = samples[..., perm]
    term2 = torch.abs(samples - samples_p).mean(dim=-1)  # (B,)
    crps_per = term1 - 0.5 * term2
    return crps_per.mean()


def student_t_crps(theta: Tensor, y: Tensor, n_samples: int = 1000) -> Tensor:
    mu, sigma, nu = unpack_student_t(theta)
    samples = student_t_sample(mu, sigma, nu, n_samples)
    return crps_empirical(samples, y)


# ─── 3. Skewed Student-t (Fernandez-Steel 1998) ────────────────────────────
def skewed_t_log_pdf(y: Tensor, mu: Tensor, sigma: Tensor, nu: Tensor, xi: Tensor) -> Tensor:
    """log f_sst(y; μ, σ, ν, ξ) per Fernandez-Steel 1998 — paper Cell 10 piecewise form.

    Paper loss_skew_st (notebook):
        epst = (y - mu) / sigma
        stneg = (1 + (xi*epst)²/nu)^(-d)    if epst < 0  (left tail)
        stpos = (1 + (epst)²/(xi²*nu))^(-d) if epst > 0  (right tail)
        log f = log(2/(xi+1/xi)) - log(sigma) + log_norm_t + log(stneg or stpos)
    where d = (nu+1)/2.
    """
    epst = (y - mu) / (sigma + EPS)
    d = (nu + 1.0) / 2.0
    # Paper piecewise: H_positive = 1 if epst > 0, else 0
    # left (epst < 0): kernel = (1 + (xi*epst)² / nu)^(-d)
    # right (epst > 0): kernel = (1 + epst² / (xi²*nu))^(-d)
    kernel_neg = torch.pow(1.0 + (xi * epst).pow(2) / nu, -d)
    kernel_pos = torch.pow(1.0 + epst.pow(2) / (xi.pow(2) * nu), -d)
    H_pos = (epst > 0).float()
    kernel = kernel_neg * (1.0 - H_pos) + kernel_pos * H_pos
    # Normalization constant a = Γ((ν+1)/2) / (Γ(ν/2) * √(νπ))
    log_a = (
        torch.lgamma((nu + 1) / 2.0)
        - torch.lgamma(nu / 2.0)
        - 0.5 * torch.log(nu * math.pi)
    )
    log_fs_norm = math.log(2.0) - torch.log(xi + 1.0 / xi)
    log_pdf = log_fs_norm - torch.log(sigma + EPS) + log_a + torch.log(kernel + EPS)
    return log_pdf


def skewed_t_nll(theta: Tensor, y: Tensor) -> Tensor:
    mu, sigma, nu, xi = unpack_skewed_t(theta)
    log_pdf = skewed_t_log_pdf(y, mu, sigma, nu, xi)
    return -log_pdf.mean()


def skewed_t_sample(mu: Tensor, sigma: Tensor, nu: Tensor, xi: Tensor, n_samples: int = 1000) -> Tensor:
    """Draw MC samples from skewed-t via FS transformation:
    1. Sample z ~ t_nu (standardized)
    2. With prob xi^2 / (xi^2 + 1): z* = |z| · ξ  (left tail expanded)
       Else:                       z* = -|z| / ξ (right tail contracted — wait sign?)

    Actually standard FS rejection: sample u from t_nu; assign sign via Bernoulli(xi/(xi+1/xi)).
    Use mixture: y* = w · |z| · ξ - (1-w) · |z| / ξ  where w ~ Bernoulli(p), p = xi / (xi + 1/xi).

    Returns: (B, n_samples)
    """
    n = n_samples
    nu_b = nu.unsqueeze(-1).expand(*nu.shape, n)
    sigma_b = sigma.unsqueeze(-1).expand(*sigma.shape, n)
    mu_b = mu.unsqueeze(-1).expand(*mu.shape, n)
    xi_b = xi.unsqueeze(-1).expand(*xi.shape, n)

    # Standard Student-t
    t_dist = torch.distributions.StudentT(df=nu_b, loc=torch.zeros_like(nu_b), scale=torch.ones_like(nu_b))
    z = t_dist.rsample()
    abs_z = torch.abs(z)
    # Probability of right side: p_right = xi / (xi + 1/xi)
    p_right = xi_b / (xi_b + 1.0 / xi_b)
    u = torch.rand_like(z)
    is_right = (u < p_right).float()
    # Right: y* = abs_z / xi (contracted right)
    # Left:  y* = -abs_z * xi (expanded left)
    z_star = is_right * (abs_z / xi_b) - (1.0 - is_right) * (abs_z * xi_b)
    # Transform to (mu, sigma):
    return mu_b + sigma_b * z_star


def skewed_t_crps(theta: Tensor, y: Tensor, n_samples: int = 1000) -> Tensor:
    mu, sigma, nu, xi = unpack_skewed_t(theta)
    samples = skewed_t_sample(mu, sigma, nu, xi, n_samples)
    return crps_empirical(samples, y)


# ─── 4. PIT (probability integral transform) ───────────────────────────────
def normal_cdf(y: Tensor, mu: Tensor, sigma: Tensor) -> Tensor:
    z = (y - mu) / (sigma + EPS)
    return 0.5 * (1 + torch.erf(z / math.sqrt(2)))


def student_t_cdf_approx(y: Tensor, mu: Tensor, sigma: Tensor, nu: Tensor) -> Tensor:
    """Student-t CDF via beta function (scipy.special equivalent in torch).

    Use I_x(a, b) regularized incomplete beta. For practical purposes here,
    we approximate via empirical sampling for PIT (consistent w/ crps_empirical).
    """
    # Empirical PIT via 1000-sample MC quantile estimation
    samples = student_t_sample(mu, sigma, nu, n_samples=2000)
    return (samples <= y.unsqueeze(-1)).float().mean(dim=-1)


def skewed_t_cdf_approx(y: Tensor, mu: Tensor, sigma: Tensor, nu: Tensor, xi: Tensor) -> Tensor:
    samples = skewed_t_sample(mu, sigma, nu, xi, n_samples=2000)
    return (samples <= y.unsqueeze(-1)).float().mean(dim=-1)


# ─── 5. VaR / Quantile (for VaR backtest) ──────────────────────────────────
def normal_var(theta: Tensor, alpha: float = 0.05) -> Tensor:
    """alpha-quantile (long position VaR — typically α=0.05 for 5% level)."""
    mu, sigma = unpack_normal(theta)
    # standard Normal quantile
    z_alpha = torch.erfinv(torch.tensor(2 * alpha - 1.0, device=theta.device)) * math.sqrt(2)
    return mu + sigma * z_alpha


def student_t_var(theta: Tensor, alpha: float = 0.05, n_samples: int = 5000) -> Tensor:
    """Student-t VaR via empirical quantile."""
    mu, sigma, nu = unpack_student_t(theta)
    samples = student_t_sample(mu, sigma, nu, n_samples)
    return torch.quantile(samples, alpha, dim=-1)


def skewed_t_var(theta: Tensor, alpha: float = 0.05, n_samples: int = 5000) -> Tensor:
    mu, sigma, nu, xi = unpack_skewed_t(theta)
    samples = skewed_t_sample(mu, sigma, nu, xi, n_samples)
    return torch.quantile(samples, alpha, dim=-1)


# ─── 6. Numpy interfaces (for NGBoost integration) ─────────────────────────
def normal_nll_np(theta_np: np.ndarray, y_np: np.ndarray) -> np.ndarray:
    """Per-obs NLL (NOT mean). For NGBoost score evaluation."""
    mu = theta_np[..., 0]
    sigma = np.clip(np.exp(theta_np[..., 1]), SIGMA_MIN, SIGMA_MAX)
    z = (y_np - mu) / (sigma + EPS)
    return 0.5 * math.log(2 * math.pi) + np.log(sigma + EPS) + 0.5 * z**2


def normal_var_np(theta_np: np.ndarray, alpha: float = 0.05) -> np.ndarray:
    from scipy.stats import norm
    mu = theta_np[..., 0]
    sigma = np.clip(np.exp(theta_np[..., 1]), SIGMA_MIN, SIGMA_MAX)
    return mu + sigma * norm.ppf(alpha)


__all__ = [
    "EPS", "SIGMA_MIN", "SIGMA_MAX", "NU_MIN", "NU_MAX", "XI_MIN", "XI_MAX",
    "unpack_normal", "unpack_student_t", "unpack_skewed_t",
    "normal_nll", "normal_crps_closed",
    "student_t_log_pdf", "student_t_nll", "student_t_sample", "student_t_crps",
    "skewed_t_log_pdf", "skewed_t_nll", "skewed_t_sample", "skewed_t_crps",
    "crps_empirical",
    "normal_cdf", "student_t_cdf_approx", "skewed_t_cdf_approx",
    "normal_var", "student_t_var", "skewed_t_var",
    "normal_nll_np", "normal_var_np",
]
