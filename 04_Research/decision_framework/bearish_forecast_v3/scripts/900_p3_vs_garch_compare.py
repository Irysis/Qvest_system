"""
900_p3_vs_garch_compare.py — P3 vs GARCH(1,1) skewed-t baseline 정량 비교

도훈 mandate 2026-05-28: "P3 vs GARCH(1,1) skewed-t baseline 정량 비교"
근거: P3 PIT PASS는 descriptive calibration. GARCH baseline 대비 outperform 입증 부재.

Spec:
- GARCH(1,1) with skewed-t distribution (Hansen 1994, arch package)
- 동일 KOSPI200 daily log return (benchmark.parquet)
- 동일 walk-forward fold 구조 (P3 trial19 = 12 fold expanding, train_min=3024 daily)
- Forecast 1d ahead → CRPS + PIT + Kupiec + Christoffersen + McNeil-Frey + Berkowitz + DM test

Compare metrics:
- CRPS / CRPS_normalized
- PIT chi² / KS / Berkowitz
- Kupiec POF 5% / 1%
- Christoffersen CC
- McNeil-Frey ES backtest
- Diebold-Mariano test (HAC lag 21, P3 vs GARCH)
- Pinball loss (per τ)

CLI:
    python 900_p3_vs_garch_compare.py
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


# Same fold spec as P3 trial19 — for direct comparability
TRAIN_MIN = 3024
TEST_WINDOW = 504
EMBARGO = 21
N_SPLITS = 12


def garch_fit_and_forecast(y_train, dist='skewt'):
    """Fit GARCH(1,1) with skewed-t and forecast 1-step ahead mean+var."""
    am = arch_model(y_train, vol='Garch', p=1, o=0, q=1, dist=dist,
                     mean='Constant', rescale=False)
    res = am.fit(disp='off', show_warning=False)
    forecast = res.forecast(horizon=1, reindex=False)
    mu = float(forecast.mean.iloc[-1, 0])
    sigma = float(np.sqrt(forecast.variance.iloc[-1, 0]))
    # Distribution parameters (Hansen Skewed-t parameterization)
    if dist == 'skewt':
        nu = float(res.params.get('nu', 8.0))
        lam = float(res.params.get('lambda', 0.0))
    else:
        nu, lam = 8.0, 0.0
    return mu, sigma, nu, lam


def garch_crps_skewt(y, mu, sigma, nu, lam, n_samples=300, rng=None):
    """Empirical CRPS via sampling from Hansen Skew-t with given params."""
    rng = rng or np.random.default_rng()
    u = rng.uniform(0.001, 0.999, n_samples)
    # Hansen quantile (using P3's p1_hansen_skewt module)
    samples = HSK.hansen_quantile(u, mu, sigma, nu, lam)
    abs_xy = np.abs(samples - y).mean()
    perm = rng.permutation(n_samples)
    abs_xx = np.abs(samples - samples[perm]).mean()
    return abs_xy - 0.5 * abs_xx


def garch_var_and_pit(mu, sigma, nu, lam, y_actual):
    """Compute VaR_05/01 and PIT for one forecast."""
    var_05 = HSK.hansen_quantile(np.array([0.05]), mu, sigma, nu, lam)[0]
    var_01 = HSK.hansen_quantile(np.array([0.01]), mu, sigma, nu, lam)[0]
    var_005 = HSK.hansen_quantile(np.array([0.005]), mu, sigma, nu, lam)[0]
    # ES_05: mean of samples below VaR_05
    rng = np.random.default_rng(0)
    u = rng.uniform(0.001, 0.999, 500)
    samples = HSK.hansen_quantile(u, mu, sigma, nu, lam)
    tail = samples[samples < var_05]
    es_05 = float(tail.mean()) if len(tail) > 0 else var_05
    # PIT
    pit = HSK.pit_per_obs(np.array([y_actual]), np.array([mu]),
                           np.array([sigma]), np.array([nu]),
                           np.array([lam]))[0]
    return var_05, var_01, var_005, es_05, pit


def diebold_mariano_test(loss_a, loss_b, hac_lag=21):
    """DM test: H0: E[loss_a - loss_b] = 0
    Returns (stat, p_value). Positive stat = b better (a has higher loss)."""
    d = loss_a - loss_b
    n = len(d)
    d_bar = d.mean()
    # Newey-West variance
    gamma_0 = np.var(d, ddof=1)
    nw_var = gamma_0
    for j in range(1, min(hac_lag + 1, n)):
        gamma_j = np.cov(d[:-j], d[j:], ddof=1)[0, 1]
        nw_var += 2 * (1 - j / (hac_lag + 1)) * gamma_j
    nw_var = max(nw_var, 1e-12)
    stat = d_bar / np.sqrt(nw_var / n)
    p_value = 2 * (1 - sp_stats.norm.cdf(np.abs(stat)))
    return float(stat), float(p_value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=str,
                        default='04_Research/decision_framework/bearish_forecast_v3/03_models/p3_vs_garch')
    args = parser.parse_args()

    # ── 1. Load KOSPI200 benchmark + compute log return ───────────────────────
    bm_path = PROJECT_ROOT / ".cache" / "benchmark.parquet"
    bm = pd.read_parquet(bm_path)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)
    bm['log_ret'] = np.log(bm['BM_Close']).diff() * 100  # percent scale (P3 정합)
    bm = bm.dropna(subset=['log_ret']).reset_index(drop=True)

    # 동일 date_start: P3 trial19 train start
    # P3 trial19 first test window = 2013-04-12 (approx). train_min=3024 starting from ~2001
    bm = bm[bm['Date'] >= '2001-01-03'].reset_index(drop=True)
    y_all = bm['log_ret'].values
    dates_all = bm['Date'].values
    n_total = len(y_all)
    print(f'[GARCH baseline] n_total={n_total}, dates {dates_all[0]} ~ {dates_all[-1]}')

    # ── 2. Walk-forward fold (same as P3 trial19) ─────────────────────────────
    rng = np.random.default_rng(0)
    all_results = []

    for fold_idx in range(N_SPLITS):
        test_start = TRAIN_MIN + fold_idx * TEST_WINDOW + EMBARGO
        test_end = min(test_start + TEST_WINDOW, n_total)
        if test_start >= n_total:
            break
        if test_end - test_start < 50:
            break

        train_end = test_start - EMBARGO
        if train_end < TRAIN_MIN:
            continue

        print(f'\n[fold {fold_idx}] train [0:{train_end}] test [{test_start}:{test_end}]'
              f' ({pd.to_datetime(dates_all[test_start]).date()} ~ '
              f'{pd.to_datetime(dates_all[test_end - 1]).date()}, n={test_end - test_start})')

        # For each test point t, refit GARCH on [0, t-embargo] and forecast t (rolling refit too expensive)
        # Use 1 fit per fold (expanding train, hold params for whole test fold) — standard GARCH backtest convention
        y_tr = y_all[:train_end]
        try:
            am = arch_model(y_tr, vol='Garch', p=1, o=0, q=1, dist='skewt',
                             mean='Constant', rescale=False)
            res = am.fit(disp='off', show_warning=False)
        except Exception as e:
            print(f'  fit FAILED: {e}')
            continue

        # In-sample params (constant for fold)
        mu_const = float(res.params['mu'])
        nu = float(res.params.get('nu', 8.0))
        lam = float(res.params.get('lambda', 0.0))
        omega = float(res.params['omega'])
        alpha = float(res.params['alpha[1]'])
        beta = float(res.params['beta[1]'])
        print(f'  GARCH(1,1)-skewt: μ={mu_const:.4f} ω={omega:.4f} α={alpha:.4f} β={beta:.4f} ν={nu:.2f} λ={lam:+.3f}')

        # Forecast 1d ahead for each test row using filtered variance up to t-1
        # Use the GARCH recurrence: σ²_t = ω + α·ε²_{t-1} + β·σ²_{t-1}
        # Initialize σ²_train_end from in-sample filtered var
        sigma2_filtered = np.asarray(res.conditional_volatility) ** 2
        sigma2_t = float(sigma2_filtered[-1]) if len(sigma2_filtered) > 0 else float(np.var(y_tr))
        eps_t = y_tr[-1] - mu_const

        fold_rows = []
        # P3 align: row Date=t에서 y_actual = log(Close_{t+1}/Close_t) forward 1d return
        # GARCH t 시점 forecast (info up to t-1) → next 1d (t의 realized)
        # P3와 align: t 시점 row → σ²_{t+1} forecast → y_{t+1} 비교
        for i in range(test_start, test_end - 1):  # exclude last (forward 미존재)
            # σ²_t = ω + α·ε²_{t-1} + β·σ²_{t-1}  (이미 sigma2_t 보유 = 이번 step forecast)
            # Forward 1d forecast: σ²_{t+1} forecast at time t (info up to t)
            sigma2_next = omega + alpha * (y_all[i] - mu_const)**2 + beta * sigma2_t
            sigma_next = float(np.sqrt(sigma2_next))
            y_forward = y_all[i + 1]  # FORWARD 1d (P3와 동일 target)

            var_05, var_01, var_005, es_05, pit = garch_var_and_pit(
                mu_const, sigma_next, nu, lam, y_forward
            )
            crps = garch_crps_skewt(y_forward, mu_const, sigma_next, nu, lam,
                                     n_samples=300, rng=rng)

            fold_rows.append({
                'Date': dates_all[i],  # P3 정합: forecast made at t for t+1
                'fold': fold_idx,
                'mu': mu_const, 'sigma': sigma_next, 'nu': nu, 'lam': lam,
                'var_05': var_05, 'var_01': var_01, 'var_005': var_005,
                'es_05': es_05,
                'pit': pit, 'crps': crps,
                'y_actual': y_forward,
            })

            sigma2_t = sigma2_next

        fold_df = pd.DataFrame(fold_rows)
        all_results.append(fold_df)
        print(f'  fold[{fold_idx}] n={len(fold_df)} CRPS={fold_df["crps"].mean():.4f}')

    # ── 3. Pooled metrics ─────────────────────────────────────────────────────
    full = pd.concat(all_results, ignore_index=True)
    y = full['y_actual'].values
    print(f'\n[Pooled] n_obs={len(full)} ({full.Date.min().date()} ~ {full.Date.max().date()})')

    y_std = float(np.std(y))
    crps_pooled = float(full['crps'].mean())
    crps_normalized = crps_pooled / y_std

    var05_bt = VARBT.var_backtest_full(y, full['var_05'].values, alpha=0.05,
                                         es_forecasts=full['es_05'].values)
    var01_bt = VARBT.var_backtest_full(y, full['var_01'].values, alpha=0.01)
    pit_chi = CALIB.pit_chi_square(full['pit'].values, n_bins=10)
    pit_ks = CALIB.pit_ks_test(full['pit'].values)
    pit_berk = CALIB.pit_berkowitz(full['pit'].values)

    print(f'\n=== GARCH(1,1)-skewt POOLED ===')
    print(f'  CRPS_pooled = {crps_pooled:.5f}')
    print(f'  CRPS_normalized = {crps_normalized:.5f}')
    print(f'  VaR_05: Kupiec_p={var05_bt["kupiec_uc"]["p_value"]:.4f}  pass={var05_bt["kupiec_uc"]["pass_at_005"]}')
    print(f'           CC_p={var05_bt["christoffersen_cc"]["p_value"]:.4f}  pass={var05_bt["christoffersen_cc"]["pass_at_005"]}')
    print(f'           McNeil-Frey_p={var05_bt["mcneil_frey_es"]["p_value"]:.4f}')
    print(f'  VaR_01: Kupiec_p={var01_bt["kupiec_uc"]["p_value"]:.4f}  pass={var01_bt["kupiec_uc"]["pass_at_005"]}')
    print(f'  PIT chi²: p={pit_chi["p_value"]:.4f}  pass={pit_chi["pass_at_005"]}')
    print(f'  PIT KS: p={pit_ks["p_value"]:.4f}')
    print(f'  PIT Berkowitz: p={pit_berk.get("p_value", float("nan")):.4f}')

    # ── 4. Compare with P3 trial19 ─────────────────────────────────────────────
    p3_path = ROOT / "03_models" / "p3_trial19" / "all_predictions.parquet"
    if p3_path.exists():
        p3 = pd.read_parquet(p3_path)
        p3['Date'] = pd.to_datetime(p3['Date'])
        # Align on overlapping Date
        full['Date'] = pd.to_datetime(full['Date'])
        merged = full.merge(p3[['Date', 'crps', 'pit', 'var_05']],
                              on='Date', how='inner', suffixes=('_garch', '_p3'))
        print(f'\n[Aligned with P3] n_overlap={len(merged)}')

        # DM test on CRPS
        dm_stat, dm_p = diebold_mariano_test(merged['crps_garch'].values,
                                                merged['crps_p3'].values, hac_lag=21)
        # positive stat = P3 better (lower CRPS)
        print(f'\n=== DM Test (CRPS) ===')
        print(f'  H0: E[CRPS_GARCH - CRPS_P3] = 0')
        print(f'  stat = {dm_stat:+.3f}  p = {dm_p:.4f}')
        if dm_p < 0.05:
            winner = "P3" if dm_stat > 0 else "GARCH"
            print(f'  → Significant: {winner} has lower CRPS')
        else:
            print(f'  → Not significant (둘 다 동등)')

        print(f'\n  P3 CRPS mean: {merged["crps_p3"].mean():.5f}')
        print(f'  GARCH CRPS mean: {merged["crps_garch"].mean():.5f}')
        print(f'  Δ CRPS (GARCH - P3): {merged["crps_garch"].mean() - merged["crps_p3"].mean():+.5f}')

        # PIT comparison
        p3_pit_chi = CALIB.pit_chi_square(merged['pit_p3'].values, n_bins=10)
        garch_pit_chi = CALIB.pit_chi_square(merged['pit_garch'].values, n_bins=10)
        print(f'\n=== PIT chi² (aligned period) ===')
        print(f'  P3:    p={p3_pit_chi["p_value"]:.4f}  pass={p3_pit_chi["pass_at_005"]}')
        print(f'  GARCH: p={garch_pit_chi["p_value"]:.4f}  pass={garch_pit_chi["pass_at_005"]}')

        # VaR_05 comparison
        p3_var05_bt = VARBT.var_backtest_full(merged['y_actual'].values,
                                                 merged['var_05_p3'].values, alpha=0.05)
        garch_var05_bt = VARBT.var_backtest_full(merged['y_actual'].values,
                                                    merged['var_05_garch'].values, alpha=0.05)
        print(f'\n=== Kupiec VaR_5% (aligned period) ===')
        print(f'  P3:    p={p3_var05_bt["kupiec_uc"]["p_value"]:.4f}  pass={p3_var05_bt["kupiec_uc"]["pass_at_005"]}')
        print(f'  GARCH: p={garch_var05_bt["kupiec_uc"]["p_value"]:.4f}  pass={garch_var05_bt["kupiec_uc"]["pass_at_005"]}')

    # ── 5. Save ───────────────────────────────────────────────────────────────
    out_dir = PROJECT_ROOT / args.output
    out_dir.mkdir(parents=True, exist_ok=True)
    full.to_parquet(out_dir / 'garch_predictions.parquet')
    summary = {
        'model': 'GARCH(1,1) skewed-t baseline',
        'spec': {'p': 1, 'o': 0, 'q': 1, 'dist': 'skewt', 'mean': 'Constant'},
        'train_min': TRAIN_MIN, 'test_window': TEST_WINDOW, 'embargo': EMBARGO,
        'n_splits': N_SPLITS,
        'n_obs': len(full),
        'crps_pooled': crps_pooled,
        'crps_normalized': crps_normalized,
        'var_05_kupiec_p': var05_bt['kupiec_uc']['p_value'],
        'var_05_kupiec_pass': var05_bt['kupiec_uc']['pass_at_005'],
        'var_05_cc_p': var05_bt['christoffersen_cc']['p_value'],
        'var_05_mcneil_frey_p': var05_bt['mcneil_frey_es']['p_value'],
        'var_01_kupiec_p': var01_bt['kupiec_uc']['p_value'],
        'var_01_kupiec_pass': var01_bt['kupiec_uc']['pass_at_005'],
        'pit_chi_p': pit_chi['p_value'],
        'pit_chi_pass': pit_chi['pass_at_005'],
        'pit_ks_p': pit_ks['p_value'],
        'pit_berkowitz_p': pit_berk.get('p_value'),
        'date_range': [str(full.Date.min().date()), str(full.Date.max().date())],
        'built_at': datetime.now().isoformat(),
    }
    if p3_path.exists() and len(merged) > 0:
        summary['p3_comparison'] = {
            'n_overlap': len(merged),
            'p3_crps_mean': float(merged['crps_p3'].mean()),
            'garch_crps_mean': float(merged['crps_garch'].mean()),
            'delta_crps': float(merged['crps_garch'].mean() - merged['crps_p3'].mean()),
            'dm_stat': dm_stat,
            'dm_p': dm_p,
            'p3_pit_p': p3_pit_chi['p_value'],
            'garch_pit_p': garch_pit_chi['p_value'],
            'p3_var05_kupiec_p': p3_var05_bt['kupiec_uc']['p_value'],
            'garch_var05_kupiec_p': garch_var05_bt['kupiec_uc']['p_value'],
        }
    (out_dir / 'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False, default=str))
    print(f'\n[saved] {out_dir / "summary.json"}')


if __name__ == '__main__':
    main()
