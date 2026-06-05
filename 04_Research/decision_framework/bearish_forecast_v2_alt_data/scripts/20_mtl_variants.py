#!/usr/bin/env python3
"""
20_mtl_variants.py — D5b + D5c + D5d MTL variants (Uncertainty / Auxiliary / PCGrad)

Plan v1.3+ — 4 MTL variants on BiLSTM hard sharing.

Models:
  V_UNC : Uncertainty weighting (Kendall-Gal-Cipolla 2018 CVPR)
          L = Σ_t (1/(2σ_t²)) · L_t + log σ_t,  σ_t learnable
  V_AUX : Auxiliary policy (main=tail α=1.0, aux=onset β=0.2)
  V_PCG : PCGrad gradient projection (Yu et al. 2020 NeurIPS)
          if cos(g_i, g_j) < 0: g_i ← g_i - (g_i·g_j / ||g_j||²) · g_j

Output: outputs/03_models/mtl_variants/predictions_mtl_{variant}_{target}.parquet
"""

import sys, math
from pathlib import Path
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
TGT = WS / "outputs/02_targets"
OUT = WS / "outputs/03_models/mtl_variants"
OUT.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[D5* MTL variants] Device: {DEVICE}")

TRAIN_START = pd.Timestamp("1995-01-01"); TRAIN_END = pd.Timestamp("2009-12-31")
VALID_START = pd.Timestamp("2010-01-01"); VALID_END = pd.Timestamp("2015-12-31")
OOS_START = pd.Timestamp("2016-01-01"); OOS_END = pd.Timestamp("2026-04-30")
SEQ_LEN = 21; HIDDEN = 64; LAYERS = 2; DROPOUT = 0.3
LR = 1e-3; BS = 64; EPOCHS = 50; PATIENCE = 10

torch.manual_seed(42); np.random.seed(42)


# ── Shared trunk ──
class MTLEncoder(nn.Module):
    def __init__(self, input_dim, hidden=HIDDEN, layers=LAYERS, dropout=DROPOUT):
        super().__init__()
        self.lstm = nn.LSTM(input_dim, hidden, num_layers=layers,
                            batch_first=True, bidirectional=True,
                            dropout=dropout if layers > 1 else 0)
        self.fc = nn.Sequential(nn.Linear(hidden * 2, 64), nn.ReLU(), nn.Dropout(dropout))

    def forward(self, x):
        out, _ = self.lstm(x)
        return self.fc(out.mean(dim=1))


# ── V_UNC: Uncertainty weighting ──
class MTLUncertainty(nn.Module):
    def __init__(self, input_dim):
        super().__init__()
        self.enc = MTLEncoder(input_dim)
        self.head_tail = nn.Linear(64, 1)
        self.head_onset = nn.Linear(64, 1)
        # log σ² (learnable; init 0 → σ²=1)
        self.log_var_tail = nn.Parameter(torch.zeros(1))
        self.log_var_onset = nn.Parameter(torch.zeros(1))

    def forward(self, x):
        h = self.enc(x)
        return (self.head_tail(h).squeeze(-1),
                self.head_onset(h).squeeze(-1))

    def uncertainty_loss(self, logit_t, y_t, logit_o, y_o, pw_t, pw_o):
        bce_t = nn.functional.binary_cross_entropy_with_logits(
            torch.clamp(logit_t, -20, 20), y_t, pos_weight=pw_t)
        bce_o = nn.functional.binary_cross_entropy_with_logits(
            torch.clamp(logit_o, -20, 20), y_o, pos_weight=pw_o)
        precision_t = torch.exp(-self.log_var_tail)
        precision_o = torch.exp(-self.log_var_onset)
        return (precision_t * bce_t + 0.5 * self.log_var_tail
                + precision_o * bce_o + 0.5 * self.log_var_onset).squeeze()


# ── V_AUX: Auxiliary policy (main=tail 1.0 / aux=onset 0.2) ──
class MTLAux(nn.Module):
    def __init__(self, input_dim):
        super().__init__()
        self.enc = MTLEncoder(input_dim)
        self.head_tail = nn.Linear(64, 1)
        self.head_onset = nn.Linear(64, 1)

    def forward(self, x):
        h = self.enc(x)
        return (self.head_tail(h).squeeze(-1),
                self.head_onset(h).squeeze(-1))


# ── PCGrad helper ──
def pcgrad_project(grads_list):
    """grads_list: list of dict[param_name -> grad tensor]. Returns combined grads."""
    n_tasks = len(grads_list)
    pc_grads = [{k: v.clone() for k, v in g.items()} for g in grads_list]
    for i in range(n_tasks):
        for j in range(n_tasks):
            if i == j:
                continue
            # Compute dot product / norm over all params
            num = 0.0; denom = 0.0
            for k in pc_grads[i]:
                if k in grads_list[j]:
                    num += (pc_grads[i][k] * grads_list[j][k]).sum().item()
                    denom += (grads_list[j][k] ** 2).sum().item()
            if denom > 0 and num < 0:  # conflict
                scale = num / denom
                for k in pc_grads[i]:
                    if k in grads_list[j]:
                        pc_grads[i][k] = pc_grads[i][k] - scale * grads_list[j][k]
    # Combine (sum)
    combined = {k: torch.zeros_like(v) for k, v in pc_grads[0].items()}
    for g in pc_grads:
        for k in g:
            combined[k] = combined[k] + g[k]
    return combined


# ── Common utils ──
def make_sequences(X, ys, seq_len=SEQ_LEN):
    N, D = X.shape
    if N <= seq_len:
        return np.empty((0, seq_len, D)), [np.empty(0) for _ in ys]
    X_seq = np.lib.stride_tricks.sliding_window_view(X, (seq_len, D)).squeeze(1)
    y_seqs = [y[seq_len - 1:] for y in ys]
    return X_seq, y_seqs


def pr_auc(p, y):
    ok = ~(np.isnan(p) | np.isnan(y))
    p = p[ok]; y = y[ok]
    if len(p) < 30 or y.sum() < 5:
        return float("nan")
    order = np.argsort(-p); y_ord = y[order]
    prec = np.cumsum(y_ord) / np.arange(1, len(y_ord) + 1)
    rec = np.cumsum(y_ord) / y_ord.sum()
    return float(np.sum(np.diff(rec) * (prec[1:] + prec[:-1]) / 2))


# ── Data load ──
print("\n[Loading data]")
feat = pd.read_parquet(DATA / "feature_panel_v1_alt_enhanced.parquet")
tgt = pd.read_parquet(TGT / "targets_full.parquet")[["Date", "y_tail_q15", "y_onset"]]
feat["Date"] = pd.to_datetime(feat["Date"]); tgt["Date"] = pd.to_datetime(tgt["Date"])
panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
panel = panel[panel["Date"] <= OOS_END]

fcols = [c for c in panel.columns if c not in ("Date", "y_tail_q15", "y_onset")]
X = panel[fcols].values.astype(np.float32)
y_tail = panel["y_tail_q15"].fillna(0).values.astype(np.float32)
y_onset = panel["y_onset"].fillna(0).values.astype(np.float32)
train_mask = (panel["Date"] >= TRAIN_START) & (panel["Date"] <= TRAIN_END)
col_med = np.nan_to_num(np.nanmedian(X[train_mask.values], axis=0), nan=0.0)
for j in range(X.shape[1]):
    X[np.isnan(X[:, j]), j] = col_med[j]
mean = np.nan_to_num(X[train_mask.values].mean(axis=0), nan=0.0)
std = np.nan_to_num(X[train_mask.values].std(axis=0), nan=1.0) + 1e-6
std[std < 1e-6] = 1.0
Xs = np.clip((X - mean) / std, -10.0, 10.0)
Xs = np.nan_to_num(Xs, nan=0.0, posinf=0.0, neginf=0.0)

X_seq, (yt_seq, yo_seq) = make_sequences(Xs, [y_tail, y_onset])
dates_seq = panel["Date"].values[SEQ_LEN - 1:]

tr_i = (dates_seq >= TRAIN_START) & (dates_seq <= TRAIN_END)
va_i = (dates_seq >= VALID_START) & (dates_seq <= VALID_END)
oo_i = (dates_seq >= OOS_START) & (dates_seq <= OOS_END)

X_tr = torch.tensor(X_seq[tr_i], dtype=torch.float32)
yt_tr = torch.tensor(yt_seq[tr_i], dtype=torch.float32)
yo_tr = torch.tensor(yo_seq[tr_i], dtype=torch.float32)
X_va = torch.tensor(X_seq[va_i], dtype=torch.float32).to(DEVICE)
yt_va = torch.tensor(yt_seq[va_i], dtype=torch.float32).to(DEVICE)
yo_va = torch.tensor(yo_seq[va_i], dtype=torch.float32).to(DEVICE)
X_oo = torch.tensor(X_seq[oo_i], dtype=torch.float32).to(DEVICE)

pw_t = torch.tensor([float(min((yt_tr == 0).sum() / max((yt_tr == 1).sum().item(), 1), 8.0))], device=DEVICE)
pw_o = torch.tensor([float(min((yo_tr == 0).sum() / max((yo_tr == 1).sum().item(), 1), 8.0))], device=DEVICE)
print(f"  pos_w tail={pw_t.item():.2f} / onset={pw_o.item():.2f}")

loader = DataLoader(TensorDataset(X_tr, yt_tr, yo_tr), batch_size=BS, shuffle=True, drop_last=True)
input_dim = X_tr.shape[2]


def train_variant(variant_name, model, loss_fn_or_aux, use_pcgrad=False):
    print(f"\n========== {variant_name} ==========")
    optim = torch.optim.Adam(model.parameters(), lr=LR, weight_decay=1e-5)
    best_combined = -1; patience_cnt = 0
    best_state = {k: v.clone() for k, v in model.state_dict().items()}

    for ep in range(EPOCHS):
        model.train(); losses = []
        for xb, yt, yo in loader:
            xb = xb.to(DEVICE); yt = yt.to(DEVICE); yo = yo.to(DEVICE)
            optim.zero_grad()
            lt, lo = model(xb)
            if use_pcgrad:
                # Compute per-task gradients
                bce_t = nn.functional.binary_cross_entropy_with_logits(
                    torch.clamp(lt, -20, 20), yt, pos_weight=pw_t)
                bce_o = nn.functional.binary_cross_entropy_with_logits(
                    torch.clamp(lo, -20, 20), yo, pos_weight=pw_o)
                # task 1 grads
                g1 = torch.autograd.grad(bce_t, list(model.parameters()), retain_graph=True, allow_unused=True)
                g1d = {n: g for (n, _), g in zip(model.named_parameters(), g1) if g is not None}
                # task 2 grads
                g2 = torch.autograd.grad(bce_o, list(model.parameters()), retain_graph=False, allow_unused=True)
                g2d = {n: g for (n, _), g in zip(model.named_parameters(), g2) if g is not None}
                # PCGrad projection
                pc = pcgrad_project([g1d, g2d])
                # Apply combined grad
                for n, p in model.named_parameters():
                    if n in pc:
                        if p.grad is None:
                            p.grad = pc[n].clone()
                        else:
                            p.grad.copy_(pc[n])
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                optim.step()
                losses.append(bce_t.item() + bce_o.item())
            elif loss_fn_or_aux == "auxiliary":
                bce_t = nn.functional.binary_cross_entropy_with_logits(
                    torch.clamp(lt, -20, 20), yt, pos_weight=pw_t)
                bce_o = nn.functional.binary_cross_entropy_with_logits(
                    torch.clamp(lo, -20, 20), yo, pos_weight=pw_o)
                loss = 1.0 * bce_t + 0.2 * bce_o
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                optim.step()
                losses.append(loss.item())
            else:  # uncertainty
                loss = model.uncertainty_loss(lt, yt, lo, yo, pw_t, pw_o)
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                optim.step()
                losses.append(loss.item())

        model.eval()
        with torch.no_grad():
            vlt, vlo = model(X_va)
            vp_t = torch.sigmoid(vlt).cpu().numpy()
            vp_o = torch.sigmoid(vlo).cpu().numpy()
            pa_t = pr_auc(vp_t, yt_va.cpu().numpy())
            pa_o = pr_auc(vp_o, yo_va.cpu().numpy())
            combined = pa_t + pa_o
        if ep % 3 == 0 or ep < 5:
            extra = ""
            if hasattr(model, "log_var_tail"):
                extra = f" | σ_tail={torch.exp(0.5*model.log_var_tail).item():.3f} σ_onset={torch.exp(0.5*model.log_var_onset).item():.3f}"
            print(f"  Ep {ep+1:02d} | loss={np.mean(losses):.4f} | valid tail={pa_t:.4f} onset={pa_o:.4f}{extra}")
        if combined > best_combined:
            best_combined = combined
            best_state = {k: v.clone() for k, v in model.state_dict().items()}
            patience_cnt = 0
        else:
            patience_cnt += 1
            if patience_cnt >= PATIENCE:
                print(f"  Early stop @ ep {ep+1}")
                break

    model.load_state_dict(best_state); model.eval()
    with torch.no_grad():
        olt, olo = model(X_oo)
        op_t = torch.sigmoid(olt).cpu().numpy()
        op_o = torch.sigmoid(olo).cpu().numpy()
    pa_t_oos = pr_auc(op_t, yt_seq[oo_i])
    pa_o_oos = pr_auc(op_o, yo_seq[oo_i])
    print(f"[{variant_name}] OOS PR-AUC tail={pa_t_oos:.4f} / onset={pa_o_oos:.4f}")

    short = variant_name.split("_")[1].lower()  # unc / aux / pcg
    pd.DataFrame({"Date": dates_seq[oo_i], f"p_mtl_{short}": op_t,
                  "y": yt_seq[oo_i], "split": "oos", "target": "y_tail_q15"}
                  ).to_parquet(OUT / f"predictions_mtl_{short}_y_tail_q15.parquet", index=False)
    pd.DataFrame({"Date": dates_seq[oo_i], f"p_mtl_{short}": op_o,
                  "y": yo_seq[oo_i], "split": "oos", "target": "y_onset"}
                  ).to_parquet(OUT / f"predictions_mtl_{short}_y_onset.parquet", index=False)
    return pa_t_oos, pa_o_oos


# Run 3 variants
results = {}
model_unc = MTLUncertainty(input_dim).to(DEVICE)
results["V_UNC"] = train_variant("V_UNC", model_unc, None)
model_aux = MTLAux(input_dim).to(DEVICE)
results["V_AUX"] = train_variant("V_AUX", model_aux, "auxiliary")
model_pcg = MTLAux(input_dim).to(DEVICE)
results["V_PCG"] = train_variant("V_PCG", model_pcg, None, use_pcgrad=True)

print("\n============================================================")
print("[D5* MTL VARIANTS SUMMARY]")
print(f"{'Variant':10} {'tail_q15':>10} {'onset':>10}")
for k, (pt, po) in results.items():
    print(f"{k:10} {pt:>10.4f} {po:>10.4f}")
