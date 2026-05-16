"""Walk-forward cross-validation — PIT strict (AX-002 정합).

60 month training + 12 month validation + roll forward 12 months.
No peek-ahead. OOS lockbox = 마지막 N folds.
"""
import pandas as pd
from typing import Iterator, Tuple


def walk_forward_folds(sig_dates: pd.Series,
                       train_months: int = 60,
                       val_months: int = 12,
                       step_months: int = 12,
                       lockbox_folds: int = 2) -> Iterator[Tuple[int, pd.Timestamp, pd.Timestamp,
                                                                  pd.Timestamp, pd.Timestamp,
                                                                  str]]:
    """Yield walk-forward (fold_id, train_start, train_end, val_start, val_end, mode).

    Args:
        sig_dates: sorted unique sig_date Series (monthly)
        train_months: training window length (months)
        val_months: validation window length (months)
        step_months: roll forward step (months)
        lockbox_folds: last N folds = OOS lockbox (held out from any model selection)

    Yields:
        (fold_id, train_start, train_end, val_start, val_end, mode) per fold
        mode: 'is' (in-sample CV) or 'lockbox' (OOS hold-out)
    """
    dates = sorted(pd.to_datetime(sig_dates.unique()))
    n = len(dates)

    folds = []
    i = train_months
    fold_id = 0
    while i + val_months <= n:
        train_start = dates[i - train_months]
        train_end = dates[i - 1]
        val_start = dates[i]
        val_end = dates[min(i + val_months - 1, n - 1)]
        folds.append((fold_id, train_start, train_end, val_start, val_end))
        fold_id += 1
        i += step_months

    n_folds = len(folds)
    for j, (fid, ts, te, vs, ve) in enumerate(folds):
        mode = "lockbox" if j >= n_folds - lockbox_folds else "is"
        yield (fid, ts, te, vs, ve, mode)


def split_train_val(df: pd.DataFrame,
                    date_col: str,
                    train_start: pd.Timestamp,
                    train_end: pd.Timestamp,
                    val_start: pd.Timestamp,
                    val_end: pd.Timestamp) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Split DataFrame into train/val per date window."""
    df[date_col] = pd.to_datetime(df[date_col])
    train = df[(df[date_col] >= train_start) & (df[date_col] <= train_end)]
    val = df[(df[date_col] >= val_start) & (df[date_col] <= val_end)]
    return train, val


# =============================================================================
# Phase 1.B helper — Per-fold turnover (Jensen-Kelly-Malamud-Pedersen 2022)
# =============================================================================

def fold_turnover_summary(pred_fold: pd.DataFrame,
                          date_col: str = "sig_date",
                          ticker_col: str = "Ticker",
                          score_col: str = "score",
                          top_n: int = 20) -> dict:
    """Per-fold mean monthly + annualized turnover (one-way).

    Args:
        pred_fold: DataFrame with (date_col, ticker_col, score_col) for one fold
        top_n: top-N portfolio size (default 20 = Production Constraint)

    Returns:
        {"mean_turnover_monthly", "annualized_turnover", "n_months"}
    """
    import numpy as np
    dates = sorted(pred_fold[date_col].unique())
    prev_top = set()
    turnovers = []
    for date in dates:
        grp = pred_fold[pred_fold[date_col] == date]
        if len(grp) < top_n:
            continue
        top_tickers = set(grp.nlargest(top_n, score_col)[ticker_col].values)
        if len(prev_top) > 0:
            new_entries = len(top_tickers - prev_top)
            turnovers.append(new_entries / top_n)
        prev_top = top_tickers
    if not turnovers:
        return {"mean_turnover_monthly": float("nan"),
                "annualized_turnover": float("nan"),
                "n_months": 0}
    arr = np.asarray(turnovers)
    return {
        "mean_turnover_monthly": float(arr.mean()),
        "annualized_turnover": float(arr.mean() * 12),
        "n_months": len(arr),
    }
