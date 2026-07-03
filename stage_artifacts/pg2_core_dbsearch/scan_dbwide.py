"""
PG2 core DB-wide search — Phase A: per-factor core-complementary scan (327 DB factors).

Frame (NEW vs prior 7f battery): NOT standalone strength. Core-complementary:
  (a) active-basis orthogonal to incumbent core (score_eff) top-N portfolio active return, cor<0.3
  (b) recent 2021+ PORT_t positive (where core is decayed)
Both -> candidate for core-integration (Phase B).

metric_type: proxy (EW top-N + inline 15bps, NW lag-3 t). Decision numbers = canonical (Phase B).
selection_type: sweep (327-factor enumeration) -> DSR/placebo/seed in meta.
PIT: pre-C13 Z * registry direction (aligned at read). score@month-end(t), F1=fwd month(t+1).
"""
import pandas as pd, numpy as np, json, os, warnings
warnings.filterwarnings("ignore")
import pyarrow.parquet as pq

ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE=ROOT+"/.cache"; OUT=ROOT+"/stage_artifacts/pg2_core_dbsearch"
PANEL=CACHE+"/discovery/explore_panel.parquet"
RECENT_LO="2021-01"; TOP_N=25
os.makedirs(OUT,exist_ok=True)

reg=json.load(open(ROOT+"/02_Infrastructure/factor_db/factor_registry.json",encoding="utf-8"))
panel=pd.read_parquet(PANEL)
meta=set(['ym','Ticker','score_eff','fwd_ret_1m','Size','F1','F3','F6','F12'])
facs=[c for c in panel.columns if c not in meta]
dirn={f: (-1.0 if reg.get(f,{}).get("direction")=="lower_better" else 1.0) for f in facs}
cat={f: reg.get(f,{}).get("category","other") for f in facs}

# ---- benchmark forward map (F1 aligned) ----
bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas()
bc=[c for c in ("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m")
bm=bm.dropna(subset=[bc])
bmlr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum())
bmidx=list(bmlr.index)
def bm_fwd1(t):
    if t not in bmidx: return np.nan
    i=bmidx.index(t)
    return np.expm1(bmlr.iloc[i+1:i+2].sum()) if i+2<=len(bmidx) else np.nan

def nw_t(x,lag=3):
    x=x[~np.isnan(x)]; n=len(x)
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1):
        s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n) if s>0 else np.nan

# ---- monthly top-N active return series for a signal (proxy, EW, 15bps, non-overlap H=1) ----
months=sorted(panel["ym"].unique()); midx={m:i for i,m in enumerate(months)}
OOS=months[60:]  # 2010+ (same as discovery_explore backtest)
ymarr=panel["ym"].values; tk=panel["Ticker"].values; F1=panel["F1"].values
bmv={t:bm_fwd1(t) for t in OOS}

def active_series(sig, lo=None, hi=None):
    """returns dict ym->active(net-bm) for monthly top-N EW. proxy."""
    out={}; prev=set()
    for t in OOS:
        if lo and t<lo: continue
        if hi and t>hi: continue
        te=np.where(ymarr==t)[0]
        if len(te)<TOP_N: continue
        s=sig[te]; ok=~np.isnan(s)
        if ok.sum()<TOP_N: continue
        idx=te[ok][np.argpartition(-s[ok],min(TOP_N,ok.sum()-1))[:TOP_N]]
        sel=set(tk[idx])
        gross=np.nanmean(F1[idx]); to=2*(TOP_N-len(sel&prev))/TOP_N if prev else 1.0
        b=bmv.get(t,np.nan)
        if not np.isnan(gross) and not np.isnan(b):
            out[t]=(gross-to*0.0015)-b
        prev=sel
    return out

def szpct(sig):
    sz=panel["Size"].values; szp=[]
    for t in OOS:
        te=np.where(ymarr==t)[0]
        if len(te)<TOP_N: continue
        s=sig[te]; ok=~np.isnan(s)
        if ok.sum()<TOP_N: continue
        idx=te[ok][np.argpartition(-s[ok],min(TOP_N,ok.sum()-1))[:TOP_N]]
        allsz=sz[te]
        szp.append(np.nanmean([(allsz<x).mean() for x in sz[idx] if not np.isnan(x)]))
    return round(np.nanmean(szp),3) if szp else np.nan

# ---- incumbent core active series (reference for orthogonality) ----
core_sig=panel["score_eff"].values
core_full=active_series(core_sig)
core_rec=active_series(core_sig,lo=RECENT_LO)
core_full_s=pd.Series(core_full)
print(f"[ref] core full n={len(core_full)} PORT_t={nw_t(np.array(list(core_full.values()))):.2f} | recent n={len(core_rec)} PORT_t={nw_t(np.array(list(core_rec.values()))):.2f}")

# ---- per-factor scan ----
rows=[]
for f in facs:
    sig=(panel[f].values)*dirn[f]  # C13 direction-align at read
    if np.isnan(sig).mean()>0.5:
        continue
    full=active_series(sig); rec=active_series(sig,lo=RECENT_LO)
    if len(full)<24 or len(rec)<12: continue
    full_arr=np.array(list(full.values())); rec_arr=np.array(list(rec.values()))
    # active-basis correlation vs core (aligned months)
    fs=pd.Series(full)
    common=core_full_s.index.intersection(fs.index)
    acor=core_full_s[common].corr(fs[common]) if len(common)>12 else np.nan
    rows.append({
        "factor":f,"category":cat[f],
        "full_PORT_t":round(nw_t(full_arr),2),"full_IR":round(full_arr.mean()/full_arr.std()*np.sqrt(12),3) if full_arr.std()>0 else np.nan,
        "recent_PORT_t":round(nw_t(rec_arr),2),"recent_IR":round(rec_arr.mean()/rec_arr.std()*np.sqrt(12),3) if rec_arr.std()>0 else np.nan,
        "active_cor_vs_core":round(acor,3) if not np.isnan(acor) else np.nan,
        "szPct":szpct(sig),"n_full":len(full),"n_recent":len(rec),
    })
res=pd.DataFrame(rows)
# core-complementary filter: orthogonal (|cor|<0.3) AND recent 2021+ positive PORT_t (>0)
res["complement"]=(res["active_cor_vs_core"].abs()<0.30)&(res["recent_PORT_t"]>0)
res["strong_complement"]=(res["active_cor_vs_core"].abs()<0.30)&(res["recent_PORT_t"]>=1.5)
res=res.sort_values(["strong_complement","recent_PORT_t"],ascending=False)
res.to_csv(OUT+"/scan_perfactor.csv",index=False)
print(f"\n=== SCAN: {len(res)} factors scanned ===")
print(f"orthogonal(|cor|<0.30) & recent PORT_t>0: {res['complement'].sum()}")
print(f"strong (& recent PORT_t>=1.5): {res['strong_complement'].sum()}")
print("\n--- top 25 by recent_PORT_t among orthogonal ---")
orth=res[res["active_cor_vs_core"].abs()<0.30].sort_values("recent_PORT_t",ascending=False)
print(orth.head(25)[["factor","category","full_PORT_t","recent_PORT_t","active_cor_vs_core","szPct"]].to_string(index=False))
print("\n--- strong_complement list ---")
sc=res[res["strong_complement"]]
print(sc[["factor","category","full_PORT_t","recent_PORT_t","active_cor_vs_core","szPct"]].to_string(index=False))

# save the strong-complement candidate list for Phase B
json.dump({"strong_complement":sc["factor"].tolist(),
           "orthogonal_positive":res[res["complement"]]["factor"].tolist(),
           "core_ref":{"full_PORT_t":round(nw_t(np.array(list(core_full.values()))),2),
                       "recent_PORT_t":round(nw_t(np.array(list(core_rec.values()))),2)},
           "n_scanned":len(res),"top_n":TOP_N,"recent_lo":RECENT_LO},
          open(OUT+"/scan_candidates.json","w"),indent=2)
print("\n[done] -> scan_perfactor.csv + scan_candidates.json")
