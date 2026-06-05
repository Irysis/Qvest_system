#!/usr/bin/env python3
"""167_patchtst_strict_PIT_q15_template.py — Cycle 56A master template

Strict-PIT PatchTST **q15 (21-day forward)** reproduction with both Codex CRITICAL bug fixes
+ M6 phantom-0 guard + M7 publication-lag awareness (CFNAI/ICSA inherited from 55A panels — q15
horizon makes feature-side leakage less impactful per 55B Codex est. < 0.005 PR-AUC).

Differences vs Cycle 55A template (157_patchtst_strict_PIT_template.py):
  - TARGET = "y_tail_q15"  (vs y_tail_q126)
  - TARGET_HORIZON_DAYS = 21  (vs 126) — Codex Bug #1 purge horizon shortened
  - target_path = "targets_long_horizon_observable.parquet"  (vs buggy targets_long_horizon)
    rationale: M6 (Cycle 54D Phase 4) mandate — phantom-0 propagation cleaned for q15
  - SKIP_FOLDS_PER_TARGET = {} — q15 has n_bear ≥ 5 in all 5 folds (no fold skip)
  - Output naming: predictions_{cycle}_seed{S}_y_tail_q15.parquet
  - Output dir default: outputs/03_models/cycle56a_q15_strict_PIT

PIT FIX (inherited from 55A — Codex CRITICAL bugs fixed):
  - Bug #1: Purged k-fold CV via np.busday_offset(dates, 21, roll='forward') < valid_start
  - Bug #2: y_valid_mask = ret_q15.notna() — exclude unresolved labels

Strict determinism (54A FIXED inherit):
  - CUBLAS_WORKSPACE_CONFIG=:4096:8 (env), torch.use_deterministic_algorithms(True),
    cudnn.deterministic=True, cudnn.benchmark=False, per-seed torch.cuda.manual_seed_all

CLI: identical to 157 template (--cycle, --feature_panel, --n_features, --patch_size,
--d_model, --nhead, --nlayers, --stride, --output_dir, --gpu_fraction).
"""

import argparse
import sys
import os
import math
import time
import json
import warnings
from pathlib import Path
import numpy as np
import pandas as pd

# Strict determinism env BEFORE torch import
os.environ.setdefault("CUBLAS_WORKSPACE_CONFIG", ":4096:8")

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

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Strict determinism (54A FIXED inherit)
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
try:
    torch.use_deterministic_algorithms(True, warn_only=True)
except Exception as e:
    print(f"[strict-PIT q15 template] determinism flag failed: {e}")

# 5-seed multi-seed (54A/54C/55A inherit)
SEEDS = [42, 123, 456, 789, 1024]

# OOS window (53H mirror)
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")
FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# 5-fold walk-forward (53H exact mirror)
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

# q15 has n_bear ≥ 5 across ALL 5 folds (verified Cycle 56A pre-check, R audit).
# Unlike q126 where Fold3 had zero-events guard, q15 needs NO fold skip.
SKIP_FOLDS_PER_TARGET = {"y_tail_q15": []}

# Training hparams (53H exact mirror)
PT_FF_MULT = 4
PT_WEIGHT_DECAY = 5e-3
PT_LR = 1e-3
PT_DROPOUT = 0.30
PT_ATTN_DROPOUT = 0.15
PT_NHEAD_DEFAULT = 4
PT_NLAYERS_DEFAULT = 3
BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

# PIT FIX (Codex CRITICAL bug #1): Purged k-fold CV
ENABLE_PURGED_CV = True

# Target horizons — CYCLE 56A q15
TARGET = "y_tail_q15"
TARGET_HORIZON_DAYS = 21  # 21 trading days forward (q15 naming: q15=21d horizon, 15=15% tail quantile)

MIN_TRAIN_DAYS = 200
MIN_TRAIN_BEAR = 5


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


def set_seed(seed):
    """Strict determinism (54A FIXED pattern)."""
    import random
    random.seed(seed)
    torch.manual_seed(seed)
    np.random.seed(seed)
    if DEVICE.type == "cuda":
        torch.cuda.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)


def prepare_data(feature_panel_path, expected_n_features, target_col=TARGET):
    """
    Load feature panel + targets (CYCLE 56A: targets_long_horizon_observable.parquet).

    M6 phantom-0 mandate (Cycle 54D): observable file has NaN propagated where ret
    column is unresolved, ensuring train/valid/OOS exclude unresolved labels naturally.

    PIT FIX (Codex CRITICAL bug #2, 55A inherit):
      - y_valid_mask = ret_q15.notna() — q15 horizon (21d) resolved-only
    """
    feat = pd.read_parquet(feature_panel_path)
    horizon_col = target_col.replace("y_tail_", "ret_")  # ret_q15
    tgt_cols = ["Date", target_col, horizon_col]
    # CYCLE 56A: use observable (Cycle 54D Phase 4 M6 mandate)
    tgt = pd.read_parquet(TGT / "targets_long_horizon_observable.parquet")[tgt_cols]

    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])

    panel = feat.merge(tgt, on="Date", how="left")
    panel = panel.sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END]

    feature_cols = [c for c in panel.columns
                    if c not in ("Date", target_col, horizon_col)]
    assert len(feature_cols) == expected_n_features, \
        f"expected {expected_n_features} features, got {len(feature_cols)}"

    X = panel[feature_cols].values.astype(np.float32)
    y_raw = panel[target_col].fillna(0).values.astype(np.float32)
    # PIT FIX bug #2: y_valid_mask
    y_valid_mask = panel[horizon_col].notna().values
    dates = panel["Date"].values

    # M6 phantom-0 HARD assertion at load: any row with y_tail not-null but ret null?
    # (Codex 56A code review recommendation — assert vs warn — to fail-fast if someone
    #  accidentally points template at buggy targets_long_horizon.parquet)
    n_phantom = int((panel[horizon_col].isna() & panel[target_col].notna()).sum())
    assert n_phantom == 0, (
        f"M6 phantom-0 VIOLATION: {n_phantom} rows have {target_col} not-null but "
        f"{horizon_col} null. Check that target file is targets_long_horizon_observable.parquet "
        f"(NOT buggy targets_long_horizon.parquet)."
    )
    print(f"[prepare_data] M6 phantom-0 ASSERT PASS (0 rows with y not-null but ret null)")

    print(f"[prepare_data] n_total={len(y_raw)} "
          f"n_y_valid={int(y_valid_mask.sum())} n_y_unresolved={int((~y_valid_mask).sum())} "
          f"feat_panel={Path(feature_panel_path).name} n_feat={len(feature_cols)} "
          f"target={target_col} horizon_days={TARGET_HORIZON_DAYS}")
    return X, y_raw, y_valid_mask, dates, feature_cols


def standardize_for_window(X, dates, train_start, train_end, train_mask_extra=None):
    train_mask = (dates >= np.datetime64(train_start)) & (dates <= np.datetime64(train_end))
    if train_mask_extra is not None:
        train_mask = train_mask & train_mask_extra
    if train_mask.sum() < 30:
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


def train_one_window(X_full, y_full, y_valid_mask, dates,
                     train_start, train_end,
                     valid_start, valid_end,
                     patch_size, d_model, nhead, nlayers,
                     fixed_epochs=None, fold_label="", seed=42,
                     stride=None):
    set_seed(seed)

    # PIT FIX bug #2: y_valid_mask applies to standardization
    Xs = standardize_for_window(X_full, dates, train_start, train_end,
                                 train_mask_extra=y_valid_mask)
    X_seq, y_seq = make_sequences(Xs, y_full, SEQ_LEN)
    dates_seq = dates[SEQ_LEN - 1:]
    y_valid_seq = y_valid_mask[SEQ_LEN - 1:]

    # Train index
    in_train_window = (dates_seq >= np.datetime64(train_start)) & \
                       (dates_seq <= np.datetime64(train_end))
    train_idx = in_train_window & y_valid_seq

    # PIT FIX bug #1: Purged k-fold CV via busday_offset
    # CYCLE 56A: H = 21 (q15 horizon, vs 126 for q126)
    has_valid = (valid_start is not None) and (valid_end is not None)
    H = TARGET_HORIZON_DAYS
    purge_count = 0
    if has_valid and ENABLE_PURGED_CV and H > 0:
        valid_start_dt = np.datetime64(valid_start)
        train_offset = np.busday_offset(dates_seq.astype('datetime64[D]'),
                                         H, roll='forward')
        purge_mask = train_offset < valid_start_dt
        purge_count = int(train_idx.sum() - (train_idx & purge_mask).sum())
        train_idx = train_idx & purge_mask

    n_train = int(train_idx.sum())
    n_train_bear = int(y_seq[train_idx].sum())

    if has_valid:
        in_valid_window = (dates_seq >= np.datetime64(valid_start)) & \
                          (dates_seq <= np.datetime64(valid_end))
        valid_idx = in_valid_window & y_valid_seq
        n_valid = int(valid_idx.sum())
        n_valid_bear = int(y_seq[valid_idx].sum())
    else:
        valid_idx = None
        n_valid = 0
        n_valid_bear = 0

    if n_train < MIN_TRAIN_DAYS or n_train_bear < MIN_TRAIN_BEAR:
        print(f"    [SKIP {fold_label}/seed{seed}] n_train={n_train} "
              f"n_train_bear={n_train_bear} < MIN (purged={purge_count})")
        return None, None, None, None, dict(
            fold=fold_label, seed=int(seed),
            best_valid_pr=None, best_epoch=None, epochs_done=0,
            early_stop_ep=None, n_train=n_train, n_train_bear=n_train_bear,
            n_valid=n_valid, n_valid_bear=n_valid_bear,
            purged_train_count=purge_count,
            skipped=True, skip_reason="insufficient_train"
        )

    if has_valid and n_valid_bear < 5:
        print(f"    [SKIP {fold_label}/seed{seed}] n_valid_bear={n_valid_bear} < 5 "
              f"(purged={purge_count})")
        return None, None, None, None, dict(
            fold=fold_label, seed=int(seed),
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

    # 53H/54A pattern: stride = 1 if patch_size == 2 else 2 (unless overridden)
    if stride is None:
        stride = 1 if patch_size == 2 else 2

    model = PatchTSTClassifier(
        input_dim=X_train_t.shape[2],
        patch_size=patch_size, patch_stride=stride,
        d_model=d_model, nhead=nhead,
        num_layers=nlayers, ff_mult=PT_FF_MULT,
        dropout=PT_DROPOUT, attn_dropout=PT_ATTN_DROPOUT,
    ).to(DEVICE)
    n_params = sum(p.numel() for p in model.parameters() if p.requires_grad)

    optim = torch.optim.AdamW(model.parameters(), lr=PT_LR, weight_decay=PT_WEIGHT_DECAY)
    loss_fn = nn.BCEWithLogitsLoss(pos_weight=pos_w)

    steps_per_epoch = max(1, len(train_loader))
    total_steps = steps_per_epoch * MAX_EPOCHS
    scheduler = make_warmup_cosine_scheduler(optim, WARMUP_STEPS, total_steps)
    USE_AMP = (DEVICE.type == "cuda")
    scaler = torch.amp.GradScaler("cuda") if USE_AMP else None

    best_val = -1.0
    best_epoch = -1
    patience = 0
    best_state = {k: v.clone() for k, v in model.state_dict().items()}
    train_loss_traj = []

    target_epochs = fixed_epochs if fixed_epochs is not None else MAX_EPOCHS
    epochs_done = 0
    early_stop_ep = -1

    print(f"    [{fold_label}/seed{seed}] n_train={n_train} n_train_bear={n_train_bear} "
          f"n_valid={'-' if not has_valid else n_valid} "
          f"pos_w={pos_w_value:.2f} target_ep={target_epochs} purged={purge_count} "
          f"params={n_params}")

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

    return model, Xs, dates_seq, y_seq, dict(
        fold=fold_label, seed=int(seed),
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


def run_one_seed(seed, X_full, y_full, y_valid_mask, dates,
                 patch_size, d_model, nhead, nlayers, output_dir, cycle_name,
                 stride=None):
    """5-fold CV + FINAL_TRAIN + OOS predictions for one seed."""
    print("\n" + "=" * 70)
    print(f"[Cycle 56A {cycle_name}] Seed={seed} TARGET={TARGET} H={TARGET_HORIZON_DAYS}d")
    print("=" * 70)
    t_start = time.time()

    skip_folds = SKIP_FOLDS_PER_TARGET.get(TARGET, [])
    fold_results = []
    for fi in FOLDS:
        if fi["name"] in skip_folds:
            print(f"\n  --- {fi['name']} SKIPPED (per SKIP_FOLDS_PER_TARGET[{TARGET}]) ---")
            fold_results.append(dict(fold=fi["name"], seed=int(seed),
                                      skipped=True, skip_reason="target_specific_skip"))
            continue
        print(f"\n  --- {fi['name']} (seed={seed}) ---")
        _, _, _, _, fold_res = train_one_window(
            X_full, y_full, y_valid_mask, dates,
            train_start=fi["train_start"], train_end=fi["train_end"],
            valid_start=fi["valid_start"], valid_end=fi["valid_end"],
            patch_size=patch_size, d_model=d_model, nhead=nhead, nlayers=nlayers,
            fixed_epochs=None, fold_label=fi["name"], seed=seed, stride=stride,
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
    print(f"\n  [avg best_epoch] seed{seed} = {avg_best_ep}")

    # FINAL_TRAIN on 1995-2015
    print(f"\n  --- FINAL_TRAIN seed={seed} ---")
    final_model, Xs_final, dates_seq_final, y_seq_final, final_res = train_one_window(
        X_full, y_full, y_valid_mask, dates,
        train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
        valid_start=None, valid_end=None,
        patch_size=patch_size, d_model=d_model, nhead=nhead, nlayers=nlayers,
        fixed_epochs=avg_best_ep, fold_label="FINAL_TRAIN", seed=seed, stride=stride,
    )

    if final_model is None:
        print(f"  [FAIL] FINAL_TRAIN skipped")
        return None

    # OOS
    print(f"\n  --- OOS prediction seed={seed} ---")
    X_seq_final, y_seq_final2 = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final2 = dates[SEQ_LEN - 1:]
    y_valid_seq_final2 = y_valid_mask[SEQ_LEN - 1:]
    # OOS mask: in [OOS_START, OOS_END] AND label resolved (PIT FIX bug #2)
    oos_mask = (dates_seq_final2 >= np.datetime64(OOS_START)) & \
               (dates_seq_final2 <= np.datetime64(OOS_END)) & \
               y_valid_seq_final2
    print(f"    OOS mask: n_valid={int(oos_mask.sum())}")
    X_oos_t = torch.tensor(X_seq_final[oos_mask], dtype=torch.float32).to(DEVICE)

    USE_AMP = (DEVICE.type == "cuda")
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

    overall_pr = pr_auc(oop, oos_y)
    overall_ic = ic_spearman(oop, oos_y)

    elapsed = time.time() - t_start
    print(f"\n  [seed{seed}] OOS PR-AUC: {overall_pr:.4f} | IC: {overall_ic:.4f} | "
          f"elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    file_name = f"predictions_{cycle_name}_seed{seed}_{TARGET}.parquet"
    df = pd.DataFrame({
        "Date": oos_dates,
        "p_strict": oop,
        "y": oos_y,
        "split": "oos",
        "target": TARGET,
        "cycle": cycle_name,
        "seed": int(seed),
    })
    df.to_parquet(output_dir / file_name, index=False)
    print(f"  Saved: {output_dir}/{file_name}")

    del final_model
    if DEVICE.type == "cuda":
        torch.cuda.empty_cache()

    return dict(
        cycle=cycle_name,
        seed=int(seed),
        overall_oos_pr=overall_pr,
        overall_oos_ic=overall_ic,
        avg_best_epoch=avg_best_ep,
        per_fold=fold_results,
        final_train=final_res,
        elapsed_sec=elapsed,
        gpu_mem_peak_mb=mem_peak_mb,
        n_params=final_res["n_params"],
        oos_dates=oos_dates,
        oos_pred=oop,
        oos_y=oos_y,
    )


def build_5seed_mean_ensemble(per_seed_results, output_dir, cycle_name):
    """5-seed mean prediction ensemble."""
    seeds = sorted([r["seed"] for r in per_seed_results if r is not None])
    if len(seeds) == 0:
        raise RuntimeError("no successful seed runs to ensemble")

    base = next(r for r in per_seed_results if r is not None)
    ref_dates = pd.to_datetime(base["oos_dates"])
    ref_y = base["oos_y"]

    # Sanity
    for r in per_seed_results:
        if r is None:
            continue
        rd = pd.to_datetime(r["oos_dates"])
        if len(rd) != len(ref_dates) or not (rd == ref_dates).all():
            raise RuntimeError(f"date mismatch at seed={r['seed']}")
        if not np.array_equal(r["oos_y"], ref_y):
            raise RuntimeError(f"y mismatch at seed={r['seed']}")

    pred_matrix = np.stack([r["oos_pred"] for r in per_seed_results if r is not None], axis=0)
    mean_pred = pred_matrix.mean(axis=0)
    per_date_std = pred_matrix.std(axis=0, ddof=0)

    mean_pr = pr_auc(mean_pred, ref_y.astype(np.float64))
    mean_ic = ic_spearman(mean_pred, ref_y.astype(np.float64))

    df_mean = pd.DataFrame({
        "Date": ref_dates.values,
        "p_mean5": mean_pred,
        "p_per_seed_std": per_date_std,
        "y": ref_y,
        "split": "oos",
        "target": TARGET,
        "cycle": cycle_name,
        "n_seeds": int(len(seeds)),
    })
    out_file = output_dir / f"predictions_{cycle_name}_mean5_{TARGET}.parquet"
    df_mean.to_parquet(out_file, index=False)
    print(f"  [mean5 ensemble] Saved: {out_file}")

    per_seed_pr = {r["seed"]: pr_auc(r["oos_pred"], ref_y.astype(np.float64))
                   for r in per_seed_results if r is not None}
    per_seed_ic = {r["seed"]: ic_spearman(r["oos_pred"], ref_y.astype(np.float64))
                   for r in per_seed_results if r is not None}

    audit = dict(
        cycle=cycle_name,
        n_seeds=int(len(seeds)),
        seeds_used=seeds,
        n_obs=int(len(ref_dates)),
        n_events=int(ref_y.sum()),
        per_seed_pr_auc={int(s): round(per_seed_pr[s], 6) for s in seeds},
        per_seed_ic={int(s): round(per_seed_ic[s], 6) for s in seeds},
        per_seed_pr_mean=round(float(np.mean(list(per_seed_pr.values()))), 6),
        per_seed_pr_std=round(float(np.std(list(per_seed_pr.values()), ddof=1)), 6)
                         if len(per_seed_pr) > 1 else 0.0,
        per_seed_pr_min=round(float(np.min(list(per_seed_pr.values()))), 6),
        per_seed_pr_max=round(float(np.max(list(per_seed_pr.values()))), 6),
        per_seed_pr_range=round(float(np.max(list(per_seed_pr.values())) -
                                      np.min(list(per_seed_pr.values()))), 6),
        mean5_pr_auc=round(float(mean_pr), 6),
        mean5_ic=round(float(mean_ic), 6),
        per_date_std_mean=round(float(per_date_std.mean()), 6),
        per_date_std_max=round(float(per_date_std.max()), 6),
    )
    return audit


def main_run(cycle_name, feature_panel, n_features,
             patch_size, d_model, output_dir, gpu_fraction=0.15,
             nhead=PT_NHEAD_DEFAULT, nlayers=PT_NLAYERS_DEFAULT, stride=None):
    """Main: 5-seed × 5-fold CV + FINAL + OOS + mean5 ensemble."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"[Cycle 56A {cycle_name}] Device: {DEVICE} | TARGET={TARGET} H={TARGET_HORIZON_DAYS}d")
    if DEVICE.type == "cuda":
        try:
            torch.cuda.set_per_process_memory_fraction(gpu_fraction, device=0)
            print(f"[Cycle 56A {cycle_name}] CUDA fraction = {gpu_fraction}")
        except Exception as e:
            print(f"[Cycle 56A {cycle_name}] CUDA fraction set failed: {e}")

    print(f"[Cycle 56A {cycle_name}] feature_panel={feature_panel}")
    print(f"[Cycle 56A {cycle_name}] n_features={n_features}")
    print(f"[Cycle 56A {cycle_name}] patch_size={patch_size} d_model={d_model} "
          f"nhead={nhead} nlayers={nlayers}")

    X_full, y_full, y_valid_mask, dates, feature_cols = prepare_data(
        feature_panel, n_features)
    print(f"[Data] X.shape={X_full.shape} y_valid_count={int(y_valid_mask.sum())}")

    cycle_start = time.time()
    per_seed_results = []
    for s in SEEDS:
        r = run_one_seed(s, X_full, y_full, y_valid_mask, dates,
                         patch_size=patch_size, d_model=d_model,
                         nhead=nhead, nlayers=nlayers,
                         output_dir=output_dir, cycle_name=cycle_name, stride=stride)
        per_seed_results.append(r)

    cycle_elapsed = time.time() - cycle_start
    print(f"\n[Cycle 56A {cycle_name}] Seed runs DONE. Total: {cycle_elapsed:.1f}s "
          f"({cycle_elapsed/60:.1f} min)")

    print("\n" + "=" * 70)
    print(f"[5-seed mean ensemble — {cycle_name}]")
    print("=" * 70)
    audit = build_5seed_mean_ensemble(per_seed_results, output_dir, cycle_name)

    print("\n" + "=" * 70)
    print(f"[Cycle 56A {cycle_name} SUMMARY]")
    print("=" * 70)
    print(f"  Per-seed PR-AUC: " +
          "  ".join([f"seed{s}={audit['per_seed_pr_auc'][s]:.4f}" for s in SEEDS
                     if s in audit['per_seed_pr_auc']]))
    print(f"  Mean: {audit['per_seed_pr_mean']:.4f}  std={audit['per_seed_pr_std']:.4f}  "
          f"range={audit['per_seed_pr_range']:.4f}")
    print(f"  5-seed MEAN ensemble PR-AUC: {audit['mean5_pr_auc']:.4f}  IC={audit['mean5_ic']:.4f}")

    def serialize_seed_result(r):
        if r is None:
            return {"skipped": True}
        return {k: v for k, v in r.items()
                if k not in ("oos_dates", "oos_pred", "oos_y")}

    final_audit = dict(
        cycle=f"56A_{cycle_name}_strict_PIT_q15",
        validation_strategy="walk_forward_expanding_5_fold_CV_purged",
        pit_fixes_applied={
            "bug_1_purged_kfold_cv": f"np.busday_offset(dates, {TARGET_HORIZON_DAYS}, roll='forward') < valid_start",
            "bug_2_y_valid_mask": "ret_q15.notna() — train/valid/OOS exclude unresolved",
            "M6_phantom0_guard": "target_path = targets_long_horizon_observable.parquet (Cycle 54D Phase 4)",
            "M7_pub_lag_acknowledged": "CFNAI ~22d / ICSA ~5d in v5e/v4a/v5f panels inherited — q15 horizon impact est. < 0.005 PR-AUC (55B Codex)",
            "reference_master": "scripts/144_moe_patchtst_v5e_q126.py (56B Codex audit fix정합) + 167 q15 adaptation"
        },
        strict_determinism={
            "CUBLAS_WORKSPACE_CONFIG": os.environ.get("CUBLAS_WORKSPACE_CONFIG"),
            "torch_use_deterministic_algorithms": True,
            "cudnn_deterministic": True,
            "cudnn_benchmark": False,
            "warn_only": True,
        },
        seeds=SEEDS,
        feature_panel=str(feature_panel),
        n_features=n_features,
        patchtst_hparams={
            "patch_size": patch_size, "d_model": d_model,
            "nhead": nhead, "nlayers": nlayers,
            "stride": stride if stride is not None else (1 if patch_size == 2 else 2),
            "dropout": PT_DROPOUT, "weight_decay": PT_WEIGHT_DECAY, "lr": PT_LR,
        },
        training_common={
            "batch_size": BATCH_SIZE, "max_epochs": MAX_EPOCHS,
            "early_stop_patience": EARLY_STOP_PATIENCE,
            "early_stop_min_delta": EARLY_STOP_MIN_DELTA,
            "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
        },
        folds=FOLDS,
        skip_folds=SKIP_FOLDS_PER_TARGET.get(TARGET, []),
        target=TARGET,
        target_horizon_days=TARGET_HORIZON_DAYS,
        ensemble_audit=audit,
        per_seed_diagnostics={f"seed{r['seed']}": serialize_seed_result(r) for r in per_seed_results if r is not None},
        total_elapsed_sec=round(cycle_elapsed, 1),
    )
    audit_path = output_dir / f"audit_{cycle_name}_strict_PIT_q15.json"
    with audit_path.open("w") as f:
        json.dump(final_audit, f, indent=2, default=str)
    print(f"\n[audit] Saved: {audit_path}")

    print("\n" + "=" * 70)
    print(f"[Cycle 56A {cycle_name} DONE]")
    print("=" * 70)
    return final_audit


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--cycle", required=True)
    parser.add_argument("--feature_panel", required=True)
    parser.add_argument("--n_features", type=int, required=True)
    parser.add_argument("--patch_size", type=int, default=4)
    parser.add_argument("--d_model", type=int, default=64)
    parser.add_argument("--nhead", type=int, default=PT_NHEAD_DEFAULT)
    parser.add_argument("--nlayers", type=int, default=PT_NLAYERS_DEFAULT)
    parser.add_argument("--stride", type=int, default=-1)
    parser.add_argument("--output_dir", required=True)
    parser.add_argument("--gpu_fraction", type=float, default=0.15)
    args = parser.parse_args()

    stride = None if args.stride <= 0 else args.stride
    main_run(
        cycle_name=args.cycle,
        feature_panel=args.feature_panel,
        n_features=args.n_features,
        patch_size=args.patch_size,
        d_model=args.d_model,
        nhead=args.nhead,
        nlayers=args.nlayers,
        stride=stride,
        output_dir=args.output_dir,
        gpu_fraction=args.gpu_fraction,
    )
