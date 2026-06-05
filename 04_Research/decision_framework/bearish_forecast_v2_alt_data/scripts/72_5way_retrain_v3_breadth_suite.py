#!/usr/bin/env python3
"""
72_5way_retrain_v3_breadth_suite.py — Cycle 44 LSTM + Transformer retrain on v3_breadth_suite

Plan: scripts/71 (R) Step 2 → scripts/72 (Python) Step 3 → scripts/73 (R) Step 4-6

Input: outputs/01_data/feature_panel_v3_breadth_suite.parquet (74 features)
Output:
  outputs/03_models/v3_breadth_suite/predictions_lstm_y_tail_q15.parquet
  outputs/03_models/v3_breadth_suite/predictions_lstm_y_onset.parquet
  outputs/03_models/v3_breadth_suite/predictions_tft_y_tail_q15.parquet
  outputs/03_models/v3_breadth_suite/predictions_tft_y_onset.parquet

Architecture (identical to Cycle 43 script 69 for fair compare):
  BiLSTM 64x2 dropout 0.3
  Transformer d_model=64 nhead=4 layers=2 ff=128 dropout=0.2
Sequence length = 21

Walk-forward identical:
  Train 1995-01 ~ 2009-12
  Valid 2010-01 ~ 2015-12 (early stop)
  OOS   2016-01 ~ 2026-04
"""

import sys
import math
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
TGT = WS / "outputs/02_targets"
OUT = WS / "outputs/03_models/v3_breadth_suite"
OUT.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 44 Python] Device: {DEVICE}")

TRAIN_START = pd.Timestamp("1995-01-01")
TRAIN_END   = pd.Timestamp("2009-12-31")
VALID_START = pd.Timestamp("2010-01-01")
VALID_END   = pd.Timestamp("2015-12-31")
OOS_START   = pd.Timestamp("2016-01-01")
OOS_END     = pd.Timestamp("2026-04-30")

SEQ_LEN = 21

# LSTM hyperparams
LSTM_HIDDEN = 64
LSTM_LAYERS = 2
LSTM_DROPOUT = 0.3

# Transformer hyperparams
TFT_D_MODEL = 64
TFT_NHEAD = 4
TFT_LAYERS = 2
TFT_FF = 128
TFT_DROPOUT = 0.2

# Common
LR = 1e-3
BATCH_SIZE = 64
EPOCHS = 50
EARLY_STOP_PATIENCE = 8

torch.manual_seed(42)
np.random.seed(42)


# ── Models (verbatim from Cycle 43) ──
class BiLSTMClassifier(nn.Module):
    def __init__(self, input_dim, hidden=LSTM_HIDDEN, layers=LSTM_LAYERS, dropout=LSTM_DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden, num_layers=layers,
                            batch_first=True, bidirectional=True,
                            dropout=dropout if layers > 1 else 0)
        self.fc = nn.Sequential(
            nn.Linear(hidden * 2, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

    def forward(self, x):
        out, _ = self.lstm(x)
        pooled = out.mean(dim=1)
        return self.fc(pooled).squeeze(-1)


class PositionalEncoding(nn.Module):
    def __init__(self, d_model, max_len=200):
        super().__init__()
        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2).float() *
                             (-math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        self.register_buffer("pe", pe.unsqueeze(0))

    def forward(self, x):
        return x + self.pe[:, :x.size(1)]


class TransformerClassifier(nn.Module):
    def __init__(self, input_dim, d_model=TFT_D_MODEL, nhead=TFT_NHEAD,
                 num_layers=TFT_LAYERS, ff_dim=TFT_FF, dropout=TFT_DROPOUT):
        super().__init__()
        self.input_proj = nn.Linear(input_dim, d_model)
        self.pos_enc = PositionalEncoding(d_model)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=ff_dim,
            dropout=dropout, batch_first=True, activation="gelu"
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.fc = nn.Sequential(
            nn.Linear(d_model, 32),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

    def forward(self, x):
        x = self.input_proj(x)
        x = self.pos_enc(x)
        x = self.encoder(x)
        x = x.mean(dim=1)
        return self.fc(x).squeeze(-1)


def make_sequences(X, y, seq_len=SEQ_LEN):
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
    order = np.argsort(-p); y_ord = y[order]
    prec = np.cumsum(y_ord) / np.arange(1, len(y_ord) + 1)
    rec = np.cumsum(y_ord) / y_ord.sum()
    return float(np.sum(np.diff(rec) * (prec[1:] + prec[:-1]) / 2))


def prepare_data(target_col):
    """Common data prep — used for both LSTM and Transformer."""
    feat_path = DATA / "feature_panel_v3_breadth_suite.parquet"
    tgt_path = TGT / "targets_full.parquet"
    if not feat_path.exists():
        sys.exit(f"missing feature panel: {feat_path}")
    if not tgt_path.exists():
        sys.exit(f"missing target parquet: {tgt_path}")

    feat = pd.read_parquet(feat_path)
    tgt = pd.read_parquet(tgt_path)[["Date", target_col]]
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])
    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END]

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    print(f"  Panel: {len(panel)} rows / {len(feature_cols)} features")

    X = panel[feature_cols].values.astype(np.float32)
    y_raw = panel[target_col].fillna(0).values.astype(np.float32)

    # Median impute (train period)
    train_mask = (panel["Date"] >= TRAIN_START) & (panel["Date"] <= TRAIN_END)
    col_med = np.nan_to_num(np.nanmedian(X[train_mask.values], axis=0), nan=0.0)
    for j in range(X.shape[1]):
        X[np.isnan(X[:, j]), j] = col_med[j]
    # Standardize + clip + nan-safe
    mean = np.nan_to_num(X[train_mask.values].mean(axis=0), nan=0.0)
    std = np.nan_to_num(X[train_mask.values].std(axis=0), nan=1.0) + 1e-6
    std[std < 1e-6] = 1.0
    Xs = (X - mean) / std
    Xs = np.clip(Xs, -10.0, 10.0)
    Xs = np.nan_to_num(Xs, nan=0.0, posinf=0.0, neginf=0.0)

    X_seq, y_seq = make_sequences(Xs, y_raw, SEQ_LEN)
    dates_seq = panel["Date"].values[SEQ_LEN - 1:]
    return X_seq, y_seq, dates_seq


def train_eval(model_class, model_name, target_col):
    print(f"\n========== {model_name} target: {target_col} ==========")
    X_seq, y_seq, dates_seq = prepare_data(target_col)

    train_idx = (dates_seq >= TRAIN_START) & (dates_seq <= TRAIN_END)
    valid_idx = (dates_seq >= VALID_START) & (dates_seq <= VALID_END)
    oos_idx   = (dates_seq >= OOS_START) & (dates_seq <= OOS_END)
    print(f"  Train={train_idx.sum()} / Valid={valid_idx.sum()} / OOS={oos_idx.sum()}")

    X_train_t = torch.tensor(X_seq[train_idx], dtype=torch.float32)
    y_train_t = torch.tensor(y_seq[train_idx], dtype=torch.float32)
    X_valid_t = torch.tensor(X_seq[valid_idx], dtype=torch.float32).to(DEVICE)
    y_valid_t = torch.tensor(y_seq[valid_idx], dtype=torch.float32).to(DEVICE)
    X_oos_t = torch.tensor(X_seq[oos_idx], dtype=torch.float32).to(DEVICE)

    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)
    print(f"  pos_weight: {pos_w_value:.2f}")

    train_loader = DataLoader(TensorDataset(X_train_t, y_train_t),
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True)

    model = model_class(input_dim=X_train_t.shape[2]).to(DEVICE)
    optim = torch.optim.AdamW(model.parameters(), lr=LR,
                              weight_decay=1e-4 if model_name == "TFT" else 1e-5)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_w)

    best_val = -1; patience = 0
    best_state = {k: v.clone() for k, v in model.state_dict().items()}
    for ep in range(EPOCHS):
        model.train(); losses = []
        for xb, yb in train_loader:
            xb = xb.to(DEVICE); yb = yb.to(DEVICE)
            optim.zero_grad()
            logits = model(xb)
            logits = torch.clamp(logits, -20, 20)
            loss = loss_fn(logits, yb)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optim.step()
            losses.append(loss.item())
        model.eval()
        with torch.no_grad():
            vp = torch.sigmoid(model(X_valid_t)).cpu().numpy()
            vpr = pr_auc(vp, y_valid_t.cpu().numpy())
        print(f"  Ep {ep+1:02d} | tr_loss={np.mean(losses):.4f} | valid PR-AUC={vpr:.4f}")
        if vpr > best_val:
            best_val = vpr
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
            patience = 0
        else:
            patience += 1
            if patience >= EARLY_STOP_PATIENCE:
                print(f"  Early stop @ ep {ep+1}"); break

    model.load_state_dict(best_state); model.eval()
    with torch.no_grad():
        oop = torch.sigmoid(model(X_oos_t)).cpu().numpy()
    oos_y = y_seq[oos_idx]
    oos_pr = pr_auc(oop, oos_y)
    print(f"\n[{model_name}] best valid PR-AUC: {best_val:.4f} | OOS PR-AUC: {oos_pr:.4f}")

    col_name = "p_lstm" if model_name == "LSTM" else "p_tft"
    df = pd.DataFrame({
        "Date": dates_seq[oos_idx],
        col_name: oop, "y": oos_y,
        "split": "oos", "target": target_col,
    })
    file_name = f"predictions_{'lstm' if model_name == 'LSTM' else 'tft'}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")
    return oos_pr


if __name__ == "__main__":
    print("=" * 60)
    print("[Cycle 44 Python — LSTM + Transformer on v3_breadth_suite 74 features]")
    print("=" * 60)

    # LSTM both targets
    lstm_q15 = train_eval(BiLSTMClassifier, "LSTM", "y_tail_q15")
    lstm_onset = train_eval(BiLSTMClassifier, "LSTM", "y_onset")

    # Transformer both targets
    tft_q15 = train_eval(TransformerClassifier, "TFT", "y_tail_q15")
    tft_onset = train_eval(TransformerClassifier, "TFT", "y_onset")

    print("\n" + "=" * 60)
    print("[Python Cycle 44 SUMMARY] v3_breadth_suite 74-feature retrain")
    print(f"  LSTM    y_tail_q15: {lstm_q15:.4f}  /  y_onset: {lstm_onset:.4f}")
    print(f"  TFT     y_tail_q15: {tft_q15:.4f}  /  y_onset: {tft_onset:.4f}")
    print("=" * 60)
