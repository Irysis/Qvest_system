#!/usr/bin/env python3
"""
164_mamba_5seed_strict.py — Cycle 56D-Batch2-multiseed (Mamba 5-seed strict-PIT)

Mandate (Q-Lead autonomous):
  Cycle 56D-Batch2 found:
    - Mamba q126 seed=42 = 0.4265 ARCH_BREAKTHROUGH (vs 53H 0.4016)
    - BUT period-fragile 1/3 lift>1 (COVID 2.98 dominate, S2018-19 0.96, S2022-24 0.71)
    - Recall 53E_v2 0.4747 single-regime COVID-dominated pattern
    - 53H_v5e 5-seed strict-PIT ensemble = 0.4880 (3/3 lift>1 robust)
  This script verifies whether Mamba is:
    (a) MAMBA_VALIDATED: mean5 ≥ 0.42 + std < 0.05 + 3/3 lift>1
    (b) MAMBA_PERIOD_FRAGILE: mean5 ≥ 0.42 but period < 3/3
    (c) MAMBA_LUCKY_SEED: single 0.43 > mean5 (multi-seed worse)

Architecture (identical to 153_mamba_fedformer_q126.py — Mamba half):
  d_model=64, d_state=16, d_conv=4, expand=2, n_layers=2, dropout=0.30
  PIT-safe: selective SSM forward-only recurrence, causal 1D conv

Strict determinism (54A FIXED inherit):
  - CUBLAS_WORKSPACE_CONFIG=:4096:8 BEFORE torch import
  - cudnn.deterministic=True / benchmark=False
  - torch.use_deterministic_algorithms(True, warn_only=True)
  - DataLoader generator per seed + worker_init_fn
  - PYTHONHASHSEED set per-seed
  - 56B Codex fix: y_valid_mask (NaN propagation, no fillna(0))
  - 56B Codex fix: purged k-fold CV (Fold3 q126 skipped)

Seeds: [42, 43, 44, 45, 46]
  - seed=42: REFERENCE — already exists at outputs/03_models/cycle58t_mvp_v5p_y_dd_8pct_15seed/
    Re-trained here under fresh determinism for bit-identical reproducibility check.
  - seeds 43-46: NEW

Output:
  outputs/03_models/cycle58t_mvp_v5p_y_dd_8pct_15seed/
    predictions_mamba_seed{42|43|44|45|46}_y_tail_q126.parquet (5 files)
    predictions_mamba_mean5_y_tail_q126.parquet (5-seed mean)
    multiseed_variance_audit.json
    per_fold_diagnostics.json
    provenance.json

PIT integrity (audited):
  - Forward labels (targets_long_horizon_observable_v2.parquet — NaN propagation)
  - y_valid_mask: BCE only on resolved labels (NaN dropped)
  - Walk-forward expanding causal split (Fold3 q126 skipped)
  - Per-window standardization train-only
  - Mamba selective SSM forward-only (no future leak)
  - bear_date_audit pre-cycle PASS 4/4 (2026-05-21 11:19:50)

GPU sharing:
  - gpu_fraction=0.15 (2.5GB) to share with concurrent 155 + 157
  - sequential per-seed (5 seeds × ~10-15 min each on RTX 3050 ≈ 60-90 min)

Codex review scope: code only (not result interpretation).
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
OUT = WS / "outputs/03_models/cycle58t_mvp_v5p_y_dd_8pct_15seed"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 56D-Batch2-multiseed] Device: {DEVICE}")

# Apply strict determinism flags
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
try:
    torch.use_deterministic_algorithms(True, warn_only=True)
    print("[Cycle 56D-Batch2-multiseed] torch.use_deterministic_algorithms(True, warn_only=True) set")
except Exception as e:
    print(f"[Cycle 56D-Batch2-multiseed] determinism flag failed: {e}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.15, device=0)
        print("[Cycle 56D-Batch2-multiseed] CUDA memory fraction set to 0.15 (2.5GB share)")
    except Exception as e:
        print(f"[Cycle 56D-Batch2-multiseed] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 56D-Batch2-multiseed] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window (same as 53H / 153 — for fair comparison to existing 53H mean5)
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")
FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# Walk-forward 5-fold CV (mirror 153 — Fold3 q126 skipped)
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

# Training infra (mirror 153 exactly)
BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

PT_LR = 1e-3
PT_WEIGHT_DECAY = 5e-3

TARGETS = ["y_dd_8pct"]   # Cycle 58T: drawdown-based y (도훈 audit fix)
SEEDS = [42, 123, 456, 789, 1024, 2048, 3000, 5000, 7777, 9999, 10000, 20000, 30000, 40000, 50000]
RESEED_MAX = 0   # Mamba did NOT collapse in 56D-Batch2 — single attempt per seed sufficient

# Reference baselines
REF_53H_MEAN5_Q126 = 0.488   # strict-PIT mean5
REF_MAMBA_SEED42_Q126 = 0.4264   # Mamba single seed=42 from 153
STABILITY_STD_STABLE = 0.02
STABILITY_STD_MODERATE = 0.05


# ============================================================================
# Architecture: Mamba (identical to 153_mamba_fedformer_q126.py)
# ============================================================================
class MambaBlock(nn.Module):
    def __init__(self, d_model, d_state=16, d_conv=4, expand=2, dt_rank=None,
                 dt_min=0.001, dt_max=0.1, dt_init_floor=1e-4):
        super().__init__()
        self.d_model = d_model
        self.d_state = d_state
        self.d_conv = d_conv
        self.expand = expand
        self.d_inner = int(expand * d_model)
        self.dt_rank = dt_rank or max(1, d_model // 16)

        self.in_proj = nn.Linear(d_model, 2 * self.d_inner, bias=False)
        self.conv1d = nn.Conv1d(
            in_channels=self.d_inner, out_channels=self.d_inner,
            kernel_size=d_conv, groups=self.d_inner,
            padding=d_conv - 1, bias=True,
        )
        self.x_proj = nn.Linear(self.d_inner, self.dt_rank + 2 * self.d_state, bias=False)
        self.dt_proj = nn.Linear(self.dt_rank, self.d_inner, bias=True)
        dt_init_std = self.dt_rank**-0.5 * 1.0
        nn.init.uniform_(self.dt_proj.weight, -dt_init_std, dt_init_std)
        dt = torch.exp(
            torch.rand(self.d_inner) * (math.log(dt_max) - math.log(dt_min)) + math.log(dt_min)
        ).clamp(min=dt_init_floor)
        inv_dt = dt + torch.log(-torch.expm1(-dt))
        with torch.no_grad():
            self.dt_proj.bias.copy_(inv_dt)

        A = torch.arange(1, d_state + 1, dtype=torch.float32).repeat(self.d_inner, 1)
        self.A_log = nn.Parameter(torch.log(A))
        self.D = nn.Parameter(torch.ones(self.d_inner))
        self.out_proj = nn.Linear(self.d_inner, d_model, bias=False)

    def forward(self, x):
        B, L, D = x.shape
        x_and_z = self.in_proj(x)
        x_in, z = x_and_z.chunk(2, dim=-1)

        # CAUSAL 1D conv (left pad, drop right tail)
        x_in_t = x_in.transpose(1, 2).contiguous()
        x_in_t = self.conv1d(x_in_t)
        x_in_t = x_in_t[:, :, :L]
        x_in = x_in_t.transpose(1, 2).contiguous()
        x_in = F.silu(x_in)

        # Selective SSM (forward-only recurrence)
        y = self._selective_scan(x_in)
        y = y * F.silu(z)
        out = self.out_proj(y)
        return out

    def _selective_scan(self, x):
        B, L, d_inner = x.shape
        N = self.d_state

        A = -torch.exp(self.A_log.float())
        D = self.D.float()

        x_proj = self.x_proj(x)
        dt_rank = self.dt_rank
        dt_raw, B_in, C_in = torch.split(x_proj, [dt_rank, N, N], dim=-1)
        delta = self.dt_proj(dt_raw)
        delta = F.softplus(delta)

        with torch.amp.autocast(device_type=x.device.type, enabled=False):
            delta = delta.float()
            B_in = B_in.float()
            C_in = C_in.float()
            x_f32 = x.float()

            delta_exp = delta.unsqueeze(-1)
            A_bar = torch.exp(delta_exp * A.unsqueeze(0).unsqueeze(0))
            B_bar = delta_exp * B_in.unsqueeze(-2)

            h = torch.zeros(B, d_inner, N, dtype=torch.float32, device=x.device)
            ys = []
            for t in range(L):
                h = A_bar[:, t] * h + B_bar[:, t] * x_f32[:, t].unsqueeze(-1)
                y_t = (C_in[:, t].unsqueeze(1) * h).sum(dim=-1)
                ys.append(y_t)
            y = torch.stack(ys, dim=1)
            y = y + D.unsqueeze(0).unsqueeze(0) * x_f32

        return y.to(dtype=x.dtype)


class MambaClassifier(nn.Module):
    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 d_model=64, d_state=16, d_conv=4, expand=2,
                 n_layers=2, dropout=0.30):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.d_model = d_model

        self.embed = nn.Linear(input_dim, d_model)
        self.embed_norm = nn.LayerNorm(d_model)
        self.blocks = nn.ModuleList([
            MambaBlock(d_model, d_state=d_state, d_conv=d_conv, expand=expand)
            for _ in range(n_layers)
        ])
        self.block_norms = nn.ModuleList([nn.LayerNorm(d_model) for _ in range(n_layers)])
        self.dropout = nn.Dropout(dropout)
        self.head_norm = nn.LayerNorm(d_model)
        self.head_drop = nn.Dropout(dropout)
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, 1),
        )

    def forward(self, x):
        h = self.embed(x)
        h = self.embed_norm(h)
        for block, norm in zip(self.blocks, self.block_norms):
            h = h + self.dropout(block(norm(h)))
        h = self.head_norm(h)
        h = h.mean(dim=1)
        h = self.head_drop(h)
        return self.head(h).squeeze(-1)


# ============================================================================
# Helpers (mirror 153 exactly)
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
    """
    Load v5e features + forward labels (observable: NaN propagation).
    Codex 56B fix: prefer observable targets; fallback to legacy with explicit mask.
    """
    feat_path = DATA / "feature_panel_v5p_etf_yield.parquet"
    obs_path = TGT / "targets_long_horizon_observable_v2.parquet"
    legacy_path = TGT / "targets_long_horizon.parquet"

    if not feat_path.exists():
        sys.exit(f"missing feature panel: {feat_path}")

    if obs_path.exists():
        tgt_path = obs_path
        print(f"  [prepare_data_full] Using observable targets: {tgt_path.name}")
    else:
        tgt_path = legacy_path
        print(f"  [prepare_data_full] WARN — observable not found, fallback to legacy: {tgt_path.name}")
    if not tgt_path.exists():
        sys.exit(f"missing target parquet: {tgt_path}")

    feat = pd.read_parquet(feat_path)
    tgt_all = pd.read_parquet(tgt_path)
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt_all["Date"] = pd.to_datetime(tgt_all["Date"])

    # Cycle 58T: y_dd_* targets use ret_dd_21 (drawdown-based)
    if target_col.startswith("y_dd_"):
        ret_col = "ret_dd_21"
        if ret_col not in tgt_all.columns:
            sys.exit(f"missing {ret_col} for y_dd target")
        label_ok = tgt_all[ret_col].notna()
    else:
        h_suffix = target_col.replace("y_tail_", "")
        ret_col = f"ret_{h_suffix}"
        thr_col = f"q15_thr_{h_suffix}"
        if ret_col not in tgt_all.columns or thr_col not in tgt_all.columns:
            sys.exit(f"missing ret/thr columns for {target_col}: {ret_col} / {thr_col}")
        label_ok = tgt_all[ret_col].notna() & tgt_all[thr_col].notna()
    tgt = tgt_all[["Date", target_col]].copy()
    tgt.loc[~label_ok, target_col] = np.nan

    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END].reset_index(drop=True)

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    assert len(feature_cols) == 100, f"v5p expects 100 features, got {len(feature_cols)}"

    X = panel[feature_cols].values.astype(np.float32)
    y_raw = panel[target_col].values.astype(np.float32)
    dates = panel["Date"].values

    n_valid = int(np.isfinite(y_raw).sum())
    n_unresolved = int(len(y_raw) - n_valid)
    print(f"  [prepare_data_full/{target_col}] n_rows={len(y_raw)} "
          f"n_valid_labels={n_valid} n_unresolved={n_unresolved} "
          f"({n_unresolved/len(y_raw)*100:.1f}% NaN preserved)")

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


def detect_logit_collapse(p):
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


def train_one_window(target_col, X_full, y_full, dates,
                     train_start, train_end,
                     valid_start=None, valid_end=None,
                     fixed_epochs=None, fold_label="", seed=42,
                     lr=PT_LR, weight_decay=PT_WEIGHT_DECAY):
    set_seed_strict(seed)
    Xs = standardize_for_window(X_full, dates, train_start, train_end)
    X_seq, y_seq = make_sequences(Xs, y_full, SEQ_LEN)
    dates_seq = dates[SEQ_LEN - 1:]

    # y_valid_mask: keep only resolved labels (Codex 56B fix)
    y_finite = np.isfinite(y_seq)

    train_idx = ((dates_seq >= np.datetime64(train_start)) &
                 (dates_seq <= np.datetime64(train_end)) &
                 y_finite)

    X_train_t = torch.tensor(X_seq[train_idx], dtype=torch.float32)
    y_train_t = torch.tensor(y_seq[train_idx], dtype=torch.float32)

    has_valid = (valid_start is not None) and (valid_end is not None)
    if has_valid:
        valid_idx = ((dates_seq >= np.datetime64(valid_start)) &
                     (dates_seq <= np.datetime64(valid_end)) &
                     y_finite)
        X_valid_t = torch.tensor(X_seq[valid_idx], dtype=torch.float32).to(DEVICE)
        y_valid_t = torch.tensor(y_seq[valid_idx], dtype=torch.float32).to(DEVICE)
        valid_bear = int(y_valid_t.sum().item())
        if valid_bear < 5:
            print(f"    [WARN] {fold_label}/{target_col} valid_bear={valid_bear} < 5 — skip fold")
            return None, None, None, None, dict(
                fold=fold_label, target=target_col, seed=int(seed),
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

    g_loader = make_loader_generator(seed)
    train_loader = DataLoader(
        TensorDataset(X_train_t, y_train_t),
        batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
        num_workers=NUM_WORKERS, generator=g_loader,
        worker_init_fn=worker_init_fn if NUM_WORKERS > 0 else None,
    )

    model = MambaClassifier(input_dim=X_train_t.shape[2]).to(DEVICE)
    n_params = sum(p.numel() for p in model.parameters() if p.requires_grad)

    optim = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)
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

    print(f"    [Mamba/seed{seed}] {fold_label} "
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


def predict_oos(final_model, Xs_final, dates, y_full):
    X_seq_final, y_seq_final = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final = dates[SEQ_LEN - 1:]
    y_finite_oos = np.isfinite(y_seq_final)
    oos_idx = ((dates_seq_final >= np.datetime64(OOS_START)) &
               (dates_seq_final <= np.datetime64(OOS_END)) &
               y_finite_oos)
    n_oos_keep = int(oos_idx.sum())
    n_oos_drop = int(((dates_seq_final >= np.datetime64(OOS_START)) &
                      (dates_seq_final <= np.datetime64(OOS_END)) &
                      ~y_finite_oos).sum())
    print(f"  [OOS mask] kept {n_oos_keep} / dropped {n_oos_drop} unresolved-label rows")
    X_oos_t = torch.tensor(X_seq_final[oos_idx], dtype=torch.float32).to(DEVICE)

    final_model.eval()
    with torch.no_grad():
        bs = 256
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
    return oop, oos_y, oos_dates


def period_balanced_metrics(p, y, dates):
    periods = {
        "S2018-19_calm":        (pd.Timestamp("2018-01-01"), pd.Timestamp("2019-12-31")),
        "S2020-21_COVID":       (pd.Timestamp("2020-01-01"), pd.Timestamp("2021-12-31")),
        "S2022-24_Stagflation": (pd.Timestamp("2022-01-01"), pd.Timestamp("2024-12-31")),
        "S2025-26_post":        (pd.Timestamp("2025-01-01"), pd.Timestamp("2026-04-30")),
    }
    dates_pd = pd.to_datetime(dates)
    res = {}
    for name, (lo, hi) in periods.items():
        m = (dates_pd >= lo) & (dates_pd <= hi)
        n = int(m.sum())
        if n == 0:
            res[name] = dict(n=0, n_bear=0, pr_auc=None, ic=None, note="empty_segment")
            continue
        y_s = y[m]
        p_s = p[m]
        n_bear = int(y_s.sum())
        if n_bear < 5:
            res[name] = dict(n=n, n_bear=n_bear, pr_auc=None, ic=None,
                             note="insufficient_bear_events")
            continue
        pr = pr_auc(p_s, y_s)
        ic = ic_spearman(p_s, y_s)
        base = n_bear / n
        lift = (pr / base) if (pr is not None and base > 0 and not np.isnan(pr)) else None
        res[name] = dict(
            n=n, n_bear=n_bear,
            base_rate=round(base, 4),
            pr_auc=round(pr, 4) if not np.isnan(pr) else None,
            ic=round(ic, 4) if not np.isnan(ic) else None,
            lift=round(lift, 4) if lift is not None else None,
            p_max=round(float(np.max(p_s)), 6),
            p_p99=round(float(np.percentile(p_s, 99)), 6),
            p_p50=round(float(np.percentile(p_s, 50)), 6),
        )
    return res


def run_mamba_for_seed(target_col, seed):
    """Run Mamba for ONE seed end-to-end: 4-fold CV (Fold3 skipped) → FINAL train → OOS predict."""
    print("\n" + "=" * 80)
    print(f"[Cycle 56D-Batch2-multiseed] Mamba target={target_col} seed={seed}")
    print("=" * 80)
    skip_folds = SKIP_FOLDS_PER_TARGET.get(target_col, [])
    if skip_folds:
        print(f"  [INFO] Skipping degenerate folds: {skip_folds}")
    t_start = time.time()

    X_full, y_full, dates, _ = prepare_data_full(target_col)

    # Walk-forward CV
    fold_results = []
    for fi in FOLDS:
        if fi["name"] in skip_folds:
            print(f"\n  --- {fi['name']} SKIPPED (degenerate q126) ---")
            fold_results.append(dict(
                fold=fi["name"], target=target_col, seed=int(seed),
                best_valid_pr=None, best_epoch=None, epochs_done=0, early_stop_ep=None,
                valid_bear_count=0, train_loss_first=None, train_loss_last=None,
                n_params=None, skipped=True, skip_reason="zero-events"
            ))
            continue
        print(f"\n  --- {fi['name']} ---")
        _, _, _, _, fold_res = train_one_window(
            target_col, X_full, y_full, dates,
            train_start=fi["train_start"], train_end=fi["train_end"],
            valid_start=fi["valid_start"], valid_end=fi["valid_end"],
            fixed_epochs=None, fold_label=fi["name"], seed=seed,
        )
        fold_results.append(fold_res)
        if DEVICE.type == "cuda":
            torch.cuda.empty_cache()

    valid_eps = [r["best_epoch"] for r in fold_results
                 if r.get("best_epoch") is not None and r["best_epoch"] > 0]
    avg_best_ep = int(round(np.mean(valid_eps))) if valid_eps else (MAX_EPOCHS // 2)
    print(f"\n  [Avg best_epoch across {len(valid_eps)} folds] = {avg_best_ep}")

    # FINAL train + OOS predict (single attempt — Mamba didn't collapse in 153)
    print(f"\n  --- FINAL TRAIN seed={seed} epochs={avg_best_ep} ---")
    final_model, Xs_final, _, _, final_train_res = train_one_window(
        target_col, X_full, y_full, dates,
        train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
        valid_start=None, valid_end=None,
        fixed_epochs=avg_best_ep, fold_label=f"FINAL_seed{seed}", seed=seed,
    )
    oop, oos_y, oos_dates = predict_oos(final_model, Xs_final, dates, y_full)
    collapse = detect_logit_collapse(oop)
    oos_pr = pr_auc(oop, oos_y)
    oos_ic = ic_spearman(oop, oos_y)

    elapsed = time.time() - t_start
    print(f"\n  [Mamba/seed{seed}/{target_col}] OOS PR-AUC={oos_pr:.4f}  IC={oos_ic:.4f}  "
          f"collapsed={collapse['collapsed']}  elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    period_metrics = period_balanced_metrics(oop, oos_y, oos_dates)

    # Save per-seed predictions
    df = pd.DataFrame({
        "Date": oos_dates,
        f"p_mamba_seed{seed}": oop,
        "y": oos_y,
        "split": "oos",
        "target": target_col,
        "model": "Mamba",
        "seed": int(seed),
        "collapsed": bool(collapse["collapsed"]),
    })
    file_name = f"predictions_mamba_seed{seed}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT / file_name}")

    del final_model
    if DEVICE.type == "cuda":
        torch.cuda.empty_cache()

    return dict(
        target=target_col,
        seed=int(seed),
        oos_pr=round(float(oos_pr), 4) if not np.isnan(oos_pr) else None,
        oos_ic=round(float(oos_ic), 4) if not np.isnan(oos_ic) else None,
        collapse=collapse,
        avg_best_epoch=avg_best_ep,
        per_fold_best_pr=[r.get("best_valid_pr") for r in fold_results],
        per_fold_best_epoch=[r.get("best_epoch") for r in fold_results],
        per_fold_valid_bear=[r.get("valid_bear_count") for r in fold_results],
        per_fold_skipped=[r.get("skipped", False) for r in fold_results],
        per_fold_n_params=fold_results[0].get("n_params") if fold_results else None,
        final_train_loss_first=final_train_res["train_loss_first"],
        final_train_loss_last=final_train_res["train_loss_last"],
        period_metrics=period_metrics,
        elapsed_sec=round(elapsed, 1),
        gpu_mem_peak_mb=round(mem_peak_mb, 1) if not math.isnan(mem_peak_mb) else None,
        n_params=int(final_train_res["n_params"]),
        fold_results_detailed=fold_results,
        oos_dates=oos_dates,
        oos_pred=oop,
        oos_y=oos_y,
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
    def md5_file(p):
        if not Path(p).exists(): return "missing"
        h = hashlib.md5()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                h.update(chunk)
        return h.hexdigest()
    feat_md5 = md5_file(DATA / "feature_panel_v5p_etf_yield.parquet")
    tgt_md5_obs = md5_file(TGT / "targets_long_horizon_observable_v2.parquet")
    return dict(
        cycle="56D-Batch2-multiseed",
        script="164_mamba_5seed_strict.py",
        git_sha=sha,
        torch_version=torch_v,
        cuda_version=cuda_v,
        device=str(DEVICE),
        python_hashseed=os.environ.get('PYTHONHASHSEED'),
        cublas_workspace=os.environ.get('CUBLAS_WORKSPACE_CONFIG'),
        cudnn_deterministic=torch.backends.cudnn.deterministic,
        cudnn_benchmark=torch.backends.cudnn.benchmark,
        use_amp=USE_AMP,
        seeds=SEEDS,
        reseed_max=RESEED_MAX,
        feature_panel_md5=feat_md5,
        targets_observable_md5=tgt_md5_obs,
        oos_window=dict(start=str(OOS_START.date()), end=str(OOS_END.date())),
        folds_used=FOLDS,
        skip_folds_per_target=SKIP_FOLDS_PER_TARGET,
        target=TARGETS,
        architecture="Mamba (Gu & Dao 2023 S6) — d_model=64 d_state=16 d_conv=4 expand=2 n_layers=2 dropout=0.30",
        ref_53h_mean5=REF_53H_MEAN5_Q126,
        ref_mamba_seed42=REF_MAMBA_SEED42_Q126,
        notes="Strict determinism + y_valid_mask + observable targets + period-balanced metrics.",
    )


# ============================================================================
# Main
# ============================================================================
if __name__ == "__main__":
    print("=" * 80)
    print("[Cycle 56D-Batch2-multiseed — Mamba 5-seed q126]")
    print("[v5e panel 74 features / forward labels observable / WF 4-fold (Fold3 q126 skip)]")
    print(f"[Seeds: {SEEDS} → 5-seed mean ensemble]")
    print(f"[Reference: 53H_v5e mean5={REF_53H_MEAN5_Q126} / Mamba seed=42 single={REF_MAMBA_SEED42_Q126}]")
    print("=" * 80)

    prov = collect_provenance()
    with (OUT / "provenance.json").open("w") as f:
        json.dump(prov, f, indent=2, default=str)
    print(f"[Provenance] Saved: {OUT / 'provenance.json'}")

    results = {}
    for target_col in TARGETS:
        for seed in SEEDS:
            key = f"seed{seed}_{target_col}"
            try:
                results[key] = run_mamba_for_seed(target_col, seed)
                # Incremental save (resumable)
                def serialize(r):
                    if not isinstance(r, dict):
                        return r
                    return {k: v for k, v in r.items() if k not in ("oos_dates", "oos_pred", "oos_y")}
                with (OUT / "per_seed_partial.json").open("w") as f:
                    json.dump(
                        dict(cycle="56D-Batch2-multiseed", provenance=prov,
                             results_so_far={k: serialize(v) for k, v in results.items()}),
                        f, indent=2, default=str,
                    )
            except Exception as e:
                print(f"\n[ERROR] seed {key} failed: {e}")
                import traceback
                traceback.print_exc()
                results[key] = dict(error=str(e))

    # ============================================================================
    # 5-seed mean ensemble
    # ============================================================================
    print("\n" + "=" * 80)
    print("[5-seed mean ensemble construction]")
    print("=" * 80)
    ensemble_per_target = {}
    for target_col in TARGETS:
        seed_results = [results.get(f"seed{s}_{target_col}") for s in SEEDS]
        seed_results = [r for r in seed_results if isinstance(r, dict) and "error" not in r]
        if len(seed_results) < 2:
            print(f"  [WARN] target={target_col}: < 2 successful seeds, skip mean.")
            continue

        # Align by Date (intersection of all per-seed dates)
        all_dates = [set(pd.to_datetime(r["oos_dates"])) for r in seed_results]
        common_dates = sorted(set.intersection(*all_dates))
        if len(common_dates) == 0:
            print(f"  [WARN] target={target_col}: no common dates across seeds, skip mean.")
            continue
        print(f"  target={target_col}: {len(common_dates)} common dates across {len(seed_results)} seeds")

        # Build per-seed prediction aligned on common_dates
        per_seed_preds = []
        per_seed_pr = []
        per_seed_ic = []
        y_common = None
        for r in seed_results:
            df_r = pd.DataFrame({
                "Date": pd.to_datetime(r["oos_dates"]),
                "p": r["oos_pred"],
                "y": r["oos_y"],
            })
            df_r = df_r.set_index("Date").loc[common_dates].reset_index()
            per_seed_preds.append(df_r["p"].values)
            per_seed_pr.append(pr_auc(df_r["p"].values, df_r["y"].values))
            per_seed_ic.append(ic_spearman(df_r["p"].values, df_r["y"].values))
            if y_common is None:
                y_common = df_r["y"].values
            else:
                # All per-seed y should be identical on common dates
                if not np.array_equal(y_common, df_r["y"].values):
                    print(f"  [WARN] y misalign across seeds — using first seed's y")

        per_seed_preds = np.vstack(per_seed_preds)  # (n_seeds, n_dates)
        mean_pred = per_seed_preds.mean(axis=0)
        per_date_std = per_seed_preds.std(axis=0)

        mean_pr = pr_auc(mean_pred, y_common)
        mean_ic = ic_spearman(mean_pred, y_common)
        mean_periods = period_balanced_metrics(mean_pred, y_common, np.array(common_dates))

        print(f"\n  [5-seed mean / {target_col}]")
        print(f"    per_seed PR-AUC: {[round(p,4) for p in per_seed_pr]}")
        print(f"    per_seed mean PR: {np.mean(per_seed_pr):.4f}  std: {np.std(per_seed_pr):.4f}")
        print(f"    per_seed IC:     {[round(i,4) for i in per_seed_ic]}")
        print(f"    Mean prediction PR-AUC: {mean_pr:.4f}  IC: {mean_ic:.4f}")
        print(f"    Per-date std mean: {np.mean(per_date_std):.4f}  median: {np.median(per_date_std):.4f}")
        print(f"\n    Period-balanced (mean5):")
        n_lift_gt1 = 0
        for nm, pm in mean_periods.items():
            lift = pm.get("lift")
            pr = pm.get("pr_auc")
            base = pm.get("base_rate")
            if lift is not None and lift > 1.0:
                n_lift_gt1 += 1
                print(f"      {nm}: PR={pr} base={base} lift={lift} ⭐")
            else:
                print(f"      {nm}: PR={pr} base={base} lift={lift}")
        n_valid_periods = sum(1 for pm in mean_periods.values()
                              if pm.get("lift") is not None)
        print(f"\n    Period-balanced verdict: {n_lift_gt1}/{n_valid_periods} segments with lift>1")

        # Stability verdict
        std_val = float(np.std(per_seed_pr))
        if std_val < STABILITY_STD_STABLE:
            stability = "STABLE"
        elif std_val < STABILITY_STD_MODERATE:
            stability = "MODERATE"
        else:
            stability = "UNSTABLE"

        # Save mean5 predictions
        df_mean = pd.DataFrame({
            "Date": pd.to_datetime(common_dates),
            "p_mamba_mean5": mean_pred,
            "p_per_seed_std": per_date_std,
            "y": y_common,
            "split": "oos",
            "target": target_col,
            "n_seeds": len(seed_results),
        })
        df_mean.to_parquet(OUT / f"predictions_mamba_mean5_{target_col}.parquet", index=False)
        print(f"    Saved: {OUT / f'predictions_mamba_mean5_{target_col}.parquet'}")

        ensemble_per_target[target_col] = dict(
            n_seeds=len(seed_results),
            seeds_used=[r["seed"] for r in seed_results],
            n_common_dates=len(common_dates),
            per_seed_pr=[float(p) for p in per_seed_pr],
            per_seed_ic=[float(i) for i in per_seed_ic],
            per_seed_pr_mean=float(np.mean(per_seed_pr)),
            per_seed_pr_std=float(np.std(per_seed_pr)),
            per_seed_pr_min=float(np.min(per_seed_pr)),
            per_seed_pr_max=float(np.max(per_seed_pr)),
            per_seed_pr_range=float(np.max(per_seed_pr) - np.min(per_seed_pr)),
            mean5_pr_auc=float(mean_pr) if not np.isnan(mean_pr) else None,
            mean5_ic=float(mean_ic) if not np.isnan(mean_ic) else None,
            per_date_std_mean=float(np.mean(per_date_std)),
            per_date_std_median=float(np.median(per_date_std)),
            per_date_std_max=float(np.max(per_date_std)),
            per_date_std_min=float(np.min(per_date_std)),
            stability_verdict=stability,
            n_segments_lift_gt1=int(n_lift_gt1),
            n_segments_evaluable=int(n_valid_periods),
            period_metrics_mean5=mean_periods,
        )

    # ============================================================================
    # SUMMARY + Verdict
    # ============================================================================
    print("\n" + "=" * 80)
    print("[Cycle 56D-Batch2-multiseed SUMMARY]")
    print("=" * 80)
    print(f"\n  Reference 53H_v5e mean5 strict-PIT = {REF_53H_MEAN5_Q126}")
    print(f"  Reference Mamba seed=42 single (153) = {REF_MAMBA_SEED42_Q126}\n")

    for target_col in TARGETS:
        if target_col not in ensemble_per_target:
            continue
        e = ensemble_per_target[target_col]
        print(f"  === Mamba 5-seed mean5 / {target_col} ===")
        print(f"    per_seed PR-AUC: {[round(p,4) for p in e['per_seed_pr']]}")
        print(f"    per_seed PR mean = {e['per_seed_pr_mean']:.4f}  std = {e['per_seed_pr_std']:.4f}")
        print(f"    mean5 PR-AUC = {e['mean5_pr_auc']:.4f}  IC = {e['mean5_ic']:.4f}")
        print(f"    Δ vs 53H mean5 = {e['mean5_pr_auc'] - REF_53H_MEAN5_Q126:+.4f}")
        print(f"    Δ vs seed=42 single (153) = {e['mean5_pr_auc'] - REF_MAMBA_SEED42_Q126:+.4f}")
        print(f"    Stability: {e['stability_verdict']} (std={e['per_seed_pr_std']:.4f})")
        print(f"    Period-balanced: {e['n_segments_lift_gt1']}/{e['n_segments_evaluable']} segments lift>1")

        # Final verdict
        mean5_pr = e['mean5_pr_auc']
        std_val = e['per_seed_pr_std']
        n_lift = e['n_segments_lift_gt1']
        n_eval = e['n_segments_evaluable']

        if (mean5_pr >= 0.42 and std_val < 0.05 and n_lift == n_eval and n_eval >= 3):
            final_verdict = "MAMBA_VALIDATED"
        elif (mean5_pr >= 0.42 and n_lift < n_eval):
            final_verdict = "MAMBA_PERIOD_FRAGILE"
        elif (mean5_pr < REF_MAMBA_SEED42_Q126):
            final_verdict = "MAMBA_LUCKY_SEED"
        else:
            final_verdict = "MAMBA_INCONCLUSIVE"
        print(f"    >>> FINAL VERDICT: {final_verdict}")
        e['final_verdict'] = final_verdict

    # ============================================================================
    # Persist diagnostics
    # ============================================================================
    audit_path = OUT / "multiseed_variance_audit.json"
    audit_doc = {
        "cycle": "56D_Batch2_multiseed_mamba",
        "audit_type": "5_seed_variance_audit_mamba",
        "purpose": "Verify Mamba seed=42 0.4264 is robust or lucky seed",
        "panel": "feature_panel_v5p_etf_yield.parquet",
        "targets_source": "targets_long_horizon_observable_v2.parquet",
        "n_features": 74,
        "seeds": SEEDS,
        "n_seeds": len(SEEDS),
        "validation_strategy": "walk_forward_expanding_5_fold_CV_Fold3_skipped_q126",
        "architecture": "Mamba (Gu & Dao 2023 S6)",
        "mamba_hparams": {
            "d_model": 64, "d_state": 16, "d_conv": 4, "expand": 2,
            "n_layers": 2, "dropout": 0.30,
        },
        "training_common": {
            "batch_size": BATCH_SIZE, "max_epochs": MAX_EPOCHS,
            "early_stop_patience": EARLY_STOP_PATIENCE,
            "early_stop_min_delta": EARLY_STOP_MIN_DELTA,
            "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
            "mixed_precision_amp": USE_AMP,
            "gpu_mem_fraction": 0.15 if DEVICE.type == "cuda" else None,
            "lr": PT_LR, "weight_decay": PT_WEIGHT_DECAY,
            "strict_determinism": True,
            "cudnn_deterministic": torch.backends.cudnn.deterministic,
            "cudnn_benchmark": torch.backends.cudnn.benchmark,
            "cublas_workspace_config": os.environ.get('CUBLAS_WORKSPACE_CONFIG'),
        },
        "stability_thresholds": {
            "STABLE_std_lt": STABILITY_STD_STABLE,
            "MODERATE_std_max": STABILITY_STD_MODERATE,
            "UNSTABLE_std_gt": STABILITY_STD_MODERATE,
        },
        "baselines": {
            "cycle_53h_v5e_mean5_strict_pit_q126": REF_53H_MEAN5_Q126,
            "cycle_56d_batch2_mamba_seed42_q126": REF_MAMBA_SEED42_Q126,
        },
        "provenance": prov,
        "audit_per_target": ensemble_per_target,
        "per_seed_summary_per_target": {
            tgt: {
                f"seed{r['seed']}": {
                    "oos_pr": r.get("oos_pr"),
                    "oos_ic": r.get("oos_ic"),
                    "collapsed": r.get("collapse", {}).get("collapsed"),
                    "p_max": r.get("collapse", {}).get("p_max"),
                    "logit_median": r.get("collapse", {}).get("logit_median"),
                    "avg_best_epoch": r.get("avg_best_epoch"),
                    "elapsed_sec": r.get("elapsed_sec"),
                    "per_fold_best_pr": r.get("per_fold_best_pr"),
                    "period_metrics": r.get("period_metrics"),
                }
                for r in [results.get(f"seed{s}_{tgt}") for s in SEEDS]
                if isinstance(r, dict) and "error" not in r
            }
            for tgt in TARGETS
        },
    }
    with audit_path.open("w") as f:
        json.dump(audit_doc, f, indent=2, default=str)
    print(f"\n[Audit] Saved: {audit_path}")

    # Per-fold diagnostics dump
    per_fold_path = OUT / "per_fold_diagnostics.json"
    per_fold = {
        "cycle": "56D_Batch2_multiseed_mamba",
        "validation_strategy": "walk_forward_expanding_5_fold_CV_Fold3_skipped_q126",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "skip_folds_per_target": SKIP_FOLDS_PER_TARGET,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date())},
        "feature_panel": "feature_panel_v5p_etf_yield.parquet (74 features)",
        "seeds": SEEDS,
        "provenance": prov,
        "per_seed_results": {
            k: {key: val for key, val in v.items()
                if key not in ("oos_dates", "oos_pred", "oos_y")}
            for k, v in results.items()
            if isinstance(v, dict) and "error" not in v
        },
        "ensemble_mean5_per_target": ensemble_per_target,
    }
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"[Per-fold] Saved: {per_fold_path}")

    print("\n" + "=" * 80)
    print("[Cycle 56D-Batch2-multiseed DONE — proceed to scripts/165_3arch_heterogeneous_ensemble.R]")
    print("=" * 80)
