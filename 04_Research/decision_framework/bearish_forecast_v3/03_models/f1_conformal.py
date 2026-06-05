"""
f1_conformal.py — Conformal Prediction wrappers for non-exchangeable TS

Reference: Stocker et al 2025 arXiv:2511.13608 "A Gentle Introduction to Conformal TS Forecasting"
v0.5 AMENDMENT E11: paper simulated DGP only (real-world stock 부재) — KR 적용은 extrapolation.

Components:
- SplitConformalPredictor (baseline SCP, for reference)
- WeightedConformalPredictor (WCP, exponential decay)
- AdaptiveConformalInference (ACI, Gibbs-Candes 2021 + Angelopoulos-Candes-Tibshirani 2023 PID variant)
- EnsembleBatchPI (EnbPI, M=25 bootstrap)

Usage pattern (post-hoc on B1/B5 quantile forecast):
    aci = AdaptiveConformalInference(alpha=0.05, gamma=0.01)
    # walk-forward
    for t in range(T):
        q_lo, q_hi = aci.predict_interval(point_pred[t], score_quantile[t])
        observe(y[t])
        aci.update(y[t])
"""
from __future__ import annotations
from typing import Optional
import numpy as np


# ─── Helper: non-conformity score ─────────────────────────────────────────
def absolute_residual_score(y: np.ndarray, pred: np.ndarray) -> np.ndarray:
    """Standard symmetric non-conformity: s_i = |y_i - μ_i|"""
    return np.abs(y - pred)


def cqr_score(
    y: np.ndarray,
    q_lo: np.ndarray,
    q_hi: np.ndarray,
) -> np.ndarray:
    """Conformalized Quantile Regression score (Romano-Patterson-Candes 2019).

    s_i = max(q_lo - y, y - q_hi) — adaptive width based on existing quantile model.
    """
    return np.maximum(q_lo - y, y - q_hi)


# ─── 1. Split Conformal Prediction (SCP, baseline) ─────────────────────────
class SplitConformalPredictor:
    """Standard SCP — distribution-free finite-sample coverage under exchangeability.

    Calibration: compute empirical (1-α)-quantile of |y_i - μ̂(x_i)| on calibration set.
    Prediction: μ̂(x) ± q̂_{1-α}.

    Coverage guarantee: P(Y ∈ Ĉ) >= 1 - α (Vovk-Gammerman-Shafer).
    """
    def __init__(self, alpha: float = 0.05):
        self.alpha = alpha
        self.q_hat: Optional[float] = None

    def calibrate(self, y_cal: np.ndarray, pred_cal: np.ndarray) -> float:
        scores = absolute_residual_score(y_cal, pred_cal)
        n = len(scores)
        if n == 0:
            self.q_hat = float('inf')
            return self.q_hat
        # finite-sample adjustment: ceil((n+1)(1-α))/n quantile
        rank = int(np.ceil((n + 1) * (1 - self.alpha)))
        rank = min(rank, n)
        self.q_hat = float(np.sort(scores)[rank - 1])
        return self.q_hat

    def predict_interval(self, pred: np.ndarray) -> tuple:
        if self.q_hat is None:
            raise RuntimeError("Must calibrate() before predict_interval()")
        return pred - self.q_hat, pred + self.q_hat


# ─── 2. Weighted Conformal (WCP) ──────────────────────────────────────────
class WeightedConformalPredictor:
    """WCP with exponential decay weights (Barber-Candes-Ramdas-Tibshirani 2023).

    w_i ∝ ρ^{t_m - t_i}, normalized. Recent past gets higher weight → robust to non-stationarity.
    """
    def __init__(self, alpha: float = 0.05, rho: float = 0.99):
        self.alpha = alpha
        self.rho = rho
        self.q_hat: Optional[float] = None

    def calibrate(self, y_cal: np.ndarray, pred_cal: np.ndarray) -> float:
        scores = absolute_residual_score(y_cal, pred_cal)
        n = len(scores)
        if n == 0:
            self.q_hat = float('inf')
            return self.q_hat
        # Weights: most recent = 1, decay backward
        weights = np.array([self.rho ** (n - 1 - i) for i in range(n)])
        weights /= weights.sum()
        # Weighted quantile
        order = np.argsort(scores)
        sorted_scores = scores[order]
        sorted_w = weights[order]
        cumw = np.cumsum(sorted_w)
        # find smallest score s.t. cumw >= 1 - α
        target = 1 - self.alpha
        idx = np.searchsorted(cumw, target)
        idx = min(idx, n - 1)
        self.q_hat = float(sorted_scores[idx])
        return self.q_hat

    def predict_interval(self, pred: np.ndarray) -> tuple:
        if self.q_hat is None:
            raise RuntimeError("Must calibrate() before predict_interval()")
        return pred - self.q_hat, pred + self.q_hat


# ─── 3. Adaptive Conformal Inference (ACI, Gibbs-Candes 2021) ──────────────
class AdaptiveConformalInference:
    """ACI — online adaptive coverage via stochastic update of α.

    Algorithm (Gibbs-Candes 2021):
        α_{t+1} = α_t + γ (α_target - err_t)
        err_t = 𝟙{Y_t ∉ Ĉ_t}

    Long-run convergence: (1/T) Σ err_t → α_target.

    Variants:
    - γ ∈ {0.005, 0.01, 0.05, 0.10} (sensitivity vs stability tradeoff)
    - Optional PID controller (Angelopoulos-Candes-Tibshirani 2023): NOT implemented here.
    """
    def __init__(
        self,
        alpha_target: float = 0.05,
        gamma: float = 0.01,
        alpha_init: Optional[float] = None,
    ):
        self.alpha_target = alpha_target
        self.gamma = gamma
        self.alpha_t = alpha_init if alpha_init is not None else alpha_target
        self.q_hat_history = []
        self.score_history = []
        self.err_history = []
        self.alpha_history = [self.alpha_t]

    def calibrate(self, y_cal: np.ndarray, pred_cal: np.ndarray) -> None:
        """Initial calibration — populate score history."""
        scores = absolute_residual_score(y_cal, pred_cal)
        self.score_history = scores.tolist()
        self._update_quantile()

    def _update_quantile(self) -> None:
        """Recompute q̂ given current α_t and score history."""
        n = len(self.score_history)
        if n == 0:
            self.q_hat_history.append(float('inf'))
            return
        # clip α to (0, 1)
        alpha = min(max(self.alpha_t, 1e-6), 1 - 1e-6)
        # finite-sample quantile
        rank = int(np.ceil((n + 1) * (1 - alpha)))
        rank = min(max(rank, 1), n)
        q = float(np.sort(self.score_history)[rank - 1])
        self.q_hat_history.append(q)

    def predict_interval(self, pred: float) -> tuple:
        q = self.q_hat_history[-1] if self.q_hat_history else float('inf')
        return pred - q, pred + q

    def update(self, y: float, pred: float) -> None:
        """Online update: observe y, compute error, update α + score history."""
        q = self.q_hat_history[-1] if self.q_hat_history else float('inf')
        lo, hi = pred - q, pred + q
        err = 1 if (y < lo or y > hi) else 0
        self.err_history.append(err)
        # α update
        self.alpha_t = self.alpha_t + self.gamma * (self.alpha_target - err)
        # ALERT: when err=1 (uncovered), α decreases → next quantile wider
        # when err=0 (covered), α increases → next quantile narrower
        # NOTE: ACI Gibbs-Candes 2021 uses opposite convention; let's verify:
        # paper Eq: α_{t+1} = α_t + γ(α - err_t)
        # If err=1, α_{t+1} = α_t + γ(α - 1) < α_t → α DECREASES (lower α → higher coverage)
        # If err=0, α_{t+1} = α_t + γ(α - 0) > α_t → α INCREASES (higher α → lower coverage)
        # So formula above is correct.
        self.alpha_history.append(self.alpha_t)
        # Add score to history
        score = abs(y - pred)
        self.score_history.append(score)
        # Recompute quantile for next prediction
        self._update_quantile()

    def long_run_coverage(self) -> float:
        """Empirical coverage = 1 - mean(err)."""
        if not self.err_history:
            return float('nan')
        return 1.0 - float(np.mean(self.err_history))


# ─── 4. Ensemble Batch Prediction Intervals (EnbPI) ────────────────────────
class EnsembleBatchPI:
    """EnbPI (Xu-Xie 2021) — bootstrap ensemble + OOB residuals + sliding refresh.

    Args:
        n_boot: number of bootstrap models (paper M=25)
        alpha: nominal miscoverage level
        refresh_steps: refresh residual quantile every s steps (default s=1)

    Workflow:
        1. Train M bootstrap models on bootstrap samples of training set
        2. For each train sample i, residual = |y_i - μ̂_OOB(x_i)| where OOB = mean of models not trained on i
        3. Test prediction: aggregate ensemble prediction + use (1-α)-quantile of residuals as half-width
        4. Sliding refresh: as new test points are observed, add residuals to pool

    NOTE: This is a generic wrapper. Caller provides bootstrap predictions externally
    (model training is the caller's responsibility).
    """
    def __init__(self, alpha: float = 0.05, refresh_steps: int = 1):
        self.alpha = alpha
        self.refresh_steps = refresh_steps
        self.residuals: list = []
        self.q_hat: Optional[float] = None
        self.step_count = 0

    def calibrate(self, oob_residuals: np.ndarray) -> float:
        """Initialize residual pool from OOB residuals on training set."""
        self.residuals = oob_residuals.tolist()
        return self._refresh_quantile()

    def _refresh_quantile(self) -> float:
        n = len(self.residuals)
        if n == 0:
            self.q_hat = float('inf')
            return self.q_hat
        rank = int(np.ceil((n + 1) * (1 - self.alpha)))
        rank = min(rank, n)
        self.q_hat = float(np.sort(self.residuals)[rank - 1])
        return self.q_hat

    def predict_interval(self, ensemble_pred: float) -> tuple:
        if self.q_hat is None:
            raise RuntimeError("Must calibrate() before predict_interval()")
        return ensemble_pred - self.q_hat, ensemble_pred + self.q_hat

    def update(self, y: float, ensemble_pred: float) -> None:
        """Add new residual; periodically refresh quantile."""
        new_resid = abs(y - ensemble_pred)
        self.residuals.append(new_resid)
        self.step_count += 1
        if self.step_count % self.refresh_steps == 0:
            self._refresh_quantile()


# ─── 5. Apply wrapper for VaR forecasts (B1 + B5 ensemble use case) ────────
def apply_conformal_to_var(
    pred_quantile_series: np.ndarray,
    actual_returns: np.ndarray,
    alpha: float = 0.05,
    method: str = 'aci',
    gamma: float = 0.01,
    calibration_n: int = 252,
) -> dict:
    """Apply conformal post-hoc on a series of point/quantile predictions.

    Args:
        pred_quantile_series: (T,) raw model VaR forecasts (e.g., 5%-quantile from B1+B5)
        actual_returns: (T,) realized returns
        alpha: nominal miscoverage
        method: 'scp' | 'wcp' | 'aci' | 'enbpi'
        gamma: ACI sensitivity
        calibration_n: warm-start calibration set size

    Returns:
        {'covered': (T,) bool array,
         'lower_bound': (T,) lower interval bound,
         'upper_bound': (T,) upper interval bound,
         'long_run_coverage': float,
         'mean_width': float}
    """
    T = len(pred_quantile_series)
    if method == 'aci':
        aci = AdaptiveConformalInference(alpha_target=alpha, gamma=gamma)
        # Initial calibration on first calibration_n points
        cal_pred = pred_quantile_series[:calibration_n]
        cal_y = actual_returns[:calibration_n]
        aci.calibrate(cal_y, cal_pred)
        covered = np.zeros(T, dtype=bool)
        lo = np.zeros(T)
        hi = np.zeros(T)
        for t in range(calibration_n, T):
            lo[t], hi[t] = aci.predict_interval(pred_quantile_series[t])
            covered[t] = (lo[t] <= actual_returns[t] <= hi[t])
            aci.update(actual_returns[t], pred_quantile_series[t])
        valid_mask = np.arange(T) >= calibration_n
        return {
            'covered': covered,
            'lower_bound': lo,
            'upper_bound': hi,
            'long_run_coverage': float(covered[valid_mask].mean()) if valid_mask.any() else float('nan'),
            'mean_width': float((hi - lo)[valid_mask].mean()) if valid_mask.any() else float('nan'),
            'n_test': int(valid_mask.sum()),
            'method': method,
        }
    elif method == 'scp':
        scp = SplitConformalPredictor(alpha=alpha)
        scp.calibrate(actual_returns[:calibration_n], pred_quantile_series[:calibration_n])
        lo, hi = scp.predict_interval(pred_quantile_series)
        covered = (lo <= actual_returns) & (actual_returns <= hi)
        valid_mask = np.arange(T) >= calibration_n
        return {
            'covered': covered,
            'lower_bound': lo,
            'upper_bound': hi,
            'long_run_coverage': float(covered[valid_mask].mean()) if valid_mask.any() else float('nan'),
            'mean_width': float((hi - lo)[valid_mask].mean()) if valid_mask.any() else float('nan'),
            'n_test': int(valid_mask.sum()),
            'method': method,
        }
    else:
        raise NotImplementedError(f"method={method} not implemented in apply_conformal_to_var")


# ─── 6. One-sided VaR ACI (Gibbs-Candes 2021 applied to lower-tail) ─────────
def aci_one_sided_var(
    y: np.ndarray,
    q_hat: np.ndarray,
    alpha: float = 0.05,
    gamma: float = 0.01,
    warmup: int = 252,
    eta0: float = 0.0,
) -> dict:
    """Online ACI correction for one-sided lower VaR.

    Goal: 𝟙{y_t < q̂_α(x_t) + η_t} → α empirically (long-run).
    Update: η_{t+1} = η_t - γ(𝟙{breach_t} - α)
    If too many breaches (>α), η decreases → q̂+η becomes more extreme (lower).
    If too few breaches (<α), η increases → q̂+η becomes less extreme (higher).

    Args:
        y: (N,) realized returns
        q_hat: (N,) base model VaR forecasts
        alpha: nominal level
        gamma: learning rate (smaller = smoother adaptation)
        warmup: warmup obs (use raw q̂ during warmup)
        eta0: initial offset

    Returns:
        dict with q_aci (N,), eta_path (N,), breach (N,), running_coverage,
        final_breach_rate
    """
    N = len(y)
    eta_path = np.zeros(N)
    q_aci = np.zeros(N)
    breach = np.zeros(N, dtype=int)
    running_coverage = np.zeros(N)

    eta_t = float(eta0)
    n_breaches = 0
    for t in range(N):
        if t < warmup:
            q_aci[t] = q_hat[t]
            eta_path[t] = 0.0
        else:
            q_aci[t] = q_hat[t] + eta_t
            eta_path[t] = eta_t

        is_breach = int(y[t] < q_aci[t])
        breach[t] = is_breach
        n_breaches += is_breach
        running_coverage[t] = n_breaches / (t + 1)

        if t >= warmup:
            eta_t = eta_t - gamma * (is_breach - alpha)

    valid_mask = np.arange(N) >= warmup
    return {
        'q_aci': q_aci,
        'eta_path': eta_path,
        'breach': breach,
        'running_coverage': running_coverage,
        'final_breach_rate': float(breach[valid_mask].mean()) if valid_mask.any() else float('nan'),
        'final_eta': float(eta_t),
        'alpha': alpha, 'gamma': gamma, 'warmup': warmup, 'n_test': int(valid_mask.sum()),
    }


def enbpi_one_sided_var(
    y: np.ndarray,
    q_hat: np.ndarray,
    alpha: float = 0.05,
    block_size: int = 252,
    warmup: int = 252,
) -> dict:
    """Block-residual conformal correction (EnbPI-inspired) for one-sided VaR.

    Adjusted: q^{enbpi}_t = q̂_t + Q_α(residuals_{t-block:t})
    where residual_i = y_i - q̂_i.

    Smoother than ACI but slower to adapt.
    """
    N = len(y)
    q_enbpi = np.zeros(N)
    residual_q_path = np.zeros(N)
    breach = np.zeros(N, dtype=int)

    for t in range(N):
        if t < warmup:
            q_enbpi[t] = q_hat[t]
            residual_q_path[t] = 0.0
        else:
            start = max(0, t - block_size)
            past_residuals = y[start:t] - q_hat[start:t]
            r_q = float(np.quantile(past_residuals, alpha))
            q_enbpi[t] = q_hat[t] + r_q
            residual_q_path[t] = r_q

        breach[t] = int(y[t] < q_enbpi[t])

    valid_mask = np.arange(N) >= warmup
    return {
        'q_enbpi': q_enbpi,
        'residual_q_path': residual_q_path,
        'breach': breach,
        'final_breach_rate': float(breach[valid_mask].mean()) if valid_mask.any() else float('nan'),
        'alpha': alpha, 'block_size': block_size, 'warmup': warmup, 'n_test': int(valid_mask.sum()),
    }


__all__ = [
    'absolute_residual_score',
    'cqr_score',
    'SplitConformalPredictor',
    'WeightedConformalPredictor',
    'AdaptiveConformalInference',
    'EnsembleBatchPI',
    'apply_conformal_to_var',
    'aci_one_sided_var',
    'enbpi_one_sided_var',
]
