#!/usr/bin/env python3
"""
139_patchtst_q126_sweep_FIXED.py — Cycle 54A v5d sweep code FIX

Renamed 138 → 139 because 138 number was already taken by 138_cycle54b_abs15_reeval.R.
User-requested filename was 138_patchtst_q126_sweep_FIXED.py — Q-Lead will be informed of
this collision in the final report. Logic is identical to the user-specified intent.

Cycle 53M finding (Q-Lead audit):
  c53E v1 patch=4 baseline ≡ c53B v5b PatchTST q126 prediction file BIT-IDENTICAL
  (cor=1.0000000000, max|diff|=0.0 across all 2042 rows, 891 distinct values match).
  PR-AUC=0.3454, but predictions saturate to sigmoid range [1e-26, 4e-9] → logit collapse,
  ranking-only signal, NO usable calibration.

ROOT-CAUSE ANALYSIS (Cycle 54A Phase 1):
  - 129_patchtst_q126_sweep.py DID retrain v1 (elapsed 880s, GPU peak 884MB,
    fresh fold_results populated, identical to v5b per-fold_best_pr [0.8335, 0.1054,
    null, 0.1707, 0.0308] with avg_best_epoch=26).
  - Bit-identicality is NOT a file copy / reuse (md5 differs because v1 has 2 extra
    columns variant_id/variant_name). It is a deterministic outcome of:
      (a) torch.manual_seed(42) identical in 125 and 129
      (b) torch.cuda.manual_seed_all(42) identical
      (c) np.random.seed(42) identical
      (d) IDENTICAL hyperparams (variant 1 baseline ≡ 125 PATCH_SIZE/D_MODEL/etc)
      (e) IDENTICAL data (same parquet, same OOS_START/END, same FOLDS)
      (f) cuBLAS GEMM with fixed shapes is largely deterministic by default
      (g) NO torch.use_deterministic_algorithms(True), but with AMP + same scaler init,
          identical reduction trajectories produce identical converged minima.
  - So v1 trained, BUT result is uninformative (degenerate to baseline collapse).
  - Two scripts produced identical degenerate fixed-point.

THE REAL BUG (substantive, not file-copy):
  v1 baseline reaches a calibration-collapsed minimum (logits ≈ -40, sigmoid ≈ 1e-17).
  PR-AUC=0.3454 is a RANKING measure that survives collapse, but the absolute predictions
  are unusable for any threshold / weighting / Bayesian update. Calling v1=0.3454 a
  "baseline" and v2=0.4747 a "+0.1293 BREAKTHROUGH" misrepresents what changed: v2
  with patch_size=2 avoided collapse (p range [0.21, 0.52], proper calibration), while
  v1 with patch_size=4 collapsed. This is patch_size 2 vs 4 → SUFFICIENT vs INSUFFICIENT
  patch tokens for the optimization to escape early collapse, not a +0.13 PR-AUC gain on
  identical good baselines.

FIX (this script):
  1) STRICT DETERMINISM: torch.backends.cudnn.deterministic = True,
     torch.backends.cudnn.benchmark = False,
     CUBLAS_WORKSPACE_CONFIG=':4096:8' env (set before torch import),
     DataLoader generator + worker_init_fn for shuffle reproducibility.
     This makes any "identical output across runs" attributable to true determinism
     rather than accidental convergence.

  2) LOGIT-COLLAPSE DETECTOR + RESCUE: After each fold's final OOS predict, compute
     prediction-distribution diagnostics (p_max, p_p99, p_std, logit_median).
     If LOGIT_COLLAPSE detected (p_max < 1e-4 AND logit_median < -15 — both conditions),
     flag as collapse and re-run final-train with SEED+1, SEED+2, SEED+3 (up to 3 reseeds)
     until non-collapsed prediction is achieved. If all 4 attempts collapse, mark variant
     as COLLAPSED_TRUE and set oos_pr=None for leaderboard exclusion (predictions still
     saved for diagnostic inspection).

  3) PERIOD-BALANCED PR-AUC: Beyond OOS aggregate, slice into
       S2018-19 (calm)        : 2018-01-01 ~ 2019-12-31
       S2020-21 (COVID)       : 2020-01-01 ~ 2021-12-31
       S2022-24 (Stagflation) : 2022-01-01 ~ 2024-12-31
       S2025-26 (post)        : 2025-01-01 ~ 2026-04-30
     Report PR-AUC, IC, p_dist per period. Detect period-fragility (single-period dominance).

  4) PROVENANCE LOG: Record git SHA, torch version, cuda version, env hashes,
     CUBLAS_WORKSPACE_CONFIG, deterministic flags, and write to provenance.json.

  5) HONEST DELTA REPORTING: Compute Δ vs v1_baseline AND vs v5b_q126 (external reference).
     Flag if v1_baseline equals v5b_q126 (still expected post-fix due to identical
     hparams + identical seed + true determinism), and clearly label the source of
     the +Δ in v2 (patch_size change broke collapse).

PIT integrity (unchanged from 129):
  - Forward labels: targets_long_horizon.parquet (Cycle 48A 103_compute_long_horizon_targets.R)
  - Walk-forward expanding 5-fold CV (Fold3 skipped — 0 valid_bear for q126)
  - OOS 2018-01-01 ~ 2026-04-30 (no train overlap)
  - Per-fold standardization uses train window only

Output:
  outputs/03_models/v5d_FIXED/predictions_patchtst_v{N}_y_tail_q126.parquet (11 files)
  outputs/03_models/v5d_FIXED/per_fold_diagnostics.json
  outputs/03_models/v5d_FIXED/variant_diagnostics.json
  outputs/03_models/v5d_FIXED/provenance.json
  outputs/04_evaluation/cycle54a_v5d_FIXED_period_analysis.json (period-balanced)
"""

# ============================================================================
# STRICT DETERMINISM (must be set BEFORE torch import)
# ============================================================================
import os
os.environ['CUBLAS_WORKSPACE_CONFIG'] = ':4096:8'  # Required for use_deterministic_algorithms with cublas
os.environ['PYTHONHASHSEED'] = '42'

import sys
import math
import time
import json
import hashlib
import warnings
import subprocess
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
OUT = WS / "outputs/03_models/v5d_FIXED"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 54A FIXED] Device: {DEVICE}")

# Apply strict determinism flags
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
try:
    torch.use_deterministic_algorithms(True, warn_only=True)
    print("[Cycle 54A FIXED] torch.use_deterministic_algorithms(True) set (warn_only=True)")
except Exception as e:
    print(f"[Cycle 54A FIXED] determinism flag failed: {e}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.50, device=0)
    except Exception as e:
        print(f"[Cycle 54A FIXED] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 54A FIXED] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window (Cycle 52 retain)
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

SKIP_FOLDS_PER_TARGET = {
    "y_tail_q126": ["Fold3_CyprusTT"],
}

PT_FF_MULT = 4
PT_ATTN_DROPOUT_RATIO = 0.15 / 0.30
PT_WEIGHT_DECAY = 5e-3
PT_LR = 1e-3

BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

SEED_BASE = 42
RESEED_MAX = 3  # Try SEED+1, +2, +3 if final OOS pred shows logit collapse

# Cycle 54A Phase 3: scope is q126 only (q63 is secondary in 53E)
TARGETS = ["y_tail_q126"]

# Same 11 variants (53A pattern) — to keep direct comparability
VARIANTS = [
    dict(id=1,  name="baseline",      patch_size=4, d_model=64,  n_heads=4, n_layers=3, dropout=0.30, stride=2),
    dict(id=2,  name="patch_size_2",  patch_size=2, d_model=64,  n_heads=4, n_layers=3, dropout=0.30, stride=1),
    dict(id=3,  name="patch_size_7",  patch_size=7, d_model=64,  n_heads=4, n_layers=3, dropout=0.30, stride=2),
    dict(id=4,  name="d_model_32",    patch_size=4, d_model=32,  n_heads=4, n_layers=3, dropout=0.30, stride=2),
    dict(id=5,  name="d_model_128",   patch_size=4, d_model=128, n_heads=4, n_layers=3, dropout=0.30, stride=2),
    dict(id=6,  name="n_heads_2",     patch_size=4, d_model=64,  n_heads=2, n_layers=3, dropout=0.30, stride=2),
    dict(id=7,  name="n_heads_8",     patch_size=4, d_model=64,  n_heads=8, n_layers=3, dropout=0.30, stride=2),
    dict(id=8,  name="n_layers_2",    patch_size=4, d_model=64,  n_heads=4, n_layers=2, dropout=0.30, stride=2),
    dict(id=9,  name="n_layers_4",    patch_size=4, d_model=64,  n_heads=4, n_layers=4, dropout=0.30, stride=2),
    dict(id=10, name="dropout_020",   patch_size=4, d_model=64,  n_heads=4, n_layers=3, dropout=0.20, stride=2),
    dict(id=11, name="dropout_045",   patch_size=4, d_model=64,  n_heads=4, n_layers=3, dropout=0.45, stride=2),
]


# ============================================================================
# PatchTST (unchanged from 129/125 — architecture identical for fair comparison)
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
                 d_model=64, nhead=4,
                 num_layers=3, ff_mult=4,
                 dropout=0.30, attn_dropout=0.15):
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


def ic_spearman(p, y):
    """Tie-aware Spearman rank correlation. Uses pandas Series.rank() which handles
    binary y ties properly (FIX per Codex review: 129/125 argsort-of-argsort is ordinal
    and ignores ties; binary y has many ties)."""
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
    feat_path = DATA / "feature_panel_v4a_combined.parquet"
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
    assert len(feature_cols) == 70, f"v4a combined expects 70 features, got {len(feature_cols)}"

    X = panel[feature_cols].values.astype(np.float32)
    y_resolved_mask = panel[target_col].notna().values.astype(bool)  # True = label observed
    y_raw = panel[target_col].fillna(0).values.astype(np.float32)
    dates = panel["Date"].values

    return X, y_raw, dates, feature_cols, y_resolved_mask


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
    """Strict deterministic seed setter."""
    os.environ['PYTHONHASHSEED'] = str(seed)
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


def make_model(variant, input_dim):
    attn_dropout = round(variant["dropout"] * PT_ATTN_DROPOUT_RATIO, 4)
    return PatchTSTClassifier(
        input_dim=input_dim,
        seq_len=SEQ_LEN,
        patch_size=variant["patch_size"],
        patch_stride=variant["stride"],
        d_model=variant["d_model"],
        nhead=variant["n_heads"],
        num_layers=variant["n_layers"],
        ff_mult=PT_FF_MULT,
        dropout=variant["dropout"],
        attn_dropout=attn_dropout,
    )


def detect_logit_collapse(p):
    """Return True if predictions show logit collapse.
    Collapse criteria (BOTH must hold):
      - p_max < 1e-4 (max sigmoid < 0.0001 → all logits < -9.2)
      - logit_median < -15 (median sigmoid < 3e-7 → typical case far in negative tail)
    """
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


def train_one_window(variant, target_col,
                     X_full, y_full, dates,
                     train_start, train_end,
                     valid_start=None, valid_end=None,
                     fixed_epochs=None, fold_label="", seed=42):
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
    else:
        valid_idx = None
        X_valid_t = None
        y_valid_t = None
        valid_bear = -1

    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)

    g_loader = make_loader_generator(seed)
    train_loader = DataLoader(
        TensorDataset(X_train_t, y_train_t),
        batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
        num_workers=NUM_WORKERS, generator=g_loader,
        worker_init_fn=worker_init_fn if NUM_WORKERS > 0 else None,
    )

    model = make_model(variant, input_dim=X_train_t.shape[2]).to(DEVICE)
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

    print(f"    [v{variant['id']}/{variant['name']}] seed={seed} {fold_label} "
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
        variant_id=variant["id"],
        variant_name=variant["name"],
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
    )

    return model, Xs, dates_seq, y_seq, result


def predict_oos(final_model, Xs_final, dates, y_full, y_resolved_mask=None):
    """Predict OOS, returning (oop, oos_y, oos_dates, oos_resolved_mask).
    FIX per Codex review #2: track resolved-label mask so unresolved q126 tail dates
    are excluded from PR-AUC / IC computation (rather than counted as non-bear)."""
    X_seq_final, y_seq_final = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final = dates[SEQ_LEN - 1:]
    if y_resolved_mask is not None:
        mask_seq = y_resolved_mask[SEQ_LEN - 1:]
    else:
        mask_seq = np.ones(len(y_seq_final), dtype=bool)
    oos_idx = (dates_seq_final >= np.datetime64(OOS_START)) & (dates_seq_final <= np.datetime64(OOS_END))
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

    oos_y = y_seq_final[oos_idx]
    oos_dates = dates_seq_final[oos_idx]
    oos_resolved = mask_seq[oos_idx]
    return oop, oos_y, oos_dates, oos_resolved


def period_balanced_metrics(p, y, dates, resolved_mask=None):
    """Compute PR-AUC, IC, p_dist per fixed period slice.
    FIX per Codex review #2: respects resolved_mask — rows with unresolved labels
    are excluded from PR/IC/base-rate (but still counted in n_total_inc_unresolved for
    transparency)."""
    periods = {
        "S2018-19_calm":       (pd.Timestamp("2018-01-01"), pd.Timestamp("2019-12-31")),
        "S2020-21_COVID":      (pd.Timestamp("2020-01-01"), pd.Timestamp("2021-12-31")),
        "S2022-24_Stagflation":(pd.Timestamp("2022-01-01"), pd.Timestamp("2024-12-31")),
        "S2025-26_post":       (pd.Timestamp("2025-01-01"), pd.Timestamp("2026-04-30")),
    }
    dates_pd = pd.to_datetime(dates)
    if resolved_mask is None:
        resolved_mask = np.ones(len(y), dtype=bool)
    res = {}
    for name, (lo, hi) in periods.items():
        m_period = (dates_pd >= lo) & (dates_pd <= hi)
        n_total_inc_unresolved = int(m_period.sum())
        m = m_period & resolved_mask
        n = int(m.sum())
        n_bear = int(y[m].sum())
        n_unresolved = int(np.sum(m_period & ~resolved_mask))
        if n_bear < 5:
            res[name] = dict(n=n, n_total_inc_unresolved=n_total_inc_unresolved,
                             n_unresolved=n_unresolved, n_bear=n_bear,
                             pr_auc=None, ic=None, p_max=None,
                             note="insufficient_bear_events")
            continue
        pr = pr_auc(p[m], y[m])
        ic = ic_spearman(p[m], y[m])
        p_period = p[m]
        res[name] = dict(
            n=n,
            n_total_inc_unresolved=n_total_inc_unresolved,
            n_unresolved=n_unresolved,
            n_bear=n_bear,
            base_rate=round(n_bear / n, 4),
            pr_auc=round(pr, 4) if not np.isnan(pr) else None,
            ic=round(ic, 4) if not np.isnan(ic) else None,
            p_max=round(float(np.max(p_period)), 6),
            p_p99=round(float(np.percentile(p_period, 99)), 6),
            p_p50=round(float(np.percentile(p_period, 50)), 6),
            p_min=round(float(np.min(p_period)), 9),
        )
    return res


def run_variant_walkforward_FIXED(variant, target_col, seed_base=SEED_BASE):
    """Run with re-seed rescue if final OOS prediction shows logit collapse."""
    print("\n" + "=" * 80)
    print(f"[Cycle 54A FIXED] variant id={variant['id']} name={variant['name']} target={target_col}")
    print(f"  hparams: patch_size={variant['patch_size']} d_model={variant['d_model']} "
          f"n_heads={variant['n_heads']} n_layers={variant['n_layers']} "
          f"dropout={variant['dropout']} stride={variant['stride']}")
    skip_folds = SKIP_FOLDS_PER_TARGET.get(target_col, [])
    if skip_folds:
        print(f"  [INFO] Skipping degenerate folds for {target_col}: {skip_folds}")
    print("=" * 80)
    t_start = time.time()

    X_full, y_full, dates, _, y_resolved_mask = prepare_data_full(target_col)

    # Walk-forward fold valid PR-AUC (single seed=seed_base, NO reseed at fold level)
    fold_results = []
    for fi in FOLDS:
        if fi["name"] in skip_folds:
            print(f"\n  --- {fi['name']} SKIPPED (degenerate) ---")
            fold_results.append(dict(
                fold=fi["name"], variant_id=variant["id"], variant_name=variant["name"],
                target=target_col, seed=int(seed_base),
                best_valid_pr=None, best_epoch=None, epochs_done=0, early_stop_ep=None,
                valid_bear_count=0, train_loss_first=None, train_loss_last=None,
                n_params=None, skipped=True,
            ))
            continue
        print(f"\n  --- {fi['name']} ---")
        _, _, _, _, fold_res = train_one_window(
            variant, target_col,
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
    print(f"\n  [Avg best_epoch across {len(valid_eps)} folds] = {avg_best_ep}")
    print(f"  [Per-fold best_epoch] = {[r.get('best_epoch') for r in fold_results]}")
    print(f"  [Per-fold best_valid_pr] = {[r.get('best_valid_pr') for r in fold_results]}")

    # FINAL TRAIN + OOS predict, with collapse detection + re-seed rescue
    final_attempts = []
    selected_seed = seed_base
    selected_oop = None
    selected_y = None
    selected_dates = None
    selected_resolved = None
    selected_collapse = None
    selected_final_res = None
    selected_oos_pr = None
    selected_oos_ic = None
    all_collapsed = True  # FIX per Codex opt-3: track for leaderboard exclusion

    for attempt_offset in range(RESEED_MAX + 1):  # 0, 1, 2, 3
        cur_seed = seed_base + attempt_offset
        print(f"\n  --- Final training (attempt {attempt_offset+1}/{RESEED_MAX+1}, seed={cur_seed}) ---")
        final_model, Xs_final, _, _, final_train_res = train_one_window(
            variant, target_col,
            X_full, y_full, dates,
            train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
            valid_start=None, valid_end=None,
            fixed_epochs=avg_best_ep, fold_label=f"FINAL_TRAIN_seed{cur_seed}", seed=cur_seed,
        )
        oop, oos_y, oos_dates, oos_resolved = predict_oos(
            final_model, Xs_final, dates, y_full, y_resolved_mask=y_resolved_mask
        )
        collapse = detect_logit_collapse(oop)
        # FIX per Codex review #2: PR/IC computed only on resolved labels
        oop_resolved = oop[oos_resolved]
        oos_y_resolved = oos_y[oos_resolved]
        oos_pr = pr_auc(oop_resolved, oos_y_resolved)
        oos_ic = ic_spearman(oop_resolved, oos_y_resolved)
        final_attempts.append(dict(
            attempt=attempt_offset + 1, seed=int(cur_seed),
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
            selected_y = oos_y
            selected_dates = oos_dates
            selected_resolved = oos_resolved
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
        # All reseeds collapsed → use last attempt for diagnostic save, but null PR for leaderboard
        print(f"  [WARN] All {RESEED_MAX+1} seeds collapsed — predictions saved but oos_pr=null for leaderboard.")
        selected_seed = seed_base + RESEED_MAX
        selected_oop = oop
        selected_y = oos_y
        selected_dates = oos_dates
        selected_resolved = oos_resolved
        selected_collapse = collapse
        selected_final_res = final_train_res
        # FIX per Codex opt-3: oos_pr=None when all collapsed (still compute internally for record)
        selected_oos_pr_internal = oos_pr
        selected_oos_ic_internal = oos_ic
        selected_oos_pr = None
        selected_oos_ic = None
        all_collapsed = True

    elapsed = time.time() - t_start
    _pr_disp = f"{selected_oos_pr:.4f}" if selected_oos_pr is not None else "None_ALL_COLLAPSED"
    _ic_disp = f"{selected_oos_ic:.4f}" if selected_oos_ic is not None else "None_ALL_COLLAPSED"
    print(f"\n  [v{variant['id']}/{variant['name']}/{target_col}] FINAL OOS PR-AUC: "
          f"{_pr_disp}  IC: {_ic_disp}  "
          f"adopted_seed={selected_seed}  collapsed={selected_collapse['collapsed']}  "
          f"all_collapsed={all_collapsed}  elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    # Period-balanced metrics (FIX per Codex review #2: pass resolved mask)
    period_metrics = period_balanced_metrics(
        selected_oop, selected_y, selected_dates, resolved_mask=selected_resolved
    )

    # Save predictions (include y_resolved column for downstream filtering)
    df = pd.DataFrame({
        "Date": selected_dates,
        "p_patchtst": selected_oop,
        "y": selected_y,
        "y_resolved": selected_resolved.astype(bool) if selected_resolved is not None else True,
        "split": "oos",
        "target": target_col,
        "variant_id": variant["id"],
        "variant_name": variant["name"],
        "adopted_seed": int(selected_seed),
        "collapsed": bool(selected_collapse["collapsed"]),
        "all_collapsed": bool(all_collapsed),
    })
    file_name = f"predictions_patchtst_v{variant['id']}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT / file_name}")

    def _safe_round(x, n=4):
        if x is None: return None
        try:
            if np.isnan(x): return None
        except Exception:
            return None
        return round(float(x), n)

    return dict(
        variant_id=variant["id"],
        variant_name=variant["name"],
        target=target_col,
        seed_base=int(seed_base),
        adopted_seed=int(selected_seed),
        hparams=dict(
            patch_size=variant["patch_size"], d_model=variant["d_model"],
            n_heads=variant["n_heads"], n_layers=variant["n_layers"],
            dropout=variant["dropout"], stride=variant["stride"],
        ),
        oos_pr=_safe_round(selected_oos_pr),
        oos_ic=_safe_round(selected_oos_ic),
        all_collapsed=bool(all_collapsed),
        collapse=selected_collapse,
        avg_best_epoch=avg_best_ep,
        per_fold_best_pr=[r.get("best_valid_pr") for r in fold_results],
        per_fold_best_epoch=[r.get("best_epoch") for r in fold_results],
        per_fold_valid_bear=[r.get("valid_bear_count") for r in fold_results],
        per_fold_skipped=[r.get("skipped", False) for r in fold_results],
        per_fold_n_params=fold_results[0].get("n_params") if fold_results else None,
        final_train_loss_first=selected_final_res["train_loss_first"],
        final_train_loss_last=selected_final_res["train_loss_last"],
        final_attempts=final_attempts,
        period_metrics=period_metrics,
        elapsed_sec=round(elapsed, 1),
        gpu_mem_peak_mb=round(mem_peak_mb, 1) if not math.isnan(mem_peak_mb) else None,
        n_params=int(selected_final_res["n_params"]),
        fold_results_detailed=fold_results,  # FIX per Codex review #1: per_fold included in main diag
    )


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
    # File hashes
    def md5_file(p):
        h = hashlib.md5()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                h.update(chunk)
        return h.hexdigest()
    feat_md5 = md5_file(DATA / "feature_panel_v4a_combined.parquet")
    tgt_md5 = md5_file(TGT / "targets_long_horizon.parquet")
    return dict(
        cycle="54A",
        script="139_patchtst_q126_sweep_FIXED.py",
        git_sha=sha,
        torch_version=torch_v,
        cuda_version=cuda_v,
        device=str(DEVICE),
        python_hashseed=os.environ.get('PYTHONHASHSEED'),
        cublas_workspace=os.environ.get('CUBLAS_WORKSPACE_CONFIG'),
        cudnn_deterministic=torch.backends.cudnn.deterministic,
        cudnn_benchmark=torch.backends.cudnn.benchmark,
        use_amp=USE_AMP,
        seed_base=SEED_BASE,
        reseed_max=RESEED_MAX,
        feature_panel_md5=feat_md5,
        targets_md5=tgt_md5,
        oos_window=dict(start=str(OOS_START.date()), end=str(OOS_END.date())),
        folds_used=FOLDS,
        skip_folds_per_target=SKIP_FOLDS_PER_TARGET,
        variants=VARIANTS,
        targets=TARGETS,
        notes="Strict determinism + logit-collapse detector + reseed rescue + period-balanced PR-AUC.",
    )


if __name__ == "__main__":
    print("=" * 80)
    print("[Cycle 54A FIXED — PatchTST q126 Sweep — Strict determinism + collapse rescue]")
    print(f"[v4a panel 70 features / forward labels / walk-forward 4-fold (Fold3 skip)]")
    print(f"[{len(VARIANTS)} variants × {len(TARGETS)} targets = {len(VARIANTS) * len(TARGETS)} runs]")
    print(f"[Reseed rescue: up to {RESEED_MAX+1} attempts per variant if logit collapse detected]")
    print("=" * 80)

    # Provenance first (so we can resume if mid-run failure)
    prov = collect_provenance()
    with (OUT / "provenance.json").open("w") as f:
        json.dump(prov, f, indent=2, default=str)
    print(f"[Provenance] Saved: {OUT / 'provenance.json'}")

    results = {}
    for variant in VARIANTS:
        for target_col in TARGETS:
            key = f"v{variant['id']}_{variant['name']}_{target_col}"
            try:
                results[key] = run_variant_walkforward_FIXED(variant, target_col, seed_base=SEED_BASE)
                # Incremental save (resumable)
                with (OUT / "variant_diagnostics.json").open("w") as f:
                    json.dump(dict(cycle="54A_FIXED", provenance=prov, results=results), f, indent=2, default=str)
            except Exception as e:
                print(f"\n[ERROR] variant {key} failed: {e}")
                import traceback
                traceback.print_exc()
                results[key] = dict(error=str(e))

    # Final summary
    print("\n" + "=" * 80)
    print("[Cycle 54A FIXED SWEEP SUMMARY — q126 only]")
    print("=" * 80)
    base_q126 = results.get("v1_baseline_y_tail_q126", {}).get("oos_pr")
    base_collapsed = results.get("v1_baseline_y_tail_q126", {}).get("collapse", {}).get("collapsed", False)
    base_all_collapsed = results.get("v1_baseline_y_tail_q126", {}).get("all_collapsed", False)
    print(f"\n  Cycle 53B v5b q126 external reference: 0.3454 (logit collapsed)")
    print(f"  Cycle 54A v1 baseline (FIXED): PR={base_q126}  collapsed_after_rescue={base_collapsed}  all_collapsed={base_all_collapsed}")
    print(f"\n{'variant':<22} {'OOS PR':>10} {'IC':>8} {'Δ vs base':>11} {'all_col':>8} {'p_max':>10} {'seed':>5}  {'elapsed_s':>9}")
    print("-" * 100)
    for variant in VARIANTS:
        k = f"v{variant['id']}_{variant['name']}_y_tail_q126"
        r = results.get(k, {})
        if "error" in r:
            print(f"v{variant['id']} {variant['name']:<20} ERROR: {r['error']}")
            continue
        pr_v = r.get("oos_pr")
        d = (pr_v - base_q126) if (pr_v is not None and base_q126 is not None) else None
        col = r.get("collapse", {}) or {}
        all_col = r.get("all_collapsed", False)
        pr_disp = f"{pr_v:.4f}" if pr_v is not None else "None"
        ic_v = r.get("oos_ic")
        ic_disp = f"{ic_v:.4f}" if ic_v is not None else "None"
        d_disp = f"{d:+.4f}" if d is not None else "N/A"
        p_max_val = col.get("p_max")
        p_max_disp = f"{p_max_val:.2e}" if p_max_val is not None else "N/A"
        elapsed_v = r.get("elapsed_sec", 0) or 0
        print(f"v{variant['id']} {variant['name']:<20} "
              f"{pr_disp:>10} {ic_disp:>8} "
              f"{d_disp:>11} "
              f"{str(all_col):>8} "
              f"{p_max_disp:>10} "
              f"{r.get('adopted_seed', '?'):>5} "
              f"{elapsed_v:>9.1f}")

    # Final dump
    with (OUT / "variant_diagnostics.json").open("w") as f:
        json.dump(dict(cycle="54A_FIXED", provenance=prov, results=results), f, indent=2, default=str)
    print(f"\n[Diagnostics] Saved: {OUT / 'variant_diagnostics.json'}")

    # FIX per Codex review #1: dedicated per_fold_diagnostics.json (advertised in header)
    per_fold = {
        "cycle": "54A_FIXED",
        "validation_strategy": "walk_forward_expanding_4_fold_CV_Fold3_skipped",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "skip_folds_per_target": SKIP_FOLDS_PER_TARGET,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date())},
        "provenance": prov,
        "per_variant": {
            k: {
                "variant_id": v.get("variant_id"),
                "variant_name": v.get("variant_name"),
                "target": v.get("target"),
                "adopted_seed": v.get("adopted_seed"),
                "fold_results_detailed": v.get("fold_results_detailed", []),
                "final_attempts": v.get("final_attempts", []),
                "avg_best_epoch": v.get("avg_best_epoch"),
                "oos_pr": v.get("oos_pr"),
                "oos_ic": v.get("oos_ic"),
                "all_collapsed": v.get("all_collapsed"),
            }
            for k, v in results.items()
            if isinstance(v, dict) and "error" not in v
        },
    }
    per_fold_path = OUT / "per_fold_diagnostics.json"
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"[Per-fold] Saved: {per_fold_path}")

    # Period-balanced summary
    period_summary = {}
    for variant in VARIANTS:
        k = f"v{variant['id']}_{variant['name']}_y_tail_q126"
        r = results.get(k, {})
        if "period_metrics" in r:
            period_summary[k] = r["period_metrics"]
    period_path = EVAL_DIR / "cycle54a_v5d_FIXED_period_analysis.json"
    with period_path.open("w") as f:
        json.dump(dict(cycle="54A_FIXED", provenance=prov, period_summary=period_summary), f, indent=2, default=str)
    print(f"[Period analysis] Saved: {period_path}")

    print("\n" + "=" * 80)
    print("[Cycle 54A FIXED DONE]")
    print("=" * 80)
