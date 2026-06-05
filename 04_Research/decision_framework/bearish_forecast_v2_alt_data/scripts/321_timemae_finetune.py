#!/usr/bin/env python3
"""321_timemae_finetune.py — Plan Phase 3.1 fine-tune for bear prediction

Pretrained encoder (timemae_pretrain_v1.pt) load → classification head 추가
→ walk-forward expanding (annual retrain efficiency, monthly prediction).

Setup:
  - Sequence: 21d v5g features ending at month-start cut (= m_start - 1 trading day)
  - Encoder: Pretrained Transformer (2-layer, d=64), 21d → 64-dim
  - Pool: mean over time → 64-dim
  - Classifier: MLP 64 → 32 → 1 (BCE loss)
  - Fine-tune: end-to-end, AdamW lr=5e-4, 30 epochs

Walk-forward:
  - Annual retrain: at start of each year, train on all past month-starts
  - Predict next 12 months
  - 9 retrainings (2018-2026)
  - Compares vs HGB V1 baseline lift 2.00x

PIT: pretrain only used 1990-2017 (no OOS leak), fine-tune monthly expanding.

Output: outputs/04_evaluation/cycle58dd_phase3_1_finetune.json
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
TGT = WS / "outputs/02_targets"
PRETRAIN_PATH = WS / "outputs/03_models/timemae_pretrain_v1.pt"
OUT_E = WS / "outputs/04_evaluation/cycle58dd_phase3_1_finetune.json"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)
print(f"[Init] Device: {DEVICE}")

# Hyperparams
SEQ_LEN = 21
FT_EPOCHS = 30
FT_LR = 5e-4
FT_BATCH = 64
FT_WD = 1e-4
TEST_START = pd.Timestamp("2018-01-01")
ANNUAL_RETRAIN = True  # if False, single fine-tune for all OOS (faster but lookahead-risky)


# ============================================================
# Load pretrained encoder
# ============================================================
ckpt = torch.load(PRETRAIN_PATH, map_location=DEVICE, weights_only=False)
cfg = ckpt['config']
feat_cols = ckpt['feature_cols']
mu = np.array(ckpt['feature_mu']); sd = np.array(ckpt['feature_sd'])
print(f"[Pretrain] Loaded {PRETRAIN_PATH.name}")
print(f"  config: {cfg}")
print(f"  feat_cols: {len(feat_cols)}")
print(f"  losses: init {ckpt['losses_per_epoch'][0]:.4f} → final {ckpt['losses_per_epoch'][-1]:.4f}")


class TimeMAEEncoder(nn.Module):
    """Encoder only (no recon head). Reused class structure for state_dict load."""
    def __init__(self, n_features, d_model, n_heads, n_layers, dropout, seq_len):
        super().__init__()
        self.d_model = d_model
        self.input_proj = nn.Linear(n_features, d_model)
        self.input_norm = nn.LayerNorm(d_model)
        self.pos_emb = nn.Parameter(torch.zeros(1, seq_len, d_model))
        self.mask_token = nn.Parameter(torch.zeros(1, 1, d_model))
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4, dropout=dropout, batch_first=True,
            activation='gelu', norm_first=True)
        self.encoder = nn.TransformerEncoder(layer, num_layers=n_layers)
        self.enc_norm = nn.LayerNorm(d_model)
        # recon_head retained for state_dict compatibility
        self.recon_head = nn.Sequential(
            nn.Linear(d_model, d_model * 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model * 2, n_features),
        )

    def encode(self, x):
        h = self.input_proj(x); h = self.input_norm(h); h = h + self.pos_emb
        h = self.encoder(h); h = self.enc_norm(h)
        return h


class BearClassifier(nn.Module):
    """Pretrained encoder + classification head (mean pool → MLP → sigmoid)."""
    def __init__(self, encoder, d_model, dropout=0.20):
        super().__init__()
        self.encoder = encoder
        self.dropout = nn.Dropout(dropout)
        self.head = nn.Sequential(
            nn.LayerNorm(d_model),
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, 1),
        )

    def forward(self, x):
        h = self.encoder.encode(x)  # (B, L, D)
        h = h.mean(dim=1)           # (B, D) mean pool
        h = self.dropout(h)
        return self.head(h).squeeze(-1)  # (B,) raw logits


# ============================================================
# Load full v5g + targets, build month-start sequences
# ============================================================
def load_panel_and_targets():
    """Build (month_start_date, X_seq, y_q15) from v5g daily + targets monthly."""
    feat = pd.read_parquet(DATA / "feature_panel_v5g_cross_market.parquet")
    feat['Date'] = pd.to_datetime(feat['Date'])
    feat = feat.sort_values('Date').reset_index(drop=True)
    feat[feat_cols] = feat[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    # Standardize using pretrain mu/sd (Important: use SAME normalization)
    feat[feat_cols] = (feat[feat_cols] - mu) / sd

    # Monthly: first business day of each month
    feat_dt = feat['Date'].values
    feat_X = feat[feat_cols].values

    # Targets — use observable monthly_features for y_tail_q15
    m = pd.read_parquet(DATA / "monthly_features.parquet")
    m['Date'] = pd.to_datetime(m['Date'])
    m = m.dropna(subset=['y_tail_q15']).reset_index(drop=True)

    seqs = []
    ys = []
    dates = []
    for _, row in m.iterrows():
        ms = row['Date']
        cut = ms - pd.Timedelta(days=1)
        # Find last 21 trading days <= cut
        cut_idx = (feat['Date'] <= cut).sum() - 1
        if cut_idx + 1 < SEQ_LEN: continue
        seq = feat_X[cut_idx - SEQ_LEN + 1 : cut_idx + 1]
        if seq.shape != (SEQ_LEN, len(feat_cols)): continue
        seqs.append(seq)
        ys.append(row['y_tail_q15'])
        dates.append(ms)
    X = np.array(seqs, dtype=np.float32)
    y = np.array(ys, dtype=np.float32)
    dates = pd.to_datetime(dates)
    print(f"[Data] {len(X)} month-start sequences, X={X.shape}, base rate {y.mean()*100:.1f}%")
    return X, y, dates


def fine_tune(X_tr, y_tr, epochs=FT_EPOCHS, lr=FT_LR, batch=FT_BATCH):
    """Fine-tune pretrained encoder + head on (X_tr, y_tr)."""
    enc = TimeMAEEncoder(n_features=cfg['n_features'], d_model=cfg['d_model'],
                          n_heads=cfg['n_heads'], n_layers=cfg['n_layers'],
                          dropout=cfg['dropout'], seq_len=cfg['seq_len']).to(DEVICE)
    enc.load_state_dict(ckpt['state_dict'], strict=True)
    model = BearClassifier(enc, d_model=cfg['d_model']).to(DEVICE)
    opt = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=FT_WD)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=epochs)
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    pos_w_t = torch.tensor([min(pos_w, 8.0)], device=DEVICE)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_w_t)
    Xt = torch.from_numpy(X_tr).to(DEVICE)
    yt = torch.from_numpy(y_tr).to(DEVICE)
    ds = TensorDataset(Xt, yt)
    loader = DataLoader(ds, batch_size=batch, shuffle=True, drop_last=False)
    for ep in range(epochs):
        model.train()
        for xb, yb in loader:
            opt.zero_grad()
            logits = model(xb)
            loss = loss_fn(logits, yb)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
        sched.step()
    return model


def predict(model, X):
    model.eval()
    with torch.no_grad():
        Xt = torch.from_numpy(X).to(DEVICE)
        logits = model(Xt)
        return torch.sigmoid(logits).cpu().numpy()


def main():
    X, y, dates = load_panel_and_targets()
    test_mask = dates >= TEST_START
    test_idx = np.where(test_mask)[0]
    print(f"\n[OOS] {len(test_idx)} months, base rate {y[test_idx].mean()*100:.1f}%")

    if ANNUAL_RETRAIN:
        # Annual retrain — group test months by year
        test_dates = pd.Series(dates[test_idx])
        years = test_dates.dt.year.unique()
        preds = np.full(len(test_idx), np.nan)
        for yr in years:
            yr_mask = test_dates.dt.year == yr
            yr_test_pos = np.where(yr_mask.values)[0]
            if len(yr_test_pos) == 0: continue
            # Train on all month-starts BEFORE this year
            first_test_global_idx = test_idx[yr_test_pos[0]]
            tr_idx = np.arange(0, first_test_global_idx)
            if y[tr_idx].sum() < 20:
                print(f"  Year {yr}: insufficient train positives ({y[tr_idx].sum():.0f}), skip")
                continue
            print(f"  Year {yr}: train n={len(tr_idx)} (pos={int(y[tr_idx].sum())}), test n={int(yr_mask.sum())}")
            model = fine_tune(X[tr_idx], y[tr_idx])
            test_X = X[test_idx[yr_test_pos]]
            preds[yr_test_pos] = predict(model, test_X)
        # Eval
        y_test = y[test_idx]
        valid = ~np.isnan(preds)
        y_test = y_test[valid]
        preds = preds[valid]
        dates_test = pd.Series(dates[test_idx])[valid]
        n = len(y_test); base = y_test.mean()
        pr = average_precision_score(y_test, preds)
        roc = roc_auc_score(y_test, preds)
        print(f"\n[TimeMAE fine-tune] OOS n={n} base={base*100:.1f}%")
        print(f"  PR-AUC: {pr:.4f}  lift: {pr/base:.2f}x  ROC: {roc:.4f}")
        # Period-balanced
        periods = [('2018-2020', '2018-01-01', '2020-12-31'),
                   ('2021-2023', '2021-01-01', '2023-12-31'),
                   ('2024-2026', '2024-01-01', '2026-12-31')]
        period_res = []
        for pname, s, e in periods:
            mask = ((dates_test >= pd.Timestamp(s)) & (dates_test <= pd.Timestamp(e))).values
            if mask.sum() < 12 or y_test[mask].sum() < 2:
                continue
            pr_p = average_precision_score(y_test[mask], preds[mask])
            bp = y_test[mask].mean()
            period_res.append({'period': pname, 'n': int(mask.sum()),
                'pos': int(y_test[mask].sum()), 'pr_auc': float(pr_p), 'lift': float(pr_p / bp)})
            print(f"  [{pname}] n={int(mask.sum())} pos={int(y_test[mask].sum())} PR-AUC {pr_p:.4f} lift {pr_p/bp:.2f}x")

        # Bootstrap CI
        B = 5000; np.random.seed(42)
        prs_boot = []
        for b in range(B):
            idx = np.random.choice(n, n, replace=True)
            if y_test[idx].sum() < 5: continue
            prs_boot.append(average_precision_score(y_test[idx], preds[idx]))
        prs_boot = np.array(prs_boot)
        print(f"\n  Bootstrap CI 95%: [{np.quantile(prs_boot, 0.025):.4f}, {np.quantile(prs_boot, 0.975):.4f}]")
        print(f"  P(lift > 2x) = {(prs_boot > 2*base).mean():.3f}")
        print(f"  P(lift > 1.5x) = {(prs_boot > 1.5*base).mean():.3f}")

        # vs HGB baseline (PR-AUC 0.3642 lift 2.00x)
        delta = pr - 0.3642
        print(f"\n  Δ vs HGB V1 baseline (0.3642): {delta:+.4f}")

        audit = {
            'cycle': '58DD_phase3_1_timemae_finetune',
            'n_test': int(n),
            'base_rate': float(base),
            'pr_auc': float(pr),
            'lift': float(pr / base),
            'roc_auc': float(roc),
            'delta_vs_hgb_baseline': float(delta),
            'period_balanced': period_res,
            'bootstrap_ci': [float(np.quantile(prs_boot, 0.025)), float(np.quantile(prs_boot, 0.975))],
            'p_lift_gt_2x': float((prs_boot > 2*base).mean()),
            'p_lift_gt_1_5x': float((prs_boot > 1.5*base).mean()),
            'pretrain_loss_reduction': float((ckpt['losses_per_epoch'][0] - ckpt['losses_per_epoch'][-1]) / ckpt['losses_per_epoch'][0]),
            'retrain_mode': 'annual',
            'epochs': FT_EPOCHS,
            'lr': FT_LR,
        }
        OUT_E.write_text(json.dumps(audit, indent=2))
        print(f"\nSaved: {OUT_E}")


if __name__ == '__main__':
    main()
