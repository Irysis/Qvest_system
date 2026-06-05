#!/usr/bin/env python3
"""
155_patchtst_v5e_q126_10seed_strict.py — Cycle 54E 5+5 seeds strict determinism

Purpose:
  Train 5 NEW seeds [2048, 3000, 5000, 7777, 9999] for PatchTST v5e q126
  with strict determinism (54A FIXED pattern) + logit-collapse detector +
  reseed rescue. Combine with existing 5 seeds from Cycle 54C
  [42, 123, 456, 789, 1024] to produce 10-seed mean prediction +
  variance audit (UNSTABLE → MODERATE transition verification).

Architecture (53H + 54C exact mirror):
  - PatchTST channel-independent (patch=4, stride=2, d_model=64, n_heads=4, n_layers=3)
  - dropout=0.30, attn_dropout=0.15
  - AdamW weight_decay=5e-3, lr=1e-3, cosine LR + warmup 500
  - patience 15, max_epochs 80, batch 96, grad_clip 1.0
  - Mixed precision, GPU memory fraction 0.3
  - SEQ_LEN 21, Walk-forward 5-fold CV (Fold3 skip q126 if valid_bear<5)

Strict determinism (54A FIXED inherit):
  - CUBLAS_WORKSPACE_CONFIG=':4096:8' (BEFORE torch import)
  - torch.backends.cudnn.deterministic=True
  - torch.backends.cudnn.benchmark=False
  - torch.use_deterministic_algorithms(True, warn_only=True)
  - DataLoader generator + worker_init_fn (when num_workers>0)
  - PYTHONHASHSEED set per-seed

Collapse detection (54A FIXED inherit):
  - LOGIT_COLLAPSE = (p_max < 1e-4) AND (logit_median < -15)
  - Reseed rescue up to RESEED_MAX=3 attempts per seed
  - If all 4 attempts collapse: oos_pr=None for leaderboard exclusion

Targets:
  - PRIMARY: y_tail_q126 (53H + 54C focus)
  - SECONDARY: y_tail_q15 (consistency with 54C)
  - Training labels from targets_long_horizon.parquet (forward labels with
    NaN tail filled to 0 — observable filtering done in R 156_*)

Outputs:
  outputs/03_models/v5e_q126_10seed/
    predictions_patchtst_v5e_seed{2048|3000|5000|7777|9999}_y_tail_q126.parquet (NEW 5)
    predictions_patchtst_v5e_seed{2048|3000|5000|7777|9999}_y_tail_q15.parquet  (NEW 5)
    predictions_patchtst_v5e_mean10_y_tail_q126.parquet  (10-seed mean: 5+5)
    predictions_patchtst_v5e_mean10_y_tail_q15.parquet
    per_fold_diagnostics.json
    seed_variance_audit.json  (5-seed vs 10-seed std comparison)
    provenance.json

PIT integrity:
  - Forward labels (Cycle 48A pattern)
  - Walk-forward expanding causal split (Cycle 45D)
  - Per-window standardization train-only
  - Strict determinism reproducibility
  - bear_date_audit PASS 4/4 (pre-cycle 2026-05-21 10:06:12 verified)

Reuse strategy:
  - 54C predictions for [42, 123, 456, 789, 1024] are REUSED (no re-training).
    They were trained WITHOUT strict-det flags. We document this drift in
    seed_variance_audit.json. The 5 NEW seeds are trained WITH strict-det,
    so the merged 10-seed mean is a SUPERSET ensemble (not bit-identical
    if 54C had been strict-det too). This is intentional — strict-det of
    historical seeds would require full retrain. Trade-off: 5+5 merge gives
    fair stability comparison while saving 4-5h GPU time on 54C re-runs.
"""

# ============================================================================
# STRICT DETERMINISM (must be set BEFORE torch import)
# ============================================================================
import os
os.environ['CUBLAS_WORKSPACE_CONFIG'] = ':4096:8'
os.environ['PYTHONHASHSEED'] = '42'

import sys
import math
import time
import json
import hashlib
import subprocess
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
OUT = WS / "outputs/03_models/v5e_q126_10seed"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

# Existing 54C multiseed dir (for SOURCE_SEEDS reuse)
SRC_54C = WS / "outputs/03_models/v5e_q126_multiseed"

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 54E] Device: {DEVICE}")

# Strict determinism flags
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
try:
    torch.use_deterministic_algorithms(True, warn_only=True)
    print("[Cycle 54E] torch.use_deterministic_algorithms(True, warn_only=True) set")
except Exception as e:
    print(f"[Cycle 54E] determinism flag failed: {e}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.3, device=0)
        print(f"[Cycle 54E] CUDA memory fraction set to 0.3")
    except Exception as e:
        print(f"[Cycle 54E] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 54E] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window (mirror 53H + 54C exact)
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")

FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# Walk-forward 5-fold CV (mirror 53H + 54C exact)
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

# PatchTST hyperparameters (mirror 53H = 54C exact)
PATCH_SIZE = 4
PATCH_STRIDE = 2
PT_D_MODEL = 64
PT_NHEAD = 4
PT_NLAYERS = 3
PT_FF_MULT = 4
PT_DROPOUT = 0.30
PT_ATTN_DROPOUT = 0.15
PT_WEIGHT_DECAY = 5e-3
PT_LR = 1e-3

BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

# Targets to evaluate
TARGETS = ["y_tail_q15", "y_tail_q126"]

# Multi-seed audit: NEW 5 seeds (strict-det), MERGE with SOURCE 54C 5 seeds
NEW_SEEDS = [2048, 3000, 5000, 7777, 9999]
SOURCE_54C_SEEDS = [42, 123, 456, 789, 1024]
ALL_SEEDS_10 = SOURCE_54C_SEEDS + NEW_SEEDS  # ordered: original then new

RESEED_MAX = 3  # try seed+1, +2, +3 if logit collapse detected


# ============================================================================
# PatchTST (mirror 132 = 140 exact)
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
                 patch_size=PATCH_SIZE, patch_stride=PATCH_STRIDE,
                 d_model=PT_D_MODEL, nhead=PT_NHEAD,
                 num_layers=PT_NLAYERS, ff_mult=PT_FF_MULT,
                 dropout=PT_DROPOUT, attn_dropout=PT_ATTN_DROPOUT):
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
# Helpers (mirror 140 + 139 FIXED hybrid)
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
    """Tie-aware Spearman (139 FIXED pattern)."""
    ok = ~(np.isnan(p) | np.isnan(y))
    p = p[ok]; y = y[ok]
    if len(p) < 30:
        return float("nan")
    p_rank = pd.Series(p).rank().values
    y_rank = pd.Series(y).rank().values
    return float(np.corrcoef(p_rank, y_rank)[0, 1])


def make_warmup_cosine_scheduler(optimizer, warmup_steps, total_steps):
    def lr_lambda(step):
        if step < warmup_steps:
            return float(step + 1) / float(max(1, warmup_steps))
        progress = float(step - warmup_steps) / float(max(1, total_steps - warmup_steps))
        progress = min(1.0, progress)
        return 0.1 + 0.9 * 0.5 * (1.0 + math.cos(math.pi * progress))
    return LambdaLR(optimizer, lr_lambda)


def prepare_data_full(target_col):
    """Load v5e feature panel (74 features) + targets_long_horizon (mirror 140)."""
    feat_path = DATA / "feature_panel_v5e_q126_usmacro.parquet"
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
    assert len(feature_cols) == 74, f"v5e expects 74 features, got {len(feature_cols)}"

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


def set_seed_strict(seed):
    """Strict deterministic seed setter (139 FIXED inherit)."""
    import random
    os.environ['PYTHONHASHSEED'] = str(seed)
    random.seed(seed)
    torch.manual_seed(seed)
    np.random.seed(seed)
    if DEVICE.type == "cuda":
        torch.cuda.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)


def make_loader_generator(seed):
    g = torch.Generator()
    g.manual_seed(seed)
    return g


def worker_init_fn(worker_id):
    seed = torch.initial_seed() % 2**32
    np.random.seed(seed)


def detect_logit_collapse(p):
    """Logit-collapse detector (139 FIXED inherit).
    Returns dict with 'collapsed' flag and p/logit diagnostics."""
    p_max = float(np.max(p))
    eps = 1e-30
    p_clipped = np.clip(p, eps, 1.0 - eps)
    logit = np.log(p_clipped / (1.0 - p_clipped))
    logit_median = float(np.median(logit))
    p_std = float(np.std(p))
    collapsed = (p_max < 1e-4) and (logit_median < -15.0)
    return {
        "collapsed": bool(collapsed),
        "p_max": p_max,
        "p_min": float(np.min(p)),
        "p_p99": float(np.percentile(p, 99)),
        "p_p50": float(np.percentile(p, 50)),
        "p_std": p_std,
        "logit_median": logit_median,
        "logit_max": float(np.max(logit)),
        "logit_min": float(np.min(logit)),
    }


def train_one_window(model_class, model_name, target_col,
                     X_full, y_full, dates,
                     train_start, train_end,
                     valid_start=None, valid_end=None,
                     fixed_epochs=None, fold_label="", seed=42):
    """Train a single window. Strict determinism per-seed (139 FIXED pattern)."""
    set_seed_strict(seed)
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
        if valid_bear < 5:
            print(f"    [WARN] {fold_label}/{target_col}/seed{seed} valid_bear={valid_bear} < 5 — skip fold")
            return None, None, None, None, dict(
                fold=fold_label, model=model_name, target=target_col, seed=int(seed),
                best_valid_pr=None, best_epoch=None, epochs_done=0,
                early_stop_ep=None, valid_bear_count=valid_bear,
                train_loss_first=None, train_loss_last=None,
                n_params=0, skipped=True, skip_reason="valid_bear < 5"
            )
    else:
        valid_idx = None
        X_valid_t = None
        y_valid_t = None
        valid_bear = -1

    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)

    # Strict determinism: DataLoader generator + worker_init_fn (when applicable)
    g_loader = make_loader_generator(seed)
    train_loader = DataLoader(
        TensorDataset(X_train_t, y_train_t),
        batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
        num_workers=NUM_WORKERS, generator=g_loader,
        worker_init_fn=worker_init_fn if NUM_WORKERS > 0 else None,
    )

    wd = PT_WEIGHT_DECAY; lr = PT_LR

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

    print(f"    [{model_name}/{target_col}/seed{seed}] {fold_label} train_n={int(train_idx.sum())}"
          f" valid_n={'-' if not has_valid else int(valid_idx.sum())}"
          f" pos_w={pos_w_value:.2f} target_ep={target_epochs}")

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

            if not np.isnan(vpr) and vpr > best_val + EARLY_STOP_MIN_DELTA:
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
        model=model_name,
        target=target_col,
        seed=int(seed),
        best_valid_pr=round(best_val, 4) if has_valid else None,
        best_epoch=int(best_epoch) if best_epoch > 0 else None,
        epochs_done=int(epochs_done),
        early_stop_ep=int(early_stop_ep) if early_stop_ep > 0 else None,
        valid_bear_count=int(valid_bear) if has_valid else None,
        train_loss_first=round(train_loss_traj[0], 4) if train_loss_traj else None,
        train_loss_last=round(train_loss_traj[-1], 4) if train_loss_traj else None,
        n_params=int(n_params),
        skipped=False,
    )

    return model, Xs, dates_seq, y_seq, result


def predict_oos_with_collapse(model, Xs_final, dates, y_full):
    """Predict OOS + return collapse diagnostics + PR-AUC + IC."""
    X_seq_final, y_seq_final = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final = dates[SEQ_LEN - 1:]
    oos_idx = (dates_seq_final >= np.datetime64(OOS_START)) & (dates_seq_final <= np.datetime64(OOS_END))
    X_oos_t = torch.tensor(X_seq_final[oos_idx], dtype=torch.float32).to(DEVICE)

    model.eval()
    with torch.no_grad():
        bs = 512
        oop_list = []
        for i in range(0, X_oos_t.size(0), bs):
            chunk = X_oos_t[i:i + bs]
            if USE_AMP:
                with torch.amp.autocast("cuda"):
                    lo = model(chunk)
            else:
                lo = model(chunk)
            oop_list.append(torch.sigmoid(lo.float()).cpu().numpy())
        oop = np.concatenate(oop_list, axis=0)

    oos_y = y_seq_final[oos_idx]
    oos_dates = dates_seq_final[oos_idx]
    return oop, oos_y, oos_dates


def run_walkforward_single_seed_strict(model_class, model_name, target_col, seed_base,
                                       X_full, y_full, dates):
    """Per-seed walk-forward + strict determinism + collapse rescue.
    Walk-forward folds use seed_base (no reseed). Final train uses collapse rescue."""
    print("\n" + "=" * 70)
    print(f"[Cycle 54E] {model_name} (seed_base={seed_base}) target: {target_col}")
    print("=" * 70)
    t_start = time.time()

    fold_results = []
    for fi in FOLDS:
        print(f"\n  --- {fi['name']} (seed={seed_base}) ---")
        _, _, _, _, fold_res = train_one_window(
            model_class, model_name, target_col,
            X_full, y_full, dates,
            train_start=fi["train_start"], train_end=fi["train_end"],
            valid_start=fi["valid_start"], valid_end=fi["valid_end"],
            fixed_epochs=None, fold_label=fi["name"], seed=seed_base,
        )
        fold_results.append(fold_res)
        if DEVICE.type == "cuda":
            torch.cuda.empty_cache()

    valid_eps = [r["best_epoch"] for r in fold_results
                 if r.get("best_epoch") is not None and r["best_epoch"] > 0]
    avg_best_ep = int(round(np.mean(valid_eps))) if valid_eps else (MAX_EPOCHS // 2)
    print(f"\n  [Avg best_epoch seed_base={seed_base}] = {avg_best_ep}")
    print(f"  [Per-fold best_epoch] = {[r.get('best_epoch') for r in fold_results]}")
    print(f"  [Per-fold best_valid_pr] = {[r.get('best_valid_pr') for r in fold_results]}")

    # Final train + OOS predict + collapse rescue (139 FIXED pattern)
    final_attempts = []
    selected_seed = seed_base
    selected_oop = None
    selected_oos_y = None
    selected_oos_dates = None
    selected_collapse = None
    selected_final_res = None
    selected_oos_pr = None
    selected_oos_ic = None
    all_collapsed = True

    for attempt_offset in range(RESEED_MAX + 1):
        cur_seed = seed_base + attempt_offset
        print(f"\n  --- Final training seed_base={seed_base} attempt {attempt_offset+1}/{RESEED_MAX+1}, "
              f"effective_seed={cur_seed}, epochs={avg_best_ep} ---")
        final_model, Xs_final, _, _, final_train_res = train_one_window(
            model_class, model_name, target_col,
            X_full, y_full, dates,
            train_start=str(FULL_TRAIN_START.date()),
            train_end=str(FULL_TRAIN_END.date()),
            valid_start=None, valid_end=None,
            fixed_epochs=avg_best_ep,
            fold_label=f"FINAL_TRAIN_seed{cur_seed}",
            seed=cur_seed,
        )
        oop, oos_y, oos_dates = predict_oos_with_collapse(final_model, Xs_final, dates, y_full)
        collapse = detect_logit_collapse(oop)
        oos_pr = pr_auc(oop, oos_y.astype(np.float64))
        oos_ic = ic_spearman(oop, oos_y.astype(np.float64))
        final_attempts.append(dict(
            attempt=attempt_offset + 1, effective_seed=int(cur_seed),
            oos_pr=round(float(oos_pr), 4) if not np.isnan(oos_pr) else None,
            oos_ic=round(float(oos_ic), 4) if not np.isnan(oos_ic) else None,
            collapse=collapse,
            train_loss_last=final_train_res["train_loss_last"],
        ))
        print(f"  attempt {attempt_offset+1}: seed={cur_seed} OOS PR={oos_pr:.4f} IC={oos_ic:.4f} "
              f"collapsed={collapse['collapsed']} p_max={collapse['p_max']:.2e} "
              f"logit_med={collapse['logit_median']:.2f}")

        if not collapse["collapsed"]:
            selected_seed = cur_seed
            selected_oop = oop
            selected_oos_y = oos_y
            selected_oos_dates = oos_dates
            selected_collapse = collapse
            selected_final_res = final_train_res
            selected_oos_pr = oos_pr
            selected_oos_ic = oos_ic
            all_collapsed = False
            print(f"  >>> seed={cur_seed} NOT collapsed — adopt.")
            del final_model
            if DEVICE.type == "cuda":
                torch.cuda.empty_cache()
            break
        else:
            print(f"  >>> seed={cur_seed} collapsed — retry.")
            del final_model
            if DEVICE.type == "cuda":
                torch.cuda.empty_cache()

    if selected_oop is None:
        print(f"  [WARN] All {RESEED_MAX+1} attempts collapsed — predictions saved but oos_pr=null for leaderboard.")
        selected_seed = seed_base + RESEED_MAX
        selected_oop = oop
        selected_oos_y = oos_y
        selected_oos_dates = oos_dates
        selected_collapse = collapse
        selected_final_res = final_train_res
        selected_oos_pr = None
        selected_oos_ic = None
        all_collapsed = True

    elapsed = time.time() - t_start
    _pr_disp = f"{selected_oos_pr:.4f}" if selected_oos_pr is not None else "None_ALL_COLLAPSED"
    _ic_disp = f"{selected_oos_ic:.4f}" if selected_oos_ic is not None else "None_ALL_COLLAPSED"
    print(f"\n  [{model_name}/{target_col}/seed_base{seed_base}] FINAL OOS PR-AUC: "
          f"{_pr_disp} IC: {_ic_disp} adopted_seed={selected_seed} "
          f"collapsed={selected_collapse['collapsed']} all_collapsed={all_collapsed} "
          f"elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        print(f"  GPU memory peak: {mem_peak_mb:.1f} MB")
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    # Save per-seed predictions (file naming by seed_base for stability merge)
    col_name = "p_patchtst_v5e"
    file_name = f"predictions_patchtst_v5e_seed{seed_base}_{target_col}.parquet"

    df = pd.DataFrame({
        "Date": selected_oos_dates,
        col_name: selected_oop,
        "y": selected_oos_y,
        "split": "oos",
        "target": target_col,
        "seed": int(seed_base),
        "adopted_seed": int(selected_seed),
        "collapsed": bool(selected_collapse["collapsed"]),
        "all_collapsed": bool(all_collapsed),
        "strict_det": True,
    })
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")

    return dict(
        model=model_name,
        target=target_col,
        seed_base=int(seed_base),
        adopted_seed=int(selected_seed),
        oos_pr=selected_oos_pr,
        oos_ic=selected_oos_ic,
        all_collapsed=bool(all_collapsed),
        collapse=selected_collapse,
        avg_best_epoch=avg_best_ep,
        per_fold=fold_results,
        final_train=selected_final_res,
        final_attempts=final_attempts,
        elapsed_sec=round(elapsed, 1),
        gpu_mem_peak_mb=round(mem_peak_mb, 1) if not math.isnan(mem_peak_mb) else None,
        n_params=int(selected_final_res["n_params"]),
        # for downstream merge
        oos_dates=selected_oos_dates,
        oos_pred=selected_oop,
        oos_y=selected_oos_y,
    )


def load_54c_prediction(seed, target_col):
    """Load 54C predictions for a source seed (non-strict-det).
    Returns dict with same shape as run_walkforward_single_seed_strict output
    (subset: oos_dates, oos_pred, oos_y, oos_pr, oos_ic, seed_base)."""
    p = SRC_54C / f"predictions_patchtst_v5e_seed{seed}_{target_col}.parquet"
    if not p.exists():
        raise FileNotFoundError(f"54C source prediction missing: {p}")
    dt = pd.read_parquet(p)
    dt["Date"] = pd.to_datetime(dt["Date"])
    # Filter to OOS window
    dt = dt[(dt["Date"] >= OOS_START) & (dt["Date"] <= OOS_END)].copy()
    oos_dates = dt["Date"].values
    oop = dt["p_patchtst_v5e"].values
    oos_y = dt["y"].values
    pa = pr_auc(oop, oos_y.astype(np.float64))
    ic = ic_spearman(oop, oos_y.astype(np.float64))
    return dict(
        model="PATCHTST",
        target=target_col,
        seed_base=int(seed),
        adopted_seed=int(seed),
        oos_pr=pa,
        oos_ic=ic,
        all_collapsed=False,
        collapse=None,
        avg_best_epoch=None,
        per_fold=None,
        final_train=None,
        final_attempts=None,
        elapsed_sec=None,
        gpu_mem_peak_mb=None,
        n_params=None,
        oos_dates=oos_dates,
        oos_pred=oop,
        oos_y=oos_y,
        source="54C_reused",
        strict_det=False,
    )


def build_n_seed_mean(per_seed_results, target_col, label):
    """Build N-seed mean prediction + per-date std + audit.
    per_seed_results: dict[seed → result dict] (subset must include oos_dates/oos_pred/oos_y/oos_pr/oos_ic).
    Returns audit dict (and saves merged parquet to OUT/{label}_y_tail_q126.parquet)."""
    seeds = sorted(per_seed_results.keys())
    base = per_seed_results[seeds[0]]
    ref_dates = pd.to_datetime(base["oos_dates"])
    ref_y = base["oos_y"]

    pred_matrix = np.zeros((len(seeds), len(ref_dates)), dtype=np.float64)
    for i, s in enumerate(seeds):
        r = per_seed_results[s]
        rd = pd.to_datetime(r["oos_dates"])
        ry = r["oos_y"]
        # Date alignment check
        if len(rd) != len(ref_dates) or not (rd == ref_dates).all():
            raise RuntimeError(f"date mismatch across seeds at seed={s} target={target_col}")
        if len(ry) != len(ref_y) or not np.array_equal(ry, ref_y):
            raise RuntimeError(f"y mismatch across seeds at seed={s} target={target_col}")
        pred_matrix[i, :] = r["oos_pred"]

    mean_pred = pred_matrix.mean(axis=0)
    per_date_std = pred_matrix.std(axis=0, ddof=0)

    mean_pr = pr_auc(mean_pred, ref_y.astype(np.float64))
    mean_ic = ic_spearman(mean_pred, ref_y.astype(np.float64))

    file_name = f"predictions_patchtst_v5e_{label}_{target_col}.parquet"
    df_mean = pd.DataFrame({
        "Date": ref_dates.values,
        f"p_patchtst_v5e_{label}": mean_pred,
        "p_per_seed_std": per_date_std,
        "y": ref_y,
        "split": "oos",
        "target": target_col,
        "n_seeds": int(len(seeds)),
        "label": label,
    })
    df_mean.to_parquet(OUT / file_name, index=False)
    print(f"  [{label} mean prediction] Saved: {OUT}/{file_name}")

    audit = dict(
        target=target_col,
        label=label,
        n_seeds=int(len(seeds)),
        seeds_used=sorted([int(s) for s in seeds]),
        n_obs=int(len(ref_dates)),
        n_events=int(ref_y.sum()),
        per_seed_pr_auc={int(s): round(per_seed_results[s]["oos_pr"], 6)
                         if per_seed_results[s]["oos_pr"] is not None else None for s in seeds},
        per_seed_ic={int(s): round(per_seed_results[s]["oos_ic"], 6)
                     if per_seed_results[s]["oos_ic"] is not None else None for s in seeds},
        per_seed_pr_mean=round(float(np.nanmean([per_seed_results[s]["oos_pr"]
                                                  if per_seed_results[s]["oos_pr"] is not None else np.nan
                                                  for s in seeds])), 6),
        per_seed_pr_std=round(float(np.nanstd([per_seed_results[s]["oos_pr"]
                                                if per_seed_results[s]["oos_pr"] is not None else np.nan
                                                for s in seeds], ddof=1)), 6),
        per_seed_pr_min=round(float(np.nanmin([per_seed_results[s]["oos_pr"]
                                                if per_seed_results[s]["oos_pr"] is not None else np.nan
                                                for s in seeds])), 6),
        per_seed_pr_max=round(float(np.nanmax([per_seed_results[s]["oos_pr"]
                                                if per_seed_results[s]["oos_pr"] is not None else np.nan
                                                for s in seeds])), 6),
        per_seed_pr_range=round(float(np.nanmax([per_seed_results[s]["oos_pr"]
                                                  if per_seed_results[s]["oos_pr"] is not None else np.nan
                                                  for s in seeds]) -
                                       np.nanmin([per_seed_results[s]["oos_pr"]
                                                  if per_seed_results[s]["oos_pr"] is not None else np.nan
                                                  for s in seeds])), 6),
        mean_prediction_pr_auc=round(float(mean_pr), 6),
        mean_prediction_ic=round(float(mean_ic), 6),
        per_date_std_mean=round(float(per_date_std.mean()), 6),
        per_date_std_median=round(float(np.median(per_date_std)), 6),
        per_date_std_max=round(float(per_date_std.max()), 6),
        per_date_std_min=round(float(per_date_std.min()), 6),
    )
    return audit


def collect_provenance():
    try:
        sha = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=str(PROJECT_ROOT), stderr=subprocess.DEVNULL
        ).decode().strip()
    except Exception:
        sha = "unknown"
    try:
        torch_v = torch.__version__
        cuda_v = torch.version.cuda
    except Exception:
        torch_v, cuda_v = "?", "?"

    def md5_file(p):
        h = hashlib.md5()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                h.update(chunk)
        return h.hexdigest()

    feat_md5 = md5_file(DATA / "feature_panel_v5e_q126_usmacro.parquet")
    tgt_md5 = md5_file(TGT / "targets_long_horizon.parquet")
    tgt_obs_md5 = md5_file(TGT / "targets_long_horizon_observable.parquet") \
        if (TGT / "targets_long_horizon_observable.parquet").exists() else None
    return dict(
        cycle="54E",
        script="155_patchtst_v5e_q126_10seed_strict.py",
        git_sha=sha,
        torch_version=torch_v,
        cuda_version=cuda_v,
        device=str(DEVICE),
        python_hashseed=os.environ.get('PYTHONHASHSEED'),
        cublas_workspace=os.environ.get('CUBLAS_WORKSPACE_CONFIG'),
        cudnn_deterministic=torch.backends.cudnn.deterministic,
        cudnn_benchmark=torch.backends.cudnn.benchmark,
        use_amp=USE_AMP,
        new_seeds=NEW_SEEDS,
        source_54c_seeds=SOURCE_54C_SEEDS,
        all_seeds_10=ALL_SEEDS_10,
        reseed_max=RESEED_MAX,
        feature_panel_md5=feat_md5,
        targets_md5=tgt_md5,
        targets_observable_md5=tgt_obs_md5,
        oos_window=dict(start=str(OOS_START.date()), end=str(OOS_END.date())),
        folds_used=FOLDS,
        targets=TARGETS,
        notes=(
            "Strict determinism for NEW 5 seeds. 54C SOURCE seeds reused as-is "
            "(non-strict-det). 10-seed mean = 5+5 ensemble. Observable mask "
            "applied in R aggregate script (156_*). Logit-collapse detector "
            "+ reseed rescue active for NEW seeds."
        ),
    )


if __name__ == "__main__":
    print("=" * 70)
    print("[Cycle 54E — PatchTST v5e q126 10-seed strict-det merge]")
    print(f"[NEW Seeds (strict-det + collapse rescue): {NEW_SEEDS}]")
    print(f"[SOURCE 54C Seeds (reused, non-strict-det): {SOURCE_54C_SEEDS}]")
    print(f"[Targets: {TARGETS} / Folds: 5 (Fold3 skip if valid_bear<5)]")
    print("=" * 70)

    cycle_start = time.time()

    # Provenance first
    prov = collect_provenance()
    with (OUT / "provenance.json").open("w") as f:
        json.dump(prov, f, indent=2, default=str)
    print(f"[Provenance] Saved: {OUT / 'provenance.json'}")

    # ============================================================
    # Phase 1: Train 5 NEW seeds (strict-det) per target
    # ============================================================
    new_seed_results = {tc: {} for tc in TARGETS}
    data_cache = {}
    for tgt in TARGETS:
        X_full, y_full, dates, feature_cols = prepare_data_full(tgt)
        data_cache[tgt] = (X_full, y_full, dates, feature_cols)
        print(f"\n[Data loaded] target={tgt} X.shape={X_full.shape} "
              f"dates=[{pd.Timestamp(dates[0]).date()}..{pd.Timestamp(dates[-1]).date()}]")

    for seed in NEW_SEEDS:
        for tgt in TARGETS:
            X_full, y_full, dates, _ = data_cache[tgt]
            r = run_walkforward_single_seed_strict(
                PatchTSTClassifier, "PATCHTST", tgt, seed_base=seed,
                X_full=X_full, y_full=y_full, dates=dates,
            )
            new_seed_results[tgt][seed] = r

    cycle_elapsed = time.time() - cycle_start
    print(f"\n[NEW 5-seed runs DONE] Total elapsed: {cycle_elapsed:.1f}s ({cycle_elapsed/60:.1f} min)")

    # ============================================================
    # Phase 2: Load 54C SOURCE 5-seed predictions (reuse)
    # ============================================================
    print("\n" + "=" * 70)
    print("[Phase 2: Loading 54C SOURCE 5-seed predictions]")
    print("=" * 70)

    source_seed_results = {tc: {} for tc in TARGETS}
    for seed in SOURCE_54C_SEEDS:
        for tgt in TARGETS:
            r = load_54c_prediction(seed, tgt)
            source_seed_results[tgt][seed] = r
            print(f"  [54C reused] seed={seed} target={tgt} oos_pr={r['oos_pr']:.4f} oos_ic={r['oos_ic']:.4f}")

    # ============================================================
    # Phase 3: Build mean predictions — 5-seed (NEW), 5-seed (SOURCE), 10-seed (merged)
    # ============================================================
    print("\n" + "=" * 70)
    print("[Phase 3: Build mean predictions]")
    print("=" * 70)

    audit_per_target = {}
    for tgt in TARGETS:
        print(f"\n  --- {tgt} ---")
        # 5-seed mean (NEW only, strict-det)
        au_new = build_n_seed_mean(new_seed_results[tgt], tgt, "mean5_new")
        # 5-seed mean (SOURCE, non-strict-det; cross-check vs 54C result)
        au_src = build_n_seed_mean(source_seed_results[tgt], tgt, "mean5_source")
        # 10-seed mean (MERGED)
        merged = dict(new_seed_results[tgt])
        merged.update(source_seed_results[tgt])
        au_merge = build_n_seed_mean(merged, tgt, "mean10")

        audit_per_target[tgt] = dict(
            mean5_new=au_new,
            mean5_source=au_src,
            mean10=au_merge,
        )

    # ============================================================
    # Phase 4: Variance audit summary
    # ============================================================
    print("\n" + "=" * 70)
    print("[Phase 4: 5-seed vs 10-seed variance comparison]")
    print("=" * 70)

    variance_audit = dict(
        cycle="54E_patchtst_v5e_q126_10seed_strict",
        audit_type="5_new_strict_det_plus_5_54c_reused_to_10_seed_merge",
        purpose=(
            "Verify 54C UNSTABLE std=0.0787 (5-seed) → expected MODERATE/STABLE "
            "transition at 10-seed. Strict-det for NEW 5 + reseed rescue."
        ),
        panel="feature_panel_v5e_q126_usmacro.parquet",
        targets_source="targets_long_horizon.parquet",
        targets_observable_path="targets_long_horizon_observable.parquet (applied in R script)",
        n_features=74,
        new_seeds=NEW_SEEDS,
        source_54c_seeds=SOURCE_54C_SEEDS,
        all_seeds_10=ALL_SEEDS_10,
        n_seeds_new=len(NEW_SEEDS),
        n_seeds_source=len(SOURCE_54C_SEEDS),
        n_seeds_merged=len(ALL_SEEDS_10),
        targets=TARGETS,
        validation_strategy="walk_forward_expanding_5_fold_CV",
        architecture_mirror="Cycle 53H + 54C (exact PatchTST hparams)",
        strict_determinism=dict(
            applied_to="NEW 5 seeds only",
            source_54c_drift_note="SOURCE 5 seeds reused as-is (non-strict-det)",
            cublas_workspace=os.environ.get('CUBLAS_WORKSPACE_CONFIG'),
            cudnn_deterministic=torch.backends.cudnn.deterministic,
            cudnn_benchmark=torch.backends.cudnn.benchmark,
            use_deterministic_algorithms=True,
            warn_only=True,
        ),
        collapse_rescue=dict(
            applied_to="NEW 5 seeds only",
            reseed_max=RESEED_MAX,
            criteria="p_max<1e-4 AND logit_median<-15 (139 FIXED inherit)",
        ),
        patchtst_hparams=dict(
            patch_size=PATCH_SIZE, patch_stride=PATCH_STRIDE,
            d_model=PT_D_MODEL, nhead=PT_NHEAD, n_layers=PT_NLAYERS,
            ff_dim=PT_D_MODEL * PT_FF_MULT, dropout=PT_DROPOUT,
            attn_dropout=PT_ATTN_DROPOUT,
            weight_decay=PT_WEIGHT_DECAY, lr=PT_LR,
        ),
        training_common=dict(
            batch_size=BATCH_SIZE, max_epochs=MAX_EPOCHS,
            early_stop_patience=EARLY_STOP_PATIENCE,
            early_stop_min_delta=EARLY_STOP_MIN_DELTA,
            grad_clip_norm=GRAD_CLIP_NORM, warmup_steps=WARMUP_STEPS,
            mixed_precision_amp=USE_AMP,
            gpu_mem_fraction=0.3 if DEVICE.type == "cuda" else None,
        ),
        stability_thresholds=dict(
            STABLE_std_lt=0.02,
            MODERATE_std_max=0.05,
            UNSTABLE_std_gt=0.05,
            note="Mirror Cycle 53C STABILITY_STABLE_STD / STABILITY_MODERATE_STD",
        ),
        cycle_54c_5seed_baseline=dict(
            y_tail_q126=dict(per_seed_pr_std=0.078693, mean_prediction_pr_auc=0.561715),
            y_tail_q15=dict(per_seed_pr_std=0.04159, mean_prediction_pr_auc=0.240609),
        ),
        cycle_53h_seed42_baseline=dict(
            y_tail_q126=0.4012,
            y_tail_q15=0.2082,
        ),
        forward_baseline_v13=0.1450,
        audit_per_target=audit_per_target,
        total_elapsed_sec=round(cycle_elapsed, 1),
    )

    variance_path = OUT / "seed_variance_audit.json"
    with variance_path.open("w") as f:
        json.dump(variance_audit, f, indent=2, default=str)
    print(f"\n[Variance audit] Saved: {variance_path}")

    # ============================================================
    # Per-fold + diagnostics dump
    # ============================================================
    per_fold_path = OUT / "per_fold_diagnostics.json"

    def serialize_seed_result(r):
        return {k: v for k, v in r.items() if k not in ("oos_dates", "oos_pred", "oos_y")}

    per_fold = dict(
        cycle="54E_patchtst_v5e_q126_10seed_strict",
        validation_strategy="walk_forward_expanding_5_fold_CV",
        patience=EARLY_STOP_PATIENCE,
        min_delta=EARLY_STOP_MIN_DELTA,
        max_epochs=MAX_EPOCHS,
        folds=FOLDS,
        oos_window=dict(start=str(OOS_START.date()), end=str(OOS_END.date())),
        feature_panel="feature_panel_v5e_q126_usmacro.parquet (74 features)",
        new_seeds=NEW_SEEDS,
        source_54c_seeds=SOURCE_54C_SEEDS,
        targets=TARGETS,
        new_seed_results={
            tc: {str(s): serialize_seed_result(new_seed_results[tc][s]) for s in NEW_SEEDS}
            for tc in TARGETS
        },
        source_seed_results_summary={
            tc: {str(s): dict(oos_pr=source_seed_results[tc][s]["oos_pr"],
                              oos_ic=source_seed_results[tc][s]["oos_ic"],
                              source="54C_reused", strict_det=False)
                 for s in SOURCE_54C_SEEDS}
            for tc in TARGETS
        },
    )
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"[Per-fold diagnostics] Saved: {per_fold_path}")

    # ============================================================
    # Summary printout
    # ============================================================
    print("\n" + "=" * 70)
    print("[Cycle 54E SUMMARY — 10-seed strict-det merge audit]")
    print("=" * 70)
    for tgt in TARGETS:
        print(f"\n  {tgt}:")
        au = audit_per_target[tgt]
        print(f"    --- 5-seed NEW (strict-det) ---")
        n = au["mean5_new"]
        print(f"      Per-seed PR-AUC: " +
              "  ".join([f"seed{s}={n['per_seed_pr_auc'][s] if n['per_seed_pr_auc'][s] is not None else 'COL'}" for s in sorted(n['per_seed_pr_auc'].keys())]))
        print(f"      Across-seed mean PR-AUC: {n['per_seed_pr_mean']:.4f} std={n['per_seed_pr_std']:.4f}")
        print(f"      5-seed NEW MEAN prediction PR-AUC: {n['mean_prediction_pr_auc']:.4f}  IC={n['mean_prediction_ic']:.4f}")

        print(f"    --- 5-seed SOURCE (reused, non-strict-det) ---")
        s = au["mean5_source"]
        print(f"      Per-seed PR-AUC: " +
              "  ".join([f"seed{ss}={s['per_seed_pr_auc'][ss]:.4f}" for ss in sorted(s['per_seed_pr_auc'].keys())]))
        print(f"      Across-seed mean PR-AUC: {s['per_seed_pr_mean']:.4f} std={s['per_seed_pr_std']:.4f}")
        print(f"      5-seed SOURCE MEAN prediction PR-AUC: {s['mean_prediction_pr_auc']:.4f}  IC={s['mean_prediction_ic']:.4f}")

        print(f"    --- 10-seed MERGED ---")
        m = au["mean10"]
        print(f"      Across-seed mean PR-AUC: {m['per_seed_pr_mean']:.4f} std={m['per_seed_pr_std']:.4f}")
        print(f"      10-seed MEAN prediction PR-AUC: {m['mean_prediction_pr_auc']:.4f}  IC={m['mean_prediction_ic']:.4f}")
        print(f"      Per-date std mean={m['per_date_std_mean']:.4f} median={m['per_date_std_median']:.4f} max={m['per_date_std_max']:.4f}")

    print("\n" + "=" * 70)
    print("[Cycle 54E Python DONE — Run scripts/156_10seed_strict_observable_aggregate.R next]")
    print("=" * 70)
