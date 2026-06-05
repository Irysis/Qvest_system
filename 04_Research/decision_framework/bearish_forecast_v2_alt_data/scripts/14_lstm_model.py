#!/usr/bin/env python3
"""
14_lstm_model.py — D2 LSTM (Bidirectional, dropout) for bearish forecast

Plan v1.1 → v1.2 Step D2

Input: feature_panel_v1_alt_enhanced.parquet (69 features + Date)
Target: y_tail_q15 (primary) + y_onset (secondary)

Architecture:
  BiLSTM (hidden=64, layers=2, bidirectional, dropout=0.3)
  → mean pooling → Linear(2*64, 32) → ReLU → Dropout → Linear(32, 1) → sigmoid
  Sequence length = 21 (1 month rolling window)

Walk-forward:
  Train  1995-01 ~ 2009-12
  Valid  2010-01 ~ 2015-12 (early stop)
  OOS    2016-01 ~ 2026-04

Output: outputs/03_models/lstm/predictions_lstm_{target}.parquet

Device: CUDA if available, else CPU.
"""

import os
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
TGT = WS / "outputs/02_targets"
OUT = WS / "outputs/03_models/lstm"
OUT.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[D2 LSTM] Device: {DEVICE}")

# Walk-forward splits
TRAIN_START = pd.Timestamp("1995-01-01")
TRAIN_END   = pd.Timestamp("2009-12-31")
VALID_START = pd.Timestamp("2010-01-01")
VALID_END   = pd.Timestamp("2015-12-31")
OOS_START   = pd.Timestamp("2016-01-01")
OOS_END     = pd.Timestamp("2026-04-30")

SEQ_LEN = 21          # 1 month window
HIDDEN = 64
NUM_LAYERS = 2
DROPOUT = 0.3
LR = 1e-3
BATCH_SIZE = 64
EPOCHS = 50
EARLY_STOP_PATIENCE = 8

torch.manual_seed(42)
np.random.seed(42)


class BiLSTMClassifier(nn.Module):
    def __init__(self, input_dim, hidden=HIDDEN, layers=NUM_LAYERS, dropout=DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden, num_layers=layers,
                            batch_first=True, bidirectional=True,
                            dropout=dropout if layers > 1 else 0)
        self.fc = nn.Sequential(
            nn.Linear(hidden * 2, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1)
        )

    def forward(self, x):
        # x shape: (B, SEQ_LEN, input_dim)
        out, _ = self.lstm(x)         # (B, SEQ, hidden*2)
        pooled = out.mean(dim=1)       # mean pooling over time
        logits = self.fc(pooled).squeeze(-1)
        return logits


def make_sequences(X, y, seq_len=SEQ_LEN):
    """Create sliding window sequences. Returns X_seq, y_seq aligned to last day."""
    N, D = X.shape
    if N <= seq_len:
        return np.empty((0, seq_len, D)), np.empty(0)
    X_seq = np.lib.stride_tricks.sliding_window_view(X, (seq_len, D)).squeeze(1)
    y_seq = y[seq_len - 1:]
    return X_seq, y_seq


def pr_auc(p, y):
    ok = ~(np.isnan(p) | np.isnan(y))
    p = p[ok]; y = y[ok]
    if len(p) < 30 or y.sum() < 5:
        return float("nan")
    order = np.argsort(-p)
    y_ord = y[order]
    prec = np.cumsum(y_ord) / np.arange(1, len(y_ord) + 1)
    rec = np.cumsum(y_ord) / y_ord.sum()
    return float(np.sum(np.diff(rec) * (prec[1:] + prec[:-1]) / 2))


def run_lstm(target_col):
    print(f"\n========== LSTM target: {target_col} ==========")

    feat_path = DATA / "feature_panel_v1_alt_enhanced.parquet"
    tgt_path = TGT / "targets_full.parquet"
    if not feat_path.exists() or not tgt_path.exists():
        sys.exit("missing input parquet")

    feat = pd.read_parquet(feat_path)
    tgt = pd.read_parquet(tgt_path)[["Date", target_col]]
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])
    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END]

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    print(f"[D2] Panel: {len(panel)} rows / {len(feature_cols)} features")

    X = panel[feature_cols].values.astype(np.float32)
    y_raw = panel[target_col].fillna(0).values.astype(np.float32)

    # Median impute on train period
    train_mask = (panel["Date"] >= TRAIN_START) & (panel["Date"] <= TRAIN_END)
    col_med = np.nanmedian(X[train_mask.values], axis=0)
    for j in range(X.shape[1]):
        nan_mask = np.isnan(X[:, j])
        X[nan_mask, j] = col_med[j]

    # Standardize (train mean/std) + clip outliers + nan_to_num (NaN propagation fix)
    mean = np.nan_to_num(X[train_mask.values].mean(axis=0), nan=0.0)
    std = np.nan_to_num(X[train_mask.values].std(axis=0), nan=1.0) + 1e-6
    std[std < 1e-6] = 1.0
    Xs = (X - mean) / std
    Xs = np.clip(Xs, -10.0, 10.0)  # winsorize
    Xs = np.nan_to_num(Xs, nan=0.0, posinf=0.0, neginf=0.0)

    # Build sequences
    X_seq, y_seq = make_sequences(Xs, y_raw, SEQ_LEN)
    dates_seq = panel["Date"].values[SEQ_LEN - 1:]
    print(f"[D2] Sequences: {len(X_seq)}")

    # Split indices
    train_idx = (dates_seq >= TRAIN_START) & (dates_seq <= TRAIN_END)
    valid_idx = (dates_seq >= VALID_START) & (dates_seq <= VALID_END)
    oos_idx   = (dates_seq >= OOS_START) & (dates_seq <= OOS_END)
    print(f"  Train={train_idx.sum()} / Valid={valid_idx.sum()} / OOS={oos_idx.sum()}")

    X_train_t = torch.tensor(X_seq[train_idx], dtype=torch.float32)
    y_train_t = torch.tensor(y_seq[train_idx], dtype=torch.float32)
    X_valid_t = torch.tensor(X_seq[valid_idx], dtype=torch.float32).to(DEVICE)
    y_valid_t = torch.tensor(y_seq[valid_idx], dtype=torch.float32).to(DEVICE)
    X_oos_t = torch.tensor(X_seq[oos_idx], dtype=torch.float32).to(DEVICE)

    # Class weight
    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)
    print(f"  pos_weight: {pos_w_value:.2f}")

    train_loader = DataLoader(TensorDataset(X_train_t, y_train_t),
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True)

    model = BiLSTMClassifier(input_dim=X_train_t.shape[2]).to(DEVICE)
    optim = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=1e-5)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_w)

    best_val_prauc = -1
    patience_cnt = 0
    # Initialize best_state with random init (NaN fail-safe)
    best_state = {k: v.clone() for k, v in model.state_dict().items()}

    for ep in range(EPOCHS):
        model.train()
        train_losses = []
        for xb, yb in train_loader:
            xb = xb.to(DEVICE); yb = yb.to(DEVICE)
            optim.zero_grad()
            logits = model(xb)
            logits = torch.clamp(logits, -20, 20)  # numerical stability
            loss = loss_fn(logits, yb)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)  # gradient clipping
            optim.step()
            train_losses.append(loss.item())

        model.eval()
        with torch.no_grad():
            valid_logits = model(X_valid_t)
            valid_p = torch.sigmoid(valid_logits).cpu().numpy()
            val_prauc = pr_auc(valid_p, y_valid_t.cpu().numpy())

        print(f"  Epoch {ep+1:02d} | train_loss={np.mean(train_losses):.4f} | valid PR-AUC={val_prauc:.4f}")

        if val_prauc > best_val_prauc:
            best_val_prauc = val_prauc
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
            patience_cnt = 0
        else:
            patience_cnt += 1
            if patience_cnt >= EARLY_STOP_PATIENCE:
                print(f"  Early stop @ epoch {ep+1}")
                break

    # Load best, predict OOS
    model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        oos_logits = model(X_oos_t)
        oos_p = torch.sigmoid(oos_logits).cpu().numpy()

    oos_y = y_seq[oos_idx]
    oos_prauc = pr_auc(oos_p, oos_y)
    print(f"\n[D2 LSTM] Best valid PR-AUC: {best_val_prauc:.4f}")
    print(f"[D2 LSTM] OOS PR-AUC: {oos_prauc:.4f}")

    # Save predictions
    df_out = pd.DataFrame({
        "Date": dates_seq[oos_idx],
        "p_lstm": oos_p,
        "y": oos_y,
        "split": "oos",
        "target": target_col,
    })
    df_out.to_parquet(OUT / f"predictions_lstm_{target_col}.parquet", index=False)
    print(f"  Saved: {OUT}/predictions_lstm_{target_col}.parquet")

    return oos_prauc


if __name__ == "__main__":
    r1 = run_lstm("y_tail_q15")
    r2 = run_lstm("y_onset")
    print("\n============================================================")
    print(f"[D2 LSTM SUMMARY]")
    print(f"  y_tail_q15 OOS PR-AUC: {r1:.4f}")
    print(f"  y_onset    OOS PR-AUC: {r2:.4f}")
