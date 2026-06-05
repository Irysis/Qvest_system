#!/usr/bin/env python3
"""320_timemae_pretrain.py — Plan Phase 3.1 Self-Supervised Pretraining

학술 anchor:
  - Yue 2022 (TS2Vec, AAAI) — hierarchical contrastive pretrain
  - TimeMAE 2023 — masked autoencoder for time series

설계: Transformer encoder + Masked Reconstruction SSL (TimeMAE 단순 variant)
  - Input: (B, seq_len=21, n_features=86)
  - Encoder: Transformer 2-layer 4-head d_model=64
  - Mask 30% timesteps with learnable [MASK] embedding
  - Decoder: linear projection back to n_features (per-timestep)
  - Loss: MSE on masked positions only
  - Pretrain: 1990-2017 unlabeled v5g daily sequences (sliding window)

PIT: SSL pretrain은 OOS (2018+) 데이터 사용 안 함 → no future leak.

Output: outputs/03_models/timemae_pretrain_v1.pt + provenance.json
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
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
OUT_DIR = WS / "outputs/03_models"
OUT_DIR.mkdir(parents=True, exist_ok=True)
OUT_MODEL = OUT_DIR / "timemae_pretrain_v1.pt"
OUT_META = OUT_DIR / "timemae_pretrain_v1_meta.json"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Init] Device: {DEVICE}")
SEED = 42
np.random.seed(SEED); torch.manual_seed(SEED)
if DEVICE.type == 'cuda': torch.cuda.manual_seed_all(SEED)

# Hyperparams
SEQ_LEN = 21
D_MODEL = 64
N_HEADS = 4
N_LAYERS = 2
DROPOUT = 0.10
MASK_RATIO = 0.30
BATCH_SIZE = 128
LR = 1e-3
EPOCHS = 60
WEIGHT_DECAY = 1e-4

# PIT cutoff for pretrain (SSL uses pre-OOS only)
PRETRAIN_END = pd.Timestamp("2017-12-31")


def load_features():
    """Load v5g daily panel, filter to PRETRAIN_END, impute NaN."""
    d = pd.read_parquet(DATA / "feature_panel_v5g_cross_market.parquet")
    d['Date'] = pd.to_datetime(d['Date'])
    d = d.sort_values('Date').reset_index(drop=True)
    d = d[d['Date'] <= PRETRAIN_END].copy()
    feat_cols = [c for c in d.columns if c != 'Date']
    # Impute: ffill → bfill → 0
    d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    # Per-feature standardize (train-only — pretrain side, no future)
    mu = d[feat_cols].mean()
    sd = d[feat_cols].std().replace(0, 1)
    d[feat_cols] = (d[feat_cols] - mu) / sd
    print(f"[Load] v5g pretrain rows {len(d)} × {len(feat_cols)} features, ~{d.Date.min().date()} ~ {d.Date.max().date()}")
    return d, feat_cols, mu.values, sd.values


def make_sequences(df, feat_cols, seq_len=SEQ_LEN):
    """Sliding window sequences. Returns (N, seq_len, n_features)."""
    X = df[feat_cols].values
    N = len(X) - seq_len + 1
    if N <= 0: return np.zeros((0, seq_len, len(feat_cols)), dtype=np.float32)
    seqs = np.lib.stride_tricks.sliding_window_view(X, (seq_len, len(feat_cols))).squeeze(1)
    return seqs.astype(np.float32)


class TimeMAEEncoder(nn.Module):
    """Transformer encoder + mask embedding + reconstruction decoder."""
    def __init__(self, n_features, d_model=D_MODEL, n_heads=N_HEADS,
                 n_layers=N_LAYERS, dropout=DROPOUT, seq_len=SEQ_LEN):
        super().__init__()
        self.n_features = n_features
        self.d_model = d_model
        self.seq_len = seq_len

        # Input projection
        self.input_proj = nn.Linear(n_features, d_model)
        self.input_norm = nn.LayerNorm(d_model)
        # Positional encoding (learnable)
        self.pos_emb = nn.Parameter(torch.zeros(1, seq_len, d_model))
        # Mask token
        self.mask_token = nn.Parameter(torch.zeros(1, 1, d_model))

        # Transformer encoder
        layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads,
            dim_feedforward=d_model * 4, dropout=dropout, batch_first=True,
            activation='gelu', norm_first=True)
        self.encoder = nn.TransformerEncoder(layer, num_layers=n_layers)
        self.enc_norm = nn.LayerNorm(d_model)

        # Reconstruction head (per-timestep)
        self.recon_head = nn.Sequential(
            nn.Linear(d_model, d_model * 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model * 2, n_features),
        )
        nn.init.trunc_normal_(self.pos_emb, std=0.02)
        nn.init.trunc_normal_(self.mask_token, std=0.02)

    def encode(self, x, mask=None):
        # x: (B, L, n_features)
        h = self.input_proj(x)
        h = self.input_norm(h)
        if mask is not None:
            # Replace masked timesteps with mask token
            mask_e = mask.unsqueeze(-1).float()  # (B, L, 1)
            h = h * (1 - mask_e) + self.mask_token * mask_e
        h = h + self.pos_emb
        h = self.encoder(h)
        h = self.enc_norm(h)
        return h  # (B, L, d_model)

    def forward(self, x, mask=None):
        h = self.encode(x, mask=mask)
        recon = self.recon_head(h)  # (B, L, n_features)
        return recon


def make_mask(B, L, ratio=MASK_RATIO, device='cuda'):
    """Bernoulli mask: 1 = masked, 0 = visible."""
    return (torch.rand(B, L, device=device) < ratio).float()


def main():
    df, feat_cols, mu, sd = load_features()
    seqs = make_sequences(df, feat_cols)
    print(f"[Seq] {seqs.shape}")
    X = torch.from_numpy(seqs)
    ds = TensorDataset(X)
    loader = DataLoader(ds, batch_size=BATCH_SIZE, shuffle=True, drop_last=True, num_workers=0)
    n_features = X.shape[2]

    # Build model
    model = TimeMAEEncoder(n_features=n_features).to(DEVICE)
    n_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
    print(f"[Model] TimeMAE encoder params: {n_params:,}")
    opt = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=EPOCHS)

    print(f"\n[Train] {EPOCHS} epochs × {len(loader)} batches = {EPOCHS * len(loader)} steps")
    t0 = time.time()
    losses_per_epoch = []
    for ep in range(EPOCHS):
        model.train()
        ep_losses = []
        for batch in loader:
            xb = batch[0].to(DEVICE)
            mask = make_mask(xb.shape[0], xb.shape[1], device=DEVICE)
            recon = model(xb, mask=mask)
            # MSE only on masked positions
            mask_e = mask.unsqueeze(-1)  # (B, L, 1)
            loss = ((recon - xb) ** 2 * mask_e).sum() / (mask_e.sum() * n_features + 1e-8)
            opt.zero_grad(); loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            ep_losses.append(loss.item())
        scheduler.step()
        mean_loss = float(np.mean(ep_losses))
        losses_per_epoch.append(mean_loss)
        if ep % 5 == 0 or ep == EPOCHS - 1:
            print(f"  Epoch {ep+1:>2d}/{EPOCHS}: loss {mean_loss:.6f}  lr {scheduler.get_last_lr()[0]:.2e}  ({time.time()-t0:.1f}s)")
    print(f"\n[Train] Done in {time.time()-t0:.1f}s. Final loss: {losses_per_epoch[-1]:.6f}  Init loss: {losses_per_epoch[0]:.6f}")

    # Save model
    torch.save({
        'state_dict': model.state_dict(),
        'config': {
            'n_features': n_features, 'd_model': D_MODEL, 'n_heads': N_HEADS,
            'n_layers': N_LAYERS, 'dropout': DROPOUT, 'seq_len': SEQ_LEN,
            'mask_ratio': MASK_RATIO,
        },
        'feature_cols': feat_cols,
        'feature_mu': mu.tolist(),
        'feature_sd': sd.tolist(),
        'losses_per_epoch': losses_per_epoch,
    }, OUT_MODEL)
    meta = {
        'cycle': '58DD_phase3.1_timemae_pretrain',
        'n_pretrain_seqs': int(len(seqs)),
        'n_features': n_features,
        'd_model': D_MODEL,
        'n_layers': N_LAYERS,
        'epochs': EPOCHS,
        'batch_size': BATCH_SIZE,
        'lr': LR,
        'mask_ratio': MASK_RATIO,
        'final_loss': float(losses_per_epoch[-1]),
        'init_loss': float(losses_per_epoch[0]),
        'loss_reduction': float((losses_per_epoch[0] - losses_per_epoch[-1]) / losses_per_epoch[0]),
        'pretrain_end_date': str(PRETRAIN_END.date()),
        'time_seconds': float(time.time() - t0),
    }
    OUT_META.write_text(json.dumps(meta, indent=2))
    print(f"\n[SAVED] {OUT_MODEL} ({OUT_MODEL.stat().st_size / 1e6:.1f}MB)")
    print(f"[SAVED] {OUT_META}")


if __name__ == '__main__':
    main()
