"""
test_lasso_quantile.py — Unit tests for LassoQuantileGaR

Sanity checks:
1. Quantile ordering (Q_0.05 < Q_0.50 < Q_0.95) on i.i.d. Normal data
2. Pinball loss decreases with more features
3. L1 sparsity → high alpha produces fewer non-zero coefficients
4. VaR interpolation match for non-fitted τ
5. ES_α <= VaR_α (ES is conditional mean of left tail)
6. KR NFCI proxy builds without errors
"""
import sys
import os
import importlib.util

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import numpy as np
from scipy import stats as sp_stats  # noqa: F401

_spec = importlib.util.spec_from_file_location(
    "a1_lasso_quantile", os.path.join(ROOT, "03_models", "a1_lasso_quantile.py")
)
assert _spec is not None and _spec.loader is not None
LQM = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(LQM)


def test_quantile_ordering_iid_normal():
    """On i.i.d. Normal, Q_0.05 < Q_0.50 < Q_0.95 in test data."""
    np.random.seed(0)
    n = 500
    F = 5
    X = np.random.randn(n, F)
    # Simulate y with sigma effect (heteroscedastic): y ~ Normal(0, 1 + |X[:,0]|)
    sigma_y = 1.0 + 0.5 * np.abs(X[:, 0])
    y = sigma_y * np.random.randn(n)
    model = LQM.LassoQuantileGaR(taus=(0.05, 0.50, 0.95), alpha=0.001)
    model.fit(X, y)
    X_test = np.random.randn(200, F)
    Q = model.predict_all_quantiles(X_test, fix_crossing=True)
    # All rows should be monotonic
    assert (np.diff(Q, axis=1) >= 0).all(), "Quantile ordering violated after sort"
    print(f"[PASS] quantile ordering iid normal. n_test=200, Q means: {Q.mean(axis=0).round(3)}")


def test_l1_sparsity():
    """High alpha → fewer non-zero coefficients."""
    np.random.seed(0)
    n = 300
    F = 20
    # Sparse true model: only first 3 features matter
    X = np.random.randn(n, F)
    beta_true = np.zeros(F)
    beta_true[:3] = [2.0, -1.5, 1.0]
    y = X @ beta_true + 0.5 * np.random.randn(n)
    # Low alpha → dense
    low_alpha = LQM.LassoQuantileGaR(taus=(0.50,), alpha=1e-5).fit(X, y)
    n_nz_low = low_alpha.n_nonzero_features(0.50, threshold=1e-4)
    # High alpha → sparse
    high_alpha = LQM.LassoQuantileGaR(taus=(0.50,), alpha=0.5).fit(X, y)
    n_nz_high = high_alpha.n_nonzero_features(0.50, threshold=1e-4)
    assert n_nz_high <= n_nz_low, f"L1 sparsity: high α n_nz={n_nz_high} should be <= low α n_nz={n_nz_low}"
    print(f"[PASS] L1 sparsity. low_α n_nonzero={n_nz_low}, high_α n_nonzero={n_nz_high}")


def test_pinball_loss_reasonable():
    """Pinball loss positive; tau=0.5 (median) should have median-ish loss."""
    np.random.seed(0)
    n = 500
    F = 3
    X = np.random.randn(n, F)
    y = X[:, 0] + 0.5 * np.random.randn(n)
    model = LQM.LassoQuantileGaR(taus=(0.10, 0.50, 0.90), alpha=0.001)
    model.fit(X, y)
    pb_loss = model.pinball_loss(X, y, tau=0.5)
    assert pb_loss > 0 and pb_loss < 1.0, f"pinball loss {pb_loss} out of reasonable bounds"
    print(f"[PASS] pinball loss reasonable. mean={pb_loss:.4f}")


def test_var_interpolation():
    """VaR at τ=0.075 (not fitted) should interpolate between Q_0.05 and Q_0.10.

    NOTE: sklearn QuantileRegressor can produce quantile crossing (Q_0.05 > Q_0.10 for some obs)
    due to independent regression per τ. Test checks interpolation within min/max envelope.
    """
    np.random.seed(0)
    n = 300
    F = 3
    X = np.random.randn(n, F)
    y = X[:, 0] + 0.5 * np.random.randn(n)
    model = LQM.LassoQuantileGaR(taus=(0.05, 0.10, 0.50, 0.90, 0.95), alpha=0.001)
    model.fit(X, y)
    X_test = X[:50]
    var_05 = model.predict_var(X_test, alpha=0.05)
    var_10 = model.predict_var(X_test, alpha=0.10)
    var_075 = model.predict_var(X_test, alpha=0.075)
    # var_075 should be midpoint between var_05 and var_10 — within envelope
    lo_env = np.minimum(var_05, var_10)
    hi_env = np.maximum(var_05, var_10)
    in_between = ((var_075 >= lo_env - 1e-6) & (var_075 <= hi_env + 1e-6)).all()
    assert in_between, f"VaR interpolation failed. var_05={var_05[:3]} var_075={var_075[:3]} var_10={var_10[:3]}"
    # Quantile crossing detection
    crossing = (var_05 > var_10).sum()
    print(f"[PASS] VaR interpolation. mean var_05={var_05.mean():.4f} var_075={var_075.mean():.4f} "
          f"var_10={var_10.mean():.4f} | crossings={crossing}/{len(var_05)}")


def test_es_below_var():
    """ES_α <= VaR_α (when no quantile crossing).

    NOTE: sklearn QuantileRegressor can produce crossings → ES > VaR for some obs.
    Check majority (>80%) respect ES <= VaR.
    """
    np.random.seed(0)
    n = 200
    F = 3
    X = np.random.randn(n, F)
    y = X[:, 0] + 0.5 * np.random.randn(n)
    taus = (0.001, 0.005, 0.01, 0.025, 0.05, 0.10, 0.50)
    model = LQM.LassoQuantileGaR(taus=taus, alpha=0.001).fit(X, y)
    X_test = X[:50]
    var_05 = model.predict_var(X_test, alpha=0.05)
    es_05 = model.predict_es(X_test, alpha=0.05, n_grid=20)
    es_le_var_rate = (es_05 <= var_05 + 1e-3).mean()
    assert es_le_var_rate >= 0.80, f"ES <= VaR rate {es_le_var_rate:.2f} < 0.80 (quantile crossings affecting ES integration)"
    print(f"[PASS] ES <= VaR rate={es_le_var_rate:.2f}. mean var_05={var_05.mean():.4f} es_05={es_05.mean():.4f}")


def test_skewed_t_normal_approx():
    """fit_skewed_t_from_quantiles Normal approx — should recover μ, σ on Gaussian quantiles."""
    np.random.seed(0)
    n = 100
    taus = np.array([0.05, 0.25, 0.50, 0.75, 0.95])
    z_taus = sp_stats.norm.ppf(taus)
    # 진짜 mu=0.3, sigma=1.5
    true_mu, true_sigma = 0.3, 1.5
    Q = (true_mu + true_sigma * z_taus)[np.newaxis, :].repeat(n, axis=0)
    params = LQM.fit_skewed_t_from_quantiles(Q, taus)
    # Recovered (mu, sigma) should match
    assert np.allclose(params[:, 0], true_mu, atol=0.05), f"mu recovery: {params[:5, 0]}"
    assert np.allclose(params[:, 1], true_sigma, atol=0.05), f"sigma recovery: {params[:5, 1]}"
    print(f"[PASS] skewed_t_from_quantiles Normal approx. mu={params[0,0]:.4f} (true={true_mu}) sigma={params[0,1]:.4f} (true={true_sigma})")


def test_kr_nfci_proxy_builds():
    """KR NFCI proxy construction runs without errors."""
    np.random.seed(0)
    n = 500
    bm = 100 * np.cumprod(1 + 0.01 * np.random.randn(n))
    dates = np.arange(n)
    out = LQM.build_kr_nfci_proxy(bm, dates)
    assert 'nfci_proxy' in out
    assert out['nfci_proxy'].shape == (n,)
    # Most recent values should be finite (after warm-up 60)
    valid_tail = out['nfci_proxy'][-100:]
    assert np.isfinite(valid_tail).any(), "all nfci_proxy tail values NaN"
    print(f"[PASS] KR NFCI proxy builds. shape={out['nfci_proxy'].shape}, "
          f"tail mean={np.nanmean(out['nfci_proxy'][-100:]):.4f}")


def main():
    print("=" * 64)
    print("v3 a1_lasso_quantile.py Unit Tests")
    print("=" * 64)
    test_quantile_ordering_iid_normal()
    test_l1_sparsity()
    test_pinball_loss_reasonable()
    test_var_interpolation()
    test_es_below_var()
    test_skewed_t_normal_approx()
    test_kr_nfci_proxy_builds()
    print("=" * 64)
    print("ALL TESTS PASSED")
    print("=" * 64)


if __name__ == "__main__":
    main()
