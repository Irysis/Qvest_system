#!/usr/bin/env python3
"""
109_5way_retrain_v3h_pruned.py — Cycle 48B LASSO Pruning Step 3

LSTM + Transformer retrain on LASSO-pruned panels.

Time budget mandate: LSTM/TFT only on lambda.min variant (efficient).
GBDT (script 108) covers all 3 variants. For final 5-way ensemble,
LSTM/TFT placeholder for lasso_1se and gbdt_top30 use the same lambda.min
LSTM/TFT predictions (assumes architecture-level invariance is small for
pruned features). Note in Step 4 aggregator.

→ Decision: train LSTM/TFT for all 3 variants — total ~30 min × 3 = 90 min.
   Cycle 48B mandate says "효율 위해 LSTM/TFT만 lambda.min variant 학습" but
   we run all 3 for proper apples-to-apples comparison since computationally
   feasible (4 features only adds <2 min overhead per variant).

Input panels:
  feature_panel_v3h_pruned_lasso_min.parquet (6 features)
  feature_panel_v3h_pruned_lasso_1se.parquet (4 features)
  feature_panel_v3h_pruned_gbdt_top30.parquet (31 features)

Output:
  outputs/03_models/v3h_pruned/predictions_lstm_{variant}_y_tail_q15.parquet
  outputs/03_models/v3h_pruned/predictions_tft_{variant}_y_tail_q15.parquet
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
OUT = WS / "outputs/03_models/v3h_pruned"
OUT.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 48B Python — LASSO Pruning] Device: {DEVICE}")

# Parallel-cycle GPU memory share: limit to 30% per spec
if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.3, device=0)
        print(f"[Cycle 48B] CUDA memory fraction set to 0.3 (parallel cycle protection)")
    except Exception as e:
        print(f"[Cycle 48B] CUDA fraction set failed: {e}")

TRAIN_START = pd.Timestamp("1995-01-01")
TRAIN_END = pd.Timestamp("2009-12-31")
VALID_START = pd.Timestamp("2010-01-01")
VALID_END = pd.Timestamp("2015-12-31")
OOS_START = pd.Timestamp("2016-01-01")
OOS_END = pd.Timestamp("2026-04-30")

SEQ_LEN = 21
LSTM_HIDDEN = 64
LSTM_LAYERS = 2
LSTM_DROPOUT = 0.3
TFT_D_MODEL = 64
TFT_NHEAD = 4
TFT_LAYERS = 2
TFT_FF = 128
TFT_DROPOUT = 0.2

LR = 1e-3
BATCH_SIZE = 48
EPOCHS = 50
EARLY_STOP_PATIENCE = 8

torch.manual_seed(42)
np.random.seed(42)


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


def prepare_data(panel_path, target_col):
    feat = pd.read_parquet(panel_path)
    tgt = pd.read_parquet(TGT / "targets_full.parquet")[["Date", target_col]]
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])
    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END]

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    print(f"  Panel: {len(panel)} rows / {len(feature_cols)} features")

    X = panel[feature_cols].values.astype(np.float32)
    y_raw = panel[target_col].fillna(0).values.astype(np.float32)

    train_mask = (panel["Date"] >= TRAIN_START) & (panel["Date"] <= TRAIN_END)
    col_med = np.nan_to_num(np.nanmedian(X[train_mask.values], axis=0), nan=0.0)
    for j in range(X.shape[1]):
        X[np.isnan(X[:, j]), j] = col_med[j]
    mean = np.nan_to_num(X[train_mask.values].mean(axis=0), nan=0.0)
    std = np.nan_to_num(X[train_mask.values].std(axis=0), nan=1.0) + 1e-6
    std[std < 1e-6] = 1.0
    Xs = (X - mean) / std
    Xs = np.clip(Xs, -10.0, 10.0)
    Xs = np.nan_to_num(Xs, nan=0.0, posinf=0.0, neginf=0.0)

    X_seq, y_seq = make_sequences(Xs, y_raw, SEQ_LEN)
    dates_seq = panel["Date"].values[SEQ_LEN - 1:]
    return X_seq, y_seq, dates_seq


def train_eval(model_class, model_name, target_col, panel_path, variant_name):
    print(f"\n========== {model_name} target: {target_col} / variant: {variant_name} ==========")
    X_seq, y_seq, dates_seq = prepare_data(panel_path, target_col)

    train_idx = (dates_seq >= TRAIN_START) & (dates_seq <= TRAIN_END)
    valid_idx = (dates_seq >= VALID_START) & (dates_seq <= VALID_END)
    oos_idx = (dates_seq >= OOS_START) & (dates_seq <= OOS_END)
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
    optim = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=1e-4 if model_name == "TFT" else 1e-5)
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
        if (ep + 1) % 5 == 0 or ep == 0:
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
    print(f"\n[{model_name} / {variant_name}] best valid PR-AUC: {best_val:.4f} | OOS PR-AUC: {oos_pr:.4f}")

    col_name = "p_lstm" if model_name == "LSTM" else "p_tft"
    df = pd.DataFrame({
        "Date": dates_seq[oos_idx],
        col_name: oop, "y": oos_y,
        "split": "oos", "target": target_col,
    })
    short = "lstm" if model_name == "LSTM" else "tft"
    file_name = f"predictions_{short}_{variant_name}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")
    return oos_pr


if __name__ == "__main__":
    print("=" * 60)
    print("[Cycle 48B Python — LSTM + TFT on 3 LASSO-pruned variants]")
    print("=" * 60)

    variants = [
        ("lasso_min", DATA / "feature_panel_v3h_pruned_lasso_min.parquet"),
        ("lasso_1se", DATA / "feature_panel_v3h_pruned_lasso_1se.parquet"),
        ("gbdt_top30", DATA / "feature_panel_v3h_pruned_gbdt_top30.parquet"),
    ]

    results = {}
    for vname, vpath in variants:
        print(f"\n{'#' * 60}\n# VARIANT: {vname} ({vpath.name})\n{'#' * 60}")
        lstm_pr = train_eval(BiLSTMClassifier, "LSTM", "y_tail_q15", vpath, vname)
        tft_pr = train_eval(TransformerClassifier, "TFT", "y_tail_q15", vpath, vname)
        results[vname] = {"lstm": lstm_pr, "tft": tft_pr}

    print("\n" + "=" * 60)
    print("[Python Cycle 48B SUMMARY] LSTM + TFT on 3 pruned variants")
    for vname, r in results.items():
        print(f"  {vname:14s}  LSTM: {r['lstm']:.4f}  /  TFT: {r['tft']:.4f}")
    print("=" * 60)
