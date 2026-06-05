"""
test_neural_levy.py — Unit tests for Neural Lévy SDE

Sanity checks:
1. NLL gradient flows
2. NLL ≈ Gaussian NLL when λ → 0 (no jumps)
3. Sample variance ≈ σ² + λ·(μ_J² + σ_J²) when small λ (theoretical)
4. CDF in [0, 1] + monotone
"""
import sys
import os
import importlib.util

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import math
import numpy as np
import torch

_spec = importlib.util.spec_from_file_location(
    "c2_neural_levy", os.path.join(ROOT, "03_models", "c2_neural_levy.py")
)
assert _spec is not None and _spec.loader is not None
NL = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(NL)


def test_nll_grad_flows():
    torch.manual_seed(0)
    B = 16
    input_size = 4
    seq_len = 3
    model = NL.NeuralLevySDE(input_size=input_size, sequence_length=seq_len, horizon=1)
    x = torch.randn(B, seq_len, input_size, requires_grad=False)
    y = torch.randn(B)
    params = model(x)
    loss = NL.neural_levy_nll(params, y)
    loss.backward()
    grad_norm = sum(p.grad.norm().item() for p in model.parameters() if p.grad is not None)
    assert torch.isfinite(loss), f"NLL not finite: {loss}"
    assert grad_norm > 0, f"no gradient flowing: norm={grad_norm}"
    print(f"[PASS] NLL grad flows. loss={loss.item():.4f} grad_norm={grad_norm:.4f}")


def test_zero_lambda_reduces_to_gaussian():
    """At λ → 0 (very small), NLL ≈ Gaussian NLL."""
    torch.manual_seed(0)
    B = 100
    # Construct params manually: λ ≈ 0
    mu = torch.zeros(B)
    sigma = torch.ones(B)
    lam = torch.full((B,), 1e-6)
    mu_j = torch.zeros(B)
    sigma_j = torch.ones(B)
    y = torch.randn(B)
    params = (mu, sigma, lam, mu_j, sigma_j)
    nll_levy = NL.neural_levy_nll(params, y).item()
    # Reference Gaussian NLL: 0.5*log(2π) + 0.5*y²
    nll_gauss = (0.5 * math.log(2 * math.pi) + 0.5 * y.pow(2)).mean().item()
    assert abs(nll_levy - nll_gauss) < 0.01, f"λ=0 should reduce to Gaussian: levy={nll_levy:.4f} gauss={nll_gauss:.4f}"
    print(f"[PASS] λ→0 reduces to Gaussian. levy={nll_levy:.5f} gauss={nll_gauss:.5f}")


def test_sample_variance_theoretical():
    """Sample variance ≈ σ² + λ·(μ_J² + σ_J²) for compound Poisson."""
    torch.manual_seed(0)
    B = 1
    mu = torch.tensor([0.0])
    sigma = torch.tensor([1.0])
    lam = torch.tensor([0.2])
    mu_j = torch.tensor([-2.0])
    sigma_j = torch.tensor([1.0])
    params = (mu, sigma, lam, mu_j, sigma_j)
    samples = NL.neural_levy_sample(params, n_samples=20000)
    var_emp = samples.var().item()
    # Theoretical: σ² + λ·(μ_J² + σ_J²)
    var_theo = 1.0 ** 2 + 0.2 * ((-2.0) ** 2 + 1.0 ** 2)
    rel_diff = abs(var_emp - var_theo) / var_theo
    assert rel_diff < 0.10, f"empirical var {var_emp:.4f} not within 10% of theoretical {var_theo:.4f}"
    print(f"[PASS] sample variance. emp={var_emp:.4f} theo={var_theo:.4f} rel_diff={rel_diff*100:.2f}%")


def test_cdf_in_range_monotone():
    """CDF in [0, 1] and monotone non-decreasing across y_grid."""
    torch.manual_seed(0)
    B = 50
    mu = torch.zeros(B)
    sigma = torch.ones(B)
    lam = torch.full((B,), 0.1)
    mu_j = torch.full((B,), -1.0)
    sigma_j = torch.full((B,), 0.5)
    params_np = tuple(p.numpy() for p in [mu, sigma, lam, mu_j, sigma_j])
    y_grid = np.linspace(-5, 5, 10)
    prev_cdf = np.zeros(B)
    for y_val in y_grid:
        y_arr = np.full(B, y_val)
        cdf = NL.levy_cdf_approx(params_np, y_arr, n_samples=2000)
        assert (cdf >= 0).all() and (cdf <= 1).all(), f"CDF out of [0,1] at y={y_val}: range {cdf.min()},{cdf.max()}"
        # monotone (with small noise tolerance from MC sampling)
        assert (cdf - prev_cdf >= -0.05).all(), f"CDF not monotone at y={y_val}: diff={cdf - prev_cdf}"
        prev_cdf = cdf
    print(f"[PASS] CDF in [0,1] + monotone over y in [-5, 5]")


def test_quantile_lower_than_mean():
    """For symmetric-ish distribution, VaR_0.05 should be lower than mean."""
    torch.manual_seed(0)
    B = 100
    mu = torch.zeros(B)
    sigma = torch.ones(B)
    lam = torch.full((B,), 0.1)
    mu_j = torch.full((B,), -2.0)
    sigma_j = torch.full((B,), 0.5)
    params_np = tuple(p.numpy() for p in [mu, sigma, lam, mu_j, sigma_j])
    var_05 = NL.levy_quantile(params_np, alpha=0.05, n_samples=5000)
    mean_samples = NL.neural_levy_sample((mu, sigma, lam, mu_j, sigma_j), n_samples=5000).mean(dim=-1).numpy()
    # Most cases: VaR_05 < sample mean
    n_lower = (var_05 < mean_samples).sum()
    assert n_lower >= B * 0.95, f"VaR_05 should be < mean in most cases: {n_lower}/{B}"
    print(f"[PASS] VaR_0.05 < sample mean in {n_lower}/{B} cases")


def main():
    print("=" * 64)
    print("v3 c2_neural_levy.py Unit Tests")
    print("=" * 64)
    test_nll_grad_flows()
    test_zero_lambda_reduces_to_gaussian()
    test_sample_variance_theoretical()
    test_cdf_in_range_monotone()
    test_quantile_lower_than_mean()
    print("=" * 64)
    print("ALL TESTS PASSED")
    print("=" * 64)


if __name__ == "__main__":
    main()
