#!/usr/bin/env python3
"""
136_patchtst_q126_v5f_ecos.py — Cycle 53I: PatchTST + v5e + ECOS KR macro (79 features)

Builds on:
  - Cycle 53H (scripts/132_patchtst_q126_usmacro.py) — PatchTST q126 = 0.4012 baseline (v5e 74 features)
  - Cycle 53B (scripts/125_patchtst_q126_horizon.py) — PatchTST q126 = 0.3456 baseline (v4a 70 features)
  - Cycle 134 (scripts/134_ecos_fetch_kr_macro.R) — ECOS KR macro fetched + 35d/50d/1d PIT lag applied
  - Cycle 135 (scripts/135_feature_panel_v5f_ecos_kr.R) — v5f panel (74 v5e + 5 ECOS = 79 features)

This cycle:
  - PatchTST baseline (53B와 동일 architecture)
  - 79 features = v5e 74 + 5 ECOS KR macro (m2_yoy, krw_usd_change_5d, base_rate, ip_yoy, cpi_yoy)
  - Walk-forward 5-fold CV
  - Targets: y_tail_q126 (primary) + y_tail_q15 (control)

Hypothesis 가설:
  - Best (additive): 0.4012 + 0.02~0.04 → 0.42~0.45 (ECOS KR macro at q126 PROVEN)
  - Realistic: +0.01~0.02 (partial overlap with BBVA composite — max |cor|=0.52)
  - Worst: dilution (cycle 46 패턴, BBVA가 이미 KR macro signal 일부 cover)

Architecture identical to 132 (Cycle 53H). Only feature panel swap (v5e → v5f).

Output:
  outputs/03_models/v5f_patchtst_q126_ecos/predictions_patchtst_v5f_y_tail_q15.parquet
  outputs/03_models/v5f_patchtst_q126_ecos/predictions_patchtst_v5f_y_tail_q126.parquet
  outputs/03_models/v5f_patchtst_q126_ecos/per_fold_diagnostics.json
  outputs/04_evaluation/patchtst_q126_v5f_ecos_python_diag.json

PIT integrity:
  - Forward labels (Cycle 48A targets_long_horizon.parquet verified)
  - Walk-forward expanding 5-fold CV
  - ECOS features 35d/50d/1d publication lag applied in 134
  - OOS 2018-01-01 ~ 2026-04-30
  - Per-horizon: standardization uses train window only
  - GPU memory fraction 0.3
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
OUT = WS / "outputs/03_models/v5f_patchtst_q126_ecos"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 53I Python] Device: {DEVICE}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.3, device=0)
        print(f"[Cycle 53I] CUDA memory fraction set to 0.3")
    except Exception as e:
        print(f"[Cycle 53I] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 53I] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")

# Full pre-OOS span
FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# Walk-forward 5-fold CV (mirror Cycle 53H)
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

# PatchTST hyperparameters (Cycle 53B / 53H retain)
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
TARGETS = ["y_tail_q15", "y_tail_q126"]
SEED = 42

N_FEATURES_EXPECTED = 79  # v5e 74 + 5 ECOS


# ============================================================================
# PatchTST (mirror 132)
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
# Helpers (mirror 132)
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
    Load v5f feature panel (79 features) + targets_long_horizon.
    """
    feat_path = DATA / "feature_panel_v5f_ecos_kr.parquet"
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
    assert len(feature_cols) == N_FEATURES_EXPECTED, f"v5f expects {N_FEATURES_EXPECTED} features, got {len(feature_cols)}"

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
    print(f"[Cycle 53I] {model_name} (seed={seed}) target: {target_col}")
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

    col_name = "p_patchtst"
    file_name = f"predictions_patchtst_v5f_{target_col}.parquet"

    df = pd.DataFrame({
        "Date": dates_seq_final2[oos_idx],
        col_name: oop, "y": oos_y,
        "split": "oos", "target": target_col,
    })
    df.to_parquet(OUT / file_name, index=False)
    print(f"  Saved: {OUT}/{file_name}")

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
    print("[Cycle 53I — PatchTST + v5e + ECOS KR macro (79 features) under q126 forward labels]")
    print("[Walk-forward 5-fold CV, forward labels, Fold3 q126 zero-events guard, seed=42]")
    print(f"[OOS window: 2018-2026 / Targets: {TARGETS} / Seed: {SEED}]")
    print("=" * 70)

    results = {}

    for tgt in TARGETS:
        results[f"patchtst_{tgt}"] = run_walkforward_single_seed(
            PatchTSTClassifier, "PATCHTST", tgt, seed=SEED)

    # Summary
    print("\n" + "=" * 70)
    print("[Python Cycle 53I SUMMARY — PatchTST + v5e + ECOS KR macro on 2 horizons]")
    print("=" * 70)
    for tgt in TARGETS:
        r = results[f"patchtst_{tgt}"]
        print(f"  PatchTST {tgt}: OOS PR-AUC={r['oos_pr']:.4f}  IC={r['oos_ic']:.4f}  avg_ep={r['avg_best_epoch']}")

    # Baseline comparison
    print("\n" + "█" * 70)
    print("[Baseline comparison — Cycle 53H v5e (74 features w/ US macro) vs Cycle 53B v4a (70 features)]")
    print("█" * 70)
    cycle53h_q126 = 0.4012
    cycle53b_q126 = 0.3456
    delta_vs_53h = results["patchtst_y_tail_q126"]["oos_pr"] - cycle53h_q126
    delta_vs_53b = results["patchtst_y_tail_q126"]["oos_pr"] - cycle53b_q126
    print(f"  Cycle 53H baseline (v5e 74, w/ US macro):  PR-AUC=0.4012")
    print(f"  Cycle 53B baseline (v4a 70, no US macro):  PR-AUC=0.3456")
    print(f"  Cycle 53I (v5f 79, +ECOS KR macro):        PR-AUC={results['patchtst_y_tail_q126']['oos_pr']:.4f}")
    print(f"  Δ vs 53H (incremental ECOS contribution):  {delta_vs_53h:+.4f}")
    print(f"  Δ vs 53B (cumulative US + ECOS):           {delta_vs_53b:+.4f}")
    if delta_vs_53h >= 0.02:
        print("  → ADDITIVE_STRONG (Δ vs 53H ≥ +0.02) — ECOS KR macro at q126 PROVEN")
    elif delta_vs_53h > 0:
        print("  → ADDITIVE_WEAK (0 < Δ vs 53H < +0.02) — marginal contribution")
    elif delta_vs_53h >= -0.005:
        print("  → NEUTRAL (-0.005 ≤ Δ vs 53H ≤ 0) — no incremental effect (BBVA covers)")
    else:
        print("  → DILUTION (Δ vs 53H < -0.005) — ECOS KR macro infringes existing signal")

    # Per-fold + diagnostics dump
    per_fold_path = OUT / "per_fold_diagnostics.json"

    def serialize_seed_result(r):
        return {k: v for k, v in r.items() if k not in ("oos_dates", "oos_pred", "oos_y")}

    per_fold = {
        "cycle": "53I_patchtst_q126_v5f_ecos",
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date())},
        "feature_panel": "feature_panel_v5f_ecos_kr.parquet (79 features: v5e 74 + 5 ECOS KR macro)",
        "patchtst_y_tail_q15": serialize_seed_result(results["patchtst_y_tail_q15"]),
        "patchtst_y_tail_q126": serialize_seed_result(results["patchtst_y_tail_q126"]),
    }
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"\n[Per-fold diagnostics] Saved: {per_fold_path}")

    # Python diagnostics summary
    diag_path = EVAL_DIR / "patchtst_q126_v5f_ecos_python_diag.json"
    diag = {
        "cycle": "53I_patchtst_q126_v5f_ecos",
        "panel": "feature_panel_v5f_ecos_kr.parquet",
        "targets_source": "targets_long_horizon.parquet (Cycle 48A 103_compute_long_horizon_targets.R)",
        "n_features": N_FEATURES_EXPECTED,
        "v5e_base_features": 74,
        "ecos_kr_macro_features": [
            "ecos_m2_yoy_lag1",
            "ecos_krw_usd_change_5d_lag1",
            "ecos_base_rate_lag1",
            "ecos_industrial_production_yoy_lag1",
            "ecos_cpi_yoy_lag1",
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
        "baselines": {
            "cycle_53h_q126_v5e_with_us_macro": cycle53h_q126,
            "cycle_53b_q126_v4a_no_us_macro": cycle53b_q126,
        },
        "delta_q126_vs_53h": round(delta_vs_53h, 4),
        "delta_q126_vs_53b": round(delta_vs_53b, 4),
        "per_fold_diagnostics_path": str(per_fold_path),
    }
    with diag_path.open("w") as f:
        json.dump(diag, f, indent=2, default=str)
    print(f"[Diagnostics] Saved: {diag_path}")

    print("\n" + "=" * 70)
    print("[Cycle 53I Python DONE — Run scripts/137_patchtst_q126_v5f_ecos_aggregate.R next]")
    print("=" * 70)
