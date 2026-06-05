"""
a1_lasso_quantile.py — LASSO Quantile Regression for Growth-at-Risk

Reference:
- Adrian-Boyarchenko-Giannone 2019 AER "Vulnerable Growth"
- Koenker-Bassett 1978 Econometrica "Regression Quantiles"
- Chernozhukov-Fernandez-Galichon 2010 Annals "Quantile and Probability Curves Without Crossing"
- IMF 2025 arxiv 2506.00572 "Machine Learning Growth at Risk" (L1 + quantile)

Methodology:
- Fit Q_{y_{t+h}}(τ | x_t) = β_0(τ) + β'(τ) x_t for τ ∈ {0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95}
- L1 (LASSO) penalty for feature selection: min Σ ρ_τ(y - Xβ) + λ ||β||_1
- Quantile crossing fix: sort quantiles ex-post (Chernozhukov-Fernandez-Galichon 2010)
- Skewed-t fit from quantile estimates (optional, Adrian 2019 §III) for full density

Output:
- Per-τ models {tau: QuantileRegressor}
- VaR_5% = Q_{0.05} directly
- ES_5% via Monte Carlo from skewed-t fit or trapezoidal integration
- Density forecast (optional) for CRPS/PIT eval

Used in:
- Phase 5c Tier 3 Linear Pool component (B+A+F)
- Phase 5d Tier 4 component (B1+B5+A+F+C)
"""
from __future__ import annotations
from typing import Sequence, Optional, Dict

import numpy as np
from sklearn.linear_model import QuantileRegressor
from sklearn.preprocessing import StandardScaler


DEFAULT_TAUS = (0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)


class LassoQuantileGaR:
    """LASSO Quantile Regression for multi-τ Growth-at-Risk forecasting.

    Args:
        taus: quantile levels to fit
        alpha: L1 penalty strength (LASSO)
        standardize: z-score features (recommended)
        solver: 'highs' (default, fast) | 'interior-point' | 'revised simplex'

    Attributes:
        models_: {tau: QuantileRegressor} fitted per quantile
        scaler_: StandardScaler (None if standardize=False)
    """
    def __init__(
        self,
        taus: Sequence[float] = DEFAULT_TAUS,
        alpha: float = 0.001,
        standardize: bool = True,
        solver: str = 'highs',
    ):
        self.taus = list(taus)
        self.alpha = alpha
        self.standardize = standardize
        self.solver = solver
        self.models_: Dict[float, QuantileRegressor] = {}
        self.scaler_: Optional[StandardScaler] = None
        self.feature_names_: Optional[list] = None

    def fit(self, X: np.ndarray, y: np.ndarray, feature_names: Optional[list] = None) -> 'LassoQuantileGaR':
        """Fit one quantile regressor per τ.

        Args:
            X: (N, F) features
            y: (N,) target (e.g., h-period forward return)
        """
        X = np.asarray(X, dtype=np.float64)
        y = np.asarray(y, dtype=np.float64)
        if self.standardize:
            self.scaler_ = StandardScaler()
            Xz = self.scaler_.fit_transform(X)
        else:
            Xz = X
        self.feature_names_ = feature_names or [f"f{i}" for i in range(Xz.shape[1])]
        self.models_ = {}
        for tau in self.taus:
            model = QuantileRegressor(quantile=tau, alpha=self.alpha, solver=self.solver, fit_intercept=True)
            model.fit(Xz, y)
            self.models_[tau] = model
        return self

    def predict_quantile(self, X: np.ndarray, tau: float) -> np.ndarray:
        if tau not in self.models_:
            raise ValueError(f"τ={tau} not in fitted models {list(self.models_.keys())}")
        Xz = self.scaler_.transform(X) if self.scaler_ is not None else X
        return self.models_[tau].predict(Xz)

    def predict_all_quantiles(self, X: np.ndarray, fix_crossing: bool = True) -> np.ndarray:
        """Return (N, len(taus)) matrix of quantile forecasts.

        Args:
            fix_crossing: if True, sort quantiles row-wise (Chernozhukov-Fernandez-Galichon 2010)
        """
        Xz = self.scaler_.transform(X) if self.scaler_ is not None else X
        Q = np.column_stack([self.models_[tau].predict(Xz) for tau in self.taus])
        if fix_crossing:
            Q = np.sort(Q, axis=1)
        return Q

    def predict_var(self, X: np.ndarray, alpha: float = 0.05) -> np.ndarray:
        """VaR at level alpha = Q_α prediction.

        If alpha not in taus, interpolate from neighboring taus.
        """
        if alpha in self.models_:
            return self.predict_quantile(X, alpha)
        # Linear interpolation between adjacent fitted taus
        sorted_taus = sorted(self.taus)
        if alpha < sorted_taus[0]:
            return self.predict_quantile(X, sorted_taus[0])
        if alpha > sorted_taus[-1]:
            return self.predict_quantile(X, sorted_taus[-1])
        for i in range(len(sorted_taus) - 1):
            lo, hi = sorted_taus[i], sorted_taus[i + 1]
            if lo <= alpha <= hi:
                w = (alpha - lo) / (hi - lo)
                Q_lo = self.predict_quantile(X, lo)
                Q_hi = self.predict_quantile(X, hi)
                return Q_lo + w * (Q_hi - Q_lo)
        raise RuntimeError("interpolation logic failed (should be unreachable)")

    def predict_es(self, X: np.ndarray, alpha: float = 0.05, n_grid: int = 50) -> np.ndarray:
        """Expected Shortfall ES_α = E[Y | Y ≤ Q_α].

        Trapezoidal approximation: ES_α ≈ (1/α) ∫_0^α Q_u du.
        """
        u_grid = np.linspace(1e-3, alpha, n_grid)
        Q_grid = np.zeros((X.shape[0], n_grid))
        for i, u in enumerate(u_grid):
            Q_grid[:, i] = self.predict_var(X, alpha=u)
        # ES ≈ trapezoidal integral / α (numpy 2.x renamed trapz → trapezoid)
        trapz_fn = getattr(np, 'trapezoid', None) or np.trapz  # type: ignore
        es = trapz_fn(Q_grid, u_grid, axis=1) / alpha
        return es

    def feature_importance(self, tau: float) -> np.ndarray:
        """L1-derived sparsity: |coef| per feature for given τ."""
        if tau not in self.models_:
            raise ValueError(f"τ={tau} not fitted")
        return np.abs(self.models_[tau].coef_)

    def n_nonzero_features(self, tau: float, threshold: float = 1e-8) -> int:
        coef = self.feature_importance(tau)
        return int(np.sum(coef > threshold))

    def pinball_loss(self, X: np.ndarray, y: np.ndarray, tau: Optional[float] = None) -> float:
        """Compute mean pinball loss.

        Args:
            tau: if None, average over all fitted taus
        """
        if tau is None:
            losses = []
            for t in self.taus:
                q_pred = self.predict_quantile(X, t)
                diff = y - q_pred
                loss = np.where(diff > 0, t * diff, -(1 - t) * diff)
                losses.append(loss.mean())
            return float(np.mean(losses))
        q_pred = self.predict_quantile(X, tau)
        diff = y - q_pred
        loss = np.where(diff > 0, tau * diff, -(1 - tau) * diff)
        return float(loss.mean())


# ─── Skewed-t fit from quantile estimates (Adrian-style, optional) ────────
def fit_skewed_t_from_quantiles(
    quantile_values: np.ndarray,
    taus: Sequence[float],
) -> tuple:
    """Fit Azzalini-Capitanio 2003 skew-t to (Q_τ, τ) pairs per observation.

    Args:
        quantile_values: (N, n_taus) — quantile predictions per obs
        taus: corresponding τ levels

    Returns:
        (params_array, density_fn) where params_array is (N, 4) [μ, σ, ν, ξ]
        and density_fn(y, params) returns f(y).

    Implementation: least-squares fit (μ, σ, ν, ξ) such that
        Q_τ_fit = F^{-1}_skewed_t(τ; μ, σ, ν, ξ) ≈ observed Q_τ.

    For Stage 1 MVP: fit only (μ, σ) Normal approximation (analytical).
    For Stage 2: full skewed-t via scipy.optimize (Adrian 2019 §III).
    """
    from scipy.stats import norm
    N = quantile_values.shape[0]
    params = np.zeros((N, 2))  # mu, sigma for Normal approx
    z_taus = norm.ppf(taus)
    for i in range(N):
        Q_i = quantile_values[i]
        # Q_τ = μ + σ z_τ  →  least squares
        A = np.column_stack([np.ones(len(taus)), z_taus])
        coef, *_ = np.linalg.lstsq(A, Q_i, rcond=None)
        params[i, 0] = coef[0]    # mu
        params[i, 1] = max(coef[1], 1e-4)  # sigma
    return params


# ─── KR NFCI proxy construction (Adrian 2019 NFCI 차용) ────────────────────
def build_kr_nfci_proxy(
    bm_close: np.ndarray,
    dates: np.ndarray,
    alt_features: Optional[np.ndarray] = None,
) -> dict:
    """Build KR National Financial Conditions Index proxy.

    Components:
    - KOSPI realized volatility (22d rolling std of log returns)
    - KOSPI drawdown depth (rolling)
    - (optional) v2 alt data: BBVA macro composite, K200 implied skew, US sector dispersion

    Returns:
        dict with 'nfci_proxy', 'components' Dataframe-like structure.
    """
    eps = 1e-8
    log_ret = np.concatenate([[np.nan], np.diff(np.log(bm_close + eps))])
    n = len(bm_close)
    # Realized volatility 22d
    rv = np.full(n, np.nan)
    for t in range(22, n):
        window = log_ret[t - 22 + 1:t + 1]
        rv[t] = np.nanstd(window)
    # Cumulative max for drawdown
    cum_max = np.maximum.accumulate(bm_close)
    dd = (bm_close - cum_max) / (cum_max + eps)
    # z-score normalization (expanding window for PIT safety)
    def expanding_z(x):
        out = np.full(n, np.nan)
        for t in range(60, n):
            mean = np.nanmean(x[:t + 1])
            std = np.nanstd(x[:t + 1]) + eps
            out[t] = (x[t] - mean) / std
        return out
    rv_z = expanding_z(rv)
    dd_z = expanding_z(dd)
    # Composite (equal weight base)
    if alt_features is not None and alt_features.shape[0] == n:
        # Average all components + alt
        all_components = np.column_stack([rv_z, -dd_z] + [alt_features[:, j] for j in range(alt_features.shape[1])])
    else:
        all_components = np.column_stack([rv_z, -dd_z])
    nfci_proxy = np.nanmean(all_components, axis=1)
    return {
        'nfci_proxy': nfci_proxy,
        'rv': rv,
        'rv_z': rv_z,
        'dd': dd,
        'dd_z': dd_z,
        'log_ret': log_ret,
    }


__all__ = [
    'LassoQuantileGaR',
    'DEFAULT_TAUS',
    'fit_skewed_t_from_quantiles',
    'build_kr_nfci_proxy',
]
