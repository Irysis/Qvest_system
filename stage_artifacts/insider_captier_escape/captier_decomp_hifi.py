"""captier_decomp_hifi.py — cross-check cap-tier decomp on parallel session's HIGH-FIDELITY
insider_netbuy_monthly.parquet (net_qty_officer, 100% elestock-parity, 2005-09 continuous +
scattered). READ-ONLY of their data/. Writes only to our stage_artifacts dir.
Independent robustness of the cap-tier escape verdict using a cleaner officer-net-qty field.
"""
import numpy as np, pandas as pd
R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/stage_artifacts/insider_captier_escape"
B = R + "/stage_artifacts/dart_parser_build"

hf = pd.read_parquet(B + "/data/insider_netbuy_monthly.parquet")
# use officer-only net qty; signal known at sig_month end -> forward return from usable base
hf = hf.rename(columns={"sig_month": "ym"})
hf["exec_net"] = pd.to_numeric(hf["net_qty_officer"], errors="coerce")
hf = hf[hf.exec_net.notna() & (hf.exec_net != 0)][["Ticker", "ym", "exec_net"]]

univ = pd.read_parquet(OUT + "/universe_monthly.parquet")
panel = hf.merge(univ[["Ticker", "ym", "F1", "Size", "cap_rank", "tier"]],
                 on=["Ticker", "ym"], how="inner").dropna(subset=["F1"])
print(f"[hifi panel] {len(panel)} signal-months, {panel.ym.nunique()} mo ({panel.ym.min()}~{panel.ym.max()})")


def nw_t(x, lag=3):
    x = np.asarray(x, float); x = x[~np.isnan(x)]; n = len(x)
    if n < 4: return np.nan, np.nan, n
    mu = x.mean(); e = x - mu; g0 = (e @ e) / n; s = g0
    for k in range(1, min(lag, n - 1) + 1):
        s += 2 * (1 - k / (lag + 1)) * (e[k:] @ e[:-k]) / n
    return mu, mu / np.sqrt(max(s, 1e-18) / n), n


def tier_stats(tiers, label, P, U):
    p = P[P.tier.isin(tiers)]; u = U[U.tier.isin(tiers)]
    ics, act_long, act_buy = [], [], []
    for ym in sorted(p.ym.unique()):
        g = p[p.ym == ym]; ug = u[u.ym == ym]
        if len(g) < 3 or g.exec_net.std() == 0: continue
        ic = np.corrcoef(g.exec_net.rank(), g.F1.rank())[0, 1]
        if np.isfinite(ic): ics.append(ic)
        buy = g[g.exec_net > 0]; sell = g[g.exec_net < 0]
        if len(buy) >= 2 and len(ug) >= 5: act_long.append(buy.F1.mean() - ug.F1.mean())
        if len(buy) >= 2 and len(sell) >= 2: act_buy.append(buy.F1.mean() - sell.F1.mean())
    ics = np.array(ics)
    ic_m, ic_t, ic_n = nw_t(ics)
    al_m, al_t, al_n = nw_t(np.array(act_long))
    ab_m, ab_t, ab_n = nw_t(np.array(act_buy))
    return {"tier": label, "n_fm": len(p), "ic_n": ic_n, "ic_mean": ic_m, "ic_t": ic_t,
            "long_n": al_n, "long_active_bps": al_m * 1e4 if np.isfinite(al_m) else np.nan, "long_t": al_t,
            "buysell_n": ab_n, "buysell_bps": ab_m * 1e4 if np.isfinite(ab_m) else np.nan, "buysell_t": ab_t}


tiers_def = {
    "MEGA (top-10)": ["MEGA"], "MID (11-30)": ["MID"], "LARGE (11-50)": ["MID", "LARGE50"],
    "BIGCAP (top-50)": ["MEGA", "MID", "LARGE50"], "REST (>50)": ["REST"],
    "ALL": ["MEGA", "MID", "LARGE50", "REST"]}
res = pd.DataFrame([tier_stats(t, lbl, panel, univ) for lbl, t in tiers_def.items()])
pd.set_option("display.width", 200, "display.max_columns", 30)
print("\n=== HIGH-FIDELITY (parallel session net_qty_officer) cap-tier decomp ===")
print(res.to_string(index=False))
res.to_csv(OUT + "/captier_decomp_hifi.csv", index=False)
print("\ncoverage by tier (hifi):")
print(panel.groupby("tier").agg(fm=("Ticker", "size"), mo=("ym", "nunique")).to_string())
