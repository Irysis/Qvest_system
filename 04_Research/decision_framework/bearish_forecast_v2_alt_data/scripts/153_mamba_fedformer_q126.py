#!/usr/bin/env python3
"""
153_mamba_fedformer_q126.py — Cycle 56D-Batch2 (Mamba + FEDformer)

Mandate (Q-Lead self-launched batch 2):
  - 56D-prelim 완료: DLinear/Informer/TimesNet 모두 q126에서 inferior vs PatchTST 53H 0.4016
  - TimesNet positive IC +0.0779 (유일) + Informer period-robust 3/3 (유일)
  - 미시도 architecture family: Mamba (state-space) / S4 / FEDformer (frequency)
  - 본 batch: Mamba + FEDformer 2종 (Batch 2)

Architectures:
  1. Mamba (Albert Gu et al. 2023) — Selective state-space model (S6 block)
     Linear-time O(L) sequence processing (attention 우회)
     Selective hidden state update (input-dependent gating B(x), C(x), Δ(x))
     PIT-safe: forward-only recurrence (causal by construction)
     Hyperparams: d_model=64, d_state=16, d_conv=4, expand=2, n_layers=2

  2. FEDformer (Zhou et al. 2022) — Frequency Enhanced Decomposed Transformer
     Trend-seasonal decomposition (moving avg, same as DLinear)
     Frequency enhanced attention: top_k=3 Fourier modes
     PIT-safe: FFT operates on train window only; no future steps
     Hyperparams: d_model=64, n_heads=4, e_layers=2, modes=3 (top frequencies), dropout=0.30

Features: v5e panel (74 features, Cycle 53H)
Target: y_tail_q126 primary + y_tail_q15 secondary
Training: walk-forward 5-fold CV (Fold3 skip q126 zero-events)
Strict determinism inherit 54A FIXED: CUBLAS_WORKSPACE_CONFIG / cudnn.deterministic
                                       / DataLoader generator / use_deterministic_algorithms
Logit-collapse detector + reseed rescue (up to 4 seeds [42,43,44,45])
GPU fraction: 0.20 (concurrent cycles)

PIT integrity:
  - Forward labels: prefer targets_long_horizon_observable.parquet (NaN propagation applied)
    fallback: targets_long_horizon.parquet (fillna(0) preserved, with explicit mask)
  - Walk-forward expanding causal split
  - Standardization train window only
  - Mamba selective gating: input-dependent state update is FORWARD-ONLY (causal)
  - FEDformer FFT: train window only (no future window)
  - bear_date_audit pre-cycle PASS (2026-05-21 09:52:37 4/4)

FFT under AMP fix (56D Cycle 56D inheritance):
  - rfft on L=21 (not power-of-2) requires float32; disable autocast
  - clone() before in-place amp_mean[0] modification
  - -inf for DC exclusion (tie safety in topk)

Output:
  outputs/03_models/v6d_mamba_fedformer/predictions_{mamba|fedformer|ew2}_y_tail_{q15|q126}.parquet
  outputs/03_models/v6d_mamba_fedformer/per_fold_diagnostics.json
  outputs/03_models/v6d_mamba_fedformer/final_attempts.json (reseed log)
  outputs/04_evaluation/mamba_fedformer_v6d_python_diag.json
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
OUT = WS / "outputs/03_models/v6d_mamba_fedformer"
OUT.mkdir(parents=True, exist_ok=True)
EVAL_DIR = WS / "outputs/04_evaluation"
EVAL_DIR.mkdir(parents=True, exist_ok=True)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"[Cycle 56D-Batch2] Device: {DEVICE}")

# Apply strict determinism flags
torch.backends.cudnn.deterministic = True
torch.backends.cudnn.benchmark = False
try:
    torch.use_deterministic_algorithms(True, warn_only=True)
    print("[Cycle 56D-Batch2] torch.use_deterministic_algorithms(True, warn_only=True) set")
except Exception as e:
    print(f"[Cycle 56D-Batch2] determinism flag failed: {e}")

if DEVICE.type == "cuda":
    try:
        torch.cuda.set_per_process_memory_fraction(0.20, device=0)
        print("[Cycle 56D-Batch2] CUDA memory fraction set to 0.20 (concurrent cycles)")
    except Exception as e:
        print(f"[Cycle 56D-Batch2] CUDA fraction set failed: {e}")
    USE_AMP = True
    print(f"[Cycle 56D-Batch2] Mixed precision (torch.cuda.amp): {USE_AMP}")
else:
    USE_AMP = False

# OOS window (same as 53H / 146)
OOS_START = pd.Timestamp("2018-01-01")
OOS_END = pd.Timestamp("2026-04-30")
FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

SEQ_LEN = 21

# Walk-forward 5-fold CV (mirror 53H / 146)
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

# Training infra (mirror 53H / 146)
BATCH_SIZE = 96
MAX_EPOCHS = 80
EARLY_STOP_PATIENCE = 15
EARLY_STOP_MIN_DELTA = 0.0005
GRAD_CLIP_NORM = 1.0
WARMUP_STEPS = 500
NUM_WORKERS = 0

PT_LR = 1e-3
PT_WEIGHT_DECAY = 5e-3

TARGETS = ["y_tail_q15", "y_tail_q126"]
SEED_BASE = 42
RESEED_MAX = 3  # SEED+1, +2, +3 if logit collapse

# Cycle 53H reference baseline (forge mask-clean per 147 aggregate convention)
REF_53H_Q126 = 0.4012  # raw fillna(0) headline
REF_53H_Q15 = 0.2082  # raw fillna(0) headline
# 56D-prelim 3-arch references
REF_56D_DLINEAR_Q126 = 0.2039
REF_56D_INFORMER_Q126 = 0.2300
REF_56D_TIMESNET_Q126 = 0.2795


# ============================================================================
# Common: PositionalEncoding (used by FEDformer)
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
# Architecture 1: Mamba (Albert Gu et al. 2023)
#
# Simplified Selective SSM (S6 block) — PyTorch native port
#   y(t) = C(t) h(t) + D x(t)
#   h(t+1) = exp(A·Δ(t)) h(t) + Δ(t) B(t) x(t)
#
#   where Δ, B, C are FUNCTIONS of input x(t) (selective gating)
#   A is state matrix (negative real diag for stability, learned)
#   D is residual scalar (learned)
#
# Forward-only recurrence: causal by construction. No future leak.
#
# References:
#   - Gu & Dao 2023 "Mamba: Linear-Time Sequence Modeling with Selective State Spaces"
#   - github.com/state-spaces/mamba (selective_scan_fn reference)
#   - github.com/johnma2006/mamba-minimal (clean PyTorch reference)
# ============================================================================

class MambaBlock(nn.Module):
    """
    Single Mamba (S6) block: input projection → 1D conv → selective SSM → out projection.

    Args:
      d_model: hidden dim
      d_state: SSM state dim N (Gu 2023 default 16)
      d_conv: 1D conv kernel size for short-range dependency mixing (Gu default 4)
      expand: MLP expansion factor for inner state (Gu default 2)

    PIT-safe:
      - 1D conv uses CAUSAL padding (left-pad only); no future leak
      - Selective scan is FORWARD-ONLY recurrence
      - No batch normalization (would leak across batch dim)
    """
    def __init__(self, d_model, d_state=16, d_conv=4, expand=2, dt_rank=None,
                 dt_min=0.001, dt_max=0.1, dt_init_floor=1e-4):
        super().__init__()
        self.d_model = d_model
        self.d_state = d_state
        self.d_conv = d_conv
        self.expand = expand
        self.d_inner = int(expand * d_model)
        self.dt_rank = dt_rank or max(1, d_model // 16)

        # Input projection: d_model → 2*d_inner (one half for x, one for residual gate z)
        self.in_proj = nn.Linear(d_model, 2 * self.d_inner, bias=False)

        # 1D conv on x with CAUSAL padding (left only)
        # Conv1d with groups=d_inner = channel-wise (depthwise) conv
        self.conv1d = nn.Conv1d(
            in_channels=self.d_inner, out_channels=self.d_inner,
            kernel_size=d_conv, groups=self.d_inner,
            padding=d_conv - 1,  # left+right pad; we trim right (causal)
            bias=True,
        )

        # x_proj: project x to (dt_rank + d_state + d_state) for Δ, B, C
        self.x_proj = nn.Linear(self.d_inner, self.dt_rank + 2 * self.d_state, bias=False)

        # dt_proj: project dt_rank → d_inner for Δ (with special init)
        self.dt_proj = nn.Linear(self.dt_rank, self.d_inner, bias=True)
        # Special Δ initialization per Gu 2023 (random in [log(dt_min), log(dt_max)])
        dt_init_std = self.dt_rank**-0.5 * 1.0
        nn.init.uniform_(self.dt_proj.weight, -dt_init_std, dt_init_std)
        dt = torch.exp(
            torch.rand(self.d_inner) * (math.log(dt_max) - math.log(dt_min)) + math.log(dt_min)
        ).clamp(min=dt_init_floor)
        inv_dt = dt + torch.log(-torch.expm1(-dt))
        with torch.no_grad():
            self.dt_proj.bias.copy_(inv_dt)
        # Don't reinitialize dt_proj.bias (kept above)

        # A: HiPPO-like negative real diagonal init (per Mamba ref)
        # A_log = log(arange(1, d_state+1)) per channel d_inner
        A = torch.arange(1, d_state + 1, dtype=torch.float32).repeat(self.d_inner, 1)
        # store as log for stable parametrization (A = -exp(A_log) for stability)
        self.A_log = nn.Parameter(torch.log(A))

        # D: skip-connection scalar per channel
        self.D = nn.Parameter(torch.ones(self.d_inner))

        # Output projection
        self.out_proj = nn.Linear(self.d_inner, d_model, bias=False)

    def forward(self, x):
        """
        x: (B, L, d_model)
        returns: (B, L, d_model)
        """
        B, L, D = x.shape

        # in_proj split into x_in and z (residual gate)
        x_and_z = self.in_proj(x)  # (B, L, 2*d_inner)
        x_in, z = x_and_z.chunk(2, dim=-1)  # each (B, L, d_inner)

        # 1D conv on x_in with CAUSAL trimming
        # Conv1d expects (B, d_inner, L)
        x_in_t = x_in.transpose(1, 2).contiguous()  # (B, d_inner, L)
        x_in_t = self.conv1d(x_in_t)  # (B, d_inner, L + d_conv - 1)
        # Causal: keep first L positions (drop last d_conv-1)
        x_in_t = x_in_t[:, :, :L]
        x_in = x_in_t.transpose(1, 2).contiguous()  # (B, L, d_inner)
        x_in = F.silu(x_in)

        # Selective SSM: compute Δ, B, C from x_in
        # PIT-safe: Δ, B, C are computed POSITION-WISE from x_in[t] (no future)
        y = self._selective_scan(x_in)  # (B, L, d_inner)

        # Apply residual gate z
        y = y * F.silu(z)

        # Output projection
        out = self.out_proj(y)  # (B, L, d_model)
        return out

    def _selective_scan(self, x):
        """
        Selective scan (S6 algorithm). x: (B, L, d_inner) → (B, L, d_inner).

        Algorithm:
          1) Project x → (Δ, B, C) per position
          2) Discretize A, B by Δ: A_bar = exp(Δ A), B_bar = Δ B
          3) Sequential recurrence: h(t+1) = A_bar h(t) + B_bar x(t)
             y(t) = C h(t) + D x(t)

        PIT-safe: FORWARD-ONLY recurrence (causal).

        FFT-free implementation (slower but PyTorch-native, fp32-stable for AMP).
        """
        B, L, d_inner = x.shape
        N = self.d_state

        # Stable A: A = -exp(A_log), so A is negative real diag
        A = -torch.exp(self.A_log.float())  # (d_inner, d_state)
        D = self.D.float()  # (d_inner,)

        # x_proj: x → (Δ_rank, B, C)
        # Note: cast x_in to float32 for SSM stability under AMP
        x_proj = self.x_proj(x)  # (B, L, dt_rank + 2*d_state)
        dt_rank = self.dt_rank
        dt_raw, B_in, C_in = torch.split(x_proj, [dt_rank, N, N], dim=-1)
        # dt_proj: dt_raw → d_inner, then softplus for positive Δ
        delta = self.dt_proj(dt_raw)  # (B, L, d_inner)
        # softplus per Mamba (with bias init biasing toward dt_min..dt_max)
        delta = F.softplus(delta)
        # Disable AMP for the SSM scan (fp32 stability with long recurrences)
        with torch.amp.autocast(device_type=x.device.type, enabled=False):
            delta = delta.float()
            B_in = B_in.float()
            C_in = C_in.float()
            x_f32 = x.float()

            # Discretize A, B (per Gu 2023 Eq. 3)
            # A_bar: (B, L, d_inner, d_state) = exp(delta.unsqueeze(-1) * A)
            #   delta: (B, L, d_inner) → (B, L, d_inner, 1)
            #   A: (d_inner, d_state) → (1, 1, d_inner, d_state)
            delta_exp = delta.unsqueeze(-1)  # (B, L, d_inner, 1)
            A_bar = torch.exp(delta_exp * A.unsqueeze(0).unsqueeze(0))  # (B, L, d_inner, d_state)
            # B_bar: (B, L, d_inner, d_state) = delta * B
            #   B_in: (B, L, d_state) → (B, L, 1, d_state)
            B_bar = delta_exp * B_in.unsqueeze(-2)  # (B, L, d_inner, d_state)

            # Sequential scan: h_t = A_bar_t * h_{t-1} + B_bar_t * x_t
            #   h(t): (B, d_inner, d_state)
            h = torch.zeros(B, d_inner, N, dtype=torch.float32, device=x.device)
            ys = []
            for t in range(L):
                # x_f32[:, t]: (B, d_inner)
                # B_bar[:, t]: (B, d_inner, d_state)
                # h = A_bar_t * h + B_bar_t * x_t (broadcast x_t over d_state)
                h = A_bar[:, t] * h + B_bar[:, t] * x_f32[:, t].unsqueeze(-1)
                # y_t = C_t @ h_t (per d_inner channel): sum over d_state
                # C_in[:, t]: (B, d_state) → (B, 1, d_state)
                # h: (B, d_inner, d_state)
                y_t = (C_in[:, t].unsqueeze(1) * h).sum(dim=-1)  # (B, d_inner)
                ys.append(y_t)
            # Stack: (B, L, d_inner)
            y = torch.stack(ys, dim=1)
            # Skip connection: y = y + D * x
            y = y + D.unsqueeze(0).unsqueeze(0) * x_f32

        # Return in original dtype (cast back if AMP was used)
        return y.to(dtype=x.dtype)


class MambaClassifier(nn.Module):
    """
    Mamba binary classifier for tail-event prediction.

    input (B, L=21, C=74) → linear embed → norm → n_layers MambaBlock → mean pool → head
    """
    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 d_model=64, d_state=16, d_conv=4, expand=2,
                 n_layers=2, dropout=0.30):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.d_model = d_model

        self.embed = nn.Linear(input_dim, d_model)
        self.embed_norm = nn.LayerNorm(d_model)

        # Stack of Mamba blocks (each pre-normed)
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
        # x: (B, L, C)
        h = self.embed(x)
        h = self.embed_norm(h)
        for block, norm in zip(self.blocks, self.block_norms):
            # Pre-norm + residual
            h = h + self.dropout(block(norm(h)))
        h = self.head_norm(h)
        # Mean pool over L
        h = h.mean(dim=1)
        h = self.head_drop(h)
        return self.head(h).squeeze(-1)


# ============================================================================
# Architecture 2: FEDformer (Zhou et al. 2022)
#
# FEDformer = Frequency Enhanced Decomposed Transformer
#   1) Series decomposition (moving avg) → trend + seasonal
#   2) Frequency Enhanced Block (FEB): top-k Fourier modes attention
#   3) Channel-aware encoder
#
# Simplified for L=21, binary classification:
#   input → embed → series decomp → trend-linear + seasonal-FEB encoder ×2 → head
#
# References:
#   - Zhou et al. ICML 2022 "FEDformer: Frequency Enhanced Decomposed Transformer
#     for Long-term Series Forecasting"
#   - github.com/MAZiqing/FEDformer
# ============================================================================

class FEDSeriesDecomposition(nn.Module):
    """Moving avg series decomp (same as DLinear / FEDformer)."""
    def __init__(self, kernel_size):
        super().__init__()
        self.kernel_size = kernel_size
        self.pad = kernel_size // 2

    def forward(self, x):
        # x: (B, L, C) → trend, seasonal (both B, L, C)
        x_t = x.transpose(1, 2).contiguous()
        x_pad = F.pad(x_t, (self.pad, self.pad), mode="replicate")
        trend = F.avg_pool1d(x_pad, kernel_size=self.kernel_size, stride=1)
        trend = trend.transpose(1, 2).contiguous()
        seasonal = x - trend
        return trend, seasonal


class FrequencyEnhancedBlock(nn.Module):
    """
    FEDformer FEB-f: Fourier-based frequency enhanced block.

    1) rfft x along L (under fp32 / AMP disabled — L=21 not power-of-2)
    2) select top-k frequency modes by amplitude
    3) learnable complex-valued projection on those modes
    4) inverse rfft → output

    PIT-safe:
      - FFT is on input window only (B, L, d_model); no future
      - Frequencies extracted within window; no temporal leakage
      - Codex review fix (146): rfft requires fp32 under CUDA AMP for non-power-of-2 L
    """
    def __init__(self, d_model, seq_len=SEQ_LEN, modes=3):
        super().__init__()
        self.d_model = d_model
        self.seq_len = seq_len
        self.n_freq = seq_len // 2 + 1  # rfft output size
        # Top-k modes (clip if requested > available)
        self.modes = min(modes, self.n_freq - 1)  # exclude DC

        # Learnable complex weights for the top-k modes
        # Each: (d_model, d_model) complex matrix (split into real + imag tensors)
        scale = 1.0 / (d_model * d_model)
        self.weight_real = nn.Parameter(
            scale * torch.randn(self.modes, d_model, d_model)
        )
        self.weight_imag = nn.Parameter(
            scale * torch.randn(self.modes, d_model, d_model)
        )

    def forward(self, x):
        """
        x: (B, L, d_model) → (B, L, d_model) in same dtype

        Codex review fix (HIGH severity, 2026-05-21):
          Previous implementation selected top-k modes from BATCH-AVERAGED amplitude
          (`amp = torch.abs(xf).mean(dim=(0,2))`), which made OOS predictions depend
          on the composition of the evaluation batch — earlier OOS rows could be
          influenced by later rows in the same batch (PIT violation).

          Fix: use FIXED non-DC modes [1..modes]. This is independent of batch
          contents and strictly per-row (point-in-time valid). FEDformer paper's
          dynamic mode selection is replaced with a deterministic mode set; this is
          a common simplification when running short L (L=21 has only 11 non-DC
          modes, so picking top-3 lowest-frequency captures ~most of the signal
          anyway and avoids batch-dependency).
        """
        B, L, D = x.shape
        # Disable AMP for FFT (L=21 not power-of-2)
        with torch.amp.autocast(device_type=x.device.type, enabled=False):
            x_f32 = x.float()
            # rfft along L
            xf = torch.fft.rfft(x_f32, dim=1)  # (B, n_freq, D) complex

            # FIXED top-k non-DC modes (batch-independent, PIT-safe)
            # modes = [1, 2, ..., self.modes] — skip DC at index 0
            top_idx = torch.arange(1, self.modes + 1, device=x.device)

            # Select the top-k modes: (B, modes, D)
            xf_top = xf[:, top_idx, :]

            # Learnable complex matmul per mode
            # weight: (modes, D, D) complex
            # For each mode m: out[:, m, :] = xf_top[:, m, :] @ weight[m]
            w_complex = torch.complex(self.weight_real, self.weight_imag)  # (modes, D, D)
            # einsum: bmd, mde -> bme
            out_top = torch.einsum("bmd,mde->bme", xf_top, w_complex)

            # Build full-length output (zero everywhere else; insert at top_idx)
            out_xf = torch.zeros_like(xf)
            out_xf[:, top_idx, :] = out_top

            # Inverse rfft
            out = torch.fft.irfft(out_xf, n=L, dim=1)  # (B, L, D) real
        # Cast back to input dtype
        return out.to(dtype=x.dtype)


class FEDformerEncoderLayer(nn.Module):
    """Single FEDformer encoder layer: FEB + decomp + FFN + decomp (per FEDformer paper)."""
    def __init__(self, d_model, n_heads=4, seq_len=SEQ_LEN, modes=3,
                 ff_mult=4, dropout=0.30, kernel_size=5):
        super().__init__()
        self.feb = FrequencyEnhancedBlock(d_model, seq_len=seq_len, modes=modes)
        self.decomp1 = FEDSeriesDecomposition(kernel_size)
        self.decomp2 = FEDSeriesDecomposition(kernel_size)

        ff_dim = d_model * ff_mult
        self.ffn = nn.Sequential(
            nn.Linear(d_model, ff_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(ff_dim, d_model),
        )
        self.drop = nn.Dropout(dropout)
        # n_heads kept as hyperparam for API compat (FEB doesn't use heads in this simplified port)
        self.n_heads = n_heads

    def forward(self, x):
        # FEB then decomp (drop trend, keep seasonal)
        h = x + self.drop(self.feb(x))
        _, h_s = self.decomp1(h)
        # FFN then decomp
        h2 = h_s + self.drop(self.ffn(h_s))
        _, out = self.decomp2(h2)
        return out


class FEDformerClassifier(nn.Module):
    """
    FEDformer binary classifier — simplified for tail-event prediction.

    input (B, L=21, C=74) → linear embed → +pos_enc → series decomp
      → trend path: mean pool L → linear (linear trend projection)
      → seasonal path: FEDformerEncoderLayer ×e_layers → mean pool L
    head: concat(trend, seasonal) → MLP → logit
    """
    def __init__(self, input_dim, seq_len=SEQ_LEN,
                 d_model=64, n_heads=4, e_layers=2,
                 modes=3, ff_mult=4, dropout=0.30, kernel_size=5):
        super().__init__()
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.d_model = d_model

        self.embed = nn.Linear(input_dim, d_model)
        self.pos_enc = PositionalEncoding(d_model, max_len=seq_len + 16)
        self.decomp_init = FEDSeriesDecomposition(kernel_size)

        # Trend projection: d_model → d_model (passes through, linear stack)
        self.trend_proj = nn.Linear(d_model, d_model)

        # Seasonal encoder
        self.enc_layers = nn.ModuleList([
            FEDformerEncoderLayer(d_model, n_heads=n_heads, seq_len=seq_len,
                                  modes=modes, ff_mult=ff_mult, dropout=dropout,
                                  kernel_size=kernel_size)
            for _ in range(e_layers)
        ])
        self.enc_norm = nn.LayerNorm(d_model)

        self.head_drop = nn.Dropout(dropout)
        # Concat(trend, seasonal) → 2*d_model
        self.head = nn.Sequential(
            nn.Linear(2 * d_model, d_model),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model, 1),
        )

    def forward(self, x):
        # x: (B, L, C)
        h = self.embed(x)  # (B, L, d_model)
        h = self.pos_enc(h)
        # Initial decomp
        trend, seasonal = self.decomp_init(h)
        # Trend path: project and mean pool
        trend_proj = self.trend_proj(trend)  # (B, L, d_model)
        trend_pool = trend_proj.mean(dim=1)  # (B, d_model)
        # Seasonal path: stacked FEB encoder
        s = seasonal
        for layer in self.enc_layers:
            s = layer(s)
        s = self.enc_norm(s)
        seasonal_pool = s.mean(dim=1)  # (B, d_model)
        # Concat + head
        feat = torch.cat([trend_pool, seasonal_pool], dim=-1)
        feat = self.head_drop(feat)
        return self.head(feat).squeeze(-1)


# ============================================================================
# Helpers (mirror 53H / 146 exactly)
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
    Load v5e features + forward labels.

    Cycle 56D-Batch2: prefer observable targets (NaN propagation applied).
    Fallback to buggy version with explicit mask (146 pattern).
    """
    feat_path = DATA / "feature_panel_v5e_q126_usmacro.parquet"
    obs_path = TGT / "targets_long_horizon_observable.parquet"
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

    h_suffix = target_col.replace("y_tail_", "")
    ret_col = f"ret_{h_suffix}"
    thr_col = f"q15_thr_{h_suffix}"

    if ret_col not in tgt_all.columns or thr_col not in tgt_all.columns:
        sys.exit(f"missing ret/thr columns for {target_col}: {ret_col} / {thr_col}")

    # Label is valid only if forward return AND threshold are resolved
    label_ok = tgt_all[ret_col].notna() & tgt_all[thr_col].notna()
    tgt = tgt_all[["Date", target_col]].copy()
    tgt.loc[~label_ok, target_col] = np.nan

    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)
    panel = panel[panel["Date"] <= OOS_END].reset_index(drop=True)

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    assert len(feature_cols) == 74, f"v5e expects 74 features, got {len(feature_cols)}"

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


def train_one_window(model_class, model_name, target_col,
                     X_full, y_full, dates,
                     train_start, train_end,
                     valid_start=None, valid_end=None,
                     fixed_epochs=None, fold_label="", seed=42,
                     lr=PT_LR, weight_decay=PT_WEIGHT_DECAY):
    set_seed_strict(seed)
    Xs = standardize_for_window(X_full, dates, train_start, train_end)
    X_seq, y_seq = make_sequences(Xs, y_full, SEQ_LEN)
    dates_seq = dates[SEQ_LEN - 1:]

    # Mask unresolved labels (NaN)
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

    g_loader = make_loader_generator(seed)
    train_loader = DataLoader(
        TensorDataset(X_train_t, y_train_t),
        batch_size=BATCH_SIZE, shuffle=True, drop_last=True,
        num_workers=NUM_WORKERS, generator=g_loader,
        worker_init_fn=worker_init_fn if NUM_WORKERS > 0 else None,
    )

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

    print(f"    [{model_name}/seed{seed}] {fold_label} "
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


def predict_oos(final_model, Xs_final, dates, y_full):
    """Predict OOS, returning (oop, oos_y, oos_dates)."""
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
        bs = 256  # smaller for Mamba sequential scan
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
        res[name] = dict(
            n=n, n_bear=n_bear,
            base_rate=round(n_bear / n, 4),
            pr_auc=round(pr, 4) if not np.isnan(pr) else None,
            ic=round(ic, 4) if not np.isnan(ic) else None,
            p_max=round(float(np.max(p_s)), 6),
            p_p99=round(float(np.percentile(p_s, 99)), 6),
            p_p50=round(float(np.percentile(p_s, 50)), 6),
            p_min=round(float(np.min(p_s)), 9),
        )
    return res


def run_arch_walkforward(model_class, model_name, target_col, seed_base=SEED_BASE):
    """Run with reseed rescue if final OOS prediction shows logit collapse."""
    print("\n" + "=" * 80)
    print(f"[Cycle 56D-Batch2] arch={model_name} target={target_col}")
    print("=" * 80)
    skip_folds = SKIP_FOLDS_PER_TARGET.get(target_col, [])
    if skip_folds:
        print(f"  [INFO] Skipping degenerate folds for {target_col}: {skip_folds}")
    t_start = time.time()

    X_full, y_full, dates, _ = prepare_data_full(target_col)

    # Walk-forward fold valid PR-AUC (single seed=seed_base)
    fold_results = []
    for fi in FOLDS:
        if fi["name"] in skip_folds:
            print(f"\n  --- {fi['name']} SKIPPED (degenerate) ---")
            fold_results.append(dict(
                fold=fi["name"], model=model_name, target=target_col,
                seed=int(seed_base),
                best_valid_pr=None, best_epoch=None, epochs_done=0, early_stop_ep=None,
                valid_bear_count=0, train_loss_first=None, train_loss_last=None,
                n_params=None, skipped=True, skip_reason="zero-events"
            ))
            continue
        print(f"\n  --- {fi['name']} ---")
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
    print(f"\n  [Avg best_epoch across {len(valid_eps)} folds] = {avg_best_ep}")
    print(f"  [Per-fold best_epoch] = {[r.get('best_epoch') for r in fold_results]}")
    print(f"  [Per-fold best_valid_pr] = {[r.get('best_valid_pr') for r in fold_results]}")

    # FINAL TRAIN + OOS predict, with collapse detection + reseed rescue
    final_attempts = []
    selected_seed = seed_base
    selected_oop = None
    selected_y = None
    selected_dates = None
    selected_collapse = None
    selected_final_res = None
    selected_oos_pr = None
    selected_oos_ic = None
    all_collapsed = True

    for attempt_offset in range(RESEED_MAX + 1):
        cur_seed = seed_base + attempt_offset
        print(f"\n  --- Final training (attempt {attempt_offset+1}/{RESEED_MAX+1}, seed={cur_seed}) ---")
        final_model, Xs_final, _, _, final_train_res = train_one_window(
            model_class, model_name, target_col,
            X_full, y_full, dates,
            train_start=str(FULL_TRAIN_START.date()), train_end=str(FULL_TRAIN_END.date()),
            valid_start=None, valid_end=None,
            fixed_epochs=avg_best_ep, fold_label=f"FINAL_TRAIN_seed{cur_seed}", seed=cur_seed,
        )
        oop, oos_y, oos_dates = predict_oos(final_model, Xs_final, dates, y_full)
        collapse = detect_logit_collapse(oop)
        oos_pr = pr_auc(oop, oos_y)
        oos_ic = ic_spearman(oop, oos_y)
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
        print(f"  [WARN] All {RESEED_MAX+1} seeds collapsed — predictions saved but oos_pr=null for leaderboard.")
        selected_seed = seed_base + RESEED_MAX
        selected_oop = oop
        selected_y = oos_y
        selected_dates = oos_dates
        selected_collapse = collapse
        selected_final_res = final_train_res
        selected_oos_pr = None
        selected_oos_ic = None
        all_collapsed = True

    elapsed = time.time() - t_start
    _pr_disp = f"{selected_oos_pr:.4f}" if selected_oos_pr is not None else "None_ALL_COLLAPSED"
    _ic_disp = f"{selected_oos_ic:.4f}" if selected_oos_ic is not None else "None_ALL_COLLAPSED"
    print(f"\n  [{model_name}/{target_col}] FINAL OOS PR-AUC: {_pr_disp}  IC: {_ic_disp}  "
          f"adopted_seed={selected_seed}  collapsed={selected_collapse['collapsed']}  "
          f"all_collapsed={all_collapsed}  elapsed={elapsed:.1f}s")

    if DEVICE.type == "cuda":
        mem_peak_mb = torch.cuda.max_memory_allocated() / (1024 ** 2)
        torch.cuda.reset_peak_memory_stats()
    else:
        mem_peak_mb = float("nan")

    period_metrics = period_balanced_metrics(selected_oop, selected_y, selected_dates)

    # Save predictions
    col_name = f"p_{model_name.lower()}"
    df = pd.DataFrame({
        "Date": selected_dates,
        col_name: selected_oop,
        "y": selected_y,
        "split": "oos",
        "target": target_col,
        "model": model_name,
        "adopted_seed": int(selected_seed),
        "collapsed": bool(selected_collapse["collapsed"]),
        "all_collapsed": bool(all_collapsed),
    })
    file_name = f"predictions_{model_name.lower()}_{target_col}.parquet"
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
        model=model_name,
        target=target_col,
        seed_base=int(seed_base),
        adopted_seed=int(selected_seed),
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
        fold_results_detailed=fold_results,
        oos_dates=selected_dates,
        oos_pred=selected_oop,
        oos_y=selected_y,
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
    feat_md5 = md5_file(DATA / "feature_panel_v5e_q126_usmacro.parquet")
    tgt_md5_obs = md5_file(TGT / "targets_long_horizon_observable.parquet")
    tgt_md5_legacy = md5_file(TGT / "targets_long_horizon.parquet")
    return dict(
        cycle="56D-Batch2",
        script="153_mamba_fedformer_q126.py",
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
        targets_observable_md5=tgt_md5_obs,
        targets_legacy_md5=tgt_md5_legacy,
        oos_window=dict(start=str(OOS_START.date()), end=str(OOS_END.date())),
        folds_used=FOLDS,
        skip_folds_per_target=SKIP_FOLDS_PER_TARGET,
        targets=TARGETS,
        architectures=["Mamba (Gu&Dao 2023 S6)", "FEDformer (Zhou 2022 freq-enhanced)"],
        ref_53h_q126=REF_53H_Q126,
        ref_53h_q15=REF_53H_Q15,
        ref_56d_prelim={
            "dlinear_q126": REF_56D_DLINEAR_Q126,
            "informer_q126": REF_56D_INFORMER_Q126,
            "timesnet_q126": REF_56D_TIMESNET_Q126,
        },
        notes="Strict determinism + collapse detector + reseed rescue + period-balanced + observable targets.",
    )


if __name__ == "__main__":
    print("=" * 80)
    print("[Cycle 56D-Batch2 — Mamba + FEDformer q126]")
    print("[v5e panel 74 features / forward labels (observable) / walk-forward 4-fold (q126 Fold3 skip)]")
    print(f"[2 archs × {len(TARGETS)} targets = {2 * len(TARGETS)} runs]")
    print(f"[Reseed rescue: up to {RESEED_MAX+1} attempts per arch if logit collapse]")
    print(f"[Reference: 53H PatchTST q126={REF_53H_Q126} / q15={REF_53H_Q15}]")
    print(f"[56D-prelim refs: DLinear={REF_56D_DLINEAR_Q126} Informer={REF_56D_INFORMER_Q126} TimesNet={REF_56D_TIMESNET_Q126}]")
    print("=" * 80)

    prov = collect_provenance()
    with (OUT / "provenance.json").open("w") as f:
        json.dump(prov, f, indent=2, default=str)
    print(f"[Provenance] Saved: {OUT / 'provenance.json'}")

    archs = [
        ("Mamba", MambaClassifier),
        ("FEDformer", FEDformerClassifier),
    ]

    results = {}
    for arch_name, arch_class in archs:
        for tgt in TARGETS:
            key = f"{arch_name}_{tgt}"
            try:
                results[key] = run_arch_walkforward(arch_class, arch_name, tgt, seed_base=SEED_BASE)
                # Incremental save (resumable)
                def serialize(r):
                    if not isinstance(r, dict):
                        return r
                    return {k: v for k, v in r.items() if k not in ("oos_dates", "oos_pred", "oos_y")}
                with (OUT / "variant_diagnostics.json").open("w") as f:
                    json.dump(
                        dict(cycle="56D-Batch2", provenance=prov,
                             results={k: serialize(v) for k, v in results.items()}),
                        f, indent=2, default=str,
                    )
            except Exception as e:
                print(f"\n[ERROR] arch {key} failed: {e}")
                import traceback
                traceback.print_exc()
                results[key] = dict(error=str(e))

    # EW2 ensemble (Mamba + FEDformer)
    print("\n" + "=" * 80)
    print("[EW2 ensemble: Mamba + FEDformer equal-weight averaged predictions]")
    print("=" * 80)
    ensemble_results = {}
    for tgt in TARGETS:
        mm_r = results.get(f"Mamba_{tgt}")
        fd_r = results.get(f"FEDformer_{tgt}")
        if mm_r is None or fd_r is None or "error" in mm_r or "error" in fd_r:
            print(f"  [WARN] EW2 {tgt} skipped — one or both archs missing/errored")
            continue
        # Align by Date
        try:
            assert (mm_r["oos_dates"] == fd_r["oos_dates"]).all(), "Date misalign Mamba/FEDformer"
            assert (mm_r["oos_y"] == fd_r["oos_y"]).all(), "y misalign Mamba/FEDformer"
        except AssertionError as ae:
            print(f"  [ERROR] EW2 {tgt} alignment: {ae}")
            continue

        ew_pred = (mm_r["oos_pred"] + fd_r["oos_pred"]) / 2.0
        ew_y = mm_r["oos_y"]
        ew_dates = mm_r["oos_dates"]

        ew_pr = pr_auc(ew_pred, ew_y)
        ew_ic = ic_spearman(ew_pred, ew_y)
        ew_periods = period_balanced_metrics(ew_pred, ew_y, ew_dates)

        print(f"  EW2 {tgt}: PR-AUC={ew_pr:.4f}  IC={ew_ic:.4f}  n={len(ew_pred)}  events={int(ew_y.sum())}")

        df_ew = pd.DataFrame({
            "Date": ew_dates,
            "p_ew2": ew_pred,
            "y": ew_y,
            "split": "oos", "target": tgt,
        })
        df_ew.to_parquet(OUT / f"predictions_ew2_{tgt}.parquet", index=False)
        ensemble_results[tgt] = dict(
            oos_pr=ew_pr, oos_ic=ew_ic,
            n_obs=int(len(ew_pred)), n_events=int(ew_y.sum()),
            event_rate=float(ew_y.mean()),
            period_metrics=ew_periods,
        )

    # SUMMARY
    print("\n" + "=" * 80)
    print("[Cycle 56D-Batch2 SUMMARY]")
    print("=" * 80)
    print(f"\n  Reference 53H PatchTST q126={REF_53H_Q126}  q15={REF_53H_Q15}")
    print(f"  Reference 56D-prelim q126: DLinear={REF_56D_DLINEAR_Q126}  Informer={REF_56D_INFORMER_Q126}  TimesNet={REF_56D_TIMESNET_Q126}")
    print()
    print(f"{'arch':12s} {'target':14s} {'PR-AUC':>9s} {'IC':>9s} {'Δ vs 53H':>10s} {'all_col':>8s} {'p_max':>10s} {'seed':>5s} {'elapsed_s':>9s}")
    print("-" * 100)
    for arch_name, _ in archs:
        for tgt in TARGETS:
            k = f"{arch_name}_{tgt}"
            r = results.get(k, {})
            if "error" in r:
                print(f"  {arch_name} {tgt} ERROR: {r['error']}")
                continue
            ref = REF_53H_Q126 if tgt == "y_tail_q126" else REF_53H_Q15
            pr_v = r.get("oos_pr")
            ic_v = r.get("oos_ic")
            d = (pr_v - ref) if (pr_v is not None and ref is not None) else None
            col = r.get("collapse", {}) or {}
            all_col = r.get("all_collapsed", False)
            pr_disp = f"{pr_v:.4f}" if pr_v is not None else "None"
            ic_disp = f"{ic_v:.4f}" if ic_v is not None else "None"
            d_disp = f"{d:+.4f}" if d is not None else "N/A"
            p_max_val = col.get("p_max")
            p_max_disp = f"{p_max_val:.2e}" if p_max_val is not None else "N/A"
            elapsed_v = r.get("elapsed_sec", 0) or 0
            print(f"  {arch_name:10s} {tgt:14s} {pr_disp:>9s} {ic_disp:>9s} {d_disp:>10s} "
                  f"{str(all_col):>8s} {p_max_disp:>10s} {r.get('adopted_seed', '?'):>5} {elapsed_v:>9.1f}")
    print("  --- ensemble ---")
    for tgt in TARGETS:
        ref = REF_53H_Q126 if tgt == "y_tail_q126" else REF_53H_Q15
        if tgt in ensemble_results:
            er = ensemble_results[tgt]
            d = er["oos_pr"] - ref
            print(f"  {'EW2':10s} {tgt:14s} {er['oos_pr']:>9.4f} {er['oos_ic']:>9.4f} {d:>+10.4f}")
        else:
            print(f"  {'EW2':10s} {tgt:14s} skipped")

    # Per-fold + diagnostics dump
    per_fold_path = OUT / "per_fold_diagnostics.json"

    def serialize_seed_result(r):
        if not isinstance(r, dict):
            return r
        return {k: v for k, v in r.items() if k not in ("oos_dates", "oos_pred", "oos_y")}

    per_fold = {
        "cycle": "56D_Batch2_mamba_fedformer",
        "validation_strategy": "walk_forward_expanding_5_fold_CV_Fold3_skipped_q126",
        "patience": EARLY_STOP_PATIENCE,
        "min_delta": EARLY_STOP_MIN_DELTA,
        "max_epochs": MAX_EPOCHS,
        "folds": FOLDS,
        "skip_folds_per_target": SKIP_FOLDS_PER_TARGET,
        "oos_window": {"start": str(OOS_START.date()), "end": str(OOS_END.date())},
        "feature_panel": "feature_panel_v5e_q126_usmacro.parquet (74 features)",
        "seed_base": SEED_BASE,
        "reseed_max": RESEED_MAX,
        "provenance": prov,
        "per_arch": {
            k: {
                "model": v.get("model"),
                "target": v.get("target"),
                "adopted_seed": v.get("adopted_seed"),
                "fold_results_detailed": v.get("fold_results_detailed", []),
                "final_attempts": v.get("final_attempts", []),
                "avg_best_epoch": v.get("avg_best_epoch"),
                "oos_pr": v.get("oos_pr"),
                "oos_ic": v.get("oos_ic"),
                "all_collapsed": v.get("all_collapsed"),
                "period_metrics": v.get("period_metrics"),
                "n_params": v.get("n_params"),
                "elapsed_sec": v.get("elapsed_sec"),
            }
            for k, v in results.items()
            if isinstance(v, dict) and "error" not in v
        },
        "ensemble_ew2": ensemble_results,
    }
    with per_fold_path.open("w") as f:
        json.dump(per_fold, f, indent=2, default=str)
    print(f"\n[Per-fold] Saved: {per_fold_path}")

    # Final attempts log (reseed rescue trail)
    final_attempts_path = OUT / "final_attempts.json"
    final_attempts_log = {
        "cycle": "56D_Batch2",
        "seed_base": SEED_BASE,
        "reseed_max": RESEED_MAX,
        "per_arch": {
            k: {
                "model": v.get("model"),
                "target": v.get("target"),
                "adopted_seed": v.get("adopted_seed"),
                "all_collapsed": v.get("all_collapsed"),
                "attempts": v.get("final_attempts", []),
            }
            for k, v in results.items()
            if isinstance(v, dict) and "error" not in v
        },
    }
    with final_attempts_path.open("w") as f:
        json.dump(final_attempts_log, f, indent=2, default=str)
    print(f"[Final attempts] Saved: {final_attempts_path}")

    # Python diagnostics summary
    diag_path = EVAL_DIR / "mamba_fedformer_v6d_python_diag.json"
    diag = {
        "cycle": "56D_Batch2_mamba_fedformer",
        "approach": "STATE_SPACE_PLUS_FREQUENCY_MAMBA_FEDFORMER",
        "panel": "feature_panel_v5e_q126_usmacro.parquet",
        "targets_source_preferred": "targets_long_horizon_observable.parquet",
        "n_features": 74,
        "forward_labels": True,
        "validation_strategy": "walk_forward_expanding_5_fold_CV_Fold3_skipped_q126",
        "horizons_evaluated": TARGETS,
        "seed_base": SEED_BASE,
        "reseed_max": RESEED_MAX,
        "architectures_evaluated": [
            "Mamba (Gu & Dao 2023 — Selective State-Space S6, linear time)",
            "FEDformer (Zhou et al. 2022 — Frequency Enhanced Decomposed Transformer, top-k Fourier modes)",
        ],
        "training_common": {
            "batch_size": BATCH_SIZE, "max_epochs": MAX_EPOCHS,
            "early_stop_patience": EARLY_STOP_PATIENCE,
            "early_stop_min_delta": EARLY_STOP_MIN_DELTA,
            "grad_clip_norm": GRAD_CLIP_NORM, "warmup_steps": WARMUP_STEPS,
            "mixed_precision_amp": USE_AMP,
            "gpu_mem_fraction": 0.20 if DEVICE.type == "cuda" else None,
            "lr": PT_LR, "weight_decay": PT_WEIGHT_DECAY,
            "strict_determinism": True,
            "cudnn_deterministic": torch.backends.cudnn.deterministic,
            "cudnn_benchmark": torch.backends.cudnn.benchmark,
            "cublas_workspace_config": os.environ.get('CUBLAS_WORKSPACE_CONFIG'),
        },
        "baseline_references": {
            "cycle_53h_patchtst_q126": REF_53H_Q126,
            "cycle_53h_patchtst_q15": REF_53H_Q15,
            "cycle_56d_prelim": {
                "dlinear_q126": REF_56D_DLINEAR_Q126,
                "informer_q126": REF_56D_INFORMER_Q126,
                "timesnet_q126": REF_56D_TIMESNET_Q126,
            },
        },
        "per_arch_per_target": {
            f"{arch_name}_{tgt}": serialize_seed_result(results.get(f"{arch_name}_{tgt}", {}))
            for arch_name, _ in archs for tgt in TARGETS
        },
        "ensemble_ew2": ensemble_results,
        "per_fold_diagnostics_path": str(per_fold_path),
        "final_attempts_path": str(final_attempts_path),
    }
    with diag_path.open("w") as f:
        json.dump(diag, f, indent=2, default=str)
    print(f"[Diagnostics] Saved: {diag_path}")

    print("\n" + "=" * 80)
    print("[Cycle 56D-Batch2 Python DONE — Run scripts/154_mamba_fedformer_aggregate.R next]")
    print("=" * 80)
