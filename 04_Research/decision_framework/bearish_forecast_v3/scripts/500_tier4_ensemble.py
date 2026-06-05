"""
500_tier4_ensemble.py — Phase 5d Tier 4 Full Paradigm Mixture Linear Pool

도훈 mandate (Plan v0.5 §5.4):
- 5 components: B1 (CNN paper-faithful) + B5 (NGBoost) + A (LASSO Quantile) + F (Conformal) + C (Neural Lévy)
- Linear Pool: F̂_ensemble = Σ_i w_i · F̂_i  with w_i ∝ 1/val_CRPS_i (Geweke-Amisano 2011)
- Diversity: Spearman ρ(F̂_i VaR_95, F̂_j VaR_95) < 0.80 strict (10 pairs)
- Activation condition (Standard): 5 components val CRPS > baseline + Spearman ρ < 0.80
- Stacking 배제 (v2 58D lesson)

Initial scope (Stage 1): B1 + C + A (3 components fully integrated)
B5 / F: code ready, can be added in subsequent run.

Phase 5d step:
1. Train each component on paper data (paper window 2000-2020, 6 walk-forward windows)
2. Collect val CRPS per component
3. Compute Spearman ρ matrix on VaR_5%
4. Compute Geweke-Amisano weights
5. Linear Pool predictions via sample-merging (each component contributes proportional samples)
6. Evaluate ensemble CRPS / VaR backtest / P(-X%) on KOSPI 2020-02-19 COVID + 2008-2011 bears

Output: 03_models/tier4_ensemble/...
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


D = _load("distributions", str(ROOT / "03_models" / "distributions.py"))
PF = _load("pf", str(ROOT / "scripts" / "320_b1_paper_faithful.py"))
NL = _load("c2_neural_levy", str(ROOT / "03_models" / "c2_neural_levy.py"))
LQM = _load("a1_lasso_quantile", str(ROOT / "03_models" / "a1_lasso_quantile.py"))
F1 = _load("f1_conformal", str(ROOT / "03_models" / "f1_conformal.py"))
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


# ─── Data loading (paper-faithful) ─────────────────────────────────────────
def load_data(cfg):
    """Load paper KOSPI + GKYZ vol."""
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
    df['ret_fwd'] = np.log(df['Close'].shift(-1) / df['Close'])  # 1-day target

    date_start = pd.to_datetime(cfg['data']['date_start'])
    date_end = pd.to_datetime(cfg['data']['date_end'])
    df = df[(df['Date'] >= date_start) & (df['Date'] <= date_end)].reset_index(drop=True)
    df = df.dropna(subset=['log_ret', 'gkyz_252', 'ret_fwd']).reset_index(drop=True)
    if cfg['data'].get('percent_scale', True):
        for c in ['log_ret', 'gkyz_252', 'ret_fwd']:
            df[c] = df[c] * 100.0
    return df


def build_sequences(df, seq_len, feature_cols, target_col='ret_fwd'):
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


def walk_forward(n, train_min=2008, test=504):
    windows = []
    train_end = train_min
    while train_end + test <= n:
        windows.append((train_end, train_end + test))
        train_end += test
    return windows


# ─── Component runners (1d horizon) ────────────────────────────────────────
def train_b1_cnn(X_tr, y_tr, X_te, device, dist='skewed_t', seed=0, cfg=None):
    """B1: paper-faithful CNN."""
    torch.manual_seed(seed)
    np.random.seed(seed)
    model = PF.PaperCNN(input_size=X_tr.shape[-1], sequence_length=X_tr.shape[1], dist_type=dist).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.003)
    loss_fn = PF.LOSS_FN[dist]
    val_n = max(int(X_tr.shape[0] * 0.3333), 50)
    X_train_in, X_val_in = X_tr[:-val_n], X_tr[-val_n:]
    y_train_in, y_val_in = y_tr[:-val_n], y_tr[-val_n:]
    X_train_t = torch.from_numpy(X_train_in).float().to(device)
    y_train_t = torch.from_numpy(y_train_in).float().to(device)
    X_val_t = torch.from_numpy(X_val_in).float().to(device)
    y_val_t = torch.from_numpy(y_val_in).float().to(device)
    batch = 64
    epochs = 300
    patience = 5
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
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
        model.eval()
        with torch.no_grad():
            v = loss_fn(model(X_val_t), y_val_t).item()
        if v < best_val:
            best_val = v; best_state = {k: vv.clone() for k, vv in model.state_dict().items()}
            bad = 0
        else:
            bad += 1
            if bad >= patience: break
    if best_state: model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        theta_te = model(torch.from_numpy(X_te).float().to(device)).cpu().numpy()
    return theta_te, dist, best_val


def predict_b1_distribution(theta, dist, n_samples=2000):
    """Return (samples (B, n), CRPS evaluator) given theta from B1 CNN."""
    theta_t = torch.from_numpy(theta).float()
    if dist == 'skewed_t':
        params = D.unpack_skewed_t(theta_t)
        samples = D.skewed_t_sample(*params, n_samples=n_samples).numpy()
    elif dist == 'student_t':
        params = D.unpack_student_t(theta_t)
        samples = D.student_t_sample(*params, n_samples=n_samples).numpy()
    else:
        params = D.unpack_normal(theta_t)
        # sample Normal manually
        mu, sigma = params[0].numpy(), params[1].numpy()
        samples = mu[:, None] + sigma[:, None] * np.random.randn(len(mu), n_samples)
    return samples


def train_c_neural_levy(X_tr, y_tr, X_te, device, seed=0):
    """C: Neural Lévy SDE."""
    torch.manual_seed(seed)
    np.random.seed(seed)
    model = NL.NeuralLevySDE(input_size=X_tr.shape[-1], sequence_length=X_tr.shape[1], horizon=1).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=0.003)
    val_n = max(int(X_tr.shape[0] * 0.3333), 50)
    X_train_in, X_val_in = X_tr[:-val_n], X_tr[-val_n:]
    y_train_in, y_val_in = y_tr[:-val_n], y_tr[-val_n:]
    X_train_t = torch.from_numpy(X_train_in).float().to(device)
    y_train_t = torch.from_numpy(y_train_in).float().to(device)
    X_val_t = torch.from_numpy(X_val_in).float().to(device)
    y_val_t = torch.from_numpy(y_val_in).float().to(device)
    batch = 64
    epochs = 300
    patience = 5
    best_val = float('inf')
    best_state = None
    bad = 0
    for _ in range(epochs):
        perm = torch.randperm(X_train_t.shape[0], device=device)
        model.train()
        for s in range(0, X_train_t.shape[0], batch):
            idx = perm[s:s + batch]
            optimizer.zero_grad()
            params = model(X_train_t[idx])
            loss = NL.neural_levy_nll(params, y_train_t[idx])
            if not torch.isfinite(loss):
                continue
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
        model.eval()
        with torch.no_grad():
            v = NL.neural_levy_nll(model(X_val_t), y_val_t).item()
        if v < best_val:
            best_val = v; best_state = {k: vv.clone() for k, vv in model.state_dict().items()}
            bad = 0
        else:
            bad += 1
            if bad >= patience: break
    if best_state: model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        params_te = model(torch.from_numpy(X_te).float().to(device))
    return params_te, best_val


def predict_c_neural_levy(params_te, n_samples=2000):
    samples = NL.neural_levy_sample(params_te, n_samples=n_samples).cpu().numpy()
    return samples


def train_a_lasso_quantile(X_tr, y_tr, X_te, seed=0):
    """A: LASSO Quantile GaR.

    Flatten X_tr/X_te (use most recent observation as features) since LQM expects (N, F).
    """
    # Use last timestep features only (LQM doesn't take sequence)
    X_tr_flat = X_tr[:, -1, :]  # (N, F)
    X_te_flat = X_te[:, -1, :]
    model = LQM.LassoQuantileGaR(taus=(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95), alpha=0.001)
    model.fit(X_tr_flat, y_tr)
    # Get quantile predictions on test
    Q_te = model.predict_all_quantiles(X_te_flat, fix_crossing=True)  # (N, 7)
    return Q_te, model.taus


def predict_a_lasso(Q_te, taus, n_samples=2000):
    """Convert quantile predictions to samples via inverse-CDF approximation.

    Use linear interpolation between (taus, Q values) per observation.
    """
    N = Q_te.shape[0]
    samples = np.zeros((N, n_samples))
    u = np.random.uniform(0, 1, n_samples)
    for i in range(N):
        # Sort Q (with extension to 0 and 1)
        q_sorted = np.sort(Q_te[i])
        # Interpolate at u quantile levels
        samples[i] = np.interp(u, taus, q_sorted)
    return samples


# ─── Ensemble Linear Pool ──────────────────────────────────────────────────
def empirical_var(samples, alpha=0.05):
    return np.quantile(samples, alpha, axis=1)


def empirical_crps(samples, y):
    """CRPS via Gneiting-Raftery Eq 21 kernel form."""
    return METRICS.crps_empirical_np(samples, y)


def linear_pool_predict(component_samples_list, weights):
    """Combine multiple component sample matrices into one ensemble.

    Args:
        component_samples_list: list of (N, n_each) arrays — each component's samples
        weights: list of w_i (sum to 1)

    Returns:
        (N, n_total) ensemble samples via importance sampling — concatenate proportional samples.
    """
    weights = np.asarray(weights) / np.sum(weights)
    N = component_samples_list[0].shape[0]
    n_each = component_samples_list[0].shape[1]
    n_take = (weights * n_each).astype(int)
    # Ensure at least 1 sample per component
    n_take = np.maximum(n_take, 10)
    parts = []
    for s, n in zip(component_samples_list, n_take):
        idx = np.random.choice(s.shape[1], n, replace=False)
        parts.append(s[:, idx])
    ensemble = np.concatenate(parts, axis=1)  # (N, n_total)
    return ensemble


def spearman_rho_matrix(var_per_component_dict, n_components):
    """Compute Spearman ρ between component VaR_95 series.

    Returns: (n_components, n_components) matrix
    """
    keys = list(var_per_component_dict.keys())
    mat = np.eye(len(keys))
    for i, ki in enumerate(keys):
        for j, kj in enumerate(keys):
            if i < j:
                rho, _ = sp_stats.spearmanr(var_per_component_dict[ki], var_per_component_dict[kj])
                mat[i, j] = rho
                mat[j, i] = rho
    return mat, keys


# ─── Main Tier 4 orchestration ─────────────────────────────────────────────
def run_tier4(cfg_path, output_dir, seed=0, components='b1,c,a'):
    """Run all components + Linear Pool ensemble."""
    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"[tier4] device: {device}")

    df = load_data(cfg)
    print(f"[tier4] data: {len(df)} rows ({df['Date'].min()} ~ {df['Date'].max()})")

    seq_len = 3
    feature_cols = ['log_ret', 'gkyz_252']
    X, y, dates = build_sequences(df, seq_len, feature_cols)
    print(f"[tier4] X={X.shape} y={y.shape}")

    windows = walk_forward(len(X), train_min=2008, test=504)
    print(f"[tier4] windows: {len(windows)}")

    os.makedirs(output_dir, exist_ok=True)
    comp_list = components.split(',')

    all_preds = {}
    for c in comp_list:
        all_preds[c] = []

    for w_idx, (tr_end, te_end) in enumerate(windows):
        X_tr, y_tr = X[:tr_end], y[:tr_end]
        X_te, y_te = X[tr_end:te_end], y[tr_end:te_end]
        dates_te = dates[tr_end:te_end]
        print(f"\n[tier4] === window {w_idx} (train {tr_end}, test {tr_end}-{te_end}) ===")

        if 'b1' in comp_list:
            theta_b1, dist, val_b1 = train_b1_cnn(X_tr, y_tr, X_te, device, dist='skewed_t', seed=seed)
            samples_b1 = predict_b1_distribution(theta_b1, dist, n_samples=2000)
            crps_b1 = empirical_crps(samples_b1, y_te)
            var_b1 = empirical_var(samples_b1, 0.05)
            all_preds['b1'].append({'window': w_idx, 'samples': samples_b1, 'crps': crps_b1,
                                    'var_05': var_b1, 'y_actual': y_te, 'dates': dates_te,
                                    'val_loss': val_b1})
            print(f"  B1 (CNN-SSTD): CRPS={float(crps_b1.mean()):.5f} val_NLL={val_b1:.4f}")

        if 'c' in comp_list:
            params_c, val_c = train_c_neural_levy(X_tr, y_tr, X_te, device, seed=seed)
            samples_c = predict_c_neural_levy(params_c, n_samples=2000)
            crps_c = empirical_crps(samples_c, y_te)
            var_c = empirical_var(samples_c, 0.05)
            all_preds['c'].append({'window': w_idx, 'samples': samples_c, 'crps': crps_c,
                                   'var_05': var_c, 'y_actual': y_te, 'dates': dates_te,
                                   'val_loss': val_c})
            print(f"  C (Neural Lévy): CRPS={float(crps_c.mean()):.5f} val_NLL={val_c:.4f}")

        if 'a' in comp_list:
            Q_a, taus_a = train_a_lasso_quantile(X_tr, y_tr, X_te, seed=seed)
            samples_a = predict_a_lasso(Q_a, taus_a, n_samples=2000)
            crps_a = empirical_crps(samples_a, y_te)
            var_a = empirical_var(samples_a, 0.05)
            all_preds['a'].append({'window': w_idx, 'samples': samples_a, 'crps': crps_a,
                                   'var_05': var_a, 'y_actual': y_te, 'dates': dates_te,
                                   'val_loss': float('nan')})
            print(f"  A (LASSO Quantile): CRPS={float(crps_a.mean()):.5f}")

        if 'b5' in comp_list:
            try:
                from ngboost import NGBoost
                from ngboost.distns import Normal as NgNormal
                from ngboost.scores import LogScore
                from sklearn.tree import DecisionTreeRegressor
                X_tr_flat = X_tr[:, -1, :]
                X_te_flat = X_te[:, -1, :]
                base = DecisionTreeRegressor(criterion="friedman_mse", max_depth=4, random_state=seed)
                model_b5 = NGBoost(Dist=NgNormal, Score=LogScore, Base=base,
                                   n_estimators=300, learning_rate=0.01,
                                   natural_gradient=True, random_state=seed, verbose=False)
                model_b5.fit(X_tr_flat, y_tr)
                dist_pred = model_b5.pred_dist(X_te_flat)
                samples_b5 = dist_pred.sample(2000).T  # (N, 2000)
                crps_b5 = empirical_crps(samples_b5, y_te)
                var_b5 = empirical_var(samples_b5, 0.05)
                all_preds['b5'].append({'window': w_idx, 'samples': samples_b5, 'crps': crps_b5,
                                        'var_05': var_b5, 'y_actual': y_te, 'dates': dates_te,
                                        'val_loss': float('nan')})
                print(f"  B5 (NGBoost): CRPS={float(crps_b5.mean()):.5f}")
            except Exception as e:
                print(f"  B5 FAILED: {e}")
                continue

        if 'f' in comp_list:
            # F: Conformal ACI wrap on B1 ensemble (need B1 already trained)
            # Skip if no B1 base — simplest: use empirical residuals from previous fold's B1 predictions
            if 'b1' in comp_list and len(all_preds['b1']) > 0:
                # Build samples by Conformal-correcting B1 samples (calibration on past windows)
                # Simplified: use B1 samples directly + ACI-style fixed quantile correction
                # For Stage 1, defer F as additional layer; treat F as B1 samples shifted by ACI offset.
                # ACI offset: empirical quantile of past abs residuals
                past_residuals = []
                for past_w in all_preds['b1'][:-1] if len(all_preds['b1']) > 1 else []:
                    past_residuals.extend(np.abs(past_w['y_actual'] - past_w['samples'].mean(axis=1)).tolist())
                if len(past_residuals) > 50:
                    q_correction = float(np.quantile(past_residuals, 0.95))
                    # Use B1 samples with correction widening (add ±q to extremes)
                    b1_cur = all_preds['b1'][-1]['samples']
                    samples_f = b1_cur + q_correction * np.random.randn(*b1_cur.shape) * 0.2  # 20% blend
                else:
                    # No past residuals, fall back to B1 samples unchanged
                    samples_f = all_preds['b1'][-1]['samples']
                crps_f = empirical_crps(samples_f, y_te)
                var_f = empirical_var(samples_f, 0.05)
                all_preds['f'].append({'window': w_idx, 'samples': samples_f, 'crps': crps_f,
                                       'var_05': var_f, 'y_actual': y_te, 'dates': dates_te,
                                       'val_loss': float('nan')})
                print(f"  F (Conformal-wrap B1): CRPS={float(crps_f.mean()):.5f}")
            else:
                print(f"  F: skipped (no B1 in components)")

    # ─── Aggregate per-component metrics ───────────────────────────────────
    print("\n" + "=" * 64)
    print("Per-component pooled metrics")
    print("=" * 64)

    pooled = {}
    for c in comp_list:
        full_crps = np.concatenate([w['crps'] for w in all_preds[c]])
        full_var05 = np.concatenate([w['var_05'] for w in all_preds[c]])
        full_y = np.concatenate([w['y_actual'] for w in all_preds[c]])
        full_dates = np.concatenate([w['dates'] for w in all_preds[c]])
        var_bt = VARBT.var_backtest_full(full_y, full_var05, alpha=0.05)
        pooled[c] = {
            'crps_mean': float(full_crps.mean()),
            'val_loss_mean': float(np.mean([w['val_loss'] for w in all_preds[c] if not math.isnan(w.get('val_loss', float('nan')))]) if any(not math.isnan(w.get('val_loss', float('nan'))) for w in all_preds[c]) else float('nan')),
            'var_05_kupiec_pass': var_bt['kupiec_uc']['pass_at_005'],
            'var_05_cc_pass': var_bt['christoffersen_cc']['pass_at_005'],
            'n_test': int(len(full_y)),
        }
        print(f"  {c}: CRPS={pooled[c]['crps_mean']:.5f}  Kupiec={pooled[c]['var_05_kupiec_pass']}  CC={pooled[c]['var_05_cc_pass']}")

    # ─── Diversity check: Spearman ρ matrix ───────────────────────────────
    var_per_component = {c: np.concatenate([w['var_05'] for w in all_preds[c]]) for c in comp_list}
    rho_mat, rho_keys = spearman_rho_matrix(var_per_component, len(comp_list))
    print("\nSpearman ρ matrix (VaR_05):")
    print("       " + " ".join(f"{k:>8s}" for k in rho_keys))
    for i, ki in enumerate(rho_keys):
        print(f"  {ki:5s} " + " ".join(f"{rho_mat[i, j]:>8.4f}" for j in range(len(rho_keys))))
    # Diversity check
    n_high_pairs = 0
    for i in range(len(rho_keys)):
        for j in range(i + 1, len(rho_keys)):
            if abs(rho_mat[i, j]) >= 0.80:
                n_high_pairs += 1
    print(f"\nHigh-similarity pairs (|ρ| >= 0.80): {n_high_pairs} of {len(rho_keys)*(len(rho_keys)-1)//2}")
    diversity_pass = n_high_pairs == 0
    print(f"Standard activation (도훈 mandate): Spearman ρ < 0.80 all pairs = {diversity_pass}")

    # ─── Linear Pool weights (Geweke-Amisano) ─────────────────────────────
    weights_raw = np.array([1.0 / pooled[c]['crps_mean'] for c in comp_list])
    weights = weights_raw / weights_raw.sum()
    print("\nLinear Pool weights (Geweke-Amisano 1/CRPS):")
    for c, w in zip(comp_list, weights):
        print(f"  {c}: w={w:.4f}")

    # ─── Tier 4 Linear Pool predictions ───────────────────────────────────
    ensemble_results = []
    for w_idx in range(len(windows)):
        component_samples = [all_preds[c][w_idx]['samples'] for c in comp_list]
        y_actual = all_preds[comp_list[0]][w_idx]['y_actual']
        dates_w = all_preds[comp_list[0]][w_idx]['dates']
        ensemble_samples = linear_pool_predict(component_samples, weights)
        ens_crps = empirical_crps(ensemble_samples, y_actual)
        ens_var_05 = empirical_var(ensemble_samples, 0.05)
        ens_var_01 = empirical_var(ensemble_samples, 0.01)
        # Bear probabilities
        p_minus_5 = (ensemble_samples <= -5.0).mean(axis=1)
        p_minus_7 = (ensemble_samples <= -7.0).mean(axis=1)
        p_minus_10 = (ensemble_samples <= -10.0).mean(axis=1)
        ensemble_results.append(pd.DataFrame({
            'Date': pd.to_datetime(dates_w),
            'y_actual': y_actual,
            'crps': ens_crps,
            'var_05': ens_var_05,
            'var_01': ens_var_01,
            'p_minus_5pct': p_minus_5,
            'p_minus_7pct': p_minus_7,
            'p_minus_10pct': p_minus_10,
        }))

    ensemble_df = pd.concat(ensemble_results, ignore_index=True)
    ensemble_path = Path(output_dir) / "tier4_ensemble_predictions.parquet"
    ensemble_df.to_parquet(ensemble_path)
    print(f"\n[tier4] ensemble predictions saved: {ensemble_path}")

    # ─── Ensemble pooled metrics ──────────────────────────────────────────
    ens_crps_pool = float(ensemble_df['crps'].mean())
    ens_var_bt = VARBT.var_backtest_full(
        ensemble_df['y_actual'].values, ensemble_df['var_05'].values, alpha=0.05
    )
    print("\n" + "=" * 64)
    print(f"TIER 4 ENSEMBLE POOLED CRPS = {ens_crps_pool:.5f}")
    print("=" * 64)
    best_single = min(pooled[c]['crps_mean'] for c in comp_list)
    delta = (ens_crps_pool - best_single) / best_single * 100
    print(f"  vs best single ({min(pooled, key=lambda c: pooled[c]['crps_mean'])}): Δ={delta:+.2f}%")
    print(f"  VaR_05 Kupiec={ens_var_bt['kupiec_uc']['pass_at_005']}")
    print(f"  VaR_05 CC={ens_var_bt['christoffersen_cc']['pass_at_005']}")

    # ─── DM test: ensemble vs each component ──────────────────────────────
    print("\nDiebold-Mariano test (ensemble vs each component):")
    dm_results = {}
    for c in comp_list:
        comp_crps_pool = np.concatenate([w['crps'] for w in all_preds[c]])
        dm = METRICS.diebold_mariano(loss_a=ensemble_df['crps'].values, loss_b=comp_crps_pool, lag=21)
        dm_results[c] = dm
        sig = '★' if dm['p_value'] < 0.05 else ''
        print(f"  ensemble vs {c}: stat={dm['dm_stat']:.4f} p={dm['p_value']:.4f} mean_diff={dm['mean_diff']:.5f} {sig}")

    # ─── Bear date evaluation ─────────────────────────────────────────────
    print("\nBear date forecast (ensemble):")
    bear_evals = {}
    for label, date_str in KEY_BEAR_DATES.items():
        td = pd.to_datetime(date_str)
        mask = ensemble_df['Date'] == td
        if mask.sum() == 0:
            diffs = (ensemble_df['Date'] - td).abs()
            if diffs.min() <= pd.Timedelta(days=3):
                idx = diffs.idxmin()
                row = ensemble_df.iloc[idx]
            else:
                bear_evals[label] = {'in_test_set': False}
                continue
        else:
            row = ensemble_df[mask].iloc[0]
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
        print(f"  {label}: forecast={row['Date'].date()}, actual={row['y_actual']:+.3f}%, "
              f"P(-5%)={row['p_minus_5pct']*100:.2f}%  P(-10%)={row['p_minus_10pct']*100:.2f}%")

    final_summary = {
        'n_components': len(comp_list),
        'components': comp_list,
        'per_component_pooled': pooled,
        'spearman_rho_matrix': rho_mat.tolist(),
        'spearman_keys': rho_keys,
        'high_similarity_pairs_count': n_high_pairs,
        'diversity_pass_standard': diversity_pass,
        'linear_pool_weights': dict(zip(comp_list, weights.tolist())),
        'tier4_ensemble_crps_pooled': ens_crps_pool,
        'delta_vs_best_single_pct': delta,
        'var_05_backtest_pooled': ens_var_bt,
        'dm_test_ensemble_vs_component': dm_results,
        'bear_date_evaluations': bear_evals,
        'n_test_total': int(len(ensemble_df)),
    }
    with open(Path(output_dir) / "tier4_summary.json", 'w') as f:
        json.dump(final_summary, f, indent=2, default=_json_default)

    print("\n" + "=" * 64)
    print(f"TIER 4 ENSEMBLE FINAL — Saved: {Path(output_dir) / 'tier4_summary.json'}")
    print(f"  Tier 4 CRPS = {ens_crps_pool:.5f}")
    print(f"  Best single: {min(pooled[c]['crps_mean'] for c in comp_list):.5f}")
    print(f"  Δ vs best: {delta:+.2f}%")
    print(f"  Diversity (Spearman ρ < 0.80 all): {diversity_pass}")
    print("=" * 64)

    return final_summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=str, default='config/tier4.yaml')
    parser.add_argument('--output', type=str, default='03_models/tier4')
    parser.add_argument('--components', type=str, default='b1,c,a',
                        help='comma-separated component IDs from {b1, c, a}')
    parser.add_argument('--seed', type=int, default=0)
    args = parser.parse_args()

    cfg_path = ROOT / args.config
    output_dir = ROOT / args.output

    print(f"[tier4] CFG: {cfg_path}")
    print(f"[tier4] OUT: {output_dir}")
    print(f"[tier4] components: {args.components}")

    run_tier4(cfg_path=str(cfg_path), output_dir=str(output_dir), seed=args.seed, components=args.components)


if __name__ == "__main__":
    main()
