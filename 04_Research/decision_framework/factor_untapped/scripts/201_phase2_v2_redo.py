"""
STR_1722 Phase 2 v2 — Statistical Factor Redo (proper per-stock variation)

v1 design 흠: p_breakout_up/down/e_fpt = closed-form constant (sigma 무관) → IC 산출 invalid.
v2 fix: 종목별 historical sample 기반 (cross-section variation 명시).

7 new factors (v1 retain 2 + v2 신규 5):
  Retain (v1 valid):
    1. recurrence_interval  (v1 valid, ICIR_5y -0.221, sp_stable)
    2. ou_half_life         (v1 valid, ICIR_5y +0.204)

  New v2 (proper variation):
    3. p_breakout_down_5pct_abs : Empirical P(R_21d < -5% absolute) from 252d sample
    4. p_breakout_up_5pct_abs   : Empirical P(R_21d > +5% absolute) from 252d sample
    5. autocorr_lag1_252d       : Pearson lag-1 autocorrelation (mean reversion)
    6. var_es_ratio_5pct        : ES_5% / VaR_5% (Embrechts 2002 tail thickness)
    7. realized_kurt_252d       : 4th-moment sample kurtosis (direct, not Z)

PIT: walk-forward 252d window, all factors at sig_date t use prices through t-1.

Output:
  - outputs/statistical_breakout_v2_factor_panel.parquet
"""

import argparse
import json
import math
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import pandas as pd

BASE = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
OUT_DIR = BASE / "04_Research/decision_framework/factor_untapped/outputs"
FEATURES = BASE / "04_Research/decision_framework/cross_section_distribution/outputs/per_stock_features.parquet"

WIN = 252
H_FORWARD = 21
ABS_THRESHOLD = 0.05  # +/- 5% absolute log return threshold


def safe_log_returns(close: np.ndarray) -> np.ndarray:
    out = np.full(len(close), np.nan)
    valid = (close > 0) & np.roll(close > 0, 1)
    valid[0] = False
    out[valid] = np.log(close[valid] / np.roll(close, 1)[valid])
    return out


def p_breakout_empirical_h(log_ret_window: np.ndarray, h: int, threshold: float, direction: str) -> float:
    """Empirical h-day cumulative log return breakout probability.
    Bootstrap h-day cumulative sums from sliding window.
    """
    n = len(log_ret_window)
    if n < h + 30:
        return np.nan
    cum_h = np.array([log_ret_window[i:i + h].sum() for i in range(n - h + 1)])
    if direction == "down":
        return float(np.mean(cum_h < -threshold))
    return float(np.mean(cum_h > threshold))


def autocorr_lag1(log_ret_window: np.ndarray) -> float:
    v = log_ret_window[~np.isnan(log_ret_window)]
    if len(v) < 30:
        return np.nan
    if np.std(v) == 0:
        return np.nan
    return float(np.corrcoef(v[:-1], v[1:])[0, 1])


def var_es_ratio(log_ret_window: np.ndarray, alpha: float = 0.05) -> float:
    """ES_alpha / VaR_alpha (tail extremity). Higher = thicker tail."""
    v = log_ret_window[~np.isnan(log_ret_window)]
    if len(v) < 50:
        return np.nan
    var_a = np.quantile(v, alpha)
    tail = v[v <= var_a]
    if len(tail) == 0 or var_a == 0:
        return np.nan
    es_a = np.mean(tail)
    return float(es_a / var_a) if var_a != 0 else np.nan


def realized_kurt(log_ret_window: np.ndarray) -> float:
    v = log_ret_window[~np.isnan(log_ret_window)]
    if len(v) < 30:
        return np.nan
    m = np.mean(v)
    s = np.std(v, ddof=1)
    if s == 0:
        return np.nan
    return float(np.mean((v - m) ** 4) / s ** 4 - 3.0)


def recurrence_interval(log_ret_window: np.ndarray, k: float = 2.0) -> float:
    v = log_ret_window[~np.isnan(log_ret_window)]
    if len(v) < 30:
        return np.nan
    sigma = np.std(v, ddof=1)
    if sigma == 0:
        return np.nan
    extremes = np.where(np.abs(v) > k * sigma)[0]
    if len(extremes) < 2:
        return float(len(v))
    gaps = np.diff(extremes)
    return float(np.mean(gaps))


def ou_half_life(log_close_window: np.ndarray) -> float:
    v = log_close_window[~np.isnan(log_close_window)]
    if len(v) < 30:
        return np.nan
    x = v[:-1]
    dx = np.diff(v)
    if np.std(x) == 0:
        return np.nan
    cov = np.cov(x, dx, ddof=1)
    var_x = cov[0, 0]
    if var_x == 0:
        return np.nan
    b = cov[0, 1] / var_x
    if b >= 0 or 1 + b <= 0:
        return np.nan
    hl = -np.log(2) / np.log(1 + b)
    return float(hl) if 0 < hl < 1000 else np.nan


def process_ticker(args):
    ticker, df_t, sig_dates = args
    df_t = df_t.sort_values("Date").reset_index(drop=True)
    if len(df_t) < WIN + 1:
        return None
    out_rows = []
    close = df_t["Close"].values.astype(float)
    log_close = np.log(np.where(close > 0, close, np.nan))
    log_ret = safe_log_returns(close)
    dates = df_t["Date"].values.astype('datetime64[D]')

    for sd in sig_dates:
        sd_np = np.datetime64(pd.Timestamp(sd).date(), 'D')
        idx = int(np.searchsorted(dates, sd_np, side='right')) - 1
        if idx < WIN:
            continue
        window_log_close = log_close[idx - WIN + 1:idx + 1]
        window_log_ret = log_ret[idx - WIN + 1:idx + 1]
        window_log_ret_clean = window_log_ret[~np.isnan(window_log_ret)]
        if len(window_log_ret_clean) < 60:
            continue
        try:
            row = {
                "Date": pd.Timestamp(sd),
                "Ticker": ticker,
                "recurrence_interval": recurrence_interval(window_log_ret_clean, k=2.0),
                "ou_half_life": ou_half_life(window_log_close[~np.isnan(window_log_close)]),
                "p_breakout_down_5pct": p_breakout_empirical_h(window_log_ret_clean, H_FORWARD, ABS_THRESHOLD, "down"),
                "p_breakout_up_5pct": p_breakout_empirical_h(window_log_ret_clean, H_FORWARD, ABS_THRESHOLD, "up"),
                "autocorr_lag1": autocorr_lag1(window_log_ret_clean),
                "var_es_ratio_5pct": var_es_ratio(window_log_ret_clean, alpha=0.05),
                "realized_kurt": realized_kurt(window_log_ret_clean),
            }
            out_rows.append(row)
        except Exception as e:
            print(f"[ERR {ticker} @ {sd}] {type(e).__name__}: {e}", flush=True)
            continue
    if not out_rows:
        return None
    return pd.DataFrame(out_rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", default=str(OUT_DIR / "statistical_breakout_v2_factor_panel.parquet"))
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    t0 = time.time()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("[1] Load features panel (daily Close per ticker)")
    feat = pd.read_parquet(FEATURES, columns=["Date", "Ticker", "Close"])
    feat["Date"] = pd.to_datetime(feat["Date"])
    feat = feat.dropna(subset=["Close"])
    feat = feat[feat["Close"] > 0]
    print(f"  rows: {len(feat):,} | tickers: {feat['Ticker'].nunique()}")

    print("[2] Load monthly sig_dates")
    ic = pd.read_parquet(BASE / ".cache/factor_db/factor_ic_monthly.parquet", columns=["Date"])
    sig_dates = sorted(pd.to_datetime(ic["Date"].unique()))
    print(f"  sig_dates: {len(sig_dates)}")

    tickers = sorted(feat["Ticker"].unique())
    groups = [(tk, feat[feat["Ticker"] == tk], sig_dates) for tk in tickers]
    out_frames = []
    done = 0
    skipped = 0
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(process_ticker, g): g[0] for g in groups}
        for fut in as_completed(futs):
            done += 1
            res = fut.result()
            if res is None or len(res) == 0:
                skipped += 1
            else:
                out_frames.append(res)
            if done % 100 == 0:
                print(f"  [{done}/{len(tickers)}] skipped={skipped}")

    out = pd.concat(out_frames, ignore_index=True)
    out = out.sort_values(["Date", "Ticker"]).reset_index(drop=True)
    out.to_parquet(args.output, index=False)

    summary = {
        "strategy_id": "STR_1722_Factor_Untapped_Statistical_Breakout_v2",
        "phase": "Phase 2 v2 — proper per-stock variation",
        "factors": [
            "recurrence_interval (v1 retain, Yamasaki 2005)",
            "ou_half_life (v1 retain, Phillips-Yu 2009)",
            "p_breakout_down_5pct (empirical bootstrap, h=21d threshold=-5%)",
            "p_breakout_up_5pct (empirical bootstrap, h=21d threshold=+5%)",
            "autocorr_lag1 (mean reversion, AR(1) coefficient)",
            "var_es_ratio_5pct (Embrechts 2002 tail thickness)",
            "realized_kurt (sample kurtosis 4th moment)"
        ],
        "spec": {"window": WIN, "horizon_h": H_FORWARD, "abs_threshold": ABS_THRESHOLD},
        "n_rows": int(len(out)),
        "n_tickers_processed": int(out["Ticker"].nunique()),
        "n_tickers_skipped": skipped,
        "elapsed_min": (time.time() - t0) / 60,
        "built_at": pd.Timestamp.now().isoformat(),
    }
    Path(args.output).with_suffix(".meta.json").write_text(json.dumps(summary, indent=2, default=str))
    print(f"[Done] saved {args.output}")
    print(json.dumps(summary, indent=2, default=str))


if __name__ == "__main__":
    main()
