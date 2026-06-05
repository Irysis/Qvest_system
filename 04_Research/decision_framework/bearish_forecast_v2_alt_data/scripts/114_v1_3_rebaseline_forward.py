#!/usr/bin/env python3
"""
114_v1_3_rebaseline_forward.py — Cycle 50 Phase 2 v1.3 baseline RE-BASELINE Python

Mirrors scripts/93_5way_retrain_v3d_walkforward.py, but with:
  - targets_full_forward.parquet (Cycle 50 forward labels)
  - feature_panel_v1_3.parquet (PIT-validated 69 features, retained)
  - Output: outputs/03_models/v1_3_forward/predictions_{lstm,tft}_{target}.parquet
  - Diag : outputs/04_evaluation/v1_3_rebaseline_forward_python_diag.json

Walk-forward 5-fold CV identical to 45D (same architectures, same patience 15,
max_epochs 80, min_delta 0.0005). OOS = 2018-2026.
"""

import sys
import math
import time
import json
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
OUT = WS / "outputs/03_models/v1_3_forward"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 50 v1.3 forward] Device: {DEVICE}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.3, device=0)
    except Exception as e:
        print(f"[CUDA fraction set failed] {e}")
    USE_AMP = True
else:
    USE_AMP = False

# Cycle 50 forward target file (Phase 1 output)
TARGET_FILE = TGT / "targets_full_forward.parquet"
FEATURE_FILE = DATA / "feature_panel_v1_3.parquet"
N_FEATURES_EXPECTED = 69

OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")
FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

FOLDS = [
    dict(name="Fold1_Lehman",     train_start="1995-01-01", train_end="2007-12-31",
         valid_start="2008-01-01", valid_end="2009-12-31"),
    dict(name="Fold2_EuroAfter",  train_start="1995-01-01", train_end="2009-12-31",
         valid_start="2010-01-01", valid_end="2011-12-31"),
    dict(name="Fold3_CyprusTT",   train_start="1995-01-01", train_end="2011-12-31",
         valid_start="2012-01-01", valid_end="2013-12-31"),
    dict(name="Fold4_KRLowVol",   train_start="1995-01-01", train_end="2013-12-31",
         valid_start="2014-01-01", valid_end="2015-12-31"),
    dict(name="Fold5_BestSignal", train_start="1995-01-01", train_end="2015-12-31",
         valid_start="2016-01-01", valid_end="2017-12-31"),
]

# Architecture HYPERPARAMS — identical to 45C/45D
LSTM_HIDDEN = 192
LSTM_LAYERS = 3
LSTM_DROPOUT = 0.45
LSTM_BIDIR = True
LSTM_WEIGHT_DECAY = 5e-3
LSTM_LR = 1e-3

TFT_D_MODEL = 128
TFT_NHEAD = 8
TFT_LAYERS = 6
TFT_FF_MULT = 6
TFT_DROPOUT = 0.45
TFT_ATTN_DROPOUT = 0.2
TFT_WEIGHT_DECAY = 5e-3
TFT_LR = 1e-3

BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

torch.manual_seed(42)
np.random.seed(42)


class BiLSTMClassifierUpgraded(nn.Module):
    def __init__(self, input_dim, hidden=LSTM_HIDDEN, layers=LSTM_LAYERS, dropout=LSTM_DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden, num_layers=layers,
                            batch_first=True, bidirectional=LSTM_BIDIR,
                            dropout=dropout if layers > 1 else 0)
        out_dim = hidden * (2 if LSTM_BIDIR else 1)
        self.fc = nn.Sequential(
            nn.Linear(out_dim, 64), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(64, 32), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

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


class TransformerClassifierUpgraded(nn.Module):
    def __init__(self, input_dim, d_model=TFT_D_MODEL, nhead=TFT_NHEAD,
                 num_layers=TFT_LAYERS, ff_mult=TFT_FF_MULT,
                 dropout=TFT_DROPOUT, attn_dropout=TFT_ATTN_DROPOUT):
        super().__init__()
        ff_dim = d_model * ff_mult
        self.input_proj = nn.Linear(input_dim, d_model)
        self.pos_enc = PositionalEncoding(d_model)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=ff_dim,
            dropout=dropout, batch_first=True, activation="gelu",
            norm_first=True,
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.fc = nn.Sequential(
            nn.Linear(d_model, 64), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(64, 32), nn.GELU(), nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

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


def make_warmup_cosine_scheduler(optimizer, warmup_steps, total_steps):
    def lr_lambda(step):
        if step < warmup_steps:
            return float(step + 1) / float(max(1, warmup_steps))
        progress = float(step - warmup_steps) / float(max(1, total_steps - warmup_steps))
        progress = min(1.0, progress)
        return 0.1 + 0.9 * 0.5 * (1.0 + math.cos(math.pi * progress))
    return LambdaLR(optimizer, lr_lambda)


def prepare_data_full(target_col):
    if not FEATURE_FILE.exists():
        sys.exit(f"missing feature panel: {FEATURE_FILE}")
    if not TARGET_FILE.exists():
        sys.exit(f"missing forward target parquet: {TARGET_FILE}")

    feat = pd.read_parquet(FEATURE_FILE)
    tgt = pd.read_parquet(TARGET_FILE)[["Date", target_col]]
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])
    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END]

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    assert len(feature_cols) == N_FEATURES_EXPECTED, \
        f"v1.3 baseline expects {N_FEATURES_EXPECTED} features, got {len(feature_cols)}"

    X = panel[feature_cols].values.astype(np.float32)
    y_raw = panel[target_col].fillna(0).values.astype(np.float32)
    dates = panel["Date"].values
    return X, y_raw, dates, feature_cols


def standardize_for_window(X, dates, train_start, train_end):
    train_mask = (dates >= np.datetime64(train_start)) & (dates <= np.datetime64(train_end))
    X_work = X.copy()
    col_med = np.nan_to_num(np.nanmedian(X_work[train_mask], axis=0), nan=0.0)
    for j in range(X_work.shape[1]):
        X_work[np.isnan(X_work[:, j]), j] = col_med[j]
    mean = np.nan_to_num(X_work[train_mask].mean(axis=0), nan=0.0)
    std = np.nan_to_num(X_work[train_mask].std(axis=0), nan=1.0) + 1e-6
    std[std < 1e-6] = 1.0
    Xs = (X_work - mean) / std
    Xs = np.clip(Xs, -10.0, 10.0)
    Xs = np.nan_to_num(Xs, nan=0.0, posinf=0.0, neginf=0.0)
    return Xs


def train_one_window(model_class, model_name, target_col,
                     X_full, y_full, dates,
                     train_start, train_end,
                     valid_start=None, valid_end=None,
                     fixed_epochs=None, fold_label=""):
    Xs = standardize_for_window(X_full, dates, train_start, train_end)
    X_seq, y_seq = make_sequences(Xs, y_full, SEQ_LEN)
    dates_seq = dates[SEQ_LEN - 1:]

    train_idx = (dates_seq >= np.datetime64(train_start)) & (dates_seq <= np.datetime64(train_end))

    X_train_t = torch.tensor(X_seq[train_idx], dtype=torch.float32)
    y_train_t = torch.tensor(y_seq[train_idx], dtype=torch.float32)

    has_valid = (valid_start is not None) and (valid_end is not None)
    if has_valid:
        valid_idx = (dates_seq >= np.datetime64(valid_start)) & (dates_seq <= np.datetime64(valid_end))
        X_valid_t = torch.tensor(X_seq[valid_idx], dtype=torch.float32).to(DEVICE)
        y_valid_t = torch.tensor(y_seq[valid_idx], dtype=torch.float32).to(DEVICE)
        valid_bear = int(y_valid_t.sum().item())
    else:
        valid_idx = None; X_valid_t = None; y_valid_t = None; valid_bear = -1

    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)

    train_loader = DataLoader(TensorDataset(X_train_t, y_train_t),
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
                              num_workers=NUM_WORKERS)

    if model_name == "LSTM":
        wd = LSTM_WEIGHT_DECAY; lr = LSTM_LR
    else:
        wd = TFT_WEIGHT_DECAY; lr = TFT_LR

    model = model_class(input_dim=X_train_t.shape[2]).to(DEVICE)
    n_params = sum(p.numel() for p in model.parameters() if p.requires_grad)

    optim = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=wd)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_w)

    steps_per_epoch = max(1, len(train_loader))
    total_steps = steps_per_epoch * MAX_EPOCHS
    scheduler = make_warmup_cosine_scheduler(optim, WARMUP_STEPS, total_steps)
    scaler = torch.amp.GradScaler("cuda") if USE_AMP else None

    best_val = -1.0
    best_epoch = -1
    patience = 0
    best_state = {k: v.clone() for k, v in model.state_dict().items()}
    train_loss_traj = []

    target_epochs = fixed_epochs if fixed_epochs is not None else MAX_EPOCHS
    epochs_done = 0
    early_stop_ep = -1

    print(f"    [{model_name}] {fold_label} train_n={int(train_idx.sum())}"
          f" valid_n={'-' if not has_valid else int(valid_idx.sum())}"
          f" pos_w={pos_w_value:.2f} target_ep={target_epochs}")

    for ep in range(target_epochs):
        epochs_done = ep + 1
        model.train(); losses = []
        for xb, yb in train_loader:
            xb = xb.to(DEVICE, non_blocking=True)
            yb = yb.to(DEVICE, non_blocking=True)
            optim.zero_grad()

            if USE_AMP:
                with torch.amp.autocast("cuda"):
                    logits = model(xb)
                    logits = torch.clamp(logits, -20, 20)
                    loss = loss_fn(logits, yb)
                scaler.scale(loss).backward()
                scaler.unscale_(optim)
                torch.nn.utils.clip_grad_norm_(model.parameters(), GRAD_CLIP_NORM)
                scaler.step(optim); scaler.update()
            else:
                logits = model(xb)
                logits = torch.clamp(logits, -20, 20)
                loss = loss_fn(logits, yb)
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), GRAD_CLIP_NORM)
                optim.step()
            scheduler.step()
            losses.append(loss.item())
        train_loss_traj.append(float(np.mean(losses)) if losses else float("nan"))

        if has_valid:
            model.eval()
            with torch.no_grad():
                if USE_AMP:
                    with torch.amp.autocast("cuda"):
                        vp_logits = model(X_valid_t)
                else:
                    vp_logits = model(X_valid_t)
                vp = torch.sigmoid(vp_logits.float()).cpu().numpy()
                vpr = pr_auc(vp, y_valid_t.cpu().numpy())
            if vpr > best_val + EARLY_STOP_MIN_DELTA:
                best_val = vpr; best_epoch = ep + 1
                best_state = {k: v.clone() for k, v in model.state_dict().items()}
                patience = 0
            else:
                patience += 1
                if fixed_epochs is None and patience >= EARLY_STOP_PATIENCE:
                    early_stop_ep = ep + 1
                    print(f"      Early stop @ ep {ep+1} (best ep={best_epoch}, best_vpr={best_val:.4f})")
                    break

    if fixed_epochs is not None and not has_valid:
        best_state = {k: v.clone() for k, v in model.state_dict().items()}
        best_epoch = epochs_done

    model.load_state_dict(best_state)

    return model, Xs, dates_seq, y_seq, dict(
        fold=fold_label, model=model_name, target=target_col,
        best_valid_pr=round(best_val, 4) if has_valid else None,
        best_epoch=int(best_epoch) if best_epoch > 0 else None,
        epochs_done=int(epochs_done),
        early_stop_ep=int(early_stop_ep) if early_stop_ep > 0 else None,
        valid_bear_count=int(valid_bear) if has_valid else None,
        train_loss_first=round(train_loss_traj[0], 4) if train_loss_traj else None,
        train_loss_last=round(train_loss_traj[-1], 4) if train_loss_traj else None,
        n_params=int(n_params),
    )


def run_walkforward_for(model_class, model_name, target_col):
    print("\n" + "=" * 70)
    print(f"[Cycle 50 forward] {model_name} target: {target_col}")
    print("=" * 70)
    t_start = time.time()

    X_full, y_full, dates, _ = prepare_data_full(target_col)

    fold_results = []
    for fi in FOLDS:
        print(f"\n  --- {fi['name']} ---")
        _, _, _, _, fold_res = train_one_window(
            model_class, model_name, target_col,
            X_full, y_full, dates,
            train_start=fi["train_start"], train_end=fi["train_end"],
            valid_start=fi["valid_start"], valid_end=fi["valid_end"],
            fixed_epochs=None, fold_label=fi["name"],
        )
        fold_results.append(fold_res)
        if DEVICE.type == "cuda":
            torch.cuda.empty_cache()

    valid_eps = [r["best_epoch"] for r in fold_results
                 if r["best_epoch"] is not None and r["best_epoch"] > 0]
    if len(valid_eps) == 0:
        avg_best_ep = MAX_EPOCHS // 2
        print(f"\n  [WARN] All folds returned best_epoch <= 0 — fallback {avg_best_ep}")
    else:
        avg_best_ep = int(round(np.mean(valid_eps)))
    print(f"\n  [Avg best_epoch] = {avg_best_ep}")
    print(f"  [Per-fold best_epoch] = {[r['best_epoch'] for r in fold_results]}")
    print(f"  [Per-fold best_valid_pr] = {[r['best_valid_pr'] for r in fold_results]}")

    print(f"\n  --- Final training: TRAIN 1995-2015 / epochs={avg_best_ep} ---")
    final_model, Xs_final, _, _, final_train_res = train_one_window(
        model_class, model_name, target_col,
        X_full, y_full, dates,
        train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
        valid_start=None, valid_end=None,
        fixed_epochs=avg_best_ep, fold_label="FINAL_TRAIN",
    )

    print(f"\n  --- OOS evaluation: 2018-2026 ---")
    X_seq_final, y_seq_final2 = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final2 = dates[SEQ_LEN - 1:]
    oos_idx = (dates_seq_final2 >= np.datetime64(OOS_START)) & (dates_seq_final2 <= np.datetime64(OOS_END))
    X_oos_t = torch.tensor(X_seq_final[oos_idx], dtype=torch.float32).to(DEVICE)

    final_model.eval()
    with torch.no_grad():
        # Batched OOS inference
        bs = 512
        oop_list = []
        for i in range(0, X_oos_t.size(0), bs):
            chunk = X_oos_t[i:i + bs]
            if USE_AMP:
                with torch.amp.autocast("cuda"):
                    lo = final_model(chunk)
            else:
                lo = final_model(chunk)
            oop_list.append(torch.sigmoid(lo.float()).cpu().numpy())
        oop = np.concatenate(oop_list, axis=0)

    oos_y = y_seq_final2[oos_idx]
    oos_pr_v = pr_auc(oop, oos_y)
    elapsed = time.time() - t_start
    print(f"\n  [{model_name}] OOS PR-AUC: {oos_pr_v:.4f}  | elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    col_name = "p_lstm" if model_name == "LSTM" else "p_tft"
    df = pd.DataFrame({
        "Date": dates_seq_final2[oos_idx],
        col_name: oop, "y": oos_y,
        "split": "oos", "target": target_col,
    })
    file_name = f"predictions_{'lstm' if model_name == 'LSTM' else 'tft'}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")

    del final_model
    if DEVICE.type == "cuda":
        torch.cuda.empty_cache()

    return dict(
        model=model_name, target=target_col,
        oos_pr=oos_pr_v, avg_best_epoch=avg_best_ep,
        per_fold=fold_results, final_train=final_train_res,
        elapsed_sec=elapsed, gpu_mem_peak_mb=mem_peak_mb,
        n_params=final_train_res["n_params"],
    )


if __name__ == "__main__":
    print("=" * 70)
    print("[Cycle 50 v1.3 RE-BASELINE — LSTM + TFT (forward labels)]")
    print(f"[Target file: {TARGET_FILE}]")
    print(f"[Feature file: {FEATURE_FILE}]")
    print(f"[OOS window: 2018-2026]")
    print("=" * 70)

    results = {}

    results["lstm_y_tail_q15"] = run_walkforward_for(BiLSTMClassifierUpgraded, "LSTM", "y_tail_q15")
    results["lstm_y_onset"] = run_walkforward_for(BiLSTMClassifierUpgraded, "LSTM", "y_onset")
    results["tft_y_tail_q15"] = run_walkforward_for(TransformerClassifierUpgraded, "TFT", "y_tail_q15")
    results["tft_y_onset"] = run_walkforward_for(TransformerClassifierUpgraded, "TFT", "y_onset")

    print("\n" + "=" * 70)
    print("[Python Cycle 50 v1.3 forward SUMMARY]")
    print(f"  LSTM  y_tail_q15: OOS={results['lstm_y_tail_q15']['oos_pr']:.4f}  "
          f"avg_ep={results['lstm_y_tail_q15']['avg_best_epoch']}")
    print(f"  LSTM  y_onset:    OOS={results['lstm_y_onset']['oos_pr']:.4f}  "
          f"avg_ep={results['lstm_y_onset']['avg_best_epoch']}")
    print(f"  TFT   y_tail_q15: OOS={results['tft_y_tail_q15']['oos_pr']:.4f}  "
          f"avg_ep={results['tft_y_tail_q15']['avg_best_epoch']}")
    print(f"  TFT   y_onset:    OOS={results['tft_y_onset']['oos_pr']:.4f}  "
          f"avg_ep={results['tft_y_onset']['avg_best_epoch']}")
    print("=" * 70)

    per_fold_path = OUT / "per_fold_diagnostics.json"
    per_fold = {
        "cycle": "50_v1_3_rebaseline_forward",
        "target_file": str(TARGET_FILE),
        "feature_file": str(FEATURE_FILE),
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date())},
        "results": {k: {**{kk: vv for kk, vv in v.items() if kk not in ("per_fold", "final_train")},
                        "per_fold": v["per_fold"],
                        "final_train": v["final_train"]}
                    for k, v in results.items()},
    }
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"\n[Per-fold diagnostics] {per_fold_path}")

    diag_path = EVAL_DIR / "v1_3_rebaseline_forward_python_diag.json"
    diag = {
        "cycle": "50_v1_3_rebaseline_forward",
        "baseline_v1_3_features": N_FEATURES_EXPECTED,
        "forward_labels": True,
        "bug_fix_commit": "Cycle 50 Phase 1: scripts/02_target_builder.R line 39",
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "v1_3_forward_oos_y_tail_q15": {
            "lstm": round(results["lstm_y_tail_q15"]["oos_pr"], 4),
            "tft": round(results["tft_y_tail_q15"]["oos_pr"], 4),
            "lstm_avg_ep": results["lstm_y_tail_q15"]["avg_best_epoch"],
            "tft_avg_ep": results["tft_y_tail_q15"]["avg_best_epoch"],
        },
        "v1_3_forward_oos_y_onset": {
            "lstm": round(results["lstm_y_onset"]["oos_pr"], 4),
            "tft": round(results["tft_y_onset"]["oos_pr"], 4),
            "lstm_avg_ep": results["lstm_y_onset"]["avg_best_epoch"],
            "tft_avg_ep": results["tft_y_onset"]["avg_best_epoch"],
        },
    }
    with diag_path.open("w") as f:
        json.dump(diag, f, indent=2, default=str)
    print(f"[Diagnostics] {diag_path}")
