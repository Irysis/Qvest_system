#!/usr/bin/env python3
"""
132_patchtst_q126_usmacro.py — Cycle 53H Path C 확장 (PatchTST + v4a + US macro)

Builds on:
  - Cycle 53B (scripts/125_patchtst_q126_horizon.py) — PatchTST q126 = 0.3456 baseline (v4a 70 features)
  - Cycle 47B/48A — US macro discovery (us_initial_claims rank 1 at q126, us_cfnai rank 1 at q15/q63)

This cycle:
  - PatchTST baseline (53B와 동일 architecture)
  - 74 features = v4a 70 + 4 US macro (us_t10y2y_spread_lag1, us_initial_claims_4w_avg_lag1,
    us_cfnai_lag1, us_stlfsi_lag1)
  - Walk-forward 5-fold CV
  - Targets: y_tail_q126 (primary) + y_tail_q15 (control / Cycle 47B regression baseline)
  - Cycle 47B at q15: us_macro REGRESSION 패턴 forward에서도 재현되는지

Hypothesis 가설:
  - Best case (additive): 0.3456 + 0.02~0.04 = 0.36~0.40
  - Realistic: +0.01~0.02 (partial overlap)
  - Worst: dilution -0.01~-0.02 (Cycle 46A 패턴, q15에서 47B 발견)

Architecture identical to 125 (Cycle 53B). Only feature panel swap (v4a → v5e).

Output:
  outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q15.parquet
  outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_tail_q126.parquet
  outputs/03_models/v5e_patchtst_q126_usmacro/per_fold_diagnostics.json
  outputs/04_evaluation/patchtst_q126_usmacro_v5e_python_diag.json

PIT integrity:
  - Forward labels (Cycle 48A targets_long_horizon.parquet verified)
  - Walk-forward expanding 5-fold CV (Cycle 45D pattern)
  - OOS 2018-01-01 ~ 2026-04-30
  - Per-horizon: standardization uses train window only, OOS standardization purged
  - GPU memory fraction 0.3 (concurrent with 53C/53E if running)
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
OUT = WS / "outputs/03_models/v5e_patchtst_q126_usmacro"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 53H Path C extension Python] Device: {DEVICE}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.3, device=0)
        print(f"[Cycle 53H] CUDA memory fraction set to 0.3 (concurrent with 53C+53E)")
    except Exception as e:
        print(f"[Cycle 53H] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 53H] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")

# Full pre-OOS span
FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# Walk-forward 5-fold CV (Cycle 45D pattern; Fold3 may have zero events for q126)
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

# PatchTST hyperparameters (Cycle 45E / Cycle 52 / Cycle 53B retain)
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
SEED = 42


# ============================================================================
# PatchTST: Channel-Independent Patch Transformer (mirror Cycle 53B)
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
# Helpers (mirror Cycle 53B)
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
    Load v5e feature panel (74 features = v4a 70 + 4 US macro) + targets_long_horizon.
    """
    feat_path = DATA / "feature_panel_v5e_q126_usmacro.parquet"
    tgt_path = TGT / "targets_long_horizon.parquet"
    if not feat_path.exists():
        sys.exit(f"missing feature panel: {feat_path}")
    if not tgt_path.exists():
        sys.exit(f"missing target parquet (run scripts/103_compute_long_horizon_targets.R): {tgt_path}")

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


def set_seed(seed):
    torch.manual_seed(seed)
    np.random.seed(seed)
    if DEVICE.type == "cuda":
        torch.cuda.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)


def train_one_window(model_class, model_name, target_col,
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
        # Fold3 zero events guard for q126
        if valid_bear < 5:
            print(f"    [WARN] {fold_label}/{target_col} valid_bear={valid_bear} < 5 — skip fold (zero events)")
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

    train_loader = DataLoader(TensorDataset(X_train_t, y_train_t),
                              batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
                              num_workers=NUM_WORKERS)

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


def run_walkforward_single_seed(model_class, model_name, target_col, seed=42):
    print("\n" + "=" * 70)
    print(f"[Cycle 53H] {model_name} (seed={seed}) target: {target_col}")
    print("=" * 70)
    t_start = time.time()

    X_full, y_full, dates, feature_cols = prepare_data_full(target_col)

    # 5-fold CV
    fold_results = []
    for fi in FOLDS:
        print(f"\n  --- {fi['name']} ---")
        _, _, _, _, fold_res = train_one_window(
            model_class, model_name, target_col,
            X_full, y_full, dates,
            train_start=fi["train_start"], train_end=fi["train_end"],
            valid_start=fi["valid_start"], valid_end=fi["valid_end"],
            fixed_epochs=None, fold_label=fi["name"], seed=seed,
        )
        fold_results.append(fold_res)
        if DEVICE.type == "cuda":
            torch.cuda.empty_cache()

    valid_eps = [r["best_epoch"] for r in fold_results
                 if r.get("best_epoch") is not None and r["best_epoch"] > 0]
    if len(valid_eps) == 0:
        avg_best_ep = MAX_EPOCHS // 2
        print(f"\n  [WARN] All folds returned best_epoch <= 0 — fallback {avg_best_ep}")
    else:
        avg_best_ep = int(round(np.mean(valid_eps)))
    print(f"\n  [Avg best_epoch across {len(valid_eps)} folds] = {avg_best_ep}")
    print(f"  [Per-fold best_epoch] = {[r.get('best_epoch') for r in fold_results]}")
    print(f"  [Per-fold best_valid_pr] = {[r.get('best_valid_pr') for r in fold_results]}")

    # Final training: TRAIN 1995-2015 with avg_best_ep
    print(f"\n  --- Final training: TRAIN 1995-2015 / epochs={avg_best_ep} ---")
    final_model, Xs_final, dates_seq_final, y_seq_final, final_train_res = train_one_window(
        model_class, model_name, target_col,
        X_full, y_full, dates,
        train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
        valid_start=None, valid_end=None,
        fixed_epochs=avg_best_ep, fold_label="FINAL_TRAIN", seed=seed,
    )

    # OOS evaluation
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
    oos_ic_v = ic_spearman(oop, oos_y)
    elapsed = time.time() - t_start
    print(f"\n  [{model_name}/{target_col}/seed{seed}] OOS PR-AUC: {oos_pr_v:.4f}  IC: {oos_ic_v:.4f}  | elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        print(f"  GPU memory peak: {mem_peak_mb:.1f} MB")
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    # Save OOS predictions
    col_name = "p_patchtst"
    file_name = f"predictions_patchtst_v5e_{target_col}.parquet"

    df = pd.DataFrame({
        "Date": dates_seq_final2[oos_idx],
        col_name: oop, "y": oos_y,
        "split": "oos", "target": target_col,
    })
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")

    # Save oos predictions array for downstream multi-horizon
    oos_dates = dates_seq_final2[oos_idx]

    del final_model
    if DEVICE.type == "cuda":
        torch.cuda.empty_cache()

    return dict(
        model=model_name,
        target=target_col,
        seed=int(seed),
        oos_pr=oos_pr_v,
        oos_ic=oos_ic_v,
        avg_best_epoch=avg_best_ep,
        per_fold=fold_results,
        final_train=final_train_res,
        elapsed_sec=elapsed,
        gpu_mem_peak_mb=mem_peak_mb,
        n_params=final_train_res["n_params"],
        oos_dates=oos_dates,
        oos_pred=oop,
        oos_y=oos_y,
    )


if __name__ == "__main__":
    print("=" * 70)
    print("[Cycle 53H Path C 확장 — PatchTST + v4a + US macro (74 features) under q126 forward labels]")
    print("[Walk-forward 5-fold CV, forward labels, Fold3 q126 zero-events guard, seed=42]")
    print(f"[OOS window: 2018-2026 / Targets: {TARGETS} / Seed: {SEED}]")
    print("=" * 70)

    results = {}

    # ============================================================
    # Run PatchTST against 2 targets (q15 control, q126 primary)
    # ============================================================
    for tgt in TARGETS:
        results[f"patchtst_{tgt}"] = run_walkforward_single_seed(
            PatchTSTClassifier, "PATCHTST", tgt, seed=SEED)

    # ============================================================
    # Summary
    # ============================================================
    print("\n" + "=" * 70)
    print("[Python Cycle 53H SUMMARY — PatchTST + v4a + US macro on 2 horizons]")
    print("=" * 70)
    for tgt in TARGETS:
        r = results[f"patchtst_{tgt}"]
        print(f"  PatchTST {tgt}: OOS PR-AUC={r['oos_pr']:.4f}  IC={r['oos_ic']:.4f}  avg_ep={r['avg_best_epoch']}")

    # ============================================================
    # Baseline comparison printout (informative; full aggregate in 133)
    # ============================================================
    print("\n" + "█" * 70)
    print("[Baseline comparison — Cycle 53B v4a baseline w/o US macro]")
    print("█" * 70)
    print(f"  Cycle 53B PatchTST q126 baseline: 0.3456 (v4a 70 features, no US macro)")
    cycle53b_q126 = 0.3456
    delta_q126 = results["patchtst_y_tail_q126"]["oos_pr"] - cycle53b_q126
    print(f"  Cycle 53H PatchTST q126 + US macro: {results['patchtst_y_tail_q126']['oos_pr']:.4f}")
    print(f"  Delta vs Cycle 53B baseline: {delta_q126:+.4f}")
    if delta_q126 >= 0.02:
        print("  → ADDITIVE_STRONG (Δ ≥ +0.02) — US macro at q126 PROVEN")
    elif delta_q126 > 0:
        print("  → ADDITIVE_WEAK (0 < Δ < +0.02) — marginal contribution")
    elif delta_q126 >= -0.005:
        print("  → NEUTRAL (-0.005 ≤ Δ ≤ +0.005) — no effect")
    else:
        print("  → DILUTION (Δ < -0.005) — US macro infringes PatchTST signal")

    # ============================================================
    # Per-fold + diagnostics dump
    # ============================================================
    per_fold_path = OUT / "per_fold_diagnostics.json"

    def serialize_seed_result(r):
        # remove numpy arrays for JSON serialization
        return {k: v for k, v in r.items() if k not in ("oos_dates", "oos_pred", "oos_y")}

    per_fold = {
        "cycle": "53H_patchtst_q126_usmacro",
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date()),
                       "note": "fold 5 valid 2016-2017 제외하여 leakage 방지"},
        "feature_panel": "feature_panel_v5e_q126_usmacro.parquet (74 features: v4a 70 + 4 US macro)",
        "patchtst_y_tail_q15": serialize_seed_result(results["patchtst_y_tail_q15"]),
        "patchtst_y_tail_q126": serialize_seed_result(results["patchtst_y_tail_q126"]),
    }
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"\n[Per-fold diagnostics] Saved: {per_fold_path}")

    # ============================================================
    # Python diagnostics summary
    # ============================================================
    diag_path = EVAL_DIR / "patchtst_q126_usmacro_v5e_python_diag.json"
    diag = {
        "cycle": "53H_patchtst_q126_usmacro",
        "panel": "feature_panel_v5e_q126_usmacro.parquet",
        "targets_source": "targets_long_horizon.parquet (Cycle 48A 103_compute_long_horizon_targets.R)",
        "n_features": 74,
        "v4a_base_features": 70,
        "us_macro_features": [
            "us_t10y2y_spread_lag1",
            "us_initial_claims_4w_avg_lag1",
            "us_cfnai_lag1",
            "us_stlfsi_lag1",
        ],
        "forward_labels": True,
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "horizons_evaluated": TARGETS,
        "patchtst_hparams": {
            "patch_size": PATCH_SIZE, "patch_stride": PATCH_STRIDE,
            "d_model": PT_D_MODEL, "nhead": PT_NHEAD, "n_layers": PT_NLAYERS,
            "ff_dim": PT_D_MODEL * PT_FF_MULT, "dropout": PT_DROPOUT,
            "attn_dropout": PT_ATTN_DROPOUT,
            "weight_decay": PT_WEIGHT_DECAY, "lr": PT_LR,
            "seed": SEED,
        },
        "training_common": {
            "batch_size": BATCH_SIZE, "max_epochs": MAX_EPOCHS,
            "early_stop_patience": EARLY_STOP_PATIENCE,
            "early_stop_min_delta": EARLY_STOP_MIN_DELTA,
            "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
            "mixed_precision_amp": USE_AMP,
            "gpu_mem_fraction": 0.3 if DEVICE.type == "cuda" else None,
        },
        "patchtst_y_tail_q15": {
            "oos_pr": round(results["patchtst_y_tail_q15"]["oos_pr"], 4),
            "oos_ic": round(results["patchtst_y_tail_q15"]["oos_ic"], 4),
            "avg_best_epoch": results["patchtst_y_tail_q15"]["avg_best_epoch"],
            "n_params": results["patchtst_y_tail_q15"]["n_params"],
            "elapsed_sec": round(results["patchtst_y_tail_q15"]["elapsed_sec"], 1),
        },
        "patchtst_y_tail_q126": {
            "oos_pr": round(results["patchtst_y_tail_q126"]["oos_pr"], 4),
            "oos_ic": round(results["patchtst_y_tail_q126"]["oos_ic"], 4),
            "avg_best_epoch": results["patchtst_y_tail_q126"]["avg_best_epoch"],
            "n_params": results["patchtst_y_tail_q126"]["n_params"],
            "elapsed_sec": round(results["patchtst_y_tail_q126"]["elapsed_sec"], 1),
        },
        "baseline_cycle53b_q126_no_usmacro": 0.3456,
        "delta_q126_vs_cycle53b": round(results["patchtst_y_tail_q126"]["oos_pr"] - 0.3456, 4),
        "per_fold_diagnostics_path": str(per_fold_path),
    }
    with diag_path.open("w") as f:
        json.dump(diag, f, indent=2, default=str)
    print(f"[Diagnostics] Saved: {diag_path}")

    print("\n" + "=" * 70)
    print("[Cycle 53H Python DONE — Run scripts/133_patchtst_q126_usmacro_aggregate.R next]")
    print("=" * 70)
