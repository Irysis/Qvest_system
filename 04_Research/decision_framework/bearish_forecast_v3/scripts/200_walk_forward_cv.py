"""
200_walk_forward_cv.py — Walk-forward purged CV + embargo

Reference: Lopez de Prado 2018 "Advances in Financial Machine Learning" Ch 7
- Purging: remove training samples whose target overlaps with test window
- Embargo: remove training samples that immediately follow test window (label leakage)

For 21-day forward target with daily data:
  Purge 21 days before each test window start
  Embargo 21 days after each test window end

Usage:
    splitter = PurgedWalkForwardCV(n_splits=5, train_min=1008, test_size=504, embargo=21)
    for fold_idx, (train_idx, test_idx) in enumerate(splitter.split(X)):
        ...
"""
from __future__ import annotations
from typing import Iterator, Tuple

import numpy as np


class PurgedWalkForwardCV:
    """Walk-forward expanding window with purging + embargo.

    Args:
        n_splits: Number of folds (test windows)
        train_min: Minimum training size (expanding starts at this size)
        test_size: Number of samples per test window
        embargo: Number of samples to purge between train and test (default 21)

    Returns: yields (train_idx, test_idx) tuples
    """
    def __init__(
        self,
        n_splits: int = 5,
        train_min: int = 1008,
        test_size: int = 504,
        embargo: int = 21,
    ):
        self.n_splits = n_splits
        self.train_min = train_min
        self.test_size = test_size
        self.embargo = embargo

    def split(self, X: np.ndarray) -> Iterator[Tuple[np.ndarray, np.ndarray]]:
        n = len(X)
        # Compute test window starts
        test_starts = []
        for fold in range(self.n_splits):
            test_start = self.train_min + fold * self.test_size + self.embargo
            test_end = test_start + self.test_size
            if test_end > n:
                # Last fold may be partial
                if test_start < n:
                    test_end = n
                else:
                    break
            test_starts.append((test_start, test_end))

        for test_start, test_end in test_starts:
            train_end = test_start - self.embargo
            if train_end < self.train_min:
                continue
            train_idx = np.arange(0, train_end)
            test_idx = np.arange(test_start, test_end)
            yield train_idx, test_idx

    def get_n_splits(self) -> int:
        return self.n_splits


class PurgedKFoldCV:
    """Purged K-Fold CV (NOT walk-forward).

    Used for NGBoost / boosting models that don't have temporal sequence structure.
    Splits all data into K folds; each fold becomes test once, rest becomes train.
    Embargo applied between train and test boundary.

    Args:
        n_splits: K
        embargo: samples around test boundary to drop from training
    """
    def __init__(self, n_splits: int = 5, embargo: int = 21):
        self.n_splits = n_splits
        self.embargo = embargo

    def split(self, X: np.ndarray) -> Iterator[Tuple[np.ndarray, np.ndarray]]:
        n = len(X)
        fold_size = n // self.n_splits
        for fold in range(self.n_splits):
            test_start = fold * fold_size
            test_end = test_start + fold_size if fold < self.n_splits - 1 else n
            # Train = everything except [test_start - embargo, test_end + embargo)
            train_mask = np.ones(n, dtype=bool)
            train_mask[max(0, test_start - self.embargo):min(n, test_end + self.embargo)] = False
            train_idx = np.where(train_mask)[0]
            test_idx = np.arange(test_start, test_end)
            yield train_idx, test_idx

    def get_n_splits(self) -> int:
        return self.n_splits


def sanity_check_cv(splitter, X: np.ndarray) -> dict:
    """Verify CV split: no train-test overlap, embargo respected."""
    result = {
        'n_splits': 0,
        'min_train_size': float('inf'),
        'max_train_size': 0,
        'min_test_size': float('inf'),
        'max_test_size': 0,
        'overlap_count': 0,
        'embargo_violations': 0,
    }
    for _fold_idx, (tr_idx, te_idx) in enumerate(splitter.split(X)):
        result['n_splits'] += 1
        result['min_train_size'] = min(result['min_train_size'], len(tr_idx))
        result['max_train_size'] = max(result['max_train_size'], len(tr_idx))
        result['min_test_size'] = min(result['min_test_size'], len(te_idx))
        result['max_test_size'] = max(result['max_test_size'], len(te_idx))
        overlap = np.intersect1d(tr_idx, te_idx)
        result['overlap_count'] += len(overlap)
        # check embargo: max(train) + embargo <= min(test) (for walk-forward)
        if isinstance(splitter, PurgedWalkForwardCV):
            if tr_idx[-1] + splitter.embargo > te_idx[0]:
                result['embargo_violations'] += 1
    return result


__all__ = ['PurgedWalkForwardCV', 'PurgedKFoldCV', 'sanity_check_cv']
