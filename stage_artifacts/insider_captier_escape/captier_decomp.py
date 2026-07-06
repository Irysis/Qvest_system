"""captier_decomp.py — CORE cap-tier ESCAPE decomposition (ANALYSIS ONLY).
Does exec insider net-buy have edge WITHIN mega/large-cap tiers (escape) or only mid-cap (trap)?

Metrics per tier:
  (a) rank-IC: cross-sectional Spearman(exec_net_rank, F1_rank) among signal-firms in tier, monthly.
      Reported as mean IC, NW-adjusted t (Newey-West lag=3 on the monthly IC series), ICIR annualized.
  (b) LONG-vs-REST active return: within tier, form monthly EW long of high-net-buy firms
      (net_buy > 0, i.e. positive exec net buying) vs the tier's non-signal universe average.
      active_t = NW t-stat of the monthly active-return series. NO cumprod — mean/NW only.
  (c) buy-only spread: EW return of positive-net-buy signal firms minus tier universe EW.

Honest: 42-mo, gappy (2005-06 + 2024-26). DIRECTIONAL read, NOT graduation.
All returns are RAW monthly mret (already computed by RAWDATA compounding); active = signal - universe.
metric_type = 'directional_read' (event-cohort active, NOT canonical_screen_bt).
"""
import numpy as np, pandas as pd
R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/stage_artifacts/insider_captier_escape"

panel = pd.read_parquet(OUT + "/exec_captier_panel.parquet")
univ = pd.read_parquet(OUT + "/universe_monthly.parquet")


def nw_t(x, lag=3):
    """Newey-West t-stat of mean(x) != 0. Returns (mean, t, n)."""
    x = np.asarray(x, float); x = x[~np.isnan(x)]
    n = len(x)
    if n < 4:
        return np.nan, np.nan, n
    mu = x.mean(); e = x - mu
    g0 = (e @ e) / n
    s = g0
    for k in range(1, min(lag, n - 1) + 1):
        gk = (e[k:] @ e[:-k]) / n
        s += 2 * (1 - k / (lag + 1)) * gk
    se = np.sqrt(max(s, 1e-18) / n)
    return mu, mu / se, n


def tier_stats(tiers, label):
    """Compute rank-IC series + long-vs-universe active series for a tier-set."""
    p = panel[panel.tier.isin(tiers)].copy()
    u = univ[univ.tier.isin(tiers)].copy()
    ics, act_long, act_buy = [], [], []
    months = sorted(p.ym.unique())
    n_names = []
    for ym in months:
        g = p[p.ym == ym]
        ug = u[u.ym == ym]
        if len(g) < 3 or g.exec_net.std() == 0 or g.F1.notna().sum() < 3:
            continue
        # (a) cross-sectional rank-IC among signal firms in tier
        ic = np.corrcoef(g.exec_net.rank(), g.F1.rank())[0, 1]
        if np.isfinite(ic):
            ics.append((ym, ic))
        # (b) long = positive-net-buy firms EW; universe = ALL tier universe EW that month
        buy = g[g.exec_net > 0]
        if len(buy) >= 2 and len(ug) >= 5:
            uni_ew = ug.F1.mean()   # tier universe forward EW (benchmark within tier)
            act_long.append((ym, buy.F1.mean() - uni_ew))
            n_names.append(len(buy))
        # (c) buy vs sell spread within signal firms
        sell = g[g.exec_net < 0]
        if len(buy) >= 2 and len(sell) >= 2:
            act_buy.append((ym, buy.F1.mean() - sell.F1.mean()))
    ic_ser = np.array([v for _, v in ics])
    al_ser = np.array([v for _, v in act_long])
    ab_ser = np.array([v for _, v in act_buy])
    ic_m, ic_t, ic_n = nw_t(ic_ser)
    icir = ic_ser.mean() / ic_ser.std() * np.sqrt(12) if len(ic_ser) > 1 and ic_ser.std() > 0 else np.nan
    al_m, al_t, al_n = nw_t(al_ser)
    ab_m, ab_t, ab_n = nw_t(ab_ser)
    return {
        "tier": label,
        "n_signal_months": len(p.ym.unique()),
        "n_signal_firmmonths": len(p),
        "ic_n": ic_n, "ic_mean": ic_m, "ic_t": ic_t, "icir": icir,
        "long_n": al_n, "long_active_mean_bps": al_m * 1e4 if np.isfinite(al_m) else np.nan, "long_active_t": al_t,
        "avg_buy_names": np.mean(n_names) if n_names else np.nan,
        "buysell_n": ab_n, "buysell_spread_bps": ab_m * 1e4 if np.isfinite(ab_m) else np.nan, "buysell_t": ab_t,
    }


tiers_def = {
    "MEGA (top-10)": ["MEGA"],
    "MID (11-30)": ["MID"],
    "LARGE (11-50)": ["MID", "LARGE50"],
    "BIGCAP (top-50)": ["MEGA", "MID", "LARGE50"],
    "REST (>50)": ["REST"],
    "ALL universe": ["MEGA", "MID", "LARGE50", "REST"],
}
rows = [tier_stats(t, lbl) for lbl, t in tiers_def.items()]
res = pd.DataFrame(rows)
pd.set_option("display.width", 200, "display.max_columns", 30)
print("=== EXEC INSIDER NET-BUY: CAP-TIER DECOMPOSITION (directional, 42-mo gappy) ===")
print(res.to_string(index=False))
res.to_csv(OUT + "/captier_decomp.csv", index=False)

# coverage by tier
print("\n=== COVERAGE: payers/month by tier ===")
cov = panel.groupby(["tier"]).agg(
    firm_months=("Ticker", "size"),
    distinct_months=("ym", "nunique"),
    avg_per_month=("Ticker", lambda s: len(s) / panel.loc[s.index, "ym"].nunique())).reset_index()
print(cov.to_string(index=False))
# per-month tier payer counts
cov2 = panel.groupby(["ym", "tier"]).size().unstack(fill_value=0)
print("\navg payers/month by tier:", {c: round(cov2[c].mean(), 1) for c in cov2.columns})
print("median payers/month by tier:", {c: int(cov2[c].median()) for c in cov2.columns})
cov2.to_csv(OUT + "/coverage_by_tier_month.csv")

# recent-only (2024-26) vs backfill (2005-06) split for honesty
print("\n=== RECENT-ONLY (2024-03+) cap-tier (the well-structured window) ===")
panel_r = panel[panel.ym >= "2024-01"]
globals()['panel'] = panel_r
univ_r = univ[univ.ym >= "2024-01"]
globals()['univ'] = univ_r
rows_r = [tier_stats(t, lbl) for lbl, t in tiers_def.items()]
print(pd.DataFrame(rows_r).to_string(index=False))
pd.DataFrame(rows_r).to_csv(OUT + "/captier_decomp_recent.csv", index=False)
