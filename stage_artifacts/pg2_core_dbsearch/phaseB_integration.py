"""
PG2 core DB-wide search — Phase B: core-INTEGRATION book-marginal.

For each Phase-A candidate: blend score_eff + w*direction*Z_factor (add) at w in {0.25,0.5,1.0}.
Measure (proxy): full & recent 2021+ PORT_t of the integrated core, paired-NW-t vs base core.
The question the 7f battery never asked: does an ORTHOGONAL DB factor lift the core in 2021+?
Base = score_eff alone. metric_type=proxy (survivors go to canonical + book-marginal).
"""
import pandas as pd, numpy as np, json, os, warnings
warnings.filterwarnings("ignore"); import pyarrow.parquet as pq
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE=ROOT+"/.cache"
OUT=ROOT+"/stage_artifacts/pg2_core_dbsearch"; PANEL=CACHE+"/discovery/explore_panel.parquet"
RECENT_LO="2021-01"; TOP_N=25

reg=json.load(open(ROOT+"/02_Infrastructure/factor_db/factor_registry.json",encoding="utf-8"))
panel=pd.read_parquet(PANEL)
cand=pd.read_csv(OUT+"/phaseB_candidates.csv")
dirn={f:(-1.0 if reg.get(f,{}).get("direction")=="lower_better" else 1.0) for f in cand["factor"]}

bm=pq.read_table(CACHE+"/benchmark.parquet").to_pandas()
bc=[c for c in ("BM_Ret","Ret") if c in bm.columns][0]
bm["ym"]=pd.to_datetime(bm["Date"]).dt.strftime("%Y-%m"); bm=bm.dropna(subset=[bc])
bmlr=bm.groupby("ym")[bc].apply(lambda r:np.log1p(r).sum()); bmidx=list(bmlr.index)
def bm_fwd1(t):
    if t not in bmidx: return np.nan
    i=bmidx.index(t); return np.expm1(bmlr.iloc[i+1:i+2].sum()) if i+2<=len(bmidx) else np.nan
def nw_t(x,lag=3):
    x=x[~np.isnan(x)]; n=len(x)
    if n<5: return np.nan
    e=x-x.mean(); s=(e@e)/n
    for l in range(1,lag+1): s+=2*(1-l/(lag+1))*((e[l:]@e[:-l])/n)
    return x.mean()/np.sqrt(s/n) if s>0 else np.nan

months=sorted(panel["ym"].unique()); OOS=months[60:]
ymarr=panel["ym"].values; tk=panel["Ticker"].values; F1=panel["F1"].values
bmv={t:bm_fwd1(t) for t in OOS}
def active_series(sig,lo=None,hi=None):
    out={}; prev=set()
    for t in OOS:
        if lo and t<lo: continue
        if hi and t>hi: continue
        te=np.where(ymarr==t)[0]
        if len(te)<TOP_N: continue
        s=sig[te]; ok=~np.isnan(s)
        if ok.sum()<TOP_N: continue
        idx=te[ok][np.argpartition(-s[ok],min(TOP_N,ok.sum()-1))[:TOP_N]]; sel=set(tk[idx])
        gross=np.nanmean(F1[idx]); to=2*(TOP_N-len(sel&prev))/TOP_N if prev else 1.0
        b=bmv.get(t,np.nan)
        if not np.isnan(gross) and not np.isnan(b): out[t]=(gross-to*0.0015)-b
        prev=sel
    return out

# z-standardize a signal cross-sectionally per month for fair add-blend
def zcs(col):
    d=panel[["ym"]].copy(); d["v"]=col
    return d.groupby("ym")["v"].transform(lambda s:(s-s.mean())/(s.std()+1e-9)).values
core_z=zcs(panel["score_eff"].values)
base=active_series(core_z); base_s=pd.Series(base)
base_rec=active_series(core_z,lo=RECENT_LO)
base_full_t=nw_t(np.array(list(base.values()))); base_rec_t=nw_t(np.array(list(base_rec.values())))
print(f"[base core-z] full PORT_t={base_full_t:.2f} (n={len(base)}) | recent PORT_t={base_rec_t:.2f} (n={len(base_rec)})")

rows=[]
for _,c in cand.iterrows():
    f=c["factor"]; fz=zcs(panel[f].values)*dirn[f]
    for w in (0.25,0.5,1.0):
        sig=np.nan_to_num(core_z,nan=0.0)+w*np.nan_to_num(fz,nan=0.0)
        full=active_series(sig); rec=active_series(sig,lo=RECENT_LO)
        if len(full)<24 or len(rec)<12: continue
        full_arr=np.array(list(full.values())); rec_arr=np.array(list(rec.values()))
        # paired NW-t of (integrated - base) full-period active
        fs=pd.Series(full); common=base_s.index.intersection(fs.index)
        paired=nw_t((fs[common]-base_s[common]).values) if len(common)>12 else np.nan
        rows.append({"factor":f,"category":c["category"],"w":w,
                     "full_PORT_t":round(nw_t(full_arr),2),"recent_PORT_t":round(nw_t(rec_arr),2),
                     "d_full_t":round(nw_t(full_arr)-base_full_t,2),"d_recent_t":round(nw_t(rec_arr)-base_rec_t,2),
                     "paired_NWt_vs_base":round(paired,2) if not np.isnan(paired) else np.nan,
                     "cor_vs_core":c["active_cor_vs_core"]})
res=pd.DataFrame(rows).sort_values("d_recent_t",ascending=False)
res.to_csv(OUT+"/phaseB_integration_proxy.csv",index=False)
print(f"\n=== INTEGRATION proxy: {len(res)} (factor x w) ===")
print(f"base recent PORT_t={base_rec_t:.2f}")
print("\n--- top 20 by d_recent_t (recent-regime lift over base core) ---")
print(res.head(20).to_string(index=False))
# survivors: recent lift AND full not-worse AND paired positive
surv=res[(res["d_recent_t"]>0.3)&(res["d_full_t"]>=-0.2)&(res["paired_NWt_vs_base"]>0)]
surv=surv.sort_values("d_recent_t",ascending=False)
print(f"\n--- SURVIVORS (d_recent_t>0.3 & d_full_t>=-0.2 & paired>0): {len(surv)} ---")
print(surv.to_string(index=False))
json.dump({"base_full_t":round(base_full_t,2),"base_rec_t":round(base_rec_t,2),
           "survivors":surv.to_dict("records")},open(OUT+"/phaseB_survivors.json","w"),indent=2)
print("\n[done] -> phaseB_integration_proxy.csv + phaseB_survivors.json")
