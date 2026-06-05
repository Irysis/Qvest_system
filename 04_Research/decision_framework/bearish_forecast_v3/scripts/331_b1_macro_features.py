"""
331_b1_macro_features.py — v3 forward-looking macro features ablation

도훈 mandate 2026-05-25: alt data (backward-looking, BBVA macro proxies)
효과 -2~-8% negative. forward-looking macro 누락이 root cause 가능성 → 시도.

Selected 6 forward-looking macro features (from .cache/fred_macro_wide.parquet):
1. Term_Spread (US 10Y - 2Y) — recession leading indicator (Estrella-Hardouvelis)
2. HY_Spread (US High Yield credit spread) — Gilchrist-Zakrajsek 2012 EBP proxy
3. VIX (CBOE volatility index) — equity volatility expectations
4. Chi_Fin_Cond (Chicago Fed NFCI) — Adrian-Boyarchenko-Giannone 2019 GaR
5. StL_Fin_Stress (St. Louis Fed financial stress) — Bank crisis indicator
6. KRW_USD log return — KR external shock proxy

Combos (4):
- paper_only (log_ret + GKYZ baseline)
- with_alt (paper + alt 5)
- with_macro (paper + macro 6)  ★ NEW
- with_alt_macro (paper + alt 5 + macro 6 = 13 total) ★ NEW

PIT discipline:
- Macro data: t-1 lag (assume published with 1-day delay)
- Forward-fill daily granularity for monthly OECD CLI
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


D = _load("distributions", str(ROOT / "03_models" / "distributions.py"))
PF = _load("pf", str(ROOT / "scripts" / "320_b1_paper_faithful.py"))
METRICS = _load("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load("calibration", str(ROOT / "04_evaluation" / "calibration.py"))


KEY_BEAR_DATES = {
    'Lehman_GFC_2008-09-15': '2008-09-15',
    'Euro_Crisis_2011-08-08': '2011-08-08',
    'COVID_2020-02-19': '2020-02-19',
}

# Selected forward-looking macro features (paper window 2001-2020 full coverage)
# HY_Spread/BBB_Spread는 FRED cache 2023+ only → exclude. Init_Claims로 credit/recession proxy 대체.
MACRO_FEATURES = [
    'Term_Spread',      # US recession indicator (yield curve)
    'VIX',              # equity vol expectation
    'Chi_Fin_Cond',     # financial conditions (Adrian 2019 GaR)
    'StL_Fin_Stress',   # bank financial stress
    'Init_Claims',      # jobless claims (recession leading)
    'KRW_USD_logret',   # KR external shock (computed)
]


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


def load_v3_with_macro(cfg: dict) -> tuple:
    """Load paper KOSPI + GKYZ + alt 5 + macro 6."""
    paper_csv = Path('/tmp/deep_learning_probability/DATA/KOSPI.csv')
    if paper_csv.exists():
        df = pd.read_csv(paper_csv)
    else:
        df = pd.read_parquet(PROJECT_ROOT / cfg['data']['bm_path'])
        df = df.rename(columns={'BM_Close': 'Close'})
    df['Date'] = pd.to_datetime(df['Date'])
    df = df.sort_values('Date').reset_index(drop=True)
    df['log_ret'] = np.log(df['Close']).diff()
    df['gkyz_252'] = PF.gkyz_volatility(df, window=252)

    horizons = cfg['data'].get('horizons', [1, 21])
    for h in horizons:
        df[f'ret_fwd_{h}d'] = np.log(df['Close'].shift(-h) / df['Close'])

    # Alt 5 features
    alt_path = PROJECT_ROOT / cfg['data']['alt_features_path']
    alt_cols = []
    if alt_path.exists():
        alt = pd.read_parquet(alt_path)
        alt['Date'] = pd.to_datetime(alt['Date'])
        excluded = {'bbva_sovereign_z', 'k200_implied_skew_z', 'k200_implied_kurt_z'}
        for c in [col for col in alt.columns if col != 'Date']:
            if c in excluded:
                continue
            first_valid = alt.dropna(subset=[c])['Date'].min() if alt[c].notna().any() else pd.Timestamp.max
            if first_valid <= pd.to_datetime('2002-01-01'):
                alt_cols.append(c)
        keep_alt = ['Date'] + alt_cols
        df = df.merge(alt[keep_alt], on='Date', how='left')
        for c in alt_cols:
            df[c] = df[c].ffill()
        print(f"[macro] alt features: {alt_cols}")

    # FRED macro 5 features (t-1 lag PIT-safe). Paper window full coverage required.
    # HY_Spread/BBB_Spread cache 2023+ only → exclude. Use Init_Claims as recession proxy.
    fred_path = PROJECT_ROOT / cfg['data']['fred_path']
    macro_cols_used = []
    if fred_path.exists():
        fred = pd.read_parquet(fred_path)
        fred['Date'] = pd.to_datetime(fred['Date'])
        fred_subset = ['Date', 'Term_Spread', 'VIX', 'Chi_Fin_Cond', 'StL_Fin_Stress', 'Init_Claims']
        fred_subset = [c for c in fred_subset if c in fred.columns]
        fred = fred[fred_subset]
        for c in fred_subset:
            if c != 'Date':
                fred[c] = fred[c].ffill()
                fred[c] = fred[c].shift(1)  # PIT t-1 lag
                macro_cols_used.append(c)
        df = df.merge(fred, on='Date', how='left')
        # ffill + bfill 보강 (paper window 시작 시점 NaN 안전 처리)
        for c in macro_cols_used:
            df[c] = df[c].ffill().bfill()
        print(f"[macro] FRED features added: {macro_cols_used}")

    # KRW/USD daily log return (KR external shock)
    krw_path = PROJECT_ROOT / cfg['data']['krw_usd_path']
    if krw_path.exists():
        krw = pd.read_parquet(krw_path)
        krw['Date'] = pd.to_datetime(krw['Date'])
        krw = krw.sort_values('Date').reset_index(drop=True)
        krw['KRW_USD_logret'] = np.log(krw['KRW_USD']).diff()
        krw['KRW_USD_logret'] = krw['KRW_USD_logret'].shift(1)  # t-1 lag
        df = df.merge(krw[['Date', 'KRW_USD_logret']], on='Date', how='left')
        df['KRW_USD_logret'] = df['KRW_USD_logret'].ffill().bfill()
        macro_cols_used.append('KRW_USD_logret')
        print(f"[macro] KRW/USD logret added")

    # Filter date range
    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    df = df[(df['Date'] >= date_start) & (df['Date'] <= date_end)].reset_index(drop=True)

    # Drop NaN essentials only (macro/alt forward-filled separately)
    essential = ['log_ret', 'gkyz_252'] + [f'ret_fwd_{h}d' for h in horizons]
    df = df.dropna(subset=essential).reset_index(drop=True)

    # Percent scale on returns + vol
    if cfg['data'].get('percent_scale', True):
        for c in df.columns:
            if c.startswith(('log_ret', 'gkyz_', 'ret_fwd_', 'KRW_USD_logret')):
                df[c] = df[c] * 100.0

    print(f"[macro] Final shape: {df.shape}, Date {df['Date'].min()} ~ {df['Date'].max()}")
    return df, alt_cols, macro_cols_used


def build_sequences(df, seq_len, feature_cols, target_col):
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


def walk_forward(n, train_min=2008, test=504):
    windows = []
    train_end = train_min
    while train_end + test <= n:
        windows.append((train_end, train_end + test))
        train_end += test
    return windows


def train_eval(X_tr, y_tr, X_te, y_te, dist, cfg, device, seed=0):
    torch.manual_seed(seed)
    np.random.seed(seed)

    # ★ Z-score standardization (PIT-safe — training set only).
    # Macro features (Init_Claims, VIX 등)는 raw scale 다양 → 필수.
    # Paper baseline (log_ret + GKYZ)만 사용 시는 둘 다 ~1% scale이라 무관.
    X_tr_flat = X_tr.reshape(-1, X_tr.shape[-1])
    mu_x = X_tr_flat.mean(axis=0)
    std_x = X_tr_flat.std(axis=0) + 1e-8
    X_tr = ((X_tr - mu_x) / std_x).astype(np.float32)
    X_te = ((X_te - mu_x) / std_x).astype(np.float32)
    # y는 percent scale (log return * 100) 그대로 사용 — 학습 target

    model = PF.PaperCNN(input_size=X_tr.shape[-1], sequence_length=X_tr.shape[1], dist_type=dist).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=cfg['training']['learning_rate'])
    loss_fn = PF.LOSS_FN[dist]
    val_n = max(int(X_tr.shape[0] * 0.3333), 50)
    X_train_in, X_val_in = X_tr[:-val_n], X_tr[-val_n:]
    y_train_in, y_val_in = y_tr[:-val_n], y_tr[-val_n:]
    X_train_t = torch.from_numpy(X_train_in).float().to(device)
    y_train_t = torch.from_numpy(y_train_in).float().to(device)
    X_val_t = torch.from_numpy(X_val_in).float().to(device)
    y_val_t = torch.from_numpy(y_val_in).float().to(device)
    batch = cfg['training']['batch_size']
    epochs = cfg['training']['epochs']
    patience = cfg['training']['early_stopping_patience']
    clipnorm = cfg['training'].get('clipnorm', 1.0)
    best_val = float('inf')
    best_state = None
    bad = 0
    for _ in range(epochs):
        perm = torch.randperm(X_train_t.shape[0], device=device)
        model.train()
        for s in range(0, X_train_t.shape[0], batch):
            idx = perm[s:s + batch]
            optimizer.zero_grad()
            theta = model(X_train_t[idx])
            loss = loss_fn(theta, y_train_t[idx])
            if not torch.isfinite(loss):
                continue
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=clipnorm)
            optimizer.step()
        model.eval()
        with torch.no_grad():
            val_loss = loss_fn(model(X_val_t), y_val_t).item()
        if val_loss < best_val:
            best_val = val_loss
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
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


def evaluate(theta_te, y_te, dist):
    theta_t = torch.from_numpy(theta_te).float()
    if dist == 'skewed_t':
        log_pdf = D.skewed_t_log_pdf(torch.from_numpy(y_te).float(), *D.unpack_skewed_t(theta_t))
        samples = D.skewed_t_sample(*D.unpack_skewed_t(theta_t), n_samples=2000).numpy()
    else:
        raise NotImplementedError
    nll_per = -log_pdf.numpy()
    crps_per = METRICS.crps_empirical_np(samples, y_te)
    var_05 = np.quantile(samples, 0.05, axis=1)
    var_01 = np.quantile(samples, 0.01, axis=1)
    p_minus_5 = (samples <= -5.0).mean(axis=1)
    p_minus_7 = (samples <= -7.0).mean(axis=1)
    p_minus_10 = (samples <= -10.0).mean(axis=1)
    pit = (samples <= y_te[:, None]).mean(axis=1)
    return {
        'crps_per_obs': crps_per, 'nll_per_obs': nll_per, 'pit_values': pit,
        'var_05': var_05, 'var_01': var_01,
        'p_minus_5': p_minus_5, 'p_minus_7': p_minus_7, 'p_minus_10': p_minus_10,
    }


def run(cfg_path, combos, output_dir, seed=0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"[macro] device: {device}")

    df, alt_cols, macro_cols = load_v3_with_macro(cfg)
    base_features = ['log_ret', 'gkyz_252']
    seq_len = cfg['training']['sequence_length']
    train_min = cfg['walk_forward']['train_min']
    test_w = cfg['walk_forward']['test_window']

    os.makedirs(output_dir, exist_ok=True)
    all_results = {}

    for combo in combos:
        feature_set = combo['feature_set']
        horizon = combo['horizon']
        if feature_set == 'paper_only':
            feats = base_features
        elif feature_set == 'with_alt':
            feats = base_features + alt_cols
        elif feature_set == 'with_macro':
            feats = base_features + macro_cols
        elif feature_set == 'with_alt_macro':
            feats = base_features + alt_cols + macro_cols
        else:
            raise ValueError(f"feature_set={feature_set}")
        tag = f"cnn_sstd_h{horizon}_{feature_set}"
        print(f"\n[macro] ====== {tag} ({len(feats)} features) ======")

        target_col = f'ret_fwd_{horizon}d'
        X, y, dates = build_sequences(df, seq_len, feats, target_col)
        print(f"  X={X.shape} y={y.shape}")

        windows = walk_forward(len(X), train_min=train_min, test=test_w)
        sub_dir = Path(output_dir) / tag
        sub_dir.mkdir(parents=True, exist_ok=True)

        all_preds = []
        win_metrics = []
        for w_idx, (tr_end, te_end) in enumerate(windows):
            X_tr, y_tr = X[:tr_end], y[:tr_end]
            X_te, y_te = X[tr_end:te_end], y[tr_end:te_end]
            dates_te = dates[tr_end:te_end]
            theta_te, best_val = train_eval(X_tr, y_tr, X_te, y_te, 'skewed_t', cfg, device, seed=seed)
            ev = evaluate(theta_te, y_te, 'skewed_t')

            pred_df = pd.DataFrame({
                'Date': pd.to_datetime(dates_te),
                'y_actual': y_te,
                'crps': ev['crps_per_obs'], 'nll': ev['nll_per_obs'],
                'pit': ev['pit_values'], 'var_05': ev['var_05'], 'var_01': ev['var_01'],
                'p_minus_5pct': ev['p_minus_5'], 'p_minus_7pct': ev['p_minus_7'],
                'p_minus_10pct': ev['p_minus_10'],
            })
            pred_df.to_parquet(sub_dir / f"window_{w_idx:02d}_predictions.parquet")
            all_preds.append(pred_df)

            var_05_bt = VARBT.var_backtest_full(y_te, ev['var_05'], alpha=0.05)
            win_metrics.append({
                'window_idx': w_idx, 'crps_mean': float(ev['crps_per_obs'].mean()),
                'n_obs': len(y_te), 'best_val_loss': best_val,
                'var_05_kupiec_pass': var_05_bt['kupiec_uc']['pass_at_005'],
            })
            print(f"  w[{w_idx}] CRPS={float(ev['crps_per_obs'].mean()):.5f} NLL={float(ev['nll_per_obs'].mean()):.4f} VaR_05={var_05_bt['kupiec_uc']['pass_at_005']} P(-5%)mean={ev['p_minus_5'].mean():.4f} P(-10%)mean={ev['p_minus_10'].mean():.4f}")

        full_pred = pd.concat(all_preds, ignore_index=True)
        full_pred.to_parquet(sub_dir / "all_predictions.parquet")
        var_05_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05)
        var_01_pool = VARBT.var_backtest_full(full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01)
        pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

        bear_evals = {}
        for label, date_str in KEY_BEAR_DATES.items():
            td = pd.to_datetime(date_str)
            mask = full_pred['Date'] == td
            if mask.sum() == 0:
                diffs = (full_pred['Date'] - td).abs()
                if diffs.min() <= pd.Timedelta(days=3):
                    idx = diffs.idxmin()
                    row = full_pred.iloc[idx]
                else:
                    bear_evals[label] = {'in_test_set': False}
                    continue
            else:
                row = full_pred[mask].iloc[0]
            bear_evals[label] = {
                'in_test_set': True, 'forecast_date': str(row['Date'].date()),
                'y_actual': float(row['y_actual']),
                'p_minus_5pct': float(row['p_minus_5pct']),
                'p_minus_7pct': float(row['p_minus_7pct']),
                'p_minus_10pct': float(row['p_minus_10pct']),
            }

        all_results[tag] = {
            'config': combo, 'n_features': len(feats), 'feature_names': feats,
            'n_test_total': int(len(full_pred)),
            'crps_pooled': float(full_pred['crps'].mean()),
            'nll_pooled': float(full_pred['nll'].mean()),
            'var_05_backtest_pooled': var_05_pool,
            'var_01_backtest_pooled': var_01_pool,
            'pit_chi_square_pooled': pit_pool,
            'window_metrics': win_metrics,
            'bear_date_evaluations': bear_evals,
            'bear_probabilities_summary': {
                'p_minus_5pct_mean': float(full_pred['p_minus_5pct'].mean()),
                'p_minus_5pct_max': float(full_pred['p_minus_5pct'].max()),
                'p_minus_10pct_mean': float(full_pred['p_minus_10pct'].mean()),
                'p_minus_10pct_max': float(full_pred['p_minus_10pct'].max()),
            },
        }
        print(f"[{tag}] POOLED CRPS={all_results[tag]['crps_pooled']:.5f} NLL={all_results[tag]['nll_pooled']:.4f} VaR_05_kupiec={var_05_pool['kupiec_uc']['pass_at_005']}")

    out_path = Path(output_dir) / "macro_features_summary.json"
    with open(out_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=_json_default)
    print(f"\n[macro] saved: {out_path}")

    print("\n" + "=" * 64)
    print("Δ CRPS Analysis (vs paper_only baseline)")
    print("=" * 64)
    for h in [1, 21]:
        baseline_tag = f"cnn_sstd_h{h}_paper_only"
        if baseline_tag not in all_results:
            continue
        base_crps = all_results[baseline_tag]['crps_pooled']
        for combo in combos:
            if combo['horizon'] != h:
                continue
            tag = f"cnn_sstd_h{combo['horizon']}_{combo['feature_set']}"
            if tag in all_results:
                r = all_results[tag]
                delta = (r['crps_pooled'] - base_crps) / base_crps * 100
                print(f"  {tag:<45s} CRPS={r['crps_pooled']:.5f}  Δ vs paper_only={delta:+.2f}%  P(-5%)max={r['bear_probabilities_summary']['p_minus_5pct_max']:.4f}  P(-10%)max={r['bear_probabilities_summary']['p_minus_10pct_max']:.4f}")

    return all_results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/b1_macro.yaml')
    parser.add_argument('--output', type=str, default='03_models/b1_macro_features')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output

    combos = []
    for h in [1, 21]:
        for fs in ['paper_only', 'with_alt', 'with_macro', 'with_alt_macro']:
            combos.append({'arch': 'cnn', 'dist': 'skewed_t', 'horizon': h, 'feature_set': fs})

    print(f"[macro] CFG: {cfg_path}")
    print(f"[macro] OUT: {output_dir}")
    print(f"[macro] combos ({len(combos)}): {combos}")
    run(str(cfg_path), combos, str(output_dir), seed=args.seed)


if __name__ == "__main__":
    main()
