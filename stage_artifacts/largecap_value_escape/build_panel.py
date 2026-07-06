"""build_panel.py — Large-cap VALUE escape probe: PIT-clean monthly panel.
Q-Lead findings-driven (motivated by WT-D20260706_012: value-in-mega rank-IC t=3.67).
Writes ONLY to stage_artifacts/largecap_value_escape/.

Reads (read-only): .cache/RAWDATA.parquet (Date,Ticker,Ret,Size,K200,KQ150,Close,Vol,BM_Ret).
Builds monthly PIT panel:
  - ym, sig_date (month-end t = decision date)
  - F1 = next-month (t+1) realized return  (forward, PIT-safe)
  - mcap = Size at month-end t (PIT: known at decision)
  - cap_rank = descending Size rank WITHIN K200∪KQ150 universe each month (1 = largest)
  - adv20 = 20-trading-day avg (Close*Vol) up to and INCLUDING sig_date (t-1 relative to held month t+1)
  - in_k200/in_kq150 = index membership flags at month-end t
Universe = K200∪KQ150. Sample = 2009-06 .. 2026-06 (verified fwd-return window).
NO prod(1+r)/cumprod self-synthesis of any performance series — panel + fwd returns only.
Monthly return = compounded daily log-returns within month (data prep, not a strategy NAV).
"""
import os, numpy as np, pandas as pd, pyarrow.parquet as pq
import warnings; warnings.filterwarnings('ignore')

R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/stage_artifacts/largecap_value_escape"
os.makedirs(OUT, exist_ok=True)

rd = pq.read_table(R + "/.cache/RAWDATA.parquet",
                   columns=["Date","Ticker","Ret","Size","K200","KQ150","Close","Vol","BM_Ret"]).to_pandas()
rd["Date"] = pd.to_datetime(rd["Date"])
rd = rd.sort_values(["Ticker","Date"])
rd["ym"] = rd.Date.dt.to_period("M").astype(str)

# ---- daily trading value + 20d rolling avg (per ticker), t-1 PIT ----
rd["tval"] = rd.Close.astype(float) * rd.Vol.astype(float)
rd["adv20"] = rd.groupby("Ticker")["tval"].transform(lambda s: s.rolling(20, min_periods=10).mean())

# ---- monthly aggregation: month-end row values (last), monthly compounded return ----
rd["Ret_c"] = rd.Ret.clip(-0.99, 5.0)
rd["lr"] = np.log1p(rd.Ret_c)
g = rd.groupby(["Ticker","ym"])
m = g.agg(
    sig_date=("Date","last"),
    lr=("lr","sum"),
    Size=("Size","last"),
    K200=("K200","last"),
    KQ150=("KQ150","last"),
    adv20=("adv20","last"),   # 20d ADV as of month-end (t-1 wrt next month held)
).reset_index().sort_values(["Ticker","ym"])
m["mret"] = np.expm1(m.lr)
m["F1"] = m.groupby("Ticker")["mret"].shift(-1)   # forward next-month realized return

# ---- universe + PIT cap-rank ----
m["in_k200"]  = (m.K200.fillna(0)  > 0).astype(int)
m["in_kq150"] = (m.KQ150.fillna(0) > 0).astype(int)
m["univ"] = (m.in_k200 == 1) | (m.in_kq150 == 1)

mu = m[m.univ & m.Size.notna() & (m.Size > 0)].copy()
mu["cap_rank"] = mu.groupby("ym")["Size"].rank(ascending=False, method="first").astype(int)

# ---- restrict sample to verified forward-return window ----
mu = mu[(mu.ym >= "2009-06") & (mu.ym <= "2026-06")].copy()

# keep only rows with forward return available (drop last month per ticker)
panel = mu.dropna(subset=["F1"]).copy()
keep = ["Ticker","ym","sig_date","F1","Size","cap_rank","adv20","in_k200","in_kq150"]
panel = panel[keep].rename(columns={"Size":"mcap"})
panel["sig_date"] = pd.to_datetime(panel["sig_date"]).dt.strftime("%Y-%m-%d")

panel.to_parquet(OUT + "/panel_returns.parquet", index=False)

# ---- benchmark: canonical BM_Ret (verified == benchmark.parquet, cap-w KOSPI200 TR) ----
bm = rd.dropna(subset=["BM_Ret"]).groupby(["Date"]).BM_Ret.first().reset_index()
bm["ym"] = bm.Date.dt.to_period("M").astype(str)
bm["lr"] = np.log1p(bm.BM_Ret.clip(-0.99, 5.0))
bmm = bm.groupby("ym").agg(BM_Ret=("lr", lambda s: np.expm1(s.sum())),
                           sig_date=("Date","last")).reset_index()
bmm = bmm[(bmm.ym >= "2009-06") & (bmm.ym <= "2026-06")].copy()
bmm["sig_date"] = pd.to_datetime(bmm["sig_date"]).dt.strftime("%Y-%m-%d")
bmm[["ym","sig_date","BM_Ret"]].to_parquet(OUT + "/benchmark_monthly.parquet", index=False)

# ---- diagnostics ----
cnt = panel.groupby("ym").size()
print(f"[panel] {len(panel)} rows, {panel.ym.nunique()} months {panel.ym.min()}..{panel.ym.max()}")
print(f"[universe/mo] mean {cnt.mean():.0f} min {cnt.min()} max {cnt.max()}")
top50 = panel[panel.cap_rank<=50].groupby("ym").size()
top100 = panel[panel.cap_rank<=100].groupby("ym").size()
print(f"[top50 avail/mo]  mean {top50.mean():.1f} min {top50.min()}  (need >=25)")
print(f"[top100 avail/mo] mean {top100.mean():.1f} min {top100.min()} (need >=25)")
print(f"[benchmark] {len(bmm)} months, mean BM_Ret {bmm.BM_Ret.mean()*100:.3f}%/mo")
# avg mcap by cutoff (KRW trillion)
for c,lab in [(50,'top50'),(100,'top100'),(10**9,'full')]:
    sub = panel[panel.cap_rank<=c]
    print(f"[avg mcap {lab}] {sub.mcap.mean()/1e12:.2f} T KRW")
