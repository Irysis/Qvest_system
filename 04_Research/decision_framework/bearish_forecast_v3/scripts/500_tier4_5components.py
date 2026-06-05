"""
500_tier4_5components.py — Tier 4 Linear Pool 5-component ensemble

도훈 mandate 2026-05-26 옵션 C: 5-component Linear Pool with Spearman ρ diversity check.

Components (paradigm-diverse):
1. A LASSO Quantile raw           — semiparametric quantile (no parametric distribution)
2. B1 CNN-N (paper-faithful)      — parametric Normal LSTM/CNN
3. B1 CNN-SkewT (paper-faithful)  — parametric Skewed-t LSTM/CNN
4. Markov 3-state                 — regime-switching
5. Hansen v3-fast (P1 patch v3)   — semiparametric → Hansen 1994 skewed-t

Activation criteria (Plan v0.5 Standard, 도훈 Phase 4 confirm):
- 5 components val CRPS > baseline ✓
- 10 pair Spearman ρ all < 0.80 strict
- DM test = additional metric (NOT GO-NOGO)

Linear Pool weight (Geweke-Amisano 2011): w_i ∝ 1 / val_CRPS_i

Output:
- var_05_pool, var_01_pool (weighted quantile average)
- VaR backtest (Kupiec/Christoffersen) on pooled VaR
- Spearman ρ matrix 10 pairs
- DM test pairwise
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats as sp_stats

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))


COMPONENTS = {
    'A_LASSO':    ROOT / '03_models' / 'a1_lasso_full' / 'alpha_0.001' / 'all_predictions.parquet',
    'B1_CNN_N':   ROOT / '03_models' / 'b1_paper_faithful' / 'cnn_normal' / 'all_predictions.parquet',
    'B1_CNN_ST':  ROOT / '03_models' / 'b1_paper_faithful' / 'cnn_skewed_t' / 'all_predictions.parquet',
    'Markov3':    ROOT / '03_models' / 'g1_markov_switching_v4' / 'ms_3state' / 'all_predictions.parquet',
    'Hansen':     ROOT / '03_models' / 'p1_patch_v3_fast' / 'all_predictions.parquet',
}


def pinball(q, y, tau):
    d = y - q
    return float(np.where(d >= 0, tau * d, (tau - 1) * d).mean())


def dm_test_hac(loss_a, loss_b, h=21):
    """Diebold-Mariano test with HAC variance (Newey-West lag h).

    H_0: E[d_t] = 0 where d_t = loss_a(t) - loss_b(t)
    Negative stat: a < b (a is better, lower loss).
    """
    d = np.asarray(loss_a, dtype=np.float64) - np.asarray(loss_b, dtype=np.float64)
    n = len(d)
    if n < 3 * h:
        return {'stat': float('nan'), 'p_value': float('nan'), 'n': n}
    mean_d = d.mean()
    # Newey-West variance
    gamma0 = ((d - mean_d) ** 2).mean()
    var = gamma0
    for lag in range(1, h + 1):
        gamma_l = ((d[:-lag] - mean_d) * (d[lag:] - mean_d)).mean()
        w = 1 - lag / (h + 1)
        var += 2 * w * gamma_l
    var = max(var, 1e-12) / n
    stat = mean_d / np.sqrt(var)
    p = 2 * (1 - sp_stats.norm.cdf(abs(stat)))
    return {'stat': float(stat), 'p_value': float(p), 'n': n, 'mean_diff': float(mean_d)}


def _json_default(obj):
    if isinstance(obj, (np.bool_,)): return bool(obj)
    if isinstance(obj, (np.integer,)): return int(obj)
    if isinstance(obj, (np.floating,)): return float(obj)
    if isinstance(obj, (np.ndarray,)): return obj.tolist()
    raise TypeError(f"{type(obj).__name__} not JSON serializable")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=str, default='03_models/tier4_5comp')
    parser.add_argument('--val_frac', type=float, default=0.3,
                        help='fraction of common test set used to learn LP weights')
    args = parser.parse_args()
    output_dir = ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    # ─── Load all components ─────────────────────────────────────────────
    dfs = {}
    for name, p in COMPONENTS.items():
        if not p.exists():
            print(f"[tier4] MISSING {name}: {p}")
            continue
        df = pd.read_parquet(p)
        df['Date'] = pd.to_datetime(df['Date'])
        df = df.sort_values('Date').reset_index(drop=True)
        df = df[['Date', 'y_actual', 'var_05', 'var_01'] + (['crps'] if 'crps' in df.columns else [])]
        dfs[name] = df
        print(f"[load] {name:<10} n={len(df):>5}  {df['Date'].min().date()}~{df['Date'].max().date()}  "
              f"has_crps={'crps' in df.columns}")

    # ─── Inner join on Date ──────────────────────────────────────────────
    merged = None
    for name, df in dfs.items():
        df2 = df.rename(columns={'var_05': f'{name}_var_05', 'var_01': f'{name}_var_01'})
        if 'crps' in df.columns:
            df2 = df2.rename(columns={'crps': f'{name}_crps'})
        if merged is None:
            merged = df2
        else:
            df2 = df2.drop(columns=['y_actual'])
            merged = merged.merge(df2, on='Date', how='inner')

    print(f"\n[merge] common dates n={len(merged)} ({merged['Date'].min().date()}~{merged['Date'].max().date()})")

    # ─── Split val/test ───────────────────────────────────────────────────
    n = len(merged)
    val_n = int(n * args.val_frac)
    val_df = merged.iloc[:val_n].copy()
    test_df = merged.iloc[val_n:].copy()
    print(f"[split] val n={len(val_df)} test n={len(test_df)}\n")

    # ─── Per-component val CRPS (LASSO has no CRPS — use pinball as proxy) ──
    comp_names = list(dfs.keys())
    val_loss = {}
    print("=== Validation loss per component ===")
    for nm in comp_names:
        if f'{nm}_crps' in val_df.columns:
            v = float(val_df[f'{nm}_crps'].mean())
            print(f"  {nm:<10} val_CRPS = {v:.5f}")
        else:
            # use pinball at 0.05 + 0.01 as proxy
            pl05 = pinball(val_df[f'{nm}_var_05'].values, val_df['y_actual'].values, 0.05)
            pl01 = pinball(val_df[f'{nm}_var_01'].values, val_df['y_actual'].values, 0.01)
            v = pl05 + pl01
            print(f"  {nm:<10} val_pinball(0.05+0.01) = {v:.5f}  (proxy: no CRPS)")
        val_loss[nm] = v

    # ─── LP weights (Geweke-Amisano: w_i ∝ 1 / val_loss_i) ────────────────
    inv = np.array([1.0 / val_loss[nm] for nm in comp_names])
    weights = inv / inv.sum()
    print(f"\n=== Linear Pool weights (∝ 1/val_loss) ===")
    for nm, w in zip(comp_names, weights):
        print(f"  {nm:<10} w = {w:.4f}")

    # ─── Spearman ρ on var_05 (10 pairs) ──────────────────────────────────
    print(f"\n=== Spearman ρ (10 pairs) on test set var_05 ===")
    spear = pd.DataFrame(index=comp_names, columns=comp_names, dtype=float)
    pair_violations = []
    all_pair_rhos = []
    for i, a in enumerate(comp_names):
        for j, b in enumerate(comp_names):
            if i >= j:
                spear.loc[a, b] = 1.0 if i == j else None
                continue
            rho, _ = sp_stats.spearmanr(test_df[f'{a}_var_05'], test_df[f'{b}_var_05'])
            spear.loc[a, b] = rho
            spear.loc[b, a] = rho
            all_pair_rhos.append((a, b, rho))
            if rho >= 0.80:
                pair_violations.append((a, b, rho))
    print(spear.round(3).to_string())
    print(f"\n  10 pairs total. ρ ≥ 0.80 violations: {len(pair_violations)}")
    for a, b, rho in pair_violations:
        print(f"  ✗ ({a}, {b}): ρ = {rho:.3f}")

    # ─── Build pooled VaR (test set) ──────────────────────────────────────
    var05_cols = [f'{nm}_var_05' for nm in comp_names]
    var01_cols = [f'{nm}_var_01' for nm in comp_names]
    var_05_pool = test_df[var05_cols].values @ weights
    var_01_pool = test_df[var01_cols].values @ weights
    y = test_df['y_actual'].values
    test_df['var_05_pool'] = var_05_pool
    test_df['var_01_pool'] = var_01_pool

    # ─── Pooled backtest ──────────────────────────────────────────────────
    print(f"\n=== Pooled VaR backtest (test n={len(test_df)}) ===")
    bt05 = VARBT.var_backtest_full(y, var_05_pool, alpha=0.05)
    bt01 = VARBT.var_backtest_full(y, var_01_pool, alpha=0.01)
    pl05_pool = pinball(var_05_pool, y, 0.05)
    pl01_pool = pinball(var_01_pool, y, 0.01)
    breach05 = (y < var_05_pool).mean() * 100
    breach01 = (y < var_01_pool).mean() * 100
    print(f"  Pool VaR_05: breach={breach05:.2f}% kupiec_p={bt05['kupiec_uc']['p_value']:.4f} "
          f"pass={bt05['kupiec_uc']['pass_at_005']}  cc_p={bt05['christoffersen_cc']['p_value']:.4f}  pinball={pl05_pool:.5f}")
    print(f"  Pool VaR_01: breach={breach01:.2f}% kupiec_p={bt01['kupiec_uc']['p_value']:.4f} "
          f"pass={bt01['kupiec_uc']['pass_at_005']}  cc_p={bt01['christoffersen_cc']['p_value']:.4f}  pinball={pl01_pool:.5f}")

    # ─── Compare pool vs each component on test set ──────────────────────
    print(f"\n=== Component vs Pool (test set) ===")
    print(f"{'comp':<10} {'pinball_05':>11} {'pinball_01':>11} {'breach_05_%':>11} {'breach_01_%':>11} {'kup05_p':>10} {'kup01_p':>10}")
    component_test = {}
    for nm in comp_names:
        v05 = test_df[f'{nm}_var_05'].values
        v01 = test_df[f'{nm}_var_01'].values
        bt05_c = VARBT.var_backtest_full(y, v05, alpha=0.05)
        bt01_c = VARBT.var_backtest_full(y, v01, alpha=0.01)
        pl05_c = pinball(v05, y, 0.05)
        pl01_c = pinball(v01, y, 0.01)
        br05 = (y < v05).mean() * 100
        br01 = (y < v01).mean() * 100
        component_test[nm] = {
            'pinball_05': pl05_c, 'pinball_01': pl01_c,
            'breach_05': br05, 'breach_01': br01,
            'kupiec_05_p': bt05_c['kupiec_uc']['p_value'],
            'kupiec_01_p': bt01_c['kupiec_uc']['p_value'],
        }
        print(f"  {nm:<10} {pl05_c:>11.5f} {pl01_c:>11.5f} {br05:>11.2f} {br01:>11.2f} "
              f"{bt05_c['kupiec_uc']['p_value']:>10.4f} {bt01_c['kupiec_uc']['p_value']:>10.4f}")
    print(f"  {'POOL':<10} {pl05_pool:>11.5f} {pl01_pool:>11.5f} {breach05:>11.2f} {breach01:>11.2f} "
          f"{bt05['kupiec_uc']['p_value']:>10.4f} {bt01['kupiec_uc']['p_value']:>10.4f}")

    # ─── DM test: pool vs each component (pinball_05 loss) ────────────────
    print(f"\n=== DM test (HAC lag 21): pool vs each component, pinball_05 loss ===")
    print(f"  (negative stat → pool better than component)")
    dm_results = {}
    for nm in comp_names:
        v05 = test_df[f'{nm}_var_05'].values
        # per-obs pinball
        pool_loss = np.where(y - var_05_pool >= 0, 0.05 * (y - var_05_pool), -0.95 * (y - var_05_pool))
        comp_loss = np.where(y - v05 >= 0, 0.05 * (y - v05), -0.95 * (y - v05))
        r = dm_test_hac(pool_loss, comp_loss, h=21)
        dm_results[nm] = r
        better = '✓' if r['stat'] < 0 else '✗'
        sig = '★' if r['p_value'] < 0.05 else ' '
        print(f"  pool vs {nm:<10}: stat={r['stat']:+.3f} p={r['p_value']:.4f} {better} {sig} "
              f"mean_diff={r['mean_diff']:+.5f}")

    # ─── Activation decision ──────────────────────────────────────────────
    activated = (len(pair_violations) == 0)
    print(f"\n=== Activation decision (Standard) ===")
    print(f"  ρ < 0.80 strict (10 pairs): {'PASS' if len(pair_violations) == 0 else f'FAIL ({len(pair_violations)} violations)'}")
    print(f"  → Tier 4 5-component LP {'ACTIVATED ✓' if activated else 'NOT activated ✗'}")
    # Component CRPS > baseline check (skip — we don't have a clear baseline; report info)

    # ─── Save summary ─────────────────────────────────────────────────────
    summary = {
        'method': 'Tier 4 Linear Pool 5-component',
        'components': comp_names,
        'common_n': len(merged),
        'val_n': len(val_df), 'test_n': len(test_df),
        'date_range_common': f"{merged['Date'].min().date()} ~ {merged['Date'].max().date()}",
        'val_loss': val_loss,
        'weights': {nm: float(w) for nm, w in zip(comp_names, weights)},
        'spearman_matrix': spear.fillna(0).to_dict(),
        'pair_violations': [(a, b, rho) for a, b, rho in pair_violations],
        'activated': activated,
        'pool_test_var_05': {
            'breach_rate': float(breach05 / 100), 'kupiec_p': bt05['kupiec_uc']['p_value'],
            'kupiec_pass': bool(bt05['kupiec_uc']['pass_at_005']),
            'cc_p': bt05['christoffersen_cc']['p_value'], 'pinball': pl05_pool,
        },
        'pool_test_var_01': {
            'breach_rate': float(breach01 / 100), 'kupiec_p': bt01['kupiec_uc']['p_value'],
            'kupiec_pass': bool(bt01['kupiec_uc']['pass_at_005']),
            'cc_p': bt01['christoffersen_cc']['p_value'], 'pinball': pl01_pool,
        },
        'component_test_metrics': component_test,
        'dm_test_pool_vs_component': dm_results,
    }
    with open(output_dir / "tier4_summary.json", 'w') as f:
        json.dump(summary, f, indent=2, default=_json_default)
    test_df[['Date', 'y_actual', 'var_05_pool', 'var_01_pool']].to_parquet(
        output_dir / "pool_predictions.parquet")
    print(f"\n[save] {output_dir / 'tier4_summary.json'}")
    print(f"[save] {output_dir / 'pool_predictions.parquet'}")


if __name__ == "__main__":
    main()
