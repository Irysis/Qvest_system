"""
320_b1_paper_faithful.py — Phase 5a-1.A B1 paper-faithful reproduce

Source: paper notebook https://github.com/jmichankow/deep_learning_probability/blob/main/SCRIPTS/prob_nn.ipynb

Differences from prior 300_b1_train.py (Implementation 진단 결과):
1. **Architecture: CNN** (Conv1D 256 filters + Dropout + MaxPool 3 + Flatten + Dense)
   — paper notebook actual (LSTM blocks commented out)
2. **n_steps = 3** (paper notebook value; paper Table 1 mentions 10 but code = 3)
3. **GKYZ vol 252d** (Garman-Klass-Yang-Zhang) feature, NOT rolling std 22d
4. **Adam lr=0.003, clipnorm=1, batch_size=64** (paper notebook actual)
5. **train_min=2008, test=504** (paper notebook actual, NOT 1008/504)
6. **No z-score standardization** (paper uses raw inputs)
7. **softplus(0.01 × raw) + 1e-3 offset** in distributions.py (already applied)
8. **validation_split=0.3333** (paper)
9. **patience=5** early stopping (paper)
10. **HeUniform initializer** (paper)

Output:
- 03_models/b1_paper_faithful/{arch}_{dist}/...
- 04_evaluation/b1_paper_faithful_metrics.json

Reproduce target: KOSPI LSTM-SSTD CRPS 0.5165 (paper Table 2) — but paper notebook=CNN.
For CNN: paper Table 2 KOSPI CNN-SSTD CRPS = 0.5302.
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
METRICS = _load_module("metrics", str(ROOT / "04_evaluation" / "metrics.py"))
VARBT = _load_module("var_backtest", str(ROOT / "04_evaluation" / "var_backtest.py"))
CALIB = _load_module("calibration", str(ROOT / "04_evaluation" / "calibration.py"))


LOSS_FN = {
    'normal': D.normal_nll,
    'student_t': D.student_t_nll,
    'skewed_t': D.skewed_t_nll,
}

DIST_P_COUNT = {'normal': 2, 'student_t': 3, 'skewed_t': 4}


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


# ─── GKYZ volatility (Garman-Klass-Yang-Zhang) ──────────────────────────────
def gkyz_volatility(df: pd.DataFrame, window: int = 252) -> np.ndarray:
    """Garman-Klass-Yang-Zhang volatility estimator.

    Combines overnight, opening drift, intraday OHLC info.
    Source: Yang-Zhang 2000, used in paper notebook (in_seq4 = vGKYZ_252).

    Reference formula:
        σ²_YZ = σ²_overnight + k · σ²_open + (1-k) · σ²_RS
        where σ²_RS is Rogers-Satchell estimator.

    For our benchmark.parquet we only have BM_Close. Use Parkinson-like estimator
    fallback if no OHLC, otherwise compute proper GKYZ if Open/High/Low available.
    """
    if all(c in df.columns for c in ['Open', 'High', 'Low', 'Close']):
        # Proper GKYZ with OHLC
        o = np.log(df['Open'].values)
        h = np.log(df['High'].values)
        low = np.log(df['Low'].values)
        c = np.log(df['Close'].values)
        c_prev = np.concatenate([[np.nan], c[:-1]])

        sigma_overnight_sq = (o - c_prev) ** 2  # log(open_t / close_{t-1})^2
        sigma_open_sq = (c - o) ** 2  # log(close_t / open_t)^2
        sigma_rs = (h - c) * (h - o) + (low - c) * (low - o)  # Rogers-Satchell

        # Yang-Zhang weighting k optimized for window
        k = 0.34 / (1.34 + (window + 1) / (window - 1))
        sigma_yz_sq_per_obs = sigma_overnight_sq + k * sigma_open_sq + (1 - k) * sigma_rs

        # Rolling sum of variance
        sigma_yz = np.full(len(df), np.nan)
        for t in range(window, len(df)):
            window_data = sigma_yz_sq_per_obs[t - window + 1:t + 1]
            if np.isfinite(window_data).sum() >= window // 2:
                var_est = np.nanmean(window_data)
                sigma_yz[t] = np.sqrt(max(var_est, 1e-12))
        return sigma_yz
    else:
        # Fallback: rolling std of log returns
        log_ret = np.log(df['Close']).diff().values
        rv = np.full(len(df), np.nan)
        for t in range(window, len(df)):
            window_data = log_ret[t - window + 1:t + 1]
            if np.isfinite(window_data).sum() >= window // 2:
                rv[t] = np.nanstd(window_data)
        return rv


# ─── Paper-faithful LSTM model (paper Cell 11 commented-out LSTM block) ───
class PaperLSTM(nn.Module):
    """Paper notebook Cell 11 LSTM architecture (commented out but described).

    Paper:
        LSTM(128, activation=LeakyReLU(0.1), kernel_regularizer=l2(0.002), return_sequences=True)
        Dropout(0.02)
        LSTM(64, activation=LeakyReLU(0.1), kernel_regularizer=l2(0.002), return_sequences=True)
        Dropout(0.02)
        LSTM(32, activation=LeakyReLU(0.1), kernel_regularizer=l2(0.002))
        Dropout(0.02)
        Dense(p)

    PyTorch LSTM doesn't expose cell-state activation customization, so we apply
    LeakyReLU between LSTM layers (post-cell activation, closest pragmatic match).
    L2 reg applied via Adam weight_decay in caller.
    """
    def __init__(self, input_size: int, dist_type: str = 'skewed_t', dropout: float = 0.02):
        super().__init__()
        self.p = DIST_P_COUNT[dist_type]
        self.lstm1 = nn.LSTM(input_size, 128, batch_first=True)
        self.dropout1 = nn.Dropout(dropout)
        self.lstm2 = nn.LSTM(128, 64, batch_first=True)
        self.dropout2 = nn.Dropout(dropout)
        self.lstm3 = nn.LSTM(64, 32, batch_first=True)
        self.dropout3 = nn.Dropout(dropout)
        self.leaky_relu = nn.LeakyReLU(0.1)
        self.dense = nn.Linear(32, self.p)
        self._init_weights()

    def _init_weights(self):
        for m in self.modules():
            if isinstance(m, nn.Linear):
                nn.init.kaiming_uniform_(m.weight, a=0.1, mode='fan_in', nonlinearity='leaky_relu')
                if m.bias is not None:
                    nn.init.zeros_(m.bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        h, _ = self.lstm1(x)
        h = self.leaky_relu(h)
        h = self.dropout1(h)
        h, _ = self.lstm2(h)
        h = self.leaky_relu(h)
        h = self.dropout2(h)
        h, _ = self.lstm3(h)
        h = self.leaky_relu(h)
        h = self.dropout3(h)
        h_last = h[:, -1, :]
        theta = self.dense(h_last)
        return theta


# ─── Paper-faithful CNN model ──────────────────────────────────────────────
class PaperCNN(nn.Module):
    """Paper notebook Cell 11 CNN architecture.

    Sequential:
        Conv1D(256, kernel=2, activation='relu', padding='causal')
        Dropout(0.02)
        MaxPool1D(pool_size=3)
        Flatten
        Dense(p)   # p = 2/3/4 per distribution

    HeUniform initializer (seed=0).
    """
    def __init__(self, input_size: int, sequence_length: int = 3, dist_type: str = 'skewed_t'):
        super().__init__()
        self.p = DIST_P_COUNT[dist_type]
        # Conv1D with causal padding: equivalent to PyTorch padding=(kernel-1) on left only
        # Simplification: use padding=1 + slice end (or use Causal padding via F.pad)
        self.conv = nn.Conv1d(input_size, 256, kernel_size=2, padding=1)
        self.dropout = nn.Dropout(0.02)
        self.pool = nn.MaxPool1d(3)
        # Output length after conv (causal pad +1, kernel 2) = T + 1 - 2 + 1 = T
        # After pool: T // 3
        out_len = (sequence_length + 1 - 2 + 1) // 3
        # Handle case where seq=3: conv out = 3, pool out = 1
        out_len = max(1, out_len)
        self.dense = nn.Linear(256 * out_len, self.p)
        self._init_weights()

    def _init_weights(self):
        # HeUniform equivalent (Kaiming uniform with fan_in)
        for m in self.modules():
            if isinstance(m, (nn.Conv1d, nn.Linear)):
                nn.init.kaiming_uniform_(m.weight, a=0, mode='fan_in', nonlinearity='relu')
                if m.bias is not None:
                    nn.init.zeros_(m.bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, T, F) → (B, F, T) for Conv1d
        h = x.permute(0, 2, 1)
        h = self.conv(h)
        # Causal: slice end to keep last T outputs
        T_in = x.shape[1]
        h = h[:, :, :T_in]  # causal trim
        h = torch.relu(h)
        h = self.dropout(h)
        h = self.pool(h)
        h = h.flatten(1)
        theta = self.dense(h)
        return theta


# ─── Data loading (paper-faithful with GKYZ) ───────────────────────────────
def load_kospi_paper_faithful(cfg: dict) -> pd.DataFrame:
    """Load paper KOSPI data (use repo CSV if available, else benchmark.parquet)."""
    paper_csv = Path('/tmp/deep_learning_probability/DATA/KOSPI.csv')
    if paper_csv.exists() and cfg.get('use_paper_data', True):
        df = pd.read_csv(paper_csv)
        df['Date'] = pd.to_datetime(df['Date'])
        df = df.sort_values('Date').reset_index(drop=True)
        df['log_ret'] = np.log(df['Close']).diff()
        # Forward target (1-day)
        df['ret_fwd'] = np.log(df['Close'].shift(-1) / df['Close'])
        # GKYZ vol (proper OHLC)
        df['gkyz_252'] = gkyz_volatility(df, window=252)
    else:
        bm_path = PROJECT_ROOT / cfg['data']['bm_path']
        df = pd.read_parquet(bm_path)
        df['Date'] = pd.to_datetime(df['Date'])
        df = df.sort_values('Date').reset_index(drop=True)
        df = df.rename(columns={'BM_Close': 'Close'})
        df['log_ret'] = np.log(df['Close']).diff()
        df['ret_fwd'] = np.log(df['Close'].shift(-1) / df['Close'])
        # No OHLC fallback → rolling std proxy
        df['gkyz_252'] = gkyz_volatility(df, window=252)

    # Filter
    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    df = df[(df['Date'] >= date_start) & (df['Date'] <= date_end)].reset_index(drop=True)
    df = df.dropna(subset=['log_ret', 'gkyz_252', 'ret_fwd']).reset_index(drop=True)

    # Percent scale on log_ret + ret_fwd (paper uses raw log_ret but appears to use percent based on table magnitudes)
    if cfg['data'].get('percent_scale', True):
        df['log_ret'] = df['log_ret'] * 100.0
        df['ret_fwd'] = df['ret_fwd'] * 100.0
        df['gkyz_252'] = df['gkyz_252'] * 100.0  # also scale vol

    return df


def build_sequences(df: pd.DataFrame, seq_len: int, feature_cols: list, target_col: str = 'ret_fwd') -> tuple:
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


# ─── Walk-forward windows (paper: train_min=2008, fixed step=504) ──────────
def walk_forward_paper(n_total: int, train_min: int = 2008, test: int = 504) -> list:
    windows = []
    train_end = train_min
    while train_end + test <= n_total:
        windows.append((train_end, train_end + test))
        train_end += test
    if train_end < n_total:
        windows.append((train_end, n_total))
    return windows


# ─── Training ──────────────────────────────────────────────────────────────
def train_one(arch: str, dist: str, X_tr, y_tr, cfg: dict, device, seed: int = 0):
    """Paper-faithful train."""
    torch.manual_seed(seed)
    np.random.seed(seed)

    input_size = X_tr.shape[-1]
    seq_len = X_tr.shape[1]

    if arch == 'cnn':
        model = PaperCNN(input_size=input_size, sequence_length=seq_len, dist_type=dist).to(device)
    elif arch == 'lstm':
        model = PaperLSTM(input_size=input_size, dist_type=dist, dropout=0.02).to(device)
    else:
        raise ValueError(f"Unknown arch: {arch}. Use 'cnn' or 'lstm'.")

    # Adam lr=0.003 + clipnorm=1 + l2 reg=0.002 (paper)
    optimizer = torch.optim.Adam(model.parameters(), lr=cfg['training']['learning_rate'], weight_decay=0.002)
    loss_fn = LOSS_FN[dist]

    # validation split 33.3%
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
    bad_epochs = 0

    n_tr_in = X_train_t.shape[0]
    for _ep in range(epochs):
        perm = torch.randperm(n_tr_in, device=device)
        model.train()
        for start in range(0, n_tr_in, batch_size):
            idx = perm[start:start + batch_size]
            xb, yb = X_train_t[idx], y_train_t[idx]
            optimizer.zero_grad()
            theta = model(xb)
            loss = loss_fn(theta, yb)
            if not torch.isfinite(loss):
                continue
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=clipnorm)
            optimizer.step()

        model.eval()
        with torch.no_grad():
            theta_val = model(X_val_t)
            val_loss = loss_fn(theta_val, y_val_t).item()
        if val_loss < best_val:
            best_val = val_loss
            best_state = {k: v.clone().detach() for k, v in model.state_dict().items()}
            bad_epochs = 0
        else:
            bad_epochs += 1
            if bad_epochs >= patience:
                break

    if best_state:
        model.load_state_dict(best_state)
    return model, best_val


def evaluate_window(model, X_te, y_te, dist, device):
    """Evaluate model on test window. Compute CRPS / NLL / VaR backtest / PIT."""
    model.eval()
    with torch.no_grad():
        theta_pred = model(torch.from_numpy(X_te).float().to(device)).cpu().numpy()
    theta_t = torch.from_numpy(theta_pred).float()

    if dist == 'normal':
        mu, sigma = D.unpack_normal(theta_t)
        mu, sigma = mu.numpy(), sigma.numpy()
        nll_per = 0.5 * math.log(2 * math.pi) + np.log(sigma + 1e-8) + 0.5 * ((y_te - mu) / (sigma + 1e-8)) ** 2
        crps_per = METRICS.crps_normal_np(mu, sigma, y_te)
        from scipy.stats import norm
        var_05 = mu + sigma * norm.ppf(0.05)
        var_01 = mu + sigma * norm.ppf(0.01)
        pit = norm.cdf((y_te - mu) / (sigma + 1e-8))
    elif dist == 'student_t':
        log_pdf = D.student_t_log_pdf(torch.from_numpy(y_te).float(), *D.unpack_student_t(theta_t))
        nll_per = -log_pdf.numpy()
        samples = D.student_t_sample(*D.unpack_student_t(theta_t), n_samples=2000).numpy()
        crps_per = METRICS.crps_empirical_np(samples, y_te)
        var_05 = np.quantile(samples, 0.05, axis=1)
        var_01 = np.quantile(samples, 0.01, axis=1)
        pit = (samples <= y_te[:, None]).mean(axis=1)
    elif dist == 'skewed_t':
        log_pdf = D.skewed_t_log_pdf(torch.from_numpy(y_te).float(), *D.unpack_skewed_t(theta_t))
        nll_per = -log_pdf.numpy()
        samples = D.skewed_t_sample(*D.unpack_skewed_t(theta_t), n_samples=2000).numpy()
        crps_per = METRICS.crps_empirical_np(samples, y_te)
        var_05 = np.quantile(samples, 0.05, axis=1)
        var_01 = np.quantile(samples, 0.01, axis=1)
        pit = (samples <= y_te[:, None]).mean(axis=1)
    else:
        raise ValueError(f"Unknown dist: {dist}")

    var_05_bt = VARBT.var_backtest_full(y_te, var_05, alpha=0.05)
    var_01_bt = VARBT.var_backtest_full(y_te, var_01, alpha=0.01)
    pit_chi = CALIB.pit_chi_square(pit, n_bins=10)

    return {
        'crps_per_obs': crps_per,
        'nll_per_obs': nll_per,
        'pit_values': pit,
        'var_05_forecasts': var_05,
        'var_01_forecasts': var_01,
        'var_05_backtest': var_05_bt,
        'var_01_backtest': var_01_bt,
        'pit_chi_square': pit_chi,
    }


def run(cfg_path: str, archs: list, dists: list, output_dir: str, seed: int = 0):
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"[paper_faithful] device: {device}")

    df = load_kospi_paper_faithful(cfg)
    print(f"[paper_faithful] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()}) | features: log_ret + gkyz_252 (paper-faithful)")

    feature_cols = ['log_ret', 'gkyz_252']
    seq_len = cfg['training']['sequence_length']
    X, y, dates = build_sequences(df, seq_len, feature_cols)
    print(f"[paper_faithful] X={X.shape} y={y.shape}")

    train_min = cfg['walk_forward']['train_min']
    test_w = cfg['walk_forward']['test_window']
    windows = walk_forward_paper(len(X), train_min=train_min, test=test_w)
    print(f"[paper_faithful] windows: {len(windows)}")

    os.makedirs(output_dir, exist_ok=True)
    all_results = {}

    for arch in archs:
        for dist in dists:
            tag = f"{arch}_{dist}"
            print(f"\n[paper_faithful] ====== {tag} ======")
            sub_dir = Path(output_dir) / tag
            sub_dir.mkdir(parents=True, exist_ok=True)
            all_preds = []
            window_metrics = []
            for w_idx, (tr_end, te_end) in enumerate(windows):
                X_tr, y_tr = X[:tr_end], y[:tr_end]
                X_te, y_te = X[tr_end:te_end], y[tr_end:te_end]
                dates_te = dates[tr_end:te_end]

                model, best_val = train_one(arch, dist, X_tr, y_tr, cfg, device, seed=seed)
                eval_res = evaluate_window(model, X_te, y_te, dist, device)

                pred_df = pd.DataFrame({
                    'Date': pd.to_datetime(dates_te),
                    'y_actual': y_te,
                    'crps': eval_res['crps_per_obs'],
                    'nll': eval_res['nll_per_obs'],
                    'pit': eval_res['pit_values'],
                    'var_05': eval_res['var_05_forecasts'],
                    'var_01': eval_res['var_01_forecasts'],
                })
                pred_df.to_parquet(sub_dir / f"window_{w_idx:02d}_predictions.parquet")
                all_preds.append(pred_df)

                window_metrics.append({
                    'window_idx': w_idx,
                    'crps_mean': float(eval_res['crps_per_obs'].mean()),
                    'nll_mean': float(eval_res['nll_per_obs'].mean()),
                    'n_obs': len(y_te),
                    'best_val_loss': best_val,
                    'var_05_kupiec_pass': eval_res['var_05_backtest']['kupiec_uc']['pass_at_005'],
                    'var_01_kupiec_pass': eval_res['var_01_backtest']['kupiec_uc']['pass_at_005'],
                    'pit_chi_pass': eval_res['pit_chi_square']['pass_at_005'],
                })
                print(f"  window[{w_idx}] CRPS={float(eval_res['crps_per_obs'].mean()):.5f} "
                      f"NLL={float(eval_res['nll_per_obs'].mean()):.4f} "
                      f"VaR_05={eval_res['var_05_backtest']['kupiec_uc']['pass_at_005']} "
                      f"VaR_01={eval_res['var_01_backtest']['kupiec_uc']['pass_at_005']} "
                      f"PIT={eval_res['pit_chi_square']['pass_at_005']}")

            full_pred = pd.concat(all_preds, ignore_index=True)
            full_pred.to_parquet(sub_dir / "all_predictions.parquet")
            crps_pool = float(full_pred['crps'].mean())
            nll_pool = float(full_pred['nll'].mean())
            var_05_pool = VARBT.var_backtest_full(
                full_pred['y_actual'].values, full_pred['var_05'].values, alpha=0.05
            )
            var_01_pool = VARBT.var_backtest_full(
                full_pred['y_actual'].values, full_pred['var_01'].values, alpha=0.01
            )
            pit_pool = CALIB.pit_chi_square(full_pred['pit'].values, n_bins=10)

            all_results[tag] = {
                'n_test_obs_total': int(len(full_pred)),
                'crps_pooled': crps_pool,
                'nll_pooled': nll_pool,
                'var_05_backtest_pooled': var_05_pool,
                'var_01_backtest_pooled': var_01_pool,
                'pit_chi_square_pooled': pit_pool,
                'window_metrics': window_metrics,
            }
            print(f"[{tag}] POOLED: CRPS={crps_pool:.5f} NLL={nll_pool:.4f} n={len(full_pred)}")

    metrics_path = Path(output_dir) / "b1_paper_faithful_metrics.json"
    with open(metrics_path, 'w') as f:
        json.dump(all_results, f, indent=2, default=_json_default)
    print(f"\n[paper_faithful] metrics saved: {metrics_path}")

    # Reproduce pass check
    print("\n" + "=" * 64)
    paper_target = cfg.get('reproduce_pass_criteria', {}).get('paper_kospi_cnn_sstd_crps', 0.5302)  # CNN-SSTD KOSPI
    tol = cfg.get('reproduce_pass_criteria', {}).get('loose_tolerance', 0.05)
    print(f"Reproduce check (paper CNN-SSTD KOSPI target={paper_target}, ± {tol*100}%)")
    print("=" * 64)
    if 'cnn_skewed_t' in all_results:
        sstd_crps = all_results['cnn_skewed_t']['crps_pooled']
        in_range = paper_target * (1 - tol) <= sstd_crps <= paper_target * (1 + tol)
        print(f"CNN-SSTD CRPS: {sstd_crps:.5f} | in_range: {in_range}")
    if all(k in all_results for k in ['cnn_normal', 'cnn_student_t', 'cnn_skewed_t']):
        n = all_results['cnn_normal']['crps_pooled']
        st = all_results['cnn_student_t']['crps_pooled']
        sst = all_results['cnn_skewed_t']['crps_pooled']
        ordering = sst <= st <= n
        print(f"Ordering: SSTD({sst:.5f}) <= STD({st:.5f}) <= N({n:.5f}): {ordering}")

    return all_results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/b1_paper_faithful.yaml')
    parser.add_argument('--output', type=str, default='03_models/b1_paper_faithful')
    parser.add_argument('--archs', type=str, default='cnn')
    parser.add_argument('--dists', type=str, default='normal,student_t,skewed_t')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output

    print(f"[paper_faithful] CFG: {cfg_path}")
    print(f"[paper_faithful] OUT: {output_dir}")

    run(cfg_path=str(cfg_path), archs=args.archs.split(','), dists=args.dists.split(','),
        output_dir=str(output_dir), seed=args.seed)


if __name__ == "__main__":
    main()
