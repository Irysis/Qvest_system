#!/usr/bin/env python3
"""
DPL_KR_v3 Training Script — Forge Cycle (Session 83)

WT-D20260519_001
Architecture (per alpha_package §factor_specs + dpl_kr_v3_architecture.md):
  - DeepSet Set Module (5,984 trainable params): phi(80->48->32) + rho(32->16)
  - ScoreHead MLP (8,321 trainable params): 96->64->32->1
  - Stage A: Continuous softmax (tau grid)
  - Stage B: STE top-K (k=20)
  - Stage C: PAN iterative max_iter=3 + Dykstra fallback
  - Stage D: Partial Adjustment alpha=0.6 + **post-PA re-projection** (Architect A-3 fix, Codex C4 ACCEPT)
  - Loss: Sharpe surrogate -E[r_p]/(sigma+eps) + lambda_to*0.003*|dw|_1 + lambda_conc*(HHI - 0.10)^2

Inputs (from R):
  features_train.parquet: Date x Ticker x {80 feature columns}
  returns_train.parquet:  Date x Ticker x ret_fwd1m

Outputs:
  weights.parquet: Date x Ticker x weight x method_selected x confidence
  train_log.json: per-window hyperparams + losses + violations + epoch trace

CRITICAL: self_synthesis_used = FALSE strict. No fabricated returns / labels.
"""

import argparse
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset


# -----------------------------------------------------------------------------
# Architecture
# -----------------------------------------------------------------------------

class DeepSetModule(nn.Module):
    """Permutation-invariant set encoder (Zaheer 2017).

    Per-stock feature x_i in R^F -> phi(x_i) -> aggregate (mean) -> rho -> cross-section
    summary c_t in R^16.

    Params: 80->48 (3,888) + 48->32 (1,568) + 32->16 (528) = 5,984
    """

    def __init__(self, feat_dim=80, hidden1=48, hidden2=32, ctx_dim=16):
        super().__init__()
        self.phi1 = nn.Linear(feat_dim, hidden1)
        self.phi2 = nn.Linear(hidden1, hidden2)
        self.rho = nn.Linear(hidden2, ctx_dim)
        self.dropout = nn.Dropout(0.1)

    def forward(self, X):
        # X: (N, F) per sig_date
        h = F.relu(self.phi1(X))
        h = self.dropout(h)
        h = F.relu(self.phi2(h))
        # Aggregate (cross-section mean)
        c_agg = h.mean(dim=0, keepdim=True)  # (1, hidden2)
        c = self.rho(c_agg)  # (1, ctx_dim)
        return c.squeeze(0)  # (ctx_dim,)


class ScoreHeadMLP(nn.Module):
    """Per-stock score head.

    Input: concat(x_i, c_t) in R^96 -> MLP (96->64->32->1)

    Params: 96->64 (6,208) + 64->32 (2,080) + 32->1 (33) = 8,321
    """

    def __init__(self, input_dim=96, hidden1=64, hidden2=32):
        super().__init__()
        self.fc1 = nn.Linear(input_dim, hidden1)
        self.fc2 = nn.Linear(hidden1, hidden2)
        self.fc3 = nn.Linear(hidden2, 1)
        self.dropout = nn.Dropout(0.1)

    def forward(self, X, c):
        # X: (N, F), c: (ctx_dim,)
        c_broadcast = c.unsqueeze(0).expand(X.shape[0], -1)  # (N, ctx_dim)
        h = torch.cat([X, c_broadcast], dim=1)  # (N, F+ctx_dim)
        h = F.relu(self.fc1(h))
        h = self.dropout(h)
        h = F.relu(self.fc2(h))
        s = self.fc3(h).squeeze(-1)  # (N,)
        return s


class DPLv3Model(nn.Module):
    def __init__(self, feat_dim=80, ctx_dim=16, top_k=20, max_weight=0.20,
                 tau=1.0, alpha_partial=0.6, max_iter_pan=3):
        super().__init__()
        self.deepset = DeepSetModule(feat_dim=feat_dim, ctx_dim=ctx_dim)
        self.scorehead = ScoreHeadMLP(input_dim=feat_dim + ctx_dim)
        self.feat_dim = feat_dim
        self.top_k = top_k
        self.max_weight = max_weight
        self.tau = tau
        self.alpha_partial = alpha_partial
        self.max_iter_pan = max_iter_pan

    def forward(self, X, w_prev=None, mode='train'):
        """
        X: (N, F)
        w_prev: (N,) previous weights aligned to current universe
                (if universe changes between sig_dates, caller must align by ticker)
                OR None for cold start
        mode: 'train' or 'inference'
        Returns: w_final (N,), aux (dict)
        """
        N = X.shape[0]
        c = self.deepset(X)
        s_raw = self.scorehead(X, c)
        # Decision-induced ranking clip
        s = torch.clamp(s_raw, -3.0, 3.0)

        # Stage A: continuous softmax (tau)
        w_raw = F.softmax(s / self.tau, dim=0)  # (N,)

        # Stage B: STE top-K (k=20)
        topk_vals, topk_idx = torch.topk(w_raw, self.top_k)
        mask = torch.zeros_like(w_raw)
        mask.scatter_(0, topk_idx, 1.0)

        if mode == 'train':
            # STE: forward = w_raw * mask, backward = w_raw (mask treated as constant)
            w_masked = w_raw * mask
            # Re-normalize to sum=1 for downstream
            w_norm = w_masked / (w_masked.sum() + 1e-9)
        else:
            # Inference: deterministic argsort + Sigma-renormalize
            w_masked = torch.zeros_like(w_raw)
            w_masked.scatter_(0, topk_idx, w_raw[topk_idx])
            w_norm = w_masked / (w_masked.sum() + 1e-9)

        # Stage C: PAN iterative max_iter=3 (clip -> L1 normalize)
        w_pan, pan_violations = self._project_simplex_bounds(w_norm)

        # Stage D: Partial Adjustment
        # NOTE: w_prev must already be aligned to current X universe (caller responsibility)
        # If shapes mismatch (universe changed unaligned), cold-start to w_pan (lose Partial Adjust benefit
        # for this sig_date but maintain correctness)
        if w_prev is None or w_prev.shape != w_pan.shape:
            w_new = w_pan
            pa_overflow = 0
        else:
            w_pa_raw = self.alpha_partial * w_pan + (1.0 - self.alpha_partial) * w_prev
            # POST-PA RE-PROJECTION (Architect A-3 fix, Codex C4 ACCEPT)
            n_active_pre = (w_pa_raw > 1e-9).sum().item()
            pa_overflow = max(0, n_active_pre - self.top_k)
            # Re-apply top-K + PAN
            tk_vals_post, tk_idx_post = torch.topk(w_pa_raw, self.top_k)
            mask_post = torch.zeros_like(w_pa_raw)
            mask_post.scatter_(0, tk_idx_post, w_pa_raw[tk_idx_post])
            w_pa_norm = mask_post / (mask_post.sum() + 1e-9)
            w_new, _ = self._project_simplex_bounds(w_pa_norm)

        aux = {
            's_raw': s_raw,
            'w_raw': w_raw,
            'topk_mass': w_raw[topk_idx].sum().item(),
            'pan_violations': pan_violations,
            'pa_overflow': pa_overflow,
            'hhi': (w_new ** 2).sum().item(),
        }
        return w_new, aux

    def _project_simplex_bounds(self, w):
        """Iterative clip-then-normalize (PAN, Bauschke-Combettes 2017 §28.3).

        Returns (w_proj, n_violations_after_max_iter)
        """
        for _ in range(self.max_iter_pan):
            w = torch.clamp(w, 0.0, self.max_weight)
            s = w.sum() + 1e-9
            w = w / s
            if (w.max().item() <= self.max_weight + 1e-6) and \
               (abs(w.sum().item() - 1.0) < 1e-6):
                return w, 0
        # If still violating after max_iter: final clip + project (1 violation)
        w = torch.clamp(w, 0.0, self.max_weight)
        w = w / (w.sum() + 1e-9)
        violation = 1 if (w.max().item() > self.max_weight + 1e-6) else 0
        return w, violation


# -----------------------------------------------------------------------------
# Helper: align w_prev to current universe by ticker
# -----------------------------------------------------------------------------

def align_w_prev(w_prev, prev_tickers, curr_tickers, device):
    """Align previous weights to current universe by ticker overlap.

    Tickers in both prev and curr: w_prev value preserved.
    Tickers only in curr (new): weight 0 (will start fresh from current).
    Tickers only in prev (delisted): dropped.

    After alignment, re-normalize to sum=1 (if any prev weight retained).
    Otherwise returns None (cold start).
    """
    if w_prev is None or prev_tickers is None or len(prev_tickers) == 0:
        return None
    # Build prev ticker -> index
    prev_tk_arr = np.asarray(prev_tickers)
    curr_tk_arr = np.asarray(curr_tickers)
    prev_idx_map = {tk: i for i, tk in enumerate(prev_tk_arr)}
    # For each curr ticker, get prev weight (or 0)
    aligned = np.zeros(len(curr_tk_arr), dtype=np.float32)
    n_retain = 0
    for j, tk in enumerate(curr_tk_arr):
        if tk in prev_idx_map:
            aligned[j] = w_prev[prev_idx_map[tk]].item()
            n_retain += 1
    if n_retain == 0:
        return None
    # Re-normalize to sum=1
    s = aligned.sum()
    if s < 1e-9:
        return None
    aligned = aligned / s
    return torch.tensor(aligned, dtype=torch.float32, device=device)


# -----------------------------------------------------------------------------
# Loss
# -----------------------------------------------------------------------------

def sharpe_surrogate_loss(returns_per_sigdate, lambda_to=2.0, lambda_conc=1.0,
                          delta_w_per_sigdate=None, hhi_per_sigdate=None,
                          eps=1e-9):
    """Loss = -E[r_p]/(sigma+eps) + lambda_to * 0.003 * mean|dw| + lambda_conc * (HHI - 0.10)^2

    returns_per_sigdate: list of scalar Tensor (portfolio return per sig_date)
    delta_w_per_sigdate: list of scalar Tensor (|dw|_1 per sig_date)
    hhi_per_sigdate:     list of scalar Tensor (HHI per sig_date)
    """
    r_stack = torch.stack(returns_per_sigdate)  # (T,)
    mu = r_stack.mean()
    sigma = r_stack.std() + eps
    sharpe = mu / sigma

    if delta_w_per_sigdate is not None and len(delta_w_per_sigdate) > 0:
        dw_stack = torch.stack(delta_w_per_sigdate)
        to_penalty = lambda_to * 0.003 * dw_stack.mean()
    else:
        to_penalty = torch.tensor(0.0)

    if hhi_per_sigdate is not None and len(hhi_per_sigdate) > 0:
        hhi_stack = torch.stack(hhi_per_sigdate)
        conc_penalty = lambda_conc * ((hhi_stack - 0.10) ** 2).mean()
    else:
        conc_penalty = torch.tensor(0.0)

    loss = -sharpe + to_penalty + conc_penalty
    return loss, dict(sharpe=sharpe.item(), to_penalty=to_penalty.item(),
                      conc_penalty=conc_penalty.item())


# -----------------------------------------------------------------------------
# Training loop (per walk-forward window)
# -----------------------------------------------------------------------------

def train_window(features_df, returns_df, window_spec, hyperparams, device,
                 seed=42):
    """Train DPL_v3 on one walk-forward window.

    features_df: pd.DataFrame[Date, Ticker, feat_1..feat_80]
    returns_df:  pd.DataFrame[Date, Ticker, ret_fwd1m]
    window_spec: dict(train_start, train_end, val_start, val_end, test_start, test_end)
    hyperparams: dict(tau, lambda_to, lambda_conc, alpha_partial, lr, n_epochs)

    Returns: weights_df (Date x Ticker x weight x confidence), train_log_dict
    """
    torch.manual_seed(seed)
    np.random.seed(seed)

    train_sd = sorted(features_df.loc[
        (features_df['Date'] >= window_spec['train_start']) &
        (features_df['Date'] <= window_spec['train_end']), 'Date'].unique())
    val_sd = sorted(features_df.loc[
        (features_df['Date'] >= window_spec['val_start']) &
        (features_df['Date'] <= window_spec['val_end']), 'Date'].unique())
    test_sd = sorted(features_df.loc[
        (features_df['Date'] >= window_spec['test_start']) &
        (features_df['Date'] <= window_spec['test_end']), 'Date'].unique())

    if len(train_sd) < 12:
        return None, dict(skipped=True, reason="train_sd<12", n_train=len(train_sd))

    feat_cols = [c for c in features_df.columns if c not in ('Date', 'Ticker')]
    feat_dim = len(feat_cols)

    model = DPLv3Model(feat_dim=feat_dim, ctx_dim=16, top_k=20, max_weight=0.20,
                       tau=hyperparams['tau'],
                       alpha_partial=hyperparams['alpha_partial']).to(device)
    optim = torch.optim.Adam(model.parameters(), lr=hyperparams['lr'])

    best_val_loss = float('inf')
    best_state = None
    epoch_trace = []

    # Pre-build sig_date -> data tensors for speed (with ticker tracking)
    feat_by_sd_train = {}
    ret_by_sd_train = {}
    tk_by_sd_train = {}
    for sd in train_sd:
        X_df = features_df[features_df['Date'] == sd]
        r_df = returns_df[returns_df['Date'] == sd]
        merged = X_df.merge(r_df, on=['Date', 'Ticker'], how='inner').dropna()
        if len(merged) < 30:
            continue
        feat_by_sd_train[sd] = torch.tensor(merged[feat_cols].values,
                                             dtype=torch.float32, device=device)
        ret_by_sd_train[sd] = torch.tensor(merged['ret_fwd1m'].values,
                                             dtype=torch.float32, device=device)
        tk_by_sd_train[sd] = merged['Ticker'].values
    train_sd_valid = sorted(feat_by_sd_train.keys())

    feat_by_sd_val = {}
    ret_by_sd_val = {}
    tk_by_sd_val = {}
    for sd in val_sd:
        X_df = features_df[features_df['Date'] == sd]
        r_df = returns_df[returns_df['Date'] == sd]
        merged = X_df.merge(r_df, on=['Date', 'Ticker'], how='inner').dropna()
        if len(merged) < 30:
            continue
        feat_by_sd_val[sd] = torch.tensor(merged[feat_cols].values,
                                           dtype=torch.float32, device=device)
        ret_by_sd_val[sd] = torch.tensor(merged['ret_fwd1m'].values,
                                           dtype=torch.float32, device=device)
        tk_by_sd_val[sd] = merged['Ticker'].values
    val_sd_valid = sorted(feat_by_sd_val.keys())

    for epoch in range(hyperparams['n_epochs']):
        model.train()
        train_rets, train_dws, train_hhis = [], [], []
        w_prev = None
        prev_tickers = None

        for sd in train_sd_valid:
            X = feat_by_sd_train[sd]
            r_fwd = ret_by_sd_train[sd]
            curr_tickers = tk_by_sd_train[sd]
            # Align w_prev to current universe by ticker (universe may change)
            w_prev_aligned = align_w_prev(w_prev, prev_tickers, curr_tickers, device)
            w, aux = model(X, w_prev=w_prev_aligned, mode='train')
            port_ret = (w * r_fwd).sum()
            train_rets.append(port_ret)
            hhi_t = (w ** 2).sum()
            train_hhis.append(hhi_t)
            if w_prev_aligned is not None and w_prev_aligned.shape == w.shape:
                dw = (w - w_prev_aligned).abs().sum()
                train_dws.append(dw)
            w_prev = w.detach()
            prev_tickers = curr_tickers

        if len(train_rets) < 6:
            continue

        loss, loss_dict = sharpe_surrogate_loss(
            train_rets, lambda_to=hyperparams['lambda_to'],
            lambda_conc=hyperparams['lambda_conc'],
            delta_w_per_sigdate=train_dws,
            hhi_per_sigdate=train_hhis
        )
        optim.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        optim.step()

        # Validation
        model.eval()
        val_rets, val_hhis = [], []
        w_prev_val = None
        prev_tk_val = None
        with torch.no_grad():
            for sd in val_sd_valid:
                X = feat_by_sd_val[sd]
                r_fwd = ret_by_sd_val[sd]
                curr_tk_val = tk_by_sd_val[sd]
                w_prev_aligned_val = align_w_prev(w_prev_val, prev_tk_val,
                                                    curr_tk_val, device)
                w, aux = model(X, w_prev=w_prev_aligned_val, mode='inference')
                port_ret = (w * r_fwd).sum()
                val_rets.append(port_ret)
                val_hhis.append(aux['hhi'])
                w_prev_val = w
                prev_tk_val = curr_tk_val

        if len(val_rets) >= 2:
            val_loss_t = -torch.stack(val_rets).mean() / (torch.stack(val_rets).std() + 1e-9)
            val_loss = val_loss_t.item()
        else:
            val_loss = float('inf')

        epoch_trace.append(dict(epoch=epoch, train_loss=loss.item(),
                                train_sharpe=loss_dict['sharpe'],
                                val_loss=val_loss,
                                train_hhi_mean=float(np.mean([h.item() for h in train_hhis]))
                                                if train_hhis else 0,
                                val_hhi_mean=float(np.mean(val_hhis)) if val_hhis else 0))

        if val_loss < best_val_loss:
            best_val_loss = val_loss
            best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}

    if best_state is not None:
        model.load_state_dict(best_state)

    # Test inference
    model.eval()
    weight_records = []
    w_prev_test = None
    prev_tk_test = None
    test_aux_log = []
    with torch.no_grad():
        for sd in test_sd:
            X_df = features_df[features_df['Date'] == sd]
            if len(X_df) < 30:
                continue
            tickers = X_df['Ticker'].values
            X = torch.tensor(X_df[feat_cols].values, dtype=torch.float32, device=device)
            w_prev_aligned_test = align_w_prev(w_prev_test, prev_tk_test, tickers, device)
            w, aux = model(X, w_prev=w_prev_aligned_test, mode='inference')
            confidence = aux['topk_mass']
            w_np = w.cpu().numpy()
            for i, tk in enumerate(tickers):
                if w_np[i] > 1e-9:
                    weight_records.append(dict(
                        Date=sd, Ticker=str(tk),
                        weight=float(w_np[i]),
                        method_selected="DPL_v3",
                        confidence=float(confidence)
                    ))
            test_aux_log.append(dict(sig_date=str(sd),
                                     n_active=int((w > 1e-9).sum().item()),
                                     hhi=float(aux['hhi']),
                                     topk_mass=float(aux['topk_mass']),
                                     pa_overflow=int(aux['pa_overflow']),
                                     pan_violations=int(aux['pan_violations'])))
            w_prev_test = w
            prev_tk_test = tickers

    weights_df = pd.DataFrame(weight_records)
    log_dict = dict(
        window_spec={k: str(v) for k, v in window_spec.items()},
        hyperparams=hyperparams,
        n_train=len(train_sd_valid), n_val=len(val_sd_valid), n_test=len(test_sd),
        best_val_loss=best_val_loss,
        n_epochs_actual=len(epoch_trace),
        epoch_trace=epoch_trace[-5:],
        test_aux_log=test_aux_log
    )
    return weights_df, log_dict


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--features', required=True)
    ap.add_argument('--returns', required=True)
    ap.add_argument('--windows', required=True)
    ap.add_argument('--hyperparams', required=True)
    ap.add_argument('--output-weights', required=True)
    ap.add_argument('--output-log', required=True)
    ap.add_argument('--seed', type=int, default=42)
    ap.add_argument('--max-trials-per-window', type=int, default=3,
                    help="hyperparams sampling per window (production = 20, smoke = 3)")
    args = ap.parse_args()

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"[DPL_v3_train] device={device} | torch={torch.__version__}", flush=True)
    if torch.cuda.is_available():
        print(f"[DPL_v3_train] GPU: {torch.cuda.get_device_name(0)}", flush=True)

    print("[DPL_v3_train] Loading features...", flush=True)
    features_df = pd.read_parquet(args.features)
    features_df['Date'] = pd.to_datetime(features_df['Date'])

    print("[DPL_v3_train] Loading returns...", flush=True)
    returns_df = pd.read_parquet(args.returns)
    returns_df['Date'] = pd.to_datetime(returns_df['Date'])

    with open(args.windows, 'r') as f:
        windows = json.load(f)
    with open(args.hyperparams, 'r') as f:
        hp_grid = json.load(f)

    print(f"[DPL_v3_train] Features: {features_df.shape}, Returns: {returns_df.shape}",
          flush=True)
    print(f"[DPL_v3_train] Windows: {len(windows)}, HP grid: {len(hp_grid)} "
          f"(cap {args.max_trials_per_window} per window)", flush=True)

    all_weights = []
    all_logs = []
    rng = np.random.default_rng(args.seed)

    for win_idx, window in enumerate(windows):
        window_parsed = dict(
            window_id=window['window_id'],
            train_start=pd.Timestamp(window['train_start']),
            train_end=pd.Timestamp(window['train_end']),
            val_start=pd.Timestamp(window['val_start']),
            val_end=pd.Timestamp(window['val_end']),
            test_start=pd.Timestamp(window['test_start']),
            test_end=pd.Timestamp(window['test_end']),
        )
        hp_indices = rng.choice(len(hp_grid),
                                size=min(args.max_trials_per_window, len(hp_grid)),
                                replace=False)
        best_window_loss = float('inf')
        best_window_weights = None
        best_window_log = None
        for trial_idx, hp_idx in enumerate(hp_indices):
            hp = hp_grid[int(hp_idx)]
            t0 = time.time()
            weights_df, log_dict = train_window(
                features_df, returns_df, window_parsed, hp, device,
                seed=args.seed + win_idx * 100 + trial_idx
            )
            elapsed = time.time() - t0
            if log_dict.get('skipped'):
                print(f"[W{window_parsed['window_id']:02d} T{trial_idx}] SKIP {log_dict['reason']}",
                      flush=True)
                continue
            val_loss = log_dict['best_val_loss']
            print(f"[W{window_parsed['window_id']:02d} T{trial_idx}] "
                  f"tau={hp['tau']:.2f} lam_to={hp['lambda_to']:.1f} "
                  f"lam_conc={hp['lambda_conc']:.2f} alpha={hp['alpha_partial']:.2f} "
                  f"lr={hp['lr']:.4f} | val_loss={val_loss:.4f} | {elapsed:.1f}s",
                  flush=True)
            if val_loss < best_window_loss:
                best_window_loss = val_loss
                best_window_weights = weights_df
                best_window_log = log_dict
                best_window_log['trial_selected'] = trial_idx
                best_window_log['hp_selected'] = hp

        if best_window_weights is not None:
            all_weights.append(best_window_weights)
            all_logs.append(best_window_log)
            print(f"[W{window_parsed['window_id']:02d}] BEST val_loss={best_window_loss:.4f} "
                  f"n_test_rows={len(best_window_weights)}", flush=True)

    if all_weights:
        weights_all = pd.concat(all_weights, ignore_index=True)
        weights_all.to_parquet(args.output_weights, index=False)
        print(f"[DPL_v3_train] Wrote {len(weights_all)} rows to {args.output_weights}",
              flush=True)
    else:
        print("[DPL_v3_train] ERROR: no weights produced", flush=True)
        sys.exit(2)

    with open(args.output_log, 'w') as f:
        json.dump(all_logs, f, indent=2, default=str)
    print(f"[DPL_v3_train] Wrote train log to {args.output_log}", flush=True)


if __name__ == '__main__':
    main()
