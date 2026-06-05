"""
450_conformal_wrap.py — Phase 5b Conformal post-hoc on v3-fast Hansen output

도훈 mandate 2026-05-26 옵션 A: Hansen VaR forecasts에 ACI (primary) + EnbPI (fallback)
적용하여 marginal coverage 강제 (PIT 우회).

Pipeline:
1. Load v3-fast Hansen all_predictions.parquet (5241 obs, 11 folds)
2. Sweep γ ∈ {0.005, 0.01, 0.05, 0.1} for ACI
3. Apply EnbPI with block_size ∈ {126, 252, 504}
4. Backtest: breach rate, Kupiec, Christoffersen, Pinball
5. Save conformal_predictions.parquet + summary JSON
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


F1 = _load("f1_conformal", str(ROOT / "03_models" / "f1_conformal.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))


KEY_BEAR_DATES = {
    'Lehman_2008-09-15': '2008-09-15',
    'Euro_2011-08-08': '2011-08-08',
    'COVID_2020-02-19': '2020-02-19',
    'COVID_2020-03-13': '2020-03-13',
    '2022_Rate_Hike': '2022-09-26',
    '2024_Yen_Carry': '2024-08-02',
    '2024_Martial_Law': '2024-12-03',
}


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def pinball(q, y, tau):
    d = y - q
    return float(np.where(d >= 0, tau * d, (tau - 1) * d).mean())


def evaluate_var_series(y, q_raw, q_adj, alpha, warmup=252):
    """Compute backtest metrics on adjusted vs raw VaR series. Skip warmup."""
    valid = np.arange(len(y)) >= warmup
    y_v = y[valid]; q_raw_v = q_raw[valid]; q_adj_v = q_adj[valid]

    bt_raw = VARBT.var_backtest_full(y_v, q_raw_v, alpha=alpha)
    bt_adj = VARBT.var_backtest_full(y_v, q_adj_v, alpha=alpha)

    return {
        'n_test': int(valid.sum()),
        'raw': {
            'breach_rate': float((y_v < q_raw_v).mean()),
            'kupiec_p': float(bt_raw['kupiec_uc']['p_value']),
            'kupiec_pass': bool(bt_raw['kupiec_uc']['pass_at_005']),
            'ind_p': float(bt_raw['christoffersen_ind']['p_value']),
            'cc_p': float(bt_raw['christoffersen_cc']['p_value']),
            'mean_var': float(q_raw_v.mean()),
            'pinball': pinball(q_raw_v, y_v, alpha),
        },
        'adj': {
            'breach_rate': float((y_v < q_adj_v).mean()),
            'kupiec_p': float(bt_adj['kupiec_uc']['p_value']),
            'kupiec_pass': bool(bt_adj['kupiec_uc']['pass_at_005']),
            'ind_p': float(bt_adj['christoffersen_ind']['p_value']),
            'cc_p': float(bt_adj['christoffersen_cc']['p_value']),
            'mean_var': float(q_adj_v.mean()),
            'pinball': pinball(q_adj_v, y_v, alpha),
        },
    }


def run(base_path, output_dir, warmup=252, gammas=None, blocks=None):
    base_path = Path(base_path)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_parquet(base_path).sort_values('Date').reset_index(drop=True)
    df['Date'] = pd.to_datetime(df['Date'])
    y = df['y_actual'].values
    q05 = df['var_05'].values
    q01 = df['var_01'].values
    print(f'[conformal] base: {base_path} n={len(df)} ({df.Date.min().date()} ~ {df.Date.max().date()})')

    if gammas is None:
        gammas = [0.005, 0.01, 0.025, 0.05]
    if blocks is None:
        blocks = [126, 252, 504]

    # ─── ACI sweep on VaR_05 ──────────────────────────────────────────────
    aci_results_05 = []
    aci_results_01 = []
    for g in gammas:
        r05 = F1.aci_one_sided_var(y, q05, alpha=0.05, gamma=g, warmup=warmup)
        r01 = F1.aci_one_sided_var(y, q01, alpha=0.01, gamma=g, warmup=warmup)
        m05 = evaluate_var_series(y, q05, r05['q_aci'], alpha=0.05, warmup=warmup)
        m01 = evaluate_var_series(y, q01, r01['q_aci'], alpha=0.01, warmup=warmup)
        aci_results_05.append({'gamma': g, 'final_eta': r05['final_eta'],
                               'final_breach_rate': r05['final_breach_rate'],
                               **{k: v for k, v in m05['adj'].items()}})
        aci_results_01.append({'gamma': g, 'final_eta': r01['final_eta'],
                               'final_breach_rate': r01['final_breach_rate'],
                               **{k: v for k, v in m01['adj'].items()}})
        df[f'var_05_aci_g{g}'] = r05['q_aci']
        df[f'var_01_aci_g{g}'] = r01['q_aci']
        df[f'eta_05_g{g}'] = r05['eta_path']
        df[f'eta_01_g{g}'] = r01['eta_path']

    # ─── EnbPI sweep on VaR_05 and VaR_01 ──────────────────────────────────
    enbpi_results_05 = []
    enbpi_results_01 = []
    for bs in blocks:
        e05 = F1.enbpi_one_sided_var(y, q05, alpha=0.05, block_size=bs, warmup=warmup)
        e01 = F1.enbpi_one_sided_var(y, q01, alpha=0.01, block_size=bs, warmup=warmup)
        m05 = evaluate_var_series(y, q05, e05['q_enbpi'], alpha=0.05, warmup=warmup)
        m01 = evaluate_var_series(y, q01, e01['q_enbpi'], alpha=0.01, warmup=warmup)
        enbpi_results_05.append({'block_size': bs, **{k: v for k, v in m05['adj'].items()}})
        enbpi_results_01.append({'block_size': bs, **{k: v for k, v in m01['adj'].items()}})
        df[f'var_05_enbpi_b{bs}'] = e05['q_enbpi']
        df[f'var_01_enbpi_b{bs}'] = e01['q_enbpi']

    # ─── Raw baselines ─────────────────────────────────────────────────────
    base_05 = evaluate_var_series(y, q05, q05, alpha=0.05, warmup=warmup)['raw']
    base_01 = evaluate_var_series(y, q01, q01, alpha=0.01, warmup=warmup)['raw']

    # ─── Pick best by Kupiec p-value (closest to centered) ─────────────────
    def best(results, target=0.05):
        # prefer high Kupiec p, and breach_rate within ±20% of target
        def score(r):
            br = r['breach_rate']
            within = abs(br - target) / target < 0.2
            return (r['kupiec_p'], within)
        return max(results, key=score)

    best_aci_05 = best(aci_results_05, 0.05)
    best_aci_01 = best(aci_results_01, 0.01)
    best_enbpi_05 = best(enbpi_results_05, 0.05)
    best_enbpi_01 = best(enbpi_results_01, 0.01)

    # ─── Bear date evaluation on best ACI variants ─────────────────────────
    g05_best = best_aci_05['gamma']
    g01_best = best_aci_01['gamma']
    bear_evals = {}
    for label, dstr in KEY_BEAR_DATES.items():
        td = pd.to_datetime(dstr)
        diffs = (df['Date'] - td).abs()
        if diffs.min() > pd.Timedelta(days=3):
            bear_evals[label] = {'in_test_set': False}
            continue
        idx = diffs.idxmin()
        row = df.iloc[idx]
        bear_evals[label] = {
            'in_test_set': True,
            'forecast_date': str(row['Date'].date()),
            'y_actual': float(row['y_actual']),
            'var_05_raw': float(row['var_05']),
            'var_05_aci_best': float(row[f'var_05_aci_g{g05_best}']),
            'var_01_raw': float(row['var_01']),
            'var_01_aci_best': float(row[f'var_01_aci_g{g01_best}']),
        }

    summary = {
        'method': 'Conformal post-hoc (ACI + EnbPI) on v3-fast Hansen',
        'base_path': str(base_path),
        'n_obs_total': len(df),
        'warmup': warmup,
        'baseline_raw': {'var_05': base_05, 'var_01': base_01},
        'aci_sweep_var_05': aci_results_05,
        'aci_sweep_var_01': aci_results_01,
        'enbpi_sweep_var_05': enbpi_results_05,
        'enbpi_sweep_var_01': enbpi_results_01,
        'best_aci_var_05': best_aci_05,
        'best_aci_var_01': best_aci_01,
        'best_enbpi_var_05': best_enbpi_05,
        'best_enbpi_var_01': best_enbpi_01,
        'bear_date_evaluations': bear_evals,
    }

    # Save
    df.to_parquet(output_dir / "conformal_predictions.parquet")
    with open(output_dir / "conformal_summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)

    # ─── Pretty print ──────────────────────────────────────────────────────
    print(f"\n=== Raw Hansen baseline (test n={base_05.get('breach_rate') and len(y)-warmup}) ===")
    print(f"  VaR_05: breach={base_05['breach_rate']*100:.2f}% kupiec_p={base_05['kupiec_p']:.4f} pass={base_05['kupiec_pass']} pinball={base_05['pinball']:.5f}")
    print(f"  VaR_01: breach={base_01['breach_rate']*100:.2f}% kupiec_p={base_01['kupiec_p']:.4f} pass={base_01['kupiec_pass']} pinball={base_01['pinball']:.5f}")

    print(f"\n=== ACI sweep on VaR_05 (target 5%) ===")
    for r in aci_results_05:
        flag = '✓' if r['kupiec_pass'] else '✗'
        print(f"  γ={r['gamma']:.4f}  η_final={r['final_eta']:+.4f}  breach={r['breach_rate']*100:.2f}% "
              f"kupiec_p={r['kupiec_p']:.4f} {flag}  cc_p={r['cc_p']:.4f}  pinball={r['pinball']:.5f}  mean_VaR={r['mean_var']:.3f}")

    print(f"\n=== ACI sweep on VaR_01 (target 1%) ===")
    for r in aci_results_01:
        flag = '✓' if r['kupiec_pass'] else '✗'
        print(f"  γ={r['gamma']:.4f}  η_final={r['final_eta']:+.4f}  breach={r['breach_rate']*100:.2f}% "
              f"kupiec_p={r['kupiec_p']:.4f} {flag}  cc_p={r['cc_p']:.4f}  pinball={r['pinball']:.5f}  mean_VaR={r['mean_var']:.3f}")

    print(f"\n=== EnbPI sweep on VaR_05 (target 5%) ===")
    for r in enbpi_results_05:
        flag = '✓' if r['kupiec_pass'] else '✗'
        print(f"  block={r['block_size']:>4}  breach={r['breach_rate']*100:.2f}% "
              f"kupiec_p={r['kupiec_p']:.4f} {flag}  cc_p={r['cc_p']:.4f}  pinball={r['pinball']:.5f}  mean_VaR={r['mean_var']:.3f}")

    print(f"\n=== EnbPI sweep on VaR_01 (target 1%) ===")
    for r in enbpi_results_01:
        flag = '✓' if r['kupiec_pass'] else '✗'
        print(f"  block={r['block_size']:>4}  breach={r['breach_rate']*100:.2f}% "
              f"kupiec_p={r['kupiec_p']:.4f} {flag}  cc_p={r['cc_p']:.4f}  pinball={r['pinball']:.5f}  mean_VaR={r['mean_var']:.3f}")

    print(f"\n=== BEST ===")
    print(f"  ACI VaR_05: γ={best_aci_05['gamma']}  breach={best_aci_05['breach_rate']*100:.2f}% kupiec_p={best_aci_05['kupiec_p']:.4f}")
    print(f"  ACI VaR_01: γ={best_aci_01['gamma']}  breach={best_aci_01['breach_rate']*100:.2f}% kupiec_p={best_aci_01['kupiec_p']:.4f}")
    print(f"  EnbPI VaR_05: bs={best_enbpi_05['block_size']}  breach={best_enbpi_05['breach_rate']*100:.2f}% kupiec_p={best_enbpi_05['kupiec_p']:.4f}")
    print(f"  EnbPI VaR_01: bs={best_enbpi_01['block_size']}  breach={best_enbpi_01['breach_rate']*100:.2f}% kupiec_p={best_enbpi_01['kupiec_p']:.4f}")

    print(f"\n=== Bear date forecasts (raw → ACI-best) ===")
    for k, v in bear_evals.items():
        if not v.get('in_test_set'):
            print(f"  {k:<24} not in test set")
            continue
        y_a = v['y_actual']
        catch_raw = '✓' if y_a < v['var_05_raw'] else '✗'
        catch_adj = '✓' if y_a < v['var_05_aci_best'] else '✗'
        print(f"  {k:<24} y={y_a:+6.2f}% | var_05 {v['var_05_raw']:+5.2f}→{v['var_05_aci_best']:+5.2f} [{catch_raw}→{catch_adj}]")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=str,
                        default='03_models/p1_patch_v3_fast/all_predictions.parquet')
    parser.add_argument('--output', type=str, default='03_models/conformal_v3_fast')
    parser.add_argument('--warmup', type=int, default=252)
    args = parser.parse_args()

    base_path = ROOT / args.base
    output_dir = ROOT / args.output
    run(base_path, output_dir, warmup=args.warmup)


if __name__ == "__main__":
    main()
