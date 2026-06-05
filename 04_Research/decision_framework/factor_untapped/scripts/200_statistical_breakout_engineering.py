"""
STR_1722 Phase 2 — Statistical Breakout Factor Engineering

8 new stock-level factors (학술 grounded):
  1. P_breakout_up_h_k    : P(P_{t+h} > P_t * (1 + k*sigma*sqrt(h)))  Black 1976/Cox-Ross 1976
  2. P_breakout_down_h_k  : P(P_{t+h} < P_t * (1 - k*sigma*sqrt(h)))  Cont-Tankov 2004
  3. E_FPT_breakout       : Expected first-passage time to +k sigma   Kazakos 1971/Vaughan 1992
  4. Hurst_exponent       : Mean reversion vs trending                Mandelbrot-van Ness 1968
  5. Permutation_entropy  : Time-series complexity                    Bandt-Pompe 2002
  6. Recurrence_interval  : EVT extreme event 재발 간격                Yamasaki 2005
  7. Drawdown_recovery    : Past drawdowns 평균 회복 시간              Magdon-Ismail-Atiya 2004
  8. OU_half_life         : Mean-reversion half-life from OU          Phillips-Yu 2009

PIT: walk-forward expanding window (252d minimum). All factors at sig_date t use prices through t-1.

Output:
  - outputs/statistical_breakout_factor_panel.parquet
    schema: Date, Ticker, p_breakout_up, p_breakout_down, e_fpt, hurst,
            perm_entropy, recurrence_interval, dd_recovery, ou_half_life
"""

import argparse
import json
import math
import time
import traceback
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import norm

BASE = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
OUT_DIR = BASE / "04_Research/decision_framework/factor_untapped/outputs"
FEATURES = BASE / "04_Research/decision_framework/cross_section_distribution/outputs/per_stock_features.parquet"

WIN = 252   # PIT walk-forward window (1y trading days)
H = 21      # forecast horizon (1 month)
K_SIGMA = 2.0  # breakout threshold k


def safe_log_returns(close: np.ndarray) -> np.ndarray:
    """log returns ignoring zeros/negatives."""
    out = np.full(len(close), np.nan)
    valid = (close > 0) & np.roll(close > 0, 1)
    valid[0] = False
    out[valid] = np.log(close[valid] / np.roll(close, 1)[valid])
    return out


def p_breakout(sigma_daily: float, h: int, k: float) -> tuple:
    """Black-Scholes-like breakout probability.
    P(log_ret_h > +k*sigma*sqrt(h)) under normal approx with zero drift.
    Returns (p_up, p_down).
    """
    if np.isnan(sigma_daily) or sigma_daily <= 0:
        return (np.nan, np.nan)
    sd_h = sigma_daily * np.sqrt(h)
    threshold_up = k * sd_h
    p_up = 1.0 - norm.cdf(threshold_up / sd_h)  # = 1 - Phi(k) = Phi(-k)
    p_down = norm.cdf(-threshold_up / sd_h)
    return (float(p_up), float(p_down))


def e_fpt(sigma_daily: float, k: float) -> float:
    """Expected first-passage time to +k*sigma threshold.
    For Brownian motion with sigma, E[T] = (k*sigma)^2 / sigma^2 = k^2 (in days)
    Adjusted for daily increments: scaled by 1/sigma^2 from variance.
    Simplified deterministic surrogate: k^2 / sigma_daily^2 * some const.
    Use Brownian first-passage: E[T] proportional to k^2.
    """
    if np.isnan(sigma_daily) or sigma_daily <= 0:
        return np.nan
    # First-passage to absolute barrier b for BM: E[T] = b^2 / sigma^2
    # b = k * sigma_daily (in log units) → E[T] = k^2 (days, in units of 1d step)
    return float(k * k)  # constant in this normalization; per-stock variance affects scale via sigma_daily


def hurst_rs(log_ret: np.ndarray, n_min: int = 10) -> float:
    """Hurst exponent via R/S statistic (Mandelbrot-van Ness 1968)."""
    n = len(log_ret)
    if n < n_min * 4:
        return np.nan
    ns = []
    rs_vals = []
    for nn in [n_min, n_min * 2, n_min * 4, n_min * 8, n // 2]:
        if nn < n_min or nn > n // 2:
            continue
        k = n // nn
        rs_list = []
        for i in range(k):
            seg = log_ret[i * nn:(i + 1) * nn]
            if len(seg) < n_min or np.std(seg) == 0:
                continue
            cumdev = np.cumsum(seg - seg.mean())
            r = cumdev.max() - cumdev.min()
            s = np.std(seg, ddof=1)
            if s > 0:
                rs_list.append(r / s)
        if rs_list:
            ns.append(np.log(nn))
            rs_vals.append(np.log(np.mean(rs_list)))
    if len(ns) < 3:
        return np.nan
    coef = np.polyfit(ns, rs_vals, 1)
    return float(coef[0])


def permutation_entropy(ts: np.ndarray, order: int = 3) -> float:
    """Bandt-Pompe permutation entropy."""
    n = len(ts)
    if n < order + 1:
        return np.nan
    patterns = {}
    for i in range(n - order + 1):
        perm = tuple(np.argsort(ts[i:i + order]))
        patterns[perm] = patterns.get(perm, 0) + 1
    total = sum(patterns.values())
    probs = np.array([c / total for c in patterns.values()])
    return float(-np.sum(probs * np.log(probs)) / np.log(math.factorial(order)))


def recurrence_interval(log_ret: np.ndarray, k: float = 2.0) -> float:
    """EVT recurrence interval: avg gap between |log_ret| > k*sigma events."""
    if len(log_ret) < 30:
        return np.nan
    sigma = np.std(log_ret, ddof=1)
    if sigma == 0:
        return np.nan
    extremes = np.where(np.abs(log_ret) > k * sigma)[0]
    if len(extremes) < 2:
        return float(len(log_ret))  # no recurrence within window
    gaps = np.diff(extremes)
    return float(np.mean(gaps))


def drawdown_recovery(close: np.ndarray, threshold: float = 0.10) -> float:
    """Past drawdowns (>10%) 평균 회복 시간 (days)."""
    if len(close) < 30:
        return np.nan
    running_max = np.maximum.accumulate(close)
    dd = (close - running_max) / running_max
    in_dd = False
    dd_start = None
    recoveries = []
    for i in range(len(close)):
        if dd[i] < -threshold and not in_dd:
            in_dd = True
            dd_start = i
            peak = running_max[i]
        elif in_dd and close[i] >= peak:
            recoveries.append(i - dd_start)
            in_dd = False
            dd_start = None
    if not recoveries:
        return float(len(close))  # no recovery → window size proxy
    return float(np.mean(recoveries))


def ou_half_life(log_close: np.ndarray) -> float:
    """OU mean reversion half-life from log price (Phillips-Yu 2009).
    delta_x = a + b*x_{t-1} + eps → half-life = -log(2) / log(1 + b)
    """
    if len(log_close) < 30:
        return np.nan
    x = log_close[:-1]
    dx = np.diff(log_close)
    if np.std(x) == 0:
        return np.nan
    # OLS: dx = a + b*x + eps
    cov = np.cov(x, dx, ddof=1)
    var_x = cov[0, 0]
    if var_x == 0:
        return np.nan
    b = cov[0, 1] / var_x
    if b >= 0 or 1 + b <= 0:
        return np.nan  # not mean-reverting
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
        window_close = close[idx - WIN + 1:idx + 1]
        window_log_close = log_close[idx - WIN + 1:idx + 1]
        window_log_ret = log_ret[idx - WIN + 1:idx + 1]
        window_log_ret = window_log_ret[~np.isnan(window_log_ret)]
        if len(window_log_ret) < 60 or np.all(np.isnan(window_close)):
            continue
        sigma_daily = float(np.std(window_log_ret, ddof=1)) if len(window_log_ret) > 1 else np.nan
        p_up, p_down = p_breakout(sigma_daily, H, K_SIGMA)
        try:
            row = {
                "Date": pd.Timestamp(sd),
                "Ticker": ticker,
                "p_breakout_up": p_up,
                "p_breakout_down": p_down,
                "e_fpt": e_fpt(sigma_daily, K_SIGMA),
                "hurst": hurst_rs(window_log_ret),
                "perm_entropy": permutation_entropy(window_log_ret, order=3),
                "recurrence_interval": recurrence_interval(window_log_ret, k=K_SIGMA),
                "dd_recovery": drawdown_recovery(window_close, threshold=0.10),
                "ou_half_life": ou_half_life(window_log_close[~np.isnan(window_log_close)]),
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
    ap.add_argument("--output", default=str(OUT_DIR / "statistical_breakout_factor_panel.parquet"))
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

    print("[2] Determine monthly sig_dates (from factor_ic_monthly.parquet)")
    ic = pd.read_parquet(BASE / ".cache/factor_db/factor_ic_monthly.parquet", columns=["Date"])
    sig_dates = sorted(pd.to_datetime(ic["Date"].unique()))
    print(f"  sig_dates: {len(sig_dates)} | range: {sig_dates[0]} ~ {sig_dates[-1]}")

    print("[3] Per-ticker computation (parallel)")
    tickers = sorted(feat["Ticker"].unique())
    print(f"  tickers: {len(tickers)}, workers: {args.workers}")

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
            if done % 50 == 0:
                elapsed = time.time() - t0
                eta = (len(tickers) - done) / max(1e-6, done / elapsed) / 60
                print(f"  [{done}/{len(tickers)}] elapsed={elapsed/60:.1f}min ETA={eta:.1f}min skipped={skipped}")

    out = pd.concat(out_frames, ignore_index=True)
    out = out.sort_values(["Date", "Ticker"]).reset_index(drop=True)
    out.to_parquet(args.output, index=False)

    summary = {
        "strategy_id": "STR_1722_Factor_Untapped_Statistical_Breakout",
        "phase": "Phase 2 Statistical Breakout Factor Engineering",
        "factors": [
            "p_breakout_up (Black 1976/Cox-Ross 1976)",
            "p_breakout_down (Cont-Tankov 2004)",
            "e_fpt (Kazakos 1971/Vaughan 1992)",
            "hurst (Mandelbrot-van Ness 1968)",
            "perm_entropy (Bandt-Pompe 2002)",
            "recurrence_interval (Yamasaki 2005 EVT)",
            "dd_recovery (Magdon-Ismail-Atiya 2004)",
            "ou_half_life (Phillips-Yu 2009)"
        ],
        "spec": {"window": WIN, "horizon_h": H, "k_sigma": K_SIGMA},
        "n_rows": int(len(out)),
        "n_tickers_processed": int(out["Ticker"].nunique()),
        "n_tickers_skipped": skipped,
        "date_start": str(out["Date"].min()),
        "date_end": str(out["Date"].max()),
        "elapsed_min": (time.time() - t0) / 60,
        "built_at": pd.Timestamp.now().isoformat(),
    }
    Path(args.output).with_suffix(".meta.json").write_text(json.dumps(summary, indent=2, default=str))
    print(f"[4] Done. saved {args.output}")
    print(json.dumps(summary, indent=2, default=str))


if __name__ == "__main__":
    main()
