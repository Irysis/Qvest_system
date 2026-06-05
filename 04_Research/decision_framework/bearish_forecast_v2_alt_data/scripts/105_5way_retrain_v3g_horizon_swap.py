#!/usr/bin/env python3
"""
105_5way_retrain_v3g_horizon_swap.py — Cycle 48A LSTM + TFT on 3 horizons

Goal: Mirror scripts/97_5way_retrain_v3f_us_macro.py with new targets
  - y_tail_q15  (H=21,  control reproduction)
  - y_tail_q63  (H=63)
  - y_tail_q126 (H=126)

GPU: torch.cuda.set_per_process_memory_fraction(0.3) (45E + 48B parallel).
Mixed precision optional (we stay FP32 for simplicity, since seq_len=21 fits
small footprint anyway).
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
OUT = WS / "outputs/03_models/v3g_horizon_swap"
OUT.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 48A Python] Device: {DEVICE}")
if torch.cuda.is_available():
    try:
        torch.cuda.set_per_process_memory_fraction(0.3)
        print("[GPU] memory fraction set to 0.3 (concurrent with 45E + 48B)")
    except Exception as e:
        print(f"[GPU] memory_fraction set failed (non-fatal): {e}")

TRAIN_START = pd.Timestamp("1995-01-01")
TRAIN_END   = pd.Timestamp("2009-12-31")
VALID_START = pd.Timestamp("2010-01-01")
VALID_END   = pd.Timestamp("2015-12-31")
OOS_START   = pd.Timestamp("2016-01-01")
OOS_END     = pd.Timestamp("2026-04-30")

SEQ_LEN = 21
LSTM_HIDDEN = 64; LSTM_LAYERS = 2; LSTM_DROPOUT = 0.3
TFT_D_MODEL = 64; TFT_NHEAD = 4; TFT_LAYERS = 2; TFT_FF = 128; TFT_DROPOUT = 0.2
LR = 1e-3; BATCH_SIZE = 64; EPOCHS = 50; EARLY_STOP_PATIENCE = 8

torch.manual_seed(42); np.random.seed(42)


class BiLSTMClassifier(nn.Module):
    def __init__(self, input_dim, hidden=LSTM_HIDDEN, layers=LSTM_LAYERS, dropout=LSTM_DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden, num_layers=layers,
                            batch_first=True, bidirectional=True,
                            dropout=dropout if layers > 1 else 0)
        self.fc = nn.Sequential(
            nn.Linear(hidden * 2, 32), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(32, 1))

    def forward(self, x):
        out, _ = self.lstm(x)
        return self.fc(out.mean(dim=1)).squeeze(-1)


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
            dropout=dropout, batch_first=True, activation="gelu")
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.fc = nn.Sequential(
            nn.Linear(d_model, 32), nn.ReLU(), nn.Dropout(dropout),
            nn.Linear(32, 1))

    def forward(self, x):
        x = self.input_proj(x)
        x = self.pos_enc(x)
        x = self.encoder(x)
        return self.fc(x.mean(dim=1)).squeeze(-1)


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
    feat_path = DATA / "feature_panel_v3f_us_macro.parquet"
    tgt_path = TGT / "targets_long_horizon.parquet"
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
    y_mask = ~panel[target_col].isna().values  # mark where target is real
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
    y_mask_seq = y_mask[SEQ_LEN - 1:]
    dates_seq = panel["Date"].values[SEQ_LEN - 1:]
    return X_seq, y_seq, y_mask_seq, dates_seq


def train_eval(model_class, model_name, target_col):
    print(f"\n========== {model_name} target: {target_col} ==========")
    X_seq, y_seq, y_mask_seq, dates_seq = prepare_data(target_col)

    train_idx = (dates_seq >= TRAIN_START) & (dates_seq <= TRAIN_END)
    valid_idx = (dates_seq >= VALID_START) & (dates_seq <= VALID_END)
    oos_idx   = (dates_seq >= OOS_START) & (dates_seq <= OOS_END)
    # For OOS evaluation, restrict to where target is real (mask out trailing NA)
    oos_eff_idx = oos_idx & y_mask_seq
    print(f"  Train={train_idx.sum()} / Valid={valid_idx.sum()} / "
          f"OOS={oos_idx.sum()} (effective {oos_eff_idx.sum()})")

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
    # Evaluate only where target is real (mask trailing NA out)
    oos_y_all = y_seq[oos_idx]
    oos_mask_local = y_mask_seq[oos_idx]
    oos_pr = pr_auc(oop[oos_mask_local], oos_y_all[oos_mask_local])
    print(f"\n[{model_name}] best valid PR-AUC: {best_val:.4f} | "
          f"OOS PR-AUC: {oos_pr:.4f} (n_eff={int(oos_mask_local.sum())})")

    col_name = "p_lstm" if model_name == "LSTM" else "p_tft"
    df = pd.DataFrame({
        "Date": dates_seq[oos_idx],
        col_name: oop,
        "y": oos_y_all,
        "y_mask": oos_mask_local.astype(int),
        "split": "oos", "target": target_col,
    })
    file_name = f"predictions_{'lstm' if model_name == 'LSTM' else 'tft'}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")
    return oos_pr


if __name__ == "__main__":
    print("=" * 60)
    print("[Cycle 48A Python — LSTM + TFT × {y_tail_q15, q63, q126}]")
    print("=" * 60)

    results = {}
    for target in ["y_tail_q15", "y_tail_q63", "y_tail_q126"]:
        results[("LSTM", target)] = train_eval(BiLSTMClassifier, "LSTM", target)
        results[("TFT",  target)] = train_eval(TransformerClassifier, "TFT", target)

    print("\n" + "=" * 60)
    print("[Python Cycle 48A SUMMARY]")
    for (m, t), pr in results.items():
        print(f"  {m:5s}  {t}: {pr:.4f}")
    print("=" * 60)
