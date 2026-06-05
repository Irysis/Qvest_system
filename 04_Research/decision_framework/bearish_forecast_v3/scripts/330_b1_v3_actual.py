"""
330_b1_v3_actual.py — Phase 5a-1.B v3 actual use case

도훈 sequence: Option 4 (paper-faithful) PASS → Option 1 (v3 actual use)

도훈 mandate 2026-05-24: B1 paper baseline 먼저 reproduce → alt data 일곱 적용 (ablation)
+ v3 본 목적: "KOSPI 월간 약세 확률 예측"

Two-axis experiment:
  Axis A — Features:
    returns+GKYZ (paper baseline 2 features)
    vs + v2 alt data 8 features (BBVA macro 4 + K200 implied 2 + US sector 2) = 10 features
  Axis B — Horizon:
    1d forward (paper baseline)
    vs 21d forward (v3 actual use, 도훈 mandate "월간")

Result outputs:
- Δ CRPS (alt data effect)
- Δ CRPS (21d vs 1d, normalized)
- Bear date forecast skill (Lehman 2008-09-15, Euro 2011-08-08, COVID 2020-02-19)
- P(r ≤ -5%), P(r ≤ -7%), P(r ≤ -10%) — v3 monthly bear probability

Architecture: CNN paper-faithful (Option 4 PASS baseline)
Distribution: Skewed-t (v3 mandate target dist)
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
import torch
import torch.nn as nn
import yaml
from scipy import stats as sp_stats

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


D = _load_module("distributions", str(ROOT / "03_models" / "distributions.py"))
PF = _load_module("paper_faithful", str(ROOT / "scripts" / "320_b1_paper_faithful.py"))
METRICS = _load_module("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load_module("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load_module("calibration", str(ROOT / "04_evaluation" / "calibration.py"))


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


# ─── Data with v2 alt features ─────────────────────────────────────────────
def load_v3_full_dataset(cfg: dict) -> pd.DataFrame:
    """Load paper KOSPI + v2 alt data 8 features + GKYZ + multi-horizon targets."""
    paper_csv = Path('/tmp/deep_learning_probability/DATA/KOSPI.csv')
    if paper_csv.exists():
        df = pd.read_csv(paper_csv)
        df['Date'] = pd.to_datetime(df['Date'])
        df = df.sort_values('Date').reset_index(drop=True)
    else:
        bm_path = PROJECT_ROOT / cfg['data']['bm_path']
        df = pd.read_parquet(bm_path)
        df = df.rename(columns={'BM_Close': 'Close'})
        df['Date'] = pd.to_datetime(df['Date'])
        df = df.sort_values('Date').reset_index(drop=True)

    df['log_ret'] = np.log(df['Close']).diff()
    df['gkyz_252'] = PF.gkyz_volatility(df, window=252)

    # Multi-horizon forward targets
    horizons = cfg['data'].get('horizons', [1, 21])
    for h in horizons:
        df[f'ret_fwd_{h}d'] = np.log(df['Close'].shift(-h) / df['Close'])

    # Merge v2 alt data — filter to features with sufficient paper-window coverage
    alt_path = PROJECT_ROOT / cfg['data']['alt_features_path']
    alt_cols = []
    if alt_path.exists():
        alt = pd.read_parquet(alt_path)
        alt['Date'] = pd.to_datetime(alt['Date'])
        # Filter to features covering target paper window (2001+ at minimum)
        # EXCLUDE: bbva_sovereign_z (2024+), k200_implied_skew/kurt (2017+)
        excluded = set(cfg['data'].get('exclude_alt_features', ['bbva_sovereign_z']))
        # Auto-detect by required start date
        max_first_valid = pd.to_datetime(cfg['data'].get('alt_max_first_valid', '2002-01-01'))
        for c in [col for col in alt.columns if col != 'Date']:
            if c in excluded:
                continue
            first_valid = alt.dropna(subset=[c])['Date'].min() if alt[c].notna().any() else pd.Timestamp.max
            if first_valid <= max_first_valid:
                alt_cols.append(c)
            else:
                excluded.add(c)
        print(f"[v3] alt features filter: included {len(alt_cols)} = {alt_cols} | excluded {sorted(excluded)}")
        keep_cols = ['Date'] + alt_cols
        df = df.merge(alt[keep_cols], on='Date', how='left')
        # Forward-fill alt features (PIT-safe: only fill future from past)
        for c in alt_cols:
            df[c] = df[c].ffill()
    else:
        print(f"[v3] alt features NOT FOUND at {alt_path}")

    # Filter date range
    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    df = df[(df['Date'] >= date_start) & (df['Date'] <= date_end)].reset_index(drop=True)

    # Drop NaN on essential cols
    essential = ['log_ret', 'gkyz_252'] + [f'ret_fwd_{h}d' for h in horizons]
    df_pre = df.copy()
    df = df.dropna(subset=essential).reset_index(drop=True)
    print(f"[v3] Data after dropna essential: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()})")

    # Percent scale
    if cfg['data'].get('percent_scale', True):
        for c in df.columns:
            if c.startswith(('log_ret', 'gkyz_', 'ret_fwd_')):
                df[c] = df[c] * 100.0

    return df, alt_cols


# ─── Sequence builder (matches paper) ──────────────────────────────────────
def build_sequences_v3(df, seq_len: int, feature_cols: list, target_col: str) -> tuple:
    X_list, y_list, dates = [], [], []
    arr_f = df[feature_cols].values.astype(np.float32)
    arr_y = df[target_col].values.astype(np.float32)
    arr_d = df['Date'].values
    valid_mask = ~np.isnan(arr_f).any(axis=1)
    for i in range(seq_len, len(df)):
        if np.isnan(arr_y[i]) or not valid_mask[i - seq_len:i].all():
            continue
        X_list.append(arr_f[i - seq_len:i])
        y_list.append(arr_y[i])
        dates.append(arr_d[i])
    return np.array(X_list), np.array(y_list), np.array(dates)


# ─── Walk-forward (paper schedule) ─────────────────────────────────────────
def walk_forward(n_total, train_min=2008, test=504):
    windows = []
    train_end = train_min
    while train_end + test <= n_total:
        windows.append((train_end, train_end + test))
        train_end += test
    if train_end < n_total:
        windows.append((train_end, n_total))
    return windows


# ─── Train one config (paper-faithful CNN) ─────────────────────────────────
def train_eval(arch, dist, X_tr, y_tr, X_te, y_te, cfg, device, seed=0):
    """Train paper-faithful CNN, eval on test."""
    torch.manual_seed(seed)
    np.random.seed(seed)

    input_size = X_tr.shape[-1]
    seq_len = X_tr.shape[1]
    if arch == 'cnn':
        model = PF.PaperCNN(input_size=input_size, sequence_length=seq_len, dist_type=dist).to(device)
    elif arch == 'lstm':
        model = PF.PaperLSTM(input_size=input_size, dist_type=dist, dropout=0.02).to(device)
    else:
        raise ValueError(f"Unknown arch: {arch}")

    optimizer = torch.optim.Adam(
        model.parameters(), lr=cfg['training']['learning_rate'],
        weight_decay=cfg['training'].get('weight_decay', 0.002) if arch == 'lstm' else 0.0,
    )
    loss_fn = PF.LOSS_FN[dist]

    val_frac = 0.3333
    n_train = X_tr.shape[0]
    val_n = max(int(n_train * val_frac), 50)
    X_train_in, X_val_in = X_tr[:-val_n], X_tr[-val_n:]
    y_train_in, y_val_in = y_tr[:-val_n], y_tr[-val_n:]
    X_train_t = torch.from_numpy(X_train_in).float().to(device)
    y_train_t = torch.from_numpy(y_train_in).float().to(device)
    X_val_t = torch.from_numpy(X_val_in).float().to(device)
    y_val_t = torch.from_numpy(y_val_in).float().to(device)

    batch_size = cfg['training']['batch_size']
    epochs = cfg['training']['epochs']
    patience = cfg['training']['early_stopping_patience']
    clipnorm = cfg['training'].get('clipnorm', 1.0)

    best_val = float('inf')
    best_state = None
    bad = 0
    n_tr = X_train_t.shape[0]
    for _ep in range(epochs):
        perm = torch.randperm(n_tr, device=device)
        model.train()
        for start in range(0, n_tr, batch_size):
            idx = perm[start:start + batch_size]
            theta = model(X_train_t[idx])
            loss = loss_fn(theta, y_train_t[idx])
            if not torch.isfinite(loss):
                continue
            optimizer.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=clipnorm)
            optimizer.step()
        model.eval()
        with torch.no_grad():
            val_loss = loss_fn(model(X_val_t), y_val_t).item()
        if val_loss < best_val:
            best_val = val_loss
            best_state = {k: v.clone().detach() for k, v in model.state_dict().items()}
            bad = 0
        else:
            bad += 1
            if bad >= patience:
                break
    if best_state:
        model.load_state_dict(best_state)

    model.eval()
    with torch.no_grad():
        theta_te = model(torch.from_numpy(X_te).float().to(device)).cpu().numpy()
    return theta_te, best_val


# ─── Evaluation (per horizon + bear date) ──────────────────────────────────
def evaluate_predictions(theta_pred, y_te, dist, dates_te):
    """Compute CRPS / NLL / VaR + bear probabilities P(r ≤ -X%) per obs."""
    theta_t = torch.from_numpy(theta_pred).float()
    if dist == 'normal':
        mu, sigma = D.unpack_normal(theta_t)
        mu_np, sigma_np = mu.numpy(), sigma.numpy()
        nll_per = 0.5 * math.log(2 * math.pi) + np.log(sigma_np + 1e-8) + 0.5 * ((y_te - mu_np) / (sigma_np + 1e-8)) ** 2
        crps_per = METRICS.crps_normal_np(mu_np, sigma_np, y_te)
        from scipy.stats import norm
        var_05 = mu_np + sigma_np * norm.ppf(0.05)
        var_01 = mu_np + sigma_np * norm.ppf(0.01)
        es_05 = mu_np - sigma_np * sp_stats.norm.pdf(sp_stats.norm.ppf(0.05)) / 0.05
        # Bear probabilities P(r ≤ threshold)
        p_minus_5 = norm.cdf((-5.0 - mu_np) / (sigma_np + 1e-8))
        p_minus_7 = norm.cdf((-7.0 - mu_np) / (sigma_np + 1e-8))
        p_minus_10 = norm.cdf((-10.0 - mu_np) / (sigma_np + 1e-8))
        pit = norm.cdf((y_te - mu_np) / (sigma_np + 1e-8))
    elif dist == 'student_t':
        log_pdf = D.student_t_log_pdf(torch.from_numpy(y_te).float(), *D.unpack_student_t(theta_t))
        nll_per = -log_pdf.numpy()
        samples = D.student_t_sample(*D.unpack_student_t(theta_t), n_samples=2000).numpy()
        crps_per = METRICS.crps_empirical_np(samples, y_te)
        var_05 = np.quantile(samples, 0.05, axis=1)
        var_01 = np.quantile(samples, 0.01, axis=1)
        es_05 = samples[samples < var_05[:, None]].reshape(samples.shape[0], -1).mean(axis=1) if False else np.array([s[s < v].mean() if (s < v).any() else v for s, v in zip(samples, var_05)])
        p_minus_5 = (samples <= -5.0).mean(axis=1)
        p_minus_7 = (samples <= -7.0).mean(axis=1)
        p_minus_10 = (samples <= -10.0).mean(axis=1)
        pit = (samples <= y_te[:, None]).mean(axis=1)
    elif dist == 'skewed_t':
        log_pdf = D.skewed_t_log_pdf(torch.from_numpy(y_te).float(), *D.unpack_skewed_t(theta_t))
        nll_per = -log_pdf.numpy()
        samples = D.skewed_t_sample(*D.unpack_skewed_t(theta_t), n_samples=2000).numpy()
        crps_per = METRICS.crps_empirical_np(samples, y_te)
        var_05 = np.quantile(samples, 0.05, axis=1)
        var_01 = np.quantile(samples, 0.01, axis=1)
        es_05 = np.array([s[s < v].mean() if (s < v).any() else v for s, v in zip(samples, var_05)])
        p_minus_5 = (samples <= -5.0).mean(axis=1)
        p_minus_7 = (samples <= -7.0).mean(axis=1)
        p_minus_10 = (samples <= -10.0).mean(axis=1)
        pit = (samples <= y_te[:, None]).mean(axis=1)
    else:
        raise ValueError(f"dist={dist}")
    return {
        'crps_per_obs': crps_per,
        'nll_per_obs': nll_per,
        'pit_values': pit,
        'var_05': var_05,
        'var_01': var_01,
        'es_05': es_05,
        'p_minus_5': p_minus_5,
        'p_minus_7': p_minus_7,
        'p_minus_10': p_minus_10,
    }


# ─── Main orchestration ────────────────────────────────────────────────────
def run_v3_actual(cfg_path: str, config_combos: list, output_dir: str, seed: int = 0):
    """Run alt data ablation × horizon experiments."""
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"[v3] device: {device}")

    df, alt_cols = load_v3_full_dataset(cfg)

    base_features = ['log_ret', 'gkyz_252']
    seq_len = cfg['training']['sequence_length']
    train_min = cfg['walk_forward']['train_min']
    test_w = cfg['walk_forward']['test_window']

    os.makedirs(output_dir, exist_ok=True)
    all_results = {}

    for combo in config_combos:
        feature_set = combo['feature_set']
        horizon = combo['horizon']
        arch = combo['arch']
        dist = combo['dist']
        tag = f"{arch}_{dist}_h{horizon}_{feature_set}"
        print(f"\n[v3] ====== {tag} ======")

        if feature_set == 'paper_only':
            feats = base_features
        elif feature_set == 'with_alt':
            feats = base_features + alt_cols
        else:
            raise ValueError(f"feature_set={feature_set}")

        target_col = f'ret_fwd_{horizon}d'
        X, y, dates = build_sequences_v3(df, seq_len, feats, target_col)
        print(f"  X={X.shape} y={y.shape} features={feats}")

        windows = walk_forward(len(X), train_min=train_min, test=test_w)
        print(f"  windows: {len(windows)}")

        sub_dir = Path(output_dir) / tag
        sub_dir.mkdir(parents=True, exist_ok=True)
        all_preds = []
        window_metrics = []
        for w_idx, (tr_end, te_end) in enumerate(windows):
            X_tr, y_tr = X[:tr_end], y[:tr_end]
            X_te, y_te = X[tr_end:te_end], y[tr_end:te_end]
            dates_te = dates[tr_end:te_end]

            theta_te, best_val = train_eval(arch, dist, X_tr, y_tr, X_te, y_te, cfg, device, seed=seed)
            ev = evaluate_predictions(theta_te, y_te, dist, dates_te)

            var_05_bt = VARBT.var_backtest_full(y_te, ev['var_05'], alpha=0.05)
            var_01_bt = VARBT.var_backtest_full(y_te, ev['var_01'], alpha=0.01)
            pit_chi = CALIB.pit_chi_square(ev['pit_values'], n_bins=10)

            pred_df = pd.DataFrame({
                'Date': pd.to_datetime(dates_te),
                'y_actual': y_te,
                'crps': ev['crps_per_obs'],
                'nll': ev['nll_per_obs'],
                'pit': ev['pit_values'],
                'var_05': ev['var_05'],
                'var_01': ev['var_01'],
                'es_05': ev['es_05'],
                'p_minus_5pct': ev['p_minus_5'],
                'p_minus_7pct': ev['p_minus_7'],
                'p_minus_10pct': ev['p_minus_10'],
            })
            pred_df.to_parquet(sub_dir / f"window_{w_idx:02d}_predictions.parquet")
            all_preds.append(pred_df)

            window_metrics.append({
                'window_idx': w_idx,
                'crps_mean': float(ev['crps_per_obs'].mean()),
                'nll_mean': float(ev['nll_per_obs'].mean()),
                'n_obs': len(y_te),
                'var_05_kupiec_pass': var_05_bt['kupiec_uc']['pass_at_005'],
                'var_05_cc_pass': var_05_bt['christoffersen_cc']['pass_at_005'],
                'var_01_kupiec_pass': var_01_bt['kupiec_uc']['pass_at_005'],
                'pit_chi_pass': pit_chi['pass_at_005'],
                'best_val_loss': best_val,
            })
            print(f"  w[{w_idx}] CRPS={float(ev['crps_per_obs'].mean()):.5f} "
                  f"NLL={float(ev['nll_per_obs'].mean()):.4f} "
                  f"VaR_05_kupiec={var_05_bt['kupiec_uc']['pass_at_005']} "
                  f"P(-5%)_mean={ev['p_minus_5'].mean():.4f} "
                  f"P(-10%)_mean={ev['p_minus_10'].mean():.4f}")

        full_pred = pd.concat(all_preds, ignore_index=True)
        full_pred.to_parquet(sub_dir / "all_predictions.parquet")

        # Bear date specific evaluation
        bear_evals = {}
        for label, date_str in KEY_BEAR_DATES.items():
            target_date = pd.to_datetime(date_str)
            # Find nearest forecast (forecast on date_t predicts ret_{t+h})
            # Bear event date = realization. forecast_date should be date_str (if it's in test, eval at that date)
            mask = (full_pred['Date'] == target_date)
            if mask.sum() == 0:
                # Find nearest within ±3 days
                diffs = (full_pred['Date'] - target_date).abs()
                if diffs.min() <= pd.Timedelta(days=3):
                    idx = diffs.idxmin()
                    row = full_pred.iloc[idx]
                else:
                    bear_evals[label] = {'in_test_set': False}
                    continue
            else:
                row = full_pred[mask].iloc[0]
            bear_evals[label] = {
                'in_test_set': True,
                'forecast_date': str(row['Date'].date()),
                'y_actual': float(row['y_actual']),
                'p_minus_5pct': float(row['p_minus_5pct']),
                'p_minus_7pct': float(row['p_minus_7pct']),
                'p_minus_10pct': float(row['p_minus_10pct']),
                'var_05_forecast': float(row['var_05']),
                'var_01_forecast': float(row['var_01']),
            }

        var_05_pool = VARBT.var_backtest_full(
            full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05,
            es_forecasts=full_pred['es_05'].values,
        )
        var_01_pool = VARBT.var_backtest_full(
            full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01,
        )
        pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

        all_results[tag] = {
            'config': combo,
            'n_features': len(feats),
            'feature_names': feats,
            'n_test_obs_total': int(len(full_pred)),
            'crps_pooled': float(full_pred['crps'].mean()),
            'nll_pooled': float(full_pred['nll'].mean()),
            'var_05_backtest_pooled': var_05_pool,
            'var_01_backtest_pooled': var_01_pool,
            'pit_chi_square_pooled': pit_pool,
            'window_metrics': window_metrics,
            'bear_date_evaluations': bear_evals,
            'bear_probabilities_summary': {
                'p_minus_5pct_mean': float(full_pred['p_minus_5pct'].mean()),
                'p_minus_5pct_max': float(full_pred['p_minus_5pct'].max()),
                'p_minus_7pct_mean': float(full_pred['p_minus_7pct'].mean()),
                'p_minus_10pct_mean': float(full_pred['p_minus_10pct'].mean()),
                'p_minus_10pct_max': float(full_pred['p_minus_10pct'].max()),
            },
        }
        print(f"[{tag}] POOLED CRPS={all_results[tag]['crps_pooled']:.5f} NLL={all_results[tag]['nll_pooled']:.4f} "
              f"VaR_05_kupiec={var_05_pool['kupiec_uc']['pass_at_005']} "
              f"VaR_05_cc={var_05_pool['christoffersen_cc']['pass_at_005']}")

    metrics_path = Path(output_dir) / "b1_v3_actual_metrics.json"
    with open(metrics_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=_json_default)
    print(f"\n[v3] metrics saved: {metrics_path}")

    # Δ Summary
    print("\n" + "=" * 64)
    print("Δ CRPS Analysis (alt data + horizon effects)")
    print("=" * 64)
    for combo in config_combos:
        tag = f"{combo['arch']}_{combo['dist']}_h{combo['horizon']}_{combo['feature_set']}"
        if tag in all_results:
            r = all_results[tag]
            print(f"{tag:50s} CRPS={r['crps_pooled']:.5f}  "
                  f"P(-5%)mean={r['bear_probabilities_summary']['p_minus_5pct_mean']:.4f}  "
                  f"P(-10%)mean={r['bear_probabilities_summary']['p_minus_10pct_mean']:.4f}  "
                  f"P(-10%)max={r['bear_probabilities_summary']['p_minus_10pct_max']:.4f}")

    return all_results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/b1_v3_actual.yaml')
    parser.add_argument('--output', type=str, default='03_models/b1_v3_actual')
    parser.add_argument('--seed', type=int, default=0)
    parser.add_argument('--combos', type=str, default='all',
                        help='all (4 combos) | paper_only_1d | with_alt_1d | paper_only_21d | with_alt_21d')
    args = parser.parse_args()

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output

    if args.combos == 'all':
        combos = [
            {'arch': 'cnn', 'dist': 'skewed_t', 'horizon': 1, 'feature_set': 'paper_only'},
            {'arch': 'cnn', 'dist': 'skewed_t', 'horizon': 1, 'feature_set': 'with_alt'},
            {'arch': 'cnn', 'dist': 'skewed_t', 'horizon': 21, 'feature_set': 'paper_only'},
            {'arch': 'cnn', 'dist': 'skewed_t', 'horizon': 21, 'feature_set': 'with_alt'},
        ]
    else:
        # Single combo by name
        parts = args.combos.split('_')
        # Expect form like 'paper_only_1d' or 'with_alt_21d'
        if 'paper' in args.combos:
            fs = 'paper_only'
        elif 'with_alt' in args.combos or 'alt' in args.combos:
            fs = 'with_alt'
        else:
            raise ValueError(f"Unknown combos: {args.combos}")
        h = 21 if '21d' in args.combos else 1
        combos = [{'arch': 'cnn', 'dist': 'skewed_t', 'horizon': h, 'feature_set': fs}]

    print(f"[v3] CFG: {cfg_path}")
    print(f"[v3] OUT: {output_dir}")
    print(f"[v3] combos: {combos}")

    run_v3_actual(cfg_path=str(cfg_path), config_combos=combos, output_dir=str(output_dir), seed=args.seed)


if __name__ == "__main__":
    main()
