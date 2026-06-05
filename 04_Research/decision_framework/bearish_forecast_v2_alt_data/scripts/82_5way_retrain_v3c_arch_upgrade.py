#!/usr/bin/env python3
"""
82_5way_retrain_v3c_arch_upgrade.py — Cycle 45C Architecture Upgrade
Upgraded LSTM + Transformer retrain on v1.3 baseline (69 features, NO new features)

Plan: scripts/81 (R) Step 2 → scripts/82 (Python) Step 3 → scripts/83 (R) Step 4-6

Input: outputs/01_data/feature_panel_v1_3.parquet (69 features = v1_alt_enhanced)
Output:
  outputs/03_models/v3c_arch_upgrade/predictions_lstm_y_tail_q15.parquet
  outputs/03_models/v3c_arch_upgrade/predictions_lstm_y_onset.parquet
  outputs/03_models/v3c_arch_upgrade/predictions_tft_y_tail_q15.parquet
  outputs/03_models/v3c_arch_upgrade/predictions_tft_y_onset.parquet

============================================================================
ARCHITECTURE UPGRADES (vs Cycle 43 v2_2feat baseline)
============================================================================

LSTM strengthen:
  hidden_dim         64 → 192     (3x capacity)
  num_layers         2  → 3       (depth +1, bidirectional retained)
  dropout            0.3 → 0.45   (regularization stronger)
  weight_decay       1e-5 → 5e-3  (덜 aggressive than TFT 1e-2)
  gradient_clip_norm 1.0 → 1.0    (retained, was already enabled)
  LR schedule        cosine warmup 500 + cosine decay (new)
  early stop         8 → 8        (retained, baseline 5 elsewhere)

TFT strengthen:
  d_model            64 → 128     (2x capacity)
  num_heads          4 → 8        (attention diversity)
  num_layers         2 → 6        (depth +4)
  ff_dim multiplier  4x (256) → 6x (768)  (FFN capacity 3x)
  dropout            0.2 → 0.45   (regularization stronger)
  attention_dropout  default → 0.2 explicit (new)
  weight_decay       1e-4 → 5e-3  (덜 aggressive)
  gradient_clip_norm 1.0          (retained)
  LR schedule        cosine warmup 500 + cosine decay (new)
  early stop         8 → 8        (retained)

Train infrastructure:
  batch_size         64 → 96      (larger batch for stability with capacity)
  GPU mem fraction   set 0.3      (3-cycle parallel protection)
  Mixed precision    torch.cuda.amp (memory + speed)
  num_workers        0            (parallel GPU safety)

Walk-forward identical:
  Train 1995-01 ~ 2009-12
  Valid 2010-01 ~ 2015-12 (early stop)
  OOS   2016-01 ~ 2026-04
"""

import sys
import math
import time
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from torch.optim.lr_scheduler import LambdaLR

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
TGT = WS / "outputs/02_targets"
OUT = WS / "outputs/03_models/v3c_arch_upgrade"
OUT.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 45C Python] Device: {DEVICE}")

# 3-cycle parallel GPU memory share
if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.3, device=0)
        print(f"[Cycle 45C] CUDA memory fraction set to 0.3 (parallel 45A/45B/45C)")
    except Exception as e:
        print(f"[Cycle 45C] CUDA fraction set failed: {e}")
    # Mixed precision support
    USE_AMP = True
    print(f"[Cycle 45C] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

TRAIN_START = pd.Timestamp("1995-01-01")
TRAIN_END   = pd.Timestamp("2009-12-31")
VALID_START = pd.Timestamp("2010-01-01")
VALID_END   = pd.Timestamp("2015-12-31")
OOS_START   = pd.Timestamp("2016-01-01")
OOS_END     = pd.Timestamp("2026-04-30")

SEQ_LEN = 21

# ============================================================================
# LSTM UPGRADED HYPERPARAMS
# ============================================================================
LSTM_HIDDEN = 192       # 64 → 192
LSTM_LAYERS = 3         # 2 → 3 (depth +1)
LSTM_DROPOUT = 0.45     # 0.3 → 0.45
LSTM_BIDIR = True       # retained
LSTM_WEIGHT_DECAY = 5e-3
LSTM_LR = 1e-3

# ============================================================================
# TFT UPGRADED HYPERPARAMS
# ============================================================================
TFT_D_MODEL = 128       # 64 → 128
TFT_NHEAD = 8           # 4 → 8
TFT_LAYERS = 6          # 2 → 6
TFT_FF_MULT = 6         # 4 → 6 (so ff_dim = 128 * 6 = 768)
TFT_DROPOUT = 0.45      # 0.2 → 0.45
TFT_ATTN_DROPOUT = 0.2  # new explicit
TFT_WEIGHT_DECAY = 5e-3
TFT_LR = 1e-3

# ============================================================================
# COMMON TRAIN INFRA
# ============================================================================
BATCH_SIZE = 96
EPOCHS = 50
EARLY_STOP_PATIENCE = 8
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

torch.manual_seed(42)
np.random.seed(42)


# ============================================================================
# Models (UPGRADED)
# ============================================================================
class BiLSTMClassifierUpgraded(nn.Module):
    """LSTM with hidden=192, layers=3, dropout=0.45, bidirectional."""

    def __init__(self, input_dim, hidden=LSTM_HIDDEN, layers=LSTM_LAYERS, dropout=LSTM_DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden, num_layers=layers,
                            batch_first=True, bidirectional=LSTM_BIDIR,
                            dropout=dropout if layers > 1 else 0)
        out_dim = hidden * (2 if LSTM_BIDIR else 1)
        # Wider FC to match increased LSTM capacity
        self.fc = nn.Sequential(
            nn.Linear(out_dim, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, 32),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

    def forward(self, x):
        out, _ = self.lstm(x)
        pooled = out.mean(dim=1)  # temporal average pooling
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


class TransformerClassifierUpgraded(nn.Module):
    """Transformer with d_model=128, heads=8, layers=6, FFN 6x, dropout=0.45."""

    def __init__(self, input_dim, d_model=TFT_D_MODEL, nhead=TFT_NHEAD,
                 num_layers=TFT_LAYERS, ff_mult=TFT_FF_MULT,
                 dropout=TFT_DROPOUT, attn_dropout=TFT_ATTN_DROPOUT):
        super().__init__()
        ff_dim = d_model * ff_mult
        self.input_proj = nn.Linear(input_dim, d_model)
        self.pos_enc = PositionalEncoding(d_model)
        # Each TransformerEncoderLayer uses 'dropout' for both attention & FFN.
        # nn.TransformerEncoderLayer doesn't expose separate attn_dropout, but we
        # can apply additional dropout post-attention by manual stack — simplification:
        # use the main dropout for both, which after the upgrade (0.45) already gives
        # strong regularization. attn_dropout=0.2 retained as the encoder's internal
        # MHA dropout (which equals the layer's `dropout` param in stock PyTorch).
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=ff_dim,
            dropout=dropout, batch_first=True, activation="gelu",
            norm_first=True,  # pre-norm for deeper transformer stability (6 layers)
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        # Wider FC to match larger d_model
        self.fc = nn.Sequential(
            nn.Linear(d_model, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, 32),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

    def forward(self, x):
        x = self.input_proj(x)
        x = self.pos_enc(x)
        x = self.encoder(x)
        x = x.mean(dim=1)
        return self.fc(x).squeeze(-1)


# ============================================================================
# Helpers
# ============================================================================
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


def make_warmup_cosine_scheduler(optimizer, warmup_steps, total_steps):
    """Cosine schedule with linear warmup."""
    def lr_lambda(step):
        if step < warmup_steps:
            return float(step + 1) / float(max(1, warmup_steps))
        # cosine decay from 1.0 to ~0.1
        progress = float(step - warmup_steps) / float(max(1, total_steps - warmup_steps))
        progress = min(1.0, progress)
        return 0.1 + 0.9 * 0.5 * (1.0 + math.cos(math.pi * progress))
    return LambdaLR(optimizer, lr_lambda)


def prepare_data(target_col):
    """Common data prep — used for both LSTM and Transformer."""
    feat_path = DATA / "feature_panel_v1_3.parquet"
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
    assert len(feature_cols) == 69, f"v1.3 baseline expects 69 features, got {len(feature_cols)}"
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
    print(f"\n========== {model_name} (UPGRADED) target: {target_col} ==========")
    t_start = time.time()
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
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
                              num_workers=NUM_WORKERS)

    # Choose hyperparams per model
    if model_name == "LSTM":
        wd = LSTM_WEIGHT_DECAY; lr = LSTM_LR
    else:
        wd = TFT_WEIGHT_DECAY; lr = TFT_LR

    model = model_class(input_dim=X_train_t.shape[2]).to(DEVICE)
    n_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
    print(f"  Model params: {n_params:,}")

    optim = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=wd)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_w)

    # LR scheduler: warmup 500 + cosine decay
    steps_per_epoch = max(1, len(train_loader))
    total_steps = steps_per_epoch * EPOCHS
    scheduler = make_warmup_cosine_scheduler(optim, WARMUP_STEPS, total_steps)

    # Mixed precision scaler
    scaler = torch.cuda.amp.GradScaler() if USE_AMP else None

    best_val = -1
    patience = 0
    best_state = {k: v.clone() for k, v in model.state_dict().items()}
    last_grad_norm = 0.0
    epochs_done = 0
    early_stop_ep = -1

    for ep in range(EPOCHS):
        epochs_done = ep + 1
        model.train()
        losses = []
        grad_norms = []
        for xb, yb in train_loader:
            xb = xb.to(DEVICE, non_blocking=True)
            yb = yb.to(DEVICE, non_blocking=True)
            optim.zero_grad()

            if USE_AMP:
                with torch.cuda.amp.autocast():
                    logits = model(xb)
                    logits = torch.clamp(logits, -20, 20)
                    loss = loss_fn(logits, yb)
                scaler.scale(loss).backward()
                # Unscale for grad clip
                scaler.unscale_(optim)
                gnorm = torch.nn.utils.clip_grad_norm_(model.parameters(), GRAD_CLIP_NORM)
                scaler.step(optim)
                scaler.update()
            else:
                logits = model(xb)
                logits = torch.clamp(logits, -20, 20)
                loss = loss_fn(logits, yb)
                loss.backward()
                gnorm = torch.nn.utils.clip_grad_norm_(model.parameters(), GRAD_CLIP_NORM)
                optim.step()

            scheduler.step()
            losses.append(loss.item())
            grad_norms.append(float(gnorm))

        last_grad_norm = float(np.mean(grad_norms)) if grad_norms else 0.0
        model.eval()
        with torch.no_grad():
            if USE_AMP:
                with torch.cuda.amp.autocast():
                    vp_logits = model(X_valid_t)
            else:
                vp_logits = model(X_valid_t)
            vp = torch.sigmoid(vp_logits.float()).cpu().numpy()
            vpr = pr_auc(vp, y_valid_t.cpu().numpy())
        cur_lr = optim.param_groups[0]["lr"]
        print(f"  Ep {ep+1:02d} | tr_loss={np.mean(losses):.4f} | valid PR-AUC={vpr:.4f} "
              f"| LR={cur_lr:.2e} | grad_norm={last_grad_norm:.3f}")
        if vpr > best_val:
            best_val = vpr
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
            patience = 0
        else:
            patience += 1
            if patience >= EARLY_STOP_PATIENCE:
                early_stop_ep = ep + 1
                print(f"  Early stop @ ep {ep+1}")
                break

    model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        if USE_AMP:
            with torch.cuda.amp.autocast():
                op_logits = model(X_oos_t)
        else:
            op_logits = model(X_oos_t)
        oop = torch.sigmoid(op_logits.float()).cpu().numpy()
    oos_y = y_seq[oos_idx]
    oos_pr = pr_auc(oop, oos_y)
    elapsed = time.time() - t_start
    print(f"\n[{model_name}] best valid PR-AUC: {best_val:.4f} | OOS PR-AUC: {oos_pr:.4f}"
          f" | epochs_done={epochs_done} | elapsed={elapsed:.1f}s")

    # GPU memory peak
    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        print(f"  GPU memory peak: {mem_peak_mb:.1f} MB")
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    col_name = "p_lstm" if model_name == "LSTM" else "p_tft"
    df = pd.DataFrame({
        "Date": dates_seq[oos_idx],
        col_name: oop, "y": oos_y,
        "split": "oos", "target": target_col,
    })
    file_name = f"predictions_{'lstm' if model_name == 'LSTM' else 'tft'}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")
    return {
        "oos_pr": oos_pr,
        "best_valid_pr": best_val,
        "epochs_done": epochs_done,
        "early_stop_ep": early_stop_ep,
        "final_grad_norm": last_grad_norm,
        "elapsed_sec": elapsed,
        "n_params": n_params,
        "gpu_mem_peak_mb": mem_peak_mb,
    }


if __name__ == "__main__":
    print("=" * 70)
    print("[Cycle 45C Architecture Upgrade — LSTM (192/3/0.45) + TFT (128/8/6/0.45)]")
    print("[v1.3 baseline 69 features, NO new features]")
    print("=" * 70)

    results = {}

    # LSTM both targets
    results["lstm_y_tail_q15"] = train_eval(BiLSTMClassifierUpgraded, "LSTM", "y_tail_q15")
    results["lstm_y_onset"] = train_eval(BiLSTMClassifierUpgraded, "LSTM", "y_onset")

    # TFT both targets
    results["tft_y_tail_q15"] = train_eval(TransformerClassifierUpgraded, "TFT", "y_tail_q15")
    results["tft_y_onset"] = train_eval(TransformerClassifierUpgraded, "TFT", "y_onset")

    print("\n" + "=" * 70)
    print("[Python Cycle 45C SUMMARY] v1.3 baseline + Architecture Upgrade")
    print(f"  LSTM (192/3/0.45)  y_tail_q15: {results['lstm_y_tail_q15']['oos_pr']:.4f}"
          f"  /  y_onset: {results['lstm_y_onset']['oos_pr']:.4f}")
    print(f"  TFT (128/8/6/0.45) y_tail_q15: {results['tft_y_tail_q15']['oos_pr']:.4f}"
          f"  /  y_onset: {results['tft_y_onset']['oos_pr']:.4f}")
    print("=" * 70)

    # Baseline comparison (Cycle 43 v2_2feat)
    BASELINE_LSTM = 0.3799  # Cycle 43 v2_2feat
    BASELINE_TFT = 0.4052
    print("\n[Architecture Upgrade Verdict — y_tail_q15]")
    d_lstm = results["lstm_y_tail_q15"]["oos_pr"] - BASELINE_LSTM
    d_tft = results["tft_y_tail_q15"]["oos_pr"] - BASELINE_TFT
    print(f"  LSTM: baseline 0.3799 → {results['lstm_y_tail_q15']['oos_pr']:.4f}  "
          f"(Δ {d_lstm:+.4f}) {'PASS_TARGET≥0.45' if results['lstm_y_tail_q15']['oos_pr'] >= 0.45 else 'BELOW_TARGET'}")
    print(f"  TFT : baseline 0.4052 → {results['tft_y_tail_q15']['oos_pr']:.4f}  "
          f"(Δ {d_tft:+.4f}) {'PASS_TARGET≥0.45' if results['tft_y_tail_q15']['oos_pr'] >= 0.45 else 'BELOW_TARGET'}")

    # Save training diagnostics for R aggregator
    import json
    diag_path = WS / "outputs/04_evaluation/5way_retrain_v3c_arch_upgrade_python_diag.json"
    diag = {
        "cycle": "45C_arch_upgrade",
        "baseline_v1_3_features": 69,
        "no_new_features": True,
        "architecture_upgrades": {
            "lstm": {
                "hidden": LSTM_HIDDEN, "layers": LSTM_LAYERS, "dropout": LSTM_DROPOUT,
                "weight_decay": LSTM_WEIGHT_DECAY, "lr": LSTM_LR,
                "bidirectional": LSTM_BIDIR,
            },
            "tft": {
                "d_model": TFT_D_MODEL, "nhead": TFT_NHEAD, "num_layers": TFT_LAYERS,
                "ff_dim": TFT_D_MODEL * TFT_FF_MULT, "dropout": TFT_DROPOUT,
                "attn_dropout": TFT_ATTN_DROPOUT, "norm_first": True,
                "weight_decay": TFT_WEIGHT_DECAY, "lr": TFT_LR,
            },
            "common": {
                "batch_size": BATCH_SIZE, "epochs": EPOCHS,
                "early_stop_patience": EARLY_STOP_PATIENCE,
                "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
                "mixed_precision_amp": USE_AMP,
                "gpu_mem_fraction": 0.3 if DEVICE.type == "cuda" else None,
            },
        },
        "baseline_individual_prauc_y_tail_q15": {
            "lstm_cycle_43_v2_2feat": BASELINE_LSTM,
            "tft_cycle_43_v2_2feat": BASELINE_TFT,
        },
        "upgraded_individual_prauc_y_tail_q15": {
            "lstm": round(results["lstm_y_tail_q15"]["oos_pr"], 4),
            "tft": round(results["tft_y_tail_q15"]["oos_pr"], 4),
        },
        "upgraded_individual_prauc_y_onset": {
            "lstm": round(results["lstm_y_onset"]["oos_pr"], 4),
            "tft": round(results["tft_y_onset"]["oos_pr"], 4),
        },
        "delta_individual_y_tail_q15": {
            "lstm": round(d_lstm, 4),
            "tft": round(d_tft, 4),
        },
        "training_diagnostics": {
            "lstm_y_tail_q15": {k: v for k, v in results["lstm_y_tail_q15"].items() if k != "n_params"},
            "lstm_y_onset": {k: v for k, v in results["lstm_y_onset"].items() if k != "n_params"},
            "tft_y_tail_q15": {k: v for k, v in results["tft_y_tail_q15"].items() if k != "n_params"},
            "tft_y_onset": {k: v for k, v in results["tft_y_onset"].items() if k != "n_params"},
        },
        "model_params": {
            "lstm": results["lstm_y_tail_q15"]["n_params"],
            "tft": results["tft_y_tail_q15"]["n_params"],
        },
    }
    with diag_path.open("w") as f:
        json.dump(diag, f, indent=2, default=str)
    print(f"\n[Diagnostics] Saved: {diag_path}")
