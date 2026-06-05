"""
var_backtest.py — Christoffersen 1998 IER VaR Backtest framework

Reference: Christoffersen, P. F. (1998). Evaluating Interval Forecasts. IER 39(4), 841-862.
v0.5 AMENDMENT E13: We cite 1998 IER (not "2009 RFS" which v0.4 mentioned).

Tests:
1. Kupiec POF (Unconditional Coverage, UC): empirical breach rate = nominal α
2. Independence (Markov chain): breaches are time-independent (no clustering)
3. Conditional Coverage (CC): UC + IND combined ~ χ²(2)
4. McNeil-Frey 2000: Expected Shortfall accuracy

All tests return:
    {'test_stat': float, 'p_value': float, 'pass_at_005': bool}
"""
from __future__ import annotations
import math

import numpy as np
from scipy import stats as sp_stats


def kupiec_pof(breaches: np.ndarray, alpha: float = 0.05) -> dict:
    """Kupiec 1995 POF (Proportion of Failures) test (Unconditional Coverage).

    H_0: π_breach = α
    LR_UC = -2 log[ (1-α)^n0 α^n1 / ((1-π̂)^n0 π̂^n1) ]  ~ χ²(1)

    Args:
        breaches: (N,) binary array (1 = VaR breach, 0 = no breach)
        alpha: nominal VaR level (e.g., 0.05 for 5% VaR)

    Returns:
        {'test_stat': LR_UC, 'p_value': χ²(1) p-value, 'pass_at_005': bool, 'n_breaches': int, 'n_total': int, 'pi_hat': float}
    """
    n_total = len(breaches)
    n1 = int(breaches.sum())
    n0 = n_total - n1
    pi_hat = n1 / n_total if n_total > 0 else 0.0

    if pi_hat == 0.0 or pi_hat == 1.0:
        return {
            'test_stat': float('inf'),
            'p_value': 0.0,
            'pass_at_005': False,
            'n_breaches': n1,
            'n_total': n_total,
            'pi_hat': pi_hat,
            'alpha_target': alpha,
            'note': 'boundary case (no/all breaches)',
        }

    log_lik_null = n0 * math.log(1 - alpha) + n1 * math.log(alpha)
    log_lik_alt = n0 * math.log(1 - pi_hat) + n1 * math.log(pi_hat)
    lr_uc = -2 * (log_lik_null - log_lik_alt)
    p_value = 1 - sp_stats.chi2.cdf(lr_uc, df=1)
    return {
        'test_stat': float(lr_uc),
        'p_value': float(p_value),
        'pass_at_005': p_value > 0.05,
        'n_breaches': n1,
        'n_total': n_total,
        'pi_hat': float(pi_hat),
        'alpha_target': alpha,
    }


def christoffersen_independence(breaches: np.ndarray) -> dict:
    """Christoffersen 1998 Independence test (Markov chain 1st order).

    H_0: π_01 = π_11 (no Markov dependence; breaches i.i.d.)
    LR_IND = -2 log[ L(π̂_1) / L(π̂_2) ]  ~ χ²(1)

    Args:
        breaches: (N,) binary array

    Returns:
        {'test_stat': LR_IND, 'p_value': float, 'pass_at_005': bool, 'pi_01': float, 'pi_11': float, 'transition_counts': {...}}
    """
    n = len(breaches)
    if n < 2:
        return {'test_stat': float('nan'), 'p_value': float('nan'), 'pass_at_005': False,
                'note': 'insufficient sample'}
    n00 = n01 = n10 = n11 = 0
    for i in range(1, n):
        prev, curr = int(breaches[i - 1]), int(breaches[i])
        if prev == 0 and curr == 0:
            n00 += 1
        elif prev == 0 and curr == 1:
            n01 += 1
        elif prev == 1 and curr == 0:
            n10 += 1
        else:
            n11 += 1

    n0 = n00 + n01
    n1 = n10 + n11
    n_total_pairs = n0 + n1

    if n1 == 0 or n0 == 0:
        return {
            'test_stat': float('nan'),
            'p_value': float('nan'),
            'pass_at_005': True,  # cannot detect Markov dep
            'pi_01': float('nan'),
            'pi_11': float('nan'),
            'transition_counts': {'n00': n00, 'n01': n01, 'n10': n10, 'n11': n11},
            'note': 'cannot estimate transitions',
        }

    pi_01 = n01 / n0
    pi_11 = n11 / n1
    pi_pool = (n01 + n11) / n_total_pairs

    eps = 1e-12
    log_lik_null = (
        (n00 + n10) * math.log(max(1 - pi_pool, eps))
        + (n01 + n11) * math.log(max(pi_pool, eps))
    )
    log_lik_alt = (
        n00 * math.log(max(1 - pi_01, eps))
        + n01 * math.log(max(pi_01, eps))
        + n10 * math.log(max(1 - pi_11, eps))
        + n11 * math.log(max(pi_11, eps))
    )
    lr_ind = -2 * (log_lik_null - log_lik_alt)
    p_value = 1 - sp_stats.chi2.cdf(lr_ind, df=1)
    return {
        'test_stat': float(lr_ind),
        'p_value': float(p_value),
        'pass_at_005': p_value > 0.05,
        'pi_01': float(pi_01),
        'pi_11': float(pi_11),
        'transition_counts': {'n00': n00, 'n01': n01, 'n10': n10, 'n11': n11},
    }


def christoffersen_conditional_coverage(breaches: np.ndarray, alpha: float = 0.05) -> dict:
    """Christoffersen 1998 Conditional Coverage (UC + IND).

    LR_CC = LR_UC + LR_IND  ~ χ²(2)
    """
    uc = kupiec_pof(breaches, alpha)
    ind = christoffersen_independence(breaches)
    if not (math.isfinite(uc['test_stat']) and math.isfinite(ind['test_stat'])):
        return {
            'test_stat': float('nan'),
            'p_value': float('nan'),
            'pass_at_005': False,
            'uc': uc,
            'ind': ind,
            'note': 'UC or IND boundary case',
        }
    lr_cc = uc['test_stat'] + ind['test_stat']
    p_value = 1 - sp_stats.chi2.cdf(lr_cc, df=2)
    return {
        'test_stat': float(lr_cc),
        'p_value': float(p_value),
        'pass_at_005': p_value > 0.05,
        'uc': uc,
        'ind': ind,
    }


def mcneil_frey_es(
    actual_loss_on_breach: np.ndarray,
    es_forecast_on_breach: np.ndarray,
) -> dict:
    """McNeil-Frey 2000 ES backtest (residual standardized t-test).

    On breach days, compute (actual - ES) / ES. Under H_0, mean of standardized residuals = 0.

    Args:
        breaches: (N,) binary
        actual_loss_on_breach: (N_breach,) actual return on breach days (negative values)
        es_forecast_on_breach: (N_breach,) forecasted ES on breach days (negative)
    """
    if len(actual_loss_on_breach) == 0:
        return {'test_stat': float('nan'), 'p_value': float('nan'), 'pass_at_005': True,
                'n_breach': 0, 'note': 'no breaches'}
    # Standardized residual: (actual - ES) / |ES|
    eps = 1e-8
    resid = (actual_loss_on_breach - es_forecast_on_breach) / (np.abs(es_forecast_on_breach) + eps)
    n = len(resid)
    mean_r = resid.mean()
    se_r = resid.std(ddof=1) / math.sqrt(n) if n > 1 else float('inf')
    t_stat = mean_r / se_r if se_r > 0 else float('nan')
    # Two-sided p-value
    if not math.isnan(t_stat):
        p_value = 2 * (1 - sp_stats.t.cdf(abs(t_stat), df=max(n - 1, 1)))
    else:
        p_value = float('nan')
    return {
        'test_stat': float(t_stat),
        'p_value': float(p_value),
        'pass_at_005': (not math.isnan(p_value)) and p_value > 0.05,
        'n_breach': n,
        'mean_residual': float(mean_r),
    }


def var_backtest_full(
    returns: np.ndarray,
    var_forecasts: np.ndarray,
    alpha: float = 0.05,
    es_forecasts: np.ndarray | None = None,
) -> dict:
    """Full backtest: UC + IND + CC + (optional) McNeil-Frey ES.

    Args:
        returns: (N,) realized returns
        var_forecasts: (N,) forecasted alpha-quantile (typically negative for long position)
        alpha: VaR level (e.g., 0.05 for 5%, 0.01 for 1%)
        es_forecasts: (N,) optional ES forecasts (E[r | r < VaR])

    Returns:
        Dict with 'kupiec_uc', 'christoffersen_ind', 'christoffersen_cc', and optionally 'mcneil_frey_es'.
    """
    breaches = (returns < var_forecasts).astype(int)
    result = {
        'kupiec_uc': kupiec_pof(breaches, alpha),
        'christoffersen_ind': christoffersen_independence(breaches),
        'christoffersen_cc': christoffersen_conditional_coverage(breaches, alpha),
    }
    if es_forecasts is not None:
        breach_mask = breaches.astype(bool)
        result['mcneil_frey_es'] = mcneil_frey_es(
            actual_loss_on_breach=returns[breach_mask],
            es_forecast_on_breach=es_forecasts[breach_mask],
        )
    return result


__all__ = [
    'kupiec_pof',
    'christoffersen_independence',
    'christoffersen_conditional_coverage',
    'mcneil_frey_es',
    'var_backtest_full',
]
