"""mega_probe.py — focused probe of the MEGA/large-cap tier (the escape claim).
Is there GENUINE mega-cap picking skill, or is the apparent MEGA buy-vs-sell spread noise?
Checks: (1) MEGA buy-only long-active month-by-month sign consistency,
(2) sign-only signal (ignore magnitude) rank-IC in MEGA (robustness to amount outliers),
(3) monthly n-names in MEGA (power), (4) recent 25-mo isolate.
Directional read only. NW t already in captier_decomp; here we inspect the raw monthly series.
"""
import numpy as np, pandas as pd
R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/stage_artifacts/insider_captier_escape"
panel = pd.read_parquet(OUT + "/exec_captier_panel.parquet")
univ = pd.read_parquet(OUT + "/universe_monthly.parquet")


def nw_t(x, lag=3):
    x = np.asarray(x, float); x = x[~np.isnan(x)]; n = len(x)
    if n < 4: return np.nan, np.nan, n
    mu = x.mean(); e = x - mu; g0 = (e @ e) / n; s = g0
    for k in range(1, min(lag, n - 1) + 1):
        s += 2 * (1 - k / (lag + 1)) * (e[k:] @ e[:-k]) / n
    return mu, mu / np.sqrt(max(s, 1e-18) / n), n


for lbl, tiers in [("MEGA", ["MEGA"]), ("BIGCAP top-50", ["MEGA", "MID", "LARGE50"])]:
    p = panel[panel.tier.isin(tiers)]; u = univ[univ.tier.isin(tiers)]
    rows = []
    for ym in sorted(p.ym.unique()):
        g = p[p.ym == ym]; ug = u[u.ym == ym]
        buy = g[g.exec_net > 0]; sell = g[g.exec_net < 0]
        if len(buy) >= 1 and len(ug) >= 5:
            la = buy.F1.mean() - ug.F1.mean()
        else:
            la = np.nan
        rows.append(dict(ym=ym, n_buy=len(buy), n_sell=len(sell), n_uni=len(ug),
                         buy_ret=buy.F1.mean() if len(buy) else np.nan,
                         uni_ret=ug.F1.mean() if len(ug) else np.nan, long_active=la))
    df = pd.DataFrame(rows)
    la = df.long_active.dropna()
    pos = (la > 0).sum(); tot = len(la)
    m, t, n = nw_t(la.values)
    print(f"\n=== {lbl}: buy-only long vs tier-universe (raw monthly) ===")
    print(f"  months with buy-signal: {tot}, positive-active months: {pos}/{tot} ({pos/tot:.0%})")
    print(f"  mean active {m*1e4:+.0f}bps  NW-t {t:+.2f}  n {n}")
    print(f"  avg buy names/mo: {df.n_buy.mean():.1f}  (median {df.n_buy.median():.0f})")

# sign-only rank-IC in MEGA (robust to amount outliers): use sign(exec_net) as signal
print("\n=== MEGA sign-only signal (buy=+1/sell=-1) vs fwd return ===")
p = panel[panel.tier == "MEGA"].copy()
p["sgn"] = np.sign(p.exec_net)
ics = []
for ym, g in p.groupby("ym"):
    if g.sgn.nunique() < 2 or len(g) < 3: continue
    ics.append(np.corrcoef(g.sgn, g.F1.rank())[0, 1])
ics = np.array([x for x in ics if np.isfinite(x)])
m, t, n = nw_t(ics)
print(f"  sign-IC mean {m:+.4f} NW-t {t:+.2f} n_months {n}")

# recent-only MEGA (2024-03+) buy-only
print("\n=== MEGA recent-only 2024-03+ ===")
pr = panel[(panel.tier == "MEGA") & (panel.ym >= "2024-01")]
ur = univ[(univ.tier == "MEGA") & (univ.ym >= "2024-01")]
la = []
for ym in sorted(pr.ym.unique()):
    g = pr[pr.ym == ym]; ug = ur[ur.ym == ym]
    buy = g[g.exec_net > 0]
    if len(buy) >= 1 and len(ug) >= 5:
        la.append(buy.F1.mean() - ug.F1.mean())
la = np.array(la); m, t, n = nw_t(la)
print(f"  recent MEGA buy-active mean {m*1e4:+.0f}bps NW-t {t:+.2f} n {n} pos {int((la>0).sum())}/{len(la)}")
