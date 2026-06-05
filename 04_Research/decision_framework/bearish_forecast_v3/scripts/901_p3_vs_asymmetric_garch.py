"""
901_p3_vs_asymmetric_garch.py — P3 vs GJR-GARCH + EGARCH (asymmetric vol) baseline 비교

도훈 mandate 2026-05-28: GARCH(1,1) 후속. asymmetric vol model로 leverage effect 포함 baseline.
KOSPI200은 negative shock skew (λ<0) → asymmetric model이 PIT calibration 개선 가능성.

Models:
- GARCH(1,1) skew-t (기존, baseline)
- GJR-GARCH(1,1,1) skew-t (Glosten-Jagannathan-Runkle 1993)
- EGARCH(1,1,1) skew-t (Nelson 1991, log σ² + leverage)

Forward 1d alignment with P3 trial19 (900 script v2 정합).
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import sys
import warnings
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
from arch import arch_model
from scipy import stats as sp_stats

warnings.filterwarnings('ignore')

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, str(p))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


HSK = _load("p1_hansen_skewt", ROOT / "03_models" / "p1_hansen_skewt.py")
VARBT = _load("var_backtest", ROOT / "04_evaluation" / "var_backtest.py")
CALIB = _load("calibration", ROOT / "04_evaluation" / "calibration.py")


TRAIN_MIN = 3024
TEST_WINDOW = 504
EMBARGO = 21
N_SPLITS = 12

MODELS = {
    'GARCH': {'vol': 'Garch', 'p': 1, 'o': 0, 'q': 1},
    'GJR': {'vol': 'Garch', 'p': 1, 'o': 1, 'q': 1},  # GJR-GARCH: o=1 asymmetric
    'EGARCH': {'vol': 'EGARCH', 'p': 1, 'o': 1, 'q': 1},
}


def garch_var_and_pit(mu, sigma, nu, lam, y_actual):
    var_05 = HSK.hansen_quantile(np.array([0.05]), mu, sigma, nu, lam)[0]
    var_01 = HSK.hansen_quantile(np.array([0.01]), mu, sigma, nu, lam)[0]
    rng = np.random.default_rng(0)
    u = rng.uniform(0.001, 0.999, 500)
    samples = HSK.hansen_quantile(u, mu, sigma, nu, lam)
    tail = samples[samples < var_05]
    es_05 = float(tail.mean()) if len(tail) > 0 else var_05
    pit = HSK.pit_per_obs(np.array([y_actual]), np.array([mu]),
                           np.array([sigma]), np.array([nu]),
                           np.array([lam]))[0]
    return var_05, var_01, es_05, pit


def crps_sample(y, mu, sigma, nu, lam, n_samples=300, rng=None):
    rng = rng or np.random.default_rng()
    u = rng.uniform(0.001, 0.999, n_samples)
    samples = HSK.hansen_quantile(u, mu, sigma, nu, lam)
    abs_xy = np.abs(samples - y).mean()
    perm = rng.permutation(n_samples)
    abs_xx = np.abs(samples - samples[perm]).mean()
    return abs_xy - 0.5 * abs_xx


def fit_and_forecast_fold(model_name, model_spec, y_all, dates_all, test_start, test_end, fold_idx, rng):
    """Fit one model for one fold, forecast all test rows (forward 1d)."""
    train_end = test_start - EMBARGO
    y_tr = y_all[:train_end]

    try:
        am = arch_model(y_tr, **model_spec, dist='skewt', mean='Constant', rescale=False)
        res = am.fit(disp='off', show_warning=False)
    except Exception as e:
        print(f'  [{model_name} fold {fold_idx}] fit FAILED: {e}')
        return None

    mu_const = float(res.params['mu'])
    nu = float(res.params.get('nu', 8.0))
    lam = float(res.params.get('lambda', 0.0))

    # Extract σ² recurrence params
    omega = float(res.params['omega'])
    alpha = float(res.params.get('alpha[1]', 0.0))
    beta = float(res.params.get('beta[1]', 0.0))
    gamma = float(res.params.get('gamma[1]', 0.0))  # asymmetric (GJR / EGARCH)

    sigma2_filtered = np.asarray(res.conditional_volatility) ** 2
    sigma2_t = float(sigma2_filtered[-1]) if len(sigma2_filtered) > 0 else float(np.var(y_tr))

    fold_rows = []
    for i in range(test_start, test_end - 1):
        eps_i = y_all[i] - mu_const
        # σ²_{t+1} forecast (forward 1d)
        if model_spec['vol'] == 'EGARCH':
            # log σ²_{t+1} = ω + α(|z_t| - E|z_t|) + γ·z_t + β·log σ²_t
            log_sigma2_t = np.log(max(sigma2_t, 1e-12))
            sigma_t = np.sqrt(sigma2_t)
            z_t = eps_i / sigma_t if sigma_t > 0 else 0
            # For skew-t with high dof, E[|z|] ≈ sqrt(2/π) (normal approx)
            e_abs_z = np.sqrt(2 / np.pi)
            log_sigma2_next = omega + alpha * (np.abs(z_t) - e_abs_z) + gamma * z_t + beta * log_sigma2_t
            sigma2_next = np.exp(log_sigma2_next)
        elif model_spec['o'] > 0:
            # GJR: σ²_{t+1} = ω + α·ε²_t + γ·ε²_t·I(ε_t<0) + β·σ²_t
            I_neg = 1.0 if eps_i < 0 else 0.0
            sigma2_next = omega + alpha * eps_i**2 + gamma * eps_i**2 * I_neg + beta * sigma2_t
        else:
            # Plain GARCH(1,1)
            sigma2_next = omega + alpha * eps_i**2 + beta * sigma2_t

        sigma2_next = max(sigma2_next, 1e-12)
        sigma_next = float(np.sqrt(sigma2_next))
        y_forward = y_all[i + 1]

        var_05, var_01, es_05, pit = garch_var_and_pit(mu_const, sigma_next, nu, lam, y_forward)
        crps = crps_sample(y_forward, mu_const, sigma_next, nu, lam, n_samples=300, rng=rng)

        fold_rows.append({
            'Date': dates_all[i],
            'fold': fold_idx,
            'model': model_name,
            'mu': mu_const, 'sigma': sigma_next, 'nu': nu, 'lam': lam,
            'var_05': var_05, 'var_01': var_01, 'es_05': es_05,
            'pit': pit, 'crps': crps,
            'y_actual': y_forward,
        })
        sigma2_t = sigma2_next

    fold_df = pd.DataFrame(fold_rows)
    print(f'  [{model_name} fold {fold_idx}] n={len(fold_df)} CRPS={fold_df["crps"].mean():.4f} '
          f'μ={mu_const:.3f} ν={nu:.1f} λ={lam:+.3f} γ={gamma:+.3f}')
    return fold_df


def diebold_mariano_test(loss_a, loss_b, hac_lag=21):
    d = loss_a - loss_b
    n = len(d)
    d_bar = d.mean()
    gamma_0 = np.var(d, ddof=1)
    nw_var = gamma_0
    for j in range(1, min(hac_lag + 1, n)):
        gamma_j = np.cov(d[:-j], d[j:], ddof=1)[0, 1]
        nw_var += 2 * (1 - j / (hac_lag + 1)) * gamma_j
    nw_var = max(nw_var, 1e-12)
    stat = d_bar / np.sqrt(nw_var / n)
    p_value = 2 * (1 - sp_stats.norm.cdf(np.abs(stat)))
    return float(stat), float(p_value)


def evaluate_pooled(full, model_name):
    y = full['y_actual'].values
    y_std = float(np.std(y))
    crps_pooled = float(full['crps'].mean())
    crps_n = crps_pooled / y_std
    var05_bt = VARBT.var_backtest_full(y, full['var_05'].values, alpha=0.05,
                                         es_forecasts=full['es_05'].values)
    var01_bt = VARBT.var_backtest_full(y, full['var_01'].values, alpha=0.01)
    pit_chi = CALIB.pit_chi_square(full['pit'].values, n_bins=10)
    pit_ks = CALIB.pit_ks_test(full['pit'].values)
    pit_berk = CALIB.pit_berkowitz(full['pit'].values)
    return {
        'model': model_name, 'n_obs': len(full),
        'crps_pooled': crps_pooled, 'crps_normalized': crps_n,
        'kupiec_05_p': float(var05_bt['kupiec_uc']['p_value']),
        'kupiec_05_pass': bool(var05_bt['kupiec_uc']['pass_at_005']),
        'cc_05_p': float(var05_bt['christoffersen_cc']['p_value']),
        'mcneil_frey_p': float(var05_bt['mcneil_frey_es']['p_value']),
        'kupiec_01_p': float(var01_bt['kupiec_uc']['p_value']),
        'kupiec_01_pass': bool(var01_bt['kupiec_uc']['pass_at_005']),
        'pit_chi_p': float(pit_chi['p_value']),
        'pit_chi_pass': bool(pit_chi['pass_at_005']),
        'pit_ks_p': float(pit_ks['p_value']),
        'pit_berkowitz_p': float(pit_berk.get('p_value', float('nan'))),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=str,
                        default='04_Research/decision_framework/bearish_forecast_v3/03_models/p3_vs_asymmetric_garch')
    args = parser.parse_args()

    bm = pd.read_parquet(PROJECT_ROOT / ".cache" / "benchmark.parquet")
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)
    bm['log_ret'] = np.log(bm['BM_Close']).diff() * 100
    bm = bm.dropna(subset=['log_ret']).reset_index(drop=True)
    bm = bm[bm['Date'] >= '2001-01-03'].reset_index(drop=True)
    y_all = bm['log_ret'].values
    dates_all = bm['Date'].values
    n_total = len(y_all)
    print(f'[Asymmetric GARCH compare] n_total={n_total}')

    rng = np.random.default_rng(0)
    model_results = {name: [] for name in MODELS.keys()}

    for fold_idx in range(N_SPLITS):
        test_start = TRAIN_MIN + fold_idx * TEST_WINDOW + EMBARGO
        test_end = min(test_start + TEST_WINDOW, n_total)
        if test_start >= n_total:
            break
        if test_end - test_start < 50:
            break
        print(f'\n[fold {fold_idx}] {pd.to_datetime(dates_all[test_start]).date()} ~ '
              f'{pd.to_datetime(dates_all[test_end-1]).date()} (n={test_end-test_start})')
        for model_name, model_spec in MODELS.items():
            df_fold = fit_and_forecast_fold(model_name, model_spec, y_all, dates_all,
                                              test_start, test_end, fold_idx, rng)
            if df_fold is not None:
                model_results[model_name].append(df_fold)

    print('\n=== POOLED Comparison ===')
    pooled_summary = {}
    for model_name in MODELS.keys():
        if model_results[model_name]:
            full = pd.concat(model_results[model_name], ignore_index=True)
            pooled_summary[model_name] = evaluate_pooled(full, model_name)
            print(f'\n[{model_name}]')
            s = pooled_summary[model_name]
            print(f'  CRPS_pooled={s["crps_pooled"]:.5f}  CRPS_n={s["crps_normalized"]:.5f}')
            print(f'  VaR_05: Kupiec p={s["kupiec_05_p"]:.4f} {"PASS" if s["kupiec_05_pass"] else "FAIL"}'
                  f'  CC p={s["cc_05_p"]:.4f}  MF p={s["mcneil_frey_p"]:.4f}')
            print(f'  VaR_01: Kupiec p={s["kupiec_01_p"]:.4f} {"PASS" if s["kupiec_01_pass"] else "FAIL"}')
            print(f'  PIT: chi² p={s["pit_chi_p"]:.4f} {"PASS" if s["pit_chi_pass"] else "FAIL"}'
                  f'  KS p={s["pit_ks_p"]:.4f}  Berkowitz p={s["pit_berkowitz_p"]:.4f}')

    # ── DM tests vs P3 (aligned) ──
    p3_path = ROOT / "03_models" / "p3_trial19" / "all_predictions.parquet"
    if p3_path.exists() and all(model_results[m] for m in MODELS):
        p3 = pd.read_parquet(p3_path)
        p3['Date'] = pd.to_datetime(p3['Date'])
        print('\n=== DM Test vs P3 (aligned, HAC lag 21) ===')
        for model_name in MODELS.keys():
            full = pd.concat(model_results[model_name], ignore_index=True)
            full['Date'] = pd.to_datetime(full['Date'])
            merged = full.merge(p3[['Date', 'crps', 'pit']], on='Date', how='inner',
                                  suffixes=(f'_{model_name}', '_p3'))
            if len(merged) < 100:
                continue
            crps_col_m = f'crps_{model_name}'
            dm_stat, dm_p = diebold_mariano_test(merged[crps_col_m].values,
                                                    merged['crps_p3'].values, hac_lag=21)
            print(f'  P3 vs {model_name}: stat={dm_stat:+.3f} p={dm_p:.4f}  '
                  f'(>0 = P3 better)  ΔCRPS={merged[crps_col_m].mean() - merged["crps_p3"].mean():+.5f}')

    # Save
    out_dir = PROJECT_ROOT / args.output
    out_dir.mkdir(parents=True, exist_ok=True)
    for model_name in MODELS.keys():
        if model_results[model_name]:
            full = pd.concat(model_results[model_name], ignore_index=True)
            full.to_parquet(out_dir / f'{model_name.lower()}_predictions.parquet')
    summary = {
        'spec': {'train_min': TRAIN_MIN, 'test_window': TEST_WINDOW, 'embargo': EMBARGO,
                  'forward_aligned': True, 'distribution': 'skewt'},
        'pooled_summary': pooled_summary,
        'built_at': datetime.now().isoformat(),
    }
    (out_dir / 'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False, default=str))
    print(f'\n[saved] {out_dir / "summary.json"}')


if __name__ == '__main__':
    main()
