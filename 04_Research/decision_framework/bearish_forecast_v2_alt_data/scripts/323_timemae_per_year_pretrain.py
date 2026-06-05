#!/usr/bin/env python3
"""323_timemae_per_year_pretrain.py — 도훈 mandate "학습기간 더 늘리기"

기존: 320 hardcoded pretrain end 2017-12-31 (모든 OOS test years 동일 encoder)
신규: per-year pretrain — test year T 예측 시 pretrain end = T-1년 12월

PIT-safe: 각 test year는 strictly past data로 학습된 encoder 사용.
9 pretrains × ~26s = ~4분 (RTX 4080).

비교:
  Baseline: 320 single pretrain (end 2017) — TimeMAE 2018-23 weak (0.92-1.22x) / 2024-26 4.18x
  Extended: per-year pretrain — pretrain data 점진 증가 (2018: 6895 days → 2026: 9000 days)

Output: outputs/03_models/timemae_pretrain_per_year/timemae_pretrain_v2_{year}.pt
       + fine-tune + eval → outputs/04_evaluation/cycle58dd_phase3_1_per_year.json
"""
import os
os.environ['CUBLAS_WORKSPACE_CONFIG'] = ':4096:8'
import json
import time
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
OUT_DIR = WS / "outputs/03_models/timemae_pretrain_per_year"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_E = WS / "outputs/04_evaluation/cycle58dd_phase3_1_per_year.json"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)

# Same hyperparams as 320
SEQ_LEN = 21
D_MODEL = 64; N_HEADS = 4; N_LAYERS = 2; DROPOUT = 0.10
MASK_RATIO = 0.30; BATCH_SIZE = 128
PRETRAIN_LR = 1e-3; PRETRAIN_EPOCHS = 60; PRETRAIN_WD = 1e-4

FT_EPOCHS = 30; FT_LR = 5e-4; FT_BATCH = 64
TEST_START = pd.Timestamp("2018-01-01")


class TimeMAEEncoder(nn.Module):
    def __init__(self, n_features, d_model=D_MODEL, n_heads=N_HEADS, n_layers=N_LAYERS,
                 dropout=DROPOUT, seq_len=SEQ_LEN):
        super().__init__()
        self.n_features = n_features; self.d_model = d_model; self.seq_len = seq_len
        self.input_proj = nn.Linear(n_features, d_model)
        self.input_norm = nn.LayerNorm(d_model)
        self.pos_emb = nn.Parameter(torch.zeros(1, seq_len, d_model))
        self.mask_token = nn.Parameter(torch.zeros(1, 1, d_model))
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4, dropout=dropout, batch_first=True,
            activation='gelu', norm_first=True)
        self.encoder = nn.TransformerEncoder(layer, num_layers=n_layers)
        self.enc_norm = nn.LayerNorm(d_model)
        self.recon_head = nn.Sequential(
            nn.Linear(d_model, d_model * 2), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(d_model * 2, n_features))
        nn.init.trunc_normal_(self.pos_emb, std=0.02)
        nn.init.trunc_normal_(self.mask_token, std=0.02)

    def encode(self, x, mask=None):
        h = self.input_proj(x); h = self.input_norm(h)
        if mask is not None:
            mask_e = mask.unsqueeze(-1).float()
            h = h * (1 - mask_e) + self.mask_token * mask_e
        h = h + self.pos_emb; h = self.encoder(h); h = self.enc_norm(h)
        return h

    def forward(self, x, mask=None):
        h = self.encode(x, mask=mask); return self.recon_head(h)


class BearClassifier(nn.Module):
    def __init__(self, encoder, d_model, dropout=0.20):
        super().__init__()
        self.encoder = encoder; self.dropout = nn.Dropout(dropout)
        self.head = nn.Sequential(
            nn.LayerNorm(d_model), nn.Linear(d_model, d_model // 2),
            nn.GELU(), nn.Dropout(dropout), nn.Linear(d_model // 2, 1))
    def forward(self, x):
        h = self.encoder.encode(x); h = h.mean(dim=1); h = self.dropout(h)
        return self.head(h).squeeze(-1)


def make_mask(B, L, ratio=MASK_RATIO, device='cuda'):
    return (torch.rand(B, L, device=device) < ratio).float()


def make_sequences(X, seq_len=SEQ_LEN):
    N = len(X) - seq_len + 1
    if N <= 0: return np.zeros((0, seq_len, X.shape[1]), dtype=np.float32)
    return np.lib.stride_tricks.sliding_window_view(X, (seq_len, X.shape[1])).squeeze(1).astype(np.float32)


def pretrain_encoder(pretrain_end, feat_df, feat_cols):
    """Pretrain TimeMAE encoder using data up to pretrain_end (PIT-safe)."""
    d = feat_df[feat_df['Date'] <= pretrain_end].copy()
    d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    mu = d[feat_cols].mean().values
    sd = d[feat_cols].std().replace(0, 1).values
    d_std = (d[feat_cols].values - mu) / sd
    seqs = make_sequences(d_std)
    if len(seqs) == 0: return None, None, None
    X = torch.from_numpy(seqs)
    loader = DataLoader(TensorDataset(X), batch_size=BATCH_SIZE, shuffle=True, drop_last=True, num_workers=0)
    n_features = X.shape[2]
    model = TimeMAEEncoder(n_features=n_features).to(DEVICE)
    opt = torch.optim.AdamW(model.parameters(), lr=PRETRAIN_LR, weight_decay=PRETRAIN_WD)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=PRETRAIN_EPOCHS)
    losses = []
    for ep in range(PRETRAIN_EPOCHS):
        model.train()
        ep_losses = []
        for batch in loader:
            xb = batch[0].to(DEVICE)
            mask = make_mask(xb.shape[0], xb.shape[1], device=DEVICE)
            recon = model(xb, mask=mask)
            mask_e = mask.unsqueeze(-1)
            loss = ((recon - xb) ** 2 * mask_e).sum() / (mask_e.sum() * n_features + 1e-8)
            opt.zero_grad(); loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
            ep_losses.append(loss.item())
        sched.step()
        losses.append(float(np.mean(ep_losses)) if ep_losses else float('nan'))
    return model, (mu, sd), losses


def fine_tune(encoder_state, n_features, X_tr, y_tr, epochs=FT_EPOCHS, lr=FT_LR):
    enc = TimeMAEEncoder(n_features=n_features).to(DEVICE)
    enc.load_state_dict(encoder_state, strict=True)
    model = BearClassifier(enc, d_model=D_MODEL).to(DEVICE)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([min(pos_w, 8.0)], device=DEVICE))
    Xt = torch.from_numpy(X_tr).to(DEVICE); yt = torch.from_numpy(y_tr).to(DEVICE)
    loader = DataLoader(TensorDataset(Xt, yt), batch_size=FT_BATCH, shuffle=True, drop_last=False)
    for _ in range(epochs):
        model.train()
        for xb, yb in loader:
            opt.zero_grad(); loss = loss_fn(model(xb), yb)
            loss.backward(); torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0); opt.step()
        sched.step()
    return model


def predict(model, X):
    model.eval()
    with torch.no_grad():
        return torch.sigmoid(model(torch.from_numpy(X).to(DEVICE))).cpu().numpy()


def main():
    # Load v5g daily
    feat = pd.read_parquet(DATA / "feature_panel_v5g_cross_market.parquet")
    feat['Date'] = pd.to_datetime(feat['Date']); feat = feat.sort_values('Date').reset_index(drop=True)
    feat_cols = [c for c in feat.columns if c != 'Date']
    print(f"[Load] v5g {len(feat)} daily rows × {len(feat_cols)} cols")

    # Monthly + labels
    m = pd.read_parquet(DATA / "monthly_features.parquet")
    m['Date'] = pd.to_datetime(m['Date'])
    m = m.dropna(subset=['y_tail_q15']).reset_index(drop=True)
    print(f"  monthly {len(m)} rows, base {m['y_tail_q15'].mean()*100:.1f}%")

    # Build month-start sequences (using raw v5g, NOT pre-standardized — we need per-year mu/sd)
    feat_raw = feat.copy()
    feat_raw[feat_cols] = feat_raw[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    feat_X = feat_raw[feat_cols].values

    seqs = []; ys = []; dates = []
    for _, row in m.iterrows():
        ms = row['Date']; cut = ms - pd.Timedelta(days=1)
        cut_idx = (feat['Date'] <= cut).sum() - 1
        if cut_idx + 1 < SEQ_LEN: continue
        seq = feat_X[cut_idx - SEQ_LEN + 1 : cut_idx + 1]
        if seq.shape != (SEQ_LEN, len(feat_cols)): continue
        seqs.append(seq); ys.append(row['y_tail_q15']); dates.append(ms)
    X_seq = np.array(seqs, dtype=np.float32)
    y = np.array(ys, dtype=np.float32)
    dates = pd.to_datetime(dates)
    test_idx = np.where(dates >= TEST_START)[0]
    print(f"  total {len(X_seq)} month-start sequences, OOS {len(test_idx)} months")

    # Per-year pretrain + fine-tune
    test_dates_s = pd.Series(dates[test_idx])
    years = sorted(test_dates_s.dt.year.unique())
    preds = np.full(len(test_idx), np.nan)
    pretrain_metas = []
    for yr in years:
        yr_mask = test_dates_s.dt.year == yr
        yr_pos = np.where(yr_mask.values)[0]
        if len(yr_pos) == 0: continue
        first_global = test_idx[yr_pos[0]]
        if y[np.arange(0, first_global)].sum() < 20: continue
        # Pretrain end = prior year end (PIT-safe for year yr predictions)
        pretrain_end = pd.Timestamp(f"{yr-1}-12-31")
        t0 = time.time()
        print(f"\n[Year {yr}] pretrain end {pretrain_end.date()} → ", end='', flush=True)
        enc_model, ms_std, losses = pretrain_encoder(pretrain_end, feat, feat_cols)
        if enc_model is None: print("FAIL"); continue
        mu_y, sd_y = ms_std
        pretrain_time = time.time() - t0
        print(f"pretrain loss {losses[0]:.4f}→{losses[-1]:.4f} ({pretrain_time:.1f}s) — fine-tune ", end='', flush=True)

        # Standardize X_seq with this year's pretrain mu/sd
        X_seq_std = (X_seq - mu_y) / sd_y
        X_seq_std = X_seq_std.astype(np.float32)

        # Fine-tune on all months before test year (PIT)
        tr_idx = np.arange(0, first_global)
        t1 = time.time()
        cls_model = fine_tune(enc_model.state_dict(), len(feat_cols),
                              X_seq_std[tr_idx], y[tr_idx])
        ft_time = time.time() - t1
        print(f"{ft_time:.1f}s — predict {int(yr_mask.sum())} months")
        preds[yr_pos] = predict(cls_model, X_seq_std[test_idx[yr_pos]])
        pretrain_metas.append({'year': int(yr), 'pretrain_n': int(len(feat[feat['Date'] <= pretrain_end])),
                                'pretrain_loss_init': float(losses[0]),
                                'pretrain_loss_final': float(losses[-1]),
                                'pretrain_time_s': float(pretrain_time),
                                'ft_time_s': float(ft_time)})

        # Save encoder (optional, audit)
        torch.save({'state_dict': enc_model.state_dict(),
                    'mu': mu_y.tolist(), 'sd': sd_y.tolist(),
                    'pretrain_end': str(pretrain_end.date())},
                   OUT_DIR / f"timemae_pretrain_v2_{yr}.pt")

    # Eval
    y_test = y[test_idx]
    valid = ~np.isnan(preds)
    y_test = y_test[valid]; preds = preds[valid]
    dates_test = pd.Series(dates[test_idx])[valid].reset_index(drop=True)
    n = len(y_test); base = y_test.mean()
    pr = average_precision_score(y_test, preds)
    roc = roc_auc_score(y_test, preds)
    print(f"\n[Per-year TimeMAE] OOS n={n} base={base*100:.1f}% PR-AUC {pr:.4f} lift {pr/base:.2f}x ROC {roc:.4f}")

    # Period-balanced
    periods = [('2018-2020', '2018-01-01', '2020-12-31'),
               ('2021-2023', '2021-01-01', '2023-12-31'),
               ('2024-2026', '2024-01-01', '2026-12-31')]
    period_res = []
    print(f"\n[Period-balanced — Per-year TimeMAE vs Single 320 pretrain]")
    print(f"{'Period':<12s} {'PerYear':>10s} {'Single (320)':>13s} {'Δ':>9s}")
    single_baselines = {'2018-2020': 0.92, '2021-2023': 1.22, '2024-2026': 4.18}
    for pname, s, e in periods:
        mask = ((dates_test >= pd.Timestamp(s)) & (dates_test <= pd.Timestamp(e))).values
        if mask.sum() < 12 or y_test[mask].sum() < 2: continue
        pr_p = average_precision_score(y_test[mask], preds[mask])
        bp = y_test[mask].mean()
        lift_p = pr_p / bp
        single = single_baselines.get(pname, np.nan)
        delta = lift_p - single
        period_res.append({'period': pname, 'n': int(mask.sum()), 'pos': int(y_test[mask].sum()),
                            'pr_auc': float(pr_p), 'per_year_lift': float(lift_p),
                            'single_320_lift': float(single), 'delta': float(delta)})
        print(f"  {pname:<12s} {lift_p:>9.2f}x {single:>12.2f}x {delta:>+8.2f}x")

    # Bootstrap CI
    B = 5000; np.random.seed(42)
    prs = []
    for b in range(B):
        idx = np.random.choice(n, n, replace=True)
        if y_test[idx].sum() < 5: continue
        prs.append(average_precision_score(y_test[idx], preds[idx]))
    prs = np.array(prs)
    print(f"\n[Bootstrap CI 95%]")
    print(f"  CI: [{np.quantile(prs, 0.025):.4f}, {np.quantile(prs, 0.975):.4f}]")
    print(f"  P(lift > 2x) = {(prs > 2*base).mean():.3f}")
    print(f"  P(lift > 1.5x) = {(prs > 1.5*base).mean():.3f}")

    audit = {
        'cycle': '58DD_phase3_1_per_year_pretrain',
        'n_test': int(n), 'base': float(base),
        'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc),
        'period_balanced': period_res,
        'bootstrap_ci': [float(np.quantile(prs, 0.025)), float(np.quantile(prs, 0.975))],
        'p_lift_gt_2x': float((prs > 2*base).mean()),
        'p_lift_gt_1_5x': float((prs > 1.5*base).mean()),
        'pretrain_meta_per_year': pretrain_metas,
        'predictions': {str(d.date()): float(p) for d, p in zip(dates_test, preds)},
    }
    OUT_E.parent.mkdir(parents=True, exist_ok=True)
    OUT_E.write_text(json.dumps(audit, indent=2))
    print(f"\nSaved: {OUT_E}")


if __name__ == '__main__':
    main()
