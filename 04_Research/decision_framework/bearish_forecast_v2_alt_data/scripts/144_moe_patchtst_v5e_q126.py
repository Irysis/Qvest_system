#!/usr/bin/env python3
"""
144_moe_patchtst_v5e_q126.py — Cycle 56B Mixture-of-Experts per Regime

Architecture:
  4 regime experts (BULL / NORMAL / CAUTION / CRISIS) + gating network.
  - Experts: PatchTST channel-independent (53H mirror exact hparams)
  - Regime detector: M4 BOCPD × AR threshold × R05 (inherited from Production overlay)
  - Per-regime training: each expert sees only its regime's days in train window
  - Gating: regime probability (currently hard one-hot from t-1 regime_state) →
            weighted ensemble of experts (only feasible experts contribute)

Empirical finding (143 audit):
  TRAIN 1995-2015 distribution:
    BULL=1233 days / 136 bear   (FEASIBLE)
    NORMAL=1664 days / 252 bear (FEASIBLE)
    CAUTION=61 days / 0 bear   (INFEASIBLE)
    CRISIS=21 days / 1 bear    (INFEASIBLE)

Design (necessary divergence from naive "4 experts"):
  - FEASIBLE regimes (BULL/NORMAL): dedicated experts, regime-conditional training.
  - INFEASIBLE regimes (CAUTION/CRISIS): fall back to a "FULL" pooled-expert
    (entire panel, no regime filter) trained alongside. This expert acts as
    the default safety net (mirrors 53H baseline architecture exactly).
  - Gating is therefore 3-way (BULL / NORMAL / FULL_default) instead of 4-way.
    When regime_t = CAUTION or CRISIS, gating routes 100% to FULL.

Multi-seed:
  - 5 seeds [42, 123, 456, 789, 1024]
  - per expert × per seed = 3 × 5 = 15 final training runs
  - Walk-forward 5-fold CV per expert × per seed = 15 × 5 = 75 fold runs
    (CAUTION/CRISIS folds rarely have valid_bear>=5 → most skipped; FULL CV used)

Pipeline:
  - Per-expert prepare_data_full (full panel) → mask train_idx by regime
  - For BULL/NORMAL: train_idx = (date in fold_train_period) & (regime_t == regime)
  - For FULL: train_idx = (date in fold_train_period) [no regime filter; 53H baseline mirror]

Outputs:
  outputs/03_models/v6a_moe_q126/predictions_expert_{BULL|NORMAL|FULL}_seed{S}_y_tail_q126.parquet
  outputs/03_models/v6a_moe_q126/predictions_moe_mean_y_tail_q126.parquet  (gating-weighted ensemble)
  outputs/03_models/v6a_moe_q126/per_fold_diagnostics.json
  outputs/03_models/v6a_moe_q126/moe_audit.json

PIT:
  - regime_state already t-1 lagged in regime_daily_lag1.parquet
  - Per-window standardization on train window only
  - Walk-forward expanding splits identical to 53H
  - bear_date_audit 4/4 PASS PRE-CYCLE (2026-05-21 08:51:46)

GPU memory fraction: 0.20 (per cycle 56B parallel budget mandate)
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
OUT = WS / "outputs/03_models/v6a_moe_q126"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 56B] Device: {DEVICE}")

if DEVICE.type == "cuda":
    try:
        # 56B + 54C + 56D + 56-2stage parallel budget allocation
        torch.cuda.set_per_process_memory_fraction(0.20, device=0)
        print(f"[Cycle 56B] CUDA memory fraction set to 0.20 (parallel budget)")
    except Exception as e:
        print(f"[Cycle 56B] CUDA fraction set failed: {e}")
    USE_AMP = True
else:
    USE_AMP = False

# Mirror 53H OOS window
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")

FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# 5-fold walk-forward (mirror 53H exact)
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

# PatchTST hparams (53H exact mirror)
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

# Targets
TARGETS = ["y_tail_q126"]  # primary only for compute budget
SEEDS = [42, 123, 456, 789, 1024]

# Horizon (target = y_tail_qH → label realized H business days forward)
TARGET_HORIZON_DAYS = {"y_tail_q126": 126, "y_tail_q15": 15, "y_tail_q63": 63}

# Experts (FEASIBLE + FULL fallback)
EXPERTS = ["BULL", "NORMAL", "FULL"]
FEASIBLE_REGIMES = {"BULL", "NORMAL"}

# Min train viability per (regime, fold) — applied to expert training data
MIN_TRAIN_DAYS = 200
MIN_TRAIN_BEAR = 5

# PIT FIX (Codex CRITICAL bug #1): Purged k-fold CV.
# For target y_tail_q126, label[t] = realized return over [t, t+126].
# If a training row at date t has t+H >= valid_start, its label leaks into valid period.
# Solution: purge training rows where t > valid_start - H business days.
ENABLE_PURGED_CV = True


# ============================================================================
# PatchTST (53H exact mirror)
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
# Helpers (53H exact mirror)
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
    return float(np.corrcoef(pd.Series(p).rank().values,
                             pd.Series(y).rank().values)[0, 1])


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
    Load v5e features + targets + regime (regime joined here).

    PIT FIX (Codex review CRITICAL bug #2, 2026-05-21):
      - targets_long_horizon.parquet에서 ret_q126 또한 load.
      - y_tail_q126==0 but ret_q126 IS NA → label unresolved (forward horizon
        미실현). 이런 rows는 y_valid_mask=False로 marking하여 train/valid/OOS
        metric에서 제외.
      - q126 horizon = 126 영업일 (≈6m). OOS_END 2026-04-30이면
        last realized prediction date ≈ 2025-11-18.
    """
    feat = pd.read_parquet(DATA / "feature_panel_v5e_q126_usmacro.parquet")
    horizon_col = target_col.replace("y_tail_", "ret_")  # y_tail_q126 → ret_q126
    tgt_cols = ["Date", target_col, horizon_col]
    tgt = pd.read_parquet(TGT / "targets_long_horizon.parquet")[tgt_cols]
    regime = pd.read_parquet(DATA / "regime_daily_lag1.parquet")[["Date", "regime_state"]]

    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])
    regime["Date"] = pd.to_datetime(regime["Date"])

    panel = feat.merge(tgt, on="Date", how="left")
    panel = panel.merge(regime, on="Date", how="left")
    panel = panel.sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END]

    feature_cols = [c for c in panel.columns
                    if c not in ("Date", target_col, horizon_col, "regime_state")]
    assert len(feature_cols) == 74, f"v5e expects 74 features, got {len(feature_cols)}"

    X = panel[feature_cols].values.astype(np.float32)
    y_raw = panel[target_col].fillna(0).values.astype(np.float32)
    # y_valid_mask: True only if forward return resolved (ret_q126 NOT NA)
    y_valid_mask = panel[horizon_col].notna().values
    dates = panel["Date"].values
    regime_arr = panel["regime_state"].fillna("UNKNOWN").values
    print(f"  [prepare_data_full] target={target_col} n_total={len(y_raw)} "
          f"n_y_valid={int(y_valid_mask.sum())} n_y_unresolved={int((~y_valid_mask).sum())} "
          f"(unresolved = label 미실현 → train/valid/OOS metric에서 제외)")
    return X, y_raw, y_valid_mask, dates, regime_arr, feature_cols


def standardize_for_window(X, dates, train_start, train_end, train_mask_extra=None):
    """
    Standardize using train window stats only.
    If train_mask_extra (e.g., regime mask) provided, intersect with date window.
    """
    train_mask = (dates >= np.datetime64(train_start)) & (dates <= np.datetime64(train_end))
    if train_mask_extra is not None:
        train_mask = train_mask & train_mask_extra
    if train_mask.sum() < 30:
        # Insufficient training data — fall back to full date window stats
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
    import random
    random.seed(seed)
    torch.manual_seed(seed)
    np.random.seed(seed)
    if DEVICE.type == "cuda":
        torch.cuda.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)


def train_one_expert_window(target_col,
                            X_full, y_full, y_valid_mask, dates, regime_arr,
                            train_start, train_end,
                            valid_start, valid_end,
                            expert_name,
                            fixed_epochs=None, fold_label="", seed=42):
    """
    Train one expert (one regime or FULL) on one window.

    Train data mask (PIT FIX 2026-05-21):
      - expert_name in FEASIBLE_REGIMES: train_idx = date∈[train_start, train_end]
                                          & regime_t==expert
                                          & y_valid_mask
                                          & (purged_horizon if has_valid)
      - expert_name == "FULL": train_idx = date∈[train_start, train_end]
                                & y_valid_mask
                                & (purged_horizon if has_valid)
    Valid data mask:
      - Always restricted to dates with resolved labels (y_valid_mask=True)
      - For FEASIBLE expert: valid_idx = date∈[valid_start, valid_end]
                                       & regime_t==expert & y_valid_mask
      - For FULL: valid_idx = date∈[valid_start, valid_end] & y_valid_mask

    Purged-label fix (Codex CRITICAL bug #1):
      For target y_tail_qH: label[t] = realized over [t, t+H].
      If t+H >= valid_start, label leaks into valid → exclude.
      Equivalent: train_idx requires t <= valid_start - H business days.

    Returns (model, Xs, dates_seq, y_seq, result)
    """
    set_seed(seed)

    # Build regime-conditional train mask BEFORE standardization
    if expert_name in FEASIBLE_REGIMES:
        regime_mask = (regime_arr == expert_name)
    else:
        regime_mask = np.ones(len(regime_arr), dtype=bool)  # FULL: no filter

    # Combine with y_valid_mask for standardization (use only valid-labeled days)
    std_mask = regime_mask & y_valid_mask

    # Standardize using EXPERT TRAIN DATA stats (regime + y_valid conditional)
    Xs = standardize_for_window(X_full, dates, train_start, train_end,
                                 train_mask_extra=std_mask)
    X_seq, y_seq = make_sequences(Xs, y_full, SEQ_LEN)
    dates_seq = dates[SEQ_LEN - 1:]
    regime_seq = regime_arr[SEQ_LEN - 1:]
    y_valid_seq = y_valid_mask[SEQ_LEN - 1:]

    # Train index (PIT FIX: y_valid_mask + purged horizon if CV)
    in_train_window = (dates_seq >= np.datetime64(train_start)) & \
                       (dates_seq <= np.datetime64(train_end))
    if expert_name in FEASIBLE_REGIMES:
        in_regime = (regime_seq == expert_name)
    else:
        in_regime = np.ones(len(regime_seq), dtype=bool)

    train_idx = in_train_window & in_regime & y_valid_seq

    # Purged k-fold CV: if has_valid, exclude rows whose label realization (t+H)
    # could overlap valid_start
    has_valid = (valid_start is not None) and (valid_end is not None)
    H = TARGET_HORIZON_DAYS.get(target_col, 0)
    purge_count = 0
    if has_valid and ENABLE_PURGED_CV and H > 0:
        # Use np.busday_offset for business-day-aware purge
        valid_start_dt = np.datetime64(valid_start)
        # Exclude train rows where dates_seq[t] > valid_start - H business days
        # Equivalent: dates_seq[t] + H business days >= valid_start
        train_offset = np.busday_offset(dates_seq.astype('datetime64[D]'),
                                         H, roll='forward')
        purge_mask = train_offset < valid_start_dt
        purge_count = int(train_idx.sum() - (train_idx & purge_mask).sum())
        train_idx = train_idx & purge_mask

    n_train = int(train_idx.sum())
    n_train_bear = int(y_seq[train_idx].sum())

    # Valid index (PIT FIX: y_valid_mask)
    if has_valid:
        in_valid_window = (dates_seq >= np.datetime64(valid_start)) & \
                          (dates_seq <= np.datetime64(valid_end))
        if expert_name in FEASIBLE_REGIMES:
            valid_idx = in_valid_window & (regime_seq == expert_name) & y_valid_seq
        else:
            valid_idx = in_valid_window & y_valid_seq
        n_valid = int(valid_idx.sum())
        n_valid_bear = int(y_seq[valid_idx].sum())
    else:
        valid_idx = None
        n_valid = 0
        n_valid_bear = 0

    # Skip if train data insufficient
    if n_train < MIN_TRAIN_DAYS or n_train_bear < MIN_TRAIN_BEAR:
        print(f"    [SKIP {expert_name}/{fold_label}/seed{seed}] "
              f"n_train={n_train} n_train_bear={n_train_bear} "
              f"< MIN({MIN_TRAIN_DAYS},{MIN_TRAIN_BEAR}) (purged={purge_count})")
        return None, None, None, None, dict(
            fold=fold_label, expert=expert_name, target=target_col, seed=int(seed),
            best_valid_pr=None, best_epoch=None, epochs_done=0,
            early_stop_ep=None, n_train=n_train, n_train_bear=n_train_bear,
            n_valid=n_valid, n_valid_bear=n_valid_bear,
            purged_train_count=purge_count,
            skipped=True, skip_reason="insufficient_train"
        )

    # Skip if valid_bear < 5 (Fold3 q126 zero-events guard, 53H mirror)
    if has_valid and n_valid_bear < 5:
        print(f"    [SKIP {expert_name}/{fold_label}/seed{seed}] "
              f"n_valid_bear={n_valid_bear} < 5 (purged={purge_count})")
        return None, None, None, None, dict(
            fold=fold_label, expert=expert_name, target=target_col, seed=int(seed),
            best_valid_pr=None, best_epoch=None, epochs_done=0,
            early_stop_ep=None, n_train=n_train, n_train_bear=n_train_bear,
            n_valid=n_valid, n_valid_bear=n_valid_bear,
            purged_train_count=purge_count,
            skipped=True, skip_reason="valid_bear<5"
        )

    X_train_t = torch.tensor(X_seq[train_idx], dtype=torch.float32)
    y_train_t = torch.tensor(y_seq[train_idx], dtype=torch.float32)

    if has_valid:
        X_valid_t = torch.tensor(X_seq[valid_idx], dtype=torch.float32).to(DEVICE)
        y_valid_t = torch.tensor(y_seq[valid_idx], dtype=torch.float32).to(DEVICE)

    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)

    train_loader = DataLoader(TensorDataset(X_train_t, y_train_t),
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
                              num_workers=NUM_WORKERS)

    model = PatchTSTClassifier(input_dim=X_train_t.shape[2]).to(DEVICE)
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

    print(f"    [{expert_name}/{target_col}/seed{seed}] {fold_label} "
          f"n_train={n_train} n_train_bear={n_train_bear} "
          f"n_valid={'-' if not has_valid else n_valid} "
          f"pos_w={pos_w_value:.2f} target_ep={target_epochs} "
          f"purged={purge_count}")

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
        expert=expert_name,
        target=target_col,
        seed=int(seed),
        best_valid_pr=round(best_val, 4) if has_valid else None,
        best_epoch=int(best_epoch) if best_epoch > 0 else None,
        epochs_done=int(epochs_done),
        early_stop_ep=int(early_stop_ep) if early_stop_ep > 0 else None,
        n_train=n_train, n_train_bear=n_train_bear,
        n_valid=n_valid, n_valid_bear=n_valid_bear,
        purged_train_count=purge_count,
        train_loss_first=round(train_loss_traj[0], 4) if train_loss_traj else None,
        train_loss_last=round(train_loss_traj[-1], 4) if train_loss_traj else None,
        n_params=int(n_params),
        skipped=False,
    )
    return model, Xs, dates_seq, y_seq, result


def run_expert_walkforward(target_col, expert_name, seed,
                            X_full, y_full, y_valid_mask, dates, regime_arr):
    """Per-expert per-seed: 5-fold CV + FINAL_TRAIN + OOS predictions."""
    print("\n" + "=" * 70)
    print(f"[Cycle 56B] Expert={expert_name} Seed={seed} Target={target_col}")
    print("=" * 70)
    t_start = time.time()

    fold_results = []
    for fi in FOLDS:
        print(f"\n  --- {fi['name']} (expert={expert_name}, seed={seed}) ---")
        _, _, _, _, fold_res = train_one_expert_window(
            target_col, X_full, y_full, y_valid_mask, dates, regime_arr,
            train_start=fi["train_start"], train_end=fi["train_end"],
            valid_start=fi["valid_start"], valid_end=fi["valid_end"],
            expert_name=expert_name,
            fixed_epochs=None, fold_label=fi["name"], seed=seed,
        )
        fold_results.append(fold_res)
        if DEVICE.type == "cuda":
            torch.cuda.empty_cache()

    valid_eps = [r["best_epoch"] for r in fold_results
                 if r.get("best_epoch") is not None and r["best_epoch"] > 0]
    if len(valid_eps) == 0:
        avg_best_ep = MAX_EPOCHS // 2
        print(f"\n  [WARN] All folds best_epoch <= 0 — fallback {avg_best_ep}")
    else:
        avg_best_ep = int(round(np.mean(valid_eps)))
    print(f"\n  [avg best_epoch] {expert_name}/seed{seed} = {avg_best_ep}")

    # FINAL_TRAIN on 1995-2015 (regime-conditional if feasible)
    # PIT FIX: FINAL_TRAIN has no valid_window → no purge needed (but y_valid_mask applies).
    print(f"\n  --- FINAL_TRAIN expert={expert_name} seed={seed} ---")
    final_model, Xs_final, dates_seq_final, y_seq_final, final_res = train_one_expert_window(
        target_col, X_full, y_full, y_valid_mask, dates, regime_arr,
        train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
        valid_start=None, valid_end=None,
        expert_name=expert_name,
        fixed_epochs=avg_best_ep, fold_label="FINAL_TRAIN", seed=seed,
    )

    if final_model is None:
        print(f"  [FAIL] FINAL_TRAIN skipped — expert {expert_name} has insufficient data")
        return None

    # OOS: predict for ALL OOS dates with VALID labels (PIT FIX bug #2)
    print(f"\n  --- OOS prediction expert={expert_name} seed={seed} ---")
    X_seq_final, y_seq_final2 = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final2 = dates[SEQ_LEN - 1:]
    regime_seq_final2 = regime_arr[SEQ_LEN - 1:]
    y_valid_seq_final2 = y_valid_mask[SEQ_LEN - 1:]
    # OOS mask: in [OOS_START, OOS_END] AND label resolved (ret_q126 NOT NA)
    oos_mask = (dates_seq_final2 >= np.datetime64(OOS_START)) & \
               (dates_seq_final2 <= np.datetime64(OOS_END)) & \
               y_valid_seq_final2
    print(f"    OOS mask: n_valid={int(oos_mask.sum())} "
          f"(unresolved excluded={int(((dates_seq_final2 >= np.datetime64(OOS_START)) & (dates_seq_final2 <= np.datetime64(OOS_END))).sum() - oos_mask.sum())})")
    X_oos_t = torch.tensor(X_seq_final[oos_mask], dtype=torch.float32).to(DEVICE)

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

    oos_y = y_seq_final2[oos_mask]
    oos_dates = dates_seq_final2[oos_mask]
    oos_regime = regime_seq_final2[oos_mask]

    # Overall OOS PR (sanity, not the final metric — gating decides)
    overall_pr = pr_auc(oop, oos_y)
    overall_ic = ic_spearman(oop, oos_y)

    # Per-expert "in-regime" OOS PR (only on its own regime dates)
    if expert_name in FEASIBLE_REGIMES:
        in_reg = (oos_regime == expert_name)
        in_reg_pr = pr_auc(oop[in_reg], oos_y[in_reg]) if in_reg.sum() >= 30 else float("nan")
        in_reg_ic = ic_spearman(oop[in_reg], oos_y[in_reg]) if in_reg.sum() >= 30 else float("nan")
    else:
        in_reg = np.ones(len(oop), dtype=bool)
        in_reg_pr = overall_pr
        in_reg_ic = overall_ic

    elapsed = time.time() - t_start
    print(f"\n  [{expert_name}/{target_col}/seed{seed}] "
          f"overall OOS PR-AUC: {overall_pr:.4f} (IC: {overall_ic:.4f})")
    print(f"  [{expert_name}/{target_col}/seed{seed}] "
          f"in-regime OOS PR-AUC: {in_reg_pr:.4f} (n={int(in_reg.sum())}, "
          f"IC: {in_reg_ic:.4f}) | elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    file_name = f"predictions_expert_{expert_name}_seed{seed}_{target_col}.parquet"
    df = pd.DataFrame({
        "Date": oos_dates,
        "p_expert": oop,
        "y": oos_y,
        "regime": oos_regime,
        "split": "oos",
        "target": target_col,
        "expert": expert_name,
        "seed": int(seed),
    })
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")

    del final_model
    if DEVICE.type == "cuda":
        torch.cuda.empty_cache()

    return dict(
        expert=expert_name,
        target=target_col,
        seed=int(seed),
        overall_oos_pr=overall_pr,
        overall_oos_ic=overall_ic,
        in_regime_oos_pr=in_reg_pr,
        in_regime_oos_ic=in_reg_ic,
        avg_best_epoch=avg_best_ep,
        per_fold=fold_results,
        final_train=final_res,
        elapsed_sec=elapsed,
        gpu_mem_peak_mb=mem_peak_mb,
        n_params=final_res["n_params"],
        oos_dates=oos_dates,
        oos_pred=oop,
        oos_y=oos_y,
        oos_regime=oos_regime,
    )


def build_gating_weighted_ensemble(per_expert_results, target_col):
    """
    Hard-routing gating:
      regime_t == BULL    → 100% BULL expert
      regime_t == NORMAL  → 100% NORMAL expert
      regime_t == CAUTION → 100% FULL expert
      regime_t == CRISIS  → 100% FULL expert
      regime_t == UNKNOWN → 100% FULL expert (safety)

    Per-seed gating ensemble: ensemble[date] = expert_pred[gate[regime[date]]][date]
    Across seeds: 5-seed mean.
    """
    seeds = sorted({r["seed"] for r in per_expert_results.values()
                    if r is not None})
    if len(seeds) == 0:
        raise RuntimeError("no successful expert run to ensemble")

    # Align: all experts × all seeds share OOS dates (same v5e panel)
    base = next(iter([v for v in per_expert_results.values() if v is not None]))
    ref_dates = pd.to_datetime(base["oos_dates"])
    ref_y = base["oos_y"]
    ref_regime = base["oos_regime"]

    # Sanity: all expert × seed share dates / y / regime
    for k, r in per_expert_results.items():
        if r is None:
            continue
        rd = pd.to_datetime(r["oos_dates"])
        if len(rd) != len(ref_dates) or not (rd == ref_dates).all():
            raise RuntimeError(f"date mismatch at {k}")
        if not np.array_equal(r["oos_y"], ref_y):
            raise RuntimeError(f"y mismatch at {k}")
        if not np.array_equal(r["oos_regime"], ref_regime):
            raise RuntimeError(f"regime mismatch at {k}")

    # Build per-seed gating ensemble
    per_seed_gating_preds = {}
    for s in seeds:
        bull_pred = per_expert_results.get(("BULL", s), {}).get("oos_pred") if ("BULL", s) in per_expert_results else None
        normal_pred = per_expert_results.get(("NORMAL", s), {}).get("oos_pred") if ("NORMAL", s) in per_expert_results else None
        full_pred = per_expert_results.get(("FULL", s), {}).get("oos_pred") if ("FULL", s) in per_expert_results else None

        if full_pred is None:
            print(f"  [WARN] seed={s} FULL expert missing — cannot gate; using BULL/NORMAL only")
            full_pred = np.full(len(ref_dates), np.nan)
        if bull_pred is None:
            bull_pred = full_pred.copy()
        if normal_pred is None:
            normal_pred = full_pred.copy()

        gating = np.where(ref_regime == "BULL", bull_pred,
                  np.where(ref_regime == "NORMAL", normal_pred,
                          full_pred))
        per_seed_gating_preds[s] = gating

    # 5-seed mean ensemble
    gating_matrix = np.stack([per_seed_gating_preds[s] for s in seeds], axis=0)
    mean_gating = gating_matrix.mean(axis=0)
    per_date_std = gating_matrix.std(axis=0, ddof=0)

    mean_pr = pr_auc(mean_gating, ref_y.astype(np.float64))
    mean_ic = ic_spearman(mean_gating, ref_y.astype(np.float64))

    # Save mean ensemble
    df_mean = pd.DataFrame({
        "Date": ref_dates.values,
        "p_moe_mean": mean_gating,
        "p_per_seed_std": per_date_std,
        "y": ref_y,
        "regime": ref_regime,
        "split": "oos",
        "target": target_col,
        "n_seeds": int(len(seeds)),
    })
    df_mean.to_parquet(OUT / f"predictions_moe_mean_{target_col}.parquet", index=False)
    print(f"  [moe mean prediction] Saved: {OUT}/predictions_moe_mean_{target_col}.parquet")

    # Per-seed PR audit
    per_seed_pr = {s: pr_auc(per_seed_gating_preds[s], ref_y.astype(np.float64))
                   for s in seeds}
    per_seed_ic = {s: ic_spearman(per_seed_gating_preds[s], ref_y.astype(np.float64))
                   for s in seeds}

    audit = dict(
        target=target_col,
        n_seeds=int(len(seeds)),
        seeds_used=seeds,
        n_obs=int(len(ref_dates)),
        n_events=int(ref_y.sum()),
        per_seed_gating_pr_auc={int(s): round(per_seed_pr[s], 6) for s in seeds},
        per_seed_gating_ic={int(s): round(per_seed_ic[s], 6) for s in seeds},
        per_seed_pr_mean=round(float(np.mean(list(per_seed_pr.values()))), 6),
        per_seed_pr_std=round(float(np.std(list(per_seed_pr.values()), ddof=1)), 6)
                          if len(per_seed_pr) > 1 else 0.0,
        per_seed_pr_min=round(float(np.min(list(per_seed_pr.values()))), 6),
        per_seed_pr_max=round(float(np.max(list(per_seed_pr.values()))), 6),
        per_seed_pr_range=round(float(np.max(list(per_seed_pr.values())) -
                                       np.min(list(per_seed_pr.values()))), 6),
        moe_mean_prediction_pr_auc=round(float(mean_pr), 6),
        moe_mean_prediction_ic=round(float(mean_ic), 6),
        per_date_std_mean=round(float(per_date_std.mean()), 6),
        per_date_std_max=round(float(per_date_std.max()), 6),
        gating_logic="HARD: BULL→BULL, NORMAL→NORMAL, CAUTION→FULL, CRISIS→FULL, UNKNOWN→FULL",
    )
    return audit


if __name__ == "__main__":
    print("=" * 70)
    print(f"[Cycle 56B — MoE per Regime PatchTST v5e q126]")
    print(f"[Seeds: {SEEDS} / Targets: {TARGETS} / Experts: {EXPERTS}]")
    print(f"[Folds: 5 / Architecture: 53H mirror]")
    print("=" * 70)

    cycle_start = time.time()
    all_results = {}  # all_results[target][(expert, seed)] = result dict
    for tgt in TARGETS:
        all_results[tgt] = {}

    # Load data ONCE per target
    data_cache = {}
    for tgt in TARGETS:
        X_full, y_full, y_valid_mask, dates, regime_arr, feature_cols = prepare_data_full(tgt)
        data_cache[tgt] = (X_full, y_full, y_valid_mask, dates, regime_arr, feature_cols)
        print(f"\n[Data loaded] target={tgt} X.shape={X_full.shape} "
              f"y_valid_count={int(y_valid_mask.sum())} "
              f"dates=[{pd.Timestamp(dates[0]).date()}..{pd.Timestamp(dates[-1]).date()}]")

    # Outer loop: target × expert × seed
    for tgt in TARGETS:
        X_full, y_full, y_valid_mask, dates, regime_arr, _ = data_cache[tgt]
        for expert in EXPERTS:
            for seed in SEEDS:
                r = run_expert_walkforward(tgt, expert, seed,
                                            X_full, y_full, y_valid_mask,
                                            dates, regime_arr)
                if r is not None:
                    all_results[tgt][(expert, seed)] = r

    cycle_elapsed = time.time() - cycle_start
    print(f"\n[Cycle 56B] Expert runs DONE. Total elapsed: {cycle_elapsed:.1f}s ({cycle_elapsed/60:.1f} min)")

    # Build MoE gating ensemble per target
    print("\n" + "=" * 70)
    print("[MoE gating-weighted ensemble per target]")
    print("=" * 70)

    audit_per_target = {}
    for tgt in TARGETS:
        print(f"\n  --- {tgt} ---")
        audit = build_gating_weighted_ensemble(all_results[tgt], tgt)
        audit_per_target[tgt] = audit

    # Summary printout
    print("\n" + "=" * 70)
    print("[Cycle 56B SUMMARY — MoE per Regime]")
    print("=" * 70)
    for tgt in TARGETS:
        au = audit_per_target[tgt]
        print(f"\n  {tgt}:")
        print(f"    Per-seed MoE PR-AUC: " +
              "  ".join([f"seed{s}={au['per_seed_gating_pr_auc'][s]:.4f}" for s in SEEDS
                         if s in au['per_seed_gating_pr_auc']]))
        print(f"    Mean: {au['per_seed_pr_mean']:.4f}  std={au['per_seed_pr_std']:.4f}  "
              f"range={au['per_seed_pr_range']:.4f}")
        print(f"    5-seed MEAN ensemble PR-AUC: {au['moe_mean_prediction_pr_auc']:.4f}  "
              f"IC={au['moe_mean_prediction_ic']:.4f}")

    # Per-fold + diagnostics dump
    per_fold_path = OUT / "per_fold_diagnostics.json"

    def serialize_seed_result(r):
        return {k: v for k, v in r.items()
                if k not in ("oos_dates", "oos_pred", "oos_y", "oos_regime")}

    per_fold = {
        "cycle": "56B_moe_per_regime_patchtst_v5e_q126",
        "validation_strategy": "walk_forward_expanding_5_fold_CV_per_expert",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date())},
        "feature_panel": "feature_panel_v5e_q126_usmacro.parquet (74 features)",
        "regime_source": "outputs/01_data/regime_daily_lag1.parquet (M4×AR×R05 inherit)",
        "seeds": SEEDS,
        "targets": TARGETS,
        "experts": EXPERTS,
        "feasibility": {"FEASIBLE": list(FEASIBLE_REGIMES),
                        "INFEASIBLE_fallback_to_FULL": ["CAUTION", "CRISIS"]},
        "min_train_days": MIN_TRAIN_DAYS,
        "min_train_bear": MIN_TRAIN_BEAR,
        "per_expert_seed_results": {
            tgt: {f"{e}_seed{s}": serialize_seed_result(all_results[tgt][(e, s)])
                  for (e, s) in all_results[tgt].keys()}
            for tgt in TARGETS
        },
    }
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"\n[Per-fold diagnostics] Saved: {per_fold_path}")

    # MoE audit summary
    moe_audit_path = OUT / "moe_audit.json"
    moe_audit = {
        "cycle": "56B_moe_per_regime_patchtst_v5e_q126",
        "audit_type": "MoE_per_regime_gating",
        "purpose": "Test regime-conditional experts (BULL/NORMAL) + FULL fallback (CAUTION/CRISIS) "
                    "with hard-routing gating; compare vs 53H baseline 0.4012",
        "regime_detector_source": "outputs/01_data/regime_daily_lag1.parquet",
        "regime_detector_pit": "M4×AR×R05 production overlay (already t-1 lagged) + additional "
                                "+1 day lag in roll join",
        "n_features": 74,
        "seeds": SEEDS,
        "n_seeds": len(SEEDS),
        "experts": EXPERTS,
        "feasibility_decision": {
            "FEASIBLE_regimes": list(FEASIBLE_REGIMES),
            "INFEASIBLE_regimes_fallback": ["CAUTION", "CRISIS"],
            "rationale_train_data_audit": {
                "BULL": "1233d / 136 bear (FEASIBLE)",
                "NORMAL": "1664d / 252 bear (FEASIBLE)",
                "CAUTION": "61d / 0 bear (INFEASIBLE — 0 events)",
                "CRISIS": "21d / 1 bear (INFEASIBLE — sample too small)"
            },
            "fallback_logic": "CAUTION/CRISIS dates route 100% to FULL expert (53H baseline mirror)"
        },
        "gating_strategy": "HARD_ROUTING (one-hot from regime_t)",
        "patchtst_hparams": {
            "patch_size": PATCH_SIZE, "patch_stride": PATCH_STRIDE,
            "d_model": PT_D_MODEL, "nhead": PT_NHEAD, "n_layers": PT_NLAYERS,
            "ff_dim": PT_D_MODEL * PT_FF_MULT, "dropout": PT_DROPOUT,
            "attn_dropout": PT_ATTN_DROPOUT,
            "weight_decay": PT_WEIGHT_DECAY, "lr": PT_LR,
        },
        "training_common": {
            "batch_size": BATCH_SIZE, "max_epochs": MAX_EPOCHS,
            "early_stop_patience": EARLY_STOP_PATIENCE,
            "early_stop_min_delta": EARLY_STOP_MIN_DELTA,
            "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
            "mixed_precision_amp": USE_AMP,
            "gpu_mem_fraction": 0.20 if DEVICE.type == "cuda" else None,
        },
        "audit_per_target": audit_per_target,
        "baseline_53H_seed42": {"y_tail_q126": 0.4012, "y_tail_q15": 0.2082,
                                  "note": "53H baseline uses leaky-PIT (no purge + unresolved-y included as 0). MoE uses strict-PIT (purged CV + y_valid_mask). Direct compare is incomplete; the strict-PIT 'fair 53H baseline' is the FULL expert's OOS PR-AUC computed within this cycle."},
        "pit_fixes_applied_2026_05_21": {
            "bug_1_purged_kfold_cv": "train_idx requires t + H_business_days < valid_start (PIT FIX)",
            "bug_2_unresolved_y_exclusion": "y_valid_mask = ret_q126 NOT NA (train/valid/OOS all exclude unresolved)",
            "codex_review_log": "outputs/04_evaluation/cycle56b_code_review_log.md"
        },
        "stability_thresholds": {
            "STABLE_std_lt": 0.02,
            "MODERATE_std_max": 0.05,
            "UNSTABLE_std_gt": 0.05,
        },
        "total_elapsed_sec": round(cycle_elapsed, 1),
    }
    with moe_audit_path.open("w") as f:
        json.dump(moe_audit, f, indent=2, default=str)
    print(f"[MoE audit] Saved: {moe_audit_path}")

    print("\n" + "=" * 70)
    print("[Cycle 56B Python DONE — Run scripts/145_moe_aggregate.R next]")
    print("=" * 70)
