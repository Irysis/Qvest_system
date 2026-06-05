"""
b1_lstm_distribution.py — B1 LSTM × {Normal, Student-t, skewed-t} models.

Architecture (paper Michańków 2025 §3.4, AMENDMENT_v0.5 CR-V02 exact spec):
- LSTM 3-layer 128 → 64 → 32 (paper actual, v0.4 "2-layer hidden=64" was wrong)
- Dense output: p neurons (p = 2/3/4 per distribution choice)
- Dropout 0.02, L2 0.002
- Input: sequence (B, T=10, F) → output θ ∈ R^p (distribution parameters)

CNN variant (paper §3.4 comparison):
- 1D Conv 256 filters / kernel_size 2 / pool 2 + flatten + dense

Output activation: linear (no constraint on raw θ — distribution unpacking applies softplus / exp internally).

Usage:
    model = LstmDistribution(input_size=F, dist_type='skewed_t')
    theta = model(x)  # (B, T, F) → (B, 4)
    loss = skewed_t_nll(theta, y)
"""
from __future__ import annotations
from typing import Literal

import torch
import torch.nn as nn


# Param count per distribution
DIST_P_COUNT = {
    'normal': 2,
    'student_t': 3,
    'skewed_t': 4,
}

DistType = Literal['normal', 'student_t', 'skewed_t']


class LstmDistribution(nn.Module):
    """LSTM 3-layer + dense → distribution parameter output.

    Paper Michańków 2025 Table 1 baseline:
    - hidden_sizes = [128, 64, 32]
    - dropout = 0.02 (inter-layer)
    - L2 (weight_decay) = 0.002 applied via optimizer
    - Adam lr = 0.002
    - batch = 128, epochs = 300 + early stopping
    """
    def __init__(
        self,
        input_size: int,
        hidden_sizes: tuple = (128, 64, 32),
        dist_type: DistType = 'skewed_t',
        dropout: float = 0.02,
    ):
        super().__init__()
        self.dist_type = dist_type
        self.p = DIST_P_COUNT[dist_type]

        # LSTM 3-layer (paper Figure 1)
        # PyTorch LSTM(num_layers=3, hidden_size=H) uses same hidden_size across all layers
        # → we manually chain 3 separate LSTMs to match paper's 128/64/32 stepdown
        self.lstm1 = nn.LSTM(input_size, hidden_sizes[0], batch_first=True)
        self.dropout1 = nn.Dropout(dropout)
        self.lstm2 = nn.LSTM(hidden_sizes[0], hidden_sizes[1], batch_first=True)
        self.dropout2 = nn.Dropout(dropout)
        self.lstm3 = nn.LSTM(hidden_sizes[1], hidden_sizes[2], batch_first=True)
        self.dropout3 = nn.Dropout(dropout)

        # Dense output (paper Figure 1)
        self.dense = nn.Linear(hidden_sizes[2], self.p)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        x: (B, T, F) input sequence
        Returns: (B, p) raw distribution parameters
        """
        h, _ = self.lstm1(x)
        h = self.dropout1(h)
        h, _ = self.lstm2(h)
        h = self.dropout2(h)
        h, _ = self.lstm3(h)
        h = self.dropout3(h)
        # Take last timestep only
        h_last = h[:, -1, :]  # (B, hidden_sizes[2])
        theta = self.dense(h_last)
        return theta


class CnnDistribution(nn.Module):
    """1D CNN + flatten + dense → distribution parameter (paper variant).

    Paper §3.4:
    - 1D Conv 256 filters, kernel_size=2
    - MaxPool 2
    - Flatten + Dense(p)
    """
    def __init__(
        self,
        input_size: int,
        sequence_length: int = 10,
        filters: int = 256,
        kernel_size: int = 2,
        pool_size: int = 2,
        dist_type: DistType = 'skewed_t',
        dropout: float = 0.02,
    ):
        super().__init__()
        self.dist_type = dist_type
        self.p = DIST_P_COUNT[dist_type]

        self.conv = nn.Conv1d(input_size, filters, kernel_size=kernel_size)
        self.pool = nn.MaxPool1d(pool_size)
        self.dropout = nn.Dropout(dropout)
        # Flattened size: filters * ((seq_len - kernel + 1) // pool)
        flat_size = filters * ((sequence_length - kernel_size + 1) // pool_size)
        self.dense = nn.Linear(flat_size, self.p)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        x: (B, T, F) → permute to (B, F, T) for Conv1d
        """
        h = x.permute(0, 2, 1)  # (B, F, T)
        h = torch.relu(self.conv(h))
        h = self.pool(h)
        h = self.dropout(h)
        h = h.flatten(1)
        theta = self.dense(h)
        return theta


def build_model(
    arch: Literal['lstm', 'cnn'],
    dist_type: DistType,
    input_size: int,
    sequence_length: int = 10,
    hidden_sizes: tuple = (128, 64, 32),
    dropout: float = 0.02,
) -> nn.Module:
    """Factory: build LSTM or CNN model for given distribution."""
    if arch == 'lstm':
        return LstmDistribution(
            input_size=input_size,
            hidden_sizes=hidden_sizes,
            dist_type=dist_type,
            dropout=dropout,
        )
    elif arch == 'cnn':
        return CnnDistribution(
            input_size=input_size,
            sequence_length=sequence_length,
            dist_type=dist_type,
            dropout=dropout,
        )
    else:
        raise ValueError(f"Unknown arch: {arch}")


__all__ = ['LstmDistribution', 'CnnDistribution', 'build_model', 'DIST_P_COUNT']
