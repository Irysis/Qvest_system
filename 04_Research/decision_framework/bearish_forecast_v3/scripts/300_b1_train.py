"""
300_b1_train.py — Phase 5a-1.A B1 LSTM paper baseline reproduce

도훈 confirm 2026-05-24:
- Full Phase 5 진행
- B1 paper baseline (수익률 + RV) 먼저 reproduce → alt data ablation Stage 2
- Loose ± 5% (CRPS 0.4907 - 0.5423) + ordering check (LSTM-SSTD < LSTM-N)

Source: Michańków 2025 arXiv:2508.18921
Spec (paper Table 1, AMENDMENT_v0.5 CR-V02):
- LSTM 3-layer 128/64/32 (NOT 2-layer hidden=64)
- Sequence length 10 (NOT 60-120)
- Adam lr=0.002, dropout 0.02, L2 0.002, batch 128, 300 epochs + ES
- Walk-forward expanding window: train_min=1008, test=504, step=504
- Feature: log return + realized volatility 22d (paper baseline, alt data 제외)

Output:
- 03_models/b1_paper_reproduce/{arch}_{dist}/window_{N}_predictions.parquet
- 04_evaluation/b1_paper_metrics.json
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

# ─── Module imports (03_models has leading digit) ─────────────────────────
ROOT = Path(__file__).resolve().parent.parent  # bearish_forecast_v3/
PROJECT_ROOT = ROOT.parent.parent.parent          # Quant_Module_Moltbot/

sys.path.insert(0, str(ROOT))


def _load_module(name: str, path: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None, f"spec load fail: {path}"
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


D = _load_module("distributions", str(ROOT / "03_models" / "distributions.py"))
M = _load_module("b1_lstm_distribution", str(ROOT / "03_models" / "b1_lstm_distribution.py"))
METRICS = _load_module("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load_module("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load_module("calibration", str(ROOT / "04_evaluation" / "calibration.py"))


# ─── Loss functions (delegate to distributions.py) ─────────────────────────
LOSS_FN = {
    'normal': D.normal_nll,
    'student_t': D.student_t_nll,
    'skewed_t': D.skewed_t_nll,
}

CRPS_FN = {
    'normal': D.normal_crps_closed,
    'student_t': lambda theta, y: D.student_t_crps(theta, y, n_samples=1000),
    'skewed_t': lambda theta, y: D.skewed_t_crps(theta, y, n_samples=1000),
}


def _json_default(obj):
    """JSON serializer for numpy types + bool_."""
    import numpy as _np
    if isinstance(obj, (_np.bool_,)):
        return bool(obj)
    if isinstance(obj, (_np.integer,)):
        return int(obj)
    if isinstance(obj, (_np.floating,)):
        return float(obj)
    if isinstance(obj, (_np.ndarray,)):
        return obj.tolist()
    raise TypeError(f"Object of type {type(obj).__name__} not JSON serializable")


# ─── Data loading + sequence construction ──────────────────────────────────
def load_kospi_data(cfg: dict) -> pd.DataFrame:
    """Load benchmark.parquet (KOSPI200 daily) + compute features.

    Target horizon:
        - 'paper' (default): 1-day forward log return (matches Michańków 2025)
        - '21d': 21-day forward log return (v3 monthly bearishness primary)

    Returns:
        DataFrame with columns: Date, BM_Close, log_ret, rv_22d, ret_fwd (forward target)
    """
    bm_path = PROJECT_ROOT / cfg['data']['bm_path']
    bm = pd.read_parquet(bm_path)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)
    # log return (1d, historical)
    bm['log_ret'] = np.log(bm['BM_Close']).diff()
    # realized volatility 22-day rolling std of log returns
    bm['rv_22d'] = bm['log_ret'].rolling(22, min_periods=10).std()
    # Forward target — default 1-day (paper reproduce); switch via cfg['data']['horizon']
    horizon_mode = cfg['data'].get('horizon', 'paper')  # 'paper' = 1d, '21d' = monthly
    if horizon_mode == 'paper':
        h = 1
    elif horizon_mode == '21d':
        h = 21
    else:
        raise ValueError(f"Unknown horizon mode: {horizon_mode}")
    bm['ret_fwd'] = np.log(bm['BM_Close'].shift(-h) / bm['BM_Close'])

    # Filter to paper window
    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    bm = bm[(bm['Date'] >= date_start) & (bm['Date'] <= date_end)].reset_index(drop=True)
    bm = bm.dropna(subset=['log_ret', 'rv_22d', 'ret_fwd']).reset_index(drop=True)

    # Convert log_ret + ret_fwd to percent scale (paper reports CRPS ~0.5 in % unit)
    if cfg['data'].get('percent_scale', True):
        bm['log_ret'] = bm['log_ret'] * 100.0
        bm['rv_22d'] = bm['rv_22d'] * 100.0
        bm['ret_fwd'] = bm['ret_fwd'] * 100.0

    return bm[['Date', 'BM_Close', 'log_ret', 'rv_22d', 'ret_fwd']]


def build_sequences(
    df: pd.DataFrame,
    seq_len: int,
    feature_cols: list,
    target_col: str = 'ret_h_21d',
) -> tuple:
    """Build (X, y, dates) sequences via sliding window.

    Args:
        df: DataFrame with Date + feature_cols + target_col
        seq_len: lookback window
        feature_cols: input features

    Returns:
        X: (N, seq_len, F)
        y: (N,) target at end of sequence
        dates: (N,) forecast date (= sequence end)
    """
    X_list, y_list, dates = [], [], []
    arr_f = df[feature_cols].values.astype(np.float32)
    arr_y = df[target_col].values.astype(np.float32)
    arr_d = df['Date'].values
    for i in range(seq_len, len(df)):
        if np.isnan(arr_y[i]):
            continue
        X_list.append(arr_f[i - seq_len:i])
        y_list.append(arr_y[i])
        dates.append(arr_d[i])
    return np.array(X_list), np.array(y_list), np.array(dates)


# ─── Standardization helpers ───────────────────────────────────────────────
def fit_standardizer(X_train: np.ndarray, y_train: np.ndarray) -> dict:
    """Fit z-score from training data only (PIT-safe).

    Returns:
        {'mu_x': (F,), 'std_x': (F,), 'mu_y': float, 'std_y': float}
    """
    return {
        'mu_x': X_train.reshape(-1, X_train.shape[-1]).mean(axis=0),
        'std_x': X_train.reshape(-1, X_train.shape[-1]).std(axis=0) + 1e-8,
        'mu_y': float(y_train.mean()),
        'std_y': float(y_train.std() + 1e-8),
    }


def apply_standardize(X: np.ndarray, y: np.ndarray, stdz: dict) -> tuple:
    Xz = (X - stdz['mu_x']) / stdz['std_x']
    yz = (y - stdz['mu_y']) / stdz['std_y']
    return Xz, yz


def inverse_standardize_y(y_std: np.ndarray, stdz: dict) -> np.ndarray:
    return y_std * stdz['std_y'] + stdz['mu_y']


# ─── Walk-forward expanding window CV ──────────────────────────────────────
def walk_forward_windows(
    n_total: int,
    train_min: int,
    test_window: int,
    expand_step: int,
) -> list:
    """Yield (train_end, test_end) index pairs."""
    windows = []
    train_end = train_min
    while train_end + test_window <= n_total:
        test_end = train_end + test_window
        windows.append((train_end, test_end))
        train_end += expand_step
    # Final window if any data remains
    if train_end < n_total:
        windows.append((train_end, n_total))
    return windows


# ─── Training loop ─────────────────────────────────────────────────────────
def train_one_window(
    arch: str,
    dist: str,
    X_train_z: np.ndarray,
    y_train_z: np.ndarray,
    X_val_z: np.ndarray,
    y_val_z: np.ndarray,
    cfg: dict,
    device: torch.device,
    seed: int = 0,
) -> tuple:
    """Train one model on one walk-forward window.

    Returns:
        (model, training_history) where history is dict with 'train_loss', 'val_loss' lists
    """
    torch.manual_seed(seed)
    np.random.seed(seed)

    input_size = X_train_z.shape[-1]
    seq_len = X_train_z.shape[1]
    hidden_sizes = tuple(cfg['architecture']['hidden_sizes'])
    dropout = cfg['architecture']['dropout']

    model = M.build_model(
        arch=arch,
        dist_type=dist,
        input_size=input_size,
        sequence_length=seq_len,
        hidden_sizes=hidden_sizes,
        dropout=dropout,
    ).to(device)

    optimizer = torch.optim.Adam(
        model.parameters(),
        lr=cfg['training']['learning_rate'],
        weight_decay=cfg['architecture']['l2_reg'],
    )

    loss_fn = LOSS_FN[dist]

    # Tensors
    X_tr = torch.from_numpy(X_train_z).float().to(device)
    y_tr = torch.from_numpy(y_train_z).float().to(device)
    X_va = torch.from_numpy(X_val_z).float().to(device)
    y_va = torch.from_numpy(y_val_z).float().to(device)

    batch_size = cfg['training']['batch_size']
    epochs = cfg['training']['epochs']
    patience = cfg['training']['early_stopping_patience']

    history = {'train_loss': [], 'val_loss': []}
    best_val = float('inf')
    best_state = None
    bad_epochs = 0

    n_train = X_tr.shape[0]
    for _ep in range(epochs):
        # Shuffle train
        perm = torch.randperm(n_train, device=device)
        model.train()
        train_loss_sum = 0.0
        n_batches = 0
        for start in range(0, n_train, batch_size):
            idx = perm[start:start + batch_size]
            xb, yb = X_tr[idx], y_tr[idx]
            optimizer.zero_grad()
            theta = model(xb)
            loss = loss_fn(theta, yb)
            if not torch.isfinite(loss):
                continue
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
            optimizer.step()
            train_loss_sum += loss.item()
            n_batches += 1
        train_loss_avg = train_loss_sum / max(n_batches, 1)

        # Validation
        model.eval()
        with torch.no_grad():
            theta_val = model(X_va)
            val_loss = loss_fn(theta_val, y_va).item()

        history['train_loss'].append(train_loss_avg)
        history['val_loss'].append(val_loss)

        if val_loss < best_val:
            best_val = val_loss
            best_state = {k: v.clone().detach() for k, v in model.state_dict().items()}
            bad_epochs = 0
        else:
            bad_epochs += 1
            if bad_epochs >= patience:
                break

    if best_state is not None:
        model.load_state_dict(best_state)
    return model, history


def predict_window(
    model: torch.nn.Module,
    X_test_z: np.ndarray,
    device: torch.device,
) -> np.ndarray:
    model.eval()
    with torch.no_grad():
        X = torch.from_numpy(X_test_z).float().to(device)
        theta = model(X)
    return theta.cpu().numpy()


# ─── Evaluation ────────────────────────────────────────────────────────────
def evaluate_window(
    theta_pred: np.ndarray,
    y_test_orig: np.ndarray,
    dist: str,
    stdz: dict,
) -> dict:
    """Compute per-window CRPS / NLL / PIT / VaR backtest in ORIGINAL scale.

    theta_pred is in standardized space (y_z prediction).
    Need to transform to original y scale for evaluation:
    - mu_orig = mu_z * std_y + mu_y
    - sigma_orig = sigma_z * std_y    (for Normal/STD/SSTD)
    """
    # Unpack into original scale via numpy/torch
    theta_t = torch.from_numpy(theta_pred).float()

    if dist == 'normal':
        mu_z, sigma_z = D.unpack_normal(theta_t)
        mu_orig = mu_z.numpy() * stdz['std_y'] + stdz['mu_y']
        sigma_orig = sigma_z.numpy() * stdz['std_y']
        # NLL per obs
        z = (y_test_orig - mu_orig) / (sigma_orig + 1e-8)
        nll_per = 0.5 * math.log(2 * math.pi) + np.log(sigma_orig + 1e-8) + 0.5 * z ** 2
        crps_per = METRICS.crps_normal_np(mu_orig, sigma_orig, y_test_orig)
        # VaR 5%, 1%
        from scipy.stats import norm
        var_05 = mu_orig + sigma_orig * norm.ppf(0.05)
        var_01 = mu_orig + sigma_orig * norm.ppf(0.01)
        # PIT
        pit = norm.cdf((y_test_orig - mu_orig) / (sigma_orig + 1e-8))
    elif dist in ('student_t', 'skewed_t'):
        # Empirical via MC sampling — transform back to original y scale
        y_z_test = (y_test_orig - stdz['mu_y']) / stdz['std_y']
        y_z_t = torch.from_numpy(y_z_test).float()
        # Empirical CRPS via MC samples in original y scale (avoid double scaling)
        if dist == 'student_t':
            samples_z = D.student_t_sample(*D.unpack_student_t(theta_t), n_samples=2000)
            log_pdf = D.student_t_log_pdf(y_z_t, *D.unpack_student_t(theta_t))
        else:
            samples_z = D.skewed_t_sample(*D.unpack_skewed_t(theta_t), n_samples=2000)
            log_pdf = D.skewed_t_log_pdf(y_z_t, *D.unpack_skewed_t(theta_t))
        # NOTE: crps_z is mean. We want per-obs nll for proper aggregation.
        nll_per_z = -log_pdf.numpy()
        # Scale back: NLL_orig per obs = NLL_z + log(std_y)
        nll_per = nll_per_z + math.log(stdz['std_y'])
        # CRPS scale: CRPS_orig = CRPS_z * std_y
        # but we computed CRPS_z as mean — to get per-obs we recompute manually
        samples_orig = samples_z.numpy() * stdz['std_y'] + stdz['mu_y']
        crps_per = METRICS.crps_empirical_np(samples_orig, y_test_orig)
        # VaR via empirical quantiles
        var_05 = np.quantile(samples_orig, 0.05, axis=1)
        var_01 = np.quantile(samples_orig, 0.01, axis=1)
        # PIT
        pit = (samples_orig <= y_test_orig[:, None]).mean(axis=1)
    else:
        raise ValueError(f"Unknown dist: {dist}")

    # VaR backtest
    var_05_bt = VARBT.var_backtest_full(y_test_orig, var_05, alpha=0.05)
    var_01_bt = VARBT.var_backtest_full(y_test_orig, var_01, alpha=0.01)

    # PIT calibration
    pit_chi = CALIB.pit_chi_square(pit, n_bins=10)
    pit_ks = CALIB.pit_ks_test(pit)

    return {
        'crps_mean': float(crps_per.mean()),
        'crps_std': float(crps_per.std()),
        'nll_mean': float(nll_per.mean()),
        'nll_std': float(nll_per.std()),
        'n_obs': int(len(y_test_orig)),
        'var_05_backtest': var_05_bt,
        'var_01_backtest': var_01_bt,
        'pit_chi_square': pit_chi,
        'pit_ks': pit_ks,
        'crps_per_obs': crps_per.tolist(),
        'nll_per_obs': nll_per.tolist(),
        'pit_values': pit.tolist(),
        'var_05_forecasts': var_05.tolist(),
        'var_01_forecasts': var_01.tolist(),
    }


# ─── Main orchestration ────────────────────────────────────────────────────
def run_b1_baseline(cfg_path: str, archs: list, dists: list, output_dir: str, seed: int = 0):
    """Run B1 paper baseline reproduce for given arch × dist combinations."""
    with open(cfg_path, 'r') as f:
        cfg = yaml.safe_load(f)
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"[b1_train] device: {device}")

    df = load_kospi_data(cfg)
    horizon = cfg['data'].get('horizon', 'paper')
    pct = cfg['data'].get('percent_scale', True)
    print(f"[b1_train] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()}) horizon={horizon} percent_scale={pct}")

    feature_cols = cfg['data']['features']['paper_baseline']
    seq_len = cfg['training']['sequence_length']
    X, y, dates = build_sequences(df, seq_len, feature_cols, target_col='ret_fwd')
    print(f"[b1_train] sequences: X={X.shape}, y={y.shape}, dates={dates.shape}")

    wf = cfg['walk_forward']
    windows = walk_forward_windows(
        n_total=len(X),
        train_min=wf['train_min'],
        test_window=wf['test_window'],
        expand_step=wf['expand_step'],
    )
    print(f"[b1_train] walk-forward windows: {len(windows)}")
    for i, (tr_end, te_end) in enumerate(windows):
        print(f"  window[{i}]: train [0, {tr_end}), test [{tr_end}, {te_end})")

    os.makedirs(output_dir, exist_ok=True)

    all_results = {}
    for arch in archs:
        for dist in dists:
            tag = f"{arch}_{dist}"
            print(f"\n[b1_train] ====== {tag} ======")
            sub_dir = Path(output_dir) / tag
            sub_dir.mkdir(parents=True, exist_ok=True)

            window_metrics = []
            all_test_preds = []
            for w_idx, (tr_end, te_end) in enumerate(windows):
                X_tr, y_tr = X[:tr_end], y[:tr_end]
                X_te, y_te = X[tr_end:te_end], y[tr_end:te_end]
                dates_te = dates[tr_end:te_end]

                # Internal val split (last 20% of training)
                val_frac = 0.2
                n_tr = len(X_tr)
                val_n = int(n_tr * val_frac)
                X_train_in, X_val_in = X_tr[:-val_n], X_tr[-val_n:]
                y_train_in, y_val_in = y_tr[:-val_n], y_tr[-val_n:]

                # Standardize from training only
                stdz = fit_standardizer(X_train_in, y_train_in)
                X_train_z, y_train_z = apply_standardize(X_train_in, y_train_in, stdz)
                X_val_z, y_val_z = apply_standardize(X_val_in, y_val_in, stdz)
                X_te_z = (X_te - stdz['mu_x']) / stdz['std_x']

                model, history = train_one_window(
                    arch=arch,
                    dist=dist,
                    X_train_z=X_train_z, y_train_z=y_train_z,
                    X_val_z=X_val_z, y_val_z=y_val_z,
                    cfg=cfg,
                    device=device,
                    seed=seed,
                )

                theta_pred = predict_window(model, X_te_z, device)
                eval_result = evaluate_window(theta_pred, y_te, dist, stdz)
                eval_result['window_idx'] = w_idx
                eval_result['train_end_idx'] = tr_end
                eval_result['test_end_idx'] = te_end
                eval_result['best_val_loss'] = min(history['val_loss']) if history['val_loss'] else None
                eval_result['epochs_used'] = len(history['val_loss'])

                window_metrics.append({
                    'window_idx': w_idx,
                    'crps_mean': eval_result['crps_mean'],
                    'nll_mean': eval_result['nll_mean'],
                    'n_obs': eval_result['n_obs'],
                    'best_val_loss': eval_result['best_val_loss'],
                    'epochs_used': eval_result['epochs_used'],
                })

                # Save per-window predictions
                pred_df = pd.DataFrame({
                    'Date': pd.to_datetime(dates_te),
                    'y_actual': y_te,
                    'crps': eval_result['crps_per_obs'],
                    'nll': eval_result['nll_per_obs'],
                    'pit': eval_result['pit_values'],
                    'var_05': eval_result['var_05_forecasts'],
                    'var_01': eval_result['var_01_forecasts'],
                })
                pred_df.to_parquet(sub_dir / f"window_{w_idx:02d}_predictions.parquet")
                all_test_preds.append(pred_df)

                print(f"  window[{w_idx}] CRPS={eval_result['crps_mean']:.5f} NLL={eval_result['nll_mean']:.4f} "
                      f"VaR_05_pass={eval_result['var_05_backtest']['kupiec_uc']['pass_at_005']} "
                      f"VaR_01_pass={eval_result['var_01_backtest']['kupiec_uc']['pass_at_005']} "
                      f"PIT_chi_pass={eval_result['pit_chi_square']['pass_at_005']} "
                      f"ep={eval_result['epochs_used']}")

            # Aggregate across windows (POOL all test predictions)
            full_pred = pd.concat(all_test_preds, ignore_index=True)
            full_pred.to_parquet(sub_dir / "all_predictions.parquet")
            crps_pooled = float(full_pred['crps'].mean())
            nll_pooled = float(full_pred['nll'].mean())
            # VaR backtest on pooled (concatenated)
            var_05_pool = VARBT.var_backtest_full(
                full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05
            )
            var_01_pool = VARBT.var_backtest_full(
                full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01
            )
            pit_pool_chi = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

            all_results[tag] = {
                'n_test_obs_total': int(len(full_pred)),
                'crps_pooled': crps_pooled,
                'nll_pooled': nll_pooled,
                'var_05_backtest_pooled': var_05_pool,
                'var_01_backtest_pooled': var_01_pool,
                'pit_chi_square_pooled': pit_pool_chi,
                'window_metrics': window_metrics,
            }
            print(f"[{tag}] POOLED: CRPS={crps_pooled:.5f} NLL={nll_pooled:.4f} n={len(full_pred)}")

    # Save aggregate metrics
    metrics_path = Path(output_dir) / "b1_paper_metrics.json"
    with open(metrics_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=_json_default)
    print(f"\n[b1_train] aggregate metrics saved: {metrics_path}")

    # Check reproduce pass criteria (Loose ± 5% + ordering)
    criteria = cfg['reproduce_pass_criteria']
    paper_target = criteria['paper_kospi_lstm_sstd_crps']
    tol = criteria['loose_tolerance']
    range_low = paper_target * (1 - tol)
    range_high = paper_target * (1 + tol)

    print("\n" + "=" * 64)
    print(f"Reproduce Pass Criteria Check (paper target: {paper_target}, ± {tol*100}%)")
    print(f"Range: [{range_low:.4f}, {range_high:.4f}]")
    print("=" * 64)

    pass_dict = {}
    if 'lstm_skewed_t' in all_results:
        sstd_crps = all_results['lstm_skewed_t']['crps_pooled']
        in_range = range_low <= sstd_crps <= range_high
        print(f"LSTM-SSTD CRPS: {sstd_crps:.5f} | in_range: {in_range}")
        pass_dict['lstm_sstd_crps_in_range'] = in_range
        pass_dict['lstm_sstd_crps'] = sstd_crps

    if all(k in all_results for k in ['lstm_normal', 'lstm_student_t', 'lstm_skewed_t']):
        n = all_results['lstm_normal']['crps_pooled']
        st = all_results['lstm_student_t']['crps_pooled']
        sst = all_results['lstm_skewed_t']['crps_pooled']
        # paper expectation: LSTM-SSTD < LSTM-STD < LSTM-N (lower is better)
        ordering = sst <= st <= n
        print(f"Ordering check: LSTM-SSTD ({sst:.5f}) <= LSTM-STD ({st:.5f}) <= LSTM-N ({n:.5f}): {ordering}")
        pass_dict['ordering_check'] = ordering

    pass_dict['reproduce_pass'] = pass_dict.get('lstm_sstd_crps_in_range', False) and pass_dict.get('ordering_check', False)
    print(f"\n>>> Reproduce PASS: {pass_dict['reproduce_pass']}")

    # Save pass result
    with open(Path(output_dir) / "reproduce_pass_result.json", 'w') as f:
        json.dump(pass_dict, f, indent=2, default=_json_default)

    return all_results, pass_dict


# ─── CLI ───────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/b1_paper_baseline.yaml')
    parser.add_argument('--output', type=str, default='03_models/b1_paper_reproduce')
    parser.add_argument('--archs', type=str, default='lstm,cnn',
                        help='comma-separated: lstm,cnn')
    parser.add_argument('--dists', type=str, default='normal,student_t,skewed_t',
                        help='comma-separated: normal,student_t,skewed_t')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    archs = args.archs.split(',')
    dists = args.dists.split(',')

    # Make paths absolute relative to bearish_forecast_v3/
    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output

    print(f"[b1_train] CFG: {cfg_path}")
    print(f"[b1_train] OUT: {output_dir}")
    print(f"[b1_train] archs: {archs}  dists: {dists}  seed: {args.seed}")

    run_b1_baseline(
        cfg_path=str(cfg_path),
        archs=archs,
        dists=dists,
        output_dir=str(output_dir),
        seed=args.seed,
    )


if __name__ == "__main__":
    main()
