#!/usr/bin/env python3
"""
17_multitask_lstm.py — D5 Multi-task BiLSTM (y_tail_q15 + y_onset)

Plan v1.2 → v1.3 D5

Architecture:
  Input (B, SEQ, D) → BiLSTM (h=64, layers=2, dropout 0.3, bidirectional)
                    → mean pooling
                    → shared FC (128 → 64) ReLU dropout
                    → Head 1: Linear(64, 1) sigmoid → p_tail_q15
                    → Head 2: Linear(64, 1) sigmoid → p_onset

Loss = α·BCE(y_tail, p_tail) + β·BCE(y_onset, p_onset)
α = β = 0.5 (equal weighting, can tune)

Output: outputs/03_models/multitask/predictions_mtl_{target}.parquet
"""

import sys
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
OUT = WS / "outputs/03_models/multitask"
OUT.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[D5 MTL] Device: {DEVICE}")

TRAIN_START = pd.Timestamp("1995-01-01"); TRAIN_END = pd.Timestamp("2009-12-31")
VALID_START = pd.Timestamp("2010-01-01"); VALID_END = pd.Timestamp("2015-12-31")
OOS_START   = pd.Timestamp("2016-01-01"); OOS_END = pd.Timestamp("2026-04-30")
SEQ_LEN = 21; HIDDEN = 64; NUM_LAYERS = 2; DROPOUT = 0.3
LR = 1e-3; BATCH_SIZE = 64; EPOCHS = 50; EARLY_STOP_PATIENCE = 10

torch.manual_seed(42); np.random.seed(42)


class MultiTaskBiLSTM(nn.Module):
    def __init__(self, input_dim, hidden=HIDDEN, layers=NUM_LAYERS, dropout=DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden, num_layers=layers,
                            batch_first=True, bidirectional=True,
                            dropout=dropout if layers > 1 else 0)
        self.shared_fc = nn.Sequential(
            nn.Linear(hidden * 2, 64), nn.ReLU(), nn.Dropout(dropout),
        )
        self.head_tail = nn.Linear(64, 1)
        self.head_onset = nn.Linear(64, 1)

    def forward(self, x):
        out, _ = self.lstm(x)
        pooled = out.mean(dim=1)
        shared = self.shared_fc(pooled)
        return self.head_tail(shared).squeeze(-1), self.head_onset(shared).squeeze(-1)


def make_sequences(X, ys, seq_len=SEQ_LEN):
    N, D = X.shape
    if N <= seq_len:
        return np.empty((0, seq_len, D)), [np.empty(0) for _ in ys]
    X_seq = np.lib.stride_tricks.sliding_window_view(X, (seq_len, D)).squeeze(1)
    y_seqs = [y[seq_len - 1:] for y in ys]
    return X_seq, y_seqs


def pr_auc(p, y):
    ok = ~(np.isnan(p) | np.isnan(y))
    p = p[ok]; y = y[ok]
    if len(p) < 30 or y.sum() < 5:
        return float("nan")
    order = np.argsort(-p); y_ord = y[order]
    prec = np.cumsum(y_ord) / np.arange(1, len(y_ord) + 1)
    rec = np.cumsum(y_ord) / y_ord.sum()
    return float(np.sum(np.diff(rec) * (prec[1:] + prec[:-1]) / 2))


print("\n========== Multi-task LSTM training ==========")
feat = pd.read_parquet(DATA / "feature_panel_v1_alt_enhanced.parquet")
tgt = pd.read_parquet(TGT / "targets_full.parquet")[["Date", "y_tail_q15", "y_onset"]]
feat["Date"] = pd.to_datetime(feat["Date"])
tgt["Date"] = pd.to_datetime(tgt["Date"])
panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
panel = panel[panel["Date"] <= OOS_END]

feature_cols = [c for c in panel.columns if c not in ("Date", "y_tail_q15", "y_onset")]
print(f"[D5] Panel: {len(panel)} rows / {len(feature_cols)} features")

X = panel[feature_cols].values.astype(np.float32)
y_tail = panel["y_tail_q15"].fillna(0).values.astype(np.float32)
y_onset = panel["y_onset"].fillna(0).values.astype(np.float32)

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

X_seq, (y_tail_seq, y_onset_seq) = make_sequences(Xs, [y_tail, y_onset], SEQ_LEN)
dates_seq = panel["Date"].values[SEQ_LEN - 1:]
print(f"[D5] Sequences: {len(X_seq)}")

train_idx = (dates_seq >= TRAIN_START) & (dates_seq <= TRAIN_END)
valid_idx = (dates_seq >= VALID_START) & (dates_seq <= VALID_END)
oos_idx = (dates_seq >= OOS_START) & (dates_seq <= OOS_END)

X_train_t = torch.tensor(X_seq[train_idx], dtype=torch.float32)
y_tail_train = torch.tensor(y_tail_seq[train_idx], dtype=torch.float32)
y_onset_train = torch.tensor(y_onset_seq[train_idx], dtype=torch.float32)
X_valid_t = torch.tensor(X_seq[valid_idx], dtype=torch.float32).to(DEVICE)
y_tail_valid = torch.tensor(y_tail_seq[valid_idx], dtype=torch.float32).to(DEVICE)
y_onset_valid = torch.tensor(y_onset_seq[valid_idx], dtype=torch.float32).to(DEVICE)
X_oos_t = torch.tensor(X_seq[oos_idx], dtype=torch.float32).to(DEVICE)

pos_w_tail = float(min((y_tail_train == 0).sum() / max((y_tail_train == 1).sum().item(), 1), 8.0))
pos_w_onset = float(min((y_onset_train == 0).sum() / max((y_onset_train == 1).sum().item(), 1), 8.0))
pw_t = torch.tensor([pos_w_tail], device=DEVICE)
pw_o = torch.tensor([pos_w_onset], device=DEVICE)
print(f"[D5] pos_weight tail={pos_w_tail:.2f} / onset={pos_w_onset:.2f}")

train_loader = DataLoader(TensorDataset(X_train_t, y_tail_train, y_onset_train),
                          batch_size=BATCH_SIZE, shuffle=True, drop_last=True)

model = MultiTaskBiLSTM(input_dim=X_train_t.shape[2]).to(DEVICE)
optim = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=1e-5)
loss_fn_tail = nn.BCEWithLogitsLoss(pos_weight=pw_t)
loss_fn_onset = nn.BCEWithLogitsLoss(pos_weight=pw_o)
ALPHA, BETA = 0.5, 0.5  # equal weighting

best_val_combined = -1; patience = 0
best_state = {k: v.clone() for k, v in model.state_dict().items()}

for ep in range(EPOCHS):
    model.train(); losses = []
    for xb, yt, yo in train_loader:
        xb = xb.to(DEVICE); yt = yt.to(DEVICE); yo = yo.to(DEVICE)
        optim.zero_grad()
        logit_t, logit_o = model(xb)
        logit_t = torch.clamp(logit_t, -20, 20)
        logit_o = torch.clamp(logit_o, -20, 20)
        loss = ALPHA * loss_fn_tail(logit_t, yt) + BETA * loss_fn_onset(logit_o, yo)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optim.step()
        losses.append(loss.item())

    model.eval()
    with torch.no_grad():
        vt, vo = model(X_valid_t)
        vp_t = torch.sigmoid(vt).cpu().numpy()
        vp_o = torch.sigmoid(vo).cpu().numpy()
        pa_t = pr_auc(vp_t, y_tail_valid.cpu().numpy())
        pa_o = pr_auc(vp_o, y_onset_valid.cpu().numpy())
        combined = pa_t + pa_o

    print(f"  Ep {ep+1:02d} | tr_loss={np.mean(losses):.4f} | valid PR-AUC tail={pa_t:.4f} onset={pa_o:.4f}")

    if combined > best_val_combined:
        best_val_combined = combined
        best_state = {k: v.clone() for k, v in model.state_dict().items()}
        patience = 0
    else:
        patience += 1
        if patience >= EARLY_STOP_PATIENCE:
            print(f"  Early stop @ ep {ep+1}"); break

model.load_state_dict(best_state); model.eval()
with torch.no_grad():
    ot, oo = model(X_oos_t)
    op_t = torch.sigmoid(ot).cpu().numpy()
    op_o = torch.sigmoid(oo).cpu().numpy()

pr_oos_t = pr_auc(op_t, y_tail_seq[oos_idx])
pr_oos_o = pr_auc(op_o, y_onset_seq[oos_idx])
print(f"\n[D5 MTL] OOS PR-AUC y_tail_q15={pr_oos_t:.4f} / y_onset={pr_oos_o:.4f}")

pd.DataFrame({
    "Date": dates_seq[oos_idx], "p_mtl": op_t, "y": y_tail_seq[oos_idx],
    "split": "oos", "target": "y_tail_q15",
}).to_parquet(OUT / "predictions_mtl_y_tail_q15.parquet", index=False)
pd.DataFrame({
    "Date": dates_seq[oos_idx], "p_mtl": op_o, "y": y_onset_seq[oos_idx],
    "split": "oos", "target": "y_onset",
}).to_parquet(OUT / "predictions_mtl_y_onset.parquet", index=False)

print(f"\n[D5] DONE. Output: {OUT}")
