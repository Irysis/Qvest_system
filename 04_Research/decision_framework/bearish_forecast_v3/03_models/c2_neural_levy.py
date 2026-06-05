"""
c2_neural_levy.py — Neural Lévy SDE for jump-diffusion forecasting

Reference: Wang-Rachev 2025 arXiv:2509.01041 "Neural Lévy SDE for State-Dependent Risk"

v3 simplified Phase 5d implementation:
- Drift μ_θ(x_t)
- Diffusion σ_θ(x_t)
- Jump intensity λ_θ(x_t)
- Jump size: Gaussian (Merton 1976 jump-diffusion) — simpler than paper Kou/CGMY

Model output: ΔY_t = μ + σ ε + Σ_{k=1}^{N} Z_k  where N ~ Poisson(λ), Z_k ~ N(μ_J, σ_J²)

Truncated compound Poisson approximation (K_max=3): mixture of Gaussian shifts.

Loss: NLL = -log P(y_t | x_t) under mixture
    p(y) = Σ_{k=0}^{K_max} P(N=k) · N(y; μ + k·μ_J, σ² + k·σ_J²)

Inference: sample 2000 paths → empirical CRPS / VaR / PIT.
"""
from __future__ import annotations
import math
from typing import Tuple

import numpy as np
import torch
import torch.nn as nn


EPS = 1e-8
SIGMA_MIN = 1e-3
SIGMA_MAX = 100.0
LAMBDA_MIN = 0.0
LAMBDA_MAX_DAILY = 0.5    # paper Section 5 (daily): jump prob ≤ 0.5
LAMBDA_MAX_WEEKLY = 2.0   # weekly (5d): ≤ 2.0
LAMBDA_MAX_MONTHLY = 5.0  # monthly (21d): ≤ 5.0
JUMP_SIZE_SIGMA_MIN = 1e-3
JUMP_SIZE_SIGMA_MAX = 50.0
JUMP_K_MAX = 3            # truncated compound Poisson


def _softplus(x):
    return torch.nn.functional.softplus(x)


class NeuralLevySDE(nn.Module):
    """Jump-diffusion model: Brownian + state-dependent jump intensity + Gaussian jump size.

    Shared encoder + 4 parameter heads:
        μ_θ(x):  drift
        σ_θ(x):  diffusion (positive via softplus + offset)
        λ_θ(x):  jump intensity (positive + capped)
        (μ_J_θ(x), σ_J_θ(x)):  jump size distribution

    Architecture (paper Section 5):
        Shared: feedforward 2 hidden × 64 + ReLU
        Heads: small NN (1 hidden × 32) per parameter

    Args:
        input_size: feature count
        sequence_length: lookback (paper uses single-step input, no sequence)
        horizon: forecast horizon (affects λ cap)
    """
    def __init__(
        self,
        input_size: int,
        sequence_length: int = 1,
        horizon: int = 1,
        hidden_dim: int = 64,
        head_dim: int = 32,
    ):
        super().__init__()
        self.input_size = input_size
        self.seq_len = sequence_length
        self.horizon = horizon
        # Flatten sequence (paper uses point-in-time features)
        flat_in = input_size * sequence_length

        # Shared encoder (2 hidden × hidden_dim)
        self.encoder = nn.Sequential(
            nn.Linear(flat_in, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
        )

        # Heads: μ, σ_raw, λ_raw, μ_J, σ_J_raw (5 params)
        def head(out_size=1):
            return nn.Sequential(
                nn.Linear(hidden_dim, head_dim),
                nn.ReLU(),
                nn.Linear(head_dim, out_size),
            )

        self.head_mu = head()
        self.head_sigma = head()
        self.head_lambda = head()
        self.head_mu_jump = head()
        self.head_sigma_jump = head()

        self._init_weights()

    def _init_weights(self):
        for m in self.modules():
            if isinstance(m, nn.Linear):
                nn.init.kaiming_uniform_(m.weight, a=0, nonlinearity='relu')
                if m.bias is not None:
                    nn.init.zeros_(m.bias)

    def _lambda_max(self):
        if self.horizon <= 1:
            return LAMBDA_MAX_DAILY
        elif self.horizon <= 5:
            return LAMBDA_MAX_WEEKLY
        else:
            return LAMBDA_MAX_MONTHLY

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
        """
        x: (B, T, F) sequence
        Returns: (mu, sigma, lambda, mu_J, sigma_J) all (B,)
        """
        if x.dim() == 3:
            B = x.shape[0]
            x_flat = x.reshape(B, -1)
        else:
            x_flat = x

        h = self.encoder(x_flat)
        mu = self.head_mu(h).squeeze(-1)
        sigma_raw = self.head_sigma(h).squeeze(-1)
        lambda_raw = self.head_lambda(h).squeeze(-1)
        mu_j = self.head_mu_jump(h).squeeze(-1)
        sigma_j_raw = self.head_sigma_jump(h).squeeze(-1)

        sigma = SIGMA_MIN + _softplus(0.01 * sigma_raw)  # paper-style scaling
        lambda_max = self._lambda_max()
        lambda_intensity = torch.clamp(_softplus(0.01 * lambda_raw), LAMBDA_MIN, lambda_max)
        sigma_j = JUMP_SIZE_SIGMA_MIN + _softplus(0.01 * sigma_j_raw)

        return mu, sigma, lambda_intensity, mu_j, sigma_j


# ─── Loss: NLL of truncated compound Poisson + Gaussian ────────────────────
def neural_levy_nll(
    params: Tuple[torch.Tensor, ...],
    y: torch.Tensor,
    k_max: int = JUMP_K_MAX,
) -> torch.Tensor:
    """Compound Poisson + Gaussian mixture NLL.

    p(y) = Σ_{k=0}^{K_max} Poisson(k; λ) · N(y; μ + k·μ_J, σ² + k·σ_J²)

    Returns mean NLL.
    """
    mu, sigma, lam, mu_j, sigma_j = params

    log_components = []
    for k in range(k_max + 1):
        # Poisson PMF in log scale: -λ + k·log(λ) - log(k!)
        log_pmf_k = -lam + k * torch.log(lam + EPS) - math.lgamma(k + 1)
        # Gaussian: y ~ N(μ + k·μ_J, σ² + k·σ_J²)
        mean_k = mu + k * mu_j
        var_k = sigma.pow(2) + k * sigma_j.pow(2)
        log_pdf_k = -0.5 * math.log(2 * math.pi) - 0.5 * torch.log(var_k + EPS) - 0.5 * (y - mean_k).pow(2) / (var_k + EPS)
        log_comp = log_pmf_k + log_pdf_k
        log_components.append(log_comp)

    # logsumexp over k components
    log_p = torch.logsumexp(torch.stack(log_components, dim=0), dim=0)
    return -log_p.mean()


# ─── Sampling ──────────────────────────────────────────────────────────────
def neural_levy_sample(
    params: Tuple[torch.Tensor, ...],
    n_samples: int = 2000,
) -> torch.Tensor:
    """Sample paths from compound Poisson + Gaussian.

    Returns: (B, n_samples) samples
    """
    mu, sigma, lam, mu_j, sigma_j = params
    B = mu.shape[0]
    # Sample N ~ Poisson(λ)
    lam_b = lam.unsqueeze(-1).expand(B, n_samples)
    N = torch.poisson(lam_b)  # (B, n_samples)
    # Sample base Brownian: ε ~ N(0, 1)
    eps = torch.randn(B, n_samples, device=mu.device)
    # Sample compound: for each (b, s), Z = Σ_{k=1}^{N_{b,s}} J_k where J_k ~ N(μ_J, σ_J²)
    # Trick: sum of N iid N(μ_J, σ_J²) ~ N(N·μ_J, N·σ_J²)
    jump_total_mean = N * mu_j.unsqueeze(-1)
    jump_total_var = N * sigma_j.unsqueeze(-1).pow(2)
    eps_j = torch.randn(B, n_samples, device=mu.device)
    # ΔY = μ + σ·ε + jump_total_mean + sqrt(jump_total_var) · eps_j
    samples = mu.unsqueeze(-1) + sigma.unsqueeze(-1) * eps + jump_total_mean + torch.sqrt(jump_total_var + EPS) * eps_j
    return samples


# ─── Numpy interfaces ──────────────────────────────────────────────────────
def levy_cdf_approx(
    params_np: Tuple[np.ndarray, ...],
    y: np.ndarray,
    n_samples: int = 2000,
) -> np.ndarray:
    """Empirical CDF via MC sampling. params_np: each (B,) array."""
    mu, sigma, lam, mu_j, sigma_j = [torch.from_numpy(p).float() for p in params_np]
    samples = neural_levy_sample((mu, sigma, lam, mu_j, sigma_j), n_samples)
    return (samples <= torch.from_numpy(y).float().unsqueeze(-1)).float().mean(dim=-1).numpy()


def levy_quantile(
    params_np: Tuple[np.ndarray, ...],
    alpha: float = 0.05,
    n_samples: int = 5000,
) -> np.ndarray:
    """VaR_α from sampled distribution."""
    mu, sigma, lam, mu_j, sigma_j = [torch.from_numpy(p).float() for p in params_np]
    samples = neural_levy_sample((mu, sigma, lam, mu_j, sigma_j), n_samples)
    return torch.quantile(samples, alpha, dim=-1).numpy()


__all__ = [
    'NeuralLevySDE',
    'neural_levy_nll',
    'neural_levy_sample',
    'levy_cdf_approx',
    'levy_quantile',
    'JUMP_K_MAX',
]
