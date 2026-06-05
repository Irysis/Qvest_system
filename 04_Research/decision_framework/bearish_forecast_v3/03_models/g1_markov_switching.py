"""
g1_markov_switching.py — Hamilton 1989 Markov-Switching for regime detection

Reference: Hamilton, J. D. (1989) "A New Approach to the Economic Analysis of Nonstationary Time Series and the Business Cycle" Econometrica 57(2):357-384

Alternative to Paradigm B (distributional) — paradigm shift mandate (도훈 2026-05-25):
- Detect "calm / volatile / bear" regimes via Markov chain
- Each regime has different mean + variance
- Filtered probabilities P(regime_t | obs ≤ t) for online inference
- Derive P(r ≤ -X%) by mixing regime-conditional Normal distributions

Architecture (2-state):
    State 0: Normal regime (low vol, μ ≈ 0)
    State 1: Bear/stress regime (high vol, μ < 0)
    Transition matrix [[p00, p01], [p10, p11]] (Markov)
    y_t = μ_{s_t} + σ_{s_t} · ε_t,  ε_t ~ N(0,1)

Filtered probability: P(s_t = i | y_1, ..., y_t) — online detection

Strengths vs distributional forecasting:
- Captures regime switches (calm → bear transitions)
- Forward-looking via regime persistence (p11 > 0.5 = bear persistence)
- Better for bear continuation detection (옵션 2 진단 결과 한계 보완)

Limitations:
- Requires regime separability (KOSPI mostly low-vol, bear is rare)
- 2-state may merge bear+volatile (3-state more flexible)
"""
from __future__ import annotations
import math
from typing import Optional

import numpy as np
import pandas as pd

try:
    from statsmodels.tsa.regime_switching.markov_regression import MarkovRegression
    HAS_STATSMODELS_MS = True
except ImportError:
    HAS_STATSMODELS_MS = False


class MarkovSwitchingForecaster:
    """Hamilton 2-state Markov-Switching for KOSPI return regimes.

    Args:
        n_regimes: 2 (calm/bear) or 3 (calm/normal/bear)
        switching_variance: True (regime-dependent σ²) — recommended
        exog: optional exogenous regressors (e.g., GKYZ vol)

    Methods:
        fit(y, exog=None) — fit on training data
        predict_regime_prob(y_new, exog_new=None) — filtered probabilities
        predict_bear_probability(y_new, threshold_pct, exog_new=None)
            — P(r_{t+1} ≤ threshold) via regime mixing
    """
    def __init__(
        self,
        n_regimes: int = 2,
        switching_variance: bool = True,
        switching_trend: bool = True,
    ):
        if not HAS_STATSMODELS_MS:
            raise ImportError("statsmodels MarkovRegression not available — install statsmodels >= 0.13")
        self.n_regimes = n_regimes
        self.switching_variance = switching_variance
        self.switching_trend = switching_trend
        self.fit_result_: Optional[object] = None
        self.train_y_: Optional[np.ndarray] = None
        self.regime_means_: Optional[np.ndarray] = None
        self.regime_stds_: Optional[np.ndarray] = None

    def fit(self, y: np.ndarray, exog: Optional[np.ndarray] = None) -> 'MarkovSwitchingForecaster':
        """Fit Markov-Switching model on training returns.

        Args:
            y: (N,) 1d log return % time series (e.g., paper percent scale)
            exog: optional (N, F) exogenous covariates
        """
        y = np.asarray(y, dtype=np.float64)
        if exog is not None:
            exog = np.asarray(exog, dtype=np.float64)
        # Hamilton Markov-Switching with switching mean + variance
        model = MarkovRegression(
            endog=y,
            k_regimes=self.n_regimes,
            trend='c' if self.switching_trend else 'n',
            switching_variance=self.switching_variance,
            switching_trend=self.switching_trend,
            exog=exog,
        )
        # Multiple random starts for robustness
        best_result = None
        best_llf = -np.inf
        n_starts = 3
        for s in range(n_starts):
            try:
                res = model.fit(disp=False, maxiter=100, em_iter=10)
                if res.llf > best_llf:
                    best_llf = res.llf
                    best_result = res
            except Exception:
                continue
        if best_result is None:
            raise RuntimeError("Markov-Switching fit failed across all starts")
        self.fit_result_ = best_result
        self.train_y_ = y

        # Extract params via param_names → dict mapping (statsmodels MarkovRegression
        # returns params as numpy array + separate param_names list)
        param_names = best_result.model.param_names
        param_values = np.asarray(best_result.params)
        params_dict = dict(zip(param_names, param_values))

        means = []
        stds = []
        for i in range(self.n_regimes):
            mu_key = f'const[{i}]'
            if mu_key in params_dict:
                means.append(float(params_dict[mu_key]))
            elif 'const' in params_dict:
                means.append(float(params_dict['const']))
            else:
                means.append(0.0)

            s2_key = f'sigma2[{i}]'
            if s2_key in params_dict:
                stds.append(np.sqrt(max(float(params_dict[s2_key]), 1e-12)))
            elif 'sigma2' in params_dict:
                stds.append(np.sqrt(max(float(params_dict['sigma2']), 1e-12)))
            else:
                stds.append(float(np.std(y)))

        self.regime_means_ = np.array(means)
        self.regime_stds_ = np.array(stds)

        # Extract transition matrix from regime_transition (shape (k, k, T-1 or 1))
        if hasattr(best_result, 'regime_transition'):
            rt_np = np.asarray(best_result.regime_transition)
            if rt_np.ndim == 3:
                trans = rt_np[..., 0]  # take first time slice (time-invariant)
            elif rt_np.ndim == 2:
                trans = rt_np
            else:
                trans = np.eye(self.n_regimes) / self.n_regimes
        else:
            trans = np.eye(self.n_regimes) / self.n_regimes
        # Ensure (k, k) shape — rows sum to 1
        if trans.shape != (self.n_regimes, self.n_regimes):
            trans = np.eye(self.n_regimes) / self.n_regimes
        # Normalize rows (defensive)
        row_sums = trans.sum(axis=1, keepdims=True)
        row_sums[row_sums == 0] = 1.0
        trans = trans / row_sums
        self.transition_ = trans
        return self

    def filtered_probabilities(self) -> np.ndarray:
        """In-sample filtered P(regime_t | y_1..y_t) — shape (T, n_regimes)."""
        if self.fit_result_ is None:
            raise RuntimeError("Must fit() first")
        return self.fit_result_.filtered_marginal_probabilities

    def smoothed_probabilities(self) -> np.ndarray:
        """In-sample smoothed P(regime_t | y_1..y_T) — shape (T, n_regimes)."""
        if self.fit_result_ is None:
            raise RuntimeError("Must fit() first")
        return self.fit_result_.smoothed_marginal_probabilities

    def predict_next_regime_prob(self) -> np.ndarray:
        """Predict P(regime_{T+1} | y_1..y_T) — one-step ahead regime probability.

        statsmodels filtered_marginal_probabilities returns (T, k_regimes).
        """
        if self.fit_result_ is None:
            raise RuntimeError("Must fit() first")
        filtered = np.asarray(self.filtered_probabilities())
        # Shape (T, k_regimes); take last timestep
        if filtered.ndim != 2:
            raise RuntimeError(f"unexpected filtered shape {filtered.shape}")
        last_filtered = filtered[-1, :]  # (k_regimes,)
        trans = self.transition_  # (k_regimes, k_regimes)
        next_prob = trans.T @ last_filtered  # (k_regimes,)
        return next_prob

    def predict_bear_probability(self, threshold_pct: float = -5.0) -> float:
        """P(r_{t+1} ≤ threshold | y_1..y_t) via regime mixing.

        P(r ≤ θ) = Σ_i P(regime_{t+1} = i) · Φ((θ - μ_i) / σ_i)
        """
        if self.fit_result_ is None:
            raise RuntimeError("Must fit() first")
        regime_probs = self.predict_next_regime_prob()
        from scipy.stats import norm
        bear_prob = 0.0
        for i in range(self.n_regimes):
            cond_prob = norm.cdf((threshold_pct - self.regime_means_[i]) / max(self.regime_stds_[i], 1e-6))
            bear_prob += regime_probs[i] * cond_prob
        return float(bear_prob)

    def predict_mixture_distribution(
        self,
        n_samples: int = 2000,
    ) -> np.ndarray:
        """Sample from one-step-ahead mixture distribution.

        r_{t+1} | y_1..y_t ~ Σ_i P(regime_{t+1} = i) · N(μ_i, σ_i²)
        """
        regime_probs = self.predict_next_regime_prob()
        # Sample regime then sample r given regime
        regime_choice = np.random.choice(self.n_regimes, size=n_samples, p=regime_probs)
        samples = np.zeros(n_samples)
        for i in range(self.n_regimes):
            mask = regime_choice == i
            n_i = int(mask.sum())
            if n_i > 0:
                samples[mask] = self.regime_means_[i] + self.regime_stds_[i] * np.random.randn(n_i)
        return samples


# ─── Walk-forward training helper ──────────────────────────────────────────
def walk_forward_predict(
    y: np.ndarray,
    train_min: int = 2008,
    test: int = 504,
    n_regimes: int = 2,
    exog: Optional[np.ndarray] = None,
    n_samples: int = 2000,
) -> dict:
    """Walk-forward Markov-Switching forecasts.

    Returns:
        dict with 'samples' (N_test, n_samples), 'bear_probs' P(-5%, -7%, -10%) per obs,
        'regime_history' filtered probs per fold.
    """
    windows = []
    train_end = train_min
    while train_end + test <= len(y):
        windows.append((train_end, train_end + test))
        train_end += test

    all_samples = []
    all_bear_probs = {-5: [], -7: [], -10: []}
    all_y_actual = []
    all_regime_history = []

    for w_idx, (tr_end, te_end) in enumerate(windows):
        y_tr = y[:tr_end]
        y_te = y[tr_end:te_end]
        exog_tr = exog[:tr_end] if exog is not None else None
        exog_te = exog[tr_end:te_end] if exog is not None else None

        print(f"  [MS-{n_regimes}] window {w_idx} fitting on {tr_end} train obs...")
        model = MarkovSwitchingForecaster(n_regimes=n_regimes, switching_variance=True, switching_trend=True)
        try:
            model.fit(y_tr, exog=exog_tr)
        except Exception as e:
            print(f"  [MS-{n_regimes}] window {w_idx} FAILED: {e}")
            continue

        # Simplified online prediction: use static parameters from train fit,
        # roll filtered probabilities forward observation-by-observation
        win_samples = []
        win_bear_5 = []
        win_bear_7 = []
        win_bear_10 = []
        trans = model.transition_  # (n_regimes, n_regimes)
        # Start from last filtered prob of train (filtered shape: (T, k_regimes))
        cur_filtered_full = np.asarray(model.filtered_probabilities())
        cur_filtered = cur_filtered_full[-1, :]  # (k_regimes,)

        from scipy.stats import norm
        for t_idx in range(len(y_te)):
            # Predict next regime prob (forward filter without observation)
            next_regime_prob = trans.T @ cur_filtered
            next_regime_prob = next_regime_prob / next_regime_prob.sum()

            # Mixture sample
            regime_choice = np.random.choice(n_regimes, size=n_samples, p=next_regime_prob)
            sample = np.zeros(n_samples)
            for i in range(n_regimes):
                mask = regime_choice == i
                n_i = int(mask.sum())
                if n_i > 0:
                    sample[mask] = model.regime_means_[i] + model.regime_stds_[i] * np.random.randn(n_i)
            win_samples.append(sample)

            # Bear probabilities
            for thr_pct, thr_list in [(-5, win_bear_5), (-7, win_bear_7), (-10, win_bear_10)]:
                bp = sum(next_regime_prob[i] * norm.cdf((thr_pct - model.regime_means_[i]) / max(model.regime_stds_[i], 1e-6))
                         for i in range(n_regimes))
                thr_list.append(float(bp))

            # Update filtered prob with observed y_te[t_idx] (forward Hamilton filter step)
            y_obs = y_te[t_idx]
            # likelihood of observation under each regime
            lik = np.array([
                np.exp(-0.5 * ((y_obs - model.regime_means_[i]) / max(model.regime_stds_[i], 1e-6)) ** 2)
                / (max(model.regime_stds_[i], 1e-6) * np.sqrt(2 * np.pi))
                for i in range(n_regimes)
            ])
            posterior = next_regime_prob * lik
            if posterior.sum() < 1e-30:
                posterior = next_regime_prob  # fallback
            cur_filtered = posterior / posterior.sum()

        win_samples = np.array(win_samples)
        all_samples.append(win_samples)
        all_bear_probs[-5].extend(win_bear_5)
        all_bear_probs[-7].extend(win_bear_7)
        all_bear_probs[-10].extend(win_bear_10)
        all_y_actual.extend(list(y_te))
        all_regime_history.append({
            'window': w_idx,
            'train_size': tr_end,
            'test_size': len(y_te),
            'regime_means': model.regime_means_.tolist(),
            'regime_stds': model.regime_stds_.tolist(),
        })

        # Empirical metrics this window
        from scipy import stats as sp_stats  # noqa: F401
        # CRPS (kernel form) via win_samples
        win_y = np.array(y_te[:len(win_samples)])
        abs_xy = np.abs(win_samples - win_y[:, None]).mean(axis=1)
        n_s = win_samples.shape[1]
        perm = np.random.permutation(n_s)
        abs_xx = np.abs(win_samples - win_samples[:, perm]).mean(axis=1)
        crps = abs_xy - 0.5 * abs_xx
        print(f"  [MS-{n_regimes}] window {w_idx}: CRPS={crps.mean():.5f} regime_means={model.regime_means_.round(3).tolist()} regime_stds={model.regime_stds_.round(3).tolist()}")

    if not all_samples:
        return {'samples': None, 'bear_probs': all_bear_probs, 'y_actual': all_y_actual,
                'regime_history': all_regime_history}

    full_samples = np.concatenate(all_samples, axis=0)
    return {
        'samples': full_samples,
        'y_actual': np.array(all_y_actual),
        'bear_probs_5': np.array(all_bear_probs[-5]),
        'bear_probs_7': np.array(all_bear_probs[-7]),
        'bear_probs_10': np.array(all_bear_probs[-10]),
        'regime_history': all_regime_history,
    }


__all__ = ['MarkovSwitchingForecaster', 'walk_forward_predict', 'HAS_STATSMODELS_MS']
