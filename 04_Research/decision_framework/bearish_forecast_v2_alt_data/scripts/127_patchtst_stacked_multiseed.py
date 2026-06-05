#!/usr/bin/env python3
"""
127_patchtst_stacked_multiseed.py — Cycle 53C Stacked Best Q15 Multi-Seed Audit

Stacked best PatchTST config (3-axis combination of Cycle 53A winners):
  - d_model    32   (v4 winner: q15 0.2571, Δ +0.0175)
  - n_layers   2    (v8 winner: q15 0.2533, Δ +0.0138)
  - dropout    0.20 (v10 winner: q15 0.2598, Δ +0.0202)
  - patch_size 4    (sweet spot retain)
  - n_heads    4    (sweet spot retain)
  - stride     2    (sweet spot retain)
  - attn_dropout 0.10  (= 0.20 * 0.5; baseline pair ratio 0.15/0.30 = 0.5)

Cycle 53A v10 (single seed=42) finding:
  q15 PR-AUC 0.2598, Δ +0.0202 vs baseline 0.2396 — EXACTLY at breakthrough threshold.
  Within seed noise (±0.007). 1/3 chance noise → multi-seed audit MANDATORY.

Multi-seed audit:
  - 3 seeds [42, 123, 456]
  - Walk-forward expanding 5-fold CV per seed
  - Per-seed PR-AUC + per-fold variance audit (Cycle 52 N-BEATS pattern)
  - 3-seed mean prediction PR-AUC

Verdicts (additivity):
  - ADDITIVE_STRONG  (stacked > v10 +0.02)   → 3-axis combine effective
  - ADDITIVE_WEAK    (stacked > v10 +0.005)  → marginal
  - NON_ADDITIVE     (stacked ≈ v10)         → single-axis only, combine no value
  - NEGATIVE         (stacked < v10)         → combine causes dilution

Verdicts (multi-seed stability):
  - STABLE     (per-seed std < 0.02)         → v10 result trustworthy
  - MODERATE   (0.02-0.05)                    → additional multi-seed needed
  - UNSTABLE   (>0.05)                        → single-seed v10 invalidated, headline hold

Targets: y_tail_q15 primary + y_onset secondary (forward labels, Cycle 50 fix)
Features: v4a panel 70 features (Cycle 52 result)

Output:
  outputs/03_models/v5c_stacked_multiseed/predictions_stacked_seed{42|123|456}_y_{tail_q15|onset}.parquet  (6 files)
  outputs/03_models/v5c_stacked_multiseed/predictions_stacked_mean_y_{tail_q15|onset}.parquet              (2 files, 3-seed mean)
  outputs/03_models/v5c_stacked_multiseed/per_fold_diagnostics.json
  outputs/03_models/v5c_stacked_multiseed/multiseed_variance_audit.json

Pipeline: 3 seeds × 5 folds × 2 targets = 30 walk-forward folds + 3 seeds × 2 targets = 6 final training runs.
"""

import sys
import math
import time
import json
import warnings
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, TensorDataset
from torch.optim.lr_scheduler import LambdaLR

warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UserWarning)

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
TGT = WS / "outputs/02_targets"
OUT = WS / "outputs/03_models/v5c_stacked_multiseed"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 53C] Device: {DEVICE}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.30, device=0)
        print(f"[Cycle 53C] CUDA memory fraction set to 0.30 (parallel-safe with 53E + 53H)")
    except Exception as e:
        print(f"[Cycle 53C] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 53C] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window (Cycle 52/53A retain)
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

# Training constants (Cycle 52/53A retain)
PT_FF_MULT = 4
PT_ATTN_DROPOUT_RATIO = 0.15 / 0.30  # baseline pair ratio = 0.5
PT_WEIGHT_DECAY = 5e-3
PT_LR = 1e-3

BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

SEEDS = [42, 123, 456]

# ============================================================================
# Stacked best config
# ============================================================================
STACKED_CONFIG = dict(
    name="stacked_v4_v8_v10",
    patch_size=4,
    d_model=32,         # v4 winner
    n_heads=4,
    n_layers=2,         # v8 winner
    dropout=0.20,       # v10 winner
    stride=2,
)


# ============================================================================
# PatchTST: Channel-Independent Patch Transformer (Cycle 45E/52/53A retain)
# ============================================================================
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


class PatchTSTClassifier(nn.Module):
    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 patch_size=4, patch_stride=2,
                 d_model=32, nhead=4,
                 num_layers=2, ff_mult=4,
                 dropout=0.20, attn_dropout=0.10):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.patch_size = patch_size
        self.patch_stride = patch_stride
        self.d_model = d_model

        self.n_patches = (seq_len - patch_size) // patch_stride + 1

        self.patch_proj = nn.Linear(patch_size, d_model)
        self.channel_embed = nn.Parameter(torch.randn(input_dim, 1, d_model) * 0.02)
        self.pos_enc = PositionalEncoding(d_model, max_len=self.n_patches + 8)

        ff_dim = d_model * ff_mult
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=ff_dim,
            dropout=dropout, batch_first=True, activation="gelu",
            norm_first=True,
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)

        self.dropout = nn.Dropout(dropout)
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, 1),
        )

    def forward(self, x):
        B, L, C = x.shape
        x = x.permute(0, 2, 1).contiguous()
        x = x.unfold(dimension=2, size=self.patch_size, step=self.patch_stride)
        x = self.patch_proj(x)
        x = x + self.channel_embed.unsqueeze(0)
        x = x.reshape(B * C, self.n_patches, self.d_model)
        x = self.pos_enc(x)
        x = self.encoder(x)
        x = x.mean(dim=1)
        x = x.reshape(B, C, self.d_model)
        x = x.mean(dim=1)
        x = self.dropout(x)
        return self.head(x).squeeze(-1)


# ============================================================================
# Helpers (Cycle 52/53A retain)
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


def ic_spearman(p, y):
    ok = ~(np.isnan(p) | np.isnan(y))
    p = p[ok]; y = y[ok]
    if len(p) < 30:
        return float("nan")
    return float(np.corrcoef(np.argsort(np.argsort(p)),
                              np.argsort(np.argsort(y)))[0, 1])


def make_warmup_cosine_scheduler(optimizer, warmup_steps, total_steps):
    def lr_lambda(step):
        if step < warmup_steps:
            return float(step + 1) / float(max(1, warmup_steps))
        progress = float(step - warmup_steps) / float(max(1, total_steps - warmup_steps))
        progress = min(1.0, progress)
        return 0.1 + 0.9 * 0.5 * (1.0 + math.cos(math.pi * progress))
    return LambdaLR(optimizer, lr_lambda)


def prepare_data_full(target_col):
    feat_path = DATA / "feature_panel_v4a_combined.parquet"
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
    assert len(feature_cols) == 70, f"v4a combined expects 70 features, got {len(feature_cols)}"

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


def set_seed(seed):
    torch.manual_seed(seed)
    np.random.seed(seed)
    if DEVICE.type == "cuda":
        torch.cuda.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)


def make_model(cfg, input_dim):
    attn_dropout = round(cfg["dropout"] * PT_ATTN_DROPOUT_RATIO, 4)
    return PatchTSTClassifier(
        input_dim=input_dim,
        seq_len=SEQ_LEN,
        patch_size=cfg["patch_size"],
        patch_stride=cfg["stride"],
        d_model=cfg["d_model"],
        nhead=cfg["n_heads"],
        num_layers=cfg["n_layers"],
        ff_mult=PT_FF_MULT,
        dropout=cfg["dropout"],
        attn_dropout=attn_dropout,
    )


def train_one_window(cfg, target_col,
                     X_full, y_full, dates,
                     train_start, train_end,
                     valid_start=None, valid_end=None,
                     fixed_epochs=None, fold_label="", seed=42):
    set_seed(seed)
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
        valid_idx = None
        X_valid_t = None
        y_valid_t = None
        valid_bear = -1

    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)

    train_loader = DataLoader(TensorDataset(X_train_t, y_train_t),
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
                              num_workers=NUM_WORKERS)

    model = make_model(cfg, input_dim=X_train_t.shape[2]).to(DEVICE)
    n_params = sum(p.numel() for p in model.parameters() if p.requires_grad)

    optim = torch.optim.AdamW(model.parameters(), lr=PT_LR, weight_decay=PT_WEIGHT_DECAY)
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

    print(f"    [stacked/seed={seed}] {fold_label} "
          f"train_n={int(train_idx.sum())} "
          f"valid_n={'-' if not has_valid else int(valid_idx.sum())} "
          f"params={n_params:,} pos_w={pos_w_value:.2f} target_ep={target_epochs}")

    for ep in range(target_epochs):
        epochs_done = ep + 1
        model.train()
        losses = []
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
                scaler.step(optim)
                scaler.update()
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
                best_val = vpr
                best_epoch = ep + 1
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

    result = dict(
        fold=fold_label,
        seed=int(seed),
        target=target_col,
        best_valid_pr=round(best_val, 4) if has_valid else None,
        best_epoch=int(best_epoch) if best_epoch > 0 else None,
        epochs_done=int(epochs_done),
        early_stop_ep=int(early_stop_ep) if early_stop_ep > 0 else None,
        valid_bear_count=int(valid_bear) if has_valid else None,
        train_loss_first=round(train_loss_traj[0], 4) if train_loss_traj else None,
        train_loss_last=round(train_loss_traj[-1], 4) if train_loss_traj else None,
        n_params=int(n_params),
    )

    return model, Xs, dates_seq, y_seq, result


def run_seed_walkforward(seed, target_col):
    print("\n" + "=" * 80)
    print(f"[Cycle 53C] seed={seed} target={target_col}")
    print(f"  stacked config: patch_size={STACKED_CONFIG['patch_size']} "
          f"d_model={STACKED_CONFIG['d_model']} n_heads={STACKED_CONFIG['n_heads']} "
          f"n_layers={STACKED_CONFIG['n_layers']} dropout={STACKED_CONFIG['dropout']} "
          f"stride={STACKED_CONFIG['stride']}")
    print("=" * 80)
    t_start = time.time()

    X_full, y_full, dates, _ = prepare_data_full(target_col)

    fold_results = []
    for fi in FOLDS:
        print(f"\n  --- {fi['name']} ---")
        _, _, _, _, fold_res = train_one_window(
            STACKED_CONFIG, target_col,
            X_full, y_full, dates,
            train_start=fi["train_start"], train_end=fi["train_end"],
            valid_start=fi["valid_start"], valid_end=fi["valid_end"],
            fixed_epochs=None, fold_label=fi["name"], seed=seed,
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
    print(f"\n  [Avg best_epoch across {len(valid_eps)} folds] = {avg_best_ep}")
    print(f"  [Per-fold best_epoch] = {[r['best_epoch'] for r in fold_results]}")
    print(f"  [Per-fold best_valid_pr] = {[r['best_valid_pr'] for r in fold_results]}")

    print(f"\n  --- Final training: 1995-2015 / epochs={avg_best_ep} ---")
    final_model, Xs_final, _, _, final_train_res = train_one_window(
        STACKED_CONFIG, target_col,
        X_full, y_full, dates,
        train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
        valid_start=None, valid_end=None,
        fixed_epochs=avg_best_ep, fold_label="FINAL_TRAIN", seed=seed,
    )

    print(f"\n  --- OOS evaluation: 2018-2026 ---")
    X_seq_final, y_seq_final2 = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final2 = dates[SEQ_LEN - 1:]
    oos_idx = (dates_seq_final2 >= np.datetime64(OOS_START)) & (dates_seq_final2 <= np.datetime64(OOS_END))
    X_oos_t = torch.tensor(X_seq_final[oos_idx], dtype=torch.float32).to(DEVICE)

    final_model.eval()
    with torch.no_grad():
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
    oos_dates = dates_seq_final2[oos_idx]
    oos_pr_v = pr_auc(oop, oos_y)
    oos_ic_v = ic_spearman(oop, oos_y)
    elapsed = time.time() - t_start
    print(f"\n  [stacked/seed={seed}/{target_col}] "
          f"OOS PR-AUC: {oos_pr_v:.4f}  IC: {oos_ic_v:.4f}  | elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        print(f"  GPU memory peak: {mem_peak_mb:.1f} MB")
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    df = pd.DataFrame({
        "Date": oos_dates,
        "p_patchtst_stacked": oop,
        "y": oos_y,
        "split": "oos",
        "target": target_col,
        "seed": int(seed),
        "config": "stacked_v4_v8_v10",
    })
    file_name = f"predictions_stacked_seed{seed}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT / file_name}")

    del final_model
    if DEVICE.type == "cuda":
        torch.cuda.empty_cache()

    return dict(
        seed=int(seed),
        target=target_col,
        config=STACKED_CONFIG,
        oos_pr=round(oos_pr_v, 4),
        oos_ic=round(oos_ic_v, 4),
        avg_best_epoch=avg_best_ep,
        per_fold_best_pr=[r["best_valid_pr"] for r in fold_results],
        per_fold_best_epoch=[r["best_epoch"] for r in fold_results],
        per_fold_n_params=fold_results[0]["n_params"],
        final_train_loss_first=final_train_res["train_loss_first"],
        final_train_loss_last=final_train_res["train_loss_last"],
        elapsed_sec=round(elapsed, 1),
        gpu_mem_peak_mb=round(mem_peak_mb, 1) if not math.isnan(mem_peak_mb) else None,
        n_params=int(final_train_res["n_params"]),
        n_oos_obs=int(len(oos_y)),
        n_oos_events=int(oos_y.sum()),
        oos_dates_path=str(OUT / file_name),
    )


def compute_seed_mean_prediction(target_col, seeds):
    """Load per-seed predictions, compute 3-seed mean, save to disk, return PR-AUC + IC."""
    dfs = []
    for s in seeds:
        p = OUT / f"predictions_stacked_seed{s}_{target_col}.parquet"
        if not p.exists():
            print(f"  [WARN] missing {p}")
            continue
        d = pd.read_parquet(p)
        d["Date"] = pd.to_datetime(d["Date"])
        d = d.rename(columns={"p_patchtst_stacked": f"p_seed{s}"})
        dfs.append(d[["Date", "y", f"p_seed{s}"]])

    if len(dfs) == 0:
        return None

    merged = dfs[0]
    for d in dfs[1:]:
        merged = merged.merge(d[["Date", f"p_seed{d.columns[-1].split('p_seed')[-1]}"]],
                              on="Date", how="inner")
    # explicit re-merge using actual column names
    base = dfs[0][["Date", "y"]].copy()
    for d in dfs:
        seed_col = [c for c in d.columns if c.startswith("p_seed")][0]
        base = base.merge(d[["Date", seed_col]], on="Date", how="inner")

    seed_cols = [c for c in base.columns if c.startswith("p_seed")]
    base["p_mean"] = base[seed_cols].mean(axis=1)
    base["p_std"] = base[seed_cols].std(axis=1)

    pa = pr_auc(base["p_mean"].values, base["y"].values)
    ic = ic_spearman(base["p_mean"].values, base["y"].values)

    df_out = pd.DataFrame({
        "Date": base["Date"].values,
        "p_patchtst_stacked_mean": base["p_mean"].values,
        "p_per_seed_std": base["p_std"].values,
        "y": base["y"].values,
        "split": "oos",
        "target": target_col,
        "config": "stacked_v4_v8_v10",
        "n_seeds": len(seeds),
    })
    out_file = OUT / f"predictions_stacked_mean_{target_col}.parquet"
    df_out.to_parquet(out_file, index=False)
    print(f"\n  [3-seed mean / {target_col}] PR-AUC={pa:.4f} IC={ic:.4f} "
          f"per_date_std_mean={float(base['p_std'].mean()):.4f}  saved: {out_file}")

    return dict(
        target=target_col,
        n_seeds=len(seeds),
        oos_pr_mean_prediction=round(pa, 4),
        oos_ic_mean_prediction=round(ic, 4),
        per_date_std_mean=round(float(base["p_std"].mean()), 4),
        per_date_std_median=round(float(base["p_std"].median()), 4),
        per_date_std_max=round(float(base["p_std"].max()), 4),
        n_obs=int(len(base)),
        saved_path=str(out_file),
    )


if __name__ == "__main__":
    print("=" * 80)
    print("[Cycle 53C PatchTST Stacked Best Q15 Multi-Seed Audit]")
    print(f"[Stacked config: d_model=32 / n_layers=2 / dropout=0.20 (3 Cycle 53A winners)]")
    print(f"[Seeds: {SEEDS}]")
    print(f"[Targets: y_tail_q15 + y_onset / OOS 2018-2026 / v4a 70 features]")
    print(f"[Pipeline: {len(SEEDS)} seeds × {len(FOLDS)} folds × 2 targets = {len(SEEDS)*len(FOLDS)*2} fold runs + "
          f"{len(SEEDS)*2} final training runs]")
    print("=" * 80)

    grand_t0 = time.time()
    per_seed_results = {}  # key = f"seed{seed}_{target}"
    for s in SEEDS:
        for tc in ["y_tail_q15", "y_onset"]:
            key = f"seed{s}_{tc}"
            per_seed_results[key] = run_seed_walkforward(s, tc)

    # ========================================================================
    # Multi-seed audit: per-seed std + 3-seed mean prediction PR-AUC
    # ========================================================================
    print("\n" + "=" * 80)
    print("[Cycle 53C MULTI-SEED VARIANCE AUDIT]")
    print("=" * 80)

    audit = {"per_target": {}}
    for tc in ["y_tail_q15", "y_onset"]:
        prs = [per_seed_results[f"seed{s}_{tc}"]["oos_pr"] for s in SEEDS]
        ics = [per_seed_results[f"seed{s}_{tc}"]["oos_ic"] for s in SEEDS]
        mean_pr = float(np.mean(prs))
        std_pr = float(np.std(prs, ddof=1)) if len(prs) > 1 else 0.0
        min_pr = float(np.min(prs))
        max_pr = float(np.max(prs))

        # Stability verdict (per mandate)
        if std_pr < 0.02:
            stability = "STABLE"
        elif std_pr <= 0.05:
            stability = "MODERATE"
        else:
            stability = "UNSTABLE"

        mean_pred_res = compute_seed_mean_prediction(tc, SEEDS)

        audit["per_target"][tc] = dict(
            seeds=SEEDS,
            per_seed_pr=prs,
            per_seed_ic=ics,
            mean_pr_across_seeds=round(mean_pr, 4),
            std_pr_across_seeds=round(std_pr, 4),
            min_pr=round(min_pr, 4),
            max_pr=round(max_pr, 4),
            range_pr=round(max_pr - min_pr, 4),
            stability_verdict=stability,
            mean_prediction_pr=mean_pred_res["oos_pr_mean_prediction"] if mean_pred_res else None,
            mean_prediction_ic=mean_pred_res["oos_ic_mean_prediction"] if mean_pred_res else None,
            per_date_std_mean=mean_pred_res["per_date_std_mean"] if mean_pred_res else None,
            per_date_std_median=mean_pred_res["per_date_std_median"] if mean_pred_res else None,
        )

        print(f"\n[{tc}]")
        print(f"  per-seed PR-AUC: {prs}")
        print(f"  mean={mean_pr:.4f}  std={std_pr:.4f}  range={max_pr - min_pr:.4f}")
        print(f"  stability: {stability}")
        if mean_pred_res:
            print(f"  3-seed mean prediction PR-AUC: {mean_pred_res['oos_pr_mean_prediction']:.4f}")
            print(f"  per-date prediction std mean={mean_pred_res['per_date_std_mean']:.4f} "
                  f"median={mean_pred_res['per_date_std_median']:.4f}")

    # Dump per_fold_diagnostics.json
    per_fold_diag = {
        "cycle": "53C_patchtst_stacked_multiseed",
        "stacked_config": STACKED_CONFIG,
        "seeds": SEEDS,
        "targets": ["y_tail_q15", "y_onset"],
        "panel": "feature_panel_v4a_combined.parquet",
        "n_features": 70,
        "forward_labels": True,
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "fixed_training": dict(
            batch_size=BATCH_SIZE, max_epochs=MAX_EPOCHS,
            early_stop_patience=EARLY_STOP_PATIENCE,
            warmup_steps=WARMUP_STEPS, weight_decay=PT_WEIGHT_DECAY, lr=PT_LR,
            grad_clip_norm=GRAD_CLIP_NORM,
            mixed_precision_amp=USE_AMP,
            gpu_mem_fraction=0.30,
        ),
        "per_seed_per_target_results": per_seed_results,
        "elapsed_grand_total_sec": round(time.time() - grand_t0, 1),
    }
    diag_path = OUT / "per_fold_diagnostics.json"
    with diag_path.open("w") as f:
        json.dump(per_fold_diag, f, indent=2, default=str)
    print(f"\n[Per-fold diagnostics] Saved: {diag_path}")

    audit_path = OUT / "multiseed_variance_audit.json"
    with audit_path.open("w") as f:
        json.dump(audit, f, indent=2, default=str)
    print(f"[Multi-seed audit] Saved: {audit_path}")

    print("\n" + "=" * 80)
    print("[Cycle 53C STACKED MULTI-SEED DONE — Run scripts/128_stacked_multiseed_aggregate.R next]")
    print("=" * 80)
