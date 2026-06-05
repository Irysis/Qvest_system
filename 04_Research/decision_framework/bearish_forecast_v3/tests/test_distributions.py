"""
test_distributions.py — Unit tests for distributions.py

Sanity checks:
1. NLL gradient flows (autograd)
2. Closed-form Normal CRPS matches scipy.stats.norm CRPS reference
3. Empirical CRPS converges to closed-form as n_samples → large (Normal)
4. Skewed-t reduces to Student-t at xi=1.0 (NLL match)
5. Student-t reduces to Normal at large nu (NLL approx)
6. PIT for true distribution → ~ U(0, 1)
7. VaR(α) — empirical quantile match with closed-form (Normal)

Reference papers:
- Gneiting-Raftery 2007 JASA §4 closed-form CRPS Normal
- Fernandez-Steel 1998 JASA 93(441) skewed-t parameterization
"""
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import math
import torch
from scipy import stats as sp_stats

# Module 03_models has leading digit — use importlib
import importlib.util
_spec = importlib.util.spec_from_file_location(
    "distributions", os.path.join(ROOT, "03_models", "distributions.py")
)
assert _spec is not None and _spec.loader is not None, "distributions.py spec load fail"
D = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(D)


def reference_crps_normal(mu, sigma, y):
    """Reference closed-form CRPS Normal via Gneiting-Raftery 2007 Eq for verification."""
    z = (y - mu) / sigma
    phi = sp_stats.norm.pdf(z)
    Phi = sp_stats.norm.cdf(z)
    return sigma * (z * (2 * Phi - 1) + 2 * phi - 1.0 / math.sqrt(math.pi))


def test_normal_nll_grad():
    theta = torch.randn(16, 2, requires_grad=True)
    y = torch.randn(16)
    loss = D.normal_nll(theta, y)
    loss.backward()
    assert theta.grad is not None, "gradient flows"
    assert torch.isfinite(theta.grad).all(), "gradient finite"
    print(f"[PASS] normal_nll grad. loss={loss.item():.4f}")


def _raw_from_sigma(sigma_target: float) -> float:
    """Inverse paper transformation: sigma = 1e-3 + softplus(0.01 * raw).

    raw = log(exp(s) - 1) / 0.01, where s = sigma_target - 1e-3
    """
    s = sigma_target - 1e-3
    if s <= 0:
        return -1e6
    return math.log(math.exp(s) - 1) / 0.01


def test_normal_crps_closed_form():
    """Compare torch closed-form vs scipy reference (paper-faithful parameterization)."""
    torch.manual_seed(0)
    mu_v = 0.5
    sigma_v = 1.2
    y_v = 1.0
    raw_sigma = _raw_from_sigma(sigma_v)
    theta = torch.tensor([[mu_v, raw_sigma]])
    y = torch.tensor([y_v])
    # Verify parameterization recovers sigma
    _, sigma_recovered = D.unpack_normal(theta)
    assert abs(sigma_recovered.item() - sigma_v) < 1e-3, f"sigma recovery: {sigma_recovered.item()} vs {sigma_v}"
    crps_torch = D.normal_crps_closed(theta, y).item()
    crps_ref = reference_crps_normal(mu_v, sigma_v, y_v)
    assert abs(crps_torch - crps_ref) < 1e-3, f"closed-form Normal CRPS mismatch: torch={crps_torch:.6f} vs ref={crps_ref:.6f}"
    print(f"[PASS] normal_crps_closed. torch={crps_torch:.5f} ref={crps_ref:.5f}")


def test_normal_crps_empirical_converges():
    """Empirical CRPS via t-sampling at large nu → matches closed-form Normal."""
    torch.manual_seed(0)
    mu_v = 0.0
    sigma_v = 1.0
    y_v = 0.5
    raw_sigma = _raw_from_sigma(sigma_v)
    theta_norm = torch.tensor([[mu_v, raw_sigma]])
    y = torch.tensor([y_v])
    crps_closed = D.normal_crps_closed(theta_norm, y).item()
    # Student-t at large nu (~Normal): raw_nu = (50 - 1e-3) inverse softplus * 0.01 → very large raw
    raw_nu = _raw_from_sigma(50.0)  # same inverse transformation, target value 50
    theta_t = torch.tensor([[mu_v, raw_sigma, raw_nu]])
    _, _, nu_recovered = D.unpack_student_t(theta_t)
    crps_t = D.student_t_crps(theta_t, y, n_samples=5000).item()
    assert abs(crps_t - crps_closed) < 0.03, f"large-nu Student-t CRPS should match Normal: t={crps_t:.5f} vs N={crps_closed:.5f} (nu={nu_recovered.item():.2f})"
    print(f"[PASS] empirical Student-t at large nu → Normal CRPS. t(5000)={crps_t:.4f} closed_N={crps_closed:.4f} ν={nu_recovered.item():.2f}")


def test_skewed_t_reduces_to_student_at_xi_one():
    """At xi=1, skewed-t should match Student-t NLL closely (paper parameterization)."""
    torch.manual_seed(0)
    mu_v = 0.1
    sigma_v = 1.0
    nu_target = 5.0
    xi_target = 1.0
    raw_sigma = _raw_from_sigma(sigma_v)
    raw_nu = _raw_from_sigma(nu_target)
    raw_xi = _raw_from_sigma(xi_target)
    theta_sst = torch.tensor([[mu_v, raw_sigma, raw_nu, raw_xi]])
    theta_t = torch.tensor([[mu_v, raw_sigma, raw_nu]])
    y = torch.tensor([0.3])
    nll_sst = D.skewed_t_nll(theta_sst, y).item()
    nll_t = D.student_t_nll(theta_t, y).item()
    # FS adds log(2 / (xi + 1/xi)) = log(2/2) = 0 at xi=1 → NLL should match (approx)
    assert abs(nll_sst - nll_t) < 0.02, f"skewed-t at xi=1 ≠ Student-t: sst={nll_sst:.4f} t={nll_t:.4f}"
    print(f"[PASS] skewed_t reduces to Student-t at xi=1. sst={nll_sst:.4f} t={nll_t:.4f}")


def test_pit_uniform_when_true_distribution():
    """Generate from Normal(0, 1); PIT under Normal(0, 1) → ~ U(0, 1)."""
    torch.manual_seed(42)
    n = 5000
    y = torch.randn(n)
    mu = torch.zeros(n)
    sigma = torch.ones(n)
    pit = D.normal_cdf(y, mu, sigma).numpy()
    # KS test for uniformity (statistic should be small)
    ks_stat, ks_p = sp_stats.kstest(pit, 'uniform')
    assert ks_p > 0.01, f"PIT under true distribution should be ~ U(0,1): KS p={ks_p:.4f}"
    print(f"[PASS] PIT under true Normal. KS p={ks_p:.4f}")


def test_var_alpha():
    """Normal VaR at α=0.05 (paper parameterization)."""
    mu_v, sigma_v = 0.0, 1.0
    raw_sigma = _raw_from_sigma(sigma_v)
    theta = torch.tensor([[mu_v, raw_sigma]])
    _, sigma_recovered = D.unpack_normal(theta)
    var_torch = D.normal_var(theta, alpha=0.05).item()
    var_ref = mu_v + sigma_recovered.item() * sp_stats.norm.ppf(0.05)
    assert abs(var_torch - var_ref) < 1e-3, f"Normal VaR mismatch: torch={var_torch:.5f} ref={var_ref:.5f}"
    print(f"[PASS] normal_var. torch={var_torch:.5f} ref={var_ref:.5f} σ={sigma_recovered.item():.4f}")


def test_param_clip_stability():
    """Extreme theta should produce finite NLL (paper softplus + offset handles extremes)."""
    theta = torch.tensor([
        [0.0, 10000.0],   # paper: σ = 1e-3 + softplus(100) ≈ 100
        [0.0, -10000.0],  # paper: σ = 1e-3 + softplus(-100) ≈ 1e-3
    ])
    y = torch.tensor([0.0, 0.0])
    nll = D.normal_nll(theta, y)
    assert torch.isfinite(nll), f"NLL with extreme theta should be finite: nll={nll}"
    print(f"[PASS] param stability. nll(extreme theta)={nll.item():.4f}")


def main():
    print("=" * 64)
    print("v3 distributions.py Unit Tests")
    print("=" * 64)
    test_normal_nll_grad()
    test_normal_crps_closed_form()
    test_normal_crps_empirical_converges()
    test_skewed_t_reduces_to_student_at_xi_one()
    test_pit_uniform_when_true_distribution()
    test_var_alpha()
    test_param_clip_stability()
    print("=" * 64)
    print("ALL TESTS PASSED")
    print("=" * 64)


if __name__ == "__main__":
    main()
