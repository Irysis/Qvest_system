"""Quality metrics — alpha graduation gates.

rank_IC / ICIR / Harvey-t (NW lag 6) / DSR (Bailey-LdP) / Monotonicity (Q1-Q10 decile) /
Pareto 6-axis (alpha vs portfolio realized cor vs benchmark admit).
"""
import numpy as np
import pandas as pd
from scipy import stats


def rank_ic_per_date(scores: pd.DataFrame,
                     returns: pd.DataFrame,
                     date_col: str = "sig_date",
                     ticker_col: str = "Ticker",
                     score_col: str = "score",
                     ret_col: str = "fwd_ret_1m") -> pd.DataFrame:
    """Per sig_date Spearman rank IC between score and forward return."""
    merged = scores.merge(returns, on=[date_col, ticker_col])
    ic_list = []
    for date, grp in merged.groupby(date_col):
        if len(grp) < 30:
            continue
        rho = grp[score_col].rank().corr(grp[ret_col].rank(), method="pearson")
        ic_list.append({date_col: date, "ic": rho, "n": len(grp)})
    return pd.DataFrame(ic_list)


def summary_stats(ic_series: pd.Series) -> dict:
    """rank_IC + ICIR + NW t-stat (lag 6)."""
    s = ic_series.dropna()
    if len(s) < 12:
        return {"rank_ic": np.nan, "icir": np.nan, "t_nw_lag6": np.nan, "n": len(s)}

    mean = s.mean()
    std = s.std(ddof=1)
    icir = mean / std if std > 0 else np.nan

    # Newey-West lag 6 t-stat
    n = len(s)
    lag = 6
    centered = s - mean
    gamma0 = (centered ** 2).sum() / n
    lrv = gamma0
    for k in range(1, lag + 1):
        w = 1.0 - k / (lag + 1.0)
        gamma_k = (centered[k:].values * centered[:-k].values).sum() / n
        lrv += 2 * w * gamma_k
    se_nw = np.sqrt(max(lrv, 1e-12) / n)
    t_nw = mean / se_nw if se_nw > 0 else np.nan

    return {"rank_ic": mean, "icir": icir, "t_nw_lag6": t_nw, "n": n}


def dsr_bailey_lopez_de_prado(sr: float, n_obs: int,
                              n_trials: int = 5,
                              skew: float = 0.0,
                              kurt: float = 3.0) -> float:
    """Deflated Sharpe Ratio (Bailey-Lopez de Prado 2014).

    Z-statistic against null SR=0 with N trials penalty.
    """
    if n_obs < 12 or sr is None or np.isnan(sr):
        return np.nan
    # Expected max SR under N trials null
    euler_mascheroni = 0.5772156649
    sr_max_expect = np.sqrt(2 * np.log(max(n_trials, 1))) - \
                    euler_mascheroni / np.sqrt(2 * np.log(max(n_trials, 1)))
    if n_trials == 1:
        sr_max_expect = 0.0
    # DSR Z-statistic
    excess_kurt = kurt - 3.0
    se = np.sqrt((1.0 - skew * sr + ((excess_kurt) / 4.0) * sr ** 2) / (n_obs - 1))
    z = (sr - sr_max_expect) / max(se, 1e-12)
    return z


def monotonicity_q1_q10(scores: pd.DataFrame,
                        returns: pd.DataFrame,
                        date_col: str = "sig_date",
                        score_col: str = "score",
                        ret_col: str = "fwd_ret_1m",
                        ticker_col: str = "Ticker") -> dict:
    """Q1-Q10 decile monotonicity (Spearman rank between decile rank and mean return)."""
    merged = scores.merge(returns, on=[date_col, ticker_col])
    decile_rets = []
    for date, grp in merged.groupby(date_col):
        if len(grp) < 30:
            continue
        grp = grp.copy()
        grp["decile"] = pd.qcut(grp[score_col].rank(), 10, labels=False, duplicates="drop") + 1
        dec_mean = grp.groupby("decile")[ret_col].mean()
        decile_rets.append(dec_mean)
    if not decile_rets:
        return {"monotonicity": np.nan, "decile_means": None}
    avg_dec = pd.concat(decile_rets, axis=1).mean(axis=1)
    # Spearman rank cor between decile (1..10) and mean return
    rho, _ = stats.spearmanr(avg_dec.index.astype(float), avg_dec.values)
    return {"monotonicity": rho, "decile_means": avg_dec.to_dict()}


def pareto_portfolio_realized_cor(scores: pd.DataFrame,
                                  returns: pd.DataFrame,
                                  benchmark_scores: pd.DataFrame,
                                  date_col: str = "sig_date",
                                  ticker_col: str = "Ticker",
                                  score_col: str = "score",
                                  ret_col: str = "fwd_ret_1m",
                                  top_n: int = 20) -> dict:
    """Portfolio realized return cor vs benchmark admit portfolio.

    Top-N EW portfolio per sig_date for both candidate and benchmark scores.
    Then Pearson/Spearman/Kendall cor across monthly returns.
    """
    def top_n_port(s_df, b_df):
        merged = s_df.merge(b_df, on=[date_col, ticker_col])
        port_rets = []
        for date, grp in merged.groupby(date_col):
            top = grp.nlargest(top_n, score_col)
            port_rets.append({date_col: date, "port_ret": top[ret_col].mean()})
        return pd.DataFrame(port_rets)

    cand_port = top_n_port(scores, returns)
    bench_port = top_n_port(benchmark_scores, returns)
    joined = cand_port.merge(bench_port, on=date_col, suffixes=("_cand", "_bench"))
    if len(joined) < 12:
        return {"pearson": np.nan, "spearman": np.nan, "kendall": np.nan, "n": len(joined)}

    return {
        "pearson": joined["port_ret_cand"].corr(joined["port_ret_bench"]),
        "spearman": joined["port_ret_cand"].corr(joined["port_ret_bench"], method="spearman"),
        "kendall": joined["port_ret_cand"].corr(joined["port_ret_bench"], method="kendall"),
        "n": len(joined),
    }


# =============================================================================
# Phase 1.A — Confident-High-Low Strategy (Liao 2025 RFS)
# =============================================================================

def confident_high_low_evaluation(scores: pd.DataFrame,
                                   returns: pd.DataFrame,
                                   date_col: str = "sig_date",
                                   ticker_col: str = "Ticker",
                                   score_col: str = "score",
                                   std_col: str = "score_std",
                                   ret_col: str = "fwd_ret_1m",
                                   top_n_naive: int = 20,
                                   confidence_quantile: float = 0.5) -> dict:
    """Compare naive High-Low vs Confident-High-Low per Liao 2025 RFS.

    Naive: top-N by score, equal-weight long
    Confident: top-N by score among lowest-uncertainty (std ≤ q_confidence)

    Returns: {"naive_port_ret_mean", "naive_sr", "confident_port_ret_mean",
              "confident_sr", "sr_improvement"}
    """
    merged = scores.merge(returns, on=[date_col, ticker_col])
    if std_col not in merged.columns:
        return {"naive_sr": np.nan, "confident_sr": np.nan,
                "sr_improvement": np.nan, "note": "score_std column missing"}

    naive_rets, conf_rets = [], []
    for date, grp in merged.groupby(date_col):
        if len(grp) < top_n_naive * 2:
            continue
        # Naive: top-N by score
        naive_top = grp.nlargest(top_n_naive, score_col)
        naive_rets.append(naive_top[ret_col].mean())
        # Confident: filter to lowest-uncertainty quantile, then top-N
        std_threshold = grp[std_col].quantile(confidence_quantile)
        confident_pool = grp[grp[std_col] <= std_threshold]
        if len(confident_pool) >= top_n_naive:
            conf_top = confident_pool.nlargest(top_n_naive, score_col)
            conf_rets.append(conf_top[ret_col].mean())
        else:
            conf_rets.append(np.nan)

    naive_arr = np.array(naive_rets)
    conf_arr = np.array([r for r in conf_rets if not np.isnan(r)])

    def _sr(arr):
        if len(arr) < 12 or np.std(arr, ddof=1) == 0:
            return np.nan
        return np.mean(arr) / np.std(arr, ddof=1) * np.sqrt(12)

    naive_sr = _sr(naive_arr)
    conf_sr = _sr(conf_arr)
    return {
        "naive_port_ret_mean_monthly": float(np.mean(naive_arr)) if len(naive_arr) else np.nan,
        "naive_sr_annualized": naive_sr,
        "confident_port_ret_mean_monthly": float(np.mean(conf_arr)) if len(conf_arr) else np.nan,
        "confident_sr_annualized": conf_sr,
        "sr_improvement": (conf_sr - naive_sr) if not np.isnan(naive_sr) and not np.isnan(conf_sr) else np.nan,
        "n_naive_months": len(naive_arr),
        "n_confident_months": len(conf_arr),
        "confidence_quantile_used": confidence_quantile,
    }


def ci_coverage(actual: pd.Series,
                lower: pd.Series,
                upper: pd.Series,
                target_coverage: float = 0.90) -> dict:
    """Bootstrap CI calibration check: actual coverage vs target.

    Coverage > target_coverage: CI too wide (under-confident model)
    Coverage < target_coverage: CI too narrow (over-confident model)
    Well-calibrated: coverage ≈ target_coverage
    """
    a = np.asarray(actual)
    lo = np.asarray(lower)
    up = np.asarray(upper)
    in_band = (a >= lo) & (a <= up)
    coverage = float(np.mean(in_band))
    return {
        "actual_coverage": coverage,
        "target_coverage": target_coverage,
        "deviation": coverage - target_coverage,
        "n": len(a),
        "calibration": "well" if abs(coverage - target_coverage) < 0.05
                       else ("under_confident" if coverage > target_coverage else "over_confident"),
    }


# =============================================================================
# Phase 1.B — Cost-adjusted IC / Net-of-Cost Sharpe Proxy (Jensen-Kelly 2022)
# =============================================================================

def portfolio_turnover_per_date(scores: pd.DataFrame,
                                 date_col: str = "sig_date",
                                 ticker_col: str = "Ticker",
                                 score_col: str = "score",
                                 top_n: int = 20) -> pd.DataFrame:
    """Per-date top-N portfolio turnover (one-way, % of weight).

    turnover_t = sum |w_t - w_{t-1}| / 2  (one-way, 0~1 range)
    Equal-weight top-N: turnover = (# new entries) / N
    """
    dates = sorted(scores[date_col].unique())
    prev_top = set()
    records = []
    for date in dates:
        grp = scores[scores[date_col] == date]
        if len(grp) < top_n:
            continue
        top_tickers = set(grp.nlargest(top_n, score_col)[ticker_col].values)
        if len(prev_top) == 0:
            turnover = 0.0  # first period: no churn
        else:
            new_entries = len(top_tickers - prev_top)
            turnover = new_entries / top_n
        records.append({date_col: date, "turnover_oneway": turnover, "n_top": len(top_tickers)})
        prev_top = top_tickers
    return pd.DataFrame(records)


def cost_adjusted_ic(scores: pd.DataFrame,
                      returns: pd.DataFrame,
                      date_col: str = "sig_date",
                      ticker_col: str = "Ticker",
                      score_col: str = "score",
                      ret_col: str = "fwd_ret_1m",
                      top_n: int = 20,
                      cost_bps_oneway: float = 15.0) -> dict:
    """Net-of-cost IC + IR proxy.

    Net portfolio return per month = top-N EW return - turnover * (2 × cost_bps_oneway / 10000)
    Then compute net IC = corr(score_rank, net_ret) — but more useful is portfolio-level net SR proxy.
    """
    merged = scores.merge(returns, on=[date_col, ticker_col])
    to_df = portfolio_turnover_per_date(scores, date_col, ticker_col, score_col, top_n)
    if len(to_df) == 0:
        return {"net_port_sr_annualized": np.nan, "gross_port_sr_annualized": np.nan,
                "cost_drag_annualized_pp": np.nan, "mean_turnover_monthly": np.nan,
                "n_months": 0}

    port_rets = []
    for date, grp in merged.groupby(date_col):
        if len(grp) < top_n:
            continue
        top = grp.nlargest(top_n, score_col)
        port_rets.append({date_col: date, "port_ret_gross": top[ret_col].mean()})
    port_df = pd.DataFrame(port_rets)
    port_df = port_df.merge(to_df, on=date_col, how="left")
    port_df["turnover_oneway"] = port_df["turnover_oneway"].fillna(0)
    cost_per_month = port_df["turnover_oneway"] * (2 * cost_bps_oneway / 10000.0)  # round-trip
    port_df["port_ret_net"] = port_df["port_ret_gross"] - cost_per_month

    def _sr(arr):
        a = np.asarray(arr)
        if len(a) < 12 or np.std(a, ddof=1) == 0:
            return np.nan
        return np.mean(a) / np.std(a, ddof=1) * np.sqrt(12)

    gross_sr = _sr(port_df["port_ret_gross"])
    net_sr = _sr(port_df["port_ret_net"])
    cost_drag_yr = float(np.mean(cost_per_month) * 12)

    return {
        "gross_port_sr_annualized": gross_sr,
        "net_port_sr_annualized": net_sr,
        "cost_drag_annualized_pp": cost_drag_yr * 100,
        "mean_turnover_monthly": float(port_df["turnover_oneway"].mean()),
        "annualized_turnover": float(port_df["turnover_oneway"].mean() * 12),
        "n_months": len(port_df),
        "cost_bps_oneway_assumed": cost_bps_oneway,
    }
