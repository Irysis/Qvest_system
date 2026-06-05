"""
310_b1_multi_seed.py — Phase 5a-1 Stage 2: B1 multi-seed hyperparameter sweep

도훈 confirm 2026-05-24 후속: Stage 1 reproduce CRPS +20% gap + ordering near-tie
→ Stage 2 multi-seed (15-seed × top 5 hyperparam) 시도

Two stages:
1. Hyperparameter sweep with 1-seed to find top configurations
2. Top-K × 15-seed averaging for stable CRPS comparison

Configurations swept (initial small grid):
- sequence_length ∈ {10, 30, 60}
- hidden_sizes ∈ {(128, 64, 32), (64, 32, 16)}
- dropout ∈ {0.02, 0.10}
- learning_rate ∈ {0.001, 0.002, 0.005}

Output:
- 03_models/b1_multi_seed/{config_tag}_seed{s}/...
- Aggregate per-config CRPS mean ± std across seeds.
"""
from __future__ import annotations
import argparse
import copy
import json
import sys
import importlib.util
from pathlib import Path
from typing import Optional

import numpy as np
import yaml

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


B1T = _load_module("b1_train", str(ROOT / "scripts" / "300_b1_train.py"))


def _json_default(obj):
    if isinstance(obj, (np.bool_,)):
        return bool(obj)
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating,)):
        return float(obj)
    if isinstance(obj, (np.ndarray,)):
        return obj.tolist()
    raise TypeError(f"Object of type {type(obj).__name__} not JSON serializable")


def make_config_variants(
    seq_lens: Optional[list] = None,
    hidden_strs: Optional[list] = None,
    dropouts: Optional[list] = None,
    lrs: Optional[list] = None,
) -> list:
    """Generate hyperparameter combinations for sweep.

    Default grid (original Stage 2 sweep): seq{10,30,60} × h{(128,64,32),(64,32,16)} × d{0.02,0.10} × lr{0.001,0.002,0.005}
    Override via args for Stage 2 expansion (도훈 mandate 2026-05-24 후속).
    """
    if seq_lens is None:
        seq_lens = [10, 30, 60]
    if hidden_strs is None:
        hidden_strs = ['128_64_32', '64_32_16']
    if dropouts is None:
        dropouts = [0.02, 0.10]
    if lrs is None:
        lrs = [0.001, 0.002, 0.005]
    variants = []
    for seq_len in seq_lens:
        for hidden_str in hidden_strs:
            for dropout in dropouts:
                for lr in lrs:
                    hidden = tuple(int(x) for x in hidden_str.split('_'))
                    variants.append({
                        'seq_len': seq_len,
                        'hidden': hidden,
                        'dropout': dropout,
                        'lr': lr,
                        'tag': f"seq{seq_len}_h{hidden_str}_d{dropout}_lr{lr}",
                    })
    return variants


def run_one_config(
    base_cfg: dict,
    variant: dict,
    seeds: list,
    archs: list,
    dists: list,
    output_dir: Path,
    epochs_override: Optional[int] = None,
) -> dict:
    """Run one hyperparameter variant across multiple seeds."""
    tag = variant['tag']
    print(f"\n[multi_seed] ==== {tag} ====")
    config = copy.deepcopy(base_cfg)
    config['training']['sequence_length'] = variant['seq_len']
    config['training']['learning_rate'] = variant['lr']
    config['architecture']['hidden_sizes'] = list(variant['hidden'])
    config['architecture']['dropout'] = variant['dropout']
    if epochs_override is not None:
        config['training']['epochs'] = epochs_override
        config['training']['early_stopping_patience'] = max(30, epochs_override // 10)

    # Save the variant config
    variant_dir = output_dir / tag
    variant_dir.mkdir(parents=True, exist_ok=True)
    with open(variant_dir / "variant_config.yaml", 'w') as f:
        yaml.dump(config, f)

    per_seed_results = {}
    for seed in seeds:
        seed_dir = variant_dir / f"seed_{seed}"
        seed_dir.mkdir(parents=True, exist_ok=True)
        cfg_path = seed_dir / "config.yaml"
        with open(cfg_path, 'w') as f:
            yaml.dump(config, f)
        try:
            results, pass_dict = B1T.run_b1_baseline(
                cfg_path=str(cfg_path),
                archs=archs,
                dists=dists,
                output_dir=str(seed_dir),
                seed=seed,
            )
            per_seed_results[seed] = {
                'crps_lstm_sstd': results.get('lstm_skewed_t', {}).get('crps_pooled'),
                'crps_lstm_std': results.get('lstm_student_t', {}).get('crps_pooled'),
                'crps_lstm_n': results.get('lstm_normal', {}).get('crps_pooled'),
                'nll_lstm_sstd': results.get('lstm_skewed_t', {}).get('nll_pooled'),
                'nll_lstm_std': results.get('lstm_student_t', {}).get('nll_pooled'),
                'nll_lstm_n': results.get('lstm_normal', {}).get('nll_pooled'),
                'reproduce_pass': pass_dict.get('reproduce_pass', False),
            }
        except Exception as e:
            print(f"  seed {seed} FAILED: {e}")
            per_seed_results[seed] = {'error': str(e)}

    # Aggregate across seeds
    crps_sstd_values = [r['crps_lstm_sstd'] for r in per_seed_results.values()
                        if 'crps_lstm_sstd' in r and r['crps_lstm_sstd'] is not None]
    crps_std_values = [r['crps_lstm_std'] for r in per_seed_results.values()
                       if 'crps_lstm_std' in r and r['crps_lstm_std'] is not None]
    crps_n_values = [r['crps_lstm_n'] for r in per_seed_results.values()
                     if 'crps_lstm_n' in r and r['crps_lstm_n'] is not None]
    nll_sstd_values = [r['nll_lstm_sstd'] for r in per_seed_results.values()
                       if 'nll_lstm_sstd' in r and r['nll_lstm_sstd'] is not None]

    agg = {
        'variant': variant,
        'n_seeds': len(per_seed_results),
        'n_valid': len(crps_sstd_values),
        'crps_lstm_sstd_mean': float(np.mean(crps_sstd_values)) if crps_sstd_values else None,
        'crps_lstm_sstd_std': float(np.std(crps_sstd_values)) if crps_sstd_values else None,
        'crps_lstm_std_mean': float(np.mean(crps_std_values)) if crps_std_values else None,
        'crps_lstm_n_mean': float(np.mean(crps_n_values)) if crps_n_values else None,
        'nll_lstm_sstd_mean': float(np.mean(nll_sstd_values)) if nll_sstd_values else None,
        'ordering_check_seeds': sum(
            1 for s in per_seed_results.values()
            if all(k in s for k in ['crps_lstm_sstd', 'crps_lstm_std', 'crps_lstm_n'])
            and s['crps_lstm_sstd'] is not None
            and s['crps_lstm_sstd'] <= s['crps_lstm_std'] <= s['crps_lstm_n']
        ),
        'per_seed': per_seed_results,
    }
    with open(variant_dir / "aggregate.json", 'w') as f:
        json.dump(agg, f, indent=2, default=_json_default)

    print(f"  CRPS sstd mean={agg['crps_lstm_sstd_mean']} std={agg['crps_lstm_sstd_std']} "
          f"ordering_seeds={agg['ordering_check_seeds']}/{agg['n_valid']}")
    return agg


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/b1_paper_baseline.yaml')
    parser.add_argument('--output', type=str, default='03_models/b1_multi_seed')
    parser.add_argument('--seeds', type=str, default='0,1,2,3,4',
                        help='comma-separated list of seeds. Stage 1 baseline=0; Stage 2=0..14')
    parser.add_argument('--archs', type=str, default='lstm')
    parser.add_argument('--dists', type=str, default='normal,student_t,skewed_t')
    parser.add_argument('--max_variants', type=int, default=8,
                        help='limit variants per call (full sweep = 36)')
    parser.add_argument('--seq_lens', type=str, default=None,
                        help='comma-separated seq_lens override (e.g., "30,60,90")')
    parser.add_argument('--hidden', type=str, default=None,
                        help='comma-separated hidden underscored (e.g., "128_64_32")')
    parser.add_argument('--dropouts', type=str, default=None,
                        help='comma-separated dropouts (e.g., "0.02,0.10")')
    parser.add_argument('--lrs', type=str, default=None,
                        help='comma-separated learning rates (e.g., "0.005,0.01")')
    parser.add_argument('--epochs', type=int, default=None,
                        help='override training.epochs (e.g., 500 for Stage 2 expansion)')
    args = parser.parse_args()

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    with open(cfg_path, 'r') as f:
        base_cfg = yaml.safe_load(f)

    seeds = [int(s) for s in args.seeds.split(',')]
    archs = args.archs.split(',')
    dists = args.dists.split(',')

    seq_lens = [int(x) for x in args.seq_lens.split(',')] if args.seq_lens else None
    hidden_strs = args.hidden.split(',') if args.hidden else None
    dropouts = [float(x) for x in args.dropouts.split(',')] if args.dropouts else None
    lrs = [float(x) for x in args.lrs.split(',')] if args.lrs else None
    variants = make_config_variants(
        seq_lens=seq_lens, hidden_strs=hidden_strs, dropouts=dropouts, lrs=lrs,
    )[:args.max_variants]

    print(f"[multi_seed] CFG: {cfg_path}")
    print(f"[multi_seed] OUT: {output_dir}")
    print(f"[multi_seed] {len(variants)} variants × {len(seeds)} seeds = {len(variants)*len(seeds)} runs")
    print(f"[multi_seed] archs: {archs}  dists: {dists}")

    all_aggregates = []
    for v_idx, variant in enumerate(variants):
        print(f"\n[multi_seed] variant {v_idx+1}/{len(variants)}: {variant['tag']}")
        agg = run_one_config(base_cfg, variant, seeds, archs, dists, output_dir, epochs_override=args.epochs)
        all_aggregates.append(agg)

    # Final summary
    summary_path = output_dir / "all_variants_summary.json"
    with open(summary_path, 'w') as f:
        json.dump(all_aggregates, f, indent=2, default=_json_default)

    # Print top configurations by CRPS-SSTD mean
    valid = [a for a in all_aggregates if a.get('crps_lstm_sstd_mean') is not None]
    valid.sort(key=lambda a: a['crps_lstm_sstd_mean'])
    print("\n" + "=" * 64)
    print(f"TOP 5 configurations (by LSTM-SSTD CRPS mean across {len(seeds)} seeds):")
    print("=" * 64)
    for i, a in enumerate(valid[:5]):
        v = a['variant']
        print(f"#{i+1} {v['tag']} | CRPS_sstd_mean={a['crps_lstm_sstd_mean']:.5f} ± {a['crps_lstm_sstd_std']:.5f} "
              f"| ordering={a['ordering_check_seeds']}/{a['n_valid']}")


if __name__ == "__main__":
    main()
