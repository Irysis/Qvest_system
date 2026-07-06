"""build_captier_panel.py — INSIDER cap-tier ESCAPE test data build (ANALYSIS ONLY).
Q-Lead findings-driven. Writes ONLY to stage_artifacts/insider_captier_escape/.
Reads (read-only): insider_trades_clean.parquet (recent, signed amounts),
insider_backfill/*.csv (2005-06, signed amounts), RAWDATA.parquet (Size/K200/KQ150/Ret).

Builds exec-only monthly net-buy signal (PIT t-1: signal known at month-end t → forward return t+1),
merges PIT market cap → cap-tier (MEGA top-10 / MID 11-30 / large top-50 / rest, ranked WITHIN
K200∪KQ150 universe each month), and cross-sectional forward-return panel.

Sign convention (verified): sp_stock_lmp_irds_cnt / qty_change signed = +buy/-sell (share count).
Exec filter: registered+unregistered officer (등기/비등기임원), EXCLUDE major-shareholder (주요주주,
10%이상주주, 사실상지배주주 = pension/holding noise).
NO prod(1+r)/cumprod self-synthesis — panel only; active t computed via NW-adjusted mean/OLS.
"""
import os, glob, numpy as np, pandas as pd, pyarrow.parquet as pq
R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/stage_artifacts/insider_captier_escape"
os.makedirs(OUT, exist_ok=True)


def num(x):
    s = str(x).replace(",", "").strip()
    if s in ("-", "", "nan", "None", "NA"):
        return np.nan
    try:
        return float(s)
    except Exception:
        return np.nan


# ---------------------------------------------------------------------------
# 1) EXEC net-buy signal (firm-month, signed share amount) from all sources
# ---------------------------------------------------------------------------
recs = []

# 1a) recent clean parquet (2024-03~2026-03)
d = pd.read_parquet(R + "/.cache/dart/insider_trades_clean.parquet")
d["irds"] = d["sp_stock_lmp_irds_cnt"].map(num)
d["Date"] = pd.to_datetime(d["Date"], errors="coerce")
# exec = has officer position AND not major-shareholder-only
d["is_exec"] = (d["isu_exctv_ofcps"].astype(str).str.len() > 1)
d["is_major"] = d["isu_main_shrholdr"].astype(str).isin(["10%이상주주", "사실상지배주주"])
# officer test: keep officer rows, drop rows that are ONLY major-shareholder
ex = d[d.is_exec & ~d.is_major & d.irds.notna() & (d.irds != 0)].copy()
ex["ym"] = ex.Date.dt.to_period("M").astype(str)
ex["src"] = "clean"
recs.append(ex[["Ticker", "ym", "irds", "src"]])

# 1b) backfill CSVs (2005-2006 + any complete months) — richer format
for f in sorted(glob.glob(R + "/.cache/dart/insider_backfill/*.csv")):
    try:
        b = pd.read_csv(f, dtype=str)
    except Exception:
        continue
    if "qty_change" not in b.columns or len(b) == 0:
        continue
    b["irds"] = b["qty_change"].map(num)
    isoff = b["is_officer"].astype(str).str.upper().eq("TRUE")
    ismaj = b["is_major_holder"].astype(str).str.upper().eq("TRUE")
    # exec-only: officer TRUE and not major-holder
    bb = b[isoff & ~ismaj].copy()
    bb = bb[bb.irds.notna() & (bb.irds != 0)]
    # ticker: backfill has corp_code not Ticker — map via universe
    bb["Ticker"] = "A" + bb["corp_code"].astype(str).str.zfill(6)
    bb["ym"] = bb["ym"].astype(str).str.replace(r"^(\d{4})(\d{2})$", r"\1-\2", regex=True)
    bb["src"] = "backfill"
    if len(bb):
        recs.append(bb[["Ticker", "ym", "irds", "src"]])

sig_raw = pd.concat(recs, ignore_index=True)
# firm-month net-buy = sum of signed officer share changes
exec_sig = sig_raw.groupby(["Ticker", "ym"], as_index=False).agg(
    exec_net=("irds", "sum"), n_reports=("irds", "size"))
exec_sig["src"] = sig_raw.groupby(["Ticker", "ym"])["src"].agg(lambda s: s.iloc[0]).values
print(f"[signal] {len(sig_raw)} officer reports -> {len(exec_sig)} firm-months "
      f"({exec_sig.ym.min()}~{exec_sig.ym.max()}, {exec_sig.ym.nunique()} distinct mo)")

# ---------------------------------------------------------------------------
# 2) RAWDATA: monthly return + PIT market cap + universe (K200∪KQ150)
# ---------------------------------------------------------------------------
rd = pq.read_table(R + "/.cache/RAWDATA.parquet",
                   columns=["Date", "Ticker", "Ret", "Size", "K200", "KQ150", "Close"]).to_pandas()
rd["Date"] = pd.to_datetime(rd["Date"])
rd["ym"] = rd.Date.dt.to_period("M").astype(str)
rd["lr"] = np.log1p(rd.Ret.clip(-0.99))
# monthly: compound log-ret, last Size (PIT mcap = end-of-month t, known at decision), last universe flags
m = (rd.groupby(["Ticker", "ym"])
     .agg(lr=("lr", "sum"), Size=("Size", "last"),
          K200=("K200", "last"), KQ150=("KQ150", "last"))
     .reset_index().sort_values(["Ticker", "ym"]))
m["mret"] = np.expm1(m.lr)
m["F1"] = m.groupby("Ticker")["mret"].shift(-1)  # forward next-month return
m["univ"] = (m.K200.fillna(0) > 0) | (m.KQ150.fillna(0) > 0)

# PIT cap-tier: rank by Size WITHIN universe each month (descending; rank 1 = largest)
mu = m[m.univ & m.Size.notna() & (m.Size > 0)].copy()
mu["cap_rank"] = mu.groupby("ym")["Size"].rank(ascending=False, method="first")
def tier(r):
    if r <= 10:  return "MEGA"       # top-10
    if r <= 30:  return "MID"        # 11-30
    if r <= 50:  return "LARGE50"    # top-50 (11-50 = large ex-mega for a clean partition; see also 'top50' overlap)
    return "REST"
mu["tier"] = mu.cap_rank.map(tier)

# ---------------------------------------------------------------------------
# 3) merge signal with universe/forward-return/tier
# ---------------------------------------------------------------------------
panel = exec_sig.merge(mu[["Ticker", "ym", "F1", "Size", "cap_rank", "tier", "mret"]],
                       on=["Ticker", "ym"], how="inner").dropna(subset=["F1"])
panel.to_parquet(OUT + "/exec_captier_panel.parquet", index=False)
print(f"[panel] {len(panel)} signal-months in universe with fwd-return "
      f"({panel.ym.min()}~{panel.ym.max()}, {panel.ym.nunique()} mo)")

# also save the FULL universe monthly (for benchmark / cross-sec IC denominators)
mu[["Ticker", "ym", "F1", "Size", "cap_rank", "tier", "mret", "univ"]].to_parquet(
    OUT + "/universe_monthly.parquet", index=False)
print("[saved] exec_captier_panel.parquet, universe_monthly.parquet")

# quick coverage print
cov = panel.groupby("ym").size()
print(f"[coverage] payers/month: mean {cov.mean():.1f} median {cov.median():.0f} "
      f"min {cov.min()} max {cov.max()}")
