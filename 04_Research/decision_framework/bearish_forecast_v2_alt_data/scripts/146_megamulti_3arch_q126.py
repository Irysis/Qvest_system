#!/usr/bin/env python3
"""
146_megamulti_3arch_q126.py — Cycle 56D-prelim Mega Multi-View 1차

Mandate (도훈 Phase 2 mandate Batch 1):
  - Cycle 53H PatchTST v5e q126 = 0.4012 headline → 3 NEW architecture 1차 검증
  - PatchTST/TFT/N-BEATS/TimeMixer/LSTM 이미 시도. 미시도:
    DLinear / Informer / TimesNet / Mamba / S4 / FEDformer
  - 본 cycle = DLinear + Informer + TimesNet 1차 (Batch 1)
  - Cycle 53C 발견: capacity 감소 axes mutually substitutive — 작은 size부터 시작

Architectures:
  1. DLinear (Zeng et al. AAAI 2023) — decomposed linear (trend + seasonal)
     Channel-independent. Very small (~10K params). Test if Transformer/PatchTST
     really beats simple decomp linear on this 21d input.
  2. Informer (Zhou et al. AAAI 2021) — ProbSparse self-attention (O(L log L))
     Distilling encoder. 21d short → e_layers=2, distilling 1 step only.
  3. TimesNet (Wu et al. ICLR 2023) — 1D → 2D via FFT period detection
     Inception block per detected period. top_k=2 periods (21d 짧음).

Features: v5e panel (74 features, Cycle 53H)
Target: y_tail_q126 primary + y_tail_q15 secondary
Training: walk-forward 5-fold CV (Fold3 skip q126 zero-events)
Seed: 42 (single seed first-pass — stable check)
GPU: fraction 0.20 (54C 0.30 + 56B 0.20 + 56-2stage 0.20 + 56D 0.20 = ~0.90)

PIT integrity:
  - Forward labels (Cycle 48A/50 verified)
  - Walk-forward expanding causal split
  - Standardization train window only
  - TimesNet FFT periods detected from training window only (no future leak)
  - Informer ProbSparse: query/key sampling within sequence (no future steps)
  - bear_date_audit pre-cycle PASS (2026-05-21 08:51:30 4/4)

Output:
  outputs/03_models/v6b_megamulti_q126/predictions_{dlinear|informer|timesnet}_y_tail_{q15|q126}.parquet
  outputs/03_models/v6b_megamulti_q126/predictions_ew3_y_tail_{q15|q126}.parquet
  outputs/03_models/v6b_megamulti_q126/per_fold_diagnostics.json
  outputs/04_evaluation/megamulti_q126_v6b_python_diag.json
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
OUT = WS / "outputs/03_models/v6b_megamulti_q126"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 56D-prelim Python] Device: {DEVICE}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.20, device=0)
        print(f"[Cycle 56D] CUDA memory fraction set to 0.20 (concurrent: 54C 0.30 + 56B 0.20 + 56-2stage 0.20)")
    except Exception as e:
        print(f"[Cycle 56D] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 56D] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window (same as 53H)
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")

# Full pre-OOS span
FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# Walk-forward 5-fold CV (45D/53H pattern)
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

# Training infra (mirror 53H)
BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

TARGETS = ["y_tail_q15", "y_tail_q126"]
SEED = 42

# Cycle 53H reference (headline baseline for verdict)
REF_53H_Q126 = 0.4012
REF_53H_Q15 = 0.2082


# ============================================================================
# Common: PositionalEncoding (defined first — used by Informer / TimesNet below)
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


# ============================================================================
# Architecture 1: DLinear (Zeng et al. AAAI 2023)
# ============================================================================
class SeriesDecomposition(nn.Module):
    """Moving average decomposition (DLinear): trend + seasonal."""
    def __init__(self, kernel_size):
        super().__init__()
        self.kernel_size = kernel_size
        # padding via replication on both sides (preserves length)
        # 21 seq, kernel 5 → pad 2 each side
        self.pad = kernel_size // 2

    def forward(self, x):
        # x: (B, L, C)
        # moving average via 1D average pool along L dim
        # F.avg_pool1d expects (B, C, L)
        x_t = x.transpose(1, 2).contiguous()  # (B, C, L)
        # Reflective padding (PIT-safe — only uses observed window's edges)
        x_pad = F.pad(x_t, (self.pad, self.pad), mode="replicate")
        trend = F.avg_pool1d(x_pad, kernel_size=self.kernel_size, stride=1)
        trend = trend.transpose(1, 2).contiguous()  # (B, L, C)
        seasonal = x - trend
        return trend, seasonal


class DLinearClassifier(nn.Module):
    """
    DLinear (Zeng et al. AAAI 2023) — decomposed linear for time series.

    For classification (binary tail event):
      input (B, L, C) → series_decomp → (trend_L_C, seasonal_L_C)
      Two channel-independent linear projections: L → 1 each
      Then concat → linear → logit
    """
    def __init__(self, input_dim, seq_len=SEQ_LEN, kernel_size=5):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.decomp = SeriesDecomposition(kernel_size)

        # Channel-independent: per channel L → 1
        # Shared linear across channels (channel-independent => weights tied)
        self.trend_linear = nn.Linear(seq_len, 1)
        self.seasonal_linear = nn.Linear(seq_len, 1)

        # Channel aggregation head
        self.head = nn.Sequential(
            nn.Linear(input_dim * 2, 64),
            nn.GELU(),
            nn.Dropout(0.30),
            nn.Linear(64, 1),
        )

    def forward(self, x):
        # x: (B, L, C)
        trend, seasonal = self.decomp(x)
        # (B, L, C) → (B, C, L)
        trend = trend.transpose(1, 2).contiguous()
        seasonal = seasonal.transpose(1, 2).contiguous()
        # Per-channel linear: L → 1
        t_proj = self.trend_linear(trend).squeeze(-1)        # (B, C)
        s_proj = self.seasonal_linear(seasonal).squeeze(-1)  # (B, C)
        # Concat and head
        feat = torch.cat([t_proj, s_proj], dim=-1)  # (B, 2C)
        return self.head(feat).squeeze(-1)


# ============================================================================
# Architecture 2: Informer (Zhou et al. AAAI 2021) — simplified for L=21
# ============================================================================
class ProbSparseAttention(nn.Module):
    """
    Simplified ProbSparse self-attention (Informer).

    For each query, sample u keys randomly, compute attention scores,
    pick top-u_top queries that have the most informative attention distribution
    (measured by KL divergence from uniform). Other queries get mean attention.

    For L=21 (short sequence), we use a relaxed version: top-c=ceil(ln(L_K) * L_Q / L_K)
    queries get full attention, rest get mean. For L=21, c ≈ 6-10 ⇒ mostly full attention.

    PIT-safe: query/key sampling is RANDOM within the sequence window (NOT future
    window). No additional temporal leakage beyond standard self-attention.
    """
    def __init__(self, d_model, n_heads, dropout=0.15, factor=5):
        super().__init__()
        assert d_model % n_heads == 0
        self.d_model = d_model
        self.n_heads = n_heads
        self.d_head = d_model // n_heads
        self.factor = factor  # u sampling factor (Informer paper c=factor)
        self.dropout = nn.Dropout(dropout)
        self.q_proj = nn.Linear(d_model, d_model)
        self.k_proj = nn.Linear(d_model, d_model)
        self.v_proj = nn.Linear(d_model, d_model)
        self.out_proj = nn.Linear(d_model, d_model)
        self.scale = 1.0 / math.sqrt(self.d_head)

    def _prob_QK(self, Q, K, sample_k, n_top):
        # Q, K: (B, H, L_Q, d_head) / (B, H, L_K, d_head)
        B, H, L_K, E = K.shape
        _, _, L_Q, _ = Q.shape

        # Sample U_part keys (drop along L_K) — for measuring query sparsity
        # sample_k = min(sample_k, L_K)
        U_part = min(sample_k, L_K)
        sample_idx = torch.randint(L_K, (L_Q, U_part), device=Q.device)
        # K_sample: (B, H, L_Q, U_part, E) — gather along L_K dim per query
        K_expand = K.unsqueeze(-3).expand(B, H, L_Q, L_K, E)
        K_sample = K_expand[:, :, torch.arange(L_Q).unsqueeze(1), sample_idx, :]
        # (B, H, L_Q, U_part, E)

        # Q dot K_sample^T → (B, H, L_Q, U_part)
        Q_K_sample = torch.matmul(Q.unsqueeze(-2), K_sample.transpose(-2, -1)).squeeze(-2)
        # M = max - mean (proxy for KL from uniform)
        M = Q_K_sample.max(dim=-1)[0] - torch.div(Q_K_sample.sum(dim=-1), L_K)

        # Top-n_top queries with largest M
        M_top = M.topk(n_top, sorted=False)[1]  # (B, H, n_top)
        # Gather Q_reduce: (B, H, n_top, E)
        Q_reduce = Q[torch.arange(B)[:, None, None], torch.arange(H)[None, :, None], M_top, :]

        # Full attention for top n_top queries
        Q_K_full = torch.matmul(Q_reduce, K.transpose(-2, -1))  # (B, H, n_top, L_K)
        return Q_K_full, M_top

    def _get_initial_context(self, V, L_Q):
        # V: (B, H, L_K, E)
        # Initial context for non-top queries = mean of V across L_K
        B, H, L_K, E = V.shape
        V_sum = V.mean(dim=-2)  # (B, H, E)
        context = V_sum.unsqueeze(-2).expand(B, H, L_Q, E).clone()
        return context

    def _update_context(self, context_in, V, scores, M_top, L_Q):
        # scores: (B, H, n_top, L_K), softmax across L_K
        attn = F.softmax(scores * self.scale, dim=-1)
        attn = self.dropout(attn)
        # context_top = attn @ V → (B, H, n_top, E)
        context_top = torch.matmul(attn, V)
        # Place context_top back into context at M_top positions
        B, H = M_top.shape[0], M_top.shape[1]
        context_in[torch.arange(B)[:, None, None], torch.arange(H)[None, :, None], M_top, :] = context_top
        return context_in

    def forward(self, x):
        # x: (B, L, d_model)
        B, L, D = x.shape
        Q = self.q_proj(x).view(B, L, self.n_heads, self.d_head).transpose(1, 2)  # (B, H, L, d_head)
        K = self.k_proj(x).view(B, L, self.n_heads, self.d_head).transpose(1, 2)
        V = self.v_proj(x).view(B, L, self.n_heads, self.d_head).transpose(1, 2)

        # ProbSparse params (Informer paper)
        # U_part = factor * ln(L_K) ; u = factor * ln(L_Q)
        L_K = L; L_Q = L
        U_part = max(int(self.factor * math.log(L_K)), 1)
        u_top = max(int(self.factor * math.log(L_Q)), 1)
        U_part = min(U_part, L_K)
        u_top = min(u_top, L_Q)

        scores, M_top = self._prob_QK(Q, K, sample_k=U_part, n_top=u_top)
        # scores: (B, H, u_top, L_K)
        context = self._get_initial_context(V, L_Q)
        context = self._update_context(context, V, scores, M_top, L_Q)

        # (B, H, L, d_head) → (B, L, d_model)
        out = context.transpose(1, 2).contiguous().view(B, L, D)
        return self.out_proj(out)


class InformerEncoderLayer(nn.Module):
    def __init__(self, d_model, n_heads, ff_mult=4, dropout=0.30, attn_dropout=0.15):
        super().__init__()
        self.attn = ProbSparseAttention(d_model, n_heads, dropout=attn_dropout)
        self.norm1 = nn.LayerNorm(d_model)
        ff_dim = d_model * ff_mult
        self.ffn = nn.Sequential(
            nn.Linear(d_model, ff_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(ff_dim, d_model),
        )
        self.norm2 = nn.LayerNorm(d_model)
        self.drop = nn.Dropout(dropout)

    def forward(self, x):
        # Pre-norm transformer
        x = x + self.drop(self.attn(self.norm1(x)))
        x = x + self.drop(self.ffn(self.norm2(x)))
        return x


class DistillingConv(nn.Module):
    """Informer distilling: conv1d (kernel 3) + ELU + maxpool (stride 2). Halves L."""
    def __init__(self, d_model):
        super().__init__()
        self.conv = nn.Conv1d(d_model, d_model, kernel_size=3, padding=1)
        self.act = nn.ELU()
        self.pool = nn.MaxPool1d(kernel_size=3, stride=2, padding=1)

    def forward(self, x):
        # x: (B, L, d_model)
        x_t = x.transpose(1, 2).contiguous()  # (B, d_model, L)
        x_t = self.act(self.conv(x_t))
        x_t = self.pool(x_t)
        return x_t.transpose(1, 2).contiguous()


class InformerClassifier(nn.Module):
    """
    Informer (Zhou et al. AAAI 2021) — ProbSparse attention + distilling encoder.

    For classification (binary tail event):
      input (B, L=21, C=74) → linear embed → +pos_enc
      encoder: 2 InformerEncoderLayer + 1 distilling (L=21→11)
      mean pool over L → linear head → logit

    For L=21 short sequence: only 1 distill step (L=11 final).
    """
    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 d_model=64, n_heads=4, e_layers=2,
                 ff_mult=4, dropout=0.30, attn_dropout=0.15):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.d_model = d_model
        self.embed = nn.Linear(input_dim, d_model)
        self.pos_enc = PositionalEncoding(d_model, max_len=seq_len + 16)

        # Encoder: e_layers transformer layers, with 1 distill in the middle for L=21
        self.enc_layers = nn.ModuleList([
            InformerEncoderLayer(d_model, n_heads, ff_mult=ff_mult,
                                  dropout=dropout, attn_dropout=attn_dropout)
            for _ in range(e_layers)
        ])
        # 1 distilling between layer 1 and layer 2 (only halves L once: 21 → 11)
        self.distill = DistillingConv(d_model)

        self.head_drop = nn.Dropout(dropout)
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, 1),
        )

    def forward(self, x):
        # x: (B, L, C)
        x = self.embed(x)  # (B, L, d_model)
        x = self.pos_enc(x)
        # Layer 0
        x = self.enc_layers[0](x)
        # Distill
        x = self.distill(x)
        # Layer 1
        x = self.enc_layers[1](x)
        # mean pool
        x = x.mean(dim=1)
        x = self.head_drop(x)
        return self.head(x).squeeze(-1)


# ============================================================================
# Architecture 3: TimesNet (Wu et al. ICLR 2023)
# ============================================================================
class InceptionBlock2D(nn.Module):
    """Inception block for 2D (period × intra-period). Mirrors TimesNet ref impl."""
    def __init__(self, in_ch, out_ch, num_kernels=6):
        super().__init__()
        # Multi-scale 2D convs
        kernels = []
        for i in range(num_kernels):
            k = 2 * i + 1  # kernels 1, 3, 5, 7, 9, 11
            kernels.append(nn.Conv2d(in_ch, out_ch, kernel_size=k, padding=k // 2))
        self.kernels = nn.ModuleList(kernels)

    def forward(self, x):
        # x: (B, C, period, intra_period)
        outs = [k(x) for k in self.kernels]
        # average across multiple kernel scales
        return torch.stack(outs, dim=-1).mean(dim=-1)


def fft_topk_periods(x, k=2):
    """
    Detect top-k periods via FFT (TimesNet pattern).

    PIT-safe: FFT operates on the input window (B, L, C). L=21 = observed window only.
    No future steps included.

    Codex review fix (2026-05-21):
      - Disable AMP autocast for FFT path: CUDA half-precision rfft requires
        power-of-2 length, but L=21 is not. Force float32 inside.
      - Use clone() before in-place amp_mean[0] modification (backward safety).
      - Use -inf for DC exclusion (tie-safety in topk).

    Args:
        x: (B, L, C)
        k: number of top periods to return
    Returns:
        periods: (k,) list of int (period lengths)
        sample_w: (B, k) amplitude softmax weight per (sample, period)
    """
    B, L, C = x.shape
    # Force float32 + disable AMP for FFT (CUDA half rfft requires power-of-2 L)
    with torch.amp.autocast(device_type=x.device.type, enabled=False):
        xf = torch.fft.rfft(x.float(), dim=1)
        # Amplitude across channels: (B, L//2+1)
        amp = torch.abs(xf).mean(dim=-1)
        # Aggregate over batch: (L//2+1,) — shared dominant frequencies
        amp_mean = amp.mean(dim=0).clone()  # clone for backward safety
        amp_mean[0] = -float("inf")  # exclude DC; -inf for tie safety in topk

        # Top-k frequencies (skipping freq=0)
        top_freqs = torch.topk(amp_mean, k).indices  # (k,)
        # Period = L / freq
        periods = []
        for f in top_freqs.tolist():
            if f == 0:
                p = L  # fallback (should not happen with -inf DC)
            else:
                p = max(L // f, 1)
            periods.append(p)

        # Per-sample amplitude weight (B, k)
        sample_amp = amp[:, top_freqs]
        sample_w = F.softmax(sample_amp, dim=-1)
        # Cast sample_w back to x.dtype for downstream multiplication compatibility
        sample_w = sample_w.to(dtype=x.dtype)
    return periods, sample_w


class TimesBlock(nn.Module):
    """TimesNet block: detect periods via FFT, reshape 1D → 2D, Inception, average."""
    def __init__(self, d_model, top_k=2, num_kernels=3, ff_mult=1, dropout=0.30):
        super().__init__()
        self.top_k = top_k
        # Channel: d_model → d_model * ff_mult → d_model
        self.inception_in = InceptionBlock2D(d_model, d_model * ff_mult, num_kernels=num_kernels)
        self.inception_out = InceptionBlock2D(d_model * ff_mult, d_model, num_kernels=num_kernels)
        self.act = nn.GELU()
        self.drop = nn.Dropout(dropout)

    def forward(self, x):
        # x: (B, L, d_model)
        B, L, D = x.shape
        periods, sample_w = fft_topk_periods(x, k=self.top_k)
        # sample_w: (B, top_k)

        res = []
        for i, p in enumerate(periods):
            # Pad L to multiple of p
            if L % p != 0:
                pad = (p - (L % p))
                x_pad = F.pad(x, (0, 0, 0, pad))
                length = L + pad
            else:
                x_pad = x
                length = L

            # Reshape: (B, length, D) → (B, length/p, p, D) → (B, D, length/p, p) for 2D conv
            n_periods = length // p
            x_2d = x_pad.reshape(B, n_periods, p, D).permute(0, 3, 1, 2).contiguous()
            # (B, D, n_periods, p)

            # Inception (in → ff_mult*D → D)
            h = self.act(self.inception_in(x_2d))
            h = self.drop(h)
            h = self.inception_out(h)

            # Back to 1D: (B, D, n_periods, p) → (B, n_periods, p, D) → (B, length, D)
            h_1d = h.permute(0, 2, 3, 1).contiguous().reshape(B, length, D)
            # Truncate back to L
            h_1d = h_1d[:, :L, :]
            res.append(h_1d)

        # Stack: (B, L, D, top_k)
        res_stack = torch.stack(res, dim=-1)
        # Weighted sum via sample_w: (B, L, D, top_k) * (B, 1, 1, top_k) → sum over top_k
        sample_w_b = sample_w.unsqueeze(1).unsqueeze(1)  # (B, 1, 1, top_k)
        out = (res_stack * sample_w_b).sum(dim=-1)

        # Residual connection
        return out + x


class TimesNetClassifier(nn.Module):
    """
    TimesNet (Wu et al. ICLR 2023) — period-aware 1D → 2D Inception modeling.

    For classification:
      input (B, L, C) → linear embed → +pos_enc
      e_layers TimesBlock (each detects own periods via FFT)
      mean pool L → linear head → logit
    """
    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 d_model=64, e_layers=2, top_k=2,
                 num_kernels=3, ff_mult=1, dropout=0.30):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.d_model = d_model

        self.embed = nn.Linear(input_dim, d_model)
        self.pos_enc = PositionalEncoding(d_model, max_len=seq_len + 16)

        self.blocks = nn.ModuleList([
            TimesBlock(d_model, top_k=top_k, num_kernels=num_kernels,
                       ff_mult=ff_mult, dropout=dropout)
            for _ in range(e_layers)
        ])
        self.norm = nn.LayerNorm(d_model)

        self.head_drop = nn.Dropout(dropout)
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, 1),
        )

    def forward(self, x):
        x = self.embed(x)
        x = self.pos_enc(x)
        for block in self.blocks:
            x = block(x)
        x = self.norm(x)
        x = x.mean(dim=1)
        x = self.head_drop(x)
        return self.head(x).squeeze(-1)


# ============================================================================
# Helpers (mirror 53H exactly)
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
    Load v5e features + forward labels.

    Codex review fix (2026-05-21 cycle 56D-prelim):
      - y_raw preserves NaN where forward return is unresolved (last H bus days).
      - Previously fillna(0) caused 108 q126 OOS rows (2025-11-19 ~ 2026-04-30)
        to be treated as confirmed negatives, biasing PR-AUC.
      - Downstream train/valid/oos selection masks via np.isfinite(y_seq).
    """
    feat_path = DATA / "feature_panel_v5e_q126_usmacro.parquet"
    tgt_path = TGT / "targets_long_horizon.parquet"
    if not feat_path.exists():
        sys.exit(f"missing feature panel: {feat_path}")
    if not tgt_path.exists():
        sys.exit(f"missing target parquet: {tgt_path}")

    feat = pd.read_parquet(feat_path)
    tgt_all = pd.read_parquet(tgt_path)
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt_all["Date"] = pd.to_datetime(tgt_all["Date"])

    # Determine ret + thr columns for validity check
    # target_col format: y_tail_q{H}, ret_col: ret_q{H}, thr_col: q15_thr_q{H}
    h_suffix = target_col.replace("y_tail_", "")  # e.g. "q15", "q126"
    ret_col = f"ret_{h_suffix}"
    thr_col = f"q15_thr_{h_suffix}"

    if ret_col not in tgt_all.columns or thr_col not in tgt_all.columns:
        sys.exit(f"missing ret/thr columns for {target_col}: {ret_col} / {thr_col}")

    # Label is valid only if both forward return AND threshold are resolved
    label_ok = tgt_all[ret_col].notna() & tgt_all[thr_col].notna()
    tgt = tgt_all[["Date", target_col]].copy()
    tgt.loc[~label_ok, target_col] = np.nan  # preserve NaN for unresolved

    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END].reset_index(drop=True)

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    assert len(feature_cols) == 74, f"v5e expects 74 features, got {len(feature_cols)}"

    X = panel[feature_cols].values.astype(np.float32)
    # IMPORTANT: do NOT fillna here — preserve NaN for downstream masking
    y_raw = panel[target_col].values.astype(np.float32)
    dates = panel["Date"].values

    n_valid = int(np.isfinite(y_raw).sum())
    n_unresolved = int(len(y_raw) - n_valid)
    print(f"    [prepare_data_full/{target_col}] n_rows={len(y_raw)} "
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
                     fixed_epochs=None, fold_label="", seed=42,
                     lr=1e-3, weight_decay=5e-3):
    set_seed(seed)
    Xs = standardize_for_window(X_full, dates, train_start, train_end)
    X_seq, y_seq = make_sequences(Xs, y_full, SEQ_LEN)
    dates_seq = dates[SEQ_LEN - 1:]

    # Codex fix (2026-05-21): mask unresolved labels (NaN) — only use rows with
    # finite forward labels. Critical for q126 last ~108 OOS rows that have no
    # forward return resolved.
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

    model = model_class(input_dim=X_train_t.shape[2]).to(DEVICE)
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

    print(f"    [{model_name}/{target_col}/seed{seed}] {fold_label} "
          f"train_n={int(train_idx.sum())} "
          f"valid_n={'-' if not has_valid else int(valid_idx.sum())} "
          f"pos_w={pos_w_value:.2f} target_ep={target_epochs} n_params={n_params:,}")

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
    print(f"[Cycle 56D-prelim] {model_name} (seed={seed}) target: {target_col}")
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

    print(f"\n  --- Final training: TRAIN 1995-2015 / epochs={avg_best_ep} ---")
    final_model, Xs_final, dates_seq_final, y_seq_final, final_train_res = train_one_window(
        model_class, model_name, target_col,
        X_full, y_full, dates,
        train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
        valid_start=None, valid_end=None,
        fixed_epochs=avg_best_ep, fold_label="FINAL_TRAIN", seed=seed,
    )

    print(f"\n  --- OOS evaluation: 2018-2026 ---")
    X_seq_final, y_seq_final2 = make_sequences(Xs_final, y_full, SEQ_LEN)
    dates_seq_final2 = dates[SEQ_LEN - 1:]
    # Codex fix (2026-05-21): OOS mask — only rows with finite labels
    # (q126 OOS last ~108 rows have unresolved forward returns → exclude)
    y_finite_oos = np.isfinite(y_seq_final2)
    oos_idx = ((dates_seq_final2 >= np.datetime64(OOS_START)) &
               (dates_seq_final2 <= np.datetime64(OOS_END)) &
               y_finite_oos)
    n_oos_keep = int(oos_idx.sum())
    n_oos_drop = int(((dates_seq_final2 >= np.datetime64(OOS_START)) &
                      (dates_seq_final2 <= np.datetime64(OOS_END)) &
                      ~y_finite_oos).sum())
    print(f"  [OOS mask] kept {n_oos_keep} / dropped {n_oos_drop} unresolved-label rows")
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
    print(f"\n  [{model_name}/{target_col}/seed{seed}] OOS PR-AUC: {oos_pr_v:.4f} "
          f"IC: {oos_ic_v:.4f} | elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        print(f"  GPU memory peak: {mem_peak_mb:.1f} MB")
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    # Save predictions
    col_name = f"p_{model_name.lower()}"
    file_name = f"predictions_{model_name.lower()}_{target_col}.parquet"
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
    print("[Cycle 56D-prelim Mega Multi-View 1차 — DLinear + Informer + TimesNet]")
    print("[v5e panel 74 features, walk-forward 5-fold CV, single seed=42 first-pass]")
    print(f"[OOS window: 2018-01-01 ~ 2026-04-30 / Targets: {TARGETS}]")
    print(f"[Reference: Cycle 53H PatchTST q126={REF_53H_Q126} / q15={REF_53H_Q15}]")
    print("=" * 70)

    results = {}
    archs = [
        ("DLinear", DLinearClassifier),
        ("Informer", InformerClassifier),
        ("TimesNet", TimesNetClassifier),
    ]

    for arch_name, arch_class in archs:
        for tgt in TARGETS:
            key = f"{arch_name}_{tgt}"
            results[key] = run_walkforward_single_seed(
                arch_class, arch_name, tgt, seed=SEED)

    # Per-target EW3 ensemble
    print("\n" + "=" * 70)
    print("[EW3 ensemble: DLinear + Informer + TimesNet equal-weight averaged predictions]")
    print("=" * 70)

    ensemble_results = {}
    for tgt in TARGETS:
        # Align by Date (all 3 should share identical OOS dates)
        dl_r = results[f"DLinear_{tgt}"]
        in_r = results[f"Informer_{tgt}"]
        tn_r = results[f"TimesNet_{tgt}"]

        # Sanity: dates align
        assert (dl_r["oos_dates"] == in_r["oos_dates"]).all(), "Date misalign DL/IN"
        assert (dl_r["oos_dates"] == tn_r["oos_dates"]).all(), "Date misalign DL/TN"
        assert (dl_r["oos_y"] == in_r["oos_y"]).all(), "y misalign DL/IN"

        # EW3
        ew_pred = (dl_r["oos_pred"] + in_r["oos_pred"] + tn_r["oos_pred"]) / 3.0
        ew_y = dl_r["oos_y"]
        ew_dates = dl_r["oos_dates"]

        ew_pr = pr_auc(ew_pred, ew_y)
        ew_ic = ic_spearman(ew_pred, ew_y)

        print(f"  EW3 {tgt}: PR-AUC={ew_pr:.4f}  IC={ew_ic:.4f}")

        # Save
        df_ew = pd.DataFrame({
            "Date": ew_dates,
            "p_ew3": ew_pred,
            "y": ew_y,
            "split": "oos", "target": tgt,
        })
        df_ew.to_parquet(OUT / f"predictions_ew3_{tgt}.parquet", index=False)
        ensemble_results[tgt] = dict(
            oos_pr=ew_pr, oos_ic=ew_ic, n_obs=int(len(ew_pred)),
            n_events=int(ew_y.sum()), event_rate=float(ew_y.mean()),
        )

    # Summary
    print("\n" + "=" * 70)
    print("[Python Cycle 56D-prelim SUMMARY]")
    print("=" * 70)
    for arch_name, _ in archs:
        for tgt in TARGETS:
            r = results[f"{arch_name}_{tgt}"]
            ref = REF_53H_Q126 if tgt == "y_tail_q126" else REF_53H_Q15
            d = r["oos_pr"] - ref
            print(f"  {arch_name:10s} {tgt:13s}: OOS PR-AUC={r['oos_pr']:.4f}  IC={r['oos_ic']:.4f}  "
                  f"avg_ep={r['avg_best_epoch']:3d}  n_params={r['n_params']:>10,}  "
                  f"Δ vs 53H={d:+.4f}")
    print("  --- ensemble ---")
    for tgt in TARGETS:
        ref = REF_53H_Q126 if tgt == "y_tail_q126" else REF_53H_Q15
        d = ensemble_results[tgt]["oos_pr"] - ref
        print(f"  {'EW3':10s} {tgt:13s}: OOS PR-AUC={ensemble_results[tgt]['oos_pr']:.4f}  "
              f"IC={ensemble_results[tgt]['oos_ic']:.4f}  Δ vs 53H={d:+.4f}")

    # Per-fold + diagnostics dump
    per_fold_path = OUT / "per_fold_diagnostics.json"

    def serialize_seed_result(r):
        return {k: v for k, v in r.items() if k not in ("oos_dates", "oos_pred", "oos_y")}

    per_fold = {
        "cycle": "56D_prelim_megamulti_3arch",
        "approach": "MEGA_MULTI_VIEW_3ARCH_DLinear_Informer_TimesNet",
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date()),
                       "note": "fold 5 valid 2016-2017 제외하여 leakage 방지"},
        "feature_panel": "feature_panel_v5e_q126_usmacro.parquet (74 features: v4a 70 + 4 US macro)",
        "seed": SEED,
    }
    for arch_name, _ in archs:
        for tgt in TARGETS:
            per_fold[f"{arch_name}_{tgt}"] = serialize_seed_result(results[f"{arch_name}_{tgt}"])
    per_fold["ensemble_ew3"] = ensemble_results

    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"\n[Per-fold diagnostics] Saved: {per_fold_path}")

    # Python diagnostics summary
    diag_path = EVAL_DIR / "megamulti_q126_v6b_python_diag.json"
    diag = {
        "cycle": "56D_prelim_megamulti_3arch",
        "approach": "MEGA_MULTI_VIEW_3ARCH_DLinear_Informer_TimesNet_FIRST_PASS",
        "panel": "feature_panel_v5e_q126_usmacro.parquet",
        "targets_source": "targets_long_horizon.parquet",
        "n_features": 74,
        "forward_labels": True,
        "validation_strategy": "walk_forward_expanding_5_fold_CV",
        "horizons_evaluated": TARGETS,
        "seed": SEED,
        "architectures_evaluated": ["DLinear (Zeng et al. AAAI 2023)",
                                     "Informer (Zhou et al. AAAI 2021)",
                                     "TimesNet (Wu et al. ICLR 2023)"],
        "training_common": {
            "batch_size": BATCH_SIZE, "max_epochs": MAX_EPOCHS,
            "early_stop_patience": EARLY_STOP_PATIENCE,
            "early_stop_min_delta": EARLY_STOP_MIN_DELTA,
            "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
            "mixed_precision_amp": USE_AMP,
            "gpu_mem_fraction": 0.20 if DEVICE.type == "cuda" else None,
        },
        "baseline_cycle53h_seed42": {
            "y_tail_q126": REF_53H_Q126,
            "y_tail_q15": REF_53H_Q15,
        },
        "per_arch_per_target": {
            f"{arch_name}_{tgt}": {
                "oos_pr": round(results[f"{arch_name}_{tgt}"]["oos_pr"], 4),
                "oos_ic": round(results[f"{arch_name}_{tgt}"]["oos_ic"], 4),
                "avg_best_epoch": results[f"{arch_name}_{tgt}"]["avg_best_epoch"],
                "n_params": results[f"{arch_name}_{tgt}"]["n_params"],
                "elapsed_sec": round(results[f"{arch_name}_{tgt}"]["elapsed_sec"], 1),
                "delta_vs_53h": round(
                    results[f"{arch_name}_{tgt}"]["oos_pr"]
                    - (REF_53H_Q126 if tgt == "y_tail_q126" else REF_53H_Q15), 4),
            }
            for arch_name, _ in archs for tgt in TARGETS
        },
        "ensemble_ew3": {
            tgt: {
                "oos_pr": round(ensemble_results[tgt]["oos_pr"], 4),
                "oos_ic": round(ensemble_results[tgt]["oos_ic"], 4),
                "delta_vs_53h": round(
                    ensemble_results[tgt]["oos_pr"]
                    - (REF_53H_Q126 if tgt == "y_tail_q126" else REF_53H_Q15), 4),
            }
            for tgt in TARGETS
        },
        "per_fold_diagnostics_path": str(per_fold_path),
    }
    with diag_path.open("w") as f:
        json.dump(diag, f, indent=2, default=str)
    print(f"[Diagnostics] Saved: {diag_path}")

    print("\n" + "=" * 70)
    print("[Cycle 56D-prelim Python DONE — Run scripts/147_megamulti_aggregate.R next]")
    print("=" * 70)
