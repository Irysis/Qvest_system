#!/usr/bin/env python3
"""
111_5way_retrain_v3i_timemixer.py — Cycle 49B Architecture Pivot (TimeMixer + N-BEATS)

Mandate (Cycle 49B):
  Cycle 45E verdict: N-BEATS 0.5479 PROVEN winner / PatchTST 0.3256 inferior
  → Pivot PatchTST → TimeMixer (Wang et al. ICLR 2024)
  → Retain N-BEATS (Oreshkin et al. ICLR 2019) — Cycle 45E proven

Hypothesis:
  TimeMixer multi-scale decomposable mixing > patch-wise attention for 21d short-horizon
  Multi-scale (3-scale 21d/10d/5d) + seasonal-trend decomp + cross-scale mixing
  MLP-based (no attention overhead), efficient on small data
  Reference: github.com/kwuking/TimeMixer

Walk-forward 5-fold CV retain (45D/E pattern):
  Fold 1: TRAIN 1995-2007 / VALID 2008-2009 (Lehman)
  Fold 2: TRAIN 1995-2009 / VALID 2010-2011
  Fold 3: TRAIN 1995-2011 / VALID 2012-2013
  Fold 4: TRAIN 1995-2013 / VALID 2014-2015
  Fold 5: TRAIN 1995-2015 / VALID 2016-2017
  Final: TRAIN 1995-2015, epochs = avg best_epoch from 5 folds
  OOS: 2018-2026

Input:
  outputs/01_data/feature_panel_v1_3.parquet (69 features)
  outputs/02_targets/targets_full.parquet

Output:
  outputs/03_models/v3i_timemixer/predictions_timemixer_y_tail_q15.parquet
  outputs/03_models/v3i_timemixer/predictions_timemixer_y_onset.parquet
  outputs/03_models/v3i_timemixer/predictions_nbeats_y_tail_q15.parquet
  outputs/03_models/v3i_timemixer/predictions_nbeats_y_onset.parquet
  outputs/03_models/v3i_timemixer/per_fold_diagnostics.json
  outputs/04_evaluation/5way_retrain_v3i_timemixer_python_diag.json
"""

import sys
import math
import time
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
OUT = WS / "outputs/03_models/v3i_timemixer"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 49B Python] Device: {DEVICE}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.30, device=0)
        print(f"[Cycle 49B] CUDA memory fraction set to 0.30 (parallel cycles 48A+48B)")
    except Exception as e:
        print(f"[Cycle 49B] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 49B] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

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

# ============================================================================
# TimeMixer hyperparameters (Wang et al. ICLR 2024)
# Reference: github.com/kwuking/TimeMixer
# ============================================================================
TM_N_SCALES = 3           # 21d / 10d / 5d via avg-pool downsampling
TM_HIDDEN = 128
TM_N_LAYERS = 2           # PDM block count
TM_DROPOUT = 0.30
TM_KERNEL_TREND = 5       # moving avg kernel for trend extraction (must be odd)
TM_WEIGHT_DECAY = 5e-3
TM_LR = 1e-3

# ============================================================================
# N-BEATS Generic hyperparameters (Oreshkin et al. ICLR 2019) — Cycle 45E retain
# ============================================================================
NB_N_STACKS = 5
NB_N_BLOCKS_PER_STACK = 3
NB_HIDDEN = 256
NB_DROPOUT = 0.30
NB_WEIGHT_DECAY = 5e-3
NB_LR = 1e-3
NB_THETA_DIM = 32

# ============================================================================
# Training infra (45D/E retain)
# ============================================================================
BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

torch.manual_seed(42)
np.random.seed(42)


# ============================================================================
# TimeMixer: Multi-scale Decomposable Mixing for Time Series Forecasting
# Wang et al. ICLR 2024
# ============================================================================
class MovingAvg(nn.Module):
    """Moving average kernel for trend extraction (causal padding)."""
    def __init__(self, kernel_size):
        super().__init__()
        self.kernel_size = kernel_size
        self.avg = nn.AvgPool1d(kernel_size=kernel_size, stride=1, padding=0)

    def forward(self, x):
        # x: (B, L, C)
        # Causal padding: replicate first value to avoid future leakage
        front = x[:, 0:1, :].repeat(1, (self.kernel_size - 1) // 2, 1)
        end = x[:, -1:, :].repeat(1, (self.kernel_size - 1) // 2, 1)
        x_padded = torch.cat([front, x, end], dim=1)
        # AvgPool1d expects (B, C, L) → permute, pool, permute back
        x_padded = x_padded.permute(0, 2, 1)
        x_trend = self.avg(x_padded).permute(0, 2, 1)
        return x_trend


class SeriesDecomp(nn.Module):
    """Decompose series into seasonal + trend (subtraction style)."""
    def __init__(self, kernel_size):
        super().__init__()
        self.moving_avg = MovingAvg(kernel_size=kernel_size)

    def forward(self, x):
        trend = self.moving_avg(x)
        seasonal = x - trend
        return seasonal, trend


class MultiScaleSeasonMixing(nn.Module):
    """
    Bottom-up mixing: from fine-grained (longer) to coarse-grained (shorter) seasonal.
    Each scale processed via MLP, fine-grained 정보 → coarse-grained.
    """
    def __init__(self, seq_lens, hidden_dim):
        super().__init__()
        self.seq_lens = seq_lens  # [21, 10, 5] (fine-grained 첫번째)
        self.down_proj = nn.ModuleList([
            nn.Sequential(
                nn.Linear(seq_lens[i], seq_lens[i + 1]),
                nn.GELU(),
                nn.Linear(seq_lens[i + 1], seq_lens[i + 1]),
            )
            for i in range(len(seq_lens) - 1)
        ])

    def forward(self, season_list):
        # season_list: [(B, L_i, C)] for i in scales
        out = [season_list[0]]
        for i in range(len(season_list) - 1):
            # transpose to (B, C, L) for linear over time
            prev = out[-1].permute(0, 2, 1)        # (B, C, L_i)
            mixed = self.down_proj[i](prev)        # (B, C, L_{i+1})
            mixed = mixed.permute(0, 2, 1)         # (B, L_{i+1}, C)
            # combine with current scale season
            combined = mixed + season_list[i + 1]
            out.append(combined)
        return out


class MultiScaleTrendMixing(nn.Module):
    """
    Top-down mixing: from coarse-grained (shorter) to fine-grained (longer) trend.
    Macro-trend 정보 → micro-trend.
    """
    def __init__(self, seq_lens, hidden_dim):
        super().__init__()
        self.seq_lens = seq_lens
        # reversed: start from coarsest (smallest L)
        self.up_proj = nn.ModuleList([
            nn.Sequential(
                nn.Linear(seq_lens[i + 1], seq_lens[i]),
                nn.GELU(),
                nn.Linear(seq_lens[i], seq_lens[i]),
            )
            for i in range(len(seq_lens) - 1)
        ])

    def forward(self, trend_list):
        # trend_list: [(B, L_i, C)] for i in scales (fine→coarse)
        # Walk from coarsest backwards
        out = [None] * len(trend_list)
        out[-1] = trend_list[-1]
        for i in range(len(trend_list) - 2, -1, -1):
            prev = out[i + 1].permute(0, 2, 1)    # (B, C, L_{i+1})
            mixed = self.up_proj[i](prev)          # (B, C, L_i)
            mixed = mixed.permute(0, 2, 1)         # (B, L_i, C)
            combined = mixed + trend_list[i]
            out[i] = combined
        return out


class PastDecomposableMixing(nn.Module):
    """
    PDM block: each scale decomposed into seasonal + trend,
    then mixed across scales (seasonal bottom-up, trend top-down).
    """
    def __init__(self, seq_lens, hidden_dim, dropout, kernel_trend):
        super().__init__()
        self.decomp_blocks = nn.ModuleList([
            SeriesDecomp(kernel_trend) for _ in seq_lens
        ])
        self.season_mixer = MultiScaleSeasonMixing(seq_lens, hidden_dim)
        self.trend_mixer = MultiScaleTrendMixing(seq_lens, hidden_dim)
        self.dropouts = nn.ModuleList([
            nn.Dropout(dropout) for _ in seq_lens
        ])
        self.layer_norms = nn.ModuleList([
            nn.LayerNorm(hidden_dim) for _ in seq_lens  # over feature dim
        ])

    def forward(self, x_list):
        # x_list: [(B, L_i, hidden_dim)] for i in scales
        season_list = []
        trend_list = []
        for i, x in enumerate(x_list):
            s, t = self.decomp_blocks[i](x)
            season_list.append(s)
            trend_list.append(t)

        season_mixed = self.season_mixer(season_list)
        trend_mixed = self.trend_mixer(trend_list)

        out = []
        for i in range(len(x_list)):
            combined = season_mixed[i] + trend_mixed[i]
            combined = self.dropouts[i](combined)
            combined = self.layer_norms[i](combined + x_list[i])  # residual + LN
            out.append(combined)
        return out


class TimeMixerClassifier(nn.Module):
    """
    TimeMixer (Wang et al. ICLR 2024) — Multi-scale decomposable mixing for classification.

    Pipeline:
      input  (B, L=21, C=69) → enbed to hidden_dim
      downsample to 3 scales: L=21 (fine), L=10, L=5 (coarse) via avg pool
      PDM stack (n_layers): each block decomposes seasonal+trend per scale + mixes across scales
      pool: mean over time per scale → concat scales → MLP head → logit
    """

    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 n_scales=TM_N_SCALES, hidden=TM_HIDDEN,
                 n_layers=TM_N_LAYERS, dropout=TM_DROPOUT,
                 kernel_trend=TM_KERNEL_TREND):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.n_scales = n_scales
        self.hidden = hidden

        # Multi-scale lengths: 21 → 10 → 5 (downsample by ~2x)
        self.seq_lens = []
        cur = seq_len
        for s in range(n_scales):
            self.seq_lens.append(cur)
            cur = max(2, (cur + 1) // 2)
        # seq_lens example: [21, 11, 6]
        # but we want 21/10/5 → manually adjust
        if seq_len == 21 and n_scales == 3:
            self.seq_lens = [21, 10, 5]

        # Embedding: per-step feature → hidden_dim
        self.embed = nn.Linear(input_dim, hidden)
        self.embed_dropout = nn.Dropout(dropout)

        # Downsample layers (linear over time per channel)
        self.downsamplers = nn.ModuleList([
            nn.Sequential(
                nn.Linear(self.seq_lens[i], self.seq_lens[i + 1]),
                nn.GELU(),
            )
            for i in range(n_scales - 1)
        ])

        # PDM blocks
        self.pdm_blocks = nn.ModuleList([
            PastDecomposableMixing(self.seq_lens, hidden, dropout, kernel_trend)
            for _ in range(n_layers)
        ])

        # Per-scale projection to scalar (mean pool + linear)
        self.scale_heads = nn.ModuleList([
            nn.Sequential(
                nn.Linear(hidden, hidden // 2),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(hidden // 2, 32),
            )
            for _ in range(n_scales)
        ])

        # Final classification head
        self.final_head = nn.Sequential(
            nn.Linear(32 * n_scales, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, 1),
        )

    def downsample_scales(self, x):
        # x: (B, L, hidden)
        out_list = [x]
        for i in range(self.n_scales - 1):
            prev = out_list[-1].permute(0, 2, 1)   # (B, hidden, L_i)
            next_x = self.downsamplers[i](prev)    # (B, hidden, L_{i+1})
            next_x = next_x.permute(0, 2, 1)       # (B, L_{i+1}, hidden)
            out_list.append(next_x)
        return out_list

    def forward(self, x):
        # x: (B, L=21, C=69)
        B = x.size(0)
        # Embed each time step
        x_emb = self.embed(x)                       # (B, L, hidden)
        x_emb = self.embed_dropout(x_emb)

        # Multi-scale downsample
        scale_list = self.downsample_scales(x_emb)   # list of (B, L_i, hidden)

        # PDM blocks
        for block in self.pdm_blocks:
            scale_list = block(scale_list)

        # Per-scale pooling + projection
        scale_feats = []
        for i, x_s in enumerate(scale_list):
            pooled = x_s.mean(dim=1)                 # (B, hidden)
            feat = self.scale_heads[i](pooled)       # (B, 32)
            scale_feats.append(feat)

        # Concat scales
        combined = torch.cat(scale_feats, dim=-1)    # (B, 32 * n_scales)
        logit = self.final_head(combined).squeeze(-1)
        return logit


# ============================================================================
# N-BEATS Generic (Oreshkin et al. ICLR 2019) — Cycle 45E retain
# ============================================================================
class NBeatsBlock(nn.Module):
    def __init__(self, input_dim, hidden=NB_HIDDEN, theta_dim=NB_THETA_DIM,
                 dropout=NB_DROPOUT, n_layers=4):
        super().__init__()
        layers = []
        for i in range(n_layers):
            in_dim = input_dim if i == 0 else hidden
            layers.append(nn.Linear(in_dim, hidden))
            layers.append(nn.ReLU(inplace=True))
            layers.append(nn.Dropout(dropout))
        self.fc_stack = nn.Sequential(*layers)
        self.theta_b = nn.Linear(hidden, theta_dim)
        self.backcast_linear = nn.Linear(theta_dim, input_dim)
        self.theta_f = nn.Linear(hidden, theta_dim)
        self.forecast_linear = nn.Linear(theta_dim, 1)

    def forward(self, x):
        h = self.fc_stack(x)
        b = self.backcast_linear(self.theta_b(h))
        f = self.forecast_linear(self.theta_f(h)).squeeze(-1)
        return b, f


class NBeatsClassifier(nn.Module):
    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 n_stacks=NB_N_STACKS, n_blocks=NB_N_BLOCKS_PER_STACK,
                 hidden=NB_HIDDEN, dropout=NB_DROPOUT,
                 theta_dim=NB_THETA_DIM):
        super().__init__()
        self.flat_dim = seq_len * input_dim
        self.n_stacks = n_stacks
        self.n_blocks = n_blocks

        self.blocks = nn.ModuleList([
            NBeatsBlock(self.flat_dim, hidden=hidden, theta_dim=theta_dim,
                        dropout=dropout, n_layers=4)
            for _ in range(n_stacks * n_blocks)
        ])

        n_block_total = n_stacks * n_blocks
        self.final_mlp = nn.Sequential(
            nn.Linear(n_block_total + 2, 64),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(64, 32),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(32, 1),
        )

    def forward(self, x):
        B = x.size(0)
        x_flat = x.reshape(B, -1)
        residual = x_flat
        forecast_sum = torch.zeros(B, device=x.device)
        forecasts = []
        for block in self.blocks:
            b, f = block(residual)
            residual = residual - b
            forecast_sum = forecast_sum + f
            forecasts.append(f)
        forecasts_cat = torch.stack(forecasts, dim=-1)
        res_norm = residual.norm(dim=-1, keepdim=True) / math.sqrt(self.flat_dim)
        res_mean = residual.mean(dim=-1, keepdim=True)
        agg_input = torch.cat([forecasts_cat, res_norm, res_mean], dim=-1)
        logit = self.final_mlp(agg_input).squeeze(-1)
        return 0.5 * logit + 0.5 * forecast_sum


# ============================================================================
# Helpers (45D/E pattern)
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
    def lr_lambda(step):
        if step < warmup_steps:
            return float(step + 1) / float(max(1, warmup_steps))
        progress = float(step - warmup_steps) / float(max(1, total_steps - warmup_steps))
        progress = min(1.0, progress)
        return 0.1 + 0.9 * 0.5 * (1.0 + math.cos(math.pi * progress))
    return LambdaLR(optimizer, lr_lambda)


def prepare_data_full(target_col):
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


# ============================================================================
# Single-fold or final-train routine
# ============================================================================
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
        valid_idx = None
        X_valid_t = None
        y_valid_t = None
        valid_bear = -1

    pos_w_value = float(min((y_train_t == 0).sum() / max((y_train_t == 1).sum().item(), 1), 8.0))
    pos_w = torch.tensor([pos_w_value], device=DEVICE)

    train_loader = DataLoader(TensorDataset(X_train_t, y_train_t),
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
                              num_workers=NUM_WORKERS)

    if model_name == "TIMEMIXER":
        wd = TM_WEIGHT_DECAY; lr = TM_LR
    else:  # NBEATS
        wd = NB_WEIGHT_DECAY; lr = NB_LR

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
          f" pos_w={pos_w_value:.2f} target_ep={target_epochs} params={n_params:,}")

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
        model=model_name,
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


# ============================================================================
# Main: Walk-forward 5-fold CV + Final Training + OOS evaluation
# ============================================================================
def run_walkforward_for(model_class, model_name, target_col):
    print("\n" + "=" * 70)
    print(f"[Cycle 49B walk-forward] {model_name} target: {target_col}")
    print("=" * 70)
    t_start = time.time()

    X_full, y_full, dates, feature_cols = prepare_data_full(target_col)

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
    print(f"\n  [Avg best_epoch across {len(valid_eps)} folds] = {avg_best_ep}")
    print(f"  [Per-fold best_epoch] = {[r['best_epoch'] for r in fold_results]}")
    print(f"  [Per-fold best_valid_pr] = {[r['best_valid_pr'] for r in fold_results]}")

    print(f"\n  --- Final training: TRAIN 1995-2015 / epochs={avg_best_ep} (no valid, no early stop) ---")
    final_model, Xs_final, dates_seq_final, y_seq_final, final_train_res = train_one_window(
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
        print(f"  GPU memory peak: {mem_peak_mb:.1f} MB")
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    col_name = "p_timemixer" if model_name == "TIMEMIXER" else "p_nbeats"
    file_stub = "timemixer" if model_name == "TIMEMIXER" else "nbeats"
    df = pd.DataFrame({
        "Date": dates_seq_final2[oos_idx],
        col_name: oop, "y": oos_y,
        "split": "oos", "target": target_col,
    })
    file_name = f"predictions_{file_stub}_{target_col}.parquet"
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")

    del final_model
    if DEVICE.type == "cuda":
        torch.cuda.empty_cache()

    return dict(
        model=model_name,
        target=target_col,
        oos_pr=oos_pr_v,
        avg_best_epoch=avg_best_ep,
        per_fold=fold_results,
        final_train=final_train_res,
        elapsed_sec=elapsed,
        gpu_mem_peak_mb=mem_peak_mb,
        n_params=final_train_res["n_params"],
    )


if __name__ == "__main__":
    print("=" * 70)
    print("[Cycle 49B Architecture Pivot — TimeMixer + N-BEATS]")
    print("[v1.3 baseline 69 features, walk-forward 5-fold CV, patience 15 retain]")
    print("[TimeMixer: Wang et al. ICLR 2024 — multi-scale decomposable mixing]")
    print("[N-BEATS retain: Cycle 45E proven 0.5479]")
    print("[OOS window: 2018-2026]")
    print("=" * 70)

    results = {}

    # TimeMixer both targets
    results["timemixer_y_tail_q15"] = run_walkforward_for(TimeMixerClassifier, "TIMEMIXER", "y_tail_q15")
    results["timemixer_y_onset"] = run_walkforward_for(TimeMixerClassifier, "TIMEMIXER", "y_onset")

    # N-BEATS both targets
    results["nbeats_y_tail_q15"] = run_walkforward_for(NBeatsClassifier, "NBEATS", "y_tail_q15")
    results["nbeats_y_onset"] = run_walkforward_for(NBeatsClassifier, "NBEATS", "y_onset")

    print("\n" + "=" * 70)
    print("[Python Cycle 49B SUMMARY] TimeMixer + N-BEATS architecture pivot")
    print(f"  TimeMixer y_tail_q15: OOS={results['timemixer_y_tail_q15']['oos_pr']:.4f}  "
          f"avg_ep={results['timemixer_y_tail_q15']['avg_best_epoch']}")
    print(f"  TimeMixer y_onset:    OOS={results['timemixer_y_onset']['oos_pr']:.4f}  "
          f"avg_ep={results['timemixer_y_onset']['avg_best_epoch']}")
    print(f"  N-BEATS   y_tail_q15: OOS={results['nbeats_y_tail_q15']['oos_pr']:.4f}  "
          f"avg_ep={results['nbeats_y_tail_q15']['avg_best_epoch']}")
    print(f"  N-BEATS   y_onset:    OOS={results['nbeats_y_onset']['oos_pr']:.4f}  "
          f"avg_ep={results['nbeats_y_onset']['avg_best_epoch']}")
    print("=" * 70)

    # Cycle 45E baselines (PatchTST 0.3256 / N-BEATS 0.5479)
    CYC45E_PATCHTST_OOS = 0.3256
    CYC45E_NBEATS_OOS = 0.5479
    CYC45E_PATCHTST_EP = None  # to be loaded from py_diag if needed
    CYC45E_NBEATS_EP = None

    d_tm_pr = results["timemixer_y_tail_q15"]["oos_pr"] - CYC45E_PATCHTST_OOS
    d_nb_pr = results["nbeats_y_tail_q15"]["oos_pr"] - CYC45E_NBEATS_OOS

    print("\n[Architecture pivot verdict (y_tail_q15)]")
    print(f"  TimeMixer vs PatchTST (45E): 0.3256  →  {results['timemixer_y_tail_q15']['oos_pr']:.4f}  "
          f"(Δ_PR={d_tm_pr:+.4f})")
    print(f"  N-BEATS   vs N-BEATS  (45E): 0.5479  →  {results['nbeats_y_tail_q15']['oos_pr']:.4f}  "
          f"(Δ_PR={d_nb_pr:+.4f})")

    import json
    per_fold_path = OUT / "per_fold_diagnostics.json"
    per_fold = {
        "cycle": "49B_timemixer_pivot",
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date()),
                       "note": "fold 5 valid 2016-2017 제외하여 leakage 방지"},
        "results": {k: {**{kk: vv for kk, vv in v.items() if kk not in ("per_fold", "final_train")},
                        "per_fold": v["per_fold"],
                        "final_train": v["final_train"]}
                    for k, v in results.items()},
    }
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"\n[Per-fold diagnostics] Saved: {per_fold_path}")

    diag_path = EVAL_DIR / "5way_retrain_v3i_timemixer_python_diag.json"
    diag = {
        "cycle": "49B_timemixer_pivot",
        "baseline_v1_3_features": 69,
        "no_new_features": True,
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "architecture_pivot": {
            "patchtst_replaced_by": "TimeMixer (Wang et al. ICLR 2024, multi-scale decomposable mixing)",
            "nbeats_retained": "N-BEATS Generic (Oreshkin et al. ICLR 2019, Cycle 45E proven 0.5479)",
            "timemixer": {
                "n_scales": TM_N_SCALES,
                "seq_lens": [21, 10, 5],
                "hidden": TM_HIDDEN,
                "n_layers": TM_N_LAYERS,
                "dropout": TM_DROPOUT,
                "kernel_trend": TM_KERNEL_TREND,
                "weight_decay": TM_WEIGHT_DECAY,
                "lr": TM_LR,
                "rationale": "MLP-based multi-scale (no attention overhead), 21d short-horizon proven ICLR 2024",
            },
            "nbeats": {
                "n_stacks": NB_N_STACKS, "n_blocks_per_stack": NB_N_BLOCKS_PER_STACK,
                "hidden": NB_HIDDEN, "dropout": NB_DROPOUT,
                "theta_dim": NB_THETA_DIM,
                "weight_decay": NB_WEIGHT_DECAY, "lr": NB_LR,
            },
            "common": {
                "batch_size": BATCH_SIZE, "epochs": MAX_EPOCHS,
                "early_stop_patience": EARLY_STOP_PATIENCE,
                "early_stop_min_delta": EARLY_STOP_MIN_DELTA,
                "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
                "mixed_precision_amp": USE_AMP,
                "gpu_mem_fraction": 0.30 if DEVICE.type == "cuda" else None,
            },
        },
        "baseline_45e_oos_y_tail_q15": {
            "patchtst": CYC45E_PATCHTST_OOS,
            "nbeats": CYC45E_NBEATS_OOS,
        },
        "v3i_oos_y_tail_q15": {
            "timemixer": round(results["timemixer_y_tail_q15"]["oos_pr"], 4),
            "nbeats": round(results["nbeats_y_tail_q15"]["oos_pr"], 4),
            "timemixer_avg_ep": results["timemixer_y_tail_q15"]["avg_best_epoch"],
            "nbeats_avg_ep": results["nbeats_y_tail_q15"]["avg_best_epoch"],
        },
        "v3i_oos_y_onset": {
            "timemixer": round(results["timemixer_y_onset"]["oos_pr"], 4),
            "nbeats": round(results["nbeats_y_onset"]["oos_pr"], 4),
            "timemixer_avg_ep": results["timemixer_y_onset"]["avg_best_epoch"],
            "nbeats_avg_ep": results["nbeats_y_onset"]["avg_best_epoch"],
        },
        "delta_45e_to_49b_y_tail_q15": {
            "timemixer_vs_patchtst_pr": round(d_tm_pr, 4),
            "nbeats_vs_nbeats_pr": round(d_nb_pr, 4),
        },
        "model_params": {
            "timemixer": results["timemixer_y_tail_q15"]["n_params"],
            "nbeats": results["nbeats_y_tail_q15"]["n_params"],
        },
        "elapsed_sec": {
            "timemixer_y_tail_q15": results["timemixer_y_tail_q15"]["elapsed_sec"],
            "timemixer_y_onset": results["timemixer_y_onset"]["elapsed_sec"],
            "nbeats_y_tail_q15": results["nbeats_y_tail_q15"]["elapsed_sec"],
            "nbeats_y_onset": results["nbeats_y_onset"]["elapsed_sec"],
        },
        "gpu_mem_peak_mb": {
            "timemixer_y_tail_q15": results["timemixer_y_tail_q15"]["gpu_mem_peak_mb"],
            "nbeats_y_tail_q15": results["nbeats_y_tail_q15"]["gpu_mem_peak_mb"],
        },
        "per_fold_diagnostics_path": str(per_fold_path),
    }
    with diag_path.open("w") as f:
        json.dump(diag, f, indent=2, default=str)
    print(f"[Diagnostics] Saved: {diag_path}")
