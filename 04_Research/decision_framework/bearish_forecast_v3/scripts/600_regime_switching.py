"""
600_regime_switching.py — Option B: Hamilton Markov-Switching regime detection

도훈 mandate 2026-05-25: paradigm pivot — regime-switching for bear continuation detection.

Workflow:
1. Load paper KOSPI 1d returns (paper window 2000-2020)
2. Fit Markov-Switching 2-state on each walk-forward training window
3. Extract:
   - Regime probabilities (calm vs bear)
   - P(r ≤ -5%), P(r ≤ -7%), P(r ≤ -10%)
4. CRPS / VaR backtest / Bear date forecast skill
5. Compare to A LASSO Quantile single best (CRPS 0.5113)
6. Test 3-state variant if 2-state fails
"""
from __future__ import annotations
import argparse
import json
import math
import os
import sys
import importlib.util
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


MS = _load("g1_markov_switching", str(ROOT / "03_models" / "g1_markov_switching.py"))
PF = _load("pf", str(ROOT / "scripts" / "320_b1_paper_faithful.py"))
METRICS = _load("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))


KEY_BEAR_DATES = {
    'Lehman_GFC_2008-09-15': '2008-09-15',
    'Euro_Crisis_2011-08-08': '2011-08-08',
    'COVID_2020-02-19': '2020-02-19',
}


def _json_default(obj):
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating,)):
        return float(obj)
    if isinstance(obj, (np.ndarray,)):
        return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def load_paper_kospi(cfg):
    paper_csv = Path('/tmp/deep_learning_probability/DATA/KOSPI.csv')
    if paper_csv.exists():
        df = pd.read_csv(paper_csv)
    else:
        df = pd.read_parquet(PROJECT_ROOT / cfg['data']['bm_path'])
        df = df.rename(columns={'BM_Close': 'Close'})
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.sort_values('Date').reset_index(drop=True)
    df['log_ret'] = np.log(df['Close']).diff()

    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    df = df[(df['Date'] >= date_start) & (df['Date'] <= date_end)].reset_index(drop=True)
    df = df.dropna(subset=['log_ret']).reset_index(drop=True)
    if cfg['data'].get('percent_scale', True):
        df['log_ret'] = df['log_ret'] * 100.0
    return df


def run_regime_switching(cfg_path, output_dir, n_regimes_list=(2, 3), seed=0):
    """Run Markov-Switching walk-forward + evaluate."""
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    np.random.seed(seed)

    df = load_paper_kospi(cfg)
    print(f"[MS] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()})")

    y = df['log_ret'].values
    train_min = cfg['walk_forward']['train_min']
    test = cfg['walk_forward']['test_window']

    os.makedirs(output_dir, exist_ok=True)
    all_results = {}

    for n_regimes in n_regimes_list:
        print(f"\n[MS] ====== n_regimes={n_regimes} ======")
        tag = f"ms_{n_regimes}state"
        sub_dir = Path(output_dir) / tag
        sub_dir.mkdir(parents=True, exist_ok=True)

        try:
            result = MS.walk_forward_predict(
                y=y, train_min=train_min, test=test, n_regimes=n_regimes,
            )
        except Exception as e:
            print(f"  [MS-{n_regimes}] FATAL: {e}")
            all_results[tag] = {'error': str(e)}
            continue

        if result['samples'] is None:
            print(f"  [MS-{n_regimes}] no samples — skip")
            all_results[tag] = {'error': 'no samples'}
            continue

        samples = result['samples']
        y_actual = result['y_actual']
        # Need to align dates
        n_test = len(y_actual)
        dates_test = df['Date'].values[train_min:train_min + n_test]
        # CRPS empirical
        from scipy.stats import norm  # noqa: F401
        abs_xy = np.abs(samples - y_actual[:, None]).mean(axis=1)
        n_s = samples.shape[1]
        perm = np.random.permutation(n_s)
        abs_xx = np.abs(samples - samples[:, perm]).mean(axis=1)
        crps_per = abs_xy - 0.5 * abs_xx
        var_05 = np.quantile(samples, 0.05, axis=1)
        var_01 = np.quantile(samples, 0.01, axis=1)
        # PIT
        pit = (samples <= y_actual[:, None]).mean(axis=1)

        var_05_bt = VARBT.var_backtest_full(y_actual, var_05, alpha=0.05)
        var_01_bt = VARBT.var_backtest_full(y_actual, var_01, alpha=0.01)
        pit_chi = CALIB.pit_chi_square(pit, n_bins=10)

        # Save full predictions
        pred_df = pd.DataFrame({
            'Date': pd.to_datetime(dates_test),
            'y_actual': y_actual,
            'crps': crps_per,
            'pit': pit,
            'var_05': var_05,
            'var_01': var_01,
            'p_minus_5pct': result['bear_probs_5'],
            'p_minus_7pct': result['bear_probs_7'],
            'p_minus_10pct': result['bear_probs_10'],
        })
        pred_df.to_parquet(sub_dir / "all_predictions.parquet")

        # Bear date evals
        bear_evals = {}
        for label, dstr in KEY_BEAR_DATES.items():
            td = pd.to_datetime(dstr)
            mask = pred_df['Date'] == td
            if mask.sum() == 0:
                diffs = (pred_df['Date'] - td).abs()
                if diffs.min() <= pd.Timedelta(days=3):
                    idx = diffs.idxmin()
                    row = pred_df.iloc[idx]
                else:
                    bear_evals[label] = {'in_test_set': False}
                    continue
            else:
                row = pred_df[mask].iloc[0]
            bear_evals[label] = {
                'in_test_set': True,
                'forecast_date': str(row['Date'].date()),
                'y_actual': float(row['y_actual']),
                'p_minus_5pct': float(row['p_minus_5pct']),
                'p_minus_7pct': float(row['p_minus_7pct']),
                'p_minus_10pct': float(row['p_minus_10pct']),
            }

        all_results[tag] = {
            'n_regimes': n_regimes,
            'n_test': int(n_test),
            'crps_pooled': float(crps_per.mean()),
            'var_05_kupiec_pass': var_05_bt['kupiec_uc']['pass_at_005'],
            'var_05_cc_pass': var_05_bt['christoffersen_cc']['pass_at_005'],
            'var_01_kupiec_pass': var_01_bt['kupiec_uc']['pass_at_005'],
            'pit_chi_pass': pit_chi['pass_at_005'],
            'regime_history': result['regime_history'],
            'bear_date_evaluations': bear_evals,
            'bear_probabilities_summary': {
                'p_minus_5pct_mean': float(pred_df['p_minus_5pct'].mean()),
                'p_minus_5pct_max': float(pred_df['p_minus_5pct'].max()),
                'p_minus_10pct_mean': float(pred_df['p_minus_10pct'].mean()),
                'p_minus_10pct_max': float(pred_df['p_minus_10pct'].max()),
            },
        }

        print(f"\n[{tag}] POOLED CRPS={crps_per.mean():.5f} "
              f"VaR_05_kupiec={var_05_bt['kupiec_uc']['pass_at_005']} "
              f"VaR_05_cc={var_05_bt['christoffersen_cc']['pass_at_005']} "
              f"PIT={pit_chi['pass_at_005']} n={n_test}")
        for label, ev in bear_evals.items():
            if ev.get('in_test_set'):
                print(f"  {label}: actual={ev['y_actual']:+.3f}% P(-5%)={ev['p_minus_5pct']*100:.2f}% P(-10%)={ev['p_minus_10pct']*100:.2f}%")

    out_path = Path(output_dir) / "ms_summary.json"
    with open(out_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=_json_default)
    print(f"\n[MS] summary saved: {out_path}")
    return all_results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/g1_markov.yaml')
    parser.add_argument('--output', type=str, default='03_models/g1_markov_switching')
    parser.add_argument('--n_regimes', type=str, default='2,3')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    n_regimes_list = tuple(int(x) for x in args.n_regimes.split(','))
    print(f"[MS] CFG: {cfg_path}")
    print(f"[MS] OUT: {output_dir}")
    print(f"[MS] n_regimes: {n_regimes_list}")
    run_regime_switching(str(cfg_path), str(output_dir), n_regimes_list=n_regimes_list, seed=args.seed)


if __name__ == "__main__":
    main()
